# Implementation Loop Runbook: User-Wide Claude Portability

**PRD**: `.claude/prds/user-wide-claude-portability.prd.md`
**Pattern**: sequential
**Mode**: fast (no intermediate confirmation prompts)
**Model tier**: sonnet (default; override with `--model` if needed)
**Stop condition**: All 4 implementation artifacts exist and PRD M2–M6 rows are updated to `complete`

## Pre-flight

- [x] Repo is on `main`
- [x] All 5 milestone plans exist under `.claude/plans/`
- [x] PRD M2–M6 rows are `in-progress` with plan paths
- [x] `ECC_HOOK_PROFILE` is not disabled globally — `not set` (hooks enabled)
- [x] No test suite in this repo — test-pass check skipped (`no tests` confirmed)

*No human-only actions required — all work is local filesystem and shell.*

## Loop Iterations

| # | Milestone | Artifact(s) to Create | Status |
|---|---|---|---|
| 1 | M2: Manifest | `manifest.yaml` at repo root | done |
| 2 | M3: Sync script | `sync.sh` at repo root | done |
| 3 | M4: validate-artifact skill | `skills/validate-artifact/SKILL.md` | done |
| 4 | M5 + M6: promote-artifact skill | `skills/promote-artifact/SKILL.md` | done |

## Stop Condition Check

Loop is DONE when:
- [x] `manifest.yaml` exists and passes `python3 -c "import yaml; yaml.safe_load(open('manifest.yaml'))"`
- [x] `sync.sh` exists and passes `bash -n sync.sh`
- [x] `skills/validate-artifact/SKILL.md` exists
- [x] `skills/promote-artifact/SKILL.md` exists with `--git` flag documented
- [x] PRD M2–M6 rows updated to `complete`

## Loop Protocol (fast mode)

Each milestone is implemented by a `claude -p` headless call. Run the commands below in order; each call is fully self-contained and exits when the milestone is done.

## Execution Commands

```bash
# M2: Manifest
claude -p "Read .claude/plans/plan-m2-manifest.plan.md and implement every task in it exactly as specified. Create manifest.yaml at the repo root populated with the full artifact inventory from the plan. Then update the PRD milestone row for M2 in .claude/prds/user-wide-claude-portability.prd.md from 'in-progress' to 'complete'. Run the validation commands from the plan's Validation section and confirm they pass before exiting."

# M3: Sync script
claude -p "Read .claude/plans/plan-m3-sync-script.plan.md and implement every task in it exactly as specified. Create sync.sh at the repo root. Then update the PRD milestone row for M3 in .claude/prds/user-wide-claude-portability.prd.md from 'in-progress' to 'complete'. Run 'bash -n sync.sh' to confirm syntax is clean before exiting."

# M4: validate-artifact skill
claude -p "Read .claude/plans/plan-m4-validate-artifact.plan.md and implement every task in it exactly as specified. Create skills/validate-artifact/SKILL.md in the repo. Then update the PRD milestone row for M4 in .claude/prds/user-wide-claude-portability.prd.md from 'in-progress' to 'complete'. Confirm the file exists before exiting."

# M5 + M6: promote-artifact skill (local + git pipeline)
claude -p "Read .claude/plans/plan-m5-promote-local.plan.md and .claude/plans/plan-m6-promote-git.plan.md and implement all tasks from both plans. Create skills/promote-artifact/SKILL.md in the repo, including the --git flag and full pipeline instructions from M6. Then update the PRD milestone rows for M5 and M6 in .claude/prds/user-wide-claude-portability.prd.md from 'in-progress' to 'complete'. Confirm the file exists before exiting."

# Stop condition check (run after all 4 calls complete)
python3 -c "import yaml; yaml.safe_load(open('manifest.yaml')); print('manifest: OK')"
bash -n sync.sh && echo "sync.sh: OK"
ls skills/validate-artifact/SKILL.md && echo "validate-artifact: OK"
ls skills/promote-artifact/SKILL.md && echo "promote-artifact: OK"

# Monitor loop progress (check between calls)
grep -E "pending|done" .claude/plans/impl-loop-runbook.md
```
