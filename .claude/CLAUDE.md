# User-Wide Claude Code Rules

## Meta Rules

Rules in this file use RFC 2119 verb definitions:

| Keyword | Meaning |
|---|---|
| **MUST** / **MUST NOT** | Absolute requirement / prohibition. No exceptions. |
| **SHOULD** / **SHOULD NOT** | Strong recommendation. Deviation requires documented justification. |
| **MAY** | Optional. Permitted but not required. |

### DRY — Code

Every piece of logic MUST have one implementation.

- Extract when the same logic appears in two callsites. Abstract when a third appears.
- Helpers MUST NOT be created for a single caller.
- Abstractions MUST NOT be introduced for hypothetical reuse.

---

## Worktree Isolation

| Rule | Requirement |
|---|---|
| Repo changes | MUST NOT modify files outside the current worktree folder unless the user names the target path outside the worktree in the current message. |
| Relative path resolution | MUST always expand relative paths by appending them to the active worktree root. MUST NOT resolve relative paths against the main checkout or CWD. |
| Git submodules | When working with submodules, MUST use the copies under the current worktree (`modules/*` inside the active worktree). MUST NOT operate on submodule copies from other worktrees or the main repo checkout. |

## PR Base Branch

| Rule | Requirement |
|---|---|
| PR target | All PRs MUST target `develop`. MUST NOT target `main` or `master`. |
| Branch semantics | `main` is the released branch; `develop` is the integration/test branch. `main` advances only by promoting `develop` (release merge/tag), never by a feature PR. |
| Review focus | When assessing branch or repo state (ahead/behind, diffs, "what changed"), Claude MUST compare against `develop` first, not `main`. The session default-branch hint MUST NOT override this. |
| Override | A repo's own CLAUDE.md or rule files MAY override this rule (e.g. trunk-based repos where `main` is the integration branch and there is no `develop`). A repo-level PR-base rule takes precedence over this global default. |

## Plan / Runbook Pre-Flight Phase

| Rule | Requirement |
|---|---|
| Pre-flight phase | Every multi-step instruction artifact (plan, runbook, loop script, ordered task list, or phased implementation guide) MUST include a Pre-flight phase as its first section. |
| Human-only chores | The Pre-flight phase MUST enumerate every task that requires human action (credentials, UI clicks, access grants, external system changes) and MUST NOT include tasks Claude can perform autonomously. Before listing any item, apply the filter test: "Does this require a human to act in an external system or supply information Claude cannot observe from the filesystem, shell, or environment?" If no, omit it. |
| Gate | If all Pre-flight tasks are already marked `[x]`, proceed immediately — no confirmation prompt needed. If any task is `[ ]`, MUST NOT begin until the user replies with "pre-flight done", "pre-flight complete", or an equivalent explicit statement confirming those items are complete. |

## Plan Approval Trust

| Rule | Requirement |
|---|---|
| Tool-reported approval | When `ExitPlanMode` (or any approval-gated tool) reports the plan as approved, that is the harness's report of what happened — MUST NOT be treated as independent confirmation the user consciously reviewed it. |
| Disputed approval | If the user later states they did not approve something, Claude MUST NOT argue from the tool's return value. MUST (1) quote exactly what the tool reported, (2) state plainly what has and has not actually been executed since, (3) halt further action until the user explicitly re-confirms. |
| Scope | Applies to any case where a user disputes that they authorized an action the harness reported as approved. |

## Command Scripts

| Rule | Requirement |
|---|---|
| Script location | Bash scripts that `.claude/commands/*.md` files depend on MUST be stored in `.claude/scripts/`. |
| Reference form | Commands MUST invoke them as `bash "${CLAUDE_PROJECT_DIR}/.claude/scripts/<name>"`. MUST NOT reference scripts outside `.claude/scripts/` from a command file. |
| File extension | All bash script files MUST use the `.sh` extension. |

## Hook Path Convention

