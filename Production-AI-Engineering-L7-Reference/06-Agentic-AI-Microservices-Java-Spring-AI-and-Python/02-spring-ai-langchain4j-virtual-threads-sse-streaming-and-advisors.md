# 02 · Spring AI, LangChain4j, Virtual Threads, SSE Streaming, and Advisors

> **Folder:** `06-Agentic-AI-Microservices-Java-Spring-AI-and-Python/` · **File 2 of 3**
> **Anchoring code and specifications:** Spring AI **2.0.2** (`spring-ai-client-chat`: `ChatClient`, advisors,
> `ToolCallingAdvisor`, `MessageChatMemoryAdvisor`, `DefaultToolCallingManager`) · LangChain4j **1.22.0**
> (`AiServices`, `@Tool`, `ChatMemoryProvider`) · Spring Boot **4.1.2** WebFlux on Reactor Netty · JEP 444 (Virtual
> Threads, JDK 21) and JEP 491 (Synchronize Virtual Threads without Pinning, JDK 24) · WHATWG HTML, *Server-sent
> events* · J. D. C. Little, *A Proof for the Queuing Formula L = λW* (1961).
> **Code baseline:** Java 21 (JDK 25.0.4, `--release 21 -parameters`), compiled and run against the real jars
> resolved by Maven (`mvn dependency:build-classpath`), no network or API key · Python 3.10+ (CPython 3.14.5,
> stdlib `asyncio`).
> **Previous:** [01 · Agentic design patterns](01-agentic-design-patterns-react-plan-execute-reflection-and-dags.md) ·
> **Next:** [03 · Durable agent execution](03-durable-agent-execution-temporal-langgraph-checkpointers-and-hitl.md)

---

## 0. The thesis in one paragraph

LLM traffic breaks the assumptions Java services were tuned for. A request is not 50 ms; **it is a stream that
lives for the whole generation**, so at 200 requests/s with 500-token answers a gateway holds **3,160 concurrent
streams** (Little's law). Thread-per-request on a pool cannot hold that. Virtual threads can: 2,000 blocking agent
conversations finish in **0.20 s on virtual threads vs 4.52 s on a 64-thread pool**. WebFlux streams can too. Both
remove the thread pool's *implicit admission control*, so explicit admission control has to replace it.

The frameworks matter in the details. On the real Spring AI 2.0.2 and LangChain4j 1.22.0 jars, this file observes
behaviour that decides production outcomes:

- a custom `ChatModel` whose options are not `ToolCallingChatOptions` **silently drops every tool**;
- without `javac -parameters` the tool schema tells the model the argument is called **`arg0`**;
- `call()` is **lazy**, so nothing happens without `.content()`;
- a per-tool limit with `THROW` **returns** `finishReason=toolCallLimitExceeded` as if it were an answer;
- a PII redactor ordered after chat memory **stores the raw card number and replays it to the model on turn 2**;
- LangChain4j sends a throwing tool's **raw exception text to the model** by default.

And one rule pays for itself: **a client disconnect must cancel generation.** The naive bridge kept generating 200
of 200 tokens for a reader who left after 10.

---

## 1. First principles: why LLM traffic breaks thread-per-request

### 1.1 Little's law for streams

For any stable system, `L = λW`: mean concurrency equals arrival rate times mean time in system. For a streaming
LLM endpoint `W` is the whole stream, `W = TTFT + n_out × TPOT`, not a request/response round trip:

| λ (req/s) | output tokens | TPOT | TTFT | W | concurrent streams L | 1 MiB stacks | 200-thread pool max λ |
|---|---|---|---|---|---|---|---|
| 50 | 300 | 25 ms | 0.5 s | 8.0 s | 400 | 0.4 GiB | 25 /s |
| 200 | 500 | 30 ms | 0.8 s | 15.8 s | 3,160 | 3.1 GiB | 12.7 /s |
| 1,000 | 400 | 20 ms | 0.3 s | 8.3 s | 8,300 | 8.1 GiB | 24.1 /s |
| 200 | 4,000 (reasoning) | 30 ms | 8.0 s | 128 s | 25,600 | 25.0 GiB | 1.6 /s |

A 200-thread Tomcat pool serves at most `200 / W` requests per second, **12.7 req/s** for ordinary chat. The pool
is the bottleneck long before the CPU, and every queued request adds its wait to TTFT.

### 1.2 Virtual threads: what they change and what they do not

A virtual thread is a continuation scheduled on a small pool of carrier threads (a `ForkJoinPool` sized to the
cores). When it blocks on I/O (socket read, `Thread.sleep`, `BlockingQueue.take`), the JDK unmounts it and the
carrier runs another. Its stack lives on the heap as chunks, so idle virtual threads cost bytes to kilobytes, not a
reserved megabyte.

Measured below with LangChain4j: 2,000 conversations, each two 50 ms model calls and one 20 ms tool call, about
120 ms of blocking.

- **64-thread pool:** 4.52 s, 443 conversations/s. Little's ceiling is `64 / 0.12 = 533/s`.
- **Virtual threads:** 0.20 s, 10,121 conversations/s. The wall time is close to the 120 ms of a single
  conversation.

What virtual threads do **not** do:

1. **They do not add GPU capacity.** The pool was limiting concurrency *by accident*. Remove it and the gateway
   happily sends 3,160 concurrent requests to a model server whose goodput peaks at a fraction of that (Folder 02
   File 01). Past saturation the model server's latency rises and its throughput does not. Admission control has to
   become explicit: a semaphore or token-rate limiter per model deployment, sized from the server's measured
   goodput curve, returning 429 or queueing with a deadline (Folder 07 File 04).
2. **They do not fix pinning everywhere.** On JDK 21–23 a virtual thread blocked *inside* `synchronized` pins its
   carrier. JEP 491 (JDK 24) removed that for `synchronized`; native frames still pin. A client library that holds
   a monitor across a network call can serialize a JDK 21 service onto a handful of carriers (⚠ verify against your
   JDK and libraries with the `jdk.VirtualThreadPinned` JFR event).
3. **They do not bound memory.** Each in-flight conversation still holds its prompt, its chat memory and its
   response buffer.

### 1.3 Reactive or virtual threads?

They are complementary, not rivals:

- **Request/response** (`ChatClient.call()`, LangChain4j `AiServices`) is blocking code. Run it on virtual threads
  (Spring Boot: `spring.threads.virtual.enabled=true` for MVC/Tomcat executors) and write it sequentially.
- **Token streaming** is naturally a `Flux`. `ChatClient.stream()` returns `Flux<String>`, WebFlux writes each
  element as an SSE event and flushes it, and *cancellation is part of the protocol*: when the HTTP connection
  closes, Reactor Netty cancels the subscription and the cancel propagates up through every advisor to the model
  call. Section 1.5 shows why that matters.

### 1.4 SSE on the wire

Server-sent events are a text protocol over one long HTTP response with `Content-Type: text/event-stream`:

```text
id: 17
event: token
data: Hello

: hb

event: done
data: [DONE]

```

A blank line ends each event. A line beginning with `:` is a comment, which makes a free heartbeat. `id` lets a
reconnecting client send `Last-Event-ID` to resume. SSE beats WebSockets for token streaming because it is
unidirectional, plain HTTP (auth headers, load balancers, HTTP/2 multiplexing), and browsers reconnect
automatically. HTTP/1.1 browsers cap concurrent connections per origin at about six, so serve SSE over HTTP/2.

Three production details:

- **Heartbeats during long TTFT.** A reasoning model can think for tens of seconds. Proxies with idle timeouts
  (AWS ALB defaults to 60 s; nginx `proxy_read_timeout` 60 s) cut silent streams. The gateway below sends a `: hb`
  comment every 100 ms (seconds in production); it delivered 13 during a 300 ms think.
- **Anti-buffering.** `X-Accel-Buffering: no` (nginx), `Cache-Control: no-cache`, and no response compression for
  small events, since gzip buffers until it has a block. The measurement below shows the client's inter-token gaps
  match the generator's exactly (client p99 17.5 ms vs server-side 17.8 ms), so the transport adds nothing. The
  bimodal shape (p50 ≈ 0.1–0.4 ms, p99 ≈ 17 ms) is the generator's fixed-rate timer catching up after Windows
  timer ticks, not the network. In the final KB gate, the same code measured p50 4.9 / p99 7.4 ms on both sides:
  Windows' global timer resolution changes when other applications request a finer one. The invariant that matters
  held in both runs: the client's distribution equals the server's.
- **A terminal event.** Send `event: done` (with usage) so clients can tell completion from a dropped connection.

### 1.5 Cancellation economics

If a user closes the tab after 10 tokens of a 500-token answer and generation continues, the model server spends
490 tokens of decode on nobody. The cost is more than money:

- each orphaned sequence keeps its **KV cache blocks** and its **batch slot** until it finishes. On Llama-3-70B
  that is 327,680 B/token, so a 4K-token orphan holds 1.25 GiB of KV that live users are waiting for (Folder 01
  File 03, Folder 02 File 01);
- orphans inflate measured throughput while goodput falls.

Measured both ways, in Java and in Python:

- **hardened** (the HTTP subscription *is* the generation subscription): the model generated **10 of 200**, and
  cancellation reached it;
- **naive** (a callback SDK bridged into a sink or a worker thread): **200 of 200**, and nobody told it.

The OpenAI-compatible servers (vLLM, SGLang) abort a request when the client closes the connection, so the gateway
must close *its* upstream connection when *its* client leaves (⚠ verify per server and version).

---

## 2. Spring AI 2.0: ChatClient, advisors and tool calling

### 2.1 The advisor onion

`ChatClient` builds a `ChatClientRequest` (prompt plus a context map) and passes it through a chain of advisors
sorted by `getOrder()`. Lower values run first on the way in and last on the way out. The last link calls the
`ChatModel`. The built-in positions in 2.0.2, printed by the listing:

| Order | Advisor | Runs |
|---|---|---|
| `HIGHEST_PRECEDENCE` (+0) | your security advisors: redaction, policy, budgets | once per request |
| +200 | `MessageChatMemoryAdvisor` (`DEFAULT_CHAT_MEMORY_PRECEDENCE_ORDER`) | once per request |
| +300 | `ToolCallingAdvisor` (`DEFAULT_ORDER`): the tool loop | once per request; loops inside |
| > +300 | observability, breakers, per-call guards | **once per model call** |

Tool calling in 2.0 is an advisor that calls the rest of the chain repeatedly: model call → tool calls →
`ToolCallingManager.executeToolCalls` → append results → model call. An advisor placed inside it runs once per
round trip. The listing's trace shows `[>outer, >inner, <inner, >inner, <inner, <outer]` for one tool call: two
model calls, one request.

### 2.2 What the real jars do (each observed below)

1. **Custom `ChatModel` without tool-capable options drops tools silently.** `ChatClient` starts from
   `chatModel.getOptions().mutate()` and attaches tool callbacks only if that builder is a
   `ToolCallingChatOptions.Builder`. A hand-written model (a test double, an internal gateway adapter) that keeps the
   default `ChatOptions` gets `DefaultChatOptions`, zero tools, and no error. The model just answers without them.
2. **`-parameters` is part of the tool contract.** Spring AI derives the JSON schema from parameter names. Compiled
   without `-parameters`, the schema for `orderStatus(String orderId)` is
   `{"properties":{"arg0":…},"required":["arg0"]}`. The model must then guess that `arg0` is an order id, and a
   model that sends `orderId` anyway gets `null`. Spring Boot's Maven and Gradle plugins enable `-parameters`; a
   plain build does not.
3. **`call()` is lazy.** `prompt()…call()` returns a `CallResponseSpec`, and nothing reaches the model until
   `.content()`, `.chatResponse()` or `.entity()` runs. A fire-and-forget audit call written as `.call();` does
   nothing.
4. **Tool-loop limits.** `DefaultToolCallingManager.builder()` has `maxCallsPerTool`, `maxTotalToolCalls` and
   `onLimitExceeded`. Against a model that requests the same tool forever:
   - `maxCallsPerTool(3)` + `THROW`: 4 model calls and 3 executions, then the call **returns** normally with
     `finishReason=toolCallLimitExceeded` and the text "Tool call limit (3) exceeded…". A caller that does not
     check the finish reason shows that sentence to the user as the answer.
   - `maxCallsPerTool(3)` + `RETURN_ERROR_RESPONSE`: tool executions stop at 3, but the error goes back to the
     model, which asks again. **Model calls continue until something else stops them** (the listing's breaker at
     25).
   - unlimited: 25 executions and 25 model calls, stopped only by the breaker.

   So bound both executions *and* model calls: keep a breaker advisor inside the loop as the backstop.
5. **`getToolCallbacks()` returns `null`, not an empty list,** when a request has no tools.
6. **Memory is stored at the memory advisor's position.** `MessageChatMemoryAdvisor.before()` stores the request's
   last user message *as it sees it*. A redaction advisor ordered after memory (+210) redacts the prompt for this
   turn, but memory already holds the raw text and replays it on turn 2. The listing shows `stored=true,
   reached the model=true` for that ordering and `false/false` with redaction at `HIGHEST_PRECEDENCE`.
7. **Memory windows bound the prompt.** With `maxMessages(4)` the prompt stops growing at 5 messages (4 of history
   plus the new user message), and two conversation ids never mix.
8. **Advisors can short-circuit.** The token-budget advisor sits *inside* memory (so it counts history) and returns
   a refusal without calling the model. The model was called once; three later turns were rejected as history grew.
9. **Streaming cancellation propagates.** `stream().content().take(5)` cancelled the model's `Flux` after exactly 5
   tokens, and the outer advisor saw `doFinally(cancel)`.

### 2.3 `ToolContext`: identity is not an argument

`orderStatus(String orderId, ToolContext ctx)` exposes only `orderId` in the schema. The tenant comes from
`.toolContext(Map.of("tenant", "acme"))`, which the server sets from the authenticated request. If the tenant were
a tool argument, the model or a prompt injection could choose it. That is the confused deputy of Folder 05 File 02.
LangChain4j's `@ToolMemoryId` plays the same role.

---

## 3. LangChain4j 1.22: AiServices

### 3.1 The model

`AiServices.builder(SupportAgent.class)` generates a proxy for a plain interface:

- `@SystemMessage` and `@UserMessage` templates;
- `@MemoryId` selects a `ChatMemory` from a `ChatMemoryProvider`, one per conversation;
- `@Tool` methods become `ToolSpecification`s; the service runs the tool loop.

Explicit `@P(name = "orderId")` names make the schema independent of `-parameters`, which is a point in its favour
over Spring AI's reflection-only naming.

### 3.2 What the real jar does (each observed below)

1. **`maxSequentialToolsInvocations` is deprecated in 1.22.0**; `maxToolCallingRoundTrips(3)` replaces it. Against
   the stubborn model it throws after 4 model calls and 3 executions ("exceeded 3 tool calling round trips").
2. **A hallucinated tool name throws by default** (`RuntimeException: …no such tool exists. Most likely, it is a
   hallucination`). `hallucinatedToolNameStrategy` turns it into a tool result listing the real tools, and the
   model can recover.
3. **A throwing tool sends its raw exception message to the model by default.** The answer contained `payments-api
   503 for A-17`. Internal hostnames, SQL fragments and stack details reach the model and then the user. A
   `toolExecutionErrorHandler` should return a sanitized instruction ("do NOT retry, escalate").
4. **Parallel tool calls run sequentially unless enabled.** Two 100 ms tool calls in one model turn took 202 ms by
   default and 102 ms with `executeToolsConcurrently(virtual-thread executor)`. This is File 01's DAG at the model
   level.
5. **Memory stores the system message too.** After one tool round trip alice's memory is `[SYSTEM, USER, AI,
   TOOL_EXECUTION_RESULT, AI]`, so budget the window accordingly.

### 3.3 Choosing between them

| Concern | Spring AI 2.0 | LangChain4j 1.22 |
|---|---|---|
| Programming model | fluent `ChatClient` + advisor chain | declarative interface proxies (`AiServices`) |
| Cross-cutting concerns | advisors with explicit order (security, memory, tools, observability) | listeners, guardrails, request transformers, error handlers |
| Streaming | `Flux` (Reactor), WebFlux-native cancellation | `TokenStream` callbacks; bridge to `Flux` carefully (§1.5) |
| Tool schema names | reflection, needs `-parameters` | `@P(name=…)` explicit |
| Spring Boot integration | first-class (auto-config, Micrometer observations) | Spring Boot starters available |
| Fit | Spring shops that want the advisor model and Boot conventions | framework-neutral services, Quarkus/Helidon, agentic interfaces |

Either works. The decision is about which extension model your team will keep correct: an explicit, ordered
advisor chain, or annotations plus handlers.

---

## 4. Production code blueprints

### 4.1 Java 21 + Spring AI 2.0.2: advisors, memory, tools, limits and streaming

The scripted `ChatModel` stands in for any provider and records every `Prompt` it receives, so each claim in §2.2
is an assertion, not an opinion.

```java
// SpringAiAdvisorPipeline.java - Spring AI 2.0.2 ChatClient against a scripted in-process ChatModel (no network, no
// API key), exercising what production code actually depends on: the advisor chain as an onion ordered by
// precedence, where the built-in ToolCallingAdvisor (HIGHEST_PRECEDENCE+300) sits INSIDE chat memory (+200); a
// PII-redaction advisor whose position decides whether raw PII reaches memory and therefore the model on the next
// turn; a token-budget advisor that short-circuits BEFORE spending; per-conversation memory windows; @Tool methods
// with server-side ToolContext (the tenant is never a model-chosen argument); per-tool call limits that stop a
// runaway tool loop; and streaming in which a consumer that stops reading cancels generation upstream.
// Build: javac --release 21 -cp "$(cat cp-f06.txt)" (spring-ai-client-chat 2.0.2 and its dependencies).
package dev.l7.ai.inference;

