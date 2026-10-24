# Bitset optimisation

> **Band:** 🟠 2000–2600 (bit-parallel LCS and Four Russians: 🔴) · **Priority:** ⚡ · **FAANG:** low · **Prerequisites:** [bit manipulation](../01-Foundations/03-bit-manipulation.md), [knapsack family](../06-Dynamic-Programming/02-knapsack-family.md), [shortest paths (Floyd–Warshall)](../09-Graphs/02-shortest-paths.md), [complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md)
> **You can say you know this when:** you can look at an $O(n^3)$ or $O(nS)$ boolean algorithm, estimate its cost divided by 64, rewrite its inner loop as word operations in C++ (`std::bitset`, including a run-time-sized variant) and in Java (`long[]` with manual shifts), and know when that turns TLE into AC.

## 1. First principles — why this works

### 1.1 Sixty-four booleans per instruction

A 64-bit register holds 64 booleans, and AND, OR, XOR, shifts and popcount act on all of them in one instruction. So any inner loop of the form

$$\text{for } j \in [0, N):\quad b_j \leftarrow b_j \;\text{op}\; c_{f(j)}$$

where $f$ is a *shift* ($f(j) = j - w$) or the identity, can process 64 values of $j$ per step. The asymptotic complexity is unchanged; the constant drops by about 64 (sometimes more: the data is 8 times smaller in cache, and the compiler may vectorise simple word loops). That is exactly the margin between $10^{10}$ operations (hopeless) and $10^{10}/64 \approx 1.6\cdot10^8$ word operations (well under a second).

What does **not** vectorise: loops with data-dependent jumps ("for each set bit, do something different"), `min`/`+` DP (bitsets hold booleans, not numbers), and random access patterns.

### 1.2 Subset sum: `dp |= dp << w`

Let $R$ be the set of reachable sums, as a bitset with bit $s$ set iff $s \in R$. Adding an item of weight $w$:

$$R' = R \cup (R + w) \quad\Longleftrightarrow\quad b' = b \mid (b \ll w).$$

Each item costs $S/64$ word operations: $O(nS/64)$ total for $n$ items and sums up to $S$. With $n = 2000$ and $S = 10^6$ that is $3\cdot10^7$ word operations instead of $2\cdot10^9$ boolean updates.

### 1.3 Bounded total: at most $\sqrt{2S}$ distinct values

If the item weights sum to $S$, there are at most $\sqrt{2S}$ **distinct** weights, because $1 + 2 + \dots + k = k(k+1)/2 \le S$. Group equal weights: $c$ copies of $v$. Binary splitting replaces them by items $v, 2v, 4v, \dots, 2^{t-1}v, (c - 2^t + 1)v$, and every count $0..c$ is a subset sum of $\{1, 2, \dots, 2^{t-1}, c-2^t+1\}$, so the reachable set is unchanged. The number of items becomes $\sum_v O(\log c_v)$, giving $O\big(\frac{S}{64}\sqrt{S}\log S\big)$ in the worst case, usually much less. (A slicker variant: process weights in increasing order and, while a weight has three or more copies, turn two copies of $v$ into one copy of $2v$; afterwards every weight has at most two copies and there are $O(\sqrt S)$ items: $O(S\sqrt S/64)$.)

