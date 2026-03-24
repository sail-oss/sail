#!/usr/bin/env bash
#
# build-images.sh
#
# Builds and pushes multi-arch Docker images for all SAIL subprojects to
# Docker Hub under the sebi2706 organisation.
#
# Usage:
#   ./scripts/build-images.sh [FLAGS] <TAG>
#
# Examples:
#   ./scripts/build-images.sh 0.4
#   ./scripts/build-images.sh --operator-only 0.4
#   ./scripts/build-images.sh --dry-run 0.4
#
# Flags:
#   --operator-only   Build sail-operator only
#   --mcp-only        Build sail-mcp-server only
#   --base-only       Build sail-base-openid only
#   --no-push         Build locally (single-platform, no push)
#   --dry-run         Print commands without executing them
#   --platforms P     Comma-separated platform list (default: linux/amd64,linux/arm64)
#
# Environment variables:
#   DOCKER_REGISTRY   Registry prefix  (default: docker.io/sebi2706)
#   PLATFORMS         Override platform list
#   BUILDER           buildx builder name (default: sail-builder)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Defaults ────────────────────────────────────────────────────────

DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io/sebi2706}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
BUILDER="${BUILDER:-sail-builder}"

BUILD_OPERATOR=true
BUILD_MCP=true
BUILD_BASE=true
NO_PUSH=false
DRY_RUN=false
TAG=""

# ─── Parse arguments ─────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --operator-only) BUILD_MCP=false;  BUILD_BASE=false ;;
    --mcp-only)      BUILD_OPERATOR=false; BUILD_BASE=false ;;
    --base-only)     BUILD_OPERATOR=false; BUILD_MCP=false ;;
    --no-push)       NO_PUSH=true ;;
    --dry-run)       DRY_RUN=true ;;
    --platforms)     ;;   # handled below as key=value
    --platforms=*)   PLATFORMS="${arg#--platforms=}" ;;
    --*)
      err "Unknown flag: $arg"
      exit 1
      ;;
    *)
      TAG="$arg"
      ;;
  esac
done

if [[ -z "$TAG" ]]; then
  err "A tag is required."
  err "Usage: $0 [FLAGS] <TAG>"
  err "Example: $0 0.4"
  exit 1
fi

# ─── Pre-flight ──────────────────────────────────────────────────────

for cmd in docker mvn; do
  if ! command -v "$cmd" &>/dev/null; then
    err "$cmd is required but not installed."
    exit 1
  fi
done

if ! $NO_PUSH && ! $DRY_RUN; then
  # Ensure the buildx builder exists
  if ! docker buildx inspect "$BUILDER" &>/dev/null; then
    log "Creating buildx builder '$BUILDER'..."
    docker buildx create --name "$BUILDER" --driver docker-container --bootstrap --use
  else
    docker buildx use "$BUILDER"
  fi
fi

$DRY_RUN && warn "Dry-run mode — commands will be printed but not executed"
echo ""

# ─── Build helper ────────────────────────────────────────────────────

build_image() {
  local name="$1"       # e.g. sail-operator
  local subdir="$2"     # e.g. sail-operator
  local repo="${DOCKER_REGISTRY}/${name}"
  local full_tag="${repo}:${TAG}"
  local dir="${ROOT_DIR}/${subdir}"

  log "──────────────────────────────────────────────"
  log " Building ${name}:${TAG}"
  log " Repo:      ${repo}"
  log " Directory: ${dir}"
  log "──────────────────────────────────────────────"

  if $DRY_RUN; then
    echo "[dry-run] cd ${dir}"
    echo "[dry-run] ./mvnw package -DskipTests"
    if $NO_PUSH; then
      echo "[dry-run] docker build -f src/main/docker/Dockerfile.jvm -t ${full_tag} ."
    else
      echo "[dry-run] docker buildx build --builder ${BUILDER} --platform ${PLATFORMS} \\"
      echo "  -f src/main/docker/Dockerfile.jvm --tag ${full_tag} --push ."
    fi
    echo ""
    return
  fi

  pushd "$dir" > /dev/null

  log "Running Maven build..."
  ./mvnw package -DskipTests -q

  if $NO_PUSH; then
    log "Building local image ${full_tag}..."
    docker build \
      -f src/main/docker/Dockerfile.jvm \
      -t "${full_tag}" \
      .
    log "Image built locally: ${full_tag}"
  else
    log "Building and pushing multi-arch image ${full_tag} (${PLATFORMS})..."
    docker buildx build \
      --builder "${BUILDER}" \
      --platform "${PLATFORMS}" \
      -f src/main/docker/Dockerfile.jvm \
      --tag "${full_tag}" \
      --push \
      .
    log "Pushed: ${full_tag}"
  fi

  popd > /dev/null
  echo ""
}

# ─── Build each subproject ───────────────────────────────────────────

log "SAIL image build — tag: ${TAG}"
log "Registry: ${DOCKER_REGISTRY}"
$NO_PUSH || log "Platforms: ${PLATFORMS}"
echo ""

$BUILD_OPERATOR && build_image "sail-operator"    "sail-operator"
$BUILD_MCP      && build_image "sail-mcp-server"  "sail-mcp-server"
$BUILD_BASE     && build_image "sail-base-openai" "sail-base-openid"

# ─── Summary ─────────────────────────────────────────────────────────

if ! $DRY_RUN; then
  echo ""
  log "============================================"
  log " Build complete!"
  log "============================================"
  echo ""
  if ! $NO_PUSH; then
    $BUILD_OPERATOR && log "  ${DOCKER_REGISTRY}/sail-operator:${TAG}"
    $BUILD_MCP      && log "  ${DOCKER_REGISTRY}/sail-mcp-server:${TAG}"
    $BUILD_BASE     && log "  ${DOCKER_REGISTRY}/sail-base-openai:${TAG}"
    echo ""
    log "Update the image tags in the Kubernetes manifests:"
    log "  sail-operator/resources/kubernetes.yml"
    log "  sail-mcp-server/kubernetes.yml"
  fi
fi
