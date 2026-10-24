# 7.5 · Streaming LLM Responses over SSE — Spring MVC/WebFlux, Time-to-First-Token, Cancellation

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** WHATWG HTML Living Standard, "Server-sent events" (event-stream format, `Last-Event-ID`, reconnection); Claude Platform docs, "Streaming Messages"; Spring Framework 7 reference (async requests, reactive return types in MVC, `SseEmitter`); Reactor reference (`Flux.create`, cancellation).
> **Verified stack:** Spring Boot 4.1.2 (Tomcat, MVC with virtual threads), Spring AI 2.0.2, `anthropic-java` 3.3.0, Reactor 3.8, JDK 25. The "model" is a local mock that streams real Anthropic SSE events, **12 text deltas 100 ms apart**, and records whether its reader went away. That lets the samples measure time-to-first-token and **whether cancellation reaches the model**.

---

## 1. Two SSE hops 🔥

```
 browser/app ◄── SSE (your format) ── Spring endpoint ◄── SSE (Anthropic events) ── Claude API
   EventSource / fetch reader          Flux<ServerSentEvent> / SseEmitter            message_start, content_block_delta…
```

**The wire format** (`text/event-stream`, UTF-8): each event is a few `field: value` lines (`event:`, `data:`, `id:`, `retry:`), ended by a **blank line**. Lines starting with `:` are comments, which make a cheap **heartbeat**. A browser `EventSource` reconnects automatically and sends `Last-Event-ID`. It only supports GET without custom headers, so authenticated chat UIs usually read the stream with `fetch()` instead.

Why stream at all: perceived latency is **time to first token (TTFT)**, not total time, and long generations would otherwise hit HTTP timeouts (the SDKs require streaming for very large `max_tokens`).

---

## 2. Measured: Spring AI streaming through a Spring MVC SSE endpoint 🔥

### 2.1 Runnable: mock Claude stream → Spring AI `ChatClient.stream()` → `Flux<ServerSentEvent>` → HTTP client

