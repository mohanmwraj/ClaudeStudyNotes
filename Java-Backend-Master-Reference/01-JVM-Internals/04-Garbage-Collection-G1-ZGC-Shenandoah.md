# 1.4 · Garbage Collection Deep Dive — G1, Generational ZGC, Shenandoah, Parallel, Serial, Epsilon

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** HotSpot GC Tuning Guide (JDK 25), JEP 248 (G1 default), 307 (parallel full GC for G1), 346 (G1 uncommit), 423 (G1 region pinning), 475 (late barrier expansion), 522 (G1 throughput, JDK 26), 523 (G1 default everywhere, JDK 27), 333/377 (ZGC), 376 (ZGC concurrent stack processing), 439/474/490 (Generational ZGC), 189/379 (Shenandoah), 404/521 (Generational Shenandoah), 318 (Epsilon), 421 (finalization deprecation).
> **Every log excerpt below was produced on Temurin 25.0.4.1** by the small programs in this file. They are real, not reconstructed.

---

## 1. First principles 🔥

### 1.1 Reachability and GC roots

An object is live if it is reachable from a **root**:

| Root category | Examples |
|---|---|
| Thread stacks | Local variables and operand-stack slots of every frame (interpreted and compiled; compiled frames use **oop maps** at safepoints to tell the GC which registers/slots hold references) |
| Class statics | Static fields, reached via `Class` mirrors held by live `ClassLoaderData` |
| JNI handles | Global and local JNI references |
| VM internals | System dictionary, string table (weak), monitors held by threads, code-cache-embedded oops, JVMTI |
| Remembered sets | For a partial (young/region) collection: references *into* the collected area from outside it. They are not true roots, but they act like roots for that GC |

Everything else is garbage. Java does **not** use reference counting: cycles are collected naturally, and there is no per-assignment counter traffic.

### 1.2 The three basic algorithms

| Algorithm | Work proportional to | Fragmentation | Space overhead | Used by |
|---|---|---|---|---|
| **Copying / evacuation** | **Live** objects | None (compacts as it copies) | Needs free to-space | Young collections (all generational GCs), G1 evacuation, ZGC/Shenandoah relocation |
| Mark–sweep | Live (mark) + **heap** (sweep) | Yes | Free lists | CMS (removed in JDK 14) |
| Mark–compact | Live (mark) + live (move) + references (fix-up) | None | Small | Serial/Parallel full GC, G1 full GC |

**The weak generational hypothesis:** most objects die young. So collect the young space frequently with copying (cost ∝ survivors ≈ small) and the old space rarely. Since old→young pointers must be tracked to avoid scanning all of old gen, every generational collector needs a **write barrier** plus a **card table or remembered set**.

### 1.3 Tri-color marking and why concurrent collectors need barriers 🔥

```
WHITE = not yet seen (garbage if still white at the end)
GREY  = seen, its fields not yet scanned (on the mark stack)
BLACK = seen and fully scanned
Invariant (strong): no BLACK object points to a WHITE object.
```

While marking runs **concurrently** with the application (the "mutator"), the mutator can break the invariant. **Lost-object problem:** the mutator (1) stores a reference to white object W into an already-black object B, and (2) deletes the only grey→W path. The marker never visits W, so a live object gets freed, which is catastrophic.

| Fix | Barrier | Idea | Used by |
|---|---|---|---|
| **Incremental update** (Dijkstra) | Write barrier on *new* value | When storing W into black B, shade W grey (or re-scan B later) | CMS (historical) |
| **Snapshot-at-the-beginning (SATB)** (Yuasa) | Write barrier on *old* value (pre-write) | Before overwriting a field, record the old referent, so everything live at mark start is marked | **G1, Shenandoah**, Generational ZGC (its store barrier reports to-be-overwritten values) |
| **Load barrier / read barrier** | On every reference *load* | The mutator never sees a stale or unmarked pointer; it self-heals the field | **ZGC** (colored-pointer load barrier), Shenandoah (load-reference barrier for evacuation) |

SATB is conservative: objects that die *during* marking survive until the next cycle ("floating garbage").

### 1.4 Safepoints, handshakes and time-to-safepoint (TTSP) 🔥

STW phases require every Java thread to stop at a **safepoint**: a point where the JIT has recorded oop maps, so the GC knows exactly where every reference lives.

* **Polls:** the interpreter checks at bytecode dispatch. JIT code polls at **method returns** and **loop back-edges**, using a thread-local poll word armed by the VM.
* **Thread-local handshakes** (JEP 312, JDK 10) let the VM stop *one* thread at a time for some operations (stack scanning, biased-lock revocation in the past, deoptimization), and concurrent GCs use them to process stacks incrementally (ZGC JEP 376).
* **Counted loops:** C2 used to omit polls in `int`-indexed counted loops, so a 2-billion-iteration loop could delay a safepoint for seconds. Since JDK 10 **loop strip mining** (`LoopStripMiningIter=1000`, `UseCountedLoopSafepoints=true`) inserts a poll every 1000 iterations with negligible overhead.
* Threads in **native code** (JNI) are already "safe" and don't block the safepoint. However, they can't return to Java until it ends.

Real `-Xlog:safepoint` output (JDK 25):

```
[0.057s][info][safepoint] Safepoint "G1CollectForAllocation", Time since last: 28104200 ns, Reaching safepoint: 2500 ns,
                          At safepoint: 2687300 ns, Leaving safepoint: 5400 ns, Total: 2695200 ns, Threads: 0 runnable, 11 total
```

**Read it as:** *Reaching safepoint* = TTSP (here 2.5 µs, which is healthy). *At safepoint* = the actual GC pause (2.7 ms). **If Reaching ≫ At**, you have a TTSP problem: a long non-polling loop, a page fault storm (mapped files, swapped heap), a giant `System.arraycopy`, or a thread stuck in a VM operation. GC logs can't show this, because the GC pause clock starts *after* all threads arrive. **Always log `safepoint` alongside `gc`.**

---

## 2. The collectors at a glance 🔥

| | Serial | Parallel | **G1** (default) | **ZGC** (generational) | **Shenandoah** | Epsilon |
|---|---|---|---|---|---|---|
| Flag | `-XX:+UseSerialGC` | `-XX:+UseParallelGC` | `-XX:+UseG1GC` | `-XX:+UseZGC` | `-XX:+UseShenandoahGC` | `-XX:+UnlockExperimentalVMOptions -XX:+UseEpsilonGC` |
| Young collection | STW copy, 1 thread | STW copy, N threads | STW parallel evacuation | **Concurrent** | Concurrent (generational mode) | — |
| Old collection | STW mark-compact | STW parallel mark-compact | Concurrent mark + STW **incremental** evacuation (mixed GCs) | **Concurrent** mark + relocate | Concurrent mark + evacuate + update-refs | Never |
| Typical pauses | 10 ms – seconds | 10 ms – seconds | 5–200 ms (goal `MaxGCPauseMillis=200`) | **< 1 ms** | < 10 ms (often ~1 ms) | 0 |
| Barriers | Card-mark post-write | Card-mark post-write | SATB pre-write + card post-write | Load barrier + store barrier (colored pointers) | SATB + load-reference barrier | None |
| Compressed oops | ✅ | ✅ | ✅ | **❌** | ✅ | ✅ |
| Heap sweet spot | < 100s of MB | Any, throughput-first | 1 GB – ~100 GB | 1 GB – 16 TB | 1 GB – 100s of GB | Short jobs |
| CPU overhead | Lowest | Low | Moderate | Higher | Higher | None |
| Picks itself | **< 2 CPUs or < ~1.8 GB RAM** (JDK ≤ 26) | Never | Otherwise (and always from JDK 27, JEP 523) | Never | Never | Never |
| Availability | All | All | All | All | OpenJDK builds (Temurin ✅, Corretto, Red Hat, Zulu); historically **not** Oracle JDK | All |

