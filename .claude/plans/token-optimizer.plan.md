# Plan: Token Optimizer Commands

**Complexity**: Small

## Summary

Two Claude commands that reduce per-turn token cost by disabling unused tools.
`claude-tool-optimized-session` looks backward (what did we use this session?).
`claude-tool-optimized-plan` looks forward (what will a given task need?).

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Naming | `.claude/commands/open-claude.md:1` | kebab-case filename, YAML frontmatter with `description` + `allowed-tools` |
| Model | `.claude/commands/open-claude.md:5` | `model: claude-haiku-4-5-20251001` for cheap utility commands |
| Tests | `.claude/tests/scripts/open-claude.test.sh:16` | `run_test name pass/fail` harness; mock binaries in `MOCK_BIN` via `mktemp -d` |

---

## Key Research

- MCP tool schemas are sent on every API request even if never called
- `enabledPlugins: false` + `disabledMcpjsonServers` in project `.claude/settings.json` override global settings — scoped, git-tracked, no global side effects
- Agent listings are interpolated into the system prompt every turn (~35 tokens/agent; 80+ ECC agents ≈ 2,800 tokens/turn)
- Agents and skills ship with their plugin — disabling `ecc@ecc` removes all 80+ agents
- Built-in tool descriptions (~2,000–3,500 tokens/turn for unused tools) require tweakcc to trim — out of scope; documented as a note in command output
- cc-mirror creates isolated native Claude Code variants per project (downloads from Anthropic CDN, not npm); out of scope
- `context-mode` plugin makes `WebFetch` redundant — treat as a known static redundancy

---

## Initial Scope

| File | Action | Why |
|---|---|---|
| `.claude/commands/claude-tool-optimized-session.md` | CREATE | Backward-looking command |
| `.claude/commands/claude-tool-optimized-plan.md` | CREATE | Forward-looking command |

No bash scripts needed — both commands embed logic as Claude instructions with inline bash/python blocks.

---

## Implementation Detail

> The sections below are the authoritative per-command spec. `## Tasks` above is the completion checklist; these sections are the source of truth for guard logic, flags, and edge cases.

## Command 1: `claude-tool-optimized-session`

**Trigger**: `/claude-tool-optimized-session [--dry-run] [--force]`

### Step 1 — Find session transcript

Derive path from `$CLAUDE_PROJECT_DIR`:
```bash
project_encoded=$(echo "${CLAUDE_PROJECT_DIR}" | sed 's|^/||' | tr '/' '-')
transcript_dir="$HOME/.claude/projects/${project_encoded}"
```
Pick most-recently-modified `.jsonl`. Abort if none found.

### Step 2 — Extract used tools

Parse JSONL for `{"type": "tool_use", "name": "..."}` records → used set.
Abort if zero `tool_use` records found (schema mismatch guard).

### Step 3 — Build loaded set

Read `~/.claude/settings.json`. If absent, treat loaded set as empty and proceed (no plugins or MCP servers to disable):
- `enabledPlugins` keys where value is `true`
- `mcpServers` keys not in `disabledMcpjsonServers`

### Step 4 — Identify unused local agents/skills

```bash
[ -d "${CLAUDE_PROJECT_DIR}/.claude/agents" ] && \
  find "${CLAUDE_PROJECT_DIR}/.claude/agents" -maxdepth 1 -name "*.md"
[ -d "${CLAUDE_PROJECT_DIR}/.claude/skills" ] && \
  find "${CLAUDE_PROJECT_DIR}/.claude/skills" -maxdepth 1 -mindepth 1 -type d
```
Cross-reference: agent used if its type appears in `Agent` tool calls; skill used if its name appears in `Skill` tool calls.

### Step 5 — Compute candidates

- Plugins: loaded ∩ ¬used
- MCP servers: loaded ∩ ¬used
- Static redundancy: if `context-mode` active → flag `WebFetch` as redundant (report only; built-in, not disableable via settings)
- Agents: installed ∩ ¬invoked
- Skills: installed ∩ ¬invoked

**Sanity guard**: if `|candidates| / |loaded| > 0.75` → warn + require `--force`

### Step 6 — Apply

**Dirty-file guard** (skip with `--force`):
```bash
git -C "${CLAUDE_PROJECT_DIR}" diff --quiet .claude/settings.json 2>/dev/null || abort
```

**Write project settings** (start from `{}` if file absent):
- Set `enabledPlugins[name] = false` for each candidate plugin
- Append candidate MCP servers to `disabledMcpjsonServers`

