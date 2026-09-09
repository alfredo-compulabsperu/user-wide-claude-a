---
paths:
  - ".claude/plans/**/*.md"
---

# Plan / Runbook Pre-Flight Phase

| Rule | Requirement |
|---|---|
| Pre-flight phase | A multi-step instruction artifact (plan, runbook, loop script, ordered task list, or phased implementation guide) MUST include a Pre-flight phase as its first section only if at least one item passes the filter test below. If none do, MUST NOT include the section at all — no empty or "none" placeholder section. |
| Human-only chores | The Pre-flight phase, when present, MUST enumerate only tasks that require human action (credentials, UI clicks, access grants, external system changes) and MUST NOT include tasks Claude can perform autonomously. Filter test per candidate item: "Does this require a human to act in an external system or supply information Claude cannot observe from the filesystem, shell, or environment?" If no, omit it. |
| Gate | If a Pre-flight section exists and all its tasks are marked `[x]`, proceed immediately — no confirmation prompt needed. If any task is `[ ]`, MUST NOT begin until the user replies with "pre-flight done", "pre-flight complete", or an equivalent explicit statement confirming those items are complete. If no Pre-flight section exists (no items passed the filter test), proceed immediately. |

## Tooling Manifest & Availability Gate

| Rule | Requirement |
|---|---|
| Tooling manifest | A plan, runbook, loop script, or phased task list whose steps declare or invoke any plugin, MCP server/tool, or CLI MUST include a `## Tooling` section listing every one of them, with the step(s) needing each one and the one-line check that proves it available. A plan with no such tool in any step MUST NOT include the section (no empty placeholder). When present, placed immediately after Pre-flight if that section exists, otherwise first. |
| Completeness | The manifest MUST list every tool declared or invoked anywhere in the plan's steps — no partial or representative subset. Before treating authoring as done, grep the plan's own step text for tool mentions and reconcile against the manifest's rows; a tool named in a step but missing from the table is a defect, found the same way `plan-cross-reference-integrity.md` requires reconciling renumbered task labels. |
| Tool categories | "Tool" means exactly three things: **plugins** (skills, commands, agents — including those supplied by a plugin marketplace), **MCP servers** (and the specific MCP tools a step calls), and **CLIs** (binaries invoked from the shell). Nothing else belongs in the manifest. |
| Per-category check | Plugin: the skill/command/agent name appears in the session's available-components listing. MCP: the server's tools resolve in this session (listed, or loadable via `ToolSearch`). CLI: `command -v <bin>` succeeds, plus any version floor the plan relies on — and a CLI that is installed but unauthenticated (e.g. `gh auth status` failing, an expired token) counts as UNAVAILABLE, not available. |
| Manifest is not Pre-flight | These checks MUST NOT appear as Pre-flight items — Claude runs them itself, and the human-only rule above forbids listing Claude-verifiable checks there. Only the human-actionable remediation for a failing check (sudo install, browser OAuth login, API key from a vault, enabling a plugin or MCP server the user must approve) becomes a Pre-flight item. |
| Pre-execution gate | If a `## Tooling` section is declared, Claude MUST run every check in it before beginning step 1 and report the results. If any check fails, MUST NOT begin — state which tool is missing, which steps it blocks, and the remediation or proposed substitute, then wait for the user. If no section is declared, no tool gate applies. |
| Mid-execution failure | If a declared tool that passed the pre-check becomes unavailable mid-run (auth expired, MCP server dropped, rate limit, plugin disabled), Claude MUST halt at that step. MUST NOT improvise a substitute, skip the step, or silently degrade to a weaker tool. MUST report the failing tool, the steps completed, and the steps remaining; resuming requires the user's explicit go-ahead. |

### Canonical `## Tooling` section

```markdown
## Tooling

| Tool | Type | Needed by | Availability check |
|---|---|---|---|
| `gh` CLI >= 2.40, authenticated as alfredo-compulabsperu | CLI | Steps 3, 7 | `gh --version` && `gh auth status` |
| `firecrawl` MCP (`firecrawl-scrape`) | MCP | Step 4 | tool resolves in session |
| `ecc:research-ops` | Plugin | Step 2 | listed in available skills |
```
