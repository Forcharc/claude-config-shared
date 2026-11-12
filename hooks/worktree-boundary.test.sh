#!/usr/bin/env bash
# Tests for worktree-boundary.sh. Run: bash hooks/worktree-boundary.test.sh
#
# The hook denies writes globally, so a regression here breaks every editing
# task in every project. Builds throwaway repos with linked worktrees and checks
# both guards against them -- nothing outside the temp dir is touched.

set -u

HOOK="$(cd "$(dirname "$0")" && pwd)/worktree-boundary.sh"
[ -x "$HOOK" ] || { echo "hook not executable: $HOOK"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Isolate git from the machine's own config and ignore files: with no
# core.excludesFile set git reads $XDG_CONFIG_HOME/git/ignore or
# ~/.config/git/ignore, which would leak into the ignored-file cases.
# HOME stays as is (the memory cases rely on it).
mkdir -p "$TMP/xdg"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 XDG_CONFIG_HOME="$TMP/xdg"

mkrepo() {
  local root="$1"
  mkdir -p "$root"
  git -C "$root" init -q
  git -C "$root" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$root" worktree add -q "$root/.claude/worktrees/wt" -b wt
}

REPO="$TMP/repo"; mkrepo "$REPO"; WT="$REPO/.claude/worktrees/wt"
OTHER="$TMP/other"; mkrepo "$OTHER"; OTHER_WT="$OTHER/.claude/worktrees/wt"

fails=0

# key: which tool_input field carries the path (file_path / notebook_path).
# extra_path: if set, PATH is overridden to this value for the hook invocation
# (used to simulate a missing `git`).
check() {
  desc="$1"; cwd="$2"; path="$3"; want="$4"; key="${5:-file_path}"; extra_path="${6:-}"
  # CLAUDE_CONFIG_DIR is blanked for the ordinary cases: the hook reads it, so a
  # suite run under the work profile would otherwise exercise a different code
  # path than one run under the default profile. Empty is equivalent to unset
  # for the hook (it expands with :- and then matches /* — neither matches an
  # empty value), and unlike `env -u` it needs no binary on PATH, which the
  # "git missing in PATH" case below strips down. check_ccd sets it on purpose.
  if [ -n "$extra_path" ]; then
    out=$(printf '{"cwd":"%s","tool_input":{"%s":"%s"}}' "$cwd" "$key" "$path" | PATH="$extra_path" CLAUDE_CONFIG_DIR= "$HOOK")
  else
    out=$(printf '{"cwd":"%s","tool_input":{"%s":"%s"}}' "$cwd" "$key" "$path" | CLAUDE_CONFIG_DIR= "$HOOK")
  fi
  got="allow"; [ -n "$out" ] && got="DENY"
  if [ "$got" = "$want" ]; then
    printf 'ok    %-46s %s\n' "$desc" "$got"
  else
    printf 'FAIL  %-46s %s (want %s)\n' "$desc" "$got" "$want"
    fails=$((fails + 1))
  fi
}

# Same as check(), with CLAUDE_CONFIG_DIR pinned to a given value — the config
# profile is not always ~/.claude, and per-project memory follows the profile.
check_ccd() {
  desc="$1"; cwd="$2"; path="$3"; want="$4"; ccd="$5"
  out=$(printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$cwd" "$path" | CLAUDE_CONFIG_DIR="$ccd" "$HOOK")
  got="allow"; [ -n "$out" ] && got="DENY"
  if [ "$got" = "$want" ]; then
    printf 'ok    %-46s %s\n' "$desc" "$got"
  else
    printf 'FAIL  %-46s %s (want %s)\n' "$desc" "$got" "$want"
    fails=$((fails + 1))
  fi
}

# Asserts on the deny REASON, not just the verdict: which path the hint offers
# is the whole point of the memory_root handling, and a wrong hint sends the
# reader to a path that gets denied again. Verdict-only checks cannot see that.
check_hint() {
  desc="$1"; cwd="$2"; path="$3"; want="$4"; ccd="$5"
  out=$(printf '{"cwd":"%s","tool_input":{"file_path":"%s"}}' "$cwd" "$path" | CLAUDE_CONFIG_DIR="$ccd" "$HOOK")
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  case "$reason" in
    *"$want"*) printf 'ok    %-46s hint\n' "$desc" ;;
    *) printf 'FAIL  %-46s hint missing %s\n    got: %s\n' "$desc" "$want" "$reason"; fails=$((fails + 1)) ;;
  esac
}

