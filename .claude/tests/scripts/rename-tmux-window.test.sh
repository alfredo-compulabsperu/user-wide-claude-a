#!/usr/bin/env bash
# rename-tmux-window.test.sh — integration tests for rename-tmux-window.sh
# Exits 0 if all tests pass, 1 if any test fails.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/rename-tmux-window.sh"
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
# Helpers
# ---------------------------------------------------------------------------

make_mock_git() {
  local toplevel="$1" branch="$2"
  cat > "$MOCK_BIN/git" <<EOF
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --show-toplevel") echo "$toplevel"; exit 0 ;;
  "rev-parse --abbrev-ref HEAD") echo "$branch"; exit 0 ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$MOCK_BIN/git"
}

make_mock_tmux() {
  rm -f "$MOCK_BIN/renamed_to"
  cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message) echo "2" ;;
  list-windows) printf '0\tmain\n1\tother\n' ;;
  rename-window) echo "${@: -1}" > "$(dirname "$0")/renamed_to" ;;
esac
EOF
  chmod +x "$MOCK_BIN/tmux"
}

# ---------------------------------------------------------------------------
# Test 1: bash -n syntax check
# ---------------------------------------------------------------------------
if bash -n "$SCRIPT" 2>/dev/null; then
  run_test "bash -n syntax check" "pass"
else
  run_test "bash -n syntax check" "fail"
fi

# ---------------------------------------------------------------------------
# Test 2: not inside tmux → error exit
# ---------------------------------------------------------------------------
if ! TMUX="" bash "$SCRIPT" mywindow 2>/dev/null; then
  run_test "not in tmux → error exit" "pass"
else
  run_test "not in tmux → error exit" "fail"
fi

# ---------------------------------------------------------------------------
# Test 3: not in git + no name supplied → usage error
# ---------------------------------------------------------------------------
cat > "$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MOCK_BIN/git"
if ! PATH="$MOCK_BIN:$PATH" TMUX="fake" TMUX_PANE="" bash "$SCRIPT" 2>/dev/null; then
  run_test "not in git + no name → usage error" "pass"
else
  run_test "not in git + no name → usage error" "fail"
fi

# ---------------------------------------------------------------------------
# Test 4: explicit name → renamed to that name
# ---------------------------------------------------------------------------
make_mock_git "/repo/tools" "worktree-tools"
make_mock_tmux
PATH="$MOCK_BIN:$PATH" TMUX="fake" TMUX_PANE="%" bash "$SCRIPT" myname 2>/dev/null || true
if [[ -f "$MOCK_BIN/renamed_to" ]] && [[ "$(cat "$MOCK_BIN/renamed_to")" == "myname" ]]; then
  run_test "explicit name → renamed to that name" "pass"
else
  echo "  renamed_to: $(cat "$MOCK_BIN/renamed_to" 2>/dev/null || echo '<missing>')"
  run_test "explicit name → renamed to that name" "fail"
fi

# ---------------------------------------------------------------------------
# Test 5: auto-compute — branch 'worktree-tools', folder 'tools' → name 'tools'
# ---------------------------------------------------------------------------
make_mock_git "/repo/tools" "worktree-tools"
make_mock_tmux
PATH="$MOCK_BIN:$PATH" TMUX="fake" TMUX_PANE="%" bash "$SCRIPT" 2>/dev/null || true
if [[ -f "$MOCK_BIN/renamed_to" ]] && [[ "$(cat "$MOCK_BIN/renamed_to")" == "tools" ]]; then
  run_test "auto-compute: branch 'worktree-tools', folder 'tools' → name 'tools'" "pass"
else
  echo "  renamed_to: $(cat "$MOCK_BIN/renamed_to" 2>/dev/null || echo '<missing>')"
  run_test "auto-compute: branch 'worktree-tools', folder 'tools' → name 'tools'" "fail"
fi

# ---------------------------------------------------------------------------
# Test 6: auto-compute — branch 'main', folder 'tools' → folder fallback 'tools'
# ---------------------------------------------------------------------------
make_mock_git "/repo/tools" "main"
make_mock_tmux
PATH="$MOCK_BIN:$PATH" TMUX="fake" TMUX_PANE="%" bash "$SCRIPT" 2>/dev/null || true
if [[ -f "$MOCK_BIN/renamed_to" ]] && [[ "$(cat "$MOCK_BIN/renamed_to")" == "tools" ]]; then
  run_test "auto-compute: branch 'main', folder 'tools' → folder fallback 'tools'" "pass"
else
  echo "  renamed_to: $(cat "$MOCK_BIN/renamed_to" 2>/dev/null || echo '<missing>')"
  run_test "auto-compute: branch 'main', folder 'tools' → folder fallback 'tools'" "fail"
fi

# ---------------------------------------------------------------------------
# Test 7: name conflict → error exit
# ---------------------------------------------------------------------------
make_mock_git "/repo/tools" "worktree-tools"
# Window 1 already named 'tools', current window is 2 → conflict
cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message) echo "2" ;;
  list-windows) printf '0\tmain\n1\ttools\n2\tcurrent\n' ;;
  rename-window) echo "${@: -1}" > "$(dirname "$0")/renamed_to" ;;
esac
EOF
chmod +x "$MOCK_BIN/tmux"
if ! PATH="$MOCK_BIN:$PATH" TMUX="fake" TMUX_PANE="%" bash "$SCRIPT" 2>/dev/null; then
  run_test "name conflict → error exit" "pass"
else
  run_test "name conflict → error exit" "fail"
fi

# ---------------------------------------------------------------------------
# Test 8: rename-window failure → error exit
# ---------------------------------------------------------------------------
make_mock_git "/repo/tools" "worktree-tools"
cat > "$MOCK_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  display-message) echo "2" ;;
  list-windows) printf '0\tmain\n1\tother\n' ;;
  rename-window) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/tmux"
if ! PATH="$MOCK_BIN:$PATH" TMUX="fake" TMUX_PANE="%" bash "$SCRIPT" myname 2>/dev/null; then
  run_test "rename-window failure → error exit" "pass"
else
  run_test "rename-window failure → error exit" "fail"
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
