# 7.7 · Pillar 7 — Interview & Certification Question Bank (AI Engineering in Java)

> **Use:** A = flashcards, B = senior and architect scenarios, C = code questions with verified answers.
> **Exam scope:** no Oracle Java SE exam covers LLM integration. Section C is written in the same "what does this print?" style, about the APIs a Java backend engineer meets in practice: the official Anthropic SDK, LangChain4j and Spring AI. All questions are original. **Every program in C was run** (`anthropic-java` 3.3.0, LangChain4j 1.22.0, Spring AI 2.0.2, JDK 25), and none needs an API key.

---

## A. Rapid-fire

<details><summary><b>A1–A24</b></summary>

1. **Default model for capable work (Oct 2026)?** `claude-opus-5-5` (Sonnet 5.5 and Haiku 5.5 for cheaper routes).
2. **How do you control reasoning depth on Opus 5.5?** `output_config.effort` (`low`…`max`); thinking is always on, and `budget_tokens` returns 400. The default effort is `medium`.
3. **What does API version 2026-10-21 reject?** `temperature`/`top_p`/`top_k`, `document` blocks in assistant turns, and `citations` on user text.
4. **First Java SDK release on 2026-10-21?** `anthropic-java` 3.0.0 (3.3.0 latest at the time of writing).
5. **How does SDK 3.x send the API key?** `Authorization: Bearer` (not `X-Api-Key`).
6. **Which `anthropic-version` do Spring AI 2.0.2 and LangChain4j 1.22 send?** `2023-06-01` (verified).
7. **Forced `tool_choice` (`any`/`tool`) on Opus 5.5?** 400. Use `auto` + an instruction, `strict` tools, or structured outputs.
8. **Structured-output schema rules?** `additionalProperties: false`; no numeric or length constraints; no recursive schemas; only string `format`s.
9. **Prompt cache order?** `tools` → `system` → `messages`; a prefix match up to the breakpoint.
10. **How do you verify caching works?** `usage.cache_read_input_tokens` > 0 on repeated prefixes.
11. **Stop reasons to handle?** `end_turn`, `max_tokens`, `tool_use`, `pause_turn`, `refusal`, `stop_sequence`.
12. **Which statuses does the SDK retry by default, and how often?** 408/409/429/5xx and connection errors, 2 retries.
13. **Streaming event carrying partial tool input?** `content_block_delta` with `input_json_delta`.
14. **What does SDK 3.3's tool runner send on turn 2 by default?** Only new messages plus `thread: {type: continue, previous_message_id}` (message threads beta).
15. **Spring AI `.entity()` default mechanism?** Prompt-appended JSON instructions; native schema needs `ENABLE_NATIVE_STRUCTURED_OUTPUT`.
16. **LangChain4j memory pitfall?** Methods without `@MemoryId` share one default memory.
17. **MCP primitives and who controls them?** Tools (the model), resources (the application), prompts (the user).
18. **Latest MCP spec revision?** `2025-11-25`.
19. **MCP over HTTP: session header? Invalid Origin?** `Mcp-Session-Id`; 403.
20. **Where must a stdio MCP server log?** stderr (stdout is the protocol).
21. **MCP connector limits?** Tools only; public HTTP servers; no stdio; not ZDR-eligible.
22. **Why hybrid retrieval?** Vectors miss exact tokens and BM25 misses paraphrases (hit@5 10 → 13 of 14 in the measurement).
23. **What happens to text beyond an embedding model's window?** It is silently ignored (cosine 1.0 for texts differing only after it).
24. **What propagates a stream cancellation to the model?** Closing the HTTP connection (closing the SDK `StreamResponse`); Spring AI 2.0.2's stream didn't (verified).

</details>

---

## B. Senior scenarios

<details><summary><b>B1. 🔥 Design a customer-support assistant for an e-commerce Spring Boot platform (orders, refunds, policy questions).</b></summary>

* **Routes:** policy Q&A via RAG over policies (hybrid retrieval, tenant and locale filters, citations); order status and refund via tools.
* **Tools:**
  * `lookup_order` is read-only and authorized with the **end user's** identity;
  * `refund_order` is destructive, so it has hard limits and confirmation or human approval above a threshold, and errors come back as `is_error` results.
