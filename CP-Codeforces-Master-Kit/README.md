# Codeforces Master → IGM Kit · November 2026 – December 2027

A self-contained study kit for reaching **Codeforces Master-level capability (2100+) by December 2027**, with notes deep enough to keep going
toward **International Grandmaster (2600+)**, plus the **complete DSA syllabus for FAANG interviews**. It has one folder per topic, with
first-principles derivations, every formula, graded worked examples with solutions, tricks and pitfalls, practice ladders of real problems, and LeetCode
cross-references. Every implementation is given in **both C++ and Java**. A separate folder holds a cheat sheet for every topic and a master formula sheet.

> **Target facts verified on 23 Oct 2026**:
> - **Titles:** Master is **2100–2299**, a floor set by Codeforces' official May 2018 announcement. IM is 2300–2399, GM 2400–2599, IGM 2600–2999 and LGM 3000+.
> - **Division rules:** Div. 2 and Educational rounds are rated only below 2100, so a Master is measured in Div. 1, Div. 1 + 2 and Global rounds.
> - **Problem ratings:** this kit's analysis of every Codeforces round from 2023-01-01 to 2026-10-23 puts the median Div. 2 **D at 1900** and **E at 2400**, and Div. 1 **B at 1900** and **C at 2300**.
>
> Details, sources and caveats: [00/01 rating tiers](00-Roadmap-and-Strategy/01-rating-tiers-and-what-each-level-solves.md) and
> [00/08 research findings](00-Roadmap-and-Strategy/08-research-findings-and-sources.md).

---

## Start here (in this order)

1. **Read** [00-Roadmap-and-Strategy/README.md](00-Roadmap-and-Strategy/README.md), then [01 · rating tiers](00-Roadmap-and-Strategy/01-rating-tiers-and-what-each-level-solves.md).
   They cover what "Master-level" means in measurable terms, and which topics matter at which rating (20 min).
2. **Place yourself** with the self-placement test in [02 · roadmap §1](00-Roadmap-and-Strategy/02-roadmap-nov-2026-to-dec-2027.md) during week 1.
   It tells you which phase (A–E) to start in.
3. **Set up** C++ and Java with [06 · environment & templates](00-Roadmap-and-Strategy/06-environment-templates-cpp-java.md).
   It has contest templates, debug macros, and stress-test scripts for Git Bash and PowerShell.
4. **Follow the month-by-month plan** in [02 · roadmap §3](00-Roadmap-and-Strategy/02-roadmap-nov-2026-to-dec-2027.md), with its quarterly checkpoints. For each topic file:
   1. Read §1 (first principles) and §2 (formulas).
   2. Type the §3 code yourself.
   3. Attempt each worked example **before** opening its solution.
   4. Work through the §8 ladder.
5. **Revise** with the [cheat sheets](99-Cheat-Sheets/README.md). Read the [master formula sheet](99-Cheat-Sheets/00-master-formula-sheet.md) before every contest.
6. **Interview track:** run [17 · FAANG plan](17-FAANG-Interview-DSA/20-faang-preparation-plan.md) alongside. It is aligned month by month with the CP roadmap, and has an 8–12 week sprint variant.

Learn how to practise from [03 · practice methodology](00-Roadmap-and-Strategy/03-practice-methodology.md) and
[05 · first-principles problem solving](00-Roadmap-and-Strategy/05-first-principles-problem-solving.md) before you need them, not after.

---

## What's inside

