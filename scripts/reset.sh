#!/usr/bin/env bash
# Puts the demo back to "day 0" without recreating clusters (~1 min):
# open demo PRs closed, env branches re-initialized, fresh Kargo project.
# (Images already on GHCR stay — Kargo's first Freight will use the newest one.)
source "$(dirname "$0")/lib.sh"

log "Deleting Kargo project dev5"
k "$MGMT_CLUSTER" delete project dev5 --ignore-not-found --wait=true >/dev/null
for _ in $(seq 1 60); do k "$MGMT_CLUSTER" get ns dev5 >/dev/null 2>&1 || break; sleep 2; done

log "Closing demo PRs (feature/*, renovate/*, kargo/promotion/*)"
gh pr list -R "$GITHUB_REPO" --state open --limit 100 --json number,headRefName \
  -q '.[] | select(.headRefName | test("^(feature|renovate|kargo)/")) | .number' \
  | while read -r n; do gh pr close "$n" -R "$GITHUB_REPO" --delete-branch >/dev/null && echo "    closed #$n"; done

log "Re-initializing env branches"
for env in "${ENV_CLUSTERS[@]}"; do
  gh api -X DELETE "repos/$GITHUB_REPO/git/refs/heads/env/$env" >/dev/null 2>&1 || true
done
"$ROOT/scripts/02-github.sh"

# Argo CD (rightly) refuses to auto-prune *everything* when its source goes empty,
# so wipe the workloads directly.
log "Removing demo-app from every env cluster"
for env in "${ENV_CLUSTERS[@]}"; do k "$env" delete ns demo-app --ignore-not-found --wait=false >/dev/null; done

"$ROOT/scripts/05-pipeline.sh"
ok "demo reset — Kargo will auto-promote the newest demo-app image to dev within ~30s"
