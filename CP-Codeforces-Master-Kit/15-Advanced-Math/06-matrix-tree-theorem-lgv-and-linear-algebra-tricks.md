# Matrix-tree theorem, LGV lemma and other linear-algebra tricks

> **Band:** 🟣 2100 – 🔴 2700 · **Priority:** ⚡ (Kirchhoff, determinant mod $p$, expectation linear systems) · 🔴 (LGV, weighted Kirchhoff + interpolation) · 🧊 (directed arborescences, BEST theorem) · **FAANG:** none · **Prerequisites:** [Gaussian elimination](02-gaussian-elimination-and-xor-basis.md), [Lagrange interpolation](05-lagrange-interpolation-and-berlekamp-massey.md), [grid path DP](../06-Dynamic-Programming/04-grid-and-path-counting-dp.md), [probability DP](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md)
> **You can say you know this when:** you can count spanning trees of a multigraph with one determinant (and prove why), handle the
> directed version, count non-intersecting path pairs with a $2\times2$ determinant, compute a determinant modulo a composite number, and
> solve an expected-value system with cycles by Gaussian or tridiagonal elimination.

---

## 1. First principles — why this works

### 1.1 Counting spanning trees: the Laplacian

For an undirected multigraph on $n$ vertices define the **Laplacian** $L=D-A$: $D$ is the diagonal degree matrix and $A_{uv}$ the number of edges
between $u$ and $v$ (self-loops ignored). Every row sums to $0$, so $\det L=0$. **Kirchhoff's theorem:** for any vertex $r$, the determinant of
$L$ with row $r$ and column $r$ removed equals the number of spanning trees $\tau(G)$.

*Why (Cauchy–Binet proof sketch).* Orient each edge arbitrarily and form the $n\times m$ incidence matrix $B$ (column $e=(u\to v)$ has $+1$ at $u$,
$-1$ at $v$). Then $L=BB^{T}$ (the $(u,u)$ entry counts incident edges, the $(u,v)$ entry is $-$(edges between them)). Deleting row $r$ gives
$B_r$ with $L_r=B_rB_r^{T}$. Cauchy–Binet expands $\det(B_rB_r^T)=\sum_{S}\det(B_r[S])^2$ over all sets $S$ of $n-1$ edges. Finally:

- if $S$ contains a cycle, the columns of that cycle (with signs following the cycle) sum to zero: $\det=0$;
- if $S$ is a spanning tree, repeatedly take a leaf $\ne r$: its row has a single $\pm1$ (its edge), so expanding along it peels the tree;
  the determinant is $\pm1$.

So the sum counts spanning trees exactly. With edge weights $w_e$ (use $w_e$ instead of $1$ in $L$), the same proof gives
$\det L_r=\sum_T\prod_{e\in T}w_e$ — the **weighted** matrix-tree theorem, which is what makes Example 5 work.

**Cayley's formula as a check.** For $K_n$, $L=nI-J$ has eigenvalues $0$ (once) and $n$ ($n-1$ times). The eigenvalue form of the theorem,
$\tau=\frac1n\prod_{i\ge2}\lambda_i$, gives $\tau(K_n)=n^{n-2}$.

### 1.2 Directed graphs: arborescences (🧊)

An **out-arborescence** rooted at $r$ is a spanning tree with all edges directed away from $r$: every vertex except $r$ has exactly one incoming
tree edge. Use the **in-degree Laplacian** $L_{vv}=\text{indeg}(v)$, $L_{uv}=-\#(u\to v)$, delete row and column $r$; the determinant counts
out-arborescences rooted at $r$ (Tutte's theorem). The proof is the same idea: each non-root vertex chooses one incoming edge (a column of the
minor), and choices containing a cycle cancel. For in-trees (all edges toward $r$) use out-degrees.

**BEST theorem.** For a connected Eulerian digraph, the number of Eulerian circuits is $t_w(G)\prod_v(\deg^+(v)-1)!$, where $t_w$ is the
number of arborescences oriented *toward* any fixed vertex $w$ — "count spanning in-trees, then the order in which each vertex uses its
remaining out-edges".

### 1.3 Non-intersecting paths: the LGV lemma (🔴)

Take a DAG, sources $a_1,\dots,a_k$, sinks $b_1,\dots,b_k$, and $e(a,b)=$ number of paths from $a$ to $b$. Let $M_{ij}=e(a_i,b_j)$. The
**Lindström–Gessel–Viennot lemma**:

$$\det M=\sum_{(P_1,\dots,P_k)\ \text{vertex-disjoint}}\operatorname{sign}(\sigma)\qquad(P_i: a_i\to b_{\sigma(i)}).$$

*Proof (sign-reversing involution).* Expanding $\det M=\sum_\sigma\operatorname{sign}\sigma\prod_ie(a_i,b_{\sigma(i)})$ counts all tuples of paths with sign.
For a tuple with an intersection, take the smallest $i$ whose path meets another, the first shared vertex $v$ on $P_i$, and the smallest $j$
whose path passes $v$; swap the tails of $P_i$ and $P_j$ after $v$. The new tuple has the same multiset of edges (weight), uses
$\sigma\circ(i\,j)$ (opposite sign), and applying the rule again swaps back — so intersecting tuples cancel in pairs.

In planar grids with sources and sinks "in order" (e.g. both along the boundary), the only permutation that admits disjoint paths is the identity,
so $\det M$ **is** the number of non-intersecting path systems. For two paths it is just $e_{11}e_{22}-e_{12}e_{21}$ — "all pairs minus the crossing
ones, where crossing pairs are in bijection with pairs going to swapped endpoints".

### 1.4 Determinants modulo $p$ — and modulo a composite