import io.micrometer.observation.ObservationRegistry;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Pattern;
import org.slf4j.LoggerFactory;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.client.ChatClientRequest;
import org.springframework.ai.chat.client.ChatClientResponse;
import org.springframework.ai.chat.client.advisor.MessageChatMemoryAdvisor;
import org.springframework.ai.chat.client.advisor.ToolCallingAdvisor;
import org.springframework.ai.chat.client.advisor.api.Advisor;
import org.springframework.ai.chat.client.advisor.api.CallAdvisor;
import org.springframework.ai.chat.client.advisor.api.CallAdvisorChain;
import org.springframework.ai.chat.client.advisor.api.StreamAdvisor;
import org.springframework.ai.chat.client.advisor.api.StreamAdvisorChain;
import org.springframework.ai.chat.memory.ChatMemory;
import org.springframework.ai.chat.memory.InMemoryChatMemoryRepository;
import org.springframework.ai.chat.memory.MessageWindowChatMemory;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.ToolResponseMessage;
import org.springframework.ai.chat.messages.UserMessage;
import org.springframework.ai.chat.metadata.ChatResponseMetadata;
import org.springframework.ai.chat.metadata.DefaultUsage;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.model.Generation;
import org.springframework.ai.chat.model.ToolContext;
import org.springframework.ai.chat.prompt.ChatOptions;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.ai.model.tool.ToolCallLimitBehavior;
import org.springframework.ai.model.tool.ToolCallingChatOptions;
import org.springframework.ai.model.tool.ToolCallingManager;
import org.springframework.ai.support.ToolCallbacks;
import org.springframework.ai.tool.annotation.Tool;
import org.springframework.ai.tool.annotation.ToolParam;
import org.springframework.core.Ordered;
import reactor.core.publisher.Flux;

public final class SpringAiAdvisorPipeline {

    // ------------------------------------------------------------------ a scripted model (stands in for any provider)
    /** Records every Prompt it receives. "stubborn" mode asks for the same tool forever (the classic agent loop). */
    static final class ScriptedModel implements ChatModel {
        final List<Prompt> seen = Collections.synchronizedList(new ArrayList<>());
        final AtomicInteger streamed = new AtomicInteger();
        final AtomicBoolean streamCancelled = new AtomicBoolean();
        volatile boolean stubborn;
        final boolean toolCapableOptions;

        ScriptedModel(boolean toolCapableOptions) { this.toolCapableOptions = toolCapableOptions; }

        ScriptedModel() { this(true); }

        /** ChatClient copies these and attaches tools ONLY if the builder is a ToolCallingChatOptions.Builder. */
        @Override
        public ChatOptions getOptions() {
            return toolCapableOptions ? ToolCallingChatOptions.builder().build() : ChatOptions.builder().build();
        }

        static int tokens(Prompt p) {
            return p.getInstructions().stream().mapToInt(m -> m.getText() == null ? 0 : m.getText().length() / 4 + 4).sum();
        }

