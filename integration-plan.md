# Integration Plan: git-auto ↔ minimal-git-workflow handshake

## Status

| Step | What                                                          | Status                                                                     |
| ---- | ------------------------------------------------------------- | -------------------------------------------------------------------------- |
| 1    | `config.py` — add `claude_handshake`, `claude_timeout`        | ✅ Done                                                                    |
| 2    | `git_tools.py` — implement handshake helpers                  | ✅ Done                                                                    |
| 3    | `cli.py` — branch `sync_workflow`, wire CLI options           | ✅ Done                                                                    |
| 4    | `configure` skill — default `claude_handshake: true`          | ✅ Done                                                                    |
| 5    | `CLAUDE.md` — fix `model` description                         | ✅ Done                                                                    |
| 6    | End-to-end verification                                       | ✅ Done — handshake receives message and commits with exact Claude message |
| 7    | `cli.py` — `_handshake_in_progress` flag to block flush timer | ✅ Done                                                                    |
| 8    | `cli.py` — atomic state file write to prevent JSON corruption | ✅ Done                                                                    |

---

## Race Condition (found during testing)

### What happens

When `files_threshold` is hit, two paths can fire `sync_workflow()` simultaneously:

1. **Threshold path** (`_handle_file_change`): detects N files → starts `sync_workflow()` → writes `pending-commit.json` → polls for 30s using `time.sleep(1)` which blocks the asyncio worker loop
2. **Flush timer path** (`_maybe_flush`, fires every 1s): sees `changed_files` still populated (not cleared until threshold path returns) + cooldown not yet set → also starts `sync_workflow()` → since the worker loop is blocked by `time.sleep`, this second call gets its own `run_until_complete` attempt

The flush timer wins the race when it fires before the threshold path acquires the worker loop — it runs a full LLM sync_workflow and commits via Mistral. The handshake then finds nothing to commit.

Test log evidence:

```
INFO Branch: test/plugin-testing
INFO Handshake: waiting up to 30s for Claude commit message...   ← threshold path polling
INFO Cooldown expired. Flushing 2 queued file(s): ...            ← flush timer fires in parallel
...
INFO Message: feat(readme): add test                             ← Mistral commits first
INFO Committed.
...
INFO Handshake: message received — 'chore(test): ...'           ← our message received
ERROR Pre-commit hook rejected commit: nothing to commit         ← nothing left to commit
```

### Fix — Step 7 (new): add `_handshake_in_progress` flag to `ChangeHandler`

**`automate-git-commands/git-auto/cli.py`**

In `ChangeHandler.__init__`, add:

```python
self._handshake_in_progress = False
```

In `_maybe_flush()`, add early return:

```python
def _maybe_flush(self) -> None:
    if self._in_cooldown() or self._handshake_in_progress:
        return
    ...
```

In `_handle_file_change()`, add guard around the threshold-triggered sync:

```python
if queued >= self.files_threshold:
    ...
    _get_worker_loop().run_until_complete(self.sync_workflow())
```

(no change here — the flag is set inside `sync_workflow`)

In `sync_workflow()`, set/clear the flag around the handshake poll:

```python
if self.claude_handshake:
    mode, content = get_pruned_diff()
    if not mode:
        ...
        return
    stat = ...
    write_pending_commit(branch, list(self.changed_files), stat)
    self._handshake_in_progress = True          # ← add
    logger.info("Handshake: waiting up to %ds...", self.claude_timeout)
    try:                                         # ← add
        message = poll_commit_message(self.claude_timeout)
    finally:                                     # ← add
        self._handshake_in_progress = False      # ← add
    if message:
        ...
    else:
        ...
```

`finally` ensures the flag clears even if `poll_commit_message` raises.

### Fix — Step 8 (new): atomic state file writes in `_save_state`

**`automate-git-commands/git-auto/cli.py`**

Two threads (`_handle_file_change` and `_maybe_flush`) both call `_save_state()` concurrently. The `_state_lock` protects the write, but the main thread's `state_file_path.write_text(...)` in `start()` is unguarded — if it overlaps with a `_save_state()` call from a watchdog thread, the file gets two JSON objects concatenated → `JSONDecodeError: Extra data`.

