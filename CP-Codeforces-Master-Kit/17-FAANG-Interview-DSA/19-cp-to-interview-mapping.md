# From Competitive Programming to Interviews: What Transfers and What Doesn't

> **Band:** all · **Priority:** ⚡ · **FAANG:** high · **Prerequisites:** [README](README.md), [interview framework](01-interview-framework-and-communication.md)
> **You can say you know this when:** you can take any solution you would write in a Codeforces round and rewrite it, in the same amount of time, as interview-quality class code, and you can tell from a problem statement whether a CP technique is expected or overkill.

Working toward Codeforces Master builds almost everything an interview needs: pattern recognition, speed, complexity intuition and edge-case paranoia. It also builds habits that interviewers read as red flags: macros, globals, single-letter names and silent typing. This file maps every CP folder of the kit to the interview patterns of this folder, says what transfers, and lists the habits to switch off.

## 1. First principles — why CP skill transfers unevenly

Interview problems are drawn from a much smaller pool of ideas than Codeforces problems. The fetched lists contain 335 distinct problems ([18](18-leetcode-master-list.md)) and are dominated by the techniques of the 🟢/🔵 CP bands. So the **algorithmic** part of an interview is usually easier for a strong competitive programmer than a Div. 2 C. The **evaluation** is different: an interviewer grades reasoning, communication and code quality, not just a verdict ([file 01](01-interview-framework-and-communication.md)). The transfer is therefore strong for "finding the idea", neutral for "implementing it", and negative for "presenting it", unless you train the presentation separately.

A rough calibration, which is this kit's opinion and not measured data: LeetCode Easy problems are mostly at the Codeforces 800–1200 level, Medium mostly 1200–1800, and Hard mostly 1600–2200, with wide variation. A solid Expert (1600–1900) already has the algorithmic range for nearly all of [18](18-leetcode-master-list.md).

## 2. CP folder → interview patterns

| CP folder (kit) | Interview patterns it feeds | Interview relevance | Transfers | Doesn't transfer |
|---|---|---|---|---|
| [00 Roadmap and strategy](../00-Roadmap-and-Strategy/README.md) | [01 framework](01-interview-framework-and-communication.md) | medium | "find the waste" thinking, time management under pressure | contest silence; skipping explanation |
| [01 Foundations](../01-Foundations/README.md) | [02](02-arrays-hashing-and-prefix-sums.md), [10](10-backtracking.md), [16](16-math-geometry-and-bit-manipulation.md) | high | complexity from constraints, STL/collections fluency, sorting with comparators, bit tricks, overflow | fast-I/O boilerplate, `bits/stdc++.h` habits in shared code |
| [02 Core techniques](../02-Core-Techniques/README.md) | [02](02-arrays-hashing-and-prefix-sums.md), [03](03-two-pointers-and-sliding-window.md), [04](04-stacks-and-monotonic-stacks.md), [05](05-binary-search.md), [15](15-greedy-and-intervals.md) | very high | prefix sums, two pointers, windows, monotonic stacks, binary search on the answer, sweep lines | meet in the middle and ternary search are rare |
| [03 Greedy, constructive, interactive](../03-Greedy-Constructive-Interactive/README.md) | [15](15-greedy-and-intervals.md), [09](09-heaps-and-top-k.md) | high | exchange arguments, greedy with heaps and regret | constructive "print any valid answer" problems and interactive judges are rare |
| [04 Number theory](../04-Number-Theory/README.md) | [16](16-math-geometry-and-bit-manipulation.md) | low | gcd, fast power, sieve, modular arithmetic | CRT, discrete log, Möbius, Pollard rho: overkill |
| [05 Combinatorics and probability](../05-Combinatorics-and-Probability/README.md) | [14](14-dynamic-programming-2d.md), [16](16-math-geometry-and-bit-manipulation.md) | low | binomials, counting by contribution, reservoir sampling intuition | Burnside, Pólya, generating-function counting |
| [06 Dynamic programming](../06-Dynamic-Programming/README.md) | [13](13-dynamic-programming-1d.md), [14](14-dynamic-programming-2d.md), [07 (tree DP)](07-trees-and-bst.md) | high (Google especially) | state design, knapsack, LIS/LCS/edit distance, grid, interval and tree DP | digit DP, broken profile DP, probability DP are rare |
| [07 DP optimisations](../07-DP-Optimizations/README.md) | — | very low | the idea that a DP can be accelerated | CHT, divide and conquer opt., Knuth, Aliens, slope trick: overkill |
| [08 Data structures](../08-Data-Structures/README.md) | [09](09-heaps-and-top-k.md), [11 (DSU)](11-graphs.md), [17](17-design-problems.md) | medium | heaps, ordered sets, DSU, "compose two structures" | Fenwick / segment trees are rarely expected (occasionally as a follow-up for range queries); lazy propagation, persistence, treaps, Mo's: overkill |
| [09 Graphs](../09-Graphs/README.md) | [11](11-graphs.md), [12](12-advanced-graphs.md) | high | BFS/DFS, topological sort, Dijkstra, Bellman–Ford, MST, bipartite checks | SCC, 2-SAT, bridges (rare: Critical Connections), Euler paths (rare: Reconstruct Itinerary) |
| [10 Trees](../10-Trees/README.md) | [07](07-trees-and-bst.md) | high | traversals, diameter, LCA, rerooting intuition | binary lifting rarely needed; HLD, centroid, virtual trees: overkill |
| [11 Strings](../11-Strings/README.md) | [02](02-arrays-hashing-and-prefix-sums.md), [03](03-two-pointers-and-sliding-window.md), [08](08-tries.md) | medium | tries, palindromes by expansion, hashing as a follow-up, KMP for `strStr` | suffix arrays/automata, Aho–Corasick, eertree: overkill (mention at most) |
| [12 Flows and matching](../12-Flows-and-Matching/README.md) | — | very low | modelling instincts | max flow / matching are almost never expected |
| [13 Game theory](../13-Game-Theory/README.md) | [13](13-dynamic-programming-1d.md), [14](14-dynamic-programming-2d.md) | low | minimax DP (Stone Game series) | Sprague–Grundy: overkill |
| [14 Geometry](../14-Geometry/README.md) | [16](16-math-geometry-and-bit-manipulation.md) | low | cross products, integer normalisation of slopes | hulls, half-planes, sweeps: overkill |
| [15 Advanced math](../15-Advanced-Math/README.md) | — | very low | matrix exponentiation as a curiosity (Fibonacci in $O(\log n)$) | FFT, linear algebra: overkill |
| [16 IGM frontier](../16-IGM-Frontier/README.md) | [17](17-design-problems.md) (randomisation) | very low | randomised hashing awareness | everything else |

