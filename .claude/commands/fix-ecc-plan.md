---
description: Audit a plan file against the ecc:plan output format spec, show proposed fixes, prompt for confirmation, and apply them. Discovers the spec at runtime from ecc:plan SKILL.md or commands/plan.md.
argument-hint: "[path-to-plan.md | keyword]"
allowed-tools: Read, Write, Edit, Bash
creation-date: 2026-06-04T00:00:00-05:00
last-update-date: 2026-06-04T12:00:00-05:00
author: alfredo-revilla <alfredorevilla@gmail.com>
---

# /fix-ecc-plan

Audit a `.plan.md` file against the live ecc:plan output format spec, present a
diff of required fixes, prompt for confirmation, and apply the approved changes.

> **Architecture:** This command is read-audit-confirm-write only. It never writes
> without explicit user approval. All spec rules are derived at runtime from the
> ecc:plan SKILL.md -- no hardcoded format assumptions.

## Steps

### Step 1 -- Resolve the plan file

Check in order:

1. `$ARGUMENTS` is a `.plan.md` or `.md` path -> use directly. Set `PLAN_SOURCE = file`.
2. `$ARGUMENTS` is a keyword -> glob `.claude/plans/` for `*keyword*.plan.md`; use most recent match. Set `PLAN_SOURCE = file`.
3. `$ARGUMENTS` is empty -> find the last `.plan.md` path mentioned in this conversation; use it. Set `PLAN_SOURCE = file`.
4. Still unresolved -> scan this conversation for the most recent plan-shaped content block (output from `/ecc:plan` or `/plan`: a structured markdown response containing at least two plan-section headings). If found, hold that content in memory as the plan. Set `PLAN_SOURCE = conversation`.
5. Still unresolved -> list `.claude/plans/` contents and print:

   ```
   No plan specified. Which plan? Found: [list]. Run: /fix-ecc-plan <filename>
   ```

   STOP. Do not continue until the user provides a path.

If `PLAN_SOURCE = file`: read the resolved plan file in full.
If `PLAN_SOURCE = conversation`: the plan content is already in context from step 4 — no file read needed.

### Step 1.5 -- Detect plan type

Scan the plan file for these markers:

| Plan type | Marker patterns |
|---|---|
| `prd` | Any of: heading `## Patterns to Mirror`, `## Files to Change`, `## Acceptance`; or a `### Task` block containing `**Action**` / `**Mirror**` / `**Validate**` sub-fields |
| `non-prd` | Any of: heading `## Requirements Restatement`, `## Implementation Phases`, `## Estimated Complexity`; or text `**WAITING FOR CONFIRMATION**` |

If both types' markers appear or neither appears:

```
AMBIGUOUS: Cannot determine plan type.
PRD markers found:     [list or "none"]
Non-PRD markers found: [list or "none"]

Override with: /fix-ecc-plan --type prd <path>
           or: /fix-ecc-plan --type plan <path>
```

STOP.

Set `PLAN_TYPE` = `prd` or `non-prd`.

### Step 2 -- Load the spec for the detected plan type

#### If `PLAN_TYPE = non-prd`

Use the inline Non-PRD schema below as `SPEC`. Skip the shell discovery commands.

**Non-PRD Plan Schema**

| Section | Required | Format |
|---|---|---|
| `## Requirements Restatement` | Yes | Prose or bullet list restating what the user asked for |
| `## Implementation Phases` | Yes | One `### Phase N: <title>` sub-section per phase; each phase is a bullet list |
| `## Dependencies` | Yes | Flat bullet list of runtime / build / service dependencies |
| `## Risks` | Yes | Bullet list; each item prefixed with `HIGH:`, `MEDIUM:`, or `LOW:` |
| `## Estimated Complexity` | Yes | Complexity label (`LOW` / `MEDIUM` / `HIGH`) + per-area hour estimates + total |
| `**WAITING FOR CONFIRMATION**` prompt | Yes | Last line of plan body |

Sub-rules for `## Implementation Phases`:
- Each phase MUST use a `### Phase N: <descriptive title>` heading
- Phase body MUST be a bullet list (not prose paragraphs, not numbered list)
- Phase headings MUST be numbered sequentially starting at 1

Sub-rules for `## Risks`:
- Each item MUST begin with `- HIGH:`, `- MEDIUM:`, or `- LOW:`
- Bullet list only — no table format

Sub-rules for `## Estimated Complexity`:
- MUST name a complexity label: `LOW`, `MEDIUM`, or `HIGH`
- MUST include at least one time estimate (hours or days)
- MUST include a total estimate

Set `SPEC_PATH` = `(inline non-PRD schema)`. Proceed to Step 3.

