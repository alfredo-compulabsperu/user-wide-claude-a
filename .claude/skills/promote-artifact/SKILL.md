---
name: promote-artifact
description: Validate a user-wide Claude artifact then install it locally and into the repo. With --git, branches, commits, pushes, opens a PR, and squash-merges automatically.
triggers:
  - /promote-artifact
args:
  - name: path
    description: Absolute or relative path to the artifact file or directory to promote.
    required: true
  - name: --type
    description: "Explicit artifact type override: skill | command | agent | script"
    required: false
  - name: --force
    description: Skip overwrite prompts for ordinary drift (SHA-256 differs, no prior baseline or baseline matches dest). Never bypasses a [DIVERGED] destination.
    required: false
  - name: --force-diverged
    description: Also overwrite destinations flagged [DIVERGED] (edited out-of-band since last sync) without prompting.
    required: false
  - name: --git
    description: After local install, run the full git pipeline (branch → commit → push → PR → squash-merge).
    required: false
---

# promote-artifact

Validates and installs an artifact into both the local `~/.claude/` directory and the repo. Optionally pushes it through a full git pipeline via `--git`.

## Invocation

```
/promote-artifact <path> [--type skill|command|agent|script] [--force] [--force-diverged] [--git]
```

---

## Step 1 — Detect artifact type

Use `--type` if provided. Otherwise apply these heuristics in order:

| Check | Type |
|---|---|
| `<path>` is a directory containing `SKILL.md` | `skill` |
| `<path>` is a `.md` file with a name matching a command (imperative verb or action noun) | `command` |
| `<path>` basename is `CLAUDE.md` | `claude_md` |
| `<path>` is a `.md` file | `agent` |
| `<path>` is a `.sh` file or executable | `script` |
| Ambiguous | Ask user to specify `--type` before continuing |

## Step 2 — Validate

Run `/validate-artifact <path>`:

- **FAIL** → abort immediately. Show the validation findings. Do not copy any files.
- **WARN** → print the warnings, then ask: "Proceed despite warnings? [y/N]" (skip prompt if `--force`)
- **PASS** → continue

## Step 3 — Determine destinations

Resolve repo root via `$CLAUDE_PROJECT_DIR` env var (primary) or `git rev-parse --show-toplevel` (fallback).

```
repo dest:  <repo_root>/.claude/<type>s/<artifact-name>
local dest: $HOME/.claude/<type>s/<artifact-name>
```

For commands, preserve subdirectory structure (e.g. `archived/` prefix) if present in `<path>`.

**Exception — `claude_md` type**: CLAUDE.md is a singleton file, not a named
collection member, so it has no pluralized `<type>s/` directory and no
`<artifact-name>` segment:

```
repo dest:  <repo_root>/.claude/CLAUDE.md
local dest: $HOME/.claude/CLAUDE.md
```

## Step 4 — Copy to repo and local (three-way divergence check)

Use the same last-synced-baseline check `sync.sh` uses, via `.claude/scripts/sync-state.sh get|set <key>`:

- **repo dest** — keyed `repo:<type>s/<artifact-name>` (or `repo:CLAUDE.md` for the `claude_md` singleton).
- **local dest** — keyed `<type>s/<artifact-name>` (or `CLAUDE.md` for the singleton) — the *same* key `sync.sh` uses for this path, so the two tools share one baseline and neither falsely flags the other's normal sync as out-of-band.

For each destination (repo, then local):

1. Dest does not exist → copy (`cp -rp` for dirs, `cp -p` for files). Report `[INSTALLED]`. Record the baseline (`sync-state.sh set <key> <sha256 of dest>`).
2. Dest exists and SHA-256 matches src → skip. Report `[OK]`. Self-heal the baseline (`sync-state.sh set <key> <sha256>`) even on a match, so pre-existing installs need no manual seeding.
3. Dest exists and SHA-256 differs from src → read the baseline (`sync-state.sh get <key>`):
   - No baseline, or baseline equals dest's current hash → **ordinary drift**: `--force` overwrites without prompting; otherwise prompt "Overwrite existing <dest>? [y/N]". Overwrite on `y`, skip on `n`. Update the baseline on overwrite.
   - Baseline recorded and differs from dest's current hash → **`[DIVERGED]`**: show `diff -u <dest> <src>` (files) or `diff -rq <dest> <src>` (dirs). Plain `--force` does **not** bypass this — only `--force-diverged`, or an explicit interactive `y`, does. Declining reports `[SKIPPED] <dest> (out-of-band edit preserved)` and suggests re-running `/promote-artifact` on that destination instead to pull the hand-edit into the repo. Update the baseline on overwrite.

For scripts with `executable: true`, run `chmod +x <local dest>` after copy.

**Accepted limitation**: immediately after this check ships, artifacts with no recorded baseline yet fall into ordinary-drift, not diverged — protection applies going forward only, matching `sync.sh`.

