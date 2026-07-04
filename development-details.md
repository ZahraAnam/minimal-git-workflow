# minimal-git-workflow — Development Details

Raw material for blog posts. Compiled from git history, merged PRs, session
summaries, and live debugging sessions across 2026-06-07 → 2026-06-08.

---

## What the plugin is

A Claude Code plugin that automates git commits using Claude's own session
context — no raw diffs are ever read into the model's context window. It
wraps and drives [`git-auto`](https://github.com/ZahraAnam/automate-git-commands),
a separate daemon (`pip install -e .` from `automate-git-commands`) that
watches a repo and fires commits on thresholds.

Two commit pathways run in parallel:

- **Pathway A — threshold-based (git-auto):** file edits accumulate →
  `files_threshold` reached → git-auto commits fully autonomously, generating
  its own message via its LLM agent (Mistral by default). **Correction (added
  2026-07-04):** this was originally documented here as a Claude handshake —
  "git-auto writes `pending-commit.json` → Claude generates a commit message
  from session context → git-auto commits" — but that's not how the real
  `git-auto` binary (`automate-git-commands/git-auto/cli.py`) works: it never
  reads or writes `pending-commit.json`/`commit-message.txt`. Those files, and
  the `commit` skill/command built around them, exist in this plugin's scripts
  but are never actually driven by git-auto in normal operation — only
  `test-handshake.sh` simulates the write, to test the plugin side in
  isolation. Caught while reviewing `plugin-working.md` against the actual
  `git-auto` source.
- **Pathway B — logical-unit-based (unit-commit):** after every Edit/Write tool
  use, `check-unit-complete.sh` fires; if the tree is dirty it writes
  `unit-check.json`; Claude evaluates "did I just finish a self-contained piece
  of work?" and commits directly if yes. This is the only pathway where
  Claude's session-context handshake is real.

Architecture in one line: for Pathway B, shell hooks + a Python handshake
module (`scripts/handshake.py`) write small JSON state files into `.git/`, and
Claude-side skills/commands read them, generate messages from *session memory*
(never `git diff`), and write back — keeping the LLM's context budget untouched
by diff content. Pathway A doesn't participate in this — it's git-auto's own
independent, session-blind commit loop.

---

## Timeline of major work

### 2026-06-07 — `feat/clean-slate-unpushed-prompt` → PR #1 (merged)
First big feature push. Added:
- `unpushed-status` detection in `handshake.py` (count + branch + upstream +
  commit subjects — **never diffs**, staying true to the plugin's core
  constraint)
- `clean-slate` interactive skill — lets the user push / squash / leave-as-is
  when unpushed commits pile up
- Wiring into `start-git-auto.sh` (prints an `UNPUSHED_COMMITS:` marker on
  session start) and into `/configure` (a new "Step 0" gate that blocks mode
  changes until the slate is clean)
- A first batch of regression tests: `test-unpushed-status.sh`,
  `test-clean-slate.sh`

Notable process detail: the PR checklist explicitly separated *automated*
coverage (scripts that pass) from *interactive* coverage ("live-test in a real
repo... in progress") — a pattern that recurs through the whole project: this
plugin's riskiest surfaces are things that need a live `AskUserQuestion`
session, which can't be scripted.

### `fix/readme-table-formatting` → PR #2 (merged)
Pure cosmetic — realigning markdown table columns. Notable only because its
description says it "carries forward a local README change that predated the
clean-slate PR merge and got missed" — a small example of how parallel
branches can drop unrelated working-tree edits if you're not careful about
what you stage.

### `feat/clean-slate-command` → PR #3 (merged)
Added `/minimal-git-workflow:clean-slate` as a standalone slash command.
Rationale given in the PR: *"mirrors existing pattern — every other skill has
a matching command; clean-slate was the one missing."* This skill↔command
duplication (each skill has a near-identical command wrapper) becomes a
recurring maintenance headache later (see the commit-confirmation saga below)
because the two copies drift out of sync silently.

### `docs/regression-test-plan` → PR #4 (still open)
A catalog rather than code: which of the 4 `test-*.sh` scripts guard what,
which flows are manual-only (anything needing `AskUserQuestion` — clean-slate
triage, `/configure` Step 0, commit-message generation, wrapup), the 4 known
race-condition scenarios already fixed, and a symlink/cross-repo invocation
checklist. Also tracks an *unrelated* `claude_handshake`/`claude_timeout`
config-key mismatch discovered while testing live in another repo
(`deutsche_bahn_delay_predictor_with_weather_info`) — explicitly filed as "not
a plugin regression" so it wouldn't get conflated with this plugin's bugs.

### `fix/unit-commit-stale-state-and-config` → PR #5 + PR #6 (merged)
Triggered by *live* testing in `deutsche_bahn_delay_predictor_with_weather_info`
— a separate real-world repo where the plugin runs symlinked. Found and fixed
three distinct bugs in one session (rated 85% — "Code done" but "complicated
and not intuitive to follow, user had to carefully find issues and provide
guidance"):

1. **Stale `unit-check.json` blocks detection forever.** If a session crashes
   or gets interrupted before evaluating a written `unit-check.json`, the
   guard in `check-unit-complete.sh` (which refuses to overwrite an existing
   check, "trusting Claude to clear it") permanently wedges Pathway B. Fix:
   sweep *any* `unit-check.json` present at `SessionStart` — it's necessarily
   orphaned, since a fresh session hasn't edited anything yet. Decision
   rationale (user's words): *"catchup and updates should always be possible"*
   — so no TTL, just presence-at-start as the deterministic signal. Before
   deleting, surface its contents via a `STALE_UNIT_CHECK:` marker so the
   uncommitted-work trail isn't silently lost (the user caught that a blind
   `rm` would do exactly that).
2. **Invalid config keys crash git-auto silently.** The daemon dies ~2s after
   a bad config (e.g. mismatched `claude_handshake`/`claude_timeout` keys),
   but the wrapper reported success because it only checked "did the process
   start," not "is it still alive." Fix: PID-liveness + log-tail check after
   launch — deliberately generic rather than a narrow validator for those two
   keys, so it "catches ANY startup crash."
3. **`catchup` races ahead of `unit_commit`.** `catchup: true` bulk-commits
   everything pending with a generic Mistral message *before* the unit-commit
   pathway gets a chance to bundle a logical unit — the two features fight
   over the same dirty tree. Fix: a Step 2.5 warning in both
   `skills/configure/SKILL.md` and `commands/configure.md` (mirrored
   deliberately — "these two drift apart historically, kept in sync").

Then PR #6 widened the fix: the crash-detection sleep window went from 1.5s →
3s (the original window could see a false "alive" PID mid-crash), and the
stale-`unit-check.json` sweep — originally SessionStart-only — got extended to
the *live* session: `check-unit-complete.sh` now ages the existing check
against its `timestamp`, and anything past 300s gets surfaced via the same
`STALE_UNIT_CHECK` marker, cleared, and regenerated from current repo state.

---

## The commit-confirmation saga (good blog material — a bug fixed twice)

This is the most interesting thread for a "what we learned" post: **the same
fix was implemented twice, a day apart, because the first implementation lived
on a branch that never got merged.**

- **2026-06-07, commit `f4d722b`** (`refactor(commit skill): auto-write commit
  message without confirmation`, on branch `feat/initialize-work` —
  **never merged into `main`**): collapsed `skills/commit/SKILL.md`'s old
  Step3/4/5 confirm-then-write flow into a direct write, with the rationale
  *"Handshake is fire-and-forget — git-auto polls and falls back to Mistral on
  timeout regardless."* Crucially, this only touched the **skill** file —
  `commands/commit.md` (the slash-command twin) was left with the old
  yes/edit/skip prompt.
- **2026-06-08** (this session, PR #7, `ebd792c`): the user explicitly said
  the plugin's whole point is "automate commits and pushes, don't ask again
  and again" — and pointed at the still-present "Use this commit message?
  (yes / edit / skip)" prompt as the contradiction. Cross-checking against
  `unit-commit` (which *also* documents itself as "Run immediately — no
  confirmation prompt") confirmed `commit` was the odd one out. Fixed **both**
  `skills/commit/SKILL.md` *and* `commands/commit.md` this time, removing the
  Step 3 confirm gate from each and renumbering the remaining steps.

**Why it regressed:** `f4d722b` sat on an orphaned feature branch
(`feat/initialize-work`) that was never merged to `main`. From `main`'s
perspective the bug was never fixed — so it surfaced again, independently,
exactly where the skill/command duplication (see PR #3 above) made it easy to
half-fix. The lesson generalizes: **a fix that isn't on the integration branch
doesn't exist**, and any place where the same behavior is described twice
(skill + command, here) is a place where "fixed it" can quietly mean "fixed
half of it."

---

## The `/doctor` plugin-marketplace warning (a red herring, almost)

`/doctor` reported: *"Plugin (minimal-git-workflow@local): Marketplace local
not found."* First instinct was to remove the dangling
`"minimal-git-workflow@local": true` entry from `~/.claude/settings.json`'s
`enabledPlugins`.

That would have **re-broken the plugin's skills** — a separate, earlier
debugging thread (preserved in project-planner memory,
`project_minimal-git-workflow-plugin.md`) had already nailed down, through
three failed/partial attempts, that:
- project-scoped plugins only get hooks, not skills (needs `scope: "user"`)
- the harness only loads skills from `installPath` under
  `~/.claude/plugins/cache/` — direct paths get hooks-only
- and, the actual fix: `enabledPlugins`' key (`minimal-git-workflow@local`)
  must **exactly match** the key used in `installed_plugins.json`, or the
  harness can't correlate "is this plugin enabled" with "is this plugin
  installed," and silently skips loading skills.

So `@local` isn't a real marketplace — it's a naming convention for
locally-installed plugins, and `known_marketplaces.json` has no `local` entry
to resolve it against. The `/doctor` warning is **cosmetic noise from a
working configuration that took real effort to stabilize**. Verdict: leave it,
document it, move on. (Memory updated accordingly so future sessions don't
reopen this.)

This is a good "measure twice" story: the obvious fix for a warning message
was the exact thing that would have reintroduced a previously-fixed, much
worse bug.

### The sleep bug: `--force` wasn't the whole fix (PR #9 + #10)

PR #8's `--force` fix (below) turned out to be necessary but **not
sufficient** — it silenced the interactive confirm blocking the stop signal,
but a second, independent masking problem meant the signal often did nothing
even once it was sent.

**Root cause:** bash forces `SIGINT`/`SIGQUIT` to `SIG_IGN` on any `&`
background job started from a script — a job-control rule, not something
`nohup` covers (`nohup` only touches `SIGHUP`). `start-git-auto.sh` launched
git-auto with a plain `nohup ... &`, so the daemon inherited that ignore-mask
straight through `exec`. `git-auto stop`'s `os.kill(pid, SIGINT)` became a
structural no-op against a `SIG_IGN` process — but the wrapper reported
success unconditionally, so the daemon just kept running, invisibly, past
every "successful" wrapup.

**Fix (`debug/fix-wrapup-command`, PR #9, `9f896b1`/`ce16c33`, merged
2026-06-08):**
- `start-git-auto.sh`: wrap the launch in a subshell that runs `trap - INT
  QUIT` before `exec`-ing git-auto, resetting the disposition to default so
  the daemon can actually receive `SIGINT`/`SIGQUIT` going forward.
- `stop-git-auto.sh`: capture the daemon's PID from `git-auto-state.json`
  *before* calling `git-auto stop`, then verify death for real instead of
  trusting the tool's report. Because the daemon's own signal handler
  (`observer.stop()` + `observer.join()` + a state-file rewrite) takes a beat
  to finish, checking immediately would false-positive into an unnecessary
  escalation — so the check is a `sleep 0.5` polling loop, up to 3s, before
  concluding the signal didn't land. Only *then* escalate: `SIGTERM` (not
  maskable by the same job-control rule) with its own grace window, and
  `SIGKILL` as a last resort if even that doesn't land.
- Old daemons already running under the un-reset mask (started before this
  fix) still needed the escalation path — hence keeping both halves of the
  fix rather than relying on the trap reset alone.

**Gap, then closure (PR #10, `fd9ee5e`, merged 2026-07-03 — same day as this
entry):** PR #9 shipped with no dedicated regression test, breaking the
pattern every other fix in this repo follows (`test-clean-slate.sh`,
`test-handshake.sh`, `test-unpushed-status.sh`, `test-start-git-auto.sh`, …).
`test-stop-git-auto.sh` closed that gap, driving `stop-git-auto.sh` against
two real daemon shapes with actual signal delivery (not mocked):
1. A bare `cmd &` daemon — reproduces the pre-fix `SIG_IGN` masking, asserts
   the script detects survival and escalates to `SIGTERM`.
2. The fixed `( trap - INT QUIT; exec ... ) &` shape — asserts a clean exit
   on the first `SIGINT`, no escalation needed.

Same lesson as the commit-confirmation saga above, in miniature: a fix
without a regression test is a fix that can still regress silently — this one
just got caught before that happened, not after.

### Companion bug found while there: `wrapup` doesn't actually stop git-auto

While investigating the plugin, a second, related issue surfaced: the
`wrapup` skill/command *reports* stopping git-auto but the daemon keeps
running. Root cause, traced into `automate-git-commands/git-auto/cli.py`:

`git-auto stop` (without `--force`) shows an **interactive** `typer.confirm`
("Stop anyway?") whenever uncommitted changes or unpushed commits exist —
exactly the state a session is normally in at wrap-up time. In Claude's
non-interactive `Bash` tool, that prompt gets no stdin, defaults to "no," and
aborts the stop — but `stop-git-auto.sh`'s `&&...||` chain interprets the
non-zero exit as "wasn't running" and prints a *misleading success-shaped*
message. The daemon survives the session.

Fix (PR #8, `5a6c2aa`): pass `--force` to skip that confirm. Verified safe to
do blindly because:
- `--force` only bypasses the interactive dirty-state confirm — it does not
  change *which* daemon gets the stop signal
- targeting is fully scoped per-repo: the state file lives at
  `<repo_root>/.git/git-auto-state.json` (derived from
  `git rev-parse --show-toplevel`), so `--force` on one repo's stop cannot
  touch another project's daemon
- `wrapup.md` Steps 1–2 already surface the same uncommitted/pending warnings
  to the user *before* Step 3 runs `stop-git-auto.sh`, making the daemon's own
  confirm pure redundancy that can never be answered in this context anyway

---

## Recurring themes worth their own blog sections

1. **"No raw diffs in context" as a hard architectural constraint.** Every
   feature — `unpushed-status`, `get_stat_summary`, commit-message generation
   — is explicitly designed around "count + subjects + stat, never diff
   content." It shows up in code comments (`get_unpushed_status`: "Detect
   unpushed commits — count and subjects only, never diffs") and in skill
   instructions ("Do NOT read file contents or run git diff — use session
   context only"). A clean example of a design principle enforced
   consistently across a whole codebase rather than stated once and forgotten.

2. **Skill/command duplication as a structural liability.** Every skill in
   `skills/*/SKILL.md` has a near-identical twin in `commands/*.md`. This
   pattern was *chosen* deliberately (PR #3: "mirrors existing pattern"), and
   the team has caught itself drifting on it more than once — both the
   commit-confirmation regression and the deliberate "mirror Step 2.5 in both
   configure files... these two drift apart historically, kept in sync" note
   in PR #5/#6 point at the same structural cost. Worth a post on "when DRY
   doesn't apply to prompts" vs. "the hidden cost of copy-pasted instructions."

3. **Automated vs. interactive test coverage as a permanent split.** PR #4's
   test plan explicitly separates what `test-*.sh` scripts can verify from
   what needs a live `AskUserQuestion` session — and PR #1's checklist already
   showed the same split ("[x] script passes" vs. "[ ] live-test... in
   progress"). Anything gated on user choice (clean-slate triage, commit
   message confirm/edit/skip, `/configure` mode-change gate) is fundamentally
   harder to regression-test than anything gated on repo state.

4. **Bugs found by *using* the plugin, not by reading it.** PR #5/#6's three
   bugs and the `/doctor`-marketplace investigation were both triggered by
   live use in a *different* repo (`deutsche_bahn_delay_predictor_with_weather_info`)
   or by a `/doctor` run surfacing something nobody went looking for. The
   in-repo unit tests caught regressions on known scenarios; cross-repo,
   real-session use kept finding the scenarios nobody had thought to write a
   test for yet.

5. **Memory as institutional knowledge across sessions.** The
   `enabledPlugins`-key-mismatch root cause (three attempts, two failures, one
   eventual fix) was preserved in a project-memory file from an *entirely
   different* project directory (`project-planner`). Without that memory, this
   session would very likely have repeated the same failed "remove the key"
   experiment. A concrete argument for cross-session memory as more than a
   convenience — it's what stopped a regression from actually happening.

---

## PR / merge log (chronological)

| # | Title | Branch | State |
|---|---|---|---|
| 1 | feat: detect unpushed commits and offer clean-slate triage | `feat/clean-slate-unpushed-prompt` | merged |
| 2 | docs(readme): align table column widths | `fix/readme-table-formatting` | merged |
| 3 | feat(clean-slate): add slash command wrapping the clean-slate skill | `feat/clean-slate-command` | merged |
| 4 | docs(test-plan): add regression test plan | `docs/regression-test-plan` | open |
| 5 | fix(unit-commit): stale state sweep, daemon crash detection, catchup conflict warning | `fix/unit-commit-stale-state-and-config` | merged |
| 6 | fix(unit-commit): widen crash-detection window + regenerate stale unit-check.json mid-session | `fix/unit-commit-stale-state-and-config` | merged |
| 7 | fix(commit): remove confirmation prompt to match unit-commit's auto-run | `fix/commit-skill-no-confirmation-prompt` | merged |
| 8 | fix(wrapup): pass --force to git-auto stop to avoid silent abort | `fix/wrapup-stop-git-auto-confirm-block` | merged |
| 9 | Debug/fix wrapup command (reset SIGINT/SIGQUIT trap on launch; verify-and-escalate SIGTERM/SIGKILL on stop) | `debug/fix-wrapup-command` | merged |
| 10 | test(stop-git-auto): add regression coverage for SIGINT/SIG_IGN escalation | `debug/fix-wrapup-command` | merged |

(Note: PRs #7 and #8 were merged within minutes of opening — the repo has
auto-merge enabled, which is itself worth a line in a "how we work" post: CI +
review gates trusted enough to merge on green without a manual click. PR #9
merged 2026-06-08 with no test; the gap sat open for nearly a month until PR
#10 closed it on 2026-07-03 — see "The sleep bug" above.)