Verified on JDK 25: `java -XX:ActiveProcessorCount=1 -Xlog:gc -version` prints `Using Serial`. A 1-vCPU Kubernetes pod running JDK 21/25 without an explicit GC flag gets **Serial GC**, which is one of the most common unnoticed misconfigurations.

---

## 3. Barriers in detail ⚡

### 3.1 Card table (Serial, Parallel, G1)

```
heap:       |<- 512 B ->|<- 512 B ->|<- 512 B ->| ...      (card = 512 bytes; log2 = 9)
card table: [  clean   ][  DIRTY   ][  clean   ] ...      (1 byte per card → table = heap/512, ~0.2%)

post-write barrier for  obj.field = val  (Parallel/Serial):
    card_table[(uintptr_t)&obj.field >> 9] = DIRTY;            // unconditional byte store
```

At young GC, only **dirty cards** in old gen are scanned for old→young pointers. `-XX:+UseCondCardMark` makes the barrier check before writing (`if (card != DIRTY) card = DIRTY`), which avoids false sharing on card bytes under heavy multi-threaded writes. Generational Shenandoah turns it on ergonomically, as its startup log shows.

### 3.2 G1's two barriers

```c
// obj.field = new_val
// ---- pre-write (SATB): only while concurrent marking is active ----
if (marking_active) {
    old_val = obj.field;
    if (old_val != null) satb_queue.enqueue(old_val);          // keep the snapshot alive
}
obj.field = new_val;
// ---- post-write (remembered-set maintenance) ----
if (region(&obj.field) != region(new_val) && new_val != null) { // cross-region store?
    card = card_for(&obj.field);
    if (*card != young && *card != dirty) {
        *card = dirty;
        dirty_card_queue.enqueue(card);                          // refinement threads update RSets
    }
}
```

* The post-barrier filters same-region and null stores and avoids most work. Refinement threads (`G1ConcRefinementThreads`) process dirty cards concurrently into per-region **remembered sets**.
* **JDK 24, JEP 475 (late barrier expansion):** C2 now expands G1 barriers late in compilation, which simplifies the compiler and slightly improves code quality and compile time.
* **JDK 26, JEP 522:** G1 replaces the dirty-card-queue handoff with **two card tables** swapped between the mutator and refinement. That reduces synchronization and shrinks the post-barrier, improving throughput. This is one of the main reasons to evaluate JDK 26/27 for G1 throughput-bound services.

### 3.3 ZGC's colored pointers and barriers

* Generational ZGC stores **GC metadata in the low-order bits** of every heap reference, with the address in the high-order bits (JEP 439). There is no multi-mapping anymore; earlier non-generational ZGC mapped the heap three times.
* **Load barrier** (on every reference load from the heap): checks whether the pointer's color is "good". On x64 a single shift both checks and strips the metadata bits. On the slow path it marks, remaps (if the object was relocated) or relocates the object, and **self-heals** the field with a good pointer, so later loads take the fast path.
* **Store barrier** (generational): records old→young pointers in the **remembered set** and reports **to-be-overwritten values** (SATB) for concurrent marking.
* Because references carry metadata, **compressed oops are impossible**. Every reference is 64 bits.

### 3.4 Shenandoah's barriers

* **SATB pre-write barrier** for concurrent marking, as in G1.
* **Load-reference barrier (LRB)** (JDK 13+): when loading a reference to an object in the collection set during evacuation, the barrier returns the to-space copy, evacuating it itself if needed, and heals the field. Originally Shenandoah used a Brooks forwarding pointer (an extra word per object). Since JDK 13 it stores the forwarding pointer in the **mark word**, so there is no per-object overhead.

---

## 4. G1 (Garbage-First) in depth 🔥

### 4.1 Heap regions

* The heap is split into equal **regions**: `G1HeapRegionSize` from 1 MB up to 512 MB, a power of 2, chosen ergonomically to give ~2048 regions. Real values: a 256 MB heap got **1 MB** regions and a 31 GB heap got **16 MB** regions.
* Each region is at any moment **free, eden, survivor, old, or humongous** (start/continues).
* **"Garbage-First"**: G1 tracks live bytes per old region after marking and evacuates the regions with the **most garbage** first, as many as fit the pause-time goal.

### 4.2 Young GC (evacuation pause) — anatomy from a real log

```
[0.117s][info][gc,start    ] GC(1) Pause Young (Normal) (G1 Evacuation Pause)
[0.117s][info][gc,task     ] GC(1) Using 6 workers of 10 for evacuation
[0.123s][info][gc,phases   ] GC(1)   Pre Evacuate Collection Set: 0.14ms   ← choose CSet, prepare TLABs/PLABs
[0.123s][info][gc,phases   ] GC(1)   Merge Heap Roots: 0.05ms              ← merge remembered sets + card table into "to scan" set
[0.123s][info][gc,phases   ] GC(1)   Evacuate Collection Set: 5.80ms       ← scan roots + RSets, COPY live objects (the bulk)
[0.123s][info][gc,phases   ] GC(1)   Post Evacuate Collection Set: 0.30ms  ← reference processing, free CSet, redirty cards
[0.123s][info][gc,phases   ] GC(1)   Other: 0.11ms
[0.123s][info][gc,heap     ] GC(1) Eden regions: 93->0(76)      ← 93 eden regions emptied; next eden target 76
[0.123s][info][gc,heap     ] GC(1) Survivor regions: 6->13(13)
[0.123s][info][gc,heap     ] GC(1) Old regions: 17->57          ← 40 regions PROMOTED in one GC: survivor overflow → premature promotion
[0.123s][info][gc,heap     ] GC(1) Humongous regions: 8->4      ← dead humongous objects eagerly reclaimed at young GC
[0.123s][info][gc,metaspace] GC(1) Metaspace: 91K(320K)->91K(320K) NonClass: 88K(192K)->88K(192K) Class: 3K(128K)->3K(128K)
[0.123s][info][gc          ] GC(1) Pause Young (Normal) (G1 Evacuation Pause) 122M->72M(256M) 6.623ms
[0.123s][info][gc,cpu      ] GC(1) User=0.00s Sys=0.09s Real=0.01s
```

