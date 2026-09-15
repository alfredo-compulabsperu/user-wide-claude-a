# TDD Evidence: `sync.sh --skip-diff`/`-sd`

**Source plan**: `.claude/plans/sync-skip-diff.plan.md`
**Mode**: Retroactive verification pass — implementation (commit `0ec5f14`) predated this report; RED/GREEN were reproduced live during this pass, not just re-asserted from memory. See "Process Note" in the plan for why the order was backwards.

## User Journey

As the person running `bash sync.sh` against a `manifest.yaml` with
`idempotency: prompt`, I want a flag that skips every "differing artifact,
overwrite? [y/N]" prompt (both ordinary drift and out-of-band divergence),
so the script can run unattended without silently overwriting anything —
it should decline and report, never hang waiting for input.

## RED — reproduced live, not claimed

Temporarily replaced `sync.sh` with its pre-implementation content (`git
show feebb9c:sync.sh`, the commit immediately before `0ec5f14`), then ran
the *current* `sync.test.sh` against it:

```
$ bash .claude/tests/scripts/sync.test.sh
...
FAIL: ordinary drift + idempotency=prompt: --skip-diff skips without reading stdin
ERROR: unknown argument: --skip-diff
FAIL: ordinary drift + idempotency=prompt (dir): --skip-diff skips without reading stdin
ERROR: unknown argument: --skip-diff
FAIL: diverged file: --skip-diff skips without reading stdin
ERROR: unknown argument: --skip-diff
FAIL: diverged dir: --skip-diff skips without reading stdin
ERROR: unknown argument: --skip-diff
FAIL: --force overwrites even when --skip-diff is also passed
ERROR: unknown argument: --skip-diff
FAIL: --force-diverged overwrites even when --skip-diff is also passed

Results: 14 passed, 6 failed
```

Exactly the 6 new assertions fail, for the intended reason (unrecognized
flag — not a syntax error or unrelated regression), and all 14
pre-existing assertions still pass. Valid runtime RED.

Then restored the committed implementation (`git checkout -- sync.sh`,
confirmed via `bash -n sync.sh`).

## GREEN — reproduced live

```
$ bash .claude/tests/scripts/sync.test.sh
...
Results: 20 passed, 0 failed
```

All 20 (14 pre-existing + 6 new) pass against the restored implementation.

## Full suite + lint

```
$ shellcheck sync.sh
sync.sh:62: SC2034 (warning): SUBCOMMAND appears unused ...
```
Pre-existing, unrelated — confirmed present at `feebb9c` (the commit
before this change) via `git show feebb9c:sync.sh | grep -n SUBCOMMAND`.
No new shellcheck findings from this diff.

```
$ bash .claude/tests/run-all.sh
...
suites run:    8
suites passed: 8
suites failed: 0
```

## Mandatory 2nd isolated-environment pass

```
$ env -i PATH=/usr/bin:/bin bash .claude/tests/scripts/sync.test.sh
...
Results: 20 passed, 0 failed
```

No ambient-state leak (no ELF-inherited `$HOME`, aliases, or extra `PATH`
entries required) — the suite's own `HOME="$SANDBOX_HOME"` per-invocation
scoping holds up with nothing else inherited from the outer shell.

## Test Specification

| # | What is guaranteed | Test | Type | Result |
|---|---|---|---|---|
| 1 | `--skip-diff`/`-sd` parses without the "unknown argument" error | (implicit in tests 15-20 all reaching the flag-dependent branches) | integration | PASS |
| 2 | Ordinary-drift file, `idempotency: prompt`, `--skip-diff`, no stdin → destination untouched, `[SKIPPED]`, exit 0 | `sync.test.sh:"ordinary drift + idempotency=prompt: --skip-diff skips without reading stdin"` | integration | PASS |
| 3 | Same, for a directory (skill) install | `sync.test.sh:"ordinary drift + idempotency=prompt (dir): ..."` | integration | PASS |
| 4 | Diverged file (hand-edited since last sync), `--skip-diff`, no stdin → untouched, `[SKIPPED]`, exit 0 | `sync.test.sh:"diverged file: --skip-diff skips without reading stdin"` | integration | PASS |
| 5 | Same, for a diverged directory | `sync.test.sh:"diverged dir: --skip-diff skips without reading stdin"` | integration | PASS |
| 6 | `--force` still overwrites ordinary drift even when `--skip-diff` is also passed (no precedence bug from the refactor) | `sync.test.sh:"--force overwrites even when --skip-diff is also passed"` | integration | PASS |
| 7 | `--force-diverged` still overwrites diverged content even when `--skip-diff` is also passed | `sync.test.sh:"--force-diverged overwrites even when --skip-diff is also passed"` | integration | PASS |
| 8-21 | Pre-existing behavior (baseline recording, branch guard, plain `--force`/`--force-diverged` semantics, dry-run) unaffected by the refactor | remaining 14 assertions in `sync.test.sh` | integration | PASS (all) |

## Coverage — qualitative (no line-coverage tool for this bash script; `kcov` not exercised in this pass)

Every branch `_confirm_overwrite` introduces or touches has at least one
assertion: ordinary-drift × {file, dir} × {skip-diff declines, force
overrides}, diverged × {file, dir} × {skip-diff declines, force-diverged
overrides}. That's 100% of the new function's decision branches (2
outcomes × 4 call sites, all exercised).

**Known gaps — pre-existing, not introduced or modified by this task**
(flagged per the plan-handoff instruction to record scope concerns rather
than silently widen them):
- No test asserts `sync.sh --help` output content for *any* flag (not
  just `--skip-diff`) — verified manually this pass (`bash sync.sh --help`
  output matches `docs/RUNBOOK.md` and the in-script usage text), not
  automated.
- `idempotency: skip` and `idempotency: overwrite` paths for *ordinary*
  drift (not diverged) have no dedicated assertion — existing tests reach
  them only via `--force`, which short-circuits before the idempotency
  check.
- `install_plugin`, `scan_local_only`, and the `claude_md: portable: true`
  path have zero test coverage in this file (manifest fixtures always use
  `plugins: []`, `portable: false`).
- Preflight failure paths (missing `manifest.yaml`, missing `python3`,
  missing `$CLAUDE_DIR`, missing `sync-state.sh`) are untested.

None of these are touched by the `--skip-diff` change; recorded here so
they don't get silently assumed "already covered" by this report.

## Git Checkpoints

Not applicable in the RED→GREEN→refactor commit-per-stage sense — this was
a retroactive verification pass on already-committed work (single commit
`0ec5f14`), not a staged new-development cycle. The live RED/GREEN
reproduction above stands in as the checkpoint evidence for this task, per
the "verification pass on completed work" framing given for this run.

## Merge Evidence

Not applicable — no squash pending; `0ec5f14` is already a single commit
on `worktree-clean`, unpushed.
