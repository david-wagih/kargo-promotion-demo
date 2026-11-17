#!/usr/bin/env bash
# "CI ships a new build": runs demo-app's GitLab pipeline, which pushes
# registry.gitlab.com/<group>/demo-app:<version>. Kargo notices it on its own.
#   ./scripts/release.sh          -> next minor after the newest tag in the registry
#   ./scripts/release.sh 2.0.0    -> explicit version
source "$(dirname "$0")/lib.sh"

V=${1:-}
if [[ -z $V ]]; then
  latest=$(registry_tags | sort -V | tail -1)
  if [[ -z $latest ]]; then V=1.0.0; else IFS=. read -r ma mi _ <<< "$latest"; V="$ma.$((mi + 1)).0"; fi
fi
registry_tags | grep -qx "$V" && die "demo-app:$V already exists in the registry, pick a new version"

log "Running the demo-app pipeline for $V"
p=$(gl POST "/projects/$(pid "$APP_REPO")/pipeline" -H 'Content-Type: application/json' \
      -d "{\"ref\":\"main\",\"variables\":[{\"key\":\"VERSION\",\"value\":\"$V\"}]}")
id=$(jq -r .id <<< "$p"); echo "    $(jq -r .web_url <<< "$p")"
while :; do
  st=$(gl GET "/projects/$(pid "$APP_REPO")/pipelines/$id" | jq -r .status)
  case $st in success) break;; failed|canceled|skipped) die "pipeline $st";; esac
  sleep 5
done
ok "pushed $IMAGE_REPO:$V"
kargo refresh warehouse dev5 --project dev5 >/dev/null 2>&1 || true
echo "$V" > "$GEN/last-release"
