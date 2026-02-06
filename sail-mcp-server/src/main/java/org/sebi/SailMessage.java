package org.sebi;

import java.util.Map;

public class SailMessage {

    private String payload;

    private String from;

    private String to;

    private Map<String, Object> inputs;

    public SailMessage(String payload, String from, String to, Map<String, Object> inputs) {
        this.payload = payload;
        this.from = from;
        this.to = to;
        this.inputs = inputs;
    }

    public SailMessage() {
      
    }
    public Map<String, Object> getInputs() {
        return inputs;
    }
    public void setInputs(Map<String, Object> inputs) {
        this.inputs = inputs;
    }
    public String getPayload() {
        return payload;
    }
    
    public String getFrom() {
        return from;
    }
    
    public String getTo() {
        return to;  
    }

    public void setPayload(String payload) {
        this.payload = payload;
    }
    public void setFrom(String from) {
        this.from = from;
    }
    public void setTo(String to) {
        this.to = to;
    }

    public static SailMessage fromJSON(String json) {
      //using jackson
      try {
        com.fasterxml.jackson.databind.ObjectMapper mapper = new com.fasterxml.jackson.databind.ObjectMapper();
        return mapper.readValue(json, SailMessage.class);
      } catch (Exception e) {
        e.printStackTrace();
        return null;            
    }
    }

}
