# GitLab flavour: Kargo + argocd-diff-preview + Renovate, shaped like `config-tde-dev5`

The same demo as the top-level README, rebuilt on **GitLab** so it looks like what
we run day to day:

- a source config repo, `config-tde-dev5`, with `config.yaml`, `apps/<app>/values.yaml` + `<env>-values.yaml` (helm pattern) and kustomize `base/` + `overlays/` (kustomize pattern)
- rendered **per-env repos**, `config-tde-dev5-dev`, `config-tde-dev5-staging` and `config-tde-dev5-prod`, each watched by its own Argo CD (app-of-apps over `argocd/apps/`)
- prod is gated by a **merge request** (`manual-promotion: true`)

It runs on **gitlab.com** (a group of your own), with kind clusters on the laptop.
Nothing touches code.swisscom.com.

## Today vs. with Kargo

| | Today (`cicd/cd` promotion component) | This demo |
|---|---|---|
| Who promotes | `deploy_<env>` jobs in `config-tde-dev5/.gitlab-ci.yml` | Kargo `Stage`s, one shared `PromotionTask` |
| Trigger | push to main, or the app pipeline triggers with `APP` + `VERSION` | Kargo **Warehouse** sees a new image tag *or* a new config commit and creates a **Freight** |
| Where the version lives | `app.version` written into `<env>-values.yaml` | inside the Freight (image + config commit), stamped at render time |
| Rendering | `promote.sh` (helm / kustomize / helm-kustomize patterns) | `helm-template` + `kustomize-build` steps |
| Env repos | `config-tde-dev5-<env>` | same, written by `kargo-bot` |
| Gated env | `manual-promotion: true` → MR on the env repo | `viaMergeRequest: "true"` → `git-open-pr` (provider gitlab) + wait for merge |
| "What runs in prod, and how did it get there?" | read pipelines and commit logs | one Freight alias per stage, full history, one-click rollback |
| Order guarantee | branch → env mapping | staging only takes Freight verified in dev, prod only from staging |
| MR review of config | YAML diff of values | **rendered diff per env** as an MR note (argocd-diff-preview) |
| Dependency bumps | manual | **Renovate** MRs → diff preview → same Kargo path |

Argo CD stays as it is. Kargo only writes git, so it can sit in front of the
existing env repos without touching the clusters.

## What runs where

| Where | What |
|---|---|
| gitlab.com `<group>/demo-app` | Dockerfile + `.gitlab-ci.yml` → `registry.gitlab.com/<group>/demo-app:x.y.z` (stand-in for Artifactory) |
| gitlab.com `<group>/config-tde-dev5` | source config. CI: `argocd-diff-preview` on MRs, `renovate` on a schedule |
| gitlab.com `<group>/config-tde-dev5-{dev,staging,prod}` | rendered manifests, **written only by Kargo** |
| kind `gl-mgmt` | Kargo |
| kind `gl-dev`, `gl-staging`, `gl-prod` | one Argo CD each, watching only its own env repo |

