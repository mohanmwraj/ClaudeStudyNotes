# 03 · Hybrid Search in SQL and CDC Ingestion: PostgreSQL 18, a pgvector-Style Operator, and Kafka

> **Folder:** `07-Production-Code-Blueprints-Java-and-Python/` · **File 3 of 4**
> **Anchoring systems and research:** PostgreSQL **18.6** (full-text search, GIN, generated columns,
> `INSERT … ON CONFLICT … WHERE`, `EXPLAIN`) · pgvector (`vector`, `halfvec`, `<=>`, HNSW, iterative index scans) ·
> Apache Kafka **4.2.2** in KRaft mode (per-partition ordering, consumer offsets, idempotent producer) ·
> G. Cormack, C. Clarke, S. Büttcher, *Reciprocal Rank Fusion* (SIGIR 2009) · M. Kleppmann, *Designing
> Data-Intensive Applications*, ch. 11 (change data capture).
> **Code baseline:** Java 21 (JDK 25.0.4) with an **embedded Kafka KRaft broker** (spring-kafka-test 4.1.2) and an
> **embedded PostgreSQL 18.6** (zonky embedded-postgres 2.2.2), JDBC 42.7.14, all in one process, with no installs ·
> Python 3.10+ (stdlib).
> **Previous:** [02 · Python MCPServer, LangGraph and the vLLM client](02-python-mcpserver-langgraph-agent-and-vllm-streaming-client.md) ·
> **Next:** [04 · LLM gateway: semantic cache, token rate limits, OTel GenAI](04-llm-gateway-semantic-cache-token-rate-limiting-and-otel-genai.md)

---

## 0. The thesis in one paragraph

A RAG index is a **materialized view of source systems**, and its correctness property is convergence: after any
sequence of deliveries, duplicates, replays and crashes, every document's chunks equal what its latest version says,
including *who may see them*.

The lab pushes 583 CDC events through a real Kafka broker into a real PostgreSQL 18: creates, shrinks from 5 to 3
chunks, 30 ACL revocations, 43 deletes, and 60 duplicates and stale replays including a backfill of a pre-revocation
snapshot. It kills both consumers mid-stream. Results:

| Consumer | Stale-version chunks | Orphan chunks | Resurrected chunks | Wrong-ACL chunks | Revoked user retrieves |
|---|---|---|---|---|---|
| Per-chunk upsert | 332 | 258 | 21 | 50 | 12 chunks |
| Version-gated replacement with tombstones | 0 | 0 | 0 | 0 | 0 chunks |

The rest of the data plane fits in one SQL statement: full-text and vector legs, RRF fusion, tenant and ACL
pre-filtering. The executed plan shows why plain Postgres needs an ANN index at scale: the vector leg computes a
distance for **every row the filter admits**.

---

## 1. First principles

### 1.1 Convergence under at-least-once delivery

Kafka gives **order within a partition** and **at-least-once** delivery to a consumer that commits offsets after its
side effects. Replays come from more places than consumer restarts: backfills, reprocessing, producer retries, and
dual pipelines. A sink converges only if all of these hold:

1. **Per-key ordering.** Partition by `doc_id`, so one document's events are totally ordered on one partition.
2. **A monotonic version gate.** Apply an event only if its version is greater than the stored one:
   `INSERT INTO doc_versions … ON CONFLICT (doc_id) DO UPDATE … WHERE doc_versions.version < EXCLUDED.version
   RETURNING version`. A returned row means "apply"; no row means duplicate or stale, which is a no-op. This makes
   the sink idempotent and immune to stale replays.
3. **Tombstones.** A delete updates the version row to `deleted = true` and removes the chunks. The row stays at
   least as long as the longest replay horizon (backfills included), so an old upsert cannot resurrect the document.
4. **Whole-document replacement.** Delete all chunks of the document and insert the new set in the same transaction.
   A per-chunk upsert leaves chunks 3 and 4 behind when a document shrinks to 3 chunks: the lab's 258 orphans, which
   still match queries with deleted text.
5. **DB commit before offset commit.** A crash between the two causes redelivery, which point 2 makes harmless.
   Committing offsets first loses events.

With one source per document, one version per document suffices. When content and ACLs come from different systems
on different streams, use per-field versions (Folder 04 File 03), or a stale content event can roll back a fresh ACL.

### 1.2 Why a revoked user still sees the document

The naive sink's revoked-user leak (12 chunks) needs no exotic failure. It takes one backfill job that re-publishes
a snapshot taken before the revocation, which is routine during migrations. Without a version gate the stale event
overwrites the new ACL. That is a security incident caused by an ordering bug, and only a monotonic gate prevents it.

### 1.3 Hybrid search in one statement

- **Lexical leg.** A generated column `tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', body)) STORED` has a
  GIN index; `plainto_tsquery` builds the query; `ts_rank_cd` orders it.
  - `ts_rank_cd` is a cover-density rank, **not BM25**: it has no IDF and no term-frequency saturation. For BM25 in
    Postgres use an extension (for example ParadeDB's `pg_search` or VectorChord-bm25; ⚠ verify availability) or an
    external engine.
  - `plainto_tsquery` ANDs the terms (`'carrier' & 'delay' & 'credit'`), so long queries lose recall.
    `websearch_to_tsquery` or an OR-query suits a hybrid lexical leg better.
- **Vector leg.** pgvector stores `vector(d)` and orders by `embedding <=> $q` (cosine distance) with an HNSW or
  IVFFlat index. The lab has no pgvector, so it defines the same operator on `float8[]`
  (`CREATE OPERATOR <=> … FUNCTION = cosine_distance`). That proves the SQL shape but gives no index, which §1.4
  quantifies.
- **Fusion.** Each leg computes `row_number()` over its own order and keeps its top 20. `UNION ALL` merges them, and
  `GROUP BY` sums `1/(60 + r)`. Results that both legs agree on (`via lex+vec`) rise to the top.
- **Filters inside each leg.** `tenant = $t` (btree) and `acl && $groups` (GIN on `text[]`) restrict both legs
  *before* ranking. That is ACL pre-filtering (Folder 04 File 03). With an ANN index, the filter interacts with the
  graph search: post-filtering starves results, and pgvector's iterative index scans address that (Folder 03
  File 01).

### 1.4 Reading the executed plan

