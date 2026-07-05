# Condition files_threshold when unit_commit is true — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent Pathway A (git-auto's autonomous `files_threshold` commits) from racing Pathway B (`unit_commit`'s logical-unit commits), while still catching edits made outside Claude's own tool calls, and make `unit_commit` default to `true` everywhere it's read or asked.

**Architecture:** No new components. Three existing surfaces change: (1) the interactive `/configure` prompt order/defaults in `skills/configure/SKILL.md` and `commands/configure.md`, (2) the code-level fallback in `scripts/check-unit-complete.sh`, (3) the docs that currently document a stale `999` recommendation (`README.md`, `plugin-working.md`).

**Tech Stack:** Bash, Python 3 (inline via `python3 -c`), Markdown-driven Claude skills.

## Global Constraints

- `unit_commit` defaults to `true` (interactive prompt default AND the code-level fallback when the key is missing from a config file). Explicit `unit_commit: false` in a config must still be respected.
- When `unit_commit: true`, `files_threshold` suggested/default is **15**, with a hard floor of **10** — reject/re-prompt below 10, mirroring the existing `squash_threshold` "min 4 if enabled" rule.
- When `unit_commit: false`, `files_threshold` behavior is unchanged (default 3, no floor).
- `skills/configure/SKILL.md` and `commands/configure.md` must stay mirrored — this repo's history shows these two drifting apart when only one is edited.
- No changes to `push_threshold`, `squash_threshold`, or git-auto's own unrelated defaults.

---

### Task 1: Default `unit_commit` to `true` at the code level, with a regression test

**Files:**
- Modify: `scripts/check-unit-complete.sh:46`
- Create: `scripts/test-unit-commit-default-fallback.sh`

**Interfaces:**
- Consumes: nothing new — exercises the existing `check-unit-complete.sh` hook via stdin JSON (`{"tool_name": "...", "tool_input": {"file_path": "..."}}`), same as `scripts/test-cross-repo-unit-check.sh`.
- Produces: nothing consumed by later tasks — this task is self-contained.

- [ ] **Step 1: Write the failing test**

Create `scripts/test-unit-commit-default-fallback.sh`:

```bash
#!/usr/bin/env bash
# test-unit-commit-default-fallback.sh
# Regression test: a git-auto-config.json that omits the `unit_commit` key
# entirely must be treated as unit_commit: true (Pathway B enabled) — not
# false. Also guards that an explicit `unit_commit: false` is still honored.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/check-unit-complete.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

setup_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  echo "init" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "init"
}

run_hook() {
  local repo="$1"
  local edited_file="$repo/src.py"
  echo "print('hello')" > "$edited_file"
  local hook_input
  hook_input=$(python3 -c "
import json
print(json.dumps({'tool_name': 'Write', 'tool_input': {'file_path': '$edited_file'}}))
")
  (cd "$repo" && echo "$hook_input" | bash "$HOOK") || true
}

PASS=true

# --- Case 1: unit_commit key omitted entirely -> must behave as true ---
REPO_MISSING="$WORKDIR/repo-missing-key"
setup_repo "$REPO_MISSING"
cat > "$REPO_MISSING/git-auto-config.json" <<'EOF'
{"start": {"files_threshold": 15}}
EOF
git -C "$REPO_MISSING" add git-auto-config.json
git -C "$REPO_MISSING" commit -q -m "add config"

run_hook "$REPO_MISSING"

echo "=== Case 1: unit_commit key missing entirely ==="
if [ -f "$REPO_MISSING/.git/unit-check.json" ]; then
  echo "PASS: missing unit_commit key treated as enabled (unit-check.json written)"
else
  echo "FAIL: missing unit_commit key was NOT treated as enabled"
  PASS=false
fi
echo ""

# --- Case 2: unit_commit explicitly false -> must stay disabled ---
REPO_FALSE="$WORKDIR/repo-explicit-false"
setup_repo "$REPO_FALSE"
cat > "$REPO_FALSE/git-auto-config.json" <<'EOF'
{"start": {"files_threshold": 3}, "unit_commit": false}
EOF
git -C "$REPO_FALSE" add git-auto-config.json
git -C "$REPO_FALSE" commit -q -m "add config"

run_hook "$REPO_FALSE"

echo "=== Case 2: unit_commit explicitly false ==="
if [ -f "$REPO_FALSE/.git/unit-check.json" ]; then
  echo "FAIL: explicit unit_commit:false was NOT respected (unit-check.json written anyway)"
  PASS=false
else
  echo "PASS: explicit unit_commit:false still disables Pathway B"
fi
echo ""

if $PASS; then
  echo "=== ALL CHECKS PASSED ==="
  exit 0
else
  echo "=== FAILURES DETECTED ==="
  exit 1
fi
```

- [ ] **Step 2: Make it executable and run it to verify Case 1 fails**

