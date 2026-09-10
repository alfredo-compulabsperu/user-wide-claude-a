# Implementation Plan: worktree-summary v9 (Structurally-Derived Verdict Architecture)

Synthesized from 2 independent `/ecc-plan` runs against the tournament-approved v9
design (6-round design tournament, 2026-09-02: both auditors satisfied, zero
outstanding issues; full mechanism detail lives in that conversation, not repeated
here). This plan is implementation-only — the design is final, not open for
re-derivation.

## Requirements Restatement

Replace the current single-script `~/.claude/skills/worktree-summary/SKILL.md`
(~325-line embedded bash block: wrong-priority base-branch guess, three-dot commit
counting, no fetch, no merge/unique separation, unbounded output, no GitHub
cross-reference, brittle session-data parsing) with the v9 pipeline: a pluggable
multi-file architecture that resolves the base branch from live `origin/HEAD`
truth, separates own-work from sync-merges, cross-references GitHub, and emits a
structurally-derived, veto-gated verdict.

## Pattern Grounding (verified against the actual skill tree, not assumed)

| Convention | Evidence |
|---|---|
| Helper scripts live in a flat `scripts/` dir sibling to `SKILL.md` | `worktree-cleaner/scripts/scan-worktrees.sh`, `git-worktrees-save/scripts/*.sh`, `resume-signal-scan/scripts/gather-signals.sh`, `rules-distill/scripts/*.sh`, `agent-self-evaluation/scripts/evaluate.py` |
| Shared modules nest under `scripts/lib/` | `continuous-learning-v2/scripts/lib/homunculus-dir.sh` |
| No existing skill uses `bin/`, `render/`, or `checks/` subdirectories | Confirmed by directory listing — v9's abstract design (`bin/worktree-summary`, `lib/*.sh`, `checks/*.sh`, `render/*.sh`) is adapted below to this repo's real convention: everything nests under `scripts/`, and `checks/`/`render/` are novel subdirectories with no prior pattern to mirror or conflict with. |

## Target Layout

```
~/.claude/skills/worktree-summary/
  SKILL.md                          (thin wrapper, per repo convention)
  scripts/
    worktree-summary                (entrypoint; was "bin/worktree-summary")
    lib/
      context.sh                    (base resolution, fetch, single diff pass)
      git-safe.sh                   (NUL-safe primitives)
      dirty-tree.sh                 (hardcoded veto pre-step)
      synthesize.sh                 (verdict reducer)
    checks/
      20-commits.sh                 (ahead-count + own-work/sync-merge separation — one file: both operate on the same base..HEAD walk and the same context data, per v9's mechanism description)
      30-files.sh                   (capped, disclosed file-change list — kept as a registry-dispatched check, not hardcoded render data, so it stays consistent with the extensibility goal the tournament fought for: any info category can be reordered/disabled via registry.json)
      40-artifacts.sh               (plan/blueprint/runbook detection — carried forward from v1, only genuinely reusable piece of the original script)
      50-session-data.sh            (jq-only tri-state)
      60-github.sh                  (cached, TTL-bounded cross-reference cascade)
    render/
      text.sh
      json.sh
    registry.json
    _lint.sh                        (registry/script-mismatch check + --nul-safety-check adversarial fixture harness)
    schemas/
      hint.schema.json
```

