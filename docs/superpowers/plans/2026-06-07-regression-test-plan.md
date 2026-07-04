# Regression Test Plan — minimal-git-workflow

**Goal:** Catalog what's covered by automated tests, what requires manual
verification, and which scenarios must be re-checked whenever the plugin's
hooks, scripts, or skills change — so race-condition and cross-repo bugs that
were already fixed don't resurface.

---

## 1. Automated coverage (run before every merge)

Run all four suites from the repo root:

```bash
./scripts/test-handshake.sh --dry-run
./scripts/test-unpushed-status.sh
./scripts/test-clean-slate.sh
./scripts/test-cross-repo-unit-check.sh
```

| Script                          | Guards against                                                                                                     | What it checks                                                                                                              |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- |
| `test-handshake.sh`             | Broken pending-commit handshake between git-auto and Claude                                                        | Writes `pending-commit.json`, verifies Claude (or a stub) can read/respond via `commit-message.txt` without reading diffs   |
| `test-unpushed-status.sh`       | Wrong unpushed-commit detection (`handshake.py unpushed-status`)                                                   | `count`/`branch`/`upstream`/`subjects` correctness on a clean repo, a repo with unpushed commits, and the no-upstream case  |
| `test-clean-slate.sh`           | Git-mechanics regressions in the clean-slate push/squash/leave-as-is paths                                         | Push, squash-into-one, and leave-as-is actually produce the expected ref state against a real local "remote"                |
| `test-cross-repo-unit-check.sh` | The original cross-repo `REPO_ROOT` bug (hook resolved repo from session `$PWD` instead of the edited file's path) | Simulates editing a file in repo-B while session `$PWD` is repo-A; asserts `unit-check.json` lands only in repo-B's `.git/` |

**Re-run trigger:** any change to `handshake.py`, `check-unit-complete.sh`,
`start-git-auto.sh`/`stop-git-auto.sh`, or the `clean-slate` skill/command.

---

## 2. Manual verification (cannot be driven headlessly)

These depend on a live `AskUserQuestion` round-trip or on Claude's session
context — no stub can substitute. Exercise them in a real session against a
repo with unpushed commits (e.g. `dev-test-plugin` in
`deutsche_bahn_delay_predictor_with_weather_info`, which naturally drifts
ahead of its upstream).

| Flow                                     | Trigger                                                                                   | Steps to verify                                                                                                                                                                                                                                                                                                                                                       |
| ---------------------------------------- | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `clean-slate` skill — interactive triage | `UNPUSHED_COMMITS:` marker at SessionStart, or manual `/minimal-git-workflow:clean-slate` | 1) Marker/command surfaces correct branch, upstream, commit subjects (no diffs). 2) `AskUserQuestion` presents exactly the 3 options (push / squash / leave-as-is). 3) Each branch performs the expected git operation and reports the right confirmation message. 4) Push failure (diverged remote) surfaces the raw error and does **not** auto-retry or force-push |
| `clean-slate` slash command              | `/minimal-git-workflow:clean-slate`                                                       | Same as above, plus: confirm the closing `git log --oneline -3` / `git status --short` recap (Step 4) — this differs from the skill's "hand back to caller" ending                                                                                                                                                                                                    |
| `/configure` Step 0 gate                 | `/minimal-git-workflow:configure` on a branch with unpushed commits                       | Confirm it runs `unpushed-status`, and when `count > 0` it routes through clean-slate triage **before** Step 1 (existing-config check), not after                                                                                                                                                                                                                     |
| `commit` / `unit-commit` skills          | Threshold reached / logical unit detected                                                 | Confirm Claude generates the commit message from session context only (subjects + own knowledge) — never via `git diff`/`git show` of file contents                                                                                                                                                                                                                   |
| `wrapup` skill                           | `/minimal-git-workflow:wrapup`                                                            | Confirm pending handshake is resolved and `git-auto` stops cleanly with an accurate final-state report                                                                                                                                                                                                                                                                |

---

## 3. Race-condition regression scenarios

These map to bugs that were found and fixed — re-check on any change that
touches the same code paths.

### 3.1 Cross-repo `REPO_ROOT` resolution

**Original bug:** `check-unit-complete.sh` resolved the repo via
`git rev-parse --show-toplevel` against the session's `$PWD`, not the edited
file's path — so editing a file in a different repo than the session started
in silently no-op'd or wrote `unit-check.json` into the wrong repo.
**Re-check:** `test-cross-repo-unit-check.sh` passes; `unit-check.json` never
appears in the session-start repo when edits happen elsewhere.

### 3.2 Unpushed-commit detection at SessionStart

**Original gap:** sessions could start "mid-stream" on a branch with unpushed
commits, with no signal to Claude before `git-auto` began operating.
**Re-check:** `start-git-auto.sh` prints `UNPUSHED_COMMITS: <n> ahead of
<upstream>` on **both** code paths — fresh start and "already running" — with
correct count and upstream. Verify by:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/start-git-auto.sh"
```

on a repo that is genuinely ahead of its upstream (check both when no daemon
is running and when one already is).

### 3.3 Unpushed-commit detection at mode change

**Original gap:** `/configure` could rewrite `git-auto-config.json` (changing
commit-trigger behavior) while unpushed commits existed from the _old_ mode,
mixing histories from two regimes.
**Re-check:** `/configure` Step 0 always runs `unpushed-status` first and
gates on `count > 0` before Step 1 — see manual flow in §2.

### 3.4 Silent no-op on `count == 0`

**Shared invariant** across both detection sites and the skill/command: when
there's nothing to do, say nothing. Confirm no spurious `AskUserQuestion` or
marker output fires on a clean branch (`test-unpushed-status.sh` covers the
detection layer; manual check confirms the skill/command stay silent).

---

## 4. Cross-repo / symlink-plugin checks

The plugin is installed as a symlink straight to this working tree
(`~/.claude/plugins/minimal-git-workflow -> .../minimal-git-workflow`), so
whatever branch is checked out here is immediately "live" for any session
using the plugin — no build/install step. This means:

- **Branch-switch hygiene:** before live-testing a change in another repo,
  confirm the correct branch is checked out here first
  (`git status --short --branch`).
- **Cross-repo invocation:** run `handshake.py unpushed-status` and
  `start-git-auto.sh` from _inside_ the target repo
  (`cd <other-repo> && python3 ~/.claude/plugins/minimal-git-workflow/scripts/handshake.py unpushed-status`)
  and confirm the returned `branch`/`upstream`/`subjects` describe the target
  repo, never the plugin's own repo.
- **Independent cross-check:** `stop-git-auto.sh`'s own "Unpushed commits: N
  commit(s) not on remote" report should match `unpushed-status`'s `count`
  exactly — a quick sanity check that the two independent code paths
  (bash vs. Python) agree.

---

## 5. Known unrelated findings (track separately, don't block on these)

- `deutsche_bahn_delay_predictor_with_weather_info`'s `git-auto-config.json`
  uses `claude_handshake`/`claude_timeout` keys the installed `git-auto`
  binary doesn't recognize (`Unknown config key(s)` crash on daemon start).
  This is a version/schema mismatch in that repo's config, not a plugin
  regression — the `UNPUSHED_COMMITS:` marker still fires correctly before
  the crash (marker logic runs pre-`nohup`).
