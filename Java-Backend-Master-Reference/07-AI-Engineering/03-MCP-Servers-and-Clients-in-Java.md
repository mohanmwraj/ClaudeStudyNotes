# 7.3 · MCP Servers and Clients in Java — Protocol, Transports, Security, Bridging to Claude

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** Model Context Protocol specification revision **2025-11-25** and its changelog; MCP Java SDK 2.1.0 (`io.modelcontextprotocol.sdk`); Claude Platform docs, "MCP connector"; Spring AI MCP starters (2.0.2).
> **Verified stack:** MCP Java SDK **2.1.0** (`mcp-core`, `mcp-json-jackson3`), Spring Boot 4.1.2 (Tomcat) for the HTTP transport, `anthropic-java` 3.3.0 for the bridge, JDK 25. The stdio samples launch the server as a **real child process**; the HTTP sample runs a real servlet transport. The model in the bridge is the local mock from [7.1](01-Claude-API-Java-SDK.md).

---

## 1. What MCP standardizes 🔥

```
 Host app (IDE, agent, chat UI)
   └── MCP client  ◄── JSON-RPC 2.0 ──►  MCP server (your Java process)
        one client per server              exposes: tools (model-invoked actions)
                                                    resources (app-attached context, URIs)
                                                    prompts (user-invoked templates)
        offers back: sampling (server asks the host's LLM), roots, elicitation (server asks the user)
 Transports: stdio (child process; newline-delimited JSON on stdin/stdout)
             Streamable HTTP (one endpoint: POST for requests, optional GET SSE stream, Mcp-Session-Id header)
```

| Primitive | Controlled by | Example | Security note |
|---|---|---|---|
| **Tools** | The model | `lookup_order`, `refund_order` | They act with the server's credentials, so authorize per call; mark them with annotations |
| **Resources** | The application | `kb://policies/refund` | Treat content as untrusted data (prompt injection) |
| **Prompts** | The user | `summarize_ticket(ticketId)` | Templates can be shadowed by malicious servers; show them to users |

Revision history the Java SDK 2.1.0 supports (constants in `ProtocolVersions`): `2024-11-05`, `2025-03-26` (Streamable HTTP replaces HTTP+SSE), `2025-06-18` (structured tool output, elicitation, OAuth resource-server rules), and **`2025-11-25`**. The latest adds icons, URL-mode elicitation, tool calling inside sampling, experimental **tasks** (durable requests), OAuth Client ID Metadata Documents and OpenID Connect discovery. It also makes **HTTP 403 for invalid `Origin` headers** a MUST, and asks that input-validation failures be returned as **tool execution errors** so the model can self-correct.

---

## 2. stdio: the protocol on the wire, then the typed client 🔥

### 2.1 Runnable: an orders MCP server (tools + resource + prompt) driven by raw JSON-RPC and by `McpSyncClient`

