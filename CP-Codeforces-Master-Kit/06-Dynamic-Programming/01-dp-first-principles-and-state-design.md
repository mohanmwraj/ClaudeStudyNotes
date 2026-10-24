# DP First Principles and State Design

> **Band:** 🟢→🟣 1200–2100 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [recursion and backtracking](../01-Foundations/04-recursion-brute-force-and-backtracking.md), [complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md)
> **You can say you know this when:** for an unseen counting or optimisation problem you can (1) write a state and *argue* it holds everything the future needs, (2) give the transition and a valid evaluation order, (3) estimate states × transitions against the limits before coding, and (4) turn the memoised version into a table with a rolling array and a reconstruction without introducing bugs.

Dynamic programming is not a bag of recurrences to memorise. It is one idea — *don't solve the same future twice* — plus a skill: choosing what to remember. Everything in the rest of this folder (knapsack, LIS, interval, bitmask, digit, tree, expected-value DP) is that idea applied to a particular shape of history. This file builds the idea from brute force and then turns it into a checklist you can run in a contest.

---

## 1. First principles — why this works

### 1.1 Start from brute force: a tree of decisions

Almost every DP problem can be phrased as: *make a sequence of decisions $d_1, d_2, \dots, d_n$; each complete sequence is valid or not and has a cost; find the best cost (optimisation), the number of valid sequences (counting), or whether one exists (feasibility).*

The brute force is a search tree. A node is a **history** $h = (d_1,\dots,d_k)$ — the decisions made so far. Children extend the history by one decision. Leaves are complete solutions. The tree has exponentially many nodes, and the brute force visits them all.

Look at what the brute force actually does at a node: it solves the sub-problem "given this history, what is the best way to finish?". The waste is that **very different histories often pose exactly the same sub-problem.**

### 1.2 States are equivalence classes of histories

Call two histories $h$ and $h'$ **equivalent** ($h \sim h'$) when they cannot be told apart by any future:

- for every possible continuation $f$, $h\cdot f$ is valid $\iff$ $h'\cdot f$ is valid, and
- the cost added by $f$ is the same after $h$ as after $h'$.

If $h \sim h'$ then the best completion of $h$ is also the best completion of $h'$, and they have the same number of valid completions. So we need to solve the future **once per equivalence class**, not once per history.