**Validate JSON** after write: `python3 -m json.tool .claude/settings.json`
If invalid → `git checkout .claude/settings.json` + abort.

**Register restore trap before moving** (ensures auto-restore even if later steps abort):
```bash
restore() {
  find "${CLAUDE_PROJECT_DIR}/.claude/agents/disabled" -name "*.md" \
    -exec mv {} "${CLAUDE_PROJECT_DIR}/.claude/agents/" \;
  find "${CLAUDE_PROJECT_DIR}/.claude/skills/disabled" -mindepth 1 -maxdepth 1 -type d \
    -exec mv {} "${CLAUDE_PROJECT_DIR}/.claude/skills/" \;
}
trap restore EXIT
```

**Move unused agents/skills** (`-n` prevents silent overwrite on repeated runs):
```bash
mkdir -p .claude/agents/disabled .claude/skills/disabled
mv -n .claude/agents/<unused>.md .claude/agents/disabled/
mv -n .claude/skills/<unused>/   .claude/skills/disabled/
```

**Gitignore disabled/ folders**:
```bash
grep -qxF '.claude/agents/disabled/' .gitignore || echo '.claude/agents/disabled/' >> .gitignore
grep -qxF '.claude/skills/disabled/' .gitignore || echo '.claude/skills/disabled/' >> .gitignore
```

### Step 7 — Print summary

```
CLAUDE TOOL OPTIMIZER — SESSION ANALYSIS
(reflects tool usage up to command invocation)

DISABLED  MCP/Plugins
  ecc@ecc              plugin   ~2,800 tokens/turn
  chrome-devtools      mcp      ~1,200 tokens/turn

DISABLED  Agents/Skills
  ecc:code-reviewer    agent    → .claude/agents/disabled/

KEPT
  context-mode         plugin   used: ctx_fetch_and_index, ctx_search
  Bash, Read, Edit     built-in used this session

NOTE: ~2,000 more tokens/turn via tweakcc built-in trimming (manual setup).
Restore: git checkout .claude/agents/ .claude/skills/ .claude/settings.json
```

### Step 8 — Relaunch (skip if `--dry-run`)

Restore trap was registered in Step 6. Launch a new session for the current project (do NOT forward `$ARGUMENTS` — session flags like `--dry-run`/`--force` are not valid `claude` CLI arguments):
```bash
command -v claude >/dev/null 2>&1 || { echo "ERROR: claude binary not found on PATH"; exit 1; }
claude
```

---

## Command 2: `claude-tool-optimized-plan`

**Trigger**: `/claude-tool-optimized-plan [path/to/plan.md | "task description"] [--dry-run]`

### Input modes

| Input | Behavior |
|---|---|
| Path to `.plan.md` or `.prd.md` | Read file |
| Free-form text via `$ARGUMENTS` | Use directly |
| No args | Ask: "Describe the task or provide a plan path" |

### Step 1 — Read input

If argument is a file path → Read it. Otherwise use `$ARGUMENTS` as the task description.

### Step 2 — Analyze required tools (LLM reasoning)

Read the input and determine which tools the task will need, using this mapping as a guide:

| Task signal | Tools needed |
|---|---|
| Edit/write files | Read, Edit, Write, Bash |
| Run tests / shell commands | Bash |
| Web research / fetch docs | ctx_fetch_and_index, ctx_search (NOT WebFetch — redundant with context-mode) |
| Spawn subagents / workflows | Agent, Workflow, ecc@ecc plugin |
| GitHub operations | Bash (gh CLI) |
| Notebook editing | NotebookEdit |
| No web, no agents | disable: ecc@ecc, context7, chrome-devtools, Gmail |

Also check: which local agents/skills in `.claude/agents/` and `.claude/skills/` are relevant to the task.

### Step 3 — Compute what to disable

Everything loaded globally (from `~/.claude/settings.json`) not in the required set.
Apply same sanity guard: warn if >75% would be disabled.

### Step 4 — Apply (same mechanism as Session command Steps 6–7)

Register restore trap before any writes (LLM reasoning in Step 2 may misclassify; trap ensures auto-restore on exit):
```bash
restore() {
  find "${CLAUDE_PROJECT_DIR}/.claude/agents/disabled" -name "*.md" \
    -exec mv {} "${CLAUDE_PROJECT_DIR}/.claude/agents/" \;
  find "${CLAUDE_PROJECT_DIR}/.claude/skills/disabled" -mindepth 1 -maxdepth 1 -type d \
    -exec mv {} "${CLAUDE_PROJECT_DIR}/.claude/skills/" \;
}
trap restore EXIT
```

