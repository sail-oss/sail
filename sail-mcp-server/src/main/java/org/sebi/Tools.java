package org.sebi;

import java.util.Map;

import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;
import org.eclipse.microprofile.reactive.messaging.Message;

import io.quarkiverse.mcp.server.Tool;
import io.quarkus.logging.Log;
import io.smallrye.common.annotation.Blocking;
import io.smallrye.reactive.messaging.kafka.api.OutgoingKafkaRecordMetadata;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;

@Singleton
public class Tools {
    @Inject
    @Channel("agent-out")
    Emitter<SailMessage> emitter;

    @Tool(description = "sendMessage - Sends a message to another agent")
    @Blocking
    public String sendMessage(String payload, Map<String, Object> inputs,String from, String to) {
         OutgoingKafkaRecordMetadata<String> metadata =
                OutgoingKafkaRecordMetadata.<String>builder()
                        .withTopic("agents-messages")
                        .build();

        emitter.send(
                Message.of(new SailMessage(payload, from, to,inputs))
                       .addMetadata(metadata)
        );
        Log.infof("Sent message from %s to %s with payload: %s", from, to, payload);
        return "Message sent from " + from + " to " + to + " with payload: " + payload + " and inputs: " + inputs.toString();
    }

}
