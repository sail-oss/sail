package org.sebi;

import io.javaoperatorsdk.operator.api.reconciler.ControllerConfiguration;
import io.javaoperatorsdk.operator.api.reconciler.DeleteControl;
import io.javaoperatorsdk.operator.api.reconciler.Cleaner;
import io.javaoperatorsdk.operator.api.reconciler.Context;
import io.javaoperatorsdk.operator.api.reconciler.Reconciler;
import io.javaoperatorsdk.operator.api.reconciler.UpdateControl;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import org.jboss.logging.Logger;

import io.fabric8.kubernetes.api.model.ContainerBuilder;
import io.fabric8.kubernetes.api.model.EnvVarBuilder;
import io.fabric8.kubernetes.api.model.EnvVarSourceBuilder;
import io.fabric8.kubernetes.api.model.OwnerReferenceBuilder;
import io.fabric8.kubernetes.api.model.SecretKeySelectorBuilder;
import io.fabric8.kubernetes.api.model.VolumeMountBuilder;
import io.fabric8.kubernetes.api.model.VolumeBuilder;
import io.fabric8.kubernetes.api.model.SecretVolumeSourceBuilder;
import io.fabric8.kubernetes.api.model.KeyToPathBuilder;
import io.fabric8.kubernetes.api.model.ObjectMeta;
import io.fabric8.knative.serving.v1.Service;
import io.fabric8.knative.serving.v1.ServiceBuilder;
import io.fabric8.knative.serving.v1.RevisionTemplateSpecBuilder;
import io.fabric8.knative.eventing.v1.Trigger;
import io.fabric8.knative.eventing.v1.TriggerBuilder;
import io.fabric8.knative.eventing.v1.TriggerFilterBuilder;
import io.fabric8.knative.duck.v1.KReferenceBuilder;
import io.fabric8.knative.duck.v1.DestinationBuilder;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Reconciler for GenericAgent CustomResource.
 *
 * On each reconciliation it ensures the {@link GenericAgentStatus} is set and
 * updates it when needed.
 */
@ControllerConfiguration
@ApplicationScoped
public class GenericAgentReconciler implements Reconciler<GenericAgent>, Cleaner<GenericAgent> {

    private static final Logger log = Logger.getLogger(GenericAgentReconciler.class);

    // Finalizer and configuration constants
    private static final String REDIS_FINALIZER = "genericagent.sebi.org/redis-cleanup";
    private static final String DEFAULT_NAMESPACE = "default";
    private static final String UNKNOWN_NAME = "<unknown>";
    
    // Service naming constants
    private static final String SERVICE_SUFFIX = "-svc";
    private static final String TRIGGER_SUFFIX = "-trigger";
    private static final String REDIS_KEY_PREFIX = "genericagent:";
    
    // Image constants
    private static final String DEFAULT_IMAGE = "docker.io/sebi2706/sail-base-openai:0.3";
    private static final String IMAGE_REGISTRY = "ghcr.io/sebi/";
    private static final String IMAGE_TAG = ":latest";
    
    // Environment variable constants
    private static final String OPENAI_KEY_ENV = "QUARKUS_LANGCHAIN4J_OPENAI_API_KEY";
    private static final String OPENAI_SECRET_NAME = "openai-api-key";
    private static final String OPENAI_SECRET_KEY = "OPENAI_API_KEY";
    
    private static final String REDIS_HOSTS_ENV = "QUARKUS_REDIS_HOSTS";
    private static final String REDIS_SECRET_NAME = "sail-redis-host";
    
    private static final String PROMPT_USER_ENV = "PROMPT_USER";
    private static final String PROMPT_SYSTEM_ENV = "PROMPT_SYSTEM";
    
    private static final String MCP_URL_ENV = "QUARKUS_LANGCHAIN4J_MCP_SAIL_URL";
    private static final String MCP_URL_VALUE = "http://sail-mcp-server.sail.svc.cluster.local/mcp/sse";
    
    // Volume constants
    private static final String CERTS_VOLUME_NAME = "certs-volume";
    private static final String CERTS_MOUNT_PATH = "/etc/certs";
    private static final String KEYSTORE_SECRET_NAME = "agents-kafka-secrets";
    
