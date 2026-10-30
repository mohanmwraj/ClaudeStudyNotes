# Apache Beam / Dataflow Pipeline and SQL Performance-Tuning Prompts

> **Folder 07 · File 3 of 4** · verified 2026-10-30 with Apache Beam Java SDK **2.77.0** and the DirectRunner (35 resolved JARs; JDK 25 runtime, `--release 21`). The PostgreSQL plans in L3 are synthetic, labelled as such.
> **Templates:** T4 Beam scaffolder and fusion/coder auditor, T7 PostgreSQL tuning from plan evidence.
> **Listings:**
> - `beam_fusion_coder_audit.py`: static pre-digest, 9 rules.
> - `BeamCoderLab.java`: real DirectRunner runs of the hazards.
> - `explain_plan_triage.py`: an `EXPLAIN (ANALYZE, BUFFERS)` digest.

---

## 0. Orientation

Both templates here are **evidence-first**. A Beam job that runs on one worker of forty, or a query that takes 1.9 s, can't be fixed by reading the code harder. The evidence lives elsewhere: the job graph, step timings, the plan's actual rows and buffers.

So each template takes a *pre-digested* evidence variable, produced by a script:
- `static_findings` and `job_evidence` for T4;
- `plan_digest` for T7.

That has three benefits:
1. Claude starts from facts instead of guesses.
2. The prompt stays small: L3's digest is 15 lines where a real plan can be thousands.
3. The same script verifies the fix afterwards (T7's verification runs it on before and after plans).

### 0.1 The twelve rules

1. **Feed evidence, not artefacts.** Digest job graphs and plans before they go in a prompt, and keep the raw file for the human. [inference + L1, L3]
2. **Fusion is the Dataflow optimiser's default.** An expensive fan-out behind a small source (`Create.of` of 3 partitions → expand to 3M records) runs on as many workers as the source had elements. Break it with `Redistribute.arbitrarily()` or `Reshuffle.viaRandomKey()` after the fan-out. In Beam 2.77 both exist and `Reshuffle` is not deprecated. [doc: Dataflow + measured: javap]
3. **GroupByKey rejects a non-deterministic key coder *at construction*:** `IllegalStateException: the keyCoder of a GroupByKey must be deterministic`. A `Serializable` key with an inferred `SerializableCoder` hits it. Use a deterministic coder (a `KvCoder` of `StringUtf8Coder`s, a schema, Avro or Proto). [measured: L2]
4. **No `SerializableCoder` anywhere.** It is slow, large on the wire, and non-deterministic, so it can't be a key. [doc + L2]
5. **Grouping an unbounded source in the GlobalWindow with the default trigger is rejected at construction:** "GroupByKey cannot be applied to non-bounded PCollection in the GlobalWindow without a trigger". Window first. [measured: L2]
6. **A DoFn with a non-serializable field passes construction and fails at `run()`:** `unable to serialize DoFnWithExecutionInformation`. Construction-only tests miss it; run the pipeline on the DirectRunner in CI. `javac -Xlint:serial` (JDK 18+) flags the field at compile time. [measured: L2]
7. **Clients belong in `@Setup` (create) and `@Teardown` (close)** as `transient` fields. Never create them per element or per bundle. [doc: Beam DoFn lifecycle + L2]
8. **Combine, don't GroupByKey-then-loop.** `Combine.perKey` / `Sum.longsPerKey()` lets the runner combine before the shuffle; `withHotKeyFanout` handles skew. [doc: Beam]
9. **Test late data explicitly with TestStream.** L2's pipeline emits an on-time pane of 15 and a late pane of 22 (accumulating), and drops an element past allowed lateness, all asserted with `PAssert.inOnTimePane` / `inLatePane`. [measured: L2]
10. **SQL: compare estimated and actual rows before proposing an index.** A 70× underestimate (L3) means stale or missing statistics. An index chosen on bad estimates may never be used. [doc: PostgreSQL + L3]
11. **Don't flag misestimates under a LIMIT that stopped early.** Planned 21,500, actual 50 under `Limit 50` is correct behaviour; L3 skips it. [doc: PostgreSQL + L3]
12. **Indexes on live tables are built `CONCURRENTLY`, outside a transaction,** in their own migration. With Flyway that means a non-transactional script (⚠ verify the mechanism for your Flyway version: 12.4.0 is Boot-managed). [doc: PostgreSQL]

---

## 1. First principles

### 1.1 Fusion: why the job used one worker [doc: Dataflow]

Dataflow fuses consecutive steps into stages to avoid serialising data between them. That is usually a win. Fusion also means parallelism is decided by the *first* step of the stage.

`Create.of(["p0","p1","p2"]) → ParDo(ExpandPartitionFn) → ParDo(EnrichFn)` fuses into one stage with three elements of input. At most three workers ever run Expand and Enrich, however many millions of records Expand emits.

A redistribution after the fan-out ends the stage, so the next stage is parallel over the expanded records. L1's rule BM01 finds the pattern statically. T4 asks Claude to confirm it against the job graph (`job_evidence`), because only the runner's plan proves fusion happened.

### 1.2 Coders: the three failure modes L2 ran [measured: L2]

| Hazard | When it fails | Message (Beam 2.77.0, DirectRunner) | Fix |
|---|---|---|---|
| `Serializable` key + `SerializableCoder` into `GroupByKey` | construction | `IllegalStateException: the keyCoder of a GroupByKey must be deterministic` | deterministic coder: `KvCoder.of(StringUtf8Coder…)`, a schema, Avro or Proto |
| Unbounded source → `GroupByKey`, GlobalWindow, default trigger | construction | `IllegalStateException: GroupByKey cannot be applied to non-bounded PCollection in the GlobalWindow without a trigger…` | `Window.into(FixedWindows…)` or an explicit trigger |
| DoFn with a non-serializable `HttpClient` field | **`run()`**, not construction | `IllegalArgumentException: unable to serialize DoFnWithExecutionInformation{…}` | `transient` field, created in `@Setup`, closed in `@Teardown` |

The third row corrected this KB's own first draft of T4. Its check said "construction succeeds, so DoFns serialize". Running L2 showed construction doesn't check, and the template's check now requires a DirectRunner `run()`.

### 1.3 Windows, triggers and late data [doc: Beam + measured: L2]

For "1-minute revenue per store, late data up to 10 minutes":

```java
Window.<KV<String, Long>>into(FixedWindows.of(Duration.standardMinutes(1)))
      .triggering(AfterWatermark.pastEndOfWindow().withLateFirings(AfterPane.elementCountAtLeast(1)))
      .withAllowedLateness(Duration.standardMinutes(10))
      .accumulatingFiredPanes()
```

L2's TestStream run:
- **On time:** 10 + 5 arrive before the watermark passes the window end, and the on-time pane fires 15.
- **Late:** 7 arrives late but within lateness. In accumulating mode the late pane is 22.
- **Too late:** 100 arrives after end + 10 minutes and is dropped.

In discarding mode the late pane would be 7, and the sink must then add, not replace. T4's INV-BEAM-6 forces that decision into the audit document, because it determines what the BigQuery table means.

### 1.4 Sinks: say the semantics [doc: Beam BigQueryIO]

The BigQuery Storage Write API has an exactly-once mode and an at-least-once mode (`STORAGE_API_AT_LEAST_ONCE`, cheaper and lower latency). Neither is wrong. The bug is not knowing which one you have.

L1 rule BM09 flags a `BigQueryIO` write with no `withMethod(...)`. T4 makes Claude state the method and the consumer's dedup key.

### 1.5 Reading a PostgreSQL plan the way T7 wants [doc: PostgreSQL EXPLAIN]

L3's synthetic "before" plan is a common real-world shape:
- **A 70× underestimate on `orders`** (planned 300, actual 21,034), with statistics 9 days stale.
- **A `Seq Scan` discarding 99.96% of 48M rows,** the hottest node at 1.1 s exclusive.
- **Three spills:** a hash that grew from 1 to 8 batches, a hashed aggregate that spilled 24 MB, and an external-merge sort of 41 MB.
- **About 1.01M shared blocks read** (≈ 7.7 GB of 8 kB pages).

T7's order of operations is deliberate:
1. Fix the estimates (`ANALYZE`; extended statistics on `(store_id, created_at)` if the columns correlate).
2. Then propose the index that serves the predicate *and* the sort: `(store_id, created_at DESC)`, so the `LIMIT 50` can stop early.
3. Then the join-side index on `order_lines(order_id)`.

L3's synthetic "after" plan shows the shape that should result: a nested loop over two index scans, 3.4 ms. Your own before/after pair, digested by the same script, is the verification.

---

## 2. Practice

### 2.1 T4: Beam / Dataflow scaffolder and fusion/coder auditor

```xml
<!-- t4_beam_pipeline_auditor.xml - scaffold or audit an Apache Beam (Java) pipeline for Dataflow: fusion, coders, keys, windows, sinks -->
<prompt id="T4" title="Apache Beam / Dataflow pipeline scaffolder and fusion/coder auditor">
  <variables>
    <var name="mode" kind="param" example="AUDIT">SCAFFOLD a new pipeline or AUDIT an existing one</var>
    <var name="pipeline_goal" kind="data" example="Read order events from Kafka, 1-minute revenue per store, write to BigQuery; late data up to 10 min.">what the pipeline must compute</var>
    <var name="pipeline_source" kind="data" example="(the pipeline's Java source, or 'none' in SCAFFOLD mode)">existing code to audit</var>
    <var name="static_findings" kind="data" example="(output of beam_fusion_coder_audit.py on the source)">the static auditor's findings, so you start from evidence</var>
    <var name="job_evidence" kind="data" example="Dataflow job graph: stage F3 fused Create+ExpandFn+Enrich, 1 worker busy of 40; GBK hot key store-42">job graph, step timings, worker metrics, errors</var>
  </variables>
  <context>
    <goal>{{pipeline_goal}}</goal>
    <source>{{pipeline_source}}</source>
    <static_findings>{{static_findings}}</static_findings>
    <job_evidence>{{job_evidence}}</job_evidence>
    <platform>Apache Beam Java SDK 2.77.0, DataflowRunner in production, DirectRunner in tests; Java 21.</platform>
  </context>
  <instructions>
    <step n="1">In AUDIT mode, confirm or reject each static finding against the source and the job evidence, then look for what static analysis cannot see. In SCAFFOLD mode, design the transform graph first and show it as a list of named steps with their PCollection types and coders.</step>
    <step n="2">Fusion: find every expensive fan-out that follows a small or slow source and would be fused into one stage; break it with Redistribute.arbitrarily() or Reshuffle.viaRandomKey(), placed after the fan-out.</step>
    <step n="3">Coders: give every PCollection element type an explicit, efficient coder (a schema via @DefaultSchema, or Avro or Proto); keys of GroupByKey, Combine.perKey and stateful DoFns must have deterministic coders.</step>
    <step n="4">Keys and aggregation: replace GroupByKey-then-sum with Combine.perKey; for skewed keys use withHotKeyFanout; state the key cardinality you assume.</step>
    <step n="5">Windows and triggers: unbounded inputs get a window, a trigger, allowed lateness and an accumulation mode that match the late-data rule.</step>
    <step n="6">DoFn lifecycle and sinks: clients created in @Setup and closed in @Teardown, never fields that cannot serialize; sink writes idempotent or exactly-once (BigQuery Storage Write API mode stated).</step>
    <step n="7">Write DirectRunner tests with TestPipeline and PAssert, including a late-data case with TestStream, run them, and report.</step>
  </instructions>
  <invariants>
    <inv id="INV-BEAM-1">No expensive ParDo is fused behind a source that produces few elements; each fan-out over 100x is followed by a redistribution.</inv>
    <inv id="INV-BEAM-2">No SerializableCoder on any PCollection; every key coder is deterministic.</inv>
    <inv id="INV-BEAM-3">Every per-key aggregation is a Combine with a combiner, not a GroupByKey followed by a loop.</inv>
    <inv id="INV-BEAM-4">Every unbounded PCollection reaching a grouping has a non-global window or an explicit trigger, plus allowed lateness.</inv>
    <inv id="INV-BEAM-5">DoFns hold no non-serializable fields; external clients live in @Setup and @Teardown.</inv>
    <inv id="INV-BEAM-6">Every sink's delivery semantics (at-least-once or exactly-once) is stated and the downstream consumer tolerates it.</inv>
  </invariants>
  <anti_goals>
    <no>No guessing about the runner's plan: claims about fusion cite the job graph or say they are predictions to check.</no>
    <no>No GlobalWindow with a default trigger on an unbounded source.</no>
    <no>No side inputs that grow without bound (a multi-gigabyte View.asMap rebuilt every window).</no>
    <no>No rewrite of the whole pipeline when the audit finds three local fixes.</no>
  </anti_goals>
  <output_contract>
    <file path="docs/pipeline-audit.md">findings table: id, evidence (source line or job metric), invariant, fix, expected effect, how to measure</file>
    <file path="src/main/java/.../pipeline/">the changed or new transforms</file>
    <file path="src/test/java/.../pipeline/">TestPipeline and PAssert tests, a TestStream late-data test</file>
    <report>Before and after: stage count, the coder of each grouped PCollection, and the test results.</report>
  </output_contract>
  <verification>
    <cmd>./mvnw -q test -Dtest='*PipelineTest'</cmd>
    <cmd>python beam_fusion_coder_audit.py src/main/java</cmd>
    <check ref="INV-BEAM-1">List each fan-out with its ratio and the redistribution after it.</check>
    <check ref="INV-BEAM-2">The static auditor reports no BM02/BM03 finding; a test constructs the pipeline (GroupByKey rejects a non-deterministic key coder at construction).</check>
    <check ref="INV-BEAM-3">The static auditor reports no BM04 finding.</check>
    <check ref="INV-BEAM-4">The TestStream test delivers an on-time, a late-within-lateness and a too-late element and asserts the panes.</check>
    <check ref="INV-BEAM-5">A DirectRunner test runs the pipeline end to end: a DoFn that cannot serialize passes construction and fails only at run().</check>
    <check ref="INV-BEAM-6">The audit document states each sink's semantics and the consumer's dedup key.</check>
  </verification>
  <task>Run the pipeline work in {{mode}} mode for the goal above, honouring every invariant, and deliver the files and report of the output contract.</task>
</prompt>
```

In AUDIT mode, fill `static_findings` with `python beam_fusion_coder_audit.py src/main/java`. Fill `job_evidence` from the Dataflow job page (stage graph, step wall time, worker counts) or `gcloud dataflow jobs describe`. Paste the stage list, not screenshots.

### 2.2 T7: PostgreSQL tuning from plan evidence

```xml
<!-- t7_sql_explain_tuning.xml - PostgreSQL query tuning from EXPLAIN (ANALYZE, BUFFERS) evidence, with migration-safe fixes -->
<prompt id="T7" title="PostgreSQL slow-query diagnosis and tuning from plan evidence">
  <variables>
    <var name="query" kind="data" example="SELECT ... FROM orders o JOIN order_lines l ON ... WHERE o.store_id = $1 AND o.created_at >= $2 ORDER BY o.created_at DESC LIMIT 50">the statement as the application sends it, with parameter types</var>
    <var name="plan_digest" kind="data" example="(output of explain_plan_triage.py on EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON))">the pre-digested plan, not the raw JSON</var>
    <var name="schema_facts" kind="data" example="orders 48M rows; indexes: pk(id), (customer_id); store_id has 1,200 distinct values; autovacuum last analyze 9 days ago">table sizes, indexes, statistics freshness</var>
    <var name="slo" kind="param" example="p99 under 40 ms at 300 calls/s">the latency target for this query</var>
  </variables>
  <context>
    <query>{{query}}</query>
    <plan>{{plan_digest}}</plan>
    <schema>{{schema_facts}}</schema>
    <platform>PostgreSQL 17; Flyway 12.4.0 migrations; the application uses prepared statements through the JDBC driver 42.7.14.</platform>
  </context>
  <instructions>
    <step n="1">State the bottleneck in one sentence, citing the plan node and its numbers (actual time, rows, loops, buffers).</step>
    <step n="2">For every scan and join in the digest, compare estimated with actual rows; a ratio beyond 10x in either direction is a statistics problem to fix before any index.</step>
    <step n="3">Propose at most three changes, ranked by expected effect, each with the predicate or ordering it serves, its write and storage cost, and the measurement that would confirm it.</step>
    <step n="4">Write each schema change as a Flyway migration that builds indexes with CREATE INDEX CONCURRENTLY outside a transaction, and each query rewrite with an argument that it returns the same rows, NULLs and duplicates included.</step>
    <step n="5">Say how to re-measure with the same parameter values, and whether the prepared statement may switch to a generic plan after five executions (plan_cache_mode).</step>
  </instructions>
  <invariants>
    <inv id="INV-SQL-1">Every claim cites a plan node and a number from the digest; nothing is inferred from the query text alone.</inv>
    <inv id="INV-SQL-2">Misestimates beyond 10x are addressed (ANALYZE, extended statistics, or a statistics target) before an index is proposed for that node.</inv>
    <inv id="INV-SQL-3">Each proposed index names the exact predicate and sort it serves and its cost on writes.</inv>
    <inv id="INV-SQL-4">Indexes on live tables are created CONCURRENTLY in a non-transactional migration.</inv>
    <inv id="INV-SQL-5">Each rewrite is shown to be semantically equivalent.</inv>
  </invariants>
  <anti_goals>
    <no>No index for every column in the WHERE clause.</no>
    <no>No configuration changes (work_mem, random_page_cost) as the first fix, and never globally for one query.</no>
    <no>No query hints or extensions the platform does not have.</no>
  </anti_goals>
  <output_contract>
    <file path="docs/perf/">diagnosis note: bottleneck, misestimates, ranked changes, measurements</file>
    <file path="src/main/resources/db/migration/">non-transactional migration for any new index</file>
    <report>A table of plan nodes cited (node, metric, value), then the ranked changes with expected and measured effect.</report>
  </output_contract>
  <verification>
    <cmd>python explain_plan_triage.py plan-before.json plan-after.json</cmd>
    <check ref="INV-SQL-1">Every sentence in the diagnosis that names a cost has a node reference from the digest.</check>
    <check ref="INV-SQL-2">The digest's misestimate list is empty after the statistics fix, or each remaining item is explained.</check>
    <check ref="INV-SQL-3">Each index line in the migration has a comment naming the predicate and sort.</check>
    <check ref="INV-SQL-4">The migration contains CONCURRENTLY and runs outside a transaction.</check>
    <check ref="INV-SQL-5">An equivalence test runs old and new query on the Testcontainers database and compares results.</check>
  </verification>
  <task>Diagnose why this query misses {{slo}} and propose the smallest safe changes that meet it, following every invariant.</task>
</prompt>
```

To capture the evidence for `plan_digest`, use the same parameter values as the slow call:

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) <the query with its real parameter values>;
```

Save the JSON as `plan-before.json` and paste the output of `python explain_plan_triage.py plan-before.json` as `plan_digest`. Run `EXPLAIN ANALYZE` against a replica or a production-sized copy: it executes the query.

---

## 3. Verified listings

### L1 · `beam_fusion_coder_audit.py`

**What it shows.** Nine regex rules over Beam Java source:
- BM01 fusion behind a small source;
- BM02 `SerializableCoder`;
- BM03 a `Serializable` grouping key without `@DefaultSchema`/`@DefaultCoder`;
- BM04 GroupByKey-then-loop;
- BM05 unwindowed grouping of an unbounded source;
- BM06 a non-transient client field in a DoFn;
- BM07 unbounded map side inputs;
- BM08 clients created per element or bundle;
- BM09 a BigQuery write without a stated method.

The BAD fixture triggers all nine; the GOOD one, none.

**What it does not show.** Anything type-resolved. It is a pre-digest for the prompt and a CI tripwire, not a compiler. L2 backs BM03, BM05 and BM06 with real runner behaviour.

```python
"""beam_fusion_coder_audit.py - static audit of Beam Java pipeline source for the hazards T4 targets, so the prompt starts
from evidence: fusion behind small sources, SerializableCoder, non-deterministic keys, GroupByKey-then-loop, unwindowed
unbounded grouping, non-serializable DoFn fields, per-element clients, unbounded side inputs, unstated sink semantics.
Heuristic (regex over source, no type resolution); BeamCoderLab.java shows the real DirectRunner behaviour behind
BM03, BM05 and BM06. Usage: python beam_fusion_coder_audit.py [src_dir]  (no argument: the BAD and GOOD fixtures)
"""
import pathlib
import re
import sys

