#!/usr/bin/env bash
# Applies the dev5 Kargo pipeline: Project, GitHub credentials, Warehouse, PromotionTask, Stages.
source "$(dirname "$0")/../lib.sh"
M=$MGMT_CLUSTER

log "Applying the dev5 pipeline (Project, Warehouse, PromotionTask, Stages)"
k $M apply -f "$ROOT/kargo/00-project.yaml" >/dev/null
wait_for "project namespace" k $M get ns dev5

# Kargo pushes env branches and opens the prod PR with this token
k $M -n dev5 create secret generic github-creds \
  --from-literal=repoURL="$GITHUB_URL" \
  --from-literal=username=kargo-bot --from-literal=password="$(github_token)" \
  --dry-run=client -o yaml | k $M label --local -f - kargo.akuity.io/cred-type=git -o yaml \
  | k $M apply -f - >/dev/null

k $M apply -f "$ROOT/kargo/" >/dev/null
ok "pipeline applied"

kargo login "https://localhost:$KARGO_PORT" --admin --password "$KARGO_PASSWORD" --insecure-skip-tls-verify >/dev/null
kargo config set-project dev5 >/dev/null
ok "kargo CLI logged in (project dev5)"
