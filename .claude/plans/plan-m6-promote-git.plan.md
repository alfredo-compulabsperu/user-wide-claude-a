# Plan: M6 — `/promote-artifact` Git Pipeline

**Source PRD**: `.claude/prds/user-wide-claude-portability.prd.md`
**Selected Milestone**: M6 — `/promote-artifact` git pipeline
**Complexity**: Medium

## Summary

Extend the M5 `promote-artifact` skill with a `--git` flag that, after local installation, branches the repo, commits the new artifact and manifest update, pushes to remote, creates a PR via `gh`, and squash-merges it. No auto-review, no auto-fix. Requires `git` and `gh` CLI; fails gracefully with a clear message if either is absent or unauthenticated.

## PR Convention

| Field | Convention | Example |
|---|---|---|
| Branch | `promote/<type>/<artifact-name>` | `promote/skill/my-custom-skill` |
| PR title | `promote(<type>): <artifact-name>` | `promote(skill): my-custom-skill` |
| Merge strategy | Squash merge | `gh pr merge --squash --delete-branch --yes` |

### PR Body Template

```
## Promoted artifact

- **Type**: skill
- **Name**: my-custom-skill
- **Source machine**: user@hostname
- **Promoted at**: YYYY-MM-DD

## Validation

[PASS] Repo-agnostic
[PASS] Dependency-complete
[PASS] Terse (9/10)
Overall: PASS

## Manifest entry added

- name: my-custom-skill

Promoted via `/promote-artifact --git`
```

## Git Pipeline Flow

```
/promote-artifact <path> --git [--type ...] [--force]

1-7. Same as M5 local promote (validate, copy to repo + local, update manifest)
8.  Preflight: verify git + gh available and gh authenticated
9.  Verify working tree has unstaged changes from steps 1-7
10. Create branch: git checkout -b promote/<type>/<artifact-name>
11. Stage: git add <type>s/<artifact-name> manifest.yaml
12. Commit: git commit -m "promote(<type>): <artifact-name>"
13. Push: git push -u origin promote/<type>/<artifact-name>
14. PR create: gh pr create --title "..." --body "..."
15. Squash merge: gh pr merge --squash --delete-branch --yes
16. Return to main: git checkout main && git pull origin main
17. Print summary: branch (deleted), PR #N, local ✓, repo (on main) ✓
```

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Skill dir layout | `skills/promote-artifact/SKILL.md` (M5) | Extend existing M5 SKILL.md — `--git` adds pipeline |
| Branch naming | Git convention | `promote/<type>/<artifact-name>` — lowercase, kebab-case |
| Commit message | Conventional commits | `promote(<type>): <artifact-name>` |
| PR creation | `gh pr create` | `--title`, `--body` heredoc, `--base main` |
| Squash merge | PRD resolution | `gh pr merge --squash --delete-branch --yes` |

## Files to Change

| File | Action | Why |
|---|---|---|
| `skills/promote-artifact/SKILL.md` | UPDATE (extend M5) | Add `--git` flag documentation and pipeline instructions |
| `.claude/prds/user-wide-claude-portability.prd.md` | UPDATE M6 row | Mark `in-progress`, add plan path |
| `.claude/plans/portability-loop-runbook.md` | UPDATE M6 row | Mark `done` |

## Tasks

### Task 1: Add `--git` flag to SKILL.md argument spec

- **Action**: Edit `skills/promote-artifact/SKILL.md` to add `--git` as an optional flag. Document: without `--git` = M5 local-only; with `--git` = full pipeline (steps 8-17).
- **Validate**: Skill definition parses; help text mentions `--git`.

### Task 2: Write git preflight check instructions

- **Action**: Add instructions for step 8:
  ```
  command -v git || ERROR "git not found"
  command -v gh  || ERROR "gh not found — install GitHub CLI"
  gh auth status || ERROR "gh not authenticated — run: gh auth login"
  git remote get-url origin || ERROR "no remote configured on this repo"
  ```
  These checks run AFTER M5 local steps complete. M5 results are not rolled back if git pipeline fails.
- **Validate**: Remove `gh` from PATH → error message, M5 install already done → no dirty state.

### Task 3: Write branch creation and commit instructions

- **Action**: Write instructions for steps 10-12:
  - `git checkout -b promote/<type>/<artifact-name>`
  - `git add <type>s/<artifact-name> manifest.yaml`
  - `git commit -m "promote(<type>): <artifact-name>"`
- **Mirror**: Conventional commits.
- **Validate**: `git log --oneline -1` shows `promote(skill): <name>` after promote.

### Task 4: Write push and PR creation instructions

- **Action**: Write instructions for steps 13-14:
  - `git push -u origin promote/<type>/<artifact-name>`
  - `gh pr create --title "promote(<type>): <artifact-name>" --body "$(cat <<'EOF'...PR body template...EOF)" --base main`
  - Capture PR URL for summary output
- **Validate**: PR visible in GitHub with correct title and body.

### Task 5: Write squash merge and cleanup instructions

- **Action**: Write instructions for steps 15-16:
  - `gh pr merge --squash --delete-branch --yes`
  - `git checkout main && git pull origin main`
- **Mirror**: Squash merge (PRD-resolved).
- **Validate**: After merge, `git log --oneline -3` on main shows squash commit; promote branch absent on remote.

### Task 6: Write final summary output

- **Action**: Print: branch name (deleted), PR #N with URL, local path ✓, repo path on main ✓. If `--git` was not used, remind user: "Run `/promote-artifact --git` to push to remote."
- **Validate**: Summary clearly distinguishes local-only from git-backed promote.

## Validation

```bash
# Full promote with git pipeline (using a test artifact)
mkdir -p /tmp/test-git-skill
cat > /tmp/test-git-skill/SKILL.md <<'EOF'
---
name: test-git-skill
description: Test git pipeline skill
trigger: When user says /test-git-skill
---
Do the test thing.
EOF

/promote-artifact /tmp/test-git-skill --type skill --git

# Verify on main after merge
git log --oneline -3              # shows: promote(skill): test-git-skill
ls skills/test-git-skill/         # repo copy on main
grep test-git-skill manifest.yaml # manifest entry present
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `gh pr merge --yes` merges without human review | By design | PRD explicitly out-scopes auto-review; solo developer, no team |
| Remote `main` diverged since M5 started | Low | `git pull --ff-only origin main` before branch creation; fail if behind |
| `gh` auth expires mid-pipeline | Low | `gh auth status` preflight before any git ops |
| No remote configured (fresh clone with no push access) | Low | `git remote get-url origin` check in preflight |
| Squash merge leaves local main behind | Handled | `git pull origin main` after merge resyncs local |

## Acceptance

- [ ] `skills/promote-artifact/SKILL.md` updated with `--git` flag docs and pipeline steps
- [ ] `/promote-artifact <clean-artifact> --git` creates branch, PR, squash-merges, returns to main
- [ ] PR title: `promote(<type>): <artifact-name>`
- [ ] PR body contains validation summary and machine info
- [ ] Without `--git`, behavior is unchanged M5 local-only
- [ ] Missing/unauthenticated `gh` → clear error, no dirty git state
- [ ] PRD M6 row updated to `in-progress` with plan path