<!-- run: javac cp=@p7 timeout=300 -->
```java
package demo.sse;

import com.sun.net.httpserver.HttpServer;
import java.io.*;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.ai.anthropic.AnthropicChatModel;
import org.springframework.ai.anthropic.AnthropicChatOptions;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.web.server.context.WebServerApplicationContext;
import org.springframework.context.annotation.*;
import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Flux;

public class StreamingEndToEnd {
    static final int DELTAS = 12;
    static final AtomicInteger upstreamWritten = new AtomicInteger();
    static volatile String upstreamOutcome = "", controllerOutcome = "no cancel signal";

    @RestController
    public static class ChatController {
        final ChatClient chat;
        public ChatController(ChatClient chat) { this.chat = chat; }

        @GetMapping(path = "/chat", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
        public Flux<ServerSentEvent<String>> chat(@RequestParam String q) {
            AtomicInteger sent = new AtomicInteger();
            return chat.prompt().user(q).stream().content()                                    // Flux<String> of text deltas
                .doOnNext(token -> sent.incrementAndGet())
                .doOnCancel(() -> controllerOutcome = "Spring cancelled the Flux after " + sent.get() + " tokens")
                .map(token -> ServerSentEvent.builder(token).event("token").build())
                .concatWith(Flux.just(ServerSentEvent.builder("[DONE]").event("done").build()));
        }
    }

    @SpringBootConfiguration @EnableAutoConfiguration @Import(ChatController.class)
    static class App {
        @Bean ChatClient chatClient() {
            return ChatClient.create(AnthropicChatModel.builder().options(AnthropicChatOptions.builder()
                .baseUrl("http://127.0.0.1:" + upstream.getAddress().getPort()).apiKey("sk-ant-demo")
                .model("claude-opus-5-5").maxTokens(1024).build()).build());
        }
    }
    static HttpServer upstream;

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        upstream = mockAnthropicStream();
        SpringApplication sa = new SpringApplication(App.class);
        sa.setBannerMode(org.springframework.boot.Banner.Mode.OFF);
        sa.setDefaultProperties(Map.of("server.port", "0", "logging.level.root", "OFF", "spring.threads.virtual.enabled", "true"));
        try (var ctx = sa.run(); HttpClient http = HttpClient.newHttpClient()) {
            URI uri = URI.create("http://localhost:" + ((WebServerApplicationContext) ctx).getWebServer().getPort() + "/chat?q=haiku");

            http.send(HttpRequest.newBuilder(uri).build(), HttpResponse.BodyHandlers.ofString());   // warm-up (lazy clients, JIT)
            // 1. read the whole stream
            long t0 = System.nanoTime();
            HttpResponse<InputStream> resp = http.send(HttpRequest.newBuilder(uri).build(), HttpResponse.BodyHandlers.ofInputStream());
            List<String> events = new ArrayList<>();
            long firstTokenMs = -1;
            try (var reader = new BufferedReader(new InputStreamReader(resp.body(), StandardCharsets.UTF_8))) {
                String line, event = null;
                while ((line = reader.readLine()) != null) {
                    if (line.startsWith("event:")) event = line.substring(6);
                    else if (line.startsWith("data:")) {
                        if (firstTokenMs < 0) firstTokenMs = (System.nanoTime() - t0) / 1_000_000;
                        events.add(event + "=" + line.substring(5));
                    }
                }
            }
            long totalMs = (System.nanoTime() - t0) / 1_000_000;
            System.out.println("1. content-type: " + resp.headers().firstValue("content-type").orElse("?"));
            System.out.println("   events (" + events.size() + "): " + events);
            System.out.println("   time to first token " + firstTokenMs + " ms, full response " + totalMs + " ms");
            Thread.sleep(300);
            System.out.println("   upstream: " + upstreamOutcome);

            // 2. the user closes the tab after 3 tokens: does generation upstream stop?
            HttpResponse<InputStream> resp2 = http.send(HttpRequest.newBuilder(uri).build(), HttpResponse.BodyHandlers.ofInputStream());
            var reader2 = new BufferedReader(new InputStreamReader(resp2.body(), StandardCharsets.UTF_8));
            int seen = 0;
            for (String line; seen < 3 && (line = reader2.readLine()) != null; ) if (line.startsWith("data:")) seen++;
            resp2.body().close();                                                               // disconnect
            Thread.sleep(DELTAS * 120 + 1500);
            System.out.println("2. client disconnected after 3 tokens; controller: " + controllerOutcome + "; upstream: " + upstreamOutcome);
        } finally {
            upstream.stop(0);
        }
    }

    /** Streams DELTAS text deltas, 100 ms apart, and records whether the reader went away. */
    static HttpServer mockAnthropicStream() throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
        server.createContext("/v1/messages", ex -> {
            ex.getRequestBody().readAllBytes();
            ex.getResponseHeaders().add("content-type", "text/event-stream");
            ex.sendResponseHeaders(200, 0);                                                    // chunked
            OutputStream out = ex.getResponseBody();
            int written = 0;
            try {
                send(out, "message_start", "{\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-opus-5-5\",\"content\":[],\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":12,\"output_tokens\":1}}}");
                send(out, "content_block_start", "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}");
                for (int i = 1; i <= DELTAS; i++) {
                    Thread.sleep(100);                                                         // the model "thinking" per token
                    send(out, "content_block_delta", "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"t" + i + " \"}}");
                    written = i;
                }
                send(out, "content_block_stop", "{\"type\":\"content_block_stop\",\"index\":0}");
                send(out, "message_delta", "{\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\",\"stop_sequence\":null},\"usage\":{\"output_tokens\":" + DELTAS + "}}");
                send(out, "message_stop", "{\"type\":\"message_stop\"}");
                upstreamOutcome = "generated all " + DELTAS + " deltas";
            } catch (IOException | InterruptedException e) {
                upstreamOutcome = "stopped after " + written + " of " + DELTAS + " deltas (" + e.getClass().getSimpleName() + ")";
            } finally {
                ex.close();
            }
        });
        server.start();
        return server;
    }
    static void send(OutputStream out, String event, String data) throws IOException {
        out.write(("event: " + event + "\ndata: " + data + "\n\n").getBytes(StandardCharsets.UTF_8));
        out.flush();
    }
}
```

One measured run (timings vary; the events and the cancellation outcome are deterministic):

```
1. content-type: text/event-stream
   events (13): [token=t1 , token=t2 , token=t3 , token=t4 , token=t5 , token=t6 , token=t7 , token=t8 , token=t9 , token=t10 , token=t11 , token=t12 , done=[DONE]]
   time to first token 113 ms, full response 1311 ms
   upstream: generated all 12 deltas
2. client disconnected after 3 tokens; controller: Spring cancelled the Flux after 5 tokens; upstream: generated all 12 deltas
```

