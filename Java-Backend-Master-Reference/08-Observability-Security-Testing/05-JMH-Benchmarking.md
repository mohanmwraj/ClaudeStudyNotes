# 8.5 · JMH — Microbenchmarks That Tell the Truth

> **Tags:** 🔥 must-know · ⚡ important · 🧊 deep cut
> **Sources:** OpenJDK JMH project and its samples (`JMHSample_08_DeadCode`, `_10_ConstantFold`, `_11_Loops`, `_12_Forking`, `_35_Profilers`); Aleksey Shipilëv, "Nanotrusting the Nanotime" and "JMH: The Lesser of Two Evils"; JEP 498 (warnings on `sun.misc.Unsafe` memory access, JDK 24); JDK 23 release notes (annotation processing off by default).
> **Verified stack:** JMH **1.37** (`jmh-core`, `jmh-generator-annprocess`), Temurin 25.0.4.1, Windows x64, 12 logical CPUs. Benchmarks ran with **short** settings (3×200 ms warmup, 5×200 ms measurement, 1 fork) to keep this page reproducible in under a minute. Timings are single measured runs on a laptop; the **ratios and allocation counts** are the point, not the absolute nanoseconds.

---

## 1. Why a `main()` loop lies, and what JMH does about it 🔥

| Pitfall | What the JIT does | JMH's countermeasure |
|---|---|---|
| **Dead-code elimination** | Removes computations whose results are unused | Return the result, or `Blackhole.consume(...)` |
| **Constant folding** | Computes expressions on constants at compile time | Inputs come from non-final `@State` fields |
| **Loop optimizations** | Unrolls, vectorizes, hoists invariants, or removes the timed loop | JMH owns the loop and calls your method once per operation (`@OperationsPerInvocation` when you loop yourself) |
| **OSR code** | A long loop in `main` runs on-stack-replaced code, often worse optimized ([1.5](../01-JVM-Internals/05-JIT-Compilation-AOT-Native-Image.md)) | Normal method compilation through repeated calls |
| **Warmup** | Interpreter → C1 → C2 tiers; class loading; deoptimizations | `@Warmup` iterations are discarded |
| **Profile pollution** | Benchmark B runs on code profiled for benchmark A (megamorphic call sites) | `@Fork`: every benchmark runs in a fresh JVM |
| **Run-to-run variance** | JIT decisions, memory layout, CPU frequency, OS noise | Several forks × iterations; a confidence interval (`±`) on every score |
| **Timer granularity** | `nanoTime` costs ~20–30 ns and has coarse resolution on some systems | Measures many operations per iteration; `SampleTime` mode for latency distributions |

### 1.1 Runnable: dead code, constant folding, and a surprise on JDK 25

<!-- run: javac cp=@jmh javacopts="-proc:full" jvm="--sun-misc-unsafe-memory-access=allow" timeout=300 -->
```java
package demo.jmh;

import java.util.concurrent.TimeUnit;
import org.openjdk.jmh.annotations.*;
import org.openjdk.jmh.infra.Blackhole;
import org.openjdk.jmh.results.RunResult;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.options.*;

@BenchmarkMode(Mode.AverageTime) @OutputTimeUnit(TimeUnit.NANOSECONDS)
@Warmup(iterations = 3, time = 200, timeUnit = TimeUnit.MILLISECONDS)
@Measurement(iterations = 5, time = 200, timeUnit = TimeUnit.MILLISECONDS)
@Fork(1)
@State(Scope.Thread)
public class BenchmarkPitfalls {
    double x = Math.PI;                                                         // a field: the JIT can't assume its value

    @Benchmark public void baseline() { }

    @Benchmark public void sqrtUnused() { Math.sqrt(x); }                       // pure node, result unused → eliminated
    @Benchmark public double sqrtReturned() { return Math.sqrt(x); }           // JMH consumes return values
    @Benchmark public void sqrtBlackhole(Blackhole bh) { bh.consume(Math.sqrt(x)); }
    @Benchmark public double sqrtConstant() { return Math.sqrt(Math.PI); }     // folded by the JIT

    @Benchmark public void logUnused() { Math.log(x); }                         // a runtime stub call: is it eliminated?
    @Benchmark public double logReturned() { return Math.log(x); }
    @Benchmark public double logConstant() { return Math.log(Math.PI); }

    public static void main(String[] args) throws Exception {
        // The "benchmark" people write first: time a loop in main()
        double y = Math.PI;
        long t0 = System.nanoTime();
        for (int i = 0; i < 200_000_000; i++) Math.sqrt(y);
        System.out.printf("naive main() loop, result unused: %.3f ns per Math.sqrt%n", (System.nanoTime() - t0) / 200_000_000.0);

        Options opts = new OptionsBuilder().include(BenchmarkPitfalls.class.getName()).verbosity(VerboseMode.SILENT).build();
        for (RunResult r : new Runner(opts).run()) {
            var score = r.getPrimaryResult();
            System.out.printf("%-14s %7.3f ± %.3f %s%n", r.getParams().getBenchmark().replaceAll(".*\\.", ""),
                score.getScore(), score.getScoreError(), score.getScoreUnit());
        }
    }
}
```

