---
description: Display a plain-English summary of the current session (default/--extra/--full sections)
model: haiku
---

# Session Summary

Display a summary of the current session. Do NOT save any file. Do NOT read any file from disk. Source is this conversation only.
Omit any section if there is nothing to report for it.

Write in plain, terse English. Gloss any technical or domain-specific jargon, code, or acronym inline on first use (e.g., "PR (pull request)").

Default sections: Currently Doing, Pending or blocked, Next steps. Extra sections: What Am I Forgetting?, Topics, Decisions, Abandoned, Deferred, Recommendations.

By default, show only the default sections. Pass `--extra` (verbatim, or inferred from phrasing like "show more" or "what else") to show only the extra sections instead. Pass `--full` (verbatim, or inferred from phrasing like "full summary," "show everything," or "complete summary") to show every section.

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
Ordered list by sequence and/or priority (inferred from session)

## Recommendations
- KB Articles to create or update from research done during the session
- Findings to document
- Improvements to make

