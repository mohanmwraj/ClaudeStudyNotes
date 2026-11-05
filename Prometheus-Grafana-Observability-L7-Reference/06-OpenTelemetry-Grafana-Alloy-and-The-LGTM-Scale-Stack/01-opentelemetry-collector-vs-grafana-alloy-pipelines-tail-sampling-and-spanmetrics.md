# 01 · OpenTelemetry Collector vs Grafana Alloy: Pipelines, Tail Sampling and Span Metrics

> **Folder 06 — OpenTelemetry, Grafana Alloy and the LGTM Scale Stack · File 1 of 3.**
> Pinned to **OpenTelemetry Collector core + contrib v0.164.0**, **Grafana Alloy v1.21.3**, **Tempo v3.1.1**, **Mimir 3.2.4**.
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L1 `tail_sampling_lab.py` | Ports the `load_balancing` exporter's consistent-hash ring (CRC-32, 131,071 positions, 200 points per endpoint) and passes the upstream `TestEndpointFor` vectors 4/4 and the distribution bounds. Shows random load balancing fragments 99% of traces. Models the tail sampler's FIFO trace buffer and finds a **cliff**: 100% of traces are dropped unevaluated once `num_traces / rate < decision_wait`. A 4→5 pod scale-out remaps 19.8% of traces. Ports the FNV-1a `probabilistic` policy (rates within ±0.2 points). Shows that a 10% head sampler followed by a 10% tail sampler keeps 1.02%, not 10%. Span metrics computed after sampling inflate the error ratio 10× | ~2 s |

**Verification.**
- Component type names, defaults and deprecated aliases come from each component's `metadata.yaml`, `config.go` and README at `v0.164.0` [D].
- The ring and the FNV policy are line-by-line ports. They are checked against upstream test vectors [M].
- Buffer, routing and bias experiments are simulations [M] with stated parameters.
- Alloy syntax and defaults come from the v1.21.3 component reference [D].
- No collector binary was run: running downloaded binaries is blocked in this environment.

---

## 0. Orientation

**What this file answers.**
- How telemetry pipelines are wired in the upstream OpenTelemetry Collector and in Grafana Alloy.
- Why tail sampling forces a two-tier, stateful topology.
- How to size that topology from first principles.
- Where to generate span metrics so they are not biased.
- Which knobs silently drop data.

**The two-tier topology that every tail-sampling design converges on.**

```text
 apps (OTel SDK / Java agent)                          tier 1: stateless "router" gateway (Deployment, HPA)
 ─────────────────────────────  OTLP gRPC :4317  ───►  receivers.otlp
   checkout ×40 pods                                   processors: memory_limiter → k8s_attributes → resource
   payments ×20 pods                                   connectors: span_metrics  (ALL spans, before sampling) ──► metrics ─► Mimir (OTLP)
   frontend ×60 pods                                   exporters:  load_balancing{routing_key: traceID, resolver: k8s}
                                                                   │  one OTLP sub-exporter per sampler pod
                                                                   │  ring: crc32(traceID) % 131071 → next of 200×N points
                                        ┌──────────────────────────┼──────────────────────────┐
                                        ▼                          ▼                          ▼
 tier 2: stateful samplers   sampler-0 (StatefulSet)      sampler-1                   sampler-2      ← headless Service
                             tail_sampling{decision_wait, num_traces, decision_cache, policies}
                             every span of trace T lands here, so the policy sees the whole trace
                                        └──────────────────────────┼──────────────────────────┘
                                                                   ▼
                                                        Tempo distributor (OTLP) → Kafka → block-builders / live-stores
```

**Collector or Alloy?**

| | OpenTelemetry Collector (contrib / k8s distro) | Grafana Alloy |
|---|---|---|
| Config model | Static YAML: `receivers`/`processors`/`exporters`/`connectors`/`extensions` + `service.pipelines` | Alloy syntax (HCL-like): components wired by references (`output { traces = [x.input] }`); a live component graph |
| OTel components | All contrib components, current names (`span_metrics`, `load_balancing`, `k8s_attributes` since the snake_case renames ⚠) | Wraps a subset as `otelcol.*` components; keeps the **old names** (`otelcol.connector.spanmetrics`, `otelcol.exporter.loadbalancing`, `otelcol.processor.k8sattributes`) [D] |
| Prometheus-native | `prometheus` receiver (scrape) + `prometheus_remote_write` exporter | First-class `prometheus.scrape`, `prometheus.relabel`, `prometheus.remote_write` (Prometheus code), plus `discovery.*` |
| Logs | `filelog` receiver + OTLP | `loki.source.*`, `loki.process` (Promtail successor) and `otelcol.receiver.filelog` |
| Profiles | Profiles signal still alpha in OTLP exporters [D] | `pyroscope.ebpf` (embeds the OTel eBPF profiler fork), `pyroscope.java`, `pyroscope.write` |
| Clustering | None built in: you build tiers with the `load_balancing` exporter | `--cluster.enabled`: consistent-hash sharding of scrape targets across Alloy peers |
| Debug UI | zPages, `debug` exporter | Built-in UI with a live graph and component health; `livedebugging` |
| Best fit | Vendor-neutral fleets and OTel-native shops | Grafana-stack fleets that want metrics, logs, traces and profiles in one agent |

The data model underneath is the same (OTLP `pdata`). Both use the same tail-sampling and span-metrics code: Alloy vendors the contrib components. **The physics in this file applies to both.**

---

## 1. First principles: pipelines, state, and why tail sampling is a distributed-systems problem

### 1.1 What a pipeline is [D]

- A collector pipeline is a typed DAG per signal (traces, metrics, logs, profiles).
- **Receivers** decode wire formats into `pdata`. **Processors** transform in order. **Exporters** encode and send.
- **Connectors** are an exporter of one pipeline and a receiver of another. That is how `span_metrics` turns traces into metrics inside one process.
- Every processor runs synchronously on the caller's goroutine. A slow processor (tail-sampling decision latency, a blocking exporter) back-pressures the receiver and, ultimately, the SDK's export queue.
- Since the batch processor fell out of favour, batching and queueing live in the **exporter** (`exporterhelper`) [D]:

```text
 receiver ─► memory_limiter ─► processors ─► exporter
                                              ├─ sending_queue {enabled: true, num_consumers: 10, queue_size: 1000, sizer: requests,
                                              │                 block_on_overflow: false, storage: <none|file_storage>}
                                              │    └─ batch {flush_timeout: 200ms, min_size: 8192, max_size: 0, sizer: items}
                                              ├─ retry_on_failure {initial_interval 5s, max_interval 30s, max_elapsed_time 300s, multiplier 1.5}
                                              └─ timeout 5s per attempt
 queue full + block_on_overflow=false  →  data rejected immediately (counted in otelcol_exporter_enqueue_failed_*)
 retry window exhausted                →  data dropped (otelcol_exporter_send_failed_*)
```

- **The memory_limiter is admission control.** It refuses data when the heap passes `limit − spike_limit` and forces GC above `limit`.
- Refusing makes the receiver return a retryable error to the client, so the SDK queues and retries.
- The limiter must come **first** in every pipeline. A processor placed before it allocates memory the limiter never gets to refuse.

### 1.2 Head vs tail sampling

| | Head sampling (SDK `ParentBased(TraceIdRatioBased)`) | Tail sampling (collector) |
|---|---|---|
| Decides | At the root span, before anything happened | After `decision_wait`, with the whole trace in memory |
| Keeps errors/slow traces | Only by luck (rate p) | By policy (`status_code`, `latency`, `ottl_condition`) |
| Cost | Zero: unsampled spans are never exported | You pay to export, ship and buffer **100%** of spans to tier 2 |
| State | None | Per-trace buffers: memory ∝ rate × decision_wait |
| Consistency across services | Propagated via the W3C `sampled` flag | Requires all spans of a trace on one sampler: **trace-ID routing** |

