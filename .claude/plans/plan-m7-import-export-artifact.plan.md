# Plan: Rename promote-artifact → import-artifact; guard against self-export; add export-artifact skill

## Summary
`promote-artifact` actually pulls artifacts *from* `~/.claude/` *into* the repo (confirmed by reading its SKILL.md) — "promote" was the wrong verb. Rename it to `import-artifact` to match its real direction, update every cross-reference, and add a hard guard (rule + hook) so this repo-development meta-tool can never accidentally become a synced, portable artifact. Then scaffold a new `export-artifact` skill (repo → `~/.claude/`, the true inverse of `import-artifact`) via `/skill-creator:skill-creator`, with the same self-export guard and a deferred stub for the "thoroughly tested" gate.

## Decisions (confirmed with user)
- Guard both `import-artifact` and `export-artifact` in the deny-list — both write to `manifest.yaml` and carry the same accidental-export risk.
- `export-artifact` auto-registers a missing manifest entry (mirrors `import-artifact`'s existing Step 5), rather than refusing to export.

## Patterns to Mirror
| Category | Source | Pattern |
|---|---|---|
| Skill structure | `.claude/skills/promote-artifact/SKILL.md:1-19` | YAML frontmatter (`name`, `description`, `triggers`, `args`) + numbered `## Step N` sections |
| Manifest write | `.claude/skills/promote-artifact/SKILL.md:76-101` | Read `manifest.yaml` with `yaml.safe_load`, append entry only if `name` not already present, re-dump with `sort_keys=False` |
| Hook contract | Context7 `/websites/code_claude` "hooks-guide" | PreToolUse hook reads JSON from stdin, inspects `.tool_input.file_path` / `.tool_input.new_string` (Edit) or `.tool_input.content` (Write) via `jq`, `exit 2` + stderr message blocks, `exit 0` allows |
| Test style | `.claude/tests/scripts/open-gh-pr.test.sh:1-25` | `set -euo pipefail`, `run_test()` pass/fail counter, exits 0/1, no external test framework |
| Doc gotchas | `CLAUDE.md:54` (project) | Terse bullet list documenting sync-system footguns |

No existing project-level `.claude/rules/` directory — this repo's own `CLAUDE.md` is already the authoritative, always-loaded instruction file, so the new rule goes there rather than inventing a new rules directory (YAGNI).

## Files to Change
| File | Action | Why |
|---|---|---|
| `.claude/skills/promote-artifact/` → `.claude/skills/import-artifact/` | RENAME (`git mv`) | Directory name follows the corrected semantics |
| `.claude/skills/import-artifact/SKILL.md` | UPDATE | `name: import-artifact`, `triggers: /import-artifact`, rewrite description/body to reflect "user-wide → repo" direction |
| `.claude/skills/validate-artifact/SKILL.md:14,107,108` | UPDATE | Replace `/promote-artifact` mentions with `/import-artifact` |
| `docs/RUNBOOK.md:40-50,65` | UPDATE | "Promote a Local-Only Artifact" section + drift-recovery step now reference `/import-artifact` |
| `docs/CONTRIBUTING.md:9,41-42,53,59` | UPDATE | Prereqs, slash-command table, test checklist, "Adding a New Artifact" steps |
| `CLAUDE.md:18-19,33` (project) | UPDATE | Artifact Lifecycle table + Key Files table; add `export-artifact` rows; add new Gotchas/rule bullet (see below) — edit on top of the currently uncommitted working changes, don't revert them |
| `.claude/settings.json` | UPDATE | Add `hooks.PreToolUse` entry for the new guard script, preserving existing `enabledPlugins` |
| `.claude/scripts/guard-manifest-skills.sh` | CREATE | PreToolUse hook script: blocks Edit/Write to `manifest.yaml` that adds `import-artifact` or `export-artifact` under `skills:` |
| `.claude/tests/scripts/guard-manifest-skills.test.sh` | CREATE | Self-checking test mirroring existing `.test.sh` convention |
| `.claude/skills/export-artifact/` | CREATE (via `/skill-creator:skill-creator`) | New skill: repo → `~/.claude/` export, gated on manifest registration (auto-register if missing) + deferred "thoroughly tested" stub |
| `.claude/plans/*.md`, `.claude/prds/*.md` | NO CHANGE | Historical planning records referencing the old name — left as-is, not rewritten |

## Tasks

### Task 1: Rename promote-artifact → import-artifact
- **Action**: `git mv .claude/skills/promote-artifact .claude/skills/import-artifact`. Edit the moved `SKILL.md`: frontmatter `name`/`triggers`, and reframe the top description from "install locally and into the repo" to something accurate like "Import a user-wide `~/.claude` artifact into this repo (and register it in `manifest.yaml`) so it becomes version-controlled and portable to other machines." Update all internal `/promote-artifact` self-references (git commit messages, PR title template, branch name `promote/<type>/<name>` → `import/<type>/<name>`).
- **Mirror**: Existing frontmatter/step structure (Patterns table).
- **Validate**: `ls .claude/skills/import-artifact/SKILL.md && ! test -d .claude/skills/promote-artifact`

### Task 2: Propagate the rename across docs
- **Action**: Update `validate-artifact/SKILL.md`, `docs/RUNBOOK.md`, `docs/CONTRIBUTING.md`, and project `CLAUDE.md` per the Files table — every `/promote-artifact` reference becomes `/import-artifact`, and `.claude/skills/promote-artifact/` path mentions become `.claude/skills/import-artifact/`.
- **Mirror**: Existing table row / bullet formatting in each file.
- **Validate**: `grep -rn "promote-artifact" . --include="*.md" --include="*.yaml"` returns only the historical `.claude/plans/`/`.claude/prds/` matches.

### Task 3: Add the "never export" rule to CLAUDE.md
- **Action**: Add a bullet under this project's `CLAUDE.md` Gotchas (or a small new section): *"`import-artifact` and `export-artifact` MUST NOT appear in `manifest.yaml`'s `skills:` list — they are repo-development meta-tools, not portable end-user skills. Enforced by a PreToolUse hook (`.claude/scripts/guard-manifest-skills.sh`)."*
- **Mirror**: `CLAUDE.md:54` bullet style.
- **Validate**: Manual read-through; no automated check for prose.

### Task 4: Write the guard hook script + register it
- **Action**: `.claude/scripts/guard-manifest-skills.sh` — reads stdin JSON, extracts `file_path` and (`new_string` or `content`) via `jq`, no-ops (`exit 0`) unless `file_path` ends in `manifest.yaml`; if it matches, greps the proposed content for a `skills:` block containing `name: import-artifact` or `name: export-artifact`; if found, `echo ... >&2; exit 2`. Register it in `.claude/settings.json` under `hooks.PreToolUse` with `"matcher": "Edit|Write"`, command `"\"$CLAUDE_PROJECT_DIR\"/.claude/scripts/guard-manifest-skills.sh"` — merge into the existing JSON, don't clobber `enabledPlugins`.
- **Mirror**: Context7 hook examples (protect-files.sh pattern); this repo's Command Scripts convention of centralizing scripts under `.claude/scripts/` even though that rule is technically scoped to command-backing scripts (kept for one canonical scripts directory rather than adding a `.claude/hooks/` dir for a single file).
- **Validate**: `bash -n .claude/scripts/guard-manifest-skills.sh`; manual dry run piping a fabricated Edit payload that adds `name: import-artifact` under `skills:` and confirming exit code 2.

### Task 5: Test the guard hook
- **Action**: `.claude/tests/scripts/guard-manifest-skills.test.sh` — feeds synthetic PreToolUse JSON payloads: (a) unrelated file → allow (exit 0); (b) manifest.yaml edit adding `import-artifact` → block (exit 2); (c) manifest.yaml edit adding `export-artifact` → block (exit 2); (d) manifest.yaml edit adding an unrelated skill name → allow (exit 0).
- **Mirror**: `.claude/tests/scripts/open-gh-pr.test.sh:1-25` (`run_test` counter, exit 0/1 summary).
- **Validate**: `bash .claude/tests/scripts/guard-manifest-skills.test.sh`

### Task 6: Scaffold export-artifact via skill-creator
- **Action**: Invoke `/skill-creator:skill-creator` conversationally to build `.claude/skills/export-artifact/SKILL.md`. Spec to feed it:
  - Invocation: `/export-artifact <path>` where `<path>` is a repo artifact under `.claude/<type>s/`.
  - Step 1 — Detect type (mirror `import-artifact`'s heuristics table).
  - Step 2 — **Guard**: refuse immediately if artifact name is `import-artifact` or `export-artifact` (defense-in-depth alongside the hook — the hook covers the manifest write path, this covers direct invocation).
  - Step 3 — Check `manifest.yaml` for an existing entry by name; if missing, **auto-register** it (same `yaml.safe_load` → append → dump pattern as `import-artifact` Step 5).
  - Step 4 — **"Thoroughly tested" gate — deferred.** Add an explicit `## Deferred: Definition of "thoroughly tested"` section in the SKILL.md documenting this as a known stub (not silently missing): for now, no test/eval verification is performed; the gate always passes once Step 3's manifest registration succeeds.
  - Step 5 — Copy repo artifact → `~/.claude/<type>s/<name>` (mirror `sync.sh`'s single-artifact copy/SHA-256-compare logic).
  - Have skill-creator generate its standard eval suite (via its `run_eval.py` / grader-analyzer-comparator agents) with test scenarios: successful export of a normal artifact; auto-register-then-export of an unregistered artifact; blocked export of `import-artifact`; blocked export of `export-artifact`; no-op when already in sync.
- **Mirror**: `import-artifact`'s Step 1–5 structure; skill-creator's own documented create-skill workflow.
- **Validate**: Whatever skill-creator's harness reports (eval pass rate) — no separate command needed beyond what the tool produces.

### Task 7: Update Files/Lifecycle tables in CLAUDE.md and CONTRIBUTING.md for export-artifact
- **Action**: Add `export-artifact` rows to CLAUDE.md's Artifact Lifecycle and Key Files tables, and CONTRIBUTING.md's slash-command table, matching the existing row style.
- **Mirror**: `CLAUDE.md:16-20,33` current table rows.
- **Validate**: Manual read-through.

## Validation
```bash
git mv .claude/skills/promote-artifact .claude/skills/import-artifact   # Task 1 (part of implementation, not a check)
grep -rn "promote-artifact" . --include="*.md" --include="*.yaml"       # only historical plans/prds should remain
bash -n .claude/scripts/guard-manifest-skills.sh
bash .claude/tests/scripts/guard-manifest-skills.test.sh
python3 -c "import yaml; yaml.safe_load(open('manifest.yaml')); print('manifest: OK')"
bash -n sync.sh && echo "sync.sh: OK"
```

## Risks
| Risk | Likelihood | Mitigation |
|---|---|---|
| Hook regex/jq parsing is too naive and either misses a sneaky manifest edit or false-positives on unrelated YAML | Medium | Keep the guard string-match on `manifest.yaml`'s `skills:` block specifically (not a blanket file-content grep), and cover both Edit and Write tool_input shapes in the test script |
| Renaming breaks a reference I didn't find via grep (e.g. inside a `.claude/plans/*.md` that's still "active", not purely historical) | Low | The grep in Task 2's validation step will catch any surviving reference; decide case-by-case whether an active plan file should also be updated |
| `export-artifact`'s deferred "thoroughly tested" stub could be mistaken later for a real quality gate | Medium | Explicit `## Deferred` section in its SKILL.md makes the gap visible rather than silent |
| Hook script errors out (e.g. `jq` missing) and silently fails open (`exit 0` by default on script crash under `set -e` without a trap) | Low | Use `set -euo pipefail` deliberately so an unexpected error aborts non-zero rather than silently allowing; verify this still surfaces as a block, not a crash Claude ignores |

## Acceptance
- [ ] `.claude/skills/promote-artifact/` no longer exists; `.claude/skills/import-artifact/` exists with corrected description
- [ ] No remaining `/promote-artifact` references outside historical `.claude/plans/`/`.claude/prds/`
- [ ] `CLAUDE.md` documents the no-export rule for `import-artifact` and `export-artifact`
- [ ] `.claude/scripts/guard-manifest-skills.sh` blocks manifest edits adding either name to `skills:`, registered via `.claude/settings.json` PreToolUse hook
- [ ] `.claude/tests/scripts/guard-manifest-skills.test.sh` passes
- [ ] `.claude/skills/export-artifact/` exists, scaffolded via skill-creator, with evals covering the five scenarios in Task 6
- [ ] `manifest.yaml`'s `skills:` list remains `[]` (or contains neither meta-tool) after all changes