## 3. Habits to switch off (and what replaces them)

| CP habit | Why it hurts in an interview | Interview replacement |
|---|---|---|
| `#define`, `typedef`, `rep(i,n)` macros | the interviewer must decode them; reads as unprofessional | plain loops and real type names |
| global arrays `int a[N]`, `vector<int> adj[N]` | hidden state, fixed sizes, not reentrant | members or locals sized from the input (`vector<vector<int>> adj(n)`) |
| one-letter names (`a`, `b`, `dp`, `f`) everywhere | the reader cannot follow the invariant | `prefix`, `seen`, `best`, `minPrice`; `dp` is fine only with a stated meaning |
| `#define int long long` | changes the API types silently | `long long` / `long` exactly where overflow is possible, and say why |
| reading stdin in `main` | LeetCode-style interviews give a function signature | implement the method; write a driver only if asked |
| writing without talking | no evidence for problem solving or communication | narrate the plan, the invariant and the test |
| "it passed the samples" | samples are chosen by you in an interview | hand-trace plus edge cases, out loud |
| heavy templates (segment tree for range sums on a static array) | over-engineering; more code, more bugs | the simplest structure that meets the bound (prefix sums) |
| recursion depth ignored ("CF gives 256 MB stack") | interviewers ask about stack limits | mention depth, offer an iterative version |
| `unordered_map` with a custom anti-hash | irrelevant in interviews | default hash map; mention worst-case behaviour if asked |

## 4. Same solution, two styles (C++ and Java)

A CP-style solution of Two Sum, followed by the interview-style version of the same algorithm. Both compile; only the second is what you write in an interview.

CP style (fine for Codeforces, poor for an interview):

```cpp
#define rep(i, a, b) for (int i = (a); i < (b); ++i)
int A[200005];
pair<int, int> solveCP(int n, int T) {
    map<int, int> M;
    rep(i, 0, n) {
        if (M.count(T - A[i])) return {M[T - A[i]], i};
        M[A[i]] = i;
    }
    return {-1, -1};
}
```

```java
static int[] A = new int[200005];
static int[] solveCP(int n, int T) {
    HashMap<Integer, Integer> M = new HashMap<>();
    for (int i = 0; i < n; i++) {
        if (M.containsKey(T - A[i])) return new int[]{M.get(T - A[i]), i};
        M.put(A[i], i);
    }
    return new int[]{-1, -1};
}
```

Interview style (same algorithm, readable, no hidden state):

```cpp
class Solution {
public:
    vector<int> twoSum(const vector<int>& nums, int target) {
        unordered_map<int, int> indexOf;               // value -> index of an earlier occurrence
        for (int i = 0; i < (int)nums.size(); ++i) {
            auto it = indexOf.find(target - nums[i]);
            if (it != indexOf.end()) return {it->second, i};
            indexOf[nums[i]] = i;                      // insert after the lookup: no self-pairing
        }
        return {};                                     // the problem guarantees an answer
    }
};
```

