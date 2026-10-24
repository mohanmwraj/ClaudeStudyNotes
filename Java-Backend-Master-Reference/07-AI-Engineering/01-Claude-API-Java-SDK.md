# 7.1 · The Claude API from Java — Models, Messages, Tools, Structured Output, Streaming, Caching (Official SDK 3.x)

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** Anthropic's Claude API skill reference (model table cached 2026-10-06; Java SDK guide); Claude Platform docs: "Migrating to API version 2026-10-21" (including its Java "SDK and CLI changes" section), MCP connector, structured outputs, tool use, streaming, prompt caching; `anthropic-sdk-java` CHANGELOG (3.0.0 = 2026-10-21, 3.2.0 "add support for message threads", 3.3.0 = 2026-10-23).
> **Verified stack:** `com.anthropic:anthropic-java` **3.3.0** (the latest; it sends API version **2026-10-21**), JDK 25. **No API key was used.** Every sample in this file talks to a **local mock of `POST /v1/messages`** written with the JDK's `HttpServer`, so the outputs show exactly what the SDK **sends** (headers, JSON) and how it **parses** responses, streams and errors, at zero cost and deterministically. The one sample that needs a real key is compile-checked only.

---

## 1. Models and the knobs that matter (October 2026) 🔥

| Model | ID | Context / max output | Input / output $ per 1M tokens | Use for |
|---|---|---|---|---|
| Claude Fable 5.1 | `claude-fable-5-1` | 1M / 128K | 10 / 50 | Hardest reasoning, long-horizon agents |
| **Claude Opus 5.5** | **`claude-opus-5-5`** | 1M / 128K | 4 / 20 | **Default** for capable work |
| Claude Sonnet 5.5 | `claude-sonnet-5-5` | 1M / 128K | 2 / 10 | Everyday coding, agents, enterprise workloads |
| Claude Haiku 5.5 | `claude-haiku-5-5` | 1M | 0.10 / 0.50 (≤100K-token prompts) | High-volume extraction, classification, sub-agents |

(Older models such as Opus 5, Opus 4.8, Sonnet 5 and Haiku 4.5 are still served. Query live capabilities with the Models API: `client.models().list()` / `retrieve(id)` expose `max_input_tokens`, `max_tokens` and `capabilities`. Prices change, so check the pricing page before quoting them.)

What changed for current models, and what Java code must respect:

* **Thinking is adaptive, not budgeted.** On Opus 5.5, thinking is always on: `{"type": "disabled"}` and `budget_tokens` return **400**. Control depth and cost with **`output_config.effort`** (`low` → `max`). **Opus 5.5 defaults to `medium`**, so set it explicitly. Thinking text is **omitted by default**; request `display: "summarized"` if you show reasoning to users.
* **Forced tool use is gone** on Opus 5.5, Sonnet 5.5 and Fable 5.1: `tool_choice` `any`/`tool` returns 400. Use `auto` plus an instruction, `strict: true` tools, or **structured outputs** when you only wanted JSON.
* **No assistant prefill** (400). Use structured outputs or system instructions instead.
* **`stop_reason` can be `refusal`** (HTTP 200), with `stop_details.category`. Always check `stop_reason` before trusting `content`. Server-side refusal **fallbacks** (`fallbacks: "default"`, beta `server-side-fallback-2026-07-01`) route a refused request to another model. The sample in §6 enables them.
* **API version `2026-10-21`** (SDK ≥ 3.0.0; verified in §2) **rejects `temperature`, `top_p` and `top_k` with a 400, even at default values.** It also rejects `document` blocks in `assistant` turns and `citations` on `user` text.

---

## 2. Anatomy of a request, captured on the wire 🔥

### 2.1 Runnable: structured output from a Java record, a cached system prompt, and the headers SDK 3.3 sends

