#!/usr/bin/python3
# PreToolUse hook (matcher: Bash). Denies commands that change the branch or
# HEAD of a git repo's MAIN working tree:
#   git checkout ...        (any form, including -b and -- <file>)
#   git switch ...
#   git reset --hard ...
#   git branch -f / --force ...
# In a linked worktree and outside any git repo these are allowed.
#
# Why: the main tree is a shared resource -- it may hold someone else's
# uncommitted work, and switching its branch either drags that work along or
# breaks a command running there. A new branch must come with its own
# worktree. Sibling hook worktree-boundary.sh guards file writes by the
# Write/Edit tools; this one covers branch changes made through the shell.
#
# What it understands (hand-rolled, shlex-based, heuristic):
#   - git global options before the subcommand (-C <path> repeated, -c k=v,
#     --no-pager, ...), and a git binary given by path (/usr/bin/git);
#   - `cd <path>` / `pushd <path>` earlier in the chain changing the directory
#     for later commands;
#   - chains: && || ; | & newlines, parentheses, redirections, leading
#     VAR=value assignments, and quoting (`echo "a && git checkout x"` is fine),
#     comments and heredoc bodies.
#
# What it does NOT expand (the command is let through when the directory or the
# command itself is dynamic): $(...), backticks, `bash -c '...'`, eval,
# $VARIABLE or globs in a path, functions and aliases, git run via
# xargs/env/sudo, git aliases from gitconfig (`git co`), and the --git-dir /
# --work-tree flags (let through). A GIT_DIR=/GIT_WORK_TREE= env prefix is
# simply dropped: the decision is made from the cwd. `cd -` and `pushd +N`
# leave the directory unknown, so later commands are let through. Directory
# changes made inside ( ... ) or { ... } are not rolled back when the group
# ends -- a deliberate simplification.
#
# Threat model: same as worktree-boundary.sh -- it protects against an
# ORDINARY mistake (wrong cwd, stale habit, a delegated agent that inherited
# the wrong directory), not against someone who deliberately bypasses it.
# Everything unexpected fails open: broken JSON, unparsable quoting, missing
# git, a git failure, a nonexistent directory all mean "allow".
#
# Deny format is the same as worktree-boundary.sh; the reason starts with
# "git-branch-guard:" so it can be told apart from a Claude Code harness deny.

import json
import os
import re
import shlex
import subprocess
import sys

PUNCT = set("();<>|&")
SKIP_WORDS = {"{", "!", "if", "then", "else", "elif", "do", "while", "until",
              "time", "command", "exec", "builtin"}
ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# '#' that starts a shell comment: at the start of a word (a mid-word '#' as in
# echo a#b is literal).
COMMENT_START_RE = re.compile(r"(?:^|(?<=[\s;&|()<>]))#")
BRANCH_FORCE_RE = re.compile(r"^-[A-Za-z]*f[A-Za-z]*$")
# git global options that take a separate value (the --opt=value form needs no skip).
VALUE_OPTS = {"--namespace", "--super-prefix", "--config-env"}
TREE_OPTS = ("--git-dir", "--work-tree")


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason}}, ensure_ascii=False))
    sys.exit(0)


def strip_comment(line):
    """Cut a real shell comment: '#' at the start of a word, outside quotes."""
    quote = None
    i = 0
    while i < len(line):
        c = line[i]
        if c == "\\" and quote != "'":
            i += 2
            continue
        if quote:
            if c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "#" and COMMENT_START_RE.match(line, i):
            return line[:i]
        i += 1
    return line