Gaussian elimination ([file 02](02-gaussian-elimination-and-xor-basis.md)) gives $\det$ in $O(n^3)$ over a field. For a **composite** modulus $M$
there are no inverses, but the determinant is unchanged by subtracting an *integer* multiple of one row from another. So clear column $i$ below
the diagonal with a **Euclidean algorithm on rows**: while $a_{ji}\ne0$, subtract $\lfloor a_{ii}/a_{ji}\rfloor$ times row $j$ from row $i$, then swap
rows $i$ and $j$ (negating $\det$). Each column needs $O(\log M)$ rounds per row in the worst case; $O(n^3+n^2\log M)$ amortised in practice.

### 1.5 Linear systems for probability and expectation

When a random process can return to earlier states, expectation DP has **cycles** and no evaluation order exists. Write one equation per
transient state, e.g. expected steps to absorption: $E_v=1+\sum_up_{vu}E_u$, and solve the linear system — $O(n^3)$ Gaussian elimination for up
to a few hundred states ([probability DP](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md)). Two structural speed-ups:

- **Layered systems**: if transitions only go "sideways or forward" (e.g. a robot that never moves up), solve layer by layer; each layer is a
  small system whose right-hand side uses the next layer.
- **Tridiagonal systems** (each unknown coupled only to its neighbours) are solved by the **Thomas algorithm** in $O(n)$: forward
  elimination $c'_j=\frac{c_j}{b_j-a_jc'_{j-1}}$, $d'_j=\frac{d_j-a_jd'_{j-1}}{b_j-a_jc'_{j-1}}$, then back substitution $x_j=d'_j-c'_jx_{j+1}$. It is
  numerically stable when the matrix is diagonally dominant (as in Example 4).

### 1.6 Determinants that are polynomials in a parameter

If matrix entries depend polynomially on $x$, then $\det$ is a polynomial in $x$ of bounded degree. Evaluate the determinant at $\deg+1$ values of
$x$ and **interpolate** the coefficients ([file 05](05-lagrange-interpolation-and-berlekamp-massey.md)). With the weighted matrix-tree theorem this
counts spanning trees **by the number of edges of a special kind**: weight $x$ on special edges, $1$ elsewhere, and $[x^k]\det$ is the number of trees
with exactly $k$ special edges (Example 5).

---

## 2. Formulas, definitions and identities

| Formula | Meaning | Cost |
|---|---|---|
| $L=D-A$, $\tau(G)=\det L_{\hat r\hat r}$ | Kirchhoff (any $r$) | $O(n^3)$ |
| $L=BB^T$; $\det(B_rB_r^T)=\sum_S\det(B_r[S])^2$ | Cauchy–Binet proof | |
| $\det L^{(w)}_{\hat r\hat r}=\sum_T\prod_{e\in T}w_e$ | weighted version | |
| $\tau=\frac1n\prod_{i=2}^{n}\lambda_i(L)$ | eigenvalue form | |
| $\tau(K_n)=n^{n-2}$, $\tau(K_{a,b})=a^{b-1}b^{a-1}$, $\tau(C_n)=n$ | classic counts | |
| $L_{vv}=\text{indeg}(v)$, $L_{uv}=-\#(u\to v)$ | out-arborescences rooted at $r$ | $O(n^3)$ |
| $ec(G)=t_w(G)\prod_v(\deg^+v-1)!$ | BEST theorem | |
| $\det[e(a_i,b_j)]=\sum_{\text{disjoint}}\operatorname{sign}\sigma$ | LGV lemma | |
| two paths: $e_{11}e_{22}-e_{12}e_{21}$ | non-intersecting pairs | |
| $\#$ monotone lattice paths $(0,0)\to(a,b)$: $\binom{a+b}{a}$ | grid path count | |
| $E_v=1+\sum_up_{vu}E_u$ | expected hitting time system | $O(n^3)$ |
| Thomas: $c'_j=\frac{c_j}{b_j-a_jc'_{j-1}}$, $d'_j=\frac{d_j-a_jd'_{j-1}}{b_j-a_jc'_{j-1}}$ | tridiagonal solve | $O(n)$ |
| Euclid row reduction | $\det$ mod composite $M$ | $O(n^3\log M)$ worst |

---

## 3. Implementation (C++ and Java)

```cpp
// Determinant modulo any M >= 1 (prime or not) by Euclid-style row reduction.
ll detAnyMod(vector<vector<ll>> a, ll M) {
    int n = a.size();
    ll det = 1 % M;
    for (auto& row : a) for (auto& v : row) v = ((v % M) + M) % M;
    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
            while (a[j][i] != 0) {                             // gcd on column i between rows i and j
                ll q = a[i][i] / a[j][i];
                for (int k = i; k < n; k++) a[i][k] = (a[i][k] - (__int128)q * a[j][k] % M + M) % M;
                swap(a[i], a[j]);
                det = (M - det) % M;
            }
        }
        if (a[i][i] == 0) return 0;
        det = (__int128)det * a[i][i] % M;
    }
    return det;
}
// Number of spanning trees of an undirected multigraph (self-loops ignored), modulo M.
ll spanningTrees(int n, const vector<pair<int, int>>& edges, ll M) {
    if (n == 1) return 1 % M;
    vector<vector<ll>> L(n - 1, vector<ll>(n - 1, 0));              // vertex n-1 removed
    for (auto [u, v] : edges) {
        if (u == v) continue;
        if (u < n - 1) L[u][u]++;
        if (v < n - 1) L[v][v]++;
        if (u < n - 1 && v < n - 1) { L[u][v]--; L[v][u]--; }
    }
    return detAnyMod(L, M);
}
// Out-arborescences rooted at r of a directed multigraph, modulo M.
ll arborescences(int n, const vector<pair<int, int>>& edges, int r, ll M) {
    if (n == 1) return 1 % M;
    vector<int> id(n, -1);
    for (int v = 0, k = 0; v < n; v++) if (v != r) id[v] = k++;
    vector<vector<ll>> L(n - 1, vector<ll>(n - 1, 0));
    for (auto [u, v] : edges) {
        if (u == v || v == r) continue;                         // edges into the root never appear in an out-tree
        L[id[v]][id[v]]++;
        if (u != r) L[id[u]][id[v]]--;
    }
    return detAnyMod(L, M);
}
// Thomas algorithm: a = sub-diagonal (a[0] unused), b = diagonal, c = super-diagonal (c[n-1] unused), d = rhs.
vector<ld> solveTridiagonal(vector<ld> a, vector<ld> b, vector<ld> c, vector<ld> d) {
    int n = b.size();
    for (int i = 1; i < n; i++) {
        ld w = a[i] / b[i - 1];
        b[i] -= w * c[i - 1];
        d[i] -= w * d[i - 1];
    }
    vector<ld> x(n);
    x[n - 1] = d[n - 1] / b[n - 1];
    for (int i = n - 2; i >= 0; i--) x[i] = (d[i] - c[i] * x[i + 1]) / b[i];
    return x;
}
```

```java
static long mulmod(long a, long b, long m) {
    return m <= 3_037_000_499L ? a * b % m : BigInteger.valueOf(a).multiply(BigInteger.valueOf(b)).mod(BigInteger.valueOf(m)).longValue();
}
static long detAnyMod(long[][] a0, long M) {
    int n = a0.length;
    long[][] a = new long[n][];
    for (int i = 0; i < n; i++) { a[i] = new long[n]; for (int j = 0; j < n; j++) a[i][j] = Math.floorMod(a0[i][j], M); }
    long det = 1 % M;
    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
            while (a[j][i] != 0) {
                long q = a[i][i] / a[j][i];
                for (int k = i; k < n; k++) a[i][k] = Math.floorMod(a[i][k] - mulmod(q % M, a[j][k], M), M);
                long[] t = a[i]; a[i] = a[j]; a[j] = t;
                det = (M - det) % M;
            }
        }
        if (a[i][i] == 0) return 0;
        det = mulmod(det, a[i][i], M);
    }
    return det;
}
static long spanningTrees(int n, int[][] edges, long M) {
    if (n == 1) return 1 % M;
    long[][] L = new long[n - 1][n - 1];
    for (int[] e : edges) {
        int u = e[0], v = e[1];
        if (u == v) continue;
        if (u < n - 1) L[u][u]++;
        if (v < n - 1) L[v][v]++;
        if (u < n - 1 && v < n - 1) { L[u][v]--; L[v][u]--; }
    }
    return detAnyMod(L, M);
}
static long arborescences(int n, int[][] edges, int r, long M) {
    if (n == 1) return 1 % M;
    int[] id = new int[n];
    for (int v = 0, k = 0; v < n; v++) id[v] = (v == r) ? -1 : k++;
    long[][] L = new long[n - 1][n - 1];
    for (int[] e : edges) {
        int u = e[0], v = e[1];
        if (u == v || v == r) continue;
        L[id[v]][id[v]]++;
        if (u != r) L[id[u]][id[v]]--;
    }
    return detAnyMod(L, M);
}
static double[] solveTridiagonal(double[] a, double[] b0, double[] c, double[] d0) {
    int n = b0.length;
    double[] b = b0.clone(), d = d0.clone(), x = new double[n];
    for (int i = 1; i < n; i++) { double w = a[i] / b[i - 1]; b[i] -= w * c[i - 1]; d[i] -= w * d[i - 1]; }
    x[n - 1] = d[n - 1] / b[n - 1];
    for (int i = n - 2; i >= 0; i--) x[i] = (d[i] - c[i] * x[i + 1]) / b[i];
    return x;
}
```

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "number of spanning trees", "ways to choose $n-1$ edges connecting everything" | Kirchhoff determinant |
| "spanning trees with exactly $k$ edges of type X" | weighted Laplacian with weight $x$, interpolate |
| "trees with forced / forbidden edges" | contract forced edges (DSU), delete forbidden, then Kirchhoff |
| "rooted directed spanning trees", "every node reachable from the root by unique path" | Tutte: in-degree Laplacian |
| "number of Euler circuits of a digraph" | BEST theorem |
| "two (or $k$) non-intersecting paths", "turtles", "disjoint routes in a grid" | LGV determinant |
| "determinant modulo $m$" with composite $m$ | Euclid row reduction |
| "expected time" with moves that can go back | linear system; tridiagonal if only neighbours couple |
| $n\le100$ and "count over all labelled trees" | Kirchhoff on $K_n$ with weights |

---

## 5. Worked examples (graded)

### Example 1 — Spanning trees modulo any $M$  ·  ★ ≈2100

- **Source:** Original problem.
- **Difficulty:** ≈2100 (est.)
- **Problem:** An undirected multigraph with $n\le200$ vertices and $m\le10^4$ edges (self-loops allowed), and a modulus $1\le M\le10^{12}$ (not
  necessarily prime). Print the number of spanning trees modulo $M$.
- **Thinking from first principles:** Enumerating edge subsets is hopeless; Kirchhoff turns the count into one determinant of the reduced Laplacian.
  Because $M$ may be composite, ordinary Gaussian elimination (which divides by pivots) is unavailable — but integer row operations are, so clear each
  column with a Euclidean algorithm between pairs of rows. Self-loops never belong to a spanning tree and are simply skipped; parallel edges add up
  in $A_{uv}$ and are counted correctly.

<details><summary>Solution</summary>

`spanningTrees` with `detAnyMod` from §3. Products use 128-bit intermediates since $M^2$ can exceed $2^{63}$. $O(n^3\log M)$ worst case.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll detAnyMod(vector<vector<ll>> a, ll M) {
    int n = a.size();
    ll det = 1 % M;
    for (auto& row : a) for (auto& v : row) v = ((v % M) + M) % M;
    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++)
            while (a[j][i] != 0) {
                ll q = a[i][i] / a[j][i];
                for (int k = i; k < n; k++) a[i][k] = (ll)((a[i][k] - (__int128)q * a[j][k] % M + M) % M);
                swap(a[i], a[j]);
                det = (M - det) % M;
            }
        if (a[i][i] == 0) return 0;
        det = (ll)((__int128)det * a[i][i] % M);
    }
    return det;
}
int main() {
    int n, m; ll M; cin >> n >> m >> M;
    vector<vector<ll>> L(max(0, n - 1), vector<ll>(max(0, n - 1), 0));
    for (int i = 0; i < m; i++) {
        int u, v; cin >> u >> v; u--; v--;
        if (u == v) continue;
        if (u < n - 1) L[u][u]++;
        if (v < n - 1) L[v][v]++;
        if (u < n - 1 && v < n - 1) { L[u][v]--; L[v][u]--; }
    }
    cout << (n == 1 ? 1 % M : detAnyMod(L, M)) << '\n';
}
```

```java
import java.util.*;
import java.io.*;
import java.math.BigInteger;

