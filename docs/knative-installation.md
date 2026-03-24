# Knative Installation Guide for SAIL

This guide covers installing Knative Serving, Knative Eventing, and the Kafka components required by SAIL. It provides multiple installation paths depending on your environment.

> **Knative version used throughout this guide: v1.21.1**

---

## Table of Contents

- [Option 1: Local Dev Setup (minikube) — Automated](#option-1-local-dev-setup-minikube--automated)
- [Option 2: YAML-based Install on an Existing Cluster](#option-2-yaml-based-install-on-an-existing-cluster)
- [Option 3: Knative Quickstart Plugin (Minimal)](#option-3-knative-quickstart-plugin-minimal)
- [Kafka SSL/TLS Configuration](#kafka-ssltls-configuration)
- [Redis](#redis)

---

## Option 1: Local Dev Setup (minikube) — Automated

This is the recommended path for development. The script `scripts/install-knative-dev.sh` installs everything on a local minikube cluster, including an in-cluster Kafka via Strimzi.

### Prerequisites

- [minikube](https://minikube.sigs.k8s.io/docs/start/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- At least **4 CPUs** and **8 GB RAM** available for the minikube VM

### Run the script

```sh
chmod +x scripts/install-knative-dev.sh
./scripts/install-knative-dev.sh
```

The script performs the following steps:

1. Creates a minikube cluster named `sail` with 4 CPUs and 8 GB RAM
2. Installs Knative Serving CRDs and core
3. Installs Kourier as the networking layer
4. Configures `sslip.io` magic DNS
5. Installs Knative Eventing CRDs and core
6. Installs the Kafka controller (eventing-kafka-broker)
7. Installs Kafka Broker, KafkaSource, KafkaSink, and KafkaChannel data planes
8. Installs Strimzi Kafka operator and creates a single-node Kafka cluster
9. Installs a single-pod Redis and creates the `sail-redis-host` secret
10. Verifies all components are running

After the script completes, start the minikube tunnel in a separate terminal:

```sh
minikube tunnel --profile sail
```

### What the dev setup does NOT include

- SSL/TLS on Kafka (the in-cluster Strimzi Kafka uses plaintext for simplicity)
- Production-grade replication (single-node Kafka)

For secured Kafka connections, see [Kafka SSL/TLS Configuration](#kafka-ssltls-configuration).

---

## Option 2: YAML-based Install on an Existing Cluster

Use this for staging or production clusters where you already have a Kubernetes cluster and an external Kafka (e.g., Aiven, Confluent, Amazon MSK).

### Prerequisites

- A running Kubernetes cluster (1.28+)
- `kubectl` configured to access the cluster
- An external Kafka cluster with SSL/TLS certificates (see [Kafka SSL/TLS Configuration](#kafka-ssltls-configuration))

### Step 1 — Knative Serving

```sh
# CRDs
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.21.1/serving-crds.yaml

# Core
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.21.1/serving-core.yaml
```

Install a networking layer (pick one):

**Kourier (lightweight, recommended for most cases):**

```sh
kubectl apply -f https://github.com/knative-extensions/net-kourier/releases/download/knative-v1.21.0/kourier.yaml

kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
```

**Istio (if you already use Istio):**

```sh
kubectl apply -l knative.dev/crd-install=true \
  -f https://github.com/knative-extensions/net-istio/releases/download/knative-v1.21.1/istio.yaml
kubectl apply -f https://github.com/knative-extensions/net-istio/releases/download/knative-v1.21.1/istio.yaml
kubectl apply -f https://github.com/knative-extensions/net-istio/releases/download/knative-v1.21.1/net-istio.yaml

kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"istio.ingress.networking.knative.dev"}}'
```

Configure DNS:

```sh
# Magic DNS (for development/testing — requires LoadBalancer support)
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.21.1/serving-default-domain.yaml
```

For production, configure a real wildcard DNS record pointing to your ingress IP. See the [Knative DNS docs](https://knative.dev/docs/install/yaml-install/serving/install-serving-with-yaml/#configure-dns).

Verify:

```sh
kubectl get pods -n knative-serving
```

### Step 2 — Knative Eventing

```sh
# CRDs
kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.21.1/eventing-crds.yaml

# Core
kubectl apply -f https://github.com/knative/eventing/releases/download/knative-v1.21.1/eventing-core.yaml
```

Verify:

```sh
kubectl get pods -n knative-eventing
```

### Step 3 — Kafka Components

All Kafka components share a common controller. Install it first, then add the data planes you need.

```sh
# Kafka controller (required for all Kafka components)
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-v1.21.1/eventing-kafka-controller.yaml

# Kafka Broker data plane
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-v1.21.1/eventing-kafka-broker.yaml

# KafkaSource data plane
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-v1.21.1/eventing-kafka-source.yaml

# KafkaSink data plane
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-v1.21.1/eventing-kafka-sink.yaml

# KafkaChannel data plane (optional, for channel-based messaging)
kubectl apply -f https://github.com/knative-extensions/eventing-kafka-broker/releases/download/knative-v1.21.1/eventing-kafka-channel.yaml
```

Verify:

```sh
kubectl get deployments.apps -n knative-eventing
# Should show: kafka-controller, kafka-broker-receiver, kafka-broker-dispatcher,
#              kafka-source-dispatcher, kafka-sink-receiver
```

### Step 4 — SAIL Kubernetes Resources

Once Knative and the Kafka components are ready, deploy the SAIL-specific resources:

```sh
# Kafka broker ConfigMap (edit bootstrap.servers to match your Kafka cluster)
kubectl apply -f resources/broker-cm.yml

# Knative Kafka Broker
kubectl apply -f resources/agent-broker.yaml

# EventTransform (JSONata-based CloudEvent transformation)
kubectl apply -f resources/eventtransform.yml

# KafkaSource (connects Kafka topic to the event pipeline)
kubectl apply -f resources/kafkasource.yaml
```

---

## Option 3: Knative Quickstart Plugin (Minimal)

The quickstart plugin gives you Knative Serving + Eventing in one command, but uses in-memory channels (no Kafka). Useful for a quick test of Knative concepts, but **not sufficient for SAIL** since SAIL requires the Kafka Broker and KafkaSource.

```sh
# Install the kn CLI and quickstart plugin
brew install knative/client/kn
brew install knative-extensions/kn-plugins/quickstart

# Create a local cluster with Knative
kn quickstart minikube   # or: kn quickstart kind
```

After quickstart, you still need to install the Kafka components from [Step 3](#step-3--kafka-components) above.

---

## Kafka SSL/TLS Configuration

SAIL uses SSL/TLS with mutual authentication (mTLS) to connect to Kafka. This section explains how to configure the Kubernetes secrets and Knative resources for a secured Kafka cluster.

### Certificate Formats

SAIL uses two certificate formats depending on the component:

| Component | Format | Usage |
|-----------|--------|-------|
| Knative Broker / KafkaSource | PEM files (`.pem`, `.crt`, `.key`) | Knative-native Kafka components expect PEM |
| Quarkus applications (sail-mcp-server, sail-base-openid) | PKCS12 keystore + JKS truststore | Java/Quarkus Kafka clients use JKS/PKCS12 |

### Converting Between Formats

If your Kafka provider gives you PEM files and you need Java keystores:

```sh
# Create PKCS12 keystore from PEM cert + key
openssl pkcs12 -export \
  -in service.cert \
  -inkey service.key \
  -name kafka-client \
  -out client.keystore.p12 \
  -password pass:changeit

# Create JKS truststore from CA certificate
keytool -importcert \
  -file ca.pem \
  -alias kafka-ca \
  -keystore client.truststore.jks \
  -storepass changeit \
  -noprompt
```

If you have Java keystores and need PEM files:

```sh
# Extract client cert from PKCS12
openssl pkcs12 -in client.keystore.p12 -clcerts -nokeys -out service.cert -password pass:changeit

# Extract client key from PKCS12
openssl pkcs12 -in client.keystore.p12 -nocerts -nodes -out service.key -password pass:changeit
```

### Creating Kubernetes Secrets

SAIL requires three secrets for Kafka TLS. Create them in the namespace where SAIL is deployed (default: `sail`):

**1. `broker-secret` — Used by the Knative Kafka Broker**

This secret is referenced by the broker's ConfigMap (`kafka-broker-config`) via `auth.secret.ref.name`. It must be in the `knative-eventing` namespace (or the namespace of the ConfigMap).

```sh
kubectl create secret generic broker-secret \
  --namespace knative-eventing \
  --from-literal=protocol=SSL \
  --from-file=ca.crt=ca.pem \
  --from-file=user.crt=service.cert \
  --from-file=user.key=service.key
```

| Key | Description |
|-----|-------------|
| `protocol` | Must be `SSL` for TLS authentication |
| `ca.crt` | CA certificate in PEM format |
| `user.crt` | Client certificate in PEM format |
| `user.key` | Client private key in PEM format |

**2. `kafka-tls` — Used by the KafkaSource**

This secret is referenced directly in the KafkaSource spec. Create it in the same namespace as the KafkaSource.

```sh
kubectl create secret generic kafka-tls \
  --from-file=ca.pem=ca.pem \
  --from-file=service.cert=service.cert \
  --from-file=service.key=service.key
```

The KafkaSource references these keys in its `spec.net.tls` section:

```yaml
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
```

**3. `agents-kafka-secrets` — Used by Quarkus application pods (sail-mcp-server, sail-base-openid)**

This secret is mounted as a volume at `/etc/certs` inside agent containers.

```sh
kubectl create secret generic agents-kafka-secrets \
  --from-file=keystore=client.keystore.p12 \
  --from-file=trustore=client.truststore.jks
```

| Key | Description |
|-----|-------------|
| `keystore` | PKCS12 keystore containing the client cert + key |
| `trustore` | JKS truststore containing the CA certificate |

The corresponding Quarkus configuration in `application.properties`:

```properties
kafka.security.protocol=SSL
kafka.ssl.protocol=TLS

kafka.ssl.keystore.location=/etc/certs/client.keystore.p12
kafka.ssl.keystore.type=PKCS12
kafka.ssl.keystore.password=<your-keystore-password>
kafka.ssl.key.password=<your-key-password>

kafka.ssl.truststore.location=/etc/certs/client.truststore.jks
kafka.ssl.truststore.type=JKS
kafka.ssl.truststore.password=<your-truststore-password>
```

### Broker ConfigMap for Secured Kafka

The `kafka-broker-config` ConfigMap must reference the `broker-secret`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kafka-broker-config
  namespace: knative-eventing
data:
  default.topic.partitions: "2"
  default.topic.replication.factor: "2"
  bootstrap.servers: "<your-kafka-bootstrap-server>:<port>"
  auth.secret.ref.name: broker-secret
```

### Other Kafka SSL Modes

The Knative Kafka Broker supports several SSL configurations beyond mTLS:

**SSL encryption only (no client certificate):**

```sh
kubectl create secret generic broker-secret \
  --namespace knative-eventing \
  --from-literal=protocol=SSL \
  --from-file=ca.crt=ca.pem \
  --from-literal=user.skip=true
```

**SASL + SSL (username/password with encryption):**

```sh
kubectl create secret generic broker-secret \
  --namespace knative-eventing \
  --from-literal=protocol=SASL_SSL \
  --from-literal=sasl.mechanism=SCRAM-SHA-512 \
  --from-file=ca.crt=ca.pem \
  --from-literal=user=<username> \
  --from-literal=password=<password>
```

---

## Redis

SAIL uses Redis for agent discovery — the operator stores agent metadata as `genericagent:<namespace>:<name>` keys, and agent pods query these keys at runtime to know which other agents are available. A running Redis instance is required for the operator and the agent runtime (`sail-base-openid`).

### Option A: Quick single-pod Redis (dev)

This is what the dev install script (`scripts/install-knative-dev.sh`) sets up automatically.

```sh
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
```

Then create the secret the operator and agents use to discover Redis:

```sh
kubectl create secret generic sail-redis-host \
  --namespace sail \
  --from-literal=QUARKUS_REDIS_HOSTS=redis://redis.sail.svc.cluster.local:6379
```

### Option B: Redis with persistence (staging / production)

Add a PersistentVolumeClaim so data survives pod restarts:

```sh
kubectl apply -n sail -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-data
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
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
          args: ["--appendonly", "yes"]
          ports:
            - containerPort: 6379
          volumeMounts:
            - name: data
              mountPath: /data
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: redis-data
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
```

### Option C: Redis with password authentication

For environments requiring authentication, configure Redis with a password via a secret:

```sh
# Create a secret holding the Redis password
kubectl create secret generic redis-password \
  --namespace sail \
  --from-literal=REDIS_PASSWORD=<your-password>
```

```sh
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
          args: ["--requirepass", "$(REDIS_PASSWORD)", "--appendonly", "yes"]
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-password
                  key: REDIS_PASSWORD
          ports:
            - containerPort: 6379
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
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
```

Update the SAIL secret to include the password in the connection string:

```sh
kubectl create secret generic sail-redis-host \
  --namespace sail \
  --from-literal=QUARKUS_REDIS_HOSTS=redis://:<your-password>@redis.sail.svc.cluster.local:6379
```

### Option D: External / managed Redis

If using a managed Redis service (AWS ElastiCache, Azure Cache, Redis Cloud, etc.), just create the connection secret:

```sh
kubectl create secret generic sail-redis-host \
  --namespace sail \
  --from-literal=QUARKUS_REDIS_HOSTS=redis://:<password>@<host>:<port>
```

For TLS-enabled managed Redis:

```sh
kubectl create secret generic sail-redis-host \
  --namespace sail \
  --from-literal=QUARKUS_REDIS_HOSTS=rediss://:<password>@<host>:<port>
```

> Note the `rediss://` scheme (double `s`) which tells the Quarkus Redis client to use TLS.

### Verify Redis

```sh
# Check the pod is running
kubectl get pods -n sail -l app=redis

# Test connectivity from inside the cluster
kubectl run -n sail redis-test --rm -it --image=redis:7-alpine -- \
  redis-cli -h redis.sail.svc.cluster.local ping
# Expected output: PONG
```

---

## Verifying the Full Stack

Once everything is installed, verify all components:

```sh
# Knative Serving
kubectl get pods -n knative-serving

# Knative Eventing + Kafka components
kubectl get pods -n knative-eventing

# SAIL Broker
kubectl get brokers

# KafkaSource
kubectl get kafkasources

# EventTransform
kubectl get eventtransforms
```
