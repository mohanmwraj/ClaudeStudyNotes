# Segment tree on time and DSU with rollback (offline dynamic connectivity)

> **Band:** 🔴 2400–2800 (DSU with rollback alone: 🟠 2200+) · **Priority:** 🧊 for the Dec-2027 Master target (rollback DSU itself: ⚡) · **FAANG:** none · **Prerequisites:** [DSU and variants](../08-Data-Structures/06-dsu-and-variants.md), [segment tree basics](../08-Data-Structures/02-segment-tree-basics.md), [offline techniques](01-offline-techniques-cdq-parallel-binary-search.md), [bipartite graphs](../09-Graphs/09-bipartite-graphs-and-cycles.md)
> **You can say you know this when:** given "add edge / remove edge / ask about connectivity (or bipartiteness, or a component statistic)" offline, you can write the segment tree over time with a rollback DSU in 15 minutes, and you can explain why path compression must be switched off.

## 1. First principles — why this works

### 1.1 The obstacle: DSU cannot delete

DSU answers "are $u$ and $v$ connected?" under edge **insertions** in near-constant time. Add **deletions** and everything breaks: removing an edge may or may not split a component, and finding out requires knowing whether another path exists. Fully dynamic connectivity *online* is a research-level structure (Holm–de Lichtenberg–Thorup, amortised $O(\log^2 n)$ per update) that nobody writes in a contest. The naive approach, recomputing components for every query, is $O(q(n+m))$.

If the whole sequence of operations is known in advance, every edge copy has a **lifetime**: the interval of operation indices $[s, e]$ during which it exists. Deletions disappear from the problem: the question becomes "which edges are alive at time $t$?"

### 1.2 Undo is easier than delete

Deleting an *arbitrary* edge is hard, but undoing the *most recent* union is easy if each union changes $O(1)$ memory cells: record what you changed and restore it. That gives a **stack** discipline: you can only roll back in reverse order of the unions.

Two consequences for the DSU:

- **Union by size (or rank) is mandatory.** It keeps every tree at depth $\le \log_2 n$, so `find` costs $O(\log n)$ in the worst case — no amortisation involved.
- **Path compression must be off.** Compression rewrites many parent pointers during `find`; undoing them would need a log entry per pointer, and the amortised analysis of compression assumes the structure never goes back in time: an adversary can force an expensive `find`, roll back, and repeat it forever. Union by size alone has a *worst-case* bound, which survives rollback.

### 1.3 Turning lifetimes into a stack discipline

Build a segment tree over the time axis $0..q-1$. Insert each edge with lifetime $[s,e]$ into the $O(\log q)$ canonical nodes that cover $[s,e]$ (exactly like a range update). Then DFS the segment tree:

```text
dfs(node):
    snapshot = dsu.history_size
    for edge in node.edges: dsu.unite(edge)
    if node is a leaf t: answer the query at time t
    else: dfs(left child); dfs(right child)
    dsu.rollback(snapshot)
```

**Why the leaf sees exactly the alive edges.** The canonical nodes of $[s,e]$ are disjoint and their union is $[s,e]$. Leaf $t$ lies under exactly one of them if $t \in [s,e]$ and under none otherwise. The root-to-leaf path passes through every ancestor of the leaf, so the edge is applied on the way to leaf $t$ **once** if it is alive at $t$ and **never** otherwise.

**Why rollback is legal.** The DFS enters and leaves nodes in a nested (LIFO) order, so the unions to undo are always the most recent ones.

### 1.4 Complexity

Each lifetime occupies at most $2\lceil\log_2 q\rceil$ nodes; each union costs a `find` of $O(\log n)$. Total:

$$O\big(q \log q \log n\big)\ \text{time},\qquad O(q\log q)\ \text{memory}.$$

For $q = 3\cdot10^5$ this is roughly $3\cdot10^5 \cdot 19 \cdot 19 \approx 10^8$ cheap operations, which is why these problems usually come with generous time limits.

### 1.5 The general pattern: offline deletion = segment tree on time + undoable insertion

Nothing above is specific to connectivity. Any structure that supports **insert** and **undo the last insert** cheaply gains **delete** offline:

| Structure | Insert | Undo | Classic use |
|---|---|---|---|
| DSU (union by size) | union | restore 2–4 cells | connectivity, component counts |
| DSU with parity | union with colour flag | restore | bipartiteness over time |
| DSU with XOR-to-root + linear basis | union / add cycle value | restore / pop basis copy | XOR shortest path over time |
| Bitset knapsack | `b = b OR (b << w)` | keep a copy per depth | subset sums under deletions |
| Any array DP with $O(\text{size})$ copy | update | restore the saved copy | "knapsack with deletions" |

The cost is one extra $\log q$ factor for the segment tree.

### 1.6 Leave-one-out divide and conquer

A related shape: "for each element $i$, answer the question for the set **without** $i$". Recurse on index ranges: `solve(l, r)` assumes every element outside $[l,r]$ is already inserted. Insert $[\text{mid}+1, r]$, recurse into $[l, \text{mid}]$, roll back; insert $[l, \text{mid}]$, recurse into $[\text{mid}+1, r]$, roll back. At a leaf $l = r$, exactly the elements $\ne l$ are inserted. Each element is inserted $O(\log m)$ times. This is the segment tree on time where element $i$ is alive on $[0, i-1] \cup [i+1, m-1]$, written without building the tree.

## 2. Formulas, definitions and identities

