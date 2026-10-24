# Java Backend Master Reference — Deep Research Report (JDK 21/25 LTS, notes to JDK 27)

A production-grade deep dive into **Core Java, Advanced Java and modern enterprise Java backend engineering**, written for engineers aiming at architect-level understanding **and** the Oracle **Java SE 21/25 Developer Professional** certification (1Z0-830 / 1Z0-831).

Every concept is tied to its internal mechanics (JVM, OS, hardware), its production failure modes, and **runnable Java 25 code whose output was captured from real runs**, not written from memory.

> **Status (2026-10-24): all 8 pillars complete.** Run 1 delivered Pillars 1–4 (JVM, Core Java, concurrency, I/O). Run 2 delivered Pillars 5–8: persistence/JPA, Spring and microservices, AI engineering, and observability/security/testing. Same rules throughout: every sample was run, and every printed number came from a real run.

---

## What's inside

| # | Folder | Files | What you'll be able to do |
|---|---|---|---|
| 00 | [Executive Architecture Map](00-Executive-Architecture-Map.md) | 1 | Explain how JDK 21→27 changed backend design: virtual threads vs reactive, generational ZGC, compact headers, Leyden AOT, data-oriented programming, integrity by default |
| 1 | [JVM Internals](01-JVM-Internals/) | 7 | Debug class loading, Metaspace, native memory, GC (G1/ZGC/Shenandoah), JIT/escape analysis and AOT; read GC and safepoint logs; size containers |
| 2 | [Core Java](02-Core-Java/) | 8 | Know collections, strings, records/sealed/patterns, lambdas, streams and gatherers, reflection/MethodHandles/VarHandles/proxies/bytecode, generics, exceptions, `java.time`, localization and numerics at the implementation level |
| 3 | [Concurrency & Loom](03-Concurrency-Loom/) | 8 | Reason with the JMM; choose locks, atomics, executors and collections; master virtual threads, pinning, structured concurrency and scoped values; read thread dumps |
| 4 | [I/O, NIO, Networking & Serialization](04-IO-NIO-Serialization/) | 6 | Build and debug NIO/Netty servers, use zero-copy and mmap correctly, configure `HttpClient`/TLS/timeouts, and secure or choose serialization formats (Java serialization, Protobuf, Avro, Jackson 2 vs 3) |
| 5 | [Persistence: JDBC, HikariCP, JPA/Hibernate, Transactions](05-Persistence-JPA-Hibernate/) | 6 | Size connection pools; reason about the persistence context, dirty checking, flush and batching; kill N+1 and Cartesian products; pick isolation levels and locks on real PostgreSQL; avoid `@Transactional` proxy traps |
| 6 | [Spring & Microservices](06-Spring-Microservices/) | 7 | Explain the container lifecycle, post-processors, circular dependencies and AOP proxies; choose MVC + virtual threads vs WebFlux with measurements; build outbox, sagas and idempotency; compose Resilience4j correctly; run Kafka consumer groups, transactions and DLTs |
| 7 | [AI Engineering in Java](07-AI-Engineering/) | 7 | Call Claude with the official Java SDK (structured output, tools, streaming, caching, API version 2026-10-21); know what Spring AI and LangChain4j actually send; build MCP servers and clients; build and evaluate RAG; stream over SSE with real cancellation |
| 8 | [Observability, Security & Testing](08-Observability-Security-Testing/) | 7 | Profile with JFR, async-profiler and thread dumps; propagate OpenTelemetry context; build aggregatable latency metrics and JSON logs; harden Spring Security (JWT, mTLS, OWASP Top 10:2025); speed up and de-flake test suites (JUnit 6, Mockito 5, Testcontainers 2, ArchUnit); benchmark with JMH |
| 99 | [Cheat Sheets](99-Cheat-Sheets/) | 3 | [JVM flags and `jcmd`/JFR](99-Cheat-Sheets/01-JVM-Flags-and-Diagnostic-Commands.md), [Java 17→27 feature matrix](99-Cheat-Sheets/02-Java-17-to-27-Feature-Matrix.md), [concurrency and I/O decision guide](99-Cheat-Sheets/03-Concurrency-and-IO-Decision-Guide.md) |

Each pillar ends with two synthesis files:

