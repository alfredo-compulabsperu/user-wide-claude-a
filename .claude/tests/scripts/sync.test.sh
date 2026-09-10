#!/usr/bin/env bash
# sync.test.sh — integration tests for sync.sh's three-way divergence detection
# Exits 0 if all tests pass, 1 if any test fails.
#
# Builds a scratch repo (copy of sync.sh + sync-state.sh + a scratch
# manifest.yaml) and runs it with HOME pointed at a mktemp -d sandbox, so the
# real ~/.claude/ is never touched.

set -euo pipefail

REAL_REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SYNC_SH="$REAL_REPO_DIR/sync.sh"
SYNC_STATE_SH="$REAL_REPO_DIR/.claude/scripts/sync-state.sh"

pass=0
fail=0

run_test() {
  local name="$1"
  local result="$2"
  if [[ "$result" == "pass" ]]; then
    echo "PASS: $name"
    (( pass++ )) || true
  else
    echo "FAIL: $name"
    (( fail++ )) || true
  fi
}

SCRATCH_REPO=""
SANDBOX_HOME=""

cleanup_sandbox() {
  [[ -n "${SCRATCH_REPO:-}" ]] && rm -rf "$SCRATCH_REPO"
  [[ -n "${SANDBOX_HOME:-}" ]] && rm -rf "$SANDBOX_HOME"
  SCRATCH_REPO=""
  SANDBOX_HOME=""
}
trap cleanup_sandbox EXIT

# setup_sandbox <script|skill>: fresh scratch repo + fresh sandbox HOME.
# Manifest tracks exactly one artifact of the given kind, so every test run
# needs at most one interactive prompt (avoids piped-answer ambiguity across
# two overwrite prompts in a single invocation).
setup_sandbox() {
  local kind="$1"
  SCRATCH_REPO="$(mktemp -d)"
  SANDBOX_HOME="$(mktemp -d)"
  # Pre-create the usual ~/.claude/ subdirectories, matching a machine that's
  # already run sync.sh before (install_dir's fresh-install path expects its
  # parent dir to pre-exist — cp -rp won't create intermediate directories).
  mkdir -p "$SANDBOX_HOME/.claude"/{skills,commands,agents,scripts,output-styles}
  mkdir -p "$SCRATCH_REPO/.claude/scripts"
  cp "$SYNC_SH" "$SCRATCH_REPO/sync.sh"
  cp "$SYNC_STATE_SH" "$SCRATCH_REPO/.claude/scripts/sync-state.sh"
  chmod +x "$SCRATCH_REPO/sync.sh" "$SCRATCH_REPO/.claude/scripts/sync-state.sh"

  if [[ "$kind" == "script" ]]; then
    echo "v1" > "$SCRATCH_REPO/.claude/scripts/myscript.sh"
    cat > "$SCRATCH_REPO/manifest.yaml" <<'EOF'
idempotency: skip
skills: []
commands: []
agents: []
scripts:
  - name: myscript.sh
    executable: false
output_styles: []
plugins: []
claude_md:
  portable: false
EOF
  else
    mkdir -p "$SCRATCH_REPO/.claude/skills/myskill"
    echo "v1" > "$SCRATCH_REPO/.claude/skills/myskill/SKILL.md"
    cat > "$SCRATCH_REPO/manifest.yaml" <<'EOF'
idempotency: skip
skills:
  - name: myskill
commands: []
agents: []
scripts: []
output_styles: []
plugins: []
claude_md:
  portable: false
EOF
  fi
}

# run_sync <answer> [sync.sh args...]: pipe <answer>\n as the overwrite-prompt
# reply (empty string == just pressing Enter, i.e. decline) and run the
# scratch sync.sh with HOME pointed at the sandbox.
run_sync() {
  local answer="$1"; shift
  printf '%s\n' "$answer" | HOME="$SANDBOX_HOME" bash "$SCRATCH_REPO/sync.sh" "$@"
}

get_baseline() {
  HOME="$SANDBOX_HOME" bash "$SCRATCH_REPO/.claude/scripts/sync-state.sh" get "$1"
}

# git_init_branch <branch>: makes $SCRATCH_REPO an actual git repo checked
# out on <branch>, for exercising the branch guard (setup_sandbox alone
# leaves it a plain non-git directory, which the guard intentionally ignores).
# An initial commit is required: on an unborn branch (zero commits), `git
# rev-parse --abbrev-ref HEAD` prints the literal string "HEAD" to stdout
# while still failing — a real repo always has commits, so this only bites
# a freshly-`init`ed sandbox.
git_init_branch() {
  git -C "$SCRATCH_REPO" init -q -b "$1"
  git -C "$SCRATCH_REPO" -c user.email=test@test -c user.name=test \
    commit -q --allow-empty -m init
}

