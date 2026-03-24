#!/usr/bin/env bash
#
# install-sail-resources.sh
#
# Applies the SAIL eventing resources and installs the SAIL operator
# (CRD + Kubernetes manifests) and the MCP server to a cluster that already
# has Knative Serving, Knative Eventing, and the Kafka components installed.
# Run this script as Step 4 of the SAIL setup after completing one of the
# Knative installation options in docs/knative-installation.md.
#
# Usage:
#   ./scripts/install-sail-resources.sh [FLAGS] <KAFKA_BOOTSTRAP_SERVER>
#
# Example (Aiven):
#   ./scripts/install-sail-resources.sh kafka-my-cluster.aivencloud.com:18981
#
# Environment variables (alternative to positional arg):
#   KAFKA_BOOTSTRAP_SERVER   Kafka bootstrap address (host:port)
#
# Prerequisites:
#   - kubectl configured to target the correct cluster/namespace
#   - Knative Serving + Eventing installed (see docs/knative-installation.md)
#   - Kafka Broker controller + data planes installed
#   - Kafka TLS secrets created:
#       broker-secret  in knative-eventing   (used by the Knative Kafka Broker)
#       kafka-tls      in sail               (used by the KafkaSource)
#   - For dev (in-cluster Strimzi, plaintext): neither secret is required;
#     set KAFKA_BOOTSTRAP_SERVER to the in-cluster bootstrap address and
#     pass --skip-tls to this script.
#   - sail-redis-host secret in the sail namespace (used by the operator)
#     kubectl create secret generic sail-redis-host --namespace sail \
#       --from-literal=QUARKUS_REDIS_HOSTS=redis://<host>:6379
#   - agents-kafka-secrets secret in sail namespace (used by the MCP server)
#     Only required when using TLS. See docs/sail-resources.md for instructions.
#
# Flags:
#   --skip-tls       Omit the TLS net block from the KafkaSource and deploy
#                    the MCP server without the certs volume (plaintext Kafka)
#   --skip-operator  Skip the CRD and operator Deployment steps
#   --skip-mcp       Skip the MCP server Deployment step
#   --dry-run        Print the rendered manifests without applying them

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RESOURCES_DIR="${ROOT_DIR}/resources/sail-eventing"
NAMESPACE="sail"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

SKIP_TLS=false
SKIP_OPERATOR=false
SKIP_MCP=false
DRY_RUN=false

# ─── Parse arguments ─────────────────────────────────────────────────

for arg in "$@"; do
  case "$arg" in
    --skip-tls)      SKIP_TLS=true      ;;
    --skip-operator) SKIP_OPERATOR=true ;;
    --skip-mcp)      SKIP_MCP=true      ;;
    --dry-run)       DRY_RUN=true       ;;
    --*)
      err "Unknown flag: $arg"
      exit 1
      ;;
    *)
      KAFKA_BOOTSTRAP_SERVER="$arg"
      ;;
  esac
done

KAFKA_BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-}"

if [[ -z "$KAFKA_BOOTSTRAP_SERVER" ]]; then
  err "KAFKA_BOOTSTRAP_SERVER is required."
  err "Usage: $0 [--skip-tls] [--dry-run] <host:port>"
  err "   or: KAFKA_BOOTSTRAP_SERVER=<host:port> $0"
  exit 1
fi

# ─── Pre-flight checks ───────────────────────────────────────────────

if ! command -v kubectl &>/dev/null; then
  err "kubectl is required but not installed."
  exit 1
fi

log "Target cluster: $(kubectl config current-context)"
log "Kafka bootstrap server: ${KAFKA_BOOTSTRAP_SERVER}"
log "Namespace: ${NAMESPACE}"
$SKIP_TLS      && warn "TLS disabled — assuming plaintext Kafka (dev/local setup)"
$SKIP_OPERATOR && warn "Skipping operator CRD and Deployment installation"
$SKIP_MCP      && warn "Skipping MCP server Deployment"
$DRY_RUN       && warn "Dry-run mode — manifests will be printed but not applied"
echo ""

apply() {
  local file="$1"
  if $DRY_RUN; then
    log "[dry-run] Would apply: $file"
    cat "$file"
    echo "---"
  else
    kubectl apply -f "$file"
  fi
}

apply_stdin() {
  local label="$1"
  local manifest="$2"
  if $DRY_RUN; then
    log "[dry-run] Would apply: $label"
    echo "$manifest"
    echo "---"
  else
    echo "$manifest" | kubectl apply -f -
  fi
}

