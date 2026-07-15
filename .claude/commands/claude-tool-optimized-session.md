---
description: Disable unused MCP plugins/tools based on current session transcript to reduce per-turn token cost, then relaunch
allowed-tools: Bash
model: claude-haiku-4-5-20251001
---

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

# ── Step 1: Find session transcript ──────────────────────────────────────────
project_encoded=$(echo "${CLAUDE_PROJECT_DIR}" | sed 's|^/||' | tr '/' '-')
transcript_dir="$HOME/.claude/projects/${project_encoded}"

if [[ ! -d "$transcript_dir" ]]; then
  echo "ERROR: No transcript directory found at: $transcript_dir"
  exit 1
fi

latest_jsonl=$(find "$transcript_dir" -maxdepth 1 -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null \
  | sort -rn | head -n 1 | awk '{print $2}')

if [[ -z "$latest_jsonl" ]]; then
  echo "ERROR: No .jsonl transcript found in: $transcript_dir"
  exit 1
fi

# ── Step 2: Extract used tools ────────────────────────────────────────────────
used_tools=$(python3 - "$latest_jsonl" <<'PYEOF'
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
)

if [[ "$used_tools" == "__SCHEMA_MISMATCH__" ]]; then
  echo "ERROR: No tool_use records found in transcript — schema mismatch or empty session."
  echo "  Transcript: $latest_jsonl"
  exit 1
fi

# ── Step 3: Build loaded set from ~/.claude/settings.json ────────────────────
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

# ── Step 4: Identify unused local agents/skills ───────────────────────────────
used_agents_from_transcript=$(python3 - "$latest_jsonl" <<'PYEOF'
import json, sys
path = sys.argv[1]
used = set()
def scan(obj):
  if isinstance(obj, dict):
    if obj.get("type") == "tool_use" and obj.get("name") == "Agent":
      st = (obj.get("input") or {}).get("subagent_type", "")
      if st: used.add(st)
    for v in obj.values(): scan(v)
  elif isinstance(obj, list):
    for item in obj: scan(item)
with open(path) as f:
  for line in f:
    line = line.strip()
    if not line: continue
    try: scan(json.loads(line))
    except json.JSONDecodeError: continue
for t in sorted(used): print(t)
PYEOF
)

used_skills_from_transcript=$(python3 - "$latest_jsonl" <<'PYEOF'
import json, sys
path = sys.argv[1]
used = set()
def scan(obj):
  if isinstance(obj, dict):
    if obj.get("type") == "tool_use" and obj.get("name") == "Skill":
      sk = (obj.get("input") or {}).get("skill", "")
      if sk: used.add(sk)
    for v in obj.values(): scan(v)
  elif isinstance(obj, list):
    for item in obj: scan(item)
with open(path) as f:
  for line in f:
    line = line.strip()
    if not line: continue
    try: scan(json.loads(line))
    except json.JSONDecodeError: continue
for t in sorted(used): print(t)
PYEOF
)

local_agents=()
if [[ -d "${CLAUDE_PROJECT_DIR}/.claude/agents" ]]; then
  while IFS= read -r f; do
    local_agents+=("$(basename "$f" .md)")
  done < <(find "${CLAUDE_PROJECT_DIR}/.claude/agents" -maxdepth 1 -name "*.md" 2>/dev/null || true)
fi

