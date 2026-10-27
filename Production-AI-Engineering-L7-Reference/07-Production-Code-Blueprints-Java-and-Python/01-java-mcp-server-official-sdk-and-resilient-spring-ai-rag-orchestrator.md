# 01 · Java Blueprint: an MCP Server on the Official SDK and a Resilient RAG Orchestrator on Spring AI

> **Folder:** `07-Production-Code-Blueprints-Java-and-Python/` · **File 1 of 4**
> **Anchoring code and specifications:** Model Context Protocol Java SDK **2.1.0** (`io.modelcontextprotocol.sdk:mcp`:
> `McpServer`, `StdioServerTransportProvider`, `McpSyncClient`) · MCP specification 2025-11-25 (tools, `isError`,
> output schemas, tool annotations) · Spring AI **2.0.2** (`ChatClient`, `CallAdvisor`) · M. Nygard, *Release It!*
> (circuit breaker, timeouts, bulkheads) · J. Dean and L. A. Barroso, *The Tail at Scale* (CACM 2013).
> **Code baseline:** Java 21 (JDK 25.0.4, `--release 21 -parameters`) against the real jars, no network or API key.
> **Previous folder:** [06 · Durable agent execution](../06-Agentic-AI-Microservices-Java-Spring-AI-and-Python/03-durable-agent-execution-temporal-langgraph-checkpointers-and-hitl.md) ·
> **Next:** [02 · Python blueprint: MCPServer, LangGraph and a vLLM client](02-python-mcpserver-langgraph-agent-and-vllm-streaming-client.md)

---

## 0. The thesis in one paragraph

A production RAG endpoint is a chain of dependencies, and availabilities multiply. With an LLM provider at 99.5% and
a vector store at 99.5%, the chain is about **98.8% before a single bug**. The engineering that gets it back above
99.9% is unglamorous:

- **deadlines that cancel** late work, so a slow vector store degrades the answer instead of the latency;
- **degradation paths**: lexical-only retrieval, a fallback model behind a **circuit breaker**;
- **guards** that refuse to answer without sources and reject citations that point nowhere.

Under a deterministic chaos schedule (slow and failing vector store, a 60-request model outage, hallucinated
citations, users without access), the naive pipeline let **67 errors and 19 invented citations reach users** with a
260 ms p99. The hardened one answered all 200 requests (190 grounded, 10 correctly refused) with **0 errors, 0 bad
citations** and a 127 ms p99.

The MCP server that exposes enterprise knowledge to agents has its own sharp edges, all observed on the official
Java SDK 2.1.0:

- a throwing handler becomes a **JSON-RPC error that carries the raw exception text** (an internal IP address in the
  lab), invisible to the model, unlike the Python SDK's `isError` result;
- **one stray `println` to stdout hangs the session until a 10 s timeout**;
- schema validation returns precise, model-correctable `isError` results;
- side-effecting tools need a client-supplied `request_id` to survive retries.

---

## 1. First principles

### 1.1 Availability of a request path

For dependencies in series, availability is the product: `A = Π aᵢ`. For alternatives in parallel with independent
failures, unavailability is the product: `1 − A = Π (1 − aᵢ)`.

| Path | Computation | A |
|---|---|---|
| Naive: lexical 99.9% × vector 99.5% × LLM 99.5% × reranker 99.9% | product | **98.80%** |
| Vector optional (degrade to lexical), reranker optional | 0.999 × 0.995 | 99.40% |
| Plus LLM failover to a second provider (independent) | 0.999 × (1 − 0.005²) | **99.90%** |

Two caveats carry the L7 answer:

1. **Independence is the assumption that fails.** Two models in the same region, behind the same gateway or the same
   quota pool fail together. Failover must cross at least one failure domain (provider, region or deployment).
2. **Degraded is not free.** Lexical-only retrieval loses paraphrase recall (Folder 04 File 02), so a degraded
   answer must be marked and measured. In the lab, 2 of the 10 refusals happened because the vector leg was missing
   for a paraphrased question.

### 1.2 Deadlines are a budget, and a timeout that does not cancel is not a timeout

Give the request an end-to-end deadline (say 2 s P99) and give each stage `min(stage cap, remaining)`:

| Stage | Cap | Behaviour at the cap |
|---|---|---|
| Hybrid retrieval | 80–150 ms | cancel late legs, fuse what arrived, mark degraded |
| Rerank | 50 ms | skip, keep the fused order |
| LLM TTFT | 500 ms–1 s | fail over or return a retrieval-only answer |
| Generation | the remainder | stream; stop at the deadline with a truncation marker |

Two Java details decide whether the cap holds:

- `Future.get(timeout)` stops *waiting* but not the *work*. Call `cancel(true)` so the virtual thread is interrupted,
  or the slow retriever keeps consuming a connection.
- `ExecutorService.close()` (try-with-resources) **waits for running tasks**. A per-request executor closed without
  cancelling turns an 80 ms timeout back into a 200 ms wait. The orchestrator cancels before anything waits.

Fan-out makes the tail worse: with two legs, each late with probability 0.2, the request is late with probability
`1 − 0.8² = 0.36` unless late legs are dropped. That is Dean and Barroso's tail-at-scale argument applied to RAG.

### 1.3 The circuit breaker as a control loop

The breaker opens after `n` consecutive failures, stays open for `T`, then lets one probe through (half-open). The
probe closes it on success and reopens it on failure.

- **Detection latency** is about `n × inter-arrival time`: 3 failures at 25 ms spacing is 75 ms of user-visible
  failures before failover. The lab opened at request 62, after requests 60 and 61 had already been served by the
  fallback.
- **False trips** at a healthy per-call failure rate `f` happen with probability about `fⁿ` per window: 10⁻⁶ for
  `f = 1%`, `n = 3`.
- **Recovery** costs at most `T` of extra fallback traffic after the primary returns. The lab's primary recovered at
  request 120 and the next probe (at 3,075 ms of virtual time) closed the breaker. One probe at a time prevents a
  recovering provider from being hit by the whole backlog at once.

### 1.4 Grounding guards

Two cheap checks remove the worst RAG failures:

1. **No sources, no model call.** If ACL-filtered retrieval returns nothing, the model can only answer from
   parametric memory. That is a hallucination with a confident tone, or a leak of what it learned elsewhere. The
   hardened path returns "I could not find this in the sources you can access" (10 of 200 requests).
2. **Every citation must resolve.** Parse `[S#]` and require at least one, each within the provided set. On a
   violation, retry once with a strict instruction, then fall back to an extractive answer (the top source with its
   citation). In the lab all 20 hallucinated `[S9]` citations were fixed by the retry.

### 1.5 MCP servers in production

- **Transport and identity.** Stdio is for local, single-user servers: identity is the launching process
  (environment, OS user), as with `MCP_TENANT` here. Remote, multi-tenant servers use Streamable HTTP with OAuth 2.1
  bearer tokens bound to the server's audience (Folder 05 File 02). Never take tenant or user identity from tool
  arguments: the lab rejects `tenant` as an unknown property and still filters by the launch identity.
- **Schemas.** Input schemas with `additionalProperties: false`, enums and bounds let the server reject bad calls
  *with a message the model can act on*. Output schemas plus `structuredContent` let hosts consume results without
  parsing prose.
- **Annotations are hints, not security.** `readOnlyHint`, `destructiveHint` and `idempotentHint` let a host decide
  what needs confirmation, but a malicious server can lie. Hosts enforce policy from their own allowlists.
