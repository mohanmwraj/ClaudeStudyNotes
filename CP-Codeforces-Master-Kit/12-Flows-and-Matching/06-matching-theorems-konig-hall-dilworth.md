# Matching Theorems: König, Hall, Dilworth, Mirsky, Gallai (and Tutte)

> **Band:** 🟣→🔴 1900–2700 · **Priority:** 🔥 (König, Hall, path cover / Dilworth) · ⚡ (Gallai, Mirsky) · 🔴/🧊 (Tutte–Berge, blossom, Birkhoff–von Neumann) · **FAANG:** low · **Prerequisites:** [bipartite matching](03-bipartite-matching-kuhn-hopcroft-karp.md), [min cut](02-min-cut-and-flow-modeling.md), [DAGs](../09-Graphs/04-topological-sort-and-dag-dp.md)
> **You can say you know this when:** you can prove König from max-flow min-cut, derive Hall (with deficiency) from König, prove Dilworth by reducing chain cover to matching,
> and — the real skill — recognise "min cover", "max antichain", "every subset has enough neighbours" in a statement and turn it into a matching size or a fast Hall check.

## 1. First principles — why this works

These theorems are all the same min-max duality (max-flow = min-cut) seen through different objects. Each gives you two things: a **number** you can compute by matching, and a
**certificate** (a cover, a deficient set, an antichain) that proves optimality — often the certificate *is* what the problem asks for.

**König's theorem: in a bipartite graph, maximum matching = minimum vertex cover.** A vertex cover is a set of vertices touching every edge. Every matching edge needs its own cover vertex,
so $\nu\le\tau$ always. For equality, use the unit network $s\to L\to R\to t$, but give the middle edges capacity $\infty$. Its max flow is still $\nu$. Take a min cut $(S,T)$: it cannot cut a
middle edge, so every edge $uv$ has $u\in T$ or $v\in S$ (otherwise $u\in S$, $v\in T$ and the $\infty$ edge is cut). The cut edges are $s\to u$ for $u\in L\cap T$ and $v\to t$ for $v\in R\cap S$, so
$C=(L\cap T)\cup(R\cap S)$ is a vertex cover of size $\text{cut} = \nu$. ∎ The constructive version (BFS of alternating paths from free left vertices) is in [03](03-bipartite-matching-kuhn-hopcroft-karp.md).

*Why bipartite matters:* in a triangle $\nu=1$ but $\tau=2$. General graphs only satisfy $\nu\le\tau\le 2\nu$, and min vertex cover is NP-hard there.

**Gallai's identities.** (1) In any graph, $S$ is independent iff $V\setminus S$ is a vertex cover, so $\alpha+\tau=n$. (2) With no isolated vertices, $\nu+\rho=n$ where $\rho$ is the minimum edge cover:
from a maximum matching, cover each of the $n-2\nu$ unmatched vertices by one extra edge ($\rho\le n-\nu$); conversely a minimum edge cover is a union of stars, and picking one edge per star gives a
matching of size $n-\rho$ ($\nu\ge n-\rho$). For **bipartite** graphs combine with König: $\alpha = n-\nu$ and $\rho = n-\nu$ — maximum independent set and minimum edge cover are both one matching away.

