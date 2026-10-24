# Coordinate compression and sweep line

> **Band:** 🔵–🟣 1400–2100 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [sorting and comparators](../01-Foundations/05-sorting-and-comparators.md), [STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md), [prefix sums and difference arrays](01-prefix-sums-and-difference-arrays.md), [binary search](02-binary-search-and-binary-search-on-answer.md)
> **You can say you know this when:** you turn "values up to $10^{18}$" into ranks without thinking, you pick the event order at ties from whether endpoints are closed or half-open (and can say why), you convert a static 2D counting question into "sort by one coordinate, sweep, query a Fenwick tree on the other", and you can compute the area of a union of rectangles in $O(n \log n)$.

## 1. First principles — why this works

### 1.1 Coordinate compression: only the order matters

Many algorithms want to **index an array by value**: a counting array, a Fenwick tree over values, a difference array
over coordinates. When values reach $10^9$ or $10^{18}$, or are negative, an array of that size is impossible, and a
`map` costs a $\log$ factor with a large constant on every access.

The key observation: if an algorithm only **compares** values (or tests them for equality), then replacing every value
$v$ by $\varphi(v)$ for any strictly increasing $\varphi$ leaves every comparison outcome, hence the whole execution,
unchanged. The smallest such $\varphi$ is the **rank** among the distinct values:

$$\varphi(v) = \bigl|\{u \in U : u < v\}\bigr|, \qquad U = \text{set of distinct values}, \ |U| = k \le n.$$

So values live in $[0, k)$ and fit in an array of size $n$. Computing ranks is one sort, one dedupe and one binary
search per lookup: $O(n \log n)$ total.

Two things break the "only order matters" premise, and both have standard fixes:

1. **Distances matter** (lengths, areas, number of integer points). Ranks destroy gaps, so keep the sorted array
   `xs` and recover lengths: the **elementary interval** between ranks $i$ and $i+1$ is $[x_i, x_{i+1})$ with length
   $x_{i+1} - x_i$. Every quantity that is constant between consecutive interesting coordinates can be summed over
   elementary intervals.
2. **Queries use values that are not in the array.** Either insert every query value into $U$ before compressing
   (offline), or answer with `lower_bound` semantics ("first element $\ge v$") and its mirror ("last element $\le v$" =
   `upper_bound` $-1$). If a half-open conversion creates new endpoints such as $r+1$, those must be compressed too.

### 1.2 The sweep line: the answer only changes at events

A static problem about intervals, points or rectangles can usually be solved by imagining a vertical line moving from
left to right. Call a coordinate where some object starts or ends an **event**. Between two consecutive events the
set of objects crossing the line (the **active set**) does not change, so anything that depends only on the active
set is constant there. That leaves $O(n)$ distinct states instead of $10^9$ coordinates or $n^2$ pairs.

The algorithm writes itself:

1. Create events `(coordinate, type, payload)`: for an interval, a $+1$ event at its start and a $-1$ event at its end.
2. Sort them by coordinate (ties: §1.3).
3. Process them in order, updating the active set. Between events $x_i$ and $x_{i+1}$ the state is fixed, so add
   $(x_{i+1} - x_i)\cdot g(\text{state})$ for "integral" answers (total length, area, number of integer points) or take
   $\max g(\text{state})$ for extremal answers (maximum overlap).

**Invariant.** After processing every event with coordinate $< x$ (and the right subset of those at $x$), the active
set is exactly the set of objects that contain $x$. Correctness of a sweep is always a proof of this invariant
plus the fact that the answer depends only on the active set. The cost is $O(n \log n)$ for the sort plus $n$ updates of
whatever structure holds the active set: a counter ($O(1)$), a multiset ($O(\log n)$), a Fenwick or segment tree over
the other coordinate ($O(\log n)$).

### 1.3 Ties decide correctness: closed versus half-open

Suppose two meetings are $[1, 3]$ and $[3, 5]$. Do they overlap at time 3?

- **Closed** intervals ($l \le x \le r$): yes, both contain 3. At equal coordinates, process **opens before closes**,
  otherwise the count at $x = 3$ never reaches 2.
- **Half-open** intervals ($l \le x < r$): no; the first meeting is over when the second starts, so one room suffices.
  Process **closes before opens**.

The robust habit is to **convert everything to half-open** and then always use "closes first". For closed integer
intervals that means $[l, r] \to [l, r+1)$, encoded as events $(l, +1)$ and $(r+1, -1)$. Sorting pairs
`(x, delta)` lexicographically then puts $-1$ before $+1$ automatically. For real-valued closed intervals you cannot
add 1; encode the type explicitly (`open = 0, close = 1`) and sort by `(x, type)`.

The same thinking applies to any object: decide what "contains $x$" means at the boundary, then order events so the
invariant of §1.2 holds immediately *after* the whole group of events at $x$ — and, if you read the state in the
middle of a group (as the maximum-overlap scan does after each open), make sure every intermediate state is one that
really occurs.

### 1.4 Offline queries: one dimension becomes time

"How many points satisfy $x \le X$ and $y \le Y$?" asked $q$ times looks like it needs a 2D structure. If all queries
are known in advance, sort points and queries together by the first coordinate and sweep. When the sweep reaches a
query $(X, Y)$, exactly the points with $x \le X$ have been inserted, each as a $+1$ at its compressed $y$ in a
[Fenwick tree](../08-Data-Structures/01-fenwick-tree.md); the answer is the prefix sum up to $Y$. One dimension
became the processing order, the other a data structure: $O((n+q)\log n)$.

This **offline sweep** is one of the most reused ideas in competitive programming. A second classic instance,
"number of distinct values in $a[l..r]$", is Example 3: sort queries by $r$, and keep a mark only at the **last**
occurrence (so far) of each value. A value occurs in $a[l..r]$ exactly when its last occurrence at or before $r$ is
at or after $l$, so the answer is the number of marks in $[l, r]$. Further offline machinery (Mo's algorithm, CDQ,
parallel binary search) is in [sqrt decomposition](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md)
and [offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md).

### 1.5 Sweep plus an ordered set

When the active set must answer **order** questions — the tallest active building, the active point nearest to $y$,
whether a new interval overlaps a stored one — keep it in a balanced BST: `std::set` / `std::multiset` in C++,
`TreeSet` / `TreeMap<key, count>` in Java (see [ordered sets and heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md)).
Two patterns cover most problems:

- **Skyline / maximum of the active set** (Example 4): insert heights at starts, erase at ends, read the maximum
  after each event group. A max-heap with lazy deletion works too.
- **A set of disjoint intervals** (§3.3): store maximal covered segments `start → end`. Inserting $[l, r)$ finds the
  first stored segment that could touch it with one `upper_bound`, then absorbs neighbours while they overlap. Every
  segment is inserted once and erased at most once, so $q$ insertions cost $O(q \log q)$ amortised.

### 1.6 Area of a union of rectangles

Coordinates up to $10^9$ rule out a grid. After compressing both axes the grid has $O(n^2)$ cells, and marking every
rectangle's cells is $O(n^3)$. The sweep does better:

- Sweep $x$. A rectangle $[x_1, x_2) \times [y_1, y_2)$ adds the $y$-interval $[y_1, y_2)$ to the active set at $x_1$
  and removes it at $x_2$.
