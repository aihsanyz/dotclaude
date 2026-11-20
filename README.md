# dotclaude

Personal [Claude Code](https://claude.com/claude-code) configuration (`~/.claude`): global instructions, subagents, skills, a git guard hook and helper scripts.

The workflow it sets up:

- `/initer` prepares a project once: it writes a project `CLAUDE.md` with the stack and a `## Komutlar` section (migrate, test, seed) that `deploy.sh` reads.
- Every task runs in a git worktree branched from `origin/development`; `main` and `development` are never committed to directly.
- `/push` gates pushes behind the `reviewer` agent, `/merge` gates squash merges into `development` behind the `auditor` security agent, `/release` merges `development` into `main` with a merge commit and tags `vX.Y.Z`.
- All project tooling runs in Docker; nothing is installed on the host.
- Each project keeps a long-running `development` environment in its main checkout, updated by `/merge` after every merge.
- Each environment runs its own data services from the project's compose file; worktrees start with a copy of the development data (`deploy.sh copy-data`).
- Before every merge, the post-merge procedure is rehearsed in the worktree (`scripts/deploy.sh`).
- Agent reports are written to `docs/reports/<agent>/` in each project.

## Contents

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Global instructions loaded in every session (written in Turkish) |
| `local.example.md` | Template for machine-specific settings; copy to `local.md` |
| `settings.json` | Language, attribution and the git guard hook |
| `agents/` | `reviewer`, `auditor`, `releaser` subagents |
| `skills/` | `/initer`, `/tasker`, `/push`, `/merge`, `/release` |
| `scripts/deploy.sh` | One standard procedure for the pre-merge rehearsal and the development update; copies development data into worktrees |
| `hooks/guard_git.py` | Blocks direct commits/pushes to `main`/`development` and force pushes |
| `scripts/scan.sh` | gitleaks and trivy in pinned Docker images |
| `scripts/release-info.sh` | Release facts and semver proposal |

## Install

```bash
git clone https://github.com/aihsanyz/dotclaude.git ~/.claude
cp ~/.claude/local.example.md ~/.claude/local.md   # then fill in machine details
```

If `~/.claude` already exists, clone elsewhere and copy the files in. Requirements on the host: `git`, `gh` (authenticated), `docker`, `python3`.

`.gitignore` is a whitelist: credentials, session transcripts, memory, caches, plugins and `local.md` are never committed.
