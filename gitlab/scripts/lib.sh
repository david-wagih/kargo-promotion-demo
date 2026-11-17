# shellcheck shell=bash
# Shared settings + helpers for the GitLab flavour of the demo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/bin"
GEN="$ROOT/.generated"
export PATH="$BIN:$PATH"
mkdir -p "$BIN" "$GEN"

[[ -f "$ROOT/demo.env" ]] && source "$ROOT/demo.env"
: "${GITLAB_GROUP:?set GITLAB_GROUP in gitlab/demo.env (see demo.env.example)}"
: "${GITLAB_TOKEN:?set GITLAB_TOKEN in gitlab/demo.env (see demo.env.example)}"
[[ $GITLAB_GROUP == your-group/* ]] && { echo "edit gitlab/demo.env first" >&2; exit 1; }

# ---- container runtime (podman or docker) -----------------------------------
if command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
  CR=podman; export KIND_EXPERIMENTAL_PROVIDER=podman
else
  CR=docker
fi

# ---- versions ---------------------------------------------------------------
KARGO_VERSION="${KARGO_VERSION:-1.12.5}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.18.0}"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.21.3}"

# ---- GitLab -----------------------------------------------------------------
GITLAB=https://gitlab.com
API=$GITLAB/api/v4
SOURCE_REPO=config-tde-dev5                # like swisscom/.../development/config-tde-dev5
APP_REPO=demo-app
IMAGE_REPO="registry.gitlab.com/$GITLAB_GROUP/demo-app"
env_repo() { echo "config-tde-dev5-$1"; }  # like config-tde-dev5-dev
auth_url() { echo "https://oauth2:$GITLAB_TOKEN@gitlab.com/$GITLAB_GROUP/$1.git"; }
urlenc()   { jq -rn --arg s "$1" '$s|@uri'; }
pid()      { urlenc "$GITLAB_GROUP/$1"; }   # project id for the API = url-encoded path
gl() { # gl METHOD path [curl args...]
  local m=$1 p=$2; shift 2
  curl -fsS -X "$m" -H "PRIVATE-TOKEN: $GITLAB_TOKEN" "$API$p" "$@"
}

# ---- topology (separate cluster names/ports: can coexist with the GitHub flavour)
ENV_CLUSTERS=(dev staging prod)
MGMT_CLUSTER=gl-mgmt
cluster()     { echo "gl-$1"; }
KARGO_PORT=8090
argocd_port() { case $1 in dev) echo 8091;; staging) echo 8092;; prod) echo 8093;; esac; }
app_port()    { case $1 in dev) echo 9091;; staging) echo 9092;; prod) echo 9093;; esac; }

ARGOCD_PASSWORD=admin1234
KARGO_PASSWORD=admin1234

ctx() { echo "kind-$1"; }
k()   { local c=$1; shift; kubectl --context "$(ctx "$c")" "$@"; }   # k <cluster> ...
ke()  { local e=$1; shift; k "$(cluster "$e")" "$@"; }               # ke <env> ...

log()  { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m ✔  %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m !  %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m ✘  %s\033[0m\n' "$*" >&2; exit 1; }

# fill the __GITLAB_GROUP__ / __ENV__ / __REPO_NAME__ placeholders in seed files
render() { sed -e "s#__GITLAB_GROUP__#$GITLAB_GROUP#g" -e "s#__ENV__#${2:-}#g" -e "s#__REPO_NAME__#${3:-}#g" "$1"; }

bcrypt() {
  if command -v htpasswd >/dev/null; then htpasswd -nbBC 10 "" "$1" | tr -d ':\n' | sed 's/$2y/$2a/'
  else kargo hash-password --password "$1"; fi
}

wait_for() { # wait_for "desc" cmd...
  local desc=$1; shift
  for _ in $(seq 1 120); do "$@" >/dev/null 2>&1 && return 0; sleep 2; done
  die "timed out waiting for $desc"
}

registry_tags() { # semver tags of demo-app in the GitLab registry
  local rid
  rid=$(gl GET "/projects/$(pid "$APP_REPO")/registry/repositories" | jq -r '.[0].id // empty')
  [[ -n $rid ]] || return 0
  gl GET "/projects/$(pid "$APP_REPO")/registry/repositories/$rid/tags?per_page=100" \
    | jq -r '.[].name | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))'
}