sha256_of() {
  sha256sum "$1" | cut -c1-64
}

# setup_diverged_script: fresh script sandbox, one real sync (baseline
# recorded), then an out-of-band hand-edit of the destination so it now
# differs from the recorded baseline while the source is untouched.
setup_diverged_script() {
  setup_sandbox script
  run_sync '' >/dev/null 2>&1 || true
  echo "hand-edited" > "$SANDBOX_HOME/.claude/scripts/myscript.sh"
}

# ---------------------------------------------------------------------------
# Test 1: bash -n syntax check
# ---------------------------------------------------------------------------
if bash -n "$SYNC_SH" 2>/dev/null; then
  run_test "bash -n syntax check" "pass"
else
  run_test "bash -n syntax check" "fail"
fi

# ---------------------------------------------------------------------------
# Test 2: fresh install records baseline
# ---------------------------------------------------------------------------
setup_sandbox script
src="$SCRATCH_REPO/.claude/scripts/myscript.sh"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
run_sync '' >/dev/null 2>&1 || true
baseline="$(get_baseline 'scripts/myscript.sh')"
if [[ -f "$dest" ]] && [[ "$(cat "$dest")" == "$(cat "$src")" ]] && [[ "$baseline" == "$(sha256_of "$src")" ]]; then
  run_test "fresh install records baseline" "pass"
else
  echo "  dest=$(cat "$dest" 2>/dev/null || echo '<missing>') baseline=[$baseline]"
  run_test "fresh install records baseline" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 3: ordinary drift, no baseline yet → --force overwrites (not diverged)
# ---------------------------------------------------------------------------
setup_sandbox script
src="$SCRATCH_REPO/.claude/scripts/myscript.sh"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
mkdir -p "$(dirname "$dest")"
echo "manually-created" > "$dest"
out="$(run_sync '' --force)" || true
if [[ "$(cat "$dest")" == "v1" ]] && ! grep -q '\[DIVERGED\]' <<< "$out"; then
  run_test "ordinary drift, no baseline → --force overwrites (not diverged)" "pass"
else
  echo "$out"
  run_test "ordinary drift, no baseline → --force overwrites (not diverged)" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 4: ordinary drift, baseline == dest → --force overwrites (not diverged)
# ---------------------------------------------------------------------------
setup_sandbox script
src="$SCRATCH_REPO/.claude/scripts/myscript.sh"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
run_sync '' >/dev/null 2>&1 || true
echo "v2" > "$src"
out="$(run_sync '' --force)" || true
if [[ "$(cat "$dest")" == "v2" ]] && ! grep -q '\[DIVERGED\]' <<< "$out"; then
  run_test "ordinary drift, baseline==dest → --force overwrites (not diverged)" "pass"
else
  echo "$out"
  run_test "ordinary drift, baseline==dest → --force overwrites (not diverged)" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 5: diverged file — dry-run reports [DIVERGED], writes nothing
# ---------------------------------------------------------------------------
setup_diverged_script
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
out="$(run_sync '' --dry-run)" || true
if grep -q '\[DIVERGED\]' <<< "$out" && [[ "$(cat "$dest")" == "hand-edited" ]]; then
  run_test "diverged file: dry-run reports [DIVERGED], no write" "pass"
else
  echo "$out"
  run_test "diverged file: dry-run reports [DIVERGED], no write" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 6: diverged file — plain --force does NOT overwrite
# ---------------------------------------------------------------------------
setup_diverged_script
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
out="$(run_sync '' --force)" || true
if [[ "$(cat "$dest")" == "hand-edited" ]] && ! grep -q '\[UPDATED\]' <<< "$out"; then
  run_test "diverged file: plain --force does NOT overwrite" "pass"
else
  echo "$out"
  run_test "diverged file: plain --force does NOT overwrite" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 7: diverged file — --force-diverged does overwrite
# ---------------------------------------------------------------------------
setup_diverged_script
src="$SCRATCH_REPO/.claude/scripts/myscript.sh"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
out="$(run_sync '' --force-diverged)" || true
if [[ "$(cat "$dest")" == "$(cat "$src")" ]] && grep -q '\[UPDATED\]' <<< "$out"; then
  run_test "diverged file: --force-diverged overwrites" "pass"
