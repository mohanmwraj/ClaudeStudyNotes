# 3.3 · Lock-Free Programming — CAS, Atomics, ABA, `LongAdder` vs `AtomicLong`, Lock-Free Structures

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam (atomic classes)
> **Sources:** `java.util.concurrent.atomic` package docs, `Striped64`/`LongAdder` source, Herlihy & Shavit *The Art of Multiprocessor Programming* (progress guarantees, Treiber stack, Michael–Scott queue), Intel SDM (`LOCK CMPXCHG`, `LOCK XADD`), Arm ARM (LSE `CAS`, `LDADD`; LL/SC `LDXR/STXR`).
> Throughput numbers are one measured run on a 12-thread laptop (JDK 25). Ratios matter, absolute values don't.

---

## 1. Compare-and-swap at the hardware level 🔥

```
CAS(addr, expected, new):  atomically { if (*addr == expected) { *addr = new; return true; } return false; }
```

| Platform | Instruction | Notes |
|---|---|---|
| x86-64 | `LOCK CMPXCHG` | Full barrier; the core takes the cache line in **exclusive (M/E) state**. `AtomicLong.incrementAndGet` compiles to **`LOCK XADD`** (fetch-and-add: no retry loop, always succeeds) |
| ARMv8.1+ (LSE) | `CAS`, `LDADD`, `SWP` | Single-instruction atomics (Graviton 2+) |
| ARMv8.0 | `LDXR`/`STXR` (load-linked / store-conditional) loop | The store can fail spuriously, which is why `weakCompareAndSet` exists |

**Cost model:** an uncontended CAS on a line already in the core's cache costs ~10–20 cycles. A **contended** CAS must pull the line from another core (~50–100+ ns cross-socket), and failed CASes retry. Throughput therefore *drops* as threads are added: atomics don't scale under write contention.

---

## 2. The atomic classes 🔥🎓

| Class | Key operations | Notes |
|---|---|---|
| `AtomicInteger`/`AtomicLong`/`AtomicBoolean`/`AtomicReference<V>` | `get`, `set`, `lazySet` (= release), `compareAndSet`, `weakCompareAndSet*`, `getAndIncrement`, `incrementAndGet`, `getAndAdd`, `updateAndGet(f)`, `accumulateAndGet(x, f)`, `compareAndExchange` | Backed by `VarHandle`/intrinsics |
| `AtomicIntegerArray`/`LongArray`/`ReferenceArray` | Per-element atomics | Elements are independent, but adjacent elements share cache lines (false sharing) |
| `Atomic*FieldUpdater` | CAS on a `volatile` field of *many* objects without an `Atomic*` wrapper per object | Saves memory (no extra object per instance). Reflection-based setup; `VarHandle` is the modern equivalent |
| `AtomicStampedReference<V>` | Reference + `int` stamp, CAS on both | ABA protection |
| `AtomicMarkableReference<V>` | Reference + `boolean` mark | Logical deletion in lock-free lists |
| `LongAdder`/`DoubleAdder` | `increment`, `add`, `sum`, `sumThenReset` | **Scalable counters**: striped cells |
| `LongAccumulator`/`DoubleAccumulator` | `accumulate(x)` with an associative, commutative function | Max/min trackers at scale |

### 2.1 `updateAndGet` retries: functions must be side-effect free

<!-- run: -->
```java
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

public class UpdateRetries {
    public static void main(String[] args) throws Exception {
        AtomicLong value = new AtomicLong();
        AtomicInteger functionCalls = new AtomicInteger();
        Thread[] ts = new Thread[8];
        for (int i = 0; i < ts.length; i++) {
            ts[i] = new Thread(() -> {
                for (int k = 0; k < 100_000; k++)
                    value.updateAndGet(v -> { functionCalls.incrementAndGet(); return v + 1; });   // side effect = a bug in real code
            });
            ts[i].start();
        }
        for (Thread t : ts) t.join();
        System.out.println("updates=" + value.get() + " function invocations=" + functionCalls.get()
            + " (" + (functionCalls.get() > value.get() ? "retried under contention" : "no retries this time") + ")");
    }
}
```

Output (one measured run; the invocation count varies):

```
updates=800000 function invocations=4048745 (retried under contention)
```

`updateAndGet` loops: `prev = get(); next = f(prev); if (compareAndSet(prev, next)) return next;`. Under contention **f runs multiple times per successful update**. Never put I/O, logging, ID generation or other side effects inside it.

---

## 3. `AtomicLong` vs `LongAdder` under contention 🔥

### 3.1 How `LongAdder` (`Striped64`) works

