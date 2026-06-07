---
name: test-suite
description: Run the full minimal-git-workflow plugin test suite with structured pass/fail tracking. Use at the start of a dedicated testing session.
---

This skill orchestrates all plugin test phases using `test-harness.sh` for deterministic assertions.
Claude handles the handshake and unit-commit judgment steps; the harness handles process checks,
timing, and state assertions.

**All edits during tests use `test-scratch.txt` only — never real source files.**

---

## Pre-flight

Run:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 0 2>/dev/null || true
git-auto status 2>&1 || true
```

Report: any git-auto processes already running, branch name, last commit.

Ask: "Which phases to run? (all / 1,3,5 / etc.)" — default: all.

---

## Phase 1 — Setup + Status baseline

```bash
# Start fresh
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" setup

# Baseline assertions
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 1
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-clean
```

Run `/minimal-git-workflow:status` and confirm all 4 sections complete without error.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" report 1 PASS "status baseline verified"
```

On any assertion failure: `report 1 FAIL "<error>"` and stop.

---

## Phase 2 — Configure

Run `/minimal-git-workflow:configure` with:
- `files_threshold=2`, `push_threshold=4`, `claude_handshake=true`, `claude_timeout=3600`, `unit_commit=false`

Then:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 0
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" setup   # restarts git-auto with new config
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 1
```

Verify `git-auto status` shows: `Mode: files (2 distinct files)`, `claude-handshake` in the process args:
```bash
ps aux | grep "git-auto start" | grep -v grep | grep "claude-handshake"
```

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" report 2 PASS "config written, handshake flag confirmed in process args"
```

---

## Phase 3 — Pathway A: Threshold-based handshake commit

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-clean
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 1

# Edit 2 distinct files
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" edit-scratch 1
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" edit-scratch 2

# Wait for pending-commit.json (up to 20s)
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" wait-pending 20
```

When Monitor fires `PENDING_COMMIT`: read pending and write message immediately (no approval):
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" read-pending
```
Generate message from session context. Write:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" write-message '<message>'
```

Wait for commit:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" wait-commit 20
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-clean
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 1
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-commit-count 1
```

Verify commit subject matches our message (not Mistral's):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-commit '<message-regex>'
```

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" report 3 PASS "handshake commit used Claude message"
```

**If `assert-commit` fails** (Mistral message used instead): check for ghost processes before marking fail:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 1
```
If >1: `report 3 FAIL "ghost process raced handshake"` — run teardown + setup, retry once.

---

## Phase 4 — Pathway B: Unit-commit

Reconfigure: `unit_commit=true`, `files_threshold=999`:
```bash
# Update git-auto-config.json (use Write tool)
# Then restart
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 0
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" setup
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 1
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-clean
```

**Test 4a — dismiss (mid-task):**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" edit-scratch 3
```
When Monitor fires `UNIT_CHECK`: run `/minimal-git-workflow:unit-commit`.
Evaluate: mid-task (no complete unit) → **dismiss**.
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" clear-unit-check
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-commit-count 0  # no new commit
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" report "4a" PASS "unit-commit correctly dismissed mid-task"
```

**Test 4b — commit (complete unit):**
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" edit-scratch 4
```
When Monitor fires `UNIT_CHECK`: run `/minimal-git-workflow:unit-commit`.
Evaluate: this IS a complete unit → commit directly, then:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" clear-pending  # cancel any stale Pathway A
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-clean
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-commit-count 1
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" report "4b" PASS "unit-commit committed complete unit"
```

---

## Phase 5 — Pathway A timeout fallback (Mistral)

Restart with `claude_timeout=15` (short, to keep test fast):
```bash
# Update git-auto-config.json: claude_timeout=15
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 0
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" setup
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 1

bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" edit-scratch 5
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" wait-pending 20
```

**Do NOT write commit-message.txt.** Wait for Mistral fallback:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" wait-commit 30
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-clean
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-commit-count 1
```

Confirm commit was Mistral (will NOT match a Claude-style typed message — check log):
```bash
tail -5 .git/git-auto.log | grep -E "Handshake: timeout|falling back"
```

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" report 5 PASS "Mistral fallback committed after timeout"
# Restore claude_timeout=3600
```

---

## Phase 6 — Stop script (wrapup)

Make 1 edit (below threshold — stays uncommitted):
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" edit-scratch 6
```

Run `/minimal-git-workflow:wrapup`. Verify:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" assert-processes 0
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" report 6 PASS "git-auto stopped cleanly"
```

---

## Teardown + Summary

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/test-harness.sh" teardown
```

Show the pass/fail table. For each FAIL, list:
- Root cause (observed vs expected)
- Which fix is needed (file + line)
- Whether it's a known gap (see integration-plan.md)