Write overrides to `.claude/settings.json`.
Move irrelevant local agents/skills to `disabled/` using `mv -n` (no-clobber).
Gitignore disabled/ folders.

### Step 5 — Print summary

```
CLAUDE TOOL OPTIMIZER — PLAN ANALYSIS
Task: <one-line summary of input>

REQUIRED
  Bash, Read, Edit, Write   built-in  file editing
  context-mode              plugin    doc research

DISABLED
  ecc@ecc                   plugin    ~2,800 tokens/turn
  chrome-devtools           mcp       ~1,200 tokens/turn
  Gmail                     mcp       unused for this task

Updated: .claude/settings.json
Restore: git checkout .claude/settings.json .claude/agents/ .claude/skills/
```

### Step 6 — Launch (skip if `--dry-run`)

Launch a new session for the current project (do NOT forward `$ARGUMENTS` — the plan path or task description is not a valid `claude` CLI argument):
```bash
command -v claude >/dev/null 2>&1 || { echo "ERROR: claude binary not found on PATH"; exit 1; }
claude
```

---

## Shared Guards

| Guard | Condition | Response |
|---|---|---|
| No transcript | Step 1 session command | Abort with path shown |
| Empty tool_use set | Step 2 session command | Abort — schema mismatch |
| >75% disable candidates | Step 5 both commands | Warn + require `--force` |
| Dirty settings.json | Step 6 session command | Abort or `--force` |
| Invalid JSON after write | Step 6 both commands | git restore + abort |
| Missing `claude` binary | Launch step | `command -v claude` check + clear error |

---

## Flags

| Flag | Applies to |
|---|---|
| `--dry-run` | Both — print plan only; skip writes and launch |
| `--force` | Both — skip dirty-file and large-disable-list guards |

---

---

## Testing

### Integration tests (bash) — deterministic, no model

One test file per command, following `.claude/tests/scripts/<command-name>.test.sh` convention.
Fixtures are created inline via `mktemp` / heredocs (no separate fixtures directory).

**Files**:
- `.claude/tests/scripts/claude-tool-optimized-session.test.sh`
- `.claude/tests/scripts/claude-tool-optimized-plan.test.sh`

Fixtures live in `.claude/tests/fixtures/`.

| ID | File | Setup | Expected |
|---|---|---|---|
| T1 | session | `fixtures/session_two_tools.jsonl`; `--dry-run` | prints candidates, no file writes |
| T2 | session | `fixtures/session_two_tools.jsonl` + `fixtures/settings_minimal.json` (live) | writes overrides, `disabled/` created |
| T3 | session | `fixtures/session_empty.jsonl` | aborts with schema-mismatch error |
| T4 | session | dirty `settings.json` (unstaged edit in temp git repo) | aborts unless `--force` |
| T5 | session | `fixtures/settings_many_tools.json` (>75% unused) | warns + requires `--force` |
| T6 | session | simulate invalid JSON after write | git restore runs, abort |
| T7 | plan | `fixtures/plan_file_editing.plan.md`; `--dry-run` | prints disable list, no writes |
| T8 | plan | `fixtures/plan_file_editing.plan.md` + `fixtures/settings_minimal.json` (live) | writes overrides, `disabled/` created, restore trap registered |

### Evals (LLM) — non-deterministic, run manually

**File**: `.claude/tests/evals/plan-tool-mapping.md`

Pass = model's required set ⊇ expected_required AND disabled set ⊇ expected_disabled.

| Eval | Input | Expected required | Expected disabled |
|---|---|---|---|
| E1 | plan with only Read/Edit/Write/Bash tasks | Bash, Read, Edit, Write | ecc@ecc, chrome-devtools, Gmail |
| E2 | `"research and summarize the Claude API docs"` | ctx_fetch_and_index, ctx_search | chrome-devtools, Gmail |
| E3 | `"run the test suite and fix failures"` | Bash | ecc@ecc, chrome-devtools, Gmail, context7 |
| E4 | `"review the PR and spawn specialist agents"` | Agent, ecc@ecc, Bash | chrome-devtools, Gmail |

Run: open a Claude session → `/claude-tool-optimized-plan --dry-run <input>` → compare output against expected columns.

---

## Files to Change

