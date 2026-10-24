# Fenwick Tree (Binary Indexed Tree)

> **Band:** 🔵 1500–1900 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [prefix sums and difference arrays](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md), [bit manipulation](../01-Foundations/03-bit-manipulation.md), [coordinate compression](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md)
> **You can say you know this when:** you can write a BIT from memory in both languages in two minutes, derive the two-BIT range-add/range-sum formula on paper, and find the k-th smallest element of a dynamic multiset in $O(\log n)$ by descending the BIT instead of binary searching over it.

## 1. First principles — why this works

**The problem.** An array $a[1..n]$ receives two kinds of operations: *add $v$ to $a_p$* and *report $a_1 + \dots + a_i$*.
The two obvious representations sit at opposite extremes:

| Store | Update | Prefix query |
|---|---|---|
| the raw array $a$ | $O(1)$ | $O(n)$ |
| the prefix array $P_i = a_1 + \dots + a_i$ | $O(n)$ (every $P_j$, $j \ge p$, changes) | $O(1)$ |

With $n, q = 2\cdot 10^5$ both are $4\cdot 10^{10}$ in the worst case. The waste is symmetric: the raw array makes a query touch
$n$ cells, the prefix array makes an update touch $n$ cells. We want a set of stored partial sums such that **every prefix is a
union of few stored blocks** and **every position lies in few stored blocks**.

**The key observation: binary representation decomposes a prefix.** Write $i$ in binary, e.g. $i = 13 = 1101_2 = 8 + 4 + 1$.
Then $[1, 13] = [1, 8] \cup [9, 12] \cup [13, 13]$: block lengths are the set bits of $i$, taken from the highest.
Read the same decomposition from the *right end*: the last block ends at 13 and has length $1$ (the lowest set bit of 13);
the next ends at $13 - 1 = 12$ and has length $4$ (lowest set bit of 12); the next ends at $12 - 4 = 8$ and has length $8$.
So if we store, for every $j$,

$$t[j] = \sum_{k = j - \mathrm{low}(j) + 1}^{j} a_k, \qquad \mathrm{low}(j) = \text{value of the lowest set bit of } j,$$

then $\text{prefix}(i) = t[i] + \text{prefix}(i - \mathrm{low}(i))$, and the recursion stops after $\mathrm{popcount}(i) \le \lfloor\log_2 n\rfloor + 1$ steps
because each step clears one set bit. That is the whole query.

**Why `i & -i` is the lowest set bit.** In two's complement, $-i = \lnot i + 1$. Let $i = x\,1\,\underbrace{0\cdots0}_{k}$ in binary.
Then $\lnot i = \bar x\,0\,\underbrace{1\cdots1}_{k}$ and adding 1 carries through the $k$ ones: $-i = \bar x\,1\,\underbrace{0\cdots0}_{k}$.
ANDing with $i$ kills $x$ against $\bar x$, keeps the single 1 at position $k$, and the zeros below: `i & -i` $= 2^k$.
Two related identities: `i & (i - 1)` clears the lowest set bit (so `i -= i & -i` is the same as `i &= i - 1`),
and `i | (i - 1)` sets all bits below it.

**Which stored blocks contain position $p$? (the update).** Let $j$ have lowest set bit $2^k$, so $j = H\cdot 2^{k+1} + 2^k$ for some $H$.
Its block is $(H\cdot 2^{k+1},\ H\cdot 2^{k+1} + 2^k]$, i.e. exactly the $m$ for which $m - 1$ has high part $H$ above bit $k$ **and bit $k$ of $m-1$ equal to 0**.
So $t[j]$ contains $p$ iff $j-1$ and $p-1$ agree above bit $k$ and bit $k$ of $p - 1$ is 0. Consequently:

- for each zero bit $k$ of $p - 1$ there is exactly one covering block, and there are no others, so **at most $\lfloor\log_2 n\rfloor + 1$ blocks contain $p$**;
- the smallest is $j = p$ itself ($k$ = number of trailing ones of $p-1$ = trailing zeros of $p$), and $j \mapsto j + \mathrm{low}(j)$
  moves to the block for the *next* zero bit of $p - 1$ (the carry turns the run of ones into zeros and sets the next bit).

Hence `for (j = p; j <= n; j += j & -j) t[j] += v;` touches every block containing $p$ and nothing else, in $O(\log n)$.

**What the structure needs from the operation.** A prefix query only combines blocks, so any associative operation works for
*prefixes* (sum, xor, product mod $p$, max *if values only increase*). To get a **range** $[l, r]$ you subtract `prefix(l-1)`,
which needs an inverse: sum and xor are fine (groups), min/max are not. For range min/max with arbitrary updates use a
[segment tree](02-segment-tree-basics.md).

**Range update instead of point update.** If updates are "add $v$ to $a_l..a_r$" and queries are "value of $a_i$", store the
difference array $d_i = a_i - a_{i-1}$ in the BIT: a range add is two point adds ($d_l \mathrel{+}= v$, $d_{r+1} \mathrel{-}= v$) and $a_i = \sum_{j\le i} d_j$ is a prefix query.

**Range update and range query — derive the two-BIT trick.** Keep $d$ as above. The prefix sum of $a$ is

$$S(x) = \sum_{i=1}^{x} a_i = \sum_{i=1}^{x}\sum_{j=1}^{i} d_j = \sum_{j=1}^{x} d_j\,(x - j + 1) = (x+1)\sum_{j=1}^{x} d_j \;-\; \sum_{j=1}^{x} j\,d_j .$$

Both sums are prefix sums of point-updated arrays ($d_j$ and $j\,d_j$), so two BITs suffice. A range add $v$ on $[l, r]$ changes
$d_l$ by $+v$ and $d_{r+1}$ by $-v$, i.e. $B_1$ gets $+v$ at $l$, $-v$ at $r+1$, and $B_2$ gets $+l\,v$ at $l$, $-(r+1)\,v$ at $r+1$.