SMALL_SOURCE = re.compile(r"Create\.of\(|Impulse\.create\(|FileIO\.match\(|FileIO\.matchAll\(")
FAN_OUT = re.compile(r"FlatMapElements|ParDo\.of\(new \w*(Expand|Explode|Split|FanOut|Fetch|Read)\w*")
REDISTRIBUTE = re.compile(r"Reshuffle\.|Redistribute\.")
GROUPING = re.compile(r"GroupByKey\.create\(|Combine\.perKey\(|Count\.perKey\(|Sum\.\w+PerKey\(|@StateId")
UNBOUNDED = re.compile(r"KafkaIO\.(?:<[^>]*>)?read|PubsubIO\.(?:<[^>]*>)?read|GenerateSequence\.from\([^)]*\)(?![^;]*\.to\()")
CLIENT_TYPES = r"(HttpClient|CloseableHttpClient|Connection|DataSource|KafkaProducer|Storage|BigQuery|JedisPool|RestTemplate)"


def audit(name, src):
    f = []
    line = lambda pos: src.count("\n", 0, pos) + 1
    for m in SMALL_SOURCE.finditer(src):
        fan = FAN_OUT.search(src, m.end())
        if fan and not REDISTRIBUTE.search(src, m.end(), fan.start()):
            f.append(("BM01", line(fan.start()), "fan-out fused behind a small source: add Redistribute.arbitrarily() "
                                                 "(or Reshuffle.viaRandomKey()) after it"))
    for m in re.finditer(r"SerializableCoder", src):
        f.append(("BM02", line(m.start()), "SerializableCoder: slow, and non-deterministic as a key; use a schema, Avro or Proto"))
    if GROUPING.search(src):
        for m in re.finditer(r"((?:@\w+(?:\([^)]*\))?\s+)*)(?:static\s+)?(?:final\s+)?(?:class|record)\s+(\w+)[^{]*"
                             r"implements[^{]*Serializable", src):
            annotations, cls = m.group(1), m.group(2)
            if not re.search(r"@DefaultSchema|@DefaultCoder", annotations) and re.search(rf"KV<{cls}\s*,", src):
                f.append(("BM03", line(m.start()), f"{cls} is a grouping key with an inferred SerializableCoder: "
                                                   "GroupByKey rejects non-deterministic key coders"))
    if re.search(r"GroupByKey\.create\(", src) and re.search(r"for\s*\([^:]+:[^;{]*getValue\(\)\s*\)", src):
        m = re.search(r"GroupByKey\.create\(", src)
        f.append(("BM04", line(m.start()), "GroupByKey followed by a loop over the values: use Combine.perKey (combiner "
                                           "lifting), withHotKeyFanout for skew"))
    if UNBOUNDED.search(src) and GROUPING.search(src) and not re.search(r"Window\.(into|<[^>]*>into|configure)", src):
        f.append(("BM05", line(GROUPING.search(src).start()), "grouping an unbounded source in the GlobalWindow without a "
                                                              "trigger: rejected at construction; add Window.into(...)"))
    for m in re.finditer(r"class\s+(\w+)\s+extends\s+DoFn<[^{]*\{(.*?)\n    \}", src, re.S):
        for fm in re.finditer(rf"\n\s+private\s+(?!transient)(?:final\s+)?{CLIENT_TYPES}\b[^;]*;", m.group(2)):
            f.append(("BM06", line(m.start(2) + fm.start() + 1), f"{m.group(1)} holds a non-transient {fm.group(1)}: constructs "
                                                             "fine, fails at run(); make it transient and create it in @Setup"))
        for hm in re.finditer(r"@(ProcessElement|StartBundle)[^{]*\{([^}]*)\}", m.group(2)):
            if re.search(r"new\s+\w*Client\w*\(|newHttpClient\(|getConnection\(", hm.group(2)):
                f.append(("BM08", line(m.start(2) + hm.start()), f"{m.group(1)} creates a client in @{hm.group(1)}: once "
                                                                 "per element/bundle; move it to @Setup, close in @Teardown"))
    for m in re.finditer(r"View\.as(Map|Multimap)\(", src):
        f.append(("BM07", line(m.start()), f"View.as{m.group(1)} side input: state its maximum size; it is broadcast "
                                           "to every worker"))
    for m in re.finditer(r"BigQueryIO\.(?:<[^>]*>)?write\w*\(\)(?:(?!;).)*;", src, re.S):
        if "withMethod(" not in m.group(0):
            f.append(("BM09", line(m.start()), "BigQueryIO write without withMethod(...): state Storage Write API "
                                               "exactly-once or at-least-once"))
    return sorted(f, key=lambda x: (x[1], x[0]))


