# User-Wide Claude Plugin Packaging

## Problem
A solo developer running Claude Code across multiple machines ships user-wide tooling via a hand-rolled `sync.sh` + `manifest.yaml` script that requires a manual re-run on every machine to pick up updates, and offers no fine-grained control over exactly which artifacts get installed where. Claude Code's native plugin system supports semver-tracked, auto-updating distribution of skills/commands/agents/hooks, but does not natively bundle `CLAUDE.md` or rules content — so no single mechanism today combines automatic updates with full coverage of this repo's artifact types.

## Evidence
- Assumption — needs validation via real multi-machine usage after install. No concrete incident triggered this; it's an anticipated architectural improvement.
- Confirmed via official docs (code.claude.com/docs/en/plugins-reference.md, plugins.md): plugins natively support skills, commands, agents, hooks, MCP/LSP servers, and a semver `version` field; they do **not** support loading a plugin-root `CLAUDE.md` as project context, and there is no manifest field for a `rules/` directory. A custom installer is required for those two artifact types.

## Users
- **Primary**: solo developer (you), managing Claude Code setup across your own machines
- **Not for**: teams, shared/multi-user distribution, other users' environments

## Hypothesis
We believe **packaging this repo's portable tooling as a versioned Claude Code plugin (skills, commands, agents, hooks, scripts, output styles) plus a custom `/install-claude-tools` installer for `CLAUDE.md` and rules** will **give fine-grained, opt-in control over what ships user-wide and eliminate manual `sync.sh` re-runs for updates** for **you, across your own machines**.
We'll know we're right when **a machine can install/update this tooling through the plugin mechanism (auto-updating skills/commands/agents/hooks via semver) and selectively apply `CLAUDE.md`/rules through the installer — without hand-editing `manifest.yaml` or running `sync.sh` by hand**.

## Success Metrics
| Metric | Target | How measured |
|---|---|---|
| Manual `sync.sh`/`manifest.yaml` edits needed to pick up an update | 0 | Walk through an update on a test machine post-install |
| `CLAUDE.md`/rules install-scope control | Explicit user-or-repo choice every run | Run `/install-claude-tools`, confirm scope prompt |
| Artifact-level install control | Can opt out of at least one artifact category | Attempt a selective install via the plugin/installer |

## Scope
**MVP**:
- Repo restructured as a valid plugin (`plugin.json` with semver; existing skills/commands/agents/hooks bundled as-is)
- `/install-claude-tools` interactive installer applying `CLAUDE.md` + rules at user or repo scope
- `promote-artifact` consolidated to one skill: accepts a named Claude Code tool to import/promote, or — if none given — interactively asks whether to scan the repo or user-wide `~/.claude` for importable/updated tools
- CI/CD step that bumps `plugin.json` semver on merge

**Out of scope**
- Team/shared distribution — solo use only
- Non-Linux OS support
- Silent auto-apply of `CLAUDE.md`/rules — installer always requires explicit invocation, never overwrites without asking
- `settings.json` sync — excluded already in the prior portability PRD (secrets risk), stays excluded
- New merge/diff UI beyond existing skip/overwrite/prompt idempotency modes

## Delivery Milestones
| # | Milestone | Outcome | Status | Plan |
|---|---|---|---|---|
| 1 | Plugin manifest scaffold | Repo has a valid `plugin.json` (semver) with existing skills/commands/agents/hooks/scripts declared and installable via the plugin mechanism | pending | — |
| 2 | CLAUDE.md/rules installer | `/install-claude-tools` lets the user apply CLAUDE.md + rules at user or repo scope, on demand | pending | — |
| 3 | `promote-artifact` consolidation | Single skill accepts a named tool to import/promote, or interactively asks repo-vs-user-wide scan when none given | pending | — |
| 4 | Repo-agnostic enforcement | Every bundled artifact is validated as repo-agnostic before being included in a plugin release | pending | — |
| 5 | CI/CD semver automation | Merges bump `plugin.json` version automatically; release published with a changelog | pending | — |

## Open Questions
- [ ] Does `promote-artifact` stay one file, or one skill directory with internal branching (import-named / scan-repo / scan-user-wide)?
- [ ] How is "repo-agnostic" enforced going forward — folded into existing `validate-artifact`, or a new CI check?
- [ ] Does `sync.sh` get deprecated once the plugin path works, or kept as a non-plugin fallback?
- [ ] Does "fine-grained control" mean per-artifact opt-in at install time, or coarser (whole categories: skills vs. commands vs. agents)?

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| CLAUDE.md/rules installer silently overwrites user edits on target machine | Medium | Medium | Installer always prompts/diffs before applying, matching `sync.sh`'s existing idempotency pattern |
| Confusion between old `sync.sh` path and new plugin path during transition | Medium | Low | Document both paths clearly until the deprecation open question is resolved |
| `copy-plugin-tool` and similar user-wide-only tools stay untracked by this repo | Medium | Medium | Milestone 4's repo-agnostic enforcement should also catch tools that exist in `~/.claude/` but never made it into the repo |

---
*Status: DRAFT — requirements only. Implementation planning pending via /plan.*
