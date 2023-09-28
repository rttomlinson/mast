# No slash at the end, please
REPO_PREFIX := rttomlinson
BASE_REPO := rttomlinson
# We want to update the build-tools container image without producing
# extra stdout output that might spoil the data output of the consequently
# called command. `docker run --pull always` will print the pulled image
# hash and there is no way to silence that, hence pull in a separate command.
BUILD_TOOLS := docker pull -q $(REPO_PREFIX)/build-tools >/dev/null 2>&1; \
               docker run --rm -i $(REPO_PREFIX)/build-tools

# This weird double assignment is to resolve the value instead of
# calculating it at every call site
GIT_COMMIT ?= $(shell git rev-parse --short=10 HEAD 2>/dev/null)
GIT_COMMIT := $(GIT_COMMIT)
GIT_BRANCH ?= $(shell git symbolic-ref -q HEAD |sed 's/refs\/heads\///')
GIT_BRANCH := $(GIT_BRANCH)
GIT_TAG ?= $(shell git describe --tags)
GIT_TAG := $(GIT_TAG)
CWD ?= $(shell pwd)
BUILD_VERSION ?= $(GIT_BRANCH)-$(GIT_COMMIT)
BUILD_VERSION := $(BUILD_VERSION)
ghprbTargetBranch ?= local
NEXUS_STAGE ?= development
GIT_ENV ?= development
GIT_COMMIT_TAG := $(GIT_COMMIT)-$(NEXUS_STAGE)
GHPRB_ID_TAG ?= ghprb-$(GITHUB_PR_ID)-$(BUILD_VERSION)
GHPRB_ID_TAG := $(GHPRB_ID_TAG)
# TODO Clean up all other tag variable uses except CONTAINER_TAG
CONTAINER_TAG := $(GIT_COMMIT_TAG)
GIT_BRANCH_HASH := $(shell $(BUILD_TOOLS) sha256 $(GIT_BRANCH) 8)
GET_SERVICE_SPEC := $(BUILD_TOOLS) get_validated_spec \
		--token BUILD_NUMBER=${BUILD_NUMBER} \
		--token BUILD_VERSION=${BUILD_VERSION} \
		--token GIT_BRANCH=${GIT_BRANCH} \
		--token GIT_COMMIT=${GIT_COMMIT} \
		--token FEATURE_BRANCH_HOSTNAME=${FEATURE_BRANCH_HOSTNAME} \
		--token GITHUB_PR_ID=${GITHUB_PR_ID} \
		--token GHPRB_ID_TAG=${GHPRB_ID_TAG} \
		--token GIT_BRANCH_HASH=${GIT_BRANCH_HASH}
GIT_CHANGELOG := git log --format='%H|%aN|%aE|%cN|%cE|%s' ${GIT_PREVIOUS_SUCCESSFUL_COMMIT}..${GIT_COMMIT}
JSONIFY_CHANGELOG := jq -nRc '[inputs|split("|")|{hash:.[0],authorName:.[1],authorEmail:.[2],committerName:.[3],committerEmail:.[4],subject:.[5]}]'

MOCK_SCENARIO ?= 'unit-test'

.PHONY: echo-version
echo-version:
	@echo $(BUILD_VERSION)

.PHONY: echo-container-tag
echo-container-tag:
	@echo $(CONTAINER_TAG)

.PHONY: echo-container-image-%
echo-container-image-%:
	@echo $(BASE_REPO)/$*:$(CONTAINER_TAG)

.PHONY: echo-nexus-service-spec
echo-nexus-service-spec:
	@SERVICE_SPEC=$$(${GET_SERVICE_SPEC} < ${NEXUS_SERVICE_SPEC}) && \
		echo "$$SERVICE_SPEC"

.PHONY: echo-graphql-service-spec
echo-graphql-service-spec:
	@SERVICE_SPEC=$$(${GET_SERVICE_SPEC} < ${GRAPHQL_SERVICE_SPEC}) && \
		echo "$$SERVICE_SPEC"

.PHONY: help build-all
.PHONY: docker-push-all-%
.PHONY: docker-push-commit-%
.PHONY: docker-push-tag-%
.PHONY: docker-rollback-push-tag-%
.PHONY: docker-push-branch-%
.PHONY: docker-tag-all-%
.PHONY: docker-tag-branch-%
.PHONY: docker-tag-gittag-%
.PHONY: docker-rollback-tag-gittag-%
.PHONY: docker-commit-rollback-tag-gittag-%
.PHONY: docker-tag-last-release-%
.PHONY: docker-push-last-release-%
.PHONY: docker-tag-version-%
.PHONY: docker-push-version-%
.PHONY: docker-tag-pr-%
.PHONY: docker-push-pr-%

