# Resources and problem sets

> **Band:** all · **Priority:** ⚡ (pick a few and use them deeply; collecting resources is not practice) · **FAANG:** high for §5 · **Prerequisites:** [roadmap](02-roadmap-nov-2026-to-dec-2027.md)
> **You can say you know this when:** for each phase of the roadmap you know which one problem set is your backbone, which reference you read when the kit is not enough, and you are not spending practice time choosing between ten lists.

Facts marked *verified* were checked in the deep-research run of 23 Oct 2026 ([08](08-research-findings-and-sources.md)); the rest is standard
knowledge about widely used resources, not verified in this research.

## 1. CSES Problem Set — the backbone for phases A–C (verified)

[cses.fi/problemset](https://cses.fi/problemset/) — **400 problems in 18 sections** (a verifier script-counted the live page on 23 Oct 2026; the set
grew from an older 300-problem version, so counts may change):

| Section | Problems | Kit folders | Roadmap phase |
|---|---|---|---|
| Introductory | 24 | [01](../01-Foundations/README.md) | A |
| Sorting and Searching | 35 | [01](../01-Foundations/README.md), [02](../02-Core-Techniques/README.md) | A–B |
| Dynamic Programming | 23 | [06](../06-Dynamic-Programming/README.md) | B–C |
| Graph Algorithms | 36 | [09](../09-Graphs/README.md) | B–C |
| Range Queries | 25 | [08](../08-Data-Structures/README.md) | B–C |
| Tree Algorithms | 16 | [10](../10-Trees/README.md) | B–C |
| Mathematics | 37 | [04](../04-Number-Theory/README.md), [05](../05-Combinatorics-and-Probability/README.md), [15](../15-Advanced-Math/README.md) | B–D |
| String Algorithms | 21 | [11](../11-Strings/README.md) | C–D |
| Geometry | 16 | [14](../14-Geometry/README.md) | D |
| Advanced Techniques | 25 | [07](../07-DP-Optimizations/README.md), [16](../16-IGM-Frontier/README.md) | D–E |
| Sliding Window | 11 | [02](../02-Core-Techniques/README.md) | B |
| Interactive | 6 | [03](../03-Greedy-Constructive-Interactive/05-interactive-problems.md) | C |
| Bitwise Operations | 11 | [01](../01-Foundations/03-bit-manipulation.md), [07](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md), [15](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md) | B–D |
| Construction | 8 | [03](../03-Greedy-Constructive-Interactive/03-constructive-algorithms.md) | B–C |
| Advanced Graph | 28 | [09](../09-Graphs/README.md), [12](../12-Flows-and-Matching/README.md) | C–D |
| Counting | 18 | [05](../05-Combinatorics-and-Probability/README.md) | C–D |
| Additional Problems I | 30 | mixed | C–E |
| Additional Problems II | 30 | mixed | D–E |

The 23-problem **DP section works as a graded DP ladder** (verified): from counting and knapsack (Dice Combinations, Coin Combinations I/II, Book
Shop) through sequence DP (Edit Distance, Longest Common Subsequence, Increasing Subsequence, Projects) to bitmask DP (Elevator Rides),
broken-profile DP (Counting Tilings), digit DP (Counting Numbers) and Increasing Subsequence II. (The technique labels are the standard reading of
these problems, not something the page states.)

How to use it: CSES problems are "pure" — the technique is the problem — so they are ideal for **learning** a technique, less good for training
**idea finding** (pair them with untagged Codeforces problems). CSES has no official ratings; the kit marks them `≈ est.` where needed.

## 2. CP-Algorithms — the main written reference (verified, with gaps)

[cp-algorithms.com](https://cp-algorithms.com/) has full articles (proofs, C++ code, practice lists) on most of the 2100–2600+ syllabus. Verified on
23 Oct 2026: heavy-light decomposition, centroid decomposition (new article, March 2026), 2-SAT, Dinic, push-relabel, flows with demands, min-cost
flow, the assignment problem, Kuhn's matching, the Hungarian algorithm, binary-lifting LCA; divide-and-conquer DP and Knuth's optimisation; the
convex hull trick and Li Chao tree (filed under *Geometry*, not DP); inclusion–exclusion, Burnside/Pólya, stars and bars, Catalan numbers, Pick's
theorem, Kirchhoff's theorem, Prüfer codes, Sprague–Grundy/Nim; and the modular binomial toolkit (factorials and inverse factorials, Lucas, prime
powers + CRT).

