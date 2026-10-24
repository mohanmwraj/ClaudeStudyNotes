# 3.1 · The Java Memory Model (JMM): Happens-Before, `volatile`, Fences, Safe Publication

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam ("thread-safe code", visibility)
> **Sources:** JLS SE 25 Chapter 17 (§17.4 Memory Model, §17.5 final fields, §17.7 non-atomic `long`/`double`), JSR-133 and Doug Lea's "JSR-133 Cookbook for Compiler Writers", Doug Lea's "Using JDK 9 Memory Order Modes", Aleksey Shipilëv's "Java Memory Model Pragmatics", `java.util.concurrent` package docs ("Memory Consistency Properties"), the jcstress project.
> The two reordering demos below were **observed on this machine** (x86-64, Temurin 25.0.4.1). They are not hypothetical.

---

## 1. Why Java needs a memory model 🔥

Three independent layers reorder and cache your memory operations:

| Layer | What it does | Example |
|---|---|---|
| **Compiler / JIT** | Reorders, eliminates, hoists and caches loads and stores when single-threaded semantics are preserved | Hoists a non-volatile field read out of a loop, so the loop never sees the update |
| **CPU core** | Out-of-order execution; **store buffers** let a core read before its earlier store is globally visible | x86 permits **StoreLoad** reordering (Dekker's algorithm breaks) |
| **Memory hierarchy** | Per-core caches with coherence protocols (MESI). Invalidation queues on weak architectures delay visibility | ARM/POWER: loads and stores can be observed in different orders by different cores |

| Architecture | Reorderings visible to other cores | Notes |
|---|---|---|
| **x86-64 (TSO)** | Only **StoreLoad** (a later load can pass an earlier store to a different address) | "Strong" model, so many latent races never show up on Intel/AMD |
| **ARMv8 / AArch64** (AWS Graviton, Ampere, Apple M-series) | LoadLoad, LoadStore, StoreStore, StoreLoad: **all** | Moving to ARM instances exposes data races that were dormant on x86 |
| POWER | All, plus non-multi-copy-atomic stores | Historically the hardest |

The **JMM** is the contract that hides this zoo. **If your program has no data races, it behaves as if sequentially consistent (SC)**: this is the *DRF-SC guarantee*. If it has data races, you get only the weak guarantees of JLS §17.4.8 (no out-of-thin-air values), and the JIT and CPU may surprise you.

---

## 2. The rules: happens-before 🔥🎓

**Definitions (JLS §17.4):**

* A **data race** is two accesses to the same variable from different threads, at least one a write, **not ordered by happens-before**.
* **Happens-before (HB)** is a partial order. If *a* HB *b*, then *a*'s effects are visible to *b* and *a* appears ordered before *b*.

**The HB edges:**

| Rule | Edge |
|---|---|
| Program order | Each action in a thread HB every later action **in that same thread** |
| Monitor lock | An **unlock** of monitor M HB every **subsequent lock** of M |
| `volatile` | A **write** to volatile v HB every **subsequent read** of v (that sees that write) |
| Thread start | `t.start()` HB every action in `t` |
| Thread termination | Every action in `t` HB another thread's return from `t.join()` (or seeing `t.isAlive() == false`) |
| Interruption | `t.interrupt()` HB the interrupted thread detecting it (`InterruptedException`, `isInterrupted`) |
| Default values | Writing default values (0/null) HB every thread's first action |
| Finalizer | End of the constructor HB the start of the finalizer |
| **Transitivity** | a HB b and b HB c ⇒ a HB c |

`java.util.concurrent` **documents additional HB edges** ("Memory Consistency Properties"): actions before `BlockingQueue.put` HB actions after the corresponding `take`; before `executor.submit(task)` HB the task's execution; the task's actions HB `future.get()` returning; `countDown()` HB a returning `await()`; `CompletableFuture.complete` HB the dependent stages; `ConcurrentMap.put` HB a `get` that sees the value; `Lock.unlock` HB a subsequent `lock`; and so on.

> **Mental model:** HB is how you *transport* writes between threads. Any variable shared between threads needs an HB path from the writer to the reader, via a lock, a volatile, a `j.u.c` structure, `start`/`join`, a `final` field freeze, or class initialization.

---

## 3. Demo 1 — visibility: the loop that never ends 🔥

<!-- run: -->
```java
public class Visibility {
    static boolean stopPlain;                    // no happens-before between writer and reader
    static volatile boolean stopVolatile;

    static boolean stillRunningAfter(Runnable spin, Runnable stop) throws InterruptedException {
        Thread t = new Thread(spin);
        t.setDaemon(true);                       // so a stuck spinner can't keep the JVM alive
        t.start();
        Thread.sleep(300);                       // let the loop get hot and C2-compiled
        stop.run();
        t.join(2000);
        return t.isAlive();
    }

    public static void main(String[] args) throws Exception {
        boolean plain = stillRunningAfter(() -> { long n = 0; while (!stopPlain) n++; }, () -> stopPlain = true);
        boolean vol = stillRunningAfter(() -> { long n = 0; while (!stopVolatile) n++; }, () -> stopVolatile = true);
        System.out.println("non-volatile flag: thread still running 2 s after stop=true? " + plain);
        System.out.println("volatile flag:     thread still running 2 s after stop=true? " + vol);
    }
}
```

Output (verified, JDK 25 with the default JIT):

```
non-volatile flag: thread still running 2 s after stop=true? true
volatile flag:     thread still running 2 s after stop=true? false
```

With `java -Xint Visibility.java` (interpreter only) both print `false`. The bug comes from the **JIT**, not the CPU: C2 sees no synchronization in the loop, proves `stopPlain` can't change within the thread, hoists the load out of the loop, and compiles `while (true) n++;`. Your code "works" in debug runs and tests, and hangs forever under production load. The **cache-coherent x86 hardware** would have shown the update within nanoseconds.

---

## 4. Demo 2 — reordering: Dekker's test on x86 🔥

Two threads each write their own flag, then read the other's. Under sequential consistency at least one must see the other's write, so `r1 == r2 == 0` is impossible.

<!-- run: timeout=120 -->
```java
import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.util.concurrent.CyclicBarrier;

public class Dekker {
    static final VarHandle INTS = MethodHandles.arrayElementVarHandle(int[].class);
    static final int N = 2_000_000;

    /** Runs N independent instances of the litmus test; counts outcomes where BOTH reads saw 0. */
    static long run(boolean sc) throws Exception {
        int[] x = new int[N], y = new int[N], r1 = new int[N], r2 = new int[N];
        CyclicBarrier start = new CyclicBarrier(2);
        Thread t1 = new Thread(() -> {
            await(start);
            for (int i = 0; i < N; i++) {
                if (sc) { INTS.setVolatile(x, i, 1); r1[i] = (int) INTS.getVolatile(y, i); }
                else { x[i] = 1; r1[i] = y[i]; }                  // plain: store then load
            }
        });
        Thread t2 = new Thread(() -> {
            await(start);
            for (int i = 0; i < N; i++) {
                if (sc) { INTS.setVolatile(y, i, 1); r2[i] = (int) INTS.getVolatile(x, i); }
                else { y[i] = 1; r2[i] = x[i]; }
            }
        });
        t1.start(); t2.start(); t1.join(); t2.join();
        long both0 = 0;
        for (int i = 0; i < N; i++) if (r1[i] == 0 && r2[i] == 0) both0++;
        return both0;
    }
    static void await(CyclicBarrier b) { try { b.await(); } catch (Exception e) { throw new RuntimeException(e); } }

    public static void main(String[] args) throws Exception {
        for (int round = 0; round < 4; round++)
            System.out.printf("plain: r1=r2=0 in %,d of %,d | volatile: %,d%n", run(false), N, run(true));
    }
}
```

One measured run (x86-64 laptop, 4 rounds):

```
plain: r1=r2=0 in 0 of 2,000,000 | volatile: 0
plain: r1=r2=0 in 7,392 of 2,000,000 | volatile: 0
plain: r1=r2=0 in 5,952 of 2,000,000 | volatile: 0
plain: r1=r2=0 in 7,088 of 2,000,000 | volatile: 0
```

An earlier 3-round run on the same machine saw 0 / 14,832 / 0.

* The forbidden-under-SC outcome **happened thousands of times per round**. Rounds where the threads didn't overlap show 0, which is exactly why concurrency bugs are intermittent.
* The cause is the **store buffer**: each core's write sits in its store buffer while its subsequent load reads the other variable from cache (StoreLoad reordering). The JIT may also legally reorder the plain store and load.
* With **volatile** accesses (sequentially consistent, `setVolatile`/`getVolatile`): **never**. HotSpot emits a StoreLoad fence after each volatile store (on x86, a `lock`-prefixed instruction).

---

## 5. `volatile` precisely 🔥🎓

| Guarantee | Yes/No |
|---|---|
| **Visibility**: a read sees the latest write in the synchronization order | ✅ |
| **Ordering**: writes before a volatile write are visible to a thread that reads that volatile (release/acquire); all volatile accesses form a single total order (SC) | ✅ |
| **Atomic 64-bit** reads/writes of `long`/`double` | ✅ (non-volatile `long`/`double` may tear per JLS §17.7, though not on 64-bit HotSpot in practice) |
| **Atomic read-modify-write** (`count++`, check-then-act) | ❌ |

<!-- run: -->
```java
import java.util.concurrent.atomic.AtomicInteger;

public class VolatileNotAtomic {
    static volatile int volatileCount;
    static final AtomicInteger atomicCount = new AtomicInteger();

    public static void main(String[] args) throws Exception {
        Thread[] ts = new Thread[4];
        for (int t = 0; t < ts.length; t++) {
            ts[t] = new Thread(() -> {
                for (int i = 0; i < 1_000_000; i++) { volatileCount++; atomicCount.incrementAndGet(); }
            });
            ts[t].start();
        }
        for (Thread t : ts) t.join();
        System.out.println("expected 4000000 | volatile int: " + volatileCount + " | AtomicInteger: " + atomicCount.get());
    }
}
```

Output (one measured run; the volatile number varies run to run but is essentially always below 4,000,000):

```
expected 4000000 | volatile int: 1869917 | AtomicInteger: 4000000
```

`volatileCount++` is three steps (read, add, write), and interleavings lose updates even though every individual read and write is visible. Use atomics (`incrementAndGet`, `LongAdder`) or a lock.

### 5.1 What `volatile` compiles to (HotSpot)

| Access | x86-64 | AArch64 |
|---|---|---|
| volatile **load** | plain `mov` (TSO already prevents LoadLoad/LoadStore) | `ldar` (load-acquire) |
| volatile **store** | `mov` + **`lock addl $0,(rsp)`** (a full StoreLoad fence; cheaper than `mfence`) | `stlr` (store-release; with `ldar` gives SC) |
| `synchronized` enter/exit | `lock cmpxchg` (CAS) — implies a full fence | `casa`/`ldaxr`+`stlxr` |

A volatile write on x86 costs tens of cycles, because the store buffer must drain. Reads are nearly free. That asymmetry is why "read-mostly volatile flags" are cheap.

### 5.2 The four barrier types (JSR-133 cookbook)

| Barrier | Prevents | Needed by |
|---|---|---|
| LoadLoad | Load₁; Load₂ reordering | Acquire semantics |
| LoadStore | Load₁; Store₂ | Acquire semantics |
| StoreStore | Store₁; Store₂ | Release semantics, final-field freeze |
| **StoreLoad** | Store₁; Load₂ (the store-buffer reordering in Demo 2) | Volatile store followed by volatile load; the most expensive barrier |

Explicit fences: `VarHandle.acquireFence()` (LoadLoad + LoadStore), `releaseFence()` (LoadStore + StoreStore), `fullFence()` (all), `loadLoadFence()`, `storeStoreFence()`.

---

## 6. Access modes beyond volatile (`VarHandle`) ⚡

| Mode | Ordering | Typical use |
|---|---|---|
| Plain | None; may be cached, hoisted or reordered | Thread-confined data, data protected by another HB edge |
| **Opaque** | Per-variable coherence, never hoisted out of loops; no ordering with *other* variables | Progress flags or counters observed by monitoring threads; "eventually see the value" |
| **Release / Acquire** | Writes before a `setRelease` are visible to a thread that `getAcquire`s that value (one-way publication); no StoreLoad | **Single-producer/single-consumer handoff**, lazySet in queues (`AtomicLong.lazySet` = `setRelease`) |
| Volatile | Sequentially consistent | When you reason with "everyone sees the same order" |

Release/acquire is enough for **message passing** (producer writes data, then releases a flag; consumer acquires the flag, then reads data) and avoids the StoreLoad fence. Dekker-style "I write mine, then read yours" mutual exclusion needs volatile (SC).

<!-- run: -->
```java
import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;

/** A single-producer/single-consumer ring buffer using release/acquire instead of locks or volatiles everywhere. */
public class SpscRing {
    private final long[] buffer;
    private final int mask;
    private long head;                  // next slot to READ  (written only by the consumer)
    private long tail;                  // next slot to WRITE (written only by the producer)
    private static final VarHandle HEAD, TAIL;
    static {
        try {
            HEAD = MethodHandles.lookup().findVarHandle(SpscRing.class, "head", long.class);
            TAIL = MethodHandles.lookup().findVarHandle(SpscRing.class, "tail", long.class);
        } catch (ReflectiveOperationException e) { throw new ExceptionInInitializerError(e); }
    }

    SpscRing(int capacityPowerOfTwo) { buffer = new long[capacityPowerOfTwo]; mask = capacityPowerOfTwo - 1; }

    boolean offer(long value) {                                   // producer thread only
        long t = tail;                                            // own variable: plain read
        if (t - (long) HEAD.getAcquire(this) == buffer.length) return false;   // full
        buffer[(int) (t & mask)] = value;                         // 1. write the data (plain)
        TAIL.setRelease(this, t + 1);                             // 2. publish: data write can't move below this
        return true;
    }

    long poll() {                                                 // consumer thread only; Long.MIN_VALUE = empty
        long h = head;
        if (h == (long) TAIL.getAcquire(this)) return Long.MIN_VALUE;   // acquire: see the data the producer released
        long v = buffer[(int) (h & mask)];
        HEAD.setRelease(this, h + 1);                             // free the slot for the producer
        return v;
    }

    public static void main(String[] args) throws Exception {
        SpscRing q = new SpscRing(1024);
        long n = 5_000_000;
        Thread producer = new Thread(() -> { for (long i = 1; i <= n; ) if (q.offer(i)) i++; else Thread.onSpinWait(); });
        long[] sum = new long[1];
        Thread consumer = new Thread(() -> {
            long received = 0;
            while (received < n) { long v = q.poll(); if (v != Long.MIN_VALUE) { sum[0] += v; received++; } else Thread.onSpinWait(); }
        });
        producer.start(); consumer.start(); producer.join(); consumer.join();
        System.out.println("sum=" + sum[0] + " expected=" + (n * (n + 1) / 2) + " ok=" + (sum[0] == n * (n + 1) / 2));
    }
}
```

Output (verified): `sum=12500002500000 expected=12500002500000 ok=true`

This is the core idea behind JCTools' and the LMAX Disruptor's queues. Each index has a **single writer**, so no CAS is needed; release/acquire carries the data across threads; `Thread.onSpinWait()` emits the x86 `PAUSE` instruction, which is polite to the sibling hyper-thread.

---

## 7. Safe publication 🔥

**Unsafe publication** means making a reference visible to another thread **without an HB edge**. The reader may see the reference but **default values for the object's fields**, because the constructor's writes can be reordered after the reference store.

### 7.1 The safe-publication idioms

| Idiom | Why it's safe |
|---|---|
| Initialize in a **static initializer** (`static final X = new X()`) | Class initialization HB the first use by any thread |
| Store into a **`volatile`** field or `AtomicReference` | Volatile write HB a subsequent read |
| Store into a field guarded by a **lock** (and read under the same lock) | Unlock HB lock |
| Put into a **concurrent collection** or `BlockingQueue` | Documented HB |
| Pass to `Thread` before `start()`, or to `executor.submit` | Start and submit HB edges |
| Object with only **`final` fields** (immutable), correctly constructed | Final-field semantics (§17.5): visible even through a race |

### 7.2 Double-checked locking: broken and fixed

```java
// ❌ BROKEN without volatile: another thread can see a non-null `instance` whose fields aren't initialized
class Config {
    private static Config instance;
    static Config get() {
        if (instance == null) {                       // first check without a lock: racy read
            synchronized (Config.class) {
                if (instance == null) instance = new Config();   // reference store may be reordered before field init
            }
        }
        return instance;
    }
}

// ✅ Fixed: volatile gives release on publish, acquire on read
class Config2 {
    private static volatile Config2 instance;
    static Config2 get() {
        Config2 local = instance;                     // one volatile read on the fast path
        if (local == null) {
            synchronized (Config2.class) {
                local = instance;
                if (local == null) instance = local = new Config2();
            }
        }
        return local;
    }
}

// ✅✅ Simplest: the holder idiom (class initialization is lazy and thread-safe), or an enum singleton
class Config3 {
    private static final class Holder { static final Config3 INSTANCE = new Config3(); }
    static Config3 get() { return Holder.INSTANCE; }
}
```

### 7.3 `final` fields: the freeze and `this` escape

* At the end of the constructor, `final` fields are **frozen**: any thread that obtains the object reference *after* construction (even via a race) sees the final fields' values, and objects reachable through them as of the freeze. On weak architectures the JIT emits a StoreStore barrier at constructor exit for this.
* This guarantee is void if **`this` escapes during construction**: registering `this` as a listener, starting a thread with `this`, or storing it into a static field from inside the constructor. Another thread might then observe the object before the freeze.
* Records and immutable value classes inherit this safety for free. That is one of the strongest arguments for immutability in concurrent code.

---

## 8. Atomicity rules (JLS §17.6–17.7) 🎓

* Reads and writes of references and of primitives up to 32 bits are atomic. **Non-volatile `long`/`double` may be split into two 32-bit halves** ("tearing") per the spec. 64-bit HotSpot doesn't tear aligned longs, but portable code, and code reviewed for the exam, must use `volatile` or atomics.
* No **word tearing**: updating one array element or field never corrupts an adjacent `byte`/`boolean`.
* Compound actions (`check-then-act`, `read-modify-write`, iteration + modification) are never atomic without synchronization.

---

## 9. Testing memory-model behaviour: jcstress ⚡

Ordinary unit tests can't reliably detect races. **jcstress** runs litmus tests millions of times with varied timing and compilation modes, and classifies outcomes:

```java
@JCStressTest
@Outcome(id = {"0, 1", "1, 0", "1, 1"}, expect = Expect.ACCEPTABLE, desc = "SC outcomes")
@Outcome(id = "0, 0", expect = Expect.ACCEPTABLE_INTERESTING, desc = "StoreLoad reordering (plain fields)")
@State
public class DekkerTest {
    int x, y;
    @Actor public void actor1(II_Result r) { x = 1; r.r1 = y; }
    @Actor public void actor2(II_Result r) { y = 1; r.r2 = x; }
}
```

Run it on **both x86 and ARM** CI agents. Many outcomes forbidden on x86 appear on AArch64.

---

## 10. Production failure modes & diagnostics (memory model)

| Failure | Signature | Fix |
|---|---|---|
| Thread never sees a stop flag | Spinning thread at 100% CPU after shutdown; thread dump shows it RUNNABLE in a loop | `volatile`/`AtomicBoolean`; better, interruption or a `BlockingQueue` poison pill |
| Partially constructed object seen | NPEs on fields that "can't be null", only under load | Safe publication (volatile, final fields, concurrent collections) |
| Bugs appear after moving to ARM (Graviton) | Rare data corruption, hangs | jcstress on ARM; remove data races, which the "x86 happens to work" assumption hid |
| Lost updates on a `volatile` counter | Metrics drift low | `LongAdder`/`AtomicLong` |
| Code works in the debugger, fails in prod | Interpreter vs C2 behaviour (Demo 1) | Treat any unsynchronized sharing as a bug, regardless of tests |
| Busy-spin burning cores | Spin loops without backoff | `Thread.onSpinWait()`, bounded spins, then park (`LockSupport`) |

**Detection tools:** code review for shared mutable state, static analysis (Error Prone `GuardedBy`, SpotBugs `IS2_INCONSISTENT_SYNC`, `VO_VOLATILE_INCREMENT`), jcstress for low-level code, and stress tests with many threads on many-core ARM and x86 machines. (Java's dynamic race detection is limited; ThreadSanitizer for Java was an experiment.)

---

## 11. Interview & certification Q&A

<details><summary><b>Q1. 🔥 What is happens-before? List five rules that create it.</b></summary>

A partial order guaranteeing that if *a* HB *b*, *a*'s memory effects are visible to and ordered before *b*. Rules: program order within a thread; monitor unlock HB a subsequent lock of the same monitor; volatile write HB a subsequent read of that variable; `Thread.start()` HB the started thread's actions; a thread's actions HB `join()` returning; plus transitivity, interruption, and the `j.u.c` documented edges (queue put → take, submit → execution, task → `Future.get`).
</details>

<details><summary><b>Q2. 🔥 Why can a `while (!stop)` loop on a non-volatile field spin forever, even on cache-coherent x86?</b></summary>

With no HB edge, the JIT may assume the field doesn't change inside the loop and **hoist the read** out of it, compiling an infinite loop. It is a compiler optimization, not a hardware cache issue, which is why `-Xint` "fixes" it. Declaring the field `volatile` (or reading it with acquire/opaque semantics) forbids the hoisting.
</details>

<details><summary><b>Q3. 🔥 Does `volatile` make `count++` thread-safe?</b></summary>

No. It guarantees visibility and ordering of individual reads and writes, but `count++` is read-modify-write, so concurrent increments interleave and lose updates (measured: about 1.87M instead of 4M). Use `AtomicInteger.incrementAndGet`, `LongAdder`, or a lock.
</details>

<details><summary><b>Q4. ⚡ Why is double-checked locking broken without `volatile`?</b></summary>

`instance = new Config()` involves allocating, running the constructor (field writes) and storing the reference. Without an HB edge, the reference store can become visible to another thread before the field writes (compiler or CPU reordering). The racy first check can then return a non-null reference to a partially initialized object. `volatile` makes the publication a release and the read an acquire. The holder idiom avoids the problem entirely.
</details>

<details><summary><b>Q5. ⚡ What reordering does x86 allow, and how does HotSpot implement a volatile store there?</b></summary>

x86 TSO only allows **StoreLoad** reordering (a later load passing an earlier store via the store buffer). HotSpot implements a volatile store as a normal `mov` followed by a `lock addl $0x0,(%rsp)`, which drains the store buffer and acts as a full fence. Volatile loads are plain `mov`s.
</details>

<details><summary><b>Q6. 🧊 When is release/acquire sufficient instead of volatile?</b></summary>

For one-way publication (message passing): a writer publishes data and then a flag/index with `setRelease`, and a reader `getAcquire`s the flag and then reads the data. It isn't sufficient when correctness needs a single global order of independent writes as seen by all threads, as in Dekker or Peterson mutual exclusion, which needs StoreLoad ordering (volatile/SC or a full fence).
</details>

<details><summary><b>Q7. 🎓 Name four ways to safely publish an object.</b></summary>

Initialize it from a static initializer; store it in a volatile field or `AtomicReference`; store and read it under the same lock; put it into a thread-safe collection or queue (or hand it to `Thread.start`/`executor.submit`). Or make it immutable with final fields and avoid `this` escape.
</details>

<details><summary><b>Q8. ⚡ What does the "DRF-SC" guarantee say?</b></summary>

If a program is correctly synchronized (no data races in any sequentially consistent execution), then all its executions appear sequentially consistent. You only need to reason about interleavings, not hardware reorderings, as long as there are no races.
</details>

<details><summary><b>Q9. 🧊 Why might a race-free-looking program on x86 fail on AWS Graviton?</b></summary>

ARMv8 allows LoadLoad, LoadStore and StoreStore reordering that x86 forbids. Code with a data race that "happened to work" on x86 (relying on TSO, for example publishing via a plain flag after plain data writes) can observe stale data or partially constructed objects on ARM. Fix the data race with proper HB, and test with jcstress on ARM.
</details>

<details><summary><b>Q10. 🎓 Are reads and writes of `long` atomic?</b></summary>

Per the JLS, only if the variable is `volatile`. Non-volatile `long`/`double` accesses may be split into two 32-bit operations. 64-bit JVMs don't tear in practice, but the specification (and the exam) say to use `volatile` or atomics.
</details>

---

## 12. Further reading

* JLS Chapter 17: <https://docs.oracle.com/javase/specs/jls/se25/html/jls-17.html>
* Doug Lea, "JSR-133 Cookbook": <https://gee.cs.oswego.edu/dl/jmm/cookbook.html> and "Using JDK 9 Memory Order Modes": <https://gee.cs.oswego.edu/dl/html/j9mm.html>
* Aleksey Shipilëv, "Java Memory Model Pragmatics" and "Close Encounters of the JMM Kind": <https://shipilev.net/blog/2016/close-encounters-of-jmm-kind/>
* jcstress: <https://github.com/openjdk/jcstress>