# ─── Check Knative is installed ──────────────────────────────────────

if ! kubectl get namespace knative-eventing &>/dev/null; then
  err "Namespace 'knative-eventing' not found. Install Knative Eventing first."
  err "See docs/knative-installation.md for instructions."
  exit 1
fi

# ─── Check secrets exist (unless TLS is skipped) ─────────────────────

if ! $SKIP_TLS && ! $DRY_RUN; then
  if ! kubectl get secret broker-secret -n knative-eventing &>/dev/null; then
    warn "Secret 'broker-secret' not found in knative-eventing."
    warn "The Kafka Broker will fail to authenticate until it is created."
    warn "See docs/sail-resources.md for instructions."
  fi
  if ! kubectl get secret kafka-tls -n "${NAMESPACE}" &>/dev/null 2>&1; then
    warn "Secret 'kafka-tls' not found in namespace '${NAMESPACE}'."
    warn "The KafkaSource will fail to connect until it is created."
    warn "See docs/sail-resources.md for instructions."
  fi
fi

# ─── Step 1: Namespace ───────────────────────────────────────────────

log "Step 1/7 — Creating namespace '${NAMESPACE}'..."
apply "${RESOURCES_DIR}/00-namespace.yaml"

# ─── Step 2: SAIL Operator CRD ───────────────────────────────────────

if $SKIP_OPERATOR; then
  warn "Step 2/7 — Skipping CRD installation (--skip-operator)"
else
  log "Step 2/7 — Applying GenericAgent CRD..."
  apply "${ROOT_DIR}/sail-operator/resources/genericagents.sebi.org-v1.yml"
fi

# ─── Step 3: SAIL Operator Deployment ────────────────────────────────

if $SKIP_OPERATOR; then
  warn "Step 3/7 — Skipping operator Deployment (--skip-operator)"
else
  log "Step 3/7 — Applying SAIL operator (ServiceAccount, RBAC, Deployment)..."
  apply "${ROOT_DIR}/sail-operator/resources/kubernetes.yml"

  if ! $DRY_RUN; then
    if ! kubectl get secret sail-redis-host -n "${NAMESPACE}" &>/dev/null; then
      warn "Secret 'sail-redis-host' not found in namespace '${NAMESPACE}'."
      warn "The operator will fail to start until it is created:"
      warn "  kubectl create secret generic sail-redis-host --namespace ${NAMESPACE} \\"
      warn "    --from-literal=QUARKUS_REDIS_HOSTS=redis://<host>:6379"
    fi
    log "Waiting for operator deployment to be available..."
    kubectl wait --for=condition=Available deployment/sail-operator \
      -n "${NAMESPACE}" --timeout=120s 2>/dev/null || \
      warn "Operator deployment not yet available — check pod logs for details."
  fi
fi

# ─── Step 4: Kafka Broker ConfigMap ──────────────────────────────────

log "Step 4/7 — Applying Kafka Broker ConfigMap (knative-eventing)..."

CM_AUTH_LINE="  auth.secret.ref.name: broker-secret"
if $SKIP_TLS; then
  CM_AUTH_LINE=""
fi

apply_stdin "kafka-broker-config ConfigMap" "$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-broker-config
  namespace: knative-eventing
data:
  default.topic.partitions: "2"
  default.topic.replication.factor: "2"
  bootstrap.servers: "${KAFKA_BOOTSTRAP_SERVER}"
${CM_AUTH_LINE}
EOF
)"

# ─── Step 5: Knative Kafka Broker ────────────────────────────────────

log "Step 5/7 — Applying Knative Kafka Broker (sail)..."
apply "${RESOURCES_DIR}/02-agent-broker.yaml"

# ─── Step 6: EventTransform ──────────────────────────────────────────

log "Step 6/7 — Applying EventTransform (sail)..."
apply "${RESOURCES_DIR}/03-eventtransform.yaml"

if ! $DRY_RUN; then
  log "Waiting for EventTransform service to become available..."
  # The EventTransform controller creates a Knative Service; wait until the URL is ready.
  for i in $(seq 1 30); do
    if kubectl get service simple-transform-jsonata -n "${NAMESPACE}" &>/dev/null; then
      break
    fi
    sleep 5
  done
fi

# ─── Step 7: KafkaSource ─────────────────────────────────────────────

log "Step 7/8 — Applying KafkaSource (sail)..."