| Folder | Band | What you get |
|---|---|---|
| [00 · Roadmap & strategy](00-Roadmap-and-Strategy/README.md) | all | Verified rating tiers; a rating/topic analysis of the Codeforces API; the 14-month roadmap with placement test, phases, weekly templates (10/15/20 h) and checkpoints; practice methodology; contest strategy; a first-principles problem-solving framework; C++/Java environment; resources; research sources |
| [01 · Foundations](01-Foundations/README.md) | 🟢 | Constraint → complexity reading, C++ STL ↔ Java Collections, bit manipulation, recursion/backtracking, sorting & comparators, overflow, precision and fast I/O |
| [02 · Core techniques](02-Core-Techniques/README.md) | 🟢🔵 | Prefix sums & difference arrays, binary search (on answer, Dinkelbach), two pointers & sliding window, monotonic stack/deque, compression & sweep line, ternary search & meet in the middle |
| [03 · Greedy, constructive, interactive](03-Greedy-Constructive-Interactive/README.md) | 🔵🟣 | Exchange arguments, heaps & regret greedy, constructive patterns, invariants/parity/ad hoc, interactive protocol and query budgets |
| [04 · Number theory](04-Number-Theory/README.md) | 🔵→🔴 | gcd & extended Euclid, modular arithmetic & inverses, sieves & factorisation, φ / Fermat / Euler, CRT, primitive roots / discrete log / Miller–Rabin / Pollard rho, Möbius & Dirichlet & floor sums |
| [05 · Combinatorics & probability](05-Combinatorics-and-Probability/README.md) | 🔵→🔴 | Binomials and nCr mod p, stars & bars, inclusion–exclusion, Catalan/Stirling/Bell/partitions, Burnside & Pólya, probability & expectation, the contribution technique |
| [06 · Dynamic programming](06-Dynamic-Programming/README.md) | 🔵→🟠 | State design from first principles, knapsack family, LIS/LCS/edit distance, grid DP, interval DP, bitmask, digit, tree DP & rerooting, DAG DP, expected-value DP, broken profile. Includes the full AtCoder DP contest and CSES DP ladders |
| [07 · DP optimisations](07-DP-Optimizations/README.md) | 🟣→🔴 | Prefix-sum & monotonic-queue, convex hull trick & Li Chao, divide & conquer, Knuth, SOS & subset convolution, Aliens/WQS, slope trick, matrix exponentiation, each with its validity conditions and counterexamples |
| [08 · Data structures](08-Data-Structures/README.md) | 🔵→🔴 | Fenwick, segment tree, lazy propagation, segment-tree descent/merging/beats, sparse table, DSU variants, sqrt & Mo, persistent structures, treaps, ordered sets / PBDS / heaps |
| [09 · Graphs](09-Graphs/README.md) | 🔵→🟠 | BFS/DFS, shortest paths, MST, topological sort, SCC, bridges & articulation points, 2-SAT, Euler paths, bipartite graphs & cycles, functional graphs |
| [10 · Trees](10-Trees/README.md) | 🔵→🔴 | Euler tour & diameter, LCA & binary lifting, small-to-large / DSU on tree, HLD, centroid decomposition, virtual trees |
| [11 · Strings](11-Strings/README.md) | 🔵→🔴 | Hashing, prefix function, Z-function, Manacher, tries & XOR trie, Aho–Corasick, suffix array & LCP, suffix automaton, eertree |
| [12 · Flows & matching](12-Flows-and-Matching/README.md) | 🟠🔴 | Dinic, min cut & modelling, Kuhn / Hopcroft–Karp, min-cost flow, Hungarian, König / Hall / Dilworth |
| [13 · Game theory](13-Game-Theory/README.md) | 🔵→🟠 | Winning/losing states, Nim & Sprague–Grundy, misère / staircase / Hackenbush / Wythoff, minimax & game DP |
| [14 · Geometry](14-Geometry/README.md) | 🔵→🔴 | Vectors & precision, segments & intersections, polygons & Pick, convex hull & rotating calipers, sweeps / closest pair / half-planes, circles |
| [15 · Advanced math](15-Advanced-Math/README.md) | 🟠🔴 | Matrices & linear recurrences, Gaussian elimination & XOR basis, FFT/NTT, polynomials & generating functions, Lagrange & Berlekamp–Massey, matrix-tree theorem & LGV |
| [16 · IGM frontier](16-IGM-Frontier/README.md) | 🔴 | CDQ & parallel binary search, segment tree on time + rollback DSU, link-cut trees, randomised algorithms & hashing, bitsets, advanced sqrt, how grandmasters think. Its README says what to learn before the Master target and what after |
| [17 · FAANG interview DSA](17-FAANG-Interview-DSA/README.md) | interview | Interview framework, 15 pattern files, design problems (LRU, LFU, iterators, rate limiters…), a **335-problem master list** with badges, CP → interview mapping, and a preparation plan |
| [99 · Cheat sheets](99-Cheat-Sheets/README.md) | all | One sheet per folder (formulas, signal → technique, C++ & Java templates, top 10 mistakes, last-minute list), plus the [master formula sheet](99-Cheat-Sheets/00-master-formula-sheet.md) |

The 335-problem list merges five lists, each fetched from its source on 23 Oct 2026: Grind 75/169, Blind 75, NeetCode 150/250 and LeetCode Top Interview 150.

### How every topic file is organised

```text
> Band · Priority · FAANG relevance · Prerequisites · "You can say you know this when…"
1. First principles — why this works     ← the most important section: how to rediscover the idea
2. Formulas, definitions and identities  ← derived or proved, with complexities
3. Implementation (C++ and Java)         ← tested reference code
4. Recognising the pattern               ← "when you see X, think Y"
5. Worked examples (graded ★ rating)     ← thinking process, then solution + C++ + Java in a collapsible block
6. Tricks, pitfalls and things to remember
7. Going further (toward 2400–2600+)
8. Practice ladder                       ← real problems, by rating, with checkboxes
9. LeetCode / FAANG cross-reference
10. Self-check                           ← answers collapsed
```

Each folder also has a `README.md` with a first-principles overview of the domain, a file table and a study order, plus a `problems.md` ladder of 90–190 problems grouped by rating band.

**Tags.**
- **Band:** 🟢 ≤ 1400 · 🔵 1400–1900 · 🟣 1900–2100 · 🟠 2100–2400 · 🔴 2400+ (Codeforces rank colours).
- **Priority for the Dec-2027 target:** 🔥 must-know · ⚡ useful · 🧊 rare / IGM depth.

