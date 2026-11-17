#!/usr/bin/env bash
# Checks tools + the GitLab token, downloads the kargo CLI into ./bin
source "$(dirname "$0")/../lib.sh"

log "Checking required tools"
for t in kind kubectl helm git curl jq openssl; do
  command -v $t >/dev/null || die "missing '$t' (brew install $t)"
done
command -v "$CR" >/dev/null || die "need podman or docker"
user=$(gl GET /user | jq -r .username) || die "GITLAB_TOKEN rejected by gitlab.com"
gl GET "/groups/$(urlenc "$GITLAB_GROUP")" >/dev/null \
  || die "group $GITLAB_GROUP not found: create it at $GITLAB/groups/new (top-level) or as a subgroup"
ok "container runtime: $CR, gitlab.com user: $user, group: $GITLAB_GROUP"

os=$(uname -s | tr '[:upper:]' '[:lower:]')
[[ $(uname -m) == x86_64 ]] && karch=amd64 || karch=arm64
if ! "$BIN/kargo" version --client >/dev/null 2>&1; then
  log "Downloading kargo CLI v$KARGO_VERSION"
  curl -fsSL -o "$BIN/kargo" "https://github.com/akuity/kargo/releases/download/v$KARGO_VERSION/kargo-$os-$karch"
  chmod +x "$BIN/kargo"
fi
ok "kargo CLI: $("$BIN/kargo" version --client 2>/dev/null | head -1)"

if [[ $CR == podman ]]; then
  # several kind clusters exhaust the rootless podman VM's default kernel keyring
  if [[ $(podman machine ssh sysctl -n kernel.keys.maxkeys 2>/dev/null | tr -d '\r') -lt 20000 ]]; then
    log "Raising kernel keyring limits inside the podman VM"
    podman machine ssh "printf 'kernel.keys.maxkeys=20000\nkernel.keys.maxbytes=2000000\n' | sudo tee /etc/sysctl.d/99-kind-keys.conf >/dev/null && sudo sysctl -q --system"
  fi
  ok "podman VM keyring limits ok"
fi
