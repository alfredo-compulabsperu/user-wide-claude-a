#!/usr/bin/env bash
# vm-health.sh -- VM resource health check for Linux dev machines running Claude Code
#
# Usage:
#   vm-health.sh       run full health check; print findings with severity flags

set -euo pipefail

# ── terminal colors (disabled when not a tty) ─────────────────────────────────
if [[ -t 1 ]]; then
  R='\033[0;31m' Y='\033[1;33m' G='\033[0;32m' B='\033[1m' N='\033[0m'
else
  R='' Y='' G='' B='' N=''
fi

_section() { printf "\n${B}=== %s ===${N}\n" "$1"; }

ISSUES_CRITICAL=()
ISSUES_IMPORTANT=()
ISSUES_ADVISORY=()

_critical()  { ISSUES_CRITICAL+=("$1");  printf "  ${R}[CRITICAL]${N}  %s\n" "$1"; }
_important() { ISSUES_IMPORTANT+=("$1"); printf "  ${Y}[IMPORTANT]${N} %s\n" "$1"; }
_advisory()  { ISSUES_ADVISORY+=("$1");  printf "  ${B}[ADVISORY]${N}  %s\n" "$1"; }
_ok()        { printf "  ${G}[OK]${N}        %s\n" "$1"; }

# ── gather data (each expensive command runs exactly once) ────────────────────
UPTIME_STR=$(uptime -p 2>/dev/null || uptime)
read -r LOAD1 LOAD5 LOAD15 _ < /proc/loadavg
NPROC=$(nproc)

read -r RAM_TOTAL RAM_USED RAM_AVAIL SWAP_TOTAL SWAP_USED < <(
  free -b | awk '/^Mem:/{mt=$2;mu=$3;ma=$7} /^Swap:/{st=$2;su=$3} END{print mt,mu,ma,st+0,su+0}'
)
SWAP_TOTAL_H="0" SWAP_USED_H="0"
read -r RAM_TOTAL_H RAM_USED_H RAM_AVAIL_H SWAP_TOTAL_H SWAP_USED_H < <(
  free -h | awk '/^Mem:/{mt=$2;mu=$3;ma=$7} /^Swap:/{st=$2;su=$3} END{print mt,mu,ma,st,su}'
)
RAM_USED_PCT=$(( RAM_USED * 100 / RAM_TOTAL ))
SWAP_USED_PCT=0
(( SWAP_TOTAL > 0 )) && SWAP_USED_PCT=$(( SWAP_USED * 100 / SWAP_TOTAL ))

PS_RAW=$(ps aux --no-headers 2>/dev/null || true)
ZOMBIE_COUNT=$(awk '$8=="Z"{c++} END{print c+0}' <<< "$PS_RAW")

# Pre-filter virtual mounts so loops don't need to repeat the skip logic
mapfile -t DF_H_LINES < <(df -h 2>/dev/null | awk 'NR>1 && $6!~/^\/(dev|sys|proc|run)/{print}')
mapfile -t DF_I_LINES < <(df -i 2>/dev/null | awk 'NR>1 && $6!~/^\/(dev|sys|proc|run)/{print}')

DISK_PCT_MAX=0
for _line in "${DF_H_LINES[@]}"; do
  _pct=$(awk '{gsub(/%/,"",$5); print $5}' <<< "$_line")
  [[ "$_pct" =~ ^[0-9]+$ ]] || continue
  (( _pct > DISK_PCT_MAX )) && DISK_PCT_MAX=$_pct
done

J_BYTES_INT=0; J_HUMAN="?"
if command -v journalctl &>/dev/null; then
  _jdu=$(journalctl --disk-usage 2>/dev/null || echo "")
  J_HUMAN=$(grep -oP '[\d.]+ [A-Z]+' <<< "$_jdu" | tail -1 || echo "?")
  _jbytes=$(grep -oP '[0-9]+\.[0-9]+\s*(G|M)' <<< "$_jdu" | awk '{
    if ($2=="G") print int($1*1024*1024*1024)
    else if ($2=="M") print int($1*1024*1024)
    else print 0
  }' | head -1 || echo 0)
  J_BYTES_INT=${_jbytes:-0}
fi

# ── 1. VM resource overview ───────────────────────────────────────────────────
_section "VM Resource Overview"
printf "  Uptime:     %s\n" "$UPTIME_STR"
printf "  Load avg:   %s (1m)  %s (5m)  %s (15m)   [nproc=%s]\n" "$LOAD1" "$LOAD5" "$LOAD15" "$NPROC"