**Hall's marriage theorem.** $G$ has a matching saturating $L$ iff $|N(X)|\ge|X|$ for every $X\subseteq L$. Necessity is obvious (the matched partners of $X$ are distinct and lie in $N(X)$).
Sufficiency from König: if $\nu<|L|$ take a minimum cover $C$, $|C|<|L|$, and let $X = L\setminus C$. Edges out of $X$ must be covered on the right, so $N(X)\subseteq C\cap R$ and
$|N(X)|\le |C|-|C\cap L| < |L|-|C\cap L| = |X|$. ∎ The same argument gives the **deficiency version**:
$$\nu(G) = |L| - \max_{X\subseteq L}\big(|X|-|N(X)|\big)\qquad(\text{with } X=\varnothing \text{ allowed}).$$
Hall is used in two ways: (a) as a *proof* that a greedy always succeeds (regular bipartite graphs have perfect matchings: $k|X|$ edges leave $X$ and each vertex of $N(X)$ absorbs at most $k$),
and (b) as a *fast feasibility test* when the left side has few "types" — then only $2^{\#\text{types}}$ sets $X$ matter (Example 4).

**Dilworth's theorem: in a finite poset, minimum number of chains covering it = maximum antichain size.** An antichain meets each chain at most once, so "$\ge$" is free. For "$\le$", build the
bipartite graph $G_<$ with a left copy $x_L$ and right copy $x_R$ of every element and an edge $x_L y_R$ whenever $x<y$. A matching is a set of "$y$ comes right after $x$ in its chain" links with no element
having two successors or two predecessors — since $<$ is transitive, these links form chains, and $k$ links on $n$ elements give $n-k$ chains. So the minimum chain cover is $n-\nu(G_<)$.
Now take a minimum vertex cover $C$ (König: $|C|=\nu$) and let $A$ be the elements with *neither* copy in $C$; $|A|\ge n-|C| = n-\nu$. If $x<y$ were both in $A$, the edge $x_Ly_R$ would be uncovered —
so $A$ is an antichain of size $\ge n-\nu$. ∎ This is also the algorithm to **print** a maximum antichain.

**Path covers in a DAG.** Two different questions:
- *Vertex-disjoint* paths covering all vertices: links must be **edges** of the DAG. Answer $n-\nu$ with the bipartite graph $u_L v_R$ for every edge $u\to v$.
- Paths that **may share vertices** (= chains of the reachability order): first take the **transitive closure**, then the same formula. By Dilworth this equals the maximum set of pairwise unreachable vertices.

Forgetting the closure in the second case is the classic error: in "$1\to3, 2\to3, 3\to4, 3\to5$" vertex-disjoint paths need 3, shared paths need only 2 ($1\!-\!3\!-\!4$, $2\!-\!3\!-\!5$).

**Mirsky's theorem (dual Dilworth): longest chain = minimum number of antichains partitioning the poset.** Let $h(x)$ be the length of the longest chain ending at $x$; elements with equal $h$ are
pairwise incomparable, giving $\max h$ antichains, and a chain needs distinct levels. For sequences: with $i\prec j \iff i<j,\ a_i<a_j$, chains are strictly increasing subsequences and antichains are
non-increasing subsequences, so **the minimum number of non-increasing subsequences covering a sequence equals its longest strictly increasing subsequence** (patience sorting), and by Dilworth
the minimum number of strictly increasing subsequences equals the longest non-increasing one.

**Tutte's theorem and Tutte–Berge (🔴).** A general graph has a perfect matching iff for every $U\subseteq V$ the graph $G-U$ has at most $|U|$ odd components; more precisely
$\nu(G)=\min_U \frac{1}{2}\big(n+|U|-\text{odd}(G-U)\big)$. Edmonds' **blossom** algorithm finds maximum matchings in general graphs in $O(V^3)$ by contracting odd alternating cycles. In contests:
know it exists, use bitmask DP for $n\le 20$–$40$, or a randomized Tutte-matrix rank computation for $\nu$ alone.

**Birkhoff–von Neumann (🧊).** Every doubly stochastic matrix (non-negative, all row and column sums 1) is a convex combination of permutation matrices: its support graph satisfies Hall, so it contains a
permutation; subtract the largest multiple possible and repeat. Corollary: the assignment LP has an integral optimum. A combinatorial cousin, **König's edge-coloring theorem**: a bipartite graph with max
degree $\Delta$ can be edge-colored with $\Delta$ colors (peel off matchings saturating all max-degree vertices).

## 2. Formulas, definitions and identities

| Name | Statement | Graph class |
|---|---|---|
| Weak duality | $\nu\le\tau$, $\ \alpha\le\rho$ | all |
| König | $\nu=\tau$ | bipartite |
| Gallai 1 | $\alpha+\tau=n$ | all |
| Gallai 2 | $\nu+\rho=n$ (no isolated vertices) | all |
| Bipartite corollaries | $\alpha = n-\nu$, $\ \rho=n-\nu$ | bipartite |
| Hall | $L$-saturating matching $\iff \lvert N(X)\rvert\ge\lvert X\rvert\ \forall X\subseteq L$ | bipartite |
| Deficiency | $\nu = \lvert L\rvert-\max_X(\lvert X\rvert-\lvert N(X)\rvert)$ | bipartite |
| Typed Hall | left vertices of types $T$ with allowed sets $A_T$: feasible $\iff\forall$ unions $U$: $\#\{v: A_{\text{type}(v)}\subseteq U\}\le \text{cap}(U)$ | bipartite with few types |
| Regular | $k$-regular bipartite ⇒ perfect matching; edge set splits into $k$ perfect matchings | bipartite |
| Dilworth | min chain cover = max antichain $= n-\nu(G_<)$ | finite posets |
| Mirsky | longest chain = min antichain partition | finite posets |
| DAG path cover | vertex-disjoint: $n-\nu(G_E)$; vertex-sharing: $n-\nu(G_{E^*})$ ($E^*$ = closure) | DAGs |
| Sequences | min # non-increasing subsequences = LIS (strict); min # strictly increasing = longest non-increasing | sequences |
| Tutte–Berge (🔴) | $\nu=\min_U\frac12(n+\lvert U\rvert-\text{odd}(G-U))$ | all |
| König edge coloring (🧊) | $\chi'(G)=\Delta(G)$ | bipartite |

Costs: König/Dilworth via Hopcroft–Karp $O(E\sqrt V)$; transitive closure with bitsets $O(nm/64)$ or $O(n^3/64)$; typed Hall check $O(2^k)$ per query with $k$ types; SOS-style maintenance $O(2^k)$ per update.

## 3. Implementation (C++ and Java)

**Minimum path covers of a DAG and a maximum antichain.** `closure` computes reachability with bitsets (process vertices in reverse topological order). `chainCover` returns the number of paths
and, via König, one maximum antichain. With `useClosure = false` it is the vertex-disjoint path cover (and the "antichain" is then only a certificate for that problem, not a poset antichain).

```cpp
const int MAXN = 512;
// reach[u] = set of vertices reachable from u by a non-empty path (DAG, vertices 0..n-1)
vector<bitset<MAXN>> closure(int n, const vector<vector<int>> &adj) {
    vector<int> indeg(n, 0), order;
    for (int u = 0; u < n; u++) for (int v : adj[u]) indeg[v]++;
    for (int u = 0; u < n; u++) if (!indeg[u]) order.push_back(u);
    for (size_t i = 0; i < order.size(); i++) for (int v : adj[order[i]]) if (--indeg[v] == 0) order.push_back(v);
    vector<bitset<MAXN>> reach(n);
    for (int i = n - 1; i >= 0; i--) { int u = order[i]; for (int v : adj[u]) { reach[u][v] = 1; reach[u] |= reach[v]; } }
    return reach;
}

// Kuhn on left copies -> right copies of the relation rel; returns {n - matching, antichain via König}
pair<int, vector<int>> chainCover(int n, const vector<bitset<MAXN>> &rel) {
    vector<int> ml(n, -1), mr(n, -1), vis(n, 0);
    int stamp = 0, matched = 0;
    function<bool(int)> augment = [&](int u) {
        if (vis[u] == stamp) return false;
        vis[u] = stamp;
        for (int v = 0; v < n; v++) if (rel[u][v] && (mr[v] == -1 || augment(mr[v]))) { ml[u] = v; mr[v] = u; return true; }
        return false;
    };
    for (int u = 0; u < n; u++) { stamp++; if (augment(u)) matched++; }
    vector<char> zL(n, 0), zR(n, 0);                 // König: alternating reachability from free left copies
    vector<int> q;
    for (int u = 0; u < n; u++) if (ml[u] == -1) { zL[u] = 1; q.push_back(u); }
    for (size_t i = 0; i < q.size(); i++) {
        int u = q[i];
        for (int v = 0; v < n; v++) if (rel[u][v] && !zR[v]) { zR[v] = 1; if (mr[v] != -1 && !zL[mr[v]]) { zL[mr[v]] = 1; q.push_back(mr[v]); } }
    }
    vector<int> anti;                                // cover = (L \ Z) ∪ (R ∩ Z); antichain = neither copy covered
    for (int x = 0; x < n; x++) if (zL[x] && !zR[x]) anti.push_back(x);
    return {n - matched, anti};
}
```

```java
// reach[u] = bitset (long[]) of vertices reachable from u by a non-empty path in a DAG
static long[][] closure(int n, int[][] adj) {
    int[] indeg = new int[n], order = new int[n];
    for (int u = 0; u < n; u++) for (int v : adj[u]) indeg[v]++;
    int qt = 0;
    for (int u = 0; u < n; u++) if (indeg[u] == 0) order[qt++] = u;
    for (int i = 0; i < qt; i++) for (int v : adj[order[i]]) if (--indeg[v] == 0) order[qt++] = v;
    int words = (n + 63) >> 6;
    long[][] reach = new long[n][words];
    for (int i = n - 1; i >= 0; i--) {
        int u = order[i];
        for (int v : adj[u]) { reach[u][v >> 6] |= 1L << (v & 63); for (int w = 0; w < words; w++) reach[u][w] |= reach[v][w]; }
    }
    return reach;
}

static int[] cml, cmr, cvis; static int cstamp; static long[][] crel; static int cn;
static boolean cAugment(int u) {
    if (cvis[u] == cstamp) return false;
    cvis[u] = cstamp;
    for (int v = 0; v < cn; v++)
        if ((crel[u][v >> 6] >>> (v & 63) & 1) != 0 && (cmr[v] == -1 || cAugment(cmr[v]))) { cml[u] = v; cmr[v] = u; return true; }
    return false;
}
// returns the antichain; the chain count is n - matching = (antichain size), stored in countOut[0]
static int[] chainCover(int n, long[][] rel, int[] countOut) {
    cn = n; crel = rel; cml = new int[n]; cmr = new int[n]; cvis = new int[n]; cstamp = 0;
    Arrays.fill(cml, -1); Arrays.fill(cmr, -1);
    int matched = 0;
    for (int u = 0; u < n; u++) { cstamp++; if (cAugment(u)) matched++; }
    boolean[] zL = new boolean[n], zR = new boolean[n];
    int[] q = new int[n]; int qh = 0, qt = 0;
    for (int u = 0; u < n; u++) if (cml[u] == -1) { zL[u] = true; q[qt++] = u; }
    while (qh < qt) {
        int u = q[qh++];
        for (int v = 0; v < n; v++)
            if ((rel[u][v >> 6] >>> (v & 63) & 1) != 0 && !zR[v]) { zR[v] = true; if (cmr[v] != -1 && !zL[cmr[v]]) { zL[cmr[v]] = true; q[qt++] = cmr[v]; } }
    }
    int cnt = 0;
    for (int x = 0; x < n; x++) if (zL[x] && !zR[x]) cnt++;
    int[] anti = new int[cnt]; cnt = 0;
    for (int x = 0; x < n; x++) if (zL[x] && !zR[x]) anti[cnt++] = x;
    countOut[0] = n - matched;
    return anti;
}
```

Why "neither copy covered" means $x\in Z_L$ and $x\notin Z_R$: the cover is $(L\setminus Z)\cup(R\cap Z)$, so $x_L$ is uncovered iff $x_L\in Z$, and $x_R$ is uncovered iff $x_R\notin Z$.
For a poset relation (transitively closed) this set has exactly $n-\nu$ elements.

## 4. Recognising the pattern

| Statement says | Theorem | Compute |
|---|---|---|
| "minimum number of rows/columns/segments/points to hit every X" with two kinds of hitters | König | matching |
| "maximum set of cells/items with no conflicting pair", conflicts bipartite | König + Gallai | $n-\nu$ |
| "minimum number of edges covering every vertex" | Gallai | $n-\nu$ (bipartite or with general $\nu$) |
| "is it always possible to assign…?", "for every group of requests there are enough resources" | Hall | check all subsets of *types*, or matching |
| "lexicographically smallest valid arrangement" with assignment constraints | greedy + Hall check after each tentative choice | |
| "minimum number of chains / sequences / workers / trips covering all tasks with a precedence" | Dilworth | $n-\nu$ on the (closed) order |
| "maximum set of pairwise incomparable / non-nested / non-reachable items" | Dilworth | $n-\nu$, antichain from the cover |
| "minimum number of decreasing subsequences", "minimum number of piles" | Mirsky | LIS |
| matching in a non-bipartite graph | Tutte / blossom (🔴) | bitmask DP for small $n$ |

## 5. Worked examples (graded)

### Example 1 — Covering a sequence by monotone subsequences  ·  ★ ≈1600

- **Source:** Original problem.
- **Difficulty:** ≈1600 (est.)
- **Problem:** a sequence $a_1..a_n$ ($n\le 2\cdot10^5$, $|a_i|\le10^9$). Print two numbers: the minimum number of **non-increasing** subsequences that partition it, and the minimum number of
  **strictly increasing** subsequences that partition it.
- **Thinking from first principles:** define $i\prec j$ iff $i<j$ and $a_i<a_j$. This is a partial order; its chains are strictly increasing subsequences and its antichains are non-increasing subsequences.
  Partitioning into antichains is Mirsky: the answer is the longest chain, the strict LIS. Partitioning into chains is Dilworth: the answer is the largest antichain, the longest non-increasing subsequence.
  Both are LIS computations in $O(n\log n)$ — no matching needed once you see the theorem.

<details><summary>Solution</summary>

Strict LIS: `lower_bound` patience sorting. Longest non-increasing subsequence: negate the values and take the longest non-decreasing subsequence (`upper_bound`). $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int longestChain(const vector<ll> &a, bool strict) {    // longest increasing (strict) or non-decreasing
    vector<ll> tails;
    for (ll x : a) {
        auto it = strict ? lower_bound(tails.begin(), tails.end(), x) : upper_bound(tails.begin(), tails.end(), x);
        if (it == tails.end()) tails.push_back(x); else *it = x;
    }
    return tails.size();
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<ll> a(n), neg(n);
    for (int i = 0; i < n; i++) { cin >> a[i]; neg[i] = -a[i]; }
    cout << longestChain(a, true) << " " << longestChain(neg, false) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static long nextLong() throws IOException {
        int b = in.read();
        while (b != '-' && (b < '0' || b > '9')) b = in.read();
        boolean neg = b == '-';
        if (neg) b = in.read();
        long r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = in.read(); }
        return neg ? -r : r;
    }

    static int longestChain(long[] a, boolean strict) {
        long[] tails = new long[a.length];
        int len = 0;
        for (long x : a) {
            int lo = 0, hi = len;                      // first index with tails >= x (strict) or > x
            while (lo < hi) {
                int mid = (lo + hi) >>> 1;
                if (strict ? tails[mid] >= x : tails[mid] > x) hi = mid; else lo = mid + 1;
            }
            tails[lo] = x;
            if (lo == len) len++;
        }
        return len;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nextLong();
        long[] a = new long[n], neg = new long[n];
        for (int i = 0; i < n; i++) { a[i] = nextLong(); neg[i] = -a[i]; }
        System.out.println(longestChain(a, true) + " " + longestChain(neg, false));
    }
}
```

</details>

<!-- test
in:
5
5 1 4 2 3
out:
3 3
-->
<!-- test
in:
1
7
out:
1 1
-->
<!-- test
in:
3
2 2 2
out:
1 3
-->
<!-- test
in:
6
3 1 2 1 3 2
out:
3 3
-->

### Example 2 — Two path covers of a DAG  ·  ★ ≈2000

- **Source:** Original problem.
- **Difficulty:** ≈2000 (est.)
- **Problem:** a DAG with $n\le 500$ vertices and $m\le 10^4$ edges. Print (a) the minimum number of vertex-disjoint paths covering all vertices, and (b) the minimum number of paths covering all
  vertices when paths may share vertices.
- **Thinking from first principles:** a path cover is a set of "successor links". In (a) a link must be an edge and each vertex has at most one successor and one predecessor: a matching in the split graph,
  and each link saves one path, so $n-\nu$. In (b) a path may "jump over" vertices already covered by another path, i.e. a link may be any pair $u\leadsto v$ — the transitive closure. Then (b) is a chain
  cover of the reachability poset, which Dilworth equates to the largest set of mutually unreachable vertices.

<details><summary>Solution</summary>

(a) Kuhn on edges. (b) Bitset closure ($O(nm/64)$), then Kuhn on the closure ($O(n^3)$ worst case, $1.25\cdot10^8$ simple bit tests — fine). Both values are $n-\nu$.

```cpp
#include <bits/stdc++.h>
using namespace std;

