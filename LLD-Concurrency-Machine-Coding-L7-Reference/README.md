# LLD, Concurrency Machine Coding and Modern OOP/DOP: an L7 Reference (Java 21/25 + C++23)

A Principal-level (FAANG L7) knowledge base on low-level design, concurrency machine coding, and modern object-oriented and data-oriented architecture. It covers 20 complete, thread-safe problems, and **every code sample is written twice, in Java 21/25 and in C++23**. Every listing compiles warning-free and runs its own self-test; the outputs shown in the files are real runs.

---

## Status

| Folder | Contents | Status |
|---|---|---|
| [01-First-Principles-L7-Rubric-and-Modern-Java-OOP](01-First-Principles-L7-Rubric-and-Modern-Java-OOP/) | L5/L6/L7 rubric + five-level calibration exhibit; SOLID, composition, sealed/record ADTs, value objects, typestate, layout; JMM/C++ memory model, CAS, AQS, StampedLock/seqlock, striping, false sharing, clock injection, stress harness | ✅ **Done 2026-10-27**: 3 files, ~54k words, 31 verified listings |
| 02-Design-Patterns-Reimagined-for-High-Throughput-Java | State machines (enum vs sealed, optimistic transitions); strategy / chain / decorator / specification DSL; observer, event bus, command undo/redo, double-dispatch visitor | ⏳ next |
| 03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5 | P1 LRU/LFU/TTL cache (Caffeine architecture) · P2 rate limiter · P3 timing wheel scheduler · P4 in-memory Kafka · P5 connection pool + circuit breaker | ⏳ |
| 04-Tier2-Resource-Allocation-and-Lock-Contention-P6-to-P10 | P6 BookMyShow · P7 parking lot · P8 elevator · P9 ride dispatch · P10 meeting rooms | ⏳ |
| 05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15 | P11 Splitwise · P12 order book · P13 double-entry ledger · P14 vending/ATM · P15 flash sale | ⏳ |
| 06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20 | P16 in-memory DB · P17 async logger · P18 multi-level cache + file system · P19 chess/snakes-ladders · P20 rule engine + DAG workflow | ⏳ |
| 07-Classic-Multithreading-Synchronization-Bar-Raisers | Writer-preference RW lock on custom AQS; dining philosophers, unisex bathroom, H2O, FizzBuzz barriers; parallel DAG executor | ⏳ |
| 08-Master-Templates-GitHub-References-and-Bar-Raiser-Playbook | 60-minute execution blueprint + skeletons; 25 curveballs and defences; curated open-source codebases | ⏳ |

The folders are generated one per turn, in order.

---

## Folder 01 at a glance

| File | What you get |
|---|---|
| [01 · L5 vs L6 vs L7 rubric](01-First-Principles-L7-Rubric-and-Modern-Java-OOP/01-l5-vs-l6-vs-l7-lld-and-machine-coding-evaluation-rubric.md) | 14-dimension rubric, hard gates, weights, how levels are decided; **one seat-hold service written at five levels** and run through one battery (double bookings measured, a 3-thread deadlock captured, the L6 stale-webhook ABA bug reproduced, the L7 fencing-token fix); correctness proof; 8 curveballs; 25 red flags; scorecard; 6 bar-raiser chains |
| [02 · SOLID, composition, data-oriented Java](01-First-Principles-L7-Rubric-and-Modern-Java-OOP/02-solid-composition-and-data-oriented-java21-sealed-records.md) | The expression problem as the core LLD decision; SOLID reframed; fragile base class measured in both languages; flags vs sealed `OrderState` (16 → 6 legal states, 128 → 6 shapes); value objects and money; typestate with real compiler errors; GoF vs modern idiom table; Java 22–25 and C++23 deltas with a library-availability matrix; AoS vs SoA and JEP 519 compact headers measured |
| [03 · Concurrency primitives](01-First-Principles-L7-Rubric-and-Modern-Java-OOP/03-concurrency-primitives-cas-stampedlock-striping-and-clock-injection.md) | DRF-SC; happens-before in both languages; access-mode → x86/ARM codegen; the store-buffer litmus test measured; CAS retry storms, `LongAdder`, CAS identity vs bits; AQS internals and the fair-lock cost; a futex mutex; `StampedLock` vs RRWL vs seqlock; CHM bin locking; four deadlock cures; false sharing and SPSC rings; `Clock` vs `Ticker`, `nanoTime` overflow, NTP steps, virtual time; the reusable stress harness |

