# Plan: Lazy-Loading Rule System — integrate into `user-wide-claude-a`

## Summary

Bring the user-wide lazy-loading rule system (`~/.claude/rules/`, `~/.claude/lazy/rules/`, `~/.claude/hooks/`) under this repo's version control and sync pipeline, and fix the defects found in the 2026-09-08/09 audit. The centrepiece is a single generalized `PreToolUse` rule injector that replaces the two existing per-edit injectors, eliminating their unbounded token cost and their after-the-fact timing.

## User Story

As the operator of a multi-machine Claude Code setup,
I want my rule-loading system version-controlled and to load rules *whenever their trigger matches* — including on writes, edits and commands — at a bounded token cost,
So that rules are neither silently absent when they apply nor re-billed on every edit.

## Problem → Solution

**Current:** 24 user-wide rules and 12 hooks live in an unversioned `~/.claude`. Native `paths:` gating is Read-only, so no rule can govern an edit. Two injectors patch around this with no dedup, costing ~2,150 tok per JS/TS edit (~86,000 over 40 edits) and firing *after* the write. Five proxy stubs have no mechanical backing at all.

**Target:** All rule/lazy/hook artifacts tracked in this repo and installed by `sync.sh`. One `PreToolUse` injector loads any rule whose declared trigger matches — path glob, tool, or command — before the action, deduped per `(rule, subject)`, at ~6,450 tok on the same 40-edit trace.

## Metadata

- **Complexity**: **XL** — split into 6 phases below; Phases 1-3 are the viable first increment
- **Source PRD**: N/A (derived from `docs/rule-loading-audit.md`)
- **PRD Phase**: N/A
- **Estimated Files**: ~24 (3 created, ~8 modified, ~13 deleted)

---

## Mandatory Reading

| Priority | File | Lines | Why |
|---|---|---|---|
| **P0** | `docs/rule-loading-audit.md` | all | Every finding, measurement and correction this plan acts on. §0 governs all mechanism choices |
| **P0** | `sync.sh` | 70-80, 172-215, 494-505, 545-560 | `yaml_get_names`, `install_file`, the `rules` install block and `scan_local_only` — the exact patterns to copy for `hooks`/`lazy` |
| **P0** | `manifest.yaml` | 25-45 | Section shape; `scripts` shows the `executable: true` flag that `hooks` needs |
| **P1** | `~/.claude/hooks/ecc-typescript-rule-inject.py` | 1-46 | The injector contract to generalize (payload parse → filter → read bodies → `hookSpecificOutput`) |
| **P1** | `~/.claude/hooks/confirm-before-test-changes-rule-inject.py` | 12-24 | The second injector; its `COVERED_SUFFIXES` is the superset causing double-billing |
| **P1** | `.claude/PRPs/examples/throttle_demo.py` | all | Runnable reference for the three dedup strategies; `per_subject()` is what M5 uses |
| **P2** | `~/.claude/rules/rule-authoring-format.md` | all | Existing authoring convention the new `on:` block must extend, not contradict |
| **P2** | `~/.claude/scripts/gh-branch-guard.sh` | 1-40 | Broken `deny()` to fix in Phase 5 |

## External Documentation

| Topic | Source | Key Takeaway |
|---|---|---|
| Hook events, schema, path variables | `code.claude.com/docs/en/hooks.md` | `PreToolUse` can both inject `additionalContext` and deny. `${CLAUDE_PROJECT_DIR}` available |
| Path-scoped rules | `code.claude.com/docs/en/memory.md` | `paths:` frontmatter gates loading — **verified Read-only in practice** (audit App. B) |
| Hooks in subagents | `code.claude.com/docs/en/hooks.md` | Hooks run inside subagents with `agent_id`/`agent_type` on the payload — unlike `paths:` gating |
| Long-context instruction following | Robinette et al., Findings EACL 2026, pp. 4855-4884 | **Checked and does not apply** — all six strategies are reactive; the 79% is from a model-architecture change. Do not cite it to justify periodic re-firing (audit §8) |

---

## Patterns to Mirror

