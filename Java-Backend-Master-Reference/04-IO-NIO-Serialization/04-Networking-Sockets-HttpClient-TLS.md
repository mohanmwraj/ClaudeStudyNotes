# 4.4 · Networking for Backend Engineers — Sockets, Timeouts, `HttpClient`, DNS, TLS, Unix-Domain Sockets

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** `java.net`, `java.net.http` (JEP 321), `javax.net.ssl` Javadoc (JDK 25); JEP 353/373 (socket reimplementation), JEP 380 (Unix-domain socket channels), JEP 517 (HTTP/3 client, JDK 26), JEP 527 (post-quantum hybrid key exchange for TLS 1.3, JDK 27); RFC 9293 (TCP), RFC 8446 (TLS 1.3); `InetAddress` Javadoc ("InetAddress Caching").
> All defaults and outputs were captured on Temurin 25.0.4.1 (Windows 11). Socket buffer defaults are OS-specific.

---

## 1. TCP from the JVM's point of view 🔥

### 1.1 Real defaults (JDK 25)

```
Socket defaults: TCP_NODELAY=false SO_KEEPALIVE=false SO_TIMEOUT=0 SO_RCVBUF=65536 SO_SNDBUF=65536 SO_LINGER=-1 REUSEADDR=false
HttpClient default version=HTTP_2 connectTimeout=Optional.empty followRedirects=NEVER
```

