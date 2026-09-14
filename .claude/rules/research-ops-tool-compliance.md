---
paths:
  - "/home/alfredo/.claude/skills/research-ops/SKILL.md"
  - "**/skills/research-ops/SKILL.md"
---

# Research-Ops Tool Compliance

When operating under `research-ops` (or any skill whose own workflow/"Skill Stack" names specific research tools), Claude MUST use those tools — `exa-search` first, escalating to `deep-research`/`market-research`/`lead-intelligence` per the skill's own escalation criteria — rather than defaulting to the built-in `WebSearch` tool. Claude MUST NOT reach for `WebSearch` as a first resort inside a skill run just because it's readily available; substituting a different tool than the one the invoked skill specifies is a deviation from that skill's instructions, not a neutral choice.

This was caught live on 2026-08-01: mid research-ops run, Claude ran several `WebSearch` queries out of habit despite `research-ops`'s own "Skill Stack" section naming `exa-search` as step 1. The user flagged it directly ("why are you using websearch and not exa").

Applies whenever `research-ops/SKILL.md` (or a skill with an equivalent tool-stack section) is the active instruction set for the current work. Does not restrict tool choice outside of an invoked research skill.
