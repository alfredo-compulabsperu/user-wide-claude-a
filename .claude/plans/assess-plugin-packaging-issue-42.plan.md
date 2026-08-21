# Plan: Assess Converting Repo into a Distributable Claude Code Plugin

**Source issue**: [#42](https://github.com/alfredo-compulabsperu/user-wide-claude-a/issues/42)
**Related**: [#39](https://github.com/alfredo-compulabsperu/user-wide-claude-a/issues/39) (sync.sh `--marketplace` flag rejected), `.claude/prds/user-wide-claude-plugin.prd.md` (existing draft PRD)
**Complexity**: Medium
**Deliverable type**: Assessment/findings, **not code**. No plugin scaffolding, no `sync.sh`/`manifest.yaml` changes as part of this plan.

## Tooling

| Tool | Type | Needed by | Availability check |
|---|---|---|---|
| `gh` CLI, authenticated as alfredo-compulabsperu | CLI | Tasks 1, 6 | `gh --version` && `gh auth status` |
| `ecc:gh-issue-create` | Plugin | Task 6 | listed in available skills |
| `ecc:docs-lookup` or `claude-code-guide` agent | Plugin/Agent | Task 1 | listed in available skills/agents |
| `general-purpose` agent (via `Agent` tool) | Plugin | Task 2, 3 | listed in available agent types |

## Summary

Produce 5 independently-researched proposals for how to ship this repo's user-wide tooling as a distributable Claude Code plugin — each covering the hard requirement of two-way `CLAUDE.md`/`.claude/rules/*` sync, which the native plugin mechanism doesn't support. Critique and refine each, define ranking criteria up front, score uniformly, select a finalist, post results to issue #42, and open a follow-up implementation issue.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| PRD structure | `.claude/prds/user-wide-claude-plugin.prd.md` | Problem/Evidence/Hypothesis/Scope/Milestones/Open Questions/Risks — reuse this shape for the finalist writeup |
| Unverified-claim flagging | `.claude/CLAUDE.md` Research Persistence rule | `⚠️ verify:` prefix on any claim not confirmed against current docs/code |
| Assessment issue rigor | `.claude/rules/gh-issue-rules.md` § Assessment/Research Issues | Outcome constraints not tool prescriptions; explicit rigor block separate from DoD; flag unverifiable claims |
| Idempotency modes | `manifest.yaml:3`, `sync.sh` | skip/overwrite/prompt — existing precedent proposals should build on, not replace silently |

No existing "5 independent proposals + critique + ranked scoring" pattern exists elsewhere in this repo — this plan defines that process fresh, per the issue's rigor requirements.

## Files to Change

None during this plan's execution. Two artifacts get **created**, not repo source files:

| File | Action | Why |
|---|---|---|
| GitHub issue #42 (comment) | UPDATE | Post proposals, critique notes, ranking table, finalist, PRD disposition recommendation |
| New GitHub issue | CREATE | Follow-up: approve + implement the chosen finalist |
| `.claude/prds/user-wide-claude-plugin.prd.md` | UPDATE (optional, per DoD's "recommended not required" note) | Only if finalist recommends reusing/updating rather than superseding it |

## Tasks

### Task 1: Ground the research in current, verified facts
- **Action**:
  1. Fetch current Claude Code plugin docs (`docs-lookup`/Context7 or `claude-code-guide` agent) to confirm/refute the existing PRD's Evidence claim: plugins support skills/commands/agents/hooks/MCP/LSP + semver `version`, but **not** a plugin-root `CLAUDE.md` as project context and **no** manifest field for a `rules/` directory. This claim is dated in the PRD (drafted earlier) — re-verify, don't assume it's still current.
  2. Re-read issue #39 in full (already fetched: `claude` CLI rejects `--marketplace` on `claude plugin install`) and confirm whether it's still open/reproduces on current `claude` CLI version — every proposal touching plugin *install* flow must account for this failure mode or explicitly note it's orthogonal.
  3. Snapshot current repo state relevant to packaging: `manifest.yaml` structure, `sync.sh` idempotency modes, `.claude/skills/promote-artifact/`, `.claude/skills/validate-artifact/` — these are candidate building blocks any proposal might reuse or replace.
- **Mirror**: Research Persistence rule's "double-check each key claim against its cited source" — apply that discipline before, not after, drafting proposals.
- **Validate**: A short grounding note (in-conversation or scratch file, not committed) listing: (a) confirmed plugin mechanism capabilities/gaps as of today, (b) issue #39 current status, (c) reusable building blocks in this repo.

### Task 2: Generate 5 proposals independently (no anchoring)
- **Action**: Produce 5 proposals, each from a genuinely distinct lens, each addressing *all* stated requirements (plugin distribution of skills/commands/agents/hooks/scripts + two-way `CLAUDE.md`/rules sync). Suggested lenses (adjust if research surfaces better distinctions, per the issue's own allowance):
  1. Plugin + custom installer command (e.g. `/install-claude-tools`, close to the existing draft PRD's hypothesis)
  2. Plugin + hooks-based sync (a plugin-shipped hook that runs sync logic automatically on session start/tool use)
  3. Plugin + companion skill (a skill embedded in the plugin itself that users invoke to pull/push `CLAUDE.md`/rules)
  4. Plugin + CI-driven install step (a GitHub Action or release pipeline that pushes updates without any local pull step)
  5. Plugin + marketplace metadata (leaning on plugin marketplace fields/versioning for update discovery, minimal custom tooling)
  - Independence mechanism: draft each proposal without reading the others' drafts first — e.g. via 5 separate `Agent` (subagent_type: general-purpose) calls launched in one message so none sees another's output, each handed the same grounding note from Task 1 plus its own lens, each told to flag unverifiable claims with `⚠️ verify:`.
  - A 6th, non-plugin proposal (git-submodule/symlink/stay-on-`sync.sh`) is **only** written if Task 1's grounding suggests plugins fall short of the hard requirement in a way no plugin-based proposal can close — do not draft it speculatively.
- **Mirror**: `adversarial-delegation` skill posture — proposals are conclusions being handed to a critique pass, not final answers; each subagent should get authority to reach its own conclusion under its assigned lens rather than being steered toward a predetermined answer.
- **Validate**: 5 (or 6) proposal documents exist, each self-contained (problem coverage, mechanism, two-way sync design, tradeoffs, `⚠️ verify:` flags), each producible by an isolated agent that never saw a sibling proposal mid-draft.

### Task 3: Critique-and-refine each proposal
- **Action**: For each proposal, run at least one independent critique pass (a fresh-context reviewer, not the proposal's own author) that actively tries to find: factual errors against Task 1's grounding note, requirement gaps (especially the two-way sync requirement), stale assumptions, and scope drift. Each surfaced weakness is either folded into a revised version of the proposal or kept with an explicit "accepted tradeoff" note — never silently dropped.
- **Mirror**: `two-pass-artifacts` rule — isolated Pass B verifying Pass A's claims; `fact-grounded-authoring` skill's verify-before-commit method.
- **Validate**: Each of the 5 proposals shows a visible before/after or an explicit tradeoffs-accepted list from its critique pass.

### Task 4: Define ranking criteria before scoring
- **Action**: Write the scoring rubric *before* looking at how each proposal scores — e.g. candidate criteria: (a) coverage of the two-way `CLAUDE.md`/rules sync hard requirement, (b) update-pull ergonomics (effort to get updates on a new/existing machine), (c) update-push ergonomics (effort to promote local edits back), (d) blast radius / reversibility if the mechanism breaks, (e) dependency on external CLI behavior that's already shown fragility (issue #39), (f) implementation complexity, (g) fit with this repo's solo-developer/multi-machine scope (per the existing PRD's Users section — not team/shared distribution). Weight or leave unweighted — state the choice explicitly.
- **Mirror**: `agent-benchmark-validity`/`reliable-multi-agent-voting` skill posture — criteria fixed before results are seen, to avoid post-hoc rationalization.
- **Validate**: A criteria table exists, timestamped/ordered before any scoring numbers appear in the conversation or output doc.

### Task 5: Score all proposals uniformly and select a finalist
- **Action**: Apply Task 4's criteria to all 5 (or 6) proposals with a visible per-criterion breakdown (table: proposal × criterion). Select the top-scoring proposal as finalist. If a non-plugin proposal exists and wins, explicitly justify why it's "overwhelmingly better" per the issue's stated bar for choosing that exception — a narrow win is not sufficient.
- **Validate**: Ranking table with per-criterion scores, finalist named, and (if applicable) the non-plugin-exception justification is explicit and reasoned, not asserted.

### Task 6: Post findings and open the follow-up issue
- **Action**:
  1. Post the full assessment (proposals, critique notes, ranking table, finalist, `⚠️ verify:` flags) to issue #42 as a comment — per `gh-issue-rules.md`, this is the DoD's "findings/proposals/ranking/finalist posted to this issue (or linked doc)" item.
  2. Include the recommended (not required per DoD) disposition of `.claude/prds/user-wide-claude-plugin.prd.md`: keep as-is, update to match the finalist, or mark superseded — with a one-line rationale.
  3. Use `/gh-issue-create` (repo convention — never `gh issue create` directly, per `CLAUDE.md`) to open a follow-up issue scoped to approving and implementing the finalist. Keep it SRP-scoped per `gh-issue-rules.md`: one ask (approve + implement chosen solution), not a re-litigation of the assessment.
  4. Check all remaining DoD checkboxes on issue #42 as satisfied; do not close the issue unless explicitly asked (issue closure is a repo-state action, confirm first).
- **Mirror**: `gh-issue-rules.md` Template Enforcement + Assessment/Research Issues sections.
- **Validate**: Issue #42 has the posted comment; a new issue exists and is linked from #42; DoD checklist items are verifiably satisfied by what was posted.

## Validation

No build/test commands apply — this is a research/writing deliverable. Validation is checklist-based:
```bash
# Confirm the follow-up issue was created and links back to #42
gh issue view 42 --repo alfredo-compulabsperu/user-wide-claude-a --json comments
gh issue list --repo alfredo-compulabsperu/user-wide-claude-a --search "in:body #42" --state open
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Proposals anchor on each other despite isolation intent | Medium | Launch all 5 lens agents in a single parallel batch with no shared intermediate state; verify none references another's proposal content before critique |
| Stale plugin-mechanism claims carried over from the existing PRD (drafted earlier, possibly outdated) | Medium | Task 1 re-verifies against current docs before any proposal is drafted, not after |
| Ranking criteria unconsciously shaped to favor a pre-existing preference (the PRD's own installer-command hypothesis) | Medium | Task 4 is a standalone step completed and stated before Task 5 scoring begins; criteria must not name a specific proposal |
| Non-plugin proposal gets drafted reflexively instead of only-if-warranted | Low | Task 2 explicitly gates the 6th proposal on Task 1's findings, not on default habit |
| Follow-up issue duplicates/overlaps issue #39 | Low | Follow-up issue explicitly references #39 as a known constraint the implementation must handle, not a separate concern |

## Acceptance
- [ ] Task 1 grounding note completed and re-verifies (not assumes) the existing PRD's plugin-capability claims
- [ ] 5 proposals drafted independently, each covering the two-way sync hard requirement, each flagging unverifiable claims
- [ ] Each proposal shows a critique-and-refine pass with addressed-or-accepted-tradeoff resolution
- [ ] Ranking criteria defined and visibly precede scoring
- [ ] All proposals scored uniformly with per-criterion breakdown; finalist selected
- [ ] Assessment posted to issue #42; PRD disposition recommendation included
- [ ] Follow-up implementation-approval issue opened via `/gh-issue-create` and linked to #42

---
*Status: DRAFT plan — awaiting confirmation before execution begins.*
