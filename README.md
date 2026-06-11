# Claude Code Configuration

A shareable [Claude Code](https://claude.ai/code) setup: slash-command skills,
custom review agents, path-scoped rules, a worktree-safety hook, and a sanitized
settings example.

> Note: `CLAUDE.md` and most skills are written in Russian (the author's working
> language). The logic is language-agnostic; translate the prompts if you prefer.

## Setup

### Fresh install

```bash
# Clone
git clone git@github.com:Forcharc/claude-config.git ~/.claude
```

### Existing ~/.claude

If `~/.claude` already exists (Claude Code creates it on first run):

```bash
# Backup and remove
mv ~/.claude ~/.claude-backup

# Clone
git clone git@github.com:Forcharc/claude-config.git ~/.claude

# Copy runtime files back (sessions, cache, etc.)
cp ~/.claude-backup/settings.local.json ~/.claude/ 2>/dev/null
cp ~/.claude-backup/history.jsonl ~/.claude/ 2>/dev/null

# Clean up
rm -rf ~/.claude-backup
```

### After setup

Restart Claude Code to pick up changes.

---

## Structure

```
~/.claude/
├── CLAUDE.md              # Global rules (loaded natively by Claude Code)
├── settings.example.json  # Settings template (copy to settings.json and edit)
├── skills/                # Skills (slash commands)
│   ├── commit/SKILL.md
│   ├── review/SKILL.md
│   ├── review-mr/SKILL.md
│   ├── rethink/SKILL.md
│   ├── finalize/SKILL.md
│   ├── fork-init/SKILL.md
│   ├── where/SKILL.md
│   ├── techdebt/SKILL.md          # auto-invoke
│   ├── techdebt-init/SKILL.md
│   ├── gist/SKILL.md              # + gist-edit.md, gist-list.md
│   ├── todo/SKILL.md              # + todo-add/delete/done/list.md
│   ├── txt/SKILL.md
│   ├── rule/SKILL.md
│   ├── remind-protocol/SKILL.md
│   ├── remind-workflow/SKILL.md
│   ├── remind-text-style/SKILL.md
│   ├── workflow-guide/SKILL.md
│   ├── tell-the-truth/SKILL.md
│   ├── agent-core-preamble/SKILL.md   # internal library, not a slash command
│   └── reviewer-findings-output/SKILL.md   # internal library, not a slash command
├── hooks/
│   └── worktree-boundary.sh       # PreToolUse safety hook: blocks writes outside worktree
├── scripts/                       # Python backends for gist and todo skills
│   ├── gist_create.py
│   ├── gist_from_file.py
│   ├── gist_list.py
│   ├── gist_update.py
│   ├── gist_view.py
│   ├── todo_add.py
│   ├── todo_api.py
│   ├── todo_config.py
│   ├── todo_delete.py
│   ├── todo_done.py
│   └── todo_list.py
├── rules/                  # Rules: path-scoped (kotlin.md...) and always-loaded (protocol.md, workflow.md)
│   ├── kotlin.md                      # path-scoped: *.kt, *.kts
│   ├── check-dependency-versions.md   # path-scoped: build files (gradle, npm, cargo...)
│   ├── protocol.md                    # always-loaded: communication protocol (canonical)
│   └── workflow.md                    # always-loaded: orchestration workflow (canonical)
└── agents/                 # Custom review agents
    ├── logic-reviewer.md
    ├── clean-code-reviewer.md
    ├── docs-reviewer.md
    ├── efficiency-reviewer.md
    ├── architecture-reviewer.md
    ├── security-reviewer.md
    ├── plan-compliance-reviewer.md
    ├── plan-factcheck-reviewer.md
    ├── plan-standards-reviewer.md
    ├── implementer.md
    ├── planner.md
    ├── research-writer.md
    └── review-judge.md
```

---

## Skills

### `/commit` - Git Commit

Automated commit workflow: stage, review, commit.

- Stages all changed files (skips secrets)
- Checks atomicity - splits unrelated changes into separate commits
- Runs `/review` after every commit (no exceptions - docs, configs, and trivial changes too)
- Generates commit message: title (imperative, <50 chars) + optional body (WHY, not WHAT)
- Does NOT push by default; push requires explicit per-project opt-in in project CLAUDE.md (e.g. "auto-push after clean review")
- Supports ticket prefixes: `/commit PROJ-12345 fix auth`

### `/review` - Code Review

Dispatches parallel review agents based on diff context:

| Agent | When | What it checks |
|-------|------|----------------|
| logic-reviewer | Always | Null/branch handling, error handling, races, deleted side-effects, edge cases, redundant state, copy-paste with variations, API misuse |
| clean-code-reviewer | Always | Dead code, speculative generality, over-explanatory comments, naming, magic numbers, parameter sprawl, DRY/reuse, project patterns |
| docs-reviewer | Always | Missing docs for changed behavior, stale/contradicting docs & comments, procedural sync-rule violations (touch A -> update B) |
| efficiency-reviewer | Logic/IO/algorithms in diff | N+1, missed concurrency, hot-path bloat, leaks, premature optimization without measurement |
| architecture-reviewer | 3+ files or new classes/APIs | Layer violations, wrong dependencies, broken abstractions, public API surface, breaking changes without migration |
| security-reviewer | Auth/network/crypto/storage/IPC code in diff | Secrets in code, sensitive logs, missing auth, TLS issues, crypto misuse, input validation, unsafe deserialization |
| plan-compliance-reviewer | plan= passed | MISSING (claimed by plan, not done), EXTRA (out of scope), DEVIATION (done differently than prescribed) |

After agents report findings, the main agent fixes real issues and skips false positives.

### `/techdebt` - Record Tech Debt

Records tech debt with auto-numbering and structured frontmatter (module, tags, priority). Storage location depends on `techdebt_location` setting in project CLAUDE.md:
- `repo` (default) - `docs/tech-debt/` (committed to repository)
- `local` - `.claude/projects/<project>/memory/tech-debt/` (local only, not in repo; nested in `memory/` so the worktree-boundary hook allows writes from worktrees)

If the storage directory doesn't exist, calls `/techdebt-init` first.

### `/techdebt-init` - Initialize Tech Debt Structure

Creates tech debt directory with INDEX.md and TEMPLATE.md. Auto-detects project modules for INDEX sections. Respects `techdebt_location` setting.

### `/rethink` - Self-Critique

Forces the AI to critically re-evaluate its last proposal/plan/decision:
- Attacks from 6 angles: complexity, completeness, correctness, necessity, alternatives, user context
- No self-defense - pure critic mode
- Speaks up if the user's approach seems questionable

### `/gist` - Quick Notes

Create and manage quick notes/gists.

### `/todo` - Task Management

Create and manage TODO lists.

### `/txt` - Text File Output

Output information to a text file.

### `/rule` - Manage Rules

Add/edit rules in ~/.claude/CLAUDE.md.

### `/remind-protocol` - Communication Protocol

Thin reminder: dynamically injects rules/protocol.md (the single source of the communication protocol) at invocation. No content copies.

### `/remind-workflow` - Agent Orchestration

Thin reminder: dynamically injects rules/workflow.md (the single source of the orchestration workflow) at invocation. No content copies.

### `/remind-text-style` - Text Style Rules

Thin reminder: injects text-masking and style rules at invocation. Two levels: symbol masking (applies everywhere - commits, docs, comments, PR replies) and style (concise, no preambles - applies only to short interactive texts like MR comments and colleague replies, not to docs or commit bodies).

### `/workflow-guide` - Detailed Workflow Guide

Extended guide with examples and step-by-step flow descriptions. Companion to rules/workflow.md (the canonical algorithm lives there; examples and details live here). Use when you need concrete examples of the review cycle, worktree workflow, or planning pipeline.

### `/finalize` - End-of-session Cleanup

Closes all tech debts created in the current session, processes flow-feedback journal entries, and resolves session threads. Runs implementer agents in parallel via worktrees. Intended to be called at the end of a feature branch or session.

### `/fork-init` - Fork Session Setup

Called immediately after forking a chat. Explains to Claude that it is a fork and sets up a new worktree so the fork does not interfere with the parent session.

### `/where` - Restore Session Context

Restores session context after switching away. Returns a one-message summary: current task, discussion highlights with quotes, what is done, what remains.

### `/review-mr` - GitLab MR Review

Full MR review flow via glab: fetches diff and discussion context, runs review agents, prepares comment drafts via /txt. The user publishes comments manually. Currently covers GitLab only (glab).

### `/tell-the-truth` - Honest Self-Review

Forces honest self-analysis of completed work: completeness, copy-paste, edge cases, tests, architecture. No sugarcoating.

---

### agent-core-preamble - Internal Agent Preamble

Not a slash command: a shared library injected into subagent context via the skills: frontmatter field of an agent definition. Carries the project-rules reading block and the flow-feedback block so they live in one place instead of 13 copies. Do not invoke directly.

### reviewer-findings-output - Internal Reviewer Output Protocol

Not a slash command: a shared library injected via the skills: frontmatter into the nine reviewer agents. Carries the out-file findings protocol (write findings to the out= path, reply with the path and a findings count). Do not invoke directly.

## Rules

Rules in `rules/`: path-scoped ones load when Claude works with matching files; protocol.md and workflow.md have no paths filter and load into every session.

### kotlin.md

Kotlin development rules: modern APIs (Coroutines over AsyncTask, Flow over LiveData), review checklist (Compose, Coroutines, idioms, Ktor). Loaded for `**/*.kt`, `**/*.kts`.

### check-dependency-versions.md

Enforces version checks via WebSearch when adding/updating dependencies. Loaded for build files: `libs.versions.toml`, `build.gradle*`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, and more.

---

## Agents

Custom subagents in `agents/`. Used by `/review` but can also be invoked directly.

### logic-reviewer

Model: Sonnet. Tools: Read, Grep, Glob, Bash (read-only, no Edit/Write).

Checks correctness and bug-prone code: null/branch/exception handling, race conditions, missing cancellation, resource leaks (un-closed), deleted side-effects, copy-paste with variations, redundant state, API misuse, edge cases. Mindset: "won't fix it - will eventually break".

### clean-code-reviewer

Model: Sonnet. Tools: Read, Grep, Glob, Bash.

Checks readability and YAGNI: dead code, speculative generality (with test-seam exceptions), speculative/over-explanatory comments, naming, magic numbers, parameter sprawl, function/class size, copy-paste without variations (DRY), reuse violations, project pattern consistency. Mindset: "remove the problem - code works the same, just cleaner".

### docs-reviewer

Model: Sonnet. Tools: Read, Grep, Glob, Bash.

Checks code↔docs sync: missing docs for changed behavior (new module/command/env-var/API not reflected in CLAUDE.md, README, docs, KDoc), stale docs and comments that contradict the code after a change, and violations of procedural sync rules ("touch A -> update B"). Covers any `.md` and any comment/KDoc; subject-matter rule violations stay with the profile reviewer. Mindset: "the text about the code drifted from the code".

### efficiency-reviewer

Model: Sonnet. Tools: Read, Grep, Glob, Bash.

Checks for redundant computations, missed concurrency, hot-path bloat, unbounded data structures, resource leaks, and premature optimization without measurement.

### architecture-reviewer

Model: Sonnet. Tools: Read, Grep, Glob, Bash.

Checks layer violations, dependency direction, broken abstractions, misplaced classes, public API surface expansion, and breaking changes without migration plan.

### security-reviewer

Model: Sonnet. Tools: Read, Grep, Glob, Bash. Conditional trigger: orchestrator runs it when diff touches auth, network, crypto, storage, logging, deeplinks, WebView, or IPC code.

Checks for hardcoded secrets, sensitive data in logs, missing auth/authz checks, TLS/certificate issues, input validation gaps (SQL/path traversal/command injection), crypto misuse (weak algorithms, bad IV, ECB), unsafe deserialization, Android-specific issues (exported components, WebView JS bridges, unencrypted storage).

### plan-compliance-reviewer

Model: Sonnet. Tools: Read, Grep, Glob, Bash, Write. Conditional trigger: orchestrator runs it when plan= is passed (commit implements an approved plan).

Checks that the commit matches the approved plan for the given scope (plan_scope=): reports MISSING when plan-required changes are absent from the diff, EXTRA when the diff contains changes outside the plan scope, and DEVIATION when something is done differently than the plan prescribed.

### plan-factcheck-reviewer

Model: Sonnet. Tools: Read, Grep, Glob, Bash, WebSearch, WebFetch, Write. Used in the planning pipeline (parallel with plan-standards-reviewer after planner produces a plan).

Checks every verifiable claim in the plan for correctness - code claims via Read/Grep, external facts via WebSearch/WebFetch. Finds hallucinations: wrong API signatures, non-existent methods, misread file paths, incorrect library behavior. Does not fix - only reports findings so planner can correct them.

### plan-standards-reviewer

Model: Sonnet. Tools: Read, Grep, Glob, Bash, Write. Used in the planning pipeline (parallel with plan-factcheck-reviewer after planner produces a plan).

Checks that the plan follows project rules (rules/), established codebase patterns, and the solution the user approved. Reports violations of rules, architectural patterns, and deviations from the agreed-upon design decision. Does not fix - only reports findings so planner can correct them.

---

## Global Settings (settings.example.json)

### Post-commit hook

After every `/commit`, a PostToolUse hook injects a reminder to record any tech debt discovered during work via `/techdebt`.

---

## CLAUDE.md (Global Rules)

Located at `~/.claude/CLAUDE.md` (loaded natively by Claude Code). Contains only what is unique to it: identity, user, text masking, git rules (always `/commit`, commit signatures, push policy), worktrees, tech debt, session threads, session id, technical tips. The full communication protocol and orchestration workflow live in rules/protocol.md and rules/workflow.md (always-loaded user-level rules).

---

## Workflow

```
Work on code
    │
    ├─ Notice tech debt? → /techdebt (record it)
    │
    ├─ Done? → /commit
    │           ├─ /review (agents check quality/efficiency/architecture)
    │           ├─ Fix issues
    │           ├─ Generate commit message
    │           ├─ git commit (+ git push если разрешён проектом)
    │           └─ Hook reminds about /techdebt
    │
    ├─ Unsure about approach? → /rethink
    │
    └─ Need to discuss? → follow protocol from /remind-protocol
```
