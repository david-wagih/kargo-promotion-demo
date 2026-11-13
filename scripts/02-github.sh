#!/usr/bin/env bash
# Prepares the GitHub repo:
#   - env/dev, env/staging, env/prod branches = the per-environment config "repos"
#     (each cluster's Argo CD watches exactly one of them; only Kargo writes to them)
#   - lets GitHub Actions open PRs (Renovate runs with the workflow's GITHUB_TOKEN)
source "$(dirname "$0")/lib.sh"

gh api "repos/$GITHUB_REPO" --jq .default_branch >/dev/null || die "repo $GITHUB_REPO not reachable"
[[ -n $(gh api "repos/$GITHUB_REPO/branches/main" --jq .name 2>/dev/null) ]] \
  || die "push this project to $GITHUB_REPO main first (see README → Setup)"

for env in "${ENV_CLUSTERS[@]}"; do
  if gh api "repos/$GITHUB_REPO/branches/env/$env" >/dev/null 2>&1; then ok "branch env/$env exists"; continue; fi
  tmp=$(mktemp -d)
  git -C "$tmp" init -q -b "env/$env"
  mkdir -p "$tmp/manifests"; touch "$tmp/manifests/.gitkeep"
  printf '# env/%s\n\nRendered manifests for **%s**, watched by the %s cluster'"'"'s Argo CD.\nWritten only by Kargo — do not edit by hand.\n' "$env" "$env" "$env" > "$tmp/README.md"
  git -C "$tmp" add -A
  git -C "$tmp" -c user.name=kargo-bot -c user.email=kargo-bot@users.noreply.github.com commit -qm "Initialize env/$env"
  git -C "$tmp" push -q "https://x-access-token:$(github_token)@github.com/$GITHUB_REPO.git" "env/$env" 2>/dev/null
  rm -rf "$tmp"
  ok "branch env/$env created"
done

gh api -X PUT "repos/$GITHUB_REPO/actions/permissions/workflow" \
  -f default_workflow_permissions=write -F can_approve_pull_request_reviews=true >/dev/null
ok "GitHub Actions may open PRs (needed by the Renovate workflow)"

ghcr_tags() {
  local t; t=$(curl -fsS "https://ghcr.io/token?scope=repository:${IMAGE_REPO#ghcr.io/}:pull" | jq -r .token) || return 1
  curl -fsS -H "Authorization: Bearer $t" "https://ghcr.io/v2/${IMAGE_REPO#ghcr.io/}/tags/list" | jq -e '.tags | length > 0' >/dev/null
}
if ghcr_tags 2>/dev/null; then
  ok "image $IMAGE_REPO is public"
else
  warn "image $IMAGE_REPO not public yet — run 'make release V=1.0.0', then set the package to Public:"
  warn "  https://github.com/users/${GITHUB_REPO%%/*}/packages/container/demo-app/settings"
fi
