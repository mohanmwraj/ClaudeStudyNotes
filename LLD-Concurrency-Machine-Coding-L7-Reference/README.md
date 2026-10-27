# LLD, Concurrency Machine Coding and Modern OOP/DOP: an L7 Reference (Java 21/25 + C++23)

A Principal-level (FAANG L7) knowledge base on low-level design, concurrency machine coding, and modern object-oriented and data-oriented architecture.
- It covers 20 complete, thread-safe problems, the classic synchronization bar-raisers and an interview playbook.
- **Every code sample is written twice, in Java 21/25 and in C++23.**
- Every listing compiles warning-free and runs its own self-test. The outputs shown in the files are real runs, and a final gate re-extracted and re-ran all of them.

**Size:** 8 folders, 32 files, ~235k words (including code), **85 verified listings**.

---

## Status: complete

| Folder | Contents | Status |
|---|---|---|
| [01-First-Principles-L7-Rubric-and-Modern-Java-OOP](01-First-Principles-L7-Rubric-and-Modern-Java-OOP/) | L5/L6/L7 rubric + five-level calibration exhibit; SOLID, composition, sealed/record ADTs, value objects, typestate, layout; JMM/C++ memory model, CAS, AQS, StampedLock/seqlock, striping, false sharing, clock injection, stress harness | ✅ 2026-10-27 · 3 files · 31 listings |
| [02-Design-Patterns-Reimagined-for-High-Throughput-Java](02-Design-Patterns-Reimagined-for-High-Throughput-Java/) | State machines (enum vs sealed, optimistic transitions); strategy / chain / decorator / specification DSL; observer, event bus, command undo/redo, double-dispatch visitor | ✅ 2026-10-27 · 3 files · 6 listings |
| [03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5](03-Tier1-Concurrency-and-Infrastructure-Machine-Coding-P1-to-P5/) | P1 LRU/LFU/TTL cache (Caffeine architecture) · P2 rate limiters · P3 timing wheel · P4 in-memory Kafka · P5 connection pool + circuit breaker | ✅ 2026-10-27 · 5 files · 10 listings |
| [04-Tier2-Resource-Allocation-and-Lock-Contention-P6-to-P10](04-Tier2-Resource-Allocation-and-Lock-Contention-P6-to-P10/) | P6 BookMyShow · P7 parking lot · P8 elevator · P9 ride dispatch · P10 meeting rooms | ✅ 2026-10-27 · 5 files · 10 listings |
| [05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15](05-Tier3-FinTech-Commerce-and-Ledger-Engines-P11-to-P15/) | P11 Splitwise · P12 order book · P13 double-entry ledger · P14 vending/ATM · P15 flash sale | ✅ 2026-10-27 · 5 files · 10 listings |
| [06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20](06-Tier4-Data-Engines-Games-and-Extensibility-P16-to-P20/) | P16 in-memory DB + MVCC · P17 async logger · P18 file system + multi-level cache · P19 chess / snakes & ladders · P20 rule engine + JSON workflow | ✅ 2026-10-27 · 5 files · 10 listings |
| [07-Classic-Multithreading-Synchronization-Bar-Raisers](07-Classic-Multithreading-Synchronization-Bar-Raisers/) | Writer-preference RW lock on a custom AQS; dining philosophers, unisex bathroom, H2O, FizzBuzz; parallel DAG executor with CompletableFuture, virtual threads and C++ coroutines | ✅ 2026-10-28 · 3 files · 6 listings |
| [08-Master-Templates-GitHub-References-and-Bar-Raiser-Playbook](08-Master-Templates-GitHub-References-and-Bar-Raiser-Playbook/) | 60-minute blueprint + a self-testing skeleton; 25 requirement changes with refactoring defences; curated Java and C++ codebases | ✅ 2026-10-28 · 3 files · 2 listings |

