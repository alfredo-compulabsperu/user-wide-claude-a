#!/usr/bin/env bash
# Sandbox functional test for vm-cleanup.sh.
#
# Covers:
#   - issue #36 Fix 1 (worktree removal leaves no husk)
#   - issue #36 Fix 2 (protection scan reaches depth 6, preserves relative path)
#   - the section 10 worktree guards: locked, dirty, no-upstream, ahead-of-upstream,
#     unreadable status, and the invoking worktree itself ("self") are never touched
#   - section 9 (node_modules) honouring the same active-tree signal, and
#     still reclaiming node_modules from trees nobody is working in
#   - scan mode (no flags) mutates nothing
#   - a rescue that fails aborts the removal, leaving the worktree in place
#
# Promoted from .claude/tdd/test-vm-cleanup-issue-36.sh so it runs as part of
# the standing suite. Both args are optional now.
#
# Usage: vm-cleanup.test.sh [path-to-vm-cleanup.sh] [sandbox-root]
set -u

REAL_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="${1:-$REAL_REPO_DIR/.claude/scripts/vm-cleanup.sh}"
SANDBOX="${2:-$(mktemp -d)}"

# The test cd's into $SANDBOX, so a relative SCRIPT would resolve to nothing
# (exit 127). Normalise to absolute before use.
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
[[ -f "$SCRIPT" ]] || { echo "FATAL: script under test not found: $SCRIPT"; exit 1; }

rm -rf "$SANDBOX"
mkdir -p "$SANDBOX"
HOME_DIR="$SANDBOX/home"
STUB="$SANDBOX/stub-bin"
mkdir -p "$HOME_DIR" "$STUB"

# No-op stubs so system-mutating sections do nothing real
for cmd in sudo apt-get journalctl npm snap; do
  printf '#!/bin/sh\nexit 0\n' > "$STUB/$cmd"
  chmod +x "$STUB/$cmd"
done

export HOME="$HOME_DIR"
export PATH="$STUB:$PATH"
git config --global user.email test@example.com
git config --global user.name "Sandbox Test"
git config --global init.defaultBranch main

REMOTE="$HOME_DIR/remote.git"
git init --bare -q "$REMOTE"

REPO="$HOME_DIR/projects/mainrepo"
mkdir -p "$REPO"
git -C "$REPO" init -q
echo base > "$REPO/base.txt"
# node_modules must be ignored, or planting one would itself dirty a worktree
# and mask which guard actually fired.
printf 'node_modules/\n' > "$REPO/.gitignore"
git -C "$REPO" add -A
git -C "$REPO" commit -qm base
git -C "$REPO" remote add origin "$REMOTE"
git -C "$REPO" push -qu origin main

# mk_wt <name> [protected-relpath] — clean, pushed, upstream-tracking worktree
mk_wt() {
  local name="$1" prot="${2:-}"
  local wt="$HOME_DIR/projects/$name"
  git -C "$REPO" worktree add -q "$wt" -b "$name-br"
  if [[ -n "$prot" ]]; then
    mkdir -p "$wt/$(dirname "$prot")"
    echo SECRET > "$wt/$prot"
    git -C "$wt" add -A
    git -C "$wt" commit -qm "add protected file"
  fi
  git -C "$wt" push -qu origin "$name-br"
}

# mk_node_modules <worktree-name> — plant a node_modules the section 9 scan
# will find (depth from $HOME is 3, well inside its -maxdepth 6).
mk_node_modules() {
  mkdir -p "$HOME_DIR/projects/$1/node_modules/pkg"
  echo "module.exports = {}" > "$HOME_DIR/projects/$1/node_modules/pkg/index.js"
}

mk_wt wt-shallow ".env"                # protected at depth 1 → Fix 1 (husk)
mk_wt wt-deep    "a/b/c/d/e/.env"      # protected at depth 6 → Fix 2 (depth cap)
mk_wt wt-locked  ".env"
git -C "$REPO" worktree lock "$HOME_DIR/projects/wt-locked"
mk_wt wt-dirty   ".env"
echo junk > "$HOME_DIR/projects/wt-dirty/junk.txt"   # untracked → dirty

# Section 9 fixtures: node_modules inside worktrees section 10 protects, plus
# one in an idle tree that SHOULD still be reclaimed. The main repo is used for
# the idle case because section 10 never removes it, so only section 9 acts on
# it -- isolating section 9's behaviour from worktree removal.
mk_node_modules wt-dirty
mk_node_modules wt-locked
mk_node_modules mainrepo

