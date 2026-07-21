---
description: Disable MCP plugins/tools not needed for a given task or plan file to reduce per-turn token cost, then launch
allowed-tools: Bash, Read
model: claude-haiku-4-5-20251001
---

Analyze the task or plan to determine which tools are needed, then disable the rest.

## Step 1 — Read input

`$ARGUMENTS` contains either a file path or a free-form task description.

- If `$ARGUMENTS` is empty: respond "Describe the task or provide a plan file path." and stop.
- If `$ARGUMENTS` looks like a file path (contains `/` or ends in `.md`): read the file at that path.
- Otherwise: treat `$ARGUMENTS` as the task description directly.

## Step 2 — Analyze required tools

Using the task content, determine which tools the task will need. Apply this mapping:

| Task signal | Tools needed |
|---|---|
| Edit/write files | Read, Edit, Write, Bash |
| Run tests / shell commands | Bash |
| Web research / fetch docs | ctx_fetch_and_index, ctx_search (NOT WebFetch — redundant with context-mode) |
| Spawn subagents / workflows | Agent, Workflow, ecc@ecc plugin |
| GitHub operations | Bash (gh CLI) |
| Notebook editing | NotebookEdit |
| No web, no agents | disable: ecc@ecc, context7, chrome-devtools, Gmail |

Identify which loaded plugins/MCP servers are NOT needed. Also identify which local agents in `.claude/agents/` and skills in `.claude/skills/` are irrelevant to this task.

## Step 3 — Output your analysis as shell variables

Output exactly this block (fill in the values from your analysis):

```
REQUIRED_PLUGINS="<space-separated plugin names needed>"
DISABLED_PLUGINS="<space-separated plugin names to disable>"
DISABLED_MCP="<space-separated MCP server names to disable>"
DISABLED_AGENTS="<space-separated agent filenames without .md to move to disabled/>"
DISABLED_SKILLS="<space-separated skill directory names to move to disabled/>"
TASK_SUMMARY="<one-line summary of the task>"
```

## Step 4 — Apply and report

