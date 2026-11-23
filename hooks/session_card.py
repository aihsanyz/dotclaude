#!/usr/bin/env python3
"""SessionStart hook (startup, resume, clear, compact): adds a short status card to the context.

It re-states the rules that drift in long sessions and tells Claude where it is: project,
branch, worktree or main checkout, distance to origin/main, uncommitted changes, open PR.
Fast and offline except for one `gh pr view` with a short timeout. Never fails the session.
"""
import json
import os
import re
import subprocess
import sys


def run(cwd, *cmd, timeout=5):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip()
    except Exception:
        return 1, ""


def card(cwd, source):
    lines = ["Session card (from ~/.claude/hooks/session_card.py):",
             "- Speak Turkish with the user; code, comments, commits and PRs in English."]
    if source == "compact":
        lines.append("- Context was compacted: re-read the files you are editing before changing them.")
    code, top = run(cwd, "git", "rev-parse", "--show-toplevel")
    if code != 0:
        lines.append(f"- {cwd} is not a git repository.")
        return lines
    _, common = run(cwd, "git", "rev-parse", "--path-format=absolute", "--git-common-dir")
    main_dir = os.path.dirname(common) if common else top
    _, branch = run(cwd, "git", "branch", "--show-current")
    name = os.path.basename(main_dir)
    if os.path.realpath(top) == os.path.realpath(os.path.expanduser("~/.claude")):
        lines.append("- This is the dotclaude repo: commit directly on main, run "
                     "`scripts/scan.sh secrets origin/main..HEAD` before pushing.")
        return lines
    in_worktree = os.path.realpath(top) != os.path.realpath(main_dir)
    where = f"worktree `{top}`" if in_worktree else "main checkout (development environment)"
    lines.append(f"- Project `{name}`, branch `{branch or 'detached'}`, {where}.")
    if not in_worktree and branch in ("main", "master"):
        lines.append("- Do not change code here; new work happens in a worktree thread branched "
                     "from origin/main.")
    _, counts = run(cwd, "git", "rev-list", "--left-right", "--count", "origin/main...HEAD")
    if re.match(r"^\d+\s+\d+$", counts or ""):
        behind, ahead = counts.split()
        lines.append(f"- vs origin/main: {ahead} ahead, {behind} behind.")
    _, dirty = run(cwd, "git", "status", "--porcelain")
    if dirty:
        lines.append(f"- {len(dirty.splitlines())} uncommitted change(s).")
    if in_worktree and branch:
        code, pr = run(cwd, "gh", "pr", "view", branch, "--json", "number,state,url",
                       "--jq", '"\\(.number) \\(.state) \\(.url)"', timeout=4)
        if code == 0 and pr:
            lines.append(f"- PR: #{pr}.")
    agents = os.path.join(main_dir if not in_worktree else top, "AGENTS.md")
    if not os.path.exists(agents):
        lines.append("- No AGENTS.md: the project is not set up for this workflow; suggest /new-project.")
    elif "## Komutlar" not in open(agents, encoding="utf-8", errors="ignore").read():
        lines.append("- AGENTS.md has no `## Komutlar` section; suggest /new-project.")
    return lines


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    cwd = data.get("cwd") or os.getcwd()
    try:
        text = "\n".join(card(cwd, data.get("source", "")))
    except Exception as e:
        text = f"Session card failed: {e}"
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
