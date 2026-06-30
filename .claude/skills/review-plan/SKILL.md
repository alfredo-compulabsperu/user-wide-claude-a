---
name: review-plan
description: "Reviews any plan before execution: audits it against 8 domain-agnostic structural axes — preconditions, interface contracts, dependency graph, null/error paths, environment assumptions, ownership, verification, and reversibility/blast-radius — then assesses the findings into a GO/HOLD/NO-GO verdict with confidence. Optional harness axes for agent orchestration and sensitivity axes for plans touching data, money, or credentials auto-enable when detected. Works for any domain: software, ops, process, agent pipelines, runbooks. Invoke as /review-plan <file> or /review-plan to infer from context. Add --loop for a closed-loop with an isolated cold-start re-audit, or --adversarial for a first-principles attack on unknown unknowns. Use whenever the user wants to review, audit, assess, validate, stress-test, or find gaps in a plan — especially before launching or executing it — even if they don't say \"review\"."
---

# review-plan

Review a plan before execution. A review is two halves: an **audit** (findings against domain-agnostic axes) and an **assessment** (those findings mapped to a GO/HOLD/NO-GO verdict). Always produce both — the verdict is the question the user came with ("can I run this?"); findings without a verdict make the user do the judgment the skill is best positioned to make.

## Input

- **File argument** — path to a plan file. Read it before reviewing.
- **No argument** — infer the plan from conversation context (most recently discussed plan, inline text). If none is evident, ask the user to paste it.
- **Acceptance criteria (optional)** — success definition, constraints, risk tolerance. If absent, see "Reviewing without criteria" below.

Two opt-in modes:

- **`--loop`** — closed-loop: review → user fixes → isolated cold-start re-audit → final verdict. See Loop Mode.
- **`--adversarial`** — after the audit, spawn an isolated agent to attack the plan from first principles with no axes or prior findings. Targets unknown unknowns. Combinable with `--loop`.

Harness and sensitivity axes auto-enable on detection (see below) — no flag needed. To force a group on when detection misses it, say so (`--harness` / `--sensitivity` are honored as overrides).

## Auto-detection

Scan the plan for two kinds of signal before auditing. Enable the matching optional axis group and tell the user which fired.

**Harness signals** — any language indicating steps execute in separate processes or are coordinated by an orchestrator → enable harness axes, say "Harness axes enabled (detected: <signal>)."
Keywords: `agent`, `pipeline()`, `parallel()`, `workflow`, `isolated`, `stage`, `orchestrat`, numbered stages with agent names, return contracts (SUCCESS/WARN/ERROR), concurrent execution language.

**Sensitivity signals** — any language indicating the plan handles protected, regulated, or personal data → enable sensitivity axes, say "Sensitivity axes enabled (detected: <signal>)."
Keywords: `PII`, `personal data`, `email`, `address`, `credential`, `secret`, `token`, `password`, `API key`, `payment`, `card`, `bank`, `health`, `medical`, `patient`, `customer data`, regulated-domain language (HIPAA, GDPR, PCI), or any step exporting/logging/transmitting user data.
A missed sensitivity axis is High-severity by this skill's own scale, so **err toward enabling**: fire on oblique data-movement language too (export, back up, send to, share with, copy to, hand off) even when no keyword above appears. A loud "enabled (detected: 'export the file')" is cheap; a silent miss is not.

---

## Reviewing without criteria

The 8 core axes are domain-agnostic — a missing rollback is a gap regardless of the plan's goal — so a review never blocks on missing acceptance criteria. When the user gives no success definition, constraints, or risk tolerance:

1. **Infer and state** — derive implied criteria from the plan's stated goal, list them as explicit assumptions, and review against those. Let the user correct.
2. **Audit structure regardless** — run all axes; the only one that genuinely needs a success definition is Verification (axis 7), so tag its findings `(speculative)` when "success" is undefined.
3. **Lower verdict confidence** — an inferred bar means a guessed GO/HOLD/NO-GO threshold; reflect that in the Assessment confidence score.

If the user is present and the stakes are high, prefer just asking for criteria first.

---

## The 8 Core Axes

Apply to every plan. Each axis has a question and a set of things to look for.

### 1. Preconditions
*What must be true before execution starts? Stated and verified, or silently assumed?*

- Auth tokens, sessions, or credentials assumed valid without a check
- External services assumed reachable
- Data assumed to exist (files, records, config) without a guard
- Human actions assumed complete with no confirmation mechanism

### 2. Interface Contracts
*What does each step consume and produce? Formats, schemas, paths — defined or improvised per step?*

- Shared identifiers (slugs, IDs, keys) with no naming convention
- File paths referenced by multiple steps with no canonical format
- Output format of step N assumed by step N+1 but never documented
- Fields read by one step written by another with no agreed schema

