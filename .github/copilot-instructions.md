# Copilot Instructions for SAIL

## Architecture

SAIL is a Kubernetes-native, event-driven multi-agent platform. It has three independent Quarkus subprojects (no parent POM, no shared modules):

- **sail-operator** — Kubernetes operator that watches `GenericAgent` custom resources (CRD group `sebi.org/v1`) and provisions a Knative Service + Trigger for each agent. Stores agent metadata in Redis for discovery. Uses a finalizer (`genericagent.sebi.org/redis-cleanup`) to clean up Redis keys on deletion.
- **sail-mcp-server** — Stateless MCP (Model Context Protocol) HTTP/SSE server exposing a `sendMessage` tool that publishes `SailMessage` objects to a Kafka topic (`agents-messages`). All agents call this shared tool to route messages to other agents.
- **sail-base-openid** — The AI agent runtime. Receives CloudEvents from Knative, renders prompt templates with Qute (using `SailMessage` context), queries Redis for available agents, then calls OpenAI via LangChain4j. The LLM invokes MCP tools to send messages onward.

### Message flow

```
Human/Agent → Kafka "agents-messages"
  → KafkaSource → EventTransform (JSONata, extracts "targetagent" from data.to)
  → Knative Broker "agent-broker"
  → Trigger (filters by targetagent) → Knative Service (agent container)
  → AgentResource receives CloudEvent → LLM processes → sendMessage tool → Kafka
```

### Shared data model

`SailMessage` is the canonical message format (duplicated in sail-mcp-server and sail-base-openid):

```java
{ "payload": String, "from": String, "to": String, "inputs": Map<String, Object> }
```

Agent discovery works via Redis keys `genericagent:<namespace>:<name>` containing `{"name":"...","description":"..."}`.

## Build and Run

All subprojects use Maven with the Quarkus plugin. Java 21 is required. Each subproject has its own `mvnw` wrapper — run commands from within each subproject directory.

```sh
# Dev mode (any subproject)
./mvnw quarkus:dev

# Build
./mvnw package

# Build native
./mvnw package -Dnative

# Run tests
./mvnw test
```

The sail-mcp-server runs on port 8081 in dev mode (`%dev.quarkus.http.port=8081`) to avoid conflicts with sail-base-openid on 8080.

### Operator agent management

```sh
cd sail-operator
make agents-add          # Apply sample agents from sample/agents/
make agents-delete       # Delete sample agents
make agents-delete-all   # Delete all GenericAgent CRs
make agents-recreate     # Delete then re-apply sample agents
make agents-list         # List agents
```

Or use `scripts/agents.sh add|delete|delete-all|recreate|list`.

### Docker image builds

Both `sail-operator` and `sail-mcp-server` have Make targets for building container images:

```sh
# Build single-platform image for local Docker daemon
make docker-build

# Build and push multi-arch image (linux/amd64 + linux/arm64)
make docker-multiarch IMAGE_TAG=0.4

# One-time setup: create the buildx builder
make docker-builder-create
```

The `IMAGE_REPO` defaults to `sebi2706/sail-operator` and `sebi2706/sail-mcp-server` respectively; override with `make docker-build IMAGE_REPO=myrepo/myimage`.

## Conventions

- **Package**: `org.sebi` across all modules
- **Quarkus profiles**: `%dev` and `%prod` prefixes in `application.properties` for environment-specific config
- **Kubernetes secrets** provide all credentials (OpenAI API key, Redis host, Kafka TLS certs) — never hardcode secrets
- **Knative naming**: operator creates services as `{agent-name}-svc` and triggers as `{agent-name}-trigger`
- **Default agent image**: `docker.io/sebi2706/sail-base-openai:0.3` (used when `agentClassName` is not set)
- **Custom agent image**: when `agentClassName` is set, the operator derives the image as `ghcr.io/sebi/<sanitized-class-name>:latest`
- **Container registries**: Docker Hub (`sebi2706/`) and GHCR (`ghcr.io/sebi/`)
- **CRD reconciler**: `GenericAgentReconciler` uses server-side apply and owner references for all child resources
- **Prompt templating**: Agent prompts use Qute syntax — `{sailMessage.inputs['agent-name']}` accesses message context
- **No tests currently exist** in any subproject; test dependencies (quarkus-junit5, rest-assured) are configured in sail-base-openid and sail-operator