**What determines young-pause length:** live objects to copy (survivors), the number of dirty cards and RSet entries to scan (old→young pointers), root counts (threads, code cache), and reference processing. Eden *size* barely matters, because dead objects cost nothing. G1 resizes eden **between** `G1NewSizePercent=5`% and `G1MaxNewSizePercent=60`% of the heap to meet `MaxGCPauseMillis`.

### 4.3 Concurrent marking cycle — anatomy from a real log

```
GC(4) Pause Young (Concurrent Start) (G1 Humongous Allocation) 177M->171M(256M) 3.410ms   ← young GC + initial mark (piggy-backed)
GC(5) Concurrent Mark Cycle
GC(5) Concurrent Scan Root Regions 0.503ms        ← survivor regions are roots for marking; must finish before next young GC
GC(5) Concurrent Mark From Roots 1.726ms          ← "Using 3 workers of 3 for marking" (ConcGCThreads)
GC(5) Concurrent Preclean 0.011ms
GC(5) Pause Remark 180M->180M(256M) 0.485ms        ← STW: drain SATB buffers, reference processing, class unloading
GC(5) Concurrent Rebuild Remembered Sets and Scrub Regions 0.871ms
GC(5) Pause Cleanup 182M->182M(256M) 0.033ms       ← STW: compute region liveness, select mixed-GC candidates
GC(5) Concurrent Clear Claimed Marks / Cleanup for Next Mark
GC(5) Concurrent Mark Cycle 4.560ms
GC(6) Pause Young (Prepare Mixed) (G1 Evacuation Pause) 205M->195M(256M) 3.294ms
GC(7) Pause Young (Mixed) (G1 Evacuation Pause) 215M->186M(256M) 2.628ms   ← young + some old regions
GC(8) Pause Young (Mixed) (G1 Evacuation Pause) 213M->180M(256M) 3.397ms
```

**When marking starts — IHOP:** when old-gen occupancy crosses the **Initiating Heap Occupancy Percent**. That is `InitiatingHeapOccupancyPercent=45` initially, and **adaptive** (`G1UseAdaptiveIHOP=true`): G1 learns how long marking takes and how fast old gen fills, and starts early enough to finish before the heap is full (keeping `G1ReservePercent=10` in reserve). Humongous allocations can also trigger it, as the `(G1 Humongous Allocation)` cause shows above.

**Mixed GCs:** after cleanup, candidate old regions (live ratio < `G1MixedGCLiveThresholdPercent=85`) are spread over up to `G1MixedGCCountTarget=8` mixed collections. Mixed GCs stop when reclaimable space drops below `G1HeapWastePercent=5`.

### 4.4 Humongous objects 🔥

* Any object ≥ **half a region** is humongous. It is allocated directly in contiguous free regions in old gen, occupies whole regions (the tail of the last region is wasted), and is never copied by young GC.
* Since JDK 8u60 G1 can **eagerly reclaim** dead humongous objects at young GC. The log above showed `Humongous regions: 8->4`.
* **Problem pattern:** services that allocate many large `byte[]`/`char[]` buffers (JSON payloads, Kafka batches, image processing) as short-lived humongous objects. That causes **fragmentation, frequent concurrent cycles, and evacuation failures**. Fixes: increase `G1HeapRegionSize` (e.g. 16m/32m so those buffers are no longer humongous), stream instead of buffering, pool the buffers.
* JDK 22 **region pinning** (JEP 423): JNI critical regions pin only their region instead of blocking GC entirely, so `GetPrimitiveArrayCritical` users no longer stall G1.

### 4.5 Evacuation failure → Full GC (real log, heap too small)

```
GC(7)  Pause Young (Prepare Mixed) (G1 Evacuation Pause) (Evacuation Failure: Allocation) 89M->91M(96M) 0.461ms
GC(8)  Pause Young (Mixed) (G1 Evacuation Pause) (Evacuation Failure: Allocation) 95M->95M(96M) 0.368ms
GC(9)  Pause Full (G1 Compaction Pause) 95M->86M(96M) 2.503ms
GC(10) Pause Young (Concurrent Start) (G1 Evacuation Pause) (Evacuation Failure: Allocation) 88M->88M(96M) 0.246ms
GC(11) Pause Full (G1 Compaction Pause) 88M->88M(96M) 2.240ms
...                                                              → java.lang.OutOfMemoryError: Java heap space
```

* **Evacuation failure** (older JDKs said "to-space exhausted"): there was no free region to copy survivors into. G1 leaves the objects in place (the self-forwarded bit in the mark word), then must fix up, and usually a **Full GC** follows: a parallel, STW mark-compact of the whole heap (parallel since JDK 10, JEP 307), which takes **seconds** on large heaps.
* Back-to-back `Pause Full` that free nothing means the live set doesn't fit. That is a leak or an undersized heap, and the end state is `OutOfMemoryError`. G1 throws OOM only after a full GC fails to free enough.
* **Fixes:** a larger heap or a smaller live set; start marking earlier (`-XX:InitiatingHeapOccupancyPercent=35`, or `-XX:G1ReservePercent=15`); avoid humongous churn; add `ConcGCThreads` if marking can't keep up.

### 4.6 G1 tuning cookbook

| Goal | Flags | Notes |
|---|---|---|
| Lower pause target | `-XX:MaxGCPauseMillis=50` | G1 shrinks young gen → more frequent GCs; below ~20 ms on large heaps is unrealistic |
| Fewer humongous objects | `-XX:G1HeapRegionSize=16m` (or 32m) | Region size ≥ 2 × typical big buffer |
| Marking starts too late (full GCs) | `-XX:InitiatingHeapOccupancyPercent=30`, `-XX:G1ReservePercent=15`, `-XX:ConcGCThreads=n` | Or `-XX:-G1UseAdaptiveIHOP` with a fixed IHOP |
| Mixed GCs too long | `-XX:G1MixedGCCountTarget=16`, `-XX:G1OldCSetRegionThresholdPercent` | Spread old-region evacuation over more pauses |
| Return memory to the OS when idle | `-XX:G1PeriodicGCInterval=60000` (ms) | JEP 346, useful for bursty tenants |
| Deduplicate Strings | `-XX:+UseStringDeduplication` | Dedups the `byte[]` backing arrays of long-lived Strings concurrently; works with all collectors since JDK 18 |
| Explicit `System.gc()` from libraries (RMI, NIO) | `-XX:+ExplicitGCInvokesConcurrent` | Better than `DisableExplicitGC`, which breaks direct-buffer reclamation |
| Container | `-XX:MaxRAMPercentage=75`, `-XX:+AlwaysPreTouch` (optional) | — |

**Don't:** set `-Xmn`/`NewRatio` with G1 (it disables pause-time-driven young sizing), or copy-paste CMS-era flags (`SurvivorRatio`, `CMSInitiatingOccupancyFraction`). Most G1 tuning consists of *removing* flags.

---

## 5. Generational ZGC in depth 🔥

### 5.1 Timeline

