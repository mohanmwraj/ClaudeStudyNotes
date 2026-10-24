# Tree DP and Rerooting

> **Band:** 🔵→🟠 1500–2400 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [DP first principles](01-dp-first-principles-and-state-design.md), [BFS/DFS](../09-Graphs/01-graph-representation-bfs-dfs.md), [tree basics](../10-Trees/01-tree-basics-diameter-center-euler-tour.md)
> **You can say you know this when:** you can write subtree DPs (independent set, matching, diameter) iteratively in both languages; you can prove the $O(n^2)$ bound of tree knapsack by "each pair is merged once at its LCA"; and you can reroot any DP to get the answer for every root in $O(n)$ — by subtraction when the combine is invertible and by prefix/suffix aggregates when it is not.

A rooted tree is the best-behaved recursive structure there is: the subtree of $v$ touches the rest of the tree only through $v$ itself (and the edge to its parent). So the natural state is "$v$, plus a few bits about $v$" — and children are independent given those bits, which turns transitions into sums and products over children.

---

## 1. First principles — why this works

### 1.1 Subtrees are the subproblems

Root the tree at vertex $0$. Any configuration (a chosen set of vertices, a colouring, a matching) restricted to the subtree of $v$ interacts with the outside only through **$v$'s own status** — whether $v$ is chosen, its colour, whether it is matched upward. Two partial configurations of the subtree with the same status of $v$ are interchangeable for the rest of the tree. That is the equivalence-class argument from [first principles](01-dp-first-principles-and-state-design.md) §1.2: the state is $(v, \text{status of } v)$.

Given $v$'s status, the children's subtrees are **independent** of each other — they share no vertices and only connect through $v$. So

- optimisation: $f(v, s) = \text{own}(v,s) + \sum_{c} \operatorname{opt}_{s' \text{ compatible with } s} f(c, s')$;
- counting: $g(v, s) = \prod_{c} \sum_{s' \text{ compatible}} g(c, s')$.

Each edge is examined a constant number of times: $O(n \cdot |\text{status}|^2)$ total.

**Maximum-weight independent set:** $f(v,1) = w_v + \sum_c f(c,0)$, $f(v,0) = \sum_c \max(f(c,0), f(c,1))$.

**Counting independent sets** (AtCoder DP P): the same with $\sum \to \prod$ and $\max \to +$.

### 1.2 Evaluation order — post-order without recursion

Children must be finished before their parent. Recursion gives post-order for free, but a path-shaped tree with $n = 2\cdot10^5$ overflows the Java stack (and the default Windows C++ stack). The robust pattern, identical in both languages:

1. BFS (or an explicit-stack DFS) from the root, recording `order` and `parent`;
2. iterate `order` **backwards** for bottom-up DPs (every child appears after its parent in BFS order);
3. iterate `order` **forwards** for top-down passes (rerooting, depths).

No recursion, no stack limits, and the code is usually shorter.

### 1.3 Paths through the highest vertex — diameter

Every path in a rooted tree has a unique **highest** vertex (closest to the root). Classify paths by it: a longest path whose highest vertex is $v$ goes down into the two children with the deepest subtrees. With $\text{down}(v) = 1 + \max_c \text{down}(c)$ (0 for a leaf),
$$\text{diameter} = \max_v \big(\text{top}_1(v) + \text{top}_2(v)\big),$$
where $\text{top}_1, \text{top}_2$ are the two largest values of $1 + \text{down}(c)$ over children (0 if missing). The same "highest vertex" classification counts pairs at distance $k$ (CF 161D) and sums path lengths.

### 1.4 Tree knapsack — merging children and the $O(n^2)$ bound

"Choose $k$ vertices of a subtree subject to an ancestor rule" needs the state $(v, j)$: $f(v, j)$ = best value using exactly $j$ vertices of $v$'s subtree. Children are merged into $v$ one at a time, like a knapsack over groups:

$$f_{\text{new}}(v, i + j) = \operatorname{opt}\big(f(v, i) \otimes f(c, j)\big), \quad 0 \le i \le S,\ 0 \le j \le s_c,$$

where $S$ is the size of the part of $v$'s subtree merged so far and $s_c$ the size of child $c$'s subtree.

It looks like $O(n^3)$ ($n$ vertices × $n^2$ per merge), but it is $O(n^2)$:

> **Claim.** $\sum_{\text{merges}} S \cdot s_c \le \binom{n}{2}$.
> **Proof.** Interpret $S \cdot s_c$ as the number of vertex pairs $(x, y)$ with $x$ in the already-merged part and $y$ in the child's subtree. After this merge, $x$ and $y$ are in the same merged part forever, so no pair is counted twice — and every pair is counted exactly at the vertex where their subtrees first join, their LCA. ∎

The loop bounds **must** be the current sizes $S$ and $s_c$, not $n$ — otherwise the bound fails. If $j$ is capped at $k$ (only $j \le k$ matters), the same argument gives $O(nk)$.

### 1.5 Rerooting — the answer for every root

Many problems ask for $\text{ans}(r)$ for every possible root $r$ ("sum of distances from each vertex", "maximum cost over all roots"). Running the DP $n$ times is $O(n^2)$. Rerooting does it in $O(n)$ with two passes:

1. **Down pass** (post-order): $\text{down}(v)$ = DP of $v$'s subtree for root 0.
2. **Up pass** (pre-order): $\text{up}(v)$ = DP of the "outside" part — the component of $\text{parent}(v)$ after deleting the edge $(v, \text{parent}(v))$, rooted at the parent.

Then $\text{ans}(v)$ combines all neighbours of $v$: its children's $\text{down}$ values and its parent's $\text{up}$ value. To compute $\text{up}(c)$ for a child $c$ of $v$ we need "everything at $v$ except $c$": the parent's contribution and all siblings' contributions.

- **Invertible combine** (sums, XOR, products mod a prime with no zero factors): take the total at $v$ and remove $c$'s contribution — $O(1)$ per child.
- **Non-invertible combine** (max, min, products mod a composite, products that can be 0): precompute **prefix and suffix** aggregates of the neighbours' contributions in adjacency order; "all except the $j$-th" $= \text{pre}_{j} \oplus \text{suf}_{j+1}$. $O(\deg v)$ per vertex, $O(n)$ total.