* **`NN-Production-Failure-Modes-Diagnostics.md`**: incident playbooks (war stories), exact diagnostic commands, metrics and alert thresholds, and review checklists.
* **`NN-Interview-and-Cert-QA.md`**: rapid-fire flashcards, senior and architect scenarios, and **certification-style code questions** with verified answers.

### Full file index

<details><summary>Expand: all 61 files</summary>

**00** · [Executive Architecture Map](00-Executive-Architecture-Map.md)

**Pillar 1 — JVM Internals, Memory Management & Mechanical Sympathy**
1. [Class loading, linking, initialization & JPMS](01-JVM-Internals/01-ClassLoading-Linking-JPMS.md)
2. [Runtime data areas, native memory, direct buffers & the FFM API](01-JVM-Internals/02-Runtime-Data-Areas-Off-Heap-FFM.md)
3. [Object layout, compressed oops, compact headers & mechanical sympathy](01-JVM-Internals/03-Object-Layout-Mechanical-Sympathy.md)
4. [Garbage collection: G1, generational ZGC, Shenandoah, Parallel, Serial, Epsilon](01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md)
5. [JIT (C1/C2), escape analysis, deoptimization, Leyden AOT & Native Image](01-JVM-Internals/05-JIT-Compilation-AOT-Native-Image.md)
6. [Production failure modes & diagnostics](01-JVM-Internals/06-Production-Failure-Modes-Diagnostics.md)
7. [Interview & certification Q&A](01-JVM-Internals/07-Interview-and-Cert-QA.md)

**Pillar 2 — Core Java Deep Dive & Modern Language Evolution**
1. [Collections internals (HashMap, ConcurrentHashMap, sequenced, immutables)](02-Core-Java/01-Collections-Internals.md)
2. [Strings, immutability, records, sealed types, enums & pattern matching](02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md)
3. [Lambdas, streams, spliterators, collectors & gatherers](02-Core-Java/03-Lambdas-Streams-Collectors-Gatherers.md)
4. [Reflection, annotations, MethodHandles, VarHandles, proxies, bytecode & agents](02-Core-Java/04-Reflection-MethodHandles-VarHandles-Proxies-Bytecode.md)
5. [Generics, exceptions & the object model](02-Core-Java/05-Generics-Exceptions-Object-Model.md)
6. [`java.time`, localization & numerics](02-Core-Java/06-Date-Time-Localization-Numerics.md)
7. [Production failure modes & diagnostics](02-Core-Java/07-Production-Failure-Modes-Diagnostics.md)
8. [Interview & certification Q&A](02-Core-Java/08-Interview-and-Cert-QA.md)

**Pillar 3 — Concurrency, Multithreading & Project Loom**
1. [Java Memory Model](03-Concurrency-Loom/01-Java-Memory-Model.md)
2. [Synchronization, locks, AQS & deadlocks](03-Concurrency-Loom/02-Synchronization-Locks-AQS.md)
3. [Lock-free programming, CAS, atomics, ABA](03-Concurrency-Loom/03-Lock-Free-CAS-Atomics.md)
4. [Executors, ForkJoinPool & CompletableFuture](03-Concurrency-Loom/04-Executors-ForkJoin-CompletableFuture.md)
5. [Concurrent collections, synchronizers & ThreadLocal internals](03-Concurrency-Loom/05-Concurrent-Collections-Synchronizers-ThreadLocal.md)
6. [Virtual threads, pinning, structured concurrency & scoped values](03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md)
7. [Production failure modes & diagnostics](03-Concurrency-Loom/07-Production-Failure-Modes-Diagnostics.md)
8. [Interview & certification Q&A](03-Concurrency-Loom/08-Interview-and-Cert-QA.md)

**Pillar 4 — I/O, Networking & High-Performance Serialization**
1. [I/O models: blocking, NIO selectors, AIO, virtual threads + NIO.2 `Files`/`Path`](04-IO-NIO-Serialization/01-IO-Models-Blocking-NIO-AIO.md)
2. [Zero-copy, memory-mapped files & Netty architecture](04-IO-NIO-Serialization/02-Zero-Copy-MMAP-Netty.md)
3. [Serialization: Java serialization security, Protobuf, Avro, Jackson 2 vs 3](04-IO-NIO-Serialization/03-Serialization-Security-Protobuf-Avro-Jackson.md)
4. [Networking: sockets, timeouts, HttpClient, DNS, TLS, Unix-domain sockets](04-IO-NIO-Serialization/04-Networking-Sockets-HttpClient-TLS.md)
5. [Production failure modes & diagnostics](04-IO-NIO-Serialization/05-Production-Failure-Modes-Diagnostics.md)
6. [Interview & certification Q&A](04-IO-NIO-Serialization/06-Interview-and-Cert-QA.md)