def tokenize(line):
    lex = shlex.shlex(strip_comment(line), posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    lex.commenters = ""  # comments are cut by strip_comment, quote-aware
    return list(lex)


def is_punct(tok):
    return bool(tok) and all(c in PUNCT for c in tok)


def logical_lines(cmd):
    """Yield token lists per logical line; joins lines split by a trailing
    backslash or an open quote, skips heredoc bodies (their lines are never
    joined). Stops (fail-open) at the first unparsable remainder."""
    lines = cmd.split("\n")
    i = 0
    while i < len(lines):
        buf = lines[i]
        i += 1
        # An odd number of trailing backslashes is a continuation; an even
        # number is escaped backslashes followed by a real newline.
        while i < len(lines) and (len(buf) - len(buf.rstrip("\\"))) % 2:
            buf = buf[:-1] + " " + lines[i]
            i += 1
        while True:
            try:
                toks = tokenize(buf)
                break
            except ValueError:
                if i >= len(lines):
                    return
                buf += "\n" + lines[i]
                i += 1
        yield toks
        for k, t in enumerate(toks):
            if t == "<<" and k + 1 < len(toks):
                delim = toks[k + 1]
                strip = delim.startswith("-")  # shlex splits <<-EOF into "<<", "-EOF"
                if strip:
                    delim = delim[1:]
                    if not delim and k + 2 < len(toks):
                        delim = toks[k + 2]  # `<<- EOF`
                while i < len(lines):
                    body = lines[i]
                    i += 1
                    if (body.strip() if strip else body) == delim:
                        break
                break


def split_segments(cmd):
    """Return a list of segments (lists of words) in command order."""
    segs = []
    for toks in logical_lines(cmd):
        cur = []
        k = 0
        depth = 0  # inside $( ... ): not expanded, skipped
        while k < len(toks):
            t = toks[k]
            if depth:
                if is_punct(t):
                    depth += t.count("(") - t.count(")")
                k += 1
                continue
            if is_punct(t):
                if "<" in t or ">" in t:
                    k += 2  # redirect and its target
                    continue
                if t.startswith("(") and k > 0 and toks[k - 1].endswith("$"):
                    cur = []  # the word before $( is not a command
                    depth = t.count("(") - t.count(")")
                    k += 1
                    continue
                if cur:
                    segs.append(cur)
                cur = []
            else:
                cur.append(t)
            k += 1
        if cur:
            segs.append(cur)
    return segs


def resolve(base, p):
    if p is None or any(c in p for c in "$`*?"):
        return None
    p = os.path.expanduser(p)
    if os.path.isabs(p):
        return os.path.normpath(p)
    if base is None:
        return None
    return os.path.normpath(os.path.join(base, p))


def parse_git(words):
    """words[0] is git. Returns (c_paths, subcmd, args) or None."""
    c_paths = []
    i = 1
    while i < len(words):
        w = words[i]
        if w == "-C" and i + 1 < len(words):
            c_paths.append(words[i + 1])
            i += 2
        elif w == "-c" and i + 1 < len(words):
            i += 2
        elif w in TREE_OPTS or w.startswith(tuple(o + "=" for o in TREE_OPTS)):
            return None
        elif w in VALUE_OPTS:
            i += 2
        elif w.startswith("-"):
            i += 1
        else:
            return c_paths, w, words[i + 1:]
    return None


def is_forbidden(sub, args):
    if sub in ("checkout", "switch"):
        return True
    if sub == "reset":
        return "--hard" in args
    if sub == "branch":
        for a in args:
            if a == "--":
                break
            if a == "--force" or BRANCH_FORCE_RE.match(a):
                return True
    return False


def git_out(base, *a):
    r = subprocess.run(["git", "-C", base] + list(a), capture_output=True,
                       text=True, timeout=5)
    if r.returncode != 0:
        raise RuntimeError("git failed")
    return r.stdout.splitlines()


def is_main_tree(base):
    gd, common = git_out(base, "rev-parse", "--absolute-git-dir", "--git-common-dir")[:2]
    common = os.path.join(base, common)
    return os.path.realpath(gd) == os.path.realpath(common)


def scan(cmd, cwd):
    cur = cwd or None
    for words in split_segments(cmd):
        while words and (ASSIGN_RE.match(words[0]) or words[0] in SKIP_WORDS):
            words = words[1:]
        if not words:
            continue
        head = words[0]
        if head in ("cd", "pushd"):
            if "-" in words[1:] or (head == "pushd" and any(
                    re.match(r"^[+-]\d+$", w) for w in words[1:])):
                cur = None  # cd - / pushd +N: directory unknown
                continue
            args = [w for w in words[1:] if not w.startswith("-")]
            cur = resolve(cur, args[0] if args else "~")
        elif head == "popd":
            cur = None
        elif os.path.basename(head) == "git":
            parsed = parse_git(words)
            if parsed is None:
                continue
            c_paths, sub, args = parsed
            if not is_forbidden(sub, args):
                continue
            base = cur
            for p in c_paths:
                base = resolve(base, p)
            if base is None or not os.path.isdir(base):
                continue
            try:
                if not is_main_tree(base):
                    continue
                root = git_out(base, "rev-parse", "--show-toplevel")[0]
            except Exception:
                continue
            shown = " ".join(shlex.quote(w) for w in words)[:120]
            return (
                "git-branch-guard: '%s' меняет ветку/HEAD в ОСНОВНОМ дереве %s. "
                "Основное дерево общее, там может лежать чужая незакоммиченная "
                "работа. Создай worktree (EnterWorktree для репо из cwd, иначе: "
                "git -C %s worktree add %s/.claude/worktrees/<name> -b <name> "
                "<base>) и работай в нём." % (shown, root, root, root))
    return None


def main():
    try:
        payload = json.load(sys.stdin)
        cmd = payload["tool_input"]["command"]
        cwd = payload.get("cwd")
        if not isinstance(cmd, str) or "git" not in cmd:
            return
        if not isinstance(cwd, str):
            return
        reason = scan(cmd, cwd)
    except Exception:
        return
    if reason:
        deny(reason)


if __name__ == "__main__":
    main()
