# Loop Runbook: User-Wide Claude Portability — Implementation Plans

**PRD**: `.claude/prds/user-wide-claude-portability.prd.md`
**Pattern**: sequential
**Mode**: safe
**Stop condition**: All 5 pending milestones have an implementation plan file under `.claude/plans/`

## Pre-flight

- [x] Repo is on `main`, clean (only untracked outside scope)
- [x] PRD exists and has been read
- [x] `.claude/plans/` directory created

## Loop Iterations

| # | Milestone | Plan file | Status |
|---|---|---|---|
| 1 | M2: Manifest format | `plan-m2-manifest.plan.md` | done |
| 2 | M3: Sync script | `plan-m3-sync-script.plan.md` | done |
| 3 | M4: `/validate-artifact` skill | `plan-m4-validate-artifact.plan.md` | done |
| 4 | M5: `/promote-artifact` local | `plan-m5-promote-local.plan.md` | done |
| 5 | M6: `/promote-artifact` git pipeline | `plan-m6-promote-git.plan.md` | done |

## Stop Condition Check

Loop is DONE when all 5 plan files exist and each contains a concrete step-by-step implementation plan.

## Loop Protocol

For each pending milestone:
1. Invoke `/ecc:plan` with the milestone scope
2. Write the plan to the corresponding file under `.claude/plans/`
3. Mark the milestone row above as `done`
4. Update the PRD's Delivery Milestones table with the plan file path
5. Move to next milestone
