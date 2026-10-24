# 1.3 · Object Memory Layout, Compressed Oops, Compact Headers & Mechanical Sympathy

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** HotSpot `markWord.hpp`, JEP 374 (biased locking), JEP 450/519/534 (compact object headers), JEP 390 (value-based class warnings), JEP 142 (`@Contended`), JDK-8237767 (field layout), JOL (Java Object Layout), Martin Thompson's mechanical-sympathy work, Ulrich Drepper's "What Every Programmer Should Know About Memory".
> **Measurements:** Temurin 25.0.4.1, Windows x64, 12 logical CPUs, using JOL 0.17. Timings are single runs on a laptop: indicative ratios, not benchmarks (use JMH for real numbers, see [8.5](../08-Observability-Security-Testing/05-JMH-Benchmarking.md)).

---

## 1. Why layout matters 🔥

* **Density means cache efficiency.** Memory moves in 64-byte cache lines. A `HashMap<Integer,Integer>` entry costs ~58 bytes spread over **three objects at three addresses**, while an `int[]` element costs 4 bytes contiguously. Most "Java is slow" profiles turn out to be cache-miss profiles.
* **GC cost is proportional to live objects and references**, not to bytes. Fewer, larger, reference-free objects (primitive arrays) are cheaper to mark and copy.
* **Heap size and the compressed-oops boundary**: crossing ~32 GB doubles every reference, from 4 to 8 bytes.

---

## 2. Object header anatomy 🔥

### 2.1 Legacy layout (default through JDK 26; `-XX:-UseCompactObjectHeaders`)

```
 Ordinary object (64-bit JVM, compressed class pointers ON — the default)
 ┌───────────────────────────── 8 bytes ─────────────────────────────┬──── 4 bytes ────┬── fields… ──┐
 │                         MARK WORD                                  │  KLASS (narrow) │             │
 └────────────────────────────────────────────────────────────────────┴─────────────────┴─────────────┘
   header = 12 bytes → first field at offset 12; object size rounded up to 8 (ObjectAlignmentInBytes)

 Array: mark (8) + klass (4) + length (4) = 16-byte header → elements start at offset 16
```

### 2.2 Mark word bit layout (JDK 25, 64-bit, from `markWord.hpp`)

```
 legacy:   [ unused:22 | identity hash:31 | unused_gap:4 | age:4 | self-fwd:1 | lock:2 ]
 compact:  [ narrow klass:22 | identity hash:31 | unused_gap:4 | age:4 | self-fwd:1 | lock:2 ]
              bit 63 ...                                                          ... bit 0
```

| `lock` bits | State | Meaning |
|---|---|---|
| `01` | **Unlocked** (neutral) | Hash and age bits valid |
| `00` | **Lightweight-locked** | Owner recorded in the owning thread's **lock-stack** (JDK 21+ lightweight locking, default since 23). The header is *not* displaced |
| `10` | **Inflated** (monitor) | Legacy: the header is a pointer to the `ObjectMonitor`. With compact headers, the monitor is found through a side table (`UseObjectMonitorTable`) |
| `11` | **Marked** | Used by GC (forwarding pointers during copying) |

* `age:4` is the GC age, which is why `MaxTenuringThreshold ≤ 15`.
* `self-fwd:1` marks objects that failed evacuation and were "forwarded to themselves" (G1 evacuation failure / promotion failure).
* `unused_gap:4` is reserved for Project Valhalla.
* **Biased locking** (bit patterns `101`) is **gone**. It was deprecated in JDK 15 (JEP 374) and removed in JDK 18. Revocation required safepoints, and uncontended CAS had become cheap on modern CPUs.

### 2.3 Runnable: watching the mark word change

<!-- run: cp=jol jvm="-XX:-UseCompactObjectHeaders" -->
```java
import org.openjdk.jol.info.ClassLayout;

public class MarkWord {
    static String mark(Object o) {
        for (String line : ClassLayout.parseInstance(o).toPrintable().split("\n"))
            if (line.contains("(object header: mark)")) return line.replaceAll("^.*mark\\)\\s+", "").trim();
        return "?";
    }

    public static void main(String[] args) throws Exception {
        Object o = new Object();
        System.out.println("fresh         : " + mark(o));
        synchronized (o) { System.out.println("locked (thin) : " + mark(o)); }
        System.out.println("unlocked      : " + mark(o));
        int h = System.identityHashCode(o);
        System.out.printf("after hash    : %s   identityHashCode=0x%x%n", mark(o), h);

        Object c = new Object();
        Thread holder = new Thread(() -> { synchronized (c) { sleep(300); } });
        holder.start(); sleep(50);
        Thread contender = new Thread(() -> { synchronized (c) { } });   // blocks → forces inflation
        contender.start(); sleep(100);
        System.out.println("contended     : " + mark(c));
        holder.join(); contender.join();
    }
    static void sleep(long ms) { try { Thread.sleep(ms); } catch (InterruptedException e) { throw new RuntimeException(e); } }
}
```