BAD = """public class RevenuePipeline {
    static class StoreDay implements Serializable {
        String store; String day;
    }

    static class EnrichFn extends DoFn<Order, Order> {
        private final HttpClient http = HttpClient.newHttpClient();
        @ProcessElement
        public void process(@Element Order o, OutputReceiver<Order> out) {
            Connection c = dataSource.getConnection();
            out.output(o);
        }
    }

    public static void main(String[] args) {
        Pipeline p = Pipeline.create(options);
        PCollection<String> partitions = p.apply(Create.of(List.of("p0", "p1", "p2")));
        PCollection<Order> orders = partitions
            .apply(ParDo.of(new ExpandPartitionFn()))
            .apply(ParDo.of(new EnrichFn()))
            .setCoder(SerializableCoder.of(Order.class));
        PCollectionView<Map<String, Store>> stores = storeTable.apply(View.asMap());
        PCollection<Order> live = p.apply(KafkaIO.<String, Order>read().withTopic("orders"));
        live.apply(MapElements.into(kvs).via(o -> KV.of(new StoreDay(o.store(), o.day()), o.amount())))
            .apply(GroupByKey.create())
            .apply(ParDo.of(new DoFn<KV<StoreDay, Iterable<Long>>, KV<StoreDay, Long>>() {
                @ProcessElement
                public void sum(ProcessContext c) {
                    long t = 0;
                    for (Long v : c.element().getValue()) { t += v; }
                    c.output(KV.of(c.element().getKey(), t));
                }
            }));
        orders.apply(BigQueryIO.<Order>write().to("proj:ds.orders").withFormatFunction(Order::toRow));
    }
}
"""