## Step 5 — Update manifest.yaml

For `skill|command|agent|script`, read `<repo_root>/manifest.yaml`, check whether the artifact is already listed under its section (match by `name`), and if not present, append the new entry:

```python
import yaml

with open('manifest.yaml') as f:
    d = yaml.safe_load(f)

section = '<type>s'        # e.g. 'skills', 'commands', 'agents', 'scripts'
name = '<artifact-name>'
source_path = '<path>'    # the path argument from the /promote-artifact invocation

if not any(e.get('name') == name for e in d.get(section, [])):
    entry = {'name': name}
    if section == 'scripts':
        import os
        entry['executable'] = os.access(source_path, os.X_OK)
    d.setdefault(section, []).append(entry)
    with open('manifest.yaml', 'w') as f:
        yaml.dump(d, f, default_flow_style=False, sort_keys=False)
    print('Manifest: updated')
else:
    print('Manifest: already listed')
```

**Exception — `claude_md` type**: there is no list section to append to — `claude_md`
is a single scalar flag. Set it instead (idempotent no-op if already `true`):

```python
import yaml

with open('manifest.yaml') as f:
    d = yaml.safe_load(f)

if not d.get('claude_md', {}).get('portable'):
    d.setdefault('claude_md', {})['portable'] = True
    with open('manifest.yaml', 'w') as f:
        yaml.dump(d, f, default_flow_style=False, sort_keys=False)
    print('Manifest: claude_md.portable set to true')
else:
    print('Manifest: already portable')
```

## Step 6 — Summary (local-only mode)

Print:

```
Promoted: <artifact-name>
Type:     <type>
Repo:     .claude/<type>s/<artifact-name>/
Local:    ~/.claude/<type>s/<artifact-name>/
Manifest: updated | already listed

Next: run /promote-artifact <path> --git to push to remote
```

**Exception — `claude_md` type**: no `<artifact-name>` segment or pluralized
directory (singleton file, per the Step 3 exception):

```
Promoted: CLAUDE.md
Type:     claude_md
Repo:     .claude/CLAUDE.md
Local:    ~/.claude/CLAUDE.md
Manifest: claude_md.portable set to true | already portable

Next: run /promote-artifact ~/.claude/CLAUDE.md --git to push to remote
```

If `--git` was passed, skip this summary and continue to the git pipeline below.

---

## Git Pipeline (--git flag only)

### Git preflight

Run before any git operations (after M5 local steps are complete — do not roll back M5 if git fails):

```bash
command -v git >/dev/null || { echo "ERROR: git not found"; exit 1; }
command -v gh  >/dev/null || { echo "ERROR: gh not found — install GitHub CLI"; exit 1; }
gh auth status            || { echo "ERROR: gh not authenticated — run: gh auth login"; exit 1; }
git remote get-url origin || { echo "ERROR: no remote origin configured"; exit 1; }
git pull --ff-only origin main || { echo "ERROR: local main is behind remote — pull first"; exit 1; }
```

### Branch, commit, push

```bash
BRANCH="promote/<type>/<artifact-name>"
git checkout -b "$BRANCH"
git add .claude/<type>s/<artifact-name> manifest.yaml
git commit -m "promote(<type>): <artifact-name>"
git push -u origin "$BRANCH"
```

**Exception — `claude_md` type**: no `<artifact-name>` segment (singleton file):

```bash
BRANCH="promote/claude_md/CLAUDE.md"
git checkout -b "$BRANCH"
git add .claude/CLAUDE.md manifest.yaml
git commit -m "promote(claude_md): CLAUDE.md"
git push -u origin "$BRANCH"
```

### Create PR

```bash
gh pr create \
  --title "promote(<type>): <artifact-name>" \
  --base main \
  --body "$(cat <<'EOF'
## Promoted artifact

- **Type**: <type>
- **Name**: <artifact-name>
- **Source machine**: $(whoami)@$(hostname)
- **Promoted at**: $(date +%Y-%m-%d)

## Validation

<paste /validate-artifact output here>

## Manifest entry added

- name: <artifact-name>

Promoted via \`/promote-artifact --git\`
EOF
)"
```

**Exception — `claude_md` type**: the PR body's "Manifest entry added" section
reports the scalar flag instead of a `name:` list entry:

```
## Manifest entry added

- claude_md.portable: true
```

Capture the PR URL from `gh pr create` output.

### Squash merge and cleanup

```bash
gh pr merge --squash --delete-branch --yes
git checkout main
git pull origin main
```

### Final summary

```
Promoted: <artifact-name>
Type:     <type>
Branch:   promote/<type>/<artifact-name> (deleted)
PR:       #N — <pr-url>
Local:    ~/.claude/<type>s/<artifact-name>/ ✓
Repo:     .claude/<type>s/<artifact-name>/ (on main) ✓
Manifest: updated ✓
```