With sequential scans disabled to mimic a large table, PostgreSQL 18 chose a bitmap index scan on the tenant index
for both legs. Each leg is then: nested loop with the query CTE → sort by `ts_rank_cd` or by `embedding <=> qv` →
`WindowAgg` → `Limit`.

The vector leg **sorts every tenant row by distance**. The capacity lab prices that: about 1.5 KFLOP per row at
d = 768, so 100,000 rows after filtering cost about 8 ms, while 10M rows cost at least 768 ms. A single small tenant
is fine; anything large needs HNSW or IVF, and then filtered ANN search is the hard problem.

### 1.5 Capacity, lag and re-embedding

From `pg_hybrid_capacity_lab.py`:

- **Index size.** About 3.35 KB per HNSW element at d = 768, m = 16 (vector, element and neighbour tuples). That is
  consistent with Folder 03's exact hnswlib figure of 3,228.5 B plus Postgres tuple headers. 10M chunks need a
  **31 GiB** index plus a 47 GiB heap. `halfvec` cuts the index to 17 GiB; re-rank with full precision if recall
  drops (Folder 03 File 03). The HNSW build is fast only if the graph fits in `maintenance_work_mem`.
- **CDC lag.** A backlog drains in `backlog / (μ − λ)`. A consumer with 10% headroom (220/s against 200/s of
  arrivals) needs **139 hours** to drain a 10M-event backlog; 2× headroom needs 13.9 hours. Run re-indexes on a
  separate backfill pipeline so a model migration never delays a live ACL revocation.
- **Re-embedding.** 10M chunks × 350 tokens = 3.5B tokens: about 24 h on one L4, 3.9 h on one H100, 0.5 h on
  8×H100 with a small encoder. Version the column (`embedding_v2`), backfill, dual-read, cut over, and never mix two
  embedding models in one index.

---

## 2. The production DDL with pgvector (not executed here)

The lab's PostgreSQL has no pgvector, and loading a downloaded extension binary is out of bounds for this KB's
harness. The shape below is from the pgvector README (⚠ verify option names against your pgvector version).

```sql
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE chunks (
  doc_id      text      NOT NULL,
  chunk_no    int       NOT NULL,
  doc_version bigint    NOT NULL,
  tenant      text      NOT NULL,
  acl         text[]    NOT NULL,
  body        text      NOT NULL,
  tsv         tsvector  GENERATED ALWAYS AS (to_tsvector('english', body)) STORED,
  embedding   vector(768) NOT NULL,                   -- or halfvec(768) to halve index memory
  PRIMARY KEY (doc_id, chunk_no));

CREATE INDEX ON chunks USING gin (tsv);
CREATE INDEX ON chunks USING gin (acl);
CREATE INDEX ON chunks (tenant);
CREATE INDEX chunks_embedding_hnsw ON chunks
  USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

SET maintenance_work_mem = '32GB';                    -- before CREATE INDEX: keep the graph build in memory
SET hnsw.ef_search = 100;                             -- recall/latency knob at query time
SET hnsw.iterative_scan = relaxed_order;              -- pgvector >= 0.8: keep scanning when filters drop candidates

-- the vector leg of the hybrid query; the rest of the statement is identical to HYBRID_SQL below
SELECT doc_id, chunk_no FROM chunks
WHERE tenant = $1 AND acl && $2
ORDER BY embedding <=> $3
LIMIT 20;
```

For very large tenants, partition by tenant, or build partial HNSW indexes per large tenant, so the filter selects a
graph instead of fighting it.

---

## 3. Production code blueprints

### 3.1 Java 21: embedded Kafka → version-gated Postgres sink → hybrid SQL, with a consumer crash

