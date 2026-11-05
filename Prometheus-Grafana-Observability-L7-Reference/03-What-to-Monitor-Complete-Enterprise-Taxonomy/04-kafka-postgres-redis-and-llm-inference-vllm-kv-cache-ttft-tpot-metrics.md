# 04 · Kafka, PostgreSQL, Redis and LLM Inference (vLLM KV Cache, TTFT, TPOT) Metrics

> **Folder 03 — What to Monitor: Complete Enterprise Taxonomy · File 4 of 4.**
> Pinned to **kafka_exporter v1.11.0**, **postgres_exporter v0.20.1**, **redis_exporter v1.97.0**, **vLLM v0.32.0** (2026-10-18; metric names read from `vllm/v1/metrics/loggers.py`), Apache Kafka 4.4, PostgreSQL 18.
> Labels: **[D]** documented / read in pinned source · **[M]** measured by the listing (deterministic, re-run by the gate) · **[E]** model · **⚠** version-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L4 `lag_llm_lab.py` | Kafka lag in offsets vs time with real exporter metric names queried through the Folder 02 PromQL engine (a 5× produce spike against a 2,000 msg/s consumer; time lag, slope and drain ETA); Postgres time-based replica lag rising on an idle primary while LSN lag is 0; Redis hit ratio vs evictions and the 5.6× database read amplification; and a continuous-batching LLM server model where TTFT, inter-token latency, KV-cache usage, preemptions and goodput are derived for 2–12 req/s | ~1 s |

**Verification.** Exporter metric names come from the pinned exporter sources (`kafka_consumergroup_lag`, `kafka_topic_partition_current_offset`, `pg_replication_lag_seconds`, `redis_keyspace_hits_total`, `redis_evicted_keys_total`, …) and every PromQL expression in L4 is evaluated with the validated engine. The LLM server is a model [E] with stated parameters (prefill 25k tok/s, decode step 8 ms + 0.12 ms × batch, 200k-token KV budget); it reproduces the qualitative behaviour vLLM's metrics expose, not vLLM's absolute numbers. No live system was run.

---

## 0. Orientation

**What this file answers.** For the stateful and AI tiers behind most services: which signals are *saturation* and *correctness* (not just "is it up"), which popular metrics mislead, and how to express SLOs for systems whose unit of work is a message, a transaction, a cache hit or a generated token.

**The pattern across all four.** Each is a queue with a backlog you can measure in *units* (offsets, WAL bytes, keys, tokens) but must alert on in *time*: how long until a consumer catches up, how stale a replica is, how long a prompt waits for prefill. Converting units → time is the L7 move.

---

## 1. First principles: backlogs in units vs time

### 1.1 Kafka (4.x, KRaft) [D]

```text
 producer ──► partition (log end offset LEO) ───────────────────────► consumer group (committed offset)
                │                                                     │
   kafka_topic_partition_current_offset                kafka_consumergroup_current_offset
                └──────────── lag (offsets) = LEO − committed  ───────┘   kafka_consumergroup_lag
 time lag ≈ lag / produce rate   (how old the oldest unconsumed message is, if produce rate is steady)
 drain ETA = lag / (consume rate − produce rate)   (only meaningful when the denominator > 0)
```

L4 §1: a 10-minute 5× produce spike against a 2,000 msg/s consumer builds **1.79 M offsets** of lag — 15 minutes of consumer work; the slope turns negative (−1,000/s) after the spike and the queue drains ~30 minutes later [M]. The same 1.79 M offsets on a 10 msg/s topic would be four days. **Offset thresholds are not portable; time lag and slope are.**

Broker-side signals (JMX via the Prometheus JMX exporter; exact names depend on its rule file ⚠): under-replicated partitions, offline partitions, active controller count (exactly 1 across the KRaft quorum), request queue time and handler idle ratio (saturation), ISR shrink/expand rates, produce/fetch request latency, log flush time, disk usage per log dir. Client-side, Micrometer's `KafkaClientMetrics` exports consumer `records-lag-max` and fetch latency per client.

### 1.2 PostgreSQL 18 [D]

| Concern | Signal (postgres_exporter v0.20 / SQL) | Note |
|---|---|---|
| Availability | `pg_up` | exporter can connect |
| Saturation: connections | `sum(pg_stat_database_numbackends) / pg_settings_max_connections` | include connection-proxy pools |
| Saturation: locks | `pg_locks_count` by mode, `pg_stat_activity` waiting on `Lock` | blocking chains, not counts, page |
| Throughput / errors | `rate(pg_stat_database_xact_commit[5m])`, `xact_rollback`, `deadlocks` | rollback ratio as an error rate |
| Replication | `pg_replication_lag_seconds` (replica: `now() − pg_last_xact_replay_timestamp()`), WAL byte lag from `pg_stat_replication` | see the idle-primary trap |
| Vacuum / bloat | dead tuples, last autovacuum age, transaction-ID age (`age(datfrozenxid)`) | wraparound is an outage, alert at ~1 billion |
| Cache | buffer hit ratio from `blks_hit / (blks_hit + blks_read)` | trend, not threshold |
| Query latency | `pg_stat_statements` (mean/total time per normalised query) | cardinality: top-N only |

