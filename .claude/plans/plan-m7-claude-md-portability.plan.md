# Plan: M7 — CLAUDE.md Portability

**Source PRD**: `.claude/prds/user-wide-claude-portability.prd.md`
**Selected Milestone**: M7 — CLAUDE.md portability
**Complexity**: Medium

## Summary

Promote the live global `~/.claude/CLAUDE.md` into the repo as `.claude/CLAUDE.md` (the source of truth `sync.sh` already expects), flip `manifest.yaml`'s `claude_md.portable` to `true`, and teach `/promote-artifact` to treat `claude_md` as a first-class artifact type — a singleton file, not a `name`d collection like skills/commands/agents/scripts — so future edits to the global CLAUDE.md can be re-promoted through the same validated pipeline. `/validate-artifact` needs no code change: its grep checks are already file-type-agnostic.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Idempotency / install | `sync.sh:417-423` | `install_file` already wired for `claude_md`; only the `portable` flag and missing source file block it today |
| Validation gate | `.claude/skills/validate-artifact/SKILL.md:26-42` | Static grep for `/home/`, `/Users/`, username, secret patterns; `# validate-artifact: ignore-line` exempts a matched line |
| Ignore-line convention | `.claude/skills/validate-artifact/SKILL.md:31,33` | Same file already uses this marker for its own illustrative `/home/` references |
| Type detection heuristics | `.claude/skills/promote-artifact/SKILL.md:33-43` | Ordered heuristic table; first match wins |
| Manifest update (list-style) | `.claude/skills/promote-artifact/SKILL.md:76-101` | Append-if-absent under a list section, `yaml.dump(..., sort_keys=False)` |

## Files to Change

| File | Action | Why |
|---|---|---|
| `.claude/CLAUDE.md` | CREATE | Repo copy of the live global CLAUDE.md — the source `sync.sh` installs from |
| `manifest.yaml` | UPDATE | Flip `claude_md.portable: false` → `true` |
| `.claude/skills/promote-artifact/SKILL.md` | UPDATE | Add `claude_md` type detection, singleton destination resolution, scalar manifest update, git-pipeline path handling |
| `.claude/prds/user-wide-claude-portability.prd.md` | UPDATE (auto, by `/plan`) | Milestone 7 row → `in-progress`, `Plan` cell → this file |

`.claude/skills/validate-artifact/SKILL.md` is **not** changed — its checks are already generic to any file path, `claude_md` included.

## Tasks

### Task 1: Seed `.claude/CLAUDE.md` from the live global file

- **Action**: Copy `~/.claude/CLAUDE.md` to `.claude/CLAUDE.md`. In the copy only (not the live file), append `<!-- validate-artifact: ignore-line -->` to the two lines that legitimately match the `/home/` grep so validation passes without weakening the check:
  - the illustrative "Incorrect forms" example line (`cd /home/user/project/...`)
  - the `Default KB path` rule line (`/home/alfredo/knowledge-base/`) — a personal path accepted per the PRD's resolved open question (same user, own machines)
- **Mirror**: `.claude/skills/validate-artifact/SKILL.md:31,33` — same marker, same reasoning (deliberate, reviewed exception vs. real leak).
- **Validate**: `grep -n "/home/" .claude/CLAUDE.md` shows both lines carry the marker; running validate-artifact's Step 1 grep and filtering lines containing the marker leaves zero unexempted matches.

### Task 2: Flip the manifest flag

- **Action**: Edit `manifest.yaml`, change `claude_md:\n  portable: false` to `portable: true`. Direct text edit, not a full YAML re-dump — this is a single scalar flip and a re-dump risks reordering the rest of the file.
- **Validate**: `python3 -c "import yaml; print(yaml.safe_load(open('manifest.yaml'))['claude_md']['portable'])"` → `True`.

### Task 3: Add `claude_md` type detection to `/promote-artifact`

- **Action**: In the Step 1 heuristic table, add a row **before** the generic "`.md` file → `agent`" row: "`<path>` basename is `CLAUDE.md` → type `claude_md`". Ordering matters — without it every CLAUDE.md promotion would misclassify as `agent`.
- **Validate**: Manually trace `/promote-artifact ~/.claude/CLAUDE.md` through the table → resolves to `claude_md`, not `agent`.

### Task 4: Add singleton destination handling