- **Idempotency.** A host retries after a timeout without knowing whether the first call ran. A `request_id`
  (conversation + turn + call index) lets the server return the original result.
- **Stdout is the protocol.** Logs go to stderr or files, never stdout.

---

## 2. What the official Java SDK 2.1.0 does (each observed below)

1. **Handshake.** The SDK negotiates protocol **2025-11-25** and advertises `tools.listChanged=true` when tools are
   enabled.
2. **Input validation is model-friendly.** With `validateToolInputs(true)`, a missing `query`, a string `top_k` and
   an extra `tenant` property each return `isError=true` with the JSON Schema error text ("required property 'query'
   not found", "/top_k: string found, integer expected", "property 'tenant' is not defined"). The model can fix its
   own call.
3. **A throwing handler is a protocol error, and it leaks.** `IllegalStateException("inventory-db timeout at
   10.2.3.4:5432")` reached the client as `McpError: inventory-db timeout at 10.2.3.4:5432`. It is a JSON-RPC error,
   so many hosts surface it as a failed call rather than a tool result. The Python SDK 2.3.0 (Folder 05 File 01)
   returned an `isError` result instead. The `safe(...)` wrapper converts exceptions into sanitized `isError`
   results with a reference id and logs the details to stderr.
4. **One stray stdout line breaks the session.** A handler that prints a debug line to stdout made the client's next
   call fail with a **10 s timeout**. That costs 10 s per call, not one garbled message.
5. **API evolution.** `Tool.builder()`, `Tool.builder(String)`, `new Implementation(name, version)` and
   `new CallToolRequest(name, args)` are deprecated in 2.1.0; `Tool.builder(name, inputSchema)`,
   `Implementation.builder(...)` and `CallToolRequest.builder(name).arguments(...)` replace them. `-Werror` caught
   all of them.
6. **Stdio is fast.** p50 ≈ 1.2 ms, p99 ≈ 2.8 ms per `tools/call` round trip on this laptop. The transport never
   matters next to a 500 ms model call; the tool's backend does.

### 2.1 With Spring AI's MCP server starter (not executed here)

Spring AI provides Boot starters that expose `@Tool` methods as MCP tools over stdio or Streamable HTTP. The shape
is below; artifact and property names are from the Spring AI MCP documentation (⚠ verify against your Spring AI
version).

```java
@Service
class KnowledgeTools {
    @Tool(description = "Search the caller's knowledge base. Returns ranked snippets with ids.")
    SearchResult searchDocs(@ToolParam(description = "natural-language query") String query, ToolContext ctx) { ... }
}

@Bean
ToolCallbackProvider knowledgeToolProvider(KnowledgeTools tools) {
    return MethodToolCallbackProvider.builder().toolObjects(tools).build();
}
// application.properties: spring.ai.mcp.server.name=kb-server, spring.ai.mcp.server.protocol=STREAMABLE
```

Everything in File 06/02 applies: compile with `-parameters`, take identity from the authenticated request (the
`ToolContext`), never from arguments, and test what the generated schema actually says.

---

## 3. Production code blueprints

### 3.1 Java 21: an MCP knowledge server on the official SDK, driven by the SDK's client

The listing is both sides. `main` launches itself as an MCP server subprocess over stdio (`--server`), connects with
`McpSyncClient`, and exercises the behaviours of §2. A second subprocess (`--server-noisy`) demonstrates the stdout
trap. The server sets the logback root level to `OFF` before anything logs, because logback's default console
appender writes to stdout.

The folder gate caught one more trap here. The first version built result maps with `Map.of`, whose iteration order
is randomized per JVM, so the `structuredContent` key order on the wire differed between runs. That is Folder 05
File 03's lesson again, on a different SDK: anything that reaches a prompt or a cache key must have a deterministic
order. The server now uses insertion-ordered maps.

```java
// McpJavaKnowledgeServer.java - a production-shaped MCP server on the official Java SDK 2.1.0 (stdio transport),
// exercised by the SDK's own McpSyncClient, which launches it as a subprocess. Covers: tool definitions with input
// AND output schemas plus behaviour annotations (readOnly / destructive / idempotent), server-side input validation,
// tool failures as isError results, a client-supplied request_id that makes a side-effecting tool idempotent across
// client retries, tenant identity taken from the launch environment (never from tool arguments), stdio latency,
// and the stdio trap: anything written to stdout that is not a protocol message corrupts the session.
// Build: javac --release 21 -cp "$(cat cp-f06.txt)" (io.modelcontextprotocol.sdk:mcp 2.1.0 + Jackson 3).
package dev.l7.ai.inference;

import io.modelcontextprotocol.client.McpClient;
import io.modelcontextprotocol.client.McpSyncClient;
import io.modelcontextprotocol.client.transport.ServerParameters;
import io.modelcontextprotocol.client.transport.StdioClientTransport;
import io.modelcontextprotocol.json.McpJsonDefaults;
import io.modelcontextprotocol.server.McpServer;
import io.modelcontextprotocol.server.McpServerFeatures.SyncToolSpecification;
import io.modelcontextprotocol.server.McpSyncServerExchange;
import io.modelcontextprotocol.server.transport.StdioServerTransportProvider;
import io.modelcontextprotocol.spec.McpSchema;
import io.modelcontextprotocol.spec.McpSchema.CallToolRequest;
import io.modelcontextprotocol.spec.McpSchema.CallToolResult;
import io.modelcontextprotocol.spec.McpSchema.TextContent;
import io.modelcontextprotocol.spec.McpSchema.Tool;
import io.modelcontextprotocol.spec.McpSchema.ToolAnnotations;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.BiFunction;

public final class McpJavaKnowledgeServer {

    record Doc(String id, String title, String body, String tenant) {}

    static final List<Doc> DOCS = List.of(
            new Doc("kb-101", "Refund policy", "Damaged items are refunded in full within 30 days of delivery.", "acme"),
            new Doc("kb-102", "Shipping delays", "Carrier delays over 5 days qualify for a 10% credit.", "acme"),
            new Doc("kb-103", "Warranty", "Electronics carry a 1-year limited warranty.", "acme"),
            new Doc("kb-900", "Globex pricing", "Globex enterprise discount schedule (confidential).", "globex"));

    // ------------------------------------------------------------------ server side
    static Map<String, Object> schema(String json) {
        try {
            return McpJsonDefaults.getMapper().readValue(json, new io.modelcontextprotocol.json.TypeRef<Map<String, Object>>() {});
        } catch (java.io.IOException e) {
            throw new java.io.UncheckedIOException(e);
        }
    }

    static Tool searchTool() {
        return Tool.builder("search_docs", schema("""
                        {"type":"object","properties":{
                           "query":{"type":"string","minLength":2,"description":"natural-language query"},
                           "top_k":{"type":"integer","minimum":1,"maximum":10,"default":3}},
                         "required":["query"],"additionalProperties":false}"""))
                .title("Search knowledge base")
                .description("Search the caller's knowledge base. Use for policy questions. Returns ranked snippets with ids.")
                .outputSchema(schema("""
                        {"type":"object","properties":{"hits":{"type":"array","items":{"type":"object","properties":{
                           "id":{"type":"string"},"title":{"type":"string"},"score":{"type":"number"},"snippet":{"type":"string"}},
                           "required":["id","score"]}}},"required":["hits"]}"""))
                .annotations(new ToolAnnotations("Search knowledge base", true, false, true, false, null))
                .build();
    }

    static Tool ticketTool() {
        return Tool.builder("create_ticket", schema("""
                        {"type":"object","properties":{
                           "title":{"type":"string","minLength":3},
                           "severity":{"type":"string","enum":["low","high"]},
                           "request_id":{"type":"string","minLength":8}},
                         "required":["title","severity","request_id"],"additionalProperties":false}"""))
                .title("Create support ticket")
                .description("Open a support ticket. Side effect. Pass the same request_id when retrying.")
                .annotations(new ToolAnnotations("Create support ticket", false, false, true, true, null))
                .build();
    }

    static Tool flakyTool(String name) {
        return Tool.builder(name, schema("""
                        {"type":"object","properties":{"sku":{"type":"string"}},"required":["sku"]}"""))
                .description("Stock level for a SKU (backend is unreliable).").build();
    }

    static CallToolResult search(String tenant, Map<String, Object> args) {
        String q = ((String) args.get("query")).toLowerCase();
        int k = args.get("top_k") instanceof Number n ? n.intValue() : 3;
        List<Map<String, Object>> hits = new ArrayList<>();
        for (Doc d : DOCS) {
            if (!d.tenant().equals(tenant)) continue;                             // tenant from the launch env, not args
            long overlap = java.util.Arrays.stream(q.split("\\W+"))
                    .filter(w -> w.length() > 2 && (d.title() + " " + d.body()).toLowerCase().contains(w)).count();
            if (overlap > 0) {
                Map<String, Object> h = new java.util.LinkedHashMap<>();         // Map.of order is randomized per JVM
                h.put("id", d.id());
                h.put("title", d.title());
                h.put("score", overlap);
                h.put("snippet", d.body());
                hits.add(h);
            }
        }
        hits.sort(Comparator.comparingLong((Map<String, Object> h) -> -((Number) h.get("score")).longValue())
                .thenComparing(h -> (String) h.get("id")));
        List<Map<String, Object>> top = hits.subList(0, Math.min(k, hits.size()));
        StringBuilder text = new StringBuilder();
        for (Map<String, Object> h : top) text.append("[").append(h.get("id")).append("] ").append(h.get("snippet")).append('\n');
        return CallToolResult.builder().addTextContent(text.toString().strip()).structuredContent(Map.of("hits", top)).build();
    }

    /** Hardened handler: exceptions become sanitized isError results the model can act on; details go to stderr. */
    static BiFunction<McpSyncServerExchange, CallToolRequest, CallToolResult> safe(String tool,
            BiFunction<McpSyncServerExchange, CallToolRequest, CallToolResult> h, AtomicInteger errorRefs) {
        return (ex, req) -> {
            try {
                return h.apply(ex, req);
            } catch (RuntimeException e) {
                String ref = "E" + errorRefs.incrementAndGet();
                System.err.println("tool " + tool + " failed ref=" + ref + ": " + e);       // stderr: never the protocol channel
                return CallToolResult.builder().isError(true)
                        .addTextContent(tool + " is temporarily unavailable (ref " + ref + "). Retry once, or answer without it.").build();
            }
        };
    }

    static BiFunction<McpSyncServerExchange, CallToolRequest, CallToolResult> flakyInventory() {
        AtomicInteger calls = new AtomicInteger();
        return (ex, req) -> {
            if (calls.incrementAndGet() % 2 == 1) throw new IllegalStateException("inventory-db timeout at 10.2.3.4:5432");
            return CallToolResult.builder().addTextContent(req.arguments().get("sku") + ": 4 in stock").build();
        };
    }

    static void serve(boolean noisy) {
        String tenant = System.getenv().getOrDefault("MCP_TENANT", "none");
        Map<String, String> tickets = new ConcurrentHashMap<>();                 // request_id -> ticket id (idempotency)
        AtomicInteger seq = new AtomicInteger(1000), errorRefs = new AtomicInteger();
        var transport = new StdioServerTransportProvider(McpJsonDefaults.getMapper());
        McpServer.sync(transport)
                .serverInfo("kb-server", "1.0.0")
                .instructions("Knowledge base and ticketing for tenant-scoped support agents.")
                .capabilities(McpSchema.ServerCapabilities.builder().tools(true).build())
                .validateToolInputs(true)
                .requestTimeout(Duration.ofSeconds(5))
                .tools(SyncToolSpecification.builder().tool(searchTool()).callHandler((ex, req) -> {
                            if (noisy) System.out.println("DEBUG search " + req.arguments());   // the stdio trap
                            return search(tenant, req.arguments());
                        }).build(),
                        SyncToolSpecification.builder().tool(ticketTool()).callHandler((ex, req) -> {
                            String rid = (String) req.arguments().get("request_id");
                            boolean[] created = {false};
                            String id = tickets.computeIfAbsent(rid, k -> { created[0] = true; return "T-" + seq.incrementAndGet(); });
                            return CallToolResult.builder().addTextContent((created[0] ? "created " : "already exists ") + id)
                                    .structuredContent(Map.of("ticket", id, "created", created[0])).build();
                        }).build(),
                        SyncToolSpecification.builder().tool(flakyTool("inventory_lookup")).callHandler(flakyInventory()).build(),
                        SyncToolSpecification.builder().tool(flakyTool("inventory_lookup_safe"))
                                .callHandler(safe("inventory_lookup_safe", flakyInventory(), errorRefs)).build())
                .build();
        try {
            new CountDownLatch(1).await();                                         // the transport owns stdin/stdout
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    // ------------------------------------------------------------------ client side (the host)
    static McpSyncClient connect(String mode) {
        String java = Path.of(System.getProperty("java.home"), "bin", "java").toString();
        ServerParameters params = ServerParameters.builder(java)
                .args("-cp", System.getProperty("java.class.path"), "-Dlogback.configurationFile=none",
                        McpJavaKnowledgeServer.class.getName(), mode)
                .addEnvVar("MCP_TENANT", "acme").build();
        StdioClientTransport t = new StdioClientTransport(params, McpJsonDefaults.getMapper());
        t.setStdErrorHandler(line -> { });                                         // server logs belong on stderr
        McpSyncClient c = McpClient.sync(t).requestTimeout(Duration.ofSeconds(10)).initializationTimeout(Duration.ofSeconds(20))
                .clientInfo(McpSchema.Implementation.builder("rag-host", "1.0.0").build()).build();
        c.initialize();
        return c;
    }

    static CallToolRequest call(String tool, Map<String, Object> args) {
        return CallToolRequest.builder(tool).arguments(args).build();
    }

    static String text(CallToolResult r) {
        return r.content().stream().map(x -> x instanceof TextContent tc ? tc.text() : x.toString())
                .reduce("", String::concat).replace("\n", " | ");
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) throws Exception {
        if (args.length > 0 && args[0].startsWith("--server")) {
            ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME))
                    .setLevel(ch.qos.logback.classic.Level.OFF);                  // logback's console appender is STDOUT
            serve(args[0].equals("--server-noisy"));
            return;
        }
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME))
                .setLevel(ch.qos.logback.classic.Level.OFF);
        try (McpSyncClient c = connect("--server")) {
            var init = c.getCurrentInitializationResult();
            System.out.println("initialized: server " + init.serverInfo().name() + " " + init.serverInfo().version()
                    + ", protocol " + init.protocolVersion() + ", tools capability listChanged=" + init.capabilities().tools().listChanged());
            for (Tool t : c.listTools().tools()) {
                ToolAnnotations a = t.annotations();
                System.out.printf("  tool %-17s readOnly=%-5s destructive=%-5s idempotent=%-5s outputSchema=%s%n", t.name(),
                        a == null ? null : a.readOnlyHint(), a == null ? null : a.destructiveHint(),
                        a == null ? null : a.idempotentHint(), t.outputSchema() != null);
            }

            CallToolResult ok = c.callTool(call("search_docs", Map.of("query", "refund for damaged item", "top_k", 2)));
            System.out.println("\nsearch_docs: isError=" + ok.isError() + " text=" + text(ok));
            System.out.println("  structuredContent=" + ok.structuredContent());
            check(!Boolean.TRUE.equals(ok.isError()) && text(ok).startsWith("[kb-101]"), "search works");
            CallToolResult leak = c.callTool(call("search_docs", Map.of("query", "globex enterprise discount pricing")));
            System.out.println("cross-tenant query from tenant acme: " + text(leak).length() + " chars, hits=" + leak.structuredContent());
            check(!text(leak).contains("kb-900"), "tenant isolation comes from the server, not the model");

            System.out.println("\ninput validation (validateToolInputs=true):");
            for (Map<String, Object> bad : List.<Map<String, Object>>of(Map.of("top_k", 3), Map.of("query", "refund", "top_k", "ten"),
                    Map.of("query", "refund", "tenant", "globex"))) {
                String outcome;
                try {
                    CallToolResult r = c.callTool(call("search_docs", bad));
                    outcome = "isError=" + r.isError() + " " + text(r);
                } catch (RuntimeException e) {
                    outcome = "JSON-RPC error " + e.getClass().getSimpleName() + ": " + e.getMessage();
                }
                System.out.println("  " + new java.util.TreeMap<>(bad) + " -> " + outcome);
            }

            System.out.println("\na handler that throws (first call fails, second succeeds):");
            Map<String, Boolean> rpcError = new java.util.HashMap<>();
            for (String tool : List.of("inventory_lookup", "inventory_lookup_safe")) {
                for (int i = 0; i < 2; i++) {
                    String outcome;
                    try {
                        CallToolResult r = c.callTool(call(tool, Map.of("sku", "SKU-9")));
                        outcome = "isError=" + r.isError() + " " + text(r);
                    } catch (RuntimeException e) {
                        outcome = "JSON-RPC error " + e.getClass().getSimpleName() + ": " + e.getMessage();
                        rpcError.put(tool, true);
                    }
                    System.out.printf("  %-22s attempt %d -> %s%n", tool, i + 1, outcome);
                }
            }
            check(rpcError.containsKey("inventory_lookup") && !rpcError.containsKey("inventory_lookup_safe"),
                    "raw exceptions surface as protocol errors; the wrapper turns them into isError results");

            System.out.println("\nidempotent side effect (client retries with the same request_id):");
            Map<String, Object> ticket = Map.of("title", "Damaged blender", "severity", "high", "request_id", "conv-42:turn-7");
            CallToolResult t1 = c.callTool(call("create_ticket", ticket));
            CallToolResult t2 = c.callTool(call("create_ticket", ticket));
            System.out.println("  first: " + text(t1) + " | retry: " + text(t2));
            check(text(t1).startsWith("created") && text(t2).startsWith("already exists") && text(t1).endsWith(text(t2).substring(15)),
                    "retry returns the original ticket");

            int n = 300;
            long[] lat = new long[n];
            for (int i = 0; i < 20; i++) c.callTool(call("search_docs", Map.of("query", "warranty")));
            for (int i = 0; i < n; i++) {
                long t0 = System.nanoTime();
                c.callTool(call("search_docs", Map.of("query", "warranty electronics")));
                lat[i] = System.nanoTime() - t0;
            }
            java.util.Arrays.sort(lat);
            System.out.printf("%nstdio round trip, %d sequential tools/call: p50 %.2f ms, p99 %.2f ms%n", n, lat[n / 2] / 1e6, lat[n * 99 / 100] / 1e6);
        }

        System.out.println("\nthe stdio trap: a handler that prints one debug line to stdout");
        try (McpSyncClient noisy = connect("--server-noisy")) {
            String outcome;
            try {
                CallToolResult r = noisy.callTool(call("search_docs", Map.of("query", "refund policy")));
                outcome = "call returned isError=" + r.isError() + " (the stray line was dropped by the client)";
            } catch (RuntimeException e) {
                outcome = "call FAILED: " + e.getClass().getSimpleName() + ": " + String.valueOf(e.getMessage()).lines().findFirst().orElse("");
            }
            System.out.println("  " + outcome);
        }
        System.out.println("\nall McpJavaKnowledgeServer self-checks passed");
    }
}
```

Output (one measured run; everything except the latency line is deterministic):

```text
initialized: server kb-server 1.0.0, protocol 2025-11-25, tools capability listChanged=true
  tool search_docs       readOnly=true  destructive=false idempotent=true  outputSchema=true
  tool create_ticket     readOnly=false destructive=false idempotent=true  outputSchema=false
  tool inventory_lookup  readOnly=null  destructive=null  idempotent=null  outputSchema=false
  tool inventory_lookup_safe readOnly=null  destructive=null  idempotent=null  outputSchema=false

search_docs: isError=false text=[kb-101] Damaged items are refunded in full within 30 days of delivery. | [kb-102] Carrier delays over 5 days qualify for a 10% credit.
  structuredContent={hits=[{id=kb-101, title=Refund policy, score=3, snippet=Damaged items are refunded in full within 30 days of delivery.}, {id=kb-102, title=Shipping delays, score=1, snippet=Carrier delays over 5 days qualify for a 10% credit.}]}
cross-tenant query from tenant acme: 0 chars, hits={hits=[]}

input validation (validateToolInputs=true):
  {top_k=3} -> isError=true Tool (search_docs) input validation failed: Validation failed: JSON schema validation errors: [: required property 'query' not found]
  {query=refund, top_k=ten} -> isError=true Tool (search_docs) input validation failed: Validation failed: JSON schema validation errors: [/top_k: string found, integer expected]
  {query=refund, tenant=globex} -> isError=true Tool (search_docs) input validation failed: Validation failed: JSON schema validation errors: [: property 'tenant' is not defined in the schema and the schema does not allow additional properties]

a handler that throws (first call fails, second succeeds):
  inventory_lookup       attempt 1 -> JSON-RPC error McpError: inventory-db timeout at 10.2.3.4:5432
  inventory_lookup       attempt 2 -> isError=false SKU-9: 4 in stock
  inventory_lookup_safe  attempt 1 -> isError=true inventory_lookup_safe is temporarily unavailable (ref E1). Retry once, or answer without it.
  inventory_lookup_safe  attempt 2 -> isError=false SKU-9: 4 in stock

idempotent side effect (client retries with the same request_id):
  first: created T-1001 | retry: already exists T-1001

stdio round trip, 300 sequential tools/call: p50 1.28 ms, p99 3.26 ms

the stdio trap: a handler that prints one debug line to stdout
  call FAILED: ReactiveException: java.util.concurrent.TimeoutException: Did not observe any item or terminal signal within 10000ms in 'source(MonoDeferContextual)' (and no fallback has been configured)

all McpJavaKnowledgeServer self-checks passed
```

### 3.2 Java 21 + Spring AI 2.0.2: the resilient RAG orchestrator under chaos

Both pipelines see the same deterministic chaos schedule:

- every 5th request the vector store is slow (200 ms), and every 17th it is down;
- requests 60–119 hit a primary-model outage;
- every 10th answer invents an `[S9]` citation;
- every 25th user lacks access to the support corpus.

The breaker runs on a virtual clock (25 ms per request) so its transitions are reproducible.

```java
// ResilientRagOrchestrator.java - a RAG request path on Spring AI 2.0.2 hardened the way production needs it, run
// against a deterministic chaos schedule and compared with the naive version of the same pipeline:
//   * hybrid retrieval (lexical + vector) on virtual threads with a real deadline: late retrievers are CANCELLED and
//     the answer is marked degraded (ExecutorService.close() waits for running tasks, so cancel first);
//   * ACL pre-filtering inside retrieval, RRF fusion, and context packing under a token budget with numbered sources;
//   * no sources -> no model call (an ungrounded answer is worse than "I could not find this");
//   * a citation guard advisor: every [S#] must be a provided source, else one strict retry, else an extractive answer;
//   * model failover behind a circuit breaker (CLOSED -> OPEN -> HALF_OPEN probe) on a ChatModel facade that keeps
//     ToolCallingChatOptions (File 06/02's silent-tool-drop trap).
// Build: javac --release 21 -cp "$(cat cp-f06.txt)" (spring-ai-client-chat 2.0.2).
package dev.l7.ai.inference;

import io.micrometer.observation.ObservationRegistry;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.LongSupplier;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.ChatClientRequest;
import org.springframework.ai.chat.client.ChatClientResponse;
import org.springframework.ai.chat.client.advisor.ToolCallingAdvisor;
import org.springframework.ai.chat.client.advisor.api.CallAdvisor;
import org.springframework.ai.chat.client.advisor.api.CallAdvisorChain;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.model.Generation;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.ai.model.tool.ToolCallingChatOptions;
import org.springframework.ai.model.tool.ToolCallingManager;
import org.springframework.core.Ordered;

public final class ResilientRagOrchestrator {

    // ------------------------------------------------------------------ corpus and chaos
    record Chunk(String id, String text, Set<String> acl) {}

    record Scored(Chunk chunk, double score) {}

    static final List<Chunk> CORPUS = List.of(
            new Chunk("kb-101", "Damaged items are refunded in full within 30 days of delivery.", Set.of("support")),
            new Chunk("kb-102", "Carrier delays over 5 days qualify for a 10 percent shipping credit.", Set.of("support")),
            new Chunk("kb-103", "Electronics carry a one year limited warranty against defects.", Set.of("support")),
            new Chunk("kb-104", "Refunds are issued to the original payment method within 5 business days.", Set.of("support")),
            new Chunk("kb-105", "Opened software cannot be returned unless it is defective.", Set.of("support")),
            new Chunk("hr-201", "Salary bands for level 6 engineers are confidential.", Set.of("hr")),
            new Chunk("hr-202", "Refund of relocation costs requires director approval.", Set.of("hr")));

    static final String[] QUESTIONS = {
            "how long do refunds take for damaged items", "what credit do I get for carrier delays",
            "is there a warranty on electronics", "can I return opened software", "refund relocation costs approval"};

    /** Deterministic chaos keyed by request index, so naive and hardened face the same storm. */
    record Chaos(int i) {
        boolean vectorSlow() { return i % 5 == 0; }
        boolean vectorDown() { return i % 17 == 0; }
        boolean primaryDown() { return i >= 60 && i < 120; }
        boolean hallucinate() { return i % 10 == 3; }
    }

    // ------------------------------------------------------------------ retrievers
    static Set<String> words(String s) {
        Set<String> w = new LinkedHashSet<>();
        for (String t : s.toLowerCase().split("\\W+")) if (t.length() > 2) w.add(t);
        return w;
    }

    static List<Scored> lexical(String q, Set<String> groups) {
        AgentDagExecutor.sleepQuietly(5);
        Set<String> qw = words(q);
        List<Scored> out = new ArrayList<>();
        for (Chunk c : CORPUS) {
            if (c.acl().stream().noneMatch(groups::contains)) continue;          // ACL pre-filter, inside retrieval
            long hits = words(c.text()).stream().filter(qw::contains).count();
            if (hits > 0) out.add(new Scored(c, hits));
        }
        out.sort(Comparator.comparingDouble((Scored s) -> -s.score()).thenComparing(s -> s.chunk().id()));
        return out;
    }

    static double[] embed(String s) {
        double[] v = new double[64];
        for (String w : words(s)) {
            v[Math.floorMod(w.hashCode(), 64)] += 1;
            if (w.length() > 4) v[Math.floorMod(w.substring(0, 4).hashCode(), 64)] += 0.5;   // crude stemming signal
        }
        double n = Math.sqrt(Arrays.stream(v).map(x -> x * x).sum());
        for (int k = 0; k < v.length; k++) v[k] /= n == 0 ? 1 : n;
        return v;
    }

    static List<Scored> vector(String q, Set<String> groups, Chaos chaos) {
        AgentDagExecutor.sleepQuietly(chaos.vectorSlow() ? 200 : 10);            // interruptible: cancellation works
        if (chaos.vectorDown()) throw new IllegalStateException("vector store 503");
        double[] qv = embed(q);
        List<Scored> out = new ArrayList<>();
        for (Chunk c : CORPUS) {
            if (c.acl().stream().noneMatch(groups::contains)) continue;
            double[] cv = embed(c.text());
            double dot = 0;
            for (int k = 0; k < 64; k++) dot += qv[k] * cv[k];
            if (dot > 0.15) out.add(new Scored(c, dot));
        }
        out.sort(Comparator.comparingDouble((Scored s) -> -s.score()).thenComparing(s -> s.chunk().id()));
        return out;
    }

    static List<Chunk> rrf(List<List<Scored>> lists, int k) {
        Map<String, Double> score = new HashMap<>();
        Map<String, Chunk> byId = new HashMap<>();
        for (List<Scored> l : lists)
            for (int r = 0; r < l.size(); r++) {
                score.merge(l.get(r).chunk().id(), 1.0 / (k + r + 1), Double::sum);
                byId.put(l.get(r).chunk().id(), l.get(r).chunk());
            }
        return score.entrySet().stream().sorted(Map.Entry.<String, Double>comparingByValue().reversed().thenComparing(Map.Entry.comparingByKey()))
                .map(e -> byId.get(e.getKey())).toList();
    }

    record Retrieval(List<Chunk> chunks, boolean degraded) {}

    static Retrieval retrieveHardened(String q, Set<String> groups, Chaos chaos, long budgetMs, ExecutorService vt) {
        Future<List<Scored>> lex = vt.submit(() -> lexical(q, groups));
        Future<List<Scored>> vec = vt.submit(() -> vector(q, groups, chaos));
        long deadline = System.nanoTime() + budgetMs * 1_000_000;
        List<List<Scored>> got = new ArrayList<>();
        boolean degraded = false;
        for (Future<List<Scored>> f : List.of(lex, vec)) {
            try {
                got.add(f.get(Math.max(0, deadline - System.nanoTime()), TimeUnit.NANOSECONDS));
            } catch (Exception e) {
                f.cancel(true);                                                   // stop waiting AND stop the work
                degraded = true;
            }
        }
        return new Retrieval(rrf(got, 60), degraded);
    }

    static Retrieval retrieveNaive(String q, Set<String> groups, Chaos chaos) {
        List<List<Scored>> got = new ArrayList<>();
        got.add(lexical(q, groups));
        got.add(vector(q, groups, chaos));                                        // waits as long as it takes; throws through
        return new Retrieval(rrf(got, 60), false);
    }

    // ------------------------------------------------------------------ models and the failover facade
    static final Pattern CITE = Pattern.compile("\\[S(\\d+)]");

    /** Answers from the numbered sources in the system message; can fail or hallucinate a citation on cue. */
    static final class ScriptedLlm implements ChatModel {
        final String name;
        final AtomicInteger calls = new AtomicInteger();
        volatile Chaos chaos = new Chaos(1);
        final boolean primary;

        ScriptedLlm(String name, boolean primary) {
            this.name = name;
            this.primary = primary;
        }

        @Override public ChatOptions getOptions() { return ToolCallingChatOptions.builder().build(); }

        @Override
        public ChatResponse call(Prompt p) {
            calls.incrementAndGet();
            AgentDagExecutor.sleepQuietly(primary ? 15 : 25);                     // the fallback is slower
            if (primary && chaos.primaryDown()) throw new IllegalStateException("primary model 503 overloaded");
            String sys = p.getSystemMessage().getText();
            Matcher m = Pattern.compile("\\[S1] \\(([\\w-]+)\\) ([^\\n]+)").matcher(sys);
            String body = m.find() ? m.group(2) : "no information";
            boolean strict = p.getInstructions().stream().map(Message::getText).anyMatch(t -> t != null && t.contains("STRICT"));
            String extra = chaos.hallucinate() && !strict ? " The policy was updated last month [S9]." : "";
            return new ChatResponse(List.of(new Generation(new AssistantMessage(body + " [S1]" + extra + " (" + name + ")"))));
        }
    }

    enum State { CLOSED, OPEN, HALF_OPEN }

    static final class FailoverChatModel implements ChatModel {
        final ChatModel primary, secondary;
        final LongSupplier clock;
        final int threshold;
        final long openMs;
        State state = State.CLOSED;
        int consecutiveFailures;
        long openedAt;
        final List<String> transitions = new ArrayList<>();
        final AtomicInteger servedBySecondary = new AtomicInteger();

        FailoverChatModel(ChatModel primary, ChatModel secondary, LongSupplier clock, int threshold, long openMs) {
            this.primary = primary;
            this.secondary = secondary;
            this.clock = clock;
            this.threshold = threshold;
            this.openMs = openMs;
        }

        @Override public ChatOptions getOptions() { return ToolCallingChatOptions.builder().build(); }

        void to(State s, String why) {
            transitions.add(state + "->" + s + " at t=" + clock.getAsLong() + "ms (" + why + ")");
            state = s;
        }

        @Override
        public synchronized ChatResponse call(Prompt p) {
            if (state == State.OPEN && clock.getAsLong() - openedAt >= openMs) to(State.HALF_OPEN, "cool-down elapsed, probing");
            if (state != State.OPEN) {
                try {
                    ChatResponse r = primary.call(p);
                    if (state == State.HALF_OPEN) to(State.CLOSED, "probe succeeded");
                    consecutiveFailures = 0;
                    return r;
                } catch (RuntimeException e) {
                    consecutiveFailures++;
                    if (state == State.HALF_OPEN || consecutiveFailures >= threshold) {
                        to(State.OPEN, e.getMessage());
                        openedAt = clock.getAsLong();
                    }
                }
            }
            servedBySecondary.incrementAndGet();
            return secondary.call(p);                                             // fail over for this request
        }
    }

    // ------------------------------------------------------------------ advisors
    static final String CTX_SOURCES = "rag.sources", CTX_DEGRADED = "rag.degraded";

    /** Retrieves, packs context under a token budget, numbers the sources, and refuses to call the model with none. */
    static final class RetrievalAdvisor implements CallAdvisor {
        final ExecutorService vt;
        final int tokenBudget;
        volatile Chaos chaos;
        volatile Set<String> groups;

        RetrievalAdvisor(ExecutorService vt, int tokenBudget) {
            this.vt = vt;
            this.tokenBudget = tokenBudget;
        }

        @Override public String getName() { return "retrieval"; }

        @Override public int getOrder() { return Ordered.HIGHEST_PRECEDENCE + 100; }

        @Override
        public ChatClientResponse adviseCall(ChatClientRequest req, CallAdvisorChain chain) {
            String q = req.prompt().getUserMessage().getText();
            Retrieval r = retrieveHardened(q, groups, chaos, 80, vt);
            List<Chunk> packed = new ArrayList<>();
            int used = 0;
            for (Chunk c : r.chunks()) {
                int cost = c.text().length() / 4 + 8;
                if (used + cost > tokenBudget) break;
                packed.add(c);
                used += cost;
            }
            if (packed.isEmpty()) {
                AssistantMessage none = new AssistantMessage("I could not find this in the sources you can access.");
                return ChatClientResponse.builder().chatResponse(new ChatResponse(List.of(new Generation(none))))
                        .context(req.context()).context(CTX_SOURCES, List.of()).context(CTX_DEGRADED, r.degraded()).build();
            }
            StringBuilder sb = new StringBuilder("Answer ONLY from these sources and cite them as [S#].\n");
            for (int i = 0; i < packed.size(); i++)
                sb.append("[S").append(i + 1).append("] (").append(packed.get(i).id()).append(") ").append(packed.get(i).text()).append('\n');
            Prompt p = req.prompt().augmentSystemMessage(sb.toString());
            ChatClientRequest next = req.mutate().prompt(p).context(CTX_SOURCES, packed).context(CTX_DEGRADED, r.degraded()).build();
            ChatClientResponse resp = chain.nextCall(next);
            return resp.mutate().context(CTX_SOURCES, packed).context(CTX_DEGRADED, r.degraded()).build();
        }
    }

    /** Every [S#] must name a provided source and at least one must be present; else retry strictly, else extract. */
    static final class CitationGuardAdvisor implements CallAdvisor {
        final AtomicInteger retried = new AtomicInteger(), extracted = new AtomicInteger();

        @Override public String getName() { return "citation-guard"; }

        @Override public int getOrder() { return Ordered.HIGHEST_PRECEDENCE + 150; }

        static boolean valid(String text, int nSources) {
            Matcher m = CITE.matcher(text);
            boolean any = false;
            while (m.find()) {
                any = true;
                int s = Integer.parseInt(m.group(1));
                if (s < 1 || s > nSources) return false;
            }
            return any;
        }

        @Override
        @SuppressWarnings("unchecked")
        public ChatClientResponse adviseCall(ChatClientRequest req, CallAdvisorChain chain) {
            List<Chunk> sources = (List<Chunk>) req.context().getOrDefault(CTX_SOURCES, List.of());
            ChatClientResponse r = chain.copy(this).nextCall(req);
            if (valid(r.chatResponse().getResult().getOutput().getText(), sources.size())) return r;
            retried.incrementAndGet();
            Prompt strict = req.prompt().augmentUserMessage(u -> u.mutate()
                    .text(u.getText() + "\nSTRICT: cite only [S1]..[S" + sources.size() + "]; never invent sources.").build());
            r = chain.copy(this).nextCall(req.mutate().prompt(strict).build());
            if (valid(r.chatResponse().getResult().getOutput().getText(), sources.size())) return r;
            extracted.incrementAndGet();
            AssistantMessage fallback = new AssistantMessage(sources.get(0).text() + " [S1]");
            return r.mutate().chatResponse(new ChatResponse(List.of(new Generation(fallback)))).build();
        }
    }

    // ------------------------------------------------------------------ the experiment
    record Tally(int ok, int grounded, int degraded, int noSource, int errors, int badCitationsShown, long p50, long p99) {}

    static long pct(List<Long> xs, double p) {
        List<Long> s = new ArrayList<>(xs);
        s.sort(null);
        return s.isEmpty() ? 0 : s.get((int) Math.min(s.size() - 1, Math.round(p * (s.size() - 1))));
    }

    static Set<String> groupsFor(int i) { return i % 25 == 7 ? Set.of("guest") : Set.of("support"); }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME))
                .setLevel(ch.qos.logback.classic.Level.OFF);
        int n = 200;
        Map<String, Tally> results = new LinkedHashMap<>();

        // naive: sequential retrieval without deadlines, one model, no guard
        {
            ScriptedLlm primary = new ScriptedLlm("primary", true);
            ChatClient client = ChatClient.builder(primary, ObservationRegistry.NOOP, null, null,
                    ToolCallingAdvisor.builder().toolCallingManager(ToolCallingManager.builder().build())).build();
            int ok = 0, errors = 0, bad = 0, degraded = 0, none = 0;
            List<Long> lat = new ArrayList<>();
            for (int i = 1; i <= n; i++) {
                Chaos chaos = new Chaos(i);
                primary.chaos = chaos;
                String q = QUESTIONS[i % QUESTIONS.length];
                long t0 = System.nanoTime();
                try {
                    Retrieval r = retrieveNaive(q, groupsFor(i), chaos);
                    StringBuilder sb = new StringBuilder("Answer from these sources and cite them as [S#].\n");
                    for (int s = 0; s < r.chunks().size(); s++)
                        sb.append("[S").append(s + 1).append("] (").append(r.chunks().get(s).id()).append(") ").append(r.chunks().get(s).text()).append('\n');
                    String a = client.prompt().system(sb.toString()).user(q).call().content();
                    ok++;
                    if (!CitationGuardAdvisor.valid(a, r.chunks().size())) bad++;
                    if (r.chunks().isEmpty()) none++;
                } catch (RuntimeException e) {
                    errors++;
                }
                lat.add((System.nanoTime() - t0) / 1_000_000);
            }
            results.put("naive", new Tally(ok, ok - bad, degraded, none, errors, bad, pct(lat, 0.5), pct(lat, 0.99)));
        }

        // hardened
        AtomicLong virtualNow = new AtomicLong();
        FailoverChatModel model;
        CitationGuardAdvisor guard = new CitationGuardAdvisor();
        ScriptedLlm primary = new ScriptedLlm("primary", true), secondary = new ScriptedLlm("fallback", false);
        try (ExecutorService vt = Executors.newVirtualThreadPerTaskExecutor()) {
            model = new FailoverChatModel(primary, secondary, virtualNow::get, 3, 500);
            RetrievalAdvisor retrieval = new RetrievalAdvisor(vt, 60);
            ChatClient client = ChatClient.builder(model, ObservationRegistry.NOOP, null, null,
                    ToolCallingAdvisor.builder().toolCallingManager(ToolCallingManager.builder().build()))
                    .defaultAdvisors(retrieval, guard).build();
            int ok = 0, errors = 0, bad = 0, degraded = 0, none = 0, grounded = 0;
            List<Long> lat = new ArrayList<>();
            for (int i = 1; i <= n; i++) {
                Chaos chaos = new Chaos(i);
                primary.chaos = chaos;
                secondary.chaos = chaos;
                retrieval.chaos = chaos;
                retrieval.groups = groupsFor(i);
                virtualNow.addAndGet(25);                                         // one request every 25 ms
                String q = QUESTIONS[i % QUESTIONS.length];
                long t0 = System.nanoTime();
                try {
                    ChatClientResponse r = client.prompt().user(q).call().chatClientResponse();
                    String a = r.chatResponse().getResult().getOutput().getText();
                    @SuppressWarnings("unchecked")
                    List<Chunk> src = (List<Chunk>) r.context().getOrDefault(CTX_SOURCES, List.of());
                    ok++;
                    if (Boolean.TRUE.equals(r.context().get(CTX_DEGRADED))) degraded++;
                    if (src.isEmpty()) none++;
                    else if (CitationGuardAdvisor.valid(a, src.size())) grounded++;
                    else bad++;
                } catch (RuntimeException e) {
                    errors++;
                }
                lat.add((System.nanoTime() - t0) / 1_000_000);
            }
            results.put("hardened", new Tally(ok, grounded, degraded, none, errors, bad, pct(lat, 0.5), pct(lat, 0.99)));
        }

        System.out.println("chaos over " + n + " requests: vector store slow (200 ms) every 5th and down every 17th, primary model"
                + " down for requests 60-119, a hallucinated [S9] every 10th, a guest user every 25th");
        System.out.printf("%n%-9s %9s %9s %9s %10s %7s %12s %8s %8s%n", "pipeline", "answered", "grounded", "degraded", "no-source",
                "errors", "bad-cites", "p50 ms", "p99 ms");
        results.forEach((k, t) -> System.out.printf("%-9s %9d %9d %9d %10d %7d %12d %8d %8d%n", k, t.ok(), t.grounded(), t.degraded(),
                t.noSource(), t.errors(), t.badCitationsShown(), t.p50(), t.p99()));
        System.out.println("\ncircuit breaker transitions (virtual clock, 25 ms per request, threshold 3, open 500 ms):");
        model.transitions.forEach(s -> System.out.println("  " + s));
        System.out.printf("served by fallback %d; primary calls %d; citation retries %d, extractive fallbacks %d%n",
                model.servedBySecondary.get(), primary.calls.get(), guard.retried.get(), guard.extracted.get());

        Tally nv = results.get("naive"), hd = results.get("hardened");
        check(hd.errors() == 0 && hd.badCitationsShown() == 0 && hd.grounded() + hd.noSource() == n, "hardened: every answer grounded or refused");
        check(nv.errors() > 60 && nv.badCitationsShown() > 0, "naive: outage and vector failures reach users; bad citations shown");
        check(hd.p99() < nv.p99(), "deadlines cut the tail");
        check(model.transitions.size() >= 3 && model.transitions.get(model.transitions.size() - 1).contains("->CLOSED"), "breaker recovers");
        System.out.println("\nall ResilientRagOrchestrator self-checks passed");
    }
}
```

Output (one measured run; the counts are deterministic by construction, and p50/p99 are measured):

```text
chaos over 200 requests: vector store slow (200 ms) every 5th and down every 17th, primary model down for requests 60-119, a hallucinated [S9] every 10th, a guest user every 25th

pipeline   answered  grounded  degraded  no-source  errors    bad-cites   p50 ms   p99 ms
naive           133       114         0          6      67           19       53      260
hardened        200       190        49         10       0            0       47      127

circuit breaker transitions (virtual clock, 25 ms per request, threshold 3, open 500 ms):
  CLOSED->OPEN at t=1550ms (primary model 503 overloaded)
  OPEN->HALF_OPEN at t=2075ms (cool-down elapsed, probing)
  HALF_OPEN->OPEN at t=2075ms (primary model 503 overloaded)
  OPEN->HALF_OPEN at t=2575ms (cool-down elapsed, probing)
  HALF_OPEN->OPEN at t=2575ms (primary model 503 overloaded)
  OPEN->HALF_OPEN at t=3075ms (cool-down elapsed, probing)
  HALF_OPEN->CLOSED at t=3075ms (probe succeeded)
served by fallback 66; primary calls 149; citation retries 20, extractive fallbacks 0

all ResilientRagOrchestrator self-checks passed
```

Reading the table:

- **Naive:**
  - 67 errors: the 60-request outage plus vector-store failures thrown straight through;
  - 19 answers shown with bad citations;
  - 6 answers generated with zero sources, which is the ungrounded-answer failure;
  - a p99 that waits for the slowest leg.
- **Hardened:**
  - every request answered;
  - 49 degraded, matching exactly the requests where the vector leg was late or down;
  - 10 refused for lack of accessible sources: 8 guests, plus 2 paraphrased questions whose only match was in the
    missing vector leg;
  - 0 bad citations, after 20 strict retries and 0 extractive fallbacks;
  - 66 requests served by the fallback model during the outage window and probes.

---

## 4. Production failure modes and P99 debugging

### F1 · An MCP server "hangs" intermittently

- **Signature:** client-side timeouts at exactly the request timeout; the server's CPU is idle.
- **Root cause:** non-protocol output on stdout (a debug print, a library banner, a logging appender on stdout).
- **Fix:** all logs to stderr or files; set the logging level before any library initialises; add a CI test that
  launches the server and asserts every stdout line parses as JSON-RPC.

### F2 · Internal details appear in agent transcripts

- **Signature:** hostnames, SQL or stack fragments in tool errors shown to users.
- **Root cause:** raw exception messages returned as JSON-RPC errors or tool text.
- **Fix:** a handler wrapper that returns sanitized `isError` results with a reference id and logs the details
  server-side.

### F3 · Duplicate tickets, emails or orders

- **Root cause:** host retries after a timeout, and the tool has no idempotency key.
- **Fix:** a required `request_id` in the schema; the server deduplicates for a retention window and returns the
  original result.

### F4 · P99 tracks the slowest retriever

- **Root cause:** sequential retrieval, timeouts that do not cancel, or a per-request executor whose `close()`
  waits for the slow task.
- **Fix:** parallel legs on virtual threads, a deadline, `cancel(true)` on late legs, and fusion of whatever
  arrived, marked degraded.

### F5 · A provider incident becomes a full outage

- **Root cause:** a single model with no breaker; every request pays a timeout and then fails.
- **Fix:** a breaker plus a fallback in a different failure domain. Fallback quality is evaluated in advance; the
  fallback is not first tried during the incident.

### F6 · Answers cite sources that do not exist

- **Root cause:** the model invents citation markers; nobody checks them.
- **Fix:** citation validation against the provided set, a strict retry, an extractive fallback, and a metric on
  violation rate per model version.

### F7 · Confident answers for users who cannot see the source

- **Root cause:** ACL-filtered retrieval returned nothing and the model answered anyway, from parametric memory or
  from leaked context.
- **Fix:** no sources, no model call. ACL filtering inside retrieval (Folder 04 File 03), never after generation.

### F8 · The breaker flaps, or recovery overloads the primary

- **Root cause:** a threshold too low for the healthy error rate, or a half-open state that admits many requests.
- **Fix:** a threshold sized from `fⁿ`, one probe at a time, and gradual ramp-up after closing.

---

## 5. FAANG L7 bar-raiser Q&A chains

### Q1 · "Our LLM provider is 99.5%. The RAG endpoint needs 99.9%. How?"

- **L5 answer:** "Retry failed requests."
- **Why L5 fails at scale:** retries do not help a provider outage. They triple load on a struggling dependency, and
  the series product (98.8%) is the real ceiling.
- **L7 principal defense:**
  1. Do the arithmetic: series dependencies multiply; parallel alternatives multiply unavailability.
  2. Make the vector store and reranker optional with marked degradation; fail over the model to a second provider
     or region behind a breaker. That reaches 99.90% if failure domains are independent.
  3. Bound everything with a deadline budget that cancels late work.
  4. Measure availability per path (full, degraded, fallback) and the quality of each path on an evaluation set.

### Q2 · "Expose our internal APIs to agents through MCP. What could go wrong?"

- **L5 answer:** "Wrap each API in a tool."
- **Why L5 fails at scale:** identity in arguments (a confused deputy), raw errors leaking internals, retries
  duplicating side effects, stdout logging breaking sessions, and hundreds of tools bloating context (Folder 05
  File 03).
- **L7 principal defense:**
  1. Remote servers on Streamable HTTP with audience-bound OAuth; identity from the token, never from arguments.
  2. Strict input schemas, output schemas with structured content, and honest annotations, with policy enforced by
     the host.
  3. Sanitized `isError` results; `request_id` idempotency for side effects.
  4. Curated, task-level tools rather than one tool per endpoint, with routing on the host.

### Q3 · "Users report answers citing documents that don't exist."

- **L5 answer:** "Tell the model in the prompt not to do that."
- **L7 principal defense:**
  1. Validate citations mechanically against the provided sources, with a strict retry and an extractive fallback.
  2. Track the violation rate per model and prompt version as a release gate.
  3. Fix the root cause in the prompt and the source formatting (numbered, short, deduplicated), but never rely on
     it.

### Q4 · "The vector database is slow this week. What do you do right now, and structurally?"

- **L5 answer:** "Raise the timeout."
- **Why L5 fails at scale:** raising timeouts moves the vector store's tail into every user's latency and holds
  connections longer, which makes the incident worse.
- **L7 principal defense:**
  1. Now: keep the deadline, cancel the late leg, serve lexical-only answers marked degraded, and watch the degraded
     rate and answer quality.
  2. Structurally: a per-leg deadline, hedged requests for the vector leg (Folder 04 File 02), capacity and index
     health (Folder 03: filtered-search traps, HNSW memory), and an SLO on the degraded rate.

### Q5 · "Stdio or HTTP for enterprise MCP servers?"

- **L7 principal defense:**
  1. Stdio for local tools on a user's machine (IDE integrations), where identity is the OS user and the blast
     radius is that machine.
  2. Streamable HTTP for shared servers: OAuth, audit, rate limits, horizontal scaling, and no per-user process.
  3. Either way: schema validation, sanitized errors, idempotency, and logs off the protocol channel.

---

## 6. Invariants checklist

- [ ] Every stage has a deadline derived from the request's remaining budget; late work is cancelled, not abandoned.
- [ ] Optional dependencies degrade with a marker and a metric; required ones fail over across failure domains.
- [ ] The model fails over behind a breaker with one half-open probe; fallback quality is evaluated beforehand.
- [ ] No sources means no model call; ACLs are enforced inside retrieval.
- [ ] Every citation resolves to a provided source, or the answer is retried or replaced.
- [ ] MCP tools have strict input schemas, output schemas and honest annotations; host policy does not trust
      annotations.
- [ ] Tool exceptions become sanitized `isError` results; details go to server logs.
- [ ] Side-effecting tools require a `request_id` and deduplicate.
- [ ] Stdio servers never write anything but protocol messages to stdout.

## 7. References

1. Model Context Protocol specification 2025-11-25: tools, `isError`, `structuredContent`, output schemas, tool
   annotations; Java SDK `io.modelcontextprotocol.sdk:mcp` 2.1.0 (⚠ verify against the version you deploy).
2. Spring AI reference: MCP server Boot starters, `MethodToolCallbackProvider` (⚠ verify names for your version).
3. J. Dean, L. A. Barroso. *The Tail at Scale.* Communications of the ACM 56(2), 2013.
4. M. T. Nygard. *Release It! Design and Deploy Production-Ready Software,* 2nd ed., 2018: timeouts, circuit
   breakers, bulkheads.
5. Google SRE Book, chapter 22 *Addressing Cascading Failures* (deadline propagation, retries and load).
