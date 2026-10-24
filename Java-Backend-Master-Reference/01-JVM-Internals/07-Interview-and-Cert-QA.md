# 1.7 · Pillar 1 — Interview & Certification Question Bank (JVM Internals)

> **How to use this file:** Section A is for spaced-repetition flashcards. Section B holds senior and architect-level scenario questions. Section C covers 1Z0-830/1Z0-831 (Java SE 21/25 Developer Professional) *exam-style* questions for the **Packaging and Deploying Java Code** objective and the JVM-adjacent bits of the OOP objective (initialization order, GC eligibility). All questions are original practice items written for this guide, **not** real exam content. Cover the answers and reason first.
> The per-topic Q&A sections at the end of files [1.1](01-ClassLoading-Linking-JPMS.md#12-interview--certification-qa)–[1.5](05-JIT-Compilation-AOT-Native-Image.md#11-interview-qa) complement this bank.

---

## A. Rapid-fire (answer in one breath)

<details><summary><b>A1–A10</b></summary>

1. **Where do class metadata live since JDK 8?** Metaspace (native), plus the compressed class space for `Klass` structures.
2. **Where are static fields stored?** In the `java.lang.Class` mirror object on the heap.
3. **Default max heap without `-Xmx`?** 25% of physical or container RAM (`MaxRAMPercentage=25`).
4. **Default GC in JDK 25?** G1, except Serial on < 2 CPUs or < ~1.8 GB RAM. JDK 27 makes it G1 everywhere.
5. **Header size of an ordinary object on 64-bit with compressed class pointers?** 12 bytes (8 mark + 4 klass); 8 bytes with compact headers.
6. **Why can't ZGC use compressed oops?** References carry GC color metadata bits, so they must be 64-bit.
7. **What's the compressed-oops heap limit with 8-byte alignment?** 32 GB.
8. **What does TLAB stand for?** Thread-Local Allocation Buffer: per-thread bump-pointer allocation in eden.
9. **Max tenuring threshold?** 15 (the age field in the mark word is 4 bits).
10. **When is a class unloaded?** When its defining class loader becomes unreachable, during a GC that unloads classes.
</details>

<details><summary><b>A11–A20</b></summary>

11. **Which `Class.forName` overload initializes the class?** The one-argument form, and the three-argument form with `initialize=true`.
12. **What error does a failing static initializer produce first, and then on later use?** `ExceptionInInitializerError`, then `NoClassDefFoundError: Could not initialize class X`.
13. **What's a hidden class?** A class defined via `Lookup.defineHiddenClass`, not discoverable by name and unloadable independently. Lambdas use them.
14. **Biased locking status?** Deprecated in 15, removed in 18.
15. **Default locking mode since JDK 23?** Lightweight locking (per-thread lock-stack).
16. **What triggers deoptimization?** Failed speculation (an uncommon trap), CHA dependency invalidation, class redefinition.
17. **Default `MaxInlineSize` / `FreqInlineSize`?** 35 / 325 bytecode bytes.
18. **What does `%` mean in `PrintCompilation`?** An OSR (on-stack replacement) compilation.
19. **What's scalar replacement?** EA-driven elimination of a non-escaping allocation by turning its fields into locals.
20. **Why do NPEs lose their stack traces in prod?** `OmitStackTraceInFastThrow` (preallocated exceptions for hot implicit-exception sites).
</details>

<details><summary><b>A21–A30</b></summary>

21. **Card size in the card table?** 512 bytes (1 byte per card).
22. **G1 region size range?** 1 MB – 512 MB, a power of two, targeting ~2048 regions.
23. **What is a humongous object?** One ≥ ½ G1 region, allocated directly in old-gen contiguous regions.
24. **G1's marking barrier style?** SATB (pre-write barrier).
25. **ZGC's barriers?** Load barrier (colored pointers, self-healing) plus store barrier (generational remembered sets and SATB).
26. **What's an allocation stall?** A ZGC thread blocking because no memory is free until the concurrent GC reclaims some.
27. **What's a degenerated GC?** Shenandoah finishing a concurrent cycle stop-the-world after an allocation failure.
28. **What does `-XX:+ExitOnOutOfMemoryError` do?** Terminates the JVM on the first OOM so the orchestrator restarts it.
29. **Which JDK tool shows native memory by category?** `jcmd <pid> VM.native_memory`, which requires `-XX:NativeMemoryTracking`.
30. **What does the AOT cache (JDK 24+) store?** Loaded and linked classes (24), method profiles (25), heap objects with any GC (26).
</details>

---

## B. Scenario & deep-dive questions (senior / architect)

<details><summary><b>B1. 🔥 Your Spring Boot service's RSS is 3.1 GB with `-Xmx2g`. Product asks why, and whether you can run 30% more pods per node. Walk through it.</b></summary>

Account for RSS = heap (committed up to 2 GB) + Metaspace (Spring apps often hold 150–300 MB) + code cache (50–150 MB used) + thread stacks (200 threads × ~0.5–1 MB touched) + GC structures (G1: ~5–15% of heap) + direct buffers (Netty/Tomcat NIO) + native libraries and malloc arenas. Measure with NMT (`VM.native_memory summary`) and compare against cgroup `memory.current`, then attribute the gap (`pmap`) to malloc arenas or JNI. To pack more pods: right-size the heap from the measured live set (G1 ~3× live), cap Metaspace and direct memory, reduce threads (virtual threads for blocking I/O), consider `-XX:+UseCompactObjectHeaders` (10–20% heap on object-heavy workloads), `MALLOC_ARENA_MAX=2`, and possibly a Leyden AOT cache (shared, read-only mapped archive). Then re-measure under load. Never cut the container limit below measured peak RSS plus margin.
</details>

<details><summary><b>B2. 🔥 p99.9 is 180 ms on G1 with `MaxGCPauseMillis=200`. The SLO is 50 ms. Options?</b></summary>

First check whether GC is the cause by correlating pause logs with latency spikes, and rule out TTSP (safepoint logs), lock contention and downstream calls. If GC: reduce the pause drivers. Young pauses scale with survivors and RSet scanning: reduce medium-lived allocations and premature promotion, check humongous churn, and set a lower `MaxGCPauseMillis=50` (more frequent, smaller young GCs, at some throughput cost). If mixed or full GCs dominate, fix IHOP and headroom. If 50 ms at p99.9 is still out of reach (big live set, high allocation rate), move to Generational ZGC with 2–3× live-set headroom and verify zero allocation stalls. Budget the extra CPU, and remember ZGC's references are 8 bytes.
</details>

<details><summary><b>B3. ⚡ A teammate proposes `-XX:+DisableExplicitGC` because a library calls `System.gc()` hourly. Risks?</b></summary>

Direct `ByteBuffer` reclamation relies on `System.gc()` inside `Bits.reserveMemory` when the direct limit is hit, so disabling it can turn temporary pressure into `OutOfMemoryError: Cannot reserve … direct buffer memory`. RMI's distributed GC also uses it. Prefer `-XX:+ExplicitGCInvokesConcurrent` (G1), which turns explicit GCs into concurrent cycles. Better still, find and fix the caller (JFR `jdk.GarbageCollection` with cause `System.gc()` plus stack traces).
</details>

<details><summary><b>B4. ⚡ How would you design a plugin system that can hot-unload plugins without Metaspace leaks?</b></summary>

One class loader per plugin (child-first for the plugin's own dependencies, parent-first for the API package), or a JPMS `ModuleLayer` per plugin. Narrow the API surface so no host-side static references plugin types. Expose lifecycle hooks (start/stop) where plugins must shut down their executors, remove `ThreadLocal`s and deregister listeners, drivers and MBeans. Don't cache plugin classes in host-level caches (or key such caches weakly by loader). After unload, verify with a `WeakReference` to the loader plus GC in an integration test (as in [1.1 §7.1](01-ClassLoading-Linking-JPMS.md#71-runnable-unloading-works--until-a-threadlocal-pins-the-loader)), and monitor `VM.classloader_stats`. Set `MaxMetaspaceSize` so failures surface fast.
</details>

<details><summary><b>B5. ⚡ Explain to a junior why "creating objects is expensive in Java" is mostly a myth, and when it is true.</b></summary>

Allocation is a TLAB bump-pointer, so it is nearly free. The young GC cost is proportional to *survivors*, and short-lived garbage costs almost nothing, and escape analysis can remove allocations entirely (measured: 96 bytes per iteration → 0). It becomes true when objects survive (premature promotion makes old-gen work), when allocation rates are very high (more frequent GCs, ZGC stalls), when objects are large (humongous), when EA fails (escape on rare paths, megamorphic calls), or when density matters for cache efficiency (boxed collections).
</details>

<details><summary><b>B6. 🧊 Why might a microbenchmark show `record` DTOs as free while the production flame graph shows them as top allocators?</b></summary>

In the microbenchmark, the call sites are monomorphic and everything is inlined, so EA scalar-replaces the records. In production the same code runs through megamorphic framework paths (Jackson serializers, lambdas, interceptors), large methods hit inlining limits, and objects escape into collections, logs or async callbacks. EA can't prove non-escape, so allocation happens. Profile allocation in production (JFR `ObjectAllocationSample`, async-profiler `-e alloc`), not in isolation.
</details>

<details><summary><b>B7. 🔥 Upgrading from JDK 17 to 25: what JVM-level risks do you test for?</b></summary>

Strong-encapsulation and `Unsafe` warnings (JEP 498): libraries using `sun.misc.Unsafe` memory methods print warnings, so plan upgrades. JNI warnings (JEP 472) mean adding `--enable-native-access` where intended. The Security Manager is gone (JEP 486). Removed GC flags (non-generational ZGC, `ZGenerational`) and deprecated flags make startup fail on unknown or obsolete options. Lightweight locking is now the default (watch native agents or tools that parse headers). Check CDS/AOT cache compatibility, changes to default GC ergonomics in small containers, locale data (CLDR updates change date/number formatting), and dynamic agent loading warnings (JEP 451). Run the full suite plus a soak test with GC/safepoint logs and JFR, and diff RSS and latency against 17.
</details>

<details><summary><b>B8. ⚡ What evidence distinguishes a memory leak from an undersized heap?</b></summary>

A leak shows a post-GC live-set floor that rises over time, independent of load, with a histogram class count growing linearly. An undersized heap shows a flat but high floor that scales with load, with GC frequency and overhead rising under traffic and recovering afterwards. Confirm with two histograms or heap dumps at different times, and a MAT dominator-tree comparison.
</details>

<details><summary><b>B9. 🧊 How does the JVM find references in a compiled frame during GC?</b></summary>

At each safepoint poll, call site and other GC point, C2 or C1 records an **oop map** describing which registers and stack slots hold references. When a thread stops at a safepoint, the GC walks its frames, using oop maps for compiled frames and the interpreter's own frame layout (computed liveness) for interpreted frames. That is why threads must reach a safepoint: arbitrary instruction boundaries have no oop maps.
</details>

<details><summary><b>B10. ⚡ When would you choose Parallel GC in 2026?</b></summary>

Throughput-oriented batch work where total job time matters more than individual pauses: ETL, offline analytics, large builds, Spark executors with large heaps and no interactive latency SLO. Parallel has lower barrier overhead than G1 (no SATB or refinement), excellent throughput, and simple ergonomics (`GCTimeRatio`). Also consider it for heaps where occasional multi-second pauses are acceptable and CPU efficiency is paramount.
</details>

---

## C. Certification-style questions (1Z0-830 / 1Z0-831 — Packaging, Deploying, Initialization, GC)

> Format: choose the correct option(s). Explanations are in the `<details>`. These cover typical exam *traps*. Practise reading the code exactly as written.

**C1.** A JAR named `order-service-2.4.1.jar` without a module descriptor and without an `Automatic-Module-Name` manifest entry is placed on the module path. What is its module name?
A. `order-service`  B. `order.service`  C. `order.service.2.4.1`  D. It cannot be used on the module path

<details><summary>Answer</summary>

**B.** The version suffix (`-2.4.1`) is dropped, and non-alphanumeric characters become dots: `order-service` → `order.service`. Automatic modules export and open all packages and read all modules.
</details>

**C2.** Given:

```java
// module-info.java of module app
module app {
    requires lib;
}
// module-info.java of module lib
module lib {
    requires transitive util;
    exports com.lib;
}
// module util exports com.util
```

Which statement is true?
A. `app` can use public types in `com.util` without changing `app`'s descriptor.
B. `app` must also declare `requires util` to use `com.util`.
C. `app` can use non-exported packages of `lib`.
D. Compilation fails because `util` is not required by `app`.

<details><summary>Answer</summary>

**A.** `requires transitive util` in `lib` gives every module that reads `lib` implied readability of `util`. `com.util` is exported, so `app` can use it. Option C is false: only exported packages are accessible.
</details>

**C3.** Which command creates a custom runtime image containing only the modules needed by an application whose main module is `app` in directory `mods`?
A. `jdeps --output runtime --module-path mods app`
B. `jlink --module-path mods --add-modules app --output runtime`
C. `jar --create --runtime runtime --module app`
D. `jmod create --add-modules app runtime`

<details><summary>Answer</summary>

**B.** `jlink` resolves `app` and its transitive `requires` (JDK modules are found automatically from the JDK; older JDKs needed `$JAVA_HOME/jmods` on the module path) and writes an image to `runtime`. Trap: **jlink cannot link automatic modules**. Every module in the image must be explicit.
</details>

**C4.** Which `jdeps` option lists the JDK modules an application needs, in a form suitable for `jlink --add-modules`?
A. `--list-deps`  B. `--print-module-deps`  C. `--summary`  D. `--generate-module-info`

<details><summary>Answer</summary>

**B.** `--print-module-deps` prints a comma-separated module list. `--list-deps` lists modules and internal APIs one per line, `-s`/`--summary` prints a dependency summary, and `--generate-module-info` creates `module-info.java` files.
</details>

**C5.** Module `a` declares `opens com.a.model;` but not `exports com.a.model;`. Module `b` requires `a`. Which is true?
A. Code in `b` can compile against public classes in `com.a.model`.
B. Code in `b` can use reflection at run time to access private fields of classes in `com.a.model`.
C. Neither compile-time nor run-time access is possible.
D. `opens` is only valid in an `open module`.

<details><summary>Answer</summary>

**B.** `opens` grants run-time deep reflective access only. It gives no compile-time access, so A is false. D is false: `open module` opens *everything*, and individual `opens` directives cannot appear inside an `open module`.
</details>

**C6.** Which `module-info.java` declarations are valid? (Choose two.)
A. `module com.example.app { requires java.base; }`
B. `module com.example.2app { }`
C. `module app { exports com.app to; }`
D. `module app { provides com.spi.Codec with com.app.JsonCodec; }`

<details><summary>Answer</summary>

**A and D.** A is valid: explicitly requiring `java.base` is allowed (it is implicit anyway). B is invalid: an identifier part can't start with a digit. C is invalid: a qualified export needs at least one target module. D is a valid service provision (the provider type must exist and be in the module).
</details>

**C7.** A service provider class declared with `provides S with P;` in a named module must:
A. Have a public no-arg constructor **or** a public static no-arg `provider()` method returning an instance of `S`.
B. Be listed in `META-INF/services`.
C. Be in an exported package.
D. Be `final`.

<details><summary>Answer</summary>

**A.** On the module path, `ServiceLoader` instantiates providers via a public static `provider()` method if present, otherwise via a public no-arg constructor. The provider's package does **not** need to be exported (C is false; that's the point of encapsulated services). `META-INF/services` is the class-path mechanism.
</details>

**C8.** What is printed?

<!-- run: -->
```java
public class InitOrder {
    static { System.out.print("S1 "); }
    int x = log("F ");
    { System.out.print("I "); }
    InitOrder() { System.out.print("C "); }
    static { System.out.print("S2 "); }
    static int log(String s) { System.out.print(s); return 1; }

    public static void main(String[] args) {
        System.out.print("M ");
        new InitOrder();
        new InitOrder();
    }
}
```

A. `S1 S2 M F I C F I C`  B. `M S1 S2 F I C F I C`  C. `S1 S2 M I F C I F C`  D. `S1 M S2 F I C F I C`

<details><summary>Answer</summary>

**A.** Static initializers run in textual order when the class initializes, which happens before `main` because it is the main class. Each `new` then runs instance field initializers and instance initializer blocks **in textual order** (`F` then `I`), and then the constructor body. Static init runs once. (Verified output: `S1 S2 M F I C F I C `.)
</details>

**C9.** What is printed?

<!-- run: -->
```java
public class ParentChild {
    static class Parent {
        static { System.out.print("PS "); }
        { System.out.print("PI "); }
        Parent() { System.out.print("PC "); }
    }
    static class Child extends Parent {
        static { System.out.print("CS "); }
        { System.out.print("CI "); }
        Child() { System.out.print("CC "); }
    }
    public static void main(String[] args) { new Child(); }
}
```

A. `PS CS PI PC CI CC`  B. `PS PI PC CS CI CC`  C. `CS PS CI CC PI PC`  D. `PS CS CI CC PI PC`

<details><summary>Answer</summary>

**A.** Class initialization goes superclass first (`PS CS`). Then construction: `Child()` implicitly calls `super()` first, which runs the Parent instance initializers and constructor (`PI PC`), and then the Child instance initializers and constructor body (`CI CC`).
</details>

**C10.** How many objects are eligible for garbage collection when the line `// HERE` is reached?

```java
String a = new String("x");   // object 1
String b = new String("y");   // object 2
String c = a;
a = null;
b = c;
// HERE
```

A. 0  B. 1  C. 2  D. 3

<details><summary>Answer</summary>

**B.** Object 1 is still referenced by `c` and `b`. Object 2 has no references after `b = c`, so one object is eligible. (The literal `"x"`/`"y"` String constants are interned and never eligible here; exam questions count the `new` objects.)
</details>

**C11.** Which statements about `System.gc()` are true? (Choose two.)
A. It guarantees that all unreachable objects are collected before it returns.
B. It is a request that the JVM may ignore.
C. With `-XX:+ExplicitGCInvokesConcurrent` on G1, it starts a concurrent cycle instead of a full STW collection.
D. It runs all pending finalizers synchronously.

<details><summary>Answer</summary>

**B and C.** The JVM may ignore it (`-XX:+DisableExplicitGC`), and with G1 it can be turned into a concurrent cycle. There is no guarantee about collection completeness or finalizer execution.
</details>

**C12.** Which command runs the main class `com.acme.Main` from module `acme.app` located in directory `mods`?
A. `java -cp mods com.acme.Main`
B. `java --module-path mods --module acme.app/com.acme.Main`
C. `java -m mods/acme.app com.acme.Main`
D. `java -p mods acme.app.Main`

<details><summary>Answer</summary>

**B** (equivalently `java -p mods -m acme.app/com.acme.Main`). A runs from the class path, so it would be the unnamed module, and the class wouldn't be found with that path layout anyway.
</details>

**C13.** Which statement about the unnamed module is true?
A. Named modules can `requires` the unnamed module.
B. The unnamed module reads every named module, and exports all its packages.
C. Classes in the unnamed module cannot use `java.sql` without `--add-modules`.
D. The unnamed module can contain split packages with named modules without error.

<details><summary>Answer</summary>

**B.** A is false: named modules cannot depend on the unnamed module (only automatic modules can read it). C is false: when the main class is on the class path, the default root modules include all JDK modules that export an API, `java.sql` among them. D is false: if a package is in a named module, the class-path copy is ignored or shadowed, which causes subtle errors.
</details>

**C14.** What does `requires static com.foo;` mean?
A. `com.foo` is required at compile time but optional at run time.
B. `com.foo`'s static members are imported.
C. `com.foo` must be on the class path, not the module path.
D. `com.foo` is loaded by the bootstrap loader.

<details><summary>Answer</summary>

**A.** Typical use: annotation-only dependencies (e.g. static-analysis annotations) that aren't needed at run time.
</details>

**C15.** (Java 25) Given the compact source file `Hello.java`:

```java
void main() {
    IO.println(List.of(1, 2, 3).reversed());
}
```

What happens with `java Hello.java`?
A. Compilation error: `List` is not imported.
B. Prints `[3, 2, 1]`.
C. Compilation error: `main` must be `static`.
D. Runtime error: no class declared.

<details><summary>Answer</summary>

**B.** In JDK 25 (JEP 512, final), a compact source file declares an implicit class, instance `main` methods are allowed, and the file automatically imports `module java.base`, so `java.util.List` is visible. `java.lang.IO.println` is also part of JEP 512. `List.reversed()` comes from Sequenced Collections (JDK 21).
</details>

---

## D. Whiteboard prompts (talk for 5 minutes each)

1. Draw a JVM process's memory map, label every area, and say which flag sizes each.
2. Walk through `new Order()` from bytecode to memory: TLAB, header initialization, zeroing, field stores, escape analysis.
3. Explain G1's young GC to someone who knows only mark-sweep, then explain why ZGC doesn't need STW evacuation.
4. Explain how a hot virtual call becomes a direct, inlined call and what makes it fall back.
5. Design the JVM configuration and observability for a 2-vCPU / 4 GiB Kubernetes pod running a REST service with a 100 ms p99 SLO.
