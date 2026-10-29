# L7 Coding Bar-Raiser: From Competitive Programming to Production

A permanent reference playbook for Staff/Principal (L6/L7) coding rounds, written for engineers with competitive-programming instincts. It shows the exact structural invariant behind each pattern, rewrites contest code into production Java 21 and C++23 side by side, and answers the three "last 10 minutes" follow-ups for every pattern:

* **Extension A — Concurrency:** what changes when 64 threads call it.
* **Extension B — Streaming / bounded RAM:** an infinite stream, or a 100 TB file and 1 GB of memory.
* **Extension C — Distribution:** the data and state partitioned across 100 machines.

## Status

| Folder | Topic | Status |
|---|---|---|
| [01-L7-Coding-Rubric-and-Hardware-Complexity-Physics](01-L7-Coding-Rubric-and-Hardware-Complexity-Physics/) | Grading model, hardware cost model, API and verification discipline | **Done** (2026-10-29): 3 files, 20 listings + 2 expected-failure builds, gate passed |
| [02-Sliding-Windows-Monotonic-Structures-and-Greedy-Proofs](02-Sliding-Windows-Monotonic-Structures-and-Greedy-Proofs/) | Two pointers, monotonic stack/deque, exchange arguments, matroids, regret heaps | **Done** (2026-10-29): 3 files, 6 listings + 1 expected-failure build, gate passed |
| [03-Trees-Tries-Segment-Trees-and-Range-Query-Structures](03-Trees-Tries-Segment-Trees-and-Range-Query-Structures/) | LCA, Euler tour, HLD, Fenwick, lazy/sparse segment trees, tries, Aho–Corasick | **Done** (2026-10-29): 3 files, 6 listings, gate passed |
| [04-Graph-Theory-Network-Flows-and-Connectivity-Invariants](04-Graph-Theory-Network-Flows-and-Connectivity-Invariants/) | 0-1 BFS, Dijkstra, Bellman–Ford, Kahn, Tarjan, DSU with rollback, matching, min-cut | **Done** (2026-10-29): 3 files, 6 listings, gate passed |
| [05-Dynamic-Programming-State-Reduction-and-Bitmask-Optimizations](05-Dynamic-Programming-State-Reduction-and-Bitmask-Optimizations/) | State design, interval/tree/digit DP, bitmask/SOS, monotonic-queue and D&C DP | **Done** (2026-10-29): 3 files, 6 listings, gate passed |
| [06-String-Algorithms-Rolling-Hashes-and-Probabilistic-Structures](06-String-Algorithms-Rolling-Hashes-and-Probabilistic-Structures/) | KMP, Z, Manacher, double hashing, Bloom, Count-Min, HyperLogLog, reservoir sampling | **Done** (2026-10-29): 2 files, 4 listings, gate passed |
| [07-External-Memory-Out-of-Core-and-Concurrent-Algorithm-Followups](07-External-Memory-Out-of-Core-and-Concurrent-Algorithm-Followups/) | External merge sort, streaming top-K, sharded BFS, thread-safe DSA, 30 hard problems | **Done** (2026-10-29): 3 files, 6 listings, gate passed |

**All 7 folders are complete (2026-10-29):** 20 files, about 190,000 words, 54 listings (27 Java + 27 C++, every C++ listing built with both GCC and Clang) plus 3 expected-failure builds, and 169 bar-raiser chains. Every folder passed its gate.

### Folder 01 files

| File | Listings | Core claims, measured |
|---|---|---|
| [01 — how bar-raisers grade L5 vs L6 vs L7](01-L7-Coding-Rubric-and-Hardware-Complexity-Physics/01-how-bar-raisers-grade-l5-vs-l6-vs-l7-in-45-minute-coding-rounds.md) | 1.1–1.6 | Contest habits fail 8 concrete cases; tie order differs across standard libraries; `(lo+hi)/2` never terminates; compilers reject the contest code in `static_assert`; 7 concurrency strategies; Space-Saving bounds; TPUT vs naive merge |
| [02 — cache-aware algorithms, branch prediction, hidden constants](01-L7-Coding-Rubric-and-Hardware-Complexity-Physics/02-cache-aware-algorithms-branch-prediction-and-hidden-big-o-constants.md) | 2.1–2.8 | 1.2 ns L1 → 140 ns DRAM per dependent load; MLP worth 10–15×; about 6 ns per mispredict; GCC and Clang make opposite branch/cmov choices; Eytzinger + prefetch 5–10× over `lower_bound`; flat vs node hash maps 3–12× |
| [03 — API hygiene, immutability, custom iterators, test-driven verification](01-L7-Coding-Rubric-and-Hardware-Complexity-Physics/03-api-hygiene-immutability-custom-iterators-and-test-driven-verification.md) | 3.1–3.6 | Representation exposure corrupts later answers; shallow record/struct equality; lazy k-way merge iterator/view; a differential-testing harness that shrinks bugs to `[-1]` and `[[0,0],[0,0]]` |

