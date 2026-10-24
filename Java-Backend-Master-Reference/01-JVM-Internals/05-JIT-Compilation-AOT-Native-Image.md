# 1.5 · JIT Compilation (Interpreter, C1, C2), Escape Analysis, Deoptimization & AOT (Leyden, Native Image)

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** HotSpot source (`compilationPolicy.cpp`, `escape.cpp`, `bytecodeInfo.cpp`), JEP 197 (segmented code cache), JEP 243 (JVMCI), JEP 410 (removal of experimental AOT/Graal JIT), JEP 483/514/515/516 (Leyden AOT cache), GraalVM Native Image docs, Shipilëv's "JVM Anatomy Quarks", Cliff Click's C2 talks.
> **Every log and number here was produced on Temurin 25.0.4.1 (Windows x64, 12 CPUs).** Timings are indicative, single-machine runs. Use JMH (Pillar 8) for real benchmarks.

---

## 1. The execution pipeline 🔥

```
 .java ──javac──► bytecode (portable, stack-based, ~200 opcodes)
                       │
                       ▼
          ┌─────────────────────────────┐
 tier 0   │ TEMPLATE INTERPRETER        │  machine-code templates per bytecode, generated at VM start;
          │ + invocation & back-edge    │  profiling counters per method
          │   counters                  │
          └──────────────┬──────────────┘
                         │ hot (Tier3InvocationThreshold=200 calls, or loop back-edges)
                         ▼
 tier 3   ┌─────────────────────────────┐  fast compile, light optimization, FULL PROFILING:
          │ C1 (client compiler)        │  branch counts, receiver types (TypeProfileWidth=2), null_seen…
          └──────────────┬──────────────┘
                         │ very hot (Tier4InvocationThreshold=5000 / Tier4CompileThreshold=15000)
                         ▼
 tier 4   ┌─────────────────────────────┐  slow compile, aggressive SPECULATIVE optimization using the
          │ C2 (server compiler)        │  profile: inlining, escape analysis, loop opts, vectorization,
          └──────────────┬──────────────┘  intrinsics; guarded by UNCOMMON TRAPS
                         │ speculation wrong (unexpected type/branch/null, class loaded)
                         ▼
                 DEOPTIMIZATION ──► back to the interpreter (tier 0) ──► re-profile ──► recompile
```

### 1.1 Tiered compilation levels

| Level | Compiler | Profiling | When |
|---|---|---|---|
| 0 | Interpreter | Full counters | Start |
| 1 | C1 | **None** | Trivial methods (getters, constant returns): C2 wouldn't do better, so stop here |
| 2 | C1 | Invocation and back-edge counters only | C2 queue is long; temporary |
| 3 | C1 | **Full** (branches, types, call sites) | The normal path to C2 |
| 4 | C2 | None (uses the tier 3 profile) | Hot code |

**Common transitions:** `0 → 3 → 4` (normal), `0 → 2 → 3 → 4` (C2 backlog), `0 → 3 → 1` (trivial), `4 → 0` (deopt).

**Defaults (JDK 25, verified with `-XX:+PrintFlagsFinal`):** `Tier3InvocationThreshold=200`, `Tier3CompileThreshold=2000`, `Tier3BackEdgeThreshold=60000`, `Tier4InvocationThreshold=5000`, `Tier4CompileThreshold=15000`, `Tier4BackEdgeThreshold=40000`. `CICompilerCount=4` here (ergonomic, scaled with CPU count, split 1:2 between C1 and C2).

### 1.2 Reading `-XX:+PrintCompilation` (real output)

```
 timestamp  compile-id  flags  tier  method                              size      event
     62        28                3   Dispatch$Circle::area (14 bytes)
     62        29                4   Dispatch$Circle::area (14 bytes)
     62        28                3   Dispatch$Circle::area (14 bytes)    made not entrant: not used   ← tier-3 code retired by tier 4
     63        30         %      3   Dispatch::total @ 11 (42 bytes)                                ← OSR compile at bytecode 11 (loop)
     64        31                3   Dispatch::total (42 bytes)
     64        32         %      4   Dispatch::total @ 11 (42 bytes)
     67        32         %      4   Dispatch::total @ 11 (42 bytes)   made not entrant: uncommon trap  ← speculation failed
     67        33         %      4   Dispatch::total @ 11 (42 bytes)                                ← recompiled
     70        34                4   Dispatch::total (42 bytes)
```

Flags column: `%` = **OSR** (on-stack replacement: a long-running loop in an interpreted frame jumps into compiled code mid-loop), `s` = synchronized, `!` = has exception handlers, `n` = native wrapper, `b` = blocking compile.