* **Streaming works end to end:** the first token reached the HTTP client after **~120 ms**, while the full answer took ~1.3 s (12 × 100 ms). Users perceive the 120 ms. The warm-up request matters: the first call through a fresh application context paid well over a second of lazy initialization (client construction, class loading, JIT).
* **Spring MVC can return a `Flux<ServerSentEvent<…>>`** (Reactor on the classpath). With `spring.threads.virtual.enabled=true`, the servlet side doesn't pin a platform thread per open stream either ([6.2](../06-Spring-Microservices/02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md)). A terminal `done` event lets clients distinguish "finished" from "connection dropped".
* **Cancellation stopped at Spring AI.** After the client disconnected, Spring noticed (on a failed write, two tokens later) and **cancelled the `Flux`**, but the Spring AI 2.0.2 Anthropic stream kept reading from the API: the mock generated **all 12 deltas**. Against the real API, abandoned requests keep generating **billed output tokens** until `max_tokens` or the natural end. Under load (users closing tabs, retrying), that is pure waste.

### 2.2 Runnable: the official SDK closes the upstream when you close the stream

<!-- run: javac cp=@p7sdk timeout=120 -->
```java
package demo.sse;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.http.StreamResponse;
import com.anthropic.models.messages.*;
import com.sun.net.httpserver.HttpServer;
import java.io.*;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.Executors;

public class SdkStreamCancellation {
    static final int DELTAS = 12;
    static volatile String upstreamOutcome = "";

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        HttpServer upstream = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        upstream.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
        upstream.createContext("/v1/messages", ex -> {
            ex.getRequestBody().readAllBytes();
            ex.getResponseHeaders().add("content-type", "text/event-stream");
            ex.sendResponseHeaders(200, 0);
            OutputStream out = ex.getResponseBody();
            int written = 0;
            try {
                send(out, "{\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-opus-5-5\",\"content\":[],\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":12,\"output_tokens\":1}}}");
                send(out, "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}");
                for (int i = 1; i <= DELTAS; i++) {
                    Thread.sleep(100);
                    send(out, "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"t" + i + " \"}}");
                    written = i;
                }
                send(out, "{\"type\":\"message_stop\"}");
                upstreamOutcome = "generated all " + DELTAS + " deltas";
            } catch (IOException | InterruptedException e) {
                upstreamOutcome = "stopped after " + written + " of " + DELTAS + " deltas (" + e.getClass().getSimpleName() + ")";
            } finally { ex.close(); }
        });
        upstream.start();
        AnthropicClient client = AnthropicOkHttpClient.builder().apiKey("sk-ant-demo")
            .baseUrl("http://127.0.0.1:" + upstream.getAddress().getPort()).build();
        try {
            int seen = 0;
            try (StreamResponse<RawMessageStreamEvent> stream = client.messages().createStreaming(MessageCreateParams.builder()
                    .model("claude-opus-5-5").maxTokens(1024L).addUserMessage("haiku").build())) {
                var it = stream.stream().iterator();
                while (it.hasNext() && seen < 3) if (it.next().isContentBlockDelta()) seen++;
            }                                                                  // close() after 3 deltas = "the user went away"
            Thread.sleep(DELTAS * 100 + 800);
            System.out.println("official SDK: StreamResponse closed after " + seen + " deltas; upstream: " + upstreamOutcome);
        } finally {
            client.close();
            upstream.stop(0);
        }
    }
    static void send(OutputStream out, String data) throws IOException {
        String type = data.replaceAll(".*?\"type\":\"([a-z_]+)\".*", "$1");
        out.write(("event: " + type + "\ndata: " + data + "\n\n").getBytes(StandardCharsets.UTF_8));
        out.flush();
    }
}
```

One measured run:

```
official SDK: StreamResponse closed after 3 deltas; upstream: stopped after 6 of 12 deltas (IOException)
```

Closing the SDK's `StreamResponse` closes the HTTP connection. The mock noticed within a few writes and **stopped generating**. Closing the connection is the only cancellation signal a streaming HTTP API receives.

### 2.3 Runnable: a cancellable `Flux` bridge for Spring endpoints