Fix: use atomic write (write to `.tmp`, then rename) in `_save_state`, and do the same in `start()`:

```python
def _save_state(self):
    with self._state_lock:
        if not self.state_file.exists():
            return
        try:
            state = json.loads(self.state_file.read_text())
            state["count"] = self.count
            state["commits_since_push"] = self._commits_since_push
            state["changed_files"] = list(self.changed_files)
            state["current_branch"] = self.current_branch
            tmp = self.state_file.with_suffix(".tmp")   # ← atomic write
            tmp.write_text(json.dumps(state, indent=2))
            tmp.replace(self.state_file)                # ← atomic replace
        except Exception as e:
            logger.error("Error saving state: %s", e)
```

Apply the same pattern (`tmp.write_text` + `tmp.replace`) to the initial `state_file_path.write_text(...)` call in `start()`.

---

## Edge Case: Unit-commit + Pathway A simultaneous fire (found 2026-05-28)

### What happens

When git-auto starts with `catchup: true` and there are pending changes, both Pathway A (threshold/catchup → `pending-commit.json`) and Pathway B (unit-commit → `unit-check.json`) can fire for the same file in the same startup flush.

If unit-commit evaluates YES and commits directly via `git add . && git commit`, the working tree is clean. But `pending-commit.json` is still on disk — git-auto is still polling for `commit-message.txt` (for up to `claude_timeout` seconds).

Result: stale `pending-commit.json` hangs around until Claude manually writes a dummy `commit-message.txt` to satisfy git-auto's poll, or until `claude_timeout` expires and git-auto attempts a commit that fails with "nothing to commit."

### Fix options

**Option A — handshake.py `clear-pending` command**: add a `clear-pending` subcommand to `handshake.py` that deletes `pending-commit.json` and `commit-message.txt`. The unit-commit skill calls this after a direct commit to cancel any in-flight handshake.

**Option B — git-auto watches for empty tree**: git-auto's handshake poll checks if the working tree is clean before committing. If clean, it cancels the pending commit and cleans up the files.

**Option C — mutual exclusion**: if `unit_commit: true`, the startup catchup path skips writing `pending-commit.json` (unit-commit handles it). Requires config awareness in git-auto.

Recommended: **Option A** — simplest, no git-auto changes needed.

```bash
# Add to handshake.py
python3 handshake.py clear-pending   # deletes pending-commit.json + commit-message.txt
```

Unit-commit skill Step 3a adds after `git commit`:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" clear-pending
```

---

## Problem

Pathway A (threshold-based commits) is fully non-functional. The plugin expects git-auto to:

1. Write `.git/pending-commit.json` when `files_threshold` is hit
2. Poll for `.git/commit-message.txt` written by Claude
3. Use that message to commit

git-auto does none of this. `sync_workflow()` in `cli.py:263` calls Mistral and commits directly. Claude is never involved. `watch-pending.sh` polls forever and finds nothing.

Secondary issue: plugin CLAUDE.md incorrectly describes `model` as "the git-auto fallback if Claude doesn't write in time." It is actually the primary model git-auto uses for every commit.

---

## Scope

Changes required in two repos:

| Repo                    | Changes                                                         |
| ----------------------- | --------------------------------------------------------------- |
| `automate-git-commands` | New handshake logic in `cli.py`, `config.py`, `git_tools.py`    |
| `minimal-git-workflow`  | Update `configure` skill + fix `model` description in CLAUDE.md |

---

## Plan

### Step 1 — Add handshake config fields (`automate-git-commands/git-auto/config.py`)

Add two new fields to `StartConfig`:

```python
claude_handshake: bool = False   # opt-in; disabled by default for backward compat
claude_timeout: int = 30         # seconds to wait for commit-message.txt
```

Register both in `_FIELD_TYPES`:

```python
"claude_handshake": bool,
"claude_timeout": int,
```

Validation: `claude_timeout` must be `>= 5`.

---

### Step 2 — Add handshake file helpers (`automate-git-commands/git-auto/git_tools.py`)

Add three functions:

```python
def write_pending_commit(branch: str, files: list[str], stat_summary: str) -> Path:
    """Write .git/pending-commit.json — signals Claude a commit is needed."""

