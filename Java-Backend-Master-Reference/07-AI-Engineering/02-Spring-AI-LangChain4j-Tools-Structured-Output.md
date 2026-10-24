# 7.2 · Spring AI 2.0 and LangChain4j 1.22 — Prompt Templates, Structured Output, Tool Calling, Memory (What They Really Send)

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** Spring AI 2.0 reference (ChatClient, Advisors, Structured Output, Tool Calling, Chat Memory, Anthropic); LangChain4j 1.22 docs (AI Services, Tools, Chat Memory, Structured Outputs, Anthropic); the Spring AI Anthropic auto-configuration metadata (2.0.2).
> **Verified stack:** Spring AI **2.0.2** (`spring-ai-client-chat`, `spring-ai-anthropic`, which uses the official `anthropic-java` **2.72.0** underneath), LangChain4j **1.22.0** (`langchain4j-anthropic`, its own HTTP client), JDK 25. **Method:** both frameworks were pointed at a **local scripted mock of the Messages API** (the `HttpServer` stub from [7.1](01-Claude-API-Java-SDK.md)). Every behaviour below is what the framework **actually sent over HTTP**, captured request by request: no API key, no cost, deterministic.

---

## 1. Why a framework, and what it costs you 🔥

| | Official SDK (`anthropic-java` 3.x) | Spring AI 2.0 | LangChain4j 1.22 |
|---|---|---|---|
| Programming model | Typed request builders | `ChatClient` fluent API + **advisors** (interceptor chain) | **AI Services**: annotate an interface; LangChain4j implements it |
| Prompt templates | Your code | StringTemplate `{var}` | Mustache-style `{{var}}`, `@SystemMessage`, `@UserMessage`, `@V` |
| Structured output | `outputConfig(Class)` → native JSON Schema | `.entity(Class)`, prompt-based by default (§2) | Return a record or POJO, prompt-based by default (§3) |
| Tools | `BetaToolRunner` + annotated classes | `@Tool` methods; `ToolCallingManager` runs the loop | `@Tool` methods; AI Service runs the loop |
| Memory | Your code (or server-side threads) | `ChatMemory` + `MessageChatMemoryAdvisor` | `ChatMemory` / `@MemoryId` |
| Ecosystem | Claude only | Vector stores, RAG advisors, MCP, observability (Micrometer), Boot starters | Very broad integrations (stores, loaders, tools), agents, RAG |
| Newest Claude features | **Immediately** (effort, fallbacks, threads, MCP connector) | When Spring AI adopts them | When LangChain4j adds them |
| `anthropic-version` sent (verified) | `2026-10-21` (3.x) | `2023-06-01` | `2023-06-01` |

**Rule of thumb:** use a framework for the plumbing it does well (memory, RAG pipelines, vector stores, observability, Boot configuration), and check **what it puts on the wire** for anything that affects correctness: structured output, tool schemas and memory scope. The sections below show three places where the defaults surprise.

---

## 2. Spring AI 2.0 on the wire 🔥

### 2.1 Runnable: template, `entity()` two ways, `@Tool`, memory

