#!/usr/bin/env bash
# Collects release facts for origin/main..origin/development and proposes a semver version.
# Run from inside the repo or a worktree. Prints key: value lines, then the commit list.
# Exit codes: 0 ready, 1 nothing to release, 2 blocked or error.
set -uo pipefail

git fetch -q origin --tags || { echo "error: git fetch failed" >&2; exit 2; }
range="origin/main..origin/development"

last=$(git describe --tags --abbrev=0 --match 'v[0-9]*' origin/main 2>/dev/null || true)
mapfile -t shas < <(git log --no-merges --format='%H' "$range")

if [[ ${#shas[@]} -eq 0 ]]; then
  echo "status: nothing-to-release"
  echo "last_tag: ${last:-none}"
  exit 1
fi

breaking=0 feat=0 fix=0 other=0
for sha in "${shas[@]}"; do
  subject=$(git log -1 --format='%s' "$sha")
  body=$(git log -1 --format='%b' "$sha")
  if [[ "$subject" =~ ^[a-z]+(\([^\)]*\))?!: ]] || grep -q '^BREAKING CHANGE' <<<"$body"; then
    breaking=$((breaking + 1))
  elif [[ "$subject" =~ ^feat(\([^\)]*\))?: ]]; then
    feat=$((feat + 1))
  elif [[ "$subject" =~ ^fix(\([^\)]*\))?: ]]; then
    fix=$((fix + 1))
  else
    other=$((other + 1))
  fi
done

if [[ -z "$last" ]]; then
  next="v0.1.0"
  reason="no previous tag, first release"
else
  IFS=. read -r major minor patch <<<"${last#v}"
  patch="${patch%%[^0-9]*}"
  if (( breaking > 0 )); then
    if (( major == 0 )); then next="v0.$((minor + 1)).0"; reason="$breaking breaking change(s) on 0.x → minor"
    else next="v$((major + 1)).0.0"; reason="$breaking breaking change(s) → major"; fi
  elif (( feat > 0 )); then
    next="v$major.$((minor + 1)).0"; reason="$feat feat commit(s) → minor"
  else
    next="v$major.$minor.$((patch + 1))"; reason="only fixes/other → patch"
  fi
fi

blockers=()
git merge-base --is-ancestor origin/main origin/development || blockers+=("origin/main is not an ancestor of origin/development")
git rev-parse -q --verify "refs/tags/$next" >/dev/null && blockers+=("tag $next already exists")
git cat-file -e "origin/development:releases/$next.md" 2>/dev/null && blockers+=("releases/$next.md already exists")

for b in main development; do
  if git rev-parse -q --verify "refs/heads/$b" >/dev/null; then
    [[ "$(git rev-parse "$b")" == "$(git rev-parse "origin/$b")" ]] || echo "warning: local $b differs from origin/$b"
  fi
done

echo "status: $([[ ${#blockers[@]} -eq 0 ]] && echo ready || echo blocked)"
echo "last_tag: ${last:-none}"
echo "next_version: $next"
echo "reason: $reason"
echo "counts: ${#shas[@]} commits — $breaking breaking, $feat feat, $fix fix, $other other"
for b in "${blockers[@]}"; do echo "blocker: $b"; done
echo "commits:"
git log --no-merges --format='  %h %s' "$range"

[[ ${#blockers[@]} -eq 0 ]] || exit 2
