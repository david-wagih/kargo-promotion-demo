#!/usr/bin/env bash
# Opens a realistic PR on GitHub — the kind of change that looks harmless in the
# YAML diff but the argocd-diff-preview comment exposes before merge.
#
#   ./scripts/scenario.sh dev-only-flag     "enable a flag in dev" ... edited base → hits staging + prod too
#   ./scripts/scenario.sh selector-rename   label "cleanup" changes an immutable Deployment selector everywhere
#   ./scripts/scenario.sh prod-replicas     "3" became "30" in prod
#   ./scripts/scenario.sh good-change       a genuinely dev-only change (diff shows only dev)
source "$(dirname "$0")/lib.sh"
NAME=${1:?usage: scenario.sh dev-only-flag|selector-rename|prod-replicas|good-change}
BRANCH="feature/$NAME"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

git clone -q --depth 1 "https://x-access-token:$(github_token)@github.com/$GITHUB_REPO.git" "$TMP/repo"
cd "$TMP/repo/platform-config"
git checkout -q -B "$BRANCH"

case $NAME in
  dev-only-flag)
    TITLE="Enable new checkout flow in dev"
    BODY="Just turning the new checkout on in **dev** so QA can test it."
    # ...but the env var is added to base/, so every environment gets it
    perl -0pi -e 's/(            - name: REDIS_URL\n              value: redis:\/\/redis:6379\n)/$1            - name: FEATURE_NEW_CHECKOUT\n              value: "true"\n/' base/demo-app.yaml ;;
  selector-rename)
    TITLE="Use recommended app.kubernetes.io labels"
    BODY="Small label cleanup, no functional change."
    perl -pi -e 's/^(\s+)app: demo-app$/$1app.kubernetes.io\/name: demo-app/' base/demo-app.yaml ;;
  prod-replicas)
    TITLE="Scale prod for the sales event"
    BODY="Bump prod replicas from 3."
    perl -pi -e 's/count: 3/count: 30/' overlays/prod/kustomization.yaml ;;
  good-change)
    TITLE="New dev banner text"
    BODY="Dev-only cosmetic change."
    perl -pi -e 's/GREETING=deployed to the dev cluster/GREETING=dev — now with extra sparkle ✨/' overlays/dev/kustomization.yaml ;;
  *) die "unknown scenario '$NAME'" ;;
esac

git -c user.name="A Developer" -c user.email=dev@users.noreply.github.com commit -qam "$TITLE"
git push -q -f origin "$BRANCH" 2>/dev/null

url=$(gh pr list -R "$GITHUB_REPO" --head "$BRANCH" --state open --json url -q '.[0].url // empty')
[[ -n $url ]] || url=$(gh pr create -R "$GITHUB_REPO" --head "$BRANCH" --base main --title "$TITLE" --body "$BODY")
ok "PR: $TITLE → $url"
echo "    the 'Argo CD Diff Preview' check will comment on it in ~2 min"