```java
static class Solution {
    public int[] twoSum(int[] nums, int target) {
        Map<Integer, Integer> indexOf = new HashMap<>();
        for (int i = 0; i < nums.length; i++) {
            Integer j = indexOf.get(target - nums[i]);
            if (j != null) return new int[]{j, i};
            indexOf.put(nums[i], i);
        }
        return new int[0];
    }
}
```

## 5. Recognising when CP depth is expected

Most interview problems want the textbook technique. Occasionally a heavier tool is the intended answer, or a good follow-up remark:

| Problem signal | Heavier tool that may be expected | Example |
|---|---|---|
| range-sum queries **with updates** | Fenwick tree or segment tree | [LC 307 · Range Sum Query - Mutable](https://leetcode.com/problems/range-sum-query-mutable/) — Medium |
| "count smaller elements after self", inversions | merge-sort counting or a Fenwick tree over ranks | [LC 315 · Count of Smaller Numbers After Self](https://leetcode.com/problems/count-of-smaller-numbers-after-self/) — Hard |
| skyline / union of intervals with heights | sweep + ordered multiset | [LC 218 · The Skyline Problem](https://leetcode.com/problems/the-skyline-problem/) — Hard |
| "critical connections" | bridges (Tarjan low-link) | [LC 1192 · Critical Connections in a Network](https://leetcode.com/problems/critical-connections-in-a-network/) — Hard |
| "use every ticket exactly once" | Euler path (Hierholzer) | [LC 332 · Reconstruct Itinerary](https://leetcode.com/problems/reconstruct-itinerary/) — Hard |
| repeated substring questions | rolling hash / KMP | [LC 1044 · Longest Duplicate Substring](https://leetcode.com/problems/longest-duplicate-substring/) — Hard |

If you reach for a CP-only structure, say why the simpler options fail first. Interviewers reward the reasoning, and some are not familiar with the structure.

## 6. Pitfalls and things to remember

1. **Speed is not the main criterion.** Finishing in 10 minutes and silently is worse than finishing in 25 with a clear explanation.
2. **Don't skip the brute force** because "it's obvious". In an interview it is part of the evidence ([file 01](01-interview-framework-and-communication.md)).
3. **Know your language's standard library API by heart** (comparators, heaps, `TreeMap`, `Deque`, `StringBuilder`). In CP you may rely on a prepared template; in an interview editor you may not have it.
4. **Switch to 0-based thinking** if your CP habit is 1-based arrays: LeetCode signatures are 0-based.
5. **Online assessments are the exception:** timed, auto-graded rounds reward CP speed directly, so your CP training pays off there without any change of style.

## 7. Follow-up: using CP strengths deliberately

| CP strength | How to show it in an interview |
|---|---|
| stress testing | "I'd test this against an $O(n^2)$ brute force on random small arrays" |
| complexity intuition | state constraints-based targets in the first two minutes |
| proof habits | give the exchange argument or invariant in one sentence |
| knowing many techniques | mention a heavier alternative as a follow-up, not as the first solution |
| edge-case paranoia | list edge cases before coding, test them after |

## 8. Practice

Rewrite drill: take five of your accepted Codeforces solutions per month and rewrite each as interview-style class code with a 30-second explanation of its invariant. Then solve the matching interview problems from the pattern files above.

## 9. CP counterpart

This file is itself the bridge. See the CP roadmap in [00-Roadmap-and-Strategy/02-roadmap-nov-2026-to-dec-2027.md](../00-Roadmap-and-Strategy/02-roadmap-nov-2026-to-dec-2027.md) and the combined schedule in [20-faang-preparation-plan.md](20-faang-preparation-plan.md).

## 10. Self-check

1. Which CP folders feed interview questions most, and which are overkill?
2. Name five CP habits that cost points in an interview and their replacements.
3. When is a Fenwick or segment tree a reasonable interview answer?
4. Why can a strong competitive programmer underperform in an interview, and how do you prevent it?

<details><summary>Answers</summary>

1. Most: 01 Foundations, 02 Core techniques, 03 Greedy, 06 DP, 09 Graphs, 10 Trees (and the DSU and heap parts of 08). Overkill: 07 DP optimisations, 12 Flows, 15 Advanced math, 16 IGM frontier, most of 04, 05, 13 and 14.
2. Macros → plain code; globals → members/locals; one-letter names → descriptive names; silent coding → narration; "passed samples" → hand-traced edge cases (also: heavy templates → the simplest structure).
3. When the problem has range queries combined with updates (or order statistics over a changing set), where prefix sums or sorting cannot meet the bound.
4. The evaluation includes communication, verification and code quality, which contests do not grade. Prevent it with the seven-step framework, weekly mock interviews and the rewrite drill.

</details>
