# Plan: Cross-Project Promote Tool

**Complexity**: Medium

## Summary

`promote-artifact` and `validate-artifact` are already synced globally to `~/.claude/skills/` and
invokable from any project. The blocker: Step 3 of promote-artifact resolves the repo root via
`$CLAUDE_PROJECT_DIR` or `git rev-parse --show-toplevel`, which points to the **caller's** project,
not the portability repo. This plan adds a portability-repo discovery layer so the full validate →
copy → manifest-update → git pipeline runs against the correct repo regardless of where it's invoked.

---

## Pre-flight

- [x] `promote-artifact` and `validate-artifact` SKILL.md files are readable and understood.
- [x] `manifest.yaml` is readable; skills/commands sections are currently empty.
- [x] Worktree is clean on `main`.

---

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Naming | `.claude/skills/promote-artifact/SKILL.md:2` | Skill dirs: `<verb>-artifact/SKILL.md` |
| Config lookup | `.claude/skills/promote-artifact/SKILL.md:55` | Check env var first, then file fallback |
| Manifest update | `.claude/skills/promote-artifact/SKILL.md:79–101` | Python snippet inlined in SKILL.md |
| Git pipeline | `.claude/skills/promote-artifact/SKILL.md:122–193` | Bash blocks inlined in SKILL.md |
| Command files | `.claude/commands/vm-health.md:1` | Thin trigger → delegates to skill |

---

## Files to Change

| File | Action | Why |
|---|---|---|
| `.claude/settings.json` | UPDATE | Add PostToolUse hook: fires on Write/Edit/MultiEdit matching `.claude/**/*.md` |
| `.claude/scripts/update-plans-index.sh` | CREATE | Scans `.claude/plans/*.md`, builds a title table, overwrites `index.md` |
| `.claude/plans/index.md` | CREATE | Auto-maintained index of all `.claude/plans/*.md` files |
| `.claude/skills/promote-artifact/SKILL.md` | UPDATE | Add portability-repo discovery to Step 3; add `--move` flag; update git pipeline to `cd` into portability repo |
| `.claude/commands/set-portability-repo.md` | CREATE | One-time setup command: writes the portability repo path to `~/.claude/config/portability-repo` |
| `manifest.yaml` | UPDATE | Add `promote-artifact`, `validate-artifact`, and `set-portability-repo` entries so they sync to new machines |

---

## Tasks

### Task 0: Plans index hook

**Files**: `.claude/settings.json`, `.claude/scripts/update-plans-index.sh`, `.claude/plans/index.md`

**Action A — hook** (`.claude/settings.json`):

Add a `PostToolUse` hook that fires after `Write`, `Edit`, and `MultiEdit` when the modified file
path matches `.claude/**/*.md`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PROJECT_DIR}/.claude/scripts/update-plans-index.sh\" \"${CLAUDE_PROJECT_DIR}\""
          }
        ]
      }
    ]
  }
}
```

The script itself filters for `.claude/**/*.md` paths — no path condition in the hook matcher (hook
matchers only support tool name patterns, not file path conditions).

**Action B — script** (`.claude/scripts/update-plans-index.sh`):

```bash
#!/usr/bin/env bash
# Rebuilds .claude/plans/index.md — only runs when touched file is under .claude/plans/
PROJECT_DIR="${1:-$CLAUDE_PROJECT_DIR}"
PLANS_DIR="$PROJECT_DIR/.claude/plans"
INDEX="$PLANS_DIR/index.md"

# Early exit: only act when a .claude/plans/**/*.md file was touched
touched=$(python3 -c "import json,os,sys; d=json.loads(os.environ.get('CLAUDE_TOOL_INPUT','{}'));  print(d.get('file_path',''))" 2>/dev/null)
case "$touched" in
  */.claude/plans/*.md|*/.claude/plans/**/*.md) ;;  # continue
  *) exit 0 ;;                                       # not a plans file — skip
esac
[[ "$touched" == "$INDEX" ]] && exit 0              # ignore writes to index.md itself

