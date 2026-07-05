# minimal-git-workflow

Claude Code plugin. Automates git commits using Claude's session context — no raw diffs read into context.

## Quick Start

New to this plugin? Follow these steps in order:

1. **Clone and install.**

   ```bash
   git clone https://github.com/ZahraAnam/minimal-git-workflow
   cd minimal-git-workflow
   ./install.sh
   ```

   This installs `git-auto` (if not already on `PATH`) and symlinks the plugin into `~/.claude/plugins/minimal-git-workflow/`.

2. **Restart Claude Code** so it picks up the plugin.

3. **Start a session — clean-slate runs automatically.** On `SessionStart`, `/minimal-git-workflow:clean-slate` checks for unpushed commits left over from a previous session and lets you choose to push, squash, or leave them as-is before git-auto starts watching. You can also run it manually anytime:

   ```
   /minimal-git-workflow:clean-slate
   ```

4. **Configure the plugin for your project.** Inside a Claude Code session, run:

   ```
   /minimal-git-workflow:configure
   ```

   This walks you through each setting (defaults shown for each) and writes `git-auto-config.json` in your project root (see the [Configure](#configure) section below for what each setting does).

5. **Work normally.** The plugin runs a background daemon and watches your edits — commits happen automatically via one of two pathways (threshold-based or logical-unit-based). No extra action needed while you code.

6. **End every session with wrapup.** Run:

   ```
   /minimal-git-workflow:wrapup
   ```

   This flushes any pending commit and stops the daemon cleanly. Skipping this step leaves the daemon running orphaned in the background.

See [How it works](#how-it-works) and [Usage](#usage) below for the full details on each pathway and command.

## How it works

Two commit pathways run in parallel — whichever fires first commits; the other finds nothing to commit:

**Pathway A — threshold-based (git-auto)**
File edits accumulate → `files_threshold` reached → `git-auto` commits fully autonomously, generating its own message via its LLM agent (Mistral by default). Runs independently of Claude — no handshake, no session context. See [plugin-working.md](plugin-working.md) for the verified current behavior.

**Pathway B — logical-unit-based (unit-commit)**
After each Edit/Write tool use → `check-unit-complete.sh` fires → if the working tree is dirty, `unit-check.json` is written → Claude evaluates whether a complete logical unit is done → if yes, Claude generates a message from session context and commits directly.

## Requirements

- Claude Code
- [git-auto](https://github.com/ZahraAnam/automate-git-commands) on `PATH`
- `python3` and `jq` (used by the plugin's hook scripts)

## Install

**Automated:**

```bash
git clone https://github.com/ZahraAnam/minimal-git-workflow
cd minimal-git-workflow
./install.sh
```

This installs `git-auto` (cloning + `pip install -e` if not already on `PATH`) and symlinks the plugin into `~/.claude/plugins/minimal-git-workflow/`. Restart Claude Code afterward to pick it up.

**Manual:**

```bash
# git-auto from source
cd automate-git-commands
pip install -e .

# symlink the plugin
ln -s ~/workdir/repositories/minimal-git-workflow ~/.claude/plugins/minimal-git-workflow
```

Claude Code picks up the plugin automatically on next session start.

**Uninstall:**

```bash
./uninstall.sh
```

Removes the plugin symlink only — `git-auto` itself is a shared tool and is left installed (`pip uninstall git-auto` manually if you no longer need it).

## Configure

Run `/minimal-git-workflow:configure` inside a Claude Code session to create `git-auto-config.json` in your project root.

Key settings:

| Setting            | Default              | Description                                                                     |
| ------------------ | -------------------- | ------------------------------------------------------------------------------- |
| `files_threshold`  | 3 (15 if `unit_commit: true`) | Files changed before git-auto auto-commits                            |
| `push_threshold`   | 0                    | Unpushed commits before auto-push (0 = disabled)                                |
| `squash_threshold` | 5                    | Squash unpushed commits into one at this count (0 = disabled, min 4 if enabled) |
| `cooldown`         | 5.0                  | Seconds after a commit before another can fire                                  |
| `unit_commit`      | true                 | Enable logical-unit commit pathway (Pathway B)                                  |
| `catchup`          | false                | Auto-commit whatever is dirty when git-auto starts                              |
| `model`            | mistral-small-latest | Fallback model for git-auto's own commit messages                               |

When `unit_commit: true`, `/configure` suggests `files_threshold: 15` and
enforces a minimum of 10. High enough that git-auto's own autonomous commits
(Pathway A) don't race Claude's logical-unit commits (Pathway B) mid-unit, but
low enough to still catch changes made outside Claude within a session —
unlike a very high sentinel (e.g. 999), which would effectively disable that
safety net.

Also avoid combining `catchup: true` with `unit_commit: true` — catchup bulk-commits
all pending changes (with a generic Mistral-generated message) on startup, before
the unit-commit pathway gets a chance to evaluate and bundle a logical unit. Set
`catchup: false` when `unit_commit: true` is enabled.

## Usage

### Background process & wrapup

Regardless of `unit_commit`, `git-auto` runs as a background daemon for the life of the session (started by the `SessionStart` hook, one process per project, tracked by PID in `.git/git-auto-state.json`). With `unit_commit: true`, that daemon isn't doing the committing itself in Pathway B — it just keeps running while Claude coordinates commits through the `unit-check.json` handshake and the `watch-pending.sh` monitor loop.

**Always end the session with `/minimal-git-workflow:wrapup`.** It flushes any pending commit, then stops the daemon cleanly. Skipping it leaves the daemon running orphaned in the background — it won't stop on its own — and can leave stale handshake files for the next session to sweep up.

A session's lifecycle looks like this:

```
Session opens
    │
    ▼
SessionStart hook → start-git-auto.sh
                        ├── resolves any stale handshake files from a previous session
                        ├── starts git-auto (background)
                        └── Claude starts watching for pending-commit / unit-check notifications
    │
    │   ┌──────────────────────────────────────────────┐
    ▼   ▼ (runs in parallel)                            │
git-auto watches the filesystem          PostToolUse hook (Edit/Write)
    │                                            │
files_threshold reached                  check-unit-complete.sh
    │                                            │
git-auto → its own LLM → git commit      unit-check.json written → Claude notified
                                                 │
                                          /minimal-git-workflow:unit-commit → evaluate
                                                 │
                                          complete unit? → git add . && git commit
    │
    ▼ (end of session)
/minimal-git-workflow:wrapup → commit pending changes → stop git-auto → confirm clean state
```

Commands/skills available inside a Claude Code session:

| Command                             | Trigger                        | Description                                                                                                                                               |
| ----------------------------------- | ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/minimal-git-workflow:configure`   | Manual                         | Create/update `git-auto-config.json`                                                                                                                      |
| `/minimal-git-workflow:clean-slate` | Auto (SessionStart) or manual  | Detect unpushed commits and choose to push, squash, or leave as-is before continuing                                                                      |
| `/minimal-git-workflow:unit-commit` | Auto (watch-pending) or manual | Evaluate whether uncommitted changes form a complete logical unit; commit if so                                                                           |
| `/minimal-git-workflow:commit`      | Manual only                    | Generate a commit message from a simulated pending-commit handshake (not driven by the real git-auto daemon — see [plugin-working.md](plugin-working.md)) |
| `/minimal-git-workflow:status`      | Manual                         | Show git-auto process state and handshake file status                                                                                                     |
| `/minimal-git-workflow:wrapup`      | Manual                         | Commit any pending changes and stop git-auto cleanly                                                                                                      |

## Known Issues / Planned Fixes

See [plugin-enhancements-plan.md](https://github.com/ZahraAnam/project_planner/blob/main/plugin-enhancements-plan.md) for full problem analysis and fix roadmap.

## License

MIT
