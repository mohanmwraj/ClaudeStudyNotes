# 99.1 · JVM Flags & Diagnostic Commands Cheat Sheet (JDK 25)

> JFR defaults below were read from JDK 25's own `lib/jfr/default.jfc` and `profile.jfc`. Every `-XX` flag on this page was checked against `java -XX:+PrintFlagsFinal` on Temurin 25.0.4.1 (with diagnostic/experimental unlocked where noted). Defaults shown are JDK 25's on a 12-CPU, 16 GB machine; *ergonomic* values depend on hardware.
> Deep explanations: [Pillar 1](../01-JVM-Internals/).

---

## 1. Memory sizing

| Flag | Default | Use |
|---|---|---|
| `-Xmx` / `-XX:MaxHeapSize` | 25% of RAM | Max heap. In containers prefer `MaxRAMPercentage` |
| `-Xms` / `-XX:InitialHeapSize` | 1/64 of RAM | Initial heap. `= -Xmx` for predictable services |
| `-XX:MaxRAMPercentage` | 25.0 | Max heap as % of the container limit (typ. 60–75) |
| `-XX:InitialRAMPercentage` | 1.5625 | Initial heap % |
| `-Xss` / `-XX:ThreadStackSize` | 1 MB (Linux) | Platform thread stack |
| `-XX:MaxMetaspaceSize` | unlimited | Cap Metaspace (fail fast on loader leaks) |
| `-XX:MetaspaceSize` | ~21 MB | Initial GC high-water mark (raise to avoid startup GCs) |
| `-XX:CompressedClassSpaceSize` | 1 GB | Klass space |
| `-XX:MaxDirectMemorySize` | = max heap | Direct `ByteBuffer` limit |
| `-XX:ReservedCodeCacheSize` | 240 MB | JIT code cache |
| `-XX:+UseCompactObjectHeaders` | off (25), **on (27)** | 8-byte object headers |
| `-XX:+AlwaysPreTouch` | off | Commit and touch the heap at startup |
| `-XX:ActiveProcessorCount=N` | detected | Override the CPU count used for ergonomics |

## 2. Garbage collectors

```bash
-XX:+UseG1GC -XX:MaxGCPauseMillis=200 -XX:G1HeapRegionSize=16m -XX:InitiatingHeapOccupancyPercent=45 -XX:G1ReservePercent=10
-XX:+UseZGC -XX:SoftMaxHeapSize=… -XX:ZAllocationSpikeTolerance=2 -XX:ConcGCThreads=N         # generational by default (JDK 23+)
-XX:+UseShenandoahGC -XX:ShenandoahGCMode=generational -XX:ShenandoahGCHeuristics=adaptive
-XX:+UseParallelGC -XX:GCTimeRatio=99
-XX:+UseSerialGC
-XX:+UnlockExperimentalVMOptions -XX:+UseEpsilonGC
-XX:+UseStringDeduplication   -XX:+ExplicitGCInvokesConcurrent   -XX:G1PeriodicGCInterval=60000
```

## 3. Logging (unified, JEP 158/271)

```bash
-Xlog:gc*,safepoint:file=/logs/gc.log:time,uptime,level,tags:filecount=5,filesize=20m
-Xlog:gc+init                 # oops mode, region size, collector at startup
-Xlog:gc+age=trace            # tenuring distribution
-Xlog:gc+humongous=debug      # G1 humongous allocations
-Xlog:class+load=info         # which JAR each class came from
-Xlog:class+unload=info
-Xlog:deoptimization=debug
-Xlog:aot                     # AOT cache diagnostics (JDK 24+)
jcmd <pid> VM.log output=file=/tmp/x.log what=gc*=debug   # change logging at run time
```

## 4. Failure handling & always-on observability

```bash
-XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/dumps -XX:+ExitOnOutOfMemoryError
-XX:ErrorFile=/logs/hs_err_pid%p.log
-XX:NativeMemoryTracking=summary
-XX:StartFlightRecording=disk=true,maxage=6h,maxsize=512m,settings=default,dumponexit=true,filename=/dumps/
-XX:+PerfDisableSharedMem      # no hsperfdata mmap stalls (disables jps/jstat discovery)
-XX:-OmitStackTraceInFastThrow # debugging: keep stack traces of hot implicit exceptions
```

## 5. JIT & AOT

```bash
-XX:+PrintCompilation
-XX:+UnlockDiagnosticVMOptions -XX:+PrintInlining
-XX:+UnlockDiagnosticVMOptions -XX:+LogCompilation -XX:LogFile=jit.xml     # → JITWatch
-XX:CompileCommand=dontinline,com.acme.Foo::bar
-XX:TieredStopAtLevel=1        # C1 only: fast startup, low peak (CLIs)
-XX:-DoEscapeAnalysis          # experiments only
-XX:AOTCacheOutput=app.aot     # JDK 25 one-step training (JEP 514)
-XX:AOTCache=app.aot           # production run with the cache
-XX:AOTMode=on                 # fail if the cache can't be used (CI)
```

