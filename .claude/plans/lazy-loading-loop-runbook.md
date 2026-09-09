# Loop Runbook: Lazy-Loading Rule System

**Plan**: `.claude/PRPs/plans/lazy-loading-system.plan.md`
**Pattern**: sequential
**Mode**: fast (test gate at phase boundaries, not per task)
**Model tier**: sonnet (default; override with `--model` if needed)
**Stop condition**: every box in the plan's `## Acceptance Criteria` is `[x]`
**Write target**: the repo only — `~/.claude/` is updated by `bash sync.sh --force`, never edited directly (plan § Architecture, *Execution principle*). Sole exception: `~/.claude/settings.json` (Task 2.3). Task 1.3 is the one reverse-direction step: a plain `cp` of the 48 files the plan changes, no `sync.sh`, no `/promote-artifact`, duplicates reconciled per file.

## Pre-flight

Human-only. The loop MUST NOT start until every item is `[x]`.

- [ ] Enable the `ecc@ecc` plugin via `/plugin` — currently `false` in `~/.claude/settings.json`; Task 3.3 folds `knowledge-ops-defaults.md` into the ECC-owned `knowledge-ops` skill
- [ ] Fix context7 MCP auth (fails `AUTH_HEADER_REJECTED`) **or** decide to keep `context7.md` — Task 3.3's own GOTCHA forbids deleting the rule while the plugin is broken
- [ ] Authorize the one direct write outside this worktree: `~/.claude/settings.json` (Task 2.3 hook registration)
- [ ] Confirm you will run the fresh-session manual validations at iterations 3 and 6 — a `claude -p` call cannot observe its own rule injection

## Tooling

| Tool | Type | Needed by | Availability check |
|---|---|---|---|
| `claude` CLI | CLI | every auto iteration | `command -v claude` |
| `/tdd-workflow` | Plugin (skill) | Iteration 2 | listed in available skills |
| `python3` + `pyyaml` | CLI | Iterations 1, 8, stop check | `python3 -c "import yaml"` |
| `pytest` | CLI | Iteration 2 | `python3 -m pytest --version` |
| `jq` | CLI | Iteration 7 (Task 5.2) | `command -v jq` |
| `gh`, authenticated | CLI | Iteration 7 (Task 5.1) | `gh auth status` |

## Loop Iterations

| # | Phase · Tasks | Kind | Gate | Status |
|---|---|---|---|---|
| 1 | Phase 1 · 1.1 → 1.3 | auto | `run-all.sh` green; `sync.sh --dry-run` exit 0 (1.1/1.2); all 48 imported files `cmp`-identical to `~/.claude/` (1.3) | pending |
| 2 | Phase 2 · 2.1 (RED) → 2.2 (GREEN) | auto, under `/tdd-workflow` | RED evidence then GREEN evidence, test file unchanged between | pending |
| 3 | Phase 2 · 2.3 → 2.4 | **HUMAN** | fresh-session cutover check (plan § Manual Validation, first 3 boxes) | pending |
| 4 | Phase 3 · 3.1, 3.2, 3.4 | auto | `run-all.sh` green; 3.2 read-check deferred to iteration 6's session | pending |
| 5 | Phase 3 · 3.3 | auto | eager-load byte script ≥ 4,180 B below 18,759 | pending |
| 6 | Phase 4 · 4.1 (+ 3.2 read-check) | **HUMAN** | one fresh session per hypothesis; cause found or documented as reproducible | pending |
| 7 | Phase 5 · 5.1, 5.2 | auto | `run-all.sh` green; `gh pr create --base main` denied; shadowed `jq` → deny | pending |
| 8 | Phase 6 · 6.1, 6.2 (stretch), 6.3 (decision) | auto | no `settings.json` entry references a deleted file | pending |

## Loop Protocol (fast mode)

Each auto iteration is one self-contained `claude -p` call. Run them in order. Between phases, run the gate; on a red gate, **stop** — do not start the next iteration. At a HUMAN iteration the loop halts until you report the checklist result.

Each `claude -p` call must:
1. Read the plan and execute only its named tasks, in order, following each task's IMPLEMENT / MIRROR / GOTCHA lines.
2. Write only under the worktree; propagate with `bash sync.sh --force`. Deletions: remove repo file + manifest entry, then `rm` the `~/.claude/` copy.
3. Run every VALIDATE line of its tasks and stop on the first failure.
4. Tick the finished tasks' acceptance boxes in the plan and set this table's row to `done`.
5. Commit with a conventional message; no push.

## Execution Commands