### 3. Dependency Graph
*Are step orderings correct? Anything parallel with a hidden sequential dependency?*

- Step B reads output of step A but may start before A finishes
- Parallel steps writing to the same resource
- A synthesis or consolidation step running concurrently with the steps it synthesizes
- Circular dependencies

### 4. Null / Error Paths
*What happens when input is missing or malformed? What happens when a step fails?*

- Optional or incomplete inputs with no fallback
- Failure signals with no documented handler
- Steps that advance silently on partial success
- Fields that may be null in real data, used without a guard

### 5. Environment Assumptions
*What capabilities, tools, auth, or runtime constraints does the plan silently rely on?*

- Tools or APIs assumed available and authenticated
- Runtime constraints assumed absent (no interactive prompts, no `Date.now()`, no display)
- Platform-specific behavior assumed (OS, shell, language version)
- Network or storage access assumed without validation

### 6. Ownership
*Exactly one executor per step? No gaps, no overlaps?*

- Steps with no named owner (agent, human, script)
- Steps where two agents or components could both plausibly act
- Handoffs with no clear trigger or acceptance signal
- Shared write targets with no designated writer

### 7. Verification
*How does the plan confirm a step succeeded before advancing?*

- Steps that advance on an agent's claim rather than an observable artifact
- Missing post-condition checks (file exists, field populated, state matches expected)
- Verification described but not wired into the flow
- Success defined only for the happy path; degraded-but-acceptable outputs unhandled

### 8. Reversibility & Blast Radius
*If a step fails or produces the wrong result, can it be undone — and how much breaks?*

- Irreversible or one-way steps with no dry-run, checkpoint, or backup before commit
- Destructive operations (delete, overwrite, mass-send, schema change) with no rollback path
- Failure of one step cascading to unrelated systems, data, or third parties
- Wide-effect actions applied all-at-once with no staged, canary, or partial-scope option
- No defined point of no return — the plan doesn't flag which step makes rollback impossible

---

## Harness Axes (auto-enabled or `--harness`)

### H1. Concurrency Model
Are parallel and sequential primitives applied to the actual dependency structure?

- `parallel()` used for steps with internal sequential dependencies
- Wrong primitive: barrier where none needed, or missing barrier where one is required
- Fan-out without a defined fan-in point

### H2. Agent Return Contract
Do all agents return signals in a consistent, parseable format? Does the orchestrator know how to consume them?

- Inconsistent signal vocabulary across agents
- VERDICT or decision values embedded in prose with no extraction mechanism
- Orchestrator parses an agent's return value with no defined contract

### H3. Shared State / Concurrent Writes
When multiple agents write to the same resource, is access coordinated?

- Two agents in a `parallel()` block appending to the same file
- No locking, sequencing, or section-ownership for shared outputs
- Merge strategy undefined when concurrent writes overlap

### H4. Prompt Completeness
Do isolated agents receive all information they need to execute without phoning home?

- Agent prompts reference data available only in the orchestrator's context
- Isolated agents expected to follow a spec they are not given
- Interactive guards (confirmation prompts, user input) inside specs invoked by isolated agents

### H5. Observability
Is there a mechanism for capturing defects, timing, and signals outside the happy path?

- No log file or defect record defined
- Log-writing instruction absent from isolated agent prompts
- Timing data capturable only at notification time with no protocol for doing so

---

## Sensitivity Axes (auto-enabled or `--sensitivity`)

Domain-specific group for plans that handle sensitive data, money, credentials, or regulated material. These name the concrete checks a capable reviewer catches only by chance — the structured pass makes them reliable. Skip entirely when no sensitivity signal is present.

### S1. Data Exposure
Where does sensitive data travel, rest, or get logged — and who can see it?

- Sensitive data written to temp dirs, logs, or world-readable paths
- Personal data copied to a less-protected system or handed to a third party (analytics, marketing) with no minimization or consent check
- Data transmitted over an unverified or plaintext channel
- No retention/cleanup for intermediate files containing sensitive data

### S2. Credential & Secret Handling
Are secrets acquired, used, and disposed of safely?

- Credentials, tokens, or keys hardcoded, echoed, or committed
- Long-lived credentials where scoped/short-lived would do
- No rotation or revocation path if a step leaks a secret
- Secrets passed through an intermediary (file, env, prompt) that persists them

### S3. Authorization & Compliance
Is access scoped to least privilege, and does the plan respect regulatory limits?

- A step runs with broader access than its task requires
- Irreversible disclosure (publish, share, send) with no approval gate
- Regulated data (health, financial, PII) handled with no stated compliance basis
- No audit trail for an action that a regulator or incident review would need