Numbered check prefixes double as self-documenting dispatch order (matches the
`checks/00-base-branch.sh` style implied by the design's own registry examples).

## Files to Change

| File | Action | Why |
|---|---|---|
| `scripts/schemas/hint.schema.json` | CREATE | Closed enums (`verdict_label` 5-value, `confidence` 3-value), `additionalProperties: false` so a `destructive` key is structurally rejected at the schema layer — the first of two independent enforcement layers (synthesize.sh's own ingestion validation is the second) |
| `scripts/lib/git-safe.sh` | CREATE | `git_status_z()`, `read_nul_records()` — the one NUL-safe primitive every check/veto that touches filenames must use |
| `scripts/lib/context.sh` | CREATE | Live `git ls-remote --symref origin HEAD` every run, regex-validated success criteria (`SYMREF_EMPTY_RESPONSE` vs `SYMREF_NETWORK_FAIL` as distinct outcomes), 4-value `base_method` enum, tool-owned cache under `~/.cache/worktree-summary/<repo-key>/`, fetch-before-base_sha ordering enforced via a parameter-expansion guard (`: "${FETCH_STATUS:?...}"`), single `git diff --name-status`/`--shortstat` pass, two-dot `git rev-list --count base..HEAD` (hardcode two-dot only — never introduce three-dot anywhere in this file, this is the exact bug class that started the tournament) |
| `scripts/lib/dirty-tree.sh` | CREATE | Hardcoded, unconditional, non-registry pre-step; fail-closed veto; NUL-safe filename sample via `git-safe.sh`; never enters the check registry or the tie-break candidate pool by construction |
| `scripts/registry.json` | CREATE | Each check's id, script path, `destructive` boolean (structural source of truth for destructive classification — never hint-declared), `priority` |
| `scripts/checks/20-commits.sh` | CREATE | Two-dot ahead-count; own-work vs. sync-merge separation via ancestor + NUL-safe diff-subsumed check |
| `scripts/checks/30-files.sh` | CREATE | Capped file-change list, shown/total always disclosed |
| `scripts/checks/40-artifacts.sh` | CREATE | Plan/blueprint/runbook detection, capped |
| `scripts/checks/50-session-data.sh` | CREATE | jq-only tri-state against `.git/worktree-summary/session-events.jsonl` — **new log format, not compatible with the current `~/.claude/session-data/*-session.tmp` files v1 reads; see Risks** |
| `scripts/checks/60-github.sh` | CREATE | `gh auth status` gate (degrades to `status=unknown` on failure, never errors the run) → O(1) `git merge-base --is-ancestor <tip> <base>` → `gh pr list --search head:branch` → `gh api commits/{sha}/pulls` → bounded patch-id fallback → `gh issue list --search`; every list capped with shown/total; cache keyed to head SHA with a stated TTL |
| `scripts/lib/synthesize.sh` | CREATE | Hint ingestion validated against `hint.schema.json` (failing hints → `degraded_checks`); `confidence_cap(base_method, degraded_checks)` as a total function over the full enumerated cross-product; `select_winner()` tie-break strictly by `registry.checks[]` array position (never a stored index field); `destructive` derived post-selection from `registry.checks[].destructive`; pre-veto `destructive`/`confidence` computed, dirty-tree veto applied to `final_verdict` afterward, `underlying_signal` preserved |
| `scripts/render/text.sh` | CREATE | Human-readable formatter; every verdict line names `base_method`/freshness; fallback paths visibly flagged |
| `scripts/render/json.sh` | CREATE | `--json` formatter over the same verdict object |
| `scripts/worktree-summary` | CREATE | Entrypoint: `jq` hard-dependency check (exit 3, clear message, on missing), CLI flags (`--json`, `--only=<ids>`, `--list-checks`, `--base=<ref>`, `--no-fetch`, `--gh-cache-ttl=<seconds>`), orchestrates `_lint.sh` → `context.sh` → dirty-tree veto + base-resolution pre-steps (never registry-dispatched) → registry-dispatched checks → `synthesize.sh` → renderer |
| `scripts/_lint.sh` | CREATE | Default mode: registry/script-diff hardcoded blocking pre-step (`comm -3` on `registry.json` vs `checks/*.sh` on disk, exit non-zero on mismatch — no check can be silently inert). `--nul-safety-check` mode: adversarial scratch-worktree fixture test (`git worktree add --detach` under a `mktemp -d` parent, hostile filenames incl. spaces/globs/embedded newlines/unicode, outer trap on the parent tmpdir bound before the per-check loop covering `EXIT INT TERM HUP`, inner per-check trap as best-effort optimization only — both scoped precisely per v9's final wording: directory-removal guarantee only, not git worktree metadata deregistration, not SIGKILL-proofing) |
| `SKILL.md` | UPDATE (last step) | Replace the embedded ~325-line bash block with a thin wrapper: `bash "$HOME/.claude/skills/worktree-summary/scripts/worktree-summary" "$@"`. Update Features/Output docs to describe the verdict line, `--json`, and new flags |

## Tasks

### Task 1 — Foundation (no dependencies on other new files)
Create `scripts/schemas/hint.schema.json` and `scripts/lib/git-safe.sh`.
**Validate:** `jq empty scripts/schemas/hint.schema.json` (valid JSON); `bash -n scripts/lib/git-safe.sh` (syntax); source it and call `git_status_z` against a scratch repo with a space-containing filename and one with an embedded newline — confirm no word-splitting.

### Task 2 — Data layer (depends on Task 1)
Create `scripts/lib/context.sh` and `scripts/lib/dirty-tree.sh`.
**Validate:** Run `context.sh` standalone against a known-clean worktree (any current worktree diffed against `origin/develop`) and confirm `base_method=ORIGIN_HEAD_LIVE`; run with a decoy stale local `main` branch present and confirm resolution still prefers `origin/develop`, never the decoy (this is the exact regression test for the bug that started the tournament). Run `dirty-tree.sh` against a worktree with an uncommitted file and confirm veto fires; force `git status` to error and confirm it still reports dirty (fail-closed, never clean).

### Task 3 — Registry + checks (depends on Task 1, Task 2)
Create `scripts/registry.json` and all 5 `scripts/checks/*.sh` files.
**Validate:** Run `scripts/_lint.sh` (from Task 5 — may need to stub it early or run this validation after Task 5) to confirm every check file has a matching registry entry and vice versa. Manually invoke each check against 2-3 fixture worktrees; confirm `60-github.sh` correctly reports known merged/tracked state (validated command shapes: `gh pr list --search`, `gh pr view --json closingIssuesReferences`, `gh issue list --search`, all confirmed working manually earlier in the design-tournament session).

### Task 4 — Verdict synthesis (depends on Task 1, Task 3)
Create `scripts/lib/synthesize.sh`, following the v9 pseudocode's exact sequencing (ingest → filter → cap → select → pre-veto verdict → veto → final) — this ordering is what closed the tournament's last two audit findings; do not simplify it.
**Validate:** Feed a synthetic hint set with two same-priority hints from checks at registry positions 0 and 2 — confirm position 0 wins deterministically. Feed a hint with an injected `destructive` key — confirm it's rejected at ingestion, not merged.

### Task 5 — Registry integrity, lint, entrypoint (depends on Task 1, Task 4)
Create `scripts/_lint.sh` and `scripts/worktree-summary`.
**Validate:** `scripts/_lint.sh` exits 0 clean; intentionally add a check file with no registry entry and confirm it blocks. `scripts/_lint.sh --nul-safety-check` exits 0 and leaves zero orphaned worktrees (`git worktree list` before/after). Interrupt a run mid-check (normal signal, not SIGKILL) and confirm the outer trap still cleans the parent tmpdir.

### Task 6 — Renderers, real-worktree verification, cutover (depends on Task 5)
Create `scripts/render/text.sh` and `scripts/render/json.sh`. Run the complete pipeline against 3 real fixture scenarios: (1) a clean, fully-merged worktree, (2) a deliberately dirty one (confirm `BLOCKED_DIRTY_TREE` suppresses any destructive-shaped verdict), (3) a worktree with a decoy stale local `main` branch (confirm base resolution still prefers `origin/develop`). Only after all three pass, update `SKILL.md` to the thin wrapper.
**Validate:** Full end-to-end run against all 3 fixtures, output compared against manually-derived ground truth from the design-tournament session. `SKILL.md`'s wrapper produces identical output to direct script invocation.

## Validation (consolidated)

```bash
# Per-file syntax
bash -n scripts/lib/*.sh scripts/checks/*.sh scripts/render/*.sh scripts/worktree-summary scripts/_lint.sh
jq empty scripts/schemas/hint.schema.json scripts/registry.json

# Registry integrity (must exit 0)
scripts/_lint.sh

# NUL-safety adversarial fixture (must exit 0, zero orphaned worktrees)
scripts/_lint.sh --nul-safety-check
git worktree list   # confirm no leftovers after

# End-to-end
scripts/worktree-summary --base=develop
scripts/worktree-summary --json | jq .    # confirm valid JSON, verdict object present
```

## No-Breakage / Cutover Strategy

Build Tasks 1-6's new files entirely under `scripts/` without touching `SKILL.md` —
the current single-script skill keeps working unmodified throughout. Only the
final `SKILL.md` edit (thin-wrapper swap) is the cutover moment, gated behind all
Task 6 verification passing, and trivially revertible (`git revert` one commit)
since everything else is additive new files. The old embedded script body is not
destructively deleted from history — `git log SKILL.md` remains the record.

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `gh` unauthenticated/unavailable in some environments | Medium | `60-github.sh` must degrade to `status=unknown` + confidence-cap-to-LOW, never error the whole run — implement exactly, not as a shortcut |
| Session-log format change (`.git/worktree-summary/session-events.jsonl`) breaks whatever currently reads the old `~/.claude/session-data/*-session.tmp` format | Medium | Confirm nothing else consumes the old format before dropping it; consider a compat shim or an explicit deprecation note if something does |
| `_lint.sh --nul-safety-check`'s scratch-worktree creation is disk/time-costly | Low-Medium | Keep it a separate, explicit `--nul-safety-check` flag — never wire it into the default `worktree-summary` invocation path |
| Cutover leaves `SKILL.md` broken if a bug slips past Task 6 verification | Medium | Task 6 gates the `SKILL.md` edit behind all 3 fixture scenarios passing; old script recoverable via git history regardless |
| Abstract design naming (`bin/`/`lib/`/`render/`) vs. this repo's real `scripts/`-only convention | Low (resolved above) | This plan already reconciles every path to `scripts/`-relative; no ambiguity carried forward |

## Acceptance

- [ ] All 6 tasks complete, each validated per its own Validate step
- [ ] `scripts/_lint.sh` and `scripts/_lint.sh --nul-safety-check` both exit 0, zero orphaned worktrees
- [ ] End-to-end run against 3 fixture scenarios (clean/merged, dirty, stale-base-decoy) produces correct verdicts
- [ ] `SKILL.md` updated only after verification passes; old script recoverable via git history

**Estimated complexity: Large** (14 new files across 6 phases, ~6-8 hours implementation + verification, vs. the original ~300-line single file). No unit-test framework exists in this skill family (only `continuous-learning-v2/scripts/test_parse_instinct.py`, unrelated stack) — verification is direct execution against real/fixture worktrees, not a test suite.
