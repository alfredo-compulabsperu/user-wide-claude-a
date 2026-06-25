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
    description: Skip all overwrite prompts and proceed automatically.
    required: false
  - name: --git
    description: After local install, run the full git pipeline (branch → commit → push → PR → squash-merge).
    required: false
---

# promote-artifact

Validates and installs an artifact into both the local `~/.claude/` directory and the repo. Optionally pushes it through a full git pipeline via `--git`.

## Invocation

```
/promote-artifact <path> [--type skill|command|agent|script] [--force] [--git]
```

---

## Step 1 — Detect artifact type

Use `--type` if provided. Otherwise apply these heuristics in order:

| Check | Type |
|---|---|
| `<path>` is a directory containing `SKILL.md` | `skill` |
| `<path>` is a `.md` file with a name matching a command (imperative verb or action noun) | `command` |
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

## Step 4 — Copy to repo and local

For skill directories, exclude `evals/` — evals are project-local development scaffolding and must not be distributed.

For each destination (repo, then local):

1. If dest does not exist → copy (`rsync -a --exclude=evals/` for skill dirs, `cp -p` for files). Report `[INSTALLED]`.
2. If dest exists and SHA-256 matches → skip. Report `[OK]`.
3. If dest exists and SHA-256 differs:
   - `--force` → overwrite. Report `[UPDATED]`.
   - Otherwise → prompt "Overwrite existing <dest>? [y/N]". Overwrite on `y`, skip on `n`.

For scripts with `executable: true`, run `chmod +x <local dest>` after copy.

## Step 5 — Update manifest.yaml

Read `<repo_root>/manifest.yaml`. Check whether the artifact is already listed under its section (match by `name`). If not present, append the new entry:

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
