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
# setup_sandbox_idem <kind> <idempotency>: shared implementation behind
# setup_sandbox (always "skip", today's default) and setup_sandbox_prompt
# (idempotency: prompt, needed to exercise the ordinary-drift interactive
# branch at all -- no existing sandbox reaches it).
setup_sandbox_idem() {
  local kind="$1" idem="$2"
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
    cat > "$SCRATCH_REPO/manifest.yaml" <<EOF
idempotency: $idem
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
    cat > "$SCRATCH_REPO/manifest.yaml" <<EOF
idempotency: $idem
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

setup_sandbox() { setup_sandbox_idem "$1" skip; }
setup_sandbox_prompt() { setup_sandbox_idem "$1" prompt; }

# run_sync <answer> [sync.sh args...]: pipe <answer>\n as the overwrite-prompt
# reply (empty string == just pressing Enter, i.e. decline) and run the
# scratch sync.sh with HOME pointed at the sandbox.
run_sync() {
  local answer="$1"; shift
  printf '%s\n' "$answer" | HOME="$SANDBOX_HOME" bash "$SCRATCH_REPO/sync.sh" "$@"
}

# run_sync_noninteractive [sync.sh args...]: stdin from /dev/null, not an
# answer -- the actual proof that --skip-diff never reaches a `read`. If a
# prompt branch weren't properly gated, `read -rp` against a closed stdin
# returns immediately with an empty answer (decline), which would make a
# weaker test (one that just checks "didn't hang") pass for the wrong reason;
# these tests instead assert the [SKIPPED] label and untouched destination.
run_sync_noninteractive() {
  HOME="$SANDBOX_HOME" bash "$SCRATCH_REPO/sync.sh" "$@" < /dev/null
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
# Test 15: ordinary drift, idempotency=prompt, --skip-diff, no stdin at all
# → destination untouched, [SKIPPED] reported, exit 0 (no hang)
# ---------------------------------------------------------------------------
setup_sandbox_prompt script
src="$SCRATCH_REPO/.claude/scripts/myscript.sh"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
mkdir -p "$(dirname "$dest")"
echo "manually-created" > "$dest"
out="$(run_sync_noninteractive --skip-diff)" && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && [[ "$(cat "$dest")" == "manually-created" ]] && grep -q '\[SKIPPED\]' <<< "$out"; then
  run_test "ordinary drift + idempotency=prompt: --skip-diff skips without reading stdin" "pass"
else
  echo "  rc=$rc"; echo "$out"
  run_test "ordinary drift + idempotency=prompt: --skip-diff skips without reading stdin" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 16: same, but for a directory (skill) install
# ---------------------------------------------------------------------------
setup_sandbox_prompt skill
src="$SCRATCH_REPO/.claude/skills/myskill"
dest="$SANDBOX_HOME/.claude/skills/myskill"
mkdir -p "$dest"
echo "manually-created" > "$dest/SKILL.md"
out="$(run_sync_noninteractive --skip-diff)" && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && [[ "$(cat "$dest/SKILL.md")" == "manually-created" ]] && grep -q '\[SKIPPED\]' <<< "$out"; then
  run_test "ordinary drift + idempotency=prompt (dir): --skip-diff skips without reading stdin" "pass"
else
  echo "  rc=$rc"; echo "$out"
  run_test "ordinary drift + idempotency=prompt (dir): --skip-diff skips without reading stdin" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 17: diverged file, --skip-diff, no stdin → untouched, [SKIPPED], exit 0
# ---------------------------------------------------------------------------
setup_diverged_script
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
out="$(run_sync_noninteractive --skip-diff)" && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && [[ "$(cat "$dest")" == "hand-edited" ]] && grep -q '\[SKIPPED\]' <<< "$out"; then
  run_test "diverged file: --skip-diff skips without reading stdin" "pass"
else
  echo "  rc=$rc"; echo "$out"
  run_test "diverged file: --skip-diff skips without reading stdin" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 18: diverged directory, --skip-diff, no stdin → untouched, [SKIPPED]
# ---------------------------------------------------------------------------
setup_sandbox skill
src="$SCRATCH_REPO/.claude/skills/myskill"
dest="$SANDBOX_HOME/.claude/skills/myskill"
run_sync '' >/dev/null 2>&1 || true
echo "hand-edited" > "$dest/SKILL.md"
out="$(run_sync_noninteractive --skip-diff)" && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && [[ "$(cat "$dest/SKILL.md")" == "hand-edited" ]] && grep -q '\[SKIPPED\]' <<< "$out"; then
  run_test "diverged dir: --skip-diff skips without reading stdin" "pass"
else
  echo "  rc=$rc"; echo "$out"
  run_test "diverged dir: --skip-diff skips without reading stdin" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 19: --force still overwrites ordinary drift even with --skip-diff
# present (skip-diff must not shadow an explicit --force)
# ---------------------------------------------------------------------------
setup_sandbox_prompt script
src="$SCRATCH_REPO/.claude/scripts/myscript.sh"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
mkdir -p "$(dirname "$dest")"
echo "manually-created" > "$dest"
out="$(run_sync_noninteractive --force --skip-diff)" && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && [[ "$(cat "$dest")" == "v1" ]] && grep -q '\[UPDATED\]' <<< "$out"; then
  run_test "--force overwrites even when --skip-diff is also passed" "pass"
else
  echo "  rc=$rc"; echo "$out"
  run_test "--force overwrites even when --skip-diff is also passed" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 20: --force-diverged still overwrites a diverged file even with
# --skip-diff present
# ---------------------------------------------------------------------------
setup_diverged_script
src="$SCRATCH_REPO/.claude/scripts/myscript.sh"
dest="$SANDBOX_HOME/.claude/scripts/myscript.sh"
out="$(run_sync_noninteractive --force-diverged --skip-diff)" && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && [[ "$(cat "$dest")" == "$(cat "$src")" ]] && grep -q '\[UPDATED\]' <<< "$out"; then
  run_test "--force-diverged overwrites even when --skip-diff is also passed" "pass"
else
  echo "  rc=$rc"; echo "$out"
  run_test "--force-diverged overwrites even when --skip-diff is also passed" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 21: identical directory reports [OK] regardless of absolute location
#
# dir_sha256() must hash each file's path RELATIVE to the directory root. The
# repo copy and the ~/.claude copy always sit at different absolute paths, so
# an absolute-path-sensitive hash can never report [OK] for a directory.
# ---------------------------------------------------------------------------
setup_sandbox skill
mkdir -p "$SANDBOX_HOME/.claude/skills/myskill"
echo "v1" > "$SANDBOX_HOME/.claude/skills/myskill/SKILL.md"
out="$(run_sync '' --dry-run)" || true
if grep -q '\[OK\].*skills/myskill' <<< "$out"; then
  run_test "identical directory reports [OK] despite differing absolute paths" "pass"
else
  echo "$out"
  run_test "identical directory reports [OK] despite differing absolute paths" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 22: directory with genuinely different content is still not [OK]
# ---------------------------------------------------------------------------
setup_sandbox skill
mkdir -p "$SANDBOX_HOME/.claude/skills/myskill"
echo "different" > "$SANDBOX_HOME/.claude/skills/myskill/SKILL.md"
out="$(run_sync '' --dry-run)" || true
if ! grep -q '\[OK\].*skills/myskill' <<< "$out" && grep -q 'skills/myskill' <<< "$out"; then
  run_test "directory with different content is still reported as changed" "pass"
else
  echo "$out"
  run_test "directory with different content is still reported as changed" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 23: identical bytes under a different filename count as changed
# (layout is part of the hash, not just content)
# ---------------------------------------------------------------------------
setup_sandbox skill
mkdir -p "$SANDBOX_HOME/.claude/skills/myskill"
echo "v1" > "$SANDBOX_HOME/.claude/skills/myskill/OTHER.md"
out="$(run_sync '' --dry-run)" || true
if ! grep -q '\[OK\].*skills/myskill' <<< "$out"; then
  run_test "same bytes under a different filename counts as changed" "pass"
else
  echo "$out"
  run_test "same bytes under a different filename counts as changed" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 24: two empty directories compare equal (the 'empty-dir' branch)
# ---------------------------------------------------------------------------
setup_sandbox skill
rm -f "$SCRATCH_REPO/.claude/skills/myskill/SKILL.md"
mkdir -p "$SANDBOX_HOME/.claude/skills/myskill"
out="$(run_sync '' --dry-run)" || true
if grep -q '\[OK\].*skills/myskill' <<< "$out"; then
  run_test "two empty directories compare equal" "pass"
else
  echo "$out"
  run_test "two empty directories compare equal" "fail"
fi
cleanup_sandbox

# ---------------------------------------------------------------------------
# Test 25: nested files are hashed by relative path, so subdirectories match
# ---------------------------------------------------------------------------
setup_sandbox skill
mkdir -p "$SCRATCH_REPO/.claude/skills/myskill/evals"
echo "nested" > "$SCRATCH_REPO/.claude/skills/myskill/evals/evals.json"
mkdir -p "$SANDBOX_HOME/.claude/skills/myskill/evals"
echo "v1" > "$SANDBOX_HOME/.claude/skills/myskill/SKILL.md"
echo "nested" > "$SANDBOX_HOME/.claude/skills/myskill/evals/evals.json"
out="$(run_sync '' --dry-run)" || true
if grep -q '\[OK\].*skills/myskill' <<< "$out"; then
  run_test "nested files hashed by relative path" "pass"
else
  echo "$out"
  run_test "nested files hashed by relative path" "fail"
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