<!-- run: javac cp=@p7 timeout=200 -->
```java
package demo.springai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.springframework.ai.anthropic.AnthropicChatModel;
import org.springframework.ai.anthropic.AnthropicChatOptions;
import org.springframework.ai.chat.client.AdvisorParams;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;

public class SpringAiOnTheWire {
    public record Itinerary(String city, int days, List<String> stops) { }

    public static class WeatherTools {
        @Tool(description = "Current weather for a city. Call it whenever the user asks about weather or what to pack.")
        public String currentWeather(@ToolParam(description = "City name") String city) {
            return "{\"city\":\"" + city + "\",\"tempC\":14,\"conditions\":\"light rain\"}";
        }
    }

    static final ObjectMapper JSON = new ObjectMapper();
    static final List<JsonNode> requests = new ArrayList<>();
    static final List<String> versions = new ArrayList<>();

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        HttpServer server = scriptedModel();
        AnthropicChatModel model = AnthropicChatModel.builder()
            .options(AnthropicChatOptions.builder()
                .baseUrl("http://127.0.0.1:" + server.getAddress().getPort())
                .apiKey("sk-ant-demo")
                .model("claude-opus-5-5")
                .maxTokens(4096)
                .build())
            .build();
        ChatClient chat = ChatClient.builder(model)
            .defaultSystem("You are a concise travel assistant.")
            .build();
        try {
            // 1. prompt template with parameters
            String text = chat.prompt().user(u -> u.text("Suggest one museum in {city} for a {interest} fan.")
                .param("city", "Paris").param("interest", "impressionism")).call().content();
            show("1. template", text);

            // 2. structured output into a record
            Itinerary plan = chat.prompt().user("Plan two days in Paris.").call().entity(Itinerary.class);
            show("2. entity(Itinerary)", String.valueOf(plan));
            Itinerary nativePlan = chat.prompt().user("Plan two days in Paris.")
                .advisors(AdvisorParams.ENABLE_NATIVE_STRUCTURED_OUTPUT).call().entity(Itinerary.class);
            show("2b. entity + ENABLE_NATIVE_STRUCTURED_OUTPUT", String.valueOf(nativePlan));
            System.out.println("    output_config sent: " + requests.getLast().get("output_config"));

            // 3. tool calling: Spring AI runs the tool and loops
            String answer = chat.prompt().user("Do I need a raincoat in Paris?").tools(new WeatherTools()).call().content();
            show("3. @Tool", answer);
            System.out.println("    tool definition sent: " + requests.get(seen - 1).get("tools").get(0));

            // 4. conversation memory as an advisor
            var memory = MessageWindowChatMemory.builder().maxMessages(10).build();
            ChatClient withMemory = chat.mutate().defaultAdvisors(MessageChatMemoryAdvisor.builder(memory).build()).build();
            withMemory.prompt().user("My name is Ada.").advisors(a -> a.param(ChatMemory.CONVERSATION_ID, "user-42")).call().content();
            String recalled = withMemory.prompt().user("What is my name?").advisors(a -> a.param(ChatMemory.CONVERSATION_ID, "user-42")).call().content();
            show("4. memory (conversation user-42)", recalled);
        } finally {
            server.stop(0);
        }
    }

    static int seen = 0;
    static void show(String label, String result) {
        System.out.println(label + " → " + result);
        for (; seen < requests.size(); seen++) {
            JsonNode r = requests.get(seen);
            List<String> keys = new ArrayList<>(); r.fieldNames().forEachRemaining(keys::add);
            System.out.println("   request " + (seen + 1) + " (anthropic-version " + versions.get(seen) + "): keys=" + keys
                + " | messages=" + roles(r.get("messages")) + " | last user text: " + lastUserText(r));
        }
    }
    static List<String> roles(JsonNode msgs) {
        List<String> out = new ArrayList<>();
        for (JsonNode m : msgs) {
            JsonNode c = m.get("content");
            String kind = c.isArray() ? c.findValuesAsText("type").toString() : "text";
            out.add(m.get("role").asText() + kind);
        }
        return out;
    }
    static String lastUserText(JsonNode r) {
        JsonNode last = r.get("messages").get(r.get("messages").size() - 1);
        String t = last.get("content").isArray() ? last.get("content").findValuesAsText("text").toString() : last.get("content").asText();
        t = t.replaceAll("\\s+", " ");
        return t.length() > 160 ? t.substring(0, 160) + "…" : t;
    }

    /** Scripted "model": tool_use when tools are offered, JSON when a schema is requested, text otherwise. */
    static HttpServer scriptedModel() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v1/messages", ex -> {
            JsonNode req = JSON.readTree(ex.getRequestBody());
            requests.add(req);
            versions.add(ex.getRequestHeaders().getFirst("anthropic-version"));
            String all = req.toString();
            String content;
            String stop = "end_turn";
            if (req.has("tools") && !all.contains("\"tool_result\"")) {
                content = "{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"" + req.get("tools").get(0).get("name").asText()
                    + "\",\"input\":{\"city\":\"Paris\"}}";
                stop = "tool_use";
            } else if (all.contains("\"tool_result\"")) {
                content = text("14°C and light rain: take a raincoat.");
            } else if (all.contains("JSON") || all.contains("output_config")) {
                content = text("{\"city\":\"Paris\",\"days\":2,\"stops\":[\"Louvre\",\"Musée d'Orsay\"]}");
            } else if (all.contains("What is my name")) {
                content = text(all.contains("Ada") ? "Your name is Ada." : "I don't know.");
            } else {
                content = text("Musée d'Orsay.");
            }
            byte[] out = ("{\"id\":\"msg_" + requests.size() + "\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-opus-5-5\","
                + "\"content\":[" + content + "],\"stop_reason\":\"" + stop + "\",\"stop_sequence\":null,"
                + "\"usage\":{\"input_tokens\":100,\"output_tokens\":20}}").getBytes(StandardCharsets.UTF_8);
            ex.getResponseHeaders().add("content-type", "application/json");
            ex.sendResponseHeaders(200, out.length);
            ex.getResponseBody().write(out);
            ex.close();
        });
        server.start();
        return server;
    }
    static String text(String t) { try { return "{\"type\":\"text\",\"text\":" + JSON.writeValueAsString(t) + "}"; } catch (Exception e) { throw new RuntimeException(e); } }
}
```

