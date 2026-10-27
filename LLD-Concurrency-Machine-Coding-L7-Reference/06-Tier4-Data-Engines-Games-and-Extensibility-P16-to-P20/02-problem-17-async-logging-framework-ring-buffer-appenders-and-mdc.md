# P17 · Async Logging Framework: an MPSC Ring of Pooled Events, Backpressure Policies, Rolling Files and an MDC That Survives Thread Pools

> **Folder 06 · Problem 17 of 20.** A logger sits on every request path, so it must be nearly free when disabled, never lose order, never take the application down, and attribute every line to the right request. This problem covers:
> - a level check **before** any work (the C++ listing found a signature that allocated before it);
> - **pooled events** in a Vyukov MPSC ring;
> - an explicit **BLOCK vs DROP** policy with measured producer latency;
> - a single consumer that **isolates appender failures**;
> - an MDC captured **at submit time**, with the `InheritableThreadLocal` bug reproduced.
>
> **Listing pair P17:** `AsyncLogger.java` / `async_logger.cpp`. Sections 3–4 are deterministic (logical clock) and **byte-identical in Java, GCC and Clang**; sections 1–2 show one measured run.

---

## 1. Problem and scope

**Functional:**
- `log(level, "user {} bought {}", args…)`.
- Levels TRACE…ERROR with a runtime threshold.
- Appenders: a counting/ordering checker, a size-based **rolling file** (keep N), and an in-memory sink.
- An MDC (`requestId`) on every line.
- Drop notices when events are shed.

**Non-functional:**
- A disabled call costs ~1 ns.
- An enabled call never blocks on I/O.
- Per-producer order is preserved.
- A failing appender never stops logging.
- Shutdown drains what was published.

**Out of scope:** structured JSON encoding (an appender concern), sampling and remote shipping (an appender with its own queue).

## 2. Domain model and invariants

| Element | Java | C++ |
|---|---|---|
| Event | `final class Event`, **preallocated**, one per ring slot, filled in place (`args[4]`, MDC reference) | `struct Event` in an `alignas(64)` slot; `std::string` buffers keep their capacity |
| Ring | `Ring`: `AtomicLongArray` per-slot sequence; `claimBlocking` (`getAndIncrement`) / `tryClaim` (CAS) | the same with `std::atomic<u64>` |
| MDC | `ThreadLocal<Map>` holding an **immutable** `Map.copyOf`; `Mdc.wrap(task)` captures at submit | `thread_local std::shared_ptr<const std::map>`; `Mdc::wrap` |
| Policy | `enum Overflow { BLOCK, DROP }` | the same |
| Appender | `interface Appender { append(Event, CharSequence); close() }` | virtual `Appender` |

**Invariants:**
- **I1:** a disabled call does no formatting, copying, claiming or allocation.
- **I2:** events from one producer are delivered in that producer's order (it claims increasing slots).
- **I3:** under DROP, delivered + dropped = logged, and the loss itself is logged, rate-limited.
- **I4:** every line carries the MDC of the code that **submitted** the work, never a thread's stale context.
- **I5:** a failing appender costs that appender one line, not the consumer thread.

## 3. Concurrency and contention analysis

### 3.1 The cheapest log line is the one you don't build

**20,000,000 DEBUG calls at threshold INFO:**

| Call style | Java | GCC | Clang |
|---|---|---|---|
| Eager: `"user " + i + …` / `std::format(…)` | 21.5 ns | 193 ns | 187 ns |
| Template + args | 3.0 ns | **0.64 ns** (was **50 ns**, see below) | 0.78 ns |
| `if (enabled(DEBUG))` guard | 0.34 ns | 2.4 ns | 0.68 ns |

**The C++ trap.** The first signature was `log(Level, const std::string& tmpl, …)`. A string literal of 17 characters had to become a `std::string` **before** the level check. libstdc++'s small-string buffer holds 15 characters, so every disabled call heap-allocated: 50 ns on GCC. libc++'s buffer holds 22, which is why Clang hid it (1.3 ns). `std::string_view` fixes it.

**The Java equivalent:** varargs allocate an `Object[]` and box primitives at the call site. The JIT often removes this when the level is off; garbage-free loggers (Log4j 2) add unrolled overloads instead. For expensive arguments, pass a supplier or guard the call.

### 3.2 The ring: claim, fill in place, publish

