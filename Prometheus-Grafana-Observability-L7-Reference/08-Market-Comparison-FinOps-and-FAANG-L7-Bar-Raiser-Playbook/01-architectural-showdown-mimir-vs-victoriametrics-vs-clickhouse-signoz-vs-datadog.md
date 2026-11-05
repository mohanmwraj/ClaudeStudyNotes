# 01 · Architectural Showdown: Mimir vs VictoriaMetrics vs ClickHouse/SigNoz vs Datadog

> **Folder 08 — Market Comparison, FinOps and the FAANG L7 Bar-Raiser Playbook · File 1 of 3.**
> Versions current on 2026-11-05:
> - **Grafana Mimir 3.2.4** (with Loki 3.7.9, Tempo 3.1.1)
> - **VictoriaMetrics v1.155.0**
> - **ClickHouse 26.10** (stable; 26.3 LTS), **SigNoz v0.149.0**
> - **Datadog** and **Grafana Cloud**: public list prices as published on 2026-11-05
>
> Labels: **[D]** documented / read in pinned source or vendor page · **[M]** measured · **[E]** model · **⚠** version- or price-sensitive.

| Listing | What it proves | Runtime |
|---|---|---|
| L1 `tco_showdown_lab.py` | A transparent monthly TCO model for one reference workload: 400 hosts, 12M active series, 3 TB/day logs, 40k spans/s. **Datadog list.** $905k if everything is sent, of which 66% is custom metrics; $335k curated, of which 76% is log indexing; $119k when also indexing 15% of logs. **Grafana Cloud.** $132k for Pro; $90k at the $3/1k enterprise floor. **Self-hosted LGTM.** $59k, of which 74% is people; infrastructure alone is $15k. **Storage.** Block storage with RF=2 only beats Mimir's S3 at 2 B/sample below **0.29 B/sample**. **Logs.** 30-day log storage costs hundreds of dollars on any engine | <1 s |

**Verification.**
- **Prices.** Read from `datadoghq.com/pricing/list` (US, billed annually) and `grafana.com/pricing` on 2026-11-05. The Datadog custom-metric allotment (Pro 100/host) comes from Datadog's billing docs. AWS list prices are us-east-1 on-demand [D] ⚠.
- **Self-hosted sizing.** Uses Mimir 3.2.4's `planning-capacity.md` and Loki 3.7.9's sizing table [D]. Tempo compute, compression ratios, cross-AZ bytes and people cost are stated assumptions [E].
- **Scope.** This is a model to argue with, not a quote. Negotiated discounts, commitments and allotments change every SaaS number.

---

## 0. Orientation

**What this file answers.**
- How the main architectures differ *mechanically*: write path, storage medium, replication, query engine and failure isolation.
- What that does to reliability and cost.
- How to run a defensible build-vs-buy decision with numbers.

**Four architectures, one diagram.**

```text
 Mimir 3 (ingest storage)            VictoriaMetrics cluster             ClickHouse / SigNoz                 Datadog (SaaS)
 ───────────────────────            ───────────────────────            ───────────────────               ──────────────
 agents ─RW/OTLP─► distributor       agents ─RW─► vminsert (stateless)   OTel Collector ─► ClickHouse       Datadog Agent / OTel
   │ shard by FNV-1(tenant,labels)     │ consistent hash of series        │ MergeTree tables (columnar)       ─► vendor intake
   ▼                                   ▼ replicationFactor copies         │ ZSTD, LowCardinality, TTL moves     │ per-host, per-custom-
 Kafka (durable log, replication)    vmstorage (stateful, LOCAL disk,     │ shards × replicas (Keeper)           │ metric, per-GB/event
   ▼ one ingester per partition/zone   own merge-tree, no object store)   ▼ hot disk → S3 tiering              ▼ billing
 ingesters (13h) ─► S3 blocks        vmselect (stateless, fan-out to     SQL (and SigNoz query builder)      proprietary storage +
 compactor (vertical dedup)            ALL vmstorage, dedups replicas)   traces/logs/metrics in one store    query; Metrics without
 store-gateway ◄─ querier (MQE)      MetricsQL (PromQL superset)         ⚠ metrics = wide tables              Limits, Flex Logs
 PromQL, multi-tenant, AGPL-3.0      Apache-2.0 (+ enterprise features)  Apache-2.0 (CH) / SigNoz OSS + EE   closed
```

---

## 1. First principles: the mechanics that decide reliability and cost

### 1.1 Where durability lives [D]

| | Commit point of a write | Durable copy | Replication unit |
|---|---|---|---|
| **Mimir 3 (ingest storage)** | Kafka ack ("the write path ends at Kafka") | Kafka log, then S3 blocks | Kafka replication; ingesters per zone for reads |
| **Mimir (classic) / Cortex / Thanos Receive** | Quorum of ingesters/receivers (2 of 3) | Ingester WAL on PVC, then S3 | Series replicated RF=3 in ingesters |
| **VictoriaMetrics cluster** | vminsert writes to `replicationFactor` vmstorage nodes | Local disk of each vmstorage | Whole series replicated on block storage |
| **ClickHouse** | Insert to a shard replica; replicated via Keeper log | Local parts, optionally tiered to S3 | ReplicatedMergeTree per shard |
| **Datadog** | Vendor intake | Vendor | Vendor |

**Storage cost as a function of medium, replication and compression** (L1 §3):

```text
 $ / sample-month  =  bytes_per_sample × replication_factor × $/GB-month(medium)
 Mimir (S3):            2.0 B × 1 (S3 is internally durable) × $0.023  = $0.046 per G samples
 block store, RF=2:     b   × 2                             × $0.080  = $0.160·b
 break-even:            0.160·b = 0.046  →  b ≈ 0.29 B/sample
            ┌────────────────────────── cheaper on block storage ──┬── cheaper on S3 at 2 B/sample ──────►
 b (B/sample) 0.1          0.2        0.29                  0.6                 1.0                1.3
                                       ▲ break-even (RF=2)   ▲ typical vendor claims sit to the right
```