# ── AC1 gap fixtures: no-upstream, ahead-of-upstream, unreadable status ──────
NOUP_WT="$HOME_DIR/projects/wt-noupstream"
git -C "$REPO" worktree add -q "$NOUP_WT" -b wt-noupstream-br   # never pushed → no upstream

AHEAD_WT="$HOME_DIR/projects/wt-ahead"
git -C "$REPO" worktree add -q "$AHEAD_WT" -b wt-ahead-br
git -C "$AHEAD_WT" push -qu origin wt-ahead-br
echo more >> "$AHEAD_WT/base.txt"
git -C "$AHEAD_WT" commit -qam "local-only commit"               # ahead by 1, unpushed

UNREAD_WT="$HOME_DIR/projects/wt-unreadable"
git -C "$REPO" worktree add -q "$UNREAD_WT" -b wt-unreadable-br
git -C "$UNREAD_WT" push -qu origin wt-unreadable-br
echo "gitdir: /nonexistent/broken-gitdir" > "$UNREAD_WT/.git"     # corrupt gitfile → status errors

FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

# ── Run 1: scan mode (no flags) — AC4, must mutate nothing ───────────────────
WT_LIST_BEFORE=$(git -C "$REPO" worktree list --porcelain)
OUT_SCAN=$(cd "$SANDBOX" && bash "$SCRIPT" 2>&1)
WT_LIST_AFTER_SCAN=$(git -C "$REPO" worktree list --porcelain)

[[ "$WT_LIST_BEFORE" == "$WT_LIST_AFTER_SCAN" ]] \
  && [[ -d "$HOME_DIR/projects/wt-dirty/node_modules" ]] \
  && [[ -d "$HOME_DIR/projects/wt-locked/node_modules" ]] \
  && [[ -d "$REPO/node_modules" ]] \
  && [[ ! -d "$HOME_DIR/.claude/cleanup-rescue" ]] \
  && grep -q "Scan complete" <<<"$OUT_SCAN" \
  && pass "scan mode (no flags) mutates nothing" \
  || fail "scan mode (no flags) mutates nothing"

# ── Task 1: ~/.cache whole-dir wipe (US-VMCLEANUP-4), plain --clean (no --risky) ──
# foo/bar are arbitrary regenerable tool-cache stand-ins; thumbnails is a
# regression check (already SAFE-wiped today, must stay wiped after the
# section 6 rewrite); firebase/emulators must survive section 6 under plain
# --clean (no --risky) — only section 7 (RISKY) may ever remove it, and only
# when --risky is passed, which this run deliberately omits.
mkdir -p "$HOME_DIR/.cache/foo" "$HOME_DIR/.cache/bar" \
  "$HOME_DIR/.cache/thumbnails" "$HOME_DIR/.cache/firebase/emulators"
echo x > "$HOME_DIR/.cache/foo/f"
echo x > "$HOME_DIR/.cache/bar/f"
echo x > "$HOME_DIR/.cache/thumbnails/f"
echo x > "$HOME_DIR/.cache/firebase/emulators/f"

OUT_CACHE=$(cd "$SANDBOX" && bash "$SCRIPT" --clean 2>&1)

[[ ! -d "$HOME_DIR/.cache/foo" ]] && [[ ! -d "$HOME_DIR/.cache/bar" ]] \
  && pass "arbitrary .cache subdirs (foo/bar) are wiped" \
  || fail "arbitrary .cache subdirs (foo/bar) are wiped"

[[ ! -d "$HOME_DIR/.cache/thumbnails" ]] \
  && pass ".cache/thumbnails still wiped (regression check)" \
  || fail ".cache/thumbnails still wiped (regression check)"

[[ -f "$HOME_DIR/.cache/firebase/emulators/f" ]] \
  && pass ".cache/firebase/emulators preserved under plain --clean (no --risky)" \
  || fail ".cache/firebase/emulators preserved under plain --clean (no --risky)"

grep -q '\[SAFE\].*~/.cache/foo' <<<"$OUT_CACHE" && grep -q '\[SAFE\].*~/.cache/bar' <<<"$OUT_CACHE" \
  && pass "[SAFE] reported for .cache/foo and .cache/bar" \
  || fail "[SAFE] reported for .cache/foo and .cache/bar"

