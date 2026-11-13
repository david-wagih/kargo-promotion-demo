#!/usr/bin/env bash
# Puts the demo back to "day 0" without recreating clusters (~2 min):
#   - closes demo PRs and deletes feature/*, renovate/*, kargo/* branches
#   - restores platform-config/ and app/ on main from the `demo-baseline` tag
#     (so Renovate has upgrades to propose again)
#   - re-initializes env/* branches, wipes the workloads, recreates the Kargo project
# Images already on GHCR stay; Kargo's first Freight uses the newest one.
source "$(dirname "$0")/lib.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
AUTH_URL="https://x-access-token:$(github_token)@github.com/$GITHUB_REPO.git"

log "Deleting Kargo project dev5"
k "$MGMT_CLUSTER" delete project dev5 --ignore-not-found --wait=true >/dev/null
for _ in $(seq 1 60); do k "$MGMT_CLUSTER" get ns dev5 >/dev/null 2>&1 || break; sleep 2; done

log "Closing open demo PRs"
gh pr list -R "$GITHUB_REPO" --state open --limit 100 --json number,headRefName \
  -q '.[] | select(.headRefName | test("^(feature|renovate|kargo)/")) | .number' \
  | while read -r n; do gh pr close "$n" -R "$GITHUB_REPO" >/dev/null && echo "    closed #$n"; done

log "Deleting demo branches"
git ls-remote --heads "$AUTH_URL" | awk '{print $2}' | sed 's#refs/heads/##' \
  | grep -E '^(feature|renovate|kargo|env)/' | while read -r b; do
      gh api -X DELETE "repos/$GITHUB_REPO/git/refs/heads/$b" >/dev/null && echo "    deleted $b"
    done

log "Restoring platform-config/ and app/ from demo-baseline"
git clone -q "$AUTH_URL" "$TMP/repo"
git -C "$TMP/repo" checkout -q demo-baseline -- platform-config app
if git -C "$TMP/repo" diff --cached --quiet; then
  ok "main already at baseline"
else
  git -C "$TMP/repo" -c user.name="demo-reset" -c user.email=demo-reset@users.noreply.github.com \
    commit -qm "demo: reset platform-config/ and app/ to demo-baseline"
  git -C "$TMP/repo" push -q origin main 2>/dev/null
  ok "main restored to baseline"
fi

"$ROOT/scripts/02-github.sh"

# Argo CD (rightly) refuses to auto-prune *everything* when its source goes empty,
# so wipe the workloads directly.
log "Removing demo-app from every env cluster"
for env in "${ENV_CLUSTERS[@]}"; do k "$env" delete ns demo-app --ignore-not-found --wait=false >/dev/null; done

"$ROOT/scripts/05-pipeline.sh"

log "Waiting for Kargo to auto-promote the first Freight to dev"
wait_for "dev to be serving" bash -c "curl -fs http://localhost:$(app_port dev)/ | grep -q demo-app"
"$ROOT/scripts/status.sh"
ok "demo reset to day 0"
