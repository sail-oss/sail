# SAIL Eventing Resources and Operator

This document describes the Kubernetes resources that wire together the SAIL
messaging pipeline and how to install the SAIL operator. Apply these resources
**after** Knative Serving, Knative Eventing, and the Kafka components are
installed (Option 1, 2, or 3 from [knative-installation.md](knative-installation.md)).

The eventing resources live in `resources/sail-eventing/`. The operator
manifests live in `sail-operator/resources/`. Both are applied in one pass by
`scripts/install-sail-resources.sh`.

---

## Overview

```
Kafka topic "agents-messages"
  └─ KafkaSource (sail)
       └─ EventTransform "simple-transform" (sail)  ← JSONata reshapes CloudEvent,
            └─ Broker "agent-broker" (sail)            adds "targetagent" attribute
                 └─ Trigger (sail, per agent)         ← operator creates these
                      └─ Knative Service (sail)       ← agent container
```

---

## Prerequisites

### 1. Knative installed

Confirm Knative Eventing and the Kafka data planes are running:

```sh
kubectl get pods -n knative-eventing
# Expected: kafka-controller, kafka-broker-receiver, kafka-broker-dispatcher,
#           kafka-source-dispatcher, kafka-sink-receiver
```

### 2. Kafka TLS secrets (external / secured Kafka)

Two secrets are required before applying the resources. Skip this section if
you are using the dev setup with in-cluster Strimzi (plaintext); in that case
pass `--skip-tls` to the install script.

**`broker-secret` — namespace: `knative-eventing`**

Used by the Knative Kafka Broker controller to authenticate with Kafka when
sending / receiving events through the broker. Must live in `knative-eventing`.

```sh
kubectl create secret generic broker-secret \
  --namespace knative-eventing \
  --from-literal=protocol=SSL \
  --from-file=ca.crt=ca.pem \
  --from-file=user.crt=service.cert \
  --from-file=user.key=service.key
```

| Key        | Description                          |
|------------|--------------------------------------|
| `protocol` | `SSL` for mTLS                       |
| `ca.crt`   | CA certificate (PEM)                 |
| `user.crt` | Client certificate (PEM)             |
| `user.key` | Client private key (PEM)             |

**`kafka-tls` — namespace: `sail`**

Used directly by the KafkaSource to authenticate with Kafka when consuming
messages.

```sh
kubectl create namespace sail 2>/dev/null || true

kubectl create secret generic kafka-tls \
  --namespace sail \
  --from-file=ca.pem=ca.pem \
  --from-file=service.cert=service.cert \
  --from-file=service.key=service.key
```

### 3. Redis secret for the operator

The SAIL operator reads agent metadata from Redis. It expects a secret named
`sail-redis-host` in the `sail` namespace containing the Redis URL:

```sh
kubectl create namespace sail 2>/dev/null || true

kubectl create secret generic sail-redis-host \
  --namespace sail \
  --from-literal=QUARKUS_REDIS_HOSTS=redis://<redis-host>:6379
```

For the dev setup (in-cluster Redis created by `scripts/install-knative-dev.sh`)
this secret is already present.

---

## Install

```sh
chmod +x scripts/install-sail-resources.sh

# External secured Kafka (mTLS) — installs operator + MCP server + eventing resources
./scripts/install-sail-resources.sh my-kafka.aivencloud.com:18981

# Local dev — in-cluster Strimzi, plaintext
./scripts/install-sail-resources.sh \
  --skip-tls \
  sail-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092

# Eventing resources only (operator and MCP server already installed)
./scripts/install-sail-resources.sh --skip-operator --skip-mcp my-kafka:9092

# Preview without applying
./scripts/install-sail-resources.sh --dry-run my-kafka:9092
```

The script applies resources in this order and waits for the operator and
EventTransform service to be ready before proceeding to subsequent steps:

| Step | Resource | Notes |
|------|----------|-------|
| 1 | Namespace `sail` | Created once |
| 2 | `GenericAgent` CRD | Cluster-scoped |
| 3 | Operator Deployment + RBAC | Waits for `Available` |
| 4 | `kafka-broker-config` ConfigMap | In `knative-eventing` |
| 5 | Knative Kafka Broker | In `sail` |
| 6 | EventTransform | In `sail` |
| 7 | KafkaSource | In `sail` |
| 8 | MCP server Deployment | In `sail`; certs volume marked optional when `--skip-tls` |