# CPU usage requires two /proc/stat samples separated by a sleep — unavoidable
CPU_PCT=$(awk '/^cpu / {total=0; for(i=2;i<=NF;i++) total+=$i; idle=$5; print total, idle}' /proc/stat | {
  read -r T1 I1; sleep 0.5
  awk '/^cpu / {total=0; for(i=2;i<=NF;i++) total+=$i; idle=$5; print total, idle}' /proc/stat | {
    read -r T2 I2
    dT=$(( T2 - T1 )); dI=$(( I2 - I1 ))
    (( dT > 0 )) && echo $(( (dT - dI) * 100 / dT )) || echo 0
  }
})
printf "  CPU usage:  %s%%\n" "$CPU_PCT"
printf "  RAM:        %s used / %s total (%s%%)  avail: %s\n" \
  "$RAM_USED_H" "$RAM_TOTAL_H" "$RAM_USED_PCT" "$RAM_AVAIL_H"

if (( SWAP_TOTAL > 0 )); then
  printf "  Swap:       %s used / %s total (%s%%)\n" "$SWAP_USED_H" "$SWAP_TOTAL_H" "$SWAP_USED_PCT"
else
  printf "  Swap:       none configured\n"
fi

printf "\n  Disk usage:\n"
df -h --output=target,size,used,avail,pcent 2>/dev/null | \
  awk 'NR==1{printf "    %-30s %6s %6s %6s %5s\n",$1,$2,$3,$4,$5}
       NR>1 && $1!~"^(tmpfs|devtmpfs|udev|cgroupfs|cgroup|overlay|squashfs)" \
             {printf "    %-30s %6s %6s %6s %5s\n",$1,$2,$3,$4,$5}' \
  || df -h | grep -v "^tmpfs\|^devtmpfs\|^udev\|^cgroupfs\|squashfs"

# ── 2. Claude Code processes ──────────────────────────────────────────────────
_section "Claude Code Processes"

