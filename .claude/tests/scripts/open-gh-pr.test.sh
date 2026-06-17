#!/usr/bin/env bash
# open-gh-pr.test.sh — integration tests for open-gh-pr.sh
# Exits 0 if all tests pass, 1 if any test fails.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/open-gh-pr.sh"
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

# Mock git: returns a known HTTPS remote URL
cat > "$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "remote get-url origin" ]]; then
  echo "https://github.com/owner/repo.git"
  exit 0
fi
exec /usr/bin/git "$@"
EOF
chmod +x "$MOCK_BIN/git"

# ---------------------------------------------------------------------------
# Test 1: bash -n syntax check
# ---------------------------------------------------------------------------
if bash -n "$SCRIPT" 2>/dev/null; then
  run_test "bash -n syntax check" "pass"
else
  run_test "bash -n syntax check" "fail"
fi

# ---------------------------------------------------------------------------
# Test 2: single PR ID → correct URL
# ---------------------------------------------------------------------------
output=$(PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" 42 2>/dev/null)
expected="https://github.com/owner/repo/pull/42"
if [[ "$output" == "$expected" ]]; then
  run_test "single PR ID produces correct URL" "pass"
else
  echo "  Expected: $expected"
  echo "  Got:      $output"
  run_test "single PR ID produces correct URL" "fail"
fi

# ---------------------------------------------------------------------------
# Test 3: multiple PR IDs → multiple URLs in order
# ---------------------------------------------------------------------------
output=$(PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" 1 2 3 2>/dev/null)
expected=$'https://github.com/owner/repo/pull/1\nhttps://github.com/owner/repo/pull/2\nhttps://github.com/owner/repo/pull/3'
if [[ "$output" == "$expected" ]]; then
  run_test "multiple PR IDs produce correct URLs in order" "pass"
else
  echo "  Expected: $(printf '%q' "$expected")"
  echo "  Got:      $(printf '%q' "$output")"
  run_test "multiple PR IDs produce correct URLs in order" "fail"
fi

# ---------------------------------------------------------------------------
# Test 4: non-numeric arg → non-zero exit
# ---------------------------------------------------------------------------
if ! PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" abc 2>/dev/null; then
  run_test "non-numeric arg → error exit" "pass"
else
  run_test "non-numeric arg → error exit" "fail"
fi

# ---------------------------------------------------------------------------
# Test 5: no args → non-zero exit
# ---------------------------------------------------------------------------
if ! PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" 2>/dev/null; then
  run_test "no args → error exit" "pass"
else
  run_test "no args → error exit" "fail"
fi

# ---------------------------------------------------------------------------
# Test 6: git@ remote URL resolved correctly
# ---------------------------------------------------------------------------
cat > "$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "remote get-url origin" ]]; then
  echo "git@github.com:owner/repo.git"
  exit 0
fi
exec /usr/bin/git "$@"
EOF
chmod +x "$MOCK_BIN/git"
output=$(PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" 7 2>/dev/null)
expected="https://github.com/owner/repo/pull/7"
if [[ "$output" == "$expected" ]]; then
  run_test "git@ remote resolved to correct pull URL" "pass"
else
  echo "  Expected: $expected"
  echo "  Got:      $output"
  run_test "git@ remote resolved to correct pull URL" "fail"
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