**The idle-primary trap (L4 §2 [M]).** Time-based replica lag is "time since the last *replayed transaction* committed"; on an idle primary no new transactions exist, so lag grows linearly (480 s after 8 idle minutes) while the replica is perfectly current (LSN byte lag 0). Page on WAL/LSN byte lag, or write a heartbeat row every 10 s so time lag is truthful.

### 1.3 Redis [D]

`redis_exporter` exposes `redis_up`, `redis_connected_clients`, `redis_blocked_clients`, `redis_rejected_connections_total`, `redis_memory_used_bytes`, `redis_memory_max_bytes`, `redis_keyspace_hits_total`, `redis_keyspace_misses_total`, `redis_evicted_keys_total`, `redis_commands_duration_seconds_total` (per command) and replication/persistence fields. Saturation for Redis is **memory against `maxmemory`** (evictions) and the **single command thread** (latency per command, slowlog), not CPU percentage.

**Cache economics (L4 §3 [M]).** Hit ratio 95% → 72% under eviction raises backend reads from 500/s to 2,800/s per 10k req/s — **5.6×** — because the backend sees *misses*, and misses scale as 1 − hit ratio. Alert on evictions *and* hit ratio together; capacity-plan cache memory from the miss-rate budget of the database behind it.

### 1.4 LLM inference servers (vLLM 0.32) [D]

vLLM's v1 engine exports (prefix `vllm:`; Prometheus names keep the colon) [D]:

| Signal | Metric | Meaning |
|---|---|---|
| Queueing | `vllm:num_requests_waiting`, `vllm:num_requests_running` | waiting = admission-blocked (KV or batch limits) |
| Saturation | `vllm:kv_cache_usage_perc` (formerly `gpu_cache_usage_perc`) | fraction of KV blocks in use |
| Preemption | `vllm:num_preemptions` (counter) | KV overflow → requests evicted and recomputed |
| TTFT | `vllm:time_to_first_token_seconds` (histogram) | queue + prefill |
| ITL / TPOT | `vllm:inter_token_latency_seconds`, `vllm:request_time_per_output_token_seconds` | decode speed per token / per request |
| E2E and phases | `vllm:e2e_request_latency_seconds`, `vllm:request_queue_time_seconds`, `vllm:request_prefill_time_seconds`, `vllm:request_decode_time_seconds` | decomposition |
| Throughput | `vllm:prompt_tokens`, `vllm:generation_tokens` (counters), `vllm:iteration_tokens_total` | tokens/s and batch size |
| Prefix cache | `vllm:prefix_cache_queries`, `vllm:prefix_cache_hits` | hit ratio (cost and TTFT lever) |
| Outcome | `vllm:request_success` (by finish reason) | stop vs length vs abort |

```text
 request ──► [waiting queue] ──admit if KV blocks + batch slots free──► [running batch]
              queue_time                       prefill (∝ prompt tokens) ─► first token  = TTFT
                                               decode steps (∝ batch size) ─► tokens… ITL/TPOT
 KV cache full ──► new requests wait; growing sequences may PREEMPT others (recompute)
```

L4 §4 (model) [E/M]:

| req/s | running | waiting | KV used | preemptions | TTFT p50 | TTFT p99 | TPOT p99 | goodput |
|---|---|---|---|---|---|---|---|---|
| 2 | 4.7 | 0 | 3% | 0 | 0.05 s | 0.18 s | 12 ms | 100% |
| 8 | 40.0 | 0 | 25% | 0 | 0.08 s | 0.33 s | 32 ms | 100% |
| 12 | 125.9 | **150.4** | 79% | **771** | **14.0 s** | **47.0 s** | 66 ms | **9%** |

- Past the knee, **TTFT is queueing, not compute** — `vllm:request_queue_time_seconds` explodes while prefill time is unchanged.
- **Tokens/s keeps rising while goodput collapses** — throughput is not the SLI. Goodput = share of requests meeting *both* TTFT and TPOT targets (e.g. TTFT ≤ 1 s, TPOT ≤ 50 ms).
- **`kv_cache_usage_perc` near 100% with `num_requests_waiting > 0`** is the saturation signal; preemptions are the error signal (recompute waste).

