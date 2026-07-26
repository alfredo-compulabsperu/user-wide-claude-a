# Plan: Three-Way Divergence Detection for `sync.sh` & `promote-artifact`

**Source PRD**: N/A — ad hoc feature request (not tied to a PRD milestone)
**Complexity**: Small–Medium

## Summary

`sync.sh` and `promote-artifact` currently do a plain SHA-256 compare between source and destination: any difference is either force-overwritten or met with a bare y/N prompt, with no way to tell "repo moved on, destination untouched since last sync" (safe) apart from "destination was hand-edited out-of-band" (must not silently clobber). This adds a per-machine state file (`~/.claude/.sync-state.json`) recording the last-synced SHA-256 per artifact, via a new shared helper `.claude/scripts/sync-state.sh`, and threads a three-way check through both consumers so out-of-band edits are flagged (`[DIVERGED]`) and immune to plain `--force`, requiring an explicit `--force-diverged` or interactive confirm instead.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Naming | `sync.sh:63-108` | kebab-case script files, `snake_case` bash functions (`yaml_get_names`, `file_sha256`) |
| Error handling | `sync.sh:47-49,158-162` | Hard preflight checks via `[[ ]] \|\| { echo "ERROR: ..." >&2; exit 1; }`; soft failures use `WARN:` to stderr + counter increment, never a hard exit |
| Logging | `sync.sh:170,178-204` | Two-space-indented bracketed tags (`[OK]`, `[UPDATED]`, `[INSTALLED]`, `[SKIP]`, `[STALE]`) |
| Data access | `sync.sh:64-72,102-108` | python3 heredoc with single-quoted `<<'PYEOF'` + env-var passing (avoids shell injection — see "C1"/"C2" comments at `sync.sh:51,142`) |
| Tests | `.claude/tests/scripts/rename-tmux-window.test.sh` | `run_test(name, pass\|fail)` counter helper, `bash -n` syntax check as test 1, mock binaries in `mktemp -d` prepended to `PATH`, summary + `exit 1` on any failure |

No existing pattern for a JSON (vs. YAML) state file in this repo — using stdlib `json` directly since the schema is a flat map; not worth pulling in YAML semantics for this.

## Files to Change

