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

echo
if [[ $FAIL -eq 0 ]]; then
  echo "RESULT: GREEN (all assertions passed)"
else
  echo "RESULT: RED (see $SANDBOX/run.log)"
fi
exit $FAIL
