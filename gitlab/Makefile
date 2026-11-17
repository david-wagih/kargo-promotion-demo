# Kargo + argocd-diff-preview + Renovate on GitLab, shaped like config-tde-dev5.
# See README.md for the talk track.
SHELL := bash
S := ./scripts
.DEFAULT_GOAL := help

help:  ## show targets
	@grep -E '^[a-z0-9-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

up:  ## gitlab.com projects + 4 kind clusters + 3x Argo CD + Kargo (~10 min first time)
	$(S)/setup/00-prereqs.sh
	$(S)/setup/01-clusters.sh
	$(S)/setup/02-gitlab.sh
	$(S)/setup/03-argocd.sh
	$(S)/setup/04-kargo.sh
	$(S)/setup/05-pipeline.sh
	@echo; $(S)/status.sh

status:  ## what runs where + all URLs
	@$(S)/status.sh

release:  ## run demo-app's GitLab pipeline: next image version (or V=2.0.0)
	$(S)/release.sh $(V)

promote:  ## promote what the upstream stage has: make promote TO=staging|prod
	@test -n "$(TO)" || (echo "usage: make promote TO=staging" && exit 1)
	./bin/kargo promote --project dev5 --stage $(TO) --freight "$$(kubectl --context kind-gl-mgmt -n dev5 get stage $$( [ "$(TO)" = prod ] && echo staging || echo dev ) -o jsonpath='{.status.freightHistory[0].items.*.name}')"

scenario:  ## open an MR: make scenario NAME=dev-only-flag|selector-rename|prod-replicas|good-change
	@test -n "$(NAME)" || (echo "usage: make scenario NAME=dev-only-flag" && exit 1)
	$(S)/scenario.sh $(NAME)

renovate:  ## run the Renovate job on config-tde-dev5 now
	@. $(S)/lib.sh; gl POST "/projects/$$(pid $$SOURCE_REPO)/pipeline" -H 'Content-Type: application/json' \
	  -d '{"ref":"main","variables":[{"key":"RUN_RENOVATE","value":"true"}]}' | jq -r '"renovate pipeline: " + .web_url'

reset:  ## back to day 0 (keeps clusters)
	$(S)/reset.sh

down:  ## delete local clusters
	$(S)/down.sh

.PHONY: help up status release promote scenario renovate reset down