### Folder 02 files

| File | Listings | Core claims, measured |
|---|---|---|
| [01 — two pointers and non-shrinkable windows](02-Sliding-Windows-Monotonic-Structures-and-Greedy-Proofs/01-two-pointers-and-non-shrinkable-sliding-window-invariants.md) | 2.1–2.2 | Closure under shrinking is the proof; `char` windows get emoji wrong; two pointers on "sum = k" is 16–40% wrong with zeros/negatives (shrunk to `[3,-2]`); O(w) stream ring; shard halo of `w − 1` |
| [02 — monotonic stack and deque](02-Sliding-Windows-Monotonic-Structures-and-Greedy-Proofs/02-monotonic-stack-and-deque-submatrix-histograms-and-window-extrema.md) | 2.3–2.4 | `int` area silently returns 2×10⁹ for 3×10⁹; the asymmetric tie rule (`[1,1]`); `%` made a ring deque lose to boxed `ArrayDeque`; the two-stacks queue handles any monoid and beat the deques 2–5× in C++ |
| [03 — exchange arguments, matroids, regret greedy](02-Sliding-Windows-Monotonic-Structures-and-Greedy-Proofs/03-exchange-arguments-matroids-interval-scheduling-and-regret-greedy-heaps.md) | 2.5–2.6 | Wrong greedies are wrong on 1–8% of inputs, shrunk to 3 intervals; regret heap (LC 630); deadline matroid + DSU; weighted intervals need DP; merging per-shard matroid optima is exact while shipping 10% of the jobs |

### Folder 03 files

| File | Listings | Core claims, measured |
|---|---|---|
| [01 — LCA, Euler tour, HLD](03-Trees-Tries-Segment-Trees-and-Range-Query-Structures/01-binary-lifting-lca-euler-tour-flattening-and-heavy-light-decomposition.md) | 3.1–3.2 | One validated, heavy-first iterative DFS builds every label; 90,000 ops vs parent-walking oracles; 524k-deep chain; LCA ranges 20 ns (Euler + sparse table) to 1.35 µs (level-major lifting) |
| [02 — Fenwick, lazy and sparse segment trees](03-Trees-Tries-Segment-Trees-and-Range-Query-Structures/02-fenwick-bit-and-lazy-segment-trees-with-sparse-dynamic-nodes.md) | 3.3–3.4 | The lengthless-lazy bug (14,775 wrong answers); sparse tree 336k nodes vs 2.1 billion; Fenwick 13–16× faster than a recursive lazy tree; per-thread Fenwicks 6–67× faster than a lock |
| [03 — radix tries, Aho–Corasick, XOR tries](03-Trees-Tries-Segment-Trees-and-Range-Query-Structures/03-compressed-radix-tries-aho-corasick-automata-and-bitwise-xor-tries.md) | 3.5–3.6 | Radix trie 13× fewer nodes; segment-boundary routing; an oracle-caught count bug on edge split; Aho–Corasick streams with one int of state and shards with a halo, both exact |

### Folder 04 files