```java
// HybridSearchCdcPipeline.java - the retrieval data plane, executed for real: an embedded Kafka 4.2 KRaft broker and an
// embedded PostgreSQL 18, in one process. Document CDC events (create, shrink to fewer chunks, ACL change, delete,
// plus duplicate deliveries and stale replays) flow through Kafka into two consumer groups that write to two schemas:
//   naive : ON CONFLICT upsert per chunk, no version gate, deletes without tombstones;
//   hard  : one transaction per event, gated by a per-document version row (tombstones block resurrection), all
//           chunks of the old version replaced (shrinks leave no orphans), Kafka offsets committed AFTER the DB commit.
// A consumer crash between DB commit and offset commit replays a batch into both. The index is then checked against
// ground truth, and hybrid search (Postgres full-text + cosine on float8[] with a pgvector-style <=> operator) is fused
// with RRF in ONE SQL statement, with tenant + ACL pre-filtering on GIN indexes.
// Build: javac --release 21 -cp <spring-kafka-test 4.1.2, kafka 4.2.2, embedded-postgres 2.2.2 (PG 18.6), postgresql 42.7>
package dev.l7.ai.inference;

import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import java.sql.Array;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Properties;
import java.util.Random;
import java.util.TreeMap;
import javax.sql.DataSource;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.kafka.test.EmbeddedKafkaKraftBroker;

public final class HybridSearchCdcPipeline {

    static final String TOPIC = "doc-cdc";

    /** One CDC event. Wire format: op|doc|version|tenant|acl1,acl2|chunk1~chunk2~... */
    record Event(String op, String doc, long version, String tenant, List<String> acl, List<String> chunks) {
        String wire() { return op + "|" + doc + "|" + version + "|" + tenant + "|" + String.join(",", acl) + "|" + String.join("~", chunks); }

        static Event parse(String s) {
            String[] p = s.split("\\|", -1);
            return new Event(p[0], p[1], Long.parseLong(p[2]), p[3], p[4].isEmpty() ? List.of() : List.of(p[4].split(",")),
                    p[5].isEmpty() ? List.of() : List.of(p[5].split("~")));
        }
    }

    // ------------------------------------------------------------------ the corpus and its CDC history
    static final String[][] TOPICS = {
            {"refund", "damaged", "items", "refunded", "full", "delivery"}, {"shipping", "carrier", "delay", "credit", "days"},
            {"warranty", "electronics", "defect", "repair", "year"}, {"returns", "opened", "software", "defective", "label"},
            {"pricing", "enterprise", "discount", "contract", "renewal"}};

    static String sentence(Random r, int topic) {
        String[] w = TOPICS[topic];
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 8; i++) sb.append(w[r.nextInt(w.length)]).append(' ');
        return sb.append("policy note ").append(r.nextInt(1000)).toString();
    }

    static List<Event> history(Random r) {
        List<Event> ev = new ArrayList<>();
        Map<String, Event> latest = new LinkedHashMap<>();
        for (int d = 0; d < 300; d++) {
            String doc = "doc-" + d, tenant = d % 3 == 0 ? "globex" : "acme";
            int topic = d % TOPICS.length;
            List<String> chunks = new ArrayList<>();
            for (int c = 0; c < 5; c++) chunks.add(sentence(r, topic));
            Event e = new Event("upsert", doc, 1, tenant, List.of(topic == 4 ? "sales" : "support"), chunks);
            ev.add(e);
            latest.put(doc, e);
        }
        for (int d = 0; d < 300; d += 2) {                                         // half the docs shrink to 3 chunks
            Event old = latest.get("doc-" + d);
            Event e = new Event("upsert", old.doc(), 2, old.tenant(), old.acl(), old.chunks().subList(0, 3));
            ev.add(e);
            latest.put(old.doc(), e);
        }
        List<Event> beforeRevocation = new ArrayList<>();
        for (int d = 1; d < 300; d += 10) {                                        // access revoked: support -> sales
            Event old = latest.get("doc-" + d);
            beforeRevocation.add(old);
            Event e = new Event("upsert", old.doc(), old.version() + 1, old.tenant(), List.of("sales"), old.chunks());
            ev.add(e);
            latest.put(old.doc(), e);
        }
        for (int d = 3; d < 300; d += 7) {                                         // deletions
            Event old = latest.get("doc-" + d);
            Event e = new Event("delete", old.doc(), old.version() + 1, old.tenant(), List.of(), List.of());
            ev.add(e);
            latest.put(old.doc(), e);
        }
        int live = ev.size();
        for (int i = 0; i < 50; i++) ev.add(ev.get(r.nextInt(live)));             // at-least-once duplicates, stale replays
        ev.addAll(beforeRevocation.subList(0, 10));                                // a backfill re-publishes an old snapshot
        COUNTS.put("revocations", beforeRevocation.size());
        COUNTS.put("replays", ev.size() - live);
        beforeRevocation.forEach(e -> REVOKED.add(e.doc()));
        return ev;
    }

    static final Map<String, Integer> COUNTS = new LinkedHashMap<>();
    static final List<String> REVOKED = new ArrayList<>();

    static Map<String, Event> truth(List<Event> ev) {
        Map<String, Event> t = new TreeMap<>();
        for (Event e : ev) if (!t.containsKey(e.doc()) || t.get(e.doc()).version() < e.version()) t.put(e.doc(), e);
        return t;
    }

    static double[] embed(String s) {
        double[] v = new double[32];
        for (String w : s.toLowerCase().split("\\W+")) if (w.length() > 2) v[Math.floorMod(w.hashCode(), 32)] += 1;
        double n = Math.sqrt(Arrays.stream(v).map(x -> x * x).sum());
        for (int k = 0; k < v.length; k++) v[k] /= n == 0 ? 1 : n;
        return v;
    }

    // ------------------------------------------------------------------ schema (pgvector stand-in included)
    static final String DDL = """
            CREATE OR REPLACE FUNCTION cosine_distance(a float8[], b float8[]) RETURNS float8
              LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS
              $$ SELECT 1 - sum(x * y) / nullif(sqrt(sum(x * x)) * sqrt(sum(y * y)), 0) FROM unnest(a, b) AS t(x, y) $$;
            DO $$ BEGIN
              CREATE OPERATOR <=> (LEFTARG = float8[], RIGHTARG = float8[], FUNCTION = cosine_distance);
            EXCEPTION WHEN duplicate_function THEN NULL; END $$;
            CREATE SCHEMA %1$s;
            CREATE TABLE %1$s.chunks (
              doc_id      text    NOT NULL,
              chunk_no    int     NOT NULL,
              doc_version bigint  NOT NULL,
              tenant      text    NOT NULL,
              acl         text[]  NOT NULL,
              body        text    NOT NULL,
              tsv         tsvector GENERATED ALWAYS AS (to_tsvector('english', body)) STORED,
              embedding   float8[] NOT NULL,
              PRIMARY KEY (doc_id, chunk_no));
            CREATE INDEX ON %1$s.chunks USING gin (tsv);
            CREATE INDEX ON %1$s.chunks USING gin (acl);
            CREATE INDEX ON %1$s.chunks (tenant);
            CREATE TABLE %1$s.doc_versions (doc_id text PRIMARY KEY, version bigint NOT NULL, deleted boolean NOT NULL);
            """;

    static Array textArray(Connection c, List<String> xs) throws SQLException { return c.createArrayOf("text", xs.toArray()); }

    static Array floatArray(Connection c, double[] v) throws SQLException {
        return c.createArrayOf("float8", Arrays.stream(v).boxed().toArray());
    }

    // ------------------------------------------------------------------ the two sinks
    interface Sink { void apply(Connection c, Event e) throws SQLException; }

    /** Per-chunk upsert without a version gate; deletes leave no tombstone; shrinks leave orphans. */
    static final Sink NAIVE = (c, e) -> {
        if (e.op().equals("delete")) {
            try (PreparedStatement d = c.prepareStatement("DELETE FROM naive.chunks WHERE doc_id = ?")) {
                d.setString(1, e.doc());
                d.executeUpdate();
            }
            return;
        }
        try (PreparedStatement up = c.prepareStatement("""
                INSERT INTO naive.chunks(doc_id, chunk_no, doc_version, tenant, acl, body, embedding) VALUES (?,?,?,?,?,?,?)
                ON CONFLICT (doc_id, chunk_no) DO UPDATE SET doc_version = EXCLUDED.doc_version, acl = EXCLUDED.acl,
                  body = EXCLUDED.body, embedding = EXCLUDED.embedding""")) {
            for (int i = 0; i < e.chunks().size(); i++) {
                up.setString(1, e.doc());
                up.setInt(2, i);
                up.setLong(3, e.version());
                up.setString(4, e.tenant());
                up.setArray(5, textArray(c, e.acl()));
                up.setString(6, e.chunks().get(i));
                up.setArray(7, floatArray(c, embed(e.chunks().get(i))));
                up.addBatch();
            }
            up.executeBatch();
        }
    };

    /** Version-gated, whole-document replacement in one transaction; tombstones survive deletes. */
    static final Sink HARD = (c, e) -> {
        try (PreparedStatement gate = c.prepareStatement("""
                INSERT INTO hard.doc_versions(doc_id, version, deleted) VALUES (?, ?, ?)
                ON CONFLICT (doc_id) DO UPDATE SET version = EXCLUDED.version, deleted = EXCLUDED.deleted
                WHERE hard.doc_versions.version < EXCLUDED.version
                RETURNING version""")) {
            gate.setString(1, e.doc());
            gate.setLong(2, e.version());
            gate.setBoolean(3, e.op().equals("delete"));
            try (ResultSet rs = gate.executeQuery()) {
                if (!rs.next()) return;                                           // duplicate or stale: a no-op
            }
        }
        try (PreparedStatement d = c.prepareStatement("DELETE FROM hard.chunks WHERE doc_id = ?")) {
            d.setString(1, e.doc());
            d.executeUpdate();
        }
        if (e.op().equals("delete")) return;
        try (PreparedStatement ins = c.prepareStatement(
                "INSERT INTO hard.chunks(doc_id, chunk_no, doc_version, tenant, acl, body, embedding) VALUES (?,?,?,?,?,?,?)")) {
            for (int i = 0; i < e.chunks().size(); i++) {
                ins.setString(1, e.doc());
                ins.setInt(2, i);
                ins.setLong(3, e.version());
                ins.setString(4, e.tenant());
                ins.setArray(5, textArray(c, e.acl()));
                ins.setString(6, e.chunks().get(i));
                ins.setArray(7, floatArray(c, embed(e.chunks().get(i))));
                ins.addBatch();
            }
            ins.executeBatch();
        }
    };

    /** Poll, apply each record in its own transaction, commit offsets after the DB. `crashAfter` simulates kill -9. */
    static int consume(String brokers, String group, DataSource ds, Sink sink, int crashAfter) throws SQLException {
        Properties p = new Properties();
        p.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, brokers);
        p.put(ConsumerConfig.GROUP_ID_CONFIG, group);
        p.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        p.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "false");
        p.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, "100");
        p.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        p.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        int applied = 0, idle = 0;
        try (KafkaConsumer<String, String> consumer = new KafkaConsumer<>(p); Connection c = ds.getConnection()) {
            consumer.subscribe(List.of(TOPIC));
            c.setAutoCommit(false);
            while (idle < 3) {
                var records = consumer.poll(Duration.ofMillis(500));
                if (records.isEmpty()) {
                    idle++;
                    continue;
                }
                idle = 0;
                for (ConsumerRecord<String, String> rec : records) {
                    sink.apply(c, Event.parse(rec.value()));
                    c.commit();                                                    // the DB is now ahead of Kafka
                    if (++applied == crashAfter) return applied;                   // crash: offsets never committed
                }
                consumer.commitSync();
            }
        }
        return applied;
    }

    record Audit(int docs, int chunks, int staleChunks, int orphanChunks, int resurrected, int aclWrong) {}

    static Audit audit(DataSource ds, String schema, Map<String, Event> truth) throws SQLException {
        int chunks = 0, stale = 0, orphan = 0, resurrected = 0, acl = 0;
        java.util.Set<String> docs = new java.util.HashSet<>();
        try (Connection c = ds.getConnection(); Statement s = c.createStatement();
             ResultSet rs = s.executeQuery("SELECT doc_id, chunk_no, doc_version, acl FROM " + schema + ".chunks")) {
            while (rs.next()) {
                chunks++;
                Event t = truth.get(rs.getString(1));
                docs.add(rs.getString(1));
                if (t.op().equals("delete")) { resurrected++; continue; }
                if (rs.getLong(3) != t.version()) stale++;
                if (rs.getInt(2) >= t.chunks().size()) orphan++;
                if (!List.of((String[]) rs.getArray(4).getArray()).equals(t.acl())) acl++;
            }
        }
        return new Audit(docs.size(), chunks, stale, orphan, resurrected, acl);
    }

    static final String HYBRID_SQL = """
            WITH q AS (SELECT plainto_tsquery('english', ?) AS tsq, ?::float8[] AS qv),
            lex AS (
              SELECT c.doc_id, c.chunk_no,
                     row_number() OVER (ORDER BY ts_rank_cd(c.tsv, q.tsq) DESC, c.doc_id, c.chunk_no) AS r
              FROM %1$s.chunks c, q
              WHERE c.tsv @@ q.tsq AND c.tenant = ? AND c.acl && ?::text[]
              ORDER BY r LIMIT 20),
            vec AS (
              SELECT c.doc_id, c.chunk_no,
                     row_number() OVER (ORDER BY c.embedding <=> q.qv, c.doc_id, c.chunk_no) AS r
              FROM %1$s.chunks c, q
              WHERE c.tenant = ? AND c.acl && ?::text[]
              ORDER BY r LIMIT 20)
            SELECT doc_id, chunk_no, round(sum(1.0 / (60 + r)), 5) AS rrf, string_agg(src, '+' ORDER BY src) AS via
            FROM (SELECT doc_id, chunk_no, r, 'lex' AS src FROM lex UNION ALL SELECT doc_id, chunk_no, r, 'vec' FROM vec) u
            GROUP BY doc_id, chunk_no
            ORDER BY rrf DESC, doc_id, chunk_no
            LIMIT ?""";

    static List<String> hybrid(Connection c, String schema, String query, String tenant, List<String> groups, int k) throws SQLException {
        List<String> out = new ArrayList<>();
        try (PreparedStatement ps = c.prepareStatement(HYBRID_SQL.formatted(schema))) {
            ps.setString(1, query);
            ps.setArray(2, floatArray(c, embed(query)));
            ps.setString(3, tenant);
            ps.setArray(4, textArray(c, groups));
            ps.setString(5, tenant);
            ps.setArray(6, textArray(c, groups));
            ps.setInt(7, k);
            try (ResultSet rs = ps.executeQuery()) {
                while (rs.next()) out.add(rs.getString(1) + "#" + rs.getInt(2) + " rrf=" + rs.getBigDecimal(3) + " via " + rs.getString(4));
            }
        }
        return out;
    }

    static List<String> planNodes(Connection c, String sql) throws SQLException {
        List<String> nodes = new ArrayList<>();
        try (Statement s = c.createStatement(); ResultSet rs = s.executeQuery("EXPLAIN (COSTS OFF) " + sql)) {
            while (rs.next()) {
                String l = rs.getString(1).replaceAll("^\\s*->\\s*", "").trim();
                if (l.matches("^(Bitmap|Index|Seq|Hash|Sort|Limit|Nested|Merge|WindowAgg|Incremental).*")) nodes.add(l);
            }
        }
        return nodes;
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new AssertionError(what);
    }

    public static void main(String[] args) throws Exception {
        ((ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME))
                .setLevel(ch.qos.logback.classic.Level.OFF);
        List<Event> events = history(new Random(42));
        Map<String, Event> truth = truth(events);
        long live = truth.values().stream().filter(e -> e.op().equals("upsert")).count();
        System.out.printf("CDC history: %d events (300 creates, 150 shrinks 5->3 chunks, %d ACL revocations, %d deletes, %d replays"
                + " incl. a stale backfill) -> ground truth %d live docs, %d chunks%n", events.size(), COUNTS.get("revocations"),
                truth.values().stream().filter(e -> e.op().equals("delete")).count(), COUNTS.get("replays"), live,
                truth.values().stream().filter(e -> e.op().equals("upsert")).mapToInt(e -> e.chunks().size()).sum());

        EmbeddedKafkaKraftBroker kafka = new EmbeddedKafkaKraftBroker(1, 3, TOPIC);
        java.io.PrintStream out = System.out;
        System.setOut(new java.io.PrintStream(java.io.OutputStream.nullOutputStream()));   // the test kit prints to stdout
        try {
            kafka.afterPropertiesSet();
        } finally {
            System.setOut(out);
        }
        try (EmbeddedPostgres pg = EmbeddedPostgres.builder().start()) {
            DataSource ds = pg.getPostgresDatabase();
            try (Connection c = ds.getConnection(); Statement s = c.createStatement()) {
                for (String schema : List.of("naive", "hard")) s.execute(DDL.formatted(schema));
                try (ResultSet rs = s.executeQuery("SHOW server_version")) {
                    rs.next();
                    System.out.println("PostgreSQL " + rs.getString(1) + " (embedded), Kafka KRaft broker (embedded), topic " + TOPIC
                            + " with 3 partitions keyed by doc_id");
                }
            }
            Properties pp = new Properties();
            pp.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, kafka.getBrokersAsString());
            pp.put(ProducerConfig.ACKS_CONFIG, "all");
            pp.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, "true");
            pp.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
            pp.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
            try (KafkaProducer<String, String> producer = new KafkaProducer<>(pp)) {
                for (Event e : events) producer.send(new ProducerRecord<>(TOPIC, e.doc(), e.wire()));
                producer.flush();
            }

            Map<String, Integer> appliedTotal = new HashMap<>();
            for (var sink : List.of(Map.entry("naive", NAIVE), Map.entry("hard", HARD))) {
                int first = consume(kafka.getBrokersAsString(), sink.getKey(), ds, sink.getValue(), 250);   // crash mid-batch
                int second = consume(kafka.getBrokersAsString(), sink.getKey(), ds, sink.getValue(), -1);   // restart
                appliedTotal.put(sink.getKey(), first + second);
            }
            System.out.println("both consumer groups were killed after 250 DB commits with offsets uncommitted, then restarted:"
                    + " the uncommitted tail was delivered again");
            check(appliedTotal.values().stream().allMatch(a -> a > events.size()), "redelivery happened (at-least-once)");

            System.out.printf("%n%-6s %6s %7s %13s %14s %12s %10s%n", "index", "docs", "chunks", "stale-version", "orphan-chunks",
                    "resurrected", "acl-wrong");
            Map<String, Audit> audits = new LinkedHashMap<>();
            for (String schema : List.of("naive", "hard")) {
                Audit a = audit(ds, schema, truth);
                audits.put(schema, a);
                System.out.printf("%-6s %6d %7d %13d %14d %12d %10d%n", schema, a.docs(), a.chunks(), a.staleChunks(), a.orphanChunks(),
                        a.resurrected(), a.aclWrong());
            }
            Audit h = audits.get("hard"), n = audits.get("naive");
            check(h.docs() == live && h.staleChunks() + h.orphanChunks() + h.resurrected() + h.aclWrong() == 0, "hard index equals truth");
            check(n.orphanChunks() > 0 && n.resurrected() + n.aclWrong() + n.staleChunks() > 0, "naive index drifts");

            try (Connection c = ds.getConnection()) {
                String q = "carrier delay credit";
                System.out.println("\nhybrid query '" + q + "' as tenant acme, groups [support] (RRF k=60 in one SQL statement):");
                for (String line : hybrid(c, "hard", q, "acme", List.of("support"), 5)) System.out.println("  " + line);

                List<String> revoked = REVOKED.stream().filter(d -> truth.get(d).op().equals("upsert")).toList();
                int leakNaive = 0, leakHard = 0;
                for (String schema : List.of("naive", "hard"))
                    for (String hit : hybrid(c, schema, q, "acme", List.of("support"), 40)) {
                        String doc = hit.substring(0, hit.indexOf('#'));
                        if (revoked.contains(doc)) {
                            if (schema.equals("naive")) leakNaive++;
                            else leakHard++;
                        }
                    }
                System.out.printf("%naccess revoked on %d docs (support -> sales): a [support] user still retrieves %d of their chunks "
                        + "from naive, %d from hard%n", revoked.size(), leakNaive, leakHard);
                check(leakHard == 0 && leakNaive > 0, "revocations take effect only in the version-gated index");

                String explainable = HYBRID_SQL.formatted("hard").replaceFirst("\\?", "'carrier delay'")
                        .replaceFirst("\\?", "'{" + String.join(",", Arrays.stream(embed("carrier delay")).mapToObj(Double::toString).toList()) + "}'")
                        .replaceFirst("\\?", "'acme'").replaceFirst("\\?", "'{support}'").replaceFirst("\\?", "'acme'")
                        .replaceFirst("\\?", "'{support}'").replaceFirst("\\?", "5");
                try (Statement s = c.createStatement()) {
                    s.execute("ANALYZE hard.chunks");
                    s.execute("SET enable_seqscan = off");                         // show the index paths a large table uses
                }
                System.out.println("\nplan nodes (EXPLAIN, COSTS OFF, seqscan disabled to mimic a large table):");
                for (String node : planNodes(c, explainable)) System.out.println("  " + node);
            }
        } finally {
            kafka.destroy();
        }
        System.out.println("\nall HybridSearchCdcPipeline self-checks passed");
    }
}
```