### Listing index (Folder 01)

| # | Java | C++ | One-line summary |
|---|---|---|---|
| 1.1 | `SeatHoldLevels.java` | `seat_hold_levels.cpp` | Five levels of one seat-hold service under one test battery |
| 2.1 | `OrderStateMachine.java` | `order_state_machine.cpp` | Flags vs sealed/variant state ADT; exhaustive transitions; optimistic CAS |
| 2.2 | `CompositionOverInheritance.java` | `composition_over_inheritance.cpp` | Fragile base class, LSP in the JDK, diamonds, thread-unsafe decorators |
| 2.3 | `ValueObjects.java` | `value_objects.cpp` | Money, rounding, allocation, strong ids, parse-don't-validate, equality traps |
| 2.4 | `TypestateOrders.java` + `TypestateMisuse.java` | `typestate_orders.cpp` | Typestate; illegal transitions rejected by javac / GCC / Clang |
| 2.5 | `Java25Delta.java` | `cpp23_delta.cpp` | JEPs 456/505/506/507/511/513 + gatherers; `expected`, deducing `this`, ranges, a jthread scope |
| 2.6 | `AosVsSoa.java` | `aos_vs_soa.cpp` | Memory layout: AoS vs SoA, compact headers, pointer chasing |
| 3.1 | `StoreBufferLitmus.java` | `store_buffer_litmus.cpp` | Which access modes forbid `(0,0)` |
| 3.2 | `LostUpdates.java` | `lost_updates.cpp` | Check-then-act, `updateAndGet` retries, `LongAdder`, CAS semantics |
| 3.3 | `AqsSynchronizers.java` | `futex_mutex.cpp` | AQS latch, mutex, conditions; Drepper's futex mutex |
| 3.4 | `ReadMostlyLocks.java` | `seqlock_vs_shared_mutex.cpp` | Read-mostly locking; a race-free C++ seqlock |
| 3.5 | `OrderedLocking.java` | `ordered_locking.cpp` | Deadlock and cures, striping, CHM bin locks |
| 3.6 | `FalseSharingRing.java` | `false_sharing_ring.cpp` | False sharing; SPSC ring with cached indices |
| 3.7 | `ClockInjection.java` | `clock_injection.cpp` | Deterministic time and a virtual scheduler |
| 3.8 | `StressHarness.java` | `stress_harness.cpp` | The harness reused by all 20 problems |

---

## Conventions

- **Tags:** 🔥 asked constantly · ⚡ high-leverage differentiator · 🧊 deep cut · ⚠ verify (release-, platform- or company-dependent).
- **Outputs:** **Output (verified)** means deterministic; a rerun produces the same text. **One measured run** means timings or race counts, which vary between runs; ranges are given where several runs were taken. Self-test lines (`SELF-TEST OK`) assert the guarantees, never the measured values.
- **Listings** are single files. A Java listing has no package and runs with `java Name.java` (or javac + java). A C++ listing has one `main`. The first line is always `// Name.java - …` or `// name.cpp - …`, which is what the extraction gate keys on.
- **Java/C++ parity:** the same design and the same test in both languages, written idiomatically in each. Where C++ must differ (data races are UB, `std::mutex` isn't recursive, deadlocked threads can't be joined, `long` is 32-bit on Windows), the file says so at that point.
- **Bar-raiser chains** use four parts: prompt → typical L5 answer → why it fails → L7 defence. The answers are in `<details>` blocks so you can self-test.
- **Interview questions are original**, not leaked or recalled questions. Company-format statements are marked ⚠.

## Toolchain and verification method

