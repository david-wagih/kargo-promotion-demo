#!/usr/bin/env bash
# Opens a realistic MR on config-tde-dev5: the kind of change that looks harmless in
# the YAML diff but the argocd-diff-preview note exposes before merge.
#   dev-only-flag    "enable a flag in dev" ... edited values.yaml -> hits staging + prod too
#   selector-rename  label "cleanup" in the chart changes an immutable Deployment selector everywhere
#   prod-replicas    "3" became "30" in prod
#   good-change      a genuinely dev-only change (diff shows only dev)
source "$(dirname "$0")/lib.sh"
NAME=${1:?usage: scenario.sh dev-only-flag|selector-rename|prod-replicas|good-change}
BRANCH="feature/$NAME"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

git clone -q --depth 1 "$(auth_url "$SOURCE_REPO")" "$TMP/repo"
cd "$TMP/repo"; git checkout -q -B "$BRANCH"

case $NAME in
  dev-only-flag)
    TITLE="Enable new checkout flow in dev"
    BODY="Just turning the new checkout on in **dev** so QA can test it."
    # ...but it goes into the shared values.yaml, so every environment gets it
    perl -0pi -e 's/(    REDIS_URL: redis:\/\/redis:6379\n)/$1    FEATURE_NEW_CHECKOUT: "true"\n/' apps/demo-app/values.yaml ;;
  selector-rename)
    TITLE="Use recommended app.kubernetes.io labels"
    BODY="Small label cleanup in the microservice chart, no functional change."
    perl -pi -e 's/^(\s+)app: \{\{ \.Values\.app\.name \}\}$/$1app.kubernetes.io\/name: {{ .Values.app.name }}/' \
      charts/microservice/templates/deployment.yaml ;;
  prod-replicas)
    TITLE="Scale prod for the sales event"
    BODY="Bump prod replicas from 3."
    perl -pi -e 's/replicas: 3/replicas: 30/' apps/demo-app/prod-values.yaml ;;
  good-change)
    TITLE="New dev banner text"
    BODY="dev-only cosmetic change."
    perl -pi -e 's/GREETING: deployed to the dev cluster/GREETING: dev — now with extra sparkle ✨/' apps/demo-app/dev-values.yaml ;;
  *) die "unknown scenario '$NAME'" ;;
esac

git -c user.name="A Developer" -c user.email=dev@noreply.gitlab.com commit -qam "$TITLE"
git push -q -f origin "$BRANCH" 2>/dev/null

url=$(gl GET "/projects/$(pid "$SOURCE_REPO")/merge_requests?state=opened&source_branch=$(urlenc "$BRANCH")" | jq -r '.[0].web_url // empty')
[[ -n $url ]] || url=$(gl POST "/projects/$(pid "$SOURCE_REPO")/merge_requests" \
  --data-urlencode "source_branch=$BRANCH" -d target_branch=main \
  --data-urlencode "title=$TITLE" --data-urlencode "description=$BODY" | jq -r .web_url)
ok "MR: $TITLE → $url"
echo "    the argocd-diff-preview job posts its note in ~3 min"
