# 01 · Foundations

The layer every other folder stands on: reading constraints into a complexity budget, choosing containers in C++ and Java, reasoning in
bits, searching exhaustively and pruning, sorting with correct comparators, and keeping integers, floating point and I/O from silently
breaking a correct idea. At Codeforces Master level these are not "beginner topics" — they are the reasons strong solutions still fail
(overflow, TLE from I/O, a `<=` comparator, a missing reset between tests, an anti-hash test).

## The domain from first principles

A solution is an idea plus an implementation that runs within limits. Foundations is everything between the two:

1. **Budget** — a judge executes roughly $10^8$ simple steps per second; constraints are the setter's message about which complexity is
   intended. Amortised and harmonic-sum arguments tell you what a loop *really* costs. → [complexity](01-complexity-and-constraint-reading.md)
2. **Layout** — every container is a memory layout (array, ring buffer, balanced tree, hash table, heap) and its costs follow from it; the Java
   versions add boxing and different defaults. → [STL & Collections](02-cpp-stl-and-java-collections.md)
3. **Representation** — integers are bit vectors; bitwise operators act per bit, so anything built from them can be solved bit by bit, and numeric
   order is decided by the highest bit. → [bit manipulation](03-bit-manipulation.md)
4. **Search** — when the solution space is small enough, enumerate it; when it is not, prune with a proof. A brute force is also the oracle that
   makes stress testing possible. → [recursion & backtracking](04-recursion-brute-force-and-backtracking.md)
5. **Order** — sorting makes order relations into positions; a comparator must be a strict weak ordering; inversions measure disorder.
   → [sorting & comparators](05-sorting-and-comparators.md)
6. **Fidelity** — fixed-width integers wrap, `double` has 53 bits, division truncates toward zero, and I/O can cost more than the algorithm.
   → [overflow, precision & fast I/O](06-integer-overflow-precision-and-fast-io.md)

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 · Complexity & constraint reading](01-complexity-and-constraint-reading.md) | 🟢 (all bands) | 🔥 | high | constraint → complexity table, potential method, harmonic sums, Master theorem, memory budgets, multi-test sums |
| [02 · C++ STL & Java Collections](02-cpp-stl-and-java-collections.md) | 🟢 (all bands) | 🔥 | high | containers side by side, sorted-set vocabulary, anti-hash hashing, algorithms and Java equivalents, invalidation, boxing |
| [03 · Bit manipulation](03-bit-manipulation.md) | 🟢 → 🟣 | 🔥 | medium | two's complement identities, XOR algebra, per-bit counting, submasks in $3^n$, Gray code, top-bit greedy |
| [04 · Recursion, brute force & backtracking](04-recursion-brute-force-and-backtracking.md) | 🟢 → 🔵 | 🔥 | high | search-space sizes, subsets/permutations/combinations, pruning, branch and bound, iterative deepening 🧊, deep recursion in Java |
| [05 · Sorting & comparators](05-sorting-and-comparators.md) | 🟢 → 🔵 | 🔥 | high | $\Omega(n\log n)$ bound, strict weak ordering, stability, counting/radix sort, Java sort hazards, inversion counting |
| [06 · Integer overflow, precision & fast I/O](06-integer-overflow-precision-and-fast-io.md) | 🟢 (all bands) | 🔥 | medium | type ranges, floor/ceil/mod of negatives, exact comparisons, `__int128`/`BigInteger`, fast readers, flushing |
| [problems.md](problems.md) | ≤ 1400 → 2400+ | — | — | ~100 problems by band with skill hints, plus LeetCode basics |

## Prerequisites

[Environment & templates](../00-Roadmap-and-Strategy/06-environment-templates-cpp-java.md) (the templates and `FastReader` used by every
code block here) and the [first-principles framework](../00-Roadmap-and-Strategy/05-first-principles-problem-solving.md). Some
programming experience in C++ or Java; the folder teaches the contest-specific parts of both.

## Recommended study order

