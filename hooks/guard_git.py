#!/usr/bin/env python3
"""PreToolUse hook: blocks direct commits/pushes to protected branches and force pushes.

Reads the Bash tool call as JSON on stdin. Exit code 2 blocks the call and shows
stderr to Claude; exit code 0 lets it through.
"""
import json
import re
import shlex
import subprocess
import sys

PROTECTED = {"main", "development"}
# Options of `git` itself that take a separate value argument.
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}


def git(cwd, *args):
    try:
        r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=15)
        return r.returncode, r.stdout.strip()
    except Exception:
        return 1, ""


def block(msg):
    print(f"BLOCKED by guard_git hook: {msg}", file=sys.stderr)
    sys.exit(2)


def split_segments(command):
    """Split a compound shell command into token lists, respecting quotes."""
    lex = shlex.shlex(command, posix=True, punctuation_chars=";&|\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    segments, current = [], []
    try:
        for tok in lex:
            if tok and set(tok) <= set(";&|\n"):
                if current:
                    segments.append(current)
                current = []
            else:
                current.append(tok)
    except ValueError:
        # Unbalanced quotes: fall back to a plain split so git commands are still checked.
        return [s.split() for s in re.split(r"&&|\|\||;|\||\n", command) if s.strip()]
    if current:
        segments.append(current)
    return segments


def parse_git(tokens, cwd):
    """Return (subcommand, args, effective_cwd) for a git invocation, or None."""
    # Skip env assignments like FOO=bar git ...
    i = 0
    while i < len(tokens) and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", tokens[i]):
        i += 1
    if i >= len(tokens) or tokens[i].rsplit("/", 1)[-1] != "git":
        return None
    i += 1
    while i < len(tokens) and tokens[i].startswith("-"):
        opt = tokens[i]
        if opt in GIT_OPTS_WITH_VALUE and i + 1 < len(tokens):
            if opt == "-C":
                cwd = resolve(cwd, tokens[i + 1])
            i += 2
        else:
            i += 1
    if i >= len(tokens):
        return None
    return tokens[i], tokens[i + 1:], cwd


def branch_name(ref):
    ref = ref.lstrip("+")
    for prefix in ("refs/heads/", "refs/remotes/origin/"):
        if ref.startswith(prefix):
            ref = ref[len(prefix):]
    return ref


def resolve(cwd, path):
    import os
    path = os.path.expanduser(os.path.expandvars(path))
    return path if path.startswith("/") else f"{cwd}/{path}"


def require_repo(cwd):
    # Fail closed: if the repository cannot be resolved (e.g. a path built from shell
    # variables defined in the same command), the rules cannot be verified.
    code, _ = git(cwd, "rev-parse", "--git-dir")
    if code != 0:
        block(f"could not resolve the git repository at `{cwd}` to verify branch rules. "
              "Use an absolute path (`git -C /abs/path ...`) without shell variables.")


def is_dotclaude(cwd):
    # ~/.claude (the dotclaude repo) is exempt from the branch workflow by user decision;
    # force pushes stay blocked there too.
    import os
    code, top = git(cwd, "rev-parse", "--show-toplevel")
    return code == 0 and os.path.realpath(top) == os.path.realpath(os.path.expanduser("~/.claude"))


def remote_has_branch(cwd, remote, name):
    # ls-remote --exit-code: 0 = found, 2 = not found, anything else = error.
    code, _ = git(cwd, "ls-remote", "--exit-code", "--heads", remote, name)
    if code == 0:
        return True
    if code == 2:
        return False
    block(f"could not reach remote `{remote}` to verify whether `{name}` exists.")


def check_push(args, cwd):
    require_repo(cwd)
    flags = [a for a in args if a.startswith("-")]
    positional = [a for a in args if not a.startswith("-")]

    if any(f in ("--force", "-f", "--force-with-lease", "--force-if-includes") or f.startswith("--force-with-lease=") for f in flags):
        block("force push is not allowed. Ask the user first.")
    if any(f in ("--all", "--mirror") for f in flags):
        block("`--all`/`--mirror` would push protected branches (main, development).")

    if is_dotclaude(cwd):
        if any(s.startswith("+") for s in positional[1:]):
            block("force refspec is not allowed. Ask the user first.")
        return

    deleting = any(f in ("--delete", "-d") for f in flags)
    remote = positional[0] if positional else "origin"
    refspecs = positional[1:]

    if not refspecs:
        _, current = git(cwd, "branch", "--show-current")
        refspecs = [current] if current else []

    for spec in refspecs:
        if spec.startswith("+"):
            block(f"force refspec `{spec}` is not allowed. Ask the user first.")
        if spec.startswith("refs/tags/") or re.match(r"^v\d+\.\d+\.\d+", spec):
            continue
        if ":" in spec:
            src, dst = spec.split(":", 1)
            target = branch_name(dst)
            if src == "":
                deleting = True
        else:
            target = branch_name(spec)
            if target == "HEAD":
                _, target = git(cwd, "branch", "--show-current")
        if target in PROTECTED:
            if deleting:
                block(f"deleting the protected branch `{target}` is not allowed.")
            # The one allowed case: creating a protected branch on the remote for the first
            # time (first push of a new repo's `main`, or creating `development` from `main`).
            if not remote_has_branch(cwd, remote, target):
                continue
            block(f"direct push to `{target}` is not allowed. Use a feature branch and a PR.")


def check_commit(args, cwd):
    # Fail open for commits: the repo may be created earlier in the same command, and a
    # local commit is recoverable; pushes to protected branches are still blocked.
    if git(cwd, "rev-parse", "--git-dir")[0] != 0 or is_dotclaude(cwd):
        return
    code, _ = git(cwd, "rev-parse", "--verify", "HEAD")
    if code != 0:
        return  # No commits yet (initial commit of a new repo) is allowed.
    _, current = git(cwd, "branch", "--show-current")
    if current in PROTECTED:
        block(f"direct commit on `{current}` is not allowed. Open a worktree branch from origin/development.")


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    if data.get("tool_name") != "Bash":
        return
    command = (data.get("tool_input") or {}).get("command", "")
    cwd = data.get("cwd") or "."
    if "git" not in command:
        return

    for tokens in split_segments(command):
        # Track simple `cd <dir>` so later segments resolve against it.
        if not tokens:
            continue
        if tokens[0] == "cd" and len(tokens) > 1:
            cwd = resolve(cwd, tokens[1])
            continue
        parsed = parse_git(tokens, cwd)
        if not parsed:
            continue
        sub, args, gcwd = parsed
        if sub == "push":
            check_push(args, gcwd)
        elif sub == "commit":
            check_commit(args, gcwd)


if __name__ == "__main__":
    main()