{
  echo "# Plans Index"
  echo ""
  echo "> Auto-generated. Do not edit manually."
  echo ""
  echo "| File | Title |"
  echo "|---|---|"
  DEPTH="${PLANS_INDEX_DEPTH:-2}"
  find "$PLANS_DIR" -maxdepth "$DEPTH" -name "*.md" ! -name "index.md" | sort | while IFS= read -r f; do
    rel="${f#$PROJECT_DIR/}"
    title=$(grep -m1 "^# " "$f" 2>/dev/null | sed 's/^# //' || echo "—")
    echo "| [\`$rel\`]($rel) | $title |"
  done
} > "$INDEX"
```

**Action C** — run the script immediately to seed `index.md` with the current state.

- **Mirror**: `${CLAUDE_PROJECT_DIR}` hook path convention from global CLAUDE.md rules.

- **Validate**:
- Hook JSON is valid (`python3 -c "import json; json.load(open('.claude/settings.json'))"`)
- Script is executable and produces a non-empty `index.md`
- `index.md` lists `plan-cross-project-promote.plan.md`

---

### Task 1: Add portability-repo discovery to `promote-artifact`

**File**: `.claude/skills/promote-artifact/SKILL.md`

- **Action**: Replace Step 3 "Determine destinations" with a three-tier lookup:

```
1. CLAUDE_PORTABILITY_REPO env var
2. Contents of ~/.claude/config/portability-repo (trim whitespace)
3. Fallback: $CLAUDE_PROJECT_DIR / git rev-parse --show-toplevel  (backward compat — used when
   already inside the portability repo)
```

Store the resolved path as `PORTABILITY_REPO`. Use it for both:
- `repo dest: $PORTABILITY_REPO/<type>s/<artifact-name>`
- manifest path: `$PORTABILITY_REPO/manifest.yaml`

- **Mirror**: The existing two-tier env/git pattern in Step 3. Third tier is additive.

- **Validate**: Read the updated SKILL.md and confirm all three lookup tiers are present with the right
priority order.

---

### Task 2: Add `--move` flag with reference check to `promote-artifact`

**File**: `.claude/skills/promote-artifact/SKILL.md`

- **Action**: Add `--move` to the frontmatter args list:

```yaml
- name: --move
  description: After both destinations are successfully written, check for references then delete the source. Prompts user if references are found.
  required: false
```

Add two new steps after the copy loop.

---

**Step 4b — Reference scan (--move only)**

Search for references to `<artifact-name>` across two scopes:

```bash
# Scope 1: caller's project (where source lives)
grep -rn "<artifact-name>" "<project-root>" \
  --include="*.md" --include="*.sh" --include="*.yaml" --include="*.json" \
  --exclude-dir=".git" \
  | grep -v "^<source-path>"   # exclude the artifact itself

# Scope 2: user-wide artifacts
grep -rn "<artifact-name>" "$HOME/.claude" \
  --include="*.md" --include="*.sh" --include="*.yaml" \
  --exclude-dir=".git"
```

Classify each hit:
- `/<artifact-name>` invocation in a skill/command → **INVOKE ref**
- `name: <artifact-name>` in manifest or frontmatter → **MANIFEST ref**
- prose mention in CLAUDE.md or docs → **DOC ref**

Output:

```
Reference scan for '<artifact-name>':
  INVOKE  .claude/skills/other-skill/SKILL.md:14   — /promote-artifact my-tool
  MANIFEST manifest.yaml:8                          — name: my-tool
  DOC     CLAUDE.md:22                              — "my-tool handles X"
  (2 project, 1 user-wide)
```

If **no references found**: print `✓ No references found — safe to remove` and proceed to Step 4c.

If **references found**: present to the user:

```
⚠ References found. Choose an action:
  [a] Remove source anyway — references will break until updated manually
  [b] Update references first — I'll show you what to change, then confirm removal
  [c] Keep source — abort --move, artifact stays in project