# Guard 1: a main working tree is read-only, whatever the cwd.
check "main tree file"               "$REPO" "$REPO/a.md"                  DENY
check "main tree, new nested file"   "$REPO" "$REPO/new/deep/a.kt"         DENY
check "main tree via traversal"      "$REPO" "$REPO/sub/../a.md"           DENY
check "main tree, cwd in worktree"   "$WT"   "$REPO/a.md"                  DENY
check "main tree via notebook_path"  "$REPO" "$REPO/a.ipynb"               DENY notebook_path
check "other repo's main tree"       "$WT"   "$OTHER/a.md"                 DENY

# Allowed: any linked worktree, scratch dirs, harness memory.
check "own worktree"                 "$WT"   "$WT/a.md"                    allow
check "worktree seen from main tree" "$REPO" "$WT/a.md"                    allow
check "other repo's worktree"        "$WT"   "$OTHER_WT/a.md"              allow
check "scratch .tmp in main tree"    "$REPO" "$REPO/.tmp/log.txt"          allow
check "harness memory"               "$WT"   "$HOME/.claude/projects/p/memory/a.md" allow

# Per-project memory under a non-default config profile (CLAUDE_CONFIG_DIR).
# PROFILE is deliberately outside any repo: without the carve-out these writes
# hit guard 2 (worktree -> outside git) and are denied, so allow/DENY here
# tells the two branches apart rather than reflecting some other rule.
PROFILE="$TMP/cfgprofile"
mkdir -p "$PROFILE/projects/p/memory/tech-debt"
check_ccd "profile memory"            "$WT" "$PROFILE/projects/p/memory/a.md"            allow "$PROFILE"
check_ccd "profile tech-debt entry"   "$WT" "$PROFILE/projects/p/memory/tech-debt/td.md" allow "$PROFILE"
check_ccd "profile with trailing /"   "$WT" "$PROFILE/projects/p/memory/a.md"            allow "$PROFILE/"
check_ccd "default profile still ok"  "$WT" "$HOME/.claude/projects/p/memory/a.md"       allow "$PROFILE"
check_ccd "profile set, unset var"    "$WT" "$PROFILE/projects/p/memory/a.md"            DENY  ""
check_ccd "profile set to a relative" "$WT" "$PROFILE/projects/p/memory/a.md"            DENY  "cfgprofile"
# normpath() returns an absolute path for any input, so a relative value must be
# rejected before it is normalized, or "a//b" would be promoted to "/a/b".
check_ccd "relative profile with //"  "$WT" "/a/b/projects/p/memory/x.md"                DENY  "a//b"
check_ccd "relative profile with ./"  "$WT" "/a/projects/p/memory/x.md"                  DENY  "./a"
# Targets the carve-out shape itself, not a repo path: a DENY on $REPO/a.md
# would come from guard 1 and stay green however "/" is handled here.
check_ccd "profile = /"               "$WT" "$PROFILE/projects/p/memory/a.md"          DENY  "/"
check_ccd "profile with inner //"     "$WT" "$PROFILE/projects/p/memory/a.md"          allow "$TMP//cfgprofile"
check_ccd "profile with a . segment"  "$WT" "$PROFILE/projects/p/memory/a.md"          allow "$TMP/./cfgprofile"
check_ccd "profile with a .. segment" "$WT" "$PROFILE/projects/p/memory/a.md"          allow "$TMP/x/../cfgprofile"
check_ccd "profile outside memory/"   "$WT" "$PROFILE/settings.json"                     DENY  "$PROFILE"
check_ccd "profile shape inside repo" "$WT" "$REPO/projects/p/memory/a.md"               DENY  "$PROFILE"

