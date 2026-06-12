# Plan: M3 — Sync Script

**Source PRD**: `.claude/prds/user-wide-claude-portability.prd.md`
**Selected Milestone**: M3 — Sync script
**Complexity**: Medium

## Summary

Write `sync.sh` at repo root. It reads `manifest.yaml`, installs all portable artifacts to `~/.claude/`, and reports drift without touching files in `--dry-run` mode. SHA-256 comparison drives idempotency for files; directory hashing via sorted `find | sha256sum` handles skill directories. Python 3 (standard on all target Linux machines) parses the YAML manifest inline.

## Patterns to Mirror

No prior scripts in this repo. The only existing script is `~/.claude/scripts/vm-cleanup.sh` (external). Conventions below are from standard bash best practices:

| Category | Source | Pattern |
|---|---|---|
| Shebang | Unix convention | `#!/usr/bin/env bash` |
| Safety flags | bash best practice | `set -euo pipefail` |
| Paths | PRD constraint | `REPO_DIR="$(cd "$(dirname "$0")" && pwd)"`, `CLAUDE_DIR="$HOME/.claude"` — no absolute paths |
| Error output | Unix convention | `echo "ERROR: ..." >&2; exit 1` |
| Dry-run flag | GNU convention | `--dry-run` as long opt; `-n` as short opt |
| Force flag | GNU convention | `--force` / `-f` |

## Script Architecture

```
sync.sh
  ├── arg parsing         --dry-run / -n, --force / -f, install (default subcommand)
  ├── preflight checks    manifest exists, python3 available
  ├── yaml_get()          python3 inline YAML parser → stdout lines
  ├── file_sha256()       sha256sum of single file → 64-char hex
  ├── dir_sha256()        sorted find | sha256sum of directory tree → 64-char hex
  ├── install_file()      compare sha256, skip/prompt/overwrite based on mode
  ├── install_dir()       compare dir_sha256, cp -rp on mismatch
  ├── install_plugin()    check installed_plugins.json, run claude plugin install
  ├── scan_local_only()   walk ~/.claude/<type>/, report entries absent from manifest
  └── main()              iterate manifest sections, call handlers, print summary
```

## Files to Change

| File | Action | Why |
|---|---|---|
| `sync.sh` | CREATE at repo root | The sync script itself |
| `.claude/prds/user-wide-claude-portability.prd.md` | UPDATE M3 row | Mark `in-progress`, add plan path |
| `.claude/plans/portability-loop-runbook.md` | UPDATE M3 row | Mark `done` |

## Tasks

### Task 1: Scaffold `sync.sh` with arg parsing and preflight

- **Action**: Write the script header: shebang, `set -euo pipefail`, `REPO_DIR`/`CLAUDE_DIR`/`MANIFEST` constants, arg parsing loop (`--dry-run`, `--force`, subcommand `install`), and preflight assertions (manifest exists, python3 available, `~/.claude/` exists).
- **Mirror**: GNU long-opt convention; `set -euo pipefail` from bash best practices.
- **Validate**: `bash -n sync.sh` (syntax check); `./sync.sh --help` exits 0 and prints usage.

### Task 2: Implement YAML parsing helper

- **Action**: Write `yaml_get <section>` function using python3 inline:
  ```bash
  yaml_get() {
    python3 -c "
  import yaml, sys
  d = yaml.safe_load(open('$MANIFEST'))
  section = d.get('$1', [])
  for item in section:
      if isinstance(item, dict):
          print(item.get('name', item.get('id', '')))
      else:
          print(item)
  "
  }
  ```
  Also write `yaml_get_plugins` variant returning `id|marketplace` pairs.
- **Mirror**: Python3 `yaml.safe_load` (stdlib, no pip install).
- **Validate**: `./sync.sh --dry-run 2>&1 | head` shows parsed artifact names.

### Task 3: Implement SHA-256 helpers

- **Action**:
  - `file_sha256 <path>` → `sha256sum "$path" | cut -c1-64`
  - `dir_sha256 <path>` → `find "$path" -type f | sort | xargs sha256sum 2>/dev/null | sha256sum | cut -c1-64`
- **Mirror**: `sha256sum` (GNU coreutils, standard on Linux).
- **Validate**: `file_sha256 "$MANIFEST"` returns 64-char hex; calling twice on same file returns same value.

### Task 4: Implement `install_file()` and `install_dir()`

