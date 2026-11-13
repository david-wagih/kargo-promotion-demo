#!/usr/bin/env bash
# Removes all local clusters (GitHub repo, branches and GHCR images are left alone).
source "$(dirname "$0")/lib.sh"
for c in "$MGMT_CLUSTER" "${ENV_CLUSTERS[@]}"; do
  $CR container inspect "$c-control-plane" >/dev/null 2>&1 && kind delete cluster --name "$c"
done
rm -rf "$GEN"
ok "local demo removed"
