# minimal-git-workflow: How it actually works

Two independent commit paths run in parallel. They don't conflict — whichever fires first commits; the other finds nothing to commit.

---

## Path A — git-auto (threshold-based, autonomous)

```
You edit files
        ↓
git-auto watchdog detects filesystem changes
        ↓
files_threshold reached (queued files >= threshold, not in cooldown)
        ↓
git add --ignore-errors .
        ↓
git-auto calls its LLM agent (Mistral by default) → generates commit message
        ↓
git commit -m "<generated message>"
        ↓
if squash_threshold reached → squash unpushed commits into one (separate LLM summary call)
        ↓
if push_threshold reached → git push
```

**git-auto is fully autonomous.** It never asks Claude, never writes `pending-commit.json`, never reads `commit-message.txt`. Those files are unused in normal operation — verified against the real `git-auto` source (`automate-git-commands/git-auto/cli.py`): nothing in the daemon reads or writes either file. Only `test-handshake.sh` simulates writing `pending-commit.json`, to test the plugin's handshake scripts in isolation from git-auto — and its `--dry-run`/timeout paths deliberately skip cleanup, so a leftover copy can sit in `.git/` indefinitely.

**`pending-commit.json` staleness (fixed 2026-07-04):** because git-auto never writes this file for real, any copy found is definitionally orphaned test data, not a real pending commit. Mirroring `unit-check.json`'s handling below: `start-git-auto.sh` sweeps any copy present at SessionStart, and `handshake.py`'s `read_pending_commit()` — the function backing both `commit`'s `read-pending` and `wrapup`'s `status` — treats anything past a 300s TTL the same way, logging a `STALE_PENDING_COMMIT` marker before clearing it. `watch-pending.sh`'s poll loop reads through this same function rather than stat'ing the file directly, so its "run /commit" notification can't fire for a file `/commit` would silently ignore as stale.

**Safety checks before commit:** git-auto refuses to run on `main`/`master` (logs a warning, no commit). Before staging anything, it also scans the working tree for secret-looking files (`git status --porcelain`, not just staged files) and aborts the sync with no commit and nothing staged if any are found — this check runs *before* `git add`, so there's nothing to unstage.

**Flush timer behaviour:** the flush timer doesn't lower the bar, it only resolves syncs that were *deferred* by cooldown. If a file-change event pushes the queued-file count past `files_threshold` while still in cooldown, that sync is silently queued instead of firing immediately; a 1s-interval flush loop fires it as soon as cooldown expires. Below `files_threshold`, nothing flushes on its own. (A separate, opt-in `interval` config key — not shown in the example below — can trigger a sync purely on a time interval regardless of threshold, but that's a distinct feature from the flush timer.)

---

## Path B — unit-commit (Claude-driven, logical-unit)

```
You edit a file via Claude (Edit/Write tool)
        ↓
PostToolUse hook fires: check-unit-complete.sh
        ↓
Checks: unit_commit: true in git-auto-config.json (top-level key)
Checks: unit-check.json not already pending (stale ones — past 300s — are cleared and fall through)
Checks: uncommitted changes exist
Checks: no secret-looking filename among changed files (.env, *.pem, *.key,
        *credentials*, *secrets*, id_rsa*, .netrc, .pgpass) — inspired by
        git-auto's own pre-commit scan, but excludes rather than aborts: any
        match is left out of unit-check.json's files_changed and listed
        under secret_files_excluded instead (SECRETS_DETECTED marker); the
        rest of the dirty tree still triggers normally. If nothing safe is
        left after excluding secrets, no unit-check.json is written at all.
        ↓
Writes .git/unit-check.json  (branch, files_changed, stat_summary,
        secret_files_excluded)
        ↓
watch-pending.sh detects it → notifies Claude session
        ↓
Claude runs /minimal-git-workflow:unit-commit
        ↓
Claude evaluates: "did I just finish a self-contained piece of work?"
        ↓
        ├── NO → clear unit-check.json, continue working
        │         (re-triggers on next edit)
        │
        └── YES → generate commit message from session context
                        ↓
                  git add . (excluding any secret_files_excluded paths)
                  git commit -m "<message>"   (no confirmation prompt — runs immediately)
                        ↓
                  clear unit-check.json
                        ↓
                  read push_threshold from config
                  count: git rev-list @{u}..HEAD --count
                  if unpushed >= push_threshold → git push
```

**Claude commits directly.** No handoff to git-auto, and no user confirmation gate. `skills/unit-commit/SKILL.md` never had one — but its command twin, `commands/unit-commit.md`, still carried a full `yes / edit / skip` prompt until this was caught and fixed (2026-07-04): the same skill/command-drift pattern behind development-details.md's separate "commit-confirmation saga" (which was about the `commit` skill, not this one), recurring here independently.

---

## Session lifecycle

```
Session opens
    │
    ▼
SessionStart hook → start-git-auto.sh
                        ├── starts git-auto (background)
                        └── prints MONITOR_REQUIRED → Claude calls Monitor(watch-pending.sh)
    │
    │         ┌─────────────────────────────────────────┐
    │         │  PARALLEL                               │
    ▼         ▼                                         │
git-auto watches filesystem          PostToolUse hook (Edit/Write)
    │                                        │
files threshold / cooldown flush    check-unit-complete.sh
    │                                        │
git-auto → Mistral → git commit     unit-check.json written
                                            │
                                    watch-pending.sh notifies Claude
                                            │
                                    /unit-commit → evaluate
                                            │
                                    git add . && git commit
    │
    ▼ (end of session)
/wrapup → stop git-auto → confirm clean state
```

---

## Configuration

`git-auto-config.json` has two sections:

```json
{
  "start": {
    "files_threshold": 999,
    "push_threshold": 0,
    "squash_threshold": 5,
    "catchup": false,
    "cooldown": 5.0,
    "model": "mistral-small-latest"
  },
  "unit_commit": true
}
```

- `start.*` keys are read by git-auto. Unknown keys cause a startup crash — `unit_commit` must NOT go in `start`.
- `unit_commit` is a plugin-only key read by `check-unit-complete.sh`. git-auto ignores it.
- `files_threshold` is set high (999) here specifically because `unit_commit: true` — see README's "avoid race conditions between the two pathways" note. git-auto's own default (unrelated to unit_commit) is 3.
- `start.*` defaults (from `git-auto/config.py`'s `StartConfig`, the actual source git-auto reads): `files_threshold: 3`, `push_threshold: 0`, `squash_threshold: 5`, `cooldown: 5.0`, `model: "mistral-small-latest"`, `catchup: false`.

---

## Key design insight

Claude never reads raw diffs. `stat_summary` tells Claude _how much_ changed. Claude's own session memory tells it _what_ changed and whether it's logically complete. Zero extra token cost.

git-auto's own LLM message (Path A) has no session context by design — it isn't a fallback conditional on something failing, it's simply what Path A always does. Only Path B (`unit-commit`) gets Claude's session-aware message in normal operation; the `commit`/handshake pathway exists in the plugin's scripts but nothing in the real `git-auto` binary ever drives it.