| File | Listings | Core claims, measured |
|---|---|---|
| [01 — 0-1 BFS, Dijkstra, state spaces, Bellman–Ford](04-Graph-Theory-Network-Flows-and-Connectivity-Invariants/01-01-bfs-multi-source-dijkstra-state-space-graphs-and-bellman-ford.md) | 4.1–4.2 | Visited-on-push Dijkstra wrong on 18% of graphs; LC 787 per-city Dijkstra wrong on 2/3,000; snapshot Bellman–Ford; explicit negative-cycle result; parallel BFS 2.4–3× with CAS claims |
| [02 — Kahn, Tarjan SCC, bridges, articulation](04-Graph-Theory-Network-Flows-and-Connectivity-Invariants/02-topological-sort-kahn-cycle-detection-and-tarjan-scc-bridges-articulation.md) | 4.3–4.4 | Sealed Order/Cycle with a verified witness; iterative Tarjan; parent-vertex skipping wrong on 27% of multigraphs; a DAG executor whose first version double-ran tasks |
| [03 — DSU, rollback, matching, min-cut](04-Graph-Theory-Network-Flows-and-Connectivity-Invariants/03-disjoint-set-union-dsu-with-rollback-bipartite-matching-and-min-cut.md) | 4.5–4.6 | Rollback DSU, parity DSU, Dinic = residual min cut = brute force, matching as unit-capacity flow, lock-free CAS DSU (1.4–4× over sequential; one lock 2–14× slower) |

### Folder 05 files

| File | Listings | Core claims, measured |
|---|---|---|
| [01 — state design, space, reconstruction](05-Dynamic-Programming-State-Reduction-and-Bitmask-Optimizations/01-dp-state-design-space-optimization-and-reconstructing-optimal-paths.md) | 5.1–5.2 | Hirschberg alignments verified by applying them; the forward knapsack loop wrong on 63%; HashMap memo 41–453× slower than arrays; a parallel wavefront that lost to cache-resident rolling rows |
| [02 — interval DP, rerooting, digit DP](05-Dynamic-Programming-State-Reduction-and-Bitmask-Optimizations/02-interval-dp-tree-dp-rerooting-and-digit-dp-blueprints.md) | 5.3–5.4 | Reconstructed parenthesizations re-evaluated (CLRS 15,125); sum of distances and eccentricity for every vertex in O(n); the `started` flag (90/90 vs 18/90); interval DP 2.3–3.8× by length |
| [03 — bitmask, SOS, monotonic-queue, D&C DP](05-Dynamic-Programming-State-Reduction-and-Bitmask-Optimizations/03-bitmask-dp-sos-dp-monotonic-queue-dp-and-divide-and-conquer-dp.md) | 5.5–5.6 | Every optimization's precondition broken on purpose: `sub > 0` loop 3/400, D&C with negative values 193/400; 33–300× speedups |

### Folder 06 files

| File | Listings | Core claims, measured |
|---|---|---|
| [01 — KMP, Z, Manacher, Rabin–Karp](06-String-Algorithms-Rolling-Hashes-and-Probabilistic-Structures/01-kmp-prefix-automaton-z-algorithm-manacher-and-rabin-karp-double-hash.md) | 6.1–6.2 | Thue–Morse breaks 2⁶⁴-overflow hashing for every odd base; mod 2⁶¹−1 with a random base + verification is exact; KMP streams with one int; content-defined chunking keeps 99.6% reuse after a 1-byte insert (fixed chunks 0%) |
| [02 — Bloom, Count-Min, HyperLogLog, reservoir](06-String-Algorithms-Rolling-Hashes-and-Probabilistic-Structures/02-bloom-filters-count-min-sketch-hyperloglog-and-reservoir-sampling.md) | 6.3–6.4 | FPR 0.0101 vs theory 0.0100 (one-hash bug 0.098); CMS one-sided and within ε·N; HLL ±0.5% in 16 KB; merges exact; reservoir off-by-one χ² 1,146 vs 76.6 |

### Folder 07 files