* **Model:** Opus 5.5 at `medium` or `high` effort, structured output for anything a program consumes, `stop_reason` checks, server-side refusal fallbacks.
* **Memory:** per user + conversation, windowed, persisted in Redis or JDBC.
* **Streaming:** SSE with a cancellable upstream, heartbeats, and buffering off at the ingress.
* **Cost:** a cached system + tools prefix, effort per route, `max_tokens` bounds.
* **Safety:** treat ticket text and documents as data; no exfiltration-capable tools in the same session as untrusted content.
* **Observability:** tokens, TTFT, stop reasons, tool calls, refusal rate, offline eval sets in CI.
</details>

<details><summary><b>B2. ⚡ Your Spring AI app must move to the new API version. What's your plan?</b></summary>

Inventory everything that sends sampling parameters (config, code, framework defaults) and remove them. Check gateways and log filters for `X-Api-Key` and switch them to `Authorization: Bearer`. Check history building for documents in assistant turns and citations in user text. Then upgrade (directly to SDK 3.x for raw calls; the Spring AI version that adopts it for the framework). Add a contract test against a mock that asserts headers and JSON, and run the evaluation suite before and after.
</details>

<details><summary><b>B3. ⚡ RAG quality complaints: "it can't find things". How do you debug?</b></summary>

Build a labelled set (questions → expected source passages). Measure hit@k and MRR for retrieval alone, separately from answer quality. Inspect chunking (sizes vs the embedding window, structure-aware splits), add BM25 hybrid retrieval and a re-ranker, check filters (are ACL filters reducing recall?), and review the embedding model (domain, language). Only then tune prompts. Track the metrics per deploy.
</details>

<details><summary><b>B4. 🔥 How do you make an LLM agent safe to call internal APIs?</b></summary>

Least privilege: tools act with the end user's permissions; authorization checks live inside tools, not in prompts. Validate arguments with strict schemas and business rules; require confirmation for destructive or irreversible actions; rate-limit and bound loops. Treat all model inputs from documents, tool results and MCP servers as untrusted; separate read-sensitive tools from network-egress tools; pin or review third-party MCP tool lists; audit-log every call with the user, arguments and result.
</details>

<details><summary><b>B5. 🧊 Official SDK, Spring AI, or LangChain4j for a new service?</b></summary>

Spring AI if the service is Spring Boot and needs vector stores, advisors, MCP starters and Micrometer observability with Boot configuration. LangChain4j if declarative AI Services and its integrations fit best. The official SDK where you need the newest API features or exact request control (threads, fallbacks, effort, MCP connector, API 2026-10-21), or to fix framework gaps such as stream cancellation. Mixing is fine: e.g. Spring AI for RAG plumbing and the SDK for a streaming endpoint. In all cases, verify the wire behaviour with a mock contract test.
</details>

---

## C. Code questions (verified)

### C1 — What schema does the SDK derive from a record?

<!-- run: cp=@p7sdk -->
```java
import com.anthropic.core.JsonSchemaLocalValidation;
import com.anthropic.core.ObjectMappers;
import com.anthropic.models.messages.MessageCreateParams;
import java.util.*;
import java.util.function.Supplier;

public class Schema01 {
    record Ticket(String title, Optional<String> assignee, int priority, List<String> tags) { }
    record Node(String name, List<Node> children) { }
    static class GetWeatherForecast implements Supplier<String> { public String city; public String get() { return "sunny"; } }

    public static void main(String[] args) {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        var json = ObjectMappers.jsonMapper();
        var params = MessageCreateParams.builder().model("claude-opus-5-5").maxTokens(1000L).addUserMessage("x")
            .outputConfig(Ticket.class, JsonSchemaLocalValidation.YES).build();
        var schema = json.valueToTree(params.outputConfig().orElseThrow()).get("format").get("schema");
        System.out.println(schema.get("required") + " " + schema.get("additionalProperties")
            + " assignee=" + schema.get("properties").get("assignee") + " priority=" + schema.get("properties").get("priority"));

        var tools = com.anthropic.models.beta.messages.MessageCreateParams.builder().model("claude-opus-5-5").maxTokens(1000L)
            .addUserMessage("x").addTool(GetWeatherForecast.class).build();
        System.out.println(json.valueToTree(tools.tools().orElseThrow().getFirst()).get("name"));

        try {
            MessageCreateParams.builder().model("claude-opus-5-5").maxTokens(1000L).addUserMessage("x")
                .outputConfig(Node.class, JsonSchemaLocalValidation.YES).build();
            System.out.println("recursive record accepted");
        } catch (RuntimeException e) {
            System.out.println(e.getClass().getSimpleName() + ": " + e.getMessage().lines().findFirst().orElse(""));
        }
    }
}
```

