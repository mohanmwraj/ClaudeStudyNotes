# Modern C++ (C++11 → C++26), Itanium ABI, STL Internals & Concurrency: L7 Reference

A 12-folder knowledge base and interview playbook at the Principal/Staff (L6/L7) bar. It covers the object model and
ABI, the standards' evolution, STL internals, templates and compile-time programming, the memory model and hardware
coherency, OS synchronization, lock-free structures and safe memory reclamation, coroutines and `std::execution`,
interview problem banks, and debugging and source reading. **All 12 folders are complete (2026-10-28).** Every
folder's code was compiled, run and gated before the folder counted as done.

**At a glance:** 44 files · ~234k words · 160 compiled listings · 341 bar-raiser chains + 60 Q&A · every listing
re-extracted from the markdown and rebuilt (467 compile/run/disassemble steps, 494 outputs compared).

## Status

| # | Folder | Files | Listings | Words | Gate |
|---|---|---|---|---|---|
| 01 | [ABI, object model, lifetimes, value categories](01-ABI-Object-Model-Lifetimes-and-Value-Categories/) | 4 | 31 | ~34.5k | ✅ passed (114 steps, 103 outputs) |
| 02 | [Chronological C++ standards evolution, C++11 → C++26](02-Chronological-C++-Standards-Evolution-C++11-to-C++26/) | 4 | 21 | ~21.7k | ✅ passed (77 steps, 82 outputs) |
| 03 | [STL containers: internals, memory layouts, trade-offs](03-STL-Containers-Internals-Memory-Layouts-and-Tradeoffs/) | 4 | 13 | ~16.7k | ✅ passed (29 steps, 32 outputs) |
| 04 | [STL algorithms, ranges, views, functional internals](04-STL-Algorithms-Ranges-Views-and-Functional-Internals/) | 3 | 8 | ~11.4k | ✅ passed (23 steps, 25 outputs) |
| 05 | [Smart pointers, RAII, memory-management internals](05-Smart-Pointers-RAII-and-Memory-Management-Internals/) | 3 | 8 | ~11.4k | ✅ passed (25 steps, 28 outputs) |
| 06 | [Templates, concepts, compile-time programming, zero-cost polymorphism](06-Templates-Concepts-Compile-Time-Programming-and-Zero-Cost-Polymorphism/) | 4 | 8 | ~13.4k | ✅ passed (27 steps, 27 outputs) |
| 07 | [C++ memory model, atomics, hardware coherency physics](07-C++-Memory-Model-Atomics-and-Hardware-Coherency-Physics/) | 4 | 16 | ~22.7k | ✅ passed (44 steps, 51 outputs) |
| 08 | [OS threads, synchronization primitives, futex internals](08-OS-Threads-Synchronization-Primitives-and-Futex-Internals/) | 4 | 12 | ~17.8k | ✅ passed (30 steps, 44 outputs) |
| 09 | [Lock-free programming, data structures, safe memory reclamation](09-Lock-Free-Programming-Data-Structures-and-Safe-Memory-Reclamation/) | 4 | 10 | ~21.0k | ✅ passed (24 steps, 24 outputs) |
| 10 | [Async execution: thread pools, coroutines, C++26 senders](10-Async-Execution-Thread-Pools-Coroutines-and-C++26-Senders/) | 4 | 9 | ~17.7k | ✅ passed (23 steps, 25 outputs) |
| 11 | [Master concurrency + STL interview problem bank](11-Master-C++-Concurrency-and-STL-Interview-Problem-Bank/) | 4 | 19 + 60 Q&A | ~29.3k | ✅ passed (38 steps, 38 outputs) |
| 12 | [Curated libraries, TSan debugging, study guide](12-Curated-Open-Source-Libraries-TSan-Debugging-and-Study-Guide/) | 2 | 5 | ~16.3k | ✅ passed (13 steps, 15 outputs) |

