## US-VMCLEANUP-1: Reclaim dev-VM disk space via `/vm-cleanup`

**Status:** `Draft` · **Implementation:** `Closed` · **Issue:** —

**As** a developer running Claude Code on a shared dev VM, **I want** to run `/vm-cleanup` to scan and optionally clear common disk consumers, **so that** I can reclaim space without manually hunting caches, worktrees, and `node_modules`.

**Acceptance criteria:**

- Running `/vm-cleanup` with no flags MUST only scan and report targets with sizes, making no changes.
- Running `/vm-cleanup --clean` MUST execute SAFE-tier actions automatically (apt cache, journald logs, npm cache, `~/.cache` subdirs) and list RISKY-tier targets as skipped.
- Running `/vm-cleanup --clean --risky` MUST also execute RISKY-tier actions (git worktrees, `node_modules`, Trash, nvm versions, snap revisions, Firebase emulator cache), each still subject to their existing safety guards (self-worktree, locked, dirty, protected files).
- The command SHOULD print the script's full output verbatim without summarizing.
- A failing action MUST cause a non-zero exit and appear in the Summary section.

**Why:** `.claude/commands/vm-cleanup.md` wraps `.claude/scripts/vm-cleanup.sh`, implementing the SAFE/RISKY tiers documented in `docs/vm-cleanup.md:19-24`. Already shipped and covered by the existing test suite — this documents existing behavior rather than proposing new work. Verified against commit `a071e8d`.

## US-VMCLEANUP-2: Flag dangling Claude Code processes for review via `/vm-cleanup`

**Status:** `Draft` · **Implementation:** `Closed` · **Issue:** —

**As** a developer running Claude Code on a shared dev VM, **I want** `/vm-cleanup` to flag dangling `claude`/`bun`/`node` processes left behind by crashed or killed sessions, **so that** I can spot and manually clean up leaked resources without guessing which processes are safe to touch.

**Acceptance criteria:**

- Every `/vm-cleanup` run (scan or `--clean`) MUST scan for `claude`/`bun`/`node` processes with no live `claude` ancestor in their parent-PID chain.
- A flagged process MUST be reported under `[REVIEW]` with its PID, parent PID, and a suggested inspect/kill command, and MUST NOT be killed automatically under any flag combination.
- A fork-subagent (a `claude` process with `tty=?` whose direct parent is another live `claude` process) MUST NOT be flagged.
- The invoking script's own process tree MUST NOT be flagged, however far its ancestor chain runs.
- A flagged process without a controlling terminal (`tty=?`) SHOULD be annotated "likely leaked"; one with a real terminal SHOULD be annotated "verify before killing" — both remain report-only.

**Why:** Implemented this session in commit `37befd3`, documented in `docs/vm-cleanup.md:48-79`, covered by 7 assertions in `.claude/tests/scripts/vm-cleanup.test.sh` (synthetic-fixture-based, GREEN). Verified against commit `a071e8d`.

## US-VMCLEANUP-3: Delete only clean, pushed git worktrees via `/vm-cleanup`

**Status:** `Draft` · **Implementation:** `Closed` · **Issue:** —

**As** a developer running Claude Code on a shared dev VM, **I want** `/vm-cleanup` to identify and remove only git worktrees that are clean (no uncommitted changes) and fully pushed, **so that** I can reclaim disk space from stale worktrees without risking unpushed or in-progress work.

**Acceptance criteria:**

- A worktree MUST NOT be removed if it has uncommitted changes, is locked, has no upstream tracking branch, is ahead of its upstream, or its git status can't be read.
- A worktree MUST NOT be removed if it's the one `/vm-cleanup` is currently running from.
- Protected files inside an otherwise-removable worktree MUST be rescued to `~/.claude/cleanup-rescue/<worktree>-<timestamp>/` before removal; a failed rescue MUST abort the removal.
- Worktree removal MUST only execute under `--clean --risky`, never plain `--clean`.

**Why:** Narrows US-VMCLEANUP-1's bundled RISKY-tier worktree bullet into its own dedicated story. Already implemented — `.claude/scripts/vm-cleanup.sh` section 10, `docs/vm-cleanup.md:36-46`, covered by the existing test suite. Verified against commit `a071e8d`.

**Scope note:** Duplicates no capability — narrows US-VMCLEANUP-1's existing bullet into full detail; both describe the same already-shipped behavior.

## US-VMCLEANUP-4: Reclaim full `~/.cache` as a SAFE-tier target (excluding `firebase/emulators`)

**Status:** `Draft` · **Implementation:** `Closed` · **Issue:** —

