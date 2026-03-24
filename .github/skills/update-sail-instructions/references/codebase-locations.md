# SAIL Codebase Discovery Locations

Use this map to know exactly where to look when updating `copilot-instructions.md`.

## Architecture Section

| Thing to verify | Where to look |
|----------------|---------------|
| Subproject roles | `sail-*/README.md`, `sail-*/pom.xml` (artifactId, dependencies) |
| Message flow topology | `resources/sail-eventing/` YAML files, `resources/eventtransform.yml` |
| `SailMessage` fields | `sail-mcp-server/src/main/java/org/sebi/SailMessage.java`, same in `sail-base-openid/` |
| Redis key format / discovery | `sail-operator/src/main/java/org/sebi/` — reconciler and Redis client |
| Kafka topic names | `sail-mcp-server/src/main/resources/application.properties`, `sail-base-openid/src/main/resources/application.properties` |
| CRD group / version / finalizer | `sail-operator/resources/genericagents.sebi.org-v1.yml`, `GenericAgentReconciler.java` |
| Knative resource naming | `GenericAgentReconciler.java` — look for `-svc` / `-trigger` string constants |
| MCP tool names / signatures | `sail-mcp-server/src/main/java/org/sebi/` |
| Agent runtime entry point | `sail-base-openid/src/main/java/org/sebi/AgentResource.java` (or similar) |
| Prompt templating syntax | `sail-base-openid/src/main/resources/` — Qute template files (`*.html`, `*.txt`) |

## Build and Run Section

| Thing to verify | Where to look |
|----------------|---------------|
| Maven goals / flags | `sail-*/pom.xml` (quarkus-maven-plugin config) |
| Dev-mode ports | `sail-*/src/main/resources/application.properties` — `%dev.quarkus.http.port` |
| Makefile targets | `sail-operator/Makefile`, `sail-mcp-server/Makefile` |
| Agent management scripts | `sail-operator/scripts/agents.sh` |
| Container image tags | `sail-*/src/main/docker/Dockerfile.*`, `sail-operator/sample/agents/*.yaml` (image field) |
| Kubernetes manifests | `sail-operator/resources/kubernetes.yml`, `sail-mcp-server/kubernetes.yml` |

## Conventions Section

| Thing to verify | Where to look |
|----------------|---------------|
| Java package | Any `.java` source file — should be `org.sebi` |
| Quarkus profile keys | All `application.properties` files — `%dev.*` and `%prod.*` prefixes |
| Secret names | `sail-*/src/main/resources/application.properties` — `${SECRET_NAME}` references |
| Container registries | `sail-operator/sample/agents/*.yaml` (image field), `scripts/build-images.sh` |
| Test dependencies present | `sail-*/pom.xml` — look for `quarkus-junit5`, `rest-assured` |

## Quick Search Commands

```sh
# Find SailMessage definition
grep -r "class SailMessage" sail-*/src/

# Find all Kafka topic references
grep -r "agents-messages" sail-*/src/main/resources/

# Find Knative service/trigger naming
grep -r "\-svc\|-trigger" sail-operator/src/

# Find Redis key format
grep -r "genericagent:" sail-operator/src/

# Find dev port overrides
grep -r "quarkus.http.port" sail-*/src/main/resources/

# Check current default image
grep -r "image:" sail-operator/sample/agents/
```
