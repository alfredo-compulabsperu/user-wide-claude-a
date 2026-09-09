#!/usr/bin/env python3
"""PreToolUse:Edit|Write|NotebookEdit|Read|Bash -- the unified lazy-rule injector (M5).

Loads any rule whose declared trigger matches the tool call, *before* the
action runs, deduped per (rule, subject, session):

    ---
    on:
      tools: [Edit, Write]            # required: tool names this rule governs
      paths: ["**/*.ts"]              # match tool_input.file_path (fnmatch, full path)
      commands: ["gh pr create*"]     # match tool_input.command (fnmatch)
    ---
    <rule body injected as additionalContext>

A rule fires when tool_name is in `tools` AND (a `paths` glob matches the
subject OR a `commands` glob matches it). Replaces ecc-typescript-rule-inject.py
and confirm-before-test-changes-rule-inject.py, which re-billed the full body on
every edit and fired after the write had landed.

Frontmatter is split by hand, not parsed with PyYAML: this runs on every edit
and must stay fast, and a hook should not assume the module exists.

Env overrides (tests point both at a tmp dir):
    LAZY_RULE_INJECT_RULE_DIRS   os.pathsep-separated dirs to scan recursively
    LAZY_RULE_INJECT_MARKER_DIR  where dedup markers live (default: tempdir)

Always exits 0 — an injector must never block the tool. Every skipped input
writes one line to stderr first (audit #6: no silent except).
"""
import fnmatch
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path

DEFAULT_RULE_DIRS = [Path.home() / ".claude" / "rules", Path.home() / ".claude" / "lazy" / "rules"]
PATH_TOOLS = {"Edit", "Write", "NotebookEdit", "Read"}
COMMAND_TOOLS = {"Bash"}
SEPARATOR = "\n\n---\n\n"


def warn(msg: str) -> None:
    print(f"lazy-rule-inject: {msg}", file=sys.stderr)


# ── Frontmatter ──────────────────────────────────────────────────────────────

def split_frontmatter(text: str):
    """Return (frontmatter_lines, body) or (None, text) when there is no block."""
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---\n", 4)
    if end == -1:
        raise ValueError("unterminated frontmatter")
    return text[4:end].split("\n"), text[end + 5:]


def _parse_list(value: str):
    """`[a, "b"]` flow list -> ['a', 'b']. Empty string means block list follows."""
    value = value.strip()
    if not value:
        return None
    if not (value.startswith("[") and value.endswith("]")):
        raise ValueError(f"expected a list, got {value!r}")
    return [item.strip().strip("\"'") for item in value[1:-1].split(",") if item.strip()]


def parse_on_block(lines):
    """Extract the `on:` mapping from frontmatter lines. Returns None if absent.

    Supports `key: [a, b]` and `key:` + `- item` forms under `on:`. Anything
    else under `on:` raises ValueError so the caller can skip the rule loudly.
    """
    on, current = None, None
    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        stripped = line.strip()
        if indent == 0:
            if on is not None:
                break  # left the on: block
            if stripped.startswith("on:"):
                if stripped[3:].strip():
                    raise ValueError("`on:` must be a mapping, not an inline value")
                on = {}
            continue
        if on is None:
            continue
        if stripped.startswith("- "):
            if current is None:
                raise ValueError("list item outside any key")
            on[current].append(stripped[2:].strip().strip("\"'"))
            continue
        key, sep, value = stripped.partition(":")
        if not sep:
            raise ValueError(f"unparseable line {stripped!r}")
        current = key.strip()
        on[current] = _parse_list(value) or []
    return on


# ── Rule index ───────────────────────────────────────────────────────────────

def rule_dirs():
    raw = os.environ.get("LAZY_RULE_INJECT_RULE_DIRS")
    return [Path(p) for p in raw.split(os.pathsep) if p] if raw else DEFAULT_RULE_DIRS


def load_rules():
    """Yield (rule_id, on, body) for every rule file carrying an `on:` block."""
    found_any_dir = False
    for base in rule_dirs():
        if not base.is_dir():
            continue
        found_any_dir = True
        for path in sorted(base.rglob("*.md")):
            rule_id = str(path.relative_to(base))
            try:
                fm, body = split_frontmatter(path.read_text())
                on = parse_on_block(fm) if fm is not None else None
            except (OSError, ValueError) as e:
                warn(f"skipping {rule_id}: {e}")
                continue
            if on:
                yield rule_id, on, body.strip()
    if not found_any_dir:
        warn("no rule directory found: " + os.pathsep.join(map(str, rule_dirs())))


# ── Matching ─────────────────────────────────────────────────────────────────

def subject_of(tool_name: str, tool_input: dict) -> str:
    if tool_name in PATH_TOOLS:
        return tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if tool_name in COMMAND_TOOLS:
        return tool_input.get("command") or ""
    return ""


def matches(on: dict, tool_name: str, subject: str) -> bool:
    if tool_name not in on.get("tools", []):
        return False
    is_path = tool_name in PATH_TOOLS
    patterns = on.get("paths" if is_path else "commands", [])
    return any(fnmatch.fnmatchcase(subject, pat) for pat in patterns)


# ── Dedup per (rule, subject, session) ───────────────────────────────────────

def session_of(payload: dict) -> str:
    sid = payload.get("session_id")
    if sid:
        return str(sid)
    transcript = payload.get("transcript_path")
    if transcript:
        return Path(transcript).stem
    warn("payload has no session_id/transcript_path; falling back to ppid (dedup may degrade)")
    return f"ppid-{os.getppid()}"


def marker_dir(session: str) -> Path:
    root = os.environ.get("LAZY_RULE_INJECT_MARKER_DIR") or tempfile.gettempdir()
    return Path(root) / f"lazy-rule-inject-{session}"


def first_time(rule_id: str, subject: str, session: str) -> bool:
    """Atomic once-per-(rule, subject, session): O_CREAT|O_EXCL, first process wins.
    If the marker dir cannot be written, fire anyway and warn — losing dedup is
    preferable to silently dropping a rule."""
    key = hashlib.sha1(f"{rule_id}\n{subject}".encode()).hexdigest()[:12]
    try:
        d = marker_dir(session)
        d.mkdir(parents=True, exist_ok=True)
        os.close(os.open(d / key, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
        return True
    except FileExistsError:
        return False
    except OSError as e:
        warn(f"marker dir unwritable ({e}); firing without dedup")
        return True


# ── Main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError) as e:
        warn(f"malformed payload: {e}")
        return
    if not isinstance(payload, dict):
        warn("payload is not a JSON object")
        return

    tool_name = payload.get("tool_name", "")
    subject = subject_of(tool_name, payload.get("tool_input") or {})
    if not subject:
        return

    session = session_of(payload)
    bodies = [
        body for rule_id, on, body in load_rules()
        if matches(on, tool_name, subject) and first_time(rule_id, subject, session)
    ]
    if not bodies:
        return
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "additionalContext": SEPARATOR.join(bodies),
        }
    }))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # last resort: never block the tool, never be silent
        warn(f"unexpected error: {type(e).__name__}: {e}")
    sys.exit(0)