| File | Listings | Core claims, measured |
|---|---|---|
| [01 — external merge sort, streaming top-K, sharded BFS](07-External-Memory-Out-of-Core-and-Concurrent-Algorithm-Followups/01-k-way-external-merge-sort-streaming-top-k-and-sharded-bfs-graph-traversal.md) | 7.1–7.2 | 64 MB sorted on disk with a 4 MB budget: fan-in 4 → 2 passes and 192 MB each way, fan-in 16 → 1 pass and 128 MB, with the same comparison count; output verified by sortedness + count/sum/hash; one-pass top-100; BSP BFS: hash partition cuts 87.5% of edges, row partition 0.34% (256× fewer messages), 2,047 supersteps either way |
| [02 — turning single-threaded DSA into concurrent structures](07-External-Memory-Out-of-Core-and-Concurrent-Algorithm-Followups/02-turning-single-threaded-dsa-into-thread-safe-concurrent-structures.md) | 7.3–7.4 | 64 lock stripes 3.6–4.5× faster than one lock at the same hit rate (capacity 9,984, not 10,000); a scripted ABA succeeds on a plain CAS in both languages and fails with a stamp or tag; 1.6 M ids conserved under stress; SPSC ring 4.8–12× faster than blocking queues |
| [03 — 30 hard problems, production Java 21 and C++23](07-External-Memory-Out-of-Core-and-Concurrent-Algorithm-Followups/03-30-faang-l7-hard-coding-problems-with-production-java21-and-cpp23-code.md) | 7.5–7.6 | 30 problems × 1,000 random trials against independent oracles, output byte-identical in Java, GCC and Clang; a 100,000-node chain without recursion; 8 of 9 planted bugs caught, and the one missed (an unverified hash match) is why verification is argued, not tested; Extensions A/B/C for every problem |

## Conventions

* **Every sample is in Java 21 and C++23.** Java is compiled with `javac --release 21 -Xlint:all -Werror` and run on JDK 25.0.4.1. C++ is compiled with **both** GCC 16.2 (MinGW-w64, libstdc++) and Clang 21.1 (Zig 0.16, libc++) using `-std=c++23 -O2 -Wall -Wextra -Wpedantic -Werror -Wshadow -Wconversion -Wsign-conversion`.
* **Listings are complete programs.** The first line names the file (`// Name.java - ...`, `// name.cpp - ...`). Each one compiles on its own and prints its own evidence.
* **Output labels.** "Output (verified)" blocks are deterministic and re-checked byte-for-byte by the gate. "One measured run" blocks contain timings: the gate checks their shape, not their numbers. Prose quotes the range seen across runs.
* **Expected-failure builds.** Some C++ listings contain a block behind a macro (`-DCONSTEXPR_OVERFLOW`, `-DCOMPARE_SPANS`) that **must not compile**. The diagnostics are spliced in, and the gate checks that the build still fails.
* **Machine.** Every number comes from one laptop: Intel i5-11260H (6C/12T, L1d 48 KiB and L2 1.25 MiB per core, L3 12 MiB), 16 GB RAM, Windows 11. Scale the conclusions, not the nanoseconds.
* **Marks.** ⚠ marks a statement that is plausible but was not verified here (a cause not isolated, or a third-party report). Company-process statements are composites from public sources, never internal documents. No "leaked" questions.
* **Bar-raiser chains** use the format *Initial Prompt / L5 Answer / Why L5 Stalls / L7 Answer*, collapsed in `<details>`.

## How each folder is verified (the gate)

1. Listings are **extracted from the published Markdown** (not from the working sources) and compared byte-for-byte with the sources that produced the spliced outputs.
2. The extracted listings are **recompiled and rerun** with the same flags on both C++ compilers and the JDK, sequentially, one process at a time.
3. Rerun outputs are compared with the spliced outputs: deterministic blocks must be identical; measured blocks must match once every number is masked. Expected-failure builds must still fail.
4. Every relative link and anchor is checked; every external URL is fetched (DOIs of ACM/IEEE papers are cited as text because those sites refuse automated fetches).

**Folder 01 gate (2026-10-29):**

| Check | Result |
|---|---|
| Listings extracted from the published Markdown | 20 (10 Java + 10 C++), **20/20 byte-identical** to the sources that produced the spliced outputs |
| Recompile + rerun from the extracted copies | 10 Java runs + 10 × 2 C++ builds (GCC and Clang): **all compile with `-Werror` and run clean**; 34 output files |
| Expected-failure builds (`cp_traps -DCONSTEXPR_OVERFLOW`, `rep_exposure -DCOMPARE_SPANS`) | Still fail on both compilers; **4/4 diagnostics identical** to the spliced ones |
| Output comparison | **12 byte-identical, 22 differ only in measured numbers, 0 structural differences** |
| Structure (sections, ≥ 8 chains with all four labels, A/B/C, an output block per listing) | 3/3 files pass; 26 chains in total |
| Relative links and anchors | 10/10 OK |
| External URLs | 46/56 return 200. The other 10 (9 LeetCode problem pages, 1 Stack Overflow question) return 403 to any automated client. They are the canonical URLs, and the less common problem numbers (692, 715, 1011) were cross-checked by web search. ACM/IEEE/Elsevier papers are cited by DOI as text |