### INJECTOR_CONTRACT
```python
# SOURCE: ~/.claude/hooks/ecc-typescript-rule-inject.py:15-42
def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)                      # ← REPLACE: must warn loudly (audit #6)
    file_path = payload.get("tool_input", {}).get("file_path", "")
    if Path(file_path).suffix not in JS_TS_SUFFIXES:
        sys.exit(0)
    ...
    output = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",   # ← REPLACE: "PreToolUse"
            "additionalContext": "\n\n---\n\n".join(sections),
        }
    }
    print(json.dumps(output))
    sys.exit(0)
```

### DEDUP_PER_SUBJECT
```python
# SOURCE: .claude/PRPs/examples/throttle_demo.py
def per_subject(kind: str, subject: str, session_id: str) -> bool:
    key = hashlib.sha1(subject.encode()).hexdigest()[:12]
    return once(f"{kind}--{key}", session_id)   # O_CREAT|O_EXCL marker
```

### SYNC_INSTALL_LOOP
```bash
# SOURCE: sync.sh:498-502
echo "--- rules ---"
names=$(yaml_get_names rules) || { echo "ERROR: manifest parse failed for rules" >&2; exit 1; }
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  install_file "$REPO_DIR/.claude/rules/$name" "$CLAUDE_DIR/rules/$name" "rules/$name"
done <<< "$names"
```

### MANIFEST_SECTION
```yaml
# SOURCE: manifest.yaml:25-27, 33-44
rules:
  - name: gh-issue-rules.md
scripts:
  - name: vm-cleanup.sh
    executable: true          # ← hooks section needs this flag
```

### DRIFT_SCAN
```bash
# SOURCE: sync.sh:553
scan_local_only rules    "$CLAUDE_DIR/rules"
```

### BROKEN_DENY (fix in Phase 5)
```bash
# SOURCE: ~/.claude/scripts/gh-branch-guard.sh:21-22
deny() {
  echo "{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$1\"}"
  exit 0        # ← exit 0 means ALLOW; decision must nest under hookSpecificOutput
}
```

---

## Architecture

**Approach.** Add `hooks` and `lazy` sections to the existing manifest/sync pipeline rather than inventing a parallel mechanism, then replace the two per-edit injectors with one trigger-driven `PreToolUse` injector (`lazy-rule-inject.py`) that reads an `on:` frontmatter block.

**Alternatives rejected:**
- *Package as a plugin* — viable (`${CLAUDE_PLUGIN_ROOT}` confirmed documented) but the user has deferred it; revisit once this and the repo are merged.
- *Separate repo at `~/repos/lazy`* — superseded by the same decision.
- *`git init ~/.claude`* — solves versioning only, forces a hazardous `.gitignore` (plugin cache, session transcripts, a `settings.local.json` that has historically held a live PAT), and gives no portability.
- *Patch the two injectors in place* — the fix is a strict subset of M5; doing both duplicates work.

**Scope:** manifest/sync support for `hooks` + `lazy`; import current artifacts; build and cut over to `lazy-rule-inject.py`; reclassify every rule by trigger; fix the enforcement bugs; delete dead weight.

**NOT Building:**
- A plugin package (deferred by the user)
- Any change to `~/.claude/plugins/**` or vendored ECC content beyond deleting rules we own
- A compliance *detector* — the EACL finding points at detection, but that is a separate project (audit §8)
- `promote-artifact` support for the new types — nice-to-have, listed as a Phase 6 stretch
- Migration of `lazy/agents/**` (out of scope; rules only)

---

## Files to Change

