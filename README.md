# dotclaude

Personal [Claude Code](https://claude.com/claude-code) configuration (`~/.claude`): global instructions, subagents, skills, a git guard hook and helper scripts.

The workflow it sets up:

- Every task runs in a git worktree branched from `origin/development`; `main` and `development` are never committed to directly.
- `/push` gates pushes behind the `reviewer` agent, `/merge` gates squash merges into `development` behind the `auditor` security agent, `/release` merges `development` into `main` with a merge commit and tags `vX.Y.Z`.
- All project tooling runs in Docker; nothing is installed on the host.
- Each project keeps a long-running `development` environment in its main checkout, updated after every merge (`/dev-env`).
- PostgreSQL, MySQL and Redis run once in a shared stack; every worktree gets its own copy of the development database (`scripts/db.sh`).
- Agent reports are written to `docs/reports/<agent>/` in each project.

## Contents

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Global instructions loaded in every session (written in Turkish) |
| `local.example.md` | Template for machine-specific settings; copy to `local.md` |
| `settings.json` | Language, attribution and the git guard hook |
| `agents/` | `reviewer`, `auditor`, `releaser` subagents |
| `skills/` | `/start-task`, `/push`, `/merge`, `/release`, `/dev-env` |
| `infra/compose.yaml` | Shared PostgreSQL, MySQL and Redis on the `shared` Docker network |
| `scripts/db.sh` | Per-project users, `<project>_dev` databases, worktree clones, backups |
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
