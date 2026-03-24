#!/usr/bin/env bash
#
# install-knative-dev.sh
#
# Installs a full Knative + Kafka development environment on minikube.
# Includes: Knative Serving, Eventing, Kafka Broker, KafkaSource, KafkaSink,
# KafkaChannel, EventTransform, and a single-node Strimzi Kafka cluster.
#
# Usage:
#   ./scripts/install-knative-dev.sh
#
# Prerequisites:
#   - minikube (https://minikube.sigs.k8s.io/docs/start/)
#   - kubectl  (https://kubernetes.io/docs/tasks/tools/)
#
# After the script completes, run in a separate terminal:
#   minikube tunnel --profile sail

set -euo pipefail

KNATIVE_VERSION="v1.21.1"
KOURIER_VERSION="v1.21.0"
STRIMZI_VERSION="0.46.0"
PROFILE="sail"
CPUS=4
MEMORY="8192"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

wait_for_pods() {
  local namespace=$1
  local timeout=${2:-300}
  log "Waiting for pods in $namespace to be ready (timeout: ${timeout}s)..."
  kubectl wait --for=condition=Ready pods --all \
    -n "$namespace" --timeout="${timeout}s" 2>/dev/null || {
    warn "Some pods in $namespace may not be ready yet. Checking status..."
    kubectl get pods -n "$namespace"
  }
}

wait_for_deployments() {
  local namespace=$1
  local timeout=${2:-300}
  log "Waiting for deployments in $namespace (timeout: ${timeout}s)..."
  kubectl wait --for=condition=Available deployments --all \
    -n "$namespace" --timeout="${timeout}s" 2>/dev/null || {
    warn "Some deployments in $namespace may not be available yet."
    kubectl get deployments -n "$namespace"
  }
}

# ─── Pre-flight checks ───────────────────────────────────────────────

for cmd in minikube kubectl; do
  if ! command -v "$cmd" &>/dev/null; then
    err "$cmd is required but not installed."
    exit 1
  fi
done

# ─── Minikube cluster ────────────────────────────────────────────────

if minikube status --profile "$PROFILE" &>/dev/null; then
  log "Minikube profile '$PROFILE' already exists. Using existing cluster."
else
  log "Creating minikube cluster '$PROFILE' with ${CPUS} CPUs and ${MEMORY}MB RAM..."
  minikube start --profile "$PROFILE" \
    --cpus="$CPUS" \
    --memory="$MEMORY" \
    --driver=docker \
    --kubernetes-version=stable
fi

minikube profile "$PROFILE"

# ─── Knative Serving ─────────────────────────────────────────────────

log "Installing Knative Serving CRDs..."
kubectl apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-crds.yaml"

log "Installing Knative Serving core..."
kubectl apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-core.yaml"

log "Installing Kourier networking layer..."
kubectl apply -f "https://github.com/knative-extensions/net-kourier/releases/download/knative-${KOURIER_VERSION}/kourier.yaml"

kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'

log "Configuring magic DNS (sslip.io)..."
kubectl apply -f "https://github.com/knative/serving/releases/download/knative-${KNATIVE_VERSION}/serving-default-domain.yaml"

wait_for_deployments "knative-serving"

# ─── Knative Eventing ────────────────────────────────────────────────

log "Installing Knative Eventing CRDs..."
kubectl apply -f "https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-crds.yaml"

log "Installing Knative Eventing core..."
kubectl apply -f "https://github.com/knative/eventing/releases/download/knative-${KNATIVE_VERSION}/eventing-core.yaml"

wait_for_deployments "knative-eventing"

# ─── Kafka Components (Knative) ──────────────────────────────────────

log "Installing Kafka controller..."
kubectl apply -f "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-${KNATIVE_VERSION}/eventing-kafka-controller.yaml"

log "Installing Kafka Broker data plane..."
kubectl apply -f "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-${KNATIVE_VERSION}/eventing-kafka-broker.yaml"