| File | Action | Why |
|---|---|---|
| `.claude/scripts/sync-state.sh` | CREATE | Shared `get`/`set` helper against `~/.claude/.sync-state.json`, used by both call sites (DRY) |
| `sync.sh` | UPDATE | Wrap helper, add `--force-diverged`/`CNT_DIVERGED`, three-way branch in `install_file`/`install_dir` |
| `.claude/skills/promote-artifact/SKILL.md` | UPDATE | Add `--force-diverged` to args/invocation; rewrite Step 4 with the same three-way logic for both destinations |
| `.claude/tests/scripts/sync-state.test.sh` | CREATE | get/set round-trip, missing-key/missing-file behavior |
| `.claude/tests/scripts/sync.test.sh` | CREATE | Three-way branches: no-baseline drift, baseline==dest drift, diverged (+`--force` doesn't bypass, `--force-diverged` does, decline preserves file) |
| `CLAUDE.md` (repo root) | UPDATE | Extend repo-internal-tooling sentence to name `sync-state.sh`; add Gotchas row for `~/.claude/.sync-state.json` |
| `manifest.yaml` | **no change** | `sync-state.sh` is repo-internal like `promote-artifact`/`validate-artifact` — deliberately excluded from sync |

## Tasks

### Task 1: `sync-state.sh`

- **Action**: `get <key>` prints the stored SHA-256 for `<key>` from `~/.claude/.sync-state.json`, or empty string if absent/file missing. `set <key> <sha256>` atomically updates that JSON map (tempfile + `os.replace`). No `unset` — a stale key is harmless dead data (YAGNI).
- **Mirror**: python3 heredoc + env-var pattern from `sync.sh:64-72`.
- **Validate**: `bash -n .claude/scripts/sync-state.sh`; manual round-trip (`set foo abc123` then `get foo` → `abc123`; `get bar` on empty state → empty string).

### Task 2: `sync.sh` integration

- **Action**: wrap the helper as `sync_state_get()`/`sync_state_set()` shell functions; add `-D|--force-diverged` flag plus `FORCE_DIVERGED`/`CNT_DIVERGED` globals. In `install_file` and `install_dir`, after the existing SHA-match check (now also self-healing the baseline via `sync_state_set` on every match — this is what lets the state file bootstrap itself on first run without manual seeding), insert a baseline-read branch before the existing stale/drift handling:
  - No baseline, or baseline equals the destination's current hash → ordinary drift, today's exact behavior (`--force`/`idempotency: overwrite` overwrites, `idempotency: skip` skips, otherwise prompts), then update baseline on any overwrite.
  - Baseline recorded and differs from the destination's current hash → `[DIVERGED]`. Show `diff -u <dest> <src>` (files) or `diff -rq <dest> <src>` (dirs). Plain `--force`/`idempotency: overwrite` do **not** apply here — only `--force-diverged` bypasses the prompt, or an explicit interactive `y`. Declining reports `[SKIPPED] <label> (out-of-band edit preserved)` and suggests promoting that path into the repo instead.
  - Dry-run reports `[DIVERGED]` without prompting or writing, matching how `[STALE]`/`[MISSING]` behave today.
  - Document the accepted limitation in a code comment: on first run after rollout, artifacts with no baseline fall into ordinary-drift (not falsely flagged diverged) — protection applies going forward only.
- **Mirror**: existing `install_file`/`install_dir` control flow; `_overwrite_dir`'s atomic-swap reused as-is for the diverged+directory case.
- **Validate**: `bash -n sync.sh`; `sync.test.sh` (Task 4).

### Task 3: `promote-artifact/SKILL.md`

- **Action**: add `--force-diverged` to frontmatter `args` and the `## Invocation` block. Rewrite `## Step 4` to run the same three-way check against the repo destination, then the local destination, each keyed by the same `<type>s/<artifact-name>` label already used elsewhere in the file.
- **Mirror**: the file's existing step-numbered prose style (instruction doc, not literal bash — matches its current Step 4).
- **Validate**: re-read the rewritten Step 4 against the `sync.sh` branch logic for parity.

### Task 4: Tests

- **Action**: `sync-state.test.sh` — get/set round trip, get-on-missing-file. `sync.test.sh` — build a scratch repo dir + scratch `manifest.yaml`, run with `HOME=<tempdir>` so both `sync.sh`'s `$HOME/.claude` and `sync-state.sh`'s state file resolve into the sandbox (no code changes needed for test isolation; the real `~/.claude/` is never touched). Cover: fresh install records baseline; ordinary drift with no baseline; ordinary drift with baseline==dest; diverged reports `[DIVERGED]`; plain `--force` does NOT overwrite a diverged file; `--force-diverged` does; declining the diverged prompt (empty stdin) leaves the file untouched and reports `[SKIPPED]`.
- **Mirror**: `rename-tmux-window.test.sh` harness exactly.
- **Validate**: `bash .claude/tests/scripts/sync-state.test.sh && bash .claude/tests/scripts/sync.test.sh`, plus a full regression run of the existing sibling `*.test.sh` files.

### Task 5: Docs

- **Action**: one-sentence edit to `CLAUDE.md`'s repo-internal-tooling paragraph (add `sync-state.sh`); one new Gotchas table row noting `~/.claude/.sync-state.json` tracks last-synced hashes per artifact and should not be hand-edited or deleted.
- **Validate**: re-read the diff for accuracy.

## Validation

```bash
bash -n .claude/scripts/sync-state.sh
bash -n sync.sh
bash .claude/tests/scripts/sync-state.test.sh
bash .claude/tests/scripts/sync.test.sh
for t in .claude/tests/scripts/*.test.sh; do bash "$t" || echo "REGRESSION: $t"; done
bash sync.sh --dry-run   # read-only sanity check against the REAL ~/.claude
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| False-positive `[DIVERGED]` right after rollout (every existing install has no baseline) | Low — by design, no-baseline falls into ordinary-drift, not diverged | Explicit "no baseline → trusted" branch; documented as an accepted limitation in a code comment |
| Concurrent `sync.sh`/`promote-artifact` runs corrupting `.sync-state.json` | Low | Atomic write (tempfile + `os.replace`) — readers never see a half-written file; worst case is a lost update, not corruption |
| Plain `--force` silently bypassing the new safety net | Medium if not enforced carefully | Explicit design constraint: `--force`/`idempotency: overwrite` never reach the diverged branch — only `--force-diverged` does; covered by a dedicated test |
| Test suite mutating the real `~/.claude/` | Medium if done carelessly | All new tests run with `HOME` pointed at a `mktemp -d` sandbox; the only live-`~/.claude` touch in validation is `--dry-run` (read-only) |
| Worktree boundary — this session runs in a worktree, but the scripts write to the real `~/.claude/` by design | N/A — inherent to the tool | Unchanged from current behavior; already this tool's designed purpose, not a new risk |
| Scope creep into `sync-state.sh` needing its own manifest entry | Low | Explicitly a non-change, matching the existing `promote-artifact`/`validate-artifact` precedent |

## Acceptance

- [ ] `sync-state.sh` get/set round-trips correctly, including on a missing file/key
- [ ] `sync.sh` three-way branches all behave as specified; plain `--force` never overwrites a diverged file; `--force-diverged` does
- [ ] `promote-artifact/SKILL.md` Step 4 mirrors the same logic for both destinations
- [ ] New tests pass; full existing `.claude/tests/scripts/*.test.sh` suite still passes (no regressions)
- [ ] `CLAUDE.md` updated; `manifest.yaml` untouched
- [ ] `bash sync.sh --dry-run` runs clean against the real `~/.claude/`