<!-- run: javac cp=@p7sdk timeout=120 -->
```java
package demo.claude;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.JsonSchemaLocalValidation;
import com.anthropic.models.messages.*;
import com.fasterxml.jackson.annotation.JsonPropertyDescription;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;

public class WireFormat {
    /** A local stand-in for POST /v1/messages that records what the SDK sends. */
    static final List<Map<String, Object>> captured = new ArrayList<>();
    static HttpServer mock(String responseJson) throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v1/messages", exchange -> {
            Map<String, Object> req = new LinkedHashMap<>();
            req.put("anthropic-version", exchange.getRequestHeaders().getFirst("anthropic-version"));
            String auth = exchange.getRequestHeaders().getFirst("authorization");
            req.put("authorization", auth == null ? null : auth.replaceAll("Bearer .*", "Bearer <key>"));
            req.put("x-api-key", exchange.getRequestHeaders().getFirst("x-api-key"));
            req.put("body", new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            captured.add(req);
            byte[] out = responseJson.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("content-type", "application/json");
            exchange.sendResponseHeaders(200, out.length);
            exchange.getResponseBody().write(out);
            exchange.close();
        });
        server.start();
        return server;
    }

    public record Itinerary(
        @JsonPropertyDescription("City to visit") String city,
        @JsonPropertyDescription("Number of days, 1-14") int days,
        @JsonPropertyDescription("Places in visiting order") List<String> stops) { }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        String reply = """
            {"id":"msg_01","type":"message","role":"assistant","model":"claude-opus-5-5",
             "content":[{"type":"text","text":"{\\"city\\":\\"Paris\\",\\"days\\":2,\\"stops\\":[\\"Louvre\\",\\"Musée d'Orsay\\"]}"}],
             "stop_reason":"end_turn","stop_sequence":null,
             "usage":{"input_tokens":32,"output_tokens":41,"cache_creation_input_tokens":0,"cache_read_input_tokens":2048}}""";
        HttpServer server = mock(reply);
        AnthropicClient client = AnthropicOkHttpClient.builder()           // build once, share: it owns connection pools
            .apiKey("sk-ant-demo-not-a-real-key")
            .baseUrl("http://127.0.0.1:" + server.getAddress().getPort())
            .build();
        try {

            StructuredMessageCreateParams<Itinerary> params = MessageCreateParams.builder()
                .model("claude-opus-5-5")
                .maxTokens(16000L)
                .systemOfTextBlockParams(List.of(TextBlockParam.builder()
                    .text("You are a travel planner. <~2,000 tokens of stable instructions and examples>")
                    .cacheControl(CacheControlEphemeral.builder().build())        // cache the stable prefix
                    .build()))
                .outputConfig(Itinerary.class, JsonSchemaLocalValidation.YES)    // schema derived from the record
                .addUserMessage("Plan two days in Paris for an art lover.")
                .build();

            StructuredMessage<Itinerary> message = client.messages().create(params);
            Itinerary plan = message.content().stream().flatMap(b -> b.text().stream()).findFirst().orElseThrow().text();
            System.out.println("typed result: " + plan);
            System.out.println("stop_reason=" + message.stopReason().orElseThrow() + ", usage: input=" + message.usage().inputTokens()
                + " output=" + message.usage().outputTokens() + " cache_read=" + message.usage().cacheReadInputTokens().orElse(0L));

            Map<String, Object> sent = captured.getFirst();
            System.out.println("headers: anthropic-version=" + sent.get("anthropic-version") + ", authorization=" + sent.get("authorization")
                + ", x-api-key=" + sent.get("x-api-key"));
            ObjectMapper json = new ObjectMapper().enable(SerializationFeature.INDENT_OUTPUT);
            System.out.println("body:\n" + json.writeValueAsString(json.readTree((String) sent.get("body"))));
        } finally {
            client.close();                                                   // not AutoCloseable: close explicitly
            server.stop(0);
        }
    }
}
```

Output (verified):