**Pillar 5 — Persistence: JDBC, HikariCP, JPA/Hibernate, Transactions**
1. [JDBC internals, HikariCP & connection-pool sizing](05-Persistence-JPA-Hibernate/01-JDBC-HikariCP-Connection-Pooling.md)
2. [Persistence context, dirty checking, flush, IDs & batching, proxies, second-level cache](05-Persistence-JPA-Hibernate/02-JPA-Hibernate-Persistence-Context-Internals.md)
3. [N+1, fetch strategies, Cartesian products, pagination, projections](05-Persistence-JPA-Hibernate/03-Performance-NPlus1-Cartesian-Projections.md)
4. [ACID, isolation levels, locking, Spring `@Transactional`, OSIV](05-Persistence-JPA-Hibernate/04-Transactions-Isolation-Locking-Spring-Transactional.md)
5. [Production failure modes & diagnostics](05-Persistence-JPA-Hibernate/05-Production-Failure-Modes-Diagnostics.md)
6. [Interview & certification Q&A](05-Persistence-JPA-Hibernate/06-Interview-and-Cert-QA.md)

**Pillar 6 — Spring Internals & Microservice Patterns**
1. [Container internals: IoC lifecycle, post-processors, circular dependencies, AOP proxies](06-Spring-Microservices/01-Spring-Container-Internals-IoC-AOP.md)
2. [MVC on virtual threads vs WebFlux/Reactor, backpressure](06-Spring-Microservices/02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md)
3. [Transactional outbox, idempotent consumers, sagas, idempotency keys](06-Spring-Microservices/03-Outbox-Saga-Idempotency.md)
4. [Resilience4j: circuit breaker, retry, rate limiter, bulkhead, composition order](06-Spring-Microservices/04-Resilience4j-CircuitBreaker-RateLimiter-Bulkhead.md)
5. [Kafka: consumer groups, rebalancing, exactly-once, dead letters](06-Spring-Microservices/05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md)
6. [Production failure modes & diagnostics](06-Spring-Microservices/06-Production-Failure-Modes-Diagnostics.md)
7. [Interview & certification Q&A](06-Spring-Microservices/07-Interview-and-Cert-QA.md)

**Pillar 7 — AI Engineering in Java**
1. [The Claude API from Java: official SDK 3.x](07-AI-Engineering/01-Claude-API-Java-SDK.md)
2. [Spring AI 2.0 and LangChain4j 1.22: templates, structured output, tools, memory](07-AI-Engineering/02-Spring-AI-LangChain4j-Tools-Structured-Output.md)
3. [MCP servers and clients in Java](07-AI-Engineering/03-MCP-Servers-and-Clients-in-Java.md)
4. [RAG: chunking, embeddings, hybrid retrieval, vector stores](07-AI-Engineering/04-RAG-Embeddings-Chunking-Vector-Stores.md)
5. [Streaming LLM responses over SSE](07-AI-Engineering/05-SSE-Streaming-LLM-Responses.md)
6. [Production failure modes & diagnostics](07-AI-Engineering/06-Production-Failure-Modes-Diagnostics.md)
7. [Interview & certification Q&A](07-AI-Engineering/07-Interview-and-Cert-QA.md)

**Pillar 8 — Observability, Security & Testing**
1. [JFR, async-profiler, jcmd, thread dumps](08-Observability-Security-Testing/01-JVM-Profiling-JFR-async-profiler-Thread-Dumps.md)
2. [OpenTelemetry context propagation, Micrometer histograms, structured logging with MDC](08-Observability-Security-Testing/02-Observability-OpenTelemetry-Micrometer-Logging.md)
3. [Spring Security filter chain, OAuth2/OIDC & JWT, mTLS, OWASP Top 10:2025](08-Observability-Security-Testing/03-Security-Spring-Security-OAuth2-JWT-mTLS-OWASP.md)
4. [JUnit 6, Mockito 5, Spring test context caching, Testcontainers 2, ArchUnit](08-Observability-Security-Testing/04-Testing-JUnit-Mockito-Testcontainers-ArchUnit.md)
5. [JMH: microbenchmarks that tell the truth](08-Observability-Security-Testing/05-JMH-Benchmarking.md)
6. [Production failure modes & diagnostics](08-Observability-Security-Testing/06-Production-Failure-Modes-Diagnostics.md)
7. [Interview & certification Q&A](08-Observability-Security-Testing/07-Interview-and-Cert-QA.md)