A clean way to think about it: every directed edge $u \to v$ has a value "DP of $u$'s side, seen from $v$". The down pass computes it for edges pointing to parents, the up pass for edges pointing to children, and $\text{ans}(v)$ merges the values on all edges pointing into $v$.

### 1.6 Rerooting with invertible sums — a formula you should derive once

Sum of weighted distances to root $r$: $\text{cost}(r) = \sum_u a_u\, \text{dist}(u, r)$. Moving the root from $v$ to its child $c$ brings every vertex of $c$'s subtree one step closer and every other vertex one step farther:
$$\text{cost}(c) = \text{cost}(v) - A_c + (A - A_c) = \text{cost}(v) + A - 2A_c,$$
with $A_c$ = total weight in $c$'s subtree and $A$ the total weight. One down pass for $A_c$ and $\text{cost}(0)$, one top-down pass for every $\text{cost}$ (Example 3; [LC 834](https://leetcode.com/problems/sum-of-distances-in-tree/) is the unweighted case).

---

## 2. Formulas, definitions and identities

| DP | Recurrence | Time |
|---|---|---|
| max-weight independent set | $f(v,1) = w_v+\sum f(c,0)$; $f(v,0) = \sum\max(f(c,0),f(c,1))$ | $O(n)$ |
| count independent sets | $g(v,1)=\prod g(c,0)$; $g(v,0)=\prod (g(c,0)+g(c,1))$ | $O(n)$ |
| maximum matching | $f(v,0)=\sum M_c$; $f(v,1)=\max_c f(v,0)-M_c+f(c,0)+1$, $M_c = \max(f(c,0),f(c,1))$ | $O(n)$ |
| minimum vertex cover | $\text{cov}(v,1) = 1+\sum\min(\cdot)$; $\text{cov}(v,0) = \sum \text{cov}(c,1)$ | $O(n)$ |
| height / diameter | $\text{down}(v) = 1+\max\text{down}(c)$; $\text{diam} = \max_v(\text{top}_1+\text{top}_2)$ | $O(n)$ |
| connected sets containing $v$ (in subtree) | $h(v) = \prod_c (h(c)+1)$ | $O(n)$ |
| tree knapsack | merge $f(v,\cdot)$ with $f(c,\cdot)$ over sizes | $O(n^2)$, $O(nk)$ capped |
| reroot sum of distances | $\text{cost}(c) = \text{cost}(v) + A - 2A_c$ | $O(n)$ |

**Size of a subtree:** $\text{sz}(v) = 1 + \sum_c \text{sz}(c)$. **Edges crossing** $(v, \text{par})$ split the tree into $\text{sz}(v)$ and $n - \text{sz}(v)$ vertices — the number of paths through that edge is $\text{sz}(v)(n-\text{sz}(v))$, and $\sum_{\text{edges}} \text{sz}(v)(n-\text{sz}(v)) = \sum_{u<w}\text{dist}(u,w)$.

**Knapsack merge bound:** $\sum_{\text{merges}} S\cdot s_c \le \binom n2$; capped at $k$: $\sum \min(S,k)\min(s_c,k) = O(nk)$.

**Rerooting cost:** $\sum_v \deg(v) = 2(n-1)$, so prefix/suffix arrays over all vertices total $O(n)$.

---

## 3. Implementation (C++ and Java)

### 3.1 Iterative traversal and the diameter

Input: $n$, then $n-1$ edges. Output: the diameter in edges ([CSES 1131 · Tree Diameter](https://cses.fi/problemset/task/1131)).

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<vector<int>> adj(n);
    for (int i = 0; i < n - 1; i++) {
        int a, b;
        cin >> a >> b;
        a--, b--;
        adj[a].push_back(b);
        adj[b].push_back(a);
    }
    vector<int> order, par(n, -1);                    // BFS order: parents before children
    order.reserve(n);
    order.push_back(0);
    for (int i = 0; i < (int)order.size(); i++) {
        int v = order[i];
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; order.push_back(u); }
    }
    vector<int> down(n, 0);
    int diam = 0;
    for (int i = n - 1; i >= 0; i--) {                // reverse BFS order = children first
        int v = order[i], best1 = 0, best2 = 0;
        for (int u : adj[v]) {
            if (u == par[v]) continue;
            int len = down[u] + 1;
            if (len > best1) { best2 = best1; best1 = len; }
            else if (len > best2) best2 = len;
        }
        down[v] = best1;
        diam = max(diam, best1 + best2);              // longest path whose highest vertex is v
    }
    cout << diam << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static int ni() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        int r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        int n = ni();
        int[] ea = new int[n - 1], eb = new int[n - 1], deg = new int[n];
        for (int i = 0; i < n - 1; i++) { ea[i] = ni() - 1; eb[i] = ni() - 1; deg[ea[i]]++; deg[eb[i]]++; }
        int[] start = new int[n + 1];                 // CSR adjacency
        for (int v = 0; v < n; v++) start[v + 1] = start[v] + deg[v];
        int[] adj = new int[2 * (n - 1)], pos = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[pos[ea[i]]++] = eb[i]; adj[pos[eb[i]]++] = ea[i]; }
        int[] order = new int[n], par = new int[n];
        Arrays.fill(par, -1);
        int head = 0, tail = 0;
        order[tail++] = 0;
        while (head < tail) {
            int v = order[head++];
            for (int k = start[v]; k < start[v + 1]; k++) {
                int u = adj[k];
                if (u != par[v]) { par[u] = v; order[tail++] = u; }
            }
        }
        int[] down = new int[n];
        int diam = 0;
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i], best1 = 0, best2 = 0;
            for (int k = start[v]; k < start[v + 1]; k++) {
                int u = adj[k];
                if (u == par[v]) continue;
                int len = down[u] + 1;
                if (len > best1) { best2 = best1; best1 = len; } else if (len > best2) best2 = len;
            }
            down[v] = best1;
            diam = Math.max(diam, best1 + best2);
        }
        System.out.println(diam);
    }
}
```

<!-- test
in:
5
1 2
1 3
3 4
3 5
out:
3
-->
<!-- test
in:
1
out:
0
-->

### 3.2 A generic rerooting template (non-invertible combine)

`lift(x, v, u)` turns the DP value `x` of neighbour `u`'s side into a contribution to `v`; `merge` is associative with identity `id`; `fin(acc, v)` turns the merged contributions into the DP value of `v`. Returns $\text{ans}(v)$ for every root $v$.

```cpp
template <class T, class Merge, class Lift, class Fin>
vector<T> reroot(const vector<vector<int>>& adj, T id, Merge merge, Lift lift, Fin fin) {
    int n = adj.size();
    vector<int> order, par(n, -1);
    order.reserve(n);
    order.push_back(0);
    for (int i = 0; i < (int)order.size(); i++) {
        int v = order[i];
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; order.push_back(u); }
    }
    vector<T> down(n, id), up(n, id), ans(n, id);      // up[v]: DP of parent's side, rooted at the parent
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i];
        T acc = id;
        for (int u : adj[v]) if (u != par[v]) acc = merge(acc, lift(down[u], v, u));
        down[v] = fin(acc, v);
    }
    for (int v : order) {
        int k = adj[v].size();
        vector<T> c(k), pre(k + 1, id), suf(k + 1, id);
        for (int j = 0; j < k; j++) {
            int u = adj[v][j];
            c[j] = u == par[v] ? lift(up[v], v, u) : lift(down[u], v, u);
        }
        for (int j = 0; j < k; j++) pre[j + 1] = merge(pre[j], c[j]);
        for (int j = k - 1; j >= 0; j--) suf[j] = merge(c[j], suf[j + 1]);
        ans[v] = fin(pre[k], v);
        for (int j = 0; j < k; j++) {
            int u = adj[v][j];
            if (u != par[v]) up[u] = fin(merge(pre[j], suf[j + 1]), v);   // v's side without u
        }
    }
    return ans;
}
```

```java
interface Lift { long apply(long x, int v, int u); }
interface Fin { long apply(long acc, int v); }

