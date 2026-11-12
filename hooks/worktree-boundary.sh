#!/usr/bin/env bash
# PreToolUse hook for Write/Edit/MultiEdit/NotebookEdit. Two independent guards:
#
#   1. Main-tree guard: refuse any write into the MAIN working tree of a git
#      repository. Every file-editing task belongs in a worktree — no size
#      exemption, not even a one-line typo fix (see ~/.claude/CLAUDE.md). One
#      narrow, self-expiring carve-out: a path that `git ls-files -u` reports
#      as currently unmerged (a live merge conflict) stays allowed, because
#      resolving it in place is exactly what finishing that merge requires;
#      the exemption disappears the moment the conflict is staged. A second
#      narrow carve-out: a path that git ignores (`git check-ignore`) stays
#      allowed, because it is in no branch and a worktree cannot isolate it
#      (see the carve-out below for what stays denied).
#   2. Worktree-boundary guard: when running inside a worktree, refuse writes
#      that land outside any git worktree. Prevents leaks from delegated agents
#      that carry absolute paths from elsewhere into their tool calls.
#
# Writes into a *different* linked worktree stay allowed: editing ~/.claude from
# a project session is done through a manually created worktree of that repo,
# and guard 1 already keeps every main tree off limits.
#
# Guard 2 compares against the *physically resolved* target path (symlinks in
# the existing prefix followed via `cd -P`), so a symlink planted inside a
# worktree cannot point outside it and slip past the string-prefix check. git
# itself already follows symlinks when probing for a repo, so guard 1 needs no
# extra resolution of its own.
#
# Guard 1 tries a cheap bash-only classification (no fork) before ever calling
# git — this hook runs on every single Write/Edit/MultiEdit/NotebookEdit in
# every project, so an unconditional `git` fork on the common allow path is a
# measurable, purely additive tax. `git` is still the fallback for anything
# the cheap check can't classify with full confidence: it is never removed as
# the ultimate authority, only deferred to when actually needed.
#
# Threat model: PreToolUse only fires for the four tools named above. It has
# no visibility into (and no way to gate) a `Bash` call, so it cannot stop
# something that already runs a shell from writing anywhere a shell can write
# — `cat > file`, `sed -i`, `git commit --allow-empty -m "$(cat evil)"` in the
# main tree are all completely outside what this hook ever sees. What it
# guards against is the ORDINARY, unintentional case: a tool call whose
# `file_path` happens to resolve into a main tree because of a wrong `cwd`, a
# stale absolute path carried over from another task, or a delegated agent
# that inherited the wrong working directory — not a determined adversary who
# already has Bash access and has decided to bypass it on purpose. Any fix
# here should be read with that scope in mind: closing an accidental-collision
# gap (a legitimate merge-conflict path getting the wrong verdict) is exactly
# what this hook is for; treating it as a defense against a deliberate,
# Bash-capable attacker overstates what a PreToolUse hook can ever provide.
# Branch changes made through Bash are caught separately by the sibling
# hooks/git-branch-guard.py; writing files through a shell stays outside both.

set -eu

# Fail open if jq is missing — safer than breaking every Write/Edit.
command -v jq >/dev/null 2>&1 || exit 0

deny() {
  jq -nc --arg reason "$1" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
  exit 0
}

# Fail CLOSED if git is missing — unlike jq above, git is this hook's only way
# to tell a main tree from a worktree. Silently falling through to guard 2
# would quietly disable the sole protection against main-tree writes.
command -v git >/dev/null 2>&1 || \
  deny "worktree-boundary: git not found in PATH, cannot verify worktree boundaries. Install/restore git before writing."

payload=$(cat)