| Option | Default | What it means | Production guidance |
|---|---|---|---|
| `SO_TIMEOUT` (read timeout) | **0 = wait forever** | A blocking `read` never returns if the peer goes silent | **Always set one**, per protocol |
| Connect timeout | **Infinite** (OS SYN retries: ~20 s on Windows, ~2 min on Linux) | `socket.connect(addr)` without a timeout | `connect(addr, timeoutMs)`; `HttpClient.Builder.connectTimeout` |
| `TCP_NODELAY` | false (Nagle **on**) | Small writes are coalesced until an ACK arrives; with delayed ACKs this adds up to ~40–200 ms | **true** for request/response protocols (most RPC frameworks set it) |
| `SO_KEEPALIVE` | false | OS probes after ~2 h idle (system-tunable) | Use application-level heartbeats or idle timeouts; enable keepalive for long-lived connections through NATs and firewalls |
| `SO_LINGER` | −1 (off) | `close()` returns immediately; the kernel finishes sending | `0` sends RST (abortive close), occasionally used to avoid `TIME_WAIT` (with care) |
| `SO_REUSEADDR` | false (client) / true for `ServerSocket` on most platforms | Rebind a port in `TIME_WAIT` | Servers restart faster |
| `SO_RCVBUF`/`SO_SNDBUF` | OS default (64 KB here; Linux autotunes) | Window size limits throughput on high-latency links (BDP = bandwidth × RTT) | Leave autotuning on unless measured |
| Backlog | 50 (`ServerSocket`) | Completed-handshake queue awaiting `accept()` | Raise for bursty servers (and the OS's `somaxconn`) |

### 1.2 Connection lifecycle failure modes 🔥

```
client                          server
  SYN ─────────────────────────►            connect timeout covers this
  ◄──────────────────── SYN-ACK
  ACK ─────────────────────────►  accept queue (backlog) → accept()
  request ─────────────────────►            write may block if the peer's receive window is full
  ◄─────────────────── response             read timeout covers waiting here
  FIN ─────────────────────────►  CLOSE_WAIT  ← server app hasn't called close() yet (LEAK if it stays!)
  ◄──────────────────────── ACK
  ◄──────────────────────── FIN
  ACK ─────────────────────────►
  TIME_WAIT (2×MSL ≈ 60 s on Linux) ← on the side that closed FIRST
```

| Symptom (`ss -tan` / `netstat`) | Meaning | Fix |
|---|---|---|
| Thousands of `CLOSE_WAIT` on your service | **Your code never closed sockets** the peer closed (leaked responses, unconsumed bodies) | try-with-resources; always consume or close HTTP response bodies |
| Thousands of `TIME_WAIT` on the client, then `BindException: Address already in use` / `Cannot assign requested address` | Ephemeral port exhaustion from a **new connection per request** | Connection pooling / keep-alive; reuse the `HttpClient` |
| `SYN_SENT` piling up | Peer unreachable or firewalled | Connect timeouts; circuit breakers |
| `Connection reset by peer` | RST: the peer crashed, an idle timeout on a load balancer or NAT dropped the connection, or `SO_LINGER(0)` | Pool idle timeout **shorter** than the LB/NAT idle timeout; validate or retry idempotent requests |

### 1.3 Runnable: a read timeout saves a thread

<!-- run: -->
```java
import java.io.InputStream;
import java.net.*;

public class ReadTimeout {
    public static void main(String[] args) throws Exception {
        try (ServerSocket silent = new ServerSocket(0, 50, InetAddress.getLoopbackAddress())) {   // accepts, never replies
            Thread.ofVirtual().start(() -> { try { silent.accept(); Thread.sleep(10_000); } catch (Exception ignored) { } });
            try (Socket s = new Socket()) {
                s.connect(new InetSocketAddress(InetAddress.getLoopbackAddress(), silent.getLocalPort()), 1_000);  // connect timeout
                s.setSoTimeout(300);                                                                              // read timeout
                s.setTcpNoDelay(true);
                long t0 = System.nanoTime();
                try (InputStream in = s.getInputStream()) { in.read(); }
                catch (SocketTimeoutException e) {
                    System.out.printf("read() gave up after ~%d00 ms: %s%n", (System.nanoTime() - t0) / 100_000_000, e.getMessage());
                }
            }
        }
    }
}
```

Output (verified):

```
read() gave up after ~300 ms: Read timed out
```

Without `setSoTimeout`, that `read()` blocks **forever**: a platform thread or connection lost per silent peer. There is **no write timeout** on blocking sockets in `java.net`. A write blocks while the peer's receive window is full. Protect against slow readers with NIO/Netty (`isWritable`) or an overall request deadline.

---

## 2. `java.net.http.HttpClient` (JDK 11+) 🔥

### 2.1 Facts you should know

* **Thread-safe and expensive to build. Create one per configuration and reuse it.** It owns a connection pool, a selector thread and an executor. Creating a client per request leaks threads and connections (`TIME_WAIT` storms).
* HTTP/2 by default, falling back to HTTP/1.1 per connection. Over TLS it negotiates via ALPN. **HTTP/3 (QUIC) support arrived in JDK 26 (JEP 517)** as an opt-in version.
* **No connect timeout and no request timeout by default**: set `Builder.connectTimeout` and `HttpRequest.Builder.timeout` (which covers the time until response headers arrive).
* `followRedirects` defaults to `NEVER`.
* `send` blocks the caller, which is perfect on virtual threads. `sendAsync` returns a `CompletableFuture`, completed on the client's executor (the default is a cached thread pool; pass `Executors.newVirtualThreadPerTaskExecutor()` for VT-based I/O completion).
* `BodyHandlers.ofString/ofByteArray` buffer the **entire body in memory**. Use `ofInputStream`/`ofLines`/`ofFile` or a custom `BodySubscriber` for large responses, and **close the `InputStream`** to release the connection.
* Connection pool tuning via system properties: `jdk.httpclient.keepalive.timeout` (idle connection lifetime), `jdk.httpclient.connectionPoolSize`, and `jdk.httpclient.maxstreams` (HTTP/2).

### 2.2 Runnable: server + client, timeouts, and concurrent fan-out on virtual threads

The server is the JDK's built-in `com.sun.net.httpserver.HttpServer`, running on a virtual-thread executor.

<!-- run: timeout=60 -->
```java
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;

public class HttpClientDemo {
    public static void main(String[] args) throws Exception {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());            // one VT per exchange
        server.createContext("/hello", ex -> respond(ex, 200, "hello " + ex.getRequestURI().getQuery()));
        server.createContext("/echo", ex -> respond(ex, 201, new String(ex.getRequestBody().readAllBytes(), StandardCharsets.UTF_8).toUpperCase()));
        server.createContext("/slow", ex -> { sleep(2_000); respond(ex, 200, "too late"); });
        server.start();
        String base = "http://127.0.0.1:" + server.getAddress().getPort();

        HttpClient client = HttpClient.newBuilder()                                 // build ONCE, reuse everywhere
            .connectTimeout(Duration.ofSeconds(2))
            .executor(Executors.newVirtualThreadPerTaskExecutor())
            .build();

        HttpResponse<String> r1 = client.send(HttpRequest.newBuilder(URI.create(base + "/hello?name=ann"))
            .timeout(Duration.ofSeconds(1)).GET().build(), HttpResponse.BodyHandlers.ofString());
        System.out.println("GET  " + r1.statusCode() + " " + r1.body() + " (negotiated " + r1.version() + " over cleartext)");

        HttpResponse<String> r2 = client.send(HttpRequest.newBuilder(URI.create(base + "/echo"))
            .header("Content-Type", "text/plain").POST(HttpRequest.BodyPublishers.ofString("payload")).build(), HttpResponse.BodyHandlers.ofString());
        System.out.println("POST " + r2.statusCode() + " " + r2.body());

        try {
            client.send(HttpRequest.newBuilder(URI.create(base + "/slow")).timeout(Duration.ofMillis(300)).build(), HttpResponse.BodyHandlers.ofString());
        } catch (HttpTimeoutException e) { System.out.println("slow endpoint → HttpTimeoutException: " + e.getMessage()); }

        // 100 concurrent requests from 100 virtual threads, sharing ONE client (pooled connections)
        List<Integer> statuses = Collections.synchronizedList(new ArrayList<>());
        try (var vts = Executors.newVirtualThreadPerTaskExecutor()) {
            for (int i = 0; i < 100; i++) {
                int id = i;
                vts.submit(() -> statuses.add(client.send(HttpRequest.newBuilder(URI.create(base + "/hello?name=u" + id)).build(),
                    HttpResponse.BodyHandlers.discarding()).statusCode()));
            }
        }
        System.out.println("fan-out: " + statuses.size() + " responses, all 200 = " + statuses.stream().allMatch(s -> s == 200));

        CompletableFuture<String> async = client.sendAsync(HttpRequest.newBuilder(URI.create(base + "/hello?name=async")).build(),
            HttpResponse.BodyHandlers.ofString()).thenApply(HttpResponse::body);
        System.out.println("sendAsync → " + async.get(2, TimeUnit.SECONDS));

        client.close();                                                              // JDK 21+: HttpClient is AutoCloseable
        server.stop(0);
    }

    static void respond(com.sun.net.httpserver.HttpExchange ex, int status, String body) throws java.io.IOException {
        byte[] b = body.getBytes(StandardCharsets.UTF_8);
        try { ex.sendResponseHeaders(status, b.length); ex.getResponseBody().write(b); }
        catch (java.io.IOException clientGone) { /* client timed out and closed: expected for /slow */ }
        finally { ex.close(); }
    }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { Thread.currentThread().interrupt(); } }
}
```

Output (verified):

```
GET  200 hello name=ann (negotiated HTTP_1_1 over cleartext)
POST 201 PAYLOAD
slow endpoint → HttpTimeoutException: request timed out
fan-out: 100 responses, all 200 = true
sendAsync → hello name=async
```

The version came back as `HTTP_1_1` even though the client prefers `HTTP_2`: over cleartext the client asks for an `h2c` upgrade, and the built-in server doesn't support HTTP/2, so it fell back. Over TLS, HTTP/2 is negotiated through ALPN when the server supports it.

### 2.3 Timeouts: the full set you need for every outbound call

| Timeout | Default (JDK `HttpClient`) | Set it with |
|---|---|---|
| DNS resolution | OS resolver (seconds) | Resolver config; caching (§3) |
| Connect | **None** | `HttpClient.Builder.connectTimeout` |
| Time to response headers | **None** | `HttpRequest.Builder.timeout` |
| Body read | Not covered by the request timeout once headers have arrived | Stream the body with your own deadline, or `CompletableFuture.orTimeout` |
| Pool acquisition / HTTP/2 stream limit | Implicit queueing | Bound concurrency (semaphore, bulkhead) |
| **Overall request deadline** (including retries) | None | Your code: deadline propagation (structured concurrency scope timeout, Resilience4j `TimeLimiter`), Pillar 6 |

**Retry rules:** retry only **idempotent** operations (GET, PUT with full replacement, or POST with idempotency keys, Pillar 6), use exponential back-off with jitter, cap the total time, and never retry inside a tight timeout budget without accounting for it.

---

## 3. DNS caching in the JVM ⚡

* `InetAddress` caches successful lookups for `networkaddress.cache.ttl` seconds (security property). When it's unset (it was `null` on this JDK 25), the implementation default is **30 seconds** (historically "forever" with a SecurityManager installed, a common surprise in old app servers).
* Negative lookups (failures) are cached for `networkaddress.cache.negative.ttl` = **10 s** (the real value printed above).
* Recent JDKs add `networkaddress.cache.stale.ttl` (keep serving stale entries while lookups fail). It wasn't set on this build.
* **Failover impact:** after a DNS-based failover (RDS/Aurora endpoints, Kubernetes services resolved via external DNS), clients keep using cached IPs for up to the TTL, **and pooled connections keep using the old IP until they close**. Keep the TTL low (5–30 s) for dynamic endpoints, and set connection max-lifetimes in pools (Hikari `maxLifetime`, HTTP client idle timeouts).
* Set via `java.security` or programmatically before first use: `Security.setProperty("networkaddress.cache.ttl", "10")`. `-Dsun.net.inetaddr.ttl` is the legacy system-property override.

---

## 4. TLS in Java ⚡

### 4.1 Defaults (JDK 25, real output)

```
TLS default enabled protocols: [TLSv1.3, TLSv1.2]
named groups: [x25519, secp256r1, secp384r1, secp521r1, x448, ffdhe2048, ffdhe3072, ffdhe4096, ffdhe6144, ffdhe8192]
```

* TLS 1.0 and 1.1 are disabled (`jdk.tls.disabledAlgorithms`), and SSLv3 is long gone.
* **JDK 27 (JEP 527)** adds **post-quantum hybrid key exchange** for TLS 1.3 (X25519 combined with ML-KEM): "harvest now, decrypt later" protection without application changes. This is worth tracking for long-lived sensitive data.
* Handshakes are the expensive part (asymmetric crypto plus round trips). **Reuse connections** (keep-alive, HTTP/2 multiplexing). Session resumption (TLS 1.3 PSK tickets) is on by default in the JDK.

### 4.2 Mutual TLS (client certificates)

<!-- run: compile -->
```java
import java.io.InputStream;
import java.net.http.HttpClient;
import java.nio.file.*;
import java.security.KeyStore;
import javax.net.ssl.*;

public final class MtlsClientFactory {
    /** Builds an HttpClient presenting a client certificate (mTLS) and trusting only the given CA bundle. */
    public static HttpClient create(Path clientP12, char[] p12Password, Path truststoreP12, char[] tsPassword) throws Exception {
        KeyStore identity = KeyStore.getInstance("PKCS12");
        try (InputStream in = Files.newInputStream(clientP12)) { identity.load(in, p12Password); }
        KeyManagerFactory kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm());
        kmf.init(identity, p12Password);

        KeyStore trust = KeyStore.getInstance("PKCS12");
        try (InputStream in = Files.newInputStream(truststoreP12)) { trust.load(in, tsPassword); }
        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(trust);

        SSLContext ctx = SSLContext.getInstance("TLS");
        ctx.init(kmf.getKeyManagers(), tmf.getTrustManagers(), null);
        SSLParameters params = ctx.getDefaultSSLParameters();
        params.setProtocols(new String[] {"TLSv1.3", "TLSv1.2"});
        params.setEndpointIdentificationAlgorithm("HTTPS");          // hostname verification (on by default for HttpClient)
        return HttpClient.newBuilder().sslContext(ctx).sslParameters(params).build();
    }
}
```

Operational notes: certificates expire, so **reload** key material without a restart (custom `X509ExtendedKeyManager` reading rotated files, or rotate pods). Never disable hostname verification or install "trust-all" `TrustManager`s, even in test code that might ship. In Kubernetes, service meshes (Istio, Linkerd) often handle mTLS at the sidecar; Pillar 8 covers mTLS in Spring.

**Debugging TLS:** `-Djavax.net.debug=ssl:handshake` (very verbose), `openssl s_client -connect host:443 -servername host`, and check `jdk.tls.disabledAlgorithms` when old peers fail.

---

## 5. Unix-domain sockets (JDK 16, JEP 380) 🧊

Local IPC without TCP: no ports, filesystem permissions as access control, and lower overhead. Used with sidecars (Envoy, Docker's API socket, PostgreSQL's local socket), and works on Linux, macOS **and Windows 10+**.

<!-- run: -->
```java
import java.net.StandardProtocolFamily;
import java.net.UnixDomainSocketAddress;
import java.nio.ByteBuffer;
import java.nio.channels.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

public class UnixDomainEcho {
    public static void main(String[] args) throws Exception {
        Path dir = Files.createTempDirectory("uds");
        Path socketFile = dir.resolve("app.sock");
        try (ServerSocketChannel server = ServerSocketChannel.open(StandardProtocolFamily.UNIX)) {
            server.bind(UnixDomainSocketAddress.of(socketFile));
            Thread.ofVirtual().start(() -> {
                try (SocketChannel conn = server.accept()) {
                    ByteBuffer buf = ByteBuffer.allocate(64);
                    conn.read(buf); buf.flip();
                    conn.write(ByteBuffer.wrap(("ack:" + StandardCharsets.UTF_8.decode(buf)).getBytes(StandardCharsets.UTF_8)));
                } catch (Exception e) { throw new RuntimeException(e); }
            });
            try (SocketChannel client = SocketChannel.open(UnixDomainSocketAddress.of(socketFile))) {
                client.write(ByteBuffer.wrap("ping".getBytes(StandardCharsets.UTF_8)));
                ByteBuffer reply = ByteBuffer.allocate(64);
                client.read(reply); reply.flip();
                System.out.println("over " + socketFile.getFileName() + ": " + StandardCharsets.UTF_8.decode(reply)
                    + " | socket file exists while bound: " + Files.exists(socketFile));
            }
        } finally {
            Files.deleteIfExists(socketFile);          // the socket FILE is not removed automatically on close
            Files.deleteIfExists(dir);
        }
    }
}
```

Output (verified on Windows 11):

```
over app.sock: ack:ping | socket file exists while bound: true
```

---

## 6. Production failure modes & diagnostics (networking)

| Failure | Signature | Fix |
|---|---|---|
| Hung threads on network reads | Thread dumps: threads in `SocketInputStream.read`/`NioSocketImpl.read` for minutes | Read timeouts everywhere; overall deadlines |
| `CLOSE_WAIT` accumulation | `ss -tanp state close-wait` shows thousands for your PID | Close sockets and responses; consume bodies; fix leaks in error paths |
| Ephemeral port exhaustion | `BindException: Cannot assign requested address`; many `TIME_WAIT` | Reuse clients and pools; keep-alive; never a new `HttpClient` per request |
| 40–200 ms latency floor on small RPCs | Nagle + delayed ACK interaction | `TCP_NODELAY=true` |
| Stale endpoints after failover | Traffic still going to the old IP | Low DNS TTL; connection max-lifetime |
| Resets after idle periods | `Connection reset` on the first request after idle | Pool idle timeout < LB/NAT idle timeout; validation and retries for idempotent calls |
| TLS handshake CPU spikes | Many short-lived TLS connections | Connection reuse, HTTP/2, session resumption |
| Handshake failures after a JDK upgrade | `SSLHandshakeException: no appropriate protocol` | Peers still on TLS 1.0/1.1 or weak ciphers: upgrade the peers; don't re-enable weak algorithms globally |
| Large response OOM | `BodyHandlers.ofString()` on huge payloads | Streaming body handlers |

**Commands:** `ss -tanp` / `netstat -ano` (states per PID), `ss -ti` (RTT, retransmits, cwnd), `tcpdump -i any port 443 -w cap.pcap` + Wireshark, `curl -v --http2`, `openssl s_client`, JFR `jdk.SocketRead`/`jdk.SocketWrite` (thresholded I/O events), `-Djdk.httpclient.HttpClient.log=errors,requests` (HttpClient logging).

---

## 7. Interview Q&A

<details><summary><b>Q1. 🔥 What timeouts does a `java.net.Socket` have by default, and what happens without them?</b></summary>

None. The connect timeout is left to the OS (seconds to minutes of SYN retries) and `SO_TIMEOUT` is 0, so reads block forever. A silent or half-dead peer ties up a thread (or a connection-pool slot) indefinitely. Always use `connect(addr, timeout)` and `setSoTimeout`, or the equivalent client settings, and wrap calls in an overall deadline.
</details>

<details><summary><b>Q2. 🔥 Why should an `HttpClient` be a singleton (per configuration)?</b></summary>

It owns a connection pool, a selector manager thread and an executor. Reusing it gives keep-alive and HTTP/2 multiplexing (fewer TCP and TLS handshakes, no `TIME_WAIT` storms). Creating one per request leaks threads and connections and exhausts ephemeral ports.
</details>

<details><summary><b>Q3. ⚡ Explain `CLOSE_WAIT` vs `TIME_WAIT` and what each indicates.</b></summary>

`CLOSE_WAIT`: the peer closed its side, and **your application hasn't closed** the socket yet. Large numbers indicate a resource leak in your code. `TIME_WAIT`: the state of the side that closed **first**, kept for 2×MSL so delayed packets don't corrupt new connections. Large numbers on a client indicate connection churn (no pooling) and can exhaust ephemeral ports.
</details>

<details><summary><b>Q4. ⚡ Why does `TCP_NODELAY` matter for RPC latency?</b></summary>

Nagle's algorithm holds small segments until outstanding data is ACKed, and the receiver's delayed-ACK timer (tens to hundreds of ms) can then delay request/response exchanges whose writes are split. Disabling Nagle (`TCP_NODELAY=true`) sends small messages immediately. Most RPC frameworks set it.
</details>

<details><summary><b>Q5. 🔥 After a database failover, half the pods keep failing for minutes. JVM-side causes?</b></summary>

JVM DNS caching (TTL 30 s by default, longer if configured, or "forever" on legacy setups), plus **pooled connections still bound to the old IP**: the pool doesn't re-resolve until connections close. Mitigate with a low `networkaddress.cache.ttl`, a pool `maxLifetime`, connection validation, and fast failure detection (timeouts and circuit breakers).
</details>

<details><summary><b>Q6. 🧊 What does JEP 527 (JDK 27) add to TLS?</b></summary>

Hybrid post-quantum key exchange for TLS 1.3, combining a classical group (such as X25519) with ML-KEM. Session keys stay secure even against future quantum attacks on recorded traffic, with no application code changes when both peers support it.
</details>

---

## 8. Further reading

* `java.net.http` package docs; JEP 321 (HTTP Client), JEP 517 (HTTP/3).
* `InetAddress` Javadoc, "InetAddress Caching"; `java.security` master file.
* RFC 9293 (TCP), RFC 8446 (TLS 1.3); Ilya Grigorik, *High Performance Browser Networking* (free online).