| Component | Version / flags |
|---|---|
| Java | Temurin **25.0.4.1**; `javac --release 21 -Xlint:all -Werror` (Listing 2.5: `--release 25 --enable-preview`, `-Xlint:all,-preview`) |
| C++ (1) | **GCC 16.2** (MinGW-w64 UCRT, posix threads), libstdc++, static; `-lstdc++exp` for `std::print` |
| C++ (2) | **Clang 21.1** + libc++ (via Zig 0.16), target `x86_64-windows-gnu` |
| C++ flags | `-std=c++23 -O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion` |
| Hardware | Intel Core i5-11260H (6C/12T, Tiger Lake), Windows 11 |

The gate for every folder:
1. Extract every listing from the published Markdown.
2. Check the extraction is byte-identical to the source that produced the outputs.
3. Recompile everything with both C++ compilers and javac, and rerun.
4. Diff the deterministic outputs, and confirm every self-test passes.
5. Check that the expected compile failures still fail.
6. Check relative links and anchors.

Folder 01 gate result (2026-10-27):
- **31 listings extracted from the Markdown, byte-identical to the sources**; all recompile warning-free under javac, GCC and Clang, and **all self-tests pass**.
- **15 output files identical on rerun; 33 differ only in measured values** (timings, race counts, which threads deadlocked); 0 structural differences.
- Expected compile failures still fail: javac 3 errors, GCC 3, Clang 3.
- **56 relative links and anchors OK.** External URLs: 36 of 41 return 200. The other 5 are ACM DOIs that ACM's bot filter answers with 403; each was confirmed through the doi.org handle API and its title checked against Crossref.
- The gate's rerun found one real nondeterminism bug: `Map.copyOf` iteration order in Listing 2.4. It was fixed, and the lesson is now part of file 02.

## Where this KB refines the brief

1. **Folder names follow the repository blueprint tree.** The role text abbreviates Folders 01 and 08 differently; the tree's names are used.
2. **Files are written straight to disk**, so there are no `### FILE:` headers in chat. The folder *is* the repository.
3. **"Java 21/25":** listings compile with `--release 21` so they run on either LTS. Java 22–25 features are isolated in Listing 2.5, and preview features are marked as preview.
4. **Guava `Striped`** is re-implemented in a few lines (no third-party dependency) with Guava's documented `bulkGet` contract: sorted, de-duplicated stripes.
5. **Read-write locks are not a default for read-heavy data.** The measurements show `ReentrantReadWriteLock` *slower* than `synchronized` for short critical sections (and `std::shared_mutex` slower than `std::mutex`). Optimistic reads or immutable snapshots are the read-mostly answer.
6. **128-byte padding** is recommended for portability, but on this CPU it measured no better than 64 B. The file reports the measurement rather than the folklore.
7. **`AtomicReference<State>` CAS compares identity.** That's correct when you CAS from the instance you read, and a trap otherwise. C++ `compare_exchange` compares bits (`-0.0`/`NaN` cases measured).
8. **C++ `std::atomic<std::shared_ptr>`** isn't lock-free in libstdc++ and is absent from libc++ 21, so the portable C++ aggregate uses a mutex.
9. **Fair locks** measured ~160× slower than barging locks; the rubric treats an unmeasured `new ReentrantLock(true)` as a red flag.
10. **Bugs found while building the listings are kept and documented** where they teach something:
    - GCC turning a runtime `memory_order` into `seq_cst`;
    - ADL selecting `std::apply`;
    - `condition_variable_any::wait_for(stop_token)` returning `pred()`;
    - `long` overflow on Windows;
    - a `nanoTime` wrap test that needed the right instant.

## Related KBs in this workspace

- [Java Backend Master Reference](../Java-Backend-Master-Reference/): JVM, Loom and the JDK concurrency libraries in depth.
- [Distributed Systems Design L7 Reference](../Distributed-Systems-Design-L7-Reference/): where these in-process designs go when they become distributed (fencing, idempotency, consensus).
- [CP Codeforces Master Kit](../CP-Codeforces-Master-Kit/): the algorithms behind P10 (interval trees), P11 (min cash flow), P12 (ordered maps).
