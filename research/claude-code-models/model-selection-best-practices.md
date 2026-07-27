
# Claude Code: Model Selection Best Practices (Opus / Sonnet / Haiku / Fable)

> **Última actualización:** 2026-07-05

## Resumen ejecutivo

There is no single official Anthropic doc that maps "brainstorm vs PRD vs plan vs implement vs test" onto a model. What exists is (a) a general cost/complexity heuristic in Claude Code's own docs (Haiku for mechanical subagent work, Sonnet for most coding, Opus for architecture/ambiguity), (b) an `effort` parameter (`low`/`medium`/`high`/`xhigh`/`max`) that is often a better lever than swapping models, and (c) per-subagent model overrides in `.claude/agents/*.md` frontmatter and the `Agent`/`Workflow` tools. Below synthesizes both layers — the Claude-Code-specific mechanics and the underlying API model/effort facts — into one routing table, with evidence type labeled per claim.

---

## 1. Current models & pricing[^1]

| Model | ID | Context | Input/1M | Output/1M | Notes |
|---|---|---|---|---|---|
| Claude Fable 5 | `claude-fable-5` | 1M | $10.00 | $50.00 | Most capable widely released model; always-on thinking; longer turns (single requests can run 15+ min) |
| Claude Opus 4.8 | `claude-opus-4-8` | 1M | $5.00 | $25.00 | Current flagship Opus; fast mode available |
| Claude Sonnet 5 | `claude-sonnet-5` | 1M | $3.00 ($2 intro thru 2026-08-31) | $15.00 ($10 intro) | Default in recent Claude Code releases; near-Opus on coding/agentic |
| Claude Haiku 4.5 | `claude-haiku-4-5` | 200K | $1.00 | $5.00 | Fastest/cheapest general-purpose |

`claude-opus-4-8`/`claude-sonnet-5`/`claude-fable-5` are the exact model-ID strings to use — no date suffixes. Older aliases (`claude-opus-4-6`, `claude-sonnet-4-6`, etc.) remain active if pinned deliberately.

---

## 2. The `effort` lever (often more useful than switching models)[^2]

`output_config.effort` controls **total token spend** (thinking + tool calls + prose), not just reasoning depth. Lower effort → fewer/terser tool calls and less preamble, not just shorter thinking.

| Level | When | Model support |
|---|---|---|
| `low` | Subagents, simple/mechanical tasks, latency-sensitive | All effort-capable models |
| `medium` | Balanced default step-down | All effort-capable models |
| `high` | Default; most coding/agentic work | All effort-capable models |
| `xhigh` | Hardest coding/agentic tasks; long-horizon runs (30+ min) | Fable 5, Mythos 5, Opus 4.8/4.7, Sonnet 5 |
| `max` | Frontier/no-budget-constraint problems | Fable 5, Mythos 5, Opus 4.7/4.8, Sonnet 5, Opus 4.6 |

In Claude Code: toggle via `/effort` (interactive) or `/config effort=<level>`. **Default is `high`** on effort-capable models — omitting it is not "off," it's `high`.

---

## 3. Claude Code-specific selection mechanisms[^3]

| Mechanism | What it does |
|---|---|
| `/model` | Interactive picker; `s` = session-only override, `d` = persistent default (writes `~/.claude/settings.json`) |
| `--model` CLI flag / `ANTHROPIC_MODEL` env var | Process-scoped override |
| `model:` in `.claude/agents/*.md` frontmatter | Per-subagent-type override (`sonnet`/`opus`/`haiku`/`fable`/full ID/`inherit`) |
| `Agent` tool `model` param | Per-invocation override for a single agent call, takes precedence over the agent definition's frontmatter |
| `Workflow` tool `agent()` opts `model`/`effort` | Per-agent-call override inside an orchestrated script; omit to inherit session model/effort (usually correct) |
| `/fast` | Toggles Fast Mode (2.5x output tok/s at ~2x cost) — Opus 4.8 only currently; **not** a model choice, an inference-speed mode |
| `--fallback-model` / `fallbackModel` setting | Up to 3 fallback models tried in order on failure/overload |
| `availableModels` managed setting | Org-level allowlist; cannot be bypassed by `--model` or env vars |

---

## 4. Official guidance by workflow stage

| Stage | Guidance | Evidence |
|---|---|---|
| Executing a plan / implementation | "Sonnet handles most coding tasks well and costs less than Opus. Reserve Opus for complex architectural decisions or multi-step reasoning." | SOURCED — Claude Code costs docs[^3] |
| Simple/mechanical subagent chores | Set `model: haiku` in the subagent's frontmatter | SOURCED — Claude Code costs docs[^3] |
| Research (web search / repeated tool calling) | Push effort to `xhigh` (not necessarily a bigger model) for exhaustive multi-round search | SOURCED — API effort docs[^2] |
| Codebase investigation / Explore agent | Use subagents to preserve main-context budget; the built-in `Explore` agent inherits the session model | SOURCED (delegation pattern) / INFERENCE (model choice itself) |
| Long-horizon agentic runs (30+ min) | `xhigh`/`max` effort, and prefer Fable 5/Opus 4.7+/Sonnet 5 (only these support `xhigh`) | SOURCED — API effort + Fable 5 docs[^2][^4] |
| Brainstorming, PRDs, plans, runbooks | **Not directly documented.** | INFERENCE (below) |