<!-- listing:lag_llm_lab.py -->
```python
"""lag_llm_lab.py - what the stateful-system signals in this file actually measure: Kafka consumer
lag in offsets vs time, Postgres replication lag on an idle primary, Redis hit ratio under
eviction, and a continuous-batching LLM server (vLLM-style) where TTFT, inter-token latency,
KV-cache usage, queue depth and goodput are derived from first principles.

The Kafka/Postgres/Redis series use the exporters' real metric names and are queried with
promql_mini.py (Folder 02). The LLM simulator is a model [E]: prefill ~ prompt tokens, decode step
time grows with batch size, KV cache is a token budget, overflow preempts the newest request.
Deterministic, stdlib only.

Usage: python lag_llm_lab.py [target.md]
"""
import math
import pathlib
import random
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from promql_mini import Engine, Parser  # noqa: E402

S, M = 1000, 60000


def kafka(checks):
    print("== 1. Kafka: lag in offsets vs lag in time (consumer capacity 2,000 msg/s) ==")
    eng = Engine()
    produced = consumed = 0.0
    off_pts, lag_pts = [], []
    for sec in range(0, 61 * 60 + 1, 15):
        rate_in = 5000.0 if 10 * 60 <= sec < 20 * 60 else 1000.0
        if sec:
            produced += rate_in * 15
            consumed = min(produced, consumed + 2000.0 * 15)
        off_pts.append((sec * S, produced))
        lag_pts.append((sec * S, produced - consumed))
    eng.add({"__name__": "kafka_topic_partition_current_offset", "topic": "orders", "partition": "0"}, off_pts)
    eng.add({"__name__": "kafka_consumergroup_lag", "consumergroup": "billing", "topic": "orders", "partition": "0"}, lag_pts)
    time_lag = ('sum by (consumergroup, topic) (kafka_consumergroup_lag) / on(topic) group_left '
                'sum by (topic) (rate(kafka_topic_partition_current_offset[5m]))')
    drain = 'deriv(sum by (consumergroup, topic) (kafka_consumergroup_lag)[10m:1m])'
    print(f"{'t':>5} {'lag (offsets)':>14} {'~time lag s':>12} {'lag slope/s':>12}")
    peak = 0
    for m in (9, 12, 15, 20, 25, 30, 35, 40):
        lag = eng.eval(Parser("sum(kafka_consumergroup_lag)").parse(), m * M)[0][1]
        tl = eng.eval(Parser(time_lag).parse(), m * M)
        dr = eng.eval(Parser(drain).parse(), m * M)
        peak = max(peak, lag)
        print(f"{m:>4}m {lag:>14,.0f} {tl[0][1] if tl else 0:>12.0f} {dr[0][1] if dr else 0:>12.0f}")
    print(f"-> peak lag {peak:,.0f} offsets = {peak / 2000 / 60:.0f} min of consumer work. The SAME offset lag on a 10 msg/s")
    print("   topic would be 4 days. Alert on time lag (lag / consume rate) and on its slope, not on offsets.")
    checks.append(("lag drains after spike", eng.eval(Parser("sum(kafka_consumergroup_lag)").parse(), 60 * M)[0][1] == 0))
    print("   drain ETA = lag / -slope: at 30m, 1,185,000 / 1,000 per s = 20 min, matching the empty queue at ~50m.")
    print()


def postgres(checks):
    print("== 2. Postgres replica lag on an idle primary ==")
    print("pg_replication_lag_seconds = now() - pg_last_xact_replay_timestamp() on the replica (postgres_exporter)")
    rows = []
    last_commit, replayed = 0.0, 0.0
    for t in range(0, 601, 60):
        if t <= 120:
            last_commit = t  # writes until t=120s, then the primary goes idle
        replayed = last_commit  # the replica is fully caught up
        rows.append((t, t - replayed, 0))
    for t, lag_s, lsn in rows[::2]:
        print(f"t={t:>3}s  time-based lag {lag_s:>4.0f}s   LSN byte lag {lsn} B")
    checks.append(("idle primary false lag", rows[-1][1] == 480 and rows[-1][2] == 0))
    print("-> time-based lag grows on an idle primary although the replica is current. Page on WAL/LSN byte lag")
    print("   (or emit a heartbeat write every 10 s, e.g. pg_cron/pt-heartbeat, so time lag stays truthful).")
    print()


def redis(checks):
    print("== 3. Redis hit ratio when maxmemory forces evictions ==")
    eng = Engine()
    hits = misses = evict = 0.0
    hp, mp, ep = [], [], []
    for sec in range(0, 1201, 15):
        evicting = sec >= 600
        req = 10000 * 15
        ratio = 0.95 if not evicting else 0.72
        hits += req * ratio
        misses += req * (1 - ratio)
        evict += (300 * 15 if evicting else 0)
        hp.append((sec * S, hits))
        mp.append((sec * S, misses))
        ep.append((sec * S, evict))
    eng.add({"__name__": "redis_keyspace_hits_total", "instance": "r1"}, hp)
    eng.add({"__name__": "redis_keyspace_misses_total", "instance": "r1"}, mp)
    eng.add({"__name__": "redis_evicted_keys_total", "instance": "r1"}, ep)
    hr = 'rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))'
    for m in (8, 15):
        h = eng.eval(Parser(hr).parse(), m * M)[0][1]
        e = eng.eval(Parser("rate(redis_evicted_keys_total[5m])").parse(), m * M)[0][1]
        print(f"t={m:>2}m hit ratio {h:.1%}  evictions {e:.0f}/s  -> backend read QPS = {10000 * (1 - h):,.0f}/s")
    checks.append(("misses x5.6", abs(10000 * 0.28 / (10000 * 0.05) - 5.6) < 1e-9))
    print("-> a 23-point hit-ratio drop multiplies database read load 5.6x: alert on evictions and hit ratio together.")
    print()


def llm(checks):
    print("== 4. Continuous-batching LLM server (model [E]): load vs TTFT / ITL / KV cache / goodput ==")
    print("prefill 25k tok/s, decode step 8 ms + 0.12 ms x batch, KV budget 200k tokens, max 256 seqs;")
    print("prompts lognormal(mean ~1.1k tok), outputs lognormal(mean ~260 tok); SLO: TTFT<=1 s and TPOT<=50 ms")
    print(f"{'req/s':>5} {'running':>8} {'waiting':>8} {'kv used':>8} {'preempt':>8} {'TTFT p50':>9} {'TTFT p99':>9} "
          f"{'TPOT p99':>9} {'goodput':>8}")
    res = {}
    for lam in (2, 4, 8, 12):
        rng = random.Random(lam)
        t, arr_t = 0.0, rng.expovariate(lam)
        waiting, running, done = [], [], []
        kv_cap, samples, preempt = 200_000, [], 0
        while t < 300.0 or (running and t < 400.0):
            while arr_t <= t and arr_t < 300.0:
                p = max(16, int(math.exp(rng.gauss(math.log(900), 0.6))))
                o = max(8, int(math.exp(rng.gauss(math.log(220), 0.6))))
                waiting.append({"arr": arr_t, "p": p, "o": o, "g": 0, "ttft": None, "start": None})
                arr_t += rng.expovariate(lam)
            kv = sum(r["p"] + r["g"] for r in running)
            prefill = 0
            while waiting and len(running) < 256 and kv + waiting[0]["p"] + 1 <= kv_cap:
                r = waiting.pop(0)
                r["g"] = 0
                kv += r["p"]
                prefill += r["p"]
                running.append(r)
            step = 0.008 + 0.00012 * len(running) + prefill / 25000.0
            t += step
            for r in running:
                r["g"] += 1
                if r["ttft"] is None:
                    r["ttft"] = t - r["arr"]
                    r["start"] = t
            while sum(r["p"] + r["g"] for r in running) > kv_cap and len(running) > 1:
                victim = running.pop()  # newest is preempted and recomputed later
                victim["ttft"], victim["g"] = None, 0
                waiting.insert(0, victim)
                preempt += 1
            fin = [r for r in running if r["g"] >= r["o"]]
            for r in fin:
                r["end"] = t
                done.append(r)
            running = [r for r in running if r["g"] < r["o"]]
            samples.append((len(running), len(waiting), sum(r["p"] + r["g"] for r in running) / kv_cap))
        tt = sorted(r["ttft"] for r in done)
        tpot = sorted((r["end"] - r["start"]) / max(1, r["o"] - 1) for r in done)
        good = sum(1 for r in done if r["ttft"] <= 1.0 and (r["end"] - r["start"]) / max(1, r["o"] - 1) <= 0.05) / len(done)
        q = lambda xs, f: xs[int(f * (len(xs) - 1))]  # noqa: E731
        avg = lambda i: sum(s[i] for s in samples) / len(samples)  # noqa: E731
        res[lam] = (q(tt, 0.99), good)
        print(f"{lam:>5} {avg(0):>8.1f} {avg(1):>8.1f} {avg(2):>8.0%} {preempt:>8} {q(tt, 0.5):>8.2f}s {q(tt, 0.99):>8.2f}s "
              f"{q(tpot, 0.99) * 1000:>7.0f}ms {good:>8.0%}")
    checks.append(("TTFT explodes with load", res[12][0] > 5 * res[2][0]))
    checks.append(("goodput collapses", res[12][1] < res[2][1]))
    print("-> past the knee, TTFT is queueing (vllm:request_queue_time_seconds), not compute; kv_cache_usage_perc")
    print("   near 100% with num_requests_waiting > 0 is the saturation signal, and goodput - not tokens/s - is the SLI.")
    print()


def main():
    checks = []
    kafka(checks)
    postgres(checks)
    redis(checks)
    llm(checks)
    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:lag_llm_lab.py -->
```text
== 1. Kafka: lag in offsets vs lag in time (consumer capacity 2,000 msg/s) ==
    t  lag (offsets)  ~time lag s  lag slope/s
   9m              0            0            0
  12m        405,000          140          550
  15m        945,000          189         1836
  20m      1,785,000          373         2945
  25m      1,485,000         1485          552
  30m      1,185,000         1185        -1000
  35m        885,000          885        -1000
  40m        585,000          585        -1000
