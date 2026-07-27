---
name: gh-pr-update
description: >
  Updates the current branch's GitHub PR title and body so they accurately reflect every
  change introduced since branching from develop. Use proactively whenever the PR metadata
  seems stale, incomplete, or doesn't match what was actually implemented — even if the user
  doesn't say "PR" explicitly. Triggers on: "update my PR", "fix the PR description",
  "PR summary is wrong", "refresh PR", "PR title is misleading", "summarize my changes for
  the PR", "the description doesn't reflect what I built", or any time you notice a mismatch
  between PR metadata and the actual implementation. Pass --install to install and authenticate
  the gh CLI and register it as the default PR update tool. Pass --dry-run (or -du) to
  preview the generated title and body without applying anything.
args:
  - name: pr-number
    description: PR number to update. Defaults to the open PR for the current branch.
    required: false
  - name: --dry-run / -du
    description: Generate and display the title + body only; do not call gh pr edit.
    required: false
  - name: --install
    description: Install the gh CLI via the system package manager and authenticate it.
    required: false
  - name: --force
    description: Skip the confirmation prompt before applying changes.
    required: false
---

# gh-pr-update

Two-phase workflow: **Phase 1** analyses the branch and writes a generated title + body to
a temp file. **Phase 2** reads that file and calls `gh pr edit` as an isolated shell
invocation. `--dry-run` / `-du` stops after Phase 1.

## Invocation

```
/gh-pr-update [pr-number] [--dry-run|-du] [--install] [--force]
```

---

## Pre-flight: tool detection

Before doing anything else, confirm `gh` is available and authenticated:

```bash
command -v gh >/dev/null 2>&1 \
  || { echo "ERROR: gh CLI not found. Run /gh-pr-update --install to install it."; exit 1; }
gh auth status >/dev/null 2>&1 \
  || { echo "ERROR: gh not authenticated. Run: gh auth login"; exit 1; }
```

If `--install` was passed, run the install flow first (see below), then continue.

---

## --install flow

Detect the system package manager and install `gh`, then authenticate:

```bash
if command -v brew &>/dev/null; then
  brew install gh
elif command -v apt-get &>/dev/null; then
  type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) \
    signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt update && sudo apt install gh -y
elif command -v snap &>/dev/null; then
  sudo snap install gh
else
  echo "ERROR: no supported package manager found (brew / apt / snap)."
  echo "Install gh manually: https://cli.github.com"
  exit 1
fi
gh auth login
```

After install, continue with Step 1.

---

## Phase 1: Generate

Gather context, analyse the diff, write output to a temp file.

```bash
BRANCH=$(git branch --show-current)
BASE="develop"
TMPFILE="/tmp/gh-pr-update-$(echo "$BRANCH" | tr '/' '-').md"

git log "$BASE".."$BRANCH" --oneline
git diff "$BASE"..."$BRANCH" --stat
git diff "$BASE"..."$BRANCH"
gh pr view --json number,title,body,url,state 2>/dev/null
```

If the branch is identical to `develop` (no commits), warn and stop.

If no open PR is found:
- Ask: *"No open PR found. Create one? [y/N]"*
- `y` → use `gh pr create` with generated content (targeting `develop`)
- `n` → stop

**Analyse the diff** — read actual code changes, not just commit messages. Apply these rules:

*Title:* conventional commit `type(scope): description`, under 72 chars, dominant type wins
(`feat`, `fix`, `refactor`, `docs`, `chore`, `test`).

*Body:* cover every meaningful change; no boilerplate; reviewer with no prior context must
understand what changed and why.

**Write to temp file** — format: title on line 1, blank line 2, body from line 3:

```
fix(auth): add RWMutex to session map

## Summary
- ...
```

```bash
printf '%s\n\n%s\n' "$TITLE" "$BODY" > "$TMPFILE"
```

**If `--dry-run` / `-du`:** print the temp file contents and stop. Do not proceed to Phase 2.

```bash
echo "--- dry run: $TMPFILE ---"
cat "$TMPFILE"
```

---

## Phase 2: Apply (isolated call)

Read title and body from the temp file and call `gh pr edit` as a single isolated
shell invocation. No analysis happens here — Phase 2 only consumes the file Phase 1 wrote.

Show the user the proposed title and body, then ask: *"Apply this update? [Y/n]"*
Skip the prompt if `--force` was passed.

```bash
TITLE=$(head -1 "$TMPFILE")
BODY=$(tail -n +3 "$TMPFILE")

gh pr edit [NUMBER] --title "$TITLE" --body "$BODY"
```

Append the result (PR URL or error) to `$TMPFILE` as a trailing comment so both phases
share the same audit record:

```bash
echo "" >> "$TMPFILE"
echo "<!-- applied: $(gh pr view --json url -q .url) -->" >> "$TMPFILE"
```

After success, print the PR URL.

---

## Error reference

| Situation | Response |
|---|---|
| Not in a git repo | Error: *"Not in a git repo"* |
| `gh` not found | Error with `--install` hint |
| Not authenticated | Error: *"Run gh auth login"* |
| No commits vs `develop` | Warn: *"Branch identical to develop — nothing to summarize"* |
| PR already merged/closed | Warn and ask for explicit PR number |
| Ambiguous PR (multiple open) | List them and ask which to update |