        @Override
        public ChatResponse call(Prompt p) {
            seen.add(p);
            Message last = p.getInstructions().get(p.getInstructions().size() - 1);
            boolean toolsOffered = p.getOptions() instanceof ToolCallingChatOptions o && o.getToolCallbacks() != null
                    && !o.getToolCallbacks().isEmpty();                              // null, not empty, when no tools
            AssistantMessage out;
            if (last instanceof ToolResponseMessage tr && !stubborn) {
                out = new AssistantMessage("Answer from tool: " + tr.getResponses().get(0).responseData());
            } else if (toolsOffered && (stubborn || last.getText().contains("order"))) {
                out = AssistantMessage.builder().content("")
                        .toolCalls(List.of(new AssistantMessage.ToolCall("call_" + seen.size(), "function", "orderStatus",
                                "{\"orderId\":\"A-17\"}"))).build();
            } else {
                out = new AssistantMessage("echo(" + p.getInstructions().size() + " msgs): " + last.getText());
            }
            return new ChatResponse(List.of(new Generation(out)),
                    ChatResponseMetadata.builder().usage(new DefaultUsage(tokens(p), 12)).build());
        }

        @Override
        public Flux<ChatResponse> stream(Prompt p) {
            seen.add(p);
            return Flux.interval(Duration.ofMillis(3)).take(200)                      // ~TPOT 3 ms, 200 tokens max
                    .map(i -> new ChatResponse(List.of(new Generation(new AssistantMessage("t" + i + " ")))))
                    .doOnNext(r -> streamed.incrementAndGet())
                    .doOnCancel(() -> streamCancelled.set(true));                     // a real client aborts the HTTP call
        }
    }

    // ------------------------------------------------------------------ tools
    public static final class OrderTools {
        final AtomicInteger calls = new AtomicInteger();

        @Tool(description = "Look up the shipping status of one order by its id")
        public String orderStatus(@ToolParam(description = "order id, e.g. A-17") String orderId, ToolContext ctx) {
            calls.incrementAndGet();
            return ctx.getContext().get("tenant") + "/" + orderId + ": delayed, carrier ETA 3 days";   // tenant from server
        }
    }

    // ------------------------------------------------------------------ advisors
    /** Records entry/exit so the onion order is visible. */
    record TraceAdvisor(String name, int order, List<String> log) implements CallAdvisor, StreamAdvisor {
        @Override public String getName() { return name; }

        @Override public int getOrder() { return order; }

        @Override
        public ChatClientResponse adviseCall(ChatClientRequest req, CallAdvisorChain chain) {
            log.add(">" + name);
            ChatClientResponse r = chain.nextCall(req);
            log.add("<" + name);
            return r;
        }

        @Override
        public Flux<ChatClientResponse> adviseStream(ChatClientRequest req, StreamAdvisorChain chain) {
            log.add(">" + name);
            return chain.nextStream(req).doFinally(s -> log.add("<" + name + "(" + s + ")"));
        }
    }

    /** Redacts card numbers and e-mail addresses from the user message. Its ORDER is the security property. */
    record PiiRedactionAdvisor(int order) implements CallAdvisor, StreamAdvisor {
        static final Pattern CARD = Pattern.compile("\\b(?:\\d[ -]?){12,15}\\d\\b");
        static final Pattern EMAIL = Pattern.compile("[\\w.+-]+@[\\w-]+\\.[\\w.]+");

        static String redact(String s) { return EMAIL.matcher(CARD.matcher(s).replaceAll("[CARD]")).replaceAll("[EMAIL]"); }

        ChatClientRequest scrub(ChatClientRequest req) {
            Prompt p = req.prompt().augmentUserMessage(u -> u.mutate().text(redact(u.getText())).build());
            return req.mutate().prompt(p).build();
        }

        @Override public String getName() { return "pii-redaction"; }

        @Override public int getOrder() { return order; }

        @Override public ChatClientResponse adviseCall(ChatClientRequest req, CallAdvisorChain chain) { return chain.nextCall(scrub(req)); }

        @Override
        public Flux<ChatClientResponse> adviseStream(ChatClientRequest req, StreamAdvisorChain chain) { return chain.nextStream(scrub(req)); }
    }

    /** Refuses over-budget prompts WITHOUT calling the model: placed inside memory so it counts the history too. */
    record TokenBudgetAdvisor(int maxPromptTokens, AtomicInteger rejected) implements CallAdvisor {
        @Override public String getName() { return "token-budget"; }

        @Override public int getOrder() { return Advisor.DEFAULT_CHAT_MEMORY_PRECEDENCE_ORDER + 50; }

        @Override
        public ChatClientResponse adviseCall(ChatClientRequest req, CallAdvisorChain chain) {
            int est = ScriptedModel.tokens(req.prompt());
            if (est <= maxPromptTokens) return chain.nextCall(req);
            rejected.incrementAndGet();
            AssistantMessage msg = new AssistantMessage("Request too large (" + est + " > " + maxPromptTokens + " tokens).");
            return ChatClientResponse.builder().chatResponse(new ChatResponse(List.of(new Generation(msg))))
                    .context(req.context()).context("budget.rejected", true).build();
        }
    }

    /** Last-resort breaker inside the tool loop: no configuration mistake may produce an unbounded loop. */
    record ModelCallBreaker(int max, AtomicInteger calls) implements CallAdvisor {
        @Override public String getName() { return "model-call-breaker"; }

        @Override public int getOrder() { return Ordered.LOWEST_PRECEDENCE - 1; }

        @Override
        public ChatClientResponse adviseCall(ChatClientRequest req, CallAdvisorChain chain) {
            if (calls.incrementAndGet() > max) throw new IllegalStateException("breaker: more than " + max + " model calls");
            return chain.nextCall(req);
        }
    }

    static ChatClient.Builder client(ScriptedModel m, ToolCallingManager mgr) {
        return ChatClient.builder(m, ObservationRegistry.NOOP, null, null, ToolCallingAdvisor.builder().toolCallingManager(mgr));
    }

