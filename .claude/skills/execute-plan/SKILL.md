---
name: execute-plan
description: |
  Drive a saved plan file end-to-end to a merged-ready, reviewed PR. Verifies the plan
  is properly sequenced via the planner agent, builds and saves a runbook that dynamically
  finds which phases/tasks can be isolated, executes each as a fresh isolated agent gated
  by commit+push+PR, threads discovered context forward between agents via a structured
  OK/WARN/ERROR handoff report, self-audits for rule violations after implementation and
  files a tracked GH issue, then runs bounded isolated /ecc:review-pr rounds until clean.
  Use whenever the user says "execute this plan", "implement this plan end to end", "run
  this plan and ship a PR", "take this plan to a merged PR", "isolate and implement <plan
  file>", "drive this plan to completion" — or references an existing plan file
  (.claude/plans/*.plan.md) and asks you to carry it out, even without the word "execute."
---

# Execute Plan — Isolated, Gated, Context-Threaded

A saved plan is a list of intentions. This skill turns it into working, reviewed,
committed code without one giant conversation holding all the state — instead, a
runbook drives a chain of fresh, isolated agents, each one reporting back just
enough for the next one to pick up cleanly.

## Why isolation, and why a structured handoff

A single long conversation executing a multi-step plan accumulates context it
doesn't need (every file read, every dead end) and risks drift (later steps
subtly reinterpreting earlier decisions). Isolated agents fix the bloat but
create a new problem: an agent with zero memory of prior units can't know a
path it needs, a decision an earlier unit made, or a constant discovered along
the way — unless something explicitly hands that fact forward. That's the
**context ledger**: each unit reports what downstream units need to know, the
runbook accumulates it, and it gets threaded into the next dependent unit's
prompt. Nothing is assumed shared; everything needed is explicit.

## Dependencies

- `ecc:planner` agent (ships with the ecc plugin) — sequencing check.
  **Fallback chain**: if `ecc:planner` isn't available in this session, search
  installed agents for any name containing "planner" (case-insensitive) and use
  that instead. If none exists at all, **HALT** — tell the user no planner agent
  is available and ask how to proceed. Do not skip sequencing silently.
- `/ecc:loop-start` (sequential, fast mode) — runbook scaffolding, if available.
  If the command isn't installed, build the runbook directly following Step 2
  below — the command is a convenience, not a hard dependency.
- `/ecc:review-pr` — the review-loop step.
- `gh` CLI, authenticated, with a remote the current branch can open/target a PR
  against.

## Step 0: Locate and verify the plan

Confirm the plan file is actually saved to disk (not just discussed in chat —
if it only exists in the conversation, write it first). Then dispatch
`ecc:planner` (fallback chain above) to check sequencing: does every consumer
of an artifact/field/dependency come after the unit that creates it? Does every
deletion come after its replacement? Fix ordering issues in the plan file
before proceeding — don't execute a plan you know is mis-sequenced.

## Step 1: Pre-flight completeness gate

Before dispatching a single agent, read every unit in the plan and ask: **does
this unit's description contain everything a fresh agent with no memory of the
rest of the plan needs to execute it correctly?** Two ways a unit can be
missing information, and they get different treatment:

- **Resolvable via handoff** — the missing fact will exist once an earlier unit
  runs (a file path it creates, a decision it makes, an ID it generates). Not a
  blocker — note it as an expected `HANDOFF` input for this unit in the runbook
  (Step 2), and Step 3 will thread it forward automatically.
- **Not resolvable by any unit in the plan** — a human decision, a credential,
  a missing requirement the plan itself never specified. **HALT here.** Surface
  the gap to the user before running anything. This is the same principle as a
  Pre-flight Phase for human-only chores, extended to missing *information*,
  not just missing *actions*.

Don't proceed past this gate with a known gap "hoping it works out" — a unit
that hits a missing fact mid-execution wastes the isolated-agent spawn and
produces a confusing partial result instead of a clean halt.

## Step 2: Build and save the runbook

Call `/ecc:loop-start --pattern sequential --mode fast` if available, directing
it to produce the runbook described below; otherwise build it directly. Save
to `<plan-path-without-.plan.md>.runbook.md`, next to the plan file.

**Finding isolatable units is dynamic, not a fixed grain.** Don't default to
"one unit per plan Task" or "one unit per plan Phase" — inspect the plan's own
dependency structure (its Files to Change / Tasks / Risks sections) and pick
the coarsest grouping where:
- every dependency of the group is satisfied by an earlier group (or nothing),
- the group doesn't require live conversational judgment mid-stream (a human
  choosing between options *while* the unit runs — that stays inline, not
  isolated),
- the group's validation can run standalone (the plan's own Validate/Acceptance
  criteria for that scope).

Coarser is cheaper (fewer agent spawns) and usually right when a plan's phases
are already dependency-ordered top-level units (e.g. PRD milestones). Finer is
right when a single phase bundles independent sub-changes that would otherwise
force serialization for no reason.

Runbook contents: unit list in execution order, each unit's dependencies, each
unit's expected `HANDOFF` inputs (from Step 1), and a `## Context Ledger`
section — empty at creation, appended to as units complete (Step 3).

## Step 3: Execute units — isolated, gated, context-threaded

For each unit, in order:

1. **Build the prompt.** Fully self-contained: the plan's relevant section, any
   file paths involved, the accumulated `## Context Ledger` entries this unit
   depends on (copy them in — don't reference "see the ledger," the agent can't
   read files you haven't told it to), and the mandatory report format below.
2. **Dispatch as a fresh isolated agent** (foreground, sequential — no shared
   memory with prior units or the main conversation).
3. **Require this report format**, last thing in the agent's response:
   ```
   STATUS: OK | WARN | ERROR
   SUMMARY: <one paragraph, what happened>
   HANDOFF: <facts a downstream unit needs — paths created/moved, decisions
             made, IDs/hashes/commit SHAs, discovered constraints — or "none">
   ```
4. **Gate on STATUS:**
   - **OK** — append `HANDOFF` to the runbook's Context Ledger. Commit → push →
     open or update the PR (reuse an existing open PR for this branch if one
     exists; otherwise open one targeting the repo's stated integration branch
     — commonly `develop`, else the repo's documented default). Proceed.
   - **WARN** — same actions as OK (ledger updated, gate passes, execution
     continues) but log the warning prominently in the runbook's running log
     AND the final report (Step 6). A WARN that silently disappears defeats
     the point of having the status — it must surface to the user even though
     it didn't block.
   - **ERROR** — **HALT.** Do not dispatch further units. Do not commit/push
     the failed unit's partial work without asking. Surface the failing unit's
     `SUMMARY` to the user and wait for direction (fix and resume from this
     unit, adjust the plan, or abandon).

## Step 4: Review loop

Run `/ecc:review-pr` in isolation (a fresh agent each round, given the plan
file path and its Acceptance criteria as grounding — not just "review the
diff" with no reference point), bounded:

- **Round 1** — always runs. Fix every non-LOW finding.
- **Round 2** — always runs, regardless of what round 1 found.
- **Round 3+** — only if the immediately prior round found any non-LOW issue.
  Stop at the first round that finds nothing.

Each round is isolated and pushes its own fixes. **Keep every round's raw
findings list** (fixed and deferred alike) — Step 5's retrospective needs the
full record, not just "round N: N fixes applied."

## Step 5: Retrospective — violations, review-pr findings, root causes, remediations

Only after the plan is fully implemented AND reviewed (Step 4 complete) —
root-causing review-pr findings before they exist isn't possible, so this step
comes last, not right after Step 3.

Produce one combined analysis covering two sources:

1. **Rule violations** — review the full set of changes against this repo's
   `CLAUDE.md` and `rules/*.md`: which rules were violated, in which unit, when.
2. **Review-pr findings** — every non-LOW issue any round of Step 4 surfaced,
   fixed or not, not just the ones still open.

For **every item in both lists**:
- **Root cause** — not "what broke" (already known from the finding itself)
  but *why the process produced it*. A missing rule in a unit's prompt? An
  assumption that didn't hold? A gap Step 1's completeness gate should have
  caught but didn't?
- **Confidence level** (High/Medium/Low) on the root-cause diagnosis itself —
  root-causing after the fact is inherently uncertain; say so plainly rather
  than presenting a guess as settled fact.
- **Proposed remediation for future `execute-plan` loops** — framed through
  KISS, YAGNI, SRP, DRY, JIT: name which principle the fix embodies and why
  (e.g. "fold the missing check into Step 1's completeness gate — DRY, one
  place enforces it instead of hoping every unit prompt remembers" or "don't
  add a speculative pre-check for a failure mode that hasn't recurred —
  YAGNI"). A remediation with no named principle is probably vague — tighten
  it until it names one.

File this whole analysis as a GH issue labeled `harness` (what / when / why /
confidence / proposed remediation per item — both categories in one issue,
not two). **Track only — do not auto-fix in this step.** Fixing belongs to a
deliberate follow-up the user triages, not a step buried inside an autonomous
run. If neither list has anything in it, skip the issue and say so plainly in
the final report — don't file an empty "no issues" issue.

## Step 6: Report back

Summarize: units executed with their STATUS (flag every WARN explicitly, don't
bury it in a list), commits/PR link, the review rounds run with what each
found and fixed, and the retrospective — link the harness issue if filed, or
confirm none was needed.

## When NOT to use this

- A plan with one or two trivial, tightly-coupled changes — the isolation and
  gating overhead isn't worth it. Just make the change.
- The user wants to watch/direct execution live, step by step — this skill's
  whole model is autonomous progression through units; if they want to approve
  each step interactively, don't isolate, just do the work turn by turn.
