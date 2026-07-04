# Plugin Cross-Repo Test Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Live-test every component of the `minimal-git-workflow` plugin (hooks, skills, scripts) against a real, disposable repo — separate from the plugin's own repo — to catch anything the automated regression scripts in `docs/superpowers/plans/2026-06-07-regression-test-plan.md` can't reach (interactive skill flows, real `git-auto` daemon behavior, real Claude Code session hooks).

**Architecture:** All tasks run against one scratch repo (`~/workdir/repositories/plugin-smoke-test`) with a local bare "remote" so push/squash/auto-commit behavior is fully exercised with zero risk to any real GitHub remote. The plugin is already live via its existing symlink (`~/.claude/plugins/minimal-git-workflow` → this repo) — no packaging/copy step needed. Each task is a black-box test: set up state, trigger the component, assert the observed output/file/git state matches what the SKILL.md/script says should happen.

**Tech Stack:** bash, git, python3, git-auto (Mistral-backed daemon, already installed at `~/.local/bin/git-auto`), Claude Code (skills invoked via `/minimal-git-workflow:<name>`).

## Global Constraints

- Never read full diffs/file contents when testing commit-message generation — every commit-generating flow in this plugin (`commit`, `unit-commit`, `clean-slate` squash) must justify its message from `stat_summary`/`files_changed`/`subjects` only. Flag it as a bug if a step reads `git diff`/`git show` content.
- Never force-push. `clean-slate`'s push step must surface raw errors on failure, not retry/force.
- All destructive git operations (push, squash, reset --soft) happen only inside `plugin-smoke-test` against its local bare remote — never against this plugin repo or any repo with a real remote.
- Scope every state-file check to `plugin-smoke-test/.git/*` — confirm nothing leaks into this plugin repo's own `.git/`.

## Task Overview

| # | Task | Status |
|---|------|--------|
| 1 | Provision the scratch repo and local bare remote | ✅ Done |
| 2 | `/configure` — fresh config, update path, conflict warning | 🟡 Partial (Steps 2–3 done) |
| 3 | SessionStart hook (`start-git-auto.sh`) — all code paths | ⬜ Not started |
| 4 | `/clean-slate` — push / squash / leave-as-is / push failure | ⬜ Not started |
| 5 | Pathway A — threshold-based commit (`/commit`) | ⬜ Not started |
| 6 | Pathway B — logical-unit commit (`/unit-commit`) | ⬜ Not started |
| 7 | `/status` | ⬜ Not started |
| 8 | `/wrapup` | ⬜ Not started |
| 9 | `stop-git-auto.sh` signal-handling edge case | ⬜ Not started |
| 10 | Cross-repo isolation check | ⬜ Not started |
| 11 | Uninstall path | ⬜ Not started |
| 12 | Cleanup | ⬜ Not started |

---

### Task 1: Provision the scratch repo and local bare remote

**Files:**

- Create (outside repo): `~/workdir/repositories/plugin-smoke-test/` (working repo)
- Create (outside repo): `~/workdir/repositories/plugin-smoke-test-remote.git/` (bare remote)

**Interfaces:**

- Produces: a repo at `~/workdir/repositories/plugin-smoke-test` on branch `main`, with `origin` pointing at the bare remote, one commit already pushed — this is the fixture every later task's Claude session runs inside.

**Note — setup gotchas hit during the first run (2026-07-04):**

1. The bare remote must actually be created (`git init --bare .../plugin-smoke-test-remote.git`) _before_ the first push.
   `git remote add` only records a path, it doesn't create anything there — a push against a missing/non-repo path fails with `does not appear to be a git repository`.