    static ChatMemory memory(int window) {
        return MessageWindowChatMemory.builder().chatMemoryRepository(new InMemoryChatMemoryRepository()).maxMessages(window).build();
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    static String render(Message m) {
        if (m instanceof ToolResponseMessage t) return "TOOL:" + t.getResponses().get(0).responseData();
        if (m instanceof AssistantMessage a && a.hasToolCalls())
            return "ASSISTANT:toolCall " + a.getToolCalls().get(0).name() + a.getToolCalls().get(0).arguments();
        return m.getMessageType() + ":" + m.getText();
    }

    static String flatten(Prompt p) {
        return String.join(" | ", p.getInstructions().stream().map(SpringAiAdvisorPipeline::render).toList());
    }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME))
                .setLevel(ch.qos.logback.classic.Level.WARN);
        System.out.printf("order constants: memory advisor %d (HIGHEST+%d), ToolCallingAdvisor %d (HIGHEST+%d)%n",
                Advisor.DEFAULT_CHAT_MEMORY_PRECEDENCE_ORDER, Advisor.DEFAULT_CHAT_MEMORY_PRECEDENCE_ORDER - Ordered.HIGHEST_PRECEDENCE,
                ToolCallingAdvisor.DEFAULT_ORDER, ToolCallingAdvisor.DEFAULT_ORDER - Ordered.HIGHEST_PRECEDENCE);
        ToolCallingManager limited = ToolCallingManager.builder().maxCallsPerTool(3).onLimitExceeded(ToolCallLimitBehavior.THROW).build();

        // 0. a custom ChatModel whose getOptions() is plain ChatOptions: the tools are dropped without any error
        ScriptedModel plain = new ScriptedModel(false);
        OrderTools t0 = new OrderTools();
        String a0 = client(plain, limited).build().prompt().user("where is my order A-17?").tools(t0)
                .toolContext(Map.of("tenant", "acme")).call().content();
        System.out.println("\n0. model with plain ChatOptions: options seen=" + plain.seen.get(0).getOptions().getClass().getSimpleName()
                + ", tool executions " + t0.calls.get() + ", answer: " + a0);
        check(t0.calls.get() == 0, "tools silently dropped");
        ScriptedModel lazy = new ScriptedModel();
        client(lazy, limited).build().prompt().user("audit this").call();         // no content()/chatResponse()/entity()
        System.out.println("   call() without a terminal method: model invoked " + lazy.seen.size() + " times");
        check(lazy.seen.isEmpty(), "CallResponseSpec is lazy");

        // 1. the schema the model is given is derived from parameter NAMES: compile with -parameters or it says arg0
        boolean named = OrderTools.class.getMethod("orderStatus", String.class, ToolContext.class).getParameters()[0].isNamePresent();
        String schema = ToolCallbacks.from(new OrderTools())[0].getToolDefinition().inputSchema().replaceAll("\\s+", "");
        System.out.println("\n1. compiled with -parameters=" + named + "; tool input schema: " + schema);
        check(named && schema.contains("\"orderId\""), "parameter names reach the schema (javac -parameters)");

        // the onion: an advisor outside the tool loop runs once per request, one inside runs once per model call
        ScriptedModel m = new ScriptedModel();
        List<String> log = Collections.synchronizedList(new ArrayList<>());
        OrderTools tools = new OrderTools();
        ChatClient c = client(m, limited).defaultAdvisors(new TraceAdvisor("outer", Ordered.HIGHEST_PRECEDENCE + 100, log),
                new TraceAdvisor("inner", ToolCallingAdvisor.DEFAULT_ORDER + 100, log)).build();
        String answer = c.prompt().user("where is my order A-17?").tools(tools).toolContext(Map.of("tenant", "acme")).call().content();
        System.out.println("   tool loop: " + answer);
        System.out.println("   advisor trace " + log + " | model calls " + m.seen.size() + ", tool executions " + tools.calls.get());
        System.out.println("   2nd prompt the model saw: " + flatten(m.seen.get(1)).replace("\n", " "));
        check(answer.contains("acme/A-17") && m.seen.size() == 2 && tools.calls.get() == 1, "one tool round trip");
        check(log.equals(List.of(">outer", ">inner", "<inner", ">inner", "<inner", "<outer")), "inner advisor runs per model call");

        // 2. a runaway tool loop (the model asks for the same tool forever) under three tool-calling managers
        System.out.println("\n2. stubborn model, ModelCallBreaker(25) as the backstop inside the tool loop:");
        ToolCallingManager returnErr = ToolCallingManager.builder().maxCallsPerTool(3)
                .onLimitExceeded(ToolCallLimitBehavior.RETURN_ERROR_RESPONSE).build();
        ToolCallingManager unlimited = ToolCallingManager.builder().unlimitedCallsPerTool().unlimitedTotalToolCalls().build();
        Map<String, ToolCallingManager> managers = new java.util.LinkedHashMap<>();
        managers.put("maxCallsPerTool(3)+THROW", limited);
        managers.put("maxCallsPerTool(3)+RETURN_ERROR_RESPONSE", returnErr);
        managers.put("unlimited", unlimited);
        Map<String, String> finish = new java.util.HashMap<>();
        for (var e : managers.entrySet()) {
            ScriptedModel loop = new ScriptedModel();
            loop.stubborn = true;
            OrderTools tl = new OrderTools();
            AtomicInteger calls = new AtomicInteger();
            String outcome;
            try {
                ChatResponse lr = client(loop, e.getValue()).defaultAdvisors(new ModelCallBreaker(25, calls)).build()
                        .prompt().user("order?").tools(tl).toolContext(Map.of("tenant", "acme")).call().chatResponse();
                outcome = "RETURNED finishReason=" + lr.getResult().getMetadata().getFinishReason() + ", text=\""
                        + lr.getResult().getOutput().getText() + "\"";
                finish.put(e.getKey(), lr.getResult().getMetadata().getFinishReason());
            } catch (RuntimeException ex) {
                outcome = "THREW " + ex.getClass().getSimpleName() + ": " + ex.getMessage();
                finish.put(e.getKey(), "breaker");
            }
            System.out.printf("   %-41s model calls %2d, tool executions %2d -> %s%n", e.getKey(), Math.min(calls.get(), 25),
                    tl.calls.get(), outcome);
        }
        check("toolCallLimitExceeded".equals(finish.get("maxCallsPerTool(3)+THROW")), "THROW surfaces as a finish reason");
        check("breaker".equals(finish.get("unlimited")), "without limits only the breaker stops the loop");

        // 3. PII redaction: ordered AFTER memory, raw PII is stored and replayed to the model on turn 2
        for (int order : new int[] {Advisor.DEFAULT_CHAT_MEMORY_PRECEDENCE_ORDER + 10, Ordered.HIGHEST_PRECEDENCE}) {
            ScriptedModel pm = new ScriptedModel();
            ChatMemory mem = memory(20);
            ChatClient pc = client(pm, limited).defaultAdvisors(MessageChatMemoryAdvisor.builder(mem).build(),
                    new PiiRedactionAdvisor(order)).build();
            pc.prompt().user("my card is 4111 1111 1111 1111, email jo@example.com").advisors(a -> a.param(ChatMemory.CONVERSATION_ID, "c1")).call().content();
            pc.prompt().user("what did I just tell you?").advisors(a -> a.param(ChatMemory.CONVERSATION_ID, "c1")).call().content();
            boolean leaked = pm.seen.stream().map(SpringAiAdvisorPipeline::flatten).anyMatch(s -> s.contains("4111"));
            boolean stored = mem.get("c1").stream().anyMatch(x -> x.getText().contains("4111"));
            String where = order == Ordered.HIGHEST_PRECEDENCE ? "redaction BEFORE memory (HIGHEST)" : "redaction AFTER memory (+210)  ";
            System.out.printf("%n3. %s: raw card stored in memory=%s, reached the model=%s%n", where, stored, leaked);
            if (order == Ordered.HIGHEST_PRECEDENCE) check(!leaked && !stored, "hardened ordering");
            else check(leaked && stored, "naive ordering leaks on turn 2 via memory");
        }

        // 4. memory window and isolation: conversation ids never mix; the window bounds the prompt
        ScriptedModel mm = new ScriptedModel();
        ChatMemory win = memory(4);
        ChatClient mc = client(mm, limited).defaultAdvisors(MessageChatMemoryAdvisor.builder(win).build()).build();
        for (int i = 1; i <= 8; i++) {
            String cid = i % 2 == 0 ? "alice" : "bob";
            mc.prompt().user("turn " + i + " from " + cid).advisors(a -> a.param(ChatMemory.CONVERSATION_ID, cid)).call().content();
        }
        List<Integer> sizes = mm.seen.stream().map(p -> p.getInstructions().size()).toList();
        System.out.println("\n4. prompt sizes (messages) over 8 turns, 2 conversations, window 4: " + sizes);
        System.out.println("   alice memory: " + win.get("alice").stream().map(x -> x.getText()).filter(s -> s.startsWith("turn")).toList());
        check(win.get("alice").stream().noneMatch(x -> x.getText().contains("bob")) && win.get("alice").size() == 4 && sizes.get(7) == 5, "isolation + window");

        // 5. a budget that refuses BEFORE spending tokens (it sits inside memory, so history counts)
        ScriptedModel bm = new ScriptedModel();
        AtomicInteger rejected = new AtomicInteger();
        ChatClient bc = client(bm, limited).defaultAdvisors(MessageChatMemoryAdvisor.builder(memory(50)).build(),
                new TokenBudgetAdvisor(120, rejected)).build();
        String big = "x".repeat(300);
        for (int i = 0; i < 4; i++) bc.prompt().user("q" + i + " " + big).advisors(a -> a.param(ChatMemory.CONVERSATION_ID, "b")).call().content();
        System.out.println("\n5. token budget 120: model called " + bm.seen.size() + "x, rejected " + rejected.get() + "x as history grew");
        check(bm.seen.size() == 1 && rejected.get() == 3, "budget short-circuits without a model call");

        // 6. streaming: a consumer that takes 5 tokens and leaves cancels the model stream through every advisor
        ScriptedModel sm = new ScriptedModel();
        List<String> slog = Collections.synchronizedList(new ArrayList<>());
        ChatClient sc = client(sm, limited).defaultAdvisors(new TraceAdvisor("outer", Ordered.HIGHEST_PRECEDENCE + 100, slog),
                new PiiRedactionAdvisor(Ordered.HIGHEST_PRECEDENCE)).build();
        List<String> got = sc.prompt().user("tell me a long story").stream().content().take(5).collectList().block();
        Thread.sleep(50);
        System.out.println("\n6. stream: client kept " + got.size() + " tokens; model produced " + sm.streamed.get()
                + " of 200 before cancellation; cancelled upstream=" + sm.streamCancelled.get() + "; trace " + slog);
        check(got.size() == 5 && sm.streamCancelled.get() && sm.streamed.get() <= 8, "cancellation reaches the model");
        System.out.println("\nall SpringAiAdvisorPipeline self-checks passed");
    }
}
```

Output (verified; deterministic):

```text
order constants: memory advisor -2147483448 (HIGHEST+200), ToolCallingAdvisor -2147483348 (HIGHEST+300)

0. model with plain ChatOptions: options seen=DefaultChatOptions, tool executions 0, answer: echo(1 msgs): where is my order A-17?
   call() without a terminal method: model invoked 0 times

