# 17 · FAANG Interview DSA

This folder covers the data structures and algorithms syllabus of FAANG-style coding interviews, organised as **15 pattern files**, a design-problems file, a framework for the interview itself, a **335-problem LeetCode master list** built from five fetched lists (Grind 75/169, Blind 75, NeetCode 150/250, LeetCode Top Interview 150), a CP → interview mapping, and a preparation plan that runs alongside the Codeforces roadmap. Every worked example has a C++ and a Java solution written as LeetCode-style `class Solution` code plus a small stdin driver, and each one is tested.

## How interview DSA differs from competitive programming

| | Codeforces round | Coding interview |
|---|---|---|
| What is graded | the verdict and the time | problem solving, code quality, verification and communication ([file 01](01-interview-framework-and-communication.md)) |
| Time | 2–3 hours for 5–8 problems | 35–45 minutes for 1–2 problems, *including* talking |
| Difficulty | up to 3500 | mostly the CP 800–2000 range: the algorithms are easier |
| Toolbox | anything (segment trees, FFT, flows) | ~15 standard patterns. Exotic structures are rarely expected and must be justified |
| Code | fast to type, macros, globals | readable class code with names, guard clauses, comments on non-obvious lines |
| After the solution | next problem | follow-ups: "what if it streams / doesn't fit in memory / has negatives / must return the path?" |
| Testing | the judge | you, by hand, out loud |

The algorithmic gap is small for someone heading for 2100. The presentation gap is large unless it is trained. That is why this folder pairs every pattern with communication, pitfalls and follow-ups, and why the plan schedules mock interviews.

## First principles of the whole domain

Almost every interview problem is a brute force with one specific waste removed:

- **Re-searching the past** (pairs, complements, counts) → remember it in a hash map; ranges become pairs of prefix sums ([02](02-arrays-hashing-and-prefix-sums.md)).
- **Re-scanning windows** → move two monotone pointers ([03](03-two-pointers-and-sliding-window.md)), or keep only useful candidates on a monotonic stack/deque ([04](04-stacks-and-monotonic-stacks.md)).
- **Scanning a sorted or monotone space** → halve it ([05](05-binary-search.md)), including the space of possible answers.
- **Losing structure** in pointers and recursion → make the invariant explicit ([06](06-linked-lists.md), [07](07-trees-and-bst.md), [08](08-tries.md)).
- **Re-finding the best element** → a heap ([09](09-heaps-and-top-k.md)).
- **Exploring all choices** → backtrack with pruning ([10](10-backtracking.md)), or, when subproblems repeat, DP ([13](13-dynamic-programming-1d.md), [14](14-dynamic-programming-2d.md)), or, when an exchange argument holds, greedy ([15](15-greedy-and-intervals.md)).
- **Hidden graphs** (grids, words, prerequisites) → BFS/DFS/topological sort/union-find ([11](11-graphs.md)) and shortest paths/MST ([12](12-advanced-graphs.md)).
- **Per-operation complexity targets** → compose two structures whose weaknesses cancel ([17](17-design-problems.md)).

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 Interview framework and communication](01-interview-framework-and-communication.md) | all | 🔥 | high | the seven steps, scripts, how interviewers score, a fully worked example |
| [02 Arrays, hashing and prefix sums](02-arrays-hashing-and-prefix-sums.md) | 🟢 | 🔥 | high | hash complements, canonical keys, prefix-sum pair counting |
| [03 Two pointers and sliding window](03-two-pointers-and-sliding-window.md) | 🟢 | 🔥 | high | monotonicity arguments, longest/shortest window templates |
| [04 Stacks and monotonic stacks](04-stacks-and-monotonic-stacks.md) | 🟢–🔵 | 🔥 | high | brackets, calculators, next greater, histogram, window max deque |
| [05 Binary search](05-binary-search.md) | 🟢–🔵 | 🔥 | high | first-true template, rotated arrays, answer search, median partition |
| [06 Linked lists](06-linked-lists.md) | 🟢 | 🔥 | high | reversal, fast/slow with proofs, k-group reversal, Floyd on arrays |
| [07 Trees and BST](07-trees-and-bst.md) | 🟢–🔵 | 🔥 | high | traversals, BST bounds, LCA, path sums, serialisation |
| [08 Tries](08-tries.md) | 🔵 | ⚡ | medium | prefix trees, wildcard search, Word Search II, binary trie |
| [09 Heaps and top-k](09-heaps-and-top-k.md) | 🔵 | 🔥 | high | top-k, k-way merge, two heaps, quickselect |
| [10 Backtracking](10-backtracking.md) | 🟢–🔵 | 🔥 | high | subsets, permutations, combinations, N-Queens, word search |
| [11 Graphs](11-graphs.md) | 🟢–🔵 | 🔥 | high | BFS/DFS, multi-source BFS, topological sort, union-find, cloning |
| [12 Advanced graphs](12-advanced-graphs.md) | 🔵–🟣 | 🔥 | medium | Dijkstra, Bellman–Ford with k stops, MST, Alien Dictionary, Word Ladder |
| [13 Dynamic programming (1D)](13-dynamic-programming-1d.md) | 🟢–🔵 | 🔥 | high | state design, House Robber, Coin Change, Word Break, LIS |
| [14 Dynamic programming (2D)](14-dynamic-programming-2d.md) | 🔵–🟣 | 🔥 | high | grids, LCS, edit distance, knapsack, interval DP, state machines |
| [15 Greedy and intervals](15-greedy-and-intervals.md) | 🟢–🔵 | 🔥 | high | exchange arguments, merge / select / sweep, jump games, gas station |
| [16 Math, geometry and bit manipulation](16-math-geometry-and-bit-manipulation.md) | 🟢 | ⚡ | medium | XOR and carry tricks, overflow, fast power, matrix rotation and spiral |
| [17 Design problems](17-design-problems.md) | 🔵 | 🔥 | high | Min Stack, LRU, LFU, randomized set, time map, iterators, hit counter, Twitter, codec |
| [18 LeetCode master list](18-leetcode-master-list.md) | — | 🔥 | high | 335 problems with list badges, sources, coverage, Grind 75 weekly schedule |
| [19 CP → interview mapping](19-cp-to-interview-mapping.md) | — | ⚡ | high | what transfers from each CP folder, habits to drop |
| [20 FAANG preparation plan](20-faang-preparation-plan.md) | — | 🔥 | high | Nov 2026 → Dec 2027 plan, 8–12 week sprint, mocks, spaced review |

