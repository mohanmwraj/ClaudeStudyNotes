# Unified Dataflow · Apache Beam · Google Cloud Dataflow · Apache Flink — L7 Reference

A Principal/Staff-level (L6/L7) knowledge base on distributed stream and batch processing, built from first principles:
the Dataflow Model, Beam portability internals, Dataflow (Runner v2, Streaming Engine/Windmill, Shuffle), and Flink
(1.20 LTS and 2.x disaggregated state with ForSt). It is meant to be both a permanent engineering reference and a FAANG L7
interview playbook.

## Layout and build status

| # | Folder | Status |
|---|--------|--------|
| 01 | [`01-First-Principles-and-The-Dataflow-Model/`](01-First-Principles-and-The-Dataflow-Model/) | ✅ Written 2026-10-26 |
| 02 | [`02-Apache-Beam-Execution-and-Portability-Internals/`](02-Apache-Beam-Execution-and-Portability-Internals/) | ✅ Written 2026-10-26 |
| 03 | [`03-Google-Cloud-Dataflow-and-MillWheel-Internals/`](03-Google-Cloud-Dataflow-and-MillWheel-Internals/) | ✅ Written 2026-10-26 |
| 04 | [`04-Apache-Flink-Runtime-Checkpointing-and-State/`](04-Apache-Flink-Runtime-Checkpointing-and-State/) | ✅ Written 2026-10-26 |
| 05 | [`05-Distributed-Shuffle-Skew-and-Join-Mechanics/`](05-Distributed-Shuffle-Skew-and-Join-Mechanics/) | ✅ Written 2026-10-26 |
| 06 | [`06-Lakehouse-Sinks-Backpressure-and-FinOps/`](06-Lakehouse-Sinks-Backpressure-and-FinOps/) | ✅ Written 2026-10-26 |
| 07 | [`07-Production-Java-Code-Blueprints/`](07-Production-Java-Code-Blueprints/) | ✅ Written 2026-10-26 |
| 08 | [`08-FAANG-L7-Architecture-Playbook-and-Bar-Raiser-QA/`](08-FAANG-L7-Architecture-Playbook-and-Bar-Raiser-QA/) | ✅ Written 2026-10-26 |

### Folder 01 contents

1. [What / Where / When / How, time domains, and skew](01-First-Principles-and-The-Dataflow-Model/01-what-where-when-how-and-time-domains-skew.md)
2. [Watermark calculus: monotonicity, idleness, and hold locks](01-First-Principles-and-The-Dataflow-Model/02-watermark-calculus-monotonicity-idleness-and-hold-locks.md)
3. [Windowing internals: merging, panes, accumulation, and retractions](01-First-Principles-and-The-Dataflow-Model/03-windowing-internals-merging-pane-accumulation-and-retractions.md)

### Folder 02 contents

1. [FlumeJava DAG optimizations: fusion and combiner lifting](02-Apache-Beam-Execution-and-Portability-Internals/01-flumejava-dag-optimizations-fusion-and-combiner-lifting.md)
2. [Runner v2 and portability: the Fn API, gRPC bundles, and the SDK harness](02-Apache-Beam-Execution-and-Portability-Internals/02-runner-v2-portability-fn-api-grpc-bundles-and-sdk-harness.md)
3. [Splittable DoFn, restriction trackers, and coder determinism](02-Apache-Beam-Execution-and-Portability-Internals/03-splittable-dofn-sdf-restriction-trackers-and-coder-determinism.md)

### Folder 03 contents

1. [MillWheel and the Streaming Engine (Windmill) architecture](03-Google-Cloud-Dataflow-and-MillWheel-Internals/01-millwheel-and-streaming-engine-windmill-architecture.md)
2. [The Dataflow Shuffle service, liquid sharding, and stragglers](03-Google-Cloud-Dataflow-and-MillWheel-Internals/02-dataflow-shuffle-service-liquid-sharding-and-stragglers.md)
3. [Exactly-once: Bloom filters, the BigQuery Storage Write API, and Dataflow Prime](03-Google-Cloud-Dataflow-and-MillWheel-Internals/03-exactly-once-bloom-filters-BigQuery-storage-write-api-and-prime.md)

### Folder 04 contents

1. [Chandy-Lamport barriers: aligned vs. unaligned checkpoints](04-Apache-Flink-Runtime-Checkpointing-and-State/01-chandy-lamport-barriers-aligned-vs-unaligned-checkpoints.md)
2. [RocksDB LSM tuning vs. Flink 2.x ForSt disaggregated state](04-Apache-Flink-Runtime-Checkpointing-and-State/02-rocksdb-lsm-tuning-vs-flink-2-forst-disaggregated-state.md)
3. [Credit-based network flow control and buffer debloating](04-Apache-Flink-Runtime-Checkpointing-and-State/03-credit-based-network-flow-control-and-buffer-debloating.md)

### Folder 05 contents

