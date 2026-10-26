# 03 · Curated GitHub Source Code and Paper Reading List

> **Folder:** `08-FAANG-L7-Architecture-Playbook-and-Bar-Raiser-QA/` · **File 3 of 3**
> **Purpose:** the primary sources behind every folder of this KB, with *what to extract* from each, plus a source-code
> map for reading the real implementations, and a 12-week study plan.
> **Prev:** [02 · 25 scenario Q&A chains](02-25-faang-l7-bar-raiser-scenario-qna-chains.md)

> **On paths.** Repository layouts move between releases (Beam merged its construction module into the SDK core; Flink
> 2.x relocated packages). Paths below reflect recent layouts. If one has moved, **search the repository for the class
> name**, which is stable far longer than paths. Pin to a release tag when you read (e.g., `release-2.0` /
> `v2.6x.0`) so line references stay valid.

---

## 1. Papers, grouped by the question they answer

### 1.1 Foundations: time, snapshots, and the dataflow model

| Paper | Venue | Extract | KB |
|-------|-------|---------|----|
| Chandy & Lamport, *Distributed Snapshots: Determining Global States of Distributed Systems* | ACM TOCS 1985 | the consistent-cut definition; markers; channel state | [04-01] |
| Lamport, *Time, Clocks, and the Ordering of Events in a Distributed System* | CACM 1978 | why wall clocks aren't orderings; logical time | [01-01] |
| Akidau et al., *The Dataflow Model* | PVLDB 2015 | What/Where/When/How; triggers; accumulation; retractions; windowing as GBK-and-window | [01-*] |
| Akidau et al., *MillWheel: Fault-Tolerant Stream Processing at Internet Scale* | PVLDB 2013 | low watermarks; per-key exactly-once; strong/weak productions; sequencer tokens; Bloom filters | [01-02], [03-01], [03-03] |
| Chambers et al., *FlumeJava: Easy, Efficient Data-Parallel Pipelines* | PLDI 2010 | deferred evaluation; the five optimizer passes; MSCR | [02-01] |
| Dean & Ghemawat, *MapReduce* | OSDI 2004 | combiners; backup tasks; the shuffle model | [02-01], [05-01] |
| Carbone et al., *Lightweight Asynchronous Snapshots for Distributed Dataflows* | arXiv 2015 | ABS: barrier alignment empties channel state in DAGs | [04-01] |
| Carbone et al., *State Management in Apache Flink* | PVLDB 2017 | keyed/operator state, key groups, rescaling, incremental checkpoints | [04-*] |
| Begoli et al., *Watermarks in Stream Processing Systems: Flink vs. Dataflow* | PVLDB 2021 | formal watermark semantics; in-band vs. out-of-band propagation | [01-02] |
| Begoli et al., *One SQL to Rule Them All* | SIGMOD 2019 | time-varying relations; changelogs; temporal joins; EMIT | [01-03], [05-03] |
| Tucker et al., *Exploiting Punctuation Semantics in Continuous Data Streams* | IEEE TKDE 2003 | punctuations, the generalization of watermarks | [01-02] |
| Li et al., *Out-of-Order Processing: A New Architecture for High-Performance Stream Systems* | PVLDB 2008 | low-watermark heartbeats; OOP vs. in-order | [01-02] |

### 1.2 Windows, aggregation, and sketches

| Paper | Venue | Extract | KB |
|-------|-------|---------|----|
| Li et al., *Semantics and Evaluation Techniques for Window Aggregates in Data Streams* | SIGMOD 2005 | window IDs; semantics | [01-01] |
| Li et al., *No Pane, No Gain* | SIGMOD Record 2005 | pane/slice-based sliding windows | [01-03] |
| Tangwongsan et al., *General Incremental Sliding-Window Aggregation* | PVLDB 2015 | FlatFAT, non-invertible sliding aggregation | [01-03] |
| Traub et al., *Scotty: Efficient Window Aggregation for Out-of-Order Stream Processing* | ICDE 2018 | general stream slicing with out-of-order data | [01-03] |
| Gray et al., *Data Cube* | DMKD 1997 | distributive/algebraic/holistic aggregates | [01-01], [02-01] |
| Flajolet et al., *HyperLogLog*; Heule et al., *HyperLogLog in Practice* (HLL++) | AofA 2007; EDBT 2013 | mergeable distinct counts | [05-02] |
| Cormode & Muthukrishnan, *Count-Min Sketch* | J. Algorithms 2005 | heavy hitters, hot-key detection | [05-02] |
| Metwally et al., *Space-Saving* | ICDT 2005 | deterministic top-k | [05-02] |
| Dunning & Ertl, *t-digest*; Karnin et al., *KLL* | 2019; FOCS 2016 | mergeable quantiles | [02-01] |
| Chan, Golub & LeVeque, *Algorithms for Computing the Sample Variance* | Amer. Statistician 1983 | the parallel variance merge | [02-01] |