# ── Task 2: ~/.vscode-server stale-version pruning (US-VMCLEANUP-5) ─────────
# Normal case: bin/ names the current version; cli/servers/ holds the current
# (must survive), a stale Stable-* (must be pruned), and a stale .staging
# entry (must be pruned); extensions/ and data/ marker files must never be
# touched.
rm -rf "$HOME_DIR/.vscode-server"
mkdir -p "$HOME_DIR/.vscode-server/bin/hash-A" \
  "$HOME_DIR/.vscode-server/cli/servers/Stable-hash-A" \
  "$HOME_DIR/.vscode-server/cli/servers/Stable-hash-B" \
  "$HOME_DIR/.vscode-server/cli/servers/Stable-hash-C.staging" \
  "$HOME_DIR/.vscode-server/extensions" \
  "$HOME_DIR/.vscode-server/data"
echo x > "$HOME_DIR/.vscode-server/extensions/marker-file"
echo x > "$HOME_DIR/.vscode-server/data/marker-file"

OUT_VSCS=$(cd "$SANDBOX" && bash "$SCRIPT" --clean 2>&1)

[[ -d "$HOME_DIR/.vscode-server/cli/servers/Stable-hash-A" ]] \
  && pass "current .vscode-server version (Stable-hash-A) survives pruning" \
  || fail "current .vscode-server version (Stable-hash-A) survives pruning"

[[ ! -d "$HOME_DIR/.vscode-server/cli/servers/Stable-hash-B" ]] \
  && [[ ! -d "$HOME_DIR/.vscode-server/cli/servers/Stable-hash-C.staging" ]] \
  && pass "stale Stable-hash-B and .staging entry are pruned" \
  || fail "stale Stable-hash-B and .staging entry are pruned"

[[ -f "$HOME_DIR/.vscode-server/extensions/marker-file" ]] \
  && [[ -f "$HOME_DIR/.vscode-server/data/marker-file" ]] \
  && pass "extensions/ and data/ marker files untouched" \
  || fail "extensions/ and data/ marker files untouched"

grep -q '\[SAFE\].*Stable-hash-B' <<<"$OUT_VSCS" && grep -q '\[SAFE\].*Stable-hash-C.staging' <<<"$OUT_VSCS" \
  && pass "[SAFE] reported for the 2 pruned .vscode-server entries" \
  || fail "[SAFE] reported for the 2 pruned .vscode-server entries"

# Edge case: bin/ has zero entries -- pruning must skip entirely, never guess.
rm -rf "$HOME_DIR/.vscode-server"
mkdir -p "$HOME_DIR/.vscode-server/bin" "$HOME_DIR/.vscode-server/cli/servers/Stable-hash-Z"

OUT_VSCS_ZERO=$(cd "$SANDBOX" && bash "$SCRIPT" --clean 2>&1)

[[ -d "$HOME_DIR/.vscode-server/cli/servers/Stable-hash-Z" ]] \
  && pass "bin/ with 0 entries: pruning skipped, nothing under cli/servers/ touched" \
  || fail "bin/ with 0 entries: pruning skipped, nothing under cli/servers/ touched"

grep -qi "cannot identify a single current version" <<<"$OUT_VSCS_ZERO" \
  && pass "bin/ with 0 entries: skip message printed" \
  || fail "bin/ with 0 entries: skip message printed"

# Edge case: bin/ has 2+ entries -- pruning must skip entirely, never guess.
rm -rf "$HOME_DIR/.vscode-server"
mkdir -p "$HOME_DIR/.vscode-server/bin/hash-D" "$HOME_DIR/.vscode-server/bin/hash-E" \
  "$HOME_DIR/.vscode-server/cli/servers/Stable-hash-D"

OUT_VSCS_MULTI=$(cd "$SANDBOX" && bash "$SCRIPT" --clean 2>&1)

[[ -d "$HOME_DIR/.vscode-server/cli/servers/Stable-hash-D" ]] \
  && pass "bin/ with 2+ entries: pruning skipped, nothing under cli/servers/ touched" \
  || fail "bin/ with 2+ entries: pruning skipped, nothing under cli/servers/ touched"

grep -qi "cannot identify a single current version" <<<"$OUT_VSCS_MULTI" \
  && pass "bin/ with 2+ entries: skip message printed" \
  || fail "bin/ with 2+ entries: skip message printed"

# Clean sandbox state before the main run below picks up $HOME_DIR again.
rm -rf "$HOME_DIR/.vscode-server"