<!-- run: javac cp=@p7 timeout=200 -->
```java
package demo.mcp;

import io.modelcontextprotocol.client.McpClient;
import io.modelcontextprotocol.client.McpSyncClient;
import io.modelcontextprotocol.client.transport.ServerParameters;
import io.modelcontextprotocol.client.transport.StdioClientTransport;
import io.modelcontextprotocol.json.McpJsonDefaults;
import io.modelcontextprotocol.json.McpJsonMapper;
import io.modelcontextprotocol.server.McpServer;
import io.modelcontextprotocol.server.McpServerFeatures.*;
import io.modelcontextprotocol.server.transport.StdioServerTransportProvider;
import io.modelcontextprotocol.spec.McpSchema.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.CountDownLatch;

public class OrdersMcp {
    public static void main(String[] args) throws Exception {
        // stdout is the protocol channel: a single log line printed there corrupts the JSON-RPC stream
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        if (args.length > 0 && args[0].equals("server")) { runServer(); return; }

        String java = ProcessHandle.current().info().command().orElseThrow();
        String cp = System.getProperty("java.class.path");

        // 1. the wire protocol: newline-delimited JSON-RPC 2.0 over the server process's stdin/stdout
        Process server = new ProcessBuilder(java, "-cp", cp, OrdersMcp.class.getName(), "server")
            .redirectError(ProcessBuilder.Redirect.DISCARD).start();
        var in = new BufferedReader(new InputStreamReader(server.getInputStream(), StandardCharsets.UTF_8));
        var out = new PrintWriter(new OutputStreamWriter(server.getOutputStream(), StandardCharsets.UTF_8), true);
        exchange(out, in, """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"raw-client","version":"0.1"}}}""");
        out.println("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}");     // a notification: no id, no reply
        exchange(out, in, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}");
        exchange(out, in, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"lookup_order\",\"arguments\":{\"orderId\":\"A-1001\"}}}");
        exchange(out, in, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"no_such_tool\",\"arguments\":{}}}");
        server.destroy();

        // 2. the same server through the SDK's typed client (it launches and owns the process)
        var transport = new StdioClientTransport(ServerParameters.builder(java).args("-cp", cp, OrdersMcp.class.getName(), "server").build(),
            McpJsonDefaults.getMapper());
        McpSyncClient client = McpClient.sync(transport).requestTimeout(Duration.ofSeconds(10))
            .clientInfo(new Implementation("orders-agent", "1.0.0")).build();
        try {
            InitializeResult init = client.initialize();
            System.out.println("SDK: negotiated protocol " + init.protocolVersion() + " with " + init.serverInfo().name() + " " + init.serverInfo().version());
            for (Tool t : client.listTools().tools())
                System.out.println("SDK: tool " + t.name() + " readOnly=" + t.annotations().readOnlyHint() + " destructive=" + t.annotations().destructiveHint());
            CallToolResult refund = client.callTool(new CallToolRequest("refund_order", Map.of("orderId", "A-1001", "amount", 250)));
            System.out.println("SDK: refund_order(250) isError=" + refund.isError() + " → " + ((TextContent) refund.content().getFirst()).text());
            ReadResourceResult policy = client.readResource(new ReadResourceRequest("kb://policies/refund"));
            System.out.println("SDK: resource → " + ((TextResourceContents) policy.contents().getFirst()).text());
            GetPromptResult prompt = client.getPrompt(new GetPromptRequest("summarize_ticket", Map.of("ticketId", "T-77")));
            System.out.println("SDK: prompt → " + prompt.messages().getFirst().role() + ": " + ((TextContent) prompt.messages().getFirst().content()).text());
        } finally {
            client.close();                                                      // also stops the server process
        }
    }

    static void exchange(PrintWriter out, BufferedReader in, String request) throws IOException {
        out.println(request.strip());
        String response = in.readLine();
        System.out.println("→ " + request.strip());
        System.out.println("← " + (response.length() > 330 ? response.substring(0, 330) + "…" : response));
    }

    static void runServer() throws InterruptedException {
        McpJsonMapper json = McpJsonDefaults.getMapper();
        var lookup = new SyncToolSpecification(Tool.builder()
                .name("lookup_order")
                .description("Look up an order's status by id. Use when the user asks where an order is.")
                .inputSchema(json, """
                    {"type":"object","properties":{"orderId":{"type":"string","description":"Order id, e.g. A-1001"}},"required":["orderId"]}""")
                .annotations(new ToolAnnotations("Look up order", true, false, true, false, null))
                .build(),
            (exchange, req) -> CallToolResult.builder()
                .addTextContent("Order " + req.arguments().get("orderId") + ": shipped on 2026-10-20, carrier DHL")
                .build());
        var refund = new SyncToolSpecification(Tool.builder()
                .name("refund_order")
                .description("Refund an order. Refunds above 100 require human approval.")
                .inputSchema(json, """
                    {"type":"object","properties":{"orderId":{"type":"string"},"amount":{"type":"number"}},"required":["orderId","amount"]}""")
                .annotations(new ToolAnnotations("Refund order", false, true, false, false, null))
                .build(),
            (exchange, req) -> {
                double amount = ((Number) req.arguments().get("amount")).doubleValue();
                return amount > 100
                    ? CallToolResult.builder().isError(true).addTextContent("Refund of " + amount + " needs human approval (limit 100).").build()
                    : CallToolResult.builder().addTextContent("Refunded " + amount).build();
            });
        var policy = new SyncResourceSpecification(Resource.builder().uri("kb://policies/refund").name("refund-policy")
                .mimeType("text/markdown").description("Customer refund policy").build(),
            (exchange, req) -> new ReadResourceResult(List.of(new TextResourceContents(req.uri(), "text/markdown",
                "Refunds within 30 days; above 100 requires a supervisor."))));
        var summarize = new SyncPromptSpecification(new Prompt("summarize_ticket", "Summarize a support ticket",
                List.of(new PromptArgument("ticketId", "Ticket id", true))),
            (exchange, req) -> new GetPromptResult("Ticket summary", List.of(new PromptMessage(Role.USER,
                new TextContent("Summarize ticket " + req.arguments().get("ticketId") + " in three bullet points: issue, impact, next step.")))));

        McpServer.sync(new StdioServerTransportProvider(json))
            .serverInfo("orders-mcp", "1.0.0")
            .instructions("Order support tools. Never refund without checking the policy resource.")
            .capabilities(ServerCapabilities.builder().tools(true).resources(false, false).prompts(false).build())
            .tools(lookup, refund).resources(policy).prompts(summarize)
            .build();
        new CountDownLatch(1).await();                                           // serve until the client kills the process
    }
}
```

