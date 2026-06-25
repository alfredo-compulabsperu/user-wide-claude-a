---
name: audit-plan
description: Audits any plan against 8 domain-agnostic structural axes — preconditions, interface contracts, dependency graph, null/error paths, environment assumptions, ownership, verification, and reversibility/blast-radius — plus optional harness axes for agent orchestration and optional security/sensitivity axes for plans touching data, money, or credentials. Works for any domain: software, ops, process, agent pipelines, runbooks. Invoke as /audit-plan <file> or /audit-plan to infer from context. Add --assess for a GO/HOLD/NO-GO verdict with confidence and rationale. Add --loop for the full closed-loop: audit + assess → user fixes → isolated re-audit → final verdict. Use whenever the user wants to review, audit, validate, stress-test, or find gaps in a plan — especially before launching or executing it — even if they don't say "audit".
---

# audit-plan

Audit a plan against a minimal set of domain-agnostic axes before execution begins.

## Input

- **File argument** — path to a plan file. Read it before auditing.
- **No argument** — infer the plan from conversation context (most recently discussed plan, inline text). If none is evident, ask the user to paste it.
- **`--harness` flag** — force-enable harness-specific axes.
- **`--no-harness` flag** — suppress harness axes even if auto-detected.
- **`--sensitivity` flag** — force-enable security/sensitivity axes.
- **`--no-sensitivity` flag** — suppress sensitivity axes even if auto-detected.
- **`--assess` flag** — after the audit, produce a GO / HOLD / NO-GO verdict with confidence and rationale grounded in the findings.
- **`--loop` flag** — full closed-loop: audit + assess → user fixes → isolated re-audit → final assess. See Loop Mode below.
- **`--adversarial` flag** — after the audit, spawn a fresh isolated agent with no axes and no prior findings. It tries to break the plan from first principles. Results labeled separately as unverified. Combinable with `--assess` and `--loop`.

## Auto-detection

Scan the plan for two kinds of signal before auditing. Enable the matching optional axis group and tell the user which fired.

**Harness signals** → enable harness axes, say "Harness axes enabled (detected: <signal>)."
`agent`, `pipeline()`, `parallel()`, `workflow`, `isolated`, `stage`, `orchestrat`, numbered stages with agent names, return contracts (SUCCESS/WARN/ERROR), concurrent execution language.

**Sensitivity signals** → enable security/sensitivity axes, say "Sensitivity axes enabled (detected: <signal>)."
`PII`, `personal data`, `email`, `address`, `credential`, `secret`, `token`, `password`, `API key`, `payment`, `card`, `bank`, `health`, `medical`, `patient`, `customer data`, regulated-domain language (HIPAA, GDPR, PCI), or any step exporting/logging/transmitting user data.

---

## The 7 Core Axes

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
| **Critical** | Will stall, corrupt output, or produce wrong results on first run |
| **High** | Silent failure, data loss, or degraded output with no detection |
| **Medium** | Operational gap — won't break first run but creates reliability or maintenance risk |

### Calibration — resist inflation

Severity is the whole product. A finding rated one level too high teaches the user to distrust the audit — worse than missing it. The common drift is promoting Medium to High to make an audit feel substantial. Resist it, especially on well-formed plans where the honest result is "mostly PASS, a few Mediums," not a manufactured HOLD.

Calibrate against the consequence, not the topic:

- **Critical vs High** — Critical breaks visibly on the first run (halts, wrong output, can't execute). High runs but fails silently or later (data lost or corrupted, no detection).
- **High vs Medium** — High = an undetected bad outcome (lost data, wrong result, unalarmed security exposure). Medium = a real gap that is recoverable, detectable, or cosmetic to correctness. "Could be tightened" is Medium; "will silently hurt and no one will know" is High.
- **Medium vs PASS** — If the plan already handles it, mark PASS. Never log a finding just to fill the table.

When torn between two levels, pick the lower and name the condition that would raise it in the Rationale. A well-formed plan yielding zero Critical and few High findings is a correct audit, not a weak one.

## Confidence

Plan audit findings are structural observations — a gap either exists in the plan text or it does not. Confidence level is therefore NOT a standard column; severity already encodes impact.

The one exception: **speculative findings** — where the plan is ambiguous and the finding depends on an assumption you cannot verify from the text alone. In that case:

- Tag the finding `(speculative)` in the Finding column
- State the condition explicitly in Rationale: "only a problem if X is true"
- Do not assign Critical severity to a speculative finding

---

## Output Format

```
## Plan Audit: <plan name or inferred title>

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

---

## Assessment Output (--assess or --loop)

Appended after the audit findings. Assessment is a probabilistic judgment — confidence belongs here, not in the audit table.

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

When `--loop --adversarial` are combined, Phase 2 spawns two agents in parallel:

1. **Structured re-audit agent** — axes only, no Phase 1 findings (same as standard loop)
2. **Adversarial agent** — plan only, no axes, no findings (same as standalone `--adversarial`)

Phase 3 synthesizes all three finding sets: Phase 1 audit, Phase 2 re-audit, adversarial.

---

### Loop exit conditions

Stop after Phase 3. Do not loop again unless the user explicitly requests another cycle. If Final Verdict is still NO-GO after one loop, tell the user: "Plan requires redesign before another audit cycle is useful."
