#!/usr/bin/env bash
# PreToolUse hook: block Write/Edit/MultiEdit/NotebookEdit that would
# write outside the active worktree. Prevents leaks from delegated
# agents that carry main-tree absolute paths into their tool calls.

set -eu

# Fail open if jq is missing — safer than breaking every Write/Edit.
command -v jq >/dev/null 2>&1 || exit 0

payload=$(cat)

# Single jq pass: cwd and file_path tab-separated.
IFS=$'\t' read -r cwd file_path < <(printf '%s' "$payload" | \
  jq -r '[(.cwd // ""), (.tool_input.file_path // .tool_input.notebook_path // "")] | @tsv')

[ -z "$cwd" ] || [ -z "$file_path" ] && exit 0

# Only enforce inside a worktree subtree.
case "$cwd" in
  */.claude/worktrees/*) ;;
  *) exit 0 ;;
esac

# Derive worktree root via parameter expansion (no fork).
prefix="${cwd%%/.claude/worktrees/*}"
rest="${cwd#*/.claude/worktrees/}"
worktree_name="${rest%%/*}"
worktree_root="${prefix}/.claude/worktrees/${worktree_name}"

# Normalize file_path to defeat path traversal (../ and ./).
normpath() {
  local path="$1" seg out=""
  local IFS=/
  local -a parts=()
  for seg in $path; do
    case "$seg" in
      ""|".") ;;
      "..") [ ${#parts[@]} -gt 0 ] && parts=("${parts[@]:0:${#parts[@]}-1}") ;;
      *) parts+=("$seg") ;;
    esac
  done
  for seg in ${parts[@]+"${parts[@]}"}; do out+="/$seg"; done
  printf '%s' "${out:-/}"
}
normalized=$(normpath "$file_path")

# Allow inside the worktree.
case "$normalized" in
  "$worktree_root"|"$worktree_root"/*) exit 0 ;;
esac

# Allow harness per-project memory (auto-memory and agent-results).
# Research agents spawned from inside a worktree legitimately write reports
# to ~/.claude/projects/<slug>/memory/agent-results/ — harness data outside
# git, shared across main and worktrees.
# Anchor to $HOME so a rogue .claude/projects/*/memory/ path inside another
# repo cannot slip through.
case "$normalized" in
  "$HOME"/.claude/projects/*/memory|"$HOME"/.claude/projects/*/memory/*) exit 0 ;;
esac

reason="worktree-boundary: refusing to write '$normalized' from worktree '$worktree_root'. Use a path under the worktree or ~/.claude/projects/*/memory/."

jq -nc \
  --arg reason "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
exit 0
