---
name: validate-artifact
description: Validate a user-wide Claude artifact for portability (no machine-specific content), dependency completeness, and terseness before promotion.
triggers:
  - /validate-artifact
args:
  - name: path
    description: Absolute or relative path to a file or directory to validate.
    required: true
---

# validate-artifact

Validates `<path>` against three criteria. Called standalone or by `/promote-artifact` before copying.

## Invocation

```
/validate-artifact <path>
```

`<path>` may be a file or directory. Relative paths are resolved from CWD.

---

## Step 1 — Repo-agnostic (static grep)

Run each grep against `<path>` (use `-rn` for directories, `-n` for files):

```bash
grep -rn  "/home/"          <path>          # validate-artifact: ignore-line
grep -rn  "/Users/"         <path>          # macOS home path
grep -rni "<your-username>" <path>          # hardcoded username — substitute actual login  # validate-artifact: ignore-line
grep -rEn "sk-[A-Za-z0-9]+" <path>         # OpenAI-style secret
grep -rEn "ghp_[A-Za-z0-9]+" <path>        # GitHub PAT
grep -rEn "xoxb-[A-Za-z0-9-]+" <path>      # Slack token
```

Lines containing `# validate-artifact: ignore-line` are exempt from all grep checks.

- Any match → **FAIL** — report each as `✗ <pattern>: <file>:<line> — <matched text>`
- No matches → **PASS** — report `✓ No machine-specific content detected`

## Step 2 — Dependency-complete

**Static scan:** grep `<path>` for dependency references:
- Shell: `source `, `. /`, `bash `, `python3 `, shell commands on PATH
- Markdown skill references: tool names, script invocations

For each referenced item, classify as one of:
- **Standard Linux tool** (`bash`, `python3`, `git`, `curl`, `jq`, `sha256sum`, `find`, `grep`, `sed`, `awk`, `sort`, `cp`, `mkdir`, `chmod`) → PASS
- **Exists under `~/.claude/`** → PASS
- **Not found** → FAIL — report `✗ Missing dependency: <reference>`
- **Network/external** (URLs, APIs) → WARN — report `⚠ External dependency: <reference>`

**LLM judgment:** After the static scan, assess: "Does this artifact reference tools, files, commands, or environment variables that might not exist on a fresh Linux machine with only Claude Code installed?"

- Any unresolved reference found → FAIL
- Uncertain/network-dependent → WARN
- Everything resolvable → PASS

## Step 3 — Terse

LLM assessment: Rate this artifact on terseness 1–10.
- Single-purpose, no dead code, no commented-out blocks, no padding prose → 8–10
- Minor bloat (redundant comments, unused sections) → 5–7
- Significant bloat (dead code, duplicated logic, multi-purpose without clear separation) → 1–4

Report: `Terseness: <N>/10 — <one-line rationale>`

- Rating ≥ 7 → **PASS**
- Rating < 7 → **WARN** (non-blocking; promote can proceed with confirmation)

---

## Output Format

```
Validating: <path>

[PASS|FAIL] Repo-agnostic
  ✓ No machine-specific content detected
  — or —
  ✗ /home/: path/to/file.md:12 — "/home/<user>/.claude/..."  # validate-artifact: ignore-line

[PASS|WARN|FAIL] Dependency-complete
  ✓ bash — standard tool
  ✗ Missing dependency: ~/.claude/scripts/helper.sh
  ⚠ External dependency: https://api.example.com

[PASS|WARN] Terse
  ✓ Terseness: 9/10 — single-purpose, no dead code

Overall: PASS | WARN | FAIL
```

---

## Verdict Rules

| Condition | Overall |
|---|---|
| Any FAIL in Repo-agnostic or Dependency-complete | **FAIL** |
| No FAILs, at least one WARN | **WARN** |
| All PASS | **PASS** |

FAIL exits non-zero so `/promote-artifact` can gate on it.
WARN exits 0 — `/promote-artifact` will prompt for confirmation before continuing.