public class Main {
    static long mulmod(long a, long b, long m) {
        return m <= 3_037_000_499L ? a * b % m : BigInteger.valueOf(a).multiply(BigInteger.valueOf(b)).mod(BigInteger.valueOf(m)).longValue();
    }
    static long detAnyMod(long[][] a, long M) {
        int n = a.length;
        for (long[] row : a) for (int j = 0; j < n; j++) row[j] = Math.floorMod(row[j], M);
        long det = 1 % M;
        for (int i = 0; i < n; i++) {
            for (int j = i + 1; j < n; j++)
                while (a[j][i] != 0) {
                    long q = a[i][i] / a[j][i];
                    for (int k = i; k < n; k++) a[i][k] = Math.floorMod(a[i][k] - mulmod(q, a[j][k], M), M);
                    long[] t = a[i]; a[i] = a[j]; a[j] = t;
                    det = (M - det) % M;
                }
            if (a[i][i] == 0) return 0;
            det = mulmod(det, a[i][i], M);
        }
        return det;
    }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new String(System.in.readAllBytes()));
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
        long M = Long.parseLong(st.nextToken());
        long[][] L = new long[Math.max(0, n - 1)][Math.max(0, n - 1)];
        for (int i = 0; i < m; i++) {
            int u = Integer.parseInt(st.nextToken()) - 1, v = Integer.parseInt(st.nextToken()) - 1;
            if (u == v) continue;
            if (u < n - 1) L[u][u]++;
            if (v < n - 1) L[v][v]++;
            if (u < n - 1 && v < n - 1) { L[u][v]--; L[v][u]--; }
        }
        System.out.println(n == 1 ? 1 % M : detAnyMod(L, M));
    }
}
```

</details>

<!-- test
in:
4 6 1000000007
1 2
1 3
1 4
2 3
2 4
3 4
out:
16
-->
<!-- test
in:
3 4 1000000000000
1 2
1 2
2 3
3 3
out:
2
-->
<!-- test
in:
4 2 7
1 2
3 4
out:
0
-->
<!-- test
in:
5 10 12
1 2
1 3
1 4
1 5
2 3
2 4
2 5
3 4
3 5
4 5
out:
5
-->

### Example 2 — Counting arborescences  ·  ★ ≈2300

- **Source:** Original problem.
- **Difficulty:** ≈2300 (est.)
- **Problem:** A directed multigraph with $n\le200$ vertices, $m\le10^4$ edges and a root $r$. Count spanning out-arborescences rooted at $r$ (every
  vertex reachable from $r$ along tree edges), modulo $10^9+7$.
- **Thinking from first principles:** An out-arborescence is exactly "every non-root vertex picks one incoming edge, and the picks contain no cycle".
  The in-degree Laplacian minor (§1.2) is the determinant whose expansion enumerates those picks with signs that cancel the cyclic ones. Edges
  into the root and self-loops are irrelevant.

<details><summary>Solution</summary>

`arborescences` from §3 (here $M$ is prime, but the Euclid determinant works for any modulus). $O(n^3\log M)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
ll detAnyMod(vector<vector<ll>> a, ll M) {
    int n = a.size();
    ll det = 1 % M;
    for (auto& row : a) for (auto& v : row) v = ((v % M) + M) % M;
    for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++)
            while (a[j][i] != 0) {
                ll q = a[i][i] / a[j][i];
                for (int k = i; k < n; k++) a[i][k] = (ll)((a[i][k] - (__int128)q * a[j][k] % M + M) % M);
                swap(a[i], a[j]);
                det = (M - det) % M;
            }
        if (a[i][i] == 0) return 0;
        det = (ll)((__int128)det * a[i][i] % M);
    }
    return det;
}
int main() {
    int n, m, r; cin >> n >> m >> r; r--;
    vector<int> id(n, -1);
    for (int v = 0, k = 0; v < n; v++) if (v != r) id[v] = k++;
    vector<vector<ll>> L(max(0, n - 1), vector<ll>(max(0, n - 1), 0));
    for (int i = 0; i < m; i++) {
        int u, v; cin >> u >> v; u--; v--;
        if (u == v || v == r) continue;
        L[id[v]][id[v]]++;
        if (u != r) L[id[u]][id[v]]--;
    }
    cout << (n == 1 ? 1 : detAnyMod(L, MOD)) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long detMod(long[][] a, long M) {
        int n = a.length;
        for (long[] row : a) for (int j = 0; j < n; j++) row[j] = Math.floorMod(row[j], M);
        long det = 1 % M;
        for (int i = 0; i < n; i++) {
            for (int j = i + 1; j < n; j++)
                while (a[j][i] != 0) {
                    long q = a[i][i] / a[j][i];
                    for (int k = i; k < n; k++) a[i][k] = Math.floorMod(a[i][k] - q * a[j][k] % M, M);   // q, a < M < 3e9: no overflow
                    long[] t = a[i]; a[i] = a[j]; a[j] = t;
                    det = (M - det) % M;
                }
            if (a[i][i] == 0) return 0;
            det = det * a[i][i] % M;
        }
        return det;
    }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int m = (int) st.nval;
        st.nextToken(); int r = (int) st.nval - 1;
        int[] id = new int[n];
        for (int v = 0, k = 0; v < n; v++) id[v] = (v == r) ? -1 : k++;
        long[][] L = new long[Math.max(0, n - 1)][Math.max(0, n - 1)];
        for (int i = 0; i < m; i++) {
            st.nextToken(); int u = (int) st.nval - 1;
            st.nextToken(); int v = (int) st.nval - 1;
            if (u == v || v == r) continue;
            L[id[v]][id[v]]++;
            if (u != r) L[id[u]][id[v]]--;
        }
        System.out.println(n == 1 ? 1 : detMod(L, MOD));
    }
}
```