One measured run:

```
naive main() loop, result unused: 0.012 ns per Math.sqrt
baseline         0.360 ± 0.016 ns/op
logConstant      6.209 ± 0.519 ns/op
logReturned      5.900 ± 0.833 ns/op
logUnused        5.849 ± 0.477 ns/op
sqrtBlackhole    1.449 ± 0.050 ns/op
sqrtConstant     0.361 ± 0.009 ns/op
sqrtReturned     1.430 ± 0.070 ns/op
sqrtUnused       0.362 ± 0.020 ns/op
```

Reading the results:

* **The naive loop reported 0.012 ns per `Math.sqrt`,** about 1/20 of a CPU cycle. Nothing was measured: C2 removed the unused computation from the (OSR-compiled) loop. Numbers like this are why "Java microbenchmark" blog posts disagree.
* **`sqrtUnused` = `baseline` = `sqrtConstant` (~0.36 ns, JMH's own per-call overhead).** The unused result was eliminated, and `Math.sqrt(Math.PI)` was folded into a constant. `sqrtReturned` and `sqrtBlackhole` measured the real cost (~1.4 ns). Returning the value or consuming it into a `Blackhole` is equivalent. Use the `Blackhole` when there is more than one result.
* **The surprise: `Math.log` was neither eliminated nor folded.** All three `log` variants cost ~6 ns, including the unused one and the constant one. On modern HotSpot x64, `Math.log` is an intrinsic implemented as a **call into a generated stub** (Intel libm), and C2 keeps the call. `Math.sqrt` maps to a pure machine instruction (`sqrtsd`) that C2 can drop or fold. The famous JMH dead-code sample uses `Math.log`, so on JDK 25 it no longer shows the effect it was written for. The lesson isn't "DCE doesn't happen". **Whether the JIT can see through your code depends on the JDK, the CPU and the code shape, so always include a baseline and sanity-check impossible numbers.**
* **JDK 24+ prints `sun.misc.Unsafe` warnings for JMH 1.37** (JEP 498: `objectFieldOffset … will be removed in a future release`). The runs above passed `--sun-misc-unsafe-memory-access=allow` to the host JVM, and JMH forks inherit the host's JVM flags.
* **JDK 23+ no longer runs annotation processors found on the class path.** Compiled without `-proc:full`, the same benchmark failed at run time with `ERROR: Unable to find the resource: /META-INF/BenchmarkList` (verified): the generated harness classes were never created. In Maven, configure `maven-compiler-plugin` with `<proc>full</proc>` or list `jmh-generator-annprocess` under `annotationProcessorPaths`. In Gradle, use the `annotationProcessor` configuration (or the `me.champeau.jmh` plugin).

---

## 2. Measure allocation, not just time 🔥

Time is noisy; **allocated bytes per operation** are almost deterministic. They are a great regression signal for hot paths (serialization, logging, mapping code). JMH's `GCProfiler` (`-prof gc`) reports `gc.alloc.rate.norm` in B/op.

### 2.1 Runnable: summing 1,000 numbers three ways, and formatting a log line two ways

<!-- run: javac cp=@jmh javacopts="-proc:full" jvm="--sun-misc-unsafe-memory-access=allow" timeout=300 -->
```java
package demo.jmh;

import java.util.List;
import java.util.concurrent.TimeUnit;
import java.util.stream.IntStream;
import org.openjdk.jmh.annotations.*;
import org.openjdk.jmh.profile.GCProfiler;
import org.openjdk.jmh.results.RunResult;
import org.openjdk.jmh.runner.Runner;
import org.openjdk.jmh.runner.options.*;

@BenchmarkMode(Mode.AverageTime) @OutputTimeUnit(TimeUnit.NANOSECONDS)
@Warmup(iterations = 3, time = 200, timeUnit = TimeUnit.MILLISECONDS)
@Measurement(iterations = 5, time = 200, timeUnit = TimeUnit.MILLISECONDS)
@Fork(1)
@State(Scope.Benchmark)
public class AllocationProfile {
    @Param({"1000"}) int size;
    int[] array;
    List<Integer> list;
    String orderId = "A-1042";
    long totalCents = 129_99;

    @Setup(Level.Trial) public void fill() {                                    // not measured
        array = IntStream.range(0, size).toArray();
        list = IntStream.range(0, size).boxed().toList();
    }

    @Benchmark public int loopSum() { int s = 0; for (int v : array) s += v; return s; }
    @Benchmark public int mapToIntSum() { return list.stream().mapToInt(Integer::intValue).sum(); }
    @Benchmark public int boxedReduce() { return list.stream().reduce(0, Integer::sum); }           // boxes every partial sum

    @Benchmark public String concat() { return "order=" + orderId + " total=" + totalCents; }      // indy string concat
    @Benchmark public String format() { return String.format("order=%s total=%d", orderId, totalCents); }

    public static void main(String[] args) throws Exception {
        Options opts = new OptionsBuilder().include(AllocationProfile.class.getName())
            .addProfiler(GCProfiler.class).verbosity(VerboseMode.SILENT).build();
        System.out.printf("%-12s %12s %14s%n", "benchmark", "ns/op", "allocated B/op");
        for (RunResult r : new Runner(opts).run()) {
            var alloc = r.getSecondaryResults().get("gc.alloc.rate.norm");
            System.out.printf("%-12s %12.1f %14.0f%n", r.getParams().getBenchmark().replaceAll(".*\\.", ""),
                r.getPrimaryResult().getScore(), alloc.getScore());
        }
    }
}
```

One measured run:

```
benchmark           ns/op allocated B/op
boxedReduce        3842.4          15896
concat               13.7             64
format              146.6            520
loopSum             231.9              0
mapToIntSum         517.1            232
```

Reading the results:

* **`boxedReduce` allocated 15,896 B per call:** one 16-byte `Integer` for nearly every partial sum (only results within the `Integer` cache, −128…127, are free), plus the stream pipeline. It was **17× slower** than the primitive loop and more than 7× slower than `mapToInt(...).sum()`. In a service handling thousands of requests per second, that is megabytes per second of avoidable garbage ([1.4](../01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md) on allocation rate and GC pressure).
* **`loopSum` allocated nothing and took ~0.23 ns per element.** C2 **vectorized** the loop with SIMD instructions. `mapToIntSum` allocated only the pipeline objects (232 B), independent of size.
* **`String.format` was ~10× slower and allocated ~8× more than concatenation** (`invokedynamic` `StringConcatFactory`). It parses the format string on every call. In a hot path, or in a log call that runs whether or not the level is enabled, that adds up. Parameterized logging (`log.debug("order={} total={}", id, total)`) defers formatting until the level is known to be enabled.
* `@Setup(Level.Trial)` built the inputs outside the measurement. `Level.Iteration` and `Level.Invocation` exist. `Invocation`-level setup adds timer overhead to every call, so use it only for operations of a millisecond or more.

---

## 3. Running JMH for real ⚡

```bash
# Generate a standalone benchmark project (shaded benchmarks.jar)
mvn archetype:generate -DarchetypeGroupId=org.openjdk.jmh -DarchetypeArtifactId=jmh-java-benchmark-archetype \
    -DarchetypeVersion=1.37 -DgroupId=com.acme -DartifactId=benchmarks

# Real settings: several forks, longer iterations, JSON output for comparison
java -jar target/benchmarks.jar 'OrderMapper.*' -f 3 -wi 5 -w 1s -i 10 -r 1s -prof gc -rf json -rff before.json

# Profilers: where does the time go inside the benchmark?
java -jar target/benchmarks.jar OrderMapper -prof jfr                       # JFR recording per fork
java -jar target/benchmarks.jar OrderMapper -prof async:output=flamegraph   # async-profiler (libasyncProfiler on the library path)
java -jar target/benchmarks.jar OrderMapper -prof perfasm                   # Linux perf + hsdis: hottest assembly
java -jar target/benchmarks.jar -lprof                                      # list the profilers available on this machine
```

| Mode | Reports | Use for |
|---|---|---|
| `Throughput` | ops per time unit | Library throughput comparisons |
| `AverageTime` | time per op | The default choice for "how expensive is X" |
| `SampleTime` | percentiles (p50 … p99.99) of sampled call times | Latency distributions, outliers, GC pauses inside ops |
| `SingleShotTime` | one call per iteration, no warmup by default | Cold-start costs (first call, class loading); pair with many forks |

Other annotations worth knowing:

* **`@State(Scope.Thread | Benchmark | Group)`**: per-thread or shared state. With **`@Threads(n)`** and `Scope.Benchmark`, it measures contention (e.g. `AtomicLong` vs `LongAdder`, [3.3](../03-Concurrency-Loom/03-Lock-Free-CAS-Atomics.md)).
* **`@Group` / `@GroupThreads`**: asymmetric benchmarks such as 3 readers + 1 writer on the same state.
* **`@Param`** sweeps inputs (sizes, implementations). Always include sizes that match production data. A 10-element benchmark tells you nothing about 10,000 elements and cache misses.
* **`@CompilerControl(DONT_INLINE)`** lets you study call costs. `Blackhole.consumeCPU(tokens)` creates controllable backoff.
* **`@Fork(jvmArgsAppend = …)`** compares GC choices, `-XX:` flags or JDK versions (`-jvm /path/to/java`).

How to read and use results:

* `score ± error` is a **99.9% confidence interval** over all measured iterations and forks. **Overlapping intervals mean "no demonstrated difference"**, however different the scores look.
* Sub-nanosecond scores (like `baseline` above) mean "the JIT made it disappear", not "it is fast".
* Microbenchmarks answer narrow questions. First **profile the real system** (async-profiler or JFR, [8.1](01-JVM-Profiling-JFR-async-profiler-Thread-Dumps.md)) to find the hot method. Then use JMH to compare alternatives for that method. Then confirm the gain with a load test or in production metrics.
* Benchmark on hardware and a JDK that resemble production. Laptops throttle; containers with CPU limits behave differently ([1.4](../01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md) on container ergonomics). Keep benchmarks in the repository and run them in CI on a quiet, dedicated runner, comparing JSON results with a threshold (or tracking `gc.alloc.rate.norm`, which is far less noisy).

---

## 4. Production failure modes & diagnostics

| Symptom | Cause | Fix |
|---|---|---|
| "Optimization" made production slower | Microbenchmark measured DCE, constant folding or OSR artifacts; or tiny unrealistic inputs | JMH with returned/consumed results, `@State` inputs, realistic `@Param` sizes |
| Benchmark results flip between runs | One fork, too few iterations, a noisy machine, CPU frequency scaling | `-f 3+`, longer iterations, a dedicated runner; compare confidence intervals |
| Benchmark A is fast alone, slow next to B | Profile pollution in a shared JVM (`@Fork(0)` or forks disabled) | Never use `-f 0` for numbers; it is for debugging only |
| `Unable to find the resource: /META-INF/BenchmarkList` | Annotation processing didn't run (JDK 23+ default, or a misconfigured build) | `-proc:full` or `annotationProcessorPaths` |
| GC pauses grow after a "harmless" refactor | Hidden allocation (boxing, streams, `String.format`, varargs, lambdas capturing state) | `-prof gc` B/op gate in CI; allocation profiling with async-profiler or JFR (`jdk.ObjectAllocationSample`) |
| Numbers differ in containers | CPU quotas, fewer GC/JIT threads, different CPU model | Benchmark under the production container limits |
| `sun.misc.Unsafe` warnings in benchmark output (JDK 24+) | JMH 1.37 uses `Unsafe` | `--sun-misc-unsafe-memory-access=allow` until JMH moves off `Unsafe` |

---

## 5. Interview Q&A

<details><summary><b>Q1. 🔥 Why can't you benchmark Java code with <code>System.nanoTime()</code> around a loop in <code>main</code>?</b></summary>

The JIT optimizes the loop you are timing. It eliminates unused results (dead code), folds constants, unrolls and vectorizes, and the loop runs as OSR-compiled code that differs from normal method compilation. Warmup and tier transitions mix into the measurement, and there is no statistics or fork isolation. The measured naive loop reported 0.012 ns per `Math.sqrt`, about 1/20 of a cycle, so nothing was measured. JMH handles warmup, forks, result consumption (`Blackhole`) and confidence intervals.
</details>

<details><summary><b>Q2. 🔥 What is a <code>Blackhole</code>, and when do you need one?</b></summary>

A JMH sink that consumes values in a way the JIT can't prove useless, which prevents dead-code elimination. Returning the value from a `@Benchmark` method is equivalent: JMH consumes it into a `Blackhole` implicitly (measured: `sqrtReturned` ≈ `sqrtBlackhole` ≈ 1.4 ns, while `sqrtUnused` collapsed to the 0.36 ns baseline). Use an explicit `Blackhole` when a benchmark produces several values or runs a loop.
</details>

<details><summary><b>Q3. ⚡ Why does JMH fork a new JVM per benchmark by default?</b></summary>

To isolate JIT profiles and compiled code. Running benchmarks A and B in one JVM lets A's type profiles pollute B (a call site that saw several implementations becomes megamorphic and stops inlining), so the results depend on execution order. Multiple forks also capture run-to-run variance from JIT decisions and memory layout, which iterations within one JVM can't show.
</details>

<details><summary><b>Q4. ⚡ How do you know whether a refactoring increased allocation on a hot path?</b></summary>

Run the benchmark with `-prof gc` and compare `gc.alloc.rate.norm` (bytes per operation), which is nearly deterministic. The measured run showed `reduce(0, Integer::sum)` allocating 15,896 B per 1,000 elements (boxing) against 0 B for a primitive loop. In production, confirm with JFR `jdk.ObjectAllocationSample` or async-profiler allocation flame graphs.
</details>

<details><summary><b>Q5. 🧊 The classic JMH dead-code sample uses <code>Math.log</code>. Why doesn't it reproduce on JDK 25 x64?</b></summary>

On modern HotSpot, `Math.log` is intrinsified as a call into a generated stub (Intel's libm port), and C2 doesn't eliminate or constant-fold that call. The unused and constant-input variants still cost ~6 ns (measured). `Math.sqrt` compiles to a single pure instruction, so its unused and constant variants collapsed to the baseline. Optimizations depend on the JDK version and code shape, so a benchmark needs a baseline and sanity checks, not assumptions.
</details>

<details><summary><b>Q6. ⚡ Two implementations score 112 ± 9 ns/op and 104 ± 11 ns/op. Which is faster?</b></summary>

Neither is demonstrated to be faster: the 99.9% confidence intervals (103–121 and 93–115) overlap. Run more forks and iterations, check the variance source (noise, bimodal JIT outcomes; look at per-fork results), or accept that the difference doesn't matter. Then ask whether 8 ns matters for the system at all.
</details>