**99 — Cheat sheets**: [flags & commands](99-Cheat-Sheets/01-JVM-Flags-and-Diagnostic-Commands.md) · [feature matrix](99-Cheat-Sheets/02-Java-17-to-27-Feature-Matrix.md) · [decision guide](99-Cheat-Sheets/03-Concurrency-and-IO-Decision-Guide.md)
</details>

---

## How this report was verified

| Item | Detail |
|---|---|
| JDK | Eclipse Temurin **25.0.4.1+1-LTS** (Windows 11 x64, 12 logical CPUs, 16 GB) |
| Java code blocks (all 8 pillars) | **297**. **251** complete programs were compiled **and run**; **17** were compile-checked (including **expected compile errors** for the exam traps); **29** are illustrative fragments |
| Result of the final full sweep (2026-10-24, one JVM at a time, 16.5 min) | **0 failures, 0 output differences**. All **125** "Output (verified)" blocks were compared line by line against a fresh run. The sweep's only failure was an illustrative snippet with a `main`; it became a complete, compile-checked example and was re-verified |
| Pillars 5–8 stack | Spring Boot **4.1.2** BOM: Spring Framework 7.0.10, Hibernate ORM 7.4.13, HikariCP 7.0.2, Spring Data 4.1.2, Spring Security 7.1.2, Micrometer 1.17.2, JUnit 6.0.3, Mockito 5.23.0, Testcontainers 2.0.5. Also: Reactor 3.8.8, Resilience4j 2.4.0, spring-kafka 4.1.2 / Kafka 4.2.2 (KRaft), OpenTelemetry 1.62.0, ArchUnit 1.5.1, JMH 1.37, Spring AI 2.0.2, LangChain4j 1.22.0, `anthropic-java` 3.3.0, MCP Java SDK 2.1.0, embedded PostgreSQL 18.6, H2 2.4.240 |
| External services | **None.** No API keys, no Docker, no cloud. The Claude API was a local mock speaking the Messages API wire format, so SDK and framework behavior (headers, JSON, SSE, retries, tool loops) is real while model text is scripted |
| Timing and measurement outputs | Labelled "one measured run". Real numbers from this laptop, never typed from memory. Ratios matter; absolute values vary by machine |
| JVM flags | All 87 distinct `-XX` flags mentioned were checked against `PrintFlagsFinal` (the 4 not present in JDK 25 are explicitly described as historical, debug-build or Linux-only) |
| JFR defaults | Read from JDK 25's own `default.jfc`/`profile.jfc` |
| Libraries used in samples | JOL 0.17 (`org.openjdk.jol:jol-cli`), ByteBuddy 1.18.16, Netty 4.2.19.Final (common, buffer, transport, resolver, handler, codec-base), Jackson 3.2.4 (`tools.jackson.core`) + annotations 2.22, and Jackson 2.22.4 for comparisons |
| JDK release facts | Checked against openjdk.org JEP and release pages (JDK 26 GA 2026-03-17; JDK 27 GA 2026-09-15) |

### Running the samples yourself

```bash
# most samples are single-file programs (JDK 25):
java --enable-preview --source 25 FanOutThreeWays.java          # preview only needed for StructuredTaskScope / primitive patterns
# samples marked with JVM options (shown in the hidden directive above each block, e.g. jvm="-Xmx64m"):
java -Xmx64m --source 25 LoaderLeak.java
# samples needing libraries: put the JARs on the class path
java -cp "jol-cli-0.17-full.jar" Footprint.java
java -cp "netty-common-4.2.19.Final.jar;netty-buffer-…;netty-transport-…;netty-resolver-…;netty-handler-…;netty-codec-base-…" NettyEcho.java
java -cp "jackson-databind-3.2.4.jar;jackson-core-3.2.4.jar;jackson-annotations-2.22.jar" JacksonThree.java
```

(On Linux and macOS use `:` instead of `;` in class paths.) Source-launcher mode compiles in memory. Use `javac` + `java -cp` for anything you want to profile seriously, and **JMH** for real benchmarks ([8.5](08-Observability-Security-Testing/05-JMH-Benchmarking.md)).

