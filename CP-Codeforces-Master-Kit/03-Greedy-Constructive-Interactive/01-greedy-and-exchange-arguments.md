# Greedy algorithms and exchange arguments

> **Band:** 🟢–🟣 800–2100 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [sorting and comparators](../01-Foundations/05-sorting-and-comparators.md), [brute force and backtracking](../01-Foundations/04-recursion-brute-force-and-backtracking.md)
> **You can say you know this when:** you can propose a greedy rule, kill the wrong candidates with a 20-line brute force, and prove the survivor with an exchange argument or a stays-ahead argument in a few minutes — and you can write comparators that are guaranteed strict weak orderings.

## 1. First principles — why this works

A **greedy algorithm** builds a solution through a sequence of local choices that are never undone. That is the whole
definition; what makes greedy a technique rather than a guess is the proof that the local choice is safe.

**Why greedy is dangerous.** Almost every problem admits several "obvious" greedy rules, and most of them are wrong:

| Problem | Plausible rule | Counterexample |
|---|---|---|
| Coin change with coins {1, 3, 4}, amount 6 | take the largest coin that fits | 4+1+1 (3 coins) vs 3+3 (2 coins) |
| Max number of disjoint intervals | shortest interval first | [1,5], [4,7], [6,10]: shortest is [4,7], blocks both others |
| Max number of disjoint intervals | earliest start first | [1,100], [2,3], [4,5] |
| 0/1 knapsack | best value/weight first | W=10: (6 kg, 7), (5 kg, 5), (5 kg, 5) |

So the workflow a strong solver uses is: **(1)** list 2–4 candidate rules; **(2)** brute force tiny inputs (n ≤ 8, all
permutations or all subsets) and compare each rule with the brute force — wrong rules die in seconds; **(3)** prove the
survivor, at least in sketch, before coding anything subtle. Step (2) is not optional for contest play: it is cheaper than
a wrong submission.

**What a correct greedy needs.** Two properties, the same two that DP needs plus one more:

1. *Greedy-choice property* — there is an optimal solution that contains the greedy's first choice.
2. *Optimal substructure* — after making that choice, what remains is a smaller instance of the same problem
   (so the argument can be applied again, by induction).

DP needs (2) only and tries every first choice; greedy commits to one. Everything below is a way to prove (1).

### Proof technique A — the exchange argument

Take an arbitrary optimal solution $O$. If it differs from the greedy solution $G$, locate a difference and **modify
$O$ towards $G$ without making it worse**. Repeat until $O = G$; then $G$ is at least as good as an optimum.

For *ordering* problems (schedule jobs, concatenate strings, process projects), the clean form is the **adjacent
swap** argument. Suppose the greedy sorts by a key $\prec$. Any order that is not sorted contains an adjacent pair
$(j, i)$ with $i \prec j$ (an adjacent inversion). Swapping that pair changes only the contribution of those two
elements — everything before them is untouched and everything after them starts at the same time/state. If you show
that the swap never makes things worse, then bubble-sorting $O$ into $G$ (which removes one inversion per swap) never
makes it worse, so $G$ is optimal. The whole proof reduces to a **two-element inequality**, which is why the rule
"compare `i then j` with `j then i`" finds most ordering keys.

The argument silently requires that $\prec$ is a **strict weak ordering** (transitive, with transitive ties);
otherwise "the sorted order" is not even defined and `std::sort` may crash. See §2.6.

### Proof technique B — greedy stays ahead

Define a measure of progress after $k$ steps and prove by induction that greedy's measure is at least as good as
any other solution's after $k$ steps. Then greedy cannot finish with a worse result.

*Interval scheduling* (pick the maximum number of pairwise disjoint intervals). Greedy: repeatedly take the interval
with the earliest end among those starting after the last chosen end. Let greedy pick $g_1, g_2, \dots$ and an optimum
pick $o_1, o_2, \dots, o_m$, both sorted by end. Claim: $\text{end}(g_k) \le \text{end}(o_k)$ for all $k$. For $k=1$ greedy
chose the globally earliest end. If it holds for $k$, then $o_{k+1}$ starts after $\text{end}(o_k) \ge \text{end}(g_k)$,
so $o_{k+1}$ was available to greedy at step $k+1$, and greedy picked something ending no later. Hence greedy has
at least $m$ intervals.

### Proof technique C — contradiction at the first difference

Assume greedy is not optimal; among optimal solutions take the one agreeing with greedy for the longest prefix. At
the first index where they differ, show that switching the optimal solution's choice to greedy's choice keeps it
optimal — contradicting maximality of the agreeing prefix. This is the exchange argument written as a contradiction;
use whichever form reads better in your head.

### Proof technique D — lower bound plus matching construction

Show that *every* solution needs at least $X$ (a counting or obstruction argument), then show that greedy achieves
$X$. Example: the minimum number of platforms (rooms) equals the maximum number of intervals overlapping at one
instant. The lower bound is obvious (overlapping intervals need different rooms); a sweep that reuses any free room
never exceeds it.

### Matroid intuition (brief)

When does "sort by weight, add an element if the set stays feasible" work for *every* weight function? Exactly when
the feasible sets form a **matroid**: (i) subsets of feasible sets are feasible; (ii) *exchange*: if $|A| < |B|$ are both
feasible, some $x \in B \setminus A$ keeps $A \cup \{x\}$ feasible (Rado–Edmonds theorem). Matroids you will meet:

- forests of a graph (graphic matroid) → **Kruskal's MST** ([MST](../09-Graphs/03-minimum-spanning-trees.md));
- linearly independent vectors over GF(2) → **XOR basis** greedy ([XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md));
- sets of unit-time jobs that can all meet their deadlines → **scheduling with deadlines and profits**
  ([heaps and regret](02-greedy-with-heaps-and-regret.md)).

0/1 knapsack sets do not satisfy the exchange axiom, which is the structural reason the ratio greedy fails there. You
rarely need to *prove* a matroid in a contest; recognising "this is a matroid in disguise" tells you that the plain
greedy is safe.

## 2. Formulas, definitions and identities

### 2.1 Interval problems