## Headline results (all verified here)

| # | What the folder's listings showed |
|---|---|
| 01 | GCC `-O2` deleted the rest of `main` after a wrong-base `void*` cast. Clang's `dynamic_cast` to a `final` class is one vptr compare (4–5 ns vs 17–20 ns). PMF encoding is `{17,0}` on x86-64 vs `{16,1}` on AArch64. The MSVC ABI ignores `[[no_unique_address]]` |
| 02 | GCC 16 ships contracts, reflection, `inplace_vector`, `function_ref` and `import std`. libc++'s `variant` goes valueless where libstdc++'s doesn't. A throw costs ≈ 1.9–3 µs. Neither library ships `hive`, senders, hazard pointers, RCU, `simd` or `linalg` |
| 03 | SSO capacity 15 vs 22 bytes; `set<int>` node 40 vs 32 B. Hash flooding takes a lookup from 3 ns to 38 µs. A Swiss-table sketch is 2–4× faster than `unordered_map`. libc++ hardening traps silently (`ud2`) |
| 04 | libstdc++'s introsort does 25.6M comparisons on sorted input, against libc++'s 2M. A ranges pipeline is 6× slower than a hand loop only on random data. `std::function` is 32 B vs 48 B, with different small-buffer rules |
| 05 | The `unique_ptr` happy path is identical to raw `new`/`delete`. `make_shared` + `weak_ptr` keeps the whole block alive. A contended `shared_ptr` copy costs 41–62 ns. A 1M-node recursive destructor overflows the stack on both compilers |
| 06 | Virtual calls in random order cost 8.3–10.2 ns vs 1.0–1.25 ns for SoA. The magic-static guard is `movzbl`+`testb` on x86 vs `ldarb`+`tbz` on ARM64. A reflection-based JSON serializer builds on GCC 16 only |
| 07 | Both compilers delete `while(!*plain){}`. The SB reordering appears in 0.4–3% of x86 runs. A `seq_cst` store is `xchg` (~4.7 ns vs 0.12–0.26 ns relaxed). libc++ 21's CAS fails on dirty padding. False sharing costs 1.7–2.25 ns vs ~0.5 ns padded |
| 08 | MinGW `thread_local` is emutls (13 ns vs 1 ns). `shared_mutex` is 2–10× slower than `mutex` for short reads. The winpthreads condvar round trip is 22–46 µs vs 0.6–0.9 µs for SRW. GCC/MinGW `call_once` hangs after a throwing callable |
| 09 | Under a stalled reader, hazard pointers free 9999 of 10000 nodes and EBR frees 0. Treiber's stack is 4× slower than a mutex + vector. Read cost: QSBR 0.33–0.46, HP 1.8–2.1, EBR 3.9–19.6 ns. SPSC is bimodal: 47–61 vs 5.4–9.2 ns |
| 10 | `std::async`'s future blocks in its destructor. Work stealing takes 9–23 ns/task vs 169–248 ns for a mutex pool at 4 workers. GCC never applies HALO. Senders make 0 allocations, and a pipeline compiles to `mov $42` |
| 11 | 15 machine-coding problems and 4 build-your-own components pass their invariant checks. TTAS takes 49–60 ns but is unfair; ticket/MCS take ~115–122 ns and are fair. The flat map is 2–2.4× faster than `unordered_map`. `~jthread` in a block requests stop immediately |
| 12 | TSan/ASan/UBSan instrumentation shown as object code. TSan's fence handler is "not implemented" (GCC warns with `-Wtsan`). Check-then-act is found in 0/300 rounds plainly vs about half under delay injection. folly's asymmetric fence takes the reader from 4.7 to 0.2–0.3 ns, with the heavy side ~2 µs: a break-even of ~500 |

## File index

