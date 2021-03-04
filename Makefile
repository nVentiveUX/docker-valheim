# Project tasks
#
SHELL := /bin/bash
.DEFAULT_GOAL := help

image: ## Build the docker image locally
	@DOCKER_BUILDKIT=1 docker build -t nventiveux/docker-valheim:latest .

tests: ## Tests the server
tests: image
	@docker run \
		--rm \
		-it \
		--name "valheim" \
		--publish 2456-2457:2456-2457/udp \
		nventiveux/docker-valheim:latest \
		./valheim_server.x86_64 -name "nVentiveUX" -port 2456 -world "Dedicated" -password "ChangeMe1234"


# Self documenting
# https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
help: ### Show this help
	@printf "Targets:\\n\\n"
	@grep -E '^[a-zA-Z_-]+:.*?\s## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?\\s## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

.PHONY: help image tests
