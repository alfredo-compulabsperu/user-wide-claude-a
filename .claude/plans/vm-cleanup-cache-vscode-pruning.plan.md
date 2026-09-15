# Plan: `.cache` full-wipe + `.vscode-server` stale-version pruning (US-VMCLEANUP-4, US-VMCLEANUP-5)

**Source**: `docs/user-stories/vm-cleanup.md` (US-VMCLEANUP-4, US-VMCLEANUP-5)
**Complexity**: Medium
**Status**: complete — all 4 tasks implemented, validated, and committed

## Summary

Two related SAFE-tier expansions to `vm-cleanup.sh`, requested and grounded via live inventory of this VM's `~/.cache` (8.8G) and `~/.vscode-server` (4.4G):

1. **US-VMCLEANUP-4**: `/vm-cleanup --clean` deletes the entire `~/.cache` directory (not just `thumbnails`/`fontconfig`/`pip`), excluding `firebase/` so the existing `firebase/emulators` RISKY-tier section (section 7) keeps working unchanged.
2. **US-VMCLEANUP-5**: `/vm-cleanup --clean` prunes stale VS Code Remote server versions under `~/.vscode-server/cli/servers/`, keeping only the version matching the single entry under `~/.vscode-server/bin/` — reclaiming space without ever forcing a VS Code reconnect/redownload (unlike a full-directory wipe).

Both are SAFE tier: every `.cache` subdirectory was verified (live inventory + a protected-file pattern scan) to be a regenerable tool cache with zero real secrets; every `.vscode-server/cli/servers/` entry that gets removed was verified to be a confirmed-stale, unreferenced install, never the active one.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Section structure | `vm-cleanup.sh:219-227` (current section 6) | `_section` header, per-item `_human`/`_add`/`_safe` loop |
| SAFE vs RISKY | `vm-cleanup.sh:60-84` | Both new pieces are SAFE tier → use `_safe`, not `_confirm` |
| New-section placement | section 12 (dangling processes) appended after section 11, before Summary, rather than renumbering | Same approach — append `.vscode-server` pruning as a new final section |
| Tests | `.claude/tests/scripts/vm-cleanup.test.sh` | Sandboxed `$HOME` pattern; zero existing coverage for `.cache`/`firebase`/`vscode-server` (confirmed via grep) |
| Docs | `docs/vm-cleanup.md` | Classification table + prose sections; mirror "Dangling process detection" section's structure for the new `.vscode-server` prose |

## Files to Change

| File | Action | Why |
|---|---|---|
| `.claude/scripts/vm-cleanup.sh` | UPDATE | Rewrite section 6 (`.cache` whole-dir wipe, skip `firebase`); append new final section (`.vscode-server` pruning) |
| `.claude/tests/scripts/vm-cleanup.test.sh` | UPDATE | New tests for both |
| `docs/vm-cleanup.md` | UPDATE | Classification table SAFE row + new prose section |
| `docs/user-stories/vm-cleanup.md` | UPDATE (Task 4, after GREEN) | Flip `Implementation: Open → Closed` for both stories, version-history entry |

## Design

### Section 6 rewrite (`.cache` whole-dir wipe, exclude `firebase`)

```bash
_section "~/.cache (SAFE — full wipe, except firebase/ which stays RISKY below)"
while IFS= read -r entry; do
  name=$(basename "$entry")
  [[ "$name" == "firebase" ]] && continue
  SZ=$(_human "$entry")
  echo "  ~/.cache/${name}: ${SZ}"
  _add "$entry"
  _safe "rm -rf ~/.cache/${name}" rm -rf "$entry"
done < <(find "$HOME/.cache" -mindepth 1 -maxdepth 1 2>/dev/null | sort)
```

Section 7 (`firebase/emulators`, RISKY) stays byte-for-byte unchanged — the `firebase` top-level dir is preserved by the skip, so section 7 still finds it.

### New final section: prune stale `.vscode-server` versions

Identify "current" via the single directory under `~/.vscode-server/bin/`; delete every `~/.vscode-server/cli/servers/<name>` whose name isn't exactly `Stable-<current-hash>`. This naturally also removes `.staging` entries — they never match that literal string, so no special-casing is needed. If `bin/` doesn't have exactly one entry, skip pruning entirely with an explanatory message (never guess). Never touches `extensions/`, `data/`, or `bin/` itself.

```bash
_section "~/.vscode-server (SAFE — prune stale server versions, keep current)"
VSCS="$HOME/.vscode-server"
if [[ ! -d "$VSCS" ]]; then
  echo "  not present"
else
  mapfile -t BIN_ENTRIES < <(find "$VSCS/bin" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  if [[ ${#BIN_ENTRIES[@]} -ne 1 ]]; then
    echo "  cannot identify a single current version under ~/.vscode-server/bin (found ${#BIN_ENTRIES[@]}) — skipping prune for safety"
  else
    CURRENT_HASH=$(basename "${BIN_ENTRIES[0]}")
    FOUND_STALE=false
    while IFS= read -r entry; do
      name=$(basename "$entry")
      [[ "$name" == "Stable-${CURRENT_HASH}" ]] && continue
      SZ=$(_human "$entry")
      echo "  ~/.vscode-server/cli/servers/${name}: ${SZ}"
      _add "$entry"
      _safe "rm -rf ~/.vscode-server/cli/servers/${name}" rm -rf "$entry"
      FOUND_STALE=true
    done < <(find "$VSCS/cli/servers" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    $FOUND_STALE || echo "  no stale versions found (current: ${CURRENT_HASH:0:12}...)"
  fi
fi
```