    // Knative constants
    private static final String KNATIVE_SERVING_API = "serving.knative.dev/v1";
    private static final String KNATIVE_SERVICE_KIND = "Service";
    private static final String BROKER_NAME = "agent-broker";
    private static final String TARGET_AGENT_FILTER = "targetagent";
    
    // Status constants
    private static final String STATUS_RECONCILED = "Reconciled";
    private static final String STATUS_ERROR = "Error";

    @Inject
    io.fabric8.kubernetes.client.KubernetesClient client;

    @Inject
    io.quarkus.redis.datasource.RedisDataSource redisDataSource;

    @Override
    public UpdateControl<GenericAgent> reconcile(GenericAgent resource, Context<GenericAgent> context) {
        ReconciliationContext ctx = new ReconciliationContext(resource);
        log.infof("Reconciling GenericAgent %s/%s", ctx.namespace, ctx.name);

        try {
            handleFinalizerLogic(ctx);
            
            String image = chooseImage(ctx.spec.getAgentClassName());
            createOrUpdateKnativeResources(ctx, image);
            storeMetadataInRedis(ctx);
            
            GenericAgentStatus desiredStatus = buildStatus(STATUS_RECONCILED, ctx, image);
            return updateStatusIfChanged(resource, desiredStatus);
            
        } catch (Exception e) {
            log.errorf(e, "Failed to ensure Knative resources for %s/%s", ctx.namespace, ctx.name);
            GenericAgentStatus errStatus = new GenericAgentStatus();
            errStatus.setState(STATUS_ERROR);
            errStatus.setMessage(e.getMessage());
            resource.setStatus(errStatus);
            return UpdateControl.patchStatus(resource);
        }
    }

    private void handleFinalizerLogic(ReconciliationContext ctx) {
        ObjectMeta metadata = ctx.resource.getMetadata();
        
        // Deletion flow: actual cleanup is handled by the cleanup method
        if (metadata != null && metadata.getDeletionTimestamp() != null) {
            log.infof("Resource %s/%s is being deleted; deferring Redis cleanup to cleanup()", ctx.namespace, ctx.name);
            return;
        }

        List<String> finalizers = metadata != null ? metadata.getFinalizers() : null;
        if (finalizers == null || !finalizers.contains(REDIS_FINALIZER)) {
            addFinalizerToResource(ctx);
        }
    }
    
    private void addFinalizerToResource(ReconciliationContext ctx) {
        ObjectMeta metadata = ctx.resource.getMetadata();
        List<String> finalizers = metadata != null && metadata.getFinalizers() != null 
            ? new ArrayList<>(metadata.getFinalizers())
            : new ArrayList<>();
        
        finalizers.add(REDIS_FINALIZER);
        
        ObjectMeta updatedMetadata = metadata != null ? metadata : new ObjectMeta();
        updatedMetadata.setFinalizers(finalizers);
        updatedMetadata.setManagedFields(null);

        try {
            final ObjectMeta finalMetadata = updatedMetadata;
            client.resource(ctx.resource).inNamespace(ctx.namespace).edit(r -> {
                ObjectMeta md = r.getMetadata() == null ? new ObjectMeta() : r.getMetadata();
                md.setFinalizers(finalMetadata.getFinalizers());
                md.setManagedFields(null);
                r.setMetadata(md);
                return r;
            });
            log.infof("Added finalizer %s for %s/%s via direct edit", REDIS_FINALIZER, ctx.namespace, ctx.name);
        } catch (Exception ex) {
            log.warnf(ex, "Direct edit to add finalizer failed for %s/%s; falling back to patchResource", ctx.namespace, ctx.name);
            ctx.resource.setMetadata(updatedMetadata);
        }
    }
    