1. compiled with -parameters=true; tool input schema: {"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"orderId":{"type":"string","description":"orderid,e.g.A-17"}},"required":["orderId"],"additionalProperties":false}
   tool loop: Answer from tool: "acme/A-17: delayed, carrier ETA 3 days"
   advisor trace [>outer, >inner, <inner, >inner, <inner, <outer] | model calls 2, tool executions 1
   2nd prompt the model saw: USER:where is my order A-17? | ASSISTANT:toolCall orderStatus{"orderId":"A-17"} | TOOL:"acme/A-17: delayed, carrier ETA 3 days"

2. stubborn model, ModelCallBreaker(25) as the backstop inside the tool loop:
   maxCallsPerTool(3)+THROW                  model calls  4, tool executions  3 -> RETURNED finishReason=toolCallLimitExceeded, text="Tool call limit (3) exceeded for tool 'orderStatus'. No further calls to this tool are allowed in this turn."
   maxCallsPerTool(3)+RETURN_ERROR_RESPONSE  model calls 25, tool executions  3 -> THREW IllegalStateException: breaker: more than 25 model calls
   unlimited                                 model calls 25, tool executions 25 -> THREW IllegalStateException: breaker: more than 25 model calls

3. redaction AFTER memory (+210)  : raw card stored in memory=true, reached the model=true

3. redaction BEFORE memory (HIGHEST): raw card stored in memory=false, reached the model=false

4. prompt sizes (messages) over 8 turns, 2 conversations, window 4: [1, 1, 3, 3, 5, 5, 5, 5]
   alice memory: [turn 6 from alice, turn 8 from alice]

5. token budget 120: model called 1x, rejected 3x as history grew

6. stream: client kept 5 tokens; model produced 5 of 200 before cancellation; cancelled upstream=true; trace [>outer, <outer(cancel)]

all SpringAiAdvisorPipeline self-checks passed
```

### 4.2 Java 21 + LangChain4j 1.22.0: AiServices, guards, errors, parallel tools and virtual threads

```java
// Lc4jAgentService.java - LangChain4j 1.22.0 AiServices against a scripted in-process ChatModel (no network): the
// declarative agent interface with @MemoryId-isolated MessageWindowChatMemory, @Tool methods with explicit @P names
// and @ToolMemoryId (server-side identity, never a model-chosen argument), the loop guard maxToolCallingRoundTrips
// (maxSequentialToolsInvocations is deprecated in 1.22), hallucinated tool names and throwing tools fed back to the
// model as errors instead of crashing the request,
// parallel tool calls executed concurrently, and the virtual-thread argument measured: 2,000 concurrent blocking
// conversations on virtual threads vs a 64-thread platform pool (Little's law: throughput = concurrency / latency).
// Build: javac --release 21 -cp "$(cat cp-f06.txt)" (langchain4j 1.22.0 and its dependencies).
package dev.l7.ai.inference;

import dev.langchain4j.agent.tool.P;
import dev.langchain4j.agent.tool.Tool;
import dev.langchain4j.agent.tool.ToolExecutionRequest;
import dev.langchain4j.agent.tool.ToolMemoryId;
import dev.langchain4j.data.message.AiMessage;
import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.data.message.ToolExecutionResultMessage;
import dev.langchain4j.data.message.UserMessage;
import dev.langchain4j.memory.chat.MessageWindowChatMemory;
import dev.langchain4j.model.chat.ChatModel;
import dev.langchain4j.model.chat.request.ChatRequest;
import dev.langchain4j.model.chat.response.ChatResponse;
import dev.langchain4j.model.output.FinishReason;
import dev.langchain4j.model.output.TokenUsage;
import dev.langchain4j.service.AiServices;
import dev.langchain4j.service.MemoryId;
import dev.langchain4j.service.SystemMessage;
import dev.langchain4j.service.tool.ToolErrorHandlerResult;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;

public final class Lc4jAgentService {

    // ------------------------------------------------------------------ the agent contract
    interface SupportAgent {
        @SystemMessage("You are a support agent. Use tools for facts; never guess order status.")
        String chat(@MemoryId String conversationId, @dev.langchain4j.service.UserMessage String message);
    }

    // ------------------------------------------------------------------ scripted model
    enum Mode { NORMAL, STUBBORN, HALLUCINATE, FAILING_TOOL, PARALLEL }

    static final class ScriptedModel implements ChatModel {
        final List<ChatRequest> seen = Collections.synchronizedList(new ArrayList<>());
        volatile Mode mode = Mode.NORMAL;
        final long latencyMs;

        ScriptedModel(long latencyMs) { this.latencyMs = latencyMs; }

        static ToolExecutionRequest req(String id, String name, String args) {
            return ToolExecutionRequest.builder().id(id).name(name).arguments(args).build();
        }

        @Override
        public ChatResponse doChat(ChatRequest r) {
            seen.add(r);
            if (latencyMs > 0) AgentDagExecutor.sleepQuietly(latencyMs);           // TTFT + decode of a short reply
            List<ChatMessage> msgs = r.messages();
            ChatMessage last = msgs.get(msgs.size() - 1);
            int n = seen.size();
            AiMessage out;
            if (last instanceof ToolExecutionResultMessage && mode != Mode.STUBBORN) {
                StringBuilder sb = new StringBuilder("Answer:");
                for (int i = msgs.size() - 1; i >= 0 && msgs.get(i) instanceof ToolExecutionResultMessage t; i--)
                    sb.append(" [").append(t.toolName()).append(" -> ").append(t.text()).append("]");
                out = AiMessage.from(sb.toString());
            } else if (!r.toolSpecifications().isEmpty() && last instanceof UserMessage u && u.singleText().contains("order")
                    || mode == Mode.STUBBORN) {
                out = switch (mode) {
                    case HALLUCINATE -> AiMessage.from(req("c" + n, "lookupOrderV2", "{\"id\":\"A-17\"}"));
                    case FAILING_TOOL -> AiMessage.from(req("c" + n, "refund", "{\"orderId\":\"A-17\",\"cents\":2500}"));
                    case PARALLEL -> AiMessage.from(req("c" + n + "a", "carrierEta", "{\"orderId\":\"A-17\"}"),
                            req("c" + n + "b", "carrierEta", "{\"orderId\":\"A-18\"}"));
                    default -> AiMessage.from(req("c" + n, "orderStatus", "{\"orderId\":\"A-17\"}"));
                };
            } else {
                out = AiMessage.from("echo(" + msgs.size() + " msgs)");
            }
            return ChatResponse.builder().aiMessage(out).tokenUsage(new TokenUsage(40 * msgs.size(), 12))
                    .finishReason(out.hasToolExecutionRequests() ? FinishReason.TOOL_EXECUTION : FinishReason.STOP).build();
        }
    }

    // ------------------------------------------------------------------ tools
    static final class OrderTools {
        final AtomicInteger calls = new AtomicInteger();
        final Map<Object, Integer> perConversation = new ConcurrentHashMap<>();
        final long toolMs;

        OrderTools(long toolMs) { this.toolMs = toolMs; }

        @Tool("Look up the shipping status of one order by its id")
        public String orderStatus(@ToolMemoryId Object conversation, @P(name = "orderId", value = "order id, e.g. A-17") String orderId) {
            calls.incrementAndGet();
            perConversation.merge(conversation, 1, Integer::sum);
            if (toolMs > 0) AgentDagExecutor.sleepQuietly(toolMs);
            return orderId + " delayed (conversation " + conversation + ")";
        }

        @Tool("Carrier delivery estimate in days for one order")
        public String carrierEta(@P(name = "orderId", value = "order id") String orderId) {
            calls.incrementAndGet();
            AgentDagExecutor.sleepQuietly(100);
            return orderId + ": 3 days";
        }

        @Tool("Refund an order")
        public String refund(@P(name = "orderId", value = "order id") String orderId, @P(name = "cents", value = "amount") int cents) {
            calls.incrementAndGet();
            throw new IllegalStateException("payments-api 503 for " + orderId);
        }
    }

    static AiServices<SupportAgent> base(ChatModel m, OrderTools tools, Map<Object, MessageWindowChatMemory> memories) {
        return AiServices.builder(SupportAgent.class).chatModel(m).tools(tools)
                .chatMemoryProvider(id -> memories.computeIfAbsent(id, k -> MessageWindowChatMemory.builder().id(k).maxMessages(10).build()));
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    static String kinds(ChatRequest r) {
        return r.messages().stream().map(m -> m.type().name()).toList().toString();
    }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME))
                .setLevel(ch.qos.logback.classic.Level.OFF);

        // 1. tool loop + per-conversation memory
        ScriptedModel m = new ScriptedModel(0);
        OrderTools tools = new OrderTools(0);
        Map<Object, MessageWindowChatMemory> mem = new ConcurrentHashMap<>();
        SupportAgent agent = base(m, tools, mem).build();
        String a1 = agent.chat("alice", "where is my order A-17?");
        String a2 = agent.chat("bob", "hello");
        System.out.println("1. alice: " + a1);
        System.out.println("   bob:   " + a2 + " | model requests " + m.seen.size() + ", 2nd request messages " + kinds(m.seen.get(1)));
        System.out.println("   tool spec offered: " + m.seen.get(0).toolSpecifications().stream()
                .filter(s -> s.name().equals("orderStatus")).findFirst().orElseThrow().parameters().properties().keySet()
                + " (the @ToolMemoryId parameter is not in the schema)");
        System.out.println("   memory alice " + mem.get("alice").messages().stream().map(x -> x.type().name()).toList()
                + " | bob " + mem.get("bob").messages().stream().map(x -> x.type().name()).toList());
        check(a1.contains("conversation alice") && mem.get("alice").messages().size() == 5 && mem.get("bob").messages().size() == 3,
                "tool round trip, memory isolated per @MemoryId");

        // 2. runaway loop: maxToolCallingRoundTrips is the guard
        ScriptedModel sm = new ScriptedModel(0);
        sm.mode = Mode.STUBBORN;
        OrderTools st = new OrderTools(0);
        try {
            base(sm, st, new ConcurrentHashMap<>()).maxToolCallingRoundTrips(3).build().chat("c", "order?");
            check(false, "loop must be stopped");
        } catch (RuntimeException e) {
            System.out.println("\n2. stubborn model, maxToolCallingRoundTrips(3): " + e.getClass().getSimpleName() + " after "
                    + sm.seen.size() + " model calls, " + st.calls.get() + " tool executions: " + e.getMessage());
            check(st.calls.get() <= 4, "guard bounds tool executions");
        }

        // 3. a hallucinated tool name: default vs a strategy that tells the model what exists
        ScriptedModel hm = new ScriptedModel(0);
        hm.mode = Mode.HALLUCINATE;
        String hDefault;
        try {
            hDefault = "answer: " + base(hm, new OrderTools(0), new ConcurrentHashMap<>()).build().chat("h", "order A-17?");
        } catch (RuntimeException e) {
            hDefault = "THREW " + e.getClass().getSimpleName() + ": " + e.getMessage();
        }
        ScriptedModel hm2 = new ScriptedModel(0);
        hm2.mode = Mode.HALLUCINATE;
        String hFixed = base(hm2, new OrderTools(0), new ConcurrentHashMap<>())
                .hallucinatedToolNameStrategy(r -> ToolExecutionResultMessage.from(r,
                        "Error: no tool named '" + r.name() + "'. Available: orderStatus, carrierEta, refund."))
                .build().chat("h", "order A-17?");
        System.out.println("\n3. hallucinated tool 'lookupOrderV2', default:  " + hDefault);
        System.out.println("   with hallucinatedToolNameStrategy: " + hFixed);
        check(hFixed.contains("no tool named"), "error fed back to the model");

        // 4. a tool that throws: the request fails, or the model sees a sanitized error and can recover/escalate
        ScriptedModel fm = new ScriptedModel(0);
        fm.mode = Mode.FAILING_TOOL;
        String fDefault;
        try {
            fDefault = "answer: " + base(fm, new OrderTools(0), new ConcurrentHashMap<>()).build().chat("f", "refund order A-17");
        } catch (RuntimeException e) {
            fDefault = "THREW " + e.getClass().getSimpleName() + ": " + e.getMessage();
        }
        ScriptedModel fm2 = new ScriptedModel(0);
        fm2.mode = Mode.FAILING_TOOL;
        String fHandled = base(fm2, new OrderTools(0), new ConcurrentHashMap<>())
                .toolExecutionErrorHandler((err, ctx) -> ToolErrorHandlerResult.text(
                        "refund failed: payments unavailable; do NOT retry, escalate to a human (ref " + ctx.toolExecutionRequest().id() + ")"))
                .build().chat("f", "refund order A-17");
        System.out.println("\n4. tool throws, default:  " + fDefault);
        System.out.println("   with toolExecutionErrorHandler: " + fHandled);
        check(fHandled.contains("escalate"), "sanitized error reaches the model");

        // 5. parallel tool calls in one model turn: sequential vs executeToolsConcurrently()
        for (boolean concurrent : new boolean[] {false, true}) {
            ScriptedModel pm = new ScriptedModel(0);
            pm.mode = Mode.PARALLEL;
            AiServices<SupportAgent> b = base(pm, new OrderTools(0), new ConcurrentHashMap<>());
            if (concurrent) b.executeToolsConcurrently(Executors.newVirtualThreadPerTaskExecutor());
            SupportAgent pa = b.build();
            pa.chat("w", "order warmup");
            long t0 = System.nanoTime();
            String r = pa.chat("p", "eta for order A-17 and A-18?");
            long ms = (System.nanoTime() - t0) / 1_000_000;
            System.out.printf("%stwo carrierEta calls (100 ms each), %s: %d ms -> %s%n", concurrent ? "   " : "\n5. ",
                    concurrent ? "executeToolsConcurrently" : "sequential (default)    ", ms, r);
            check(concurrent ? ms < 180 : ms >= 195, "parallel tool calls overlap only when enabled");
        }

        // 6. virtual threads vs a platform pool for blocking agent calls (2 model calls x 50 ms + 1 tool call x 20 ms)
        int conversations = 2_000;
        System.out.println("\n6. " + conversations + " concurrent conversations, each ~120 ms of blocking I/O (2 model calls + 1 tool):");
        for (String kind : new String[] {"platform pool (64 threads)", "virtual threads"}) {
            ScriptedModel vm = new ScriptedModel(50);
            OrderTools vt = new OrderTools(20);
            SupportAgent va = base(vm, vt, new ConcurrentHashMap<>()).build();
            va.chat("warm", "order warmup");
            long t0 = System.nanoTime();
            try (ExecutorService ex = kind.startsWith("virtual") ? Executors.newVirtualThreadPerTaskExecutor() : Executors.newFixedThreadPool(64)) {
                List<Future<String>> fs = new ArrayList<>();
                for (int i = 0; i < conversations; i++) {
                    String id = "u" + i;
                    fs.add(ex.submit(() -> va.chat(id, "where is order A-" + id + "?")));
                }
                for (Future<String> f : fs) check(f.get().contains("conversation u"), "every conversation completed with its own memory id");
            }
            double s = (System.nanoTime() - t0) / 1e9;
            System.out.printf("   %-27s %5.2f s wall, %6.0f conversations/s (Little: concurrency %d / 0.12 s = %.0f/s ceiling)%n",
                    kind, s, conversations / s, kind.startsWith("virtual") ? conversations : 64,
                    (kind.startsWith("virtual") ? conversations : 64) / 0.12);
            check(vt.perConversation.size() == conversations + 1, "tool saw every conversation id");
        }
        System.out.println("\nall Lc4jAgentService self-checks passed");
    }
}
```

Output (one measured run on the i5-11260H, `-XX:ActiveProcessorCount=4`; sections 1–4 are deterministic, and the
timings in 5–6 vary run to run while the assertions hold):

```text
1. alice: Answer: [orderStatus -> A-17 delayed (conversation alice)]
   bob:   echo(2 msgs) | model requests 3, 2nd request messages [SYSTEM, USER, AI, TOOL_EXECUTION_RESULT]
   tool spec offered: [orderId] (the @ToolMemoryId parameter is not in the schema)
   memory alice [SYSTEM, USER, AI, TOOL_EXECUTION_RESULT, AI] | bob [SYSTEM, USER, AI]