- **Depth bound for union by size:** depth$(x) \le \lfloor \log_2 n\rfloor$. *Proof:* the depth of $x$ grows by one only when the root of $x$'s tree becomes a child of another root whose tree is at least as large, so the size of the tree containing $x$ at least doubles each time; it cannot exceed $n$.
- **Canonical decomposition:** an interval of a segment tree over $q$ leaves splits into at most $2\lceil\log_2 q\rceil$ nodes.
- **Total cost:** $O(L \log q \cdot \log n)$ for $L$ lifetimes; memory $O(L\log q)$.
- **Lifetime bookkeeping:** an edge added by operation $s$ and removed by operation $e$ is alive for the states after operations $s, s+1, \dots, e-1$, i.e. the interval $[s, e-1]$. An edge never removed is alive on $[s, q-1]$.
- **Parity DSU:** store $\text{par}[x] =$ colour of $x$ XOR colour of its parent. Colour relative to the root: $c(x) = \bigoplus_{\text{path}} \text{par}$. Adding edge $(u,v)$ with roots $r_u \ne r_v$: attach $r_v$ under $r_u$ with $\text{par}[r_v] = c(u) \oplus c(v) \oplus 1$, which makes $c(u) \ne c(v)$. With $r_u = r_v$: the edge closes an odd cycle iff $c(u) = c(v)$.
- **Closure of a point set under rectangle completion** (Example 3): treat point $(x,y)$ as an edge between node $x$ and node $y'$ of a bipartite graph. Then
  $$|E(S)| = \sum_{\text{components } C} \#x(C)\cdot \#y(C).$$
  *Proof sketch:* adding the fourth corner of a rectangle never merges components (its endpoints are already connected through the other three corners), so components are invariant; and inside a component every pair $(x, y)$ is eventually added, by induction on the length of an $x$–$y$ path (a path $x - y_1 - x_1 - y$ of length 3 is exactly the rule, longer odd paths shorten by one rule application).
- **Leave-one-out D&C:** $O(m \log m)$ insertions, so $O(m\log m\log n)$ with a rollback DSU.

## 3. Implementation (C++ and Java)

### 3.1 DSU with rollback

`find` walks up without compression; `unite` records the child root and the parent root; `rollback(snap)` pops until the history has `snap` entries. The Java version keeps the history in two `int` arrays: at most $n-1$ unions can be live simultaneously, so size $n$ is enough.

```cpp
struct RollbackDSU {
    vector<int> p, sz;
    vector<pair<int, int>> hist;         // (child root b, parent root a) of every successful union
    int comps;
    RollbackDSU(int n) : p(n), sz(n, 1), comps(n) { iota(p.begin(), p.end(), 0); }
    int find(int x) const { while (p[x] != x) x = p[x]; return x; }   // no path compression!
    bool unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) swap(a, b);   // union by size keeps depth <= log2 n
        p[b] = a; sz[a] += sz[b]; comps--;
        hist.push_back({b, a});
        return true;
    }
    int snapshot() const { return hist.size(); }
    void rollback(int snap) {            // undo unions in reverse order, O(1) each
        while ((int)hist.size() > snap) {
            auto [b, a] = hist.back(); hist.pop_back();
            p[b] = b; sz[a] -= sz[b]; comps++;
        }
    }
};
```

```java
static final class RollbackDSU {
    final int[] p, sz;
    int[] histB, histA;
    int top = 0, comps;
    RollbackDSU(int n) {
        p = new int[n]; sz = new int[n]; comps = n;
        histB = new int[n]; histA = new int[n];      // at most n - 1 unions can be live at once
        for (int i = 0; i < n; i++) { p[i] = i; sz[i] = 1; }
    }
    int find(int x) { while (p[x] != x) x = p[x]; return x; }    // no path compression
    boolean unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        p[b] = a; sz[a] += sz[b]; comps--;
        histB[top] = b; histA[top] = a; top++;
        return true;
    }
    int snapshot() { return top; }
    void rollback(int snap) {
        while (top > snap) { top--; int b = histB[top], a = histA[top]; p[b] = b; sz[a] -= sz[b]; comps++; }
    }
}
```

Variants change only what is stored and restored: a parity bit (Examples 2 and 4), per-component counters and a running total (Example 3).

## 4. Recognising the pattern

- **"Add an edge / remove an edge / ask"** with no online decoding, $n, q \le 3\cdot10^5$ and a generous time limit → segment tree on time.
- **Toggles** ("if the edge exists remove it, otherwise add it") → each edge's lifetimes are the intervals between consecutive toggles.
- **"Each element exists from day $a$ to day $b$"** or "contacts expire after $k$ days" → lifetimes are given directly.
- **"For each $i$, is the property true without element $i$?"** → leave-one-out D&C with rollback.
- **The maintained quantity is non-decomposable** (connectivity, bipartiteness, component products) — that is what rules out CDQ from [offline techniques](01-offline-techniques-cdq-parallel-binary-search.md) and points here.
- **Only deletions** → no segment tree needed: reverse time and use a plain DSU.
- **Online forced** → think [link-cut trees](03-link-cut-trees.md) (forests, or maximum spanning forest keyed by deletion time when deletion times are known) or square-root rebuilding.

## 5. Worked examples (graded)

### Example 1 — Number of components under insertions and deletions  ·  ★ ≈2300 (est.)