**Gaps (verified — no dedicated article):** DSU on tree / small-to-large, virtual trees, link-cut trees, general (blossom) matching, SOS DP, the
Aliens/WQS (Lagrangian) trick, slope trick. The kit covers these in
[small to large](../10-Trees/03-small-to-large-and-dsu-on-tree.md), [virtual trees](../10-Trees/06-virtual-trees.md),
[link-cut trees](../16-IGM-Frontier/03-link-cut-trees.md), [SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md),
[Aliens trick](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md) and [slope trick](../07-DP-Optimizations/07-slope-trick.md); for more,
use the USACO Guide (§3) and Codeforces blogs.

## 3. USACO Guide — Platinum and Advanced (verified)

[usaco.guide](https://usaco.guide/) is a community-maintained curriculum with modules and graded problem lists.

- **Platinum** ([usaco.guide/plat](https://usaco.guide/plat)) is the core advanced layer. Its frequency labels (how often a topic appeared in
  **USACO Platinum**, not on Codeforces) rate only two modules "Somewhat Frequent" — *More Applications of Segment Tree* (walking on a segment tree,
  non-commutative combiners) and *Binary Jumping*; Small-to-Large, HLD, Centroid Decomposition and Kruskal Reconstruction Tree are "Rare"; Virtual
  Tree "Has Not Appeared"; Convex Hull, CHT, SOS DP and sweep-line range queries "Not Frequent". Read these as a suggested *order*, not as permission to
  skip HLD or centroid decomposition — the guide teaches every module, and Codeforces frequencies differ
  ([rating tiers §6](01-rating-tiers-and-what-each-level-solves.md) has the Codeforces tag data).
- **Advanced** ([usaco.guide/adv](https://usaco.guide/adv)) — **41 modules, 376 problems in 8 sections** (fetched live on 23 Oct 2026; counts drift):
  Data Structures (46 problems: wavelet tree, segment tree beats, persistent structures, treaps), Convexity (30: LineContainer, Lagrangian
  relaxation, slope trick), Graphs (80: link-cut tree, BCC/2CC, SCC, offline deletion), Dynamic Programming (24: broken profile, more DP
  optimisations), Flows (30), Polynomials (12: FFT and operations built on it), Strings (62: suffix array, suffix structures), Misc. Topics (92: XOR
  basis, matroids, matroid intersection, prefix sums of number-theoretic functions). The page itself says some topics "have not appeared in Platinum
  and probably never will (ex. Matroid Intersection)". It is a sensible outline for the IGM-depth layer ([16](../16-IGM-Frontier/README.md)).

## 4. Standard resources (not verified in this research)

| Resource | What it is | Use it in |
|---|---|---|
| *Competitive Programmer's Handbook* (Antti Laaksonen) | free PDF book; concise chapters that match CSES | phases A–B, alongside CSES |
| *Guide to Competitive Programming* (Laaksonen) | expanded book version of the handbook | optional |
| **Codeforces problemset** with filters | filter by rating range and tags, sort by solves, hide tags in settings | every phase: untagged practice at your level |
| **Codeforces EDU** | interactive courses with step-by-step lessons and practice (e.g. segment tree, binary search, two pointers, DSU, suffix array) | phases B–C for those topics |
| **Codeforces blogs / catalog** | topic tutorials written by strong competitors | when the kit points to a gap or a 🧊 topic |
| **AtCoder Beginner Contest (ABC)** | weekly; clean problems, strong on implementation and classic techniques | weekly second contest until ~1900 |
| **AtCoder Regular Contest (ARC)** | harder, ad-hoc/constructive heavy | from ~1900: trains Div. 1 B–C thinking |
| **AtCoder Grand Contest (AGC)** | very hard ad-hoc problems | phase E, for depth |
| **AtCoder Educational DP Contest** (`atcoder.jp/contests/dp`) | 26 classic DP problems (Frog 1 … Permutation) | phases B–C with [06](../06-Dynamic-Programming/README.md) |
| **AtCoder Library (ACL)** | official C++ library (modint, convolution, max flow, min-cost flow, segtree, lazy segtree, SCC, 2-SAT, string algorithms) | as a reference for clean implementations; pre-published, so allowed under the third-party rule |
| **AtCoder Problems** (kenkoooo) | difficulty estimates and progress tracking for AtCoder | choosing AtCoder problems; the kit's AtCoder `diff≈` values come from it |
| **KACTL** (KTH team notebook) | compact, tested implementations of many algorithms | reference when writing your own library (mind its licence) |
| **clist.by** | contest calendar across platforms, performance statistics | contest planning |

Rule of thumb (opinion): **one backbone set per phase** (CSES in A–C, USACO Guide Platinum/Advanced and Codeforces 2100+ in D–E), the kit file
as the explanation, CP-Algorithms or a blog only when you need a second explanation.

## 5. FAANG lists

- **Grind 75 / Grind 169 (verified).** Created by **Yangshun Tay**, the author of Blind 75 (he describes himself as an ex-Meta Staff Engineer),
  presented as "Blind 75 reimagined for the future" ([techinterviewhandbook.org/grind75/about](https://www.techinterviewhandbook.org/grind75/about)).
  He selected 169 LeetCode questions by popularity, frequency, topic coverage and like-rating, ranked them by value, and made the top 75 the core
  list; you can extend up to all 169 ("Grind 169" is a community name) and, in his words, probably do not need to go beyond 169. "Rating" there means
  LeetCode like-rating, not difficulty. The research did **not** verify the 75/169 problem numbers.
- **Blind 75, NeetCode 150/250, LeetCode Top Interview 150** — widely used; their contents and overlaps were **not verified** in this research.
- The kit's own list is [LeetCode master list](../17-FAANG-Interview-DSA/18-leetcode-master-list.md), and the study plan is
  [FAANG preparation plan](../17-FAANG-Interview-DSA/20-faang-preparation-plan.md).

## 6. Which resource when (summary)

| Phase ([roadmap](02-roadmap-nov-2026-to-dec-2027.md)) | Backbone problems | Explanations | Contests |
|---|---|---|---|
| A — Foundations | CSES Introductory, Sorting and Searching | kit 01–02, Handbook | Div. 2/3/4, ABC |
| B — Expert core | CSES DP, Graph, Range Queries, Tree; AtCoder DP contest | kit 03–06, 08–10; CF EDU courses | Div. 2, Educational, ABC |
| C — CM → Master | CSES Counting, String, Advanced Graph; CF 1900–2200 untagged | kit 05–11; CP-Algorithms | Div. 2, Div. 1 + 2, ARC |
| D — Master consolidation | CF 2100–2400 untagged; USACO Guide Platinum | kit 07, 12–15; CP-Algorithms | Div. 1 (virtual/rated), Div. 1 + 2 |
| E — IGM depth | USACO Guide Advanced; CF 2400+ | kit 16; Codeforces blogs | Div. 1, Global, AGC |

## 7. Self-check

1. How many problems and sections does CSES have, and which section is the graded DP ladder?
2. Name three topics that CP-Algorithms has no dedicated article on.
3. What do the USACO Guide Platinum frequency labels measure, and why should you not use them to skip HLD?
4. Who made Grind 75, and what is the relationship between Grind 75 and Grind 169?

<details><summary>Answers</summary>

1. 400 problems in 18 sections (as of 23 Oct 2026); the 23-problem Dynamic Programming section.
2. Any three of: DSU on tree/small-to-large, virtual trees, link-cut trees, general (blossom) matching, SOS DP, the Aliens/WQS trick, slope trick.
3. How often a topic appeared in USACO Platinum contests — not Codeforces relevance; the guide still teaches every module, and Codeforces rounds at 2100+ do use HLD-type techniques.
4. Yangshun Tay (author of Blind 75); Grind 75 is the top-75 core of a 169-question pool ranked by value.

</details>