static long[] reroot(int[][] adj, long id, java.util.function.LongBinaryOperator merge, Lift lift, Fin fin) {
    int n = adj.length;
    int[] order = new int[n], par = new int[n];
    Arrays.fill(par, -1);
    int tail = 1;
    for (int i = 0; i < tail; i++) {
        int v = order[i];
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; order[tail++] = u; }
    }
    long[] down = new long[n], up = new long[n], ans = new long[n];
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i];
        long acc = id;
        for (int u : adj[v]) if (u != par[v]) acc = merge.applyAsLong(acc, lift.apply(down[u], v, u));
        down[v] = fin.apply(acc, v);
    }
    for (int idx = 0; idx < n; idx++) {
        int v = order[idx], k = adj[v].length;
        long[] c = new long[k], pre = new long[k + 1], suf = new long[k + 1];
        pre[0] = id;
        suf[k] = id;
        for (int j = 0; j < k; j++) {
            int u = adj[v][j];
            c[j] = u == par[v] ? lift.apply(up[v], v, u) : lift.apply(down[u], v, u);
        }
        for (int j = 0; j < k; j++) pre[j + 1] = merge.applyAsLong(pre[j], c[j]);
        for (int j = k - 1; j >= 0; j--) suf[j] = merge.applyAsLong(c[j], suf[j + 1]);
        ans[v] = fin.apply(pre[k], v);
        for (int j = 0; j < k; j++) {
            int u = adj[v][j];
            if (u != par[v]) up[u] = fin.apply(merge.applyAsLong(pre[j], suf[j + 1]), v);
        }
    }
    return ans;
}
```

Instances: eccentricity of every vertex — `merge = max`, `lift = x + 1`, `fin = acc`, `id = 0`; connected sets containing each vertex (AtCoder DP V) — `merge = product mod M`, `lift = x + 1`, `fin = acc`, `id = 1`.

---

## 4. Recognising the pattern

| Signal | Technique |
|---|---|
| tree + "choose vertices/edges" with a local rule (no two adjacent, cover all edges, matching) | $(v, \text{status})$ DP |
| "for every vertex as the root …", "for each vertex compute …" with a whole-tree quantity | rerooting |
| combine is a sum / count with an inverse | reroot by subtraction (§1.6) |
| combine is max/min, or product mod composite | reroot with prefix/suffix (§3.2) |
| "choose exactly $k$ vertices", budgets, "a vertex needs its parent" | tree knapsack with size-bounded merges |
| paths in a tree, longest / counting by length | classify by the highest vertex |
| sums over all pairs of vertices | contribution of each edge: $\text{sz}(n-\text{sz})$ |
| $n$ up to $2\cdot10^5$, Java | iterative BFS order, CSR adjacency |
| queries on paths, many | not DP — [LCA](../10-Trees/02-lca-and-binary-lifting.md), [HLD](../10-Trees/04-heavy-light-decomposition.md) |
| "number of paths of length exactly $k$" with large $n$ and $k$ | small-to-large or centroid ([centroid](../10-Trees/05-centroid-decomposition.md)) |

---

## 5. Worked examples (graded)

### Example 1 — Independent Set (counting)  ·  ★ ≈1500 (est.)

- **Source:** [AtCoder DP P · Independent Set](https://atcoder.jp/contests/dp/tasks/dp_p)
- **Difficulty:** ≈1500 (est.)
- **Problem:** A tree with $n \le 10^5$ vertices. Count the ways to paint each vertex white or black so that no two adjacent vertices are both black, mod $10^9+7$.
- **Thinking from first principles:** A colouring of $v$'s subtree affects the outside only through $v$'s colour. Given $v$'s colour, children are independent — multiply. A black $v$ forces white children; a white $v$ allows either.

<details><summary>Solution</summary>

$g(v,W) = \prod_c (g(c,W)+g(c,B))$, $g(v,B) = \prod_c g(c,W)$; answer $g(0,W)+g(0,B)$. Iterative, $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const long long MOD = 1'000'000'007;
    int n;
    cin >> n;
    vector<vector<int>> adj(n);
    for (int i = 0; i < n - 1; i++) {
        int a, b;
        cin >> a >> b;
        a--, b--;
        adj[a].push_back(b);
        adj[b].push_back(a);
    }
    vector<int> order{0}, par(n, -1);
    for (int i = 0; i < (int)order.size(); i++)
        for (int u : adj[order[i]]) if (u != par[order[i]]) { par[u] = order[i]; order.push_back(u); }
    vector<long long> white(n, 1), black(n, 1);
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i];
        for (int u : adj[v]) {
            if (u == par[v]) continue;
            white[v] = white[v] * ((white[u] + black[u]) % MOD) % MOD;
            black[v] = black[v] * white[u] % MOD;     // a black vertex needs white children
        }
    }
    cout << (white[0] + black[0]) % MOD << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static int ni() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        int r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        int n = ni();
        int[] ea = new int[n - 1], eb = new int[n - 1], deg = new int[n];
        for (int i = 0; i < n - 1; i++) { ea[i] = ni() - 1; eb[i] = ni() - 1; deg[ea[i]]++; deg[eb[i]]++; }
        int[] start = new int[n + 1];
        for (int v = 0; v < n; v++) start[v + 1] = start[v] + deg[v];
        int[] adj = new int[2 * (n - 1)], pos = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[pos[ea[i]]++] = eb[i]; adj[pos[eb[i]]++] = ea[i]; }
        int[] order = new int[n], par = new int[n];
        Arrays.fill(par, -1);
        int tail = 1;
        for (int i = 0; i < tail; i++) {
            int v = order[i];
            for (int k = start[v]; k < start[v + 1]; k++) if (adj[k] != par[v]) { par[adj[k]] = v; order[tail++] = adj[k]; }
        }
        long[] white = new long[n], black = new long[n];
        Arrays.fill(white, 1);
        Arrays.fill(black, 1);
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i];
            for (int k = start[v]; k < start[v + 1]; k++) {
                int u = adj[k];
                if (u == par[v]) continue;
                white[v] = white[v] * ((white[u] + black[u]) % MOD) % MOD;
                black[v] = black[v] * white[u] % MOD;
            }
        }
        System.out.println((white[0] + black[0]) % MOD);
    }
}
```

