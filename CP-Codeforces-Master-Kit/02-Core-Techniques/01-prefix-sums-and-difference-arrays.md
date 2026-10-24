# Prefix sums and difference arrays

> **Band:** 🟢–🔵 800–1900 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md), [integer overflow and fast I/O](../01-Foundations/06-integer-overflow-precision-and-fast-io.md), [STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md)
> **You can say you know this when:** you answer static range-sum, rectangle-sum and range-XOR queries in $O(1)$ after linear preprocessing; you apply a batch of range updates (constants, arithmetic progressions, rectangles) offline in $O(n+q)$; you turn "count subarrays whose sum has property X" into counting pairs of prefix values; and you can say exactly when a problem has become dynamic and needs a Fenwick or segment tree instead.

## 1. First principles — why this works

**The waste.** You are given an array $a_1,\dots,a_n$ and $q$ questions "what is $a_l+\dots+a_r$?". Answering each by a loop
costs $O(n)$, so $O(nq)$ overall — $4\cdot10^{10}$ at $n=q=2\cdot10^5$. The waste is obvious once you look at two
queries $[1,7]$ and $[1,9]$: the second recomputes the first seven terms. Every range is the *difference of two prefixes*:

$$a_l+\dots+a_r = (a_1+\dots+a_r) - (a_1+\dots+a_{l-1}).$$

So store the $n+1$ prefix totals $P_0=0,\ P_i=P_{i-1}+a_i$ once ($O(n)$) and answer every query with one subtraction ($O(1)$).

**What the operation needs.** The subtraction step requires an *inverse*: from "total of $[1,r]$" and "total of $[1,l-1]$" we
recover "total of $[l,r]$". That works for any operation forming a group: $+$, XOR (its own inverse), addition mod $m$,
multiplication mod a prime when no factor is $0$, and componentwise vector addition (count of each letter in a range: keep 26
prefix-count arrays). It fails for $\min$, $\max$, $\gcd$, OR, AND: knowing $\min(a_1..a_r)$ and $\min(a_1..a_{l-1})$ says
nothing about $\min(a_l..a_r)$. For those you still get prefix and suffix aggregates (useful whenever the query is a prefix,
a suffix, or "everything except one element / one window", which is prefix ⊕ suffix), and for arbitrary ranges you need a
[sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md) or a [segment tree](../08-Data-Structures/02-segment-tree-basics.md).

**Subarrays are pairs of prefixes.** A subarray $[l,r]$ corresponds to the pair of prefix indices $(l-1, r)$ with $l-1<r$, and
its sum is $P_r-P_{l-1}$. So *any* condition on a subarray sum becomes a condition on a pair $(P_i, P_j)$, $i<j$:

| Subarray condition | Pair condition ($i<j$) | Counting tool |
|---|---|---|
| sum $=k$ | $P_i = P_j-k$ | hash map of earlier prefix values |
| sum divisible by $k$ | $P_i \equiv P_j \pmod k$ | array of size $k$ (or map) |
| XOR $=x$ | $X_i = X_j \oplus x$ | map / array of size $2^{b}$ |
| as many 0s as 1s | $P_i=P_j$ after mapping $0\to-1$ | map, first occurrence |
| sum $\ge k$, all $a\ge 0$ | $P_i\le P_j-k$, $P$ monotone | [two pointers](03-two-pointers-and-sliding-window.md) |
| sum $\ge k$, negatives allowed | $P_i\le P_j-k$, $P$ arbitrary | Fenwick on compressed $P$, or [monotone deque](04-monotonic-stack-and-deque.md) for the shortest |

Scan $j$ from left to right, query "how many earlier $i$ satisfy the relation", then insert $P_j$. With an *equality*
relation this is a hash-map lookup and the whole count is $O(n)$. This "pair counting on prefixes" reduction is the single
most reused idea in this file.

**The inverse direction: difference arrays.** Now flip the problem: $q$ updates "add $v$ to every $a_i$, $i\in[l,r]$", and
only at the end you read the array. Define $D_i=a_i-a_{i-1}$ (with $a_0=0$). Then $a_i=D_1+\dots+D_i$ — the prefix sum of $D$
is $a$. A range add changes the *differences* in only two places: $D_l$ grows by $v$ (the step into the range) and $D_{r+1}$
drops by $v$ (the step out). So each update is $O(1)$ and one final prefix-sum pass rebuilds $a$: $O(n+q)$ total.
This is discrete calculus: $P$ is an integral, $D$ is a derivative, and "range update + point query" on $a$ is
"point update + prefix query" on $D$.

**Offline versus online.** Both tricks are *offline*: prefix sums assume no updates after building; difference arrays assume
no reads until all updates are in. When updates and queries interleave ("add on a range, then ask a sum, then add again"),
you need a structure that does both in $O(\log n)$ — a [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md) is exactly a
prefix-sum array that tolerates point updates, and two Fenwicks over $D$ give range add + range sum;
a [lazy segment tree](../08-Data-Structures/03-lazy-propagation.md) handles everything else (range assign, range min with
range add, arithmetic-progression updates with interleaved queries). The decision is mechanical:

| Updates | Queries | Tool |
|---|---|---|
| none | range sum | prefix sums, $O(1)$ per query |
| all before all queries | range sum / point | difference array, then prefix sums |
| point, interleaved | range sum | Fenwick tree |
| range add, interleaved | point | Fenwick over $D$ |
| range add, interleaved | range sum | two Fenwicks over $D$ (formula in §2) or lazy segment tree |
| anything with min/max/assign | interleaved | segment tree (lazy) |

**More dimensions.** In 2D, $P_{x,y}=\sum_{i\le x,\,j\le y}a_{i,j}$. A rectangle $[x_1,x_2]\times[y_1,y_2]$ is the big prefix
$P_{x_2,y_2}$ minus the strip above it and the strip left of it, which overlap in the corner $P_{x_1-1,y_1-1}$, subtracted twice
and so added back once (inclusion–exclusion). The 2D difference array is the inverse: a rectangle add touches four corners.

**Higher order.** Adding an arithmetic progression $s, s+d, s+2d,\dots$ on $[l,r]$ is not a constant add, so the first
difference changes on the whole range (by $d$ at every inner position). But that change *is* a constant add on a range of $D$,
so difference once more: the second difference $E_i=D_i-D_{i-1}$ changes in only four places. In general a polynomial of degree
$p$ in the index becomes zero after $p+1$ differences ($\Delta^{p+1}f=0$), so adding a degree-$p$ polynomial on a range costs
$O(p)$ point changes in the $(p+1)$-th difference array, and $p+1$ prefix passes rebuild the result.

## 2. Formulas, definitions and identities