**Every problem file has the same spine:**
1. problem and scope;
2. domain model and invariants;
3. concurrency and contention analysis, with **measured** tables;
4. the Java listing + output;
5. the C++ listing + GCC and Clang outputs;
6. L5 → L6 → L7;
7. curveballs;
8. bar-raiser chains;
9. failure modes + checklist;
10. references.

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

### Listing index (Folders 02–08)

| File | Java | C++ | One-line summary |
|---|---|---|---|
| 02.1 | `StateMachines.java` | `state_machines.cpp` | Table-driven enum FSM vs sealed-state FSM; optimistic (versioned) transitions |
| 02.2 | `PricingRulesDsl.java` | `pricing_rules_dsl.cpp` | Strategy, phased decorators, chain of responsibility, a specification DSL, hot-swapped rules |
| 02.3 | `EventBusCommandVisitor.java` | `event_bus_command_visitor.cpp` | Event bus (ordering, isolation, mailboxes), command undo/redo, double dispatch |
| P1 | `CaffeineStyleCache.java` | `caffeine_style_cache.cpp` | LRU/LFU/TTL; why LRU `get()` is a write; Caffeine-style read buffers; TinyLFU |
| P2 | `RateLimiters.java` | `rate_limiters.cpp` | Token bucket (CAS on immutable state), GCRA, windows, and their races |
| P3 | `TimingWheelScheduler.java` | `timing_wheel_scheduler.cpp` | Hierarchical timing wheel (O(1) add/cancel) vs a heap scheduler |
| P4 | `MiniKafkaBroker.java` | `mini_kafka_broker.cpp` | Segmented log partitions, consumer groups, fenced offset commits (EBR in C++) |
| P5 | `PoolAndBreaker.java` | `pool_and_breaker.cpp` | Bounded blocking pool (semaphore + deque) and a lock-free ring-bit circuit breaker |
| P6 | `BookMyShow.java` | `book_my_show.cpp` | Tiered seat holds, per-user limits, fenced idempotent webhooks, flash crowd |
| P7 | `ParkingLot.java` | `parking_lot.cpp` | Nearest-spot allocation by CAS on bitmaps vs skip list vs one lock; phased pricing |
| P8 | `ElevatorSystem.java` | `elevator_system.cpp` | Event-driven cars; SSTF vs LOOK vs destination dispatch; starvation measured |
| P9 | `RideDispatch.java` | `ride_dispatch.cpp` | Geo-grid buckets, correct ring search, CAS driver states |
| P10 | `MeetingRooms.java` | `meeting_rooms.cpp` | Floor/ceiling interval checks, per-room RW locks, RRULE series across DST |
| P11 | `SplitwiseLedger.java` | `splitwise_ledger.cpp` | Exact splits (largest remainder), CAS-published group ledger, min-cash-flow settlement |
| P12 | `OrderBookEngine.java` | `order_book_engine.cpp` | Price-time book, O(1) cancel, single-writer sequenced engine; 1M-command hash identical across languages |
| P13 | `WalletLedger.java` | `wallet_ledger.cpp` | Double entry, ordered locking, idempotency state machine with leases and fencing |
| P14 | `VendingAtm.java` | `vending_atm.cpp` | State machines, greedy chain vs backtracking change, saga rollback, committed events |
| P15 | `FlashSale.java` | `flash_sale.cpp` | Striped inventory without a hot row, TTL holds, stackable vs exclusive promotions |
| P16 | `MiniDb.java` | `mini_db.cpp` | Schema, hash + ordered indexes, predicate planner, MVCC, write skew |
| P17 | `AsyncLogger.java` | `async_logger.cpp` | MPSC ring of pooled events, BLOCK/DROP, rolling files, appender isolation, MDC |
| P18 | `FileSystemCache.java` | `file_system_cache.cpp` | Composite inodes, hand-over-hand locking, rename lock, versioned cache fills |
| P19 | `BoardGames.java` | `board_games.cpp` | Chess with perft-verified undo, checkmate, double-submit race; snakes & ladders |
| P20 | `WorkflowEngine.java` | `workflow_engine.cpp` | JSON → validated DAG, rules, retries, compensation, journal resume, exactly-once fan-in |
| 07.1 | `RwLocks.java` | `rw_locks.cpp` | Reader vs writer preference, a custom AQS, RRWL, `std::shared_mutex`, optimistic reads |
| 07.2 | `ClassicSync.java` | `classic_sync.cpp` | Dining philosophers, unisex bathroom, H2O, FizzBuzz, each verified |
| 07.3 | `DagExecutor.java` | `dag_executor.cpp` | CompletableFuture vs counters, virtual threads vs pools, C++20 coroutines, cancellation |
| 08.1 | `MachineCodingSkeleton.java` | `machine_coding_skeleton.cpp` | The 60-minute starter that already passes its own stress test |

