# Disjoint Set Union (Union–Find) and Its Variants

> **Band:** 🔵 1400–2100 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [graph representation, BFS/DFS](../09-Graphs/01-graph-representation-bfs-dfs.md), [recursion](../01-Foundations/04-recursion-brute-force-and-backtracking.md)
> **You can say you know this when:** you can write a DSU with union by size and an iterative find in both languages from memory; extend it with per-component data, potentials ($x_u - x_v = w$) and parity; and recognise when to run DSU on reversed time, on indices ("next free cell"), or with rollbacks.

## 1. First principles — why this works

**The problem.** Maintain a partition of $\{1..n\}$ under two operations: *merge the sets containing $u$ and $v$*, and *are $u$ and $v$ in the same set?*
Equivalently: incremental connectivity of a graph whose edges only get added.

- Relabelling a `comp[]` array on every merge is $O(n)$ per merge → $O(n^2)$.
- BFS per query is $O(n + m)$ per query.

**Forest of parent pointers.** Represent each set as a rooted tree; the root is the set's *representative*. `find(x)` follows parents to the root;
`union(u, v)` makes one root the child of the other. Both are $O(\text{depth})$. Without care the trees degenerate into chains ($O(n)$ depth). Two independent fixes:

1. **Union by size** (or by rank): attach the smaller tree under the larger. *Claim: depth $\le \log_2 n$.* A node's depth grows by 1 only when its tree is
   attached under a tree at least as large, so the size of the tree containing it at least doubles; that can happen at most $\log_2 n$ times.
2. **Path compression**: after `find(x)` reaches the root $r$, point every node on the path directly at $r$. Alone it gives $O(\log n)$ amortised per operation.

**Together: $O(\alpha(n))$ amortised** per operation (Tarjan, 1975), where $\alpha$ is the inverse Ackermann function — $\alpha(n) \le 4$ for every $n$ that
fits in this universe. In contests, treat DSU operations as $O(1)$. (*Path halving* — `p[x] = p[p[x]]; x = p[x]` in a loop — has the same bound, needs one pass and
no recursion: the right choice in Java.)

