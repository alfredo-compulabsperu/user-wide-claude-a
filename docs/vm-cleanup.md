# vm-cleanup.sh

Scans and cleans common dev-VM disk consumers: apt cache, journald logs, npm
cache, `~/.cache` subdirs, snap disabled revisions, the Firebase emulator
cache, Trash, `node_modules`, stale git worktrees, and old `nvm` node
versions.

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
| **SAFE** | Automatically, in `--clean` mode (low risk, recoverable) | apt cache, journald logs, npm cache, `~/.cache` subdirs (`thumbnails`, `fontconfig`, `pip`) |
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

## Exit codes

- `0` — success, including scan mode, `--dry-run`, and a second run that finds
  nothing left to do.
- `1` — one or more actions failed; failed actions are listed under the
  `Summary` section of the output.

## Related

- `/vm-cleanup` — Claude Code command wrapping this script (`.claude/commands/vm-cleanup.md`).
- `/vm-health` — companion script that recommends running this one when disk usage is high.
