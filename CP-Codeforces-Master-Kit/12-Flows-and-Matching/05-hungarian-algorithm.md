# The Hungarian Algorithm (Assignment Problem in $O(n^3)$)

> **Band:** 🟠 2000–2500 · **Priority:** ⚡ (🔥 if you meet many assignment problems; min-cost flow covers the rest) · **FAANG:** low · **Prerequisites:** [bipartite matching](03-bipartite-matching-kuhn-hopcroft-karp.md), [min-cost flow](04-min-cost-flow.md)
> **You can say you know this when:** you can derive the algorithm from LP duality (potentials $u_i+v_j\le c_{ij}$, tight edges), explain the $\delta$ update and why it is $O(n^2)$ per row,
> and adapt it to maximization, rectangular matrices and forbidden pairs.

## 1. First principles — why this works

**The assignment problem.** An $n\times m$ cost matrix ($n\le m$): assign every row (worker) to a distinct column (job) minimizing the total cost. Brute force is $m!/(m-n)!$; bitmask DP is
$O(2^n n)$ — fine for $n\le 20$, hopeless for $n=200$. Min-cost flow solves it in $O(n\cdot n^2\log n)$; the Hungarian algorithm is the same idea specialized to dense bipartite graphs, $O(n^2m)$.

**A lower bound you can certify.** Suppose we choose numbers $u_i$ (one per row) and $v_j$ (one per column) such that
$$u_i + v_j \le c_{ij}\quad\text{for all } i,j.$$
For any assignment $\sigma$, $\sum_i c_{i\sigma(i)} \ge \sum_i (u_i + v_{\sigma(i)}) = \sum_i u_i + \sum_{j\in\sigma} v_j$. If additionally $v_j\le 0$ for unused columns (true in the algorithm below,
which starts from $v=0$ and only decreases $v$ on columns it ends up using), every assignment costs at least $\sum u + \sum v$. This is LP duality: the potentials are the dual variables of
$$\min \sum c_{ij}x_{ij}\ \text{ s.t. } \sum_j x_{ij} = 1,\ \sum_i x_{ij}\le 1,\ x\ge 0.$$

**When is the bound tight?** If we find an assignment that uses only **tight** cells ($u_i+v_j=c_{ij}$), its cost equals the bound, so it is optimal (complementary slackness).
So the algorithm keeps two invariants:

1. *Feasibility*: reduced costs $c_{ij}-u_i-v_j\ge 0$ everywhere.
2. *Tightness*: every matched pair is tight.

and grows the matching one row at a time.

**Adding one row.** Row $i$ is new and unmatched. Search for an augmenting path in the **equality subgraph** (tight cells only): from row $i$ go to any tight column $j$; if $j$ is free we are done;
otherwise continue from the row matched to $j$ (an alternating tree, exactly like Kuhn). If the tree gets stuck — no tight cell from a tree row to a non-tree column — change the potentials:
let $\delta = \min\{c_{ij}-u_i-v_j : i\text{ in tree},\ j\text{ not in tree}\}$ and set $u_i \mathrel{+}= \delta$ for tree rows, $v_j \mathrel{-}= \delta$ for tree columns.

- Tree edges (row in tree, column in tree) keep their reduced cost: $+\delta-\delta=0$. Matched pairs stay tight.
- Cells from tree rows to non-tree columns drop by $\delta$; at least one becomes tight, so the tree can grow. Feasibility holds by the choice of $\delta$ as the minimum.
- Cells from non-tree rows to tree columns *increase* — harmless.

Each $\delta$ step adds at least one column to the tree, so after at most $m$ steps a free column is reached and the path is flipped.

**Making a step $O(m)$.** Maintain, for every non-tree column $j$, $\text{minv}[j] = \min_{i\in\text{tree}} (c_{ij}-u_i-v_j)$ and which tree column led to it (`way[j]`). When a row joins the tree,
update minv in $O(m)$; $\delta = \min_j \text{minv}[j]$ in $O(m)$; applying $\delta$ is $O(m)$ (subtract it from minv of non-tree columns instead of touching all cells). A row costs $O(m)$ steps of $O(m)$,
so the total is $O(n m^2)$, i.e. $O(n^3)$ for square matrices.