---

## SAIL Operator

The SAIL operator watches `GenericAgent` custom resources and provisions a
Knative Service + Trigger for each agent. It also registers agents in Redis
so the agent runtime can discover available peers.

### `sail-operator/resources/genericagents.sebi.org-v1.yml` — CRD

Defines the `GenericAgent` custom resource (group `sebi.org`, version `v1`,
kind `GenericAgent`). This is a cluster-scoped CRD that must be installed
before any `GenericAgent` objects are created.

Key fields in the CRD spec:

| Field            | Type    | Description                                                   |
|------------------|---------|---------------------------------------------------------------|
| `agentClassName` | string  | Docker image override. Defaults to `sebi2706/sail-base-openai:0.3` if not set |
| `description`    | string  | Natural-language description stored in Redis for peer discovery |
| `systemMessage`  | string  | System prompt injected into every LLM call                   |
| `userMessage`    | string  | Qute template for the user turn; receives `SailMessage` context |
| `useMemory`      | boolean | Whether the agent retains conversation history               |

Install manually:

```sh
kubectl apply -f sail-operator/resources/genericagents.sebi.org-v1.yml
```

Verify:

```sh
kubectl get crd genericagents.sebi.org
```

### `sail-operator/resources/kubernetes.yml` — Operator Deployment

Contains all Kubernetes objects needed to run the operator:

- **ServiceAccount** `sail-operator` — identity for the operator pod
- **ClusterRole** `genericagentreconciler-cluster-role` — get/list/watch/patch/update/create/delete on `genericagents`, `genericagents/status`, and `genericagents/finalizers`
- **ClusterRole** `josdk-crd-validating-cluster-role` — read CRDs (used by JOSDK to validate the reconciler configuration at startup)
- **ClusterRoleBinding** × 2 — bind the above roles to the `sail-operator` ServiceAccount
- **RoleBinding** `sail-operator-view` — adds the built-in `view` role for general resource read access
- **Service** `sail-operator` — ClusterIP exposing port 80 → 8080 (health probes)
- **Deployment** `sail-operator` — single replica running the operator image

The operator image is configured via the `image` field in the Deployment. The
`resources/kubernetes.yml` is regenerated by `./mvnw package` — to update the
image tag, edit `application.properties` or rebuild and re-apply.

Install manually:

```sh
# Install in the sail namespace (matches the ServiceAccount namespace in the manifest)
kubectl apply -f sail-operator/resources/kubernetes.yml -n sail
```

> **Note:** The manifest does not hard-code a namespace on most resources so
> that `kubectl apply -n sail` sets it. The ClusterRole and ClusterRoleBinding
> resources are cluster-scoped and ignore `-n`.

Verify:

```sh
kubectl get deployment sail-operator -n sail
kubectl get pods -n sail -l app.kubernetes.io/name=sail-operator
kubectl logs -n sail -l app.kubernetes.io/name=sail-operator --tail=50
```

### Operator prerequisites at runtime

The operator pod requires:

| Secret | Namespace | Key | Description |
|--------|-----------|-----|-------------|
| `sail-redis-host` | `sail` | `QUARKUS_REDIS_HOSTS` | Redis URL — used for agent registration and discovery |

The operator does **not** need Kafka credentials at runtime; Kafka is only
used by the MCP server and agent pods.

---

## Eventing Resources

### `00-namespace.yaml` — Namespace `sail`

Creates the `sail` namespace that contains all SAIL workloads (agents, MCP
server, Redis, operator, and the eventing resources below).

### `01-broker-cm.yaml` — ConfigMap `kafka-broker-config` (knative-eventing)

Configures the Knative Kafka Broker:

| Field                        | Description                                     |
|------------------------------|-------------------------------------------------|
| `bootstrap.servers`          | Kafka cluster address — **must be customised**  |
| `default.topic.partitions`   | Partition count for auto-created topics (`2`)   |
| `default.topic.replication.factor` | Replication factor (`2` for production, `1` for dev) |
| `auth.secret.ref.name`       | Reference to `broker-secret` in this namespace  |

> **Why `knative-eventing`?** The Kafka Broker controller runs in this
> namespace and reads the ConfigMap directly. The Broker CR in `sail` points to
> this ConfigMap using the `namespace: knative-eventing` field.