| Rule | Requirement |
|---|---|
| Hook script paths | MUST use `${CLAUDE_PROJECT_DIR}` as the path prefix for any hook command that references a file inside the project. MUST NOT use absolute paths or bare relative paths. |
| Rationale | `${CLAUDE_PROJECT_DIR}` resolves to the session root in both normal and worktree sessions; bare relative paths fail when hook CWD differs from repo root; absolute paths break on other machines. |
| Correct form | `"command": "cd \"${CLAUDE_PROJECT_DIR}/path/to/dir\" && npm run type-check"` |
| Incorrect forms | `"command": "cd path/to/dir && ..."` (relative) · `"command": "cd /home/user/project/... && ..."` (absolute) <!-- validate-artifact: ignore-line --> |
| Scope | Applies to all hooks in `~/.claude/settings.json`, `.claude/settings.json`, and `.claude/settings.local.json`. |

## Archiving

| Rule | Requirement |
|---|---|
| Move path | When archiving a file, it MUST move to `archived/<original relative path>`, preserving the full original path under an `archived/` root at the same level. |
| Examples | `docs/a.md` → `archived/docs/a.md`. `.a/b.js` → `archived/.a/b.js`. |
| Scope | Applies whenever archiving is requested without an explicit destination path in the current message. An explicit destination path given by the user overrides this default. |

## Knowledge Operations

| Rule | Requirement |
|---|---|
| Default KB path | When using `/ecc:knowledge-ops`, the knowledge base storage location MUST default to `/home/alfredo/knowledge-base/`. Use `projects/` for durable technical notes and runbooks, `sessions/` for session exports. <!-- validate-artifact: ignore-line --> |

## Active Session Hooks

| Hook | Behavior |
|------|----------|
| GateGuard (PreToolUse:Bash) | Before the first Bash call each session, state: (1) the user request in one sentence, (2) what this specific command verifies. |
| context-mode (PreToolUse:Bash) | Prefer `ctx_batch_execute` for research/aggregation; use Bash only for observation or state mutation. |

The Spanish field names in Research Persistence (`Última actualización`, `Generación`, etc.) are intentional — do not "correct" them.

## Research Persistence

| Rule | Requirement |
|---|---|
| No autosave | Research findings MUST NOT be saved automatically. |
| Recommend & prompt | Before the conversation ends, Claude MUST recommend one destination (with a one-line rationale) and prompt the user to choose: (a) the user-wide KB repo or project memory (Layer 2) via `/ecc:knowledge-ops`, or (b) `research/<topic-dir>/<sub-topic>.md` in the active worktree — only when the data is worth storing and shaping within the repo. |
| Headless mode | When running headless (`claude -p`, no interactive user), Claude MUST NOT prompt and MUST auto-apply its own recommendation. |
| Repo-save format | The Template, Content style, Metadata, Version history, Generation log, and Source verification rules below apply only when saving under `research/` in a repo. KB/memory saves follow `/ecc:knowledge-ops` conventions instead. |
| Template | MUST follow `research/_template.md`. If the template does not exist in the worktree, create it first by copying the canonical structure below. |
| Content style | Terse — no prose padding. Tables and bullet lists preferred. Sources MUST appear as footnotes or inline citations at the bottom of each file. |
| Metadata required | Every research file MUST include at the top: `> **Última actualización:** YYYY-MM-DD`. |
| Version history | Every research file MUST include a `## Historial de versiones` table (version, date, changes) at the end, before `## Generación`. |
| Generation log | Every research file MUST include a `## Generación` section at the very end listing: (a) the prompts or questions that produced the content, (b) the tools used (exa-search, web_search_exa, accounting-peru, legal-peru, etc.). |
| Source verification | After writing, double-check each key claim against its cited source. Flag any unverified claim with `⚠️ verify:`. |
| Trigger | Any time the user asks to research, look up, or investigate a topic — run the recommend-and-prompt step (or headless auto-apply) before the conversation ends. |

### Canonical template structure

```markdown
# [Título]

> **Última actualización:** YYYY-MM-DD

## [Sección]

- Punto terse.[^1]

---

[^1]: Fuente. URL (YYYY-MM-DD)

---

## Historial de versiones

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | YYYY-MM-DD | Creación inicial |

## Generación

**Prompts usados:**
- `"[prompt o pregunta que generó este contenido]"`

**Herramientas:**
- `exa-search`, `web_search_exa`, `accounting-peru`, `legal-peru`, etc.
```
