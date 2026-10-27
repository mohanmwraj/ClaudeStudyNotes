# 04 · The LLM Gateway: Semantic Caching, Token-Aware Rate Limiting, and OpenTelemetry GenAI

> **Folder:** `07-Production-Code-Blueprints-Java-and-Python/` · **File 4 of 4**
> **Anchoring specifications and research:** OpenTelemetry Semantic Conventions for Generative AI (spans
> `gen_ai.*`, metrics `gen_ai.client.token.usage` and `gen_ai.client.operation.duration`; Development status) and the
> OpenTelemetry Java SDK **1.62.0** · ITU-T I.371 / ATM Forum, the Generic Cell Rate Algorithm (GCRA) · M. Shreedhar
> and G. Varghese, *Efficient Fair Queuing Using Deficit Round Robin* (SIGCOMM 1995) · F. Bang, *GPTCache* (2023).
> **Code baseline:** Java 21 (JDK 25.0.4) with the real OTel SDK and its in-memory exporters · Python 3.10+ (stdlib).
> **Previous:** [03 · Hybrid search SQL and Kafka CDC](03-hybrid-search-sql-postgres-and-kafka-cdc-ingestion-pipeline.md) ·
> **Next folder:** `08-FAANG-L7-AI-Architecture-Playbook-and-Bar-Raiser-QA/`

---

## 0. The thesis in one paragraph

The gateway in front of model servers is where cost, fairness and observability are decided, and each feature has
a trap measured below:

- **A semantic cache** saves money only if wrong hits are rarer than the economics allow. Embeddings are nearly
  blind to identifiers, so "status of order A-18" scored **1.000** against a cached "order A-17". Without an entity
  guard, entity near-misses hit 3/3 at the usual 0.80 threshold. At a 25% hit rate, **one wrong answer per 1,942
  requests** erases the savings when a wrong answer costs $2.
- **Rate limits must be token-aware, per tenant, and reserve-then-refund.** A global-only limit let a flooding tenant
  reject 37 of 60 of a quiet tenant's requests; per-tenant buckets rejected none. Counting tokens after completion
  let 20 concurrent long requests spend **1.9×** the budget; reservation kept it at 0.76×.
- **Telemetry follows the GenAI semantic conventions**: provider, model, tokens, finish reasons and `error.type` on
  every span; histograms for token usage and duration; prompts and completions **off by default**; cache hits
  labelled so they do not mask model latency.
- **Under overload, weighted fair admission (DRR)** keeps a premium tenant's p95 wait at 0.0 s while FIFO gives it
  12.1 s.

---

## 1. First principles

### 1.1 What a semantic cache can and cannot know

A semantic cache maps a new prompt to a cached one when `cos(embed(new), embed(cached)) ≥ θ`. Two facts bound it:

1. **The answer depends on more than the user text.** The key must include the tenant, model, system prompt,
   tool-set version and any retrieved-context version. The listing hashes these into a *scope*. Without it, tenant
   A's answer serves tenant B, and yesterday's tool behaviour serves today.
2. **Embeddings compress away the details that change answers.** Identifiers, numbers, dates and negations carry
   little weight in dense embeddings. The listing models this by masking digits in its embedder, and
   `cos("…order A-17", "…order A-18") = 1.000`, as high as a true paraphrase. **No threshold separates them.** An
   *entity guard*, requiring exact equality of extracted identifiers and numbers, removes that class entirely: 0/3
   entity wrong hits at every threshold.

What is left are **semantic near-misses** ("opened software" vs "opened games", "Canada" vs "Mexico"). Only the
threshold, a verifier or a narrower scope handles those:

| θ | Paraphrase hits | Semantic wrong hits |
|---|---|---|
| 0.70 | 5/6 | 3/3 |
| 0.80 | 5/6 | 1/3 |
| 0.90 | 4/6 | 0/3 |
| 0.95 | 3/6 | 0/3 |

The threshold is a precision/recall trade, and its price comes from §1.4.

Cache only what is safe to replay: `temperature = 0` requests, responses that finished with `stop` (not `length`),
no tool calls with side effects, and a TTL bounded by how fast the underlying facts change.

### 1.2 Token-aware rate limiting

Requests are the wrong unit: one request can be 50 tokens or 50,000. Limit **tokens per minute** per tenant and per
deployment, with a token bucket of rate `r` and capacity `b`.

- **Reserve, then refund.** At admission the true cost is unknown; it is bounded by `prompt_tokens + max_tokens`.
  Reserve that bound, and refund `reserved − actual` when usage arrives. Post-hoc counting (charge after completion)
  cannot see in-flight requests: in the lab, 20 concurrent requests were all admitted against a counter still at 0
  and spent **1.9×** the budget. Reservation admitted 8, spent 0.76× and returned 4,800 tokens for later requests.
  The cost of reservation is conservatism: a large `max_tokens` blocks budget until the refund, so encourage tight
  `max_tokens` per use case.
- **Two levels.** Per-tenant buckets isolate tenants from each other. A global per-deployment bucket protects the
  model server's goodput (Folder 02 File 01). In the noisy-neighbour run, the global-only limiter let acme's 10×
  flood consume the shared budget and reject 37 of globex's 60 requests. With per-tenant buckets globex lost none
  and acme was held to its quota (181 admitted).
- **Retry-After is computable.** A bucket short by `d` tokens refills in `d / r`. Return that, and well-behaved
  clients (File 02 §1.4) wait exactly long enough.

### 1.3 GCRA: one timestamp per tenant

The Generic Cell Rate Algorithm keeps only the *theoretical arrival time* (TAT). A request of cost `c` is admitted if
`max(TAT, now) + c·T − now ≤ τ`, where `T = 1/r` and `τ = b·T`; then `TAT ← max(TAT, now) + c·T`. It is exactly
equivalent to the token bucket: the lab's 400-request trace produced identical decisions, 49 admits each. It needs
8 bytes of state and one atomic compare-and-set, which makes it the natural design for a distributed limiter in a
Redis script or a sharded counter service.

### 1.4 Semantic-cache economics

Monthly net savings:

```text
net = N·h·c_call − N·c_lookup − N·f·c_wrong          (every request pays the lookup; hits save the model call)
```

