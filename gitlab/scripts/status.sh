#!/usr/bin/env bash
# One screen: what runs where, and where to click.
source "$(dirname "$0")/lib.sh"

printf '\n\033[1m%-8s %-10s %-12s %-22s %s\033[0m\n' ENV APP REDIS "KARGO FREIGHT" "ARGO CD (demo-app)"
for env in "${ENV_CLUSTERS[@]}"; do
  ver=$(curl -fs "http://localhost:$(app_port "$env")/" | sed -n 's/.*demo-app \([0-9.]*\)<.*/\1/p' || true)
  redis=$(ke "$env" -n demo-app get deploy redis -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/redis://' || true)
  fr=$(k "$MGMT_CLUSTER" -n dev5 get stage "$env" -o jsonpath='{.status.freightHistory[0].items.*.name}' 2>/dev/null | cut -c1-7 || true)
  alias=$([[ -n $fr ]] && k "$MGMT_CLUSTER" -n dev5 get freight -o json | jq -r --arg f "$fr" '.items[] | select(.metadata.name|startswith($f)) | .alias' || true)
  argo=$(ke "$env" -n argocd get app demo-app -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)
  printf '%-8s %-10s %-12s %-22s %s\n' "$env" "${ver:--}" "${redis:--}" "${alias:--}" "${argo:--}"
done
cat <<EOT

  Kargo     http://localhost:$KARGO_PORT        admin / $KARGO_PASSWORD
  GitLab    $GITLAB/$GITLAB_GROUP   (MRs, pipelines, config-tde-dev5-* env repos)
  Argo CD   dev http://localhost:$(argocd_port dev)  staging http://localhost:$(argocd_port staging)  prod http://localhost:$(argocd_port prod)   admin / $ARGOCD_PASSWORD
  App       dev http://localhost:$(app_port dev)  staging http://localhost:$(app_port staging)  prod http://localhost:$(app_port prod)
EOT
