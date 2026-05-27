# Graph Report - .  (2026-05-27)

## Corpus Check
- Corpus is ~6,242 words - fits in a single context window. You may not need a graph.

## Summary
- 86 nodes · 122 edges · 21 communities (20 shown, 1 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 8 edges (avg confidence: 0.89)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_Plugin Metadata|Plugin Metadata]]
- [[_COMMUNITY_Handshake Unit Check|Handshake Unit Check]]
- [[_COMMUNITY_Pending Commit Protocol|Pending Commit Protocol]]
- [[_COMMUNITY_Git Utilities|Git Utilities]]
- [[_COMMUNITY_Commit & Wrapup Skills|Commit & Wrapup Skills]]
- [[_COMMUNITY_Unit Commit Flow|Unit Commit Flow]]
- [[_COMMUNITY_Threshold Commit Handshake|Threshold Commit Handshake]]
- [[_COMMUNITY_Plugin Config & Protocol|Plugin Config & Protocol]]
- [[_COMMUNITY_Configure & Session Start|Configure & Session Start]]
- [[_COMMUNITY_Commit Message Writing|Commit Message Writing]]
- [[_COMMUNITY_Claude Code Hooks|Claude Code Hooks]]
- [[_COMMUNITY_Plugin Overview & Docs|Plugin Overview & Docs]]
- [[_COMMUNITY_Session Management|Session Management]]
- [[_COMMUNITY_Status Skill|Status Skill]]

## God Nodes (most connected - your core abstractions)
1. `CLAUDE.md — Plugin Codebase Guide` - 14 edges
2. `scripts/handshake.py` - 9 edges
3. `Skill: unit-commit` - 7 edges
4. `Pathway A — Threshold-Based Commit` - 7 edges
5. `write_unit_check()` - 6 edges
6. `Pathway B — Logical-Unit Commit` - 6 edges
7. `scripts/watch-pending.sh` - 6 edges
8. `git-auto CLI Tool` - 6 edges
9. `get_git_dir()` - 5 edges
10. `pending_commit_path()` - 5 edges

## Surprising Connections (you probably didn't know these)
- `Command: configure` --semantically_similar_to--> `Skill: configure`  [INFERRED] [semantically similar]
  commands/configure.md → skills/configure/SKILL.md
- `Command: unit-commit` --semantically_similar_to--> `Skill: unit-commit`  [INFERRED] [semantically similar]
  commands/unit-commit.md → skills/unit-commit/SKILL.md
- `Command: commit` --semantically_similar_to--> `Skill: commit`  [INFERRED] [semantically similar]
  commands/commit.md → skills/commit/SKILL.md
- `Command: status` --semantically_similar_to--> `Skill: status`  [INFERRED] [semantically similar]
  commands/status.md → skills/status/SKILL.md
- `Command: wrapup` --semantically_similar_to--> `Skill: wrapup`  [INFERRED] [semantically similar]
  commands/wrapup.md → skills/wrapup/SKILL.md

## Hyperedges (group relationships)
- **Threshold-Based Commit Flow (Pathway A)** — git_auto_tool, pending_commit_json, watch_pending_sh, skills_skill_commit, handshake_py, commit_message_txt [EXTRACTED 1.00]
- **Logical-Unit Commit Flow (Pathway B)** — check_unit_complete_sh, unit_check_json, watch_pending_sh, skills_skill_unit_commit, handshake_py [EXTRACTED 1.00]
- **Skill-Command Pair Pattern** — skills_skill_commit, commands_commit, skills_skill_unit_commit, commands_unit_commit, skills_skill_configure, commands_configure [INFERRED 0.85]

## Communities (21 total, 1 thin omitted)

### Community 0 - "Plugin Metadata"
Cohesion: 0.17
Nodes (11): author, email, name, url, description, homepage, keywords, license (+3 more)

### Community 1 - "Handshake Unit Check"
Cohesion: 0.39
Nodes (7): clear_unit_check(), get_git_dir(), get_repo_root(), Read unit-check.json. Returns None if not found., Remove unit-check.json after Claude has responded., read_unit_check(), unit_check_path()

