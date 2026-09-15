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

Validation command: `bats tests/`

```
1..5
not ok 1 byte-identical skill directory reports [OK]
#   `[[ "$output" == *"[OK]"*"skills/demo"* ]]' failed
ok 2 differing skill directory is still reported as changed
ok 3 same bytes under a different filename counts as changed
ok 4 two empty skill directories report [OK]
not ok 5 nested files are hashed by their relative path
```

Tests 1 and 5 fail for the intended reason. Test 4 passes even when broken because the
empty-directory branch returns the literal `empty-dir`, which contains no path. Tests 2
and 3 are guards: they must keep passing after the fix.

Checkpoint: `1a6589b test: add reproducer for path-sensitive dir_sha256 in sync.sh`

### Apply the minimal fix (GREEN)

`cd` into the directory before `find`, so `sha256sum` emits paths relative to the
directory root. Content and layout still determine the hash; location no longer does.
`file_sha256()` needed no change — it cuts the hash out of `sha256sum`'s output and
never saw the path.

Validation command: `bats tests/`

```
1..5
ok 1 byte-identical skill directory reports [OK]
ok 2 differing skill directory is still reported as changed
ok 3 same bytes under a different filename counts as changed
ok 4 two empty skill directories report [OK]
ok 5 nested files are hashed by their relative path
```

Isolated 2nd pass, `env -i PATH=/usr/bin:/bin bats tests/` — all 5 pass with no ambient
`HOME` and a minimal `PATH`, so nothing depends on leaked shell state.

Lint: `shellcheck sync.sh` reports one pre-existing `SC2034` (`SUBCOMMAND` unused,
`sync.sh:57`), untouched by this change and deliberately left alone.

Checkpoint: `c0bce1e fix: hash directory contents by relative path in sync.sh`

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

## Test specification

| # | What is guaranteed | Test file or command | Test type | Result | Evidence |
|---|--------------------|----------------------|-----------|--------|----------|
| 1 | A byte-identical skill directory reports `[OK]` regardless of where each copy lives | `tests/sync-dir-hash.bats:byte-identical skill directory reports [OK]` | integration | PASS | `bats tests/` |
| 2 | A skill directory with genuinely different content is still reported as changed | `tests/sync-dir-hash.bats:differing skill directory is still reported as changed` | integration | PASS | `bats tests/` |
| 3 | Identical bytes under a different filename count as changed (layout is hashed) | `tests/sync-dir-hash.bats:same bytes under a different filename counts as changed` | integration | PASS | `bats tests/` |
| 4 | Two empty directories compare equal via the `empty-dir` branch | `tests/sync-dir-hash.bats:two empty skill directories report [OK]` | integration | PASS | `bats tests/` |
| 5 | Nested files are hashed by relative path, so subdirectories compare correctly | `tests/sync-dir-hash.bats:nested files are hashed by their relative path` | integration | PASS | `bats tests/` |

Tests drive `sync.sh --dry-run` end to end inside a sandbox repo and a sandbox `HOME`
under `$BATS_TEST_TMPDIR`. The real `~/.claude/` and the real `.sync-state.json` are
never touched.

## Coverage and known gaps

`kcov` is installed, but both `--include-path=sync.sh` and `--include-pattern=sync.sh`
report `0.00%`: the suite executes a *copy* of `sync.sh` in a temp sandbox via
`env bash …/sync.sh`, and kcov does not trace that nested subprocess under Bats. That
figure is an instrumentation artifact, not a measurement, so no coverage percentage is
claimed here. Qualitative checklist per the TDD skill's Bash-coverage guidance:

| `dir_sha256()` branch | Covered by |
|---|---|
| Non-empty dir, identical content and layout | Tests 1, 5 |
| Non-empty dir, differing content | Test 2 |
| Non-empty dir, differing layout (rename) | Test 3 |
| Empty dir (`empty-dir` literal) | Test 4 |
| `find`/`xargs` failure -> `return 1` | **Not covered** |

Known gaps, all pre-existing and out of scope for this fix:

- The `return 1` failure path in `dir_sha256()` is untested; it needs an unreadable
  directory, which is awkward to stage as root-independent.
- Only `--dry-run` is exercised. `install_dir()`'s write paths — `[INSTALLED]`,
  the `[DIVERGED]` prompt, `--force` / `--force-diverged` — have no tests.
- Filenames containing spaces or newlines are handled by `-print0`/`sort -z`/`xargs -0`
  but have no dedicated test.

## Merge evidence

If these checkpoints are squashed, preserve:

- **RED** — `bats tests/`: tests 1 and 5 fail; byte-identical skill dirs never report `[OK]`.
- **GREEN** — `bats tests/`: 5/5 pass, plus a scrubbed `env -i PATH=/usr/bin:/bin bats tests/` pass.
- **Refactor** — none needed; the fix is one line plus an explanatory comment.

## Historial de versiones

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | 2026-09-15 | Creación inicial — RED/GREEN evidence for the dir_sha256 path-sensitivity fix |