| JDK | Change |
|---|---|
| 11 | ZGC experimental (JEP 333), Linux only |
| 15 | Production (JEP 377) |
| 16 | Concurrent thread-stack processing (JEP 376): pauses no longer scale with thread count |
| 21 | **Generational ZGC** (JEP 439), opt-in with `-XX:+ZGenerational` |
| 23 | Generational is the **default** ZGC mode (JEP 474) |
| 24 | Non-generational mode **removed** (JEP 490). `-XX:+UseZGC` means generational |
| 26 | AOT object caching works with ZGC (JEP 516) |

### 5.2 A cycle, from a real log (`-Xlog:gc*`)

```
[0.077s][info][gc          ] GC(0) Major Collection (Warmup)
[0.078s][info][gc,task     ] GC(0) Using 2 Workers for Young Generation
[0.078s][info][gc,task     ] GC(0) Using 1 Workers for Old Generation
[0.078s][info][gc,phases   ] GC(0) Y: Young Generation
[0.078s][info][gc,phases   ] GC(0) Y: Pause Mark Start (Major) 0.012ms       ← STW #1: 12 µs
[0.079s][info][gc,phases   ] GC(0) Y: Concurrent Mark 1.486ms
[0.079s][info][gc,phases   ] GC(0) Y: Pause Mark End 0.011ms                 ← STW #2: 11 µs
[0.079s][info][gc,phases   ] GC(0) Y: Concurrent Mark Free 0.002ms
[0.079s][info][gc,phases   ] GC(0) Y: Concurrent Reset Relocation Set 0.009ms
[0.079s][info][gc,reloc    ] GC(0) Y: Using tenuring threshold: 1 (Computed)
[0.080s][info][gc,phases   ] GC(0) Y: Concurrent Select Relocation Set 0.185ms
[0.080s][info][gc,phases   ] GC(0) Y: Pause Relocate Start 0.004ms           ← STW #3: 4 µs
[0.081s][info][gc,phases   ] GC(0) Y: Concurrent Relocate 1.775ms
[0.081s][info][gc,alloc    ] GC(0) Y:                         Mark Start   Mark End   Relocate Start   Relocate End
[0.081s][info][gc,alloc    ] GC(0) Y: Allocation Stalls:          0            0              0                0
[0.082s][info][gc,mmu      ] GC(0) Y: MMU: 2ms/98.6%, 5ms/99.5%, 10ms/99.7%, 20ms/99.9%, 50ms/99.9%, 100ms/100.0%
[0.082s][info][gc,reloc    ] GC(0) Y:                        Candidates     Selected     In-Place         Size        Empty    Relocated
[0.082s][info][gc,reloc    ] GC(0) Y: Small Pages:                   11            7            0          22M           0M           4M
...
[0.083s][info][gc          ] GC(0) Major Collection (Warmup) 26M(10%)->28M(11%) 0.006s
```

* **Three pauses per generation cycle**, each a few microseconds to well under 1 ms. They only synchronize phase transitions. Thread stacks are processed concurrently via handshakes and stack watermarks.
* `Y:` and `O:` prefix the young and old generation phases. A **Major Collection** collects both, while a **Minor Collection** collects only young.
* **MMU** (minimum mutator utilization): `2ms/98.6%` means that in the worst 2 ms window, the application still got 98.6% of the time. This is the right metric for latency SLOs, better than "pause time".
* **Collection causes** you'll see: `Warmup`, `Allocation Rate` (the allocation-rate model predicts running out), `Proactive`, `High Usage`, `Timer` (`ZCollectionInterval`), `System.gc()`, `Metadata GC Threshold`, and **`Allocation Stall`**.

### 5.3 Allocation stalls — ZGC's real failure mode (real log, `-Xmx128m` with an ~100 MB live set)

```
[0.121s][info][gc          ] GC(3) Minor Collection (Allocation Rate)
[0.127s][info][gc          ] GC(3) Minor Collection (Allocation Rate) 92M(72%)->94M(73%) 0.006s
[0.142s][info][gc          ] Allocation Stall (main) 2.106ms
[0.152s][info][gc          ] Allocation Stall (main) 7.044ms
[0.141s][info][gc,alloc    ] GC(11) y: Allocation Stalls:          1                1                1                1
```

An **allocation stall** means a thread wanted memory, no page was free, and the thread **blocked until the concurrent GC freed some**. The 7 ms above is a latency spike that the "pause time" metrics never show. Stalls mean the GC can't keep up. Fixes, in order:

1. **More heap headroom**: `-Xmx` ≥ 2–3× the live set (ZGC is a "pay in memory" collector).
2. More concurrent GC threads: `-XX:ConcGCThreads=` (ZGC sizes these dynamically by default; the log shows "(dynamic)").
3. `-XX:ZAllocationSpikeTolerance=3` (default 2) if allocation is bursty, so GC starts earlier.
4. **Allocate less** (Pillar 1.5: escape analysis; Pillar 2: collection footprint).

JFR event: `jdk.ZAllocationStall`. Metrics: `jvm.gc.pause` won't show stalls, so export the JFR event or parse the logs.

### 5.4 ZGC tuning cookbook

| Flag | Default | Use |
|---|---|---|
| `-Xmx` | — | **The** main knob. Size from the live set × 2–3 |
| `-XX:SoftMaxHeapSize` | = Xmx | GC tries to stay below it and uses the rest only to avoid stalls (headroom for spikes) |
| `-XX:ConcGCThreads` | dynamic | Raise if stalls persist and CPU is available |
| `-XX:ZAllocationSpikeTolerance` | 2.0 | Bursty allocation |
| `-XX:+ZUncommit`, `-XX:ZUncommitDelay` | true, 300 s | Return memory to the OS (disabled when `-Xms` = `-Xmx`, as the init log says) |
| `-XX:ZCollectionInterval` | 0 (off) | Periodic GC for idle services (seconds) |
| `-XX:+UseLargePages` / THP | off | Fewer TLB misses on big heaps |
| `-XX:+AlwaysPreTouch` | off | Avoid page-fault latency at first use |

---

## 6. Shenandoah in depth ⚡

### 6.1 A cycle from a real log (`-Xlog:gc`)

```
[0.015s][info][gc] Heuristics ergonomically sets -XX:+ExplicitGCInvokesConcurrent
[0.016s][info][gc] Using Shenandoah
[0.082s][info][gc] Trigger: Learning 1 of 5. Free (178M) is below initial threshold (179M)
GC(1) Concurrent reset (unload classes) 0.060ms
GC(1) Pause Init Mark (unload classes) 0.011ms                 ← STW
GC(1) Concurrent marking roots 0.093ms
GC(1) Concurrent marking (unload classes) 0.864ms
GC(1) Pause Final Mark (unload classes) 0.132ms                ← STW: finish marking, choose collection set
GC(1) Concurrent thread roots / weak references / weak roots / class unloading ...
GC(1) Concurrent evacuation 0.188ms                            ← copy live objects CONCURRENTLY (LRB makes it safe)
GC(1) Pause Init Update Refs 0.002ms                           ← STW
GC(1) Concurrent update references 0.417ms                     ← walk heap, rewrite pointers to to-space copies
GC(1) Pause Final Update Refs 0.021ms                          ← STW
GC(1) Concurrent cleanup (unload classes) 69M->68M(256M) 0.008ms
```

