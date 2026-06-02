# Claude Code Configuration

A shareable [Claude Code](https://claude.ai/code) setup: slash-command skills,
custom review agents, path-scoped rules, a worktree-safety hook, and a sanitized
settings example.

> Note: `CLAUDE.md` and most skills are written in Russian (the author's working
> language). The logic is language-agnostic; translate the prompts if you prefer.

## Setup

### Fresh install

```bash
git clone git@github.com:Forcharc/claude-config-shared.git ~/.claude
```

### Existing ~/.claude

If `~/.claude` already exists (Claude Code creates it on first run):

```bash
mv ~/.claude ~/.claude-backup
git clone git@github.com:Forcharc/claude-config-shared.git ~/.claude
# copy your local files back
cp ~/.claude-backup/settings.local.json ~/.claude/ 2>/dev/null
cp ~/.claude-backup/history.jsonl ~/.claude/ 2>/dev/null
```

### Settings

There is no `settings.json` in the repo (it is machine-specific and gitignored).
Copy the example and edit:

```bash
cp ~/.claude/settings.example.json ~/.claude/settings.json
```

### Environment (for /gist and /todo skills)

The gist/todo scripts read GitHub access from environment variables — no secrets
in code. Add to `~/.zshrc`:

```bash
export GITHUB_GIST_TOKEN=ghp_xxx        # token with scope "gist"
export GITHUB_TODO_GIST_ID=xxx          # id of a gist to hold todo lists (/todo only)
export GITHUB_USER=your-github-username
```

Token: https://github.com/settings/tokens (scope: `gist`). Scripts print a clear
hint if a variable is missing.

Restart Claude Code after setup.

---

## Structure

```
~/.claude/
├── CLAUDE.md              # Global rules (loaded natively by Claude Code)
├── settings.example.json  # Settings template (copy to settings.json)
├── skills/                # Slash commands (see below)
├── agents/                # Custom subagents (review + orchestration)
├── rules/                 # Path-scoped rules (auto-loaded by file glob)
├── hooks/                 # worktree-boundary.sh (write-safety in worktrees)
├── scripts/               # Python helpers for /gist and /todo
└── docs/tech-debt/        # Tech-debt log (INDEX, TEMPLATE, entries)
```

---

## Skills

Slash commands in `skills/`. Each is a `SKILL.md` with instructions.

| Skill | Purpose |
|-------|---------|
| `/commit` | Stage, split by atomicity, review, format message, push |
| `/review` | Dispatch parallel review agents over the current diff |
| `/review-mr` | Review a GitLab merge request via `glab` |
| `/finalize` | Close all tech-debt items recorded in the session |
| `/techdebt` | Record tech debt with auto-numbering and frontmatter |
| `/techdebt-init` | Initialize the tech-debt directory structure |
| `/rethink` | Critically re-evaluate the last decision from 6 angles |
| `/tell-the-truth` | Honest self-review of completed work |
| `/rule` | Add/edit/remove rules in CLAUDE.md |
| `/fork-init` | Initialize a fork session with a fresh worktree |
| `/gist` | Create/view/update GitHub gists |
| `/todo` | Manage TODO lists stored in a gist |
| `/txt` | Write information to a text file |
| `/remind-protocol` | Reminder: communication protocol |
| `/remind-workflow` | Reminder: agent-orchestration workflow |
| `/remind-text-style` | Reminder: text-style rules for human-facing text |
| `/workflow-guide` | Detailed problem-solving / documentation workflow |
| `/where` | Restore session context after a switch |

---

## Agents

Custom subagents in `agents/`. Used by `/review` and the orchestration skills,
but can also be invoked directly. All run read-only (no Edit/Write) except the
implementer.

**Review agents:**

| Agent | Checks |
|-------|--------|
| logic-reviewer | Null/branch/exception handling, races, leaks, deleted side-effects, edge cases, API misuse |
| clean-code-reviewer | Dead code, speculative generality, naming, magic numbers, DRY, project patterns |
| docs-reviewer | Docs↔code sync: stale docs/comments, missing docs, procedural sync rules |
| efficiency-reviewer | Redundant work, missed concurrency, hot-path bloat, leaks, premature optimization |
| architecture-reviewer | Layer violations, dependency direction, broken abstractions, breaking changes |
| security-reviewer | Secrets, sensitive logs, missing auth, TLS/crypto misuse, input validation |

**Orchestration agents:**

| Agent | Role |
|-------|------|
| review-orchestrator | Runs the full review cycle and the fix-loop until clean |
| implementer | Writes/edits code from a plan or task (the only writing agent) |
| planner | Writes a detailed implementation plan to a file |
| research-writer | Researches the codebase and writes a report to a file |

---

## Rules

Path-scoped rules in `rules/`, auto-loaded when Claude touches matching files.

| Rule | Loaded for |
|------|-----------|
| `kotlin.md` | `**/*.kt`, `**/*.kts` — modern APIs, Compose/Coroutines/Ktor review checklist |
| `check-dependency-versions.md` | Build files (`*.gradle*`, `package.json`, `Cargo.toml`, `go.mod`, ...) — verify versions via WebSearch |

---

## Hooks

`hooks/worktree-boundary.sh` — a `PreToolUse` hook on Write/Edit that prevents
writing outside the active git worktree. Wired up in `settings.example.json`.
