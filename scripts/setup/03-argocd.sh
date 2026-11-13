#!/usr/bin/env bash
# Installs an independent Argo CD into each env cluster (dev / staging / prod) and
# points it at *its own* env branch — exactly like one Argo CD per cluster today.
source "$(dirname "$0")/../lib.sh"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
hash=$(bcrypt "$ARGOCD_PASSWORD")

for env in "${ENV_CLUSTERS[@]}"; do
  log "Installing Argo CD into cluster '$env'"
  helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_CHART_VERSION" \
    --kube-context "$(ctx "$env")" -n argocd --create-namespace --wait --timeout 10m \
    -f "$ROOT/argocd/values.yaml" \
    --set-string configs.secret.argocdServerAdminPassword="$hash" \
    --set-string "configs.cm.url=http://localhost:$(argocd_port "$env")" >/dev/null

  sed -e "s/__ENV__/$env/g" -e "s#__REPO_URL__#$GITHUB_URL#" "$ROOT/argocd/application.yaml" \
    | k "$env" apply -f - >/dev/null
  ok "Argo CD ($env) → http://localhost:$(argocd_port "$env")  admin / $ARGOCD_PASSWORD"
done