> **OSR caveat:** OSR-compiled code is entered mid-method and is often less optimized than a normal compile. Microbenchmarks that put all the work in one big `main` loop measure **OSR code**, which is one of many reasons to use JMH.

---

## 2. Inlining — "the mother of all optimizations" 🔥

Inlining removes call overhead, but more importantly it **exposes the callee's body to the caller's optimizations**: escape analysis, constant folding, range-check elimination and vectorization all work within the inlined scope.

| Rule | Default | Meaning |
|---|---|---|
| `MaxInlineSize` | 35 bytecode bytes | Always consider inlining methods up to this size (even if cold) |
| `FreqInlineSize` | 325 bytecode bytes | Max size for **hot** call sites |
| `InlineSmallCode` | 2500 bytes of *native* code | Don't inline a callee whose already-compiled body is larger |
| `MaxInlineLevel` | 15 (raised from 9 in JDK 14) | Max nesting depth |
| `MaxRecursiveInlineLevel` | 1 | Recursion inlining depth |

**Consequences:** small methods are free, so write them. Giant "god methods" (> 325 bytes of bytecode) don't get inlined into their callers. The big `switch` in a hand-written parser often sits right at the threshold, which is why refactoring a hot method into smaller pieces can make it *faster*.

### 2.1 Call-site polymorphism: monomorphic, bimorphic, megamorphic 🔥

C2 inlines virtual and interface calls **speculatively** using the receiver-type profile collected at tier 3 (`TypeProfileWidth=2`):

| Profile at call site | What C2 emits | Cost |
|---|---|---|
| **Monomorphic** (1 type seen) | Type guard + inlined body; uncommon trap on a mismatch | ≈ direct call, fully optimizable |
| CHA-proven single implementor (class hierarchy analysis) | Inlined with **no guard**, plus a *dependency*: loading a new subclass deoptimizes it | ≈ static call |
| **Bimorphic** (2 types) | Two guards + two inlined bodies | Small overhead |
| **Megamorphic** (3+ types) | Real `vtable`/`itable` dispatch, **no inlining** | Call overhead + lost optimizations (EA, etc.) |

**Measured (one call site, `shapes[i].area()` over 1M elements, JDK 25):**

```
1 receiver type(s): 1.35 ns/call
2 receiver type(s): 1.35 ns/call
3 receiver type(s): 2.71 ns/call      ← megamorphic: 2× slower here; worse when inlining would have enabled EA
4 receiver type(s): 3.03 ns/call
```

**`-XX:+UnlockDiagnosticVMOptions -XX:+PrintInlining` shows the decision (real lines):**

```
1 type:   @ 27   Dispatch$Circle::area (14 bytes)   inline (hot)   \-> TypeProfile (40960/40960 counts) = Dispatch$Circle
3 types:  @ 27   Dispatch$Shape::area (0 bytes)   failed to inline: virtual call
```

The source of this experiment (copy and run it with `java Dispatch.java 3`):

<!-- run: args="3" -->
```java
public class Dispatch {
    interface Shape { double area(); }
    record Circle(double r) implements Shape { public double area() { return 3.14159 * r * r; } }
    record Square(double s) implements Shape { public double area() { return s * s; } }
    record Rect(double w, double h) implements Shape { public double area() { return w * h; } }
    record Tri(double b, double h) implements Shape { public double area() { return 0.5 * b * h; } }

    static double total(Shape[] shapes) {           // ONE call site: shapes[i].area()
        double t = 0;
        for (Shape s : shapes) t += s.area();
        return t;
    }

    static Shape[] make(int kinds, int n) {
        Shape[] a = new Shape[n];
        for (int i = 0; i < n; i++) a[i] = switch (i % kinds) {
            case 0 -> new Circle(1); case 1 -> new Square(2); case 2 -> new Rect(1, 2); default -> new Tri(2, 2);
        };
        return a;
    }

    public static void main(String[] args) {
        int kinds = Integer.parseInt(args[0]);
        Shape[] data = make(kinds, 1 << 20);
        for (int i = 0; i < 50; i++) total(data);     // warm-up: the profile sees `kinds` receiver types
        long best = Long.MAX_VALUE; double sink = 0;
        for (int i = 0; i < 20; i++) { long s = System.nanoTime(); sink += total(data); best = Math.min(best, System.nanoTime() - s); }
        System.out.printf("%d receiver type(s): %.2f ns/call  (sink %.0f)%n", kinds, best / (double) (1 << 20), sink);
    }
}
```

### 2.2 Profile pollution — why "the same code" is slower in production 🧊