1. [Push vs. pull shuffle, sort-merge, and remote shuffle services](05-Distributed-Shuffle-Skew-and-Join-Mechanics/01-push-vs-pull-shuffle-sort-merge-and-remote-shuffle-services.md)
2. [Mitigating data skew: salting, fan-out, and broadcast joins](05-Distributed-Shuffle-Skew-and-Join-Mechanics/02-mitigating-data-skew-salting-fanout-and-broadcast-joins.md)
3. [Temporal joins, interval joins, and state TTL with compaction filters](05-Distributed-Shuffle-Skew-and-Join-Mechanics/03-temporal-joins-interval-joins-and-state-ttl-compaction-filters.md)

### Folder 06 contents

1. [Streaming into Iceberg and BigQuery, and small-file compaction](06-Lakehouse-Sinks-Backpressure-and-FinOps/01-streaming-into-iceberg-bigquery-and-small-file-compaction.md)
2. [End-to-end exactly-once: two-phase commit and idempotency](06-Lakehouse-Sinks-Backpressure-and-FinOps/02-end-to-end-exactly-once-two-phase-commit-and-idempotency.md)
3. [Cloud FinOps: Dataflow vs. Flink on Kubernetes vs. Spark Structured Streaming](06-Lakehouse-Sinks-Backpressure-and-FinOps/03-cloud-finops-dataflow-vs-flink-k8s-vs-spark-structured-streaming.md)

### Folder 07 contents

1. [Beam stateful DoFn: timers, @OnWindowExpiration, and custom coders](07-Production-Java-Code-Blueprints/01-beam-stateful-dofn-timers-onwindowexpiration-and-custom-coders.md)
2. [High-throughput I/O in Beam: the wait anti-pattern and the async batch RPC DoFn](07-Production-Java-Code-Blueprints/02-beam-high-throughput-io-wait-antipattern-async-batch-rpc-dofn.md)
3. [Flink KeyedProcessFunction, Async I/O, and the RocksDB options factory](07-Production-Java-Code-Blueprints/03-flink-keyedprocessfunction-async-io-and-rocksdb-config-setter.md)
4. [Schema evolution, dead-letter routing, and the drain/update lifecycle](07-Production-Java-Code-Blueprints/04-schema-evolution-dead-letter-routing-and-drain-update-lifecycle.md)

### Folder 08 contents

1. [Architecture decision matrix: Beam/Dataflow vs. Flink vs. Spark Structured Streaming vs. Kafka Streams](08-FAANG-L7-Architecture-Playbook-and-Bar-Raiser-QA/01-architecture-decision-matrix-beam-dataflow-flink-spark-kafka-streams.md)
2. [25 FAANG L7 bar-raiser scenario Q&A chains](08-FAANG-L7-Architecture-Playbook-and-Bar-Raiser-QA/02-25-faang-l7-bar-raiser-scenario-qna-chains.md)
3. [Curated GitHub source code and paper reading list (with a 12-week study plan)](08-FAANG-L7-Architecture-Playbook-and-Bar-Raiser-QA/03-curated-github-source-code-and-paper-reading-list.md)

## How every file is structured

1. **First-principles math and internal mechanics:** state machines, equations, wire formats, and optimizer rules.
2. **Production Java 21 code blueprints:** a naive anti-pattern next to a production-hardened version (Beam SDK and Flink DataStream).
3. **Production failure modes and P99 debugging:** symptoms, metric signatures, root-cause physics, fix, and prevention.
4. **FAANG L7 bar-raiser Q&A chains:** the prompt, then the L5 textbook answer, then why that answer breaks at petabyte scale, then the L7 principal defense.

## Notation used throughout

| Symbol | Meaning |
|--------|---------|
| $E$, $t_e$ | Event-time domain; event timestamp of element $e$ (the producer's *claim*) |
| $P$, $p_e(S)$ | Processing-time domain; wall-clock instant at which stage $S$ observes $e$ |
| $W_S(p)$ | Watermark of stage $S$ at processing time $p$; $W: P \to E$, monotone non-decreasing |
| $\mathrm{IWM}(S)$, $\mathrm{OWM}(S)$ | Input / output watermark of stage $S$ |
| $[s, e)$ | Half-open window; `maxTimestamp = e − 1 ms` in both Beam and Flink |
| Beam watermark semantics | Watermark $W$ asserts that no more elements with $t < W$ will arrive (strict) |
| Flink watermark semantics | `Watermark(t)` asserts that no more elements with $t' \le t$ will arrive (non-strict) |

## Version baseline

- **Java 21** throughout. Records, sealed interfaces, and pattern-matching `switch` are used where they make the code clearer.
- **Apache Beam Java SDK 2.6x+.** Beam Java still uses Joda-Time `Instant`/`Duration`; the portability protos use µs.
- **Apache Flink 1.20 LTS and 2.x.** Code uses `java.time.Duration` window APIs and `open(OpenContext)`. The legacy `Time` class and
  `SourceFunction`/`SinkFunction` are gone in 2.0.
- Claims that depend on the version are marked **⚠ verify**. Pin to the exact release you run before you rely on internal
  class names or defaults.