<!-- run: javac cp=@p7mcp timeout=120 -->
```java
package demo.sse;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.anthropic.core.http.StreamResponse;
import com.anthropic.models.messages.*;
import com.sun.net.httpserver.HttpServer;
import java.io.*;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.Executors;
import reactor.core.publisher.Flux;
import reactor.core.scheduler.Schedulers;

public class CancellableClaudeFlux {
    /** Text deltas as a Flux whose cancellation closes the HTTP stream to the API. */
    static Flux<String> stream(AnthropicClient client, MessageCreateParams params) {
        return Flux.<String>create(sink -> {
            StreamResponse<RawMessageStreamEvent> response = client.messages().createStreaming(params);
            sink.onDispose(response::close);                                  // cancel, error or complete → close the connection
            try {
                response.stream()
                    .takeWhile(e -> !sink.isCancelled())
                    .forEach(e -> e.contentBlockDelta().flatMap(d -> d.delta().text()).ifPresent(t -> sink.next(t.text())));
                sink.complete();
            } catch (RuntimeException e) {
                if (!sink.isCancelled()) sink.error(e);
            }
        }).subscribeOn(Schedulers.boundedElastic());                          // the SDK stream blocks: keep it off event loops
    }

    static final int DELTAS = 12;
    static volatile String upstreamOutcome = "";

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger("ROOT")).setLevel(ch.qos.logback.classic.Level.OFF);
        HttpServer upstream = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        upstream.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
        upstream.createContext("/v1/messages", ex -> {
            ex.getRequestBody().readAllBytes();
            ex.getResponseHeaders().add("content-type", "text/event-stream");
            ex.sendResponseHeaders(200, 0);
            OutputStream out = ex.getResponseBody();
            int written = 0;
            try {
                send(out, "message_start", "{\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-opus-5-5\",\"content\":[],\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":12,\"output_tokens\":1}}}");
                send(out, "content_block_start", "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}");
                for (int i = 1; i <= DELTAS; i++) {
                    Thread.sleep(100);
                    send(out, "content_block_delta", "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"t" + i + " \"}}");
                    written = i;
                }
                send(out, "message_stop", "{\"type\":\"message_stop\"}");
                upstreamOutcome = "generated all " + DELTAS + " deltas";
            } catch (IOException | InterruptedException e) {
                upstreamOutcome = "stopped after " + written + " of " + DELTAS + " deltas";
            } finally { ex.close(); }
        });
        upstream.start();
        AnthropicClient client = AnthropicOkHttpClient.builder().apiKey("sk-ant-demo")
            .baseUrl("http://127.0.0.1:" + upstream.getAddress().getPort()).build();
        try {
            var params = MessageCreateParams.builder().model("claude-opus-5-5").maxTokens(1024L).addUserMessage("haiku").build();
            System.out.println("full stream: " + stream(client, params).collectList().block());
            Thread.sleep(300);
            System.out.println("   upstream: " + upstreamOutcome);
            System.out.println("take(3), i.e. the subscriber cancels: " + stream(client, params).take(3).collectList().block());
            Thread.sleep(DELTAS * 100 + 800);
            System.out.println("   upstream: " + upstreamOutcome);
        } finally {
            client.close();
            upstream.stop(0);
        }
    }
    static void send(OutputStream out, String event, String data) throws IOException {
        out.write(("event: " + event + "\ndata: " + data + "\n\n").getBytes(StandardCharsets.UTF_8));
        out.flush();
    }
}
```

One measured run:

```
full stream: [t1 , t2 , t3 , t4 , t5 , t6 , t7 , t8 , t9 , t10 , t11 , t12 ]
   upstream: generated all 12 deltas
take(3), i.e. the subscriber cancels: [t1 , t2 , t3 ]
   upstream: stopped after 5 of 12 deltas
```

`Flux.create` + `sink.onDispose(response::close)` ties the subscriber's cancellation (client disconnect, `take`, a timeout operator) to the SDK stream. The blocking SDK read is moved to `boundedElastic`, so it never runs on an event loop. Return this `Flux` (mapped to `ServerSentEvent`s) from the controller when you need cancellation to reach the model, or verify that your framework version propagates it with a test like §2.1.

---

## 3. Production checklist for streaming endpoints ⚡

