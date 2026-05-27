---
name: configure
description: Configure git-auto settings for this project. Creates or updates git-auto-config.json with thresholds, model, and push settings.
---

Help the user create or update their `git-auto-config.json` file in the repo root.

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
   "Which model should git-auto use when falling back to LLM? (open-mistral-nemo is free tier)"
   Options: open-mistral-nemo, mistral-small-latest, gpt-4o, claude-3-5-haiku-latest

5. **claude_handshake** (default: true)
   "Enable Claude-generated commit messages via handshake? When true, git-auto writes a pending-commit.json on threshold, waits for Claude to write commit-message.txt, then falls back to the LLM model on timeout. Set false to use LLM only."

6. **claude_timeout** (default: 30)
   "Seconds git-auto waits for Claude to write commit-message.txt before falling back to LLM (min 5)."

7. **catchup** (default: false)
   "Commit all pending changes immediately when git-auto starts? (true/false)"

8. **cooldown** (default: 3.0)
   "Seconds to wait after a commit before allowing another. Keep low for frequent commits."

9. **unit_commit** (default: false)
   "Enable logical-unit-based commits? When true, Claude evaluates after each file edit whether a complete logical unit of work has been finished and commits if so — independent of the files_threshold. (true/false)"

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
    "model": "<value>",
    "claude_handshake": <value>,
    "claude_timeout": <value>
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