2. stubborn model, maxToolCallingRoundTrips(3): RuntimeException after 4 model calls, 3 tool executions: Something is wrong, exceeded 3 tool calling round trips (maxToolCallingRoundTrips)

3. hallucinated tool 'lookupOrderV2', default:  THREW RuntimeException: The LLM is trying to execute the 'lookupOrderV2' tool, but no such tool exists. Most likely, it is a hallucination. You can override this default strategy by setting the hallucinatedToolNameStrategy on the AiService
   with hallucinatedToolNameStrategy: Answer: [lookupOrderV2 -> Error: no tool named 'lookupOrderV2'. Available: orderStatus, carrierEta, refund.]

4. tool throws, default:  answer: Answer: [refund -> payments-api 503 for A-17]
   with toolExecutionErrorHandler: Answer: [refund -> refund failed: payments unavailable; do NOT retry, escalate to a human (ref c1)]

5. two carrierEta calls (100 ms each), sequential (default)    : 202 ms -> Answer: [carrierEta -> A-18: 3 days] [carrierEta -> A-17: 3 days]
   two carrierEta calls (100 ms each), executeToolsConcurrently: 102 ms -> Answer: [carrierEta -> A-18: 3 days] [carrierEta -> A-17: 3 days]

6. 2000 concurrent conversations, each ~120 ms of blocking I/O (2 model calls + 1 tool):
   platform pool (64 threads)   4.52 s wall,    443 conversations/s (Little: concurrency 64 / 0.12 s = 533/s ceiling)
   virtual threads              0.20 s wall,  10121 conversations/s (Little: concurrency 2000 / 0.12 s = 16667/s ceiling)

all Lc4jAgentService self-checks passed
```

### 4.3 Java 21 + Spring Boot 4.1.2 WebFlux: the SSE gateway, measured from a real client

```java
// SseStreamingGateway.java - a real Spring Boot 4.1.2 WebFlux (Reactor Netty) server streaming LLM tokens as
// Server-Sent Events from Spring AI's ChatClient.stream(), and a JDK HttpClient consumer that measures it. Shows the
// production details: SSE framing with ids and a terminal `done` event, heartbeat comments during a long time to
// first token (reasoning models, proxies with idle timeouts), anti-buffering headers, and the property that pays for
// itself: a client disconnect CANCELS generation upstream. The naive endpoint bridges a callback-style generator into a
// sink without wiring cancellation, so it keeps "generating" (burning GPU) for a reader who has left.
// Build: javac --release 21 -cp "$(cat cp-f06.txt)" (spring-boot-starter-webflux 4.1.2 + spring-ai-client-chat 2.0.2).
package dev.l7.ai.inference;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.ServerSocket;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.model.Generation;
import org.springframework.ai.chat.prompt.Prompt;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.MediaType;
import org.springframework.http.codec.ServerSentEvent;
import org.springframework.web.reactive.function.BodyInserters;
import org.springframework.web.reactive.function.server.RouterFunction;
import org.springframework.web.reactive.function.server.RouterFunctions;
import org.springframework.web.reactive.function.server.ServerResponse;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Sinks;

public final class SseStreamingGateway {

    static final int TOKENS = 200;
    static final AtomicInteger generated = new AtomicInteger();
    static final AtomicBoolean cancelled = new AtomicBoolean();
    static final List<Long> genTimes = java.util.Collections.synchronizedList(new ArrayList<>());

    /** 300 ms of "thinking" (TTFT), then one token every 5 ms (TPOT). Counts what it actually generates. */
    static final class SlowFirstTokenModel implements ChatModel {
        @Override
        public ChatResponse call(Prompt p) { throw new UnsupportedOperationException("streaming only"); }

        @Override
        public Flux<ChatResponse> stream(Prompt p) {
            return Flux.interval(Duration.ofMillis(300), Duration.ofMillis(5)).take(TOKENS)
                    .doOnNext(i -> { generated.incrementAndGet(); genTimes.add(System.nanoTime()); })
                    .doOnCancel(() -> cancelled.set(true))
                    .map(i -> new ChatResponse(List.of(new Generation(new AssistantMessage("tok" + i + " ")))));
        }
    }

    static Flux<ServerSentEvent<String>> withHeartbeats(Flux<String> tokens) {
        AtomicInteger seq = new AtomicInteger();
        Flux<ServerSentEvent<String>> events = tokens
                .map(t -> ServerSentEvent.builder(t).id(Integer.toString(seq.incrementAndGet())).event("token").build())
                .concatWith(Flux.just(ServerSentEvent.builder("[DONE]").event("done").build()));
        Flux<ServerSentEvent<String>> heartbeats = Flux.interval(Duration.ofMillis(100))
                .map(i -> ServerSentEvent.<String>builder().comment("hb").build());
        return Flux.merge(events, heartbeats).takeUntil(e -> "done".equals(e.event()));    // heartbeats stop with the stream
    }

    static ServerResponse.BodyBuilder sse() {
        return ServerResponse.ok().contentType(MediaType.TEXT_EVENT_STREAM)
                .header("Cache-Control", "no-cache").header("X-Accel-Buffering", "no");   // nginx: do not buffer
    }

    @Configuration(proxyBeanMethods = false)
    @EnableAutoConfiguration
    static class App {
        @Bean
        ChatClient chatClient() { return ChatClient.create(new SlowFirstTokenModel()); }

        @Bean
        RouterFunction<ServerResponse> routes(ChatClient client) {
            return RouterFunctions.route()
                    // hardened: the HTTP subscription IS the generation subscription, so a disconnect cancels the model
                    .GET("/v1/chat/stream", req -> sse().body(BodyInserters.fromServerSentEvents(
                            withHeartbeats(client.prompt().user(req.queryParam("q").orElse("")).stream().content()))))
                    // naive: generation runs detached, pushing into a sink; nobody tells it the reader left
                    .GET("/naive/stream", req -> {
                        Sinks.Many<String> sink = Sinks.many().replay().all();
                        client.prompt().user("q").stream().content()
                                .subscribe(sink::tryEmitNext, sink::tryEmitError, sink::tryEmitComplete);
                        return sse().body(BodyInserters.fromServerSentEvents(withHeartbeats(sink.asFlux())));
                    })
                    .build();
        }
    }

    record Read(long ttftMs, int tokens, int heartbeats, boolean done, List<Long> gapsMs, long totalMs) {}

    /** Reads SSE lines; stops after maxTokens (closing the connection = the user closed the tab). */
    static Read consume(HttpClient http, String url, int maxTokens) throws Exception {
        long t0 = System.nanoTime();
        HttpResponse<java.io.InputStream> resp = http.send(HttpRequest.newBuilder(URI.create(url)).header("Accept", "text/event-stream").build(),
                HttpResponse.BodyHandlers.ofInputStream());
        long ttft = -1, last = 0;
        int tokens = 0, hb = 0;
        boolean done = false, tokenEvent = false;
        List<Long> gaps = new ArrayList<>();
        try (BufferedReader r = new BufferedReader(new InputStreamReader(resp.body(), StandardCharsets.UTF_8))) {
            String line;
            while ((line = r.readLine()) != null) {
                if (line.startsWith(":")) hb++;
                else if (line.equals("event:token")) tokenEvent = true;
                else if (line.equals("event:done")) { done = true; break; }
                else if (line.startsWith("data:") && tokenEvent) {
                    long now = System.nanoTime();
                    if (ttft < 0) ttft = (now - t0) / 1_000_000;
                    else gaps.add((now - last) / 1_000);
                    last = now;
                    tokenEvent = false;
                    if (++tokens >= maxTokens) break;
                }
            }
        }
        return new Read(ttft, tokens, hb, done, gaps, (System.nanoTime() - t0) / 1_000_000);
    }

