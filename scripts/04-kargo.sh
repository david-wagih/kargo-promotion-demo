#!/usr/bin/env bash
# Installs cert-manager + Kargo into the mgmt cluster.
source "$(dirname "$0")/lib.sh"
M=$MGMT_CLUSTER

log "Installing cert-manager into '$M'"
helm upgrade --install cert-manager oci://quay.io/jetstack/charts/cert-manager \
  --version "$CERT_MANAGER_VERSION" --kube-context "$(ctx $M)" \
  -n cert-manager --create-namespace --set crds.enabled=true --wait >/dev/null
ok "cert-manager ready"

log "Installing Kargo v$KARGO_VERSION into '$M'"
hash=$(bcrypt "$KARGO_PASSWORD")
[[ -s "$GEN/kargo-signing-key" ]] || openssl rand -base64 48 | tr -d '=+/' | head -c 32 > "$GEN/kargo-signing-key"

helm upgrade --install kargo oci://ghcr.io/akuity/kargo-charts/kargo \
  --version "$KARGO_VERSION" --kube-context "$(ctx $M)" -n kargo --create-namespace \
  --set-string api.adminAccount.passwordHash="$hash" \
  --set-string api.adminAccount.tokenSigningKey="$(cat "$GEN/kargo-signing-key")" \
  --set api.host="localhost:$KARGO_PORT" \
  --set api.service.type=NodePort --set api.service.nodePort=31443 \
  --set controller.argocd.integrationEnabled=false \
  --set-string controller.reconcilers.warehouses.minReconciliationInterval=10s \
  --wait --timeout 10m >/dev/null
ok "Kargo ready → https://localhost:$KARGO_PORT  admin / $KARGO_PASSWORD"
