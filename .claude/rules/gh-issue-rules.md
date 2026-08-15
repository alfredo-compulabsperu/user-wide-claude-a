# GitHub Issue Rules

When creating or reviewing a GitHub issue, enforce all four principles.

## KISS — Keep It Simple

- Title: imperative mood, ≤ 72 chars, no filler words ("please", "question about", "help with")
- Body: every sentence must earn its place — cut prose padding
- Reproduction steps: minimal — strip anything that isn't necessary to trigger the bug
- One clear ask per issue; complexity is a signal to split

## SRP — Single Responsibility

- One topic per issue: one bug, one feature request, one chore
- If the body covers multiple concerns, split into separate issues before submitting
- An issue that requires two separate PRs to close is a signal it violates SRP

## YAGNI — You Aren't Gonna Need It

- Scope to the immediate, concrete need
- Do not add "while we're at it" sub-tasks or future extension hooks
- Do not propose solutions that go beyond what the problem statement requires
- "Nice to have" items belong in a separate issue, not as a sub-bullet here

## DRY — Don't Repeat Yourself

- Search existing issues before opening; if a duplicate exists, comment on it instead
- Do not repeat information already captured in the template description or label
- Do not restate the title verbatim in the first sentence of the body

## Template Enforcement

- Must use an existing `.github/ISSUE_TEMPLATE/*.yml` template
- All fields marked `required: true` must be filled with real content (not placeholder text, not "N/A" without explanation)
- Title must not duplicate the template name (title = "Bug Report" is invalid)
- Remove any unfilled optional sections rather than leaving them blank
