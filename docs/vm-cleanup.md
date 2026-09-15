# vm-cleanup.sh

Scans and cleans common dev-VM disk consumers: apt cache, journald logs, npm
cache, `~/.cache` (full wipe, excluding `firebase/`), stale VS Code Remote
server versions under `~/.vscode-server`, snap disabled revisions, the
Firebase emulator cache, Trash, `node_modules`, stale git worktrees, and old
`nvm` node versions. Also reports (never kills) dangling Claude Code
processes — see [Dangling process detection](#dangling-process-detection).

## Usage

```bash
vm-cleanup.sh                  # scan only; print targets with sizes
vm-cleanup.sh --dry-run        # same as scan only, explicit alias; overrides --clean/--risky
vm-cleanup.sh --clean          # execute SAFE; list RISKY targets (skipped)
vm-cleanup.sh --clean --risky  # execute SAFE + RISKY
vm-cleanup.sh -h | --help      # show help
```

## Classification

| Tier | Executes | Targets |
|---|---|---|
| **SAFE** | Automatically, in `--clean` mode (low risk, recoverable) | apt cache, journald logs, npm cache, `~/.cache` in full (except `firebase/`, which stays RISKY-tier — see below), stale `~/.vscode-server` versions (keeps the current one) |
| **RISKY** | Only with `--clean --risky` (higher risk / harder to recover) | git worktrees (clean, pushed, unlocked only), `node_modules` outside active worktrees, Trash, old `nvm` node versions, snap disabled revisions, Firebase emulator cache |

## Protected files

Never deleted, at any depth: `.env` `.env.*` `*.local.json`
`serviceAccountKey*` `*.pem` `*.key` `*secret*` `*credential*`.

When a removable worktree contains protected files, they are moved to
`~/.claude/cleanup-rescue/<worktree>-<timestamp>/` before the worktree is
removed. If the rescue itself fails (e.g. the rescue directory isn't
writable), the removal is aborted and the worktree is left in place.

## Guards (git worktrees and `node_modules`)

A worktree, or the `node_modules` inside one, is never touched if any of
these hold:

- it's the worktree the script is currently running from
- it's locked (`git worktree lock`)
- it has uncommitted changes
- its git status can't be read
- it has no upstream tracking branch
- it's ahead of its upstream (unpushed commits)

## Dangling process detection

Every run (scan or `--clean`) also scans the process table for `claude`,
`bun`, and `node` processes with no live `claude` ancestor — leftovers from a
crashed or killed Claude Code session (its MCP server subprocesses reparent
to init or a subreaper like tmux instead of exiting). These are reported
under `[REVIEW]` with the suspect PID, its parent PID, and a suggested
inspect/kill command. **They are never killed automatically, under any flag
combination** — the script only ever reports them.

Detection walks each candidate's parent-PID chain looking for a live `claude`
process; a chain that never finds one is flagged. This deliberately does not
rely on `ppid == 1`, because a subreaper (tmux, `systemd --user`) can
reparent an orphan to itself rather than to init. A fork-subagent — a
`claude` process with `tty=?` whose direct parent is another live `claude`
process — has a live ancestor and is never flagged, regardless of its `tty`.

`claude` processes themselves are only ever reported, never a kill
candidate under any tier: a background/headless `claude` run legitimately
looks identical to a dead one from the process table alone, and killing a
live one destroys in-progress agent work with no rescue path (unlike the
file deletions above, which are rescued to `~/.claude/cleanup-rescue/`).

The report annotates each finding for manual judgment, but doesn't act on
it:
- **No controlling terminal** (`tty=?`) — likely leaked; safest to inspect
  first (`ps -fp <pid>`), then `kill -TERM <pid>` if confirmed unwanted.
- **Has a terminal** — may be an intentionally backgrounded/disowned job;
  verify before killing.

This script's own process tree (and its invoking Claude Code session, if
any) is never reported, however far its ancestor chain runs.

## VS Code Remote server pruning

`~/.vscode-server/cli/servers/` accumulates a full server install
(hundreds of MB each) for every VS Code Remote-SSH client update, since the
client never prunes old versions on its own. Every run with `--clean`
identifies the currently-active version via the single directory under
`~/.vscode-server/bin/`, then deletes every `cli/servers/` entry that isn't
exactly `Stable-<current-hash>` — this naturally also removes incomplete
`.staging` entries with no special-casing needed.

This is why it's safe: every deleted entry is a confirmed-stale,
unreferenced version — never the one the active VS Code Remote connection
is using — so pruning never forces a reconnect or redownload. It never
touches `~/.vscode-server/extensions/`, `~/.vscode-server/data/`, or the
current `bin/`/`cli/servers/` pair.

If `~/.vscode-server/bin/` doesn't have exactly one entry (e.g. a client
update is mid-flight), pruning is skipped entirely with an explanatory
message rather than guessing which version is current. A second
consecutive `--clean` run is a no-op once nothing stale remains.

## Exit codes

- `0` — success, including scan mode, `--dry-run`, and a second run that finds
  nothing left to do.
- `1` — one or more actions failed; failed actions are listed under the
  `Summary` section of the output.

## Related

- `/vm-cleanup` — Claude Code command wrapping this script (`.claude/commands/vm-cleanup.md`).
- `/vm-health` — companion script that recommends running this one when disk usage is high.
