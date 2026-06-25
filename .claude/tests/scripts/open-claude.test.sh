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
# Test 4: non-tmux without -p → exits with error, claude not called
# ---------------------------------------------------------------------------
rm -f "$MOCK_BIN/claude.args" "$MOCK_BIN/tmux.args"
PATH="$MOCK_BIN:$PATH" TMUX="" bash "$SCRIPT" foo bar --baz 2>/dev/null && exit_code=0 || exit_code=$?

if [[ $exit_code -ne 0 ]] && [[ ! -f "$MOCK_BIN/claude.args" ]]; then
  run_test "non-tmux without -p: exits with error, claude not called" "pass"
else
  run_test "non-tmux without -p: exits with error, claude not called" "fail"
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

# Test 5b: -p flag is stripped and not forwarded to claude
if [[ -f "$MOCK_BIN/claude.args" ]]; then
  claude_args=$(cat "$MOCK_BIN/claude.args")
  if grep -qx '\-p' "$MOCK_BIN/claude.args" 2>/dev/null; then
    echo "  -p flag leaked through to claude: $claude_args"
    run_test "tmux + -p: -p flag stripped before calling claude" "fail"
  else
    run_test "tmux + -p: -p flag stripped before calling claude" "pass"
  fi
else
  run_test "tmux + -p: -p flag stripped before calling claude" "fail"
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

# Test 6b: tmux new-window received -n flag
if [[ -f "$MOCK_BIN/tmux.args" ]]; then
  if grep -qx '\-n' "$MOCK_BIN/tmux.args" 2>/dev/null; then
    run_test "tmux + no -p: tmux new-window -n flag present" "pass"
  else
    echo "  tmux args: $(cat "$MOCK_BIN/tmux.args")"
    run_test "tmux + no -p: tmux new-window -n flag present" "fail"
  fi
else
  run_test "tmux + no -p: tmux new-window -n flag present" "fail"
fi

# Test 6c: command string passed to tmux contains the forwarded arg
if [[ -f "$MOCK_BIN/tmux.args" ]]; then
  last_tmux_arg=$(tail -n 1 "$MOCK_BIN/tmux.args")
  if [[ "$last_tmux_arg" == *"somearg"* ]]; then
    run_test "tmux + no -p: command string forwarded to tmux contains arg" "pass"
  else
    echo "  last tmux arg: $last_tmux_arg"
    run_test "tmux + no -p: command string forwarded to tmux contains arg" "fail"
  fi
else
  run_test "tmux + no -p: command string forwarded to tmux contains arg" "fail"
fi

# ---------------------------------------------------------------------------
# Test 7: tmux + --print flag → exec claude directly (no tmux new-window)
# ---------------------------------------------------------------------------
rm -f "$MOCK_BIN/claude.args" "$MOCK_BIN/tmux.args"
PATH="$MOCK_BIN:$PATH" TMUX="fake-tmux-session" bash "$SCRIPT" --print foo bar 2>/dev/null || true

if [[ -f "$MOCK_BIN/claude.args" ]] && [[ ! -f "$MOCK_BIN/tmux.args" ]]; then
  run_test "tmux + --print: exec claude directly (no new-window)" "pass"
else
  if [[ ! -f "$MOCK_BIN/claude.args" ]]; then
    echo "  claude was not called"
  fi
  if [[ -f "$MOCK_BIN/tmux.args" ]]; then
    echo "  tmux was called unexpectedly: $(cat "$MOCK_BIN/tmux.args")"
  fi
  run_test "tmux + --print: exec claude directly (no new-window)" "fail"
fi

# Test 7b: --print flag is stripped and not forwarded to claude
if [[ -f "$MOCK_BIN/claude.args" ]]; then
  if grep -qx '\-\-print' "$MOCK_BIN/claude.args" 2>/dev/null; then
    echo "  --print flag leaked through to claude: $(cat "$MOCK_BIN/claude.args")"
    run_test "tmux + --print: --print flag stripped before calling claude" "fail"
  else
    run_test "tmux + --print: --print flag stripped before calling claude" "pass"
  fi
else
  run_test "tmux + --print: --print flag stripped before calling claude" "fail"
fi

# ---------------------------------------------------------------------------
# Test 8: tmux path — arg with spaces is present in command string
# ---------------------------------------------------------------------------
rm -f "$MOCK_BIN/claude.args" "$MOCK_BIN/tmux.args"
PATH="$MOCK_BIN:$PATH" TMUX="fake-tmux-session" bash "$SCRIPT" "hello world" 2>/dev/null || true

if [[ -f "$MOCK_BIN/tmux.args" ]]; then
  last_tmux_arg=$(tail -n 1 "$MOCK_BIN/tmux.args")
  if [[ "$last_tmux_arg" == *"hello"*"world"* ]]; then
    run_test "tmux path: arg with spaces present in command string" "pass"
  else
    echo "  last tmux arg: $last_tmux_arg"
    run_test "tmux path: arg with spaces present in command string" "fail"
  fi
else
  run_test "tmux path: arg with spaces present in command string" "fail"
fi

# ---------------------------------------------------------------------------
# Test 9: get_worktree_name fallback — returns "claude" when not in a git repo
# ---------------------------------------------------------------------------
GET_WORKTREE_WRAPPER="$(mktemp)"
trap 'rm -rf "$MOCK_BIN" "$GET_WORKTREE_WRAPPER"' EXIT

cat > "$GET_WORKTREE_WRAPPER" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
$(sed -n '/^get_worktree_name()/,/^}/p' "$SCRIPT")

get_worktree_name
WRAPPER
chmod +x "$GET_WORKTREE_WRAPPER"

result=$(cd /tmp && bash "$GET_WORKTREE_WRAPPER" 2>/dev/null || true)
if [[ "$result" == "claude" ]]; then
  run_test "get_worktree_name: returns 'claude' outside a git repo" "pass"
else
  echo "  Got: $result"
  run_test "get_worktree_name: returns 'claude' outside a git repo" "fail"
fi

# ---------------------------------------------------------------------------
# Test 10: tmux new-window FAILS → fallback exec claude with original args
# ---------------------------------------------------------------------------
rm -f "$MOCK_BIN/claude.args" "$MOCK_BIN/tmux.args"

# Mock tmux that exits 1 for new-window so the fallback path is triggered
cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/tmux.args"
[[ "$1" == "display-message" ]] && { echo "test-session"; exit 0; }
[[ "$1" == "new-window" ]] && exit 1
exit 0
EOF
chmod +x "$MOCK_BIN/tmux"

PATH="$MOCK_BIN:$PATH" TMUX="fake-tmux-session" bash "$SCRIPT" somearg 2>/dev/null || true

if [[ -f "$MOCK_BIN/claude.args" ]]; then
  args=$(cat "$MOCK_BIN/claude.args")
  if [[ "$args" == "somearg" ]]; then
    run_test "tmux new-window failure: fallback exec claude with correct args" "pass"
  else
    echo "  claude.args: $(printf '%q' "$args")"
    run_test "tmux new-window failure: fallback exec claude with correct args" "fail"
  fi
else
  run_test "tmux new-window failure: fallback exec claude with correct args" "fail"
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