</details>

<!-- test
in:
4
1 2
1 3
1 4
out:
9
-->
<!-- test
in:
1
out:
2
-->
<!-- test
in:
5
1 2
2 3
3 4
4 5
out:
13
-->

### Example 2 — Tree Matching  ·  ★ ≈1600 (est.)

- **Source:** [CSES 1130 · Tree Matching](https://cses.fi/problemset/task/1130)
- **Difficulty:** ≈1600 (est.)
- **Problem:** A tree with $n \le 2\cdot10^5$ vertices. Maximum number of pairwise disjoint edges.
- **Thinking from first principles:** Status of $v$: is it already matched to one of its children (then the edge to the parent is unavailable)? $f(v,0)$ = best in the subtree with $v$ free, $f(v,1)$ = best with $v$ matched downward. If $v$ matches child $c$, we gain 1 and $c$ must be free — so we replace $c$'s best $M_c$ by $f(c,0)$. (A greedy — match each leaf with its parent, bottom-up — is also optimal by an exchange argument; the DP generalises to weighted edges, the greedy does not.)

<details><summary>Solution</summary>

$f(v,0) = \sum_c M_c$, $f(v,1) = \max_c \big(f(v,0) - M_c + f(c,0) + 1\big)$, $M_c = \max(f(c,0), f(c,1))$. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<vector<int>> adj(n);
    for (int i = 0; i < n - 1; i++) {
        int a, b;
        cin >> a >> b;
        a--, b--;
        adj[a].push_back(b);
        adj[b].push_back(a);
    }
    vector<int> order{0}, par(n, -1);
    for (int i = 0; i < (int)order.size(); i++)
        for (int u : adj[order[i]]) if (u != par[order[i]]) { par[u] = order[i]; order.push_back(u); }
    vector<int> f0(n, 0), f1(n, INT_MIN / 2);
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i];
        int bestGain = INT_MIN / 2;
        for (int u : adj[v]) {
            if (u == par[v]) continue;
            int M = max(f0[u], f1[u]);
            f0[v] += M;
            bestGain = max(bestGain, f0[u] + 1 - M);  // switch u from "best" to "free + matched with v"
        }
        f1[v] = f0[v] + bestGain;
    }
    cout << max(f0[0], f1[0]) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static int ni() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        int r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        int n = ni();
        int[] ea = new int[n - 1], eb = new int[n - 1], deg = new int[n];
        for (int i = 0; i < n - 1; i++) { ea[i] = ni() - 1; eb[i] = ni() - 1; deg[ea[i]]++; deg[eb[i]]++; }
        int[] start = new int[n + 1];
        for (int v = 0; v < n; v++) start[v + 1] = start[v] + deg[v];
        int[] adj = new int[2 * (n - 1)], pos = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[pos[ea[i]]++] = eb[i]; adj[pos[eb[i]]++] = ea[i]; }
        int[] order = new int[n], par = new int[n];
        Arrays.fill(par, -1);
        int tail = 1;
        for (int i = 0; i < tail; i++) {
            int v = order[i];
            for (int k = start[v]; k < start[v + 1]; k++) if (adj[k] != par[v]) { par[adj[k]] = v; order[tail++] = adj[k]; }
        }
        int[] f0 = new int[n], f1 = new int[n];
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i], bestGain = Integer.MIN_VALUE / 2;
            for (int k = start[v]; k < start[v + 1]; k++) {
                int u = adj[k];
                if (u == par[v]) continue;
                int M = Math.max(f0[u], f1[u]);
                f0[v] += M;
                bestGain = Math.max(bestGain, f0[u] + 1 - M);
            }
            f1[v] = f0[v] + bestGain;
        }
        System.out.println(Math.max(f0[0], f1[0]));
    }
}
```

</details>

<!-- test
in:
5
1 2
1 3
3 4
3 5
out:
2
-->
<!-- test
in:
1
out:
0
-->
<!-- test
in:
4
1 2
2 3
3 4
out:
2
-->

### Example 3 — Tree with Maximum Cost (rerooting by subtraction)  ·  ★ 1900

- **Source:** [CF 1092F · Tree with Maximum Cost](https://codeforces.com/problemset/problem/1092/F) — 1900
- **Difficulty:** 1900
- **Problem:** A tree with $n \le 2\cdot10^5$ vertices and weights $a_v \le 2\cdot10^5$. For a root $r$, $\text{cost}(r) = \sum_u a_u\,\text{dist}(u, r)$. Find $\max_r \text{cost}(r)$.
- **Thinking from first principles:** $n$ BFS runs are $O(n^2)$. When the root moves across one edge $v \to c$, distances change by exactly $\pm1$: $-1$ for $c$'s subtree, $+1$ for the rest. So $\text{cost}(c) = \text{cost}(v) + A - 2A_c$ (§1.6) — a sum, invertible, so no prefix/suffix needed. Values reach $2\cdot10^5 \cdot 2\cdot10^5 \cdot 2\cdot10^5 = 8\cdot10^{15}$: 64-bit.

<details><summary>Solution</summary>

Down pass: subtree weights $A_v$ and $\text{cost}(0) = \sum_v a_v\,\text{depth}(v)$. Top-down pass with the formula. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    vector<vector<int>> adj(n);
    for (int i = 0; i < n - 1; i++) {
        int u, v;
        cin >> u >> v;
        u--, v--;
        adj[u].push_back(v);
        adj[v].push_back(u);
    }
    vector<int> order{0}, par(n, -1), depth(n, 0);
    for (int i = 0; i < (int)order.size(); i++) {
        int v = order[i];
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; depth[u] = depth[v] + 1; order.push_back(u); }
    }
    vector<long long> sub(a), cost(n, 0);
    long long A = 0;
    for (int v = 0; v < n; v++) { A += a[v]; cost[0] += a[v] * depth[v]; }
    for (int i = n - 1; i > 0; i--) sub[par[order[i]]] += sub[order[i]];
    long long best = cost[0];
    for (int i = 1; i < n; i++) {                     // parents are processed before children
        int c = order[i];
        cost[c] = cost[par[c]] + A - 2 * sub[c];
        best = max(best, cost[c]);
    }
    cout << best << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static int ni() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        int r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        int n = ni();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = ni();
        int[] ea = new int[n - 1], eb = new int[n - 1], deg = new int[n];
        for (int i = 0; i < n - 1; i++) { ea[i] = ni() - 1; eb[i] = ni() - 1; deg[ea[i]]++; deg[eb[i]]++; }
        int[] start = new int[n + 1];
        for (int v = 0; v < n; v++) start[v + 1] = start[v] + deg[v];
        int[] adj = new int[2 * (n - 1)], pos = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[pos[ea[i]]++] = eb[i]; adj[pos[eb[i]]++] = ea[i]; }
        int[] order = new int[n], par = new int[n], depth = new int[n];
        Arrays.fill(par, -1);
        int tail = 1;
        for (int i = 0; i < tail; i++) {
            int v = order[i];
            for (int k = start[v]; k < start[v + 1]; k++) {
                int u = adj[k];
                if (u != par[v]) { par[u] = v; depth[u] = depth[v] + 1; order[tail++] = u; }
            }
        }
        long[] sub = a.clone(), cost = new long[n];
        long A = 0;
        for (int v = 0; v < n; v++) { A += a[v]; cost[0] += a[v] * depth[v]; }
        for (int i = n - 1; i > 0; i--) sub[par[order[i]]] += sub[order[i]];
        long best = cost[0];
        for (int i = 1; i < n; i++) {
            int c = order[i];
            cost[c] = cost[par[c]] + A - 2 * sub[c];
            best = Math.max(best, cost[c]);
        }
        System.out.println(best);
    }
}
```