- **Source:** Original problem (the same task, with a different input format, is [CSES 2133 · Dynamic Connectivity](https://cses.fi/problemset/task/2133)).
- **Difficulty:** ≈2300 (est.)
- **Problem:** $n$ vertices, $k \le 3\cdot10^5$ operations: `1 u v` adds an edge (multi-edges and loops allowed), `2 u v` removes one existing copy of edge $u$–$v$, `3` prints the number of connected components.
- **Thinking from first principles:** Recomputing per query is $O(k(n+k))$. DSU handles additions only. Offline, each edge copy lives on an interval of operation indices; store the start time of every live copy (a stack per unordered pair, so multi-edges pair up correctly), close the interval at the removal, and close all survivors at $k-1$. Then run the DFS of §1.3, keeping the component count inside the DSU (decrement on a successful union, increment on rollback).

<details><summary>Solution</summary>

Lifetimes: added at operation $s$, removed at operation $e$ → alive on $[s, e-1]$ (non-empty because $e > s$). The segment tree has one leaf per operation; non-query leaves simply do nothing. Complexity $O(k \log k \log n)$. A loop $u$–$u$ is harmless: `unite` returns false.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct RollbackDSU {
    vector<int> p, sz;
    vector<pair<int, int>> hist;
    int comps;
    RollbackDSU(int n) : p(n), sz(n, 1), comps(n) { iota(p.begin(), p.end(), 0); }
    int find(int x) const { while (p[x] != x) x = p[x]; return x; }
    bool unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return false;
        if (sz[a] < sz[b]) swap(a, b);
        p[b] = a; sz[a] += sz[b]; comps--;
        hist.push_back({b, a});
        return true;
    }
    int snapshot() const { return hist.size(); }
    void rollback(int snap) {
        while ((int)hist.size() > snap) {
            auto [b, a] = hist.back(); hist.pop_back();
            p[b] = b; sz[a] -= sz[b]; comps++;
        }
    }
};

int k;
vector<vector<pair<int, int>>> seg;      // edges stored at segment-tree nodes over time [0, k)
vector<int> type;
vector<int> answers;

void insert(int node, int l, int r, int ql, int qr, pair<int, int> e) {
    if (qr < l || r < ql) return;
    if (ql <= l && r <= qr) { seg[node].push_back(e); return; }
    int m = (l + r) / 2;
    insert(2 * node, l, m, ql, qr, e);
    insert(2 * node + 1, m + 1, r, ql, qr, e);
}

void dfs(int node, int l, int r, RollbackDSU& d) {
    int snap = d.snapshot();
    for (auto [u, v] : seg[node]) d.unite(u, v);   // these edges are alive on all of [l, r]
    if (l == r) {
        if (type[l] == 3) answers.push_back(d.comps);
    } else {
        int m = (l + r) / 2;
        dfs(2 * node, l, m, d);
        dfs(2 * node + 1, m + 1, r, d);
    }
    d.rollback(snap);                               // leave the DSU exactly as we found it
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n >> k;
    type.resize(k);
    seg.assign(4 * k, {});
    map<pair<int, int>, vector<int>> open;          // edge -> start times of its live copies
    for (int i = 0; i < k; i++) {
        cin >> type[i];
        if (type[i] == 3) continue;
        int u, v;
        cin >> u >> v;
        u--; v--;
        if (u > v) swap(u, v);
        if (type[i] == 1) open[{u, v}].push_back(i);
        else {
            auto& st = open[{u, v}];
            int s = st.back(); st.pop_back();
            insert(1, 0, k - 1, s, i - 1, {u, v});  // alive after op s, removed by op i
        }
    }
    for (auto& [e, st] : open)
        for (int s : st) insert(1, 0, k - 1, s, k - 1, e);
    RollbackDSU d(n);
    dfs(1, 0, k - 1, d);
    for (int x : answers) cout << x << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static final class RollbackDSU {
        final int[] p, sz;
        int[] histB, histA;
        int top = 0, comps;
        RollbackDSU(int n) {
            p = new int[n]; sz = new int[n]; comps = n;
            histB = new int[n]; histA = new int[n];
            for (int i = 0; i < n; i++) { p[i] = i; sz[i] = 1; }
        }
        int find(int x) { while (p[x] != x) x = p[x]; return x; }
        boolean unite(int a, int b) {
            a = find(a); b = find(b);
            if (a == b) return false;
            if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
            p[b] = a; sz[a] += sz[b]; comps--;
            histB[top] = b; histA[top] = a; top++;
            return true;
        }
        int snapshot() { return top; }
        void rollback(int snap) {
            while (top > snap) { top--; int b = histB[top], a = histA[top]; p[b] = b; sz[a] -= sz[b]; comps++; }
        }
    }

    static int k;
    static int[] head, nxt, eu, ev, type;      // edge lists of segment-tree nodes as intrusive linked lists
    static int cnt = 0;
    static RollbackDSU d;
    static StringBuilder sb = new StringBuilder();

    static void insert(int node, int l, int r, int ql, int qr, int u, int v) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) {
            if (cnt == eu.length) grow();
            eu[cnt] = u; ev[cnt] = v; nxt[cnt] = head[node]; head[node] = cnt++;
            return;
        }
        int m = (l + r) >>> 1;
        insert(2 * node, l, m, ql, qr, u, v);
        insert(2 * node + 1, m + 1, r, ql, qr, u, v);
    }

    static void grow() {
        eu = Arrays.copyOf(eu, eu.length * 2); ev = Arrays.copyOf(ev, ev.length * 2); nxt = Arrays.copyOf(nxt, nxt.length * 2);
    }

    static void dfs(int node, int l, int r) {
        int snap = d.snapshot();
        for (int e = head[node]; e != -1; e = nxt[e]) d.unite(eu[e], ev[e]);
        if (l == r) {
            if (type[l] == 3) sb.append(d.comps).append('\n');
        } else {
            int m = (l + r) >>> 1;
            dfs(2 * node, l, m);
            dfs(2 * node + 1, m + 1, r);
        }
        d.rollback(snap);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        k = in.nextInt();
        type = new int[k];
        head = new int[4 * k];
        Arrays.fill(head, -1);
        eu = new int[16]; ev = new int[16]; nxt = new int[16];
        HashMap<Long, ArrayDeque<Integer>> open = new HashMap<>();
        for (int i = 0; i < k; i++) {
            type[i] = in.nextInt();
            if (type[i] == 3) continue;
            int u = in.nextInt() - 1, v = in.nextInt() - 1;
            if (u > v) { int t = u; u = v; v = t; }
            long key = (long) u * n + v;
            if (type[i] == 1) open.computeIfAbsent(key, z -> new ArrayDeque<>()).push(i);
            else {
                int s = open.get(key).pop();
                insert(1, 0, k - 1, s, i - 1, u, v);
            }
        }
        for (Map.Entry<Long, ArrayDeque<Integer>> en : open.entrySet()) {
            int u = (int) (en.getKey() / n), v = (int) (en.getKey() % n);
            for (int s : en.getValue()) insert(1, 0, k - 1, s, k - 1, u, v);
        }
        d = new RollbackDSU(n);
        dfs(1, 0, k - 1);
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
4 8
3
1 1 2
1 3 4
3
1 2 3
3
2 1 2
3
out:
4
2
1
2
-->
<!-- test
in:
2 6
1 1 2
1 2 1
2 1 2
3
2 2 1
3
out:
1
2
-->
<!-- test
in:
1 1
3
out:
1
-->

### Example 2 — Bipartiteness after every toggle  ·  ★ 2500

- **Source:** [CF 813F · Bipartite Checking](https://codeforces.com/problemset/problem/813/F) — 2500
- **Difficulty:** 2500
- **Problem:** $n$ vertices, $q \le 10^5$ queries; each query names a pair $x < y$: if the edge is present remove it, otherwise add it. After each query report whether the graph is bipartite.
- **Thinking from first principles:** Bipartiteness is "no odd cycle", which is not decomposable over edges, so CDQ-style tricks fail. But a DSU that stores each vertex's colour relative to its parent can *insert* an edge and detect an odd cycle in $O(\log n)$, and it rolls back like the plain DSU. Toggles define lifetimes. One extra observation saves time: if the edges stored at a segment-tree node already create an odd cycle, every leaf below is "NO" and the subtree need not be explored.

<details><summary>Solution</summary>

Parity DSU as in §2. At a node, apply its edges; if one closes an odd cycle, mark the whole range $[l, r]$ as NO and roll back. Otherwise recurse (or mark the leaf YES). Marking a range costs $O(r-l+1)$ but each range is marked once and the ranges of pruned subtrees are disjoint, so the total is $O(q)$. Complexity $O(q\log q\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

// DSU with parity (colour of x relative to its parent) and rollback.
struct ParityDSU {
    vector<int> p, sz, par;
    vector<pair<int, int>> hist;
    ParityDSU(int n) : p(n), sz(n, 1), par(n, 0) { iota(p.begin(), p.end(), 0); }
    pair<int, int> find(int x) const {          // (root, colour of x relative to root)
        int c = 0;
        while (p[x] != x) { c ^= par[x]; x = p[x]; }
        return {x, c};
    }
    bool addEdge(int u, int v) {                // false if the edge closes an odd cycle
        auto [a, ca] = find(u);
        auto [b, cb] = find(v);
        if (a == b) return ca != cb;
        if (sz[a] < sz[b]) swap(a, b);
        p[b] = a; sz[a] += sz[b];
        par[b] = ca ^ cb ^ 1;                    // forces colour(u) != colour(v)
        hist.push_back({b, a});
        return true;
    }
    int snapshot() const { return hist.size(); }
    void rollback(int snap) {
        while ((int)hist.size() > snap) {
            auto [b, a] = hist.back(); hist.pop_back();
            p[b] = b; par[b] = 0; sz[a] -= sz[b];
        }
    }
};

int q;
vector<vector<pair<int, int>>> seg;
vector<char> ok;

void insert(int node, int l, int r, int ql, int qr, pair<int, int> e) {
    if (qr < l || r < ql) return;
    if (ql <= l && r <= qr) { seg[node].push_back(e); return; }
    int m = (l + r) / 2;
    insert(2 * node, l, m, ql, qr, e);
    insert(2 * node + 1, m + 1, r, ql, qr, e);
}

void dfs(int node, int l, int r, ParityDSU& d) {
    int snap = d.snapshot();
    bool good = true;
    for (auto [u, v] : seg[node]) if (!d.addEdge(u, v)) { good = false; break; }
    if (!good) {
        for (int t = l; t <= r; t++) ok[t] = 0;   // an odd cycle is alive during all of [l, r]
    } else if (l == r) {
        ok[l] = 1;
    } else {
        int m = (l + r) / 2;
        dfs(2 * node, l, m, d);
        dfs(2 * node + 1, m + 1, r, d);
    }
    d.rollback(snap);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n >> q;
    seg.assign(4 * q, {});
    ok.assign(q, 0);
    map<pair<int, int>, int> since;              // present edge -> time it was added
    for (int i = 0; i < q; i++) {
        int x, y;
        cin >> x >> y;
        x--; y--;
        if (x > y) swap(x, y);
        auto it = since.find({x, y});
        if (it == since.end()) since[{x, y}] = i;
        else { insert(1, 0, q - 1, it->second, i - 1, {x, y}); since.erase(it); }
    }
    for (auto& [e, s] : since) insert(1, 0, q - 1, s, q - 1, e);
    ParityDSU d(n);
    dfs(1, 0, q - 1, d);
    for (int i = 0; i < q; i++) cout << (ok[i] ? "YES" : "NO") << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int[] p, sz, par, histB, histA;
    static int top = 0;
    static int find(int x) { while (p[x] != x) x = p[x]; return x; }
    static int colour(int x) { int c = 0; while (p[x] != x) { c ^= par[x]; x = p[x]; } return c; }
    static boolean addEdge(int u, int v) {
        int a = find(u), b = find(v), ca = colour(u), cb = colour(v);
        if (a == b) return ca != cb;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        p[b] = a; sz[a] += sz[b]; par[b] = ca ^ cb ^ 1;
        histB[top] = b; histA[top] = a; top++;
        return true;
    }
    static void rollback(int snap) {
        while (top > snap) { top--; int b = histB[top], a = histA[top]; p[b] = b; par[b] = 0; sz[a] -= sz[b]; }
    }

    static int q, cnt = 0;
    static int[] head, nxt, eu, ev;
    static boolean[] ok;

    static void insert(int node, int l, int r, int ql, int qr, int u, int v) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) {
            if (cnt == eu.length) { eu = Arrays.copyOf(eu, 2 * cnt); ev = Arrays.copyOf(ev, 2 * cnt); nxt = Arrays.copyOf(nxt, 2 * cnt); }
            eu[cnt] = u; ev[cnt] = v; nxt[cnt] = head[node]; head[node] = cnt++;
            return;
        }
        int m = (l + r) >>> 1;
        insert(2 * node, l, m, ql, qr, u, v);
        insert(2 * node + 1, m + 1, r, ql, qr, u, v);
    }

    static void dfs(int node, int l, int r) {
        int snap = top;
        boolean good = true;
        for (int e = head[node]; e != -1 && good; e = nxt[e]) good = addEdge(eu[e], ev[e]);
        if (!good) {
            for (int t = l; t <= r; t++) ok[t] = false;
        } else if (l == r) {
            ok[l] = true;
        } else {
            int m = (l + r) >>> 1;
            dfs(2 * node, l, m);
            dfs(2 * node + 1, m + 1, r);
        }
        rollback(snap);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        q = in.nextInt();
        head = new int[4 * q];
        Arrays.fill(head, -1);
        eu = new int[16]; ev = new int[16]; nxt = new int[16];
        ok = new boolean[q];
        HashMap<Long, Integer> since = new HashMap<>();
        for (int i = 0; i < q; i++) {
            int x = in.nextInt() - 1, y = in.nextInt() - 1;
            if (x > y) { int t = x; x = y; y = t; }
            long key = (long) x * n + y;
            Integer s = since.remove(key);
            if (s == null) since.put(key, i);
            else insert(1, 0, q - 1, s, i - 1, x, y);
        }
        for (Map.Entry<Long, Integer> en : since.entrySet())
            insert(1, 0, q - 1, en.getValue(), q - 1, (int) (en.getKey() / n), (int) (en.getKey() % n));
        p = new int[n]; sz = new int[n]; par = new int[n]; histB = new int[n]; histA = new int[n];
        for (int i = 0; i < n; i++) { p[i] = i; sz[i] = 1; }
        dfs(1, 0, q - 1);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < q; i++) sb.append(ok[i] ? "YES" : "NO").append('\n');
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
3 5
2 3
1 3
1 2
1 2
1 2
out:
YES
YES
NO
YES
NO
-->
<!-- test
in:
2 1
1 2
out:
YES
-->

### Example 3 — Size of the rectangle closure under toggles  ·  ★ 2600

- **Source:** [CF 1140F · Extending Set of Points](https://codeforces.com/problemset/problem/1140/F) — 2600
- **Difficulty:** 2600
- **Problem:** A set $S$ of lattice points; $E(S)$ is obtained by repeatedly adding the fourth corner of any axis-parallel rectangle that has the other three corners in the set. $q \le 3\cdot10^5$ queries toggle a point $(x, y)$ with $1 \le x, y \le 3\cdot10^5$; after each, print $|E(S)|$.
- **Thinking from first principles:** Simulating the closure is hopeless. Look for an invariant: the rule needs $(x_1,y_1), (x_1,y_2), (x_2,y_1)$, i.e. a path $y_2 - x_1 - y_1 - x_2$ in the bipartite graph "row $x$ — column $y$" where points are edges. So the closure is about connected components of that graph, and inside a component everything gets filled: $|E(S)| = \sum_C \#x(C)\cdot\#y(C)$ (§2). Now the problem is "maintain $\sum_C \#x\cdot\#y$ under edge insertions and deletions" — a DSU with two counters per root and a running total, made dynamic by the segment tree on time.

<details><summary>Solution</summary>

Nodes $0..X-1$ are rows, $X..2X-1$ columns; a row root starts with $(\#x, \#y) = (1, 0)$, a column root with $(0, 1)$. On a union, subtract both components' products, merge counters, add the new product; save the old total in the history so rollback is a plain assignment. Answers reach $(3\cdot10^5)^2 = 9\cdot10^{10}$, so 64-bit. Complexity $O(q\log q\log X)$.

The brute force used for stress testing applied the rectangle rule literally until nothing changed, so it checks the component formula as well as the code.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

const int X = 300000;                        // x-node i, y-node X + i

struct DSU {
    vector<int> p, sz;
    vector<ll> cx, cy;
    ll total = 0;                            // sum over components of cx * cy
    vector<tuple<int, int, ll>> hist;        // (child, parent, total before the union)
    DSU(int n) : p(n), sz(n, 1), cx(n, 0), cy(n, 0) {
        iota(p.begin(), p.end(), 0);
        for (int i = 0; i < n; i++) (i < X ? cx[i] : cy[i]) = 1;
    }
    int find(int x) const { while (p[x] != x) x = p[x]; return x; }
    void unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return;
        if (sz[a] < sz[b]) swap(a, b);
        hist.emplace_back(b, a, total);
        total -= cx[a] * cy[a] + cx[b] * cy[b];
        p[b] = a; sz[a] += sz[b]; cx[a] += cx[b]; cy[a] += cy[b];
        total += cx[a] * cy[a];
    }
    int snapshot() const { return hist.size(); }
    void rollback(int snap) {
        while ((int)hist.size() > snap) {
            auto [b, a, old] = hist.back(); hist.pop_back();
            cx[a] -= cx[b]; cy[a] -= cy[b]; sz[a] -= sz[b]; p[b] = b; total = old;
        }
    }
};

int q;
vector<vector<pair<int, int>>> seg;
vector<ll> ans;

void insert(int node, int l, int r, int ql, int qr, pair<int, int> e) {
    if (qr < l || r < ql) return;
    if (ql <= l && r <= qr) { seg[node].push_back(e); return; }
    int m = (l + r) / 2;
    insert(2 * node, l, m, ql, qr, e);
    insert(2 * node + 1, m + 1, r, ql, qr, e);
}

void dfs(int node, int l, int r, DSU& d) {
    int snap = d.snapshot();
    for (auto [x, y] : seg[node]) d.unite(x, X + y);    // point (x, y) = edge x -- y
    if (l == r) ans[l] = d.total;
    else {
        int m = (l + r) / 2;
        dfs(2 * node, l, m, d);
        dfs(2 * node + 1, m + 1, r, d);
    }
    d.rollback(snap);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    cin >> q;
    seg.assign(4 * q, {});
    ans.assign(q, 0);
    map<pair<int, int>, int> since;
    for (int i = 0; i < q; i++) {
        int x, y;
        cin >> x >> y;
        x--; y--;
        auto it = since.find({x, y});
        if (it == since.end()) since[{x, y}] = i;
        else { insert(1, 0, q - 1, it->second, i - 1, {x, y}); since.erase(it); }
    }
    for (auto& [e, s] : since) insert(1, 0, q - 1, s, q - 1, e);
    DSU d(2 * X);
    dfs(1, 0, q - 1, d);
    for (int i = 0; i < q; i++) cout << ans[i] << (i + 1 < q ? ' ' : '\n');
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static final int X = 300000;
    static int[] p, sz, histB, histA;
    static long[] cx, cy, histT;
    static long total = 0;
    static int top = 0;

    static int find(int x) { while (p[x] != x) x = p[x]; return x; }
    static void unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        histB[top] = b; histA[top] = a; histT[top] = total; top++;
        total -= cx[a] * cy[a] + cx[b] * cy[b];
        p[b] = a; sz[a] += sz[b]; cx[a] += cx[b]; cy[a] += cy[b];
        total += cx[a] * cy[a];
    }
    static void rollback(int snap) {
        while (top > snap) {
            top--;
            int b = histB[top], a = histA[top];
            cx[a] -= cx[b]; cy[a] -= cy[b]; sz[a] -= sz[b]; p[b] = b; total = histT[top];
        }
    }

    static int q, cnt = 0;
    static int[] head, nxt, ex, ey;
    static long[] ans;

    static void insert(int node, int l, int r, int ql, int qr, int x, int y) {
        if (qr < l || r < ql) return;
        if (ql <= l && r <= qr) {
            if (cnt == ex.length) { ex = Arrays.copyOf(ex, 2 * cnt); ey = Arrays.copyOf(ey, 2 * cnt); nxt = Arrays.copyOf(nxt, 2 * cnt); }
            ex[cnt] = x; ey[cnt] = y; nxt[cnt] = head[node]; head[node] = cnt++;
            return;
        }
        int m = (l + r) >>> 1;
        insert(2 * node, l, m, ql, qr, x, y);
        insert(2 * node + 1, m + 1, r, ql, qr, x, y);
    }

    static void dfs(int node, int l, int r) {
        int snap = top;
        for (int e = head[node]; e != -1; e = nxt[e]) unite(ex[e], X + ey[e]);
        if (l == r) ans[l] = total;
        else {
            int m = (l + r) >>> 1;
            dfs(2 * node, l, m);
            dfs(2 * node + 1, m + 1, r);
        }
        rollback(snap);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        q = in.nextInt();
        head = new int[4 * q];
        Arrays.fill(head, -1);
        ex = new int[16]; ey = new int[16]; nxt = new int[16];
        ans = new long[q];
        HashMap<Long, Integer> since = new HashMap<>();
        for (int i = 0; i < q; i++) {
            int x = in.nextInt() - 1, y = in.nextInt() - 1;
            long key = (long) x * X + y;
            Integer s = since.remove(key);
            if (s == null) since.put(key, i);
            else insert(1, 0, q - 1, s, i - 1, x, y);
        }
        for (Map.Entry<Long, Integer> en : since.entrySet())
            insert(1, 0, q - 1, en.getValue(), q - 1, (int) (en.getKey() / X), (int) (en.getKey() % X));
        int n = 2 * X;
        p = new int[n]; sz = new int[n]; cx = new long[n]; cy = new long[n];
        histB = new int[n]; histA = new int[n]; histT = new long[n];
        for (int i = 0; i < n; i++) { p[i] = i; sz[i] = 1; if (i < X) cx[i] = 1; else cy[i] = 1; }
        dfs(1, 0, q - 1);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < q; i++) sb.append(ans[i]).append(i + 1 < q ? ' ' : '\n');
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
7
1 1
1 2
2 1
2 2
1 2
1 3
2 1
out:
1 2 4 4 4 6 3
-->
<!-- test
in:
1
5 5
out:
1
-->

### Example 4 — Which single edge removal makes the graph bipartite?  ·  ★ 2900

- **Source:** [CF 19E · Fairy](https://codeforces.com/problemset/problem/19/E) — 2900
- **Difficulty:** 2900
- **Problem:** A graph with $n, m \le 10^4$. Find all edges whose removal leaves a bipartite graph; print their count and their indices in increasing order.
- **Thinking from first principles:** The classical solution works on a DFS tree, counting for every tree edge how many "odd" and "even" fundamental cycles cover it — elegant, but easy to get wrong. The mechanical route: "for each $i$, the property of the set without $i$" is the leave-one-out pattern (§1.6). With a parity DSU every check is an insertion, and an odd cycle found while inserting the *outside* edges prunes the whole range at once.

<details><summary>Solution</summary>

`solve(l, r)` keeps the invariant "all edges outside $[l,r]$ are inserted and bipartite". Insert $[\text{mid}+1, r]$; if no conflict, recurse left; roll back; insert $[l, \text{mid}]$; if no conflict, recurse right; roll back. A leaf $l$ is an answer. Leaves are reached left to right, so the output is already sorted. Each edge is inserted $O(\log m)$ times: $O(m\log m\log n)$. Self-loops are handled for free (a loop is an odd cycle: $c(u) = c(u)$).

```cpp
#include <bits/stdc++.h>
using namespace std;

struct ParityDSU {
    vector<int> p, sz, par;
    vector<pair<int, int>> hist;
    ParityDSU(int n) : p(n), sz(n, 1), par(n, 0) { iota(p.begin(), p.end(), 0); }
    pair<int, int> find(int x) const {
        int c = 0;
        while (p[x] != x) { c ^= par[x]; x = p[x]; }
        return {x, c};
    }
    bool addEdge(int u, int v) {
        auto [a, ca] = find(u);
        auto [b, cb] = find(v);
        if (a == b) return ca != cb;
        if (sz[a] < sz[b]) swap(a, b);
        p[b] = a; sz[a] += sz[b]; par[b] = ca ^ cb ^ 1;
        hist.push_back({b, a});
        return true;
    }
    int snapshot() const { return hist.size(); }
    void rollback(int snap) {
        while ((int)hist.size() > snap) {
            auto [b, a] = hist.back(); hist.pop_back();
            p[b] = b; par[b] = 0; sz[a] -= sz[b];
        }
    }
};

vector<pair<int, int>> E;
vector<int> res;

// Invariant: every edge outside [l, r] is in the DSU and they form a bipartite graph.
void solve(int l, int r, ParityDSU& d) {
    if (l == r) { res.push_back(l + 1); return; }
    int m = (l + r) / 2, snap = d.snapshot();
    bool good = true;
    for (int i = m + 1; i <= r && good; i++) good = d.addEdge(E[i].first, E[i].second);
    if (good) solve(l, m, d);                    // left candidates: right half is now "outside"
    d.rollback(snap);
    good = true;
    for (int i = l; i <= m && good; i++) good = d.addEdge(E[i].first, E[i].second);
    if (good) solve(m + 1, r, d);
    d.rollback(snap);
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    E.resize(m);
    for (auto& [u, v] : E) { cin >> u >> v; u--; v--; }
    ParityDSU d(n);
    if (m > 0) solve(0, m - 1, d);
    cout << res.size() << '\n';
    for (size_t i = 0; i < res.size(); i++) cout << res[i] << (i + 1 < res.size() ? ' ' : '\n');
    if (res.empty()) cout << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int[] p, sz, par, histB, histA, eu, ev;
    static int top = 0, rc = 0;
    static int[] res;

    static int find(int x) { while (p[x] != x) x = p[x]; return x; }
    static int colour(int x) { int c = 0; while (p[x] != x) { c ^= par[x]; x = p[x]; } return c; }
    static boolean addEdge(int u, int v) {
        int a = find(u), b = find(v), ca = colour(u), cb = colour(v);
        if (a == b) return ca != cb;
        if (sz[a] < sz[b]) { int t = a; a = b; b = t; }
        p[b] = a; sz[a] += sz[b]; par[b] = ca ^ cb ^ 1;
        histB[top] = b; histA[top] = a; top++;
        return true;
    }
    static void rollback(int snap) {
        while (top > snap) { top--; int b = histB[top], a = histA[top]; p[b] = b; par[b] = 0; sz[a] -= sz[b]; }
    }

    static void solve(int l, int r) {
        if (l == r) { res[rc++] = l + 1; return; }
        int m = (l + r) >>> 1, snap = top;
        boolean good = true;
        for (int i = m + 1; i <= r && good; i++) good = addEdge(eu[i], ev[i]);
        if (good) solve(l, m);
        rollback(snap);
        good = true;
        for (int i = l; i <= m && good; i++) good = addEdge(eu[i], ev[i]);
        if (good) solve(m + 1, r);
        rollback(snap);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        eu = new int[m]; ev = new int[m]; res = new int[m];
        for (int i = 0; i < m; i++) { eu[i] = in.nextInt() - 1; ev[i] = in.nextInt() - 1; }
        p = new int[n]; sz = new int[n]; par = new int[n]; histB = new int[n]; histA = new int[n];
        for (int i = 0; i < n; i++) { p[i] = i; sz[i] = 1; }
        if (m > 0) solve(0, m - 1);
        StringBuilder sb = new StringBuilder();
        sb.append(rc).append('\n');
        for (int i = 0; i < rc; i++) sb.append(res[i]).append(i + 1 < rc ? ' ' : '\n');
        if (rc == 0) sb.append('\n');
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
4 4
1 2
1 3
2 4
3 4
out:
4
1 2 3 4
-->
<!-- test
in:
4 5
1 2
2 3
3 4
4 1
1 3
out:
1
5
-->
<!-- test
in:
3 0
out:
0
-->
<!-- test
in:
3 3
1 2
2 3
3 1
out:
3
1 2 3
-->

Every example was stress-tested against recomputing the answer from scratch after each operation (BFS components, BFS 2-colouring, literal closure, delete-each-edge-and-check) on 250–400 random small cases, plus Java-vs-C++ comparison.

## 6. Tricks, pitfalls and things to remember

1. **No path compression.** It is the classic bug: everything works on samples (tiny depth) and then produces wrong answers after rollback, or TLE. Union by size, worst-case $O(\log n)$ `find`.
2. **Rollback to a snapshot, not "undo $k$ times".** Store `snap = history.size()` on entry and pop down to it on exit; failed unions push nothing, so counting your own calls goes wrong.
3. **Lifetime off-by-one.** Added at $s$, removed at $e$: alive on $[s, e-1]$. Write it once, test with an add immediately followed by a query.
4. **Multi-edges and toggles.** Keep a stack of start times per unordered pair (normalise $u < v$); a single `map<pair,int>` silently merges two copies of the same edge.
5. **Only query leaves matter.** If memory is tight, build the segment tree over *query indices* only and map each lifetime to the range of queries it covers.
6. **Memory layout.** `vector<vector<pair<int,int>>>` with $4q$ inner vectors is fine in C++; in Java use intrusive linked lists (`head[node]`, `nxt[]`) instead of `ArrayList<int[]>` per node to avoid millions of small objects.
7. **Prune.** When a node's edges already decide every leaf below (odd cycle → all NO), stop. It is often the difference between 4 s and 1 s.
8. **Recursion depth** is $O(\log q)$, safe in both languages; the DSU `find` loop is iterative.
9. **Store what you need to restore.** For running totals, push the old total into the history and assign it back; recomputing the inverse operation invites sign bugs.
10. **Arrays of size $2X$.** In bipartite "row/column" models, the DSU needs both sides; forgetting the offset merges row 5 with column 5.
11. **Do not mix with path-compressed DSU code from your template.** Keep a separate `RollbackDSU` in your library.

## 7. Going further (toward 2400–2600+)

- **XOR shortest paths over time** ([CF 938G · Shortest Path Queries](https://codeforces.com/problemset/problem/938/G) — 2900): DSU storing XOR distance to the root, plus a linear basis of cycle values ([XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)). The basis is copied per DFS depth (it has only 30 vectors), which makes "undo" trivial.
- **Lifetimes decided on the fly** ([CF 576E · Painting Edges](https://codeforces.com/problemset/problem/576/E) — 3300, [CF 1217F · Forced Online Queries Problem](https://codeforces.com/problemset/problem/1217/F) — 2600): the end of an interval is known, but *what* is alive on it depends on answers at earlier leaves. Because the DFS visits leaves left to right, you can decide at leaf $t$ what to insert on $[t+1, \text{next}_t - 1]$ before that range is visited.
- **Knapsack / bitset on time:** each item alive on an interval, answer "is sum $s$ reachable" at each time; copy the bitset per depth ([bitset optimisation](05-bitset-optimization.md); [CF 981E · Addition on Segments](https://codeforces.com/problemset/problem/981/E) — 2200 uses the same segment-tree-over-positions idea).
- **Monotone two-pointer with rollback** ([CF 1386C · Joker](https://codeforces.com/problemset/problem/1386/C) — 2800): for each $l$ the minimal valid $r$ is monotone; D&C on $l$ with rollback computes all of them in $O(m\log m\log n)$.
- **Online alternatives:** [link-cut trees](03-link-cut-trees.md) maintain a maximum spanning forest keyed by deletion time, which answers connectivity online when each edge's deletion time is known at insertion; true online dynamic connectivity (Holm–de Lichtenberg–Thorup) is 🧊.
- **Persistent DSU** (DSU over a persistent array) answers queries on an arbitrary *version tree* online at $O(\log^2 n)$ per operation — see [persistent data structures](../08-Data-Structures/08-persistent-data-structures.md).

## 8. Practice ladder

2200–2400
- [ ] [CF 981E · Addition on Segments](https://codeforces.com/problemset/problem/981/E) — 2200 — segment tree over positions + bitset (the same DFS idea)
- [ ] [CSES 2133 · Dynamic Connectivity](https://cses.fi/problemset/task/2133) — Example 1 with a different format
- [ ] [CF 891C · Envy](https://codeforces.com/problemset/problem/891/C) — 2300 — rollback DSU per query group, by weight
- [ ] [CF 1681F · Unique Occurrences](https://codeforces.com/problemset/problem/1681/F) — 2300 — segment tree over colours, rollback DSU

2500–2700
- [ ] [CF 813F · Bipartite Checking](https://codeforces.com/problemset/problem/813/F) — 2500 — Example 2
- [ ] [CF 1423H · Virus](https://codeforces.com/problemset/problem/1423/H) — 2500 — lifetimes of $k$ days
- [ ] [CF 1140F · Extending Set of Points](https://codeforces.com/problemset/problem/1140/F) — 2600 — Example 3
- [ ] [CF 1217F · Forced Online Queries Problem](https://codeforces.com/problemset/problem/1217/F) — 2600 — candidate edges, decide at the leaf

2800+
- [ ] [CF 1386C · Joker](https://codeforces.com/problemset/problem/1386/C) — 2800 — monotone pointer, D&C + rollback
- [ ] [CF 19E · Fairy](https://codeforces.com/problemset/problem/19/E) — 2900 — Example 4
- [ ] [CF 938G · Shortest Path Queries](https://codeforces.com/problemset/problem/938/G) — 2900 — XOR distances + linear basis on time
- [ ] [CF 603E · Pastoral Oddities](https://codeforces.com/problemset/problem/603/E) — 3000 — D&C on answers with rollback
- [ ] [CF 576E · Painting Edges](https://codeforces.com/problemset/problem/576/E) — 3300 — 50 parity DSUs, lifetimes decided on the fly

## 9. LeetCode / FAANG cross-reference

Rare in interviews: no LeetCode problem needs deletions in a DSU, and the full technique is far beyond interview length. Two problems use the "tentative union, then undo" idea in a simple form:

- [LC 2076 · Process Restricted Friend Requests](https://leetcode.com/problems/process-restricted-friend-requests/) — Hard — test a union against restrictions before committing (a one-step rollback).
- [LC 1489 · Find Critical and Pseudo-Critical Edges in Minimum Spanning Tree](https://leetcode.com/problems/find-critical-and-pseudo-critical-edges-in-minimum-spanning-tree/) — Hard — leave-one-out over edges; the constraints allow rerunning Kruskal, but D&C with rollback is the scalable version.
- [LC 1579 · Remove Max Number of Edges to Keep Graph Fully Traversable](https://leetcode.com/problems/remove-max-number-of-edges-to-keep-graph-fully-traversable/) — Hard — two DSUs sharing a prefix of unions (copying a DSU is the poor man's rollback).

## 10. Self-check

1. Why does union by size bound the depth by $\log_2 n$?
2. Why is path compression incompatible with rollback, both for correctness of the undo log and for the complexity guarantee?
3. Prove that the edges applied on the root-to-leaf path to leaf $t$ are exactly the edges alive at $t$.
4. An edge is added by operation 4 and removed by operation 9. Which leaves must see it?
5. How do you detect an odd cycle when inserting $(u, v)$ into a parity DSU, and what parity do you store when merging?
6. What is the total complexity of segment tree on time with a rollback DSU, and where does each log come from?
7. Describe the leave-one-out recursion and its invariant.
8. Give an example of a problem where this technique does not apply even though there are deletions.

<details><summary>Answers</summary>

1. A node's depth grows only when its tree is attached under a root of a tree at least as large, which at least doubles the size of its tree.
2. Compression changes an unbounded number of pointers per `find` (the log could not be $O(1)$ per union), and its amortised bound relies on never revisiting old states; rollback lets an adversary repeat the expensive operation.
3. The canonical nodes of $[s, e]$ partition the interval; leaf $t$ has exactly one of them as an ancestor iff $t \in [s,e]$.
4. The states after operations $4, \dots, 8$: lifetime $[4, 8]$.
5. With roots equal, an odd cycle iff $c(u) = c(v)$. With roots different, attach $r_v$ under $r_u$ with parity $c(u)\oplus c(v)\oplus 1$.
6. $O(q\log q\log n)$: $\log q$ canonical nodes per lifetime, $\log n$ per `find`.
7. `solve(l, r)` assumes all elements outside $[l, r]$ are inserted; it inserts one half, recurses into the other, and rolls back. A leaf has everything except itself.
8. Forced-online queries (each query depends on the previous answer), or a structure that has no cheap undo (e.g. a path-compressed DSU with a requirement of near-constant time, or a sorted container with amortised rebalancing).

</details>