#### If `PLAN_TYPE = prd` — Discover the ecc:plan spec at runtime

Do NOT use a hardcoded spec. Run all five discovery commands in order and use the first
non-empty result as `SPEC_PATH`:

```bash
# 1. Dedicated SKILL.md (ecc plugin layout)
SPEC_PATH=$(find ~/.claude/plugins -path "*/ecc/skills/plan/SKILL.md" 2>/dev/null | head -1)
# 2. Any SKILL.md containing the output format section
[ -z "$SPEC_PATH" ] && SPEC_PATH=$(find ~/.claude/plugins -name "SKILL.md" 2>/dev/null \
  | xargs grep -l "PRD Artifact Output" 2>/dev/null | grep -i plan | head -1)
# 3. Project-local SKILL.md
[ -z "$SPEC_PATH" ] && SPEC_PATH=$(find .claude/skills -name "SKILL.md" 2>/dev/null \
  | xargs grep -l "PRD Artifact Output" 2>/dev/null | head -1)
# 4. ecc command file (spec embedded in plan.md, not a SKILL.md)
[ -z "$SPEC_PATH" ] && SPEC_PATH=$(find ~/.claude/plugins -name "plan.md" 2>/dev/null \
  | xargs grep -l "PRD Artifact Output" 2>/dev/null | head -1)
# 5. User-level commands directory
[ -z "$SPEC_PATH" ] && SPEC_PATH=$(find ~/.claude/commands -name "plan.md" 2>/dev/null \
  | xargs grep -l "PRD Artifact Output" 2>/dev/null | head -1)
echo "$SPEC_PATH"
```

If `SPEC_PATH` is empty after all five:

```
ERROR: ecc:plan spec not found. Cannot audit without a reference spec.
Searched: ~/.claude/plugins (SKILL.md + plan.md), .claude/skills, ~/.claude/commands
Fix: verify ecc plugin is installed, then retry.
```

Stop.

Read `SPEC_PATH` in full. Locate the output format section (heading: "PRD Artifact Output"
or "Output Format"). If the section does not exist inside the file:

```
ERROR: output format section not found in spec at <SPEC_PATH>.
```

Stop.

Extract and record as your working spec:
- Required top-level section names (e.g. Summary, Patterns to Mirror, Files to Change, Tasks, Validation, Risks, Acceptance)
- Expected format per section: table | prose | fenced-bash-block | checkbox-list
- Required sub-fields per `### Task N` block (e.g. Action, Mirror, Validate)
- Field-level format rules (e.g. `path:line` in source refs, three-column Risks table, `- [ ]` checkbox syntax for Acceptance)

### Step 3 -- Audit

#### If `PLAN_TYPE = non-prd`

Compare the plan against the Non-PRD schema from Step 2. For each required section:

- **Present**: yes / no
- **Format**: correct / wrong (specify what is wrong)
- `## Implementation Phases`: each phase uses `### Phase N: <title>` heading? Each phase body is a bullet list (not numbered list or prose)?
- `## Risks`: each item has a `HIGH:` / `MEDIUM:` / `LOW:` prefix?
- `## Estimated Complexity`: includes a complexity label (`LOW` / `MEDIUM` / `HIGH`)? includes per-area estimates? includes a total?
- `**WAITING FOR CONFIRMATION**` prompt present as the last line of the plan body?

**Do NOT flag extra sections** (architecture notes, design decisions, open questions) — these are allowed additions.

Severity scale: same as PRD (Critical = section absent, Medium = format wrong, Low = minor deviation).

Proceed to Step 4 with the gap list.

#### If `PLAN_TYPE = prd`

Compare plan against the extracted spec. For each required section:

- Present: yes / no
- Format: correct / wrong (specify what is wrong)
- `### Task N` blocks: Action present? Mirror present? Validate present?
- `## Patterns to Mirror`: source column has `path:line` refs (not just filenames)?
- `## Validation`: fenced bash block present (not prose)?
- `## Risks`: three columns (Risk / Likelihood / Mitigation)?
- `## Acceptance`: items are `- [ ]` checkboxes?

**Do NOT flag extra sections** (Phase 0.5, architecture notes, project context) -- these
are allowed additions, not violations.

**Authority ambiguity check** (run when `## Tasks` is present): scan for extra sections whose
names match implementation-detail patterns (`## Command N`, `## Phase N`, `## Step N`,
`## Implementation`, or any `##` section containing step-by-step content or code blocks that
overlaps with what `## Tasks` describes). If any such sections exist and there is no explicit
disambiguation note (a blockquote or sentence stating which section is authoritative), flag:

| Severity | Condition | Fix |
|---|---|---|
| Medium | `## Tasks` present + overlapping detail sections + no disambiguation | Add an `## Implementation Detail` grouping header with a one-line note stating that `## Tasks` is the completion checklist and the sections below are the authoritative step-by-step spec |

Severity scale:

| Severity | Meaning |
|---|---|
| Critical | Required section entirely absent |
| Medium | Section present but format is wrong |
| Low | Minor deviation (e.g. missing one sub-field in one task) |

### Step 4 -- Present proposed fixes

**If zero gaps:**

```
PASS -- plan conforms to ecc:plan spec.
Spec: <SPEC_PATH> | Sections checked: N
```

STOP.

**If gaps found**, print the full numbered fix list before touching any file:

```
AUDIT RESULT: N gap(s)
Spec: <SPEC_PATH>
Plan: <plan path>

[1] CRITICAL -- <section>: <what is missing>
    Current:  <one line>
    Fix:      <one line>

[2] MEDIUM -- <section>: <what is wrong>
    Current:  <one line>
    Fix:      <one line>

...

Apply all N fixes? (yes / no / select: 1,3)
```

STOP HERE. Do not proceed to Step 5 until the user responds.

### Step 5 -- Apply confirmed fixes

Parse user response:

| Response | Action |
|---|---|
| `yes` / `y` / `all` | Apply all proposed fixes |
| `no` / `n` / `skip` | Print "No changes made." STOP. |
| `1,3` / `1 3` / `select: 1,3` / `select:1,3` | Apply only the listed fix numbers |
| Anything else | Re-print the fix list, append "Apply which? (yes / no / 1,3)". STOP. Wait for user reply before continuing. |

**If `PLAN_SOURCE = file`:** Apply each confirmed fix using the Edit tool:
- Change only the bytes that satisfy the fix
- Preserve all surrounding content character-for-character
- Do not reformat, reword, or reorder anything outside the changed lines
- Do not remove extra sections

**If `PLAN_SOURCE = conversation`:** Output the full corrected plan as a fenced markdown block in your response. Apply fixes to the in-memory content — do not write any file. Annotate each changed line or section with a brief inline comment (`<!-- fix N applied -->`). Remind the user the corrected plan is not persisted.

### Step 6 -- Report

```
DONE -- <N> fix(es) applied to <plan path | conversation>

  Applied: [number + one-line description per fix]
  Skipped: [number + reason, or "none"]
  Spec:    <SPEC_PATH>
  Source:  file (<path>) | conversation (not persisted — save to file to keep)

Run /fix-ecc-plan again to verify no remaining gaps.
```

## Do NOT use when

- Audit only (no edits needed) -- read the plan and compare manually
- The plan does not exist yet -- run `/ecc:plan` first to generate it
- Changing plan *content* (scope, tasks, decisions) -- edit directly

## Constraints

- Never write to the plan file before Step 5 confirmation is received
- Never modify sections not covered by a confirmed fix
- Never remove extra sections (Phase 0.5, architecture notes, project context)
- Derive the spec from SKILL.md at runtime only -- do not rely on training-data memory
- If `$ARGUMENTS` contains shell metacharacters (`;`, `|`, `&`, backtick, `$()`):
  abort with "ERROR: path contains shell metacharacters -- refusing."
- On any Read/Bash failure: fail-closed -- report the error and stop

## Example Usage

### PRD plan (from `/ecc:plan`)

```
/fix-ecc-plan write-cover-letter-pipeline

-> Finds .claude/plans/write-cover-letter-pipeline.plan.md
-> Detects PLAN_TYPE = prd (## Patterns to Mirror heading present)
-> Runs find to locate ecc:plan SKILL.md
-> Extracts output format spec from SKILL.md
-> Audits: 2 gaps found
-> Shows numbered fix proposal, STOP
-> User types: select: 2
-> Applies fix [2] only
-> Reports: 1 fix applied, 1 skipped
```

### Non-PRD plan (from `/plan`)

```
/fix-ecc-plan notifications

-> Finds .claude/plans/notifications.plan.md
-> Detects PLAN_TYPE = non-prd (## Requirements Restatement heading present)
-> Loads inline Non-PRD schema (no SKILL.md discovery needed)
-> Audits: 1 gap found
   [1] MEDIUM -- ## Risks: items missing HIGH:/MEDIUM:/LOW: prefix
       Current:  - Email deliverability (SPF/DKIM required)
       Fix:      - HIGH: Email deliverability (SPF/DKIM required)
-> Shows fix proposal, STOP
-> User types: yes
-> Applies fix [1]
-> Reports: 1 fix applied
```