### 6.2 Degenerated and full GC — Shenandoah's failure modes (real log)

```
[0.157s][info][gc] GC(5) Pause Degenerated GC (Outside of Cycle) 189M->123M(256M) 3.151ms
[0.201s][info][gc] GC(6) Pause Degenerated GC (Outside of Cycle) 188M->124M(255M) 3.328ms
```

* **Pacing:** when free memory runs low during a cycle, Shenandoah first slows allocating threads (`ShenandoahPacing`, tiny sleeps per allocation).
* **Degenerated GC:** if allocation still fails, it finishes the current cycle **stop-the-world**, continuing from where the concurrent cycle was. "Outside of Cycle" means it hadn't even started. Degenerated GCs are usually much shorter than a full GC, but they are pauses.
* **Full GC:** if degenerated GC can't free enough, it falls back to a STW mark-compact.
* **Heuristics:** `adaptive` (default), `static`, `compact` (aggressive footprint), `aggressive` (testing). **Modes:** `satb` (default), `passive` (diagnostic: STW only), and `generational` (JDK 25 product, JEP 521).

```bash
-XX:+UseShenandoahGC -XX:ShenandoahGCMode=generational    # JDK 25+: young/old generations, better for high allocation rates
```

---

## 7. Parallel, Serial and Epsilon (briefly) ⚡

Real Parallel GC log (`-Xmx256m`, live set ~90 MB):

```
[0.016s][info][gc] Using Parallel
[0.064s][info][gc] GC(0) Pause Young (Allocation Failure) 64M->21M(241M) 4.922ms
[0.091s][info][gc] GC(1) Pause Young (Allocation Failure) 84M->81M(242M) 13.794ms
[0.159s][info][gc] GC(4) Pause Full (Allocation Failure) 221M->89M(245M) 7.397ms
```