| Concern | What to do |
|---|---|
| **Buffering proxies** | Reverse proxies and CDNs may buffer the whole response, so TTFT becomes the total time. nginx: `proxy_buffering off;` or send `X-Accel-Buffering: no`. Exclude `text/event-stream` from gzip filters, which also buffer |
| **Idle timeouts** | Load balancers drop "silent" connections (often 60 s). Send a heartbeat comment (`:\n\n`) every 15–30 s while the model thinks. Set `spring.mvc.async.request-timeout` deliberately (an unset value falls back to the container's default) |
| **Connection limits** | Browsers allow ~6 concurrent HTTP/1.1 connections per origin, and each open SSE stream uses one. Serve over HTTP/2, or multiplex streams |
| **Server resources** | Each open stream is an open request: use virtual threads (MVC) or WebFlux; cap concurrent streams per user; bound the Anthropic client's connection pool |
| **Cancellation** | Propagate client disconnects to the upstream request (§2.3); also set `max_tokens` so a runaway generation is bounded anyway |
| **Errors mid-stream** | HTTP 200 is already sent, so report errors as an `event: error` with a code, and let the client decide to retry. Upstream `overloaded_error` can arrive **inside** the stream after 200 |
| **Resumption** | Give events `id:`s; on reconnect with `Last-Event-ID`, either replay from a buffer or restart the turn explicitly (LLM output can't be "resumed" from the API) |
| **Tool use while streaming** | `input_json_delta` fragments are partial JSON: accumulate them and parse at `content_block_stop` (the SDK accumulators do this). With `eager_input_streaming`, validate the parsed input before running the tool ([7.1 §3](01-Claude-API-Java-SDK.md#3-tool-use-and-the-agent-loop-)) |
| **Observability** | Record TTFT, tokens/s, total time, output tokens, and the cancel rate per endpoint. Log `stop_reason` per stream |

---

## 4. Production failure modes & diagnostics

| Symptom | Cause | Confirm with | Fix |
|---|---|---|---|
| Tokens appear all at once at the end | A proxy or gzip filter buffering the stream | `curl -N` directly against the app vs through the proxy | Disable buffering for `text/event-stream` |
| Streams cut at ~60 s | LB or proxy idle timeout | Disconnects cluster at a fixed duration | Heartbeat comments; raise idle timeouts |
| Token spend high but users abandon answers | Cancellation not propagated upstream | Cancel rate vs generated tokens; the mock test of §2.1 | Cancellable bridge (§2.3); lower `max_tokens` |
| Threads exhausted with many open streams | Platform thread per stream (MVC without virtual threads) | Thread dumps, `tomcat.threads.busy` | Virtual threads or WebFlux; per-user stream caps |
| Client shows "connection closed" without a reason | Error after 200 not surfaced | Server logs show a mid-stream `error` event | Emit `event: error` with a code before closing |
| Partial JSON crash in tool streaming | Parsing `input_json_delta` fragments eagerly | Exceptions at the fragment parse | Accumulate until `content_block_stop`; validate |

---

## 5. Interview Q&A

<details><summary><b>Q1. 🔥 Why stream LLM responses, and what metric do you optimize?</b></summary>

Streaming cuts perceived latency to the time to first token (measured ~120 ms vs ~1.3 s total in the demo) and avoids HTTP timeouts on long generations. Track TTFT, tokens per second and total latency separately, plus the cancel rate. Streaming doesn't make generation faster; it makes waiting shorter for the user.
</details>

<details><summary><b>Q2. ⚡ What happens to an LLM request when the user closes the browser tab mid-stream?</b></summary>

Only if the disconnect propagates all the way up does the model stop. In the measured stack, Spring detected the disconnect and cancelled its `Flux`, but Spring AI 2.0.2 kept reading from the API, so the model generated every token anyway (billed). Closing the official SDK's `StreamResponse` closes the HTTP connection and stops generation. Bridge the SDK stream into a `Flux` that closes on dispose, and always bound `max_tokens`.
</details>

<details><summary><b>Q3. ⚡ `SseEmitter` vs returning `Flux<ServerSentEvent>` in Spring MVC vs WebFlux?</b></summary>

`SseEmitter` is the imperative MVC API: you call `send()` from any thread and `complete()` at the end. With virtual threads that is simple and efficient. Returning a `Flux` from an MVC controller lets Spring subscribe and write events as they arrive, with cancellation on disconnect. WebFlux does the same on Netty with non-blocking I/O end to end. All three produce the same wire format. Choose by stack ([6.2](../06-Spring-Microservices/02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md)) and make sure blocking SDK calls never run on event loops.
</details>

<details><summary><b>Q4. 🧊 Why might SSE work locally but arrive in one burst in production?</b></summary>

An intermediary is buffering: a reverse proxy (nginx `proxy_buffering`), a CDN, a compression filter, or an API gateway that collects whole responses. Disable buffering for `text/event-stream` (or send `X-Accel-Buffering: no`), exclude it from gzip, and verify with `curl -N` at each hop.
</details>