**As** a developer running Claude Code on a shared dev VM, **I want** `/vm-cleanup --clean` to automatically reclaim the entire `~/.cache` directory (except `firebase/emulators`), **so that** I recover disk space from regenerable tool caches without `--risky` or manual cleanup.

**Acceptance criteria:**

- `/vm-cleanup --clean` MUST delete `~/.cache` in full, **except** `~/.cache/firebase/emulators`, which MUST remain excluded and stay a separate RISKY-tier item exactly as today.
- This deletion MUST remain SAFE tier — every verified subdirectory is a regenerable tool cache, not user data (see Why).
- This deletion SHOULD NOT require the existing protected-file scan — verified false-positive-prone against `.cache`'s contents (see Why) — and MAY skip it.

**Why:** Full inventory (2026-09-15): `.cache`'s top-level is entirely tool caches — `uv/` (5.4G), `ms-playwright/`+`ms-playwright-mcp/` (1.2G), `puppeteer/` (636M), `huggingface/` (464M), `go-build/` (285M), `claude-cli-nodejs/` (278M, MCP logs), `code-server/`, `node-gyp/`, browser caches, `typescript/`, `gh/`, `sessions/`, `Microsoft/`, `mslearn/` — all re-download/rebuild on next use. Protected-pattern scan (`.env`/`*.pem`/`*secret*`/etc.) against all of `.cache` returned zero real secrets — every hit was a false positive: either third-party library source code (`botocore/credentials.py`, `keyring/credentials.py`, `certifi/cacert.pem`, the `secretstorage` package, all inside `uv`'s cache) or a `claude-cli-nodejs` log directory coincidentally named after a worktree/branch called "secrets" (contents are just `mcp-logs-*` log dirs). Verified against commit `a071e8d`.

**Scope note:** Excludes `.cache/firebase/emulators` (stays RISKY, unchanged — user directive), `.local` (real installed software: pip `--user` packages, `$PATH` binaries, possibly rclone credentials), `.claude-tmp` (shared scratch root, actively used by concurrent sessions), and `.claude` (live config, never a target). See US-VMCLEANUP-5 for `.vscode-server`.

## US-VMCLEANUP-5: Prune stale VS Code Remote server versions under `~/.vscode-server`

**Status:** `Draft` · **Implementation:** `Closed` · **Issue:** —

**As** a developer running Claude Code on a shared dev VM, **I want** `/vm-cleanup --clean` to prune stale VS Code Remote server versions under `~/.vscode-server`, keeping the currently-active one, **so that** I reclaim disk space without forcing a VS Code reconnect or redownload.

**Acceptance criteria:**

- `/vm-cleanup --clean` MUST identify the currently-active version via the single entry under `~/.vscode-server/bin/`, and MUST delete every `~/.vscode-server/cli/servers/Stable-*` entry whose hash doesn't match it, plus any empty/`.staging` entries.
- `/vm-cleanup --clean` MUST NOT touch `~/.vscode-server/extensions/`, `~/.vscode-server/data/`, or the currently-active `bin/<hash>/`/`cli/servers/Stable-<hash>/` pair.
- This pruning MUST remain SAFE tier — every deleted path is a confirmed-stale, unreferenced version, never the active install (see Why).
- A second consecutive run MUST be a no-op — idempotent by construction.

**Why:** `cli/servers/` holds 7 full server installs (~485-629M each, ~3.4G total) accumulated since March 2026 — VS Code Remote-SSH never auto-prunes old versions on client update. A full wipe would force a redownload of the currently-active version on next reconnect; pruning only stale ones reclaims ~3G immediately with zero reconnect impact. Verified against commit `a071e8d`, live inspection 2026-09-15.

**Scope note:** Same exclusion list as US-VMCLEANUP-4 (`.local`, `.claude-tmp`, `.claude`) — none touched here either.

## Version History

| Version | Date | Commit | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-09-15 | a071e8d | Initial: US-VMCLEANUP-1, US-VMCLEANUP-2 |
| 1.1 | 2026-09-15 | a071e8d | Added: US-VMCLEANUP-3 (worktree cleanup, narrows US-VMCLEANUP-1), US-VMCLEANUP-4 (`.cache` SAFE-tier target), US-VMCLEANUP-5 (`.vscode-server` stale-version pruning) |
| 1.2 | 2026-09-15 | a071e8d | Added `Implementation` field (GitHub issue-state vocabulary: `Open`/`Closed`) to all 5 stories, distinct from `Status` (agreement state) |
| 1.3 | 2026-09-15 | f8c5324, 6072237 | US-VMCLEANUP-4 and US-VMCLEANUP-5 `Implementation: Open → Closed` — landed via `.claude/plans/vm-cleanup-cache-vscode-pruning.plan.md` (full `.cache` wipe, `.vscode-server` stale-version pruning) |