local_skills=()
if [[ -d "${CLAUDE_PROJECT_DIR}/.claude/skills" ]]; then
  while IFS= read -r d; do
    local_skills+=("$(basename "$d")")
  done < <(find "${CLAUDE_PROJECT_DIR}/.claude/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null || true)
fi

unused_agents=()
for agent in "${local_agents[@]:-}"; do
  [[ -z "$agent" ]] && continue
  if ! echo "$used_agents_from_transcript" | grep -qx "$agent"; then
    unused_agents+=("$agent")
  fi
done

unused_skills=()
for skill in "${local_skills[@]:-}"; do
  [[ -z "$skill" ]] && continue
  if ! echo "$used_skills_from_transcript" | grep -qx "$skill"; then
    unused_skills+=("$skill")
  fi
done

# ── Step 5: Compute candidates ────────────────────────────────────────────────
plugin_used_by_tools() {
  local plugin="$1"
  local base="${plugin%%@*}"  # strip @package suffix: context-mode@context-mode → context-mode
  case "$base" in
    ecc)             echo "$used_tools" | grep -qE '^(Agent|Skill|Workflow)$' && return 0 ;;
    context-mode)    echo "$used_tools" | grep -qE '^ctx_' && return 0 ;;
    chrome-devtools) echo "$used_tools" | grep -q 'chrome.devtools' && return 0 ;;
    context7)        echo "$used_tools" | grep -q 'context7' && return 0 ;;
    Gmail)           echo "$used_tools" | grep -qi 'gmail' && return 0 ;;
  esac
  echo "$used_tools" | grep -qi "$base" && return 0
  return 1
}

unused_plugins=()
for plugin in "${loaded_plugins[@]:-}"; do
  [[ -z "$plugin" ]] && continue
  if ! plugin_used_by_tools "$plugin"; then
    unused_plugins+=("$plugin")
  fi
done

unused_mcp=()
for mcp in "${loaded_mcp[@]:-}"; do
  [[ -z "$mcp" ]] && continue
  if ! echo "$used_tools" | grep -qi "$mcp"; then
    unused_mcp+=("$mcp")
  fi
done

context_mode_active=false
for p in "${loaded_plugins[@]:-}"; do
  [[ "$p" == "context-mode" ]] && context_mode_active=true
done