```bash
set -euo pipefail

DRY_RUN=false
FORCE=false
for arg in $ARGUMENTS; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --force)   FORCE=true ;;
  esac
done

settings_file="$HOME/.claude/settings.json"
loaded_plugins=()
loaded_mcp=()

if [[ -f "$settings_file" ]]; then
  mapfile -t loaded_plugins < <(python3 - "$settings_file" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
  s = json.load(f)
for k, v in s.get("enabledPlugins", {}).items():
  if v is True:
    print(k)
PYEOF
  )

  mapfile -t loaded_mcp < <(python3 - "$settings_file" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
  s = json.load(f)
disabled = s.get("disabledMcpjsonServers", [])
for k in s.get("mcpServers", {}):
  if k not in disabled:
    print(k)
PYEOF
  )
fi

# Sanity guard: warn if >75% would be disabled
total_loaded=$(( ${#loaded_plugins[@]:-0} + ${#loaded_mcp[@]:-0} ))
disabled_plugins_arr=($DISABLED_PLUGINS)
disabled_mcp_arr=($DISABLED_MCP)
total_disabled=$(( ${#disabled_plugins_arr[@]:-0} + ${#disabled_mcp_arr[@]:-0} ))

if [[ $total_loaded -gt 0 && $total_disabled -gt 0 ]]; then
  pct=$(( total_disabled * 100 / total_loaded ))
  if [[ $pct -gt 75 ]] && ! $FORCE; then
    echo "WARNING: ${total_disabled}/${total_loaded} loaded items (${pct}%) would be disabled."
    echo "  Re-run with --force to proceed."
    exit 1
  fi
fi

if ! $DRY_RUN; then
  project_settings="${CLAUDE_PROJECT_DIR}/.claude/settings.json"
  mkdir -p "$(dirname "$project_settings")"

  # Register restore trap BEFORE any moves
  restore() {
    find "${CLAUDE_PROJECT_DIR}/.claude/agents/disabled" -name "*.md" 2>/dev/null \
      -exec mv {} "${CLAUDE_PROJECT_DIR}/.claude/agents/" \; || true
    find "${CLAUDE_PROJECT_DIR}/.claude/skills/disabled" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
      -exec mv {} "${CLAUDE_PROJECT_DIR}/.claude/skills/" \; || true
  }
  trap restore EXIT

  python3 - "$project_settings" <<PYEOF
import json, sys, os

path = sys.argv[1]
plugins_to_disable = [p for p in """${DISABLED_PLUGINS}""".split() if p]
mcp_to_disable     = [m for m in """${DISABLED_MCP}""".split() if m]

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

  # Validate JSON
  if ! python3 -m json.tool "$project_settings" > /dev/null 2>&1; then
    echo "ERROR: settings.json is invalid JSON after write — restoring."
    git -C "${CLAUDE_PROJECT_DIR}" checkout -- "$project_settings" 2>/dev/null || rm -f "$project_settings"
    exit 1
  fi

  # Move unused agents
  disabled_agents_arr=($DISABLED_AGENTS)
  if [[ ${#disabled_agents_arr[@]:-0} -gt 0 ]]; then
    mkdir -p "${CLAUDE_PROJECT_DIR}/.claude/agents/disabled"
    for agent in "${disabled_agents_arr[@]:-}"; do
      [[ -z "$agent" ]] && continue
      src="${CLAUDE_PROJECT_DIR}/.claude/agents/${agent}.md"
      [[ -f "$src" ]] && mv -n "$src" "${CLAUDE_PROJECT_DIR}/.claude/agents/disabled/"
    done
  fi

  # Move unused skills
  disabled_skills_arr=($DISABLED_SKILLS)
  if [[ ${#disabled_skills_arr[@]:-0} -gt 0 ]]; then
    mkdir -p "${CLAUDE_PROJECT_DIR}/.claude/skills/disabled"
    for skill in "${disabled_skills_arr[@]:-}"; do
      [[ -z "$skill" ]] && continue
      src="${CLAUDE_PROJECT_DIR}/.claude/skills/${skill}"
      [[ -d "$src" ]] && mv -n "$src" "${CLAUDE_PROJECT_DIR}/.claude/skills/disabled/"
    done
  fi

  # Gitignore disabled/ folders
  gitignore="${CLAUDE_PROJECT_DIR}/.gitignore"
  touch "$gitignore"
  grep -qxF '.claude/agents/disabled/' "$gitignore" || echo '.claude/agents/disabled/' >> "$gitignore"
  grep -qxF '.claude/skills/disabled/' "$gitignore" || echo '.claude/skills/disabled/' >> "$gitignore"
fi

echo ""
echo "CLAUDE TOOL OPTIMIZER — PLAN ANALYSIS"
echo "Task: ${TASK_SUMMARY:-<from input>}"
echo ""

echo "REQUIRED"
for r in ${REQUIRED_PLUGINS:-}; do
  printf "  %-24s plugin   (needed)\n" "$r"
done
echo "  Bash, Read, Edit, Write   built-in  (always available)"
echo ""

if [[ -n "${DISABLED_PLUGINS:-}" ]] || [[ -n "${DISABLED_MCP:-}" ]]; then
  echo "DISABLED"
  token_hint() {
    local base="${1%%@*}"
    case "$base" in
      ecc)             echo "~2,800 tokens/turn" ;;
      chrome-devtools) echo "~1,200 tokens/turn" ;;
      context7)        echo "~400 tokens/turn" ;;
      Gmail)           echo "~300 tokens/turn" ;;
      *)               echo "" ;;
    esac
  }
  for p in ${DISABLED_PLUGINS:-}; do
    hint=$(token_hint "$p")
    printf "  %-24s plugin   %s\n" "$p" "$hint"
  done
  for m in ${DISABLED_MCP:-}; do
    printf "  %-24s mcp      unused for this task\n" "$m"
  done
  echo ""
fi

if $DRY_RUN; then
  echo "(dry-run — no changes written)"
  exit 0
fi

echo "Updated: .claude/settings.json"
echo "Restore: git checkout .claude/settings.json .claude/agents/ .claude/skills/"
```

## Step 5 — Prompt to launch

Print this line verbatim:

```
→ Start a new Claude session to apply these changes.
```

Print all output verbatim.
