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

# We need to extract has_flag without running main logic; do it by sourcing
# only the function definitions via a wrapper
HAS_FLAG_WRAPPER="$(mktemp)"
trap 'rm -rf "$MOCK_BIN" "$HAS_FLAG_WRAPPER"' EXIT

# Write a standalone script that sources open-claude.sh's helpers only.
# Use sed to extract the has_flag function by its opening/closing braces.
cat > "$HAS_FLAG_WRAPPER" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
$(sed -n '/^has_flag()/,/^}/p' "$SCRIPT")

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
trap 'rm -rf "$MOCK_BIN" "$HAS_FLAG_WRAPPER" "$GET_WORKTREE_WRAPPER"' EXIT

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
[[ "$1" == "new-window" ]] && exit 1
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
# Test 11: -w flag sets tmux window name
# ---------------------------------------------------------------------------
rm -f "$MOCK_BIN/claude.args" "$MOCK_BIN/tmux.args"

# Reset mock tmux to success (Test 10 left a failing mock)
cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/tmux.args"
EOF
chmod +x "$MOCK_BIN/tmux"

PATH="$MOCK_BIN:$PATH" TMUX="fake-tmux-session" bash "$SCRIPT" -w custwin somearg 2>/dev/null || true

if [[ -f "$MOCK_BIN/tmux.args" ]]; then
  window_name=$(awk '/^-n$/{getline; print; exit}' "$MOCK_BIN/tmux.args")
  if [[ "$window_name" == "custwin" ]]; then
    run_test "-w: tmux new-window uses -w value as window name" "pass"
  else
    echo "  Expected window name: custwin, got: $(printf '%q' "$window_name")"
    echo "  tmux args: $(cat "$MOCK_BIN/tmux.args")"
    run_test "-w: tmux new-window uses -w value as window name" "fail"
  fi
else
  echo "  tmux was not called"
  run_test "-w: tmux new-window uses -w value as window name" "fail"
fi

# ---------------------------------------------------------------------------
# Test 12: -w flag and its value are stripped from the claude command string
# ---------------------------------------------------------------------------
if [[ -f "$MOCK_BIN/tmux.args" ]]; then
  cmd_line=$(awk '/^-c$/{getline; print; exit}' "$MOCK_BIN/tmux.args")
  if [[ " $cmd_line " == *" -w "* ]] || [[ " $cmd_line " == *" custwin "* ]] || [[ "$cmd_line" == *" custwin" ]]; then
    echo "  -w or value leaked into claude cmd: $cmd_line"
    run_test "-w: -w and value stripped from claude command" "fail"
  else
    run_test "-w: -w and value stripped from claude command" "pass"
  fi
else
  run_test "-w: -w and value stripped from claude command" "fail"
fi

# ---------------------------------------------------------------------------
# Test 13: non-tmux path — -w and its value stripped before calling claude
# ---------------------------------------------------------------------------
rm -f "$MOCK_BIN/claude.args" "$MOCK_BIN/tmux.args"
PATH="$MOCK_BIN:$PATH" TMUX="" bash "$SCRIPT" -w mywin foo bar 2>/dev/null || true

if [[ -f "$MOCK_BIN/claude.args" ]]; then
  if grep -qx '\-w' "$MOCK_BIN/claude.args" 2>/dev/null || grep -qx 'mywin' "$MOCK_BIN/claude.args" 2>/dev/null; then
    echo "  -w or value leaked to claude: $(cat "$MOCK_BIN/claude.args")"
    run_test "non-tmux: -w and value stripped before calling claude" "fail"
  else
    run_test "non-tmux: -w and value stripped before calling claude" "pass"
  fi
else
  run_test "non-tmux: -w and value stripped before calling claude" "fail"
fi

# ---------------------------------------------------------------------------
# Test 14: integration (real tmux, no mock tmux) — -w creates named window
# ---------------------------------------------------------------------------
if command -v tmux >/dev/null 2>&1; then
  INT_SOCK=$(mktemp -u /tmp/tmux-oc-test-XXXXXX)
  INT_MOCK_BIN=$(mktemp -d)

  # Sleeping mock claude keeps the window alive long enough to query
  cat > "$INT_MOCK_BIN/claude" <<'EOF'
#!/usr/bin/env bash
sleep 3
EOF
  chmod +x "$INT_MOCK_BIN/claude"

  trap 'tmux -S "$INT_SOCK" kill-server 2>/dev/null || true; rm -f "$INT_SOCK"; rm -rf "$INT_MOCK_BIN"; rm -rf "$MOCK_BIN" "$HAS_FLAG_WRAPPER" "$GET_WORKTREE_WRAPPER"' EXIT

  if tmux -S "$INT_SOCK" new-session -d -s main -x 220 -y 24 2>/dev/null; then
    SERVER_PID=$(tmux -S "$INT_SOCK" display-message -p "#{pid}" -t main 2>/dev/null || echo "0")

    PATH="$INT_MOCK_BIN:$PATH" TMUX="$INT_SOCK,$SERVER_PID,0" \
      bash "$SCRIPT" -w "oc-int-test" somearg 2>/dev/null || true

    sleep 0.5

    if tmux -S "$INT_SOCK" list-windows -t main 2>/dev/null | grep -q "oc-int-test"; then
      run_test "integration (real tmux): -w creates named window" "pass"
    else
      echo "  Windows: $(tmux -S "$INT_SOCK" list-windows -t main 2>/dev/null || echo 'query failed')"
      run_test "integration (real tmux): -w creates named window" "fail"
    fi

    tmux -S "$INT_SOCK" kill-server 2>/dev/null || true
    rm -f "$INT_SOCK"
    rm -rf "$INT_MOCK_BIN"
  else
    echo "  Could not start real tmux test server"
    rm -rf "$INT_MOCK_BIN"
    run_test "integration (real tmux): -w creates named window" "fail"
  fi
else
  echo "SKIP: integration (real tmux): -w creates named window (tmux not found)"
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
