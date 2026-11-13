# shellcheck shell=bash
# Shared settings + helpers for every script in this demo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/bin"
GEN="$ROOT/.generated"          # kubeconfigs, keys (git-ignored)
export PATH="$BIN:$PATH"
mkdir -p "$BIN" "$GEN"

# ---- container runtime (podman or docker) -----------------------------------
if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
  CR=podman
  export KIND_EXPERIMENTAL_PROVIDER=podman
else
  CR=docker
fi

# ---- versions ---------------------------------------------------------------
KARGO_VERSION="${KARGO_VERSION:-1.12.5}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.18.0}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.3}"

# ---- GitHub -----------------------------------------------------------------
# Change with ./scripts/use-fork.sh <owner>/<repo>
GITHUB_REPO=david-wagih/kargo-promotion-demo
GITHUB_URL="https://github.com/$GITHUB_REPO.git"
IMAGE_REPO="ghcr.io/${GITHUB_REPO%%/*}/demo-app"
# Token Kargo uses to push env branches + open the prod PR (needs contents + pull-requests write).
# Defaults to your gh CLI token; prefer a fine-grained PAT scoped to this one repo.
github_token() { echo "${GITHUB_TOKEN:-$(gh auth token)}"; }

# ---- topology ---------------------------------------------------------------
ENV_CLUSTERS=(dev staging prod)    # one cluster + one Argo CD per environment
MGMT_CLUSTER=mgmt                  # Kargo control plane
KARGO_PORT=8443
argocd_port() { case $1 in dev) echo 8081;; staging) echo 8082;; prod) echo 8083;; esac; }
app_port()    { case $1 in dev) echo 9081;; staging) echo 9082;; prod) echo 9083;; esac; }

ARGOCD_PASSWORD=admin1234
KARGO_PASSWORD=admin1234

ctx() { echo "kind-$1"; }
k()   { local c=$1; shift; kubectl --context "$(ctx "$c")" "$@"; }

log()  { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m ✔  %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m !  %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m ✘  %s\033[0m\n' "$*" >&2; exit 1; }

bcrypt() { # bcrypt <password>
  if command -v htpasswd >/dev/null; then
    htpasswd -nbBC 10 "" "$1" | tr -d ':\n' | sed 's/$2y/$2a/'
  else
    kargo hash-password --password "$1"
  fi
}

wait_for() { # wait_for "desc" cmd...
  local desc=$1; shift
  for _ in $(seq 1 120); do "$@" >/dev/null 2>&1 && return 0; sleep 2; done
  die "timed out waiting for $desc"
}
