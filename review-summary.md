# minimal-git-workflow — Delivery Readiness Review

Date: 2026-07-05
Scope: read-only review of the plugin's manifest, hooks, scripts, skill/command
pairs, and existing test/planning docs, to assess readiness for delivery and
further testing.

**Verdict: Not yet ready.** One real bug, two stale planning docs, and the
live/interactive test plan is mostly unexecuted.

---

## 1. Real bug — skill/command drift in `/configure` (blocking)

`skills/configure/SKILL.md` has a **Step 0** gate (added 2026-06-07, commit
`a0dab43`): before changing `git-auto-config.json`, check for unpushed
commits and route through `clean-slate` first. `commands/configure.md` never
received this step — it jumps straight to Step 1. Anyone invoking the slash
command `/minimal-git-workflow:configure` skips the safety gate entirely.

This is the same skill/command-drift failure class already documented twice
in `development-details.md` (the "commit-confirmation saga" and the "wrapup
silent-warn gap") — the project has been burned by this exact pattern before.

**Fix:** mirror `skills/configure/SKILL.md`'s Step 0 into `commands/configure.md`
verbatim (aside from the required frontmatter difference).

---

## 2. Stale doc — `docs/pathway-b-fix-plan.md` reads as unresolved but isn't

This doc (added 2026-07-05, PR #15) lists 2 "blocking" + 4 "gap" findings
against Pathway B (`unit-commit`). All 6 were checked against current code
and are **already fixed**, merged in PRs #16–#21 on this same branch:

| # | Finding | Fixed by |
|---|---|---|
| 1 | No secrets-scan guard before commit | `9b09a34` |
| 2 | Config-default documentation mismatch | `c4a0813` |
| 3 | Untested mid-session unit-check staleness sweep | `4ea06b4` |
| 4 | Asymmetric cleanup at session end (stop-git-auto) | `43a6b23` |
| 5 | `/status` doesn't surface unit-check state | `b45c2ac` |
| 6 | Skill/command message wording drift in unit-commit | `fdb1255` |

The doc's own "Verdict" line still says "Two findings are blocking." Anyone
reading only this file would wrongly conclude the plugin isn't ready.

**Fix:** mark the doc resolved (or delete it, since its content is now fully
captured by the merged PRs and `development-details.md`).

---

## 3. Stale doc — cross-repo test plan tests a removed design

`docs/superpowers/plans/2026-07-04-plugin-cross-repo-test-plan.md` Task 8
Step 2b still instructs testers to verify "Write a catchup note" as a
`/wrapup` option. That option was replaced the same day with "Commit as WIP
(no push)" — confirmed live in `skills/wrapup/SKILL.md` and
`commands/wrapup.md` (both already updated and in sync with each other).
Following this test plan as written would validate behavior that no longer
exists.

**Fix:** update Task 8 Step 2b to test the WIP-commit option instead.

---

## 4. Live/interactive testing is mostly unexecuted

Of the 12-task cross-repo smoke-test plan (`docs/superpowers/plans/2026-07-04-plugin-cross-repo-test-plan.md`),
only Task 1 (fixture setup) is fully done and Task 2 (`/configure`) is
partial. Tasks 3–12 are all "Not started":

- SessionStart hook (`start-git-auto.sh`) — all code paths
- `/clean-slate` — push / squash / leave-as-is / push failure
- Pathway A — threshold-based commit (`/commit`)
- Pathway B — logical-unit commit (`/unit-commit`)
- `/status`
- `/wrapup` (all three branches)
- `stop-git-auto.sh` signal-handling edge case
- Cross-repo isolation check
- Uninstall path
- Cleanup

The 13 automated `test-*.sh` scripts look reasonably thorough for unit-level
coverage, but were not executed as part of this review (read-only scope), so
current pass/fail state is unconfirmed. The plugin's own history
(`development-details.md`, "Bugs found by *using* the plugin, not by reading
it") shows that live/interactive flows are consistently where real bugs
surface — this pass hasn't happened yet.

---

## 5. Minor, non-blocking

- `.claude/sessions/INDEX.md` and `session-specific-instructions.md` had
  uncommitted changes at review time — harness/session bookkeeping, unrelated
  to plugin code, but worth clearing before calling the branch clean.
- `install.sh` / `uninstall.sh` are solid — idempotent, guard against
  overwriting real directories, correct symlink handling. No issues found.

---

## What's strong

The manifest, hooks wiring, `handshake.py`, `check-unit-complete.sh`,
`start-git-auto.sh`, and `stop-git-auto.sh` are unusually well-hardened —
every race condition and false-success mode checked already has a documented
fix and (mostly) a regression test. The `wrapup` / `commit` / `unit-commit` /
`clean-slate` / `status` skill↔command pairs are byte-identical except for
the one `/configure` gap in finding #1.
