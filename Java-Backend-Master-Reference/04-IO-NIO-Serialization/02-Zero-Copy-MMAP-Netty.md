# 4.2 · Zero-Copy, Memory-Mapped Files & Netty Architecture

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** `FileChannel.transferTo/transferFrom/map` Javadoc; Linux `sendfile(2)`, `splice(2)`, `mmap(2)`, `madvise(2)`; Kafka design docs ("Efficiency", zero-copy); Netty 4.2 documentation and source (`AdaptiveByteBufAllocator`, `PooledByteBufAllocator`, `ResourceLeakDetector`, `MultiThreadIoEventLoopGroup`); JEP 454 (FFM mapping); Norman Maurer, *Netty in Action*.
> **Measured on Windows 11 + JDK 25 + Netty 4.2.19.Final.** Where the Linux behaviour differs (sendfile), this file says so explicitly instead of extrapolating from Windows numbers.

---

## 1. What "zero-copy" means 🔥

### 1.1 The traditional path: read file, write socket

```
   disk ──DMA──► page cache (kernel) ──CPU copy──► user buffer (JVM) ──CPU copy──► socket buffer (kernel) ──DMA──► NIC
                           1                              2                               3                        4
   syscalls: read() + write() per chunk → 4 context switches per chunk, 2 CPU copies, user buffer pollutes CPU caches
   (+1 more copy in Java if the user buffer is a HEAP ByteBuffer: heap → temporary direct buffer)
```

### 1.2 With `FileChannel.transferTo` on Linux → `sendfile(2)`

```
   disk ──DMA──► page cache ──(descriptors only, with scatter-gather DMA)──► NIC
   one syscall per transfer; no user-space copy; no CPU memcpy of payload on modern NICs
```

* `transferTo(position, count, target)` may transfer **fewer bytes than requested** (Linux caps sendfile at ~2 GB per call). **Always loop** until the count is reached.
* Zero-copy only helps when you **don't touch the bytes**. Any transformation (compression, encryption, templating) needs them in user space.
* **TLS breaks zero-copy** unless the kernel does the encryption (kTLS), which the JDK's TLS doesn't use. That's why Kafka's zero-copy fetch path applies to **plaintext** listeners only. With TLS, brokers copy through the JVM.
* `transferFrom` (socket/file → file) and `FileChannel`↔`FileChannel` transfers can also use kernel paths (`copy_file_range`/`splice` on Linux, depending on the JDK version).

### 1.3 Measured on this Windows laptop (loopback socket, 128 MB file)

```
   stream copy: wall 111 ms, process CPU 218 ms
   transferTo : wall 93 ms, process CPU 187 ms
   stream copy: wall 101 ms, process CPU 250 ms
   transferTo : wall 95 ms, process CPU 171 ms
   stream copy: wall 91 ms, process CPU 156 ms
   transferTo : wall 95 ms, process CPU 171 ms

second run (same machine, minutes later):
   stream copy: wall 141 ms, process CPU 359 ms
   transferTo : wall 100 ms, process CPU 203 ms
   stream copy: wall 96 ms, process CPU 218 ms
   transferTo : wall 96 ms, process CPU 203 ms
   stream copy: wall 94 ms, process CPU 171 ms
   transferTo : wall 96 ms, process CPU 125 ms
```

No consistent win here: `transferTo` used less CPU in 4 of 6 pairings, the variance is large, and wall time is a wash. On Windows loopback both paths are memory-bound, and the CPU total includes the receiving side in the same process. This is a useful lesson in itself: **zero-copy is an OS-specific optimization**. Its benefits (lower CPU per byte, less memory bandwidth, no cache pollution) show up on **Linux with real NICs, large files and many concurrent transfers**: static file servers, Kafka brokers serving consumer fetches, object storage gateways. Measure CPU per GB on your production OS. (The probe program is in §6.)

---

## 2. Memory-mapped files 🔥

```java
try (FileChannel ch = FileChannel.open(path, READ)) {
    MappedByteBuffer mbb = ch.map(FileChannel.MapMode.READ_ONLY, 0, ch.size());   // ≤ 2 GB per buffer (int index)
    byte b = mbb.get(12_345);           // page fault on first touch → kernel maps the page cache page into our address space
}
```