## Pattern map

| File | Pattern | Key problems | CP counterpart |
|---|---|---|---|
| [02](02-arrays-hashing-and-prefix-sums.md) | hashing, prefix sums | [LC 1 · Two Sum](https://leetcode.com/problems/two-sum/) — Easy, [LC 560 · Subarray Sum Equals K](https://leetcode.com/problems/subarray-sum-equals-k/) — Medium | [02 Core techniques](../02-Core-Techniques/README.md) |
| [03](03-two-pointers-and-sliding-window.md) | two pointers, windows | [LC 15 · 3Sum](https://leetcode.com/problems/3sum/) — Medium, [LC 76 · Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/) — Hard | [02 Core techniques](../02-Core-Techniques/README.md) |
| [04](04-stacks-and-monotonic-stacks.md) | stacks, monotonic stack/deque | [LC 739 · Daily Temperatures](https://leetcode.com/problems/daily-temperatures/) — Medium, [LC 84 · Largest Rectangle in Histogram](https://leetcode.com/problems/largest-rectangle-in-histogram/) — Hard | [02 Core techniques](../02-Core-Techniques/README.md) |
| [05](05-binary-search.md) | binary search | [LC 33 · Search in Rotated Sorted Array](https://leetcode.com/problems/search-in-rotated-sorted-array/) — Medium, [LC 875 · Koko Eating Bananas](https://leetcode.com/problems/koko-eating-bananas/) — Medium | [02 Core techniques](../02-Core-Techniques/README.md) |
| [06](06-linked-lists.md) | linked lists | [LC 206 · Reverse Linked List](https://leetcode.com/problems/reverse-linked-list/) — Easy, [LC 143 · Reorder List](https://leetcode.com/problems/reorder-list/) — Medium | [09 Graphs](../09-Graphs/README.md) (functional graphs) |
| [07](07-trees-and-bst.md) | trees, BST | [LC 98 · Validate Binary Search Tree](https://leetcode.com/problems/validate-binary-search-tree/) — Medium, [LC 124 · Binary Tree Maximum Path Sum](https://leetcode.com/problems/binary-tree-maximum-path-sum/) — Hard | [10 Trees](../10-Trees/README.md) |
| [08](08-tries.md) | tries | [LC 208 · Implement Trie (Prefix Tree)](https://leetcode.com/problems/implement-trie-prefix-tree/) — Medium, [LC 212 · Word Search II](https://leetcode.com/problems/word-search-ii/) — Hard | [11 Strings](../11-Strings/README.md) |
| [09](09-heaps-and-top-k.md) | heaps, top-k | [LC 23 · Merge k Sorted Lists](https://leetcode.com/problems/merge-k-sorted-lists/) — Hard, [LC 295 · Find Median from Data Stream](https://leetcode.com/problems/find-median-from-data-stream/) — Hard | [08 Data structures](../08-Data-Structures/README.md) |
| [10](10-backtracking.md) | backtracking | [LC 78 · Subsets](https://leetcode.com/problems/subsets/) — Medium, [LC 51 · N-Queens](https://leetcode.com/problems/n-queens/) — Hard | [01 Foundations](../01-Foundations/README.md) |
| [11](11-graphs.md) | BFS/DFS, topo sort, DSU | [LC 200 · Number of Islands](https://leetcode.com/problems/number-of-islands/) — Medium, [LC 207 · Course Schedule](https://leetcode.com/problems/course-schedule/) — Medium | [09 Graphs](../09-Graphs/README.md) |
| [12](12-advanced-graphs.md) | shortest paths, MST | [LC 743 · Network Delay Time](https://leetcode.com/problems/network-delay-time/) — Medium, [LC 269 · Alien Dictionary](https://leetcode.com/problems/alien-dictionary/) — Hard 🔒 | [09 Graphs](../09-Graphs/README.md) |
| [13](13-dynamic-programming-1d.md) | 1D DP | [LC 322 · Coin Change](https://leetcode.com/problems/coin-change/) — Medium, [LC 300 · Longest Increasing Subsequence](https://leetcode.com/problems/longest-increasing-subsequence/) — Medium | [06 Dynamic programming](../06-Dynamic-Programming/README.md) |
| [14](14-dynamic-programming-2d.md) | 2D DP | [LC 72 · Edit Distance](https://leetcode.com/problems/edit-distance/) — Medium, [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard | [06 Dynamic programming](../06-Dynamic-Programming/README.md) |
| [15](15-greedy-and-intervals.md) | greedy, intervals | [LC 56 · Merge Intervals](https://leetcode.com/problems/merge-intervals/) — Medium, [LC 134 · Gas Station](https://leetcode.com/problems/gas-station/) — Medium | [03 Greedy](../03-Greedy-Constructive-Interactive/README.md) |
| [16](16-math-geometry-and-bit-manipulation.md) | math, bits, matrices | [LC 371 · Sum of Two Integers](https://leetcode.com/problems/sum-of-two-integers/) — Medium, [LC 48 · Rotate Image](https://leetcode.com/problems/rotate-image/) — Medium | [01 Foundations](../01-Foundations/README.md), [04 Number theory](../04-Number-Theory/README.md) |
| [17](17-design-problems.md) | data-structure design | [LC 146 · LRU Cache](https://leetcode.com/problems/lru-cache/) — Medium, [LC 460 · LFU Cache](https://leetcode.com/problems/lfu-cache/) — Hard | [08 Data structures](../08-Data-Structures/README.md) |

## Prerequisites and study order

Prerequisites: comfortable C++ or Java with the standard library ([STL and collections](../01-Foundations/02-cpp-stl-and-java-collections.md)), and big-O reasoning ([complexity](../01-Foundations/01-complexity-and-constraint-reading.md)).

Recommended order: **01 → 02 → 03 → 04 → 05 → 06 → 07 → 15 → 09 → 10 → 11 → 13 → 14 → 08 → 12 → 16 → 17**, then 18–20. This follows the Grind 75 schedule (easy array and string patterns first, DP and advanced graphs later) and the CP roadmap order closely enough to run them together. The month-by-month version is in [20](20-faang-preparation-plan.md).

## How to use this folder with the CP roadmap

- During the long plan, each CP month has a matching interview month ([20 §3](20-faang-preparation-plan.md)). Read the interview pattern file *after* the corresponding CP topic, so that the interview file is a fast consolidation rather than new material.
- Use the [master list](18-leetcode-master-list.md) checkboxes as the single progress tracker for interview problems.
- Before mocks and interviews, revise from the [cheat sheet](../99-Cheat-Sheets/17-faang-interview-cheatsheet.md).

## Conventions in this folder

- Every pattern file follows the kit template adapted for interviews: first principles, definitions and complexities, reusable templates, recognition signals, worked examples, pitfalls, **interviewer follow-ups**, a tiered problem list with list badges, the CP counterpart, and a self-check.
- Badges (`G75` `G169` `B75` `NC150` `NC250` `TI150`) come only from the lists fetched on 23 Oct 2026. Sources, legend and caveats are in [18 §1](18-leetcode-master-list.md). 🔒 marks LeetCode Premium problems.
- Worked-example code is the LeetCode-style class (paste it into LeetCode as is) plus a `main` driver that reads a simple stdin format described in each example. Java drivers use a `DataInputStream`-based token reader, a `BufferedReader`, or `System.in.readAllBytes()`; never `Scanner`.
- Difficulty lines give the LeetCode label and a rough Codeforces-rating estimate marked "est.". The estimates are this kit's judgement, not data.