# ── Run 2: --clean --risky (main destructive run) ────────────────────────────
OUT=$(cd "$SANDBOX" && bash "$SCRIPT" --clean --risky 2>&1)
RC=$?
printf '%s\n' "$OUT" > "$SANDBOX/run.log"

WT_LIST=$(git -C "$REPO" worktree list --porcelain)

[[ $RC -eq 0 ]] \
  && pass "script exits 0" || fail "script exits 0 (got $RC)"

! grep -q "projects/wt-shallow" <<<"$WT_LIST" \
  && pass "wt-shallow unregistered (no husk)" || fail "wt-shallow unregistered (no husk)"

! grep -q "projects/wt-deep" <<<"$WT_LIST" \
  && pass "wt-deep unregistered" || fail "wt-deep unregistered"

compgen -G "$HOME_DIR/.claude/cleanup-rescue/wt-shallow-*/.env" >/dev/null \
  && pass "shallow .env rescued" || fail "shallow .env rescued"

compgen -G "$HOME_DIR/.claude/cleanup-rescue/wt-deep-*/a/b/c/d/e/.env" >/dev/null \
  && pass "depth-6 .env rescued preserving relative path" || fail "depth-6 .env rescued preserving relative path"

grep -q "cleanup-rescue" <<<"$OUT" \
  && pass "rescue location printed" || fail "rescue location printed"

grep -q "rescue.*wt-deep" <<<"$OUT" \
  && pass "depth-6 file routes wt-deep to protected branch" || fail "depth-6 file routes wt-deep to protected branch"

grep -q "projects/wt-locked" <<<"$WT_LIST" && [[ -f "$HOME_DIR/projects/wt-locked/.env" ]] \
  && pass "locked worktree untouched" || fail "locked worktree untouched"

grep -q "projects/wt-dirty" <<<"$WT_LIST" && [[ -f "$HOME_DIR/projects/wt-dirty/junk.txt" ]] \
  && pass "dirty worktree untouched" || fail "dirty worktree untouched"

# ── section 9 honours section 10's "active tree" signal ──────────────────────
# Section 9 scans `find "$HOME" -name node_modules -maxdepth 6` and rm -rf's
# every hit. It now calls _tree_is_active() first, so a dirty or locked
# worktree keeps its node_modules — matching section 10's posture. The third
# assertion guards the other direction: the fix must not neuter section 9 for
# trees nobody is working in.
[[ -d "$HOME_DIR/projects/wt-dirty/node_modules" ]] \
  && pass "node_modules inside a DIRTY worktree is preserved" \
  || fail "node_modules inside a DIRTY worktree is preserved"

[[ -d "$HOME_DIR/projects/wt-locked/node_modules" ]] \
  && pass "node_modules inside a LOCKED worktree is preserved" \
  || fail "node_modules inside a LOCKED worktree is preserved"

[[ ! -d "$REPO/node_modules" ]] \
  && pass "node_modules in an IDLE tree is still reclaimed" \
  || fail "node_modules in an IDLE tree is still reclaimed"

# ── AC1 gaps: no-upstream, ahead-of-upstream, unreadable status ─────────────
grep -q "projects/wt-noupstream" <<<"$WT_LIST" && grep -q "no upstream tracking branch" <<<"$OUT" \
  && pass "worktree with no upstream tracking branch is left in place" \
  || fail "worktree with no upstream tracking branch is left in place"

grep -q "projects/wt-ahead" <<<"$WT_LIST" && grep -q "ahead of upstream" <<<"$OUT" \
  && pass "worktree ahead of upstream (unpushed commits) is left in place" \
  || fail "worktree ahead of upstream (unpushed commits) is left in place"

grep -q "projects/wt-unreadable" <<<"$WT_LIST" && grep -q "cannot read status" <<<"$OUT" \
  && pass "worktree with unreadable git status is left in place" \
  || fail "worktree with unreadable git status is left in place"

# ── Run 9: AC5 — idempotency: a second identical run is a no-op, exits 0 ───
OUT2=$(cd "$SANDBOX" && bash "$SCRIPT" --clean --risky 2>&1)
RC2=$?
WT_LIST2=$(git -C "$REPO" worktree list --porcelain)

[[ $RC2 -eq 0 ]] && [[ "$WT_LIST2" == "$WT_LIST" ]] \
  && pass "a second identical --clean --risky run performs no further destructive action and exits 0" \
  || fail "a second identical --clean --risky run performs no further destructive action and exits 0"