| File | Action | Why |
|---|---|---|
| `.claude/commands/claude-tool-optimized-session.md` | CREATE | Backward-looking command |
| `.claude/commands/claude-tool-optimized-plan.md` | CREATE | Forward-looking command |
| `.claude/tests/scripts/claude-tool-optimized-session.test.sh` | CREATE | Bash integration tests T1–T6 |
| `.claude/tests/scripts/claude-tool-optimized-plan.test.sh` | CREATE | Bash integration tests T7–T8 |
| `.claude/tests/fixtures/session_two_tools.jsonl` | CREATE | Transcript with Bash + Read tool_use records |
| `.claude/tests/fixtures/session_empty.jsonl` | CREATE | Transcript with no tool_use records |
| `.claude/tests/fixtures/settings_minimal.json` | CREATE | Settings with ecc@ecc + context-mode + chrome-devtools |
| `.claude/tests/fixtures/settings_many_tools.json` | CREATE | Settings with >75% tools unused (for T5) |
| `.claude/tests/fixtures/plan_file_editing.plan.md` | CREATE | Plan requiring only Read/Edit/Write/Bash |
| `.claude/tests/evals/plan-tool-mapping.md` | CREATE | Eval cases E1–E4 for plan command LLM step |

---

## Tasks

### Task 1: claude-tool-optimized-session.md
- **Action**: Write the backward-looking command — 8-step flow: find transcript → parse tool_use records → build loaded set → identify unused local agents/skills → compute candidates with sanity guard → apply settings overrides + move agents/skills + gitignore disabled/ → print summary → relaunch with restore trap
- **Mirror**: `.claude/commands/open-claude.md:1` — YAML frontmatter with `description`, `allowed-tools: Bash`, `model: claude-haiku-4-5-20251001`
- **Validate**: `--dry-run` produces output with no file writes; abort paths trigger on missing transcript / empty tool_use / dirty settings.json

### Task 2: claude-tool-optimized-plan.md
- **Action**: Write the forward-looking command — 6-step flow: read input (file or free-form) → LLM tool-mapping reasoning using signal table → compute disable set with sanity guard → apply settings overrides → print summary → launch
- **Mirror**: `.claude/commands/open-claude.md:1` — same frontmatter pattern; haiku model
- **Validate**: `--dry-run` prints disable list without file writes; E1–E4 evals pass manually

### Task 3: Integration tests + fixtures
- **Action**: Write `.claude/tests/scripts/claude-tool-optimized-session.test.sh` (T1–T6) and `.claude/tests/scripts/claude-tool-optimized-plan.test.sh` (T7–T8) plus fixture files under `.claude/tests/fixtures/`
- **Mirror**: `.claude/tests/scripts/open-claude.test.sh:16` — `run_test name pass/fail` harness, mock binaries in `MOCK_BIN` via `mktemp -d`
- **Validate**: `bash .claude/tests/scripts/claude-tool-optimized-session.test.sh && bash .claude/tests/scripts/claude-tool-optimized-plan.test.sh`

### Task 4: Eval cases
- **Action**: Write `.claude/tests/evals/plan-tool-mapping.md` with E1–E4 cases (input / expected_required / expected_disabled triples)
- **Mirror**: No existing pattern — follow format established in `## Testing` section of this plan
- **Validate**: Run manually: open Claude session → `/claude-tool-optimized-plan --dry-run <input>` → verify required/disabled columns match

## Validation

```bash
# Integration tests
bash .claude/tests/scripts/claude-tool-optimized-session.test.sh
bash .claude/tests/scripts/claude-tool-optimized-plan.test.sh
```

---

## Acceptance

- [ ] `--dry-run` prints candidates without writing or launching
- [ ] Aborts with clear error when transcript missing or schema mismatches (session command)
- [ ] Aborts when disable list >75% without `--force`
- [ ] Aborts when `settings.json` dirty without `--force` (session command)
- [ ] Post-write JSON validation runs; restores on failure
- [ ] Agents/skills restored automatically on Claude exit (session command)
- [ ] `disabled/` folders added to `.gitignore`
- [ ] Plan command correctly identifies required tools from a sample plan
- [ ] `.claude/tests/scripts/claude-tool-optimized-session.test.sh` passes T1–T6 cleanly
- [ ] `.claude/tests/scripts/claude-tool-optimized-plan.test.sh` passes T7–T8 cleanly
- [ ] E1–E4 evals pass manually against the live command