```
LongAdder
 ├── volatile long base               ← uncontended: CAS base (like AtomicLong)
 └── volatile Cell[] cells            ← created on first CAS failure; grows (×2) on repeated collisions, up to ≥ #CPUs
        Cell { @Contended volatile long value; }   ← each cell padded to its own cache-line pair (no false sharing)
 increment(): pick a cell by the thread's probe hash (ThreadLocalRandom); CAS that cell; on collision, rehash the probe
 sum():       base + Σ cells   ← NOT an atomic snapshot: concurrent updates may or may not be included
```

### 3.2 Measured scaling (ops/s, all threads hammering one counter)

```
threads       AtomicLong       LongAdder    synchronized     manual CAS fail/op
1            161,707,905     119,064,230      82,134,622                   0.00
2             95,589,455     179,405,425      49,064,577                   0.36
4             87,408,245     400,787,837      31,092,462                   0.86
8             80,609,017     710,558,820      29,518,050                   1.50
```

* `AtomicLong` (a `LOCK XADD` on one cache line) gets **slower** as threads are added (162M → 81M ops/s), because the line ping-pongs between cores.
* `LongAdder` **scales** (119M → 711M ops/s, ~9× AtomicLong at 8 threads) because threads update different cache lines. It's slightly slower single-threaded (extra indirection).
* A hand-written CAS loop (`get` + `compareAndSet`) fails **1.5 times per successful increment at 8 threads**. That's wasted work, and why `getAndAdd`'s single `XADD` instruction beats a CAS loop.

### 3.3 When to use which

