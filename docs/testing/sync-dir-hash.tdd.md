# TDD Evidence — sync.sh directory hash is path-sensitive

> **Última actualización:** 2026-09-15

## Source plan

No `*.plan.md`. The bug was found incidentally while promoting the `audit-plan`
skill: a freshly installed, byte-identical skill directory reported `[DIVERGED]`,
then `[STALE]`, but never `[OK]`. Journeys below were written during this TDD run.

## User journeys

1. As a maintainer running `sync.sh --dry-run`, I want a skill directory whose repo
   content is byte-identical to the installed `~/.claude/` copy to report `[OK]`, so
   I can distinguish real drift from noise.
2. As a maintainer, I want a directory whose content genuinely differs to still be
   reported as changed, so the fix does not make sync blind to real drift.
3. As a maintainer, I want a file renamed within the directory (same bytes, different
   relative path) to count as changed, so layout stays part of the hash.

## Task report

### Reproduce the defect (RED)

`dir_sha256()` (`sync.sh:184`) computed `find "$1" -type f | xargs sha256sum` and hashed
that output. `sha256sum` prints `<hash>  <path>`, so the **absolute path of every file**
was folded into the directory hash. An artifact's repo copy and its `~/.claude` copy
always live at different absolute paths, so `src_hash` could never equal `dest_hash`
for a directory — no directory artifact could ever report `[OK]`, regardless of content.

Five cases were added to the existing `sync.sh` suite as tests 15-19. Validation command:

```
bash .claude/tests/scripts/sync.test.sh
```

Against the pre-fix `sync.sh`:

```
FAIL: identical directory reports [OK] despite differing absolute paths
FAIL: nested files hashed by relative path
Results: 17 passed, 2 failed
```

Both failures are the intended defect. The three other new cases pass even while the
bug is present and exist as guards — they must keep passing after the fix. The
empty-directory case passes when broken because that branch returns the literal
`empty-dir`, which contains no path.

### Apply the minimal fix (GREEN)

`cd` into the directory before `find`, so `sha256sum` emits paths relative to the
directory root. Content and layout still determine the hash; location no longer does.
`file_sha256()` needed no change — it cuts the hash out of `sha256sum`'s output and
never saw the path.

```
bash .claude/tests/scripts/sync.test.sh
Results: 19 passed, 0 failed

bash .claude/tests/run-all.sh
  suites run:    8
  suites passed: 8
  suites failed: 0
```

Lint: `shellcheck sync.sh` reports one pre-existing `SC2034` (`SUBCOMMAND` unused,
`sync.sh:57`), untouched by this change and deliberately left alone.

### Real-world confirmation

`bash sync.sh --dry-run` against the actual repo, after the fix:

```
  [OK]       skills/catalog/
  [STALE]    skills/execute-plan/
  [OK]       skills/copy-plugin-tool/
  [OK]       skills/gh-pr-update/
  [OK]       skills/audit-plan/
```

Four directories that were permanently `[STALE]` now read `[OK]`. `execute-plan` stays
`[STALE]` and `diff -rq` confirms its `SKILL.md` genuinely differs — the fix did not
blanket-approve everything.

### Correction made during this run

The five cases were first written as a new Bats suite at `tests/sync-dir-hash.bats`.
That was wrong for this repo: CI (`.github/workflows/tests.yml`) runs
`bash .claude/tests/run-all.sh`, which executes only `.claude/tests/scripts/*.test.sh`,
and a `sync.test.sh` suite already existed. The Bats file would never have run in CI
and duplicated an existing harness. The cases were ported into `sync.test.sh` using its
own `setup_sandbox` / `run_sync` / `run_test` helpers, and the Bats file was deleted.
RED was then re-verified in the real harness by restoring the pre-fix `sync.sh` via
`git show`, as recorded above.

## Test specification

| # | What is guaranteed | Test file or command | Test type | Result | Evidence |
|---|--------------------|----------------------|-----------|--------|----------|
| 15 | A byte-identical directory reports `[OK]` regardless of where each copy lives | `.claude/tests/scripts/sync.test.sh:identical directory reports [OK] despite differing absolute paths` | integration | PASS | `bash .claude/tests/scripts/sync.test.sh` |
| 16 | A directory with genuinely different content is still reported as changed | `.claude/tests/scripts/sync.test.sh:directory with different content is still reported as changed` | integration | PASS | `bash .claude/tests/scripts/sync.test.sh` |
| 17 | Identical bytes under a different filename count as changed (layout is hashed) | `.claude/tests/scripts/sync.test.sh:same bytes under a different filename counts as changed` | integration | PASS | `bash .claude/tests/scripts/sync.test.sh` |
| 18 | Two empty directories compare equal via the `empty-dir` branch | `.claude/tests/scripts/sync.test.sh:two empty directories compare equal` | integration | PASS | `bash .claude/tests/scripts/sync.test.sh` |
| 19 | Nested files are hashed by relative path, so subdirectories compare correctly | `.claude/tests/scripts/sync.test.sh:nested files hashed by relative path` | integration | PASS | `bash .claude/tests/scripts/sync.test.sh` |

Tests drive `sync.sh --dry-run` end to end inside a scratch repo and a sandbox `HOME`
under `mktemp -d`, per the suite's existing convention. The real `~/.claude/` and the
real `.sync-state.json` are never touched.

## Coverage and known gaps

No coverage percentage is claimed. `kcov` is installed, but both `--include-path=sync.sh`
and `--include-pattern=sync.sh` report `0.00%`: every suite here executes a *copy* of
`sync.sh` in a temp sandbox via a nested `bash` subprocess, which kcov does not trace.
That figure is an instrumentation artifact, not a measurement. Qualitative checklist for
the changed function:

| `dir_sha256()` branch | Covered by |
|---|---|
| Non-empty dir, identical content and layout | Tests 15, 19 |
| Non-empty dir, differing content | Test 16 |
| Non-empty dir, differing layout (rename) | Test 17 |
| Empty dir (`empty-dir` literal) | Test 18 |
| `find`/`xargs` failure -> `return 1` | **Not covered** |

Known gaps, all pre-existing and out of scope for this fix:

- The `return 1` failure path in `dir_sha256()` is untested; it needs an unreadable
  directory, which is awkward to stage root-independently.
- Filenames containing spaces or newlines are handled by `-print0`/`sort -z`/`xargs -0`
  but have no dedicated test.
- Directory baselines recorded in `~/.claude/.sync-state.json` before this fix hold
  absolute-path-derived hashes. They are harmless — the `[OK]` branch returns before the
  divergence check and rewrites the baseline on the next real sync — but they are stale
  until then.

## Merge evidence

If these checkpoints are squashed, preserve:

- **RED** — `bash .claude/tests/scripts/sync.test.sh` against pre-fix `sync.sh`:
  17 passed, 2 failed; byte-identical directories never report `[OK]`.
- **GREEN** — same command: 19 passed, 0 failed. Full CI entrypoint
  `bash .claude/tests/run-all.sh`: 8 suites, 8 passed.
- **Refactor** — none needed; the fix is one line plus an explanatory comment.

## Historial de versiones

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-09-15 | Creación inicial — RED/GREEN evidence for the dir_sha256 path-sensitivity fix |
| 1.1 | 2026-09-15 | Ported cases from a standalone Bats suite into `.claude/tests/scripts/sync.test.sh` (the suite CI actually runs); re-verified RED/GREEN in that harness |
