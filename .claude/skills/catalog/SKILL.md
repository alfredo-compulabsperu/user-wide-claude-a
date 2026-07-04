---
name: catalog
description: Summarize every artifact declared in manifest.yaml — skills, commands, agents, scripts, claude_md, and plugins — as grouped markdown tables, cross-checked against the repo's .claude/ source files to flag anything missing. Invoke explicitly via /catalog when the user asks to summarize, catalog, or list what's registered in the manifest.
triggers:
  - /catalog
args:
  - name: manifest_path
    description: Path to manifest.yaml. Defaults to manifest.yaml at the repo root.
    required: false
---

# catalog

Summarizes `manifest.yaml`: what's declared, grouped by type, cross-checked
against the repo's own `.claude/` source files (not `~/.claude/` — this
reports on manifest accuracy, not sync state).

## Invocation

```
/catalog [path-to-manifest.yaml]
```

Defaults to `manifest.yaml` at the repo root if no path is given. If a
relative path is given, resolve it to an absolute path against the repo
root *before* substituting below — do not pass a bare relative string
through unresolved (the script itself resolves paths against the python
process's CWD, not the repo root, so an unresolved relative path can
silently point at the wrong file).

## How it works

Substitute `<manifest_path>` with an **already-resolved absolute path**,
single-quoted using standard shell escaping (replace each `'` in the value
with `'\''` and wrap the whole value in single quotes). Do not use double
quotes and do not substitute the raw value unescaped — `manifest_path` is
caller-supplied, and a double-quoted substitution can be broken out of by a
value containing `"`, `$`, or backticks. The env-var pass-through for the
YAML *contents* (as opposed to the path itself) mirrors `sync.sh`'s own
`yaml_get_*` helpers.

```bash
MANIFEST_PATH='<manifest_path, single-quote-escaped>' python3 - <<'PYEOF'
import yaml, os, sys

manifest_path = os.environ['MANIFEST_PATH']
repo_dir = os.path.dirname(os.path.abspath(manifest_path)) or "."
claude_dir = os.path.join(repo_dir, ".claude")

d = yaml.safe_load(open(manifest_path)) or {}

def name_of(item):
    return item.get('name') if isinstance(item, dict) else item

def status(path, is_dir):
    exists = os.path.isdir(path) if is_dir else os.path.isfile(path)
    return "✓" if exists else "✗ MISSING"

def rows_for(key, is_dir):
    rows = []
    for item in d.get(key, []):
        n = name_of(item)
        if not isinstance(n, str) or not n:
            rows.append((repr(n), "✗ INVALID (missing/blank name)"))
            continue
        path = os.path.join(claude_dir, key, n)
        rows.append((n, status(path, is_dir=is_dir(path) if callable(is_dir) else is_dir)))
    return rows

sections = []
total = 0
missing = 0

sections.append(("skills", ["name", "status"], rows_for('skills', is_dir=True)))
sections.append(("commands", ["name", "status"], rows_for('commands', is_dir=os.path.isdir)))
sections.append(("agents", ["name", "status"], rows_for('agents', is_dir=False)))

# scripts — files, note declared executable flag; not run through rows_for
# because of the extra 'executable' column
rows = []
for item in d.get('scripts', []):
    n = item.get('name')
    if not isinstance(n, str) or not n:
        rows.append((repr(n), "n/a", "✗ INVALID (missing/blank name)"))
        continue
    exe = "yes" if item.get('executable') else "no"
    path = os.path.join(claude_dir, 'scripts', n)
    rows.append((n, exe, status(path, is_dir=False)))
sections.append(("scripts", ["name", "executable", "status"], rows))

# claude_md — single file, only expected when portable: true
cm = d.get('claude_md', {}) or {}
portable = "yes" if cm.get('portable') else "no"
cm_path = os.path.join(claude_dir, 'CLAUDE.md')
cm_status = status(cm_path, is_dir=False) if cm.get('portable') else "n/a (portable: false)"
sections.append(("claude_md", ["file", "portable", "status"], [("CLAUDE.md", portable, cm_status)]))

# plugins — not repo-local files; installed via marketplace, so no MISSING
# check, just declared id/marketplace/scope
plugin_rows = [(p.get('id', ''), p.get('marketplace', ''), p.get('scope', '')) for p in d.get('plugins', [])]
sections.append(("plugins", ["id", "marketplace", "scope"], plugin_rows))

for title, headers, rows in sections:
    print(f"### {title} ({len(rows)})")
    print("| " + " | ".join(headers) + " |")
    print("|" + "|".join(["---"] * len(headers)) + "|")
    for r in rows:
        print("| " + " | ".join(str(x) for x in r) + " |")
    print()
    if title != "plugins":
        total += len(rows)
        missing += sum(1 for r in rows if "MISSING" in str(r[-1]) or "INVALID" in str(r[-1]))

print(f"**Total tracked artifacts:** {total}  |  **Missing/invalid:** {missing}  |  **Plugins:** {len(plugin_rows)}")
PYEOF
```

Before relaying output: check the command's exit code. If non-zero, show
the user the stderr/traceback and say the catalog is incomplete — do not
present partial stdout (e.g. only the first few sections, printed before a
later section crashed) as if it were the complete report. On a zero exit
code, relay the script's stdout to the user verbatim as the catalog — do
not re-derive counts or re-check file existence by hand.

## Notes

- A section absent from `manifest.yaml` (e.g. `skills: []`) prints as `(0)`
  with an empty table, not an error.
- A manifest entry with a missing or blank `name` is reported as
  `✗ INVALID (missing/blank name)`, distinct from `✗ MISSING`, so a
  malformed manifest isn't mistaken for an artifact that just hasn't been
  synced yet.
- `plugins` have no repo-local file to check — a plugin can only be verified
  as *installed* via `~/.claude/plugins/installed_plugins.json` on the
  current machine, which is out of scope for a manifest-accuracy report. List
  them as declared; they're excluded from the total/missing counts.
- If `manifest_path` doesn't exist, `python3` raises `FileNotFoundError` —
  let it surface (via the exit-code check above) rather than adding a guard
  clause; the traceback already names the missing path. The same applies to
  `yaml.YAMLError` on malformed YAML.