**Per-component data.** The root can store anything that merges in $O(1)$ (or small-to-large): size, sum, min/max, number of edges (a component has a cycle iff
$\#\text{edges} \ge \#\text{vertices}$), a flag. At `union`, combine the two roots' data into the new root. Keep a global counter of components.

**Weighted DSU / potentials.** Suppose constraints arrive as $x_v - x_u = w$ and we must detect contradictions or answer differences. Store for each node
$\text{pot}[x] = x_x - x_{\text{parent}(x)}$. Then the sum of `pot` along the path to the root is $x_x - x_{\text{root}}$, and path compression keeps this invariant if it
adds up the potentials while re-pointing. To merge under $x_v - x_u = w$ with roots $r_u, r_v$ and known $P_u = x_u - x_{r_u}$, $P_v = x_v - x_{r_v}$:

$$x_{r_v} - x_{r_u} = (x_v - P_v) - (x_u - P_u) = w + P_u - P_v,$$

so attach $r_v$ under $r_u$ with $\text{pot}[r_v] = w + P_u - P_v$ (or $r_u$ under $r_v$ with the negation). If $r_u = r_v$ the constraint is consistent iff $P_v - P_u = w$.
This works for any abelian group: integers under $+$, residues mod $k$, bit-vectors under xor.

**Parity DSU = online bipartiteness.** "$u$ and $v$ have different colours" is $c_u \oplus c_v = 1$ — the potential DSU over $\mathbb{Z}_2$. A contradiction is an odd cycle.
An alternative encoding uses $2n$ nodes ($u$ and $\bar u = u + n$): "different" = `union(u, v̄)`, `union(ū, v)`; contradiction iff `find(u) == find(ū)`. The potential
version is more general (it also answers "same or different?" for any pair in a component).

**DSU cannot delete — so reverse time.** If all deletions are known in advance (edges removed one by one, cells destroyed), process the events **backwards**:
start from the final state, *add* the deleted items back in reverse order, and record answers; then output them reversed. Many "after each removal print …"
problems become plain DSU this way.

**DSU on indices ("next free cell").** For "paint every unpainted cell in $[l, r]$" or "eliminate everyone still alive in $[l, r]$", keep `nxt[i]` = the smallest
unprocessed index $\ge i$ as a DSU over positions $1..n+1$: processing $i$ sets `nxt[i] = i + 1`, and `find(i)` with path compression jumps over processed runs.
Each index is processed once, so the total is $O((n + q)\,\alpha(n))$ — the same amortisation as "each element is deleted once".
Classic use: assignments where the *last* write wins — process queries in reverse and let each cell be written only by the first (i.e. latest) query that reaches it.

**DSU with rollback.** Some offline algorithms need to *undo* the most recent unions (segment tree over time, divide and conquer over queries). Use union by size
**without** path compression (compression changes many pointers; we would have to log them all). Then a union changes exactly two fields (`parent[child]`, `size[root]`):
push them on a stack; `rollback()` pops. `find` is $O(\log n)$. See [segment tree on time and DSU rollback](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md).

**Kruskal.** Sorting edges by weight and adding each edge that joins two different components builds a minimum spanning tree; DSU is the component oracle.
See [minimum spanning trees](../09-Graphs/03-minimum-spanning-trees.md). The same "sort then union" pattern answers offline threshold queries
("is $v$ reachable from $u$ using edges of weight $\le w$?") by sorting queries by $w$.

## 2. Formulas, definitions and identities

| Fact | Statement |
|---|---|
| depth under union by size | $\le \lfloor\log_2 n\rfloor$ (a node's set size doubles each time its depth grows) |
| path compression only | $O(\log n)$ amortised per operation |
| both | $O(m\,\alpha(n))$ for $m$ operations; $\alpha(n) \le 4$ in practice |
| rollback DSU | union by size, no compression: $O(\log n)$ find, $O(1)$ undo |
| potential invariant | $\sum_{\text{path } x \to r} \text{pot} = x_x - x_r$ |
| merge rule for $x_v - x_u = w$ | $\text{pot}[r_v] = w + P_u - P_v$ (attach $r_v$ under $r_u$) |
| consistency check (same root) | $P_v - P_u = w$ |
| cycle in a component | $\#E \ge \#V$; a forest has exactly $n - \#\text{components}$ edges |
| next-pointer DSU | each index removed once: $O((n + q)\alpha(n))$ |

## 3. Implementation (C++ and Java)

### 3.1 DSU with union by size and path halving

```cpp
struct DSU {
    vector<int> p, sz; int comps;
    explicit DSU(int n) : p(n), sz(n, 1), comps(n) { iota(p.begin(), p.end(), 0); }
    int find(int x) {
        while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; }     // path halving: iterative, O(alpha) amortised
        return x;
    }
    bool unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) swap(a, b);
        p[b] = a; sz[a] += sz[b]; comps--;
        return true;
    }
    bool same(int a, int b) { return find(a) == find(b); }
    int size(int a) { return sz[find(a)]; }
};
```

```java
static class DSU {
    final int[] p, sz; int comps;
    DSU(int n) { p = new int[n]; sz = new int[n]; comps = n; for (int i = 0; i < n; i++) { p[i] = i; sz[i] = 1; } }
    int find(int x) {
        while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; }       // no recursion: safe for n = 10^6 in Java
        return x;
    }
    boolean unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        p[b] = a; sz[a] += sz[b]; comps--;
        return true;
    }
    boolean same(int a, int b) { return find(a) == find(b); }
    int size(int a) { return sz[find(a)]; }
}
```

### 3.2 Weighted DSU (potentials) — relation $x_v - x_u = w$

Union by size bounds the depth by $\log_2 n$, so the recursive `find` is safe even in Java.

```cpp
struct WeightedDSU {
    vector<int> p, sz; vector<long long> pot;              // pot[x] = value(x) - value(p[x])
    explicit WeightedDSU(int n) : p(n), sz(n, 1), pot(n, 0) { iota(p.begin(), p.end(), 0); }
    int find(int x) {
        if (p[x] == x) return x;
        int r = find(p[x]);
        pot[x] += pot[p[x]];                               // now pot[x] = value(x) - value(r)
        return p[x] = r;
    }
    // add constraint value(v) - value(u) = w; returns false on contradiction (state unchanged)
    bool unite(int u, int v, long long w) {
        int ru = find(u), rv = find(v);
        long long pu = pot[u], pv = pot[v];
        if (ru == rv) return pv - pu == w;
        if (sz[ru] < sz[rv]) { swap(ru, rv); swap(pu, pv); w = -w; }   // now attach rv under ru
        p[rv] = ru; sz[ru] += sz[rv]; pot[rv] = w + pu - pv;
        return true;
    }
    bool same(int u, int v) { return find(u) == find(v); }
    long long diff(int u, int v) { find(u); find(v); return pot[v] - pot[u]; }   // value(v) - value(u), same set only
};
```

```java
static class WeightedDSU {
    final int[] p, sz; final long[] pot;                   // pot[x] = value(x) - value(p[x])
    WeightedDSU(int n) { p = new int[n]; sz = new int[n]; pot = new long[n]; for (int i = 0; i < n; i++) { p[i] = i; sz[i] = 1; } }
    int find(int x) {
        if (p[x] == x) return x;
        int r = find(p[x]);
        pot[x] += pot[p[x]];
        return p[x] = r;
    }
    boolean unite(int u, int v, long w) {                  // value(v) - value(u) = w
        int ru = find(u), rv = find(v);
        long pu = pot[u], pv = pot[v];
        if (ru == rv) return pv - pu == w;
        if (sz[ru] < sz[rv]) { int t = ru; ru = rv; rv = t; long s = pu; pu = pv; pv = s; w = -w; }
        p[rv] = ru; sz[ru] += sz[rv]; pot[rv] = w + pu - pv;
        return true;
    }
    boolean same(int u, int v) { return find(u) == find(v); }
    long diff(int u, int v) { find(u); find(v); return pot[v] - pot[u]; }
}
```

Why the swap negates $w$: after swapping the roles of $u$ and $v$, the constraint $x_v - x_u = w$ reads $x_{u'} - x_{v'} = w$, i.e. $x_{v'} - x_{u'} = -w$.

### 3.3 DSU with rollback

Original task: `1 a b` unite; `2 a b` print `YES`/`NO`; `3` save a checkpoint; `4` undo everything since the last checkpoint (and drop it); `5` print the number of components.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct RollbackDSU {
    vector<int> p, sz, hist; int comps;                    // hist = children attached, in order
    explicit RollbackDSU(int n) : p(n), sz(n, 1), comps(n) { iota(p.begin(), p.end(), 0); }
    int find(int x) const { while (p[x] != x) x = p[x]; return x; }   // no compression!
    bool unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) swap(a, b);
        p[b] = a; sz[a] += sz[b]; comps--; hist.push_back(b);
        return true;
    }
    int snapshot() const { return hist.size(); }
    void rollback(int snap) {
        while ((int)hist.size() > snap) {
            int b = hist.back(); hist.pop_back();
            sz[p[b]] -= sz[b]; p[b] = b; comps++;
        }
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    RollbackDSU d(n + 1); d.comps = n;                     // vertices 1..n
    vector<int> checkpoints;
    while (q--) {
        int t; cin >> t;
        if (t == 1) { int a, b; cin >> a >> b; d.unite(a, b); }
        else if (t == 2) { int a, b; cin >> a >> b; cout << (d.find(a) == d.find(b) ? "YES" : "NO") << '\n'; }
        else if (t == 3) checkpoints.push_back(d.snapshot());
        else if (t == 4) { d.rollback(checkpoints.back()); checkpoints.pop_back(); }
        else cout << d.comps << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] p, sz, hist; static int histTop = 0, comps;
    static int find(int x) { while (p[x] != x) x = p[x]; return x; }
    static void unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        p[b] = a; sz[a] += sz[b]; comps--; hist[histTop++] = b;
    }
    static void rollback(int snap) {
        while (histTop > snap) { int b = hist[--histTop]; sz[p[b]] -= sz[b]; p[b] = b; comps++; }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        p = new int[n + 1]; sz = new int[n + 1]; hist = new int[n + 1]; comps = n;
        for (int i = 0; i <= n; i++) { p[i] = i; sz[i] = 1; }
        int[] cps = new int[q + 1]; int top = 0;
        while (q-- > 0) {
            int t = in.nextInt();
            if (t == 1) unite(in.nextInt(), in.nextInt());
            else if (t == 2) out.println(find(in.nextInt()) == find(in.nextInt()) ? "YES" : "NO");
            else if (t == 3) cps[top++] = histTop;
            else if (t == 4) rollback(cps[--top]);
            else out.println(comps);
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
5 12
1 1 2
3
1 2 3
1 4 5
2 1 3
5
4
2 1 3
2 1 2
5
1 3 3
5
out:
YES
2
NO
YES
4
4
-->
<!-- test
in:
1 4
5
3
4
5
out:
1
1
-->

## 4. Recognising the pattern

- **"Are $u$ and $v$ connected?" with edges only added**, or "number of components / largest component after each addition" → plain DSU.
- **Edges/cells only removed, all removals known** → reverse time and add them back.
- **"Group items that share a property"** (same letter in some word, same email, common prime factor) → union each item with a virtual node per property value.
- **Equations/relations between pairs** ($x_v - x_u = w$, "same/different", $x_v \oplus x_u = w$, "$a/b = k$") with contradiction detection → potential DSU.
- **"Is the graph still bipartite after each edge?"** → parity DSU.
- **"Process every not-yet-processed index in $[l, r]$"** (painting, elimination, filling) → next-pointer DSU; with "last write wins", go through queries in reverse.
- **Threshold connectivity** ("using only edges with weight $\le w$") → sort edges and queries by weight, Kruskal-style sweep.
- **Need to undo unions** (offline dynamic connectivity, divide and conquer) → rollback DSU.
- Confused with: BFS/DFS (enough when the graph is static and you need it once); DSU wins when edges arrive over time or queries interleave.

## 5. Worked examples (graded)

### Example 1 — Road Construction  ·  ★ ≈1400

- **Source:** [CSES 1676 · Road Construction](https://cses.fi/problemset/task/1676)
- **Difficulty:** ≈1400 (est.)
- **Problem:** $n \le 10^5$ cities, $m \le 2\cdot10^5$ roads built one by one. After each road print the number of components and the size of the largest component.
- **Thinking from first principles:** components only merge, so DSU with sizes. The largest component never shrinks, so it is a running maximum updated at each successful union — no heap needed.

<details><summary>Solution</summary>

$O((n + m)\alpha(n))$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<int> p(n + 1), sz(n + 1, 1);
    iota(p.begin(), p.end(), 0);
    auto find = [&](int x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; } return x; };
    int comps = n, best = 1;
    while (m--) {
        int a, b; cin >> a >> b;
        a = find(a); b = find(b);
        if (a != b) {
            if (sz[a] < sz[b]) swap(a, b);
            p[b] = a; sz[a] += sz[b]; comps--;
            best = max(best, sz[a]);
        }
        cout << comps << ' ' << best << '\n';
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
        int n = in.nextInt(), m = in.nextInt();
        int[] p = new int[n + 1], sz = new int[n + 1];
        for (int i = 0; i <= n; i++) { p[i] = i; sz[i] = 1; }
        int comps = n, best = 1;
        while (m-- > 0) {
            int a = in.nextInt(), b = in.nextInt();
            while (p[a] != a) { p[a] = p[p[a]]; a = p[a]; }
            while (p[b] != b) { p[b] = p[p[b]]; b = p[b]; }
            if (a != b) {
                if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
                p[b] = a; sz[a] += sz[b]; comps--;
                best = Math.max(best, sz[a]);
            }
            out.println(comps + " " + best);
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
5 3
1 2
1 3
4 5
out:
4 2
3 3
2 3
-->
<!-- test
in:
2 3
1 1
1 2
2 1
out:
2 1
1 2
1 2
-->

</details>

### Example 2 — Knight Tournament (next-pointer DSU)  ·  ★ 1500

- **Source:** [CF 356A · Knight Tournament](https://codeforces.com/problemset/problem/356/A) — 1500
- **Difficulty:** 1500
- **Problem:** $n, m \le 3\cdot10^5$. Fight $i$ involves all knights *still in the tournament* with numbers in $[l_i, r_i]$; knight $x_i$ (who is guaranteed to be there) wins and all others in the fight are eliminated by him. For each knight print who eliminated him (0 for the final winner).
- **Thinking from first principles:** scanning $[l, r]$ each fight is $O(nm)$. The waste is re-visiting eliminated knights. Each knight is eliminated once, so if we can *jump over* eliminated
  knights, total work is $O(n + m)$ up to the jumps — the next-pointer DSU: `nxt[i]` = next knight $\ge i$ still in. After eliminating $i$, `nxt[i] = i + 1`.

<details><summary>Solution</summary>

For each fight: `i = find(l)`; while `i <= r`: if `i != x`, record `ans[i] = x` and set `nxt[i] = i + 1`; `i = find(i + 1)`. The winner stays.
$O((n + m)\alpha(n))$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<int> nxt(n + 2), ans(n + 1, 0);
    iota(nxt.begin(), nxt.end(), 0);
    auto find = [&](int x) { while (nxt[x] != x) { nxt[x] = nxt[nxt[x]]; x = nxt[x]; } return x; };
    while (m--) {
        int l, r, x; cin >> l >> r >> x;
        for (int i = find(l); i <= r; i = find(i + 1))
            if (i != x) { ans[i] = x; nxt[i] = i + 1; }
    }
    for (int i = 1; i <= n; i++) cout << ans[i] << (i < n ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] nxt;
    static int find(int x) { while (nxt[x] != x) { nxt[x] = nxt[nxt[x]]; x = nxt[x]; } return x; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        nxt = new int[n + 2];
        for (int i = 0; i < n + 2; i++) nxt[i] = i;
        int[] ans = new int[n + 1];
        while (m-- > 0) {
            int l = in.nextInt(), r = in.nextInt(), x = in.nextInt();
            for (int i = find(l); i <= r; i = find(i + 1))
                if (i != x) { ans[i] = x; nxt[i] = i + 1; }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= n; i++) sb.append(ans[i]).append(i < n ? ' ' : '\n');
        System.out.print(sb);
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
4 3
1 2 1
1 3 3
1 4 4
out:
3 1 4 0
-->
<!-- test
in:
8 4
3 5 4
3 7 6
2 8 8
1 8 1
out:
0 8 4 6 4 8 6 1
-->
<!-- test
in:
2 1
1 2 2
out:
2 0
-->

</details>

### Example 3 — Destroying Array (reverse time)  ·  ★ 1600

- **Source:** [CF 722C · Destroying Array](https://codeforces.com/problemset/problem/722/C) — 1600
- **Difficulty:** 1600
- **Problem:** $n \le 10^5$ non-negative values; elements are destroyed one by one in a given order (a permutation). After each destruction print the maximum sum of a contiguous segment containing no destroyed element (0 if none).
- **Thinking from first principles:** destruction *splits* segments — DSU cannot split. But the full destruction order is known. Reversed, it is a sequence of *insertions*:
  an inserted element merges with alive neighbours, and the best segment sum can only grow, so a running maximum suffices. The answer after the $i$-th destruction equals the state
  in which only elements destroyed *after* step $i$ are present.

<details><summary>Solution</summary>

`ans[n] = 0`; for $i = n$ down to $2$: revive $p_i$, merge with $p_i \pm 1$ if alive, `best = max(best, sum[root])`, `ans[i-1] = best`. Sums up to $10^{14}$ → 64-bit. $O(n\,\alpha(n))$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long long> a(n + 2, 0), sum(n + 2, 0);
    for (int i = 1; i <= n; i++) cin >> a[i];
    vector<int> ord(n);
    for (auto& x : ord) cin >> x;
    vector<int> p(n + 2), sz(n + 2, 1);
    iota(p.begin(), p.end(), 0);
    vector<char> alive(n + 2, 0);
    auto find = [&](int x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; } return x; };
    auto unite = [&](int x, int y) {
        x = find(x); y = find(y);
        if (x == y) return;
        if (sz[x] < sz[y]) swap(x, y);
        p[y] = x; sz[x] += sz[y]; sum[x] += sum[y];
    };
    vector<long long> ans(n + 1, 0);
    long long best = 0;
    for (int i = n - 1; i >= 1; i--) {                          // revive ord[i] (0-indexed); answer for step i
        int v = ord[i];
        alive[v] = 1; sum[v] = a[v];
        if (alive[v - 1]) unite(v, v - 1);
        if (alive[v + 1]) unite(v, v + 1);
        best = max(best, sum[find(v)]);
        ans[i] = best;
    }
    for (int i = 1; i <= n; i++) cout << ans[i] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] p, sz; static long[] sum;
    static int find(int x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x]; } return x; }
    static void unite(int x, int y) {
        x = find(x); y = find(y);
        if (x == y) return;
        if (sz[x] < sz[y]) { int t = x; x = y; y = t; }
        p[y] = x; sz[x] += sz[y]; sum[x] += sum[y];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long[] a = new long[n + 2];
        for (int i = 1; i <= n; i++) a[i] = in.nextLong();
        int[] ord = new int[n];
        for (int i = 0; i < n; i++) ord[i] = in.nextInt();
        p = new int[n + 2]; sz = new int[n + 2]; sum = new long[n + 2];
        for (int i = 0; i < n + 2; i++) { p[i] = i; sz[i] = 1; }
        boolean[] alive = new boolean[n + 2];
        long[] ans = new long[n + 1];
        long best = 0;
        for (int i = n - 1; i >= 1; i--) {
            int v = ord[i];
            alive[v] = true; sum[v] = a[v];
            if (alive[v - 1]) unite(v, v - 1);
            if (alive[v + 1]) unite(v, v + 1);
            best = Math.max(best, sum[find(v)]);
            ans[i] = best;
        }
        for (int i = 1; i <= n; i++) out.println(ans[i]);
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

The loop index `i` runs over 0-indexed positions of `ord`; reviving `ord[i]` produces the state after destructions `ord[0..i-1]`, i.e. the answer printed after the $i$-th destruction (1-indexed).

<!-- test
in:
4
1 3 2 5
3 4 1 2
out:
5
4
3
0
-->
<!-- test
in:
5
1 2 3 4 5
4 2 3 5 1
out:
6
5
5
1
0
-->
<!-- test
in:
1
1000000000
1
out:
0
-->

</details>

### Example 4 — The Number of Imposters (parity DSU)  ·  ★ 1700

- **Source:** [CF 1594D · The Number of Imposters](https://codeforces.com/problemset/problem/1594/D) — 1700
- **Difficulty:** 1700
- **Problem:** $t$ tests; $n$ players, each an *imposter* (always lies) or a *crewmate* (always truthful), and $m$ comments "$i$ says $j$ is an imposter/crewmate" (total $n \le 2\cdot10^5$, $m \le 5\cdot10^5$). Print the maximum possible number of imposters, or $-1$ if the comments are contradictory.
- **Thinking from first principles:** if $i$ says "$j$ is an imposter": a truthful $i$ makes $j$ an imposter, a lying $i$ makes $j$ a crewmate — either way **$i$ and $j$ have different types**. "Crewmate" means **same type**.
  So each comment is a parity constraint $t_i \oplus t_j = c$. A component of constraints has exactly two consistent assignments (flip everything), and we choose per component the one with more imposters.
  Contradiction ⇔ some constraint closes an odd-parity cycle — exactly what the parity DSU detects.

<details><summary>Solution</summary>

Potential DSU over $\mathbb{Z}_2$ (`par[x]` = parity of $x$ relative to its parent). At the end, count per root how many vertices have parity 0 and 1; add the larger. $O((n + m)\log n)$ with
union by size and a recursive find of depth $\le\log n$ (C++), iterative two-pass find in Java.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> p, sz, par;                                         // par[x] = type(x) xor type(p[x])
int find(int x) {
    if (p[x] == x) return x;
    int r = find(p[x]);
    par[x] ^= par[p[x]];
    return p[x] = r;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) {
        int n, m; cin >> n >> m;
        p.assign(n + 1, 0); sz.assign(n + 1, 1); par.assign(n + 1, 0);
        iota(p.begin(), p.end(), 0);
        bool ok = true;
        for (int k = 0; k < m; k++) {
            int i, j; string s; cin >> i >> j >> s;
            int c = (s[0] == 'i');                              // imposter claim -> different types
            int ri = find(i), rj = find(j);
            if (ri == rj) { if ((par[i] ^ par[j]) != c) ok = false; continue; }
            if (sz[ri] < sz[rj]) { swap(ri, rj); swap(i, j); }
            p[rj] = ri; sz[ri] += sz[rj]; par[rj] = par[i] ^ par[j] ^ c;
        }
        if (!ok) { cout << -1 << '\n'; continue; }
        vector<array<int, 2>> cnt(n + 1, {0, 0});
        for (int v = 1; v <= n; v++) { int r = find(v); cnt[r][par[v]]++; }
        long long ans = 0;
        for (int v = 1; v <= n; v++) if (find(v) == v) ans += max(cnt[v][0], cnt[v][1]);
        cout << ans << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] p, sz, par, stk;
    static int find(int x) {                                    // iterative: collect the path, then fix parities top-down
        int top = 0;
        while (p[x] != x) { stk[top++] = x; x = p[x]; }
        int r = x;
        for (int k = top - 1; k >= 0; k--) {                    // stk[top-1] is the child of the root
            int v = stk[k];
            if (p[v] != r) par[v] ^= par[p[v]];                 // p[v] already points to r with a corrected parity
            p[v] = r;
        }
        return r;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) {
            int n = in.nextInt(), m = in.nextInt();
            p = new int[n + 1]; sz = new int[n + 1]; par = new int[n + 1]; stk = new int[n + 1];
            for (int i = 0; i <= n; i++) { p[i] = i; sz[i] = 1; }
            boolean ok = true;
            for (int k = 0; k < m; k++) {
                int i = in.nextInt(), j = in.nextInt();
                int c = in.next().charAt(0) == 'i' ? 1 : 0;
                int ri = find(i), rj = find(j);
                if (ri == rj) { if ((par[i] ^ par[j]) != c) ok = false; continue; }
                if (sz[ri] < sz[rj]) { int t = ri; ri = rj; rj = t; t = i; i = j; j = t; }
                p[rj] = ri; sz[ri] += sz[rj]; par[rj] = par[i] ^ par[j] ^ c;
            }
            if (!ok) { out.println(-1); continue; }
            int[][] cnt = new int[n + 1][2];
            for (int v = 1; v <= n; v++) { int r = find(v); cnt[r][par[v]]++; }
            long ans = 0;
            for (int v = 1; v <= n; v++) if (p[v] == v) ans += Math.max(cnt[v][0], cnt[v][1]);
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
        String next() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
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

Why the merge sets `par[rj] = par[i] ^ par[j] ^ c`: we need $t_i \oplus t_j = c$ with $t_i = \text{par}_i \oplus t_{r_i}$ and $t_j = \text{par}_j \oplus t_{r_j}$, so $t_{r_j}\oplus t_{r_i} = \text{par}_i \oplus\text{par}_j\oplus c$ — the parity DSU instance of the potential formula.
(In the Java `find`, after the top-down pass every node on the path points to the root and its parity is relative to the root.)

<!-- test
in:
5
3 2
1 2 imposter
2 3 crewmate
5 4
1 3 crewmate
2 5 crewmate
2 4 imposter
3 4 imposter
2 2
1 2 imposter
2 1 crewmate
3 5
1 2 imposter
1 2 imposter
3 2 crewmate
3 2 crewmate
1 3 imposter
5 0
out:
2
4
-1
2
5
-->
<!-- test
in:
1
1 1
1 1 imposter
out:
-1
-->

</details>

### Example 5 — Restructuring Company (DSU + next pointer)  ·  ★ 1900

- **Source:** [CF 566D · Restructuring Company](https://codeforces.com/problemset/problem/566/D) — 1900
- **Difficulty:** 1900
- **Problem:** $n \le 2\cdot10^5$ employees, each initially alone; $q \le 5\cdot10^5$ queries: `1 x y` merge the teams of $x$ and $y$; `2 x y` merge the teams of all of $x, x+1, \dots, y$; `3 x y` print `YES` if $x, y$ are in the same team, else `NO`.
- **Thinking from first principles:** type 2 is a chain of unions $(i, i+1)$ for $i \in [x, y)$ — up to $n$ unions per query, $O(nq)$ total. But a link $(i, i+1)$ needs to be made **once**:
  after that it is redundant forever. Keep a second DSU over link positions, `nxt[i]` = first $j \ge i$ whose link $(j, j+1)$ is not yet made. Each link is made once → $O(n)$ links overall, plus $O(\alpha)$ jumps per query.

<details><summary>Solution</summary>

Two DSUs: `team` (union by size) and `nxt` (next unmade link). Type 2: `for (j = nxt.find(x); j < y; j = nxt.find(j + 1)) { team.unite(j, j+1); nxt[j] = j+1; }`. $O((n + q)\alpha(n))$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<int> p(n + 2), sz(n + 2, 1), nx(n + 2);
    iota(p.begin(), p.end(), 0); iota(nx.begin(), nx.end(), 0);
    auto find = [&](vector<int>& f, int x) { while (f[x] != x) { f[x] = f[f[x]]; x = f[x]; } return x; };
    auto unite = [&](int a, int b) {
        a = find(p, a); b = find(p, b);
        if (a == b) return;
        if (sz[a] < sz[b]) swap(a, b);
        p[b] = a; sz[a] += sz[b];
    };
    string out;
    while (q--) {
        int t, x, y; cin >> t >> x >> y;
        if (t == 1) unite(x, y);
        else if (t == 2) {
            for (int j = find(nx, x); j < y; j = find(nx, j + 1)) { unite(j, j + 1); nx[j] = j + 1; }
        } else out += (find(p, x) == find(p, y)) ? "YES\n" : "NO\n";
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] p, sz, nx;
    static int find(int[] f, int x) { while (f[x] != x) { f[x] = f[f[x]]; x = f[x]; } return x; }
    static void unite(int a, int b) {
        a = find(p, a); b = find(p, b);
        if (a == b) return;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        p[b] = a; sz[a] += sz[b];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        p = new int[n + 2]; sz = new int[n + 2]; nx = new int[n + 2];
        for (int i = 0; i < n + 2; i++) { p[i] = i; sz[i] = 1; nx[i] = i; }
        while (q-- > 0) {
            int t = in.nextInt(), x = in.nextInt(), y = in.nextInt();
            if (t == 1) unite(x, y);
            else if (t == 2) { for (int j = find(nx, x); j < y; j = find(nx, j + 1)) { unite(j, j + 1); nx[j] = j + 1; } }
            else out.println(find(p, x) == find(p, y) ? "YES" : "NO");
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
8 6
3 2 5
1 2 5
3 2 5
2 4 7
2 1 2
3 1 7
out:
NO
YES
YES
-->
<!-- test
in:
1 2
3 1 1
2 1 1
out:
YES
-->
<!-- test
in:
5 4
2 1 3
3 1 3
3 3 4
3 4 4
out:
YES
NO
YES
-->

</details>

### Example 6 — Difference constraints online (weighted DSU)  ·  ★ ≈1900

- **Source:** Original problem (the core of [LC 399 · Evaluate Division](https://leetcode.com/problems/evaluate-division/) — Medium and of [CF 1044D · Deduction Queries](https://codeforces.com/problemset/problem/1044/D) — 2400).
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n, q \le 2\cdot10^5$ unknown integers $x_1..x_n$. Queries: `1 a b d` — the fact $x_b - x_a = d$ ($|d| \le 10^9$): print `OK` if it is consistent with all accepted facts (and accept it), else `BAD` (and ignore it). `2 a b` — print $x_b - x_a$ if it is determined by the accepted facts, else `?`.
- **Thinking from first principles:** facts form a graph with weighted edges; $x_b - x_a$ is determined iff $a, b$ are connected, and then equals the weighted path length (all paths agree, since every accepted cycle has total 0).
  Running a BFS per query is $O(nq)$. The potential DSU stores exactly "offset to the representative", and merges two components by fixing one offset between their roots (§1). Offsets reach $2\cdot10^{14}$ → 64-bit.

<details><summary>Solution</summary>

The `WeightedDSU` of §3.2 verbatim. $O((n + q)\log n)$ worst case, effectively $O(\alpha)$ with compression.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct WeightedDSU {
    vector<int> p, sz; vector<long long> pot;
    explicit WeightedDSU(int n) : p(n), sz(n, 1), pot(n, 0) { iota(p.begin(), p.end(), 0); }
    int find(int x) {
        if (p[x] == x) return x;
        int r = find(p[x]);
        pot[x] += pot[p[x]];
        return p[x] = r;
    }
    bool unite(int u, int v, long long w) {
        int ru = find(u), rv = find(v);
        long long pu = pot[u], pv = pot[v];
        if (ru == rv) return pv - pu == w;
        if (sz[ru] < sz[rv]) { swap(ru, rv); swap(pu, pv); w = -w; }
        p[rv] = ru; sz[ru] += sz[rv]; pot[rv] = w + pu - pv;
        return true;
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    WeightedDSU d(n + 1);
    while (q--) {
        int t, a, b; cin >> t >> a >> b;
        if (t == 1) { long long w; cin >> w; cout << (d.unite(a, b, w) ? "OK" : "BAD") << '\n'; }
        else if (d.find(a) != d.find(b)) cout << "?\n";
        else cout << d.pot[b] - d.pot[a] << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] p, sz; static long[] pot;
    static int find(int x) {
        if (p[x] == x) return x;
        int r = find(p[x]);
        pot[x] += pot[p[x]];
        return p[x] = r;
    }
    static boolean unite(int u, int v, long w) {
        int ru = find(u), rv = find(v);
        long pu = pot[u], pv = pot[v];
        if (ru == rv) return pv - pu == w;
        if (sz[ru] < sz[rv]) { int t = ru; ru = rv; rv = t; long s = pu; pu = pv; pv = s; w = -w; }
        p[rv] = ru; sz[ru] += sz[rv]; pot[rv] = w + pu - pv;
        return true;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        p = new int[n + 1]; sz = new int[n + 1]; pot = new long[n + 1];
        for (int i = 0; i <= n; i++) { p[i] = i; sz[i] = 1; }
        while (q-- > 0) {
            int t = in.nextInt(), a = in.nextInt(), b = in.nextInt();
            if (t == 1) out.println(unite(a, b, in.nextLong()) ? "OK" : "BAD");
            else if (find(a) != find(b)) out.println("?");
            else out.println(pot[b] - pot[a]);
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
4 8
1 1 2 5
1 2 3 -2
2 1 3
2 3 1
1 1 3 4
2 1 4
1 4 3 10
2 4 2
out:
OK
OK
3
-3
BAD
?
OK
12
-->
<!-- test
in:
2 4
2 1 1
1 1 1 0
1 2 2 7
1 1 2 -1000000000
out:
0
OK
BAD
OK
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Recursive `find` without union by size can be $O(n)$ deep** → stack overflow in Java (and on Windows C++). Use path halving (iterative), or union by size (depth $\le \log n$) if you need a recursive potential `find`.
2. **Compare roots, not elements**: `find(a) == find(b)`; `p[a] == p[b]` is wrong after compression is partial.
3. **Merge per-component data at the root**, and only when the roots differ — adding sizes twice on a self-union is a classic bug.
4. **Potentials: update `pot` before re-pointing.** In the recursive find, `pot[x] += pot[p[x]]` must use the *old* parent (already compressed to the root), then `p[x] = r`.
5. **Swap carefully in the weighted union**: swapping the roots swaps the endpoints, which negates the constraint.
6. **Reverse-time problems**: the answer printed after step $i$ corresponds to the state *before* reviving element $i$ in reverse order — write the index mapping down explicitly (Example 3).
7. **Next-pointer DSU needs a sentinel** at $n+1$ (`nxt` of size $n+2$), otherwise `find(i + 1)` at $i = n$ reads out of bounds.
8. **Rollback DSU must not use path compression**; and rollbacks must be LIFO (undo the most recent unions first).
9. **Multi-test resets**: re-initialise only the first $n + 1$ entries per test; allocating $2\cdot10^5$-sized arrays for each of $10^4$ tests is fine only if sizes are per-test.
10. **Virtual nodes** for properties (letters, primes, emails): allocate $n + (\text{number of property values})$ nodes; for primes, union each number with its prime factors (sieve first).
11. **Kruskal with equal weights / offline threshold queries**: process all edges with weight $\le w$ before answering a query with threshold $w$ — sort queries and edges together with a consistent tie-break.
12. **Counting components**: maintain a counter decremented on successful unions instead of scanning for roots each time.

## 7. Going further (toward 2400–2600+)

- **Offline dynamic connectivity**: DSU with rollback over a segment tree of edge lifetimes ([segment tree on time](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md)); [CSES 2133 · Dynamic Connectivity](https://cses.fi/problemset/task/2133).
- **Parallel binary search with DSU** ("first time $u$ and $v$ become connected"): [CSES 2101 · New Roads Queries](https://cses.fi/problemset/task/2101) ([parallel binary search](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md)); also solvable with a Kruskal reconstruction tree.
- **Kruskal reconstruction tree** (each union creates a new node with the edge weight): turns threshold queries into LCA/subtree queries; [CF 1416D · Graph and Queries](https://codeforces.com/problemset/problem/1416/D) — 2600.
- **DSU with small-to-large set merging** (keep a set or map per component, merge smaller into larger): [CF 1559D2 · Mocha and Diana (Hard Version)](https://codeforces.com/problemset/problem/1559/D2) — 2500 needs a cleverer greedy, [CF 687D · Dividing Kingdom II](https://codeforces.com/problemset/problem/687/D) — 2500 uses parity DSU over sorted edges.
- **Xor potentials** answer "xor of a subarray" constraints online: [CF 1044D · Deduction Queries](https://codeforces.com/problemset/problem/1044/D) — 2400 (with coordinate hashing of prefix indices).
- **Link–cut trees** generalise DSU to forests with deletions online: [link-cut trees](../16-IGM-Frontier/03-link-cut-trees.md).

## 8. Practice ladder

**≤ 1500**
- [ ] [CSES 1676 · Road Construction](https://cses.fi/problemset/task/1676)
- [ ] [AtCoder PRACTICE2 A · Disjoint Set Union](https://atcoder.jp/contests/practice2/tasks/practice2_a)
- [ ] [CF 1167C · News Distribution](https://codeforces.com/problemset/problem/1167/C) — 1400
- [ ] [CF 277A · Learning Languages](https://codeforces.com/problemset/problem/277/A) — 1400
- [ ] [CF 1559D1 · Mocha and Diana (Easy Version)](https://codeforces.com/problemset/problem/1559/D1) — 1400
- [ ] [CF 356A · Knight Tournament](https://codeforces.com/problemset/problem/356/A) — 1500
- [ ] [CF 1263D · Secret Passwords](https://codeforces.com/problemset/problem/1263/D) — 1500
- [ ] [CF 977E · Cyclic Components](https://codeforces.com/problemset/problem/977/E) — 1500

**1500–1900**
- [ ] [CF 722C · Destroying Array](https://codeforces.com/problemset/problem/722/C) — 1600
- [ ] [CF 731C · Socks](https://codeforces.com/problemset/problem/731/C) — 1600
- [ ] [CF 1594D · The Number of Imposters](https://codeforces.com/problemset/problem/1594/D) — 1700
- [ ] [CF 1213G · Path Queries](https://codeforces.com/problemset/problem/1213/G) — 1800
- [ ] [CF 25D · Roads not only in Berland](https://codeforces.com/problemset/problem/25/D) — 1900
- [ ] [CF 566D · Restructuring Company](https://codeforces.com/problemset/problem/566/D) — 1900
- [ ] [CF 1620E · Replace the Numbers](https://codeforces.com/problemset/problem/1620/E) — 1900

**1900–2500**
- [ ] [CF 776D · The Door Problem](https://codeforces.com/problemset/problem/776/D) — 2000
- [ ] [CF 659F · Polycarp and Hay](https://codeforces.com/problemset/problem/659/F) — 2000
- [ ] [CF 920E · Connected Components?](https://codeforces.com/problemset/problem/920/E) — 2100
- [ ] [CF 609E · Minimum spanning tree for each edge](https://codeforces.com/problemset/problem/609/E) — 2100
- [ ] [CF 1044D · Deduction Queries](https://codeforces.com/problemset/problem/1044/D) — 2400
- [ ] [CF 915F · Imbalance Value of a Tree](https://codeforces.com/problemset/problem/915/F) — 2400
- [ ] [CF 687D · Dividing Kingdom II](https://codeforces.com/problemset/problem/687/D) — 2500

## 9. LeetCode / FAANG cross-reference

- [LC 547 · Number of Provinces](https://leetcode.com/problems/number-of-provinces/) — Medium — count components.
- [LC 684 · Redundant Connection](https://leetcode.com/problems/redundant-connection/) — Medium — first edge whose endpoints are already connected.
- [LC 685 · Redundant Connection II](https://leetcode.com/problems/redundant-connection-ii/) — Hard — directed version: in-degree-2 case analysis + DSU.
- [LC 721 · Accounts Merge](https://leetcode.com/problems/accounts-merge/) — Medium — union accounts through shared emails (virtual nodes).
- [LC 990 · Satisfiability of Equality Equations](https://leetcode.com/problems/satisfiability-of-equality-equations/) — Medium — unions for `==`, then check `!=`.
- [LC 399 · Evaluate Division](https://leetcode.com/problems/evaluate-division/) — Medium — weighted DSU with multiplicative potentials (or logs).
- [LC 128 · Longest Consecutive Sequence](https://leetcode.com/problems/longest-consecutive-sequence/) — Medium — union $x$ with $x \pm 1$ via a hash map (a hash set scan is simpler).
- [LC 1697 · Checking Existence of Edge Length Limited Paths](https://leetcode.com/problems/checking-existence-of-edge-length-limited-paths/) — Hard — offline threshold queries, Kruskal sweep.
- [LC 803 · Bricks Falling When Hit](https://leetcode.com/problems/bricks-falling-when-hit/) — Hard — reverse time with a virtual "roof" node.
- [LC 2382 · Maximum Segment Sum After Removals](https://leetcode.com/problems/maximum-segment-sum-after-removals/) — Hard — exactly Example 3.
- [LC 952 · Largest Component Size by Common Factor](https://leetcode.com/problems/largest-component-size-by-common-factor/) — Hard — union numbers with their prime factors.
- [LC 1579 · Remove Max Number of Edges to Keep Graph Fully Traversable](https://leetcode.com/problems/remove-max-number-of-edges-to-keep-graph-fully-traversable/) — Hard — two DSUs, shared edges first.
- [LC 305 · Number of Islands II](https://leetcode.com/problems/number-of-islands-ii/) — Hard 🔒 — online component count on a grid.
- [LC 2421 · Number of Good Paths](https://leetcode.com/problems/number-of-good-paths/) — Hard — process vertices by value, union with smaller neighbours, count per root.

Interview frequency: high. Expect to write DSU from memory and to explain path compression + union by rank in one sentence each.

## 10. Self-check

1. Prove that union by size keeps the depth at most $\log_2 n$.
2. Why must a rollback DSU avoid path compression?
3. Derive the merge formula of the weighted DSU for the constraint $x_v - x_u = w$.
4. How do you test bipartiteness after every added edge?
5. You must print the number of components after each of $m$ edge *deletions*. What do you do?
6. Explain the next-pointer trick and its total complexity for $q$ range-processing queries.
7. How do you detect whether a component contains a cycle using only DSU data?

<details><summary>Answers</summary>

1. A node's depth increases only when its root is attached under a root of a tree at least as large; then the size of its tree at least doubles. Sizes are $\le n$, so this happens $\le \log_2 n$ times.
2. A rollback must restore the exact previous state; compression changes $O(\text{path})$ pointers per find, all of which would need logging. Union by size alone changes two fields per union.
3. With $P_u = x_u - x_{r_u}$, $P_v = x_v - x_{r_v}$: $x_{r_v} - x_{r_u} = (x_v - P_v) - (x_u - P_u) = w + P_u - P_v$; attach $r_v$ under $r_u$ with that potential.
4. Parity DSU: each edge says "different colours" ($c_u \oplus c_v = 1$); the graph stops being bipartite at the first edge whose endpoints are in the same component with equal parity.
5. Read all deletions; start from the graph with all deleted edges removed; add edges back in reverse order, recording the component count before each addition; print the records reversed.
6. `nxt[i]` points to the first unprocessed index $\ge i$; processing $i$ sets `nxt[i] = i + 1`; each index is processed once and each query does $O(\alpha)$ extra jumps: $O((n + q)\alpha(n))$.
7. Keep vertex and edge counts per root; on every edge (including edges inside a component) increment the edge count; a component has a cycle iff edges $\ge$ vertices.

</details>
