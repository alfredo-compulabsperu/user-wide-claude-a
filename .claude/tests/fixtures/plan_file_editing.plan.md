# Plan: Refactor utility functions

## Summary

Refactor duplicate helper functions across `src/utils/` into a single shared module.
No web research, no agent spawning, no notebook editing.

## Tasks

1. Read `src/utils/string-helpers.ts` and `src/utils/format-helpers.ts`
2. Identify duplicate logic
3. Create `src/utils/shared.ts` with the deduplicated functions
4. Update all import sites using Edit
5. Run `npm test` via Bash to confirm nothing broke

## Files to Change

| File | Action |
|------|--------|
| `src/utils/shared.ts` | CREATE |
| `src/utils/string-helpers.ts` | EDIT — remove duplicates |
| `src/utils/format-helpers.ts` | EDIT — remove duplicates |