```
typed result: Itinerary[city=Paris, days=2, stops=[Louvre, Musée d'Orsay]]
stop_reason=end_turn, usage: input=32 output=41 cache_read=2048
headers: anthropic-version=2026-10-21, authorization=Bearer <key>, x-api-key=null
body:
{
  "max_tokens" : 16000,
  "messages" : [ {
    "content" : "Plan two days in Paris for an art lover.",
    "role" : "user"
  } ],
  "model" : "claude-opus-5-5",
  "output_config" : {
    "format" : {
      "schema" : {
        "$schema" : "https://json-schema.org/draft/2020-12/schema",
        "type" : "object",
        "properties" : {
          "city" : {
            "type" : "string",
            "description" : "City to visit"
          },
          "days" : {
            "type" : "integer",
            "description" : "Number of days, 1-14"
          },
          "stops" : {
            "description" : "Places in visiting order",
            "type" : "array",
            "items" : {
              "type" : "string"
            }
          }
        },
        "required" : [ "city", "days", "stops" ],
        "additionalProperties" : false
      },
      "type" : "json_schema"
    }
  },
  "system" : [ {
    "text" : "You are a travel planner. <~2,000 tokens of stable instructions and examples>",
    "type" : "text",
    "cache_control" : {
      "type" : "ephemeral"
    }
  } ]
}
```

* **SDK 3.x sends `anthropic-version: 2026-10-21` and `Authorization: Bearer <key>`** (no `x-api-key`). Proxies, gateways or log filters that read `X-Api-Key` must change. A v3 client also holds **one** credential: setting both `apiKey` and `authToken` throws at `build()`.
* **`outputConfig(Itinerary.class, …)`** derived a strict JSON Schema from the record: draft 2020-12, `required` for every component, **`additionalProperties: false`**, and Jackson `@JsonPropertyDescription`s as `description`. The response text was parsed back into an `Itinerary`. Structured outputs **don't support numeric or length constraints** (`minimum`, `maxLength`, …), so constraints like "1–14" belong in the description, and you validate them yourself.
* **Prompt caching** is a prefix match over `tools` → `system` → `messages`. The `cache_control` breakpoint on the system block caches everything up to it. Verify hits with `usage.cache_read_input_tokens` (here the mock reported 2,048). Anything volatile (timestamps, user IDs) placed **before** the breakpoint silently disables caching. The minimum cacheable prefix is model-dependent (512–4,096 tokens).
* Build **one** `AnthropicClient` per application and share it (it owns connection pools). It is **not** `AutoCloseable` in 3.3, so call `close()` at shutdown.

---

## 3. Tool use and the agent loop 🔥

```
request (tools + messages) ──► model ──► stop_reason=tool_use, content=[text?, tool_use{id,name,input}…]
   ▲                                              │ your code runs each tool (in parallel if several)
   └──── user message: [tool_result{tool_use_id, content, is_error?}…]  (ALL results in ONE message)
loop until stop_reason=end_turn (also handle max_tokens, refusal, pause_turn)
```

### 3.1 Runnable: the SDK's `BetaToolRunner`, with and without server-side message threads

