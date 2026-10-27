# Curated Open-Source Architectures to Study (GitHub)

> **Folder 10 · File 03** of the Distributed Systems & System Design L7 Reference.
> **How to use it:** for each problem or concept, one or two real codebases where the mechanism lives. "Read for"
> says what to look for. Repository layouts change, so search the repository for the named concept rather than
> trusting a path; directory hints are given only where they have been stable for years.
> **§4** contains `verify_reading_list.py`, which checked every link in Folder 10. Its output is a measured run,
> since it depends on the network.

---

## 1. Consensus, coordination, transactions

| Repository | Language | Read for | KB |
|---|---|---|---|
| [etcd-io/raft](https://github.com/etcd-io/raft) | Go | The canonical Raft library: `raft.go` (step functions, PreVote, CheckQuorum), `log.go`, `read_only.go` (ReadIndex) | F03 f01 |
| [etcd-io/etcd](https://github.com/etcd-io/etcd) | Go | Leases, the MVCC store (revisions as fencing tokens), watch fan-out | F03 f03, problem 3 |
| [hashicorp/raft](https://github.com/hashicorp/raft) | Go | A compact Raft used by Consul/Nomad; snapshots, membership | F03 f01 |
| [tikv/raft-rs](https://github.com/tikv/raft-rs) | Rust | Raft in Rust (a port of etcd's) | F03 f01 |
| [apache/zookeeper](https://github.com/apache/zookeeper) | Java | Zab, sessions, ephemeral nodes, the lock recipes | Problem 3 |
| [tikv/tikv](https://github.com/tikv/tikv) | Rust | Multi-Raft, region splits, Percolator transactions, async commit | F03 f03, F02 f04 |
| [pingcap/tidb](https://github.com/pingcap/tidb) | Go | SQL layer over TiKV, TSO usage, pessimistic transactions | F02 f04 |
| [cockroachdb/cockroach](https://github.com/cockroachdb/cockroach) | Go | HLC, uncertainty intervals, parallel commits, leaseholders, closed timestamps | F02 f04, F03 f02 |
| [apple/foundationdb](https://github.com/apple/foundationdb) | C++ (Flow) | Deterministic simulation testing; OCC with resolvers; the sequencer | F03 f01 §3.3 |
| [aws/clock-bound](https://github.com/aws/clock-bound) | Rust | TrueTime-style [earliest, latest] bounds on commodity clocks | F03 f02 |
| [temporalio/temporal](https://github.com/temporalio/temporal) | Go | Durable execution for sagas; history, timers, retries | F03 f03 §4 |

## 2. Storage engines and databases

| Repository | Language | Read for | KB |
|---|---|---|---|
| [facebook/rocksdb](https://github.com/facebook/rocksdb) | C++ | `db/compaction/` (leveled/universal), write stalls, `table/block_based/` (SST format, filters), BlobDB | F02 f01 |
| [google/leveldb](https://github.com/google/leveldb) | C++ | The minimal LSM: small enough to read end to end in a weekend | F02 f01 |
| [apache/cassandra](https://github.com/apache/cassandra) | Java | Consistency levels, read repair, hinted handoff, compaction strategies (incl. UCS) | F02 f02, F02 f01 |
| [scylladb/scylladb](https://github.com/scylladb/scylladb) | C++ | Shard-per-core (Seastar), no shared state, incremental compaction | F01 f02 §2.4 |
| [vitessio/vitess](https://github.com/vitessio/vitess) | Go | MySQL sharding: query routing (vtgate), resharding workflows | F09 f01 |
| [citusdata/citus](https://github.com/citusdata/citus) | C | Distributed PostgreSQL: shard placement, distributed planning | F09 f01 |
| [ClickHouse/ClickHouse](https://github.com/ClickHouse/ClickHouse) | C++ | MergeTree parts, sparse indexes, vectorized execution | Problem 29, F09 f01 |
| [apache/iceberg](https://github.com/apache/iceberg) | Java | Snapshots, manifests, optimistic commits, hidden partitioning | Problem 31 |
| [redis/redis](https://github.com/redis/redis) | C | `t_zset.c` (skip list with spans → ZRANK), cluster slots, replication | Problem 30, F04 f02 |
| [valkey-io/valkey](https://github.com/valkey-io/valkey) | C | The open-source Redis fork; I/O threading changes | F04 f02 |
| [memcached/memcached](https://github.com/memcached/memcached) | C | Slab allocator, LRU crawler | F04 f02 |
| [facebook/CacheLib](https://github.com/facebook/CacheLib) | C++ | Hybrid RAM + flash caches, admission policies | F04 f02 §7, F01 f02 §3.2 |
| [ben-manes/caffeine](https://github.com/ben-manes/caffeine) | Java | W-TinyLFU admission + eviction | F04 f03 §3 |
| [minio/minio](https://github.com/minio/minio) | Go | Object storage with Reed-Solomon erasure coding, bitrot protection | Problem 2 |
| [ceph/ceph](https://github.com/ceph/ceph) | C++ | CRUSH placement, erasure-coded pools, recovery/backfill throttling | Problem 2 |

## 3. Networking, messaging, streaming, observability, ML/AI serving

| Repository | Language | Read for | KB |
|---|---|---|---|
| [envoyproxy/envoy](https://github.com/envoyproxy/envoy) | C++ | LB policies (P2C least-request, ring hash, Maglev), outlier detection, retry budgets, adaptive concurrency, xDS | F04 f01 |
| [facebookincubator/katran](https://github.com/facebookincubator/katran) | C / eBPF | XDP L4 load balancer, Maglev-style hashing | F04 f01 §3 |
| [cilium/cilium](https://github.com/cilium/cilium) | Go / eBPF | eBPF data plane, sidecarless service mesh | F01 f02 §4.8 |
| [cloudflare/quiche](https://github.com/cloudflare/quiche) | Rust | QUIC/HTTP/3 implementation | F04 f03 §5 |
| [apache/kafka](https://github.com/apache/kafka) | Java/Scala | Log segments, ISR/high watermark, idempotent producers, KRaft, tiered storage | Problem 8 |
| [redpanda-data/redpanda](https://github.com/redpanda-data/redpanda) | C++ | Kafka API on Seastar; Raft per partition | Problem 8 |
| [apache/pulsar](https://github.com/apache/pulsar) | Java | Stateless brokers + BookKeeper segments | F09 f02 |
| [nats-io/nats-server](https://github.com/nats-io/nats-server) | Go | Lightweight pub/sub, JetStream with Raft | F09 f02 |
| [apache/flink](https://github.com/apache/flink) | Java | Checkpoint barriers, keyed state, watermarks, 2PC sinks | Problem 29 |
| [debezium/debezium](https://github.com/debezium/debezium) | Java | CDC from WAL/binlog; snapshot + stream handoff | F02 f02 §1.2 |
| [prometheus/prometheus](https://github.com/prometheus/prometheus) | Go | TSDB head block, WAL, Gorilla-style chunks, postings index | Problem 9 |
| [grafana/mimir](https://github.com/grafana/mimir) | Go | Horizontally scaled Prometheus: sharding, limits (cardinality) | Problem 9 |
| [open-telemetry/opentelemetry-collector](https://github.com/open-telemetry/opentelemetry-collector) | Go | Pipelines, batching; the contrib repo has the tail-sampling processor | Problem 10 |
| [authzed/spicedb](https://github.com/authzed/spicedb) | Go | Zanzibar implementation: zookies (ZedTokens), caveats, dispatch | Problem 11 |
| [openfga/openfga](https://github.com/openfga/openfga) | Go | Zanzibar-style ReBAC | Problem 11 |
| [uber/h3](https://github.com/uber/h3) | C | Hexagonal hierarchical index, k-rings | Problem 22 |
| [google/s2geometry](https://github.com/google/s2geometry) | C++ | S2 cells, region coverings | Problem 22 |
| [yjs/yjs](https://github.com/yjs/yjs) | JavaScript | YATA sequence CRDT, state vectors, GC | Problem 21 |
| [automerge/automerge](https://github.com/automerge/automerge) | Rust/JS | JSON CRDT, compact columnar encoding | Problem 21 |
| [LMAX-Exchange/disruptor](https://github.com/LMAX-Exchange/disruptor) | Java | Ring buffer, sequence barriers, single-writer principle | Problem 28 |
| [Netflix/concurrency-limits](https://github.com/Netflix/concurrency-limits) | Java | Vegas/Gradient2/AIMD adaptive limits | F05 f02 |
| [Netflix/vmaf](https://github.com/Netflix/vmaf) | C/Python | Perceptual video quality metric | Problem 16 |
| [Dash-Industry-Forum/dash.js](https://github.com/Dash-Industry-Forum/dash.js) | JavaScript | ABR rules (BOLA, throughput, abandonment) | Problem 16 |
| [feast-dev/feast](https://github.com/feast-dev/feast) | Python | Point-in-time joins, online/offline stores | Problem 31 |
| [vllm-project/vllm](https://github.com/vllm-project/vllm) | Python/CUDA | PagedAttention, prefix caching, continuous batching | Problem 32 |
| [sgl-project/sglang](https://github.com/sgl-project/sglang) | Python | RadixAttention, cache-aware routing | Problem 32 |

## 3.1 Testing and verification

| Repository | Read for | KB |
|---|---|---|
| [jepsen-io/jepsen](https://github.com/jepsen-io/jepsen) | Fault-injection framework; histories and checkers | F01 f03 |
| [jepsen-io/knossos](https://github.com/jepsen-io/knossos) | Linearizability checking | F01 f03 §2.3 |
| [jepsen-io/elle](https://github.com/jepsen-io/elle) | Transactional anomaly inference from dependency graphs | F01 f03 |
| [anishathalye/porcupine](https://github.com/anishathalye/porcupine) | Fast linearizability checker in Go | F01 f03 |
| [ept/hermitage](https://github.com/ept/hermitage) | What each database's isolation levels actually prevent | F01 f03 §3.3 |
| [tlaplus/tlaplus](https://github.com/tlaplus/tlaplus) | TLA+ tools (TLC model checker) | F03 f01 |
| [Raft site with TLA+ spec and implementations](https://raft.github.io/) | Visualizations, the spec, a catalog of implementations | F03 f01 |
| [MIT 6.824 / 6.5840 Distributed Systems](https://pdos.csail.mit.edu/6.824/) | Labs: build Raft, a sharded KV store | F03 f01 |
| [Jepsen consistency map](https://jepsen.io/consistency) | The model hierarchy used in Folder 01 file 03 | F01 f03 |
| [Jepsen analyses](https://jepsen.io/analyses) | Real database bugs found by testing | All |

---

## 4. The link check

```python
"""verify_reading_list.py - check every URL in Folder 10 of this KB (one measured run; needs network access).

Usage: python verify_reading_list.py [kb_root]          (default: the current directory)
Extracts http(s) links from 10-*/*.md, requests each one sequentially (HEAD, then GET if HEAD is refused), follows
redirects, and classifies: OK (2xx), BLOCKED (401/403/429: the server exists but refuses automated clients), or
BROKEN (404/410/other errors). Broken links are what an editor must fix; blocked ones need a manual click.
"""
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

URL = re.compile(r"\((https?://[^)\s]+)\)")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) KB-link-check",
      "Accept": "text/html,application/xhtml+xml,*/*;q=0.8", "Accept-Language": "en-US,en;q=0.9"}


def fetch(url: str) -> tuple[str, int | str]:
    for method in ("HEAD", "GET"):
        try:
            req = urllib.request.Request(url, method=method, headers=UA)
            with urllib.request.urlopen(req, timeout=15) as r:
                return "OK", r.status
        except urllib.error.HTTPError as e:
            if method == "HEAD" and e.code in (400, 403, 405, 429, 500, 501):
                continue                                         # many servers refuse HEAD: retry with GET
            if e.code in (401, 403, 429):
                return "BLOCKED", e.code
            return "BROKEN", e.code
        except Exception as e:                                   # DNS, TLS, timeouts
            if method == "HEAD":
                continue
            return "BROKEN", type(e).__name__
    return "BROKEN", "unknown"


def main() -> None:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    files = sorted(root.glob("10-*/*.md"))
    urls = []
    for f in files:
        for u in URL.findall(f.read_text(encoding="utf-8")):
            if u not in urls:
                urls.append(u)
    counts = {"OK": 0, "BLOCKED": 0, "BROKEN": 0}
    problems = []
    for u in urls:
        status, code = fetch(u)
        counts[status] += 1
        if status != "OK":
            problems.append((status, code, u))
        time.sleep(0.2)                                          # be polite to the hosts
    print(f"checked {len(urls)} unique URLs in {len(files)} files")
    for status, code, u in problems:
        print(f"  {status:<8} {code!s:<22} {u}")
    print(f"OK {counts['OK']}, BLOCKED {counts['BLOCKED']}, BROKEN {counts['BROKEN']}")
    print(f"summary: {counts['OK'] + counts['BLOCKED']}/{len(urls)} URLs reachable "
          f"({counts['BROKEN']} broken)")


if __name__ == "__main__":
    main()
```

Output (one measured run on 2026-10-27; network-dependent):

```text
checked 161 unique URLs in 3 files
  BLOCKED  403                    https://netflixtechblog.com/
  BLOCKED  403                    https://cacm.acm.org/research/how-amazon-web-services-uses-formal-methods/
  BLOCKED  403                    https://netflixtechblog.com/performance-under-load-3e6fa9a60581
  BLOCKED  403                    https://netflixtechblog.com/per-title-encode-optimization-7e99442b62a2
  BLOCKED  403                    https://netflixtechblog.com/vmaf-the-journey-continues-44b51ee9ed12
  BLOCKED  403                    https://queue.acm.org/detail.cfm?id=2839461
  BLOCKED  403                    https://dl.acm.org/doi/10.1145/2517349.2517350
  BLOCKED  403                    https://dl.acm.org/doi/10.1145/3318464.3386134
  BLOCKED  403                    https://queue.acm.org/detail.cfm?id=3022184
  BLOCKED  403                    https://dl.acm.org/doi/10.1145/3098822.3098842
  BLOCKED  403                    https://dl.acm.org/doi/10.1145/3600006.3613147
  BLOCKED  403                    https://dl.acm.org/doi/10.1145/2619239.2626296
OK 149, BLOCKED 12, BROKEN 0
summary: 161/161 URLs reachable (0 broken)
```

"BLOCKED" means the server exists but refuses automated clients (typically HTTP 403 from bot protection on publisher
sites). Those links were not machine-verified, so open them by hand. "BROKEN" would mean a link to fix. The final
build of this file has none (see the summary line).
