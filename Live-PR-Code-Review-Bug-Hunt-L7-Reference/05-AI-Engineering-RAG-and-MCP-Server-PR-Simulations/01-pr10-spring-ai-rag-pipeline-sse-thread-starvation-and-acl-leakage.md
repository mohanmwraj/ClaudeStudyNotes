# PR10 · Spring AI RAG Pipeline: SSE Thread Starvation and ACL Leakage

> **What this module is.** An enterprise-assistant PR moves a retrieval-augmented answer endpoint from one blocking response to token streaming over server-sent events. It adds a semantic answer cache and a department filter. It hides **8 defects (4 Sev-1)** across three axes: AI-serving concurrency (threads pinned by streams, no cancellation, no timeout), RAG security (ACL leakage through the context window, a cross-tenant cache, filter-expression injection) and stream semantics (retrying a token stream, caching partial answers). It compiles under `-Xlint:all -Werror` against **Spring AI 2.0.2** and passes the author's tests. One defect rests on Spring AI behavior that this module measured rather than assumed: a `ChatClient` stream can't be re-subscribed.

| Artifact | What it is | Verified |
|---|---|---|
| `pr10-diff` | `AnswerService` (blocking → SSE streaming on a pool), new `SemanticCache` and `RagProperties`, `Answer` removed, tests rewritten: 266 diff lines | `git diff --no-index` from compiled sources |
| `AnswerServiceTest` (author's) | 5 JUnit 5 tests | **5/5 pass** (§4) |
| Test doubles (unchanged) | `StubChatModel` (deterministic `ChatModel`: quotes its context, streams on its own I/O threads; gated, stalled or failing modes), `HashingEmbeddingModel`, `SimpleVectorStore` corpus, `RecordingChannel` | listed in §8 |
| `Pr10Probes` | 8 probes plus a library lemma for F6 | each shows the defect on the PR and its absence on the fix (§8) |
| Fixed code | Pre-filtered retrieval (tenant, ACL, department via `FilterExpressionBuilder`), the same documents for context and citations, a scoped cache written on completion only, a non-blocking subscription cancelled on close, a token timeout, retry only before the first token, on a fresh request | fixed suite 12/12; PR's own tests against the fix 5/5 |

**Verification.** JDK 25 (`javac --release 21 -Xlint:all,-path,-classfile -Werror`), Spring AI 2.0.2 (`spring-ai-client-chat`, `-model`, `-vector-store`), Reactor 3.8.8, JUnit 5 console 1.13.4. "Slow" provider calls are modeled with a gate (no token until the probe releases one), so the starvation and cancellation counts don't depend on timing. No network or real model is involved. The probes exercise the service's own control flow against a model whose output is a deterministic function of its prompt.

---

## 0. Orientation

### 0.1 What this PR tests

| Layer | Defects | Why reviewers miss them |
|---|---|---|
| L2/L7 Concurrency and capacity | F1 streams pin a fixed pool's threads | "Async" (`submit`) looks non-blocking; the blocking is inside `toIterable()` |
| L4 I/O boundaries | F2 no cancellation on disconnect, F6 `retry` on a token stream, F8 configured timeout never applied | Streams look like method calls; their lifecycle is invisible in a unit test |
| L6 Security (RAG) | F3 citations filtered but context not, F4 cache ignores tenant and groups, F7 filter built by string concatenation | The visible output (citations) looks right; the leak is in the generated text |
| L3 Failure paths | F5 `finally` caches partial answers | `finally` reads as "always clean up" |

### 0.2 Habits this PR punishes

| Habit | What happens here |
|---|---|
| "It's async: we `submit` it." | The task blocks a pool thread for the whole generation. |
| "Citations hide restricted docs, so we're compliant." | The model read them, and the answer quotes them. |
| "Cache by question similarity." | An answer quotes *one scope's* documents; reusing it elsewhere leaks them. |
| "`retry(2)` for resilience." | Re-subscribing a token stream either fails (Spring AI 2.0.2) or replays text the user already saw. |
| "Build the filter string." | It's a query language: concatenation is injection. |
| "There's a timeout property." | Nothing reads it. |

---

## 1. First principles

1. **A stream holds whatever its consumer blocks.** `Flux.toIterable()` parks the calling thread until each element arrives. On a fixed pool of N threads, N slow generations stop every later request from even starting. Nothing in the request path times out or reports it.
2. **Cancellation must flow upstream.** When the SSE client goes away, the subscription must be disposed so the provider stream is cancelled (and stops billing tokens). An abandoned iterator isn't a cancellation.
3. **Access control must happen before the model sees the text.** Anything in the context window can appear in the output. OWASP Top 10 for LLM Applications, LLM08:2025 *Vector and Embedding Weaknesses*: "Inadequate or misaligned access controls can lead to unauthorized access to embeddings containing sensitive information," and the prevention advice is to "implement fine-grained access controls and permission-aware vector and embedding stores."
4. **A cached answer inherits the permissions of the documents it quotes.** The cache key must include every input that selected those documents: tenant, groups, filters.
5. **Filter expressions are a language.** Spring AI parses string filters (`"tenant == 'acme' && dept == 'x'"`) with a grammar that includes `||` and `!=`. Build filters with `FilterExpressionBuilder`, where values stay values.
6. **Token streams aren't idempotent to the consumer.** Once a token is on the wire, re-subscribing replays it. Retry only before the first token, and on a freshly built request.
7. **Terminal paths differ.** Cache on `onComplete`, not on "terminated." Cancel, error and timeout produce partial results.

---

## 2. The PR

> **ASSIST-204 · Stream answers to the browser**
>
> Users wait 8–25 s for a complete answer. Stream tokens over SSE so the first words appear in about a second. Most traffic is the same dozen questions, so add a semantic cache. Product wants a department dropdown to narrow sources.
>
> **PR description, by the author:**
> - `answer()` returns immediately; the work runs on a pool sized `assistant.rag.stream-threads` (8, "one per in-flight model stream").
> - A "sources" event first (citations filtered by the user's groups), then "token" events.
> - The model gets the full retrieved context "for answer quality"; only the citations shown to the user are ACL-filtered.
> - `.retry(2)` rides out transient provider errors.
> - `SemanticCache`: reuse answers for questions with cosine similarity ≥ 0.95.
> - Department filter appended to the tenant filter.
> - Tests: streaming, citation filtering, department filter, cache hit, 4 concurrent requests.
>
> **Context the reviewer can discover:** the assistant is multi-tenant (`tenant` metadata on every chunk), and HR documents carry `acl = hr`. The department value comes straight from a UI dropdown, so the browser controls it. Provider streams routinely last 10–40 s. `RagProperties` has a `tokenTimeout`. The web layer adapts `SseEmitter` to `SseChannel`, and its close callbacks fire on disconnect.

---

## 3. The diff

```diff
diff --git a/assistant/src/main/java/com/acme/assist/Answer.java b/assistant/src/main/java/com/acme/assist/Answer.java
deleted file mode 100644
index 7f38c9c..0000000
--- a/assistant/src/main/java/com/acme/assist/Answer.java
+++ /dev/null
@@ -1,5 +0,0 @@
-package com.acme.assist;
-
-/** A complete answer and the ids of the documents it was built from. */
-public record Answer(String text, String sources) {
-}
diff --git a/assistant/src/main/java/com/acme/assist/AnswerService.java b/assistant/src/main/java/com/acme/assist/AnswerService.java
index 652e8f7..0ce2238 100644
--- a/assistant/src/main/java/com/acme/assist/AnswerService.java
+++ b/assistant/src/main/java/com/acme/assist/AnswerService.java
@@ -1,39 +1,77 @@
 package com.acme.assist;
 
 import java.util.List;
+import java.util.Optional;
+import java.util.concurrent.ExecutorService;
+import java.util.concurrent.Executors;
 import java.util.stream.Collectors;
 import org.springframework.ai.chat.client.ChatClient;
 import org.springframework.ai.chat.model.ChatModel;
 import org.springframework.ai.document.Document;
+import org.springframework.ai.embedding.EmbeddingModel;
 import org.springframework.ai.vectorstore.SearchRequest;
 import org.springframework.ai.vectorstore.VectorStore;
-import org.springframework.ai.vectorstore.filter.FilterExpressionBuilder;
 
-/** Answers questions from the tenant's documents (retrieval-augmented generation). */
+/** Answers questions from the tenant's documents (retrieval-augmented generation), streamed as server-sent events. */
 public final class AnswerService {
 
     private final ChatClient chat;
     private final VectorStore store;
-    private final int topK;
+    private final SemanticCache cache;
+    private final RagProperties props;
+    private final ExecutorService streams;
 
-    public AnswerService(ChatModel model, VectorStore store, int topK) {
+    public AnswerService(ChatModel model, VectorStore store, EmbeddingModel embeddings, RagProperties props) {
         this.chat = ChatClient.create(model);
         this.store = store;
-        this.topK = topK;
+        this.cache = new SemanticCache(embeddings, props.cacheThreshold());
+        this.props = props;
+        this.streams = Executors.newFixedThreadPool(props.streamThreads()); // one thread per in-flight model stream
     }
 
-    /** Answers in one response, from and citing only documents the user may read. */
-    public Answer answer(UserContext user, String question) {
-        List<Document> docs = store.similaritySearch(SearchRequest.builder()
-                        .query(question)
-                        .topK(topK)
-                        .filterExpression(new FilterExpressionBuilder().eq("tenant", user.tenant()).build())
-                        .build())
-                .stream()
-                .filter(d -> user.groups().contains(d.getMetadata().get("acl")))
-                .toList();
-        String text = chat.prompt().system(systemPrompt(docs)).user(question).call().content();
-        return new Answer(text, ids(docs));
+    /** Streams one "sources" event, then "token" events, then completes. Returns at once; the work runs on the pool. */
+    public void answer(UserContext user, RagRequest request, SseChannel out) {
+        Optional<String> cached = cache.lookup(request.question());
+        if (cached.isPresent()) {
+            out.send("token", cached.get());
+            out.complete();
+            return;
+        }
+        streams.submit(() -> {
+            List<Document> docs = store.similaritySearch(SearchRequest.builder()
+                    .query(request.question())
+                    .topK(props.topK())
+                    .filterExpression(filterFor(user, request))
+                    .build());
+            List<Document> visible = docs.stream()
+                    .filter(d -> user.groups().contains(d.getMetadata().get("acl")))
+                    .toList();
+            out.send("sources", ids(visible));
+            StringBuilder answer = new StringBuilder();
+            try {
+                for (String token : chat.prompt()
+                        .system(systemPrompt(docs)) // the model needs the full context; only citations are filtered
+                        .user(request.question())
+                        .stream()
+                        .content()
+                        .retry(2) // ride out transient provider errors
+                        .toIterable()) {
+                    answer.append(token);
+                    out.send("token", token);
+                }
+            } finally {
+                cache.put(request.question(), answer.toString());
+            }
+            out.complete();
+        });
+    }
+
+    private static String filterFor(UserContext user, RagRequest request) {
+        String filter = "tenant == '" + user.tenant() + "'";
+        if (request.department() != null && !request.department().isBlank()) {
+            filter += " && dept == '" + request.department() + "'";
+        }
+        return filter;
     }
 
     static String systemPrompt(List<Document> docs) {
diff --git a/assistant/src/main/java/com/acme/assist/RagProperties.java b/assistant/src/main/java/com/acme/assist/RagProperties.java
new file mode 100644
index 0000000..95468cf
--- /dev/null
+++ b/assistant/src/main/java/com/acme/assist/RagProperties.java
@@ -0,0 +1,7 @@
+package com.acme.assist;
+
+import java.time.Duration;
+
+/** assistant.rag.* configuration. */
+public record RagProperties(int topK, int streamThreads, double cacheThreshold, Duration tokenTimeout) {
+}
diff --git a/assistant/src/main/java/com/acme/assist/SemanticCache.java b/assistant/src/main/java/com/acme/assist/SemanticCache.java
new file mode 100644
index 0000000..e24e107
--- /dev/null
+++ b/assistant/src/main/java/com/acme/assist/SemanticCache.java
@@ -0,0 +1,43 @@
+package com.acme.assist;
+
+import java.util.List;
+import java.util.Optional;
+import java.util.concurrent.CopyOnWriteArrayList;
+import org.springframework.ai.embedding.EmbeddingModel;
+
+/** Reuses answers for questions whose embeddings are nearly identical: most traffic is the same dozen questions. */
+public final class SemanticCache {
+
+    private record Entry(float[] embedding, String answer) {
+    }
+
+    private final EmbeddingModel embeddings;
+    private final double threshold;
+    private final List<Entry> entries = new CopyOnWriteArrayList<>();
+
+    public SemanticCache(EmbeddingModel embeddings, double threshold) {
+        this.embeddings = embeddings;
+        this.threshold = threshold;
+    }
+
+    public Optional<String> lookup(String question) {
+        float[] q = embeddings.embed(question);
+        return entries.stream().filter(e -> cosine(q, e.embedding()) >= threshold).map(Entry::answer).findFirst();
+    }
+
+    public void put(String question, String answer) {
+        entries.add(new Entry(embeddings.embed(question), answer));
+    }
+
+    static double cosine(float[] a, float[] b) {
+        double dot = 0;
+        double na = 0;
+        double nb = 0;
+        for (int i = 0; i < a.length; i++) {
+            dot += a[i] * b[i];
+            na += a[i] * a[i];
+            nb += b[i] * b[i];
+        }
+        return na == 0 || nb == 0 ? 0 : dot / Math.sqrt(na * nb);
+    }
+}
diff --git a/assistant/src/test/java/com/acme/assist/AnswerServiceTest.java b/assistant/src/test/java/com/acme/assist/AnswerServiceTest.java
index 9b36323..1d65b1d 100644
--- a/assistant/src/test/java/com/acme/assist/AnswerServiceTest.java
+++ b/assistant/src/test/java/com/acme/assist/AnswerServiceTest.java
@@ -1,33 +1,74 @@
 package com.acme.assist;
 
+import static org.junit.jupiter.api.Assertions.assertEquals;
 import static org.junit.jupiter.api.Assertions.assertFalse;
 import static org.junit.jupiter.api.Assertions.assertTrue;
 
+import java.time.Duration;
+import java.util.ArrayList;
+import java.util.List;
 import org.junit.jupiter.api.Test;
 
 class AnswerServiceTest {
 
+    private static final RagProperties PROPS = new RagProperties(3, 8, 0.95, Duration.ofSeconds(30));
+
+    private static AnswerService service(StubChatModel model) {
+        return new AnswerService(model, Corpus.store(), new HashingEmbeddingModel(), PROPS);
+    }
+
+    @Test
+    void streamsSourcesThenTokens() throws Exception {
+        RecordingChannel out = new RecordingChannel();
+        service(StubChatModel.free()).answer(Corpus.ACME_ENGINEER, new RagRequest("What is the Q3 plan?", null), out);
+        assertTrue(out.awaitEnd(5_000));
+        assertEquals("complete", out.endedWith());
+        assertTrue(out.data("sources").contains("acme-plan-1"));
+        assertTrue(out.data("token").contains("EU region"));
+    }
+
+    @Test
+    void citationsHideRestrictedDocuments() throws Exception {
+        RecordingChannel out = new RecordingChannel();
+        service(StubChatModel.free()).answer(Corpus.ACME_ENGINEER, new RagRequest("What is the Q3 plan?", null), out);
+        assertTrue(out.awaitEnd(5_000));
+        assertFalse(out.data("sources").contains("acme-hr-1"));
+    }
+
     @Test
-    void answersWithSources() {
-        AnswerService service = new AnswerService(StubChatModel.free(), Corpus.store(), 3);
-        Answer a = service.answer(Corpus.ACME_ENGINEER, "What is the Q3 plan?");
-        assertTrue(a.sources().contains("acme-plan-1"));
-        assertTrue(a.text().contains("EU region"));
+    void departmentFilterNarrowsSources() throws Exception {
+        RecordingChannel out = new RecordingChannel();
+        service(StubChatModel.free()).answer(Corpus.ACME_ENGINEER, new RagRequest("What is the Q3 plan?", "strategy"), out);
+        assertTrue(out.awaitEnd(5_000));
+        assertEquals("acme-plan-1", out.data("sources"));
     }
 
     @Test
-    void restrictedDocumentsNeverReachTheAnswer() {
-        AnswerService service = new AnswerService(StubChatModel.free(), Corpus.store(), 3);
-        Answer a = service.answer(Corpus.ACME_ENGINEER, "What is the Q3 plan?");
-        assertFalse(a.sources().contains("acme-hr-1"));
-        assertFalse(a.text().contains(Corpus.HR_ONLY_TEXT));
+    void repeatedQuestionIsServedFromCache() throws Exception {
+        StubChatModel model = StubChatModel.free();
+        AnswerService service = service(model);
+        RecordingChannel first = new RecordingChannel();
+        service.answer(Corpus.ACME_ENGINEER, new RagRequest("What is the Q3 plan?", null), first);
+        assertTrue(first.awaitEnd(5_000));
+        RecordingChannel second = new RecordingChannel();
+        service.answer(Corpus.ACME_ENGINEER, new RagRequest("What is the Q3 plan?", null), second);
+        assertTrue(second.awaitEnd(5_000));
+        assertEquals(1, model.streams.get());
+        assertEquals(first.data("token"), second.data("token"));
     }
 
     @Test
-    void tenantsAreIsolated() {
-        AnswerService service = new AnswerService(StubChatModel.free(), Corpus.store(), 3);
-        Answer a = service.answer(Corpus.GLOBEX_ANALYST, "What is the Q3 plan?");
-        assertTrue(a.text().contains(Corpus.GLOBEX_TEXT));
-        assertFalse(a.text().contains("EU region"));
+    void concurrentRequestsAllComplete() throws Exception {
+        AnswerService service = service(StubChatModel.free());
+        List<RecordingChannel> outs = new ArrayList<>();
+        for (int i = 0; i < 4; i++) {
+            RecordingChannel out = new RecordingChannel();
+            outs.add(out);
+            service.answer(Corpus.ACME_ENGINEER, new RagRequest("Question " + i + " about laptops", null), out);
+        }
+        for (RecordingChannel out : outs) {
+            assertTrue(out.awaitEnd(5_000));
+            assertEquals("complete", out.endedWith());
+        }
     }
 }
```

---

## 4. The author's tests: green

```text
├─ JUnit Jupiter ✔
│  └─ AnswerServiceTest ✔
│     ├─ concurrentRequestsAllComplete() ✔
│     ├─ streamsSourcesThenTokens() ✔
│     ├─ departmentFilterNarrowsSources() ✔
│     ├─ citationsHideRestrictedDocuments() ✔
│     └─ repeatedQuestionIsServedFromCache() ✔
[         5 tests found           ]
[         5 tests successful      ]
[         0 tests failed          ]
```

Every test uses a free-running model, so no stream is ever slow, cancelled, failed or stalled. `citationsHideRestrictedDocuments` asserts on the *sources event only*, while the answer text quotes the HR document. The cache test reuses an answer for the *same user*. The concurrency test runs 4 requests on 8 threads. No test passes a department value containing a quote. All five also pass against the fixed code (§7): none of them encodes a defect, and none could detect one.

---

## 5. The timed 3-pass diagnostic guide

### Minute 2: map and triage

- **Contracts changed:** request threading (blocking → "async"), stream lifecycle (cancel, error, timeout), what the model may read, what may be reused across users, and how the retrieval filter is built.
- **Hunk scores:** `answer()` 8/8, `filterFor` 6/8, `SemanticCache` 6/8, `RagProperties` 2/8.
- **Radar hits:** `newFixedThreadPool` + `toIterable()` (29, 58). `submit` with the `Future` dropped (40). No `onClose` anywhere. `systemPrompt(docs)` next to `ids(visible)` (49–53). `retry(2)` on a stream (57). `cache.put` in `finally` (62–63). `cache.lookup(request.question())` with no user (34). `"... dept == '" + request.department() + "'"` (72). `tokenTimeout` declared, never read.

### Minute 10: one hop each

- Nine concurrent questions while the provider is slow: what does the ninth user see? Nothing, not even "sources": F1.
- The user closes the tab: what stops the provider? Nothing: F2.
- Which list builds the prompt, `docs` or `visible`? `docs`: F3.
- HR at acme asks, then globex asks the same words: what's the cache key? The question only: F4.
- The stream ends by disconnect: what does `finally` cache? Whatever arrived: F5.
- What does `retry` re-subscribe, and is that request reusable? F6.
- `department = x' || dept != 'x`? F7.
- The provider accepts and never sends: who ends the request? Nobody: F8.

### Minute 20: prove, unify, fix

- **Unify:** two root causes. **Scope**: what this user may see must drive retrieval, the context, the citations and the cache key alike (F3, F4, F7). **Lifecycle**: a stream is a resource with an owner. It must not hold a thread while it waits (F1), must be cancelled when its consumer leaves (F2), must time out (F8), and its terminal states (complete, error, cancel) mean different things (F5, F6).
- **Fix shape:** pre-filter in the store with `FilterExpressionBuilder` (tenant ∧ ACL ∧ department); one document list for both context and citations; cache key = scope + question, written only in `onComplete`; subscribe without blocking, dispose on `onClose`; `timeout(tokenTimeout)`; `retryWhen` only while no token has been sent, around a `Flux.defer` that builds a fresh request.

---

## 6. The L7 answer key, line by line

### F1 · L7 · Sev-1 · Each stream pins one of 8 pool threads for the whole generation: request 9 can't even start (AnswerService 29, 40, 58)

**Mechanism.** `answer()` "returns immediately," but the submitted task iterates `toIterable()`, which parks the pool thread until every token has arrived, 10–40 s per answer. With 8 threads, the 9th concurrent question waits in the executor's unbounded queue. It gets no "sources" event, no error and no timeout, and nothing reports it. When the provider slows down (higher latency per token), every stream lasts longer, the pool saturates sooner, and the assistant looks down while CPU sits idle. The pool size was chosen as "one thread per in-flight stream," which makes the cap the concurrency limit of the whole feature.

**Evidence.** P1: 10 questions while the model is slow. PR: `requests that received their first event = 8 of 10`. Fix: `10 of 10`. The fixed `manySlowStreamsDoNotStarveNewRequests` starts 20.

```comment-l7
issue (blocking): each answer blocks a pool thread in toIterable() for the whole generation, so with streamThreads = 8 the ninth concurrent question waits in the executor queue with no event, error or timeout

Provider streams last 10-40 s, which means 8 slow streams stop the feature for everyone while the CPU is idle; the gated-model probe shows 8 of 10 requests getting their first event and 2 receiving nothing. Suggest subscribing to the Flux instead of iterating it (callbacks run when tokens arrive, and nothing waits), with publishOn(boundedElastic) for the blocking SSE writes; then streamThreads isn't needed at all.
```

**Fix.**
```java
        subscription.update(Flux.defer(() -> chat.prompt() // a fresh request per attempt: the advisor chain is single-use
                        .system(systemPrompt(docs))
                        .user(request.question())
                        .stream()
                        .content())
```
```java
                .publishOn(Schedulers.boundedElastic()) // SSE writes block: keep them off the provider's I/O threads
                .subscribe(
```

### F2 · L4 · Sev-2 · A disconnected client doesn't cancel the provider stream: generation (and billing) continues, and the failure disappears into a dropped `Future` (AnswerService 40–65)

**Mechanism.** Nothing registers `onClose`. When the user closes the tab, the next `out.send` throws, the `for` loop exits, and the iterator is abandoned. Abandoning an iterator doesn't cancel its subscription, so the provider keeps generating to the end. Those tokens are billed, the provider-side concurrency slot stays held, and the queue behind it (F1) waits. The exception escapes the task and is stored in the `Future` that `submit` returned and the code dropped, so no log line appears.

**Evidence.** P2: disconnect after the first token. PR: `tokens the provider generated afterwards = 30, provider stream cancelled = no`. Fix: `0, cancelled = yes`.

```comment-l7
issue (blocking): nothing cancels the provider stream when the client disconnects, so generation runs to completion after the user has left and the exception from send() is lost in the dropped Future

Abandoning the toIterable() iterator doesn't cancel its subscription, which means every closed tab keeps a provider stream (and its billing) running; the probe disconnects after one token and the stub provider generates the remaining 30. Suggest registering out.onClose(subscription::dispose) before subscribing (a Disposable.Swap closes the race where the client leaves first), and not discarding task failures.
```

**Fix.**
```java
        Disposable.Swap subscription = Disposables.swap();
        out.onClose(subscription::dispose); // client gone or response ended: cancel the provider stream
```

### F3 · L6 · Sev-1 · Citations are ACL-filtered, but the model's context isn't: restricted documents leak through the answer text (AnswerService 46–53)

**Mechanism.** `visible` (ACL-filtered) feeds the "sources" event, and `docs` (unfiltered) feeds the system prompt, "for answer quality." The model is instructed to answer from its context, so it quotes the HR-only chunk to an engineer. The citation list looks compliant, and every test asserts on it. The leak is in the generated text, which no ACL check reads. Any document the model can read must be treated as disclosed.

**Evidence.** P3: an engineer (groups `[all]`) asks "What is the Q3 plan?" PR: `cited sources = [acme-plan-1,acme-eng-1], answer quotes the HR-only document = yes`. Fix: same citations, `no`.

```comment-l7
issue (blocking): the system prompt is built from all retrieved docs while only the citations are ACL-filtered, so the answer text can quote documents the user may not read

Anything in the context window can appear in the output, which means the HR-only chunk reaches an engineer through the generated answer while the sources event looks clean (probe: engineer asks about the Q3 plan, citations omit acme-hr-1, the answer quotes it). Suggest enforcing the ACL in the retrieval filter (acl in the user's groups) and using one list for both the prompt and the citations; OWASP LLM08:2025 recommends permission-aware vector stores for exactly this.
```

**Fix.**
```java
                .filterExpression(filterFor(user, request)) // tenant, department and ACL enforced by the store
```
```java
        out.send("sources", ids(docs)); // the documents cited are exactly the documents the model sees
```

### F4 · L6 · Sev-1 · The semantic cache is keyed by question similarity alone: one tenant's answer is served to another (AnswerService 34, 63; SemanticCache 23–30)

**Mechanism.** An answer is a function of (question, documents retrieved for this scope). The cache keys only on the question's embedding, so the first asker's scope wins for everyone who asks something similar. Acme HR asks about the Q3 plan, the answer quotes the headcount reduction, and then a globex analyst gets that answer from the cache. That's a cross-tenant disclosure, with no retrieval or ACL check on the cached path.

**Evidence.** P4: PR `globex answer quotes acme's HR document = yes, quotes globex's own plan = no`. Fix: `no`, `yes`.

```comment-l7
issue (blocking): SemanticCache keys answers by question embedding only, so an answer built from one tenant's (or group's) documents is served to anyone who asks a similar question

A cached answer quotes the documents of the scope that produced it, which means the cache bypasses the tenant and ACL filters entirely; the probe has acme HR ask first and a globex analyst then receives acme's HR content. Suggest making the scope part of the key (tenant, sorted groups, department) and only looking up within it; it costs some hit rate, which is the correct trade.
```

**Fix.**
```java
        String scope = scopeOf(user, request); // everything that decides which documents an answer may quote
        Optional<String> cached = cache.lookup(scope, request.question());
```
```java
    private static String scopeOf(UserContext user, RagRequest request) {
        return user.tenant() + "|" + new TreeSet<>(user.groups()) + "|" + request.department();
    }
```

### F5 · L3 · Sev-2 · `finally` caches whatever was streamed: a disconnect or error poisons the cache with a partial answer (AnswerService 62–63)

**Mechanism.** The cache write is in `finally`, so it runs on disconnect (F2), on provider error (F6), and on a stall that never ends. The answer so far, sometimes empty, is stored as *the* answer for that question, and later askers get a fragment until restart, with no model call to repair it.

**Evidence.** P5: the first asker disconnects after one token. PR: `the next asker of the same question gets 2 words, model calls = 1`. Fix: `19 words, model calls = 2`.

```comment-l7
issue (blocking): cache.put runs in finally, so a disconnected, failed or stalled stream stores its partial answer as the cached answer for that question

finally covers every termination, which means the first user who closes the tab decides what everyone else gets (probe: after a disconnect at token 1, the next asker receives a 2-word answer from the cache and the model isn't called). Suggest caching only on successful completion, the onComplete signal, and never on cancel or error.
```

**Fix.**
```java
                        () -> {
                            cache.put(scope, request.question(), answer.toString()); // complete answers only
                            out.complete();
                        }));
```

### F6 · L4 · Sev-2 · `retry(2)` on a token stream: in Spring AI 2.0.2 it can't retry and masks the error; where re-subscription works, it replays tokens; and the failed response is never ended (AnswerService 57)

**Mechanism.** Two layers of wrong, plus a hang.

1. **Spring AI 2.0.2:** the `Flux` from `chat.prompt()…stream().content()` belongs to one request whose advisor chain is consumed on first subscription. `retry` re-subscribes the same `Flux`, and each re-subscription fails at once with `IllegalStateException: No StreamAdvisors available to execute`. That *replaces* the provider's real error (`IOException: provider reset the stream`) in logs and alerts, and nothing is retried.
2. **Semantics:** at any layer where re-subscription does work (here, `model.stream(prompt)`), a retry after tokens were delivered replays them. The user sees "The Q3 plan The Q3 plan is to…", and the tokens are billed twice.
3. **Hang:** the resulting exception escapes the pool task into the dropped `Future`. `out.complete()` and `out.error()` are never called, so the browser shows a spinner after the partial text until some proxy timeout.

**Evidence.** P6 (PR): provider reset after 3 tokens gives `client received 3 tokens, response ended with open, model subscriptions = 1`. Reset before any token gives `0 tokens … open … 1`. Fix: `3 tokens, response ended with error` (no replay), and before the first token, `19 tokens, complete, model subscriptions = 2` (a real retry). Lemma, same for both builds: `ChatClient … retry(2)` ends with `IllegalStateException: No StreamAdvisors available to execute` after 1 model subscription. `model.stream(prompt).retry(2)` delivers `"[d1] a b [d1] a b c d e"`.

```comment-l7
issue (blocking): retry(2) on the ChatClient stream can't retry and hides the real error, and where re-subscription does work it would replay tokens the user already received

In Spring AI 2.0.2 re-subscribing the same stream().content() Flux fails with "No StreamAdvisors available to execute" (the probe reproduces it after 1 model subscription), which means the provider's IOException disappears and the escaped exception leaves the SSE response open forever; at the model level the same retry produces "[d1] a b [d1] a b c d e". Suggest retrying only while no token has been sent, around Flux.defer(() -> chat.prompt()...) so each attempt is a new request, and ending the response with an error event otherwise.
```

**Fix.**
```java
                .doOnNext(token -> started.set(true))
                .retryWhen(Retry.max(2).filter(e -> !started.get())) // never replay tokens the client already has
```
```java
                        error -> out.error("generation failed"),
```

### F7 · L6 · Sev-1 · The department filter is concatenated into a filter-expression string: the browser can rewrite the tenant filter (AnswerService 69–74)

**Mechanism.** `"tenant == 'acme' && dept == '" + department + "'"` goes to Spring AI's filter text parser, whose grammar has `||`, `!=` and quoting. `department = x' || dept != 'x` produces `tenant == 'acme' && dept == 'x' || dept != 'x`. `&&` binds tighter, so the `||` arm matches every document in every tenant. The dropdown value is client-controlled, so this is injection, in the same family as SQL injection.

**Evidence.** P7: PR `cited sources = [acme-plan-1,globex-plan-1], answer quotes another tenant's document = yes`. Fix: `cited sources = [], … no` (the value is compared literally and matches nothing). Measured on Spring AI 2.0.2's `SimpleVectorStore`. Production stores translate the same `Filter.Expression` to their own query languages, so the parsed expression is wrong before any store sees it.

```comment-l7
issue (blocking): filterFor concatenates the department from the UI into a filter-expression string, so a value like  x' || dept != 'x  rewrites the filter and returns other tenants' documents

The string is parsed by Spring AI's filter grammar, which means quotes and || in the value become syntax: && binds tighter, so the || arm matches everything (probe: that department value returns globex-plan-1 to an acme user). Suggest building the expression with FilterExpressionBuilder (b.eq("dept", department) keeps it a value) and allow-listing department names server-side.
```

**Fix.**
```java
    private static Filter.Expression filterFor(UserContext user, RagRequest request) {
        FilterExpressionBuilder b = new FilterExpressionBuilder();
        FilterExpressionBuilder.Op filter = b.and(b.eq("tenant", user.tenant()), b.in("acl", user.groups().toArray()));
        if (request.department() != null && !request.department().isBlank()) {
            filter = b.and(filter, b.eq("dept", request.department())); // a value, never parsed as filter syntax
        }
        return filter.build();
    }
```

### F8 · L4 · Sev-2 · `tokenTimeout` is configured but never applied: a stalled provider holds the request and its thread forever (RagProperties; AnswerService 50–58)

**Mechanism.** `RagProperties.tokenTimeout` exists, ops will set it, and nothing reads it. A provider that accepts the request and never sends (overloaded upstream, half-open connection) leaves `toIterable()` parked indefinitely. Each such stall permanently removes one of the 8 threads (F1), and the client never receives an end event.

**Evidence.** P8 (`tokenTimeout = 100 ms`, a provider that never emits). PR: `response ended within 1.5 s = no (still open)`. Fix: `yes (error)`.

```comment-l7
issue (blocking): RagProperties.tokenTimeout is never applied, so a provider that accepts the request and never streams holds the response and a pool thread indefinitely

Nothing bounds the wait in toIterable(), which means each stall permanently removes one of the eight threads and the client gets no end event (probe: with tokenTimeout = 100 ms the PR's response is still open after 1.5 s). Suggest .timeout(props.tokenTimeout()) on the token Flux, which bounds the gap between tokens including the first, with the error mapped to an SSE error event.
```

**Fix.**
```java
                .timeout(props.tokenTimeout()) // a stalled provider ends the request instead of holding it open
```

### D1 · Decoy · `CopyOnWriteArrayList` in `SemanticCache` is thread-safe

Reviewers flag it as "not thread-safe." It is. Its real costs are elsewhere: every `put` copies the array, every `lookup` scans every entry, and nothing evicts. That's N1. The cache's blocking defects are scope (F4) and when it's written (F5), not the collection type.

### N1 · Non-blocking · The cache grows without bound and never invalidates

```comment-l7
suggestion (non-blocking): SemanticCache never evicts or invalidates, so it grows with every distinct question (O(n) scan per request) and keeps serving answers after the underlying documents are edited, deleted or re-permissioned

A bounded LRU with a TTL, cleared for a tenant when its corpus or ACLs change, would cover both; worth a follow-up ticket.
```

### T1 · Tests

```comment-l7
todo (blocking): the tests use a free-running model and assert on citations only, so slowness, disconnects, provider errors, stalls, the answer text, other tenants and hostile filter values are all untested

This means every defect in this review passes CI. Suggest a gated stub model for slow and stalled providers, a disconnect test that checks the provider was cancelled, a test asserting restricted text never appears in the answer, a cross-tenant cache test, a department value containing a quote, and more concurrent requests than streamThreads.
```

---

## 7. The refactored code

```java
// ===== assistant/src/main/java/com/acme/assist/AnswerService.java =====
package com.acme.assist;

import java.util.List;
import java.util.Optional;
import java.util.TreeSet;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.stream.Collectors;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.document.Document;
import org.springframework.ai.embedding.EmbeddingModel;
import org.springframework.ai.vectorstore.SearchRequest;
import org.springframework.ai.vectorstore.VectorStore;
import org.springframework.ai.vectorstore.filter.Filter;
import org.springframework.ai.vectorstore.filter.FilterExpressionBuilder;
import reactor.core.Disposable;
import reactor.core.Disposables;
import reactor.core.publisher.Flux;
import reactor.core.scheduler.Schedulers;
import reactor.util.retry.Retry;

/** Answers questions from the tenant's documents (retrieval-augmented generation), streamed as server-sent events. */
public final class AnswerService {

    private final ChatClient chat;
    private final VectorStore store;
    private final SemanticCache cache;
    private final RagProperties props; // streamThreads is no longer used: a stream holds no thread while it waits

    public AnswerService(ChatModel model, VectorStore store, EmbeddingModel embeddings, RagProperties props) {
        this.chat = ChatClient.create(model);
        this.store = store;
        this.cache = new SemanticCache(embeddings, props.cacheThreshold());
        this.props = props;
    }

    /** Streams one "sources" event, then "token" events, then completes. Returns once the stream is subscribed. */
    public void answer(UserContext user, RagRequest request, SseChannel out) {
        String scope = scopeOf(user, request); // everything that decides which documents an answer may quote
        Optional<String> cached = cache.lookup(scope, request.question());
        if (cached.isPresent()) {
            out.send("token", cached.get());
            out.complete();
            return;
        }
        List<Document> docs = store.similaritySearch(SearchRequest.builder()
                .query(request.question())
                .topK(props.topK())
                .filterExpression(filterFor(user, request)) // tenant, department and ACL enforced by the store
                .build());
        out.send("sources", ids(docs)); // the documents cited are exactly the documents the model sees
        StringBuilder answer = new StringBuilder();
        AtomicBoolean started = new AtomicBoolean();
        Disposable.Swap subscription = Disposables.swap();
        out.onClose(subscription::dispose); // client gone or response ended: cancel the provider stream
        subscription.update(Flux.defer(() -> chat.prompt() // a fresh request per attempt: the advisor chain is single-use
                        .system(systemPrompt(docs))
                        .user(request.question())
                        .stream()
                        .content())
                .timeout(props.tokenTimeout()) // a stalled provider ends the request instead of holding it open
                .doOnNext(token -> started.set(true))
                .retryWhen(Retry.max(2).filter(e -> !started.get())) // never replay tokens the client already has
                .publishOn(Schedulers.boundedElastic()) // SSE writes block: keep them off the provider's I/O threads
                .subscribe(
                        token -> {
                            answer.append(token);
                            out.send("token", token);
                        },
                        error -> out.error("generation failed"),
                        () -> {
                            cache.put(scope, request.question(), answer.toString()); // complete answers only
                            out.complete();
                        }));
    }

    private static Filter.Expression filterFor(UserContext user, RagRequest request) {
        FilterExpressionBuilder b = new FilterExpressionBuilder();
        FilterExpressionBuilder.Op filter = b.and(b.eq("tenant", user.tenant()), b.in("acl", user.groups().toArray()));
        if (request.department() != null && !request.department().isBlank()) {
            filter = b.and(filter, b.eq("dept", request.department())); // a value, never parsed as filter syntax
        }
        return filter.build();
    }

    private static String scopeOf(UserContext user, RagRequest request) {
        return user.tenant() + "|" + new TreeSet<>(user.groups()) + "|" + request.department();
    }

    static String systemPrompt(List<Document> docs) {
        return "Answer only from the context below and cite document ids.\n"
                + docs.stream().map(d -> "[" + d.getId() + "] " + d.getText()).collect(Collectors.joining("\n"));
    }

    static String ids(List<Document> docs) {
        return docs.stream().map(Document::getId).collect(Collectors.joining(","));
    }
}

// ===== assistant/src/main/java/com/acme/assist/RagProperties.java =====
package com.acme.assist;

import java.time.Duration;

/** assistant.rag.* configuration. */
public record RagProperties(int topK, int streamThreads, double cacheThreshold, Duration tokenTimeout) {
}

// ===== assistant/src/main/java/com/acme/assist/SemanticCache.java =====
package com.acme.assist;

import java.util.List;
import java.util.Optional;
import java.util.concurrent.CopyOnWriteArrayList;
import org.springframework.ai.embedding.EmbeddingModel;

/**
 * Reuses answers for questions whose embeddings are nearly identical: most traffic is the same dozen questions. An answer
 * is only reusable within the scope it was produced for (tenant, groups, filters), because it quotes that scope's
 * documents.
 */
public final class SemanticCache {

    private record Entry(String scope, float[] embedding, String answer) {
    }

    private final EmbeddingModel embeddings;
    private final double threshold;
    private final List<Entry> entries = new CopyOnWriteArrayList<>();

    public SemanticCache(EmbeddingModel embeddings, double threshold) {
        this.embeddings = embeddings;
        this.threshold = threshold;
    }

    public Optional<String> lookup(String scope, String question) {
        float[] q = embeddings.embed(question);
        return entries.stream()
                .filter(e -> e.scope().equals(scope) && cosine(q, e.embedding()) >= threshold)
                .map(Entry::answer)
                .findFirst();
    }

    public void put(String scope, String question, String answer) {
        entries.add(new Entry(scope, embeddings.embed(question), answer));
    }

    static double cosine(float[] a, float[] b) {
        double dot = 0;
        double na = 0;
        double nb = 0;
        for (int i = 0; i < a.length; i++) {
            dot += a[i] * b[i];
            na += a[i] * a[i];
            nb += b[i] * b[i];
        }
        return na == 0 || nb == 0 ? 0 : dot / Math.sqrt(na * nb);
    }
}
```

**Fixed suite: 12/12 (output, verified).**

```text
├─ JUnit Jupiter ✔
│  └─ AnswerServiceTest ✔
│     ├─ partialAnswersAreNotCached() ✔
│     ├─ disconnectCancelsGeneration() ✔
│     ├─ streamsSourcesThenTokens() ✔
│     ├─ departmentFilterNarrowsSources() ✔
│     ├─ midStreamFailureIsNotReplayed() ✔
│     ├─ failureBeforeTheFirstTokenIsRetried() ✔
│     ├─ cacheIsScopedToTenantAndGroups() ✔
│     ├─ restrictedDocumentsNeverReachTheAnswer() ✔
│     ├─ manySlowStreamsDoNotStarveNewRequests() ✔
│     ├─ stalledModelTimesOut() ✔
│     ├─ repeatedQuestionIsServedFromCache() ✔
│     └─ departmentValueCannotRewriteTheFilter() ✔
[        12 tests found           ]
[        12 tests successful      ]
[         0 tests failed          ]
```

**The PR's original tests against the fix (output, verified).** All pass. None of them encodes a defect, and none could detect one:

```text
├─ JUnit Jupiter ✔
│  └─ AnswerServiceTest ✔
│     ├─ concurrentRequestsAllComplete() ✔
│     ├─ streamsSourcesThenTokens() ✔
│     ├─ departmentFilterNarrowsSources() ✔
│     ├─ citationsHideRestrictedDocuments() ✔
│     └─ repeatedQuestionIsServedFromCache() ✔
[         5 tests found           ]
[         5 tests successful      ]
[         0 tests failed          ]
```

### 7.1 Why this shape

| Concern | PR | Fix |
|---|---|---|
| Threading | Pool of 8; each stream blocks one thread in `toIterable()` | Non-blocking subscription; `publishOn(boundedElastic)` only for the SSE write |
| Disconnect | Iterator abandoned; provider keeps generating | `onClose` disposes the subscription (via `Disposable.Swap`, race-free) |
| Stall | `tokenTimeout` unused | `timeout(tokenTimeout)` → SSE error event |
| Retry | `retry(2)` on a single-use `ChatClient` stream | `Flux.defer` (fresh request per attempt) + `retryWhen` only before the first token |
| ACL | Citations filtered; context unfiltered | `acl in groups` in the store filter; one list for context and citations |
| Tenant + department | String concatenation into the filter grammar | `FilterExpressionBuilder` values |
| Cache key | Question embedding | Scope (tenant, sorted groups, department) + question |
| Cache write | `finally` (any termination) | `onComplete` only |
| Failures | Swallowed in a dropped `Future` | `out.error(...)`, logged by the error consumer in production |
| Alternative | n/a | Spring WebFlux returning `Flux<ServerSentEvent<String>>` end to end removes the adapter, and the cancel-on-disconnect comes from the framework |

---

## 8. Probe evidence

**Against the PR's code (output, verified):**

```text
PR10 probes against the PR's answer service
P1 F1 10 questions while the model is slow (streamThreads = 8): requests that received their first event = 8 of 10
P2 F2 client disconnects after the first token: tokens the provider generated afterwards = 30, provider stream cancelled = no
P3 F3 engineer (groups [all]) asks "What is the Q3 plan?": cited sources = [acme-plan-1,acme-eng-1], answer quotes the HR-only document = yes
P4 F4 acme HR asks first, then a globex analyst asks the same question: globex answer quotes acme's HR document = yes, quotes globex's own plan = no
P5 F5 first asker disconnects after one token; the next asker of the same question gets 2 words, model calls = 1
P6 F6 provider resets the first stream after 3 tokens: client received 3 tokens, response ended with open, model subscriptions = 1
P6 F6 provider resets the first stream after 0 tokens: client received 0 tokens, response ended with open, model subscriptions = 1
P6 F6 (Spring AI 2.0.2) ChatClient stream().content().retry(2), provider reset after 3 tokens: terminal error = IllegalStateException: No StreamAdvisors available to execute, model subscriptions = 1
P6 F6 (Reactor) model.stream(prompt).retry(2), same failure: client-visible text = "[d1] a b [d1] a b c d e"
P7 F7 department = "x' || dept != 'x": cited sources = [acme-plan-1,globex-plan-1], answer quotes another tenant's document = yes
P8 F8 provider accepts the request and never sends a token (tokenTimeout = 100 ms): response ended within 1.5 s = no (still open)
```

**Against the fixed code (output, verified):**

```text
PR10 probes against the fixed answer service
P1 F1 10 questions while the model is slow (streamThreads = 8): requests that received their first event = 10 of 10
P2 F2 client disconnects after the first token: tokens the provider generated afterwards = 0, provider stream cancelled = yes
P3 F3 engineer (groups [all]) asks "What is the Q3 plan?": cited sources = [acme-plan-1,acme-eng-1], answer quotes the HR-only document = no
P4 F4 acme HR asks first, then a globex analyst asks the same question: globex answer quotes acme's HR document = no, quotes globex's own plan = yes
P5 F5 first asker disconnects after one token; the next asker of the same question gets 19 words, model calls = 2
P6 F6 provider resets the first stream after 3 tokens: client received 3 tokens, response ended with error, model subscriptions = 1
P6 F6 provider resets the first stream after 0 tokens: client received 19 tokens, response ended with complete, model subscriptions = 2
P6 F6 (Spring AI 2.0.2) ChatClient stream().content().retry(2), provider reset after 3 tokens: terminal error = IllegalStateException: No StreamAdvisors available to execute, model subscriptions = 1
P6 F6 (Reactor) model.stream(prompt).retry(2), same failure: client-visible text = "[d1] a b [d1] a b c d e"
P7 F7 department = "x' || dept != 'x": cited sources = [], answer quotes another tenant's document = no
P8 F8 provider accepts the request and never sends a token (tokenTimeout = 100 ms): response ended within 1.5 s = yes (error)
```

The two `P6 … (Spring AI 2.0.2)` and `P6 … (Reactor)` lines are identical in both runs by design. They measure library behavior that F6 depends on, not the service.

<details><summary><b>The unchanged code the PR builds on: request types, the SSE port, test doubles</b></summary>

```java
// ===== assistant/src/main/java/com/acme/assist/RagRequest.java =====
package com.acme.assist;

/** What the UI sends: the question and an optional department filter chosen from a dropdown. */
public record RagRequest(String question, String department) {
}

// ===== assistant/src/main/java/com/acme/assist/SseChannel.java =====
package com.acme.assist;

/**
 * The service's view of one server-sent-events response. The web layer adapts Spring MVC's SseEmitter to it and maps
 * SseEmitter's onCompletion/onTimeout/onError callbacks to {@link #onClose}.
 */
public interface SseChannel {

    /** Sends one event; throws IllegalStateException once the client has gone. */
    void send(String event, String data);

    /** Ends the response normally (no-op once closed). */
    void complete();

    /** Ends the response with an error event (no-op once closed). */
    void error(String message);

    /** Runs the callback when the response ends for any reason: completed, failed, timed out or client disconnected. */
    void onClose(Runnable callback);
}

// ===== assistant/src/main/java/com/acme/assist/UserContext.java =====
package com.acme.assist;

import java.util.Set;

/** The authenticated caller, from the verified session (never from request parameters). */
public record UserContext(String userId, String tenant, Set<String> groups) {
}

// ===== assistant/src/test/java/com/acme/assist/Corpus.java =====
package com.acme.assist;

import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.ai.document.Document;
import org.springframework.ai.vectorstore.SimpleVectorStore;

/** Test corpus: two tenants, one HR-only document. */
public final class Corpus {

    public static final String HR_ONLY_TEXT = "twelve percent headcount reduction";
    public static final String GLOBEX_TEXT = "acquire Initech";

    public static final UserContext ACME_ENGINEER = new UserContext("dana", "acme", Set.of("all"));
    public static final UserContext ACME_HR = new UserContext("hal", "acme", Set.of("all", "hr"));
    public static final UserContext GLOBEX_ANALYST = new UserContext("gus", "globex", Set.of("all"));

    private Corpus() {
    }

    public static SimpleVectorStore store() {
        SimpleVectorStore store = SimpleVectorStore.builder(new HashingEmbeddingModel()).build();
        store.add(List.of(
                doc("acme-eng-1", "Laptops for new engineers ship within three days.", "acme", "eng", "all"),
                doc("acme-plan-1", "The Q3 plan is to launch the EU region.", "acme", "strategy", "all"),
                doc("acme-hr-1", "The Q3 plan includes a twelve percent headcount reduction in support.", "acme", "hr", "hr"),
                doc("globex-plan-1", "The Globex Q3 plan is to acquire Initech.", "globex", "strategy", "all")));
        return store;
    }

    private static Document doc(String id, String text, String tenant, String dept, String acl) {
        return new Document(id, text, Map.of("tenant", tenant, "dept", dept, "acl", acl));
    }
}

// ===== assistant/src/test/java/com/acme/assist/HashingEmbeddingModel.java =====
package com.acme.assist;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import org.springframework.ai.document.Document;
import org.springframework.ai.embedding.Embedding;
import org.springframework.ai.embedding.EmbeddingModel;
import org.springframework.ai.embedding.EmbeddingRequest;
import org.springframework.ai.embedding.EmbeddingResponse;

/** Deterministic test embedding: bag of lower-cased words hashed into 64 dimensions, L2-normalized. */
public final class HashingEmbeddingModel implements EmbeddingModel {

    private static final int DIMENSIONS = 64;

    @Override
    public EmbeddingResponse call(EmbeddingRequest request) {
        List<Embedding> out = new ArrayList<>();
        for (String text : request.getInstructions()) {
            out.add(new Embedding(vector(text), out.size()));
        }
        return new EmbeddingResponse(out);
    }

    @Override
    public float[] embed(Document document) {
        return vector(document.getText());
    }

    @Override
    public int dimensions() {
        return DIMENSIONS;
    }

    static float[] vector(String text) {
        float[] v = new float[DIMENSIONS];
        for (String word : text.toLowerCase(Locale.ROOT).split("[^a-z0-9]+")) {
            if (!word.isEmpty()) {
                v[Math.floorMod(word.hashCode(), DIMENSIONS)] += 1f;
            }
        }
        double norm = 0;
        for (float x : v) {
            norm += x * x;
        }
        for (int i = 0; i < v.length && norm > 0; i++) {
            v[i] = (float) (v[i] / Math.sqrt(norm));
        }
        return v;
    }
}

// ===== assistant/src/test/java/com/acme/assist/RecordingChannel.java =====
package com.acme.assist;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.stream.Collectors;

/** An SseChannel that records events and can simulate the client disconnecting. */
public final class RecordingChannel implements SseChannel {

    public record Event(String name, String data) {
    }

    private final List<Event> events = new CopyOnWriteArrayList<>();
    private final List<Runnable> closeCallbacks = new CopyOnWriteArrayList<>();
    private final AtomicBoolean open = new AtomicBoolean(true);
    private final CountDownLatch closed = new CountDownLatch(1);
    private volatile String endedWith = "open";

    @Override
    public void send(String event, String data) {
        if (!open.get()) {
            throw new IllegalStateException("client disconnected");
        }
        events.add(new Event(event, data));
    }

    @Override
    public void complete() {
        end("complete");
    }

    @Override
    public void error(String message) {
        if (open.get()) {
            events.add(new Event("error", message));
        }
        end("error");
    }

    @Override
    public void onClose(Runnable callback) {
        closeCallbacks.add(callback);
        if (!open.get()) {
            callback.run();
        }
    }

    public void disconnect() {
        end("disconnect");
    }

    private void end(String how) {
        if (open.compareAndSet(true, false)) {
            endedWith = how;
            closeCallbacks.forEach(Runnable::run);
            closed.countDown();
        }
    }

    public String endedWith() {
        return endedWith;
    }

    public boolean awaitEnd(long millis) throws InterruptedException {
        return closed.await(millis, TimeUnit.MILLISECONDS);
    }

    public long count(String name) {
        return events.stream().filter(e -> e.name().equals(name)).count();
    }

    public String data(String name) {
        return events.stream().filter(e -> e.name().equals(name)).map(Event::data).collect(Collectors.joining());
    }

    /** Waits until at least n events with this name have arrived; false on timeout. */
    public boolean awaitCount(String name, long n, long millis) throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(millis);
        while (count(name) < n) {
            if (System.nanoTime() > deadline) {
                return false;
            }
            Thread.sleep(2);
        }
        return true;
    }
}

// ===== assistant/src/test/java/com/acme/assist/StubChatModel.java =====
package com.acme.assist;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.ai.chat.messages.AssistantMessage;
import org.springframework.ai.chat.messages.Message;
import org.springframework.ai.chat.messages.SystemMessage;
import org.springframework.ai.chat.model.ChatModel;
import org.springframework.ai.chat.model.ChatResponse;
import org.springframework.ai.chat.model.Generation;
import org.springframework.ai.chat.prompt.Prompt;
import reactor.core.publisher.Flux;
import reactor.core.publisher.FluxSink;

/**
 * A deterministic chat model. It "answers" by quoting every context line ("[id] text") of the system prompt, one word per
 * streamed token, on its own I/O threads like a real provider client. Modes: free-running, gated (one token per
 * released permit), stalled (never emits), or failing the first stream after N tokens.
 */
public final class StubChatModel implements ChatModel {

    private static final Pattern CONTEXT_LINE = Pattern.compile("^\\[(\\S+)] (.*)$", Pattern.MULTILINE);

    public final AtomicInteger streams = new AtomicInteger();
    public final AtomicInteger generated = new AtomicInteger();
    public final AtomicInteger cancelled = new AtomicInteger();
    public final AtomicInteger ended = new AtomicInteger();

    private final Semaphore permits; // null: emit freely
    private final boolean stall;
    private final int failFirstStreamAfter; // -1: never fail
    private final ExecutorService io = Executors.newCachedThreadPool(r -> {
        Thread t = new Thread(r, "provider-io");
        t.setDaemon(true);
        return t;
    });

    private StubChatModel(Semaphore permits, boolean stall, int failFirstStreamAfter) {
        this.permits = permits;
        this.stall = stall;
        this.failFirstStreamAfter = failFirstStreamAfter;
    }

    public static StubChatModel free() {
        return new StubChatModel(null, false, -1);
    }

    public static StubChatModel gated() {
        return new StubChatModel(new Semaphore(0), false, -1);
    }

    public static StubChatModel stalled() {
        return new StubChatModel(null, true, -1);
    }

    public static StubChatModel failingFirstStreamAfter(int tokens) {
        return new StubChatModel(null, false, tokens);
    }

    public void release(int tokens) {
        permits.release(tokens);
    }

    @Override
    public ChatResponse call(Prompt prompt) {
        return response(String.join("", tokens(prompt)));
    }

    @Override
    public Flux<ChatResponse> stream(Prompt prompt) {
        List<String> tokens = tokens(prompt);
        return Flux.create(sink -> {
            int attempt = streams.incrementAndGet(); // per subscription: a retry re-subscribes the same Flux
            io.execute(() -> run(sink, tokens, attempt));
        });
    }

    private void run(FluxSink<ChatResponse> sink, List<String> tokens, int attempt) {
        try {
            for (int i = 0; i < tokens.size(); i++) {
                if (!awaitPermit(sink)) {
                    cancelled.incrementAndGet();
                    return;
                }
                if (attempt == 1 && i == failFirstStreamAfter) {
                    sink.error(new IOException("provider reset the stream"));
                    return;
                }
                generated.incrementAndGet();
                sink.next(response(tokens.get(i)));
            }
            sink.complete();
        } finally {
            ended.incrementAndGet();
        }
    }

    /** Waits until all streams started so far have ended; false on timeout. */
    public boolean awaitEnded(long millis) throws InterruptedException {
        long deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(millis);
        while (ended.get() < streams.get()) {
            if (System.nanoTime() > deadline) {
                return false;
            }
            Thread.sleep(5);
        }
        return true;
    }

    private boolean awaitPermit(FluxSink<?> sink) {
        try {
            while (true) {
                if (sink.isCancelled()) {
                    return false;
                }
                if (!stall && (permits == null || permits.tryAcquire(10, TimeUnit.MILLISECONDS))) {
                    return !sink.isCancelled();
                }
                if (stall) {
                    Thread.sleep(10);
                }
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return false;
        }
    }

    static List<String> tokens(Prompt prompt) {
        String system = prompt.getInstructions().stream()
                .filter(m -> m instanceof SystemMessage)
                .map(Message::getText)
                .findFirst()
                .orElse("");
        StringBuilder answer = new StringBuilder();
        Matcher m = CONTEXT_LINE.matcher(system);
        while (m.find()) {
            answer.append('[').append(m.group(1)).append("] ").append(m.group(2)).append(' ');
        }
        if (answer.isEmpty()) {
            answer.append("I do not know.");
        }
        List<String> out = new ArrayList<>();
        for (String word : answer.toString().trim().split(" ")) {
            out.add(word + " ");
        }
        return out;
    }

    private static ChatResponse response(String text) {
        return new ChatResponse(List.of(new Generation(new AssistantMessage(text))));
    }
}
```

</details>

<details><summary><b>The probe harness (Pr10Probes.java)</b></summary>

```java
package com.acme.assist;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

/**
 * Probes for PR10 against a deterministic stub model and an in-memory vector store. "Slow" model calls are modelled with a
 * gate (no token until the probe releases one), so counts don't depend on timing. The stalled-model probe runs last and
 * the run ends with System.exit, because the PR's stream threads never finish.
 */
public final class Pr10Probes {

    private static final String Q3 = "What is the Q3 plan?";
    private static final RagProperties PROPS = new RagProperties(3, 8, 0.95, Duration.ofSeconds(30));

    private Pr10Probes() {
    }

    private static AnswerService service(StubChatModel model, RagProperties props) {
        return new AnswerService(model, Corpus.store(), new HashingEmbeddingModel(), props);
    }

    private static int words(String s) {
        return s.isBlank() ? 0 : s.trim().split("\\s+").length;
    }

    static void starvation() throws Exception {
        StubChatModel model = StubChatModel.gated(); // the provider is slow: no tokens yet
        AnswerService service = service(model, PROPS);
        List<RecordingChannel> outs = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            RecordingChannel out = new RecordingChannel();
            outs.add(out);
            service.answer(Corpus.ACME_ENGINEER, new RagRequest("Question " + i + " about laptops", null), out);
        }
        long deadline = System.nanoTime() + 2_000_000_000L;
        while (outs.stream().filter(o -> o.count("sources") > 0).count() < 8 && System.nanoTime() < deadline) {
            Thread.sleep(5);
        }
        Thread.sleep(300); // anything still able to start has started by now
        long started = outs.stream().filter(o -> o.count("sources") > 0).count();
        System.out.println("P1 F1 10 questions while the model is slow (streamThreads = 8): requests that received"
                + " their first event = " + started + " of 10");
    }

    static void disconnect() throws Exception {
        StubChatModel model = StubChatModel.gated();
        RecordingChannel out = new RecordingChannel();
        service(model, PROPS).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), out);
        model.release(1);
        out.awaitCount("token", 1, 5_000);
        out.disconnect(); // the user closed the tab
        int atDisconnect = model.generated.get();
        model.release(1_000);
        model.awaitEnded(5_000);
        System.out.println("P2 F2 client disconnects after the first token: tokens the provider generated afterwards = "
                + (model.generated.get() - atDisconnect) + ", provider stream cancelled = "
                + (model.cancelled.get() > 0 ? "yes" : "no"));
    }

    static void aclLeak() throws Exception {
        RecordingChannel out = new RecordingChannel();
        service(StubChatModel.free(), PROPS).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), out);
        out.awaitEnd(5_000);
        System.out.println("P3 F3 engineer (groups [all]) asks \"" + Q3 + "\": cited sources = [" + out.data("sources")
                + "], answer quotes the HR-only document = "
                + (out.data("token").contains(Corpus.HR_ONLY_TEXT) ? "yes" : "no"));
    }

    static void crossTenantCache() throws Exception {
        AnswerService service = service(StubChatModel.free(), PROPS);
        RecordingChannel hr = new RecordingChannel();
        service.answer(Corpus.ACME_HR, new RagRequest(Q3, null), hr);
        hr.awaitEnd(5_000);
        RecordingChannel globex = new RecordingChannel();
        service.answer(Corpus.GLOBEX_ANALYST, new RagRequest(Q3, null), globex);
        globex.awaitEnd(5_000);
        String answer = globex.data("token");
        System.out.println("P4 F4 acme HR asks first, then a globex analyst asks the same question: globex answer quotes"
                + " acme's HR document = " + (answer.contains(Corpus.HR_ONLY_TEXT) ? "yes" : "no")
                + ", quotes globex's own plan = " + (answer.contains(Corpus.GLOBEX_TEXT) ? "yes" : "no"));
    }

    static void partialCached() throws Exception {
        StubChatModel model = StubChatModel.gated();
        AnswerService service = service(model, PROPS);
        RecordingChannel first = new RecordingChannel();
        service.answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), first);
        model.release(1);
        first.awaitCount("token", 1, 5_000);
        first.disconnect();
        model.release(1_000);
        model.awaitEnded(5_000);
        RecordingChannel second = new RecordingChannel();
        service.answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), second);
        model.release(1_000);
        second.awaitEnd(5_000);
        System.out.println("P5 F5 first asker disconnects after one token; the next asker of the same question gets "
                + words(second.data("token")) + " words, model calls = " + model.streams.get());
    }

    static void retry() throws Exception {
        for (int failAfter : new int[] {3, 0}) {
            StubChatModel model = StubChatModel.failingFirstStreamAfter(failAfter);
            RecordingChannel out = new RecordingChannel();
            service(model, PROPS).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), out);
            out.awaitEnd(2_000);
            System.out.println("P6 F6 provider resets the first stream after " + failAfter + " tokens: client received "
                    + out.count("token") + " tokens, response ended with " + out.endedWith() + ", model subscriptions = "
                    + model.streams.get());
        }
    }

    /** Library behavior behind F6 (identical for both builds): what retry does to a ChatClient stream and a model stream. */
    static void retryLemma() {
        StubChatModel model = StubChatModel.failingFirstStreamAfter(3);
        Throwable error = org.springframework.ai.chat.client.ChatClient.create(model).prompt()
                .system("[d1] a b c d e")
                .user("q")
                .stream()
                .content()
                .retry(2)
                .then()
                .materialize()
                .block()
                .getThrowable();
        System.out.println("P6 F6 (Spring AI 2.0.2) ChatClient stream().content().retry(2), provider reset after 3 tokens:"
                + " terminal error = " + error.getClass().getSimpleName() + ": " + error.getMessage()
                + ", model subscriptions = " + model.streams.get());
        StubChatModel raw = StubChatModel.failingFirstStreamAfter(3);
        String replayed = String.join("", raw.stream(new org.springframework.ai.chat.prompt.Prompt(
                        List.of(new org.springframework.ai.chat.messages.SystemMessage("[d1] a b c d e")))).retry(2)
                .map(r -> r.getResult().getOutput().getText())
                .collectList()
                .block());
        System.out.println("P6 F6 (Reactor) model.stream(prompt).retry(2), same failure: client-visible text = \""
                + replayed.trim() + "\"");
    }

    static void filterInjection() throws Exception {
        RecordingChannel out = new RecordingChannel();
        service(StubChatModel.free(), PROPS)
                .answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, "x' || dept != 'x"), out);
        out.awaitEnd(5_000);
        System.out.println("P7 F7 department = \"x' || dept != 'x\": cited sources = [" + out.data("sources")
                + "], answer quotes another tenant's document = "
                + (out.data("token").contains(Corpus.GLOBEX_TEXT) ? "yes" : "no"));
    }

    static void stalledModel() throws Exception {
        RagProperties fast = new RagProperties(3, 8, 0.95, Duration.ofMillis(100));
        RecordingChannel out = new RecordingChannel();
        service(StubChatModel.stalled(), fast).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), out);
        boolean ended = out.awaitEnd(1_500);
        System.out.println("P8 F8 provider accepts the request and never sends a token (tokenTimeout = 100 ms): response"
                + " ended within 1.5 s = " + (ended ? "yes (" + out.endedWith() + ")" : "no (still open)"));
    }

    public static void main(String[] args) throws Exception {
        System.out.println("PR10 probes against the " + (args.length > 0 ? args[0] : "?") + " answer service");
        starvation();
        disconnect();
        aclLeak();
        crossTenantCache();
        partialCached();
        retry();
        retryLemma();
        filterInjection();
        stalledModel();
        System.exit(0);
    }
}
```

</details>

<details><summary><b>The refactor as a diff (PR → fixed)</b></summary>

```diff
diff --git a/assistant/src/main/java/com/acme/assist/AnswerService.java b/assistant/src/main/java/com/acme/assist/AnswerService.java
index 0ce2238..0668c86 100644
--- a/assistant/src/main/java/com/acme/assist/AnswerService.java
+++ b/assistant/src/main/java/com/acme/assist/AnswerService.java
@@ -2,8 +2,8 @@ package com.acme.assist;
 
 import java.util.List;
 import java.util.Optional;
-import java.util.concurrent.ExecutorService;
-import java.util.concurrent.Executors;
+import java.util.TreeSet;
+import java.util.concurrent.atomic.AtomicBoolean;
 import java.util.stream.Collectors;
 import org.springframework.ai.chat.client.ChatClient;
 import org.springframework.ai.chat.model.ChatModel;
@@ -11,6 +11,13 @@ import org.springframework.ai.document.Document;
 import org.springframework.ai.embedding.EmbeddingModel;
 import org.springframework.ai.vectorstore.SearchRequest;
 import org.springframework.ai.vectorstore.VectorStore;
+import org.springframework.ai.vectorstore.filter.Filter;
+import org.springframework.ai.vectorstore.filter.FilterExpressionBuilder;
+import reactor.core.Disposable;
+import reactor.core.Disposables;
+import reactor.core.publisher.Flux;
+import reactor.core.scheduler.Schedulers;
+import reactor.util.retry.Retry;
 
 /** Answers questions from the tenant's documents (retrieval-augmented generation), streamed as server-sent events. */
 public final class AnswerService {
@@ -18,60 +25,66 @@ public final class AnswerService {
     private final ChatClient chat;
     private final VectorStore store;
     private final SemanticCache cache;
-    private final RagProperties props;
-    private final ExecutorService streams;
+    private final RagProperties props; // streamThreads is no longer used: a stream holds no thread while it waits
 
     public AnswerService(ChatModel model, VectorStore store, EmbeddingModel embeddings, RagProperties props) {
         this.chat = ChatClient.create(model);
         this.store = store;
         this.cache = new SemanticCache(embeddings, props.cacheThreshold());
         this.props = props;
-        this.streams = Executors.newFixedThreadPool(props.streamThreads()); // one thread per in-flight model stream
     }
 
-    /** Streams one "sources" event, then "token" events, then completes. Returns at once; the work runs on the pool. */
+    /** Streams one "sources" event, then "token" events, then completes. Returns once the stream is subscribed. */
     public void answer(UserContext user, RagRequest request, SseChannel out) {
-        Optional<String> cached = cache.lookup(request.question());
+        String scope = scopeOf(user, request); // everything that decides which documents an answer may quote
+        Optional<String> cached = cache.lookup(scope, request.question());
         if (cached.isPresent()) {
             out.send("token", cached.get());
             out.complete();
             return;
         }
-        streams.submit(() -> {
-            List<Document> docs = store.similaritySearch(SearchRequest.builder()
-                    .query(request.question())
-                    .topK(props.topK())
-                    .filterExpression(filterFor(user, request))
-                    .build());
-            List<Document> visible = docs.stream()
-                    .filter(d -> user.groups().contains(d.getMetadata().get("acl")))
-                    .toList();
-            out.send("sources", ids(visible));
-            StringBuilder answer = new StringBuilder();
-            try {
-                for (String token : chat.prompt()
-                        .system(systemPrompt(docs)) // the model needs the full context; only citations are filtered
+        List<Document> docs = store.similaritySearch(SearchRequest.builder()
+                .query(request.question())
+                .topK(props.topK())
+                .filterExpression(filterFor(user, request)) // tenant, department and ACL enforced by the store
+                .build());
+        out.send("sources", ids(docs)); // the documents cited are exactly the documents the model sees
+        StringBuilder answer = new StringBuilder();
+        AtomicBoolean started = new AtomicBoolean();
+        Disposable.Swap subscription = Disposables.swap();
+        out.onClose(subscription::dispose); // client gone or response ended: cancel the provider stream
+        subscription.update(Flux.defer(() -> chat.prompt() // a fresh request per attempt: the advisor chain is single-use
+                        .system(systemPrompt(docs))
                         .user(request.question())
                         .stream()
-                        .content()
-                        .retry(2) // ride out transient provider errors
-                        .toIterable()) {
-                    answer.append(token);
-                    out.send("token", token);
-                }
-            } finally {
-                cache.put(request.question(), answer.toString());
-            }
-            out.complete();
-        });
+                        .content())
+                .timeout(props.tokenTimeout()) // a stalled provider ends the request instead of holding it open
+                .doOnNext(token -> started.set(true))
+                .retryWhen(Retry.max(2).filter(e -> !started.get())) // never replay tokens the client already has
+                .publishOn(Schedulers.boundedElastic()) // SSE writes block: keep them off the provider's I/O threads
+                .subscribe(
+                        token -> {
+                            answer.append(token);
+                            out.send("token", token);
+                        },
+                        error -> out.error("generation failed"),
+                        () -> {
+                            cache.put(scope, request.question(), answer.toString()); // complete answers only
+                            out.complete();
+                        }));
     }
 
-    private static String filterFor(UserContext user, RagRequest request) {
-        String filter = "tenant == '" + user.tenant() + "'";
+    private static Filter.Expression filterFor(UserContext user, RagRequest request) {
+        FilterExpressionBuilder b = new FilterExpressionBuilder();
+        FilterExpressionBuilder.Op filter = b.and(b.eq("tenant", user.tenant()), b.in("acl", user.groups().toArray()));
         if (request.department() != null && !request.department().isBlank()) {
-            filter += " && dept == '" + request.department() + "'";
+            filter = b.and(filter, b.eq("dept", request.department())); // a value, never parsed as filter syntax
         }
-        return filter;
+        return filter.build();
+    }
+
+    private static String scopeOf(UserContext user, RagRequest request) {
+        return user.tenant() + "|" + new TreeSet<>(user.groups()) + "|" + request.department();
     }
 
     static String systemPrompt(List<Document> docs) {
diff --git a/assistant/src/main/java/com/acme/assist/SemanticCache.java b/assistant/src/main/java/com/acme/assist/SemanticCache.java
index e24e107..6f7147f 100644
--- a/assistant/src/main/java/com/acme/assist/SemanticCache.java
+++ b/assistant/src/main/java/com/acme/assist/SemanticCache.java
@@ -5,10 +5,14 @@ import java.util.Optional;
 import java.util.concurrent.CopyOnWriteArrayList;
 import org.springframework.ai.embedding.EmbeddingModel;
 
-/** Reuses answers for questions whose embeddings are nearly identical: most traffic is the same dozen questions. */
+/**
+ * Reuses answers for questions whose embeddings are nearly identical: most traffic is the same dozen questions. An answer
+ * is only reusable within the scope it was produced for (tenant, groups, filters), because it quotes that scope's
+ * documents.
+ */
 public final class SemanticCache {
 
-    private record Entry(float[] embedding, String answer) {
+    private record Entry(String scope, float[] embedding, String answer) {
     }
 
     private final EmbeddingModel embeddings;
@@ -20,13 +24,16 @@ public final class SemanticCache {
         this.threshold = threshold;
     }
 
-    public Optional<String> lookup(String question) {
+    public Optional<String> lookup(String scope, String question) {
         float[] q = embeddings.embed(question);
-        return entries.stream().filter(e -> cosine(q, e.embedding()) >= threshold).map(Entry::answer).findFirst();
+        return entries.stream()
+                .filter(e -> e.scope().equals(scope) && cosine(q, e.embedding()) >= threshold)
+                .map(Entry::answer)
+                .findFirst();
     }
 
-    public void put(String question, String answer) {
-        entries.add(new Entry(embeddings.embed(question), answer));
+    public void put(String scope, String question, String answer) {
+        entries.add(new Entry(scope, embeddings.embed(question), answer));
     }
 
     static double cosine(float[] a, float[] b) {
diff --git a/assistant/src/test/java/com/acme/assist/AnswerServiceTest.java b/assistant/src/test/java/com/acme/assist/AnswerServiceTest.java
index 1d65b1d..1888b2a 100644
--- a/assistant/src/test/java/com/acme/assist/AnswerServiceTest.java
+++ b/assistant/src/test/java/com/acme/assist/AnswerServiceTest.java
@@ -12,15 +12,20 @@ import org.junit.jupiter.api.Test;
 class AnswerServiceTest {
 
     private static final RagProperties PROPS = new RagProperties(3, 8, 0.95, Duration.ofSeconds(30));
+    private static final String Q3 = "What is the Q3 plan?";
 
     private static AnswerService service(StubChatModel model) {
-        return new AnswerService(model, Corpus.store(), new HashingEmbeddingModel(), PROPS);
+        return service(model, PROPS);
+    }
+
+    private static AnswerService service(StubChatModel model, RagProperties props) {
+        return new AnswerService(model, Corpus.store(), new HashingEmbeddingModel(), props);
     }
 
     @Test
     void streamsSourcesThenTokens() throws Exception {
         RecordingChannel out = new RecordingChannel();
-        service(StubChatModel.free()).answer(Corpus.ACME_ENGINEER, new RagRequest("What is the Q3 plan?", null), out);
+        service(StubChatModel.free()).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), out);
         assertTrue(out.awaitEnd(5_000));
         assertEquals("complete", out.endedWith());
         assertTrue(out.data("sources").contains("acme-plan-1"));
@@ -28,47 +33,137 @@ class AnswerServiceTest {
     }
 
     @Test
-    void citationsHideRestrictedDocuments() throws Exception {
+    void restrictedDocumentsNeverReachTheAnswer() throws Exception {
         RecordingChannel out = new RecordingChannel();
-        service(StubChatModel.free()).answer(Corpus.ACME_ENGINEER, new RagRequest("What is the Q3 plan?", null), out);
+        service(StubChatModel.free()).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), out);
         assertTrue(out.awaitEnd(5_000));
         assertFalse(out.data("sources").contains("acme-hr-1"));
+        assertFalse(out.data("token").contains(Corpus.HR_ONLY_TEXT));
     }
 
     @Test
     void departmentFilterNarrowsSources() throws Exception {
         RecordingChannel out = new RecordingChannel();
-        service(StubChatModel.free()).answer(Corpus.ACME_ENGINEER, new RagRequest("What is the Q3 plan?", "strategy"), out);
+        service(StubChatModel.free()).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, "strategy"), out);
         assertTrue(out.awaitEnd(5_000));
         assertEquals("acme-plan-1", out.data("sources"));
     }
 
+    @Test
+    void departmentValueCannotRewriteTheFilter() throws Exception {
+        RecordingChannel out = new RecordingChannel();
+        service(StubChatModel.free()).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, "x' || dept != 'x"), out);
+        assertTrue(out.awaitEnd(5_000));
+        assertEquals("", out.data("sources"));
+        assertFalse(out.data("token").contains(Corpus.GLOBEX_TEXT));
+    }
+
+    @Test
+    void cacheIsScopedToTenantAndGroups() throws Exception {
+        AnswerService service = service(StubChatModel.free());
+        RecordingChannel hr = new RecordingChannel();
+        service.answer(Corpus.ACME_HR, new RagRequest(Q3, null), hr);
+        assertTrue(hr.awaitEnd(5_000));
+        RecordingChannel globex = new RecordingChannel();
+        service.answer(Corpus.GLOBEX_ANALYST, new RagRequest(Q3, null), globex);
+        assertTrue(globex.awaitEnd(5_000));
+        assertTrue(globex.data("token").contains(Corpus.GLOBEX_TEXT));
+        assertFalse(globex.data("token").contains(Corpus.HR_ONLY_TEXT));
+    }
+
     @Test
     void repeatedQuestionIsServedFromCache() throws Exception {
         StubChatModel model = StubChatModel.free();
         AnswerService service = service(model);
         RecordingChannel first = new RecordingChannel();
-        service.answer(Corpus.ACME_ENGINEER, new RagRequest("What is the Q3 plan?", null), first);
+        service.answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), first);
         assertTrue(first.awaitEnd(5_000));
         RecordingChannel second = new RecordingChannel();
-        service.answer(Corpus.ACME_ENGINEER, new RagRequest("What is the Q3 plan?", null), second);
+        service.answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), second);
         assertTrue(second.awaitEnd(5_000));
         assertEquals(1, model.streams.get());
         assertEquals(first.data("token"), second.data("token"));
     }
 
     @Test
-    void concurrentRequestsAllComplete() throws Exception {
-        AnswerService service = service(StubChatModel.free());
+    void partialAnswersAreNotCached() throws Exception {
+        StubChatModel model = StubChatModel.gated();
+        AnswerService service = service(model);
+        RecordingChannel first = new RecordingChannel();
+        service.answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), first);
+        model.release(1);
+        assertTrue(first.awaitCount("token", 1, 5_000));
+        first.disconnect();
+        model.release(1_000);
+        assertTrue(model.awaitEnded(5_000));
+        RecordingChannel second = new RecordingChannel();
+        service.answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), second);
+        assertTrue(second.awaitEnd(5_000));
+        assertEquals(2, model.streams.get());
+        assertTrue(second.data("token").contains("EU region"));
+    }
+
+    @Test
+    void disconnectCancelsGeneration() throws Exception {
+        StubChatModel model = StubChatModel.gated();
+        RecordingChannel out = new RecordingChannel();
+        service(model).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), out);
+        model.release(1);
+        assertTrue(out.awaitCount("token", 1, 5_000));
+        out.disconnect();
+        model.release(1_000);
+        assertTrue(model.awaitEnded(5_000));
+        assertEquals(1, model.generated.get());
+        assertEquals(1, model.cancelled.get());
+    }
+
+    @Test
+    void manySlowStreamsDoNotStarveNewRequests() throws Exception {
+        StubChatModel model = StubChatModel.gated(); // no tokens until released: every stream is "slow"
+        AnswerService service = service(model);
         List<RecordingChannel> outs = new ArrayList<>();
-        for (int i = 0; i < 4; i++) {
+        for (int i = 0; i < 20; i++) {
             RecordingChannel out = new RecordingChannel();
             outs.add(out);
             service.answer(Corpus.ACME_ENGINEER, new RagRequest("Question " + i + " about laptops", null), out);
         }
+        for (RecordingChannel out : outs) {
+            assertTrue(out.awaitCount("sources", 1, 5_000));
+        }
+        model.release(100_000);
         for (RecordingChannel out : outs) {
             assertTrue(out.awaitEnd(5_000));
-            assertEquals("complete", out.endedWith());
         }
     }
+
+    @Test
+    void midStreamFailureIsNotReplayed() throws Exception {
+        StubChatModel model = StubChatModel.failingFirstStreamAfter(3);
+        RecordingChannel out = new RecordingChannel();
+        service(model).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), out);
+        assertTrue(out.awaitEnd(5_000));
+        assertEquals("error", out.endedWith());
+        assertEquals(3, out.count("token"));
+        assertEquals(1, model.streams.get());
+    }
+
+    @Test
+    void failureBeforeTheFirstTokenIsRetried() throws Exception {
+        StubChatModel model = StubChatModel.failingFirstStreamAfter(0);
+        RecordingChannel out = new RecordingChannel();
+        service(model).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), out);
+        assertTrue(out.awaitEnd(5_000));
+        assertEquals("complete", out.endedWith());
+        assertEquals(2, model.streams.get());
+        assertTrue(out.data("token").contains("EU region"));
+    }
+
+    @Test
+    void stalledModelTimesOut() throws Exception {
+        RagProperties fast = new RagProperties(3, 8, 0.95, Duration.ofMillis(100));
+        RecordingChannel out = new RecordingChannel();
+        service(StubChatModel.stalled(), fast).answer(Corpus.ACME_ENGINEER, new RagRequest(Q3, null), out);
+        assertTrue(out.awaitEnd(5_000));
+        assertEquals("error", out.endedWith());
+    }
 }
```

</details>

---

## 9. Scoring this PR

| # | Defect | Severity (weight) | Tier | Typically found by |
|---|---|---|---|---|
| F3 | Context unfiltered, citations filtered | Sev-1 (5) | 2 | L6+ (L5s see "ACL filter present" and move on) |
| F4 | Cache ignores tenant and groups | Sev-1 (5) | 10 | L6+ |
| F7 | Filter-expression injection | Sev-1 (5) | 10 | L6+ security-minded |
| F1 | Streams pin a fixed pool | Sev-1 (5) | 10 | L6+ (requires seeing the blocking inside `toIterable`) |
| F2 | No cancel on disconnect | Sev-2 (3) | 10 | L6+ |
| F5 | `finally` caches partials | Sev-2 (3) | 10 | L6+ |
| F8 | Timeout configured, never applied | Sev-2 (3) | 2 | L5+ (an unused record component) |
| F6 | `retry` on a token stream | Sev-2 (3) | 20 | L7 (replay semantics *and* the library's single-use chain) |

Total **32**. L5s find F8 and maybe F1. L6s add F3, F4, F7, F2 and F5. L7s unify them into scope and lifecycle, catch F6 at both levels (replay, and Spring AI 2.0.2's non-resubscribable stream), and leave `CopyOnWriteArrayList` alone (D1).

---

## 10. Failure modes (reviewers on this PR)

| Failure mode | What it looks like | Why it fails |
|---|---|---|
| "Raise `streamThreads` to 200" | Fewer complaints | Moves the cliff; each stall still leaks a thread forever |
| "Use virtual threads" for F1 | Removes the thread cap | Doesn't fix F2, F5, F6 or F8; the stream still isn't cancelled or bounded |
| "Tell the model not to reveal restricted docs" | A prompt rule | Prompt instructions aren't access control; filter before the model reads |
| Post-filter the context too | Fixes F3 | Correct but loses recall: `topK` is spent on unreadable chunks; prefer the store filter |
| Escaping quotes in `department` | Blocks this payload | Ad-hoc escaping of a grammar you don't own; use the builder and an allow-list |
| Disabling the cache | Removes F4 and F5 | Gives up the feature; scope the key and write on complete |
| `onErrorResume(e -> Flux.empty())` | No more spinners | Turns failures into silently truncated "complete" answers, which then get cached |

---

## 11. Bar-raiser chains

<details><summary><b>Q1 · "answer() returns immediately. Why do you say it blocks?"</b></summary>

**Initial Prompt.** Where blocking hides in reactive code.

**L5 Answer.** "It runs on an executor, so the request thread is free."

**Why L5 Stalls.** Correct about the servlet thread, but misses that the pool thread is now the scarce resource.

**L7 Answer.** "The servlet thread is freed, but `toIterable()` parks a pool thread per in-flight stream for 10–40 s. With 8 threads, concurrency is capped at 8 *answers*, not 8 requests per second. Requests beyond that queue invisibly: no first event, no timeout, no metric. Subscribing instead of iterating means no thread waits for tokens, since callbacks run when tokens arrive. The only blocking left is the SSE write, which I move to `boundedElastic` so the provider's I/O threads never block."

</details>

<details><summary><b>Q2 · "The citations are filtered. Isn't that enough for compliance?"</b></summary>

**Initial Prompt.** What counts as disclosure in RAG.

**L5 Answer.** "Yes, users only see sources they may read."

**Why L5 Stalls.** Treats the citation list as the output. The output is the generated text.

**L7 Answer.** "The model's context window is a disclosure boundary: anything it reads can come back out, paraphrased, summarized or quoted. The probe shows the HR chunk quoted to an engineer with a clean citation list. So ACLs apply at retrieval, as a store filter on `acl in groups`, and the documents cited and the documents in context are the same list. OWASP's LLM08:2025 says the same: permission-aware vector stores and partitioned datasets."

</details>

<details><summary><b>Q3 · "How should a semantic cache work in a multi-tenant RAG system?"</b></summary>

**Initial Prompt.** Caching generated content safely.

**L5 Answer.** "Key it by user ID."

**Why L5 Stalls.** Safe, but discards most of the hit rate. The right key is the scope, not the user.

**L7 Answer.** "Key by everything that determines which documents the answer may quote: tenant, the user's effective groups (sorted), and the request's filters. Two users with the same scope can share an answer, while users with different scopes never do. Write only completed answers. Bound it with LRU and TTL, and invalidate a tenant's entries when its corpus or ACLs change, or the cache serves documents that were deleted or re-permissioned. Log hit rate per scope, so you can see if scoping made the cache useless."

</details>

<details><summary><b>Q4 · "The PR retries twice. What's wrong with retries here?"</b></summary>

**Initial Prompt.** Retry semantics for streams.

**L5 Answer.** "Nothing, transient errors happen."

**Why L5 Stalls.** Treats a stream like a request/response call.

**L7 Answer.** "Two problems. Semantically, once a token is on the wire, re-subscribing replays it: users see duplicated text and you pay twice. Mechanically, in Spring AI 2.0.2 a `ChatClient` stream can't be re-subscribed at all. The probe shows `IllegalStateException: No StreamAdvisors available to execute`, which replaces the provider's real error. The fix retries only while nothing has been sent, around `Flux.defer(() -> chat.prompt()…)` so each attempt is a new request. After the first token, send an error event and let the client offer 'regenerate'."

</details>

<details><summary><b>Q5 · "Why is building the filter as a string an injection risk if it's not SQL?"</b></summary>

**Initial Prompt.** Query languages beyond SQL.

**L5 Answer.** "Only SQL is injectable."

**Why L5 Stalls.** Injection is about mixing code and data in any parsed language.

**L7 Answer.** "Spring AI parses string filters with a grammar that has quotes, `&&`, `||`, `!=`, `in`. Concatenating a client-controlled value lets the client write syntax. Here `x' || dept != 'x` turns a tenant-scoped query into a global one. The builder API keeps values as values, and it's portable: the same `Filter.Expression` is translated per store (PGvector, Elasticsearch, Redis), so string escaping would have to be right for every backend. Plus an allow-list of department names, because a dropdown value is still user input."

</details>

<details><summary><b>Q6 · "What does cancellation buy you beyond tidiness?"</b></summary>

**Initial Prompt.** The cost model of abandoned streams.

**L5 Answer.** "Saves a little CPU."

**Why L5 Stalls.** Misses money and capacity.

**L7 Answer.** "Three things. Provider cost: output tokens are billed whether anyone reads them. Users who navigate away mid-answer, which is common with long answers, cost the full answer. Provider-side concurrency: most providers rate-limit concurrent streams per key, so abandoned streams consume quota other users need. Our own capacity: in the PR they also hold pool threads. The probe shows 30 tokens generated after the disconnect versus 0 with `onClose → dispose`."

</details>

<details><summary><b>Q7 · "How would you load-test this before launch?"</b></summary>

**Initial Prompt.** Validating streaming capacity.

**L5 Answer.** "Run a few hundred requests against staging."

**Why L5 Stalls.** Against a real provider, results depend on provider latency that day, and cost money.

**L7 Answer.** "Against a stub provider with controllable per-token latency and stall and failure injection: the `StubChatModel` modes, behind the real HTTP client in staging. The scenarios: steady state at expected concurrency; provider latency doubling (does time-to-first-token stay flat?); 5% of streams stalling (do timeouts free resources?); 30% of clients disconnecting mid-stream (does provider concurrency drop?); and a cache-hit-heavy mix. The metrics: time to first token, concurrent provider streams, tokens billed per answer delivered, and error events by cause."

</details>

<details><summary><b>Q8 · "Rank the findings."</b></summary>

**Initial Prompt.** Prioritization.

**L5 Answer.** "F1 first: outages are the worst."

**Why L5 Stalls.** An outage is recoverable. A disclosure isn't.

**L7 Answer.** "F4 and F7 (cross-tenant disclosure, contractual and regulatory exposure; F7 is attacker-driven), then F3 (within-tenant restricted disclosure). Then F1 (feature outage under ordinary provider slowness), F8 (which makes F1 permanent), then F5 and F6 (wrong answers served or shown), then F2 (cost). The disclosures block the merge even behind a feature flag, because a flag doesn't un-disclose what was cached."

</details>

---

## 12. Checklist

- [ ] Does anything block a thread for the life of a stream (`toIterable`, `blockLast`, `get`)? Subscribe instead.
- [ ] Does disconnect, timeout or error dispose the subscription? Is there a race between subscribe and close?
- [ ] Is there a timeout on the token stream (gap between tokens, including the first)?
- [ ] Retries: only before the first token, on a freshly built request.
- [ ] ACLs and tenant applied at retrieval; context and citations come from the same list.
- [ ] Filters built with the builder API; client values allow-listed.
- [ ] Cache key includes the full scope; written on complete only; bounded and invalidated on corpus or ACL changes.
- [ ] Tests: gated, stalled and failing stub models; answer-text assertions; cross-tenant; hostile filter values.

---

## 13. References

- OWASP Top 10 for LLM Applications 2025: LLM08:2025 Vector and Embedding Weaknesses. https://genai.owasp.org/llmrisk/llm082025-vector-and-embedding-weaknesses/
- Spring AI reference: Vector Databases (metadata filters, `FilterExpressionBuilder`). https://docs.spring.io/spring-ai/reference/api/vectordbs.html
- Spring AI reference: Chat Client API (streaming). https://docs.spring.io/spring-ai/reference/api/chatclient.html
- Reactor reference guide (cancellation, `retryWhen`, `timeout`). https://projectreactor.io/docs/core/release/reference/
- Within this KB: [PR11 MCP tool server](02-pr11-mcp-tool-server-confused-deputy-and-non-idempotent-agent-retries.md) · [PR03 multi-tenant auth](../02-Java-Spring-Hibernate-and-Microservices-PR-Simulations/03-pr03-multi-tenant-auth-cache-stampede-idor-and-jwt-security-flaws.md) · [01-02 Layer 6](../01-The-L7-Code-Review-Mental-Model-and-Rubric/02-the-7-layer-fault-scan-correctness-concurrency-io-compat-security.md#8-layer-6-security-and-trust-boundaries)
