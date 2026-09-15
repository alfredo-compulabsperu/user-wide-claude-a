#!/usr/bin/env bats
#
# sync.sh directory-hash behaviour.
#
# dir_sha256() must depend only on each file's path RELATIVE to the directory
# root plus its content — never on the directory's absolute location. The repo
# copy and the ~/.claude copy of an artifact always live at different absolute
# paths, so an absolute-path-sensitive hash can never report [OK] for a
# directory, even when the two copies are byte-identical.

SYNC_SH="${BATS_TEST_DIRNAME}/../sync.sh"
SYNC_STATE_SH="${BATS_TEST_DIRNAME}/../.claude/scripts/sync-state.sh"

setup() {
  REPO="${BATS_TEST_TMPDIR}/repo"
  TEST_HOME="${BATS_TEST_TMPDIR}/home"

  mkdir -p "$REPO/.claude/scripts"
  mkdir -p "$TEST_HOME/.claude/skills"

  cp "$SYNC_SH" "$REPO/sync.sh"
  cp "$SYNC_STATE_SH" "$REPO/.claude/scripts/sync-state.sh"

  cat > "$REPO/manifest.yaml" <<'MANIFEST'
version: 1
idempotency: skip

skills:
  - name: demo
MANIFEST
}

# Create the repo-side and home-side copies of skill "demo".
# $1 = content written to SKILL.md on the repo side
# $2 = content written to SKILL.md on the home side
make_skill() {
  mkdir -p "$REPO/.claude/skills/demo" "$TEST_HOME/.claude/skills/demo"
  printf '%s' "$1" > "$REPO/.claude/skills/demo/SKILL.md"
  printf '%s' "$2" > "$TEST_HOME/.claude/skills/demo/SKILL.md"
}

run_sync() {
  run env HOME="$TEST_HOME" bash "$REPO/sync.sh" --dry-run
}

@test "byte-identical skill directory reports [OK]" {
  make_skill "same content" "same content"
  run_sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"*"skills/demo"* ]]
}

@test "differing skill directory is still reported as changed" {
  make_skill "repo content" "home content is different"
  run_sync
  [ "$status" -eq 0 ]
  [[ "$output" != *"[OK]"*"skills/demo"* ]]
  [[ "$output" == *"skills/demo"* ]]
}

@test "same bytes under a different filename counts as changed" {
  mkdir -p "$REPO/.claude/skills/demo" "$TEST_HOME/.claude/skills/demo"
  printf 'shared bytes' > "$REPO/.claude/skills/demo/SKILL.md"
  printf 'shared bytes' > "$TEST_HOME/.claude/skills/demo/OTHER.md"
  run_sync
  [ "$status" -eq 0 ]
  [[ "$output" != *"[OK]"*"skills/demo"* ]]
}

@test "two empty skill directories report [OK]" {
  mkdir -p "$REPO/.claude/skills/demo" "$TEST_HOME/.claude/skills/demo"
  run_sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"*"skills/demo"* ]]
}

@test "nested files are hashed by their relative path" {
  mkdir -p "$REPO/.claude/skills/demo/evals" "$TEST_HOME/.claude/skills/demo/evals"
  printf 'top' > "$REPO/.claude/skills/demo/SKILL.md"
  printf 'top' > "$TEST_HOME/.claude/skills/demo/SKILL.md"
  printf 'nested' > "$REPO/.claude/skills/demo/evals/evals.json"
  printf 'nested' > "$TEST_HOME/.claude/skills/demo/evals/evals.json"
  run_sync
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]"*"skills/demo"* ]]
}