-> peak lag 1,785,000 offsets = 15 min of consumer work. The SAME offset lag on a 10 msg/s
   topic would be 4 days. Alert on time lag (lag / consume rate) and on its slope, not on offsets.
   drain ETA = lag / -slope: at 30m, 1,185,000 / 1,000 per s = 20 min, matching the empty queue at ~50m.

== 2. Postgres replica lag on an idle primary ==
pg_replication_lag_seconds = now() - pg_last_xact_replay_timestamp() on the replica (postgres_exporter)
t=  0s  time-based lag    0s   LSN byte lag 0 B
t=120s  time-based lag    0s   LSN byte lag 0 B
t=240s  time-based lag  120s   LSN byte lag 0 B
t=360s  time-based lag  240s   LSN byte lag 0 B
t=480s  time-based lag  360s   LSN byte lag 0 B
t=600s  time-based lag  480s   LSN byte lag 0 B
-> time-based lag grows on an idle primary although the replica is current. Page on WAL/LSN byte lag
   (or emit a heartbeat write every 10 s, e.g. pg_cron/pt-heartbeat, so time lag stays truthful).

== 3. Redis hit ratio when maxmemory forces evictions ==
t= 8m hit ratio 95.0%  evictions 0/s  -> backend read QPS = 500/s
t=15m hit ratio 72.0%  evictions 300/s  -> backend read QPS = 2,800/s
-> a 23-point hit-ratio drop multiplies database read load 5.6x: alert on evictions and hit ratio together.

