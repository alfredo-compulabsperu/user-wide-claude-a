# Runbook: user-wide-claude-portability

PRD: `.claude/prds/user-wide-claude-portability.prd.md`

## Phase 0 — Isolate
Reused current worktree `worktree-claude-md` at
`/home/alfredo/user-wide-claude-a/.claude/worktrees/claude-md` — this session
was already opened for CLAUDE.md portability work (window/branch named
`claude-md`), matching the PRD's intent. No nested worktree created.

## Config
- Mode: unattended (default, no `--confirm` passed)
- `run-prd bindings`: none declared in CLAUDE.md / `.claude/rules/*` /
  `.claude/run-prd.bindings.*` → all fallbacks apply:
  - `tdd` → `/ecc:tdd-workflow`
  - `review.fast` → `ecc:code-reviewer` agent
  - `isolation` → inner rubric
- Review depth: `fast` (default)

## Pre-flight (human-only chores)
None identified — milestone 7 (CLAUDE.md portability) is filesystem/git work
only: copying a file, editing skill markdown, editing manifest.yaml/sync.sh,
committing, pushing, opening a PR. No credentials, UI clicks, or external
access grants required.

Gate: clear — proceeding immediately.

## Milestones (from PRD)
| # | Milestone | Status at run start |
|---|---|---|
| 1-6 | audit, manifest, sync script, validate-artifact, promote-artifact (local + git) | complete |
| 7 | CLAUDE.md portability | pending |

## Phase A — Plan milestone 7
- [x] Run `/ecc:plan` on the PRD → `.claude/plans/plan-m7-claude-md-portability.plan.md`
- [x] Dependency-sequence check (single self-contained unit, no shared-dependency ordering risk)
- [x] Set milestone 7 `Status = in-progress`

## Phase B — Implement
- [x] Classify plan: non-code (docs/config: repo copy of CLAUDE.md, manifest.yaml flag,
      SKILL.md instruction updates) → implemented inline (main agent), not TDD/isolated —
      single sequential unit, no independent siblings, context not oversized
- [x] Verify plan/PRD fidelity — all 6 tasks completed as specified; validate-artifact
      correctly left unchanged per plan
- [x] Set milestone 7 `Status = complete`

## Phase C — Consolidate
- [x] Reconcile PRD prose status footer → "EXECUTED — all milestones complete."
- [ ] Commit all files touched by the run
- [ ] Push + create/update PR targeting `develop`

## Phase D — Review (fast)
- [ ] One pass via `ecc:code-reviewer` agent; fix all non-LOW findings
- [ ] File LOW/out-of-scope findings as a follow-up issue if any

## Deviations
None — implementation matched the plan exactly.

Noted but out of scope for M7 (pre-existing, from M6): `promote-artifact/SKILL.md`'s
git pipeline hardcodes `--base main` for its PR, which conflicts with this repo's
own PR-base convention (`develop`). Left untouched here to avoid scope creep;
flagged in the final run-prd report as a follow-up.

## Stop condition
Not yet met — Phase C/D still pending.
