---
name: configure
description: Configure git-auto settings for this project. Creates or updates git-auto-config.json with thresholds, model, and push settings.
---

Help the user create or update their `git-auto-config.json` file in the repo root.

## Step 0 — Ensure a clean slate before changing modes

Changing `git-auto-config.json` (e.g. toggling `unit_commit`, switching
`files_threshold`/`threshold` modes) changes how commits get triggered going
forward. Before applying any change, check for unpushed commits so the new
mode starts from a known-clean state:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" unpushed-status
```

If `count > 0`, run `/minimal-git-workflow:clean-slate` and let the user choose
push / squash / leave-as-is before continuing to Step 1. If `count == 0`,
proceed directly to Step 1.

## Step 1 — Check existing config

Run:
```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/handshake.py" status
```

Also check if a config file already exists:
```bash
ls git-auto-config.{json,toml,yaml,yml} 2>/dev/null || echo "No config found"
```

If a config exists, show the current values and ask: "Would you like to update it or keep it as-is?"

## Step 2 — Ask for configuration values

Ask the user for each setting. Show the default and a brief explanation:

1. **files_threshold** (default: 2)
   "How many distinct files changed before auto-commit? Lower = more frequent commits."

2. **push_threshold** (default: 4)
   "How many commits before auto-push? Set 0 to disable auto-push."

3. **squash_threshold** (default: 0)
   "Squash unpushed commits into one when count reaches N (0 = disabled, min 4 if enabled)."

4. **model** (default: open-mistral-nemo)
   "Which model for fallback commit messages? (open-mistral-nemo is free tier)"
   Options: open-mistral-nemo, mistral-small-latest, gpt-4o, claude-3-5-haiku-latest

5. **catchup** (default: false)
   "Commit all pending changes immediately when git-auto starts? (true/false)"

6. **cooldown** (default: 3.0)
   "Seconds to wait after a commit before allowing another. Keep low for frequent commits."

7. **unit_commit** (default: false)
   "Enable logical-unit-based commits? When true, Claude evaluates after each file edit whether a complete logical unit of work has been finished and commits if so — independent of the files_threshold. (true/false)"

## Step 2.5 — Warn about catchup + unit_commit conflict

If the user answered `catchup: true` AND `unit_commit: true`, warn them before
writing the config:

"Heads up: `catchup` bulk-commits all pending changes immediately on startup
(with a generic Mistral-generated message), before the unit-commit pathway
ever gets a chance to evaluate and bundle a logical unit. Combining both
means catchup will likely race ahead and commit your in-flight work first.
Recommend setting `catchup: false` when `unit_commit: true` is enabled.
Keep both as you specified, or set `catchup: false`?"

Use their answer for the value written in Step 3.

## Step 3 — Write config file

Write the values to `git-auto-config.json` in the repo root:

```json
{
  "start": {
    "files_threshold": <value>,
    "push_threshold": <value>,
    "squash_threshold": <value>,
    "catchup": <value>,
    "cooldown": <value>,
    "model": "<value>"
  },
  "unit_commit": <value>
}
```

Confirm to the user: "Config written to git-auto-config.json. git-auto will pick this up automatically on next start."

## Step 4 — Offer to restart

If git-auto is already running, ask: "git-auto is currently running. Restart it with the new config? (yes/no)"

If yes, run:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/stop-git-auto.sh"
sleep 2
"${CLAUDE_PLUGIN_ROOT}/scripts/start-git-auto.sh"
```