### `02-agent-broker.yaml` — Broker `agent-broker` (sail)

A Knative Kafka-backed Broker. All agent Knative Services subscribe to this
broker via Triggers created by the SAIL operator. The broker spec references
the ConfigMap in `knative-eventing` explicitly:

```yaml
spec:
  config:
    apiVersion: v1
    kind: ConfigMap
    name: kafka-broker-config
    namespace: knative-eventing
```

### `03-eventtransform.yaml` — EventTransform `simple-transform` (sail)

A JSONata-based transformation that sits between the KafkaSource and the
broker. It adds a `targetagent` CloudEvent extension attribute by extracting
`data.to` from the incoming `SailMessage` payload:

```jsonata
{
  "specversion": "1.0",
  "id": id,
  "time": time,
  "type": type,
  "source": source,
  "targetagent": data.to,   ← used by Trigger filters
  "data": $.data
}
```

The Knative EventTransform controller automatically creates a Knative Service
named `simple-transform-jsonata` in the `sail` namespace. The KafkaSource
sends events to this service's ClusterIP URL.

### `04-kafkasource.yaml` — KafkaSource `kafka-source` (sail)

Consumes the `agents-messages` Kafka topic and forwards CloudEvents to the
EventTransform. Key fields:

| Field                  | Description                                        |
|------------------------|----------------------------------------------------|
| `bootstrapServers`     | Kafka cluster address — **must be customised**     |
| `topics`               | `agents-messages` — all SAIL messages flow here    |
| `consumerGroup`        | `agents` — shared consumer group for all listeners |
| `sink.uri`             | Internal URL of the `simple-transform-jsonata` Knative Service |
| `net.tls`              | PEM references to `kafka-tls` secret               |
| `ordering`             | `ordered` — preserves per-partition message order  |
| `initialOffset`        | `latest` — ignores messages sent before startup    |

---

## MCP Server

The MCP (Model Context Protocol) server is a stateless HTTP/SSE service that
exposes a single `sendMessage` tool to agents. When an agent's LLM decides to
call `sendMessage`, the MCP server publishes a `SailMessage` object to the
`agents-messages` Kafka topic, kicking off the next hop in the pipeline.

### Kubernetes manifest — `sail-mcp-server/kubernetes.yml`

Contains a **Service** (ClusterIP, port 80 → 8080) and a **Deployment**. The
pod mounts the `agents-kafka-secrets` secret at `/etc/certs` when TLS is
enabled.

### Kafka configuration — `sail-mcp-server/src/main/resources/application.properties`

The MCP server uses Quarkus profiles to switch between plaintext (dev) and TLS
(prod) Kafka:

| Profile | `kafka.bootstrap.servers` | TLS properties |
|---------|--------------------------|----------------|
| `dev`   | in-cluster Strimzi bootstrap | none |
| `prod`  | external Kafka bootstrap | full SSL/TLS mTLS config |

In **dev** mode the server connects to the in-cluster Strimzi Kafka over
plaintext — no secrets needed. In **prod** mode it reads PKCS12 keystore and
JKS truststore from `/etc/certs`, which are mounted from the
`agents-kafka-secrets` Secret.

### Required secret (TLS / prod only)