**01 · ABI, object model, lifetimes, value categories**
- [01 Itanium C++ ABI: vptr, vtable groups, multiple & virtual inheritance, thunks](01-ABI-Object-Model-Lifetimes-and-Value-Categories/01-itanium-abi-vtable-vptr-multiple-virtual-inheritance-and-thunks.md)
- [02 Value categories, RVO/NRVO, implicit move, the call ABI, and `noexcept` moves](01-ABI-Object-Model-Lifetimes-and-Value-Categories/02-value-categories-lvalue-prvalue-xvalue-rvo-nrvo-and-move-noexcept.md)
- [03 Object lifetime, placement new, `std::launder`, `std::bit_cast`, and strict aliasing](01-ABI-Object-Model-Lifetimes-and-Value-Categories/03-object-lifetime-placement-new-std-launder-bit-cast-and-strict-aliasing.md)
- [04 Empty base optimization, `[[no_unique_address]]`, tail padding, and trivial relocation](01-ABI-Object-Model-Lifetimes-and-Value-Categories/04-empty-base-optimization-no-unique-address-and-trivially-relocatable.md)

**02 · Standards evolution, C++11 → C++26**
- [01 C++11 and C++14: the foundation](02-Chronological-C++-Standards-Evolution-C++11-to-C++26/01-cpp11-and-cpp14-foundation-move-raii-lambdas-variadics-and-constexpr.md)
- [02 C++17: the structural leap](02-Chronological-C++-Standards-Evolution-C++11-to-C++26/02-cpp17-structural-leap-pmr-string-view-optional-variant-and-if-constexpr.md)
- [03 C++20: the paradigm shift](02-Chronological-C++-Standards-Evolution-C++11-to-C++26/03-cpp20-paradigm-shift-concepts-ranges-coroutines-modules-and-spaceship.md)
- [04 C++23 and C++26: deducing `this`, `mdspan`, `expected`, reflection, contracts, `std::execution`](02-Chronological-C++-Standards-Evolution-C++11-to-C++26/04-cpp23-and-cpp26-deducing-this-mdspan-expected-reflection-and-execution.md)

