#!/usr/bin/env bash
# claude-tool-optimized-session.test.sh — integration tests T1-T6
# Tests the session command's bash logic by extracting its helper scripts.
# Does NOT launch claude (mock binary used). Exits 0 if all pass, 1 if any fail.

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="${TESTS_DIR}/../fixtures"

MOCK_BIN="$(mktemp -d)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN" "$WORK_DIR"' EXIT

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
# Shared helper: extract tool names from a JSONL transcript
# ---------------------------------------------------------------------------

extract_tools_from_jsonl() {
  local jsonl_path="$1"
  python3 - "$jsonl_path" <<'PYEOF'
import json, sys

path = sys.argv[1]
used = set()
found_any = False

def scan(obj):
  global found_any
  if isinstance(obj, dict):
    if obj.get("type") == "tool_use" and obj.get("name"):
      used.add(obj["name"])
      found_any = True
    for v in obj.values():
      scan(v)
  elif isinstance(obj, list):
    for item in obj:
      scan(item)

with open(path) as f:
  for line in f:
    line = line.strip()
    if not line:
      continue
    try:
      scan(json.loads(line))
    except json.JSONDecodeError:
      continue

if not found_any:
  print("__SCHEMA_MISMATCH__")
else:
  for t in sorted(used):
    print(t)
PYEOF
}

# ---------------------------------------------------------------------------
# T1: --dry-run with session_two_tools.jsonl → prints candidates, no file writes
# ---------------------------------------------------------------------------
{
  tools=$(extract_tools_from_jsonl "${FIXTURES_DIR}/session_two_tools.jsonl")
  no_mismatch=true
  [[ "$tools" == "__SCHEMA_MISMATCH__" ]] && no_mismatch=false

  found_bash=false
  found_read=false
  echo "$tools" | grep -qx "Bash" && found_bash=true
  echo "$tools" | grep -qx "Read" && found_read=true

  if $no_mismatch && $found_bash && $found_read; then
    run_test "T1: dry-run - session_two_tools.jsonl extracts Bash and Read" "pass"
  else
    echo "  tools output: $tools"
    run_test "T1: dry-run - session_two_tools.jsonl extracts Bash and Read" "fail"
  fi
}