```

- User picks `a` → proceed to Step 4c.
- User picks `b` → list each reference with the suggested replacement path
  (`~/.claude/<type>s/<artifact-name>` for local refs), ask for confirmation,
  apply updates via Edit, then proceed to Step 4c.
- User picks `c` → print `[KEPT] Source retained at <source-path>` and stop (copies already done).
- `--force` flag skips the prompt and selects `a` automatically, printing the reference list as warnings.

---

**Step 4c — Remove source (--move only, after 4b resolves)**

Only runs after Step 4b completes without aborting.

- Source is a directory → `rm -rf "<source-path>"`
- Source is a file     → `rm "<source-path>"`

Report: `[REMOVED] Source deleted: <source-path>`

If either destination copy (Step 4) failed or was skipped due to error, skip Steps 4b and 4c entirely and print:
`[KEPT] Source retained: copy to <failed-dest> did not succeed`

---

- **Mirror**: Reference-scan pattern mirrors validate-artifact's static grep approach. User decision prompt mirrors the `--force` / prompt flow already in Step 4.

- **Validate**: Confirm Step 4b grep covers both project and `~/.claude` scopes; confirm three user choices are present; confirm `--force` auto-selects `a`.

---

### Task 3: Update git pipeline to operate in the portability repo

**File**: `.claude/skills/promote-artifact/SKILL.md`

- **Action**: In the "Git Pipeline (--git flag only)" section, prepend every git/gh command block with:

```bash
cd "$PORTABILITY_REPO"
```

The branch, commit, push, PR-create, and squash-merge blocks must all run from `$PORTABILITY_REPO`,
not from the caller's CWD.

- **Mirror**: Same inline bash-block style already used in the git pipeline section.

- **Validate**: Confirm `cd "$PORTABILITY_REPO"` appears before the first `git checkout -b` command.

---

### Task 4: Create `set-portability-repo` command

**File**: `.claude/commands/set-portability-repo.md`

- **Action**: New command file. Frontmatter: `name: set-portability-repo`, `description: Register the
path to your user-wide-claude-a portability repo so /promote-artifact works cross-project.`

Behavior:
1. Ask the user: "Enter the absolute path to your portability repo:" (skip if `$1` provided).
2. Expand `~` to `$HOME`.
3. Verify the path is a git repo containing `manifest.yaml`.
4. Write the path to `~/.claude/config/portability-repo` (create `~/.claude/config/` if needed).
5. Print `✓ Portability repo set to: <path>`.

- **Mirror**: Thin command → inline bash steps (no separate script file needed; pure shell).

- **Validate**: After writing the command, confirm it contains the three verification steps (expand,
check manifest.yaml, write file) and does not reference any hardcoded paths.

---

### Task 5: Add skills to `manifest.yaml`

**File**: `manifest.yaml`

- **Action**: Add two entries to the `skills:` section:

```yaml
skills:
  - name: promote-artifact
  - name: validate-artifact
```

These skills live under `.claude/skills/` in this repo. Adding them ensures `bash sync.sh`
installs them to `~/.claude/skills/` on any new machine.

- **Mirror**: Existing plugin entry format in `manifest.yaml` (name-only entries).

- **Validate**: Run `bash sync.sh --dry-run` and confirm `promote-artifact` and `validate-artifact`
appear as `[WOULD COPY]` (not `[MISSING]`).

---

## Validation

```bash
# Task 0
python3 -c "import json; json.load(open('.claude/settings.json'))"     # valid JSON
bash .claude/scripts/update-plans-index.sh .                            # index rebuilds cleanly
grep "plan-cross-project-promote" .claude/plans/index.md               # listed in index

# Tasks 1–5
bash sync.sh --dry-run           # promote-artifact, validate-artifact, set-portability-repo not [MISSING]
grep -n "PORTABILITY_REPO" .claude/skills/promote-artifact/SKILL.md   # must appear 3+ times
grep -n "cd.*PORTABILITY_REPO" .claude/skills/promote-artifact/SKILL.md  # git pipeline fix
grep "manifest.yaml" .claude/commands/set-portability-repo.md          # verification step present
```

---

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Caller in subdir of portability repo; fallback `git rev-parse` returns portability root by coincidence | Low | Document in SKILL.md that fallback is for same-repo invocations only |
| `~/.claude/config/` dir doesn't exist on fresh machine | Medium | `set-portability-repo` command creates it; also add `mkdir -p` guard in Step 3 |
| `$PORTABILITY_REPO` contains spaces | Low | Quote all usages: `"$PORTABILITY_REPO"` |
| `--move` + `--force` silently removes a referenced artifact | Medium | `--force` still prints reference list as warnings before removing |
| Reference grep matches artifact name as substring (e.g. `my-tool` hits `my-tool-v2`) | Low | Grep pattern anchored with word boundaries: `\bmy-tool\b` |
| User picks `b` (update refs) but edit fails mid-way | Low | Edit each file atomically; if any Edit fails, abort removal and report partial state |

---

## Acceptance

- [ ] PostToolUse hook fires on Write/Edit/MultiEdit and updates `index.md`
- [ ] `index.md` lists all `.md` files under `.claude/` grouped by section
- [ ] `bash sync.sh --dry-run` shows `promote-artifact`, `validate-artifact`, `set-portability-repo` as would-copy
- [ ] `promote-artifact` SKILL.md has three-tier repo discovery with correct priority
- [ ] `--move` arg in frontmatter; Step 4b reference scan covers project + `~/.claude` scopes
- [ ] Three user choices present (remove anyway / update refs / keep); `--force` auto-picks `a`
- [ ] Step 4c gated on both copies succeeding AND Step 4b not aborting
- [ ] Git pipeline section uses `cd "$PORTABILITY_REPO"` before all git operations
- [ ] `set-portability-repo` command file exists and has no hardcoded paths
- [ ] All changes validate with `grep` checks above