<!-- run: javac cp=@p7sdk timeout=120 -->
```java
package demo.claude;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.helpers.BetaToolRunner;
import com.anthropic.models.beta.messages.BetaMessage;
import com.anthropic.models.beta.messages.MessageCreateParams;
import com.anthropic.models.beta.messages.ToolRunnerCreateParams;
import com.fasterxml.jackson.annotation.JsonClassDescription;
import com.fasterxml.jackson.annotation.JsonPropertyDescription;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.function.Supplier;

public class ToolRunnerLoop {
    @JsonClassDescription("Get the current weather for a city. Call this whenever the user asks about weather or what to wear.")
    public static class GetWeather implements Supplier<String> {
        @JsonPropertyDescription("City name, e.g. Paris")
        public String city;
        @Override public String get() { return "{\"city\":\"" + city + "\",\"tempC\":14,\"conditions\":\"light rain\"}"; }
    }

    static final ObjectMapper JSON = new ObjectMapper();
    static final List<JsonNode> requests = new ArrayList<>();
    static final List<String> betaHeaders = new ArrayList<>();

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        HttpServer server = scriptedModel();
        AnthropicClient client = AnthropicOkHttpClient.builder().apiKey("sk-ant-demo")
            .baseUrl("http://127.0.0.1:" + server.getAddress().getPort()).build();
        try {
            MessageCreateParams params = MessageCreateParams.builder()
                .model("claude-opus-5-5")
                .maxTokens(16000L)
                .addTool(GetWeather.class)                                        // schema derived from the annotated class
                .addUserMessage("Do I need a raincoat in Paris today?")
                .build();

            for (boolean thread : new boolean[] {true, false}) {
                requests.clear(); betaHeaders.clear();
                BetaToolRunner runner = client.beta().messages().toolRunner(ToolRunnerCreateParams.builder()
                    .initialMessageParams(params).thread(thread).maxIterations(5).build());
                System.out.println("== tool runner, thread(" + thread + ")");
                for (BetaMessage m : runner) {                                     // one iteration per model response
                    System.out.println("   response: stop_reason=" + m.stopReason().orElseThrow() + ", blocks="
                        + m.content().stream().map(b -> b.isToolUse() ? "tool_use(" + b.asToolUse().name() + ")" : "text").toList());
                }
                for (int i = 0; i < requests.size(); i++) System.out.println("   request " + (i + 1) + ": " + summarize(requests.get(i), betaHeaders.get(i)));
            }
            System.out.println("tool definition sent: " + JSON.writeValueAsString(requests.getFirst().get("tools").get(0)));
        } finally {
            client.close();
            server.stop(0);
        }
    }

    static String summarize(JsonNode req, String beta) {
        List<String> msgs = new ArrayList<>();
        for (JsonNode m : req.get("messages")) {
            JsonNode c = m.get("content");
            List<String> types = new ArrayList<>();
            if (c.isArray()) c.forEach(b -> types.add(b.get("type").asText()));
            msgs.add(m.get("role").asText() + ":" + (c.isArray() ? types : "text"));
        }
        return "anthropic-beta=" + beta + ", thread=" + req.get("thread") + ", tools=" + (req.has("tools") ? "sent" : "absent") + ", messages=" + msgs;
    }

    static HttpServer scriptedModel() throws Exception {                          // 1st turn: call the tool; after a tool_result: answer
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v1/messages", exchange -> {
            JsonNode req = JSON.readTree(exchange.getRequestBody());
            requests.add(req);
            betaHeaders.add(String.valueOf(exchange.getRequestHeaders().getFirst("anthropic-beta")));
            boolean hasToolResult = req.get("messages").toString().contains("\"tool_result\"");
            String body = hasToolResult
                ? """
                  {"id":"msg_2","type":"message","role":"assistant","model":"claude-opus-5-5",
                   "content":[{"type":"text","text":"It's 14°C with light rain in Paris. Take a raincoat."}],
                   "stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":420,"output_tokens":18}}"""
                : """
                  {"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5",
                   "content":[{"type":"text","text":"Let me check the weather."},
                              {"type":"tool_use","id":"toolu_01","name":"get_weather","input":{"city":"Paris"}}],
                   "stop_reason":"tool_use","stop_sequence":null,"usage":{"input_tokens":380,"output_tokens":40}}""";
            byte[] out = body.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("content-type", "application/json");
            exchange.sendResponseHeaders(200, out.length);
            exchange.getResponseBody().write(out);
            exchange.close();
        });
        server.start();
        return server;
    }
}
```

Output (verified):

```
== tool runner, thread(true)
   response: stop_reason=tool_use, blocks=[text, tool_use(get_weather)]
   response: stop_reason=end_turn, blocks=[text]
   request 1: anthropic-beta=message-threads-2026-08-12, thread={"type":"create"}, tools=sent, messages=[user:text]
   request 2: anthropic-beta=message-threads-2026-08-12, thread={"previous_message_id":"msg_1","type":"continue"}, tools=absent, messages=[user:[tool_result]]
== tool runner, thread(false)
   response: stop_reason=tool_use, blocks=[text, tool_use(get_weather)]
   response: stop_reason=end_turn, blocks=[text]
   request 1: anthropic-beta=null, thread=null, tools=sent, messages=[user:text]
   request 2: anthropic-beta=null, thread=null, tools=sent, messages=[user:text, assistant:[text, tool_use], user:[tool_result]]
tool definition sent: {"input_schema":{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"city":{"type":"string","description":"City name, e.g. Paris"}},"required":["city"],"additionalProperties":false},"name":"get_weather","description":"Get the current weather for a city. Call this whenever the user asks about weather or what to wear.","strict":true}
```