### Community 2 - "Pending Commit Protocol"
Cohesion: 0.29
Nodes (7): clear_handshake_files(), pending_commit_path(), Write pending-commit.json — simulates what git-auto will do on threshold., Read pending-commit.json. Returns None if not found., Remove both handshake files after commit is done., read_pending_commit(), write_pending_commit()

### Community 3 - "Git Utilities"
Cohesion: 0.29
Nodes (7): get_changed_files(), get_current_branch(), get_stat_summary(), Get lightweight diff stat — never full diff content., Get list of changed file paths (staged + unstaged)., Write unit-check.json — signals Claude to evaluate whether a logical unit is com, write_unit_check()

### Community 4 - "Commit & Wrapup Skills"
Cohesion: 0.33
Nodes (6): Command: commit, Command: wrapup, Conventional Commits Format, Skill: commit, Skill: wrapup, scripts/stop-git-auto.sh

### Community 5 - "Unit Commit Flow"
Cohesion: 0.60
Nodes (6): scripts/check-unit-complete.sh, Command: unit-commit, Pathway B — Logical-Unit Commit, Skill: unit-commit, .git/unit-check.json, scripts/watch-pending.sh

### Community 6 - "Threshold Commit Handshake"
Cohesion: 0.70
Nodes (5): .git/commit-message.txt, git-auto CLI Tool, scripts/handshake.py, Pathway A — Threshold-Based Commit, .git/pending-commit.json

### Community 7 - "Plugin Config & Protocol"
Cohesion: 0.60
Nodes (5): CLAUDE.md — Plugin Codebase Guide, git-auto-config.json Structure, Handshake File Protocol, .claude-plugin/plugin.json, Race Condition Guard — High files_threshold with unit_commit

### Community 8 - "Configure & Session Start"
Cohesion: 0.40
Nodes (5): Command: configure, .git/git-auto-state.json, hooks/hooks.json, Skill: configure, scripts/start-git-auto.sh

### Community 9 - "Commit Message Writing"
Cohesion: 0.40
Nodes (5): commit_message_path(), Write commit-message.txt for git-auto to pick up., Poll for commit-message.txt. Returns message or None on timeout., wait_for_commit_message(), write_commit_message()

### Community 10 - "Claude Code Hooks"
Cohesion: 0.50
Nodes (3): hooks, PostToolUse, SessionStart

### Community 11 - "Plugin Overview & Docs"
Cohesion: 0.50
Nodes (4): minimal-git-workflow Plugin v2.0.0, Plugin Enhancements Plan (external), README — minimal-git-workflow, Session Context Invariant — No Raw Diffs in Context

### Community 12 - "Session Management"
Cohesion: 0.67
Nodes (3): Session-Specific Instructions, Session Summary Protocol, Session Index

## Knowledge Gaps
- **21 isolated node(s):** `SessionStart`, `PostToolUse`, `name`, `version`, `description` (+16 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `CLAUDE.md — Plugin Codebase Guide` connect `Plugin Config & Protocol` to `Configure & Session Start`, `Plugin Overview & Docs`, `Unit Commit Flow`, `Threshold Commit Handshake`?**
  _High betweenness centrality (0.054) - this node is a cross-community bridge._
- **Why does `scripts/handshake.py` connect `Threshold Commit Handshake` to `Commit & Wrapup Skills`, `Unit Commit Flow`, `Plugin Config & Protocol`, `Configure & Session Start`, `Status Skill`?**
  _High betweenness centrality (0.051) - this node is a cross-community bridge._
- **Why does `Skill: configure` connect `Configure & Session Start` to `Commit & Wrapup Skills`, `Threshold Commit Handshake`, `Plugin Config & Protocol`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **What connects `Write pending-commit.json — simulates what git-auto will do on threshold.`, `Read pending-commit.json. Returns None if not found.`, `Write commit-message.txt for git-auto to pick up.` to the rest of the system?**
  _31 weakly-connected nodes found - possible documentation gaps or missing edges._