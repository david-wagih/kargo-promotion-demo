#!/usr/bin/env bash
# Creates and seeds the gitlab.com projects (idempotent):
#   demo-app                   app repo: Dockerfile + CI that pushes to the GitLab registry
#   config-tde-dev5            source config repo: values, kustomize, diff preview + Renovate CI
#   config-tde-dev5-<env>      rendered env repos, one per cluster, written only by Kargo
source "$(dirname "$0")/../lib.sh"
SEED="$ROOT/repos"
gid=$(gl GET "/groups/$(urlenc "$GITLAB_GROUP")" | jq -r .id)

ensure_project() { # name description
  if gl GET "/projects/$(pid "$1")" >/dev/null 2>&1; then ok "project $1 exists"; return; fi
  gl POST /projects --data-urlencode "name=$1" --data-urlencode "path=$1" \
    --data-urlencode "description=$2" -d namespace_id="$gid" -d visibility=public \
    -d initialize_with_readme=false -d public_jobs=false >/dev/null
  ok "project $1 created"
}

allow_pipeline_vars() { # newer GitLab blocks pipeline variables (VERSION, RUN_RENOVATE) by default
  gl PUT "/projects/$(pid "$1")" -d ci_pipeline_variables_minimum_override_role=developer >/dev/null
}

seed() { # name srcdir [env]  -> first push to main if the project is still empty
  local name=$1 src=$2 env=${3:-} tmp
  if [[ $(gl GET "/projects/$(pid "$name")/repository/branches" | jq length) -gt 0 ]]; then
    ok "$name already has content"; return
  fi
  tmp=$(mktemp -d)
  (cd "$src" && find . -type f) | while read -r f; do
    mkdir -p "$tmp/$(dirname "$f")"; render "$src/$f" "$env" "$name" > "$tmp/$f"
  done
  git -C "$tmp" init -q -b main && git -C "$tmp" add -A
  git -C "$tmp" -c user.name=demo-setup -c user.email=demo-setup@noreply.gitlab.com commit -qm "Initial $name"
  git -C "$tmp" push -q "$(auth_url "$name")" main 2>/dev/null
  rm -rf "$tmp"; ok "$name seeded"
}

ensure_project "$APP_REPO" "demo-app: image built by GitLab CI, promoted by Kargo"
seed "$APP_REPO" "$SEED/demo-app"
allow_pipeline_vars "$APP_REPO"

ensure_project "$SOURCE_REPO" "Source config repo (values + kustomize). Kargo renders it into config-tde-dev5-<env>"
seed "$SOURCE_REPO" "$SEED/config-tde-dev5"
allow_pipeline_vars "$SOURCE_REPO"
for env in "${ENV_CLUSTERS[@]}"; do
  ensure_project "$(env_repo "$env")" "Rendered manifests for $env, written only by Kargo"
  seed "$(env_repo "$env")" "$SEED/env-repo" "$env"
done

# Day-0 tag that `make reset` restores config-tde-dev5 from
if ! gl GET "/projects/$(pid "$SOURCE_REPO")/repository/tags/demo-baseline" >/dev/null 2>&1; then
  gl POST "/projects/$(pid "$SOURCE_REPO")/repository/tags" -d tag_name=demo-baseline -d ref=main >/dev/null
  ok "tag demo-baseline created on $SOURCE_REPO"
fi

# CI variable for the diff-preview MR note + Renovate (unprotected: MR pipelines run on feature branches)
for p in "$SOURCE_REPO"; do
  gl DELETE "/projects/$(pid "$p")/variables/GITLAB_PAT" >/dev/null 2>&1 || true
  gl POST "/projects/$(pid "$p")/variables" -d key=GITLAB_PAT --data-urlencode "value=$GITLAB_TOKEN" \
    -d masked=true -d protected=false >/dev/null
done
ok "CI variable GITLAB_PAT set on $SOURCE_REPO (masked)"

if [[ $(gl GET "/projects/$(pid "$SOURCE_REPO")/pipeline_schedules" | jq 'map(select(.description=="renovate")) | length') -eq 0 ]]; then
  gl POST "/projects/$(pid "$SOURCE_REPO")/pipeline_schedules" -d description=renovate -d ref=main \
    --data-urlencode "cron=0 6 * * 1-5" -d cron_timezone=Europe/Zurich >/dev/null
  ok "Renovate schedule: weekdays 06:00"
fi

if [[ -z $(registry_tags) ]]; then
  warn "no demo-app image yet: run 'make release V=1.0.0' before Kargo can create Freight"
else
  ok "demo-app images: $(registry_tags | sort -V | tr '\n' ' ')"
fi
