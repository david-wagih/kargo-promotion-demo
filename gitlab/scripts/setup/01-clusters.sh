#!/usr/bin/env bash
# 4 kind clusters: gl-mgmt (Kargo) + gl-dev / gl-staging / gl-prod (one Argo CD each,
# like the one-EKS-cluster-per-space setup of config-tde-dev5).
source "$(dirname "$0")/../lib.sh"

create_cluster() { # name [hostPort:containerPort ...]
  local name=$1; shift
  if $CR container inspect "$name-control-plane" >/dev/null 2>&1; then ok "cluster $name exists"; return; fi
  local cfg="$GEN/kind-$name.yaml"
  {
    echo "kind: Cluster"; echo "apiVersion: kind.x-k8s.io/v1alpha4"; echo "name: $name"
    echo "nodes:"; echo "- role: control-plane"; echo "  extraPortMappings:"
    for m in "$@"; do echo "  - hostPort: ${m%%:*}"; echo "    containerPort: ${m##*:}"; done
  } > "$cfg"
  log "Creating kind cluster '$name'"
  kind create cluster --config "$cfg" --wait 120s
}

prev_ctx=$(kubectl config current-context 2>/dev/null || true)
trap '[[ -n $prev_ctx ]] && kubectl config use-context "$prev_ctx" >/dev/null || true' EXIT

create_cluster "$MGMT_CLUSTER" "$KARGO_PORT:31080"
for env in "${ENV_CLUSTERS[@]}"; do
  create_cluster "$(cluster "$env")" "$(argocd_port "$env"):30080" "$(app_port "$env"):30090"
done
ok "clusters ready (contexts: kind-$MGMT_CLUSTER, kind-gl-<env>)"