**Why it matters.**
- **Object storage is ~3.5× cheaper per GB than gp3 and needs no replication.** S3 is durable by design.
- **Block storage gives faster queries** but must be replicated by the database.
- L1 §3 turns this into a break-even. VictoriaMetrics with `replicationFactor=2` on gp3 costs less than Mimir's S3 storage (at 2 B/sample, the Mimir guide's assumption) only if it stores below **0.29 B/sample**. At 0.6 B/sample × RF2 it is $1,311 vs $628 per month.
- **Compression claims are not cost claims.** The medium and the replication factor dominate.

### 1.2 Query path and its failure isolation [D]

**Mimir.**
- Query-frontend splitting (24h) and sharding (16) with a results cache.
- The MQE streaming engine.
- Store-gateways with lazy index-headers.
- Read and write paths are isolated by Kafka. A query storm cannot fail writes (Folder 06 file 02).
- Shuffle sharding bounds a tenant's blast radius.

**VictoriaMetrics.**
- `vmselect` fans out to **all** `vmstorage` nodes for every query and merges the results.
- Simple and fast at moderate scale, but every query touches every storage node.
- A heavy query affects all of them, which is why VM exposes per-query memory and concurrency limits.
- MetricsQL is a PromQL superset with deliberate differences ⚠. For example, `rate`/`increase` do not extrapolate and use the last sample before the window. Dashboards ported 1:1 can show slightly different numbers. Verify on the panels you depend on (Folder 02 file 01 for Prometheus's exact extrapolation).

**ClickHouse.**
- A SQL query over columnar parts with primary-key (sort key) pruning, skip indexes and partition pruning.
- Excellent for high-cardinality, wide events (logs and traces with many attributes) and ad-hoc aggregation.
- Weaker for the Prometheus-style "millions of independent series, `rate()` per series" workload unless modelled carefully.
- Metrics in ClickHouse-based stacks are usually wide tables with attribute maps ⚠.

**Datadog.**
- Opaque. Performance is the vendor's problem, and cost is yours.
- Query-time features (Metrics without Limits, percentiles on distributions) change what you pay for, not what you send.

### 1.3 Cardinality: how each system fails [D][E]

| System | What happens at a cardinality explosion |
|---|---|
| Prometheus | Head series and postings grow until OOM. `sample_limit` fails scrapes loudly (Folder 01 file 02, Folder 07 file 02) |
| Mimir | Per-tenant `max_global_series_per_user` rejects new series (`cortex_discarded_samples_total{reason="per_user_series_limit"}`). The tenant is degraded; the cluster survives |
| VictoriaMetrics | Per-vmstorage cardinality limiters (`-storage.maxHourlySeries`, `-storage.maxDailySeries`) drop new series. Limits are per node, ×N cluster-wide |
| ClickHouse | No series concept. Cardinality costs **part count, sort-key effectiveness and memory in GROUP BY**. It degrades gradually rather than rejecting |
| Datadog | Accepts and **bills**. Every unique tag combination is a custom metric at $5 per 100/month above the allotment |

**The FinOps consequence.**
- On SaaS, cardinality is a bill.
- On self-hosted Mimir or VictoriaMetrics, cardinality is capacity (RAM per series).
- On ClickHouse, cardinality is query cost.
- The control loop differs, so the governance does too (File 02).

### 1.4 What the TCO model says [M][E]

L1's reference workload: 400 hosts, 12M active series at 30 s (400k samples/s) with 13-month retention, 3 TB/day logs, 40k spans/s with 10% kept.

| Option | Monthly | Dominant term |
|---|---|---|
| Datadog, everything sent | **$905k** | custom metrics 66% |
| Datadog, curated to 600k custom metrics | $335k | indexed logs 76% |
| Datadog, curated + 15% of logs indexed (rest Flex/archive) | $119k | — |
| Grafana Cloud Pro (list) | $132k | metrics 59% |
| Grafana Cloud at $3/1k (enterprise floor) | $90k | logs 55% |
| Self-hosted LGTM (2 SRE FTE) | **$59k** | people 74% |
| Self-hosted, infrastructure only | $15k | compute |

**Sensitivities** (L1 §2):
- Doubling series adds **$600k** on Datadog, **$78k** on Grafana Cloud Pro and **$8k** on self-hosted.
- Self-hosting stays cheaper than Grafana Cloud Pro list until **5.3 FTE** of operational effort.

**Reading these numbers.**
- **SaaS bills scale with volume, and self-hosted bills scale with people.** At this size, governance (sending less) is worth more than platform choice.
- **"Datadog, everything sent" is not a real deployment.** It is the number that shows why Datadog customers curate custom metrics aggressively, and why OSS migrations get approved.
- **Self-hosting has a staffing floor.** Below a few million series, 2 FTE costs more than any SaaS bill. Above tens of millions, infrastructure grows sublinearly while SaaS grows linearly.

### 1.5 Decision matrix [D][E]

| Criterion | Mimir 3 | VictoriaMetrics | ClickHouse/SigNoz | Datadog |
|---|---|---|---|---|
| PromQL fidelity | Native (MQE) | MetricsQL (superset, small semantic differences ⚠) | Translated/PromQL-ish via SigNoz ⚠ | Own language; OpenMetrics ingest |
| Multi-tenancy and limits | Strong (per-tenant limits, shuffle sharding) | Cluster: accountID/projectID tenancy; limits per node | Database/row-level; DIY | Org-level |
| Long retention cost | S3 + compactor (cheap) | Local disk × RF (enterprise: downsampling ⚠) | S3 tiering via storage policies | Per-product retention pricing |
| Logs and traces | Loki/Tempo (separate systems) | VictoriaLogs/VictoriaTraces (separate products ⚠) | **One store** for all signals | One platform |
| Operational complexity | High: Kafka, many components | Low–medium: 3 binaries | Medium–high: Keeper, shards, schema design | None (yours is cost governance) |
| Failure isolation | Excellent (Kafka-decoupled writes) | Good; vmselect fans out to all nodes | Depends on cluster layout | Vendor |
| Lock-in | Low (OSS, Prometheus/OTLP APIs) | Low | Low (OTel ingest) | High (agent, query language, dashboards) |

<!-- listing:tco_showdown_lab.py -->
```python
"""tco_showdown_lab.py - a transparent monthly TCO model for one reference workload on four platforms:
Datadog (list price), Grafana Cloud Pro (list price), self-hosted LGTM on AWS (Mimir/Loki/Tempo sized from
the vendors' own capacity guides), and the storage economics of VictoriaMetrics and ClickHouse-style
columnar stores.

Every price and sizing rule is a named constant with its source; nothing is hidden in the arithmetic.
Prices were read from the vendors' public pages on 2026-11-05 (US, billed annually) and WILL drift:
  Datadog list page (datadoghq.com/pricing/list): Infrastructure Pro $15/host; custom metrics $5 per 100;
    APM $31/APM host; APM ingestion $0.10/GB; indexed spans (15-day) $1.70 per 1M; log ingestion
    $0.10/GB; indexed logs (15-day) $1.70 per 1M events. Allotment: Pro includes 100 indexed custom
    metrics per host (docs.datadoghq.com billing/custom_metrics).
  Grafana Cloud Pro (grafana.com/pricing): metrics from $6.50 per 1k active series (Enterprise "as low
    as $3" with a $25k/yr minimum); logs/traces from $0.05 process + $0.40 write + $0.10 retain per GB.
  AWS us-east-1 on-demand: r7i.xlarge (4 vCPU, 32 GiB) $0.2646/h; S3 Standard $0.023/GB-month;
    gp3 $0.08/GB-month; inter-AZ transfer $0.01/GB each way.
Sizing: Mimir 3.2.4 planning-capacity.md; Loki 3.7.9 setup/size table (<3 TB/day row).
Usage: python tco_showdown_lab.py [target.md]
"""
import math
import sys

HOURS = 730
# ---- reference workload (inputs) --------------------------------------------------------------
W = dict(hosts=400, apm_hosts=400, series=12_000_000, scrape_s=30, metric_retention_days=395,
         logs_gb_day=3000, log_line_bytes=600, log_index_days=15, spans_per_s=40_000, span_bytes=700,
         trace_keep=0.10, trace_retention_days=30)
# ---- prices --------------------------------------------------------------------------------------
DD = dict(infra_pro=15.0, cm_per_100=5.0, cm_allot_per_host=100, apm_host=31.0, apm_gb=0.10,
          spans_15d_per_m=1.70, log_gb=0.10, logs_15d_per_m=1.70)
GC = dict(per_1k_series=6.50, per_1k_series_ent=3.00, gb_all_in=0.05 + 0.40 + 0.10, platform=19.0)
AWS = dict(r7i_xlarge_h=0.2646, vcpu=4, mem_gib=32, s3_gb=0.023, gp3_gb=0.08, xaz_gb=0.02)


def nodes(cores, mem_gib):
    return max(math.ceil(cores / AWS["vcpu"]), math.ceil(mem_gib / AWS["mem_gib"]))


def datadog(w, series_sent=None):
    s = w["series"] if series_sent is None else series_sent
    lines = w["logs_gb_day"] * 1e9 / w["log_line_bytes"] * 30
    spans_m = w["spans_per_s"] * 86400 * 30
    c = {
        "infrastructure (Pro)": w["hosts"] * DD["infra_pro"],
        "custom metrics": max(0, s - DD["cm_allot_per_host"] * w["hosts"]) / 100 * DD["cm_per_100"],
        "logs ingest": w["logs_gb_day"] * 30 * DD["log_gb"],
        "logs indexed (15d, all)": lines / 1e6 * DD["logs_15d_per_m"],
        "APM hosts": w["apm_hosts"] * DD["apm_host"],
        "APM ingest": spans_m * w["span_bytes"] / 1e9 * DD["apm_gb"],
        "indexed spans (15d, kept)": spans_m * w["trace_keep"] / 1e6 * DD["spans_15d_per_m"],
    }
    return c


def grafana_cloud(w, enterprise=False):
    kept_gb = w["spans_per_s"] * 86400 * 30 * w["trace_keep"] * w["span_bytes"] / 1e9
    return {
        "metrics": w["series"] / 1000 * (GC["per_1k_series_ent"] if enterprise else GC["per_1k_series"]),
        "logs (process+write+retain 30d)": w["logs_gb_day"] * 30 * GC["gb_all_in"],
        "traces (kept, 30d)": kept_gb * GC["gb_all_in"],
        "platform fee": GC["platform"],
    }


def self_hosted(w, sre_fte=2.0, fte_month=22_000):
    samples_s = w["series"] / w["scrape_s"]
    mem_series = w["series"] * 3                                    # RF=3 in ingesters
    mimir = {
        "distributor": (samples_s / 25_000, samples_s / 25_000),
        "ingester": (mem_series / 300_000, mem_series / 300_000 * 2.5 * 1.5),
        "querier (200 qps)": (200 / 10, 200 / 10 * 1.5),
        "store-gateway (200 qps)": (200 / 10, 200 / 10 * 1.5),
        "frontend+scheduler": (2, 4),
        "compactor": (max(1, math.ceil(w["series"] / 20e6)), 4 * max(1, math.ceil(w["series"] / 20e6))),
    }
    cores = sum(c for c, _ in mimir.values())
    mem = sum(m for _, m in mimir.values())
    mimir_nodes = nodes(cores, mem)
    mimir_disk_gb = mem_series / 300_000 * 5 * 1.5 + w["series"] / 1e6 * 13 * 1.5 + 300
    mimir_s3_gb = w["series"] * 86400 / w["scrape_s"] * 2 * w["metric_retention_days"] / 1e9   # 2 B/sample (guide)
    loki_nodes = nodes(38, 59)                                       # <3 TB/day table totals
    loki_s3_gb = w["logs_gb_day"] / 8 * 30                           # ~8x chunk compression [E]
    kept_gb_day = w["spans_per_s"] * 86400 * w["trace_keep"] * w["span_bytes"] / 1e9
    tempo_nodes = nodes(24, 96)                                      # [E] no official table; measured guess
    tempo_s3_gb = kept_gb_day / 3 * w["trace_retention_days"]        # ~3x parquet compression [E]
    kafka_nodes = 6                                                  # 3 brokers x r7i.2xlarge-equivalent [E]
    xaz_gb = samples_s * 20 * 2 * 86400 * 30 / 1e9                   # 2 cross-AZ copies x ~20 B/sample [E]
    all_nodes = mimir_nodes + loki_nodes + tempo_nodes + kafka_nodes
    c = {
        f"compute ({all_nodes} r7i.xlarge-eq: Mimir {mimir_nodes}, Loki {loki_nodes}, Tempo {tempo_nodes}, Kafka {kafka_nodes})":
            all_nodes * AWS["r7i_xlarge_h"] * HOURS,
        "block storage (ingester WAL/TSDB, store-gateway, Kafka)": (mimir_disk_gb + 3 * 2000) * AWS["gp3_gb"],
        "object storage (metrics 13 mo, logs 30d, traces 30d)": (mimir_s3_gb + loki_s3_gb + tempo_s3_gb) * AWS["s3_gb"],
        "cross-AZ replication traffic": xaz_gb * AWS["xaz_gb"],
        f"people ({sre_fte} SRE FTE)": sre_fte * fte_month,
    }
    detail = dict(samples_s=samples_s, mimir_cores=cores, mimir_mem=mem, mimir_s3_tb=mimir_s3_gb / 1e3)
    return c, detail


def show(name, costs):
    total = sum(costs.values())
    print(f"{name}: ${total:,.0f}/month")
    for k, v in sorted(costs.items(), key=lambda x: -x[1]):
        print(f"    {k:<86} ${v:>11,.0f}  {v / total:>5.1%}")
    return total


def main():
    checks = []
    w = W
    print("== Reference workload ==")
    print(f"{w['hosts']} hosts, {w['series'] / 1e6:.0f}M active series @ {w['scrape_s']}s ({w['series'] / w['scrape_s']:,.0f} samples/s), "
          f"13-month metric retention; {w['logs_gb_day'] / 1e3:.0f} TB/day logs; {w['spans_per_s']:,} spans/s, "
          f"{w['trace_keep']:.0%} kept after tail sampling")
    print()

    print("== 1. Monthly cost by platform (list prices 2026-11-05; model, not a quote) ==")
    dd = datadog(w)
    t_dd = show("Datadog, everything sent", dd)
    dd_cur = datadog(w, series_sent=600_000)
    t_dd_cur = show("Datadog, curated: 600k custom metrics (5% of series)", dd_cur)
    t_gc = show("Grafana Cloud Pro", grafana_cloud(w))
    t_gce = show("Grafana Cloud at the $3/1k enterprise floor", grafana_cloud(w, enterprise=True))
    sh, det = self_hosted(w)
    t_sh = show("Self-hosted LGTM on AWS", sh)
    print(f"  Mimir sizing from the 3.2.4 guide: {det['samples_s']:,.0f} samples/s, {det['mimir_cores']:.0f} cores, "
          f"{det['mimir_mem']:,.0f} GB RAM (incl. +50% headroom on memory), {det['mimir_s3_tb']:.1f} TB in S3 at 2 B/sample")
    checks.append(("custom metrics dominate DD", dd["custom metrics"] / t_dd > 0.6))
    checks.append(("logs indexing dominates curated DD", max(dd_cur, key=dd_cur.get) == "logs indexed (15d, all)"))
    checks.append(("people dominate self-hosted", max(sh, key=sh.get).startswith("people")))
    print()

    print("== 2. Where each model is sensitive ==")
    base = t_gc
    w2 = dict(w, series=w["series"] * 2)
    print(f"double the series: Datadog +${datadog(w2)['custom metrics'] - dd['custom metrics']:,.0f}, "
          f"Grafana Cloud +${grafana_cloud(w2)['metrics'] - grafana_cloud(w)['metrics']:,.0f}, self-hosted "
          f"+${sum(self_hosted(w2)[0].values()) - t_sh:,.0f}")
    w3 = dict(w, logs_gb_day=w["logs_gb_day"] / 2)
    print(f"halve log volume: Datadog -${t_dd - sum(datadog(w3).values()):,.0f}, Grafana Cloud "
          f"-${base - sum(grafana_cloud(w3).values()):,.0f}")
    idx_share = 0.15
    dd_idx = dict(dd_cur)
    dd_idx["logs indexed (15d, all)"] *= idx_share
    print(f"Datadog curated + index only {idx_share:.0%} of logs (rest to archive/Flex): ${sum(dd_idx.values()):,.0f}/month "
          f"(from ${t_dd_cur:,.0f})")
    sh0, _ = self_hosted(w, sre_fte=0)
    print(f"self-hosted infrastructure alone (no people): ${sum(sh0.values()):,.0f}; break-even FTEs vs Grafana Cloud Pro: "
          f"{(t_gc - sum(sh0.values())) / 22_000:.1f}")
    checks.append(("ordering", t_dd > t_dd_cur and t_gc > t_gce))
    print()

    print("== 3. Storage medium vs compression: when does better compression on block storage win? ==")
    for rf in (1, 2):
        b = 2.0 * AWS["s3_gb"] / (rf * AWS["gp3_gb"])
        print(f"block storage with replicationFactor={rf} matches Mimir's S3 cost at 2 B/sample only below "
              f"{b:.2f} B/sample")
    days, samples_day = w["metric_retention_days"], w["series"] * 86400 / w["scrape_s"]
    for bps, rf in ((0.6, 2), (1.0, 2), (0.6, 1)):
        gb = samples_day * bps * days / 1e9 * rf
        print(f"  {bps} B/sample x RF{rf} on gp3: {gb / 1e3:,.1f} TB -> ${gb * AWS['gp3_gb']:,.0f}/month   vs   Mimir 2 B/sample on S3: "
              f"${samples_day * 2 * days / 1e9 * AWS['s3_gb']:,.0f}/month")
    lin = 0.29
    checks.append(("break-even formula", abs(2.0 * AWS["s3_gb"] / (2 * AWS["gp3_gb"]) - 0.2875) < 1e-9 and lin > 0))
    print("-> compression ratios alone don't decide storage cost: the medium (object vs replicated block")
    print("   storage) and the replication factor do. Compare $/sample-retained, measured on YOUR data.")
    print()

    print("== 4. Columnar logs (ClickHouse/SigNoz-style) vs Loki chunks: storage only ==")
    for ratio, name in ((8, "Loki chunks (gzip/snappy) ~8x [E]"), (15, "ClickHouse ZSTD + LowCardinality ~15x [E]")):
        gb = w["logs_gb_day"] / ratio * 30
        print(f"  {name:<44} 30 days: {gb / 1e3:,.1f} TB -> S3 ${gb * AWS['s3_gb']:,.0f}, gp3 ${gb * AWS['gp3_gb']:,.0f}")
    print("-> at 3 TB/day, 30-day log storage costs hundreds to low thousands of dollars on any engine; the")
    print("   bill is compute for queries and, on SaaS, per-GB/per-event pricing. Index less, not compress more.")
    print()

    failed = [n for n, ok in checks if not ok]
    print(f"checks: {len(checks) - len(failed)}/{len(checks)} passed")
    print("verdict: OK" if not failed else f"verdict: FAIL {failed}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
```

<!-- output:tco_showdown_lab.py -->
```text
== Reference workload ==
400 hosts, 12M active series @ 30s (400,000 samples/s), 13-month metric retention; 3 TB/day logs; 40,000 spans/s, 10% kept after tail sampling

== 1. Monthly cost by platform (list prices 2026-11-05; model, not a quote) ==
Datadog, everything sent: $905,283/month
    custom metrics                                                                         $    598,000  66.1%
    logs indexed (15d, all)                                                                $    255,000  28.2%
    indexed spans (15d, kept)                                                              $     17,626   1.9%
    APM hosts                                                                              $     12,400   1.4%
    logs ingest                                                                            $      9,000   1.0%
    APM ingest                                                                             $      7,258   0.8%
    infrastructure (Pro)                                                                   $      6,000   0.7%
Datadog, curated: 600k custom metrics (5% of series): $335,283/month
    logs indexed (15d, all)                                                                $    255,000  76.1%
    custom metrics                                                                         $     28,000   8.4%
    indexed spans (15d, kept)                                                              $     17,626   5.3%
    APM hosts                                                                              $     12,400   3.7%
    logs ingest                                                                            $      9,000   2.7%
    APM ingest                                                                             $      7,258   2.2%
    infrastructure (Pro)                                                                   $      6,000   1.8%
Grafana Cloud Pro: $131,511/month
    metrics                                                                                $     78,000  59.3%
    logs (process+write+retain 30d)                                                        $     49,500  37.6%
    traces (kept, 30d)                                                                     $      3,992   3.0%
    platform fee                                                                           $         19   0.0%
Grafana Cloud at the $3/1k enterprise floor: $89,511/month
    logs (process+write+retain 30d)                                                        $     49,500  55.3%
    metrics                                                                                $     36,000  40.2%
    traces (kept, 30d)                                                                     $      3,992   4.5%
    platform fee                                                                           $         19   0.0%
Self-hosted LGTM on AWS: $59,308/month
    people (2.0 SRE FTE)                                                                   $     44,000  74.2%
    compute (67 r7i.xlarge-eq: Mimir 45, Loki 10, Tempo 6, Kafka 6)                        $     12,942  21.8%
    object storage (metrics 13 mo, logs 30d, traces 30d)                                   $        942   1.6%
    cross-AZ replication traffic                                                           $        829   1.4%
    block storage (ingester WAL/TSDB, store-gateway, Kafka)                                $        595   1.0%
  Mimir sizing from the 3.2.4 guide: 400,000 samples/s, 179 cores, 534 GB RAM (incl. +50% headroom on memory), 27.3 TB in S3 at 2 B/sample

== 2. Where each model is sensitive ==
double the series: Datadog +$600,000, Grafana Cloud +$78,000, self-hosted +$8,115
halve log volume: Datadog -$132,000, Grafana Cloud -$24,750
Datadog curated + index only 15% of logs (rest to archive/Flex): $118,533/month (from $335,283)
self-hosted infrastructure alone (no people): $15,308; break-even FTEs vs Grafana Cloud Pro: 5.3

== 3. Storage medium vs compression: when does better compression on block storage win? ==
block storage with replicationFactor=1 matches Mimir's S3 cost at 2 B/sample only below 0.57 B/sample
block storage with replicationFactor=2 matches Mimir's S3 cost at 2 B/sample only below 0.29 B/sample
  0.6 B/sample x RF2 on gp3: 16.4 TB -> $1,311/month   vs   Mimir 2 B/sample on S3: $628/month
  1.0 B/sample x RF2 on gp3: 27.3 TB -> $2,184/month   vs   Mimir 2 B/sample on S3: $628/month
  0.6 B/sample x RF1 on gp3: 8.2 TB -> $655/month   vs   Mimir 2 B/sample on S3: $628/month
-> compression ratios alone don't decide storage cost: the medium (object vs replicated block
   storage) and the replication factor do. Compare $/sample-retained, measured on YOUR data.

== 4. Columnar logs (ClickHouse/SigNoz-style) vs Loki chunks: storage only ==
  Loki chunks (gzip/snappy) ~8x [E]            30 days: 11.2 TB -> S3 $259, gp3 $900
  ClickHouse ZSTD + LowCardinality ~15x [E]    30 days: 6.0 TB -> S3 $138, gp3 $480
-> at 3 TB/day, 30-day log storage costs hundreds to low thousands of dollars on any engine; the
   bill is compute for queries and, on SaaS, per-GB/per-event pricing. Index less, not compress more.

checks: 5/5 passed
verdict: OK
```

---

## 2. Production-hardened configurations and code blueprints

### 2.1 A neutral ingestion layer that keeps every option open

```yaml
# OTel Collector gateway (v0.164.0 names): fan out to two backends during an evaluation / migration.
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
  prometheus:
    config:
      scrape_configs:
        - job_name: federate-legacy
          scrape_interval: 30s
          static_configs:
            - targets: ["prometheus-legacy.monitoring.svc:9090"]
          metrics_path: /federate
          params:
            "match[]": ['{__name__=~"job:.*"}']
processors:
  memory_limiter:
    check_interval: 1s
    limit_percentage: 80
    spike_limit_percentage: 20
  filter/drop-unused:
    error_mode: ignore
    metrics:
      metric:
        - 'IsMatch(name, "^go_memstats_.*|^process_.*|^jvm_buffer_.*")'
exporters:
  prometheus_remote_write/mimir:
    endpoint: http://mimir-distributor.mimir.svc:8080/api/v1/push
    headers:
      X-Scope-OrgID: prod
  prometheus_remote_write/victoria:
    endpoint: http://vminsert.vm.svc:8480/insert/0/prometheus/api/v1/write
  otlp_http/candidate-saas:
    endpoint: https://otlp.vendor.example/otlp
service:
  pipelines:
    metrics:
      receivers: [otlp, prometheus]
      processors: [memory_limiter, filter/drop-unused]
      exporters: [prometheus_remote_write/mimir, prometheus_remote_write/victoria, otlp_http/candidate-saas]
```

**Why.**
- **Dual-write through one collector tier** keeps the bake-off honest: identical data, identical cardinality.
- **Dropping at the gateway** (File 02) happens *before* any per-series bill.
- **Federation of recording-rule outputs only (`job:.*`)** is the safe way to bridge a legacy Prometheus without copying its raw cardinality.

### 2.2 Bake-off protocol (what to measure, not what vendors claim)

```yaml
# bakeoff.yaml: the acceptance criteria a principal engineer signs before a platform decision
workload:
  replay: two weeks of production remote-write + OTLP traffic (dual-write, §2.1)
  queries: top 200 dashboard queries + all recording/alerting rules (from query logs)
measure:
  ingest:
    - samples/s and spans/s sustained at p99 latency < 1s, zero drops (conservation counters)
    - behaviour at 3x burst and during a backend node loss
  storage:
    - bytes per sample retained (after compaction) on our data, per signal
    - $ per sample-month including replication and medium (object vs block)
  query:
    - p50/p99 latency of the 200 queries at 1h, 24h, 30d ranges
    - numeric diff of every query result vs Prometheus reference (tolerance 1e-9 relative)
  operations:
    - upgrade procedure duration and blast radius; restore from backup; tenant isolation test
  cost:
    - monthly TCO at today's volume and at 3x, with FTE estimate, using list and negotiated prices
decide:
  - reject any option whose query results differ from the reference beyond tolerance on SLO queries
  - choose the lowest 3x-volume TCO among the options meeting ingest/query SLOs
```

**The "numeric diff vs reference" row is the one most bake-offs skip.**
- Semantics differ: MetricsQL `rate` extrapolation, SaaS rollups, staleness handling.
- An SLO computed differently is a different SLO.
- Folder 02's `promql_mini` passes the upstream promqltest corpus and can serve as an offline reference for the diff.

### 2.3 PromQL to measure your own inputs to the TCO model

```promql
# Active series and samples/s you actually ingest (Prometheus or Mimir)
sum(prometheus_tsdb_head_series)
sum(rate(prometheus_tsdb_head_samples_appended_total[5m]))

# Mimir: per-tenant in-memory series and ingestion rate
sum by (user) (cortex_ingester_memory_series)
sum by (user) (rate(cortex_distributor_received_samples_total[5m]))

# Bytes per sample on disk for a Prometheus (blocks only; head excluded)
prometheus_tsdb_storage_blocks_bytes
  / on() (sum(rate(prometheus_tsdb_head_samples_appended_total[1h])) * (prometheus_tsdb_retention_limit_seconds > 0))
```

The last expression divides block bytes by (samples/s × retention seconds). It is meaningful only once the TSDB has filled its retention window ⚠.

---

## 3. Failure modes and FinOps debugging

### F1. The SaaS bill triples after a "harmless" tag

**Symptom.** The Datadog custom-metrics line grows 3× month over month.

**Signature.** A new tag (`pod_name`, `customer_id`, `url`) on a high-volume metric. Distribution metrics with percentiles count 10 custom metrics per tag combination [D].

**Root cause.** SaaS bills every unique tag combination: $5 per 100/month above 100 per host (L1).

**Fix.**
- Drop or aggregate the tag at the agent or collector (File 02).
- Use Metrics without Limits to index fewer tags (billing changes).
- Prefer histograms with fewer tags.

**Prevention.** A cardinality budget per team with alerts on custom-metric count. Review tag changes like schema changes.

### F2. The bake-off picked a winner on compression ratio

**Symptom.** The new metrics backend costs more than projected despite "10× better compression".

**Signature.** Storage on replicated gp3 instead of S3. The replication factor was ignored. Bytes/sample measured on synthetic data.

**Root cause.** Medium × replication dominates (L1 §3: break-even at 0.29 B/sample for RF=2).

**Fix.** Recompute $/sample-month with the real medium and RF on production replay data.

**Prevention.** Bake-off protocol §2.2. Never accept vendor-benchmark bytes/sample.

### F3. Dashboards changed numbers after migration

**Symptom.** SLO dashboards differ by a few percent between old and new backends. Burn alerts fire differently.

**Signature.**
- `rate()`/`increase()` semantics (extrapolation, lookback).
- Staleness handling.
- Rollups or step alignment in the new engine.

**Root cause.** Query-engine semantic differences (§1.2) ⚠.

**Fix.**
- Pin SLO computations to recording rules evaluated in one engine.
- Adjust windows.
- Document accepted differences.

**Prevention.** Numeric-diff gate in the bake-off. Golden-query regression tests on upgrades.

### F4. Self-hosted platform without the people

**Symptom.** A Mimir/Kafka platform built by one engineer degrades after they leave. Upgrades stall and compaction halts.

**Signature.** No runbooks, no on-call rotation for the observability platform, and the compactor alert silenced.

**Root cause.** Self-hosted TCO is 74% people (L1). Under-staffing turns a cheap bill into an outage risk.

**Fix.** Staff it as a product (≥2 FTE plus a rotation), or buy.

**Prevention.** Make the people line explicit in every TCO; the break-even FTE count (5.3 in L1) is part of the decision record.

### F5. A query storm takes down ingestion

**Symptom.** A dashboard rollout with heavy queries causes ingestion errors in a self-hosted TSDB.

**Signature.** Shared nodes serve reads and writes: classic Mimir ingesters, or VictoriaMetrics `vmstorage` under heavy fan-out.

**Root cause.** Read and write paths share resources.

**Fix.**
- Query limits and caching.
- Shuffle-sharded queriers.
- Decoupled ingest (Mimir ingest storage; Kafka in front of any engine).

**Prevention.** A query-path SLO separate from the ingest SLO; load tests with the real dashboard set.

### F6. Log costs dominate after moving metrics off SaaS

**Symptom.** Metrics migration saved money, but the total bill barely moved.

**Signature.** Log indexing is now 76% of the remaining SaaS spend (L1 curated row).

**Root cause.** Logs were never governed: debug logs, health-check access logs, everything indexed.

**Fix.** Index only what is searched (15% in L1, $335k → $119k). Archive or Flex the rest. Drop debug at the agent (File 02 §4).

**Prevention.** Per-team log budgets and an index-vs-archive policy.

### F7. Lock-in discovered at renewal

**Symptom.** A renewal comes with a 40% increase. Migration is estimated at 18 months.

**Signature.** A proprietary agent, query language, dashboards and monitors everywhere, with no OTel or Prometheus exposition.

**Root cause.** Instrumentation coupled to the vendor.

**Fix.**
- Re-instrument with Micrometer/OTel (Folder 07).
- Route through an OTel collector tier (§2.1).
- Convert monitors to rules-as-code.

**Prevention.** A policy that instrumentation and pipelines are vendor-neutral, so the backend is a replaceable exporter.

---

## 4. L7 bar-raiser Q&A chains

<details><summary><b>Q1 · "Mimir or VictoriaMetrics for 50M active series?"</b></summary>

**Initial Prompt.** Choose and defend.

**L5 Textbook Answer.** VictoriaMetrics: better compression and simpler operations.

**Why L5 Fails at 3 AM or on the Bill.** "Better compression" ignores the medium and the replication (L1 §3), and "simpler" ignores multi-tenant isolation and query fan-out. The decision has no measurement behind it.

**L7 Principal Defense.** I'd run the §2.2 bake-off on replayed production traffic. My priors:
- **Mimir** wins when multi-tenancy, per-tenant limits, shuffle-sharded failure isolation, read/write decoupling (ingest storage) and S3-economics for long retention matter.
- **VictoriaMetrics** wins on operational simplicity and single-tenant efficiency when retention is moderate and the team is small.

I'd decide on measured $/sample-month (medium × RF), p99 of our top queries, numeric equality with Prometheus on SLO queries, and the FTE estimate. I'd also check MetricsQL differences on our burn-rate rules before committing.
</details>

<details><summary><b>Q2 · "Should we put metrics in ClickHouse with our logs and traces?"</b></summary>

**Initial Prompt.** One store for everything sounds cheaper.

**L5 Textbook Answer.** Yes, ClickHouse is fast and compresses well.

**Why L5 Fails at 3 AM or on the Bill.**
- Prometheus-style workloads (millions of independent counters, per-series `rate()`, alerting every 30 s) are not what columnar sort keys optimise.
- PromQL fidelity and the alerting ecosystem (rules, Alertmanager, mixins) are lost or translated.
- Schema design becomes your job.

**L7 Principal Defense.**
- ClickHouse is excellent for logs and traces: wide events, high-cardinality attributes, ad-hoc SQL (L1 §4: 30-day storage of 3 TB/day is hundreds of dollars).
- For metrics I'd keep a Prometheus-native TSDB for alerting and SLOs.
- I'd use ClickHouse for exploratory analytics over exported or derived metrics.
- If a single vendor such as SigNoz is attractive, I'd verify alerting semantics and PromQL compatibility on our rule catalog first (Folder 07 file 03) ⚠.
</details>

<details><summary><b>Q3 · "Build vs buy at 12M series."</b></summary>

**Initial Prompt.** The CFO wants a number.

**L5 Textbook Answer.** Self-hosting is always cheaper.

**Why L5 Fails at 3 AM or on the Bill.** It ignores people (74% of self-hosted TCO in L1) and the break-even point (5.3 FTE vs Grafana Cloud Pro list). Below a few million series, buying wins.

**L7 Principal Defense.** Present L1's table with every assumption visible:

| | Monthly |
|---|---|
| Datadog curated | $335k |
| Grafana Cloud Pro | $132k |
| Self-hosted | $59k |

- **Sensitivities:** doubling series costs +$600k / +$78k / +$8k respectively.
- **Recommendation:** an OTel and Prometheus-native neutral pipeline (§2.1) in all cases, a governance program first (File 02 savings are platform-independent), then self-host if we can staff 2+ FTE with an on-call rotation, or negotiate SaaS from a position of portability.
- **Revisit annually** with measured inputs (§2.3).
</details>

<details><summary><b>Q4 · "Why did our Datadog bill jump?"</b></summary>

**Initial Prompt.** Nothing changed in traffic.

**L5 Textbook Answer.** More hosts or more logs.

**Why L5 Fails at 3 AM or on the Bill.** The dominant term is usually custom metrics (66% in L1's send-everything case). A single new tag on a high-volume metric, or percentiles enabled on a distribution, can multiply it without any traffic change.

**L7 Principal Defense.**
- Pull the usage attribution by metric and tag. Find the new tag combinations, and check distribution percentile settings.
- Check high-water-mark host counts from autoscaling spikes.
- Fix at the pipeline (drop or aggregate the tag), not by asking teams.
- Install a cardinality budget alert.
- The model in L1 lets finance see which knob moves which line.
</details>

<details><summary><b>Q5 · "VictoriaMetrics shows different SLO numbers than Prometheus."</b></summary>

**Initial Prompt.** Same data, different burn rates.

**L5 Textbook Answer.** One of them has a bug.

**Why L5 Fails at 3 AM or on the Bill.** Both may be correct for their documented semantics. MetricsQL deliberately avoids `rate()` extrapolation and handles window edges differently ⚠. Treating it as a bug wastes days.

**L7 Principal Defense.**
- Reproduce with a small series and compute both by hand (Folder 02 file 01 has the exact Prometheus algorithm).
- Decide which semantics define the SLO, and compute SLO recording rules in one engine.
- Accept documented differences for dashboards.
- Add golden-query regression tests so upgrades don't shift SLOs silently.
</details>

<details><summary><b>Q6 · "Storage is cheap. Why do you care about bytes per sample?"</b></summary>

**Initial Prompt.** S3 is $0.023/GB.

**L5 Textbook Answer.** We don't. Retention is free.

**Why L5 Fails at 3 AM or on the Bill.**
- Bytes per sample drive store-gateway disk and cache sizes, query latency (bytes scanned) and compaction CPU, not just S3.
- On block-storage engines they are multiplied by RF on a medium ~3.5× pricier.

**L7 Principal Defense.**
- S3 itself is small: $628/month for 27 TB in L1.
- I care about **bytes scanned per query** and **bytes on replicated block storage**.
- I measure bytes/sample retained (§2.3) and $/sample-month by medium.
- I optimise the big levers: series count, histogram buckets, retention per tenant.
- Shaving bytes/sample is last.
</details>

<details><summary><b>Q7 · "Design a vendor-neutral observability architecture."</b></summary>

**Initial Prompt.** Leadership wants negotiating leverage.

**L5 Textbook Answer.** Use OpenTelemetry.

**Why L5 Fails at 3 AM or on the Bill.** "Use OTel" without pipelines, semantic conventions, rules-as-code and portable dashboards still leaves you locked in at the query and alerting layer.

**L7 Principal Defense.** Lay out four portable layers.
- **Instrumentation:** Micrometer/OTel (Folder 07) with Prometheus exposition.
- **Pipeline:** an OTel/Alloy tier with routing, dropping and dual-write (§2.1).
- **Storage behind standard APIs:** Prometheus remote write / PromQL, OTLP, LogQL/SQL.
- **As code:** rules and SLOs (Folder 07 file 03), dashboards (Folder 05 file 03) and alert routing.

Then any backend is an exporter swap, proven by keeping a continuous dual-write to a second backend for a sample tenant.
</details>

<details><summary><b>Q8 · "What's the single biggest lever on observability cost?"</b></summary>

**Initial Prompt.** One answer.

**L5 Textbook Answer.** Switch to open source.

**Why L5 Fails at 3 AM or on the Bill.** Platform choice changes the price per unit. Governance changes the *units*, on every platform, and compounds.

**L7 Principal Defense.** Not sending what nobody uses.
- **Units are mostly waste.** In File 02, 88% of series and 55% of log volume are removable for this corpus without losing a dashboard or rule result.
- **The saving is portable:** $26k/month on Grafana Cloud list, $202k on Datadog list, and less capacity self-hosted.
- **Do it first.** Then compare platforms on the reduced volume.
</details>

---

## 5. Invariants checklist

- [ ] Every platform comparison uses one reference workload, list *and* negotiated prices, and an explicit people line.
- [ ] Storage cost is computed as $/sample-month including medium and replication factor, from production replay data.
- [ ] SLO and alert queries are numerically diffed against a reference engine before any migration.
- [ ] Instrumentation and pipelines are vendor-neutral (Micrometer/OTel, OTel/Alloy tier); the backend is an exporter.
- [ ] A cardinality budget and a log index-vs-archive policy exist before any SaaS contract is signed.
- [ ] The decision record lists the break-even FTE count and the 3×-volume TCO.

---

## 6. References

- Datadog pricing list: <https://www.datadoghq.com/pricing/list/>
- Datadog custom metrics billing: <https://docs.datadoghq.com/account_management/billing/custom_metrics/>
- Grafana Cloud pricing: <https://grafana.com/pricing/>
- Mimir capacity planning (3.2.4 source): <https://github.com/grafana/mimir/blob/mimir-3.2.4/docs/sources/mimir/manage/run-production-environment/planning-capacity.md>
- Loki sizing (3.7.9 source): <https://github.com/grafana/loki/blob/v3.7.9/docs/sources/setup/size/_index.md>
- VictoriaMetrics cluster (capacity planning, replication): <https://docs.victoriametrics.com/victoriametrics/cluster-victoriametrics/>
- MetricsQL: <https://docs.victoriametrics.com/victoriametrics/metricsql/>
- ClickHouse MergeTree: <https://clickhouse.com/docs/engines/table-engines/mergetree-family/mergetree>
- SigNoz: <https://github.com/SigNoz/signoz>
- Amazon S3 pricing: <https://aws.amazon.com/s3/pricing/>
- Amazon EBS pricing: <https://aws.amazon.com/ebs/pricing/>
