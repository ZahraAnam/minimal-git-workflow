# Integration Plan: git-auto ↔ minimal-git-workflow handshake

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

| Repo | Changes |
|---|---|
| `automate-git-commands` | New handshake logic in `cli.py`, `config.py`, `git_tools.py` |
| `minimal-git-workflow` | Update `configure` skill + fix `model` description in CLAUDE.md |

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

| File | Change |
|---|---|
| `automate-git-commands/git-auto/config.py` | Add `claude_handshake`, `claude_timeout` to `StartConfig` + `_FIELD_TYPES` |
| `automate-git-commands/git-auto/git_tools.py` | Add `write_pending_commit`, `poll_commit_message`, `clear_handshake_files` |
| `automate-git-commands/git-auto/cli.py` | Branch `sync_workflow()` on `claude_handshake`; wire new fields through `start` + `ChangeHandler` |
| `minimal-git-workflow/skills/configure/SKILL.md` | Default config includes `claude_handshake: true`, `claude_timeout: 30` |
| `minimal-git-workflow/CLAUDE.md` | Fix `model` field description (line 79) |
