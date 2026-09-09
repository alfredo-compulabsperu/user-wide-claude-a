#!/usr/bin/env python3
"""Minimal reproduction of context-mode's guidance-throttle architecture.

WHY THIS SHAPE
--------------
Claude Code spawns a NEW PROCESS for every hook invocation. In-memory state
therefore never survives between calls, so any "fire only sometimes" logic has
to persist outside the process. context-mode persists in `tmpdir()`:

    <tmpdir>/context-mode-guidance-<session-id>/
        bash              <- marker: "the bash nudge already fired"
        external-mcp.count <- counter: "external-mcp nudge has fired N times"

Session identity resolves as: sessionId from the hook payload (stable), else
process.ppid (context-mode issue #298: ppid is unstable on Windows/Git Bash,
which is why passing the real sessionId matters).

STRATEGY 1 and 2 are what context-mode actually ships.
STRATEGY 3 is the one docs/rule-loading-audit.md recommends for the M5
PreToolUse rule injector (see .claude/PRPs/plans/lazy-loading-system.plan.md,
task 2.1, MIRROR: DEDUP_PER_SUBJECT) and does not exist yet.
"""

import hashlib
import os
import tempfile
from pathlib import Path

SESSION = "demo-session-01"


def _dir(session_id: str) -> Path:
    ident = f"s-{session_id}" if session_id else str(os.getppid())
    d = Path(tempfile.gettempdir()) / f"throttle-demo-{ident}"
    d.mkdir(parents=True, exist_ok=True)
    return d


# ── Strategy 1: once per session ──────────────────────────────────────────
# context-mode's guidanceOnce(). Used for the Bash / Read / Grep nudges.
# Atomic across concurrent processes via O_CREAT|O_EXCL — the first process to
# create the marker wins; everyone else gets FileExistsError and stays silent.
def once(kind: str, session_id: str = SESSION) -> bool:
    marker = _dir(session_id) / kind
    try:
        os.close(os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
        return True
    except FileExistsError:
        return False


# ── Strategy 2: periodic re-fire ──────────────────────────────────────────
# context-mode's guidancePeriodic(). Used for the external-MCP nudge.
# Fires on calls 1, period+1, 2*period+1, ... Default period 10, env-tunable
# via CONTEXT_MODE_EXTERNAL_MCP_NUDGE_EVERY, bounded [1, 100].
# Rationale in their source: a one-shot nudge "was lost after context
# compaction in MCP-heavy sessions"; re-firing keeps it in the recent window.
def periodic(kind: str, period: int = 10, session_id: str = SESSION) -> bool:
    counter = _dir(session_id) / f"{kind}.count"
    try:
        n = int(counter.read_text())
    except (OSError, ValueError):
        n = 0  # on any failure, fall through to firing — losing a counter is
    n += 1     # preferable to silently dropping the advisory
    try:
        counter.write_text(str(n))
    except OSError:
        pass
    return (n - 1) % max(1, period) == 0


# ── Strategy 3: once per (rule, subject) — PROPOSED, audit issue D ────────
# Neither of the above is right for rule loading:
#   - `once` goes silent forever after the first match, so a LATER edit to a
#     DIFFERENT file gets no rule at all (violates §0: load whenever the
#     trigger matches).
#   - `periodic` re-bills the full rule body on a fixed cadence regardless of
#     whether the subject changed (unbounded cost, audit finding #1).
# Keying the marker on the subject gives: every distinct file gets the rule
# exactly once, repeat edits to the same file cost nothing.
def per_subject(kind: str, subject: str, session_id: str = SESSION) -> bool:
    key = hashlib.sha1(subject.encode()).hexdigest()[:12]
    return once(f"{kind}--{key}", session_id)


# ── Demo ──────────────────────────────────────────────────────────────────
EVENTS = [
    "src/app.ts", "src/app.ts", "src/app.ts",
    "src/api.ts", "src/api.ts",
    "src/app.ts",
    "src/db.ts", "src/db.ts", "src/db.ts", "src/db.ts",
    "src/api.ts", "src/app.ts",
]
BODY_TOKENS = 2150  # measured cost of one ask-before-test-changes injection


def main() -> None:
    # start clean so the demo is reproducible
    import shutil
    shutil.rmtree(_dir(SESSION), ignore_errors=True)

    rows, totals = [], {"once": 0, "periodic": 0, "per_subject": 0}
    for i, subject in enumerate(EVENTS, 1):
        fired = {
            "once": once("rule"),
            "periodic": periodic("rule", period=4),
            "per_subject": per_subject("rule", subject),
        }
        for k, v in fired.items():
            totals[k] += BODY_TOKENS if v else 0
        rows.append((i, subject, fired))

    mark = lambda b: " FIRE " if b else "   ·  "
    print(f"{'#':>2}  {'edited file':<12} {'once':^6} {'periodic':^9} {'per-subject':^12}")
    print("-" * 46)
    for i, subject, f in rows:
        print(f"{i:>2}  {subject:<12} {mark(f['once']):^6} "
              f"{mark(f['periodic']):^9} {mark(f['per_subject']):^12}")
    print("-" * 46)
    print(f"{'':>2}  {'tokens':<12} {totals['once']:^6} "
          f"{totals['periodic']:^9} {totals['per_subject']:^12}")
    print()
    print("once        : 1 fire. Files #4-#12 governed by NOTHING. Cheapest, broken.")
    print("periodic(4) : fires on a cadence blind to which file — re-bills app.ts,")
    print("              still misses nothing only by luck. Unbounded as N grows.")
    print("per-subject : 3 fires = 3 distinct files. Every file governed exactly")
    print("              once; repeat edits free. Cost scales with breadth, not volume.")


if __name__ == "__main__":
    main()
