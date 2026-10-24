# 4.5 · Pillar 4 — Production Failure Modes & Diagnostic Checklist (I/O, Networking, Serialization)

> I/O incidents present as **"everything is slow" or "nothing works"** with misleading symptoms: CPU is low, the heap is fine, threads are "RUNNABLE". This file has the playbooks (composite war stories, each mechanism demonstrated in [4.1](01-IO-Models-Blocking-NIO-AIO.md)–[4.4](04-Networking-Sockets-HttpClient-TLS.md) or [Pillar 1](../01-JVM-Internals/02-Runtime-Data-Areas-Off-Heap-FFM.md)), an OS-level diagnostic toolkit, and the metrics that catch them early.

---

## 1. Incident playbooks

### 🔥 Story 1 — "Too many open files" after a week of uptime

* **Symptom:** `java.io.IOException: Too many open files`, at first in log rotation and then in every new socket accept.
* **Evidence:** `ls /proc/<pid>/fd | wc -l` returned 65,412 (with `ulimit -n` = 65,536). `lsof -p <pid> | awk '{print $9}' | sort | uniq -c | sort -rn | head` showed thousands of handles to the same report directory.
* **Root cause:** `Files.list(dir).filter(...).count()` inside a health check: a lazy stream that was never closed ([4.1 §2.3](01-IO-Models-Blocking-NIO-AIO.md#23-files-the-operations-and-their-traps-)).
* **Fix:** try-with-resources around every `Files.lines/list/walk/find`, plus a CI static-analysis rule (Error Prone `StreamResourceLeak`, Sonar S2095).
* **Prevention:** alert on `process.files.open / process.files.max > 0.8` (Micrometer `FileDescriptorMetrics`).

### 🔥 Story 2 — "Direct memory OOM in the gateway"

* **Symptom:** `io.netty.util.internal.OutOfDirectMemoryError` after hours; RSS grew steadily.
* **Evidence:** logs contained `LEAK: ByteBuf.release() was not called before it's garbage-collected` with a trace pointing at a custom auth handler.
* **Root cause:** the handler consumed the request `ByteBuf` on an error path without releasing it ([4.2 §3.2](02-Zero-Copy-MMAP-Netty.md#32-the-netty-rules-that-prevent-90-of-incidents)).
* **Fix:** `ReferenceCountUtil.release(msg)` in `finally`, or extend `SimpleChannelInboundHandler`; paranoid leak detection in integration tests.

### 🔥 Story 3 — "Reactive service, one slow DB call, 30-second freezes"

* **Root cause:** a blocking JDBC call (`repository.findById`) in a WebFlux handler ran **on the Netty event loop**. Every connection served by that loop froze until the query returned.
* **Evidence:** thread dumps showed `reactor-http-nio-3` in `SocketInputStream.read` under a JDBC driver frame.
* **Fix:** R2DBC or `publishOn(Schedulers.boundedElastic())` for blocking calls; BlockHound in tests. Better, for request/response services: Spring MVC on virtual threads ([00 §3](../00-Executive-Architecture-Map.md#3-paradigm-1--virtual-threads-vs-reactive-the-decision-quantified)).

### 🔥 Story 4 — "CLOSE_WAIT storm"

* **Symptom:** the outbound HTTP pool was exhausted (`Timeout waiting for connection from pool`), and `ss -tan state close-wait` showed 4,000 sockets.
* **Root cause:** responses with non-2xx status were returned early **without consuming or closing the body**, so the connection was never released back to the pool or closed.
* **Fix:** always close responses (`try (var body = response.body())`, `EntityUtils.consume`, OkHttp's `response.close()`); with JDK `HttpClient`, close the `InputStream` from `BodyHandlers.ofInputStream()`.

### 🔥 Story 5 — "Cannot assign requested address"

* **Root cause:** a new `HttpClient` per request (copied from a tutorial) left 28,000 sockets in `TIME_WAIT` and exhausted the ephemeral port range, plus a selector thread leaked per client.
* **Fix:** a singleton client per configuration ([4.4 §2.1](04-Networking-Sockets-HttpClient-TLS.md#21-facts-you-should-know)).

### 🔥 Story 6 — "Remote code execution via a monitoring port"

* **Root cause:** a JMX RMI port exposed to the internal network without authentication. An attacker sent a serialized gadget chain, and the classpath had a vulnerable Commons Collections ([4.3 §2](03-Serialization-Security-Protobuf-Avro-Jackson.md#2-why-java-serialization-is-dangerous-)).
* **Fix:** no unauthenticated JMX/RMI (use JFR, Micrometer, JMX over authenticated TLS, or bind to localhost); JEP 290 filters (`-Djdk.serialFilter`); dependency scanning.

### ⚡ Story 7 — "Rolling deploy breaks sessions"

* **Root cause:** HTTP sessions were stored in a distributed cache using Java serialization. Version N+1 added a field to `UserSession` without a `serialVersionUID`, giving `InvalidClassException: local class incompatible` for every session written by version N.
* **Fix:** an explicit `serialVersionUID`; better, a JSON or Protobuf session format with tolerant readers; versioned cache keys during migrations.

### ⚡ Story 8 — "The Jackson 3 upgrade ate our validation"

* **Root cause:** after moving to Spring Boot 4 (Jackson 3), unknown JSON properties were silently ignored, so client typos (`"emial"`) produced half-empty records that passed into the system ([4.3 §4.1](03-Serialization-Security-Protobuf-Avro-Jackson.md#41-jackson-3-vs-2-what-changed-verified-defaults)).
* **Fix:** explicit `FAIL_ON_UNKNOWN_PROPERTIES` where strictness is required, plus Bean Validation on DTOs.

### ⚡ Story 9 — "Legit documents rejected after the upgrade"

* **Root cause:** a GIS integration sends GeoJSON nested 640 levels deep. Jackson 3's default max nesting depth is **500** (it was 1,000 in 2.x), so `StreamConstraintsException` was thrown.
* **Fix:** a dedicated mapper for that endpoint with `StreamReadConstraints.builder().maxNestingDepth(1000)`, without raising limits globally.

### ⚡ Story 10 — "Native memory grows with thread count"

* **Root cause:** 2,000 platform threads wrote large **heap** `ByteBuffer`s to `SocketChannel`s. Each thread cached a large temporary direct buffer forever ([1.2 §7.3](../01-JVM-Internals/02-Runtime-Data-Areas-Off-Heap-FFM.md#73-the-hidden-per-thread-temporary-direct-buffer-cache-)).
* **Fix:** `-Djdk.nio.maxCachedBufferSize=262144`, direct buffers, fewer threads.

### ⚡ Story 11 — "Every RPC takes at least 40 ms"

* **Root cause:** a custom TCP client wrote the request header and body in two small writes with Nagle enabled, combined with the server's delayed ACK.
* **Fix:** `TCP_NODELAY=true`, plus a single gathered write.

### ⚡ Story 12 — "Writes to the old primary after failover"

* **Root cause:** a JVM DNS TTL set to `-1` (cache forever, from an old hardening guide), combined with pooled connections that had no max lifetime ([4.4 §3](04-Networking-Sockets-HttpClient-TLS.md#3-dns-caching-in-the-jvm-)).
* **Fix:** a TTL of 10–30 s, pool `maxLifetime`, and failover drills.

### ⚡ Story 13 — "Mojibake in Windows batch output"

* **Root cause:** a legacy `new FileReader(file)` assumption combined with an old JDK default charset (Cp1252), and a UTF-8 file.
* **Fix:** explicit `StandardCharsets.UTF_8` everywhere. JDK 18+ defaults to UTF-8, but `native.encoding` and console encodings still differ ([4.1 §2.1](01-IO-Models-Blocking-NIO-AIO.md#21-the-decorator-hierarchy)).

---

## 2. OS-level diagnostic toolkit

```bash
# file descriptors
ls /proc/$PID/fd | wc -l ; cat /proc/$PID/limits | grep "open files"
lsof -p $PID | awk '{print $5}' | sort | uniq -c | sort -rn        # by type: REG, IPv4, sock, FIFO…

# TCP state per process
ss -tanp | grep "pid=$PID" | awk '{print $1}' | sort | uniq -c     # ESTAB / CLOSE-WAIT / TIME-WAIT counts
ss -ti dst <peer-ip>                                                # rtt, retrans, cwnd per connection
cat /proc/sys/net/ipv4/ip_local_port_range                          # ephemeral range (port exhaustion)

# syscalls and blocking
strace -f -tt -e trace=network,read,write,epoll_wait -p $PID 2>&1 | head    # who blocks where (Linux)
perf trace -p $PID --duration 10                                     # lighter-weight alternative

# packets
tcpdump -i any -nn host <peer> and port 443 -w /tmp/cap.pcap         # analyse in Wireshark

# JVM side
jcmd $PID Thread.print | grep -B2 -A8 "SocketInputStream\|NioSocketImpl\|EPoll"   # threads blocked in I/O
jcmd $PID VM.native_memory summary | grep -A2 Other                  # direct buffers
jcmd $PID JFR.start settings=profile duration=60s filename=/tmp/io.jfr
jfr print --events jdk.SocketRead,jdk.FileRead /tmp/io.jfr | head     # slow I/O (JDK 25: ≥ 1 ms, throttled 100/s)
```

---

## 3. Metrics and alerts

| Signal | Source | Alert / meaning |
|---|---|---|
| Open file descriptors | Micrometer `process.files.open`, `process.files.max` | > 80% of the max |
| Direct and mapped buffers | `jvm.buffer.memory.used{id=direct\|mapped}`; JFR `jdk.DirectBufferStatistics`; Netty allocator metrics | Monotonic growth |
| HTTP client pool | Leased/pending/available connections (Apache/OkHttp/Reactor Netty metrics) | Pending > 0 sustained |
| Outbound latency | `http.client.requests` histograms per host | p99 vs SLO; timeouts count |
| TCP retransmits | node_exporter `node_netstat_Tcp_RetransSegs` | Spikes indicate network problems |
| `CLOSE_WAIT`/`TIME_WAIT` counts | node_exporter `node_sockstat_TCP_tw`, custom `ss` exporters | Thousands |
| Deserialization filter rejections | JFR `jdk.Deserialization` (enable it) / logs | Any rejection is a potential attack or a bug |
| Netty leaks | Log alerts on `LEAK:` | Any occurrence |

---

## 4. Code-review checklist (I/O)

- [ ] Every stream, channel, socket, `Files.*` stream and HTTP response body is closed (try-with-resources).
- [ ] Explicit charsets on every byte↔char boundary.
- [ ] Buffered I/O for byte or line-oriented processing; `transferTo` for copies.
- [ ] NIO: `flip()` before reads; loops for partial reads and writes; `OP_WRITE` only while pending.
- [ ] Netty: no blocking in handlers; every consumed `ByteBuf` released; writability checked; frame and aggregate limits set.
- [ ] Every network call has connect and read timeouts plus an overall deadline; retries only for idempotent operations.
- [ ] One HTTP client per configuration, reused; pool idle timeout < LB/NAT idle timeout; max connection lifetime set.
- [ ] `TCP_NODELAY` for RPC-style protocols.
- [ ] No Java deserialization of untrusted data; JEP 290 filter set for any remaining `ObjectInputStream`.
- [ ] Jackson mappers built once; limits deliberate; polymorphism by logical names only; behaviour verified after Jackson 2→3.
- [ ] Protobuf numbers never reused (`reserved`); Avro changes compatibility-checked against the registry in CI.
- [ ] Large payloads streamed, not buffered (`ofInputStream`, `JsonParser`).