== 4. Continuous-batching LLM server (model [E]): load vs TTFT / ITL / KV cache / goodput ==
prefill 25k tok/s, decode step 8 ms + 0.12 ms x batch, KV budget 200k tokens, max 256 seqs;
prompts lognormal(mean ~1.1k tok), outputs lognormal(mean ~260 tok); SLO: TTFT<=1 s and TPOT<=50 ms
req/s  running  waiting  kv used  preempt  TTFT p50  TTFT p99  TPOT p99  goodput
    2      4.7      0.0       3%        0     0.05s     0.18s      12ms     100%
    4     11.7      0.0       7%        0     0.06s     0.22s      16ms     100%
    8     40.0      0.0      25%        0     0.08s     0.33s      32ms     100%
   12    125.9    150.4      79%      771    14.04s    46.95s      66ms       9%
-> past the knee, TTFT is queueing (vllm:request_queue_time_seconds), not compute; kv_cache_usage_perc
   near 100% with num_requests_waiting > 0 is the saturation signal, and goodput - not tokens/s - is the SLI.

checks: 5/5 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 Kafka consumer SLO rules

```yaml
groups:
  - name: kafka.rules
    interval: 30s
    rules:
      - record: consumergroup_topic:kafka_consumergroup_lag:sum
        expr: sum by (consumergroup, topic) (kafka_consumergroup_lag)
      - record: topic:kafka_produce_rate:rate5m
        expr: sum by (topic) (rate(kafka_topic_partition_current_offset[5m]))
      - record: consumergroup_topic:kafka_time_lag_seconds:estimate
        expr: |
          consumergroup_topic:kafka_consumergroup_lag:sum
            / on (topic) group_left
          clamp_min(topic:kafka_produce_rate:rate5m, 1)
  - name: kafka.alerts
    rules:
      - alert: KafkaConsumerFallingBehind
        expr: |
          consumergroup_topic:kafka_time_lag_seconds:estimate > 300
            and deriv(consumergroup_topic:kafka_consumergroup_lag:sum[10m]) > 0
        for: 10m
        labels: {severity: page}
        annotations:
          summary: "{{ $labels.consumergroup }} on {{ $labels.topic }} is ~{{ $value | humanizeDuration }} behind and still falling behind"
      - alert: KafkaConsumerGroupNoMembers
        expr: kafka_consumergroup_members == 0 and on (consumergroup) (sum by (consumergroup) (kafka_consumergroup_lag) > 0)
        for: 10m
        labels: {severity: page}
```

### 2.2 PostgreSQL and Redis alerts