</details>

<!-- test
in:
3 3 1
1 2
2 3
1 3
out:
2
-->
<!-- test
in:
3 2 2
1 2
2 3
out:
0
-->
<!-- test
in:
3 6 1
1 2
2 1
1 3
3 1
2 3
3 2
out:
3
-->
<!-- test
in:
1 1 1
1 1
out:
1
-->

### Example 3 — Turtles (LGV)  ·  ★ 2500

- **Source:** [CF 348D · Turtles](https://codeforces.com/problemset/problem/348/D) — 2500
- **Difficulty:** 2500
- **Problem:** An $n\times m$ grid ($n,m\le3000$) with obstacles. Two turtles go from $(1,1)$ to $(n,m)$ moving right or down. Count pairs of paths that
  share no cell except the start and the end, modulo $10^9+7$.
- **Thinking from first principles:** Two such paths must leave the start through different neighbours — one through $(1,2)$, one through $(2,1)$ — and
  enter the end from $(n-1,m)$ and $(n,m-1)$. Strip the shared endpoints: we need vertex-disjoint paths from $a_1=(1,2)$, $a_2=(2,1)$ to
  $b_1=(n-1,m)$, $b_2=(n,m-1)$. By LGV, $e(a_1,b_1)e(a_2,b_2)-e(a_1,b_2)e(a_2,b_1)$ counts them: in a grid, any pair of paths $a_1\to b_2$, $a_2\to b_1$
  must cross, and the identity term counts exactly the disjoint pairs plus the crossing ones, which the swap bijection removes. Four path counts
  from two grid DPs.

<details><summary>Solution</summary>

One rolling-row DP from each of $(1,2)$ and $(2,1)$, reading values at $(n-1,m)$ and $(n,m-1)$. $O(nm)$ time, $O(m)$ extra memory.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
int n, m;
vector<string> g;
pair<ll, ll> paths(int sr, int sc) {                       // to (n-2, m-1) and (n-1, m-2), 0-indexed
    vector<ll> dp(m, 0);
    ll toA = 0, toB = 0;
    for (int i = 0; i < n; i++) {
        for (int j = 0; j < m; j++) {
            if (g[i][j] == '#') dp[j] = 0;
            else if (i == sr && j == sc) dp[j] = 1;
            else dp[j] = (dp[j] + (j > 0 ? dp[j - 1] : 0)) % MOD;
        }
        if (i == n - 2) toA = dp[m - 1];
        if (i == n - 1) toB = dp[m - 2];
    }
    return {toA, toB};
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    cin >> n >> m;
    g.resize(n);
    for (auto& s : g) cin >> s;
    auto [x1, y1] = paths(0, 1);                           // from (1,2)
    auto [x2, y2] = paths(1, 0);                           // from (2,1)
    cout << ((x1 * y2 - y1 * x2) % MOD + MOD) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static int n, m;
    static char[][] g;
    static long[] paths(int sr, int sc) {
        long[] dp = new long[m];
        long toA = 0, toB = 0;
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < m; j++) {
                if (g[i][j] == '#') dp[j] = 0;
                else if (i == sr && j == sc) dp[j] = 1;
                else dp[j] = (dp[j] + (j > 0 ? dp[j - 1] : 0)) % MOD;
            }
            if (i == n - 2) toA = dp[m - 1];
            if (i == n - 1) toB = dp[m - 2];
        }
        return new long[]{toA, toB};
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        n = Integer.parseInt(st.nextToken()); m = Integer.parseInt(st.nextToken());
        g = new char[n][];
        for (int i = 0; i < n; i++) g[i] = br.readLine().trim().toCharArray();
        long[] a = paths(0, 1), b = paths(1, 0);
        System.out.println(((a[0] * b[1] - a[1] * b[0]) % MOD + MOD) % MOD);
    }
}
```

</details>

<!-- test
in:
2 2
..
..
out:
1
-->
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
3 4
....
.#..
....
out:
2
-->
<!-- test
in:
2 3
.#.
...
out:
0
-->

### Example 4 — Broken robot (tridiagonal expectation)  ·  ★ 2400

- **Source:** [CF 24D · Broken robot](https://codeforces.com/problemset/problem/24/D) — 2400
- **Difficulty:** 2400
- **Problem:** A robot on an $N\times M$ board ($N,M\le1000$) starts at row $i$, column $j$ (rows numbered from the top). Each step it chooses uniformly
  among the valid moves: stay, left, right, down (no leaving the board). Find the expected number of steps to reach the bottom row.
- **Thinking from first principles:** Within a row the robot can wander left and right forever, so the expectation DP has cycles *inside* a row — but it
  never moves up, so rows are layers: if $D_c$ are the known values of the row below, the current row satisfies, for $M\ge2$,
  $2E_1-E_2=3+D_1$, $3E_c-E_{c-1}-E_{c+1}=4+D_c$, $2E_M-E_{M-1}=3+D_M$ (multiply $E_c=1+\frac1k\sum(\text{options})$ by the number of options $k$).
  That is a **tridiagonal**, strictly diagonally dominant system: Thomas algorithm in $O(M)$ per row. For $M=1$ the only moves are stay/down:
  $E=D+2$.

<details><summary>Solution</summary>

Rows from $N-1$ up to $i$; each row one Thomas solve. $O(NM)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ld = long double;
int main() {
    int N, M, si, sj; cin >> N >> M >> si >> sj;
    vector<ld> D(M, 0);
    for (int r = N - 1; r >= si; r--) {
        if (M == 1) { D[0] += 2; continue; }
        vector<ld> a(M, -1), b(M, 3), c(M, -1), d(M);
        b[0] = b[M - 1] = 2;
        for (int k = 0; k < M; k++) d[k] = (k == 0 || k == M - 1 ? 3 : 4) + D[k];
        for (int k = 1; k < M; k++) { ld w = a[k] / b[k - 1]; b[k] -= w * c[k - 1]; d[k] -= w * d[k - 1]; }
        D[M - 1] = d[M - 1] / b[M - 1];
        for (int k = M - 2; k >= 0; k--) D[k] = (d[k] - c[k] * D[k + 1]) / b[k];
    }
    cout << fixed << setprecision(10) << D[sj - 1] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int N = (int) st.nval; st.nextToken(); int M = (int) st.nval;
        st.nextToken(); int si = (int) st.nval; st.nextToken(); int sj = (int) st.nval;
        double[] D = new double[M], b = new double[M], d = new double[M];
        for (int r = N - 1; r >= si; r--) {
            if (M == 1) { D[0] += 2; continue; }
            for (int k = 0; k < M; k++) { b[k] = (k == 0 || k == M - 1) ? 2 : 3; d[k] = ((k == 0 || k == M - 1) ? 3 : 4) + D[k]; }
            for (int k = 1; k < M; k++) { double w = -1 / b[k - 1]; b[k] -= w * -1; d[k] -= w * d[k - 1]; }
            D[M - 1] = d[M - 1] / b[M - 1];
            for (int k = M - 2; k >= 0; k--) D[k] = (d[k] + D[k + 1]) / b[k];   // c[k] = -1
        }
        System.out.println(String.format(Locale.US, "%.10f", D[sj - 1]));
    }
}
```