| File | Action | Justification |
|---|---|---|
| `manifest.yaml` | UPDATE | Add `hooks:` and `lazy:` sections; extend `rules:` to the full promoted set |
| `sync.sh` | UPDATE | Install loops + drift scan for two new types; `hooks` needs `chmod +x` |
| `.claude/hooks/tests/test_lazy_rule_inject.py` | CREATE **first** | First real test of a live hook (audit #11: only dead code is tested). Written and failing before the injector — Task 2.1 (RED) |
| `.claude/hooks/lazy-rule-inject.py` | CREATE **second** | The M5 unified `PreToolUse` injector — Task 2.2 (GREEN) |
| `.claude/lazy/rules/*.md` | CREATE | Promoted lazy bodies |
| `.claude/rules/*.md` | UPDATE | Promoted user-wide rules, reclassified |
| `~/.claude/settings.json` | UPDATE | Register the new hook; deregister the two retired injectors; add timeouts |
| `~/.claude/hooks/ecc-typescript-rule-inject.py` | DELETE | Superseded by M5 |
| `~/.claude/hooks/confirm-before-test-changes-rule-inject.py` | DELETE | Superseded by M5 |
| `~/.claude/hooks/plans-index-guard.py` | DELETE | Registered nowhere (audit #11) |
| `~/.claude/hooks/hooks.json` | DELETE | 37 KB, 21 entries, dead (audit #12) |
| `~/.claude/hooks/README.md` | DELETE | Documents ~20 hooks that don't run |
| `~/.claude/rules/{pr-review,context7,knowledge-ops-defaults}.md` | DELETE | Redundant with skills/plugins (audit §3) |
| `.claude/rules/web-research-tool-selection.md` | DELETE | Verbatim duplicate of the user-wide copy |
| `~/.claude/scripts/gh-branch-guard.sh` | MOVE+UPDATE | → `.claude/hooks/`; fix `deny()` |
| `~/.claude/hooks/check-settings-json-secrets.sh` | UPDATE | Remove `\|\| true`; fail closed on missing `jq` |
| `docs/rule-loading-audit.md` | UPDATE | Record outcomes as phases land |

---

## Step-by-Step Tasks

### Phase 1 — Version control the surface (do this first; everything after is reversible)

**Task 1.1: Add `hooks` and `lazy` manifest sections**
- **ACTION**: Add two sections to `manifest.yaml`.
- **IMPLEMENT**: `hooks:` entries as `- name: <file>` + `executable: true` for `.sh`/`.py`. `lazy:` entries as `- name: rules/<file>.md` (nested path in the name, since `lazy/rules/` has depth). Also allow an optional `vendored: ecc@<version>` key on any entry (used by Task 1.3 for ECC-shipped files); `yaml_get_names` reads only `name`, so an extra key is inert to sync — it is documentation for the drift-recovery runbook, not behavior.
- **MIRROR**: `MANIFEST_SECTION`.
- **GOTCHA**: `yaml_get_names` (sync.sh:70-80) returns `item['name']` verbatim — a nested `rules/foo.md` name works only because `install_file` does `mkdir -p "$(dirname "$dest")"` (sync.sh:184). Verify that before relying on it.
- **VALIDATE**: `python3 -c "import yaml;d=yaml.safe_load(open('manifest.yaml'));print(d['hooks'],d['lazy'])"`

**Task 1.2: Add sync install loops**
- **ACTION**: Add `hooks` and `lazy` blocks to `sync.sh`.
- **IMPLEMENT**: Copy the `rules` block verbatim, substituting paths: `.claude/hooks/$name` → `$CLAUDE_DIR/hooks/$name`, `.claude/lazy/$name` → `$CLAUDE_DIR/lazy/$name`. Add `'hooks','lazy'` to the section list at sync.sh:123. Add `scan_local_only` lines for both.
- **MIRROR**: `SYNC_INSTALL_LOOP`, `DRIFT_SCAN`.
- **GOTCHA**: `install_file` uses `cp`, which does **not** preserve the executable bit reliably across filesystems. Hooks must be `chmod +x` after copy — `scripts` already faces this; check how it handles `executable: true` before writing new logic (DRY).
- **VALIDATE**: `bash sync.sh --dry-run` reports the new sections with `[MISSING]`, exit 0.

**Task 1.3: Import current artifacts into the repo**
- **ACTION**: Copy the live files from `~/.claude` into `.claude/`, then commit.
- **IMPLEMENT**: `rules/*.md` (all 24), `lazy/rules/**/*.md` (13), `hooks/*.py` + `*.sh` (the 10 live ones — **not** the 3 marked for deletion).
- **GOTCHA**: parts of `~/.claude/rules/ecc/**` are **vendored** — an ECC reinstall overwrites them. Run `diff -r` against the ECC source before importing and record ours-vs-vendored per file in `docs/` (audit #K). **Vendored does not mean excluded**: track vendored files too, with a `vendored: ecc@<version>` marker in the manifest entry, so `sync.sh`'s three-way SHA detection reports an ECC overwrite as `[DIVERGED]` with the repo copy as merge base — instead of the overwrite silently reverting any `on:` frontmatter or customization. Same pattern as `tdd-workflow/SKILL.md`'s `customized: true` note, but enforced by sync rather than by prose.
- **GOTCHA 2 — directory is not origin.** `ecc/common/hooks-todowrite-practices.md` lives in the ECC directory but is absent from every ECC cache version (user-owned, mtime 2026-08-24). Classify every `ecc/**` file by cache match, not path: the 213 skills/commands and 4 scripts below were checked that way; the `rules/ecc/**` and `lazy/rules/ecc/**` files were not until 2026-09-09, when the first one checked turned out to be misclassified. Re-run the check across all of them before importing.
- **VALIDATE**: `bash sync.sh --dry-run` now reports every entry as in-sync (no `[MISSING]`, no drift).

**Drift-check finding (2026-09-09), refining the scope of this task:** re-running `sync.sh --dry-run`'s local-only scan found **256 files** running outside this repo's tracking entirely — not the 1 an earlier, narrower grep had suggested. Breakdown by category and confirmed origin:

| Category | Count | Origin | Action |
|---|---:|---|---|
| `skills/` | 100 | **ECC-vendored** — confirmed via plain-file (non-symlink) matches in `~/.claude/plugins/cache/ecc/`, batch-installed 2026-08-21 | Exclude — not this repo's to track |
| `commands/` | 113 | Same ECC batch, same confirmation method | Exclude |
| `scripts/` | 20 | **Mixed** — see script-level breakdown below | Split: 4 exclude, 16 import |
| `rules/` | 23 | **Not ECC** — no cache match, no ECC branding; this project's own custom rules | **In scope for this task** — matches the plan's existing "all 24" figure (23 local-only + `pr-review.md`, itself slated for deletion in Phase 3) |

**Script-level breakdown** (20 total, classified by ECC-cache match + mtime clustering):

- **ECC-vendored, exclude (4):** `auto-update.js`, `harness-audit.js`, `setup-package-manager.js`, `skills-health.js` — all four match files in `~/.claude/plugins/cache/ecc/` and share the exact 2026-08-21 batch-install date as the vendored skills/commands above.
- **User-owned, import in this task (16):** `agent-token-monitor.py`, `default-branch.sh`, `gh-branch-guard.sh`, `github-mcp.sh`, `git-search-content.sh`, `git-worktrees-ahead.sh`, `git-worktrees-dirty.sh`, `git-worktrees.sh`, `lib-resolve-lan-host.sh`, `merge-default.sh`, `open-bash.sh`, `open-code-server.sh`, `open-smb-path.sh`, `restart-code-server.sh`, `tmux-ops-list-windows.sh`, `tmux-ops-move-window.sh` — no ECC-cache match, mtimes spread June–September (no batch clustering), consistent with independent, project-owned scripts. `gh-branch-guard.sh` is already separately in scope for Phase 5 (Task 5.1, its broken `deny()`); this import is a prerequisite for that fix landing under version control at all.

### Phase 2 — Retire the expensive injectors

> **Run this phase under `/tdd-workflow .claude/PRPs/plans/lazy-loading-system.plan.md`.** Tasks 2.1 and 2.2 are the RED and GREEN halves of one cycle and MUST NOT be reordered: the test is written and observed failing *before* the injector exists. Capture RED evidence (the failing run's output) and GREEN evidence (the same command passing) — the skill's Step 8 evidence report maps plan task → test target → RED → GREEN. Checkpoint-commit after each half; do not squash until the phase completes.

**Task 2.1 (RED): Write the failing hook test first**
- **ACTION**: Create `.claude/hooks/tests/test_lazy_rule_inject.py` **before** any injector code exists. This is the first real test of a live hook (audit #11: only dead code is tested today).
- **IMPLEMENT**: Cases — matching path fires; non-matching path silent; second call same subject silent; different subject fires; malformed payload exits 0 *and* writes stderr; missing rule dir exits 0.
- **GOTCHA 1**: Tests must point the marker dir at a temp path, or they pollute the real session throttle and pass spuriously on re-run.
- **GOTCHA 2**: RED must fail for the *right* reason. A bare `ModuleNotFoundError`/missing-file error proves only that the file is absent, not that the assertions are meaningful — exactly the vacuous-pass trap hit last session with the relative-path `vm-cleanup` test. Create a stub `lazy-rule-inject.py` that exits 0 emitting nothing, so every case fails on its own assertion.
- **VALIDATE (RED)**: `python3 -m pytest .claude/hooks/tests/ -q` — every case **fails**, each on its own assertion, none on an import or file-not-found error. Record this output as RED evidence.

**Task 2.2 (GREEN): Build `lazy-rule-inject.py`**
- **ACTION**: Replace the stub with the unified `PreToolUse` injector, changing nothing in the Task 2.1 tests.
- **IMPLEMENT**:
  1. Parse stdin payload; extract `tool_name`, `tool_input`, `session_id`.
  2. Derive the *subject*: `tool_input.file_path` for `Edit|Write|NotebookEdit|Read`, `tool_input.command` for `Bash`.
  3. Build the rule index: scan `~/.claude/rules/**/*.md` and `~/.claude/lazy/rules/**/*.md`, parse YAML frontmatter, collect any with an `on:` block.
  4. Match: `on.tools` contains `tool_name`, **and** (`on.paths` glob-matches the subject **or** `on.commands` prefix/glob-matches it).
  5. Dedup via `per_subject(rule_id, subject, session_id)`.
  6. Emit `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "\n\n---\n\n".join(bodies)}}`.
- **MIRROR**: `INJECTOR_CONTRACT` for the payload/output shape; `DEDUP_PER_SUBJECT` for throttling.
- **IMPORTS**: `json`, `sys`, `os`, `hashlib`, `tempfile`, `fnmatch`, `pathlib.Path`. YAML: prefer a hand-rolled frontmatter split over importing `yaml` — the hook runs on every edit and must stay fast; `sync.sh` already assumes `python3` + `yaml` exist, but a hook should not.
- **GOTCHA 1**: **`PreToolUse` supports `additionalContext` — confirmed empirically this session** (context-mode's `PreToolUse:Bash` guidance arrived that way). Do not assume it's PostToolUse-only.
- **GOTCHA 2**: The exact payload key for the session id is **unverified**. Log the raw payload once from a live invocation and confirm before relying on `session_id`; falling back to `os.getppid()` is unreliable (context-mode issue #298).
- **GOTCHA 3**: Never `except: sys.exit(0)` silently — write a one-line reason to stderr first (audit #6). Still exit 0: an injector must never block the tool.
- **VALIDATE (GREEN)**: `python3 -m pytest .claude/hooks/tests/ -q` — all Task 2.1 cases now pass, with no edits to the test file. Record as GREEN evidence. Then the smoke check: `echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.ts"},"session_id":"t1"}' | python3 .claude/hooks/lazy-rule-inject.py` emits JSON containing the TS rule bodies; a second identical run emits nothing.

**Task 2.3: Cut over**
- **ACTION**: Register the new hook, deregister the two old ones.
- **IMPLEMENT**: In `~/.claude/settings.json`, add a `PreToolUse` entry matching `Edit|Write|NotebookEdit|Bash|Read` for `lazy-rule-inject.py` with an explicit `timeout`; remove the two `PostToolUse` `Edit|Write` injector entries.
- **GOTCHA**: `settings.json` is guarded by `check-settings-json-secrets.sh` on `Edit|Write` — expect the hook to run. That is correct behavior, not an error.
- **VALIDATE**: Write a `.ts` file twice in a fresh session; rule content appears **before** the first write and not at all on the second. Confirm the retired injectors no longer fire.

**Task 2.4: Delete the retired injectors**
- **ACTION**: Remove both files and their manifest entries.
- **VALIDATE**: `bash sync.sh --dry-run` clean; a `.ts` edit still loads rules via M5 only.

### Phase 3 — Reclassify every rule by trigger

**Task 3.1: Classify all 24 rules**
- **ACTION**: For each, decide mechanism per audit §2's selection table.
- **IMPLEMENT**: Write the decision into a table in `docs/rule-loading-audit.md` §3. Rule of thumb: read-trigger + no fork requirement → keep `paths:`; write/command trigger, or must hold in forks → add `on:`; no matchable trigger → leave eager.
- **GOTCHA**: **§0 governs — `MUST`/`SHOULD`/`MAY` must not influence this.** Classify on trigger shape only.
- **SPLIT CLAUSE**: a file whose clauses have *different* trigger shapes is split into one file per shape **before** bucketing — the bucket is a property of a trigger, not of a filename, and forcing a mixed file into one bucket either loads untriggerable prose lazily (never seen) or keeps triggerable text eager (the cost this plan exists to remove). Known cases:
  - `authoring-conventions.md` (1,833 B): the Required heredoc-escaping clause → new file, M5 `on.commands` matching `gh issue|pr` / `git commit` / `<<'` heredocs; the Recommended KISS/YAGNI drafting clause → stays eager (~560 B).
  - `pr-base-branch.md` (539 B): "PRs MUST target `develop`" + the Advisory override → M5 `on.commands` `gh pr create`; "compare against `develop` first" → session-wide judgment, no trigger, stays eager (~200 B).
  - Any further mixed file found while classifying gets the same treatment — record the split in the §3 table as two rows.
- **VALIDATE**: Every rule lands in exactly one bucket, and no single file contains clauses from two buckets. Zero M2 proxies remain (Task 3.2 does the collapsing).

**Task 3.2: Collapse M2 proxies into M3**
- **ACTION**: Inline the five M2 proxy bodies back into their gated rule files. (An earlier revision said "six"; the audit's M2 table has exactly five collapse candidates — the other `lazy/rules/` bodies are hook-served, not proxied: `ask-before-test-changes` moves to M5 in Phase 2, `plan` and `research-ops` belong to the injectors deferred in Task 6.3, and `ecc/typescript/*` is handled in Task 3.4.)
- **IMPLEMENT**: For `coding-principles` (997 B), `command-scripts` (564 B), `claude-md-self-reference` (941 B), `two-pass-artifacts` (1,753 B), `hook-path-convention` (478 B): merge body into the `paths:`-gated file, delete the `lazy/rules/` copy and its manifest entry.
- **GOTCHA**: `hook-path-convention` *also* needs an `on:` block — it governs *writing* a hook entry, which `paths:` cannot see.
- **VALIDATE**: Read a matching file; full rule text arrives with no "go read X" indirection. Afterwards `lazy/rules/` holds only hook-served bodies: `ask-before-test-changes`, `plan`, `research-ops`, `ecc/typescript/*` — no file there is referenced by a `paths:`-gated proxy.

**Task 3.3: Delete redundant eager rules**
- **ACTION**: Remove `pr-review.md`, `context7.md`, `knowledge-ops-defaults.md` and the duplicate repo `web-research-tool-selection.md`. **Not** the two eager `ecc/common/*` (reclassified 2026-09-09, audit §3 correction): `git-workflow.md` → M5 `on.commands` (`git commit`, `gh pr create`) in Task 3.1; `hooks-todowrite-practices.md` → keep eager, but first check whether `TodoWrite` still exists in the harness — it is absent from the current session's tool list, and if it is gone the rule is dead content and *then* gets deleted.
- **SUB-CASES**: `pr-review` and `knowledge-ops-defaults` are *fold-then-delete* — content moves into the matching skill first, and the ECC plugin (which owns `knowledge-ops`) is currently disabled, so the fold target must be enabled to do it. `context7` is *delete-when-unblocked* (next GOTCHA).
- **GOTCHA**: `context7.md` is only redundant *while* the context7 plugin is installed — and it failed to connect this session (`AUTH_HEADER_REJECTED`). Confirm the plugin is working before deleting the rule, or the guidance disappears entirely.
- **VALIDATE**: Session-start eager load drops by ≥4,180 B (was 5,260 before the `ecc/common/*` reclassification). Measure with the audit §3 byte script.

**Task 3.4: Fix the dangling ECC links**
- **ACTION**: Repair the first line of all 5 `lazy/rules/ecc/typescript/*.md`.
- **IMPLEMENT**: `> This file extends [common/X.md](../common/X.md)` resolves to `lazy/rules/ecc/common/`, which does not exist. Either create that dir or repoint to `~/.claude/rules/ecc/common/X.md`.
- **VALIDATE**: Every relative link resolves to an existing file.

### Phase 4 — Investigate the unexplained

**Task 4.1: Determine why `hook-path-convention.md` never fires**
- **ACTION**: Isolate the cause. The glob-collision theory is **refuted** (audit §4-A: five rules sharing `**/*.py` all fired together).
- **IMPLEMENT**: Bisect — read a `settings.local.json` (its second glob) in a fresh session; test the rule with a unique glob; compare its frontmatter byte-for-byte against a rule that does fire.
- **GOTCHA**: Dedup is per-session — each hypothesis needs a **fresh session**, or the first test poisons the rest.
- **VALIDATE**: Either the rule fires, or the cause is documented as a reproducible harness bug.

### Phase 5 — Enforcement fixes

**Task 5.1: Fix `gh-branch-guard.sh`**
- **ACTION**: Make `deny()` actually deny; relocate to `.claude/hooks/`.
- **IMPLEMENT**: Emit `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}`. Update the `settings.json` path.
- **MIRROR**: `BROKEN_DENY` shows exactly what to replace.
- **GOTCHA**: Its current location violates this repo's own `hooks.md` rule (scripts in `scripts/`, not `hooks/`) — the move fixes both defects at once.
- **VALIDATE**: `gh pr create --base main` is blocked. Verify with a dry command that would fail anyway, not a real PR.

**Task 5.2: Fail closed in the secret scanner**
- **ACTION**: Remove `|| true` from every `jq` call in `check-settings-json-secrets.sh`; deny when `jq` is absent.
- **GOTCHA**: Currently an empty extraction `exit 0`s, so a missing `jq` silently disables the guard on the exact file class that once held a live PAT.
- **VALIDATE**: Temporarily shadow `jq` with a failing stub; confirm the hook denies rather than passes.

### Phase 6 — Cleanup and stretch

**Task 6.1**: Delete `plans-index-guard.py`, `hooks/hooks.json`, `hooks/README.md`, `hooks/tests/` (the old suite testing only dead code), `noop-bash-guard.py` if still unwanted. **VALIDATE**: no `settings.json` entry references a deleted file.

**Task 6.2 (stretch)**: Extend `promote-artifact` to accept `rule | hook | lazy` so future promotion is repeatable rather than manual.

**Task 6.3 (decision, deferred)**: Decide whether the four surviving one-off injectors fold into M5.
- **CONTEXT**: Phase 2 retires only 2 of the 6 injectors in `~/.claude/hooks/`. `enterplanmode-rule-inject.py`, `research-ops-rule-inject.py`, `research-ops-promptsubmit.py` and `research-ops-tooling-gate.py` are the same class of thing — a hook that loads rule text on a trigger — and survive as one-offs. The acceptance criterion "one injector replaces both old ones" is met while "one injector" as a system property is not.
- **WHY DEFERRED**: M5 as specced matches on `tool_name` + path/command. `enterplanmode-rule-inject.py` triggers on a *tool* with no subject, and the `research-ops` trio spans `UserPromptSubmit` plus a tooling gate — neither fits the `(rule, subject)` dedup key without extending the `on:` schema. Deciding before M5 is live and measured would be designing on assumption.
- **ALSO OPEN**: the `EnterPlanMode` matcher was only *partially* refuted last session (`EnterPlanMode` is a real tool in the current harness) — needs a live retest before anything is rewritten or folded.
- **DECIDE**: after Phase 2's manual validation passes, pick one: (a) extend `on:` with a `tools`-only trigger and a per-session dedup fallback, fold all four; (b) fold only `enterplanmode-rule-inject.py`, leave `research-ops` as a coherent subsystem; (c) leave all four and record why in audit §2.
- **VALIDATE**: the decision and its reasoning are written into `docs/rule-loading-audit.md` §2 and the acceptance criterion below is reworded to match.

---

## Testing Strategy

| Test | Input | Expected | Edge case? |
|---|---|---|---|
| Path match fires | `Write` to `x.ts` | rule bodies in `additionalContext` | no |
| Non-match silent | `Write` to `x.md` | no output | no |
| Same subject deduped | 2× `Write` to `x.ts` | fires once | **yes** |
| New subject fires | `Write` `x.ts` then `y.ts` | fires twice | **yes** |
| Command trigger | `Bash: gh pr create` | `pr-base-branch` body | **yes** |
| Malformed payload | `not json` | exit 0 + stderr line | **yes** |
| Missing rules dir | valid payload, no dir | exit 0 + stderr line | **yes** |
| Fork propagation | subagent edits `x.ts` | rule loads (hooks reach subagents) | **yes** |

### Edge Cases Checklist
- [ ] Empty `file_path` in payload
- [ ] Subject path containing spaces / non-ASCII
- [ ] Two rules matching the same subject → **both** must fire (§4-A: rules don't compete)
- [ ] Marker dir unwritable (read-only `tmpdir`) → fire anyway, warn
- [ ] Concurrent hook processes on the same subject → `O_EXCL` makes exactly one win
- [ ] Rule file with malformed frontmatter → skip that rule, warn, continue others

---

## Validation Commands

```bash
# Manifest parses and has the new sections
python3 -c "import yaml;d=yaml.safe_load(open('manifest.yaml'));assert 'hooks' in d and 'lazy' in d"
```
EXPECT: exit 0

```bash
# Sync is clean and non-destructive
bash sync.sh --dry-run
```
EXPECT: no `[MISSING]`, no drift, exit 0

```bash
# Hook unit tests
python3 -m pytest .claude/hooks/tests/ -q
```
EXPECT: all pass

```bash
# Injector smoke test (fires, then dedupes)
echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.ts"},"session_id":"t1"}' \
  | python3 .claude/hooks/lazy-rule-inject.py
```
EXPECT: JSON with `additionalContext` on first run, empty on second

```bash
# Eager-load budget after Phase 3
cd ~/.claude/rules && e=0; for f in *.md ecc/common/*.md; do \
  sed -n '1,10p' "$f" | grep -q '^paths:' || e=$((e+$(wc -c < "$f"))); done; echo "$e"
```
EXPECT: ≤ 14,600 bytes (from 18,759; Cut bucket is 4,180 B after the `ecc/common/*` reclassification — the M5 bucket's 6,328 B stops loading eagerly only once Phase 2 is live and those rules leave the eager path)

### Manual Validation
- [ ] Fresh session: edit a `.ts` file → rule text appears **before** the write lands
- [ ] Same session, edit it again → no re-injection
- [ ] Same session, edit a different `.ts` → injection fires again
- [ ] Spawn a subagent that edits a `.ts` → rule loads there too
- [ ] `/hooks` lists the new hook and none of the deleted ones

---

## Acceptance Criteria
- [ ] `manifest.yaml` + `sync.sh` manage `hooks` and `lazy`; `--dry-run` clean
- [ ] Every live rule, lazy body and hook is tracked in this repo
- [ ] One `PreToolUse` injector replaces both old ones; both deleted (the four remaining one-off injectors are a separate, deferred decision — Task 6.3)
- [ ] Injection fires **before** writes and dedupes per `(rule, subject)`
- [ ] 40-edit trace costs ≈6,450 tok, not ≈86,000
- [ ] Eager session load reduced by ≥4,180 B from cuts alone, ≥10,508 B once M5 carries the write- and command-triggered rules
- [ ] `gh-branch-guard.sh` can actually deny
- [ ] Secret scanner fails closed
- [ ] Hook test suite exists and passes, with RED evidence recorded from before the injector existed (Task 2.1) and GREEN evidence from the unmodified same tests after (Task 2.2)
- [ ] `hook-path-convention` fires, or its failure is documented and reproducible

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| ECC reinstall reverts vendored `rules/ecc/**` | **High** | Medium | Record ours-vs-vendored in `docs/` (Task 1.3); prefer editing only files we own |
| Session-id payload key differs from assumption | Medium | High — dedup silently degrades to per-process | Log one live payload before coding (Task 2.2 Gotcha 2) |
| `PreToolUse` injector adds latency to every edit | Medium | Medium | Frontmatter split, not a YAML parse; no network/subprocess; measure before/after |
| Deleting `context7.md` while the plugin is broken | Medium | Low | Plugin currently fails `AUTH_HEADER_REJECTED` — verify before deleting (Task 3.3) |
| Cutover leaves a window with no test-change guard | Low | Medium | Register M5 **before** deleting the old injectors; both merge safely |
| `hook-path-convention` cause is a harness bug | Medium | Low | Time-box Phase 4; document and move on rather than chasing |

---

## Notes

- **Phases 1-3 are the viable first increment** and deliver every measurable win. Phases 4-6 are cleanup and investigation and can land separately.
- Cost figures come from the audit's measured trace, not estimates: 2,150 tok per injection × 40 edits = 86,000, vs 3 distinct files × 2,150 = 6,450.
- The EACL paper is deliberately **not** load-bearing anywhere in this plan — recorded in audit §8 as checked-and-inapplicable so it isn't re-litigated.
- Two audit findings were **retracted or corrected** during research and must not be re-imported: the glob-collision theory (refuted), and the earlier recommendation to gate the two secret rules to M3 (they govern writes; M3 is Read-only).