### Filling the documented gap (inference, argued from sourced primitives)

- **Brainstorming / ideation** — low ambiguity cost of a wrong idea, wide option space favors a capable model at moderate effort: Sonnet 5 `high` by default; escalate to Opus/Fable only if the domain is genuinely novel or the user wants exhaustive option generation (`ecc:council`, `ecc:design` patterns use judge panels rather than just a bigger single model).
- **PRDs / specs** — the deliverable is high-leverage (everything downstream inherits its assumptions) and requires holding many constraints simultaneously → Opus 4.8 at `high`, or Sonnet 5 at `high`/`xhigh` if cost-sensitive. This matches the general rule "reserve Opus for complex architectural decisions."
- **Implementation plans** — usually decomposition + sequencing of already-scoped work → Sonnet 5 `high` is normally sufficient; bump to Opus only when the plan itself has architectural ambiguity (new subsystem, cross-cutting refactor, security-sensitive design).
- **Runbooks / playbooks** — largely procedural transcription with some judgment on failure branches → Sonnet 5 `medium`–`high`; Haiku is usually too weak to reason about failure/rollback branches correctly.
- **Running/implementing a plan** — SOURCED: Sonnet, reserve Opus for the architecturally hard steps within it. In a multi-agent execution (e.g. `execute-plan` skill), this argues for per-phase model selection rather than one model for the whole run: simple phases → Sonnet/Haiku, ambiguous or highest-blast-radius phases → Opus.
- **Testing** — writing/running tests is mechanical-to-moderate; Sonnet `medium` is typically enough. Diagnosing *why* a test fails ambiguously (flaky test root-causing, complex race conditions) benefits from Opus or higher effort, not necessarily a different tier.
- **Researching scoped `.claude/` opportunities** (skills/commands/agents/hooks audits) — mostly retrieval + pattern-matching over docs and repo structure → Sonnet `medium`–`high` is adequate; reserve Opus for judging *design* tradeoffs (e.g., should this become a skill vs a hook vs a subagent).
- **General SWE "chores"** — this is where a size/blast-radius heuristic earns its keep (see §5).

---

## 5. Sizing heuristic: chore/artifact size, repo size, blast radius

No official doc ties model choice numerically to LOC/file-count/repo size. The defensible, sourced-primitive-backed heuristic is:

| Signal | Route to |
|---|---|
| Single-file, mechanical, deterministic (rename, format fix, boilerplate) | Haiku, `low` effort |
| Typical feature/bugfix within one module, requirements clear | Sonnet 5, `high` effort (the default) |
| Cross-cutting change (touches many files/subsystems), or requirements ambiguous | Opus 4.8, `high` (escalate to `xhigh` if long-running) |
| High blast-radius (auth, billing, data migration, security, destructive ops) | Opus 4.8 regardless of size — correctness cost of a wrong call dominates token cost |
| Long-horizon autonomous run (many tool-call rounds, minutes-to-hours) | Fable 5 or Opus 4.7+/Sonnet 5 at `xhigh`, because only these support that effort tier and the "give full spec up front, run at high effort" pattern is explicitly recommended for exactly this shape of work[^4] |
| Repo size itself | Not a documented independent variable. It mostly acts through context-window pressure (favor the 1M-context models — Opus 4.8, Sonnet 5, Fable 5 — over Haiku's 200K when the repo/context genuinely needs it) rather than through "bigger repo → bigger model." |

This mirrors — and sharpens — the existing local `ecc:model-route`/`ecc:token-budget-advisor` heuristic (haiku = deterministic/low-risk, sonnet = default, opus = architecture/ambiguity), adding the effort dimension and the long-horizon/`xhigh` carve-out that heuristic doesn't mention.

---

## 6. Known issues & workarounds

| Issue | Detail | Evidence |
|---|---|---|
| Prompt-cache invalidation on model switch | Any model change invalidates the cached prefix — mixing models mid-workflow (e.g. per-phase overrides in `Workflow`) pays a cold-cache tax on every switch | SOURCED[^5] |
| Prompt-cache invalidation on effort change | Changing `effort` also invalidates cache, same mechanism | SOURCED[^5] |
| Fast Mode cache invalidation | Toggling `/fast` invalidates cache; fast/standard requests never share a cached prefix | SOURCED[^6] |
| Fast Mode deprecation on Opus 4.7 | Deprecated 2026-06-25, removed 2026-07-24; Opus 4.8 is the durable fast-capable tier — don't build automation pinned to `claude-opus-4-7` + `speed:"fast"` | SOURCED[^6] |
| Agent-team cost multiplier | Multi-agent "teams" running in plan mode use ~7x the tokens of a single session — a strong argument for cheaper models/lower effort on teammates, not just the lead agent | SOURCED[^3] |
| Subagent frontmatter model restricted by org allowlist | `availableModels` can silently make a requested `model:` override a no-op if not on the allowlist — verify before assuming a cheap-model override is actually taking effect | SOURCED[^3] |
| Thinking-block replay across models | Fable 5/Mythos 5 thinking blocks are **dropped** (not billed, not erroring) when replayed to a different model — relevant if a workflow's later phase swaps from Fable 5 to Opus mid-conversation | SOURCED[^7] |
| `effort: "max"`/`"xhigh"` truncation risk | At high effort tiers, leave `max_tokens` headroom — a tight limit can truncate mid-thought (`stop_reason: "max_tokens"`) before the actual answer is produced | SOURCED[^2] |
| Skill/trigger degradation on cheaper models (session finding, not vendor-documented) | ⚠️ verify: prior session note found skill-trigger-harness recall drop to 0% under certain conditions unrelated to model choice (skill not installed) — not a confirmed model-tier effect, flagging so it isn't conflated | INFERENCE / caveat only |

---

## 7. Practical routing table (synthesis)

| Chore type | Model | Effort | Rationale |
|---|---|---|---|
| Brainstorm / ideation | Sonnet 5 (Opus if domain genuinely novel) | high | breadth of ideas, moderate cost |
| PRD / spec authoring | Opus 4.8 | high | highest leverage artifact, ambiguity-heavy |
| Implementation plan | Sonnet 5 (Opus if cross-cutting/ambiguous) | high | usually decomposition of already-scoped work |
| Runbook / playbook | Sonnet 5 | medium–high | procedural + some failure-branch judgment |
| Implement/execute a plan (per phase) | Sonnet 5 default; Opus for the hard phases; Haiku for pure mechanical phases | high (low for mechanical phases) | matches official "reserve Opus" guidance |
| Testing (write/run) | Sonnet 5 | medium | mechanical-to-moderate |
| Debugging ambiguous/flaky failures | Opus 4.8 | high | correctness > cost when root cause is unclear |
| Scoped `.claude/` opportunity research (skills/hooks/agents audit) | Sonnet 5 | medium–high | retrieval + pattern-match; Opus only for design tradeoffs |
| General SWE chore, single-file/mechanical | Haiku | low | official subagent guidance |
| General SWE chore, typical feature work | Sonnet 5 | high (default) | official guidance |
| High blast-radius / security / destructive | Opus 4.8 | high | correctness dominates regardless of size |
| Long-horizon autonomous agent run | Fable 5 or Opus 4.7+/Sonnet 5 | xhigh | only these support xhigh; give full spec up front |

---

## Historial de versiones

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-07-05 | Creación inicial |

## Generación

**Prompts usados:**
- `"best practices, known issues and workarounds when choosing claude code models for brainstorming, authoring prds, plans, runbooks, runnning or implementing them, testing, researching scoped .claude opps, software engineering or general work, what are the conditions, hints, rules, reasons to choose between one and the other, the effort: per chore or artifact size, pero repo size, others? fresh research"`

**Herramientas:**
- `claude-api` skill (cached model catalog/pricing/effort docs, 2026-06-24)
- `claude-code-guide` subagent (live WebFetch of code.claude.com/docs — costs.md, sub-agents.md, agent-view.md, prompt-caching.md, and platform.claude.com effort.md/fast-mode.md — 2026-07-05)
- `ecc:model-route`, `ecc:token-budget-advisor` skill definitions (existing local heuristics, cross-referenced not duplicated)

---

[^1]: Anthropic `claude-api` skill, cached model table. 2026-06-24.
[^2]: Anthropic `claude-api` skill / platform.claude.com/docs/en/build-with-claude/effort.md. 2026-07-05.
[^3]: code.claude.com/docs/en/costs.md, sub-agents.md, agent-view.md (via claude-code-guide subagent WebFetch). 2026-07-05.
[^4]: Anthropic `claude-api` skill, Claude Fable 5 / Opus 4.8 migration guidance (long-horizon agentic work, give full spec up front, run at high/xhigh effort). 2026-06-24.
[^5]: code.claude.com/docs/en/prompt-caching.md (via claude-code-guide subagent WebFetch). 2026-07-05.
[^6]: platform.claude.com/docs/en/build-with-claude/fast-mode.md (via claude-code-guide subagent WebFetch). 2026-07-05.
[^7]: Anthropic `claude-api` skill, Claude Fable 5 thinking-block replay semantics. 2026-06-24.