Output (verified; addresses and hash values differ per run):

```
-XX:-UseCompactObjectHeaders (legacy)
fresh         : 0x0000000000000001 (non-biasable; age: 0)
locked (thin) : 0x0000000000000000 (thin lock: 0x0000000000000000)
unlocked      : 0x0000000000000001 (non-biasable; age: 0)
after hash    : 0x000000f3378fa801 (hash: 0xf3378fa8; age: 0)   identityHashCode=0x1e66f1f5
contended     : 0x000001911cc5e3a2 (fat lock: 0x000001911cc5e3a2)

-XX:+UseCompactObjectHeaders
fresh         : 0x0018340000000001 (Lilliput)          ← upper 22 bits = narrow klass
locked (thin) : 0x0018340000000000 (Lilliput)          ← only the lock bits changed: 01 → 00
after hash    : 0x001836c54bb06801 (Lilliput)   identityHashCode=0x58a9760d
contended     : 0x00183582f443d802 (Lilliput)          ← lock bits 10 = inflated
```

**Decoding it yourself** (and a tooling trap): JOL 0.17 prints `hash: 0xf3378fa8`, but the real identity hash is `0x1e66f1f5`. On JDK 25 the hash field starts at **bit 11** (2 lock + 1 self-fwd + 4 age + 4 gap), and JOL's decoder assumes the older bit 8. Check: `(0x000000f3378fa801 >>> 11) & 0x7FFFFFFF = 0x1e66f1f5`. Lesson: tools that hard-code header layouts break across JDK versions. So does any `Unsafe` code that assumes header sizes or array base offsets.

### 2.4 Identity hash code facts 🔥

* Generated **lazily** on the first `System.identityHashCode`/non-overridden `Object.hashCode()`, then stored in the header, so it is stable even though GC moves the object.
* Default algorithm (`-XX:hashCode=5`): a thread-local Marsaglia xor-shift random number. It is **not a memory address**, and has not been on HotSpot for a long time.
* 31 bits, so collisions are expected. It is never unique.
* Locking on a hashed object is fine with lightweight locking. The old "hash + biased locking forces revocation" problem died with biased locking.
* **Don't synchronize on value-based classes** (`Integer`, `Long`, `Optional`, `LocalDate`, records you treat as values). Identity is not guaranteed, caches share instances (`Integer.valueOf(1)` is a JVM-wide singleton), and future Valhalla value classes will reject it. Detect with `-XX:DiagnoseSyncOnValueBasedClasses=1` (fatal error) or `=2` (log), per JEP 390.

### 2.5 Compact object headers (JEP 450 → 519 → 534) ⚡

| | Legacy | Compact |
|---|---|---|
| Header size | 12 B (mark 8 + narrow klass 4) | **8 B** (klass folded into the mark word) |
| Narrow klass bits | 32 | **22** (class space addressing via larger shift; JOL reports "10-bit shift") |
| `new Object()` | 16 B | **8 B** |
| `int[]` elements start at | 16 | **12** |
| `long[]` elements start at | 16 | 16 (8-byte alignment) |
| Monitor lookup when inflated | Pointer in mark word | **Side table** (`UseObjectMonitorTable=true` automatically) |
| Status | Default ≤ 26 | Experimental 24, **product 25 (opt-in)**, **default 27** |

**Real JOL layouts (JDK 25):**

| Class | Legacy size | Compact size | Why |
|---|---|---|---|
| `java.lang.Object` | 16 | **8** | 12-byte header padded to 16 → 8-byte header, no fields |
| `java.lang.Integer` | 16 | 16 | 12+4 = 16 → 8+4 = 12, padded to 16. **No gain** |
| `java.lang.Long` | 24 | **16** | 12 + (4 gap) + 8 = 24 → 8 + 8 = 16 |
| `java.lang.Boolean` | 16 | 16 | 12+1 → 13 → 16; 8+1 → 9 → 16 |
| `java.lang.String` | 24 | 24 | hash(4) coder(1) hashIsZero(1) value-ref(4): 12+10 → 24; 8+10 → 18 → 24 |
| `HashMap.Node` | 32 | **24** | hash(4) + key/value/next refs(12): 12+16 = 28 → 32; 8+16 = 24 |

> **Gains are workload-specific**: objects whose `12 + fields` lands just past an 8-byte boundary gain the most, while `Integer`-like objects gain nothing. JEP 519 reports 10–20% live-set reductions on object-heavy workloads. Measure your own with `GC.class_histogram` or JOL.

---

## 3. Field layout rules 🔥

Since JDK 15 (JDK-8237767) HotSpot lays out fields as follows:

1. **Superclass fields first.** A subclass never interleaves with its superclass's fields, but it *may fill gaps the superclass left* (for example, a 4-byte hole after the 12-byte header).
2. Within a class, fields are placed **largest primitives first** (`long`/`double` → `int`/`float` → `short`/`char` → `byte`/`boolean`) and then **references** (oops grouped together helps GC scanning), filling alignment gaps greedily.
3. **Declaration order does not matter.** You cannot "pack" fields by reordering source code.
4. `@Contended` fields or groups are isolated with 128 bytes of padding (`ContendedPaddingWidth`).

<!-- run: cp=jol -->
```java
import org.openjdk.jol.info.ClassLayout;

public class FieldLayout {
    static class Order {                       // declaration order: deliberately "bad"
        boolean active;
        long id;
        byte status;
        Object customer;
        int quantity;
        short region;
    }
    static class PriorityOrder extends Order { // subclass may fill superclass gaps
        byte priority;
    }

    public static void main(String[] args) {
        System.out.println(ClassLayout.parseClass(Order.class).toPrintable());
        System.out.println(ClassLayout.parseClass(PriorityOrder.class).toPrintable());
    }
}
```

Output (verified, legacy headers):

```
FieldLayout$Order object internals:
OFF  SZ               TYPE DESCRIPTION               VALUE
  0   8                    (object header: mark)     N/A
  8   4                    (object header: class)    N/A
 12   4                int Order.quantity            N/A      ← int fills the 4-byte gap after the header
 16   8               long Order.id                  N/A
 24   2              short Order.region              N/A
 26   1            boolean Order.active              N/A
 27   1               byte Order.status              N/A
 28   4   java.lang.Object Order.customer            N/A      ← references last
Instance size: 32 bytes
Space losses: 0 bytes internal + 0 bytes external = 0 bytes total

FieldLayout$PriorityOrder object internals:
OFF  SZ               TYPE DESCRIPTION               VALUE
  0   8                    (object header: mark)     N/A
  8   4                    (object header: class)    N/A
 12   4                int Order.quantity            N/A
 16   8               long Order.id                  N/A
 24   2              short Order.region              N/A
 26   1            boolean Order.active              N/A
 27   1               byte Order.status              N/A
 28   4   java.lang.Object Order.customer            N/A
 32   1               byte PriorityOrder.priority    N/A
 33   7                    (object alignment gap)
Instance size: 40 bytes
Space losses: 0 bytes internal + 7 bytes external = 7 bytes total
```

Adding a single `byte` in the subclass costs **8 bytes** per instance, because the superclass had no gap. Multiply by 50M entity objects and that is 400 MB. This is the kind of thing `jcmd GC.class_histogram` reveals.

---

## 4. Compressed oops and the 32 GB cliff 🔥

### 4.1 Encoding

```
narrow oop (32-bit) ──► address = heap_base + (narrow << 3)        (shift = log2(ObjectAlignmentInBytes) = 3)
2^32 × 8 bytes = 32 GB of addressable heap with 4-byte references
```

| Mode | Condition | Decode cost |
|---|---|---|
| **Unscaled** (32-bit) | Heap ends below 4 GB | `address = narrow` |
| **Zero-based** | Heap ends below 32 GB | `address = narrow << 3` |
| **Non-zero based** (`Non-zero disjoint base` on this Windows box at `-Xmx31g`) | Heap can't be placed low enough | `address = base + (narrow << 3)` (disjoint base: OR instead of ADD) |
| **Disabled** | `-Xmx` ≥ 32 GB (with 8-byte alignment) | 8-byte references |

Real output (JDK 25):

```
$ java -Xmx31g -Xlog:gc+init -version | grep Oops
[0.016s][info][gc,init] Compressed Oops: Enabled (Non-zero disjoint base)
$ java -Xmx32g -Xlog:gc+init -version | grep Oops
[0.015s][info][gc,init] Compressed Oops: Disabled
```

### 4.2 Consequences

* A heap of **32–40 GB often holds *less* live data than one of ~31 GB**, because every reference field, every `Object[]` slot and every array-of-reference grows from 4 to 8 bytes. Move from 31 GB to **≥ 48 GB**, or stay under 32.
* `-XX:ObjectAlignmentInBytes=16` extends compressed oops to 64 GB, at the cost of more padding per object (average +4 bytes). It is rarely worth it.
* **ZGC never uses compressed oops**: its colored pointers need 64-bit references. Reference-heavy heaps are therefore noticeably larger under ZGC (often tens of percent for object-graph-heavy workloads). Size ZGC heaps from **measured** live sets, not by copying the G1 `-Xmx`.
* Compressed **class** pointers (`UseCompressedClassPointers`) are independent and remain on regardless of heap size.

---

## 5. What collections really cost (JOL `GraphLayout`, 100k entries) 🔥