The type profile is **per bytecode call site, not per caller**. A shared utility method that dispatches on an interface (`Function.apply` inside a generic helper, `Comparator.compare` inside a sort, a stream operation inside the JDK's `ReferencePipeline`) sees *every* type used anywhere in the application. In a microbenchmark it's monomorphic and blazing fast. In production, with 30 different lambdas flowing through it, it's megamorphic. Mitigations:

* Keep hot inner loops free of megamorphic dispatch. Specialize them by hand (separate methods per type), or use a `sealed` hierarchy plus a pattern `switch`, which compiles to type tests that C2 handles well.
* Since this depends on the whole application, **profile the real application** (async-profiler, JFR), not a microbenchmark.

---

## 3. Speculation, uncommon traps and deoptimization 🔥

C2 compiles for **the behaviour it has seen** and plants **uncommon traps** where its assumptions could break:

| Speculation | Trap reason (in logs) |
|---|---|
| Branch never taken | `unstable_if` |
| Receiver always type X | `class_check` / `bimorphic` |
| Value never null | `null_check` / `null_assert` |
| Array index always in range | `range_check` |
| Class not yet loaded at compile time | `unloaded` / `uninitialized` |
| Only one implementor (CHA) | dependency invalidation on class load |

### 3.1 Runnable: watch a deoptimization happen

<!-- run: -->
```java
public class Deopt {
    static int classify(int x) {
        if (x < 0) return -1;            // never taken during warm-up → C2 replaces this branch with an uncommon trap
        return x & 7;
    }

    public static void main(String[] args) {
        long s = 0;
        for (int i = 0; i < 5_000_000; i++) s += classify(i);
        System.out.println("warm, now sending a negative value...");
        s += classify(-5);               // trap → deoptimize → interpreter → re-profile → recompile
        for (int i = 0; i < 5_000_000; i++) s += classify(i - 100);
        System.out.println("done " + s);
    }
}
```

Real output with `javac Deopt.java && java -XX:+PrintCompilation -Xlog:deoptimization=debug -cp . Deopt` (filtered):

```
47   11       3       Deopt::classify (11 bytes)
47   12       4       Deopt::classify (11 bytes)
warm, now sending a negative value...
[0.054s][debug][deoptimization] cid=  12     level=4 Deopt.classify(I)I trap_bci=1 unstable_if reinterpret pc=0x000001f2bbb20cc0
53   12       4       Deopt::classify (11 bytes)   made not entrant: uncommon trap
53   16       3       Deopt::classify (11 bytes)                       ← back to tier 3 to re-profile, C2 recompiles later
```

* `trap_bci=1` is the `if` bytecode. `unstable_if` is the reason, and `reinterpret` is the action (discard the code and re-profile).
* **"made not entrant"**: new calls can't enter the old code. Frames already executing it are deoptimized lazily. The nmethod is freed later.
* **Deopt is expensive**: frames must be rebuilt as interpreter frames from debug info, and the method then runs interpreted until recompiled. A few deopts are normal. Thousands are a **deopt storm**: check JFR `jdk.Deoptimization` events.
* `PerMethodTrapLimit=100` and `PerBytecodeTrapLimit=4` stop C2 from repeatedly speculating on a site that keeps trapping; it then compiles the general path.

### 3.2 The `OmitStackTraceInFastThrow` production gotcha 🔥

When an **implicit** exception (NPE from a null dereference, `ArithmeticException` from `/ 0`, `ArrayIndexOutOfBoundsException`, `ClassCastException`, `ArrayStoreException`) is thrown repeatedly from the same compiled site, C2 recompiles that site to throw a **preallocated exception without a stack trace** (`OmitStackTraceInFastThrow=true` by default). Your logs then show:

```
java.lang.NullPointerException
        (no stack trace, no message)
```

after the first few thousand occurrences. **Fix while debugging:** `-XX:-OmitStackTraceInFastThrow`. **Real fix:** search the logs for the *earliest* occurrences, which still have traces.

---

## 4. Escape analysis (EA) and scalar replacement 🔥

C2's EA classifies each allocation site:

| Escape state | Meaning | Optimization |
|---|---|---|
| **NoEscape** | Object never leaves the compiled method (after inlining) | **Scalar replacement**: no allocation; fields become locals or registers. **Lock elision** on it |
| **ArgEscape** | Passed as an argument to a callee that doesn't let it escape (not inlined, but analysable) | Lock elision possible; allocation stays |
| **GlobalEscape** | Stored to a static or heap field, returned, thrown, or passed to an unknown callee | None |

HotSpot C2 does **not** stack-allocate. It **scalar-replaces**, which is better when it works: the object vanishes entirely.

### 4.1 Runnable: EA removing 960 MB of allocation

<!-- run: -->
```java
import java.lang.management.ManagementFactory;

public class EscapeDemo {
    record Point(double x, double y) {
        Point plus(Point o) { return new Point(x + o.x, y + o.y); }
        double norm2() { return x * x + y * y; }
    }

    static double work(int n) {
        double acc = 0;
        for (int i = 0; i < n; i++) {
            Point p = new Point(i, i + 1);           // never escapes `work`
            Point q = p.plus(new Point(1, 1));       // neither do these, once plus() is inlined
            acc += q.norm2();
        }
        return acc;
    }

    public static void main(String[] args) {
        var mx = (com.sun.management.ThreadMXBean) ManagementFactory.getThreadMXBean();
        for (int i = 0; i < 20; i++) work(100_000);   // warm-up: let C2 compile work() with inlining
        long before = mx.getCurrentThreadAllocatedBytes();
        double r = work(10_000_000);
        long bytes = mx.getCurrentThreadAllocatedBytes() - before;
        System.out.printf("allocated %,d bytes for 10M iterations (%.2f bytes/iter) result=%.3e%n", bytes, bytes / 1e7, r);
    }
}
```

Output (verified; three separate runs with different flags):

```
java EscapeDemo.java                         → allocated 0 bytes for 10M iterations (0.00 bytes/iter)
java -XX:-DoEscapeAnalysis EscapeDemo.java   → allocated 960,000,000 bytes for 10M iterations (96.00 bytes/iter)
java -Xint EscapeDemo.java                   → allocated 960,000,000 bytes for 10M iterations (96.00 bytes/iter)
```

Three `Point`s × 32 bytes (12-byte header, 4-byte gap, two `double`s) = 96 bytes per iteration, or **zero** once C2 scalar-replaces them. This is why "records/value objects are expensive" is often wrong in hot, inlined code. It is also why the same code allocates heavily in the interpreter and in C1-compiled code.

### 4.2 Where EA fails (measured on JDK 25)

<!-- run: jvm="-XX:CompileCommand=quiet -XX:CompileCommand=dontinline,EscapeLimits::sink" -->
```java
import java.lang.management.ManagementFactory;

public class EscapeLimits {
    record Point(double x, double y) {}
    static Point lastSeen;                                         // a global escape target

    static double noEscape(int n) { double a = 0; for (int i = 0; i < n; i++) { Point p = new Point(i, 1); a += p.x() + p.y(); } return a; }
    static double globalEscape(int n) { double a = 0; for (int i = 0; i < n; i++) { Point p = new Point(i, 1); if ((i & 1023) == 0) lastSeen = p; a += p.x(); } return a; }
    static double mergeEscape(int n) { double a = 0; for (int i = 0; i < n; i++) { Point p = (i & 1) == 0 ? new Point(i, 1) : new Point(1, i); a += p.x(); } return a; }
    static double notInlined(int n) { double a = 0; for (int i = 0; i < n; i++) { Point p = new Point(i, 1); a += sink(p); } return a; }
    static double sink(Point p) { return p.x(); }                 // excluded from inlining via CompileCommand
    static double smallArray(int n) { double a = 0; for (int i = 0; i < n; i++) { long[] t = new long[8]; t[i & 7] = i; a += t[(i + 1) & 7]; } return a; }
    static double smallArrayConst(int n) { double a = 0; for (int i = 0; i < n; i++) { long[] t = new long[8]; t[0] = i; t[7] = 2L * i; a += t[0] + t[7]; } return a; }
    static double bigArray(int n) { double a = 0; for (int i = 0; i < n; i++) { long[] t = new long[128]; t[i & 127] = i; a += t[(i + 1) & 127]; } return a; }

    interface Work { double run(int n); }
    static void measure(String name, Work w) {
        var mx = (com.sun.management.ThreadMXBean) ManagementFactory.getThreadMXBean();
        for (int i = 0; i < 30; i++) w.run(100_000);
        long before = mx.getCurrentThreadAllocatedBytes();
        w.run(1_000_000);
        System.out.printf("%-38s %7.1f bytes/iter%n", name, (mx.getCurrentThreadAllocatedBytes() - before) / 1e6);
    }

    public static void main(String[] args) {
        measure("no escape", EscapeLimits::noEscape);
        measure("escapes to static field (1 in 1024)", EscapeLimits::globalEscape);
        measure("merge of two allocations (phi)", EscapeLimits::mergeEscape);
        measure("passed to non-inlined method", EscapeLimits::notInlined);
        measure("long[8], variable index", EscapeLimits::smallArray);
        measure("long[8], constant indices", EscapeLimits::smallArrayConst);
        measure("long[128] (> 64 elements)", EscapeLimits::bigArray);
    }
}
```

Output (verified):

```
no escape                                  0.0 bytes/iter
escapes to static field (1 in 1024)       32.0 bytes/iter   ← NO partial EA in C2: a rare escape path kills it for ALL iterations
merge of two allocations (phi)             0.0 bytes/iter   ← handled in recent JDKs (C2 ReduceAllocationMerges, on by default)
passed to non-inlined method              32.0 bytes/iter   ← EA is only as good as inlining
long[8], variable index                   80.0 bytes/iter   ← arrays scalar-replace only with constant indices
long[8], constant indices                  0.0 bytes/iter
long[128] (> 64 elements)               1040.0 bytes/iter   ← EliminateAllocationArraySizeLimit=64
```

**Practical rules for EA-friendly hot paths:**

1. Keep temporary objects **local** and their methods **small** (inlinable).
2. Don't let a rare path (logging, an error branch, debug capture) store the object anywhere. Copy the fields instead.
3. Avoid variable-indexed small temp arrays in hot loops. Use locals.
4. Don't trust EA across megamorphic calls, very large methods, or deep inlining chains (`MaxInlineLevel=15`).
5. GraalVM's compiler (Native Image, or Oracle GraalVM JIT where available) does **partial escape analysis**, which handles case 2. That is one of its historical advantages.

### 4.3 Lock elision and coarsening

* **Lock elision:** `synchronized` on a NoEscape or ArgEscape object is removed (`EliminateLocks=true`). Example: a local `StringBuffer` or `Vector` that never escapes.
* **Lock coarsening:** adjacent `synchronized(x)` blocks on the same object are merged, reducing acquire/release pairs (`EliminateNestedLocks`).
* Neither works on objects that escape, so don't rely on them for shared objects.

---

## 5. Other C2 optimizations worth knowing ⚡

| Optimization | What it does | Why you care |
|---|---|---|
| **Intrinsics** (`@IntrinsicCandidate`) | Replace a Java method with hand-written assembly or IR: `System.arraycopy`, `Arrays.equals/mismatch/fill`, `String.indexOf/equals/compareTo`, `Math.*`, `Integer.bitCount/numberOfLeadingZeros`, `CRC32/CRC32C`, AES/GHASH/SHA, `BigInteger.multiplyToLen`, `Object.hashCode`, `Thread.onSpinWait` | Use the JDK methods; a hand-written loop is usually slower. Inspect with `-XX:+UnlockDiagnosticVMOptions -XX:+PrintIntrinsics` |
| **Range-check elimination / loop predication** | Hoist array bounds checks out of loops | Simple counted loops over arrays run at native speed |
| **Loop unrolling, peeling, unswitching** | Reduce loop overhead and hoist invariant branches | — |
| **SuperWord auto-vectorization** (`UseSuperWord`) | SIMD for simple array loops | `sum int[2M] → 0 ms` in [1.3](03-Object-Layout-Mechanical-Sympathy.md#62-runnable-locality-measured). For explicit SIMD there is the Vector API (incubator through JDK 27) |
| **Constant folding of `static final`** | `static final` fields (and `@Stable` JDK-internal arrays, record fields, hidden-class fields) are folded into code | `static final MethodHandle`/`VarHandle`/config constants become free. **Instance** `final` fields are *not* trusted (`TrustFinalNonStaticFields=false`) because reflection can change them; JEP 500 (JDK 26) starts the path to "final means final" |
| **Implicit null checks** | No explicit test: a null dereference triggers SIGSEGV and the signal handler converts it to an NPE | Free null checks until nulls actually happen, then an uncommon trap and recompile |
| **Dead-code elimination (DCE)** | Removes computations whose results are unused | **The #1 microbenchmark lie**: a loop whose result is never consumed is compiled away. JMH `Blackhole` exists for this |
| **GVN / CSE** | Global value numbering, common sub-expression elimination | — |

---

## 6. Code cache & compiler threads ⚡

* Segmented code cache: **non-nmethods** (interpreter, stubs, adapters), **profiled** (tier 2/3), **non-profiled** (tier 1/4). `ReservedCodeCacheSize=240M` with tiered compilation. Inspect with `jcmd <pid> Compiler.codecache` and the `CodeHeap '…'` memory pools ([1.2 §6](02-Runtime-Data-Areas-Off-Heap-FFM.md#6-code-cache-symbol-table-string-table-)).
* `jcmd <pid> Compiler.queue` shows what's waiting. A persistently long queue means compiler threads are starved: common in 1-CPU containers, where compiler threads compete with app threads during warm-up.
* `-XX:CICompilerCount=N` overrides ergonomics. `-XX:TieredStopAtLevel=1` (C1 only) gives faster startup and lower peak: good for short-lived CLIs, bad for services.

---

## 7. JIT diagnostics toolkit

```bash
-XX:+PrintCompilation                                   # tiers, OSR, deopts (stdout)
-XX:+UnlockDiagnosticVMOptions -XX:+PrintInlining       # inlining decisions + reasons
-XX:+UnlockDiagnosticVMOptions -XX:+LogCompilation -XX:LogFile=jit.xml   # → JITWatch (visual)
-XX:+UnlockDiagnosticVMOptions -XX:+PrintAssembly        # needs the hsdis plugin; JMH -prof perfasm
-Xlog:deoptimization=debug                               # every uncommon trap with reason/action
-XX:CompileCommand=dontinline,com.acme.Foo::bar          # experiments (also: exclude, inline, print, quiet)
jcmd <pid> Compiler.codecache | Compiler.codelist | Compiler.queue
jcmd <pid> Compiler.directives_add directives.json      # per-method compiler options at run time
JFR events: jdk.Compilation (slow compiles), jdk.Deoptimization, jdk.CodeCacheFull, jdk.CompilerStatistics
```

---

## 8. Warm-up: the JIT's operational cost 🔥

A freshly started JVM runs interpreted code, then C1 code, then (seconds to minutes later) C2 code. For services that **autoscale** or **deploy frequently**, warm-up shows up as:

* high p99 latency for the first N thousand requests,
* CPU spikes (the compiler threads plus slow code) that can trip autoscalers into a feedback loop,
* timeouts during rolling deploys.

| Strategy | How | Notes |
|---|---|---|
| Synthetic warm-up before readiness | Run representative requests internally, then flip the readiness probe | Cheap and effective; beware side effects |
| **Leyden AOT cache** (JDK 24+) | Training run → `-XX:AOTCache` | Classes pre-loaded/linked; **JEP 515 (JDK 25) stores method profiles**, so C2 compiles hot methods sooner |
| CRaC | Checkpoint a warmed JVM, restore | Fastest "warm" start; vendor-specific; snapshot hygiene (secrets, sockets) |
| Native Image | No warm-up (already compiled) | But a lower peak without PGO |
| More CPU at startup | K8s CPU limits above requests, or burstable CPU | Compiler threads need cycles |

---

## 9. AOT in 2026: Leyden AOT cache vs GraalVM Native Image vs CRaC 🔥

### 9.1 Leyden AOT cache, measured

A small JDK-only app (HTTP client, streams, records, `java.time`, regex, a virtual-thread executor) packaged as `app.jar`:

```bash
java -XX:AOTCacheOutput=app.aot -jar app.jar        # JDK 25 one-step training (JEP 514)
#   Reading AOTConfiguration app.aot.config and writing AOTCache app.aot
#   AOTCache creation is complete: app.aot 22478848 bytes
java -XX:AOTCache=app.aot -jar app.jar              # production run
```

Best-of-7 wall-clock startup on this laptop:

| Mode | Startup |
|---|---|
| `-Xshare:off` (no CDS) | 846 ms |
| Default CDS archive | 743 ms |
| **AOT cache** | **624 ms (−16% vs CDS, −26% vs no CDS)** |

That's for a tiny app. Gains grow with class count: JEP 483 reports **4.486 s → 2.604 s (−42%)** for Spring PetClinic. A **mismatched class path** is detected and the cache ignored. The app still runs, because the default `AOTMode=auto` only logs:

```
[0.028s][warning][aot] The name of app classpath [1] does not match: expected 'app.jar', got 'classes'
[0.028s][error  ][aot] shared class paths mismatch (hint: enable -Xlog:class+path=info to diagnose the failure)
```

In CI, use `-XX:AOTMode=on` so a stale cache **fails the build** instead of silently giving up the speed-up.

### 9.2 GraalVM Native Image fundamentals

* **Closed-world assumption:** at build time, points-to analysis starts from `main` and finds all reachable code. Anything reached only reflectively must be **declared** (reachability metadata: reflection, resources, proxies, JNI, serialization). The tracing agent (`-agentlib:native-image-agent`) and the shared GraalVM reachability-metadata repository help.
* **Build-time initialization:** selected classes run `<clinit>` at build time, and the resulting objects are snapshotted into the **image heap**, giving near-instant startup.
* **Runtime:** Substrate VM, a minimal runtime. GC: Serial by default in Community Edition, plus Epsilon. Oracle GraalVM adds G1 on Linux.
* **Trade-offs:** startup in **tens of ms**, low RSS, no warm-up, but long builds (minutes, GBs of RAM), a separate test matrix, lower peak throughput than C2 unless you use PGO, and **no dynamic class loading** (agents and runtime bytecode generation need build-time alternatives). Spring Boot 3+/4 has first-class AOT processing for it.
* **Status note (Oct 2026):** in September 2025 Oracle announced that GraalVM for JDK 24 was the last GraalVM release licensed as part of Java SE products, and discontinued the experimental Graal JIT option in Oracle JDK. GraalVM Community Native Image releases have continued (25.x line in 2026), and OpenJDK's startup/footprint work is in **Project Leyden**. Check graalvm.org for current licensing and roadmap before standardizing on it.

### 9.3 Decision table

| Need | Pick |
|---|---|
| Long-running service, peak throughput matters, faster restarts wanted | **JIT + Leyden AOT cache** |
| Scale-to-zero / serverless / CLI, < 100 ms cold start, small RSS | **Native Image** (accept the closed world) |
| Instant "already warm" restart, Linux, vendor JDK OK | **CRaC** |
| Batch jobs | Plain JIT (maybe `-XX:TieredStopAtLevel=1` for very short ones) |

---

## 10. Production failure modes & diagnostic checklist (JIT)

| Symptom | Cause | Diagnose | Fix |
|---|---|---|---|
| p99 terrible for minutes after each deploy | Warm-up (interpreter/C1), compiler threads starved | JFR `jdk.Compilation`, `Compiler.queue`, CPU throttling metrics | Warm-up traffic; AOT cache with profiles (25+); more CPU at startup |
| Sudden permanent slowdown after hours | **Code cache full** → compilation disabled | Log `CodeCache is full. Compiler has been disabled.`, `Compiler.codecache` | `ReservedCodeCacheSize` ↑; find generated-code explosions or deopt loops |
| Periodic CPU spikes and latency blips | **Deopt storms**: CHA invalidation as plugins load classes, flip-flopping type profiles | JFR `jdk.Deoptimization`, `-Xlog:deoptimization` | Stabilize class loading at startup; reduce megamorphic hot sites |
| Fast in benchmark, slow in prod | Profile pollution or megamorphism; benchmark measured OSR/DCE artifacts | async-profiler on prod; `PrintInlining` "virtual call" | JMH done right; specialize hot paths |
| `NullPointerException` with no stack trace | `OmitStackTraceInFastThrow` | Look for the earliest occurrences | `-XX:-OmitStackTraceInFastThrow` while debugging |
| Throughput drop after enabling an agent | Agent retransformation forces deopt/recompile; instrumentation blocks inlining (bytecode size grows) | JFR, agent docs | Limit instrumented scope; use JFR events instead of bytecode agents (JDK 25 JEP 520 method timing) |
| Allocation-heavy flame graph after a "harmless" refactor | EA broken by a new escape path (logging, a field store) or by a callee no longer inlinable | JFR allocation profile; `-XX:+PrintEscapeAnalysis` (debug builds) or compare allocation bytes | Restore locality; split methods |
| Native Image works in tests, fails in prod with `ClassNotFoundException`/`MissingReflectionRegistrationError` | Undeclared reflection or resource | Run the tracing agent over prod-like paths | Add reachability metadata; Spring AOT hints |

---

## 11. Interview Q&A

<details><summary><b>Q1. 🔥 Explain tiered compilation, its levels, and why C1 profiles before C2 compiles.</b></summary>

Level 0 is the interpreter. Levels 1–3 are C1 (1 = no profiling, for trivial methods; 2 = counters only, used when C2 is backlogged; 3 = full profiling), and level 4 is C2. The normal path is 0→3→4. C1 compiles quickly and gives decent code early, while gathering the branch, type and null profiles that C2 needs for speculative optimizations (type-guarded inlining, pruning untaken branches). C2 produces much faster code but compiles slowly and relies on that profile.
</details>

<details><summary><b>Q2. 🔥 What is deoptimization? Give three triggers.</b></summary>

Discarding compiled code whose speculative assumptions no longer hold, and continuing execution in the interpreter by reconstructing interpreter frames from the compiled frame's debug info. Triggers: an uncommon trap (an unseen branch, receiver type or null), class loading that invalidates a CHA dependency (a new subclass overriding a method assumed monomorphic), and explicit invalidation (redefinition by an agent, `MethodHandle` call-site target change). The compiled method is marked "not entrant" and later recompiled with the updated profile.
</details>

<details><summary><b>Q3. 🔥 What is a megamorphic call site and how does it hurt performance beyond the call itself?</b></summary>

A virtual or interface call site whose profile has seen more than two receiver types (`TypeProfileWidth=2`). C2 can't inline it speculatively, so it emits a vtable or itable dispatch. Besides the indirect call, the callee's body isn't visible to the caller's optimizer: no escape analysis of arguments, no constant propagation, no loop optimizations across the call. In the measured demo a 3-type site was ~2× slower per call. In realistic code the lost EA and loop optimizations often cost more.
</details>

<details><summary><b>Q4. 🔥 What does escape analysis do in HotSpot, and when does it fail?</b></summary>

It determines whether an allocation escapes the compiled method (after inlining). NoEscape objects are scalar-replaced, meaning no heap allocation and fields in registers, and locks on them are elided. It fails when the object escapes on *any* path (C2 has no partial EA, so a rare branch storing it to a field kills the optimization), when it's passed to a non-inlined callee, for arrays with non-constant indices or more than 64 elements, and when inlining limits stop the analysis. Measured: 0 vs 96 bytes/iteration with EA on vs off.
</details>

<details><summary><b>Q5. ⚡ What is OSR and why does it matter for benchmarks?</b></summary>

On-stack replacement compiles a hot loop and transfers a running interpreted frame into compiled code mid-loop (`%` in PrintCompilation). Code compiled this way is often less optimized than a normal method entry compile (for example, loop-invariant facts established before the loop aren't known). Naive benchmarks that time one giant loop in `main` measure OSR code. JMH avoids this by calling the benchmark method repeatedly.
</details>

<details><summary><b>Q6. ⚡ Why do production NPE logs sometimes have no stack trace?</b></summary>

`-XX:+OmitStackTraceInFastThrow` (the default): after a compiled site throws the same implicit exception repeatedly, C2 recompiles it to throw a preallocated exception without a stack trace, for speed. Disable it with `-XX:-OmitStackTraceInFastThrow` while debugging, or find the first occurrences in the logs.
</details>

<details><summary><b>Q7. ⚡ What does the Leyden AOT cache store and how is it different from Native Image?</b></summary>

It stores the state of a training run: classes loaded and linked (constant-pool entries resolved, lambda and indy sites linked) in JDK 24, method execution profiles in JDK 25 (JEP 515), and heap objects with any GC in JDK 26 (JEP 516). The production JVM maps this and skips that work, keeping full JIT, dynamic class loading and peak performance. It requires the same JDK, OS, architecture and a compatible class path, and otherwise is ignored with a warning. Native Image compiles a closed world ahead of time into a standalone executable: much faster startup and lower memory, but no dynamic class loading without metadata, and a lower peak without PGO.
</details>

<details><summary><b>Q8. 🧊 Why is a `static final MethodHandle` fast but a non-final `MethodHandle` field slow?</b></summary>

C2 constant-folds `static final` fields. A constant `MethodHandle` lets the JIT see through the handle's LambdaForm chain to the target method and inline it like a direct call. A handle loaded from a mutable field is opaque at compile time, so every `invokeExact` goes through the generic invocation path. The same applies to `VarHandle`s.
</details>

<details><summary><b>Q9. 🔥 How do you diagnose "the service is slow for 2 minutes after every deploy"?</b></summary>

Confirm it's warm-up: CPU is high in compiler threads (JFR `jdk.Compilation`, `jcmd Compiler.queue`), and latency improves as compilations complete. Check CPU throttling (cgroup `cpu.stat` `nr_throttled`), since starved compiler threads prolong warm-up. Mitigate with a warm-up phase before readiness, a Leyden AOT cache with training profiles (25+), more CPU during startup, or CRaC/Native Image when the constraints allow.
</details>

<details><summary><b>Q10. 🧊 Name four optimizations that depend on inlining.</b></summary>

Escape analysis and scalar replacement (allocation must be visible), constant folding and propagation across call boundaries, range-check elimination and loop optimizations in callers' loops, and lock elision or coarsening on objects passed to callees. Speculative type-based optimizations also depend on the callee being inlined.
</details>

---

## 12. Further reading

* Aleksey Shipilëv, "JVM Anatomy Quarks" (#18 scalar replacement, #29 uncommon traps, etc.): <https://shipilev.net/jvm/anatomy-quarks/>
* "Black Magic of (Java) Method Dispatch": <https://shipilev.net/blog/2015/black-magic-method-dispatch/>
* Cliff Click, "A JVM Does That???"; JITWatch: <https://github.com/AdoptOpenJDK/jitwatch>
* JEP 483, 514, 515, 516 (Project Leyden): <https://openjdk.org/projects/leyden/>
* GraalVM Native Image docs: <https://www.graalvm.org/latest/reference-manual/native-image/>