    private void createOrUpdateKnativeResources(ReconciliationContext ctx, String image) {
        var ownerRef = buildOwnerReference(ctx);
        
        Service service = buildKnativeService(ctx, image, ownerRef);
        client.resource(service).inNamespace(ctx.namespace).serverSideApply();
        log.infof("Ensured Knative Service %s/%s with image %s", ctx.namespace, ctx.serviceName, image);

        Trigger trigger = buildKnativeTrigger(ctx, ownerRef);
        client.resource(trigger).inNamespace(ctx.namespace).serverSideApply();
        log.infof("Ensured Knative Trigger %s/%s -> %s", ctx.namespace, ctx.triggerName, ctx.serviceName);
    }
    
    private io.fabric8.kubernetes.api.model.OwnerReference buildOwnerReference(ReconciliationContext ctx) {
        String uid = ctx.resource.getMetadata() != null ? ctx.resource.getMetadata().getUid() : null;
        if (uid == null) {
            return null;
        }
        
        return new OwnerReferenceBuilder()
                .withApiVersion(ctx.resource.getApiVersion())
                .withKind(ctx.resource.getKind())
                .withName(ctx.name)
                .withUid(uid)
                .withController(true)
                .withBlockOwnerDeletion(true)
                .build();
    }
    
    private Service buildKnativeService(ReconciliationContext ctx, String image, 
                                       io.fabric8.kubernetes.api.model.OwnerReference ownerRef) {
        var container = buildContainer(ctx, image).build();
        var volumes = buildVolumes();
        
        return new ServiceBuilder()
                .withNewMetadata()
                    .withName(ctx.serviceName)
                    .withNamespace(ctx.namespace)
                    .addToOwnerReferences(ownerRef)
                .endMetadata()
                .withNewSpec()
                    .withTemplate(new RevisionTemplateSpecBuilder()
                            .withNewSpec()
                                .withContainers(container)
                                .withVolumes(volumes)
                            .endSpec()
                            .build())
                .endSpec()
                .build();
    }
    
    private ContainerBuilder buildContainer(ReconciliationContext ctx, String image) {
        return new ContainerBuilder()
                .withImage(image)
                .withEnv(
                        buildOpenAIKeyEnv().build(),
                        buildRedisHostsEnv().build(),
                        buildPromptUserEnv(ctx).build(),
                        buildPromptSystemEnv(ctx).build(),
                        buildMcpUrlEnv().build()
                )
                .withVolumeMounts(buildCertsVolumeMount().build());
    }
    
    private EnvVarBuilder buildOpenAIKeyEnv() {
        return new EnvVarBuilder()
                .withName(OPENAI_KEY_ENV)
                .withValueFrom(new EnvVarSourceBuilder()
                        .withSecretKeyRef(new SecretKeySelectorBuilder()
                                .withName(OPENAI_SECRET_NAME)
                                .withKey(OPENAI_SECRET_KEY)
                                .build())
                        .build());
    }
    
    private EnvVarBuilder buildRedisHostsEnv() {
        return new EnvVarBuilder()
                .withName(REDIS_HOSTS_ENV)
                .withValueFrom(new EnvVarSourceBuilder()
                        .withSecretKeyRef(new SecretKeySelectorBuilder()
                                .withName(REDIS_SECRET_NAME)
                                .withKey(REDIS_HOSTS_ENV)
                                .build())
                        .build());
    }
    
    private EnvVarBuilder buildPromptUserEnv(ReconciliationContext ctx) {
        return new EnvVarBuilder()
                .withName(PROMPT_USER_ENV)
                .withValue(ctx.spec.getUserMessage());
    }
    
    private EnvVarBuilder buildPromptSystemEnv(ReconciliationContext ctx) {
        return new EnvVarBuilder()
                .withName(PROMPT_SYSTEM_ENV)
                .withValue(ctx.spec.getSystemMessage());
    }
    
    private EnvVarBuilder buildMcpUrlEnv() {
        return new EnvVarBuilder()
                .withName(MCP_URL_ENV)
                .withValue(MCP_URL_VALUE);
    }
    
    private VolumeMountBuilder buildCertsVolumeMount() {
        return new VolumeMountBuilder()
                .withMountPath(CERTS_MOUNT_PATH)
                .withName(CERTS_VOLUME_NAME)
                .withReadOnly(false);
    }
    