| Need | Use |
|---|---|
| High-frequency counters and metrics (request counts, bytes) | **`LongAdder`** (Micrometer counters use it) |
| A value you **read-modify-write with logic** (sequence numbers, `compareAndSet` state machines) | `AtomicLong` / `AtomicReference` |
| Unique IDs (each caller must get a distinct value) | `AtomicLong.getAndIncrement()` (`LongAdder` can't hand out unique values) |
| An exact snapshot at a point in time | `AtomicLong` (`LongAdder.sum()` isn't atomic with concurrent updates) |
| Max/min watermark at scale | `LongAccumulator(Long::max, Long.MIN_VALUE)` |
| Memory per counter matters (millions of counters) | `AtomicLong` or a `VarHandle` on a `long` field (`LongAdder` can grow to N padded cells, 128+ bytes each) |

---

## 4. The ABA problem 🔥

A CAS checks only that the value **equals** the expected value, not that it **hasn't changed in between**. If a location goes A → B → A, a stale CAS succeeds.

In Java the GC prevents the classic C/C++ form (memory reuse of a freed node while someone holds a pointer to it). ABA **still happens** when nodes or values are **reused deliberately** (object pools, recycled nodes, small integer states, indexes into arrays).

### 4.1 Runnable: ABA corrupting a pooled Treiber stack, fixed with a stamp

The interleaving is simulated step by step in one thread, so it's deterministic.

<!-- run: -->
```java
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.atomic.AtomicStampedReference;

public class AbaDemo {
    static final class Node { final String v; Node next; Node(String v) { this.v = v; } public String toString() { return v; } }

    static String dump(Node n) { StringBuilder sb = new StringBuilder("["); for (; n != null; n = n.next) sb.append(n.v).append(n.next != null ? "→" : ""); return sb.append("]").toString(); }

    public static void main(String[] args) {
        Node a = new Node("A"), b = new Node("B"), c = new Node("C");
        a.next = b; b.next = c;
        AtomicReference<Node> top = new AtomicReference<>(a);                 // stack: A→B→C

        // Thread 1 begins pop(): reads top=A and next=B, then gets descheduled…
        Node t1Top = top.get(), t1Next = t1Top.next;

        // Thread 2 meanwhile: pop A, pop B, then pushes A back (A is a recycled node from a pool)
        top.set(b); top.set(c); a.next = c; top.set(a);                      // stack: A→C   (B is gone)

        // Thread 1 resumes: CAS(top, A, B) — succeeds because top == A again
        boolean ok = top.compareAndSet(t1Top, t1Next);
        System.out.println("plain CAS succeeded=" + ok + " → stack " + dump(top.get()) + "   ← popped B is back on top, pushed-back A is lost");

        // Same interleaving with a version stamp
        a.next = b; b.next = c;
        AtomicStampedReference<Node> stamped = new AtomicStampedReference<>(a, 0);
        int[] holder = new int[1];
        Node s1Top = stamped.get(holder); int s1Stamp = holder[0]; Node s1Next = s1Top.next;
        stamped.set(b, 1); stamped.set(c, 2); a.next = c; stamped.set(a, 3);  // every change bumps the stamp
        boolean ok2 = stamped.compareAndSet(s1Top, s1Next, s1Stamp, s1Stamp + 1);
        System.out.println("stamped CAS succeeded=" + ok2 + " → stack " + dump(stamped.getReference()) + " (stamp " + stamped.getStamp() + ") ← stale update rejected");
    }
}
```

Output (verified):

```
plain CAS succeeded=true → stack [B→C]   ← popped B is back on top, pushed-back A is lost
stamped CAS succeeded=false → stack [A→C] (stamp 3) ← stale update rejected
```

Thread 2 left the stack as `A→C`. Thread 1's stale CAS still saw `top == A` and installed its old `next` (B), so a node that had already been popped is back on top and A disappears. The stamped version detects that `top` changed three times in between.

**Mitigations:** don't recycle nodes in lock-free structures (let GC do it); use stamped or versioned references (`AtomicStampedReference`, or a 64-bit word packing value + version); use hazard pointers or epochs in off-heap structures (Agrona, Chronicle).

---

## 5. Building lock-free data structures ⚡

### 5.1 Progress guarantees

| Guarantee | Meaning | Example |
|---|---|---|
| **Wait-free** | Every thread completes in a bounded number of its own steps | `AtomicLong.getAndIncrement` on x86 (`XADD`) |
| **Lock-free** | Some thread always makes progress (individual threads may retry forever in theory) | Treiber stack, Michael–Scott queue (`ConcurrentLinkedQueue`) |
| **Obstruction-free** | A thread makes progress if it runs in isolation | Some STM designs |
| **Blocking** | A descheduled lock holder can stop everyone | `synchronized`, `ReentrantLock` |

Lock-freedom gives **robustness** (no convoys, no deadlock, no priority inversion), **not** automatically more speed. Contended CAS loops can be slower than a good lock, because a lock serializes without wasted retries. Measure.

### 5.2 Runnable: a Treiber stack with `VarHandle` (no node reuse, so no ABA)

<!-- run: -->
```java
import java.lang.invoke.MethodHandles;
import java.lang.invoke.VarHandle;
import java.util.concurrent.atomic.LongAdder;

public class TreiberStack<E> {
    private static final class Node<E> { final E item; Node<E> next; Node(E item) { this.item = item; } }
    private volatile Node<E> top;
    private static final VarHandle TOP;
    static {
        try { TOP = MethodHandles.lookup().findVarHandle(TreiberStack.class, "top", Node.class); }
        catch (ReflectiveOperationException e) { throw new ExceptionInInitializerError(e); }
    }

    public void push(E item) {
        Node<E> n = new Node<>(item);                     // new node each time: GC prevents ABA
        Node<E> cur;
        do { cur = top; n.next = cur; } while (!TOP.compareAndSet(this, cur, n));
    }

    public E pop() {
        Node<E> cur, next;
        do {
            cur = top;
            if (cur == null) return null;
            next = cur.next;
        } while (!TOP.compareAndSet(this, cur, next));
        return cur.item;
    }

    public static void main(String[] args) throws Exception {
        TreiberStack<Integer> s = new TreiberStack<>();
        LongAdder popped = new LongAdder(), sum = new LongAdder();
        Thread[] ts = new Thread[8];
        for (int t = 0; t < ts.length; t++) {
            int base = t * 100_000;
            ts[t] = new Thread(() -> {
                for (int i = 1; i <= 100_000; i++) {
                    s.push(base + i);
                    Integer v = s.pop();
                    if (v != null) { popped.increment(); sum.add(v); }
                }
            });
            ts[t].start();
        }
        for (Thread t : ts) t.join();
        long expectedSum = 0; for (int t = 0; t < 8; t++) for (int i = 1; i <= 100_000; i++) expectedSum += t * 100_000L + i;
        System.out.println("pushed=800000 popped=" + popped.sum() + " leftover=" + (s.pop() == null ? 0 : "≥1")
            + " sumOK=" + (sum.sum() == expectedSum));
    }
}
```

Output (verified): `pushed=800000 popped=800000 leftover=0 sumOK=true`

Each thread pushes then immediately pops, so every pop succeeds, though not necessarily with its own element. The checksum proves no element was lost or duplicated.

### 5.3 JDK lock-free structures you should use instead of writing your own

| Structure | Algorithm |
|---|---|
| `ConcurrentLinkedQueue` | Michael–Scott lock-free queue (with lazy tail updates) |
| `ConcurrentLinkedDeque` | Lock-free deque |
| `ConcurrentSkipListMap/Set` | Lock-free skip list (sorted, O(log n)) |
| `LinkedTransferQueue` | Dual-queue algorithm, lock-free: producers can hand elements directly to waiting consumers (`transfer`) |
| `ConcurrentHashMap` | CAS for empty bins plus per-bin locks ([2.1 §9](../02-Core-Java/01-Collections-Internals.md#9-concurrenthashmap-internals-jdk-8-)) |
| JCTools (`MpscArrayQueue`, `SpscArrayQueue`, …) | Specialized bounded queues: used by Netty's event loops |
| LMAX Disruptor | Ring buffer with sequence barriers, padding, single-writer principle |

---

## 6. Production failure modes & diagnostics

| Failure | Signature | Fix |
|---|---|---|
| Hot `AtomicLong` counter limits throughput | CPU high, throughput flat as cores are added; `perf c2c` shows the counter's line | `LongAdder`; per-thread or sharded counters |
| Side effects in `updateAndGet`/`accumulateAndGet` | Duplicate logs, duplicate IDs, double-sent messages under load | Pure functions; do side effects after a successful CAS |
| ABA corruption | Lost or duplicated elements in custom pooled lock-free code | Don't recycle nodes; stamped references |
| Spin loops burning CPU | Threads RUNNABLE in CAS retry loops at 100% CPU | Back-off (`Thread.onSpinWait`, then park); a lock may be better |
| `LongAdder.sum()` used for exact decisions | Rare over- or under-shoot of limits (e.g. rate limiting) | `AtomicLong` (or `Semaphore`) for exact admission control |
| False sharing between atomics in an array | `AtomicLongArray` slots used by different threads are slow | Pad (stride 16 longs) or use `LongAdder` |

---

## 7. Interview & certification Q&A

<details><summary><b>Q1. 🔥 Why does `LongAdder` outperform `AtomicLong` under contention, and when should you still use `AtomicLong`?</b></summary>

`AtomicLong` funnels every update through one cache line, so cores serialize on it and the line bounces between them (measured: throughput falls from 162M to 81M ops/s, 1→8 threads). `LongAdder` spreads updates over padded per-thread-ish cells and sums lazily (it scales to 711M ops/s). Use `AtomicLong` when you need read-modify-write semantics, unique values (`getAndIncrement` IDs), or an exact, atomic current value.
</details>

<details><summary><b>Q2. 🔥 What is the ABA problem? Does garbage collection solve it in Java?</b></summary>

A CAS succeeds because the value equals the expected one, even though it changed and changed back in between (A→B→A), so the operation acts on stale assumptions. GC solves the memory-reuse variant (a node can't be freed and reallocated while referenced), but not ABA from deliberate reuse (pooled nodes, recycled IDs, state values). Fix with version stamps (`AtomicStampedReference`) or by avoiding reuse.
</details>

<details><summary><b>Q3. ⚡ `compareAndSet` vs `weakCompareAndSet`?</b></summary>

`weakCompareAndSet` may fail **spuriously** (even if the value matched), as on LL/SC architectures, and (in its plain form) has weaker ordering. It's fine inside retry loops and can be cheaper. `compareAndSet` fails only if the value differs, and has volatile semantics.
</details>

<details><summary><b>Q4. 🎓 What does `AtomicInteger.getAndIncrement()` return vs `incrementAndGet()`?</b></summary>

`getAndIncrement` returns the **previous** value (like `i++`), and `incrementAndGet` returns the **new** value (like `++i`). Both are atomic.
</details>

<details><summary><b>Q5. ⚡ Is lock-free always faster than locking?</b></summary>

No. Lock-free guarantees system-wide progress and avoids blocking pathologies (convoys, deadlocks, a descheduled holder). Under heavy contention, CAS retry storms waste work, and a lock (which queues threads) can deliver higher throughput. Pick based on measurement and on whether robustness to blocking matters.
</details>

<details><summary><b>Q6. 🧊 What does `LongAdder.sum()` guarantee?</b></summary>

It returns base plus the sum of all cells. Without concurrent updates the result is exact. With concurrent updates it may miss in-flight increments, because it is not an atomic snapshot. That is acceptable for metrics, not for exact limits.
</details>

<details><summary><b>Q7. ⚡ Why must the function passed to `updateAndGet` be side-effect free?</b></summary>

The method retries the function whenever the CAS fails due to concurrent updates, so the function may run several times per successful update (measured: ~5 invocations per update with 8 threads in one run; the ratio varies with contention).
</details>

---

## 8. Further reading

* `java.util.concurrent.atomic` package summary; `Striped64` source comments.
* Herlihy & Shavit, *The Art of Multiprocessor Programming* (2nd ed.), chapters 10–11.
* Martin Thompson, "Lock-Free Algorithms" talks; JCTools: <https://github.com/JCTools/JCTools>