---

## Severity

| Severity | Meaning |
|---|---|
| **Critical** | Failure is visible on first run — plan stalls, errors out, or produces obviously wrong output |
| **High** | Failure is silent — plan runs to completion but loses data, produces wrong results, or creates an undetected security exposure |
| **Medium** | A real gap that is recoverable or detectable through monitoring or user complaint; does not break the first run |
| **Low** | Cosmetic or hardening nit — worth noting, costs nothing to ignore on this run |

### Calibration — resist inflation

Severity is the whole product. A finding rated one level too high teaches the user to distrust the audit — worse than missing it. The common drift is promoting Medium to High to make an audit feel substantial. Resist it, especially on well-formed plans where the honest result is "mostly PASS, a few Mediums," not a manufactured HOLD.

Calibrate against the consequence, not the topic:

- **Critical vs High** — Critical breaks visibly on the first run (halts, wrong output, can't execute). High runs but fails silently or later (data lost or corrupted, no detection).
- **High vs Medium** — High = an undetected bad outcome (lost data, wrong result, unalarmed security exposure). Medium = a real gap that is recoverable or detectable. "Could be tightened" is Medium; "will silently hurt and no one will know" is High.
- **Medium vs Low** — Medium is a gap that will plausibly cost someone time or correctness if unaddressed. Low is a nit that is fine to ship as-is — note it once, do not dwell.
- **Below Low vs PASS** — If the plan already handles it, mark PASS. Never log a finding just to fill the table.

When torn between two levels, pick the lower and name the condition that would raise it in the Rationale. A well-formed plan yielding zero Critical and few High findings is a correct audit, not a weak one.

Severity rates **consequence**. The Adversarial and Harness tables rate **likelihood** (High/Medium/Low) — a separate dimension. Do not merge the two scales: in Phase 3 synthesis, keep adversarial findings on their own likelihood scale rather than forcing them into a consequence tier.

**Speculative findings:** When a finding depends on runtime conditions not visible in the plan text, tag it `(speculative)` in the Finding column and state the condition in Rationale ("only a problem if X is true"). Do not assign Critical to a speculative finding.

---

## Output Format

```
## Plan Review: <plan name or inferred title>

**Axes applied:** Core (8) [+ Harness (5)] [+ Sensitivity (3)]

---

### Critical

| Axis | Finding | Rationale | Recommendation |
|------|---------|-----------|---------------|
| Dependency Graph | career-coach runs in parallel() with agents 1+2 | Has a hard read dependency on both completing first | Move career-coach to a sequential agent() call after parallel([agent1, agent2]) |

### High

| Axis | Finding | Rationale | Recommendation |
|------|---------|-----------|---------------|

### Medium

| Axis | Finding | Rationale | Recommendation |
|------|---------|-----------|---------------|

### Low

| Axis | Finding | Rationale | Recommendation |
|------|---------|-----------|---------------|

---

### Axis Coverage

| Axis | Status | Findings |
|------|--------|----------|
| 1. Preconditions | PASS / FINDINGS | N |
| 2. Interface Contracts | PASS / FINDINGS | N |
| 3. Dependency Graph | PASS / FINDINGS | N |
| 4. Null / Error Paths | PASS / FINDINGS | N |
| 5. Environment Assumptions | PASS / FINDINGS | N |
| 6. Ownership | PASS / FINDINGS | N |
| 7. Verification | PASS / FINDINGS | N |
| 8. Reversibility & Blast Radius | PASS / FINDINGS | N |
| H1. Concurrency Model | PASS / FINDINGS / N/A | N |
| H2. Agent Return Contract | PASS / FINDINGS / N/A | N |
| H3. Shared State | PASS / FINDINGS / N/A | N |
| H4. Prompt Completeness | PASS / FINDINGS / N/A | N |
| H5. Observability | PASS / FINDINGS / N/A | N |
| S1. Data Exposure | PASS / FINDINGS / N/A | N |
| S2. Credential & Secret Handling | PASS / FINDINGS / N/A | N |
| S3. Authorization & Compliance | PASS / FINDINGS / N/A | N |
```

One finding per row. If an axis has no issues, mark PASS and move on. Do not pad.

**Ground every finding in the plan.** The Finding column must point to a specific step, line, or quoted phrase that actually appears in the plan — name it ("Step 4", "the `parallel([a,b,c])` call", "the line 'email the export to finance'"). Do not raise findings about steps the plan does not contain; an audit's credibility dies the first time it flags something that isn't there. If a gap is an *omission* (the plan should do X but doesn't), say what the plan does instead and where the omission bites. When two axes describe the same defect, log it once under the most specific axis and mark the other PASS — double-counting inflates the totals the verdict depends on.

---

## Assessment (always produced)

The second half of every review. Appended after the audit findings — a review is incomplete without it. Assessment is a probabilistic judgment, so confidence belongs here, not in the audit table.

Map findings to a verdict with this default rule, then adjust only with a stated reason:

- **NO-GO** — one or more unresolved **Critical** findings. The plan will break or corrupt on first run.
- **HOLD** — no Critical, but one or more unresolved **High** findings. The plan runs but risks silent data loss or wrong results; resolve or consciously accept each High first.
- **GO** — only Medium/Low findings remain. Safe to execute; address the Mediums as conditions where practical.

The rule is a floor, not a ceiling: you may downgrade GO→HOLD when several Mediums compound into a likely-bad outcome, or note why a lone High is acceptable for this run — but state the reason in Rationale whenever you depart from the default.

```
## Assessment

**Verdict:** GO | HOLD | NO-GO
**Confidence:** High | Medium | Low (0–100 score)

**Rationale:** <2–3 sentences — what drives the verdict, which findings are decisive>

**Conditions to advance:**
- <what must be resolved before GO, or what would change the verdict>
```

---

## Adversarial Mode (--adversarial)

Targets unknown unknowns — gaps outside the axes. Runs after the structured audit.

Spawn a fresh isolated agent with **only** these inputs:

1. The plan file (read fresh from disk)
2. This prompt — verbatim, nothing else:

```
You are trying to break this plan. Read it carefully, then find every assumption,
gap, or failure mode it doesn't account for. No categories. No axes. No structure.
Just attack it from first principles — the way an adversary or a production incident would.

Return a flat list of findings. For each:
- What could go wrong
- Why the plan doesn't prevent it
- How likely it is to matter (High / Medium / Low)
```

**Do NOT pass** the structured audit findings, axes, or any prior analysis. The adversarial agent must derive independently — its value comes from not being constrained by the axis framework.

### Adversarial Output Format

Appended after structured audit findings, clearly separated:

```
---

## Adversarial Findings (unverified — unknown unknowns)

> These findings come from a free-form adversarial pass, not the structured axes.
> They are hypotheses, not confirmed gaps. Verify before acting on them.

| Finding | Why the plan misses it | Likelihood |
|---------|----------------------|------------|
| ... | ... | High / Medium / Low |
```

---

## Loop Mode (--loop)

The loop eliminates confirmation bias on re-audit by using a cold-start isolated agent that cannot see the first pass findings.

### Phase 1 — Audit + Assess (same instance)

Run the full audit against all applicable axes. Produce findings + assessment verdict. Tell the user:

```
Loop Phase 1 complete.
Critical: N  High: N  Medium: N
Verdict: <GO | HOLD | NO-GO>  Confidence: <score>

Fix the Critical and High findings in the plan, then reply "re-audit" to continue.
```

Wait for the user to reply before proceeding.

### Phase 2 — Isolated Re-audit (fresh agent, written output only)

An audit is only as valid as the independence of the auditor. The re-audit agent must derive its findings fresh — seeing Phase 1 results would anchor its judgment and defeat the loop's purpose.

Spawn an isolated agent with **only** these inputs — nothing else:

1. The updated plan file (read fresh from disk)
2. The axes to apply (copy the axis definitions verbatim from this skill)
3. The log-writing protocol if harness mode is active

**Do NOT pass** the Phase 1 findings, the assessment verdict, or any prior reasoning to the re-audit agent. It must re-derive independently.

The re-audit agent returns its findings in the standard audit output format. If it surfaces the same gaps as Phase 1, the fixes did not hold. If it surfaces new gaps, the fixes introduced them.

### Phase 3 — Final Assess (same instance)

Read both the Phase 1 findings and the Phase 2 re-audit findings. Compare:

- Gaps that closed: fixes confirmed
- Gaps that persisted: fixes did not hold — escalate severity
- New gaps: fixes introduced regressions

Produce a final assessment with updated verdict and confidence.

```
## Final Assessment

**Phase 1 verdict:** <verdict> (<confidence>)
**Phase 2 re-audit:** <N critical> <N high> <N medium> remaining / <N new>
**Final Verdict:** GO | HOLD | NO-GO
**Confidence:** High | Medium | Low (0–100)

**Rationale:** <what changed, what held, what's still open>
```

### Loop + Adversarial

When `--loop --adversarial` are combined, Phase 2 spawns the structured re-audit agent and the adversarial agent in parallel. Phase 3 synthesizes all three finding sets: Phase 1 audit, Phase 2 re-audit, adversarial. If Final Verdict is still NO-GO, tell the user: "Plan requires redesign before another audit cycle is useful."
