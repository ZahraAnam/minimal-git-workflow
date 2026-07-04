#!/usr/bin/env python3
"""
handshake.py
Standalone handshake utilities for minimal-git-workflow plugin.
No dependency on git-auto internals.

Used by:
  - test-handshake.sh (simulate git-auto writing pending-commit.json)
  - commit command (read pending, write message)
  - wrapup command (cleanup)
"""

import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path


def get_repo_root() -> Path:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError("Not a git repository.")
    return Path(result.stdout.strip())


def get_git_dir() -> Path:
    return get_repo_root() / ".git"


def pending_commit_path() -> Path:
    return get_git_dir() / "pending-commit.json"


def commit_message_path() -> Path:
    return get_git_dir() / "commit-message.txt"


# git-auto never writes pending-commit.json in real operation (see
# plugin-working.md) — only test-handshake.sh does, to simulate the handshake
# in isolation, and its --dry-run/timeout paths deliberately skip cleanup.
# start-git-auto.sh sweeps any copy left over at SessionStart, but one written
# mid-session and then abandoned survives past that sweep for the rest of the
# session — so read_pending_commit() applies the same TTL
# check-unit-complete.sh already uses for unit-check.json, instead of trusting
# mere existence.
PENDING_COMMIT_STALE_AFTER_SECONDS = 300


def write_pending_commit(
    branch: str,
    files_changed: list[str],
    stat_summary: str,
) -> Path:
    """Write pending-commit.json — simulates what git-auto will do on threshold."""
    path = pending_commit_path()
    payload = {
        "branch": branch,
        "files_changed": files_changed,
        "stat_summary": stat_summary,
        "timestamp": datetime.now().isoformat(),
    }
    path.write_text(json.dumps(payload, indent=2))
    print(f"[handshake] Written: {path}", file=sys.stderr)
    return path


def read_pending_commit() -> dict | None:
    """Read pending-commit.json. Returns None if not found or stale.

    A copy older than PENDING_COMMIT_STALE_AFTER_SECONDS is orphaned test data
    (see the comment above that constant) rather than a real pending commit —
    surface it via a STALE_PENDING_COMMIT marker and clear it instead of
    letting wrapup/commit act on it.
    """
    path = pending_commit_path()
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text())
    except Exception as e:
        print(f"[handshake] Error reading pending-commit.json: {e}", file=sys.stderr)
        return None

    try:
        age = time.time() - datetime.fromisoformat(data["timestamp"]).timestamp()
    except Exception:
        age = None

    if age is None or age >= PENDING_COMMIT_STALE_AFTER_SECONDS:
        stat_summary = data.get("stat_summary", "changes detected")
        files = ", ".join(data.get("files_changed", []))
        timestamp = data.get("timestamp", "unknown time")
        print(
            f"[handshake] STALE_PENDING_COMMIT: orphaned handshake file "
            f"({timestamp} | {stat_summary} | files: {files}) — never a real "
            "pending commit. Clearing it.",
            file=sys.stderr,
        )
        path.unlink()
        return None

    return data


def write_commit_message(message: str) -> Path:
    """Write commit-message.txt for git-auto to pick up."""
    path = commit_message_path()
    path.write_text(message.strip())
    print(f"[handshake] Commit message written: {path}", file=sys.stderr)
    return path


def wait_for_commit_message(timeout: int = 30) -> str | None:
    """Poll for commit-message.txt. Returns message or None on timeout."""
    path = commit_message_path()
    start = time.monotonic()
    while (time.monotonic() - start) < timeout:
        if path.exists():
            msg = path.read_text().strip()
            if msg:
                return msg
        time.sleep(1)
    return None


def clear_handshake_files() -> None:
    """Remove both handshake files after commit is done."""
    for path in [pending_commit_path(), commit_message_path()]:
        if path.exists():
            path.unlink()
            print(f"[handshake] Cleared: {path}", file=sys.stderr)


def get_current_branch() -> str:
    result = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        capture_output=True, text=True
    )
    return result.stdout.strip() if result.returncode == 0 else "unknown"


def get_upstream_branch() -> str | None:
    result = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
        capture_output=True, text=True
    )
    return result.stdout.strip() if result.returncode == 0 else None