GOOD = """public class RevenuePipeline {
    @DefaultSchema(JavaFieldSchema.class)
    static class StoreDay implements Serializable {
        public String store; public String day;
    }

    static class EnrichFn extends DoFn<Order, Order> {
        private transient HttpClient http;
        @Setup
        public void setup() { http = HttpClient.newHttpClient(); }
        @ProcessElement
        public void process(@Element Order o, OutputReceiver<Order> out) {
            out.output(o);
        }
    }

    public static void main(String[] args) {
        Pipeline p = Pipeline.create(options);
        PCollection<String> partitions = p.apply(Create.of(List.of("p0", "p1", "p2")));
        PCollection<Order> orders = partitions
            .apply(Redistribute.arbitrarily())
            .apply(ParDo.of(new ExpandPartitionFn()))
            .apply(Redistribute.arbitrarily())
            .apply(ParDo.of(new EnrichFn()));
        PCollection<Order> live = p.apply(KafkaIO.<String, Order>read().withTopic("orders"));
        live.apply(Window.<Order>into(FixedWindows.of(Duration.standardMinutes(1))).withAllowedLateness(Duration.standardMinutes(10)))
            .apply(MapElements.into(kvs).via(o -> KV.of(new StoreDay(o.store(), o.day()), o.amount())))
            .apply(Sum.longsPerKey());
        orders.apply(BigQueryIO.<Order>write().to("proj:ds.orders").withMethod(Method.STORAGE_WRITE_API));
    }
}
"""


def report(title, findings):
    print(f"== {title}: {len(findings)} finding(s) ==")
    for rule, ln, msg in findings:
        print(f"  {rule} line {ln}: {msg}")