**Pillars 5–8 use real frameworks.** Each sample's hidden directive names a dependency set (`cp=@p5`, `@p6web`, `@p6kafka`, `@p7`, `@p7sdk`, `@p7mcp`, `@p8`, `@jmh`), which is a Spring Boot 4.1.2 BOM-managed Maven project. The easiest way to run one is to paste it into a Boot 4.1 project with the matching starters (listed in each file's "Verified stack" header). Samples marked `javac` contain a `package` line: compile them with `javac -d out` (add `-proc:full` for JMH) and run the main class. Nothing needs Docker or an API key:

* **PostgreSQL 18** ran embedded (zonky `embedded-postgres`). **Kafka 4.2** ran in-process in KRaft mode (`spring-kafka-test`).
* **Claude** calls went to a local JDK `HttpServer` that speaks the Messages API (JSON, SSE, errors, tool loops). **MCP** servers ran over stdio and Streamable HTTP on localhost.
* Embeddings came from a local ONNX model (LangChain4j `all-MiniLM-L6-v2`). JWTs and certificates were generated per run.

---

## Conventions

| Marker | Meaning |
|---|---|
| 🔥 | Must know: frequent in interviews and production incidents |
| ⚡ | Important: senior-level depth |
| 🧊 | Deep cut: specialist or architect knowledge |
| 🎓 | In scope for 1Z0-830 (Java SE 21) and/or 1Z0-831 (Java SE 25) |
| `<details>` | Answers are collapsed: predict first, then open |
| "Output (verified)" | Exact output of the program above it, captured on JDK 25 |
| "One measured run" | Real but machine-dependent timings |
| JDK tags | Features are labelled with the release where they became final, e.g. "(JDK 24, JEP 485)", or "preview" |

Certification practice questions are **original items written for this guide** in the exam's style. They are not real exam content.

---

## Study tracks

### A. Certification (1Z0-831 Java SE 25 Developer Professional; 1Z0-830 for Java 21)

Third-party sources (confirm on education.oracle.com) list **50 questions, 120 minutes, 68% to pass**. 1Z0-831 adds gatherers, scoped values, module import declarations, compact source files and flexible constructor bodies to the Java 21 syllabus.

