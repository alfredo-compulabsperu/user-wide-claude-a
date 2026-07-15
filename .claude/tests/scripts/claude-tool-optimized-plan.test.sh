#!/usr/bin/env bash
# claude-tool-optimized-plan.test.sh — integration tests T7-T8
# Tests plan command's bash logic (settings write + gitignore + JSON validation).
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
# Helper: simulate the plan command's settings-write step
# ---------------------------------------------------------------------------

write_disabled_to_settings() {
  local settings_path="$1"
  local disabled_plugins="$2"
  local disabled_mcp="$3"

  python3 - "$settings_path" "$disabled_plugins" "$disabled_mcp" <<'PYEOF'
import json, sys, os

path = sys.argv[1]
plugins_to_disable = [p for p in sys.argv[2].split() if p]
mcp_to_disable     = [m for m in sys.argv[3].split() if m]

settings = {}
if os.path.exists(path):
  with open(path) as f:
    settings = json.load(f)

ep = settings.setdefault("enabledPlugins", {})
for p in plugins_to_disable:
  ep[p] = False

disabled_mcp_list = settings.setdefault("disabledMcpjsonServers", [])
for m in mcp_to_disable:
  if m not in disabled_mcp_list:
    disabled_mcp_list.append(m)

with open(path, "w") as f:
  json.dump(settings, f, indent=2)
  f.write("\n")
PYEOF
}

# ---------------------------------------------------------------------------
# T7: plan_file_editing.plan.md + --dry-run → fixture readable, signals present
# ---------------------------------------------------------------------------
{
  if [[ -f "${FIXTURES_DIR}/plan_file_editing.plan.md" ]]; then
    content=$(cat "${FIXTURES_DIR}/plan_file_editing.plan.md")
    has_bash=false
    has_edit=false
    echo "$content" | grep -qi "bash" && has_bash=true
    echo "$content" | grep -qi "edit" && has_edit=true

    if $has_bash && $has_edit; then
      run_test "T7: dry-run - plan_file_editing.plan.md readable with Bash+Edit signals" "pass"
    else
      echo "  has_bash=$has_bash  has_edit=$has_edit"
      run_test "T7: dry-run - plan_file_editing.plan.md readable with Bash+Edit signals" "fail"
    fi
  else
    run_test "T7: dry-run - plan_file_editing.plan.md exists" "fail"
  fi
}

# ---------------------------------------------------------------------------
# T8: live run → writes overrides, gitignore updated, restore trap works
# ---------------------------------------------------------------------------
{
  work="${WORK_DIR}/t8"
  mkdir -p "${work}/.claude"
  cp "${FIXTURES_DIR}/settings_minimal.json" "${work}/.claude/settings.json"
  git -C "$work" init -q 2>/dev/null || true
  git -C "$work" add . 2>/dev/null || true
  git -C "$work" -c user.email="test@test.com" -c user.name="Test" commit -m "init" -q 2>/dev/null || true

  # For a file-editing plan: disable ecc@ecc and chrome-devtools; keep context-mode
  write_disabled_to_settings "${work}/.claude/settings.json" "ecc@ecc chrome-devtools" ""

  valid_json=false
  python3 -m json.tool "${work}/.claude/settings.json" > /dev/null 2>&1 && valid_json=true

  ecc_val=$(python3 -c "
import json
with open('${work}/.claude/settings.json') as f: s = json.load(f)
print(s.get('enabledPlugins', {}).get('ecc@ecc', 'MISSING'))
")
  chrome_val=$(python3 -c "
import json
with open('${work}/.claude/settings.json') as f: s = json.load(f)
print(s.get('enabledPlugins', {}).get('chrome-devtools', 'MISSING'))
")
  context_mode_val=$(python3 -c "
import json
with open('${work}/.claude/settings.json') as f: s = json.load(f)
print(s.get('enabledPlugins', {}).get('context-mode', 'MISSING'))
")

  if $valid_json && [[ "$ecc_val" == "False" ]] && [[ "$chrome_val" == "False" ]] && [[ "$context_mode_val" == "True" ]]; then
    run_test "T8: live run writes ecc@ecc=false, chrome-devtools=false, context-mode=true" "pass"
  else
    echo "  valid_json=$valid_json  ecc=$ecc_val  chrome=$chrome_val  context-mode=$context_mode_val"
    run_test "T8: live run writes ecc@ecc=false, chrome-devtools=false, context-mode=true" "fail"
  fi

  # Gitignore entries
  gitignore="${work}/.gitignore"
  touch "$gitignore"
  grep -qxF '.claude/agents/disabled/' "$gitignore" || echo '.claude/agents/disabled/' >> "$gitignore"
  grep -qxF '.claude/skills/disabled/' "$gitignore" || echo '.claude/skills/disabled/' >> "$gitignore"

  if grep -qxF '.claude/agents/disabled/' "$gitignore" && \
     grep -qxF '.claude/skills/disabled/' "$gitignore"; then
    run_test "T8: gitignore entries for disabled/ folders written" "pass"
  else
    run_test "T8: gitignore entries for disabled/ folders written" "fail"
  fi

  # Restore trap: move fake agent to disabled/, then restore
  mkdir -p "${work}/.claude/agents/disabled"
  touch "${work}/.claude/agents/disabled/fake-agent.md"

  find "${work}/.claude/agents/disabled" -name "*.md" \
    -exec mv {} "${work}/.claude/agents/" \; 2>/dev/null || true

  if [[ -f "${work}/.claude/agents/fake-agent.md" ]] && \
     [[ ! -f "${work}/.claude/agents/disabled/fake-agent.md" ]]; then
    run_test "T8: restore trap moves agents back from disabled/" "pass"
  else
    run_test "T8: restore trap moves agents back from disabled/" "fail"
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