if __name__ == "__main__":
    if len(sys.argv) > 1:
        total = 0
        for path in sorted(pathlib.Path(sys.argv[1]).rglob("*.java")):
            found = audit(path.name, path.read_text(encoding="utf-8"))
            total += len(found)
            if found:
                report(str(path), found)
        sys.exit(1 if total else 0)
    bad = audit("BAD", BAD)
    report("BAD RevenuePipeline.java", bad)
    report("GOOD RevenuePipeline.java", audit("GOOD", GOOD))
    print(f"\nBAD triggers {len({r for r, _, _ in bad})} of 9 rules: {', '.join(sorted({r for r, _, _ in bad}))}")
```

**Output (verified):**

```text
== BAD RevenuePipeline.java: 9 finding(s) ==
  BM03 line 2: StoreDay is a grouping key with an inferred SerializableCoder: GroupByKey rejects non-deterministic key coders
  BM06 line 7: EnrichFn holds a non-transient HttpClient: constructs fine, fails at run(); make it transient and create it in @Setup
  BM08 line 8: EnrichFn creates a client in @ProcessElement: once per element/bundle; move it to @Setup, close in @Teardown
  BM01 line 19: fan-out fused behind a small source: add Redistribute.arbitrarily() (or Reshuffle.viaRandomKey()) after it
  BM02 line 21: SerializableCoder: slow, and non-deterministic as a key; use a schema, Avro or Proto
  BM07 line 22: View.asMap side input: state its maximum size; it is broadcast to every worker
  BM04 line 25: GroupByKey followed by a loop over the values: use Combine.perKey (combiner lifting), withHotKeyFanout for skew
  BM05 line 25: grouping an unbounded source in the GlobalWindow without a trigger: rejected at construction; add Window.into(...)
  BM09 line 34: BigQueryIO write without withMethod(...): state Storage Write API exactly-once or at-least-once
== GOOD RevenuePipeline.java: 0 finding(s) ==

BAD triggers 9 of 9 rules: BM01, BM02, BM03, BM04, BM05, BM06, BM07, BM08, BM09
```

### L2 · `BeamCoderLab.java`

**What it shows.** Real Beam 2.77.0 pipelines on the DirectRunner:
- three hazards, each next to its fix, with the exact exception and *when* it is raised (construction vs `run()`);
- a TestStream pipeline whose on-time and late panes `PAssert` checks.

**What it does not show.** Dataflow itself: fusion decisions, autoscaling, the hot-key fan-out effect, Storage Write API semantics. Those need a real job.

**Build notes.**
- Classpath: `beam-sdks-java-core` + `beam-runners-direct-java` 2.77.0, plus `junit` 4.13.2 and `hamcrest` for PAssert.
- Compiled with `-Xlint:all,-path,-classfile -Werror`. The two disabled categories are about the dependency JARs (missing manifest Class-Path entries, a missing findbugs annotation type), not this code.
- Run with `--enable-native-access=ALL-UNNAMED --sun-misc-unsafe-memory-access=allow`. Otherwise JDK 25 prints warnings about Beam's vendored protobuf and snappy.

```java
// BeamCoderLab.java - the Beam hazards from T4, run for real on the DirectRunner (Beam 2.77.0): three that the SDK rejects
// at pipeline construction (a non-deterministic GroupByKey key coder, an unwindowed GroupByKey on an unbounded source, a
// DoFn that cannot serialize), each next to its fix, and a late-data pipeline whose panes PAssert checks via TestStream.
import java.io.Serializable;
import java.net.http.HttpClient;
import java.util.List;
import org.apache.beam.runners.direct.DirectRunner;
import org.apache.beam.sdk.Pipeline;
import org.apache.beam.sdk.coders.KvCoder;
import org.apache.beam.sdk.coders.SerializableCoder;
import org.apache.beam.sdk.coders.StringUtf8Coder;
import org.apache.beam.sdk.coders.VarLongCoder;
import org.apache.beam.sdk.io.GenerateSequence;
import org.apache.beam.sdk.options.PipelineOptions;
import org.apache.beam.sdk.options.PipelineOptionsFactory;
import org.apache.beam.sdk.testing.PAssert;
import org.apache.beam.sdk.testing.TestStream;
import org.apache.beam.sdk.transforms.Create;
import org.apache.beam.sdk.transforms.DoFn;
import org.apache.beam.sdk.transforms.GroupByKey;
import org.apache.beam.sdk.transforms.MapElements;
import org.apache.beam.sdk.transforms.ParDo;
import org.apache.beam.sdk.transforms.Sum;
import org.apache.beam.sdk.transforms.windowing.AfterPane;
import org.apache.beam.sdk.transforms.windowing.AfterWatermark;
import org.apache.beam.sdk.transforms.windowing.FixedWindows;
import org.apache.beam.sdk.transforms.windowing.IntervalWindow;
import org.apache.beam.sdk.transforms.windowing.Window;
import org.apache.beam.sdk.values.KV;
import org.apache.beam.sdk.values.PCollection;
import org.apache.beam.sdk.values.TimestampedValue;
import org.apache.beam.sdk.values.TypeDescriptors;
import org.joda.time.Duration;
import org.joda.time.Instant;

public final class BeamCoderLab {
    record StoreDay(String store, String day) implements Serializable {}

    @SuppressWarnings("serial")   // javac -Xlint:serial flags this field at compile time; suppressed to show the runtime check
    static final class EnrichWithFieldClient extends DoFn<String, String> {
        private final HttpClient client = HttpClient.newHttpClient();

        @ProcessElement
        public void process(@Element String s, OutputReceiver<String> out) {
            out.output(s + ":" + client.version());
        }
    }

    static final class EnrichWithSetupClient extends DoFn<String, String> {
        private static final long serialVersionUID = 1L;
        private transient HttpClient client;

        @Setup
        public void setup() {
            client = HttpClient.newHttpClient();                   // one client per DoFn instance, not per element
        }

        @ProcessElement
        public void process(@Element String s, OutputReceiver<String> out) {
            out.output(s + ":" + client.version());
        }

        @Teardown
        public void teardown() {
            client.close();
        }
    }

    static Pipeline pipeline() {
        PipelineOptions options = PipelineOptionsFactory.create();
        options.setRunner(DirectRunner.class);
        return Pipeline.create(options);
    }

    static void rejected(String label, Runnable build) {
        try {
            build.run();
            System.out.println("  BAD  " + label + ": NOT rejected");
        } catch (RuntimeException e) {
            String msg = String.valueOf(e.getMessage()).replaceAll("@[0-9a-f]{4,}", "@<hash>").lines().findFirst().orElse("");
            System.out.println("  BAD  " + label + ": " + e.getClass().getSimpleName() + ": "
                    + (msg.length() > 150 ? msg.substring(0, 150) + "..." : msg));
        }
    }

