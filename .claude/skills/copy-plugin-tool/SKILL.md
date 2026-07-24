---
name: copy-plugin-tool
description: Copy a single agent, command, or skill out of an installed Claude Code plugin's cache directory into this repo's .claude/ or the user's ~/.claude/, stamping provenance (plugin name, version, release date, original tool name, copy date, bundled file dependencies) into its frontmatter. Trigger for requests like "copy the X skill from the ecc plugin", "grab that agent out of the plugin cache", "pull commit-pr out of ecc", bare plugin names used as a shorthand ("ecc", "ecc commit-pr"), or "I don't want to install the whole plugin, just this one tool." Distinct from /promote-artifact, which promotes artifacts already under ~/.claude/ — this skill is for tools still living inside ~/.claude/plugins/cache/.
triggers:
  - /copy-plugin-tool
args:
  - name: --plugin
    description: Plugin name or fuzzy hint, matched against installed plugins. Omit to browse all installed plugins.
    required: false
  - name: --tools
    description: Comma-separated tool name(s) or fuzzy hint(s) within the plugin. Omit to browse the plugin's agents/commands/skills.
    required: false
  - name: --scope
    description: "Destination: repo (<repo_root>/.claude/) or user (~/.claude/). Omit to be asked."
    required: false
---

# copy-plugin-tool

Extracts one tool from a plugin's cache directory as a standalone, provenance-stamped artifact — without installing the rest of the plugin.

## Invocation

```
/copy-plugin-tool [--plugin <hint>] [--tools <hint>[,<hint>...]] [--scope repo|user]
```

**Natural language:** a bare token matching an installed plugin name is `--plugin`; a following token or short phrase is a `--tools` hint. `"ecc commit-pr"` → `--plugin ecc --tools commit-pr` — fuzzy-matched, so it can resolve to `prp-commit` even without an exact name match. A bare plugin name alone (`"ecc"`) browses that plugin's tools.

---

## Step 1 — Resolve plugin

Source of truth: `~/.claude/plugins/installed_plugins.json` → `plugins["<name>@<marketplace>"][]`, each entry carrying `scope`, `installPath`, `version`, `installedAt`, `lastUpdated`, optional `gitCommitSha`.

- No `--plugin` → list every `<name>@<marketplace>` (version, scope), ask user to pick.
- `--plugin <hint>` → case-insensitive substring match against `<name>` and `<name>@<marketplace>`.
  - Zero matches → show the full list, ask again.
  - Multiple matches → list candidates, ask to disambiguate.
  - One match → continue.

## Step 2 — Resolve tool(s)

Read `<installPath>/.claude-plugin/plugin.json` (fallback `<installPath>/plugin.json`) for its `agents`/`commands`/`skills` path arrays. Fall back to `<installPath>/agents/`, `<installPath>/commands/`, `<installPath>/skills/` for any type it doesn't declare (this is the plugin spec's default and most plugins omit the field even when the directory exists).

Enumerate: commands/agents = every `*.md` file (recursive, keep subdir prefix); skills = every directory containing `SKILL.md`.

- No `--tools` → list all enumerated tools grouped by type, ask user to pick one or more.
- `--tools <hint>[,<hint>...]` → for each hint, case-insensitive substring match against the basename (minus `.md`) or skill dirname, across all three types.
  - Zero matches → report it, show the nearest candidates (share a token with the hint), ask to pick or skip.
  - Multiple matches → list, ask to disambiguate.

## Step 3 — Resolve scope

`--scope` given → use it. Otherwise ask: "Copy to repo (`<repo_root>/.claude/`) or user (`~/.claude/`)?"

Repo root: `$CLAUDE_PROJECT_DIR` env var, fallback `git rev-parse --show-toplevel`.

## Step 4 — Stage and pull in dependencies

Copy each selected tool into a scratch staging dir: skill → `cp -rp <skill-dir> <staging>/<name>/`; command/agent → `cp -p <file>.md <staging>/<name>.md`.

Read the staged file(s) and identify file references not already bundled — script/reference/asset paths, `source`/`bash`/`python3 <path>` invocations, relative includes — using the same static-scan-plus-judgment approach as validate-artifact's dependency-complete check (`.claude/skills/validate-artifact/SKILL.md`).

For each reference:
- Resolve it against the plugin's `installPath` (references are usually relative to the tool's own dir or the plugin root).
- Found inside the plugin → copy it into staging at the same relative path from the tool's root, creating parent dirs as needed, so the reference still resolves post-copy.
- Not found anywhere in the plugin → leave unresolved; Step 5 will surface it as a FAIL/WARN instead of guessing.

Record every path copied here — it becomes `file_dependencies` in Step 6.

## Step 5 — Validate

Run `/validate-artifact <staging>/<name>` (repo-agnostic, dependency-complete, terse — see `.claude/skills/validate-artifact/SKILL.md`, the same gate `/promote-artifact` uses).

- FAIL → report findings, delete staging, stop.
- WARN → show findings, ask "Proceed despite warnings? [y/N]".
- PASS → continue.

## Step 6 — Stamp provenance frontmatter

Merge a `source:` block into the staged file's YAML frontmatter — namespaced so it can't collide with the tool's own fields (`name`, `description`, `tools`, etc.):

```yaml
source:
  plugin: <plugin name>
  plugin_version: <from plugin.json, or the installPath version segment if plugin.json omits it>
  plugin_release_date: <installed_plugins.json "lastUpdated" for this plugin@marketplace, as YYYY-MM-DD>
  original_name: <file/dir name inside the plugin, before copy>
  copied_at: <today, YYYY-MM-DD, via `date +%Y-%m-%d`>
  file_dependencies:
    - <relative path pulled in during Step 4>
```

Omit `file_dependencies` entirely if Step 4 pulled in nothing extra. Load/merge/dump with Python's `yaml` module (as `/promote-artifact` does for `manifest.yaml`) so the rest of the frontmatter and body survive untouched.

## Step 7 — Copy to destination

```
repo dest:  <repo_root>/.claude/<type>s/<name>
user dest:  $HOME/.claude/<type>s/<name>
```

(commands/agents are single files `<name>.md`; skills are directories.)

If dest exists:
- Its frontmatter has a `source:` block with the same `plugin` + `original_name` → this is a re-copy of the same tool. Ask "Update existing <dest> with newer copy? [y/N]".
- Otherwise → ask "A different file already exists at <dest> (not a prior copy-plugin-tool output). Overwrite? [y/N]".
- `n` → skip, report `[SKIPPED]`.
- `y` / dest didn't exist → copy, report `[INSTALLED]` or `[UPDATED]`.

Delete the staging dir once done, whether copied or skipped.

## Step 8 — Summary

```
Copied:    <name> (<type>)
From:      <plugin>@<marketplace> v<version> (released <plugin_release_date>)
Deps:      <N> bundled file(s) pulled in | none
To:        <repo|user> — <dest path>
Validated: PASS | WARN (proceeded)
```
