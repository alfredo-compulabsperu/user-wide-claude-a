# Plan: vm-cleanup.sh hardening — merge the stranded fix, rename flags, add safety/quality gates

**Complexity**: Medium

## Tooling

| Tool | Type | Needed by | Availability check |
|---|---|---|---|
| `git` | CLI | All tasks | `git --version` |
| `kcov` | CLI | Task 7 | `command -v kcov` — confirmed installed |
| `shellcheck` | CLI | Validation, Task 6 | `command -v shellcheck` — confirmed 0.11.0 |
| `gh`, authenticated | CLI | PR creation (post-plan) | `gh auth status` — confirmed authenticated |
| `python3` + PyYAML | CLI | CI workflow (sync.sh dependency, not this plan directly) | already required by this repo's `sync.sh` |
| `tdd-workflow` skill | Plugin | Tasks 1-7 | listed in available skills |
| `/validate-artifact` skill | Plugin | Task 6 | appears in this session's available-skills listing **and is model-invocable** — now `name-only` in `.claude/settings.json`. Was `user-invocable-only`, which lets only the user run it by hand and blocks Claude from invoking it at all; presence on disk under `.claude/skills/` is *not* the check |

## Summary

`worktree-lazy`'s commit `18ceb9d` already fixes a real gap in `.claude/scripts/vm-cleanup.sh`
(section 9's `node_modules` deletion didn't honor the active-worktree guards section 10
uses) and promotes a 12-assertion test suite, a `.claude/tests/run-all.sh` runner, and a
CI workflow — but it was never merged to `develop`. This plan lands that commit, then
hardens the script further: rename the misleading `--yes` flag, rewrite `--help` to
actually explain the two action tiers, make failures surface in the exit code, verify
idempotency, and reach 90% line coverage via `kcov`. Driven by `tdd-workflow`.

No deployment step. `sync.sh`/`manifest.yaml` govern when this reaches `~/.claude/`, and
that is a separate, later decision — out of scope here.

## Background

Three copies of `vm-cleanup.sh` exist right now:

| Copy | Content |
|---|---|
| `~/.claude/scripts/vm-cleanup.sh` (deployed, live) | Has the active-worktree guard. SHA-256 `928ac995…` |
| This repo's `develop` (and this `worktree-cleanup` branch) | 318 lines, **missing** the guard. SHA-256 `3d278ecd…` |
| `worktree-lazy` branch, commit `18ceb9d` | Adds the guard + tests + CI. Not merged anywhere. |

`~/.claude/.sync-state.json` records `928ac995…` as the last-synced hash for
`scripts/vm-cleanup.sh` — the deployed copy was manually synced from `18ceb9d` (or a
close relative) at some point, bypassing `develop`. `develop` itself never received it.

`18ceb9d`'s parent commit is exactly this worktree's current `HEAD` (`8390656`) — the
four other commits on `worktree-lazy` (lazy-loading-system audit, plugin settings,
scratchpad cleanup, a plan-doc edit) touch none of `18ceb9d`'s files. It cherry-picks
with zero drift.

`18ceb9d`'s own commit message documents its content precisely: adds `_tree_is_active()`
(checked out / locked / uncommitted changes) and calls it from section 9's loop; promotes
`.claude/tdd/test-vm-cleanup-issue-36.sh` into `.claude/tests/scripts/vm-cleanup.test.sh`
(155 lines, 12 `pass`/`fail` assertions — script-exit-0, worktree-removal-leaves-no-husk,
protected-file rescue at shallow and depth-6, locked/dirty-worktree-untouched, and three
assertions for the new node_modules guard); adds `.claude/tests/run-all.sh`; adds
`.github/workflows/tests.yml`.

Issue #36 (closed) already covered husk prevention and the depth-mismatched protection
scan — both already in the pre-cherry-pick script and untouched by this plan.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Test style | `.claude/tests/scripts/gh-lib.test.sh`, `sync.test.sh` | Hand-rolled `pass()`/`fail()` bash — **this repo has no bats**; do not introduce it |
| Test runner | `18ceb9d:.claude/tests/run-all.sh` | Iterates `*.test.sh` under `.claude/tests/scripts/`, sandboxes `$HOME` |
| PATH-stub mocking | `18ceb9d:.claude/tests/scripts/vm-cleanup.test.sh:30-45` | Stub `sudo`/`apt-get`/`journalctl`/`npm`/`snap` before invoking the script under test |
| CI | `18ceb9d:.github/workflows/tests.yml` | `actions/checkout` → install PyYAML (sync.sh dependency) → git identity → `bash .claude/tests/run-all.sh` |
| Manifest registration | `manifest.yaml:43-44` (script), `manifest.yaml:16-21` (commands) | `- name: <file>` with `executable: true` where applicable |
| Artifact portability gate | `.claude/skills/validate-artifact/SKILL.md` | Repo's own pre-promotion check: no hardcoded `/home/`, usernames, secrets |