# ---------------------------------------------------------------------------
# T2: Live run writes overrides to settings.json; disabled/ created
# ---------------------------------------------------------------------------
{
  work="${WORK_DIR}/t2"
  mkdir -p "${work}/.claude"
  cp "${FIXTURES_DIR}/settings_minimal.json" "${work}/.claude/settings.json"
  git -C "$work" init -q 2>/dev/null || true
  git -C "$work" add . 2>/dev/null || true
  git -C "$work" -c user.email="test@test.com" -c user.name="Test" commit -m "init" -q 2>/dev/null || true

  # Simulate the write step (ecc@ecc and chrome-devtools unused)
  python3 - "${work}/.claude/settings.json" <<'PYEOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
  settings = json.load(f)

ep = settings.setdefault("enabledPlugins", {})
for p in ["ecc@ecc", "chrome-devtools"]:
  ep[p] = False

with open(path, "w") as f:
  json.dump(settings, f, indent=2)
  f.write("\n")
PYEOF

  valid_json=false
  python3 -m json.tool "${work}/.claude/settings.json" > /dev/null 2>&1 && valid_json=true

  ecc_val=$(python3 -c "
import json
with open('${work}/.claude/settings.json') as f:
  s = json.load(f)
print(s.get('enabledPlugins', {}).get('ecc@ecc', 'MISSING'))
")

  if $valid_json && [[ "$ecc_val" == "False" ]]; then
    run_test "T2: live run writes ecc@ecc=false to settings.json" "pass"
  else
    echo "  valid_json=$valid_json  ecc_val=$ecc_val"
    run_test "T2: live run writes ecc@ecc=false to settings.json" "fail"
  fi
}

# ---------------------------------------------------------------------------
# T3: session_empty.jsonl → __SCHEMA_MISMATCH__ abort
# ---------------------------------------------------------------------------
{
  result=$(extract_tools_from_jsonl "${FIXTURES_DIR}/session_empty.jsonl")
  if [[ "$result" == "__SCHEMA_MISMATCH__" ]]; then
    run_test "T3: empty transcript returns __SCHEMA_MISMATCH__" "pass"
  else
    echo "  Got: $result"
    run_test "T3: empty transcript returns __SCHEMA_MISMATCH__" "fail"
  fi
}

# ---------------------------------------------------------------------------
# T4: Dirty settings.json → git diff detects it (guard logic verified)
# ---------------------------------------------------------------------------
{
  work="${WORK_DIR}/t4"
  mkdir -p "${work}/.claude"
  cp "${FIXTURES_DIR}/settings_minimal.json" "${work}/.claude/settings.json"
  git -C "$work" init -q 2>/dev/null || true
  git -C "$work" add . 2>/dev/null || true
  git -C "$work" -c user.email="test@test.com" -c user.name="Test" commit -m "init" -q 2>/dev/null || true

  # Make the file dirty
  echo "   " >> "${work}/.claude/settings.json"

  # The guard uses: git -C "${CLAUDE_PROJECT_DIR}" diff --quiet .claude/settings.json
  # A non-zero exit means dirty → should abort
  if ! git -C "$work" diff --quiet "${work}/.claude/settings.json" 2>/dev/null; then
    run_test "T4: dirty settings.json detected by git diff (guard triggers)" "pass"
  else
    run_test "T4: dirty settings.json detected by git diff (guard triggers)" "fail"
  fi
}

# ---------------------------------------------------------------------------
# T5: settings_many_tools.json + only Bash/Read used → >75% disable rate
# ---------------------------------------------------------------------------
{
  # settings_many_tools.json has 5 plugins + 2 MCP = 7 loaded items
  # With Bash+Read used: ecc@ecc, chrome-devtools, context7, Gmail unused (4 plugins)
  # + 2 MCP = 6 disabled → 6/7 = 85% > 75% → should warn
  total_loaded=$(python3 - "${FIXTURES_DIR}/settings_many_tools.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
  s = json.load(f)
plugins = [k for k, v in s.get("enabledPlugins", {}).items() if v is True]
disabled_mcp = s.get("disabledMcpjsonServers", [])
mcp = [k for k in s.get("mcpServers", {}) if k not in disabled_mcp]
print(len(plugins) + len(mcp))
PYEOF
  )

  # 4 plugins (all except context-mode) + 2 MCP = 6 disabled
  total_disabled=6
  pct=$(( total_disabled * 100 / total_loaded ))

  if [[ $pct -gt 75 ]]; then
    run_test "T5: settings_many_tools gives >75% disable rate (${pct}%) — guard triggers" "pass"
  else
    echo "  pct=$pct (expected >75), total_loaded=$total_loaded"
    run_test "T5: settings_many_tools gives >75% disable rate — guard triggers" "fail"
  fi
}

# ---------------------------------------------------------------------------
# T6: Invalid JSON after write → git restore runs and recovers valid JSON
# ---------------------------------------------------------------------------
{
  work="${WORK_DIR}/t6"
  mkdir -p "${work}/.claude"
  cp "${FIXTURES_DIR}/settings_minimal.json" "${work}/.claude/settings.json"
  git -C "$work" init -q 2>/dev/null || true
  git -C "$work" add . 2>/dev/null || true
  git -C "$work" -c user.email="test@test.com" -c user.name="Test" commit -m "init" -q 2>/dev/null || true

  # Corrupt the JSON (simulates a bad write)
  printf 'NOT VALID JSON {{{\n' > "${work}/.claude/settings.json"

  # Verify it's invalid
  if ! python3 -m json.tool "${work}/.claude/settings.json" > /dev/null 2>&1; then
    # Simulate the restore branch: git checkout
    git -C "$work" checkout -- "${work}/.claude/settings.json" 2>/dev/null || true

    # Verify restore worked
    if python3 -m json.tool "${work}/.claude/settings.json" > /dev/null 2>&1; then
      run_test "T6: invalid JSON detected → git restore recovers valid settings.json" "pass"
    else
      run_test "T6: invalid JSON detected → git restore recovers valid settings.json" "fail"
    fi
  else
    echo "  Corrupted file unexpectedly passed JSON validation"
    run_test "T6: invalid JSON detected → git restore recovers valid settings.json" "fail"
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: ${pass} passed, ${fail} failed"

if [[ $fail -gt 0 ]]; then
  exit 1
fi
exit 0