* **Parallel** optimizes **throughput** with adaptive sizing toward goals: `GCTimeRatio=99` (≤ 1% of time in GC; G1's own default for this flag is 12), and optionally `MaxGCPauseMillis`. `UseGCOverheadLimit` throws `OOM: GC overhead limit exceeded` when > 98% of the time goes to GC and < 2% of the heap is recovered. Best for batch, ETL and offline analytics, where the *total* time matters.
* **Serial**: a single-threaded STW copy plus mark-compact, with the lowest footprint and overhead. Fine for heaps < ~200 MB and CLI tools. It is the silent default on 1-CPU or small-memory machines up to JDK 26.
* **Epsilon** (JEP 318): allocation only, never collects, and the process dies with OOM when the heap fills. Useful for measuring pure allocation and GC-barrier costs in benchmarks, ultra-short-lived jobs, and proving a code path is allocation-free.

---

## 8. Reference types, finalization and `Cleaner` 🔥🎓

| Type | Cleared when | `get()` after enqueue | Typical use | Pitfall |
|---|---|---|---|---|
| Strong | Never while reachable | — | Normal references | Leaks |
| `SoftReference` | Only under memory pressure; policy keeps soft refs alive ~`SoftRefLRUPolicyMSPerMB=1000` ms per MB of free heap since last access | `null` | Memory-sensitive caches (discouraged) | **GC death spiral**: the heap fills with soft refs, and GC clears them only when nearly full, so latency suffers and full GCs follow. Prefer bounded caches (Caffeine) |
| `WeakReference` | At the next GC that finds the referent only weakly reachable | `null` | Canonicalizing maps (`WeakHashMap` keys), listener lists, `ThreadLocalMap` keys | A value strongly referencing its own key in `WeakHashMap` never clears |
| `PhantomReference` | After the referent is finalized/unreachable; **`get()` always returns `null`** | `null` | Post-mortem cleanup (`Cleaner`, direct buffers) | Must hold the `PhantomReference` itself strongly until processed |
| `finalize()` | Deprecated for removal (JEP 421, JDK 18); `--finalization=disabled` to test | — | **Don't** | Resurrection, unpredictable delays, an extra GC cycle, a single finalizer thread bottleneck |

<!-- run: jvm="-Xmx64m" -->
```java
import java.lang.ref.*;
import java.util.ArrayList;
import java.util.List;

public class ReferenceKinds {
    static final Cleaner CLEANER = Cleaner.create();

    /** The idiomatic replacement for finalize(): a Cleaner action that must NOT reference the owner. */
    static final class NativeHandle implements AutoCloseable {
        private final Cleaner.Cleanable cleanable;
        NativeHandle(String name) {
            State state = new State(name);                  // state holds the resource, not `this`
            this.cleanable = CLEANER.register(this, state);
        }
        @Override public void close() { cleanable.clean(); } // deterministic path (try-with-resources)
        private record State(String name) implements Runnable {
            public void run() { System.out.println("cleaned " + name); }
        }
    }

    public static void main(String[] args) throws Exception {
        Object strong = new Object();
        WeakReference<Object> weak = new WeakReference<>(new Object());
        SoftReference<byte[]> soft = new SoftReference<>(new byte[1024]);
        ReferenceQueue<Object> q = new ReferenceQueue<>();
        PhantomReference<Object> phantom = new PhantomReference<>(new Object(), q);

        System.gc(); Thread.sleep(100);
        System.out.println("weak cleared after GC     : " + (weak.get() == null));
        System.out.println("soft cleared after GC     : " + (soft.get() == null) + "  (no memory pressure)");
        System.out.println("phantom.get() always null : " + (phantom.get() == null));
        System.out.println("phantom enqueued          : " + (q.remove(1000) == phantom));

        try {                                              // memory pressure clears soft refs before OOM
            List<byte[]> hog = new ArrayList<>();
            while (true) hog.add(new byte[1 << 20]);
        } catch (OutOfMemoryError e) {
            System.out.println("soft cleared before OOM   : " + (soft.get() == null));
        }

        try (var h = new NativeHandle("explicit")) { }     // cleaned deterministically
        new NativeHandle("forgotten");                     // cleaned by GC (eventually)
        System.gc(); Thread.sleep(200);
        System.out.println(strong != null ? "done" : "");
    }
}
```

Output (verified):

```
weak cleared after GC     : true
soft cleared after GC     : false  (no memory pressure)
phantom.get() always null : true
phantom enqueued          : true
soft cleared before OOM   : true
cleaned explicit
cleaned forgotten
done
```

> **`Cleaner` rule:** the cleaning action (here the `State` record) must **not** capture the object being registered. If it does, the object is always reachable from the Cleaner and never becomes phantom-reachable, which is a leak. Lambdas that touch `this` are the usual mistake.

---

## 9. GC logging & analysis 🔥

### 9.1 Unified logging syntax (JEP 158/271)

```
-Xlog:<selectors>:<output>:<decorators>:<output-options>

-Xlog:gc*,gc+age=trace,safepoint:file=/logs/gc-%p-%t.log:time,uptime,level,tags,pid:filecount=10,filesize=50m
      │                          │                          │                          └ rotation
      │                          │                          └ decorations per line
      │                          └ %p = pid, %t = start timestamp
      └ all gc tags at info, tenuring at trace, safepoint stats
```

| Want | Selector |
|---|---|
| One line per GC | `gc` |
| Phases, heap regions, CPU | `gc*` (or `gc,gc+phases,gc+heap,gc+cpu`) |
| Tenuring distribution | `gc+age=trace` |
| Humongous allocations (G1) | `gc+humongous=debug` |
| Reference processing | `gc+ref=debug` |
| Safepoint / TTSP | `safepoint` |
| Heap/oops mode at startup | `gc+init` |
| Class unloading | `class+unload` |

Change logging at run time **without a restart**: `jcmd <pid> VM.log output=file=/tmp/gc2.log what=gc*=debug`.

### 9.2 Live-process GC inspection (real output)

```
$ jstat -gcutil <pid> 1000 3
  S0     S1     E      O      M     CCS    YGC     YGCT     FGC    FGCT     CGC    CGCT       GCT
     - 100.00  33.33  71.42  32.91   3.82    314     0.709     0     0.000   104     0.023     0.732
     - 100.00  86.36  68.42  32.91   3.82    436     0.968     0     0.000   146     0.031     1.000
     - 100.00  99.83  70.47  32.91   3.82    561     1.231     0     0.000   186     0.040     1.271
```

Columns: survivor/eden/old/metaspace/compressed-class **utilization %**, young GC count/time, full GC count/time, **CGC** = concurrent GC pauses (G1 remark/cleanup), total GC time. Here there were 247 young GCs per 2 seconds, but GC time grew only ~0.27 s per second (~27%). That is a *very* high allocation rate for a 256 MB heap: this program allocates aggressively on purpose.

```
$ jcmd <pid> GC.heap_info
garbage-first heap   total reserved 262144K, committed 262144K, used 169024K [0x00000000f0000000, 0x0000000100000000)
 region size 1024K, 9 young (9216K), 5 survivors (5120K)
```

### 9.3 Metrics that matter (and their formulas)

| Metric | How | Healthy |
|---|---|---|
| **Allocation rate** | Δ(heap before GC − heap after previous GC) / Δt, or JFR `jdk.ObjectAllocationSample` | Depends; > 1 GB/s per JVM deserves attention |
| **Promotion rate** | Δ old-gen occupancy after young GCs / Δt | Low and stable; rising = premature promotion |
| **Live set** | Old-gen occupancy after a full GC or after a concurrent cycle ("after remark/cleanup") | Stable over days; a sawtooth whose floor rises = leak |
| **GC overhead** | Σ pause time / wall time (plus concurrent CPU for ZGC/Shenandoah) | < 5% for services |
| **Pause p99/p99.9/max** | `jvm.gc.pause` histogram (Micrometer), GC logs | Within the SLO budget |
| **Allocation stalls** (ZGC) / **degenerated GCs** (Shenandoah) / **evacuation failures** and **Full GCs** (G1) | Logs and JFR | **Zero** |
| **TTSP** | `-Xlog:safepoint` "Reaching safepoint" | < 1 ms |

**Tools:** GCeasy and GCViewer (log analysis), JDK Mission Control (JFR: GC tab, "Garbage Collections", "GC Configuration"), `jfr print --events jdk.GarbageCollection rec.jfr`, Micrometer + Prometheus (`jvm_gc_pause_seconds`, `jvm_gc_memory_allocated_bytes_total`, `jvm_gc_memory_promoted_bytes_total`, `jvm_gc_live_data_size_bytes`).

---

## 10. Diagnosing `OutOfMemoryError` and memory leaks 🔥

### 10.1 The OOM message decoder

| Message | Meaning | Section |
|---|---|---|
| `Java heap space` | Allocation failed after full GC | Below |
| `GC overhead limit exceeded` | Parallel GC: > 98% time in GC, < 2% recovered | Below |
| `Requested array size exceeds VM limit` | `new T[n]` with n near `Integer.MAX_VALUE` | [1.2 §9](02-Runtime-Data-Areas-Off-Heap-FFM.md#9-production-failure-modes--diagnostic-checklist-memory-areas) |
| `Metaspace` / `Compressed class space` | Class metadata | [1.2 §4](02-Runtime-Data-Areas-Off-Heap-FFM.md#4-metaspace-) |
| `Cannot reserve N bytes of direct buffer memory` | Direct buffers | [1.2 §7](02-Runtime-Data-Areas-Off-Heap-FFM.md#7-direct-bytebuffers--off-heap-the-old-way-) |
| `unable to create native thread` | OS thread limits | [1.2 §5.4](02-Runtime-Data-Areas-Off-Heap-FFM.md#54-unable-to-create-native-thread-) |
| Container exit 137, no Java OOM | Kernel OOM killer: native total > limit | [1.2 §2](02-Runtime-Data-Areas-Off-Heap-FFM.md#2-what-a-jvm-processs-memory-actually-is-rss--heap-) |

### 10.2 Leak vs undersized heap

```
 heap after GC ▲
               │      leak: floor rises            undersized: floor flat but near max
               │            /|  /|  /|                ___________________________
               │       /|  / | / | / |               |/|/|/|/|/|/|/|/|/|/|/|/|/|  ← GC thrash
               │  /|  / | /  |/  |/                  |
               │ / | /  |/                           |
               └───────────────────────────► time    └─────────────────────────────►
```

### 10.3 Workflow

1. **Always-on:** `-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/dumps -XX:+ExitOnOutOfMemoryError`, plus JFR with `jdk.OldObjectSample` (on in the default profile; add `path-to-gc-roots=true` when dumping for leak chains).
2. **Before OOM:** compare two class histograms minutes apart. The class whose count grows linearly is the leak suspect.
3. **Heap dump analysis (Eclipse MAT):** *Leak Suspects* report → **Dominator tree** (sort by retained heap) → *Path to GC Roots* (exclude weak/soft) → find the owning static or ThreadLocal or cache. Use **OQL** for ad-hoc queries.
4. **Common leak roots:** static collections used as caches without eviction, listener/observer registries never unregistered, `ThreadLocal` on pooled threads, unbounded queues (executor `LinkedBlockingQueue`), per-request `ClassLoader`s or proxies (Metaspace), `String.intern()` on unbounded input, ORM sessions or persistence contexts in long transactions (Pillar 5), Kafka or HTTP client instances created per call.

### 10.4 Runnable: catching a leak with in-process class histograms

<!-- run: jvm="-Xmx128m" -->
```java
import java.lang.management.ManagementFactory;
import java.util.HashMap;
import java.util.Map;
import javax.management.ObjectName;

public class LeakHunt {
    record Session(String id, byte[] payload) {}
    static final Map<String, Session> SESSIONS = new HashMap<>();   // "cache" with no eviction = leak

    static String histogramTop(String filter) throws Exception {
        String h = (String) ManagementFactory.getPlatformMBeanServer().invoke(
            new ObjectName("com.sun.management:type=DiagnosticCommand"), "gcClassHistogram",
            new Object[] { new String[0] }, new String[] { String[].class.getName() });   // forces a full GC!
        StringBuilder sb = new StringBuilder();
        for (String line : h.split("\n")) if (line.contains(filter)) sb.append(line.trim()).append('\n');
        return sb.toString();
    }

    static void handleRequests(int from, int to) {
        for (int i = from; i < to; i++) SESSIONS.put("s" + i, new Session("s" + i, new byte[512]));
    }

    public static void main(String[] args) throws Exception {
        handleRequests(0, 10_000);
        System.out.print("t0:\n" + histogramTop("LeakHunt$Session"));
        handleRequests(10_000, 30_000);
        System.out.print("t1:\n" + histogramTop("LeakHunt$Session"));
        System.out.println("=> instance count tripled while traffic was steady: unbounded growth from a static map");
    }
}
```

Output (verified; columns are rank, #instances, #bytes, class; the rank varies between runs):

```
t0:
6:         10000         240000  LeakHunt$Session
t1:
4:         30000         720000  LeakHunt$Session
=> instance count tripled while traffic was steady: unbounded growth from a static map
```

The `Session` record is 24 bytes (12 header + two 4-byte refs, padded). The real memory is in the 512-byte arrays it retains, which is why you need the **retained size** from a heap dump (MAT) and not just the shallow sizes the histogram prints.

---

## 11. Choosing and tuning — a decision procedure 🔥

```
1. Define SLOs: p99/p99.9 latency budget, throughput target, memory budget per instance.
2. Measure under production-like load with -Xlog:gc*,safepoint and JFR:
      allocation rate, promotion rate, live set, pause distribution, TTSP.
3. Size the heap: G1 ≈ live set × 3–4; ZGC ≈ live set × 2–3 (+ no compressed oops); keep < 32 GB or ≥ 48 GB.
4. Pick the collector:
      batch / offline throughput  → Parallel
      general service             → G1 (default); tune only MaxGCPauseMillis, region size, IHOP if needed
      p99.9 pause SLO < ~10 ms, CPU and memory headroom available → Generational ZGC
      low latency AND compressed-oops density, vendor ships it → Shenandoah (generational on 25+)
      tiny container (<= 1 vCPU, < 1 GB)  → Serial (explicitly), or G1 if latency matters
5. Re-measure. Change ONE flag at a time. Keep the GC logs from every experiment.
6. Reduce allocation before adding GC tuning: it's the only change that helps every collector.
```

---

## 12. Production failure modes & diagnostic checklist (GC)

| # | Failure | Signature | Root cause | Fix |
|---|---|---|---|---|
| 1 | **Full GC storms** (G1) | `Pause Full (G1 Compaction Pause)`, preceded by `Evacuation Failure` | Live set too big for the heap, marking started too late, humongous fragmentation | Heap or live-set fix; lower IHOP; bigger regions; more `ConcGCThreads` |
| 2 | **Premature promotion** | `Old regions` jump per young GC; mixed GCs constantly | Survivors overflow; medium-lived objects | Bigger heap/young gen (raise `MaxGCPauseMillis` slightly); reduce request-scoped retention |
| 3 | **Humongous churn** | Many `(G1 Humongous Allocation)` causes; `Humongous regions` large | Big short-lived buffers | `G1HeapRegionSize` ↑; streaming; buffer pooling |
| 4 | **ZGC allocation stalls** | `Allocation Stall (thread) N ms` | Not enough headroom or GC threads | Headroom, `ConcGCThreads`, `SoftMaxHeapSize`, reduce allocation |
| 5 | **Shenandoah degenerated/full GC** | `Pause Degenerated GC`, `Pause Full` | Same as above | Same; generational mode |
| 6 | **Long TTSP** | `Reaching safepoint` ≫ `At safepoint` | Non-polling loops (pre-JDK 10 or `-XX:-UseCountedLoopSafepoints`), page faults (swap, mmap), huge array copies | Remove swap; `AlwaysPreTouch`; investigate with `-Xlog:safepoint+stats` / JFR `jdk.SafepointBegin` |
| 7 | **Silent Serial GC** in containers | `Using Serial` in the `-Xlog:gc` startup line | < 2 CPUs or < ~1.8 GB visible (JDK ≤ 26) | Explicit `-XX:+UseG1GC`, or JDK 27 |
| 8 | **Metadata GC Threshold** full GCs at startup | GC cause `Metadata GC Threshold` | Metaspace HWM too low for a framework-heavy app | `-XX:MetaspaceSize=128m+` |
| 9 | **Explicit GC pauses** | `Pause Full (System.gc())` | RMI DGC (hourly), libraries calling `System.gc()`, `jmap -histo:live` | `-XX:+ExplicitGCInvokesConcurrent`; find the caller with JFR `jdk.GarbageCollection` + stack traces |
| 10 | **SoftReference cache thrash** | Old gen near full, frequent mixed or full GCs that clear many refs | Soft-reference caches | Bounded caches (Caffeine with size/weight limits) |
| 11 | **Reference-processing pauses** | Long `Post Evacuate`/`Remark` with `-Xlog:gc+ref=debug` showing millions of weak/phantom refs | Massive `WeakHashMap`/`ThreadLocal`/Cleaner use | Reduce reference objects; `ParallelRefProcEnabled` (default true) |
| 12 | **GC CPU starvation in containers** | Long concurrent phases, stalls | CPU limits throttle GC threads (CFS quota) | Raise CPU limits; `-XX:ActiveProcessorCount`; avoid tiny CPU quotas for ZGC |
| 13 | **Heap dump kills the pod** | Liveness probe fails during `HeapDumpOnOutOfMemoryError` | Dump takes minutes on a large heap | Dump to a fast volume; `ExitOnOutOfMemoryError`; tolerant probes; `jcmd GC.heap_dump -gz=1` |

**Command crib:**

```bash
jcmd <pid> GC.heap_info                          # current heap layout
jcmd <pid> GC.class_histogram | head -25         # live objects by class (FULL GC!)
jcmd <pid> GC.heap_dump -gz=1 /dumps/h.hprof.gz  # compressed heap dump (JDK 15+)
jcmd <pid> GC.run                                # System.gc() equivalent
jcmd <pid> VM.log output=file=/tmp/gc.log what=gc*  # enable GC logging at run time
jstat -gcutil <pid> 1000                         # per-second utilization (needs hsperfdata, see PerfDisableSharedMem)
jcmd <pid> JFR.start duration=120s filename=/tmp/gc.jfr settings=profile
jfr print --events jdk.GarbageCollection,jdk.GCPhasePause /tmp/gc.jfr | head
jfr summary /tmp/gc.jfr
```

---

## 13. Interview Q&A

<details><summary><b>Q1. 🔥 Explain G1's young, concurrent-mark and mixed phases, and what makes a young pause long.</b></summary>

Young GC is a STW parallel evacuation of all eden and survivor regions (the collection set): it scans roots and remembered sets, copies live objects to survivor/old regions, and frees the CSet. When old occupancy crosses the adaptive IHOP, a young GC also does the initial mark (Concurrent Start). Concurrent marking traces the heap using SATB, then a STW Remark (draining SATB, reference processing, class unloading), a concurrent RSet rebuild, and a STW Cleanup that ranks old regions by garbage. Mixed GCs then evacuate young regions plus a slice of the most garbage-dense old regions, up to `G1MixedGCCountTarget`. Young-pause length is driven by **surviving object volume**, **RSet and card scanning** (old→young pointers), **root counts**, and **reference processing**, not by eden size.
</details>

<details><summary><b>Q2. 🔥 Why are ZGC pauses independent of heap size, and what is the catch?</b></summary>

All heavy work (marking, relocation, reference updating, and since JDK 16 even thread-stack scanning) is concurrent. It is made safe by colored pointers with load barriers (and store barriers for generational remembered sets and SATB). The STW pauses only flip phases and take microseconds. The catches: higher CPU use (barriers plus concurrent threads), no compressed oops (larger heaps), and **allocation stalls** when allocation outpaces the concurrent GC, which are latency spikes that don't appear as "pauses". ZGC needs heap headroom.
</details>

<details><summary><b>Q3. ⚡ SATB vs incremental update: which collectors use which, and what is floating garbage?</b></summary>

SATB (G1, Shenandoah, Generational ZGC's store barrier) records the *old* value on reference overwrite, so everything reachable at mark start is retained. Incremental update (CMS) shades the *new* value stored into black objects and needs a re-scan at remark. SATB is simpler to terminate and cheaper at remark, but retains objects that died during marking until the next cycle; those are floating garbage.
</details>

<details><summary><b>Q4. 🔥 What is a humongous object in G1 and why can it cause full GCs?</b></summary>

An object ≥ ½ region size, allocated directly into contiguous old-gen regions. Short-lived humongous objects fragment old gen, waste region tails, and trigger concurrent cycles. If no contiguous free run exists, allocation can fail, leading to evacuation failure and Full GC. Mitigate with larger regions, streaming or chunking, and pooling.
</details>

<details><summary><b>Q5. 🔥 A service on JDK 21 in a 1-vCPU container shows 400 ms pauses. Why?</b></summary>

With fewer than 2 CPUs (or < ~1.8 GB memory) and no explicit GC flag, HotSpot ergonomics select **Serial GC**: single-threaded STW collections, whose full GCs scale with heap size. Check the startup line `Using Serial` (`-Xlog:gc`). Fix by explicitly setting `-XX:+UseG1GC` (and giving the pod ≥ 2 CPUs if possible). JDK 27 (JEP 523) makes G1 the default everywhere.
</details>

<details><summary><b>Q6. ⚡ What is time-to-safepoint and how do you detect a TTSP problem?</b></summary>

TTSP is the time from the VM requesting a safepoint until all Java threads reach a safepoint poll. GC pause metrics exclude it, so a GC can report 5 ms while the app stalled 500 ms. Enable `-Xlog:safepoint` and compare "Reaching safepoint" with "At safepoint", or use JFR `jdk.SafepointBegin`/`SafepointStateSynchronization`. Causes: loops without polls (rare since loop strip mining), page faults (swap, mmap), long-running intrinsics or array copies.
</details>

<details><summary><b>Q7. 🔥 Soft vs weak vs phantom references: when is each cleared, and why are SoftReference caches dangerous?</b></summary>

Weak: cleared at the first GC that finds the referent only weakly reachable. Soft: cleared only under memory pressure, with an LRU-ish policy based on free heap (`SoftRefLRUPolicyMSPerMB`), and guaranteed cleared before OOM. Phantom: enqueued after the referent is unreachable, and `get()` is always `null`; it is used for cleanup (`Cleaner`). Soft caches let the heap fill to near capacity before clearing, which causes frequent expensive collections and unpredictable latency. A bounded cache with explicit eviction is far better.
</details>

<details><summary><b>Q8. ⚡ Why is `finalize()` deprecated, and what replaces it?</b></summary>

Finalizers run on an unspecified thread at an unspecified time (possibly never), can resurrect objects, require an extra GC cycle to reclaim the object, slow allocation of finalizable objects, and serialize on a finalizer thread, so a slow finalizer leaks everything queued behind it. Replace with `try`-with-resources (`AutoCloseable`) for deterministic release, and `java.lang.ref.Cleaner` as a safety net (whose action must not reference the owner).
</details>

<details><summary><b>Q9. ⚡ What does `Pause Young (Concurrent Start) (G1 Humongous Allocation)` tell you?</b></summary>

A humongous allocation request pushed old occupancy over the IHOP, so G1 started a concurrent marking cycle, piggy-backed on this young GC. Frequent occurrences mean humongous churn. Check `gc+humongous=debug` and consider a larger region size.
</details>

<details><summary><b>Q10. 🔥 How would you prove a memory leak and find its root?</b></summary>

Watch the post-GC live-set floor over time (it rises with a leak and stays flat with an undersized heap). Take two class histograms minutes apart and find classes growing linearly. Capture a heap dump (on OOM or `jcmd GC.heap_dump`), then use MAT: the dominator tree by retained size, and Path to GC Roots excluding weak/soft refs to find the static/ThreadLocal/cache holding it. JFR `OldObjectSample` with path-to-GC-roots can show leak candidates with allocation stacks without a full dump.
</details>

<details><summary><b>Q11. 🧊 Why did G1's write barrier get cheaper in JDK 26?</b></summary>

JEP 522 replaced the dirty-card-queue mechanism (mutator threads enqueueing cards for refinement threads, with synchronization) with two card tables that the mutator and refinement swap. The post-write barrier becomes simpler, and contention between application and refinement threads drops, which improves throughput for reference-store-heavy code.
</details>

<details><summary><b>Q12. ⚡ What's the right first response when someone says "GC is slow, add flags"?</b></summary>

Measure first: GC logs plus safepoint logs plus JFR. Quantify allocation rate, promotion rate, live set, pause percentiles and TTSP. Most problems are an undersized heap, a leak, humongous churn, or allocation hotspots. Remove legacy flags, fix allocation, then size the heap, and only then consider collector changes. Change one variable at a time.
</details>

---

## 14. Further reading

* HotSpot Virtual Machine Garbage Collection Tuning Guide (JDK 25): <https://docs.oracle.com/en/java/javase/25/gctuning/>
* JEP 439 Generational ZGC: <https://openjdk.org/jeps/439>. Per Lidén and Stefan Karlsson's ZGC talks.
* Shenandoah wiki: <https://wiki.openjdk.org/display/shenandoah/Main>
* Thomas Schatzl's G1 blog (tschatzl.github.io): per-release G1 changes.
* "The Garbage Collection Handbook" (Jones, Hosking, Moss), 2nd ed. 2023, the theory reference.
