# Claude Code Harness

A shareable [Claude Code](https://claude.ai/code) setup: an orchestrator workflow
that delegates work to sub-agents, with a code review loop at its center. It
contains agents, skills (slash commands), rules, safety hooks, a status line and a
sanitized settings example.

> Note: `CLAUDE.md`, the rules, the agents and the skills are written in Russian
> (the author's working language). The logic does not depend on the language;
> translate the prompts if you prefer.

## What it is

- The main session acts as an orchestrator: it classifies a task, researches,
  plans, delegates implementation and review to agents, and checks the result.
- Agents are narrow roles (researcher, planner, implementer, several reviewers, a
  judge). They exchange data through files, not through the orchestrator's context.
- Every commit goes through a review loop (`/review`) until it comes back clean.
- Edits to tracked files happen in git worktrees; hooks enforce that.

## Quick start

If `~/.claude` does not exist yet, just clone and create settings:

```bash
git clone https://github.com/Forcharc/claude-config-shared.git ~/.claude
cp ~/.claude/settings.example.json ~/.claude/settings.json   # then edit it
```

If `~/.claude` already exists (Claude Code creates it on first run), move it aside first.

Moving `~/.claude` also moves your credentials, sessions and `projects/` into the
backup: you will have to log in again, and the old session history stays in the
backup directory.

```bash
mv ~/.claude ~/.claude-backup
git clone https://github.com/Forcharc/claude-config-shared.git ~/.claude

# Copy your own settings and history back
cp ~/.claude-backup/settings.json ~/.claude/ 2>/dev/null
cp ~/.claude-backup/settings.local.json ~/.claude/ 2>/dev/null
cp ~/.claude-backup/history.jsonl ~/.claude/ 2>/dev/null
[ -f ~/.claude/settings.json ] || cp ~/.claude/settings.example.json ~/.claude/settings.json
```

Restart Claude Code afterwards and edit `settings.json` to fit your setup.

## Review loop

`/review` is the main entry point. It starts the `review-runner` agent, which drives
the whole loop:

```
/review
  -> review-runner
       -> reviewers in parallel
          (logic, security, clean-code, efficiency, architecture, docs,
           plan-compliance, fresh-reader)
       -> review-judge        verifies every finding against the code
       -> implementer         fixes confirmed findings
       -> fix commit
       -> re-review, until the verdict is clean
```

- `mode=full` (default): findings are fixed and committed.
- `mode=analysis-only`: someone else's code, no edits, no commits; only a verdict.
- `/review-mr` reviews a GitLab merge request through `glab`, using the same loop in
  `analysis-only` mode.

Minimal set if you only want the review loop: all of `agents/`, and
`skills/{review,agent-core-preamble,reviewer-findings-output,commit,techdebt,techdebt-init}`,
plus `rules/workflow.md`, `rules/code-says-what-it-does.md` and `rules/repo-references.md`. These are the
things the loop refers to: `/commit` (fix commits), `/techdebt` and `/techdebt-init`
(the judge records confirmed debt), `/review-mr` (optional), and the three rule files
(`workflow.md` is referenced by `/review` and `/commit`; `repo-references.md` is used by `docs-reviewer`).

## Agents

All agents live in `agents/`. Most of them load the shared preambles
`agent-core-preamble` and `reviewer-findings-output` through the `skills:` field of
their frontmatter.

| Agent | Role |
|-------|------|
| `review-runner` | Drives the review loop: picks reviewers, runs them, calls the judge, fixes, re-reviews |
| `review-judge` | Verifies each reviewer finding against the code; confirms, defers as debt, or drops |
| `logic-reviewer` | Bugs, edge cases, error handling, races |
| `security-reviewer` | Secrets, sensitive data in logs, missing checks, unsafe input handling |
| `clean-code-reviewer` | YAGNI, dead code, speculative abstractions, naming, duplication |
| `efficiency-reviewer` | Redundant work, missed concurrency, leaks |
| `architecture-reviewer` | Layering, dependencies, public API surface, breaking changes |
| `docs-reviewer` | Docs that no longer match the code |
| `plan-compliance-reviewer` | Compares a commit with the implementation plan |
| `fresh-reader-reviewer` | Reads the final branch state without the plan and checks the shape of the code |
| `plan-runner` | Drives plan creation and plan review |
| `planner` | Writes a detailed implementation plan to a file |
| `plan-factcheck-reviewer` | Checks the claims in a plan against the code |
| `plan-standards-reviewer` | Checks a plan against project rules and established patterns |
| `research-writer` | Researches the codebase and writes a report to a file |
| `implementer` | Writes and edits code from a plan or task |

## Skills

Skills live in `skills/<name>/SKILL.md`.

| Skill | Purpose |
|-------|---------|
| `/review` | Starts the review loop |
| `/review-mr` | Reviews a GitLab merge request through `glab` |
| `/commit` | Stages, reviews and formats a commit; pushes only if the project opts in |
| `/techdebt` | Records a tech debt item with an automatic number |
| `/techdebt-init` | Creates the tech debt directory structure |
| `/finalize` | Closes the session's tech debt, processes flow feedback and deferred threads |
| `/fork-init` | Sets up a forked chat session with its own worktree |
| `/txt` | Writes information to a text file and opens it for copying |
| `agent-core-preamble` | Library for sub-agents: rules check, worktree check, flow feedback (loaded by agents, not called directly) |
| `reviewer-findings-output` | Library for reviewers: how to write the findings file (loaded by reviewers, not called directly) |

## Rules

Rules are in `rules/`. The first three apply to every session; the last two are
scoped by `paths:` in their frontmatter.

| File | Content |
|------|---------|
| `workflow.md` | Orchestration through sub-agents, worktree isolation, delegation reference |
| `protocol.md` | Communication protocol: numbered questions, options with a recommended one |
| `repo-references.md` | What may and may not be referenced from texts committed to a repository |
| `code-says-what-it-does.md` | Code shape must match production behavior; no test-only members |
| `check-dependency-versions.md` | Check the current version before adding or bumping a dependency |

## Hooks and status line

| File | Purpose |
|------|---------|
| `hooks/worktree-boundary.sh` | `PreToolUse` on Write/Edit/MultiEdit/NotebookEdit: refuses writes into the main working tree of a git repository (git-ignored files and live merge conflicts excepted) |
| `hooks/git-branch-guard.py` | `PreToolUse` on Bash: refuses `git checkout`, `switch`, `reset --hard` and `branch -f` in the main working tree |
| `hooks/*.test.sh` | Test scripts for the two hooks |
| `statusline.sh` | One-line status line: folder, model, context, monthly cost |

## Requirements

- Claude Code
- git and bash
- `python3` (the `git-branch-guard.py` hook)
- `jq` (`statusline.sh`, `skills/review/runner-wait.sh` - exits with an error without it; `worktree-boundary.sh` skips its checks without it)
- `glab`, configured for your GitLab instance (only for `/review-mr`)
- `ccusage`, run through `npx` (only for the monthly cost in the status line)
- macOS: `statusline.sh` calls `stat -f`, the BSD form. On Linux, change those calls
  to `stat -c`.

## Files created at runtime

The harness writes these itself; they are not part of the repository.

- `projects/<slug>/memory/agent-results/` - reports exchanged between agents
- `projects/<slug>/memory/flow-feedback.md` - problems agents hit in the process itself
- `projects/<slug>/memory/commit-sessions.md` - which session made which commit
- `projects/<slug>/memory/session-threads.md` - ideas and questions deferred during a session
- `.tmp/` in your working repositories - scratch files and logs

`<slug>` is the absolute path of `~/.claude` with every `/` and `.` replaced by `-`.

## Settings example

`settings.example.json` is a minimal starting point for `settings.json`:

- Two `PreToolUse` hooks: `worktree-boundary.sh` for file edits and
  `git-branch-guard.py` for Bash. Together they keep tracked-file edits and branch
  switches out of the main working tree.
- `statusLine` points to `statusline.sh`.
- `includeGitInstructions: false` drops Claude Code's built-in git instructions;
  the git section of `CLAUDE.md` replaces them.
- `defaultMode: default` keeps the normal permission prompts. The allow list is
  short on purpose; add commands you trust. Only read-only git commands
  (`status`, `diff`, `log`, `show`) are pre-approved; `push` and other git commands
  that write still ask for confirmation. The form `git -C <path> ...` is not
  covered by these rules and will ask too; add `Bash(git -C:*)` only on purpose,
  because it also covers `push`.

## Customizing

`CLAUDE.md` is a template without a persona or a user name. Add your own: how the
assistant should address you, your language, your project conventions. Per-project
`CLAUDE.md` files override the global one, for example to allow or forbid pushing
for a particular repository.
