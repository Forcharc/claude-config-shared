#!/usr/bin/env bash
# Tests for git-branch-guard.py. Run: bash hooks/git-branch-guard.test.sh
#
# Builds throwaway repos with a linked worktree and feeds the hook the JSON a
# Bash PreToolUse call would carry -- nothing outside the temp dir is touched.
# The hook never executes the command it inspects, it only reads it.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/git-branch-guard.py"
[ -x "$HOOK" ] || { echo "hook not executable: $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkrepo() {
  local root="$1"
  mkdir -p "$root"
  git -C "$root" init -q
  git -C "$root" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$root" worktree add -q "$root/.claude/worktrees/wt" -b wt
}

REPO="$TMP/repo"; mkrepo "$REPO"; WT="$REPO/.claude/worktrees/wt"
OTHER="$TMP/other"; mkrepo "$OTHER"
NOREPO="$TMP/plain"; mkdir -p "$NOREPO"

fails=0

report() {
  if [ "$got" = "$want" ]; then
    printf 'ok    %-52s %s\n' "$desc" "$got"
  else
    printf 'FAIL  %-52s %s (want %s)\n' "$desc" "$got" "$want"
    fails=$((fails + 1))
  fi
}

# check desc cwd command want(DENY|allow)
check() {
  desc="$1"; cwd="$2"; cmd="$3"; want="$4"
  out=$(jq -nc --arg cwd "$cwd" --arg cmd "$cmd" \
    '{cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd}}' | "$HOOK")
  got="allow"; [ -n "$out" ] && got="DENY"
  report
}

# check_raw desc rawinput want -- arbitrary stdin, e.g. garbage
check_raw() {
  desc="$1"; raw="$2"; want="$3"
  out=$(printf '%s' "$raw" | "$HOOK")
  got="allow"; [ -n "$out" ] && got="DENY"
  report
}

# check_hint desc cwd command expected-substring
check_hint() {
  desc="$1"; cwd="$2"; cmd="$3"; sub="$4"
  out=$(jq -nc --arg cwd "$cwd" --arg cmd "$cmd" \
    '{cwd:$cwd,tool_name:"Bash",tool_input:{command:$cmd}}' | "$HOOK")
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  case "$reason" in
    *"$sub"*) printf 'ok    %-52s hint\n' "$desc" ;;
    *) printf 'FAIL  %-52s hint missing %s\n    got: %s\n' "$desc" "$sub" "$reason"; fails=$((fails + 1)) ;;
  esac
}

# --- forbidden forms in the main tree
for c in 'git checkout main' 'git checkout -b feat' 'git checkout -- a.md' \
         'git switch x' 'git switch -c x' 'git reset --hard' \
         'git reset --hard HEAD~1' 'git branch -f x HEAD' \
         'git branch --force x' 'git branch -f -u x'; do
  check "main: $c" "$REPO" "$c" DENY
done

# --- same commands in a linked worktree
for c in 'git checkout main' 'git switch x' 'git reset --hard' 'git branch -f x HEAD'; do
  check "worktree: $c" "$WT" "$c" allow
done

# --- safe commands in main
for c in 'git status' 'git log --oneline' 'git worktree add -b n ../n HEAD' \
         'git branch' 'git branch -d x' 'git branch -m a b' \
         'git reset --soft HEAD~1' 'git reset HEAD file' 'git restore a.md' 'git stash'; do
  check "main safe: $c" "$REPO" "$c" allow
done

# --- global options and git by path
check 'global: --no-pager'            "$REPO" 'git --no-pager checkout x' DENY
check 'global: -c k=v checkout'       "$REPO" 'git -c user.name=a checkout x' DENY
check 'global: -c k=v switch'         "$REPO" 'git -c core.pager=cat switch x' DENY
check 'global: /usr/bin/git'          "$REPO" '/usr/bin/git checkout x' DENY

# --- -C
check '-C main from plain dir'        "$NOREPO" "git -C $REPO checkout x" DENY
check '-C worktree from main'         "$REPO" "git -C $WT checkout x" allow
check '-C main from worktree'         "$WT" "git -C $REPO checkout x" DENY
check '-C two: relative to first'     "$NOREPO" "git -C $TMP -C repo checkout x" DENY
check '-C two: into worktree'         "$NOREPO" "git -C $REPO -C .claude/worktrees/wt checkout x" allow
check '-C . in main'                  "$REPO" 'git -C . checkout x' DENY
check '-C ../repo from sibling dir'   "$NOREPO" 'git -C ../repo checkout x' DENY
check '-C nonexistent path'           "$REPO" 'git -C /no/such/dir checkout x' allow

# --- cd
check 'cd main && checkout'           "$NOREPO" "cd $REPO && git checkout x" DENY
check 'cd worktree && checkout'       "$REPO" "cd $WT && git checkout x" allow
check 'cd main; switch'               "$NOREPO" "cd $REPO; git switch x" DENY
check 'cd relative worktree'          "$REPO" 'cd .claude/worktrees/wt && git checkout x' allow
check 'cd plain dir from main'        "$REPO" "cd $NOREPO && git checkout x" allow
check 'cd $VAR (unknown)'             "$REPO" 'cd $SOMEVAR && git checkout x' allow
check 'cd back to main after wt'      "$NOREPO" "cd $WT && git status && cd $REPO && git checkout x" DENY