- **Action**: In Step 3 ("Determine destinations"), add an explicit exception: for `type == claude_md`, `repo dest = <repo_root>/.claude/CLAUDE.md` and `local dest = $HOME/.claude/CLAUDE.md` — no pluralized `<type>s/` directory, no `<artifact-name>` segment, since CLAUDE.md is a singleton, not a named collection member.
- **Mirror**: Same repo-root resolution (`$CLAUDE_PROJECT_DIR` primary, `git rev-parse --show-toplevel` fallback) as every other type — only the path shape changes.
- **Validate**: Manually trace the same invocation → repo dest and local dest resolve to the two literal `CLAUDE.md` paths, not `claude_mds/CLAUDE.md`.

### Task 5: Add scalar manifest update for `claude_md`

- **Action**: In Step 5 ("Update manifest.yaml"), branch on type: existing list-append logic stays for `skill|command|agent|script`; for `claude_md`, instead set `d['claude_md']['portable'] = True` (idempotent — no-op if already `true`) rather than appending to a list section.
- **Mirror**: Same `yaml.dump(d, default_flow_style=False, sort_keys=False)` write-back to preserve manifest structure.
- **Validate**: Promote flow on an already-portable CLAUDE.md reports "Manifest: already portable" and makes no file change (idempotent).

### Task 6: Handle the `--git` pipeline's path templates for `claude_md`

- **Action**: In the Git Pipeline section (branch/commit/PR body), the `git add .claude/<type>s/<artifact-name>` line and PR body's "Manifest entry added" section assume the list-style shape. Add a `claude_md` branch: `git add .claude/CLAUDE.md manifest.yaml`, and PR body reports "Manifest: `claude_md.portable` set to `true`" instead of a `name:` list entry.
- **Validate**: Manually trace `/promote-artifact ~/.claude/CLAUDE.md --git` → branch name `promote/claude_md/CLAUDE.md`, commit adds exactly the two files, PR body reflects the scalar flag change.

## Validation

```bash
# Repo-agnostic check on the new repo copy (manual equivalent of validate-artifact Step 1)
grep -n "/home/" .claude/CLAUDE.md | grep -v "validate-artifact: ignore-line"   # expect: no output
grep -n "/Users/" .claude/CLAUDE.md                                            # expect: no output
grep -Ein "sk-[A-Za-z0-9]+|ghp_[A-Za-z0-9]+|xoxb-[A-Za-z0-9-]+" .claude/CLAUDE.md  # expect: no output

# Manifest flag flipped
python3 -c "import yaml; print(yaml.safe_load(open('manifest.yaml'))['claude_md']['portable'])"  # expect: True

# sync.sh now installs CLAUDE.md instead of skipping it
bash sync.sh --dry-run 2>&1 | grep -A2 "claude_md"   # expect [OK] or [MISSING]/[STALE], never "(portable: false)"
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Ignore-line markers drift out of sync if the live CLAUDE.md is re-promoted with new `/home/` content later | Medium | Re-run Task 1's grep+marker step on every future re-promotion, not just this one-time seed |
| `claude_md` singleton shape breaks assumptions in shared promote-artifact code (list section, `<artifact-name>`) | Medium | Explicit type branch at each step (3, 5, 6) rather than trying to force it through the generic list path |
| Live `~/.claude/CLAUDE.md` diverges from repo copy after this seed (edited locally without re-promoting) | High (ongoing) | Out of scope for M7 itself — drift detection is PRD risk "Repo drifts from actual `~/.claude/` state", mitigated by periodic `sync.sh --dry-run` per the PRD |

## Acceptance

- [ ] `.claude/CLAUDE.md` exists in repo, byte-identical to `~/.claude/CLAUDE.md` except for the two added ignore-line markers
- [ ] `manifest.yaml`'s `claude_md.portable` is `true`
- [ ] `/promote-artifact ~/.claude/CLAUDE.md` classifies as type `claude_md`, not `agent`
- [ ] `/promote-artifact ~/.claude/CLAUDE.md --git` produces a correct branch/commit/PR without list-section manifest logic misfiring
- [ ] `bash sync.sh --dry-run` no longer reports `[SKIP] CLAUDE.md (portable: false)`
- [ ] PRD M7 row updated to `in-progress` with this plan path