else
  echo "$out"
  run_test "diverged file: --force-diverged overwrites" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 8: diverged file — declining the prompt (empty answer) leaves the
# file untouched and reports [SKIPPED]
# ---------------------------------------------------------------------------
setup_diverged_script
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
out="$(run_sync '')" || true
if [[ "$(cat "$dest")" == "hand-edited" ]] && grep -q '\[SKIPPED\]' <<< "$out"; then
  run_test "diverged file: declining prompt leaves file untouched, reports [SKIPPED]" "pass"
else
  echo "$out"
  run_test "diverged file: declining prompt leaves file untouched, reports [SKIPPED]" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 9: diverged directory — plain --force does NOT overwrite (parity with
# install_file's divergence branch)
# ---------------------------------------------------------------------------
setup_sandbox skill
src="$SCRATCH_REPO/.claude/skills/myskill"
dest="$SANDBOX_HOME/.claude/skills/myskill"
run_sync '' >/dev/null 2>&1 || true
echo "hand-edited" > "$dest/SKILL.md"
out="$(run_sync '' --force)" || true
if [[ "$(cat "$dest/SKILL.md")" == "hand-edited" ]] && ! grep -q '\[UPDATED\]' <<< "$out"; then
  run_test "diverged dir: plain --force does NOT overwrite" "pass"
else
  echo "$out"
  run_test "diverged dir: plain --force does NOT overwrite" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 10: diverged directory — --force-diverged does overwrite
# ---------------------------------------------------------------------------
setup_sandbox skill
src="$SCRATCH_REPO/.claude/skills/myskill"
dest="$SANDBOX_HOME/.claude/skills/myskill"
run_sync '' >/dev/null 2>&1 || true
echo "hand-edited" > "$dest/SKILL.md"
out="$(run_sync '' --force-diverged)" || true
if [[ "$(cat "$dest/SKILL.md")" == "$(cat "$src/SKILL.md")" ]] && grep -q '\[UPDATED\]' <<< "$out"; then
  run_test "diverged dir: --force-diverged overwrites" "pass"
else
  echo "$out"
  run_test "diverged dir: --force-diverged overwrites" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 11: branch guard — refuses a real sync from a feature branch
# ---------------------------------------------------------------------------
setup_sandbox script
git_init_branch "worktree-some-feature"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
out="$(run_sync '' 2>&1)" && rc=0 || rc=$?
if [[ $rc -ne 0 ]] && grep -q 'refusing to sync' <<< "$out" && [[ ! -f "$dest" ]]; then
  run_test "branch guard: refuses real sync from a feature branch" "pass"
else
  echo "  rc=$rc"
  echo "$out"
  run_test "branch guard: refuses real sync from a feature branch" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 12: branch guard — allows a real sync from develop
# ---------------------------------------------------------------------------
setup_sandbox script
git_init_branch "develop"
src="$SCRATCH_REPO/.claude/scripts/myscript.sh"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
out="$(run_sync '')" || true
if [[ -f "$dest" ]] && [[ "$(cat "$dest")" == "$(cat "$src")" ]]; then
  run_test "branch guard: allows real sync from develop" "pass"
else
  echo "$out"
  run_test "branch guard: allows real sync from develop" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 13: branch guard — --allow-branch overrides the refusal
# ---------------------------------------------------------------------------
setup_sandbox script
git_init_branch "worktree-some-feature"
src="$SCRATCH_REPO/.claude/scripts/myscript.sh"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
out="$(run_sync '' --allow-branch 2>&1)" || true
if [[ -f "$dest" ]] && [[ "$(cat "$dest")" == "$(cat "$src")" ]] && grep -q 'allow-branch override' <<< "$out"; then
  run_test "branch guard: --allow-branch overrides refusal" "pass"
else
  echo "$out"
  run_test "branch guard: --allow-branch overrides refusal" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 14: branch guard — --dry-run is exempt on a feature branch
# ---------------------------------------------------------------------------
setup_sandbox script
git_init_branch "worktree-some-feature"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
out="$(run_sync '' --dry-run)" && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && ! grep -q 'refusing to sync' <<< "$out" && [[ ! -f "$dest" ]]; then
  run_test "branch guard: --dry-run exempt from guard on a feature branch" "pass"
else
  echo "  rc=$rc"
  echo "$out"
  run_test "branch guard: --dry-run exempt from guard on a feature branch" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${pass} passed, ${fail} failed"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
exit 0
