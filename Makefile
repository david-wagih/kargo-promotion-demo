# Kargo + argocd-diff-preview + Renovate demo — see README.md for the talk track.
S := ./scripts
.DEFAULT_GOAL := help

help:  ## show targets
	@grep -E '^[a-z0-9-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

up:  ## create local clusters + Argo CD + Kargo and wire them to GitHub (~10 min first time)
	$(S)/00-prereqs.sh
	$(S)/01-clusters.sh
	$(S)/02-github.sh
	$(S)/03-argocd.sh
	$(S)/04-kargo.sh
	$(S)/05-pipeline.sh
	@echo; $(S)/status.sh

status:  ## what runs where + all URLs
	@$(S)/status.sh

demo:  ## guided demo, pauses before each step (ACT=2 to start at act 2)
	$(S)/demo.sh $(or $(ACT),1)

rehearse:  ## unattended full run of the demo (merges PRs itself), then reset
	AUTO=1 $(S)/demo.sh
	$(S)/reset.sh

release:  ## GitHub Actions builds + pushes the next image version (or V=2.0.0)
	$(S)/release.sh $(V)

promote:  ## promote what's in the upstream stage: make promote TO=staging|prod
	@test -n "$(TO)" || (echo "usage: make promote TO=staging" && exit 1)
	./bin/kargo promote --project dev5 --stage $(TO) --freight "$$(kubectl --context kind-mgmt -n dev5 get stage $$( [ "$(TO)" = prod ] && echo staging || echo dev ) -o jsonpath='{.status.freightHistory[0].items.*.name}')"

scenario:  ## open a PR: make scenario NAME=dev-only-flag|selector-rename|prod-replicas|good-change
	@test -n "$(NAME)" || (echo "usage: make scenario NAME=dev-only-flag" && exit 1)
	$(S)/scenario.sh $(NAME)

renovate:  ## run the Renovate workflow on GitHub Actions now
	gh workflow run renovate.yaml -R $$(grep '^GITHUB_REPO=' $(S)/lib.sh | cut -d= -f2)

reset:  ## back to day 0 (keeps clusters)
	$(S)/reset.sh

down:  ## delete local clusters
	$(S)/down.sh

.PHONY: help up status demo rehearse release promote scenario renovate reset down
