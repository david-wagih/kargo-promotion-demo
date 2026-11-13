#!/usr/bin/env bash
# Guided demo: walks through all three acts, running each step and waiting for the
# real outcome (Freight created, Argo CD synced, PR comment posted, PR merged...).
#
#   ./scripts/demo.sh          interactive: pauses before each step; you merge PRs in the GitHub UI
#   ./scripts/demo.sh 2        start at act 2 (acts: 1 Kargo, 2 diff preview, 3 Renovate)
#   AUTO=1 ./scripts/demo.sh   unattended dress rehearsal (no pauses, merges PRs itself)
#
# Start from a clean slate with `make reset`.
source "$(dirname "$0")/lib.sh"
START_ACT=${1:-1}
AUTO=${AUTO:-0}
M=$MGMT_CLUSTER

# ---- presentation helpers -----------------------------------------------------
act()  { printf '\n\033[1;45m  ACT %s  \033[0m \033[1m%s\033[0m\n' "$1" "$2"; }
say()  { printf '\033[0;37m    %s\033[0m\n' "$@"; }
step() { # step "title" — pause until Enter (unless AUTO)
  printf '\n\033[1;34m▶ %s\033[0m\n' "$1"
  [[ $AUTO == 1 ]] || read -r -p "    [enter] " _ </dev/tty
}
until_true() { # until_true "desc" timeout_s cmd...
  local desc=$1 t=$2; shift 2
  printf '    ⏳ %s ' "$desc"
  for _ in $(seq 1 $((t / 5))); do
    if "$@" >/dev/null 2>&1; then printf '\033[1;32m✔\033[0m\n'; return 0; fi
    printf '.'; sleep 5
  done
  printf '\n'; die "timed out: $desc"
}

# ---- state helpers ------------------------------------------------------------
app_version() { curl -fs "http://localhost:$(app_port "$1")/" | sed -n 's/.*demo-app \([0-9.]*\)<.*/\1/p'; }
redis_tag()   { k "$1" -n demo-app get deploy redis -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null | sed 's/.*://'; }
serves()      { [[ $(app_version "$1") == "$2" ]]; }
runs_redis()  { [[ $(redis_tag "$1") == "$2" ]]; }
stage_freight() { k $M -n dev5 get stage "$1" -o jsonpath='{.status.freightHistory[0].items.*.name}'; }
freight_alias() { k $M -n dev5 get freight "$1" -o jsonpath='{.alias}'; }
freight_for_tag() { # newest Freight carrying image tag $1
  k $M -n dev5 get freight -o json | jq -r --arg t "$1" \
    '[.items[] | select(.images[0].tag==$t)] | sort_by(.metadata.creationTimestamp) | last | .metadata.name'
}
promote() { # promote <stage> <freight>
  say "kargo promote --stage $1 --freight-alias $(freight_alias "$2")"
  kargo promote --project dev5 --stage "$1" --freight "$2" >/dev/null
}
pr_for_branch() { gh pr list -R "$GITHUB_REPO" --state open --json number,headRefName -q ".[] | select(.headRefName | test(\"$1\")) | .number" | head -1; }
has_diff_comment() { [[ $(gh pr view "$1" -R "$GITHUB_REPO" --json comments -q '[.comments[].body | select(startswith("## Argo CD Diff Preview"))] | length') -gt 0 ]]; }
show_diff_summary() {
  gh pr view "$1" -R "$GITHUB_REPO" --json comments \
    -q '[.comments[].body | select(startswith("## Argo CD Diff Preview"))] | last' \
    | awk '/^Summary:/{f=1;next} f&&/^```$/{if(++n==2)exit;next} f' | sed 's/^/      /'
}
merged() { [[ $(gh pr view "$1" -R "$GITHUB_REPO" --json state -q .state) == MERGED ]]; }
merge_pr() { # merge_pr <number> — you merge in the UI, or the script does in AUTO mode
  local url="https://github.com/$GITHUB_REPO/pull/$1"
  if [[ $AUTO == 1 ]]; then gh pr merge "$1" -R "$GITHUB_REPO" --merge >/dev/null; say "merged $url"
  else say "👉 review + merge: $url"; fi
  until_true "PR #$1 merged" 1800 merged "$1"
}
open_scenario() { # open_scenario <name> -> prints PR summary once diff preview commented
  "$ROOT/scripts/scenario.sh" "$1" | grep '✔' || true
  local pr; pr=$(pr_for_branch "^feature/$1$")
  until_true "argocd-diff-preview comment on #$pr (GitHub Actions)" 600 has_diff_comment "$pr"
  show_diff_summary "$pr"
  say "full diff: https://github.com/$GITHUB_REPO/pull/$pr"
}

# ===============================================================================
if (( START_ACT <= 1 )); then
act 1 "Kargo replaces the overlay-folder pipeline"
step "Starting point"
"$ROOT/scripts/status.sh"
say "Kargo UI: https://localhost:$KARGO_PORT  — the whole pipeline is the 4 files in kargo/"