Output (verified; deterministic. The event stream is seeded and per-document order is fixed by partitioning, so the
final index state does not depend on batch timing):

```text
CDC history: 583 events (300 creates, 150 shrinks 5->3 chunks, 30 ACL revocations, 43 deletes, 60 replays incl. a stale backfill) -> ground truth 257 live docs, 1027 chunks
PostgreSQL 18.6 (embedded), Kafka KRaft broker (embedded), topic doc-cdc with 3 partitions keyed by doc_id
both consumer groups were killed after 250 DB commits with offsets uncommitted, then restarted: the uncommitted tail was delivered again

index    docs  chunks stale-version  orphan-chunks  resurrected  acl-wrong
naive     262    1306           332            258           21         50
hard      257    1027             0              0            0          0

hybrid query 'carrier delay credit' as tenant acme, groups [support] (RRF k=60 in one SQL statement):
  doc-166#0 rrf=0.03227 via lex+vec
  doc-146#2 rrf=0.03083 via lex+vec
  doc-296#1 rrf=0.03016 via lex+vec
  doc-26#0 rrf=0.03012 via lex+vec
  doc-76#0 rrf=0.03002 via lex+vec

access revoked on 26 docs (support -> sales): a [support] user still retrieves 12 of their chunks from naive, 0 from hard

plan nodes (EXPLAIN, COSTS OFF, seqscan disabled to mimic a large table):
  Limit
  Sort
  Sort Key: (round(sum((1.0 / ((60 + lex.r))::numeric)), 5)) DESC, lex.doc_id, lex.chunk_no
  Sort
  Sort Key: lex.doc_id, lex.chunk_no, ('lex'::text)
  Limit
  Sort
  Sort Key: (row_number() OVER w1)
  WindowAgg
  Sort
  Sort Key: (ts_rank_cd(c.tsv, q.tsq)) DESC, c.doc_id, c.chunk_no
  Nested Loop
  Bitmap Heap Scan on chunks c
  Bitmap Index Scan on chunks_tenant_idx
  Index Cond: (tenant = 'acme'::text)
  Limit
  Sort
  Sort Key: (row_number() OVER w1)
  WindowAgg
  Sort
  Sort Key: ((c_1.embedding <=> q_1.qv)), c_1.doc_id, c_1.chunk_no
  Nested Loop
  Bitmap Heap Scan on chunks c_1
  Bitmap Index Scan on chunks_tenant_idx
  Index Cond: (tenant = 'acme'::text)

all HybridSearchCdcPipeline self-checks passed
```