### 1.3 Storage engines and state

| Paper | Venue | Extract | KB |
|-------|-------|---------|----|
| O'Neil et al., *The Log-Structured Merge-Tree* | Acta Informatica 1996 | LSM fundamentals | [04-02] |
| Dong et al., *Optimizing Space Amplification in RocksDB* | CIDR 2017 | leveled compaction trade-offs, dynamic levels | [04-02] |
| Athanassoulis et al., *The RUM Conjecture* | EDBT 2016 | read/update/memory trade-off | [04-02] |
| Dayan et al., *Monkey: Optimal Navigable Key-Value Store* | SIGMOD 2017 | per-level Bloom filter allocation | [04-02] |
| Chang et al., *Bigtable* | OSDI 2006 | row-level atomicity (MillWheel's backing store) | [03-01] |
| Corbett et al., *Spanner* | OSDI 2012 | TrueTime; external consistency | [01-01], [03-01] |
| Bloom, *Space/Time Trade-offs in Hash Coding with Allowable Errors* | CACM 1970 | Bloom filters | [03-03] |

### 1.4 Shuffle, skew, stragglers, and scheduling

| Paper | Venue | Extract | KB |
|-------|-------|---------|----|
| Shen et al., *Magnet: Push-based Shuffle Service* | PVLDB 2020 | push-merge shuffle | [05-01] |
| Zhang et al., *Riffle: Optimized Shuffle Service* | EuroSys 2018 | node-level merge of map outputs | [05-01] |
| Dean & Barroso, *The Tail at Scale* | CACM 2013 | tail amplification (the min over many inputs) | [01-02], [03-02] |
| Ananthanarayanan et al., *Mantri* | OSDI 2010 | outlier mitigation in MapReduce | [03-02] |
| Zaharia et al., *LATE* | OSDI 2008 | speculative execution in heterogeneous clusters | [03-02] |
| Kwon et al., *SkewTune* | SIGMOD 2012 | runtime skew mitigation | [05-02] |
| DeWitt et al., *Practical Skew Handling in Parallel Joins* | VLDB 1992 | join skew | [05-02] |
| Nasir et al., *The Power of Both Choices* | ICDE 2015 | partial key grouping for streaming skew | [05-02] |
| Graefe, *Implementing Sorting in Database Systems* | ACM CSUR 2006 | external sort, normalized keys | [05-01] |

### 1.5 Transactions, exactly-once, and fault tolerance

| Paper | Venue | Extract | KB |
|-------|-------|---------|----|
| Gray, *Notes on Data Base Operating Systems* | 1978 | two-phase commit | [06-02] |
| Gray & Lamport, *Consensus on Transaction Commit* | ACM TODS 2006 | 2PC failure modes; Paxos Commit | [06-02] |
| Helland, *Life beyond Distributed Transactions* | CIDR 2007 | idempotent entities and messages over 2PC | [06-02] |
| Young, *A First Order Approximation to the Optimum Checkpoint Interval* | CACM 1974 | √(2CM) | [04-01] |
| Kung et al., *Credit-Based Flow Control for ATM Networks* | SIGCOMM 1994 | credits vs. TCP HOL blocking | [04-03] |
| Little, *A Proof for the Queuing Formula L = λW* | Oper. Res. 1961 | in-flight sizing everywhere | [04-03], [07-02] |
| Armbrust et al., *Delta Lake*; *Lakehouse* | PVLDB 2020; CIDR 2021 | ACID tables over object storage | [06-01] |

---

## 2. Books, blog series, and talks

| Source | Why |
|--------|-----|
| Akidau, Chernyak, Lax, *Streaming Systems* (O'Reilly, 2018) | the canonical long-form treatment of the Dataflow Model, watermarks, exactly-once, streams and tables |
| Kleppmann, *Designing Data-Intensive Applications* (O'Reilly, 2017) | encoding and evolution, transactions, stream processing fundamentals |
| Hueske & Kalavri, *Stream Processing with Apache Flink* (O'Reilly, 2019) | Flink DataStream, state, and time in practice (pre-2.x APIs) |
| T. Akidau, *Streaming 101* and *Streaming 102* (O'Reilly Radar, 2015–2016) | the shortest correct intro to event time, watermarks, and triggers |
| R. Lax, *After Lambda: Exactly-once processing in Google Cloud Dataflow*, Parts 1–3 (2017) | Dataflow's dedup, Bloom filters, GC, sinks |
| E. Kirpichov & M. Denielou, *No shard left behind: dynamic work rebalancing* (2016) | liquid sharding |
| E. Kirpichov, *Splittable DoFn* proposal + Beam blog on SDF I/O | the claim protocol |
| K. Knowles, *Stateful processing* / *Timely and stateful processing with Apache Beam* (2017) | state and timers in Beam |
| N. Kruber, *A Deep-Dive into Flink's Network Stack* + *Vol. 2* (2019) | credits, buffers, backpressure metrics |
| Flink blog posts on unaligned checkpoints, buffer debloating, and the Flink 2.0 release (disaggregated state) | the modern Flink runtime |
| M. Brooker, *Exponential Backoff and Jitter* (AWS, 2015) | retry design |

---

## 3. Source-code map (read the real implementations)

### 3.1 Apache Beam: `github.com/apache/beam`

| Concept | Where to look (class names are the stable handle) | KB |
|---------|----------------------------------------------------|----|
| Windowing, triggers, panes | `sdks/java/core/src/main/java/org/apache/beam/sdk/transforms/windowing/` (`Window`, `AfterWatermark`, `PaneInfo`, `TimestampCombiner`, `Sessions`, `MergeOverlappingIntervalWindows`) | [01-03] |
| GBK-with-windowing engine | `runners/core-java/src/main/java/org/apache/beam/runners/core/` (`ReduceFnRunner`, `WatermarkHold`, `PaneInfoTracker`, `MergingActiveWindowSet`, `LateDataDroppingDoFnRunner`, `triggers/*StateMachine*`) | [01-02], [01-03] |
| `DoFn` runner, timer validation | `runners/core-java/.../SimpleDoFnRunner` (timer output-timestamp rules) | [01-02 §7.3] |
| Combine and lifting | `sdks/java/core/.../transforms/Combine.java`, `CombineFnTester`; Python `apache_beam/runners/portability/fn_api_runner/translations.py` (`lift_combiners`, `greedily_fuse`) | [02-01] |
| Fusion (portable) | `GreedyPipelineFuser`, `ExecutableStage` (formerly `runners/core-construction-java`; moved into the SDK core's construction utilities in recent releases ⚠) | [02-01] |
| Redistribution | `sdks/java/core/.../transforms/Reshuffle.java`, `Redistribute.java`, `GroupIntoBatches.java` | [02-01], [07-02] |
| SDF | `sdks/java/core/.../transforms/splittabledofn/` (`OffsetRangeTracker`, `GrowableOffsetRangeTracker`, `WatermarkEstimators`); `.../io/range/OffsetRange` | [02-03] |
| State and timers API | `sdks/java/core/.../state/` (`StateSpecs`, `OrderedListState`, `Timer`) | [07-01] |
| Coders | `sdks/java/core/.../coders/` (`Coder#verifyDeterministic`, `InstantCoder`, `CustomCoder`), `.../testing/CoderProperties` | [02-03] |
| Schemas | `sdks/java/core/.../schemas/` (`RowCoder`, `Select`, `Group`, `JavaFieldSchema`) | [02-03] |
| Fn API protos | `model/fn-execution/src/main/proto/org/apache/beam/model/fn_execution/v1/beam_fn_api.proto` | [02-02] |
| Runner API protos | `model/pipeline/src/main/proto/org/apache/beam/model/pipeline/v1/beam_runner_api.proto` (standard URNs, coders, requirements) | [02-02] |
| Java SDK harness | `sdks/java/harness/src/main/java/org/apache/beam/fn/harness/` (`FnHarness`, `control/ProcessBundleHandler`, `state/*`) | [02-02] |
| Dataflow worker + Windmill client | `runners/google-cloud-dataflow-java/worker/` (streaming worker, Windmill client, state cache, `KeyCommitTooLargeException`); `windmill.proto` under the worker's `windmill` module | [03-01] |
| Flink runner | `runners/flink/` (`DoFnOperator`, `ExecutableStageDoFnOperator`) | [02-02 §5] |
| KafkaIO | `sdks/java/io/kafka/` (`KafkaIO`, `ReadFromKafkaDoFn`, `TimestampPolicy`, `CustomTimestampPolicyWithLimitedDelay`) | [01-02 §5.2] |
| BigQueryIO (Storage Write API) | `sdks/java/io/google-cloud-platform/src/main/java/org/apache/beam/sdk/io/gcp/bigquery/` (`StorageApiWritesShardedRecords`, `StorageApiWriteUnshardedRecords`, `RowMutationInformation`) | [03-03 §4] |
| Sorter extension | `sdks/java/extensions/sorter/` (`SortValues`, `BufferedExternalSorter`) | [03-02] |

### 3.2 Apache Flink: `github.com/apache/flink`

| Concept | Where to look | KB |
|---------|---------------|----|
| Checkpoint coordination | `flink-runtime/.../checkpoint/CheckpointCoordinator` | [04-01] |
| Barrier handling (aligned/unaligned) | `flink-streaming-java/.../runtime/io/checkpointing/` (`SingleCheckpointBarrierHandler`, `CheckpointBarrierTracker`) | [04-01] |
| Channel state (unaligned) | `flink-runtime/.../checkpoint/channel/` (`ChannelStateWriter`) | [04-01 §4] |
| Watermark generation | `flink-core/.../api/common/eventtime/` (`WatermarkStrategy`, `BoundedOutOfOrdernessWatermarks`, `WatermarksWithIdleness`, `WatermarkOutputMultiplexer`) | [01-02] |
| Watermark combining | `StatusWatermarkValve` (search the class) | [01-02 §6.2] |
| Timers | `flink-streaming-java/.../api/operators/InternalTimerServiceImpl` | [01-02 §2.2] |
| Window operator | `flink-streaming-java/.../runtime/operators/windowing/` (`WindowOperator`, `MergingWindowSet`, `EvictingWindowOperator`) | [01-03] |
| Network stack | `flink-runtime/.../io/network/` (`partition/ResultPartition`, `partition/consumer/RemoteInputChannel`, `buffer/NetworkBufferPool`, `netty/*Credit*`); buffer debloating: `BufferDebloater` (search) | [04-03] |
| RocksDB backend | `flink-state-backends/flink-statebackend-rocksdb/` (`RocksDBKeyedStateBackend`, options factories, memory management) | [04-02] |
| ForSt backend (2.x) | `flink-state-backends/` ForSt module (search `ForSt`) ⚠ | [04-02 §4] |
| State V2 / async execution | search `StateFuture`, `AsyncExecutionController` | [04-02 §4.1] |
| TTL | `flink-runtime/.../state/ttl/` (`TtlStateFactory`); compaction filter in `ververica/frocksdb` | [05-03 §5] |
| Interval and temporal joins | `flink-streaming-java/.../operators/co/IntervalJoinOperator`; `flink-table/flink-table-runtime/.../operators/join/temporal/` | [05-03] |
| Window TVF slicing | `flink-table/flink-table-runtime/.../operators/window/` (slice assigners) | [01-03 §8] |
| Sink V2 | `flink-core/.../api/connector/sink2/` (`Sink`, `SupportsCommitter`, `CommittingSinkWriter`, `Committer`) | [06-02] |
| Async I/O | `flink-streaming-java/.../api/operators/async/AsyncWaitOperator`; retry: `.../util/retryable/AsyncRetryStrategies` | [07-03] |
| State Processor API | `flink-libraries/flink-state-processing-api/` (`SavepointReader`, `SavepointWriter`) | [07-04] |
| FLIPs | `cwiki.apache.org/confluence/display/FLINK/` (FLIP-27, 76, 143/191, 148, 158, 182/217, 183, 227, 232, 235, 263, 271, 306, 373, 423–428) | throughout |

### 3.3 Connectors and adjacent systems

| Repository | Read | KB |
|------------|------|----|
| `github.com/apache/flink-connector-kafka` | `KafkaSource` (split enumerator, per-split watermarks), `KafkaSink` (transactional ID handling, abort-on-restore) | [06-02] |
| `github.com/apache/flink-kubernetes-operator` | the `flink-autoscaler` module (scaling algorithm, metrics windows) | [06-03] |
| `github.com/apache/iceberg` | `core/` (snapshot producers, commit retries, sequence numbers), `flink/` (writer + committer, max-committed checkpoint ID), `spark/` actions (`RewriteDataFiles`, `ExpireSnapshots`) | [06-01] |
| `github.com/apache/kafka` | the transaction coordinator, LSO and read_committed fetch logic, the `RackAwareReplicaSelector` | [06-02], [06-03] |
| `github.com/facebook/rocksdb` | `db/compaction/`, `table/block_based/`, `util/bloom*`, write stall logic (`db/column_family.cc`) | [04-02] |
| `github.com/ververica/frocksdb` | the Flink fork with the TTL compaction filter | [05-03] |
| ForSt repository (Ververica / Flink community) ⚠ verify the location | disaggregated LSM | [04-02] |
| `github.com/apache/celeborn` | push-based remote shuffle; partition splitting; replication | [05-01] |
| `github.com/apache/spark` | `UnsafeShuffleWriter`, `ExternalSorter`, AQE skew-join rules | [05-01], [05-02] |
| `github.com/GoogleCloudPlatform/DataflowTemplates` | production Beam patterns (DLQs, Pub/Sub → BigQuery, CDC) | [07-*] |

---

## 4. How to read source code productively

1. **Start from a test, not from `main`.** Unit tests (`ReduceFnRunnerTest`, `WindowOperatorTest`,
   `CheckpointCoordinatorTest`, `OffsetRangeTrackerTest`) state the invariants in executable form.
2. **Trace one record end to end** through one mechanism (e.g., a late element through `LateDataDroppingDoFnRunner` →
   `ReduceFnRunner` → `WatermarkHold`), writing down every state read and write.
3. **Map each class to a KB equation or invariant.** For example, `WatermarkHold#addElementHold` maps to "holds can't go
   behind the output watermark" [01-02 §7.2].
4. **Read the FLIP or design doc before the code,** then diff what shipped against what was proposed. The gaps are where
   the hard problems were.
5. **Pin versions.** Record the tag you read in your notes.

---

## 5. A 12-week study plan

| Week | Focus | Read | Do |
|------|-------|------|----|
| 1 | Time domains, the four questions | Dataflow Model paper; Streaming 101/102; [01-01] | implement event-time counts in Beam and Flink; run the two-speed determinism test |
| 2 | Watermarks and holds | MillWheel §4–5; Begoli 2021; [01-02] | reproduce an idle-partition stall and fix it with lag-aware idleness; reproduce an `EARLIEST` hold |
| 3 | Windows, panes, accumulation | [01-03]; *No Pane, No Gain* | sliced 24 h sliding sum; pane-versioned upsert sink |
| 4 | FlumeJava and fusion | FlumeJava §4; [02-01] | reproduce the gzip fan-out trap; fix it with `Redistribute`; prove `CombineFn` laws in CI |
| 5 | Portability and the Fn API | `beam_fn_api.proto`; [02-02] | trace a bundle on the portable Flink runner; measure bundle sizes |
| 6 | SDF and coders | the SDF proposal; [02-03] | split-everywhere tests for a line reader; a coder determinism suite |
| 7 | Dataflow internals | MillWheel §6; Lax blogs; Kirpichov blog; [03-*] | hot-key experiment; Storage Write API exactly-once vs. at-least-once comparison |
| 8 | Flink checkpoints | Chandy-Lamport; ABS; [04-01] | induce backpressure and compare aligned, alignment-timeout, and unaligned checkpoint sizes |
| 9 | State backends | LSM / RUM / Monkey; [04-02] | RocksDB metrics dashboard; options factory; a ForSt experiment (2.x) |
| 10 | Flow control, shuffle, skew | Kung 1994; Magnet; [04-03], [05-01], [05-02] | bottleneck-finder script; salted aggregation; broadcast vs. salted join |
| 11 | Joins, TTL, sinks, exactly-once | One SQL; [05-03], [06-01], [06-02] | temporal join with an idle dimension; Iceberg compaction; Kafka EOS timeout drill |
| 12 | Blueprints, FinOps, interview drills | [06-03], [07-*], [08-*] | build the fraud engine and the telemetry DoFn; cost attribution query; answer all 25 scenarios aloud |

---

## 6. Final checklist: the L7 mental model in twelve lines

1. Completeness is unknowable, so watermarks are promises and lateness is a policy.
2. Holds constrain *output* watermarks. Monotonicity makes poisoning permanent.
3. Windows extend the key. Panes form a changelog. Accumulating + versioned upserts converge.
4. Fusion trades parallelism for serialization. Lifting trades CPU and memory for shuffle bytes.
5. The bundle is the unit of commit and retry. Side effects must be idempotent.
6. Claim before you emit. Key coders must be deterministic and injective.
7. The key is the atom of consistency and serialization. Hot keys are fixed in the key space.
8. Exactly-once = atomic commit + dedup + idempotent/transactional effects + fencing.
9. Checkpoint time ≈ in-flight bytes ÷ drain rate. Debloat, and decouple with unaligned when needed.
10. LSM physics (W/R/S amplification) and Little's law govern state backends, local or disaggregated.
11. Every join's state is its retention policy. TTL is a correctness trade.
12. Cost follows bytes moved, idle capacity, requests, cross-AZ traffic, and people. Measure $/M events.

---

**End of the knowledge base.** Return to the [README](../README.md) for the full index.