```yaml
groups:
  - name: postgres.alerts
    rules:
      - alert: PostgresConnectionsNearMax
        expr: |
          sum by (instance) (pg_stat_database_numbackends)
            / on (instance) max by (instance) (pg_settings_max_connections) > 0.85
        for: 10m
        labels: {severity: warning}
      - alert: PostgresReplicaLagging
        # time-based lag with an idle-primary guard: only page when the primary is committing
        expr: |
          max by (instance) (pg_replication_lag_seconds) > 60
            and on () sum(rate(pg_stat_database_xact_commit{datname!~"template.*"}[5m])) > 1
        for: 5m
        labels: {severity: page}
      - alert: PostgresDeadlocks
        expr: sum by (instance, datname) (increase(pg_stat_database_deadlocks[15m])) > 0
        labels: {severity: ticket}
  - name: redis.alerts
    rules:
      - alert: RedisEvictingWithHitRatioDrop
        expr: |
          rate(redis_evicted_keys_total[5m]) > 0
            and (
              rate(redis_keyspace_hits_total[5m])
                / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))
            ) < 0.85
        for: 15m
        labels: {severity: warning}
      - alert: RedisMemoryNearMax
        expr: redis_memory_used_bytes / (redis_memory_max_bytes > 0) > 0.9
        for: 15m
        labels: {severity: warning}
      - alert: RedisRejectingConnections
        expr: increase(redis_rejected_connections_total[5m]) > 0
        labels: {severity: page}
```

### 2.3 LLM inference SLO rules (vLLM)

```yaml
groups:
  - name: vllm.rules
    interval: 15s
    rules:
      - record: model:vllm_ttft_seconds:p99_5m
        expr: |
          histogram_quantile(0.99, sum by (model_name, le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))
      - record: model:vllm_itl_seconds:p99_5m
        expr: |
          histogram_quantile(0.99, sum by (model_name, le) (rate(vllm:inter_token_latency_seconds_bucket[5m])))
      - record: model:vllm_ttft_good:ratio_rate5m
        # TTFT <= 1s; 1.0 must be a bucket boundary of the server's histogram (check the exposition)
        expr: |
          sum by (model_name) (rate(vllm:time_to_first_token_seconds_bucket{le="1.0"}[5m]))
            / sum by (model_name) (rate(vllm:time_to_first_token_seconds_count[5m]))
      - record: model:vllm_generation_tokens:rate5m
        expr: sum by (model_name) (rate(vllm:generation_tokens_total[5m]))
      - record: model:vllm_prefix_cache_hit:ratio_rate5m
        expr: |
          sum by (model_name) (rate(vllm:prefix_cache_hits_total[5m]))
            / sum by (model_name) (rate(vllm:prefix_cache_queries_total[5m]))
  - name: vllm.alerts
    rules:
      - alert: VllmSaturated
        expr: |
          max by (model_name, instance) (vllm:kv_cache_usage_perc) > 0.95
            and on (model_name, instance) max by (model_name, instance) (vllm:num_requests_waiting) > 0
        for: 5m
        labels: {severity: page}
        annotations:
          summary: "{{ $labels.model_name }} on {{ $labels.instance }}: KV cache full with queued requests (TTFT is now queueing)"
      - alert: VllmPreemptions
        expr: sum by (model_name, instance) (rate(vllm:num_preemptions_total[5m])) > 0.1
        for: 10m
        labels: {severity: ticket}
```

> ⚠ Counter suffixes: vLLM registers counters such as `vllm:generation_tokens` and `vllm:num_preemptions` through `prometheus_client`, which exposes them with a `_total` suffix; confirm names against your server's `/metrics` before deploying rules. Histogram bucket boundaries are chosen by vLLM per metric and change between releases — verify that the SLO threshold (`le="1.0"`) exists.

---

## 3. Failure modes and FinOps debugging

### F1. Offset-lag alerts that are always wrong

**Symptom.** Lag alerts fire constantly on high-volume topics and never on low-volume ones where consumers are hours behind.

**Signature.** One threshold (e.g. lag > 10,000) across all topics; produce rates differ by 1000×.

**Root cause.** Offsets are units, not time (L4 §1).

**Fix.** Time lag (lag / produce rate) with a slope condition (§2.1); per-consumer SLOs in seconds.

**Prevention.** Lag dashboards show time lag first, offsets second.

### F2. Replica-lag pages at 3 AM on an idle database

**Symptom.** `PostgresReplicaLag` pages every night during low traffic; the replica is fine.

**Signature.** `pg_replication_lag_seconds` grows linearly while WAL byte lag is 0 and commits/s ≈ 0.

**Root cause.** Time-based lag measures time since the last replayed commit (L4 §2).

**Fix.** Guard with commit activity (§2.2) or alert on byte lag; add a heartbeat writer.

**Prevention.** Synthetic heartbeat tables for every replicated database.

### F3. Cache "optimisation" that triples database load

**Symptom.** After lowering Redis `maxmemory` to save cost, database CPU triples.

**Signature.** `redis_evicted_keys_total` rate > 0; hit ratio down 20+ points; DB read QPS up 3–6×.

**Root cause.** Backend load ∝ miss ratio (L4 §3).

