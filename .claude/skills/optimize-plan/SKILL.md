---
name: optimize-plan
description: Optimizes how an existing PLAN, runbook, or agent-pipeline DOCUMENT executes — making it leaner, faster, and cheaper to run WITHOUT changing what it produces. Scans across 4 efficiency lenses: context isolation (move heavy/noisy steps into isolated subagent calls that return only conclusions, to keep the main conversation lean), parallelization (run genuinely independent steps concurrently), dedup & ordering (collapse repeated work, run cheap fail-fast checks first), and tool/command efficiency (batch reads, narrow searches, route large outputs through sandboxed processing). Preserves the plan's original schema and proposes changes diff-first, waiting for approval before editing the file. Invoke as /optimize-plan <file> or /optimize-plan to infer the plan from context. Use it whenever the user wants to optimize, streamline, speed up, parallelize, slim the context/token cost of, or tighten an existing plan/runbook/pipeline — even if they don't say "optimize" (e.g. "this plan blows up my context window", "the steps run one at a time", "it keeps re-reading the same file", "make it cheaper to execute"). Do NOT use it for: optimizing code, SQL queries, render or runtime performance, build artifacts, prompts, or CI/CD configs (those are code/runtime performance, not a plan document); writing or creating a brand-new plan; fixing a specific bug in a plan step; or finding and adding missing structure, error handling, or safety. Surfacing structural gaps and recommending /audit-plan is in scope, but actually auditing or fixing them is audit-plan's job, not this skill's.
---

# optimize-plan

Make a plan cheaper and faster to execute **without changing what it produces.**
Audit-plan finds structural gaps; optimize-plan finds efficiency wins. Different job, same discipline.

## The one rule that governs everything

An optimization changes *how* a plan runs — never *what it produces*. If a proposed change alters the plan's outcomes, scope, or correctness, it is not an optimization; it is a rewrite, and it does not belong here. The most common way to violate this is parallelizing steps that have a hidden dependency, or isolating a step whose full output is actually needed downstream. Treat every finding as guilty of breaking correctness until you've checked it against the plan's real data/control flow.

## Input

- **File argument** — path to a plan file. Read it before doing anything.
- **No argument** — infer the plan from conversation context (most recently discussed plan, inline text). If none is evident, ask the user to paste it.
- **`--audit-first` flag** — run audit-plan (or its core axes) before optimizing; skip optimization of any section with an open Critical/High structural finding. See Chaining below.
- **`--apply` flag** — skip the diff-first gate and write the optimized plan directly. Default is diff-first: propose, wait, then write.
- **Lens-scoping flags** — `--isolation`, `--parallel`, `--dedup`, `--tools` restrict the pass to the named lens(es). Default is all four.

## Auto-detection — what's even optimizable

Not every plan benefits from every lens. Classify the plan first, enable the lenses that apply, and tell the user what fired. Optimizing the wrong lens wastes the user's attention and erodes trust in the rest of the pass.

| Signal in the plan | Lens it unlocks |
|---|---|
| Agent/subagent calls, `pipeline()`, `parallel()`, `workflow`, isolated stages, research steps, log/test-output analysis, large file reads, web fetches, big JSON/CSV processing | **Context Isolation** — the headline lens |
| Multiple independent steps, fan-out language, several files/targets handled the same way, "for each", batch operations | **Parallelization** |
| Repeated reads of the same source, re-gathering the same context, duplicated verification, expensive steps ahead of cheap preconditions | **Dedup & Ordering** |
| `cat`/`grep`/`find` pipelines, re-reading files already in context, narrow tool replaced by shell, large command output piped into the conversation | **Tool/Command Efficiency** |

A pure human runbook (UI clicks, approvals, credential entry) usually has little to isolate or parallelize — say so plainly rather than manufacturing findings. State which lenses you enabled and why.

## Schema preservation

The output must look like the input. Before proposing anything, read the plan's structure and lock onto it:

- Heading hierarchy and section names (Pre-flight, Phases, Steps, etc.)
- Task format — numbered list, `- [ ]` checkboxes, table rows
- Numbering / ID scheme for steps
- Any house conventions present (e.g. a Pre-flight phase, owner column, verification line per step)

Every rewrite slots **into** that structure. Don't introduce a new format, renumber gratuitously, or drop sections. If an optimization needs a new step (e.g. splitting one step into "delegate" + "consume result"), give it an ID consistent with the existing scheme and keep it in the existing format. Preserving schema is what makes the diff reviewable and the optimized plan a drop-in replacement.

## First: structural pre-scan (do this before any lens)

Run this scan *before* looking for optimizations — it's a single quick pass, and its result goes at the **top** of your report, not buried at the end. Optimizing a structurally broken plan wastes effort and can entrench the breakage (parallelizing around a missing dependency, isolating a step whose contract is undefined). You can't reliably make a plan faster until you know it's sound.

Scan the plan for these structural-gap signals (the same ones `/audit-plan` checks):