Output (verified):

```
→ {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"raw-client","version":"0.1"}}}
← {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{"logging":{},"prompts":{"listChanged":false},"resources":{"subscribe":false,"listChanged":false},"tools":{"listChanged":true}},"serverInfo":{"name":"orders-mcp","version":"1.0.0"},"instructions":"Order support tools. Never refund without checking th…
→ {"jsonrpc":"2.0","id":2,"method":"tools/list"}
← {"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"lookup_order","description":"Look up an order's status by id. Use when the user asks where an order is.","inputSchema":{"type":"object","properties":{"orderId":{"type":"string","description":"Order id, e.g. A-1001"}},"required":["orderId"]},"annotations":{"title":"Look up order…
→ {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lookup_order","arguments":{"orderId":"A-1001"}}}
← {"jsonrpc":"2.0","id":3,"result":{"content":[{"type":"text","text":"Order A-1001: shipped on 2026-10-20, carrier DHL"}],"isError":false}}
→ {"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}
← {"jsonrpc":"2.0","id":4,"error":{"code":-32602,"message":"Unknown tool: invalid_tool_name","data":"Tool not found: no_such_tool"}}
SDK: negotiated protocol 2025-11-25 with orders-mcp 1.0.0
SDK: tool lookup_order readOnly=true destructive=false
SDK: tool refund_order readOnly=false destructive=true
SDK: refund_order(250) isError=true → Refund of 250.0 needs human approval (limit 100).
SDK: resource → Refunds within 30 days; above 100 requires a supervisor.
SDK: prompt → USER: Summarize ticket T-77 in three bullet points: issue, impact, next step.
```

* **Lifecycle:** `initialize` (the client proposes `protocolVersion` and capabilities, and the server answers with its own capabilities, `serverInfo` and `instructions`), then the `notifications/initialized` **notification** (no `id`, no reply), then requests. Both sides negotiated `2025-11-25`.
* **Capabilities are a contract.** The server advertised `tools` (with `listChanged`), `resources`, `prompts` and `logging`; clients must not call what isn't advertised.
* **Two kinds of errors:**
  * an unknown tool is a **protocol error** (JSON-RPC `error`, code `-32602`);
  * a tool that runs and fails returns a **result with `isError: true`** (the refund above the limit), which the model sees and can react to.
  Use the second for business and validation failures.
* **Tool annotations** (`readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`) let hosts ask for confirmation before destructive calls. They are **hints from the server**, not guarantees: never trust annotations from a server you don't control.
* **stdout belongs to the protocol.** The server sets logging to OFF, because one log line on stdout corrupts the JSON-RPC stream. The 2025-11-25 spec explicitly allows stdio servers to log to **stderr**: configure your logback console appender with `<target>System.err</target>` in server mode.

---