# The hint must always name a path that is actually honored. LOOSE sits outside
# any repo, so writing it from a worktree is denied by guard 2 and carries the
# hint. HOME is the fallback profile; PROFILE is honored when set absolutely.
LOOSE="$TMP/loose-hint.md"
check_hint "hint: profile honored"     "$WT" "$LOOSE" "$PROFILE/projects/*/memory/"      "$PROFILE"
check_hint "hint: trailing slash"      "$WT" "$LOOSE" "$PROFILE/projects/*/memory/"      "$PROFILE/"
check_hint "hint: relative rejected"   "$WT" "$LOOSE" "$HOME/.claude/projects/*/memory/" "cfgprofile"
check_hint "hint: root rejected"       "$WT" "$LOOSE" "$HOME/.claude/projects/*/memory/" "/"
check_hint "hint: unset"               "$WT" "$LOOSE" "$HOME/.claude/projects/*/memory/" ""
check_ccd  "root profile not honored"  "$WT" "/projects/p/memory/a.md"                   DENY "/"

# Guard 2: from a worktree, no writes outside version control.
check "worktree -> path outside git" "$WT"   "$TMP/loose.md"               DENY
check "main tree -> path outside git" "$REPO" "$TMP/loose.md"              allow

# Relative file_path must resolve against cwd before normalizing -- otherwise
# normpath() lexically collapses it as rooted at "/", which both defeats
# guard 1 (a relative path inside a main tree no longer looks like it's
# inside it) and false-denies guard 2 (a relative path legitimately inside
# the worktree no longer looks like it's inside it).
check "relative file_path in main tree" "$REPO" "a.md" DENY
check "relative file_path in worktree"  "$WT"   "a.md" allow

# The .tmp exemption must be anchored to the target's OWN repo root, not any
# bare "/.tmp/" substring on disk. A worktree's own .tmp stays allowed...
check "worktree own .tmp (anchored)"  "$WT" "$WT/.tmp/log.txt"            allow
# ...but a path outside ANY repo with a ".tmp" segment must no longer borrow
# the exemption -- before the fix this bypassed guard 2 entirely.
check "unanchored .tmp outside any repo" "$WT" "$TMP/outside/.tmp/evil.txt" DENY

# A symlink planted inside the worktree that points at a non-repo directory
# must not let guard 2's comparison believe the write still lands inside the
# worktree (normpath() is purely lexical and never follows symlinks).
mkdir -p "$TMP/secret"
ln -s "$TMP/secret" "$WT/escape"
check "worktree symlink escape" "$WT" "$WT/escape/evil.txt" DENY

# git missing from PATH must fail CLOSED (deny), unlike jq's fail-open above:
# git is guard 1's only signal, silently falling through would quietly
# disable the sole protection against main-tree writes.
BINDIR="$TMP/bin-no-git"
mkdir -p "$BINDIR"
ln -s "$(command -v jq)" "$BINDIR/jq"
check "git missing in PATH" "$REPO" "$REPO/a.md" DENY file_path "/bin:$BINDIR"

# --- empty cwd + relative file_path must fail CLOSED ----------------
# Without cwd, normpath() would lexically mis-root "a.md" as "/a.md", which
# defeats guard 1 (looks like it's outside every repo) and false-allows guard 2
# (exits early on empty cwd). Must be denied outright instead.
check "empty cwd + relative file_path" "" "a.md" DENY

# --- cheap ".git" prescreen must not misclassify a ".git" FILE ------
# A nested repo whose ".git" is a plain FILE (not a directory) -- same on-disk
# shape as both a linked worktree and a git submodule, built here via
# `git init --separate-git-dir` so it's a real, valid nested repo without
# needing network access or `git submodule add`. Unlike a linked worktree, its
# git dir has no 'gitdir' back-reference file, so it must still be denied as a
# main tree -- the cheap directory-only fast path must NOT mistake the mere
# presence of a ".git" file for "not a repo" and let this slip through.
SUBREPO="$REPO/sub"
mkdir -p "$REPO/.git/modules"
git init -q --separate-git-dir="$REPO/.git/modules/sub" "$SUBREPO" >/dev/null
git -C "$SUBREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
check "nested repo, .git is a file (submodule-like)" "$WT" "$SUBREPO/a.md" DENY

