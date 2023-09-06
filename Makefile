# No slash at the end please
REPO_PREFIX ?= myrepo
DOCKER ?= docker

.PHONY: build
build:
	$(DOCKER) build --pull \
		--build-arg BUILD_OPTIONS="$$BUILD_OPTIONS" \
		--build-arg REPO_PREFIX="$$REPO_PREFIX/" \
		-t $(REPO_PREFIX)/mast \
			./mast

.PHONY: quick
quick:
	BUILD_OPTIONS='--notest' make -s build

.PHONY: push
push:
	$(DOCKER) push $(REPO_PREFIX)/mast

.PHONY: local-quick
local-quick:
	$(DOCKER) build --pull --build-arg BUILD_OPTIONS='--notest' -t mast ./mast