## 3. Streamable HTTP: remote servers, sessions, and the Origin check 🔥

### 3.1 Runnable: the servlet transport inside Spring Boot, with a wire log and a forged-Origin request

<!-- run: javac cp=@p7 timeout=200 -->
```java
package demo.mcphttp;

import io.modelcontextprotocol.client.McpClient;
import io.modelcontextprotocol.client.McpSyncClient;
import io.modelcontextprotocol.client.transport.HttpClientStreamableHttpTransport;
import io.modelcontextprotocol.json.McpJsonDefaults;
import io.modelcontextprotocol.server.McpServer;
import io.modelcontextprotocol.server.McpServerFeatures.SyncToolSpecification;
import io.modelcontextprotocol.server.McpSyncServer;
import io.modelcontextprotocol.server.transport.DefaultServerTransportSecurityValidator;
import io.modelcontextprotocol.server.transport.HttpServletStreamableServerTransportProvider;
import io.modelcontextprotocol.spec.McpSchema;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import java.io.IOException;
import java.net.URI;
import java.net.http.*;
import java.util.*;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.annotation.Bean;

public class StreamableHttpMcp {
    static final List<String> wire = Collections.synchronizedList(new ArrayList<>());

    @SpringBootConfiguration @EnableAutoConfiguration
    static class App {
        @Bean HttpServletStreamableServerTransportProvider mcpTransport() {
            return HttpServletStreamableServerTransportProvider.builder()
                .jsonMapper(McpJsonDefaults.getMapper())
                .mcpEndpoint("/mcp")
                .securityValidator(DefaultServerTransportSecurityValidator.builder()
                    .allowedOrigin("https://claude.ai").build())                  // browsers from other origins are refused
                .build();
        }
        @Bean ServletRegistrationBean<HttpServletStreamableServerTransportProvider> mcpServlet(HttpServletStreamableServerTransportProvider t) {
            return new ServletRegistrationBean<>(t, "/mcp");
        }
        @Bean(destroyMethod = "closeGracefully") McpSyncServer mcpServer(HttpServletStreamableServerTransportProvider t) {
            var json = McpJsonDefaults.getMapper();
            return McpServer.sync(t).serverInfo("orders-mcp-http", "1.0.0")
                .tools(new SyncToolSpecification(McpSchema.Tool.builder().name("lookup_order").description("Look up an order by id.")
                        .inputSchema(json, "{\"type\":\"object\",\"properties\":{\"orderId\":{\"type\":\"string\"}},\"required\":[\"orderId\"]}").build(),
                    (ex, req) -> McpSchema.CallToolResult.builder().addTextContent("Order " + req.arguments().get("orderId") + ": shipped").build()))
                .build();
        }
        @Bean FilterRegistrationBean<Filter> wireLog() {                          // records each HTTP exchange on /mcp
            var reg = new FilterRegistrationBean<Filter>((req, res, chain) -> {
                var rq = (HttpServletRequest) req; var rs = (HttpServletResponse) res;
                chain.doFilter(req, res);
                wire.add(String.format("%-6s accept=%s mcp-protocol-version=%s mcp-session-id=%s origin=%s → %d %s session=%s",
                    rq.getMethod(), rq.getHeader("Accept"), rq.getHeader("MCP-Protocol-Version"), mask(rq.getHeader("Mcp-Session-Id")),
                    rq.getHeader("Origin"), rs.getStatus(), rs.getContentType(), mask(rs.getHeader("Mcp-Session-Id"))));
            });
            reg.addUrlPatterns("/mcp");
            return reg;
        }
    }
    static String mask(String id) { return id == null ? null : "<" + id.length() + "-char id>"; }

    public static void main(String[] args) throws Exception {
        SpringApplication sa = new SpringApplication(App.class);
        sa.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
        sa.setDefaultProperties(Map.of("server.port", "0", "logging.level.root", "OFF", "server.shutdown", "immediate"));
        try (var ctx = sa.run()) {
            String base = "http://localhost:" + ((WebServerApplicationContext) ctx).getWebServer().getPort();

            McpSyncClient client = McpClient.sync(HttpClientStreamableHttpTransport.builder(base).endpoint("/mcp").build()).build();
            client.initialize();
            var result = client.callTool(new McpSchema.CallToolRequest("lookup_order", Map.of("orderId", "A-1001")));
            System.out.println("tool result: " + ((McpSchema.TextContent) result.content().getFirst()).text());
            client.close();
            Thread.sleep(300);
            synchronized (wire) { wire.forEach(w -> System.out.println("wire: " + w)); wire.clear(); }

            try (HttpClient http = HttpClient.newHttpClient()) {                 // a web page on another origin tries to talk to it
                var forged = HttpRequest.newBuilder(URI.create(base + "/mcp"))
                    .header("Content-Type", "application/json").header("Accept", "application/json, text/event-stream")
                    .header("Origin", "https://evil.example")
                    .POST(HttpRequest.BodyPublishers.ofString("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":"
                        + "{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"clientInfo\":{\"name\":\"x\",\"version\":\"1\"}}}")).build();
                var resp = http.send(forged, HttpResponse.BodyHandlers.ofString());
                System.out.println("forged Origin https://evil.example → HTTP " + resp.statusCode());
            }
        }
        System.out.println("context closed; live non-daemon threads: " + Thread.getAllStackTraces().keySet().stream()
            .filter(t -> t.isAlive() && !t.isDaemon() && t != Thread.currentThread()).map(Thread::getName).sorted().toList());
        System.exit(0);                         // the transport's session sweeper is non-daemon and would keep this JVM alive
    }
}
```

