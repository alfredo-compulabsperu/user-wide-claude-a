#!/usr/bin/env bash
# vm-cleanup.sh -- scan and clean dev VM disk consumers
#
# Classification:
#   SAFE  auto-executes in --clean mode (low risk, recoverable)
#   RISKY skipped in --clean mode unless --risky is also passed
#
# Protected files (never deleted; at any depth):
#   .env  .env.*  *.local.json  serviceAccountKey*  *.pem  *.key  *secret*  *credential*
# When a removable worktree contains protected files, they are moved to
# ~/.claude/cleanup-rescue/<worktree>-<timestamp>/ before the worktree is removed.
#
# Usage:
#   vm-cleanup.sh                scan only; print targets with sizes
#   vm-cleanup.sh --dry-run      same as scan only, explicit alias; overrides --clean/--risky
#   vm-cleanup.sh --clean        execute SAFE; list RISKY targets (skipped)
#   vm-cleanup.sh --clean --risky  execute SAFE + RISKY

set -euo pipefail

CLEAN=false
RISKY=false
DRYRUN=false

for arg in "$@"; do
  case "$arg" in
    --clean)   CLEAN=true ;;
    --risky)   RISKY=true ;;
    --dry-run) DRYRUN=true ;;
    -h|--help)
      sed -n '/^# Usage/,/^[^#]/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; exit 1 ;;
  esac
done

$DRYRUN && CLEAN=false

# ── terminal colors (disabled when not a tty) ─────────────────────────────────
if [[ -t 1 ]]; then
  R='\033[0;31m' Y='\033[1;33m' G='\033[0;32m' B='\033[1m' N='\033[0m'
else
  R='' Y='' G='' B='' N=''
fi

TOTAL_BYTES=0

_section() { printf "\n${B}=== %s ===${N}\n" "$1"; }
_bytes()   { du -sb "$1" 2>/dev/null | cut -f1 || echo 0; }
_human()   { du -sh "$1" 2>/dev/null | cut -f1 || echo "?"; }
_add()     { TOTAL_BYTES=$(( TOTAL_BYTES + $(_bytes "$1") )); }

_safe() {
  local desc="$1"; shift
  printf "  ${G}[SAFE]${N}    %s\n" "$desc"
  $CLEAN && { "$@" 2>&1 | sed 's/^/    /' || true; }
  return 0
}

_confirm() {
  local desc="$1"; shift
  if $CLEAN && $RISKY; then
    printf "  ${Y}[RISKY]${N} %s\n" "$desc"
    "$@" 2>&1 | sed 's/^/    /' || true
  elif $CLEAN; then
    printf "  ${Y}[RISKY]${N} ${R}(skipped -- rerun with --risky)${N} %s\n" "$desc"
  else
    printf "  ${Y}[RISKY]${N} %s\n" "$desc"
  fi
  return 0
}

_skip() { printf "  ${R}[SKIP]${N}    %s\n" "$1"; }

# Single source of truth for the protected-name predicates; used by both the
# detection probe and the rescue pass so they can never disagree on depth or
# name list again (issue #36).
PROTECTED_EXPR=(
  -name ".env" -o -name ".env.*" -o -name "*.local.json"
  -o -name "serviceAccountKey*" -o -name "*.pem" -o -name "*.key"
  -o -name "*secret*" -o -name "*credential*"
)

_has_protected() {
  find "$1" \( "${PROTECTED_EXPR[@]}" \) -print -quit 2>/dev/null | grep -q .
}

# The worktree this script itself is running from -- never touched by ANY
# section, even if clean, locked, or otherwise eligible. Deleting the caller's
# own checkout mid-session is never a "SAFE"/"CONFIRM" cleanup, it's active
# data loss. Resolved once, up here, because sections 9 and 10 both need it.
SELF_WORKTREE=$(git rev-parse --show-toplevel 2>/dev/null || true)

