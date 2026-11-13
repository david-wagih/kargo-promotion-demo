#!/usr/bin/env bash
# "CI ships a new build": triggers the build-image workflow on GitHub Actions,
# which pushes ghcr.io/<owner>/demo-app:<version>. Kargo notices it on its own.
#   ./scripts/release.sh          -> next minor version after the newest tag on GHCR
#   ./scripts/release.sh 2.0.0    -> explicit version
source "$(dirname "$0")/lib.sh"

ghcr_tags() {
  local t; t=$(curl -fsS "https://ghcr.io/token?scope=repository:${IMAGE_REPO#ghcr.io/}:pull" | jq -r .token)
  curl -fsS -H "Authorization: Bearer $t" "https://ghcr.io/v2/${IMAGE_REPO#ghcr.io/}/tags/list" \
    | jq -r '.tags[]? | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))'
}

V=${1:-}
if [[ -z $V ]]; then
  latest=$(ghcr_tags 2>/dev/null | sort -V | tail -1)
  if [[ -z $latest ]]; then V=1.0.0
  else IFS=. read -r ma mi _ <<< "$latest"; V="$ma.$((mi + 1)).0"; fi
fi
ghcr_tags 2>/dev/null | grep -qx "$V" && die "demo-app:$V already exists on GHCR — pick a new version"

log "Triggering build-image workflow for demo-app $V"
gh workflow run build-image.yaml -R "$GITHUB_REPO" -f version="$V"
sleep 5
run=$(gh run list -R "$GITHUB_REPO" --workflow build-image.yaml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$run" -R "$GITHUB_REPO" --exit-status >/dev/null || die "build failed: gh run view $run -R $GITHUB_REPO --log-failed"
ok "pushed $IMAGE_REPO:$V"
kargo refresh warehouse dev5 --project dev5 >/dev/null 2>&1 || true
echo "$V" > "$GEN/last-release"