</details>

<!-- test
in:
2 1
1 1
out:
2.0000000000
-->
<!-- test
in:
2 2
1 1
out:
3.0000000000
-->
<!-- test
in:
3 3
1 2
out:
6.8750000000
-->
<!-- test
in:
4 5
2 1
out:
6.8677685950
-->
<!-- test
in:
7 3
7 2
out:
0.0000000000
-->

### Example 5 — Stranger Trees (weighted Kirchhoff + interpolation)  ·  ★ 2600

- **Source:** [CF 917D · Stranger Trees](https://codeforces.com/problemset/problem/917/D) — 2600
- **Difficulty:** 2600
- **Problem:** A tree $T$ on $n\le100$ labelled vertices. For every $k=0..n-1$, count labelled trees on the same vertices that share exactly $k$ edges with
  $T$, modulo $10^9+7$.
- **Thinking from first principles:** All labelled trees are the spanning trees of $K_n$. Give the $n-1$ edges of $T$ weight $x$ and all other edges weight
  $1$: by the weighted matrix-tree theorem the reduced Laplacian's determinant is $P(x)=\sum_{\text{trees }S}x^{\lvert S\cap T\rvert}=\sum_k\text{ans}_kx^k$, a
  polynomial of degree $\le n-1$. We cannot run elimination with a symbolic $x$, but we can evaluate $P$ at $n$ points $x=0..n-1$ (one $O(n^3)$
  determinant each) and **interpolate the coefficients** in $O(n^2)$. Total $O(n^4)=10^8$ — fine. (A tree-DP in $O(n^2)$ also exists; the
  linear-algebra route needs no cleverness about the tree at all.)

<details><summary>Solution</summary>

Determinant modulo the prime by Gaussian elimination; coefficients from the Lagrange basis $\prod_{j\ne i}\frac{x-j}{i-j}$, using
$M(x)=\prod_j(x-j)$ divided by $(x-i)$ synthetically.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
ll pw(ll b, ll e) { ll r = 1; b %= MOD; if (b < 0) b += MOD; for (; e; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD; return r; }
ll det(vector<vector<ll>> a) {
    int n = a.size();
    ll d = 1;
    for (int c = 0; c < n; c++) {
        int p = -1;
        for (int i = c; i < n; i++) if (a[i][c]) { p = i; break; }
        if (p < 0) return 0;
        if (p != c) { swap(a[p], a[c]); d = MOD - d; }
        d = d * a[c][c] % MOD;
        ll inv = pw(a[c][c], MOD - 2);
        for (int i = c + 1; i < n; i++) if (a[i][c]) {
            ll f = a[i][c] * inv % MOD;
            for (int j = c; j < n; j++) a[i][j] = (a[i][j] - f * a[c][j] % MOD + MOD) % MOD;
        }
    }
    return d % MOD;
}
int main() {
    int n; cin >> n;
    vector<vector<int>> inT(n, vector<int>(n, 0));
    for (int i = 0; i < n - 1; i++) { int u, v; cin >> u >> v; u--; v--; inT[u][v] = inT[v][u] = 1; }
    vector<ll> y(n);
    for (int x = 0; x < n; x++) {                            // P(x) = det of reduced weighted Laplacian of K_n
        vector<vector<ll>> L(n - 1, vector<ll>(n - 1, 0));
        for (int u = 0; u < n - 1; u++) for (int v = 0; v < n; v++) if (u != v) {
            ll w = inT[u][v] ? x : 1;
            L[u][u] = (L[u][u] + w) % MOD;
            if (v < n - 1) L[u][v] = (L[u][v] - w + MOD) % MOD;
        }
        y[x] = det(L);
    }
    vector<ll> Mx(n + 1, 0);                                 // M(x) = prod_{j<n} (x - j)
    Mx[0] = 1;
    for (int j = 0; j < n; j++)
        for (int k = j + 1; k >= 0; k--) Mx[k] = ((k ? Mx[k - 1] : 0) - (ll)j * Mx[k] % MOD + MOD) % MOD;
    vector<ll> ans(n, 0), q(n);
    for (int i = 0; i < n; i++) {
        q[n - 1] = Mx[n];                                    // q = M(x) / (x - i)
        for (int k = n - 1; k >= 1; k--) q[k - 1] = (Mx[k] + (ll)i * q[k]) % MOD;
        ll den = 1;
        for (int j = 0; j < n; j++) if (j != i) den = den * ((i - j + MOD) % MOD) % MOD;
        ll coef = y[i] * pw(den, MOD - 2) % MOD;
        for (int k = 0; k < n; k++) ans[k] = (ans[k] + coef * q[k]) % MOD;
    }
    for (int k = 0; k < n; k++) cout << ans[k] << (k + 1 < n ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long pw(long b, long e) { long r = 1; b %= MOD; if (b < 0) b += MOD; for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD; return r; }
    static long det(long[][] a) {
        int n = a.length;
        long d = 1;
        for (int c = 0; c < n; c++) {
            int p = -1;
            for (int i = c; i < n; i++) if (a[i][c] != 0) { p = i; break; }
            if (p < 0) return 0;
            if (p != c) { long[] t = a[p]; a[p] = a[c]; a[c] = t; d = MOD - d; }
            d = d * a[c][c] % MOD;
            long inv = pw(a[c][c], MOD - 2);
            for (int i = c + 1; i < n; i++) if (a[i][c] != 0) {
                long f = a[i][c] * inv % MOD;
                long[] ai = a[i], ac = a[c];
                for (int j = c; j < n; j++) { ai[j] = (ai[j] - f * ac[j]) % MOD; if (ai[j] < 0) ai[j] += MOD; }
            }
        }
        return d % MOD;
    }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        boolean[][] inT = new boolean[n][n];
        for (int i = 0; i < n - 1; i++) {
            st.nextToken(); int u = (int) st.nval - 1; st.nextToken(); int v = (int) st.nval - 1;
            inT[u][v] = inT[v][u] = true;
        }
        long[] y = new long[n];
        for (int x = 0; x < n; x++) {
            long[][] L = new long[n - 1][n - 1];
            for (int u = 0; u < n - 1; u++) for (int v = 0; v < n; v++) if (u != v) {
                long w = inT[u][v] ? x : 1;
                L[u][u] = (L[u][u] + w) % MOD;
                if (v < n - 1) L[u][v] = (L[u][v] - w + MOD) % MOD;
            }
            y[x] = det(L);
        }
        long[] Mx = new long[n + 1];
        Mx[0] = 1;
        for (int j = 0; j < n; j++)
            for (int k = j + 1; k >= 0; k--) Mx[k] = ((k > 0 ? Mx[k - 1] : 0) - (long) j * Mx[k] % MOD + MOD) % MOD;
        long[] ans = new long[n], q = new long[n];
        for (int i = 0; i < n; i++) {
            q[n - 1] = Mx[n];
            for (int k = n - 1; k >= 1; k--) q[k - 1] = (Mx[k] + (long) i * q[k]) % MOD;
            long den = 1;
            for (int j = 0; j < n; j++) if (j != i) den = den * ((i - j + MOD) % MOD) % MOD;
            long coef = y[i] * pw(den, MOD - 2) % MOD;
            for (int k = 0; k < n; k++) ans[k] = (ans[k] + coef * q[k]) % MOD;
        }
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < n; k++) sb.append(ans[k]).append(k + 1 < n ? ' ' : '\n');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
1
out:
1
-->
<!-- test
in:
3
1 2
1 3
out:
0 2 1
-->
<!-- test
in:
4
1 2
2 3
3 4
out:
1 7 7 1
-->
<!-- test
in:
5
1 2
1 3
1 4
1 5
out:
0 64 48 12 1
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Delete exactly one row and the same column** of the Laplacian; the full Laplacian always has determinant $0$.
2. **Self-loops** never appear in spanning trees: skip them when building $L$ (they would add to the degree without a matching $-1$).
3. **Disconnected graph** ⇒ determinant $0$ automatically; no special case needed.
4. **Forced edges**: contract them with DSU first (a cycle among forced edges ⇒ answer $0$), then count spanning trees of the contracted multigraph.
5. **Directed version**: in-degree Laplacian for out-trees (edges away from the root), out-degree for in-trees; mixing them up gives a wrong but
   plausible number. Verify on a 3-vertex example.
6. **Composite modulus**: use Euclid row reduction; never compute inverses. For $M>3\cdot10^9$ products need 128-bit arithmetic.
7. **LGV needs the right pairing**: in non-planar situations other permutations contribute with signs; the determinant counts the *signed* sum.
8. **Expectation systems in `double`**: prefer structure (layers, tridiagonal) over general Gauss — less error and $O(n)$ instead of $O(n^3)$.
   Strict diagonal dominance makes the Thomas algorithm stable without pivoting.
9. **$m=1$ / $n=1$ edge cases**: Broken robot with one column has no left/right moves; a one-vertex graph has exactly one spanning tree (the empty
   determinant).
10. **Interpolating a determinant**: degree bound = number of variable-weight edges a spanning tree can contain ($\le n-1$); sample $n$ points.

---

## 7. Going further (toward 2400–2600+)

- **Kirchhoff with forced edges**: [AtCoder JSC2021 G · Spanning Tree](https://atcoder.jp/contests/jsc2021/tasks/jsc2021_g) — diff≈2451
  (contract forced edges, delete forbidden ones).
- **Matrix-tree inside a subset DP**: [AtCoder ABC253 Ex · We Love Forest](https://atcoder.jp/contests/abc253/tasks/abc253_h) — diff≈2758.
- **Gaussian elimination on pair states for meeting probabilities**: [CF 113D · Museum](https://codeforces.com/problemset/problem/113/D) — 2700.
- **Banded systems on a disc of lattice points**: [CF 963E · Circles of Waiting](https://codeforces.com/problemset/problem/963/E) — 3100.
- **Spanning trees with colour constraints**: [AtCoder ABC399 G · Colorful Spanning Tree](https://atcoder.jp/contests/abc399/tasks/abc399_g) — diff≈3625.
- **BEST theorem** problems (count Euler circuits) and **Pfaffians** for perfect matchings of planar graphs (FKT) are IGM/ICPC depth.

---

## 8. Practice ladder

**1900–2300**
- [ ] [CSES 3154 · System of Linear Equations](https://cses.fi/problemset/task/3154)

**2400+**
- [ ] [CF 24D · Broken robot](https://codeforces.com/problemset/problem/24/D) — 2400
- [ ] [AtCoder JSC2021 G · Spanning Tree](https://atcoder.jp/contests/jsc2021/tasks/jsc2021_g) — diff≈2451
- [ ] [CF 348D · Turtles](https://codeforces.com/problemset/problem/348/D) — 2500
- [ ] [CF 917D · Stranger Trees](https://codeforces.com/problemset/problem/917/D) — 2600
- [ ] [CF 113D · Museum](https://codeforces.com/problemset/problem/113/D) — 2700
- [ ] [AtCoder ABC253 Ex · We Love Forest](https://atcoder.jp/contests/abc253/tasks/abc253_h) — diff≈2758
- [ ] [CF 963E · Circles of Waiting](https://codeforces.com/problemset/problem/963/E) — 3100

---

## 9. LeetCode / FAANG cross-reference

Rare in interviews: determinants, Kirchhoff and LGV are outside the FAANG syllabus. The interview-adjacent idea is the grid path count
$\binom{a+b}{a}$ ([LC 62 · Unique Paths](https://leetcode.com/problems/unique-paths/) — Medium), of which LGV is the multi-path generalisation, and
"expected value with cycles ⇒ linear equations" (sometimes asked as a follow-up to random-walk questions).

---

## 10. Self-check

1. State Kirchhoff's theorem and sketch the Cauchy–Binet proof.
2. Why is $\tau(K_n)=n^{n-2}$ from the eigenvalues of $L$?
3. Which Laplacian counts out-arborescences rooted at $r$?
4. Prove the LGV lemma's cancellation step for two paths.
5. In Turtles, why are the sources $(1,2),(2,1)$ and the sinks $(n-1,m),(n,m-1)$?
6. How do you compute a determinant modulo $10^9$ (composite)?
7. Why is the Broken-robot row system tridiagonal and why is the Thomas algorithm safe?
8. In Stranger Trees, why is $\det L(x)$ a polynomial of degree $\le n-1$ whose $x^k$ coefficient is the answer?

<details><summary>Answers</summary>

1. $\tau(G)=\det L_{\hat r\hat r}$. With $L=BB^T$, Cauchy–Binet gives $\sum_S\det(B_r[S])^2$ over $(n-1)$-edge sets; the minor is $\pm1$ for spanning trees
   (peel leaves) and $0$ for sets containing a cycle.
2. $L(K_n)=nI-J$ has eigenvalues $0,n,\dots,n$; $\tau=\frac1n\prod_{i\ge2}\lambda_i=\frac1nn^{n-1}=n^{n-2}$.
3. $L_{vv}=$ in-degree, $L_{uv}=-\#(u\to v)$; delete row and column $r$.
4. For crossing paths $a_1\to b_1$, $a_2\to b_2$, swap tails at the first common vertex: a bijection with path pairs $a_1\to b_2$, $a_2\to b_1$, which carry
   the opposite sign in $\det$; non-crossing pairs remain.
5. Disjoint paths must leave the start by different cells and enter the end by different cells; removing the shared endpoints leaves four distinct terminals.
6. Euclidean row reduction: repeatedly subtract integer multiples of rows (and swap) until the column below the pivot is zero; track the sign.
7. The robot never moves up and only sideways by one, so each unknown in a row couples only to its neighbours; the matrix is strictly diagonally
   dominant ($2>1$, $3>2$), so no pivoting is needed and errors do not grow.
8. By the weighted matrix-tree theorem $\det=\sum_S\prod_{e\in S}w_e=\sum_Sx^{\lvert S\cap T\rvert}$, and a spanning tree has at most $n-1$ edges of $T$.

</details>