### 3.2 Python: capacity, scan cost, lag and re-embedding arithmetic

```python
"""pg_hybrid_capacity_lab.py - capacity and lag arithmetic for a Postgres hybrid index fed by CDC (stdlib only).

1. Bytes per chunk row and per HNSW element for pgvector-style storage (vector = 4d + 8 bytes, halfvec = 2d + 8),
   and what 10M chunks need in RAM for the index to stay hot.
2. The vector leg without an ANN index: a sequential distance scan is O(rows in the filter), which is why the plain
   Postgres plan in HybridSearchCdcPipeline scans every tenant row.
3. CDC lag: a consumer with service rate mu draining arrivals lambda; backlog drain time = backlog / (mu - lambda),
   and why re-embedding on a model change is a backfill, not an incident.
4. Re-embedding cost of a corpus in tokens and GPU-hours.
The pgvector layout figures are approximations of its on-disk format (verify against your pgvector version).
"""
from __future__ import annotations

TUPLE_HEADER, ITEM_ID, ALIGN = 23, 4, 8


def align(n: int) -> int:
    return (n + ALIGN - 1) // ALIGN * ALIGN


def row_bytes(dim: int, elem: int, text_bytes: int = 1200, tsv_bytes: int = 600, acl_bytes: int = 40) -> int:
    vec = elem * dim + 8                                           # pgvector: 2 x int16 header + 4 bytes padding
    return align(TUPLE_HEADER) + ITEM_ID + vec + text_bytes + tsv_bytes + acl_bytes + 64   # keys, version, tenant


def hnsw_element_bytes(dim: int, elem: int, m: int) -> int:
    """Element tuple (vector + level/heap-TID metadata) plus a neighbour tuple: 2m TIDs on layer 0 and m per upper
    layer. With level multiplier 1/ln(m), E[levels above 0] = 1/(m-1), so E[TIDs] = 2m + m/(m-1) (6 bytes each)."""
    element = align(TUPLE_HEADER) + ITEM_ID + elem * dim + 8 + 16
    neighbours = align(TUPLE_HEADER) + ITEM_ID + round(6 * (2 * m + m / (m - 1)))
    return element + neighbours


def gib(b: float) -> float:
    return b / 2 ** 30


def main() -> None:
    print("== 1. Storage for 10M chunks (d = embedding dimensions) ==")
    print(f"  {'type':8} {'d':>5} {'row B':>7} {'heap GiB':>9} {'HNSW m=16 B/elem':>17} {'HNSW GiB':>9} {'hot set GiB':>12}")
    n = 10_000_000
    rows = []
    for name, elem in (("vector", 4), ("halfvec", 2)):
        for d in (768, 1024, 1536):
            rb, hb = row_bytes(d, elem), hnsw_element_bytes(d, elem, 16)
            rows.append((name, d, rb, hb))
            print(f"  {name:8} {d:>5} {rb:>7,} {gib(rb * n):>9.1f} {hb:>17,} {gib(hb * n):>9.1f} {gib(hb * n) * 1.2:>12.1f}")
    v768 = next(r for r in rows if r[0] == "vector" and r[1] == 768)
    h768 = next(r for r in rows if r[0] == "halfvec" and r[1] == 768)
    print(f"  halfvec halves the vector bytes: HNSW {gib(v768[3] * n):.1f} -> {gib(h768[3] * n):.1f} GiB for d=768;"
          f" re-rank with full precision if recall drops (Folder 03 File 03)")
    print("  the HNSW build needs the graph in maintenance_work_mem to stay fast; size it like the index, not like a sort")

    print("\n== 2. The vector leg without an ANN index ==")
    for rows_in_filter in (1_000, 100_000, 10_000_000):
        flops = rows_in_filter * 768 * 2
        ms = flops / 20e9 * 1e3                                        # ~20 GFLOP/s effective in SQL-level loops is optimistic
        print(f"  {rows_in_filter:>10,} rows after tenant/ACL filter -> {flops / 1e9:7.2f} GFLOP per query -> >= {ms:8.1f} ms")
    print("  -> fine for one small tenant; at scale an ANN index (HNSW/IVF) is required, and then the tenant/ACL filter")
    print("     interacts with the graph search (Folder 03 File 01: filtered-search traps, iterative scans)")

    print("\n== 3. CDC lag: drain time = backlog / (mu - lambda) ==")
    lam = 200.0                                                         # doc change events per second at peak
    for mu in (220.0, 400.0, 1000.0):
        for backlog in (100_000, 10_000_000):
            t = backlog / (mu - lam)
            print(f"  arrivals {lam:.0f}/s, consumer capacity {mu:>5.0f}/s, backlog {backlog:>10,}: drains in {t / 3600:7.2f} h")
    print("  a consumer at 110% of peak arrivals needs 139 h to drain a 10M backlog: provision headroom (>= 2x) or a")
    print("  separate backfill pipeline so a re-index never delays live ACL changes")

    print("\n== 4. Re-embedding a corpus after an embedding-model change ==")
    chunks, tokens_per_chunk = 10_000_000, 350
    total = chunks * tokens_per_chunk
    for name, tok_s in (("1x L4, small encoder", 40_000), ("1x H100, small encoder", 250_000), ("8x H100", 2_000_000)):
        print(f"  {total / 1e9:.1f}B tokens on {name:24s} at {tok_s:>9,} tok/s -> {total / tok_s / 3600:6.1f} h")
    print("  version the embedding column (embedding_v2) and dual-read until the backfill completes; never mix vectors")
    print("  from two models in one index")
    assert abs(10_000_000 / (220 - 200) / 3600 - 138.9) < 0.1
    print("\nall pg_hybrid_capacity_lab self-checks passed")


if __name__ == "__main__":
    main()
```

