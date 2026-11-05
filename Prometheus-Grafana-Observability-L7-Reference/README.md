# Prometheus, PromQL, Grafana and the LGTM Stack: Observability L7 Reference

A Principal/Staff-level (FAANG L7) reference and interview playbook. It covers Prometheus 3.x internals, PromQL mathematics, recording/alerting rules and SLO error-budget math, Grafana as code, the LGTM + OpenTelemetry stack, and market alternatives. Every file follows the same spine:

1. first-principles storage, math or wire mechanics;
2. production-hardened configurations and code;
3. failure modes with FinOps debugging;
4. bar-raiser Q&A chains;
5. an invariants checklist;
6. references.

## Status

**All 8 folders are complete and gated (2026-11-05):**
- 27 files and ~172k words, including listings;
- 36 listings: 31 Python programs, 3 Java classes and 2 YAML artefacts;
- 247 bar-raiser chains.

| # | Folder | Files | Words | Listings | Chains |
|---|---|---|---|---|---|
| 01 | [01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics](01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics/) | 4 | 41.2k | 7 | 33 |
| 02 | [02-PromQL-Deep-Dive-and-Mathematical-Mechanics](02-PromQL-Deep-Dive-and-Mathematical-Mechanics/) | 3 | 22.2k | 4 | 24 |
| 03 | [03-What-to-Monitor-Complete-Enterprise-Taxonomy](03-What-to-Monitor-Complete-Enterprise-Taxonomy/) | 4 | 17.6k | 4 | 32 |
| 04 | [04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math](04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math/) | 4 | 16.2k | 4 | 32 |
| 05 | [05-Grafana-Architecture-Dashboards-as-Code-and-Signal-Correlation](05-Grafana-Architecture-Dashboards-as-Code-and-Signal-Correlation/) | 3 | 11.1k | 3 | 24 |
| 06 | [06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack](06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/) | 3 | 25.2k | 3 | 27 |
| 07 | [07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs](07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/) | 3 | 18.7k | 8 | 24 |
| 08 | [08-Market-Comparison-FinOps-and-FAANG-L7-Bar-Raiser-Playbook](08-Market-Comparison-FinOps-and-FAANG-L7-Bar-Raiser-Playbook/) | 3 | 19.7k | 3 | 51 |

Folder names follow the repository blueprint in the brief. The brief's role section calls Folder 08 `08-Market-Comparison-and-L7-Bar-Raiser-Playbook`; the blueprint name is used.

**Where to start.**
- For interviews, start with [Folder 08 file 03](08-Market-Comparison-FinOps-and-FAANG-L7-Bar-Raiser-Playbook/03-35-faang-l7-observability-and-incident-diagnostics-bar-raiser-qna-chains.md). Its 35 cross-domain chains link back to the evidence in every folder.
- For building, start with [Folder 07](07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/).

## Folder 01: Prometheus 3 TSDB internals and cardinality physics

| File | Covers | Listings |
|---|---|---|
| [01 · TSDB head, WAL, mmap chunks, Gorilla/XOR](01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics/01-tsdb-head-block-wal-mmap-chunks-and-gorilla-xor-compression.md) | Write path, `stripeSeries`/`memSeries`, XOR and XOR2 bit layouts, chunk cutting, 2 ms timestamp alignment, head compaction and WAL checkpoints, OOO/WBL, memory per series | L1 `xor_chunk.py`, L2 `wal_head_lab.py` |
| [02 · Inverted index, postings, cardinality OOMs](01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics/02-inverted-index-postings-lists-and-high-cardinality-oom-mechanics.md) | `MemPostings`, index format V2, `PostingsForMatchers`, the cardinality product law, churn, `/api/v1/status/tsdb` | L3 `tsdb_block_reader.py`, L4 `postings_lab.py` |
| [03 · Metric types and native histograms](01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics/03-metric-types-counters-gauges-summaries-and-prometheus3-native-histograms.md) | Counters and start timestamps, gauges, summaries, classic histograms, native exponential histograms and NHCB, OTel mapping, quantile accuracy | L5 `native_histogram_lab.py` |
| [04 · Scrape lifecycle, SD, relabeling, Remote Write 2.0](01-Prometheus-3-TSDB-Internals-and-Cardinality-Physics/04-scrape-lifecycle-service-discovery-relabel-configs-and-remote-write-2.md) | Scrape pipeline and staleness, relabel semantics and Go template traps, hashmod sharding and HA, RW1 vs RW2 wire format, remote-write autoscaling and loss modes, OTLP receiver, Agent mode | L6 `relabel_engine.py`, L7 `remote_write_lab.py` |