* **The tool definition came from the class:** name `get_weather` (snake-cased from `GetWeather`), `description` from `@JsonClassDescription`, a strict schema, and **`"strict": true`** added by the SDK, so Claude's tool inputs are guaranteed to validate. Write descriptions that say **when** to call the tool ("Call this whenever…"). Recent models call tools more conservatively, and trigger conditions measurably raise the should-call rate.
* **SDK 3.3's tool runner uses server-side message threads by default.** The first request creates a thread (`thread: {"type":"create"}`, beta header `message-threads-2026-08-12`). Every later request sends **only the new `tool_result`** plus `thread: {"type":"continue","previous_message_id":"msg_1"}`. The conversation and tools are **not resent**. The feature arrived in Java SDK 3.2.0 (2026-10-23), and at the time of writing the public API reference doesn't yet document the `thread` parameter, so treat it as an early beta. Check retention and data-handling terms before relying on it in regulated workloads.
* **`ToolRunnerCreateParams.builder().thread(false)`** restores the classic, stateless loop: every request carries the full history (`user`, `assistant[text, tool_use]`, `user[tool_result]`) and the tools. Use it when a gateway must see full transcripts, or when you need to replay requests elsewhere.
* Production rules for any loop:
  * return **all** `tool_result`s of a turn in **one** user message (splitting them teaches the model to stop calling tools in parallel);
  * failures go back as `is_error: true` results, not exceptions;
  * bound the loop (`maxIterations`);
  * gate side-effecting tools behind validation or human approval;
  * check `max_tokens` and `refusal` stop reasons **before** executing a turn's tools.

---

## 4. Streaming and retries 🔥

Server-sent events of `POST /v1/messages` with `"stream": true`:

| Event | Carries |
|---|---|
| `message_start` | Message shell: id, model, initial `usage` (input tokens) |
| `content_block_start` | Block index and type: `text`, `thinking`, `tool_use`, server-tool blocks |
| `content_block_delta` | `text_delta`, `thinking_delta`, `signature_delta`, `input_json_delta` (partial tool input JSON) |
| `content_block_stop` | End of a block |
| `message_delta` | `stop_reason`, final `usage.output_tokens` |
| `message_stop` | End of the stream |
| `ping`, `error` | Keep-alive; mid-stream errors (e.g. `overloaded_error`) **after** HTTP 200 |

### 4.1 Runnable: parsing a stream with `MessageAccumulator`, and what the SDK retries