# Any control byte (0x01-0x1f, or 0x7f/DEL) inside cwd or file_path is refused
# outright, before anything else touches these fields. An earlier version of
# this hook tried to *carry* an embedded "\n" through safely by escaping it
# into the two printable characters "\" + "n" before splitting fields with
# `read` -- that closed the truncate-to-empty bypass (an unescaped LF made
# `read` stop early, file_path came out empty, and the
# `[ -z "$file_path" ] && exit 0` check right below let the write through
# without ever reaching either guard). But escaping only that one case did not
# close the more general problem: a literal control byte sitting inside ONE
# segment of an otherwise-valid absolute path is not a "/" to the filesystem,
# so the segment it's part of simply doesn't exist on disk. The "nearest
# existing ancestor" probe both guards share below then walks straight past
# that segment -- and everything after it, including a real repo that should
# have been the write's target -- and lands on some harmless directory further
# up the tree, which `git rev-parse` then (honestly) reports as "not a repo".
# No legitimate harness call ever puts a raw control byte in cwd or file_path,
# so there is nothing here worth carefully preserving -- fail closed instead
# of normalizing/resolving a path that cannot be trusted to mean what it looks
# like it means. (0x00 is included in the class below for completeness, but
# can never actually reach this check: `payload=$(cat)` above already can't
# hold a NUL byte in a bash variable, so any NUL is silently dropped before jq
# even sees the payload.)
#
# The class is built from raw printf-emitted bytes (the same technique already
# used just below for the \x1f field separator) rather than a \uXXXX/\xXX
# escape spelled out in the jq program text, so this does not depend on which
# escape syntax jq's regex engine happens to support.
cntrl_lo=$(printf '\1')
cntrl_hi=$(printf '\37')
cntrl_del=$(printf '\177')
cntrl_re="[${cntrl_lo}-${cntrl_hi}${cntrl_del}]"

