# minimal-git-workflow

Claude Code plugin. Automates git commits using Claude's session context — no raw diffs read into context.

## How it works

Two commit pathways run in parallel:

**Pathway A — threshold-based (git-auto)**
File edits accumulate → `files_threshold` reached → git-auto commits fully autonomously, generating its own message via its LLM agent (Mistral by default). No Claude handshake — see [plugin-working.md](plugin-working.md) for the verified current behavior.

**Pathway B — logical-unit-based (unit-commit)**
After each Edit/Write tool use → `check-unit-complete.sh` fires → if working tree dirty, `unit-check.json` written → Claude evaluates whether a complete logical unit is done → if yes, commits directly.

## Dependencies

Requires [git-auto](https://github.com/ZahraAnam/automate-git-commands) installed and available on `PATH`.

```bash
# Install git-auto from source
cd automate-git-commands
pip install -e .
```

## Install

Copy or symlink this directory to `~/.claude/plugins/minimal-git-workflow/`:

```bash
ln -s ~/workdir/repositories/minimal-git-workflow ~/.claude/plugins/minimal-git-workflow
```

Claude Code picks it up automatically on next session start.

## Configure

Run `/minimal-git-workflow:configure` inside a Claude Code session to create `git-auto-config.json` in your project root.

Key settings:

| Setting           | Default           | Description                                      |
| ----------------- | ----------------- | ------------------------------------------------ |
| `files_threshold` | 10                | Files changed before git-auto auto-commits       |
| `push_threshold`  | 0                 | Unpushed commits before auto-push (0 = disabled) |
| `unit_commit`     | false             | Enable logical-unit commit pathway               |
| `model`           | open-mistral-nemo | Fallback model for commit messages               |

When `unit_commit: true`, set `files_threshold` high (e.g. 999) to avoid race conditions between the two pathways.

Also avoid combining `catchup: true` with `unit_commit: true` — catchup bulk-commits
all pending changes (with a generic Mistral-generated message) on startup, before
the unit-commit pathway gets a chance to evaluate and bundle a logical unit. Set
`catchup: false` when `unit_commit: true` is enabled.

## Skills

| Skill         | Trigger                        | Description                                    |
| ------------- | ------------------------------ | ---------------------------------------------- |
| `unit-commit` | Auto (watch-pending) or manual | Evaluate + commit logical unit                 |
| `commit`      | Manual only                    | Generate message from a simulated pending-commit handshake (not driven by the real git-auto daemon — see [plugin-working.md](plugin-working.md)) |
| `configure`   | Manual                         | Create/update git-auto-config.json             |
| `status`      | Manual                         | Show git-auto state + handshake status         |
| `wrapup`      | Manual                         | Commit pending, stop git-auto cleanly          |

## Known Issues / Planned Fixes

See [plugin-enhancements-plan.md](https://github.com/ZahraAnam/project_planner/blob/main/plugin-enhancements-plan.md) for full problem analysis and fix roadmap.

## License

MIT