<!-- run: cp=jol jvm="-Xmx512m" -->
```java
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import org.openjdk.jol.info.GraphLayout;

public class Footprint {
    static void show(String name, Object o, int n) {
        long bytes = GraphLayout.parseInstance(o).totalSize();   // follows all references (keys/values included)
        System.out.printf("%-40s %,12d bytes  (%5.1f B/elem)%n", name, bytes, (double) bytes / n);
    }

    public static void main(String[] args) {
        int n = 100_000;
        int[] prim = new int[n];
        var al = new ArrayList<Integer>(); var ll = new LinkedList<Integer>(); var ad = new ArrayDeque<Integer>();
        var hm = new HashMap<Integer, Integer>(); var lhm = new LinkedHashMap<Integer, Integer>();
        var tm = new TreeMap<Integer, Integer>(); var chm = new ConcurrentHashMap<Integer, Integer>();
        for (int i = 0; i < n; i++) {
            Integer k = 1_000 + i;                                    // outside the Integer cache (-128..127)
            prim[i] = k; al.add(k); ll.add(k); ad.add(k); hm.put(k, k); lhm.put(k, k); tm.put(k, k); chm.put(k, k);
        }
        show("int[100k]", prim, n);
        show("ArrayList<Integer>", al, n);
        show("ArrayDeque<Integer>", ad, n);
        show("LinkedList<Integer>", ll, n);
        show("HashMap<Integer,Integer>", hm, n);
        show("LinkedHashMap<Integer,Integer>", lhm, n);
        show("TreeMap<Integer,Integer>", tm, n);
        show("ConcurrentHashMap<Integer,Integer>", chm, n);
    }
}
```

Measured (JDK 25, both header modes):

| Structure (100k elements) | Legacy headers | Compact headers | vs `int[]` |
|---|---|---|---|
| `int[]` | 400 KB (4.0 B/elem) | 400 KB | 1× |
| `ArrayList<Integer>` | 2.03 MB (20.3 B) | 2.03 MB | **5×** |
| `ArrayDeque<Integer>` | 2.03 MB (20.3 B) | 2.03 MB | 5× |
| `LinkedList<Integer>` | 4.00 MB (40.0 B) | 4.00 MB | 10× |
| `HashMap<Integer,Integer>` (= `HashSet` + 32 B) | 5.85 MB (58.5 B) | 5.05 MB (50.5 B) | **14.6×** |
| `LinkedHashMap<Integer,Integer>` | 6.65 MB (66.5 B) | 5.85 MB (58.5 B) | 16.6× |
| `TreeMap<Integer,Integer>` | 5.60 MB (56.0 B) | 4.80 MB (48.0 B) | 14× |
| `ConcurrentHashMap<Integer,Integer>` | 5.85 MB (58.5 B) | 5.05 MB (50.5 B) | 14.6× |
| `String "hello"` (Latin-1, compact strings) | 48 B (24 String + 24 `byte[]`) | 48 B | — |

**Where the bytes go for one `HashMap<Integer,Integer>` entry (legacy):** `Node` 32 B + key `Integer` 16 B + value `Integer` 16 B (shared here, since key and value are the same object) + table slot 4 B × (1/0.75 load factor, rounded up to a power of two) ≈ 58 B. Primitive-specialized maps (fastutil `Int2IntOpenHashMap`, Eclipse Collections, HPPC, Agrona) store this in ~**8–16 B/entry** in two parallel `int[]` arrays.

---

## 6. Mechanical sympathy: the memory hierarchy 🔥

### 6.1 Latency numbers you should carry around (order of magnitude, modern x86 server)

| Level | Size (per core / shared) | Latency | In 3 GHz cycles |
|---|---|---|---|
| Register | — | ~0.3 ns | 1 |
| L1d cache | 32–48 KB per core | ~1 ns | ~4–5 |
| L2 cache | 1–2 MB per core | ~3–5 ns | ~12–15 |
| L3 (LLC) | 16–100+ MB shared | ~10–20 ns | ~40–70 |
| DRAM (local NUMA node) | GBs | ~60–100 ns | ~200–300 |
| DRAM (remote NUMA node) | | ~1.3–2× local | |
| Cache line | **64 B** (x86, most ARM servers incl. Graviton); **128 B** on Apple M-series | | |
| Page / TLB | 4 KB pages (2 MB / 1 GB huge pages) | TLB miss ≈ extra page-walk | |

Two rules fall out of this table:

1. **Sequential access is nearly free**, because hardware prefetchers stream cache lines ahead of you.
2. **Pointer chasing is expensive.** Each dependent load that misses costs ~100 ns, and the CPU cannot overlap dependent misses.

### 6.2 Runnable: locality, measured