One verified run (the order in which concurrent requests finish can vary):

```
tool result: Order A-1001: shipped
wire: POST   accept=application/json, text/event-stream mcp-protocol-version=2025-11-25 mcp-session-id=null origin=null → 200 application/json;charset=UTF-8 session=<36-char id>
wire: GET    accept=text/event-stream mcp-protocol-version=2025-11-25 mcp-session-id=<36-char id> origin=null → 200 text/event-stream;charset=UTF-8 session=null
wire: POST   accept=application/json, text/event-stream mcp-protocol-version=2025-11-25 mcp-session-id=<36-char id> origin=null → 202 null session=null
wire: POST   accept=application/json, text/event-stream mcp-protocol-version=2025-11-25 mcp-session-id=<36-char id> origin=null → 200 text/event-stream;charset=UTF-8 session=null
wire: DELETE accept=null mcp-protocol-version=2025-11-25 mcp-session-id=<36-char id> origin=null → 200 null session=null
forged Origin https://evil.example → HTTP 403
context closed; live non-daemon threads: [streamable-http-server-transport-session-sweeper-1]
```

* **One endpoint, several verbs:**
  * `POST /mcp` carries every JSON-RPC message. Requests are answered as `application/json` or as an SSE stream; notifications get **202**.
  * The server issues an **`Mcp-Session-Id`** on `initialize`, and the client sends it on every later request, together with **`MCP-Protocol-Version`**.
  * An optional `GET` opens a server-to-client SSE stream for server-initiated messages.
  * `DELETE` ends the session.
* **DNS-rebinding protection:** with an Origin allow-list, a browser page from `https://evil.example` got **403**, which the 2025-11-25 spec now requires. Without it, any web page the user visits could drive a server bound to `localhost`. Bind local servers to `127.0.0.1`, validate `Origin`/`Host`, and require authentication for anything non-trivial.
* **Authorization** for HTTP servers is OAuth 2.1. The MCP server is a **resource server**: it validates access tokens issued by your authorization server, with audience bound to the MCP server, and advertises Protected Resource Metadata (RFC 9728). **Never pass the client's token through to downstream APIs** (the "confused deputy" problem); obtain separate credentials for those.
* 🧊 **Shutdown gotcha (MCP SDK 2.1.0):** the transport's `streamable-http-server-transport-session-sweeper-1` thread is **non-daemon** and survived context close, `destroy()` and `closeGracefully()` in this test, so a program that closes the context and returns from `main` (CLIs, some test setups) **never exits** (the first runs of this sample hung until killed). A normal SIGTERM shutdown still terminates (shutdown hooks don't wait for non-daemon threads). The demo ends with `System.exit(0)`.
* **Spring Boot shortcut:** the Spring AI MCP starters (`spring-ai-starter-mcp-server-webmvc`/`-webflux`, `spring-ai-starter-mcp-client`, 2.0.2) auto-configure the transports, and expose Spring AI tool callbacks as MCP tools (for example a `MethodToolCallbackProvider` over `@Tool` beans).

