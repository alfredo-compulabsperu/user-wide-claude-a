# Plan: Autonomous GitHub Issue Worker

**Issue**: #12 — "As a system I would like to automatically work on issues"
**Complexity**: Small
**Research**: `research/gh-issue-automation/tool-survey.md` (v1.1)

## Summary

Add `.github/workflows/claude.yml` using `anthropic/claude-code-action` triggered by `issues: types: [opened]`. Claude receives a triage prompt, checks blocking relationships, assesses completeness, posts a structured comment, and applies one of three labels (`ready`, `blocked`, `needs-info`). All write operations are scoped to what the GitHub Actions token permits — no additional safety-guard bypass needed because the workflow itself is the safety gate (human-authored workflow YAML = deliberate authorization).

## Pre-flight (human actions — gate before implementation)

- [ ] Add `ANTHROPIC_API_KEY` to repo secrets: Settings → Secrets and variables → Actions → New repository secret

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Naming | `.claude/scripts/open-gh-issue.sh` | kebab-case filenames, verb-noun |
| Error handling | `.claude/tests/scripts/open-gh-issue.test.sh:7` | `set -euo pipefail`; explicit exit codes |
| Tests | `.claude/tests/scripts/open-gh-issue.test.sh` | Custom `run_test` harness; mock binaries in `$MOCK_BIN` |
| Skills | `.claude/skills/promote-artifact/SKILL.md` | SKILL.md frontmatter: `name`, `description`, `triggers`, `args` |
| No GH Actions precedent | — | Net-new; no existing `.github/` directory to mirror |

## Files to Change

| File | Action | Why |
|---|---|---|
| `.github/workflows/claude.yml` | CREATE | Main workflow — trigger, permissions, claude-code-action invocation |
| `.github/prompts/issue-triage.md` | CREATE | Triage prompt injected into claude-code-action; separated from workflow YAML for readability |

`manifest.yaml` and `.claude/` — **do not touch**. GitHub Actions workflows are not synced artifacts.

## Tasks

### Task 1 — Create triage prompt

**File:** `.github/prompts/issue-triage.md`

Content contract:
- Instructs Claude to use `gh issue list` to check for blocking relationships
- Defines structured comment template: Triage / Blocking-Blocked-by / Assessment / Next step sections
- Label rules: `ready` (self-contained, no blockers), `blocked` (blocked by open issue), `needs-info` (insufficient detail)
- Write ordering: post comment first (observable), then apply label — never reverse

**Validate:** `cat .github/prompts/issue-triage.md` confirms all AC items addressed

### Task 2 — Create workflow

**File:** `.github/workflows/claude.yml`

```yaml
on:
  issues:
    types: [opened]

permissions:
  contents: read
  issues: write
  pull-requests: write

jobs:
  triage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: anthropics/claude-code-action@v1
        with:
          prompt_file: .github/prompts/issue-triage.md
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

- Pin to `@v1`, not `@main`
- Do not set `label_trigger` — bug #210; using `opened` event directly
- `issues: write` required for comment + label

**Validate:** `gh workflow list --repo alfredo-compulabsperu/user-wide-claude-a` shows `claude.yml`

### Task 3 — Create labels

```bash
gh label create ready      --repo alfredo-compulabsperu/user-wide-claude-a --color 0e8a16 --description "Issue is self-contained and ready to work"
gh label create blocked    --repo alfredo-compulabsperu/user-wide-claude-a --color d93f0b --description "Blocked by another open issue"
gh label create needs-info --repo alfredo-compulabsperu/user-wide-claude-a --color e4e669 --description "Author needs to provide more information"
```

**Validate:** `gh label list --repo alfredo-compulabsperu/user-wide-claude-a | grep -E 'ready|blocked|needs-info'`

### Task 4 — Smoke test

```bash
gh issue create \
  --repo alfredo-compulabsperu/user-wide-claude-a \
  --title "test: smoke test autonomous triage worker" \
  --body "This is a self-contained test issue. No blockers. Expected label: ready."
```

**Validate:**
- Workflow run appears in Actions tab within 30 seconds
- Claude posts a triage comment on the issue
- Label `ready` is applied

## Validation

```bash
gh workflow list --repo alfredo-compulabsperu/user-wide-claude-a
gh label list --repo alfredo-compulabsperu/user-wide-claude-a | grep -E 'ready|blocked|needs-info'
gh issue view <N> --repo alfredo-compulabsperu/user-wide-claude-a --json labels,comments
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `claude-code-action` version API changes | Low | Pin to `@v1`, not `@main` |
| Claude applies wrong label or posts no comment | Medium | Prompt explicit about comment-first ordering; smoke test catches this |
| Triage fires on every issue including noise | Medium | Acceptable for single-dev repo; add `if:` condition later if needed |
| `ANTHROPIC_API_KEY` secret not set | High pre-flight | Pre-flight gate; workflow fails with clear error |

## Acceptance

- [ ] Pre-flight complete (secret added)
- [ ] `.github/workflows/claude.yml` created and pushed
- [ ] `.github/prompts/issue-triage.md` created and pushed
- [ ] Labels `ready`, `blocked`, `needs-info` exist in repo
- [ ] Smoke test issue receives triage comment and correct label

### Issue #12 AC checklist

- [ ] Triggers on `issues: [opened]` GH event
- [ ] Checks if issue is blocked by another open issue
- [ ] Checks if issue blocks other open issues
- [ ] Checks if issue is self-contained (enough info to act)
- [ ] Checks if issue requires more information (prompts author)
- [ ] Posts structured triage comment with findings
- [ ] Applies appropriate label (`ready`, `blocked`, `needs-info`)
- [ ] Write operations gated (comment before label)