Key verified results, so later folders can reuse them without re-deriving:

**Compression and storage (L1, L2):**
- XOR: 0.40 B/sample for a constant series and 2.09 for an aligned integer counter. The same counter with 0–10 ms scrape lateness costs 3.84; random floats 7.4; float-accumulated CPU seconds 8.3.
- XOR2 vs XOR: −29% on constant series and roughly ±1% elsewhere; 24 vs 16 bits for dods of 4096–8192 ms.
- Chunks hold 118–120 samples for 1–60 s intervals, but only 60 at 120 s and 24 at 300 s (2 h boundary), which costs 2.17 B/sample.
- 1 M series @15 s: WAL ~0.55 MiB/s, peak WAL + checkpoint ~6 GiB, worst-case replay ~720 M samples.
- Structural head memory ~1.4 KiB live → ~2.4 KiB with GOGC 75 for a 14-label series [E].

**Index and cardinality (L3, L4):**
- Index ≈ 103 B/series for a Kubernetes fleet (57% series section, 39% postings).
- A real Prometheus 2.0 block decodes and re-encodes byte-identically.
- Rolling deploys every 30 minutes inflate the head to 8× active series.

**Histograms (L5):**
- Native schema 3 quantile error ≤ 0.5% vs up to +51% for DefBuckets on bimodal data.
- Averaging per-pod p99s is −12% off the fleet p99.
- The native bounds table is reproduced bit-exactly by client_golang's generator with Go's `math.Exp2`; only 170 of 511 entries are correctly rounded.

**Relabeling and remote write (L6, L7):**
- 16 of 16 Prometheus relabel test vectors pass (MD5 hashmod 976 and 734). `$1_suffix` expands to `""`.
- RW2 is 0.23× RW1 raw and ~0.72× after snappy on a 2,000-sample Kubernetes batch.
- With default `max_shards` 50, a 2 s backend latency spike leaves 1 M series @15 s ~5 minutes behind; 200 shards bound it to 9 s.

## Folder 02: PromQL deep dive and mathematical mechanics

| File | Covers | Listings |
|---|---|---|
| [01 · Instant vs range vectors, rate vs irate, extrapolation, resets](02-PromQL-Deep-Dive-and-Mathematical-Mechanics/01-instant-vs-range-vectors-rate-vs-irate-extrapolation-and-counter-resets.md) | Left-open ranges (3.x), `extrapolatedRate` (1.1× threshold, half-interval rule, zero clamp), lookback and staleness, `$__rate_interval` | `promql_mini.py`, `rate_math_lab.py` |
| [02 · Aggregations, vector matching, subqueries](02-PromQL-Deep-Dive-and-Mathematical-Mechanics/02-aggregations-vector-matching-on-ignoring-group-left-and-subqueries.md) | Signatures, `on`/`ignoring`/`group_left`, Kahan sums, subquery absolute-grid alignment | `vector_matching_lab.py` |
| [03 · `histogram_quantile` math, classic vs native](02-PromQL-Deep-Dive-and-Mathematical-Mechanics/03-histogram-quantile-math-classic-le-buckets-vs-native-exponential-schemas.md) | `BucketQuantile`, `histogram_fraction`, interpolation error, NHCB | `histogram_quantile_lab.py` |

**Key result.** `promql_mini.py` is a 1,474-line PromQL engine. It passes **695/695** attempted cases from the upstream v3.15.1 `promqltest` corpus (kept in `fixtures/promqltest-v3.15.1`), with 0 failures and 427 skipped, mostly native histograms. Folders 04, 07 and 08 reuse it as a reference engine.

## Folder 03: What to monitor, the enterprise taxonomy