    public static void main(String[] args) {
        System.out.println("1. GroupByKey key coder (INV-BEAM-2)");
        rejected("SerializableCoder key", () -> pipeline()
                .apply(Create.of(KV.of(new StoreDay("s1", "2026-10-30"), 5L))
                        .withCoder(KvCoder.of(SerializableCoder.of(StoreDay.class), VarLongCoder.of())))
                .apply(GroupByKey.create()));
        Pipeline good1 = pipeline();
        PCollection<KV<KV<String, String>, Long>> sums = good1
                .apply(Create.of(KV.of(KV.of("s1", "2026-10-30"), 5L), KV.of(KV.of("s1", "2026-10-30"), 7L))
                        .withCoder(KvCoder.of(KvCoder.of(StringUtf8Coder.of(), StringUtf8Coder.of()), VarLongCoder.of())))
                .apply(Sum.longsPerKey());
        PAssert.that(sums).containsInAnyOrder(List.of(KV.of(KV.of("s1", "2026-10-30"), 12L)));
        good1.run().waitUntilFinish();
        System.out.println("  GOOD KvCoder(StringUtf8, StringUtf8) key + Sum.longsPerKey: ran, PAssert passed (12)");

        System.out.println("2. Unbounded source into GroupByKey (INV-BEAM-4)");
        rejected("GlobalWindow, default trigger", () -> pipeline()
                .apply(GenerateSequence.from(0).withRate(10, Duration.standardSeconds(1)))
                .apply(MapElements.into(TypeDescriptors.kvs(TypeDescriptors.strings(), TypeDescriptors.longs()))
                        .via((Long n) -> KV.of("store-" + n % 3, 1L)))
                .apply(GroupByKey.create()));
        pipeline().apply(GenerateSequence.from(0).withRate(10, Duration.standardSeconds(1)))
                .apply(MapElements.into(TypeDescriptors.kvs(TypeDescriptors.strings(), TypeDescriptors.longs()))
                        .via((Long n) -> KV.of("store-" + n % 3, 1L)))
                .apply(Window.into(FixedWindows.of(Duration.standardMinutes(1))))
                .apply(GroupByKey.create());
        System.out.println("  GOOD Window.into(FixedWindows 1 min) first: pipeline constructs");

        System.out.println("3. DoFn serialization (INV-BEAM-5)");
        Pipeline bad3 = pipeline();
        bad3.apply(Create.of("a")).apply(ParDo.of(new EnrichWithFieldClient()));
        System.out.println("  BAD  HttpClient field: pipeline constructs without complaint (no check at ParDo.of)");
        rejected("HttpClient field, at run()", () -> bad3.run().waitUntilFinish());
        Pipeline good3 = pipeline();
        PCollection<String> enriched = good3.apply(Create.of("a", "b")).apply(ParDo.of(new EnrichWithSetupClient()));
        PAssert.that(enriched).containsInAnyOrder("a:HTTP_2", "b:HTTP_2");
        good3.run().waitUntilFinish();
        System.out.println("  GOOD transient client from @Setup, closed in @Teardown: ran, PAssert passed");

        System.out.println("4. Late data, TestStream (INV-BEAM-4)");
        Instant t0 = Instant.parse("2026-10-30T10:00:00Z");
        TestStream<KV<String, Long>> events = TestStream.create(KvCoder.of(StringUtf8Coder.of(), VarLongCoder.of()))
                .advanceWatermarkTo(t0)
                .addElements(TimestampedValue.of(KV.of("s1", 10L), t0.plus(Duration.standardSeconds(10))),
                        TimestampedValue.of(KV.of("s1", 5L), t0.plus(Duration.standardSeconds(20))))
                .advanceWatermarkTo(t0.plus(Duration.standardMinutes(2)))          // window closes: on-time pane
                .addElements(TimestampedValue.of(KV.of("s1", 7L), t0.plus(Duration.standardSeconds(30))))   // late, in time
                .advanceWatermarkTo(t0.plus(Duration.standardMinutes(20)))         // past end + allowed lateness
                .addElements(TimestampedValue.of(KV.of("s1", 100L), t0.plus(Duration.standardSeconds(40)))) // too late
                .advanceWatermarkToInfinity();
        Pipeline good4 = pipeline();
        PCollection<KV<String, Long>> perMinute = good4.apply(events)
                .apply(Window.<KV<String, Long>>into(FixedWindows.of(Duration.standardMinutes(1)))
                        .triggering(AfterWatermark.pastEndOfWindow().withLateFirings(AfterPane.elementCountAtLeast(1)))
                        .withAllowedLateness(Duration.standardMinutes(10))
                        .accumulatingFiredPanes())
                .apply(Sum.longsPerKey());
        IntervalWindow minute = new IntervalWindow(t0, t0.plus(Duration.standardMinutes(1)));
        PAssert.that(perMinute).inOnTimePane(minute).containsInAnyOrder(List.of(KV.of("s1", 15L)));
        PAssert.that(perMinute).inLatePane(minute).containsInAnyOrder(List.of(KV.of("s1", 22L)));
        PAssert.that(perMinute).inWindow(minute).containsInAnyOrder(List.of(KV.of("s1", 15L), KV.of("s1", 22L)));
        good4.run().waitUntilFinish();
        System.out.println("  GOOD on-time pane 15, late pane 22 (accumulating 15+7), the too-late 100 dropped: PAssert passed");
    }
}
```

**Output (verified):**

```text
1. GroupByKey key coder (INV-BEAM-2)
  BAD  SerializableCoder key: IllegalStateException: the keyCoder of a GroupByKey must be deterministic
  GOOD KvCoder(StringUtf8, StringUtf8) key + Sum.longsPerKey: ran, PAssert passed (12)
2. Unbounded source into GroupByKey (INV-BEAM-4)
  BAD  GlobalWindow, default trigger: IllegalStateException: GroupByKey cannot be applied to non-bounded PCollection in the GlobalWindow without a trigger. Use a Window.into or Window.triggering transform prior ...
  GOOD Window.into(FixedWindows 1 min) first: pipeline constructs
