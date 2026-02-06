package org.sebi;

import com.fasterxml.jackson.annotation.JsonInclude;

import io.fabric8.kubernetes.api.model.Namespaced;
import io.fabric8.kubernetes.client.CustomResource;
import io.fabric8.kubernetes.model.annotation.Group;
import io.fabric8.kubernetes.model.annotation.Version;
import io.fabric8.kubernetes.model.annotation.Kind;

/**
 * GenericAgent CustomResource.
 * <p>
 * Spec fields: agentClassName, systemMessage, userMessage, useMemory
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@Group("sebi.org")
@Version("v1")
@Kind("GenericAgent")
public class GenericAgent extends CustomResource<GenericAgentSpec, GenericAgentStatus> implements Namespaced{

    public GenericAgent() {
        super();
    }

    @Override
    public String toString() {
        return "GenericAgent{" +
                "apiVersion='" + getApiVersion() + '\'' +
                ", kind='" + getKind() + '\'' +
                ", metadata=" + getMetadata() +
                ", spec=" + getSpec() +
                ", status=" + getStatus() +
                '}';
    }
}