<!-- run: jvm="-Xms1g -Xmx1g" timeout=120 -->
```java
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedList;
import java.util.List;
import java.util.Random;

public class Locality {
    static final int N = 1 << 24;                       // 16M ints = 64 MB, far bigger than L3
    static long sink;

    static long bestOf5(Runnable r) {
        long best = Long.MAX_VALUE;
        for (int i = 0; i < 5; i++) { long s = System.nanoTime(); r.run(); best = Math.min(best, System.nanoTime() - s); }
        return best / 1_000_000;
    }

    public static void main(String[] args) {
        int[] data = new int[N], seqIdx = new int[N], rndIdx = new int[N];
        for (int i = 0; i < N; i++) { data[i] = i; seqIdx[i] = i; rndIdx[i] = i; }
        Random r = new Random(1);
        for (int i = N - 1; i > 0; i--) { int j = r.nextInt(i + 1); int t = rndIdx[i]; rndIdx[i] = rndIdx[j]; rndIdx[j] = t; }

        System.out.printf("%-40s %4d ms%n", "int[] gather, sequential indices", bestOf5(() -> { long s = 0; for (int i = 0; i < N; i++) s += data[seqIdx[i]]; sink += s; }));
        System.out.printf("%-40s %4d ms%n", "int[] gather, random indices", bestOf5(() -> { long s = 0; for (int i = 0; i < N; i++) s += data[rndIdx[i]]; sink += s; }));

        int rows = 4096, cols = 4096;
        int[][] grid = new int[rows][cols];
        System.out.printf("%-40s %4d ms%n", "2D row-major", bestOf5(() -> { long s = 0; for (int i = 0; i < rows; i++) for (int j = 0; j < cols; j++) s += grid[i][j]; sink += s; }));
        System.out.printf("%-40s %4d ms%n", "2D column-major", bestOf5(() -> { long s = 0; for (int j = 0; j < cols; j++) for (int i = 0; i < rows; i++) s += grid[i][j]; sink += s; }));

        int m = 2_000_000;
        int[] prim = new int[m];
        List<Integer> boxed = new ArrayList<>(m);
        for (int i = 0; i < m; i++) { prim[i] = i; boxed.add(i); }
        List<Integer> shuffled = new ArrayList<>(boxed);
        Collections.shuffle(shuffled, new Random(2));        // same Integer objects, references in random heap order
        LinkedList<Integer> linked = new LinkedList<>(boxed);
        System.out.printf("%-40s %4d ms%n", "sum int[2M]", bestOf5(() -> { long s = 0; for (int v : prim) s += v; sink += s; }));
        System.out.printf("%-40s %4d ms%n", "sum ArrayList<Integer> (alloc order)", bestOf5(() -> { long s = 0; for (Integer v : boxed) s += v; sink += s; }));
        System.out.printf("%-40s %4d ms%n", "sum ArrayList<Integer> (shuffled refs)", bestOf5(() -> { long s = 0; for (Integer v : shuffled) s += v; sink += s; }));
        System.out.printf("%-40s %4d ms%n", "sum LinkedList<Integer>", bestOf5(() -> { long s = 0; for (Integer v : linked) s += v; sink += s; }));
        if (sink == 42) System.out.println();
    }
}
```

One run (JDK 25, laptop):

```
int[] gather, sequential indices            7 ms
int[] gather, random indices              134 ms     ← 19× slower: every access is a cache miss
2D row-major                                4 ms
2D column-major                           182 ms     ← 45× slower: each step jumps to another int[] row
sum int[2M]                                 0 ms     ← C2 vectorizes it (SIMD)
sum ArrayList<Integer> (alloc order)        2 ms     ← Integers were allocated contiguously, so the prefetcher helps
sum ArrayList<Integer> (shuffled refs)     14 ms     ← same objects, random order: 7× slower
sum LinkedList<Integer>                     4 ms     ← nodes happen to be adjacent in the TLAB; after GC/churn this degrades
```

**Interpretation:**

* The *same data* with a *different access order* differs by 19–45×. Algorithms with identical Big-O can be orders of magnitude apart.
* Boxed collections are only "okay" while allocation order happens to match iteration order. In long-running services, objects get scattered across regions by allocation interleaving between threads, so the shuffled-refs number is the realistic one.
* A Java `int[][]` is an **array of arrays** (separate row objects), not a contiguous matrix. Use a flat `int[rows*cols]` with `i*cols+j` indexing for numeric work.

### 6.3 False sharing 🔥

**MESI** (and MOESI/MESIF) coherence works at **cache-line** granularity. When core A writes field `a` and core B writes field `b`, and both fields share a 64-byte line, the line ping-pongs between the cores' caches: each write invalidates the other core's copy. No data is shared, but the performance is that of heavy contention.