**Tail sampling is a stateful, partitioned stream join keyed by trace ID.** Everything else follows from that sentence:
- routing must be consistent (L1 §1–2);
- the per-partition buffer must hold rate × wait (L1 §3);
- repartitioning (scaling) breaks in-flight joins (L1 §4);
- late data needs a decision cache (L1 §3).

### 1.3 The load-balancing ring, exactly [D][M]

`exporter/loadbalancingexporter/consistent_hashing.go` at v0.164.0 builds an immutable ring:

```text
 for each endpoint e, for i in 0..199:   h = crc32_ieee(e || le32(i));  pos = h % 131071
 sort candidates by (pos, h, endpoint); on a taken position probe pos+1 … up to 10 times, else skip
 lookup(traceID):  pos = crc32_ieee(traceID[16 bytes]) % 131071  →  first ring item with position >= pos (wrap to item 0)
```

What L1 measured with this port:

- **Correctness.** The upstream vectors pass 4/4: `{1,2,0,0}→endpoint-2`, `{128,128,0,0}→endpoint-1`, `"ad-service-7"→endpoint-2`, `"get-recommendations-1"→endpoint-2`. The ring holds 400 items for two endpoints.
- **Balance.** With 10 endpoints, CV is 0.099 and max/min is 1.32, inside the upstream test bounds (≤ 0.10, ≤ 1.35). With 4 pods the shares are 23/27/27/23%. **Provision the sampler tier for the hottest pod, not the average.**
- **Scaling.** 4→5 pods remaps 19.8% of trace IDs (ideal 20%). Naive `hash mod N` would remap 79.4%.
- **Endpoint list order does not matter.** Upstream tests assert invariance to resolver order, so two router pods that see the same endpoint set agree on ownership.
- **Two routers can disagree.** If they see *different* endpoint sets (one has observed the new pod, the other has not), they route the same trace to different samplers. **That transition window is the real cost of scaling.**

### 1.4 The tail sampler's buffer is a cliff, not a slope [D][M]

From the tail-sampling README:

- traces are held in a circular buffer of `num_traces` (default 50,000);
- decisions are made `decision_wait` (default **30s**) after a trace's first span;
- when a new trace arrives at a full buffer, **the oldest is evicted**, and if it had not been decided yet it is counted in `otelcol_processor_tail_sampling_sampling_trace_dropped_too_early`.

Under FIFO eviction every trace lives exactly `num_traces / rate` seconds:

```text
 lifetime = num_traces / new_traces_per_sec
 lifetime ≥ decision_wait  →  every trace is decided            (0% dropped)
 lifetime < decision_wait  →  every trace is evicted undecided  (100% dropped)
 defaults: 50,000 / 30 s  →  the cliff is at 1,667 new traces/s PER SAMPLER POD
```

L1 §3 at 2,000 traces/s:

| `num_traces` | `decision_wait` | dropped too early |
|---|---|---|
| 50,000 | 30s | 100% |
| 59,000 | 30s | 100% |
| 61,000 | 30s | 0% |
| 50,000 | 10s | 0% |

**Production consequences.**
- Size `num_traces ≥ 1.5 × peak per-pod rate × decision_wait`, using the hottest pod's rate.
- Set `expected_new_traces_per_sec` to pre-size maps.
- `block_on_overflow: true` (present in v0.164.0 `config.go` [D]) turns the cliff into back-pressure onto tier 1, which then queues and retries. That is usually the better failure mode, *if* tier 1's queues are sized for it.
- **Alert on `dropped_too_early > 0`. It is never benign.**
- Choose `decision_wait` from your trace-completion distribution, not a guess. L1 §3: 5.08% of traces still had spans arriving after 2s, 4.09% after 5s (async consumers, batch jobs) and none after 10s. Measure yours with `otelcol_processor_tail_sampling_sampling_late_span_age` and `..._sampling_trace_removal_age`.

**Late spans** [D]:
- While the decision is still in the buffer, late spans inherit it.
- After eviction, with no decision cache, the late spans look like a brand-new trace and get a *second, independent* decision. That produces half-traces in Tempo.
- With `decision_cache.sampled_cache_size` set **much greater than** `num_traces`, "keep" decisions are remembered by trace ID after the span data is released.

### 1.5 Composing samplers: why 10% × 10% = 1% [D][M]

- The `probabilistic` tail policy hashes `hash_salt + traceID` with FNV-1a 64 and keeps the trace when `hash ≤ ratio × MaxUint64`. L1 §5 reproduces 25.02%, 32.98% and 33.14% (salted) against ±0.2 tolerances.
- An SDK ratio sampler decides on the trace ID's randomness bits, which is a **different function**. The two decisions are independent, so a 10% head sampler feeding a 10% tail policy keeps **1.02%**.
- With the `processor.tailsamplingprocessor.usetracestate` gate, the policy reads the W3C `tracestate` `ot` fields (`th`, `rv`) and writes back the effective threshold, so downstream adjusted counts stay correct.
- `sample_on_first_match` must not be combined with that gate: it stops before a later, less strict policy can report its threshold [D].

### 1.6 Span metrics: placement decides truth [D][M]

The `span_metrics` connector emits `traces.span.metrics.calls` (a sum) and `traces.span.metrics.duration` (explicit or exponential histogram). The default dimensions are:
- `service.name`;
- `span.name`;
- `span.kind`;
- `status.code`;
- plus a `collector.instance.id` resource attribute unless excluded.

In Prometheus these become `traces_span_metrics_calls_total` and `traces_span_metrics_duration_seconds_bucket`/`_milliseconds_` depending on the unit: the default unit is `ms`, and a feature gate moves it to `s` ⚠.

- **Cardinality.** L1 §6: 40 services × 25 span names × 3 status codes × 2 kinds = 6,000 call series. A 16-bucket histogram makes that **108,000 series**. One unbounded dimension (`http.url`, `user.id`) multiplies it by the number of distinct values.
  - `aggregation_cardinality_limit` caps tracked combinations. Overflow is folded into `otel.metric.overflow="true"`.
  - **Set it.** Without it the connector's memory is unbounded.
- **Bias.** L1 §6: the error ratio from all spans is 1.00%, while computing it from tail-sampled traces gives **10.2%**. Sampling policies keep errors by design, so RED computed after sampling is a lie. Generate span metrics in **tier 1, before sampling**, or in Tempo's metrics-generator from the unsampled stream.
- **Instance duplication.** Several tier-1 pods each emit the same series for a service (`calls{service="checkout"}` from router-0 and router-1). Either:
  - keep `collector.instance.id` and `sum without (collector_instance_id)` in queries/recording rules (the **single-writer** principle: each series has exactly one writer); or
  - route by `service` (`routing_key: service`) to a dedicated span-metrics tier, so each service is aggregated by exactly one pod.