# ── Run 3: AC3 — a rescue that fails aborts the removal ─────────────────────
# cleanup-rescue already exists after Run 2 (wt-shallow/wt-deep rescues created
# it); making it read-only forces the next mkdir -p inside it to fail without
# touching any rescue that already happened.
chmod 555 "$HOME_DIR/.claude/cleanup-rescue"
mk_wt wt-rescuefail ".env"
OUT_RESCUEFAIL=$(cd "$SANDBOX" && bash "$SCRIPT" --clean --risky 2>&1)
WT_LIST_RESCUEFAIL=$(git -C "$REPO" worktree list --porcelain)
chmod 755 "$HOME_DIR/.claude/cleanup-rescue"

grep -q "projects/wt-rescuefail" <<<"$WT_LIST_RESCUEFAIL" \
  && [[ -f "$HOME_DIR/projects/wt-rescuefail/.env" ]] \
  && grep -q "rescue FAILED" <<<"$OUT_RESCUEFAIL" \
  && pass "a rescue that fails aborts the removal (worktree left in place)" \
  || fail "a rescue that fails aborts the removal (worktree left in place)"

# Tear down explicitly so the next run doesn't depend on whether a later
# invocation happens to make the rescue succeed instead.
git -C "$REPO" worktree remove --force "$HOME_DIR/projects/wt-rescuefail" 2>/dev/null || true

# ── Run 4: AC1 — the invoking worktree itself is never touched ("self") ─────
mk_wt wt-self   # clean, pushed, no protected files -- otherwise fully eligible for plain removal
SELF_WT="$HOME_DIR/projects/wt-self"
OUT_SELF=$(cd "$SELF_WT" && bash "$SCRIPT" --clean --risky 2>&1)
WT_LIST_SELF=$(git -C "$REPO" worktree list --porcelain)

grep -q "projects/wt-self" <<<"$WT_LIST_SELF" && grep -q "current worktree" <<<"$OUT_SELF" \
  && pass "the invoking worktree itself is never removed, even though otherwise eligible" \
  || fail "the invoking worktree itself is never removed, even though otherwise eligible"

# ── Run 5: Task 2 — --risky replaces --yes; bare --yes rejected ─────────────
mk_wt wt-risky-check ".env"

OUT_OLDYES=$(cd "$SANDBOX" && bash "$SCRIPT" --clean --yes 2>&1)
RC_OLDYES=$?
[[ $RC_OLDYES -ne 0 ]] && grep -q "Unknown arg: --yes" <<<"$OUT_OLDYES" \
  && pass "bare --yes is rejected as an unknown arg" \
  || fail "bare --yes is rejected as an unknown arg"

OUT_RISKY=$(cd "$SANDBOX" && bash "$SCRIPT" --clean --risky 2>&1)
WT_LIST_AFTER_RISKY=$(git -C "$REPO" worktree list --porcelain)
! grep -q "projects/wt-risky-check" <<<"$WT_LIST_AFTER_RISKY" \
  && pass "--risky unlocks RISKY-tier actions (worktree removed)" \
  || fail "--risky unlocks RISKY-tier actions (worktree removed)"

# ── Run 6: Task 2 — bare invocation and --dry-run behave identically ────────
mk_wt wt-dryrun-check ".env"
WT_LIST_BEFORE_DRYRUN=$(git -C "$REPO" worktree list --porcelain)
OUT_BARE=$(cd "$SANDBOX" && bash "$SCRIPT" 2>&1)
WT_LIST_AFTER_BARE=$(git -C "$REPO" worktree list --porcelain)
OUT_DRYRUN=$(cd "$SANDBOX" && bash "$SCRIPT" --dry-run 2>&1)
WT_LIST_AFTER_DRYRUN=$(git -C "$REPO" worktree list --porcelain)

[[ "$WT_LIST_BEFORE_DRYRUN" == "$WT_LIST_AFTER_BARE" ]] \
  && [[ "$WT_LIST_BEFORE_DRYRUN" == "$WT_LIST_AFTER_DRYRUN" ]] \
  && [[ -f "$HOME_DIR/projects/wt-dryrun-check/.env" ]] \
  && grep -q "Scan complete" <<<"$OUT_BARE" \
  && grep -q "Scan complete" <<<"$OUT_DRYRUN" \
  && pass "bare invocation and --dry-run behave identically (both mutate nothing)" \
  || fail "bare invocation and --dry-run behave identically (both mutate nothing)"