**The same thing as min-cost flow.** `minv` is a Dijkstra distance array over columns with reduced costs; the $\delta$ updates are the potential shifts of [successive shortest paths](04-min-cost-flow.md).
Hungarian = SSP on the assignment network with the $O(V^2)$ dense Dijkstra, where each row is one augmentation.

**Variants.**
- *Maximize*: run on $-c$ (or $C-c$ with $C=\max c$; equivalent because every assignment has exactly $n$ cells).
- *Rectangular $n\le m$*: works as is (extra columns stay unmatched). If $n>m$, transpose.
- *Forbidden pairs*: cost $\text{BIG}$ larger than $n\cdot\max c$; the optimum uses a forbidden cell iff no perfect matching avoids them.
- *Bottleneck* (minimize the maximum cost): binary search the threshold + bipartite matching — not Hungarian.

## 2. Formulas, definitions and identities

- **Primal**: $\min \sum_{i,j} c_{ij}x_{ij}$, $\ \sum_j x_{ij}=1\ \forall i$, $\ \sum_i x_{ij}\le 1\ \forall j$, $\ x\ge0$. The constraint matrix is totally unimodular (bipartite incidence), so an integral optimum exists.
- **Dual**: $\max \sum_i u_i + \sum_j v_j$, $\ u_i+v_j\le c_{ij}$, $\ v_j\le 0$ (for the $\le 1$ column constraints; equality columns have free $v_j$).
- **Reduced cost**: $\bar c_{ij} = c_{ij}-u_i-v_j\ge 0$; **complementary slackness**: $x_{ij}=1\Rightarrow \bar c_{ij}=0$.
- **$\delta$ step**: $\delta=\min_{i\in T_R,\ j\notin T_C}\bar c_{ij}$; $\ u_i\mathrel{+}=\delta\ (i\in T_R)$, $v_j\mathrel{-}=\delta\ (j\in T_C)$.
- **Dual objective increases** by $\delta\cdot(|T_R|-|T_C|) = \delta$ per step (the tree has one more row than columns) — the lower bound rises monotonically.
- **Optimal value**: $\sum_i c_{i\sigma(i)} = \sum_i u_i + \sum_{j \text{ matched}} v_j$ at termination.
- **Birkhoff–von Neumann** (🧊): every doubly stochastic matrix is a convex combination of permutation matrices — another proof that the LP optimum is attained at a permutation.
- **Complexity**: $O(n^2m)$ time, $O(nm)$ memory for the matrix plus $O(m)$ extra.

## 3. Implementation (C++ and Java)

Input: an $n\times m$ matrix with $n\le m$ (0-indexed). Output: the minimum cost and `row → column`. Internally 1-indexed with a virtual column 0 that holds the row being inserted.

```cpp
// Minimum-cost assignment of every row to a distinct column; requires n <= m.
pair<ll, vector<int>> hungarian(const vector<vector<ll>> &c) {
    int n = c.size(), m = c[0].size();
    const ll INF = LLONG_MAX / 4;
    vector<ll> u(n + 1, 0), v(m + 1, 0);
    vector<int> rowOf(m + 1, 0), way(m + 1, 0);    // rowOf[j] = row matched to column j (0 = free)
    for (int i = 1; i <= n; i++) {
        rowOf[0] = i;                               // column 0 temporarily holds the new row
        int j0 = 0;
        vector<ll> minv(m + 1, INF);
        vector<char> inTree(m + 1, 0);
        do {
            inTree[j0] = 1;
            int i0 = rowOf[j0], j1 = 0;
            ll delta = INF;
            for (int j = 1; j <= m; j++) if (!inTree[j]) {
                ll cur = c[i0 - 1][j - 1] - u[i0] - v[j];            // reduced cost from the newest tree row
                if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
                if (minv[j] < delta) { delta = minv[j]; j1 = j; }
            }
            for (int j = 0; j <= m; j++) {
                if (inTree[j]) { u[rowOf[j]] += delta; v[j] -= delta; }
                else minv[j] -= delta;
            }
            j0 = j1;                                // j1 is now tight
        } while (rowOf[j0] != 0);                   // stop at a free column
        do { int j1 = way[j0]; rowOf[j0] = rowOf[j1]; j0 = j1; } while (j0);   // flip the path
    }
    vector<int> colOf(n);
    for (int j = 1; j <= m; j++) if (rowOf[j]) colOf[rowOf[j] - 1] = j - 1;
    ll cost = 0;
    for (int i = 0; i < n; i++) cost += c[i][colOf[i]];
    return {cost, colOf};
}
```

