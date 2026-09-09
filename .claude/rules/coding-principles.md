---
paths:
  - "**/*.py"
  - "**/*.js"
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.sh"
  - "**/*.go"
  - "**/*.rb"
  - "**/*.rs"
  - "**/*.java"
on:
  tools: [Edit, Write]
  paths: ["**/*.py", "**/*.js", "**/*.ts", "**/*.tsx", "**/*.jsx", "**/*.sh", "**/*.go", "**/*.rb", "**/*.rs", "**/*.java"]
---
# Coding Principles

## Required

### DRY (Don't Repeat Yourself)
- Every piece of logic MUST have one implementation. Extract when the same logic appears in two callsites; abstract when a third appears.
- Helpers MUST NOT be created for a single caller.
- Abstractions MUST NOT be introduced for hypothetical reuse.

Distinct from `ecc/common/coding-style.md`'s own DRY subsection (no extract-at-2/abstract-at-3 threshold, no single-caller-helper prohibition) — this is the stricter, authoritative version; apply this one when they conflict.

### KISS (Keep It Simple)
- MUST prefer the simplest solution that actually works — MUST NOT add complexity, indirection, or cleverness the problem doesn't require.

## Recommended
- YAGNI and SRP (Single Responsibility Principle) also apply — see `ecc/common/coding-style.md` for baseline coverage (YAGNI has an explicit subsection there; SRP coverage is implicit via its "File Organization" section). No stricter override exists for either yet.
