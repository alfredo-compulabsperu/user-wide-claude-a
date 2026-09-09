# Research Ops Invocation Syntax & Parallelism

## Required
- Call syntax, in this fixed order: `/research-ops <subject> [modifier] [continuation instructions]`. A modifier, when present, MUST come immediately after the subject and before any continuation instructions — never interleaved with the subject, never after continuation text.
- Recognized modifier tokens (case-insensitive): a fork-control token — `quick`, `nopa`, `fork`, `para<n>`, `p<n>`, or their `--flag` forms `--quick`, `--nopa`, `--fork`, `--para=<n>`, `--p=<n>` — and, independently, `--force` (see Repetition guard below). At most one fork-control token plus optionally `--force`, in either order, both before any continuation instructions.
- Everything before the first recognized modifier token is the research subject/prompt. Everything after the modifier token is a **continuation instruction** — a separate follow-up step to run once the research is done and reported (e.g. "proceed with aaa") — it is NOT part of the research subject and MUST NOT be fed into any research agent's prompt.
- If no modifier token appears anywhere in the argument string, the entire remainder is the subject — there is no way to split out a continuation instruction without a modifier delimiting it.

## Default behavior — no modifier
- MUST spawn 2 parallel `Agent` (`fork`) calls (2p auto-fork), each given the identical subject as its prompt, launched together in a single message. The main chat MUST then synthesize the 2 results into one unified response using the research-ops skill's own Output Format, explicitly reconciling disagreements between passes rather than silently picking one.

## Opt out — `quick`, `nopa`, `--quick`, `--nopa`
- MUST NOT spawn any parallel `Agent` (`fork`) calls. Run the research-ops workflow as a single direct pass in the main chat instead.

## Raise the count — `fork`, `--fork`, `para<n>`, `p<n>`, `--para=<n>`, `--p=<n>`
- `fork` / `--fork` (no count given) → N=2 (same as default, explicit).
- `para<n>` / `p<n>` / `--para=<n>` / `--p=<n>` → N=n parallel calls.
- All N calls MUST be launched together in a single message; synthesize as in Default behavior above.

## Fallback
- If a token that looks like it might be a modifier can't be confidently parsed, state the ambiguity to the user in one sentence, then proceed with the 2p auto-fork default — MUST NOT block on a clarifying question for this case.

## After the research
- If a continuation instruction was given, execute it as a separate step after the research (and any synthesis) is complete and has been reported to the user — never fold it into the research task itself.

## Required tooling
- The tool the skill stack designates for search (Exa — `web_search_exa`/`exa-agent`, per the global `web-research-tool-selection` rule) MUST be available before running research. MUST NOT silently substitute a different tool (`WebSearch`, `WebFetch`, etc.) when it's missing or unconfigured.
- If it's unavailable: MUST stop and report the error — name the missing tool, state that research did not run — rather than degrading to a fallback tool.

## Repetition guard
- Before running, check whether the subject substantially duplicates a prior `/research-ops` call in this session, or an existing `research/*.md` file in the active repo. "Substantially duplicates" means same underlying question, not just overlapping keywords.
- If it does: MUST NOT run the research. State in one sentence that it looks like a repeat, name the earlier answer/file, and stop.
- `--force` overrides the skip and runs normally (respecting whatever fork-control modifier, if any, is also present).
