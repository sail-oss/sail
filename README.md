

## Creating Secrets for Secured Kafka Connections

```
kubectl create secret generic agents-kafka-secrets --from-file=keystore=client.keystore.p12 --from-file=trustore=client.truststore.jks
```

```
kubectl create secret broker-secret \
  --from-literal=protocol=SSL \
  --from-file=ca.crt=ca.pem \
  --from-file=user.crt=service.cert \
  --from-file=user.key=service.key
```

```
kubectl create secret generic kafka-tls \
  --from-file=ca.pem=ca.pem \
  --from-file=service.cert=service.cert \
  --from-file=service.key=service.key
```

### Install KafkaSource
https://knative.dev/docs/eventing/sources/kafka-source/


```
kubectl create secret generic sail-redis-host \  --from-literal=QUARKUS_REDIS_HOSTS=<your_redis_host>
```

```
kubectl create secret generic openai-api-key \  --from-literal=OPENAI_API_KEY=<YOUR_KEY>
```

## Trigger agent

```

kafka-console-producer.sh \
  --bootstrap-server my-broker:9093 \
  --topic agents-messages \
  --producer.config client.properties \
  --property parse.headers=true \
  --property headers=content-type:application/json \
  < human-to-creative-writer.json

```