## Files to Change

| File | Action | Why |
|---|---|---|
| `.claude/scripts/vm-cleanup.sh` | UPDATE | Cherry-pick `18ceb9d`'s fix, then rename/harden further |
| `.claude/tests/scripts/vm-cleanup.test.sh` | UPDATE | Cherry-picked from `18ceb9d`, then extended for each new behavior |
| `.claude/tests/run-all.sh` | CREATE (cherry-picked) | Test runner, from `18ceb9d` |
| `.claude/tdd/test-vm-cleanup-issue-36.sh` | DELETE (via cherry-pick rename) | Tracked on HEAD; `18ceb9d` renames it to `.claude/tests/scripts/vm-cleanup.test.sh`, so the cherry-pick removes this path. `.claude/tdd/vm-cleanup-issue-36.tdd.md` is untouched |
| `.github/workflows/tests.yml` | CREATE (cherry-picked) | CI, from `18ceb9d` |
| `.claude/commands/vm-cleanup.md` | CREATE | Does not exist in this repo yet — the deployed command was never tracked here |
| `manifest.yaml` | UPDATE | Add `commands: - name: vm-cleanup.md` (script entry already present at line 43) |
| `docs/RUNBOOK.md` or a new `docs/vm-cleanup.md` | UPDATE/CREATE | Document both flags per this repo's docs convention (check `RUNBOOK.md` shape before choosing) |
| `.claude/plans/index.md` | UPDATE | Register this plan |

## Tasks

`tdd-workflow` Step 0 applies as: no `package.json`, `.claude/tests/scripts/*.test.sh`
exist, hand-rolled `pass()`/`fail()` bash (not Bats). Runner = `bash .claude/tests/run-all.sh`
(or scoped: `bash .claude/tests/scripts/vm-cleanup.test.sh`), lint = `shellcheck
.claude/scripts/vm-cleanup.sh`, coverage = `kcov --include-path=. coverage/ bash
.claude/tests/scripts/vm-cleanup.test.sh`. Coverage threshold for this plan is **90%**,
overriding the skill's stock 80%. The skill's mandatory second isolated-environment pass
(`env -i PATH=/usr/bin:/bin HOME=... bash .claude/tests/run-all.sh`) applies before any
GREEN is called final — this script reads `$HOME` and git worktree state throughout, the
exact leak-prone shape that check exists for.

### Task 1: Cherry-pick `18ceb9d`, confirm GREEN baseline
- **Action**: `git cherry-pick 18ceb9d` onto this branch. Zero-drift per Background —
  confirm no conflicts. This is not itself a TDD cycle (no new behavior beyond what
  `18ceb9d` already proves); it establishes the baseline every later task diffs against.
  **AC2 is satisfied here** by the promoted suite's 12 assertions. **AC1, AC3 and AC4 are
  not — closing them is part of this task.** Verified against the suite, which invokes the
  script exactly once (line 95, `bash "$SCRIPT" --clean --yes`) and reads all 12 assertions
  off that single run:
  - **AC1** — asserts 3 of the 7 section-10 guards (locked, dirty, protected-files-present)
    plus the 3 new section-9 node_modules cases. **No assertion for `self`,
    unreadable-status (`GIT_ERROR`), no-upstream, or ahead-of-upstream.** Add those 4.
  - **AC3** — protected-file rescue is covered at shallow and depth-6, but the
    "a rescue that *fails* aborts the removal" branch is not. Add it.
  - **AC4** — **zero coverage.** Scan mode is never exercised: no bare invocation and no
    `--dry-run` run exists anywhere in the suite. Add a scan-mode case asserting no mutation.
  So this task is cherry-pick **plus ~6 new assertions**, not a pure baseline step — budget
  accordingly.
- **Mirror**: n/a — direct cherry-pick, not a re-implementation.
- **Validate**: `bash .claude/tests/run-all.sh` — all suites green, including the new
  `vm-cleanup.test.sh`.

