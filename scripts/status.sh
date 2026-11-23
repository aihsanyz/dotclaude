#!/usr/bin/env bash
# Read-only overview of projects, worktrees, environments and PRs on this machine.
#   status.sh [repo...]   default: every git repo under ~/projects and ~/github.com (up to 3 levels deep)
# Marks: STALE = environment running but no commit for 3+ days; ORPHAN = compose project
# running without a matching checkout; MERGED/CLOSED = the branch's PR is done (clean up).
set -uo pipefail

STALE_DAYS=3
now=$(date +%s)
repos=("$@")
if [[ ${#repos[@]} -eq 0 ]]; then
  while IFS= read -r g; do repos+=("$(dirname "$g")"); done < <(
    find "$HOME/projects" "$HOME/github.com" -maxdepth 4 -name .git -type d 2>/dev/null | sort)
fi

declare -A running=()
while read -r name status; do running[$name]=$status; done < <(
  docker compose ls --all --format json 2>/dev/null | python3 -c '
import json, sys
for p in json.load(sys.stdin): print(p["Name"], p["Status"].replace(" ", ""))' 2>/dev/null)
declare -A seen=()

env_name() { sed -n 's/^[[:space:]]*COMPOSE_PROJECT_NAME=//p' "$1/.env" 2>/dev/null | tail -1 | tr -d '"'"'"; }

for repo in "${repos[@]}"; do
  [[ -d $repo/.git ]] || continue
  remote=$(git -C "$repo" remote get-url origin 2>/dev/null | sed -E 's#(https://github.com/|git@github.com:)##; s#\.git$##')
  echo "== $(basename "$repo")${remote:+ ($remote)}"
  declare -A prs=()
  if [[ -n $remote ]]; then
    while IFS=$'\t' read -r head num state; do prs[$head]="#$num $state"; done < <(
      gh pr list -R "$remote" --state all -L 50 --json headRefName,number,state \
        --jq '.[] | [.headRefName, .number, .state] | @tsv' 2>/dev/null)
  fi
  while read -r path branch; do
    marks=() info=""
    if [[ -n $branch ]]; then
      counts=$(git -C "$path" rev-list --left-right --count origin/main...HEAD 2>/dev/null)
      [[ -n $counts ]] && info="ahead $(cut -f2 <<<"$counts") behind $(cut -f1 <<<"$counts")"
    fi
    dirty=$(git -C "$path" status --porcelain 2>/dev/null | grep -vc '^.. docs/reports/' || true)
    (( dirty > 0 )) && info+=" dirty $dirty"
    name=$(env_name "$path"); env="-"
    if [[ -n $name ]]; then
      seen[$name]=1; env="$name:${running[$name]:-down}"
      last=$(git -C "$path" log -1 --format=%ct 2>/dev/null || echo "$now")
      [[ ${running[$name]:-} == running* ]] && (( now - last > STALE_DAYS * 86400 )) && marks+=(STALE)
    fi
    pr=${prs[$branch]:-}
    [[ $pr == *MERGED* || $pr == *CLOSED* ]] && marks+=("PR-${pr##* }")
    printf '  %-12s %-28s %-24s env %-40s %s %s\n' "$([[ $path == "$repo" ]] && echo main-checkout || echo worktree)" \
      "${branch:-detached}" "$info" "$env" "${pr:-no-PR}" "${marks[*]:-}"
    [[ $path != "$repo" ]] && echo "               $path"
  done < <(git -C "$repo" worktree list --porcelain | awk '/^worktree /{p=$2} /^branch /{sub("refs/heads/","",$2); print p, $2} /^detached/{print p, ""}')
  unset prs
done

echo "== compose projects without a checkout"
orphan=0
for name in "${!running[@]}"; do
  [[ -n ${seen[$name]:-} ]] && continue
  echo "  $name ${running[$name]} ORPHAN"; orphan=1
done
(( orphan )) || echo "  none"
echo "== memory: $(free -m | awk 'NR == 2 {print $7 " MB available of " $2 " MB"}')"