CLAUDE_PROCS=$(awk '
  /[c]laude|[C]laude Code|claude-code|claude_code/ && !/awk/ {
    printf "  PID=%-7s CPU=%-5s MEM=%-5s RSS=%-8s %s\n",
      $2, $3, $4, $6, substr($0, index($0,$11), 100)
  }
' <<< "$PS_RAW" || true)

if [[ -n "$CLAUDE_PROCS" ]]; then
  printf "%s\n" "$CLAUDE_PROCS"
  while read -r pid rss; do
    RSS_MB=$(( rss / 1024 ))
    if (( rss >= 4194304 )); then
      _critical "Claude PID $pid RSS=${RSS_MB}MB exceeds 4GB — likely memory leak; restart recommended"
    elif (( rss >= 2097152 )); then
      _important "Claude PID $pid RSS=${RSS_MB}MB exceeds 2GB — monitor closely"
    elif (( rss >= 1048576 )); then
      _advisory "Claude PID $pid RSS=${RSS_MB}MB exceeds 1GB — normal for large sessions, watch trend"
    fi
  done < <(awk '/[c]laude|[C]laude Code|claude-code|claude_code/ && !/awk/ {print $2, $6}' <<< "$PS_RAW" || true)
else
  printf "  (no Claude Code processes found)\n"
fi

# ── 3. Top resource consumers ─────────────────────────────────────────────────
_section "Top Resource Consumers (excluding kernel threads)"

printf "\n  Top 5 by CPU%%:\n"
ps aux --no-headers --sort=-%cpu 2>/dev/null | head -5 | \
  awk '$1!="root" || $3>0 {printf "    %-8s %-7s %-5s %-5s %s\n",$1,$2,$3,$4,substr($0,index($0,$11),100)}'

printf "\n  Top 5 by MEM%%:\n"
ps aux --no-headers --sort=-%mem 2>/dev/null | head -5 | \
  awk '$1!="root" || $4>0 {printf "    %-8s %-7s %-5s %-5s %s\n",$1,$2,$3,$4,substr($0,index($0,$11),100)}'

# ── 4. Current issues ─────────────────────────────────────────────────────────
_section "Current Issues"

OOM_COUNT=0
OOM_OUTPUT=""
# journalctl -k is reliable and unprivileged on most systemd distros; dmesg as fallback
if command -v journalctl &>/dev/null; then
  OOM_OUTPUT=$(journalctl -k --no-pager -g "oom|out of memory|killed process" 2>/dev/null | grep -v "^--" | tail -5 || true)
fi
if [[ -z "$OOM_OUTPUT" ]] && command -v dmesg &>/dev/null; then
  OOM_OUTPUT=$(dmesg --time-format=reltime 2>/dev/null | grep -i "oom\|out of memory\|killed process" | tail -5 || \
               sudo dmesg 2>/dev/null | grep -i "oom\|out of memory\|killed process" | tail -5 || true)
fi
if [[ -n "$OOM_OUTPUT" ]]; then
  OOM_COUNT=$(wc -l <<< "$OOM_OUTPUT")
  _critical "OOM kills detected ($OOM_COUNT events) — processes were killed due to memory exhaustion"
  printf "%s\n" "$OOM_OUTPUT" | sed 's/^/    /'
fi

for _line in "${DF_H_LINES[@]}"; do
  _pct=$(awk '{gsub(/%/,"",$5); print $5}' <<< "$_line")
  _mnt=$(awk '{print $6}' <<< "$_line")
  [[ "$_pct" =~ ^[0-9]+$ ]] || continue
  (( _pct > 90 )) && _critical "Disk $_mnt at ${_pct}% — writes may fail imminently (run /vm-cleanup)"
done

(( RAM_USED_PCT > 90 )) && _critical "RAM at ${RAM_USED_PCT}% — system under severe memory pressure"
(( SWAP_TOTAL > 0 && SWAP_USED_PCT > 80 )) && _critical "Swap at ${SWAP_USED_PCT}% — system is swapping heavily; performance severely degraded"

LOAD1_INT=$(awk '{printf "%d", $1 * 100}' <<< "$LOAD1")
NPROC_X100=$(( NPROC * 100 ))
(( LOAD1_INT > NPROC_X100 )) && _critical "Load avg ${LOAD1} exceeds nproc=${NPROC} — CPU-bound; processes are queuing"

if (( ZOMBIE_COUNT > 5 )); then
  _important "$ZOMBIE_COUNT zombie processes — parent processes not reaping children; may indicate crashed dev tools"
elif (( ZOMBIE_COUNT > 0 )); then
  _advisory "$ZOMBIE_COUNT zombie process(es) — usually harmless but worth monitoring"
fi

for _line in "${DF_I_LINES[@]}"; do
  _pct=$(awk '{gsub(/%/,"",$5); print $5}' <<< "$_line")
  _mnt=$(awk '{print $6}' <<< "$_line")
  [[ "$_pct" =~ ^[0-9]+$ ]] || continue
  if (( _pct > 90 )); then
    _critical "Inodes on $_mnt at ${_pct}% — new file creation will fail (many small files: node_modules?)"
  elif (( _pct > 75 )); then
    _important "Inodes on $_mnt at ${_pct}% — approaching exhaustion"
  fi
done

(( ${#ISSUES_CRITICAL[@]} == 0 )) && _ok "No critical issues detected right now"

# ── 5. Potential issues ───────────────────────────────────────────────────────
_section "Potential Issues (Trending / Near Threshold)"

POTENTIAL_FOUND=false

for _line in "${DF_H_LINES[@]}"; do
  _pct=$(awk '{gsub(/%/,"",$5); print $5}' <<< "$_line")
  _mnt=$(awk '{print $6}' <<< "$_line")
  [[ "$_pct" =~ ^[0-9]+$ ]] || continue
  if (( _pct > 90 )); then
    :
  elif (( _pct > 75 )); then
    _important "Disk $_mnt at ${_pct}% — approaching full; run /vm-cleanup to reclaim space"
    POTENTIAL_FOUND=true
  elif (( _pct > 60 )); then
    _advisory "Disk $_mnt at ${_pct}% — monitor; dev builds and node_modules grow quickly"
    POTENTIAL_FOUND=true
  fi
done

if (( RAM_USED_PCT > 90 )); then
  :
elif (( RAM_USED_PCT > 75 )); then
  _important "RAM at ${RAM_USED_PCT}% — high; Claude Code sessions may OOM under load"
  POTENTIAL_FOUND=true
elif (( RAM_USED_PCT > 60 )); then
  _advisory "RAM at ${RAM_USED_PCT}% — moderate; watch if running Firebase emulators concurrently"
  POTENTIAL_FOUND=true
fi

if (( SWAP_TOTAL > 0 && SWAP_USED_PCT <= 80 && SWAP_USED_PCT > 50 )); then
  _important "Swap at ${SWAP_USED_PCT}% — system is relying on swap; performance degraded"
  POTENTIAL_FOUND=true
fi

NPROC75_X100=$(( NPROC * 75 ))
NPROC50_X100=$(( NPROC * 50 ))
if (( LOAD1_INT > NPROC_X100 )); then
  :
elif (( LOAD1_INT > NPROC75_X100 )); then
  _important "Load avg ${LOAD1} is >75% of nproc=${NPROC} — system under sustained load"
  POTENTIAL_FOUND=true
elif (( LOAD1_INT > NPROC50_X100 )); then
  _advisory "Load avg ${LOAD1} is >50% of nproc=${NPROC} — moderate load; normal for active builds"
  POTENTIAL_FOUND=true
fi

if (( J_BYTES_INT > 2147483648 )); then
  _important "systemd journal at ${J_HUMAN} — exceeds 2GB; run: sudo journalctl --vacuum-size=200M"
  POTENTIAL_FOUND=true
elif (( J_BYTES_INT > 524288000 )); then
  _advisory "systemd journal at ${J_HUMAN} — exceeds 500MB; run: sudo journalctl --vacuum-size=100M"
  POTENTIAL_FOUND=true
fi

! $POTENTIAL_FOUND && _ok "No potential issues trending toward thresholds"

# ── 6. Recommendations ────────────────────────────────────────────────────────
_section "Recommendations"

REC_COUNT=0

if (( DISK_PCT_MAX > 60 )); then
  REC_COUNT=$(( REC_COUNT + 1 ))
  printf "  %d. ${B}Free disk space:${N} /vm-cleanup --clean --yes\n" "$REC_COUNT"
fi

if command -v npm &>/dev/null; then
  NPM_CACHE="${HOME}/.npm"
  if [[ -d "$NPM_CACHE" ]]; then
    NPM_BYTES=$(du -sb "$NPM_CACHE" 2>/dev/null | cut -f1 || echo 0)
    if (( NPM_BYTES > 524288000 )); then
      REC_COUNT=$(( REC_COUNT + 1 ))
      printf "  %d. ${B}Prune npm cache (>500MB):${N} npm cache clean --force\n" "$REC_COUNT"
    fi
  fi
fi

if (( J_BYTES_INT > 524288000 )); then
  REC_COUNT=$(( REC_COUNT + 1 ))
  printf "  %d. ${B}Vacuum journal (%s):${N} sudo journalctl --vacuum-size=100M\n" "$REC_COUNT" "$J_HUMAN"
fi

if (( SWAP_TOTAL > 0 && SWAP_USED_PCT > 50 )); then
  REC_COUNT=$(( REC_COUNT + 1 ))
  printf "  %d. ${B}Reduce swap pressure:${N} identify and restart high-RSS processes (see Claude processes above)\n" "$REC_COUNT"
fi

if (( OOM_COUNT > 0 )); then
  REC_COUNT=$(( REC_COUNT + 1 ))
  printf "  %d. ${B}OOM recovery:${N} free -h && sudo dmesg | grep -i 'oom\\|killed' | tail -20\n" "$REC_COUNT"
fi

if (( RAM_USED_PCT > 75 )); then
  REC_COUNT=$(( REC_COUNT + 1 ))
  printf "  %d. ${B}Identify top RAM consumers:${N} ps aux --sort=-%mem | head -10\n" "$REC_COUNT"
fi

if (( ZOMBIE_COUNT > 0 )); then
  REC_COUNT=$(( REC_COUNT + 1 ))
  printf "  %d. ${B}Inspect zombies:${N} ps aux | awk '\$8==\"Z\"'\n" "$REC_COUNT"
fi

if command -v git &>/dev/null; then
  GC_NEEDED=false
  while IFS= read -r git_dir; do
    repo=$(dirname "$git_dir")
    if git -C "$repo" worktree list 2>/dev/null | awk 'END{exit (NR>3)?0:1}'; then
      GC_NEEDED=true; break
    fi
  done < <(find "$HOME" \( -path "$HOME/.nvm" -o -path "$HOME/.cache" \) -prune \
    -o -name ".git" -maxdepth 4 -type d -print 2>/dev/null | head -10)
  if $GC_NEEDED; then
    REC_COUNT=$(( REC_COUNT + 1 ))
    printf "  %d. ${B}Repos with many worktrees detected — run git gc:${N} git gc --prune=now\n" "$REC_COUNT"
  fi
fi

if (( REC_COUNT == 0 )); then
  printf "  ${G}System looks healthy — no immediate recommendations.${N}\n"
fi

# ── summary ───────────────────────────────────────────────────────────────────
_section "Summary"
printf "  ${R}[CRITICAL]${N}  %d issue(s)\n" "${#ISSUES_CRITICAL[@]}"
printf "  ${Y}[IMPORTANT]${N} %d issue(s)\n" "${#ISSUES_IMPORTANT[@]}"
printf "  ${B}[ADVISORY]${N}  %d item(s)\n" "${#ISSUES_ADVISORY[@]}"
printf "\n"
