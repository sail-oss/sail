package org.sebi;

/**
 * Status for the GenericAgent CRD.
 * Kept minimal; extend as needed to report operator reconciliation status.
 */
public class GenericAgentStatus {

    private String state;
    private String message;

    public GenericAgentStatus() {
    }

    public GenericAgentStatus(String state, String message) {
        this.state = state;
        this.message = message;
    }

    public String getState() {
        return state;
    }

    public void setState(String state) {
        this.state = state;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    @Override
    public String toString() {
        return "GenericAgentStatus{" +
                "state='" + state + '\'' +
                ", message='" + message + '\'' +
                '}';
    }
}
