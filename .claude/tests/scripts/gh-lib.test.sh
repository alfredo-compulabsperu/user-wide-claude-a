#!/usr/bin/env bash
# gh-lib.test.sh — integration tests for gh-lib.sh helper functions
# Exits 0 if all tests pass, 1 if any test fails.

set -euo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/gh-lib.sh"
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
# Helper: write a mock git binary that returns a given remote URL
# ---------------------------------------------------------------------------
make_mock_git() {
  local url="$1"
  cat > "$MOCK_BIN/git" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "remote get-url origin" ]]; then
  echo "$url"
  exit 0
fi
exec /usr/bin/git "\$@"
EOF
  chmod +x "$MOCK_BIN/git"
}

# ---------------------------------------------------------------------------
# Test 1: bash -n syntax check
# ---------------------------------------------------------------------------
if bash -n "$LIB" 2>/dev/null; then
  run_test "bash -n syntax check" "pass"
else
  run_test "bash -n syntax check" "fail"
fi

# ---------------------------------------------------------------------------
# Test 2: git@ SCP format → https URL, .git stripped
# ---------------------------------------------------------------------------
make_mock_git "git@github.com:owner/repo.git"
result=$(PATH="$MOCK_BIN:$PATH" bash -c ". '$LIB'; resolve_github_base_url && echo \"\$base_url\"" 2>/dev/null)
if [[ "$result" == "https://github.com/owner/repo" ]]; then
  run_test "git@ URL → https, .git stripped" "pass"
else
  echo "  Got: $result"
  run_test "git@ URL → https, .git stripped" "fail"
fi

# ---------------------------------------------------------------------------
# Test 3: ssh://git@ format → https URL, .git stripped
# ---------------------------------------------------------------------------
make_mock_git "ssh://git@github.com/owner/repo.git"
result=$(PATH="$MOCK_BIN:$PATH" bash -c ". '$LIB'; resolve_github_base_url && echo \"\$base_url\"" 2>/dev/null)
if [[ "$result" == "https://github.com/owner/repo" ]]; then
  run_test "ssh://git@ URL → https, .git stripped" "pass"
else
  echo "  Got: $result"
  run_test "ssh://git@ URL → https, .git stripped" "fail"
fi

# ---------------------------------------------------------------------------
# Test 4: https:// format passthrough, .git stripped
# ---------------------------------------------------------------------------
make_mock_git "https://github.com/owner/repo.git"
result=$(PATH="$MOCK_BIN:$PATH" bash -c ". '$LIB'; resolve_github_base_url && echo \"\$base_url\"" 2>/dev/null)
if [[ "$result" == "https://github.com/owner/repo" ]]; then
  run_test "https:// URL passthrough, .git stripped" "pass"
else
  echo "  Got: $result"
  run_test "https:// URL passthrough, .git stripped" "fail"
fi

# ---------------------------------------------------------------------------
# Test 5: https:// without .git suffix — no double-strip
# ---------------------------------------------------------------------------
make_mock_git "https://github.com/owner/repo"
result=$(PATH="$MOCK_BIN:$PATH" bash -c ". '$LIB'; resolve_github_base_url && echo \"\$base_url\"" 2>/dev/null)
if [[ "$result" == "https://github.com/owner/repo" ]]; then
  run_test "https:// without .git — no double-strip" "pass"
else
  echo "  Got: $result"
  run_test "https:// without .git — no double-strip" "fail"
fi

# ---------------------------------------------------------------------------
# Test 6: non-GitHub remote → non-zero exit
# ---------------------------------------------------------------------------
make_mock_git "https://gitlab.com/owner/repo.git"
if ! PATH="$MOCK_BIN:$PATH" bash -c ". '$LIB'; resolve_github_base_url" 2>/dev/null; then
  run_test "non-GitHub remote → error exit" "pass"
else
  run_test "non-GitHub remote → error exit" "fail"
fi

# ---------------------------------------------------------------------------
# Test 7: no remote (git fails) → non-zero exit
# ---------------------------------------------------------------------------
cat > "$MOCK_BIN/git" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MOCK_BIN/git"
if ! PATH="$MOCK_BIN:$PATH" bash -c ". '$LIB'; resolve_github_base_url" 2>/dev/null; then
  run_test "no remote → error exit" "pass"
else
  run_test "no remote → error exit" "fail"
fi

# ---------------------------------------------------------------------------
# Test 8: open_urls prints each URL to stdout
# ---------------------------------------------------------------------------
output=$(bash -c ". '$LIB'; open_urls 'https://example.com/1' 'https://example.com/2'" 2>/dev/null)
expected=$'https://example.com/1\nhttps://example.com/2'
if [[ "$output" == "$expected" ]]; then
  run_test "open_urls prints URLs to stdout" "pass"
else
  echo "  Expected: $(printf '%q' "$expected")"
  echo "  Got:      $(printf '%q' "$output")"
  run_test "open_urls prints URLs to stdout" "fail"
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
