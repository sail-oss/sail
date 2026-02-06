package org.sebi;

import java.util.Map;

import org.eclipse.microprofile.config.inject.ConfigProperty;

import io.quarkus.logging.Log;
import io.quarkus.qute.Qute;
import jakarta.inject.Inject;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;

import jakarta.ws.rs.core.HttpHeaders;
import io.quarkus.redis.datasource.RedisDataSource;
import io.smallrye.common.annotation.Blocking;


@Path("/")
public class AgentResource {

    @ConfigProperty(name = "prompt.system")
    String systemMessage;

    @ConfigProperty(name = "prompt.user")
    String userMessage;

    @Inject
    AIGenericService genericService;

    @Inject
    RedisDataSource redisDataSource;

    @POST
    @Blocking
    public void message(String message, HttpHeaders headers) {   
         String id = headers.getHeaderString("Ce-Id");
        String type = headers.getHeaderString("Ce-Type");
        String source = headers.getHeaderString("Ce-Source");

        System.out.println("Received CloudEvent");
        System.out.println("ID     : " + id);
        System.out.println("Type   : " + type);
        System.out.println("Source : " + source);
        System.out.println("Custom: " + headers.getHeaderString("Ce-Mycustomfield"));
        System.out.println("Target: " + headers.getHeaderString("Ce-Targetagent"));
        System.out.println("Body   : " + message);
        String renderedUserMessage = Qute.fmt(userMessage, Map.of("sailMessage", SailMessage.fromJSON(message)));
        String renderedSystemMessage = Qute.fmt(systemMessage, Map.of("sailMessage", SailMessage.fromJSON(message)));
        Log.infof("Rendered User Message: %s", renderedUserMessage);
        Log.infof("Rendered System Message: %s", renderedSystemMessage);

        // Fetch all redis values for keys starting with "genericagent" and append to user message
        StringBuilder agentDataBuilder = new StringBuilder();
        try {
            var keys = redisDataSource.key().keys("genericagent*");
            if (keys != null) {
                for (String k : keys) {
                    try {
                        String v = redisDataSource.value(String.class).get(k);
                        if (v != null) {
                            agentDataBuilder.append(v).append("\n");
                        }
                    } catch (Exception e) {
                        Log.warnf(e, "Failed to fetch value for key %s", k);
                    }
                }
            }
        } catch (Exception e) {
            Log.warn("Failed to fetch agent data from Redis", e);
        }
        String agentData = agentDataBuilder.toString();
        if (!agentData.isBlank()) {
            renderedUserMessage = renderedUserMessage + "\n\nThose are the available agents:\n" + agentData;
        }
        Log.infof("Final User Message with Agent Data: %s", renderedUserMessage);
        genericService.callService(SailMessage.fromJSON(message), renderedUserMessage, renderedSystemMessage);
    }

}
