#!/usr/bin/env bash
# Sandbox functional test for vm-cleanup.sh (issue #36, Fixes 1 & 2).
# Usage: test-vm-cleanup.sh <path-to-vm-cleanup.sh> <sandbox-root>
set -u

SCRIPT="${1:?path to vm-cleanup.sh under test}"
SANDBOX="${2:?sandbox root dir}"

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

mk_wt wt-shallow ".env"                # protected at depth 1 → Fix 1 (husk)
mk_wt wt-deep    "a/b/c/d/e/.env"      # protected at depth 6 → Fix 2 (depth cap)
mk_wt wt-locked  ".env"
git -C "$REPO" worktree lock "$HOME_DIR/projects/wt-locked"
mk_wt wt-dirty   ".env"
echo junk > "$HOME_DIR/projects/wt-dirty/junk.txt"   # untracked → dirty

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

echo
if [[ $FAIL -eq 0 ]]; then
  echo "RESULT: GREEN (all assertions passed)"
else
  echo "RESULT: RED (see $SANDBOX/run.log)"
fi
exit $FAIL