# --- chains
check 'chain: &&'                     "$REPO" 'git status && git checkout x' DENY
check 'chain: ;'                      "$REPO" 'git status; git checkout x' DENY
check 'chain: ||'                     "$REPO" 'false || git checkout x' DENY
check 'chain: pipe then ;'            "$REPO" 'git log | cat; git switch x' DENY
check 'chain: newline'                "$REPO" $'git status\ngit checkout x' DENY
check 'chain: && without space'       "$REPO" 'git status &&git checkout x' DENY
check 'chain: parentheses'            "$REPO" '(git checkout x)' DENY
check 'chain: env assignment prefix'  "$REPO" 'FOO=1 git checkout x' DENY
check 'chain: harmless'               "$REPO" 'echo hi && git status' allow
check 'chain: subshell cd not undone' "$REPO" "(cd $WT && git status); git checkout x" allow

# --- quoting and false positives
check 'quoted && in echo'             "$REPO" 'echo "a && git checkout x"' allow
check 'single-quoted echo'            "$REPO" "echo 'git checkout x'" allow
check 'commit message'                "$REPO" 'git commit -m "git checkout fix"' allow
check 'grep pattern'                  "$REPO" 'grep -r "git reset --hard" .' allow
check 'echo arguments'                "$REPO" 'echo git checkout x' allow
check 'trailing comment'              "$REPO" 'git status # git checkout x' allow
check 'heredoc body'                  "$REPO" $'cat <<EOF\ngit checkout x\nEOF' allow
check 'command after heredoc'         "$REPO" $'cat <<EOF\nhi\nEOF\ngit checkout x' DENY

check 'heredoc <<- tabs, then checkout' "$REPO" $'cat <<-EOF\n\thi\n\tEOF\ngit checkout x' DENY
check 'line continuation'             "$REPO" $'git \\\n checkout x' DENY
check 'mid-word hash, then checkout'  "$REPO" 'echo a#b; git checkout x' DENY
check 'escaped backslash, newline, checkout' "$REPO" $'echo \\\\\ngit checkout x' DENY
check 'heredoc body ends with backslash'  "$REPO" $'cat <<\'EOF\'\nfoo \\\nEOF\ngit checkout x' DENY
HASHREPO="$TMP/dir#1"; mkrepo "$HASHREPO"
check 'hash in quoted -C path, main tree' "$NOREPO" "git -C '$HASHREPO' checkout x" DENY
check 'hash in quoted -C path, worktree'  "$NOREPO" "git -C '$HASHREPO/.claude/worktrees/wt' checkout x" allow
check 'heredoc <<- with space, then checkout' "$REPO" $'cat <<- EOF\n\thi\n\tEOF\ngit checkout x' DENY
check 'cd - (unknown dir)'            "$REPO" 'cd -; git checkout x' allow
check 'comment, then checkout'        "$REPO" $'echo a # c\ngit checkout x' DENY
check 'comment with apostrophe'       "$REPO" $'echo a # don\'t\ngit checkout x' DENY

# --- redirects
check 'redirect output'               "$REPO" 'git checkout x > /dev/null 2>&1' DENY

# --- not expanded: let through
check 'bash -c'                       "$REPO" "bash -c 'git checkout x'" allow
check 'eval'                          "$REPO" 'eval "git checkout x"' allow
check 'command substitution'          "$REPO" '$(git checkout x)' allow
check 'echo with substitution'        "$REPO" 'echo $(git checkout x)' allow
check 'backticks'                     "$REPO" '`git checkout x`' allow
check '-C with variable'              "$REPO" 'git -C "$DIR" checkout x' allow
check '--git-dir'                     "$REPO" 'git --git-dir=/x checkout y' allow

# --- outside a repo
check 'plain dir'                     "$NOREPO" 'git checkout x' allow
check 'nonexistent cwd'               "$TMP/nope" 'git checkout x' allow

# --- garbage input
check_raw 'empty stdin'               '' allow
check_raw 'not json'                  'not json' allow
check_raw 'empty object'              '{}' allow
check_raw 'no tool_input'             '{"cwd":"/x"}' allow
check_raw 'command not a string'      '{"cwd":"x","tool_input":{"command":5}}' allow
check 'unclosed quote'                "$REPO" 'git checkout "x' allow
check 'empty command'                 "$REPO" '' allow

# --- deny reason
check_hint 'reason prefix'            "$REPO" 'git checkout x' 'git-branch-guard:'
check_hint 'reason offers worktree'   "$REPO" 'git checkout x' 'worktree add'

echo
if [ "$fails" -eq 0 ]; then echo "all scenarios passed"; else echo "failures: $fails"; fi
exit "$fails"
