#!/usr/bin/env bash
# open-claude.test.sh — integration tests for open-claude.sh
# Uses mock claude and tmux binaries in $TMPDIR/mock-bin/
# Exits 0 if all tests pass, 1 if any test fails.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/open-claude.sh"
MOCK_BIN="$(mktemp -d)"

trap 'rm -rf "$MOCK_BIN"' EXIT

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

# ---------------------------------------------------------------------------
# Mock binaries
# ---------------------------------------------------------------------------

# mock claude: records its args to $MOCK_BIN/claude.args, then exits 0
cat > "$MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/claude.args"
EOF
chmod +x "$MOCK_BIN/claude"

# mock tmux: records its args to $MOCK_BIN/tmux.args, then exits 0
cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/tmux.args"
EOF
chmod +x "$MOCK_BIN/tmux"

# ---------------------------------------------------------------------------
# Test 1: bash -n syntax check
# ---------------------------------------------------------------------------
if bash -n "$SCRIPT" 2>/dev/null; then
  run_test "bash -n syntax check" "pass"
else
  run_test "bash -n syntax check" "fail"
fi

# ---------------------------------------------------------------------------
# Test 2: has_flag -p — true and false
# ---------------------------------------------------------------------------
source_has_flag() {
  # Source only the has_flag function from the script in a subshell
  bash -c "
    source '$SCRIPT' 2>/dev/null || true
    has_flag \"\$@\"
  " -- "$@"
}

# We need to extract has_flag without running main logic; do it by sourcing
# only the function definitions via a wrapper
HAS_FLAG_WRAPPER="$(mktemp)"
trap 'rm -rf "$MOCK_BIN" "$HAS_FLAG_WRAPPER"' EXIT

# Write a standalone script that sources open-claude.sh's helpers only
cat > "$HAS_FLAG_WRAPPER" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
# Source only function definitions (stop before main logic)
# has_flag and get_worktree_name are defined before any main logic in open-claude.sh
$(grep -A 8 '^has_flag()' "$SCRIPT")

has_flag "\$@"
WRAPPER
chmod +x "$HAS_FLAG_WRAPPER"

if bash "$HAS_FLAG_WRAPPER" "-p" "-p" "foo" 2>/dev/null; then
  run_test "has_flag -p returns true when present" "pass"
else
  run_test "has_flag -p returns true when present" "fail"
fi

if ! bash "$HAS_FLAG_WRAPPER" "-p" "foo" "bar" 2>/dev/null; then
  run_test "has_flag -p returns false when absent" "pass"
else
  run_test "has_flag -p returns false when absent" "fail"
fi

# ---------------------------------------------------------------------------
# Test 3: has_flag --print — true and false
# ---------------------------------------------------------------------------
if bash "$HAS_FLAG_WRAPPER" "--print" "--print" "foo" 2>/dev/null; then
  run_test "has_flag --print returns true when present" "pass"
else
  run_test "has_flag --print returns true when present" "fail"
fi

if ! bash "$HAS_FLAG_WRAPPER" "--print" "foo" "bar" 2>/dev/null; then
  run_test "has_flag --print returns false when absent" "pass"
else
  run_test "has_flag --print returns false when absent" "fail"
fi

# ---------------------------------------------------------------------------
# Test 4: non-tmux path passes args verbatim to claude
# ---------------------------------------------------------------------------
rm -f "$MOCK_BIN/claude.args" "$MOCK_BIN/tmux.args"
PATH="$MOCK_BIN:$PATH" TMUX="" bash "$SCRIPT" foo bar --baz 2>/dev/null || true

if [[ -f "$MOCK_BIN/claude.args" ]]; then
  args=$(cat "$MOCK_BIN/claude.args")
  expected=$'foo\nbar\n--baz'
  if [[ "$args" == "$expected" ]]; then
    run_test "non-tmux: args passed verbatim to claude" "pass"
  else
    echo "  Expected: $(printf '%q' "$expected")"
    echo "  Got:      $(printf '%q' "$args")"
    run_test "non-tmux: args passed verbatim to claude" "fail"
  fi
else
  run_test "non-tmux: args passed verbatim to claude" "fail"
fi

# ---------------------------------------------------------------------------
# Test 5: tmux + -p flag → exec claude directly (no tmux new-window)
# ---------------------------------------------------------------------------
rm -f "$MOCK_BIN/claude.args" "$MOCK_BIN/tmux.args"
PATH="$MOCK_BIN:$PATH" TMUX="fake-tmux-session" bash "$SCRIPT" -p foo bar 2>/dev/null || true

if [[ -f "$MOCK_BIN/claude.args" ]] && [[ ! -f "$MOCK_BIN/tmux.args" ]]; then
  run_test "tmux + -p: exec claude directly (no new-window)" "pass"
else
  if [[ ! -f "$MOCK_BIN/claude.args" ]]; then
    echo "  claude was not called"
  fi
  if [[ -f "$MOCK_BIN/tmux.args" ]]; then
    echo "  tmux was called unexpectedly: $(cat "$MOCK_BIN/tmux.args")"
  fi
  run_test "tmux + -p: exec claude directly (no new-window)" "fail"
fi

# ---------------------------------------------------------------------------
# Test 6: tmux + no -p → tmux new-window called with correct args
# ---------------------------------------------------------------------------
rm -f "$MOCK_BIN/claude.args" "$MOCK_BIN/tmux.args"
# Set TMUX_PANE so mock tmux doesn't fail if script references it
PATH="$MOCK_BIN:$PATH" TMUX="fake-tmux-session" bash "$SCRIPT" somearg 2>/dev/null || true

if [[ -f "$MOCK_BIN/tmux.args" ]]; then
  tmux_args=$(cat "$MOCK_BIN/tmux.args")
  # Should contain "new-window" as first arg
  first_arg=$(head -n 1 "$MOCK_BIN/tmux.args")
  if [[ "$first_arg" == "new-window" ]]; then
    run_test "tmux + no -p: tmux new-window called" "pass"
  else
    echo "  tmux args: $tmux_args"
    run_test "tmux + no -p: tmux new-window called" "fail"
  fi
else
  run_test "tmux + no -p: tmux new-window called" "fail"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${pass} passed, ${fail} failed"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
exit 0
