---
description: Display a plain-English summary of the current session (default/--extra/--full sections)
model: haiku
---

# Session Summary

Display a summary of the current session. Do NOT save any file. Do NOT read any file from disk. Source is this conversation only.
Omit any section if there is nothing to report for it.

Write in plain, terse English. Gloss any technical or domain-specific jargon, code, or acronym inline on first use (e.g., "PR (pull request)").

Default sections: Currently Doing, Pending or blocked, Next steps, Things worth saving before clearing out or exiting the session. Extra sections: What Am I Forgetting?, Topics, Decisions, Abandoned, Deferred, Recommendations.

By default, show only the default sections. Pass `--extra` (verbatim, or inferred from phrasing like "show more" or "what else") to show only the extra sections instead. Pass `--full` (verbatim, or inferred from phrasing like "full summary," "show everything," or "complete summary") to show every section.

If Next steps and/or Things worth saving renders at least one item, prompt the user afterward to pick one item number, from their combined running sequence, to work on next. Do not act on it until they answer. This applies even if one of the two sections is omitted for having nothing to report.

## Currently Doing
Latest actions taken this session and their current status. Include the related plan, runbook (only if not closed this session), work item number + summary, or ad hoc topic for each action. If there has been a direction change, note what was active just before the pivot and its status at the time of the switch.

## What Am I Forgetting?
Prior work actions left aside due to a direction change. Surface anything that was in progress (work item, refactor, plan implementation) before a pivot to standards, tooling, documentation, or other ad hoc work.

## Topics
Key topics covered this session.

## Decisions
Decisions reached, each with its rationale.

## Abandoned
Approaches ruled out or abandoned: what was tried, why it was dropped, what was learned, and whether it's an explicit dead end that must not be attempted again.

## Deferred
Items explicitly pushed to later without a decision being made.

## Pending or blocked
Unresolved items and their blockers.

## Next steps
Numbered list by sequence and/or priority (inferred from session), starting at 1. Continuation steps only — actions to actually do next in the work itself (build, fix, test, ship).

## Things worth saving before clearing out or exiting the session
A separate category from Next steps, not a continuation of the work: content that exists only in this conversation and would be lost if the session is cleared or closed, with no action to "do" beyond capturing it somewhere durable. Include only items that are not yet durably recorded anywhere. Exclude anything that will naturally be captured by the next steps or by work already in flight (for example, a fix that the next commit will record anyway), and exclude anything already captured elsewhere as of now (e.g. already written into a repo's CLAUDE.md, already committed) — the fact that a correction happened is not itself worth preserving once the correction is already on record.

Render as a numbered list that continues the numbering from Next steps (if Next steps ends at 3, this list starts at 4) purely for a single running reference sequence — the two sections MUST NOT share items. Every item belongs to exactly one section: if it is a thing to do, it goes in Next steps; if it is a thing to preserve, it goes here. Do not list the same item in both, even rephrased.

Render each item as: `[<destination>] <topic subject>: <summary>` — one line per item, continuing the numbered sequence from Next steps. `<destination>` is exactly one of the labels below; `<topic subject>` is a short noun phrase naming what the item is about; `<summary>` covers the content and, where not obvious, why it would be lost if not captured.

Destination labels:
- `memory` — a durable preference, correction, or fact about the user or the work
- `KB, repo` / `KB, user-wide` — knowledge base article, add/update/replace; research results done this session belong here
- `GH` — GitHub issue or comment, new or update
- `PRD` — product requirements document, new or update
- `plan` — a new plan file, or an update to an ongoing one
- `skill, repo` / `skill, user-wide` — instructions or steps followed this session that repeated or are likely to recur
- `hook` — a rule that went unfollowed this session and would benefit from mechanical enforcement instead of prose

Typical candidates: a decision and its rationale that no artifact records, a constraint or gotcha discovered by trial and error, a dead end that must not be retried, research findings, a user correction about how to work, or a scoped follow-up nobody has filed yet.

## Recommendations
- Findings to document
- Improvements to make