</details>

<!-- test
in:
5
1 2 3 4 5
1 2
2 3
3 4
4 5
out:
40
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
4
10 1 1 1
1 2
1 3
1 4
out:
14
-->

### Example 4 — Subtree (rerooting with prefix/suffix products)  ·  ★ ≈2200 (est.)

- **Source:** [AtCoder DP V · Subtree](https://atcoder.jp/contests/dp/tasks/dp_v)
- **Difficulty:** ≈2200 (est.)
- **Problem:** A tree with $n \le 10^5$ vertices and an integer $M \le 10^9$ (**not necessarily prime**). For every vertex $v$, count the ways to paint vertices black/white so that the black vertices form a connected set containing $v$, mod $M$.
- **Thinking from first principles:** Rooted at $v$, a connected set containing $v$ chooses, independently for each neighbour $u$, either nothing on $u$'s side or a connected set containing $u$ on $u$'s side: $\text{ans}(v) = \prod_{u \sim v} (h(u \to v) + 1)$ where $h(u\to v)$ counts connected sets containing $u$ in $u$'s side. That's rerooting — and the combine is a product mod a composite $M$, so we **cannot divide** to exclude one child: use prefix and suffix products over each vertex's neighbours.

<details><summary>Solution</summary>

Down: $h(v) = \prod_{c}(h(c)+1)$. Up: for the children $c_1..c_k$ of $v$ with parent contribution $P = \text{up}(v)+1$ (1 at the root), $\text{up}(c_j) = P\cdot\prod_{i\ne j}(h(c_i)+1)$ via prefix/suffix. $\text{ans}(v) = P \cdot h(v)$. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    long long M;
    cin >> n >> M;
    vector<vector<int>> adj(n);
    for (int i = 0; i < n - 1; i++) {
        int a, b;
        cin >> a >> b;
        a--, b--;
        adj[a].push_back(b);
        adj[b].push_back(a);
    }
    vector<int> order{0}, par(n, -1);
    for (int i = 0; i < (int)order.size(); i++)
        for (int u : adj[order[i]]) if (u != par[order[i]]) { par[u] = order[i]; order.push_back(u); }
    vector<long long> h(n, 1), up(n, 0), ans(n);
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i];
        for (int u : adj[v]) if (u != par[v]) h[v] = h[v] * (h[u] + 1) % M;
    }
    for (int v : order) {
        long long P = par[v] == -1 ? 1 : (up[v] + 1) % M;     // contribution of the parent's side
        ans[v] = P * h[v] % M;
        vector<int> ch;
        for (int u : adj[v]) if (u != par[v]) ch.push_back(u);
        int k = ch.size();
        vector<long long> pre(k + 1, 1), suf(k + 1, 1);
        for (int j = 0; j < k; j++) pre[j + 1] = pre[j] * (h[ch[j]] + 1) % M;
        for (int j = k - 1; j >= 0; j--) suf[j] = suf[j + 1] * (h[ch[j]] + 1) % M;
        for (int j = 0; j < k; j++) up[ch[j]] = P * pre[j] % M * suf[j + 1] % M;   // v's side without ch[j]
    }
    for (int v = 0; v < n; v++) cout << ans[v] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long M = nl();
        int[] ea = new int[n - 1], eb = new int[n - 1], deg = new int[n];
        for (int i = 0; i < n - 1; i++) { ea[i] = (int) nl() - 1; eb[i] = (int) nl() - 1; deg[ea[i]]++; deg[eb[i]]++; }
        int[] start = new int[n + 1];
        for (int v = 0; v < n; v++) start[v + 1] = start[v] + deg[v];
        int[] adj = new int[2 * (n - 1)], pos = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[pos[ea[i]]++] = eb[i]; adj[pos[eb[i]]++] = ea[i]; }
        int[] order = new int[n], par = new int[n];
        Arrays.fill(par, -1);
        int tail = 1;
        for (int i = 0; i < tail; i++) {
            int v = order[i];
            for (int k = start[v]; k < start[v + 1]; k++) if (adj[k] != par[v]) { par[adj[k]] = v; order[tail++] = adj[k]; }
        }
        long[] h = new long[n], up = new long[n], ans = new long[n];
        Arrays.fill(h, 1 % M);
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i];
            for (int k = start[v]; k < start[v + 1]; k++) if (adj[k] != par[v]) h[v] = h[v] * (h[adj[k]] + 1) % M;
        }
        long[] pre = new long[n + 1], suf = new long[n + 1];
        int[] ch = new int[n];
        for (int idx = 0; idx < n; idx++) {
            int v = order[idx];
            long P = par[v] == -1 ? 1 % M : (up[v] + 1) % M;
            ans[v] = P * h[v] % M;
            int k = 0;
            for (int e = start[v]; e < start[v + 1]; e++) if (adj[e] != par[v]) ch[k++] = adj[e];
            pre[0] = 1 % M;
            for (int j = 0; j < k; j++) pre[j + 1] = pre[j] * (h[ch[j]] + 1) % M;
            suf[k] = 1 % M;
            for (int j = k - 1; j >= 0; j--) suf[j] = suf[j + 1] * (h[ch[j]] + 1) % M;
            for (int j = 0; j < k; j++) up[ch[j]] = P * pre[j] % M * suf[j + 1] % M;
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 0; v < n; v++) sb.append(ans[v]).append('\n');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
4 1000000000
1 2
2 3
3 4
out:
4
6
6
4
-->
<!-- test
in:
1 7
out:
1
-->
<!-- test
in:
5 6
1 2
2 3
3 4
3 5
out:
0
4
0
1
1
-->