Solutions sit in `<details>` blocks. In VS Code, open **Markdown: Open Preview** (Ctrl+Shift+V) to get click-to-reveal solutions and rendered
LaTeX formulas; both also render on GitHub. Try each example before you open its solution.

---

## Code: C++ and Java everywhere

- **Two blocks per implementation.** Every implementation and every worked-example solution has a ```` ```cpp ```` block followed by a ```` ```java ```` block doing the same thing.
- **Full programs** read stdin and write stdout:
  - C++20 with fast I/O.
  - Java 21 as `public class Main`, using a `DataInputStream`-based reader and `PrintWriter`. Never `Scanner`.
- **Pitfalls in both languages are spelled out:**
  - Java: `Arrays.sort` on primitives, recursion depth, `HashMap` anti-hash, `StreamTokenizer`'s 53-bit precision limit.
  - C++: overflow, `unordered_map` hacks, MinGW-specific behaviour (Codeforces judges on Windows).
- **Sample tests in the raw files.** Hidden `<!-- test in: … out: … -->` comments under each solution are sample tests. Open the raw Markdown to copy them as inputs.

---

## Problem references are real

Every problem ID, name, Codeforces rating and LeetCode difficulty was taken from, and checked against, official lists downloaded on 23 Oct 2026:

| Source | Data used | Distinct problems linked |
|---|---|---|
| Codeforces | `problemset.problems` API (IDs, names, ratings, tags) | 1,275 |
| LeetCode | full problem list (numbers, slugs, difficulty, paid flag 🔒) | 842 |
| CSES | the 400-problem set (18 sections) | 265 |
| AtCoder | AtCoder Problems dataset (tasks and estimated difficulties) | 197 |

That is about **2,000 practice-ladder entries** across folders 01–16, plus the 335-problem FAANG list.

- **CSES, AtCoder DP and original problems:** ratings are the writers' estimates on the Codeforces scale, marked `≈… (est.)`.
- **Regular AtCoder contests:** difficulties come from the AtCoder Problems model, marked `(AtCoder est.)`.

---

## Quality checks run on this kit (23 Oct 2026)

- **Every code block compiled and ran.** The kit has **2,030 code blocks** (1,015 C++ + 1,015 Java). All but two were compiled with g++ 16.2 (`-std=c++20 -O2`, MinGW-w64, the same family as Codeforces' G++) and Temurin JDK 21.
  - Full programs were run against **2,356 hidden tests**.
  - Final kit-wide run: **2,028 blocks compiled, 1,488 full programs, 4,716 test runs** (each hidden test runs on both the C++ and the Java program), **0 failures**.
  - The 2 skipped blocks are live interactive programs; the simulated-judge version beside each one is tested.
- **Stress tests.** Every non-trivial worked example was also stress-tested against an independent brute force on random small inputs, in both languages.
  - Optimised DPs were compared with the naive DP.
  - Graph and string algorithms were compared with exhaustive or $O(n^2)$ references.
  - Geometry was checked with exact arithmetic.
  - Interactive solutions were run against local judges.
- **Links resolve.** A link checker validated every problem link against the official data, including names, ratings and difficulties, and every relative link between files: 3,390 Codeforces, 2,424 LeetCode, 773 CSES and 377 AtCoder links plus 3,345 relative links, **0 problems**.
- **Structure audit.**
  - All 196 planned files exist.
  - Every topic file has the header and all 10 sections.
  - Every worked example (562 in total) has both C++ and Java code and at least one hidden test.
- **Master formula sheet checked numerically.** Most of its identities were checked with scripts, and the ones that weren't are listed in its §17.
- **Fixed during the final review:**
  - A Java fast-reader end-of-input bug, in 156 places across 37 files.
  - An overstated divisor-count rule of thumb.
  - The heapify bound.
  - The FAANG plan's month table, realigned to the roadmap.
  - A MinGW `cin >> double` speed pitfall, added to Foundations.
- **Not done:**
  - Solutions were **not submitted to the online judges.** Worked examples based on real problems use paraphrased statements, often written from memory, and the kit's own tests. Before submitting, read the official statement for the exact input/output format.
  - Some hints on the hardest ladder entries are from memory, not from editorials.
  - Timings were measured on a shared laptop and are quoted as rough ratios only.
  - Practice "rules" (how hard to practise, how long before reading the editorial) and the roadmap timelines are **opinion and plan, not verified facts**. The files label them that way; [00/08](00-Roadmap-and-Strategy/08-research-findings-and-sources.md) lists what the research did and did not verify.

Topic files are long, typically 800–1,700 lines, because every program appears twice and in full. Use the collapsible blocks, and read one language
at a time if you prefer.

---

## Using this kit on Windows

No WSL is needed. Install a MinGW-w64 g++ and a JDK 21, then follow [00/06](00-Roadmap-and-Strategy/06-environment-templates-cpp-java.md) for compile
commands, debug builds and the stress-test scripts (Git Bash and PowerShell versions).

Good luck. Struggle honestly, upsolve everything, and let the checkpoints, not your mood, tell you how you're doing.
