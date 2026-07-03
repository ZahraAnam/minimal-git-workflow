## Summary
Consolidated review of all session summaries in this repo (2026-06-07 to 2026-06-08). Only one session produced a real `.summary.md` — `fix-race-condition-bug` (85%, PR #5). Rest are empty session-start stubs (no actual summary written): fix-race-condition-bug (multiple reruns), add-command-for-clean-slate-skill, analyse-changes-needed-for-git-auto (x2), analyse-plugin, check-local-settings-impact.

## Key Decisions / Learnings (from fix-race-condition-bug)
- Stale-lock sweep uses presence-at-SessionStart, not TTL: user said "catchup and updates should always be possible" — time-based locks risk blocking legit work; presence check is deterministic
- Never blind-delete state files: user caught a silent `rm` of `unit-check.json` that would've lost uncommitted-work context — now surfaced via STALE_UNIT_CHECK marker before delete
- Prefer generic failure detection over special-casing: PID-liveness + log-tail catches ANY daemon crash, vs narrow per-config-key validation
- Docs (`skills/configure/SKILL.md` + `commands/configure.md`) drift apart historically — mirror changes deliberately when touching one

## Process Learning (Went Wrong, 85% session)
User's own note: "Complicated and not intuitive to follow — user had to carefully find issues and provide guidance." → for race-condition/state-bug work, front-load smaller, more guided steps; don't let user carry the debugging.

## Carry Forward (verified 2026-06-08)
- PR #4 (regression test plan) — still OPEN, awaiting merge: https://github.com/ZahraAnam/minimal-git-workflow/pull/4
- PR #5 (3-bug fix) — MERGED 2026-06-08, no action needed: https://github.com/ZahraAnam/minimal-git-workflow/pull/5

## Note
Most sessions in this folder never wrote summaries (session ended without triggering the protocol, or got interrupted). Consider this when relying on `.claude/sessions/` history going forward.