Indexing: 1-based arrays, $P_0=0$. (Half-open $[l,r)$ with $P_r-P_l$ is the same thing shifted; pick one convention per program.)

**1D prefix sums.**
$$P_i=\sum_{t=1}^{i}a_t,\qquad \sum_{t=l}^{r}a_t=P_r-P_{l-1}.$$
Build $O(n)$, query $O(1)$, memory $n+1$ values. Overflow: $|P_i|\le n\max|a|$, so with $n=2\cdot10^5$, $|a|\le10^9$ use 64-bit.

**Prefix XOR.** $X_i=a_1\oplus\dots\oplus a_i$, $\ \bigoplus_{t=l}^{r}a_t=X_r\oplus X_{l-1}$ (because $x\oplus x=0$).

**Subarrays with sum $k$.** $\#\{(l,r): \sum_{l}^{r}a=k\}=\sum_{j=1}^{n}\#\{i<j: P_i=P_j-k\}$ — one scan with a frequency map;
valid for negative values too (unlike two pointers).

**Subarrays with sum divisible by $k$.** $k\mid P_r-P_{l-1}\iff P_r\equiv P_{l-1}\pmod k$. If $c_v$ is the number of indices
$i\in[0,n]$ with $P_i\bmod k=v$, the answer is $\sum_v\binom{c_v}{2}$. Normalise negatives: $((P\bmod k)+k)\bmod k$ in both C++ and
Java, because `%` keeps the sign of the dividend.

**Longest subarray with sum $k$.** Keep the *first* index where each prefix value appears; answer $\max_j (j-\text{first}[P_j-k])$.

**Prefix minimum and maximum subarray sum.**
$$\max_{l\le r}\sum_{t=l}^{r}a_t=\max_{r}\Big(P_r-\min_{0\le i<r}P_i\Big),$$
which is Kadane's algorithm written in prefix form. "Best buy-then-sell" is the same formula on prices.

**Prefix–suffix decomposition.** For an associative $\circ$ without inverse, $\text{pre}_i=a_1\circ\dots\circ a_i$,
$\text{suf}_i=a_i\circ\dots\circ a_n$; "everything except $a_i$" $=\text{pre}_{i-1}\circ\text{suf}_{i+1}$; "everything except window
$[l,r]$" $=\text{pre}_{l-1}\circ\text{suf}_{r+1}$. $O(n)$ build, $O(1)$ per query.

**Weighted prefix.** With $W_i=\sum_{t\le i}t\,a_t$:
$\ \sum_{t=l}^{r}(t-l+1)a_t=(W_r-W_{l-1})-(l-1)(P_r-P_{l-1}).$