---

## 4. Connecting MCP tools to Claude ⚡

Three integration shapes:

| Shape | Who runs the MCP client | Works with | Notes |
|---|---|---|---|
| **MCP connector** (API beta `mcp-client-2025-11-20`, or `mcp-client-2026-09-15` with tool-list pinning) | Anthropic's API, server-side | **Public HTTP** servers only (Streamable HTTP or SSE) | Only **tools** (no resources or prompts); not eligible for zero data retention; needs `mcp_servers` **plus** an `mcp_toolset` entry ([7.1 §6](01-Claude-API-Java-SDK.md#6-a-production-shaped-call-compile-checked-needs-a-real-key)) |
| **Your app as MCP client + tool runner** (below) | Your JVM | Any transport, including stdio and private networks | You control auth, auditing, approvals and result filtering |
| **Spring AI MCP client** | Your Spring app | Any transport | MCP tools appear as Spring AI tool callbacks in `ChatClient` |

### 4.1 Runnable: Claude (mocked) → SDK tool runner → MCP client → MCP server process

<!-- run: javac cp=@p7mcp timeout=200 -->
```java
package demo.mcpbridge;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.JsonValue;
import com.anthropic.helpers.BetaToolRunner;
import com.anthropic.helpers.McpBetaTool;
import com.anthropic.models.beta.messages.*;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpServer;
import io.modelcontextprotocol.client.McpClient;
import io.modelcontextprotocol.client.McpSyncClient;
import io.modelcontextprotocol.client.transport.ServerParameters;
import io.modelcontextprotocol.client.transport.StdioClientTransport;
import io.modelcontextprotocol.json.McpJsonDefaults;
import io.modelcontextprotocol.server.McpServer;
import io.modelcontextprotocol.server.McpServerFeatures.SyncToolSpecification;
import io.modelcontextprotocol.server.transport.StdioServerTransportProvider;
import io.modelcontextprotocol.spec.McpSchema;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.CountDownLatch;

/** Claude (mocked) → SDK tool runner → MCP client → MCP server process over stdio. */
public class McpToClaudeBridge {
    static final ObjectMapper JSON = new ObjectMapper();

    @SuppressWarnings("unchecked")
    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        if (args.length > 0) { runMcpServer(); return; }

        String java = ProcessHandle.current().info().command().orElseThrow();
        McpSyncClient mcp = McpClient.sync(new StdioClientTransport(
                ServerParameters.builder(java).args("-cp", System.getProperty("java.class.path"), McpToClaudeBridge.class.getName(), "server").build(),
                McpJsonDefaults.getMapper())).build();
        HttpServer claude = scriptedClaude();
        AnthropicClient anthropic = AnthropicOkHttpClient.builder().apiKey("sk-ant-demo")
            .baseUrl("http://127.0.0.1:" + claude.getAddress().getPort()).build();
        try {
            mcp.initialize();
            List<McpBetaTool> bridged = new ArrayList<>();
            for (McpSchema.Tool t : mcp.listTools().tools()) {                      // adapt each MCP tool to a Claude tool
                Map<String, Object> schema = t.inputSchema();                         // MCP 2.x: the raw JSON Schema as a Map
                var props = BetaTool.InputSchema.Properties.builder();
                ((Map<String, Object>) schema.get("properties")).forEach((k, v) -> props.putAdditionalProperty(k, JsonValue.from(v)));
                @SuppressWarnings("unchecked") List<String> required = (List<String>) schema.getOrDefault("required", List.of());
                bridged.add(McpBetaTool.builder()
                    .name(t.name())
                    .definition(BetaTool.builder().name(t.name()).description(t.description())
                        .inputSchema(BetaTool.InputSchema.builder().properties(props.build()).required(required).build())
                        .build())
                    .runner(inputJson -> {
                        try {
                            Map<String, Object> input = JSON.readValue(inputJson, Map.class);
                            McpSchema.CallToolResult r = mcp.callTool(new McpSchema.CallToolRequest(t.name(), input));
                            String text = ((McpSchema.TextContent) r.content().getFirst()).text();
                            return BetaToolResultBlockParam.Content.ofString(Boolean.TRUE.equals(r.isError()) ? "ERROR: " + text : text);
                        } catch (Exception e) { throw new RuntimeException(e); }
                    })
                    .build());
            }
            System.out.println("bridged MCP tools: " + bridged.stream().map(McpBetaTool::name).toList());

            BetaToolRunner runner = anthropic.beta().messages().toolRunner(MessageCreateParams.builder()
                .model("claude-opus-5-5").maxTokens(16000L)
                .addUserMessage("Where is my order A-1001?").build());
            bridged.forEach(runner::addTool);
            BetaMessage last = null;
            for (BetaMessage m : runner) {
                last = m;
                m.content().forEach(b -> b.toolUse().ifPresent(tu -> System.out.println("Claude called " + tu.name() + " " + tu._input())));
            }
            System.out.println("final answer: " + last.content().getFirst().asText().text());
        } finally {
            anthropic.close();
            claude.stop(0);
            mcp.close();
        }
    }

    static void runMcpServer() throws InterruptedException {
        var json = McpJsonDefaults.getMapper();
        McpServer.sync(new StdioServerTransportProvider(json)).serverInfo("orders-mcp", "1.0.0")
            .tools(new SyncToolSpecification(McpSchema.Tool.builder().name("lookup_order")
                    .description("Look up an order's status by id. Use when the user asks where an order is.")
                    .inputSchema(json, "{\"type\":\"object\",\"properties\":{\"orderId\":{\"type\":\"string\"}},\"required\":[\"orderId\"]}").build(),
                (exchange, req) -> McpSchema.CallToolResult.builder()
                    .addTextContent("Order " + req.arguments().get("orderId") + ": shipped on 2026-10-20, carrier DHL").build()))
            .build();
        new CountDownLatch(1).await();
    }

    static HttpServer scriptedClaude() throws Exception {                         // calls lookup_order, then answers from the result
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/v1/messages", ex -> {
            JsonNode req = JSON.readTree(ex.getRequestBody());
            JsonNode last = req.get("messages").get(req.get("messages").size() - 1).get("content");
            String content, stop = "end_turn";
            if (last.isArray() && last.get(0).get("type").asText().equals("tool_result")) {
                content = "{\"type\":\"text\",\"text\":" + JSON.writeValueAsString("Your order shipped on 20 October with DHL. ("
                    + last.get(0).get("content").asText() + ")") + "}";
            } else {
                content = "{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"lookup_order\",\"input\":{\"orderId\":\"A-1001\"}}";
                stop = "tool_use";
            }
            byte[] out = ("{\"id\":\"msg_" + System.nanoTime() + "\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-opus-5-5\","
                + "\"content\":[" + content + "],\"stop_reason\":\"" + stop + "\",\"stop_sequence\":null,\"usage\":{\"input_tokens\":200,\"output_tokens\":30}}")
                .getBytes(StandardCharsets.UTF_8);
            ex.getResponseHeaders().add("content-type", "application/json");
            ex.sendResponseHeaders(200, out.length);
            ex.getResponseBody().write(out);
            ex.close();
        });
        server.start();
        return server;
    }
}
```

