# dotclaude

Personal [Claude Code](https://claude.com/claude-code) configuration (`~/.claude`), built for working through [T3 Code](https://t3.codes) on a single Linux server where everything runs in Docker.

The previous setup is kept at the `legacy-2026-11` tag.

## How it works

- **One long-lived branch: `main`.** Every task is a T3 thread in its own git worktree, branched from `origin/main`. Changes land through a PR and a squash merge.
- **Deterministic checks run in CI, judgement in agents.** GitHub Actions runs lint, tests, a fresh-database and upgrade migration rehearsal, the production build and secret/CVE scans. Agents review code and security.
- **Guards are hooks, not prose.** `hooks/guard.py` blocks direct pushes or commits to `main`, force pushes, `--no-verify`, admin merges and host installs. It asks before destructive commands. `hooks/session_card.py` restates the language rule and the current branch, worktree and PR at every session start and after compaction.
- **Small context.** `CLAUDE.md` holds principles only. File-type rules in `rules/` load only when matching files are touched. Skills are vendored, not installed as plugins, and claude.ai skill/plugin sync is off.
- **Provider-neutral projects.** Project rules live in `AGENTS.md`, which both Claude and Codex read. The project `CLAUDE.md` is `@AGENTS.md`.
- **Environments.**
  - The main checkout runs the development environment from `main`.
  - Each worktree gets its own environment on ports 4100–4999.
  - Production runs on a separate Dokploy server (Compose type) and is updated by hand to a release tag.

## Contents

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Global instructions (Turkish) |
| `rules/` | Path-scoped rules: Docker/compose, migrations, dev-server networking, CI |
| `settings.json` | Language, attribution, sync off, permissions, hooks |
| `hooks/` | `guard.py` (+ `test_guard.py`), `session_card.py` |
| `agents/` | `reviewer` (full, incremental or short mode), `security` (blocks only on findings the scope introduces) |
| `skills/` | Workflow: `/new-project`, `/ship`, `/land`, `/release`, `/status`. Design skills vendored from Anthropic (see `SOURCES.md`) |
| `scripts/devenv.sh` | Worktree and main-checkout environments: `up`, `reset`, `down`, `stop`, `apply`, `ports`, `run <cmd>` |
| `scripts/status.sh` | Read-only overview of repos, worktrees, compose projects, PRs and memory |
| `scripts/release-info.sh` | Release range, semver proposal and upgrade-relevant files |
| `scripts/scan.sh` | gitleaks and trivy in pinned Docker images |
| `templates/project/` | Project skeleton: `AGENTS.md`, compose files, env examples, CI (`lint`, `test`, `rehearse`, `scan`) |

## Flow

1. `/new-project` once per project: GitHub repo, skeleton, T3 project with worktree threads and a setup script (`devenv.sh up`).
2. New T3 thread per task: its own worktree and environment on ports 4100–4999.
3. `/ship`: lint and tests, reviewer, security and a Codex cross-review on sensitive changes, push, PR, CI watch.
4. `/land`: squash merge when CI is green, `devenv.sh apply` in the main checkout, cleanup.
5. `/release`: security over the release range, release notes PR, `vX.Y.Z` tag; production is updated in Dokploy to that tag.
| `SOURCES.md` | Origin, commit and license of vendored content |
| `local.example.md` | Template for machine-specific settings; copy to `local.md` |

## Install

```bash
git clone https://github.com/aihsanyz/dotclaude.git ~/.claude
cp ~/.claude/local.example.md ~/.claude/local.md   # then fill in machine details
python3 ~/.claude/hooks/test_guard.py              # verify the guard hook
```

If `~/.claude` already exists, clone elsewhere and copy the files in. Host requirements: `git`, `gh` (authenticated), `docker`, `python3`.

`.gitignore` is a whitelist: credentials, session transcripts, memory, caches, plugins and `local.md` are never committed.