    private List<io.fabric8.kubernetes.api.model.Volume> buildVolumes() {
        return List.of(
                new VolumeBuilder()
                        .withName(CERTS_VOLUME_NAME)
                        .withSecret(new SecretVolumeSourceBuilder()
                                .withDefaultMode(420)
                                .withItems(
                                        new KeyToPathBuilder()
                                                .withKey("keystore")
                                                .withPath("client.keystore.p12")
                                                .build(),
                                        new KeyToPathBuilder()
                                                .withKey("trustore")
                                                .withPath("client.truststore.jks")
                                                .build()
                                )
                                .withOptional(false)
                                .withSecretName(KEYSTORE_SECRET_NAME)
                                .build())
                        .build()
        );
    }
    
    private Trigger buildKnativeTrigger(ReconciliationContext ctx, 
                                       io.fabric8.kubernetes.api.model.OwnerReference ownerRef) {
        var kRef = new KReferenceBuilder()
                .withApiVersion(KNATIVE_SERVING_API)
                .withKind(KNATIVE_SERVICE_KIND)
                .withName(ctx.serviceName)
                .build();

        var destination = new DestinationBuilder()
                .withRef(kRef)
                .build();

        var filter = new TriggerFilterBuilder()
                .withAttributes(Map.of(TARGET_AGENT_FILTER, ctx.name))
                .build();

        return new TriggerBuilder()
                .withNewMetadata()
                    .withName(ctx.triggerName)
                    .withNamespace(ctx.namespace)
                    .addToOwnerReferences(ownerRef)
                .endMetadata()
                .withNewSpec()
                    .withBroker(BROKER_NAME)
                    .withFilter(filter)
                    .withSubscriber(destination)
                .endSpec()
                .build();
    }
    
    private void storeMetadataInRedis(ReconciliationContext ctx) {
        try {
            String key = buildRedisKey(ctx);
            String value = buildRedisValue(ctx);
            redisDataSource.value(String.class).set(key, value);
            log.infof("Wrote metadata to Redis key=%s", key);
        } catch (Exception ex) {
            log.warnf(ex, "Failed to write agent metadata to Redis for %s/%s", ctx.namespace, ctx.name);
        }
    }
    
    private String buildRedisKey(ReconciliationContext ctx) {
        return REDIS_KEY_PREFIX + ctx.namespace + ":" + ctx.name;
    }
    
    private String buildRedisValue(ReconciliationContext ctx) {
        String description = ctx.spec != null ? ctx.spec.getDescription() : null;
        String escapedDescription = description != null ? description.replace("\"", "\\\"") : "";
        return String.format("{\"name\":\"%s\",\"description\":\"%s\"}", ctx.name, escapedDescription);
    }
    
    private GenericAgentStatus buildStatus(String state, ReconciliationContext ctx, String image) {
        GenericAgentStatus status = new GenericAgentStatus();
        status.setState(state);
        status.setMessage(String.format("Reconciled at %s with spec=%s, service=%s, trigger=%s", 
                Instant.now(), ctx.spec, ctx.serviceName, ctx.triggerName));
        return status;
    }
    
    private UpdateControl<GenericAgent> updateStatusIfChanged(GenericAgent resource, 
                                                              GenericAgentStatus desiredStatus) {
        GenericAgentStatus currentStatus = resource.getStatus();
        
        if (currentStatus == null || !desiredStatus.toString().equals(currentStatus.toString())) {
            resource.setStatus(desiredStatus);
            log.infof("Updating status for %s", resource.getMetadata().getName());
            return UpdateControl.patchStatus(resource);
        }
        
        return UpdateControl.noUpdate();
    }

    private boolean cleanupRedisKey(String ns, String name) {
        try {
            String key = buildRedisKeyForCleanup(ns, name);
            redisDataSource.key().del(key);
            log.infof("Deleted Redis key %s for %s/%s", key, ns, name);
            return true;
        } catch (Exception e) {
            log.warnf(e, "Failed to delete Redis key for %s/%s", ns, name);
            return false;
        }
    }
    
