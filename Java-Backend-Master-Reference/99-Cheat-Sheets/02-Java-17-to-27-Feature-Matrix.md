# 99.2 · Java 17 → 27 Feature Matrix (what's final, what's preview, where it's covered)

> **Legend:** ✅ final/product · 🧪 preview (needs `--enable-preview`) · 🔬 experimental/incubator · ❌ removed · 🎓 in 1Z0-830 (Java 21) and/or 1Z0-831 (Java 25) scope.
> Status is taken from the OpenJDK release pages for JDK 21–27 (GA dates: 21 = 2023-09-19, 25 = 2025-09-16, 26 = 2026-03-17, 27 = 2026-09-15). Preview APIs change between releases, so pin preview code to one JDK.

---

## 1. Language

| Feature | JEP(s) | 17 | 21 | 25 | 26/27 | Covered in |
|---|---|---|---|---|---|---|
| Records 🎓 | 395 | ✅ | ✅ | ✅ | ✅ | [2.2 §3](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#3-records-jdk-16-jep-395-) |
| Sealed classes 🎓 | 409 | ✅ | ✅ | ✅ | ✅ | [2.2 §4](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#4-sealed-classes-and-interfaces-jdk-17-jep-409-) |
| Pattern matching for `instanceof` 🎓 | 394 | ✅ | ✅ | ✅ | ✅ | [2.2 §5.1](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#51-instanceof-patterns-and-flow-scoping) |
| Switch expressions 🎓 | 361 | ✅ | ✅ | ✅ | ✅ | [2.8 C4](../02-Core-Java/08-Interview-and-Cert-QA.md#c4--switch-arrows-vs-fall-through) |
| Text blocks 🎓 | 378 | ✅ | ✅ | ✅ | ✅ | [2.2 §1.4](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#14-api-facts--traps-) |
| Pattern matching for `switch` 🎓 | 441 | 🧪 | ✅ | ✅ | ✅ | [2.2 §5](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#5-pattern-matching-) |
| Record patterns 🎓 | 440 | — | ✅ | ✅ | ✅ | [2.2 §5.4](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#54-runnable-data-oriented-programming-end-to-end) |
| Unnamed variables and patterns `_` 🎓 | 443→456 | — | 🧪 | ✅ (22) | ✅ | [2.2 §5.2](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#52-switch-with-patterns--semantics) |
| Flexible constructor bodies 🎓(831) | 447→482→492→513 | — | — | ✅ | ✅ | [2.2 §7](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#7-flexible-constructor-bodies-jdk-25-jep-513-) |
| Module import declarations 🎓(831) | 476→494→511 | — | — | ✅ | ✅ | [1.1 §10.8](../01-JVM-Internals/01-ClassLoading-Linking-JPMS.md#108-module-import-declarations-jdk-25-jep-511-) |
| Compact source files and instance `main` 🎓(831) | 445→463→477→495→512 | — | 🧪 | ✅ | ✅ | [1.7 C15](../01-JVM-Internals/07-Interview-and-Cert-QA.md) |
| Primitive types in patterns | 455→488→507→530→532 | — | — | 🧪 | 🧪 (4th/5th) | [2.2 §5.6](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#56-primitive-patterns-preview-in-jdk-2527-jeps-507--530--532-) |
| String templates | 430/459 | — | 🧪 | ❌ (withdrawn in 23) | ❌ | — |
| Derived record creation (`with`) | 468 | — | — | Candidate | Not delivered | [2.2 §3](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#3-records-jdk-16-jep-395-) |
| Value classes (Valhalla) | 401 | — | — | EA builds only | EA builds only | [1.3 §6.4](../01-JVM-Internals/03-Object-Layout-Mechanical-Sympathy.md#64-other-mechanical-sympathy-levers-) |

## 2. Libraries / APIs

| Feature | JEP(s) | 21 | 25 | 26/27 | Covered in |
|---|---|---|---|---|---|
| Sequenced collections 🎓 | 431 | ✅ | ✅ | ✅ | [2.1 §7](../02-Core-Java/01-Collections-Internals.md#7-sequenced-collections-jdk-21-jep-431-) |
| Virtual threads 🎓 | 444 | ✅ | ✅ | ✅ | [3.6](../03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md) |
| `synchronized` without pinning | 491 | — | ✅ (24) | ✅ | [3.6 §4](../03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md#4-pinning-) |
| Structured concurrency | 453→462→480→499→505→525→533 | 🧪 | 🧪 (5th) | 🧪 (6th/7th) | [3.6 §7](../03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md#7-structured-concurrency-preview-jep-505-in-jdk-25-) |
| Scoped values 🎓(831) | 446→464→481→487→506 | 🧪 | ✅ | ✅ | [3.6 §8](../03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md#8-scoped-values-final-in-jdk-25-jep-506-) |
| Stream gatherers 🎓(831) | 461→473→485 | — | ✅ (24) | ✅ | [2.3 §5](../02-Core-Java/03-Lambdas-Streams-Collectors-Gatherers.md#5-stream-gatherers-jdk-24-final-jep-485-) |
| Foreign Function & Memory API | 424→434→442→454 | 🧪 | ✅ (22) | ✅ | [1.2 §8](../01-JVM-Internals/02-Runtime-Data-Areas-Off-Heap-FFM.md#8-the-foreign-function--memory-api-jdk-22-jep-454-) |
| Class-File API | 457→466→484 | — | ✅ (24) | ✅ | [2.4 §7.2](../02-Core-Java/04-Reflection-MethodHandles-VarHandles-Proxies-Bytecode.md#72-runnable-transforming-a-class-with-the-class-file-api-jdk-24) |
| Stable values → lazy constants | 502→526→531 | — | 🧪 | 🧪 | [1.1 §5.2](../01-JVM-Internals/01-ClassLoading-Linking-JPMS.md#52-the-initialization-lock-and-the-procedure-jvms-55-) |
| Vector API | 338…508→529→537 | 🔬 | 🔬 (10th) | 🔬 (11th/12th) | [1.3 §6.4](../01-JVM-Internals/03-Object-Layout-Mechanical-Sympathy.md#64-other-mechanical-sympathy-levers-) |
| `HttpClient` HTTP/3 | 517 | — | — | ✅ (26) | [4.4 §2](../04-IO-NIO-Serialization/04-Networking-Sockets-HttpClient-TLS.md#2-javanethttphttpclient-jdk-11-) |
| `ListFormat` | (JDK 22 API) | — | ✅ | ✅ | [2.6 §2.3](../02-Core-Java/06-Date-Time-Localization-Numerics.md#23-formatting-numbers-currency-messages-and-lists-) |
| Key Derivation Function API | 510 | — | ✅ | ✅ | — |
| PEM encodings | 470→524→538 | — | 🧪 | 🧪 | — |
| Post-quantum hybrid TLS 1.3 key exchange | 527 | — | — | ✅ (27) | [4.4 §4](../04-IO-NIO-Serialization/04-Networking-Sockets-HttpClient-TLS.md#4-tls-in-java-) |

## 3. JVM / runtime

| Feature | JEP(s) | 21 | 25 | 26 | 27 | Covered in |
|---|---|---|---|---|---|---|
| Generational ZGC | 439/474/490 | opt-in | **only mode** | ✅ | ✅ | [1.4 §5](../01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md#5-generational-zgc-in-depth-) |
| Generational Shenandoah | 404→521 | — | ✅ | ✅ | ✅ | [1.4 §6](../01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md#6-shenandoah-in-depth-) |
| G1 late barrier expansion | 475 | — | ✅ (24) | ✅ | ✅ | [1.4 §3.2](../01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md#32-g1s-two-barriers) |
| G1 throughput: fewer synchronizations | 522 | — | — | ✅ | ✅ | same |
| G1 default in all environments | 523 | — | — | — | ✅ | [1.4 §2](../01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md#2-the-collectors-at-a-glance-) |
| Compact object headers | 450→519→534 | — | product (opt-in) | product | **default** | [1.3 §2.5](../01-JVM-Internals/03-Object-Layout-Mechanical-Sympathy.md#25-compact-object-headers-jep-450--519--534-) |
| Lightweight locking default (`LockingMode=2`) | — | opt-in | ✅ | ✅ | ✅ | [3.2 §1.2](../03-Concurrency-Loom/02-Synchronization-Locks-AQS.md#12-how-hotspot-implements-monitors-jdk-2127) |
| AOT class loading and linking | 483 | — | ✅ (24) | ✅ | ✅ | [1.5 §9](../01-JVM-Internals/05-JIT-Compilation-AOT-Native-Image.md#9-aot-in-2026-leyden-aot-cache-vs-graalvm-native-image-vs-crac-) |
| AOT command-line ergonomics, method profiling | 514/515 | — | ✅ | ✅ | ✅ | same |
| AOT object caching with any GC | 516 | — | — | ✅ | ✅ | same |
| JFR CPU-time profiling | 509 | — | 🔬 (Linux) | 🔬 | 🔬 | [99.1 §10](01-JVM-Flags-and-Diagnostic-Commands.md#10-important-jfr-events) |
| JFR cooperative sampling, method timing/tracing | 518/520 | — | ✅ | ✅ | ✅ | same |
| JFR in-process data redaction | 536 | — | — | — | ✅ | — |
| Security Manager | 411→486 | deprecated | ❌ permanently disabled (24) | ❌ | ❌ | [00 §7](../00-Executive-Architecture-Map.md#7-paradigm-5--integrity-by-default-and-native-interop) |
| `sun.misc.Unsafe` memory access | 471→498 | — | warns (24+) | warns | warns | [2.4 §5.3](../02-Core-Java/04-Reflection-MethodHandles-VarHandles-Proxies-Bytecode.md#53-migrating-off-sunmiscunsafe-jep-471--498-) |
| Restricted JNI | 472 | — | warns (24+) | warns | warns | [1.2 §8](../01-JVM-Internals/02-Runtime-Data-Areas-Off-Heap-FFM.md#8-the-foreign-function--memory-api-jdk-22-jep-454-) |
| "Final means final" (reflection mutation warnings) | 500 | — | — | ✅ (warnings) | ✅ | [2.2 §2](../02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#2-immutability--final-field-semantics-) |
| Dynamic agent loading warnings | 451 | ✅ | ✅ | ✅ | ✅ | [2.4 §8](../02-Core-Java/04-Reflection-MethodHandles-VarHandles-Proxies-Bytecode.md#8-java-agents-javalanginstrument-) |
| 32-bit x86 port | 501/503 | ✅ | ❌ (25) | ❌ | ❌ | — |

## 4. Defaults that changed under your feet

| Default | Old | New | Since |
|---|---|---|---|
| Default charset | Platform-dependent | **UTF-8** | 18 (JEP 400) |
| Biased locking | On | Removed | 15 disabled, 18 removed |
| Locking mode | Stack locking | Lightweight (lock-stack) | 23 |
| ZGC mode | Non-generational | Generational only | 23 default, 24 only |
| GC on < 2 CPUs or < ~1.8 GB | Serial | **G1** | 27 (JEP 523) |
| Object headers | 12 B | **8 B** | 27 default (JEP 534) |
| CLDR locale data | — | NNBSP before AM/PM in `en_US` times | 20 (CLDR 42) |
| COMPAT locale provider | Available | Removed | 23 |
| Jackson (library, not JDK) | Unknown props fail, depth 1,000 | Unknown props ignored, depth 500 | Jackson 3.0 (Spring Boot 4) |