3. DoFn serialization (INV-BEAM-5)
  BAD  HttpClient field: pipeline constructs without complaint (no check at ParDo.of)
  BAD  HttpClient field, at run(): IllegalArgumentException: unable to serialize DoFnWithExecutionInformation{doFn=BeamCoderLab$EnrichWithFieldClient@<hash>, mainOutputTag=Tag<output>, sideInputMapping={}, schem...
  GOOD transient client from @Setup, closed in @Teardown: ran, PAssert passed
4. Late data, TestStream (INV-BEAM-4)
  GOOD on-time pane 15, late pane 22 (accumulating 15+7), the too-late 100 dropped: PAssert passed
```

### L3 · `explain_plan_triage.py`

**What it shows.** A digest of `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`:
- execution time and buffers;
- the three hottest nodes by *exclusive* time;
- misestimates of 10× or more, excluding nodes a `LIMIT` stopped early;
- red flags: filter-heavy sequential scans, sorts spilled to disk, hashes that grew batches, aggregates that spilled.

It runs on two synthetic plans in PostgreSQL 17's JSON shape and reports the digest size against the raw JSON.

**What it does not show.** Real plans, which this harness can't produce (no database here). Parallel plans (`Gather`, workers) and JIT details are not specially handled. Run it on your own `plan-before.json` / `plan-after.json`.

```python
"""explain_plan_triage.py - digest PostgreSQL EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) into the evidence T7 needs, so the
prompt carries 30 lines instead of the raw plan: hottest nodes by exclusive time, estimate-vs-actual misestimates (not
flagging nodes a LIMIT stopped early), filter-heavy sequential scans, sorts/hashes/aggregates that spilled to disk, buffer
totals. Usage: python explain_plan_triage.py before.json [after.json]. With no arguments it digests two SYNTHETIC plans
(PostgreSQL 17 JSON shape, numbers constructed for the example, not captured from a database).
"""
import json
import sys


def walk(node, depth=0, under_limit=False):
    yield node, depth, under_limit
    for child in node.get("Plans", []):
        yield from walk(child, depth + 1, under_limit or node["Node Type"] == "Limit")


def label(n):
    rel = f" on {n['Relation Name']}" if "Relation Name" in n else ""
    idx = f" using {n['Index Name']}" if "Index Name" in n else ""
    return f"{n['Node Type']}{rel}{idx}"


def digest(plan):
    root = plan[0]["Plan"]
    nodes = list(walk(root))
    out = [f"execution {plan[0]['Execution Time']:,.1f} ms, planning {plan[0]['Planning Time']:,.1f} ms; "
           f"buffers: shared hit {root.get('Shared Hit Blocks', 0):,}, read {root.get('Shared Read Blocks', 0):,}, "
           f"temp written {root.get('Temp Written Blocks', 0):,} (8 kB blocks)"]
    timed = []
    for n, depth, _ in nodes:
        total = n["Actual Total Time"] * n["Actual Loops"]
        children = sum(c["Actual Total Time"] * c["Actual Loops"] for c in n.get("Plans", []))
        timed.append((total - children, n, depth))
    out.append("hottest nodes (exclusive ms):")
    for excl, n, depth in sorted(timed, key=lambda t: -t[0])[:3]:
        out.append(f"  [{depth}] {label(n)}: {excl:,.1f} ms, rows {n['Actual Rows'] * n['Actual Loops']:,} "
                   f"(loops {n['Actual Loops']:,})")
    out.append("misestimates (|actual/plan| >= 10x):")
    found = False
    for n, depth, under_limit in nodes:
        actual, planned = max(n["Actual Rows"], 1), max(n["Plan Rows"], 1)
        ratio = actual / planned
        if under_limit and ratio < 1:
            continue                                     # a LIMIT above stopped this node early: expected, not stale stats
        if ratio >= 10 or ratio <= 0.1:
            found = True
            out.append(f"  [{depth}] {label(n)}: planned {planned:,}, actual {actual:,} "
                       f"({'under' if ratio > 1 else 'over'}estimated {max(ratio, 1 / ratio):,.0f}x)")
    if not found:
        out.append("  none")
    out.append("red flags:")
    flags = []
    for n, depth, _ in nodes:
        removed = n.get("Rows Removed by Filter", 0) * n["Actual Loops"]
        kept = n["Actual Rows"] * n["Actual Loops"]
        if n["Node Type"] == "Seq Scan" and removed > 9 * max(kept, 1):
            flags.append(f"  [{depth}] {label(n)}: filter '{n.get('Filter')}' discards {removed / (removed + kept):.2%} "
                         f"of {removed + kept:,} rows")
        if n.get("Sort Space Type") == "Disk":
            flags.append(f"  [{depth}] {label(n)}: {n['Sort Method']} spilled {n['Sort Space Used']:,} kB "
                         f"(sort key {', '.join(n['Sort Key'])})")
        if n.get("Hash Batches", 1) > max(1, n.get("Original Hash Batches", 1)):
            flags.append(f"  [{depth}] {label(n)}: hash grew to {n['Hash Batches']} batches from "
                         f"{n['Original Hash Batches']} (work_mem exceeded)")
        if n.get("Disk Usage", 0) > 0:
            flags.append(f"  [{depth}] {label(n)}: aggregate spilled {n['Disk Usage']:,} kB in {n.get('HashAgg Batches')} batches")
    out += flags or ["  none"]
    return out


def scan(rel, rows, plan_rows, ms, removed, filt, read, hit=0, **extra):
    return {"Node Type": "Seq Scan", "Relation Name": rel, "Plan Rows": plan_rows, "Actual Rows": rows, "Actual Loops": 1,
            "Actual Total Time": ms, "Filter": filt, "Rows Removed by Filter": removed, "Shared Read Blocks": read,
            "Shared Hit Blocks": hit, **extra}


BEFORE = [{"Planning Time": 0.9, "Execution Time": 1912.4, "Plan": {
    "Node Type": "Limit", "Plan Rows": 50, "Actual Rows": 50, "Actual Loops": 1, "Actual Total Time": 1911.8,
    "Shared Hit Blocks": 2_310, "Shared Read Blocks": 1_010_400, "Temp Written Blocks": 11_480, "Plans": [{
        "Node Type": "Sort", "Plan Rows": 300, "Actual Rows": 50, "Actual Loops": 1, "Actual Total Time": 1911.7,
        "Sort Key": ["o.created_at DESC"], "Sort Method": "external merge", "Sort Space Used": 41_200, "Sort Space Type": "Disk",
        "Plans": [{
            "Node Type": "Aggregate", "Strategy": "Hashed", "Plan Rows": 300, "Actual Rows": 21_034, "Actual Loops": 1,
            "Actual Total Time": 1830.2, "HashAgg Batches": 5, "Disk Usage": 24_576, "Plans": [{
                "Node Type": "Hash Join", "Plan Rows": 900, "Actual Rows": 61_220, "Actual Loops": 1,
                "Actual Total Time": 1795.0, "Hash Cond": "(l.order_id = o.id)", "Plans": [
                    scan("order_lines", 9_604_112, 9_600_000, 620.4, 0, None, 410_200),
                    {"Node Type": "Hash", "Plan Rows": 300, "Actual Rows": 21_034, "Actual Loops": 1,
                     "Actual Total Time": 1101.3, "Hash Batches": 8, "Original Hash Batches": 1, "Plans": [
                         scan("orders", 21_034, 300, 1099.8, 47_978_966,
                              "((store_id = $1) AND (created_at >= $2))", 600_200)]}]}]}]}]}}]

AFTER = [{"Planning Time": 1.1, "Execution Time": 3.4, "Plan": {
    "Node Type": "Limit", "Plan Rows": 50, "Actual Rows": 50, "Actual Loops": 1, "Actual Total Time": 3.2,
    "Shared Hit Blocks": 1_204, "Shared Read Blocks": 37, "Temp Written Blocks": 0, "Plans": [{
        "Node Type": "Nested Loop", "Plan Rows": 21_500, "Actual Rows": 50, "Actual Loops": 1, "Actual Total Time": 3.1,
        "Plans": [
            {"Node Type": "Index Scan", "Relation Name": "orders", "Index Name": "idx_orders_store_created",
             "Index Cond": "((store_id = $1) AND (created_at >= $2))", "Plan Rows": 21_500, "Actual Rows": 50,
             "Actual Loops": 1, "Actual Total Time": 0.4},
            {"Node Type": "Index Scan", "Relation Name": "order_lines", "Index Name": "idx_order_lines_order_id",
             "Index Cond": "(order_id = o.id)", "Plan Rows": 3, "Actual Rows": 4, "Actual Loops": 50,
             "Actual Total Time": 0.05}]}]}}]


if __name__ == "__main__":
    plans = [json.load(open(p, encoding="utf-8")) for p in sys.argv[1:3]] if len(sys.argv) > 1 else [BEFORE, AFTER]
    for name, plan in zip(["before", "after"], plans):
        lines = digest(plan)
        raw = len(json.dumps(plan, indent=2))
        print(f"== {name}: digest {len(lines)} lines, {sum(map(len, lines)):,} chars from {raw:,} chars of plan JSON ==")
        print("\n".join(lines))
    if len(plans) == 2:
        b, a = plans[0][0]["Execution Time"], plans[1][0]["Execution Time"]
        print(f"\nexecution {b:,.1f} ms -> {a:,.1f} ms ({b / a:,.0f}x)")
```

**Output (verified):**

```text
== before: digest 15 lines, 913 chars from 2,970 chars of plan JSON ==
execution 1,912.4 ms, planning 0.9 ms; buffers: shared hit 2,310, read 1,010,400, temp written 11,480 (8 kB blocks)
hottest nodes (exclusive ms):
  [5] Seq Scan on orders: 1,099.8 ms, rows 21,034 (loops 1)
  [4] Seq Scan on order_lines: 620.4 ms, rows 9,604,112 (loops 1)
  [1] Sort: 81.5 ms, rows 50 (loops 1)
misestimates (|actual/plan| >= 10x):
  [2] Aggregate: planned 300, actual 21,034 (underestimated 70x)
  [3] Hash Join: planned 900, actual 61,220 (underestimated 68x)
  [4] Hash: planned 300, actual 21,034 (underestimated 70x)
  [5] Seq Scan on orders: planned 300, actual 21,034 (underestimated 70x)
red flags:
  [1] Sort: external merge spilled 41,200 kB (sort key o.created_at DESC)
  [2] Aggregate: aggregate spilled 24,576 kB in 5 batches
  [4] Hash: hash grew to 8 batches from 1 (work_mem exceeded)
  [5] Seq Scan on orders: filter '((store_id = $1) AND (created_at >= $2))' discards 99.96% of 48,000,000 rows
== after: digest 9 lines, 405 chars from 1,288 chars of plan JSON ==
execution 3.4 ms, planning 1.1 ms; buffers: shared hit 1,204, read 37, temp written 0 (8 kB blocks)
hottest nodes (exclusive ms):
  [2] Index Scan on order_lines using idx_order_lines_order_id: 2.5 ms, rows 200 (loops 50)
  [2] Index Scan on orders using idx_orders_store_created: 0.4 ms, rows 50 (loops 1)
  [1] Nested Loop: 0.2 ms, rows 50 (loops 1)
misestimates (|actual/plan| >= 10x):
  none
red flags:
  none

execution 1,912.4 ms -> 3.4 ms (562x)
```

The "after" digest has no misestimates although two nodes planned 21,500 rows and returned 50. Both sit under the `Limit`, which stopped them early: that is the rule 11 exemption at work.

---

## 4. Failure modes

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| F1 | Job with 40 workers, 1 busy | Fan-out fused behind a 3-element source | `Redistribute.arbitrarily()` after the fan-out (BM01) |
| F2 | Pipeline won't start: "keyCoder … must be deterministic" | `Serializable` key with a `SerializableCoder` | Deterministic coder (BM02/BM03) |
| F3 | Streaming pipeline rejected at construction | Unbounded grouping in the GlobalWindow | `Window.into` (BM05) |
| F4 | Unit tests pass, the job fails at start | DoFn not serializable; tests never called `run()` | DirectRunner `run()` in CI; `transient` + `@Setup` (BM06) |
| F5 | Connection storms from workers | Client per element or bundle | `@Setup`/`@Teardown` (BM08) |
| F6 | Late events double-counted downstream | Accumulating panes into an appending sink | Choose the accumulation mode to match the sink (INV-BEAM-6) |
| F7 | New index unused | Misestimate left unfixed; planner still prefers a seq scan | Statistics first (INV-SQL-2) |
| F8 | Index creation locked the table in production | `CREATE INDEX` without `CONCURRENTLY`, inside a transaction | INV-SQL-4 |
| F9 | Fast in psql, slow from the app | The prepared statement switched to a generic plan after five executions | Test with the app's parameter types; check `plan_cache_mode` |

---

## 5. Staff-level drills

<details><summary><b>D1 · "The job is slow. Why not paste the whole pipeline and ask Claude to optimise it?"</b></summary>

**Naive answer.** Claude can read the code and spot problems.

**Why it fails.** Most Beam performance problems are about the *runner's* plan: fusion, stage parallelism, hot keys, shuffle volume. None of that is in the source. Without evidence the model will propose plausible generic changes, often several, and you can't tell which one mattered.

**Staff answer.** Run the static auditor and paste its findings plus the stage graph and step timings into T4 AUDIT. Require each finding to cite a line or a metric (`docs/pipeline-audit.md`). Fix the top one and measure.
</details>

<details><summary><b>D2 · "Claude proposed five indexes. What do you ask next?"</b></summary>

**Staff answer.** "Which plan node does each one change, and what does each cost on writes?" That is INV-SQL-3.

If the answer cites a 70× misestimate, fix the statistics first and re-plan. Often one composite index serving predicate and sort (`(store_id, created_at DESC)`) replaces all five. T7 caps proposals at three for this reason.
</details>

<details><summary><b>D3 · "How do we stop Beam regressions in CI without a Dataflow job per PR?"</b></summary>

**Staff answer.**
- The static auditor as a tripwire (exit 1 on findings).
- DirectRunner tests that *run* every pipeline, which catches the serialization class at `run()` (L2 row 3).
- A TestStream test per windowing rule.
- Construction-time checks (coders, windows) come free with any test that builds the pipeline.
- A nightly Dataflow job on a sample covers fusion and scaling, which only the real runner shows.
</details>

---

## 6. Checklist

- [ ] T4 AUDIT always gets `static_findings` and `job_evidence`; findings cite lines or metrics.
- [ ] No `SerializableCoder`; deterministic key coders; Combine over GroupByKey-and-loop.
- [ ] Unbounded inputs windowed, with lateness and an accumulation mode matched to the sink.
- [ ] Every pipeline has a DirectRunner test that calls `run()`, plus a TestStream late-data test.
- [ ] T7 gets a digest, not raw JSON; statistics are fixed before indexes; indexes built `CONCURRENTLY`.
- [ ] Before and after plans digested with the same script, attached to the PR.

---

## 7. References

- Apache Beam programming guide (coders, windowing, triggers, DoFn lifecycle): <https://beam.apache.org/documentation/programming-guide/>
- Dataflow pipeline lifecycle and fusion optimization: <https://docs.cloud.google.com/dataflow/docs/pipeline-lifecycle>
- Beam Java SDK 2.77.0 on Maven Central: <https://repo1.maven.org/maven2/org/apache/beam/beam-sdks-java-core/2.77.0/>
- PostgreSQL `EXPLAIN`: <https://www.postgresql.org/docs/current/sql-explain.html> and using EXPLAIN: <https://www.postgresql.org/docs/current/using-explain.html>
- PostgreSQL `CREATE INDEX … CONCURRENTLY`: <https://www.postgresql.org/docs/current/sql-createindex.html>
- PostgreSQL planner statistics (extended statistics): <https://www.postgresql.org/docs/current/planner-stats.html>

Previous: [02 · Kafka outbox, saga, Resilience4j](02-kafka-outbox-saga-and-resilience4j-implementation-prompt-templates.md) · Next: [04 · Testcontainers, ArchUnit, legacy refactoring](04-testcontainers-integration-testing-archunit-and-legacy-refactoring-prompts.md) · [KB README](../README.md)
