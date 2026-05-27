# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Claude Code plugin (`minimal-git-workflow v2.0.0`). Automates git commits using Claude's session context — raw diffs never enter context. Installed as a symlink at `~/.claude/plugins/minimal-git-workflow/`.

## Install & setup

```bash
./install.sh                          # installs git-auto dep + creates plugin symlink
/minimal-git-workflow:configure       # creates git-auto-config.json in target project
```

Requires `git-auto` on PATH (Python CLI, installed via `pip install -e .` from the automate-git-commands repo).

## Testing the handshake

```bash
./scripts/test-handshake.sh           # simulate git-auto threshold hit, wait for response
./scripts/test-handshake.sh --dry-run # write pending-commit.json only, don't wait
python3 scripts/handshake.py status   # inspect current handshake file state
```

## Architecture

Two parallel commit pathways:

**Pathway A — threshold-based**
`SessionStart` hook runs `start-git-auto.sh` → git-auto monitors file changes → on `files_threshold` hit → git-auto writes `.git/pending-commit.json` → `watch-pending.sh` (Monitor tool) notifies Claude → `/minimal-git-workflow:commit` skill generates message from session context → `handshake.py write-message` writes `.git/commit-message.txt` → git-auto reads it and commits.

**Pathway B — logical-unit-based** (requires `unit_commit: true` in config)
`PostToolUse` hook (Edit/Write) runs `check-unit-complete.sh` → writes `.git/unit-check.json` → `watch-pending.sh` notifies Claude → `/minimal-git-workflow:unit-commit` skill evaluates completeness → commits directly with `git add . && git commit -m`.

**Critical invariant:** Commit messages are generated from Claude's session context + `stat_summary` only. Never read file contents or `git diff` for commit generation.

**Race condition guard:** When `unit_commit: true`, set `files_threshold` high (e.g. 999) so both pathways don't trigger simultaneously.

## Key files

| Path | Role |
|---|---|
| `scripts/handshake.py` | Read/write handshake JSON files; CLI entrypoint for shell scripts |
| `scripts/watch-pending.sh` | Background monitor (runs via Monitor tool); polls both `.git/pending-commit.json` and `.git/unit-check.json` every 5s |
| `scripts/start-git-auto.sh` | SessionStart hook; guards against multi-project conflicts via `.git/git-auto-state.json` |
| `scripts/check-unit-complete.sh` | PostToolUse hook; writes unit-check.json only if `unit_commit: true` and working tree is dirty |
| `hooks/hooks.json` | Plugin hook declarations (`SessionStart`, `PostToolUse` on Edit/Write) |
| `.claude-plugin/plugin.json` | Plugin manifest |
| `skills/*/SKILL.md` | Skill implementations (commit, unit-commit, configure, status, wrapup) |

## Handshake file protocol

All files live under `.git/` (gitignored):

| File | Written by | Read/consumed by |
|---|---|---|
| `pending-commit.json` | git-auto | watch-pending.sh → commit skill |
| `commit-message.txt` | commit skill (handshake.py) | git-auto |
| `unit-check.json` | check-unit-complete.sh (handshake.py) | watch-pending.sh → unit-commit skill |
| `git-auto-state.json` | git-auto | start-git-auto.sh (PID check) |

## git-auto-config.json structure

```json
{
  "start": {
    "files_threshold": 2,
    "push_threshold": 4,
    "squash_threshold": 0,
    "catchup": false,
    "cooldown": 3.0,
    "model": "open-mistral-nemo",
    "claude_handshake": true,
    "claude_timeout": 30
  },
  "unit_commit": false
}
```

`model` is the primary LLM git-auto uses for commit messages. With `claude_handshake: true`, git-auto falls back to this model if Claude does not write `commit-message.txt` within `claude_timeout` seconds.
