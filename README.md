# SAIL — Serverless AI Layer

SAIL is a **Kubernetes-native, event-driven multi-agent platform** built on Quarkus, Knative, and Kafka. You define AI agents as Kubernetes custom resources; SAIL wires them together into collaborative pipelines where each agent can call others by sending messages.

---

## Table of Contents

- [What SAIL Does](#what-sail-does)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [1. Install the cluster stack](#1-install-the-cluster-stack)
  - [2. Install SAIL resources](#2-install-sail-resources)
  - [3. Create your first agents](#3-create-your-first-agents)
  - [4. Trigger a pipeline](#4-trigger-a-pipeline)
- [Defining Agents](#defining-agents)
- [Message Format](#message-format)
- [Building & Running Locally](#building--running-locally)
- [Docker Image Builds](#docker-image-builds)
- [Secrets Reference](#secrets-reference)
- [Directory Layout](#directory-layout)

---

## What SAIL Does

You write a `GenericAgent` YAML — just a name, a system prompt, and a user prompt. SAIL's operator automatically provisions a Knative Service and Knative Trigger for it. When a message arrives addressed to that agent, the agent's runtime:

1. Renders the user prompt with Qute (it can reference the incoming message, inputs, and sender).
2. Queries Redis for the list of currently deployed agents.
3. Calls OpenAI through LangChain4j.
4. The LLM invokes the `sendMessage` MCP tool to forward results to the next agent.

No service discovery code. No routing code. Just prompts and Kubernetes.

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Kubernetes Cluster                             │
│                                                                         │
│  ┌─────────────────┐    ┌───────────────────┐    ┌───────────────────┐  │
│  │  sail-operator  │    │  sail-mcp-server  │    │  sail-base-openid │  │
│  │                 │    │                   │    │  (agent runtime)  │  │
│  │  Watches        │    │  HTTP/SSE server  │    │                   │  │
│  │  GenericAgent   │    │  exposes the      │    │  Receives         │  │
│  │  CRs            │    │  sendMessage MCP  │    │  CloudEvents      │  │
│  │                 │    │  tool             │    │  → calls LLM      │  │
│  │  Creates:       │    │                   │    │  → calls MCP tool │  │
│  │  · Knative Svc  │    │  Publishes to     │    │                   │  │
│  │  · Trigger      │    │  Kafka            │    │  One pod per      │  │
│  │  · Redis entry  │    │                   │    │  GenericAgent CR  │  │
│  └─────────────────┘    └───────────────────┘    └───────────────────┘  │
│                                                                         │
│  ┌──────────┐   ┌────────────────────────────────────────────────────┐  │
│  │  Redis   │   │                  Knative Eventing                  │  │
│  │          │   │  KafkaSource → EventTransform → Broker → Trigger   │  │
│  │  Agent   │   └────────────────────────────────────────────────────┘  │
│  │  registry│                                                           │
│  └──────────┘   ┌────────────┐                                          │
│                 │   Kafka    │  topic: agents-messages                  │
│                 └────────────┘                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Message Flow

```
  Human / external system
        │
        │  POST JSON to Kafka topic "agents-messages"
        │  { "to": "creative-writer-agent", "from": "human", "inputs": {...} }
        ▼
  ┌──────────────┐
  │  KafkaSource │  consumes agents-messages
  └──────┬───────┘
         │ CloudEvent
         ▼
  ┌──────────────────┐
  │  EventTransform  │  JSONata: extracts data.to → sets "targetagent" attribute
  └────────┬─────────┘
           │ enriched CloudEvent
           ▼
  ┌──────────────────┐
  │  Knative Broker  │  agent-broker
  └────────┬─────────┘
           │ routes on CE attribute "targetagent"
           ▼
  ┌──────────────────────┐
  │  Trigger             │  filter: targetagent = "creative-writer-agent"
  │  (per agent)         │
  └──────────┬───────────┘
             │
             ▼
  ┌──────────────────────────┐
  │  Knative Service         │  sail-base-openid container
  │  creative-writer-agent   │
  │  -svc                    │
  └──────────┬───────────────┘
             │  1. render Qute prompt with SailMessage
             │  2. query Redis for peer agents
             │  3. call OpenAI via LangChain4j
             │  4. LLM calls sendMessage(to="audience-editor-agent", ...)
             ▼
  ┌───────────────────┐
  │  sail-mcp-server  │  MCP tool: sendMessage → publishes to Kafka
  └───────────────────┘
             │
             ▼  (loop continues for each downstream agent)
        Kafka "agents-messages"
```

### Agent Discovery

The operator writes a Redis key for every `GenericAgent` it reconciles:

```
KEY:   genericagent:<namespace>:<name>
VALUE: {"name":"creative-writer-agent","description":"Generates short creative story drafts"}
```

At runtime, each agent reads all `genericagent*` keys from Redis and appends the list to its prompt. This is how the LLM knows which agents it can route to.

---

## Project Structure

```
sail/
├── sail-operator/          # Kubernetes operator (Quarkus + JOSDK)
│   ├── src/
│   ├── resources/          # CRD + deployment manifests
│   ├── sample/
│   │   ├── agents/         # Example GenericAgent CRs
│   │   └── sail-messages/  # Example trigger payloads
│   └── Makefile
│
├── sail-mcp-server/        # MCP HTTP/SSE server (Quarkus)
│   ├── src/
│   └── Makefile
│
├── sail-base-openid/       # Agent runtime (Quarkus + LangChain4j)
│   └── src/
│
├── resources/
│   └── sail-eventing/      # Knative eventing manifests (applied in order)
│       ├── 00-namespace.yaml
│       ├── 01-broker-cm.yaml
│       ├── 02-agent-broker.yaml
│       ├── 03-eventtransform.yaml
│       └── 04-kafkasource.yaml
│
├── docs/
│   ├── knative-installation.md   # Full Knative install guide
│   └── sail-resources.md         # Deep-dive on every Kubernetes resource
│
└── scripts/
    ├── install-knative-dev.sh    # Automated minikube + Knative + Strimzi setup
    └── install-sail-resources.sh # Installs SAIL onto an existing cluster
```

> Each subproject is **fully independent** — no parent POM, no shared modules. Run `./mvnw` from within each directory.

---

## Prerequisites

| Requirement | Version |
|-------------|---------|
| Java | 21+ |
| Maven | 3.9+ (or use the included `./mvnw`) |
| Kubernetes cluster | 1.28+ |
| Knative Serving + Eventing | v1.21.1 |
| Kafka | Any (Strimzi in-cluster or external with TLS) |
| Redis | 7+ |
| OpenAI API key | — |

---

## Getting Started

### 1. Install the cluster stack

**Local dev (minikube, fully automated):**

```sh
chmod +x scripts/install-knative-dev.sh
./scripts/install-knative-dev.sh
# Then in a separate terminal:
minikube tunnel --profile sail
```

This installs minikube, Knative Serving/Eventing, in-cluster Strimzi Kafka, and Redis. See [docs/knative-installation.md](docs/knative-installation.md) for other options (existing cluster, Istio, etc.).

### 2. Install SAIL resources

```sh
chmod +x scripts/install-sail-resources.sh

# Dev (in-cluster Strimzi, no TLS)
./scripts/install-sail-resources.sh \
  --skip-tls \
  sail-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092

# External Kafka with mTLS (e.g. Aiven)
./scripts/install-sail-resources.sh my-kafka.aivencloud.com:18981
```

This applies the CRD, operator, MCP server, and all eventing resources in the correct order and waits for each to be ready.

### 3. Create your first agents

Apply the sample three-agent pipeline (creative writer → audience editor → style editor):

```sh
cd sail-operator
make agents-add
```

Or apply individual agent files:

```sh
kubectl apply -f sail-operator/sample/agents/creative-writer-agent.yaml
```

List running agents:

```sh
make agents-list
# or
kubectl get genericagents -n sail
```

### 4. Trigger a pipeline

Send a message to the `creative-writer-agent` by publishing to Kafka:

```sh
# The sample payload:
# {"to":"creative-writer-agent","from":"human",
#  "inputs":{"creative-writer-agent":"landing on the moon",
#             "audience-editor-agent":"kids",
#             "style-editor-agent":"serious"}}

kafka-console-producer.sh \
  --bootstrap-server <bootstrap-server> \
  --topic agents-messages \
  --producer.config client.properties \
  --property parse.headers=true \
  --property headers=content-type:application/json \
  < sail-operator/sample/sail-messages/human-to-creative-writer.json
```

The message travels: `human → creative-writer-agent → audience-editor-agent → style-editor-agent`.

---

## Defining Agents

A `GenericAgent` is a standard Kubernetes custom resource:

```yaml
apiVersion: sebi.org/v1
kind: GenericAgent
metadata:
  name: creative-writer-agent
  namespace: sail
spec:
  description: "Generates short creative story drafts"
  systemMessage: You are a creative writer called 'creative-writer-agent'.
  userMessage: |
    Generate a draft of a story no more than 3 sentences long
    around the topic: {sailMessage.inputs['creative-writer-agent']}
    Send the story to an audience editor agent using the sendMessage tool.
    Include the original inputs {sailMessage.inputs} in the SailMessage.
```

| Field | Required | Description |
|-------|----------|-------------|
| `description` | Recommended | Stored in Redis; used by the LLM to discover this agent |
| `systemMessage` | Yes | System prompt for the LLM |
| `userMessage` | Yes | Qute template; receives `sailMessage` as context |
| `agentClassName` | No | Fully-qualified Java class for a custom image. Defaults to `docker.io/sebi2706/sail-base-openai:0.3` |
| `useMemory` | No | Retain conversation history across calls |

**Prompt templating** uses [Qute](https://quarkus.io/guides/qute):

```
{sailMessage.payload}                    → the message text
{sailMessage.from}                       → sender name
{sailMessage.to}                         → this agent's name
{sailMessage.inputs['some-key']}         → named input value
{sailMessage.inputs}                     → all inputs as a map
```

### Custom agent images

If you set `agentClassName`, the operator derives the image automatically:

```
agentClassName: org.sebi.MyCustomAgent
→ image: ghcr.io/sebi/mycustomagent:latest
```

---

## Message Format

`SailMessage` is the canonical message object passed between all agents:

```json
{
  "payload": "The story text or message content",
  "from":    "creative-writer-agent",
  "to":      "audience-editor-agent",
  "inputs":  {
    "creative-writer-agent": "landing on the moon",
    "audience-editor-agent": "kids",
    "style-editor-agent":    "serious"
  }
}
```

The `inputs` map is passed through the entire pipeline unchanged (each agent can read its own entry by name). Agents are instructed in their prompt to forward inputs when calling `sendMessage`.

---

## Building & Running Locally

Each subproject has its own `./mvnw` wrapper. Java 21 is required.

```sh
# Dev mode (hot reload)
cd sail-operator && ./mvnw quarkus:dev      # port 8080
cd sail-mcp-server && ./mvnw quarkus:dev    # port 8081
cd sail-base-openid && ./mvnw quarkus:dev   # port 8080

# Build
./mvnw package

# Build native binary
./mvnw package -Dnative

# Run tests
./mvnw test
```

> `sail-mcp-server` uses port **8081** in dev mode to avoid conflicting with `sail-base-openid` on 8080.

---

## Docker Image Builds

Both `sail-operator` and `sail-mcp-server` have Makefile targets for container images:

```sh
# Build a local single-platform image
make docker-build

# Build and push a multi-arch image (linux/amd64 + linux/arm64)
make docker-multiarch IMAGE_TAG=0.4

# One-time buildx setup
make docker-builder-create
```

Override the repository with `IMAGE_REPO=myorg/myimage`. Defaults are:
- `sail-operator` → `sebi2706/sail-operator`
- `sail-mcp-server` → `sebi2706/sail-mcp-server`
- agent runtime → `sebi2706/sail-base-openai`

---

## Secrets Reference

All credentials are supplied via Kubernetes Secrets — never hardcoded.

| Secret name | Namespace | Key | Used by |
|-------------|-----------|-----|---------|
| `openai-api-key` | `sail` | `OPENAI_API_KEY` | agent runtime (injected by operator) |
| `sail-redis-host` | `sail` | `QUARKUS_REDIS_HOSTS` | operator + agent runtime |
| `kafka-tls` | `sail` | `ca.pem`, `service.cert`, `service.key` | KafkaSource (TLS) |
| `broker-secret` | `knative-eventing` | `protocol`, `ca.crt`, `user.crt`, `user.key` | Knative Kafka Broker |
| `agents-kafka-secrets` | `sail` | `keystore`, `trustore` | agent runtime (Kafka mTLS) |

Create them:

```sh
kubectl create secret generic openai-api-key \
  --namespace sail \
  --from-literal=OPENAI_API_KEY=sk-...

kubectl create secret generic sail-redis-host \
  --namespace sail \
  --from-literal=QUARKUS_REDIS_HOSTS=redis://<host>:6379

kubectl create secret generic kafka-tls \
  --namespace sail \
  --from-file=ca.pem=ca.pem \
  --from-file=service.cert=service.cert \
  --from-file=service.key=service.key
```

---

## Further Reading

- [Knative installation guide](docs/knative-installation.md) — minikube, YAML-based, or quickstart plugin
- [SAIL resources deep-dive](docs/sail-resources.md) — every Kubernetes resource explained