Output (verified; deterministic):

```text
== 1. Storage for 10M chunks (d = embedding dimensions) ==
  type         d   row B  heap GiB  HNSW m=16 B/elem  HNSW GiB  hot set GiB
  vector     768   5,012      46.7             3,350      31.2         37.4
  vector    1024   6,036      56.2             4,374      40.7         48.9
  vector    1536   8,084      75.3             6,422      59.8         71.8
  halfvec    768   3,476      32.4             1,814      16.9         20.3
  halfvec   1024   3,988      37.1             2,326      21.7         26.0
  halfvec   1536   5,012      46.7             3,350      31.2         37.4
  halfvec halves the vector bytes: HNSW 31.2 -> 16.9 GiB for d=768; re-rank with full precision if recall drops (Folder 03 File 03)
  the HNSW build needs the graph in maintenance_work_mem to stay fast; size it like the index, not like a sort

== 2. The vector leg without an ANN index ==
       1,000 rows after tenant/ACL filter ->    0.00 GFLOP per query -> >=      0.1 ms
     100,000 rows after tenant/ACL filter ->    0.15 GFLOP per query -> >=      7.7 ms
  10,000,000 rows after tenant/ACL filter ->   15.36 GFLOP per query -> >=    768.0 ms
  -> fine for one small tenant; at scale an ANN index (HNSW/IVF) is required, and then the tenant/ACL filter
     interacts with the graph search (Folder 03 File 01: filtered-search traps, iterative scans)

== 3. CDC lag: drain time = backlog / (mu - lambda) ==
  arrivals 200/s, consumer capacity   220/s, backlog    100,000: drains in    1.39 h
  arrivals 200/s, consumer capacity   220/s, backlog 10,000,000: drains in  138.89 h
  arrivals 200/s, consumer capacity   400/s, backlog    100,000: drains in    0.14 h
  arrivals 200/s, consumer capacity   400/s, backlog 10,000,000: drains in   13.89 h
  arrivals 200/s, consumer capacity  1000/s, backlog    100,000: drains in    0.03 h
  arrivals 200/s, consumer capacity  1000/s, backlog 10,000,000: drains in    3.47 h
  a consumer at 110% of peak arrivals needs 139 h to drain a 10M backlog: provision headroom (>= 2x) or a
  separate backfill pipeline so a re-index never delays live ACL changes

== 4. Re-embedding a corpus after an embedding-model change ==
  3.5B tokens on 1x L4, small encoder     at    40,000 tok/s ->   24.3 h
  3.5B tokens on 1x H100, small encoder   at   250,000 tok/s ->    3.9 h
  3.5B tokens on 8x H100                  at 2,000,000 tok/s ->    0.5 h
  version the embedding column (embedding_v2) and dual-read until the backfill completes; never mix vectors
  from two models in one index

all pg_hybrid_capacity_lab self-checks passed
```