# Single jq pass computes the control-byte verdict together with cwd and
# file_path, all three joined by \x1f (unit separator), not a real tab/@tsv.
# Tab is an "IFS whitespace" character to bash's `read` even when IFS is set
# to just "\t" -- a leading empty field (empty cwd) gets silently swallowed as
# leading whitespace instead of read as an empty first field, shifting
# file_path into cwd and leaving file_path empty. \x1f is not whitespace, so
# `read` preserves empty fields exactly as jq emitted them.
#
# The verdict is emitted FIRST, ahead of cwd and file_path. A literal newline
# embedded in either field still makes `read` stop consuming at that byte (the
# one control character `read` treats as a line terminator regardless of
# IFS), same as before -- but by the time that happens the verdict has already
# been fully read, since it sits earlier in the stream than the byte that cuts
# the line short. Only the two fields after it can end up truncated, and
# is_bad="true" makes that moot: we deny below before ever looking at them
# again.
IFS=$'\37' read -r is_bad cwd file_path < <(printf '%s' "$payload" | \
  jq -r --arg re "$cntrl_re" --arg sep "$(printf '\37')" \
  '[(.cwd // ""), (.tool_input.file_path // .tool_input.notebook_path // "")] as $f
   | ([($f | map(test($re)) | any | tostring)] + $f) | join($sep)')

[ "$is_bad" = "true" ] && \
  deny "worktree-boundary: cwd or file_path contains a control character (a byte below 0x20, or 0x7f/DEL) -- refusing to trust or normalize a path that isn't plain text. Remove the stray control byte (e.g. an embedded newline) and retry with a plain path."

[ -z "$file_path" ] && exit 0

# Resolve a relative file_path against cwd before normalizing. Without this,
# normpath() below lexically collapses a relative path as if it were rooted at
# "/" (e.g. "notes.md" -> "/notes.md"), which both defeats guard 1 (a relative
# path inside the main tree no longer looks like it's inside the main tree)
# and false-denies guard 2 (a relative path legitimately inside the worktree
# no longer looks like it's inside the worktree).
#
# If cwd is missing/empty, a relative file_path cannot be safely resolved at
# all -- fail CLOSED rather than let normpath() silently mis-root it as "/"
# (which would make it look like it's outside every repo and slip past BOTH
# guards: guard 1 finds no repo at "/", guard 2 exits early on empty cwd).
# The harness always populates cwd in normal operation; this only fires for a
# payload shape that should never happen, and denying is the safe default.
case "$file_path" in
  /*) ;;
  *)
    if [ -n "$cwd" ]; then
      file_path="$cwd/$file_path"
    else
      deny "worktree-boundary: relative file_path '$file_path' with no cwd in the hook payload -- cannot safely resolve where this write would land. Refusing."
    fi
    ;;
esac

# Normalize file_path to defeat path traversal (../ and ./).
normpath() {
  local path="$1" seg out=""
  local -a raw=() parts=()
  # Split on "/" WITHOUT ever letting bash treat a resulting segment as a
  # pathname-expansion pattern. The previous form here was `for seg in
  # $path` with `IFS=/` -- unquoted word-splitting is ALSO subject to
  # filename generation for every word it produces: if a segment contains a
  # glob metacharacter (*, ?, [...]) that happens to match real filenames in
  # the CURRENT WORKING DIRECTORY OF THE HOOK PROCESS ITSELF (not the JSON
  # payload's cwd -- an unrelated, uncontrolled bit of state), bash silently
  # substituted those on-disk names in place of the literal segment,
  # producing a $normalized that could differ from the path actually being
  # written. `read -ra` performs the same IFS-based splitting but a `read`
  # builtin never performs pathname expansion on what it reads, so every
  # element of `raw` is always exactly the literal substring of $path.
  IFS=/ read -ra raw <<< "$path"
  for seg in ${raw[@]+"${raw[@]}"}; do
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

# Harness per-project memory (auto-memory, agent-results, tech-debt records):
# agents spawned from inside a worktree legitimately write reports and debt
# entries there, whichever repo the task itself lives in. Note this is the
# config repo's own MAIN tree — the carve-out is what makes these writes
# possible at all, and it is deliberate: this data is addressed by a fixed
# path that every session and worktree shares, so routing it through a branch
# would put it where the next session cannot find it. Some of it may be tracked
# (MEMORY.md and the journals), depending on the repo's .gitignore;
# agent-results/ and tech-debt/ are typically gitignored.
# Anchored to an absolute prefix so a rogue projects/*/memory/ path inside
# another repo cannot slip through.
#
# Two roots, because the config profile is not always ~/.claude: the harness
# sets CLAUDE_CONFIG_DIR (an alternate config profile points it elsewhere),
# and per-project memory resolves under whichever profile is active. Matching
# only the default root denied writes that the local techdebt mode is supposed
# to make, and agents worked around it by shelling out — which defeats the
# guard instead of satisfying it.
case "$normalized" in
  "$HOME"/.claude/projects/*/memory|"$HOME"/.claude/projects/*/memory/*) exit 0 ;;
esac
# The profile goes through the same normalization as the target: normalized has
# no trailing slash, no doubled slash and no "." / ".." left in it, so any of
# those in the profile value would fail to match and silently restore the very
# denial this branch removes — with the deny message then suggesting the same
# broken path, which makes the block self-perpetuating. The case guard keeps
# the common, already-canonical value fork-free; normpath only runs when the
# value actually carries something to fix.
# Only a profile that was actually honored may appear in the deny hint below:
# naming a value the hook just rejected sends the reader to a path that will be
# refused again, which is how the earlier trailing-slash bug perpetuated itself.
memory_root="$HOME/.claude"
config_dir="${CLAUDE_CONFIG_DIR:-}"
case "$config_dir" in
  /*)
    # Absoluteness is decided BEFORE normalization, not after: normpath returns
    # an absolute path for whatever it is given ("a//b" comes back as "/a/b"),
    # so normalizing first would promote a relative value into an absolute one
    # and hand the carve-out to a root nobody configured. A relative profile is
    # simply not honored — it cannot address the same file the target does.
    case "$config_dir" in
      *//*|*/|*/./*|*/../*|*/.|*/..) config_dir=$(normpath "$config_dir") ;;
    esac
    # "/" is not a profile. It survives the absoluteness check (as does anything
    # normalizing to it: "//", "/.", "/.."), but the pattern built from it would
    # carry a doubled slash, which normalized never contains — the carve-out
    # would be unreachable while the deny hint still advertised it. Treated as
    # unconfigured, exactly like a relative value.
    if [ "$config_dir" != "/" ]; then
      memory_root="$config_dir"
      case "$normalized" in
        "$config_dir"/projects/*/memory|"$config_dir"/projects/*/memory/*) exit 0 ;;
      esac
    fi
    ;;
esac

# Nearest existing ancestor directory of the target — the file itself may not
# exist yet (Write of a new file, possibly in a new directory). Shared by both
# guards below: guard 1 probes it for a git repo; guard 2 (if reached) uses it
# as the anchor for physical (symlink-resolved) comparison.
probe="$normalized"
while [ ! -d "$probe" ] && [ "$probe" != "/" ]; do
  probe="${probe%/*}"
  [ -z "$probe" ] && probe="/"
done

# Physically resolve a path rooted at an existing anchor directory, following
# symlinks in the anchor itself (via `cd -P`) without requiring the remaining
# (possibly nonexistent) tail to exist. Pure bash — no external fork.
physical_resolve() {
  local target="$1" anchor="$2" resolved suffix
  resolved=$(cd -P "$anchor" 2>/dev/null && pwd -P) || resolved="$anchor"
  if [ "$anchor" = "/" ]; then
    suffix="${target#/}"
    [ -n "$suffix" ] && suffix="/$suffix"
  else
    suffix="${target#"$anchor"}"
  fi
  if [ "$resolved" = "/" ]; then
    printf '%s' "${suffix:-/}"
  else
    printf '%s' "$resolved$suffix"
  fi
}

# normpath() above is purely lexical and never follows symlinks, and git's own
# rev-parse output IS symlink-resolved (e.g. macOS /var -> /private/var) — so
# both the guard-1 .tmp anchor and the guard-2 worktree-boundary comparison
# need $normalized resolved the same way to stay comparable. This forks a
# subshell (`cd -P`), so it's computed lazily via resolve_real_normalized()
# only in the branches that actually need it, instead of unconditionally for
# every path (most paths never touch a .tmp/ segment and never reach guard 2
# at all, since guard 1 already decided them).
real_normalized=""
resolve_real_normalized() {
  [ -n "$real_normalized" ] && return 0
  real_normalized=$(physical_resolve "$normalized" "$probe")
}

# --- Guard 1: main working tree of a git repo is read-only ------------------
#
# Cheap bash-only pass first (no fork): walk up from $probe looking for a
# ".git" entry.
#   - a DIRECTORY: by git's own worktree implementation a linked worktree's
#     ".git" is ALWAYS a plain file (never a directory), so a directory can
#     never BE a linked worktree — but bash finding a directory literally
#     named ".git" is not the same as git confirming it is actually a repo
#     (a stray test fixture or scratch directory can be named ".git" too).
#     A cheap sanity check below (HEAD file present) decides whether to trust
#     it outright or defer to git.
#   - a FILE (linked worktree, git submodule, or a nonstandard layout), or no
#     ".git" found anywhere up to "/": ambiguous — defer to the real `git
#     rev-parse` below, exactly as this hook always has. A bare "not found"
#     could still theoretically be a repo via GIT_DIR/GIT_CEILING_DIRECTORIES
#     overrides or a bare-repo layout, so it is NOT treated as a confident
#     "no repo" answer on its own — the env vars are neutralized below so the
#     cheap walk and the git fallback see the same reality, but the fallback
#     call still runs to cover the remaining edge cases (bare repo etc.).
unset GIT_DIR GIT_WORK_TREE GIT_CEILING_DIRECTORIES 2>/dev/null || true

git_dir=""
repo_root=""
cheap_dir_git=0
walk="$probe"
while :; do
  if [ -d "$walk/.git" ]; then
    git_dir="$walk/.git"
    repo_root="$walk"
    cheap_dir_git=1
    break
  fi
  [ -e "$walk/.git" ] && break   # ambiguous (file/other) entry -- fall back
  [ "$walk" = "/" ] && break
  walk="${walk%/*}"
  [ -z "$walk" ] && walk="/"
done

# Sanity check the cheap directory-form match before trusting it (no fork --
# just a stat). A real git dir always has a HEAD file; a directory that merely
# happens to be named ".git" (test fixture, scratch dir made by some other
# tool) does not. Without this, such a directory would be treated as an
# unconditional main tree below, even nested inside an otherwise legitimate
# worktree -- and conversely, blindly trusting it also skipped the "is this
# actually a linked worktree" discriminator later, which only makes sense for
# a git_dir git itself has confirmed. If the check fails, forget this match
# entirely and fall through to the real `git rev-parse` below, which performs
# its own correct walk-up from $probe and simply ignores the bogus ".git".
if [ "$cheap_dir_git" = 1 ] && [ ! -e "$git_dir/HEAD" ]; then
  git_dir=""
  repo_root=""
  cheap_dir_git=0
fi

# Fallback: the cheap walk above didn't find a sanity-checked directory-form
# ".git". Ask git directly — same single fork guard 1 has always paid for
# every path it couldn't classify on its own; not a regression.
if [ -z "$git_dir" ]; then
  git_dir=$(git -C "$probe" rev-parse --absolute-git-dir 2>/dev/null) || git_dir=""
fi

# Not a repo (by either check) → falls through to guard 2.
if [ -n "$git_dir" ]; then
  # Scratch dir (<repo>/.tmp/): gitignored working files — agent logs, verdicts,
  # plan findings, active-tds.md. Skills write these from either tree by design.
  # Anchored to THIS repo's actual root (not a bare "*/.tmp/*" substring) so a
  # target completely unrelated to any repo can't borrow the exemption just by
  # having a ".tmp" path segment somewhere on disk.
  #
  # Lexical prescreen first (no fork): only pay for repo_root/physical_resolve
  # when $normalized could plausibly be this repo's own .tmp scratch dir.
  # Every other write inside a recognized repo skips straight to the gitdir
  # check below without ever computing repo_root or resolving symlinks.
  case "$normalized" in
    */.tmp|*/.tmp/*)
      [ -z "$repo_root" ] && repo_root=$(git -C "$probe" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${git_dir%/.git}")
      resolve_real_normalized
      real_repo_root=$(cd -P "$repo_root" 2>/dev/null && pwd -P) || real_repo_root="$repo_root"
      case "$real_normalized" in
        "$real_repo_root"/.tmp|"$real_repo_root"/.tmp/*) exit 0 ;;
      esac
      ;;
  esac

  # A linked worktree's git dir is <common>/worktrees/<id>/ and always holds a
  # 'gitdir' file; a main tree's .git never does. That file is the
  # discriminator -- but it is only meaningful for a git_dir git itself has
  # confirmed (the fallback below). A sanity-checked cheap-path directory
  # match (cheap_dir_git=1) can never be a linked worktree in the first place
  # (see the walk-up comment above: a linked worktree's ".git" is always a
  # file), so consulting "$git_dir/gitdir" for it would be asking the wrong
  # question -- skip straight past to the deny below instead.
  if [ "$cheap_dir_git" != 1 ] && [ -f "$git_dir/gitdir" ]; then
    exit 0
  fi

  # repo_root may still be unset here (cheap walk found only an ambiguous
  # ".git" file and the .tmp prescreen above didn't match) — compute it now.
  # Forking on the deny path is fine: this is the error path, not the hot
  # allow path this optimization targets.
  [ -z "$repo_root" ] && repo_root=$(git -C "$probe" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${git_dir%/.git}")

  # Ignored-file carve-out: a path git ignores is in no branch, so a worktree
  # gives it no isolation (e.g. ~/.claude/settings.json, read from the main
  # tree only). Fail closed: any check-ignore exit code other than 0 falls
  # through to the deny. No --no-index: a tracked file must stay denied.
  # -C "$probe" (nearest existing dir of the target) makes git pick the same,
  # possibly nested, repository found above.
  # Skipped for paths inside .git (a pattern like `worktrees/` or `*.log`
  # would otherwise let metadata be corrupted) and for any path reached
  # through a symlink located inside the repo (check-ignore does not follow
  # it, and the write would land on a possibly tracked target).
  carve_ok=1
  case "$normalized" in
    "$git_dir"|"$git_dir"/*|*/.git|*/.git/*) carve_ok=0 ;;
  esac
  if [ "$carve_ok" = 1 ]; then
    real_repo_root=$(cd -P "$repo_root" 2>/dev/null && pwd -P) || real_repo_root="$repo_root"
    link_probe=""
    old_ifs=$IFS; IFS=/
    set -f
    for link_part in ${normalized#/}; do
      link_probe="$link_probe/$link_part"
      [ -L "$link_probe" ] || continue
      link_parent=$(cd -P "${link_probe%/*}/" 2>/dev/null && pwd -P) || { carve_ok=0; break; }
      case "$link_parent" in
        "$real_repo_root"|"$real_repo_root"/*) carve_ok=0; break ;;
      esac
    done
    set +f
    IFS=$old_ifs
  fi
  if [ "$carve_ok" = 1 ] && git -C "$probe" check-ignore -q -- "$normalized" 2>/dev/null; then
    exit 0
  fi

  # Merge-conflict carve-out: our own workflow merges worktree branches back
  # into the main tree, and resolving a conflict IS editing the conflicted
  # file in place there -- there is no other tree to do it in, the merge
  # lives in the main tree by definition. A path currently listed by
  # `git ls-files -u` (unmerged, stage 1/2/3) stays allowed, because that is
  # exactly what finishing the merge requires. The exemption is self-expiring:
  # once the conflict is resolved and staged (`git add`), the unmerged
  # entries are replaced by a normal stage-0 entry, `ls-files -u` goes back
  # to empty, and this path falls straight back under the deny below -- no
  # separate "merge finished" signal to track or forget to clear.
  #
  # Scoped to exactly this path, not "somewhere mid-merge": a second,
  # unrelated file in the same repo during the same conflicted merge has no
  # unmerged entry of its own and is still denied by the fallthrough below --
  # the exemption never widens to "the whole repo while a merge is open".
  #
  # Deliberately NOT `git ls-files -u -- "$normalized"`: passing the write
  # target as a pathspec hands git's own fnmatch-style glob magic (bare `*`,
  # `?`, `[...]` are active by default -- no leading `:(glob)` needed) the
  # literal target path. A file named e.g. "f*" or "notes[draft].md" would
  # then match ANY unmerged path in the repo that happens to fit the
  # pattern, not just itself, and borrow that unrelated file's exemption --
  # a full guard-1 bypass for any writer able to pick the target's name. The
  # same pathspec form has a second, independent bug: `git ls-files -u --
  # <path>` also matches an entire subtree when <path> is a directory
  # prefix of an unmerged file's path, so a write request for the
  # CONTAINING DIRECTORY of a conflicted file used to borrow the file's own
  # exemption. Both are closed the same way: list every unmerged path with
  # NO pathspec argument at all (nothing left for git to glob-match), then
  # compare each listed path against $normalized's repo-relative form as a
  # plain string -- literal on both sides, no pattern semantics, and never a
  # match for anything but the exact blob path git actually listed.
  #
  # repo_root can only be empty in the pathological "repository lives at the
  # filesystem root" layout (".git" directly under "/", so stripping
  # "/.git" off git_dir yields ""). `git -C ""` is not an error -- git
  # treats an empty -C argument as a no-op and quietly runs in the HOOK
  # PROCESS'S OWN cwd instead of the intended repo, which could be some
  # unrelated repository with its own, unrelated conflicts. Skip the
  # exemption outright rather than risk that; the write still gets a
  # (slightly less specific) deny below, same fail-closed default already
  # used everywhere else in this hook.
  #
  # Only reached once guard 1 has already decided to deny (this sits right
  # before that deny call) -- an ordinary allowed write never pays for this
  # extra `git` fork.
  if [ -n "$repo_root" ]; then
    case "$normalized" in
      "$repo_root") rel="" ;;
      "$repo_root"/*) rel="${normalized#"$repo_root"/}" ;;
      *) rel="" ;;
    esac

    if [ -n "$rel" ]; then
      # The exact literal $rel spelling is checked first (cheap, no extra
      # syscall beyond the `git` fork already paid on this deny-bound path).
      # It covers the overwhelming majority of calls, including a conflicted
      # file that has been deleted from the working tree as part of
      # resolving a modify/delete conflict (see the `-ef` fallback comment
      # below for why that case needs nothing more than this).
      #
      # If the literal spelling does not match, ask the filesystem itself
      # whether $normalized and the unmerged entry name the SAME file, via
      # `-ef` (same device + inode). This replaces two earlier attempts that
      # both tried to GUESS the filesystem's equivalence rules instead of
      # asking it directly:
      #   - Unicode/locale case-folding via bash `nocasematch` does not
      #     match APFS's actual comparison for every codepoint: ASCII
      #     "f.md" vs "F.MD" fold the same way under both, but nocasematch
      #     ALSO folds plain "i" (U+0069) together with the distinct
      #     Turkish "İ" (U+0130), while APFS stores them as two different
      #     files with two different inodes. An attacker who opens any
      #     conflict, anywhere, and then targets a Unicode-confusable
      #     spelling of the conflicted name got ALLOW on a completely
      #     unrelated write.
      #   - Trusting `git config core.ignorecase` as a proxy for "is the
      #     filesystem case-insensitive" was worse still: it is an ordinary,
      #     mutable git config value any writer with Bash access can flip
      #     with `git config core.ignorecase true` -- entirely outside this
      #     hook's Write/Edit/MultiEdit/NotebookEdit gate -- so it does not
      #     reliably describe the disk underneath the repo at all.
      # `-ef` sidesteps both problems: it's the kernel's own answer to "do
      # these two paths name the same file", so it automatically agrees with
      # whatever case-folding AND Unicode-normalization rules the real
      # filesystem actually uses. APFS's default volume format is
      # case-insensitive AND normalization-insensitive, so an NFC-composed
      # and an NFD-decomposed spelling of the same accented name both
      # resolve to the same inode via `-ef` -- no bash-side fold table to
      # keep in sync, no repo config to (mis)trust.
      #
      # `-ef` needs BOTH sides to exist on disk to compare inodes -- when
      # either is missing it simply reports "not the same file" (exit 1, no
      # error), never a crash under `set -eu`. That silently skips two
      # shapes, and neither is a gap:
      #   - a brand-new file a Write is creating has nothing to `stat` yet;
      #   - re-creating a conflicted file whose working copy was itself
      #     deleted (resolving a modify/delete conflict by removing the
      #     file, then Write-ing it back before staging) also has nothing on
      #     the $normalized side to `stat`.
      # Both are already handled above: a fresh Write and a modify/delete
      # resolution both address the file by its one true `git ls-files -u`
      # spelling (nothing else was ever written under a different spelling
      # to alias), so the literal-string comparison already matches them.
      # `-ef` exists only to recognize a DIFFERENT, already-on-disk spelling
      # of that same one true blob -- it has nothing left to add once
      # neither side of the comparison exists.
      exempt=1
      while IFS= read -r -d '' entry; do
        # `ls-files -u -z` output per unmerged stage: "<mode> <sha> <stage>"
        # then a real TAB then the path, NUL-terminated. Strip everything up
        # to and including that one tab; what remains is the repo-relative
        # path.
        entry="${entry#*$'\t'}"
        if [ "$entry" = "$rel" ]; then
          exempt=0
          break
        fi
        if [ "$normalized" -ef "$repo_root/$entry" ]; then
          exempt=0
          break
        fi
      done < <(git -C "$repo_root" ls-files -u -z 2>/dev/null)

      [ "$exempt" = 0 ] && exit 0
    fi
  fi

  deny "worktree-boundary: '$normalized' is in the MAIN working tree of $repo_root. Edits in a main tree are never allowed — no exemption for small or trivial changes. Create a worktree first (EnterWorktree for the cwd repo, otherwise: git -C $repo_root worktree add $repo_root/.claude/worktrees/<name> -b <name>) and write there."
fi

# --- Guard 2: no writes outside version control while in a worktree ---------
# Everything under git has already been decided above: linked worktrees exited
# clean, main trees were denied. What is left is untracked territory (home dir,
# a stray checkout-less path) — a session working in a worktree has no business
# writing there.
[ -z "$cwd" ] && exit 0

case "$cwd" in
  */.claude/worktrees/*) ;;
  *) exit 0 ;;
esac

# Derive worktree root via parameter expansion (no fork).
prefix="${cwd%%/.claude/worktrees/*}"
rest="${cwd#*/.claude/worktrees/}"
worktree_name="${rest%%/*}"
worktree_root="${prefix}/.claude/worktrees/${worktree_name}"

# A symlink planted inside the worktree that points at an unrelated directory
# would otherwise still compare as "inside" the worktree by string prefix
# alone — resolve worktree_root the same way before comparing. Only paid here,
# once guard 1 has ruled out every git-repo case above.
resolve_real_normalized
real_worktree_root=$(cd -P "$worktree_root" 2>/dev/null && pwd -P) || real_worktree_root="$worktree_root"

case "$real_normalized" in
  "$real_worktree_root"|"$real_worktree_root"/*) exit 0 ;;
esac

deny "worktree-boundary: refusing to write '$normalized' from worktree '$worktree_root'. Use a path under the worktree or ${memory_root}/projects/*/memory/."
