# sail-operator

This project uses Quarkus, the Supersonic Subatomic Java Framework.

If you want to learn more about Quarkus, please visit its website: <https://quarkus.io/>.

## Running the application in dev mode

You can run your application in dev mode that enables live coding using:

```shell script
./mvnw quarkus:dev
```

> **_NOTE:_**  Quarkus now ships with a Dev UI, which is available in dev mode only at <http://localhost:8080/q/dev/>.

## Packaging and running the application

The application can be packaged using:

```shell script
./mvnw package
```

It produces the `quarkus-run.jar` file in the `target/quarkus-app/` directory.
Be aware that it’s not an _über-jar_ as the dependencies are copied into the `target/quarkus-app/lib/` directory.

The application is now runnable using `java -jar target/quarkus-app/quarkus-run.jar`.

If you want to build an _über-jar_, execute the following command:

```shell script
./mvnw package -Dquarkus.package.jar.type=uber-jar
```

The application, packaged as an _über-jar_, is now runnable using `java -jar target/*-runner.jar`.

## Creating a native executable

You can create a native executable using:

```shell script
./mvnw package -Dnative
```

Or, if you don't have GraalVM installed, you can run the native executable build in a container using:

```shell script
./mvnw package -Dnative -Dquarkus.native.container-build=true
```

You can then execute your native executable with: `./target/sail-operator-1.0.0-SNAPSHOT-runner`

If you want to learn more about building native executables, please consult <https://quarkus.io/guides/maven-tooling>.

## Related Guides

- Operator SDK ([guide](https://docs.quarkiverse.io/quarkus-operator-sdk/dev/index.html)): Quarkus extension for the Java Operator SDK (https://javaoperatorsdk.io)

---

## Managing sample agents ✅

You can add and remove the sample agents in `sample/agents` using the provided Makefile targets or convenient shell aliases.

Usage (make targets):

- **Add agents**

```sh
make agents-add
```

- **Delete agents defined in** `sample/agents`

```sh
make agents-delete
```

- **Delete *all* `GenericAgent` custom resources** (current namespace)

```sh
make agents-delete-all
```

### Redis cleanup on delete ✅

When a `GenericAgent` is deleted, the operator removes an associated Redis key `genericagent:<namespace>:<name>` that stores the agent name and description. The operator uses a Kubernetes finalizer `genericagent.sebi.org/redis-cleanup` to ensure the Redis key is removed before the resource is fully deleted.

Make sure `quarkus.redis.hosts` is configured so the operator can reach Redis (see earlier in this README). If you prefer the operator to not manage Redis keys, you can remove the finalizer from the resource metadata or disable Redis by not setting `quarkus.redis.hosts`.

- **Recreate agents**

```sh
make agents-recreate
```

- **List agents**

```sh
make agents-list
```

You can either use the Makefile targets or the convenience script `scripts/agents.sh`.

- Using the helper script (recommended):

```sh
# Make it executable once
chmod +x scripts/agents.sh

# Examples
scripts/agents.sh add
scripts/agents.sh delete
scripts/agents.sh delete-all -n my-namespace --yes
scripts/agents.sh recreate
scripts/agents.sh list
```

Suggested `zsh` aliases (add to `~/.zshrc`):

```sh
# point aliases at the script
alias sail-add-agents='scripts/agents.sh add'
alias sail-delete-agents='scripts/agents.sh delete'
alias sail-delete-all-agents='scripts/agents.sh delete-all'
alias sail-recreate-agents='scripts/agents.sh recreate'
alias sail-list-agents='scripts/agents.sh list'
```

Then run `source ~/.zshrc` (or open a new terminal) to enable the aliases.

---

## Agent description & Redis metadata (new)

Each `GenericAgent` spec supports an optional `description` field which gets stored in Redis when the controller reconciles the resource.

- To enable Redis, configure it in `src/main/resources/application.properties` or via environment variable `QUARKUS_REDIS_HOSTS`, e.g.:

```properties
# quarkus.redis.hosts=redis://localhost:6379
```

- The controller writes a key `genericagent:<namespace>:<name>` with value `{"name":"<name>","description":"<description>"}` (JSON string). If `description` is empty the field will be an empty string.

- The Redis client used is the Quarkus `quarkus-redis-client` extension.