### Example 5 — Karen and Supermarket (tree knapsack)  ·  ★ 2400

- **Source:** [CF 815C · Karen and Supermarket](https://codeforces.com/problemset/problem/815/C) — 2400
- **Difficulty:** 2400
- **Problem:** $n \le 5000$ goods, budget $b \le 10^9$. Good $i$ costs $c_i$; its coupon lowers the price by $d_i < c_i$. For $i \ge 2$, coupon $i$ may be used only if coupon $x_i$ ($x_i < i$) is used; a coupon is used only together with buying its good. Maximise the number of goods bought.
- **Thinking from first principles:** Coupon dependencies form a tree rooted at 1. In $v$'s subtree, if $v$'s coupon is **not** used, no coupon below it can be used — all purchases there are at full price. If it is used, each child subtree independently is in either state. So $f_0(v, k)$ = min cost to buy $k$ goods in the subtree at full price, $f_1(v, k)$ = min cost to buy $k$ goods with $v$ bought using its coupon. "Number of goods" is a knapsack dimension, merged child by child; the size-bounded loops make it $O(n^2) = 2.5\cdot10^7$ (§1.4). Since $x_i < i$, processing $i = n..2$ and merging $i$ into $x_i$ is already a valid bottom-up order — no DFS needed.

<details><summary>Solution</summary>

Initialise $f_0(v) = [0, c_v]$, $f_1(v) = [\infty, c_v - d_v]$. Merge child $u$ into $v$: $f_0'(i+j) = \min f_0(v,i)+f_0(u,j)$; $f_1'(i+j) = \min f_1(v,i) + \min(f_0(u,j), f_1(u,j))$. Answer: the largest $k$ with $\min(f_0(1,k), f_1(1,k)) \le b$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    long long b;
    cin >> n >> b;
    vector<long long> c(n), d(n);
    vector<int> par(n, -1);
    for (int i = 0; i < n; i++) {
        cin >> c[i] >> d[i];
        if (i > 0) { cin >> par[i]; par[i]--; }
    }
    const long long INF = LLONG_MAX / 4;
    vector<vector<long long>> f0(n), f1(n);
    for (int v = 0; v < n; v++) { f0[v] = {0, c[v]}; f1[v] = {INF, c[v] - d[v]}; }
    for (int u = n - 1; u > 0; u--) {                  // par[u] < u: children are finished first
        int v = par[u];
        int S = f0[v].size() - 1, s = f0[u].size() - 1;
        vector<long long> g0(S + s + 1, INF), g1(S + s + 1, INF);
        for (int i = 0; i <= S; i++)
            for (int j = 0; j <= s; j++) {             // bounded by current sizes: O(n^2) total
                g0[i + j] = min(g0[i + j], f0[v][i] + f0[u][j]);
                if (f1[v][i] < INF) g1[i + j] = min(g1[i + j], f1[v][i] + min(f0[u][j], f1[u][j]));
            }
        f0[v] = move(g0);
        f1[v] = move(g1);
        vector<long long>().swap(f0[u]);               // free the child's tables
        vector<long long>().swap(f1[u]);
    }
    int ans = 0;
    for (int k = 0; k < (int)f0[0].size(); k++)
        if (min(f0[0][k], f1[0][k]) <= b) ans = k;
    cout << ans << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c < '0' || c > '9') c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long b = nl();
        long[] c = new long[n], d = new long[n];
        int[] par = new int[n];
        par[0] = -1;
        for (int i = 0; i < n; i++) {
            c[i] = nl();
            d[i] = nl();
            if (i > 0) par[i] = (int) nl() - 1;
        }
        final long INF = Long.MAX_VALUE / 4;
        long[][] f0 = new long[n][], f1 = new long[n][];
        for (int v = 0; v < n; v++) { f0[v] = new long[]{0, c[v]}; f1[v] = new long[]{INF, c[v] - d[v]}; }
        for (int u = n - 1; u > 0; u--) {
            int v = par[u];
            int S = f0[v].length - 1, s = f0[u].length - 1;
            long[] g0 = new long[S + s + 1], g1 = new long[S + s + 1];
            Arrays.fill(g0, INF);
            Arrays.fill(g1, INF);
            for (int i = 0; i <= S; i++) {
                long a0 = f0[v][i], a1 = f1[v][i];
                for (int j = 0; j <= s; j++) {
                    long x = a0 + f0[u][j];
                    if (x < g0[i + j]) g0[i + j] = x;
                    if (a1 < INF) {
                        long y = a1 + Math.min(f0[u][j], f1[u][j]);
                        if (y < g1[i + j]) g1[i + j] = y;
                    }
                }
            }
            f0[v] = g0;
            f1[v] = g1;
            f0[u] = null;
            f1[u] = null;
        }
        int ans = 0;
        for (int k = 0; k < f0[0].length; k++) if (Math.min(f0[0][k], f1[0][k]) <= b) ans = k;
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
5 20
10 5
8 3 1
6 2 2
4 1 1
9 8 4
out:
5
-->
<!-- test
in:
1 3
5 1
out:
0
-->
<!-- test
in:
3 100
10 1
10 1 1
10 1 2
out:
3
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Recursion depth:** a path of $2\cdot10^5$ vertices kills recursive DFS in Java and on Windows; use the BFS order (§1.2). If you must recurse in Java, run inside `new Thread(null, r, "", 1 << 28)`.
2. **Root choice:** with BFS order from vertex 0, `par[0] = -1`; test `u != par[v]` (not `u != v`) when scanning neighbours.
3. **$n = 1$:** no edges — arrays of size $2(n-1)=0$, loops must still produce the single-vertex answer (all examples handle it).
4. **Tree knapsack loop bounds:** iterate $i \le S$ and $j \le s_c$ with the *current* sizes; looping to $n$ or $k$ for every merge breaks the $O(n^2)$ bound.
5. **Rerooting non-invertible combines:** don't divide by a contribution that may be 0 mod $M$ or under a composite modulus; use prefix/suffix (Example 4). Max/min are never invertible.
6. **Rerooting off-by-one:** $\text{up}(c)$ is "the DP of $v$'s side", which still needs to be *lifted* across the edge $(c, v)$ (the $+1$ in Example 4, the $+1$ distance in eccentricities) when used at $c$.
7. **Overflow:** sums of weighted distances reach $10^{16}$; products mod $M$ up to $10^9$ need 64-bit intermediates (`P * pre % M * suf % M`).
8. **`% M` with $M = 1$:** initialise products to `1 % M`, not `1`, when $M$ can be 1.
9. **Memory in tree knapsack:** free children's tables after merging (Example 5) — otherwise the total stays $O(n^2)$ memory.
10. **Java adjacency:** `ArrayList<Integer>[]` is slow and memory-hungry for $2\cdot10^5$ vertices; CSR arrays (`start`, `adj`) are 3–5× faster.
11. **Multiple statuses:** write the table of compatible (parent status, child status) pairs explicitly before coding — most WA in tree DPs come from a forgotten combination.
12. **Forests:** run the DP from every unvisited vertex; combine the components' answers (product for counts, sum for optimisation).