**Order statistics without binary search.** Store counts: $t$ over $c[v]$ = how many copies of value $v$ are in the multiset.
"k-th smallest" = smallest $p$ with $\text{prefix}(p) \ge k$. A binary search over $p$ costs $O(\log^2 n)$, but the BIT's
layout lets us do it in one descent: keep `pos` (initially 0) and try steps $2^{\lfloor \log n \rfloor}, \dots, 2, 1$.
Invariant: before trying step $s$, `pos` is a multiple of $2s$, so $\mathrm{low}(pos + s) = s$ and $t[pos+s]$ is *exactly*
$c[pos+1] + \dots + c[pos+s]$. If that is $< k$, the answer lies beyond `pos + s`: jump and subtract. Otherwise stay.
After the loop `pos` is the largest index with prefix $< k$, so the answer is `pos + 1`. $O(\log n)$, no division, no recursion.

**Offline counting of distinct values in ranges.** Queries "how many distinct values in $a[l..r]$" do not decompose (distinct
count of a union is not a function of the parts). Fix the right end $r$: if we mark, for every value, only its **last
occurrence at or before $r$**, then each value present in $a[l..r]$ has exactly one mark in $[l, r]$ and each value absent from
it has none. So the answer is the number of marks in $[l, r]$ — a BIT range sum. Sort queries by $r$; when $r$ advances to
$i$, unmark the previous occurrence of $a_i$ and mark $i$. Total $O((n + q)\log n)$. The same "sort by right end, keep only
the most recent representative" idea powers many offline problems (range xor of distinct values, range "unique" queries).

**Inversions and dominance counting.** Counting pairs $i < j$ with $a_i > a_j$ is "for each $j$, how many earlier values exceed
$a_j$": sweep $j$ left to right, query the BIT over values, then insert $a_j$. Every 2D dominance count ("pairs with
$x_i < x_j$ and $y_i > y_j$") is the same: sort by one coordinate, BIT over the other (compressed).

## 2. Formulas, definitions and identities