# --- .tmp-shaped path outside any repo, main-tree cwd -------
# Exercises the cheap "no .git anywhere -> skip guard 1 entirely" fast path
# together with guard 2's own main-tree cwd exemption -- a ".tmp" path
# segment with no enclosing repo at all must still just be a normal allow,
# not accidentally borrow the repo-scratch exemption or get misrouted.
check "main tree cwd, .tmp path outside any repo" "$REPO" "$TMP/outside/.tmp/evil.txt" allow

# --- symlink under .tmp escaping into ANOTHER repo ----------
# The cheap directory-form ".git" classification must still resolve symlinks
# correctly when computing repo_root for the .tmp anchor check: a symlink
# planted under the worktree's own .tmp/ that points into a DIFFERENT repo
# must not be treated as "own .tmp" (repo_root would physically resolve to
# the OTHER repo, not this one) -- and must still be caught as a write into
# that other repo's main tree.
mkdir -p "$WT/.tmp"
ln -s "$OTHER" "$WT/.tmp/other-repo"
check "worktree .tmp symlink into another repo's main tree" "$WT" "$WT/.tmp/other-repo/evil.txt" DENY

# --- 8b4dc6a review round 1, Bug A: fake ".git" DIRECTORY nested inside a ---
# real repo must not bypass the gitdir-file discriminator. The cheap walk-up
# only confirms a directory literally named ".git" -- it does not by itself
# prove the directory is a real git dir. Before the fix, the code trusted it
# unconditionally and then asked "$git_dir/gitdir" (a check only meaningful
# for a git-CONFIRMED git_dir) whether it looked like a linked worktree; a
# throwaway "gitdir" file dropped inside such a directory made the whole
# thing look like an "unambiguous linked worktree" and slipped past guard 1
# entirely, even though the target is really inside REPO's main tree.
mkdir -p "$REPO/fakewt/.git"
printf 'garbage' > "$REPO/fakewt/.git/gitdir"
check "fake .git DIR containing a gitdir file, nested in main tree" "$REPO" "$REPO/fakewt/file.txt" DENY

# --- 8b4dc6a review round 1, Bug B: directory merely NAMED ".git", not a ---
# real repo, must not be treated as an unconditional main tree. Before the
# fix, the cheap walk-up trusted ANY directory called ".git" as "unambiguous
# main tree" without git ever confirming it is actually a repository -- a
# plain empty directory happening to be named ".git" (test fixture, stray
# scratch dir from some other tool) produced a false-positive DENY where the
# real `git rev-parse` (both before this optimization and after this fix)
# correctly says "not a git repository" and allows the write.
mkdir -p "$TMP/fakegit2/.git"
check "bogus .git dir with no HEAD -- not a real repo (sanity check)" "$TMP/fakegit2" "$TMP/fakegit2/note.md" allow

# --- 8b4dc6a review round 1, Bug C: literal newline inside file_path must ---
# not truncate the field during parsing. `read` unconditionally stops at the
# first LF byte regardless of IFS -- unlike \x1f, a real newline embedded in
# a JSON string value (\n escape) survives JSON decoding as an actual LF
# byte. Before the fix, that LF prematurely ended `read`'s line, file_path
# came out empty, and `[ -z "$file_path" ] && exit 0` allowed the write
# without ever reaching guard 1 -- a full main-tree-guard bypass. The jq
# gsub now neutralizes any embedded LF into the two printable characters
# "\" + "n" before the \x1f-separated join, so `read` sees the whole field.
check "main tree, literal newline embedded in file_path" "$REPO" '\na.md' DENY

# --- security review 05c45c0: control byte mid-path defeats the shared -----
# "nearest existing ancestor" probe, not just the truncate-to-empty case ----
# The fix above (Bug C) only escaped an embedded "\n" so `read` wouldn't
# truncate the field to empty. It did not stop a raw control byte from making
# ONE path segment nonexistent on disk -- the probe/normpath helper shared by
# both guards then walks straight past that segment (and everything after it,
# including a real repo that should have been the target) and lands on some
# harmless ancestor further up, which `git rev-parse` honestly reports as
# "not a repo". cwd is deliberately NOT worktree-shaped here (no
# ".claude/worktrees/" segment) so guard 2 would also short-circuit allow --
# this reproduces the exact silent-ALLOW chain from the finding, not just a
# guard-2 corner case.
check "main tree via control char mid-path (probe-skip bypass)" \
  "$TMP" '/nonexistent_prefix\n'"$REPO"'/a.md' DENY

