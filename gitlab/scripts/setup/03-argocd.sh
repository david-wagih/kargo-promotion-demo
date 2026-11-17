#!/usr/bin/env bash
# One independent Argo CD per env cluster, pointed at ITS env repo only
# (exactly like argocd.dev5.icp.corproot.net watching config-tde-dev5-dev5).
source "$(dirname "$0")/../lib.sh"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
helm repo update argo >/dev/null
hash=$(bcrypt "$ARGOCD_PASSWORD")

for env in "${ENV_CLUSTERS[@]}"; do
  log "Installing Argo CD into cluster '$(cluster "$env")'"
  helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_CHART_VERSION" \
    --kube-context "$(ctx "$(cluster "$env")")" -n argocd --create-namespace --wait --timeout 10m \
    -f "$ROOT/argocd/values.yaml" \
    --set-string configs.secret.argocdServerAdminPassword="$hash" \
    --set-string "configs.cm.url=http://localhost:$(argocd_port "$env")" >/dev/null
  render "$ROOT/argocd/root-app.yaml" "$env" | ke "$env" apply -f - >/dev/null
  ok "Argo CD ($env) → http://localhost:$(argocd_port "$env")  watches $(env_repo "$env")"
done