---

## 7. Going further (toward 2400–2600+)

- **Small-to-large merging of DP tables** (maps keyed by depth): $O(n\log n)$ or $O(n \log^2 n)$ ([small to large](../10-Trees/03-small-to-large-and-dsu-on-tree.md)); **long-path decomposition** for depth-indexed DPs in $O(n)$.
- **Tree DP with convex tables** — merging by slope (slope trick on trees) or with the Aliens trick when the DP over "exactly $k$ chosen" is concave ([Aliens trick](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md)).
- **DP on virtual trees** for many small queries on a big tree ([virtual trees](../10-Trees/06-virtual-trees.md)).
- **Counting subtrees / connected sets with constraints** (CF 1499F *Diameter Cuts*: keep the max depth as a knapsack dimension, bounded by $k$ — the $O(nk)$ version of §1.4).
- **Rerooting with two best values** (eccentricity, "farthest marked vertex", CF 337D *Book of Evil*): store top-2 children instead of prefix/suffix when the combine is max.
- **Tree DP on edges as states** (CF 1032F *Vasya and Maximum Matching*): statuses describe whether the vertex is matched, unmatched-but-must-be, etc.
- **Centroid decomposition** for path-counting queries that are not decomposable by the highest vertex alone ([centroid](../10-Trees/05-centroid-decomposition.md)).

---

## 8. Practice ladder