This is the standard final step of problems where "the sizes of all parts sum to $n$": cycle lengths of a permutation ([CF 755F · PolandBall and Gifts](https://codeforces.com/problemset/problem/755/F) — 2600) or subtree sizes of a node's children ([CF 1856E2 · PermuTree (hard version)](https://codeforces.com/problemset/problem/1856/E2) — 2700).

### 1.4 Transitive closure in $O(n^3/64)$

Warshall's algorithm: after processing intermediate vertex $k$, `reach[i][j]` is true iff there is a path $i \to j$ whose inner vertices are all $\le k$. The update "if `reach[i][k]` then for all $j$: `reach[i][j] |= reach[k][j]`" is a row OR — one bitset operation. $n = 2000$: $n^3/64 = 1.25\cdot10^8$ word operations.

### 1.5 Intersections: counting common neighbours

$|A \cap B| = \mathrm{popcount}(A \,\&\, B)$, so any "for each pair, count common elements" loop becomes $O(N/64)$ per pair:

- **Triangles in a dense graph:** $\sum_{(u,v) \in E} |N(u) \cap N(v)| = 3T$, cost $O(mn/64)$.
- **Corner rectangles in a 0/1 grid:** a pair of rows with $k$ common 1-columns contributes $\binom{k}{2}$ rectangles, cost $O(n^2 m/64)$.

### 1.6 Estimating whether a bitset solution passes

Write the boolean cost, divide by 64, and compare with roughly $10^9$ simple word operations per second for sequential, in-cache loops in C++ (Java `long[]` loops are typically 1.2–2× slower). Then check memory: $n^2$ bits is $n^2/8$ bytes — $n = 5\cdot10^4$ already needs 312 MB, so large reachability problems process targets in chunks of a few thousand bits.

| Boolean cost | /64 | Verdict (2 s) |
|---|---|---|
| $2000^3 = 8\cdot10^9$ | $1.25\cdot10^8$ | comfortable |
| $10^{10}$ | $1.6\cdot10^8$ | comfortable |
| $5000^3 = 1.25\cdot10^{11}$ | $2\cdot10^9$ | only with a tiny constant |
| $10^5 \cdot 10^6 = 10^{11}$ | $1.6\cdot10^9$ | borderline; reduce the items first (§1.3) |

## 2. Formulas, definitions and identities

- **Shift-or knapsack:** $b \leftarrow b \mid (b \ll w)$; reachable sums after all items $= \{s : b_s = 1\}$. Cost $O(S/64)$ per item.
- **Distinct values with bounded sum:** $\#\{\text{distinct } a_i\} \le \sqrt{2S}$ when $\sum a_i = S$, since $k(k+1)/2 \le S$.
- **Binary splitting:** $c = 1 + 2 + \dots + 2^{t-1} + r$ with $0 \le r < 2^t$; every integer in $[0, c]$ is a subset sum of these parts.
- **Warshall:** $R^{(k)}_{ij} = R^{(k-1)}_{ij} \lor (R^{(k-1)}_{ik} \land R^{(k-1)}_{kj})$; $O(n^3/64)$ with row bitsets.
- **Triangles:** $3T = \sum_{\{u,v\} \in E} \mathrm{popcount}(N(u) \,\&\, N(v))$.
- **Corner rectangles:** $\sum_{r_1 < r_2} \binom{k_{r_1 r_2}}{2}$ with $k = \mathrm{popcount}(\text{row}_{r_1} \,\&\, \text{row}_{r_2})$.
- **Bit-parallel LCS** (🔴, Allison–Dix): let $M_c$ be the bitset of positions of character $c$ in $A$. Start with $S = 0$; for each character $c$ of $B$: $X = M_c \mid S$, $S \leftarrow X \,\&\, \lnot\big(X - ((S \ll 1) \mid 1)\big)$. Then $\mathrm{LCS}(A,B) = \mathrm{popcount}(S)$. The subtraction propagates borrows across words, so it needs a hand-written multiword subtract; cost $O(|A||B|/64)$. (Formula checked against the $O(nm)$ DP on 3000 random string pairs while writing this file.)
- **Matrix product over GF(2):** $C = AB$ with rows as bitsets: $C_i = \bigoplus_{k: A_{ik}=1} B_k$, $O(n^3/64)$.
- **Memory:** a bitset of $N$ bits uses $\lceil N/64\rceil$ words $= N/8$ bytes.

## 3. Implementation (C++ and Java)

C++ `std::bitset<N>` needs a compile-time size. When the needed size depends on the input, instantiate a ladder of sizes with a template and pick the smallest one at run time (each instantiation is a separate function; 16 of them cover up to $2^{21}$ bits). Java has `java.util.BitSet`, but it has no shift-or and allocates on `get(from, to)`, so contest code uses a `long[]` with hand-written shifts.

```cpp
// Fixed size: the size must be a compile-time constant.
const int MAXS = 1000000;
bitset<MAXS + 1> reachableSums(const vector<int>& w) {
    bitset<MAXS + 1> b;
    b[0] = 1;
    for (int x : w) b |= b << x;          // one pass over MAXS/64 words per item
    return b;
}

// Dynamic size: instantiate the smallest power of two above S (64, 128, ..., 2^21).
template <size_t LEN = 64>
vector<char> subsetSums(const vector<int>& w, int S) {
    if constexpr (LEN < (size_t(1) << 21)) {
        if ((size_t)S >= LEN) return subsetSums<LEN * 2>(w, S);
    }
    bitset<LEN> b;
    b[0] = 1;
    for (int x : w) if (x <= S) b |= b << x;
    vector<char> res(S + 1);
    for (int s = 0; s <= S; s++) res[s] = b[s];
    return res;
}

// Useful members: b.count(), b.any(), b.none(), b._Find_first(), b._Find_next(i) (GCC only),
// (b >> l) & mask, and b1 & b2 for intersections.
```

```java
// A minimal bitset on long[] (java.util.BitSet has no shift-or and allocates on every shift).
static final class Bits {
    final long[] w;
    final int n;                                   // number of valid bits
    Bits(int nbits) { n = nbits; w = new long[(nbits + 63) >>> 6]; }
    void set(int i) { w[i >>> 6] |= 1L << i; }    // Java uses only the low 6 bits of the shift count
    boolean get(int i) { return (w[i >>> 6] >>> i & 1L) != 0; }
    // this |= this << s, in place: walk from the top word down so sources are still unmodified
    void orShiftLeft(int s) {
        int ws = s >>> 6, bs = s & 63;
        for (int i = w.length - 1; i >= ws; i--) {
            long v = w[i - ws] << bs;
            if (bs != 0 && i - ws - 1 >= 0) v |= w[i - ws - 1] >>> (64 - bs);
            w[i] |= v;
        }
        int extra = (w.length << 6) - n;           // clear bits past n so they never propagate
        if (extra > 0) w[w.length - 1] &= -1L >>> extra;
    }
    void orWith(Bits o) { for (int i = 0; i < w.length; i++) w[i] |= o.w[i]; }
    int andCount(Bits o) { int c = 0; for (int i = 0; i < w.length; i++) c += Long.bitCount(w[i] & o.w[i]); return c; }
    int count() { int c = 0; for (long x : w) c += Long.bitCount(x); return c; }
}
```

The in-place `orShiftLeft` walks from the highest word down: when word $i$ is written, the source words $i - ws$ and $i - ws - 1$ are lower and therefore still hold their old values. Walking upwards would let the item be used twice (that is the unbounded-knapsack bug in bitset form).

## 4. Recognising the pattern

- **$n \le 2000$–$5000$ with an $O(n^3)$ or $O(n^2 \cdot n)$ boolean algorithm** (closure, "is there a $k$ adjacent to both", matrix over GF(2)) → row bitsets.
- **Subset sum / knapsack *feasibility*** with $nS/64 \le 10^9$ → shift-or. If the problem asks for a *minimum count* or *maximum value*, bitsets do not apply directly.
- **"The sizes sum to $n$"** (components, cycles, subtrees) + feasibility → group equal sizes, binary-split, bitset.
- **"Count pairs/triples with common …"** in dense data → popcount of AND.
- **String matching with wildcards or a small alphabet**, many queries → one bitset of positions per character; the start positions of a pattern are the AND of shifted character bitsets ([CF 914F · Substrings in a String](https://codeforces.com/problemset/problem/914/F) — 3000).
- **The intended complexity looks like $O(n^2)$ with $n = 10^5$** and a small, simple inner loop → the author may have intended $n^2/64$.
- Commonly confused: `vector<bool>` (bit-packed but without whole-vector operators) and `java.util.BitSet` (no shift) are not substitutes for word-level loops.

## 5. Worked examples (graded)

### Example 1 — Split into two groups with the smallest difference  ·  ★ ≈1800 (est.)

- **Source:** Original problem (the decision version is [LC 416 · Partition Equal Subset Sum](https://leetcode.com/problems/partition-equal-subset-sum/) — Medium).
- **Difficulty:** ≈1800 (est.)
- **Problem:** $n \le 2000$ positive integers, each $\le 500$. Split them into two groups minimising $|\text{sum}_1 - \text{sum}_2|$; print the minimum.
- **Thinking from first principles:** If one group has sum $s$, the difference is $|S - 2s|$, so we want the reachable $s$ closest to $S/2$. Reachable sums are a subset-sum DP over $S \le 10^6$ values and $n = 2000$ items: $2\cdot10^9$ boolean updates — too slow as bytes, $3\cdot10^7$ word operations as a bitset.

<details><summary>Solution</summary>

`b |= b << a_i` for every item, then scan $s = \lfloor S/2\rfloor$ downwards for the first set bit; the answer is $S - 2s$. Bits above $S$ are never set because no subset exceeds the total. $O(nS/64)$. The C++ bitset is `static` (125 KB): large local bitsets can overflow the 1 MB default stack on Windows.

```cpp
#include <bits/stdc++.h>
using namespace std;

const int MAXS = 1000000;                    // n * max(a) <= 2000 * 500

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> a(n);
    int S = 0;
    for (auto& x : a) { cin >> x; S += x; }
    static bitset<MAXS + 1> b;               // static: 125 KB, keep it off the stack
    b[0] = 1;
    for (int x : a) b |= b << x;
    int best = S;
    for (int s = S / 2; s >= 0; s--)         // the closest reachable sum to S/2 from below
        if (b[s]) { best = S - 2 * s; break; }
    cout << best << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        int S = 0;
        for (int i = 0; i < n; i++) { a[i] = in.nextInt(); S += a[i]; }
        long[] w = new long[(S >>> 6) + 1];           // bits 0..S
        w[0] = 1L;
        for (int x : a) {                             // w |= w << x, top word first
            int ws = x >>> 6, bs = x & 63;
            for (int i = w.length - 1; i >= ws; i--) {
                long v = w[i - ws] << bs;
                if (bs != 0 && i - ws - 1 >= 0) v |= w[i - ws - 1] >>> (64 - bs);
                w[i] |= v;
            }
        }
        int best = S;
        for (int s = S / 2; s >= 0; s--)
            if ((w[s >>> 6] >>> s & 1L) != 0) { best = S - 2 * s; break; }
        System.out.println(best);
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
5
3 1 4 2 2
out:
0
-->
<!-- test
in:
1
500
out:
500
-->
<!-- test
in:
3
10 10 10
out:
10
-->

### Example 2 — Rectangles with four black corners  ·  ★ ≈2000 (est.)

- **Source:** Original problem (the same task as [CSES 2137 · Corner Subgrid Count](https://cses.fi/problemset/task/2137) and [LC 750 · Number Of Corner Rectangles](https://leetcode.com/problems/number-of-corner-rectangles/) — Medium 🔒, with different limits).
- **Difficulty:** ≈2000 (est.)
- **Problem:** An $n \times m$ grid of 0/1 ($n, m \le 2000$). Count axis-parallel rectangles (with at least two rows and two columns) whose four corner cells are all 1.
- **Thinking from first principles:** Fix the two rows: a rectangle is a choice of two columns where both rows have a 1. If $k$ such columns exist, there are $\binom{k}{2}$ rectangles. So the answer is a sum over $\binom{n}{2} = 2\cdot10^6$ row pairs of an intersection size, each $O(m)$ naively ($4\cdot10^9$) and $O(m/64)$ with bitsets ($1.25\cdot10^8$).

<details><summary>Solution</summary>

Rows as bitsets; for $a < b$, $k = \mathrm{popcount}(\text{row}_a \,\&\, \text{row}_b)$, add $k(k-1)/2$. The answer can reach $\binom{2000}{2}^2 \approx 4\cdot10^{12}$: use 64-bit. $O(n^2 m/64)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

const int MAXM = 2000;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<bitset<MAXM>> row(n);
    for (int i = 0; i < n; i++) {
        string s;
        cin >> s;
        for (int j = 0; j < m; j++) if (s[j] == '1') row[i][j] = 1;
    }
    long long ans = 0;
    for (int a = 0; a < n; a++)
        for (int b = a + 1; b < n; b++) {
            long long k = (row[a] & row[b]).count();   // columns where both rows have a 1
            ans += k * (k - 1) / 2;                      // any two of them form a rectangle
        }
    cout << ans << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = readInt(in), m = readInt(in);
        int W = (m + 63) >>> 6;
        long[][] row = new long[n][W];
        for (int i = 0; i < n; i++) {
            int c = in.read();
            while (c != '0' && c != '1') c = in.read();
            for (int j = 0; j < m; j++, c = in.read()) if (c == '1') row[i][j >>> 6] |= 1L << j;
        }
        long ans = 0;
        for (int a = 0; a < n; a++) {
            long[] ra = row[a];
            for (int b = a + 1; b < n; b++) {
                long[] rb = row[b];
                long k = 0;
                for (int t = 0; t < W; t++) k += Long.bitCount(ra[t] & rb[t]);
                ans += k * (k - 1) / 2;
            }
        }
        System.out.println(ans);
    }

    static int readInt(DataInputStream in) throws IOException {
        int c = in.read();
        while (c < '0' || c > '9') c = in.read();
        int r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = in.read(); }
        return r;
    }
}
```

</details>

<!-- test
in:
3 4
1101
1111
0101
out:
5
-->
<!-- test
in:
1 1
1
out:
0
-->
<!-- test
in:
2 2
11
11
out:
1
-->

### Example 3 — Triangles in a dense graph  ·  ★ ≈2000 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈2000 (est.)
- **Problem:** An undirected graph with $n \le 2000$ vertices and up to $n(n-1)/2$ edges (duplicates and loops may appear and should be ignored). Count triangles.
- **Thinking from first principles:** $O(n^3)$ triple loops are $1.3\cdot10^9$ checks for distinct triples — too slow with random memory access. Each triangle $\{u, v, w\}$ is determined by an edge $\{u, v\}$ and a common neighbour $w$, so $3T = \sum_{\{u,v\}\in E} |N(u)\cap N(v)|$. With adjacency bitsets each term is a popcount of an AND: $O(mn/64) \approx 3\cdot10^7$ for a complete graph. (For sparse graphs the degree-ordering algorithm of [advanced sqrt techniques](06-advanced-sqrt-techniques.md) is better: $O(m\sqrt m)$.)

<details><summary>Solution</summary>

Build symmetric adjacency bitsets (setting a bit twice is harmless, loops are skipped). For each $u$, enumerate neighbours $v > u$ with `_Find_next` (GCC) or `numberOfTrailingZeros` (Java) so each edge is used once, add $\mathrm{popcount}(N(u) \,\&\, N(v))$, divide by 3. $O(mn/64)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

const int MAXN = 2000;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<bitset<MAXN>> adj(n);
    for (int i = 0; i < m; i++) {
        int u, v;
        cin >> u >> v;
        u--; v--;
        if (u != v) { adj[u][v] = 1; adj[v][u] = 1; }     // duplicates collapse automatically
    }
    long long t = 0;
    for (int u = 0; u < n; u++)
        for (int v = adj[u]._Find_next(u); v < n; v = adj[u]._Find_next(v))   // each edge once, u < v
            t += (adj[u] & adj[v]).count();             // common neighbours close a triangle
    cout << t / 3 << '\n';                               // each triangle is seen from its 3 edges
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        int W = (n + 63) >>> 6;
        long[][] adj = new long[n][W];
        for (int i = 0; i < m; i++) {
            int u = in.nextInt() - 1, v = in.nextInt() - 1;
            if (u != v) { adj[u][v >>> 6] |= 1L << v; adj[v][u >>> 6] |= 1L << u; }
        }
        long t = 0;
        for (int u = 0; u < n; u++) {
            long[] au = adj[u];
            for (int wi = u >>> 6; wi < W; wi++) {
                long word = au[wi];
                if (wi == (u >>> 6)) word &= (u & 63) == 63 ? 0L : -1L << ((u & 63) + 1);   // only v > u
                while (word != 0) {
                    int v = (wi << 6) + Long.numberOfTrailingZeros(word);
                    word &= word - 1;
                    long[] av = adj[v];
                    for (int k = 0; k < W; k++) t += Long.bitCount(au[k] & av[k]);
                }
            }
        }
        System.out.println(t / 3);
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
3 4
1 2
2 1
2 3
3 3
out:
0
-->
<!-- test
in:
1 0
out:
0
-->

### Example 4 — Number of reachable pairs (transitive closure)  ·  ★ ≈2100 (est.)

- **Source:** Original problem (related: [CSES 2138 · Reachable Nodes](https://cses.fi/problemset/task/2138) and [CSES 2143 · Reachability Queries](https://cses.fi/problemset/task/2143), where the graph is larger and you combine SCCs/topological order with bitsets).
- **Difficulty:** ≈2100 (est.)
- **Problem:** A directed graph with $n \le 2000$ vertices and $m$ edges. Count ordered pairs $(u, v)$, $u \ne v$, such that $v$ is reachable from $u$.
- **Thinking from first principles:** BFS from every vertex is $O(n(n+m))$, fine for sparse graphs but $8\cdot10^9$ when $m \approx n^2$. Warshall's closure is $n^3 = 8\cdot10^9$ boolean steps — but the inner step is "OR row $k$ into row $i$", a single bitset operation: $1.25\cdot10^8$ word operations whatever $m$ is.

<details><summary>Solution</summary>

`r[u][v] = 1` for every edge. For $k = 0..n-1$, for every $i$ with `r[i][k]`, `r[i] |= r[k]`. Count all set bits and subtract the diagonal (a vertex on a cycle reaches itself, but the pair $(u,u)$ is excluded). Correctness is Warshall's invariant (§1.4). $O(n^3/64)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

const int MAXN = 2000;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<bitset<MAXN>> r(n);
    for (int i = 0; i < m; i++) {
        int u, v;
        cin >> u >> v;
        r[u - 1][v - 1] = 1;
    }
    // Warshall: after round k, r[i][j] = 1 iff a path i -> j uses only intermediate vertices < k + 1
    for (int k = 0; k < n; k++)
        for (int i = 0; i < n; i++)
            if (r[i][k]) r[i] |= r[k];          // n/64 word operations instead of n bit operations
    long long pairs = 0;
    for (int i = 0; i < n; i++) pairs += r[i].count() - r[i][i];
    cout << pairs << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        int W = (n + 63) >>> 6;
        long[][] r = new long[n][W];
        for (int i = 0; i < m; i++) {
            int u = in.nextInt() - 1, v = in.nextInt() - 1;
            r[u][v >>> 6] |= 1L << v;
        }
        for (int k = 0; k < n; k++) {
            long[] rk = r[k];
            int kw = k >>> 6;
            long kb = 1L << k;
            for (int i = 0; i < n; i++) {
                long[] ri = r[i];
                if ((ri[kw] & kb) != 0) for (int t = 0; t < W; t++) ri[t] |= rk[t];
            }
        }
        long pairs = 0;
        for (int i = 0; i < n; i++) {
            for (long x : r[i]) pairs += Long.bitCount(x);
            if ((r[i][i >>> 6] >>> i & 1L) != 0) pairs--;
        }
        System.out.println(pairs);
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
4 4
1 2
2 3
3 1
3 4
out:
9
-->
<!-- test
in:
3 0
out:
0
-->
<!-- test
in:
2 2
1 1
1 2
out:
1
-->

### Example 5 — All subset sums when the total is bounded  ·  ★ ≈2200 (est.)

- **Source:** Original problem (the final step of [CF 755F · PolandBall and Gifts](https://codeforces.com/problemset/problem/755/F) — 2600 and [CF 1856E2 · PermuTree (hard version)](https://codeforces.com/problemset/problem/1856/E2) — 2700).
- **Difficulty:** ≈2200 (est.)
- **Problem:** $n$ positive integers with total $S \le 10^6$ ($n$ can be as large as $10^6$). Print how many distinct values (including 0) are subset sums.
- **Thinking from first principles:** Plain shift-or is $O(nS/64) = 1.6\cdot10^{10}$ for $n = S = 10^6$ (all ones). But a bounded total means few *distinct* values ($\le \sqrt{2S} \approx 1414$), and equal values can be merged: binary splitting turns $c$ copies into $O(\log c)$ items without changing the reachable set. Now the number of items is small and the bitset size should match $S$, not a fixed maximum — the template ladder of §3.

<details><summary>Solution</summary>

Count each value, binary-split the counts into items $v\cdot 2^j$ and a remainder, and run shift-or on a bitset of the smallest power-of-two size above $S$ (chosen by the template). The answer is the popcount. With $\le 1414$ distinct values, each contributing $O(\log c_v)$ items, the total is a few thousand shifts of $S/64 \approx 15600$ words: under $10^8$ word operations.

```cpp
#include <bits/stdc++.h>
using namespace std;

// Smallest power-of-two bitset above S, chosen at run time from compile-time sizes.
template <size_t LEN = 64>
int countSums(const vector<int>& items, int S) {
    if constexpr (LEN < (size_t(1) << 21)) {
        if ((size_t)S >= LEN) return countSums<LEN * 2>(items, S);
    }
    static bitset<LEN> b;                        // static: large sizes must not live on the stack
    b.reset();
    b[0] = 1;
    for (int x : items) b |= b << x;
    return b.count();                            // bits above S are never set: no sum exceeds S
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> a(n);
    int S = 0;
    for (auto& x : a) { cin >> x; S += x; }
    vector<int> cnt(S + 1, 0);
    for (int x : a) cnt[x]++;
    vector<int> items;                           // binary splitting: c copies of v -> v*1, v*2, v*4, ..., rest
    for (int v = 1; v <= S; v++) {
        int c = cnt[v];
        for (int k = 1; c > 0; k *= 2) {
            int t = min(k, c);
            items.push_back(v * t);
            c -= t;
        }
    }
    cout << countSums(items, S) << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        int S = 0;
        for (int i = 0; i < n; i++) { a[i] = in.nextInt(); S += a[i]; }
        int[] cnt = new int[S + 1];
        for (int x : a) cnt[x]++;
        long[] w = new long[(S >>> 6) + 1];
        w[0] = 1L;
        for (int v = 1; v <= S; v++) {
            int c = cnt[v];
            for (int k = 1; c > 0; k *= 2) {
                int t = Math.min(k, c), x = v * t;
                c -= t;
                int ws = x >>> 6, bs = x & 63;
                for (int i = w.length - 1; i >= ws; i--) {
                    long val = w[i - ws] << bs;
                    if (bs != 0 && i - ws - 1 >= 0) val |= w[i - ws - 1] >>> (64 - bs);
                    w[i] |= val;
                }
            }
        }
        int total = 0;
        for (long x : w) total += Long.bitCount(x);
        System.out.println(total);
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
5
1 1 1 5 5
out:
12
-->
<!-- test
in:
1
7
out:
2
-->
<!-- test
in:
4
2 2 2 2
out:
5
-->

All five programs were stress-tested against direct implementations (Python sets of sums, BFS from every vertex, quadruple loops over rectangles, triple loops over triangles) on 200 random cases each, plus Java-vs-C++ comparison.

## 6. Tricks, pitfalls and things to remember

1. **Big bitsets off the stack.** `bitset<1000001>` is 125 KB; a few of them as locals overflow the 1 MB default stack of Windows builds and some judges. Make them `static`, global, or put them in a `vector`.
2. **Compile-time size.** `bitset<n>` with a run-time `n` does not compile. Use the maximum size, or the template ladder for "smallest size above $S$" when the maximum is large and typical inputs are small.
3. **`b << x` allocates nothing but still costs $N/64$.** Shifting by more than the size gives an all-zero bitset, not UB.
4. **GCC-only helpers:** `_Find_first()`, `_Find_next(i)` are not standard; they exist on Codeforces (GCC) but not on MSVC.
5. **Java shift counts are taken mod 64.** `1L << 64 == 1L`, `x >>> 64 == x`. Special-case shifts of exactly 0 or 64 (the `bs != 0` guard in `orShiftLeft`).
6. **Use `>>>` for words in Java.** `>>` drags the sign bit into the high positions.
7. **Clear garbage bits past $n$** in the last word before counting, or they leak into popcounts and shifted results.
8. **Direction of the in-place shift-or:** top word down for 0/1 items (each item once). Bottom up would reuse the item (unbounded knapsack) — only correct if that is what you want.
9. **Bitsets hold booleans.** Counting "how many ways" or "minimum items" needs integers; then bitsets help only if you can restructure the DP into feasibility checks.
10. **Memory of $n^2$ bits:** $n = 3\cdot10^4$ is 112 MB, $5\cdot10^4$ is 312 MB. Chunk the target dimension (64 · k columns at a time) when needed.
11. **Popcount:** `__builtin_popcountll` / `bitset::count()` in C++, `Long.bitCount` in Java (an intrinsic, compiled to one instruction on modern JVMs).
12. **Measure:** bitset loops are memory-bound once the data leaves L2 cache; a $2000 \times 2000$ bit matrix (500 KB) fits, a $20000 \times 20000$ one does not.

## 7. Going further (toward 2400–2600+)

- **Bitset + Möbius over divisors:** represent each multiset by a bitset indexed by divisors (or by values with a Möbius transform baked in) so that union, product-of-gcd and queries become XOR/AND of bitsets ([CF 1097F · Alex and a TV Show](https://codeforces.com/problemset/problem/1097/F) — 2500).
- **Segment tree on positions + bitset knapsack:** operations covering ranges, "which maxima are achievable" — insert each operation into $O(\log n)$ segment-tree nodes and DFS with a bitset copy per depth ([CF 981E · Addition on Segments](https://codeforces.com/problemset/problem/981/E) — 2200; the same DFS as [segment tree on time](02-segment-tree-on-time-and-dsu-rollback.md)).
- **Bitset DP over "how far can we reach":** [CF 1854B · Earn or Unlock](https://codeforces.com/problemset/problem/1854/B) — 2200 keeps the set of reachable "unlocked prefix lengths" as a bitset.
- **Gaussian elimination over GF(2)** with rows as bitsets: $O(n^3/64)$ ([Gaussian elimination and XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)).
- **Bit-parallel LCS / edit distance** (🔴): the Allison–Dix formula in §2 and Myers' bit-vector edit distance handle strings of length $5\cdot10^4$ in a fraction of a second.
- **Four Russians** (🔴): precompute all $2^k$ combinations of $k$ rows to multiply boolean matrices in $O(n^3/(w \log n))$.

## 8. Practice ladder

1700–2200
- [ ] [CF 1516C · Baby Ehab Partitions Again](https://codeforces.com/problemset/problem/1516/C) — 1700 — subset-sum feasibility, then a parity argument
- [ ] [CSES 2136 · Hamming Distance](https://cses.fi/problemset/task/2136) — XOR + popcount on words
- [ ] [CSES 2137 · Corner Subgrid Count](https://cses.fi/problemset/task/2137) — Example 2
- [ ] [CSES 2138 · Reachable Nodes](https://cses.fi/problemset/task/2138) — DAG + bitsets in reverse topological order
- [ ] [CSES 2143 · Reachability Queries](https://cses.fi/problemset/task/2143) — SCC condensation + bitsets
- [ ] [CF 1854B · Earn or Unlock](https://codeforces.com/problemset/problem/1854/B) — 2200 — bitset DP
- [ ] [CF 981E · Addition on Segments](https://codeforces.com/problemset/problem/981/E) — 2200 — segment tree D&C + bitset

2500+
- [ ] [CF 1097F · Alex and a TV Show](https://codeforces.com/problemset/problem/1097/F) — 2500 — bitsets over divisors
- [ ] [CF 755F · PolandBall and Gifts](https://codeforces.com/problemset/problem/755/F) — 2600 — cycle lengths, bounded-sum subset sum
- [ ] [CF 1856E2 · PermuTree (hard version)](https://codeforces.com/problemset/problem/1856/E2) — 2700 — run-time-sized bitset per node
- [ ] [CF 914F · Substrings in a String](https://codeforces.com/problemset/problem/914/F) — 3000 — per-character position bitsets

## 9. LeetCode / FAANG cross-reference

- [LC 416 · Partition Equal Subset Sum](https://leetcode.com/problems/partition-equal-subset-sum/) — Medium — the bitset one-liner `b |= b << x`; interviewers accept the boolean DP, the bitset is a bonus.
- [LC 1981 · Minimize the Difference Between Target and Chosen Elements](https://leetcode.com/problems/minimize-the-difference-between-target-and-chosen-elements/) — Medium — reachable sums row by row as a bitset.
- [LC 750 · Number Of Corner Rectangles](https://leetcode.com/problems/number-of-corner-rectangles/) — Medium 🔒 — Example 2.
- [LC 1761 · Minimum Degree of a Connected Trio in a Graph](https://leetcode.com/problems/minimum-degree-of-a-connected-trio-in-a-graph/) — Hard — triangle enumeration; adjacency bitsets or the degree ordering of the next file.

Bitset tricks are rare in interviews: the expected answer is the plain DP, and constant-factor engineering is not what is being measured.

## 10. Self-check

1. Why does `b |= b << w` implement adding one 0/1 item, and why must the in-place Java loop run from the top word down?
2. Why are there at most $\sqrt{2S}$ distinct values when the values sum to $S$?
3. Show that binary splitting of $c$ copies preserves the set of reachable sums.
4. What is the bitset cost of Warshall's algorithm for $n = 3000$, and does it fit in 2 s?
5. Give the formula for the number of triangles using adjacency bitsets. Why divide by 3?
6. Name two reasons a bitset rewrite might not speed up a DP.
7. Why is `bitset<1000001> b;` inside a function risky on Windows?
8. In Java, what is `1L << 70`, and why does it matter for bitset code?

<details><summary>Answers</summary>

1. Bit $s$ of $b \ll w$ is bit $s-w$ of $b$, so the OR adds every reachable sum plus $w$. Writing from the top down reads only words not yet modified in this pass, so the item is used at most once.
2. $k$ distinct positive integers sum to at least $1 + \dots + k = k(k+1)/2$.
3. $c = 1 + 2 + \dots + 2^{t-1} + r$ with $r < 2^t$: subsets of the powers give $0..2^t - 1$, adding $r$ shifts that to $r..c$, and since $r < 2^t$ the two ranges cover $0..c$.
4. $3000^3/64 \approx 4.2\cdot10^8$ word operations — fits with a small constant (around 0.5 s in C++).
5. $3T = \sum_{\{u,v\} \in E} \mathrm{popcount}(N(u) \,\&\, N(v))$; each triangle is counted once from each of its three edges.
6. The DP is not boolean (counts, minima), or the access pattern is not a shift/identity (data-dependent indices).
7. It is 125 KB on the stack; several such locals (or recursion) exceed the 1 MB default stack.
8. `1L << 70 == 1L << 6 == 64`: Java masks the shift count to 6 bits, so word/bit index arithmetic must be explicit.

</details>
