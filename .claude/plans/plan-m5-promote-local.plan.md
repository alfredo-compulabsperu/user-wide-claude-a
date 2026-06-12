# Plan: M5 — `/promote-artifact` Skill (Local)

**Source PRD**: `.claude/prds/user-wide-claude-portability.prd.md`
**Selected Milestone**: M5 — `/promote-artifact` skill (local)
**Complexity**: Medium

## Summary

Create a `promote-artifact` Claude Code skill that accepts an artifact path, runs `/validate-artifact` as a gate, then installs it in two places: `~/.claude/<type>/` (for immediate use) and the repo's `<type>/` directory (for version control via M6). Also updates `manifest.yaml`. Works fully offline with no git operations — M6 handles the git pipeline as a follow-on step.

## Artifact Type Detection

Priority: explicit `--type` flag overrides all heuristics.

| Heuristic | Type |
|---|---|
| Directory containing `SKILL.md` | `skill` |
| `.md` file matching command naming patterns | `command` |
| `.md` file matching agent naming patterns | `agent` |
| `.sh` file or executable script | `script` |
| Ambiguous → prompt user to specify `--type` | — |

## Promote Flow

```
/promote-artifact <path> [--type skill|command|agent|script] [--force]

1. Detect artifact type (heuristic or --type)
2. Run /validate-artifact <path>
   - FAIL → abort with error; show validation findings
   - WARN → prompt "Proceed despite warnings? [y/N]" (--force skips prompt)
   - PASS → continue
3. Determine dest names:
   - repo dest:  <repo_root>/<type>s/<artifact-name>[.md]
   - local dest: ~/.claude/<type>s/<artifact-name>[.md]
4. If dest exists: compare SHA-256; if identical → skip; else prompt overwrite (--force skips)
5. Copy <path> → repo dest (cp -rp for dirs)
6. Copy <path> → local dest (cp -rp for dirs)
7. Update manifest.yaml: add entry to appropriate section if not already present
8. Print summary:
   Promoted: <artifact-name>
   Type: skill
   Repo:  skills/<name>/
   Local: ~/.claude/skills/<name>/
   Manifest: updated
   Next: run /promote-artifact --git to push to remote (M6)
```

## Skill Structure

```
skills/promote-artifact/
  SKILL.md        ← skill definition (lives in repo, synced by M3)
```

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Skill dir layout | `skills/validate-artifact/SKILL.md` (M4) | One directory per skill, one SKILL.md inside |
| Validation gate | M4 `/validate-artifact` | Run validate first; abort on FAIL |
| Idempotency | M3 sync.sh | SHA-256 compare before overwrite |
| Manifest update | `manifest.yaml` schema (M2) | Append under correct section key; no duplicate entries |

## Files to Change

| File | Action | Why |
|---|---|---|
| `skills/promote-artifact/SKILL.md` | CREATE | The skill definition |
| `.claude/prds/user-wide-claude-portability.prd.md` | UPDATE M5 row | Mark `in-progress`, add plan path |
| `.claude/plans/portability-loop-runbook.md` | UPDATE M5 row | Mark `done` |

## Tasks

### Task 1: Write `SKILL.md` frontmatter and argument spec

- **Action**: Create `skills/promote-artifact/SKILL.md` with:
  - `name: promote-artifact`
  - `description`: "Validate an artifact and install it locally + into the repo"
  - `trigger`: explicit `/promote-artifact <path>` invocation
  - Arguments: `<path>` (required), `--type skill|command|agent|script` (optional), `--force` (optional)
- **Validate**: Skill definition file parses; skill appears in list.

### Task 2: Write type detection instructions

- **Action**: Write SKILL.md instructions for type auto-detection using the heuristic table above. If ambiguous, instruct Claude to ask the user before proceeding.
- **Validate**: Test with a skill directory (has SKILL.md) → detected as `skill`; `.sh` file → detected as `script`.

### Task 3: Write validation gate instructions

- **Action**: Instruct the skill to call `/validate-artifact <path>` before any copy operations. Define abort/prompt/continue behavior based on FAIL/WARN/PASS verdict.
- **Mirror**: M4 plan overall verdict determines gate behavior.
- **Validate**: Point promote at a file with `/home/alfredo/` → must abort before any file is copied.

### Task 4: Write copy instructions (repo + local)

- **Action**: Write instructions to:
  1. Derive repo dest: `<REPO_ROOT>/<type>s/<artifact-name>` — resolved via `$CLAUDE_PROJECT_DIR` env var (primary) or `git rev-parse --show-toplevel` (fallback)
  2. Derive local dest: `$HOME/.claude/<type>s/<artifact-name>`
  3. Copy with SHA-256 idempotency check (skip if identical, prompt/force if different)
  4. Use `cp -rp` for directories; `cp -p` for single files
- **Validate**: Promote a test skill; verify it appears in both `skills/` and `~/.claude/skills/`.

### Task 5: Write manifest update instructions

- **Action**: Instruct the skill to read `manifest.yaml`, check if the artifact is already listed under its section, and if not, append a new entry using python3 inline YAML manipulation with `yaml.dump(d, default_flow_style=False, sort_keys=False)` to preserve structure.
- **Mirror**: M2 manifest schema — same field names (`name`, `executable` for scripts).
- **Validate**: Promote a new skill; check `manifest.yaml` contains the new entry under `skills:`.

### Task 6: Write summary output and next-step hint

- **Action**: After all operations, print a structured summary (artifact name, type, repo path, local path, manifest status, `Next: /promote-artifact --git` hint for M6).
- **Validate**: Output is human-readable and includes M6 hint.

## Validation

```bash
# Setup: create a test skill in /tmp
mkdir -p /tmp/test-skill
cat > /tmp/test-skill/SKILL.md <<'EOF'
---
name: test-skill
description: A test skill
trigger: When user says /test-skill
---
Do the test thing.
EOF

# Promote it (local only)
/promote-artifact /tmp/test-skill --type skill

# Verify both destinations
ls skills/test-skill/SKILL.md
ls ~/.claude/skills/test-skill/SKILL.md

# Verify manifest
python3 -c "import yaml; d=yaml.safe_load(open('manifest.yaml')); print([s for s in d['skills'] if s.get('name','') == 'test-skill'])"

# Cleanup
rm -rf skills/test-skill ~/.claude/skills/test-skill
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| REPO_ROOT detection fails in a worktree | Medium | Use `$CLAUDE_PROJECT_DIR` env var as primary; `git rev-parse` as fallback |
| `yaml.dump()` reorders manifest entries | Medium | Use `sort_keys=False` and `default_flow_style=False` to preserve structure |
| Artifact name collision with existing repo artifact | Low | SHA-256 compare before overwrite; prompt user |
| CLAUDE.md not a promotable type | N/A | CLAUDE.md not a target for promote; sync.sh handles it |

## Acceptance

- [ ] `skills/promote-artifact/SKILL.md` exists in repo
- [ ] `/promote-artifact <clean-artifact>` copies to both repo and `~/.claude/`
- [ ] `/promote-artifact <failing-artifact>` aborts before any copy
- [ ] `manifest.yaml` is updated with the new artifact entry after promote
- [ ] Second promote of same artifact (identical) reports skip (idempotent)
- [ ] PRD M5 row updated to `in-progress` with plan path
