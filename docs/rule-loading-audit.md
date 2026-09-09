# Rule Loading Audit — `~/.claude` lazy-loading system

> Audit date: 2026-09-08 · Session `94e2433a` · Sources: empirical testing this session + harness-audit session `5760a9a4` (2026-09-07)

---

## 0. Governing principle — loading and enforcement are orthogonal

Rule strength (`MUST` / `SHOULD` / `MAY`, RFC 2119) has **nothing to do with whether a rule is loaded.**

| Axis | Determined by | Question it answers |
|---|---|---|
| **Loading** | Trigger match — action / event / tool / file | *Is this rule in context right now?* |
| **Enforcement** | Consequence of violation | *Does something mechanically block a violation?* |

**A rule must be loaded whenever its intended action/event/tool/file matches — regardless of its normative strength.** A `MAY` rule with a precise glob loads on match exactly as a `MUST` rule does. Strength only decides whether a *blocking hook* must also sit behind it.

This reframes the defect in the current system. The problem is **not** "MUST rules were gated behind `paths:`". The problem is that **gating sometimes fails to load a rule whose trigger did match** — glob collision silently drops one of two competing rules, and forks/subagents receive nothing at all. That is a *loading-correctness bug*, independent of rule strength.

**Two independent failure classes, therefore:**

| Class | Symptom | Fix domain |
|---|---|---|
| **L — Load failure** | Trigger matched, rule never entered context | Glob de-collision, mechanism choice, fork coverage |
| **E — Enforcement gap** | Rule was in context, violated anyway with no block | Hooks that deny, not prose |

Audit finding #10 (*"withheld text governs nothing"*) is class **L**. Its verdict about "enforcement theater" is class **E**. They need separate fixes and must not be conflated.

---

## 1. The token-consumption issue is actually two opposite problems

| | Cost shape | Magnitude |
|---|---|---|
| **Eager rules** (no `paths:`) | Once per session, **bounded** | 18,759 B ≈ **4,689 tokens/session** |
| **Hook-injected rules** (no dedup) | Once per *matching edit*, **unbounded** | ~8,575 B ≈ **2,150 tokens per JS/TS edit** |

Audit findings #1–#3, verbatim: both injectors are stateless `PostToolUse`/`Edit|Write` and re-emit full text on every matching edit — *"~86K tokens over 40 edits, ~98% exact duplicates"* — and `JS_TS_SUFFIXES ⊂ COVERED_SUFFIXES`, so both fire together (double-billing).

Finding #2: **"The lazy split made loading worse, not better… loses to plain eager loading after ~2 edits."**

**Crossover math** — eager costs 4,689 tokens once; hook injection costs 2,150 per edit:

| Edits | Eager (cumulative) | Hook-injected (cumulative) |
|---:|---:|---:|
| 0 | 4,689 | 0 |
| 2 | 4,689 | 4,300 |
| **≈2.2** | **4,689** | **4,689 ← crossover** |
| 5 | 4,689 | 10,750 |
| 10 | 4,689 | 21,500 |
| 40 | 4,689 | 86,000 |

So the thing remembered as "loaded indefinitely" is real, but **the worse half is the lazy path, not the eager one.**

---

## 2. The four mechanisms actually in play

| # | Mechanism | How it fires | Fires on | Count | Reaches forks? |
|---|---|---|---|---|---|
| **M1** | **Eager** — no frontmatter | Full text at session start, every session | session start | 16 files | Yes |
| **M2** | **Proxy stub → `lazy/rules/` body** | `paths:` glob fires → injects *"go read X"* → needs a Read | **Read only** | 11 files | **No** |
| **M3** | **Self-contained `paths:`-gated** | glob fires → full content injected directly | **Read only** | 11 files | **No** |
| **M4** | **Hook-injected** | hook emits body text on a tool/event match | any hooked tool/event | 4 hooks | Yes |

### ⚠ `paths:` gating is Read-triggered — it is blind to writes

Verified empirically 2026-09-08 (method in Appendix B):

| Action | Location | `**/*.py`-gated rules fired? |
|---|---|---|
| **Write** `.py` | outside project | No |
| **Write** `.py` | inside project | No |
| **Read** `.py` | inside project | **Yes — all 5, ~10.1 KB at once** |

**Consequence: M2 and M3 structurally cannot govern edits.** Any rule shaped *"when editing X, do Y"* will never load at edit time under `paths:` gating — it loads only if a matching file happens to be Read first, which is incidental, not causal. Under §0 this is a permanent **class-L** failure for the entire edit-triggered rule category: the trigger matches and the rule still does not load.

**Rules of that shape must use M4.** This is not a preference; it is the only mechanism that observes writes.

### M2 is strictly worse than M3 in most cases

When an M2 proxy fires you get a **pointer, not a rule**. That costs:

1. An extra tool call (latency + the Read's tokens anyway)
2. A **class-L load failure risk** — the rule only reaches context if the pointer is obeyed

**M2 only earns its keep when the glob is over-broad AND the body is large** — it then acts as a second-stage filter, letting the body be skipped when the glob over-fires. Otherwise M3 wins outright.

### Mechanism selection rule

| Trigger is… | Must hold in forks/subagents? | Use |
|---|---|---|
| **Reading** a file matching a glob | No | **M3** (or M2 if glob over-broad *and* body large) |
| **Reading** a file matching a glob | Yes | **M4** |
| **Writing/editing** a file | Either | **M4** — M2/M3 are blind to writes |
| A tool or event (not a path) | Either | **M4** |
| Nothing matchable (prose/judgment) | Either | **M1** |

### Decision (2026-09-09, plan Task 6.3) — the four surviving one-off injectors stay

M5 (`lazy-rule-inject.py`) is live and measured: it replaced the two per-edit injectors, dedupes per `(rule, subject, session)`, and costs ~29 ms per call. Phase 2 left four hook-injectors untouched: `enterplanmode-rule-inject.py` (`PostToolUse:EnterPlanMode` → `lazy/rules/plan.md`), `research-ops-rule-inject.py` (`PostToolUse:Skill`), `research-ops-promptsubmit.py` (`UserPromptSubmit`) and `research-ops-tooling-gate.py` (`PreToolUse:Skill`, a gate, not a loader).

Chosen: **(c) leave all four as they are.** Reasons:

1. None has a *subject*. M5's dedup key is `(rule, subject, session)`; a tool-only or prompt-level trigger would need a new `on.tools`-only mode with a per-session fallback key — a schema extension with no measured cost problem to justify it. These hooks fire on rare events (`EnterPlanMode`, a specific `Skill`, a prompt match), not on every edit; the unbounded-cost finding (#1) that motivated M5 does not apply to them.
2. The `research-ops` trio is a coherent subsystem (prompt detection → skill gate → rule injection). Folding one third of it into M5 would split its logic across two mechanisms for no gain.
3. `enterplanmode-rule-inject.py`'s matcher was only *partially* retested (`EnterPlanMode` is a real tool in this harness); folding it before a clean live retest would be rewriting on assumption.

Revisit when a fifth tool-only rule appears — at that point an `on.tools`-only trigger earns its keep (DRY: abstract at the third instance). The acceptance criterion "one `PreToolUse` injector replaces both old ones" stands as written; "one injector" as a system-wide property is explicitly **not** claimed.

---

## 3. Per-rule inventory

### M1 — Eager (4,689 tok/session, every session)

| Rule | Bytes | Issue | Recommendation | Action |
|---|---:|---|---|---|
| `settings-json-secrets.md` | 3071 | Biggest eager file. **Governs writes** — M3 would be structurally blind to it | → **M4** injector on `Edit\|Write` (blocking hook already exists; add the injection) | M4 |
| `pr-review.md` | 2629 | Duplicates the `pr-review` **skill** | Delete, fold into skill | Cut |
| `secrets-and-env.md` | 2502 | Same shape — governs *writing* `.mcp.json` / `.env*` / `.bashrc` | → **M4** injector on `Edit\|Write` | M4 |
| `authoring-conventions.md` | 1833 | Two unrelated rules in one file (heredoc quoting + artifact drafting) | Split: heredoc → Bash hook; drafting → keep | Split |
| `web-research-tool-selection.md` | 1708 | **Loaded twice** — verbatim-identical copy in this repo's `.claude/rules/` (confirmed `diff`-identical) | Delete the repo copy | Cut |
| `context7.md` | 1308 | Now **redundant** — the context7 plugin ships its own MCP server instructions saying the same thing | Delete | Cut |
| `goal-focus-chore-deferral.md` | 996 | Also exists as a skill | Check overlap, keep one | Review |
| `hooks.md` | 908 | **3-way topic collision** with `hook-path-convention.md` + `ecc/common/hooks.md` | Merge into one | Merge |
| `ecc/common/git-workflow.md` | 755 | Vendored ECC (byte-identical to cache 2.2.0; already stale vs 2.2.1, which rewrote line 12). Both sections are command-triggerable: commit format on `git commit`, PR workflow on `gh pr create` | → **M5** `on.commands`; track in the repo with a `vendored: ecc@2.2.0` marker so an ECC overwrite shows as `[DIVERGED]` instead of silently reverting | M5 |
| `plan-approval-trust.md` | 651 | No matchable trigger (judgment/behavioral) | Keep eager | Keep |
| `worktree-isolation.md` | 558 | Session-wide, no matchable trigger | Keep eager | Keep |
| `pr-base-branch.md` | 539 | Mixed trigger shapes: the PR-target MUST is hookable on `gh pr create`; the "compare against `develop` first" clause is session-wide judgment | Split (plan Task 3.1): PR-target + Advisory → **M5** on `gh pr create`; comparison clause stays eager (~200 B) | Split |
| `active-session-hooks.md` | 409 | **Documents a gate that's already off** (`GATEGUARD_BASH_ROUTINE_DISABLED=1`) | Fix claim or delete | Fix |
| `ecc/common/hooks-todowrite-practices.md` | 325 | **Not vendored** — absent from every ECC cache version (2.2.0, 2.2.1, all locale copies); mtime 2026-08-24, three days after the ECC batch. Misclassified by directory. Only trigger is the `TodoWrite` tool itself (no subject), and that tool is absent from the current harness tool list | Keep eager pending a `TodoWrite`-exists check; if it exists, tools-only trigger via plan Task 6.3; if not, delete as dead content | Keep |
| `archiving.md` | 324 | No matchable trigger (prose) | Keep eager | Keep |
| `knowledge-ops-defaults.md` | 243 | Tiny, belongs to a skill | Fold into `knowledge-ops` | Cut |
| **Total** | **18,759** | | | |

**Projected savings**

| Bucket | Files | Bytes | Requires |
|---|---|---:|---|
| **Cut** | `pr-review`, `context7`, `knowledge-ops-defaults` | 4,180 | deletion only (`context7` blocked while the plugin is auth-rejected) |
| **Move → M5** | `settings-json-secrets`, `secrets-and-env`, `ecc/common/git-workflow` | 6,328 | the `PreToolUse` injector (plan Phase 2) |
| **Immediately actionable** | Cut bucket only | **4,180 B ≈ 1,045 tok** | **22%** |
| **After M5 exists** | both buckets | **10,508 B ≈ 2,627 tok** | **56%** |
| **Remaining eager (best case)** | | 8,251 B ≈ 2,063 tok | |

> **Correction (2026-09-09):** an earlier revision put both `ecc/common/*` eager files in the Cut bucket as "vendored, overwritten on reinstall". Diffing against the ECC cache showed `hooks-todowrite-practices.md` is not vendored at all (user-owned, never shipped by ECC), and `git-workflow.md` is vendored but fully command-triggerable — being vendored is a reason to *track and detect divergence*, not to delete. Cut drops from 5,260 B to 4,180 B; the difference moves to M5 and Keep.

Separately, deleting the duplicated repo copy of `web-research-tool-selection.md` saves another 1,708 B of session context.

> **Correction (2026-09-08):** an earlier revision recommended gating these two to **M3**. That was wrong — both govern *writes*, and `paths:` gating is Read-triggered (§2), so M3 would never load them at the moment they apply. They must go to **M4**, and to a `PreToolUse` hook specifically, so the rule arrives *before* the write. Neither is weakened by the move: both keep their existing blocking hooks. This changes *when they load*, not *whether they're enforced*.

### M2 — Proxy → lazy body

| Proxy → body | Bytes | Issue | Recommendation |
|---|---|---|---|
| `coding-principles` | 262→997 | Prose-only pointer; body small enough that the indirection buys nothing | Collapse to **M3** |
| `command-scripts` | 213→564 | Same | Collapse to **M3** |
| `claude-md-self-reference` | 161→941 | Same | Collapse to **M3** |
| `two-pass-artifacts` | 173→1753 | Same | Collapse to **M3** |
| `hook-path-convention` | 181→478 | **Class-L failure: never fires.** Cause **unknown** — the glob-collision theory is *refuted* (see §4-A). Compounding it: the rule governs *writing* a hook entry, and `paths:` is Read-only, so it could never fire at the right moment anyway | Move to **M4** on `PreToolUse:Edit\|Write`; investigate the non-firing separately |
| `ask-before-test-changes` | 287→2121 | Hook exists but is `PostToolUse` — **fires after the test file is already written** (#5) | Move hook to **PreToolUse** |
| `ecc/typescript/*` ×5 | ~200 each → 302–4218 | Hook-injected with **no dedup**, double-billed (#1, #3); bodies are **66% code fences** (#4) | Add session dedup marker; trim fences |

### M3 — Self-contained gated (working as designed)

| Rule | Bytes | Glob |
|---|---:|---|
| `plan-preflight` | 4520 | `.claude/plans/**/*.md` |
| `rule-authoring-format` | 2359 | `.claude/rules/**/*.md`, `.claude/lazy/rules/**/*.md` |
| `terse-artifact-content` | 1605 | `CLAUDE.md`, `**/CLAUDE.md`, `.claude/skills/**`, `.claude/agents/*` |
| `plan-cross-reference-integrity` | 1280 | `.claude/plans/**/*.md` |
| `ecc/common/code-review` | 3618 | `**/*.py`, `**/*.js`, `**/*.ts` |
| `ecc/common/coding-style` | 2697 | `**/*.py`, `**/*.js`, `**/*.ts` |
| `ecc/common/development-workflow` | 2296 | `.claude/plans/**/*.md` |
| `ecc/common/testing` | 1560 | `**/*.py`, `**/*.js`, `**/*.ts` |
| `ecc/common/patterns` | 1182 | `**/*.py`, `**/*.js`, `**/*.ts` |
| `ecc/common/security` | 1069 | `**/*.py`, `**/*.js`, `**/*.ts` |
| `ecc/common/hooks` | 537 | `**/settings.json`, `**/settings.local.json`, `.claude/hooks/**/*.sh` |

✓ Correct pattern. **One note:** the seven `ecc/common/*` rules gate on `**/*.py|js|ts`, which is very broad — they fire in almost any code session, collectively ~13.9 KB.

### M4 — Hook-injected

| Hook | Target | Status |
|---|---|---|
| `research-ops-rule-inject.py` | `lazy/rules/research-ops.md` (3671 B) | ✓ Works (fired this session) |
| `enterplanmode-rule-inject.py` | `lazy/rules/plan.md` (726 B) | Audit claimed matcher wrong (`EnterPlanMode` vs `ExitPlanMode`) — **partially refuted:** `EnterPlanMode` *is* a real tool in the current harness. Retest live before rewriting. |
| `ecc-typescript-rule-inject.py` | ecc/typescript bodies | No dedup, no timeout |
| `confirm-before-test-changes-rule-inject.py` | `rules/ask-before-test-changes.md` | Structurally too late (`PostToolUse`) |

**Not orphans:** `lazy/rules/plan.md` and `lazy/rules/research-ops.md` have no proxy stub **by design** — hook-only splits, explicitly legal per `rule-authoring-format.md`. The only cost is human discoverability.

### Classification applied 2026-09-09 (plan Tasks 3.1, 3.2, 3.4)

Every user-owned rule classified on **trigger shape only** (§0 — strength ignored), per the selection rule above. M5 = the `lazy-rule-inject.py` `PreToolUse` injector, live since 2026-09-09. "Dual" = keeps `paths:` for native Read-gating and adds `on:` for the injector; such files stay under `rules/` and are not eager. `on:`-only files live under `lazy/rules/` (hook-served, no proxy).

| Rule | Trigger shape | Bucket | Change made |
|---|---|---|---|
| `settings-json-secrets` | writes to `settings*.json` | Dual | added `paths:` + `on: [Edit, Write]` — left the eager path (3,071 B) |
| `secrets-and-env` | writes to `.mcp.json`, `.env*`, `.bashrc`, `environment.d/*`, `.claude.json` | Dual | same (2,502 B) |
| `plan-preflight`, `plan-cross-reference-integrity`, `two-pass-artifacts` | read **and write** of `.claude/plans/**` (+ `docs/**` for two-pass) | Dual | `on:` mirroring existing `paths:` |
| `rule-authoring-format` | read/write of `rules/**`, `lazy/rules/**` | Dual | same |
| `terse-artifact-content` | read/write of `CLAUDE.md`, skills, agents, commands | Dual | same |
| `coding-principles`, `command-scripts`, `claude-md-self-reference` | read/write of their globs | Dual | **M2 proxy collapsed into the rule file** (Task 3.2); lazy body deleted |
| `hooks` ← `hook-path-convention` | writes to `settings*.json` | Dual | audit "Merge": `hook-path-convention` proxy + body folded into `hooks.md` under the proxy's exact `paths:` (so the Phase 4 bisect still targets the same globs); both `hook-path-convention` files deleted. Leaves the eager path (908 B) |
| `authoring-conventions` | **mixed** → split | Eager + `on:`-only | heredoc clause → `lazy/rules/heredoc-quoting.md` `on: [Bash]` commands `*<<'*`, `gh issue/pr …`, `git commit*`; KISS/drafting clause stays eager (≈560 B) |
| `pr-base-branch` | **mixed** → split | Eager + `on:`-only | PR-target MUST + Advisory → `lazy/rules/pr-base-branch.md` `on: [Bash]` `gh pr create*`/`gh pr edit*`; compare-against-`develop` clause stays eager (≈300 B) |
| `ecc/common/git-workflow` | `git commit*`, `gh pr create*` | `on:`-only | moved to `lazy/rules/ecc/common/git-workflow.md`, `vendored: ecc` kept in the manifest. Leaves the eager path (755 B). Risk: an ECC reinstall recreates the eager copy under `rules/ecc/common/` — `rules` scan is depth-1 and will not flag it |
| `ask-before-test-changes` | writes to code files | `on:`-only (since Task 2.3) | `paths:` proxy deleted — redundant once the body is hook-served |
| `ecc/typescript/*` ×5 | writes to JS/TS | `on:`-only (since Task 2.3) | Task 3.4: `../common/X.md` → `../../../../rules/ecc/common/X.md`, resolves in the installed layout |
| `plan`, `research-ops` | tool / prompt events | M4 one-off hooks | unchanged — Task 6.3 decides |
| `plan-approval-trust`, `worktree-isolation`, `archiving`, `goal-focus-chore-deferral`, `active-session-hooks`, `web-research-tool-selection`, `context7` (kept by user decision), `hooks-todowrite-practices` (pending Task 3.3's `TodoWrite` check) | no matchable trigger | **M1 eager** | none |
| `pr-review` | **mixed** → split (Task 3.3) | `on:`-only + fold | reply-etiquette clauses (inline replies, `PENDING` reviews) govern *responding* to review comments, which the review skill never does → `lazy/rules/pr-review-replies.md` `on: [Bash]` `gh pr comment*`/`gh pr review*`/`gh api*pulls*`; tool-selection clauses folded into `skills/pr-review/SKILL.md` § Scope; rule file deleted (−2,629 B) |
| `knowledge-ops-defaults` | — | **Cut** (Task 3.3) | folded into `skills/knowledge-ops/SKILL.md` Layer 4 as the default path; rule file deleted (−243 B) |
| `ecc/common/hooks-todowrite-practices` | `TodoWrite` tool only | **Cut** (Task 3.3) | `TodoWrite` is absent from the current harness tool list (checked 2026-09-09: not listed, not deferred) → dead content, deleted (−325 B) |
| repo copy of `web-research-tool-selection` | — | **Kept** (deviation from Task 3.3) | see the double-load finding below — deleting only this one copy no longer makes sense now that all 24 user-wide rules are tracked under the repo's own `.claude/rules/` |

**Double-load finding (2026-09-09).** Tracking user-wide rules under this repo's `.claude/rules/` makes every one of them a *project* rule for sessions run inside this repo — so each eager rule loads twice here (once from `~/.claude/rules/`, once from `.claude/rules/`), and each `paths:`-gated rule fires twice on a matching Read. Observed live this session: `terse-artifact-content.md` arrived twice on one `Read` of a skill file. The audit's original "loaded twice" note about `web-research-tool-selection` was the first instance of this, not a one-off. It only affects sessions inside this repo, but the fix is structural — e.g. have `sync.sh` install rules from a directory Claude Code does not auto-load (`.claude/user-rules/` → `~/.claude/rules/`) — and is a user decision, not a Phase 3 edit.

Result: zero M2 proxies remain; no file mixes two trigger shapes; `lazy/rules/` holds only hook-served bodies (`ask-before-test-changes`, `heredoc-quoting`, `plan`, `pr-base-branch`, `research-ops`, `ecc/common/git-workflow`, `ecc/typescript/*`).

---

## 4. Cross-cutting issues

| # | Class | Issue | Evidence |
|---|---|---|---|
| A | **L** | ~~**Glob collision is silent.**~~ **RETRACTED 2026-09-08.** A later test fired **five** rules sharing `**/*.py` *simultaneously* — matching rules plainly do **not** compete, so collision cannot explain anything. **Open question:** why `hook-path-convention.md` never fired on any `settings.json` read remains **unexplained**. Do not act on the collision theory | Refuted empirically, this session |
| A2 | **L** | **`paths:` gating is Read-only** — no `paths:`-gated rule fires on Write/Edit, in-project or out. Every edit-governing gated rule is permanently dark | Empirical, 3-cell test (§2, App. B) |
| B | **L** | **Forks/subagents don't get `paths:`-gated rules.** A fork triggered 0 injections across 4 matching reads that fired reliably in the main session and a fresh agent | Empirical, this session |
| C | — | **Hooks *do* reach subagents** — so anything that must hold inside a fork can only use M4 | Official docs + observed hook context in fresh agent |
| D | **L** | **Injection dedups once per rule per session** — fires on first matching read, never again, even for a *different* matching file. A later match that genuinely needs the rule gets nothing | Empirical, this session |
| E | Cost | **No dedup on hook injection** — opposite behavior, re-emits every edit | Audit #1 |
| F | **E** | **`PostToolUse` is structurally too late** for any "ask before doing X" rule | Audit #5 |
| G | **E** | **Silent failure by design** — `except Exception: sys.exit(0)` → partial-or-zero injection with no signal | Audit #6 |
| H | **E** | **No timeout on any of the 12 registered hook entries** | Audit #7 |
| I | — | **Dead weight**: `plans-index-guard.py` (3,922 B of deny logic, registered nowhere); `~/.claude/hooks/hooks.json` (37 KB, 21 entries, dead); `hooks/README.md` (~20 nonexistent hooks); `hooks/tests/` tests only the dead hook | Audit #11, #12 |
| J | — | **Dangling links**: all 5 `lazy/rules/ecc/typescript/*` bodies open with `> This file extends [common/X.md](../common/X.md)` → resolves to `lazy/rules/ecc/common/`, **which does not exist** (verified) | Audit #13 |
| K | — | **`~/.claude` has no version control**, while `rules/ecc/**` and `hooks/hooks.json` are vendored from an installer that overwrites them | Audit, unanimous across all 3 sets |

> **D is the most under-appreciated.** Once-per-session dedup means a matched trigger late in a session loads nothing. Under the §0 principle — *load whenever the trigger matches* — that is a straightforward violation, and it cannot be fixed by rewording the rule.

---

## 5. Two audit UNKNOWNs resolved this session

The 2026-09-07 audit explicitly listed these as unresolved — *"I verified the effect, not the mechanism"*:

| Unknown | Resolution |
|---|---|
| *"Whether `paths:` frontmatter is a genuine Claude Code feature or an inert convention"* | **Genuine and documented.** Official docs confirm path-scoped rules load only on glob match; nested `CLAUDE.md` files load on-demand when files in that subdirectory are read. |
| *"Whether hooks fire for subagents/background tasks"* | **Hooks do reach subagents** (docs + observed). **`paths:`-gated rules do not reach forks** (proven: 0 injections across 4 matching reads). |

**Design consequence:** anything that must hold inside a fork or subagent **cannot use M2 or M3 at all — only M4.**

---

## 6. The audit's verdict (verbatim)

> *"The system's enforcement layer is largely theater: of ~25 rules written in MUST language, only three hooks actually block anything, one of those three (`gh-branch-guard.sh`) is structurally incapable of denying, and 18 rules are deliberately withheld from context by `paths:` frontmatter — governing nothing. It is not fit for purpose as an enforcement system. It is adequate as a context-budget system and as a prose reference… The dominant failure mode is not risk of harm but **false assurance**."*

Read through §0: the "18 rules withheld… governing nothing" clause is a **class-L** claim and is only a defect where the trigger actually matched. Where the trigger did not match, withholding is correct behavior, not a failure.

### What actually works (audit's SOUND list)

- GateGuard Edit/Write (fired ~6× in that session)
- `check-settings-json-secrets.sh` / `check-mcp-gitignore.py` — when `jq` is present
- `research-ops-tooling-gate.py` — `PreToolUse:Skill`, correct event, correct shape
- **`paths:` gating as a *context-budget* mechanism — empirically verified working**
- Repo `PostToolUse Edit|Write → npm run type-check`
- Eager repo rules + CLAUDE.md

---

## 7. Ranked next actions

**Safety first**

1. **`git init ~/.claude`** — *the only unanimous item across all three audit sets*, still not done
2. Fix `gh-branch-guard.sh:21-22` to emit `hookSpecificOutput.permissionDecision`; move to `~/.claude/hooks/`; replay-verify
3. Remove `|| true` from `check-settings-json-secrets.sh` — missing `jq` must **deny**; make `check-mcp-gitignore.py` fail closed
4. Decide GateGuard scope — drop `GATEGUARD_BASH_ROUTINE_DISABLED` **or** delete the false claim in `active-session-hooks.md`, not both
5. Retest the `EnterPlanMode` matcher live before changing it

**Load-correctness (class L) — from §0**

6. **Build the `PreToolUse` rule injector (§8).** This is the headline gap: `paths:` gating is Read-only and fires after the fact, so no edit-governing rule can ever load in time. Everything else in this class is downstream of it
7. Key dedup on *(rule, triggering file)* rather than *(rule, session)* — a later match on a different file must still load (issue D)
8. Re-home any rule that must hold inside forks/subagents to **M4**
9. ~~De-collide overlapping globs~~ — **dropped**, the collision theory is retracted (§4-A). Instead: investigate why `hook-path-convention.md` never fires, as an isolated bug

**Then deletions**

9. `diff -r` vendored ECC rules before deleting anything
10. Delete `hooks.json`, `hooks/README.md`, `plans-index-guard.py`, `hooks/tests/`, `noop-bash-guard.py` (the two eager `rules/ecc/common/*` were removed from this list 2026-09-09 — see §3 correction)
11. **"Resolve every `paths:`-gated rule: promote to eager prose, back with a hook, or delete. No third state."**

**Also raised (Set C)**

- Add injection hooks for `coding-principles` + `claude-md-self-reference`
- Move `ask-before-test-changes` to `PreToolUse`
- Regenerate the CLAUDE.md index — it currently names 11 of 25 rules

---

## 8. The missing mechanism — a `PreToolUse` rule injector (M5)

**Requirement (2026-09-08):** loading should be finer-grained than "on read" — it must fire on writes, edits, and any other action that needs rule awareness, and it must fire **ahead of** the action, not after it.

Native `paths:` gating fails both halves: it is Read-only (§2) and it delivers *after* the tool result. Every existing injector in `~/.claude/hooks/` is `PostToolUse`, which fails the second half too (audit #5, reproduced live this session — `ask-before-test-changes` arrived after the file was written).

### Contract

| Property | Value |
|---|---|
| Event | **`PreToolUse`** — the only event that precedes the action |
| Matcher | `Edit\|Write\|NotebookEdit\|Bash` (extend as needed) |
| Input | `tool_input.file_path` for edits; `tool_input.command` for Bash |
| Output | `hookSpecificOutput.additionalContext` — the matching rule bodies |
| Dedup key | **`(rule, subject)`** — never `(rule, session)`; see issue D |
| Failure mode | **Loud** — emit a visible warning; never `except: exit(0)` (issue G) |
| Timeout | Set one (issue H) |

### Trigger vocabulary

Keep `paths:` for native Read-gating (free, no hook cost, still useful) and add an `on:` block the injector reads. Rules stay dual-compatible — native handles reads, the injector handles everything else:

```yaml
---
paths:                          # native, Read-triggered — unchanged
  - "**/settings.json"
on:                             # new — hook-driven, fires ahead of the action
  tools: [Edit, Write]
  paths: ["**/settings.json", "**/settings.local.json"]
  commands: ["gh pr create*", "git push*"]
---
```

`on.commands` is the piece nothing currently covers: it makes rules like `pr-base-branch` (*"PRs MUST target `develop`"*) loadable at the moment a `gh pr create` is about to run, instead of paying for them eagerly in all 100% of sessions that never open a PR.

### Why this subsumes M2/M3/M4

| Property | M2/M3 (`paths:`) | M4 (current, PostToolUse) | **M5 (proposed)** |
|---|---|---|---|
| Fires on reads | ✓ | — | ✓ |
| Fires on writes/edits | ✗ | ✓ | ✓ |
| Fires on commands | ✗ | ✗ | ✓ |
| Fires **before** the action | ✗ | ✗ | **✓** |
| Reaches forks/subagents | ✗ | ✓ | ✓ |
| Dedup | per session (too coarse) | none (unbounded cost) | per `(rule, subject)` |
| Can also block | ✗ | ✗ | ✓ (keep separate per §0) |

### Boundary — keep §0 intact

M5 unifies *delivery*, not *authority*. Injecting a rule and denying an action are two decisions in one hook, and must stay independently configured: strength (`MUST`/`SHOULD`/`MAY`) decides whether a violation is *blocked*; trigger match decides whether the rule is *loaded*. A `MAY` rule still loads on match; a `MUST` rule still loads no differently — it just also carries a deny.

### Dedup strategy — the cost knob

M5's cost is set entirely by its dedup key. Four options; only one is both correct and bounded:

| Strategy | Key | Fires | Cost scales with | Verdict |
|---|---|---|---|---|
| None | — | every matching event | every event — **unbounded** | what today's 4 injectors do (audit #1) |
| `guidanceOnce` | `(rule, session)` | first match only | flat, 1 fire | **violates §0** — later subjects governed by nothing (issue D) |
| `guidancePeriodic` | `(rule, session)` + counter | calls 1, N+1, 2N+1… | event count — **unbounded** | cadence is blind to *which* subject |
| **`per_subject`** | **`(rule, subject)`** | **once per distinct subject** | **distinct subjects — bounded by breadth** | **use this** |

Measured on a 40-edit trace across 3 files (`.claude/PRPs/examples/throttle_demo.py`, runnable):

| Strategy | Fires | Tokens |
|---|---:|---:|
| none | 40 | 86,000 |
| `periodic(4)` | 10 | 21,500 |
| **`per_subject`** | **3** | **6,450** |
| `once` | 1 | 2,150 *(broken)* |

≈13× cheaper than today's behavior, while still guaranteeing every distinct subject is governed exactly once.

Rows 2–3 are context-mode's real implementations (`guidanceOnce` / `guidancePeriodic`, `hooks/core/routing.mjs`). Both persist state as marker files under `tmpdir()` — necessary because **every hook invocation is a fresh process**, so in-memory throttling cannot survive between calls. M5 must do the same, and should key the marker on a hash of the subject.

### On the research literature — checked, does not apply

Robinette et al., *"We Are What We Repeatedly Do: Improving Long Context Instruction Following"* (Findings of ACL: EACL 2026, pp. 4855–4884) is the obvious paper to reach for when justifying re-injection. **It does not support periodic re-injection.** Recorded here so it isn't re-litigated:

- Its six strategies — Reinstruct, Teach, Rewrite and Replace, Summarize, Combine, IGA — are **all reactive**. Each fires only *after* a non-compliant response is detected. None runs on a cadence.
- The headline *"improvement up to 79%"* is Certified Compliance Accuracy gain from **IGA**, a model-architecture change (split instruction/context attention pathways, α=0.6). Not reachable from outside model internals, and not from re-stating anything. Baseline: Gemma2 27B-it avg CCA 46.43. Note also that Summarize's *average* CCA is 79.40 — a different number, trivially conflated with the first.
- Tested only on open-weight models (Gemma 7B-it, Gemma2 27B-it, Llama3 8B-it/70B-it) at 10/25/50 **turns** — not token-window lengths. On Gemma 7B, Combine and IGA **failed outright** while the simpler four helped, so even the winning method is model-dependent.

**What it does imply — and it reinforces §0:** the lever for compliance is **detection**, not louder loading. Reinstruct costs ~30 tokens precisely because it only fires once something has already gone wrong. `ecc:skill-comply` is the detector-shaped tool already installed.

The `per_subject` recommendation above therefore rests on its own cost arithmetic, not on this paper.

### Open risks

- **Cost.** M5 re-fires per subject, so it inherits M4's cost profile unless the `(rule, subject)` dedup is real. Budget it against the §1 crossover math before migrating high-frequency rules.
- **Latency.** A `PreToolUse` hook sits in the critical path of every edit. Keep it to a file-stat + glob match; no network, no subprocess.
- **Ordering.** It shares `PreToolUse:Edit|Write` with GateGuard and the two secret-scanners. Confirm injected context survives alongside another hook's `deny`.

---

## Appendix A — registered hooks (`~/.claude/settings.json`)

The `settings.json` matcher is only the **coarse** filter. Every hook then narrows again *inside* the script — and that second layer is invisible from `settings.json`, which is where most of the surprises live.

| Event | Matcher | Internal matching (inside the script) | Effect | Script |
|---|---|---|---|---|
| UserPromptSubmit | `*` | Regex `^\s*/research-ops\b` (case-insens.) on **raw prompt text**. Exists because a native slash command never emits a `Skill` tool_use event, so the two `Skill`-matched hooks below never fire for a typed `/research-ops` | deny (exit 2) if Exa plugin absent; else inject `lazy/rules/research-ops.md` | `research-ops-promptsubmit.py` |
| SessionStart | `*` | *(not inspected — context-mode helper)* | cache heal | `context-mode-cache-heal.mjs` |
| SessionStart | `*` | *(not inspected — context-mode helper)* | install check | `context-mode-check.js` |
| PreToolUse | `Bash` | Fast-exit unless command matches `(gh pr create\|git commit\|git push\|gh repo create)`. Then 4 sub-guards: `--base` present **and** not `main\|master`; `git commit` while `git rev-parse --abbrev-ref HEAD` ∈ `main\|master`; push to protected; `gh repo create` without explicit visibility | **deny — but broken**, see note ▼ | `gh-branch-guard.sh` |
| PreToolUse | `Bash` | Strips `#` comments, then blocks if what remains is empty or filler (`true`, `:`) | deny (exit 2) | `noop-bash-guard.py` |
| PreToolUse | `Edit\|Write` | `basename(file_path) == ".mcp.json"` **exactly**; then `git rev-parse` (passthrough if not a repo); then `git check-ignore -q` | deny (exit 2) if not gitignored | `check-mcp-gitignore.py` |
| PreToolUse | `Edit\|Write` | `case "$base" in settings.json\|settings.local.json)` — basename only; then jq-extracts content and greps a secret-pattern list | deny (exit 2) on pattern hit | `check-settings-json-secrets.sh` |
| PreToolUse | `Skill` | `tool_input.skill.split(":")[-1] == "research-ops"`; then scans merged plugin config for an enabled `exa` | deny (exit 2) if Exa absent | `research-ops-tooling-gate.py` |
| PostToolUse | `EnterPlanMode` | None — matcher is the only filter | inject `lazy/rules/plan.md` | `enterplanmode-rule-inject.py` |
| PostToolUse | `Skill` | Same skill-name check as the gate above | inject `lazy/rules/research-ops.md` | `research-ops-rule-inject.py` |
| PostToolUse | `Edit\|Write` | `Path(file_path).suffix ∈ {.ts, .tsx, .js, .jsx}` | inject ecc/typescript bodies | `ecc-typescript-rule-inject.py` |
| PostToolUse | `Edit\|Write` | `Path(file_path).suffix ∈ {.py, .js, .ts, .tsx, .jsx, .sh, .go, .rb, .rs, .java}` | inject `lazy/rules/ask-before-test-changes.md` | `confirm-before-test-changes-rule-inject.py` |

### What the internal layer reveals

- **▼ `gh-branch-guard.sh` cannot deny — confirmed at source.** Its `deny()` emits a *bare* object and then exits 0:
  ```bash
  deny() {
    echo "{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"$1\"}"
    exit 0
  }
  ```
  Claude Code's `PreToolUse` contract requires the decision nested under `hookSpecificOutput` (with `hookEventName`), and `exit 0` means *allow*. So every `deny()` path — PR base branch, commits to `main`, pushes to protected, repo visibility — is **silently ignored**. This is the audit's #1 correctness item, verified.
- **It also violates the repo's own rule.** It lives in `~/.claude/scripts/`, but `hooks.md` states hook command scripts MUST live in `.claude/hooks/`. A rule with no mechanical backing, broken by the very hook it governs.
- **Double-billing confirmed at source.** `{.ts,.tsx,.js,.jsx} ⊂ {.py,.js,.ts,.tsx,.jsx,.sh,.go,.rb,.rs,.java}` — every TS/JS edit fires **both** injectors (audit #3).
- **No dedup anywhere.** None of the four injectors contains a marker, cache, or seen-set. Every match re-emits the full body (audit #1).
- **Fail-open in the secret scanner.** Every `jq` call in `check-settings-json-secrets.sh` is suffixed `|| true`, and an empty extraction exits 0 — so a missing `jq` turns the deny into a silent pass.
- **Basename-only matching is narrower than the rule it enforces.** Both `check-mcp-gitignore.py` and `check-settings-json-secrets.sh` match on `basename` alone, so a path like `config/settings.json.bak` or a renamed copy is unguarded.
- **The `UserPromptSubmit` hook exists to patch a harness gap.** Its own docstring records that native slash commands never emit `Skill` events — meaning any rule wired only to `PreToolUse:Skill` / `PostToolUse:Skill` silently never fires for user-typed commands. That is a general trap, not a research-ops quirk.

Note: context-mode's own `PreToolUse` / `PostToolUse` / `PreCompact` / `Stop` hooks are **not** listed here — they ship in the plugin's own `hooks/hooks.json` and are invisible to a `settings.json` read.

---

## Appendix B — method for the Read-vs-Write test

Run 2026-09-08, session `94e2433a`. Target: the five `ecc/common/*` rules gated on `**/*.py`, none of which had fired yet that session (no `.py` file had been touched).

| # | Action | Path | Result |
|---|---|---|---|
| 1 | `Write` a `.py` | scratchpad, **outside** project | No gated rule fired. Only `ask-before-test-changes` (an M4 `PostToolUse` hook) |
| 2 | `Write` a `.py` | worktree root, **inside** project | Identical — no gated rule fired. Rules out "glob resolves relative to project root" as the cause |
| 3 | `Read` that same `.py` | worktree root, inside project | **All five fired at once**, ~10.1 KB: `testing`, `patterns`, `security`, `code-review`, `coding-style` |

**Conclusions:** (a) `paths:` gating is Read-triggered, not Write-triggered; (b) location is not a factor; (c) **multiple matching rules all fire together** — which refutes the earlier glob-collision theory (§4-A).

**Incidental observation:** step 2 produced a *second* full injection of `ask-before-test-changes.md` (~2.1 KB) for the second write in a row — issue E (no dedup) demonstrating itself in real time.

Both probe files were deleted immediately after; `git status` confirmed a clean tree.