# Add the following 'help' target to your Makefile
# And add help text after each target name starting with '\#\#'
help:	## Show this help message.
	@echo 'usage: make [target] ...'
	@echo
	@echo 'targets:'
	@egrep '^(.+)\:\s##\s(.+)' $(MAKEFILE_LIST) |sed 's/^/  /' | column -t -c 2 -s ':#'

clean:	## run all clean targets
clean: ui-clean graphql-clean

docker-push-all-%: docker-push-commit-% docker-push-tag-% docker-push-branch-%
	@echo pushed all container tags

docker-push-commit-%:
	docker image push $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG)
	@echo pushed docker container $(BASE_REPO)/$*:$(GIT_COMMIT_TAG)

docker-push-tag-%:
	docker image push $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_TAG)
	@echo pushed docker container $(BASE_REPO)/$*:$(GIT_TAG)

docker-rollback-push-tag-%:
	docker image push $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_ENV)-live
	@echo pushed docker container $(BASE_REPO)/$*:$(GIT_ENV)-live	

docker-push-branch-%:
	docker image push $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_BRANCH)
	@echo pushed docker container $(BASE_REPO)/$*:$(GIT_BRANCH)

docker-push-latest-%:
	docker image push $(REPO_PREFIX)/$(BASE_REPO)/$*:latest
	@echo pushed docker container $(BASE_REPO)/$*:latest

docker-tag-all-%:
	@echo tagged docker container with all tags

docker-tag-branch-%:
	-docker image pull $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG)
	docker image tag $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG) $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_BRANCH)
	@echo tagged docker container $(BASE_REPO)$*:$(GIT_COMMIT_TAG) as $(BASE_REPO)/$*:$(GIT_BRANCH)

docker-tag-gittag-%:
	-docker image pull $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG)
	docker image tag $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG) $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_TAG)
	@echo tagged docker container $(BASE_REPO)$*:$(GIT_COMMIT_TAG) as $(BASE_REPO)/$*:$(GIT_TAG)

docker-rollback-tag-gittag-%:
	-docker image pull $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_ENV)-last-stable
	docker image tag $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_ENV)-last-stable $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_ENV)-live
	@echo tagged docker container $(BASE_REPO)$*:$(GIT_ENV)-last-stable as $(BASE_REPO)/$*:$(GIT_ENV)-live

docker-commit-rollback-tag-gittag-%:
	-docker image pull $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG)
	docker image tag $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG) $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_ENV)-live
	@echo tagged docker container $(BASE_REPO)$*:$(GIT_COMMIT_TAG) as $(BASE_REPO)/$*:$(GIT_ENV)-live

docker-tag-latest-%:
	-docker image pull $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG)
	docker image tag $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG) $(REPO_PREFIX)/$(BASE_REPO)/$*:latest
	@echo tagged docker container $(BASE_REPO)$*:$(GIT_COMMIT_TAG) as $(BASE_REPO)/$*:latest

docker-tag-last-release-%:
	-docker image pull $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_ENV)-live
	docker image tag $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_ENV)-live $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_ENV)-last-stable
	@echo tagged docker container $(BASE_REPO)$*:$(GIT_ENV)-live as $(BASE_REPO)/$*:$(GIT_ENV)-last-stable

docker-push-last-release-%:
	docker image push $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_ENV)-last-stable
	@echo pushed docker container $(BASE_REPO)/$*:$(GIT_ENV)-last-stable

docker-tag-version-%:
	-docker image pull $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG)
	docker image tag $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG) $(REPO_PREFIX)/$(BASE_REPO)/$*:$(BUILD_VERSION)
	@echo tagged docker container $(BASE_REPO)/$*:$(GIT_COMMIT_TAG) as $(BASE_REPO)/$*:$(BUILD_VERSION)

docker-push-version-%:
	docker image push $(REPO_PREFIX)/$(BASE_REPO)/$*:$(BUILD_VERSION)
	@echo pushed docker container $(BASE_REPO)/$*:$(BUILD_VERSION)

docker-tag-pr-%:
	-docker image pull $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG)
	docker image tag $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GIT_COMMIT_TAG) $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GHPRB_ID_TAG)
	@echo tagged docker container $(BASE_REPO)/$*:$(GIT_COMMIT_TAG) as $(BASE_REPO)/$*:$(GHPRB_ID_TAG)

