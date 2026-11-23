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
| `scripts/scan.sh` | gitleaks and trivy in pinned Docker images |
| `skills/` | Design skills vendored from Anthropic (see `SOURCES.md`); workflow skills follow |
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
