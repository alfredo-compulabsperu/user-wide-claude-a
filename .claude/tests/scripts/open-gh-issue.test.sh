#!/usr/bin/env bash
# open-gh-issue.test.sh — integration tests for open-gh-issue.sh
# Exits 0 if all tests pass, 1 if any test fails.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/open-gh-issue.sh"
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
# Test 2: single issue ID → correct URL
# ---------------------------------------------------------------------------
output=$(PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" 42 2>/dev/null)
expected="https://github.com/owner/repo/issues/42"
if [[ "$output" == "$expected" ]]; then
  run_test "single issue ID produces correct URL" "pass"
else
  echo "  Expected: $expected"
  echo "  Got:      $output"
  run_test "single issue ID produces correct URL" "fail"
fi

# ---------------------------------------------------------------------------
# Test 3: multiple issue IDs → multiple URLs in order
# ---------------------------------------------------------------------------
output=$(PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" 1 2 3 2>/dev/null)
expected=$'https://github.com/owner/repo/issues/1\nhttps://github.com/owner/repo/issues/2\nhttps://github.com/owner/repo/issues/3'
if [[ "$output" == "$expected" ]]; then
  run_test "multiple issue IDs produce correct URLs in order" "pass"
else
  echo "  Expected: $(printf '%q' "$expected")"
  echo "  Got:      $(printf '%q' "$output")"
  run_test "multiple issue IDs produce correct URLs in order" "fail"
fi

# ---------------------------------------------------------------------------
# Test 4: no args → non-zero exit
# ---------------------------------------------------------------------------
if ! PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" 2>/dev/null; then
  run_test "no args → error exit" "pass"
else
  run_test "no args → error exit" "fail"
fi

# ---------------------------------------------------------------------------
# Test 5: NL search — gh returns JSON, URLs extracted correctly
# ---------------------------------------------------------------------------
cat > "$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo '[{"number":7,"url":"https://github.com/owner/repo/issues/7"},{"number":12,"url":"https://github.com/owner/repo/issues/12"}]'
EOF
chmod +x "$MOCK_BIN/gh"

output=$(PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" fixes the login bug 2>/dev/null)
expected=$'https://github.com/owner/repo/issues/7\nhttps://github.com/owner/repo/issues/12'
if [[ "$output" == "$expected" ]]; then
  run_test "NL search: URLs extracted from gh JSON response" "pass"
else
  echo "  Expected: $(printf '%q' "$expected")"
  echo "  Got:      $(printf '%q' "$output")"
  run_test "NL search: URLs extracted from gh JSON response" "fail"
fi

# ---------------------------------------------------------------------------
# Test 6: NL search with 'that ' prefix — prefix stripped from query
# ---------------------------------------------------------------------------
rm -f "$MOCK_BIN/gh.args"
cat > "$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/gh.args"
echo '[{"number":5,"url":"https://github.com/owner/repo/issues/5"}]'
EOF
chmod +x "$MOCK_BIN/gh"

PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" that fixes login 2>/dev/null || true
if [[ -f "$MOCK_BIN/gh.args" ]]; then
  if ! grep -q "that fixes" "$MOCK_BIN/gh.args" 2>/dev/null; then
    run_test "NL search 'that ' prefix stripped from query" "pass"
  else
    echo "  gh args: $(cat "$MOCK_BIN/gh.args")"
    run_test "NL search 'that ' prefix stripped from query" "fail"
  fi
else
  run_test "NL search 'that ' prefix stripped from query" "fail"
fi

# ---------------------------------------------------------------------------
# Test 7: NL search passes --state open to gh
# ---------------------------------------------------------------------------
if [[ -f "$MOCK_BIN/gh.args" ]]; then
  if grep -qx "open" "$MOCK_BIN/gh.args" 2>/dev/null; then
    run_test "NL search passes --state open to gh" "pass"
  else
    echo "  gh args: $(cat "$MOCK_BIN/gh.args")"
    run_test "NL search passes --state open to gh" "fail"
  fi
else
  run_test "NL search passes --state open to gh" "fail"
fi

# ---------------------------------------------------------------------------
# Test 8: NL search zero results → non-zero exit
# ---------------------------------------------------------------------------
cat > "$MOCK_BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo '[]'
EOF
chmod +x "$MOCK_BIN/gh"

if ! PATH="$MOCK_BIN:$PATH" bash "$SCRIPT" nonexistent query 2>/dev/null; then
  run_test "NL search zero results → error exit" "pass"
else
  run_test "NL search zero results → error exit" "fail"
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
