#!/usr/bin/env bash
# sync-state.test.sh — unit tests for sync-state.sh
# Exits 0 if all tests pass, 1 if any test fails.
#
# All tests run with HOME pointed at a mktemp -d sandbox so the real
# ~/.claude/ is never touched.

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync-state.sh"
SANDBOX_HOME="$(mktemp -d)"

trap 'rm -rf "$SANDBOX_HOME"' EXIT

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

reset_sandbox() {
  rm -rf "${SANDBOX_HOME:?}/.claude"
  mkdir -p "$SANDBOX_HOME/.claude"
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
# Test 2: get on missing state file (no ~/.claude/ at all yet) → empty string
# ---------------------------------------------------------------------------
rm -rf "${SANDBOX_HOME:?}/.claude"
out="$(HOME="$SANDBOX_HOME" bash "$SCRIPT" get foo)"
if [[ -z "$out" ]]; then
  run_test "get on missing state file → empty string" "pass"
else
  echo "  got: [$out]"
  run_test "get on missing state file → empty string" "fail"
fi

# ---------------------------------------------------------------------------
# Test 3: set then get round trip
# ---------------------------------------------------------------------------
reset_sandbox
HOME="$SANDBOX_HOME" bash "$SCRIPT" set foo abc123
out="$(HOME="$SANDBOX_HOME" bash "$SCRIPT" get foo)"
if [[ "$out" == "abc123" ]]; then
  run_test "set then get round trip" "pass"
else
  echo "  got: [$out]"
  run_test "set then get round trip" "fail"
fi

# ---------------------------------------------------------------------------
# Test 4: get on missing key (state file exists, key absent) → empty string
# ---------------------------------------------------------------------------
reset_sandbox
HOME="$SANDBOX_HOME" bash "$SCRIPT" set foo abc123
out="$(HOME="$SANDBOX_HOME" bash "$SCRIPT" get bar)"
if [[ -z "$out" ]]; then
  run_test "get on missing key → empty string" "pass"
else
  echo "  got: [$out]"
  run_test "get on missing key → empty string" "fail"
fi

# ---------------------------------------------------------------------------
# Test 5: set overwrites an existing key's value
# ---------------------------------------------------------------------------
reset_sandbox
HOME="$SANDBOX_HOME" bash "$SCRIPT" set foo abc123
HOME="$SANDBOX_HOME" bash "$SCRIPT" set foo def456
out="$(HOME="$SANDBOX_HOME" bash "$SCRIPT" get foo)"
if [[ "$out" == "def456" ]]; then
  run_test "set overwrites existing key" "pass"
else
  echo "  got: [$out]"
  run_test "set overwrites existing key" "fail"
fi

# ---------------------------------------------------------------------------
# Test 6: multiple keys stay independent
# ---------------------------------------------------------------------------
reset_sandbox
HOME="$SANDBOX_HOME" bash "$SCRIPT" set foo aaa
HOME="$SANDBOX_HOME" bash "$SCRIPT" set bar bbb
out_foo="$(HOME="$SANDBOX_HOME" bash "$SCRIPT" get foo)"
out_bar="$(HOME="$SANDBOX_HOME" bash "$SCRIPT" get bar)"
if [[ "$out_foo" == "aaa" && "$out_bar" == "bbb" ]]; then
  run_test "multiple keys stay independent" "pass"
else
  echo "  got foo=[$out_foo] bar=[$out_bar]"
  run_test "multiple keys stay independent" "fail"
fi

# ---------------------------------------------------------------------------
# Test 7: set creates ~/.claude/ automatically if missing
# ---------------------------------------------------------------------------
rm -rf "${SANDBOX_HOME:?}/.claude"
HOME="$SANDBOX_HOME" bash "$SCRIPT" set foo abc123
if [[ -f "$SANDBOX_HOME/.claude/.sync-state.json" ]]; then
  run_test "set creates ~/.claude/ automatically" "pass"
else
  run_test "set creates ~/.claude/ automatically" "fail"
fi

# ---------------------------------------------------------------------------
# Test 8: missing args → usage error exit
# ---------------------------------------------------------------------------
reset_sandbox
if ! HOME="$SANDBOX_HOME" bash "$SCRIPT" get 2>/dev/null; then
  run_test "get with no key → usage error" "pass"
else
  run_test "get with no key → usage error" "fail"
fi

if ! HOME="$SANDBOX_HOME" bash "$SCRIPT" set foo 2>/dev/null; then
  run_test "set with only one arg → usage error" "pass"
else
  run_test "set with only one arg → usage error" "fail"
fi

# ---------------------------------------------------------------------------
# Test 9: unknown subcommand → usage error
# ---------------------------------------------------------------------------
if ! HOME="$SANDBOX_HOME" bash "$SCRIPT" bogus foo 2>/dev/null; then
  run_test "unknown subcommand → usage error" "pass"
else
  run_test "unknown subcommand → usage error" "fail"
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