Output (verified):

```
1. template → Musée d'Orsay.
   request 1 (anthropic-version 2023-06-01): keys=[max_tokens, messages, model, system] | messages=[usertext] | last user text: Suggest one museum in Paris for a impressionism fan.
2. entity(Itinerary) → Itinerary[city=Paris, days=2, stops=[Louvre, Musée d'Orsay]]
   request 2 (anthropic-version 2023-06-01): keys=[max_tokens, messages, model, system] | messages=[usertext] | last user text: Plan two days in Paris. Your response should be in JSON format. Do not include any explanations, only provide a RFC8259 compliant JSON response following this f…
2b. entity + ENABLE_NATIVE_STRUCTURED_OUTPUT → Itinerary[city=Paris, days=2, stops=[Louvre, Musée d'Orsay]]
   request 3 (anthropic-version 2023-06-01): keys=[max_tokens, messages, model, output_config, system] | messages=[usertext] | last user text: Plan two days in Paris.
    output_config sent: {"format":{"schema":{"type":"object","properties":{"city":{"type":"string"},"days":{"type":"integer","format":"int32"},"stops":{"type":"array","items":{"type":"string"}}},"required":["city","days","stops"],"additionalProperties":false},"type":"json_schema"}}
3. @Tool → 14°C and light rain: take a raincoat.
   request 4 (anthropic-version 2023-06-01): keys=[max_tokens, messages, model, system, tools] | messages=[usertext] | last user text: Do I need a raincoat in Paris?
   request 5 (anthropic-version 2023-06-01): keys=[max_tokens, messages, model, system, tools] | messages=[usertext, assistant[tool_use], user[tool_result]] | last user text: []
    tool definition sent: {"input_schema":{"type":"object","properties":{"city":{"type":"string","description":"City name"}},"required":["city"]},"name":"currentWeather","description":"Current weather for a city. Call it whenever the user asks about weather or what to pack."}
4. memory (conversation user-42) → Your name is Ada.
   request 6 (anthropic-version 2023-06-01): keys=[max_tokens, messages, model, system] | messages=[usertext] | last user text: My name is Ada.
   request 7 (anthropic-version 2023-06-01): keys=[max_tokens, messages, model, system] | messages=[usertext, assistanttext, usertext] | last user text: What is my name?
```