# A control byte in cwd (not file_path) must be caught the same way -- cwd
# feeds guard 2's own comparisons and (for a relative file_path) gets
# prepended before normalizing, so it needs the same fail-closed treatment.
# file_path here is otherwise a perfectly ordinary path inside the worktree,
# which would allow on its own -- isolating that the deny comes from cwd.
check "control char (tab) embedded in cwd" 'cwd\twith\ttab' "$WT/a.md" DENY

# Control sanity check: an ordinary path with spaces and non-ASCII characters
# is not control-byte content and must stay allowed -- the new gate must not
# over-match on unicode or whitespace, only on actual control bytes.
check "unicode + spaces path stays allowed" "$WT" "$WT/имя файла with spaces.md" allow

# --- merge-conflict carve-out: resolving a conflict happens in the main -----
# tree by definition (that's where the merge lives), so guard 1 must let a
# write land on a path `git ls-files -u` currently reports as unmerged. Own
# repo, not REPO above, so the merge history here doesn't tangle with REPO's
# unrelated submodule/fakewt/newline fixtures built earlier in this file.
MREPO="$TMP/mergerepo"
mkdir -p "$MREPO"
git -C "$MREPO" init -q
printf 'base\n' > "$MREPO/f.md"
printf 'other\n' > "$MREPO/other.md"
git -C "$MREPO" add f.md other.md
git -C "$MREPO" -c user.email=t@t -c user.name=t commit -q -m base
git -C "$MREPO" checkout -q -b conflict-branch
printf 'branch content\n' > "$MREPO/f.md"
git -C "$MREPO" -c user.email=t@t -c user.name=t commit -q -am branch
git -C "$MREPO" checkout -q -
printf 'main content\n' > "$MREPO/f.md"
git -C "$MREPO" -c user.email=t@t -c user.name=t commit -q -am main
git -C "$MREPO" -c user.email=t@t -c user.name=t merge -q conflict-branch >/dev/null 2>&1

# The conflicted path itself: allowed while unresolved.
check "merge conflict, conflicted path" "$MREPO" "$MREPO/f.md" allow

# A second, unrelated tracked file in the SAME repo during the SAME open
# merge: `git ls-files -u` reports no unmerged entries for it, so it must
# still be denied -- the carve-out is scoped per-path, it does not widen to
# "the whole repo while a merge is open".
check "merge conflict, unrelated file same repo" "$MREPO" "$MREPO/other.md" DENY

# --- security review d2b525b: pathspec-glob injection --------------------
# `git ls-files -u -- <pathspec>` interprets a bare *, ?, or [...] as an
# fnmatch pattern by default (no leading ":(glob)" needed) -- passing the
# write target straight through as a pathspec let it match ANY unmerged
# path in the repo whose name happens to fit the pattern, not just the
# literal target. None of these four names is f.md itself and none of them
# has any unmerged entry of its own -- each must be denied exactly like the
# plain "other.md" case above, even though every one of them is a valid
# fnmatch pattern that DOES match the real conflicted "f.md" if handed to
# git as a pathspec instead of compared as a literal string.
check "merge conflict, glob-named file 'f*' (unrelated)"   "$MREPO" "$MREPO/f*"   DENY
check "merge conflict, glob-named file '*' (unrelated)"    "$MREPO" "$MREPO/*"    DENY
check "merge conflict, glob-named file '[f]*' (unrelated)" "$MREPO" "$MREPO/[f]*" DENY
check "merge conflict, glob-named file 'f.m?' (unrelated)" "$MREPO" "$MREPO/f.m?" DENY

