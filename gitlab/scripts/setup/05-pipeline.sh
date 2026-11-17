#!/usr/bin/env bash
# Applies the dev5 Kargo pipeline: Project, GitLab credentials, Warehouse, PromotionTask, Stages.
source "$(dirname "$0")/../lib.sh"
M=$MGMT_CLUSTER

log "Applying the dev5 pipeline"
render "$ROOT/kargo/00-project.yaml" | k $M apply -f - >/dev/null
wait_for "project namespace" k $M get ns dev5

# One credential for every repo in the group (the GROUP_PROMOTION_TOKEN equivalent)
k $M -n dev5 create secret generic gitlab-creds \
  --from-literal=repoURL="^https://gitlab\\.com/${GITLAB_GROUP//./\\.}/.*" \
  --from-literal=repoURLIsRegex=true \
  --from-literal=username=oauth2 --from-literal=password="$GITLAB_TOKEN" \
  --dry-run=client -o yaml | k $M label --local -f - kargo.akuity.io/cred-type=git -o yaml \
  | k $M apply -f - >/dev/null

for f in "$ROOT"/kargo/*.yaml; do render "$f"; echo "---"; done | k $M apply -f - >/dev/null
ok "pipeline applied"

kargo login "http://localhost:$KARGO_PORT" --admin --password "$KARGO_PASSWORD" >/dev/null
kargo config set-project dev5 >/dev/null
ok "kargo CLI logged in (project dev5)"
