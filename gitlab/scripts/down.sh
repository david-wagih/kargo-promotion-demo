#!/usr/bin/env bash
# Deletes the local clusters. gitlab.com projects and images are left alone
# (delete the group in the GitLab UI when you're done).
source "$(dirname "$0")/lib.sh"
for c in "$MGMT_CLUSTER" $(for e in "${ENV_CLUSTERS[@]}"; do cluster "$e"; done); do
  $CR container inspect "$c-control-plane" >/dev/null 2>&1 && kind delete cluster --name "$c"
done
rm -rf "$GEN"
ok "local clusters removed"