* **Templates:** `u.text("… {city} … {interest} …").param(…)` is rendered by **StringTemplate** before sending. Literal braces in a template, such as a JSON example in a system prompt, must be escaped, or rendering fails. Never put raw user input into the **system** prompt; keep it in the user turn, delimited.
* **`entity(Itinerary.class)` is prompt-based by default:** Spring AI appended *"Your response should be in JSON format. Do not include any explanations, only provide a RFC8259 compliant JSON response following this format…"* to the user message and parsed the text. Nothing on the API side guarantees the shape.
* **`.advisors(AdvisorParams.ENABLE_NATIVE_STRUCTURED_OUTPUT)`** sends a real **`output_config.format` JSON Schema** (Claude's structured outputs), so the response is constrained to the schema. Prefer it. Note the generated schema carries `"format": "int32"` on integers; Claude's documented supported `format` values are **string** formats (date-time, email, uuid, …). The mock can't tell you whether the API ignores or rejects it, so test against the real API once, or provide your own schema (`outputSchema(…)` on `AnthropicChatOptions`). `StructuredOutputValidationAdvisor` adds validate-and-retry on top.
* **Tools:** the `@Tool` method became a tool named **`currentWeather`** (the method name) **without** `strict` or `additionalProperties: false`. Spring AI executed it and sent the full history back (`user`, `assistant[tool_use]`, `user[tool_result]`). Tool descriptions are prompts: say *when* to call the tool.
* **Memory needs an explicit conversation ID in 2.0:** calling `MessageChatMemoryAdvisor` without one failed with `IllegalArgumentException: conversationId cannot be null` (the first version of this demo hit exactly that). Pass `a.param(ChatMemory.CONVERSATION_ID, userOrSessionId)`. With it, the second call carried the prior turns. Scope the ID to user **and** conversation, never to a shared constant.
* **No sampling parameters were sent** (`max_tokens`, `messages`, `model`, `system` only). Keep it that way: don't set `spring.ai.anthropic.chat.options.temperature`. Models ≥ 4.7 only accept the default, and API version 2026-10-21 rejects the field outright ([7.1 §5](01-Claude-API-Java-SDK.md#5-api-version-2026-10-21-and-the-java-framework-landscape-)).

Spring Boot configuration (`spring-ai-starter-model-anthropic` 2.0.2; property names from its configuration metadata):

```yaml
spring:
  ai:
    anthropic:
      api-key: ${ANTHROPIC_API_KEY}
      timeout: 120s
      max-retries: 2
      chat:
        options:
          model: claude-opus-5-5
          max-tokens: 16000
          # no temperature / top-p / top-k (see above)
```

---

## 3. LangChain4j 1.22 on the wire 🔥

### 3.1 Runnable: an AI Service with a template, a record return type, a tool, and per-user memory

<!-- run: javac cp=@p7 timeout=200 -->
```java
package demo.lc4j;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import dev.langchain4j.agent.tool.P;
import dev.langchain4j.agent.tool.Tool;
import dev.langchain4j.memory.chat.MessageWindowChatMemory;
import dev.langchain4j.model.anthropic.AnthropicChatModel;
import dev.langchain4j.model.chat.Capability;
import dev.langchain4j.service.*;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class LangChain4jOnTheWire {
    public record Itinerary(String city, int days, List<String> stops) { }

    interface TravelAssistant {
        @SystemMessage("You are a concise travel assistant.")
        @UserMessage("Suggest one museum in {{city}} for a {{interest}} fan.")
        String museum(@V("city") String city, @V("interest") String interest);

        Itinerary plan(@UserMessage String request);                        // structured output from the return type

        String chat(@MemoryId String userId, @UserMessage String message);   // one memory per user
    }

    public static class WeatherTools {
        @Tool("Current weather for a city. Call it whenever the user asks about weather or what to pack.")
        public String currentWeather(@P("City name") String city) {
            return "{\"city\":\"" + city + "\",\"tempC\":14,\"conditions\":\"light rain\"}";
        }
    }

    static final ObjectMapper JSON = new ObjectMapper();
    static final List<JsonNode> requests = new ArrayList<>();
    static final List<String> versions = new ArrayList<>();

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        HttpServer server = scriptedModel();
        String base = "http://127.0.0.1:" + server.getAddress().getPort() + "/v1/";
        try {
            for (boolean nativeSchema : new boolean[] {false, true}) {
                var builder = AnthropicChatModel.builder().baseUrl(base).apiKey("sk-ant-demo")
                    .modelName("claude-opus-5-5").maxTokens(4096);
                if (nativeSchema) builder.supportedCapabilities(Capability.RESPONSE_FORMAT_JSON_SCHEMA);
                TravelAssistant assistant = AiServices.builder(TravelAssistant.class)
                    .chatModel(builder.build())
                    .tools(new WeatherTools())
                    .chatMemoryProvider(userId -> MessageWindowChatMemory.withMaxMessages(10))
                    .build();
                System.out.println("== supportedCapabilities(RESPONSE_FORMAT_JSON_SCHEMA): " + nativeSchema);
                requests.clear(); versions.clear(); seen = 0;
                if (!nativeSchema) {
                    show("1. template", assistant.museum("Paris", "impressionism"));
                }
                show("2. Itinerary return type", String.valueOf(assistant.plan("Plan two days in Paris.")));
                if (!nativeSchema) {
                    show("3. @Tool", assistant.chat("user-42", "Do I need a raincoat in Paris?"));
                    assistant.chat("user-7", "My name is Ada.");
                    show("4. @MemoryId user-7", assistant.chat("user-7", "What is my name?"));
                }
            }
        } finally {
            server.stop(0);
        }
    }

    static int seen;
    static void show(String label, String result) {
        System.out.println(label + " → " + result);
        for (; seen < requests.size(); seen++) {
            JsonNode r = requests.get(seen);
            List<String> keys = new ArrayList<>(); r.fieldNames().forEachRemaining(keys::add);
            List<String> msgs = new ArrayList<>();
            for (JsonNode m : r.get("messages")) msgs.add(m.get("role").asText() + m.get("content").findValuesAsText("type"));
            String lastText = String.join(" ", r.get("messages").get(r.get("messages").size() - 1).get("content").findValuesAsText("text")).replaceAll("\\s+", " ");
            System.out.println("   request " + (seen + 1) + " (anthropic-version " + versions.get(seen) + ", stream=" + r.get("stream") + ", tools=" + r.path("tools").size() + "): system=" + r.has("system") + " | messages=" + msgs
                + " | last user text: " + (lastText.length() > 140 ? lastText.substring(0, 140) + "…" : lastText));
            if (r.has("output_config")) System.out.println("     output_config: " + r.get("output_config"));
            if (r.has("tools") && seen == 2) System.out.println("     tool definition: " + r.get("tools").get(0));
        }
    }

    static HttpServer scriptedModel() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v1/messages", ex -> {
            JsonNode req = JSON.readTree(ex.getRequestBody());
            requests.add(req);
            versions.add(ex.getRequestHeaders().getFirst("anthropic-version"));
            String all = req.get("messages").toString() + req.path("output_config");
            String content, stop = "end_turn";
            if (all.contains("raincoat") && !all.contains("\"tool_result\"")) {
                content = "{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"" + req.get("tools").get(0).get("name").asText()
                    + "\",\"input\":{\"city\":\"Paris\"}}";
                stop = "tool_use";
            } else if (all.contains("\"tool_result\"")) content = text("14°C and light rain: take a raincoat.");
            else if (all.contains("Plan two days")) content = text("{\"city\":\"Paris\",\"days\":2,\"stops\":[\"Louvre\",\"Musée d'Orsay\"]}");
            else if (all.contains("What is my name")) content = text(all.contains("Ada") ? "Your name is Ada." : "I don't know.");
            else content = text(all.contains("museum") ? "Musée d'Orsay." : "Nice to meet you.");
            byte[] out = ("{\"id\":\"msg_" + requests.size() + "\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-opus-5-5\","
                + "\"content\":[" + content + "],\"stop_reason\":\"" + stop + "\",\"stop_sequence\":null,"
                + "\"usage\":{\"input_tokens\":100,\"output_tokens\":20}}").getBytes(StandardCharsets.UTF_8);
            ex.getResponseHeaders().add("content-type", "application/json");
            ex.sendResponseHeaders(200, out.length);
            ex.getResponseBody().write(out);
            ex.close();
        });
        server.start();
        return server;
    }
    static String text(String t) { try { return "{\"type\":\"text\",\"text\":" + JSON.writeValueAsString(t) + "}"; } catch (Exception e) { throw new RuntimeException(e); } }
}
```

Output (verified):

```
== supportedCapabilities(RESPONSE_FORMAT_JSON_SCHEMA): false
1. template → Musée d'Orsay.
   request 1 (anthropic-version 2023-06-01, stream=false, tools=1): system=true | messages=[user[text]] | last user text: Suggest one museum in Paris for a impressionism fan.
2. Itinerary return type → Itinerary[city=Paris, days=2, stops=[Louvre, Musée d'Orsay]]
   request 2 (anthropic-version 2023-06-01, stream=false, tools=1): system=true | messages=[user[text], assistant[text], user[text]] | last user text: Plan two days in Paris. You must answer strictly in the following JSON format: { "city": (type: string), "days": (type: integer), "stops": (…
3. @Tool → 14°C and light rain: take a raincoat.
   request 3 (anthropic-version 2023-06-01, stream=false, tools=1): system=false | messages=[user[text]] | last user text: Do I need a raincoat in Paris?
     tool definition: {"name":"currentWeather","description":"Current weather for a city. Call it whenever the user asks about weather or what to pack.","input_schema":{"type":"object","properties":{"city":{"type":"string","description":"City name"}},"required":["city"]}}
   request 4 (anthropic-version 2023-06-01, stream=false, tools=1): system=false | messages=[user[text], assistant[tool_use], user[tool_result]] | last user text:
4. @MemoryId user-7 → Your name is Ada.
   request 5 (anthropic-version 2023-06-01, stream=false, tools=1): system=false | messages=[user[text]] | last user text: My name is Ada.
   request 6 (anthropic-version 2023-06-01, stream=false, tools=1): system=false | messages=[user[text], assistant[text], user[text]] | last user text: What is my name?
== supportedCapabilities(RESPONSE_FORMAT_JSON_SCHEMA): true
2. Itinerary return type → Itinerary[city=Paris, days=2, stops=[Louvre, Musée d'Orsay]]
   request 1 (anthropic-version 2023-06-01, stream=false, tools=1): system=false | messages=[user[text]] | last user text: Plan two days in Paris.
     output_config: {"format":{"type":"json_schema","schema":{"type":"object","properties":{"city":{"type":"string"},"days":{"type":"integer"},"stops":{"type":"array","items":{"type":"string"}}},"required":[],"additionalProperties":false}}}
```

* **Memory leaked between methods.** With a `chatMemoryProvider` configured, every method **without `@MemoryId`** shares one default memory. `plan()` was sent the previous `museum()` exchange (`[user, assistant, user]` in request 2). Give every method that should be stateless its own service without memory, or an explicit `@MemoryId`. Methods with `@MemoryId` were isolated correctly (`user-42` vs `user-7`).
* **Every request carried the service's tools** (`tools=1` even for `museum()` and `plan()`). Tools cost input tokens on every call and invite unwanted tool calls. Split AI Services by capability.
* **Structured output is prompt-based by default** (*"You must answer strictly in the following JSON format: { "city": (type: string) …"*). Declaring `supportedCapabilities(Capability.RESPONSE_FORMAT_JSON_SCHEMA)` switches to native `output_config`. The generated schema has **`"required": []`**, so under native structured outputs the model may legally **omit every field**, and your record gets nulls or zeros. Validate the result, or supply a schema with `required`.
* **Tool definition:** named after the method (`currentWeather`), no `strict`. Enable `strictTools(true)` on the model builder for schema-guaranteed tool inputs.
* The model builder still exposes `temperature`, `topP`, `topK` and a `version(…)` override (default `2023-06-01`, verified). Leave sampling parameters unset.

---

## 4. Patterns that hold regardless of framework ⚡

| Concern | Do | Don't |
|---|---|---|
| Structured output | Native schema (`output_config`); validate business rules after parsing; check `stop_reason` (`max_tokens`/`refusal` mean a partial or empty object) | Rely on "respond in JSON" instructions for anything a program consumes |
| Tools | Small, well-described, idempotent tools; `strict` schemas; authorization inside the tool (the model is not a security boundary) | Give an agent a "run SQL" or "call any URL" tool |
| Memory | Scope by user + conversation; window or summarize; persist outside the JVM for multi-instance apps (`JdbcChatMemoryRepository`, Redis) | One global memory; unbounded windows (cost and latency grow every turn) |
| Prompt injection | Treat tool results and retrieved documents as **data**: delimit them, never let them change tool permissions, keep side-effecting tools behind confirmation | Let retrieved text instruct the model to call tools with user privileges |
| Cost and latency | Stable prefixes for prompt caching (system + tools first); stream long outputs; set `max_tokens` deliberately | Rebuild system prompts with timestamps per request |
| Observability | Spring AI emits Micrometer observations (`gen_ai.*`); log token usage per call; trace tool calls ([8.2](../08-Observability-Security-Testing/02-Observability-OpenTelemetry-Micrometer-Logging.md)) | Log full prompts containing personal data |

---

## 5. Production failure modes & diagnostics

| Symptom | Cause | Confirm with | Fix |
|---|---|---|---|
| `JsonParseException` / nulls in parsed records | Prompt-based structured output; `required: []` schemas; `max_tokens` truncation | Log the raw text and `stop_reason` | Native structured output with a correct schema; check stop reasons |
| A user sees another user's context | Shared or default memory ID | Memory keys in storage | Explicit IDs per user and conversation; per-request scoping |
| Bills grow over a conversation | Full history and all tools resent every turn | `usage.input_tokens` per turn | Window or summarize memory; prompt caching; fewer tools per service |
| Model calls tools at odd times | Tools attached to every method; vague descriptions | Tool-call logs | Split services; prescriptive descriptions ("Call this when…") |
| 400 after a framework upgrade | Sampling parameters sent under API 2026-10-21 | Error body names the field | Remove `temperature`/`top_p`/`top_k` from config |
| Template rendering exceptions | Unescaped braces in StringTemplate prompts | Stack trace from the template engine | Escape literal braces, or move examples into variables |
| `conversationId cannot be null` (Spring AI 2.0) | Memory advisor without an ID | Exception | Pass `ChatMemory.CONVERSATION_ID` |

---

## 6. Interview Q&A

<details><summary><b>Q1. 🔥 How does Spring AI's `.entity(MyRecord.class)` get structured data from Claude, and how do you make it reliable?</b></summary>

By default it appends JSON format instructions (from `BeanOutputConverter`) to the prompt and parses the reply text (verified on the wire). That is best-effort. Enable `AdvisorParams.ENABLE_NATIVE_STRUCTURED_OUTPUT` to send a JSON Schema in `output_config` (Claude's structured outputs), which constrains generation to the schema. Still check `stop_reason`, validate business rules, and review the generated schema (required fields, supported `format` values).
</details>

<details><summary><b>Q2. ⚡ What surprised you about LangChain4j AI Services' memory?</b></summary>

With a `chatMemoryProvider`, methods without `@MemoryId` share a default memory, so an unrelated method received a previous conversation (verified). Use explicit memory IDs, or separate services for stateless calls, and scope IDs per user and conversation.
</details>

<details><summary><b>Q3. 🔥 Walk through a tool-calling round trip as the framework executes it.</b></summary>

Request 1 carries `tools` (name, description, JSON Schema derived from the annotated method). The model returns `stop_reason=tool_use` with a `tool_use` block (id, name, input). The framework invokes the Java method, appends the assistant `tool_use` turn and a user `tool_result` turn (same id), and sends request 2 with the full history. The loop ends at `end_turn`. Production concerns: bound the iterations, return errors as `is_error` results, run independent calls in parallel (all results in one message), authorize inside tools, and log each call.
</details>

<details><summary><b>Q4. ⚡ When would you use the official SDK instead of Spring AI or LangChain4j?</b></summary>

When you need API features as soon as they ship (effort controls, refusal fallbacks, server-side message threads, MCP connector, newest beta tools), exact control over the request (caching breakpoints, strict schemas), or the newest API version (2026-10-21). Use the frameworks for Spring integration, RAG and vector-store plumbing, memory and observability, and verify their defaults on the wire.
</details>

<details><summary><b>Q5. 🧊 Why must you remove `temperature` from your Spring AI or LangChain4j configuration even though it works today?</b></summary>

Both frameworks currently send API version `2023-06-01` (verified), where sampling parameters are accepted (current models only honour the defaults). API version `2026-10-21` rejects `temperature`, `top_p` and `top_k` with a 400, even at default values. Once the frameworks move to SDK 3.x or the new version, configured sampling parameters break every request.
</details>
