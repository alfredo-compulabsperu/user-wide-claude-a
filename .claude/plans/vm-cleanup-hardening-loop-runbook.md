# Loop Runbook: vm-cleanup.sh Hardening

**Plan**: `.claude/plans/vm-cleanup-hardening.plan.md`
**Pattern**: sequential
**Mode**: fast
**Stop condition**: All 7 tasks marked `done` below, all 15 Acceptance Criteria in the plan checked, and `bash .claude/tests/run-all.sh` plus `shellcheck .claude/scripts/vm-cleanup.sh` are green.

## Tooling

| Tool | Type | Needed by | Availability check |
|---|---|---|---|
| `tdd-workflow` skill | Plugin | Every iteration (Tasks 1-7) | listed in available skills — confirmed |
| `git` | CLI | Every iteration (cherry-pick, per-task commits) | `git --version` — confirmed |
| `gh` CLI, authenticated | CLI | Final step (PR to `develop`) | `gh auth status` — confirmed authenticated (per plan's own Tooling table) |
| `shellcheck` | CLI | Validation, each iteration | confirmed 0.11.0 (per plan's own Tooling table) |
| `kcov` | CLI | Task 7 iteration | confirmed installed (per plan's own Tooling table) |
| `/validate-artifact` skill | Plugin | Task 6 iteration | `name-only`, model-invocable (per plan's own Tooling table) |

## Fast-Mode Deviations from the Plan's Own Gates

The plan (`vm-cleanup-hardening.plan.md`) was authored assuming safe-mode TDD gates. The user
selected **fast** mode for this loop, so:

- The plan's mandatory isolated-environment second pass (`env -i PATH=/usr/bin:/bin HOME=...
  bash .claude/tests/run-all.sh`) runs once at the end (Step 7 of the Loop Protocol below), not
  after every task's GREEN.
- The plan's 90% `kcov` coverage threshold (Task 7) is treated as a target with a documented gap
  allowed, not a loop-blocking hard failure. This is not itself a fast-mode relaxation — AC10
  already permits "an explicitly documented, justified gap" regardless of mode — it's listed
  here only so the loop doesn't stall waiting for a number the plan never required as absolute.
- Every task's own `Validate:` line (`bash .claude/tests/run-all.sh` after each RED/GREEN cycle)
  still runs every iteration — that is baseline TDD, not an extra safe-mode gate, and is not
  skipped.

## Baseline Check

No `vm-cleanup.test.sh` or `.claude/tests/run-all.sh` exist on this branch yet (confirmed via
`ls .claude/tests/scripts/` before this runbook was written) — the promoted suite arrives with
Task 1's cherry-pick. "Verify tests pass before first loop iteration" therefore applies to the
repo's existing suites (`gh-lib.test.sh`, `sync.test.sh`, etc.), not to `vm-cleanup.test.sh`,
which does not exist until Task 1 completes it.

## Loop Iterations

| # | Task | Description | Status |
|---|---|---|---|
| 1 | Task 1 | Cherry-pick `18ceb9d` + confirm GREEN baseline (plus ~6 new assertions closing AC1/AC3/AC4 gaps) | done |
| 2 | Task 2 | Rename `--yes` → `--risky`; add `--dry-run` as explicit alias | done |
| 3 | Task 3 | Rewrite `--help` to explain both SAFE/RISKY tiers | done |
| 4 | Task 4 | Harden exit codes (script currently always exits 0) | done |
| 5 | Task 5 | Idempotency check (second `--clean --risky` run is a no-op) | pending |
| 6 | Task 6 | Command file (`.claude/commands/vm-cleanup.md`), manifest registration, docs | pending |
| 7 | Task 7 | Coverage — wire `kcov`, close gaps toward 90% | pending |

## Stop Condition Check

Loop is DONE when all 7 rows above read `done`, every checkbox under the plan's Acceptance
Criteria (AC1-AC15) is checked, and the final validation pass (Loop Protocol step 7) is green.

## Loop Protocol

For each pending task, in order:

1. Read that task's `Action` / `Mirror` / `Validate` from `vm-cleanup-hardening.plan.md`.
2. Invoke the `tdd-workflow` skill for that task's RED → GREEN → IMPROVE cycle.
3. Run the task's `Validate:` command(s); confirm green before advancing.
4. Check off any Acceptance Criteria the task closes in the plan file.
5. Mark the task's row above `done`; commit the task's changes.
6. Move to the next pending task.

After Task 7 (all rows `done`):

7. Run the plan's full `## Validation` block: `shellcheck`, `bash .claude/tests/run-all.sh`,
   `kcov`, the isolated-environment second pass, and the manual `--help`-vs-docs check.
8. Run `/validate-artifact` on both `.claude/scripts/vm-cleanup.sh` and
   `.claude/commands/vm-cleanup.md` (AC15).
9. Update this plan's row in `.claude/plans/index.md` from "not started" to "complete".
10. Open a PR against `develop` (per this repo's PR Base Branch rule — never `main`) summarizing
    all 7 tasks.

## Start & Monitor

```bash
# Start: proceed with Task 1 per the Loop Protocol above (this session, one task at a time).

# Monitor progress at any point:
cat .claude/plans/vm-cleanup-hardening-loop-runbook.md   # this file: iteration table + stop condition
git log --oneline -10                                     # per-task commits as the loop advances
bash .claude/tests/run-all.sh                              # current test state (once Task 1 lands it)
```
