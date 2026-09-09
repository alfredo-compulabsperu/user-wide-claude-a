---
paths:
  - ".claude/rules/**/*.md"
  - ".claude/lazy/rules/**/*.md"
---

# Rule Authoring Format

## Required

Rule files MUST be written in prose, not tables. Content MUST be grouped under up to three headers, in this order: **Required** (MUST / MUST NOT statements), **Recommended** (SHOULD / SHOULD NOT statements), and **Advisory** (MAY / MAY NOT statements). Omit any of the three headers a given file has no content for — do not include an empty section.

When a rule's guidance only matters at the moment of writing or editing a specific class of file — not every session — it MUST be split so the full content lives in a lazy file under `.claude/lazy/rules/`, enforced by at least one of: a proxy under `.claude/rules/` stating only the trigger and pointing to the lazy file, or a hook that inspects the tool call and enforces the trigger mechanically (see Recommended below). Use both when the hook alone doesn't also surface the trigger to a human skimming `.claude/rules/`.

When a proxy is used and the trigger corresponds to a file glob, the proxy MUST express it via `paths:` frontmatter over a prose-only condition. Use a prose-only condition only when no glob can capture the trigger precisely. A hook-only split (no proxy) MUST express its own trigger condition directly in the hook's matching logic instead.

Do NOT split off content that must be evaluated even when no matching file gets written (e.g. a policy that applies regardless of the eventual save destination) — that stays in an always-loaded rule.

## Recommended

For a `paths:`-triggered proxy, relying solely on the proxy's "Claude must load and follow `<lazy-file>`" instruction depends on the model choosing to read that file every time. Where guaranteed enforcement matters more than that convenience, back the split with a `PostToolUse:Edit|Write` hook that inspects `tool_input.file_path`, matches it against the same glob the proxy declares, and injects the lazy file's full content directly as `additionalContext` — see `~/.claude/hooks/ecc-typescript-rule-inject.py` (paired with `~/.claude/rules/ecc/typescript/*.md` → `~/.claude/lazy/rules/ecc/typescript/*.md`) and the analogous `research-ops-rule-inject.py`/`enterplanmode-rule-inject.py` pattern for Skill- and tool-triggered proxies. Register the hook in `settings.json` under the matching event.