Architecture diagram: [kargo-demo on Excalidraw](https://app.excalidraw.com/s/3NqPjPnhAl/4VJRLKIZOJt)

## Setup

**Prerequisites:** podman or Docker (~8–12 GB for the VM), `kind`, `kubectl`, `helm`, `git`, `jq`, `curl`, `openssl`.

1. On gitlab.com, create a group for the demo (top-level groups can only be created in the UI), e.g. `<you>-dev5-demo`.
2. Create a **personal access token** with scopes `api`, `write_repository` and `read_registry`, and give it a short expiry.
3. Configure and start:

```bash
cd gitlab
cp demo.env.example demo.env      # set GITLAB_GROUP and GITLAB_TOKEN
make up                           # creates + seeds the 5 projects, clusters, Argo CD x3, Kargo
make release V=1.0.0              # first image (the pipeline needs ~2 min)
make status
```

`make up` is idempotent. It also tags `config-tde-dev5` with `demo-baseline` (what
`make reset` restores), sets the masked `GITLAB_PAT` CI variable, and schedules
Renovate on weekdays at 06:00.

| What | Where | Login |
|---|---|---|
| Kargo UI | http://localhost:8090 | `admin` / `admin1234` |
| Argo CD dev / staging / prod | http://localhost:8091 / 8092 / 8093 | `admin` / `admin1234` |
| The app dev / staging / prod | http://localhost:9091 / 9092 / 9093 | – |

Ports and cluster names differ from the GitHub flavour, so both can exist side by side (if you have the RAM).

## Talk track (~25 min)

`make reset` before you start (closes demo MRs, restores the baseline, recreates the Kargo project).

### Act 1: Kargo replaces the `deploy_<env>` jobs

1. **Starting state:** dev is green on :9091, and staging / prod are empty. Show `kargo/`: that's the
   whole pipeline, with **one** `PromotionTask` for all three spaces. Compare it to `config.yaml` spaces.
2. **The app team ships:** `make release`. demo-app's GitLab pipeline pushes a new tag, a Freight appears,
   and dev auto-promotes. Open `config-tde-dev5-dev` → `apps/demo-app/manifest.yaml`: plain rendered
   YAML, committed by `kargo-bot`, with the Freight in the commit message.
3. **Promote to staging:** click *Promote* (or `make promote TO=staging`). staging turns orange on :9092.
4. **prod = `manual-promotion: true`:** promote to prod. Kargo opens an **MR on
   `config-tde-dev5-prod`**, and its *Changes* tab is exactly what prod will run. Merge it, and prod turns blue.
5. **Guardrail:** try promoting dev-only Freight straight to prod. Kargo refuses.
6. **Rollback:** after a second release reaches staging, promote the older Freight to staging again.

### Act 2: catch it in the MR with argocd-diff-preview

| `make scenario NAME=…` | The MR says… | The diff-preview note shows… |
|---|---|---|
| `dev-only-flag` | "Enable new checkout flow in **dev**" | dev, staging **and prod** change, because it went into the shared `values.yaml` |
| `selector-rename` | "Small label cleanup" | the **immutable Deployment selector** changes in every env (and the Service no longer matches) |
| `prod-replicas` | "Scale prod" | prod replicas `3 → 30` |
| `good-change` | "dev-only cosmetic change" | only `demo-app-dev` changes |

The `argocd-diff-preview` job (docker-in-docker on the shared runners) starts an
ephemeral Argo CD, renders both branches and posts the diff as an MR note in about 3 minutes.

### Act 3: Renovate → diff preview → Kargo

1. `make renovate`. Renovate opens MRs on `config-tde-dev5` (redis minor, redis **major** with the `major-upgrade`
   label) and on `demo-app` (nginx base image).
2. On GitLab, Renovate's MRs **trigger MR pipelines directly**, so the diff preview just appears. GitHub needed a workaround here.
3. Merge the redis minor MR. A new Freight appears (*same image, new config commit*) and lands in dev only.
4. Promote it to staging, then to prod via MR. The dependency bump gets the same gated path as an app release.

## Mapping to the real platform

| Demo | Real world |
|---|---|
| gitlab.com group | `swisscom/<team>/.../development` on code.swisscom.com |
| `charts/microservice` | `blu-helm-microservice` |
| GitLab registry | Artifactory (`*-docker-local.artifactory.swisscom.com`), Kargo image creds secret |
| PAT in `gitlab-creds` | the `GROUP_PROMOTION_TOKEN` (or a GitLab service account with signed commits) |
| Kargo polls every 15 s | GitLab webhook receiver → instant Freight |
| kind clusters, local Kargo | Kargo on a management cluster, with sharding / Argo CD health via `kubeconfigSecrets.argocd` |
| static `argocd/apps/*.yaml` in env repos | generated today by the promotion component from `config.yaml` (`cd.apps`, `syncPolicy`, …) |

## Layout

```
kargo/             Project, Warehouse, PromotionTask, Stages (dev → staging → prod)
argocd/            Argo CD Helm values + the root app each cluster watches
repos/             seed content pushed to gitlab.com by `make up`
  config-tde-dev5/   config.yaml, charts/microservice, apps/{demo-app,redis}, argocd-preview/, .gitlab-ci.yml, renovate.json
  demo-app/          Dockerfile + .gitlab-ci.yml (build → registry)
  env-repo/          skeleton of config-tde-dev5-<env>
scripts/           setup/00-05, release, scenario, status, reset, down, lib.sh
demo.env.example   GITLAB_GROUP + GITLAB_TOKEN
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `group … not found` | Create the group in the GitLab UI first and put its full path in `demo.env`. |
| No Freight | No image yet: `make release V=1.0.0`. Check the registry is public (it follows project visibility). |
| Diff-preview job: no note | The `GITLAB_PAT` CI variable must be **unprotected** (MR pipelines run on unprotected branches). `make up` sets it this way. |
| Kargo push rejected on `main` | The token user needs Maintainer on the env repos (branch protection allows Maintainers to push). |
| prod promotion stays *Running* | It's waiting for its MR to be merged. That's the gate. |