<!-- run: javac cp=@p7sdk timeout=120 -->
```java
package demo.claude;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.http.StreamResponse;
import com.anthropic.errors.*;
import com.anthropic.helpers.MessageAccumulator;
import com.anthropic.models.messages.*;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;

public class StreamingAndRetries {
    static final String SSE = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-opus-5-5","content":[],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":25,"output_tokens":1}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: ping
        data: {"type":"ping"}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Autumn rain falls soft"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" / on the quiet stone path"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" / a lantern flickers"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":17}}

        event: message_stop
        data: {"type":"message_stop"}

        """;

    static final Deque<int[]> script = new ArrayDeque<>();                  // {status, retry-after seconds} per request; empty = 200
    static final AtomicInteger attempts = new AtomicInteger();
    static final List<String> retryCountHeaders = new ArrayList<>();

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v1/messages", exchange -> {
            attempts.incrementAndGet();
            retryCountHeaders.add(exchange.getRequestHeaders().getFirst("x-stainless-retry-count"));
            String body = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
            int[] next = script.poll();
            if (next != null) {                                                  // scripted failure
                String type = switch (next[0]) { case 429 -> "rate_limit_error"; case 529 -> "overloaded_error"; default -> "invalid_request_error"; };
                byte[] err = ("{\"type\":\"error\",\"error\":{\"type\":\"" + type + "\",\"message\":\"scripted " + next[0] + "\"}}").getBytes();
                if (next[1] >= 0) exchange.getResponseHeaders().add("retry-after", String.valueOf(next[1]));
                exchange.sendResponseHeaders(next[0], err.length);
                exchange.getResponseBody().write(err);
            } else if (body.contains("\"stream\":true")) {
                byte[] out = SSE.getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().add("content-type", "text/event-stream");
                exchange.sendResponseHeaders(200, out.length);
                exchange.getResponseBody().write(out);
            } else {
                byte[] out = """
                    {"id":"msg_02","type":"message","role":"assistant","model":"claude-opus-5-5","content":[{"type":"text","text":"ok"}],
                     "stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":5,"output_tokens":1}}""".getBytes();
                exchange.getResponseHeaders().add("content-type", "application/json");
                exchange.sendResponseHeaders(200, out.length);
                exchange.getResponseBody().write(out);
            }
            exchange.close();
        });
        server.start();
        AnthropicClient client = AnthropicOkHttpClient.builder().apiKey("sk-ant-demo")
            .baseUrl("http://127.0.0.1:" + server.getAddress().getPort()).build();
        try {
            // 1. streaming: raw events in, a complete Message out
            MessageCreateParams params = MessageCreateParams.builder().model("claude-opus-5-5").maxTokens(64000L)
                .addUserMessage("Write a haiku about rain").build();
            MessageAccumulator accumulator = MessageAccumulator.create();
            List<String> events = new ArrayList<>();
            StringBuilder printed = new StringBuilder();
            try (StreamResponse<RawMessageStreamEvent> stream = client.messages().createStreaming(params)) {
                stream.stream().forEach(event -> {
                    accumulator.accumulate(event);
                    events.add(event.isMessageStart() ? "message_start" : event.isContentBlockStart() ? "content_block_start"
                        : event.isContentBlockDelta() ? "delta" : event.isContentBlockStop() ? "content_block_stop"
                        : event.isMessageDelta() ? "message_delta" : event.isMessageStop() ? "message_stop" : "other");
                    event.contentBlockDelta().flatMap(d -> d.delta().text()).ifPresent(t -> printed.append(t.text()));   // render as it arrives
                });
            }
            Message full = accumulator.message();
            System.out.println("1. events: " + events);
            System.out.println("   rendered incrementally: " + printed);
            System.out.println("   accumulated: stop_reason=" + full.stopReason().orElseThrow() + ", output_tokens=" + full.usage().outputTokens()
                + ", text equal=" + full.content().getFirst().asText().text().equals(printed.toString()));

            // 2. retries: 429 and 529 are retried (default maxRetries = 2), 400 is not
            for (int[][] scenario : new int[][][] {
                    {{429, 0}, {529, 0}},                      // two transient failures, then success
                    {{529, 0}, {529, 0}, {529, 0}},            // more failures than retries
                    {{400, -1}}}) {                            // a client error
                script.clear(); script.addAll(List.of(scenario)); attempts.set(0); retryCountHeaders.clear();
                String outcome;
                try { client.messages().create(MessageCreateParams.builder().model("claude-opus-5-5").maxTokens(16L).addUserMessage("hi").build()); outcome = "success"; }
                catch (AnthropicServiceException e) { outcome = e.getClass().getSimpleName() + " (status " + e.statusCode() + ")"; }
                System.out.printf("2. scripted %s → %s after %d attempt(s), x-stainless-retry-count=%s%n",
                    Arrays.stream(scenario).map(s -> String.valueOf(s[0])).toList(), outcome, attempts.get(), retryCountHeaders);
            }
        } finally {
            client.close();
            server.stop(0);
        }
    }
}
```

Output (verified):

```
1. events: [message_start, content_block_start, delta, delta, delta, content_block_stop, message_delta, message_stop]
   rendered incrementally: Autumn rain falls soft / on the quiet stone path / a lantern flickers
   accumulated: stop_reason=end_turn, output_tokens=17, text equal=true
2. scripted [429, 529] → success after 3 attempt(s), x-stainless-retry-count=[0, 1, 2]
2. scripted [529, 529, 529] → InternalServerException (status 529) after 3 attempt(s), x-stainless-retry-count=[0, 1, 2]
2. scripted [400] → BadRequestException (status 400) after 1 attempt(s), x-stainless-retry-count=[0]
```