# _tree_is_active <dir> -- returns 0 when <dir> sits inside a git working tree
# that someone is plausibly mid-work in: the caller's own checkout, a tree
# locked via `git worktree lock`, or one with uncommitted changes. Returns 1
# otherwise, including when <dir> is not inside a git tree at all.
#
# Deliberately a SUBSET of section 10's seven guards, and the difference is
# intentional. Section 10 additionally refuses trees with no upstream or with
# unpushed commits, because removing a worktree destroys commits that exist
# nowhere else. node_modules is gitignored and regenerable, so commit
# reachability says nothing about whether deleting it is safe -- the only
# question is whether someone is actively working in that tree. Two different
# consequences, so two different predicates.
_tree_is_active() {
  local dir="$1" top gitdir status
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1

  [[ -n "$SELF_WORKTREE" && "$top" == "$SELF_WORKTREE" ]] && return 0

  # `git worktree lock` writes a `locked` file into that worktree's git dir.
  # Checking the file directly avoids parsing `worktree list --porcelain`,
  # whose whitespace-split output mangles paths containing spaces.
  gitdir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  [[ -f "$gitdir/locked" ]] && return 0

  # Unreadable status means we cannot prove the tree is idle -- treat as active.
  status=$(git -C "$dir" status --porcelain 2>/dev/null) || return 0
  [[ -n "$status" ]] && return 0

  return 1
}

# Move every protected file/dir out of the worktree into a timestamped rescue
# dir (preserving worktree-relative paths), then unregister the worktree.
# --force is required (rescuing the files makes the tree dirty to git) and
# safe: eligibility gates — unlocked, clean, pushed, not self — already passed.
_rescue_and_remove_worktree() {
  local wt="$1" repo="$2"
  local rescue f rel
  rescue="$HOME/.claude/cleanup-rescue/$(basename "$wt")-$(date +%Y%m%d-%H%M%S)"
  while IFS= read -r -d '' f; do
    rel="${f#"$wt"/}"
    # A failed rescue MUST abort before the removal below — _confirm's
    # `|| true` context suppresses set -e inside this function.
    if ! mkdir -p "$rescue/$(dirname "$rel")" || ! mv "$f" "$rescue/$rel"; then
      echo "rescue FAILED for ${f} -- aborting, worktree left in place"
      return 1
    fi
  done < <(find "$wt" -mindepth 1 \( "${PROTECTED_EXPR[@]}" \) -prune -print0 2>/dev/null)
  echo "protected files rescued to: $rescue"
  git -C "$repo" worktree remove --force "$wt"
}

# ── 1. disk overview ──────────────────────────────────────────────────────────
_section "Disk overview"
df -h /

# ── 2. apt ────────────────────────────────────────────────────────────────────
_section "apt caches"
if command -v apt-get &>/dev/null; then
  APT_SZ=$(_human /var/cache/apt/archives/)
  echo "  /var/cache/apt/archives: ${APT_SZ}"
  _safe    "apt-get autoremove --purge -y"  sudo apt-get autoremove --purge -y -q
  _safe    "apt-get clean"                   sudo apt-get clean
else
  echo "  apt not found"
fi

# ── 3. journald ───────────────────────────────────────────────────────────────
_section "journald logs"
if command -v journalctl &>/dev/null; then
  J_SZ=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.]+ [A-Z]+' | tail -1 || echo "?")
  echo "  current usage: ${J_SZ}"
  _safe "journalctl --vacuum-size=50M" sudo journalctl --vacuum-size=50M
else
  echo "  journalctl not found"
fi

# ── 4. snap disabled revisions ────────────────────────────────────────────────
_section "snap disabled revisions"
if command -v snap &>/dev/null; then
  DISABLED=$(snap list --all 2>/dev/null | awk '/disabled/{print $1, $3}' || true)
  if [[ -n "$DISABLED" ]]; then
    while read -r name rev; do
      echo "  snap ${name} rev ${rev}"
      _confirm "snap remove ${name} --revision=${rev}" \
        sudo snap remove "$name" --revision="$rev"
    done <<< "$DISABLED"
  else
    echo "  none"
  fi
