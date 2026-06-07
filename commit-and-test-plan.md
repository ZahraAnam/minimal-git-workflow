# Plan: Commit handshake-integration changes + test-in-another-repo plan

## Context

Handshake protocol (git-auto ↔ minimal-git-workflow) was implemented and verified
end-to-end in `project_planner` (commit `3687772` landed with Claude's exact message).

Checked both repos:

- `automate-git-commands` (`feat/updates-for-claude-plugin`) — **already clean**, all
  handshake code (config.py, git_tools.py, cli.py incl. race-condition fix + atomic
  writes) is committed in `9cc3e08`/`5de3ba7`. Nothing to commit there.
- `minimal-git-workflow` (`feat/initialize-work`) — **has uncommitted work** from this
  session: wiring of `claude_handshake`/`claude_timeout` through the plugin scripts,
  a simplified commit-skill flow (no user confirmation — handshake auto-writes), a new
  test harness + test-suite skill, plus doc/session bookkeeping.

Goal: land these as logical commits on `feat/initialize-work`, then define a plan to
re-run the handshake test against a fresh/different repo to confirm the wiring works
outside `project_planner`.

---

## Part 1 — Commit the uncommitted minimal-git-workflow changes

Group into 4 logical commits (conventional-commits style, matches repo history):

1. **`feat(scripts): wire claude_handshake config through start/stop scripts`**
   - `scripts/start-git-auto.sh` — read `claude_handshake`/`claude_timeout` from
     `git-auto-config.json`, pass `--claude-handshake --claude-timeout N` to `git-auto start`
   - `scripts/stop-git-auto.sh` — `--force` stop + orphan-process cleanup
     (the exact bug class that caused the zombie-PID test failure)

2. **`refactor(commit skill): auto-write commit message without user confirmation`**
   - `skills/commit/SKILL.md` — collapses Step 3/4/5 confirmation flow into a direct
     write (handshake is fire-and-forget; git-auto already polls and falls back on timeout)

3. **`feat(testing): add test harness + test-suite skill`**
   - `scripts/test-harness.sh` (new) — deterministic setup/teardown/assert helpers
   - `skills/test-suite/SKILL.md` (new) — orchestrates phased plugin test runs

4. **`docs: update integration plan and session bookkeeping`**
   - `integration-plan.md` — mark all 8 steps done, document race condition + fixes
   - `.claude/sessions/INDEX.md`, `session-specific-instructions.md`,
     `.claude/sessions/analysis/2026052*` — session tracking housekeeping

Each commit staged with explicit file paths (no `git add -A`).

---

## Part 2 — Plan: test handshake in a different repo

**Target: `deutsche_bahn_delay_predictor_with_weather_info`** (branch `dev-test-plugin`).
It's a git repo, already has `git-auto-config.json` from a prior plugin test session —
proves the fix isn't `project_planner`-path-specific.

Current config there is set up for **Pathway B** (unit-commit), not what we want:

```json
{ "files_threshold": 999, "claude_timeout": 3600, "unit_commit": true, ... }
```

Needs editing for **Pathway A** (threshold-based handshake) testing — same adjustment
made to `project_planner`'s config earlier this session.

Steps:

1. **Pre-flight**
   - `pgrep -af git-auto` → confirm no process already watching this repo's path
     (one IS running for `automate-git-commands` path — PID 9829 — leave it alone,
     it's a different repo)
   - confirm `which git-auto` resolves to the editable install (`~/.local/bin/git-auto`)

2. **Adjust config** — edit `git-auto-config.json` in target repo:
   - `files_threshold: 999 → 2` (low, triggers quickly)
   - `unit_commit: true → false` (isolate Pathway A; avoid race between pathways
     per the "Critical invariant" in plugin `CLAUDE.md`)
   - `claude_timeout: 3600 → 30` (sane test window)
   - keep `claude_handshake: true`

3. **Use new test harness** — run via `/minimal-git-workflow:test-suite` skill
   (built this session) which wraps `test-harness.sh`:
   - `setup` → kills stray processes for this repo, starts fresh git-auto, creates `test-scratch.txt`
   - `edit-scratch` → trigger `files_threshold=2`
   - `wait-pending` → assert `pending-commit.json` appears
   - write `commit-message.txt` via `handshake.py write-message '<msg>'`
   - `wait-commit` → assert handshake files cleared + commit lands
   - `assert-commit '<msg-regex>'` → exact message match (not Mistral's)
   - `teardown` + `summary` → pass/fail table

4. **Verify**
   - `git log -1` shows Claude's message verbatim
   - `assert-processes 0` — no orphan git-auto left for this repo
   - `assert-clean` — handshake files removed

5. **Report** — pass/fail table from `test-harness.sh summary`; restore original
   config values (`files_threshold: 999`, `unit_commit: true`, `claude_timeout: 3600`)
   if the repo needs to return to its prior Pathway-B test setup afterward.
   → Ask user whether to restore or leave the Pathway-A test config in place.
