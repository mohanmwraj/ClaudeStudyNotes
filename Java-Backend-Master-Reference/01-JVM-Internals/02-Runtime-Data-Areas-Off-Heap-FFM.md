# 1.2 · Runtime Data Areas, Native Memory, Direct Buffers & the FFM API (Project Panama)

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut · 🎓 exam
> **Specs and sources:** JVMS §2.5 (Run-Time Data Areas), JEP 122 (Remove PermGen), JEP 387 (Elastic Metaspace), JEP 197 (Segmented Code Cache), JEP 454 (FFM API, final in 22), JEP 472 (Restrict JNI), JEP 471/498 (Unsafe memory access deprecation), HotSpot NMT docs.
> **All numbers and outputs in this file were captured on Temurin 25.0.4.1 (Windows x64, 12 CPUs, 16 GB)** unless stated otherwise.

---

## 1. The JVMS model vs what HotSpot actually allocates 🔥

| JVMS run-time data area (§2.5) | Scope | HotSpot implementation | Where the bytes live | Typical failure |
|---|---|---|---|---|
| **pc register** | Per thread | Interpreter: `bcp` register; compiled code: native PC | CPU register / frame | — |
| **JVM stack** | Per thread | **One native stack per platform thread** holds Java frames *and* native frames ("mixed stacks") | Native memory (reserved `-Xss`, committed on touch) | `StackOverflowError`; `OOM: unable to create native thread` |
| **Native method stack** | Per thread | Same stack as above | Native | Same |
| **Heap** | Shared | GC-managed spaces (G1 regions / ZGC pages / Parallel generations) | Reserved `mmap` of `-Xmx`, committed as it grows | `OOM: Java heap space` |
| **Method area** | Shared | **Metaspace** (`InstanceKlass`, `Method`, bytecode, constant pools) + **Compressed Class Space** (`Klass` only) | Native memory | `OOM: Metaspace`, `OOM: Compressed class space` |
| **Run-time constant pool** | Per class | `ConstantPool` + `ConstantPoolCache` in Metaspace; resolved Strings point to heap | Metaspace + heap | — |
| *(not in JVMS)* | Shared | **Code cache** (JIT output), **GC data structures**, **symbol table**, **string table**, **thread structures**, **NMT**, **arena chunks**, **direct buffers**, **mapped files**, **FFM segments** | Native memory | `CodeCache is full`; container OOMKill |

Two things changed in JDK 8 that many interview answers still get wrong:

