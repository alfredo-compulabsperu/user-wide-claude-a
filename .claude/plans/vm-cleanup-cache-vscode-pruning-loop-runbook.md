# Loop Runbook: `.cache` Full-Wipe + `.vscode-server` Stale-Version Pruning

**Plan**: `.claude/plans/vm-cleanup-cache-vscode-pruning.plan.md`
**Pattern**: sequential
**Mode**: fast
**Stop condition**: All 4 tasks marked `done` below, all 7 checkboxes under the plan's Acceptance
Criteria + Acceptance sections are checked, and `bash .claude/tests/run-all.sh` plus
`shellcheck .claude/scripts/vm-cleanup.sh` are green.

## Tooling

| Tool | Type | Needed by | Availability check |
|---|---|---|---|
| `tdd-workflow` skill | Plugin | Tasks 1-2 (RED/GREEN cycles) | listed in available skills — confirmed (global `~/.claude/skills/tdd-workflow`; repo-local copy archived, global still resolves) |
| `git` | CLI | Every iteration (per-task commits) | `git --version` — confirmed |
| `shellcheck` | CLI | Validation, each iteration | confirmed 0.11.0 |
| `gh` CLI, authenticated | CLI | Final step (PR to `develop`) | `gh auth status` — confirmed authenticated as `alfredo-compulabsperu` |

## Fast-Mode Deviations from the Plan's Own Gates

The plan itself only requires each task's own `Validate:` line (`bash .claude/tests/run-all.sh`)
after its RED/GREEN cycle — there is no isolated-environment second pass or coverage threshold in
this plan (unlike the prior `vm-cleanup-hardening` plan). So fast mode changes nothing about
per-task gates here; it only means: no extra confirmation checkpoint between tasks, and the plan's
`## Validation` block runs once at the end (after Task 4) rather than being re-run after every task.

## Baseline Check

`bash .claude/tests/run-all.sh` confirmed GREEN before this loop starts (8/8 suites, all
assertions passed). `vm-cleanup.test.sh` already exists on this branch (from the prior hardening
plan) — Tasks 1-2 add new assertions to it, they don't create it.

## Loop Iterations

| # | Task | Description | Status |
|---|---|---|---|
| 1 | Task 1 | `.cache` whole-dir wipe: RED (sandboxed `.cache` w/ `foo`/`bar`/`firebase/emulators`/`thumbnails` fixtures) → GREEN (rewrite section 6, exclude `firebase`) | done |
| 2 | Task 2 | `.vscode-server` stale-version pruning: RED (sandboxed `bin/`+`cli/servers/` fixtures incl. `.staging` and 0/2+-entry edge cases) → GREEN (new final section) | done |
| 3 | Task 3 | Docs: `docs/vm-cleanup.md` classification table SAFE row + new `.vscode-server` prose section | done |
| 4 | Task 4 | Flip US-VMCLEANUP-4/-5 `Implementation: Open → Closed` in `docs/user-stories/vm-cleanup.md`, version-history entry, update `docs/user-stories/index.md` | done |

## Stop Condition Check

Loop is DONE when all 4 rows above read `done`, every checkbox under the plan's Acceptance
Criteria and Acceptance sections is checked, and the final validation pass (Loop Protocol step 7)
is green.

## Loop Protocol

For each pending task, in order:

1. Read that task's `Action` / `Mirror` / `Validate` from `vm-cleanup-cache-vscode-pruning.plan.md`.
2. Tasks 1-2: invoke the `tdd-workflow` skill for that task's RED → GREEN cycle. Tasks 3-4: docs-only edits, no TDD cycle (per the plan's own `Validate: n/a (docs-only)` for Task 4, and manual-read validation for Task 3).
3. Run the task's `Validate:` command(s); confirm green before advancing.
4. Check off any Acceptance Criteria / Acceptance checkboxes the task closes in the plan file.
5. Mark the task's row above `done`; commit the task's changes.
6. Move to the next pending task.

After Task 4 (all rows `done`):

7. Run the plan's full `## Validation` block: `shellcheck .claude/scripts/vm-cleanup.sh`,
   `bash .claude/tests/run-all.sh`, and the manual `--dry-run` check (confirm new targets show up,
   no writes).
8. Update this plan's row in `.claude/plans/index.md` from "pending" to "complete".
9. Open a PR against `develop` (per this repo's PR Base Branch rule — never `main`) summarizing
   both tasks (US-VMCLEANUP-4, US-VMCLEANUP-5).

## Start & Monitor

```bash
# Start: proceed with Task 1 per the Loop Protocol above (this session, one task at a time).

# Monitor progress at any point:
cat .claude/plans/vm-cleanup-cache-vscode-pruning-loop-runbook.md   # this file: iteration table + stop condition
git log --oneline -10                                                # per-task commits as the loop advances
bash .claude/tests/run-all.sh                                        # current test state
```