| Exam domain (approx. weight) | Read | Practise |
|---|---|---|
| Date, time, text, numeric, boolean values (~11%) | [2.2](02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md), [2.5 §4](02-Core-Java/05-Generics-Exceptions-Object-Model.md#4-primitives-boxing-and-arithmetic-traps-), [2.6](02-Core-Java/06-Date-Time-Localization-Numerics.md) | [2.8](02-Core-Java/08-Interview-and-Cert-QA.md) C1–C3, C21, C25–C26, C33 |
| Program flow (~8%) | [2.2 §5](02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md#5-pattern-matching-) | 2.8 C4, C5, C24, C29 |
| OOP: records, sealed, nested, interfaces, enums (~18%) | [2.2](02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md), [2.5 §3](02-Core-Java/05-Generics-Exceptions-Object-Model.md#3-the-object-model-resolution-rules-the-jvm-and-javac-apply-), [1.1 §5](01-JVM-Internals/01-ClassLoading-Linking-JPMS.md#5-initialization-) | 2.8 C6–C8, C27–C28, C30, C32; [1.7](01-JVM-Internals/07-Interview-and-Cert-QA.md) C8–C9 |
| Exceptions (~8%) | [2.5 §2](02-Core-Java/05-Generics-Exceptions-Object-Model.md#2-exceptions--internals-costs-and-exam-rules-) | 2.8 C9–C12 |
| Arrays and collections (~8%) | [2.1](02-Core-Java/01-Collections-Internals.md) | 2.8 C14–C16, C31, C34 |
| Streams and lambdas, incl. gatherers (~9%) | [2.3](02-Core-Java/03-Lambdas-Streams-Collectors-Gatherers.md) | 2.8 C17–C20 |
| Packaging and deploying (modules, jlink) (~9%) | [1.1 §10](01-JVM-Internals/01-ClassLoading-Linking-JPMS.md#10-the-java-platform-module-system-jpms-internals-) | 1.7 C1–C7, C12–C15 |
| Concurrency, virtual threads, scoped values (~11%) | [Pillar 3](03-Concurrency-Loom/) | [3.8](03-Concurrency-Loom/08-Interview-and-Cert-QA.md) C1–C17 |
| I/O, serialization, NIO.2 (~11%) | [4.1 §2](04-IO-NIO-Serialization/01-IO-Models-Blocking-NIO-AIO.md#2-classic-javaio-and-what-the-exam-asks-), [4.3 §1–2](04-IO-NIO-Serialization/03-Serialization-Security-Protobuf-Avro-Jackson.md) | [4.6](04-IO-NIO-Serialization/06-Interview-and-Cert-QA.md) C1–C9 |
| Localization (~7%) | [2.6 §2](02-Core-Java/06-Date-Time-Localization-Numerics.md#2-localization-i18n--l10n-) | 2.8 C22 |

Suggested 6-week plan: weeks 1–2 Pillar 2 (files 01–06) plus its 🎓 questions; week 3 Pillar 3 (01, 02, 04, 05, 06) plus 3.8; week 4 Pillar 4 (01, 03) plus 4.6 and Pillar 1 (01 §10) plus 1.7 C; week 5 redo every question you missed, without opening the answers; week 6 timed mocks (50 questions / 120 min) from a reputable practice-exam provider.

### B. Spring Professional and backend frameworks (2V0-72.22 style)

JDBC isn't on 1Z0-830/831, and Oracle's exams don't cover Spring. The question banks of Pillars 5–8 are written in the style of the **Spring Certified Professional** exam and of backend interviews, with every code answer verified:

| Domain | Read | Practise |
|---|---|---|
| Container, beans, AOP | [6.1](06-Spring-Microservices/01-Spring-Container-Internals-IoC-AOP.md) | [6.7](06-Spring-Microservices/07-Interview-and-Cert-QA.md) |
| Data access, JDBC, transactions, JPA | [5.1](05-Persistence-JPA-Hibernate/01-JDBC-HikariCP-Connection-Pooling.md)–[5.4](05-Persistence-JPA-Hibernate/04-Transactions-Isolation-Locking-Spring-Transactional.md) | [5.6](05-Persistence-JPA-Hibernate/06-Interview-and-Cert-QA.md) |
| Spring MVC / WebFlux, REST | [6.2](06-Spring-Microservices/02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md) | 6.7 |
| Security | [8.3](08-Observability-Security-Testing/03-Security-Spring-Security-OAuth2-JWT-mTLS-OWASP.md) | [8.7](08-Observability-Security-Testing/07-Interview-and-Cert-QA.md) C3 |
| Testing | [8.4](08-Observability-Security-Testing/04-Testing-JUnit-Mockito-Testcontainers-ArchUnit.md) | 8.7 C1, C4 |
| Actuator, metrics, observability | [8.2](08-Observability-Security-Testing/02-Observability-OpenTelemetry-Micrometer-Logging.md), [6.6](06-Spring-Microservices/06-Production-Failure-Modes-Diagnostics.md) (health groups and circuit-breaker health) | 8.7 C2 |

The exam's objectives predate Boot 4. Know both the classic names (`@MockBean`) and their Boot 4 replacements (`@MockitoBean`), as flagged in the files.

### C. Senior and staff interview track

00 → 1.4 (GC) → 1.5 (JIT) → 2.1 (collections) → 3.1 (JMM) → 3.2/3.3 (locks, atomics) → 3.4 (executors) → 3.6 (Loom) → 4.1/4.2 (NIO, Netty) → 4.3 (serialization security) → 5.1–5.4 (pools, ORM, transactions) → 6.1–6.5 (Spring internals, concurrency models, distributed data, resilience, Kafka) → 8.1–8.2 (profiling, observability) → 8.3 (security). Add 7.1–7.5 if the role involves LLM features. Then all "B" scenario questions and every `NN-Production-Failure-Modes` file. Practise explaining the measured demos aloud: they make strong interview stories.

### D. Architect and production track

00 (ADRs, baseline JVM config) → the eight failure-mode files: [1.6](01-JVM-Internals/06-Production-Failure-Modes-Diagnostics.md), [2.7](02-Core-Java/07-Production-Failure-Modes-Diagnostics.md), [3.7](03-Concurrency-Loom/07-Production-Failure-Modes-Diagnostics.md), [4.5](04-IO-NIO-Serialization/05-Production-Failure-Modes-Diagnostics.md), [5.5](05-Persistence-JPA-Hibernate/05-Production-Failure-Modes-Diagnostics.md), [6.6](06-Spring-Microservices/06-Production-Failure-Modes-Diagnostics.md), [7.6](07-AI-Engineering/06-Production-Failure-Modes-Diagnostics.md), [8.6](08-Observability-Security-Testing/06-Production-Failure-Modes-Diagnostics.md) → the [decision guide](99-Cheat-Sheets/03-Concurrency-and-IO-Decision-Guide.md) → [flags & commands](99-Cheat-Sheets/01-JVM-Flags-and-Diagnostic-Commands.md). Turn the checklists into your team's review templates and runbooks. 8.6 §3 lists the alerts most teams are missing.

---

## Selected measured findings (highlights)

| Finding | Measured | Where |
|---|---|---|
| Compact object headers shrink `HashMap` entries | 58.5 → 50.5 B/entry (`new Object()` 16 → 8 B) | [1.3](01-JVM-Internals/03-Object-Layout-Mechanical-Sympathy.md) |
| Escape analysis removes allocation entirely | 960 MB → **0 B** for 10M iterations; a rare escape path disables it | [1.5](01-JVM-Internals/05-JIT-Compilation-AOT-Native-Image.md) |
| False sharing | 2,349 ms vs 693 ms (padded) | [1.3](01-JVM-Internals/03-Object-Layout-Mechanical-Sympathy.md) |
| Leyden AOT cache startup | 846 ms → 743 ms (CDS) → **624 ms** | [1.5](01-JVM-Internals/05-JIT-Compilation-AOT-Native-Image.md) |
| Silent Serial GC on 1 CPU | `Using Serial` (JDK ≤ 26) | [1.4](01-JVM-Internals/04-Garbage-Collection-G1-ZGC-Shenandoah.md) |
| Non-volatile stop flag | Loop never ends under C2; works under `-Xint` | [3.1](03-Concurrency-Loom/01-Java-Memory-Model.md) |
| StoreLoad reordering on x86 | `r1 = r2 = 0` in thousands of 2M Dekker trials; 0 with volatile | [3.1](03-Concurrency-Loom/01-Java-Memory-Model.md) |
| Fair `ReentrantLock` | ~230× lower throughput than non-fair | [3.2](03-Concurrency-Loom/02-Synchronization-Locks-AQS.md) |
| `LongAdder` vs `AtomicLong` at 8 threads | 711M vs 81M ops/s | [3.3](03-Concurrency-Loom/03-Lock-Free-CAS-Atomics.md) |
| Virtual threads, 10k × 100 ms blocking tasks | 153 ms vs 5,347 ms (200-thread pool) | [3.6](03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md) |
| No time slicing for VTs | A 10 ms sleep woke after **507 ms** behind CPU hogs | [3.6](03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md) |
| JDK 25 pinning | `synchronized` no longer pins; `<clinit>` blocking still does (JFR `pinnedReason`) | [3.6](03-Concurrency-Loom/06-Virtual-Threads-Structured-Concurrency-Scoped-Values.md) |
| ReDoS on JDK 25 | Classic `(a+)+b` defused by memoization; bounded `(?:a+){2,20}b` still exponential | [2.2](02-Core-Java/02-Strings-Records-Sealed-Pattern-Matching.md) |
| Jackson 3 changed defaults | Unknown props ignored; nesting depth 500; `java.time` built in | [4.3](04-IO-NIO-Serialization/03-Serialization-Security-Protobuf-Avro-Jackson.md) |
| Netty 4.2 default allocator | `AdaptiveByteBufAllocator` | [4.2](04-IO-NIO-Serialization/02-Zero-Copy-MMAP-Netty.md) |
| Hibernate auto-flush with a big persistence context | 500 lookups: **3.5 s** with 50,000 managed entities vs ~80 ms without | [5.2](05-Persistence-JPA-Hibernate/02-JPA-Hibernate-Persistence-Context-Internals.md) |
| `StatelessSession` doesn't batch by default | 5,000 inserts → **5,100** round trips vs 201 with a batched `Session` | [5.2](05-Persistence-JPA-Hibernate/02-JPA-Hibernate-Persistence-Context-Internals.md) |
| Bag + set fetched in one query | 200,000 JDBC rows and `books=400` (real: 20) vs 20,000 rows with one query per collection | [5.3](05-Persistence-JPA-Hibernate/03-Performance-NPlus1-Cartesian-Projections.md) |
| `PESSIMISTIC_WRITE` on PostgreSQL | Renders `for no key update`, not `for update` | [5.4](05-Persistence-JPA-Hibernate/04-Transactions-Isolation-Locking-Spring-Transactional.md) |
| `@Async` field cycle in Spring 7 | Starts **without error**; one side holds the raw bean and runs synchronously | [6.1](06-Spring-Microservices/01-Spring-Container-Internals-IoC-AOP.md) |
| 100 ms blocking endpoint, 400 clients | Platform threads ~1,700 req/s; **virtual threads ~3,300**; WebFlux ~3,050; `sleep` on the event loop **106** | [6.2](06-Spring-Microservices/02-MVC-Virtual-Threads-vs-WebFlux-Backpressure.md) |
| Resilience4j fallback on the inner `@CircuitBreaker` | Disables `@Retry` entirely (target invoked once) | [6.4](06-Spring-Microservices/04-Resilience4j-CircuitBreaker-RateLimiter-Bulkhead.md) |
| Kafka 4.2 zombie transactional producer | Fenced with `InvalidProducerEpochException` | [6.5](06-Spring-Microservices/05-Kafka-Consumer-Groups-Rebalancing-EOS-DLQ.md) |
| Anthropic Java SDK 3.x | Sends API version `2026-10-21` (rejects `temperature`) with `Authorization: Bearer` | [7.1](07-AI-Engineering/01-Claude-API-Java-SDK.md) |
| Hybrid retrieval (BM25 + vectors, RRF) | hit@5 **13/14** vs 10/14 for vectors alone | [7.4](07-AI-Engineering/04-RAG-Embeddings-Chunking-Vector-Stores.md) |
| Client disconnect during a Spring AI stream | Upstream generation kept going (billed tokens) unless the bridge cancels it | [7.5](07-AI-Engineering/05-SSE-Streaming-LLM-Responses.md) |
| Averaging per-instance p99s | **595 ms** vs true p99 **1,057 ms** | [8.2](08-Observability-Security-Testing/02-Observability-OpenTelemetry-Micrometer-Logging.md) |
| Spring 7 test-context pausing | Inactive cached contexts' lifecycle beans stopped on context switch; `@MockitoBean` → a new context | [8.4](08-Observability-Security-Testing/04-Testing-JUnit-Mockito-Testcontainers-ArchUnit.md) |
| JMH on JDK 25 | Unused `Math.sqrt` eliminated (0.36 ns = baseline); unused `Math.log` **not** (~6 ns: stub call) | [8.5](08-Observability-Security-Testing/05-JMH-Benchmarking.md) |

---

## Primary sources

* JEP index: <https://openjdk.org/jeps/0> · JDK release pages: <https://openjdk.org/projects/jdk/25/>, `/26/`, `/27/`
* JVMS and JLS SE 25: <https://docs.oracle.com/javase/specs/>
* HotSpot GC Tuning Guide, Troubleshooting Guide, Virtual Threads guide (JDK 25 docs): <https://docs.oracle.com/en/java/javase/25/>
* Aleksey Shipilëv (JVM Anatomy Quarks, JMM Pragmatics), Doug Lea (JSR-133 Cookbook, j.u.c design papers), Martin Thompson (mechanical sympathy), Brian Goetz (*Java Concurrency in Practice*, data-oriented programming), Ron Pressler (Loom).
* Netty, Jackson, Protobuf, Avro, OWASP official documentation (links inside each file).
* **Pillars 5–8:** HikariCP wiki and CHANGES; Hibernate ORM 7.0 and 7.4 documentation; PostgreSQL 18 documentation (explicit locking, transaction isolation); Spring Framework 7.0 and Spring Boot 4.1 reference documentation; Spring Security 7.1 reference; Resilience4j 2.4 documentation; Apache Kafka 4.x documentation, KIP-848 and KIP-1030; IETF `draft-ietf-httpapi-idempotency-key-header`; Anthropic API docs and the `anthropic-sdk-java` CHANGELOG; Spring AI 2.0 and LangChain4j 1.22 docs; the MCP specification (2025-11-25) and Java SDK; OpenTelemetry specification (W3C Trace Context Level 2, messaging semantic conventions); Micrometer docs; OWASP Top 10:2025; JUnit 6.0 release notes; Mockito, Testcontainers 2.0 and ArchUnit docs; OpenJDK JMH samples. Each file's header lists its own sources.