- **Undefined inter-step interface** — step N consumes something (a file, an ID, a "store", a result) that no earlier step clearly defines or produces.
- **Missing error/null path** — a step that can fail or return nothing, with no stated handler or fallback.
- **Ambiguous ownership** — a step with no clear executor, or two steps that could both act on the same thing.

If **any** signal fires, lead your report with the Structural note (see Output Format) — one line naming the gap and recommending an independent structural audit first (e.g. `/audit-plan <file>` if that skill is installed). Then proceed to optimize only the parts you're confident are sound; with `--audit-first`, skip optimizing any section with an open Critical/High structural finding. If **no** signal fires, omit the note and go straight to the lenses. Don't turn this into an audit — naming the gap and pointing at the right tool is the whole job here; fixing it is a structural audit's remit.

---

## The 4 Lenses

### 1. Context Isolation — the headline lens

*Which steps dump bytes into the main conversation that no one downstream actually needs?*

Every byte a step's tool returns into the main context costs reasoning capacity for the rest of the run. A step is a strong isolation candidate when it **produces a large intermediate output but only a small conclusion is consumed downstream.** Move it into an isolated subagent call that does the heavy reading in its own context and returns only the compact result.

Look for:

- Research / web-fetch / doc-lookup steps whose output is read once to extract a few facts
- Log, test-output, or build-output analysis where only pass/fail + a few lines matter
- Large file or directory reads where only a summary or specific value is needed
- Big JSON/CSV/API-response processing where only an aggregate or filtered subset is used
- Codebase-wide searches/audits where only the conclusion feeds the next step

For each candidate, the rewrite must specify three things — without them the isolation is incomplete and will phone home (audit-plan H4):

1. **What to delegate** — the exact sub-task.
2. **What the isolated agent receives** — all inputs it needs to run cold. If it would need data that lives only in the main context, either pass that data in or the step is not actually isolatable.
3. **The return contract** — the compact, structured result it sends back (and nothing else).

Anti-patterns — do NOT propose isolation when:

- The step's full output is genuinely needed verbatim downstream (isolation just adds a round-trip).
- The step is tiny — delegation overhead exceeds the context saved.
- The agent would need so much main-context state passed in that the prompt itself becomes the bloat.

> Tool-level isolation counts too: a step that pipes large command output into the conversation can often be rewritten to process it in a sandbox (e.g. `ctx_execute` / `ctx_batch_execute`) and surface only the derived answer. Same principle, smaller scope — see the Tool/Command lens.

### 2. Parallelization

*Which steps run one-after-another but have no dependency forcing that order?*

Independent steps run serially waste wall-clock. Propose concurrency — but only after proving independence, because this is the single most dangerous lens.

Look for:

- Sequential steps that read/write disjoint resources and don't consume each other's output
- "For each X" loops over independent items (fan-out)
- Multiple independent research/read/verify steps gathered serially

For each finding, you MUST:

- **Prove independence** against the plan's real data flow. If step B reads anything step A writes, they cannot parallelize. If unsure, don't propose it — flag it as needs-verification instead.
- **Define the fan-in** — where parallel branches rejoin, and whether a barrier is required before the next step. A fan-out with no defined fan-in is a new bug, not an optimization.
- **Name the shared-write hazard** — if two parallel branches could write the same file/resource, parallelization is unsafe without coordination.

This lens overlaps audit-plan's Dependency Graph (axis 3) and Concurrency Model (H1) by design — a parallelization win that violates the dependency graph is a correctness regression wearing an optimization costume.

### 3. Dedup & Ordering

*What work is done twice, and what runs in a costly order?*

Look for:

- The same file/source read or the same context gathered in multiple steps → gather once, reuse.
- Duplicated verification or setup repeated across steps → hoist to a shared step.
- Expensive or irreversible work placed ahead of cheap checks that could fail the plan early → reorder so fast, cheap, fail-fast checks (preconditions, validation, dry-runs) run first. This protects the Pre-flight discipline: never spend effort before the cheap gate that could abort.
- Redundant re-confirmation of state already established earlier and unchanged since.

Reordering must preserve the dependency graph — only move a step earlier if everything it depends on still precedes it.

### 4. Tool/Command Efficiency

*Within steps, are the cheapest correct tools being used?*

Look for:

- Independent tool calls issued in separate steps that could batch into one message (parallel tool calls).
- `cat`/`head`/`sed`/`grep` shell pipelines where a dedicated read/search tool is cheaper and cleaner.
- Re-reading a file already read earlier in the plan (it's already in context).
- Broad searches that could be narrowed (scoped path, specific glob) to return less.
- Large command output piped into the conversation that could be filtered/aggregated in a sandbox first, returning only what's used.

These are small, safe wins individually; in aggregate they meaningfully cut tokens and latency. Keep each one concrete — point at the step and name the cheaper pattern.

---

## Benefit & Risk

Each finding carries a benefit estimate and a risk level. Together they decide whether an optimization is worth proposing at all.

**Benefit** — what the change buys, in the unit that matters for its lens:

| Lens | Benefit unit |
|---|---|
| Context Isolation | Approx. context/tokens kept out of the main conversation (Large / Medium / Small) |
| Parallelization | Wall-clock saved — serial steps collapsed into concurrent ones |
| Dedup & Ordering | Repeated work removed, or expensive work avoided on early failure |
| Tool/Command | Tokens/latency trimmed per step (usually Small individually) |

**Risk** — the chance the change alters behavior or breaks correctness:

| Risk | Meaning |
|---|---|
| **Safe** | Pure efficiency win; outcomes provably unchanged. Most isolation, dedup, and tool findings. |
| **Verify** | Sound only if an assumption holds (steps truly independent, output truly not needed downstream). State the assumption; the user confirms before applying. |
| **Unsafe-as-stated** | Would change behavior or risk correctness as written. Don't propose it as an optimization — either describe the precondition that would make it safe, or drop it. |

### Calibration — resist manufacturing wins

The value of this pass is trust: a user who applies your optimizations must believe they won't break the plan. One optimization that silently changes behavior teaches them to distrust the whole set — far worse than a missed win.

- A lean, well-structured plan honestly yields **few or zero** findings. "Already well-optimized; two small tool wins" is a correct result, not a weak one. Don't pad the table to look thorough.
- Never promote a **Verify** to **Safe** to make a finding land easier. The assumption is the whole risk; surface it.
- A parallelization or isolation win you can't prove is correct is **Verify** at best — when torn, rate the higher risk and name what would lower it.
- Prefer many small Safe wins you're sure of over one large win you're guessing at.

---

## Chaining with audit-plan (`--audit-first`, or always recommend)

Optimizing a structurally broken plan is wasted effort — and worse, parallelization/isolation can entrench the breakage. The two skills compose:

- **Recommend it by default** when the structural pre-scan (above) fires. Lead the report with the Structural note: "This plan has structural questions optimize-plan won't catch — consider `/audit-plan <file>` first." Offer; don't force.
- **`--audit-first`** — run audit-plan's core axes first. For any section carrying an open **Critical or High** structural finding, skip optimization there and note why. Optimize only the structurally sound parts.
- **Always cross-check the dependency graph.** Even without `--audit-first`, every Parallelization and Ordering finding must be validated against the plan's real dependencies — that's the same analysis audit-plan's axis 3 performs. A "win" that breaks ordering is a regression.

---

## Output Format

```
## Plan Optimization: <plan name or inferred title>

**Lenses applied:** <Context Isolation, Parallelization, Dedup & Ordering, Tool/Command — list only those enabled>
**Schema detected:** <e.g. "Phases → numbered steps, `- [ ]` checkboxes, Pre-flight section present">
[**Structural note:** recommend a structural audit (e.g. /audit-plan) first — <reason>]   ← only if warranted

---

### Findings

| # | Lens | Step / Section | Current | Optimization | Benefit | Risk |
|---|------|----------------|---------|--------------|---------|------|
| 1 | Context Isolation | Step 4 — analyze test logs | Reads full pytest output into main context | Delegate to isolated agent; return only {passed, failed_count, first_3_failures} | Large | Safe |
| 2 | Parallelization | Steps 6–8 — lint, typecheck, test | Run serially | Run concurrently; barrier before Step 9 (report) | 2 steps wall-clock | Verify (confirm no shared writes) |

One finding per row. If a lens found nothing, omit it from the table and mark it PASS in coverage. Do not pad.

### Lens Coverage

| Lens | Status | Findings |
|------|--------|----------|
| Context Isolation | PASS / FINDINGS / N/A | N |
| Parallelization | PASS / FINDINGS / N/A | N |
| Dedup & Ordering | PASS / FINDINGS / N/A | N |
| Tool/Command Efficiency | PASS / FINDINGS / N/A | N |
```

---

## Delivery — diff-first, then write on approval

Default behavior. After the findings table:

1. **Show the proposed rewrite as a diff of changed sections only** — never re-output the whole plan. For each change, show the original block and the optimized block, in the plan's own schema. Group by step/section so the user can accept or reject piecemeal.
2. **List any Verify-risk assumptions** that need the user's confirmation before applying.
3. **Wait for an explicit go-ahead** — "apply", "write it", "proceed", or selective ("apply 1 and 3, skip 2"). A clarifying reply, a question, or "looks good" alone is not approval to write; if ambiguous, ask. Only then write to the plan file, preserving everything you didn't change.

With **`--apply`**, skip the gate: write the optimized plan directly, then show what changed.

When writing, modify only the targeted sections. The optimized plan must be a drop-in replacement — same schema, same intent, leaner execution.

---

## What this skill is NOT

- It does not fix structural gaps, missing error handling, or ambiguous ownership — that's a structural audit's job (e.g. `/audit-plan`).
- It does not change the plan's scope, goals, or outcomes. Same destination, faster route.
- It does not add verification or safety it judges "missing" — adding steps is audit-plan's remit, not an optimization.
- It does not renumber, reformat, or restructure beyond what a specific optimization requires.