- **Producers** claim a slot with one atomic op (`getAndIncrement`), fill the **preallocated** `Event`, then publish by storing `seq = pos + 1` (release).
- **The consumer** sees `seq == head + 1`, formats into a **reused** `StringBuilder` / `std::string`, fans out, clears references (so pooled events don't pin request contexts), and frees the slot with `seq = head + capacity`.
- **Order:** each producer claims increasing positions, so its events stay in order. Zero violations in every run.

**Backpressure is a product decision. Measured with 4 producers × 250,000 events and an appender at ~1 µs/event:**

| Policy | Delivered | `log()` p50 / p99 | Wall time |
|---|---|---|---|
| **BLOCK** | 1,000,000 | 3.9 µs / 9.8 µs (Java); 6.4 / 15.5 µs (GCC) | 1.0–1.7 s: producers are throttled to the appender's rate |
| **DROP** (CAS try-claim, never waits) | 2–3% (Java 26,740; GCC 22,929) | ≤ 0.1 µs / 0.5–1.3 µs | 35–54 ms |

A p50 of "100 ns" is the Windows timer resolution, not the call cost.

**Which policy when:**
- **DROP** with a rate-limited "dropped N events" notice (4–5 notices here) protects latency during an incident storm.
- **BLOCK** protects completeness (audit logs).
- **The common production compromise** is to drop below WARN and block at WARN and above.

### 3.3 One consumer, isolated appenders

The consumer is the only thread formatting or touching appenders, so **appenders need no locks**. That gives two failure modes:
- **A slow appender delays all of them.** Give a slow sink its own ring (an async appender per destination).
- **An appender exception kills the consumer.** Under BLOCK, every producer then spins forever on a full ring: the application hangs because of its logger.

`drain()` catches per appender and counts failures. In section 3 a faulty appender throws once ("disk full"); the rolling file still receives all 20,000 lines, and `appender errors isolated: 1`.

**Rolling files:** size-based, rename chain `app.log → app.1.log → … → app.3.log`, oldest deleted. With 20,000 lines, 64 KiB files and keep 3: **11 rolls, 6,342 lines kept**, and the oldest kept line is #13,658. That output is identical across all three builds.

### 3.4 MDC across thread pools

**Capturing is cheap.** The MDC is an **immutable map**, so an event holds one reference (Java) or bumps one refcount (C++) instead of copying the map on the hot path.

**The bug: `InheritableThreadLocal` copies context when a *thread* is created.**
1. Request A happened to create the pool's thread.
2. Request B's task later ran on it and saw **`requestId = req-A`**.

C++ has no inheritable thread-locals; the listing's `SingleThreadPool` copies the creator's context at thread creation to reproduce the same bug.

**The fix: capture at *submit*.**
- `Mdc.wrap(task)` captures the submitter's map, installs it around the task, and **restores** the worker's previous context afterwards. That's why the next task sees `-`.
- Java 25's `ScopedValue` (JEP 506) is the structured version of this. Its bindings are inherited by `StructuredTaskScope` subtasks. The listing targets `--release 21`, so it shows the wrapper.

## 4. Java 21 implementation

```java
// AsyncLogger.java - P17: async logging: MPSC ring of pooled events, level filtering, BLOCK/DROP backpressure, rolling appender, MDC
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicLongArray;
import java.util.concurrent.atomic.LongAdder;
import java.util.function.LongSupplier;

public final class AsyncLogger implements AutoCloseable {

    enum Level { TRACE, DEBUG, INFO, WARN, ERROR }

    enum Overflow { BLOCK, DROP }

    // ---- MDC: the context is an immutable map, so snapshotting it for an event is one reference copy

    static final class Mdc {
        static final ThreadLocal<Map<String, String>> CTX = ThreadLocal.withInitial(Map::of);

        static void put(String k, String v) {
            Map<String, String> m = new HashMap<>(CTX.get());
            m.put(k, v);
            CTX.set(Map.copyOf(m));
        }

        static String get(String k) {
            return CTX.get().getOrDefault(k, "-");
        }

        static void clear() {
            CTX.set(Map.of());
        }

        /** Capture at SUBMIT time, restore around the task, then put back what the worker had: no leaks between tasks. */
        static Runnable wrap(Runnable task) {
            Map<String, String> captured = CTX.get();
            return () -> {
                Map<String, String> previous = CTX.get();
                CTX.set(captured);
                try {
                    task.run();
                } finally {
                    CTX.set(previous);
                }
            };
        }
    }

    /** The common mistake: context inherited when a THREAD is created, not when a TASK is submitted. */
    static final InheritableThreadLocal<String> INHERITED = new InheritableThreadLocal<>();

    // ---- events: preallocated and reused; producers fill a slot in place

    static final class Event {
        Level level;
        long ts, producer, seq;
        String thread, template;
        final Object[] args = new Object[4];
        int argc;
        Map<String, String> mdc;
    }

    interface Appender {
        void append(Event e, CharSequence line);

        default void close() {}
    }

    /** Bounded MPSC ring with per-slot sequence numbers (Vyukov). Slots hold reusable Event objects. */
    static final class Ring {
        final Event[] slots;
        final AtomicLongArray seq;
        final AtomicLong tail = new AtomicLong();
        final int mask;
        long head;                                                     // consumer-owned

        Ring(int capacityPow2) {
            slots = new Event[capacityPow2];
            seq = new AtomicLongArray(capacityPow2);
            mask = capacityPow2 - 1;
            for (int i = 0; i < capacityPow2; i++) {
                slots[i] = new Event();
                seq.set(i, i);
            }
        }

        long claimBlocking() {                                         // one atomic op; waits only if the ring is full
            long pos = tail.getAndIncrement();
            while (seq.get((int) (pos & mask)) != pos) Thread.onSpinWait();
            return pos;
        }

        long tryClaim() {                                              // never waits: -1 when the slot is still in use
            for (;;) {
                long pos = tail.get();
                long s = seq.get((int) (pos & mask));
                if (s < pos) return -1;
                if (s == pos && tail.compareAndSet(pos, pos + 1)) return pos;
            }
        }

        void publish(long pos) {
            seq.set((int) (pos & mask), pos + 1);
        }

        Event peek() {
            int i = (int) (head & mask);
            return seq.get(i) == head + 1 ? slots[i] : null;
        }

        void release() {
            seq.set((int) (head & mask), head + mask + 1);
            head++;
        }
    }

    volatile Level threshold;
    final Ring ring;
    final Overflow overflow;
    final List<Appender> appenders;
    final LongSupplier clock;
    final LongAdder dropped = new LongAdder();
    final Thread consumer;
    volatile boolean running = true;
    long reportedDrops, delivered, appenderErrors;                     // consumer-owned

    AsyncLogger(Level threshold, int capacity, Overflow overflow, LongSupplier clock, List<Appender> appenders) {
        this.threshold = threshold;
        this.ring = new Ring(capacity);
        this.overflow = overflow;
        this.clock = clock;
        this.appenders = appenders;
        consumer = Thread.ofPlatform().name("log-consumer").start(this::drain);
    }

    boolean enabled(Level l) {
        return l.ordinal() >= threshold.ordinal();
    }

    void log(Level l, String template, Object... args) {
        if (!enabled(l)) return;                                       // before any formatting, copying or claiming
        logAs(l, -1, -1, template, args);
    }

    void logAs(Level l, long producer, long seq, String template, Object... args) {
        long pos = overflow == Overflow.BLOCK ? ring.claimBlocking() : ring.tryClaim();
        if (pos < 0) {
            dropped.increment();                                       // never block the application thread
            return;
        }
        Event e = ring.slots[(int) (pos & ring.mask)];
        e.level = l;
        e.ts = clock.getAsLong();
        e.thread = Thread.currentThread().getName();
        e.template = template;
        e.argc = Math.min(args.length, 4);
        System.arraycopy(args, 0, e.args, 0, e.argc);
        e.mdc = Mdc.CTX.get();                                         // a reference, not a copy
        e.producer = producer;
        e.seq = seq;
        ring.publish(pos);
    }

    void drain() {
        StringBuilder sb = new StringBuilder(256);                     // reused: formatting allocates nothing per event
        for (;;) {
            Event e = ring.peek();
            if (e == null) {
                if (!running && ring.peek() == null) break;
                Thread.onSpinWait();
                continue;
            }
            format(sb, e);
            for (Appender a : appenders) {
                try {
                    a.append(e, sb);
                } catch (RuntimeException ex) {                        // a dead consumer would block every producer forever
                    appenderErrors++;
                }
            }
            delivered++;
            e.mdc = null;                                              // don't pin request contexts in the pool
            for (int i = 0; i < e.argc; i++) e.args[i] = null;
            ring.release();
            long d = dropped.sum();
            if (d > reportedDrops && (ring.peek() == null || delivered % 4_096 == 0)) {   // the loss is itself logged, rate-limited
                Event w = new Event();
                w.level = Level.WARN;
                w.ts = clock.getAsLong();
                w.thread = "log-consumer";
                w.template = "dropped {} events (ring full)";
                w.args[0] = d - reportedDrops;
                w.argc = 1;
                w.mdc = Map.of();
                w.producer = -1;
                reportedDrops = d;
                format(sb, w);
                for (Appender a : appenders) a.append(w, sb);
            }
        }
        appenders.forEach(Appender::close);
    }

    static void format(StringBuilder sb, Event e) {
        sb.setLength(0);
        sb.append(e.ts).append(' ').append(e.level).append(" [").append(e.thread).append("] ")
                .append(e.mdc.getOrDefault("requestId", "-")).append(' ');
        int arg = 0;
        String t = e.template;
        for (int i = 0; i < t.length(); i++) {
            if (t.charAt(i) == '{' && i + 1 < t.length() && t.charAt(i + 1) == '}' && arg < e.argc) {
                sb.append(e.args[arg++]);
                i++;
            } else {
                sb.append(t.charAt(i));
            }
        }
    }

    void stop() {                                                      // drains everything already published, then stops
        running = false;
        try {
            consumer.join();
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }

    @Override
    public void close() {
        stop();
    }

    // ---- appenders

    /** Counts lines and checks that each producer's events arrive in the order that producer logged them. */
    static final class Checker implements Appender {
        final Map<Long, Long> lastSeq = new HashMap<>();
        long lines, outOfOrder, dropNotices;
        final int slowSpins;

        Checker(int slowSpins) {
            this.slowSpins = slowSpins;
        }

        @Override
        public void append(Event e, CharSequence line) {
            lines++;
            if (e.producer < 0) {
                dropNotices++;
                return;
            }
            Long prev = lastSeq.put(e.producer, e.seq);
            if (prev != null && e.seq <= prev) outOfOrder++;
            for (int i = 0; i < slowSpins; i++) Thread.onSpinWait();   // a slow disk / network appender
        }
    }

    /** Size-based rolling: app.log -> app.1.log -> ... -> app.{keep}.log, the oldest deleted. */
    static final class RollingFile implements Appender {
        final Path dir;
        final String base;
        final long maxBytes;
        final int keep;
        BufferedWriter out;
        long size;
        int rolls;

        RollingFile(Path dir, String base, long maxBytes, int keep) throws IOException {
            this.dir = dir;
            this.base = base;
            this.maxBytes = maxBytes;
            this.keep = keep;
            out = Files.newBufferedWriter(dir.resolve(base + ".log"), StandardCharsets.UTF_8);
        }

        Path file(int i) {
            return dir.resolve(i == 0 ? base + ".log" : base + "." + i + ".log");
        }

        @Override
        public void append(Event e, CharSequence line) {
            try {
                int len = line.length() + 1;                           // ASCII lines: bytes == chars
                if (size + len > maxBytes) roll();
                out.append(line).append('\n');
                size += len;
            } catch (IOException ex) {
                throw new UncheckedIOException(ex);
            }
        }

        void roll() throws IOException {
            out.close();
            Files.deleteIfExists(file(keep));
            for (int i = keep - 1; i >= 0; i--)
                if (Files.exists(file(i))) Files.move(file(i), file(i + 1), StandardCopyOption.REPLACE_EXISTING);
            out = Files.newBufferedWriter(file(0), StandardCharsets.UTF_8);
            size = 0;
            rolls++;
        }

        @Override
        public void close() {
            try {
                out.close();
            } catch (IOException ex) {
                throw new UncheckedIOException(ex);
            }
        }
    }

    /** An appender that fails on one line: its failure must not stop the others, or the consumer. */
    static final class Faulty implements Appender {
        @Override
        public void append(Event e, CharSequence line) {
            if (line.toString().endsWith("line 5000 of 20000")) throw new IllegalStateException("disk full");
        }
    }

    /** Collects lines in memory (for the MDC demo). */
    static final class Memory implements Appender {
        final List<String> lines = new ArrayList<>();

        @Override
        public synchronized void append(Event e, CharSequence line) {
            lines.add(line.toString());
        }
    }

    // ---- harness

    record Burst(long delivered, long dropped, long dropNotices, long outOfOrder, long p50, long p99, long max, long ms) {}

    static Burst burst(Overflow policy, int slowSpins) throws Exception {
        Checker checker = new Checker(slowSpins);
        long[][] samples = new long[4][250_000 / 8];                   // every 8th log() call's latency, per producer
        long t0;
        try (AsyncLogger log = new AsyncLogger(Level.INFO, 1 << 13, policy, System::nanoTime, List.of(checker))) {
            CountDownLatch go = new CountDownLatch(1), done = new CountDownLatch(4);
            for (int p = 0; p < 4; p++) {
                final long producer = p;
                Thread.ofPlatform().name("producer-" + p).start(() -> {
                    try {
                        go.await();
                        for (long i = 0; i < 250_000; i++) {
                            long a = (i & 7) == 0 ? System.nanoTime() : 0;
                            log.logAs(Level.INFO, producer, i, "order {} item {}", producer, i);
                            if ((i & 7) == 0) samples[(int) producer][(int) (i >> 3)] = System.nanoTime() - a;
                        }
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                    } finally {
                        done.countDown();
                    }
                });
            }
            t0 = System.nanoTime();
            go.countDown();
            done.await();
        }
        long ms = (System.nanoTime() - t0) / 1_000_000;
        long[] all = java.util.Arrays.stream(samples).flatMapToLong(java.util.Arrays::stream).sorted().toArray();
        return new Burst(checker.lines - checker.dropNotices, 1_000_000 - (checker.lines - checker.dropNotices), checker.dropNotices, checker.outOfOrder,
                all[all.length / 2], all[all.length * 99 / 100], all[all.length - 1], ms);
    }

    public static void main(String[] args) throws Exception {
        System.out.println("== 1. A disabled DEBUG call must cost ~nothing: 20,000,000 calls at threshold INFO ==");
        try (AsyncLogger log = new AsyncLogger(Level.INFO, 1 << 10, Overflow.BLOCK, () -> 0, List.of())) {
            long sink = 0;
            for (int pass = 0; pass < 2; pass++) {                     // pass 0 warms the JIT
                long t0 = System.nanoTime();
                for (int i = 0; i < 20_000_000; i++) log.log(Level.DEBUG, "user " + i + " bought " + (i * 7));   // eager concatenation
                long t1 = System.nanoTime();
                for (int i = 0; i < 20_000_000; i++) log.log(Level.DEBUG, "user {} bought {}", i, i * 7);        // template + varargs
                long t2 = System.nanoTime();
                for (int i = 0; i < 20_000_000; i++)
                    if (log.enabled(Level.DEBUG)) log.log(Level.DEBUG, "user {} bought {}", i, i * 7);           // guarded
                    else sink += i;
                long t3 = System.nanoTime();
                if (pass == 1)
                    System.out.printf("  eager concat %.2f ns/call | template + args %.2f ns/call | guarded %.2f ns/call (sink %d)%n", (t1 - t0) / 2e7,
                            (t2 - t1) / 2e7, (t3 - t2) / 2e7, sink % 10);
            }
        }

        System.out.println("== 2. 4 producers x 250,000 events, ring of 8,192 pooled events, a slow appender (~1 us/event) ==");
        Burst block = burst(Overflow.BLOCK, 20), drop = burst(Overflow.DROP, 20);
        for (Burst b : List.of(block, drop))
            System.out.printf("  %-6s delivered %d, dropped %d (%d drop notices) | order violations %d | log() p50 %d ns, p99 %d ns, max %.1f us | %d ms%n",
                    b == block ? "BLOCK:" : "DROP:", b.delivered(), b.dropped(), b.dropNotices(), b.outOfOrder(), b.p50(), b.p99(), b.max() / 1e3, b.ms());

        System.out.println("== 3. Rolling file appender: 20,000 lines, roll at 64 KiB, keep 3 (logical clock) ==");
        Path dir = Files.createTempDirectory("p17-logs");
        RollingFile rolling = new RollingFile(dir, "app", 64 * 1024, 3);
        long[] tick = {0};
        long errors;
        try (AsyncLogger log = new AsyncLogger(Level.INFO, 1 << 10, Overflow.BLOCK, () -> ++tick[0], List.of(new Faulty(), rolling))) {
            Thread.currentThread().setName("main");
            for (int i = 0; i < 20_000; i++) log.log(Level.INFO, "line {} of 20000", i);
            log.stop();
            errors = log.appenderErrors;                               // consumer-owned, read after the join
        }
        long kept = 0;
        StringBuilder files = new StringBuilder();
        for (int i = 0; i <= 3; i++) {
            Path f = rolling.file(i);
            if (!Files.exists(f)) continue;
            List<String> lines = Files.readAllLines(f, StandardCharsets.UTF_8);
            kept += lines.size();
            files.append(String.format("%s %d lines %d bytes; ", f.getFileName(), lines.size(), Files.size(f)));
        }
        String oldestFirst = Files.readAllLines(rolling.file(3), StandardCharsets.UTF_8).get(0);
        System.out.println("  " + files.toString().trim());
        System.out.printf("  rolls %d | lines kept %d of 20000 | oldest kept line: %s | appender errors isolated: %d%n", rolling.rolls, kept, oldestFirst,
                errors);
        for (int i = 0; i <= 3; i++) Files.deleteIfExists(rolling.file(i));
        Files.deleteIfExists(dir);

        System.out.println("== 4. MDC across a thread pool ==");
        Memory mem = new Memory();
        String inheritedSeen, wrappedSeen, leakAfter;
        try (AsyncLogger log = new AsyncLogger(Level.INFO, 1 << 10, Overflow.BLOCK, () -> 0, List.of(mem))) {
            INHERITED.set("req-A");                                    // request A happens to create the pool's thread
            ExecutorService pool = Executors.newSingleThreadExecutor(r -> new Thread(r, "worker"));
            pool.submit(() -> {}).get();
            INHERITED.set("req-B");                                    // request B submits work to the same pool
            String[] seen = new String[1];
            pool.submit(() -> seen[0] = INHERITED.get()).get();
            inheritedSeen = seen[0];
            Mdc.put("requestId", "req-B");
            pool.submit(Mdc.wrap(() -> log.log(Level.INFO, "charging card"))).get();
            Mdc.clear();
            pool.submit(() -> seen[0] = Mdc.get("requestId")).get();   // the worker must not keep B's context
            leakAfter = seen[0];
            pool.shutdown();
            if (!pool.awaitTermination(5, TimeUnit.SECONDS)) throw new IllegalStateException("pool stuck");
        }
        wrappedSeen = mem.lines.get(0);
        System.out.println("  InheritableThreadLocal: request B's task sees requestId = " + inheritedSeen + " (inherited when the thread was created)");
        System.out.println("  capture at submit:      " + wrappedSeen);
        System.out.println("  after the task, the worker's requestId is " + leakAfter + " (restored, nothing leaks into the next task)");

        boolean ok = block.dropped() == 0 && block.outOfOrder() == 0 && drop.outOfOrder() == 0 && drop.delivered() + drop.dropped() == 1_000_000
                && drop.dropped() > 0 && drop.dropNotices() > 0 && kept > 0 && kept < 20_000 && rolling.rolls > 3
                && oldestFirst.contains("line ") && errors == 1 && inheritedSeen.equals("req-A") && wrappedSeen.endsWith("req-B charging card") && leakAfter.equals("-");
        System.out.println(ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
        if (!ok) System.exit(1);
    }
}
```

**Output (sections 3–4 deterministic; 1–2 one measured run):**

```text
== 1. A disabled DEBUG call must cost ~nothing: 20,000,000 calls at threshold INFO ==
  eager concat 21.53 ns/call | template + args 2.97 ns/call | guarded 0.34 ns/call (sink 0)
== 2. 4 producers x 250,000 events, ring of 8,192 pooled events, a slow appender (~1 us/event) ==
  BLOCK: delivered 1000000, dropped 0 (0 drop notices) | order violations 0 | log() p50 3900 ns, p99 9800 ns, max 3579.2 us | 1048 ms
  DROP:  delivered 26740, dropped 973260 (5 drop notices) | order violations 0 | log() p50 100 ns, p99 1300 ns, max 619.3 us | 54 ms
== 3. Rolling file appender: 20,000 lines, roll at 64 KiB, keep 3 (logical clock) ==
  app.log 1428 lines 57120 bytes; app.1.log 1638 lines 65520 bytes; app.2.log 1638 lines 65520 bytes; app.3.log 1638 lines 65520 bytes;
  rolls 11 | lines kept 6342 of 20000 | oldest kept line: 13659 INFO [main] - line 13658 of 20000 | appender errors isolated: 1
== 4. MDC across a thread pool ==
  InheritableThreadLocal: request B's task sees requestId = req-A (inherited when the thread was created)
  capture at submit:      0 INFO [worker] req-B charging card
  after the task, the worker's requestId is - (restored, nothing leaks into the next task)
SELF-TEST OK
```

## 5. C++23 implementation

```cpp
// async_logger.cpp - P17: async logging: MPSC ring of pooled events, level filtering, BLOCK/DROP backpressure, rolling appender, MDC
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <filesystem>
#include <format>
#include <fstream>
#include <functional>
#include <future>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <print>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <variant>
#include <vector>

using i64 = std::int64_t;
using u64 = std::uint64_t;
using sz = std::size_t;
namespace fs = std::filesystem;

template <class... Fs> struct overloaded : Fs... { using Fs::operator()...; };

enum class Level { Trace, Debug, Info, Warn, Error };
constexpr std::array<const char*, 5> kLevelNames{"TRACE", "DEBUG", "INFO", "WARN", "ERROR"};
enum class Overflow { Block, Drop };

thread_local std::string thread_name = "main";

// ---- MDC: the context is an immutable map behind a shared_ptr, so snapshotting it for an event is one refcount bump

using Ctx = std::shared_ptr<const std::map<std::string, std::string>>;

struct Mdc {
    static Ctx& cur() {
        thread_local Ctx ctx = std::make_shared<const std::map<std::string, std::string>>();
        return ctx;
    }
    static void put(const std::string& k, const std::string& v) {
        auto m = std::make_shared<std::map<std::string, std::string>>(*cur());
        (*m)[k] = v;
        cur() = std::move(m);
    }
    static std::string get(const Ctx& c, const std::string& k) {
        const auto it = c->find(k);
        return it == c->end() ? "-" : it->second;
    }
    static void clear() { cur() = std::make_shared<const std::map<std::string, std::string>>(); }
    /** Capture at SUBMIT time, restore around the task, then put back what the worker had: no leaks between tasks. */
    template <class F> static auto wrap(F task) {
        return [captured = cur(), task = std::move(task)]() mutable {
            Ctx previous = cur();
            cur() = captured;
            struct Restore { Ctx p; ~Restore() { cur() = std::move(p); } } restore{std::move(previous)};
            task();
        };
    }
};

/** The InheritableThreadLocal mistake, reproduced: context copied when a THREAD is created, not when a TASK is submitted. */
thread_local std::string inherited;

class SingleThreadPool {  // creates its thread lazily on the first submit, like Executors.newSingleThreadExecutor
    std::mutex m_;
    std::condition_variable cv_;
    std::deque<std::function<void()>> q_;
    std::optional<std::jthread> worker_;
    bool stop_ = false;

public:
    SingleThreadPool() { std::scoped_lock warm(m_); }
    template <class F> std::future<void> submit(F f) {
        auto task = std::make_shared<std::packaged_task<void()>>(std::move(f));
        auto fut = task->get_future();
        std::scoped_lock l(m_);
        if (!worker_)
            worker_.emplace([this, parent = inherited] {  // the creator's value, copied forever
                inherited = parent;
                thread_name = "worker";
                for (;;) {
                    std::function<void()> job;
                    {
                        std::unique_lock lk(m_);
                        cv_.wait(lk, [&] { return stop_ || !q_.empty(); });
                        if (q_.empty()) return;
                        job = std::move(q_.front());
                        q_.pop_front();
                    }
                    job();
                }
            });
        q_.emplace_back([task] { (*task)(); });
        cv_.notify_one();
        return fut;
    }
    ~SingleThreadPool() {
        {
            std::scoped_lock l(m_);
            stop_ = true;
        }
        cv_.notify_all();
    }
};

// ---- events: preallocated and reused; producers fill a slot in place

using Arg = std::variant<std::monostate, i64, std::string>;

struct Event {
    Level level = Level::Info;
    i64 ts = 0, producer = -1, seq = -1;
    std::string thread, tmpl;  // reused buffers: assignment keeps capacity, so steady state does not allocate
    std::array<Arg, 4> args;
    sz argc = 0;
    Ctx mdc;
};

struct Appender {
    virtual ~Appender() = default;
    virtual void append(const Event& e, const std::string& line) = 0;
    virtual void close() {}
};

/** Bounded MPSC ring with per-slot sequence numbers (Vyukov). Slots hold reusable Event objects. */
class Ring {
    struct alignas(64) Slot {
        std::atomic<u64> seq;
        Event e;
    };
    std::vector<Slot> slots_;
    const u64 mask_;
    alignas(64) std::atomic<u64> tail_{0};
    alignas(64) u64 head_ = 0;  // consumer-owned

public:
    explicit Ring(u64 cap) : slots_(cap), mask_(cap - 1) {
        for (u64 i = 0; i < cap; ++i) slots_[i].seq.store(i, std::memory_order_relaxed);
    }
    i64 claim_blocking() {  // one atomic op; waits only if the ring is full
        const u64 pos = tail_.fetch_add(1, std::memory_order_relaxed);
        while (slots_[pos & mask_].seq.load(std::memory_order_acquire) != pos) {}
        return static_cast<i64>(pos);
    }
    i64 try_claim() {  // never waits: -1 when the slot is still in use
        for (;;) {
            u64 pos = tail_.load(std::memory_order_relaxed);
            const u64 s = slots_[pos & mask_].seq.load(std::memory_order_acquire);
            if (s < pos) return -1;
            if (s == pos && tail_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) return static_cast<i64>(pos);
        }
    }
    Event& at(i64 pos) { return slots_[static_cast<u64>(pos) & mask_].e; }
    void publish(i64 pos) { slots_[static_cast<u64>(pos) & mask_].seq.store(static_cast<u64>(pos) + 1, std::memory_order_release); }
    Event* peek() {
        Slot& s = slots_[head_ & mask_];
        return s.seq.load(std::memory_order_acquire) == head_ + 1 ? &s.e : nullptr;
    }
    void release() {
        slots_[head_ & mask_].seq.store(head_ + mask_ + 1, std::memory_order_release);
        ++head_;
    }
};

void render(std::string& out, const Event& e) {  // not "format": ADL on std::string would find std::format
    out.clear();
    std::format_to(std::back_inserter(out), "{} {} [{}] {} ", e.ts, kLevelNames[static_cast<sz>(e.level)], e.thread, Mdc::get(e.mdc, "requestId"));
    sz arg = 0;
    for (sz i = 0; i < e.tmpl.size(); ++i) {
        if (e.tmpl[i] == '{' && i + 1 < e.tmpl.size() && e.tmpl[i + 1] == '}' && arg < e.argc) {
            std::visit(overloaded{[](std::monostate) {}, [&](i64 v) { std::format_to(std::back_inserter(out), "{}", v); },
                                  [&](const std::string& v) { out += v; }},
                       e.args[arg++]);
            ++i;
        } else {
            out += e.tmpl[i];
        }
    }
}

class AsyncLogger {
    Ring ring_;
    Overflow overflow_;
    std::vector<Appender*> appenders_;
    std::function<i64()> clock_;
    std::atomic<bool> running_{true};
    i64 reported_drops_ = 0, delivered_ = 0, appender_errors_ = 0;  // consumer-owned
    std::jthread consumer_;

    static Arg to_arg(i64 v) { return v; }
    static Arg to_arg(int v) { return i64{v}; }
    static Arg to_arg(const char* v) { return std::string(v); }
    static Arg to_arg(const std::string& v) { return v; }

    void drain() {
        std::string line;  // reused: formatting allocates nothing per event once warm
        line.reserve(256);
        for (;;) {
            Event* e = ring_.peek();
            if (!e) {
                if (!running_.load() && !ring_.peek()) break;
                continue;
            }
            render(line, *e);
            for (Appender* a : appenders_) {
                try {
                    a->append(*e, line);
                } catch (const std::exception&) {  // a dead consumer would block every producer forever
                    ++appender_errors_;
                }
            }
            ++delivered_;
            e->mdc.reset();  // don't pin request contexts in the pool
            ring_.release();
            if (const i64 d = dropped.load(); d > reported_drops_ && (!ring_.peek() || delivered_ % 4'096 == 0)) {  // rate-limited loss notice
                Event w;
                w.level = Level::Warn;
                w.ts = clock_();
                w.thread = "log-consumer";
                w.tmpl = "dropped {} events (ring full)";
                w.args[0] = d - reported_drops_;
                w.argc = 1;
                w.mdc = std::make_shared<const std::map<std::string, std::string>>();
                reported_drops_ = d;
                render(line, w);
                for (Appender* a : appenders_) a->append(w, line);
            }
        }
        for (Appender* a : appenders_) a->close();
    }

public:
    std::atomic<Level> threshold;
    std::atomic<i64> dropped{0};

    AsyncLogger(Level t, u64 capacity, Overflow o, std::function<i64()> clock, std::vector<Appender*> appenders)
        : ring_(capacity), overflow_(o), appenders_(std::move(appenders)), clock_(std::move(clock)), consumer_([this] { drain(); }), threshold(t) {}
    ~AsyncLogger() { stop(); }

    void stop() {  // drains everything already published, then stops
        running_.store(false);
        if (consumer_.joinable()) consumer_.join();
    }
    i64 appender_errors() const { return appender_errors_; }  // read after stop()

    bool enabled(Level l) const { return l >= threshold.load(std::memory_order_relaxed); }

    // string_view, not const std::string&: a 17-char literal would be heap-allocated (libstdc++ SSO is 15) BEFORE the level check
    template <class... A> void log(Level l, std::string_view tmpl, const A&... args) {
        if (!enabled(l)) return;  // before any formatting, copying or claiming
        log_as(l, -1, -1, tmpl, args...);
    }

    template <class... A> void log_as(Level l, i64 producer, i64 seq, std::string_view tmpl, const A&... args) {
        const i64 pos = overflow_ == Overflow::Block ? ring_.claim_blocking() : ring_.try_claim();
        if (pos < 0) {
            dropped.fetch_add(1, std::memory_order_relaxed);  // never block the application thread
            return;
        }
        Event& e = ring_.at(pos);
        e.level = l;
        e.ts = clock_();
        e.thread = thread_name;
        e.tmpl = tmpl;
        e.argc = 0;
        ((e.args[e.argc++] = to_arg(args)), ...);
        e.mdc = Mdc::cur();  // a refcount bump, not a copy
        e.producer = producer;
        e.seq = seq;
        ring_.publish(pos);
    }
};

// ---- appenders

/** Counts lines and checks that each producer's events arrive in the order that producer logged them. */
struct Checker final : Appender {
    std::map<i64, i64> last_seq;
    i64 lines = 0, out_of_order = 0, drop_notices = 0;
    int slow_spins;
    explicit Checker(int s) : slow_spins(s) {}
    void append(const Event& e, const std::string&) override {
        ++lines;
        if (e.producer < 0) {
            ++drop_notices;
            return;
        }
        if (const auto it = last_seq.find(e.producer); it != last_seq.end() && e.seq <= it->second) ++out_of_order;
        last_seq[e.producer] = e.seq;
        for (int i = 0; i < slow_spins; ++i) {  // a slow disk / network appender
#if defined(__x86_64__) || defined(__i386__)
            __builtin_ia32_pause();
#endif
        }
    }
};

/** Size-based rolling: app.log -> app.1.log -> ... -> app.{keep}.log, the oldest deleted. */
struct RollingFile final : Appender {
    fs::path dir;
    std::string base;
    i64 max_bytes;
    int keep;
    std::ofstream out;
    i64 size = 0;
    int rolls = 0;
    RollingFile(fs::path d, std::string b, i64 max, int k) : dir(std::move(d)), base(std::move(b)), max_bytes(max), keep(k), out(file(0), std::ios::binary) {}
    fs::path file(int i) const { return dir / (i == 0 ? base + ".log" : std::format("{}.{}.log", base, i)); }
    void append(const Event&, const std::string& line) override {
        const i64 len = static_cast<i64>(line.size()) + 1;
        if (size + len > max_bytes) roll();
        out << line << '\n';
        size += len;
    }
    void roll() {
        out.close();
        fs::remove(file(keep));
        for (int i = keep - 1; i >= 0; --i)
            if (fs::exists(file(i))) fs::rename(file(i), file(i + 1));
        out.open(file(0), std::ios::binary);
        size = 0;
        ++rolls;
    }
    void close() override { out.close(); }
};

/** An appender that fails on one line: its failure must not stop the others, or the consumer. */
struct Faulty final : Appender {
    void append(const Event&, const std::string& line) override {
        if (line.ends_with("line 5000 of 20000")) throw std::runtime_error("disk full");
    }
};

/** Collects lines in memory (for the MDC demo). */
struct Memory final : Appender {
    std::mutex m;
    std::vector<std::string> lines;
    Memory() { std::scoped_lock warm(m); }
    void append(const Event&, const std::string& line) override {
        std::scoped_lock l(m);
        lines.push_back(line);
    }
};

// ---- harness

i64 now_ns() { return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }

struct Burst { i64 delivered, dropped, drop_notices, out_of_order, p50, p99, max, ms; };

Burst burst(Overflow policy, int slow_spins) {
    Checker checker(slow_spins);
    std::vector<std::vector<i64>> samples(4, std::vector<i64>(250'000 / 8));  // every 8th log() call's latency, per producer
    i64 t0 = 0;
    {
        AsyncLogger log(Level::Info, 1u << 13, policy, now_ns, {&checker});
        std::atomic<bool> go{false};
        std::vector<std::jthread> producers;
        for (i64 p = 0; p < 4; ++p)
            producers.emplace_back([&, p] {
                thread_name = std::format("producer-{}", p);
                while (!go.load()) {}
                auto& mine = samples[static_cast<sz>(p)];
                for (i64 i = 0; i < 250'000; ++i) {
                    const i64 a = (i & 7) == 0 ? now_ns() : 0;
                    log.log_as(Level::Info, p, i, "order {} item {}", p, i);
                    if ((i & 7) == 0) mine[static_cast<sz>(i >> 3)] = now_ns() - a;
                }
            });
        t0 = now_ns();
        go.store(true);
    }
    const i64 ms = (now_ns() - t0) / 1'000'000;
    std::vector<i64> all;
    for (const auto& s : samples) all.insert(all.end(), s.begin(), s.end());
    std::ranges::sort(all);
    const i64 delivered = checker.lines - checker.drop_notices;
    return {delivered, 1'000'000 - delivered, checker.drop_notices, checker.out_of_order, all[all.size() / 2], all[all.size() * 99 / 100], all.back(), ms};
}

int main() {
    std::setvbuf(stdout, nullptr, _IONBF, 0);
    std::println("== 1. A disabled DEBUG call must cost ~nothing: 20,000,000 calls at threshold INFO ==");
    {
        AsyncLogger log(Level::Info, 1u << 10, Overflow::Block, [] { return i64{0}; }, {});
        i64 sink = 0;
        for (int pass = 0; pass < 2; ++pass) {
            const i64 t0 = now_ns();
            for (i64 i = 0; i < 20'000'000; ++i) log.log(Level::Debug, std::format("user {} bought {}", i, i * 7));  // eager formatting
            const i64 t1 = now_ns();
            for (i64 i = 0; i < 20'000'000; ++i) log.log(Level::Debug, "user {} bought {}", i, i * 7);  // template + args
            const i64 t2 = now_ns();
            for (i64 i = 0; i < 20'000'000; ++i)
                if (log.enabled(Level::Debug)) log.log(Level::Debug, "user {} bought {}", i, i * 7);  // guarded
                else sink += i;
            const i64 t3 = now_ns();
            if (pass == 1)
                std::println("  eager format {:.2f} ns/call | template + args {:.2f} ns/call | guarded {:.2f} ns/call (sink {})",
                             static_cast<double>(t1 - t0) / 2e7, static_cast<double>(t2 - t1) / 2e7, static_cast<double>(t3 - t2) / 2e7, sink % 10);
        }
    }

    std::println("== 2. 4 producers x 250,000 events, ring of 8,192 pooled events, a slow appender (~1 us/event) ==");
    const Burst block = burst(Overflow::Block, 20), drop = burst(Overflow::Drop, 20);
    for (const Burst* b : {&block, &drop})
        std::println("  {:<6} delivered {}, dropped {} ({} drop notices) | order violations {} | log() p50 {} ns, p99 {} ns, max {:.1f} us | {} ms",
                     b == &block ? "BLOCK:" : "DROP:", b->delivered, b->dropped, b->drop_notices, b->out_of_order, b->p50, b->p99,
                     static_cast<double>(b->max) / 1e3, b->ms);

    std::println("== 3. Rolling file appender: 20,000 lines, roll at 64 KiB, keep 3 (logical clock) ==");
    const fs::path dir = fs::temp_directory_path() / "p17-logs-cpp";
    fs::create_directories(dir);
    RollingFile rolling(dir, "app", 64 * 1024, 3);
    Faulty faulty;
    i64 errors = 0;
    {
        i64 tick = 0;
        AsyncLogger log(Level::Info, 1u << 10, Overflow::Block, [&] { return ++tick; }, {&faulty, &rolling});
        for (i64 i = 0; i < 20'000; ++i) log.log(Level::Info, "line {} of 20000", i);
        log.stop();
        errors = log.appender_errors();
    }
    i64 kept = 0;
    std::string files, oldest_first;
    for (int i = 0; i <= 3; ++i) {
        if (!fs::exists(rolling.file(i))) continue;
        std::ifstream in(rolling.file(i), std::ios::binary);
        i64 n = 0;
        for (std::string l; std::getline(in, l);) {
            if (i == 3 && n == 0) oldest_first = l;
            ++n;
        }
        kept += n;
        files += std::format("{} {} lines {} bytes; ", rolling.file(i).filename().string(), n, fs::file_size(rolling.file(i)));
    }
    files.pop_back();
    std::println("  {}", files);
    std::println("  rolls {} | lines kept {} of 20000 | oldest kept line: {} | appender errors isolated: {}", rolling.rolls, kept, oldest_first, errors);
    fs::remove_all(dir);

    std::println("== 4. MDC across a thread pool ==");
    Memory mem;
    std::string inherited_seen, leak_after;
    {
        AsyncLogger log(Level::Info, 1u << 10, Overflow::Block, [] { return i64{0}; }, {&mem});
        SingleThreadPool pool;
        inherited = "req-A";  // request A happens to create the pool's thread
        pool.submit([] {}).get();
        inherited = "req-B";  // request B submits work to the same pool
        pool.submit([&] { inherited_seen = inherited; }).get();
        Mdc::put("requestId", "req-B");
        pool.submit(Mdc::wrap([&] { log.log(Level::Info, "charging card"); })).get();
        Mdc::clear();
        pool.submit([&] { leak_after = Mdc::get(Mdc::cur(), "requestId"); }).get();  // the worker must not keep B's context
    }
    const std::string wrapped_seen = mem.lines.at(0);
    std::println("  InheritableThreadLocal: request B's task sees requestId = {} (inherited when the thread was created)", inherited_seen);
    std::println("  capture at submit:      {}", wrapped_seen);
    std::println("  after the task, the worker's requestId is {} (restored, nothing leaks into the next task)", leak_after);

    const bool ok = block.dropped == 0 && block.out_of_order == 0 && drop.out_of_order == 0 && drop.delivered + drop.dropped == 1'000'000 &&
                    drop.dropped > 0 && drop.drop_notices > 0 && kept > 0 && kept < 20'000 && rolling.rolls > 3 &&
                    oldest_first.find("line ") != std::string::npos && errors == 1 && inherited_seen == "req-A" && wrapped_seen.ends_with("req-B charging card") &&
                    leak_after == "-";
    std::println("{}", ok ? "SELF-TEST OK" : "SELF-TEST FAILED");
    return ok ? 0 : 1;
}
```

**Output, GCC 16.2:**

```text
== 1. A disabled DEBUG call must cost ~nothing: 20,000,000 calls at threshold INFO ==
  eager format 192.99 ns/call | template + args 0.64 ns/call | guarded 2.37 ns/call (sink 0)
== 2. 4 producers x 250,000 events, ring of 8,192 pooled events, a slow appender (~1 us/event) ==
  BLOCK: delivered 1000000, dropped 0 (0 drop notices) | order violations 0 | log() p50 6400 ns, p99 15500 ns, max 395.6 us | 1646 ms
  DROP:  delivered 22929, dropped 977071 (4 drop notices) | order violations 0 | log() p50 100 ns, p99 500 ns, max 61.9 us | 35 ms
== 3. Rolling file appender: 20,000 lines, roll at 64 KiB, keep 3 (logical clock) ==
  app.log 1428 lines 57120 bytes; app.1.log 1638 lines 65520 bytes; app.2.log 1638 lines 65520 bytes; app.3.log 1638 lines 65520 bytes;
  rolls 11 | lines kept 6342 of 20000 | oldest kept line: 13659 INFO [main] - line 13658 of 20000 | appender errors isolated: 1
== 4. MDC across a thread pool ==
  InheritableThreadLocal: request B's task sees requestId = req-A (inherited when the thread was created)
  capture at submit:      0 INFO [worker] req-B charging card
  after the task, the worker's requestId is - (restored, nothing leaks into the next task)
SELF-TEST OK
```

**Output, Clang 21.1:**

```text
== 1. A disabled DEBUG call must cost ~nothing: 20,000,000 calls at threshold INFO ==
  eager format 187.30 ns/call | template + args 0.78 ns/call | guarded 0.68 ns/call (sink 0)
== 2. 4 producers x 250,000 events, ring of 8,192 pooled events, a slow appender (~1 us/event) ==
  BLOCK: delivered 1000000, dropped 0 (0 drop notices) | order violations 0 | log() p50 6500 ns, p99 15600 ns, max 345.9 us | 1665 ms
  DROP:  delivered 21964, dropped 978036 (4 drop notices) | order violations 0 | log() p50 100 ns, p99 600 ns, max 718.7 us | 45 ms
== 3. Rolling file appender: 20,000 lines, roll at 64 KiB, keep 3 (logical clock) ==
  app.log 1428 lines 57120 bytes; app.1.log 1638 lines 65520 bytes; app.2.log 1638 lines 65520 bytes; app.3.log 1638 lines 65520 bytes;
  rolls 11 | lines kept 6342 of 20000 | oldest kept line: 13659 INFO [main] - line 13658 of 20000 | appender errors isolated: 1
== 4. MDC across a thread pool ==
  InheritableThreadLocal: request B's task sees requestId = req-A (inherited when the thread was created)
  capture at submit:      0 INFO [worker] req-B charging card
  after the task, the worker's requestId is - (restored, nothing leaks into the next task)
SELF-TEST OK
```

## 6. L5 → L6 → L7

| Aspect | L5 | L6 | L7 |
|---|---|---|---|
| API | `log(String)` with concatenation | `{}` templates | Level check before anything; no allocation on the disabled path (verified per standard library); suppliers or guards for expensive args |
| Queue | `synchronized` + `ArrayList` | `ArrayBlockingQueue` | MPSC ring of preallocated events: one atomic claim, fill in place, publish; per-producer order |
| Overload | Unbounded queue (OOM) | Bounded, blocks | Explicit BLOCK/DROP (or per-level), measured latency, rate-limited loss notices |
| Consumer | One appender call per event, exceptions propagate | Background thread | One formatter thread, reused buffers, appender isolation, drain on shutdown, per-sink queues for slow sinks |
| Context | `InheritableThreadLocal` | Copy the map per event | Immutable snapshot by reference, capture at submit and restore after, `ScopedValue` on Java 25 |

## 7. Curveballs and 5-minute refactors

| Curveball | Response |
|---|---|
| "Change the level at runtime" | `threshold` is volatile/atomic: one store; producers read it with a relaxed/plain load |
| "Never lose ERROR lines" | Per-level policy: try-claim for < WARN, blocking claim for ≥ WARN; or a synchronous emergency appender for FATAL |
| "Logs after a crash" | Events still in the ring are lost. For audits use a memory-mapped ring (Chronicle Queue style) the next process can read, or BLOCK + sync-on-ERROR |
| "Time-based rolling + gzip" | Roll on a time boundary from the consumer; hand the closed file to a background compressor so the consumer never blocks on CPU |
| "JSON output" | A different `render()`; the ring and the policies are unchanged |
| "Virtual threads" | `ThreadLocal` MDC works but copies per virtual thread; `ScopedValue` is the intended carrier. The ring is unchanged: producers don't block unless BLOCK is chosen |

## 8. Bar-raiser chains

<details>
<summary><b>Q1 🔥 "Why is logging slowing the service when DEBUG is off?"</b></summary>

**L5:** "It isn't, the level check returns early."

**Why it fails:** the arguments are built before the call: concatenation is 21–193 ns. And in C++ a `const std::string&` parameter allocated a 17-character literal on every disabled call (50 ns on libstdc++).

**L7 defence:** "Templates with deferred formatting, a level check first, `string_view` parameters in C++, suppliers or guards for expensive args. Measure on each standard library, because SSO size differs."
</details>

<details>
<summary><b>Q2 ⚡ "The appender is slow. What happens to the app?"</b></summary>

**L5:** "It's async, the app doesn't notice."

**Why it fails:** the ring fills. Under BLOCK, producers wait at the appender's rate (p99 10–16 µs per call here). Under an unbounded queue, memory explodes.

**L7 defence:** "Bounded ring, explicit policy: DROP sheds load with a rate-limited notice (p99 ≤ 1.3 µs), BLOCK keeps everything; usually drop below WARN. Slow sinks get their own ring, and appender exceptions are isolated so the consumer can't die and wedge every producer."
</details>

<details>
<summary><b>Q3 ⚡ "Request B's log lines show request A's id."</b></summary>

**L5:** "Use InheritableThreadLocal so child threads get the MDC."

**Why it fails:** it copies at thread **creation**. Pool threads outlive requests, so B ran on a thread A created and logged `req-A`.

**L7 defence:** "Capture the immutable MDC snapshot at submit, install it around the task, restore afterwards. On Java 25, `ScopedValue` with structured concurrency does this by construction."
</details>

## 9. Failure modes and checklist

| Symptom | Root cause | Fix |
|---|---|---|
| CPU burned with DEBUG off | Arguments built before the level check | Templates, guards, `string_view` |
| Out-of-memory under a log storm | Unbounded queue | Bounded ring + policy |
| Application hangs; logger thread gone | Appender exception killed the consumer | Per-appender isolation |
| Lines out of order per thread | Multiple consumers / unordered queue | One consumer; per-producer increasing claims |
| Wrong `requestId` | Thread-creation inheritance | Capture at submit, restore after |
| Lost lines on exit | No drain | `stop()` drains published events; shutdown hook |

- [ ] Disabled path: no format, no copy, no allocation (checked per library).
- [ ] Pooled events in an MPSC ring; reused format buffer; references cleared after use.
- [ ] Explicit BLOCK/DROP (per level), loss notices, p99 measured.
- [ ] One consumer, isolated appenders, drain on stop; rolling with a rename chain.
- [ ] MDC: immutable snapshot, captured at submit.

## 10. References

- LMAX Disruptor (pre-allocated ring entries). <https://lmax-exchange.github.io/disruptor/>
- Apache Log4j 2, *Garbage-free logging* and *Async loggers*. <https://logging.apache.org/log4j/2.x/manual/garbagefree.html>
- JEP 506, *Scoped Values*. <https://openjdk.org/jeps/506>
- Java `InheritableThreadLocal`. <https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/InheritableThreadLocal.html>
- In this KB: [P12 MPSC ring as a sequencer](../05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/02-problem-12-stock-exchange-limit-order-book-price-time-matching-engine.md) · [01.3 SPSC rings and false sharing](../01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) · [P20 Structured concurrency](05-problem-20-dynamic-rule-engine-and-json-Workflow-state-orchestrator.md)