def poll_commit_message(timeout: int) -> str | None:
    """Poll .git/commit-message.txt every 1s up to timeout. Returns message or None."""

def clear_handshake_files() -> None:
    """Delete pending-commit.json and commit-message.txt after commit."""
```

File paths resolved via `get_state_file_path()` parent (already returns `.git/` dir).

---

### Step 3 — Branch `sync_workflow()` on `claude_handshake` (`automate-git-commands/git-auto/cli.py`)

`ChangeHandler` needs the two new config values. Pass them through `__init__`:

```python
def __init__(self, ..., claude_handshake: bool = False, claude_timeout: int = 30):
    self.claude_handshake = claude_handshake
    self.claude_timeout = claude_timeout
```

In `sync_workflow()`, after `git add .` and before the diff/agent block, insert:

```python
if self.claude_handshake:
    mode, content = get_pruned_diff()
    if not mode:
        logger.info("Nothing to commit: %s", content)
        return
    stat = subprocess.run(["git", "diff", "--cached", "--stat"], capture_output=True, text=True).stdout.strip()
    write_pending_commit(branch, list(self.changed_files), stat)
    logger.info("Handshake: waiting up to %ds for Claude commit message...", self.claude_timeout)
    message = poll_commit_message(self.claude_timeout)
    if message:
        logger.info("Handshake: message received — '%s'", message)
        clear_handshake_files()
        # skip LLM block, go straight to Phase 2 commit
        try:
            git_commit(message)
        except HookError as e:
            ...  # same handling as existing Phase 2
        ...
        return
    else:
        logger.warning("Handshake: timeout — falling back to Mistral.")
        clear_handshake_files()
        # fall through to existing LLM block
```

Wrap the existing diff+LLM block in an `else` / fallthrough so it runs when `claude_handshake` is off or timed out.

Wire `claude_handshake` + `claude_timeout` through the `start` command and into the `ChangeHandler` constructor call at `cli.py:529`.

---

### Step 4 — Update `configure` skill (`minimal-git-workflow/skills/configure/SKILL.md`)

When generating `git-auto-config.json`, include the two new fields in the `start` section:

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

`claude_handshake: true` should be the default when configuring via the plugin — that is the entire point of the plugin.

---

### Step 5 — Fix `model` description in `minimal-git-workflow/CLAUDE.md`

Current (line 79):

> `model` is the git-auto fallback if Claude doesn't write a commit message in time.

Replace with:

> `model` is the primary LLM git-auto uses for commit messages. With `claude_handshake: true`, git-auto falls back to this model if Claude does not write `commit-message.txt` within `claude_timeout` seconds.

---

### Step 6 — Verify end-to-end

1. In `automate-git-commands`: run existing test suite — `pytest tests/`
2. In `minimal-git-workflow`: run `./scripts/test-handshake.sh --dry-run` to confirm `pending-commit.json` writes correctly
3. Run full handshake test: `./scripts/test-handshake.sh`, then invoke `/minimal-git-workflow:commit` in a live session — confirm `commit-message.txt` is written and picked up
4. Test fallback: let `test-handshake.sh` time out — confirm git-auto falls back to Mistral and commits

---

## Compatibility guarantee

- `claude_handshake` defaults to `false` — existing git-auto users see no behavior change
- All new config keys pass through existing `validate_config_data()` validation
- `unit_commit` (plugin top-level key) remains outside the `start` section — git-auto ignores it safely
- Pathway B (unit-commit) is unaffected — it never calls git-auto

---

## File change summary

| File                                             | Change                                                                                            |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| `automate-git-commands/git-auto/config.py`       | Add `claude_handshake`, `claude_timeout` to `StartConfig` + `_FIELD_TYPES`                        |
| `automate-git-commands/git-auto/git_tools.py`    | Add `write_pending_commit`, `poll_commit_message`, `clear_handshake_files`                        |
| `automate-git-commands/git-auto/cli.py`          | Branch `sync_workflow()` on `claude_handshake`; wire new fields through `start` + `ChangeHandler` |
| `minimal-git-workflow/skills/configure/SKILL.md` | Default config includes `claude_handshake: true`, `claude_timeout: 30`                            |
| `minimal-git-workflow/CLAUDE.md`                 | Fix `model` field description (line 79)                                                           |
