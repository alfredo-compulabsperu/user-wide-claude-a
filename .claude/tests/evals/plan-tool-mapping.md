# Eval: Plan Tool Mapping

Tests for the LLM reasoning step in `/claude-tool-optimized-plan`.

**Pass condition**: model's `REQUIRED_PLUGINS` ⊇ `expected_required` AND `DISABLED_PLUGINS`+`DISABLED_MCP` ⊇ `expected_disabled`.

**How to run**: open a Claude session → `/claude-tool-optimized-plan --dry-run <input>` → compare output against expected columns below.

---

## E1 — File-editing only plan

**Input**: `.claude/tests/fixtures/plan_file_editing.plan.md`

| Column | Expected values |
|--------|----------------|
| `expected_required` | Bash, Read, Edit, Write |
| `expected_disabled` | ecc@ecc, chrome-devtools, Gmail |
| `expected_kept` | context-mode (if loaded) |

**Rationale**: plan has only Read/Edit/Write/Bash tasks; no web, no agents, no notebooks.

---

## E2 — Research task

**Input** (free-form): `"research and summarize the Claude API docs"`

| Column | Expected values |
|--------|----------------|
| `expected_required` | ctx_fetch_and_index, ctx_search (context-mode plugin) |
| `expected_disabled` | chrome-devtools, Gmail |
| `expected_kept` | context-mode, context7 |
| `expected_notes` | WebFetch should NOT appear as required — redundant with context-mode |

**Rationale**: web research task only; no file editing, no agents, no notebooks.

---

## E3 — Test suite run

**Input** (free-form): `"run the test suite and fix failures"`

| Column | Expected values |
|--------|----------------|
| `expected_required` | Bash, Read, Edit, Write |
| `expected_disabled` | ecc@ecc, chrome-devtools, Gmail, context7 |
| `expected_kept` | (none required beyond built-ins) |

**Rationale**: running tests and fixing code is pure Bash + file editing; no web research, no agents.

---

## E4 — PR review with agents

**Input** (free-form): `"review the PR and spawn specialist agents"`

| Column | Expected values |
|--------|----------------|
| `expected_required` | Agent, ecc@ecc, Bash |
| `expected_disabled` | chrome-devtools, Gmail |
| `expected_kept` | ecc@ecc (needed for agent spawning) |

**Rationale**: task explicitly spawns agents → ecc@ecc required; GitHub PR work uses Bash (gh CLI).

---

## Scoring

- **PASS**: output's required set ⊇ expected_required AND disabled set ⊇ expected_disabled
- **FAIL**: any expected_required item missing from REQUIRED output, OR any expected_disabled item missing from DISABLED output
- **WARN**: extra items disabled beyond expected (overly aggressive — note but don't fail)

---

## Eval Run: 2026-06-18

**Environment**: plugins loaded = `ecc@ecc`, `context-mode@context-mode` (no chrome-devtools, context7, or Gmail in this env).

**Bug found & fixed**: `plugin_used_by_tools()` and `token_hint()` used bare names (`context-mode`) but settings keys use `name@package` format (`context-mode@context-mode`). Fixed by stripping `@suffix` with `${plugin%%@*}` before case-matching in both command files.

| Eval | Result | Notes |
|------|--------|-------|
| E1 | PASS | ecc@ecc + context-mode@context-mode disabled; 100% sanity guard fires — expected, use `--force` |
| E2 | PASS | context-mode@context-mode kept; ecc@ecc disabled (~2,800 tokens/turn hint correct after fix) |
| E3 | PASS | Same as E1; sanity guard fires — expected |
| E4 | PASS | ecc@ecc kept for agent spawning; context-mode@context-mode disabled |