## Tasks

### Task 1: `.cache` whole-dir wipe
- **Action**: RED — sandboxed `$HOME/.cache` with fake `foo`/`bar` dirs plus a `firebase/emulators` dir; assert after `--clean`: `foo`/`bar` gone, `firebase/emulators` still present, `[SAFE]` reported for `foo`/`bar`. GREEN — rewrite section 6 as designed above. Regression assertion: a `.cache/thumbnails` fixture is still removed (catches accidental scope-narrowing vs. today's behavior).
- **Mirror**: `vm-cleanup.sh:219-227`'s existing loop shape.
- **Validate**: `bash .claude/tests/run-all.sh`

### Task 2: `.vscode-server` stale-version pruning
- **Action**: RED — sandboxed `$HOME/.vscode-server` fixture: `bin/<hash-A>/`, `cli/servers/Stable-<hash-A>/` (current), `cli/servers/Stable-<hash-B>/` (stale), `cli/servers/Stable-<hash-C>.staging/` (stale/incomplete), `extensions/marker-file`, `data/marker-file`. Assert after `--clean`: `Stable-<hash-A>` present, `Stable-<hash-B>` and the `.staging` entry gone, both marker files untouched, `[SAFE]` reported for the 2 removed entries. GREEN — implement the new section. Edge case: `bin/` with 0 or 2+ entries → assert pruning is skipped entirely (nothing under `cli/servers/` touched), message printed.
- **Mirror**: section 11 (nvm versions)'s "enumerate fresh each run" idempotency pattern — no state file needed, matches this script's existing convention.
- **Validate**: `bash .claude/tests/run-all.sh`

### Task 3: Docs
- **Action**: Update `docs/vm-cleanup.md`'s Classification table SAFE row (full `.cache` wipe, excluding `firebase`); add a new prose section for `.vscode-server` pruning mirroring "Dangling process detection"'s structure (what it does, why it's safe, what it never touches). No `--help` text changes — expanded SAFE-tier scope under existing `--clean`, not a new flag.
- **Mirror**: `docs/vm-cleanup.md`'s existing prose section style.
- **Validate**: manual side-by-side read of the two changed sections vs. the implemented script behavior.

### Task 4: Flip story Implementation status
- **Action**: Once Tasks 1-3 are GREEN and validated, edit `docs/user-stories/vm-cleanup.md`: US-VMCLEANUP-4 and US-VMCLEANUP-5 `Implementation: Open → Closed`, add a version-history entry with the implementing commit hash. Update `docs/user-stories/index.md`'s Implementation column to match.
- **Mirror**: existing version-history entry pattern in the same file.
- **Validate**: n/a (docs-only)

## Validation

```bash
shellcheck .claude/scripts/vm-cleanup.sh
bash .claude/tests/run-all.sh
bash .claude/scripts/vm-cleanup.sh --dry-run   # manual: confirm new targets show up, no writes
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Misidentifying "current" `.vscode-server` version if `bin/` ever holds 2 entries (mid-update race) | Low | Explicit skip-with-message when count ≠ 1, never guess |
| Section 6 rewrite accidentally narrows scope vs. today | Low | Regression assertion for `thumbnails` specifically (Task 1) |
| `.cache` wipe hits a tool mid-operation | Low-Medium (inherent to any cache wipe, not new) | Already accepted in the story's Why; SAFE tier still appropriate per the verified false-positive-free protected-file scan; no code-level mitigation beyond what's already true of today's thumbnails/fontconfig/pip wipe |
| New `.vscode-server` section placement (appended at end, not near section 6) reads oddly in output ordering | Cosmetic only | Matches existing precedent (section 12 also appended at end) — accepted, not fixed |

## Acceptance Criteria

- [x] `/vm-cleanup --clean` deletes `~/.cache` in full except `firebase/`, which stays RISKY-tier unchanged
- [x] `/vm-cleanup --clean` prunes stale `~/.vscode-server` versions, keeps the current one, never touches `extensions/`/`data/`
- [x] Pruning skips entirely (never guesses) when `bin/` doesn't have exactly one entry
- [x] Second consecutive `--clean` run is a no-op for `.vscode-server` pruning
- [x] `shellcheck` clean (no new findings beyond the pre-existing baseline)
- [x] `bash .claude/tests/run-all.sh` fully green
- [x] `docs/vm-cleanup.md` and `docs/user-stories/vm-cleanup.md` updated

## Acceptance

- [x] All tasks complete
- [x] Validation passes
- [x] Patterns mirrored, not reinvented