<!-- run: nosource jvm="-XX:-RestrictContended --add-exports java.base/jdk.internal.vm.annotation=ALL-UNNAMED" timeout=120 -->
```java
import jdk.internal.vm.annotation.Contended;

public class FalseSharing {
    static final long ITERS = 100_000_000L;

    static final class Adjacent { volatile long a; volatile long b; }                 // same 64-byte line
    static class PadA { volatile long a; long p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12, p13, p14, p15; }
    static final class Padded extends PadA { volatile long b; }                      // superclass fields come first
    static final class ContendedPair { @Contended volatile long a; @Contended volatile long b; }

    interface Bump { void a(); void b(); }

    static long run(Bump bump) throws InterruptedException {
        Thread t1 = new Thread(() -> { for (long i = 0; i < ITERS; i++) bump.a(); });
        Thread t2 = new Thread(() -> { for (long i = 0; i < ITERS; i++) bump.b(); });
        long start = System.nanoTime();
        t1.start(); t2.start(); t1.join(); t2.join();
        return (System.nanoTime() - start) / 1_000_000;
    }

    public static void main(String[] args) throws Exception {
        var adj = new Adjacent(); var pad = new Padded(); var con = new ContendedPair();
        for (int round = 0; round < 2; round++) {                // round 0 = warm-up
            long t1 = run(new Bump() { public void a() { adj.a++; } public void b() { adj.b++; } });
            long t2 = run(new Bump() { public void a() { pad.a++; } public void b() { pad.b++; } });
            long t3 = run(new Bump() { public void a() { con.a++; } public void b() { con.b++; } });
            if (round == 1) System.out.printf("adjacent fields: %5d ms%nmanual padding:  %5d ms%n@Contended:      %5d ms%n", t1, t2, t3);
        }
    }
}
```

One run (2 threads × 100M volatile increments each):

```
adjacent fields:  2349 ms
manual padding:    693 ms     ← 3.4× faster with zero code-logic change
@Contended:        685 ms
```

JOL confirms the layouts:

```
FalseSharing$Adjacent:       a @16, b @24                → same line. Instance size: 32 bytes
FalseSharing$Padded:         a @16, p1..p15, b @144      → 128 bytes apart. Instance size: 152 bytes
FalseSharing$ContendedPair:  a @144, b @280              → 128 B padding around each. Instance size: 416 bytes
```

**`@Contended` facts:**