```bash
# Tooling gate (run once, before iteration 1)
command -v claude && python3 -c "import yaml" && python3 -m pytest --version && command -v jq && gh auth status

# Iteration 1 — Phase 1
claude -p "Read .claude/PRPs/plans/lazy-loading-system.plan.md. Execute Tasks 1.1, 1.2, 1.3 exactly as written, in order, writing only inside this worktree. Task 1.3 is a plain cp of exactly the 48 files it lists from ~/.claude/ into .claude/ — do NOT run sync.sh or /promote-artifact for it, and do NOT import anything outside that list. For any file that already exists on both sides, apply the DUPLICATES decision recorded in the task and note it in the commit message. Run each task's VALIDATE line and stop on the first failure. Finish with 'bash .claude/tests/run-all.sh'. Commit each task separately with a conventional message. Do not push."

# Gate 1
bash .claude/tests/run-all.sh && bash sync.sh --dry-run   # dry-run is read-only: confirms 1.1/1.2 parse, not an install

# Iteration 2 — Phase 2 RED → GREEN under the TDD skill
claude -p "/tdd-workflow .claude/PRPs/plans/lazy-loading-system.plan.md — execute Task 2.1 (RED) then Task 2.2 (GREEN) only. Task 2.1 must create the stub injector first so every test case fails on its own assertion, not on import; record the failing pytest output as RED evidence. Task 2.2 replaces the stub without touching the test file; record the passing run as GREEN evidence, then run the smoke test in the plan's Validation Commands. Checkpoint-commit after each half. Do not run Task 2.3 or 2.4. Do not push."

# Gate 2
python3 -m pytest .claude/hooks/tests/ -q

# Iteration 3 — HUMAN: cut over (Task 2.3), verify in a fresh session, then delete (Task 2.4)
#   a. Apply the Task 2.3 settings.json change; bash sync.sh --force
#   b. Fresh session: edit a .ts file twice — rule text before the first write, none on the second
#   c. Only if (b) passes: claude -p "Read .claude/PRPs/plans/lazy-loading-system.plan.md and execute Task 2.4 only: delete both retired injectors from the repo and manifest, rm their ~/.claude/hooks/ copies, run 'bash sync.sh --dry-run', commit. Do not push."

# Iteration 4 — Phase 3 (except 3.3)
claude -p "Read .claude/PRPs/plans/lazy-loading-system.plan.md. Execute Tasks 3.1, 3.2, 3.4 in order, including 3.1's SPLIT CLAUSE. Write the classification table into docs/rule-loading-audit.md §3. Propagate with 'bash sync.sh --force'; deletions also rm the ~/.claude/ copy. Run each VALIDATE line except 3.2's fresh-session read-check (deferred to a human). Finish with 'bash .claude/tests/run-all.sh'. Commit per task. Do not push."

# Gate 4
bash .claude/tests/run-all.sh

# Iteration 5 — Task 3.3 (requires pre-flight items 1 and 2)
claude -p "Read .claude/PRPs/plans/lazy-loading-system.plan.md. Execute Task 3.3 only, respecting its SUB-CASES and GOTCHA: fold pr-review and knowledge-ops-defaults into their skills before deleting; delete context7.md only if the context7 plugin connects. Check whether TodoWrite exists in the harness before deciding hooks-todowrite-practices.md. Run the eager-load byte script from Validation Commands and report the number. Commit. Do not push."

# Gate 5
cd ~/.claude/rules && e=0; for f in *.md ecc/common/*.md; do sed -n '1,10p' "$f" | grep -q '^paths:' || e=$((e+$(wc -c < "$f"))); done; echo "$e  (target ≤ 14,579)"; cd - >/dev/null

# Iteration 6 — HUMAN: Task 4.1 bisect, one fresh session per hypothesis, plus the deferred 3.2 read-check
#   Record the outcome in docs/rule-loading-audit.md, then commit.

# Iteration 7 — Phase 5
claude -p "Read .claude/PRPs/plans/lazy-loading-system.plan.md. Execute Tasks 5.1 and 5.2. 5.1: move gh-branch-guard.sh to .claude/hooks/ with a working deny(), update the settings.json path, rm the old ~/.claude/scripts/ copy after sync installs the new one; validate with a dry command, never a real PR. 5.2: remove every '|| true' from the jq calls and deny when jq is absent; validate by shadowing jq with a failing stub. Finish with 'bash .claude/tests/run-all.sh'. Commit per task. Do not push."

# Gate 7
bash .claude/tests/run-all.sh

# Iteration 8 — Phase 6
claude -p "Read .claude/PRPs/plans/lazy-loading-system.plan.md. Execute Task 6.1 (delete the listed dead files from repo, manifest and ~/.claude/), attempt 6.2 as a stretch only if 6.1 is clean, and for 6.3 write the decision and its reasoning into docs/rule-loading-audit.md §2 rather than changing code. Validate that no settings.json entry references a deleted file. Commit. Do not push."

# Stop condition check
grep -c '^- \[ \]' .claude/PRPs/plans/lazy-loading-system.plan.md   # Acceptance Criteria section must contribute 0
bash .claude/tests/run-all.sh && bash sync.sh --dry-run

# Monitor
grep -E '\| (pending|done) \|' .claude/plans/lazy-loading-loop-runbook.md
```
