#!/usr/bin/env python3
"""PreToolUse hook for Bash: deterministic guards for git, host installs and destructive commands.

Reads the tool call as JSON on stdin.
  exit 2 + stderr        -> the call is blocked and the reason is shown to Claude
  JSON "ask" on stdout    -> the user is asked to confirm
  exit 0, no output      -> the call goes through
Only the Python standard library is used (the host has no other runtime).
"""
import json
import os
import re
import shlex
import subprocess
import sys

PROTECTED = {"main", "master", "development"}
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
SHELLS = {"sh", "bash", "zsh", "dash"}
# Commands whose arguments run inside a container, not on the host.
CONTAINER_RUNNERS = {"docker", "podman"}
SCRATCH_PREFIXES = ("/tmp/", "/var/tmp/")


class Decision(Exception):
    def __init__(self, kind, msg):
        super().__init__(msg)
        self.kind, self.msg = kind, msg


def block(msg):
    raise Decision("block", msg)


def ask(msg):
    raise Decision("ask", msg)


def git(cwd, *args):
    try:
        r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=15)
        return r.returncode, r.stdout.strip()
    except Exception:
        return 1, ""


def resolve(cwd, path):
    path = os.path.expanduser(os.path.expandvars(path))
    return os.path.normpath(path if path.startswith("/") else os.path.join(cwd, path))


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
        return [s.split() for s in re.split(r"&&|\|\||;|\||\n", command) if s.strip()]
    if current:
        segments.append(current)
    return segments