**≤ 1700**
- [ ] [CF 1676G · White-Black Balanced Subtrees](https://codeforces.com/problemset/problem/1676/G) — 1300
- [ ] [AtCoder DP P · Independent Set](https://atcoder.jp/contests/dp/tasks/dp_p)
- [ ] [CSES 1130 · Tree Matching](https://cses.fi/problemset/task/1130)
- [ ] [CSES 1131 · Tree Diameter](https://cses.fi/problemset/task/1131)
- [ ] [CF 1528A · Parsa's Humongous Tree](https://codeforces.com/problemset/problem/1528/A) — 1600
- [ ] [CF 1689C · Infected Tree](https://codeforces.com/problemset/problem/1689/C) — 1600
- [ ] [CSES 1133 · Tree Distances II](https://cses.fi/problemset/task/1133) — rerooting sums
- [ ] [CF 219D · Choosing Capital for Treeland](https://codeforces.com/problemset/problem/219/D) — 1700

**1700–2100**
- [ ] [CF 161D · Distance in Tree](https://codeforces.com/problemset/problem/161/D) — 1800
- [ ] [CF 1324F · Maximum White Subtree](https://codeforces.com/problemset/problem/1324/F) — 1800
- [ ] [CF 1083A · The Fair Nut and the Best Path](https://codeforces.com/problemset/problem/1083/A) — 1800
- [ ] [CF 1092F · Tree with Maximum Cost](https://codeforces.com/problemset/problem/1092/F) — 1900
- [ ] [CF 1153D · Serval and Rooted Tree](https://codeforces.com/problemset/problem/1153/D) — 1900
- [ ] [CF 461B · Appleman and Tree](https://codeforces.com/problemset/problem/461/B) — 2000
- [ ] [CF 337D · Book of Evil](https://codeforces.com/problemset/problem/337/D) — 2000
- [ ] [CF 1294F · Three Paths on a Tree](https://codeforces.com/problemset/problem/1294/F) — 2000
- [ ] [CF 1187E · Tree Painting](https://codeforces.com/problemset/problem/1187/E) — 2100

**2100+**
- [ ] [AtCoder DP V · Subtree](https://atcoder.jp/contests/dp/tasks/dp_v)
- [ ] [CF 543D · Road Improvement](https://codeforces.com/problemset/problem/543/D) — 2300
- [ ] [CF 708C · Centroids](https://codeforces.com/problemset/problem/708/C) — 2300
- [ ] [CF 815C · Karen and Supermarket](https://codeforces.com/problemset/problem/815/C) — 2400
- [ ] [CF 1499F · Diameter Cuts](https://codeforces.com/problemset/problem/1499/F) — 2400
- [ ] [CF 1032F · Vasya and Maximum Matching](https://codeforces.com/problemset/problem/1032/F) — 2400

---

## 9. LeetCode / FAANG cross-reference

- [LC 337 · House Robber III](https://leetcode.com/problems/house-robber-iii/) — Medium — max-weight independent set (§1.1).
- [LC 124 · Binary Tree Maximum Path Sum](https://leetcode.com/problems/binary-tree-maximum-path-sum/) — Hard — highest-vertex classification with negative weights.
- [LC 543 · Diameter of Binary Tree](https://leetcode.com/problems/diameter-of-binary-tree/) — Easy — §1.3.
- [LC 968 · Binary Tree Cameras](https://leetcode.com/problems/binary-tree-cameras/) — Hard — three statuses (has camera / covered / not covered).
- [LC 834 · Sum of Distances in Tree](https://leetcode.com/problems/sum-of-distances-in-tree/) — Hard — rerooting by subtraction (Example 3 with unit weights).
- [LC 310 · Minimum Height Trees](https://leetcode.com/problems/minimum-height-trees/) — Medium — eccentricities by rerooting (or peel leaves).
- [LC 2858 · Minimum Edge Reversals So Every Node Is Reachable](https://leetcode.com/problems/minimum-edge-reversals-so-every-node-is-reachable/) — Hard — rerooting with $\pm1$ edge costs (CF 219D).
- [LC 2246 · Longest Path With Different Adjacent Characters](https://leetcode.com/problems/longest-path-with-different-adjacent-characters/) — Hard — top-2 children with a filter.
- [LC 1372 · Longest ZigZag Path in a Binary Tree](https://leetcode.com/problems/longest-zigzag-path-in-a-binary-tree/) — Medium — status = direction of the last edge.

Tree DP is common in interviews in its binary-tree form (LC 337/124/968); the follow-up "now for every root" is rerooting — explain the two passes.

---

## 10. Self-check

1. Why are the children's subtrees independent once $v$'s status is fixed?
2. How do you compute a post-order without recursion, and why does reverse BFS order work?
3. Prove that tree knapsack with size-bounded loops is $O(n^2)$.
4. Derive $\text{cost}(c) = \text{cost}(v) + A - 2A_c$.
5. When must rerooting use prefix/suffix aggregates instead of subtraction?
6. In Example 4, why is the answer for $v$ a product over *all* neighbours of $(h + 1)$?
7. Why does Example 5 not need a DFS at all?
8. What changes if the input is a forest?

<details><summary>Answers</summary>

1. They share no vertices and every path between them passes through $v$; with $v$'s status fixed, every constraint involving one child's subtree mentions only that subtree and $v$.
2. BFS from the root records each vertex after its parent; reading the order backwards visits every vertex after all its descendants, which is all a bottom-up DP needs.
3. A merge of a part of size $S$ with a child subtree of size $s_c$ costs $O(S\cdot s_c)$ = number of pairs with one vertex in each; those pairs are joined for the first and only time at this merge (at their LCA), so the total is at most $\binom n2$.
4. Moving the root from $v$ to its child $c$ decreases the distance of every vertex in $c$'s subtree (total weight $A_c$) by 1 and increases every other distance (weight $A - A_c$) by 1.
5. When the combine has no inverse: max/min, products modulo a composite, or products where a factor may be $0$.
6. Rooted at $v$, a connected black set containing $v$ is determined by an independent choice for each neighbour's side: empty (1 way) or a connected set containing that neighbour ($h$ ways).
7. Every parent index is smaller than its child's, so processing indices from $n$ down to 2 and merging each into its parent finishes all children before their parent.
8. Run the DP from every unvisited vertex and combine component answers (sum for optimisation, product for counts); rerooting is per component.

</details>