- **Activity selection.** Max number of pairwise disjoint intervals = sort by right end, take an interval if its left
  end is $\ge$ the last taken right end. $O(n \log n)$. Proof: stays ahead (§1).
- **Duality.** Max number of pairwise disjoint closed intervals = min number of points that stab every interval. The
  greedy's chosen right ends *are* a stabbing set of that size. (LC 452 is exactly this.)
- **Min rooms / platforms.** $\min \#\text{rooms} = \max_t \#\{i : l_i \le t < r_i\}$ (half-open). Interval graphs
  are perfect: chromatic number = clique number. Sweep events: $(l, +1)$, $(r, -1)$, with $-1$ processed first at equal
  times for half-open intervals. $O(n \log n)$.
- **Min intervals to cover $[0, L]$.** Sort by left end; repeatedly, among intervals with $l \le$ covered, take the max
  $r$. Stays ahead on the covered prefix. $O(n \log n)$.

### 2.2 Single-machine scheduling (all jobs available at time 0, no idle time)

Let job $i$ have processing time $p_i$, weight $w_i$, deadline $d_i$; $C_i$ = completion time.

| Objective | Optimal order | Two-element inequality ($i$ before $j$ is no worse iff …) |
|---|---|---|
| $\sum C_i$ | $p$ ascending (SPT) | $p_i \le p_j$ |
| $\sum w_i C_i$ | $p_i / w_i$ ascending (**Smith's rule**) | $p_i w_j \le p_j w_i$ |
| $L_{\max} = \max_i (C_i - d_i)$ | $d$ ascending (**EDF**) | $d_i \le d_j$ |
| $\sum (d_i - C_i)$ (CSES "Tasks and Deadlines") | SPT, since $\sum d_i$ is constant | $p_i \le p_j$ |
| number of late jobs | Moore–Hodgson: EDF + drop longest when late | heap greedy, see [02](02-greedy-with-heaps-and-regret.md) |

*Smith's rule derivation.* Jobs $i, j$ adjacent, starting at time $T$:
$\text{cost}(i,j) = w_i(T+p_i) + w_j(T+p_i+p_j)$ and $\text{cost}(j,i) = w_j(T+p_j) + w_i(T+p_j+p_i)$, so
$$\text{cost}(i,j) - \text{cost}(j,i) = w_j p_i - w_i p_j .$$
$i$ first is no worse iff $p_i w_j \le p_j w_i$, i.e. $p_i / w_i \le p_j / w_j$. Everything outside the pair is unchanged.

*EDF derivation.* With $i, j$ adjacent and $d_i \le d_j$: in order $(j,i)$ the later job $i$ finishes at
$T + p_i + p_j$ with lateness $T+p_i+p_j-d_i$. In order $(i,j)$ both latenesses are $\le T+p_i+p_j-d_i$ (job $j$
finishes at the same time with a later deadline; job $i$ finishes earlier). So the max cannot increase.

*SPT closed form.* In sorted order $p_{(1)} \le \dots \le p_{(n)}$: $\sum_i C_i = \sum_{k=1}^{n} (n-k+1)\, p_{(k)}$ — the
$k$-th job delays itself and every later job. Putting large coefficients on small $p$ is the rearrangement inequality.

### 2.3 Rearrangement inequality

For $a_1 \le \dots \le a_n$ and any permutation $\sigma$ of $b$: $\sum a_i b_{(n+1-i)} \le \sum a_i b_{\sigma(i)} \le \sum a_i b_{(i)}$
(sorted with sorted maximises, sorted with reverse-sorted minimises). Proof: adjacent exchange — if $a_i \le a_j$ and
$b_i > b_j$, swapping gives $(a_j - a_i)(b_i - b_j) \ge 0$ improvement. It underlies "pair the largest with the largest".

### 2.4 Huffman coding (optimal merge pattern)

Given weights $f_1, \dots, f_n$, build a binary tree with these leaves minimising $\sum f_i \cdot \text{depth}_i$. Equivalently,
repeatedly merge two piles paying their total; **cost = sum of all internal-node weights**. Greedy: always merge the two
smallest. $O(n \log n)$ with a heap; $O(n)$ after sorting with the two-queue trick (merged weights are produced in
non-decreasing order, so a FIFO queue of merged weights stays sorted).

*Proof.* (i) In some optimal tree the two smallest weights are siblings at maximum depth: swap them with the two
deepest siblings — moving a smaller weight deeper never increases cost. (ii) Merge them into one leaf of weight
$f_1+f_2$: every tree for the reduced instance corresponds to a tree for the original with cost exactly $f_1+f_2$ larger.
Induct.

### 2.5 Fractional knapsack

Items with weight $w_i$ and value $v_i$, capacity $W$, fractions allowed. Sort by $v_i / w_i$ descending, take whole items
while they fit, then a fraction of the next. Optimal because a unit of capacity spent on a lower-density item can be moved
to a higher-density item without loss (an exchange on infinitesimal pieces; formally it is the LP optimum).
Compare densities with cross-multiplication $v_i w_j > v_j w_i$, not floating division.

### 2.6 Comparators and strict weak orderings

`std::sort`, `std::set`, `Collections.sort`, `TreeMap` require `comp(a, b)` ("a strictly before b") to satisfy:

1. irreflexive: `comp(a, a)` is false — so **never** use `<=`;
2. asymmetric: `comp(a, b)` implies `!comp(b, a)`;
3. transitive: `comp(a, b) && comp(b, c)` implies `comp(a, c)`;
4. incomparability is transitive: if neither of $a, b$ precedes the other, and likewise $b, c$, then likewise $a, c$.

Violations are undefined behaviour in C++ (out-of-bounds reads inside `std::sort` are real, and crash on some inputs)
and throw `IllegalArgumentException: Comparison method violates its general contract!` in Java's TimSort.

**Concatenation order** ("smallest/largest number from pieces"). Define $a \prec b \iff a + b < b + a$ (string
concatenation, lexicographic compare). Is it transitive? Treat a string $s$ over an alphabet of size $K$ as the integer
$\text{val}(s)$ in base $K$ (strings of equal length compare lexicographically exactly as these integers, and $a+b$,
$b+a$ have equal length). Then $\text{val}(a+b) = \text{val}(a) K^{|b|} + \text{val}(b)$, so
$$a + b < b + a \iff \text{val}(a)\,(K^{|b|} - 1) < \text{val}(b)\,(K^{|a|} - 1) \iff \frac{\text{val}(a)}{K^{|a|}-1} < \frac{\text{val}(b)}{K^{|b|}-1}.$$
The comparator is "compare one real number per string", hence a strict weak ordering. (The number is the value of the
infinite repetition $aaa\ldots$ read as a base-$K$ fraction — that is why "compare $a^\infty$ with $b^\infty$" is the
intuition.)

**Ratio keys** $x_i / y_i$ with $y_i > 0$: compare $x_i y_j < x_j y_i$ in 64-bit (or `__int128` if the products can
exceed $9.2 \cdot 10^{18}$). If some $y$ can be 0 or negative, handle signs explicitly — cross-multiplication flips the
inequality for negative denominators and breaks transitivity.

### 2.7 Projects with requirement and change (CF 1203F1 pattern)

Rating $r$; project $i$ needs $r \ge a_i$ before and changes $r$ by $b_i$ (and $r$ must stay $\ge 0$). Do all projects with
$b_i \ge 0$ first, by $a_i$ ascending. Then do the projects with $b_i < 0$ by $a_i + b_i$ **descending**.
Two-element check for negatives: the minimum starting rating for order $(i, j)$ is $\max(a_i,\; a_j - b_i)$ (plus the
non-negativity terms, which equal the final rating constraint and do not depend on the order). Since $-b_j > 0$,
$a_i - b_j \ge a_i$, and $a_i - b_j \ge a_j - b_i \iff a_i + b_i \ge a_j + b_j$. Hence if $a_i+b_i \ge a_j+b_j$,
$\max(a_i, a_j - b_i) \le a_i - b_j \le \max(a_j, a_i - b_j)$: putting $i$ first never needs more rating.

## 3. Implementation (C++ and Java)

### 3.1 Interval toolkit: activity selection, minimum rooms, covering a segment

```cpp
// Max number of pairwise disjoint intervals [l, r] where touching endpoints are allowed (l_next >= r_prev).
int maxDisjoint(vector<pair<long long, long long>> iv) {
    sort(iv.begin(), iv.end(), [](auto& x, auto& y) { return x.second < y.second; });
    long long last = LLONG_MIN; int cnt = 0;
    for (auto& [l, r] : iv) if (l >= last) { ++cnt; last = r; }
    return cnt;
}
// Minimum number of rooms for half-open intervals [l, r).
int minRooms(const vector<pair<long long, long long>>& iv) {
    vector<pair<long long, int>> ev;
    for (auto& [l, r] : iv) { ev.push_back({l, +1}); ev.push_back({r, -1}); }
    sort(ev.begin(), ev.end());            // at equal time, -1 sorts before +1: a room freed at t is reusable at t
    int cur = 0, best = 0;
    for (auto& [t, d] : ev) best = max(best, cur += d);
    return best;
}
// Min number of intervals whose union covers [0, L]; -1 if impossible.
int minCover(vector<pair<long long, long long>> iv, long long L) {
    sort(iv.begin(), iv.end());
    long long covered = 0; int cnt = 0; size_t i = 0;
    while (covered < L) {
        long long reach = covered;
        while (i < iv.size() && iv[i].first <= covered) reach = max(reach, iv[i++].second);
        if (reach == covered) return -1;  // gap: nothing extends the covered prefix
        covered = reach; ++cnt;
    }
    return cnt;
}
```

```java
static int maxDisjoint(long[][] iv) {
    long[][] a = iv.clone();
    Arrays.sort(a, (x, y) -> Long.compare(x[1], y[1]));   // object sort = merge sort, no anti-quicksort issue
    long last = Long.MIN_VALUE; int cnt = 0;
    for (long[] p : a) if (p[0] >= last) { cnt++; last = p[1]; }
    return cnt;
}
static int minRooms(long[][] iv) {
    int n = iv.length;
    long[] ev = new long[2 * n];
    // encode (time, type) in one long: type 0 = end, 1 = start, so ends sort first at equal times
    for (int i = 0; i < n; i++) { ev[2 * i] = iv[i][0] * 2 + 1; ev[2 * i + 1] = iv[i][1] * 2; }
    Arrays.sort(ev);                                       // long[]: dual-pivot quicksort, but values are not adversarial
    int cur = 0, best = 0;
    for (long e : ev) { cur += (e & 1) == 1 ? 1 : -1; best = Math.max(best, cur); }
    return best;
}
static int minCover(long[][] iv, long L) {
    long[][] a = iv.clone();
    Arrays.sort(a, (x, y) -> Long.compare(x[0], y[0]));
    long covered = 0; int cnt = 0, i = 0;
    while (covered < L) {
        long reach = covered;
        while (i < a.length && a[i][0] <= covered) reach = Math.max(reach, a[i++][1]);
        if (reach == covered) return -1;
        covered = reach; cnt++;
    }
    return cnt;
}
```

The `time * 2 + type` encoding assumes non-negative times; for negative times shift them first.

### 3.2 Fractional knapsack, Huffman cost, safe comparators

```cpp
// Fractional knapsack: max value with capacity W. Density compared by cross-multiplication.
double fractionalKnapsack(vector<pair<long long, long long>> items, long long W) {  // (weight, value), weight > 0
    sort(items.begin(), items.end(), [](auto& a, auto& b) {
        return (__int128)a.second * b.first > (__int128)b.second * a.first;   // v_a/w_a > v_b/w_b
    });
    double total = 0;
    for (auto& [w, v] : items) {
        if (W == 0) break;
        long long take = min(w, W);
        total += (double)v * take / w;
        W -= take;
    }
    return total;
}
// Huffman / optimal merge cost: repeatedly merge the two smallest.
long long huffmanCost(const vector<long long>& f) {
    priority_queue<long long, vector<long long>, greater<long long>> pq(f.begin(), f.end());
    long long cost = 0;
    while (pq.size() > 1) {
        long long a = pq.top(); pq.pop();
        long long b = pq.top(); pq.pop();
        cost += a + b; pq.push(a + b);
    }
    return cost;
}
// Concatenation comparator (a strict weak ordering, proved in section 2.6).
bool concatLess(const string& a, const string& b) { return a + b < b + a; }
// Debug helper: check the strict-weak-ordering axioms on a small sample (O(n^3)); use it when a comparator is new.
template <class T, class Cmp> bool isStrictWeakOrder(const vector<T>& v, Cmp cmp) {
    int n = v.size();
    for (int i = 0; i < n; i++) {
        if (cmp(v[i], v[i])) return false;
        for (int j = 0; j < n; j++) {
            if (cmp(v[i], v[j]) && cmp(v[j], v[i])) return false;
            for (int k = 0; k < n; k++) {
                if (cmp(v[i], v[j]) && cmp(v[j], v[k]) && !cmp(v[i], v[k])) return false;
                bool ij = !cmp(v[i], v[j]) && !cmp(v[j], v[i]), jk = !cmp(v[j], v[k]) && !cmp(v[k], v[j]);
                bool ik = !cmp(v[i], v[k]) && !cmp(v[k], v[i]);
                if (ij && jk && !ik) return false;
            }
        }
    }
    return true;
}
```

```java
static double fractionalKnapsack(long[][] items, long W) {     // items[i] = {weight, value}, weight > 0
    long[][] a = items.clone();
    // v_x/w_x > v_y/w_y  <=>  v_x*w_y > v_y*w_x ; Math.multiplyHigh would be needed above ~3e9 * 3e9
    Arrays.sort(a, (x, y) -> Long.compare(y[1] * x[0], x[1] * y[0]));
    double total = 0;
    for (long[] it : a) {
        if (W == 0) break;
        long take = Math.min(it[0], W);
        total += (double) it[1] * take / it[0];
        W -= take;
    }
    return total;
}
static long huffmanCost(long[] f) {
    PriorityQueue<Long> pq = new PriorityQueue<>();
    for (long x : f) pq.add(x);
    long cost = 0;
    while (pq.size() > 1) {
        long a = pq.poll(), b = pq.poll();
        cost += a + b; pq.add(a + b);
    }
    return cost;
}
static final Comparator<String> CONCAT = (a, b) -> (a + b).compareTo(b + a);
static <T> boolean isStrictWeakOrder(List<T> v, Comparator<T> c) {
    int n = v.size();
    for (int i = 0; i < n; i++) {
        if (c.compare(v.get(i), v.get(i)) != 0) return false;
        for (int j = 0; j < n; j++) {
            if (Integer.signum(c.compare(v.get(i), v.get(j))) != -Integer.signum(c.compare(v.get(j), v.get(i)))) return false;
            for (int k = 0; k < n; k++) {
                int ij = Integer.signum(c.compare(v.get(i), v.get(j))), jk = Integer.signum(c.compare(v.get(j), v.get(k)));
                int ik = Integer.signum(c.compare(v.get(i), v.get(k)));
                if (ij <= 0 && jk <= 0 && ik > 0) return false;      // <= and <= must give <=
                if (ij == 0 && jk == 0 && ik != 0) return false;     // ties are transitive
            }
        }
    }
    return true;
}
```

Java comparators return an `int` sign, so "strict weak ordering" becomes "a total preorder consistent in sign". The
classic bug is `(a, b) -> a - b` on ints that can overflow: use `Integer.compare`.

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| "choose an order / permutation to process items", cost depends on position or accumulated time | adjacent-swap exchange: compare `i then j` with `j then i`, extract a key |
| "maximum number of non-overlapping …", "minimum number of points/arrows to hit all …" | sort by right end (activity selection / stabbing duality) |
| "minimum number of rooms / machines / colours so that overlapping things differ" | max overlap via sweep (lower bound = answer) |
| "cover a segment with fewest intervals", "jump game II", "minimum taps" | extend-the-reach greedy |
| "merge piles, cost = sum", "split a stick, cost = length" | Huffman (reverse of splitting is merging) |
| "fractions allowed", "can take part of an item" | density sort (fractional knapsack) |
| "arrange pieces to get the smallest/largest concatenation" | comparator $a+b$ vs $b+a$ |
| constraints $n \le 2 \cdot 10^5$ and an optimisation over subsets/orders | either greedy + sort, or DP with a sort-defined order |
| greedy rule plus "you can change your mind later" | heap / regret greedy, see [02](02-greedy-with-heaps-and-regret.md) |

**Commonly confused with:** DP. If the two-element inequality depends on more than the two elements (for example
on the time already elapsed in a non-linear way), adjacent exchange fails and you usually need DP — often *after*
sorting by an exchange key (sort to fix the order, then knapsack over that order: CF 1203F2, LC 1665).

## 5. Worked examples (graded)

### Example 1 — Movie Festival  ·  ★ ≈1200 (est.)

- **Source:** [CSES 1629 · Movie Festival](https://cses.fi/problemset/task/1629)
- **Difficulty:** ≈1200 (est.)
- **Problem:** $n \le 2 \cdot 10^5$ movies with start $a_i$ and end $b_i$ ($1 \le a_i < b_i \le 10^9$). Watch as many complete
  movies as possible; a movie may start at the exact moment the previous one ends. Print the maximum count.
- **Thinking from first principles:** we choose a set, so order is free — think of what to commit to first. Shortest
  movie first fails ($[1,5],[4,7],[6,10]$); earliest start fails ($[1,100]$ swallows everything). The resource being
  consumed is "time to the right", so commit to the movie that frees the screen earliest. Stays-ahead proof in §1.

<details><summary>Solution</summary>

Sort by end time; scan, taking a movie whenever its start is at least the end of the last taken movie.
Correctness: stays ahead on the end time of the $k$-th chosen movie. $O(n \log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<pair<long long, long long>> v(n);            // (end, start)
    for (auto& [e, s] : v) cin >> s >> e;
    sort(v.begin(), v.end());
    long long lastEnd = LLONG_MIN; int cnt = 0;
    for (auto& [e, s] : v) if (s >= lastEnd) { ++cnt; lastEnd = e; }
    cout << cnt << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[][] v = new long[n][];
        for (int i = 0; i < n; i++) { long s = in.nextLong(), e = in.nextLong(); v[i] = new long[]{s, e}; }
        Arrays.sort(v, (x, y) -> Long.compare(x[1], y[1]));
        long lastEnd = Long.MIN_VALUE; int cnt = 0;
        for (long[] m : v) if (m[0] >= lastEnd) { cnt++; lastEnd = m[1]; }
        System.out.println(cnt);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
4
1 3
2 5
3 6
6 8
out:
3
-->
<!-- test
in:
1
5 9
out:
1
-->
<!-- test
in:
3
1 10
2 3
4 5
out:
2
-->

</details>

### Example 2 — Minimise the maximum lateness (EDF)  ·  ★ ≈1400 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈1400 (est.)
- **Problem:** one machine, $n \le 2 \cdot 10^5$ jobs, job $i$ takes $p_i$ time units and has deadline $d_i$
  ($1 \le p_i, d_i \le 10^9$). Process all jobs back to back from time 0 in an order of your choice. The lateness of a job
  is $\max(0, C_i - d_i)$ where $C_i$ is its completion time. Minimise the maximum lateness.
- **Thinking from first principles:** an ordering problem, so try the adjacent swap. For adjacent $i, j$ the pair
  finishes at the same time $T + p_i + p_j$ in both orders; only who finishes *last* differs. The last one should be the
  one with the later deadline. The key is the deadline alone — $p$ does not matter, which surprises people who try
  "shortest first" or "slack $d - p$ first" (both lose on small cases; check with brute force).

<details><summary>Solution</summary>

Sort by deadline (Earliest Deadline First), simulate, take the maximum lateness. Exchange proof in §2.2.
$O(n \log n)$; completion times reach $2 \cdot 10^{14}$, so 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<pair<long long, long long>> job(n);           // (deadline, processing time)
    for (auto& [d, p] : job) cin >> p >> d;
    sort(job.begin(), job.end());
    long long t = 0, worst = 0;
    for (auto& [d, p] : job) { t += p; worst = max(worst, t - d); }
    cout << worst << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] p = new long[n], d = new long[n];
        for (int i = 0; i < n; i++) { p[i] = in.nextLong(); d[i] = in.nextLong(); }
        Integer[] idx = new Integer[n];
        for (int i = 0; i < n; i++) idx[i] = i;
        Arrays.sort(idx, (x, y) -> Long.compare(d[x], d[y]));
        long t = 0, worst = 0;
        for (int i : idx) { t += p[i]; worst = Math.max(worst, t - d[i]); }
        System.out.println(worst);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
3
2 2
1 5
3 4
out:
1
-->
<!-- test
in:
1
5 10
out:
0
-->
<!-- test
in:
2
5 1
5 1
out:
9
-->

</details>

### Example 3 — Weighted completion time (Smith's rule)  ·  ★ ≈1500 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈1500 (est.)
- **Problem:** $n \le 2 \cdot 10^5$ jobs with processing time $p_i$ and weight $w_i$ ($1 \le p_i, w_i \le 10^4$). Order them
  on one machine to minimise $\sum w_i C_i$.
- **Thinking from first principles:** heavy jobs want to go early, long jobs want to go late; neither key alone can be
  right ($(p,w) = (1,1), (3,2)$ refutes heaviest-first; $(2,1), (3,10)$ refutes shortest-first). The two-element computation in §2.2 gives the trade-off exactly: sort by
  $p/w$. Cross-multiply to stay in integers; $p_i w_j \le 10^8$ fits easily, the answer needs 64 bits
  ($n \cdot \max w \cdot \sum p \le 2\cdot 10^5 \cdot 10^4 \cdot 2 \cdot 10^9 = 4 \cdot 10^{18}$).

<details><summary>Solution</summary>

Sort by $p_i w_j < p_j w_i$, accumulate. Ties (equal ratios) can go in either order — the pair inequality is an equality.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long long> p(n), w(n);
    for (int i = 0; i < n; i++) cin >> p[i] >> w[i];
    vector<int> idx(n);
    iota(idx.begin(), idx.end(), 0);
    sort(idx.begin(), idx.end(), [&](int a, int b) { return p[a] * w[b] < p[b] * w[a]; });
    long long t = 0, cost = 0;
    for (int i : idx) { t += p[i]; cost += w[i] * t; }
    cout << cost << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] p = new long[n], w = new long[n];
        for (int i = 0; i < n; i++) { p[i] = in.nextLong(); w[i] = in.nextLong(); }
        Integer[] idx = new Integer[n];
        for (int i = 0; i < n; i++) idx[i] = i;
        Arrays.sort(idx, (a, b) -> Long.compare(p[a] * w[b], p[b] * w[a]));
        long t = 0, cost = 0;
        for (int i : idx) { t += p[i]; cost += w[i] * t; }
        System.out.println(cost);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
3
3 1
1 2
2 2
out:
14
-->
<!-- test
in:
1
7 3
out:
21
-->
<!-- test
in:
2
2 1
4 2
out:
14
-->

</details>

### Example 4 — The Smallest String Concatenation  ·  ★ 1700

- **Source:** [CF 632C · The Smallest String Concatenation](https://codeforces.com/problemset/problem/632/C) — 1700
- **Difficulty:** 1700
- **Problem:** $n \le 5 \cdot 10^4$ lowercase strings, each of length $\le 50$. Print the lexicographically smallest string
  obtainable by concatenating all of them in some order.
- **Thinking from first principles:** "sort lexicographically" fails: `b` < `ba` but `ba`+`b` = `bab` < `bba`. Use the
  adjacent swap: in an optimal order, swapping neighbours $a, b$ changes only the substring $ab \to ba$, at the same
  position, so we need $a+b \le b+a$. The remaining worry is transitivity, settled in §2.6 (each string maps to one
  real number).

<details><summary>Solution</summary>

Sort with the comparator $a + b < b + a$ and print the concatenation. Each comparison is $O(L)$ with $L \le 100$,
total $O(n \log n \cdot L)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<string> s(n);
    for (auto& x : s) cin >> x;
    sort(s.begin(), s.end(), [](const string& a, const string& b) { return a + b < b + a; });
    string res;
    for (auto& x : s) res += x;
    cout << res << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StreamTokenizer st = new StreamTokenizer(br);
        st.nextToken();
        int n = (int) st.nval;
        String[] s = new String[n];
        for (int i = 0; i < n; i++) { st.nextToken(); s[i] = st.sval; }
        Arrays.sort(s, (a, b) -> (a + b).compareTo(b + a));
        StringBuilder sb = new StringBuilder();
        for (String x : s) sb.append(x);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(sb);
        out.flush();
    }
}
```

<!-- test
in:
3
b
ba
bab
out:
bababb
-->
<!-- test
in:
3
c
cb
cba
out:
cbacbc
-->
<!-- test
in:
1
abc
out:
abc
-->

</details>

`StreamTokenizer` treats lowercase words as `TT_WORD` tokens by default, which is exactly what this input needs; for
tokens mixing digits and letters, read them with a byte reader instead.

### Example 5 — Stick Divisions (Huffman in reverse)  ·  ★ ≈1500 (est.)

- **Source:** [CSES 1161 · Stick Divisions](https://cses.fi/problemset/task/1161)
- **Difficulty:** ≈1500 (est.)
- **Problem:** a stick of length $x$ must be cut into $n \le 2 \cdot 10^5$ pieces of given lengths $d_1, \dots, d_n$
  ($\sum d_i = x \le 10^9$). Cutting one stick into two costs the length of the stick being cut. Minimise the total cost.
- **Thinking from first principles:** top-down there are too many choices (where to cut, which piece to cut next). Run
  time backwards: cutting is merging in reverse, and the cost of a cut equals the size of the merged stick. So the cost is
  the sum of internal nodes of a binary tree with leaves $d_i$ — Huffman. Merge the two smallest repeatedly.

<details><summary>Solution</summary>

Min-heap of lengths; pop two, add their sum to the answer, push the sum. With $n = 1$ the answer is 0. Proof in §2.4.
$O(n \log n)$. The optimal cost is at most $x \cdot \lceil \log_2 n \rceil \approx 1.8 \cdot 10^{10}$ (a balanced tree already
achieves that), which overflows 32-bit integers — use 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    long long x; int n; cin >> x >> n;
    priority_queue<long long, vector<long long>, greater<long long>> pq;
    for (int i = 0; i < n; i++) { long long d; cin >> d; pq.push(d); }
    long long cost = 0;
    while (pq.size() > 1) {
        long long a = pq.top(); pq.pop();
        long long b = pq.top(); pq.pop();
        cost += a + b; pq.push(a + b);
    }
    cout << cost << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        long x = in.nextLong(); int n = in.nextInt();
        PriorityQueue<Long> pq = new PriorityQueue<>();
        for (int i = 0; i < n; i++) pq.add(in.nextLong());
        long cost = 0;
        while (pq.size() > 1) {
            long a = pq.poll(), b = pq.poll();
            cost += a + b; pq.add(a + b);
        }
        System.out.println(cost);
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
8 3
2 3 3
out:
13
-->
<!-- test
in:
5 1
5
out:
0
-->
<!-- test
in:
10 4
1 2 3 4
out:
19
-->

</details>

### Example 6 — Complete the Projects (easy version)  ·  ★ 2100

- **Source:** [CF 1203F1 · Complete the Projects (easy version)](https://codeforces.com/problemset/problem/1203/F1) — 2100
- **Difficulty:** 2100
- **Problem:** initial rating $r$; $n \le 100$ projects, project $i$ requires rating $\ge a_i$ to start and changes the
  rating by $b_i$ ($-300 \le b_i \le 300$); the rating must never become negative. Can all projects be completed in some order?
  Print `YES` or `NO`.
- **Thinking from first principles:** split by the sign of $b$. A project with $b_i \ge 0$ never hurts once it can be
  started, so do every such project as early as possible: by $a_i$ ascending (if the smallest-requirement one cannot be
  started, none can). For the negative ones, look at the end of the process in reverse, or just do the two-element
  computation (§2.7): order by $a_i + b_i$ descending. Intuition: $a_i + b_i$ is "the rating you are left with if you
  start with just enough"; projects that leave you high should go first. Sorting negatives by $a_i$ descending (a common
  guess) is wrong — the third test below kills it.

<details><summary>Solution</summary>

Positives by $a$ ascending, then negatives by $a + b$ descending; simulate and check $r \ge a_i$ before and $r \ge 0$
after each project. $O(n \log n)$. (The hard version F2 asks for the largest subset: sort the same way, then run a
knapsack-style DP over the negative projects in that order.)

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long r; cin >> n >> r;
    vector<pair<int, int>> pos, neg;
    for (int i = 0; i < n; i++) {
        int a, b; cin >> a >> b;
        (b >= 0 ? pos : neg).push_back({a, b});
    }
    sort(pos.begin(), pos.end());
    sort(neg.begin(), neg.end(), [](auto& x, auto& y) { return x.first + x.second > y.first + y.second; });
    bool ok = true;
    for (auto* group : {&pos, &neg})
        for (auto& [a, b] : *group) {
            if (r < a) ok = false;
            r += b;
            if (r < 0) ok = false;
        }
    cout << (ok ? "YES" : "NO") << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(); long r = in.nextLong();
        List<int[]> pos = new ArrayList<>(), neg = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            int a = in.nextInt(), b = in.nextInt();
            (b >= 0 ? pos : neg).add(new int[]{a, b});
        }
        pos.sort((x, y) -> Integer.compare(x[0], y[0]));
        neg.sort((x, y) -> Integer.compare(y[0] + y[1], x[0] + x[1]));
        boolean ok = true;
        for (List<int[]> g : List.of(pos, neg))
            for (int[] p : g) {
                if (r < p[0]) ok = false;
                r += p[1];
                if (r < 0) ok = false;
            }
        System.out.println(ok ? "YES" : "NO");
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
3 4
4 6
10 -2
8 -1
out:
YES
-->
<!-- test
in:
2 5
5 -3
4 -3
out:
NO
-->
<!-- test
in:
2 11
10 -8
9 -1
out:
YES
-->
<!-- test
in:
1 3
1 -4
out:
NO
-->

</details>

All six solutions were stress-tested against exhaustive search over permutations / merge orders on random inputs with
$n \le 7$.

## 6. Tricks, pitfalls and things to remember

1. **Brute force first, prove second.** A 15-line permutation brute force kills a wrong greedy in seconds; a wrong
   submission costs 10 minutes of penalty and, worse, your confidence in the rest of the idea.
2. **Use the two-element test to *discover* the key**, not just to verify it: write cost$(i,j)$ − cost$(j,i)$, simplify,
   and read off the comparator. If it does not separate into "something about $i$" vs "something about $j$", adjacent
   exchange is the wrong tool.
3. **`<=` in a comparator is undefined behaviour in C++** and throws in Java. Equal elements must compare false both ways.
4. **Cross-multiply ratios**, never divide in floating point inside a comparator: rounding can make it
   non-transitive. Watch the product's range (`__int128` / `Math.multiplyHigh` when needed) and the sign of denominators.
5. **Java `(a, b) -> a - b` overflows** for ints near $\pm 2^{31}$ and silently breaks the order; use `Integer.compare`.
6. **Java primitive sort.** `Arrays.sort(int[])` is a dual-pivot quicksort with an adversarial $O(n^2)$ input; on
   Codeforces, hackers use it. Shuffle first, or sort `Integer[]`/`long[][]` (object sorts are merge sorts), or sort
   encoded `long[]` after shuffling.
7. **Touching intervals.** Decide whether $[1,3]$ and $[3,5]$ conflict and encode it consistently — in activity
   selection (`>=` vs `>`) and in sweeps (end-before-start event order at equal times).
8. **Exchange arguments need the rest of the schedule to be unaffected.** With release times, setup costs that depend on
   the previous job, or non-linear penalties, swapping two jobs shifts others and the proof breaks.
9. **Greedy + sort + DP** is a frequent 2000+ pattern: the exchange argument tells you the order in which items should
   be *considered*, and DP decides *which* items to take (CF 1203F2, "Complete the Projects hard", is the model).
10. **Huffman with $n = 1$** costs 0; with a heap of `int` the merged sums overflow — use 64-bit.
11. **Ties in the greedy key** — make sure any tie order is optimal (the pair inequality is an equality) or add a
    tie-breaker that makes it so.
12. **"Largest number" variants** (LC 179) need the reverse comparator and a final check for an all-zero answer
    (`"00"` → `"0"`).

## 7. Going further (toward 2400–2600+)

- **Exchange order + DP:** CF 1203F2 (2300), LC 1665; also "choose a subset and an order" problems where the order is
  fixed by an exchange key and the subset by knapsack.
- **Two-machine flow shop (Johnson's rule):** jobs with times $(a_i, b_i)$ on machines 1 then 2; minimise makespan. Jobs
  with $a_i < b_i$ first by $a$ ascending, then the rest by $b$ descending. The pairwise key is
  $\min(a_i, b_j) \le \min(a_j, b_i)$, which is *not* a strict weak ordering by itself — the split into two groups is what
  makes it one. A good example of why transitivity must be checked.
- **Greedy on matroids and matroid intersection:** bipartite matching is the intersection of two partition matroids;
  colourful spanning trees and similar problems need matroid intersection (IGM-level, rare).
- **Exchange arguments on trees:** "merge children in a specific order" problems use the same ratio keys at every node
  (e.g. scheduling a tree with precedence constraints and Smith's rule: merge the best-ratio node into its parent).
- **Greedy with a heap, regret and undo:** the next file, [02](02-greedy-with-heaps-and-regret.md); for the convex-function
  view of regret greedy, see [slope trick](../07-DP-Optimizations/07-slope-trick.md).

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 160A · Twins](https://codeforces.com/problemset/problem/160/A) — 900
- [ ] [CF 1165B · Polycarp Training](https://codeforces.com/problemset/problem/1165/B) — 1000
- [ ] [CF 1472D · Even-Odd Game](https://codeforces.com/problemset/problem/1472/D) — 1200
- [ ] [CF 545D · Queue](https://codeforces.com/problemset/problem/545/D) — 1300
- [ ] [CF 479C · Exams](https://codeforces.com/problemset/problem/479/C) — 1400
- [ ] [CF 1369C · RationalLee](https://codeforces.com/problemset/problem/1369/C) — 1400
- [ ] [CF 1380C · Create The Teams](https://codeforces.com/problemset/problem/1380/C) — 1400
- [ ] [CF 1197C · Array Splitting](https://codeforces.com/problemset/problem/1197/C) — 1400
- [ ] [CSES 1629 · Movie Festival](https://cses.fi/problemset/task/1629)
- [ ] [CSES 1619 · Restaurant Customers](https://cses.fi/problemset/task/1619)
- [ ] [CSES 1090 · Ferris Wheel](https://cses.fi/problemset/task/1090)
- [ ] [CSES 1630 · Tasks and Deadlines](https://cses.fi/problemset/task/1630)
- [ ] [CSES 2183 · Missing Coin Sum](https://cses.fi/problemset/task/2183)

**1400–1900**
- [ ] [CF 545C · Woodcutters](https://codeforces.com/problemset/problem/545/C) — 1500
- [ ] [CF 1066B · Heaters](https://codeforces.com/problemset/problem/1066/B) — 1500
- [ ] [CF 1203E · Boxers](https://codeforces.com/problemset/problem/1203/E) — 1500
- [ ] [CF 1336A · Linova and Kingdom](https://codeforces.com/problemset/problem/1336/A) — 1600
- [ ] [CF 1251C · Minimize The Integer](https://codeforces.com/problemset/problem/1251/C) — 1600
- [ ] [CF 632C · The Smallest String Concatenation](https://codeforces.com/problemset/problem/632/C) — 1700
- [ ] [CF 1157C2 · Increasing Subsequence (hard version)](https://codeforces.com/problemset/problem/1157/C2) — 1700
- [ ] [CSES 1164 · Room Allocation](https://cses.fi/problemset/task/1164)
- [ ] [CSES 1161 · Stick Divisions](https://cses.fi/problemset/task/1161)

**1900–2400**
- [ ] [CF 1203F1 · Complete the Projects (easy version)](https://codeforces.com/problemset/problem/1203/F1) — 2100
- [ ] [CF 1203F2 · Complete the Projects (hard version)](https://codeforces.com/problemset/problem/1203/F2) — 2300
- [ ] [CSES 1632 · Movie Festival II](https://cses.fi/problemset/task/1632)

## 9. LeetCode / FAANG cross-reference

- [LC 455 · Assign Cookies](https://leetcode.com/problems/assign-cookies/) — Easy — sort both, smallest cookie that satisfies the least greedy child.
- [LC 1710 · Maximum Units on a Truck](https://leetcode.com/problems/maximum-units-on-a-truck/) — Easy — fractional knapsack with integral items of equal weight.
- [LC 435 · Non-overlapping Intervals](https://leetcode.com/problems/non-overlapping-intervals/) — Medium — $n$ minus activity selection.
- [LC 452 · Minimum Number of Arrows to Burst Balloons](https://leetcode.com/problems/minimum-number-of-arrows-to-burst-balloons/) — Medium — stabbing = disjoint-interval duality.
- [LC 646 · Maximum Length of Pair Chain](https://leetcode.com/problems/maximum-length-of-pair-chain/) — Medium — activity selection with strict inequality.
- [LC 253 · Meeting Rooms II](https://leetcode.com/problems/meeting-rooms-ii/) — Medium 🔒 — max overlap sweep.
- [LC 1024 · Video Stitching](https://leetcode.com/problems/video-stitching/) — Medium — extend-the-reach covering.
- [LC 45 · Jump Game II](https://leetcode.com/problems/jump-game-ii/) — Medium — covering greedy in BFS layers.
- [LC 1326 · Minimum Number of Taps to Open to Water a Garden](https://leetcode.com/problems/minimum-number-of-taps-to-open-to-water-a-garden/) — Hard — segment covering.
- [LC 179 · Largest Number](https://leetcode.com/problems/largest-number/) — Medium — concatenation comparator (reverse) plus the all-zero case.
- [LC 1029 · Two City Scheduling](https://leetcode.com/problems/two-city-scheduling/) — Medium — sort by $a_i - b_i$ (exchange).
- [LC 406 · Queue Reconstruction by Height](https://leetcode.com/problems/queue-reconstruction-by-height/) — Medium — tallest first, insert at index $k$ (exchange on order of insertion).
- [LC 135 · Candy](https://leetcode.com/problems/candy/) — Hard — two passes, each a stays-ahead lower bound.
- [LC 134 · Gas Station](https://leetcode.com/problems/gas-station/) — Medium — restart after the prefix minimum.
- [LC 1167 · Minimum Cost to Connect Sticks](https://leetcode.com/problems/minimum-cost-to-connect-sticks/) — Medium 🔒 — Huffman.
- [LC 1665 · Minimum Initial Energy to Finish Tasks](https://leetcode.com/problems/minimum-initial-energy-to-finish-tasks/) — Hard — exchange key $\text{minimum}_i - \text{actual}_i$, same algebra as §2.7.

Greedy-with-proof is a favourite interview topic precisely because a wrong greedy is easy to propose; interviewers
expect you to justify the rule (an exchange argument in two sentences is enough) and to name a counterexample for the
naive one.

## 10. Self-check

1. State the adjacent-swap argument and explain why it needs the comparator to be transitive.
2. Why does "earliest end first" work for activity selection while "shortest first" fails? Give the stays-ahead invariant.
3. Derive Smith's rule from the two-job cost difference.
4. Why is $a+b<b+a$ a strict weak ordering on strings?
5. What is the minimum number of rooms for intervals, and why is the greedy never worse than that bound?
6. Prove that in Huffman's algorithm the two smallest weights may be taken as siblings.
7. In "Complete the Projects", why sort the negative projects by $a_i+b_i$ rather than by $a_i$?
8. Name two things that break an exchange argument for scheduling problems.

<details><summary>Answers</summary>

1. If an order has an adjacent inversion $(j,i)$ with $i \prec j$, swapping only changes the cost of that pair; show it
   does not increase. Bubble sort removes one inversion per swap, reaching the sorted order. Without transitivity there is
   no consistent "sorted order" to reach, and the sort algorithm itself is undefined.
2. Invariant: end of greedy's $k$-th interval $\le$ end of any solution's $k$-th interval. Shortest-first fails on
   $[1,5],[4,7],[6,10]$.
3. $\text{cost}(i,j)-\text{cost}(j,i) = w_j p_i - w_i p_j$; $i$ first iff $p_i/w_i \le p_j/w_j$.
4. $a+b<b+a \iff \text{val}(a)/(K^{|a|}-1) < \text{val}(b)/(K^{|b|}-1)$: comparing one real number per string.
5. The maximum number of intervals containing a common point; overlapping intervals need distinct rooms (lower bound),
   and the sweep opens a new room only when all open rooms are busy at that instant, so it never exceeds the bound.
6. Take an optimal tree and its two deepest sibling leaves; swapping the two smallest weights into those positions moves
   smaller weights deeper and larger ones shallower, which cannot increase $\sum f_i \text{depth}_i$.
7. The minimum start rating for the order $(i,j)$ is $\max(a_i, a_j-b_i)$; the algebra in §2.7 shows $i$ first is safe iff
   $a_i+b_i \ge a_j+b_j$. Sorting by $a_i$ fails on $r=11$, $(10,-8)$, $(9,-1)$.
8. Release times / idle time (swapping shifts other jobs), sequence-dependent setup times, non-linear penalties, or a
   comparator that is not transitive.

</details>