The `agents-kafka-secrets` secret must contain a PKCS12 client keystore and a
JKS truststore. See [knative-installation.md — Kafka SSL/TLS Configuration](knative-installation.md#kafka-ssltls-configuration) for how to create them from your PEM files.

```sh
kubectl create secret generic agents-kafka-secrets \
  --namespace sail \
  --from-file=keystore=client.keystore.p12 \
  --from-file=trustore=client.truststore.jks
```

> **Note:** the key `trustore` (no second `t`) matches the key name used in
> the Kubernetes volume item mapping — do not rename it.

### Plaintext Kafka (dev / `--skip-tls`)

When `--skip-tls` is passed to the install script, the manifest is applied with
the `agents-kafka-secrets` volume marked as `optional: true`. The pod starts
even if the secret does not exist, and Kafka is accessed without TLS using the
bootstrap server you supplied.

To do this manually:

```sh
# Mark the volume optional and apply
sed 's/optional: false/optional: true/' sail-mcp-server/kubernetes.yml \
  | kubectl apply -n sail -f -
```

### Manual install

```sh
# TLS (prod)
kubectl apply -f sail-mcp-server/kubernetes.yml -n sail

# Plaintext (dev)
sed 's/optional: false/optional: true/' sail-mcp-server/kubernetes.yml \
  | kubectl apply -n sail -f -
```

### Verify

```sh
kubectl get deployment sail-mcp-server -n sail
kubectl get pods -n sail -l app.kubernetes.io/name=sail-mcp-server
kubectl logs -n sail -l app.kubernetes.io/name=sail-mcp-server --tail=50
```

The MCP server exposes its tool endpoint at:
```
http://sail-mcp-server.sail.svc.cluster.local/mcp/sse
```

Agent pods reference this URL via the `quarkus.langchain4j.mcp.*.url` property
in their `application.properties`.

---

## Verification

```sh
# Operator
kubectl get deployment sail-operator -n sail
kubectl get crd genericagents.sebi.org

# Eventing
kubectl get broker,eventtransform,kafkasource -n sail

# Broker should show READY=True
kubectl get broker agent-broker -n sail

# KafkaSource should show READY=True
kubectl get kafkasource kafka-source -n sail

# EventTransform Knative Service should be ready
kubectl get ksvc simple-transform-jsonata -n sail

# Confirm the ConfigMap is in knative-eventing
kubectl get configmap kafka-broker-config -n knative-eventing
```

---

## Troubleshooting

**Operator pod not starting**

```sh
kubectl describe deployment sail-operator -n sail
kubectl logs -n sail -l app.kubernetes.io/name=sail-operator
# Missing sail-redis-host secret? → create it first (see Prerequisites above)
# CRD not found? → apply the CRD before the Deployment
kubectl get crd genericagents.sebi.org
```

**Operator not creating Triggers / Knative Services for agents**

```sh
# List agents and their status
kubectl get genericagents -n sail
kubectl describe genericagent <name> -n sail
# Check operator logs for reconciliation errors
kubectl logs -n sail -l app.kubernetes.io/name=sail-operator --tail=100
```

**MCP server pod not starting**

```sh
kubectl describe deployment sail-mcp-server -n sail
kubectl logs -n sail -l app.kubernetes.io/name=sail-mcp-server
# TLS errors? → check agents-kafka-secrets secret
kubectl get secret agents-kafka-secrets -n sail -o jsonpath='{.data}' | jq 'keys'
# Expected: ["keystore", "trustore"]
# Deployed without TLS? → verify the volume is marked optional: true
kubectl get deployment sail-mcp-server -n sail -o jsonpath=\
  '{.spec.template.spec.volumes[?(@.name=="certs-volume")].secret.optional}'
```

**Broker stuck in non-ready state**

```sh
kubectl describe broker agent-broker -n sail
# Check for auth errors → verify broker-secret in knative-eventing
kubectl get secret broker-secret -n knative-eventing
```

**KafkaSource not consuming messages**

```sh
kubectl describe kafkasource kafka-source -n sail
# TLS errors → verify kafka-tls secret keys match exactly
kubectl get secret kafka-tls -n sail -o jsonpath='{.data}' | jq 'keys'
# Expected: ["ca.pem", "service.cert", "service.key"]
```

**EventTransform service not created**

```sh
kubectl get eventtransform simple-transform -n sail -o yaml
# If the CRD is missing, re-install the Knative Eventing core
kubectl get crd eventtransforms.eventing.knative.dev
```

**Messages not routing to agents**

Send a test message directly to the broker (bypassing Kafka):

```sh
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -sS -X POST http://agent-broker-brokercell-ingress.sail.svc.cluster.local \
  -H "Content-Type: application/json" \
  -H "Ce-Specversion: 1.0" \
  -H "Ce-Type: sail.message" \
  -H "Ce-Source: test" \
  -H "Ce-Id: test-001" \
  -H "Ce-Targetagent: creative-writer-agent" \
  -d '{"payload":"Hello","from":"human","to":"creative-writer-agent","inputs":{}}'
```

Check the target agent pod logs to confirm delivery.

---

## Next Steps

Once the operator, MCP server, and eventing resources are ready:

1. **Apply sample agents** — `cd sail-operator && make agents-add`
2. **Send a message** — post a `SailMessage` JSON to the `agents-messages` Kafka topic

To build and push a new operator image see the `docker-multiarch` target in
[sail-operator/Makefile](../sail-operator/Makefile).