---

## Conventions

- **Tags:** 🔥 asked constantly · ⚡ high-leverage differentiator · 🧊 deep cut · ⚠ verify (release-, platform- or company-dependent).
- **Outputs:** **Output (verified / deterministic)** means a rerun produces the same text. **One measured run** means timings or race counts, which vary between runs; ranges are given where several runs were taken. Self-test lines (`SELF-TEST OK`) assert the guarantees, never the measured values.
- **Cross-language determinism:** simulations use the same SplitMix64 generator in both languages, so deterministic sections (cache hit rates, order-book event hashes, perft counts, planner candidate counts) are byte-identical in Java, GCC and Clang.
- **Listings** are single files. A Java listing has no package and runs with `java Name.java` (or javac + java). A C++ listing has one `main`. The first line is always `// Name.java - …` or `// name.cpp - …`, which is what the extraction gate keys on.
- **Java/C++ parity:** the same design and the same test in both languages, written idiomatically in each. Where C++ must differ (data races are UB, so naive races use relaxed atomics; `std::atomic<std::shared_ptr>` is missing from libc++; there's no concurrent skip list or virtual threads), the file says so at that point.
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
4. Diff the outputs: identical, or differing only in measured values.
5. Confirm every self-test passes, and that the expected compile failures still fail.
6. Check relative links, anchors and external URLs.

**Folder 01 gate (2026-10-27):**
- **31 listings extracted from the Markdown, byte-identical to the sources**; all recompile warning-free under javac, GCC and Clang, and **all self-tests pass**.
- **15 output files identical on rerun; 33 differ only in measured values** (timings, race counts, which threads deadlocked); 0 structural differences.
- Expected compile failures still fail: javac 3 errors, GCC 3, Clang 3.
- **56 relative links and anchors OK.** External URLs: 36 of 41 return 200. The other 5 are ACM DOIs that ACM's bot filter answers with 403; each was confirmed through the doi.org handle API and its title checked against Crossref.
- The gate's rerun found one real nondeterminism bug: `Map.copyOf` iteration order in Listing 2.4. It was fixed, and the lesson is now part of file 02.

**Folders 02–08 gate (2026-10-28):**
- **54 listings extracted from the Markdown; 54 of 54 byte-identical to the sources.** Nineteen sources first differed only in line endings: patch scripts had used Python's `write_text()`, which writes CRLF on Windows. They were normalized to LF. No content differed.
- **All 81 recompile-and-run steps passed** (27 javac, 27 GCC, 27 Clang), warning-free under `-Werror`, and **every self-test passes**.
- **Outputs on rerun:**
  - 4 identical (the deterministic elevator simulation in all three builds, and one pool run);
  - 73 differ only in measured values;
  - 4 differ only in the **sign** of a racy measured value: a naive design's final balance of −6,523.47 on one run and +22,393.99 on the next. The masker hides digits, not signs.
  - **0 structural differences.**
- **Every naive-failure demonstration reproduced on the rerun** (lost creates, double-scheduled joins, double moves, overpayments, deadlock waits, starved writers, overlapping bookings, lost money), **with one exception.** GCC's naive striped adder happened to oversell 0. P15 and this README were corrected from "oversold in every run" to "5 of 6 runs": a passing race test proves nothing.
- **132 relative links and anchors OK.** External URLs: 104 of 111 returned 200 at first. One broken Jakarta javadoc link was fixed (now 200). The other 6 are ACM/VLDB DOIs that the publishers' bot filters answer with 403; each was confirmed through the doi.org handle API and its title checked against Crossref.

## Where this KB refines the brief

1. **Folder names follow the repository blueprint tree.** The role text abbreviates Folders 01 and 08 differently; the tree's names are used.
2. **Files are written straight to disk**, so there are no `### FILE:` headers in chat. The folder *is* the repository.
3. **"Java 21/25":** listings compile with `--release 21` so they run on either LTS. Java 22–25 features are isolated in Listing 2.5, and preview features are marked as preview.
   - **`StructuredTaskScope`** is still a preview API in Java 25 (JEP 505), so P20 and 07.3 use executors plus explicit cancellation, and explain what the scope would add.
   - **`ScopedValue`** (JEP 506) is discussed for MDC propagation in P17.
4. **Guava `Striped`** is re-implemented in a few lines (no third-party dependency) with Guava's documented `bulkGet` contract: sorted, de-duplicated stripes.
5. **Read-write locks are not a default for read-heavy data.** `ReentrantReadWriteLock` measured *slower* than `synchronized` for short critical sections (01.3), and optimistic reads beat every RW lock by two orders of magnitude (07.1).
6. **The blueprint's `ArrayDeque` order queue** can't cancel in O(1) (`remove(Object)` is linear: 164–403 ms vs 0.27 ms). P12 uses an intrusive FIFO plus an id index.
7. **The single-writer order book was *not* faster** than a lock in this measurement. P12 says so, and explains what the design buys: determinism, cache residency, no convoys, free journaling.
8. **`LongAdder` is rejected for inventory** (P15). It has no conditional decrement and oversold in 5 of 6 runs; the one clean run shows why a passing race test proves nothing. Striping uses CAS-guarded buckets with a collapse slow path.
9. **Strict writer preference on AQS loses wake-ups** (07.1). The custom synchronizer uses the JDK's rule: readers queue behind a *first-queued* writer.
10. **`std::atomic<std::shared_ptr>`** isn't lock-free in libstdc++ and is absent from libc++ 21. C++ listings use a feature-tested fallback or a mutex.
11. **Fair locks** measured ~160× slower than barging locks; the rubric treats an unmeasured `new ReentrantLock(true)` as a red flag.
12. **Bugs found while building the listings are kept and documented** where they teach something:
    - GCC turning a runtime `memory_order` into `seq_cst`; ADL selecting `std::apply` and `std::format`;
    - TimSort throwing on live mutable sort keys (P9);
    - MinGW's lazily initialised `std::shared_mutex` hanging under concurrent first use (P10);
    - a boxed `Long !=` identity comparison (P13) and a chrono `.count()` unit bug (P13);
    - a `const std::string&` parameter allocating before the level check on libstdc++ (P17);
    - a cancel-propagation hang (P20);
    - fixed-backoff livelock and an H2O tail deadlock found with a thread dump (07.2);
    - mutex barging hiding a double-submit race (P19).

## Related KBs in this workspace

- [Java Backend Master Reference](../Java-Backend-Master-Reference/): JVM, Loom and the JDK concurrency libraries in depth.
- [Distributed Systems Design L7 Reference](../Distributed-Systems-Design-L7-Reference/): where these in-process designs go when they become distributed (fencing, idempotency, consensus).
- [CP Codeforces Master Kit](../CP-Codeforces-Master-Kit/): the algorithms behind P10 (interval trees), P11 (min cash flow), P12 (ordered maps).
