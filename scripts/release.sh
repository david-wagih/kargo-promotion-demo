#!/usr/bin/env bash
# "CI ships a new build": triggers the build-image workflow on GitHub Actions,
# which pushes ghcr.io/<owner>/demo-app:<version>. Kargo notices it on its own.
source "$(dirname "$0")/lib.sh"
V=${1:?usage: release.sh <semver, e.g. 1.1.0>}
log "Triggering build-image workflow for demo-app $V"
gh workflow run build-image.yaml -R "$GITHUB_REPO" -f version="$V"
sleep 5
run=$(gh run list -R "$GITHUB_REPO" --workflow build-image.yaml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch "$run" -R "$GITHUB_REPO" --exit-status >/dev/null && ok "pushed $IMAGE_REPO:$V" || die "build failed: gh run view $run -R $GITHUB_REPO --log-failed"
kargo refresh warehouse dev5 --project dev5 >/dev/null 2>&1 || true
ok "Kargo warehouse refreshed — new Freight appears in a few seconds"