if $SKIP_TLS; then
  apply_stdin "KafkaSource (plaintext)" "$(cat <<EOF
apiVersion: sources.knative.dev/v1
kind: KafkaSource
metadata:
  name: kafka-source
  namespace: ${NAMESPACE}
  labels:
    app: kafka-source
spec:
  bootstrapServers:
    - "${KAFKA_BOOTSTRAP_SERVER}"
  topics:
    - agents-messages
  ceOverrides:
    extensions:
      datacontenttype: application/json
  consumerGroup: agents
  sink:
    uri: http://simple-transform-jsonata.${NAMESPACE}.svc.cluster.local
  ordering: ordered
  initialOffset: latest
  consumers: 1
EOF
)"
else
  apply_stdin "KafkaSource (TLS)" "$(cat <<EOF
apiVersion: sources.knative.dev/v1
kind: KafkaSource
metadata:
  name: kafka-source
  namespace: ${NAMESPACE}
  labels:
    app: kafka-source
spec:
  bootstrapServers:
    - "${KAFKA_BOOTSTRAP_SERVER}"
  topics:
    - agents-messages
  ceOverrides:
    extensions:
      datacontenttype: application/json
  consumerGroup: agents
  sink:
    uri: http://simple-transform-jsonata.${NAMESPACE}.svc.cluster.local
  ordering: ordered
  initialOffset: latest
  net:
    tls:
      enable: true
      caCert:
        secretKeyRef:
          name: kafka-tls
          key: ca.pem
      cert:
        secretKeyRef:
          name: kafka-tls
          key: service.cert
      key:
        secretKeyRef:
          name: kafka-tls
          key: service.key
  consumers: 1
EOF
)"
fi

# ─── Step 8: MCP Server ──────────────────────────────────────────────

if $SKIP_MCP; then
  warn "Step 8/8 — Skipping MCP server Deployment (--skip-mcp)"
else
  log "Step 8/8 — Applying SAIL MCP server..."

  MCP_MANIFEST="${ROOT_DIR}/sail-mcp-server/kubernetes.yml"

  if $SKIP_TLS; then
    # Plaintext: patch the manifest on-the-fly to remove the certs volume
    # and set the secret as optional so the pod starts without it.
    if $DRY_RUN; then
      log "[dry-run] Would apply MCP server manifest (plaintext, no certs volume)"
      sed '/certs-volume/,/secretName: agents-kafka-secrets/{
             /optional: false/s/optional: false/optional: true/
           }' "${MCP_MANIFEST}"
      echo "---"
    else
      sed '/optional: false/s/optional: false/optional: true/' "${MCP_MANIFEST}" \
        | kubectl apply -n "${NAMESPACE}" -f -
    fi
  else
    # TLS: check the secret exists before applying
    if ! $DRY_RUN && ! kubectl get secret agents-kafka-secrets -n "${NAMESPACE}" &>/dev/null; then
      warn "Secret 'agents-kafka-secrets' not found in namespace '${NAMESPACE}'."
      warn "The MCP server will fail to start until it is created."
      warn "See docs/sail-resources.md for instructions."
    fi
    apply "${MCP_MANIFEST}"
  fi

  if ! $DRY_RUN; then
    log "Waiting for MCP server deployment to be available..."
    kubectl wait --for=condition=Available deployment/sail-mcp-server \
      -n "${NAMESPACE}" --timeout=120s 2>/dev/null || \
      warn "MCP server deployment not yet available — check pod logs for details."
  fi
fi

# ─── Summary ─────────────────────────────────────────────────────────

if ! $DRY_RUN; then
  echo ""
  log "============================================"
  log " SAIL resources applied!"
  log "============================================"
  echo ""
  log "Verifying operator in namespace '${NAMESPACE}':"
  kubectl get deployment sail-operator -n "${NAMESPACE}" 2>/dev/null || true
  echo ""
  log "Verifying MCP server in namespace '${NAMESPACE}':"
  kubectl get deployment sail-mcp-server -n "${NAMESPACE}" 2>/dev/null || true
  echo ""
  log "Verifying eventing resources in namespace '${NAMESPACE}':"
  kubectl get broker,eventtransform,kafkasource -n "${NAMESPACE}" 2>/dev/null || true
  echo ""
  log "Next steps:"
  log "  1. Apply sample agents:  cd sail-operator && make agents-add"
  log ""
  log "For troubleshooting, see docs/sail-resources.md"
fi