Output (verified):

```
bridged MCP tools: [lookup_order]
Claude called lookup_order {orderId=A-1001}
final answer: Your order shipped on 20 October with DHL. (Order A-1001: shipped on 2026-10-20, carrier DHL)
```

* `McpBetaTool` (official SDK helper) wraps a **name + a `BetaTool` definition + a runner function**. Here each MCP tool's JSON Schema (a `Map` in MCP SDK 2.x) became the Claude tool schema, and the runner forwarded the call to `mcp.callTool(…)`. MCP `isError` results were prefixed `ERROR:` so the model sees the failure.
* This is the place to enforce **policy**: an allow-list of tools per user, confirmation for `destructiveHint` tools, argument validation, size limits on results (a 5 MB resource dumped into context is a cost and injection hazard), and audit logs of every call.

---

## 5. Production failure modes & security checklist

| Symptom or risk | Cause | Mitigation |
|---|---|---|
| Client hangs or `JsonParseException` with a stdio server | Server logs to stdout | Log to stderr in server mode |
| Model performs unintended actions | **Tool poisoning**: malicious tool descriptions or results instruct the model; "rug pull" (server changes its tools after approval) | Vet servers; pin tool lists (`mcp-client-2026-09-15` pinning, or your own allow-list); show tool changes to users; human approval for destructive tools |
| Data exfiltration via chained tools | One tool reads secrets; another can send data out (open-world) | Separate trust zones; no "read sensitive + send anywhere" combinations in one session; egress controls |
| Local server driven by a web page | Missing Origin/Host validation (DNS rebinding) | Origin allow-list (403), bind to `127.0.0.1`, authentication |
| Confused deputy | Server forwards the client's token, or uses its own broad credentials for every user | Audience-bound tokens; per-user downstream authorization |
| Sessions leak memory | Clients never `DELETE` sessions; no sweeper | Session TTLs and sweeping; `disallowDelete` only if you accept that |
| JVM doesn't exit after close (CLIs/tests) | Non-daemon session sweeper (SDK 2.1.0) | Explicit exit; track SDK fixes |
| Tool calls time out | Long operations inside a request | Progress notifications, the experimental **tasks** utility (2025-11-25), or async patterns with polling |