```java
// Minimum-cost assignment of every row to a distinct column; requires n <= m. Returns colOf[], cost in costOut[0].
static int[] hungarian(long[][] c, long[] costOut) {
    int n = c.length, m = c[0].length;
    final long INF = Long.MAX_VALUE / 4;
    long[] u = new long[n + 1], v = new long[m + 1], minv = new long[m + 1];
    int[] rowOf = new int[m + 1], way = new int[m + 1];
    boolean[] inTree = new boolean[m + 1];
    for (int i = 1; i <= n; i++) {
        rowOf[0] = i;
        int j0 = 0;
        Arrays.fill(minv, INF);
        Arrays.fill(inTree, false);
        do {
            inTree[j0] = true;
            int i0 = rowOf[j0], j1 = 0;
            long delta = INF;
            for (int j = 1; j <= m; j++) if (!inTree[j]) {
                long cur = c[i0 - 1][j - 1] - u[i0] - v[j];
                if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
                if (minv[j] < delta) { delta = minv[j]; j1 = j; }
            }
            for (int j = 0; j <= m; j++) {
                if (inTree[j]) { u[rowOf[j]] += delta; v[j] -= delta; }
                else minv[j] -= delta;
            }
            j0 = j1;
        } while (rowOf[j0] != 0);
        do { int j1 = way[j0]; rowOf[j0] = rowOf[j1]; j0 = j1; } while (j0 != 0);
    }
    int[] colOf = new int[n];
    for (int j = 1; j <= m; j++) if (rowOf[j] != 0) colOf[rowOf[j] - 1] = j - 1;
    long cost = 0;
    for (int i = 0; i < n; i++) cost += c[i][colOf[i]];
    costOut[0] = cost;
    return colOf;
}
```

Notes on the code: `rowOf[0] = i` lets the first iteration treat the new row as "the row matched to the virtual column 0", so the same loop handles the root. The final `do … while (j0)`
walks `way[]` back from the free column to column 0, shifting each matched row one column along the augmenting path.

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "$n$ workers, $n$ jobs, cost matrix", $n\le 500$ | Hungarian, $O(n^3)$ |
| $n\le 20$ | bitmask DP is simpler ($O(2^n n)$) |
| "maximize total compatibility / profit" | Hungarian on negated costs |
| more columns than rows ("choose $n$ of $m$ slots") | rectangular Hungarian, $n\le m$ |
| some pairs impossible | big cost; check the result |
| costs on a line / sorted structure ($\lvert a_i-b_j\rvert$) | sort both and match in order (exchange argument), or DP |
| capacities > 1 or extra side constraints | min-cost flow instead |
| "minimize the maximum cost" | binary search + matching, not Hungarian |

## 5. Worked examples (graded)

### Example 1 — Task Assignment  ·  ★ ≈2200

