# Plan: M4 — `/validate-artifact` Skill

**Source PRD**: `.claude/prds/user-wide-claude-portability.prd.md`
**Selected Milestone**: M4 — `/validate-artifact` skill
**Complexity**: Medium

## Summary

Create a `validate-artifact` Claude Code skill that checks any user-wide artifact (file or directory) against three criteria: repo-agnostic (no machine-specific content), dependency-complete (all referenced tools/files exist), and terse (single-purpose, no bloat). Static grep handles portability violations deterministically; LLM judgment handles dependency completeness and terseness where grep is insufficient. The skill is standalone — callable without `/promote-artifact`.

## Open Question Resolution

| Question | Decision | Rationale |
|---|---|---|
| Static grep vs LLM for repo-agnostic violations? | **Hybrid**: static grep first, LLM as secondary | Grep is fast and reliable for known patterns (absolute paths, hardcoded usernames). LLM catches semantic violations grep misses. Static grep findings are always reported; LLM findings are flagged as warnings. |

## Validation Criteria

### 1. Repo-agnostic (static grep)
Fail if artifact contains any of:
- Absolute paths: `/home/`, `/Users/`, `/root/`
- Hardcoded username: `alfredo` or any `/home/<word>/` pattern
- Machine hostnames: anything matching `@hostname` or referencing `$HOSTNAME` with a literal value
- API keys / secrets: patterns matching `sk-`, `ghp_`, `xoxb-`, etc.

### 2. Dependency-complete (grep + LLM)
- Static: scan for `source`, `./`, `require`, `import` statements → verify referenced files exist in `~/.claude/` or are standard Linux tools (`bash`, `python3`, `git`, `curl`, `jq`, `sha256sum`)
- LLM: "Does this artifact reference tools, files, or environment variables that might not exist on a fresh machine?"

### 3. Terse (LLM)
- LLM: "Is this artifact single-purpose with no dead code, commented-out blocks, or bloat?"
- Threshold: PASS = LLM rates ≥ 7/10 on terseness; < 7 = WARNING (not FAIL)

## Skill Structure

```
skills/validate-artifact/
  SKILL.md        ← skill definition (frontmatter + instructions)
```

Skill invocation: `/validate-artifact <path>`

Output format:
```
Validating: <path>
[PASS|FAIL] Repo-agnostic
  ✓ No absolute paths
  ✗ Contains hardcoded path: /home/alfredo/... (line 12)
[PASS|WARN|FAIL] Dependency-complete
  ✓ bash — standard tool
  ✗ Missing: ~/.claude/scripts/helper.sh
[PASS|WARN] Terse
  ✓ Single-purpose (8/10)

Overall: PASS | FAIL
```

## Patterns to Mirror

Existing skill structure: `~/.claude/skills/humanizer/SKILL.md` — single `SKILL.md` file per skill directory.

| Category | Source | Pattern |
|---|---|---|
| Skill dir layout | `~/.claude/skills/humanizer/` | One directory per skill, containing `SKILL.md` |
| Output style | PRD constraint | Terse — structured PASS/FAIL/WARN per criterion |

## Files to Change

| File | Action | Why |
|---|---|---|
| `skills/validate-artifact/SKILL.md` | CREATE | The skill definition — lives in repo, synced by M3 |
| `.claude/prds/user-wide-claude-portability.prd.md` | UPDATE M4 row | Mark `in-progress`, add plan path |
| `.claude/plans/portability-loop-runbook.md` | UPDATE M4 row | Mark `done` |

## Tasks

### Task 1: Write `SKILL.md` frontmatter and trigger

- **Action**: Create `skills/validate-artifact/SKILL.md` with:
  - `name: validate-artifact`
  - `description`: one-line description of what it validates
  - `trigger`: explicit `/validate-artifact <path>` call or invoked by M5 `/promote-artifact`
  - Argument: `<path>` — absolute or relative path to a file or directory
- **Validate**: File parses as valid SKILL.md; skill appears in skill list.

### Task 2: Static grep checks (repo-agnostic)

- **Action**: Write the SKILL.md instructions for the grep-based checks:
  ```
  Run: grep -rn "/home/" <path>              → FAIL if any match
  Run: grep -rn "/Users/" <path>             → FAIL if any match
  Run: grep -rni "alfredo" <path>            → FAIL if any match
  Run: grep -rEn "sk-[A-Za-z0-9]+" <path>   → FAIL if any match (secret pattern)
  Run: grep -rEn "ghp_[A-Za-z0-9]+" <path>  → FAIL if any match
  ```
  Report each match with file:line for actionable output.
- **Validate**: Test against a file containing `/home/alfredo/` → FAIL; test against a clean file → PASS.

### Task 3: Dependency scan (dependency-complete)

- **Action**: Write instructions to:
  1. Grep for `source`, `./script`, shell `require`, Python `import` statements in the artifact
  2. For each reference: check if it's a standard Linux tool OR exists under `~/.claude/`
  3. Report missing dependencies as FAIL; unresolvable (network-dependent) as WARN
- **Validate**: Test against a skill that sources a missing helper → FAIL.

### Task 4: LLM terseness assessment

- **Action**: Write instructions that prompt the LLM to rate terseness 1-10 and list any bloat found. WARN if < 7, PASS if ≥ 7. Include the rating in output.
- **Validate**: Test against a skill with commented-out dead code → WARN; against a clean skill → PASS.

### Task 5: Overall verdict and exit behavior

- **Action**: Define overall verdict rules:
  - Any FAIL in repo-agnostic or dependency-complete → Overall FAIL
  - Only WARNs → Overall WARN (promote can proceed with confirmation)
  - All PASS → Overall PASS
  - Skill exits non-zero on FAIL so M5 `/promote-artifact` can gate on it
- **Validate**: `/validate-artifact ~/.claude/skills/humanizer/` → PASS on a known-clean skill.

## Validation

```bash
# Clean artifact → PASS
/validate-artifact ~/.claude/skills/humanizer/

# Artifact with absolute path → FAIL
echo "/home/alfredo/test" > /tmp/test-artifact.md
/validate-artifact /tmp/test-artifact.md

# Artifact with missing dependency → FAIL
echo "source ~/.claude/scripts/nonexistent.sh" > /tmp/dep-test.md
/validate-artifact /tmp/dep-test.md
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| False positives on grep (e.g., a skill about `/home/` directory management) | Low | Allow `# validate-artifact: ignore-line` inline suppression comment |
| LLM terseness rating is subjective and inconsistent | Medium | Use terseness only as WARN, never FAIL; rating is informational |
| Skill not installed to `~/.claude/skills/` on first use | Medium | M5 `/promote-artifact` calls validate-artifact directly from repo path before install |

## Acceptance

- [ ] `skills/validate-artifact/SKILL.md` exists in repo under `skills/`
- [ ] `/validate-artifact <clean-skill-path>` returns PASS overall
- [ ] `/validate-artifact <path-with-absolute-path>` returns FAIL on repo-agnostic
- [ ] `/validate-artifact <path-with-missing-dep>` returns FAIL on dependency-complete
- [ ] Output format is structured (criterion-per-line, PASS/FAIL/WARN labels)
- [ ] PRD M4 row updated to `in-progress` with plan path