# --- logic review d2b525b: case-insensitive filesystem false-deny --------
# `git ls-files -u` always matches case-sensitively, but macOS/APFS (and
# HFS+) default to a case-insensitive volume format -- the filesystem itself
# does not distinguish "f.md" from "F.MD", they are the same file. Requesting
# the identical conflicted file spelled with different case (an easy
# accident: some other tool or `git status` output handed back a
# differently-cased path for the same inode) must resolve the same way the
# filesystem would.
#
# The expected verdict is computed by asking the filesystem the exact same
# question the hook itself now asks (`-ef`, same device+inode) instead of
# reading `core.ignorecase` -- that config is a mutable git setting, not a
# fact about the disk underneath the repo, and the hook no longer trusts it
# either (security review 698e23a, finding 1). This stays correct on a
# case-sensitive filesystem too (e.g. a typical Linux ext4 checkout), without
# turning case-insensitive matching into a way to widen the exemption.
case_want="DENY"
[ "$MREPO/F.MD" -ef "$MREPO/f.md" ] && case_want="allow"
check "merge conflict, same file different case (F.MD)" "$MREPO" "$MREPO/F.MD" "$case_want"

# --- security review 698e23a, finding 1: Unicode-confusable case-fold ------
# bypass -- bash `nocasematch` folded plain "i" (U+0069) and the distinct
# Turkish "İ" (U+0130) together even though they are two different files
# with two different inodes on APFS. "ifile.md" is the ONLY conflicted path
# here; "İfile.md" is a brand-new, never-conflicted target name that merely
# LOOKS like a case-variant of it under bash's (but not the filesystem's)
# folding rules. This must stay denied -- if it doesn't, the case-fold
# bypass is back. Own repo/history -- MREPO's own f.md conflict above is
# still unresolved at this point in the script (its `git add` happens
# further down), and checking out a new branch or committing on top of an
# unresolved conflict is refused by git itself.
IREPO="$TMP/irepo"
mkdir -p "$IREPO"
git -C "$IREPO" init -q
printf 'base\n' > "$IREPO/ifile.md"
git -C "$IREPO" add ifile.md
git -C "$IREPO" -c user.email=t@t -c user.name=t commit -q -m base
git -C "$IREPO" checkout -q -b iconflict-branch
printf 'branch\n' > "$IREPO/ifile.md"
git -C "$IREPO" -c user.email=t@t -c user.name=t commit -q -am branch
git -C "$IREPO" checkout -q -
printf 'main\n' > "$IREPO/ifile.md"
git -C "$IREPO" -c user.email=t@t -c user.name=t commit -q -am main
git -C "$IREPO" -c user.email=t@t -c user.name=t merge -q iconflict-branch >/dev/null 2>&1
check "merge conflict on ifile.md, write targets confusable İfile.md (exploit)" \
  "$IREPO" "$IREPO/İfile.md" DENY

# --- security review 698e23a, finding 2: NFC/NFD Unicode-normalization -----
# false-deny -- git stores whatever byte sequence the file was created with
# (APFS itself does not normalize bytes on disk), so an accented filename
# tracked as precomposed NFC ("é" = U+00E9, single codepoint) must still be
# recognized when the SAME conflicted file is addressed via its decomposed
# NFD spelling ("e" + U+0301 combining acute, two codepoints) -- a plausible
# alias some other tool or copy-paste could hand back. APFS's default volume
# format is normalization-insensitive (an NFD lookup resolves to the NFC
# dirent's inode), so `-ef` correctly recognizes them as the same file. Own
# repo/history, same reason as IREPO above.
# "é.md" spelled two ways, in raw UTF-8 bytes -- no external tool needed:
#   NFC (precomposed): U+00E9 = 0xC3 0xA9
#   NFD (decomposed):  'e' (0x65) + U+0301 COMBINING ACUTE ACCENT = 0xCC 0x81
NFC_NAME=$(printf '\xc3\xa9.md')
NFD_NAME=$(printf 'e\xcc\x81.md')
NFCREPO="$TMP/nfcrepo"
mkdir -p "$NFCREPO"
git -C "$NFCREPO" init -q
printf 'base\n' > "$NFCREPO/$NFC_NAME"
git -C "$NFCREPO" add "$NFC_NAME"
git -C "$NFCREPO" -c user.email=t@t -c user.name=t commit -q -m base
git -C "$NFCREPO" checkout -q -b nfcconflict-branch
printf 'branch\n' > "$NFCREPO/$NFC_NAME"
git -C "$NFCREPO" -c user.email=t@t -c user.name=t commit -q -am branch
git -C "$NFCREPO" checkout -q -
printf 'main\n' > "$NFCREPO/$NFC_NAME"
git -C "$NFCREPO" -c user.email=t@t -c user.name=t commit -q -am main
git -C "$NFCREPO" -c user.email=t@t -c user.name=t merge -q nfcconflict-branch >/dev/null 2>&1
check "merge conflict on NFC filename, write addresses it via NFD spelling" \
  "$NFCREPO" "$NFCREPO/$NFD_NAME" allow