    private String buildRedisKeyForCleanup(String ns, String name) {
        return REDIS_KEY_PREFIX + ns + ":" + name;
    }
    
    /**
     * Chooses the image based on the agent class name.
     * If no class name is provided, uses the default base image.
     * Otherwise, derives the image name from the simple class name.
     */
    private String chooseImage(String agentClassName) {
        if (agentClassName == null || agentClassName.isBlank()) {
            return DEFAULT_IMAGE;
        }
        String simpleClassName = extractSimpleClassName(agentClassName);
        String sanitizedName = sanitizeImageName(simpleClassName);
        return IMAGE_REGISTRY + sanitizedName + IMAGE_TAG;
    }
    
    private String extractSimpleClassName(String fullyQualifiedName) {
        if (!fullyQualifiedName.contains(".")) {
            return fullyQualifiedName;
        }
        return fullyQualifiedName.substring(fullyQualifiedName.lastIndexOf('.') + 1);
    }
    
    private String sanitizeImageName(String name) {
        return name.replaceAll("[^A-Za-z0-9_-]", "").toLowerCase();
    }

    @Override
    public DeleteControl cleanup(GenericAgent resource, Context<GenericAgent> context) throws Exception {
        CleanupContext ctx = new CleanupContext(resource);
        log.infof("Running cleanup for GenericAgent %s/%s", ctx.namespace, ctx.name);

        if (!cleanupRedisKey(ctx.namespace, ctx.name)) {
            log.warnf("Redis cleanup failed for %s/%s; retrying later", ctx.namespace, ctx.name);
            return DeleteControl.noFinalizerRemoval();
        }

        return removeFinalizerFromResource(ctx);
    }
    
    private DeleteControl removeFinalizerFromResource(CleanupContext ctx) {
        try {
            client.resource(ctx.resource).inNamespace(ctx.namespace).edit(r -> {
                ObjectMeta md = r.getMetadata();
                if (md != null) {
                    List<String> finals = md.getFinalizers();
                    if (finals != null) {
                        finals.remove(REDIS_FINALIZER);
                        md.setFinalizers(finals.isEmpty() ? null : finals);
                    }
                    md.setManagedFields(null);
                    r.setMetadata(md);
                }
                return r;
            });
            log.infof("Removed finalizer %s for %s/%s via direct edit in cleanup", REDIS_FINALIZER, ctx.namespace, ctx.name);
            return DeleteControl.defaultDelete();
        } catch (Exception ex) {
            log.warnf(ex, "Direct edit to remove finalizer failed for %s/%s in cleanup; letting operator remove finalizer", ctx.namespace, ctx.name);
            return DeleteControl.defaultDelete();
        }
    }
    
    /**
     * Helper class to encapsulate reconciliation context
     */
    private class ReconciliationContext {
        final GenericAgent resource;
        final String namespace;
        final String name;
        final GenericAgentSpec spec;
        final String serviceName;
        final String triggerName;
        
        ReconciliationContext(GenericAgent resource) {
            this.resource = resource;
            ObjectMeta metadata = resource.getMetadata();
            this.namespace = metadata != null && metadata.getNamespace() != null 
                ? metadata.getNamespace() 
                : DEFAULT_NAMESPACE;
            this.name = metadata != null && metadata.getName() != null 
                ? metadata.getName() 
                : UNKNOWN_NAME;
            this.spec = resource.getSpec();
            this.serviceName = name + SERVICE_SUFFIX;
            this.triggerName = name + TRIGGER_SUFFIX;
        }
    }
    
    /**
     * Helper class to encapsulate cleanup context
     */
    private class CleanupContext {
        final GenericAgent resource;
        final String namespace;
        final String name;
        
        CleanupContext(GenericAgent resource) {
            this.resource = resource;
            ObjectMeta metadata = resource.getMetadata();
            this.namespace = metadata != null && metadata.getNamespace() != null 
                ? metadata.getNamespace() 
                : DEFAULT_NAMESPACE;
            this.name = metadata != null && metadata.getName() != null 
                ? metadata.getName() 
                : UNKNOWN_NAME;
        }
    }
}
