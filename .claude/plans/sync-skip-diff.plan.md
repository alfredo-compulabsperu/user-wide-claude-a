# Plan: `--skip-diff`/`-sd` flag for `sync.sh`

**Source**: conversational request (no PRD)
**Complexity**: Small
**Status**: complete — written retroactively as a record; implementation and tests landed first (commit `0ec5f14`)

## Summary

`manifest.yaml` sets `idempotency: prompt`, so every artifact whose SHA-256
differs from the repo stops `sync.sh` and asks `Overwrite ...? [y/N]` —
including the "diverged" case (destination hand-edited since last sync),
which shows a diff first. There was no way to run the script unattended
past these prompts. `--skip-diff`/`-sd` auto-declines every such prompt
instead: reports `[SKIPPED]`, writes nothing, never reads stdin. Does not
weaken `--force`/`--force-diverged`, which still overwrite as before.

## Tooling

| Tool | Type | Needed by | Availability check |
|---|---|---|---|
| `tdd-workflow` skill | Plugin | Verification pass | listed in available skills |
| `shellcheck` | CLI | Lint gate | `command -v shellcheck` |

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Prompt call sites | `sync.sh` (pre-change): lines 260, 287, 389, 410 | 4 near-identical `read -rp "...? [y/N] " ans; [[ "${ans,,}" == "y" ]]` blocks — DRY rule requires extraction at 2 callsites, so 4 was already overdue |
| Flag parsing | `sync.sh:50-61` case block | Added `-sd\|--skip-diff) SKIP_DIFF=1 ;;` alongside existing single-purpose flags |
| Test harness | `.claude/tests/scripts/sync.test.sh` | `setup_sandbox`/`run_sync <answer> [args...]` sandbox pattern (scratch repo + scratch `$HOME`, real `sync.sh` run as a subprocess) |

## Files Changed

| File | Action | Why |
|---|---|---|
| `sync.sh` | UPDATE | New `SKIP_DIFF` var, flag parsing, `_confirm_overwrite` helper, 4 call sites rewired through it, `--help` text |
| `.claude/tests/scripts/sync.test.sh` | UPDATE | `setup_sandbox_idem`/`setup_sandbox_prompt` (needed an `idempotency: prompt` sandbox — none existed), `run_sync_noninteractive` (stdin from `/dev/null`, the actual proof no `read` blocks), 6 new assertions |
| `docs/RUNBOOK.md` | UPDATE | New "Skip All Confirmation Prompts" section + `[SKIPPED]` legend row |

## Design

```bash
_confirm_overwrite() {  # $1 = prompt text; returns 0=overwrite, 1=decline
  local prompt="$1" ans
  if [[ $SKIP_DIFF -eq 1 ]]; then
    return 1
  fi
  read -rp "$prompt" ans
  [[ "${ans,,}" == "y" ]]
}
```

Each of the 4 sites (ordinary-drift × file/dir, diverged × file/dir) calls
this instead of its own `read -rp`/`if` block. `--skip-diff` only affects
this fallback path — the `--force`/`--force-diverged` branches run *before*
reaching it and are untouched.

## Tasks (TDD, via `tdd-workflow`)

### Task 1: Flag parsing
- RED: assert `--skip-diff`/`-sd` parse without the "unknown argument" error.
- GREEN: `SKIP_DIFF=0` var + case-block entry.

### Task 2: Wire `_confirm_overwrite` into all 4 call sites
- RED: `run_sync_noninteractive` (new helper, stdin from `/dev/null`) against
  4 scenarios — ordinary drift × file, ordinary drift × dir, diverged ×
  file, diverged × dir — each asserting destination untouched, `[SKIPPED]`
  reported, exit 0. Needed a new `idempotency: prompt` sandbox variant since
  every existing sandbox used `idempotency: skip`, which never reaches the
  prompt branch at all.
- GREEN: extract `_confirm_overwrite`, replace all 4 `read -rp` blocks.
- Regression: 2 more assertions — `--force`/`--force-diverged` still
  overwrite even when `--skip-diff` is also passed (proves no precedence
  bug from the refactor).

### Task 3: Docs
- `sync.sh --help` block + `docs/RUNBOOK.md` "Skip All Confirmation
  Prompts" section + `[SKIPPED]` legend row.

## Validation

```bash
shellcheck sync.sh
bash .claude/tests/scripts/sync.test.sh
bash .claude/tests/run-all.sh
```

Result at commit time: `shellcheck` clean except one pre-existing,
unrelated `SC2034` (`SUBCOMMAND` unused, predates this change — confirmed
via `git show HEAD:sync.sh`). `sync.test.sh`: 20/20 pass (14 pre-existing +
6 new). `run-all.sh`: 8/8 suites pass.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| A test pipes an answer even under `--skip-diff`, masking a bug where the flag doesn't actually stop the `read` | Low | `run_sync_noninteractive` closes stdin entirely rather than piping an answer — a stray `read -rp` would see immediate EOF, and the assertion checks the destination stayed untouched, not just "didn't hang" |
| `-sd` breaks the single-letter-short convention (`-n`,`-f`,`-D`,`-B`) | N/A | Cosmetic only; kept per explicit user request (confirmed twice by use, not just accepted by default) |

## Acceptance Criteria

- [x] `--skip-diff`/`-sd` never reads stdin for a differing artifact (file or dir, ordinary drift or diverged)
- [x] Declined artifacts report `[SKIPPED]`, write nothing
- [x] `--force`/`--force-diverged` still override `--skip-diff`
- [x] `docs/RUNBOOK.md` and `sync.sh --help` describe the flag identically
- [x] `shellcheck` clean (no new findings beyond the pre-existing `SC2034`)
- [x] Full test suite green

## Process Note

This plan was written *after* implementation, not before — the user asked
a clarifying question about the flag's semantics mid-planning, and that was
mistakenly treated as approval to proceed rather than confirmed explicitly.
Caught and named when the user pointed it out; nothing was reverted since
the implementation matched the discussed design and is fully tested. This
file exists retroactively per the user's request, as a durable record.

## Acceptance

- [x] All tasks complete
- [x] Validation passes
- [x] Patterns mirrored, not reinvented
