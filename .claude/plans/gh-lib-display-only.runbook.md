# Runbook: gh-lib-display-only loop

**Plan**: `gh-lib-display-only.plan.md`
**Pattern**: sequential
**Mode**: fast (reduced gates)
**Branch**: `worktree-gh-lib-no-browser` (confirmed current branch)

## Pre-flight
Both items confirmed by user 2026-09-09 — see plan file (checked off).

## Safety override
Plan's hard step-ordering constraint takes precedence over the generic
"verify tests pass before first loop iteration" check: the existing suite
is unstubbed and running it before Task 1+3 land reproduces the Chrome
incident. So the loop does **not** run the test suite as a pre-check.
Baseline verification is `bash -n .claude/scripts/gh-lib.sh` only.

## Driver
`/tdd-workflow` implements Tasks 1–6 in order via the Skill tool, honoring
the plan's task ordering and Validation section as the test gates.

## Stop condition
Loop ends when either:
- All items in the plan's `## Acceptance` checklist are satisfied, PR opened
  targeting `develop` (Task 6), or
- A task fails validation twice in a row, or requires a decision the plan
  marks as human-only — in which case stop and report to the user rather
  than retrying indefinitely.

## Monitor
This is a single interactive session executing turn-by-turn; no background
process to poll. Progress is visible in this conversation as each task
completes.
