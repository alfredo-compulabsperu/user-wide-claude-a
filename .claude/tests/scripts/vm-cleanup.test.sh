#!/usr/bin/env bash
# Sandbox functional test for vm-cleanup.sh.
#
# Covers:
#   - issue #36 Fix 1 (worktree removal leaves no husk)
#   - issue #36 Fix 2 (protection scan reaches depth 6, preserves relative path)
#   - the section 10 worktree guards (locked / dirty are never touched)
#   - section 9 (node_modules) honouring the same active-tree signal, and
#     still reclaiming node_modules from trees nobody is working in
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

OUT=$(cd "$SANDBOX" && bash "$SCRIPT" --clean --yes 2>&1)
RC=$?
printf '%s\n' "$OUT" > "$SANDBOX/run.log"

WT_LIST=$(git -C "$REPO" worktree list --porcelain)
FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

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

echo
if [[ $FAIL -eq 0 ]]; then
  echo "RESULT: GREEN (all assertions passed)"
else
  echo "RESULT: RED (see $SANDBOX/run.log)"
fi
exit $FAIL