## 6. Locking, concurrency, Loom

```bash
-XX:DiagnoseSyncOnValueBasedClasses=1|2     # synchronizing on Integer/Optional/…
-XX:-RestrictContended                     # allow @Contended outside the JDK
-Djdk.virtualThreadScheduler.parallelism=N -Djdk.virtualThreadScheduler.maxPoolSize=M
-Djava.util.concurrent.ForkJoinPool.common.parallelism=N
```

## 7. Encapsulation, native access, Unsafe

```bash
--add-opens java.base/java.lang=ALL-UNNAMED   --add-exports java.base/sun.nio.ch=ALL-UNNAMED
--enable-native-access=ALL-UNNAMED            # FFM restricted methods + JNI without warnings
--sun-misc-unsafe-memory-access=warn|debug|deny|allow
-XX:+EnableDynamicAgentLoading                # allow dynamic attach (JEP 451)
-Djdk.serialFilter='com.acme.dto.*;java.base/*;!*'
-Djdk.nio.maxCachedBufferSize=262144
```

---

## 8. `jcmd` commands (the Swiss-army knife)

| Command | Output |
|---|---|
| `jcmd` | List JVMs |
| `jcmd <pid> help` | Commands available for this JVM |
| `VM.version`, `VM.uptime`, `VM.command_line`, `VM.flags [-all]`, `VM.system_properties` | What is this JVM? |
| `GC.heap_info` | Heap layout now |
| `GC.class_histogram [-all]` | Live objects by class (**full GC** unless `-all`) |
| `GC.heap_dump [-gz=1] <file>` | Heap dump (long pause on big heaps) |
| `GC.run` | `System.gc()` |
| `VM.native_memory summary\|detail\|baseline\|summary.diff` | NMT (needs `-XX:NativeMemoryTracking`) |
| `VM.metaspace [show-loaders]` | Metaspace by loader |
| `VM.classloaders`, `VM.classloader_stats` | Loader hierarchy and per-loader stats |
| `VM.stringtable`, `VM.symboltable` | String/symbol table stats |
| `Thread.print [-l]` | Thread dump (`-l`: ownable synchronizers) |
| `Thread.dump_to_file -format=json <file>` | **All threads including virtual threads**, with containers |
| `Compiler.codecache`, `Compiler.queue`, `Compiler.codelist`, `Compiler.directives_add <file>` | JIT state |
| `JFR.start name=x settings=profile duration=120s filename=x.jfr`, `JFR.dump`, `JFR.stop`, `JFR.check` | Flight recordings |
| `VM.log …` | Reconfigure unified logging live |

## 9. Other tools

```bash
jstat -gcutil <pid> 1000                    # GC utilization per second (needs hsperfdata)
jfr print --events jdk.GarbageCollection,jdk.VirtualThreadPinned rec.jfr
jfr summary rec.jfr ; jfr metadata          # event catalogue
jhsdb jstack --pid <pid> --mixed            # native + Java frames (post-mortem: --core)
async-profiler: asprof -e cpu|alloc|lock|wall -d 30 -f out.html <pid>
java -jar jol-cli.jar internals|footprint|estimates …   # object layout
```

## 10. Important JFR events

| Event | Default | Shows |
|---|---|---|
| `jdk.GarbageCollection`, `jdk.GCPhasePause` | on | GC pauses |
| `jdk.ZAllocationStall` | on | ZGC stalls |
| `jdk.SafepointBegin` | on (≥ 10 ms; `profile`: 0 ms) | TTSP |
| `jdk.ObjectAllocationSample` | on (throttled) | Allocation profile |
| `jdk.OldObjectSample` | on | Leak candidates (path-to-roots on dump) |
| `jdk.ExecutionSample`, `jdk.CPUTimeSample` (25, exp., Linux) | on / opt-in | CPU profile |
| `jdk.JavaMonitorEnter`, `jdk.ThreadPark` | ≥ 20 ms | Lock contention |
| `jdk.VirtualThreadPinned`, `jdk.VirtualThreadSubmitFailed` | on | Loom problems |
| `jdk.Deoptimization`, `jdk.CodeCacheFull`, `jdk.Compilation` | on (thresholds) | JIT problems |
| `jdk.SocketRead/Write`, `jdk.FileRead/Write` | ≥ 1 ms, throttled 100/s | Slow I/O |
| `jdk.DirectBufferStatistics` | on | Direct buffer pool |
| `jdk.Deserialization` | off | Java deserialization activity (security) |
| `jdk.JavaExceptionThrow` / `jdk.ExceptionStatistics` | on, throttled 100/s (`exceptions=throttled`) / on (1 s period) | Exception throw sites / rates |
| `jdk.MethodTiming`, `jdk.MethodTrace` (25) | enabled, but **empty filter**, so nothing is recorded until you set one (`-XX:StartFlightRecording:method-timing=com.acme.Foo::bar`) | Method timing without agents (JEP 520) |