docker-push-pr-%:
	docker image push $(REPO_PREFIX)/$(BASE_REPO)/$*:$(GHPRB_ID_TAG)
	@echo pushed docker container $(BASE_REPO)/$*:$(GHPRB_ID_TAG)

docker-prune:
	docker network prune -f
	docker volume prune -f

unittest: ui-unit-test graphql-unit-test

datadog-upload-sourcemap:
	@docker container run \
			--env "DATADOG_API_KEY=$(DATADOG_API_KEY)" \
			--entrypoint '' \
			--rm \
			$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-nexus-build:$(GIT_COMMIT_TAG) \
				npx --no-install @datadog/datadog-ci \
					sourcemaps upload ./build/output/static \
					--service=web \
					--release-version=$(BUILD_VERSION) \
					--minified-path-prefix=/static

run-dev: docker-network-setup
	docker run -p 80:80 -p 443:443 --rm \
		--name nexus-dev.$(BASE_REPO).com \
		--network nexus \
		-e CLOUD_ENV="development" \
		-e GATEWAY_ENDPOINT="gateway-steelix.$(BASE_REPO).com" \
		-e APP_ENDPOINT="nexus-dev.$(BASE_REPO).com" \
		-e GRAPHQL_ENDPOINT="http://graphql:4000" \
		-e SEGMENT_KEY="" \
		$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-nexus:$(GIT_COMMIT_TAG)

build-and-run: ui-build-dev ui-build-final run-dev

devbranch:
	git checkout develop
	git pull
	git checkout -b $(GIT_BRANCH)-develop
	git merge origin/$(GIT_BRANCH)
	git push origin $(GIT_BRANCH)-develop

graphql-clean:
	rm -rf ./build/graphql ./build/graphql-output

graphql-prep:
	mkdir -p ./build/graphql

