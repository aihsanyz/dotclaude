#!/usr/bin/env bash
# Security scanners in pinned Docker images. Nothing is installed on the host.
#
#   scan.sh secrets <git-range>   gitleaks over the commits in <git-range>
#   scan.sh fs                    trivy over the repo files (deps, secrets, misconfig)
#   scan.sh image <image>         trivy over a local Docker image
#
# Run from inside the repo or worktree. Exit codes: 0 clean, 1 findings, 2+ error.
set -uo pipefail

GITLEAKS_IMAGE="zricethezav/gitleaks:v8.30.1"
TRIVY_IMAGE="aquasec/trivy:0.76.2"
TRIVY_CACHE_VOLUME="claude-trivy-cache"

top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "error: not inside a git repository" >&2; exit 2; }
common=$(git rev-parse --path-format=absolute --git-common-dir)

# Pull quietly so only scanner output reaches the report.
pull() { docker image inspect "$1" >/dev/null 2>&1 || docker pull -q "$1" >/dev/null || { echo "error: cannot pull $1" >&2; exit 2; }; }

case "${1:-}" in
  secrets)
    range="${2:?usage: scan.sh secrets <git-range>}"
    pull "$GITLEAKS_IMAGE"
    echo "# gitleaks ${GITLEAKS_IMAGE##*:} — range: $range"
    # Worktrees keep their git data in the main repo, so mount both at their real paths.
    docker run --rm --user "$(id -u):$(id -g)" \
      -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
      -v "$top:$top:ro" -v "$common:$common:ro" -w "$top" \
      "$GITLEAKS_IMAGE" git --log-opts="$range" --redact --no-banner --no-color -v --exit-code 1 "$top"
    ;;
  fs)
    pull "$TRIVY_IMAGE"
    echo "# trivy ${TRIVY_IMAGE##*:} — fs: $top"
    docker run --rm -v "$TRIVY_CACHE_VOLUME:/root/.cache" -v "$top:$top:ro" \
      "$TRIVY_IMAGE" fs --quiet --scanners vuln,secret,misconfig \
      --severity MEDIUM,HIGH,CRITICAL --ignore-unfixed --exit-code 1 "$top"
    ;;
  image)
    image="${2:?usage: scan.sh image <image>}"
    pull "$TRIVY_IMAGE"
    echo "# trivy ${TRIVY_IMAGE##*:} — image: $image"
    tmp=$(mktemp -d) && trap 'rm -rf "$tmp"' EXIT
    docker save "$image" -o "$tmp/image.tar" || { echo "error: cannot export image $image" >&2; exit 2; }
    docker run --rm -v "$TRIVY_CACHE_VOLUME:/root/.cache" -v "$tmp:/scan:ro" \
      "$TRIVY_IMAGE" image --quiet --scanners vuln,secret \
      --severity MEDIUM,HIGH,CRITICAL --ignore-unfixed --exit-code 1 --input /scan/image.tar
    ;;
  *)
    sed -n '2,8p' "$0" >&2
    exit 2
    ;;
esac