* **The accumulator rebuilds the full `Message`** (stop reason, usage, text) from the events, so render deltas as they arrive and still get a final object to log or store. `ping` events are consumed by the SDK and never reach your code.
* **Retries are built in:** 429 and 5xx (here 529 overloaded) were retried twice by default, each attempt marked with `x-stainless-retry-count`. A 400 was **not** retried. With the defaults, a hard outage costs 3 attempts × your timeout before you see an exception, so set timeouts and `maxRetries` deliberately, and don't stack another retry layer on top ([6.4](../06-Spring-Microservices/04-Resilience4j-CircuitBreaker-RateLimiter-Bulkhead.md), retry amplification).
* **Errors after HTTP 200** arrive as an `error` event inside the stream. Long outputs must be streamed: the SDKs require streaming for large `max_tokens` (up to 128K) to avoid HTTP timeouts.

---

## 5. API version 2026-10-21 and the Java framework landscape ⚡

| Client | Version tested | `anthropic-version` sent (verified) | Notes |
|---|---|---|---|
| `anthropic-java` (official) | **3.3.0** | **`2026-10-21`** | `MessageParam` is now a per-role union (`MessageParam.ofUser(…)`); `addUserMessageOfContentBlockParams`; Bearer auth; one credential per client; Text Completions removed |
| `anthropic-java` used **inside Spring AI 2.0.2** | 2.72.0 (transitive) | `2023-06-01` (from the SDK's `AnthropicBackend`) | Spring AI options such as `temperature` still pass today, but will 400 once Spring AI moves to SDK 3.x |
| LangChain4j `langchain4j-anthropic` | 1.22.0 | `2023-06-01` (hard-coded in `AnthropicChatModel` and friends) | Own HTTP client, not the official SDK |

**Migration hazard for framework users:** both frameworks expose `temperature`, `topP` and `topK` options. On models from Claude 4.7 onward, only the defaults have ever been accepted. On API version 2026-10-21 **any** value fails. Remove sampling settings from configuration now (`spring.ai.anthropic.chat.options.temperature`, `AnthropicChatModel.builder().temperature(…)`) instead of discovering it at the next upgrade. File [7.2](02-Spring-AI-LangChain4j-Tools-Structured-Output.md) shows exactly what each framework puts on the wire.

---

## 6. A production-shaped call (compile-checked; needs a real key)

<!-- run: compile cp=@p7sdk -->
```java
import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.http.StreamResponse;
import com.anthropic.errors.*;
import com.anthropic.helpers.BetaMessageAccumulator;
import com.anthropic.models.beta.AnthropicBeta;
import com.anthropic.models.beta.messages.*;
import java.time.Duration;

public class LiveCall {
    public static void main(String[] args) {
        AnthropicClient client = AnthropicOkHttpClient.builder()
            .fromEnv()                                   // ANTHROPIC_API_KEY, or a profile from `ant auth login`
            .maxRetries(2)                               // default; retries 408/409/429/5xx and connection errors
            .timeout(Duration.ofMinutes(10))
            .build();
        try {
            MessageCreateParams params = MessageCreateParams.builder()
                .model("claude-opus-5-5")
                .maxTokens(64000L)                                          // streaming: give the model room
                .thinking(BetaThinkingConfigAdaptive.builder()
                    .display(BetaThinkingConfigAdaptive.Display.SUMMARIZED).build())   // default display is "omitted"
                .outputConfig(BetaOutputConfig.builder().effort(BetaOutputConfig.Effort.HIGH).build())   // Opus 5.5 default: medium
                .addBeta(AnthropicBeta.SERVER_SIDE_FALLBACK_2026_07_01)
                .fallbacksDefault()                                         // a refused request is retried on a fallback model
                .addUserMessage("Review this Kafka consumer configuration for delivery-semantics bugs: ...")
                .build();

            BetaMessageAccumulator accumulator = BetaMessageAccumulator.create();
            try (StreamResponse<BetaRawMessageStreamEvent> stream = client.beta().messages().createStreaming(params)) {
                stream.stream().forEach(event -> {
                    accumulator.accumulate(event);
                    event.contentBlockDelta().flatMap(d -> d.delta().text()).ifPresent(t -> System.out.print(t.text()));
                });
            }
            BetaMessage message = accumulator.message();
            switch (message.stopReason().map(Object::toString).orElse("")) {   // always check before trusting content
                case "refusal" -> message.stopDetails().ifPresent(d -> System.err.println("refused: " + d.category()));
                case "max_tokens" -> System.err.println("truncated: raise max_tokens or continue the turn");
                default -> { }
            }
        } catch (RateLimitException e) {                // 429 after the SDK's own retries
            System.err.println("rate limited: back off and queue the work");
        } catch (BadRequestException | UnprocessableEntityException e) {   // 400/422: a bug in the request, don't retry
            System.err.println("invalid request: " + e.getMessage());
        } catch (AnthropicServiceException e) {         // other HTTP statuses (401, 403, 404, 5xx after retries)
            System.err.println("API error " + e.statusCode());
        } catch (AnthropicIoException e) {              // network failures after retries
            System.err.println("network: " + e.getMessage());
        } finally {
            client.close();
        }
    }
}
```

This sample shows the defaults recommended for new code on Opus 5.5:

* adaptive thinking with summarized display;
* an explicit `effort`;
* **server-side refusal fallbacks enabled** (`fallbacksDefault()` + `SERVER_SIDE_FALLBACK_2026_07_01`; remove them if you never want a different model to answer);
* streaming with an accumulator;
* a stop-reason check;
* a most-specific-first exception chain (rate limit → invalid request → other HTTP → network).

**The MCP connector** (Claude calls a remote MCP server's tools server-side) is a beta on the same endpoint:

* `addMcpServer(BetaRequestMcpServerUrlDefinition…)` **and** `addTool(BetaMcpToolset…mcpServerName(…))`. Both are required, and a server without a toolset is a validation error.
* Beta `mcp-client-2025-11-20`. Its successor, `mcp-client-2026-09-15`, adds tool-list pinning via `mcp_tool_listing` blocks.
* Only **tools** are supported (no resources or prompts), and only **public HTTP** servers (Streamable HTTP or SSE, no stdio).
* It is not eligible for zero data retention.

Running MCP servers and clients yourself is covered in [7.3](03-MCP-Servers-and-Clients-in-Java.md).

---

## 7. Failure modes (Claude API integration)

| Symptom | Cause | Fix |
|---|---|---|
| `400` after upgrading to SDK 3.x | `temperature`/`top_p`/`top_k` sent (API 2026-10-21) | Remove them; models 4.7+ only ever accepted the defaults |
| `400` "not supported for this model" on `tool_choice` | Forced tool use on Opus 5.5 / Sonnet 5.5 / Fable 5.1 | `auto` + an instruction, `strict` tools, or structured outputs |
| `400` on thinking config | `budget_tokens` or `disabled` on Opus 5.5 | Adaptive only; tune `effort` |
| Answers "cut off" | `stop_reason=max_tokens` ignored | Check stop reasons; stream with a high `max_tokens` |
| Empty or partial structured output | `refusal` or `max_tokens` | Check `stop_reason` before parsing |
| Proxy rejects requests after the upgrade | The gateway reads `X-Api-Key`; SDK 3.x sends `Authorization: Bearer` | Update the gateway, or set `X-Api-Key` explicitly |
| Costs high, cache hits zero | Volatile data before the cache breakpoint; unsorted tool JSON; tools changing per request | Stable prefix first; check `cache_read_input_tokens` |
| Latency spikes under load | 429/529 retried silently by the SDK (3 attempts) plus your own retries | One retry layer; queue and back off; monitor `x-stainless-retry-count`/attempt metrics |
| Tool loops never end | No iteration bound; the model keeps calling a failing tool | `maxIterations`; return informative `is_error` results; stop on repeats |
| Gateway logs show only fragments of conversations | SDK 3.3 tool runner uses message threads (only new turns sent) | `thread(false)` where full transcripts are required |