.PHONY: graphql-build-dev
graphql-build-dev: graphql-clean graphql-prep
	rsync -a --exclude='/graphql/node_modules/**' \
		./graphql/Dockerfile* \
		./graphql/package.json \
		./graphql/yarn.lock \
		./graphql/.babelrc.cjs \
		./graphql/eslint.config.cjs \
		./graphql/*.js \
		./graphql/mock \
		./graphql/packages \
		./graphql/src \
		./graphql/test\
			./build/graphql
	MAKEFILE=$$(cat Makefile) && \
	docker image build --pull \
		-f ./build/graphql/Dockerfile.dev \
		-t $(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-graphql-build:$(GIT_COMMIT_TAG) \
			--label Makefile="$$MAKEFILE" \
			--build-arg BUILD_VERSION=$(BUILD_VERSION) \
				./build/graphql	

.PHONY: graphql-build-mock
graphql-build-mock: graphql-clean graphql-prep
	rsync -a ./graphql/Dockerfile.mock ./build/graphql
	SERVICE_SPEC=$$(${GET_SERVICE_SPEC} < ${GRAPHQL_SERVICE_SPEC}) && \
	docker image build \
		-f ./build/graphql/Dockerfile.mock \
		-t $(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-graphql-mock:$(GIT_COMMIT_TAG) \
			--label git_repository="$(BASE_REPO)/frontend" \
			--label git_branch=$(GIT_BRANCH) \
			--label feature_branch_hostname=$(FEATURE_BRANCH_HOSTNAME) \
			--label github_pr_id=$(GITHUB_PR_ID) \
			--label service_spec="$$SERVICE_SPEC" \
			--build-arg git_commit_tag=$(GIT_COMMIT_TAG) \
			--build-arg mock_scenario=$(MOCK_SCENARIO) \
			./build/graphql	

.PHONY: graphql-output
graphql-output: graphql-clean
	mkdir -p ./build/graphql-output
	docker container run --rm --entrypoint '' \
		--volume ${PWD}/build/graphql-output:/build-output \
		$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-graphql-build:$(GIT_COMMIT_TAG) \
			rsync -av \
				--exclude='/node_modules/**' \
				--exclude='/mock/**' \
				--exclude='/test/**' \
				--exclude='/.babelrc.cjs' \
				--exclude='/eslint.config.cjs' \
				--exclude='/jest-setup.js' \
				/app/ /build-output

.PHONY: graphql-build-final
graphql-build-final: graphql-clean graphql-prep graphql-output
	SERVICE_SPEC=$$(${GET_SERVICE_SPEC} < ${GRAPHQL_SERVICE_SPEC}) && \
	docker image build --pull \
		-f ./build/graphql-output/Dockerfile.prod \
		-t $(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-graphql:$(GIT_COMMIT_TAG) \
			--label git_branch=$(GIT_BRANCH) \
			--label feature_branch_hostname=$(FEATURE_BRANCH_HOSTNAME) \
			--label github_pr_id=$(GITHUB_PR_ID) \
			--label service_spec="$$SERVICE_SPEC" \
			--label build_number="$(BUILD_NUMBER)" \
			--label build_job_url="$(BUILD_URL)" \
			--build-arg BUILD_VERSION=$(BUILD_VERSION) \
					./build/graphql-output

.PHONY: graphql-lint
graphql-lint:
	mkdir -p ./build/graphql/testreports
	docker container run --rm \
		--volume ${PWD}/build/graphql/testreports:/app/testreports \
		$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-graphql-build:$(GIT_COMMIT_TAG) \
			yarn lint-ci

.PHONY: graphql-unit-test
graphql-unit-test:
	mkdir -p ./build/graphql/testreports
	docker container run --entrypoint '' --rm \
		--volume ${PWD}/build/graphql/testreports:/app/testreports \
		$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-graphql-build:$(GIT_COMMIT_TAG) \
			yarn test-ci
		
# Just an alias
.PHONY: graphql-test
graphql-test: graphql-unit-test

.PHONY: graphql-run-dev
graphql-run-dev: docker-network-setup
	docker run -p 4000:4000 --rm \
		--network nexus \
		--name graphql \
		-e STAGE=dev \
		-e GATEWAY_HOST="gateway-steelix.$(BASE_REPO).com" \
		-e HTTP_CLIENT_TIMEOUT=120000 \
		$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-graphql:$(GIT_COMMIT_TAG)

.PHONY: graphql-run-mock
graphql-run-mock: docker-network-setup graphql-build-mock
	docker run -p 4000:4000 --rm \
		--network nexus \
		--name graphql \
		-e STAGE=dev \
		-e GATEWAY_HOST="gateway-steelix.$(BASE_REPO).com" \
		-e HTTP_CLIENT_TIMEOUT=120000 \
		$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-graphql-mock:$(GIT_COMMIT_TAG)

.PHONY: ui-clean
ui-clean:
	rm -rf ./build/ui

.PHONY: ui-prep
ui-prep:
	mkdir -p ./build/ui/cache ./build/ui/testreports

.PHONY: ui-build-dev
ui-build-dev: ui-clean ui-prep
	rsync -a --exclude='/graphql/node_modules/**' \
		./package.json \
		./yarn.lock \
		./babel.config.js \
		./eslint.config.js \
		./webpack.config.js \
		./Dockerfile \
		./packages \
		./__mocks__ \
		./scripts \
		./graphql \
		./tsconfig.json \
			./build/ui/cache
	MAKEFILE=$$(cat Makefile) && \
	docker image build --pull \
		-t $(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-nexus-build:$(GIT_COMMIT_TAG) \
			--label Makefile="$$MAKEFILE" \
			--build-arg BUILD_VERSION=$(BUILD_VERSION) \
			--build-arg GITHUB_TOKEN=$(GITHUB_TOKEN) \
			./build/ui/cache
	make ui-clean

.PHONY: ui-lint
ui-lint: ui-prep
	docker container run --entrypoint '' --rm \
		--volume ${PWD}/build/ui/testreports:/app/testreports \
		$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-nexus-build:$(GIT_COMMIT_TAG) \
			yarn lint-ci

.PHONY: ui-unit-test
ui-unit-test: ui-prep
	docker container run --entrypoint '' --rm \
	--volume ${PWD}/build/ui/testreports:/app/testreports \
	$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-nexus-build:$(GIT_COMMIT_TAG) \
		yarn test-ci
	
# Just an alias
.PHONY: ui-test
ui-test: ui-unit-test

.PHONY: ui-output
ui-output:
	mkdir -p ./build/ui/output/cache
	docker container run --rm --entrypoint '' \
		--volume $(CWD)/build/ui/output/cache:/build \
		$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-nexus-build:$(GIT_COMMIT_TAG) \
			rsync -av ./build/output/ /build/

.PHONY: ui-build-final
ui-build-final: ui-output
	rsync -av ./buildfiles/$(BASE_REPO)-nexus/ ./build/ui/output/
	CHANGELOG=$$(${GIT_CHANGELOG} | ${JSONIFY_CHANGELOG}) \
	SERVICE_SPEC=$$(${GET_SERVICE_SPEC} < ${NEXUS_SERVICE_SPEC}) && \
	MSG_1=$$(cat ${APPROVAL_MSG_1}) && \
	MSG_2=$$(cat ${APPROVAL_MSG_2}) && \
	MSG_3=$$(cat ${RELEASE_NOTIFICATION_MSG}) && \
	docker image build --pull \
		-t $(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-nexus:$(GIT_COMMIT_TAG) \
			--label git_repository="$(BASE_REPO)/frontend" \
			--label git_branch=$(GIT_BRANCH) \
			--label feature_branch_hostname=$(FEATURE_BRANCH_HOSTNAME) \
			--label github_pr_id=$(GITHUB_PR_ID) \
			--label service_spec="$$SERVICE_SPEC" \
			--label changelog="$$CHANGELOG" \
			--label build_number="$(BUILD_NUMBER)" \
			--label build_job_url="$(BUILD_URL)" \
			--label approval_msg_1="$$MSG_1" \
			--label approval_msg_2="$$MSG_2" \
			--label release_notification_msg="$$MSG_3" \
			--build-arg BUILD_VERSION=$(BUILD_VERSION) \
			--build-arg GITHUB_TOKEN=$(GITHUB_TOKEN) \
			--build-arg REPO_PREFIX=$(REPO_PREFIX) \
				./build/ui/output

.PHONY: ui-run-dev
ui-run-dev:
	docker run -p 443:443 -v $(CWD)/certificates:/app/certs --rm \
		--name nexus-dev.$(BASE_REPO).com \
		-e CERT_NAME="server" \
		-e CLOUD_ENV="steelix" \
		-e ENABLE_NGINX_OVERRIDES=1 \
		-e GATEWAY_ENDPOINT="nexus-dev.$(BASE_REPO).com/gateway" \
		-e APP_ENDPOINT="nexus-dev.$(BASE_REPO).com" \
		-e GRAPHQL_ENDPOINT="https://app.prestaging.$(BASE_REPO).com" \
		-e SEGMENT_KEY="" \
		$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-nexus:$(GIT_COMMIT_TAG)

.PHONY: ui-run-local-graphql
ui-run-local-graphql: docker-network-setup
	docker run -p 443:443 -v $(CWD)/certificates:/app/certs --rm \
		--name nexus-dev.$(BASE_REPO).com \
		--network nexus \
		-e CERT_NAME="server" \
		-e CLOUD_ENV="steelix" \
		-e ENABLE_NGINX_OVERRIDES=1 \
		-e GATEWAY_ENDPOINT="nexus-dev.$(BASE_REPO).com/gateway" \
		-e APP_ENDPOINT="nexus-dev.$(BASE_REPO).com" \
		-e GRAPHQL_ENDPOINT="http://graphql:4000" \
		-e SEGMENT_KEY="" \
		$(REPO_PREFIX)/$(BASE_REPO)/$(BASE_REPO)-nexus:$(GIT_COMMIT_TAG)

.PHONY: docker-network-setup
docker-network-setup:
	docker network inspect nexus &>/dev/null \
		|| docker network create nexus &>/dev/null

.PHONY: cypress-clean
cypress-clean:
	rm -rf ./build/cypress

.PHONY: cypress-prep
cypress-prep:
	mkdir -p ./build/cypress

.PHONY: cypress-build
cypress-build: cypress-clean cypress-prep
	rsync -a \
		./cypress.config.js \
		./cypress \
		./cypress/Dockerfile \
			./build/cypress
	mv ./build/cypress/cypress/*.sh ./build/cypress/
	docker image build --pull \
		-t $(REPO_PREFIX)/$(BASE_REPO)/cypress-tests:$(GIT_COMMIT_TAG) \
			./build/cypress
	make cypress-clean

YAML_SPEC_INPUT_FILENAME?=green_service_spec.yaml
JSON_SPEC_OUTPUT_FILENAME?=green_service_spec.json

convert:
        yq -o=json -I=2 ${YAML_SPEC_INPUT_FILENAME} > ${JSON_SPEC_OUTPUT_FILENAME}


prepare: convert
        jq -c 'del(.variables,.environments)' ${JSON_SPEC_OUTPUT_FILENAME} > temp-${JSON_SPEC_OUTPUT_FILENAME} && mv temp-${JSON_SPEC_OUTPUT_FILENAME} ${JSON_SPEC_OUTPUT_FILENAME}

output: prepare
        jq -Rsa . ${JSON_SPEC_OUTPUT_FILENAME}