- Between consecutive event coordinates the **covered $y$-length** $L$ is constant, so area $\mathrel{+}= L \cdot \Delta x$.
- Computing $L$ by scanning the $k-1$ elementary $y$-segments with a cover counter gives $O(n^2)$ total. To get
  $O(n \log n)$, build a [segment tree](../08-Data-Structures/02-segment-tree-basics.md) over the elementary
  $y$-segments. Each node keeps `cnt` (how many active rectangles cover the node's whole range, counted only at the
  canonical nodes of each update) and `len` (covered length inside the node):

$$\text{len}(v) = \begin{cases} y_{r+1} - y_l & \text{cnt}(v) > 0 \\ 0 & \text{cnt}(v) = 0,\ v \text{ a leaf} \\ \text{len}(\text{left}) + \text{len}(\text{right}) & \text{otherwise.} \end{cases}$$

Unlike general [lazy propagation](../08-Data-Structures/03-lazy-propagation.md), nothing is pushed down. Every
removal hits exactly the canonical nodes its matching insertion hit, so `cnt` never goes negative and a node with
`cnt = 0` is described exactly by its children. The root's `len` is $L$. Total $O(n \log n)$ (Example 5).

## 2. Formulas, definitions and identities

| Quantity | Formula | Meaning / proof sketch |
|---|---|---|
| Rank | $\varphi(v) = \lvert\{u \in U: u < v\}\rvert$ = `lower_bound(U, v)` | strictly increasing, so all comparisons are preserved |
| Last element $\le v$ | `upper_bound(U, v) - 1` (may be $-1$) | mirror of `lower_bound` |
| Elementary intervals | $k$ distinct coordinates give $k-1$ gaps $[x_i, x_{i+1})$ | any quantity constant between events is summed per gap |
| Coverage after event $i$ | $c_i = \sum_{j \le i} \delta_j$ | difference array over compressed coordinates ([prefix sums](01-prefix-sums-and-difference-arrays.md)) |
| Union length | $\sum_i (x_{i+1} - x_i)\,[c_i > 0]$ | sum over gaps that are covered |
| Measure covered exactly $t$ times | $\sum_i (x_{i+1}-x_i)\,[c_i = t]$ | for closed integer intervals use $[l, r+1)$; this counts integer points (Example 1) |
| Maximum overlap | $\max_i c_i$ | the maximum of a piecewise-constant function is attained on some gap |
| Minimum rooms | $= $ maximum overlap | lower bound: that many meetings share a point; greedy reuse of the earliest-free room achieves it |
| Dominance count | $F(X, Y) = \#\{p : p_x \le X,\ p_y \le Y\}$ | one offline sweep in $x$ with a BIT over $y$ |
| Points in a rectangle | $F(x_2,y_2) - F(x_1-1,y_2) - F(x_2,y_1-1) + F(x_1-1,y_1-1)$ | inclusion–exclusion of four dominance queries |
| $k$ intervals sharing a point | $\sum_{\text{opens}} \binom{a}{k-1}$, $a$ = active count before the open | each valid $k$-set is counted at its latest start (Example 2) |
| Union of rectangles | $A = \sum_i (x_{i+1} - x_i)\, L_i$ | $L_i$ = covered $y$-length between events $i$ and $i+1$ |

**Minimum rooms = maximum overlap, proof.** Let $c$ be the maximum overlap. At that point $c$ meetings are
simultaneously in progress, so at least $c$ rooms are needed. Conversely, process meetings by start time and give each
one any room that is free (for example the one that became free earliest, kept in a min-heap). If a meeting
starting at $s$ finds all $c$ rooms busy, then $c$ meetings plus this one all contain $s$, so the overlap at $s$ is
$c+1$, a contradiction. In graph terms, interval graphs are perfect: chromatic number equals clique size.

**Complexities.**

| Operation | Cost |
|---|---|
| Compress $n$ values (sort + unique) | $O(n \log n)$ time, $O(n)$ memory |
| One rank lookup (binary search) | $O(\log k)$ |
| Sweep with a counter | $O(n \log n)$ (sort dominates) |
| Sweep with a multiset / BIT / segment tree | $O(n \log n)$ |
| Offline dominance / distinct-values queries | $O((n+q)\log n)$ |
| Disjoint-interval set, $q$ insertions | $O(q \log q)$ amortised |
| Union of $n$ rectangles | $O(n^2)$ by scanning gaps, $O(n \log n)$ with the cover segment tree |

## 3. Implementation (C++ and Java)

### 3.1 Coordinate compression with lookups of absent values

