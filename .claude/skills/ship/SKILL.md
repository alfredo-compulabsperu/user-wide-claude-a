---
name: ship
description: 'Drives the current branch through commit → push → PR create/update (regenerated summary) → optional review → merge → delete (remote+local), one shot. Trigger on: "ship it", "ship this branch", "commit push PR merge and delete the branch", "wrap this up and merge", "finish this off", "get this merged", or any partial-chain ask that explicitly names merge/finish (e.g. "push this and merge it"). `--review` gates merge on PR review; `--admin` bypasses branch-protection/approval blocks. Skip for: reviewing a PR without merging (use the review skill), authoring a PR body only, a plain `git commit` with no push/merge intent, or "commit push and open a PR"-style asks that name only commit/push/PR — those stop at the PR, not merge+delete; do them directly, not via this skill.'
---

# ship

```
commit → push → create/update PR → [review PR] → merge → delete branch (remote + local)
```

One command, one branch, fully autonomous — no confirmation prompts. Stops only on: a
failed safety check, blocking `--review` findings, or a merge the platform refuses
(unless `--admin` was passed).

## Flags

- `--review` — gate merge on PR review; blocking findings stop before merge, PR stays open. Omit to skip review and merge directly.
- `--admin` — if merge is blocked by branch protection or an approval this account can't self-supply, retry with `gh pr merge --admin` to bypass it. Explicit opt-in only — omit to always stop and report on such blocks instead. Does not affect real merge conflicts, which always stop regardless.
- `--base <branch>` — override PR base (default: repo's GitHub default branch).
- `--squash` | `--merge` | `--rebase` — force merge strategy (default: first the repo allows).
- Remaining free text → commit-message hint (e.g. `ship "wire up retry backoff"`).

## Delegate to the harness

Resolve each step in order: whatever the installed harness  
 mandates, then this skill's own inner default.

- Commit → a tool mandated by `CLAUDE.md`/`.claude/rules/*.md` or the available-skills/commands list (if any) → else inner default: raw `git`.
- Push+PR → a tool mandated by the same sources (if any) → else inner default: raw `git`/`gh`.
- Review (`--review`) → a review mechanism mandated by the same sources (if any) → else inner default: `/code-review` the PR diff, and confirm the PR's acceptance criteria (if any) are met.

Check the available-skills/commands list and repo rules first; fall back to each step's inner default only when nothing is mandated.

## Step 0 — Preflight

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated — run: gh auth login"; exit 1; }
BRANCH=$(git symbolic-ref --quiet --short HEAD) || { echo "detached HEAD"; exit 1; }
BASE=${BASE_OVERRIDE:-$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)}
```

Refuse if `BRANCH == BASE`, or branch is a bare `main`/`master`/`develop` not meant as a feature branch — say why and stop.

## Step 1 — Commit

```bash
git status --short
```

- Changes present → commit per "Delegate to the harness" above; the raw-`git` fallback is a conventional-commit message (`feat:`/`fix:`/`chore:`/…, imperative, ≤72 chars) + `git add -A && git commit`.
- Nothing to commit, nothing ahead of `BASE`, nothing unpushed → stop, nothing to ship.
- Nothing to commit but ahead of `BASE` → re-ship of existing commits, continue.

## Step 2 — Push

Resolve per "Delegate to the harness" above. Raw-`git` fallback:

```bash
git push -u origin HEAD
```

Non-fast-forward → fetch, rebase, retry with a lease (never bare `--force`):

```bash
git fetch origin
git rebase origin/"$BRANCH"
git push --force-with-lease
```

Conflicts → stop, report.

## Step 3 — Create/update PR

```bash
gh pr list --head "$BRANCH" --state open --json number,url
```

- Exists → regenerate summary from current commits/diff, `gh pr edit <n> --body "<summary>"` (refresh title if scope changed). Report as *updated*.
- None → resolve per "Delegate to the harness" above; raw-`gh` fallback:

```bash
gh pr create --base "$BASE" --title "<conventional title>" --body "<summary>"
```

Base = `--base` override, else Step 0's resolved default. (Repo-default wins over a hardcoded `develop` — pass `--base develop` explicitly if the repo requires it.)

**Summary body** — the template below is the fallback default only. Before using it, check in order and use whichever resolves first:
1. A mandated PR-creation tool (per "Delegate to the harness") that already applies its own body format — don't double-template.
2. A repo PR template (`.github/PULL_REQUEST_TEMPLATE.md` or `.github/PULL_REQUEST_TEMPLATE/*.md`) — fill that instead.
3. An explicit PR-body format mandated in `CLAUDE.md`/`.claude/rules/*.md` — use that instead.
4. None of the above → use the template below.

```markdown
## Summary
<1–2 sentences>

## Changes
<bullets by area, from commits>

## Files changed
<from `git diff --stat BASE..HEAD`>

## Testing / Validation
<how verified, or "N/A — docs/config only">
```

## Step 4 — Review (`--review` only)

Resolve per "Delegate to the harness" above: a mandated review mechanism wins (it may carry severity gates or comment-posting requirements this skill can't replicate); else run the inner default — `/code-review` the PR diff, and confirm the PR's acceptance criteria (if any) are met.

- Blocking/critical findings → STOP, don't merge, report, leave PR open.
- Clean or non-blocking nits → proceed to merge.

No `--review` → skip entirely.

## Step 5 — Merge

```bash
gh api "repos/{owner}/{repo}" --jq '{squash:.allow_squash_merge,merge:.allow_merge_commit,rebase:.allow_rebase_merge}'
gh pr merge <n> --<strategy> --delete-branch
```

Honor an explicit `--squash`/`--merge`/`--rebase`; else first method the repo allows.

- Real conflicts (not mergeable) → STOP, report, don't force. `--admin` does not apply here.
- Blocked by branch protection / an approval this account can't self-supply:
  - `--admin` passed → retry: `gh pr merge <n> --<strategy> --delete-branch --admin`.
  - `--admin` not passed → STOP, report. Bypassing protections without explicit opt-in is not a default.

## Step 6 — Delete branch + verify

```bash
git switch "$BASE" 2>/dev/null || git checkout "$BASE"
git branch -D "$BRANCH" 2>/dev/null || true
git fetch --prune
git ls-remote --heads origin "$BRANCH"   # both should print nothing
git branch --list "$BRANCH"
```

Checked out in another worktree → report, don't force.

## Step 7 — Report

```
Shipped <branch> → <base>
  commit   <short-hash> <message>  (or "reused N existing commits")
  PR       #<n> <created|updated> <url>
  review   <skipped | clean | BLOCKED — n findings>
  merge    <merge-commit-hash> (<strategy>) [--admin used]
  branches remote deleted ✓  local deleted ✓
```

Stopped early → say exactly which step and what's needed next.

## Failure reference

| Situation | Do |
|---|---|
| Not a git repo / `gh` not authed | Stop at preflight, show fix. |
| On base branch | Stop — nothing to ship. |
| Nothing to commit, nothing ahead | Stop — nothing to ship. |
| Push rejected (non-ff) | Rebase onto `origin/<branch>`, `--force-with-lease`. Conflicts → stop. |
| PR already open | Update, don't duplicate. |
| `--review` blocking findings | Stop before merge, leave PR open, report. |
| `--review`, nothing mandated | Run inner default: `/code-review` the PR diff, confirm acceptance criteria (if any). |
| PR not mergeable (real conflicts) | Stop, report, don't force — `--admin` doesn't apply. |
| Merge needs approval this account lacks | Stop, report — unless `--admin` given, then retry with `--admin`. |
| Local branch checked out elsewhere | Report, don't force-delete. |