    static long pct(List<Long> xs, double p) {
        List<Long> s = new ArrayList<>(xs);
        s.sort(null);
        return s.get((int) Math.min(s.size() - 1, Math.round(p * (s.size() - 1))));
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) throws Exception {
        int port;
        try (ServerSocket s = new ServerSocket(0)) { port = s.getLocalPort(); }
        ConfigurableApplicationContext ctx = new SpringApplicationBuilder(App.class)
                .properties("server.port=" + port, "spring.main.banner-mode=off", "logging.level.root=WARN",
                        "spring.main.web-application-type=reactive")
                .run();
        HttpClient http = HttpClient.newHttpClient();
        String base = "http://localhost:" + port;
        try {
            consume(http, base + "/v1/chat/stream?q=warm", Integer.MAX_VALUE);         // JIT + connection warm-up
            generated.set(0);
            genTimes.clear();
            Read full = consume(http, base + "/v1/chat/stream?q=hello", Integer.MAX_VALUE);
            List<Long> serverGaps = new ArrayList<>();
            for (int i = 1; i < genTimes.size(); i++) serverGaps.add((genTimes.get(i) - genTimes.get(i - 1)) / 1_000);
            System.out.printf("full stream: TTFT %d ms (model thinks 300 ms), %d tokens, done=%s, %d heartbeat comments, "
                    + "total %d ms%n", full.ttftMs(), full.tokens(), full.done(), full.heartbeats(), full.totalMs());
            System.out.printf("  inter-token gap: client p50 %.1f / p99 %.1f / mean %.1f ms; server-side generation p50 %.1f / "
                    + "p99 %.1f ms%n", pct(full.gapsMs(), 0.5) / 1000.0, pct(full.gapsMs(), 0.99) / 1000.0,
                    full.gapsMs().stream().mapToLong(Long::longValue).average().orElse(0) / 1000.0,
                    pct(serverGaps, 0.5) / 1000.0, pct(serverGaps, 0.99) / 1000.0);
            check(full.tokens() == TOKENS && full.done() && full.heartbeats() >= 1 && full.ttftMs() >= 300, "complete stream");

            for (String path : new String[] {"/v1/chat/stream?q=bye", "/naive/stream"}) {
                generated.set(0);
                cancelled.set(false);
                Read part = consume(http, base + path, 10);
                Thread.sleep(1_800);                                                     // let a detached generator run on
                System.out.printf("%-22s client read %d tokens then disconnected -> model generated %3d of %d, upstream cancelled=%s%n",
                        path, part.tokens(), generated.get(), TOKENS, cancelled.get());
                if (path.startsWith("/v1")) check(cancelled.get() && generated.get() < 40, "disconnect cancels generation");
                else check(!cancelled.get() && generated.get() == TOKENS, "naive bridge generates for nobody");
            }
        } finally {
            ctx.close();
        }
        System.out.println("all SseStreamingGateway self-checks passed");
    }
}
```

Output (one measured run; the token counts are asserted):

```text
full stream: TTFT 311 ms (model thinks 300 ms), 200 tokens, done=true, 13 heartbeat comments, total 1312 ms
  inter-token gap: client p50 0.4 / p99 17.5 / mean 5.0 ms; server-side generation p50 0.1 / p99 17.8 ms
/v1/chat/stream?q=bye  client read 10 tokens then disconnected -> model generated  10 of 200, upstream cancelled=true
/naive/stream          client read 10 tokens then disconnected -> model generated 200 of 200, upstream cancelled=false
all SseStreamingGateway self-checks passed
```

### 4.4 Python: Little's law, SSE cancellation and backpressure with asyncio

```python
"""sse_gateway_lab.py - the Python side of an LLM streaming gateway, stdlib asyncio only.

1. Little's law sizes the gateway: concurrent streams L = lambda * W, where W is the whole stream (TTFT + n * TPOT),
   not a request/response round trip. That is what makes thread-per-request expensive for LLM traffic.
2. A real asyncio SSE server: a client disconnect must cancel the generation task (hardened) - the naive server runs
   generation in a background thread that keeps producing for nobody.
3. Backpressure: `await writer.drain()` pauses generation when a slow client stops reading; without it the server's
   write buffer grows without bound.
"""
from __future__ import annotations

import asyncio
import socket
import threading
import time

TOKENS, TTFT_S, TPOT_S = 200, 0.05, 0.002


# ---------------------------------------------------------------------- 1. Little's law for streaming traffic
def sizing() -> None:
    print("== Little's law: concurrent streams = arrival rate x stream duration ==")
    print(f"  {'rps':>5} {'out tok':>8} {'TPOT ms':>8} {'TTFT s':>7} {'W s':>6} {'streams':>8} "
          f"{'platform stacks':>16} {'pool-200 max rps':>17}")
    for rps, n, tpot, ttft in ((50, 300, 25, 0.5), (200, 500, 30, 0.8), (1000, 400, 20, 0.3), (200, 4000, 30, 8.0)):
        w = ttft + n * tpot / 1000
        streams = rps * w
        print(f"  {rps:>5} {n:>8} {tpot:>8} {ttft:>7} {w:>6.1f} {streams:>8,.0f} {streams * 1 / 1024:>13.1f} GiB "
              f"{200 / w:>17.1f}")
    print("  (platform stacks = 1 MiB reserved per thread; a 200-thread pool serves at most 200 / W requests/s)")


# ---------------------------------------------------------------------- 2. SSE server: disconnects must cancel generation
class Stats:
    def __init__(self, tokens: int = TOKENS, tpot: float = TPOT_S, pad: int = 0) -> None:
        self.tokens, self.tpot, self.pad = tokens, tpot, pad
        self.generated = 0
        self.cancelled = False
        self.max_buffer = 0


async def model_stream(stats: Stats):
    """An async token generator: TTFT, then one token per TPOT. Cancellation arrives as CancelledError at an await."""
    try:
        await asyncio.sleep(TTFT_S)
        for i in range(stats.tokens):
            stats.generated += 1
            yield f"tok{i} " + "x" * stats.pad
            await asyncio.sleep(stats.tpot)
    except asyncio.CancelledError:
        stats.cancelled = True
        raise


def frame(data: str, event: str = "token", eid: int | None = None) -> bytes:
    head = f"id: {eid}\n" if eid is not None else ""
    return f"{head}event: {event}\ndata: {data}\n\n".encode()


HEADERS = (b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n"
           b"X-Accel-Buffering: no\r\nConnection: close\r\n\r\n")


async def handle_hardened(reader, writer, stats: Stats, drain: bool = True):
    await reader.readuntil(b"\r\n\r\n")
    writer.get_extra_info("socket").setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 16_384)
    writer.write(HEADERS)

    async def pump():
        i = 0
        async for tok in model_stream(stats):
            i += 1
            writer.write(frame(tok, eid=i))
            stats.max_buffer = max(stats.max_buffer, writer.transport.get_write_buffer_size())
            if drain:
                await writer.drain()                                  # backpressure: wait while the client is slow
        writer.write(frame("[DONE]", "done"))
        await writer.drain()

    gen = asyncio.create_task(pump())
    eof = asyncio.create_task(reader.read(1))                         # resolves with b"" when the client goes away
    done, _ = await asyncio.wait({gen, eof}, return_when=asyncio.FIRST_COMPLETED)
    if eof in done and not gen.done():
        gen.cancel()                                                  # the disconnect cancels generation
    for t in (gen, eof):
        t.cancel()
    await asyncio.gather(gen, eof, return_exceptions=True)
    writer.close()


async def handle_naive(reader, writer, stats: Stats):
    """Generation in a worker thread feeding a queue (a callback-style SDK); nothing ever stops the thread."""
    await reader.readuntil(b"\r\n\r\n")
    writer.write(HEADERS)
    q: asyncio.Queue = asyncio.Queue()
    loop = asyncio.get_running_loop()

    def worker():
        time.sleep(TTFT_S)
        for i in range(TOKENS):
            stats.generated += 1
            loop.call_soon_threadsafe(q.put_nowait, f"tok{i} ")
            time.sleep(TPOT_S)
        loop.call_soon_threadsafe(q.put_nowait, None)

    threading.Thread(target=worker, daemon=True).start()
    try:
        i = 0
        while (tok := await q.get()) is not None:
            i += 1
            writer.write(frame(tok, eid=i))
            await writer.drain()
    except (ConnectionError, OSError):
        pass                                                          # the reader left; the worker does not know
    writer.close()


async def client(port: int, max_tokens: int | None, stall: float = 0.0, stats: Stats | None = None):
    t0 = time.perf_counter()
    sock = socket.socket()
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16_384)       # a small receive window, like a slow phone
    sock.connect(("127.0.0.1", port))
    reader, writer = await asyncio.open_connection(sock=sock)
    snapshot = (0, 0)
    writer.write(b"GET /v1/chat/stream HTTP/1.1\r\nHost: x\r\nAccept: text/event-stream\r\n\r\n")
    await writer.drain()
    tokens, done, ttft = 0, False, -1.0
    while line := await reader.readline():
        if line.startswith(b"event: done"):
            done = True
            break
        if line.startswith(b"data:"):
            ttft = time.perf_counter() - t0 if ttft < 0 else ttft
            tokens += 1
            if stall and tokens == 1:
                await asyncio.sleep(stall)                            # the client stops reading (tunnel, background tab)
                snapshot = (stats.generated, stats.max_buffer)
            if max_tokens and tokens >= max_tokens:
                break
    writer.close()                                                    # the user closed the tab
    return (tokens, done, ttft, snapshot) if stall else (tokens, done, ttft)


async def run_case(handler, max_tokens, stall=0.0, drain=True, settle=0.6, stats=None):
    stats = stats or Stats()
    if handler is handle_hardened:
        srv = await asyncio.start_server(lambda r, w: handle_hardened(r, w, stats, drain), "127.0.0.1", 0)
    else:
        srv = await asyncio.start_server(lambda r, w: handler(r, w, stats), "127.0.0.1", 0)
    port = srv.sockets[0].getsockname()[1]
    async with srv:
        got = await client(port, max_tokens, stall, stats)
        await asyncio.sleep(settle)                                   # give a detached generator time to run on
    return got, stats


async def main_async() -> None:
    print("\n== SSE: a client that reads 10 tokens and disconnects ==")
    (tok, done, ttft), s = await run_case(handle_hardened, None)
    print(f"  full read (hardened): {tok} tokens, done={done}, TTFT {ttft * 1000:.0f} ms")
    assert tok == TOKENS and done
    (tok, _, _), hard = await run_case(handle_hardened, 10)
    (tok2, _, _), naive = await run_case(handle_naive, 10)
    print(f"  hardened: client read {tok}, model generated {hard.generated:3d}/{TOKENS}, generator cancelled={hard.cancelled}")
    print(f"  naive   : client read {tok2}, model generated {naive.generated:3d}/{TOKENS} (worker thread never told)")
    assert hard.cancelled and hard.generated < 30 and naive.generated == TOKENS

    print("\n== Backpressure: 20,000 x ~100-byte events; the client stalls 0.5 s after the first token ==")
    res = {}
    for drain in (True, False):
        st = Stats(tokens=20_000, tpot=0.0, pad=80)
        (tok, done, _, (gen_at_stall, buf_at_stall)), st = await run_case(handle_hardened, None, stall=0.5, drain=drain,
                                                                          settle=0.0, stats=st)
        res[drain] = (gen_at_stall, buf_at_stall)
        print(f"  drain={str(drain):5}: during the stall the model generated {gen_at_stall:6,} events, server write buffer "
              f"peaked at {buf_at_stall:9,} bytes; all {tok:,} delivered={done}")
    assert res[True][1] < 200_000 < res[False][1] and res[True][0] < res[False][0]
    print("  (drain pauses generation at the transport high-water mark; without it the unsent stream piles up in server")
    print("   memory - per connection, times thousands of slow mobile clients)")