**Gates for later folders** (same method; external URLs: every non-LeetCode URL returns 200, LeetCode pages return 403 to automated clients):

| Folder | Listings byte-identical | Rerun | Outputs (identical / numbers-only / structural diff) | Structure | Relative links |
|---|---|---|---|---|---|
| 02 | 6/6 | 11 steps OK (incl. 1 expected-failure build × 2 compilers) | 8 / 3 / **0** | 3/3, 24 chains | 11/11 |
| 03 | 6/6 | 9 steps OK | 0 / 9 / **0** | 3/3, 24 chains | 14/14 |
| 04 | 6/6 | 9 steps OK | 0 / 9 / **0** | 3/3, 24 chains | 18/18 |
| 05 | 6/6 | 9 steps OK | 0 / 9 / **0** | 3/3, 24 chains | 22/22 |
| 06 | 4/4 | 6 steps OK | 6 / 0 / **0** | 2/2, 16 chains | 22/22 (INRIA PDF checked with curl: Python's CA bundle lacks its chain) |
| 07 | 6/6 | 9 steps OK | 3 / 6 / **0** | 3/3, 31 chains | 29/29 |

### Facts measured in Folder 01 (reused by later folders)

* GCC and Clang evaluate function arguments in opposite orders: `f(rng(), rng())` built different data from one seed.
* Java `HashMap` scan over about 1 M entries: 13 ms on G1, 22 ms on Parallel GC, 63 ms on Epsilon (no relocation); C++ `unordered_map` 77–81 ms. Copying GCs restore locality.
* Default main-thread stacks: `java.exe` 1 MiB (StackOverflowError at about 15k frames of a simple DFS), MinGW-GCC 2 MiB, Zig/Clang 16 MiB.
* GCC treats signed overflow in `constexpr` as a `-fpermissive` error and keeps evaluating up to its 262,144-iteration loop limit; Clang stops at its step limit.
* Latency ladder on this CPU: L1 about 1.2 ns, L2 3.4–5.3 ns, L3 13+ ns, DRAM 104–140 ns per dependent load; independent loads 10–15× cheaper at DRAM.
* GCC `-O2` does not vectorize a `uint32 → uint64` sum (11 GB/s); Clang `-O2` does (30 GB/s); Java C2 does (about 80 GB/s in cache).
* Mispredict about 6 ns. GCC emits `cmov` for both a ternary and a mask `lower_bound`; Clang 21 turns both into branches; libc++'s `std::lower_bound` is branch-free, libstdc++'s is branchy.
* `System.nanoTime` and `steady_clock` resolve 100 ns on this machine.
* `HashMap<Long,Long>` about 88 B/entry; `unordered_map<u64,u64>` 32 B (libstdc++) / 40 B (libc++) requested per entry.

## Where this KB refines the brief

1. **Folder names follow the repository tree**, not the role paragraph (`01-L7-Coding-Rubric-and-Hardware-Complexity-Physics`, not `...-and-Complexity-Physics`; `07-...-and-Concurrent-Algorithm-Followups`).
2. **"64 threads" is measured with 8**, because this laptop has 12 hardware threads. The text scales the conclusions, not the numbers.
3. **"Bar-raiser" persona content is composite.** Google's public re:Work structured-interviewing guidance and widely reported (⚠, not official) Meta coding areas anchor the rubric. Nothing claims to be a company's internal rubric or question bank.
4. **Measured contradictions of folklore are reported as measured.** Examples: the famous sorted-array branch example does not reproduce in C++; branch-free search loses out of cache; concatenate-and-sort beats a heap merge in RAM; thread-local + merge lost to a shared `ConcurrentHashMap<String, LongAdder>`.
5. **Undefined behaviour is never executed.** C++ versions of racy or overflowing contest code are either evaluated at compile time (`static_assert`, which must diagnose UB) or explicitly marked "not run".
6. **No JMH / Google Benchmark.** Listings stay self-contained, using best-of-N timing with warm-up. The text says where a real harness is required.
7. **"FAANG" in Folder 07 File 3's name is the brief's wording.** The 30 problems are public LeetCode problems; nothing claims that a particular company asks them.
