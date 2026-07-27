---
name: gh-issue-create
description: Create a GitHub issue with template enforcement, dual-agent draft review (mechanical + judgment), and MCP/gh-CLI fallback. Run --install once per repo to bootstrap prerequisites.
triggers:
  - /gh-issue-create
args:
  - name: body
    description: Issue content. Omit to infer from conversation context.
    required: false
  - name: title
    description: Issue title. Derived from body/topic if omitted.
    required: false
  - name: repo
    description: "Target repo as owner/name. Defaults to current git remote."
    required: false
  - name: --install
    description: Install bundled templates and rules into the current project, then auto-register this skill as the default issue creation tool.
    required: false
---

# gh-issue-create

Creates a GitHub issue through a **draft → review → publish** pipeline.
Enforces template usage and KISS/SRP/YAGNI/DRY rules before submitting.

## Invocation

```
/gh-issue-create [--body "..."] [--title "..."] [--repo owner/name]
/gh-issue-create --install
```

---

## `--install` Mode

Run once per repo. Steps execute in order; stop and report `✗` on any failure.

**1. Templates** — copy bundled templates to `.github/ISSUE_TEMPLATE/`:
- Source: `~/.claude/skills/gh-issue-create/bundled/templates/` (Read each `.yml` file)
- Dest: `.github/ISSUE_TEMPLATE/<filename>` (create dir if absent)
- Skip a file if it already exists and content is identical.

**2. Rules** — copy bundled rules:
- Source: `~/.claude/skills/gh-issue-create/bundled/rules/gh-issue-rules.md`
- Dest: `.claude/rules/gh-issue-rules.md` (create `.claude/rules/` if absent)
- Skip if identical.

**3. Auto-register** — append to the project's `CLAUDE.md`:
```
## GitHub Issue Creation
Always use `/gh-issue-create` when opening GitHub issues. Never run `gh issue create` directly.
```
Skip if the heading `## GitHub Issue Creation` already exists in `CLAUDE.md`.

**4. gh CLI check** — run `which gh`; if not found, print:
```
⚠ gh CLI not installed. Install from https://cli.github.com
  MCP must be connected as the only available fallback.
```

Report on completion:
```
✓ install complete
  Templates: N installed, M skipped
  Rules: installed | skipped
  CLAUDE.md: updated | already registered
```

---

## Issue Creation Mode

### Step 1 — Pre-flight checks

Abort with the specified error if either check fails:

| Check | Pass condition | Error message |
|---|---|---|
| Templates exist | At least one `.yml` in `.github/ISSUE_TEMPLATE/` | "No issue templates found. Run `/gh-issue-create --install` or add templates to `.github/ISSUE_TEMPLATE/`." |
| Rules exist | `.claude/rules/gh-issue-rules.md` is present | "No gh-issue rules found. Run `/gh-issue-create --install`." |

### Step 2 — Parse content

- `--body` provided → use it.
- Otherwise → scan the last 10 conversation turns for actionable topics (bugs, features, tasks, chores).
- **One topic found** → proceed.
- **Multiple topics found** → output:
  ```
  Multiple topics detected — one issue per topic (SRP).

  1. [topic A]
  2. [topic B]
  ...

  Create separate issues? Reply with y (all), n (cancel), or numbers e.g. "1 3".
  ```
  Wait for user reply. Proceed with each confirmed topic as a separate issue (loop steps 3–6).

### Step 3 — Select template

1. List all `.github/ISSUE_TEMPLATE/*.yml` files; read the `name:` field from each.
2. Match topic by keyword heuristic:
   - "bug", "error", "crash", "fail", "broken" → bug template
   - "feature", "add", "support", "request", "allow" → feature template
   - "chore", "refactor", "clean", "update", "task", "remove", "migrate" → chore template
3. If no confident match or multiple candidates, prompt:
   ```
   Which template?
   1. [template names listed]
   >
   ```

### Step 4 — Draft

1. Compose a draft filling every field of the selected template.
2. Derive `title` from `--title` arg, or from the topic (imperative mood, ≤ 72 chars).
3. Write draft to a temp file using the Write tool (path: session scratchpad, filename `gh-issue-draft.md`).
   Format:
   ```markdown
   # {title}

   <!-- template: {template filename} -->

   {filled template body using Markdown}
   ```

### Step 5 — Review

Spawn two agents in parallel. Pass each agent the full draft content and the contents of `.claude/rules/gh-issue-rules.md`.

**Agent A — Mechanical review** prompt:
> "Review this GitHub issue draft for structural compliance. Check: (1) all required template fields are filled with real content (not placeholder text), (2) title is imperative mood and ≤ 72 chars, (3) title does not duplicate the template name, (4) no `<!-- ... -->` placeholder comments remain, (5) no empty sections. Return JSON array: [{\"severity\":\"HIGH\"|\"MEDIUM\"|\"LOW\",\"field\":\"...\",\"finding\":\"...\",\"fix\":\"...\"}]"

**Agent B — Judgment review** prompt:
> "Review this GitHub issue draft against the provided rules (KISS/SRP/YAGNI/DRY). Check: (1) exactly one topic (SRP), (2) no speculative scope or 'while we're at it' additions (YAGNI), (3) no repeated information already in the template description (DRY), (4) minimal prose — every sentence earns its place (KISS). Return JSON array: [{\"severity\":\"HIGH\"|\"MEDIUM\"|\"LOW\",\"principle\":\"...\",\"finding\":\"...\",\"fix\":\"...\"}]"

**After both complete:**
- Discard all LOW findings.
- For each MEDIUM and HIGH finding: apply `fix` to the draft (update the temp file).
- Output:
  ```
  Review: N finding(s) fixed (H HIGH, M MEDIUM). L LOW finding(s) dismissed.
  ```

### Step 6 — Create

**Resolve target repo:**
- `--repo` provided → use it.
- Otherwise → `git remote get-url origin` and parse `owner/repo` from the URL (strip `.git`, handle both HTTPS and SSH forms).

**Tool resolution — use first that works:**

1. **MCP** — if `mcp__github__create_issue` is available in this session:
   ```
   mcp__github__create_issue(owner, repo, title, body, labels=[label from template])
   ```

2. **gh CLI** — otherwise:
   ```bash
   gh issue create --title "{title}" --body-file {draft_path} --repo "{owner/repo}"
   ```

On success:
```
✓ Issue created: {url}
```
On failure: report the error verbatim and stop.

---

## Bundled Asset Paths

| Asset | Path (installed) |
|---|---|
| Bug template | `~/.claude/skills/gh-issue-create/bundled/templates/bug.yml` |
| Feature template | `~/.claude/skills/gh-issue-create/bundled/templates/feature.yml` |
| Chore template | `~/.claude/skills/gh-issue-create/bundled/templates/chore.yml` |
| Rules | `~/.claude/skills/gh-issue-create/bundled/rules/gh-issue-rules.md` |

When running from the worktree (not yet synced), substitute `~/.claude/` with the worktree root's `.claude/skills/gh-issue-create/bundled/`.