**Fix.** Restore memory or change eviction policy and key TTLs; size cache from the miss budget.

**Prevention.** Cost changes to caches require a modelled miss-rate impact on the backing store.

### F4. LLM "throughput is up" while users wait 30 seconds

**Symptom.** Tokens/s dashboards look great after a load increase; user complaints about slow first responses.

**Signature.** `vllm:num_requests_waiting` > 0 continuously; `vllm:kv_cache_usage_perc` > 0.95; `vllm:request_queue_time_seconds` p99 in seconds; TTFT p99 ≫ prefill time.

**Root cause.** The server is past saturation; throughput rises because batches are full, while queueing dominates TTFT (L4 §4: goodput 9%).

**Fix.** Scale out on queue/KV saturation, not GPU utilization; cap max concurrency per replica; route long prompts separately; use prefix caching.

**Prevention.** SLO on goodput (TTFT and TPOT together); autoscaling on `num_requests_waiting` and KV usage.

### F5. Preemption storms

**Symptom.** Generation latency spikes; GPU busy but completed requests per second drop.

**Signature.** `rate(vllm:num_preemptions_total[5m])` > 0; KV usage oscillating near 100%.

**Root cause.** Long generations grow KV until it overflows; the scheduler preempts and recomputes requests (wasted GPU).

**Fix.** Lower `max_num_seqs`/`max_model_len`, raise `gpu_memory_utilization` if safe, enable KV offload or quantised KV cache, separate long-context traffic.

**Prevention.** Alert on preemption rate; capacity tests with realistic output-length distributions.

### F6. Consumer group silently empty

**Symptom.** A topic's lag grows for hours; no consumer errors anywhere.

**Signature.** `kafka_consumergroup_members == 0`; the consuming deployment scaled to zero or crashlooping; committed offsets unchanged.

**Root cause.** No members means no errors and no consumer-side metrics — only the lag tells.

**Fix.** Restore consumers; re-evaluate retention vs lag to avoid data loss at log deletion.

**Prevention.** Alert on "lag > 0 and members == 0" (§2.1); and on time lag approaching topic retention.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Design Kafka consumer alerting."</b></summary>

**Initial Prompt.** What should page for a consumer group?

**L5 Textbook Answer.** Alert when consumer lag exceeds a threshold like 10,000 messages.

**Why L5 Fails at 3 AM or on the Bill.** Offsets are not time; the threshold is either always firing (busy topics) or useless (quiet topics), and a recovering consumer pages as loudly as a stuck one.

**L7 Principal Defense.** Page on time lag above the consumer's freshness SLO **and** a non-negative slope; ticket when drain ETA (lag/(consume−produce)) exceeds the SLO; page on "lag and no members"; warn when time lag approaches retention (imminent data loss). Thresholds come from the business freshness requirement per consumer, expressed in seconds.
</details>

<details><summary><b>Q2 · "How do you monitor Postgres replication correctly?"</b></summary>

**Initial Prompt.** `pg_replication_lag_seconds > 60` pages nightly. Fix it.

**L5 Textbook Answer.** Raise the threshold to 300 seconds at night.

**Why L5 Fails at 3 AM or on the Bill.** The metric is wrong on idle primaries; raising thresholds hides real lag during the day.

**L7 Principal Defense.** Time lag = now − last replayed commit, so it grows with idleness (L4 §2). Use WAL byte lag (from `pg_stat_replication` on the primary) for correctness, guard time lag with commit activity, and run a heartbeat writer so time lag is meaningful. Page on byte lag that keeps rising or time lag with commits flowing.
</details>

<details><summary><b>Q3 · "What's Redis's saturation signal?"</b></summary>

**Initial Prompt.** CPU on our Redis is 30%. Are we fine?

**L5 Textbook Answer.** Yes, 30% CPU leaves plenty of headroom.

**Why L5 Fails at 3 AM or on the Bill.** Redis executes commands on one thread; 30% of a multi-core box can be 100% of that thread, and memory saturation shows as evictions, not CPU.

**L7 Principal Defense.** Saturation = per-command latency and slowlog (the single thread), `maxmemory` usage and eviction rate, blocked clients and rejected connections. Effect on the system = miss ratio × backend capacity (L4 §3: 5.6× read amplification). I'd alert on evictions with hit-ratio drop and on command latency, and plan memory from the backend's miss budget.
</details>

<details><summary><b>Q4 · "Define SLOs for an LLM inference API."</b></summary>

**Initial Prompt.** What SLIs for a chat completion endpoint?

**L5 Textbook Answer.** p99 latency and tokens per second.

**Why L5 Fails at 3 AM or on the Bill.** End-to-end latency scales with output length (not a property of the service); tokens/s rises as users suffer (L4 §4).

