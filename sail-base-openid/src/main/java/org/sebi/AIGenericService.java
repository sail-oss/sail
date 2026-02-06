package org.sebi;

import dev.langchain4j.service.SystemMessage;
import dev.langchain4j.service.UserMessage;
import io.quarkiverse.langchain4j.RegisterAiService;
import io.quarkiverse.langchain4j.mcp.runtime.McpToolBox;

@RegisterAiService()
public interface AIGenericService {

    @McpToolBox()
    @UserMessage("{userMessage}")
    @SystemMessage("{systemMessage}")
    String callService(SailMessage sailMessage, String userMessage, String systemMessage);

}
