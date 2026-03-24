# Makefile: convenience targets for building and pushing the MCP server image

IMAGE_REPO  ?= sebi2706/sail-mcp-server
IMAGE_TAG   ?= latest
PLATFORMS   ?= linux/amd64,linux/arm64
BUILDER     ?= sail-builder

.PHONY: docker-build docker-multiarch docker-builder-create

## Build the JAR and create a single-platform image for the local daemon.
docker-build:
	./mvnw package -DskipTests
	docker build -f src/main/docker/Dockerfile.jvm \
		-t $(IMAGE_REPO):$(IMAGE_TAG) .

## Build and push a multi-arch image (linux/amd64 + linux/arm64).
## Requires a docker-container buildx builder — run 'make docker-builder-create' first.
## Example: make docker-multiarch IMAGE_TAG=0.4
docker-multiarch:
	./mvnw package -DskipTests
	docker buildx build \
		--builder $(BUILDER) \
		--platform $(PLATFORMS) \
		-f src/main/docker/Dockerfile.jvm \
		--tag $(IMAGE_REPO):$(IMAGE_TAG) \
		--push .

## Create the buildx builder with the docker-container driver (one-time setup).
docker-builder-create:
	docker buildx create --name $(BUILDER) --driver docker-container --bootstrap --use \
		|| docker buildx use $(BUILDER)