| Formula | Meaning |
|---|---|
| $\mathrm{low}(i) = i \,\&\, (-i)$ | value of the lowest set bit (two's-complement derivation above) |
| $i \,\&\, (i-1) = i - \mathrm{low}(i)$ | clear the lowest set bit — the query step |
| $t[i] = \sum_{k=i-\mathrm{low}(i)+1}^{i} a_k$ | what node $i$ stores |
| $\text{prefix}(i) = t[i] + \text{prefix}(i - \mathrm{low}(i))$ | query recursion, $\mathrm{popcount}(i)$ steps |
| covering blocks of $p$: $p,\ p+\mathrm{low}(p),\ \dots$ | update walk, one block per zero bit of $p-1$ |
| $\text{sum}(l, r) = \text{prefix}(r) - \text{prefix}(l-1)$ | needs an invertible operation |
| $a_i = \sum_{j \le i} d_j$, $d_j = a_j - a_{j-1}$ | range add / point query |
| $S(x) = (x+1)\sum_{j\le x} d_j - \sum_{j \le x} j\,d_j$ | range add / range sum with two BITs |
| $\text{rect}(x_1,y_1,x_2,y_2) = P(x_2,y_2)-P(x_1-1,y_2)-P(x_2,y_1-1)+P(x_1-1,y_1-1)$ | 2D inclusion–exclusion |
| $\#\text{inv} = \sum_j \#\{i<j : a_i > a_j\}$, $0 \le \#\text{inv} \le \binom n2$ | inversion count, needs 64-bit for $n \ge 65536$ |

**Complexities.** Point update and prefix query: $\le \lfloor\log_2 n\rfloor + 1$ iterations each. Build: $O(n)$
(push each $t[i]$ once into $t[i + \mathrm{low}(i)]$). k-th: $\lfloor\log_2 n\rfloor + 1$ iterations. 2D BIT: $O(\log n \log m)$
per operation, $O(nm)$ memory. Memory of the 1D BIT: exactly $n + 1$ cells — half of an iterative segment tree, a quarter of a recursive one.
Constant factor: a BIT query is a tight loop over one array; in practice it is 2–4× faster than a segment tree.

**Proof that the build is $O(n)$ and correct.** Node $j$'s block is the disjoint union of $\{j\}$ and the blocks of its
"children" $i$ with $i + \mathrm{low}(i) = j$; all children are $< j$. Processing $i = 1..n$ in order, $t[i]$ is complete when we
reach it (all its children came earlier), and we push it to its unique parent. One push per node.

## 3. Implementation (C++ and Java)

### 3.1 Point add, range sum, k-th (reusable structure)

1-indexed. `kth(k)` requires all stored values to be non-negative (counts); it returns `n + 1` if the total is less than `k`.

```cpp
struct Fenwick {
    int n, LOG;
    vector<long long> t;                       // t[i] = a[i - low(i) + 1] + ... + a[i]
    explicit Fenwick(int n) : n(n), LOG(1), t(n + 1, 0) { while ((LOG << 1) <= n) LOG <<= 1; }
    void build(const vector<long long>& a) {   // a is 1-indexed, size n + 1; O(n)
        for (int i = 1; i <= n; i++) {
            t[i] += a[i];
            int j = i + (i & -i);
            if (j <= n) t[j] += t[i];
        }
    }
    void add(int i, long long v) { for (; i <= n; i += i & -i) t[i] += v; }   // i must be >= 1
    long long sum(int i) const { long long s = 0; for (; i > 0; i -= i & -i) s += t[i]; return s; }
    long long sum(int l, int r) const { return l > r ? 0 : sum(r) - sum(l - 1); }
    int kth(long long k) const {               // smallest p with sum(p) >= k
        int pos = 0;
        for (int step = LOG; step > 0; step >>= 1)
            if (pos + step <= n && t[pos + step] < k) { pos += step; k -= t[pos]; }
        return pos + 1;
    }
};
```

```java
static class Fenwick {
    final int n; int log = 1; final long[] t;          // t[i] = a[i - low(i) + 1] + ... + a[i]
    Fenwick(int n) { this.n = n; t = new long[n + 1]; while ((log << 1) <= n) log <<= 1; }
    void build(long[] a) {                              // a is 1-indexed, length n + 1; O(n)
        for (int i = 1; i <= n; i++) {
            t[i] += a[i];
            int j = i + (i & -i);
            if (j <= n) t[j] += t[i];
        }
    }
    void add(int i, long v) { for (; i <= n; i += i & -i) t[i] += v; }   // i must be >= 1
    long sum(int i) { long s = 0; for (; i > 0; i -= i & -i) s += t[i]; return s; }
    long sum(int l, int r) { return l > r ? 0 : sum(r) - sum(l - 1); }
    int kth(long k) {                                   // smallest p with sum(p) >= k
        int pos = 0;
        for (int step = log; step > 0; step >>= 1)
            if (pos + step <= n && t[pos + step] < k) { pos += step; k -= t[pos]; }
        return pos + 1;
    }
}
```

### 3.2 Range add, range sum with two BITs

Input: `n q`, the array, then `q` lines `1 l r v` (add $v$ to $a_l..a_r$) or `2 l r` (print $a_l + \dots + a_r$).
The program is the formula $S(x) = (x+1)\,B_1(x) - B_2(x)$ verbatim. Note `(r + 1) * v` is computed in 64 bits.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct RangeBIT {
    int n; vector<long long> b1, b2;           // b1 over d[j], b2 over j * d[j]
    explicit RangeBIT(int n) : n(n), b1(n + 2, 0), b2(n + 2, 0) {}
    void upd(vector<long long>& b, int i, long long v) { for (; i <= n + 1; i += i & -i) b[i] += v; }
    long long qry(const vector<long long>& b, int i) const { long long s = 0; for (; i > 0; i -= i & -i) s += b[i]; return s; }
    void rangeAdd(int l, int r, long long v) {
        upd(b1, l, v); upd(b1, r + 1, -v);
        upd(b2, l, v * l); upd(b2, r + 1, -v * (r + 1));
    }
    long long prefix(int x) const { return (long long)(x + 1) * qry(b1, x) - qry(b2, x); }
    long long rangeSum(int l, int r) const { return prefix(r) - prefix(l - 1); }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    RangeBIT bit(n);
    for (int i = 1; i <= n; i++) { long long x; cin >> x; bit.rangeAdd(i, i, x); }
    while (q--) {
        int type, l, r; cin >> type >> l >> r;
        if (type == 1) { long long v; cin >> v; bit.rangeAdd(l, r, v); }
        else cout << bit.rangeSum(l, r) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n; static long[] b1, b2;                 // b1 over d[j], b2 over j * d[j]
    static void upd(long[] b, int i, long v) { for (; i <= n + 1; i += i & -i) b[i] += v; }
    static long qry(long[] b, int i) { long s = 0; for (; i > 0; i -= i & -i) s += b[i]; return s; }
    static void rangeAdd(int l, int r, long v) {
        upd(b1, l, v); upd(b1, r + 1, -v);
        upd(b2, l, v * l); upd(b2, r + 1, -v * (r + 1));
    }
    static long prefix(int x) { return (long) (x + 1) * qry(b1, x) - qry(b2, x); }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt(); int q = in.nextInt();
        b1 = new long[n + 2]; b2 = new long[n + 2];
        for (int i = 1; i <= n; i++) rangeAdd(i, i, in.nextLong());
        while (q-- > 0) {
            int type = in.nextInt(), l = in.nextInt(), r = in.nextInt();
            if (type == 1) rangeAdd(l, r, in.nextLong());
            else out.println(prefix(r) - prefix(l - 1));
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
5 6
1 2 3 4 5
2 1 5
1 2 4 10
2 1 5
2 3 3
1 1 5 -1
2 2 5
out:
15
45
13
40
-->
<!-- test
in:
1 3
-7
2 1 1
1 1 1 1000000000
2 1 1
out:
-7
999999993
-->

### 3.3 2D BIT — toggle a cell, count in a rectangle

This solves [CSES 1739 · Forest Queries II](https://cses.fi/problemset/task/1739): an $n \times n$ grid of `.`/`*`, queries
`1 y x` (toggle cell) and `2 y1 x1 y2 x2` (count `*` in the rectangle). Node $(i, j)$ stores the block
$(i - \mathrm{low}(i), i] \times (j - \mathrm{low}(j), j]$; both loops are independent BIT walks.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<vector<int>> t;
void add(int x, int y, int v) { for (int i = x; i <= n; i += i & -i) for (int j = y; j <= n; j += j & -j) t[i][j] += v; }
int pre(int x, int y) { int s = 0; for (int i = x; i > 0; i -= i & -i) for (int j = y; j > 0; j -= j & -j) s += t[i][j]; return s; }

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> n >> q;
    t.assign(n + 1, vector<int>(n + 1, 0));
    vector<string> g(n);
    for (int i = 0; i < n; i++) {
        cin >> g[i];
        for (int j = 0; j < n; j++) if (g[i][j] == '*') add(i + 1, j + 1, 1);
    }
    while (q--) {
        int type; cin >> type;
        if (type == 1) {
            int y, x; cin >> y >> x;
            char& c = g[y - 1][x - 1];
            add(y, x, c == '*' ? -1 : 1);
            c = (c == '*') ? '.' : '*';
        } else {
            int y1, x1, y2, x2; cin >> y1 >> x1 >> y2 >> x2;
            cout << pre(y2, x2) - pre(y1 - 1, x2) - pre(y2, x1 - 1) + pre(y1 - 1, x1 - 1) << '\n';
        }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n; static int[][] t;
    static void add(int x, int y, int v) { for (int i = x; i <= n; i += i & -i) for (int j = y; j <= n; j += j & -j) t[i][j] += v; }
    static int pre(int x, int y) { int s = 0; for (int i = x; i > 0; i -= i & -i) for (int j = y; j > 0; j -= j & -j) s += t[i][j]; return s; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt(); int q = in.nextInt();
        t = new int[n + 1][n + 1];
        char[][] g = new char[n][];
        for (int i = 0; i < n; i++) {
            g[i] = in.next().toCharArray();
            for (int j = 0; j < n; j++) if (g[i][j] == '*') add(i + 1, j + 1, 1);
        }
        while (q-- > 0) {
            int type = in.nextInt();
            if (type == 1) {
                int y = in.nextInt(), x = in.nextInt();
                add(y, x, g[y - 1][x - 1] == '*' ? -1 : 1);
                g[y - 1][x - 1] = g[y - 1][x - 1] == '*' ? '.' : '*';
            } else {
                int y1 = in.nextInt(), x1 = in.nextInt(), y2 = in.nextInt(), x2 = in.nextInt();
                out.println(pre(y2, x2) - pre(y1 - 1, x2) - pre(y2, x1 - 1) + pre(y1 - 1, x1 - 1));
            }
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
        String next() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
        int nextInt() throws IOException { return Integer.parseInt(next()); }
    }
}
```

<!-- test
in:
4 4
.*..
*.**
**..
****
2 2 2 3 4
2 1 1 4 4
1 3 3
2 2 2 3 4
out:
3
10
4
-->
<!-- test
in:
1 3
.
2 1 1 1 1
1 1 1
2 1 1 1 1
out:
0
1
-->

## 4. Recognising the pattern

- **"Point update + range sum/xor"**, values change, $n, q \le 2\cdot10^5$ → BIT (simplest correct structure). If the query is min/max/gcd, or the update is "assign", think [segment tree](02-segment-tree-basics.md) instead.
- **"Count pairs $i < j$ with a condition comparing $a_i$ and $a_j$"** (inversions, pairs with $a_i > 2a_j$, nested segments, "greetings") → sort/sweep one coordinate, BIT over the other.
- **"Range add, point query"** → BIT over the difference array; "range add, range sum" → two BITs (or a lazy segment tree, which is slower).
- **"Remove the $k$-th remaining element"**, "find the $k$-th smallest in a changing multiset", Josephus-type deletions → BIT of 0/1 counts + descent.
- **Offline queries over ranges where the answer is "count distinct", "xor of distinct", "count values with last occurrence < l"** → sort by right end, BIT over positions.
- **Coordinates up to $10^9$ but only $n$ distinct values** → compress first ([coordinate compression](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md)); a BIT cannot be sparse cheaply.
- **Subtree sums on a tree with point updates** → Euler tour flattens subtrees to ranges ([tree basics](../10-Trees/01-tree-basics-diameter-center-euler-tour.md)), then a BIT.
- Confused with: prefix sums (static, no updates — do not use a BIT); segment tree (needed for non-invertible operations or lazy assign); merge sort (also counts inversions, but cannot handle updates).

## 5. Worked examples (graded)

### Example 1 — Dynamic Range Sum Queries  ·  ★ ≈1300

- **Source:** [CSES 1648 · Dynamic Range Sum Queries](https://cses.fi/problemset/task/1648)
- **Difficulty:** ≈1300 (est.)
- **Problem:** array of $n \le 2\cdot10^5$ values up to $10^9$; $q \le 2\cdot10^5$ operations: `1 k u` sets $a_k = u$; `2 a b` prints $a_a + \dots + a_b$.
- **Thinking from first principles:** the BIT supports *add*, not *assign*. An assignment is an add of the difference
  $u - a_k$, provided we keep a plain copy of the current array. Sums reach $2\cdot10^{14}$ → 64-bit.

<details><summary>Solution</summary>

Keep `a[]` and a BIT; set = add `u - a[k]`, then `a[k] = u`. Build in $O(n)$. Each operation $O(\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct Fenwick {
    int n; vector<long long> t;
    explicit Fenwick(int n) : n(n), t(n + 1, 0) {}
    void build(const vector<long long>& a) {
        for (int i = 1; i <= n; i++) { t[i] += a[i]; int j = i + (i & -i); if (j <= n) t[j] += t[i]; }
    }
    void add(int i, long long v) { for (; i <= n; i += i & -i) t[i] += v; }
    long long sum(int i) const { long long s = 0; for (; i > 0; i -= i & -i) s += t[i]; return s; }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<long long> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    Fenwick f(n); f.build(a);
    while (q--) {
        int type; cin >> type;
        if (type == 1) { int k; long long u; cin >> k >> u; f.add(k, u - a[k]); a[k] = u; }
        else { int l, r; cin >> l >> r; cout << f.sum(r) - f.sum(l - 1) << '\n'; }
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
        int n = in.nextInt(), q = in.nextInt();
        long[] a = new long[n + 1], t = new long[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextLong();
        for (int i = 1; i <= n; i++) { t[i] += a[i]; int j = i + (i & -i); if (j <= n) t[j] += t[i]; }
        while (q-- > 0) {
            int type = in.nextInt();
            if (type == 1) {
                int k = in.nextInt(); long u = in.nextLong(), d = u - a[k]; a[k] = u;
                for (int i = k; i <= n; i += i & -i) t[i] += d;
            } else {
                int l = in.nextInt(), r = in.nextInt(); long s = 0;
                for (int i = r; i > 0; i -= i & -i) s += t[i];
                for (int i = l - 1; i > 0; i -= i & -i) s -= t[i];
                out.println(s);
            }
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
8 4
3 2 4 5 1 1 5 3
2 1 4
2 5 6
1 3 1
2 1 4
out:
14
2
11
-->
<!-- test
in:
1 3
1000000000
2 1 1
1 1 1
2 1 1
out:
1000000000
1
-->
<!-- test
in:
3 2
1000000000 1000000000 1000000000
1 2 999999999
2 1 3
out:
2999999999
-->

</details>

### Example 2 — Greetings  ·  ★ 1500

- **Source:** [CF 1915F · Greetings](https://codeforces.com/problemset/problem/1915/F) — 1500
- **Difficulty:** 1500
- **Problem:** $t$ test cases, total $n \le 2\cdot 10^5$. Person $i$ walks from $a_i$ to $b_i$ ($a_i < b_i$, all $2n$ numbers distinct, $|.| \le 10^9$), everyone at the same speed starting together. Two people greet when they are at the same point. Count greetings.
- **Thinking from first principles:** equal speeds mean two walkers keep their distance until one stops. Person $j$ can only
  be caught by $i$ if $j$ starts ahead of $i$ and stops before $i$ does: $a_i < a_j$ and $b_j < b_i$, i.e. segment $j$ is
  nested in segment $i$. If they cross ($a_i < a_j < b_i < b_j$) they never meet. So we count **nested pairs** — a 2D dominance count.
  Brute force is $O(n^2)$; sort by $a$, and for each segment count earlier ones (smaller $a$) with larger $b$ — a BIT over compressed $b$.

<details><summary>Solution</summary>

Sort by $a$ ascending. Sweep; before inserting $b_i$, the number of inserted $b$ greater than $b_i$ is
`inserted - prefix(rank(b_i))`. Add to the answer, then insert. The answer can be $\binom{n}{2} \approx 2\cdot10^{10}$ → 64-bit.
$O(n \log n)$ per test. Java: sort the pairs packed into a `long[]` after shuffling (anti-quicksort), and compress with binary search.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) {
        int n; cin >> n;
        vector<pair<int,int>> p(n);
        vector<int> bs(n);
        for (int i = 0; i < n; i++) { cin >> p[i].first >> p[i].second; bs[i] = p[i].second; }
        sort(p.begin(), p.end());
        sort(bs.begin(), bs.end());                       // all b distinct: rank = index + 1
        vector<int> t(n + 1, 0);
        long long ans = 0;
        for (int i = 0; i < n; i++) {
            int r = int(lower_bound(bs.begin(), bs.end(), p[i].second) - bs.begin()) + 1;
            int le = 0;
            for (int j = r; j > 0; j -= j & -j) le += t[j];
            ans += i - le;                                 // earlier segments with larger b contain this one
            for (int j = r; j <= n; j += j & -j) t[j]++;
        }
        cout << ans << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static void shuffleSort(long[] a) {
        Random rnd = new Random(12345);
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long x = a[i]; a[i] = a[j]; a[j] = x; }
        Arrays.sort(a);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) {
            int n = in.nextInt();
            long[] seg = new long[n], bs = new long[n];
            final long OFF = 1_000_000_001L;               // shift to make both coordinates non-negative
            for (int i = 0; i < n; i++) {
                long a = in.nextLong() + OFF, b = in.nextLong() + OFF;
                seg[i] = a * (1L << 31) + b;               // sort by a, b rides along
                bs[i] = b;
            }
            shuffleSort(seg); shuffleSort(bs);
            int[] t = new int[n + 1];
            long ans = 0;
            for (int i = 0; i < n; i++) {
                long b = seg[i] & ((1L << 31) - 1);
                int r = Arrays.binarySearch(bs, b) + 1;
                int le = 0;
                for (int j = r; j > 0; j -= j & -j) le += t[j];
                ans += i - le;
                for (int j = r; j <= n; j += j & -j) t[j]++;
            }
            out.println(ans);
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
3
2
2 3
1 4
4
1 10
2 9
3 8
4 5
3
1 3
2 4
5 6
out:
1
6
0
-->
<!-- test
in:
2
1
-1000000000 1000000000
5
-5 5
-4 -3
-2 2
-1 1
3 4
out:
0
5
-->

</details>

### Example 3 — List Removals (k-th by descent)  ·  ★ ≈1700

- **Source:** [CSES 1749 · List Removals](https://cses.fi/problemset/task/1749)
- **Difficulty:** ≈1700 (est.)
- **Problem:** a list of $n \le 2\cdot10^5$ values; $n$ times, remove the element at (current) position $p_i$ and print it.
- **Thinking from first principles:** removing from a `vector` is $O(n)$ → $O(n^2) = 4\cdot10^{10}$ worst case. Positions
  *shift*, original indices do not. Mark each original index alive (1) or dead (0); "current position $p$" is the original
  index whose alive-prefix count first reaches $p$ — the k-th one. That is exactly the BIT descent. Build the all-ones BIT in $O(n)$:
  $t[i] = \mathrm{low}(i)$.

<details><summary>Solution</summary>

`t[i] = i & -i` initially (block length = number of ones in it). For each $p$: `idx = kth(p)`, print `x[idx]`, `add(idx, -1)`.
$O(n \log n)$; no binary search needed.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long long> x(n + 1);
    for (int i = 1; i <= n; i++) cin >> x[i];
    vector<int> t(n + 1);
    for (int i = 1; i <= n; i++) t[i] = i & -i;          // all ones
    int LOG = 1; while ((LOG << 1) <= n) LOG <<= 1;
    for (int it = 0; it < n; it++) {
        int k; cin >> k;
        int pos = 0;
        for (int step = LOG; step > 0; step >>= 1)
            if (pos + step <= n && t[pos + step] < k) { pos += step; k -= t[pos]; }
        int idx = pos + 1;
        cout << x[idx] << (it + 1 < n ? ' ' : '\n');
        for (int j = idx; j <= n; j += j & -j) t[j]--;
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
        int n = in.nextInt();
        long[] x = new long[n + 1];
        for (int i = 1; i <= n; i++) x[i] = in.nextLong();
        int[] t = new int[n + 1];
        for (int i = 1; i <= n; i++) t[i] = i & -i;
        int log = 1; while ((log << 1) <= n) log <<= 1;
        StringBuilder sb = new StringBuilder();
        for (int it = 0; it < n; it++) {
            int k = in.nextInt(), pos = 0;
            for (int step = log; step > 0; step >>= 1)
                if (pos + step <= n && t[pos + step] < k) { pos += step; k -= t[pos]; }
            int idx = pos + 1;
            sb.append(x[idx]).append(it + 1 < n ? ' ' : '\n');
            for (int j = idx; j <= n; j += j & -j) t[j]--;
        }
        out.print(sb);
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
2 6 1 4 2
3 1 3 1 1
out:
1 2 2 6 4
-->
<!-- test
in:
1
42
1
out:
42
-->
<!-- test
in:
6
10 20 30 40 50 60
6 5 4 3 2 1
out:
60 50 40 30 20 10
-->

</details>

### Example 4 — Enemy is weak (triples by two sweeps)  ·  ★ 1900

- **Source:** [CF 61E · Enemy is weak](https://codeforces.com/problemset/problem/61/E) — 1900
- **Difficulty:** 1900
- **Problem:** $n \le 10^6$ distinct values up to $10^9$. Count triples $i < j < k$ with $a_i > a_j > a_k$.
- **Thinking from first principles:** a triple has a unique middle $j$. Given $j$, the choices of $i$ and $k$ are independent:
  $L_j = \#\{i < j: a_i > a_j\}$, $R_j = \#\{k > j: a_k < a_j\}$, and the answer is $\sum_j L_j R_j$. Each of $L, R$ is an
  inversion-style count: one BIT sweep left-to-right for $L$, one right-to-left for $R$. The answer is up to $\binom{10^6}{3}\approx 1.7\cdot 10^{17}$: 64-bit, but $L_j R_j$ itself fits since each is $< 10^6$.
  With $n = 10^6$ the constant matters: compress once by sorting `(value, index)` pairs, use `int` BIT arrays, fast input.

<details><summary>Solution</summary>

Compress values to ranks $1..n$ (distinct). Left sweep: $L_j = (j-1) - \text{prefix}(\text{rank}_j)$. Right sweep with a fresh BIT:
$R_j = \text{prefix}(\text{rank}_j - 1)$. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> a(n);
    for (auto& v : a) cin >> v;
    vector<int> idx(n);
    iota(idx.begin(), idx.end(), 0);
    sort(idx.begin(), idx.end(), [&](int x, int y) { return a[x] < a[y]; });
    vector<int> rk(n);
    for (int i = 0; i < n; i++) rk[idx[i]] = i + 1;
    vector<int> t(n + 1, 0);
    auto add = [&](int i) { for (; i <= n; i += i & -i) t[i]++; };
    auto pre = [&](int i) { int s = 0; for (; i > 0; i -= i & -i) s += t[i]; return s; };
    vector<long long> L(n);
    for (int j = 0; j < n; j++) { L[j] = j - pre(rk[j]); add(rk[j]); }
    fill(t.begin(), t.end(), 0);
    long long ans = 0;
    for (int j = n - 1; j >= 0; j--) { ans += L[j] * pre(rk[j] - 1); add(rk[j]); }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] key = new long[n];                          // value * 2^20 + index: sorting gives ranks
        for (int i = 0; i < n; i++) key[i] = (long) in.nextInt() << 20 | i;
        Random rnd = new Random(7);
        for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long x = key[i]; key[i] = key[j]; key[j] = x; }
        Arrays.sort(key);
        int[] rk = new int[n];
        for (int i = 0; i < n; i++) rk[(int) (key[i] & ((1 << 20) - 1))] = i + 1;
        int[] t = new int[n + 1];
        long[] L = new long[n];
        for (int j = 0; j < n; j++) {
            int s = 0; for (int i = rk[j]; i > 0; i -= i & -i) s += t[i];
            L[j] = j - s;
            for (int i = rk[j]; i <= n; i += i & -i) t[i]++;
        }
        Arrays.fill(t, 0);
        long ans = 0;
        for (int j = n - 1; j >= 0; j--) {
            int s = 0; for (int i = rk[j] - 1; i > 0; i -= i & -i) s += t[i];
            ans += L[j] * s;
            for (int i = rk[j]; i <= n; i += i & -i) t[i]++;
        }
        System.out.println(ans);
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        int nextInt() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            int r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
    }
}
```

<!-- test
in:
3
3 2 1
out:
1
-->
<!-- test
in:
4
10 8 3 1
out:
4
-->
<!-- test
in:
4
1 5 4 3
out:
1
-->
<!-- test
in:
1
1000000000
out:
0
-->

</details>

### Example 5 — Distinct Values Queries (offline by right end)  ·  ★ ≈1900

- **Source:** [CSES 1734 · Distinct Values Queries](https://cses.fi/problemset/task/1734)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n, q \le 2\cdot10^5$, values up to $10^9$; each query $(a, b)$ asks for the number of distinct values in $x_a..x_b$.
- **Thinking from first principles:** a segment tree does not help directly — the distinct count of two halves is not
  determined by the halves' counts. Dead ends: prefix counts per value ($O(nV)$ memory), Mo's algorithm ($O((n+q)\sqrt n)$,
  works but is slower; see [Mo's algorithm](07-sqrt-decomposition-and-mos-algorithm.md)). The key move: *process queries by right
  end* and keep a canonical representative of each value — its last occurrence so far (proof in §1). Then each query is a range count.

<details><summary>Solution</summary>

Compress values. Sort queries by $b$. Sweep $i = 1..n$: if `last[x_i]` exists, `add(last, -1)`; `add(i, +1)`; `last = i`;
then answer all queries with $b = i$ as `sum(a, i)`. $O((n + q)\log n)$. (For an **online** version use a
[persistent segment tree](08-persistent-data-structures.md).)

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<int> x(n + 1);
    for (int i = 1; i <= n; i++) cin >> x[i];
    vector<int> vals(x.begin() + 1, x.end());
    sort(vals.begin(), vals.end()); vals.erase(unique(vals.begin(), vals.end()), vals.end());
    for (int i = 1; i <= n; i++) x[i] = int(lower_bound(vals.begin(), vals.end(), x[i]) - vals.begin());
    vector<vector<pair<int,int>>> byRight(n + 1);          // byRight[b] = {(a, query id)}
    for (int k = 0; k < q; k++) { int a, b; cin >> a >> b; byRight[b].push_back({a, k}); }
    vector<int> t(n + 1, 0), last(vals.size(), 0), ans(q);
    auto add = [&](int i, int v) { for (; i <= n; i += i & -i) t[i] += v; };
    auto pre = [&](int i) { int s = 0; for (; i > 0; i -= i & -i) s += t[i]; return s; };
    for (int i = 1; i <= n; i++) {
        if (last[x[i]]) add(last[x[i]], -1);
        add(i, 1); last[x[i]] = i;
        for (auto [a, k] : byRight[i]) ans[k] = pre(i) - pre(a - 1);
    }
    for (int k = 0; k < q; k++) cout << ans[k] << '\n';
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
        int[] x = new int[n + 1];
        for (int i = 1; i <= n; i++) x[i] = in.nextInt();
        HashMap<Integer, Integer> id = new HashMap<>();    // compression by first appearance is enough here
        for (int i = 1; i <= n; i++) { Integer v = id.get(x[i]); if (v == null) { v = id.size(); id.put(x[i], v); } x[i] = v; }
        int[] qa = new int[q], head = new int[n + 1], nxt = new int[q];  // queries bucketed by right end
        Arrays.fill(head, -1);
        for (int k = 0; k < q; k++) { qa[k] = in.nextInt(); int b = in.nextInt(); nxt[k] = head[b]; head[b] = k; }
        int[] t = new int[n + 1], last = new int[id.size()], ans = new int[q];
        for (int i = 1; i <= n; i++) {
            if (last[x[i]] != 0) for (int j = last[x[i]]; j <= n; j += j & -j) t[j]--;
            for (int j = i; j <= n; j += j & -j) t[j]++;
            last[x[i]] = i;
            for (int k = head[i]; k != -1; k = nxt[k]) {
                int s = 0;
                for (int j = i; j > 0; j -= j & -j) s += t[j];
                for (int j = qa[k] - 1; j > 0; j -= j & -j) s -= t[j];
                ans[k] = s;
            }
        }
        for (int k = 0; k < q; k++) out.println(ans[k]);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        int nextInt() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            int r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
    }
}
```

The Java version uses a `HashMap<Integer,Integer>` only for the one-time compression; for hack-prone Codeforces inputs prefer
sort-based compression (see [ordered sets and hashing](10-ordered-sets-pbds-and-heaps.md)).

<!-- test
in:
5 3
3 2 3 1 2
1 3
2 4
1 5
out:
2
3
3
-->
<!-- test
in:
1 1
7
1 1
out:
1
-->
<!-- test
in:
6 4
5 5 5 5 5 5
1 6
3 3
2 5
6 6
out:
1
1
1
1
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Index 0 is an infinite loop.** `add(0, v)` never terminates because `0 & -0 = 0`. Shift every index by +1 if your data is 0-based, and remember that difference-array updates touch `r + 1` — size the array `n + 2` or guard `r + 1 <= n`.
2. **Assign is not add.** Keep a plain copy of the array and add the delta; forgetting to update the copy makes the second assignment wrong.
3. **Range sums need an inverse.** `sum(r) - sum(l-1)` is meaningless for max/min/gcd. A prefix-max BIT is legal only when values never decrease (e.g. LIS with $dp$ values) — and then only *prefix* queries.
4. **Overflow.** Sums of $2\cdot10^5$ values of $10^9$ need `long long`; the two-BIT formula multiplies `(x + 1) * B1(x)` and `l * v` — cast before multiplying (`1LL *` in C++, `(long)` in Java). Inversion counts exceed $2^{31}$ once $n > 65536$.
5. **k-th descent preconditions:** all stored values non-negative, `LOG` = largest power of two $\le n$ (not $\le n$ rounded up), and the check `pos + step <= n`. If $k$ exceeds the total, the result is `n + 1` — check it when the problem allows "not found".
6. **Compression must be consistent.** Use the same sorted-unique array for inserts and queries; when queries ask about values not in the array, use `lower_bound`/`upper_bound` semantics deliberately (count of values $\le v$ is `prefix(upper_bound(v))`).
7. **Java sorting:** `Arrays.sort(int[])`/`long[]` is a quicksort with an $O(n^2)$ anti-test; shuffle first, or pack `(value, index)` into a `long` and shuffle that (as in Example 2 and 4). `Integer[]` sorts are safe (TimSort) but box.
8. **Java speed with $n = 10^6$:** inline the BIT loops on `int[]` rather than calling methods on `long[]` objects when the time limit is tight; never use `Scanner`.
9. **Build in $O(n)$** when the initial array is given; $n$ separate `add`s cost $O(n \log n)$, which is fine for $2\cdot10^5$ but noticeable for $10^6$ in Java.
10. **2D BIT memory** is $(n+1)(m+1)$ cells: $1000 \times 1000$ ints = 4 MB is fine, $10^5 \times 10^5$ is not — for large sparse 2D problems go offline (sort by $x$, 1D BIT over $y$) or use CDQ ([offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md)).
11. **Counting "earlier and greater" vs "earlier and greater-or-equal"** differs by `prefix(r)` vs `prefix(r - 1)`; with duplicates (CF 1676H2) the off-by-one changes the answer.
12. **Offline by right end:** answer queries *after* processing position $b$, and bucket them by $b$ (linked lists of ids as in the Java code avoid `ArrayList<int[]>` overhead).

## 7. Going further (toward 2400–2600+)

- **BIT over a tree's Euler tour** for subtree updates/queries and path queries via "add at $tin$, subtract at $tout$" ([tree basics](../10-Trees/01-tree-basics-diameter-center-euler-tour.md), [HLD](../10-Trees/04-heavy-light-decomposition.md)).
- **Offline 2D counting with updates**: BIT of sorted vectors (static points), BIT of BITs on compressed coordinates, or CDQ divide and conquer for 3D dominance ([CDQ](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md)). [CF 1093E · Intersection of Permutations](https://codeforces.com/problemset/problem/1093/E) — 2400 is the standard test.
- **2D range-update range-query BIT** generalises the two-BIT trick to four BITs (coefficients $1, i, j, ij$); with xor it degenerates to parity cases: [CF 341D · Iahub and Xors](https://codeforces.com/problemset/problem/341/D) — 2500.
- **Random hashing on a 2D BIT** to test "same set of rectangles" equality: [CF 869E · The Untended Antiquity](https://codeforces.com/problemset/problem/869/E) — 2400.
- **Parallel binary search** wraps a BIT inside $\log V$ rounds of offline sweeps ([parallel binary search](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md)).
- **Order-statistics descent** generalises to segment trees ("walk the tree", [advanced segment trees](04-segment-tree-advanced-descent-merging-beats.md)) and to persistent trees for k-th in a range ([persistent structures](08-persistent-data-structures.md)).

## 8. Practice ladder

**≤ 1500**
- [ ] [CSES 1648 · Dynamic Range Sum Queries](https://cses.fi/problemset/task/1648)
- [ ] [CSES 1651 · Range Update Queries](https://cses.fi/problemset/task/1651)
- [ ] [AtCoder PRACTICE2 B · Fenwick Tree](https://atcoder.jp/contests/practice2/tasks/practice2_b)
- [ ] [CF 1915F · Greetings](https://codeforces.com/problemset/problem/1915/F) — 1500
- [ ] [CF 1676H2 · Maximum Crossings (Hard Version)](https://codeforces.com/problemset/problem/1676/H2) — 1500
- [ ] [CF 1791F · Range Update Point Query](https://codeforces.com/problemset/problem/1791/F) — 1500

**1500–1900**
- [ ] [CSES 1739 · Forest Queries II](https://cses.fi/problemset/task/1739)
- [ ] [CSES 1749 · List Removals](https://cses.fi/problemset/task/1749)
- [ ] [CSES 1144 · Salary Queries](https://cses.fi/problemset/task/1144)
- [ ] [CSES 1734 · Distinct Values Queries](https://cses.fi/problemset/task/1734)
- [ ] [AtCoder ABC174 F · Range Set Query](https://atcoder.jp/contests/abc174/tasks/abc174_f)
- [ ] [AtCoder ABC190 F · Shift and Inversions](https://atcoder.jp/contests/abc190/tasks/abc190_f)
- [ ] [CF 459D · Pashmak and Parmida's problem](https://codeforces.com/problemset/problem/459/D) — 1800
- [ ] [CF 1042D · Petya and Array](https://codeforces.com/problemset/problem/1042/D) — 1800
- [ ] [CF 652D · Nested Segments](https://codeforces.com/problemset/problem/652/D) — 1800
- [ ] [CF 1227D2 · Optimal Subsequences (Hard Version)](https://codeforces.com/problemset/problem/1227/D2) — 1800
- [ ] [CF 61E · Enemy is weak](https://codeforces.com/problemset/problem/61/E) — 1900
- [ ] [CF 1311F · Moving Points](https://codeforces.com/problemset/problem/1311/F) — 1900
- [ ] [CF 1354D · Multiset](https://codeforces.com/problemset/problem/1354/D) — 1900

**1900–2500**
- [ ] [CF 1288E · Messenger Simulator](https://codeforces.com/problemset/problem/1288/E) — 2000
- [ ] [CF 703D · Mishka and Interesting sum](https://codeforces.com/problemset/problem/703/D) — 2100
- [ ] [CF 1093E · Intersection of Permutations](https://codeforces.com/problemset/problem/1093/E) — 2400
- [ ] [CF 869E · The Untended Antiquity](https://codeforces.com/problemset/problem/869/E) — 2400
- [ ] [CF 341D · Iahub and Xors](https://codeforces.com/problemset/problem/341/D) — 2500

## 9. LeetCode / FAANG cross-reference

- [LC 307 · Range Sum Query - Mutable](https://leetcode.com/problems/range-sum-query-mutable/) — Medium — the textbook BIT; assignment = add the delta.
- [LC 308 · Range Sum Query 2D - Mutable](https://leetcode.com/problems/range-sum-query-2d-mutable/) — Medium 🔒 — 2D BIT exactly as in §3.3.
- [LC 315 · Count of Smaller Numbers After Self](https://leetcode.com/problems/count-of-smaller-numbers-after-self/) — Hard — right-to-left sweep over compressed values.
- [LC 493 · Reverse Pairs](https://leetcode.com/problems/reverse-pairs/) — Hard — pairs with $a_i > 2a_j$: compress both $a_i$ and $2a_j$.
- [LC 327 · Count of Range Sum](https://leetcode.com/problems/count-of-range-sum/) — Hard — prefix sums in $[P_j - \text{upper}, P_j - \text{lower}]$, BIT over compressed prefixes.
- [LC 1649 · Create Sorted Array through Instructions](https://leetcode.com/problems/create-sorted-array-through-instructions/) — Hard — count strictly smaller and strictly greater so far.
- [LC 2179 · Count Good Triplets in an Array](https://leetcode.com/problems/count-good-triplets-in-an-array/) — Hard — the $L_j \cdot R_j$ decomposition of Example 4 after relabelling.
- [LC 406 · Queue Reconstruction by Height](https://leetcode.com/problems/queue-reconstruction-by-height/) — Medium — place tallest-last; "k-th free slot" is the BIT descent.
- [LC 1395 · Count Number of Teams](https://leetcode.com/problems/count-number-of-teams/) — Medium — $O(n^2)$ passes, but the BIT version is the $L\cdot R$ trick.

Interview frequency: medium. Interviewers accept merge sort for inversion-type questions; a BIT is the shortest correct code when updates exist.

## 10. Self-check

1. Why does `i & -i` isolate the lowest set bit? Derive it from two's complement.
2. Which nodes does `add(13, v)` touch for $n = 16$, and which does `sum(13)` touch?
3. Derive the two-BIT formula for range add / range sum. What exactly goes into each BIT on `rangeAdd(l, r, v)`?
4. Why does the k-th descent work in $O(\log n)$ without binary search? What invariant holds for `pos`?
5. How do you count distinct values in $q$ ranges offline? Why is "last occurrence" the right representative?
6. Why can't a Fenwick tree answer range-minimum queries with arbitrary point updates?
7. How many 64-bit cells does a BIT for $n = 10^6$ use, versus a recursive segment tree?

<details><summary>Answers</summary>

1. $-i = \lnot i + 1$; for $i = x10^k$, $\lnot i = \bar x 0 1^k$, adding one gives $\bar x 1 0^k$; AND with $x10^k$ leaves $10^k$.
2. Update: $13 \to 14 \to 16$ (13 = 1101, +1 → 14 = 1110, +2 → 16). Query: $13 \to 12 \to 8 \to 0$, i.e. nodes 13, 12, 8.
3. $S(x) = (x+1)\sum_{j \le x} d_j - \sum_{j\le x} j d_j$. `B1.add(l, v); B1.add(r+1, -v); B2.add(l, l*v); B2.add(r+1, -(r+1)*v)`.
4. Before trying step $s$, `pos` is a multiple of $2s$, so node `pos + s` covers exactly $(pos, pos+s]$; each probe is one array read and decides one bit of the answer.
5. Sort queries by right end $r$; keep a 1 only at the last occurrence (≤ r) of each value; the answer is the number of ones in $[l, r]$ because a value occurs in $[l, r]$ iff its last occurrence ≤ r is ≥ l.
6. A range answer is obtained by subtracting two prefixes, and min has no inverse; also a decreased value cannot be "un-maxed" from the blocks above it.
7. $n + 1 \approx 10^6$ cells (8 MB) versus $4n = 4\cdot10^6$ (32 MB) for a recursive segment tree.

</details>