# --- security review 698e23a, requirement 3: modify/delete conflict where --
# the working copy has been deleted from disk -- `-ef` cannot stat either
# side in this shape (nothing to compare), so this only works at all because
# the literal-string comparison is tried FIRST and never needs `-ef` to
# begin with: the write addresses the conflicted path by its one true
# `git ls-files -u` spelling, same as before this fix. Own repo/history so it
# doesn't tangle with MREPO's other fixtures.
DELREPO="$TMP/delrepo"
mkdir -p "$DELREPO"
git -C "$DELREPO" init -q
printf 'base\n' > "$DELREPO/f.md"
git -C "$DELREPO" add f.md
git -C "$DELREPO" -c user.email=t@t -c user.name=t commit -q -m base
git -C "$DELREPO" checkout -q -b modbranch
printf 'modified\n' > "$DELREPO/f.md"
git -C "$DELREPO" -c user.email=t@t -c user.name=t commit -q -am mod
git -C "$DELREPO" checkout -q -
git -C "$DELREPO" rm -q f.md
git -C "$DELREPO" -c user.email=t@t -c user.name=t commit -q -m del
git -C "$DELREPO" -c user.email=t@t -c user.name=t merge -q modbranch >/dev/null 2>&1
# git leaves the modified content in the tree by default on modify/delete --
# remove it to reproduce "resolution in progress, working copy gone" before
# `git add`/`git rm` finalizes anything.
rm -f "$DELREPO/f.md"
check "modify/delete conflict, working copy absent from disk, write recreates it" \
  "$DELREPO" "$DELREPO/f.md" allow

# `git add` records the resolution: the path's unmerged (stage 1/2/3) entries
# collapse back to a single ordinary stage-0 entry, `ls-files -u` goes back to
# empty, and the exemption expires on its own -- no separate "merge finished"
# signal needed.
git -C "$MREPO" add "$MREPO/f.md"
check "merge conflict, resolved + staged path" "$MREPO" "$MREPO/f.md" DENY

# --- logic review d2b525b: directory-prefix match -------------------------
# `git ls-files -u -- <path>` (no glob needed at all) also matches an entire
# subtree when <path> is a directory that CONTAINS an unmerged file -- so a
# write request for the CONTAINING DIRECTORY of a conflicted file used to
# borrow the file's own exemption, even though a directory can never itself
# be "resolved" the way a conflicted blob is. Own repo (own history), so
# this doesn't tangle with MREPO's fixtures above.
DREPO="$TMP/dirrepo"
mkdir -p "$DREPO/sub"
git -C "$DREPO" init -q
printf 'base\n' > "$DREPO/sub/a.md"
git -C "$DREPO" add sub/a.md
git -C "$DREPO" -c user.email=t@t -c user.name=t commit -q -m base
git -C "$DREPO" checkout -q -b conflict-branch
printf 'branch content\n' > "$DREPO/sub/a.md"
git -C "$DREPO" -c user.email=t@t -c user.name=t commit -q -am branch
git -C "$DREPO" checkout -q -
printf 'main content\n' > "$DREPO/sub/a.md"
git -C "$DREPO" -c user.email=t@t -c user.name=t commit -q -am main
git -C "$DREPO" -c user.email=t@t -c user.name=t merge -q conflict-branch >/dev/null 2>&1

check "merge conflict, conflicted path (sub/a.md)"          "$DREPO" "$DREPO/sub/a.md" allow
check "merge conflict, containing directory of conflicted path (sub)" "$DREPO" "$DREPO/sub" DENY