else
  echo "  snap not installed"
fi

# ── 5. npm cache ──────────────────────────────────────────────────────────────
_section "npm cache"
if command -v npm &>/dev/null; then
  NPM_CACHE=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
  if [[ -d "$NPM_CACHE" ]]; then
    SZ=$(_human "$NPM_CACHE")
    echo "  ${NPM_CACHE}: ${SZ}"
    _add "$NPM_CACHE"
    _safe "npm cache clean --force" npm cache clean --force
  else
    echo "  cache dir not found (${NPM_CACHE})"
  fi
else
  echo "  npm not found"
fi

# ── 6. ~/.cache safe subdirs ──────────────────────────────────────────────────
_section "~/.cache (safe subdirs)"
for subdir in thumbnails fontconfig pip; do
  target="$HOME/.cache/$subdir"
  [[ -d "$target" ]] || continue
  SZ=$(_human "$target")
  echo "  ~/.cache/${subdir}: ${SZ}"
  _add "$target"
  _safe "rm -rf ~/.cache/${subdir}" rm -rf "$target"
done

# ── 7. firebase emulator cache ────────────────────────────────────────────────
_section "~/.cache/firebase/emulators"
FB_CACHE="$HOME/.cache/firebase/emulators"
if [[ -d "$FB_CACHE" ]]; then
  SZ=$(_human "$FB_CACHE")
  echo "  ${FB_CACHE}: ${SZ}"
  _add "$FB_CACHE"
  _confirm "rm -rf ~/.cache/firebase/emulators" rm -rf "$FB_CACHE"
else
  echo "  not present"
fi

# ── 8. Trash ──────────────────────────────────────────────────────────────────
_section "Trash"
TRASH="$HOME/.local/share/Trash"
if [[ -d "$TRASH" ]]; then
  SZ=$(_human "$TRASH")
  echo "  Trash: ${SZ}"
  _add "$TRASH"
  _confirm "empty Trash" bash -c "rm -rf '${TRASH}/files/'* '${TRASH}/info/'* 2>/dev/null; true"
else
  echo "  not present"
fi

# ── 9. node_modules ───────────────────────────────────────────────────────────
_section "node_modules"
while IFS= read -r nm; do
  if [[ -L "$nm" ]]; then
    _skip "symlink: ${nm}"
    continue
  fi
  # Honour the same "someone is working here" signal section 10 respects.
  # Without this, a dirty or locked worktree -- which section 10 explicitly
  # refuses to remove -- still had its node_modules deleted out from under it.
  if _tree_is_active "$(dirname "$nm")"; then
    _skip "active git tree (current/locked/dirty): ${nm}"
    continue
  fi
  SZ=$(_human "$nm")
  echo "  ${nm}: ${SZ}"
  _add "$nm"
  _confirm "rm -rf ${nm}" rm -rf "$nm"
done < <(find "$HOME" \
  \( -path "$HOME/.nvm" -o -path "$HOME/.cache" -o -path "$HOME/.local" -o -path "$HOME/.vscode-server" \) -prune \
  -o -name "node_modules" -maxdepth 6 -prune -print \
  2>/dev/null | sort)

# ── 10. git worktrees ─────────────────────────────────────────────────────────
_section "git worktrees"

# SELF_WORKTREE is resolved near the top, alongside _tree_is_active, because
# section 9 needs it too.

