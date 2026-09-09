---
paths:
  - "CLAUDE.md"
  - "**/CLAUDE.md"
  - ".claude/skills/**/*.md"
  - ".claude/agents/*.md"
  - ".claude/commands/*.md"
on:
  tools: [Edit, Write]
  paths: ["CLAUDE.md", "**/CLAUDE.md", ".claude/skills/**/*.md", ".claude/agents/*.md", ".claude/commands/*.md"]
---

## Required
- MUST cut any word/clause whose removal loses no information the agent needs to act on. This is the definition of terse — not a word-count target.
- MUST cut connective filler, hedges, narrative transitions, self-evident "why" explanations, and anything already stated elsewhere in the artifact or session.
- MUST NOT enumerate a step-by-step procedure for something the model can already reason through from a stated goal + constraints — that pattern measurably degrades output quality on current models (over-prescription), it's not a safety margin.
- MUST NOT cut: exact reproducible values (paths, commands, error strings, code), safety-critical caveats/HALT conditions, glossary anchors, schema-governed frontmatter, or any genuine constraint/exception — an omitted boundary is not inferred, only assumed absent.

## Recommended
- SHOULD use a table/bullets when content is genuinely enumerable (options, steps, mappings) — one row/bullet per item, no padding inside.
- SHOULD keep prose for causal/nuanced explanation a bullet list would fragment.

## Advisory
- MAY compress further when information survives intact.
- Terseness here targets economy and output-quality (avoiding over-prescription/padding) — it is NOT a rule-compliance mechanism. No controlled evidence shows shorter rule files are followed more reliably; if a rule is being ignored, the fix is session length, instruction-count crowding, or a hook — not a shorter file.