| File | Covers | Listings |
|---|---|---|
| [01 · USE/RED/golden signals, kernel, eBPF, node_exporter](03-What-to-Monitor-Complete-Enterprise-Taxonomy/01-use-red-four-golden-signals-and-linux-kernel-ebpf-node-exporter-metrics.md) | Method choice per resource, PSI, Little's law | `use_red_lab.py` |
| [02 · Kubernetes: KSM, cAdvisor, CFS throttling, OOMs](03-What-to-Monitor-Complete-Enterprise-Taxonomy/02-kubernetes-monitoring-kube-state-metrics-cadvisor-cfs-throttling-and-ooms.md) | CFS quota stalls at low average CPU, OOM signals | `cfs_throttling_sim.py` |
| [03 · JVM, Micrometer, GC, virtual threads, HikariCP](03-What-to-Monitor-Complete-Enterprise-Taxonomy/03-java-jvm-micrometer-gc-pauses-virtual-threads-and-hikaricp-pool-metrics.md) | Pool sizing with Erlang C (M/M/c) checked against a discrete-event simulation | `hikari_pool_lab.py` |
| [04 · Kafka, Postgres, Redis, LLM inference (vLLM)](03-What-to-Monitor-Complete-Enterprise-Taxonomy/04-kafka-postgres-redis-and-llm-inference-vllm-kv-cache-ttft-tpot-metrics.md) | Time-based consumer lag, idle-primary replication-lag trap, TTFT/TPOT/goodput | `lag_llm_lab.py` |

## Folder 04: Recording rules, Alertmanager and SLO error-budget math