**2D prefix sums** (inclusion–exclusion):
$$P_{x,y}=a_{x,y}+P_{x-1,y}+P_{x,y-1}-P_{x-1,y-1},$$
$$\text{sum}([x_1,x_2]\times[y_1,y_2])=P_{x_2,y_2}-P_{x_1-1,y_2}-P_{x_2,y_1-1}+P_{x_1-1,y_1-1}.$$
Proof: a cell inside the rectangle is counted once (only in the first term); a cell above it is in terms 1 and 2 ($+1-1$); a cell
to the left is in terms 1 and 3; a cell in the top-left corner region is in all four ($+1-1-1+1=0$). In $d$ dimensions the box sum
has $2^d$ terms with sign $(-1)^{\#\text{lower corners used}}$. Build $O(nm)$, query $O(1)$.

**1D difference array.** $D_i=a_i-a_{i-1}$. Range add $v$ on $[l,r]$: $D_l\mathrel{+}=v,\ D_{r+1}\mathrel{-}=v$ (allocate $n+2$).
Rebuild $a_i=\sum_{t\le i}D_t$. Each update $O(1)$, rebuild $O(n)$.

**2D difference array.** Add $v$ on $[x_1,x_2]\times[y_1,y_2]$:
$$D_{x_1,y_1}\mathrel{+}=v,\quad D_{x_1,y_2+1}\mathrel{-}=v,\quad D_{x_2+1,y_1}\mathrel{-}=v,\quad D_{x_2+1,y_2+1}\mathrel{+}=v,$$
then take the 2D prefix sum of $D$. (Each corner's sign is the inclusion–exclusion sign; the 2D prefix of a single $+v$ at
$(x_1,y_1)$ fills the whole quadrant below-right, and the other three corners cancel the excess.)

**Arithmetic progression on a range.** Add $s+(i-l)d$ to $a_i$ for $i\in[l,r]$. The first difference changes by $s$ at $l$, by $d$
at $l+1..r$, by $-(s+(r-l)d)$ at $r+1$. Differencing that once more gives the second difference $E$:
$$E_l\mathrel{+}=s,\quad E_{l+1}\mathrel{+}=d-s,\quad E_{r+1}\mathrel{-}=s+(r-l+1)d,\quad E_{r+2}\mathrel{+}=s+(r-l)d.$$
(Check: the four changes sum to $0$, and when $r=l$ the two middle ones merge correctly.) Rebuild with two prefix passes.
Equivalent and often less error-prone: write the added term as $(s-l\,d)+d\cdot i$ and keep two ordinary difference arrays,
$C$ for the constant $(s-ld)$ and $B$ for the coefficient $d$; then $a_i=C_i+i\cdot B_i$.

**Polynomials of degree $p$.** $\Delta^{p+1}f\equiv0$ for $\deg f=p$ (each difference lowers the degree by one). So adding
$f(i)$ on $[l,r]$ changes the $(p+1)$-th difference only at $l..l+p$ and $r+1..r+p+1$; or keep $p+1$ coefficient arrays
(coefficient of $i^0,\dots,i^p$), each a plain difference array. The $t$-fold prefix sum of a single $1$ at position $1$ is
$\binom{i+t-2}{t-1}$ at position $i$ — the reason repeated prefix sums produce binomial coefficients.

**Range add + range sum with two Fenwick trees.** With $a_i=\sum_{j\le i}D_j$,
$$\sum_{i=1}^{x}a_i=\sum_{j=1}^{x}D_j\,(x-j+1)=(x+1)\sum_{j\le x}D_j-\sum_{j\le x}j\,D_j,$$
so keep Fenwicks over $D_j$ and over $j\,D_j$; both updates and queries are $O(\log n)$.

| Operation | Cost |
|---|---|
| build 1D / 2D prefix | $O(n)$ / $O(nm)$ |
| range / rectangle query | $O(1)$ |
| range / rectangle add (difference) | $O(1)$, rebuild $O(n)$ / $O(nm)$ |
| AP add (second difference) | $O(1)$, rebuild $2\times O(n)$ |
| count subarrays with sum $k$ / divisible by $k$ | $O(n)$ expected (hash) / $O(n+k)$ |

## 3. Implementation (C++ and Java)

### 3.1 Prefix sums, prefix–suffix aggregates and subarray counting (fragments)

```cpp
// 1D prefix sums, 1-indexed: sum(l, r) = P[r] - P[l-1]
struct Prefix {
    vector<ll> P;
    Prefix(const vector<ll>& a) : P(a.size() + 1, 0) {          // a is 0-indexed input
        for (size_t i = 0; i < a.size(); i++) P[i + 1] = P[i] + a[i];
    }
    ll sum(int l, int r) const { return l > r ? 0 : P[r] - P[l - 1]; } // 1 <= l, r <= n
};

// splitmix64: hash that anti-hash tests cannot target (seeded from the clock)
struct SplitMix {
    size_t operator()(ull x) const {
        static const ull R = chrono::steady_clock::now().time_since_epoch().count();
        x += R + 0x9e3779b97f4a7c15ULL;
        x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
        x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
        return x ^ (x >> 31);
    }
};

// number of subarrays with sum exactly k (negative values allowed)
ll countSumK(const vector<ll>& a, ll k) {
    unordered_map<ull, int, SplitMix> seen;
    seen.reserve(a.size() * 2 + 1);
    seen[0] = 1;                                   // the empty prefix P_0 = 0
    ll p = 0, ans = 0;
    for (ll x : a) {
        p += x;
        auto it = seen.find((ull)(p - k));
        if (it != seen.end()) ans += it->second;
        seen[(ull)p]++;
    }
    return ans;
}

// number of subarrays with sum divisible by k (k >= 1)
ll countDivisible(const vector<ll>& a, int k) {
    vector<ll> cnt(k, 0);
    cnt[0] = 1;
    ll p = 0, ans = 0;
    for (ll x : a) {
        p = ((p + x) % k + k) % k;                 // keep the residue in [0, k)
        ans += cnt[p]++;
    }
    return ans;
}

// gcd of everything except a[i], for every i: prefix and suffix aggregates (gcd has no inverse)
vector<ll> gcdExceptSelf(const vector<ll>& a) {
    int n = a.size();
    vector<ll> pre(n + 1, 0), suf(n + 2, 0), res(n);
    for (int i = 0; i < n; i++) pre[i + 1] = gcd(pre[i], a[i]);
    for (int i = n - 1; i >= 0; i--) suf[i] = gcd(suf[i + 1], a[i]);
    for (int i = 0; i < n; i++) res[i] = gcd(pre[i], suf[i + 1]);
    return res;
}
```

```java
static long[] prefix(long[] a) {                   // P[0] = 0, sum(l..r) = P[r] - P[l-1] (1-indexed)
    long[] P = new long[a.length + 1];
    for (int i = 0; i < a.length; i++) P[i + 1] = P[i] + a[i];
    return P;
}

// subarrays with sum exactly k, without hashing: compress the prefix values, count in index order
static long countSumK(long[] a, long k) {
    int n = a.length;
    long[] P = new long[n + 1];
    for (int i = 0; i < n; i++) P[i + 1] = P[i] + a[i];
    long[] vals = P.clone();
    Arrays.sort(vals);                              // long[] sort: no anti-quicksort issue in practice for this use
    int m = 0;
    for (int i = 0; i <= n; i++) if (m == 0 || vals[m - 1] != vals[i]) vals[m++] = vals[i];
    int[] cnt = new int[m];
    long ans = 0;
    for (int j = 0; j <= n; j++) {
        int t = Arrays.binarySearch(vals, 0, m, P[j] - k);   // distinct values: the index is exact
        if (t >= 0) ans += cnt[t];
        cnt[Arrays.binarySearch(vals, 0, m, P[j])]++;
    }
    return ans;
}

static long countDivisible(long[] a, int k) {
    long[] cnt = new long[k];
    cnt[0] = 1;
    long p = 0, ans = 0;
    for (long x : a) {
        p = ((p + x) % k + k) % k;                  // Java % is negative for negative p + x
        ans += cnt[(int) p]++;
    }
    return ans;
}

static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }

static long[] gcdExceptSelf(long[] a) {
    int n = a.length;
    long[] pre = new long[n + 1], suf = new long[n + 2], res = new long[n];
    for (int i = 0; i < n; i++) pre[i + 1] = gcd(pre[i], a[i]);
    for (int i = n - 1; i >= 0; i--) suf[i] = gcd(suf[i + 1], a[i]);
    for (int i = 0; i < n; i++) res[i] = gcd(pre[i], suf[i + 1]);
    return res;
}
```

### 3.2 2D difference array and 2D prefix sums (tested program)

Input: `n m U Q`, then `U` rectangle adds `x1 y1 x2 y2 v` (1-indexed, inclusive), then `Q` rectangle-sum queries `x1 y1 x2 y2`.
All updates come first, so the whole thing is offline: four corner updates each, one 2D prefix pass to materialise the grid, a
second 2D prefix pass to answer queries.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m, U, Q;
    cin >> n >> m >> U >> Q;
    vector<vector<ll>> g(n + 2, vector<ll>(m + 2, 0));
    for (int t = 0; t < U; t++) {
        int x1, y1, x2, y2; ll v;
        cin >> x1 >> y1 >> x2 >> y2 >> v;
        g[x1][y1] += v; g[x1][y2 + 1] -= v; g[x2 + 1][y1] -= v; g[x2 + 1][y2 + 1] += v;
    }
    // pass 1: 2D prefix of the difference grid = actual values; pass 2: 2D prefix of the values
    for (int pass = 0; pass < 2; pass++)
        for (int i = 1; i <= n; i++)
            for (int j = 1; j <= m; j++)
                g[i][j] += g[i - 1][j] + g[i][j - 1] - g[i - 1][j - 1];
    // cells in row n+1 / column m+1 hold leftovers of the corner updates; they are never read below
    while (Q--) {
        int x1, y1, x2, y2;
        cin >> x1 >> y1 >> x2 >> y2;
        cout << g[x2][y2] - g[x1 - 1][y2] - g[x2][y1 - 1] + g[x1 - 1][y1 - 1] << '\n';
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
        int n = in.nextInt(), m = in.nextInt(), U = in.nextInt(), Q = in.nextInt();
        long[][] g = new long[n + 2][m + 2];
        for (int t = 0; t < U; t++) {
            int x1 = in.nextInt(), y1 = in.nextInt(), x2 = in.nextInt(), y2 = in.nextInt();
            long v = in.nextLong();
            g[x1][y1] += v; g[x1][y2 + 1] -= v; g[x2 + 1][y1] -= v; g[x2 + 1][y2 + 1] += v;
        }
        for (int pass = 0; pass < 2; pass++)
            for (int i = 1; i <= n; i++)
                for (int j = 1; j <= m; j++)
                    g[i][j] += g[i - 1][j] + g[i][j - 1] - g[i - 1][j - 1];
        while (Q-- > 0) {
            int x1 = in.nextInt(), y1 = in.nextInt(), x2 = in.nextInt(), y2 = in.nextInt();
            out.println(g[x2][y2] - g[x1 - 1][y2] - g[x2][y1 - 1] + g[x1 - 1][y1 - 1]);
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
2 3 2 3
1 1 2 2 5
2 2 2 3 -1
1 1 2 3
2 3 2 3
1 2 2 3
out:
18
-1
8
-->
<!-- test
in:
1 1 1 1
1 1 1 1 7
1 1 1 1
out:
7
-->
<!-- test
in:
3 3 3 2
1 1 3 3 1
2 2 2 2 10
3 1 3 3 -2
2 2 2 2
1 1 3 3
out:
11
13
-->

### 3.3 Arithmetic progressions on ranges via second differences (tested program)

Input: `n q`, then `q` lines `l r s d` meaning "add $s, s+d, \dots, s+(r-l)d$ to $a_l..a_r$" (a constant add is $d=0$).
Output the final array. Constraints for 64-bit safety: $n,q\le2\cdot10^5$, $|s|,|d|\le10^6$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q;
    cin >> n >> q;
    vector<ll> E(n + 3, 0);                          // second difference, indices up to r+2
    while (q--) {
        ll l, r, s, d;
        cin >> l >> r >> s >> d;
        E[l] += s;
        E[l + 1] += d - s;
        E[r + 1] -= s + (r - l + 1) * d;
        E[r + 2] += s + (r - l) * d;
    }
    for (int pass = 0; pass < 2; pass++)             // E -> D -> a
        for (int i = 1; i <= n + 2; i++) E[i] += E[i - 1];
    for (int i = 1; i <= n; i++) cout << E[i] << " \n"[i == n];
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
        long[] E = new long[n + 3];
        while (q-- > 0) {
            long l = in.nextLong(), r = in.nextLong(), s = in.nextLong(), d = in.nextLong();
            E[(int) l] += s;
            E[(int) l + 1] += d - s;
            E[(int) r + 1] -= s + (r - l + 1) * d;
            E[(int) r + 2] += s + (r - l) * d;
        }
        for (int pass = 0; pass < 2; pass++)
            for (int i = 1; i <= n + 2; i++) E[i] += E[i - 1];
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= n; i++) sb.append(E[i]).append(i == n ? "\n" : " ");
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
5 3
1 5 1 1
2 4 10 -3
5 5 7 100
out:
1 12 10 8 12
-->
<!-- test
in:
1 2
1 1 5 3
1 1 -2 9
out:
3
-->
<!-- test
in:
6 2
1 6 0 0
3 6 -1 -1
out:
0 0 -1 -2 -3 -4
-->

## 4. Recognising the pattern

- **"$q$ queries asking the sum / count / XOR on a range", no updates** → prefix array. Counting "positions in $[l,r]$ with
  property X" is a prefix sum of an indicator array.
- **"Apply $m$ operations each adding to a range, then output"** or **"how many intervals cover point $x$"** → difference
  array. If the coordinates are up to $10^9$, sort the $2m$ events instead ([sweep line](05-coordinate-compression-and-sweep-line.md)).
- **"Count subarrays whose sum equals / is divisible by / XORs to …"** → pair counting on prefixes with a map.
  Transform first when the condition is not literally a sum: "sum equals length" → subtract 1 from each element; "equal number of
  A and B" → $\pm1$; "odd and even positions have equal sums" → alternate signs; "every letter appears an even number of times" →
  prefix XOR of bitmasks.
- **"Rectangle sums", "count cells in a sub-grid", "$k\times k$ window" on a grid up to $\sim 2000\times2000$** → 2D prefix; "paint
  many rectangles" → 2D difference.
- **"Remove one element / one window and optimise the rest"** with min, max, gcd, intersection of segments → prefix and suffix aggregates.
- **Values up to $10^5$ – $10^6$ in a query ("count items with $h$ between …")** → prefix sums over the *value* axis, not the index axis.
- **Operations interleaved with queries** → stop; this is a Fenwick / segment tree problem.
- **Confused with:** two pointers (works for "sum $\ge k$" only when all values are non-negative), sliding window max (needs a
  deque, not prefixes), and segment trees (overkill for static data — and $O(\log n)$ per query can TLE where $O(1)$ passes).

## 5. Worked examples (graded)

### Example 1 — Karen and Coffee  ·  ★ 1400

- **Source:** [CF 816B · Karen and Coffee](https://codeforces.com/problemset/problem/816/B) — 1400
- **Difficulty:** 1400
- **Problem:** $n$ recipes each recommend a temperature interval $[l_i,r_i]$ ($1\le l_i\le r_i\le 200000$). A temperature is
  *admissible* if at least $k$ recipes recommend it. Answer $q$ questions: how many admissible integer temperatures lie in $[a,b]$?
  $n,q\le2\cdot10^5$.
- **Thinking from first principles:** Two separate wastes. (1) Computing "how many recipes cover $t$" for every $t$ by walking
  each interval is $O(n\cdot200000)$; but all intervals are known before any question, so a difference array gives every
  coverage count in $O(n+V)$. (2) Each question counts admissible points in a range — a range count over a fixed 0/1 array, i.e. a
  prefix sum of the indicator. Two prefix passes, one after the other, solve it in $O(n+q+V)$.

<details><summary>Solution</summary>

$d_{l_i}\mathrel{+}=1$, $d_{r_i+1}\mathrel{-}=1$; running sum gives coverage $c_t$; $g_t=g_{t-1}+[c_t\ge k]$; answer $g_b-g_{a-1}$.
Correctness is the difference-array identity plus the prefix-sum identity. $O(n+q+V)$ time, $O(V)$ memory with $V=2\cdot10^5$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int V = 200000;
    int n, k, q;
    cin >> n >> k >> q;
    vector<int> d(V + 2, 0), good(V + 1, 0);
    for (int i = 0; i < n; i++) {
        int l, r; cin >> l >> r;
        d[l]++; d[r + 1]--;
    }
    int cover = 0;
    for (int t = 1; t <= V; t++) {
        cover += d[t];
        good[t] = good[t - 1] + (cover >= k);
    }
    while (q--) {
        int a, b; cin >> a >> b;
        cout << good[b] - good[a - 1] << '\n';
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
        final int V = 200000;
        int n = in.nextInt(), k = in.nextInt(), q = in.nextInt();
        int[] d = new int[V + 2], good = new int[V + 1];
        for (int i = 0; i < n; i++) {
            int l = in.nextInt(), r = in.nextInt();
            d[l]++; d[r + 1]--;
        }
        int cover = 0;
        for (int t = 1; t <= V; t++) {
            cover += d[t];
            good[t] = good[t - 1] + (cover >= k ? 1 : 0);
        }
        while (q-- > 0) {
            int a = in.nextInt(), b = in.nextInt();
            out.println(good[b] - good[a - 1]);
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
3 2 3
1 5
3 8
4 4
1 10
4 4
6 200000
out:
3
1
0
-->
<!-- test
in:
1 1 2
200000 200000
1 200000
199999 199999
out:
1
0
-->

</details>

### Example 2 — Subarray Divisibility  ·  ★ ≈1500 (est.)

- **Source:** [CSES 1662 · Subarray Divisibility](https://cses.fi/problemset/task/1662)
- **Difficulty:** ≈1500 (est.)
- **Problem:** Given $n$ integers $a_i$ ($|a_i|\le10^9$, $n\le2\cdot10^5$), count the subarrays whose sum is divisible by $n$.
- **Thinking from first principles:** $O(n^2)$ subarrays is too many. A subarray sum is $P_r-P_{l-1}$, and "$n$ divides a
  difference" is "same residue". So the question is how many *pairs of prefix indices* share a residue mod $n$ — a pure counting
  question over $n+1$ residues. Dead end to avoid: two pointers (values can be negative, nothing is monotone). Trap: `%` on a
  negative prefix gives a negative residue, which would split one residue class into two.

<details><summary>Solution</summary>

Count residues $c_v$ of $P_0..P_n$ modulo $n$ (normalised into $[0,n)$); the answer is $\sum_v\binom{c_v}{2}$, accumulated
online as `ans += cnt[r]++`. $O(n)$ time and memory; the answer can reach $\binom{n+1}{2}\approx2\cdot10^{10}$, so 64-bit.
The same scan with a hash map keyed by $P_j-x$ solves "subarrays with sum exactly $x$" ([CSES 1661 · Subarray Sums II](https://cses.fi/problemset/task/1661)).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<ll> cnt(n, 0);
    cnt[0] = 1;                                     // P_0 = 0
    ll p = 0, ans = 0;
    for (int i = 0; i < n; i++) {
        ll x; cin >> x;
        p = ((p + x) % n + n) % n;
        ans += cnt[p]++;
    }
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
        long[] cnt = new long[n];
        cnt[0] = 1;
        long p = 0, ans = 0;
        for (int i = 0; i < n; i++) {
            long x = in.nextLong();
            p = ((p + x) % n + n) % n;
            ans += cnt[(int) p]++;
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
1 -1 3
out:
3
-->
<!-- test
in:
1
-5
out:
1
-->
<!-- test
in:
4
-4 -8 2 6
out:
6
-->

</details>

### Example 3 — Sasha and a Bit of Relax  ·  ★ 1600

- **Source:** [CF 1109A · Sasha and a Bit of Relax](https://codeforces.com/problemset/problem/1109/A) — 1600
- **Difficulty:** 1600
- **Problem:** Given $a_1..a_n$ ($n\le3\cdot10^5$, $0\le a_i<2^{20}$), count pairs $l<r$ such that $r-l+1$ is even and the XOR of the
  left half of $a_l..a_r$ equals the XOR of the right half.
- **Thinking from first principles:** "Left half XOR equals right half XOR" looks like it needs the midpoint. But $x=y\iff x\oplus y=0$,
  and $x\oplus y$ is the XOR of the *whole* subarray — the midpoint disappears. So: count even-length subarrays with XOR $0$, i.e.
  pairs of prefix indices $i=l-1<j=r$ with $X_i=X_j$ and $j-i$ even, i.e. $i\equiv j\pmod 2$. Bucket prefix XORs by
  (index parity, value).

<details><summary>Solution</summary>

Keep `cnt[parity][value]` for prefix indices seen so far, starting with `cnt[0][0]=1` for $X_0$. For each $j$, add
`cnt[j&1][X_j]`, then increment it. $O(n+2^{21})$ time and memory; answer up to $\approx\binom{n}{2}/2$, so 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<array<int, 2>> cnt(1 << 20, {0, 0});
    cnt[0][0] = 1;
    int x = 0; ll ans = 0;
    for (int j = 1; j <= n; j++) {
        int a; cin >> a;
        x ^= a;
        ans += cnt[x][j & 1]++;
    }
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
        int[][] cnt = new int[2][1 << 20];
        cnt[0][0] = 1;
        int x = 0; long ans = 0;
        for (int j = 1; j <= n; j++) {
            x ^= in.nextInt();
            ans += cnt[j & 1][x]++;
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
3 3 3 3
out:
4
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
6
1 1 1 1 1 1
out:
9
-->

</details>

### Example 4 — Counting Rectangles  ·  ★ 1600

- **Source:** [CF 1722E · Counting Rectangles](https://codeforces.com/problemset/problem/1722/E) — 1600
- **Difficulty:** 1600
- **Problem:** $t$ test cases. Each has $n$ rectangles with integer height $h_i$ and width $w_i$ ($1\le h_i,w_i\le1000$) and $q$
  queries $(h_s,w_s,h_b,w_b)$; for each query output the total *area* of the rectangles with $h_s<h_i<h_b$ and $w_s<w_i<w_b$.
  $\sum n,\sum q\le10^5$, $t\le100$.
- **Thinking from first principles:** Per query, scanning the rectangles is $O(nq)=10^{10}$. The condition is a box in the
  $(h,w)$ plane, and the coordinates are tiny (1000). So index by *value*: put $h\cdot w$ into cell $(h,w)$ of a $1000\times1000$
  grid, and every query becomes a 2D prefix rectangle sum over $[h_s+1,h_b-1]\times[w_s+1,w_b-1]$. Strict inequalities become
  shifted inclusive bounds; an empty range (e.g. $h_b=h_s+1$) automatically gives $0$ in the formula. Reset the grid per test case.

<details><summary>Solution</summary>

Grid $G_{h,w}\mathrel{+}=h w$; prefix $P$; answer
$P_{h_b-1,w_b-1}-P_{h_s,w_b-1}-P_{h_b-1,w_s}+P_{h_s,w_s}$. Per test $O(V^2+n+q)$ with $V=1000$, so at most $10^8$ simple
additions over all tests. Areas sum to at most $10^5\cdot10^6$: 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

static ll P[1001][1001];

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n, q; cin >> n >> q;
        for (auto& row : P) fill(begin(row), end(row), 0);
        for (int i = 0; i < n; i++) {
            int h, w; cin >> h >> w;
            P[h][w] += 1LL * h * w;
        }
        for (int i = 1; i <= 1000; i++)
            for (int j = 1; j <= 1000; j++)
                P[i][j] += P[i - 1][j] + P[i][j - 1] - P[i - 1][j - 1];
        while (q--) {
            int hs, ws, hb, wb; cin >> hs >> ws >> hb >> wb;
            cout << P[hb - 1][wb - 1] - P[hs][wb - 1] - P[hb - 1][ws] + P[hs][ws] << '\n';
        }
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
        long[][] P = new long[1001][1001];
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt(), q = in.nextInt();
            for (long[] row : P) Arrays.fill(row, 0);
            for (int i = 0; i < n; i++) {
                int h = in.nextInt(), w = in.nextInt();
                P[h][w] += (long) h * w;
            }
            for (int i = 1; i <= 1000; i++)
                for (int j = 1; j <= 1000; j++)
                    P[i][j] += P[i - 1][j] + P[i][j - 1] - P[i - 1][j - 1];
            while (q-- > 0) {
                int hs = in.nextInt(), ws = in.nextInt(), hb = in.nextInt(), wb = in.nextInt();
                out.println(P[hb - 1][wb - 1] - P[hs][wb - 1] - P[hb - 1][ws] + P[hs][ws]);
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
1
3 3
2 3
5 5
2 3
1 1 3 4
1 1 1000 1000
2 2 6 6
out:
12
37
25
-->
<!-- test
in:
2
1 1
999 999
998 998 1000 1000
1 2
1 1
1 1 2 2
1 1 1000 1000
out:
998001
0
0
-->

</details>

### Example 5 — Progressions Covering  ·  ★ 1900

- **Source:** [CF 1661D · Progressions Covering](https://codeforces.com/problemset/problem/1661/D) — 1900
- **Difficulty:** 1900
- **Problem:** Array $a$ starts as $n$ zeros. One operation picks a window of exactly $k$ consecutive positions and adds
  $1,2,\dots,k$ to it (left to right). Find the minimum number of operations so that $a_i\ge b_i$ for all $i$.
  $1\le k\le n\le3\cdot10^5$, $1\le b_i\le10^{12}$.
- **Thinking from first principles:**
  1. Which windows can help the *last* position $n$? Only those that contain it, and the window ending at $n$ gives it the
     most ($k$). More generally, process positions right to left; when position $i$ is the rightmost one we still have to fix,
     a window ending exactly at $i$ dominates every other window that covers $i$: a window ending at $e>i$ gives each position
     $p\le i$ the value $p-e+k<p-i+k$ and covers a subset of $[i-k+1,i]$; its extra coverage to the right of $i$ is wasted because
     those positions are already satisfied. (Near the left border, where $i<k$, the only window is $[1,k]$, giving $i$ the value $i$.)
  2. So greedily place $\lceil(b_i-\text{cur}_i)/\min(k,i)\rceil$ windows ending at $i$. Exchange argument: take an optimal solution
     agreeing with greedy on all window ends $>i$; it needs at least as many windows ending at $i$; if it has more, shift the
     extras one step left — positions $<i$ only gain, $i$ stays satisfied — so it agrees at $i$ too.
  3. The remaining problem is computing $\text{cur}_i$, the total currently added at $i$, without touching each window: this is
     a second-order difference maintained *on the fly*. When moving from $i$ to $i-1$, every active window loses exactly $1$, so
     $\text{cur}\mathrel{-}=\text{cnt}$ (number of active windows), and windows whose left end is $i$ leave the active set.

<details><summary>Solution</summary>

Scan $i=n..1$ with `sum` (value added at $i$), `cnt` (active windows) and `closeAt[s]` (windows whose left end is $s$).
At $i$: `len = min(k, i)`; if `sum < b_i`, take `need = ceil((b_i - sum)/len)` windows, `sum += need*len`, `cnt += need`,
`closeAt[i-len+1] += need`. Then step left: `sum -= cnt; cnt -= closeAt[i]`. $O(n)$ time. Bounds: at most $k$ window groups
overlap a position and each contributes at most $b+k$, so `sum` stays below $3\cdot10^{17}$; 64-bit is enough.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k; cin >> n >> k;
    vector<ll> b(n + 1), closeAt(n + 2, 0);
    for (int i = 1; i <= n; i++) cin >> b[i];
    ll sum = 0, cnt = 0, ans = 0;
    for (int i = n; i >= 1; i--) {
        ll len = min(k, i);
        if (sum < b[i]) {
            ll need = (b[i] - sum + len - 1) / len;
            ans += need; sum += need * len; cnt += need;
            closeAt[i - len + 1] += need;
        }
        sum -= cnt;                                  // every active window gives one less at i-1
        cnt -= closeAt[i];                           // windows starting at i end here
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt();
        long[] b = new long[n + 1], closeAt = new long[n + 2];
        for (int i = 1; i <= n; i++) b[i] = in.nextLong();
        long sum = 0, cnt = 0, ans = 0;
        for (int i = n; i >= 1; i--) {
            long len = Math.min(k, i);
            if (sum < b[i]) {
                long need = (b[i] - sum + len - 1) / len;
                ans += need; sum += need * len; cnt += need;
                closeAt[(int) (i - len + 1)] += need;
            }
            sum -= cnt;
            cnt -= closeAt[i];
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
1 2 3 4
out:
4
-->
<!-- test
in:
1 1
1000000000000
out:
1000000000000
-->
<!-- test
in:
5 5
5 1 1 1 1
out:
5
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Seed the empty prefix.** `cnt[0] = 1` / `seen[0] = 1` before the scan, or every subarray starting at index 1 is missed.
   This is the most common WA in prefix-counting code.
2. **Query before insert.** In the pair-counting scan, look up partners of $P_j$ *before* inserting $P_j$; otherwise $k=0$
   counts the empty subarray $(j,j)$.
3. **Normalise residues.** `((p % k) + k) % k` in both C++ and Java. Also note `p % k` with `p` of type `long long` and `k` of type
   `int` is fine, but `(a + b) % k` where `a + b` overflowed first is not.
4. **64-bit prefix sums.** $2\cdot10^5\cdot10^9$ overflows `int`. In C++ write `vector<ll>`; in Java `long[]`. The *counts* of
   subarrays can reach $\approx2\cdot10^{10}$, also 64-bit.
5. **Size $n+2$ for difference arrays** ($D_{r+1}$ with $r=n$), and $n+3$ for the second difference ($E_{r+2}$).
6. **2D memory.** A `long long` grid of $5000\times5000$ is 200 MB; for counts use `int`, and prefer a flat array
   `g[i*(m+1)+j]` in Java (an array of arrays costs one object header per row and is slower to traverse).
7. **Java hash maps of `Long`** box every key and are vulnerable to collisions only in contrived cases, but they are 5–10× slower
   than arrays. When the relation is "equal", sorting the prefix array and counting runs (or compressing as in §3.1) avoids hashing.
8. **C++ `unordered_map` anti-hash.** Hackers on Codeforces craft inputs that collide with the default hash; use the splitmix64
   hash from §3.1, and `reserve` to avoid rehashing.
9. **Difference arrays need all updates first.** If a query sits between two updates, rebuilding the array each time is
   $O(n)$ per query; switch to a [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md).
10. **Prefix over the value axis.** When the condition involves values up to $10^6$ rather than positions, build the
    prefix array over values (Example 4). If values reach $10^9$, compress first ([coordinate compression](05-coordinate-compression-and-sweep-line.md)).
11. **Off-by-one with strict inequalities.** "$h_s<h<h_b$" means inclusive bounds $[h_s+1,h_b-1]$; write the conversion once,
    explicitly, before the formula.
12. **Multiple test cases:** reset only what you used, or reset everything if the grid is fixed-size and small; never allocate a
    $10^6$ array per test when $t$ is $10^4$.

## 7. Going further (toward 2400–2600+)

- **Repeated prefix sums.** $t$-fold prefix sums give binomial weights $\binom{j-i+t-1}{t-1}$; with updates this becomes a
  Fenwick tree per moment of the index — see
  [AtCoder ABC256 F · Cumulative Cumulative Cumulative Sum](https://atcoder.jp/contests/abc256/tasks/abc256_f), and
  [combinatorics](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) for the identities.
- **Polynomial updates with interleaved queries** are lazy segment tree territory ([CSES 1736 · Polynomial Queries](https://cses.fi/problemset/task/1736),
  [lazy propagation](../08-Data-Structures/03-lazy-propagation.md)).
- **Prefix sums over subsets** (sum over all submasks) generalise the 1D prefix to the hypercube: [SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md).
- **Prefix sums inside DP** remove a factor of $n$ from transitions of the form $dp_i=\sum_{j\in[i-k,i-1]}dp_j$:
  [prefix-sum DP optimisation](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md).
- **Prefix sums on trees** (root-to-node sums, $\text{sum}(u,v)=S_u+S_v-2S_{\text{lca}}+a_{\text{lca}}$) and difference arrays on
  trees (add on a path, accumulate subtree sums): [LCA](../10-Trees/02-lca-and-binary-lifting.md).
- **Counting subarrays with sum $\ge k$ and negative values** needs order statistics on prefixes: a Fenwick tree over compressed
  prefix values, or merge-sort counting ([offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md) for the CDQ generalisation).

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 1709B · Also Try Minecraft](https://codeforces.com/problemset/problem/1709/B) — 900
- [ ] [CF 313B · Ilya and Queries](https://codeforces.com/problemset/problem/313/B) — 1100
- [ ] [CF 433B · Kuriyama Mirai's Stones](https://codeforces.com/problemset/problem/433/B) — 1200
- [ ] [CF 1915E · Romantic Glasses](https://codeforces.com/problemset/problem/1915/E) — 1300
- [ ] [CF 295A · Greg and Array](https://codeforces.com/problemset/problem/295/A) — 1400
- [ ] [CSES 1646 · Static Range Sum Queries](https://cses.fi/problemset/task/1646)
- [ ] [CSES 1650 · Range Xor Queries](https://cses.fi/problemset/task/1650)
- [ ] [CSES 1652 · Forest Queries](https://cses.fi/problemset/task/1652)
- [ ] [AtCoder ABC183 D · Water Heater](https://atcoder.jp/contests/abc183/tasks/abc183_d)

**1400–1700**
- [ ] [CF 276C · Little Girl and Maximum Sum](https://codeforces.com/problemset/problem/276/C) — 1500
- [ ] [CF 611C · New Year and Domino](https://codeforces.com/problemset/problem/611/C) — 1500
- [ ] [CF 1516B · AGAGA XOOORRR](https://codeforces.com/problemset/problem/1516/B) — 1500
- [ ] [CF 1872E · Data Structures Fan](https://codeforces.com/problemset/problem/1872/E) — 1500
- [ ] [CSES 1661 · Subarray Sums II](https://cses.fi/problemset/task/1661)
- [ ] [CF 1398C · Good Subarrays](https://codeforces.com/problemset/problem/1398/C) — 1600
- [ ] [CF 1748C · Zero-Sum Prefixes](https://codeforces.com/problemset/problem/1748/C) — 1600
- [ ] [CF 1029C · Maximal Intersection](https://codeforces.com/problemset/problem/1029/C) — 1600
- [ ] [CF 1028C · Rectangles](https://codeforces.com/problemset/problem/1028/C) — 1600
- [ ] [CF 835C · Star sky](https://codeforces.com/problemset/problem/835/C) — 1600
- [ ] [CF 466C · Number of Ways](https://codeforces.com/problemset/problem/466/C) — 1700

**1700–1900**
- [ ] [CF 1343D · Constant Palindrome Sum](https://codeforces.com/problemset/problem/1343/D) — 1700
- [ ] [CF 1333C · Eugene and an array](https://codeforces.com/problemset/problem/1333/C) — 1700
- [ ] [CF 1879D · Sum of XOR Functions](https://codeforces.com/problemset/problem/1879/D) — 1700
- [ ] [CF 1355C · Count Triangles](https://codeforces.com/problemset/problem/1355/C) — 1800
- [ ] [CF 1200D · White Lines](https://codeforces.com/problemset/problem/1200/D) — 1900
- [ ] [CF 1197D · Yet Another Subarray Problem](https://codeforces.com/problemset/problem/1197/D) — 1900

**Stretch**
- [ ] [AtCoder ABC256 F · Cumulative Cumulative Cumulative Sum](https://atcoder.jp/contests/abc256/tasks/abc256_f)
- [ ] [CSES 1736 · Polynomial Queries](https://cses.fi/problemset/task/1736)

## 9. LeetCode / FAANG cross-reference

Prefix sums are among the most frequent interview ideas; the hash-map counting scan (LC 560) is asked constantly.

- [LC 303 · Range Sum Query - Immutable](https://leetcode.com/problems/range-sum-query-immutable/) — Easy — the 1D identity.
- [LC 724 · Find Pivot Index](https://leetcode.com/problems/find-pivot-index/) — Easy — left prefix vs total minus prefix.
- [LC 304 · Range Sum Query 2D - Immutable](https://leetcode.com/problems/range-sum-query-2d-immutable/) — Medium — 2D inclusion–exclusion.
- [LC 1314 · Matrix Block Sum](https://leetcode.com/problems/matrix-block-sum/) — Medium — 2D prefix with clamped windows.
- [LC 238 · Product of Array Except Self](https://leetcode.com/problems/product-of-array-except-self/) — Medium — prefix × suffix (no inverse allowed).
- [LC 560 · Subarray Sum Equals K](https://leetcode.com/problems/subarray-sum-equals-k/) — Medium — pair counting with a map, negatives allowed.
- [LC 974 · Subarray Sums Divisible by K](https://leetcode.com/problems/subarray-sums-divisible-by-k/) — Medium — residue counting; normalise negatives.
- [LC 523 · Continuous Subarray Sum](https://leetcode.com/problems/continuous-subarray-sum/) — Medium — residues with first occurrence (length ≥ 2).
- [LC 525 · Contiguous Array](https://leetcode.com/problems/contiguous-array/) — Medium — $0\to-1$, longest zero-sum via first occurrence.
- [LC 930 · Binary Subarrays With Sum](https://leetcode.com/problems/binary-subarrays-with-sum/) — Medium — sum $=k$ counting (or atMost trick).
- [LC 1248 · Count Number of Nice Subarrays](https://leetcode.com/problems/count-number-of-nice-subarrays/) — Medium — prefix count of odd numbers.
- [LC 1371 · Find the Longest Substring Containing Vowels in Even Counts](https://leetcode.com/problems/find-the-longest-substring-containing-vowels-in-even-counts/) — Medium — prefix XOR of a 5-bit mask.
- [LC 1915 · Number of Wonderful Substrings](https://leetcode.com/problems/number-of-wonderful-substrings/) — Medium — prefix mask, equal or one bit different.
- [LC 1442 · Count Triplets That Can Form Two Arrays of Equal XOR](https://leetcode.com/problems/count-triplets-that-can-form-two-arrays-of-equal-xor/) — Medium — the Example 3 observation.
- [LC 1094 · Car Pooling](https://leetcode.com/problems/car-pooling/) — Medium — difference array over stops.
- [LC 1109 · Corporate Flight Bookings](https://leetcode.com/problems/corporate-flight-bookings/) — Medium — textbook range add.
- [LC 370 · Range Addition](https://leetcode.com/problems/range-addition/) — Medium 🔒 — the same, locked.
- [LC 2381 · Shifting Letters II](https://leetcode.com/problems/shifting-letters-ii/) — Medium — difference array mod 26.
- [LC 1589 · Maximum Sum Obtained of Any Permutation](https://leetcode.com/problems/maximum-sum-obtained-of-any-permutation/) — Medium — coverage counts via difference, then sort (CF 276C).
- [LC 3355 · Zero Array Transformation I](https://leetcode.com/problems/zero-array-transformation-i/) — Medium — coverage count vs requirement.
- [LC 2536 · Increment Submatrices by One](https://leetcode.com/problems/increment-submatrices-by-one/) — Medium — 2D difference.
- [LC 1074 · Number of Submatrices That Sum to Target](https://leetcode.com/problems/number-of-submatrices-that-sum-to-target/) — Hard — fix two rows, then LC 560 on column sums: $O(n^2m)$.
- [LC 2132 · Stamping the Grid](https://leetcode.com/problems/stamping-the-grid/) — Hard — 2D prefix to test stamps, 2D difference to paint them.
- [LC 437 · Path Sum III](https://leetcode.com/problems/path-sum-iii/) — Medium — LC 560 on root-to-node paths (add on enter, remove on exit).

Interview framing: see [arrays, hashing and prefix sums](../17-FAANG-Interview-DSA/02-arrays-hashing-and-prefix-sums.md).

## 10. Self-check

1. Why can't you answer "min of $a_l..a_r$" with prefix minima, while you can with prefix sums? What *can* prefix minima answer?
2. Write the 2D rectangle-sum formula and explain why the corner term has a plus sign.
3. You count subarrays with sum $k$ and get an answer that is too small by exactly the number of valid prefixes. What did you forget?
4. Which four second-difference entries change when you add $s, s+d, \dots$ on $[l,r]$? How else can you do it with two plain difference arrays?
5. Values can be negative and you need the number of subarrays with sum $\ge k$. Why do two pointers fail, and what works?
6. Updates "add $v$ on $[l,r]$" and queries "sum on $[l,r]$" interleave. Which structure, and what is the formula behind the two-Fenwick trick?
7. In Example 3, why does the midpoint of the subarray not matter?
8. A grid is $3000\times3000$ and you need rectangle sums of counts. How much memory does a `long long` prefix grid take, and what would you use instead?

<details><summary>Answers</summary>

1. $\min$ has no inverse: from $\min(a_1..a_r)$ and $\min(a_1..a_{l-1})$ you cannot recover the minimum of the middle. Prefix minima
   answer prefix queries, and with suffix minima any "all except a window" query; general ranges need a sparse table.
2. $P_{x_2,y_2}-P_{x_1-1,y_2}-P_{x_2,y_1-1}+P_{x_1-1,y_1-1}$; the top-left region is subtracted by both strips, so it must be added back once.
3. The seed $P_0=0$ (`cnt[0]=1`): subarrays starting at index 1 have no left partner without it.
4. $E_l\mathrel{+}=s$, $E_{l+1}\mathrel{+}=d-s$, $E_{r+1}\mathrel{-}=s+(r-l+1)d$, $E_{r+2}\mathrel{+}=s+(r-l)d$. Alternatively write the term as
   $(s-ld)+d\cdot i$ and keep difference arrays for the constant and for the coefficient of $i$; $a_i=C_i+iB_i$.
5. With negatives, extending a window can decrease the sum, so the left pointer is not monotone. Count pairs $i<j$ with
   $P_i\le P_j-k$ using a Fenwick tree over compressed prefix values ($O(n\log n)$).
6. Two Fenwick trees over $D_j$ and $jD_j$: $\sum_{i\le x}a_i=(x+1)\sum_{j\le x}D_j-\sum_{j\le x}jD_j$; or a lazy segment tree.
7. Left XOR $=$ right XOR $\iff$ left $\oplus$ right $=0$, and left $\oplus$ right is the XOR of the whole subarray, independent of where it is split.
8. $\approx 9\cdot10^6\cdot8$ bytes $=72$ MB; counts fit in `int` (36 MB). In Java use a flat `int[]`.

</details>

See also the [cheat sheet](../99-Cheat-Sheets/02-core-techniques-cheatsheet.md) and the folder [problem list](problems.md).