2. Never set `origin` via `git remote add origin $(pwd)` from inside the working repo itself.
   That points origin at itself, not the bare remote, and silently produces a nonsensical setup (working repo's `.git` gets read back as a "remote").
3. If `git checkout -b` fails with `fatal: this operation must be run in a work tree`, the current directory is bare (no work tree).
   Check with `git rev-parse --is-bare-repository`. This happens if `git init --bare` was used for the _working_ repo by mistake.

- [x] **Step 1: Create the bare remote and working repo**

```bash
mkdir -p ~/workdir/repositories
git init -q --bare ~/workdir/repositories/plugin-smoke-test-remote.git

git init -q ~/workdir/repositories/plugin-smoke-test
cd ~/workdir/repositories/plugin-smoke-test
git config user.email "test@example.com"
git config user.name "Test"
git remote add origin ~/workdir/repositories/plugin-smoke-test-remote.git
git checkout -q -b main
echo "# plugin-smoke-test" > README.md
git add README.md
git commit -q -m "init"
git push -q -u origin main
```

- [x] **Step 2: Verify clean baseline**

Run:
```bash
cd ~/workdir/repositories/plugin-smoke-test && git status --short --branch && git rev-list @{u}..HEAD --count
```
Expected:
- `## main...origin/main` with no `[ahead/behind]` suffix
- count `0`

- [x] **Step 3: Confirm the plugin symlink covers this repo (symlink install, not per-repo)**

Run: `readlink ~/.claude/plugins/minimal-git-workflow`
Expected: points at this plugin repo's path — since it's a symlink, `plugin-smoke-test` gets the plugin automatically in any Claude Code session started inside it. No install step is repo-specific; only the confirm below matters.
Verified once already (machine-wide symlink, not session-scoped).

- [x] **Step 4: No commit needed** — this task only creates fixtures outside the plugin repo, nothing to commit here.

---

### Task 2: `/minimal-git-workflow:configure` — fresh config, update path, conflict warning

**Files:**

- Create (in scratch repo): `~/workdir/repositories/plugin-smoke-test/git-auto-config.json`

**Interfaces:**

- Consumes: nothing from Task 1 beyond the repo existing at `~/workdir/repositories/plugin-smoke-test`.
- Produces: a `git-auto-config.json` in the scratch repo that Task 3 (SessionStart) and Task 4/5 (commit pathways) read.

- [ ] **Step 1: Start a Claude Code session inside the scratch repo**

Run (in a terminal, not this session): `cd ~/workdir/repositories/plugin-smoke-test && claude`
Expected: SessionStart hook fires `start-git-auto.sh`; since no `git-auto-config.json` exists yet, expect stderr:
```
[minimal-git-workflow] No git-auto-config file found in .../plugin-smoke-test. Run /minimal-git-workflow:configure to create one.
```

- [x] **Step 2: Run `/minimal-git-workflow:configure`, fresh-config path**

Invoke: `/minimal-git-workflow:configure`

Follow SKILL.md:
- Step 0 (unpushed check — count is 0, proceeds silently)
- Step 1 (`ls git-auto-config.*` → "No config found")
- Step 2 (answer with non-default values, e.g. `files_threshold=3`, `push_threshold=2`, `unit_commit=true`, `catchup=false`)

Expected: Step 3 writes `git-auto-config.json` with exactly the fields from SKILL.md Step 3's JSON shape (`start.files_threshold`, `start.push_threshold`, `start.squash_threshold`, `start.catchup`, `start.cooldown`, `start.model`, top-level `unit_commit`), and confirms: "Config written to git-auto-config.json...".

- [x] **Step 3: Verify file contents directly**

Run: `cat ~/workdir/repositories/plugin-smoke-test/git-auto-config.json`
Expected: valid JSON matching the values entered in Step 2 above.

- [ ] **Step 4: Re-run `/minimal-git-workflow:configure`, existing-config path**

Invoke: `/minimal-git-workflow:configure` again.
Expected:
- Step 1 finds the existing file and shows current values
- It asks "update or keep as-is?"
- Confirm both branches work: keep as-is leaves the file unchanged; update lands new values via Step 3's write.

- [ ] **Step 5: Trigger the catchup+unit_commit conflict warning**

Invoke `/minimal-git-workflow:configure` and answer `catchup=true` AND `unit_commit=true`.
Expected:
- Step 2.5's exact warning text appears before the write, asking to keep both or set `catchup: false`.
- Choose "set catchup: false" and confirm the written file reflects `catchup: false`.

**Finding (2026-07-04): `/configure` doesn't validate `squash_threshold` vs. `push_threshold`.**

Live run: Step 2 answers `push_threshold=4`, `squash_threshold=6` were accepted and written without warning. `git-auto` itself rejects this combination at daemon start (`squash_threshold` must be `<` `push_threshold`) — see Task 3 Step 7's crash-detection path, which is what actually surfaced this: `start-git-auto.sh` correctly detected the crash and reported it, but the _cause_ traces back to `/configure` accepting an invalid combination silently. Unlike Step 2.5's `catchup`+`unit_commit` warning, `skills/configure/SKILL.md` Step 2 has no equivalent guard for this constraint.

Proposed fix (not applied — flag only): add a check in Step 2/2.5 rejecting or warning when `squash_threshold > 0` and `squash_threshold >= push_threshold`.

- [ ] **Step 6: Commit the fixture config for reference (optional but keeps the scratch repo reproducible)**

```bash
cd ~/workdir/repositories/plugin-smoke-test
git add git-auto-config.json
git commit -m "chore: add git-auto-config.json from /configure test"
git push
```

---

### Task 3: SessionStart hook (`start-git-auto.sh`) — all code paths

**Files:**

- Reference only: `scripts/start-git-auto.sh`, `.git/git-auto-state.json`, `.git/unit-check.json`, `.git/pending-commit.json` (all under `plugin-smoke-test/.git/`)

**Interfaces:**

- Consumes: `git-auto-config.json` written in Task 2.
- Produces: a running `git-auto` daemon scoped to `plugin-smoke-test`, whose state Task 4–7 depend on.

- [ ] **Step 1: Fresh start (daemon not yet running for this repo)**

Ensure no daemon is running: `git-auto status --path ~/workdir/repositories/plugin-smoke-test` (expect "not running" or similar).

Start a fresh Claude Code session in the scratch repo (or manually run):

```bash
cd ~/workdir/repositories/plugin-smoke-test
bash ~/.claude/plugins/minimal-git-workflow/scripts/start-git-auto.sh
```

Expected stderr:
1. `Starting git-auto with config: .../git-auto-config.json`
2. after the 3s liveness check: `git-auto started for .../plugin-smoke-test (PID <pid>)`

Expected stdout: `MONITOR_REQUIRED: Call the Monitor tool with command: bash ".../scripts/watch-pending.sh" ...`

- [ ] **Step 2: Verify daemon is actually alive**

Run: `cat ~/workdir/repositories/plugin-smoke-test/.git/git-auto-state.json`
Expected:
- JSON containing `pid` and `path` matching `plugin-smoke-test`'s absolute path
- `kill -0 <pid>` exits 0

- [ ] **Step 3: Already-running skip path**

Run the same start command again: `bash ~/.claude/plugins/minimal-git-workflow/scripts/start-git-auto.sh`
Expected:
- stderr: `git-auto already running for this project (PID <same pid>) — skipping.`
- the same `MONITOR_REQUIRED` line on stdout
- the PID in `git-auto-state.json` is unchanged (no restart happened)

- [ ] **Step 4: Stale `unit-check.json` sweep**

Stop the daemon first (see Task 9), then manually plant a stale file:

```bash
cd ~/workdir/repositories/plugin-smoke-test
python3 -c "
import json
from datetime import datetime
json.dump({'branch':'main','files_changed':['README.md'],'stat_summary':'1 file changed','timestamp':datetime.now().isoformat()}, open('.git/unit-check.json','w'))
"
bash ~/.claude/plugins/minimal-git-workflow/scripts/start-git-auto.sh
```

Expected:
- stderr: `STALE_UNIT_CHECK: orphaned check from a previous session (... ) — never evaluated. Clearing it; ...`
- `.git/unit-check.json` no longer exists afterward: `test -f ~/workdir/repositories/plugin-smoke-test/.git/unit-check.json` exits 1

- [ ] **Step 5: Stale `pending-commit.json` sweep**

Stop the daemon, plant a stale pending-commit file, restart:

```bash
cd ~/workdir/repositories/plugin-smoke-test
python3 "$HOME/.claude/plugins/minimal-git-workflow/scripts/handshake.py" write-message dummy 2>/dev/null || true
python3 -c "
import json
from datetime import datetime
json.dump({'branch':'main','files_changed':['README.md'],'stat_summary':'1 file changed','timestamp':datetime.now().isoformat()}, open('.git/pending-commit.json','w'))
"
bash ~/.claude/plugins/minimal-git-workflow/scripts/start-git-auto.sh
```

Expected:
- stderr: `STALE_PENDING_COMMIT: orphaned handshake file from a previous session/test (...) — never a real pending commit. Clearing it.`
- the file is gone

- [ ] **Step 6: No-config case**

Temporarily rename the config, restart, then restore it:

```bash
cd ~/workdir/repositories/plugin-smoke-test
mv git-auto-config.json /tmp/git-auto-config.json.bak
bash ~/.claude/plugins/minimal-git-workflow/scripts/start-git-auto.sh
mv /tmp/git-auto-config.json.bak git-auto-config.json
```

Expected:
- stderr: `No git-auto-config file found in .../plugin-smoke-test.` / `Run /minimal-git-workflow:configure to create one.`
- Exit code 0 (not an error — no daemon started)

- [ ] **Step 7: Invalid-config crash detection**

```bash
cd ~/workdir/repositories/plugin-smoke-test
cp git-auto-config.json /tmp/git-auto-config.json.good
python3 -c "import json; json.dump({'start':{'bogus_key_xyz': True}}, open('git-auto-config.json','w'))"
bash ~/.claude/plugins/minimal-git-workflow/scripts/start-git-auto.sh; echo "exit=$?"
cp /tmp/git-auto-config.json.good git-auto-config.json
```

Expected:
- exit code `1`
- stderr shows `git-auto failed to start — it exited immediately. Last log lines:` followed by `tail -n 5` of `.git/git-auto.log` (should show git-auto's own "Unknown config key(s)" error)
- a hint to check the config or run `git-auto start --path ...` directly

- [ ] **Step 8: UNPUSHED_COMMITS marker on both fresh-start and already-running paths**

Create one local commit without pushing, then restart from a stopped state:

```bash
cd ~/workdir/repositories/plugin-smoke-test
echo "line" >> README.md && git commit -qam "chore: unpushed test commit"
bash ~/.claude/plugins/minimal-git-workflow/scripts/start-git-auto.sh
```

Expected stderr includes: `UNPUSHED_COMMITS: 1 ahead of origin/main — invoke /minimal-git-workflow:clean-slate before continuing.`

Repeat without stopping the daemon (already-running path) — same marker must appear per `start-git-auto.sh`'s "already running" branch too.

Clean up: push or reset this commit before continuing to Task 4 (`git push` is fine — it's the scratch remote).

---

### Task 4: `/minimal-git-workflow:clean-slate` — push / squash / leave-as-is / push failure

**Files:**

- Reference only: `skills/clean-slate/SKILL.md`

**Interfaces:**

- Consumes: `handshake.py unpushed-status` output (`count`, `branch`, `upstream`, `subjects`).
- Produces: scratch repo returned to `count == 0` after each sub-test (except leave-as-is, tested last).

- [ ] **Step 1: Silent no-op on count == 0**

With a clean scratch repo (`git rev-list @{u}..HEAD --count` → 0), invoke `/minimal-git-workflow:clean-slate`.
Expected: no `AskUserQuestion`, no output — the skill returns control immediately per Step 1.

- [ ] **Step 2: Push now**

```bash
cd ~/workdir/repositories/plugin-smoke-test
echo "a" >> README.md && git commit -qam "feat: a"
echo "b" >> README.md && git commit -qam "fix: b"
```

Invoke `/minimal-git-workflow:clean-slate`.
Expected:
- `AskUserQuestion` shows branch `main`, upstream `origin/main`, subjects `["fix: b", "feat: a"]` (newest-first) — never diffs.
- Choose "Push now".
- `git push` succeeds, confirmation "Pushed 2 commit(s) to origin/main.", and `git rev-list @{u}..HEAD --count` → `0`.

- [ ] **Step 3: Squash into one**

```bash
cd ~/workdir/repositories/plugin-smoke-test
echo "c" >> README.md && git commit -qam "feat: c"
echo "d" >> README.md && git commit -qam "fix: d"
```

Invoke `/minimal-git-workflow:clean-slate`, choose "Squash into one".
Expected:
- `git reset --soft @{u}` runs
- one new commit is created summarizing "c" and "d" using only the subjects (never `git diff`), then pushed
- `git log -1 --format=%s` shows the new squashed message
- `git rev-list @{u}..HEAD --count` → `0`

- [ ] **Step 4: Leave as-is**

```bash
cd ~/workdir/repositories/plugin-smoke-test
echo "e" >> README.md && git commit -qam "feat: e"
```

Invoke `/minimal-git-workflow:clean-slate`, choose "Leave as-is".
Expected:
- no git operation runs
- confirm "Leaving 1 unpushed commit(s) as-is."
- `git rev-list @{u}..HEAD --count` still `1`

Clean up: `git push` manually to return to a clean baseline for Task 5.

- [ ] **Step 5: Push failure surfaces raw error, no force-push**

Simulate a diverged remote:

```bash
cd ~/workdir/repositories/plugin-smoke-test-remote.git
# simulate an external push landing on origin/main that this working copy doesn't have
git --git-dir=. log --oneline -1
```

```bash
cd /tmp && rm -rf plugin-smoke-test-other
git clone -q ~/workdir/repositories/plugin-smoke-test-remote.git plugin-smoke-test-other
cd plugin-smoke-test-other
git config user.email test@example.com && git config user.name Test
echo "other" >> README.md && git commit -qam "chore: divergent commit" && git push -q
```

Back in `plugin-smoke-test`:

```bash
cd ~/workdir/repositories/plugin-smoke-test
echo "f" >> README.md && git commit -qam "feat: f"
```

Invoke `/minimal-git-workflow:clean-slate`, choose "Push now".
Expected:
- `git push` fails (non-fast-forward)
- the skill surfaces the exact git error text
- does NOT retry, does NOT force-push
- `git log origin/main -1` confirms the remote still only has the "divergent commit" — no forced overwrite occurred

Clean up: `git pull --rebase && git push` to resolve, then `rm -rf /tmp/plugin-smoke-test-other`.

---

### Task 5: Pathway A — threshold-based commit (git-auto + `/minimal-git-workflow:commit`)

**Files:**

- Reference only: `skills/commit/SKILL.md`, `scripts/watch-pending.sh`, `scripts/handshake.py`

**Interfaces:**

- Consumes: `files_threshold` from `git-auto-config.json` (Task 2).
- Produces: a real commit in `plugin-smoke-test`, and clears both handshake files.

- [ ] **Step 1: Set a low threshold and start the Monitor**

```bash
cd ~/workdir/repositories/plugin-smoke-test
python3 -c "
import json
c = json.load(open('git-auto-config.json'))
c['start']['files_threshold'] = 1
json.dump(c, open('git-auto-config.json','w'))
"
```

Restart git-auto with the new config (stop then start per Task 3/9), and call the Monitor tool with `bash ~/.claude/plugins/minimal-git-workflow/scripts/watch-pending.sh` in the session (this is what `MONITOR_REQUIRED` asks for).

- [ ] **Step 2: Trigger the threshold**

```bash
cd ~/workdir/repositories/plugin-smoke-test
echo "trigger" >> README.md
```

Wait up to ~5s (git-auto's own poll interval) for it to detect 1 file changed and hit the threshold.
Expected: `watch-pending.sh` (running under Monitor) emits a notification line: `PENDING_COMMIT: git-auto needs a commit message. Summary: ... Run /minimal-git-workflow:commit to generate one.`

- [ ] **Step 3: Run `/minimal-git-workflow:commit`**

Invoke `/minimal-git-workflow:commit`.
Expected:
- Step 1 reads `pending-commit.json` via `handshake.py read-pending`, returns `branch`/`files_changed`/`stat_summary`/`timestamp`
- Step 2 generates a conventional commit message using only that JSON + session knowledge (no `git diff`/`git show`)
- Step 3 writes it via `handshake.py write-message '<msg>'` with no confirmation prompt

- [ ] **Step 4: Verify the round-trip**

```bash
cat ~/workdir/repositories/plugin-smoke-test/.git/commit-message.txt
```

Expected: the exact message Claude generated. Then wait a few seconds and confirm git-auto picked it up:

```bash
cd ~/workdir/repositories/plugin-smoke-test && git log -1 --format=%s
```

Expected:
- matches the written message
- both `.git/pending-commit.json` / `.git/commit-message.txt` are gone (git-auto clears them after committing)

- [ ] **Step 5: No pending commit case**

Run `/minimal-git-workflow:commit` again immediately with nothing pending.
Expected: "No pending commit found. git-auto hasn't hit a threshold yet." and it stops — no file writes.

---

### Task 6: Pathway B — logical-unit commit (`check-unit-complete.sh` + `/minimal-git-workflow:unit-commit`)

**Files:**

- Reference only: `scripts/check-unit-complete.sh`, `skills/unit-commit/SKILL.md`

**Interfaces:**

- Consumes: `unit_commit: true` in `git-auto-config.json` (set in Task 2 Step 2/5).
- Produces: either a direct commit (yes-branch) or a cleared `unit-check.json` with no commit (no-branch).

- [ ] **Step 1: Ensure `unit_commit: true` and a high `files_threshold` (avoid Pathway A racing)**

```bash
cd ~/workdir/repositories/plugin-smoke-test
python3 -c "
import json
c = json.load(open('git-auto-config.json'))
c['unit_commit'] = True
c['start']['files_threshold'] = 999
c['start']['catchup'] = False
json.dump(c, open('git-auto-config.json','w'))
"
```

Restart git-auto (Task 3/9 stop+start) so the new config takes effect.

- [ ] **Step 2: Edit a file via Claude's Edit tool inside the scratch-repo session**

Have Claude edit a file in `plugin-smoke-test` (e.g. append a line to README.md via the Edit tool — this fires the `PostToolUse` hook for real).
Expected:
- stderr from `check-unit-complete.sh`: `unit-check.json written (N changed file(s)) — watch-pending.sh will notify Claude.`
- Monitor output: `UNIT_CHECK: Uncommitted changes detected. Summary: ... Run /minimal-git-workflow:unit-commit to evaluate whether this is a complete logical unit.`

- [ ] **Step 3: `/minimal-git-workflow:unit-commit` — NO branch (incomplete unit)**

Make a clearly incomplete edit (e.g. add a single import-like line with no accompanying logic), invoke `/minimal-git-workflow:unit-commit`.
Expected: Claude judges "no", runs `handshake.py clear-unit-check`, no commit happens, no message to the user.
Verify: `git status --short` still shows the uncommitted change; `.git/unit-check.json` is gone.

- [ ] **Step 4: `/minimal-git-workflow:unit-commit` — YES branch (complete unit)**

Make a self-contained change (e.g. finish a small doc section), let `check-unit-complete.sh` fire again, invoke `/minimal-git-workflow:unit-commit`.
Expected: Claude judges "yes", generates a conventional message from `stat_summary`/`files_changed` only, runs `git add . && git commit -m '<msg>'` directly (no confirmation prompt), then `handshake.py clear-unit-check`.
Verify: `git log -1 --format=%s` matches the message; `.git/unit-check.json` gone; reports "Committed: `<message>`" (no push, since `push_threshold` wasn't reached).

- [ ] **Step 5: Push-threshold cascade**

Set `push_threshold` low (e.g. `1`) and repeat Step 4's yes-branch flow once more.
Expected: after committing, the skill reads `push_threshold` from config, counts `git rev-list @{u}..HEAD --count`, finds it `>= push_threshold`, runs `git push`, and reports "Committed: `<message>` — pushed."
Verify: `git rev-list @{u}..HEAD --count` → `0` after.

- [ ] **Step 6: Stale unit-check mid-session sweep**

Manually backdate a `unit-check.json` past the 300s TTL and fire the hook again to confirm the mid-session sweep (distinct from the SessionStart sweep in Task 3 Step 4):

```bash
cd ~/workdir/repositories/plugin-smoke-test
python3 -c "
import json
json.dump({'branch':'main','files_changed':['README.md'],'stat_summary':'x','timestamp':'2020-01-01T00:00:00'}, open('.git/unit-check.json','w'))
"
echo "another edit" >> README.md
```

Trigger the PostToolUse hook again via an Edit tool call.
Expected: stderr: `STALE_UNIT_CHECK: orphaned check from earlier in this session (... 300s+ old ...) — never evaluated. Clearing it and regenerating from current state.` and a fresh `unit-check.json` is written afterward.

---

### Task 7: `/minimal-git-workflow:status`

**Files:**

- Reference only: `skills/status/SKILL.md`

**Interfaces:**

- Consumes: `git-auto status`, `handshake.py status`, `git status --short`, `git log --oneline -5`.

- [ ] **Step 1: Running, no pending commits**

With git-auto running and a clean tree, invoke `/minimal-git-workflow:status`.
Expected:
- Step 1 shows `git-auto status` output (PID/branch/mode/thresholds)
- Step 2 shows `pending-commit.json: none`, `commit-message.txt: none`, `unit-check.json: none`
- Step 4 summary: "git-auto is running. No pending commits."

- [ ] **Step 2: Running, commit pending**

Trigger Pathway A's threshold (like Task 5 Step 2) but don't run `/minimal-git-workflow:commit` yet, then invoke `/minimal-git-workflow:status`.
Expected:
- Step 2 shows `pending-commit.json: EXISTS`, with `branch` and `stat_summary` populated
- Step 4 summary: "git-auto is running. Commit pending — run /minimal-git-workflow:commit"

Clean up: run `/minimal-git-workflow:commit` to resolve it.

- [ ] **Step 3: Not running**

Stop git-auto (Task 9), invoke `/minimal-git-workflow:status`.
Expected: Step 4 summary: "git-auto is not running — run /minimal-git-workflow:configure to set up, or check SessionStart hook."

---

### Task 8: `/minimal-git-workflow:wrapup`

**Files:**

- Reference only: `skills/wrapup/SKILL.md`, `scripts/stop-git-auto.sh`

**Interfaces:**

- Consumes: handshake state from Task 5/6, `stop-git-auto.sh` exit behavior.

- [ ] **Step 1: Wrapup with a pending handshake**

Trigger Pathway A's threshold (Task 5 Step 2) so `pending-commit.json` exists, then invoke `/minimal-git-workflow:wrapup`.
Expected: Step 1 detects the pending commit and resolves it first (same steps as `/minimal-git-workflow:commit`) before proceeding to Step 2.
Verify: `git log -1 --format=%s` reflects the generated message before stop-git-auto runs.

- [ ] **Step 2: Wrapup with uncommitted changes present**

```bash
cd ~/workdir/repositories/plugin-smoke-test
echo "uncommitted" >> README.md
```

Invoke `/minimal-git-workflow:wrapup`.
Expected: Step 2 reports "There are uncommitted changes. git-auto stop will warn about these." and lists the short-form file list (no content).

- [ ] **Step 3: Stop and final report**

Continuing from Step 2, confirm:
- Step 3 runs `stop-git-auto.sh` and shows its output
- Step 4 shows `git log --oneline -3` and `git status --short`
- Step 5 gives a summary distinguishing "Working tree is clean." vs. "Note: N uncommitted files remain — commit manually if needed." (should be the latter here, matching Step 2's dirty file)

Clean up: `git checkout -- README.md` or commit it, to return to a clean baseline.

---

### Task 9: `stop-git-auto.sh` signal-handling edge case

**Files:**

- Reference only: `scripts/stop-git-auto.sh`

**Interfaces:**

- Consumes: `.git/git-auto-state.json`'s `pid` field.
- Produces: confirmed-dead PID, cleared handshake files.

- [ ] **Step 1: Normal stop (SIGINT succeeds)**

```bash
cd ~/workdir/repositories/plugin-smoke-test
PID_BEFORE=$(python3 -c "import json;print(json.load(open('.git/git-auto-state.json'))['pid'])")
bash ~/.claude/plugins/minimal-git-workflow/scripts/stop-git-auto.sh
```

Expected stderr:
1. `Stopping git-auto for .../plugin-smoke-test`
2. after the grace window: `git-auto stopped for .../plugin-smoke-test (PID <PID_BEFORE> confirmed dead).`

Verify: `kill -0 <PID_BEFORE>` exits nonzero (process gone); `.git/pending-commit.json`, `.git/commit-message.txt`, `.git/unit-check.json` are all removed.

- [ ] **Step 2: Stop when nothing is running**

Run `bash ~/.claude/plugins/minimal-git-workflow/scripts/stop-git-auto.sh` again immediately.
Expected: `git-auto was not running for .../plugin-smoke-test.`

- [ ] **Step 3: SIGINT-masked escalation path (only if reproducible)**

This path only triggers when the daemon was started without the `trap - INT QUIT` reset (e.g. a manually-launched `nohup git-auto start ... &` outside `start-git-auto.sh`). If reproduced:

```bash
cd ~/workdir/repositories/plugin-smoke-test
( trap '' INT QUIT; exec nohup git-auto start --path "$(pwd)" >> .git/git-auto.log 2>&1 ) &
sleep 3
bash ~/.claude/plugins/minimal-git-workflow/scripts/stop-git-auto.sh
```

Expected: stderr shows `PID <pid> survived SIGINT (likely masked to SIG_IGN by bash job control) — escalating to SIGTERM.` and eventually confirmed dead (SIGTERM or, if needed, `forcing SIGKILL`).
Verify: `kill -0 <pid>` exits nonzero at the end regardless of which signal finally worked.

---

### Task 10: Cross-repo isolation check

**Files:**

- Reference only: none modified; this task only asserts file locations.

**Interfaces:**

- Consumes: an active `plugin-smoke-test` session plus a second, simultaneous edit in the plugin's own repo.

- [ ] **Step 1: Start git-auto for plugin-smoke-test, confirm baseline state files**

```bash
ls ~/workdir/repositories/plugin-smoke-test/.git/ | grep -E 'git-auto-state|unit-check|pending-commit' || true
ls ~/workdir/repositories/minimal-git-workflow/.git/ | grep -E 'git-auto-state|unit-check|pending-commit' || true
```

Expected: `plugin-smoke-test/.git/git-auto-state.json` exists; `minimal-git-workflow/.git/` shows none of these three (assuming no session-in-progress there).

- [ ] **Step 2: Edit a file in the plugin repo while the smoke-test session's `$PWD` is elsewhere**

With the Claude session's shell `$PWD` still logically tied to `plugin-smoke-test`, have Claude Edit a file whose path lives under `~/workdir/repositories/minimal-git-workflow/` (e.g. append a comment to `development-details.md` — revert after).
Expected: `check-unit-complete.sh` resolves `REPO_ROOT` from `tool_input.file_path` (the edited file), not `$PWD` — so (if `unit_commit` is enabled there) `unit-check.json` would land in `minimal-git-workflow/.git/`, never in `plugin-smoke-test/.git/`.
Verify: `ls ~/workdir/repositories/plugin-smoke-test/.git/unit-check.json` still does NOT exist (no cross-contamination); revert the edit in `development-details.md` (`git checkout -- development-details.md` in the plugin repo) since it was only a probe.

---

### Task 11: Uninstall path

**Files:**

- Reference only: `uninstall.sh`

**Interfaces:**

- Consumes: `~/.claude/plugins/minimal-git-workflow` symlink.

- [ ] **Step 1: Run uninstall.sh**

```bash
cd ~/workdir/repositories/minimal-git-workflow
bash uninstall.sh
```

Expected: `Removed symlink: /home/anam/.claude/plugins/minimal-git-workflow`, and the note that `git-auto` itself was not uninstalled.
Verify: `test -L ~/.claude/plugins/minimal-git-workflow` exits nonzero (symlink gone); `command -v git-auto` still succeeds.

- [ ] **Step 2: Re-run uninstall.sh (idempotency)**

```bash
bash uninstall.sh
```

Expected: `Plugin not installed at .../minimal-git-workflow — nothing to do.`

- [ ] **Step 3: Restore the symlink for normal use**

```bash
bash install.sh
```

Expected: `git-auto already on PATH — skipping install.` then `Symlink already correct` or a fresh `ln -s`; confirm `readlink ~/.claude/plugins/minimal-git-workflow` points back at this repo.

---

### Task 12: Cleanup

**Files:**

- Delete (outside repo): `~/workdir/repositories/plugin-smoke-test/`, `~/workdir/repositories/plugin-smoke-test-remote.git/`

- [ ] **Step 1: Stop any running daemon for the scratch repo**

```bash
cd ~/workdir/repositories/plugin-smoke-test 2>/dev/null && bash ~/.claude/plugins/minimal-git-workflow/scripts/stop-git-auto.sh || true
```

- [ ] **Step 2: Remove scratch fixtures**

```bash
rm -rf ~/workdir/repositories/plugin-smoke-test ~/workdir/repositories/plugin-smoke-test-remote.git /tmp/plugin-smoke-test-other
```

- [ ] **Step 3: Confirm no residue in the plugin repo**

```bash
cd ~/workdir/repositories/minimal-git-workflow && git status --short
```

Expected: clean (aside from any intentional edits from this session, e.g. this plan file itself).
