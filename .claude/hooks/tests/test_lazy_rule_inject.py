"""Black-box tests for lazy-rule-inject.py — the M5 unified PreToolUse injector.

Run: python3 -m pytest .claude/hooks/tests/ -q

Each test drives the hook exactly as Claude Code does: JSON on stdin, JSON (or
nothing) on stdout, exit 0 always. Rule dirs and the dedup marker dir are
pointed at a per-test tmp path via env, so no test touches ~/.claude or the
real session throttle (plan Task 2.1, GOTCHA 1).
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

HOOK = Path(__file__).resolve().parents[1] / "lazy-rule-inject.py"

TS_RULE = """---
on:
  tools: [Edit, Write]
  paths: ["**/*.ts", "**/*.tsx"]
---
TS BODY
"""

PR_RULE = """---
on:
  tools: [Bash]
  commands: ["gh pr create*"]
---
PR BODY
"""


def write_rule(rules: Path, name: str, text: str) -> None:
    rules.mkdir(parents=True, exist_ok=True)
    (rules / name).write_text(text)


def run_hook(tmp: Path, payload, rules: Path | str | None = None):
    """Invoke the hook once. `payload` may be a dict or a raw string."""
    env = {
        **os.environ,
        "LAZY_RULE_INJECT_RULE_DIRS": str(rules if rules is not None else tmp / "rules"),
        "LAZY_RULE_INJECT_MARKER_DIR": str(tmp / "markers"),
    }
    data = payload if isinstance(payload, str) else json.dumps(payload)
    return subprocess.run(
        [sys.executable, str(HOOK)],
        input=data, capture_output=True, text=True, env=env, timeout=10,
    )


def write_payload(path: str, session: str = "s1", tool: str = "Write") -> dict:
    return {"session_id": session, "tool_name": tool, "tool_input": {"file_path": path}}


def bash_payload(command: str, session: str = "s1") -> dict:
    return {"session_id": session, "tool_name": "Bash", "tool_input": {"command": command}}


def context_of(result) -> str:
    """Parse stdout as the hook output contract and return additionalContext."""
    out = json.loads(result.stdout)
    hso = out["hookSpecificOutput"]
    assert hso["hookEventName"] == "PreToolUse"
    return hso["additionalContext"]


# ── Firing ────────────────────────────────────────────────────────────────────

def test_matching_path_fires_with_rule_body(tmp_path):
    write_rule(tmp_path / "rules", "ts.md", TS_RULE)
    r = run_hook(tmp_path, write_payload("/w/src/app.ts"))
    assert r.returncode == 0
    assert "TS BODY" in context_of(r)


def test_non_matching_path_is_silent(tmp_path):
    write_rule(tmp_path / "rules", "ts.md", TS_RULE)
    assert "TS BODY" in context_of(run_hook(tmp_path, write_payload("/w/a.ts")))  # sanity: rule is live
    r = run_hook(tmp_path, write_payload("/w/README.md"))
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_command_trigger_fires_for_bash(tmp_path):
    write_rule(tmp_path / "rules", "pr.md", PR_RULE)
    r = run_hook(tmp_path, bash_payload("gh pr create --base develop --title x"))
    assert "PR BODY" in context_of(r)


def test_tool_not_in_on_tools_is_silent(tmp_path):
    write_rule(tmp_path / "rules", "ts.md", TS_RULE)
    assert "TS BODY" in context_of(run_hook(tmp_path, write_payload("/w/a.ts")))  # sanity
    r = run_hook(tmp_path, write_payload("/w/b.ts", tool="Read"))
    assert r.stdout.strip() == ""


def test_two_rules_matching_same_subject_both_fire(tmp_path):
    write_rule(tmp_path / "rules", "ts.md", TS_RULE)
    write_rule(tmp_path / "rules", "ts2.md", TS_RULE.replace("TS BODY", "SECOND BODY"))
    ctx = context_of(run_hook(tmp_path, write_payload("/w/a.ts")))
    assert "TS BODY" in ctx and "SECOND BODY" in ctx


# ── Dedup per (rule, subject) ────────────────────────────────────────────────

def test_second_call_same_subject_is_silent(tmp_path):
    write_rule(tmp_path / "rules", "ts.md", TS_RULE)
    assert "TS BODY" in context_of(run_hook(tmp_path, write_payload("/w/a.ts")))
    r = run_hook(tmp_path, write_payload("/w/a.ts"))
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_different_subject_fires_again(tmp_path):
    write_rule(tmp_path / "rules", "ts.md", TS_RULE)
    assert "TS BODY" in context_of(run_hook(tmp_path, write_payload("/w/a.ts")))
    assert "TS BODY" in context_of(run_hook(tmp_path, write_payload("/w/b.ts")))


def test_dedup_is_scoped_per_session(tmp_path):
    write_rule(tmp_path / "rules", "ts.md", TS_RULE)
    assert "TS BODY" in context_of(run_hook(tmp_path, write_payload("/w/a.ts", session="s1")))
    assert "TS BODY" in context_of(run_hook(tmp_path, write_payload("/w/a.ts", session="s2")))


# ── Dev override: a repo's settings.json can point the scan at itself ────────

def test_rule_dirs_env_expands_variables(tmp_path, monkeypatch):
    """settings.json env values reach the hook unexpanded; the hook must expand them."""
    write_rule(tmp_path / "repo" / ".claude" / "rules", "ts.md", TS_RULE)
    monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path / "repo"))
    r = run_hook(tmp_path, write_payload("/w/a.ts"), rules="${CLAUDE_PROJECT_DIR}/.claude/rules")
    assert r.returncode == 0
    assert "TS BODY" in context_of(r)


# ── Failure modes: never block the tool, never fail silently ─────────────────

def test_malformed_payload_exits_zero_and_warns(tmp_path):
    r = run_hook(tmp_path, "not json")
    assert r.returncode == 0
    assert r.stdout.strip() == ""
    assert r.stderr.strip() != ""


def test_missing_rule_dir_exits_zero_and_warns(tmp_path):
    r = run_hook(tmp_path, write_payload("/w/a.ts"), rules=tmp_path / "does-not-exist")
    assert r.returncode == 0
    assert r.stdout.strip() == ""
    assert r.stderr.strip() != ""


def test_malformed_frontmatter_skips_that_rule_and_continues(tmp_path):
    write_rule(tmp_path / "rules", "bad.md", "---\non: [this is: not a block\n---\nBAD BODY\n")
    write_rule(tmp_path / "rules", "ts.md", TS_RULE)
    r = run_hook(tmp_path, write_payload("/w/a.ts"))
    ctx = context_of(r)
    assert "TS BODY" in ctx and "BAD BODY" not in ctx
    assert "bad.md" in r.stderr


def test_empty_file_path_is_silent(tmp_path):
    write_rule(tmp_path / "rules", "ts.md", TS_RULE)
    assert "TS BODY" in context_of(run_hook(tmp_path, write_payload("/w/a.ts")))  # sanity
    r = run_hook(tmp_path, write_payload(""))
    assert r.returncode == 0
    assert r.stdout.strip() == ""