1. **01 complexity** first — every other file refers to its budget table.
2. **06 overflow/precision/I/O** next — it prevents the most common wrong answers immediately.
3. **02 containers**, then **05 sorting** — they are used together constantly.
4. **03 bits** and **04 recursion/backtracking** — these feed bitmask DP, meet in the middle and stress testing.
5. Work the **[problems.md](problems.md)** ladder band by band in parallel with [02-Core-Techniques](../02-Core-Techniques/README.md).

If you are already ~1600+, skim §1–2 of each file, do the worked examples without looking at the solutions, read §6 (pitfalls) carefully, and
move on.

## How this domain shows up in rounds

- **Div. 2 A–C** (medians 800/1100/1400 in 2023–2026 rounds, [rating tiers](../00-Roadmap-and-Strategy/01-rating-tiers-and-what-each-level-solves.md)):
  much of the content is directly foundations — implementation, sorting, brute force over a small space, parity and bit observations. In the
  Codeforces tag data, `implementation` marks 43.7% of problems rated 800–1399 and `brute force` about 19%.
- **Div. 2 D – Div. 1 B and above**: rarely *about* foundations, but they fail on them — a constraint misread into the wrong complexity, `int` overflow
  in a counting answer, a hash map hacked during the open-hacking phase, Java `Arrays.sort` on adversarial input, recursion depth on a path-shaped
  tree. `bitmasks` actually *grows* from 3.0% (800–1399) to 11.3% (2400–2599) of problems, and `brute force` stays at 15–21% up to 2999.
- **Interviews**: complexity analysis, containers, bit tricks, backtracking and sorting are core FAANG material
  ([FAANG track](../17-FAANG-Interview-DSA/README.md)).

## Exit test: you are done with Foundations when

1. Given any constraint block, you write the feasible complexity classes in under a minute and can justify an $O(n\log n)$ "loop over
   multiples" and an $O(n)$ two-pointer bound ([01](01-complexity-and-constraint-reading.md) §1).
2. You can implement, from memory and in both languages: a fast reader, an anti-hash hash map, `lowerBound`, `nextPermutation`, merge-sort
   inversion counting, submask enumeration, `floorDiv`/`ceilDiv`/`floorMod`, an exact integer square root.
3. You solve the worked examples of every file without looking at the solutions (the hidden tests in each file let you check yourself).
4. You have solved at least 80% of the ≤ 1400 and 1400–1700 bands of [problems.md](problems.md) without tags.
5. You can list, without notes, the ten mistakes in the [cheat sheet](../99-Cheat-Sheets/01-foundations-cheatsheet.md) §12 and how each one fails
   (WA, TLE, RE or "works locally").

## Where each file is used later

| Foundation | Used heavily in |
|---|---|
| complexity & constraints | every folder; especially [sqrt decomposition](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md), [advanced sqrt](../16-IGM-Frontier/06-advanced-sqrt-techniques.md) |
| containers | [greedy with heaps](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md), [sweep line](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md), [shortest paths](../09-Graphs/02-shortest-paths.md) |
| bits | [bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md), [SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md), [XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md), [binary trie](../11-Strings/05-trie-and-binary-trie.md) |
| recursion & backtracking | [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md), [meet in the middle](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md), [game DP](../13-Game-Theory/04-minimax-and-game-dp.md) |
| sorting & comparators | [greedy & exchange arguments](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md), [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md), [suffix array](../11-Strings/07-suffix-array-and-lcp.md) |
| overflow & precision | [modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md), [geometry](../14-Geometry/01-vectors-dot-cross-and-precision.md), [hashing](../11-Strings/01-string-hashing.md) |

## Practice and revision

- Consolidated ladder: **[problems.md](problems.md)** (CSES Introductory and Sorting and Searching; Codeforces implementation, greedy,
  sortings, bitmasks, brute force; LeetCode basics).
- Revision: **[foundations cheat sheet](../99-Cheat-Sheets/01-foundations-cheatsheet.md)** — limits, identities, templates in both languages,
  top-10 mistakes and a last-minute pre-contest list.