```bash
chmod +x scripts/test-unit-commit-default-fallback.sh
bash scripts/test-unit-commit-default-fallback.sh
```

Expected: Case 1 prints `FAIL: missing unit_commit key was NOT treated as enabled`, Case 2 passes, overall script exits 1 with `=== FAILURES DETECTED ===`. This confirms the test correctly detects today's `False` fallback.

- [ ] **Step 3: Implement the minimal fix**

In `scripts/check-unit-complete.sh`, change line 46:

```diff
     print('true' if c.get('unit_commit', False) else 'false')
+    print('true' if c.get('unit_commit', True) else 'false')
```

(Only the literal `False` → `True` changes; nothing else on the line.)

- [ ] **Step 4: Run the test again to verify both cases pass**

```bash
bash scripts/test-unit-commit-default-fallback.sh
```

Expected: both cases print `PASS`, script exits 0 with `=== ALL CHECKS PASSED ===`.

- [ ] **Step 5: Run the existing test suite to confirm no regressions**

```bash
bash scripts/test-cross-repo-unit-check.sh
bash scripts/test-unit-check-mid-session-staleness.sh
bash scripts/test-unit-commit-secrets-guard.sh
```

Expected: all three still print `=== ALL CHECKS PASSED ===` (they all set `unit_commit` explicitly in their fixtures, so the fallback change doesn't affect them).

- [ ] **Step 6: Commit**

```bash
git add scripts/check-unit-complete.sh scripts/test-unit-commit-default-fallback.sh
git commit -m "fix(unit-commit): default missing unit_commit key to true

A git-auto-config.json that omits unit_commit entirely now behaves as
enabled, matching the new /configure interactive default. Explicit
unit_commit: false is still respected."
```

---

### Task 2: Reorder `/configure` prompts — `unit_commit` first, conditioned `files_threshold`

**Files:**
- Modify: `skills/configure/SKILL.md:37-61` (Step 2 body)
- Modify: `commands/configure.md:36-60` (Step 2 body — mirrored twin)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Replace Step 2 in `skills/configure/SKILL.md`**

Old text (lines 37-61):

```markdown
## Step 2 — Ask for configuration values

Ask the user for each setting. Show the default and a brief explanation:

1. **files_threshold** (default: 3)
   "How many distinct files changed before auto-commit? Lower = more frequent commits."

2. **push_threshold** (default: 0)
   "How many commits before auto-push? Set 0 to disable auto-push."

3. **squash_threshold** (default: 5)
   "Squash unpushed commits into one when count reaches N (0 = disabled, min 4 if enabled)."

4. **model** (default: mistral-small-latest)
   "Which model for fallback commit messages?"
   Options: mistral-small-latest, open-mistral-nemo, gpt-4o, claude-3-5-haiku-latest

5. **catchup** (default: false)
   "Commit all pending changes immediately when git-auto starts? (true/false)"

6. **cooldown** (default: 5.0)
   "Seconds to wait after a commit before allowing another. Keep low for frequent commits."

7. **unit_commit** (default: false)
   "Enable logical-unit-based commits? When true, Claude evaluates after each file edit whether a complete logical unit of work has been finished and commits if so — independent of the files_threshold. (true/false)"
```

New text:

```markdown
## Step 2 — Ask for configuration values

Ask the user for each setting. Show the default and a brief explanation:

1. **unit_commit** (default: true)
   "Enable logical-unit-based commits? When true, Claude evaluates after each file edit whether a complete logical unit of work has been finished and commits if so — independent of the files_threshold. (true/false)"

2. **files_threshold** — depends on the `unit_commit` answer just given:
   - If `unit_commit: true` (default: 15, minimum 10):
     "How many distinct files changed before auto-commit? Since unit_commit is on, keep this high enough that git-auto's own autonomous commits (Pathway A) don't race Claude's logical-unit commits (Pathway B) mid-unit — but still low enough to catch changes made outside Claude within a session. Default 15; minimum 10."
     If the user answers below 10, say: "files_threshold below 10 risks Pathway A firing mid-unit and racing Pathway B's commit — please pick 10 or higher." and re-ask until they give a value of 10 or more.
   - If `unit_commit: false` (default: 3):
     "How many distinct files changed before auto-commit? Lower = more frequent commits."

3. **push_threshold** (default: 0)
   "How many commits before auto-push? Set 0 to disable auto-push."

4. **squash_threshold** (default: 5)
   "Squash unpushed commits into one when count reaches N (0 = disabled, min 4 if enabled)."

5. **model** (default: mistral-small-latest)
   "Which model for fallback commit messages?"
   Options: mistral-small-latest, open-mistral-nemo, gpt-4o, claude-3-5-haiku-latest

6. **catchup** (default: false)
   "Commit all pending changes immediately when git-auto starts? (true/false)"

7. **cooldown** (default: 5.0)
   "Seconds to wait after a commit before allowing another. Keep low for frequent commits."
```

Use the Edit tool with the old text above as `old_string` and the new text as `new_string` against `skills/configure/SKILL.md`.

- [ ] **Step 2: Apply the identical replacement to `commands/configure.md`**

`commands/configure.md`'s Step 2 body (lines 36-60) is byte-for-byte identical to the old text in Step 1 above (the command file just lacks the `name:`/frontmatter lines the skill file has). Apply the exact same old_string → new_string replacement to `commands/configure.md`.

- [ ] **Step 3: Verify the two files still mirror each other**

```bash
diff <(sed -n '/## Step 2/,/## Step 3/p' skills/configure/SKILL.md) \
     <(sed -n '/## Step 2/,/## Step 3/p' commands/configure.md)
```

Expected: no output (identical Step 2 blocks in both files).

- [ ] **Step 4: Commit**

```bash
git add skills/configure/SKILL.md commands/configure.md
git commit -m "feat(configure): ask unit_commit first, default true, condition files_threshold

Reorders /configure's Step 2 so unit_commit is collected before
files_threshold, defaults unit_commit to true, and when it's true
suggests files_threshold: 15 with a floor of 10 so Pathway A (git-auto)
can't race Pathway B (unit-commit) mid-unit while still catching edits
made outside Claude."
```

---

### Task 3: Reconcile docs that recommend the stale `999` value

**Files:**
- Modify: `README.md:104-117`
- Modify: `plugin-working.md:118-135`

**Interfaces:**
- Consumes: nothing from Tasks 1-2 (docs only).
- Produces: nothing.

- [ ] **Step 1: Update `README.md`'s config table and race-avoidance note**

Old text (lines 102-117):

```markdown
| Setting            | Default              | Description                                                                     |
| ------------------ | -------------------- | ------------------------------------------------------------------------------- |
| `files_threshold`  | 3                    | Files changed before git-auto auto-commits                                      |
| `push_threshold`   | 0                    | Unpushed commits before auto-push (0 = disabled)                                |
| `squash_threshold` | 5                    | Squash unpushed commits into one at this count (0 = disabled, min 4 if enabled) |
| `cooldown`         | 5.0                  | Seconds after a commit before another can fire                                  |
| `unit_commit`      | false                | Enable logical-unit commit pathway (Pathway B)                                  |
| `catchup`          | false                | Auto-commit whatever is dirty when git-auto starts                              |
| `model`            | mistral-small-latest | Fallback model for git-auto's own commit messages                               |

When `unit_commit: true`, set `files_threshold` high (e.g. 999) to avoid race conditions between the two pathways.

Also avoid combining `catchup: true` with `unit_commit: true` — catchup bulk-commits
all pending changes (with a generic Mistral-generated message) on startup, before
the unit-commit pathway gets a chance to evaluate and bundle a logical unit. Set
`catchup: false` when `unit_commit: true` is enabled.
```

New text:

```markdown
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
```

Use the Edit tool with the old text as `old_string` and the new text as `new_string` against `README.md`.

- [ ] **Step 2: Update `plugin-working.md`'s example config and inline comment**

Old text (lines 118-135):

```markdown
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
```

New text:

```markdown
```json
{
  "start": {
    "files_threshold": 15,
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
- `unit_commit` is a plugin-only key read by `check-unit-complete.sh`. git-auto ignores it. A missing `unit_commit` key is treated as `true`.
- `files_threshold` is set to 15 here specifically because `unit_commit: true` — see README's "avoid race conditions between the two pathways" note. `/configure` enforces a minimum of 10 in this mode; git-auto's own unconditioned default is 3.
- `start.*` defaults (from `git-auto/config.py`'s `StartConfig`, the actual source git-auto reads): `files_threshold: 3`, `push_threshold: 0`, `squash_threshold: 5`, `cooldown: 5.0`, `model: "mistral-small-latest"`, `catchup: false`.
```

Use the Edit tool with the old text as `old_string` and the new text as `new_string` against `plugin-working.md`.

- [ ] **Step 3: Grep to confirm no stale `999` references remain**

```bash
grep -rn "999" README.md plugin-working.md
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add README.md plugin-working.md
git commit -m "docs: replace stale files_threshold: 999 guidance with 15/10 floor

README.md and plugin-working.md recommended an unconditioned 999
sentinel for files_threshold when unit_commit is true, which effectively
disabled Pathway A as a safety net for edits made outside Claude. Update
both to the new /configure-enforced default (15) and floor (10)."
```

---

## Post-plan verification

- [ ] Run the full existing test suite once more to confirm nothing regressed:

```bash
for t in scripts/test-*.sh; do
  echo "=== $t ==="
  bash "$t" || echo "FAILED: $t"
done
```

Expected: every script prints its own `ALL CHECKS PASSED` (or equivalent success) line, none print `FAILED:`.