const int MAXN = 512;
int n;

int matching(const vector<bitset<MAXN>> &rel) {
    vector<int> mr(n, -1), vis(n, 0);
    int stamp = 0, res = 0;
    function<bool(int)> augment = [&](int u) {
        if (vis[u] == stamp) return false;
        vis[u] = stamp;
        for (int v = 0; v < n; v++) if (rel[u][v] && (mr[v] == -1 || augment(mr[v]))) { mr[v] = u; return true; }
        return false;
    };
    for (int u = 0; u < n; u++) { stamp++; if (augment(u)) res++; }
    return res;
}

int main() {
    int m;
    cin >> n >> m;
    vector<vector<int>> adj(n);
    vector<bitset<MAXN>> edge(n), reach(n);
    vector<int> indeg(n, 0), order;
    for (int i = 0; i < m; i++) { int u, v; cin >> u >> v; u--; v--; adj[u].push_back(v); edge[u][v] = 1; indeg[v]++; }
    for (int u = 0; u < n; u++) if (!indeg[u]) order.push_back(u);
    for (size_t i = 0; i < order.size(); i++) for (int v : adj[order[i]]) if (--indeg[v] == 0) order.push_back(v);
    for (int i = n - 1; i >= 0; i--) { int u = order[i]; for (int v : adj[u]) { reach[u][v] = 1; reach[u] |= reach[v]; } }
    cout << n - matching(edge) << " " << n - matching(reach) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n, stamp;
    static int[] mr, vis;
    static long[][] rel;

    static boolean augment(int u) {
        if (vis[u] == stamp) return false;
        vis[u] = stamp;
        for (int v = 0; v < n; v++)
            if ((rel[u][v >> 6] >>> (v & 63) & 1) != 0 && (mr[v] == -1 || augment(mr[v]))) { mr[v] = u; return true; }
        return false;
    }
    static int matching(long[][] r) {
        rel = r; mr = new int[n]; vis = new int[n]; stamp = 0;
        Arrays.fill(mr, -1);
        int res = 0;
        for (int u = 0; u < n; u++) { stamp++; if (augment(u)) res++; }
        return res;
    }

    static void solve() throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); n = (int) st.nval;
        st.nextToken(); int m = (int) st.nval;
        int words = (n + 63) >> 6;
        int[] eu = new int[m], ev = new int[m], deg = new int[n], indeg = new int[n];
        long[][] edge = new long[n][words], reach = new long[n][words];
        for (int i = 0; i < m; i++) {
            st.nextToken(); eu[i] = (int) st.nval - 1; st.nextToken(); ev[i] = (int) st.nval - 1;
            deg[eu[i]]++; indeg[ev[i]]++;
            edge[eu[i]][ev[i] >> 6] |= 1L << (ev[i] & 63);
        }
        int[][] adj = new int[n][];
        for (int u = 0; u < n; u++) adj[u] = new int[deg[u]];
        for (int i = 0; i < m; i++) adj[eu[i]][--deg[eu[i]]] = ev[i];
        int[] order = new int[n]; int qt = 0;
        for (int u = 0; u < n; u++) if (indeg[u] == 0) order[qt++] = u;
        for (int i = 0; i < qt; i++) for (int v : adj[order[i]]) if (--indeg[v] == 0) order[qt++] = v;
        for (int i = n - 1; i >= 0; i--) {
            int u = order[i];
            for (int v : adj[u]) { reach[u][v >> 6] |= 1L << (v & 63); for (int w = 0; w < words; w++) reach[u][w] |= reach[v][w]; }
        }
        System.out.println((n - matching(edge)) + " " + (n - matching(reach)));
    }

    public static void main(String[] args) throws Exception {
        Thread th = new Thread(null, () -> {
            try { solve(); } catch (IOException e) { throw new UncheckedIOException(e); }
        }, "main", 1 << 27);
        th.start();
        th.join();
    }
}
```

</details>

The second test is the "hourglass" from §1: vertex-disjoint paths need 3, shared paths need 2.

<!-- test
in:
4 3
1 2
2 3
1 4
out:
2 2
-->
<!-- test
in:
5 4
1 3
2 3
3 4
3 5
out:
3 2
-->
<!-- test
in:
1 0
out:
1 1
-->
<!-- test
in:
3 0
out:
3 3
-->

### Example 3 — Security Camera 3  ·  ★ ≈2340

- **Source:** [AtCoder ABC274 G · Security Camera 3](https://atcoder.jp/contests/abc274/tasks/abc274_g)
- **Difficulty:** ≈2340 (est., AtCoder difficulty)
- **Problem:** an $H\times W$ grid ($H,W\le300$) of empty cells `.` and obstacles `#`. A camera is placed on an empty cell and faces one of four directions; it watches its own cell and the cells in that
  direction up to the first obstacle. Find the minimum number of cameras so that every empty cell is watched.
