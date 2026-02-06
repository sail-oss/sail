package org.sebi;

import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Spec for the GenericAgent CRD.
 */
public class GenericAgentSpec {

    @JsonProperty("agentClassName")
    private String agentClassName;

    @JsonProperty("systemMessage")
    private String systemMessage;

    @JsonProperty("userMessage")
    private String userMessage;

    @JsonProperty("useMemory")
    private boolean useMemory;

    @JsonProperty("description")
    private String description;

    public GenericAgentSpec() {
    }

    public GenericAgentSpec(String agentClassName, String systemMessage, String userMessage, boolean useMemory, String description) {
        this.agentClassName = agentClassName;
        this.systemMessage = systemMessage;
        this.userMessage = userMessage;
        this.useMemory = useMemory;
        this.description = description;
    }

    public String getAgentClassName() {
        return agentClassName;
    }

    public void setAgentClassName(String agentClassName) {
        this.agentClassName = agentClassName;
    }

    public String getSystemMessage() {
        return systemMessage;
    }

    public void setSystemMessage(String systemMessage) {
        this.systemMessage = systemMessage;
    }

    public String getUserMessage() {
        return userMessage;
    }

    public void setUserMessage(String userMessage) {
        this.userMessage = userMessage;
    }

    public boolean isUseMemory() {
        return useMemory;
    }

    public void setUseMemory(boolean useMemory) {
        this.useMemory = useMemory;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    @Override
    public String toString() {
        return "GenericAgentSpec{" +
                "agentClassName='" + agentClassName + '\'' +
                ", systemMessage='" + systemMessage + '\'' +
                ", userMessage='" + userMessage + '\'' +
                ", useMemory=" + useMemory +
                ", description='" + description + '\'' +
                '}';
    }
}
