#!/usr/bin/env bash
# Back to "day 0" without recreating clusters:
#   - closes demo MRs, deletes feature/*, renovate/*, kargo/* branches
#   - restores config-tde-dev5 from the demo-baseline tag (so Renovate has upgrades again)
#   - empties apps/ in every env repo, wipes workloads, recreates the Kargo project
# Images already in the registry stay; the first Freight uses the newest one.
source "$(dirname "$0")/lib.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
REPOS=("$SOURCE_REPO" "$APP_REPO"); for e in "${ENV_CLUSTERS[@]}"; do REPOS+=("$(env_repo "$e")"); done

log "Deleting Kargo project dev5"
k "$MGMT_CLUSTER" delete project dev5 --ignore-not-found --wait=true >/dev/null
for _ in $(seq 1 60); do k "$MGMT_CLUSTER" get ns dev5 >/dev/null 2>&1 || break; sleep 2; done

log "Closing demo MRs and deleting demo branches"
for r in "${REPOS[@]}"; do
  gl GET "/projects/$(pid "$r")/merge_requests?state=opened&per_page=100" \
    | jq -r '.[] | select(.source_branch | test("^(feature|renovate|kargo)/")) | .iid' \
    | while read -r iid; do gl PUT "/projects/$(pid "$r")/merge_requests/$iid" -d state_event=close >/dev/null && echo "    closed $r!$iid"; done
  gl GET "/projects/$(pid "$r")/repository/branches?per_page=100" \
    | jq -r '.[].name | select(test("^(feature|renovate|kargo)/"))' \
    | while read -r b; do gl DELETE "/projects/$(pid "$r")/repository/branches/$(urlenc "$b")" >/dev/null && echo "    deleted $r:$b"; done
done

log "Restoring $SOURCE_REPO from demo-baseline"
git clone -q "$(auth_url "$SOURCE_REPO")" "$TMP/src"
git -C "$TMP/src" fetch -q --tags
git -C "$TMP/src" rm -rq . && git -C "$TMP/src" checkout -q demo-baseline -- .
if git -C "$TMP/src" diff --cached --quiet; then ok "already at baseline"; else
  git -C "$TMP/src" -c user.name=demo-reset -c user.email=demo-reset@noreply.gitlab.com commit -qm "demo: reset to demo-baseline"
  git -C "$TMP/src" push -q origin main 2>/dev/null; ok "restored"
fi

log "Emptying apps/ in the env repos"
for e in "${ENV_CLUSTERS[@]}"; do
  d="$TMP/$e"; git clone -q "$(auth_url "$(env_repo "$e")")" "$d"
  rm -rf "$d/apps"; mkdir -p "$d/apps/demo-app" "$d/apps/redis"; touch "$d/apps/demo-app/.gitkeep" "$d/apps/redis/.gitkeep"
  git -C "$d" add -A
  if ! git -C "$d" diff --cached --quiet; then
    git -C "$d" -c user.name=demo-reset -c user.email=demo-reset@noreply.gitlab.com commit -qm "demo: reset"
    git -C "$d" push -q origin main 2>/dev/null
  fi
  ok "$(env_repo "$e") reset"
done

log "Removing workloads from every env cluster"
for e in "${ENV_CLUSTERS[@]}"; do ke "$e" delete ns demo-app --ignore-not-found --wait=false >/dev/null; done
for e in "${ENV_CLUSTERS[@]}"; do ke "$e" wait --for=delete ns/demo-app --timeout=180s >/dev/null 2>&1 || true; done

"$ROOT/scripts/setup/05-pipeline.sh"

log "Waiting for Kargo to auto-promote the first Freight to dev"
wait_for "dev Freight" bash -c "[[ -n \$(kubectl --context kind-$MGMT_CLUSTER -n dev5 get stage dev -o jsonpath='{.status.freightHistory[0].items}') ]]"
wait_for "dev to be serving" bash -c "curl -fs http://localhost:$(app_port dev)/ | grep -q demo-app"
"$ROOT/scripts/status.sh"
ok "demo reset to day 0"