- **Thinking from first principles:** a camera watches part of one horizontal or one vertical maximal run of empty cells, and a camera at the end of a run pointing inward watches the whole run — so
  WLOG cameras choose **runs**. Every cell lies on exactly one horizontal run and one vertical run, and it is watched iff one of those two runs is chosen: choose a set of runs hitting every cell.
  Cells are edges between their two runs, so this is a **minimum vertex cover** of a bipartite graph: König says it equals the maximum matching. (Compare [rooks behind walls](03-bipartite-matching-kuhn-hopcroft-karp.md):
  same graph, the dual question.)

<details><summary>Solution</summary>

Number horizontal and vertical runs, add an edge per empty cell, run Hopcroft–Karp. $V\le 2HW$, $E\le HW = 9\cdot10^4$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct HopcroftKarp {
    int nl, nr;
    vector<vector<int>> adj; vector<int> ml, mr, dist, it;
    HopcroftKarp(int nl, int nr) : nl(nl), nr(nr), adj(nl), ml(nl, -1), mr(nr, -1), dist(nl), it(nl) {}
    void addEdge(int u, int v) { adj[u].push_back(v); }
    bool bfs() {
        queue<int> q;
        for (int u = 0; u < nl; u++) { dist[u] = ml[u] == -1 ? 0 : -1; if (!dist[u]) q.push(u); }
        bool found = false;
        while (!q.empty()) {
            int u = q.front(); q.pop();
            for (int v : adj[u]) { int w = mr[v]; if (w == -1) found = true; else if (dist[w] < 0) { dist[w] = dist[u] + 1; q.push(w); } }
        }
        return found;
    }
    bool dfs(int u) {
        for (int &i = it[u]; i < (int)adj[u].size(); i++) {
            int v = adj[u][i], w = mr[v];
            if (w == -1 || (dist[w] == dist[u] + 1 && dfs(w))) { ml[u] = v; mr[v] = u; return true; }
        }
        dist[u] = -1;
        return false;
    }
    int solve() {
        int res = 0;
        while (bfs()) { fill(it.begin(), it.end(), 0); for (int u = 0; u < nl; u++) if (ml[u] == -1 && dfs(u)) res++; }
        return res;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int h, w;
    cin >> h >> w;
    vector<string> g(h);
    for (auto &row : g) cin >> row;
    vector<vector<int>> hid(h, vector<int>(w, -1)), vid(h, vector<int>(w, -1));
    int nh = 0, nv = 0;
    for (int i = 0; i < h; i++) for (int j = 0; j < w; j++) if (g[i][j] == '.') hid[i][j] = (j && g[i][j - 1] == '.') ? hid[i][j - 1] : nh++;
    for (int j = 0; j < w; j++) for (int i = 0; i < h; i++) if (g[i][j] == '.') vid[i][j] = (i && g[i - 1][j] == '.') ? vid[i - 1][j] : nv++;
    HopcroftKarp hk(nh, nv);
    for (int i = 0; i < h; i++) for (int j = 0; j < w; j++) if (g[i][j] == '.') hk.addEdge(hid[i][j], vid[i][j]);
    cout << hk.solve() << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static class HopcroftKarp {
        int nl, nr; int[] start, adjv, ml, mr, dist, it, q, stk;
        HopcroftKarp(int nl, int nr, int[] eu, int[] ev, int m) {
            this.nl = nl; this.nr = nr;
            start = new int[nl + 1]; adjv = new int[m];
            for (int i = 0; i < m; i++) start[eu[i] + 1]++;
            for (int u = 0; u < nl; u++) start[u + 1] += start[u];
            int[] pos = Arrays.copyOf(start, nl);
            for (int i = 0; i < m; i++) adjv[pos[eu[i]]++] = ev[i];
            ml = new int[nl]; mr = new int[nr]; dist = new int[nl]; it = new int[nl]; q = new int[nl]; stk = new int[nl];
            Arrays.fill(ml, -1); Arrays.fill(mr, -1);
        }
        boolean bfs() {
            int qh = 0, qt = 0;
            for (int u = 0; u < nl; u++) { dist[u] = ml[u] == -1 ? 0 : -1; if (dist[u] == 0) q[qt++] = u; }
            boolean found = false;
            while (qh < qt) {
                int u = q[qh++];
                for (int k = start[u]; k < start[u + 1]; k++) { int w = mr[adjv[k]]; if (w == -1) found = true; else if (dist[w] < 0) { dist[w] = dist[u] + 1; q[qt++] = w; } }
            }
            return found;
        }
        boolean dfs(int root) {
            int top = 0; stk[top++] = root;
            while (top > 0) {
                int u = stk[top - 1];
                if (it[u] == start[u + 1]) { dist[u] = -1; top--; continue; }
                int w = mr[adjv[it[u]]];
                if (w == -1) { for (int i = top - 1; i >= 0; i--) { int x = stk[i], y = adjv[it[x]]; ml[x] = y; mr[y] = x; } return true; }
                if (dist[w] == dist[u] + 1) stk[top++] = w; else it[u]++;
            }
            return false;
        }
        int solve() {
            int res = 0;
            while (bfs()) { System.arraycopy(start, 0, it, 0, nl); for (int u = 0; u < nl; u++) if (ml[u] == -1 && dfs(u)) res++; }
            return res;
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int h = Integer.parseInt(st.nextToken()), w = Integer.parseInt(st.nextToken());
        char[][] g = new char[h][];
        for (int i = 0; i < h; i++) g[i] = br.readLine().trim().toCharArray();
        int[][] hid = new int[h][w], vid = new int[h][w];
        int nh = 0, nv = 0, cells = 0;
        for (int i = 0; i < h; i++) for (int j = 0; j < w; j++) if (g[i][j] == '.') { hid[i][j] = (j > 0 && g[i][j - 1] == '.') ? hid[i][j - 1] : nh++; cells++; }
        for (int j = 0; j < w; j++) for (int i = 0; i < h; i++) if (g[i][j] == '.') vid[i][j] = (i > 0 && g[i - 1][j] == '.') ? vid[i - 1][j] : nv++;
        int[] eu = new int[cells], ev = new int[cells];
        int m = 0;
        for (int i = 0; i < h; i++) for (int j = 0; j < w; j++) if (g[i][j] == '.') { eu[m] = hid[i][j]; ev[m] = vid[i][j]; m++; }
        System.out.println(new HopcroftKarp(nh, nv, eu, ev, m).solve());
    }
}
```

</details>

Hand checks: an empty $3\times3$ grid needs 3 cameras (three rows; the matching of size 3 proves 2 are not enough). A single row `..#..` needs 2. A plus-shaped region around a central obstacle needs 4.

<!-- test
in:
3 3
...
...
...
out:
3
-->
<!-- test
in:
1 5
..#..
out:
2
-->
<!-- test
in:
3 3
...
.#.
...
out:
4
-->
<!-- test
in:
2 2
##
#.
out:
1
-->

### Example 4 — Allowed Letters  ·  ★ 2400

- **Source:** [CF 1009G · Allowed Letters](https://codeforces.com/problemset/problem/1009/G) — 2400
- **Difficulty:** 2400
- **Problem:** a string $s$ ($|s|\le10^5$) over letters `a`–`f` may be rearranged arbitrarily. Some positions (at most one constraint each) allow only a given subset of letters; the other positions allow all six.
  Print the lexicographically smallest rearrangement satisfying all constraints, or `Impossible`.
- **Thinking from first principles:** lexicographically smallest ⇒ greedy: at each position, try letters from `a` upward and keep the first one after which the *rest* can still be completed. The whole difficulty is that
  completion check. It is a bipartite perfect matching (remaining positions ↔ remaining letter copies) with $10^5$ vertices — far too slow to recompute $6\cdot10^5$ times. But positions have only $2^6=64$
  *types* (their allowed mask) and letters only 6 kinds, so Hall's condition collapses to 64 inequalities: for every letter set $U$, the number of remaining positions whose allowed set is a subset of $U$ must not
  exceed the number of remaining letters belonging to $U$. (The worst $X$ for a given $N(X)=U$ is "all positions whose mask $\subseteq U$".)

<details><summary>Solution</summary>

Maintain `sub[U]` = number of remaining positions with mask $\subseteq U$ and `have[U]` = number of remaining letters in $U$. Removing a position with mask $a$ decrements `sub[U]` for all
$U\supseteq a$ (64 updates); removing letter $c$ decrements `have[U]` for all $U\ni c$. The check is `sub[U] <= have[U]` for all 64 sets. At position $i$, remove the position once, then for each candidate letter
remove it, check, and either commit or restore. Hall guarantees that if the initial check passes some candidate always succeeds. Cost $\approx |s|\cdot 6\cdot 3\cdot 64\approx 10^8$ trivial operations.

```cpp
#include <bits/stdc++.h>
using namespace std;

int sub_[64], have_[64];

bool hallOk() {
    for (int U = 0; U < 64; U++) if (sub_[U] > have_[U]) return false;
    return true;
}
void changePos(int mask, int d) { for (int U = 0; U < 64; U++) if ((U & mask) == mask) sub_[U] += d; }
void changeLetter(int c, int d) { for (int U = 0; U < 64; U++) if (U >> c & 1) have_[U] += d; }

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string s;
    int m;
    cin >> s >> m;
    int n = s.size();
    vector<int> allow(n, 63);
    for (int i = 0; i < m; i++) {
        int pos; string letters;
        cin >> pos >> letters;
        int mask = 0;
        for (char ch : letters) mask |= 1 << (ch - 'a');
        allow[pos - 1] = mask;
    }
    vector<int> cnt(6, 0);
    for (char ch : s) { cnt[ch - 'a']++; changeLetter(ch - 'a', 1); }
    for (int i = 0; i < n; i++) changePos(allow[i], 1);
    if (!hallOk()) { cout << "Impossible\n"; return 0; }
    string res(n, '?');
    for (int i = 0; i < n; i++) {
        changePos(allow[i], -1);
        for (int c = 0; c < 6; c++) {
            if (!(allow[i] >> c & 1) || cnt[c] == 0) continue;
            changeLetter(c, -1);
            if (hallOk()) { res[i] = 'a' + c; cnt[c]--; break; }
            changeLetter(c, 1);
        }
    }
    cout << res << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] sub = new int[64], have = new int[64];

    static boolean hallOk() {
        for (int U = 0; U < 64; U++) if (sub[U] > have[U]) return false;
        return true;
    }
    static void changePos(int mask, int d) { for (int U = 0; U < 64; U++) if ((U & mask) == mask) sub[U] += d; }
    static void changeLetter(int c, int d) { for (int U = 0; U < 64; U++) if ((U >> c & 1) != 0) have[U] += d; }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in), 1 << 16);
        String s = br.readLine().trim();
        int m = Integer.parseInt(br.readLine().trim());
        int n = s.length();
        int[] allow = new int[n];
        Arrays.fill(allow, 63);
        for (int i = 0; i < m; i++) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            int pos = Integer.parseInt(st.nextToken());
            String letters = st.nextToken();
            int mask = 0;
            for (int k = 0; k < letters.length(); k++) mask |= 1 << (letters.charAt(k) - 'a');
            allow[pos - 1] = mask;
        }
        int[] cnt = new int[6];
        for (int i = 0; i < n; i++) { cnt[s.charAt(i) - 'a']++; changeLetter(s.charAt(i) - 'a', 1); }
        for (int i = 0; i < n; i++) changePos(allow[i], 1);
        if (!hallOk()) { System.out.println("Impossible"); return; }
        char[] res = new char[n];
        for (int i = 0; i < n; i++) {
            changePos(allow[i], -1);
            for (int c = 0; c < 6; c++) {
                if ((allow[i] >> c & 1) == 0 || cnt[c] == 0) continue;
                changeLetter(c, -1);
                if (hallOk()) { res[i] = (char) ('a' + c); cnt[c]--; break; }
                changeLetter(c, 1);
            }
        }
        System.out.println(new String(res));
    }
}
```

</details>

Expected outputs were checked by trying every permutation of $s$.

<!-- test
in:
bedefead
5
2 e
1 dc
5 b
7 ef
6 ef
out:
deadbeef
-->
<!-- test
in:
abacaba
0
out:
aaaabbc
-->
<!-- test
in:
fc
2
1 cfab
2 f
out:
cf
-->
<!-- test
in:
ab
2
1 b
2 b
out:
Impossible
-->

### Example 5 — Hakata (maximum antichain of palindromes)  ·  ★ ≈2800

- **Source:** [AtCoder ABC237 H · Hakata](https://atcoder.jp/contests/abc237/tasks/abc237_h)
- **Difficulty:** ≈2807 (est., AtCoder difficulty)
- **Problem:** a string $S$ ($|S|\le200$). Choose as many **distinct** palindromes as possible, each a substring of $S$, such that no chosen string is a substring of another chosen string. Print the maximum.
- **Thinking from first principles:** "is a substring of" is a partial order on strings (reflexive, antisymmetric, transitive), and the condition asks for a **maximum antichain** among the palindromic substrings.
  How many are there? Each position can end at most one *new* distinct palindrome (the longest palindromic suffix ending there), so there are at most $|S|\le200$. Dilworth: maximum antichain $= P-\nu$ where
  $\nu$ is a maximum matching in the bipartite graph "$x_L\to y_R$ if $x$ is a proper substring of $y$" — the relation is already transitive, so no closure is needed.

<details><summary>Solution</summary>

Collect distinct palindromic substrings ($O(n^3)$ by brute force is $8\cdot10^6$ — fine), build the "proper substring" relation with `find` ($P^2$ checks of length $\le 200$), Kuhn ($P\le200$), print $P-\nu$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int P;
vector<vector<int>> adj;
vector<int> mr, vis;
int stamp_ = 0;

bool augment(int u) {
    if (vis[u] == stamp_) return false;
    vis[u] = stamp_;
    for (int v : adj[u]) if (mr[v] == -1 || augment(mr[v])) { mr[v] = u; return true; }
    return false;
}

int main() {
    string s;
    cin >> s;
    int n = s.size();
    set<string> pals;
    for (int i = 0; i < n; i++)
        for (int j = i; j < n; j++) {
            bool ok = true;
            for (int a = i, b = j; a < b; a++, b--) if (s[a] != s[b]) { ok = false; break; }
            if (ok) pals.insert(s.substr(i, j - i + 1));
        }
    vector<string> p(pals.begin(), pals.end());
    P = p.size();
    adj.assign(P, {});
    for (int x = 0; x < P; x++)
        for (int y = 0; y < P; y++)
            if (x != y && p[y].size() > p[x].size() && p[y].find(p[x]) != string::npos) adj[x].push_back(y);
    mr.assign(P, -1); vis.assign(P, 0);
    int nu = 0;
    for (int u = 0; u < P; u++) { stamp_++; if (augment(u)) nu++; }
    cout << P - nu << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[][] adj;
    static int[] mr, vis;
    static int stamp = 0;

    static boolean augment(int u) {
        if (vis[u] == stamp) return false;
        vis[u] = stamp;
        for (int v : adj[u]) if (mr[v] == -1 || augment(mr[v])) { mr[v] = u; return true; }
        return false;
    }

    public static void main(String[] args) throws IOException {
        String s = new BufferedReader(new InputStreamReader(System.in)).readLine().trim();
        int n = s.length();
        TreeSet<String> pals = new TreeSet<>();
        for (int i = 0; i < n; i++)
            for (int j = i; j < n; j++) {
                boolean ok = true;
                for (int a = i, b = j; a < b; a++, b--) if (s.charAt(a) != s.charAt(b)) { ok = false; break; }
                if (ok) pals.add(s.substring(i, j + 1));
            }
        String[] p = pals.toArray(new String[0]);
        int P = p.length;
        adj = new int[P][];
        for (int x = 0; x < P; x++) {
            int[] tmp = new int[P]; int k = 0;
            for (int y = 0; y < P; y++) if (x != y && p[y].length() > p[x].length() && p[y].contains(p[x])) tmp[k++] = y;
            adj[x] = Arrays.copyOf(tmp, k);
        }
        mr = new int[P]; Arrays.fill(mr, -1);
        vis = new int[P];
        int nu = 0;
        for (int u = 0; u < P; u++) { stamp++; if (augment(u)) nu++; }
        System.out.println(P - nu);
    }
}
```

</details>

Hand checks (also verified by brute force over all subsets): `abcbaba` has the palindromes a, b, c, aba, bab, bcb, abcba; both {a, b, c} and {aba, bab, bcb} are antichains of size 3
and no set of 4 avoids nesting, so 3. `aaaa`: all palindromes are nested, 1. `abcd`: four single letters, 4.

<!-- test
in:
abcbaba
out:
3
-->
<!-- test
in:
a
out:
1
-->
<!-- test
in:
aaaa
out:
1
-->
<!-- test
in:
abcd
out:
4
-->
<!-- test
in:
ababa
out:
2
-->

## 6. Tricks, pitfalls and things to remember

1. **König is bipartite-only.** On general graphs $\tau$ can be up to $2\nu$; "max independent set = $n-\nu$" is wrong there (and NP-hard to compute).
2. **Gallai's $\nu+\rho=n$ needs no isolated vertices** — an isolated vertex cannot be edge-covered at all.
3. **Path cover with shared vertices needs the transitive closure.** Without it you compute vertex-disjoint paths.
4. **Dilworth needs a partial order** (transitive). If the "conflict" relation is not transitive, $n-\nu$ is the vertex-disjoint path cover of that graph, not a max antichain.
5. **Hall with types:** the right family of sets to check is all unions $U$ of *right-side* kinds, with "left vertices whose allowed set $\subseteq U$". Checking subsets of left vertices directly is exponential.
6. **Greedy + Hall** (lexicographically smallest assignment): remove the current position *before* trying letters, and restore only the letter on failure.
7. **Antichain reconstruction**: elements with $x_L\in Z$ and $x_R\notin Z$; using the cover from a *non-maximum* matching gives garbage.
8. **Mirsky on sequences:** strict vs non-strict matters — non-increasing pieces ↔ strictly increasing LIS (`lower_bound`), strictly decreasing pieces ↔ non-decreasing LIS (`upper_bound`).
9. **Bitset closures** in Java: use `long[]` words; `>>>` not `>>` when extracting bits.
10. **Recursion depth** in Kuhn on $n=500$ is fine in C++; Java code above runs Kuhn in a big-stack thread where $n$ can be larger.

## 7. Going further (toward 2400–2600+)

- **Weighted Dilworth / maximum-weight antichain**: min cut on the split graph with vertex weights — [AtCoder ABC354 G · Select Strings](https://atcoder.jp/contests/abc354/tasks/abc354_g).
- **Hall-based binary search**: [CF 981F · Round Marriage](https://codeforces.com/problemset/problem/981/F) — 2500 checks a cyclic Hall condition with prefix sums.
- **Hall on intervals**: when each left vertex is an interval of right vertices, Hall reduces to checking contiguous unions; greedy by right endpoint is optimal (exchange argument), and segment trees maintain the deficiency
  ([CF 1179C · Serge and Dining Room](https://codeforces.com/problemset/problem/1179/C) — 2200 is a related "first unmatched" query).
- **König in disguise** ("rows or columns", "lines covering points"): [CF 1198E · Rectangle Painting 2](https://codeforces.com/problemset/problem/1198/E) — 2500 with coordinate-compressed capacities;
  [CF 1404E · Bricks](https://codeforces.com/problemset/problem/1404/E) — 2800 as a maximum independent set.
- **General graphs (🔴)**: Tutte–Berge certificates, Gallai–Edmonds decomposition (which vertices are in every maximum matching), randomized matching via Tutte matrix rank over $\mathbb{F}_p$.
- **Regular bipartite edge coloring / Birkhoff decomposition (🧊)**: schedule construction problems (e.g. round-robin, Latin squares) peel off perfect matchings one at a time.

## 8. Practice ladder

≤ 2000
- [ ] [LC 1349 · Maximum Students Taking Exam](https://leetcode.com/problems/maximum-students-taking-exam/) — Hard — max independent set = seats − matching
- [ ] [AtCoder ARC092 A · 2D Plane 2N Points](https://atcoder.jp/contests/arc092/tasks/arc092_a) — matching on a dominance order
- [ ] [CF 1437C · Chef Monocarp](https://codeforces.com/problemset/problem/1437/C) — 1800 — assignment; Hall explains why sorted greedy order works
- [ ] [CF 1423B · Valuable Paper](https://codeforces.com/problemset/problem/1423/B) — 1900 — perfect matching existence under a threshold

2000–2400
- [ ] [CF 387D · George and Interesting Graph](https://codeforces.com/problemset/problem/387/D) — 2200 — degree constraints via matching
- [ ] [CF 1179C · Serge and Dining Room](https://codeforces.com/problemset/problem/1179/C) — 2200 — Hall-type prefix condition on a segment tree
- [ ] [AtCoder ABC274 G · Security Camera 3](https://atcoder.jp/contests/abc274/tasks/abc274_g) — Example 3 (König)
- [ ] [AtCoder ABC317 G · Rearranging](https://atcoder.jp/contests/abc317/tasks/abc317_g) — regular bipartite graph: peel off perfect matchings (Hall)
- [ ] [CF 1009G · Allowed Letters](https://codeforces.com/problemset/problem/1009/G) — 2400 — Example 4 (typed Hall)
- [ ] [CF 1027F · Session in BSU](https://codeforces.com/problemset/problem/1027/F) — 2400 — Hall per component: every component needs #edges ≤ #vertices

2400+
- [ ] [CF 981F · Round Marriage](https://codeforces.com/problemset/problem/981/F) — 2500 — binary search + cyclic Hall condition
- [ ] [CF 1198E · Rectangle Painting 2](https://codeforces.com/problemset/problem/1198/E) — 2500 — vertex cover by rows/columns with weights
- [ ] [CF 2026E · Best Subsequence](https://codeforces.com/problemset/problem/2026/E) — 2500 — maximum independent set (elements vs bits)
- [ ] [CF 1783F · Double Sort II](https://codeforces.com/problemset/problem/1783/F) — 2500 — cycles as vertices, indices as edges: keep a maximum matching
- [ ] [AtCoder ABC354 G · Select Strings](https://atcoder.jp/contests/abc354/tasks/abc354_g) — weighted antichain via min cut
- [ ] [AtCoder ABC237 H · Hakata](https://atcoder.jp/contests/abc237/tasks/abc237_h) — Example 5 (Dilworth)
- [ ] [CF 1404E · Bricks](https://codeforces.com/problemset/problem/1404/E) — 2800 — König on "joints"

## 9. LeetCode / FAANG cross-reference

- [LC 1349 · Maximum Students Taking Exam](https://leetcode.com/problems/maximum-students-taking-exam/) — Hard — König/Gallai: maximum independent set in a bipartite graph.
- [LC 2123 · Minimum Operations to Remove Adjacent Ones in Matrix](https://leetcode.com/problems/minimum-operations-to-remove-adjacent-ones-in-matrix/) — Hard 🔒 — minimum vertex cover on a grid = matching (König).
- [LC 300 · Longest Increasing Subsequence](https://leetcode.com/problems/longest-increasing-subsequence/) — Medium — Mirsky: also the minimum number of non-increasing piles.
- [LC 354 · Russian Doll Envelopes](https://leetcode.com/problems/russian-doll-envelopes/) — Hard — longest chain in a 2D dominance order (sort + LIS).
- [LC 1964 · Find the Longest Valid Obstacle Course at Each Position](https://leetcode.com/problems/find-the-longest-valid-obstacle-course-at-each-position/) — Hard — non-strict chain lengths per prefix (patience sorting).

Interviews ask the *sequence* versions (LIS, piles) far more than the graph theorems; knowing Dilworth/Mirsky lets you justify the greedy in one sentence.

## 10. Self-check

1. Prove König from max-flow min-cut.
2. Derive Hall's theorem (and the deficiency formula) from König.
3. Why does a $k$-regular bipartite graph have a perfect matching?
4. Prove Dilworth's theorem using matchings. How do you print a maximum antichain?
5. What is the difference between the two path-cover formulas for a DAG? Give a graph where they differ.
6. State Mirsky's theorem and its LIS corollary. Which direction needs `lower_bound` and which `upper_bound`?
7. In Allowed Letters, why do 64 inequalities suffice to decide whether a completion exists?
8. State Gallai's two identities and the condition for the second.

<details><summary>Answers</summary>

1. Unit network with $\infty$ middle edges; a min cut cannot cut a middle edge, so $(L\cap T)\cup(R\cap S)$ covers every edge, and its size equals the cut $=\nu$.
2. If $\nu<|L|$, a cover $C$ with $|C|<|L|$ exists; $X = L\setminus C$ has $N(X)\subseteq C\cap R$, so $|N(X)|<|X|$. Applying the same to $\nu$ directly gives $\nu = |L|-\max_X(|X|-|N(X)|)$.
3. Any $X\subseteq L$ sends $k|X|$ edges into $N(X)$, which can absorb at most $k|N(X)|$; so $|N(X)|\ge|X|$ and Hall applies.
4. Chains ↔ successor links ↔ matchings in $G_<$, so min chains $=n-\nu$; from a König cover, the elements with neither copy covered form an antichain of size $\ge n-\nu$. Print exactly those.
5. Vertex-disjoint uses DAG edges only; shared uses the transitive closure. Hourglass $1\to3,2\to3,3\to4,3\to5$: 3 vs 2.
6. Longest chain = minimum antichain partition. Min number of non-increasing subsequences = strict LIS (`lower_bound`); min number of strictly decreasing subsequences = longest non-decreasing (`upper_bound`).
7. For a fixed neighbourhood union $U$, the largest violating set is "all positions with mask $\subseteq U$"; there are only 64 unions.
8. $\alpha+\tau=n$ always; $\nu+\rho=n$ when there are no isolated vertices.

</details>