* Annotation: `jdk.internal.vm.annotation.Contended` (internal). It is **ignored outside the JDK** unless you pass `-XX:-RestrictContended`, and compiling against it needs `--add-exports java.base/jdk.internal.vm.annotation=ALL-UNNAMED`.
* Padding = `ContendedPaddingWidth` = **128 bytes**. That covers adjacent-line prefetching (Intel's spatial prefetcher pulls line pairs) and 128-byte-line CPUs.
* The JDK uses it in `Thread` (ThreadLocalRandom fields), `Striped64.Cell` (`LongAdder`), `ConcurrentHashMap.CounterCell`, `ForkJoinPool.WorkQueue`, and `Exchanger`.
* Libraries outside the JDK use **hierarchy padding** like `PadA` above (LMAX Disruptor, JCTools, Agrona). Since the field-layout changes, padding fields declared in the *same class* can be reordered around your hot field. Padding via **superclass/subclass layers** is robust because superclass fields always come first.

**Where false sharing bites in real services:**

* Per-thread counters stored in a `long[]` indexed by thread id (adjacent slots, same line). Use `LongAdder`, or space the slots 16 longs apart.
* Hot `volatile` fields of a shared object next to each other: queue `head`/`tail` indices, `AtomicLong`s allocated back-to-back (consecutive allocations land adjacent in the TLAB).
* Card-table writes: GC write barriers mark one byte per 512-byte heap card, and multiple threads updating references in nearby objects contend on card bytes. Parallel/Serial GC have `-XX:+UseCondCardMark` (check before writing); G1's barrier already filters.

**How to detect it:** Linux `perf c2c record/report` (HITM, "hit modified" lines), `perf stat -e LLC-load-misses`, async-profiler `-e cache-misses`. The symptom is CPU-bound threads whose throughput *drops* as you add cores.

### 6.4 Other mechanical-sympathy levers ⚡

| Lever | Effect | Java knob |
|---|---|---|
| Huge pages | Fewer TLB misses for big heaps | `-XX:+UseTransparentHugePages` (Linux THP in `madvise` mode) or `-XX:+UseLargePages` (hugetlbfs) |
| Pre-touch | No page-fault latency during warm-up/GC | `-XX:+AlwaysPreTouch` (slower startup) |
| NUMA | Allocate young objects on the local node | `-XX:+UseNUMA` (Parallel, G1 since JDK 14 / JEP 345, ZGC) |
| Branch predictability | Sorted data is faster in branchy loops | C2 may use `cmov`, so results vary. Measure with JMH |
| SIMD | 4–16× for numeric loops | Auto-vectorization (C2 SuperWord), or the Vector API (incubator through JDK 27) |
| Data-oriented layout | Struct-of-arrays beats array-of-structs for column scans | Parallel primitive arrays, FFM segments, or Valhalla value classes in the future |
| Single-writer principle | Avoid write contention entirely | One thread owns a datum and others read it (Disruptor, Agrona) |
| Batching | Amortize per-message costs (syscalls, cache misses) | Batched queue drains, Kafka producer `linger.ms`/`batch.size` |

> **Valhalla note (Oct 2026):** JEP 401 (*Value Classes and Objects*, preview) is still in early-access builds, not in mainline JDK 27. When it lands, value objects without identity can be **flattened** into arrays and fields (no header, no pointer), which fixes the `ArrayList<Integer>`/`Point[]` density problem at the language level.

---

## 7. Production failure modes & diagnostic checklist (layout and mechanical sympathy)

| Symptom | Likely cause | Diagnose | Fix |
|---|---|---|---|
| Heap is 3–10× larger than "the data" | Boxed collections, `HashMap` per entity, `String` per small value | `jcmd <pid> GC.class_histogram \| head -30` (look at `java.util.HashMap$Node`, `java.lang.Integer`, `[B`), MAT retained sizes | Primitive collections, arrays, enums/bitsets, compact encodings, interning of repeated values (with care) |
| Raised `-Xmx` from 30 GB to 34 GB and got *more* GC pressure | Compressed oops disabled at ≥ 32 GB | `-Xlog:gc+init` shows `Compressed Oops: Disabled` | Stay < 32 GB or jump to ≥ 48 GB |
| Migrated G1 → ZGC and the heap is too small / allocation stalls | No compressed oops in ZGC plus GC headroom needs | GC logs (`Allocation Stall`), JFR `jdk.ZAllocationStall` | Re-size from the measured live set; leave 2–3× headroom |
| Adding threads makes a CPU-bound component slower | False sharing / contended atomics | `perf c2c`, JFR lock profiles, async-profiler cache-misses | Padding / `@Contended` / `LongAdder` / per-thread state |
| Library crashes or returns garbage after enabling compact headers or upgrading the JDK | Hard-coded header or array-offset assumptions (`Unsafe`), old JOL/agent | Reproduce with `-XX:-UseCompactObjectHeaders` | Upgrade the library; use `Unsafe.ARRAY_*_BASE_OFFSET`/VarHandles/FFM instead of constants |
| Deadlock or "lock not held" weirdness on `Integer`/`String` monitors | Synchronizing on cached/interned shared instances | `-XX:DiagnoseSyncOnValueBasedClasses=2` | Lock on a private `final Object` or a `ReentrantLock` |
| Latency spikes at startup or after scaling out | Page faults on first touch of heap pages | GC logs show long first GCs; `perf` page-fault counts | `-XX:+AlwaysPreTouch`, warm-up traffic |

**Tool belt:**

```bash
java -jar jol-cli.jar internals -cp app.jar com.acme.Order      # per-class layout
java -jar jol-cli.jar footprint -cp app.jar com.acme.Cache      # graph footprint of an instance (needs a factory)
jcmd <pid> GC.class_histogram                                    # live instances + bytes per class (forces full GC!)
java -Xlog:gc+init -version                                      # compressed oops mode, region size, etc.
perf c2c record -p <pid> -- sleep 10 && perf c2c report          # false sharing (Linux)
```

> ⚠️ `GC.class_histogram` (and `jmap -histo:live`) triggers a **full GC**. On a 30 GB G1 heap that can be a multi-second pause, so use it on canaries or during low traffic. The `-all` option skips the GC but includes dead objects.

---

## 8. Interview Q&A

<details><summary><b>Q1. 🔥 How big is `new Object()`, `new Integer(5)`, `new Long(5)` and an empty `int[]` on a 64-bit JVM with default settings (JDK 25)? And with compact headers?</b></summary>

Defaults (compressed oops and class pointers, 12-byte header): Object 16 B (12 + 4 padding), Integer 16 B (12 + 4), Long 24 B (12 + 4 gap + 8), `int[0]` 16 B (12 + 4-byte length). With `-XX:+UseCompactObjectHeaders` (8-byte header): Object 8 B, Integer 16 B (8 + 4 + 4 padding), Long 16 B, and `int[]` data starts at offset 12.
</details>

<details><summary><b>Q2. 🔥 What is in the mark word, and what are the lock states in JDK 21+?</b></summary>

Identity hash (31 bits, lazily computed), GC age (4 bits), a self-forwarded bit, 4 bits reserved for Valhalla, and 2 lock bits: 01 unlocked, 00 lightweight-locked (owner tracked on the thread's lock-stack; the header is not displaced), 10 inflated monitor, 11 GC-marked/forwarded. With compact headers, the upper 22 bits also hold the narrow klass pointer. Biased locking no longer exists (removed in JDK 18).
</details>

<details><summary><b>Q3. 🔥 Explain compressed oops and why a 32 GB heap can be worse than 31 GB.</b></summary>

References are stored as 32-bit offsets scaled by the 8-byte object alignment, which covers 32 GB. At `-Xmx` ≥ 32 GB the JVM must use 64-bit references, so every reference field and array slot doubles in size. A reference-heavy heap's live set grows substantially, often making a 32–40 GB heap hold less than 31 GB did. Options: stay under 32 GB, go well above it (≥ 48 GB), or use `ObjectAlignmentInBytes=16` for up to 64 GB at a padding cost.
</details>

<details><summary><b>Q4. ⚡ Does field declaration order affect object size in HotSpot?</b></summary>

No. HotSpot reorders fields: superclass fields first, then larger primitives first, filling gaps, with references grouped. You cannot pack fields by reordering source. Inheritance does matter, though: each class's fields start after its superclass's fields, which is also why hierarchy-based padding against false sharing works.
</details>

<details><summary><b>Q5. 🔥 What is false sharing, how do you detect it, and how does the JDK avoid it in `LongAdder`?</b></summary>

Independent variables written by different cores that sit on the same cache line make the line bounce between cores under the coherence protocol, serializing the writes. Detect it with `perf c2c` (HITM), or with the symptom that throughput falls as cores are added. `LongAdder` spreads updates across `Striped64.Cell` objects annotated with `@Contended`, which get 128 bytes of padding so each cell sits on its own line pair.
</details>

<details><summary><b>Q6. ⚡ Why doesn't ZGC support compressed oops, and what does that imply for sizing?</b></summary>

ZGC stores GC metadata ("colors": remapped/marked/remembered state) in reference bits and needs a 64-bit pointer format for its load/store barriers and concurrent relocation. References are always 8 bytes, so the same application has a larger live set under ZGC than under G1 with compressed oops. ZGC also needs headroom to avoid allocation stalls. Measure and re-size rather than copying the G1 `-Xmx`.
</details>

<details><summary><b>Q7. ⚡ What are compact object headers, what do they save, and what changes behaviourally?</b></summary>

They are 8-byte headers that merge a 22-bit narrow klass pointer into the mark word (JEP 519 product in 25, default in 27 via JEP 534). They save 4 bytes on every object, and 8 bytes for objects that previously spilled into a new 8-byte alignment unit (Long: 24 → 16, HashMap.Node: 32 → 24). Inflated monitors are found through a side table (`UseObjectMonitorTable`) instead of a header pointer. The number of loadable classes is limited by the 22-bit klass encoding (millions, so rarely an issue), and code that hard-codes header sizes or array base offsets breaks.
</details>

<details><summary><b>Q8. 🧊 Is `System.identityHashCode` an address? Can two live objects share one?</b></summary>

It is not an address. By default it is a per-thread xor-shift pseudo-random number, stored in the header on first use so it survives GC moves. It has 31 bits, so collisions between live objects are possible and must be expected. Never use it as a unique id.
</details>

<details><summary><b>Q9. 🔥 Why is iterating an `ArrayList<Integer>` slower than an `int[]`, beyond boxing instructions?</b></summary>

Each element is a reference to a separate 16-byte `Integer` object. Iteration does a dependent load per element (reference, then value), the objects may be scattered across the heap (cache and TLB misses), the `int[]` loop can be vectorized by C2 while the boxed loop can't, and the boxed version uses 5× more memory bandwidth. In the measured demo, shuffled boxed references were ~7× slower than allocation-ordered ones and far slower than `int[]`.
</details>

<details><summary><b>Q10. 🧊 What does `-XX:DiagnoseSyncOnValueBasedClasses` catch, and why does it matter for the future?</b></summary>

`synchronized` on instances of value-based classes (`Integer`, `Optional`, `LocalDateTime`, …). Their identity is not guaranteed (caches share instances, so unrelated code could contend or deadlock on the same lock), and under Project Valhalla such classes may become value classes without identity, where synchronization will fail. Mode 1 is a fatal error at the offending sync; mode 2 logs a warning.
</details>

---

## 9. Further reading

* Aleksey Shipilëv, "Java Objects Inside Out": <https://shipilev.net/jvm/objects-inside-out/>
* JEP 450/519/534 (Compact Object Headers), Roman Kennke's Lilliput talks.
* JOL samples: <https://github.com/openjdk/jol/tree/master/jol-samples>
* Martin Thompson, "False Sharing" and "Mechanical Sympathy" talks. LMAX Disruptor technical paper.
* Ulrich Drepper, "What Every Programmer Should Know About Memory" (2007, still the reference).