# Find main repos (where .git is a directory, not a file)
while IFS= read -r git_dir; do
  repo=$(dirname "$git_dir")
  [[ "$repo" == */.nvm/* || "$repo" == */.cache/* || "$repo" == */node_modules/* ]] && continue

  # Parse `worktree list --porcelain` into path<TAB>locked pairs so a
  # `locked` worktree is never treated as eligible for cleanup.
  while IFS=$'\t' read -r wt is_locked; do
    [[ -z "$wt" ]] && continue
    [[ "$wt" == "$repo" ]] && continue  # skip the main worktree itself

    if [[ -n "$SELF_WORKTREE" && "$wt" == "$SELF_WORKTREE" ]]; then
      _skip "current worktree (never touch the caller's own checkout): ${wt}"
      continue
    fi

    if [[ "$is_locked" == "1" ]]; then
      _skip "locked worktree (git worktree lock): ${wt}"
      continue
    fi

    STATUS=$(git -C "$wt" status --porcelain 2>/dev/null || echo "GIT_ERROR")
    if [[ "$STATUS" == "GIT_ERROR" ]]; then
      _skip "cannot read status: ${wt}"
      continue
    fi
    if [[ -n "$STATUS" ]]; then
      _skip "dirty (uncommitted changes): ${wt}"
      continue
    fi

    UPSTREAM=$(git -C "$wt" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
    if [[ -z "$UPSTREAM" ]]; then
      _skip "no upstream tracking branch (possibly never pushed): ${wt}"
      continue
    fi
    AHEAD=$(git -C "$wt" rev-list --count '@{u}..HEAD' 2>/dev/null || echo "?")
    if [[ "$AHEAD" != "0" ]]; then
      _skip "ahead of upstream by ${AHEAD} commit(s) (possible unpushed work): ${wt}"
      continue
    fi

    SZ=$(_human "$wt")
    echo "  ${wt}: ${SZ}"
    _add "$wt"

    if _has_protected "$wt"; then
      _confirm "rescue protected files + git worktree remove (protected files present): ${wt}" \
        _rescue_and_remove_worktree "$wt" "$repo"
    else
      _confirm "git worktree remove ${wt}" \
        bash -c "git -C '${repo}' worktree remove '${wt}'"
    fi
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { if (path != "") print path "\t" (locked ? "1" : "0"); path=$2; locked=0; next }
    /^locked/    { locked=1; next }
    END          { if (path != "") print path "\t" (locked ? "1" : "0") }
  ')

done < <(find "$HOME" \
  \( -path "$HOME/.nvm" -o -path "$HOME/.cache" \) -prune \
  -o -name ".git" -maxdepth 5 -type d -print \
  2>/dev/null)

# ── 11. nvm node versions ─────────────────────────────────────────────────────
_section "nvm node versions"
NVM_DIR="$HOME/.nvm/versions/node"
if [[ -d "$NVM_DIR" ]]; then
  ACTIVE_NODE=$(node -v 2>/dev/null || true)
  while IFS= read -r ver; do
    SZ=$(_human "${NVM_DIR}/${ver}")
    if [[ -n "$ACTIVE_NODE" && "$ver" == "$ACTIVE_NODE" ]]; then
      printf "  nvm %-12s %s  ${G}(active -- skip)${N}\n" "$ver" "$SZ"
      continue
    fi
    printf "  nvm %-12s %s\n" "$ver" "$SZ"
    _add "${NVM_DIR}/${ver}"
    _confirm "nvm uninstall ${ver}" \
      bash -c "source '$HOME/.nvm/nvm.sh' && nvm uninstall '${ver}'"
  done < <(ls "$NVM_DIR" | sort -V)
else
  echo "  nvm not found"
fi

# ── summary ───────────────────────────────────────────────────────────────────
_section "Summary"
df -h /
RECLAIMABLE=$(numfmt --to=iec-i --suffix=B "$TOTAL_BYTES" 2>/dev/null || echo "${TOTAL_BYTES} bytes")
printf "  Estimated reclaimable (enumerated targets): %s\n" "$RECLAIMABLE"

if ! $CLEAN; then
  printf "\n  ${Y}Scan complete.${N}\n"
  printf "  Run with ${B}--clean${N} to execute SAFE actions (apt, journald, npm cache, ~/.cache subdirs).\n"
  printf "  Run with ${B}--clean --risky${N} to also execute RISKY actions (node_modules, worktrees, Trash, etc).\n"
elif ! $RISKY; then
  printf "\n  ${Y}SAFE actions executed. RISKY targets were listed but skipped.${N}\n"
  printf "  Rerun with ${B}--clean --risky${N} to execute RISKY targets.\n"
fi