# Ignored-file carve-out: a path git ignores is allowed in a main tree, a
# tracked one is not.
IGREPO="$TMP/igrepo"; mkrepo "$IGREPO"
IGWT="$IGREPO/.claude/worktrees/wt"
printf '*.log\nbuild/\nsecret.txt\ntracked-ign.txt\n' > "$IGREPO/.gitignore"
printf 'x\n' > "$IGREPO/tracked-ign.txt"
git -C "$IGREPO" add .gitignore
git -C "$IGREPO" add -f tracked-ign.txt
git -C "$IGREPO" -c user.email=t@t -c user.name=t commit -q -m ign
printf 'x\n' > "$IGREPO/ign.log"
mkdir -p "$IGREPO/sub" "$IGREPO/real"
ln -s real "$IGREPO/sl"
ln -s "$IGREPO" "$TMP/ig-alias"
mkdir -p "$IGREPO/inner"
git -C "$IGREPO/inner" init -q
printf '*.inner\n' > "$IGREPO/inner/.gitignore"
printf '*.excl\n' >> "$IGREPO/.git/info/exclude"
printf '*.glob\n' > "$TMP/global-ignore"
printf '[core]\n\texcludesFile = %s\n' "$TMP/global-ignore" > "$TMP/gitconfig-global"
OIG="$TMP/otherig"; mkrepo "$OIG"
printf '*.log\n' > "$OIG/.gitignore"

check "ignored, existing file"         "$IGREPO" "$IGREPO/ign.log"            allow
check "ignored, new file"              "$IGREPO" "$IGREPO/new.log"            allow
check "ignored dir, missing subdirs"   "$IGREPO" "$IGREPO/build/a/b.o"        allow
check "ignored file, missing subdirs"  "$IGREPO" "$IGREPO/x/y/z.log"          allow
check "not ignored stays denied"       "$IGREPO" "$IGREPO/a.md"               DENY
check "force-added ignored stays denied" "$IGREPO" "$IGREPO/tracked-ign.txt"  DENY
check "ignored, cwd in worktree"       "$IGWT"   "$IGREPO/ign.log"            allow
check "ignored, relative path"         "$IGREPO" "ign.log"                    allow
check "not ignored, relative path"     "$IGREPO" "a.md"                       DENY
check "ignored via .."                 "$IGREPO" "$IGREPO/sub/../ign.log"     allow
check "ignored via symlink to repo"    "$IGREPO" "$TMP/ig-alias/ign.log"      allow
check "nested repo, its own ignore"    "$IGREPO" "$IGREPO/inner/x.inner"      allow
check "nested repo, outer ignore only" "$IGREPO" "$IGREPO/inner/x.log"        DENY
check "symlink inside repo denies" "$IGREPO" "$IGREPO/sl/x.log"              DENY
GIT_CONFIG_GLOBAL="$TMP/gitconfig-global" \
check "global excludesFile"            "$IGREPO" "$IGREPO/x.glob"             allow
check "global pattern without config"  "$IGREPO" "$IGREPO/x.glob"             DENY
check ".git/info/exclude"              "$IGREPO" "$IGREPO/x.excl"             allow
check "other repo ignored, from wt"    "$IGWT"   "$OIG/x.log"                 allow
# A worktrees/ pattern would also cover a ghost path under .claude/worktrees;
# harmless, since such a path is in no branch either.
printf 'worktrees/\n' >> "$IGREPO/.git/info/exclude"
check "ignored worktrees/ ghost path"  "$IGREPO" "$IGREPO/.claude/worktrees/ghost/x" allow
check "ignored pattern, path inside .git" "$IGREPO" "$IGREPO/.git/worktrees/x/HEAD" DENY
printf 'x\n' > "$IGREPO/tracked.md"
git -C "$IGREPO" add tracked.md
ln -s tracked.md "$IGREPO/lnk.log"
check "ignored symlink to tracked file" "$IGREPO" "$IGREPO/lnk.log" DENY

echo
if [ "$fails" -eq 0 ]; then echo "all scenarios passed"; else echo "failures: $fails"; fi
exit "$fails"