### Task 2: Rename `--yes` → `--risky`; add `--dry-run` as an explicit alias
- **Action**: RED — add a case to `vm-cleanup.test.sh` asserting `--risky` unlocks the
  CONFIRM-tier actions and bare `--yes` is rejected as an unknown arg (no deprecated
  alias — single-user tool). Note the rationale is *not* "no external callers": the deployed
  `~/.claude/commands/vm-cleanup.md` does end with "rerun with `--clean --yes`". Task 6
  rewrites that file, which is what makes dropping the alias safe. Add a case asserting bare invocation
  and `--dry-run` behave identically. GREEN — rename `YES` → `RISKY` throughout the
  script, add `--risky` and `--dry-run` to the arg parser, update every `[CONFIRM]`
  output label to `[RISKY]`, update the two "Rerun with `--clean --yes`" summary lines.
  **Also re-plumb the suite's own invocation, in the same commit as the rename**:
  `vm-cleanup.test.sh` line 95 (`bash "$SCRIPT" --clean --yes`) is the single call every one
  of the 12 promoted assertions reads from. The moment `--yes` is rejected as an unknown arg
  the script exits 1, `$OUT` becomes "Unknown arg: --yes", and all 12 collapse at once —
  a full-suite red for entirely the wrong reason. Change it to `--clean --risky`.
- **Mirror**: existing arg-parsing `case` block in the script.
- **Validate**: `bash .claude/tests/run-all.sh`.

### Task 3: Rewrite `--help` to explain both tiers
- **Action**: RED — add a case asserting `--help` output contains "SAFE", "RISKY", and
  at least one example target from each tier (e.g. "apt cache" for SAFE, "worktree" for
  RISKY) — fails today, since `--help` only echoes the 3-line `# Usage:` comment block.
  GREEN — replace the usage-comment-grep with a real help block naming both tiers, what's
  in each, and the exact flags.
- **Mirror**: none in this repo yet for a rich `--help`; `docs/RUNBOOK.md` for prose style.
- **Validate**: `bash .claude/tests/run-all.sh`. The `--help`-vs-docs drift check happens
  in Task 6, once the docs file exists — not here.

### Task 4: Harden exit codes (script currently always exits 0)
- **Action**: RED — inject a failing action and assert it surfaces. **Do not stub `rm`**:
  the section-10 removal path delegates to the VCS's own worktree-removal subcommand, which
  unlinks internally rather than shelling out to `rm`, so a `$PATH` stub never intercepts it
  — and a global `rm` stub also breaks the harness's own sandbox teardown. Instead pick a
  target the script really does reach through `$PATH` (e.g. stub `sudo`/`apt-get`/`journalctl`
  to exit non-zero for a SAFE-tier action), or make a `_confirm` target path unwritable.
  Assert non-zero exit and that the summary reports the failure. Fails today because
  `_safe`/`_confirm` wrap every action in `|| true`. GREEN —
  track a `FAILURES` counter, increment inside `_safe`/`_confirm` on non-zero exit, print
  failed actions in the Summary section, exit 1 if `FAILURES > 0`.
- **Mirror**: the existing `TOTAL_BYTES` accumulator pattern — same shape, new counter.
- **Validate**: `bash .claude/tests/run-all.sh`; confirm a normal successful run still
  exits 0.

### Task 5: Idempotency check
- **Action**: RED — add a case: run `--clean --risky` twice against the same sandbox,
  assert the second run's `FAILURES` is 0 and performs no destructive action beyond
  what's already gone. GREEN — guard each `_confirm` action with an existence check
  before invoking, or confirm the existing guards already provide this and document
  which (don't invent a PASS that wasn't actually run).
- **Mirror**: existing `[[ -d "$target" ]]` existence checks in sections 6/7/8.
- **Validate**: `bash .claude/tests/run-all.sh`.

### Task 6: Command file, manifest registration, docs
- **Action**: Write `.claude/commands/vm-cleanup.md` (the deployed copy exists at
  `~/.claude/commands/vm-cleanup.md` — read it for reference, but it is untracked
  anywhere in this repo's git history; treat it as a starting draft, not a source of
  truth, since manifest.yaml never listed it). Add `commands: - name: vm-cleanup.md` to
  `manifest.yaml`. Read `docs/RUNBOOK.md`'s existing shape and either extend it or add a
  new `docs/vm-cleanup.md` matching that convention — document `--clean`, `--risky`,
  `--dry-run`, and what's in each of the SAFE/RISKY tiers. Every flag in `--help` output
  must appear in the doc and vice versa.
- **Mirror**: `docs/RUNBOOK.md`'s prose/structure conventions.
- **Validate**: manual side-by-side read of `--help` output vs. the doc. Run
  `/validate-artifact .claude/commands/vm-cleanup.md` and
  `/validate-artifact .claude/scripts/vm-cleanup.sh` — this repo's own portability gate
  (no hardcoded `/home/`, username, or secrets).