def get_unpushed_status() -> dict:
    """Detect unpushed commits — count and subjects only, never diffs."""
    branch = get_current_branch()
    upstream = get_upstream_branch()
    if upstream is None:
        return {"count": 0, "branch": branch, "upstream": None, "subjects": []}

    count_result = subprocess.run(
        ["git", "rev-list", "@{u}..HEAD", "--count"],
        capture_output=True, text=True
    )
    count = 0
    if count_result.returncode == 0:
        try:
            count = int(count_result.stdout.strip() or "0")
        except ValueError:
            count = 0

    subjects: list[str] = []
    if count > 0:
        log_result = subprocess.run(
            ["git", "log", "@{u}..HEAD", "--format=%s"],
            capture_output=True, text=True
        )
        if log_result.returncode == 0:
            # newest-first — matches `git log` default order; downstream consumers display in this order
            subjects = [s for s in log_result.stdout.splitlines() if s.strip()]

    return {"count": count, "branch": branch, "upstream": upstream, "subjects": subjects}


def get_stat_summary() -> str:
    """Get lightweight diff stat — never full diff content."""
    # Staged changes first
    staged = subprocess.run(
        ["git", "diff", "--cached", "--stat"],
        capture_output=True, text=True
    ).stdout.strip()
    if staged:
        return staged
    # Fall back to unstaged
    unstaged = subprocess.run(
        ["git", "diff", "--stat"],
        capture_output=True, text=True
    ).stdout.strip()
    return unstaged or "no changes detected"


def get_changed_files() -> list[str]:
    """Get list of changed file paths (staged + unstaged)."""
    result = subprocess.run(
        ["git", "status", "--porcelain"],
        capture_output=True, text=True
    )
    files = []
    for line in result.stdout.splitlines():
        if line.strip():
            files.append(line[3:].strip())
    return files


# --- Unit-check handshake (logical-unit-based commits) ---

def unit_check_path() -> Path:
    return get_git_dir() / "unit-check.json"


def write_unit_check() -> Path:
    """Write unit-check.json — signals Claude to evaluate whether a logical unit is complete."""
    path = unit_check_path()
    payload = {
        "branch": get_current_branch(),
        "files_changed": get_changed_files(),
        "stat_summary": get_stat_summary(),
        "timestamp": datetime.now().isoformat(),
    }
    path.write_text(json.dumps(payload, indent=2))
    print(f"[handshake] Written: {path}", file=sys.stderr)
    return path


def read_unit_check() -> dict | None:
    """Read unit-check.json. Returns None if not found."""
    path = unit_check_path()
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except Exception as e:
        print(f"[handshake] Error reading unit-check.json: {e}", file=sys.stderr)
        return None


def clear_unit_check() -> None:
    """Remove unit-check.json after Claude has responded."""
    path = unit_check_path()
    if path.exists():
        path.unlink()
        print(f"[handshake] Cleared: {path}", file=sys.stderr)


# CLI entrypoint for shell scripts
if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""

    if cmd == "read-pending":
        data = read_pending_commit()
        if data:
            print(json.dumps(data, indent=2))
        else:
            print("{}")

    elif cmd == "write-message":
        msg = sys.argv[2] if len(sys.argv) > 2 else ""
        if not msg:
            print("Usage: handshake.py write-message '<message>'", file=sys.stderr)
            sys.exit(1)
        write_commit_message(msg)

    elif cmd == "clear":
        clear_handshake_files()

    elif cmd == "status":
        pending = read_pending_commit()
        msg_path = commit_message_path()
        unit = read_unit_check()
        print(f"pending-commit.json : {'EXISTS' if pending else 'none'}")
        print(f"commit-message.txt  : {'EXISTS' if msg_path.exists() else 'none'}")
        print(f"unit-check.json     : {'EXISTS' if unit else 'none'}")
        if pending:
            print(f"branch              : {pending.get('branch')}")
            print(f"stat_summary        : {pending.get('stat_summary')}")
        if unit:
            print(f"unit branch         : {unit.get('branch')}")
            print(f"unit stat_summary   : {unit.get('stat_summary')}")

    elif cmd == "read-unit-check":
        data = read_unit_check()
        if data:
            print(json.dumps(data, indent=2))
        else:
            print("{}")

    elif cmd == "write-unit-check":
        write_unit_check()

    elif cmd == "clear-unit-check":
        clear_unit_check()

    elif cmd == "unit-check-status":
        unit = read_unit_check()
        print(f"unit-check.json : {'EXISTS' if unit else 'none'}")
        if unit:
            print(f"branch          : {unit.get('branch')}")
            print(f"files_changed   : {unit.get('files_changed')}")
            print(f"stat_summary    : {unit.get('stat_summary')}")

    elif cmd == "unpushed-status":
        print(json.dumps(get_unpushed_status(), indent=2))

    else:
        print("Commands: read-pending | write-message '<msg>' | clear | status")
        print("          read-unit-check | write-unit-check | clear-unit-check | unit-check-status")
        print("          unpushed-status")
        sys.exit(1)