- **Action**:
  ```
  install_file <repo_path> <dest_path>:
    if dest doesn't exist → copy (or report MISSING in dry-run)
    elif sha256 matches  → skip (report OK)
    elif --force         → overwrite (report UPDATED)
    elif --dry-run       → report STALE
    else                 → prompt "Overwrite? [y/N]"

  install_dir <repo_path> <dest_path>:
    same logic but using dir_sha256; copy with cp -rp
  ```
- **Mirror**: Idempotency decision from M2 plan (skip/prompt/force).
- **Validate**: Run install twice on a temp dir; second run reports all OK with zero copies.

### Task 5: Implement `install_plugin()`

- **Action**:
  ```
  install_plugin <id> <marketplace>:
    if python3 detects id@marketplace in installed_plugins.json with scope=user → skip
    elif --dry-run → report MISSING_PLUGIN
    else → run: claude plugin install <id> --marketplace <marketplace>
  ```
  Note: plugin install requires internet and `claude` CLI. Script must warn if offline or `claude` not found, but not abort — continue with other artifacts.
- **Mirror**: `installed_plugins.json` format (version 2, plugins dict keyed by `<id>@<marketplace>`).
- **Validate**: Run with a mock `installed_plugins.json` containing one known plugin → skip reported; remove entry → MISSING_PLUGIN reported in dry-run.

### Task 6: Implement `scan_local_only()`

- **Action**: For each artifact type directory (`~/.claude/skills/`, `~/.claude/commands/`, `~/.claude/agents/`, `~/.claude/scripts/`), list entries and cross-reference against manifest. Report any entry NOT in manifest as `LOCAL_ONLY`.
- **Mirror**: Dry-run three-category output format: `[MISSING]`, `[STALE]`, `[LOCAL_ONLY]`.
- **Validate**: Add a fake skill dir in `~/.claude/skills/` not in manifest; dry-run reports it as LOCAL_ONLY.

### Task 7: Wire `main()` and summary report

- **Action**:
  - Call handlers for each section: `skills`, `commands`, `agents`, `scripts`, `claude_md`, `plugins`
  - After all sections: print summary line counts (e.g. `19 OK  2 UPDATED  1 MISSING  3 LOCAL_ONLY`)
  - `scan_local_only()` always runs (even in install mode) to surface untracked local work
- **Validate**: `./sync.sh --dry-run` on current machine shows all artifacts as OK (nothing installed yet → shows MISSING); `./sync.sh install` installs and re-run shows all OK.

## Validation

```bash
# Syntax check
bash -n sync.sh

# Dry-run (no changes to ~/.claude/)
./sync.sh --dry-run

# Install (copy artifacts to ~/.claude/)
./sync.sh install

# Idempotency: second install run must report all OK, zero copies
./sync.sh install 2>&1 | grep -c UPDATED  # expect 0

# Local-only detection
mkdir -p ~/.claude/skills/test-local-only-skill
./sync.sh --dry-run 2>&1 | grep LOCAL_ONLY  # expect 1 line
rmdir ~/.claude/skills/test-local-only-skill
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `claude plugin install` CLI syntax changes | Low | Wrap in a try/catch; log the exact command used; pin to documented form |
| `cp -rp` on a skill dir that already exists merges rather than replaces | Medium | Use `rm -rf dest && cp -rp src dest` only when SHA-256 differs and user confirms/force |
| `python3` not available on a target machine | Low | Add preflight check; exit with clear message "python3 required for YAML parsing" |
| `sha256sum` absent (non-GNU Linux) | Very Low | Also check for `shasum -a 256`; scope is Linux-only per PRD |
| `installed_plugins.json` format version bump | Low | Version check at startup; warn and skip plugin section if version != 2 |

## Acceptance

- [ ] `bash -n sync.sh` exits 0
- [ ] `./sync.sh --dry-run` reports all 5 artifact sections without touching `~/.claude/`
- [ ] `./sync.sh install` installs all artifacts; re-run reports 0 UPDATED
- [ ] `./sync.sh --dry-run` reports LOCAL_ONLY for a manually added fake skill
- [ ] CLAUDE.md installed to `~/.claude/CLAUDE.md` when `claude_md.portable: true`
- [ ] Plugin section skipped gracefully when `claude` CLI not found (warning only, no abort)
- [ ] PRD M3 row updated to `in-progress` with plan path