- **Temporality.** The default is cumulative. Delta temporality to Prometheus needs `deltatocumulative`, or a backend that accepts delta (Mimir's OTLP endpoint has delta-handling options ⚠).

<!-- listing:tail_sampling_lab.py -->
```python
"""tail_sampling_lab.py - the physics of a two-tier tail-sampling pipeline (OpenTelemetry Collector
v0.164.0 / Grafana Alloy otelcol.* components), using ports of the upstream code where it matters:

  * the load_balancing exporter's consistent-hash ring (exporter/loadbalancingexporter/consistent_hashing.go:
    CRC-32/IEEE, 131,071 positions, 200 points per endpoint, linear probing on collisions), checked against
    the upstream TestEndpointFor vectors;
  * the tail_sampling processor's circular trace buffer (num_traces, FIFO eviction -> dropped_too_early)
    and its 'probabilistic' policy (FNV-1a 64 over hash_salt + trace ID <= ratio * MaxUint64).

Then it measures what routing, decision_wait, num_traces, scaling and span-metric placement do to the
result. Deterministic, stdlib only.

Usage: python tail_sampling_lab.py [target.md]
"""
import bisect
import collections
import random
import sys
import zlib

MAX_POSITIONS = 131071   # consistent_hashing.go: maxPositions
DEFAULT_WEIGHT = 200     # defaultWeight
PROBE_LIMIT = 10         # linearProbeLimit


class LBRing:
    """Port of newHashRing / endpointFor from the load_balancing exporter (v0.164.0)."""

    def __init__(self, endpoints, weight=DEFAULT_WEIGHT):
        cands = []
        for ep in endpoints:
            for i in range(weight):
                h = zlib.crc32(ep.encode() + i.to_bytes(4, "little"))
                cands.append((h % MAX_POSITIONS, h, ep))
        cands.sort()
        used, items = set(), []
        for pos, _h, ep in cands:
            probes = 0
            while pos in used and probes < PROBE_LIMIT:
                pos = (pos + 1) % MAX_POSITIONS
                probes += 1
            if probes >= PROBE_LIMIT:
                continue
            used.add(pos)
            items.append((pos, ep))
        items.sort()
        self.pos = [p for p, _ in items]
        self.ep = [e for _, e in items]

    def endpoint_for(self, ident: bytes):
        pos = zlib.crc32(ident) % MAX_POSITIONS
        i = bisect.bisect_left(self.pos, pos)      # closest position >= pos, wrapping to the first
        return self.ep[i % len(self.ep)]


def fnv1a64(data: bytes):
    h = 0xcbf29ce484222325
    for b in data:
        h ^= b
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


def prob_threshold(ratio):
    ratio = min(max(ratio, 0.0), 1.0)
    return int((2**64 - 1) * ratio)


def prob_sampled(trace_id: bytes, pct, salt="default-hash-seed"):
    """tail_sampling 'probabilistic' policy without the usetracestate gate (hashTraceID <= threshold)."""
    return fnv1a64(salt.encode() + trace_id) <= prob_threshold(pct / 100)


def gen_traces(n, seed=1):
    rng = random.Random(seed)
    out = []
    for _ in range(n):
        spans = rng.randint(3, 12)
        tail = 8.0 if rng.random() < 0.05 else 2.0          # 5% of traces have async/batch spans
        offs = sorted(rng.uniform(0, tail) for _ in range(spans))
        out.append({"id": rng.getrandbits(128).to_bytes(16, "big"), "spans": spans,
                    "error": rng.random() < 0.01, "dur": rng.lognormvariate(-2.0, 0.9),
                    "lateness": offs[-1] - offs[0], "baseline": rng.random() < 0.02})
    return out


def keep(tr, saw=None):
    """errors OR latency > 500 ms OR 2% baseline; with a partial view (saw < spans) the sampler only
    sees the error if the erroring span landed on it, and only sees full latency with all spans."""
    if saw is None:
        saw = tr["spans"]
    err_seen = tr["error"] and saw >= max(1, tr["spans"] // 2)
    slow_seen = tr["dur"] > 0.5 and saw == tr["spans"]
    return err_seen or slow_seen or tr["baseline"]


def buffer_sim(rate, seconds, num_traces, decision_wait):
    """tail_sampling circular buffer: traces stay buffered after their decision (so late spans inherit
    it) until a new trace evicts the oldest once num_traces are held; a trace evicted before
    decision_wait elapsed is 'dropped too early' (never evaluated)."""
    held = collections.deque()
    dropped = decided = 0
    for k in range(int(rate * seconds)):
        now = k / rate
        if len(held) >= num_traces:
            born = held.popleft()
            if now - born < decision_wait:
                dropped += 1
            else:
                decided += 1
        held.append(now)
    return dropped, decided


def main():
    checks = []
    print("== 1. The load_balancing exporter ring (port of consistent_hashing.go @ v0.164.0) ==")
    ring2 = LBRing(["endpoint-1", "endpoint-2"])
    vectors = [(bytes([1, 2, 0, 0]), "endpoint-2"), (bytes([128, 128, 0, 0]), "endpoint-1"),
               (b"ad-service-7", "endpoint-2"), (b"get-recommendations-1", "endpoint-2")]
    ok = sum(ring2.endpoint_for(k) == want for k, want in vectors)
    print(f"upstream TestEndpointFor vectors: {ok}/{len(vectors)} match; ring items = {len(ring2.pos)} "
          f"(test expects 2 x defaultWeight = {2 * DEFAULT_WEIGHT})")
    checks.append(("upstream ring vectors", ok == len(vectors) and len(ring2.pos) == 400))
    rng = random.Random(7)
    eps = [f"endpoint-{i}" for i in range(10)]
    ring10 = LBRing(eps)
    cnt = collections.Counter(ring10.endpoint_for(rng.getrandbits(128).to_bytes(16, "big")) for _ in range(20_000))
    mean = 20_000 / 10
    cv = (sum((cnt[e] - mean) ** 2 for e in eps) / 10) ** 0.5 / mean
    print(f"10 endpoints, 20,000 random trace IDs: CV {cv:.3f}, max/min {max(cnt.values()) / min(cnt.values()):.2f} "
          f"(upstream test bounds: CV <= 0.10, max/min <= 1.35)")
    checks.append(("distribution within upstream bounds", cv <= 0.10 and max(cnt.values()) / min(cnt.values()) <= 1.35))
    print()

    print("== 2. Why tail samplers need trace-ID routing: random LB vs the ring, 4 sampler pods ==")
    traces = gen_traces(20_000)
    truth = sum(keep(t) for t in traces)
    pods = [f"sampler-{i}.sampler-headless:4317" for i in range(4)]
    ring4 = LBRing(pods)
    rr = random.Random(2)
    whole = wrong = 0
    owners = collections.Counter()
    for t in traces:
        per = collections.Counter(pods[rr.randrange(4)] for _ in range(t["spans"]))
        whole += len(per) == 1
        votes = {keep(t, c) for c in per.values()}
        wrong += len(votes) > 1 or votes != {keep(t)}
        owners[ring4.endpoint_for(t["id"])] += 1
    print(f"policy on complete traces keeps {truth:,} of {len(traces):,} ({truth / len(traces):.1%})")
    print(f"random LB: {whole / len(traces):.1%} of traces seen whole by one pod; {wrong / len(traces):.1%} get a "
          f"split or wrong decision (errors/latency visible to only part of the trace)")
    print(f"ring:      100% seen whole by construction; per-pod share "
          f"{', '.join(f'{v / len(traces):.0%}' for _, v in sorted(owners.items()))}")
    checks.append(("random LB fragments traces", whole / len(traces) < 0.05 and wrong > 0))
    print()

    print("== 3. The circular buffer: num_traces vs rate x decision_wait (dropped_too_early) ==")
    rate = 2000
    print(f"{'num_traces':>10} {'decision_wait':>13} {'rate x wait':>11} {'dropped too early':>18}")
    rows = []
    for num, wait in ((50_000, 30), (59_000, 30), (61_000, 30), (50_000, 10)):
        d, dec = buffer_sim(rate, 120, num, wait)
        frac = d / (d + dec) if d + dec else 0.0
        rows.append(frac)
        print(f"{num:>10,} {wait:>12}s {rate * wait:>11,} {frac:>17.1%}")
    checks.append(("buffer is a cliff", rows[0] == 1.0 and rows[1] == 1.0 and rows[2] == 0.0 and rows[3] == 0.0))
    print("-> a cliff, not a slope: with FIFO eviction every trace lives num_traces / rate seconds, so once")
    print("   that is shorter than decision_wait EVERY trace is evicted unevaluated. The README defaults")
    print("   (decision_wait 30s, num_traces 50,000) fall off it at 1,667 new traces/s per pod. Size")
    print("   num_traces >= 1.5 x per-pod rate x decision_wait and alert on dropped_too_early > 0.")
    late = {w: sum(t["lateness"] > w for t in traces) / len(traces) for w in (2, 5, 10)}
    print(f"traces with a span arriving after decision_wait (first->last span spread): "
          f"{', '.join(f'{w}s {v:.2%}' for w, v in late.items())}")
    checks.append(("late spans shrink with wait", late[10] < late[5] < late[2]))
    print("-> late spans inherit the decision only while it is still buffered or cached; configure")
    print("   decision_cache.sampled_cache_size >> num_traces so stragglers of kept traces are kept too.")
    print()

    print("== 4. Scaling the sampler StatefulSet 4 -> 5 pods with the upstream ring ==")
    ring5 = LBRing(pods + ["sampler-4.sampler-headless:4317"])
    moved = sum(ring4.endpoint_for(t["id"]) != ring5.endpoint_for(t["id"]) for t in traces) / len(traces)
    modn = sum((int.from_bytes(t["id"], "big") % 4) != (int.from_bytes(t["id"], "big") % 5) for t in traces) / len(traces)
    print(f"ring: {moved:.1%} of trace IDs change owner (ideal 1/5 = 20%); naive hash mod N: {modn:.1%}")
    checks.append(("ring remaps ~1/N", 0.14 < moved < 0.27 and modn > 0.7))
    print("-> for one decision_wait after the resolver sees the new pod, every remapped in-flight trace is")
    print("   split across two samplers. Scale with headroom, not reactively on CPU, and prefer the k8s")
    print("   resolver (EndpointSlice watch) over dns (polling) to shrink the inconsistent window.")
    print()

    print("== 5. The probabilistic policy (FNV-1a over salt + trace ID) and stacked samplers ==")
    fnv_ok = fnv1a64(b"a") == 0xAF63DC4C8601EC8C and fnv1a64(b"foobar") == 0x85944171F73967E8
    print(f"FNV-1a 64 reference vectors ('a', 'foobar'): {'match' if fnv_ok else 'MISMATCH'}")
    checks.append(("fnv1a64 vectors", fnv_ok))
    rp = random.Random(123)
    ids = [rp.getrandbits(128).to_bytes(16, "big") for _ in range(100_000)]
    eff = {pct: sum(prob_sampled(i, pct) for i in ids) / len(ids) * 100 for pct in (25, 33)}
    salted = sum(prob_sampled(i, 33, "test-salt") for i in ids) / len(ids) * 100
    print(f"effective rate on 100,000 IDs: 25% -> {eff[25]:.2f}%, 33% -> {eff[33]:.2f}%, 33% salted -> {salted:.2f}% "
          f"(upstream test tolerance +/-0.2)")
    checks.append(("FNV policy hits its rate", all(abs(eff[p] - p) <= 0.2 for p in eff) and abs(salted - 33) <= 0.2))
    head = [i for i in ids if int.from_bytes(i[9:], "big") < int(0.10 * 2**56)]   # SDK ratio sampler on 56-bit randomness
    both = sum(prob_sampled(i, 10) for i in head) / len(ids)
    print(f"10% head sampling (SDK, low 56 bits of the trace ID) then a 10% tail probabilistic policy keeps "
          f"{both:.2%} of traces, not 10%")
    checks.append(("independent hashes multiply", 0.007 < both < 0.013))
    print("-> two samplers with unrelated hash functions compose multiplicatively. Either sample once, or")
    print("   enable the usetracestate gate so the tail policy reads the W3C tracestate threshold/randomness")
    print("   and adjusted counts stay correct end to end.")
    print()

    print("== 6. Span metrics: where to generate them, and what they cost ==")
    services, ops, codes, kinds, buckets = 40, 25, 3, 2, 16
    calls = services * ops * codes * kinds
    print(f"service.name x span.name x status.code x span.kind = {services}x{ops}x{codes}x{kinds} = {calls:,} calls "
          f"series; duration histogram adds {buckets} buckets + _sum + _count = {calls * (buckets + 2):,} series")
    true_err = sum(t["error"] for t in traces) / len(traces)
    kept = [t for t in traces if keep(t)]
    post_err = sum(t["error"] for t in kept) / len(kept)
    print(f"error ratio from all spans {true_err:.2%}; from tail-sampled traces {post_err:.1%} "
          f"({post_err / true_err:.0f}x inflated)")
    checks.append(("post-sampling RED biased", post_err > 5 * true_err))
    print("-> run the span_metrics connector in tier 1 (before sampling) or rely on Tempo's metrics-generator")
    print("   fed the unsampled stream; RED computed after sampling is biased toward what the policy keeps.")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:tail_sampling_lab.py -->
```text
== 1. The load_balancing exporter ring (port of consistent_hashing.go @ v0.164.0) ==
upstream TestEndpointFor vectors: 4/4 match; ring items = 400 (test expects 2 x defaultWeight = 400)
10 endpoints, 20,000 random trace IDs: CV 0.099, max/min 1.32 (upstream test bounds: CV <= 0.10, max/min <= 1.35)

== 2. Why tail samplers need trace-ID routing: random LB vs the ring, 4 sampler pods ==
policy on complete traces keeps 1,978 of 20,000 (9.9%)
random LB: 0.8% of traces seen whole by one pod; 7.6% get a split or wrong decision (errors/latency visible to only part of the trace)
ring:      100% seen whole by construction; per-pod share 23%, 27%, 27%, 23%

== 3. The circular buffer: num_traces vs rate x decision_wait (dropped_too_early) ==
num_traces decision_wait rate x wait  dropped too early
    50,000           30s      60,000            100.0%
    59,000           30s      60,000            100.0%
    61,000           30s      60,000              0.0%
    50,000           10s      20,000              0.0%
-> a cliff, not a slope: with FIFO eviction every trace lives num_traces / rate seconds, so once
   that is shorter than decision_wait EVERY trace is evicted unevaluated. The README defaults
   (decision_wait 30s, num_traces 50,000) fall off it at 1,667 new traces/s per pod. Size
   num_traces >= 1.5 x per-pod rate x decision_wait and alert on dropped_too_early > 0.
traces with a span arriving after decision_wait (first->last span spread): 2s 5.08%, 5s 4.09%, 10s 0.00%
-> late spans inherit the decision only while it is still buffered or cached; configure
   decision_cache.sampled_cache_size >> num_traces so stragglers of kept traces are kept too.

== 4. Scaling the sampler StatefulSet 4 -> 5 pods with the upstream ring ==
ring: 19.8% of trace IDs change owner (ideal 1/5 = 20%); naive hash mod N: 79.4%
-> for one decision_wait after the resolver sees the new pod, every remapped in-flight trace is
   split across two samplers. Scale with headroom, not reactively on CPU, and prefer the k8s
   resolver (EndpointSlice watch) over dns (polling) to shrink the inconsistent window.

== 5. The probabilistic policy (FNV-1a over salt + trace ID) and stacked samplers ==
FNV-1a 64 reference vectors ('a', 'foobar'): match
effective rate on 100,000 IDs: 25% -> 25.02%, 33% -> 32.98%, 33% salted -> 33.14% (upstream test tolerance +/-0.2)
10% head sampling (SDK, low 56 bits of the trace ID) then a 10% tail probabilistic policy keeps 1.02% of traces, not 10%
-> two samplers with unrelated hash functions compose multiplicatively. Either sample once, or
   enable the usetracestate gate so the tail policy reads the W3C tracestate threshold/randomness
   and adjusted counts stay correct end to end.

== 6. Span metrics: where to generate them, and what they cost ==
service.name x span.name x status.code x span.kind = 40x25x3x2 = 6,000 calls series; duration histogram adds 16 buckets + _sum + _count = 108,000 series
error ratio from all spans 1.00%; from tail-sampled traces 10.2% (10x inflated)
-> run the span_metrics connector in tier 1 (before sampling) or rely on Tempo's metrics-generator
   fed the unsampled stream; RED computed after sampling is biased toward what the policy keeps.

checks: 10/10 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Tier 1 — OpenTelemetry Collector router gateway (v0.164.0 component names)

```yaml
# otelcol-router.yaml — Deployment behind a ClusterIP Service; HPA on CPU; 3+ replicas across zones.
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
  file_storage/queue:
    directory: /var/lib/otelcol/queue
    timeout: 1s
    compaction:
      on_start: true
      directory: /var/lib/otelcol/queue
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        max_recv_msg_size_mib: 16
      http:
        endpoint: 0.0.0.0:4318
processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 20
  k8s_attributes:
    auth_type: serviceAccount
    passthrough: false
    pod_association:
      - sources:
          - from: resource_attribute
            name: k8s.pod.ip
      - sources:
          - from: connection
    extract:
      metadata:
        - k8s.namespace.name
        - k8s.deployment.name
        - k8s.statefulset.name
        - k8s.pod.name
        - k8s.node.name
  resource/cluster:
    attributes:
      - key: k8s.cluster.name
        value: prod-use1
        action: upsert
      - key: deployment.environment.name
        value: production
        action: upsert
connectors:
  span_metrics:
    histogram:
      unit: s
      exponential:
        max_size: 160
    dimensions:
      - name: http.request.method
      - name: http.route
      - name: rpc.method
    exclude_dimensions:
      - status.message
    aggregation_cardinality_limit: 50000
    metrics_flush_interval: 15s
    metrics_expiration: 5m
    exemplars:
      enabled: true
      max_per_data_point: 5
    resource_metrics_key_attributes:
      - service.name
      - k8s.cluster.name
exporters:
  load_balancing/samplers:
    routing_key: traceID
    protocol:
      otlp:
        timeout: 5s
        tls:
          insecure: true
        sending_queue:
          enabled: true
          num_consumers: 20
          queue_size: 5000
        retry_on_failure:
          enabled: true
          max_elapsed_time: 60s
    resolver:
      k8s:
        service: otel-sampler.observability
        ports:
          - 4317
        timeout: 1s
    sending_queue:
      enabled: true
      queue_size: 10000
    retry_on_failure:
      enabled: true
      max_elapsed_time: 120s
  otlp_http/mimir:
    endpoint: http://mimir-distributor.mimir.svc:8080/otlp
    headers:
      X-Scope-OrgID: prod
    sending_queue:
      enabled: true
      num_consumers: 10
      queue_size: 2000
      storage: file_storage/queue
      batch:
        flush_timeout: 1s
        min_size: 4096
        max_size: 16384
        sizer: items
    retry_on_failure:
      enabled: true
      max_elapsed_time: 300s
service:
  extensions:
    - health_check
    - file_storage/queue
  telemetry:
    metrics:
      level: detailed
      readers:
        - pull:
            exporter:
              prometheus:
                host: 0.0.0.0
                port: 8888
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, k8s_attributes, resource/cluster]
      exporters: [span_metrics, load_balancing/samplers]
    metrics/spans:
      receivers: [span_metrics]
      processors: [memory_limiter]
      exporters: [otlp_http/mimir]
```

**Why each non-default line exists.**
- **`memory_limiter` first.** It is admission control (§1.1).
- **`k8s_attributes` with `pod_association`.** Resource attributes give stable per-pod RED, and the connection fallback covers SDKs that did not set `k8s.pod.ip`.
- **`span_metrics` gets every span before sampling.** It runs with a cardinality cap, `metrics_expiration` (so dead pods' series stop being exported) and exemplars (Folder 05 file 02).
- **The `load_balancing` exporter uses the `k8s` resolver.** It watches EndpointSlices, which makes it faster than `dns` polling.
  - It needs RBAC `get/list/watch` on `discovery.k8s.io/v1` `EndpointSlice` [D].
  - Two resilience levels are configured. The sub-exporter queue/retry handles one sampler blipping. The top-level queue/retry re-routes after the ring changes; it is **disabled by default** [D].
- **Persistent queue on the Mimir exporter.** It survives a router restart. The sampler path cannot use a persistent queue, because sub-exporters share one queue config [D].

### 2.2 Tier 2 — tail samplers (StatefulSet + headless Service)

```yaml
# otelcol-sampler.yaml — StatefulSet otel-sampler, headless Service otel-sampler (clusterIP: None), 4+ replicas.
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 75
    spike_limit_percentage: 15
  tail_sampling:
    decision_wait: 15s
    num_traces: 150000
    expected_new_traces_per_sec: 6000
    block_on_overflow: true
    decision_cache:
      sampled_cache_size: 1000000
      non_sampled_cache_size: 1000000
    policies:
      - name: errors
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: slow
        type: latency
        latency:
          threshold_ms: 1500
      - name: checkout-and-payments-always
        type: string_attribute
        string_attribute:
          key: service.name
          values: [payments, fraud-scoring]
      - name: drop-health-checks
        type: drop
        drop:
          drop_sub_policy:
            - name: health-route
              type: string_attribute
              string_attribute:
                key: http.route
                values: ['/health.*', '/ready', '/metrics']
                enabled_regex_matching: true
      - name: baseline
        type: probabilistic
        probabilistic:
          sampling_percentage: 5
          hash_salt: prod-tail-v1
exporters:
  otlp_grpc/tempo:
    endpoint: tempo-distributor.tempo.svc:4317
    tls:
      insecure: true
    headers:
      X-Scope-OrgID: prod
    sending_queue:
      enabled: true
      num_consumers: 20
      queue_size: 10000
      sizer: requests
      batch:
        flush_timeout: 500ms
        min_size: 8192
        max_size: 32768
        sizer: items
    retry_on_failure:
      enabled: true
      max_elapsed_time: 300s
service:
  extensions: [health_check]
  telemetry:
    metrics:
      level: detailed
      readers:
        - pull:
            exporter:
              prometheus:
                host: 0.0.0.0
                port: 8888
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, tail_sampling]
      exporters: [otlp_grpc/tempo]
```

**Sizing this pod.** The peak is 4,000 new traces/s per pod (the hottest pod is 1.08× the mean from L1 §1, plus headroom).
- `num_traces` is 150,000, which is at least 1.5 × 6,000 × 15 s.
- Memory ≈ in-flight traces × spans/trace × ~1.2 KB/span: 60,000 × 9 × 1.2 KB ≈ **650 MB**, plus decision caches (≈ 16 B/ID → 32 MB). Set the pod limit around 2 GiB so `limit_percentage: 75` leaves room.
- The `drop` policy wins over every sample policy [D], so health-check traces never reach Tempo however slow they are.

### 2.3 The same two tiers in Grafana Alloy (v1.21.3 component names)

```alloy
// alloy-router.alloy — tier 1. Note the Alloy names: otelcol.connector.spanmetrics, otelcol.exporter.loadbalancing.
otelcol.receiver.otlp "apps" {
  grpc { endpoint = "0.0.0.0:4317" }
  http { endpoint = "0.0.0.0:4318" }
  output {
    traces = [otelcol.processor.memory_limiter.router.input]
  }
}

otelcol.processor.memory_limiter "router" {
  check_interval         = "1s"
  limit_percentage       = 80
  spike_limit_percentage = 20
  output {
    traces = [otelcol.processor.k8sattributes.router.input]
  }
}

otelcol.processor.k8sattributes "router" {
  extract {
    metadata = ["k8s.namespace.name", "k8s.deployment.name", "k8s.pod.name", "k8s.node.name"]
  }
  output {
    traces = [
      otelcol.connector.spanmetrics.red.input,
      otelcol.exporter.loadbalancing.samplers.input,
    ]
  }
}

otelcol.connector.spanmetrics "red" {
  dimension { name = "http.request.method" }
  dimension { name = "http.route" }
  histogram {
    unit = "s"
    exponential { max_size = 160 }
  }
  aggregation_cardinality_limit = 50000
  metrics_flush_interval        = "15s"
  metrics_expiration            = "5m"
  exemplars { enabled = true }
  output {
    metrics = [otelcol.exporter.otlphttp.mimir.input]
  }
}

otelcol.exporter.loadbalancing "samplers" {
  routing_key = "traceID"
  resolver {
    kubernetes {
      service = "otel-sampler.observability"
      ports   = [4317]
    }
  }
  protocol {
    otlp {
      client {
        tls { insecure = true }
      }
    }
  }
}

otelcol.exporter.otlphttp "mimir" {
  client {
    endpoint = "http://mimir-distributor.mimir.svc:8080/otlp"
    headers  = { "X-Scope-OrgID" = "prod" }
  }
}
```

```alloy
// alloy-sampler.alloy — tier 2 (StatefulSet + headless Service otel-sampler).
otelcol.receiver.otlp "router" {
  grpc { endpoint = "0.0.0.0:4317" }
  output {
    traces = [otelcol.processor.memory_limiter.sampler.input]
  }
}

otelcol.processor.memory_limiter "sampler" {
  check_interval         = "1s"
  limit_percentage       = 75
  spike_limit_percentage = 15
  output {
    traces = [otelcol.processor.tail_sampling.policy.input]
  }
}

otelcol.processor.tail_sampling "policy" {
  decision_wait               = "15s"
  num_traces                  = 150000
  expected_new_traces_per_sec = 6000
  block_on_overflow           = true
  decision_cache = {
    sampled_cache_size     = 1000000,
    non_sampled_cache_size = 1000000,
  }

  policy {
    name = "errors"
    type = "status_code"
    status_code { status_codes = ["ERROR"] }
  }
  policy {
    name = "slow"
    type = "latency"
    latency { threshold_ms = 1500 }
  }
  policy {
    name = "baseline"
    type = "probabilistic"
    probabilistic {
      sampling_percentage = 5
      hash_salt           = "prod-tail-v1"
    }
  }

  output {
    traces = [otelcol.exporter.otlp.tempo.input]
  }
}

otelcol.exporter.otlp "tempo" {
  client {
    endpoint = "tempo-distributor.tempo.svc:4317"
    tls { insecure = true }
    headers = { "X-Scope-OrgID" = "prod" }
  }
}
```

### 2.4 Kubernetes objects the topology depends on

```yaml
apiVersion: v1
kind: Service
metadata:
  name: otel-sampler
  namespace: observability
spec:
  clusterIP: None
  publishNotReadyAddresses: false
  selector:
    app.kubernetes.io/name: otel-sampler
  ports:
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: otel-router-endpointslices
  namespace: observability
rules:
  - apiGroups: ["discovery.k8s.io"]
    resources: ["endpointslices"]
    verbs: ["get", "list", "watch"]
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: otel-sampler
  namespace: observability
spec:
  maxUnavailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: otel-sampler
```

- **`publishNotReadyAddresses: false`.** The `k8s` resolver drops endpoints whose `conditions.ready` is false [D], so a starting sampler gets traffic only once ready.
- **PDB `maxUnavailable: 1`.** Each eviction remaps ~1/N of in-flight traces (L1 §4). One at a time bounds the damage.
- **Do not put an HPA on the sampler StatefulSet.** Reactive scaling remaps traces exactly when load peaks. Scale it deliberately, off-peak, with headroom from §2.2.

### 2.5 PromQL for the pipeline itself

```promql
# Traces evicted before evaluation (must be 0)
sum by (pod) (rate(otelcol_processor_tail_sampling_sampling_trace_dropped_too_early[5m])) > 0

# Kept ratio per policy (sanity-check policy drift)
sum by (policy) (rate(otelcol_processor_tail_sampling_count_traces_sampled{sampled="true"}[15m]))
  / sum by (policy) (rate(otelcol_processor_tail_sampling_count_traces_sampled[15m]))

# Exporter queue saturation (1 = full; anything above 0.8 for 10m is a page)
max by (pod, exporter) (otelcol_exporter_queue_size / otelcol_exporter_queue_capacity)

# Data the collector refused or failed to send
sum by (pod, receiver) (rate(otelcol_receiver_refused_spans_total[5m]))
sum by (pod, exporter) (rate(otelcol_exporter_send_failed_spans_total[5m]))

# Sampler load skew: hottest sampler vs mean (provision for the max)
max(sum by (pod) (rate(otelcol_receiver_accepted_spans_total{job="otel-sampler"}[5m])))
  / avg(sum by (pod) (rate(otelcol_receiver_accepted_spans_total{job="otel-sampler"}[5m])))
```

⚠ Internal metric names depend on `service.telemetry.metrics.level` and on feature gates (the README notes that `count_spans_sampled` needs `processor.tailsamplingprocessor.metricstatcountspanssampled`). Confirm names against `:8888/metrics` after each upgrade.

---

## 3. Failure modes and FinOps debugging

### F1. Tail sampling keeps "random" traces and misses errors

**Symptom.** Error traces are missing in Tempo even though the `status_code` policy is configured. Kept traces look fragmented.

**Signature.** Tier 1 uses a plain Service (kube-proxy round-robin) or OTLP client load balancing in front of the samplers. Each sampler's accepted-span rate is fine, but per-trace span counts in Tempo are a fraction of what the SDK emitted.

**Root cause.** Spans of a trace are spread across samplers, so no single pod sees the whole trace. L1 §2: 99.2% of traces are fragmented and 7.6% get a wrong or split decision.

**Fix.** Put the `load_balancing` exporter (`routing_key: traceID`, `k8s` resolver) in tier 1 and a headless Service in front of a sampler StatefulSet.

**Prevention.** Run a synthetic trace with a known span count through the pipeline every minute and assert the count in Tempo.

### F2. Silent 100% drop after a traffic increase

**Symptom.** Tempo ingest falls to near zero during a peak; collectors look healthy.

**Signature.** `otelcol_processor_tail_sampling_sampling_trace_dropped_too_early` jumps from 0 to the full new-trace rate. `sampling_trace_removal_age` p1 is below `decision_wait`.

**Root cause.** The FIFO buffer cliff (§1.4): `num_traces / per-pod rate < decision_wait`. With the defaults (50,000 / 30 s) it hits at 1,667 traces/s per pod.

**Fix.** Raise `num_traces` and/or cut `decision_wait` from the measured completion distribution. Add sampler pods off-peak. Consider `block_on_overflow: true` with tier-1 queue headroom.

**Prevention.** Capacity alert on `rate(new traces) × decision_wait / num_traces > 0.7` per pod. Keep a `dropped_too_early > 0` page.

### F3. Half-traces after rollouts and scale events

**Symptom.** Traces with missing subtrees appear in bursts around deploys of the sampler tier.

**Signature.** It correlates with EndpointSlice changes. The routers' `loadbalancer` ring-update metrics fire at different times on different router pods.

**Root cause.**
- About 1/N of trace IDs move owner when the ring changes (L1 §4).
- Router pods see the change at different moments.
- In-flight traces are split for one `decision_wait`.

**Fix.**
- Set PDB `maxUnavailable: 1` and roll slowly (`minReadySeconds` ≥ `decision_wait`).
- Use the `k8s` resolver over `dns`.
- Enable top-level queue/retry so data re-routes after ring changes.

**Prevention.** No HPA on samplers. Schedule capacity changes off-peak. Track the fraction of traces with orphan spans (`rootServiceName` missing) as a pipeline SLI.

### F4. RED dashboards show 10× the real error rate

**Symptom.** After tail sampling went live, error-ratio panels and SLO burn alerts jumped. No customer impact.

**Signature.** The span-metrics series originate from the sampler tier or from Tempo's metrics-generator fed sampled data. Their error ratio is roughly the kept-error ratio.

**Root cause.** RED computed after a policy that keeps errors preferentially. L1 §6: 1.00% true vs 10.2% observed.

**Fix.** Move `span_metrics` to tier 1 (before sampling). For Tempo-generated metrics, feed the generator the full stream, or use the tracestate span multiplier to re-weight ⚠.

**Prevention.** Reconcile span-metrics request rate against application (Micrometer) request rate daily. They must agree within a few percent.

### F5. Span-metrics cardinality bill

**Symptom.** Active series in Mimir grow by hundreds of thousands. The OTLP endpoint starts returning per-tenant series-limit errors.

**Signature.** New `traces_span_metrics_*` series per `span.name` or per dimension value. Span names contain IDs (`GET /orders/8812731`) because an instrumentation library used raw paths.

**Root cause.**
- An unbounded dimension or unbounded span names.
- No `aggregation_cardinality_limit`.
- A histogram × dimensions product (§1.6: 108,000 series from 6,000 call series).

**Fix.**
- Normalise span names (use `http.route`).
- Drop the dimension.
- Set `aggregation_cardinality_limit` and watch `otel.metric.overflow="true"`.
- Prefer exponential histograms (one native histogram series in Mimir instead of 16+ bucket series).

**Prevention.** Run a CI check on span names in instrumentation. Add a Mimir per-tenant active-series dashboard with a span-metrics breakdown.

### F6. Collector OOMKilled under a burst

**Symptom.** Gateway pods restart with OOMKilled; data loss during the burst.

**Signature.** No `memory_limiter`, or it is not first. `limit_percentage` is set without a container memory limit, so the percentage is of node memory. Or GOMEMLIMIT is unset and the Go GC lags.

**Root cause.** Admission control is missing, so the heap grows with the burst until the cgroup kills the process.

**Fix.**
- Put `memory_limiter` first with `limit_percentage`/`spike_limit_percentage` against a real container limit.
- Set `GOMEMLIMIT` to about 80% of the limit.
- Give exporter queues bounded sizes.

**Prevention.** Load-test at 3× peak. Alert on `otelcol_receiver_refused_*` (healthy back-pressure) separately from restarts (unhealthy).

### F7. Double-counted span metrics across router replicas

**Symptom.** Span-metrics request rate equals N × the application's request rate after scaling tier 1 to N pods.

**Signature.** The same series exists from each router pod. Recording rules use `sum by (service)` but the series differ only by a dropped instance attribute, so Mimir sees colliding samples (out-of-order or duplicate errors) or, if distinct, sums them.

**Root cause.** The single-writer principle is violated: several writers emit the same metric identity.

**Fix.** Keep `collector.instance.id` (or `include_collector_instance_id` in Alloy) and aggregate it away in rules. Or route by service to a span-metrics tier.

**Prevention.** Lint for metric streams with more than one writer (`count by (__name__, service_name) (...) > 1` on an instance-free projection).

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Design trace sampling for 300k spans/s across 400 services."</b></summary>

**Initial Prompt.** Keep all errors and slow traces, cap storage cost, and keep RED accurate.

**L5 Textbook Answer.** Use the tail-sampling processor with error, latency and probabilistic policies in the collector.

**Why L5 Fails at 3 AM or on the Bill.**
- It does not say where spans go, so a round-robin Service fragments traces (F1).
- The defaults fall off the buffer cliff at 1,667 traces/s per pod (F2).
- RED computed downstream is 10× wrong (F4).

**L7 Principal Defense.**
- **Topology.** Two tiers: a stateless router (HPA) and stateful samplers (StatefulSet, headless Service, `load_balancing` with `traceID` routing and the `k8s` resolver).
- **Sizing.** 300k spans/s ÷ 9 spans/trace ≈ 33k traces/s. With 8 sampler pods that is ~4.2k/s mean and ~4.5k at the hottest pod. With `decision_wait` 15 s, `num_traces` ≥ 1.5 × 4.5k × 15 ≈ 100k. Memory is roughly 0.6–0.8 GB per pod.
- **Span metrics.** Generated in tier 1 from 100% of spans, with a cardinality cap.
- **Policies.** Errors, latency at the p99 SLO threshold, always-keep for regulated flows, drop for health checks, and a 5% salted baseline.
- **Guardrails.** Alert on `dropped_too_early > 0`, a synthetic span-count check, and no autoscaling on samplers.
- **Cost.** Storage ≈ 5% baseline + ~1% errors + ~1% slow ≈ 7% of spans, versus 100% for head-based capture-all.
</details>

<details><summary><b>Q2 · "Why not just head-sample at 10%?"</b></summary>

**Initial Prompt.** It's cheaper and stateless.

**L5 Textbook Answer.** Head sampling is fine if errors are frequent enough.

**Why L5 Fails at 3 AM or on the Bill.** At a 1% error rate with 10% head sampling, 90% of error traces are gone. The trace you need during an incident is usually not there, and exemplars point to missing traces (Folder 05 file 02).

**L7 Principal Defense.**
- I'd use head sampling where its statistics are acceptable: very high-volume, homogeneous endpoints.
- I'd use tail sampling where outcomes matter.
- If both exist, they must compose consistently. L1 §5 shows independent hashes multiply (10% × 10% → 1.02%). Enable the tracestate-aware mode so thresholds compose and adjusted counts stay correct, or sample in exactly one place.
- RED never comes from sampled data.
</details>

<details><summary><b>Q3 · "Collector or Alloy for our fleet?"</b></summary>

**Initial Prompt.** We run the Grafana stack plus some vendor APM.

**L5 Textbook Answer.** Alloy, because it's Grafana's and supports everything.

**Why L5 Fails at 3 AM or on the Bill.**
- It ignores component lag and naming drift. Alloy wraps contrib components under old names and lags the newest options.
- It ignores team skills (YAML pipelines vs Alloy syntax).
- It ignores where clustering and Prometheus-native features matter.

**L7 Principal Defense.** Decide per tier.
- **Node agents:** Alloy. Its native `prometheus.scrape` with clustering, `loki.source.kubernetes`, `pyroscope.ebpf` and the debug UI mean one agent replaces node-exporter scraping, Promtail and the profiler DaemonSet.
- **Gateway/sampling tiers:** either works, because the tail-sampling code is the same. I'd pick the upstream Collector where we need contrib components on release day or vendor exporters Alloy doesn't wrap.
- **Shared contract:** OTLP between tiers, semantic conventions, `service.name`/`k8s.*` resource attributes.
- **Upgrades:** each agent version is pinned and its component type names are checked in CI (the snake_case renames will bite YAML users).
</details>

<details><summary><b>Q4 · "How do you scale the sampling tier safely?"</b></summary>

**Initial Prompt.** Traffic doubles every Black Friday.

**L5 Textbook Answer.** Put an HPA on the sampler StatefulSet.

**Why L5 Fails at 3 AM or on the Bill.** Each scale event remaps ~1/N of in-flight traces (L1 §4: 19.8% for 4→5), and routers converge at different times. Autoscaling at peak manufactures half-traces exactly when you need complete ones (F3).

**L7 Principal Defense.**
- Pre-scale on a calendar to the peak-plus-headroom size.
- Roll one pod at a time with `minReadySeconds` ≥ `decision_wait`.
- Use the `k8s` resolver.
- Enable the load-balancer's top-level retry/queue for re-routing.
- Size the decision caches large so late spans keep their decisions.
- Measure orphan-span rate during the event.
- If the business can't tolerate any fragmentation, run samplers with consistent hashing inside one bigger pod per zone. That trades elasticity for stability.
</details>

<details><summary><b>Q5 · "Where should span metrics be generated?"</b></summary>

**Initial Prompt.** We have Tempo's metrics-generator and the collector connector.

**L5 Textbook Answer.** Tempo's metrics-generator, because it's built in.

**Why L5 Fails at 3 AM or on the Bill.** If Tempo only receives sampled traces, the generator computes RED on a biased sample (F4), and SLO alerts fire on phantom error rates.

**L7 Principal Defense.**
- RED must be computed on the full stream.
- Option A: the connector in the router tier, with duplicate writers handled (F7).
- Option B: Tempo receives 100% and the metrics-generator computes RED and service graphs, with tail sampling applied *after*. That is expensive.
- Option C: the generator with a span multiplier, valid only for probabilistic policies whose thresholds are known.
- I'd choose A for most fleets. Either way, reconcile against Micrometer request counters, because the application is the source of truth for RED.
</details>

<details><summary><b>Q6 · "A sampler pod is hot. Why?"</b></summary>

**Initial Prompt.** One of 6 samplers runs at 2× the CPU of the others.

**L5 Textbook Answer.** Hashing is uneven; add more pods.

**Why L5 Fails at 3 AM or on the Bill.** With 200 virtual points per endpoint the ring is within ~1.3× max/min (L1 §1), so 2× is not the ring. Adding pods remaps traces and doesn't fix the cause.

**L7 Principal Defense.**
- Look at what is routed, not how.
- A few giant traces (batch jobs with 50k spans) dominate one pod. Cap them with `maximum_trace_size_bytes` or `span_count`, or route batch traffic separately.
- A producer with a non-random trace-ID generator skews the hash. Upstream warns about non-random low bytes for `randomness` routing.
- A misconfigured resolver can list one pod twice.
- I'd check per-pod trace size histograms and span-count p99 before touching the ring.
</details>

<details><summary><b>Q7 · "How do you know your pipeline isn't losing data?"</b></summary>

**Initial Prompt.** The CFO asks why we pay for observability that 'loses traces'.

**L5 Textbook Answer.** Check the collector logs for errors.

**Why L5 Fails at 3 AM or on the Bill.** Drops are mostly silent counters:
- `enqueue_failed`;
- `send_failed`;
- `dropped_too_early`;
- `refused`;
- memory-limiter refusals that become SDK-side drops.

Logs won't show them.

**L7 Principal Defense.** Track a conservation equation per hop.
- **Equation.** SDK exported = router accepted + router refused. Router sent = sampler accepted. Sampler kept = Tempo distributor received.
- **Mechanism.** Each term is a counter. A recording rule computes loss ratios, and an SLO on "telemetry delivered" (99.9% of accepted spans reach storage) gets its own error budget.
- **Synthetics.** A probe with a known span count runs end to end.
- **Budget.** Collector queues are sized for 10 minutes of backend outage (persistent where possible), so 'losing traces' becomes a quantified, budgeted number instead of a surprise.
</details>

<details><summary><b>Q8 · "OTLP gRPC or HTTP between tiers, and how big are batches?"</b></summary>

**Initial Prompt.** Network team wants fewer, bigger requests.

**L5 Textbook Answer.** gRPC is faster; use big batches.

**Why L5 Fails at 3 AM or on the Bill.**
- gRPC with long-lived HTTP/2 connections pins clients to one backend behind an L4 load balancer, so new pods get no traffic.
- Huge batches exceed `max_recv_msg_size` (OTLP gRPC defaults to 4 MiB receive on many servers) and are rejected wholesale.
- They also amplify retry storms.

**L7 Principal Defense.**
- Within the cluster, use gRPC with client-side balancing. The `load_balancing` exporter makes one connection per endpoint anyway.
- Across L7 proxies, use HTTP/protobuf, which balances per request.
- Size batches in **items** (`sending_queue.batch` 8–32k spans) with `max_size` set so splitting happens, and align the receiver's `max_recv_msg_size_mib`.
- Monitor request size p99 against the limit.
- gzip compresses OTLP well (CPU vs bytes). On a cross-AZ link billed per GB, compression pays for itself; within an AZ, measure first.
</details>

<details><summary><b>Q9 · "What does decision_wait really cost?"</b></summary>

**Initial Prompt.** Product wants 60s to catch slow async flows.

**L5 Textbook Answer.** Increase it to 60s; memory is cheap.

**Why L5 Fails at 3 AM or on the Bill.** Memory scales linearly, and the cliff moves: with unchanged `num_traces`, the drop threshold halves (F2). Every trace also becomes visible in Tempo a minute later, which hurts incident response.

**L7 Principal Defense.**
- Use `decision_wait_after_root_received` to decide early when the root span has arrived. Most synchronous traces then decide in seconds while async ones wait.
- Size `num_traces` for the long tail.
- Route known-async workloads (batch, messaging) to a separate sampler pool with a long wait.
- Quantify with `late_span_age`: L1 §3 shows lateness concentrated in a few percent of traces.
</details>

---

## 5. Invariants checklist

- [ ] Every pipeline starts with `memory_limiter`, sized against a real container limit; `GOMEMLIMIT` is set.
- [ ] Tail samplers receive spans only via trace-ID consistent hashing (`load_balancing`, `k8s` resolver, headless Service, EndpointSlice RBAC).
- [ ] `num_traces ≥ 1.5 × hottest-pod new-traces/s × decision_wait`; `dropped_too_early > 0` pages.
- [ ] `decision_cache.sampled_cache_size ≫ num_traces`; `decision_wait` is chosen from measured lateness.
- [ ] No HPA on samplers; PDB `maxUnavailable: 1`; rollouts with `minReadySeconds ≥ decision_wait`.
- [ ] Span metrics are generated from 100% of spans, with `aggregation_cardinality_limit`, exemplars, and a single-writer strategy.
- [ ] Head and tail samplers compose deliberately (tracestate-aware) or only one exists.
- [ ] Per-hop conservation counters and a synthetic span-count probe exist.
- [ ] Component type names are pinned and CI-checked against the collector/Alloy version (snake_case renames).

---

## 6. References

- Tail sampling processor README (v0.164.0): <https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.164.0/processor/tailsamplingprocessor/README.md>
- Load-balancing exporter README and ring (v0.164.0): <https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.164.0/exporter/loadbalancingexporter/README.md> · <https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.164.0/exporter/loadbalancingexporter/consistent_hashing.go>
- Span metrics connector README (v0.164.0): <https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.164.0/connector/spanmetricsconnector/README.md>
- Exporter helper (queue, batch, retry) README: <https://github.com/open-telemetry/opentelemetry-collector/blob/v0.164.0/exporter/exporterhelper/README.md>
- Probabilistic policy source: <https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/v0.164.0/processor/tailsamplingprocessor/internal/sampling/probabilistic.go>
- Grafana Alloy `otelcol.processor.tail_sampling`: <https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.processor.tail_sampling/>
- Grafana Alloy `otelcol.exporter.loadbalancing`: <https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.exporter.loadbalancing/>
- Grafana Alloy `otelcol.connector.spanmetrics`: <https://grafana.com/docs/alloy/latest/reference/components/otelcol/otelcol.connector.spanmetrics/>
- OpenTelemetry sampling concepts: <https://opentelemetry.io/docs/concepts/sampling/>
- W3C Trace Context Level 2: <https://www.w3.org/TR/trace-context-2/>