**03 · STL containers**
- [01 Sequence containers: `vector` growth, SSO `string`, `deque`'s block map, `inplace_vector`](03-STL-Containers-Internals-Memory-Layouts-and-Tradeoffs/01-sequence-containers-vector-sso-string-deque-chunk-map-and-inplace-vector.md)
- [02 Associative trees: red-black trees, node overhead, hints, transparent comparators](03-STL-Containers-Internals-Memory-Layouts-and-Tradeoffs/02-associative-trees-map-set-rb-tree-node-overhead-and-transparent-comparators.md)
- [03 Hash tables: chaining vs Swiss tables, hash flooding, `flat_map`](03-STL-Containers-Internals-Memory-Layouts-and-Tradeoffs/03-hash-tables-unordered-map-bucket-chaining-vs-swiss-tables-and-flat-map.md)
- [04 Iterator invalidation, PMR pool allocators, and `std::hive`](03-STL-Containers-Internals-Memory-Layouts-and-Tradeoffs/04-iterator-invalidation-rules-custom-pmr-allocators-and-std-hive.md)

**04 · Algorithms, ranges, functional**
- [01 Sorting and selection: introsort vs pdqsort, `stable_sort`, `nth_element`, erase-remove](04-STL-Algorithms-Ranges-Views-and-Functional-Internals/01-introsort-pdqsort-timsort-nth-element-and-erase-remove-idiom.md)
- [02 C++20/23 ranges: lazy views, sentinels, borrowed ranges, `dangling`, codegen](04-STL-Algorithms-Ranges-Views-and-Functional-Internals/02-cpp20-cpp23-ranges-lazy-views-sentinel-optimizations-and-dangling-views.md)
- [03 `std::function`, small-buffer type erasure, `function_ref`, `move_only_function`](04-STL-Algorithms-Ranges-Views-and-Functional-Internals/03-std-function-callable-sbo-type-erasure-vs-function-ref-and-move-only-function.md)

**05 · Smart pointers, RAII, memory management**
- [01 `unique_ptr`: custom deleters, EBO, and the zero-overhead claim, in assembly](05-Smart-Pointers-RAII-and-Memory-Management-Internals/01-unique-ptr-custom-deleters-ebo-and-zero-overhead-assembly-proof.md)
- [02 `shared_ptr`: control block, `make_shared`, weak-pointer zombie memory, aliasing, atomics](05-Smart-Pointers-RAII-and-Memory-Management-Internals/02-shared-ptr-control-block-make-shared-weak-ptr-zombie-memory-and-aliasing.md)
- [03 `enable_shared_from_this`, intrusive reference counting, arena ownership](05-Smart-Pointers-RAII-and-Memory-Management-Internals/03-enable-shared-from-this-intrusive-ref-counting-and-pmr-monotonic-arenas.md)

**06 · Templates, concepts, compile-time programming**
- [01 Type deduction, forwarding references, reference collapsing, perfect forwarding](06-Templates-Concepts-Compile-Time-Programming-and-Zero-Cost-Polymorphism/01-type-deduction-forwarding-references-reference-collapsing-and-perfect-forwarding.md)
- [02 SFINAE, `void_t`, tag dispatch vs C++20 concepts, subsumption and `requires`](06-Templates-Concepts-Compile-Time-Programming-and-Zero-Cost-Polymorphism/02-sfinae-void-t-tag-dispatch-vs-cpp20-concepts-subsumption-and-requires-clauses.md)
- [03 Zero-cost polymorphism: CRTP, mixins, deducing `this`, `variant` visitors, type erasure](06-Templates-Concepts-Compile-Time-Programming-and-Zero-Cost-Polymorphism/03-crtp-mixins-cpp23-deducing-this-std-variant-visitor-and-type-erasure.md)
- [04 `constexpr`, `consteval`, `constinit`, pack indexing, C++26 static reflection](06-Templates-Concepts-Compile-Time-Programming-and-Zero-Cost-Polymorphism/04-constexpr-consteval-constinit-pack-indexing-and-cpp26-static-reflection.md)

**07 · Memory model, atomics, hardware coherency**
- [01 Happens-before, synchronizes-with, modification orders, data-race UB](07-C++-Memory-Model-Atomics-and-Hardware-Coherency-Physics/01-happens-before-synchronizes-with-modification-orders-and-data-race-ub.md)
- [02 The six memory orders, litmus tests, x86-64 vs ARM64 assembly](07-C++-Memory-Model-Atomics-and-Hardware-Coherency-Physics/02-the-6-memory-orders-relaxed-acq-rel-seq-cst-litmus-tests-and-x86-vs-arm64-asm.md)
- [03 `std::atomic` internals: CAS strong vs weak, 16-byte atomics, `atomic_ref`, `atomic<shared_ptr>`](07-C++-Memory-Model-Atomics-and-Hardware-Coherency-Physics/03-std-atomic-internals-cas-strong-vs-weak-atomic-ref-and-atomic-shared-ptr.md)
- [04 `atomic_thread_fence`, compiler barriers, false sharing, cache-line bouncing](07-C++-Memory-Model-Atomics-and-Hardware-Coherency-Physics/04-atomic-thread-fence-compiler-barriers-false-sharing-and-cache-line-bouncing.md)

**08 · OS threads, synchronization, futexes**
- [01 `thread` vs `jthread`, `stop_token`/`stop_callback`, `thread_local`](08-OS-Threads-Synchronization-Primitives-and-Futex-Internals/01-thread-vs-jthread-cooperative-stop-token-stop-callback-and-thread-local-tls.md)
- [02 `mutex`, `shared_mutex`, `scoped_lock`, deadlock avoidance, Linux futex internals](08-OS-Threads-Synchronization-Primitives-and-Futex-Internals/02-mutex-shared-mutex-scoped-lock-deadlock-avoidance-and-linux-futex-internals.md)
- [03 `condition_variable`: spurious and lost wakeups, notify placement, `atomic::wait`](08-OS-Threads-Synchronization-Primitives-and-Futex-Internals/03-condition-variable-spurious-wakeups-lost-wakeups-and-atomic-wait-notify.md)
- [04 `latch`, `barrier`, `counting_semaphore`, `call_once` and magic statics](08-OS-Threads-Synchronization-Primitives-and-Futex-Internals/04-cpp20-latches-barriers-counting-semaphore-and-call-once-static-init-magic.md)

**09 · Lock-free programming and memory reclamation**
- [01 Lock-free vs wait-free vs obstruction-free, and the ABA problem](09-Lock-Free-Programming-Data-Structures-and-Safe-Memory-Reclamation/01-lock-free-vs-wait-free-obstruction-free-and-solving-the-aba-problem.md)
- [02 Lock-free SPSC and Vyukov MPMC ring buffers with cached indices](09-Lock-Free-Programming-Data-Structures-and-Safe-Memory-Reclamation/02-lock-free-spsc-and-vyukov-mpmc-bounded-ring-buffers-with-cached-indices.md)
- [03 Treiber stack, Michael-Scott queue, lock-free hash tables](09-Lock-Free-Programming-Data-Structures-and-Safe-Memory-Reclamation/03-treiber-lock-free-stack-michael-scott-queue-and-lock-free-hash-tables.md)
- [04 Safe memory reclamation: EBR, C++26 hazard pointers, RCU](09-Lock-Free-Programming-Data-Structures-and-Safe-Memory-Reclamation/04-safe-memory-reclamation-epoch-based-reclamation-cpp26-hazard-pointers-and-rcu.md)

**10 · Async execution**
- [01 `future`, `promise`, `packaged_task`, `std::async` pitfalls, `shared_future`](10-Async-Execution-Thread-Pools-Coroutines-and-C++26-Senders/01-futures-promises-packaged-task-async-pitfalls-and-shared-future.md)
- [02 Work-stealing pools, the Chase-Lev deque, task graphs](10-Async-Execution-Thread-Pools-Coroutines-and-C++26-Senders/02-work-stealing-thread-pool-architecture-chase-lev-deque-and-task-graphs.md)
- [03 C++20 coroutines: symmetric transfer, awaitables, async generators](10-Async-Execution-Thread-Pools-Coroutines-and-C++26-Senders/03-cpp20-coroutines-in-depth-symmetric-transfer-awaitables-and-async-generators.md)
- [04 C++26 `std::execution` (P2300): senders, receivers, schedulers, structured concurrency](10-Async-Execution-Thread-Pools-Coroutines-and-C++26-Senders/04-cpp26-std-execution-p2300-senders-receivers-schedulers-and-structured-concurrency.md)

**11 · Interview problem bank**
- [01 15 classic concurrency machine-coding problems, production C++23](11-Master-C++-Concurrency-and-STL-Interview-Problem-Bank/01-15-classic-concurrency-machine-coding-problems-with-production-cpp23-code.md)
- [02 Build your own STL: `vector`, `shared_ptr`/`weak_ptr`, `function`, flat hash map](11-Master-C++-Concurrency-and-STL-Interview-Problem-Bank/02-build-your-own-stl-vector-shared-ptr-function-and-flat-hash-map.md)
- [03 30 bar-raiser questions: multithreading and the memory model](11-Master-C++-Concurrency-and-STL-Interview-Problem-Bank/03-30-faang-nvidia-hft-multithreading-and-memory-model-bar-raiser-qna.md)
- [04 30 bar-raiser questions: core C++, ABI, STL, templates, lifetimes](11-Master-C++-Concurrency-and-STL-Interview-Problem-Bank/04-30-core-cpp-abi-stl-templates-and-lifetime-bar-raiser-qna.md)

**12 · Debugging, curated sources, study guide**
- [01 Debugging concurrency: ThreadSanitizer, ASan, UBSan, Helgrind and rr](12-Curated-Open-Source-Libraries-TSan-Debugging-and-Study-Guide/01-debugging-concurrency-threadsanitizer-tsan-asan-ubsan-helgrind-and-rr.md)
- [02 Curated source code: Abseil, folly, libunifex, stdexec, and the CppCon reading list](12-Curated-Open-Source-Libraries-TSan-Debugging-and-Study-Guide/02-curated-github-source-code-abseil-folly-libunifex-and-cppcon-reading-list.md)

## How to use it

* **Interview in two weeks:** Folder 11 (the 15 problems out loud, then the 60 Q&A), plus the chains of Folders 07–10.
  Every chain's "Why L5 breaks" step is the part interviewers probe.
* **Twelve-week deep study:** the plan in [Folder 12, file 02, §1.6](12-Curated-Open-Source-Libraries-TSan-Debugging-and-Study-Guide/02-curated-github-source-code-abseil-folly-libunifex-and-cppcon-reading-list.md#16-study-plan-twelve-weeks-to-an-l7-bar).
  One folder a week: read the production source, predict the number, then run the listing.
* **Production reference:** §3 (blueprints) and §4 (failure modes) of each file, and the invariants checklists in §6.

## Conventions

* **Spine of every file:** first-principles memory layout / state machine / assembly proof → evolution table
  (C++11 → C++26) → production blueprints (subtle buggy way vs production-hardened way, as compiled listings)
  → failure-mode table → adversarial bar-raiser chains → invariants checklist → references.
* **Bar-raiser chains** follow *Initial prompt → L5 textbook answer → Why L5 breaks → L7 principal defense*. In the
  concurrency folders (07–12) the third step is literally "why L5 deadlocks or corrupts memory on ARM64" wherever that
  is the failure. Elsewhere it is "why it breaks", and the ARM64 angle (PAuth, X8, PMF encoding, alignment faults, weak
  ordering of vptr stores) appears where it is real. Chains are domain-representative composites, **not** claimed to
  be actual questions from any company.
* **Tags:** 🔥 interview-critical · ⚡ performance · 🧊 deep or rare · ⚠ a claim that was *not* executed here
  (read from a spec or source, or inferred from codegen); each ⚠ says which.
* **Listings** start with `// name.cpp - description`. Assembly blocks are filtered godbolt-style: labels,
  instructions and data directives, demangled names as comments, and EH landing pads labelled.
* **Outputs** labelled "verified" are deterministic and reproduced by the gate. Outputs with timings come from one
  captured run; the text gives ranges over repeat runs.

## Toolchains and verification method

| Purpose | Tool |
|---|---|
| Codegen, x86-64 + AArch64 (Itanium ABI) | Clang 21.1.0 (Zig 0.16 bundle), `-O3 -fomit-frame-pointer`, `x86_64-linux-gnu` / `aarch64-linux-gnu` (Armv8.0 baseline; `-mcpu=neoverse_n1` / `neoverse_v1` where LSE, RCpc and LSE2 matter) |
| Codegen cross-check | GCC 16.2.0 MinGW-w64, `-O3 -mabi=sysv` (SysV registers, Itanium C++ ABI), or the native Win64 ABI where `-mabi=sysv` trips over headers |
| Hardened ABIs | Clang `aarch64-unknown-linux-pauthtest`; `-fexperimental-relative-c++-abi-vtables`; `x86_64-pc-windows-msvc` (compile-only `static_assert`s) |
| Sanitizers | instrumentation as object code (Clang, Linux targets); UBSan runs on both compilers (GCC in trap mode) |
| Layout dumps | Clang `-fdump-record-layouts`, `-fdump-vtable-layouts` |
| Runs | Windows 11, Intel i5-11260H (Tiger Lake, 6 cores / 12 threads): GCC 16.2 + libstdc++ 16, Clang 21.1 + libc++ 21.1; `-std=c++23` (or `c++26`) `-O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion` |

**The gate, run for every folder:** each `cpp` block whose first line is `// name.cpp - ` is extracted from the
markdown and must be byte-identical to the source that produced its outputs. The folder's whole build script is then
rerun from the extracted copies, one process at a time, and every output is compared. Deterministic outputs must be
identical. Outputs declared as timed may differ only in their numbers. Structurally, every file needs all seven
sections and at least eight chains, each with all four parts, and every relative link must resolve. External URLs were
checked with HTTP requests; dead ones were replaced by DOIs or plain citations.

**Not possible on this machine** (marked ⚠ in the text): running AArch64 code (no hardware or emulator; AArch64 facts
come from Clang codegen plus the Arm ARM), a Linux-hosted GCC, LTO-dependent devirtualization, the TSan and ASan
runtimes (no runtime for MinGW GCC; TSan unsupported for zig's `windows-gnu` target), Helgrind and rr (Linux only),
and MSVC `cl.exe` itself (MSVC-ABI facts come from Clang targeting `x86_64-pc-windows-msvc`).

## Where this KB refines the brief

1. **Trivial relocatability is not in C++26.** P2786R13 was adopted in February 2025 and removed in November 2025
   (P3920R0). The KB treats it as history plus a C++29 design question (Folder 01, file 04).
2. **"Acquire/release are free on x86" holds for loads and stores only.** RMWs are always `LOCK`ed. A `seq_cst` store
   is `xchg` on both compilers, not `mov` + `mfence`, and a `seq_cst` fence is a locked `or` to the stack (Folder 07).
   On ARM, acquire is `LDAR` on Armv8.0 but `LDAPR` on RCpc cores.
3. **Several "well-known" facts were wrong when checked**, and the text says so where it matters. A `final`-less
   most-derived class still needs a run-time vbase lookup. Two same-type `[[no_unique_address]]` empties don't enlarge
   a struct here. GCC 16's `-Wdangling-reference` is enabled by `-Wextra`, not `-Wall`. `unique_ptr` with a `final`
   deleter is 16 bytes in both libraries.
4. **glibc's condition variable (2.25 and later) does no requeue or "wait morphing"**, contrary to much folklore
   (Folder 08).
5. **Lock-free is not faster by default.** At this core count, Treiber's stack was 4× slower and the Michael-Scott queue
   2× slower than their mutex-based counterparts, while the lock-free hash map was 10–30× faster (Folder 09).
6. **`memory_order_consume`** is implemented as acquire by every compiler. It was discouraged in C++17 and deprecated
   in C++26 (P3475), so the KB teaches dependency ordering as history and hardware fact, not as a tool.
7. **C++26 hazard pointers, RCU, senders, `hive` and `simd` are in the standard but in neither library here**
   (Listing 12.4). The KB builds each core itself (Folders 03, 09, 10) and points to the production implementations:
   folly, liburcu, stdexec/libunifex, plf::hive.
8. **ThreadSanitizer can't see check-then-act on atomics and doesn't model fences** (its runtime's fence handler is
   "not implemented", and GCC warns with `-Wtsan`). Folder 12 shows its instrumentation as object code, and catches
   the race it misses in three other ways.
9. **folly's asymmetric fences are Linux-only.** A Folder 09 sentence implying otherwise was corrected after
   Folder 12 read folly's source and reproduced the technique with `FlushProcessWriteBuffers`.
10. **Standard-library gaps that matter in production:** libc++ 21 lacks `atomic<shared_ptr>`, `generator` and
    `move_only_function`. Its CAS fails on dirty padding (no P0528). GCC/MinGW's `call_once` doesn't reset after a
    throwing callable (PR66146) and hangs the next caller.