### Task 7: Coverage — wire `kcov`, close gaps to 90%
- **Action**: Run `kcov --include-path=. coverage/ bash .claude/tests/scripts/vm-cleanup.test.sh`,
  read the report, add targeted cases for uncovered branches (apt/snap/nvm-absent paths
  are the likely gaps — the existing stubs cover tools being present, not absent). If a
  branch is genuinely untestable, exclude it explicitly in a kcov config and state the
  real reachable percentage rather than gaming the number.
- **Mirror**: none — first coverage tooling in this repo. Document the exact invocation
  in the TDD evidence report (Step 8) so it's reusable for the next bash tool here.
- **Validate**: `kcov` report showing ≥90% line coverage, or an explicit documented gap
  with rationale.

## Validation

```bash
shellcheck .claude/scripts/vm-cleanup.sh                                    # lint gate
bash .claude/tests/run-all.sh                                                # RED/GREEN gate, full suite
kcov --include-path=. coverage/ bash .claude/tests/scripts/vm-cleanup.test.sh  # 90% coverage gate
env -i PATH=/usr/bin:/bin HOME="$TEST_HOME" bash .claude/tests/run-all.sh     # mandatory 2nd isolated pass
bash .claude/scripts/vm-cleanup.sh --help                                    # manual help-output check vs docs
```

Plus the repo's own portability gate on both artifacts. `/validate-artifact` is a Claude
slash command, not a shell binary, so it is invoked in-session rather than from the block
above: `/validate-artifact .claude/scripts/vm-cleanup.sh` and
`/validate-artifact .claude/commands/vm-cleanup.md`.

## Acceptance Criteria

**Safety**
- [x] **AC1** — Only safe-to-delete resources are deleted. Every section-10 guard (self,
  locked, dirty, unreadable status, no upstream, ahead of upstream, protected-files-present)
  and the new section-9 `_tree_is_active` guard have a passing assertion.
- [x] **AC2** — A worktree that fails any guard is left healthy: still in `git worktree
  list`, working tree unchanged, no husk directory.
- [x] **AC3** — Protected files are never deleted at any depth; a rescue that fails
  aborts the removal, worktree left in place.
- [ ] **AC4** — Scan mode (no flags, or `--dry-run`) mutates nothing.

**Correctness**
- [ ] **AC5** — A second identical `--clean --risky` run performs no further destructive
  action and exits 0.
- [ ] **AC6** — A failing action causes non-zero exit and appears in the Summary.
- [ ] **AC7** — `18ceb9d` is fully landed on **this branch**: the guard, the promoted test,
  the runner, and the CI workflow are all present. Reaching `develop` is a post-plan PR
  merge, outside Tasks 1–7 — this AC closes at branch level here, and for real on that merge.

**Usability**
- [ ] **AC8** — `--help` names both tiers (SAFE/RISKY) and at least one example target
  from each.
- [ ] **AC9** — `--risky` replaces `--yes`; bare `--yes` is rejected.

**Quality**
- [ ] **AC10** — ≥90% line coverage via `kcov`, or an explicitly documented, justified gap.
- [ ] **AC11** — `bash .claude/tests/run-all.sh` fully green, including the mandatory
  second isolated-environment pass.
- [ ] **AC12** — `shellcheck .claude/scripts/vm-cleanup.sh` clean (baseline today: 8
  low-severity findings — 2× SC2088, 1× SC2012, 5× SC2059 — 0 error-severity; confirm
  still clean or improved).
- [ ] **AC13** — docs match `--help` output exactly, both directions.
- [ ] **AC14** — `.claude/commands/vm-cleanup.md` exists in-repo and is registered in
  `manifest.yaml`.
- [ ] **AC15** — `/validate-artifact` passes clean on both the script and the command file.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Cherry-pick conflicts despite the zero-drift analysis (branch could move before this runs) | Low | Re-check `git merge-base 18ceb9d worktree-cleanup` immediately before Task 1; if HEAD has moved, re-verify before proceeding |
| kcov+this repo's hand-rolled test style is unproven together (no prior coverage tooling here) | High | Prototype the invocation in Task 7 before treating 90% as a hard blocker |
| 90% unreachable on tool-absent branches | Medium | Existing stubs cover tool-present paths; add tool-absent stubs (`command -v` failing) rather than skip |
| `.claude/commands/vm-cleanup.md` has no in-repo history to diff against — the deployed copy is the only reference and may itself need editing, not just copying | Medium | Treat it as a draft per Task 6, run `/validate-artifact` on it explicitly rather than assuming it's already clean |
| Docs location ambiguous (`RUNBOOK.md` extension vs. new file) | Low | Read `RUNBOOK.md`'s actual shape in Task 6 before deciding; state the choice in the PR |

## Acceptance
- [ ] All tasks complete
- [ ] Validation passes
- [ ] Patterns mirrored, not reinvented