| File | Covers | Listings |
|---|---|---|
| [01 · Recording rules naming and pre-aggregation](04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math/01-recording-rules-naming-conventions-level-metric-operations-and-pre-aggregation.md) | `level:metric:operations`, a linter reused by Folders 07–08 | `rules_lab.py` |
| [02 · Multi-window multi-burn-rate SLO alerts](04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math/02-google-sre-multi-window-multi-burn-rate-slo-alerts-and-error-budget-math.md) | Reproduces the SRE Workbook's 2%/5%/10% budget consumption and 0.86 min detection exactly | `burn_rate_lab.py` |
| [03 · Alertmanager: gossip HA, dedup, grouping, inhibition](04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math/03-alertmanager-architecture-gossip-ha-deduplication-grouping-inhibition-and-silences.md) | Port of v0.34.2 `Route.Match`, `needsUpdate`, inhibition `equal`; at-least-once HA | `alertmanager_lab.py` |
| [04 · Dead man's switch, absent(), flapping](04-Recording-Rules-Alertmanager-and-SLO-Error-Budget-Math/04-dead-mans-switch-watchdog-absent-alerts-and-preventing-flapping-alert-fatigue.md) | Port of `AlertingRule.Eval` (`for`, `keep_firing_for`), absence vs `up == 0` | `alert_state_lab.py` |

## Folder 05: Grafana architecture, dashboards as code, correlation

| File | Covers | Listings |
|---|---|---|
| [01 · Cognitive hierarchy, RED drill-downs, variables](05-Grafana-Architecture-Dashboards-as-Code-and-Signal-Correlation/01-grafana-cognitive-hierarchy-red-drilldowns-variables-and-transformations.md) | Dashboard generator and query linter (Grafana 13.3) | `dashboard_lab.py` |
| [02 · Exemplars to Tempo and Loki](05-Grafana-Architecture-Dashboards-as-Code-and-Signal-Correlation/02-exemplars-linking-prometheus-metrics-to-tempo-traces-and-loki-logs.md) | Port of the exemplar ring buffer: ~2.5 min retention at 10k series; 2.3% click-through at 1% head sampling | `exemplar_lab.py` |
| [03 · Git Sync, Terraform, mixins](05-Grafana-Architecture-Dashboards-as-Code-and-Signal-Correlation/03-observability-as-code-grafana-git-sync-terraform-grizzly-and-monitoring-mixins.md) | Spec → rules + dashboards pipeline, drift detection | `mixin_lab.py` |

## Folder 06: OpenTelemetry, Grafana Alloy and the LGTM scale stack

| File | Covers | Listings |
|---|---|---|
| [01 · Collector vs Alloy, tail sampling, span metrics](06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/01-opentelemetry-collector-vs-grafana-alloy-pipelines-tail-sampling-and-spanmetrics.md) | Two-tier sampling topology, v0.164.0 snake_case component names vs Alloy's old names | `tail_sampling_lab.py` |
| [02 · Mimir and Thanos rings, quorum, compaction](06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/02-grafana-mimir-and-thanos-distributor-ingester-hash-rings-and-s3-compaction.md) | Mimir 3 ingest storage (Kafka), zone awareness, shuffle sharding, Thanos dedup and downsampling | `ring_lab.py` |
| [03 · Loki/LogQL, Tempo/TraceQL, Pyroscope eBPF](06-OpenTelemetry-Grafana-Alloy-and-The-LGTM-Scale-Stack/03-grafana-loki-logql-tempo-traceql-and-pyroscope-continuous-ebpf-profiling.md) | Streams and chunks economics, mini LogQL and TraceQL engines, profiling statistics | `lgtm_query_lab.py` |

**Key results.**
- **Load-balancing ring.** A port of the OTel `load_balancing` ring passes the upstream vectors 4/4.
- **Tail-sampler buffer.** The buffer is a **cliff**: 100% of traces are dropped unevaluated once `num_traces / rate < decision_wait`. The defaults fail at 1,667 new traces/s per pod.
- **Stacked sampling.** 10% head + 10% tail keeps 1.02%.
- **Mimir rings.** The series token is FNV-1 32 with no separators. Zone-blind "even" tokens give 7.01× skew, against 1.12× for random tokens and 1.02× for per-zone spread. Zone awareness turns an AZ loss into 0% failed writes, against 23.7% without it.
- **Thanos.** The penalty dedup passes upstream vectors 5/5. Downsampling grows storage at equal retention.
- **Loki.** A `level` label doubles chunks.
- **Profiling.** At 19 Hz, a 2.0→2.5% regression is z = 0.84 per pod-window and 25.5 fleet-wide.

## Folder 07: Production blueprints (Spring Boot, Kubernetes, rule catalogs)

| File | Covers | Listings |
|---|---|---|
| [01 · Java 21 Spring Boot 4.1, Micrometer, OTel, exemplars](07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/01-complete-java21-spring-boot-micrometer-otel-exemplar-and-custom-meter-code.md) | Guardrails, business meters, Observations, Boot 4 configuration | 3 Java classes, `checkout-application.yaml`, `boot_micrometer_lab.py` |
| [02 · kube-prometheus-stack, ServiceMonitor/PodMonitor](07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/02-kube-prometheus-stack-servicemonitor-podmonitor-and-relabeling-manifests.md) | Port of operator v0.94.2 relabel-chain generation, EndpointSlice, sharding | `servicemonitor_lab.py` |
| [03 · Recording and SLO alerting rule catalog](07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/03-production-ready-recording-and-slo-alerting-rules-catalog-for-microservices.md) | 17 recording rules + 10 alerts, scenario-tested | `microservice-rules.yaml`, `rule_catalog_lab.py` |

**Key results.**
- **Java.** The Java classes compile with `javac --release 21 -Xlint:all -Werror` against 40 SHA-1-verified Boot 4.1.2 BOM jars.
- **Micrometer oracle.** A small oracle program ran them on the real Micrometer 1.17.2 `PrometheusMeterRegistry` (`fixtures/micrometer-1.17.2-oracle`). The Python port matches it exactly: 276/66/48 ladder buckets, and the 69 and 54 `le` boundaries one by one.
- **Configuration lint.** Every `application.yaml` key is validated against the configuration metadata inside the Boot 4.1.2 jars (`fixtures/spring-boot-4.1.2-metadata`). The lint catches Boot 4's removal of `management.otlp.tracing.endpoint`.
- **Rule catalog.** It fires exactly the expected alerts in 7 scenarios, including a quantile alert that can never fire because no bucket exists above its threshold.

## Folder 08: Market comparison, FinOps and the L7 playbook

| File | Covers | Listings |
|---|---|---|
| [01 · Mimir vs VictoriaMetrics vs ClickHouse/SigNoz vs Datadog](08-Market-Comparison-FinOps-and-FAANG-L7-Bar-Raiser-Playbook/01-architectural-showdown-mimir-vs-victoriametrics-vs-clickhouse-signoz-vs-datadog.md) | Durability, query isolation, cardinality behaviour, TCO with list prices of 2026-11-05 | `tco_showdown_lab.py` |
| [02 · FinOps: adaptive telemetry, unused metrics, TCO math](08-Market-Comparison-FinOps-and-FAANG-L7-Bar-Raiser-Playbook/02-observability-finops-adaptive-telemetry-dropping-unused-metrics-and-tco-math.md) | Usage-driven drop/aggregate, reset-aware aggregation proof, log volume control | `finops_lab.py` |
| [03 · 35 L7 observability and incident-diagnostics chains](08-Market-Comparison-FinOps-and-FAANG-L7-Bar-Raiser-Playbook/03-35-faang-l7-observability-and-incident-diagnostics-bar-raiser-qna-chains.md) | 9 domains, each defense linked to evidence | `chain_coverage_lab.py` |

**Key results.**
- **Reference workload** (12M series, 3 TB/day logs, 40k spans/s):

  | Option | Monthly | Note |
  |---|---|---|
  | Datadog list, everything sent | $905k | 66% custom metrics |
  | Datadog, curated | $335k | |
  | Grafana Cloud Pro list | $132k | |
  | Self-hosted LGTM | $59k | 74% people |

  The break-even is 5.3 FTE.
- **Usage-driven reduction.** Removes 88% of series and 55% of log volume for the analysed corpus.
- **Aggregation safety.** Reset-aware aggregation is exact, while naive counter summing is off by 1,333 req/s on one restart.

## Conventions

- **Evidence labels.** **[D]** documented or read in the pinned source. **[M]** measured by a listing in this KB (deterministic, regenerated by the gate). **[E]** estimate or model with stated assumptions. **⚠** version-sensitive, so re-verify on upgrade.
- **Pinned versions:**
  - Prometheus **v3.15.1** (2026-10-21; source read at tag `v3.15.1`), the v3.13 LTS line where it differs, client_golang **v1.25.0**. The Remote Write 2.0 proto in that tag is marked v2.0-rc.4.
  - Alertmanager v0.34.2; Grafana 13.3.
  - OTel Collector v0.164.0; Alloy v1.21.3.
  - Mimir 3.2.4; Thanos v0.42.5; Loki 3.7.9 (4.0.0-rc.2 noted); Tempo 3.1.1; Pyroscope 2.4.3.
  - Spring Boot 4.1.2 (Micrometer 1.17.2, OTel Java 1.62.0); Prometheus Operator v0.94.2; kube-prometheus-stack 92.18.0.
  - VictoriaMetrics v1.155.0; ClickHouse 26.10; SigNoz v0.149.0.
- **Listings** include Java and YAML artefacts (Folder 07). Only Python listings are executed by the gate; the Java classes were compiled separately (see Verification method).
- **Failure modes** use `### Fn` with **Symptom → Signature → Root cause → Fix → Prevention**.
- **Bar-raiser chains** use **Initial Prompt → L5 Textbook Answer → Why L5 Fails at 3 AM or on the Bill → L7 Principal Defense**.
- **Listings** are complete, stdlib-only Python 3 programs. Each is embedded verbatim after an `<!-- listing:NAME -->` marker, and its stdout follows an `<!-- output:NAME -->` marker.

## Verification method

A folder gate runs after every change. For each folder it checks:

- **Spine.** The section order, ≥ 2 ASCII diagrams, ≥ 6 failure modes with all five labels, and ≥ 8 chains with all four labels.
- **Code blocks.**
  - Every `yaml` block parses.
  - Every non-listing `python` block parses.
  - Every `promql` block is bracket- and quote-balanced.
- **Listings.**
  - Each listing is byte-identical to its source.
  - Re-running each listing reproduces its embedded output exactly, ending in `verdict: OK`.
- **Links.** Relative links resolve, and external URLs return < 400.

Oracles used in Folder 01:

- **Real data.** `fixtures/prometheus-v3.15.1-testdata/index_format_v1/` is a block written by Prometheus 2.0.0. It is copied verbatim from the Prometheus repository (Apache-2.0); see the fixture's `NOTICE.md`. Its expected contents are asserted by Prometheus's own `TestReadIndexFormatV1`.
- **Prometheus's own test vectors.** The 16 `TestRelabel` cases in `model/relabel/relabel_test.go`.
- **Hashes of upstream constants.** The SHA-256 of the native-histogram bounds table parsed from `model/histogram/generic.go`; it equals client_golang's table.
- **Independent decoders.** Every encoder (XOR, XOR2, WAL, index V2, RW1/RW2 protobuf, snappy) is checked by a decoder written from the format documents.

Oracles added in later folders:

- **Folder 02.** The upstream `promqltest` corpus at v3.15.1: 695/695 attempted cases pass.
- **Folder 04.** The SRE Workbook burn-rate numbers, plus ports of Alertmanager and rule-state code.
- **Folder 06.** Upstream Go test vectors for:
  - the OTel `load_balancing` ring;
  - the Thanos dedup iterator;
  - FNV reference vectors (Mimir token, tail-sampling policy).
- **Folder 07.**
  - `javac` compilation against SHA-1-verified Maven Central jars.
  - A run of the real Micrometer 1.17.2 registry (the only third-party code executed, on a JDK already used in earlier sessions).
  - Spring Boot 4.1.2's own configuration metadata.
  - Prometheus Operator v0.94.2 relabel generation, run through the Folder 01 relabel engine.
- **Folder 08.** Vendor list prices read from their public pages on 2026-11-05, and vendor sizing guides (Mimir `planning-capacity.md`, Loki sizing table).

**Not verified here.**
- **Binaries.** Running freshly downloaded server binaries was not permitted in the build environment: Prometheus/promtool, the OTel Collector, Alloy, Mimir, Loki, Tempo, Pyroscope and the operator.
- **Live-server numbers.** None come from a live server. Live behaviour (memory per series, replay times, real snappy ratios, tail-sampler memory) is labelled [E] and comes with the metric to calibrate it against.
- **Other artefacts.** Configuration YAML is parsed by the gate and keys are checked against source or metadata where noted. Alloy configurations and the `promtool` test file are not executed.

## Where this KB refines the brief

- **Postings are not Roaring bitmaps.** Upstream Prometheus writes raw 4-byte big-endian postings (`EncodePostingsRaw`), and the head uses sorted `[]SeriesRef`. The encoder is pluggable, and bitmaps appear in Lucene, Druid/Pinot and ClickHouse, not in Prometheus's index (File 02 §0).
- **Gorilla ≠ Prometheus XOR.** The timestamp buckets are 14/17/20/64 bits (millisecond resolution) with an asymmetric range check, not the paper's 7/9/12/32. 3.15 adds a stable XOR2 format with joint timestamp/value control bits (File 01 §1.4–1.5).
- **Native histograms are stable but opt-in** (3.8+). Scraping needs `scrape_native_histograms: true` and a protobuf or OM 2.0 exposition. Remote write needs `send_native_histograms: true`; both default to off.
- **Doc-vs-code drift found:**
  - `wal.md` draws Samples-record deltas as uvarint, but the code writes signed varints.
  - `memoryInBytesByLabelName` is documented as "sum of value lengths", but the code computes `(1+len(name)+1+len(value)) × series`.
  - The native bounds table is not correctly rounded (341 of 511 entries are 1–4 ulps low) and is reproducible only with Go's `math.Exp2`.
- **Retention moved to the config file** (`storage.tsdb.retention.*`); the CLI flags are deprecated in 3.x.

## Notation

- `dod` is the delta-of-delta of timestamps.
- "Head" means the in-memory block (1–3 h of data).
- "Churn" is series created per unit time relative to active series.
- B/sample is bytes per sample including chunk headers.
- Schema `s` means base `2^(2^-s)`.
- RW1/RW2 are Remote Write 1.0 and 2.0.

## Re-running a listing

Listings import across folders:
- `mixin_lab`, `rule_catalog_lab` and `finops_lab` import `promql_mini` (Folder 02) and `rules_lab` (Folder 04);
- `servicemonitor_lab` imports `relabel_engine` (Folder 01);
- `finops_lab` also reads Folder 07's `microservice-rules.yaml`.

So extract the listings of **all** folders into one directory:

```python
import pathlib
import re
import sys

kb = pathlib.Path(sys.argv[1])                  # the KB root (this README's folder)
out = pathlib.Path(sys.argv[2]); out.mkdir(exist_ok=True)
for md in sorted(kb.glob("*/*.md")):
    for name, body in re.findall(r"<!-- listing:(\S+) -->\n```\w+\n(.*?)\n```\n", md.read_text(encoding="utf-8"), re.S):
        (out / name).write_text(body + "\n", encoding="utf-8")
        print("extracted", name)
# then, e.g.: python <out>/rule_catalog_lab.py <kb>/07-Production-Blueprints-Spring-Boot-K8s-and-Rule-Catalogs/03-production-ready-recording-and-slo-alerting-rules-catalog-for-microservices.md
# The argument is the .md file the listing belongs to: listings use it to locate that folder's fixtures/
# (Folders 01, 02, 07) or, for chain_coverage_lab.py, to audit the document itself.
```

The Java classes (Folder 07 file 01) need the Spring Boot 4.1.2 BOM jars on the classpath. The exact versions are listed in that file's header, and they compile with `javac -proc:none --release 21 -Xlint:all -Werror -cp <jars> *.java`.