| Aspect | Detail |
|---|---|
| Mechanism | `mmap(2)`: file pages appear as process memory, and reads are page-cache hits after the first fault. There is no `read()` syscall per access |
| Size limit | `MappedByteBuffer` ≤ 2 GB (int index). **FFM** `FileChannel.map(mode, offset, size, Arena)` returns a `MemorySegment` with `long` offsets, so there's no limit (JDK 22+) |
| Unmapping | `MappedByteBuffer` is unmapped **only when GC'd** (no public `unmap`). FFM segments unmap **deterministically** on `arena.close()` |
| Durability | `force()` (msync) writes dirty pages. Without it, writes reach disk whenever the OS decides |
| Latency hazards | **Page faults are invisible blocking I/O.** A thread faulting on an evicted page stalls (and can delay safepoints, [1.6 Story 6](../01-JVM-Internals/06-Production-Failure-Modes-Diagnostics.md#-story-6--gc-logs-say-5-ms-users-say-900-ms)). There's no `madvise` API in the JDK (FFM can call `madvise` natively) |
| Accounting | Mapped pages count toward the container's memory as page cache (they're reclaimable, but RSS dashboards show them). `BufferPoolMXBean("mapped")` tracks the count and capacity |
| Address space | Every mapping is a VMA. Too many mappings fail with `OutOfMemoryError: Map failed` (`vm.max_map_count`) |
| Users | Lucene/Elasticsearch/OpenSearch (`MMapDirectory`; Lucene 9.x+ uses FFM on recent JDKs), Chronicle Queue/Map, embedded DBs (MapDB, LMDB bindings), Kafka index files |

Measured behaviour on this machine (JDK 25, Windows 11):

```
mapped 128 MB, touched every page, checksum=7680 isLoaded=false
delete while mapped: succeeded
FFM mapped segment size=134217728 first byte=115
deleted after unmap/GC: true
```

`isLoaded()` is only a hint: it reported `false` right after touching every page. Deleting a mapped file **succeeded** on this Windows 11 + JDK 25 setup. Older JDK/Windows combinations failed with "file in use", and on Linux the name disappears but the disk space stays allocated until the mapping is released. Treat "delete or truncate while mapped" as **platform-dependent** and avoid it. **Truncating a file that another process has mapped** leads to `SIGBUS`/`InternalError` on access.

---

## 3. Netty architecture 🔥

Netty is the I/O engine under gRPC-Java, Reactor Netty (Spring WebFlux), Vert.x, Micronaut's HTTP server, Elasticsearch transport, Cassandra drivers, Redis clients (Lettuce, Redisson) and many proxies and gateways.

```
                        ┌──────────── EventLoopGroup (N event loops ≈ 2 × cores by default) ─────────────┐
 accept ─► boss loop ─► │ EventLoop-1: ONE thread + Selector/epoll + task queue (MPSC) + scheduled tasks  │
                        │   owns many Channels for their whole lifetime (thread confinement → no locks)   │
                        │ EventLoop-2: …                                                                   │
                        └──────────────────────────────────────────────────────────────────────────────────┘
 Channel ─ ChannelPipeline (doubly-linked list of ChannelHandlerContexts):
   inbound  ──►  [SslHandler] → [LineBasedFrameDecoder] → [HttpServerCodec] → [BusinessHandler]
   outbound ◄──  [SslHandler] ← [encoder]               ← [HttpServerCodec] ← ctx.writeAndFlush(msg)
```

| Concept | What to know |
|---|---|
| **EventLoop** | A single thread running select, process I/O, run tasks. **All handler callbacks for a channel run on its event loop**, so handlers need no synchronization, but **must never block** |
| `EventLoopGroup` (4.2) | `new MultiThreadIoEventLoopGroup(n, NioIoHandler.newFactory())`, with `EpollIoHandler`, `KQueueIoHandler` and `IoUringIoHandler` (native transports) as alternatives. `NioEventLoopGroup` is deprecated in 4.2 |
| **ChannelPipeline** | Inbound events flow head→tail; outbound operations tail→head. Codecs translate between bytes and messages |
| **Framing** | TCP is a byte stream, so decoders (`LineBasedFrameDecoder`, `LengthFieldBasedFrameDecoder`, `HttpObjectDecoder`) accumulate bytes until a full frame arrives (`ByteToMessageDecoder` cumulation) |
| **`ByteBuf`** | Separate `readerIndex`/`writerIndex` (no `flip()`!), dynamic capacity, pooled or unpooled, heap or direct, `CompositeByteBuf` for zero-copy aggregation, `slice`/`duplicate` views sharing memory |
| **Reference counting** | Pooled and direct buffers are freed **explicitly**: `refCnt`, `retain()`, `release()`. The last handler that consumes a message must release it (`SimpleChannelInboundHandler` does it automatically after `channelRead0`) |
| **Allocators** | Netty **4.2 default: `AdaptiveByteBufAllocator`** (verified below); `PooledByteBufAllocator` (jemalloc-style arenas, chunks, subpages, thread-local caches) was the 4.1 default; `UnpooledByteBufAllocator` |
| **Leak detection** | `ResourceLeakDetector` samples buffers (`-Dio.netty.leakDetection.level=disabled\|simple\|advanced\|paranoid`) and logs `LEAK: ByteBuf.release() was not called before it's garbage-collected` with access records |
| Zero-copy features | `FileRegion`/`DefaultFileRegion` (→ `transferTo`/sendfile), `CompositeByteBuf`, `slice` |
| Blocking work | Hand it off: `ctx.executor()` is the event loop. Use a separate `EventExecutorGroup` for handlers, or a VT executor, for blocking calls |

### 3.1 Runnable: Netty 4.2 echo pipeline and `ByteBuf` reference counting

<!-- run: cp=netty timeout=60 -->
```java
import io.netty.bootstrap.Bootstrap;
import io.netty.bootstrap.ServerBootstrap;
import io.netty.buffer.*;
import io.netty.channel.*;
import io.netty.channel.nio.NioIoHandler;
import io.netty.channel.socket.SocketChannel;
import io.netty.channel.socket.nio.NioServerSocketChannel;
import io.netty.channel.socket.nio.NioSocketChannel;
import io.netty.handler.codec.LineBasedFrameDecoder;
import io.netty.util.CharsetUtil;
import io.netty.util.IllegalReferenceCountException;
import java.net.InetSocketAddress;
import java.util.concurrent.*;

public class NettyEcho {
    public static void main(String[] args) throws Exception {
        // --- ByteBuf basics & reference counting ---
        System.out.println("default allocator: " + ByteBufAllocator.DEFAULT.getClass().getSimpleName());
        ByteBuf buf = ByteBufAllocator.DEFAULT.buffer(16);
        System.out.println("buffer: " + buf.getClass().getSimpleName() + " direct=" + buf.isDirect() + " refCnt=" + buf.refCnt());
        buf.writeBytes("hello".getBytes(CharsetUtil.US_ASCII));
        System.out.println("readerIndex=" + buf.readerIndex() + " writerIndex=" + buf.writerIndex() + " (no flip needed)");
        ByteBuf slice = buf.retainedSlice(0, 3);                    // shares memory, bumps the refCnt
        System.out.println("after retainedSlice refCnt=" + buf.refCnt() + " slice=" + slice.toString(CharsetUtil.US_ASCII));
        slice.release();
        buf.release();
        System.out.println("after both releases refCnt=" + buf.refCnt());
        try { buf.readByte(); } catch (IllegalReferenceCountException e) { System.out.println("use after release → IllegalReferenceCountException"); }

        // --- Echo server + client on the same event-loop group ---
        EventLoopGroup group = new MultiThreadIoEventLoopGroup(2, NioIoHandler.newFactory());
        try {
            Channel server = new ServerBootstrap().group(group).channel(NioServerSocketChannel.class)
                .childHandler(new ChannelInitializer<SocketChannel>() {
                    @Override protected void initChannel(SocketChannel ch) {
                        ch.pipeline()
                          .addLast(new LineBasedFrameDecoder(1024))                     // framing: one message per line
                          .addLast(new SimpleChannelInboundHandler<ByteBuf>() {        // auto-releases msg after channelRead0
                              @Override protected void channelRead0(ChannelHandlerContext ctx, ByteBuf msg) {
                                  String line = msg.toString(CharsetUtil.UTF_8);
                                  ctx.writeAndFlush(Unpooled.copiedBuffer("echo:" + line + "\n", CharsetUtil.UTF_8));
                              }
                          });
                    }
                })
                .bind("127.0.0.1", 0).sync().channel();
            int port = ((InetSocketAddress) server.localAddress()).getPort();

            CompletableFuture<String> reply = new CompletableFuture<>();
            Channel client = new Bootstrap().group(group).channel(NioSocketChannel.class)
                .handler(new ChannelInitializer<SocketChannel>() {
                    @Override protected void initChannel(SocketChannel ch) {
                        ch.pipeline().addLast(new LineBasedFrameDecoder(1024)).addLast(new SimpleChannelInboundHandler<ByteBuf>() {
                            @Override protected void channelRead0(ChannelHandlerContext ctx, ByteBuf msg) {
                                reply.complete(msg.toString(CharsetUtil.UTF_8) + " (handled on an event-loop thread: "
                                    + Thread.currentThread().getName().startsWith("multiThreadIoEventLoopGroup") + ")");
                            }
                        });
                    }
                })
                .connect("127.0.0.1", port).sync().channel();
            client.writeAndFlush(Unpooled.copiedBuffer("ping\n", CharsetUtil.UTF_8));
            System.out.println("client got: " + reply.get(5, TimeUnit.SECONDS));
            client.close().sync();
            server.close().sync();
        } finally {
            group.shutdownGracefully(0, 1, TimeUnit.SECONDS).sync();
        }
    }
}
```

Output (verified with netty-common/buffer/transport/resolver/handler/codec-base 4.2.19.Final):

```
default allocator: AdaptiveByteBufAllocator
buffer: AdaptiveByteBuf direct=true refCnt=1
readerIndex=0 writerIndex=5 (no flip needed)
after retainedSlice refCnt=2 slice=hel
after both releases refCnt=0
use after release → IllegalReferenceCountException
client got: echo:ping (handled on an event-loop thread: true)
```

### 3.2 The Netty rules that prevent 90% of incidents

1. **Don't block the event loop.** JDBC, `Thread.sleep`, synchronous HTTP calls, `future.get()`, heavy CPU, even DNS resolution: all stall every channel on that loop. Use **BlockHound** in tests to fail on blocking calls, and offload to a separate executor (or a virtual-thread executor, then `ctx.executor().execute(...)` to write back).
2. **Release what you consume.** If a handler passes a message on (`ctx.fireChannelRead(msg)`), ownership passes on. If it consumes it, it must `ReferenceCountUtil.release(msg)` (or extend `SimpleChannelInboundHandler`). Writes release the buffer once it's flushed.
3. **Run leak detection** at `paranoid` level in CI, and keep the default `simple` sampling in production. Read `LEAK:` logs: they show where the buffer was last accessed.
4. **Respect backpressure:** check `channel.isWritable()` and handle `channelWritabilityChanged` (high/low water marks) instead of writing unboundedly to a slow client, which would grow the outbound buffer without limit.
5. **Bound everything:** the max frame length in decoders (`LineBasedFrameDecoder(1024)`), aggregator limits (`HttpObjectAggregator(maxContentLength)`), and idle timeouts (`IdleStateHandler`).
6. Size event loops deliberately (`2 × cores` default). More loops than cores only helps if loops sometimes block, which is itself the bug to fix.

### 3.3 `PooledByteBufAllocator` internals (still common in 4.1 deployments) 🧊

```
PooledByteBufAllocator
 ├── PoolArena[] (heap and direct; ≈ 2 × cores each)   ← threads are bound to the least-used arena
 │     └── PoolChunk (default 4 MB in 4.1.x newer releases; 16 MB historically) = buddy-allocated runs of pages
 │           └── PoolSubpage for small sizes (size classes, jemalloc-like)
 └── PoolThreadCache per thread: small per-size-class caches, so most allocations need no arena locking
```

Consequences: **direct memory grows in chunk-sized steps and stays reserved** (pools rarely shrink). Netty can bypass `MaxDirectMemorySize` accounting by allocating without Cleaners (`io.netty.noPreferDirect`, `io.netty.maxDirectMemory`), so monitor `PooledByteBufAllocator.DEFAULT.metric()` (`usedDirectMemory`) and not only the JDK's `BufferPoolMXBean`. Thread-local caches on **many** threads (for example virtual threads that allocate) multiply memory, which is one reason Netty 4.2 moved to the adaptive allocator by default.

---

## 4. Putting it together: a high-throughput file download service

| Requirement | Technique |
|---|---|
| Serve large static files over plaintext HTTP/1.1 | Netty `DefaultFileRegion` or `FileChannel.transferTo` (sendfile on Linux), so no user-space copy |
| Serve over TLS | Chunked reads with **pooled direct buffers** (`ChunkedNioFile`) through `SslHandler`; zero-copy isn't possible without kTLS |
| Ranged requests | `FileChannel` positional reads (thread-safe, no shared position) |
| Thousands of slow clients | Event-loop architecture or VTs; `isWritable` backpressure |
| Random-access index lookups | FFM `MemorySegment` mapping (no 2 GB limit, deterministic unmap) |
| Observability | `BufferPoolMXBean` (direct/mapped), Netty allocator metrics, JFR `jdk.FileRead`/`SocketWrite` |

---

## 5. Production failure modes & diagnostics

| Failure | Signature | Fix |
|---|---|---|
| Netty buffer leak | `LEAK: ByteBuf.release() was not called…` logs; direct memory grows; eventually `OutOfDirectMemoryError` | Release in consumers; `SimpleChannelInboundHandler`; paranoid leak detection in tests |
| Blocking the event loop | Latency spikes for all connections on a loop; event-loop threads in JDBC/sleep frames in dumps | Offload; BlockHound |
| Unbounded outbound buffer | Memory grows when clients read slowly | `isWritable()` / water marks; disconnect slow consumers |
| Direct memory exhaustion with pooling | Pod RSS grows in chunk-sized steps and stays there | Size limits; monitor allocator metrics; tune arenas/caches; the 4.2 adaptive allocator |
| Short `transferTo` treated as complete | Truncated downloads above ~2 GB | Loop until the full count is transferred |
| mmap page-fault stalls | Latency spikes and safepoint delays under memory pressure | Pre-touch/warm, enough RAM for the hot set, avoid swap; async I/O for cold data |
| `OOM: Map failed` | Too many or too large mappings | Fewer larger mappings; raise `vm.max_map_count`; unmap via FFM arenas |
| `SIGBUS`/`InternalError` reading a mapped file | The file was truncated underneath the mapping | Never truncate mapped files; coordinate writers |

**Commands:** `-Dio.netty.leakDetection.level=paranoid` (tests), JFR `jdk.DirectBufferStatistics` (periodic direct-buffer pool snapshots; Netty's cleaner-less allocations are *not* included, so use the allocator's own metrics), `BufferPoolMXBean`, `jcmd <pid> VM.native_memory summary` (direct buffers under *Other*), `pmap -x <pid>` (mapped files), `cat /proc/<pid>/smaps | grep -A3 <file>` (resident mapped pages).

---

## 6. Appendix: the zero-copy probe used in §1.3

<!-- run: timeout=300 -->
```java
import java.io.*;
import java.net.*;
import java.nio.ByteBuffer;
import java.nio.channels.*;
import java.nio.file.*;
import java.util.concurrent.*;

public class ZeroCopyProbe {
    public static void main(String[] args) throws Exception {
        Path src = Files.createTempFile("zc-src", ".bin");
        byte[] block = new byte[1 << 20];
        new java.util.Random(1).nextBytes(block);
        try (OutputStream o = Files.newOutputStream(src)) { for (int i = 0; i < 128; i++) o.write(block); }   // 128 MB
        try {
            for (int round = 0; round < 3; round++) { toSocket(src, false); toSocket(src, true); }
        } finally { Files.deleteIfExists(src); }
    }

    static void toSocket(Path src, boolean zeroCopy) throws Exception {
        try (ServerSocketChannel server = ServerSocketChannel.open().bind(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0));
             var drainer = Executors.newVirtualThreadPerTaskExecutor()) {
            int port = ((InetSocketAddress) server.getLocalAddress()).getPort();
            Future<Long> drain = drainer.submit(() -> {
                try (SocketChannel c = server.accept()) {
                    ByteBuffer b = ByteBuffer.allocateDirect(1 << 16); long n = 0; int r;
                    while ((r = c.read(b)) != -1) { n += r; b.clear(); }
                    return n;
                }
            });
            var os = (com.sun.management.OperatingSystemMXBean) java.lang.management.ManagementFactory.getOperatingSystemMXBean();
            long cpu0 = os.getProcessCpuTime(), t0 = System.nanoTime();
            try (SocketChannel out = SocketChannel.open(new InetSocketAddress(InetAddress.getLoopbackAddress(), port));
                 FileChannel in = FileChannel.open(src, StandardOpenOption.READ)) {
                if (zeroCopy) {
                    long pos = 0, size = in.size();
                    while (pos < size) pos += in.transferTo(pos, size - pos, out);          // ALWAYS loop: partial transfers
                } else {
                    try (InputStream is = Files.newInputStream(src); OutputStream o = Channels.newOutputStream(out)) { is.transferTo(o); }
                }
            }
            if (drain.get() != Files.size(src)) throw new IllegalStateException("short transfer");
            System.out.printf("   %s: wall %d ms, process CPU %d ms%n", zeroCopy ? "transferTo " : "stream copy",
                (System.nanoTime() - t0) / 1_000_000, (os.getProcessCpuTime() - cpu0) / 1_000_000);
        }
    }
}
```

---

## 7. Interview Q&A

<details><summary><b>Q1. 🔥 Explain zero-copy and when it doesn't apply.</b></summary>

`FileChannel.transferTo` lets the kernel move file data to a socket (Linux `sendfile`) without copying it through user-space buffers, saving CPU copies, syscalls and context switches, and avoiding cache pollution. It doesn't apply when the application must transform the bytes (compression, encryption via JDK TLS, templating), and its benefit depends on the OS: on this Windows loopback test there was no measurable gain. Kafka serves consumers via sendfile on plaintext listeners, but not with TLS.
</details>

<details><summary><b>Q2. ⚡ Why loop on `transferTo`?</b></summary>

It may transfer fewer bytes than requested: Linux sendfile caps a single call at about 2 GB, and non-blocking targets can accept partial writes. A single call can silently truncate large transfers.
</details>

<details><summary><b>Q3. 🔥 What are the risks of memory-mapped files in a latency-sensitive service?</b></summary>

Page faults are synchronous, invisible I/O: a cold page stalls the thread and can delay safepoints. Memory pressure evicts pages, causing unpredictable latency. `MappedByteBuffer` can't be unmapped deterministically (only by GC) and is limited to 2 GB, while FFM segments fix both. Truncation by another process causes SIGBUS-style errors. Mapped pages inflate RSS metrics. There are limits on the number of mappings (`vm.max_map_count`).
</details>

<details><summary><b>Q4. 🔥 Why must Netty handlers never block?</b></summary>

Each event loop is a single thread serving many channels, and every handler callback for those channels runs on it. A blocking call stalls I/O, timers and tasks for every connection on that loop, causing latency spikes or apparent hangs. Offload blocking work to another executor and write back via the channel (which dispatches to the event loop).
</details>

<details><summary><b>Q5. ⚡ Who releases a `ByteBuf` in a Netty pipeline?</b></summary>

The component that consumes it last. If a handler forwards the message (`ctx.fireChannelRead(msg)` or writes it), ownership moves along. If it consumes the message without forwarding, it must call `release()` (or extend `SimpleChannelInboundHandler`, which releases after `channelRead0`). Outbound buffers are released by the transport after they're written. Missing releases leak pooled or direct memory, which `ResourceLeakDetector` reports.
</details>

<details><summary><b>Q6. 🧊 What changed in Netty 4.2 that matters operationally?</b></summary>

The I/O-handler-based event loop model (`MultiThreadIoEventLoopGroup` with `NioIoHandler`/`EpollIoHandler`/`IoUringIoHandler`; `NioEventLoopGroup` deprecated), io_uring as a first-class transport, and **`AdaptiveByteBufAllocator` as the default allocator** (verified above), which adapts to usage and behaves better with many threads than the old thread-local-cache-heavy pooled allocator.
</details>

---

## 8. Further reading

* Linux `sendfile(2)`, `mmap(2)`; Kafka docs, "Efficiency" (zero-copy).
* Netty user guide and 4.2 migration notes: <https://netty.io/wiki/>; BlockHound: <https://github.com/reactor/BlockHound>
* JEP 454 (FFM API: mapping files into `MemorySegment`s).