# Sanity guard: warn if >75% of loaded items would be disabled
total_loaded=$(( ${#loaded_plugins[@]:-0} + ${#loaded_mcp[@]:-0} ))
total_unused=$(( ${#unused_plugins[@]:-0} + ${#unused_mcp[@]:-0} ))

if [[ $total_loaded -gt 0 && $total_unused -gt 0 ]]; then
  pct=$(( total_unused * 100 / total_loaded ))
  if [[ $pct -gt 75 ]] && ! $FORCE; then
    echo "WARNING: ${total_unused}/${total_loaded} loaded items (${pct}%) would be disabled."
    echo "  This seems unusually high. Re-run with --force to proceed."
    exit 1
  fi
fi

# ── Step 6: Apply ─────────────────────────────────────────────────────────────
if ! $DRY_RUN; then
  project_settings="${CLAUDE_PROJECT_DIR}/.claude/settings.json"

  # Dirty-file guard
  if ! $FORCE && [[ -f "$project_settings" ]]; then
    if ! git -C "${CLAUDE_PROJECT_DIR}" diff --quiet "$project_settings" 2>/dev/null; then
      echo "ERROR: .claude/settings.json has uncommitted changes. Commit or stash first, or use --force."
      exit 1
    fi
  fi

  # Register restore trap BEFORE any moves
  restore() {
    find "${CLAUDE_PROJECT_DIR}/.claude/agents/disabled" -name "*.md" 2>/dev/null \
      -exec mv {} "${CLAUDE_PROJECT_DIR}/.claude/agents/" \; || true
    find "${CLAUDE_PROJECT_DIR}/.claude/skills/disabled" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
      -exec mv {} "${CLAUDE_PROJECT_DIR}/.claude/skills/" \; || true
  }
  trap restore EXIT

  # Write project settings
  mkdir -p "$(dirname "$project_settings")"
  python3 - "$project_settings" <<PYEOF
import json, sys, os

path = sys.argv[1]
plugins_to_disable = [p for p in """${unused_plugins[*]:-}""".split() if p]
mcp_to_disable     = [m for m in """${unused_mcp[*]:-}""".split() if m]

settings = {}
if os.path.exists(path):
  with open(path) as f:
    settings = json.load(f)

ep = settings.setdefault("enabledPlugins", {})
for p in plugins_to_disable:
  ep[p] = False

disabled_mcp = settings.setdefault("disabledMcpjsonServers", [])
for m in mcp_to_disable:
  if m not in disabled_mcp:
    disabled_mcp.append(m)

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

  # Move unused agents/skills
  if [[ ${#unused_agents[@]:-0} -gt 0 ]]; then
    mkdir -p "${CLAUDE_PROJECT_DIR}/.claude/agents/disabled"
    for agent in "${unused_agents[@]:-}"; do
      [[ -z "$agent" ]] && continue
      src="${CLAUDE_PROJECT_DIR}/.claude/agents/${agent}.md"
      [[ -f "$src" ]] && mv -n "$src" "${CLAUDE_PROJECT_DIR}/.claude/agents/disabled/"
    done
  fi

  if [[ ${#unused_skills[@]:-0} -gt 0 ]]; then
    mkdir -p "${CLAUDE_PROJECT_DIR}/.claude/skills/disabled"
    for skill in "${unused_skills[@]:-}"; do
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

# ── Step 7: Print summary ─────────────────────────────────────────────────────
echo ""
echo "CLAUDE TOOL OPTIMIZER — SESSION ANALYSIS"
echo "(reflects tool usage up to command invocation)"
echo ""

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

if [[ ${#unused_plugins[@]:-0} -gt 0 ]] || [[ ${#unused_mcp[@]:-0} -gt 0 ]]; then
  echo "DISABLED  MCP/Plugins"
  for p in "${unused_plugins[@]:-}"; do
    [[ -z "$p" ]] && continue
    hint=$(token_hint "$p")
    printf "  %-24s plugin   %s\n" "$p" "$hint"
  done
  for m in "${unused_mcp[@]:-}"; do
    [[ -z "$m" ]] && continue
    printf "  %-24s mcp\n" "$m"
  done
  echo ""
fi

if [[ ${#unused_agents[@]:-0} -gt 0 ]] || [[ ${#unused_skills[@]:-0} -gt 0 ]]; then
  echo "DISABLED  Agents/Skills"
  for a in "${unused_agents[@]:-}"; do
    [[ -z "$a" ]] && continue
    printf "  %-24s agent    → .claude/agents/disabled/\n" "$a"
  done
  for s in "${unused_skills[@]:-}"; do
    [[ -z "$s" ]] && continue
    printf "  %-24s skill    → .claude/skills/disabled/\n" "$s"
  done
  echo ""
fi

kept_any=false
for p in "${loaded_plugins[@]:-}"; do
  [[ -z "$p" ]] && continue
  is_unused=false
  for u in "${unused_plugins[@]:-}"; do [[ "$u" == "$p" ]] && is_unused=true && break; done
  if ! $is_unused; then
    if ! $kept_any; then echo "KEPT"; kept_any=true; fi
    printf "  %-24s plugin   (active)\n" "$p"
  fi
done
for m in "${loaded_mcp[@]:-}"; do
  [[ -z "$m" ]] && continue
  is_unused=false
  for u in "${unused_mcp[@]:-}"; do [[ "$u" == "$m" ]] && is_unused=true && break; done
  if ! $is_unused; then
    if ! $kept_any; then echo "KEPT"; kept_any=true; fi
    printf "  %-24s mcp      (active)\n" "$m"
  fi
done
$kept_any && echo ""

if $context_mode_active; then
  echo "NOTE: WebFetch is redundant when context-mode is active (ctx_fetch_and_index covers it)."
fi
echo "NOTE: ~2,000 more tokens/turn via tweakcc built-in tool trimming (manual setup)."

if $DRY_RUN; then
  echo ""
  echo "(dry-run — no changes written)"
  exit 0
fi

echo ""
echo "Restore: git checkout .claude/agents/ .claude/skills/ .claude/settings.json"
echo ""
echo "→ Start a new Claude session to apply these changes."
```

Print the output verbatim.
