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

## Assessment / Research Issues (LLM-Executed)

When the issue scopes a research or assessment task — especially one an LLM will pick up and execute:

- State outcome constraints, not tool/strategy prescriptions — e.g. "must survive an independent critique pass" instead of "iterate 3 times using workflow X"
- If process rigor matters, spell it out as an explicit "Rigor requirements" block, separate from Definition of Done: independent generation (no anchoring on the first idea), ranking/scoring criteria defined *before* scoring, at least one critique-and-refine pass per option, and any claim that can't be independently verified flagged (e.g. `⚠️ verify:`) rather than presented as confirmed
- Whenever the task involves LLM-produced output of any kind, explicitly guard against hallucination, stale/outdated assumptions, goal drift from stated requirements, and silent requirement bypass — well-known LLM failure modes, not specific to research
- Keep rigor requirements distinct from Definition of Done: rigor describes *how the work must be conducted*, DoD lists *what must exist* when done