log "Installing KafkaSource data plane..."
kubectl apply -f "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-${KNATIVE_VERSION}/eventing-kafka-source.yaml"

log "Installing KafkaSink data plane..."
kubectl apply -f "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-${KNATIVE_VERSION}/eventing-kafka-sink.yaml"

log "Installing KafkaChannel data plane..."
kubectl apply -f "https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-${KNATIVE_VERSION}/eventing-kafka-channel.yaml"

wait_for_deployments "knative-eventing" 360

# ─── Strimzi Kafka (in-cluster, for dev) ─────────────────────────────

log "Installing Strimzi Kafka operator (v${STRIMZI_VERSION})..."
kubectl create namespace kafka 2>/dev/null || true
kubectl apply -f "https://strimzi.io/install/latest?namespace=kafka" -n kafka

log "Waiting for Strimzi operator to be ready..."
kubectl wait --for=condition=Available deployment/strimzi-cluster-operator \
  -n kafka --timeout=300s

log "Creating single-node Kafka cluster (KRaft mode)..."
kubectl apply -n kafka -f - <<'EOF'
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: combined
  labels:
    strimzi.io/cluster: sail-kafka
spec:
  replicas: 1
  roles:
    - controller
    - broker
  storage:
    type: jbod
    volumes:
      - id: 0
        type: persistent-claim
        size: 10Gi
        deleteClaim: true
---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: sail-kafka
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 4.1.0
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
      - name: tls
        port: 9093
        type: internal
        tls: true
        authentication:
          type: tls
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
      min.insync.replicas: 1
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF

log "Waiting for Kafka cluster to be ready (this can take a few minutes)..."
kubectl wait kafka/sail-kafka --for=condition=Ready --timeout=600s -n kafka

# ─── Kafka Broker ConfigMap (dev, plaintext) ─────────────────────────

log "Creating Kafka broker config for local development..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-broker-config
  namespace: knative-eventing
data:
  default.topic.partitions: "2"
  default.topic.replication.factor: "1"
  bootstrap.servers: "sail-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092"
EOF

# ─── Redis (in-cluster, for dev) ─────────────────────────────────────

log "Installing Redis..."
kubectl create namespace sail 2>/dev/null || true

kubectl apply -n sail -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:7-alpine
          ports:
            - containerPort: 6379
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 250m
              memory: 256Mi
---
apiVersion: v1
kind: Service
metadata:
  name: redis
spec:
  selector:
    app: redis
  ports:
    - port: 6379
      targetPort: 6379
EOF

log "Creating sail-redis-host secret..."
kubectl create secret generic sail-redis-host \
  --namespace sail \
  --from-literal=QUARKUS_REDIS_HOSTS=redis://redis.sail.svc.cluster.local:6379 \
  --dry-run=client -o yaml | kubectl apply -f -

log "Waiting for Redis to be ready..."
kubectl wait --for=condition=Available deployment/redis -n sail --timeout=120s

# ─── Summary ─────────────────────────────────────────────────────────

echo ""
log "============================================"
log " Knative dev environment ready!"
log "============================================"
echo ""
log "Knative Serving:   $(kubectl get pods -n knative-serving --no-headers | wc -l | tr -d ' ') pods"
log "Knative Eventing:  $(kubectl get pods -n knative-eventing --no-headers | wc -l | tr -d ' ') pods"
log "Kafka (Strimzi):   sail-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092"
log "Redis:             redis.sail.svc.cluster.local:6379"
echo ""
log "Next steps:"
log "  1. Run 'minikube tunnel --profile sail' in a separate terminal"
log "  2. Deploy SAIL resources: kubectl apply -f resources/agent-broker.yaml"
log "  3. Deploy the MCP server: kubectl apply -f sail-mcp-server/kubernetes.yml"
log "  4. Deploy agents: cd sail-operator && make agents-add"
echo ""
warn "This is a dev setup with plaintext Kafka. For SSL/TLS config, see docs/knative-installation.md"