def strip_prefix(tokens):
    """Drop env assignments and wrappers such as sudo/env/time/nohup; report whether sudo was used."""
    i, sudo = 0, False
    while i < len(tokens):
        t = tokens[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
        elif t in ("sudo", "doas"):
            sudo = True
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                i += 2 if tokens[i] in ("-u", "-g", "-p") else 1
        elif t in ("env", "time", "nohup", "nice", "command", "exec"):
            i += 1
        else:
            break
    return tokens[i:], sudo


# ---- git --------------------------------------------------------------------------------------

def parse_git(tokens, cwd):
    if not tokens or tokens[0].rsplit("/", 1)[-1] != "git":
        return None
    i = 1
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


def is_dotclaude(cwd):
    code, top = git(cwd, "rev-parse", "--show-toplevel")
    return code == 0 and os.path.realpath(top) == os.path.realpath(os.path.expanduser("~/.claude"))


def require_repo(cwd):
    if git(cwd, "rev-parse", "--git-dir")[0] != 0:
        block(f"could not resolve the git repository at `{cwd}`. Use `git -C /absolute/path ...` "
              "without shell variables, and run repo creation and the first push as separate commands.")


def remote_has_branch(cwd, remote, name):
    code, _ = git(cwd, "ls-remote", "--exit-code", "--heads", remote, name)
    if code == 0:
        return True
    if code == 2:
        return False
    block(f"could not reach remote `{remote}` to check whether `{name}` exists.")


def check_push(args, cwd):
    require_repo(cwd)
    flags = [a for a in args if a.startswith("-")]
    positional = [a for a in args if not a.startswith("-")]
    if any(f in ("--force", "-f", "--force-with-lease", "--force-if-includes")
           or f.startswith("--force-with-lease=") for f in flags):
        block("force push is not allowed. Ask the user first.")
    if "--no-verify" in flags:
        block("`--no-verify` skips the repository's hooks; fix the failing hook instead.")
    if any(f in ("--all", "--mirror") for f in flags):
        block("`--all`/`--mirror` would push protected branches.")
    if any(s.startswith("+") for s in positional[1:]):
        block("force refspec is not allowed. Ask the user first.")
    if is_dotclaude(cwd):
        return
    deleting = any(f in ("--delete", "-d") for f in flags)
    remote = positional[0] if positional else "origin"
    refspecs = positional[1:]
    if not refspecs:
        _, current = git(cwd, "branch", "--show-current")
        refspecs = [current] if current else []
    for spec in refspecs:
        if spec.startswith("refs/tags/") or re.match(r"^v\d+\.\d+\.\d+", spec):
            continue
        if ":" in spec:
            src, dst = spec.split(":", 1)
            target = branch_name(dst)
            deleting = deleting or src == ""
        else:
            target = branch_name(spec)
            if target == "HEAD":
                _, target = git(cwd, "branch", "--show-current")
        if target in PROTECTED:
            if deleting:
                block(f"deleting the protected branch `{target}` is not allowed.")
            if not remote_has_branch(cwd, remote, target):
                continue  # first push of a new repository's default branch
            block(f"direct push to `{target}` is not allowed. Work on a branch and open a PR (/ship).")


def check_commit(args, cwd):
    if "--no-verify" in args or "-n" in args:
        block("`--no-verify` skips the repository's hooks; fix the failing hook instead.")
    if git(cwd, "rev-parse", "--git-dir")[0] != 0 or is_dotclaude(cwd):
        return
    if git(cwd, "rev-parse", "--verify", "HEAD")[0] != 0:
        return  # initial commit of a new repository
    _, current = git(cwd, "branch", "--show-current")
    if current in PROTECTED:
        block(f"direct commit on `{current}` is not allowed. Work in a worktree branch from origin/main.")


def check_git(tokens, cwd):
    parsed = parse_git(tokens, cwd)
    if not parsed:
        return
    sub, args, gcwd = parsed
    if sub == "push":
        check_push(args, gcwd)
    elif sub == "commit":
        check_commit(args, gcwd)
    elif sub == "reset" and "--hard" in args:
        ask("`git reset --hard` discards uncommitted work.")
    elif sub == "clean" and any(re.match(r"^-[a-zA-Z]*f", a) or a == "--force" for a in args):
        ask("`git clean -f` deletes untracked files.")
    elif sub == "branch" and any(a in ("-D", "--delete", "-d") for a in args):
        names = [a for a in args if not a.startswith("-")]
        if any(n in PROTECTED for n in names):
            block("deleting a protected branch is not allowed.")


def check_gh(tokens):
    if not tokens or tokens[0] != "gh":
        return
    args = tokens[1:]
    if args[:2] == ["pr", "merge"]:
        if "--admin" in args:
            block("`gh pr merge --admin` bypasses branch protection. Wait for the checks (/land).")
    if args[:1] == ["api"]:
        joined = " ".join(args)
        if re.search(r"/pulls/\d+/merge\b|/merges\b", joined):
            block("merging through `gh api` bypasses the /land checks. Use `gh pr merge` via /land.")
        if re.search(r"/git/refs/heads/(main|master|development)\b", joined):
            block("rewriting a protected branch through `gh api` is not allowed.")
    if args[:2] == ["auth", "token"] or args[:2] == ["auth", "login"]:
        block("do not read or create gh tokens; the user manages `gh auth`.")


# ---- host installs ----------------------------------------------------------------------------

HOST_INSTALL = [
    (r"^(apt|apt-get|aptitude|dnf|yum|snap|apk|pacman|zypper)$", r"^(install|add|-S)$"),
    (r"^(pip|pip3|pipx|uv)$", r"^(install|tool)$"),
    (r"^(npm|pnpm|yarn|bun)$", r"^(install|i|add|global)$"),
    (r"^(brew|cargo|go|gem)$", r"^install$"),
]


def check_host_install(tokens, sudo):
    if not tokens:
        return
    cmd = tokens[0].rsplit("/", 1)[-1]
    rest = tokens[1:]
    if cmd in ("python", "python3") and rest[:2] == ["-m", "pip"] and "install" in rest:
        block("installing Python packages on the host is not allowed; run it inside a container.")
    for name_re, verb_re in HOST_INSTALL:
        if re.match(name_re, cmd) and any(re.match(verb_re, a) for a in rest[:3]):
            block(f"`{cmd}` installs software on the host, which is not allowed. Run project tooling "
                  "inside Docker; ask the user if a host tool is really required.")
    if cmd in ("npm", "npx", "pnpm", "yarn", "bun", "node", "pip", "pip3"):
        block(f"`{cmd}` is not on the host by design; run it inside a container "
              "(`docker compose run --rm <service> ...`).")


def check_pipe_to_shell(command):
    if re.match(r"^\s*(docker|podman)\b", command):
        return
    if re.search(r"\b(curl|wget)\b[^|;&]*\|\s*(sudo\s+)?(ba|z|da)?sh\b", command):
        block("piping a download into a shell installs unreviewed code on the host.")


# ---- destructive ------------------------------------------------------------------------------

def check_destructive(tokens, cwd, sudo):
    if not tokens:
        return
    cmd = tokens[0].rsplit("/", 1)[-1]
    args = tokens[1:]
    if cmd == "rm" and any(re.match(r"^-[a-zA-Z]*[rR]", a) or a == "--recursive" for a in args):
        targets = [resolve(cwd, a) for a in args if not a.startswith("-")]
        if sudo or not targets or any(not t.startswith(SCRATCH_PREFIXES) for t in targets):
            ask("recursive delete outside /tmp: " + " ".join(targets or ["(no target)"]))
    if cmd == "docker":
        if args[:1] == ["compose"] and "down" in args and any(a in ("-v", "--volumes") for a in args):
            ask("`docker compose down -v` deletes this project's volumes (data). "
                "Worktree environments are removed with `devenv.sh down` instead.")
        if args[:2] in (["volume", "rm"], ["volume", "prune"], ["system", "prune"]) or args[:1] == ["prune"]:
            ask("this deletes Docker data that may belong to other projects.")
    if cmd == "systemctl" and any(a in ("stop", "restart", "disable", "mask", "kill") for a in args):
        ask("changing a system service; the user decides on system services.")


# ---- main -------------------------------------------------------------------------------------

def check_segment(tokens, cwd, depth=0):
    tokens, sudo = strip_prefix(tokens)
    if not tokens:
        return cwd
    if tokens[0] == "cd" and len(tokens) > 1:
        return resolve(cwd, tokens[1])
    if tokens[0].rsplit("/", 1)[-1] in SHELLS and "-c" in tokens and depth < 3:
        i = tokens.index("-c")
        if i + 1 < len(tokens):
            check_command(tokens[i + 1], cwd, depth + 1)
        return cwd
    if tokens[0] in CONTAINER_RUNNERS:
        check_destructive(tokens, cwd, sudo)
        return cwd  # the rest runs inside the container
    check_git(tokens, cwd)
    check_gh(tokens)
    check_host_install(tokens, sudo)
    check_destructive(tokens, cwd, sudo)
    return cwd


def check_command(command, cwd, depth=0):
    check_pipe_to_shell(command)
    for tokens in split_segments(command):
        if tokens:
            cwd = check_segment(tokens, cwd, depth)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    if data.get("tool_name") != "Bash":
        return 0
    command = (data.get("tool_input") or {}).get("command", "")
    try:
        check_command(command, data.get("cwd") or os.getcwd())
    except Decision as d:
        if d.kind == "block":
            print(f"BLOCKED by guard hook: {d.msg}", file=sys.stderr)
            return 2
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": f"guard hook: {d.msg}",
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
