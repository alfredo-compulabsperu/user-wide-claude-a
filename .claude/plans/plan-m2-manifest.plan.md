# Plan: M2 — Manifest Format

**Source PRD**: `.claude/prds/user-wide-claude-portability.prd.md`
**Selected Milestone**: M2 — Manifest format
**Complexity**: Small

## Summary

Define and populate a `manifest.yaml` at the repo root that catalogs every portable user-wide Claude artifact. The manifest is the single input the M3 sync script needs to install all artifacts on a new machine. This plan resolves all open questions from the PRD before any file is written.

## Open Question Resolutions

| # | Question | Decision | Rationale |
|---|---|---|---|
| 1 | Flat file vs directory inference? | **Flat YAML file** (`manifest.yaml` at repo root) | Plugins cannot be inferred from directories — they need id+marketplace. A flat file allows explicit opt-in/opt-out and supports human annotation. |
| 2 | Idempotency behavior? | **Skip if SHA-256 matches; prompt if different; `--force` overwrites** | Protects local customizations (PRD risk #2) while keeping the default safe. Force mode satisfies "fresh machine" parity. |
| 3 | Is `CLAUDE.md` portable? | **Yes — fully portable** | Audited: uses `${CLAUDE_PROJECT_DIR}`, no absolute paths, no machine-specific credentials. Mark `portable: true`. |
| 4 | Plugin reinstall fields? | **`id`, `marketplace`, `scope`** | `claude plugin install <id> --marketplace <marketplace>` is the reinstall command. `scope: user` distinguishes from project-scoped plugins (excluded per PRD). |

## Patterns to Mirror

No prior manifest or sync pattern exists in this repo — it is newly initialized. The schema below is the first-of-kind. Conventions sourced from `installed_plugins.json` (existing plugin registry format) and standard Unix manifest idioms.

## Manifest Schema

```yaml
version: 1                      # bump on breaking schema changes
generated: "YYYY-MM-DD"         # last full population date
idempotency: skip               # skip | overwrite | prompt — sync script default

skills:
  - name: <dir-or-file>         # relative to ~/.claude/skills/

commands:
  - name: <file-or-subpath>     # relative to ~/.claude/commands/

agents:
  - name: <file>                # relative to ~/.claude/agents/

scripts:
  - name: <file>                # relative to ~/.claude/scripts/
    executable: true            # optional; sync chmod +x on install

claude_md:
  portable: true                # if false, skip on install

plugins:
  - id: <plugin-id>             # matches <id>@<marketplace> in installed_plugins.json
    marketplace: <marketplace>
    scope: user                 # only user-scoped plugins in manifest
```

## Current Artifact Inventory (as of 2026-06-09)

**Skills** (19):
`humanizer`, `learned`, `legal`, `legal-agreement`, `legal-compare`, `legal-compliance`,
`legal-freelancer`, `legal-missing`, `legal-nda`, `legal-negotiate`, `legal-plain`,
`legal-privacy`, `legal-report-pdf`, `legal-review`, `legal-risks`, `legal-terms`,
`skill-stocktake`, `worktree-cleaner`, `worktree-summary`

**Commands** (7 + 1 archived subdir):
`claude-yolo.md`, `merge-branches.md`, `merge-from-main.md`, `prp-prd-auto.md`,
`session-summary.md`, `vm-cleanup.md`, `archived/merge-to-main.md`

**Agents** (7):
`legal-clauses.md`, `legal-compliance.md`, `legal-recommendations.md`,
`legal-risks.md`, `legal-terms.md`, `linux-dev-vm-expert.md`, `prd-answerer.md`

**Scripts** (1):
`vm-cleanup.sh` (executable)

**CLAUDE.md**: portable — no machine-specific content

**Plugins** (3 user-scoped):
- `context-mode` @ `context-mode`
- `commercial-legal` @ `claude-for-legal`
- `employment-legal` @ `claude-for-legal`

Note: `ralph-loop@claude-plugins-official` is project-scoped — excluded per PRD.

## Files to Change

| File | Action | Why |
|---|---|---|
| `manifest.yaml` | CREATE at repo root | The manifest itself — consumed by M3 sync script |
| `.claude/prds/user-wide-claude-portability.prd.md` | UPDATE M2 row | Mark status `in-progress`, add plan path |

## Tasks

### Task 1: Write `manifest.yaml`

- **Action**: Create `manifest.yaml` at repo root using the schema above, populated with the full inventory from the "Current Artifact Inventory" section.
- **Mirror**: `~/.claude/plugins/installed_plugins.json` schema conventions for plugin entries.
- **Validate**: `python3 -c "import yaml; yaml.safe_load(open('manifest.yaml'))"` — must parse without error.

### Task 2: Update PRD milestone row

- **Action**: In `.claude/prds/user-wide-claude-portability.prd.md`, update M2's table row:
  - Status: `pending` → `in-progress`
  - Plan column: `.claude/plans/plan-m2-manifest.plan.md`
- **Mirror**: Same table row format as M1 (complete).
- **Validate**: Visual check — table renders correctly in markdown.

### Task 3: Update loop runbook

- **Action**: In `.claude/plans/portability-loop-runbook.md`, mark M2 row as `done`.
- **Validate**: File updated, M3 row still `pending`.

## Validation

```bash
python3 -c "import yaml; yaml.safe_load(open('manifest.yaml'))"

python3 -c "
import yaml
d = yaml.safe_load(open('manifest.yaml'))
print('skills:', len(d['skills']))
print('commands:', len(d['commands']))
print('agents:', len(d['agents']))
print('scripts:', len(d['scripts']))
print('plugins:', len(d['plugins']))
"
# Expected: skills:19, commands:7, agents:7, scripts:1, plugins:3
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `skills/learned/` contains machine-local instincts | Medium | Include in manifest — instincts are user-curated and portable by intent; machines diverging is normal and sync will prompt |
| Plugin reinstall command changes in future Claude versions | Low | Document `claude plugin install <id> --marketplace <marketplace>` at time of writing; M3 sync script pins to this form |
| New artifacts added after manifest is written | High | M3 sync script's `--dry-run` mode will surface local-only files; manifest is hand-maintained until a future auto-populate command |

## Acceptance

- [ ] `manifest.yaml` exists at repo root
- [ ] `python3 -c "import yaml; yaml.safe_load(open('manifest.yaml'))"` exits 0
- [ ] All 5 artifact sections present: `skills`, `commands`, `agents`, `scripts`, `plugins`
- [ ] `claude_md.portable: true` present
- [ ] Plugin count = 3 (user-scoped only)
- [ ] PRD M2 row updated to `in-progress` with plan path