Here `h` is the hit rate, `f` the false-hit rate and `c_wrong` the cost of a wrong cached answer (an escalation, a
wrong refund, lost trust). With the lab's assumptions (30M requests, $0.0042 per call, $0.00002 per lookup, $2 per
wrong answer), a 25% hit rate saves $30,900/month with no false hits and **loses $269,100** at a 0.5% false-hit
rate. The break-even false-hit rate is `(h·c_call − c_lookup) / c_wrong` = **0.051%**.

Two conclusions follow:

- The threshold is a business decision priced by `c_wrong`.
- Low-hit-rate traffic (open-ended chat at a few percent) rarely pays for a semantic cache. The exact-match prompt
  cache and the model server's prefix cache (Folder 01 File 03) are the safer wins.

### 1.5 Fair admission under overload

When demand exceeds goodput, something queues or something is rejected. With **FIFO**, the flooding tenant sets
everyone's wait: premium p95 was 12.1 s in the lab. **Deficit round robin** with weights (premium 3, free 1) serves
the premium queue first in each round: premium p95 was 0.0 s, and the free tier absorbed the overload (p95 14.2 s).

In production, queue only up to a deadline (the request's TTFT budget) and reject beyond it with 429 and
Retry-After. A request that will time out anyway should not occupy a slot.

### 1.6 OpenTelemetry GenAI conventions

The GenAI semantic conventions (Development status; ⚠ verify the attribute set against the semconv version you pin)
define:

- **Span:** name `"{gen_ai.operation.name} {gen_ai.request.model}"` (here `chat llama-3-70b`), kind `CLIENT`.
  Attributes:
  - `gen_ai.operation.name`, `gen_ai.provider.name` (which replaced the older `gen_ai.system`);
  - `gen_ai.request.model`, `gen_ai.request.max_tokens`, `gen_ai.request.temperature`;
  - `gen_ai.response.model`, `gen_ai.response.finish_reasons`;
  - `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`;
  - `error.type` on failure.
- **Metrics:** histogram `gen_ai.client.token.usage` (unit `{token}`, attribute `gen_ai.token.type` = `input` or
  `output`), and histogram `gen_ai.client.operation.duration` (unit `s`). Server-side conventions add
  time-to-first-token and time-per-output-token histograms.
- **Content is opt-in.** Prompts and completions are PII and secrets risk. The conventions put them in opt-in events,
  not default span attributes, and the listing asserts no prompt text appears in its telemetry.

Gateway-specific attributes (`gateway.tenant`, `gateway.cache.hit`, `gateway.ratelimit.decision`) sit beside them.
`gateway.cache.hit` is also a metric attribute: a 15 ms cache hit in the same histogram as a 1.74 s model call
hides model-latency regressions as the hit rate rises.

---

## 2. Production code blueprints

### 2.1 Java 21 + OpenTelemetry SDK 1.62: the gateway, its experiments and its telemetry

```java
// LlmGateway.java - the control plane in front of model servers: a semantic cache that is scoped and entity-guarded,
// per-tenant token-bucket rate limiting that RESERVES estimated tokens up front and refunds the difference, and
// OpenTelemetry GenAI-convention spans and metrics, exported in-memory by the real OTel Java SDK 1.62 and printed.
// Experiments (deterministic, virtual clock):
//   1. cache threshold sweep on labelled paraphrases and near-misses ("order A-17" vs "order A-18"), with and without
//      an entity guard - similarity alone cannot tell them apart;
//   2. a noisy neighbour flooding 10x its quota: global-only limiting vs per-tenant buckets;
//   3. a burst of concurrent long requests: post-hoc token accounting overshoots the budget, reservation does not;
//   4. three requests through the gateway (miss, hit, rate-limited) and the spans/metrics they emit.
// Build: javac --release 21 -cp <opentelemetry-sdk 1.62.0 + opentelemetry-sdk-testing 1.62.0>
package dev.l7.ai.inference;

import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.metrics.DoubleHistogram;
import io.opentelemetry.api.metrics.LongHistogram;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.metrics.SdkMeterProvider;
import io.opentelemetry.sdk.metrics.data.MetricData;
import io.opentelemetry.sdk.testing.exporter.InMemoryMetricReader;
import io.opentelemetry.sdk.testing.exporter.InMemorySpanExporter;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.data.SpanData;
import io.opentelemetry.sdk.trace.export.SimpleSpanProcessor;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class LlmGateway {

    // ------------------------------------------------------------------ semantic cache
    /** Dense embedders are notoriously insensitive to identifiers and numbers; masking digits reproduces that. */
    static double[] embed(String s) {
        String[] w = s.toLowerCase().replaceAll("[^a-z0-9\\- ]", " ").replaceAll("\\d", "#").trim().split("\\s+");
        double[] v = new double[256];
        for (int i = 0; i < w.length; i++) {
            if (Set.of("the", "of", "my", "is", "a", "for", "what", "me", "tell", "please", "an", "to").contains(w[i])) continue;
            v[Math.floorMod(w[i].hashCode(), 256)] += 1.0;
            if (i + 1 < w.length) v[Math.floorMod((w[i] + "_" + w[i + 1]).hashCode(), 256)] += 0.5;
        }
        double n = Math.sqrt(Arrays.stream(v).map(x -> x * x).sum());
        for (int k = 0; k < v.length; k++) v[k] /= n == 0 ? 1 : n;
        return v;
    }

    static double cos(double[] a, double[] b) {
        double d = 0;
        for (int i = 0; i < a.length; i++) d += a[i] * b[i];
        return d;
    }

    static final Pattern ENTITY = Pattern.compile("\\b([A-Z]{1,4}-\\d+|\\d+(?:\\.\\d+)?)\\b");

    static Set<String> entities(String s) {
        Set<String> out = new TreeSet<>();
        Matcher m = ENTITY.matcher(s.toUpperCase());
        while (m.find()) out.add(m.group(1));
        return out;
    }

    record CacheEntry(String scope, String prompt, double[] vec, Set<String> entities, String answer, String key, long expiresAt) {}

    static final class SemanticCache {
        final double threshold;
        final boolean entityGuard;
        final List<CacheEntry> entries = new ArrayList<>();

        SemanticCache(double threshold, boolean entityGuard) {
            this.threshold = threshold;
            this.entityGuard = entityGuard;
        }

        /** Scope = everything that changes the right answer besides the user text. */
        static String scope(String tenant, String model, String systemPrompt, String toolsVersion) {
            try {
                byte[] h = MessageDigest.getInstance("SHA-256").digest((tenant + "\u0000" + model + "\u0000" + systemPrompt + "\u0000"
                        + toolsVersion).getBytes(StandardCharsets.UTF_8));
                return HexFormat.of().formatHex(h, 0, 8);
            } catch (java.security.NoSuchAlgorithmException e) {
                throw new IllegalStateException(e);
            }
        }

        CacheEntry lookup(String scope, String prompt, long now) {
            double[] q = embed(prompt);
            Set<String> ents = entities(prompt);
            CacheEntry best = null;
            double bestSim = -1;
            for (CacheEntry e : entries) {
                if (!e.scope().equals(scope) || e.expiresAt() < now) continue;
                if (entityGuard && !e.entities().equals(ents)) continue;              // A-17 never answers A-18
                double s = cos(q, e.vec());
                if (s > bestSim) { bestSim = s; best = e; }
            }
            return bestSim >= threshold ? best : null;
        }

        void put(String scope, String prompt, String answer, String key, long now, long ttl) {
            entries.add(new CacheEntry(scope, prompt, embed(prompt), entities(prompt), answer, key, now + ttl));
        }
    }

    // ------------------------------------------------------------------ token-aware rate limiting
    static final class TokenBucket {
        final double capacity, ratePerMs;
        double tokens;
        long last;

        TokenBucket(double tokensPerMinute, double burstMinutes) {
            this.capacity = tokensPerMinute * burstMinutes;
            this.ratePerMs = tokensPerMinute / 60_000.0;
            this.tokens = capacity;
        }

        void refill(long now) {
            tokens = Math.min(capacity, tokens + (now - last) * ratePerMs);
            last = now;
        }

        /** Returns 0 if reserved, else the milliseconds until `n` tokens are available (the Retry-After). */
        long tryReserve(double n, long now) {
            refill(now);
            if (tokens >= n) {
                tokens -= n;
                return 0;
            }
            return (long) Math.ceil((n - tokens) / ratePerMs);
        }

        void refund(double n) { tokens = Math.min(capacity, tokens + n); }
    }

    // ------------------------------------------------------------------ the gateway
    record Request(String tenant, String model, String system, String user, int maxTokens, double temperature) {}

    record Response(int status, String body, int inputTokens, int outputTokens, boolean cacheHit, long retryAfterMs, String finish) {}

    static int estimateTokens(String s) { return Math.max(1, s.length() / 4); }

    static final class Gateway {
        final SemanticCache cache;
        final Map<String, TokenBucket> perTenant = new TreeMap<>();
        final TokenBucket global;
        final Tracer tracer;
        final DoubleHistogram duration;
        final LongHistogram tokenUsage;
        long now;

        Gateway(SemanticCache cache, double tenantTpm, double globalTpm, OpenTelemetrySdk otel) {
            this.cache = cache;
            this.global = new TokenBucket(globalTpm, 1);
            for (String t : List.of("acme", "globex")) perTenant.put(t, new TokenBucket(tenantTpm, 1));
            this.tracer = otel.getTracer("llm-gateway", "1.0.0");
            var meter = otel.getMeter("llm-gateway");
            this.duration = meter.histogramBuilder("gen_ai.client.operation.duration").setUnit("s")
                    .setDescription("GenAI operation duration").build();
            this.tokenUsage = meter.histogramBuilder("gen_ai.client.token.usage").ofLongs().setUnit("{token}")
                    .setDescription("Measures number of input and output tokens used").build();
        }

        /** The upstream model: deterministic usage and latency. */
        Response upstream(Request r) {
            int in = estimateTokens(r.system() + r.user()) + 12;
            int out = Math.min(r.maxTokens(), 40 + r.user().length() % 60);
            now += 300 + out * 20L;                                            // TTFT + TPOT x tokens (virtual ms)
            return new Response(200, "answer(" + r.user() + ")", in, out, false, 0, out == r.maxTokens() ? "length" : "stop");
        }

        Response handle(Request r) {
            long start = now;
            Span span = tracer.spanBuilder("chat " + r.model()).setSpanKind(SpanKind.CLIENT)
                    .setAttribute("gen_ai.operation.name", "chat")
                    .setAttribute("gen_ai.provider.name", "vllm")
                    .setAttribute("gen_ai.request.model", r.model())
                    .setAttribute("gen_ai.request.max_tokens", (long) r.maxTokens())
                    .setAttribute("gen_ai.request.temperature", r.temperature())
                    .setAttribute("gateway.tenant", r.tenant())
                    .startSpan();
            try {
                String scope = SemanticCache.scope(r.tenant(), r.model(), r.system(), "tools-v3");
                boolean cacheable = r.temperature() == 0.0;
                CacheEntry hit = cacheable ? cache.lookup(scope, r.user(), now) : null;
                if (hit != null) {
                    now += 15;                                                    // embedding + vector lookup
                    span.setAttribute("gateway.cache.hit", true);
                    return finish(span, r, start, new Response(200, hit.answer(), 0, 0, true, 0, "stop"));
                }
                span.setAttribute("gateway.cache.hit", false);
                int reserve = estimateTokens(r.system() + r.user()) + 12 + r.maxTokens();   // worst case for this call
                TokenBucket tb = perTenant.get(r.tenant());
                long wait = Math.max(tb.tryReserve(reserve, now), 0);
                if (wait == 0) {
                    long g = global.tryReserve(reserve, now);
                    if (g > 0) {
                        tb.refund(reserve);
                        wait = g;
                    }
                }
                if (wait > 0) {
                    span.setAttribute("gateway.ratelimit.decision", "reject");
                    span.setAttribute("error.type", "rate_limited");
                    span.setStatus(StatusCode.ERROR, "429");
                    return finish(span, r, start, new Response(429, "rate limited", 0, 0, false, wait, null));
                }
                span.setAttribute("gateway.ratelimit.decision", "allow");
                Response up = upstream(r);
                int unused = reserve - up.inputTokens() - up.outputTokens();
                tb.refund(unused);                                                // reconcile with actual usage
                global.refund(unused);
                if (cacheable && up.finish().equals("stop")) cache.put(scope, r.user(), up.body(), r.user(), now, 3_600_000);
                return finish(span, r, start, up);
            } finally {
                span.end();
            }
        }

        Response finish(Span span, Request r, long start, Response resp) {
            if (resp.status() == 200) {
                span.setAttribute("gen_ai.response.model", r.model());
                span.setAttribute(AttributeKey.stringArrayKey("gen_ai.response.finish_reasons"), List.of(resp.finish()));
                span.setAttribute("gen_ai.usage.input_tokens", (long) resp.inputTokens());
                span.setAttribute("gen_ai.usage.output_tokens", (long) resp.outputTokens());
            }
            Attributes base = Attributes.builder().put("gen_ai.operation.name", "chat").put("gen_ai.provider.name", "vllm")
                    .put("gen_ai.request.model", r.model()).build();
            Attributes withErr = resp.status() == 200 ? base : base.toBuilder().put("error.type", "rate_limited").build();
            duration.record((now - start) / 1000.0, withErr.toBuilder().put("gateway.cache.hit", resp.cacheHit()).build());   // hits must not mask model latency
            if (resp.status() == 200 && !resp.cacheHit()) {
                tokenUsage.record(resp.inputTokens(), base.toBuilder().put("gen_ai.token.type", "input").build());
                tokenUsage.record(resp.outputTokens(), base.toBuilder().put("gen_ai.token.type", "output").build());
            }
            return resp;
        }
    }

    // ------------------------------------------------------------------ experiments
    /** kind: "para" = a true paraphrase of a cached prompt; "entity" = differs only in an id/number; "semantic" = a content word. */
    record Probe(String text, String key, String kind) {}

    static final List<Probe> SEED = List.of(new Probe("what is the status of order A-17", "status A-17", "seed"),
            new Probe("refund policy for damaged items", "refund damaged", "seed"),
            new Probe("refund policy for opened software", "refund software", "seed"),
            new Probe("how long does shipping take to Canada", "ship canada", "seed"),
            new Probe("warranty length for electronics", "warranty", "seed"),
            new Probe("can I get a refund of 25 dollars", "refund 25", "seed"));

    static final List<Probe> PROBES = List.of(
            new Probe("status of my order A-17?", "status A-17", "para"),
            new Probe("tell me the status of order A-17 please", "status A-17", "para"),
            new Probe("what is the refund policy for damaged items", "refund damaged", "para"),
            new Probe("refund policy for software that was opened", "refund software", "para"),
            new Probe("shipping time to Canada", "ship canada", "para"),
            new Probe("electronics warranty length", "warranty", "para"),
            new Probe("what is the status of order A-18", "status A-18", "entity"),
            new Probe("status of my order A-19?", "status A-19", "entity"),
            new Probe("can I get a refund of 250 dollars", "refund 250", "entity"),
            new Probe("refund policy for opened games", "refund games", "semantic"),
            new Probe("how long does shipping take to Mexico", "ship mexico", "semantic"),
            new Probe("warranty length for appliances", "warranty appliances", "semantic"));

    /** Returns counts: para-hit, para-miss, entity-wrong, semantic-wrong. */
    static Map<String, Integer> sweep(double threshold, boolean guard) {
        SemanticCache c = new SemanticCache(threshold, guard);
        String scope = SemanticCache.scope("acme", "llama-3-70b", "sys", "tools-v3");
        for (Probe p : SEED) c.put(scope, p.text(), "answer:" + p.key(), p.key(), 0, Long.MAX_VALUE / 2);
        Map<String, Integer> out = new TreeMap<>(Map.of("para-hit", 0, "para-miss", 0, "entity-wrong", 0, "semantic-wrong", 0));
        for (Probe p : PROBES) {
            CacheEntry e = c.lookup(scope, p.text(), 1);
            if (p.kind().equals("para")) out.merge(e != null && e.key().equals(p.key()) ? "para-hit" : "para-miss", 1, Integer::sum);
            else if (e != null) out.merge(p.kind() + "-wrong", 1, Integer::sum);
        }
        return out;
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) {
        System.out.println("1. semantic cache: 6 cached prompts; 12 probes = 6 paraphrases (should hit), 3 entity near-misses and"
                + " 3 semantic near-misses (must NOT hit)");
        System.out.printf("   %-9s %-12s %15s %18s %20s%n", "threshold", "entity-guard", "paraphrase hits", "WRONG: entity", "WRONG: semantic");
        Map<String, Map<String, Integer>> res = new LinkedHashMap<>();
        for (boolean guard : new boolean[] {false, true})
            for (double t : new double[] {0.70, 0.80, 0.90, 0.95}) {
                Map<String, Integer> r = sweep(t, guard);
                res.put(t + "/" + guard, r);
                System.out.printf("   %-9.2f %-12s %13d/6 %16d/3 %18d/3%n", t, guard, r.get("para-hit"), r.get("entity-wrong"), r.get("semantic-wrong"));
            }
        check(res.get("0.8/false").get("entity-wrong") > 0 && res.values().stream().filter(r -> true).count() == 8, "entity near-misses hit without a guard");
        check(res.entrySet().stream().filter(e -> e.getKey().endsWith("true")).allMatch(e -> e.getValue().get("entity-wrong") == 0),
                "the entity guard removes every entity near-miss at any threshold");
        check(res.get("0.95/true").get("para-hit") < res.get("0.7/true").get("para-hit"), "a higher threshold costs paraphrase hits");
        double simNear = cos(embed("what is the status of order A-17"), embed("what is the status of order A-18"));
        double simPara = cos(embed("what is the status of order A-17"), embed("status of my order A-17?"));
        System.out.printf("   cosine('...order A-17', '...order A-18') = %.3f, as high as cosine('...order A-17', 'status of my order A-17?')"
                + " = %.3f: no threshold separates them%n", simNear, simPara);
        check(simNear >= simPara - 1e-9, "a near-miss scores as high as a true paraphrase");

        System.out.println("\n2. noisy neighbour: acme sends 10x its 60K tokens/min quota for 60 s; globex sends 30K tokens/min");
        for (boolean perTenant : new boolean[] {false, true}) {
            Gateway g = new Gateway(new SemanticCache(2.0, true), perTenant ? 60_000 : 1e12, 120_000,
                    OpenTelemetrySdk.builder().build());
            int[] okA = new int[1], rejA = new int[1], okB = new int[1], rejB = new int[1];
            for (int sec = 0; sec < 60; sec++) {
                for (int i = 0; i < 10; i++) {                                    // acme: 10 req/s x ~1,000 tokens
                    g.now = sec * 1000L + i * 100;
                    Response r = g.global.tryReserve(0, g.now) >= 0 ? g.handle(new Request("acme", "llama-3-70b", "s",
                            "q" + sec + "-" + i + " " + "x".repeat(2_400), 400, 0.7)) : null;
                    if (r.status() == 200) okA[0]++; else rejA[0]++;
                }
                g.now = sec * 1000L + 50;
                Response r = g.handle(new Request("globex", "llama-3-70b", "s", "g" + sec + " " + "y".repeat(1_200), 200, 0.7));
                if (r.status() == 200) okB[0]++; else rejB[0]++;
            }
            System.out.printf("   %-26s acme %3d ok / %3d rejected | globex %2d ok / %2d rejected%n",
                    perTenant ? "per-tenant + global buckets" : "global bucket only", okA[0], rejA[0], okB[0], rejB[0]);
            if (perTenant) check(rejB[0] == 0, "per-tenant buckets isolate globex");
            else check(rejB[0] > 0, "global-only limiting lets acme starve globex");
        }

        System.out.println("\n3. a burst of 20 concurrent requests, max_tokens 2,000 each, against a 20K tokens/min tenant budget");
        {
            double budget = 20_000;
            int n = 20, prompt = 500, maxTok = 2_000, actual = 1_400;
            double spentPostHoc = 0, counted = 0;
            int admittedPostHoc = 0;
            for (int i = 0; i < n; i++) if (counted < budget) admittedPostHoc++;  // nothing has completed yet: counter is 0
            spentPostHoc = admittedPostHoc * (prompt + actual);
            TokenBucket tb = new TokenBucket(budget, 1);
            int admittedReserve = 0;
            double spentReserve = 0;
            for (int i = 0; i < n; i++) if (tb.tryReserve(prompt + maxTok, 0) == 0) admittedReserve++;
            spentReserve = admittedReserve * (prompt + actual);
            System.out.printf("   post-hoc counting: admitted %d, spent %,.0f tokens = %.1fx the budget%n", admittedPostHoc, spentPostHoc,
                    spentPostHoc / budget);
            System.out.printf("   reserve-then-refund: admitted %d, spent %,.0f tokens = %.2fx the budget (refunds return %,d unused)%n",
                    admittedReserve, spentReserve, spentReserve / budget, admittedReserve * (maxTok - actual));
            check(spentPostHoc > 1.5 * budget && spentReserve <= budget, "reservation bounds concurrent overshoot");
        }

        System.out.println("\n4. three requests through the gateway with the OpenTelemetry SDK (in-memory exporters):");
        InMemorySpanExporter spans = InMemorySpanExporter.create();
        InMemoryMetricReader metrics = InMemoryMetricReader.create();
        OpenTelemetrySdk otel = OpenTelemetrySdk.builder()
                .setTracerProvider(SdkTracerProvider.builder().addSpanProcessor(SimpleSpanProcessor.create(spans)).build())
                .setMeterProvider(SdkMeterProvider.builder().registerMetricReader(metrics).build()).build();
        Gateway g = new Gateway(new SemanticCache(0.80, true), 3_000, 1_000_000, otel);
        g.handle(new Request("acme", "llama-3-70b", "You are a support agent.", "what is the status of order A-17", 256, 0.0));
        g.handle(new Request("acme", "llama-3-70b", "You are a support agent.", "status of my order A-17?", 256, 0.0));
        g.handle(new Request("acme", "llama-3-70b", "You are a support agent.", "summarize every open ticket " + "z".repeat(9_000), 2_000, 0.0));
        for (SpanData s : spans.getFinishedSpanItems()) {
            Map<String, Object> attrs = new TreeMap<>();
            s.getAttributes().forEach((k, v) -> attrs.put(k.getKey(), v));
            System.out.println("   span '" + s.getName() + "' kind=" + s.getKind() + " status=" + s.getStatus().getStatusCode() + " " + attrs);
        }
        List<String> points = new ArrayList<>();
        for (MetricData m : metrics.collectAllMetrics())
            m.getHistogramData().getPoints().forEach(p -> {
                Map<String, Object> a = new TreeMap<>();
                p.getAttributes().forEach((k, v) -> a.put(k.getKey(), v));
                points.add(String.format("%s [%s] count=%d sum=%s %s", m.getName(), m.getUnit(), p.getCount(),
                        m.getName().endsWith("duration") ? String.format("%.3f", p.getSum()) : String.valueOf((long) p.getSum()), a));
            });
        points.stream().sorted().forEach(p -> System.out.println("   metric " + p));
        List<SpanData> fs = spans.getFinishedSpanItems();
        check(fs.size() == 3 && Boolean.TRUE.equals(fs.get(1).getAttributes().get(AttributeKey.booleanKey("gateway.cache.hit")))
                && fs.get(2).getStatus().getStatusCode() == StatusCode.ERROR, "miss, hit, rate-limited");
        Map<String, Object> first = new LinkedHashMap<>();
        fs.get(0).getAttributes().forEach((k, v) -> first.put(k.getKey(), v));
        check(first.keySet().stream().noneMatch(k -> k.contains("prompt") || k.contains("content")), "no prompt text in default telemetry");
        System.out.println("\nall LlmGateway self-checks passed");
    }
}
```

Output (verified; deterministic, on a virtual clock):

```text
1. semantic cache: 6 cached prompts; 12 probes = 6 paraphrases (should hit), 3 entity near-misses and 3 semantic near-misses (must NOT hit)
   threshold entity-guard paraphrase hits      WRONG: entity      WRONG: semantic
   0.70      false                    5/6                3/3                  3/3
   0.80      false                    5/6                3/3                  1/3
   0.90      false                    4/6                2/3                  0/3
   0.95      false                    3/6                2/3                  0/3
   0.70      true                     5/6                0/3                  3/3
   0.80      true                     5/6                0/3                  1/3
   0.90      true                     4/6                0/3                  0/3
   0.95      true                     3/6                0/3                  0/3
   cosine('...order A-17', '...order A-18') = 1.000, as high as cosine('...order A-17', 'status of my order A-17?') = 1.000: no threshold separates them

2. noisy neighbour: acme sends 10x its 60K tokens/min quota for 60 s; globex sends 30K tokens/min
   global bucket only         acme 351 ok / 249 rejected | globex 23 ok / 37 rejected
   per-tenant + global buckets acme 181 ok / 419 rejected | globex 60 ok /  0 rejected

3. a burst of 20 concurrent requests, max_tokens 2,000 each, against a 20K tokens/min tenant budget
   post-hoc counting: admitted 20, spent 38,000 tokens = 1.9x the budget
   reserve-then-refund: admitted 8, spent 15,200 tokens = 0.76x the budget (refunds return 4,800 unused)

4. three requests through the gateway with the OpenTelemetry SDK (in-memory exporters):
   span 'chat llama-3-70b' kind=CLIENT status=UNSET {gateway.cache.hit=false, gateway.ratelimit.decision=allow, gateway.tenant=acme, gen_ai.operation.name=chat, gen_ai.provider.name=vllm, gen_ai.request.max_tokens=256, gen_ai.request.model=llama-3-70b, gen_ai.request.temperature=0.0, gen_ai.response.finish_reasons=[stop], gen_ai.response.model=llama-3-70b, gen_ai.usage.input_tokens=26, gen_ai.usage.output_tokens=72}
   span 'chat llama-3-70b' kind=CLIENT status=UNSET {gateway.cache.hit=true, gateway.tenant=acme, gen_ai.operation.name=chat, gen_ai.provider.name=vllm, gen_ai.request.max_tokens=256, gen_ai.request.model=llama-3-70b, gen_ai.request.temperature=0.0, gen_ai.response.finish_reasons=[stop], gen_ai.response.model=llama-3-70b, gen_ai.usage.input_tokens=0, gen_ai.usage.output_tokens=0}
   span 'chat llama-3-70b' kind=CLIENT status=ERROR {error.type=rate_limited, gateway.cache.hit=false, gateway.ratelimit.decision=reject, gateway.tenant=acme, gen_ai.operation.name=chat, gen_ai.provider.name=vllm, gen_ai.request.max_tokens=2000, gen_ai.request.model=llama-3-70b, gen_ai.request.temperature=0.0}
   metric gen_ai.client.operation.duration [s] count=1 sum=0.000 {error.type=rate_limited, gateway.cache.hit=false, gen_ai.operation.name=chat, gen_ai.provider.name=vllm, gen_ai.request.model=llama-3-70b}
   metric gen_ai.client.operation.duration [s] count=1 sum=0.015 {gateway.cache.hit=true, gen_ai.operation.name=chat, gen_ai.provider.name=vllm, gen_ai.request.model=llama-3-70b}
   metric gen_ai.client.operation.duration [s] count=1 sum=1.740 {gateway.cache.hit=false, gen_ai.operation.name=chat, gen_ai.provider.name=vllm, gen_ai.request.model=llama-3-70b}
   metric gen_ai.client.token.usage [{token}] count=1 sum=26 {gen_ai.operation.name=chat, gen_ai.provider.name=vllm, gen_ai.request.model=llama-3-70b, gen_ai.token.type=input}
   metric gen_ai.client.token.usage [{token}] count=1 sum=72 {gen_ai.operation.name=chat, gen_ai.provider.name=vllm, gen_ai.request.model=llama-3-70b, gen_ai.token.type=output}

all LlmGateway self-checks passed
```

### 2.2 Python: GCRA, fair admission and cache economics

```python
"""gateway_economics_lab.py - three gateway decisions as arithmetic and discrete-event simulation (stdlib only).

1. GCRA: a token limiter with ONE timestamp of state per tenant (the theoretical arrival time, TAT). It admits exactly
   what a token bucket admits, needs 8 bytes per key, and is a single atomic read-modify-write (a Redis script).
2. Fair admission under overload: when demand exceeds the model deployment's goodput, a FIFO queue lets a flooding
   free-tier tenant set everyone's wait; deficit round robin (DRR) with weights isolates the premium tenant.
3. Semantic-cache economics: savings per month against the cost of wrong answers; the break-even false-hit rate.
Prices and hit rates are ASSUMPTIONS stated inline; substitute your own.
"""
from __future__ import annotations

from collections import deque


# ---------------------------------------------------------------------- 1. GCRA == token bucket
class TokenBucket:
    """Integer arithmetic: time in ms, `rate` tokens per ms."""

    def __init__(self, rate: int, burst: int):
        self.rate, self.cap, self.tokens, self.t = rate, burst, burst, 0

    def allow(self, now: int, cost: int) -> bool:
        self.tokens = min(self.cap, self.tokens + (now - self.t) * self.rate)
        self.t = now
        if self.tokens >= cost:
            self.tokens -= cost
            return True
        return False


class Gcra:
    """State = TAT only. Emission interval T = 1/rate ms per token; tolerance tau = burst * T."""

    def __init__(self, rate: int, burst: int):
        self.rate, self.burst, self.tat = rate, burst, 0              # keep T = 1/rate exact by scaling by rate

    def allow(self, now: int, cost: int) -> bool:
        tat = max(self.tat, now * self.rate)                          # TAT in units of (ms x rate) = tokens
        new_tat = tat + cost
        if new_tat - now * self.rate > self.burst:
            return False
        self.tat = new_tat
        return True


def gcra_equivalence() -> None:
    print("== 1. GCRA vs token bucket on the same request trace (rate 1,000 tokens/s, burst 5,000) ==")
    tb, g = TokenBucket(1, 5000), Gcra(1, 5000)                       # 1 token per ms = 1,000 tokens/s
    trace = [(t * 50, 300 + (t * 37) % 900) for t in range(400)]     # every 50 ms, 300..1,199 tokens each
    a = [tb.allow(now, c) for now, c in trace]
    b = [g.allow(now, c) for now, c in trace]
    print(f"  {len(trace)} requests: token bucket admits {sum(a)}, GCRA admits {sum(b)}, decisions identical: {a == b}")
    print("  state per tenant: bucket = (tokens, last_refill) 16 bytes; GCRA = TAT 8 bytes, one atomic compare-and-set")
    assert a == b


# ---------------------------------------------------------------------- 2. FIFO vs weighted DRR under overload
def admission(policy: str) -> dict:
    """Capacity 40 requests/s; premium sends 10/s; free tier floods 60/s for 30 s. Returns p95 wait per tenant (s)."""
    cap_per_tick, ticks = 4, 300                                       # 0.1 s ticks, 30 s
    arrivals = {"premium": 1, "free": 6}                               # per tick
    queues = {k: deque() for k in arrivals}
    fifo: deque = deque()
    waits = {k: [] for k in arrivals}
    weights, deficit = {"premium": 3, "free": 1}, {"premium": 0, "free": 0}
    for t in range(ticks):
        for k, n in arrivals.items():
            for _ in range(n):
                (fifo if policy == "fifo" else queues[k]).append((k, t))
        served = 0
        if policy == "fifo":
            while fifo and served < cap_per_tick:
                k, t0 = fifo.popleft()
                waits[k].append((t - t0) / 10)
                served += 1
        else:
            while served < cap_per_tick and any(queues.values()):
                for k in ("premium", "free"):
                    deficit[k] += weights[k]
                    while deficit[k] >= 1 and queues[k] and served < cap_per_tick:
                        _, t0 = queues[k].popleft()
                        waits[k].append((t - t0) / 10)
                        deficit[k] -= 1
                        served += 1
                    if not queues[k]:
                        deficit[k] = 0
    out = {}
    for k, w in waits.items():
        w = sorted(w)
        out[k] = (w[int(0.95 * (len(w) - 1))] if w else float("nan"), len(w))
    return out


def fair_admission() -> None:
    print("\n== 2. Overload: capacity 40 req/s; premium 10 req/s; free tier floods 60 req/s for 30 s ==")
    res = {p: admission(p) for p in ("fifo", "drr")}
    for p, r in res.items():
        print(f"  {p.upper():5}: premium p95 wait {r['premium'][0]:5.1f} s ({r['premium'][1]} served), "
              f"free p95 wait {r['free'][0]:5.1f} s ({r['free'][1]} served)")
    assert res["drr"]["premium"][0] <= 0.2 < res["fifo"]["premium"][0]
    print("  FIFO: the flood sets everyone's queueing delay; weighted DRR: premium waits ~0 and the free tier absorbs the")
    print("  overload. In production, reject (429 + Retry-After) beyond a queue deadline instead of queueing forever.")


# ---------------------------------------------------------------------- 3. semantic cache economics
def cache_economics() -> None:
    print("\n== 3. Semantic cache: monthly savings vs the cost of wrong answers ==")
    requests = 30_000_000                                              # per month (assumption)
    cost_per_call = 0.0042                                             # $: 1.5K in + 400 out tokens at assumed prices
    lookup_cost = 0.00002                                              # $: embedding + vector lookup per request
    wrong_answer_cost = 2.00                                           # $: a support escalation or a refund mistake
    print(f"  assumptions: {requests:,} requests/month, ${cost_per_call:.4f} per model call, ${lookup_cost:.5f} per lookup, "
          f"${wrong_answer_cost:.2f} per wrong cached answer")
    print(f"  {'hit rate':>8} {'false-hit rate':>15} {'model $ saved':>14} {'lookup $':>10} {'wrong-answer $':>15} {'net $/month':>12}")
    for hit, false_hit in ((0.25, 0.0), (0.25, 0.005), (0.25, 0.02), (0.05, 0.005)):
        saved = requests * hit * cost_per_call
        lookups = requests * lookup_cost
        wrong = requests * false_hit * wrong_answer_cost
        print(f"  {hit:>8.0%} {false_hit:>15.1%} {saved:>14,.0f} {lookups:>10,.0f} {wrong:>15,.0f} {saved - lookups - wrong:>12,.0f}")
    breakeven = (0.25 * cost_per_call - lookup_cost) / wrong_answer_cost
    print(f"  break-even false-hit rate at a 25% hit rate: {breakeven:.3%} of requests - one wrong answer per "
          f"{1 / breakeven:,.0f} requests erases the savings")
    assert 0.0004 < breakeven < 0.0006
    print("  -> the threshold is a business decision priced by the wrong-answer cost; entity guards and scoping buy")
    print("     false-hit rate cheaply; low-hit-rate traffic (open-ended chat) rarely pays for a semantic cache at all")


def main() -> None:
    gcra_equivalence()
    fair_admission()
    cache_economics()
    print("\nall gateway_economics_lab self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== 1. GCRA vs token bucket on the same request trace (rate 1,000 tokens/s, burst 5,000) ==
  400 requests: token bucket admits 49, GCRA admits 49, decisions identical: True
  state per tenant: bucket = (tokens, last_refill) 16 bytes; GCRA = TAT 8 bytes, one atomic compare-and-set

== 2. Overload: capacity 40 req/s; premium 10 req/s; free tier floods 60 req/s for 30 s ==
  FIFO : premium p95 wait  12.1 s (172 served), free p95 wait  12.2 s (1028 served)
  DRR  : premium p95 wait   0.0 s (300 served), free p95 wait  14.2 s (900 served)
  FIFO: the flood sets everyone's queueing delay; weighted DRR: premium waits ~0 and the free tier absorbs the
  overload. In production, reject (429 + Retry-After) beyond a queue deadline instead of queueing forever.

== 3. Semantic cache: monthly savings vs the cost of wrong answers ==
  assumptions: 30,000,000 requests/month, $0.0042 per model call, $0.00002 per lookup, $2.00 per wrong cached answer
  hit rate  false-hit rate  model $ saved   lookup $  wrong-answer $  net $/month
       25%            0.0%         31,500        600               0       30,900
       25%            0.5%         31,500        600         300,000     -269,100
       25%            2.0%         31,500        600       1,200,000   -1,169,100
        5%            0.5%          6,300        600         300,000     -294,300
  break-even false-hit rate at a 25% hit rate: 0.051% of requests - one wrong answer per 1,942 requests erases the savings
  -> the threshold is a business decision priced by the wrong-answer cost; entity guards and scoping buy
     false-hit rate cheaply; low-hit-rate traffic (open-ended chat) rarely pays for a semantic cache at all

all gateway_economics_lab self-checks passed
```

---

## 3. Production failure modes and P99 debugging

### F1 · Customers receive another customer's answer, or an answer about the wrong order

- **Root cause:** a cache key without tenant/model/system-prompt scope, or similarity matching across identifiers.
- **Fix:** scoped keys, an entity guard, no caching of personalized or tool-calling responses, and an audit sample of
  cache hits labelled by humans.

### F2 · The cache "works" but support tickets rise

- **Signature:** a high hit rate together with rising escalations or corrections.
- **Root cause:** false hits from a threshold tuned for hit rate, not cost.
- **Fix:** price the threshold with §1.4, measure the false-hit rate on labelled traffic, and lower the threshold
  only with a verifier.

### F3 · One tenant's batch job degrades everyone

- **Root cause:** global-only limits, request-count limits, or a FIFO queue.
- **Fix:** per-tenant token buckets plus a per-deployment bucket, weighted fair admission, and per-tenant dashboards.

### F4 · Spend exceeds budgets during bursts

- **Root cause:** post-hoc token accounting with concurrent requests in flight.
- **Fix:** reserve `prompt + max_tokens` at admission, refund on completion, and enforce tight per-use-case
  `max_tokens`.

### F5 · The distributed limiter is the bottleneck, or inconsistent

- **Root cause:** read-modify-write of bucket state without atomicity across gateway replicas.
- **Fix:** GCRA in one atomic script per key, local pre-admission with periodic sync for very high QPS, and
  tolerance for small overshoot documented in the SLO.

### F6 · Latency dashboards improved but users complain

- **Root cause:** cache hits mixed into model-latency histograms.
- **Fix:** label `gateway.cache.hit`; track model-call TTFT/TPOT separately (File 02).

### F7 · Telemetry leaks prompts

- **Root cause:** prompts and completions logged as span attributes or logs by default.
- **Fix:** content capture off by default, opt-in per environment with redaction and retention limits.

### F8 · Dashboards break after an instrumentation upgrade

- **Root cause:** GenAI conventions are still evolving (for example `gen_ai.system` → `gen_ai.provider.name`), and
  they now live in a separate repository from the core semantic conventions, with their own release cadence.
- **Fix:** pin the semconv version, transform at the collector during migrations, and alert on missing attributes.

---

## 4. FAANG L7 bar-raiser Q&A chains

### Q1 · "Add a semantic cache to cut our LLM bill by 30%."

- **L5 answer:** "Embed prompts, cache answers above 0.9 similarity."
- **Why L5 fails at scale:** similarity is blind to identifiers (A-17 vs A-18 at 1.000), keys without scope leak
  across tenants, and a 0.5% false-hit rate turns $30.9K of savings into a $269K loss at $2 per wrong answer.
- **L7 principal defense:**
  1. Measure the hit-rate ceiling first: what share of traffic truly repeats? FAQ-style support might reach tens of
     percent; open-ended chat rarely does.
  2. Scope keys (tenant, model, system prompt, tool and context versions) and add an entity guard.
  3. Cache only replay-safe responses (`temperature` 0, `stop`, no side effects) with a TTL.
  4. Tune θ against the priced false-hit rate on labelled traffic; add a verifier for borderline similarity.
  5. Prefer the cheaper wins first: exact-match caching and prefix caching of shared system prompts and tools.

### Q2 · "Design rate limiting for a multi-tenant LLM platform."

- **L5 answer:** "100 requests per minute per API key."
- **L7 principal defense:**
  1. Limit tokens per minute per tenant and per deployment, reserve-then-refund, with computed Retry-After.
  2. Use GCRA state in a fast store; local pre-admission for very high QPS.
  3. Add weighted fair admission with queue deadlines when the deployment is saturated.
  4. Expose quotas and usage to tenants; alert on sustained throttling as a capacity signal.

### Q3 · "What should we instrument on every LLM call?"

- **L7 principal defense:** OTel GenAI spans with:
  - provider, request and response model;
  - `max_tokens` and temperature;
  - input and output tokens and finish reasons;
  - `error.type`;
  - gateway attributes (tenant, cache hit, limiter decision).

  Token-usage and duration histograms, plus server-side TTFT/TPOT. No prompt content by default. Pin the semconv
  version.

### Q4 · "One customer's nightly job makes daytime users slow."

- **L7 principal defense:**
  1. Per-tenant token buckets and a deployment bucket.
  2. Weighted fair admission, with the batch tenant at low weight or on a separate batch tier with its own capacity
     and pricing.
  3. Reject past the queue deadline.
  4. Show the customer their throttling and offer a batch API.

### Q5 · "Self-hosted or provider API behind the gateway?"

- **L7 principal defense:** the gateway makes the choice reversible. It provides one API, one quota model and one
  telemetry schema, with routing by model and tenant. Folder 08 File 01 does the TCO arithmetic; the gateway is what
  lets you act on it.

---

## 5. Invariants checklist

- [ ] Cache keys are scoped by tenant, model, system prompt and tool/context versions; an entity guard requires
      exact identifier equality.
- [ ] Only replay-safe responses are cached, with a TTL; the threshold is tuned against the priced false-hit rate.
- [ ] Rate limits are in tokens, per tenant and per deployment, reserve-then-refund, with computed Retry-After.
- [ ] Limiter state updates are atomic across replicas (GCRA or an equivalent).
- [ ] Saturation uses weighted fair admission with queue deadlines, then rejection.
- [ ] Every call emits a GenAI-convention span and token/duration histograms; cache hits are labelled.
- [ ] Prompt and completion content is off by default in telemetry.
- [ ] The semconv version is pinned and migrations are handled at the collector.

## 6. References

1. OpenTelemetry GenAI semantic conventions: spans and metrics (`gen_ai.*`; Development status). As of semantic
   conventions 1.44.0 they are maintained in their own repository, `open-telemetry/semantic-conventions-genai` (link
   verified in File 08/03); pin the version you implement. OpenTelemetry Java SDK 1.62.0.
2. ITU-T Recommendation I.371 (traffic control and congestion control in B-ISDN): the Generic Cell Rate Algorithm.
3. M. Shreedhar, G. Varghese. *Efficient Fair Queuing Using Deficit Round Robin.* SIGCOMM 1995.
4. F. Bang. *GPTCache: An Open-Source Semantic Cache for LLM Applications.* NLP-OSS workshop, 2023 (⚠ verify the
   venue).
5. Google SRE Book, chapter 21 *Handling Overload* (per-customer quotas, criticality, client-side throttling).