* **PermGen is gone** (JEP 122). Class metadata lives in **Metaspace** (native). Interned strings and static fields had already moved to the **heap** in JDK 7. Static fields live in the `java.lang.Class` mirror object.
* Method-area GC still exists: classes unload when their loader dies (see [1.1](01-ClassLoading-Linking-JPMS.md#7-class-unloading-and-loader-leaks-)).

---

## 2. What a JVM process's memory actually is (RSS ≠ heap) 🔥

```
 RSS of a JVM ≈  committed Java heap
               + Metaspace (non-class) + Compressed class space
               + Code cache
               + Thread stacks (committed pages only) × #threads
               + GC structures (card table, remembered sets, mark bitmaps, ZGC forwarding tables)
               + Symbol table, string table (table itself; strings are on heap), interned symbols
               + Compiler arenas (C1/C2 working memory; spikes during compilation)
               + Direct ByteBuffers + mapped files (page cache pages that are resident) + FFM allocations
               + malloc by JNI/native libraries (Netty native, compression codecs, RocksDB, TLS providers)
               + glibc malloc arena fragmentation (per-thread arenas: up to 8 × cores on 64-bit)
               + shared libraries (libjvm.so ≈ 20+ MB) and CDS archive mappings
```

### 2.1 Real NMT summary (JDK 25)

The program below allocates 32 MB of direct buffers and parks 50 extra threads, then prints its own Native Memory Tracking summary through the `DiagnosticCommand` MBean. That is the same thing `jcmd <pid> VM.native_memory summary` prints.

<!-- run: jvm="-XX:NativeMemoryTracking=summary -Xms256m -Xmx256m" -->
```java
import java.lang.management.BufferPoolMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryPoolMXBean;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import javax.management.ObjectName;

public class MemoryAreas {
    public static void main(String[] args) throws Exception {
        List<ByteBuffer> keep = new ArrayList<>();
        for (int i = 0; i < 8; i++) keep.add(ByteBuffer.allocateDirect(4 * 1024 * 1024)); // 32 MB off-heap
        for (int i = 0; i < 50; i++) Thread.ofPlatform().daemon().start(() -> {
            try { Thread.sleep(60_000); } catch (InterruptedException ignored) { }
        });
        System.out.println("== Memory pools (MemoryPoolMXBean)");
        for (MemoryPoolMXBean p : ManagementFactory.getMemoryPoolMXBeans())
            System.out.printf("  %-34s %-16s used=%,d KB%n", p.getName(), p.getType(), p.getUsage().getUsed() / 1024);
        System.out.println("== Buffer pools (BufferPoolMXBean)");
        for (BufferPoolMXBean b : ManagementFactory.getPlatformMXBeans(BufferPoolMXBean.class))
            System.out.printf("  %-34s count=%d used=%,d KB%n", b.getName(), b.getCount(), b.getMemoryUsed() / 1024);
        Object nmt = ManagementFactory.getPlatformMBeanServer().invoke(
            new ObjectName("com.sun.management:type=DiagnosticCommand"), "vmNativeMemory",
            new Object[] { new String[] { "summary", "scale=MB" } }, new String[] { String[].class.getName() });
        System.out.println(nmt);
    }
}
```

Output (one verified run, trimmed; the numbers vary between runs):

```
== Memory pools (MemoryPoolMXBean)
  CodeHeap 'non-nmethods'            Non-heap memory  used=1,447 KB
  Metaspace                          Non-heap memory  used=10,598 KB
  CodeHeap 'profiled nmethods'       Non-heap memory  used=2,555 KB
  Compressed Class Space             Non-heap memory  used=1,315 KB
  G1 Eden Space                      Heap memory      used=13,312 KB
  G1 Old Gen                         Heap memory      used=1,174 KB
  G1 Survivor Space                  Heap memory      used=2,847 KB
  CodeHeap 'non-profiled nmethods'   Non-heap memory  used=547 KB
== Buffer pools (BufferPoolMXBean)
  mapped                             count=0 used=0 KB
  direct                             count=8 used=32,768 KB
  mapped - 'non-volatile memory'     count=0 used=0 KB

Native Memory Tracking:
Total: reserved=1784MB, committed=401MB
       malloc: 69MB #60791, peak=72MB #60626
       mmap:   reserved=1714MB, committed=332MB

-                 Java Heap (reserved=256MB, committed=256MB)
-                     Class (reserved=1024MB, committed=2MB)
                            (classes #3677)
                            (  Metadata:   )
                            (    reserved=64MB, committed=11MB)
                            (  Class space:)
                            (    reserved=1024MB, committed=2MB)
-                    Thread (reserved=75MB, committed=4MB)
                            (threads #75)
                            (stack: reserved=75MB, committed=4MB, peak=4MB)
-                      Code (reserved=244MB, committed=10MB)
-                        GC (reserved=58MB, committed=58MB)
-                     Other (reserved=32MB, committed=32MB)      <-- the 32 MB of direct ByteBuffers
-                    Symbol (reserved=3MB, committed=3MB)
-        Shared class space (reserved=16MB, committed=14MB, readonly=0MB)
-               Arena Chunk (reserved=8MB, committed=8MB)
-                 Metaspace (reserved=64MB, committed=11MB)
```

**How to read it:**

* **reserved** is address space, which is nearly free on 64-bit. **committed** is what can show up in RSS. Container limits care about committed and touched pages.
* `Thread`: 75 threads reserved 75 MB of stack (1 MB each) but committed only **4 MB**, because stack pages are committed on touch. Deep recursion or large frames raise the committed number.
* `GC` = 58 MB of committed *native* memory for a 256 MB heap (≈ 23% here, because small heaps have fixed costs). G1 card table + remembered sets + mark bitmap + per-region data. **Budget 5–20% of heap for GC structures**, more for ZGC with a high object count.
* Direct `ByteBuffer`s show up under **Other**, not under Java Heap.
* NMT's own overhead is ~1 MB here. `summary` mode costs a few % CPU; `detail` mode records call sites and is more expensive.
* NMT does **not** see memory malloc'd by native libraries that bypass HotSpot (JNI libs, glibc arenas used by them). If `RSS − NMT committed` is large, suspect native-library leaks or malloc fragmentation (`pmap -x <pid>`, jemalloc profiling, `MALLOC_ARENA_MAX=2`).

### 2.2 Container sizing rule of thumb

```
container_limit ≥ Xmx + Metaspace(steady) + CodeCache(≤240 MB, typically 30–80 MB used)
                 + threads × (committed stack ≈ 100 KB–1 MB) + GC overhead(5–20% Xmx)
                 + MaxDirectMemorySize(actual usage) + native libs + 10% slack
```

That is why `-XX:MaxRAMPercentage=75` is a common default for 2–8 GB pods, while pods running Netty, Kafka clients, compression codecs or large thread counts often need **60–70%**.

---

## 3. The heap: layout, allocation and aging 🔥

### 3.1 Logical layout (generational collectors)

```
G1 (region-based; region size = 1–512 MB, power of 2; ergonomic target ≈ 2048 regions)
┌──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐
│E │E │S │O │O │H │H │H │F │E │O │F │F │O │E │S │   E=eden S=survivor O=old H=humongous F=free
└──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘   (generations are SETS of regions, not contiguous)

Parallel / Serial (contiguous generations)
┌──────────── Young (NewRatio=2 → 1/3 of heap) ───────────┬────────── Old (2/3) ──────────┐
│        Eden (SurvivorRatio=8 → 8/10)    │ S0 1/10 │ S1 1/10 │                              │
└─────────────────────────────────────────┴─────────┴─────────┴──────────────────────────────┘

ZGC (generational, JDK 21+): pages — small 2 MB (objects ≤ 256 KB), medium (range shown in log:
"Page Size Medium: Range [2M, 8M]" on this machine), large (N × 2 MB, one object each); young/old
generations are sets of pages.
```

### 3.2 Allocation: the TLAB fast path ⚡

```
new Foo()  ─►  [1] TLAB bump-pointer:  top += size; if (top <= end) done    ~10 instructions, no atomics
                     │ TLAB exhausted
                     ▼
               [2] Retire TLAB (fill the remainder with a dummy int[] so the heap stays parseable),
                   request a NEW TLAB from eden with a CAS on the region's top (size adapts: ResizeTLAB)
                     │ object too big for a TLAB, or waste would exceed TLABRefillWasteFraction
                     ▼
               [3] Allocate directly in shared eden (CAS)  ← JFR: jdk.ObjectAllocationOutsideTLAB
                     │ eden full
                     ▼
               [4] Trigger young GC (or a ZGC minor cycle / allocation stall), then retry
                     │ object ≥ ½ G1 region
                     ▼
               [H] G1 humongous allocation: contiguous free regions in OLD, never moved by young GC
```

* TLABs make allocation **almost as cheap as stack allocation**. The cost of objects in Java is mostly **GC work proportional to survivors** plus **cache misses**, not the `new` itself.
* JIT-compiled code inlines the TLAB fast path and **zeroes** the object, or elides the zeroing when it can prove every field is written.
* Flags: `-XX:+UseTLAB` (default), `-XX:+ResizeTLAB` (default), `MinTLABSize=2K`, `TLABWasteTargetPercent=1`. You almost never tune these; you reduce allocation instead.
* JFR events: `jdk.ObjectAllocationSample` (JDK 16+, throttled and cheap, on by default), `jdk.ObjectAllocationInNewTLAB` and `jdk.ObjectAllocationOutsideTLAB` (expensive, off by default). These feed async-profiler/JMC allocation flame graphs ([8.1](../08-Observability-Security-Testing/01-JVM-Profiling-JFR-async-profiler-Thread-Dumps.md)).

### 3.3 Aging, tenuring, premature promotion ⚡

* Each young GC copies survivors **eden → survivor**, and between survivor spaces, incrementing the **age** stored in the mark word (4 bits, so `MaxTenuringThreshold ≤ 15`).
* An object is promoted to old when its age exceeds the **dynamic tenuring threshold**: the age at which cumulative survivor occupancy would exceed `TargetSurvivorRatio=50`% of a survivor space. If survivors overflow, objects are promoted **prematurely**.
* **Premature promotion** is the root of most "old gen keeps growing, then a long mixed/full GC" problems: medium-lived objects (request-scoped caches, batch buffers) get promoted and then die in old gen, where they are expensive to collect.

```bash
-Xlog:gc+age=trace        # tenuring distribution per young GC (replaces -XX:+PrintTenuringDistribution)
```

### 3.4 Heap sizing ergonomics (JDK 25 defaults) 🔥

| Flag | Default | Meaning |
|---|---|---|
| `MaxRAMPercentage` | **25.0** | Max heap = 25% of (container) RAM when `-Xmx` is not set |
| `InitialRAMPercentage` | 1.5625 | Initial heap = 1/64 of RAM |
| `MinRAMPercentage` | 50.0 | Max heap for **small** RAM (≲ 250 MB), despite its misleading name |
| `MinHeapFreeRatio` / `MaxHeapFreeRatio` | 40 / 70 | Grow/shrink thresholds after GC (manageable at run time) |
| `SoftMaxHeapSize` | = Xmx | Soft target the GC tries to stay under (honoured by ZGC/Shenandoah; manageable) |
| `AlwaysPreTouch` | false | Touch every heap page at startup: slower start, no page-fault jitter later |
| `UseContainerSupport` | true (Linux) | Read cgroup v1/v2 CPU and memory limits |

> **Rule:** in containers set either `-Xmx`/`-Xms` explicitly or `MaxRAMPercentage`/`InitialRAMPercentage`. **Never** both: `-Xmx` wins silently.

---

## 4. Metaspace 🔥

### 4.1 Architecture (JDK 16+ "elastic Metaspace", JEP 387)

```
 ClassLoaderData (one per class loader, plus one per hidden class that is not strong)
      └── MetaspaceArena (non-class)  ─┐  bump-pointer allocation of Method, ConstMethod, ConstantPool,
      └── MetaspaceArena (class)      ─┤  annotations, …; Klass structures go to the class arena
                                       ▼
                         Chunks from a BUDDY ALLOCATOR: power-of-two sizes 1 KB … 16 MB
                         (the "Chunk freelists: 16m 8m 4m … 1k" section of jcmd VM.metaspace)
                                       ▼
                 VirtualSpaceList nodes (reserved address ranges; committed in 64 KB granules)
                 ├── non-class space  (grows as needed, up to MaxMetaspaceSize — unlimited by default)
                 └── compressed class space (ONE contiguous range, CompressedClassSpaceSize = 1 GB default)
```

* **Why compressed class space is separate:** with `UseCompressedClassPointers` (default), an object's klass word is a 32-bit offset (or 22-bit with compact headers) from a base. All `Klass` structures must therefore live in one contiguous, bounded range.
* When a loader dies, its arenas' chunks return to the freelists, buddies merge, and fully free granules are **uncommitted** (returned to the OS). Before JDK 16, Metaspace rarely shrank.

### 4.2 Sizing flags and GC interaction

| Flag | Default (JDK 25) | Notes |
|---|---|---|
| `MetaspaceSize` | 21 MB (22020096 B) | **Not** a size: it is the initial *high-water mark*. Crossing it triggers a GC with cause `Metadata GC Threshold` (to unload classes); the mark then adapts |
| `MaxMetaspaceSize` | unlimited | Set it (e.g. 256m–512m) so a loader leak fails fast with `OOM: Metaspace` instead of the container being OOMKilled |
| `CompressedClassSpaceSize` | 1 GB | Reserved, not committed. Max 4 GB |
| `MinMetaspaceFreeRatio` / `MaxMetaspaceFreeRatio` | 40 / 70 | HWM adjustment after GC |

**Startup symptom:** several full GCs or G1 concurrent cycles with cause `Metadata GC Threshold` in the first seconds of a Spring app. **Fix:** `-XX:MetaspaceSize=128m` (≈ steady-state usage).

### 4.3 Runnable: exhausting Metaspace, and the error handler that also fails

<!-- run: jvm="-XX:MaxMetaspaceSize=24m" timeout=60 -->
```java
import java.lang.classfile.ClassFile;
import java.lang.constant.ClassDesc;
import java.lang.constant.ConstantDescs;
import java.lang.constant.MethodTypeDesc;
import java.lang.invoke.MethodHandles;
import java.util.ArrayList;
import java.util.List;

public class MetaspaceOom {
    public static void main(String[] args) throws Exception {
        List<Class<?>> keep = new ArrayList<>();                 // strong refs: classes can never unload
        var lookup = MethodHandles.lookup();
        try {
            for (int i = 0; ; i++) {
                byte[] b = ClassFile.of().build(ClassDesc.of("Gen" + i), cb -> {
                    for (int m = 0; m < 50; m++)
                        cb.withMethodBody("m" + m, MethodTypeDesc.of(ConstantDescs.CD_void),
                                          ClassFile.ACC_PUBLIC | ClassFile.ACC_STATIC, code -> code.return_());
                });
                keep.add(lookup.defineHiddenClass(b, false).lookupClass());
            }
        } catch (OutOfMemoryError e) {
            // NOTE: "after " + n + ... would be an invokedynamic string concat whose FIRST execution
            // spins a hidden class -> needs Metaspace -> fails again with BootstrapMethodError.
            System.out.println("after ".concat(String.valueOf(keep.size())).concat(" classes: ").concat(e.toString()));
        }
    }
}
```

Output (verified; the class count varies between runs):

```
after 1434 classes: java.lang.OutOfMemoryError: Metaspace      (count varies per run: ~1,370–1,440)
```

> **War story built into the comment:** the first version of this demo used `"after " + keep.size() + …` in the `catch`. That line had never executed before, so its `invokedynamic` string-concat call site had to be **linked at that moment**, which spins a hidden class and needs Metaspace. The handler died with `BootstrapMethodError … Caused by: OutOfMemoryError: Metaspace`. Lambdas and string concatenation in *error paths that never ran before* can fail exactly when memory is exhausted. That is one more reason to use `-XX:+ExitOnOutOfMemoryError` in production.

---

## 5. Thread stacks 🔥

### 5.1 Frame anatomy

```
 Interpreted frame (JVMS model)                         Compiled frame (C2)
 ┌──────────────────────────────┐                      ┌──────────────────────────────┐
 │ operand stack (max_stack)    │                      │ spill slots, outgoing args   │
 │ monitors (synchronized)      │                      │ (locals live in REGISTERS;   │
 │ frame data: return bcp, CP   │                      │  inlined callees have NO     │
 │   cache, method*, mirror     │                      │  frame of their own)         │
 │ local variables (max_locals) │                      │ return address               │
 └──────────────────────────────┘                      └──────────────────────────────┘
```

* `max_stack` and `max_locals` are computed by javac and stored in the `Code` attribute.
* Inlining collapses frames, so **the same `-Xss` allows a much deeper recursion once code is JIT-compiled**. Deoptimization must rebuild the interpreter frames ("virtual frames") from the compiled frame's debug info, which is why deopt is not free.

### 5.2 Runnable: recursion depth vs stack size, interpreted vs compiled

<!-- run: -->
```java
public class StackDepth {
    static int depth;
    static void recurse() { depth++; recurse(); }

    static int measure(long stackBytes) throws InterruptedException {
        int[] result = new int[1];
        Thread t = new Thread(null, () -> {
            depth = 0;
            try { recurse(); } catch (StackOverflowError e) { result[0] = depth; }
        }, "probe", stackBytes);                    // per-thread stack size (a hint; the platform may round)
        t.start(); t.join();
        return result[0];
    }

    public static void main(String[] args) throws Exception {
        for (long kb : new long[] {256, 1024, 4096})
            System.out.printf("stack %5d KB -> max depth ~%,d frames%n", kb, measure(kb * 1024));
    }
}
```

Output (verified; exact numbers vary run to run with JIT timing):

```
# java -Xint StackDepth.java   (interpreter only)        # java StackDepth.java   (tiered JIT)
stack   256 KB -> max depth ~2,387 frames                 stack   256 KB -> max depth ~2,935 frames
stack  1024 KB -> max depth ~11,317 frames                stack  1024 KB -> max depth ~38,718 frames
stack  4096 KB -> max depth ~47,060 frames                stack  4096 KB -> max depth ~258,822 frames
```

**Takeaways:**

1. An interpreted frame of this trivial method costs ~90 bytes, while compiled frames are ~4× smaller, so depth depends on **JIT state**. A recursion that "works in prod" can overflow in a cold JVM, or under `-Xint` in tests.
2. Never rely on deep recursion for unbounded input (JSON nesting, tree depth, regex backtracking). Use iteration or explicit stacks, and set depth limits. Jackson 2.15+ enforces `StreamReadConstraints.maxNestingDepth = 1000` partly for this reason.

### 5.3 Guard zones and `StackOverflowError` recovery 🧊

```
 high addr ┌────────────────────┐  stack base
           │   normal frames    │
           │        ...         │
           ├────────────────────┤  ← StackShadowPages (8 pages here): "bang" ahead so native/VM code
           │   shadow zone      │    never faults inside the VM; checked on method entry ("stack banging")
           ├────────────────────┤
           │  reserved zone     │  ← StackReservedPages: lets @ReservedStackAccess critical sections
           │                    │    (e.g. ReentrantLock internals) finish, so locks aren't left corrupted (JEP 270)
           ├────────────────────┤
           │  yellow zone (3)   │  ← touching it → StackOverflowError thrown; zone re-armed after unwinding
           ├────────────────────┤
           │  red zone (1)      │  ← touching it → VM fatal error (hs_err), no recovery possible
 low addr  └────────────────────┘
```

* Catching `StackOverflowError` is legal but dangerous: `finally` blocks and `synchronized` exits on the way up may themselves overflow and leave invariants broken. JEP 270's reserved zone exists precisely because `ReentrantLock` could be left half-acquired.
* Defaults: `ThreadStackSize` is 1 MB on Linux/x64 (Windows uses the OS default, also 1 MB; the flag prints as `0`). Change globally with `-Xss512k` (saves *reserved* memory, rarely committed memory), or per thread with the `Thread` constructor's `stackSize` argument or `Thread.ofPlatform().stackSize(n)`.
* **Virtual threads** do not have fixed native stacks. Their frames are stored in heap **`StackChunk`** objects while unmounted, and they grow and shrink with use (Pillar 3, file 06). A deep recursion in a virtual thread still overflows on the **carrier's** stack while mounted.

### 5.4 "unable to create native thread" 🔥

`java.lang.OutOfMemoryError: unable to create native thread: possibly out of memory or process/resource limits reached` is **not** a heap problem. Causes, in order of likelihood:

1. **Thread leak**: unbounded `newCachedThreadPool`, a new executor per request, `HttpClient` instances created per call (each owns a selector thread).
2. **OS limits**: `ulimit -u` (max user processes, which counts threads), `kernel.threads-max`, `vm.max_map_count` (each thread stack is a mapping, plus its guard), **cgroup `pids.max`** (Kubernetes `podPidsLimit`, often 1024–4096).
3. **Native memory/address space** exhaustion (32-bit, or a strict overcommit policy).

Diagnose with `jcmd <pid> Thread.print | grep -c '^"'`, `ls /proc/<pid>/task | wc -l`, `cat /sys/fs/cgroup/pids.max`, and the JFR `jdk.ThreadStart` events for who creates the threads.

---

## 6. Code cache, symbol table, string table ⚡

| Area | JDK 25 default | Inspect | Failure |
|---|---|---|---|
| Code cache (segmented, JEP 197) | `ReservedCodeCacheSize` = 240 MB with tiered compilation: **non-nmethods** ≈ 5.6 MB (interpreter, stubs), **profiled** ≈ 117 MB (C1 tier 2/3), **non-profiled** ≈ 117 MB (C1 tier 1, C2 tier 4) | `jcmd <pid> Compiler.codecache`, `-XX:+PrintCodeCache` at exit, MemoryPoolMXBeans `CodeHeap '…'` | `CodeCache is full. Compiler has been disabled.`: **10–100× slowdown**, because the JVM falls back to the interpreter for new hot code |
| Symbol table | Native (`Symbol` = UTF-8 names and signatures), ref-counted | `jcmd <pid> VM.symboltable -verbose` | Growth from huge numbers of generated classes/method names |
| String table (interned strings) | `StringTableSize` = 65536 buckets (resizes concurrently); the String objects are on the **heap** | `jcmd <pid> VM.stringtable`, `-XX:+PrintStringTableStatistics` | `String.intern()` abuse: GC root-scanning cost, table growth |

`UseCodeCacheFlushing` (default true) evicts cold nmethods. If code-cache-full warnings appear anyway, raise `-XX:ReservedCodeCacheSize=512m` and look for **deoptimization loops** or massive generated-code footprints (Groovy, many lambdas or proxies).

---

## 7. Direct ByteBuffers — off-heap the "old" way 🔥

### 7.1 Lifecycle

```
ByteBuffer.allocateDirect(n)
   └─ java.nio.Bits.reserveMemory(n)           // accounting against MaxDirectMemorySize (default = max heap)
         ├─ fast path: CAS the reserved counter
         └─ if over limit: wait for pending Reference processing, then System.gc(),
            then retry with exponential back-off sleeps … → OOM "Cannot reserve N bytes of direct buffer memory"
   └─ Unsafe.allocateMemory(n) (+ page alignment) and zero-fill
   └─ register a Cleaner (PhantomReference) → when the DirectByteBuffer object is unreachable AND a GC
      discovers it, the Cleaner thread calls Unsafe.freeMemory and unreserves
```

**Consequences:**

1. Native memory is freed **only after a GC notices the small Java wrapper object is dead**. A long-lived app with a big old gen and few old-gen GCs can hold **gigabytes** of dead direct memory. The heap looks fine while RSS climbs.
2. `-XX:+DisableExplicitGC` turns the `System.gc()` in `reserveMemory` into a no-op, so direct-buffer reclamation under pressure **fails** → OOM. Prefer `-XX:+ExplicitGCInvokesConcurrent` (G1) if you must tame explicit GCs.
3. Allocation is expensive (malloc + zeroing + Cleaner registration + a possible GC). **Pool and reuse** direct buffers. Netty's `PooledByteBufAllocator` exists for this (Pillar 4).

### 7.2 Runnable: hitting the direct-memory limit

<!-- run: jvm="-XX:MaxDirectMemorySize=16m" -->
```java
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

public class DirectOom {
    public static void main(String[] args) {
        List<ByteBuffer> leak = new ArrayList<>();
        try {
            while (true) leak.add(ByteBuffer.allocateDirect(1024 * 1024));
        } catch (OutOfMemoryError e) {
            System.out.println("after " + leak.size() + " MB: " + e);
        }
    }
}
```

Output (verified, with `-XX:MaxDirectMemorySize=16m`):

```
after 16 MB: java.lang.OutOfMemoryError: Cannot reserve 1048576 bytes of direct buffer memory (allocated: 16777216, limit: 16777216)
```

### 7.3 The hidden per-thread temporary direct-buffer cache 🧊

When you `write()` a **heap** `ByteBuffer` to a `SocketChannel`/`FileChannel`, the JDK copies it into a **temporary direct buffer** (the kernel needs a stable native address), taken from a **per-thread cache** (`sun.nio.ch.Util.BufferCache`, a few buffers per thread). With **many threads** each writing **large** heap buffers, every thread caches large direct buffers forever. That is a classic native-memory "leak" in services with big thread pools.

* **Fix:** `-Djdk.nio.maxCachedBufferSize=262144` (buffers larger than this are not cached), use direct buffers yourself, or write in smaller chunks.
* With **virtual threads** this matters even more (many threads). The JDK's NIO paths have been adapted, but verify with `BufferPoolMXBean("direct")` and NMT `Other` growth.

### 7.4 Monitoring

```java
for (var pool : ManagementFactory.getPlatformMXBeans(BufferPoolMXBean.class))
    log.info("{} count={} used={} capacity={}", pool.getName(), pool.getCount(), pool.getMemoryUsed(), pool.getTotalCapacity());
```

Micrometer exports these as `jvm.buffer.memory.used{id=direct|mapped}`. Alert on **direct** growing without bound. Note that Netty's own allocator memory is **not** in these pools when Netty uses its cleaner-less path; use `PooledByteBufAllocator.metric()` for that.

---

## 8. The Foreign Function & Memory API (JDK 22+, JEP 454) 🔥

FFM replaces two unsafe practices: **`sun.misc.Unsafe` off-heap access** (deprecated for removal, warnings since JDK 24) and **JNI glue code**.

### 8.1 Concepts

| Concept | What it is | Key methods |
|---|---|---|
| `MemorySegment` | Bounded, typed view of a contiguous memory region (heap array, native memory, mapped file). Carries **size** (spatial safety) and **scope** (temporal safety) | `get/set(ValueLayout, offset)`, `getAtIndex`, `asSlice`, `copyFrom`, `fill`, `toArray`, `reinterpret` (restricted) |
| `Arena` | Owner of a set of native segments' **lifetime** | `ofConfined()`, `ofShared()`, `ofAuto()`, `global()`, `allocate`, `allocateFrom`, `close()` |
| `MemoryLayout` | Description of data shape and alignment | `structLayout`, `sequenceLayout`, `paddingLayout`, `ValueLayout.JAVA_INT…`, `varHandle(path)`, `byteOffset(path)` |
| `Linker` | ABI-aware bridge to native functions | `nativeLinker()`, `downcallHandle` (restricted), `upcallStub` (restricted), `defaultLookup()` |
| `SymbolLookup` | Finds native symbols | `libraryLookup(path, arena)`, `loaderLookup()` |
| `FunctionDescriptor` | C signature in layouts | `of(ret, args…)`, `ofVoid(args…)` |

### 8.2 Arena kinds — the lifetime/threading trade-off

| Arena | Lifetime | Accessible from | `close()` | Use for |
|---|---|---|---|---|
| `Arena.global()` | Forever | Any thread | Not closable | Process-lifetime tables |
| `Arena.ofAuto()` | Until GC finds it unreachable (Cleaner) | Any thread | Not closable | Convenience, like direct buffers (same GC-dependency problem) |
| **`Arena.ofConfined()`** | Explicit (try-with-resources) | **Owner thread only** | **Cheap** | Default choice: per-request or per-call scratch memory |
| `Arena.ofShared()` | Explicit | Any thread | **Expensive**: a thread-local handshake with all threads so none is mid-access | Long-lived segments shared across threads |

### 8.3 Runnable: downcall, struct layout, upcall, and the safety guarantees

<!-- run: jvm="--enable-native-access=ALL-UNNAMED" -->
```java
import java.lang.foreign.*;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.invoke.VarHandle;
import java.util.Arrays;
import static java.lang.foreign.ValueLayout.*;

public class FfmDemo {
    // struct Point { int x; int y; }  — 8 bytes, natural alignment
    static final StructLayout POINT = MemoryLayout.structLayout(JAVA_INT.withName("x"), JAVA_INT.withName("y"));
    static final VarHandle X = POINT.varHandle(MemoryLayout.PathElement.groupElement("x"));
    static final VarHandle Y = POINT.varHandle(MemoryLayout.PathElement.groupElement("y"));

    static int compareInts(MemorySegment a, MemorySegment b) {               // called FROM native qsort
        return Integer.compare(a.get(JAVA_INT, 0), b.get(JAVA_INT, 0));
    }

    public static void main(String[] args) throws Throwable {
        Linker linker = Linker.nativeLinker();
        SymbolLookup libc = linker.defaultLookup();                          // C runtime (libc / ucrt)

        // 1. Downcall: size_t strlen(const char*)
        MethodHandle strlen = linker.downcallHandle(libc.find("strlen").orElseThrow(),
                FunctionDescriptor.of(JAVA_LONG, ADDRESS));
        try (Arena arena = Arena.ofConfined()) {
            MemorySegment cString = arena.allocateFrom("Hello, Panama!");   // UTF-8, NUL-terminated
            System.out.println("strlen = " + (long) strlen.invokeExact(cString));

            // 2. Off-heap array of structs; layout VarHandles take an extra long base-offset coordinate
            MemorySegment points = arena.allocate(POINT, 3);
            for (int i = 0; i < 3; i++) {
                MemorySegment p = points.asSlice(i * POINT.byteSize(), POINT);
                X.set(p, 0L, i);
                Y.set(p, 0L, i * i);
            }
            System.out.println("struct size=" + POINT.byteSize()
                + " p[2]=(" + X.get(points.asSlice(16), 0L) + "," + Y.get(points.asSlice(16), 0L) + ")");

            // 3. Upcall: native qsort calls back into Java through an upcall stub
            MethodHandle qsort = linker.downcallHandle(libc.find("qsort").orElseThrow(),
                    FunctionDescriptor.ofVoid(ADDRESS, JAVA_LONG, JAVA_LONG, ADDRESS));
            MethodHandle cmp = MethodHandles.lookup().findStatic(FfmDemo.class, "compareInts",
                    MethodType.methodType(int.class, MemorySegment.class, MemorySegment.class));
            MemorySegment cmpStub = linker.upcallStub(cmp, FunctionDescriptor.of(JAVA_INT,
                    ADDRESS.withTargetLayout(JAVA_INT), ADDRESS.withTargetLayout(JAVA_INT)), arena);
            MemorySegment ints = arena.allocateFrom(JAVA_INT, 42, 7, 19, 3, 88);
            qsort.invokeExact(ints, 5L, JAVA_INT.byteSize(), cmpStub);
            System.out.println("qsort = " + Arrays.toString(ints.toArray(JAVA_INT)));

            // 4. Spatial safety: out-of-bounds access is an exception, not a segfault
            try { ints.getAtIndex(JAVA_INT, 5); }
            catch (IndexOutOfBoundsException e) { System.out.println("spatial: " + e.getClass().getSimpleName()); }

            // 5. Thread confinement: confined arena segments can't be touched by other threads
            Thread t = Thread.ofPlatform().start(() -> {
                try { ints.get(JAVA_INT, 0); }
                catch (WrongThreadException e) { System.out.println("confined: " + e.getMessage()); }
            });
            t.join();
        }
        // 6. Temporal safety: use-after-free is an exception
        MemorySegment escaped;
        try (Arena arena = Arena.ofConfined()) { escaped = arena.allocate(JAVA_LONG); }
        try { escaped.get(JAVA_LONG, 0); }
        catch (IllegalStateException e) { System.out.println("temporal: " + e.getMessage()); }
    }
}
```

Output (verified on Windows x64; the same code runs on Linux and macOS because `defaultLookup()` resolves the platform C runtime):

```
strlen = 14
struct size=8 p[2]=(2,4)
qsort = [3, 7, 19, 42, 88]
spatial: IndexOutOfBoundsException
confined: Attempted access outside owning thread
temporal: Already closed
```

Without `--enable-native-access=ALL-UNNAMED` the same program prints a **restricted-method warning** on first use:

```
WARNING: A restricted method in java.lang.foreign.Linker has been called
WARNING: java.lang.foreign.Linker::downcallHandle has been called by FfmDemo in an unnamed module (file:/…/FfmDemo.java)
WARNING: Use --enable-native-access=ALL-UNNAMED to avoid a warning for callers in this module
WARNING: Restricted methods will be blocked in a future release unless native access is enabled
```

### 8.4 FFM vs JNI vs Unsafe vs ByteBuffer

| Criterion | JNI | `Unsafe` | `ByteBuffer` (direct) | **FFM** |
|---|---|---|---|---|
| Native glue code | C/C++ stubs required | — | — | **None** (pure Java; generate bindings with `jextract`) |
| Bounds checks | None | None (segfault risk) | Yes | Yes (hoisted by C2 in loops) |
| Deterministic free | Manual | Manual | **No** (GC/Cleaner) | **Yes** (`Arena.close`) |
| Size limit | — | — | **2 GB** (int index) | **long** offsets |
| Mapped files | — | — | `MappedByteBuffer` (≤ 2 GB, unmap at GC) | `FileChannel.map(mode, off, size, arena)` → segment, unmapped on `close()` |
| Struct layout | Manual | Manual offsets | Manual offsets | `MemoryLayout` + `VarHandle` |
| Call overhead | JNI transition | — | — | Similar to JNI; `Linker.Option.critical(…)` for short leaf calls that may also access heap arrays |
| Status (2026) | Restricted (warnings, JEP 472) | **Deprecated for removal** (JEP 471/498) | Supported | **Final since 22** |

### 8.5 FFM pitfalls in production 🧊

* **`Arena.ofShared().close()` is slow**: it performs a handshake with every thread. Do not create and close shared arenas per request; use confined arenas, or a long-lived shared arena.
* **`ofAuto()` reintroduces GC-dependent freeing.** It is fine for tests, but the direct-buffer problem returns.
* **Upcall exceptions**: an exception escaping an upcall **crashes the JVM**. Catch everything inside upcall targets.
* **Pinning**: a virtual thread executing a downcall that calls back into Java (upcall) and then blocks is **pinned** (JEP 491 still lists this case).
* **`reinterpret` is restricted.** A zero-length segment returned from native code must be reinterpreted to a size, and getting that size wrong brings back C-style bugs.
* `jextract` output is ABI- and platform-specific. Generate it per target OS/arch in CI.

---

## 9. Production failure modes & diagnostic checklist (memory areas)

| Error / symptom | Area | First commands | Usual fixes |
|---|---|---|---|
| `OOM: Java heap space` | Heap | `-XX:+HeapDumpOnOutOfMemoryError`; `jcmd <pid> GC.class_histogram`; MAT dominator tree | Fix the leak / bound the caches; raise `-Xmx` only after proving the live set legitimately needs it |
| `OOM: GC overhead limit exceeded` | Heap (Parallel GC only) | Same | Same; it means > 98% of time in GC recovering < 2% of the heap |
| `OOM: Requested array size exceeds VM limit` | Heap | Stack trace | Array length near `Integer.MAX_VALUE` (e.g. `ArrayList`/`StringBuilder` growth on giant data); stream it instead |
| `OOM: Metaspace` | Metaspace | `jcmd VM.metaspace`, `VM.classloader_stats`, MAT duplicate classes | Fix loader leaks; cache generated classes; set `MaxMetaspaceSize` |
| `OOM: Compressed class space` | Class space | `jcmd VM.metaspace` | Reduce class count; `CompressedClassSpaceSize` up to 4 GB |
| `OOM: Cannot reserve N bytes of direct buffer memory` | Direct | `BufferPoolMXBean`, NMT `Other` | Release/pool buffers; don't `DisableExplicitGC`; raise `MaxDirectMemorySize` deliberately |
| `OOM: unable to create native thread` | Threads/OS | Thread count, `ulimit -u`, `pids.max` | Fix thread leaks; bound pools; use virtual threads for blocking concurrency |
| `OOM: Map failed` | Mapped files / address space | `vm.max_map_count`, `/proc/<pid>/maps \| wc -l` | Fewer, larger mappings; raise `vm.max_map_count` (Elasticsearch/Lucene recommend 262144) |
| `CodeCache is full. Compiler has been disabled.` | Code cache | `jcmd Compiler.codecache`, deopt counts in JFR | Raise `ReservedCodeCacheSize`; fix deopt storms |
| Container **OOMKilled** (exit 137) with a healthy heap | Native total | NMT summary/diff, `pmap -x`, `/sys/fs/cgroup/memory.stat` | Lower `MaxRAMPercentage`; cap direct memory; `MALLOC_ARENA_MAX=2`; consider jemalloc |
| RSS grows slowly forever, NMT flat | Native outside HotSpot | `pmap -x` (many 64 MB anon regions = glibc arenas), jemalloc profiling | `MALLOC_ARENA_MAX`; fix the JNI library leak |
| `StackOverflowError` only in cold JVM or tests | Stack | Depth vs JIT state (see §5.2) | Iterative algorithms; depth limits; larger `-Xss` for that specific thread |
| Startup GCs with cause `Metadata GC Threshold` | Metaspace | GC log causes | `-XX:MetaspaceSize=<steady state>` |

**NMT diff workflow for slow native leaks:**

```bash
java -XX:NativeMemoryTracking=summary ...            # (detail = call sites, more overhead)
jcmd <pid> VM.native_memory baseline
# ... wait for growth (hours) ...
jcmd <pid> VM.native_memory summary.diff scale=MB     # which category grew? Thread? Other? Class? GC? Internal?
```

---

## 10. Interview & certification Q&A

<details><summary><b>Q1. 🔥 Where do static fields, interned strings and class metadata live in JDK 8+?</b></summary>

Static fields live in the `java.lang.Class` mirror object on the **heap**. Interned strings are heap objects referenced from the native `StringTable` (moved from PermGen in JDK 7). Class metadata (`InstanceKlass`, methods, bytecode, constant pools) lives in **Metaspace** (native memory). `Klass` structures specifically live in the **compressed class space** when compressed class pointers are on. PermGen no longer exists.
</details>

<details><summary><b>Q2. 🔥 A pod with `-Xmx2g` and a 2.5 GiB limit gets OOMKilled, but heap usage never exceeds 1.5 GB. Walk through the diagnosis.</b></summary>

RSS = heap + non-heap. Enable `-XX:NativeMemoryTracking=summary` and compare `jcmd VM.native_memory summary` to the container's `memory.current`/RSS. The usual suspects are: thread stacks (hundreds of threads), Metaspace (no `MaxMetaspaceSize`), code cache (up to 240 MB), GC structures (5–20% of heap), direct buffers (Netty/NIO, default limit = `-Xmx` = 2 GB!), and native libraries plus glibc arenas (outside NMT, so check `pmap`). Fixes: lower the heap (`MaxRAMPercentage≈70`), cap `MaxDirectMemorySize`, bound thread counts, set `MALLOC_ARENA_MAX=2`, and size the container from measured RSS plus 10–20% headroom.
</details>

<details><summary><b>Q3. ⚡ Why is object allocation in Java cheap, and what is the actual cost of creating garbage?</b></summary>

TLAB bump-pointer allocation is a few instructions with no synchronization, and JIT code inlines it. The real costs are (1) zeroing and cache-line traffic for new memory, (2) GC work proportional to **live** objects at collection time (copying survivors, promotion), (3) more frequent young GCs at high allocation rates, and (4) premature promotion when survivors overflow. Dead objects cost almost nothing to a copying collector.
</details>

<details><summary><b>Q4. ⚡ What does `MetaspaceSize` actually control?</b></summary>

It sets the initial high-water mark that triggers a GC (cause `Metadata GC Threshold`) to try class unloading. It does not set a maximum or a reservation. Setting it near steady-state usage avoids startup GCs. `MaxMetaspaceSize` is the hard limit (unlimited by default).
</details>

<details><summary><b>Q5. 🔥 How are direct ByteBuffers freed, and why can `-XX:+DisableExplicitGC` cause `OutOfMemoryError: Cannot reserve … direct buffer memory`?</b></summary>

Each `DirectByteBuffer` has a `Cleaner` (phantom reference) that frees the native memory after a GC finds the buffer unreachable. When an allocation would exceed `MaxDirectMemorySize`, `Bits.reserveMemory` waits for reference processing and then calls `System.gc()` to discover dead buffers before retrying. With `DisableExplicitGC` that GC never happens, so dead-but-undiscovered buffers keep their reservation and the allocation fails.
</details>

<details><summary><b>Q6. ⚡ Compare `Arena.ofConfined()`, `ofShared()`, `ofAuto()` and `global()`.</b></summary>

Confined: explicit close, owner thread only, cheap to close, the default choice. Shared: explicit close, any thread may access, and close requires a handshake with all threads, which is expensive. Auto: freed by GC (Cleaner), any thread, no deterministic release. Global: never freed. Pick confined for request-scoped buffers, shared for long-lived cross-thread data structures, and avoid auto in high-churn paths.
</details>

<details><summary><b>Q7. 🧊 Why can the same recursive method overflow at depth 11k in one run and 38k in another with the same `-Xss`?</b></summary>

Interpreted frames are much larger than C2-compiled frames (locals and operand stack in memory versus registers, and inlining collapses frames). Depth therefore depends on whether, and at which tier, the method was compiled when the recursion happened. Tests running in a cold JVM (or `-Xint`) overflow earlier.
</details>

<details><summary><b>Q8. 🔥 What are the root causes of `OutOfMemoryError: unable to create native thread`?</b></summary>

The OS refused `pthread_create`/`CreateThread`: per-user process/thread limits (`ulimit -u`), cgroup `pids.max` in Kubernetes, `kernel.threads-max`, `vm.max_map_count`, or native memory/address-space exhaustion. In practice it is almost always a thread leak or an unbounded thread pool. The heap size is irrelevant, and raising `-Xmx` makes it worse because it leaves less native memory.
</details>

<details><summary><b>Q9. ⚡ What happens when the code cache fills up?</b></summary>

The JVM logs `CodeCache is full. Compiler has been disabled.` and stops JIT-compiling. Already-compiled code keeps running, but anything newly hot stays interpreted, giving severe performance degradation. Code-cache flushing tries to evict cold methods first. Fix by increasing `ReservedCodeCacheSize` and investigating deoptimization loops or excessive generated code.
</details>

<details><summary><b>Q10. 🎓 Which memory areas are per-thread and which are shared according to the JVMS?</b></summary>

Per-thread: the pc register, the JVM stack and the native method stack. Shared: the heap, the method area and the run-time constant pools (one per class, inside the method area).
</details>

<details><summary><b>Q11. ⚡ Why does FFM's `Arena`-based allocation beat direct `ByteBuffer`s for request-scoped native memory?</b></summary>

Deterministic release on `close()` (no GC dependency, no `Bits.reserveMemory` back-off or `System.gc()` stalls), no 2 GB limit, structured layouts with `VarHandle` accessors, and confinement/temporal-safety checks that turn use-after-free into exceptions. Direct buffers rely on Cleaners, so native memory lingers until a GC discovers the dead wrappers.
</details>

<details><summary><b>Q12. 🧊 What does the per-thread temporary direct-buffer cache do, and how does it cause leaks?</b></summary>

NIO channel I/O with heap buffers copies through a temporary direct buffer taken from a per-thread cache. Threads that ever wrote large heap buffers keep large direct buffers cached for their whole lifetime. Many threads multiplied by large buffers gives a big native footprint. Limit it with `-Djdk.nio.maxCachedBufferSize` or use direct buffers yourself.
</details>

---

## 11. Further reading

* JVMS §2.5: <https://docs.oracle.com/javase/specs/jvms/se25/html/jvms-2.html#jvms-2.5>
* NMT: <https://docs.oracle.com/en/java/javase/25/vm/native-memory-tracking.html>
* JEP 387 Elastic Metaspace (Thomas Stüfe's design notes), JEP 454 FFM, JEP 472, JEP 471/498.
* Aleksey Shipilëv, "JVM Anatomy Quark #4: TLAB allocation", "#12: Native Memory Tracking".