<details><summary>Answer</summary>

```
["assignee","priority","tags","title"] false assignee={"type":["string","null"]} priority={"type":"integer"}
"get_weather_forecast"
recursive record accepted
```

Every record component is **required**: an `Optional<String>` becomes a required but **nullable** field (`["string","null"]`), not an optional one. `additionalProperties` is `false`. Tool names are snake-cased from the class name. The SDK's local schema validation **accepted** the recursive `Node` record, but recursive schemas are listed as unsupported for structured outputs, so test such schemas against the API before relying on them (and prefer flattening).
</details>

### C2 — How does LangChain4j's recursive splitter cut text?

<!-- run: cp=@p7 -->
```java
import dev.langchain4j.data.document.Document;
import dev.langchain4j.data.document.splitter.DocumentSplitters;

public class Split02 {
    public static void main(String[] args) {
        String text = "Pools bound concurrency.\n\nKafka offsets are committed per partition after processing.\n\nDone.";
        var segments = DocumentSplitters.recursive(40, 0).split(Document.from(text));
        System.out.println(segments.size());
        segments.forEach(s -> System.out.println("[" + s.text() + "]"));
    }
}
```

<details><summary>Answer</summary>

```
4
[Pools bound concurrency.]
[Kafka offsets are committed per]
[partition after processing.]
[Done.]
```

It splits by paragraph first. A paragraph that fits (≤ 40 characters) becomes one segment. The 59-character middle paragraph doesn't fit, so it is split further at sentence boundaries, then at word boundaries, into pieces of at most 40 characters. A sentence split across segments is exactly why overlap and structure-aware chunking exist.
</details>

### C3 — Spring AI prompt templates: braces and missing variables

<!-- run: cp=@p7 -->
```java
import java.util.Map;
import org.springframework.ai.chat.prompt.PromptTemplate;

public class Template03 {
    public static void main(String[] args) {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        System.out.println(new PromptTemplate("Suggest a museum in {city}.").render(Map.of("city", "Paris")));
        try {
            System.out.println(new PromptTemplate("Reply as JSON like {\"name\": \"...\"} for {city}.").render(Map.of("city", "Paris")));
        } catch (RuntimeException e) {
            System.out.println(e.getClass().getSimpleName());
        }
        try {
            System.out.println(new PromptTemplate("Suggest a museum in {city} for {interest}.").render(Map.of("city", "Paris")));
        } catch (RuntimeException e) {
            System.out.println(e.getClass().getSimpleName() + ": " + e.getMessage());
        }
    }
}
```

<details><summary>Answer</summary>

```
Suggest a museum in Paris.
IllegalArgumentException
IllegalStateException: Not all variables were replaced in the template. Missing variable names are: [interest].
```

Spring AI's default renderer is StringTemplate with `{…}` delimiters. A literal JSON example in the template is parsed as template syntax and fails (`IllegalArgumentException`; the renderer also logs the parse error). Put such examples in a variable, or configure different delimiters. A missing variable fails fast with `IllegalStateException`, which is better than silently sending `{interest}` to the model.
</details>

---

## D. Study map

| Topic | Files | Practise |
|---|---|---|
| Claude API from Java (models, structured output, tools, streaming, caching, API versions) | [7.1](01-Claude-API-Java-SDK.md) | C1, A1–A14 |
| Spring AI and LangChain4j on the wire | [7.2](02-Spring-AI-LangChain4j-Tools-Structured-Output.md) | C3, A15–A16, B2, B5 |
| MCP | [7.3](03-MCP-Servers-and-Clients-in-Java.md) | A17–A21, B4 |
| RAG | [7.4](04-RAG-Embeddings-Chunking-Vector-Stores.md) | C2, A22–A23, B3 |
| Streaming | [7.5](05-SSE-Streaming-LLM-Responses.md) | A24, B1 |
| Incident response | [7.6](06-Production-Failure-Modes-Diagnostics.md) | Rehearse Stories 1–6 aloud |