A **state** is a compact label $\sigma(h)$ of the class: a function of the history such that $\sigma(h)=\sigma(h') \Rightarrow h\sim h'$. It may split a class into several states (that only costs time), but it must **never merge two non-equivalent histories** (that gives wrong answers). This is the same idea as the Myhill–Nerode theorem for automata: the "state" of a recogniser is what it remembers about the prefix, and the minimum automaton remembers exactly the equivalence class.

So the design question is always:

> **What do I need to remember about the past to decide the future — and nothing more?**

| Problem | Full history | What the future actually needs | State |
|---|---|---|---|
| Frog jumps over stones, cost $\lvert h_i-h_j\rvert$ | the whole path | where the frog stands | $i$ |
| Vacation: no activity two days in a row | every day's activity | today's index, yesterday's activity | $(i, \text{last})$ |
| 0/1 knapsack | the set of chosen items | next item index, weight used so far | $(i, w)$ |
| Count strings avoiding pattern $P$ | the full prefix | longest suffix of the prefix that is a prefix of $P$ | $(i, \text{KMP state})$ |
| Travelling salesman | the visit order | which cities are visited, where I stand | $(\text{mask}, v)$ |
| Count $x \le N$ with digit sum $\equiv 0 \pmod D$ | the digits chosen | position, "still equal to $N$'s prefix?", sum mod $D$ | $(pos, tight, s)$ |
| Longest increasing subsequence | the chosen indices | the last chosen value | last index $i$ |

Two failure modes, both worth recognising instantly:

- **Merging too much.** "Longest simple path in a general graph with state = current vertex" is wrong: two histories ending at $v$ differ in *which vertices are already used*, and that changes the future. The famous phrase "longest path has no optimal substructure" really means "vertex alone is an incomplete state". Add the visited set (bitmask, $n \le 20$) and the DP is correct again — and exponential, which is the honest price.
- **Remembering too much.** Carrying the whole chosen set when only its sum matters, or the exact sum when only the sum mod $k$ matters, multiplies the state space for nothing. Every time you add a parameter, ask "could two different values of this parameter ever lead to different futures?" If not, drop it.

### 1.3 DP is a best path in a DAG of states

Once the states are fixed, draw a graph: one node per state, an edge $s \to t$ for every decision that moves state $s$ to state $t$, labelled with that decision's cost. A complete solution is a path from the start state to a terminal state, so

- optimisation = shortest/longest path,
- counting = number of paths,
- feasibility = reachability,
- probability = sum over paths of products of edge probabilities.

The graph is **acyclic** whenever decisions make measurable progress — the index grows, the mask gains a bit, the interval shrinks, the subtree is smaller. On a DAG, best paths are computed by processing nodes in topological order in $O(V+E)$. That is the whole algorithm:

$$\text{time} = \Theta(\#\text{states} \times \text{average transitions per state}), \qquad \text{memory} = \Theta(\#\text{states kept at once}).$$

The value of a state satisfies a **Bellman equation** over a *semiring* $(\oplus, \otimes)$:

$$f(s) = \bigoplus_{s \to t} \big( w(s,t) \otimes f(t) \big), \qquad f(\text{terminal}) = \mathbb 1 .$$

The textbook conditions now read naturally:

- **Optimal substructure:** a best path through state $s$ uses a best path from $s$ onward. On a DAG with additive costs this is automatic *if the state is complete* (§1.2). When it seems to fail, the state is missing information.
- **Overlapping subproblems:** many histories share a state, so the DAG has far fewer nodes than the search tree has leaves. The speed-up of DP is exactly $\#\text{histories} / \#\text{states}$.

If the state graph has **cycles** it is not a plain DP: use shortest paths (Dijkstra, Bellman–Ford — see [shortest paths](../09-Graphs/02-shortest-paths.md) and [DP on graphs](09-dp-on-dags-and-graphs.md)) or, for expectations, solve a system of equations ([expected-value DP](10-probability-and-expected-value-dp.md)).

### 1.4 Pull versus push

Two ways to evaluate the same DAG:

- **Pull** (backward-looking): $f(t) = \bigoplus_{s \to t} f(s)\otimes w(s,t)$ — each state gathers from its predecessors.
- **Push** (forward-looking): for each $s$ in topological order, for each successor $t$, do $f(t) \mathrel{\oplus}= f(s)\otimes w(s,t)$.

They do identical work. Use **push** when successors are easy to enumerate and predecessors are not ("from this state I can do X, Y, Z"), which is typical for probability DP and for "generate the next state" problems. Use **pull** when the predecessors form a nice range — then a prefix sum, a monotonic deque or a convex hull can aggregate them in $O(1)$ amortised ([DP optimisations](../07-DP-Optimizations/README.md) all need the pull form).

### 1.5 Memoisation versus tabulation

| | Memoisation (top-down) | Tabulation (bottom-up) |
|---|---|---|
| Order | automatic (recursion = DFS of the DAG) | you must give a topological order |
| States visited | only reachable ones | all of them |
| Overhead | call stack, cache checks | tight loops, vectorisable |
| Memory tricks | hard | rolling arrays easy |
| Risk | stack overflow, slow hashing | wrong order, wrong bounds |

Rules of thumb: prototype with memoisation when the order is unclear or only a sparse part of the state space is reachable (digit DP, game DP on odd states); switch to tables when the state space is dense or you need rolling arrays or optimisations.

**Recursion depth.** A chain of $10^5$–$10^6$ nested calls overflows a default stack. Codeforces gives C++ a 256 MB stack, but your local Windows build defaults to 1 MB (link with `-Wl,--stack,268435456`). Java's main thread stack is small (often 512 KB–1 MB, ~10⁴ frames): either run `solve()` inside `new Thread(null, runnable, "", 1 << 28)` or go iterative. Both are shown in §3.

**Sentinels.** Memo tables need an "unknown" marker distinct from every real value: `-1` works for counts mod $p$; for optimisation values that can be negative, use a separate `visited` array.

### 1.6 Order of evaluation

The single rule: **when you compute a state, every state it reads must already be final.** Typical orders:

| DP shape | Valid order |
|---|---|
| prefix / sequence $f(i)$ from $f(<i)$ | $i$ increasing |
| interval $f(l,r)$ from shorter intervals | length increasing (or $l$ decreasing, $r$ increasing) |
| subsets $f(\text{mask})$ from submasks | mask increasing (a submask is numerically smaller) |
| trees | post-order (children before parent) |
| general DAG | topological sort |

Classic wrong orders: 0/1 knapsack in one array with $w$ increasing (an item gets used twice — [knapsack](02-knapsack-family.md) §1); interval DP looping $l$ increasing with $r$ inner (reads $f(l+1, r)$ before it exists).

### 1.7 Dimension reduction and rolling arrays

If layer $i$ reads only layer $i-1$, keep two rows (`cur`, `nxt`, or index `i & 1`) — or one row if you can choose a direction that never reads an overwritten cell. Memory drops from $O(n\cdot W)$ to $O(W)$, and the smaller working set is often faster too (cache).

Three deeper reductions:

1. **A dimension that is determined by the others.** Two walkers moving right/down in lock-step: after $d$ steps, $r + c = d$, so the state $(r_1,c_1,r_2,c_2)$ shrinks to $(d, r_1, r_2)$ ([grid DP](04-grid-and-path-counting-dp.md)).
2. **Swap value and index.** $dp[i][w]$ = max value with weight $w$ needs $W$ columns; if $W = 10^9$ but values are small, use $dp[i][v]$ = min weight achieving value $v$ ([Knapsack 2](02-knapsack-family.md)). Put the *small-range* quantity in the index and optimise the other.
3. **Drop a dimension by an exchange argument.** Sort items so that an optimal solution takes them in sorted order; then the "which items are used" dimension becomes "prefix index".

The price of rolling: you lose the table needed to **reconstruct** the solution. Keep one bit per (layer, state) for the decision taken, or use Hirschberg's divide and conquer (🧊, [sequence DP](03-sequence-dp-lis-lcs-edit-distance.md)).

### 1.8 Reconstructing the answer

The DP gives the value; the solution is the path achieving it. Two ways:

- **Parent pointers:** store, for each state, which transition gave the optimum. Walk back from the answer state.
- **Recompute:** at state $s$, find any transition $t$ with $f(s) = w(s,t)\otimes f(t)$ and move to $t$. No extra memory, same cost as one more DP layer.

For the **lexicographically smallest** optimal solution, compute the DP over *suffixes* ($g(s)$ = best way to finish from $s$), then walk *forward* from the start, at each step taking the smallest decision that keeps $g$ optimal. Walking backward from the end gives you lexicographic minimality of the *reversed* sequence, which is usually not what is asked.

### 1.9 Counting, optimisation, feasibility — the semiring matters

| Kind | $\oplus$ | $\otimes$ | Identity of $\oplus$ | Notes |
|---|---|---|---|---|
| min cost | min | + | $+\infty$ | use a large sentinel, beware overflow of `INF + w` |
| max value | max | + | $-\infty$ | unreachable states must stay $-\infty$, not 0 |
| count | + | × | 0 | mod $p$; subtraction needs `+ p` |
| feasibility | or | and | false | 64 states per machine word with bitsets |
| probability | + | × | 0 | doubles or mod $p$ |
| bottleneck | max | min | $-\infty$ | "maximise the minimum edge" |

The most important difference: **min and max are idempotent, + is not.** In an optimisation DP it is harmless if the same solution is reachable along several paths of the state graph. In a counting DP each object must correspond to **exactly one** path — the decomposition must be *unambiguous*. Coin change is the standard illustration: "last coin is any coin" counts ordered sequences; "process coin types in a fixed order" counts multisets ([knapsack](02-knapsack-family.md) §1.5). When you design a counting DP, write down the canonical form that makes every object unique (e.g. "split at the *first* position where…", "the *largest* element goes…").

Modular counting also forbids comparisons: you cannot take `max` of two values reduced mod $p$, and you cannot test "is the count zero?" (a non-zero count can be $\equiv 0$). If you need both a count and a comparison, keep the comparison quantity exact and the count modular, or cap counts at a threshold (as in [CF 1183H](03-sequence-dp-lis-lcs-edit-distance.md)).

### 1.10 Heuristic 1 — fix the last element (or the last operation)

To find the transition, classify all solutions by their **last decision**. Each class is a smaller instance of the same problem plus one step:

- LIS: classify by the last element → $f(i) = 1 + \max_{j<i,\,a_j<a_i} f(j)$.
- Coin change: classify by the last coin → $f(x) = \sum_c f(x - c)$.
- Partition an array into segments: classify by where the last segment starts → $f(i) = \min_{j<i} f(j) + \text{cost}(j+1, i)$.
- Burst balloons: classify by the **last** balloon to burst in $(l, r)$ — it splits the interval into two parts that never interact again. Classifying by the *first* balloon does not, because its neighbours change ([interval DP](05-interval-dp.md)).

The "last" choice is preferred because, at the moment of the last decision, everything else is already settled, so the remaining parts are independent. If "last" still leaves dependencies, try "first", "the position of the maximum", or "the root" (for trees and intervals).

### 1.11 Heuristic 2 — add a dimension for whatever breaks the greedy

Often a greedy *almost* works: "take the best option at each step" fails only because one small piece of information about the past matters. Put exactly that piece into the state.

- Vacation: "take each day's best activity" fails only because yesterday's activity is forbidden → remember yesterday.
- Maximum subarray with one segment multiplied by $x$: Kadane works for a fixed phase → state = phase $\in\{\text{before}, \text{inside}, \text{after}\}$ (Example 4).
- Stock trading with cooldown or a fee → state = holding / not holding / cooling down.
- Longest increasing run after deleting one element → state = (position, deleted yet?).

The general form: the set of valid decision sequences is recognised by a **finite automaton**, and the DP state is $(\text{position}, \text{automaton state})$. Example 5 makes the automaton explicit (KMP). This view also tells you when DP is hopeless: if validity needs unbounded memory (e.g. "all chosen values distinct" over a large value range), no small state exists — look for a different structure (sorting, exchange arguments, inclusion–exclusion).

### 1.12 Complexity estimation — states × transitions

Before writing code, multiply. A Codeforces 1–2 s limit allows roughly $10^8$–$3\cdot10^8$ simple operations in C++ and somewhat less in Java (JIT warm-up, bounds checks, no unsigned types).

| Constraint | Typical DP | Count |
|---|---|---|
| $n \le 20$ | subsets × vertex | $n 2^n \approx 2\cdot 10^7$ |
| $n \le 15$–$16$ | subsets × submasks | $3^n \approx 1.4\cdot10^7$ / $4.3\cdot 10^7$ |
| $n \le 400$–$500$ | intervals × split point | $n^3/6 \approx 10^7$–$2\cdot10^7$ |
| $n \le 5000$ | pairs $(i,j)$ | $n^2 = 2.5\cdot10^7$ |
| $n \cdot W \le 10^7$–$10^8$ | knapsack | $nW$ |
| $n \le 10^5$–$10^6$ | prefix DP with $O(1)$ or $O(\log)$ transitions | $n\log n$ |
| number up to $10^{18}$ | digit DP | $19 \times 2 \times |\text{extra}| \times 10$ |

Memory: 256 MB holds $6.4\cdot10^7$ `int` or $3.2\cdot10^7$ `long long`. If a table does not fit, it is a hint that one dimension must be rolled or eliminated.

When the product is too large you have three moves: **fewer states** (an observation that drops a dimension, §1.7), **cheaper transitions** (prefix sums, monotonic queue, convex hull trick, divide and conquer, Knuth — [DP optimisations](../07-DP-Optimizations/README.md)), or **a different state** (swap value and index, process in a different order).

### 1.13 The state-design checklist

Run this, in order, every time:

1. **Brute force first.** Write the recursion that makes decisions one at a time. Its parameters are your first-draft state.
2. **Shrink the state.** For each parameter ask: can two values lead to different futures? If not, drop or coarsen it (exact sum → sum mod $k$; set → size; sequence → last element).
3. **Grow the state if needed.** For each constraint the future must check, is the needed information in the state? (Last colour used, run length so far, phase, tight flag.)
4. **Progress measure.** Which quantity strictly increases along every transition? That proves acyclicity and gives the evaluation order.
5. **Count** states × transitions and memory against the limits (§1.12).
6. **Base case and answer.** Which state starts, which states are terminal, and is the answer one state or an aggregate over many?
7. **Counting? Check uniqueness.** Does each object correspond to exactly one path?
8. **Optimise memory** (rolling) and transitions only after the plain version is correct.
9. **Stress-test** against the brute force from step 1 on random tiny inputs.

---

## 2. Formulas, definitions and identities

**Bellman equation** (pull form, over a semiring):
$$f(t) = \bigoplus_{s\,:\,s\to t} f(s) \otimes w(s,t), \qquad f(\text{start}) = \mathbb 1.$$
Meaning: the value of a state aggregates over its last transition. Correct by induction along a topological order.

**Running time:**
$$T = \sum_{\text{states } s} \big(\text{cost of evaluating } s\big) = \sum_s O(\deg^-(s)) = O(V + E).$$

**Counting by partition (sum rule):** if the set $S$ of solutions is partitioned into classes $S_1,\dots,S_k$ by the last decision, then $|S| = \sum_i |S_i|$. Requires disjointness — the reason counting decompositions must be unambiguous.

**Product rule (independent parts):** if a solution splits into two parts chosen independently, the count is the product. Used in tree DP and interval DP (left part × right part).

**Range transitions via prefix sums:** if $f(i) = \sum_{j=i-k}^{i-1} f(j)$, then with $P(i) = \sum_{j \le i} f(j)$,
$$f(i) = P(i-1) - P(i-k-1),$$
turning $O(nk)$ into $O(n)$ (Example 2; [prefix-sum optimisation](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md)).

**Rolling arrays:** if $f_i$ depends only on $f_{i-1}$, memory $O(n W) \to O(W)$; time unchanged.

**Typical state counts:**

| State | Count |
|---|---|
| prefixes | $n+1$ |
| pairs $i<j$ / intervals | $\binom{n}{2}$ / $\frac{n(n+1)}{2}$ |
| subsets | $2^n$ |
| (subset, element) | $n 2^n$ |
| (set, submask) pairs | $\sum_{k}\binom{n}{k}2^k = 3^n$ |
| digit DP | $\text{len} \times 2 \times |\text{extra}|$ |
| tree DP | $O(n)$ states, total transitions $O(n)$ (sum of degrees) |

**Expected value (linearity):** $\mathbb E[\sum X_i] = \sum \mathbb E[X_i]$ regardless of dependence — often lets you avoid a DP entirely ([expected-value DP](10-probability-and-expected-value-dp.md)).

---

## 3. Implementation (C++ and Java)

One small problem, every style. **Frog** ([AtCoder DP A · Frog 1](https://atcoder.jp/contests/dp/tasks/dp_a)): stones $1..n$ with heights $h_i$; from stone $i$ the frog jumps to $i+1$ or $i+2$ paying $|h_i - h_j|$. Minimum total cost to reach stone $n$. ($n \le 10^5$, $h_i \le 10^4$.)

State: $f(i)$ = minimum cost to stand on stone $i$. Last jump came from $i-1$ or $i-2$:
$$f(1)=0,\qquad f(i) = \min\big(f(i-1)+|h_i-h_{i-1}|,\; f(i-2)+|h_i-h_{i-2}|\big).$$

### 3.1 Pull tabulation

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> h(n);
    for (auto& x : h) cin >> x;
    vector<long long> f(n, LLONG_MAX);
    f[0] = 0;
    for (int i = 1; i < n; i++) {
        f[i] = f[i - 1] + llabs(h[i] - h[i - 1]);
        if (i >= 2) f[i] = min(f[i], f[i - 2] + llabs(h[i] - h[i - 2]));
    }
    cout << f[n - 1] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long[] h = new long[n];
        for (int i = 0; i < n; i++) h[i] = nl();
        long[] f = new long[n];
        for (int i = 1; i < n; i++) {
            f[i] = f[i - 1] + Math.abs(h[i] - h[i - 1]);
            if (i >= 2) f[i] = Math.min(f[i], f[i - 2] + Math.abs(h[i] - h[i - 2]));
        }
        System.out.println(f[n - 1]);
    }
}
```

<!-- test
in:
5
1 5 2 8 3
out:
2
-->
<!-- test
in:
1
7
out:
0
-->
<!-- test
in:
2
3 9
out:
6
-->

### 3.2 Push tabulation

Same DAG, edges relaxed from the source side. Note the initialisation to $+\infty$ — in push form every state starts "unreached".

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> h(n);
    for (auto& x : h) cin >> x;
    const long long INF = LLONG_MAX / 4;
    vector<long long> f(n, INF);
    f[0] = 0;
    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j <= min(n - 1, i + 2); j++)       // successors of state i
            f[j] = min(f[j], f[i] + llabs(h[i] - h[j]));
    }
    cout << f[n - 1] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long[] h = new long[n];
        for (int i = 0; i < n; i++) h[i] = nl();
        long[] f = new long[n];
        Arrays.fill(f, Long.MAX_VALUE / 4);
        f[0] = 0;
        for (int i = 0; i < n; i++)
            for (int j = i + 1; j <= Math.min(n - 1, i + 2); j++)
                f[j] = Math.min(f[j], f[i] + Math.abs(h[i] - h[j]));
        System.out.println(f[n - 1]);
    }
}
```

<!-- test
in:
5
1 5 2 8 3
out:
2
-->
<!-- test
in:
1
7
out:
0
-->

### 3.3 Memoised recursion (and how to survive the stack)

Depth reaches $n = 10^5$. The C++ version relies on a large stack (Codeforces: 256 MB). The Java version runs in a thread with a 256 MB stack — the standard contest workaround.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<long long> h, memo;
vector<char> done;

long long f(int i) {                       // min cost to reach stone i
    if (i == 0) return 0;
    if (done[i]) return memo[i];
    long long best = f(i - 1) + llabs(h[i] - h[i - 1]);
    if (i >= 2) best = min(best, f(i - 2) + llabs(h[i] - h[i - 2]));
    done[i] = 1;
    return memo[i] = best;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    cin >> n;
    h.resize(n);
    for (auto& x : h) cin >> x;
    memo.assign(n, 0);
    done.assign(n, 0);
    cout << f(n - 1) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    static long[] h, memo;
    static boolean[] done;

    static long f(int i) {
        if (i == 0) return 0;
        if (done[i]) return memo[i];
        long best = f(i - 1) + Math.abs(h[i] - h[i - 1]);
        if (i >= 2) best = Math.min(best, f(i - 2) + Math.abs(h[i] - h[i - 2]));
        done[i] = true;
        return memo[i] = best;
    }

    public static void main(String[] args) throws Exception {
        Thread t = new Thread(null, () -> {
            try {
                int n = (int) nl();
                h = new long[n];
                for (int i = 0; i < n; i++) h[i] = nl();
                memo = new long[n];
                done = new boolean[n];
                System.out.println(f(n - 1));
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
        }, "solver", 1 << 28);                // 256 MB stack for deep recursion
        t.start();
        t.join();
    }
}
```

<!-- test
in:
5
1 5 2 8 3
out:
2
-->
<!-- test
in:
2
3 9
out:
6
-->

### 3.4 Reconstruction with parent pointers

Print the cost and the stones visited. Tie-break (stated so the output is unique): prefer arriving from $i-1$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> h(n);
    for (auto& x : h) cin >> x;
    vector<long long> f(n, 0);
    vector<int> par(n, -1);
    for (int i = 1; i < n; i++) {
        f[i] = f[i - 1] + llabs(h[i] - h[i - 1]);
        par[i] = i - 1;
        if (i >= 2 && f[i - 2] + llabs(h[i] - h[i - 2]) < f[i]) {   // strict: ties keep i-1
            f[i] = f[i - 2] + llabs(h[i] - h[i - 2]);
            par[i] = i - 2;
        }
    }
    vector<int> path;
    for (int v = n - 1; v != -1; v = par[v]) path.push_back(v + 1);
    reverse(path.begin(), path.end());
    cout << f[n - 1] << "\n";
    for (size_t k = 0; k < path.size(); k++) cout << path[k] << " \n"[k + 1 == path.size()];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long[] h = new long[n];
        for (int i = 0; i < n; i++) h[i] = nl();
        long[] f = new long[n];
        int[] par = new int[n];
        par[0] = -1;
        for (int i = 1; i < n; i++) {
            f[i] = f[i - 1] + Math.abs(h[i] - h[i - 1]);
            par[i] = i - 1;
            if (i >= 2 && f[i - 2] + Math.abs(h[i] - h[i - 2]) < f[i]) {
                f[i] = f[i - 2] + Math.abs(h[i] - h[i - 2]);
                par[i] = i - 2;
            }
        }
        ArrayDeque<Integer> path = new ArrayDeque<>();
        for (int v = n - 1; v != -1; v = par[v]) path.addFirst(v + 1);
        StringBuilder sb = new StringBuilder();
        sb.append(f[n - 1]).append('\n');
        StringJoiner sj = new StringJoiner(" ");
        for (int v : path) sj.add(Integer.toString(v));
        sb.append(sj).append('\n');
        System.out.print(sb);
    }
}
```

<!-- test
in:
5
1 5 2 8 3
out:
2
1 3 5
-->
<!-- test
in:
3
4 4 4
out:
0
1 2 3
-->
<!-- test
in:
1
9
out:
0
1
-->

---

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| "number of ways … modulo $10^9+7$ / 998244353" | counting DP; check the decomposition is unambiguous |
| "minimum / maximum … " and a greedy has a counterexample | optimisation DP: what does the greedy forget? |
| choices made left to right with a local constraint (no two adjacent, at most $k$ in a row, alternate) | state = (position, the last few choices or a run length) |
| "subsequence" | fix the last chosen element; state = last index or last value |
| "split / partition the array into segments" | $f(i) = \text{opt}_{j<i} f(j) + \text{cost}(j+1,i)$ |
| small numeric range for some quantity (sum ≤ $10^5$, $k \le 100$) | that quantity is a DP index |
| $n \le 20$ | bitmask state ([bitmask DP](06-bitmask-dp.md)) |
| $n \le 500$, merging/removing on a line | interval DP ([interval DP](05-interval-dp.md)) |
| numbers up to $10^{18}$ with a digit property | digit DP ([digit DP](07-digit-dp.md)) |
| tree, "choose vertices/edges with a local rule" | tree DP ([tree DP](08-tree-dp-and-rerooting.md)) |
| "expected number of steps", "probability that" | probability/expected-value DP ([EV DP](10-probability-and-expected-value-dp.md)) |
| a string must avoid/contain patterns | DP over (position, automaton state) — KMP or Aho–Corasick |

**Often confused with:**

- *Greedy* — if an exchange argument proves the local choice is safe, greedy is simpler and faster ([greedy](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md)). Many 1600–2000 problems are "greedy after sorting, DP for the remaining choice".
- *Shortest paths* — if transitions can go "backwards" (the state graph has cycles), you need Dijkstra/BFS, not a single pass.
- *Binary search on the answer* — "maximise the minimum" often becomes "binary search $X$, then a feasibility DP".
- *Pure combinatorics* — a counting DP whose transition is a binomial can sometimes collapse into a closed formula ([combinatorics](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md)).

---

## 5. Worked examples (graded)

### Example 1 — Vacation  ·  ★ ≈1000 (est.)

- **Source:** [AtCoder DP C · Vacation](https://atcoder.jp/contests/dp/tasks/dp_c)
- **Difficulty:** ≈1000 (est.)
- **Problem:** $n \le 10^5$ days; on day $i$ you do one of three activities with happiness $a_i, b_i, c_i$ ($\le 10^4$). You may not do the same activity on two consecutive days. Maximise total happiness.
- **Thinking from first principles:** Greedy "take the best activity every day" breaks exactly when two consecutive days have the same best activity. What breaks the greedy is *yesterday's activity* — so remember it. Two histories that end on day $i$ with the same last activity are equivalent: the future only checks "not equal to the last one". State $(i, j)$, $3n$ states, 2 transitions each.

<details><summary>Solution</summary>

$f(i, j)$ = best total over days $1..i$ if day $i$ does activity $j$:
$$f(i,j) = v_{i,j} + \max_{k \ne j} f(i-1, k),\qquad f(0, \cdot) = 0.$$
Answer $\max_j f(n, j)$. Rolling array: only the previous day is needed. $O(n)$ time, $O(1)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    array<long long, 3> f = {0, 0, 0};    // f[j]: best so far if the last day did activity j
    for (int i = 0; i < n; i++) {
        long long v[3];
        cin >> v[0] >> v[1] >> v[2];
        array<long long, 3> g;
        for (int j = 0; j < 3; j++) g[j] = v[j] + max(f[(j + 1) % 3], f[(j + 2) % 3]);
        f = g;
    }
    cout << max({f[0], f[1], f[2]}) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long[] f = new long[3];
        for (int i = 0; i < n; i++) {
            long[] v = {nl(), nl(), nl()};
            long[] g = new long[3];
            for (int j = 0; j < 3; j++) g[j] = v[j] + Math.max(f[(j + 1) % 3], f[(j + 2) % 3]);
            f = g;
        }
        System.out.println(Math.max(f[0], Math.max(f[1], f[2])));
    }
}
```

</details>

<!-- test
in:
3
1 2 3
1 2 3
1 2 3
out:
8
-->
<!-- test
in:
1
5 3 7
out:
7
-->
<!-- test
in:
2
10 1 1
10 1 1
out:
11
-->

### Example 2 — Flowers  ·  ★ 1700

- **Source:** [CF 474D · Flowers](https://codeforces.com/problemset/problem/474/D) — 1700
- **Difficulty:** 1700
- **Problem:** A row of flowers is a sequence of red flowers (length 1) and white groups (exactly $k$ white flowers in a row). For $t \le 10^5$ queries $(a, b)$ with $1 \le a \le b \le 10^5$, count rows whose length is in $[a, b]$, modulo $10^9+7$.
- **Thinking from first principles:** A row is a sequence of tokens of length 1 or $k$. Fix the **last token**: it is red (the rest has length $i-1$) or a white group (the rest has length $i-k$). The classes are disjoint, so counting is safe. The answer for a range is a range sum — precompute prefix sums once and answer each query in $O(1)$; recomputing per query would be $O(t\cdot 10^5)$, too slow.

<details><summary>Solution</summary>

$f(0) = 1$, $f(i) = f(i-1) + [i \ge k]\,f(i-k)$. Prefix $P(i) = \sum_{j=1}^{i} f(j)$, answer $P(b) - P(a-1)$ (add the modulus before reducing). $O(10^5 + t)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const int MOD = 1'000'000'007, N = 100000;
    int t, k;
    cin >> t >> k;
    vector<long long> f(N + 1), P(N + 1);
    f[0] = 1;
    for (int i = 1; i <= N; i++) {
        f[i] = (f[i - 1] + (i >= k ? f[i - k] : 0)) % MOD;
        P[i] = (P[i - 1] + f[i]) % MOD;
    }
    while (t--) {
        int a, b;
        cin >> a >> b;
        cout << (P[b] - P[a - 1] + MOD) % MOD << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        final int N = 100000;
        int t = (int) nl(), k = (int) nl();
        long[] f = new long[N + 1], P = new long[N + 1];
        f[0] = 1;
        for (int i = 1; i <= N; i++) {
            f[i] = (f[i - 1] + (i >= k ? f[i - k] : 0)) % MOD;
            P[i] = (P[i - 1] + f[i]) % MOD;
        }
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            int a = (int) nl(), b = (int) nl();
            sb.append((P[b] - P[a - 1] + MOD) % MOD).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
3 2
1 3
2 3
4 4
out:
6
5
5
-->
<!-- test
in:
1 1
1 3
out:
14
-->
<!-- test
in:
2 5
1 4
5 5
out:
4
2
-->

### Example 3 — Sleeping Schedule  ·  ★ 1700

- **Source:** [CF 1324E · Sleeping Schedule](https://codeforces.com/problemset/problem/1324/E) — 1700
- **Difficulty:** 1700
- **Problem:** A day has $h$ hours ($h \le 2000$). Starting at time 0, you go to sleep $n \le 2000$ times; before the $i$-th sleep you stay awake either $a_i$ or $a_i - 1$ hours, then sleep exactly $h$ hours. A sleep is *good* if it starts at an hour in $[l, r]$. Maximise the number of good sleeps.
- **Thinking from first principles:** The brute force has $2^n$ histories. What does the future need? Only *the hour of the day* at which the last sleep started — sleeping exactly $h$ hours means waking at the same hour. All histories with the same current hour are equivalent. State $(i, t)$ with $t \in [0,h)$: $n h = 4\cdot10^6$ states, 2 transitions each. Unreachable states must stay at $-\infty$ — initialising them to 0 would let the DP "teleport" to any hour.

<details><summary>Solution</summary>

$f(i, t)$ = max good sleeps among the first $i$ if sleep $i$ starts at hour $t$; $f(0, 0) = 0$, others $-\infty$. Push: from $(i, t)$ go to $u = (t + a_{i+1} - \delta) \bmod h$, $\delta \in \{0,1\}$, gaining $[l \le u \le r]$. Answer $\max_t f(n, t)$. $O(nh)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, h, l, r;
    cin >> n >> h >> l >> r;
    const int NEG = INT_MIN / 2;
    vector<int> f(h, NEG), g(h);
    f[0] = 0;
    for (int i = 0; i < n; i++) {
        int a;
        cin >> a;
        fill(g.begin(), g.end(), NEG);
        for (int t = 0; t < h; t++) {
            if (f[t] == NEG) continue;                 // unreachable hour
            for (int d = a - 1; d <= a; d++) {
                int u = (t + d) % h;
                g[u] = max(g[u], f[t] + (l <= u && u <= r));
            }
        }
        swap(f, g);
    }
    cout << *max_element(f.begin(), f.end()) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl(), h = (int) nl(), l = (int) nl(), r = (int) nl();
        final int NEG = Integer.MIN_VALUE / 2;
        int[] f = new int[h], g = new int[h];
        Arrays.fill(f, NEG);
        f[0] = 0;
        for (int i = 0; i < n; i++) {
            int a = (int) nl();
            Arrays.fill(g, NEG);
            for (int t = 0; t < h; t++) {
                if (f[t] == NEG) continue;
                for (int d = a - 1; d <= a; d++) {
                    int u = (t + d) % h;
                    g[u] = Math.max(g[u], f[t] + (l <= u && u <= r ? 1 : 0));
                }
            }
            int[] tmp = f; f = g; g = tmp;
        }
        int best = NEG;
        for (int v : f) best = Math.max(best, v);
        System.out.println(best);
    }
}
```

</details>

<!-- test
in:
3 10 4 6
5 5 5
out:
2
-->
<!-- test
in:
1 5 0 0
1
out:
1
-->
<!-- test
in:
4 3 1 1
2 2 2 2
out:
2
-->

### Example 4 — Beautiful Array  ·  ★ 1900

- **Source:** [CF 1155D · Beautiful Array](https://codeforces.com/problemset/problem/1155/D) — 1900
- **Difficulty:** 1900
- **Problem:** Array $a$ of $n \le 3\cdot 10^5$ integers ($|a_i| \le 10^9$) and an integer $x$ ($|x| \le 100$). The beauty is the maximum subarray sum (the empty subarray counts, so beauty $\ge 0$). You may multiply at most one contiguous subarray by $x$. Maximise the beauty.
- **Thinking from first principles:** Without the operation this is Kadane: state "best sum of a subarray ending here". The operation breaks Kadane only because the subarray now passes through *phases*: before the multiplied segment, inside it, after it. Whatever else the history did is irrelevant — only the phase and the best sum so far matter. Try the dead end first: "choose the segment to multiply as the most negative subarray when $x<0$" fails because the chosen subarray and the multiplied segment interact. The phase automaton handles every interaction at once: $3n$ states, $O(1)$ transitions. Values reach $3\cdot10^5 \cdot 10^{11} = 3\cdot10^{16}$ — use 64-bit.

<details><summary>Solution</summary>

Let $f_0, f_1, f_2$ be the best sum of a subarray ending at $i$ in phase before / inside / after the multiplied segment ($f_0$ may be empty, i.e. $\ge 0$):
$$f_0 \leftarrow \max(0, f_0 + a_i),\quad f_1 \leftarrow \max(f_0^{\text{old}}, f_1) + x a_i,\quad f_2 \leftarrow \max(f_1^{\text{old}}, f_2) + a_i .$$
Answer: the maximum of all values seen and 0. Starting $f_1$ from $f_0^{\text{old}} \ge 0$ also covers "the subarray starts inside the multiplied segment". $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    long long x;
    cin >> n >> x;
    const long long NEG = LLONG_MIN / 4;
    long long f0 = 0, f1 = NEG, f2 = NEG, best = 0;
    for (int i = 0; i < n; i++) {
        long long a;
        cin >> a;
        long long g0 = max(0LL, f0 + a);
        long long g1 = max(f0, f1) + x * a;            // enter (from phase 0) or stay inside
        long long g2 = max(f1, f2) + a;                // leave (from phase 1) or stay after
        f0 = g0, f1 = g1, f2 = g2;
        best = max({best, f0, f1, f2});
    }
    cout << best << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long x = nl();
        final long NEG = Long.MIN_VALUE / 4;
        long f0 = 0, f1 = NEG, f2 = NEG, best = 0;
        for (int i = 0; i < n; i++) {
            long a = nl();
            long g0 = Math.max(0, f0 + a);
            long g1 = Math.max(f0, f1) + x * a;
            long g2 = Math.max(f1, f2) + a;
            f0 = g0; f1 = g1; f2 = g2;
            best = Math.max(best, Math.max(f0, Math.max(f1, f2)));
        }
        System.out.println(best);
    }
}
```

</details>

<!-- test
in:
5 -2
-3 8 -2 1 -6
out:
22
-->
<!-- test
in:
3 2
-1 -2 -3
out:
0
-->
<!-- test
in:
1 100
1000000000
out:
100000000000
-->

### Example 5 — Required Substring  ·  ★ ≈2000 (est.)

- **Source:** [CSES 1112 · Required Substring](https://cses.fi/problemset/task/1112)
- **Difficulty:** ≈2000 (est.)
- **Problem:** Count strings of length $n \le 1000$ over `A`–`Z` that contain a given pattern $P$ ($|P| = m \le 100$) as a substring, modulo $10^9+7$.
- **Thinking from first principles:** Count the complement: strings that *avoid* $P$. What must we remember about a prefix to know whether a future occurrence of $P$ appears? Not the whole prefix — only **the longest suffix of the prefix that is also a prefix of $P$** (a future occurrence must start inside that suffix, or later). Two prefixes with the same such length are equivalent. This is precisely the state of the KMP automaton, so the DP is "walk the automaton": states $0..m-1$ are "not matched yet, $j$ characters of $P$ matched", state $m$ is absorbing "already contained". $O(n\cdot m\cdot 26)$.

<details><summary>Solution</summary>

Build the automaton $\delta(j, c)$ with the prefix function $\pi$: $\delta(j,c) = j+1$ if $P_j = c$, else $\delta(\pi_{j-1}, c)$ (or 0 when $j=0$). Then $g(\delta(j,c)) \mathrel{+}= f(j)$ for every $j<m$, $c$, and $g(m) \mathrel{+}= 26 f(m)$. Answer $f_n(m)$. See [KMP](../11-Strings/02-prefix-function-kmp.md) for the prefix function. (Equivalently: $26^n - \sum_{j<m} f_n(j)$.)

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const long long MOD = 1'000'000'007;
    int n;
    string p;
    cin >> n >> p;
    int m = p.size();
    vector<int> pi(m, 0);
    for (int i = 1; i < m; i++) {
        int k = pi[i - 1];
        while (k > 0 && p[i] != p[k]) k = pi[k - 1];
        if (p[i] == p[k]) k++;
        pi[i] = k;
    }
    vector<array<int, 26>> go(m);                     // go[j][c]: next automaton state
    for (int j = 0; j < m; j++)
        for (int c = 0; c < 26; c++) {
            if (p[j] - 'A' == c) go[j][c] = j + 1;
            else go[j][c] = j == 0 ? 0 : go[pi[j - 1]][c];
        }
    vector<long long> f(m + 1, 0), g(m + 1);
    f[0] = 1;
    for (int i = 0; i < n; i++) {
        fill(g.begin(), g.end(), 0);
        g[m] = f[m] * 26 % MOD;                       // already contains P: any letter
        for (int j = 0; j < m; j++) {
            if (!f[j]) continue;
            for (int c = 0; c < 26; c++) {
                int u = go[j][c];
                g[u] += f[j];
                if (g[u] >= MOD) g[u] -= MOD;
            }
        }
        swap(f, g);
    }
    cout << f[m] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static String ns() throws IOException {
        int c = IN.read();
        while (c <= ' ') c = IN.read();
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = IN.read(); }
        return sb.toString();
    }

    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        int n = Integer.parseInt(ns());
        String p = ns();
        int m = p.length();
        int[] pi = new int[m];
        for (int i = 1; i < m; i++) {
            int k = pi[i - 1];
            while (k > 0 && p.charAt(i) != p.charAt(k)) k = pi[k - 1];
            if (p.charAt(i) == p.charAt(k)) k++;
            pi[i] = k;
        }
        int[][] go = new int[m][26];
        for (int j = 0; j < m; j++)
            for (int c = 0; c < 26; c++) {
                if (p.charAt(j) - 'A' == c) go[j][c] = j + 1;
                else go[j][c] = j == 0 ? 0 : go[pi[j - 1]][c];
            }
        long[] f = new long[m + 1], g = new long[m + 1];
        f[0] = 1;
        for (int i = 0; i < n; i++) {
            Arrays.fill(g, 0);
            g[m] = f[m] * 26 % MOD;
            for (int j = 0; j < m; j++) {
                if (f[j] == 0) continue;
                for (int c = 0; c < 26; c++) {
                    int u = go[j][c];
                    g[u] += f[j];
                    if (g[u] >= MOD) g[u] -= MOD;
                }
            }
            long[] tmp = f; f = g; g = tmp;
        }
        System.out.println(f[m]);
    }
}
```

</details>

<!-- test
in:
3
AA
out:
51
-->
<!-- test
in:
2
AB
out:
1
-->
<!-- test
in:
2
AAA
out:
0
-->
<!-- test
in:
1000
A
out:
578969911
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Unreachable ≠ zero.** In max-DPs initialise unreachable states to $-\infty$ and skip them; a 0 lets the DP start from states that are impossible (Example 3). In min-DPs use $+\infty$ but make sure `INF + w` cannot overflow (`LLONG_MAX/4`, or skip INF states).
2. **Check the state is complete by trying to break it.** Take two different histories with the same state and look for a future that treats them differently. If you find one, add the distinguishing information.
3. **Counting must be unambiguous.** If an object can be produced by two different transition paths, it is counted twice. Fix a canonical decomposition (fixed order of item types, "first position where …", "the largest element").
4. **Mod arithmetic:** reduce after every `+` and `*`; `(a - b + MOD) % MOD` for subtraction; in Java `%` of a negative is negative; in C++ `int * int` overflows before you reduce — use `1LL *` or `long long` everywhere.
5. **Never compare modded values.** Max/min/zero-tests on counts reduced mod $p$ are meaningless; cap counts (`min(cnt, LIMIT)`) when you need comparisons.
6. **Order of evaluation:** write down which states a state reads, then check your loops produce them first. Interval DP by length; knapsack direction; tree DP in post-order.
7. **Rolling arrays need clearing.** When you reuse `g` for the next layer, reset it (to 0, $-\infty$ or $+\infty$) before pushing into it. Forgetting this is the most common rolling-array bug.
8. **Base cases are states too.** $f(0)$ (empty prefix), the empty subset, the empty interval: decide their value from the definition, not by guessing. The empty object is usually counted once ($f(0)=1$).
9. **Recursion depth:** memoised recursion over $10^5$+ states needs a big stack; in Java use `new Thread(null, r, "", 1 << 28)`; locally on Windows link C++ with a larger stack. Iterative tabulation sidesteps it.
10. **Memo sentinel collisions:** if $-1$ is a legitimate value, use a separate `visited` array.
11. **Java performance:** `long[][]` with the large dimension *last* (`dp[i][w]` iterating `w` inside) is cache-friendly; `dp[w][i]` with `i` inner jumps between arrays. Avoid `HashMap<Long, …>` memo for dense states — boxing is 10–50× slower than arrays.
12. **Multiple test cases:** do not `memset` the whole maximal table for every test case if the sum of $n$ is bounded but $t$ is large — clear only what the test case used.
13. **Answer is often an aggregate, not one state:** max over all end states (LIS), sum over a range (Example 2), the absorbing state (Example 5).
14. **Precompute across queries.** If the DP does not depend on the query, run it once (Example 2). If it depends on the query only through the start, reverse the direction of the DP.
15. **When stuck, write the brute force.** Its recursion parameters are a first draft of the state; then shrink (§1.13). This is also the stress-test oracle.

---

## 7. Going further (toward 2400–2600+)

- **Transition optimisations** — once the state is right, the bottleneck is the transition: [prefix sums / monotonic queue](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md), [convex hull trick](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md), [divide and conquer](../07-DP-Optimizations/03-divide-and-conquer-optimization.md), [Knuth](../07-DP-Optimizations/04-knuth-optimization.md), [Aliens trick](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md), [slope trick](../07-DP-Optimizations/07-slope-trick.md).
- **Linear DP with huge $n$** — a fixed linear recurrence over a small state is a matrix power ([matrix exponentiation for DP](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md)).
- **DP + data structure** — when transitions are "max over $j$ with $a_j < a_i$", a Fenwick/segment tree over values replaces the inner loop ([Fenwick tree](../08-Data-Structures/01-fenwick-tree.md)).
- **Exchange argument + DP** — sort by a key proved by an exchange argument, then run a knapsack in that order (CF 864E Fire, CF 1203F2). The sort is what makes the "set" state collapse to a prefix.
- **Connected-component DP** (🔴) — build a permutation by inserting elements in sorted order while tracking the number of "components" (CF 704B Ant Man). The state is the number of partial blocks, not their contents.
- **DP of DP** (🔴) — count inputs for which an inner DP produces a given result; the outer state is the *entire state vector* of the inner DP, compressed (e.g. LCS with a fixed string: the inner DP row has a compact difference encoding).
- **Game DP** — winning/losing positions are a feasibility DP over game states ([game DP](../13-Game-Theory/04-minimax-and-game-dp.md)).

---

## 8. Practice ladder

**≤ 1400**
- [ ] [AtCoder DP A · Frog 1](https://atcoder.jp/contests/dp/tasks/dp_a) — the template above
- [ ] [AtCoder DP B · Frog 2](https://atcoder.jp/contests/dp/tasks/dp_b) — $k$ predecessors
- [ ] [CSES 1633 · Dice Combinations](https://cses.fi/problemset/task/1633) — fix the last die
- [ ] [CSES 1637 · Removing Digits](https://cses.fi/problemset/task/1637) — min steps, state = current number
- [ ] [CF 1195C · Basketball Exercise](https://codeforces.com/problemset/problem/1195/C) — 1400
- [ ] [CF 698A · Vacations](https://codeforces.com/problemset/problem/698/A) — 1400

**1400–1700**
- [ ] [CF 455A · Boredom](https://codeforces.com/problemset/problem/455/A) — 1500
- [ ] [CF 545C · Woodcutters](https://codeforces.com/problemset/problem/545/C) — 1500
- [ ] [CF 1881E · Block Sequence](https://codeforces.com/problemset/problem/1881/E) — 1500
- [ ] [CF 1272D · Remove One Element](https://codeforces.com/problemset/problem/1272/D) — 1500
- [ ] [CF 1842C · Tenzing and Balls](https://codeforces.com/problemset/problem/1842/C) — 1500
- [ ] [CF 1741E · Sending a Sequence Over the Network](https://codeforces.com/problemset/problem/1741/E) — 1600
- [ ] [CF 1389B · Array Walk](https://codeforces.com/problemset/problem/1389/B) — 1600
- [ ] [CF 977F · Consecutive Subsequence](https://codeforces.com/problemset/problem/977/F) — 1700
- [ ] [CF 118D · Caesar's Legions](https://codeforces.com/problemset/problem/118/D) — 1700

**1700–2100**
- [ ] [CF 1625C · Road Optimization](https://codeforces.com/problemset/problem/1625/C) — 1700
- [ ] [CF 1969C · Minimizing the Sum](https://codeforces.com/problemset/problem/1969/C) — 1700
- [ ] [CF 1398D · Colored Rectangles](https://codeforces.com/problemset/problem/1398/D) — 1800
- [ ] [CF 1437C · Chef Monocarp](https://codeforces.com/problemset/problem/1437/C) — 1800
- [ ] [CF 1525D · Armchairs](https://codeforces.com/problemset/problem/1525/D) — 1800
- [ ] [CF 1353E · K-periodic Garland](https://codeforces.com/problemset/problem/1353/E) — 1900
- [ ] [CF 1077F1 · Pictures with Kittens (easy version)](https://codeforces.com/problemset/problem/1077/F1) — 1900

**2100+**
- [ ] [CF 1667B · Optimal Partition](https://codeforces.com/problemset/problem/1667/B) — 2100
- [ ] [CF 1699D · Almost Triple Deletions](https://codeforces.com/problemset/problem/1699/D) — 2300
- [ ] [CF 1188C · Array Beauty](https://codeforces.com/problemset/problem/1188/C) — 2500

---

## 9. LeetCode / FAANG cross-reference

- [LC 70 · Climbing Stairs](https://leetcode.com/problems/climbing-stairs/) — Easy — Frog with unit costs: fix the last step.
- [LC 198 · House Robber](https://leetcode.com/problems/house-robber/) — Medium — state = (index, took previous?).
- [LC 213 · House Robber II](https://leetcode.com/problems/house-robber-ii/) — Medium — a cycle: run the line DP twice (first house excluded / last excluded).
- [LC 309 · Best Time to Buy and Sell Stock with Cooldown](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-with-cooldown/) — Medium — state = holding / not holding / cooling down.
- [LC 152 · Maximum Product Subarray](https://leetcode.com/problems/maximum-product-subarray/) — Medium — keep both max and min ending here: the sign is what breaks Kadane.
- [LC 91 · Decode Ways](https://leetcode.com/problems/decode-ways/) — Medium — fix the last token (1 or 2 digits); zeros are the edge cases.
- [LC 139 · Word Break](https://leetcode.com/problems/word-break/) — Medium — feasibility DP over prefixes.
- [LC 2140 · Solving Questions With Brainpower](https://leetcode.com/problems/solving-questions-with-brainpower/) — Medium — suffix DP (push form is awkward, pull from the right is natural).
- [LC 552 · Student Attendance Record II](https://leetcode.com/problems/student-attendance-record-ii/) — Hard — state = (absences used, current late-run length): an explicit automaton.

In interviews, say the state out loud *as a sentence* ("$f(i,j)$ is the best total for days $1..i$ when day $i$ is activity $j$"), then the transition, base case, order and complexity — that is exactly the checklist of §1.13. See [interview DP 1-D](../17-FAANG-Interview-DSA/13-dynamic-programming-1d.md).

---

## 10. Self-check

1. Define "two histories are equivalent". Why may a state split an equivalence class but never merge two classes?
2. "Longest simple path has no optimal substructure." Rephrase this in terms of an incomplete state, and give the complete state.
3. Why is it harmless to reach the same solution through two paths in a min-cost DP, but fatal in a counting DP?
4. When would you choose push over pull? Name a DP optimisation that requires the pull form.
5. In Example 3, what goes wrong if unreachable hours are initialised to 0 instead of $-\infty$?
6. You have $n = 2000$, values $\le 2000$, and a DP with state $(i, v)$ and transition "max over all $v' < v$". Estimate the cost and name the fix.
7. Why does "fix the last balloon to burst" give independent sub-problems while "fix the first balloon" does not?
8. How do you reconstruct the lexicographically smallest optimal solution?

<details><summary>Answers</summary>

1. $h \sim h'$ if every continuation is valid after both or neither, with equal added cost. Splitting only creates duplicate work (two states with equal futures); merging makes one state stand for histories with different futures, so its value is wrong for at least one of them.
2. The future of a path at $v$ depends on which vertices are already used, so "vertex" is not a complete state. The complete state is (visited set, current vertex): bitmask DP, $O(2^n n^2)$.
3. Min/max are idempotent — counting a solution twice does not change the minimum. Addition is not, so every object must correspond to exactly one path.
4. Push when successors are easy to enumerate (probability DP, "what can I do next"). Prefix-sum, monotonic-queue and convex-hull optimisations need pull form, because they aggregate over a structured set of predecessors.
5. Every hour would look reachable with 0 good sleeps, and the DP could start the next sleep from an impossible hour, overstating the answer.
6. $2000 \times 2000$ states × up to 2000 transitions $= 8\cdot10^9$ — too slow. Keep a running prefix maximum over $v$ (or a Fenwick tree if the order is not monotone) to make each transition $O(1)$: $4\cdot10^6$.
7. When the last balloon $k$ in $(l, r)$ bursts, all others in $(l,k)$ and $(k,r)$ are already gone, and their neighbours during their bursts were inside their own side or the fixed boundaries $l, k, r$. Fixing the first balloon changes the neighbours of the remaining ones, so the two sides interact.
8. Compute the DP over suffixes (best way to finish from each state), then walk forward from the start, always taking the smallest decision whose successor still achieves the optimum.

</details>
