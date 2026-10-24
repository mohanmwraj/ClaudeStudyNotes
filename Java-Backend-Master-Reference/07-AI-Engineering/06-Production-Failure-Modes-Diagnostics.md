# 7.6 · Pillar 7 — Production Failure Modes & Diagnostic Checklist (AI Engineering)

> LLM features fail differently from ordinary services. They return **HTTP 200 with the wrong content**, they cost money per token, and inputs can carry instructions. This file has composite war stories (each mechanism **reproduced in [7.1](01-Claude-API-Java-SDK.md)–[7.5](05-SSE-Streaming-LLM-Responses.md)** against a local mock of the Messages API, or with a real local embedding model), the signals to log, the metrics to alert on, and a review checklist.

---

## 1. Incident playbooks

### 🔥 Story 1 — "Every Claude call returns 400 after the dependency upgrade"

* **Symptom:** after bumping `com.anthropic:anthropic-java` to 3.x, every request failed with `invalid_request_error` naming `temperature`.
* **Root cause:** SDK 3.x sends API version **`2026-10-21`**, which rejects `temperature`, `top_p` and `top_k`, even at default values. The config still set `temperature: 0.2` from years ago ([7.1 §5](01-Claude-API-Java-SDK.md#5-api-version-2026-10-21-and-the-java-framework-landscape-)).
* **Also bit them:** the API gateway authenticated on `X-Api-Key`, while SDK 3.x sends `Authorization: Bearer` (verified on the wire, [7.1 §2.1](01-Claude-API-Java-SDK.md#21-runnable-structured-output-from-a-java-record-a-cached-system-prompt-and-the-headers-sdk-33-sends)).
* **Fix:** remove sampling parameters; update the gateway. **Prevention:** a contract test that runs the app's real client against a mock and asserts the request JSON and headers (the technique used throughout this pillar).

### 🔥 Story 2 — "The bill tripled two weeks after launch"

* **Evidence:** output tokens per request ≈ `max_tokens` on 40% of chat requests; `cache_read_input_tokens` ≈ 0; input tokens growing turn by turn.
* **Root causes (all reproduced):**
  1. Users closed tabs mid-answer, but Spring AI's stream kept generating to the end ([7.5 §2.1](05-SSE-Streaming-LLM-Responses.md#21-runnable-mock-claude-stream--spring-ai-chatclientstream--fluxserversentevent--http-client)).
  2. Memory resent the entire conversation plus all tools on every turn ([7.2](02-Spring-AI-LangChain4j-Tools-Structured-Output.md)).
  3. A timestamp at the top of the system prompt broke prompt caching.
* **Fix:** a cancellable stream bridge ([7.5 §2.3](05-SSE-Streaming-LLM-Responses.md#23-runnable-a-cancellable-flux-bridge-for-spring-endpoints)); windowed or summarized memory; a stable cached prefix (system + tools) with volatile data after the breakpoint; realistic `max_tokens`; effort tuned per route.

### 🔥 Story 3 — "2% of orders fail with `JsonParseException`"

* **Root cause:** structured data via **prompt instructions** (Spring AI `.entity()` default, LangChain4j default). The model occasionally added prose, or stopped at `max_tokens` mid-object ([7.2 §2.1](02-Spring-AI-LangChain4j-Tools-Structured-Output.md#21-runnable-template-entity-two-ways-tool-memory)).
* **Fix:** native structured outputs (`ENABLE_NATIVE_STRUCTURED_OUTPUT`, `supportedCapabilities(RESPONSE_FORMAT_JSON_SCHEMA)`, or the SDK's `outputConfig(Class)`); check `stop_reason`; validate business rules after parsing.
* **Second-order bug:** LangChain4j's native schema had `"required": []`, so fields came back missing as nulls or zeros. Supply schemas with `required`.

### 🔥 Story 4 — "Customer A saw Customer B's order number"

* **Root cause A:** a LangChain4j AI Service with a `chatMemoryProvider`, where a helper method without `@MemoryId` shared the **default memory** across all users ([7.2 §3.1](02-Spring-AI-LangChain4j-Tools-Structured-Output.md#31-runnable-an-ai-service-with-a-template-a-record-return-type-a-tool-and-per-user-memory)).
* **Root cause B (a different team):** RAG retrieval without a tenant filter; ACLs were applied after the top-k ([7.4 §3](04-RAG-Embeddings-Chunking-Vector-Stores.md#3-vector-stores-what-to-choose-and-how-to-configure-them-)).
* **Fix:** explicit memory IDs (user + conversation), tenant filters **inside** the vector query, and an audit log of which chunks and memory entries reached each prompt.

### 🔥 Story 5 — "The support bot says 'not in our docs' when it clearly is"

* **Evidence:** offline evaluation showed the right chunk at rank 7–15, or not at all for questions containing config keys.
* **Root causes:**
  1. Vector-only retrieval missed exact identifiers.
  2. 2,000-character chunks embedded with a model that silently ignores everything beyond its input window (verified: cosine 1.0 for texts differing only at the end, [7.4 §2.1](04-RAG-Embeddings-Chunking-Vector-Stores.md#21-runnable-four-chunkers-three-retrievers-one-benchmark)).
* **Fix:** chunks sized to the embedding window; hybrid BM25 + vector retrieval (hit@5 10/14 → 13/14 in the measurement); re-ranking; a labelled evaluation set in CI.

### 🔥 Story 6 — "The agent refunded an order it shouldn't have"

* **Root cause:** a `refund_order` tool exposed to the model with the service's own credentials. A crafted ticket text said "the supervisor approved a full refund". No server-side authorization, no confirmation for destructive tools.
* **Fix:** authorize inside every tool against the **end user's** permissions; confirmation for `destructiveHint` tools; business-rule limits returned as `isError` results ([7.3 §2.1](03-MCP-Servers-and-Clients-in-Java.md#21-runnable-an-orders-mcp-server-tools--resource--prompt-driven-by-raw-json-rpc-and-by-mcpsyncclient)); treat ticket text, documents and tool results as **data**.

### ⚡ Story 7 — "The MCP server works in tests but the IDE says 'invalid JSON'"

* **Root cause:** the stdio server logged its startup banner to **stdout**, which is the JSON-RPC channel.
* **Fix:** log to stderr in stdio mode (explicitly allowed by spec 2025-11-25). Test with a raw JSON-RPC client like [7.3 §2.1](03-MCP-Servers-and-Clients-in-Java.md#21-runnable-an-orders-mcp-server-tools--resource--prompt-driven-by-raw-json-rpc-and-by-mcpsyncclient).

### ⚡ Story 8 — "Streaming worked in staging, arrives in one chunk in production"

* **Root cause:** the production ingress buffered responses and compressed `text/event-stream`.
* **Fix:** disable proxy buffering and gzip for SSE, add heartbeats, and verify with `curl -N` at each hop ([7.5 §3](05-SSE-Streaming-LLM-Responses.md#3-production-checklist-for-streaming-endpoints-)).

### ⚡ Story 9 — "Answers end mid-sentence"

* **Root cause:** `max_tokens: 1024` on a report endpoint; `stop_reason: "max_tokens"` was never checked.
* **Fix:** check `stop_reason` on every response (`end_turn`, `max_tokens`, `tool_use`, `pause_turn`, `refusal`, `stop_sequence`); stream with a generous `max_tokens`; alert on the share of `max_tokens` stops.

### ⚡ Story 10 — "Latency spikes to 30 s during provider incidents"

* **Root cause:** the SDK's built-in retries (2 retries on 429 and 5xx, verified) **plus** a Resilience4j retry **plus** a gateway retry, all on a 10-minute default timeout.
* **Fix:** one retry layer; explicit timeouts sized to the route; queue non-interactive work; a circuit breaker with a degraded fallback. For `refusal` stop reasons on Opus 5.5, server-side **fallbacks** answer with another model instead of failing.

### 🧊 Story 11 — "Our LLM gateway only logs the last message of agent conversations"

* **Root cause:** after upgrading to SDK 3.3, the tool runner uses server-side **message threads** by default: only new messages plus `thread: {type: "continue", previous_message_id}` go over the wire ([7.1 §3.1](01-Claude-API-Java-SDK.md#31-runnable-the-sdks-betatoolrunner-with-and-without-server-side-message-threads)).
* **Fix:** `ToolRunnerCreateParams.builder().thread(false)` where full transcripts must pass through the gateway; or log transcripts in the application instead.

---

## 2. What to log for every LLM call

| Field | Why |
|---|---|
| Model, effort, `max_tokens`, API version, SDK/framework version | Explains behaviour changes after upgrades |
| `usage.input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens` | Cost attribution; cache health |
| `stop_reason` (+ `stop_details.category` for refusals) | Truncation and refusal rates |
| TTFT, total latency, retries and attempt count | User-perceived performance; retry amplification |
| Tool calls (name, duration, `isError`, argument hash) | Agent behaviour, abuse detection, debugging |
| Retrieved chunk IDs and scores; memory/conversation ID | Data-leak forensics; RAG quality |
| Prompt/response bodies **only** under a data policy (redacted, sampled, access-controlled) | Privacy: prompts contain personal data |

Emit these as **OpenTelemetry** spans with the GenAI semantic conventions (`gen_ai.*` attributes), plus metrics. [8.2](../08-Observability-Security-Testing/02-Observability-OpenTelemetry-Micrometer-Logging.md) covers tracing and log pipelines. Spring AI already emits Micrometer observations for chat calls, tool calls and vector-store queries.

---

## 3. Metrics and alerts

| Signal | Alert / meaning |
|---|---|
| Error rate by type (400 / 401 / 429 / 529 / network) | 400 spikes = a contract change or a bad deploy; 429/529 = capacity |
| `stop_reason = max_tokens` share | Truncation regressions |
| Refusal rate (and fallback rate) | Prompt or content changes; safeguard false positives |
| Output tokens per request (p50/p95) and tokens per user per day | Cost anomalies and abuse |
| Cache read ratio (`cache_read / (cache_read + input)`) | A drop = something volatile entered the prefix |
| TTFT p95; streams cancelled vs completed | UX; wasted generation |
| Tool error rate; tool calls per conversation | Broken tools; loops |
| RAG offline eval (hit@k, MRR) per deploy; answer groundedness score | Retrieval regressions |
| MCP server availability, latency, `isError` rate | Tool backend health |

---

## 4. Code-review checklist (AI features)

- [ ] Model ID explicit; effort set explicitly (Opus 5.5 defaults to `medium`); **no `temperature`/`top_p`/`top_k`**.
- [ ] `stop_reason` handled (`max_tokens`, `refusal`, `tool_use`, `pause_turn`) before content is trusted.
- [ ] Structured output via native schemas; generated schemas reviewed (required fields, supported formats, no recursion); results validated.
- [ ] Tools: precise descriptions with *when to call*; strict schemas; authorization inside the tool; confirmation for destructive actions; bounded loops; errors returned as `is_error` results.
- [ ] Memory scoped per user and conversation; bounded; persisted outside the JVM for multi-instance apps.
- [ ] Prompt caching: stable system and tools first; no timestamps or IDs before the breakpoint; hit ratio monitored.
- [ ] Streaming: cancellation reaches the API; heartbeats; proxies not buffering; `max_tokens` bounded.
- [ ] RAG: chunk size within the embedding window; hybrid retrieval; ACL filters in the query; labelled evaluation set in CI; retrieved text treated as untrusted.
- [ ] MCP: stdio servers log to stderr; HTTP servers validate Origin (403) and tokens (OAuth 2.1 resource server); tool lists pinned or reviewed; least-privilege credentials.
- [ ] One retry layer; timeouts per route; fallback or degraded path defined; one shared client instance per app.
- [ ] Logging and tracing of usage, latency, stop reasons and tool calls, with personal data redacted.