---

## 4. Production failure modes and P99 debugging

### F1 · Deleted documents reappear in answers

- **Signature:** retrieval returns chunks whose source document no longer exists; the count rises after backfills.
- **Root cause:** deletes without tombstones; a later replay of an old upsert re-creates the document.
- **Fix:** tombstones in the version table, retained beyond the longest replay horizon; the version gate rejects
  older upserts.

### F2 · Answers quote text that was removed from a document

- **Root cause:** per-chunk upserts; a document that shrank kept its tail chunks (orphans).
- **Fix:** whole-document replacement in one transaction, and an audit that counts chunks with
  `chunk_no ≥ current count`.

### F3 · A user whose access was revoked still gets the content

- **Root cause:** a stale event (backfill, replay, a second pipeline) overwrote the newer ACL.
- **Fix:** a monotonic version gate, per-field versions when ACL and content arrive separately, ACL
  pre-filtering at query time (Folder 04 File 03), and an SLO on revocation propagation latency.

### F4 · Duplicates or gaps after consumer restarts

- **Root cause:** offsets committed before the DB transaction (gaps), or non-idempotent inserts with offsets after
  (duplicates).
- **Fix:** DB commit, then offset commit, and an idempotent, version-gated sink. Kafka transactions give
  exactly-once only for Kafka-to-Kafka flows; a database sink still needs idempotency.

