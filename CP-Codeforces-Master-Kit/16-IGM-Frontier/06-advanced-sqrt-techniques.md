# Advanced square-root techniques

> **Band:** 🟠 2100–2700 (sqrt tree: 🧊) · **Priority:** ⚡ (the heavy/light split is close to 🔥: it appears in Div 2 E/F regularly) · **FAANG:** low · **Prerequisites:** [sqrt decomposition and Mo's algorithm](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md), [complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md), [LCA](../10-Trees/02-lca-and-binary-lifting.md), [string hashing](../11-Strings/01-string-hashing.md)
> **You can say you know this when:** for a problem with two natural algorithms — one fast for "small" objects, one fast for "large" ones — you can name the split parameter (step, degree, set size, frequency, length, age of an update), write the cost of each side as a function of the threshold $B$, solve for $B$, and implement both sides without mixing them up.

## 1. First principles — why this works

### 1.1 One principle: balance two costs

Square-root techniques are not one algorithm but one *argument*. You have two ways to handle an object (an update, a query, a vertex, a set):

- way 1 costs about $a\cdot B$ (it is cheap when the object is "small", or it pays per small object);
- way 2 costs about $b / B$ (it is cheap when the object is "large", because there are few large objects or a large object has few "steps").

Choosing the threshold $B$ minimises $aB + b/B$ at $B = \sqrt{b/a}$, with total $2\sqrt{ab}$. Everything in this file is an instance: identify the parameter, write both costs, balance.

Three counting facts produce the "few large objects" side again and again:

1. **Sizes sum to $S$** ⇒ at most $S/B$ objects have size $> B$ (sets, components, adjacency lists: $\sum \deg = 2m$).
2. **Distinct sizes are few:** if sizes sum to $S$, there are at most $\sqrt{2S}$ *distinct* sizes ($1 + 2 + \dots + k \le S$).
3. **Large steps are short:** walking over $1..N$ with step $x > B$ visits fewer than $N/B$ positions.

### 1.2 Split by step or modulus

"Sum of $a_i$ over $i \equiv y \pmod x$" with point updates ([CF 1207F · Remainder Problem](https://codeforces.com/problemset/problem/1207/F) — 2100). For $x \le B$ keep a table `small[x][y]` of all answers, updated in $O(B)$ per point update. For $x > B$ answer by walking $y, y+x, \dots$: fewer than $N/B$ terms. Total $O(q(B + N/B))$, optimal at $B = \sqrt N$. The same split answers "jump by $k$ until you leave the array" ([CF 797E · Array Queries](https://codeforces.com/problemset/problem/797/E) — 2000) and "sum of every $k$-th element from $t$" ([CF 103D · Time to Raid Cowavans](https://codeforces.com/problemset/problem/103/D) — 2100).

### 1.3 Heavy/light by degree, size or frequency

**Triangles.** Enumerating all wedges $u - v - w$ costs $\sum \deg^2$, which is $\Theta(m^2)$ for a star. Orient every edge from the endpoint of smaller degree to the endpoint of larger degree (ties by index). The orientation is acyclic, every triangle becomes exactly one pattern $u \to v,\ u \to w,\ v \to w$, and **every out-degree is at most $\sqrt{2m}$**: if $\deg(v) \le \sqrt{2m}$ then $\text{out}(v) \le \deg(v)$; otherwise all out-neighbours have degree $\ge \deg(v) > \sqrt{2m}$, and fewer than $\sqrt{2m}$ vertices can have such degree since degrees sum to $2m$. Enumerating $u \to v \to w$ and checking $u \to w$ with a mark array costs $\sum_v \text{in}(v)\cdot\text{out}(v) \le \sqrt{2m}\cdot m$: $O(m\sqrt m)$.

**Heavy sets.** Sets $S_1..S_m$ of indices with total size $T$, updates "add $x$ to every element of $S_k$", queries "sum over $S_k$" ([CF 348C · Subset Sums](https://codeforces.com/problemset/problem/348/C) — 2500). Light sets ($|S| \le B$) are handled element by element. Heavy sets ($|S| > B$) are at most $T/B$; for each, precompute its intersection size with every other set ($O(T)$ per heavy set by marking). A heavy update is recorded as a lazy total; a light update also pushes its effect into each heavy set's stored sum through the intersection table; a query adds the heavy lazies times intersections. All operations become $O(B + T/B)$.

**Heavy values.** The same argument with "values that occur more than $B$ times" (at most $n/B$ of them) is the core of [CF 1446D2 · Frequency Problem (Hard Version)](https://codeforces.com/problemset/problem/1446/D2) — 3000: heavy values get an $O(n)$ scan each, light values are handled by fixing the frequency $f \le B$ and two pointers.

### 1.4 Square root on time: buffer recent updates, rebuild periodically

Many problems have a *static* structure that is expensive to build ($R$) but answers queries fast, and updates that would invalidate it. Keep:

- the structure built from all updates up to the last rebuild (exact for those);
- a buffer of at most $B$ newer updates, each checked by brute force at query time ($c$ per buffered update).

Rebuild when the buffer is full. Cost: $(q/B)\cdot R + q\cdot B\cdot c$, optimal at $B = \sqrt{R/c}$. In [CF 342E · Xenia and Tree](https://codeforces.com/problemset/problem/342/E) — 2400 the structure is a multi-source BFS ($R = n$), a buffered red vertex is checked by an $O(1)$ LCA distance ($c = 1$), so $B \approx \sqrt n$ and the total is $O((n+q)\sqrt n)$. The same pattern rebuilds prefix sums, sorted arrays or a Fenwick tree every $\sqrt q$ operations when updates are insertions in the middle.

### 1.5 Square root over the answer

If an answer $f(k)$ is non-increasing in $k$ and $f(k) \le n/k$, then for $k > \sqrt n$ it is below $\sqrt n$: the function takes at most $2\sqrt n$ distinct values. Compute it directly for small $k$, and for each of the few possible values binary search the range of $k$ that produces it ([CF 1039D · You Are Given a Tree](https://codeforces.com/problemset/problem/1039/D) — 2800). The same counting gives "$\lfloor n/i \rfloor$ takes $O(\sqrt n)$ values" used in [floor sums](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md).

### 1.6 Few distinct lengths

Patterns with total length $L$ have at most $\sqrt{2L}$ distinct lengths. For each distinct length, one $O(|T|)$ pass of rolling hashes over the text counts every pattern of that length at once: $O(|T|\sqrt L)$ instead of $O(|T|\cdot q)$. Aho–Corasick ([Aho–Corasick](../11-Strings/06-aho-corasick.md)) is linear for the static version, but the length grouping survives *insertions and deletions* of patterns between queries ([CF 710F · String Set Queries](https://codeforces.com/problemset/problem/710/F) — 2400), where rebuilding an automaton is expensive. Knapsack with bounded total sum uses the same fact ([bitset optimisation](05-bitset-optimization.md)).

### 1.7 Related structures (know they exist)

- **Mo's algorithm with updates** — add a time dimension to Mo; $O(n^{5/3})$ with block size $n^{2/3}$ ([sqrt decomposition and Mo](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md), [CF 940F · Machine Learning](https://codeforces.com/problemset/problem/940/F) — 2600).
- **Sqrt tree** (🧊) — $O(1)$ range queries for any associative operation after $O(n\log\log n)$ preprocessing; recursion of prefix/suffix tables on blocks of size $\sqrt n$. Rarely needed: a sparse table or disjoint sparse table usually suffices.
- **Block decomposition with "exit pointers"** — for jump structures ([CF 13E · Holes](https://codeforces.com/problemset/problem/13/E) — 2700), store for each position where the ball leaves its block and after how many jumps; an update rebuilds one block. Compare with the [link-cut tree](03-link-cut-trees.md) solution.

## 2. Formulas, definitions and identities

- **Balancing:** $\min_B (aB + b/B) = 2\sqrt{ab}$ at $B = \sqrt{b/a}$. The optimum is flat: any $B$ within a factor 2 of it costs at most $1.25\times$ the minimum.
- **Heavy count:** sizes $s_i \ge 0$ with $\sum s_i = S$ ⇒ $\#\{i : s_i > B\} < S/B$.
- **Distinct sizes:** $\sum s_i = S$ ⇒ $\#\{\text{distinct } s_i\} \le \sqrt{2S}$.
- **Degree orientation:** $\text{out}(v) \le \sqrt{2m}$ ⇒ triangles in $O(m\sqrt m)$; also cycles of length 4 in $O(m\sqrt m)$.
- **Remainder table:** update $O(B)$, query $O(1)$ for $x \le B$ and $O(N/x) < O(N/B)$ otherwise.
- **Periodic rebuild:** total $(q/B)R + qBc$, optimal $B = \sqrt{R/c}$.
- **Heavy sets (348C):** memory $O(m\cdot T/B)$ for the intersection table; time per operation $O(B + T/B)$.
- **Values of $\lfloor n/k \rfloor$:** at most $2\sqrt n$ distinct values; for $k > \sqrt n$ the value is $< \sqrt n$.
- **Mo with updates:** block $n^{2/3}$, time $O(n^{5/3})$ for $n$ queries and updates.

## 3. Implementation (C++ and Java)

The techniques here are patterns rather than library code; each worked example below is a complete, tested reference program for one pattern:

| Pattern | Example |
|---|---|
| split by step/modulus | Example 1 |
| heavy/light by degree (orientation) | Example 2 |
| few distinct lengths | Example 3 |
| buffer + periodic rebuild | Example 4 |
| heavy/light sets with an intersection table | Example 5 |

A generic skeleton of the periodic-rebuild pattern:

```text
built = structure over all updates up to now       # exact for them
buffer = []
on update u:   buffer.append(u); if len(buffer) == B: built = rebuild(built, buffer); buffer = []
on query q:    answer = built.answer(q) combined with brute(q, u) for u in buffer
```

## 4. Recognising the pattern

- **Two parameters whose product is bounded** ($x \cdot \#\text{steps} \le N$, $\deg \cdot \#\text{heavy} \le 2m$, size $\cdot$ count $\le T$) → threshold on one of them.
- **"Sum of sizes $\le 10^5$ / $2\cdot10^5$"** in a statement about many sets, patterns or components → heavy/light, or few distinct sizes.
- **Updates and queries interleaved, a static structure is easy, a dynamic one is hard** → buffer + periodic rebuild.
- **$n, q \le 10^5$ with a 3–5 s limit** and no obvious $\log$ structure → the intended solution is often $O(n\sqrt n)$.
- **"For every $k$ from 1 to $n$ compute …"** with answers $\le n/k$ → few distinct answers.
- **Graph problems on "pairs of adjacent vertices with something in common"** → degree orientation.
- Commonly confused: Mo's algorithm (reorders *range queries*) vs. the techniques here (split *objects* or *time*). Both are offline-friendly, but heavy/light and rebuild work online too.

## 5. Worked examples (graded)

### Example 1 — Sums over residue classes with point updates  ·  ★ 2100

- **Source:** [CF 1207F · Remainder Problem](https://codeforces.com/problemset/problem/1207/F) — 2100
- **Difficulty:** 2100
- **Problem:** An array of $N = 500000$ zeros. $q \le 5\cdot10^5$ operations: `1 x y` adds $y$ ($|y| \le 1000$) to $a_x$; `2 x y` ($0 \le y < x$) prints the sum of $a_i$ over $1 \le i \le N$ with $i \bmod x = y$.
- **Thinking from first principles:** Answering type 2 by walking costs $N/x$ — terrible for $x = 1$, great for large $x$. Precomputing all answers costs $O(N)$ per update for all moduli — terrible, but for moduli $\le B$ only it is $O(B)$ per update. So: small moduli by table, large moduli by walking; balance $B = N/B$, $B \approx 707$.

<details><summary>Solution</summary>

`small[k][r]` for $k \le K = 708$. Update: $a_x \mathrel{+}= y$ and `small[k][x % k] += y` for all $k \le K$. Query with $x \le K$: read the table. Query with $x > K$: sum $a_y, a_{y+x}, \dots$ (starting at $x$ when $y = 0$, since indices start at 1) — fewer than $N/K \approx 707$ terms. $O(q\sqrt N)$ total, $O(K^2)$ extra memory. All sums fit in 32 bits here (the total of all updates is at most $5\cdot10^8$ in absolute value), but the walk uses 64 bits anyway. About 1.4 s for $5\cdot10^5$ operations in either language on the test machine.

```cpp
#include <bits/stdc++.h>
using namespace std;

const int N = 500000, K = 708;                 // K ~ sqrt(N)

int a[N + 1];
int small_[K + 1][K + 1];                       // small_[k][r] = sum of a[i] with i % k == r, for k <= K

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> q;
    while (q--) {
        int t, x, y;
        cin >> t >> x >> y;
        if (t == 1) {
            a[x] += y;
            for (int k = 1; k <= K; k++) small_[k][x % k] += y;   // O(K) per update
        } else if (x <= K) {
            cout << small_[x][y] << '\n';                        // O(1) for small moduli
        } else {
            long long s = 0;                                     // at most N / x < K terms
            for (int i = (y == 0 ? x : y); i <= N; i += x) s += a[i];
            cout << s << '\n';
        }
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final int N = 500000, K = 708;
        FastReader in = new FastReader(System.in);
        int q = in.nextInt();
        int[] a = new int[N + 1];
        int[][] small = new int[K + 1][];
        for (int k = 1; k <= K; k++) small[k] = new int[k];
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int t = in.nextInt(), x = in.nextInt(), y = in.nextInt();
            if (t == 1) {
                a[x] += y;
                for (int k = 1; k <= K; k++) small[k][x % k] += y;
            } else if (x <= K) {
                sb.append(small[x][y]).append('\n');
            } else {
                long s = 0;
                for (int i = (y == 0 ? x : y); i <= N; i += x) s += a[i];
                sb.append(s).append('\n');
            }
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        int nextInt() throws IOException {
            int ret = 0, b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
    }
}
```

</details>

<!-- test
in:
6
1 3 4
2 3 0
2 4 3
1 4 -4
2 1 0
2 1000 3
out:
4
4
0
4
-->
<!-- test
in:
4
1 500000 7
2 500000 0
2 709 155
2 710 0
out:
7
7
0
-->

### Example 2 — Counting triangles in $O(m\sqrt m)$  ·  ★ ≈2100 (est.)

- **Source:** Original problem (the same enumeration underlies [LC 1761 · Minimum Degree of a Connected Trio in a Graph](https://leetcode.com/problems/minimum-degree-of-a-connected-trio-in-a-graph/) — Hard).
- **Difficulty:** ≈2100 (est.)
- **Problem:** An undirected graph with $n, m \le 2\cdot10^5$ (loops and repeated edges may appear and are ignored). Count triangles.
- **Thinking from first principles:** For each vertex, pairs of neighbours cost $\sum \deg^2$ — $m^2$ on a star. Adjacency bitsets cost $n^2/8$ bytes — too much for $n = 2\cdot10^5$. What makes the star bad is one high-degree vertex being the *middle* of many wedges; so never let a high-degree vertex be the middle. Orienting edges "low degree → high degree" bounds every out-degree by $\sqrt{2m}$ (§1.3), and each triangle is found exactly once, from its lowest vertex in the orientation order.

<details><summary>Solution</summary>

Deduplicate edges, compute degrees, orient $u \to v$ if $(\deg u, u) < (\deg v, v)$. For each $u$: mark its out-neighbours with the stamp $u$; for each out-neighbour $v$ and each out-neighbour $w$ of $v$, count $w$ if it is marked. The order "$(\deg, \text{id})$" is a strict total order, so the orientation is acyclic and a triangle $\{x, y, z\}$ with $x < y < z$ in that order is counted once (at $u = x$, $v = y$, $w = z$). $O(m\sqrt m)$ time, $O(n + m)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<pair<int, int>> e;
    for (int i = 0; i < m; i++) {
        int u, v;
        cin >> u >> v;
        u--; v--;
        if (u == v) continue;
        if (u > v) swap(u, v);
        e.push_back({u, v});
    }
    sort(e.begin(), e.end());
    e.erase(unique(e.begin(), e.end()), e.end());          // simple graph
    vector<int> deg(n, 0);
    for (auto [u, v] : e) { deg[u]++; deg[v]++; }
    auto before = [&](int u, int v) { return deg[u] != deg[v] ? deg[u] < deg[v] : u < v; };
    vector<vector<int>> out(n);                             // orient every edge towards the "larger" end
    for (auto [u, v] : e) {
        if (before(u, v)) out[u].push_back(v);
        else out[v].push_back(u);
    }
    vector<int> mark(n, -1);
    long long tri = 0;
    for (int u = 0; u < n; u++) {
        for (int v : out[u]) mark[v] = u;
        for (int v : out[u])
            for (int w : out[v])                            // out-degrees are <= sqrt(2m)
                if (mark[w] == u) tri++;                    // u -> v -> w and u -> w
    }
    cout << tri << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        long[] keys = new long[m];
        int k = 0;
        for (int i = 0; i < m; i++) {
            int u = in.nextInt() - 1, v = in.nextInt() - 1;
            if (u == v) continue;
            if (u > v) { int t = u; u = v; v = t; }
            keys[k++] = (long) u * n + v;
        }
        keys = Arrays.copyOf(keys, k);
        SplittableRandom rng = new SplittableRandom(System.nanoTime());
        for (int i = k - 1; i > 0; i--) { int j = rng.nextInt(i + 1); long t = keys[i]; keys[i] = keys[j]; keys[j] = t; }
        Arrays.sort(keys);
        int me = 0;
        for (int i = 0; i < k; i++) if (me == 0 || keys[me - 1] != keys[i]) keys[me++] = keys[i];
        int[] deg = new int[n], eu = new int[me], ev = new int[me];
        for (int i = 0; i < me; i++) { eu[i] = (int) (keys[i] / n); ev[i] = (int) (keys[i] % n); deg[eu[i]]++; deg[ev[i]]++; }
        int[] start = new int[n + 1], from = new int[me], to = new int[me];
        for (int i = 0; i < me; i++) {
            int u = eu[i], v = ev[i];
            boolean uFirst = deg[u] != deg[v] ? deg[u] < deg[v] : u < v;
            from[i] = uFirst ? u : v; to[i] = uFirst ? v : u;
            start[from[i] + 1]++;
        }
        for (int i = 0; i < n; i++) start[i + 1] += start[i];
        int[] adj = new int[me], fill = Arrays.copyOf(start, n + 1);
        for (int i = 0; i < me; i++) adj[fill[from[i]]++] = to[i];    // CSR out-lists
        int[] mark = new int[n];
        Arrays.fill(mark, -1);
        long tri = 0;
        for (int u = 0; u < n; u++) {
            for (int p = start[u]; p < start[u + 1]; p++) mark[adj[p]] = u;
            for (int p = start[u]; p < start[u + 1]; p++) {
                int v = adj[p];
                for (int r = start[v]; r < start[v + 1]; r++) if (mark[adj[r]] == u) tri++;
            }
        }
        System.out.println(tri);
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        int nextInt() throws IOException {
            int ret = 0, b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
    }
}
```

</details>

<!-- test
in:
4 6
1 2
2 3
3 1
1 4
2 4
3 4
out:
4
-->
<!-- test
in:
5 6
1 2
2 1
2 3
1 3
3 3
4 5
out:
1
-->
<!-- test
in:
4 3
1 2
1 3
1 4
out:
0
-->

### Example 3 — Occurrence counts for many patterns, grouped by length  ·  ★ ≈2200 (est.)

- **Source:** Original problem (the grouping idea is the heart of [CF 710F · String Set Queries](https://codeforces.com/problemset/problem/710/F) — 2400).
- **Difficulty:** ≈2200 (est.)
- **Problem:** A text $T$ ($|T| \le 10^5$, lowercase) and $q$ patterns with total length $L \le 10^5$. For each pattern print the number of (possibly overlapping) occurrences in $T$.
- **Thinking from first principles:** Matching each pattern separately (KMP) is $O(q|T| + L)$, up to $10^{10}$. The patterns of one length $\ell$ can all be compared with every window of length $\ell$ at once by hashing: one pass computes all window hashes. How many passes? One per *distinct* length, and lengths sum to at most $L$, so there are at most $\sqrt{2L} \approx 447$ of them: $O(|T|\sqrt L \log)$ with sorted pattern hashes and binary search. Collisions: windows × patterns comparisons $\le |T| \cdot q$, so use the $2^{61}-1$ modulus with a random base ([randomised algorithms and hashing](04-randomized-algorithms-and-hashing.md)).

<details><summary>Solution</summary>

Prefix hashes of $T$ modulo $2^{61}-1$ with a random base. Group pattern indices by length (lengths above $|T|$ answer 0). For each length: hash the patterns, sort and deduplicate the hashes, scan all windows of $T$ of that length and increment the count of a matching hash (binary search), then read each pattern's count. The multiplication mod $2^{61}-1$ uses `__int128` in C++ and `Math.multiplyHigh` in Java with the identity $2^{61} \equiv 1$. About 0.6 s (C++) and 1.2 s (Java) for the worst case of $\approx 447$ distinct lengths.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ull = unsigned long long;

const ull MOD = (1ULL << 61) - 1;
ull mulmod(ull a, ull b) {                      // (a * b) mod 2^61 - 1 without division
    __uint128_t c = (__uint128_t)a * b;
    ull r = (ull)(c & MOD) + (ull)(c >> 61);    // 2^61 = 1 (mod 2^61 - 1)
    return r >= MOD ? r - MOD : r;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string T;
    int q;
    cin >> T >> q;
    int n = T.size();
    vector<string> P(q);
    for (auto& p : P) cin >> p;
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    ull base = rng() % (MOD - 1000) + 500;      // random base: no precomputed anti-hash test works
    vector<ull> h(n + 1, 0), pw(n + 1, 1);
    for (int i = 0; i < n; i++) {
        h[i + 1] = (mulmod(h[i], base) + (ull)T[i]) % MOD;
        pw[i + 1] = mulmod(pw[i], base);
    }
    auto sub = [&](int l, int len) { return (h[l + len] + MOD - mulmod(h[l], pw[len])) % MOD; };
    map<int, vector<int>> byLen;                 // only sqrt(2L) distinct lengths can exist
    for (int i = 0; i < q; i++) if ((int)P[i].size() <= n) byLen[P[i].size()].push_back(i);
    vector<long long> ans(q, 0);
    for (auto& [len, ids] : byLen) {
        vector<ull> hs;
        for (int i : ids) {
            ull x = 0;
            for (char c : P[i]) x = (mulmod(x, base) + (ull)c) % MOD;
            hs.push_back(x);
        }
        vector<ull> keys = hs;
        sort(keys.begin(), keys.end());
        keys.erase(unique(keys.begin(), keys.end()), keys.end());
        vector<long long> cnt(keys.size(), 0);
        for (int s = 0; s + len <= n; s++) {     // one O(n) scan per distinct length
            ull x = sub(s, len);
            auto it = lower_bound(keys.begin(), keys.end(), x);
            if (it != keys.end() && *it == x) cnt[it - keys.begin()]++;
        }
        for (size_t t = 0; t < ids.size(); t++)
            ans[ids[t]] = cnt[lower_bound(keys.begin(), keys.end(), hs[t]) - keys.begin()];
    }
    for (auto x : ans) cout << x << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static final long MOD = (1L << 61) - 1;

    static long mulmod(long a, long b) {        // a, b < 2^61
        long hi = Math.multiplyHigh(a, b), lo = a * b;
        long r = (lo & MOD) + (lo >>> 61) + (hi << 3);   // 2^64 = 8 (mod 2^61 - 1)
        r = (r & MOD) + (r >>> 61);
        return r >= MOD ? r - MOD : r;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        String T = in.next();
        int n = T.length();
        int q = Integer.parseInt(in.next());
        String[] P = new String[q];
        for (int i = 0; i < q; i++) P[i] = in.next();
        SplittableRandom rng = new SplittableRandom(System.nanoTime());
        long base = 500 + rng.nextLong(MOD - 1000);
        long[] h = new long[n + 1], pw = new long[n + 1];
        pw[0] = 1;
        for (int i = 0; i < n; i++) {
            h[i + 1] = (mulmod(h[i], base) + T.charAt(i)) % MOD;
            pw[i + 1] = mulmod(pw[i], base);
        }
        TreeMap<Integer, List<Integer>> byLen = new TreeMap<>();
        for (int i = 0; i < q; i++) if (P[i].length() <= n) byLen.computeIfAbsent(P[i].length(), z -> new ArrayList<>()).add(i);
        long[] ans = new long[q];
        for (Map.Entry<Integer, List<Integer>> en : byLen.entrySet()) {
            int len = en.getKey();
            List<Integer> ids = en.getValue();
            long[] hs = new long[ids.size()];
            for (int t = 0; t < hs.length; t++) {
                long x = 0;
                for (char c : P[ids.get(t)].toCharArray()) x = (mulmod(x, base) + c) % MOD;
                hs[t] = x;
            }
            long[] keys = hs.clone();
            Arrays.sort(keys);                     // hash values under a random base: not attackable
            int u = 0;
            for (int t = 0; t < keys.length; t++) if (u == 0 || keys[u - 1] != keys[t]) keys[u++] = keys[t];
            long[] cnt = new long[u];
            for (int s = 0; s + len <= n; s++) {   // one O(n) scan per distinct length
                long x = h[s + len] - mulmod(h[s], pw[len]);
                if (x < 0) x += MOD;
                int idx = Arrays.binarySearch(keys, 0, u, x);
                if (idx >= 0) cnt[idx]++;
            }
            for (int t = 0; t < hs.length; t++) ans[ids.get(t)] = cnt[Arrays.binarySearch(keys, 0, u, hs[t])];
        }
        StringBuilder sb = new StringBuilder();
        for (long x : ans) sb.append(x).append('\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        String next() throws IOException {
            StringBuilder sb = new StringBuilder();
            int b = read();
            while (b <= ' ') b = read();
            while (b > ' ') { sb.append((char) b); b = read(); }
            return sb.toString();
        }
    }
}
```

</details>

<!-- test
in:
abababa
4
aba
bab
abababab
a
out:
3
2
0
4
-->
<!-- test
in:
a
1
a
out:
1
-->

### Example 4 — Nearest painted vertex with periodic rebuilds  ·  ★ 2400

- **Source:** [CF 342E · Xenia and Tree](https://codeforces.com/problemset/problem/342/E) — 2400
- **Difficulty:** 2400
- **Problem:** A tree with $n \le 10^5$ vertices; vertex 1 is red, the rest blue. $m \le 10^5$ operations: paint a vertex red, or print the distance from a vertex to the nearest red vertex.
- **Thinking from first principles:** If no painting happened, one multi-source BFS from the red set answers every query in $O(1)$. Repainting after every update is $O(n)$ per update. Answering by checking every red vertex is $O(\#\text{red})$ per query. Neither alone works; combined they do: keep the BFS distances for the red vertices known at the last rebuild, and check the at most $B$ vertices painted since then with an $O(1)$ LCA distance. Rebuild after $B$ paints. $R = n$, $c = O(1)$ ⇒ $B \approx \sqrt n$. (Centroid decomposition solves it in $O(\log n)$ per operation — see [centroid decomposition](../10-Trees/05-centroid-decomposition.md); the rebuild trick is the one that generalises to structures without such a decomposition.)

<details><summary>Solution</summary>

LCA in $O(1)$: in DFS preorder, the LCA of $u \ne v$ with $\text{tin}_u < \text{tin}_v$ is the parent of the shallowest vertex at positions $\text{tin}_u+1..\text{tin}_v$, so a sparse table over "parent of the vertex at position $i$", compared by depth, answers it with two lookups. The rebuild is a BFS that starts from the buffered vertices with distance 0 and only relaxes strictly improving distances (old distances are already correct for the old red set). With $B = 320$: about $n \cdot m/B \approx 3\cdot10^7$ BFS steps and $m \cdot B \approx 3\cdot10^7$ LCA queries; 0.7 s (C++) and 1.1 s (Java) on the test machine. With binary lifting instead of $O(1)$ LCA the same code took 3.2 s — the LCA cost $c$ sits inside the balancing formula, so it matters.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<vector<int>> g, sp;
vector<int> dep, par, tin, dist_;

// O(1) LCA: in DFS preorder, the LCA of u != v (tin[u] < tin[v]) is the parent of the
// shallowest vertex among positions tin[u]+1 .. tin[v]. sp = sparse table of those parents.
int better(int a, int b) { return dep[a] < dep[b] ? a : b; }
int lca(int u, int v) {
    if (u == v) return u;
    int l = tin[u], r = tin[v];
    if (l > r) swap(l, r);
    l++;
    int k = __lg(r - l + 1);
    return better(sp[k][l], sp[k][r - (1 << k) + 1]);
}
int treeDist(int u, int v) { return dep[u] + dep[v] - 2 * dep[lca(u, v)]; }

void rebuild(vector<int>& pending) {           // multi-source BFS from the newly painted vertices
    queue<int> q;
    for (int v : pending) if (dist_[v] != 0) { dist_[v] = 0; q.push(v); }
    while (!q.empty()) {
        int u = q.front(); q.pop();
        for (int w : g[u]) if (dist_[w] > dist_[u] + 1) { dist_[w] = dist_[u] + 1; q.push(w); }
    }
    pending.clear();
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int m;
    cin >> n >> m;
    g.assign(n + 1, {});
    for (int i = 0; i < n - 1; i++) {
        int a, b;
        cin >> a >> b;
        g[a].push_back(b); g[b].push_back(a);
    }
    dep.assign(n + 1, 0); par.assign(n + 1, 0); tin.assign(n + 1, 0);
    vector<int> order, st = {1};                // iterative DFS preorder (subtrees stay contiguous)
    par[1] = 1;
    while (!st.empty()) {
        int u = st.back(); st.pop_back();
        tin[u] = order.size(); order.push_back(u);
        for (int w : g[u]) if (w != par[u]) { par[w] = u; dep[w] = dep[u] + 1; st.push_back(w); }
    }
    int LOG = __lg(max(n, 1)) + 1;
    sp.assign(LOG, vector<int>(n));
    for (int i = 0; i < n; i++) sp[0][i] = par[order[i]];
    for (int k = 1; k < LOG; k++)
        for (int i = 0; i + (1 << k) <= n; i++) sp[k][i] = better(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
    dist_.assign(n + 1, INT_MAX);
    vector<int> pending = {1};                  // vertex 1 starts red
    rebuild(pending);
    const int B = 320;                          // rebuild after B paints: O(n) per rebuild, O(B) per query
    while (m--) {
        int t, v;
        cin >> t >> v;
        if (t == 1) {
            pending.push_back(v);
            if ((int)pending.size() >= B) rebuild(pending);
        } else {
            int best = dist_[v];                // exact for the red vertices up to the last rebuild
            for (int p : pending) best = min(best, treeDist(v, p));
            cout << best << '\n';
        }
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int n;
    static int[] head, nxt, to, dep, par, tin, dist, queue;
    static int[][] sp;

    static int better(int a, int b) { return dep[a] < dep[b] ? a : b; }
    static int lca(int u, int v) {
        if (u == v) return u;
        int l = tin[u], r = tin[v];
        if (l > r) { int t = l; l = r; r = t; }
        l++;
        int k = 31 - Integer.numberOfLeadingZeros(r - l + 1);
        return better(sp[k][l], sp[k][r - (1 << k) + 1]);
    }

    static void rebuild(int[] pending, int cnt) {
        int qh = 0, qt = 0;
        for (int i = 0; i < cnt; i++) { int v = pending[i]; if (dist[v] != 0) { dist[v] = 0; queue[qt++] = v; } }
        while (qh < qt) {
            int u = queue[qh++];
            for (int e = head[u]; e != -1; e = nxt[e]) {
                int w = to[e];
                if (dist[w] > dist[u] + 1) { dist[w] = dist[u] + 1; queue[qt++] = w; }
            }
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        n = in.nextInt();
        int m = in.nextInt();
        head = new int[n + 1]; nxt = new int[2 * n]; to = new int[2 * n];
        Arrays.fill(head, -1);
        for (int i = 0, e = 0; i < n - 1; i++) {
            int a = in.nextInt(), b = in.nextInt();
            to[e] = b; nxt[e] = head[a]; head[a] = e++;
            to[e] = a; nxt[e] = head[b]; head[b] = e++;
        }
        dep = new int[n + 1]; par = new int[n + 1]; tin = new int[n + 1]; queue = new int[n + 1];
        int[] order = new int[n], stack = new int[n];
        int top = 0, cnt = 0;
        stack[top++] = 1; par[1] = 1;
        while (top > 0) {                       // iterative DFS preorder
            int u = stack[--top];
            tin[u] = cnt; order[cnt++] = u;
            for (int e = head[u]; e != -1; e = nxt[e]) {
                int w = to[e];
                if (w != par[u]) { par[w] = u; dep[w] = dep[u] + 1; stack[top++] = w; }
            }
        }
        int LOG = 32 - Integer.numberOfLeadingZeros(Math.max(n, 1));
        sp = new int[LOG][n];
        for (int i = 0; i < n; i++) sp[0][i] = par[order[i]];
        for (int k = 1; k < LOG; k++)
            for (int i = 0; i + (1 << k) <= n; i++) sp[k][i] = better(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
        dist = new int[n + 1];
        Arrays.fill(dist, Integer.MAX_VALUE);
        final int B = 320;
        int[] pending = new int[B];
        int pc = 0;
        pending[pc++] = 1;
        rebuild(pending, pc);
        pc = 0;
        StringBuilder sb = new StringBuilder();
        while (m-- > 0) {
            int t = in.nextInt(), v = in.nextInt();
            if (t == 1) {
                pending[pc++] = v;
                if (pc == B) { rebuild(pending, pc); pc = 0; }
            } else {
                int best = dist[v];
                for (int i = 0; i < pc; i++) {
                    int p = pending[i];
                    best = Math.min(best, dep[v] + dep[p] - 2 * dep[lca(v, p)]);
                }
                sb.append(best).append('\n');
            }
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        int nextInt() throws IOException {
            int ret = 0, b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
    }
}
```

</details>

<!-- test
in:
5 7
1 2
2 3
2 4
4 5
2 1
2 5
1 3
2 5
1 4
2 5
2 3
out:
0
3
3
1
0
-->
<!-- test
in:
1 1
2 1
out:
0
-->

### Example 5 — Add to a set, sum over a set  ·  ★ 2500

- **Source:** [CF 348C · Subset Sums](https://codeforces.com/problemset/problem/348/C) — 2500
- **Difficulty:** 2500
- **Problem:** An array $a_1..a_n$ and $m$ sets of indices with total size $T \le 10^5$ ($n, m, q \le 10^5$, $|a_i|, |x| \le 10^8$). Queries: `? k` prints the sum of $a_i$ over $i \in S_k$; `+ k x` adds $x$ to every $a_i$ with $i \in S_k$.
- **Thinking from first principles:** Doing both operations element by element is $O(|S_k|)$ — fine for small sets, $10^{10}$ if one big set is hit repeatedly. Large sets are few (at most $T/B$). For them we can afford a table of intersection sizes with **every** set ($O(T)$ per large set to build). Then: an update to a large set is just a lazy number; its effect on any query set $S_j$ is $\text{lazy}_h \cdot |S_h \cap S_j|$. An update to a small set touches its elements directly and informs every large set's stored sum through the table.

<details><summary>Solution</summary>

$B = \sqrt{2T}$. For each heavy $h$: `base[h]` = current sum of its elements counting only light updates; `lazy[h]` = total added to $h$ by heavy updates; `inter[h][j]` for all $j$. Light update $(k, x)$: $a_i \mathrel{+}= x$ for $i \in S_k$, and `base[h] += x * inter[h][k]` for every heavy $h$. Heavy update: `lazy[h] += x`. Query $k$: (light: $\sum_{i \in S_k} a_i$; heavy: `base[k]`) $+ \sum_h \text{lazy}_h \cdot \text{inter}[h][k]$. Every operation is $O(B + T/B) = O(\sqrt T)$; the table has $(T/B)\cdot m \approx 2.2\cdot10^7$ entries (90 MB as `int`). Sums reach about $10^{18}$: 64-bit. The stress test also ran with $B = 1$ (every set heavy) to exercise the heavy paths on small inputs.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, q;
    cin >> n >> m >> q;
    vector<ll> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    vector<vector<int>> S(m);
    int total = 0;
    for (auto& s : S) {
        int k;
        cin >> k;
        s.resize(k);
        for (auto& x : s) cin >> x;
        total += k;
    }
    int B = max(1, (int)sqrt((double)total * 2));        // heavy: size > B, so at most total / B heavy sets
    vector<int> heavy, hid(m, -1);
    for (int j = 0; j < m; j++) if ((int)S[j].size() > B) { hid[j] = heavy.size(); heavy.push_back(j); }
    int H = heavy.size();
    vector<vector<int>> inter(H, vector<int>(m, 0));    // inter[h][j] = |S_heavy[h] ∩ S_j|
    vector<char> mark(n + 1, 0);
    vector<ll> base(H, 0), lazy(H, 0);                    // base: sum seen through light updates
    for (int h = 0; h < H; h++) {
        for (int x : S[heavy[h]]) { mark[x] = 1; base[h] += a[x]; }
        for (int j = 0; j < m; j++) {
            int c = 0;
            for (int x : S[j]) c += mark[x];
            inter[h][j] = c;
        }
        for (int x : S[heavy[h]]) mark[x] = 0;
    }
    while (q--) {
        char op;
        int k;
        cin >> op >> k;
        k--;
        if (op == '+') {
            ll x;
            cin >> x;
            if (hid[k] >= 0) lazy[hid[k]] += x;          // heavy update: O(1), applied lazily
            else {
                for (int i : S[k]) a[i] += x;            // light update: touch <= B elements
                for (int h = 0; h < H; h++) base[h] += x * inter[h][k];
            }
        } else {
            ll s = hid[k] >= 0 ? base[hid[k]] : 0;
            if (hid[k] < 0) for (int i : S[k]) s += a[i];
            for (int h = 0; h < H; h++) s += lazy[h] * inter[h][k];   // pending heavy updates
            cout << s << '\n';
        }
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt(), q = in.nextInt();
        long[] a = new long[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextLong();
        int[][] S = new int[m][];
        int total = 0;
        for (int j = 0; j < m; j++) {
            int k = in.nextInt();
            S[j] = new int[k];
            for (int t = 0; t < k; t++) S[j][t] = in.nextInt();
            total += k;
        }
        int B = Math.max(1, (int) Math.sqrt(2.0 * total));
        int[] hid = new int[m];
        int H = 0;
        for (int j = 0; j < m; j++) hid[j] = S[j].length > B ? H++ : -1;
        int[] heavy = new int[H];
        for (int j = 0; j < m; j++) if (hid[j] >= 0) heavy[hid[j]] = j;
        int[][] inter = new int[H][m];
        boolean[] mark = new boolean[n + 1];
        long[] base = new long[H], lazy = new long[H];
        for (int h = 0; h < H; h++) {
            for (int x : S[heavy[h]]) { mark[x] = true; base[h] += a[x]; }
            for (int j = 0; j < m; j++) {
                int c = 0;
                for (int x : S[j]) if (mark[x]) c++;
                inter[h][j] = c;
            }
            for (int x : S[heavy[h]]) mark[x] = false;
        }
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            char op = in.nextChar();
            int k = in.nextInt() - 1;
            if (op == '+') {
                long x = in.nextLong();
                if (hid[k] >= 0) lazy[hid[k]] += x;
                else {
                    for (int i : S[k]) a[i] += x;
                    for (int h = 0; h < H; h++) base[h] += x * inter[h][k];
                }
            } else {
                long s = 0;
                if (hid[k] >= 0) s = base[hid[k]];
                else for (int i : S[k]) s += a[i];
                for (int h = 0; h < H; h++) s += lazy[h] * inter[h][k];
                sb.append(s).append('\n');
            }
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        char nextChar() throws IOException {
            int b = read();
            while (b <= ' ') b = read();
            return (char) b;
        }
        long nextLong() throws IOException {
            long ret = 0;
            int b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
4 2 4
1 2 3 4
2 1 2
3 2 3 4
? 1
+ 2 10
? 1
? 2
out:
3
13
39
-->
<!-- test
in:
3 3 5
-100000000 100000000 0
3 1 2 3
1 3
2 1 3
+ 1 -5
? 2
+ 3 7
? 3
? 1
out:
-5
-99999996
-1
-->

All five programs were stress-tested against brute force (dictionary sums, triple loops, naive substring counting, BFS per query, direct set updates) on 200–250 random cases each; Examples 4 and 5 were also compiled with tiny thresholds ($B = 2$ and $B = 1$) so that the rebuild and heavy-set code paths run on small inputs.

## 6. Tricks, pitfalls and things to remember

1. **Derive $B$, then tune it.** The formula gives the order of magnitude; the constant factors of the two sides differ (cache misses, LCA cost), so try $B/2$ and $2B$ on a maximum test. The optimum is flat.
2. **Put the per-object cost into the formula.** In Example 4 an $O(\log n)$ LCA moves the optimum to $B \approx \sqrt{n/\log n}$ and doubles the running time; an $O(1)$ LCA keeps $B \approx \sqrt n$.
3. **Memory of heavy tables:** $(T/B) \times m$ entries. Increase $B$ (fewer heavy objects) when memory is tight; the time cost grows only linearly in $B$.
4. **Do not double count between sides.** In Example 5 a heavy update must not also be applied to `base`; a light update must update `base` of every heavy set but never `lazy`.
5. **Residues and 1-based indices.** For $y = 0$ the first index in $[1, N]$ is $x$, not $0$.
6. **Static `int small[K+1][K+1]`** is fine globally in C++; in Java allocate jagged rows `new int[k]` to halve the memory.
7. **Rebuild the right thing.** A periodic rebuild must produce exactly the state "all updates so far"; incremental BFS from the buffered sources works only because distances never increase.
8. **Orientation ties.** Orient by $(\deg, \text{id})$, not by degree alone, or equal-degree triangles are counted 0 or 2 times.
9. **Deduplicate edges** before computing degrees for the orientation argument; multi-edges inflate degrees and break the count.
10. **Hash modulus for many comparisons:** $|T| \cdot \#\text{lengths}$ window hashes are compared against pattern hashes; use $2^{61}-1$ and a random base.
11. **Java:** avoid `ArrayList<Integer>` adjacency for $2\cdot10^5$ edges; use CSR arrays (`start[]`, `adj[]`) as in Example 2.

## 7. Going further (toward 2400–2600+)

- **Memoisation with a square-root bound:** in [CF 1806E · Tree Master](https://codeforces.com/problemset/problem/1806/E) — 2200, memoising pairs of vertices at equal depth is fast: with $c_d$ vertices at depth $d$, at most $\min(c_d^2, n)$ distinct pairs per depth are ever touched, and $\sum_d \min(c_d^2, n) = O(n\sqrt n)$ (depths with $c_d \le \sqrt n$ contribute $\le \sqrt n \sum c_d$; there are at most $\sqrt n$ other depths).
- **Split by value magnitude:** [CF 1822G2 · Magic Triples (Hard Version)](https://codeforces.com/problemset/problem/1822/G2) — 2200 splits on the size of the middle value (iterate the ratio for large values, divisors for small ones).
- **Split by difference:** [CF 1654E · Arithmetic Operations](https://codeforces.com/problemset/problem/1654/E) — 2300 treats small common differences by counting $a_i - i d$ and large ones by looking only $O(n/d)$ positions ahead.
- **Frequency threshold:** [CF 1446D2 · Frequency Problem (Hard Version)](https://codeforces.com/problemset/problem/1446/D2) — 3000.
- **Few distinct answers:** [CF 1039D · You Are Given a Tree](https://codeforces.com/problemset/problem/1039/D) — 2800.
- **Blocks with jump pointers that stop changing:** [CF 1491H · Yuezheng Ling and Dynamic Tree](https://codeforces.com/problemset/problem/1491/H) — 3400 — after about $\sqrt n$ full-block updates every parent leaves its block, so full blocks become lazy.
- **Offline Mo with updates and Mo on trees:** [sqrt decomposition and Mo](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md).

## 8. Practice ladder

2000–2200
- [ ] [CF 797E · Array Queries](https://codeforces.com/problemset/problem/797/E) — 2000 — small $k$ by DP, large $k$ by simulation
- [ ] [CF 103D · Time to Raid Cowavans](https://codeforces.com/problemset/problem/103/D) — 2100 — split by step, offline
- [ ] [CF 1207F · Remainder Problem](https://codeforces.com/problemset/problem/1207/F) — 2100 — Example 1
- [ ] [CF 785E · Anton and Permutation](https://codeforces.com/problemset/problem/785/E) — 2200 — blocks with sorted contents
- [ ] [CF 1580C · Train Maintenance](https://codeforces.com/problemset/problem/1580/C) — 2200 — split by period
- [ ] [CF 1806E · Tree Master](https://codeforces.com/problemset/problem/1806/E) — 2200 — memoisation with a sqrt bound
- [ ] [CF 1822G2 · Magic Triples (Hard Version)](https://codeforces.com/problemset/problem/1822/G2) — 2200 — threshold on the middle value

2300–2500
- [ ] [CF 1654E · Arithmetic Operations](https://codeforces.com/problemset/problem/1654/E) — 2300 — split by difference
- [ ] [CF 342E · Xenia and Tree](https://codeforces.com/problemset/problem/342/E) — 2400 — Example 4
- [ ] [CF 506D · Mr. Kitayuta's Colorful Graph](https://codeforces.com/problemset/problem/506/D) — 2400 — heavy/light colours
- [ ] [CF 710F · String Set Queries](https://codeforces.com/problemset/problem/710/F) — 2400 — few distinct lengths, online
- [ ] [CF 348C · Subset Sums](https://codeforces.com/problemset/problem/348/C) — 2500 — Example 5
- [ ] [CF 444D · DZY Loves Strings](https://codeforces.com/problemset/problem/444/D) — 2500 — heavy/light by occurrence count

2600+
- [ ] [CF 940F · Machine Learning](https://codeforces.com/problemset/problem/940/F) — 2600 — Mo with updates
- [ ] [CF 13E · Holes](https://codeforces.com/problemset/problem/13/E) — 2700 — blocks with exit pointers
- [ ] [CF 455D · Serega and Fun](https://codeforces.com/problemset/problem/455/D) — 2700 — blocks of deques, periodic rebuild
- [ ] [CF 1039D · You Are Given a Tree](https://codeforces.com/problemset/problem/1039/D) — 2800 — few distinct answers
- [ ] [CF 1446D2 · Frequency Problem (Hard Version)](https://codeforces.com/problemset/problem/1446/D2) — 3000 — heavy values
- [ ] [CF 1491H · Yuezheng Ling and Dynamic Tree](https://codeforces.com/problemset/problem/1491/H) — 3400 — blocks that stabilise

## 9. LeetCode / FAANG cross-reference

- [LC 1761 · Minimum Degree of a Connected Trio in a Graph](https://leetcode.com/problems/minimum-degree-of-a-connected-trio-in-a-graph/) — Hard — triangle enumeration; the degree orientation is the scalable version.
- [LC 1157 · Online Majority Element In Subarray](https://leetcode.com/problems/online-majority-element-in-subarray/) — Hard — heavy values (frequency $\ge \sqrt n$) can be precomputed with prefix counts; light ones checked by brute force (or the random sampling of the previous file).
- [LC 1906 · Minimum Absolute Difference Queries](https://leetcode.com/problems/minimum-absolute-difference-queries/) — Medium — values $\le 100$: prefix counts per value; the "small domain" end of the same trade-off.

Rare in interviews beyond these: interviewers expect $O(n\log n)$ structures, and square-root solutions need a constraint-driven argument that interviews do not usually provide.

## 10. Self-check

1. State the balancing rule and apply it to "update $O(B)$, query $O(N/B)$".
2. Why is the out-degree at most $\sqrt{2m}$ after orienting edges by $(\deg, \text{id})$?
3. Why are there at most $\sqrt{2L}$ distinct pattern lengths?
4. In the periodic-rebuild pattern, what are $R$ and $c$ for Xenia and Tree, and what $B$ follows?
5. In Subset Sums, what exactly does `base[h]` contain, and why must heavy updates not change it?
6. A function $f(k) \le n/k$ is non-increasing. How many distinct values can it take, and how would you compute all of them?
7. Why does the Remainder Problem start the walk at $x$ when $y = 0$?
8. What breaks if you orient edges by degree only?

<details><summary>Answers</summary>

1. Minimise $aB + b/B$: $B = \sqrt{b/a}$. With $a = 1$, $b = N$: $B = \sqrt N$, $O(\sqrt N)$ per operation.
2. Low-degree vertices: out-degree $\le$ degree $\le \sqrt{2m}$. High-degree vertices point only to vertices of even higher degree, and fewer than $\sqrt{2m}$ vertices have degree above $\sqrt{2m}$.
3. $k$ distinct positive lengths sum to at least $k(k+1)/2$, which must be $\le L$.
4. $R = n$ (one BFS), $c = O(1)$ (LCA distance per buffered vertex), so $B = \sqrt n$.
5. The sum of $a_i$ over $S_h$ including the initial values and all *light* updates; heavy updates are added at query time through `lazy` × intersection, so adding them to `base` would count them twice.
6. At most $2\sqrt n$: values for $k \le \sqrt n$ plus values $< \sqrt n$ for larger $k$. Compute small $k$ directly; for each possible value binary search its range of $k$ (monotonicity).
7. Indices are $1..N$; index 0 does not exist, and the first positive index with residue 0 is $x$.
8. Equal-degree vertices would need a tie rule; without a strict total order some edges get both or no orientation, triangles are miscounted and the orientation may contain cycles.

</details>