step "CI ships a new build (GitHub Actions → GHCR)"
"$ROOT/scripts/release.sh" | grep -E '✔|https'
V1=$(cat "$GEN/last-release")
F1=""; until_true "Kargo created Freight for $V1" 120 bash -c "[[ \$(kubectl --context kind-$M -n dev5 get freight -o json | jq -r '.items[].images[0].tag' | grep -cx '$V1') -gt 0 ]]"
F1=$(freight_for_tag "$V1")
say "Freight '$(freight_alias "$F1")' = demo-app $V1 + current platform-config commit"
until_true "dev auto-promoted and serving $V1 (http://localhost:$(app_port dev))" 300 serves dev "$V1"
say "rendered YAML: https://github.com/$GITHUB_REPO/commits/env/dev"

step "Promote to staging (one click in the UI)"
promote staging "$F1"
until_true "staging serving $V1 (http://localhost:$(app_port staging))" 300 serves staging "$V1"

step "Promote to prod — Kargo opens a GitHub PR with the rendered diff"
promote prod "$F1"
until_true "Kargo opened the promotion PR" 120 bash -c "[[ -n \$(gh pr list -R $GITHUB_REPO --state open --json headRefName -q '.[] | select(.headRefName | startswith(\"kargo/promotion/prod\")) | .headRefName') ]]"
merge_pr "$(pr_for_branch '^kargo/promotion/prod')"
until_true "prod serving $V1 (http://localhost:$(app_port prod))" 300 serves prod "$V1"

step "Another build — and the guardrail"
"$ROOT/scripts/release.sh" | grep -E '✔|https'
V2=$(cat "$GEN/last-release")
until_true "dev serving $V2" 300 serves dev "$V2"
F2=$(freight_for_tag "$V2")
say "Try to skip staging: kargo promote --stage prod --freight-alias $(freight_alias "$F2")"
if out=$(kargo promote --project dev5 --stage prod --freight "$F2" 2>&1); then
  die "expected Kargo to refuse this promotion"
fi
printf '    \033[1;31m%s\033[0m\n' "$(echo "$out" | sed -n 's/.*"error":"\(.*\)"}.*/\1/p' | sed 's/\\"/"/g')"

step "Promote $V2 to staging, then roll staging back to $V1"
promote staging "$F2"
until_true "staging serving $V2" 300 serves staging "$V2"
promote staging "$F1"
until_true "staging rolled back to $V1" 300 serves staging "$V1"
"$ROOT/scripts/status.sh" | head -5
fi

# ===============================================================================
if (( START_ACT <= 2 )); then
act 2 "Catch problems before merge with argocd-diff-preview"
step "PR: 'Enable new checkout flow in dev' (edited base/ ...)"
open_scenario dev-only-flag
say "→ 'dev only' actually changes staging and prod too"

step "PR: 'Small label cleanup'"
open_scenario selector-rename
say "→ immutable Deployment selector changes in every env: sync would fail everywhere after merge"

step "PR: a genuinely dev-only change"
open_scenario good-change
say "→ only demo-app-dev changes — that's what a safe PR looks like"
fi

# ===============================================================================
if (( START_ACT <= 3 )); then
act 3 "Renovate + diff preview + Kargo"
step "Run Renovate (GitHub Actions)"
gh workflow run renovate.yaml -R "$GITHUB_REPO"
sleep 5
run=$(gh run list -R "$GITHUB_REPO" --workflow renovate.yaml --limit 1 --json databaseId -q '.[0].databaseId')
say "https://github.com/$GITHUB_REPO/actions/runs/$run"
gh run watch "$run" -R "$GITHUB_REPO" --exit-status >/dev/null
gh pr list -R "$GITHUB_REPO" --state open --json number,title,headRefName \
  -q '.[] | select(.headRefName | startswith("renovate/")) | "      #\(.number) \(.title)"'

PR=$(pr_for_branch '^renovate/redis-7')
OLD_REDIS=$(redis_tag dev)
NEW_REDIS=$(gh pr view "$PR" -R "$GITHUB_REPO" --json title -q .title | sed 's/.* to v//')
step "Diff preview on the Renovate PR #$PR (redis $OLD_REDIS → $NEW_REDIS)"
until_true "argocd-diff-preview comment on #$PR" 600 has_diff_comment "$PR"
show_diff_summary "$PR"

step "Merge it → Kargo turns it into Freight → dev only"
merge_pr "$PR"
kargo refresh warehouse dev5 --project dev5 >/dev/null 2>&1 || true
until_true "dev running redis $NEW_REDIS" 300 runs_redis dev "$NEW_REDIS"
"$ROOT/scripts/status.sh" | head -5
say "staging + prod keep redis $OLD_REDIS until someone promotes it"

step "Promote the upgrade through staging and prod"
F3=$(stage_freight dev)
promote staging "$F3"
until_true "staging running redis $NEW_REDIS" 300 runs_redis staging "$NEW_REDIS"
promote prod "$F3"
until_true "Kargo opened the promotion PR" 120 bash -c "[[ -n \$(gh pr list -R $GITHUB_REPO --state open --json headRefName -q '.[] | select(.headRefName | startswith(\"kargo/promotion/prod\")) | .headRefName') ]]"
merge_pr "$(pr_for_branch '^kargo/promotion/prod')"
until_true "prod running redis $NEW_REDIS" 300 runs_redis prod "$NEW_REDIS"
fi

printf '\n'; "$ROOT/scripts/status.sh"
ok "demo complete — 'make reset' to run it again"