### F5 · CDC lag spikes during a re-index

- **Root cause:** the backfill shares the live pipeline; `μ − λ` collapses.
- **Fix:** a separate backfill topic and consumer group with its own capacity; live events take priority; lag is
  alerted in time-to-drain, not message counts.

### F6 · Lexical recall drops for long or natural-language queries

- **Root cause:** `plainto_tsquery` ANDs every term.
- **Fix:** `websearch_to_tsquery` or an OR-query for the hybrid leg, BM25 where available, and let RRF combine the
  legs.

### F7 · Vector-leg latency grows with tenant size

- **Root cause:** no ANN index (an exact distance scan over the filtered rows), or an HNSW index whose filter
  post-filters away most candidates.
- **Fix:** HNSW with iterative scans, per-tenant partitions or partial indexes, and the planner tactics of Folder 03
  File 01 (exact scans for very selective filters).

### F8 · Relevance collapses after an embedding-model upgrade

- **Root cause:** vectors from two models in one index (query embeddings from the new model, documents from the old).
- **Fix:** a versioned embedding column, a full backfill, dual-read evaluation, and an atomic cut-over.

---

## 5. FAANG L7 bar-raiser Q&A chains

### Q1 · "Design ingestion from 40 source systems into the RAG index."

- **L5 answer:** "A connector per system that upserts chunks into the vector DB."
- **Why L5 fails at scale:** at-least-once delivery, replays, backfills and deletes make a per-chunk upsert drift:
  stale versions, orphans, resurrected documents, regressed ACLs, as measured.
- **L7 principal defense:**
  1. Log-based CDC per source into Kafka, keyed by document id; schema-versioned events carrying a monotonic source
     version (log position, `updated_at` plus a sequence, or a revision number).
  2. One sink contract: a version gate, tombstones and whole-document replacement in one transaction, then the
     offset commit.
  3. Per-field versions where ACLs come from the identity system.
  4. A separate backfill path; lag measured as time-to-drain.
  5. Continuous audits against source truth (stale, orphan, resurrected, ACL mismatches) as SLOs.

### Q2 · "A user lost access yesterday, but the assistant quoted the document today."

- **L5 answer:** "The cache must be stale; flush it."
- **L7 principal defense:**
  1. Trace the document's version history in the sink: was the revocation applied and then overwritten by a stale
     event?
  2. Fix structurally with a monotonic gate and per-field versions.
  3. Enforce ACLs at query time from an authoritative entitlement snapshot (Folder 04 File 03), not only from
     indexed copies.
  4. Set an SLO for revocation propagation, alert on it, and replay the incident as a regression test.

### Q3 · "pgvector or a dedicated vector database?"

- **L5 answer:** "A dedicated vector DB, because it is faster."
- **L7 principal defense:**
  1. pgvector wins when the corpus fits comfortably (tens of millions of vectors, an index that fits in RAM: about
     31 GiB per 10M at d = 768, 17 GiB with halfvec) and you value transactions. ACL, content and vectors then commit
     atomically, which is exactly what §1.1 needs. Joins, filters and one operational system also count.
  2. A dedicated engine wins at hundreds of millions to billions of vectors, very high QPS, heavy filtering at scale
     (Folder 03: ACORN-style filtering, DiskANN), or when the team needs vector-specific operations.
  3. Either way: hybrid retrieval, ACL pre-filtering, versioned embeddings, and measured recall@k under filters.

### Q4 · "We're switching embedding models next month."

- **L7 principal defense:**
  1. It is a backfill, not a deploy: 3.5B tokens for 10M chunks, about 4 GPU-hours on one H100 with a small
     encoder, but days on small GPUs.
  2. Add a versioned column and index, backfill through a separate pipeline, dual-read and compare recall@k and
     answer quality, then cut over atomically and drop the old column after a soak period.
  3. Never mix models in one index or one query.

### Q5 · "Can we get exactly-once from Kafka into Postgres?"

- **L5 answer:** "Yes, enable Kafka exactly-once."
- **L7 principal defense:**
  1. Kafka's transactions cover read-process-write *within Kafka*. A Postgres sink sits outside that boundary.
  2. Effectively-once = at-least-once delivery + an idempotent sink: a version gate keyed by document, or storing the
     consumed offset in the same DB transaction and seeking to it on restart.
  3. The lab shows the version-gated sink converging exactly after a crash and 60 replays.

---

## 6. Invariants checklist

- [ ] CDC events are keyed by document id and carry a monotonic source version.
- [ ] The sink applies an event only if its version is newer, atomically with the chunk changes.
- [ ] Deletes write tombstones retained beyond the longest replay horizon.
- [ ] Updates replace all chunks of the document; audits count orphans.
- [ ] Offsets are committed after the DB transaction; the sink is idempotent under redelivery.
- [ ] ACLs come from per-field versions when they have their own source, and are enforced again at query time.
- [ ] Hybrid SQL filters by tenant and ACL inside both legs before ranking.
- [ ] The vector leg uses an ANN index at scale, with filtered-search behaviour tested; small tenants may use exact
      scans.
- [ ] Embeddings are versioned per model; re-embedding runs as a separate backfill.
- [ ] Lag is measured in time-to-drain; backfills never share capacity with live revocations.

## 7. References

1. PostgreSQL 18 documentation: Full Text Search (`tsvector`, `ts_rank_cd`, `plainto_tsquery`,
   `websearch_to_tsquery`), GIN indexes, generated columns, `INSERT … ON CONFLICT`, `EXPLAIN`.
2. pgvector README: `vector`/`halfvec` types, `<=>`, HNSW (`m`, `ef_construction`, `hnsw.ef_search`), iterative
   index scans (0.8.0+) (⚠ verify against your version).
3. Apache Kafka 4.x documentation: consumer groups and offset commits, idempotent producer, KRaft.
4. G. V. Cormack, C. L. A. Clarke, S. Büttcher. *Reciprocal Rank Fusion Outperforms Condorcet and Individual Rank
   Learning Methods.* SIGIR 2009.
5. M. Kleppmann. *Designing Data-Intensive Applications*, ch. 11 *Stream Processing* (change data capture, log
   compaction, tombstones).
6. Debezium documentation: delete events and tombstones (a production CDC source for Postgres and MySQL).