---

## 6. Interview Q&A

<details><summary><b>Q1. 🔥 Explain tools vs resources vs prompts in MCP, and who controls each.</b></summary>

Tools are model-controlled actions with JSON Schema inputs (the model decides to call them). Resources are application-controlled context identified by URIs (the host decides what to attach). Prompts are user-controlled templates (the user picks them, e.g. slash commands). Each implies a different trust and approval model: tools need authorization and possibly confirmation, resources need injection-aware handling, and prompts should be visible to users.
</details>

<details><summary><b>Q2. 🔥 Walk through an MCP session over Streamable HTTP.</b></summary>

`POST /mcp` with `initialize` (protocol version and capabilities) returns the server's capabilities and an `Mcp-Session-Id` header. The client sends `notifications/initialized` (202). Subsequent POSTs carry the session ID and `MCP-Protocol-Version`, and responses come back as JSON or as an SSE stream. An optional GET opens a server-initiated SSE stream, and DELETE ends the session (all verified). The server must validate `Origin` (403 on invalid) and, for protected servers, validate OAuth access tokens as a resource server.
</details>

<details><summary><b>Q3. ⚡ Protocol error vs tool execution error: which should a server return for bad tool arguments?</b></summary>

A tool execution error: a normal result with `isError: true` and an explanatory message, so the model can correct itself (the 2025-11-25 spec clarifies this). Protocol errors (JSON-RPC `error`, e.g. `-32602` for an unknown tool) are for malformed requests the model can't fix by retrying with different content.
</details>

<details><summary><b>Q4. 🔥 What are the main security risks of letting an LLM use third-party MCP servers?</b></summary>

Tool poisoning (instructions hidden in descriptions or results), rug pulls (tools changing after approval), data exfiltration through tool combinations, confused-deputy token handling, overly broad server credentials, and DNS rebinding against local servers. Mitigations: vet and pin servers and tools, human approval for destructive or open-world tools, least-privilege credentials per user, Origin and authentication checks, result size limits and sanitization, and full audit logging.
</details>

<details><summary><b>Q5. ⚡ When would you use Anthropic's MCP connector vs running the MCP client yourself?</b></summary>

Use the connector for public HTTP MCP servers when you only need tools and want the least code: Anthropic connects server-side. Run your own client (SDK tool runner + MCP client, or Spring AI MCP client) for stdio or private-network servers, for resources and prompts, or when you need to enforce approval, auditing, per-user authorization, or result filtering in your own process.
</details>