def main() -> None:
    sizing()
    asyncio.run(main_async())
    print("\nall sse_gateway_lab self-checks passed")


if __name__ == "__main__":
    main()
```

Output (one measured run; the sizing table is deterministic, and the backpressure byte counts depend on OS socket
buffers):

```text
== Little's law: concurrent streams = arrival rate x stream duration ==
    rps  out tok  TPOT ms  TTFT s    W s  streams  platform stacks  pool-200 max rps
     50      300       25     0.5    8.0      400           0.4 GiB              25.0
    200      500       30     0.8   15.8    3,160           3.1 GiB              12.7
   1000      400       20     0.3    8.3    8,300           8.1 GiB              24.1
    200     4000       30     8.0  128.0   25,600          25.0 GiB               1.6
  (platform stacks = 1 MiB reserved per thread; a 200-thread pool serves at most 200 / W requests/s)

== SSE: a client that reads 10 tokens and disconnects ==
  full read (hardened): 200 tokens, done=True, TTFT 58 ms
  hardened: client read 10, model generated  10/200, generator cancelled=True
  naive   : client read 10, model generated 200/200 (worker thread never told)

== Backpressure: 20,000 x ~100-byte events; the client stalls 0.5 s after the first token ==
  drain=True : during the stall the model generated  2,038 events, server write buffer peaked at    65,608 bytes; all 20,000 delivered=True
  drain=False: during the stall the model generated 20,000 events, server write buffer peaked at 2,205,125 bytes; all 20,000 delivered=True
  (drain pauses generation at the transport high-water mark; without it the unsent stream piles up in server
   memory - per connection, times thousands of slow mobile clients)

all sse_gateway_lab self-checks passed
```

`await writer.drain()` is the asyncio form of Reactor's demand signal. With it, the server's write buffer stops at
asyncio's 64 KiB high-water mark (65,608 B) and generation pauses (2,038 events during a 0.5 s stall). Without it,
the generator ran to completion and 2.2 MB sat in server memory for one slow client.

---

## 5. Production failure modes and P99 debugging

### F1 · The agent stopped using tools after an adapter change

- **Symptom:** answers become generic; tool-execution metrics drop to zero; no errors.
- **Root cause:** a custom or wrapping `ChatModel` whose `getOptions()` is not `ToolCallingChatOptions`, so
  `ChatClient` drops the tool callbacks.
- **Fix:** return a `ToolCallingChatOptions` (or the provider's subclass). Add a contract test asserting that the
  model receives the expected tool names.

### F2 · Tool arguments arrive null or under the wrong name after a build change

- **Signature:** the tool schema contains `arg0`; logs show `null` parameters.
- **Root cause:** compiled without `-parameters` (a Gradle or Maven build not using the Boot plugin, or a shaded
  module).
- **Fix:** `-parameters` in every module that defines `@Tool` methods; a startup check that rejects schemas
  containing `arg\d+`.

### F3 · GPU spend and queueing grow while user-visible traffic is flat

- **Signature:** server-side generated tokens exceed client-delivered tokens; many streams end with client
  disconnects.
- **Root cause:** generation not cancelled on disconnect (a callback SDK bridged into a sink, a detached
  `subscribe()`, a worker thread).
- **Fix:** make the HTTP subscription the generation subscription; propagate cancel to the upstream HTTP call;
  measure tokens generated after disconnect as an SLI.

### F4 · Streams arrive in bursts, or die at 60 s

- **Root cause:** proxy buffering (nginx `proxy_buffering`, gzip), or idle timeouts during long TTFT.
- **Fix:** `X-Accel-Buffering: no`, no compression on `text/event-stream`, heartbeat comments below the smallest
  idle timeout on the path, and `Last-Event-ID` resume.

### F5 · PII appears in the conversation store

- **Root cause:** redaction ordered after `MessageChatMemoryAdvisor`, or redaction applied only to the outbound
  prompt.
- **Fix:** redaction at `HIGHEST_PRECEDENCE`, before memory, and a test that inspects the memory store, not just the
  model prompt.

### F6 · Heap grows with slow mobile clients

- **Root cause:** no backpressure; the generator runs ahead and the unsent stream accumulates per connection.
- **Fix:** Reactor demand or `drain()`; bounded per-connection buffers; drop or close clients that stay behind for
  too long.

### F7 · After the move to virtual threads the model server falls over

- **Symptom:** gateway throughput rises, then the model server's TTFT explodes and 5xx errors appear.
- **Root cause:** the old pool was the admission control. Virtual threads removed it.
- **Fix:** explicit per-deployment concurrency or token-rate limits sized from the goodput curve; 429 with
  `Retry-After`; queue with a deadline.
- **Also check:** pinning on JDK 21–23 (`synchronized` around I/O in client libraries) via the `jdk.VirtualThreadPinned`
  JFR event.

### F8 · Users receive "Tool call limit (3) exceeded…" as the answer

- **Root cause:** `THROW` surfaces at the `ChatClient` boundary as a normal response with
  `finishReason=toolCallLimitExceeded`.
- **Fix:** check the finish reason; map it to a structured failure (File 01 §1.5) and a fallback answer; alert on
  its rate.

---

## 6. FAANG L7 bar-raiser Q&A chains

### Q1 · "Design a Spring-based chat API that streams answers to 10,000 concurrent users."

- **L5 answer:** "Spring MVC with a bigger thread pool, and return the full answer when it is ready."
- **Why L5 fails at scale:** 10,000 concurrent streams need 10,000 threads or a non-blocking stack, and buffering the
  whole answer destroys TTFT.
- **L7 principal defense:**
  1. Size it: `L = λW`. 10,000 streams at a 15 s mean stream is about 670 new requests/s.
  2. Use WebFlux SSE for the stream (`ChatClient.stream()` → `Flux<ServerSentEvent>`), with ids, a terminal
     `done` event with usage, heartbeats, anti-buffering headers and HTTP/2.
  3. Run blocking work (retrieval, tools) on virtual threads; never block the event loop.
  4. Propagate cancellation from the client to the model server, and measure tokens generated after disconnect.
  5. Add explicit admission control per model deployment and backpressure per connection.
  6. Put security and budget advisors first, then memory, then tools, then per-call observability.

### Q2 · "Virtual threads or WebFlux?"

- **L5 answer:** "Virtual threads make reactive obsolete."
- **Why L5 fails at scale:** streaming is a sequence with demand and cancellation; that is what `Flux` models.
  Virtual threads make blocking cheap but do not give you backpressure or cancel propagation for free.
- **L7 principal defense:**
  1. Use both: virtual threads for request/response and blocking integrations (2,000 conversations in 0.20 s vs
     4.52 s); `Flux` for token streams.
  2. With either, replace the old pool's implicit limit with explicit admission control.
  3. Check pinning on the deployed JDK (JEP 491 is JDK 24+).

### Q3 · "How do you guarantee PII never reaches the model or the memory store?"

- **L5 answer:** "A regex in the prompt template."
- **Why L5 fails at scale:** ordering. Memory stores what it sees, so redacting after memory leaks on the next turn,
  as measured. Tool results and retrieved chunks are PII sources too.
- **L7 principal defense:**
  1. A redaction advisor at `HIGHEST_PRECEDENCE`, covering user input, tool results and retrieved documents.
  2. Tests that inspect the memory store and the model-bound prompt.
  3. Identity through `ToolContext` / `@ToolMemoryId`, never through model-chosen arguments.
  4. Retention limits and encryption on the memory store.

### Q4 · "Users close the tab mid-answer. What happens to your GPUs?"

- **L5 answer:** "Nothing; the request finishes and we discard it."
- **Why L5 fails at scale:** the orphan holds KV blocks and a batch slot (1.25 GiB of KV for a 4K-token 70B
  sequence) and decodes for nobody, which raises TTFT for live users.
- **L7 principal defense:**
  1. Make the client's subscription the generation subscription; close the upstream HTTP request on cancel so
     vLLM or SGLang aborts the sequence.
  2. Measure generated-after-disconnect tokens and alert on it.
  3. Verify it in a test like §4.3: 10 of 200 tokens hardened vs 200 of 200 naive.

### Q5 · "Spring AI or LangChain4j?"

- **L5 answer:** a feature checklist.
- **L7 principal defense:**
  1. Both are viable; choose on the extension model and the platform. Spring shops get advisors, Boot
     auto-configuration and Micrometer; LangChain4j gives framework-neutral declarative services.
  2. Whichever you choose, pin the version and write contract tests for the behaviours that bite: tool options and
     schema names, loop limits and their finish reasons, default error handling (LangChain4j's raw exception text),
     memory contents.
  3. Wrap the framework behind your own gateway interfaces so a provider or framework swap is a module change.

---

## 7. Invariants checklist

- [ ] Concurrency is sized with `L = λW` using the stream duration, and admission control is explicit per model
      deployment.
- [ ] Client disconnects cancel generation end to end; generated-after-disconnect tokens are an SLI.
- [ ] SSE responses carry ids, heartbeats, a terminal `done` event, `X-Accel-Buffering: no` and no compression.
- [ ] Per-connection backpressure bounds server memory.
- [ ] Redaction runs before memory; tests inspect the memory store.
- [ ] Identity reaches tools through `ToolContext` / `@ToolMemoryId`, never as model-chosen arguments.
- [ ] Every `@Tool` module is compiled with `-parameters`, or uses explicit names; schemas never contain `arg0`.
- [ ] Custom `ChatModel`s return tool-capable options; a contract test asserts the tools the model receives.
- [ ] Tool loops bound both tool executions and model calls; limit finish reasons are mapped to structured failures.
- [ ] Tool errors are sanitized before they reach the model; hallucinated tool names return the list of real tools.

## 8. References

1. Spring AI reference documentation, 2.0.x: ChatClient, Advisors, Tool Calling, Chat Memory; source of
   `spring-ai-client-chat` and `spring-ai-model` 2.0.2 (⚠ verify against the version you deploy).
2. LangChain4j documentation: AI Services, Tools, Chat Memory; `langchain4j` 1.22.0 (⚠ verify).
3. JEP 444: *Virtual Threads* (JDK 21). JEP 491: *Synchronize Virtual Threads without Pinning* (JDK 24).
4. WHATWG HTML Living Standard, §9.2 *Server-sent events*.
5. J. D. C. Little. *A Proof for the Queuing Formula: L = λW.* Operations Research 9(3), 1961.
6. Spring Framework reference, WebFlux: functional endpoints, `ServerSentEvent`, streaming media types; Reactor
   reference: cancellation and backpressure.
7. Python documentation, `asyncio` Streams: `StreamWriter.drain()` and transport write-buffer limits.