- **Source:** [CSES 2129 · Task Assignment](https://cses.fi/problemset/task/2129)
- **Difficulty:** ≈2200 (est.)
- **Problem:** $n\le 200$ employees and $n$ tasks; employee $i$ doing task $j$ costs $c_{ij}$. Each employee does exactly one task and each task is done once. Print the minimum total cost and
  an optimal assignment (one line "employee task" per employee).
- **Thinking from first principles:** a square assignment problem with $n=200$: $n^3=8\cdot10^6$. Min-cost flow also works ($n$ Dijkstras on $n^2$ edges), Hungarian is the compact choice.
  Several optimal assignments may exist; the tests here have a unique optimum.

<details><summary>Solution</summary>

Hungarian as in §3, then print employee $i$ with task `colOf[i]`, in increasing $i$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

pair<ll, vector<int>> hungarian(const vector<vector<ll>> &c) {
    int n = c.size(), m = c[0].size();
    const ll INF = LLONG_MAX / 4;
    vector<ll> u(n + 1, 0), v(m + 1, 0);
    vector<int> rowOf(m + 1, 0), way(m + 1, 0);
    for (int i = 1; i <= n; i++) {
        rowOf[0] = i;
        int j0 = 0;
        vector<ll> minv(m + 1, INF);
        vector<char> inTree(m + 1, 0);
        do {
            inTree[j0] = 1;
            int i0 = rowOf[j0], j1 = 0;
            ll delta = INF;
            for (int j = 1; j <= m; j++) if (!inTree[j]) {
                ll cur = c[i0 - 1][j - 1] - u[i0] - v[j];
                if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
                if (minv[j] < delta) { delta = minv[j]; j1 = j; }
            }
            for (int j = 0; j <= m; j++) {
                if (inTree[j]) { u[rowOf[j]] += delta; v[j] -= delta; }
                else minv[j] -= delta;
            }
            j0 = j1;
        } while (rowOf[j0] != 0);
        do { int j1 = way[j0]; rowOf[j0] = rowOf[j1]; j0 = j1; } while (j0);
    }
    vector<int> colOf(n);
    for (int j = 1; j <= m; j++) if (rowOf[j]) colOf[rowOf[j] - 1] = j - 1;
    ll cost = 0;
    for (int i = 0; i < n; i++) cost += c[i][colOf[i]];
    return {cost, colOf};
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<vector<ll>> c(n, vector<ll>(n));
    for (auto &row : c) for (auto &x : row) cin >> x;
    auto [cost, colOf] = hungarian(c);
    cout << cost << "\n";
    for (int i = 0; i < n; i++) cout << i + 1 << " " << colOf[i] + 1 << "\n";
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

    static int[] hungarian(long[][] c, long[] costOut) {
        int n = c.length, m = c[0].length;
        final long INF = Long.MAX_VALUE / 4;
        long[] u = new long[n + 1], v = new long[m + 1], minv = new long[m + 1];
        int[] rowOf = new int[m + 1], way = new int[m + 1];
        boolean[] inTree = new boolean[m + 1];
        for (int i = 1; i <= n; i++) {
            rowOf[0] = i;
            int j0 = 0;
            Arrays.fill(minv, INF);
            Arrays.fill(inTree, false);
            do {
                inTree[j0] = true;
                int i0 = rowOf[j0], j1 = 0;
                long delta = INF;
                for (int j = 1; j <= m; j++) if (!inTree[j]) {
                    long cur = c[i0 - 1][j - 1] - u[i0] - v[j];
                    if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
                    if (minv[j] < delta) { delta = minv[j]; j1 = j; }
                }
                for (int j = 0; j <= m; j++) {
                    if (inTree[j]) { u[rowOf[j]] += delta; v[j] -= delta; }
                    else minv[j] -= delta;
                }
                j0 = j1;
            } while (rowOf[j0] != 0);
            do { int j1 = way[j0]; rowOf[j0] = rowOf[j1]; j0 = j1; } while (j0 != 0);
        }
        int[] colOf = new int[n];
        for (int j = 1; j <= m; j++) if (rowOf[j] != 0) colOf[rowOf[j] - 1] = j - 1;
        long cost = 0;
        for (int i = 0; i < n; i++) cost += c[i][colOf[i]];
        costOut[0] = cost;
        return colOf;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nextLong();
        long[][] c = new long[n][n];
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) c[i][j] = nextLong();
        long[] cost = new long[1];
        int[] colOf = hungarian(c, cost);
        StringBuilder sb = new StringBuilder().append(cost[0]).append('\n');
        for (int i = 0; i < n; i++) sb.append(i + 1).append(' ').append(colOf[i] + 1).append('\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }
}
```

</details>

All three tests have a unique optimal assignment (checked by enumerating all permutations). In the first, the row minima (8, 7, 6, 7) cannot all be used — columns clash — and the optimum 33
uses row 1's second-best cell.

<!-- test
in:
4
17 8 16 9
7 15 12 19
6 9 10 11
14 7 13 10
out:
33
1 4
2 1
3 3
4 2
-->
<!-- test
in:
1
5
out:
5
1 1
-->
<!-- test
in:
3
1 2 3
2 4 6
3 6 9
out:
10
1 3
2 2
3 1
-->
<!-- test
in:
3
4 1 3
2 0 5
3 2 2
out:
5
1 2
2 1
3 3
-->

### Example 2 — Maximum profit with spare jobs  ·  ★ ≈2000

- **Source:** Original problem.
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n$ workers and $m$ jobs ($1\le n\le m\le 300$); worker $i$ earns $p_{ij}\in[0,10^6]$ on job $j$. Every worker must take a different job (some jobs stay unused).
  Print the maximum total profit.
- **Thinking from first principles:** two changes from the textbook case. *Maximize*: the dual argument is symmetric, so negate the matrix (every assignment uses exactly $n$ cells, so negation
  is exact). *Rectangular*: the algorithm inserts rows one at a time and never needs every column to be matched, so $n\le m$ works directly; unused columns keep $v_j=0$.

<details><summary>Solution</summary>

Run Hungarian on $c_{ij} = -p_{ij}$ and print $-\text{cost}$. $O(n^2 m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

pair<ll, vector<int>> hungarian(const vector<vector<ll>> &c) {
    int n = c.size(), m = c[0].size();
    const ll INF = LLONG_MAX / 4;
    vector<ll> u(n + 1, 0), v(m + 1, 0);
    vector<int> rowOf(m + 1, 0), way(m + 1, 0);
    for (int i = 1; i <= n; i++) {
        rowOf[0] = i;
        int j0 = 0;
        vector<ll> minv(m + 1, INF);
        vector<char> inTree(m + 1, 0);
        do {
            inTree[j0] = 1;
            int i0 = rowOf[j0], j1 = 0;
            ll delta = INF;
            for (int j = 1; j <= m; j++) if (!inTree[j]) {
                ll cur = c[i0 - 1][j - 1] - u[i0] - v[j];
                if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
                if (minv[j] < delta) { delta = minv[j]; j1 = j; }
            }
            for (int j = 0; j <= m; j++) {
                if (inTree[j]) { u[rowOf[j]] += delta; v[j] -= delta; }
                else minv[j] -= delta;
            }
            j0 = j1;
        } while (rowOf[j0] != 0);
        do { int j1 = way[j0]; rowOf[j0] = rowOf[j1]; j0 = j1; } while (j0);
    }
    vector<int> colOf(n);
    for (int j = 1; j <= m; j++) if (rowOf[j]) colOf[rowOf[j] - 1] = j - 1;
    ll cost = 0;
    for (int i = 0; i < n; i++) cost += c[i][colOf[i]];
    return {cost, colOf};
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<vector<ll>> c(n, vector<ll>(m));
    for (auto &row : c) for (auto &x : row) { cin >> x; x = -x; }
    cout << -hungarian(c).first << "\n";
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

    static int[] hungarian(long[][] c, long[] costOut) {
        int n = c.length, m = c[0].length;
        final long INF = Long.MAX_VALUE / 4;
        long[] u = new long[n + 1], v = new long[m + 1], minv = new long[m + 1];
        int[] rowOf = new int[m + 1], way = new int[m + 1];
        boolean[] inTree = new boolean[m + 1];
        for (int i = 1; i <= n; i++) {
            rowOf[0] = i;
            int j0 = 0;
            Arrays.fill(minv, INF);
            Arrays.fill(inTree, false);
            do {
                inTree[j0] = true;
                int i0 = rowOf[j0], j1 = 0;
                long delta = INF;
                for (int j = 1; j <= m; j++) if (!inTree[j]) {
                    long cur = c[i0 - 1][j - 1] - u[i0] - v[j];
                    if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
                    if (minv[j] < delta) { delta = minv[j]; j1 = j; }
                }
                for (int j = 0; j <= m; j++) {
                    if (inTree[j]) { u[rowOf[j]] += delta; v[j] -= delta; }
                    else minv[j] -= delta;
                }
                j0 = j1;
            } while (rowOf[j0] != 0);
            do { int j1 = way[j0]; rowOf[j0] = rowOf[j1]; j0 = j1; } while (j0 != 0);
        }
        int[] colOf = new int[n];
        for (int j = 1; j <= m; j++) if (rowOf[j] != 0) colOf[rowOf[j] - 1] = j - 1;
        long cost = 0;
        for (int i = 0; i < n; i++) cost += c[i][colOf[i]];
        costOut[0] = cost;
        return colOf;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nextLong(), m = (int) nextLong();
        long[][] c = new long[n][m];
        for (int i = 0; i < n; i++) for (int j = 0; j < m; j++) c[i][j] = -nextLong();
        long[] cost = new long[1];
        hungarian(c, cost);
        System.out.println(-cost[0]);
    }
}
```

</details>

Hand checks: $\begin{pmatrix}7&3&9\\8&2&6\end{pmatrix}$ → worker 1 takes job 3 and worker 2 job 1: 17 (greedy "worker 1 takes its best" happens to work here, but the third test shows it can fail:
two workers both want job 1, and the best total 31 gives job 1 to one of them and job 3 to the worker who values it at 20).

<!-- test
in:
2 3
7 3 9
8 2 6
out:
17
-->
<!-- test
in:
1 4
1 2 3 4
out:
4
-->
<!-- test
in:
3 3
10 1 1
10 1 1
10 1 20
out:
31
-->

### Example 3 — Assignment with forbidden pairs  ·  ★ ≈2100

- **Source:** Original problem.
- **Difficulty:** ≈2100 (est.)
- **Problem:** an $n\times n$ matrix ($n\le 300$) of costs in $[0,10^6]$, where $-1$ marks a forbidden pair. Find a minimum-cost perfect assignment using only allowed pairs, or print $-1$.
- **Thinking from first principles:** the algorithm needs a complete matrix. Replace forbidden cells by a cost $\text{BIG}$ so large that a single forbidden cell outweighs any assignment of allowed
  cells: $\text{BIG} > n\cdot 10^6$. Then if any assignment avoids forbidden cells, the optimum does too; if the optimum's cost is $\ge \text{BIG}$, no valid assignment exists. Keep BIG small enough that
  $n\cdot\text{BIG}$ and the potentials fit in 64 bits ($10^{12}$ is comfortable).

<details><summary>Solution</summary>

Hungarian with $\text{BIG}=10^{12}$; if the result is $\ge \text{BIG}$ print $-1$. Same $O(n^3)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

pair<ll, vector<int>> hungarian(const vector<vector<ll>> &c) {
    int n = c.size(), m = c[0].size();
    const ll INF = LLONG_MAX / 4;
    vector<ll> u(n + 1, 0), v(m + 1, 0);
    vector<int> rowOf(m + 1, 0), way(m + 1, 0);
    for (int i = 1; i <= n; i++) {
        rowOf[0] = i;
        int j0 = 0;
        vector<ll> minv(m + 1, INF);
        vector<char> inTree(m + 1, 0);
        do {
            inTree[j0] = 1;
            int i0 = rowOf[j0], j1 = 0;
            ll delta = INF;
            for (int j = 1; j <= m; j++) if (!inTree[j]) {
                ll cur = c[i0 - 1][j - 1] - u[i0] - v[j];
                if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
                if (minv[j] < delta) { delta = minv[j]; j1 = j; }
            }
            for (int j = 0; j <= m; j++) {
                if (inTree[j]) { u[rowOf[j]] += delta; v[j] -= delta; }
                else minv[j] -= delta;
            }
            j0 = j1;
        } while (rowOf[j0] != 0);
        do { int j1 = way[j0]; rowOf[j0] = rowOf[j1]; j0 = j1; } while (j0);
    }
    vector<int> colOf(n);
    for (int j = 1; j <= m; j++) if (rowOf[j]) colOf[rowOf[j] - 1] = j - 1;
    ll cost = 0;
    for (int i = 0; i < n; i++) cost += c[i][colOf[i]];
    return {cost, colOf};
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const ll BIG = 1'000'000'000'000LL;
    int n;
    cin >> n;
    vector<vector<ll>> c(n, vector<ll>(n));
    for (auto &row : c) for (auto &x : row) { cin >> x; if (x < 0) x = BIG; }
    ll cost = hungarian(c).first;
    cout << (cost >= BIG ? -1 : cost) << "\n";
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

    static int[] hungarian(long[][] c, long[] costOut) {
        int n = c.length, m = c[0].length;
        final long INF = Long.MAX_VALUE / 4;
        long[] u = new long[n + 1], v = new long[m + 1], minv = new long[m + 1];
        int[] rowOf = new int[m + 1], way = new int[m + 1];
        boolean[] inTree = new boolean[m + 1];
        for (int i = 1; i <= n; i++) {
            rowOf[0] = i;
            int j0 = 0;
            Arrays.fill(minv, INF);
            Arrays.fill(inTree, false);
            do {
                inTree[j0] = true;
                int i0 = rowOf[j0], j1 = 0;
                long delta = INF;
                for (int j = 1; j <= m; j++) if (!inTree[j]) {
                    long cur = c[i0 - 1][j - 1] - u[i0] - v[j];
                    if (cur < minv[j]) { minv[j] = cur; way[j] = j0; }
                    if (minv[j] < delta) { delta = minv[j]; j1 = j; }
                }
                for (int j = 0; j <= m; j++) {
                    if (inTree[j]) { u[rowOf[j]] += delta; v[j] -= delta; }
                    else minv[j] -= delta;
                }
                j0 = j1;
            } while (rowOf[j0] != 0);
            do { int j1 = way[j0]; rowOf[j0] = rowOf[j1]; j0 = j1; } while (j0 != 0);
        }
        int[] colOf = new int[n];
        for (int j = 1; j <= m; j++) if (rowOf[j] != 0) colOf[rowOf[j] - 1] = j - 1;
        long cost = 0;
        for (int i = 0; i < n; i++) cost += c[i][colOf[i]];
        costOut[0] = cost;
        return colOf;
    }

    public static void main(String[] args) throws IOException {
        final long BIG = 1_000_000_000_000L;
        int n = (int) nextLong();
        long[][] c = new long[n][n];
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) { long x = nextLong(); c[i][j] = x < 0 ? BIG : x; }
        long[] cost = new long[1];
        hungarian(c, cost);
        System.out.println(cost[0] >= BIG ? -1 : cost[0]);
    }
}
```

</details>

<!-- test
in:
2
3 -1
-1 4
out:
7
-->
<!-- test
in:
2
-1 1
-1 2
out:
-1
-->
<!-- test
in:
3
1 -1 5
2 3 -1
-1 4 1
out:
5
-->

## 6. Tricks, pitfalls and things to remember

1. **$n\le m$ is required.** Transpose if there are more rows than columns; otherwise the loop never finds a free column and spins.
2. **Maximize by negation**, not by $\max - c$ unless you remember the constant: both work because every assignment uses exactly $n$ cells.
3. **BIG for forbidden pairs** must exceed $n\cdot\max c$ but keep $n\cdot\text{BIG}$ (and potentials, which can reach about $n\cdot\text{BIG}$) inside 64 bits.
4. **Use 64-bit potentials** even if costs fit in 32 bits: potentials accumulate many $\delta$s.
5. **Compute the cost from the assignment** ($\sum c_{i,\sigma(i)}$) — it is self-evidently correct and avoids sign confusion with `-v[0]`.
6. **Do not reinitialize `u`, `v` between rows**; only `minv` and the tree marks are per row.
7. **Floating costs**: works with `double`, but compare with a tolerance and expect tiny negative reduced costs.
8. **Java**: allocate `minv`/`inTree` once and refill per row; a `long[][]` of $500\times500$ is fine. Avoid boxing in the inner $O(n^3)$ loop.
9. **When $n\le 20$**, bitmask DP is less code and less risk. When there are capacities or the graph is sparse with $E\ll n^2$, [min-cost flow](04-min-cost-flow.md) can be faster.

## 7. Going further (toward 2400–2600+)

- **$k$-best / incremental assignment**: insertion of a new row costs $O(nm)$ with the same machinery — useful when rows arrive online.
- **Kuhn–Munkres on sparse graphs**: with SSP and a heap you get $O(nE\log n)$; with the "potentials from the previous phase" trick it is the [min-cost flow](04-min-cost-flow.md) code.
- **Weighted general matching** (🔴): Edmonds' weighted blossom, $O(n^3)$ — rarely needed; for $n\le 20$ use bitmask DP
  ([AtCoder ABC318 D · General Weighted Max Matching](https://atcoder.jp/contests/abc318/tasks/abc318_d)).
- **Duality as a modeling tool**: problems that ask for "labels $u_i,v_j$ with $u_i+v_j\ge w_{ij}$ minimizing $\sum u+\sum v$" are the dual of max-weight matching — answer = Hungarian's optimum.
- **Birkhoff–von Neumann** (🧊): decompositions of doubly stochastic matrices into permutations appear in scheduling constructions.

## 8. Practice ladder

- [ ] [CSES 2129 · Task Assignment](https://cses.fi/problemset/task/2129) — Example 1
- [ ] [CF 1437C · Chef Monocarp](https://codeforces.com/problemset/problem/1437/C) — 1800 — dishes × minutes cost matrix, rectangular
- [ ] [CF 1525D · Armchairs](https://codeforces.com/problemset/problem/1525/D) — 1800 — rectangular assignment on a line (DP intended)
- [ ] [AtCoder PRACTICE2 E · MinCostFlow](https://atcoder.jp/contests/practice2/tasks/practice2_e) — the capacitated generalization
- [ ] [CF 1107F · Vasya and Endless Credits](https://codeforces.com/problemset/problem/1107/F) — 2600 — offers × months profit matrix, maximize
- [ ] [AtCoder ABC247 G · Dream Team](https://atcoder.jp/contests/abc247/tasks/abc247_g) — all prefix answers of a weighted matching
- [ ] [CF 1354F · Summoning Minions](https://codeforces.com/problemset/problem/1354/F) — 2500 — order positions × minions (DP or assignment)
- [ ] [AtCoder ABC318 D · General Weighted Max Matching](https://atcoder.jp/contests/abc318/tasks/abc318_d) — non-bipartite, bitmask DP
- [ ] [CF 1955H · The Most Reckless Defense](https://codeforces.com/problemset/problem/1955/H) — 2300 — towers × radii profit matrix (each radius used once), rectangular maximize
- [ ] [CF 1510B · Button Lock](https://codeforces.com/problemset/problem/1510/B) — 2600 — chain cover with costs → min-cost matching

## 9. LeetCode / FAANG cross-reference

Interviews use small $n$ (≤ 10–15) where bitmask DP or backtracking is expected; Hungarian is a strong talking point but rarely required.

- [LC 1947 · Maximum Compatibility Score Sum](https://leetcode.com/problems/maximum-compatibility-score-sum/) — Medium — maximize assignment; $n\le 8$, bitmask DP or Hungarian.
- [LC 1066 · Campus Bikes II](https://leetcode.com/problems/campus-bikes-ii/) — Medium 🔒 — rectangular min-cost assignment ($n\le 10$ workers, $m\le 10$ bikes).
- [LC 1879 · Minimum XOR Sum of Two Arrays](https://leetcode.com/problems/minimum-xor-sum-of-two-arrays/) — Hard — square assignment with $c_{ij}=a_i\oplus b_j$.
- [LC 2172 · Maximum AND Sum of Array](https://leetcode.com/problems/maximum-and-sum-of-array/) — Hard — numbers × slots (each slot twice): duplicate columns, then maximize.
- [LC 2850 · Minimum Moves to Spread Stones Over Grid](https://leetcode.com/problems/minimum-moves-to-spread-stones-over-grid/) — Medium — surplus stones × empty cells, Manhattan cost.

## 10. Self-check

1. Write the dual of the assignment LP and explain why any feasible dual gives a lower bound.
2. Why is an assignment made of tight cells optimal?
3. What exactly changes in the $\delta$ step, and why do matched pairs stay tight?
4. Why does each row insertion take $O(m^2)$?
5. How is Hungarian related to successive shortest paths?
6. How do you handle $n>m$, maximization and forbidden pairs?
7. Why must BIG exceed $n\cdot\max c$, and what is the risk of choosing it too large?

<details><summary>Answers</summary>

1. $\max \sum u_i + \sum v_j$ s.t. $u_i+v_j\le c_{ij}$ ($v_j\le0$ if columns may stay unused). Summing $u_i+v_{\sigma(i)}\le c_{i\sigma(i)}$ over an assignment bounds its cost from below.
2. Its cost equals $\sum u + \sum v$ over the used rows/columns, which is a lower bound for every assignment.
3. Tree rows gain $\delta$, tree columns lose $\delta$; a matched pair inside the tree changes by $+\delta-\delta=0$; matched pairs outside the tree are untouched.
4. Each step adds a column to the tree (at most $m$ steps) and costs $O(m)$ thanks to the `minv` array.
5. `minv` is Dijkstra over columns with reduced costs and the $\delta$ updates are potential shifts; each row insertion is one shortest augmenting path.
6. Transpose; negate costs; replace forbidden cells by BIG and reject results $\ge$ BIG.
7. So that one forbidden cell costs more than any all-allowed assignment; too large and $n\cdot\text{BIG}$ or the potentials overflow 64 bits.

</details>
