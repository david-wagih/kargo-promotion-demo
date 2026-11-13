#!/usr/bin/env bash
# Creates 4 kind clusters:
#   mgmt                 -> Kargo control plane
#   dev / staging / prod -> one cluster + one Argo CD each
source "$(dirname "$0")/lib.sh"

create_cluster() { # name [hostPort:containerPort ...]
  local name=$1; shift
  # (not `kind get clusters`: it breaks on podman 6)
  if $CR container inspect "$name-control-plane" >/dev/null 2>&1; then ok "cluster $name exists"; return; fi
  local cfg="$GEN/kind-$name.yaml"
  {
    echo "kind: Cluster"
    echo "apiVersion: kind.x-k8s.io/v1alpha4"
    echo "name: $name"
    echo "nodes:"
    echo "- role: control-plane"
    echo "  extraPortMappings:"
    for m in "$@"; do
      echo "  - hostPort: ${m%%:*}"
      echo "    containerPort: ${m##*:}"
    done
  } > "$cfg"
  log "Creating kind cluster '$name'"
  kind create cluster --config "$cfg" --wait 120s
}

# kind switches your current kubectl context — put it back afterwards
prev_ctx=$(kubectl config current-context 2>/dev/null || true)
trap '[[ -n $prev_ctx ]] && kubectl config use-context "$prev_ctx" >/dev/null || true' EXIT

create_cluster "$MGMT_CLUSTER" "$KARGO_PORT:31443"
for env in "${ENV_CLUSTERS[@]}"; do
  create_cluster "$env" "$(argocd_port "$env"):30080" "$(app_port "$env"):30090"
done
ok "clusters ready: $MGMT_CLUSTER ${ENV_CLUSTERS[*]} (contexts: kind-<name>)"
