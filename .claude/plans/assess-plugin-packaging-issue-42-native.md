# Plan: Assess Converting Repo into a Distributable Claude Code Plugin (Issue #42)

## Context

This repo currently ships user-wide Claude Code tooling (skills, commands, agents, hooks, scripts, `CLAUDE.md`, rules) to other machines via a hand-rolled `sync.sh` + `manifest.yaml` pull-based script. That requires a manual re-run on every machine to pick up updates and gives no fine-grained per-artifact install control. Claude Code's native plugin system offers versioned, more standardized distribution for skills/commands/agents/hooks, but it does **not** natively support `CLAUDE.md` or a `rules/` directory as installable content — the two artifact types this repo leans on most for behavioral guidance.

Issue #42 asks for an **assessment**, not an implementation: produce 5 independently-generated proposals for achieving plugin distribution while still covering two-way `CLAUDE.md`/rules sync (pulling updates in, and promoting local edits back out), critique each, define ranking criteria before scoring, rank them, and post the result plus a follow-up issue. A related bug (#39) shows `sync.sh`'s existing `claude plugin install --marketplace` call already fails against the current CLI, so any proposal touching plugin install must account for that. A draft PRD (`.claude/prds/user-wide-claude-plugin.prd.md`) already sketches one candidate direction (plugin + custom installer command) — it's a starting hypothesis to validate or supersede, not a foregone conclusion.

Nothing here produces code or repo changes; the deliverable is a GitHub issue comment (findings) and a new follow-up issue.

## Recommended Approach

Run the assessment as a 6-step pipeline, each step producing a durable artifact so quality can be checked before moving on:

1. **Ground the research.** Re-verify (not assume) the PRD's claim about what the native plugin mechanism does and doesn't cover, using `ecc:docs-lookup`/Context7 or the `claude-code-guide` agent against current docs — the PRD may be stale. Re-check issue #39's current repro status. Snapshot the reusable building blocks already in the repo: `manifest.yaml`, `sync.sh` idempotency modes (skip/overwrite/prompt), `.claude/skills/promote-artifact/`, `.claude/skills/validate-artifact/`.

2. **Generate 5 proposals independently**, each from a distinct lens, each covering the full requirement set (plugin-distributed skills/commands/agents/hooks/scripts + two-way CLAUDE.md/rules sync):
   - Plugin + custom installer command
   - Plugin + hooks-based sync
   - Plugin + companion skill
   - Plugin + CI-driven install step
   - Plugin + marketplace metadata
   Draft these via separate isolated `Agent` calls launched in one batch (subagent_type: general-purpose), each given the Step 1 grounding note and only its own lens — never another proposal's draft — so none anchors on a prior answer. Each proposal must flag unverifiable claims with `⚠️ verify:`. Only add a 6th non-plugin proposal (submodule/symlink/stay-on-sync.sh) if Step 1 finds plugins structurally can't meet the hard requirement — don't draft it by default.

3. **Critique-and-refine each proposal** with an independent reviewer pass per proposal (fresh context, not the drafting agent) checking for factual errors against the grounding note, missed two-way-sync coverage, stale assumptions, and scope drift. Fold fixes in or record an explicit accepted-tradeoff note — nothing gets silently dropped.

4. **Define ranking criteria before scoring**: two-way sync coverage, update-pull ergonomics, update-push ergonomics, blast radius/reversibility, dependency on fragile external CLI behavior (per #39), implementation complexity, fit with solo-developer/multi-machine scope. Write this table before any proposal is scored against it.

5. **Score all proposals uniformly** against the fixed criteria with a visible per-criterion table, select the top scorer as finalist. If a non-plugin proposal wins, require an explicit "overwhelmingly better" justification, not just a narrow edge.

6. **Post and follow up**: comment the full assessment (proposals, critique notes, ranking table, finalist, PRD disposition recommendation) on issue #42; open a follow-up issue via `/gh-issue-create` (never bare `gh issue create`, per repo `CLAUDE.md`) scoped only to approving/implementing the finalist, cross-referencing #39 as a known constraint.

## Critical Files / References

- `.claude/prds/user-wide-claude-plugin.prd.md` — existing draft hypothesis to validate/supersede
- `manifest.yaml`, `sync.sh` — current distribution mechanism, candidate building blocks
- `.claude/skills/promote-artifact/`, `.claude/skills/validate-artifact/` — existing artifact-lifecycle tooling proposals may reuse
- `.claude/rules/gh-issue-rules.md` (§ Assessment/Research Issues) — governs rigor and unverifiable-claim flagging for the eventual issue post
- GitHub issue #39 — plugin install failure mode any install-touching proposal must address

## Verification

No build/tests apply (research deliverable). Verify completion via:
```bash
gh issue view 42 --repo alfredo-compulabsperu/user-wide-claude-a --json comments   # assessment posted
gh issue list --repo alfredo-compulabsperu/user-wide-claude-a --search "in:body #42" --state open   # follow-up issue exists and links back
```
Checklist correctness: all 5 (or 6) proposals independently drafted, each critiqued, ranking criteria predate scoring, finalist named with rationale, PRD disposition recommended.