Input: $n$, the array, $q$, then $q$ query values. Output: the number of distinct values $k$, the rank of every
element, and for every query $v$ the number of distinct values $< v$ (its `lower_bound` position).

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    vector<long long> xs = a;                                  // xs[rank] = value, so lengths can be recovered
    sort(xs.begin(), xs.end());
    xs.erase(unique(xs.begin(), xs.end()), xs.end());
    auto rankOf = [&](long long v) { return int(lower_bound(xs.begin(), xs.end(), v) - xs.begin()); };
    cout << xs.size() << '\n';
    for (int i = 0; i < n; i++) cout << rankOf(a[i]) << " \n"[i == n - 1];
    int q; cin >> q;
    for (int i = 0; i < q; i++) { long long v; cin >> v; cout << rankOf(v) << " \n"[i == q - 1]; }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        long[] xs = a.clone();
        shuffle(xs);                                           // Arrays.sort on primitives is a quicksort: shuffle first
        Arrays.sort(xs);
        int k = 0;
        for (int i = 0; i < n; i++) if (k == 0 || xs[i] != xs[k - 1]) xs[k++] = xs[i];   // in-place unique
        StringBuilder sb = new StringBuilder().append(k).append('\n');
        for (int i = 0; i < n; i++) sb.append(rankOf(xs, k, a[i])).append(i == n - 1 ? '\n' : ' ');
        int q = in.nextInt();
        for (int i = 0; i < q; i++) sb.append(rankOf(xs, k, in.nextLong())).append(i == q - 1 ? '\n' : ' ');
        out.print(sb);
        out.flush();
    }
    // xs[0..k) is sorted and distinct, so a hit is unique; a miss returns -(insertion point) - 1.
    static int rankOf(long[] xs, int k, long v) {
        int p = Arrays.binarySearch(xs, 0, k, v);
        return p >= 0 ? p : -p - 1;
    }
    static void shuffle(long[] a) {
        Random rnd = new Random();
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
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
6
1000000000000000000 -5 7 -5 7 0
4
-6 -5 8 1000000000000000001
out:
4
3 0 2 0 2 1
0 0 3 4
-->
<!-- test
in:
1
42
3
41 42 43
out:
1
0
0 0 1
-->

Java notes: `Arrays.binarySearch` on an array **with duplicates** returns an arbitrary matching index, so dedupe first
and pass the range `(0, k)`; on a miss it returns `-(insertion point) - 1`, which is why `rankOf` converts. Other Java
options: a `TreeMap<Long,Integer>` built from the sorted values (gives `ceilingKey` / `floorKey`, about 5–10× slower), or
a `HashMap<Long,Integer>` value→rank (equality only, boxing cost, hackable hash). The sorted-array form is the default.

### 3.2 Event sweep on the real line: union length and maximum overlap, closed vs half-open

Input: $n$ intervals with integer endpoints $l \le r$, viewed as segments of the real line. Output: the length of
their union, the maximum number sharing a point if they are **closed** $[l, r]$, and the same if they are
**half-open** $[l, r)$ (where $[x, x)$ is empty). The type is encoded explicitly because real endpoints cannot be shifted by 1.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<array<long long, 2>> closedEv, halfEv;              // {x, type}
    for (int i = 0; i < n; i++) {
        long long l, r; cin >> l >> r;
        closedEv.push_back({l, 0}); closedEv.push_back({r, 1});    // closed: open(0) sorts before close(1)
        halfEv.push_back({l, 1});   halfEv.push_back({r, 0});      // half-open: close(0) sorts before open(1)
    }
    sort(closedEv.begin(), closedEv.end());
    sort(halfEv.begin(), halfEv.end());
    long long unionLen = 0, prevX = 0; int active = 0, bestClosed = 0, bestHalf = 0;
    for (auto [x, t] : closedEv) {
        if (active > 0) unionLen += x - prevX;                 // [prevX, x) was covered
        prevX = x;
        if (t == 0) bestClosed = max(bestClosed, ++active); else --active;
    }
    active = 0;
    for (auto [x, t] : halfEv) {
        if (t == 1) bestHalf = max(bestHalf, ++active); else --active;
    }
    cout << unionLen << ' ' << bestClosed << ' ' << bestHalf << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long[] L = new long[n], R = new long[n];
        for (int i = 0; i < n; i++) { L[i] = in.nextLong(); R[i] = in.nextLong(); }
        shuffle(L); shuffle(R); Arrays.sort(L); Arrays.sort(R);
        // Merge the sorted starts and ends instead of sorting event objects. Closed: starts win ties.
        long unionLen = 0, prevX = 0; int active = 0, bestClosed = 0, bestHalf = 0;
        for (int i = 0, j = 0; j < n; ) {
            boolean open = i < n && L[i] <= R[j];
            long x = open ? L[i] : R[j];
            if (active > 0) unionLen += x - prevX;
            prevX = x;
            if (open) { bestClosed = Math.max(bestClosed, ++active); i++; } else { active--; j++; }
        }
        active = 0;
        for (int i = 0, j = 0; i < n; ) {                      // half-open: ends win ties (strict <)
            boolean open = j == n || L[i] < R[j];              // j can run ahead when some l == r
            if (open) { bestHalf = Math.max(bestHalf, ++active); i++; } else { active--; j++; }
        }
        out.println(unionLen + " " + bestClosed + " " + bestHalf);
        out.flush();
    }
    static void shuffle(long[] a) {
        Random rnd = new Random();
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
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
2
1 3
3 5
out:
4 2 1
-->
<!-- test
in:
4
0 10
2 4
4 4
8 12
out:
12 3 2
-->
<!-- test
in:
1
-7 -7
out:
0 1 0
-->

Why the Java merge needs no explicit sort of events: starts and ends are each sorted, and the tie rule is just `<=`
(starts first) or `<` (ends first). In the closed loop the ends run out last, because every end is $\ge$ its own start.
In the half-open loop an empty interval $[x, x)$ closes before it opens, so the end pointer can finish first — hence
the `j == n` guard (the third test exercises it).

### 3.3 Sweep plus ordered set: maintaining disjoint covered segments

Online operations "add $[l, r)$" ($l < r$); after each, print the total covered length and the number of maximal
segments (touching segments merge). This is the core of [LC 2276](https://leetcode.com/problems/count-integers-in-intervals/) and [LC 715](https://leetcode.com/problems/range-module/).

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> q;
    map<long long, long long> seg;                             // start -> end, disjoint and non-touching
    long long covered = 0;
    while (q--) {
        long long l, r; cin >> l >> r;
        auto it = seg.upper_bound(l);                          // first segment starting after l
        if (it != seg.begin() && prev(it)->second >= l) --it;  // the one before it overlaps or touches [l, r)
        while (it != seg.end() && it->first <= r) {            // absorb everything that overlaps or touches
            l = min(l, it->first); r = max(r, it->second);
            covered -= it->second - it->first;
            it = seg.erase(it);
        }
        seg[l] = r; covered += r - l;
        cout << covered << ' ' << seg.size() << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int q = in.nextInt();
        TreeMap<Long, Long> seg = new TreeMap<>();
        long covered = 0;
        while (q-- > 0) {
            long l = in.nextLong(), r = in.nextLong();
            Map.Entry<Long, Long> e = seg.floorEntry(l);       // last segment starting at or before l
            if (e != null && e.getValue() >= l) { l = e.getKey(); r = Math.max(r, e.getValue()); covered -= e.getValue() - e.getKey(); seg.remove(e.getKey()); }
            while ((e = seg.ceilingEntry(l)) != null && e.getKey() <= r) {
                r = Math.max(r, e.getValue());
                covered -= e.getValue() - e.getKey();
                seg.remove(e.getKey());
            }
            seg.put(l, r); covered += r - l;
            out.println(covered + " " + seg.size());
        }
        out.flush();
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
5
1 3
5 7
3 5
10 11
0 20
out:
2 1
4 2
6 1
7 2
20 1
-->
<!-- test
in:
1
-1000000000000 1000000000000
out:
2000000000000 1
-->

Amortisation: each `add` erases some segments and inserts one; a segment can be erased only once after its insertion,
so the total number of erasures is at most $q$, and $q$ operations cost $O(q \log q)$.

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| values up to $10^9$/$10^{18}$ but $n \le 2\cdot10^5$, and you want to index by value (BIT over values, counting) | compress: ranks in $[0, n)$ |
| "intervals", "segments", "meetings", "lamps on during $[l, r]$", "at some moment" | events at endpoints, sort, sweep a counter |
| "how many points covered exactly $k$ times", "total length covered" | sweep with elementary intervals, sum $\Delta x$ per state |
| "minimum number of rooms / platforms / colours so overlapping intervals differ" | maximum overlap (and a min-heap if you must output the assignment) |
| many queries "count items with $a \le X$ and $b \le Y$", all known in advance | offline: sort by one key, BIT over the other |
| "number of distinct values in $[l, r]$", offline | sort queries by $r$, mark last occurrences in a BIT |
| "outline", "visible height", "largest active value" | sweep + multiset / heap with lazy deletion |
| "insert intervals, report covered amount", "merge overlapping" online | `map` of disjoint segments |
| "area / perimeter covered by rectangles" | sweep $x$ + cover-count segment tree over compressed $y$ |
| pairs of intervals that intersect / nest | sort by left end, BIT over right ends (or the reverse) |

Often confused with: **difference arrays** (same $+1/-1$ idea, but they need a small coordinate range or
compression first — compression + difference array *is* a sweep); **interval scheduling greedy**
(sort by right end, pick greedily — see [greedy and exchange arguments](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md));
**geometric sweeps** (segment intersection, closest pair — see [geometry sweeps](../14-Geometry/05-sweep-closest-pair-and-half-plane.md)).

## 5. Worked examples (graded)

### Example 1 — Covered Points Count  ·  ★ 1700

- **Source:** [CF 1000C · Covered Points Count](https://codeforces.com/problemset/problem/1000/C) — 1700
- **Difficulty:** 1700
- **Problem:** $n \le 2\cdot10^5$ closed integer segments $[l_i, r_i]$ with $0 \le l_i \le r_i \le 10^{18}$. For every
  $k = 1..n$, output how many integer points are covered by exactly $k$ segments.
- **Thinking from first principles:** A difference array over $[0, 10^{18}]$ is impossible, and compressing
  endpoints alone loses the integer points between them. But coverage is piecewise constant: it only changes at an
  $l_i$ or just after an $r_i$. Convert to half-open $[l_i, r_i + 1)$; then between consecutive event coordinates
  $p < p'$ every one of the $p' - p$ integer points has the same coverage $c$, so add $p' - p$ to $\text{cnt}[c]$.
  No explicit compression is needed — sorting the events *is* the compression.

<details><summary>Solution</summary>

Events $(l_i, +1)$ and $(r_i + 1, -1)$; sort by coordinate. Keep the running coverage `cur`. Before applying event
$i$, the gap $[x_{i-1}, x_i)$ had coverage `cur`, so `cnt[cur] += x_i - x_{i-1}` (zero for equal coordinates, so the
order inside a tie group is irrelevant here). `cnt[0]` collects uncovered gaps and is ignored. $r_i + 1 \le 10^{18}+1$
fits in `long long`. $O(n \log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<pair<long long, int>> ev;
    for (int i = 0; i < n; i++) {
        long long l, r; cin >> l >> r;
        ev.push_back({l, +1}); ev.push_back({r + 1, -1});     // closed [l, r] -> half-open [l, r+1)
    }
    sort(ev.begin(), ev.end());
    vector<long long> cnt(n + 1, 0);
    int cur = 0;
    for (size_t i = 0; i < ev.size(); i++) {
        if (i > 0) cnt[cur] += ev[i].first - ev[i - 1].first;  // gap [x_{i-1}, x_i) has coverage cur
        cur += ev[i].second;
    }
    for (int k = 1; k <= n; k++) cout << cnt[k] << " \n"[k == n];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long[] L = new long[n], R = new long[n];
        for (int i = 0; i < n; i++) { L[i] = in.nextLong(); R[i] = in.nextLong() + 1; }
        shuffle(L); shuffle(R); Arrays.sort(L); Arrays.sort(R);
        long[] cnt = new long[n + 1];
        int cur = 0; long prev = L[0];
        for (int i = 0, j = 0; j < n; ) {                      // merge the two sorted event lists
            boolean open = i < n && L[i] < R[j];
            long x = open ? L[i] : R[j];
            cnt[cur] += x - prev;
            prev = x;
            if (open) { cur++; i++; } else { cur--; j++; }
        }
        StringBuilder sb = new StringBuilder();
        for (int k = 1; k <= n; k++) sb.append(cnt[k]).append(k == n ? '\n' : ' ');
        out.print(sb);
        out.flush();
    }
    static void shuffle(long[] a) {
        Random rnd = new Random();
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
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
2 5
4 9
5 5
out:
6 1 1
-->
<!-- test
in:
2
0 1000000000000000000
0 1000000000000000000
out:
0 1000000000000000001
-->
<!-- test
in:
1
7 7
out:
1
-->
<!-- test
in:
4
1 2
3 4
1 4
10 10
out:
1 4 0 0
-->

</details>

### Example 2 — Rescue Nibel!  ·  ★ 1800

- **Source:** [CF 1420D · Rescue Nibel!](https://codeforces.com/problemset/problem/1420/D) — 1800
- **Difficulty:** 1800
- **Problem:** $n \le 3\cdot10^5$ lamps, lamp $i$ is on during the closed interval $[l_i, r_i]$ ($1 \le l_i \le r_i \le 10^9$).
  Count the $k$-element sets of lamps that are all on at some common moment, modulo $998244353$.
- **Thinking from first principles:** A family of intervals has a common point iff $\max l \le \min r$. Counting sets
  by enumerating their intersection is hopeless, so assign each valid set to a **canonical event**: the start of the
  member with the latest start (ties broken by processing order). At that moment the other $k-1$ members have
  started and not ended, i.e. they are exactly some $k-1$ of the currently active lamps. Conversely, any $k-1$ active
  lamps plus the one starting now share the current moment. So the answer is a sum of binomials taken at open
  events — provided that at equal times, **opens come before closes** (closed intervals: a lamp ending at time $t$
  still shares $t$ with one starting at $t$).

<details><summary>Solution</summary>

Sort starts and ends separately and merge them, taking the start on ties. At a start: `ans += C(active, k-1)`, then
`active++`; at an end: `active--`. Each valid set is counted exactly once (at its canonical start), and every counted
set is valid, so the sum is exact. Binomials from precomputed factorials and inverse factorials (Fermat inverse,
see [modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md)). $O(n \log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 998244353;
long long power(long long b, long long e) { long long r = 1; b %= MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k; cin >> n >> k;
    vector<long long> L(n), R(n);
    for (int i = 0; i < n; i++) cin >> L[i] >> R[i];
    sort(L.begin(), L.end()); sort(R.begin(), R.end());
    vector<long long> f(n + 1, 1), inv(n + 1, 1);
    for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
    inv[n] = power(f[n], MOD - 2);
    for (int i = n; i > 0; i--) inv[i - 1] = inv[i] * i % MOD;
    auto C = [&](int a, int b) { return (b < 0 || a < b) ? 0LL : f[a] * inv[b] % MOD * inv[a - b] % MOD; };
    long long ans = 0; int active = 0;
    for (int i = 0, j = 0; i < n; ) {
        if (L[i] <= R[j]) { ans = (ans + C(active, k - 1)) % MOD; active++; i++; }   // opens win ties
        else { active--; j++; }
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353;
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), k = in.nextInt();
        long[] L = new long[n], R = new long[n];
        for (int i = 0; i < n; i++) { L[i] = in.nextLong(); R[i] = in.nextLong(); }
        shuffle(L); shuffle(R); Arrays.sort(L); Arrays.sort(R);
        long[] f = new long[n + 1], inv = new long[n + 1];
        f[0] = 1;
        for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
        inv[n] = power(f[n], MOD - 2);
        for (int i = n; i > 0; i--) inv[i - 1] = inv[i] * i % MOD;
        long ans = 0; int active = 0;
        for (int i = 0, j = 0; i < n; ) {
            if (L[i] <= R[j]) {
                if (active >= k - 1) ans = (ans + f[active] * inv[k - 1] % MOD * inv[active - k + 1]) % MOD;
                active++; i++;
            } else { active--; j++; }
        }
        out.println(ans);
        out.flush();
    }
    static long power(long b, long e) { long r = 1; b %= MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    static void shuffle(long[] a) {
        Random rnd = new Random();
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
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
4 2
1 3
3 5
6 7
2 6
out:
4
-->
<!-- test
in:
3 3
5 5
5 5
5 5
out:
1
-->
<!-- test
in:
1 1
1 1000000000
out:
1
-->
<!-- test
in:
3 2
1 2
3 4
5 6
out:
0
-->

</details>

### Example 3 — Distinct Values Queries  ·  ★ ≈1900 (est.)

- **Source:** [CSES 1734 · Distinct Values Queries](https://cses.fi/problemset/task/1734)
- **Difficulty:** ≈1900 (est.)
- **Problem:** An array of $n \le 2\cdot10^5$ values up to $10^9$ and $q \le 2\cdot10^5$ queries $[a, b]$ (1-based):
  how many distinct values does $x[a..b]$ contain?
- **Thinking from first principles:** Online, this needs a persistent or merge-sort tree. But the queries are known
  in advance. Fix the right end $b$ and ask which positions should "represent" each value: if every value is
  represented only by its **last occurrence at or before $b$**, then a value appears in $[a, b]$ iff its representative
  is $\ge a$. Moving $b$ one step right changes one representative: unmark the previous occurrence of $x_b$, mark $b$.
  A Fenwick tree counts marks in $[a, b]$. The value range needs compression so that "previous occurrence" can be an
  array indexed by rank instead of a hash map.

<details><summary>Solution</summary>

Compress values. Bucket queries by right end (a counting sort: linked lists `head[b]`, `nxt[query]`). Sweep
$b = 1..n$: if `last[x_b]` exists, add $-1$ there; add $+1$ at $b$; set `last[x_b] = b`; answer every query with right
end $b$ as `sum(b) - sum(a-1)`. Correctness is the invariant "after step $b$, position $p \le b$ is marked iff $p$ is the
last occurrence of $x_p$ in $[1, b]$". $O((n + q) \log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<long long> x(n + 1);
    for (int i = 1; i <= n; i++) cin >> x[i];
    vector<long long> xs(x.begin() + 1, x.end());
    sort(xs.begin(), xs.end()); xs.erase(unique(xs.begin(), xs.end()), xs.end());
    vector<int> c(n + 1);
    for (int i = 1; i <= n; i++) c[i] = lower_bound(xs.begin(), xs.end(), x[i]) - xs.begin();
    vector<int> qa(q), head(n + 1, -1), nxt(q);
    for (int i = 0; i < q; i++) { int a, b; cin >> a >> b; qa[i] = a; nxt[i] = head[b]; head[b] = i; }   // bucket by b
    vector<int> bit(n + 1, 0), last(xs.size(), 0), ans(q);
    auto add = [&](int p, int v) { for (; p <= n; p += p & -p) bit[p] += v; };
    auto sum = [&](int p) { int s = 0; for (; p > 0; p -= p & -p) s += bit[p]; return s; };
    for (int b = 1; b <= n; b++) {
        if (last[c[b]]) add(last[c[b]], -1);                   // the old representative of this value retires
        add(b, +1); last[c[b]] = b;
        for (int i = head[b]; i != -1; i = nxt[i]) ans[i] = sum(b) - sum(qa[i] - 1);
    }
    for (int i = 0; i < q; i++) cout << ans[i] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        long[] x = new long[n + 1];
        for (int i = 1; i <= n; i++) x[i] = in.nextLong();
        long[] xs = Arrays.copyOfRange(x, 1, n + 1);
        shuffle(xs); Arrays.sort(xs);
        int k = 0;
        for (int i = 0; i < n; i++) if (k == 0 || xs[i] != xs[k - 1]) xs[k++] = xs[i];
        int[] c = new int[n + 1];
        for (int i = 1; i <= n; i++) c[i] = Arrays.binarySearch(xs, 0, k, x[i]);   // always a hit
        int[] qa = new int[q], head = new int[n + 1], nxt = new int[q], ans = new int[q];
        Arrays.fill(head, -1);
        for (int i = 0; i < q; i++) { int a = in.nextInt(), b = in.nextInt(); qa[i] = a; nxt[i] = head[b]; head[b] = i; }
        int[] bit = new int[n + 1], last = new int[k];
        for (int b = 1; b <= n; b++) {
            if (last[c[b]] != 0) add(bit, last[c[b]], -1);
            add(bit, b, 1); last[c[b]] = b;
            for (int i = head[b]; i != -1; i = nxt[i]) ans[i] = sum(bit, b) - sum(bit, qa[i] - 1);
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < q; i++) sb.append(ans[i]).append('\n');
        out.print(sb);
        out.flush();
    }
    static void add(int[] bit, int p, int v) { for (; p < bit.length; p += p & -p) bit[p] += v; }
    static int sum(int[] bit, int p) { int s = 0; for (; p > 0; p -= p & -p) s += bit[p]; return s; }
    static void shuffle(long[] a) {
        Random rnd = new Random();
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
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
6 4
5 1000000000 5 7 1000000000 5
1 6
2 4
3 3
4 6
out:
3
3
1
3
-->
<!-- test
in:
1 1
9
1 1
out:
1
-->
<!-- test
in:
5 3
2 2 2 2 2
1 5
2 3
5 5
out:
1
1
1
-->

</details>

### Example 4 — The skyline (sweep + multiset)  ·  ★ ≈1900 (est.)

- **Source:** [LC 218 · The Skyline Problem](https://leetcode.com/problems/the-skyline-problem/) — Hard (stdin/stdout format below is ours)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n \le 10^5$ buildings, building $i$ occupies $[l_i, r_i)$ with height $h_i > 0$ ($l_i < r_i$). Output the
  skyline as key points: every $x$ where the outline height (maximum height over buildings containing $x$, or 0)
  changes, with the new height. Print the number of key points, then one `x h` per line.
- **Thinking from first principles:** The outline height at $x$ depends only on the multiset of heights of buildings
  that contain $x$ — the active set. It can change only at some $l_i$ or $r_i$. So group events by coordinate, apply
  all of them, read the maximum, and emit a key point if it differs from the last height. Grouping is what makes ties
  harmless here: a building ending at $x$ and another starting at $x$ are both applied before the maximum is read
  (half-open intervals). Reading the maximum after each individual event instead would emit spurious points.

<details><summary>Solution</summary>

C++ keeps a `multiset<int>` of active heights. Java keeps a `TreeMap<Integer,Integer>` height → multiplicity and
merges the starts (sorted by $l$) with the ends (sorted by $r$) instead of sorting event objects. Each event costs
$O(\log n)$: $O(n \log n)$. Correctness: after processing the group at $x$, the active multiset is exactly the
buildings with $l \le x < r$, so its maximum is the outline on $[x, \text{next event})$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<pair<long long, int>> ev;                           // {x, +h for start, -h for end}
    for (int i = 0; i < n; i++) {
        long long l, r; int h; cin >> l >> r >> h;
        ev.push_back({l, h}); ev.push_back({r, -h});
    }
    sort(ev.begin(), ev.end());
    multiset<int> active;
    vector<pair<long long, int>> key;
    int last = 0;
    for (size_t i = 0; i < ev.size(); ) {
        long long x = ev[i].first;
        for (; i < ev.size() && ev[i].first == x; i++) {       // apply the whole group at x
            if (ev[i].second > 0) active.insert(ev[i].second);
            else active.erase(active.find(-ev[i].second));     // erase one copy, not all equal heights
        }
        int cur = active.empty() ? 0 : *active.rbegin();
        if (cur != last) { key.push_back({x, cur}); last = cur; }
    }
    cout << key.size() << '\n';
    for (auto [x, h] : key) cout << x << ' ' << h << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long[] l = new long[n], r = new long[n]; int[] h = new int[n];
        for (int i = 0; i < n; i++) { l[i] = in.nextLong(); r[i] = in.nextLong(); h[i] = in.nextInt(); }
        long[] byL = new long[n], byR = new long[n];           // (coordinate << 20) | index, sorted as primitives
        for (int i = 0; i < n; i++) { byL[i] = (l[i] << 20) | i; byR[i] = (r[i] << 20) | i; }
        shuffle(byL); shuffle(byR); Arrays.sort(byL); Arrays.sort(byR);
        TreeMap<Integer, Integer> active = new TreeMap<>();
        StringBuilder sb = new StringBuilder();
        int last = 0, cnt = 0;
        for (int i = 0, j = 0; j < n; ) {
            long x = Math.min(i < n ? byL[i] >> 20 : Long.MAX_VALUE, byR[j] >> 20);
            while (i < n && (byL[i] >> 20) == x) { int id = (int) (byL[i] & 0xFFFFF); active.merge(h[id], 1, Integer::sum); i++; }
            while (j < n && (byR[j] >> 20) == x) {
                int id = (int) (byR[j] & 0xFFFFF);
                if (active.merge(h[id], -1, Integer::sum) == 0) active.remove(h[id]);
                j++;
            }
            int cur = active.isEmpty() ? 0 : active.lastKey();
            if (cur != last) { sb.append(x).append(' ').append(cur).append('\n'); cnt++; last = cur; }
        }
        out.print(cnt + "\n" + sb);
        out.flush();
    }
    static void shuffle(long[] a) {
        Random rnd = new Random();
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
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

The Java packing `(x << 20) | index` needs $0 \le x < 2^{43}$ and $n \le 2^{20}$; for negative coordinates add an
offset first.

<!-- test
in:
3
1 5 3
2 4 6
5 8 3
out:
4
1 3
2 6
4 3
8 0
-->
<!-- test
in:
2
0 3 2
3 6 2
out:
2
0 2
6 0
-->
<!-- test
in:
3
0 10 5
0 10 5
4 6 5
out:
2
0 5
10 0
-->
<!-- test
in:
1
1000000000 2000000000 7
out:
2
1000000000 7
2000000000 0
-->

</details>

### Example 5 — Area of Rectangles  ·  ★ ≈2100 (est.)

- **Source:** [CSES 1741 · Area of Rectangles](https://cses.fi/problemset/task/1741)
- **Difficulty:** ≈2100 (est.)
- **Problem:** $n \le 10^5$ axis-parallel rectangles with corners $(x_1, y_1), (x_2, y_2)$, $-10^6 \le x_1 < x_2 \le 10^6$,
  same for $y$. Output the area of their union.
- **Thinking from first principles:** Inclusion–exclusion over intersections is exponential. A compressed grid is
  $O(n^2)$ cells — $10^{10}$, too many. Sweep $x$: the union's cross-section at $x$ is the union of the active
  $y$-intervals, and its length $L$ only changes at rectangle edges, so area $= \sum L \cdot \Delta x$. What remains is a
  data structure for "add / remove a $y$-interval, report covered length": the cover-count segment tree of §1.6.
  The $O(n^2)$ version (recount $L$ over all elementary $y$-gaps after each event) is the brute force used to
  stress-test this one.

<details><summary>Solution</summary>

Compress the $2n$ $y$-coordinates to $k$ values; leaves are the $k-1$ elementary gaps. Sort the $2n$ events by $x$
(ties in any order: $\Delta x = 0$ between them, and `cnt` cannot go negative because a rectangle is always added at a
strictly smaller $x$ than it is removed). Before each event add `len[root] * (x - prevX)`. $O(n \log n)$; the area is at
most $4\cdot10^{12}$, so `long long`.

```cpp
#include <bits/stdc++.h>
using namespace std;
vector<long long> ys, len;
vector<int> cnt;
void update(int node, int l, int r, int ql, int qr, int v) {
    if (qr < l || r < ql) return;
    if (ql <= l && r <= qr) cnt[node] += v;                     // canonical node: count it, do not recurse
    else {
        int mid = (l + r) / 2;
        update(2 * node, l, mid, ql, qr, v);
        update(2 * node + 1, mid + 1, r, ql, qr, v);
    }
    if (cnt[node] > 0) len[node] = ys[r + 1] - ys[l];          // fully covered
    else if (l == r) len[node] = 0;
    else len[node] = len[2 * node] + len[2 * node + 1];        // children are exact: no push-down needed
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<array<long long, 4>> ev;                            // {x, y1, y2, delta}
    for (int i = 0; i < n; i++) {
        long long x1, y1, x2, y2; cin >> x1 >> y1 >> x2 >> y2;
        ev.push_back({x1, y1, y2, 1}); ev.push_back({x2, y1, y2, -1});
        ys.push_back(y1); ys.push_back(y2);
    }
    sort(ys.begin(), ys.end()); ys.erase(unique(ys.begin(), ys.end()), ys.end());
    int m = ys.size() - 1;                                     // number of elementary y-gaps (>= 1)
    cnt.assign(4 * m, 0); len.assign(4 * m, 0);
    sort(ev.begin(), ev.end());
    long long area = 0;
    for (size_t i = 0; i < ev.size(); i++) {
        if (i > 0) area += len[1] * (ev[i][0] - ev[i - 1][0]);
        int ql = lower_bound(ys.begin(), ys.end(), ev[i][1]) - ys.begin();
        int qr = lower_bound(ys.begin(), ys.end(), ev[i][2]) - ys.begin() - 1;   // gaps ql..qr cover [y1, y2)
        update(1, 0, m - 1, ql, qr, (int)ev[i][3]);
    }
    cout << area << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] ys, len;
    static int[] cnt;
    static void update(int node, int l, int r, int ql, int qr, int v) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) cnt[node] += v;
        else {
            int mid = (l + r) / 2;
            update(2 * node, l, mid, ql, qr, v);
            update(2 * node + 1, mid + 1, r, ql, qr, v);
        }
        if (cnt[node] > 0) len[node] = ys[r + 1] - ys[l];
        else if (l == r) len[node] = 0;
        else len[node] = len[2 * node] + len[2 * node + 1];
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long[] x1 = new long[n], y1 = new long[n], x2 = new long[n], y2 = new long[n];
        long[] all = new long[2 * n];
        for (int i = 0; i < n; i++) {
            x1[i] = in.nextLong(); y1[i] = in.nextLong(); x2[i] = in.nextLong(); y2[i] = in.nextLong();
            all[2 * i] = y1[i]; all[2 * i + 1] = y2[i];
        }
        shuffle(all); Arrays.sort(all);
        int k = 0;
        for (int i = 0; i < 2 * n; i++) if (k == 0 || all[i] != all[k - 1]) all[k++] = all[i];
        ys = Arrays.copyOf(all, k);
        int m = k - 1;
        cnt = new int[4 * m]; len = new long[4 * m];
        long OFF = 1_000_000, E = 2L * n;                      // event key = (x + OFF) * 2n + id: sort primitives
        long[] key = new long[2 * n];
        for (int i = 0; i < n; i++) { key[2 * i] = (x1[i] + OFF) * E + 2 * i; key[2 * i + 1] = (x2[i] + OFF) * E + 2 * i + 1; }
        shuffle(key); Arrays.sort(key);
        long area = 0, prevX = 0;
        for (int t = 0; t < 2 * n; t++) {
            long x = key[t] / E - OFF; int id = (int) (key[t] % E), r = id / 2;
            if (t > 0) area += len[1] * (x - prevX);
            prevX = x;
            int ql = Arrays.binarySearch(ys, y1[r]), qr = Arrays.binarySearch(ys, y2[r]) - 1;
            update(1, 0, m - 1, ql, qr, id % 2 == 0 ? 1 : -1);
        }
        out.println(area);
        out.flush();
    }
    static void shuffle(long[] a) {
        Random rnd = new Random();
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
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
2
0 0 4 4
2 2 6 6
out:
28
-->
<!-- test
in:
3
-1000000 -1000000 1000000 1000000
0 0 1 1
-5 -5 5 5
out:
4000000000000
-->
<!-- test
in:
3
0 0 2 1
2 0 4 1
1 -3 3 0
out:
10
-->
<!-- test
in:
1
3 -2 4 7
out:
9
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Decide closed vs half-open first, then the tie order.** Convert closed integer intervals to $[l, r+1)$ and use
   "closes before opens" everywhere; sorting `pair(x, delta)` with $\delta \in \{-1, +1\}$ does it for free. For real
   closed intervals encode the type and sort opens first. Wrong tie order is the number-one WA in sweeps.
2. **$r+1$ must be compressed too.** If you compress endpoints and then use $r+1$ as an event, `lower_bound(r+1)` lands
   on the next existing coordinate and silently merges gaps. Insert $r+1$ into the coordinate list.
3. **Ranks lose distances.** Keep `xs` and multiply by `xs[i+1] - xs[i]` whenever the answer is a length or count of
   integer points.
4. **Querying an absent value.** `lower_bound` gives "first $\ge v$"; for "last $\le v$" use `upper_bound - 1` and check for
   $-1$. Java's `Arrays.binarySearch` returns `-(insertion point) - 1` on a miss and an *arbitrary* index among
   duplicates — dedupe before using it.
5. **Java sorting.** `Arrays.sort(long[])`/`int[]` is a dual-pivot quicksort that can be driven to $O(n^2)$ by crafted
   tests: shuffle first. Avoid sorting `long[][]`/objects with comparators in hot paths; pack `(key, index)` into one
   `long` (Examples 4, 5) or merge two sorted primitive arrays (Examples 1, 2).
6. **`multiset::erase(value)` erases every copy.** Use `erase(find(value))`. Java's `TreeSet` cannot hold duplicates — use a
   `TreeMap<value, count>`.
7. **Read the state after the whole event group**, unless you have proved that no intermediate state exceeds the
   true one. The maximum-overlap scan of §3.2 reads after each open; that is safe because, with the tie order matching
   the interval type, the counts inside a group only rise towards the true count at $x$ (closed: opens first, so
   intermediate counts are partial; half-open: closes first, then opens). The skyline (Example 4) has no such
   guarantee, so it reads only after the group.
8. **Offline order must be restored.** Store each query's index and write answers into `ans[idx]`. Bucketing queries by
   right end (`head`/`nxt` arrays) is a linear-time counting sort and avoids sorting objects in Java.
9. **Overflow.** Lengths times counts and areas exceed 32 bits quickly ($2\cdot10^6 \times 2\cdot10^6 = 4\cdot10^{12}$); events at
   $r+1$ with $r = 10^{18}$ are still below $2^{63}$, but $r+1$ with $r = 2^{63}-1$ is not.
10. **Segment tree size for elementary gaps.** With $k$ distinct coordinates there are $k-1$ leaves; a node covering
    leaves $l..r$ spans $[y_l, y_{r+1})$. Allocating for $k$ leaves and indexing `ys[r+1]` at the last leaf reads past the end.
11. **Recursion in Java segment trees** is only $O(\log n)$ deep — fine. Recursion on the sweep itself (rare) is not.

## 7. Going further (toward 2400–2600+)

- **Perimeter of a union of rectangles:** the same sweep, but each node also tracks how many disjoint covered pieces
  it contains (with flags for "left end covered" and "right end covered"); vertical perimeter $= \sum 2 \cdot \text{pieces}
  \cdot \Delta x$, horizontal perimeter $= \sum |L_{\text{new}} - L_{\text{old}}|$.
- **Counting intersections of horizontal and vertical segments** ([CSES 1740 · Intersection Points](https://cses.fi/problemset/task/1740)):
  sweep $x$, horizontal segments are $\pm1$ events at their endpoints in a BIT over $y$, a vertical segment is a range-count query.
- **3D dominance / nested intervals:** sort by one coordinate, sweep, BIT over the second, and a third dimension
  needs CDQ divide and conquer ([offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md)).
- **Online versions** of offline sweeps need persistence: a persistent segment tree answers "distinct values in $[l, r]$"
  online ([persistent data structures](../08-Data-Structures/08-persistent-data-structures.md)).
- **Segment tree on the sweep with range assign/min** ("for each point, the best active interval") and **segment
  tree beats** for sweeps with chmin updates ([advanced segment trees](../08-Data-Structures/04-segment-tree-advanced-descent-merging-beats.md)).
- **Angular sweeps** (rotate a ray around a point, events at angles) and the Bentley–Ottmann segment-intersection
  sweep belong to [geometry](../14-Geometry/05-sweep-closest-pair-and-half-plane.md).
- **Sweep over time with deletions** ("which intervals are alive when") becomes the segment tree on time with DSU
  rollback ([segment tree on time](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md)).

## 8. Practice ladder

**≤ 1400**
- [ ] [AtCoder ABC213 C · Reorder Cards](https://atcoder.jp/contests/abc213/tasks/abc213_c) — compress rows and columns independently
- [ ] [AtCoder ABC188 D · Snuke Prime](https://atcoder.jp/contests/abc188/tasks/abc188_d) — events with costs, multiply by gap lengths
- [ ] [CSES 1619 · Restaurant Customers](https://cses.fi/problemset/task/1619) — maximum overlap

**1400–1700**
- [ ] [CF 1029C · Maximal Intersection](https://codeforces.com/problemset/problem/1029/C) — 1600
- [ ] [CSES 1164 · Room Allocation](https://cses.fi/problemset/task/1164) — rooms = overlap, assignment with a min-heap
- [ ] [CSES 1163 · Traffic Lights](https://cses.fi/problemset/task/1163) — set of cut points + multiset of gaps

**1700–1900**
- [ ] [CF 652D · Nested Segments](https://codeforces.com/problemset/problem/652/D) — 1800
- [ ] [CF 1462F · The Treasure of The Segments](https://codeforces.com/problemset/problem/1462/F) — 1800
- [ ] [CF 1859D · Andrey and Escape from Capygrad](https://codeforces.com/problemset/problem/1859/D) — 1800
- [ ] [CSES 2169 · Nested Ranges Count](https://cses.fi/problemset/task/2169) — sort by left end, BIT over right ends
- [ ] [CSES 1144 · Salary Queries](https://cses.fi/problemset/task/1144) — offline compression of values and queries
- [ ] [AtCoder ABC128 E · Roadwork](https://atcoder.jp/contests/abc128/tasks/abc128_e) — events in shifted time + ordered set

**1900–2100**
- [ ] [CF 1311F · Moving Points](https://codeforces.com/problemset/problem/1311/F) — 1900
- [ ] [CF 61E · Enemy is weak](https://codeforces.com/problemset/problem/61/E) — 1900
- [ ] [CF 863E · Turn Off The TV](https://codeforces.com/problemset/problem/863/E) — 2000
- [ ] [CF 689E · Mike and Geometry Problem](https://codeforces.com/problemset/problem/689/E) — 2000
- [ ] [CF 1690G · Count the Trains](https://codeforces.com/problemset/problem/1690/G) — 2000
- [ ] [CSES 1740 · Intersection Points](https://cses.fi/problemset/task/1740) — sweep + BIT range counts

**2100–2400**
- [ ] [CF 1284D · New Year and Conference](https://codeforces.com/problemset/problem/1284/D) — 2100
- [ ] [CF 1418D · Trash Problem](https://codeforces.com/problemset/problem/1418/D) — 2100
- [ ] [CF 1194E · Count The Rectangles](https://codeforces.com/problemset/problem/1194/E) — 2200
- [ ] [CF 915E · Physical Education Lessons](https://codeforces.com/problemset/problem/915/E) — 2300
- [ ] [CF 610D · Vika and Segments](https://codeforces.com/problemset/problem/610/D) — 2300
- [ ] [CF 1401E · Divide Square](https://codeforces.com/problemset/problem/1401/E) — 2400
- [ ] [CF 12D · Ball](https://codeforces.com/problemset/problem/12/D) — 2400

## 9. LeetCode / FAANG cross-reference

Interval sweeps are a staple of interviews (meeting rooms, calendars, merging); compression + BIT appears in the
"count smaller after self" family. See also [greedy and intervals](../17-FAANG-Interview-DSA/15-greedy-and-intervals.md).

- [LC 56 · Merge Intervals](https://leetcode.com/problems/merge-intervals/) — Medium — sort by start, extend the current segment while starts $\le$ its end.
- [LC 57 · Insert Interval](https://leetcode.com/problems/insert-interval/) — Medium — one step of the §3.3 disjoint-segment insertion.
- [LC 253 · Meeting Rooms II](https://leetcode.com/problems/meeting-rooms-ii/) — Medium 🔒 — maximum overlap with half-open ties.
- [LC 1094 · Car Pooling](https://leetcode.com/problems/car-pooling/) — Medium — weighted $\pm$ events, check the running sum.
- [LC 2406 · Divide Intervals Into Minimum Number of Groups](https://leetcode.com/problems/divide-intervals-into-minimum-number-of-groups/) — Medium — closed intervals: opens before closes.
- [LC 732 · My Calendar III](https://leetcode.com/problems/my-calendar-iii/) — Hard — online maximum overlap with an ordered map of deltas.
- [LC 2251 · Number of Flowers in Full Bloom](https://leetcode.com/problems/number-of-flowers-in-full-bloom/) — Hard — offline queries: #starts $\le t$ minus #ends $< t$ by binary search.
- [LC 1851 · Minimum Interval to Include Each Query](https://leetcode.com/problems/minimum-interval-to-include-each-query/) — Hard — sort queries, sweep, heap with lazy deletion.
- [LC 218 · The Skyline Problem](https://leetcode.com/problems/the-skyline-problem/) — Hard — Example 4.
- [LC 850 · Rectangle Area II](https://leetcode.com/problems/rectangle-area-ii/) — Hard — Example 5 (modulo $10^9+7$).
- [LC 2276 · Count Integers in Intervals](https://leetcode.com/problems/count-integers-in-intervals/) — Hard — §3.3 with closed intervals.
- [LC 715 · Range Module](https://leetcode.com/problems/range-module/) — Hard — §3.3 plus removal (split segments at the boundaries).
- [LC 315 · Count of Smaller Numbers After Self](https://leetcode.com/problems/count-of-smaller-numbers-after-self/) — Hard — compress values, sweep right to left, BIT.
- [LC 493 · Reverse Pairs](https://leetcode.com/problems/reverse-pairs/) — Hard — compress $\{a_i\} \cup \{2a_i\}$, BIT.
- [LC 759 · Employee Free Time](https://leetcode.com/problems/employee-free-time/) — Hard 🔒 — union of all intervals, output the gaps.

## 10. Self-check

1. Why is replacing values by their ranks safe for an algorithm that only compares values, and what two kinds of
   algorithms break this?
2. Meetings $[1, 3]$ and $[3, 5]$ need 1 room in one reading of the statement and 2 in the other. Which event order
   gives each, and what single convention avoids thinking about it?
3. You compressed segment endpoints and used `lower_bound(r + 1)` for the end event. What goes wrong?
4. Prove that the minimum number of rooms equals the maximum overlap.
5. In "distinct values in $[l, r]$", why is it enough to mark only the last occurrence of each value, and why must the
   queries be sorted by $r$ (not $l$)?
6. In the rectangle-union segment tree, why is no lazy push-down needed, and what does a node with `cnt = 0` report?
7. A skyline implementation reads the maximum after every single event. Give a two-building input where it emits a
   wrong key point.
8. What does Java's `Arrays.binarySearch` return for a value that is absent, and for a value that appears three times?

<details><summary>Answers</summary>

1. A strictly increasing map preserves every comparison result, so the algorithm takes the same branches. It breaks
   when actual **distances** matter (lengths, areas, counts of integer points — keep `xs` to recover them) and when
   **arithmetic** on values matters (sums, $a_i + a_j = T$, $2a_i$), unless the derived values are compressed too.
2. Closed: opens before closes gives 2. Half-open: closes before opens gives 1. Convert everything to half-open
   ($[l, r] \to [l, r+1)$ for integers) and always process closes first, e.g. by sorting `(x, delta)` pairs.
3. If $r+1$ is not itself a compressed coordinate, `lower_bound` returns the next larger coordinate, so the interval is
   treated as covering every point up to it — gaps are merged and counts are wrong. Insert $r+1$ into the list.
4. Lower bound: the meetings containing the point of maximum overlap pairwise conflict. Upper bound: greedy by start
   time reusing any free room; needing a new room beyond $c$ would mean $c+1$ meetings contain the current start, a
   contradiction.
5. A value occurs in $[l, r]$ iff some occurrence lies in it iff its last occurrence $\le r$ is $\ge l$; one mark per
   value makes the count of marks in $[l, r]$ the number of distinct values. "Last occurrence $\le r$" depends on $r$,
   so the marks are valid for one $r$ at a time and the sweep must go in increasing $r$.
6. Every removal is applied to exactly the canonical nodes of its earlier insertion, so `cnt` is never negative and
   never needs to be distributed to children. A node with `cnt = 0` reports the sum of its children's covered lengths
   (or 0 for a leaf) — exactly the coverage from rectangles counted strictly below it.
7. Buildings $[0, 3)$ and $[3, 6)$, both height 2. Processing the end at 3 before the start at 3 and reading in between
   emits $(3, 0)$ and then $(3, 2)$; the correct skyline is $(0, 2), (6, 0)$.
8. Absent: `-(insertion point) - 1`, always negative. Present three times: the index of **some** copy — not necessarily
   the first — so it cannot be used as `lower_bound` without deduplicating.

</details>