# ── Run 7: Task 3 — --help names both tiers with an example target each ─────
OUT_HELP=$(bash "$SCRIPT" --help 2>&1)
grep -q "SAFE" <<<"$OUT_HELP" && grep -q "RISKY" <<<"$OUT_HELP" \
  && grep -qi "apt" <<<"$OUT_HELP" && grep -qi "worktree" <<<"$OUT_HELP" \
  && pass "--help names both tiers (SAFE/RISKY) with an example target each" \
  || fail "--help names both tiers (SAFE/RISKY) with an example target each"

# ── Run 8: Task 4 — a failing action causes non-zero exit + Summary entry ───
FAILSTUB="$SANDBOX/stub-bin-fail"
mkdir -p "$FAILSTUB"
printf '#!/bin/sh\nexit 1\n' > "$FAILSTUB/sudo"   # every SAFE apt/journald action goes through sudo
chmod +x "$FAILSTUB/sudo"

OUT_FAILINJECT=$(cd "$SANDBOX" && PATH="$FAILSTUB:$PATH" bash "$SCRIPT" --clean 2>&1)
RC_FAILINJECT=$?

[[ $RC_FAILINJECT -ne 0 ]] && grep -qi "Failed actions" <<<"$OUT_FAILINJECT" \
  && pass "a failing SAFE action causes non-zero exit and appears in the Summary" \
  || fail "a failing SAFE action causes non-zero exit and appears in the Summary"

# ── Run 10: section 12 — dangling process detection (synthetic ps table) ────
# A real system's own process tree can't be safely fuzzed in a test, so this
# feeds a synthetic "pid ppid comm tty" table via VMCLEANUP_PROCESSES_FILE
# instead of letting the script call the real `ps`.
FAKE_PS="$SANDBOX/fake-ps.txt"
cat > "$FAKE_PS" <<'EOF'
90001 1 bun ?
90002 90003 bun ?
90003 1 claude pts/9
90004 90005 claude ?
90005 1 claude pts/1
90006 1 claude ?
90007 1 node pts/20
EOF

WT_LIST_BEFORE_ORPHAN=$(git -C "$REPO" worktree list --porcelain)
OUT_ORPHAN=$(cd "$SANDBOX" && VMCLEANUP_PROCESSES_FILE="$FAKE_PS" bash "$SCRIPT" 2>&1)
WT_LIST_AFTER_ORPHAN=$(git -C "$REPO" worktree list --porcelain)

grep -q "Dangling Claude Code processes" <<<"$OUT_ORPHAN" \
  && pass "section 12 header present" || fail "section 12 header present"

grep -q "pid=90001" <<<"$OUT_ORPHAN" \
  && pass "orphaned bun (ppid=1, no claude ancestor, no tty) is reported" \
  || fail "orphaned bun (ppid=1, no claude ancestor, no tty) is reported"

! grep -q "pid=90002" <<<"$OUT_ORPHAN" \
  && pass "bun with a live claude ancestor (90003) is NOT reported" \
  || fail "bun with a live claude ancestor (90003) is NOT reported"

grep -q "pid=90003" <<<"$OUT_ORPHAN" \
  && pass "top-level claude with ppid=1 and a real tty is reported for review" \
  || fail "top-level claude with ppid=1 and a real tty is reported for review"

! grep -q "pid=90004" <<<"$OUT_ORPHAN" \
  && pass "fork-subagent shape (claude, tty=?, live claude parent 90005) is NOT reported" \
  || fail "fork-subagent shape (claude, tty=?, live claude parent 90005) is NOT reported"

grep -q "pid=90006.*no controlling terminal" <<<"$OUT_ORPHAN" \
  && pass "orphaned claude (ppid=1, tty=?) reported as likely leaked" \
  || fail "orphaned claude (ppid=1, tty=?) reported as likely leaked"

grep -q "pid=90007.*has a terminal" <<<"$OUT_ORPHAN" \
  && pass "orphaned node with a real tty is reported but annotated for manual verification" \
  || fail "orphaned node with a real tty is reported but annotated for manual verification"

[[ "$WT_LIST_BEFORE_ORPHAN" == "$WT_LIST_AFTER_ORPHAN" ]] \
  && pass "process review section performs no mutation of unrelated state" \
  || fail "process review section performs no mutation of unrelated state"

echo
if [[ $FAIL -eq 0 ]]; then
  echo "RESULT: GREEN (all assertions passed)"
else
  echo "RESULT: RED (see $SANDBOX/run.log)"
fi
exit $FAIL