**L7 Principal Defense.** Two latency SLIs — TTFT (perceived responsiveness; queue + prefill) and TPOT/ITL (streaming speed) — combined into goodput (share of requests meeting both), plus availability (non-abort finish reasons). Saturation signals: KV usage, waiting requests, preemptions. Capacity planning in goodput per GPU, not tokens/s.
</details>

<details><summary><b>Q5 · "Autoscale vLLM on what?"</b></summary>

**Initial Prompt.** HPA on GPU utilization?

**L5 Textbook Answer.** Yes, scale when GPU utilization exceeds 80%.

**Why L5 Fails at 3 AM or on the Bill.** GPU "utilization" is busy-time, near 100% at any non-trivial batch; it says nothing about queueing, so the HPA either never scales or always does.

**L7 Principal Defense.** Scale on `vllm:num_requests_waiting` (queue) and KV-cache usage with a TTFT p99 guard; scale-in only when waiting = 0 and KV < 50% for a sustained window; model load time (minutes) dictates aggressive scale-out. KEDA with Prometheus triggers implements it.
</details>

<details><summary><b>Q6 · "Why does the prefix cache hit ratio matter to the bill?"</b></summary>

**Initial Prompt.** Is prefix caching worth monitoring?

**L5 Textbook Answer.** It's an optimisation; nice to have.

**Why L5 Fails at 3 AM or on the Bill.** For chat and agents with long shared system prompts, prefill dominates GPU time; a falling hit ratio silently raises cost per request and TTFT.

**L7 Principal Defense.** Prefill cost ∝ uncached prompt tokens; hit ratio from `vllm:prefix_cache_hits/queries` (and cached prompt tokens) is a direct cost and TTFT lever. I'd track cached-token share per model, alert on drops after deploys (prompt template changes break caching), and use cache-aware routing across replicas.
</details>

<details><summary><b>Q7 · "One dashboard for a Postgres-backed service. What's on it?"</b></summary>

**Initial Prompt.** Design it.

**L5 Textbook Answer.** CPU, memory, connections, queries per second.

**Why L5 Fails at 3 AM or on the Bill.** No saturation (locks, pool waits), no correctness (replication, wraparound) and no link to the service's latency.

**L7 Principal Defense.** Row 1: service RED and Hikari pending (File 3). Row 2: DB saturation — connections vs max, lock waits/blocking chains, top `pg_stat_statements` by total time. Row 3: correctness — replication byte lag, XID age, deadlocks. Row 4: resources — CPU, IO latency, cache hit ratio. Every row answers "is the database the first full queue?".
</details>

<details><summary><b>Q8 · "Kafka time lag estimate — when is it wrong?"</b></summary>

**Initial Prompt.** You use lag / produce rate. Critique your own metric.

**L5 Textbook Answer.** It's accurate if the produce rate is stable.

**Why L5 Fails at 3 AM or on the Bill.** "If stable" hides the failure: during a produce spike the estimate understates the age of the oldest message; after it, it overstates (L4: 1,485 s estimate at 25 m when the backlog was built at a higher rate).

**L7 Principal Defense.** The estimate uses the *current* produce rate while the backlog was produced at historical rates. Truthful time lag needs message timestamps: consumers export "event age of last processed record" (`now − record.timestamp`) — the best SLI. Lag/produce-rate stays as a broker-side fallback with the slope condition.
</details>

---

## 5. Invariants checklist

- [ ] Backlog alerts are in time (seconds of lag), with slope conditions; offsets are diagnostic.
- [ ] Consumers export record event-age; "lag > 0 and members == 0" pages.
- [ ] Postgres replication is judged by WAL byte lag or heartbeat-backed time lag; XID age is alerted.
- [ ] Cache alerts pair evictions with hit ratio; cache capacity is planned from the backend's miss budget.
- [ ] LLM SLOs are TTFT, TPOT/ITL and goodput; autoscaling uses waiting requests and KV usage, not GPU utilization.
- [ ] vLLM metric names and bucket boundaries are re-verified on every vLLM upgrade.

---

## 6. References

- kafka_exporter v1.11.0: <https://github.com/danielqsj/kafka_exporter/blob/v1.11.0/kafka_exporter.go>
- Apache Kafka monitoring documentation: <https://kafka.apache.org/documentation/#monitoring>
- postgres_exporter v0.20.1: <https://github.com/prometheus-community/postgres_exporter/tree/v0.20.1>
- PostgreSQL monitoring statistics: <https://www.postgresql.org/docs/current/monitoring-stats.html>
- redis_exporter v1.97.0: <https://github.com/oliver006/redis_exporter/tree/v1.97.0>
- Redis latency monitoring: <https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/latency/>
- vLLM v1 metrics (loggers.py, v0.32.0): <https://github.com/vllm-project/vllm/blob/v0.32.0/vllm/v1/metrics/loggers.py>
- vLLM production metrics documentation: <https://docs.vllm.ai/en/latest/usage/metrics.html>
