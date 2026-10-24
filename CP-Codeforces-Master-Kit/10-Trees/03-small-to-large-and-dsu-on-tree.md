# Small-to-large merging and DSU on tree (sack)

> **Band:** 🟣 1900 – 🟠 2400 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [tree basics and Euler tour](01-tree-basics-diameter-center-euler-tour.md), [DSU (union by size)](../08-Data-Structures/06-dsu-and-variants.md), [ordered sets and hash maps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md), [tree DP](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md)
> **You can say you know this when:** you can prove the $O(n\log n)$ bound from "each element moves $O(\log n)$ times", and write both the container-merging version and the array-based sack (no recursion) for any "statistic of a subtree" query in under 15 minutes.

## 1. First principles — why this works

### 1.1 The problem class

For every vertex $v$ (or for queries attached to vertices) we want a statistic of the **multiset of values in subtree($v$)** that is *not* decomposable into a sum over children: the number of distinct colours, the most frequent colour, how many colours occur at least $k$ times, whether the letters at depth $h$ can form a palindrome, whether two vertices in the subtree have prefix-XORs that combine to 0 …

The naive solution rebuilds the multiset for every vertex: cost $\sum_v sz(v) = \sum_v (\mathrm{depth}(v)+1)$, which is $\Theta(n^2)$ on a path. The waste is obvious once stated: the parent recomputes from scratch what its children already built. The child's structure *is* most of the parent's structure — so reuse it.

### 1.2 Small-to-large: merge the smaller container into the larger

Keep one container (set / map / vector) per vertex. To build $v$'s container, take its children's containers and **insert every element of the smaller one into the larger one**, then keep the larger one (swap pointers, $O(1)$).

**Lemma.** Every element is moved $O(\log n)$ times, so the total number of insertions is $O(n \log n)$.

*Proof.* When an element moves, it moves out of a container of size $s$ into one of size $\ge s$; the merged container has size $\ge 2s$. So the size of the container holding a fixed element at least doubles each time that element moves, and it never exceeds $n$: at most $\log_2 n$ moves. $\blacksquare$

With `std::set`/`TreeMap` each insertion is $O(\log n)$, giving $O(n \log^2 n)$; with hash maps, expected $O(n\log n)$. This is exactly the argument behind [DSU union by size](../08-Data-Structures/06-dsu-and-variants.md), and it works far beyond trees: any process that repeatedly merges groups and pays the size of the smaller one costs $O(n\log n)$ in total.

Two implementation notes that matter:

- **Swap, don't copy.** `swap(S[v], S[c])` on `std::set`/`std::map` is $O(1)$ (pointer swap); in Java swap the references in the array. Copying the big container destroys the bound.
- **Answer before you donate.** If the container of $v$ is later merged into (or swapped into) its parent, read $v$'s answer first.

### 1.3 DSU on tree ("sack"): one global array, keep the heavy child

Containers with logarithmic operations are sometimes too slow ($n = 5\cdot10^5$) or the statistic is easier to maintain on a plain counting array (`cnt[colour]`, `mask[depth]`). The sack technique (often called "DSU on tree", though no DSU is involved; it is also attributed in the community to a CF blog by Arpa) uses **one** global array and the heavy child:

- the **heavy child** $h(v)$ is the child with the largest subtree; other children are light;
- solve the light children first, *each time clearing* the global array afterwards;
- solve the heavy child last and **keep** its contents;
- then add $v$ and every vertex of the light subtrees, and answer $v$.

```text
solve(v, keep):
    for light child c: solve(c, keep = false)     # array is empty afterwards
    if heavy child h:  solve(h, keep = true)      # array = subtree(h)
    add(v); for light child c: add every vertex of subtree(c)
    answer queries at v                           # array = subtree(v)
    if not keep: remove every vertex of subtree(v)   # array empty again
```

**Lemma.** Every vertex is added (and removed) $O(\log n)$ times.

*Proof.* A vertex $x$ is added once when it is processed itself, and once more each time one of its ancestors $a$ adds the light subtree containing $x$, i.e. once per **light edge** on the path from $x$ to the root. Going up a light edge from $c$ to $p$, $sz(p) \ge 2\,sz(c)$ (the heavy sibling is at least as big as $c$). Sizes are at most $n$, so there are at most $\log_2 n$ light edges on any root path. Removals mirror additions. $\blacksquare$

So the total work is $O(n\log n)$ array operations — no extra log. The same light-edge bound powers [heavy–light decomposition](04-heavy-light-decomposition.md).

### 1.4 The sack without recursion

Recursion depth is the tree height, fatal in Java on a path. A small observation removes the recursion entirely. Take a **preorder in which the heavy child is visited first**. Then for every vertex $v$ at position $i$:

- the heavy subtree occupies positions $[i+1,\; i + sz(h)]$, and
- $v$ itself plus all light subtrees occupy $\{i\} \cup [\,i + 1 + sz(h),\; i + sz(v))$ — one vertex and one contiguous range.

Now **process positions from $n-1$ down to $0$**. Heavy paths are contiguous runs of positions, and all light subtrees hanging off a heavy path have larger positions than its bottom vertex, so the reversed preorder replays exactly the recursive sack's schedule:

```text
for i = n-1 downto 0:
    v = order[i]
    add(v); add every order[j] for j in [i + 1 + sz(h(v)), i + sz(v))
    answer queries at v                 # the array holds exactly subtree(v)
    if v is the root or a light child:  # top of a heavy path -> clear
        remove every order[j] for j in [i, i + sz(v))
```

Why the array holds exactly subtree($v$): if $v$ has a heavy child $h$, $h$ was processed at position $i+1$ just before, and it is not a path top, so it was not cleared — the array is subtree($h$), and we add the rest. If $v$ is a leaf, the vertex processed before it (position $i+1$) is a light child of some ancestor — a path top — so the array was just cleared. Both versions cost $O(n \log n)$.

### 1.5 Which one to use

| Situation | Use |
|---|---|
| statistic lives naturally in a map/set; $n \le 2\cdot10^5$; you need the container itself for the parent (e.g. greedy decisions that delete it) | small-to-large containers |
| statistic fits a counting array indexed by value/depth; $n$ up to $5\cdot10^5$–$10^6$; offline queries | sack |
| statistic indexed by **depth** with arrays whose length is the subtree height | long-path decomposition (§7) — $O(n)$ |
| the answer is a range query on the Euler array (count of distinct values in a range) | Euler tour + offline BIT / [Mo's algorithm](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md) |

## 2. Formulas, definitions and identities

| Formula | Meaning / proof sketch |
|---|---|
| naive cost $\sum_v sz(v) = \sum_v (\mathrm{dep}(v) + 1)$ | $\Theta(n^2)$ on a path |
| moves per element $\le \lfloor\log_2 n\rfloor$ | container size doubles per move |
| small-to-large total: $O(n\log n)$ moves; $\times O(\log n)$ for ordered containers | lemma §1.2 |
| heavy child $h(v) = \arg\max_{c} sz(c)$ | ties arbitrary |
| light edge $(p, c)$: $sz(c) \le sz(p)/2$; $\le \log_2 n$ light edges on a root path | a heavy sibling is at least as big |
| sack: additions per vertex $\le 1 + \#\text{light edges above it}$ | §1.3 |
| heavy-first preorder: heavy subtree $= [i+1, i+sz(h)]$, rest of subtree $= \{i\}\cup[i+1+sz(h), i+sz(v))$ | contiguous ranges |
| general merging lemma: merging groups at cost $\min(\lvert A\rvert,\lvert B\rvert)$ totals $O(n\log n)$ | each element is on the smaller side $\le \log_2 n$ times |

**Complexities.** Small-to-large with `set`/`map`: $O(n\log^2 n)$ time, $O(n)$ memory at any moment (each element lives in one container). With hash maps: expected $O(n\log n)$. Sack: $O(n\log n)$ time, $O(n + \text{value range})$ memory. Answering $q$ offline queries attached to vertices adds $O(q)$.

## 3. Implementation (C++ and Java)

Both programs solve the same task so they cross-check each other. Input: `n`, colours $c_1..c_n$ (any integers up to $10^9$), $n-1$ edges; root 1. Output line 1: the number of distinct colours in each subtree; line 2: the largest multiplicity of a colour in each subtree.

### 3.1 Small-to-large with maps (reverse preorder, no recursion)

Process vertices in reverse preorder: by the time we reach $v$, all its children have already been merged into it, so its map is complete; read the answers, then donate the map to the parent.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> c(n + 1);
    for (int v = 1; v <= n; v++) cin >> c[v];
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<int> par(n + 1, 0), order, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    vector<map<int, int>> mp(n + 1);
    vector<int> best(n + 1, 1), distinct(n + 1), mostFreq(n + 1);   // best[v] = max count inside mp[v]
    for (int v = 1; v <= n; v++) mp[v][c[v]] = 1;
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i];
        distinct[v] = mp[v].size(); mostFreq[v] = best[v];           // complete: all children merged
        if (i == 0) break;
        int p = par[v];
        if (mp[v].size() > mp[p].size()) { swap(mp[v], mp[p]); swap(best[v], best[p]); }   // O(1)
        for (auto [col, k] : mp[v]) { int& t = mp[p][col]; t += k; best[p] = max(best[p], t); }
        map<int, int>().swap(mp[v]);                                   // free memory
    }
    for (int v = 1; v <= n; v++) cout << distinct[v] << (v == n ? '\n' : ' ');
    for (int v = 1; v <= n; v++) cout << mostFreq[v] << (v == n ? '\n' : ' ');
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
        int[] c = new int[n + 1];
        for (int v = 1; v <= n; v++) c[v] = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        @SuppressWarnings("unchecked")
        HashMap<Integer, Integer>[] mp = new HashMap[n + 1];
        int[] best = new int[n + 1], distinct = new int[n + 1], mostFreq = new int[n + 1];
        for (int v = 1; v <= n; v++) { mp[v] = new HashMap<>(); mp[v].put(c[v], 1); best[v] = 1; }
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i];
            distinct[v] = mp[v].size(); mostFreq[v] = best[v];
            if (i == 0) break;
            int p = par[v];
            if (mp[v].size() > mp[p].size()) {
                HashMap<Integer, Integer> t = mp[v]; mp[v] = mp[p]; mp[p] = t;
                int tb = best[v]; best[v] = best[p]; best[p] = tb;
            }
            HashMap<Integer, Integer> big = mp[p];
            for (Map.Entry<Integer, Integer> e : mp[v].entrySet()) {
                int t = big.merge(e.getKey(), e.getValue(), Integer::sum);
                if (t > best[p]) best[p] = t;
            }
            mp[v] = null;                                              // let the GC take it
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(distinct[v]).append(v == n ? '\n' : ' ');
        for (int v = 1; v <= n; v++) sb.append(mostFreq[v]).append(v == n ? '\n' : ' ');
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
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

Test 1: tree $1$–$2$, $1$–$3$, $3$–$4$, $3$–$5$ with colours $2, 3, 2, 2, 1$. Subtree of 3 is $\{2,2,1\}$: 2 distinct, max multiplicity 2.

<!-- test
in:
5
2 3 2 2 1
1 2
1 3
3 4
3 5
out:
3 1 2 1 1
3 1 2 1 1
-->
<!-- test
in:
1
1000000000
out:
1
1
-->
<!-- test
in:
6
7 7 7 5 5 7
1 2
2 3
3 4
4 5
5 6
out:
2 2 2 2 2 1
4 3 2 2 1 1
-->

### 3.2 Sack: heavy-first preorder, processed backwards

Same input and output. Colours are compressed to $0..n-1$ so that a counting array works.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> c(n + 1);
    for (int v = 1; v <= n; v++) cin >> c[v];
    vector<int> vals(c.begin() + 1, c.end());
    sort(vals.begin(), vals.end()); vals.erase(unique(vals.begin(), vals.end()), vals.end());
    for (int v = 1; v <= n; v++) c[v] = lower_bound(vals.begin(), vals.end(), c[v]) - vals.begin();
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    // pass 1: parents and sizes; heavy child = largest child subtree
    vector<int> par(n + 1, 0), sz(n + 1, 1), heavy(n + 1, 0), ord, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); ord.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) {
        int v = ord[i], p = par[v];
        sz[p] += sz[v];
        if (!heavy[p] || sz[v] > sz[heavy[p]]) heavy[p] = v;
    }
    // pass 2: preorder with the heavy child visited right after its parent
    vector<int> order; st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v] && u != heavy[v]) st.push_back(u);
        if (heavy[v]) st.push_back(heavy[v]);                       // pushed last -> popped first
    }
    vector<int> cnt(n, 0), distinct(n + 1), mostFreq(n + 1);
    int curDistinct = 0, curMax = 0;
    auto add = [&](int x) { if (cnt[c[x]]++ == 0) curDistinct++; curMax = max(curMax, cnt[c[x]]); };
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i], h = heavy[v];
        add(v);
        for (int j = i + 1 + (h ? sz[h] : 0); j < i + sz[v]; j++) add(order[j]);   // light subtrees
        distinct[v] = curDistinct; mostFreq[v] = curMax;
        if (v == 1 || heavy[par[v]] != v) {                              // top of a heavy path: clear
            for (int j = i; j < i + sz[v]; j++) cnt[c[order[j]]] = 0;
            curDistinct = 0; curMax = 0;
        }
    }
    for (int v = 1; v <= n; v++) cout << distinct[v] << (v == n ? '\n' : ' ');
    for (int v = 1; v <= n; v++) cout << mostFreq[v] << (v == n ? '\n' : ' ');
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
        int[] c = new int[n + 1];
        long[] key = new long[n];
        for (int v = 1; v <= n; v++) { c[v] = in.nextInt(); key[v - 1] = ((long) c[v] << 20) | v; }
        Random rnd = new Random(7);
        for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = key[i]; key[i] = key[j]; key[j] = t; }
        Arrays.sort(key);                                   // shuffled long[]: compress colours safely
        for (int i = 0, id = -1; i < n; i++) {
            if (i == 0 || (key[i] >> 20) != (key[i - 1] >> 20)) id++;
            c[(int) (key[i] & ((1 << 20) - 1))] = id;
        }
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], sz = new int[n + 1], heavy = new int[n + 1], ord = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; ord[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) {
            int v = ord[i], p = par[v];
            sz[p] += sz[v];
            if (heavy[p] == 0 || sz[v] > sz[heavy[p]]) heavy[p] = v;
        }
        int[] order = new int[n];
        top = 0; cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v] && adj[j] != heavy[v]) st[top++] = adj[j];
            if (heavy[v] != 0) st[top++] = heavy[v];
        }
        int[] num = new int[n], distinct = new int[n + 1], mostFreq = new int[n + 1];
        int curDistinct = 0, curMax = 0;
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i], h = heavy[v];
            int from = i + 1 + (h != 0 ? sz[h] : 0);
            for (int j = from - 1; j < i + sz[v]; j++) {
                int x = j == from - 1 ? v : order[j];           // first v itself, then the light range
                if (num[c[x]]++ == 0) curDistinct++;
                if (num[c[x]] > curMax) curMax = num[c[x]];
            }
            distinct[v] = curDistinct; mostFreq[v] = curMax;
            if (v == 1 || heavy[par[v]] != v) {
                for (int j = i; j < i + sz[v]; j++) num[c[order[j]]] = 0;
                curDistinct = 0; curMax = 0;
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(distinct[v]).append(v == n ? '\n' : ' ');
        for (int v = 1; v <= n; v++) sb.append(mostFreq[v]).append(v == n ? '\n' : ' ');
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
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
5
2 3 2 2 1
1 2
1 3
3 4
3 5
out:
3 1 2 1 1
3 1 2 1 1
-->
<!-- test
in:
1
1000000000
out:
1
1
-->
<!-- test
in:
6
7 7 7 5 5 7
1 2
2 3
3 4
4 5
5 6
out:
2 2 2 2 2 1
4 3 2 2 1 1
-->

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "for every vertex, count distinct / most frequent / colours appearing $\ge k$ times in its subtree" | sack (array) or small-to-large (map) |
| queries "(v, something)" about the subtree of $v$, offline allowed | attach queries to $v$, answer when the sack holds subtree($v$) |
| "for each depth below $v$" / "$k$-th level descendants of $v$" | sack with arrays indexed by depth, or long-path decomposition |
| a greedy that **discards** a whole subtree's information when a condition fires | small-to-large containers (you need to clear/keep them) |
| "merge sets bottom-up and the sizes are unbalanced" | swap-to-larger: $O(n \log n)$ moves |
| statistic is a *sum* or *min* | not this — plain subtree DP or Euler tour + Fenwick |
| one query vertex, many vertices to aggregate from, values small | the counting array of the sack beats `map` by a big constant |

Often confused with: [centroid decomposition](05-centroid-decomposition.md) (paths through a vertex, not subtrees), [Mo's algorithm on the Euler tour](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md) (also offline subtree queries, $O(n\sqrt n)$ — use when the statistic needs removal of single elements).

## 5. Worked examples (graded)

### Example 1 — Distinct Colors · ★ ≈1700 (est.)

- **Source:** [CSES 1139 · Distinct Colors](https://cses.fi/problemset/task/1139)
- **Difficulty:** ≈1700 (est.)
- **Problem:** rooted tree (root 1), $n \le 2\cdot10^5$, colours up to $10^9$; for each vertex print the number of distinct colours in its subtree.
- **Thinking from first principles:** distinct counts do not add over children (two children can share a colour), so no simple DP. A set per vertex built from the children is correct but quadratic if built naively; merge smaller into larger and it is $O(n\log^2 n)$. The answer is just the set size — read it before the set is given away.

<details><summary>Solution</summary>

Reverse preorder, one set per vertex, swap-to-larger. $O(n\log^2 n)$ with `std::set`; Java's `HashSet` is expected $O(n\log n)$ operations (boxing makes it slower but well within limits for $2\cdot10^5$).

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<set<int>> S(n + 1);
    for (int v = 1; v <= n; v++) { int x; cin >> x; S[v].insert(x); }
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<int> par(n + 1, 0), order, st = {1}, ans(n + 1);
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i];
        ans[v] = S[v].size();
        if (i == 0) break;
        int p = par[v];
        if (S[v].size() > S[p].size()) swap(S[v], S[p]);
        S[p].insert(S[v].begin(), S[v].end());
        set<int>().swap(S[v]);
    }
    for (int v = 1; v <= n; v++) cout << ans[v] << (v == n ? '\n' : ' ');
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
        @SuppressWarnings("unchecked")
        HashSet<Integer>[] S = new HashSet[n + 1];
        for (int v = 1; v <= n; v++) { S[v] = new HashSet<>(); S[v].add(in.nextInt()); }
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], order = new int[n], st = new int[n], ans = new int[n + 1];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i];
            ans[v] = S[v].size();
            if (i == 0) break;
            int p = par[v];
            if (S[v].size() > S[p].size()) { HashSet<Integer> t = S[v]; S[v] = S[p]; S[p] = t; }
            S[p].addAll(S[v]);
            S[v] = null;
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(ans[v]).append(v == n ? '\n' : ' ');
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
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
5
2 3 2 2 1
1 2
1 3
3 4
3 5
out:
3 1 2 1 1
-->
<!-- test
in:
4
5 5 5 5
4 3
3 2
2 1
out:
1 1 1 1
-->

</details>

### Example 2 — Tree Requests · ★ 2200

- **Source:** [CF 570D · Tree Requests](https://codeforces.com/problemset/problem/570/D) — 2200
- **Difficulty:** 2200
- **Problem:** rooted tree on $n \le 5\cdot10^5$ vertices given by parents $p_i < i$, a lowercase letter on each vertex, and $m \le 5\cdot10^5$ queries $(v, h)$: can the letters of the vertices in subtree($v$) at depth $h$ (root has depth 1) be rearranged into a palindrome?
- **Thinking from first principles:** a multiset of letters can form a palindrome iff at most one letter has odd count — only the **parity vector**, a 26-bit mask, matters. So for a fixed subtree we need, for every depth, the XOR of letter bits: an array `mask[depth]`. That is a counting-array statistic over a subtree, with queries attached to vertices: the sack, offline. $n = 5\cdot10^5$ rules out per-vertex maps of depth → mask.

<details><summary>Solution</summary>

Group queries by vertex. Sack with `mask[dep[x]] ^= 1 << letter(x)`; XOR is its own inverse, so "add" and "remove" are the same toggle. Answer $(v,h)$: `mask[h]` has at most one bit set. Depths not present in the subtree have mask 0 (empty multiset — a palindrome). $O((n + m) + n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<int> par(n + 1, 0), dep(n + 1, 1), sz(n + 1, 1), heavy(n + 1, 0);
    vector<vector<int>> ch(n + 1);
    for (int v = 2; v <= n; v++) { cin >> par[v]; ch[par[v]].push_back(v); }
    string s; cin >> s;
    for (int v = 2; v <= n; v++) dep[v] = dep[par[v]] + 1;            // p_v < v
    for (int v = n; v >= 2; v--) {
        sz[par[v]] += sz[v];
        if (!heavy[par[v]] || sz[v] > sz[heavy[par[v]]]) heavy[par[v]] = v;
    }
    vector<int> order, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : ch[v]) if (u != heavy[v]) st.push_back(u);
        if (heavy[v]) st.push_back(heavy[v]);
    }
    vector<vector<pair<int,int>>> qs(n + 1);
    for (int i = 0; i < m; i++) { int v, h; cin >> v >> h; qs[v].push_back({h, i}); }
    vector<int> mask(n + 2, 0);
    vector<char> ans(m);
    auto toggle = [&](int x) { mask[dep[x]] ^= 1 << (s[x - 1] - 'a'); };
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i], h = heavy[v];
        toggle(v);
        for (int j = i + 1 + (h ? sz[h] : 0); j < i + sz[v]; j++) toggle(order[j]);
        for (auto [d, id] : qs[v]) { int x = d <= n ? mask[d] : 0; ans[id] = (x & (x - 1)) == 0; }
        if (v == 1 || heavy[par[v]] != v)
            for (int j = i; j < i + sz[v]; j++) toggle(order[j]);
    }
    string res;
    for (int i = 0; i < m; i++) res += ans[i] ? "Yes\n" : "No\n";
    cout << res;
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
        int[] par = new int[n + 1], dep = new int[n + 1], sz = new int[n + 1], heavy = new int[n + 1], start = new int[n + 2];
        for (int v = 2; v <= n; v++) { par[v] = in.nextInt(); start[par[v] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] ch = new int[Math.max(1, n - 1)], fill = start.clone();
        for (int v = 2; v <= n; v++) ch[fill[par[v]]++] = v;
        String s = in.next();
        int[] bit = new int[n + 1];
        for (int v = 1; v <= n; v++) bit[v] = 1 << (s.charAt(v - 1) - 'a');
        dep[1] = 1;
        for (int v = 2; v <= n; v++) dep[v] = dep[par[v]] + 1;
        Arrays.fill(sz, 1);
        for (int v = n; v >= 2; v--) {
            sz[par[v]] += sz[v];
            if (heavy[par[v]] == 0 || sz[v] > sz[heavy[par[v]]]) heavy[par[v]] = v;
        }
        int[] order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (ch[j] != heavy[v]) st[top++] = ch[j];
            if (heavy[v] != 0) st[top++] = heavy[v];
        }
        int[] qv = new int[m], qh = new int[m], qs = new int[n + 2];
        for (int i = 0; i < m; i++) { qv[i] = in.nextInt(); qh[i] = in.nextInt(); qs[qv[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) qs[v] += qs[v - 1];
        int[] qid = new int[m], qf = qs.clone();
        for (int i = 0; i < m; i++) qid[qf[qv[i]]++] = i;
        int[] mask = new int[n + 2];
        boolean[] ans = new boolean[m];
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i], h = heavy[v];
            mask[dep[v]] ^= bit[v];
            for (int j = i + 1 + (h != 0 ? sz[h] : 0); j < i + sz[v]; j++) mask[dep[order[j]]] ^= bit[order[j]];
            for (int k = qs[v]; k < qs[v + 1]; k++) {
                int id = qid[k], x = qh[id] <= n ? mask[qh[id]] : 0;
                ans[id] = (x & (x - 1)) == 0;
            }
            if (v == 1 || heavy[par[v]] != v)
                for (int j = i; j < i + sz[v]; j++) mask[dep[order[j]]] ^= bit[order[j]];
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < m; i++) sb.append(ans[i] ? "Yes\n" : "No\n");
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
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

Test 1: parents of $2..6$ are $1,1,2,2,3$, letters `abcbca`, so depth 3 holds $4{:}b$, $5{:}c$, $6{:}a$. Under 1 at depth 3: `b, c, a` → no; under 2: `b, c` → no; depth 2 under 1: `b, c` → no; under 3 at depth 3: `a` → yes; depth 2 under 2: `b` → yes; depth 4: empty → yes; vertex 4 at its own depth → yes. Test 2: two equal letters at one depth (`c, c`) → yes. Test 3: a single vertex and a too-deep $h$.

<!-- test
in:
6 7
1 1 2 2 3
abcbca
1 3
2 3
1 2
3 3
2 2
1 4
4 3
out:
No
No
No
Yes
Yes
Yes
Yes
-->
<!-- test
in:
5 3
1 1 2 3
abccc
1 3
1 2
2 3
out:
Yes
No
Yes
-->
<!-- test
in:
1 2
a
1 1
1 2
out:
Yes
Yes
-->

</details>

### Example 3 — Lomsat gelral · ★ 2300

- **Source:** [CF 600E · Lomsat gelral](https://codeforces.com/problemset/problem/600/E) — 2300
- **Difficulty:** 2300
- **Problem:** rooted tree (root 1), $n \le 10^5$, colours $1..n$. A colour *dominates* a subtree if no other colour appears more often there (ties: several dominate). For each vertex print the **sum** of dominating colours of its subtree.
- **Thinking from first principles:** we need "max frequency" and "sum of colours achieving it" under insertions. Under pure insertions both are easy: when `cnt[c]` rises above the max, reset the sum to $c$; when it equals the max, add $c$. Deletions would be hard (the max may drop) — but the sack never deletes single elements, it **clears everything**, after which max and sum reset to 0. That is precisely why the sack fits.

<details><summary>Solution</summary>

Sack with `cnt`, `mx`, `sum`. Sums reach $\approx n^2/2$: 64-bit. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> c(n + 1);
    for (int v = 1; v <= n; v++) cin >> c[v];
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<int> par(n + 1, 0), sz(n + 1, 1), heavy(n + 1, 0), ord, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); ord.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) {
        int v = ord[i], p = par[v];
        sz[p] += sz[v];
        if (!heavy[p] || sz[v] > sz[heavy[p]]) heavy[p] = v;
    }
    vector<int> order; st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v] && u != heavy[v]) st.push_back(u);
        if (heavy[v]) st.push_back(heavy[v]);
    }
    vector<int> cnt(n + 1, 0);
    vector<long long> ans(n + 1);
    int mx = 0; long long sum = 0;
    auto add = [&](int x) {
        int k = ++cnt[c[x]];
        if (k > mx) { mx = k; sum = c[x]; } else if (k == mx) sum += c[x];
    };
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i], h = heavy[v];
        add(v);
        for (int j = i + 1 + (h ? sz[h] : 0); j < i + sz[v]; j++) add(order[j]);
        ans[v] = sum;
        if (v == 1 || heavy[par[v]] != v) {
            for (int j = i; j < i + sz[v]; j++) cnt[c[order[j]]] = 0;
            mx = 0; sum = 0;
        }
    }
    for (int v = 1; v <= n; v++) cout << ans[v] << (v == n ? '\n' : ' ');
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
        int[] c = new int[n + 1];
        for (int v = 1; v <= n; v++) c[v] = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], sz = new int[n + 1], heavy = new int[n + 1], ord = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; ord[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) {
            int v = ord[i], p = par[v];
            sz[p] += sz[v];
            if (heavy[p] == 0 || sz[v] > sz[heavy[p]]) heavy[p] = v;
        }
        int[] order = new int[n];
        top = 0; cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v] && adj[j] != heavy[v]) st[top++] = adj[j];
            if (heavy[v] != 0) st[top++] = heavy[v];
        }
        int[] num = new int[n + 1];
        long[] ans = new long[n + 1];
        int mx = 0; long sum = 0;
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i], h = heavy[v];
            int from = i + 1 + (h != 0 ? sz[h] : 0);
            for (int j = from - 1; j < i + sz[v]; j++) {
                int x = j == from - 1 ? v : order[j];
                int k = ++num[c[x]];
                if (k > mx) { mx = k; sum = c[x]; } else if (k == mx) sum += c[x];
            }
            ans[v] = sum;
            if (v == 1 || heavy[par[v]] != v) {
                for (int j = i; j < i + sz[v]; j++) num[c[order[j]]] = 0;
                mx = 0; sum = 0;
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(ans[v]).append(v == n ? '\n' : ' ');
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
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

Test 1: edge $1$–$2$ and vertex 2 with children $3, 4$, colours $1,2,3,4$ — every colour appears once in the root's subtree, so all four dominate: $1+2+3+4 = 10$; under 2 it is $2+3+4 = 9$. Test 2: path $1$–$2$–$3$–$4$ with colours $1,2,2,1$: subtree of 1 has two 1s and two 2s → 3; subtree of 2 is $\{2,2,1\}$ → 2; subtree of 3 is $\{2,1\}$ → 3.

<!-- test
in:
4
1 2 3 4
1 2
2 3
2 4
out:
10 9 3 4
-->
<!-- test
in:
4
1 2 2 1
1 2
2 3
3 4
out:
3 2 3 1
-->

</details>

### Example 4 — Tree and Queries · ★ 2400

- **Source:** [CF 375D · Tree and Queries](https://codeforces.com/problemset/problem/375/D) — 2400
- **Difficulty:** 2400
- **Problem:** rooted tree (root 1), $n, m \le 10^5$, colours up to $10^5$. Query $(v, k)$: how many colours occur **at least $k$ times** in subtree($v$)?
- **Thinking from first principles:** for a fixed subtree we need, for many thresholds, "number of colours with count $\ge k$". Maintain `cnt[c]` and `ge[t]` = number of colours with `cnt` $\ge t$. When `cnt[c]` goes from $t-1$ to $t$, exactly `ge[t]` increases by one — $O(1)$ per insertion, and symmetric for removal. With queries grouped by vertex, the sack answers them all offline.

<details><summary>Solution</summary>

Sack; when clearing, decrement one occurrence at a time so `ge` stays consistent (or reset both arrays over the touched range). Thresholds above $n$ answer 0. $O((n + m) + n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<int> c(n + 1);
    for (int v = 1; v <= n; v++) cin >> c[v];
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; adj[a].push_back(b); adj[b].push_back(a); }
    vector<vector<pair<int,int>>> qs(n + 1);
    for (int i = 0; i < m; i++) { int v, k; cin >> v >> k; qs[v].push_back({k, i}); }
    vector<int> par(n + 1, 0), sz(n + 1, 1), heavy(n + 1, 0), ord, st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); ord.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; st.push_back(u); }
    }
    for (int i = n - 1; i > 0; i--) {
        int v = ord[i], p = par[v];
        sz[p] += sz[v];
        if (!heavy[p] || sz[v] > sz[heavy[p]]) heavy[p] = v;
    }
    vector<int> order; st = {1};
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v] && u != heavy[v]) st.push_back(u);
        if (heavy[v]) st.push_back(heavy[v]);
    }
    const int C = 100000;
    vector<int> cnt(C + 1, 0), ge(n + 2, 0), ans(m);
    auto add = [&](int x) { ge[++cnt[c[x]]]++; };
    auto rem = [&](int x) { ge[cnt[c[x]]--]--; };
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i], h = heavy[v];
        add(v);
        for (int j = i + 1 + (h ? sz[h] : 0); j < i + sz[v]; j++) add(order[j]);
        for (auto [k, id] : qs[v]) ans[id] = k <= n ? ge[k] : 0;
        if (v == 1 || heavy[par[v]] != v)
            for (int j = i; j < i + sz[v]; j++) rem(order[j]);
    }
    for (int i = 0; i < m; i++) cout << ans[i] << '\n';
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
        int[] c = new int[n + 1];
        for (int v = 1; v <= n; v++) c[v] = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] qv = new int[m], qk = new int[m], qs = new int[n + 2];
        for (int i = 0; i < m; i++) { qv[i] = in.nextInt(); qk[i] = in.nextInt(); qs[qv[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) qs[v] += qs[v - 1];
        int[] qid = new int[m], qf = qs.clone();
        for (int i = 0; i < m; i++) qid[qf[qv[i]]++] = i;
        int[] par = new int[n + 1], sz = new int[n + 1], heavy = new int[n + 1], ord = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; ord[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; st[top++] = adj[j]; }
        }
        Arrays.fill(sz, 1);
        for (int i = n - 1; i > 0; i--) {
            int v = ord[i], p = par[v];
            sz[p] += sz[v];
            if (heavy[p] == 0 || sz[v] > sz[heavy[p]]) heavy[p] = v;
        }
        int[] order = new int[n];
        top = 0; cnt = 0;
        st[top++] = 1;
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v] && adj[j] != heavy[v]) st[top++] = adj[j];
            if (heavy[v] != 0) st[top++] = heavy[v];
        }
        int[] num = new int[100001], ge = new int[n + 2], ans = new int[m];
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i], h = heavy[v];
            ge[++num[c[v]]]++;
            for (int j = i + 1 + (h != 0 ? sz[h] : 0); j < i + sz[v]; j++) ge[++num[c[order[j]]]]++;
            for (int k = qs[v]; k < qs[v + 1]; k++) { int id = qid[k]; ans[id] = qk[id] <= n ? ge[qk[id]] : 0; }
            if (v == 1 || heavy[par[v]] != v)
                for (int j = i; j < i + sz[v]; j++) ge[num[c[order[j]]]--]--;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < m; i++) sb.append(ans[i]).append('\n');
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
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

Test 1: tree $1$–$2$, $1$–$3$, $3$–$4$, $3$–$5$, colours $1,2,2,3,2$. Root subtree counts: colour 2 ×3, colours 1, 3 ×1. So $k=1$: 3 colours, $k=2$: 1, $k=3$: 1, $k=4$: 0. Subtree of 3 is $\{2,3,2\}$: $k=2$ → 1.

<!-- test
in:
5 6
1 2 2 3 2
1 2
1 3
3 4
3 5
1 1
1 2
1 3
1 4
3 2
4 1
out:
3
1
1
0
1
1
-->
<!-- test
in:
1 2
100000
1 1
1 100000
out:
1
0
-->

</details>

### Example 5 — XOR Tree · ★ 2400

- **Source:** [CF 1709E · XOR Tree](https://codeforces.com/problemset/problem/1709/E) — 2400
- **Difficulty:** 2400
- **Problem:** a tree on $n \le 2\cdot10^5$ vertices with values $1 \le a_i < 2^{30}$. Change as few values as possible (to any positive integers) so that **no simple path has XOR 0**.
- **Thinking from first principles:** let $d(v)$ = XOR of $a$ on the root-to-$v$ path (inclusive). The path $x$–$y$ with top vertex $v$ has XOR $d(x)\oplus d(y)\oplus a_v$. Changing a vertex to a huge distinct power of two kills every path through it. Greedy: process vertices bottom-up; at the deepest vertex $v$ that is the top of some zero path inside its subtree, we must change *some* vertex of that path, and changing $v$ itself is best — it kills every path through $v$, which includes every path that passes from $v$'s subtree to the outside. After changing $v$, its whole subtree no longer interacts with anything, so its information is thrown away. Detecting "is there a zero path with top $v$" while merging child sets: when merging set $A$ into set $B$ (both of $d$-values within $v$'s subtree, different branches or $v$ itself), check each $x \in A$ for $x \oplus a_v \in B$. Small-to-large keeps the checks and inserts at $O(n\log n)$ set operations.

<details><summary>Solution</summary>

Reverse preorder; `S[v]` starts as $\{d(v)\}$; merging child $v$ into parent $p$: swap to larger, check the small side against the big side with $a_p$, then insert. When $p$ is reached, if any check fired, count one change and clear `S[p]`. $O(n\log^2 n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> a(n + 1);
    for (int v = 1; v <= n; v++) cin >> a[v];
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int x, y; cin >> x >> y; adj[x].push_back(y); adj[y].push_back(x); }
    vector<int> par(n + 1, 0), d(n + 1, 0), order, st = {1};
    d[1] = a[1];
    while (!st.empty()) {
        int v = st.back(); st.pop_back(); order.push_back(v);
        for (int u : adj[v]) if (u != par[v]) { par[u] = v; d[u] = d[v] ^ a[u]; st.push_back(u); }
    }
    vector<set<int>> S(n + 1);
    vector<char> bad(n + 1, 0);
    for (int v = 1; v <= n; v++) S[v].insert(d[v]);
    int ans = 0;
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i];
        if (bad[v]) { ans++; S[v].clear(); }                    // change a[v]: its subtree is cut off
        if (i == 0) break;
        int p = par[v];
        if (S[v].size() > S[p].size()) swap(S[v], S[p]);
        for (int x : S[v]) if (S[p].count(x ^ a[p])) { bad[p] = 1; break; }
        if (!bad[p]) S[p].insert(S[v].begin(), S[v].end());    // a bad p is cleared anyway
        set<int>().swap(S[v]);
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
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        int[] a = new int[n + 1];
        for (int v = 1; v <= n; v++) a[v] = in.nextInt();
        int[] eu = new int[n - 1], ev = new int[n - 1], start = new int[n + 2];
        for (int i = 0; i < n - 1; i++) { eu[i] = in.nextInt(); ev[i] = in.nextInt(); start[eu[i] + 1]++; start[ev[i] + 1]++; }
        for (int v = 1; v <= n + 1; v++) start[v] += start[v - 1];
        int[] adj = new int[2 * (n - 1)], fill = start.clone();
        for (int i = 0; i < n - 1; i++) { adj[fill[eu[i]]++] = ev[i]; adj[fill[ev[i]]++] = eu[i]; }
        int[] par = new int[n + 1], d = new int[n + 1], order = new int[n], st = new int[n];
        int top = 0, cnt = 0;
        st[top++] = 1; d[1] = a[1];
        while (top > 0) {
            int v = st[--top]; order[cnt++] = v;
            for (int j = start[v]; j < start[v + 1]; j++) if (adj[j] != par[v]) { par[adj[j]] = v; d[adj[j]] = d[v] ^ a[adj[j]]; st[top++] = adj[j]; }
        }
        @SuppressWarnings("unchecked")
        HashSet<Integer>[] S = new HashSet[n + 1];
        for (int v = 1; v <= n; v++) { S[v] = new HashSet<>(); S[v].add(d[v]); }
        boolean[] bad = new boolean[n + 1];
        int ans = 0;
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i];
            if (bad[v]) { ans++; S[v].clear(); }
            if (i == 0) break;
            int p = par[v];
            if (S[v].size() > S[p].size()) { HashSet<Integer> t = S[v]; S[v] = S[p]; S[p] = t; }
            HashSet<Integer> big = S[p];
            for (int x : S[v]) if (big.contains(x ^ a[p])) { bad[p] = true; break; }
            if (!bad[p]) big.addAll(S[v]);
            S[v] = null;
        }
        out.println(ans);
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
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

Two shortcuts are safe: once `bad[p]` is set, `S[p]` will be cleared when $p$ is processed, so further checks and inserts into it can be skipped. Test 1: path $1$–$2$–$3$ with values $1, 2, 3$: $1 \oplus 2 \oplus 3 = 0$, one change. Test 2: star centred at 1 with values $5$ and leaves $1, 4, 1, 4$: the paths leaf–1–leaf with $1 \oplus 5 \oplus 4 = 0$ all pass through 1; changing vertex 1 fixes everything → 1. Test 3: two disjoint zero paths $2$–$4$ ($3 \oplus 3$) and $3$–$5$ ($6 \oplus 6$) under a root → 2.

<!-- test
in:
3
1 2 3
1 2
2 3
out:
1
-->
<!-- test
in:
5
5 1 4 1 4
1 2
1 3
1 4
1 5
out:
1
-->
<!-- test
in:
5
7 3 6 3 6
1 2
1 3
2 4
3 5
out:
2
-->
<!-- test
in:
1
5
out:
0
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Swap containers, never copy.** `swap(S[a], S[b])` is $O(1)$ for `std::set`/`map`/`vector`/`unordered_map`; `S[p] = S[v]` is a full copy and turns $O(n\log n)$ into $O(n^2)$.
2. **Read the answer before donating** the container to the parent, and remember that after a swap the *parent's* old contents now sit in the child's slot.
3. **Keep side data with the container** (e.g. `best[v]` for the max count): swap it together with the container.
4. **In the sack, the heavy child must be the true heavy child** (largest subtree). A wrong choice (e.g. the first child) silently degrades to $O(n^2)$ on adversarial trees — it still passes small tests.
5. **Statistics that need deletion of single elements** (e.g. max frequency) are fine in the sack only because the sack clears *everything* at once; reset the derived values (max, sum) at the clear, not by "undoing".
6. **Clear only what you touched** — iterate the subtree's range, never `fill` the whole array per path top ($O(n)$ per clear would be $O(n^2)$).
7. **Java**: `HashMap<Integer,Integer>` boxing is slow but OK for $2\cdot10^5$ with $\approx 4\cdot10^6$ operations. For $10^6$ elements prefer the sack with `int[]`. Anti-hash tests rarely target `HashMap<Integer,…>` keys because Java switches to tree bins, but `HashSet` of crafted long keys can still be slow — randomise (XOR with a random constant) if the values are adversarial.
8. **C++ `unordered_map` with the default hash** is attackable on CF; use `map`, a sorted vector, or a splitmix64 custom hash.
9. **Depth arrays in the sack** must be sized by the maximum depth ($n$), and queries with $h > n$ must be guarded.
10. **Memory in small-to-large**: free the donated container (`set<int>().swap(S[v])` / `S[v] = null`); otherwise peak memory is the sum of all containers, not $O(n)$.

## 7. Going further (toward 2400–2600+)

- **Long-path (depth) decomposition**: when the statistic is an array indexed by depth below $v$, inherit the *deepest* child's array by pointer offset and merge the others element-wise; total $O(n)$ because each array cell is merged once per path. Classic: [CF 1009F · Dominant Indices](https://codeforces.com/problemset/problem/1009/F) — 2300.
- **Small-to-large with lazy global offsets**: keep a map plus a "shift" applied to all its keys or values, so that parent-level updates cost $O(1)$; e.g. [CF 1805E · There Should Be a Lot of Maximums](https://codeforces.com/problemset/problem/1805/E) — 2300, [CF 1824C · LuoTianyi and XOR-Tree](https://codeforces.com/problemset/problem/1824/C) — 2500, [CF 1455G · Forbidden Value](https://codeforces.com/problemset/problem/1455/G) — 2900 (merging DP maps).
- **Merging tries / segment trees** bottom-up (segment-tree merging, total $O(n \log C)$): [CF 778C · Peterson Polyglot](https://codeforces.com/problemset/problem/778/C) — 2500; see [segment tree merging](../08-Data-Structures/04-segment-tree-advanced-descent-merging-beats.md).
- **Sack for path statistics**: with XOR masks of letters, count palindromic-able paths via the sack — [CF 741D · Arpa’s letter-marked tree and Mehrdad’s Dokhtar-kosh paths](https://codeforces.com/problemset/problem/741/D) — 2900.
- **Distinct values in subtree, online**: persistent segment tree over the Euler array ([persistent structures](../08-Data-Structures/08-persistent-data-structures.md)).
- Revision: [cheat sheet](../99-Cheat-Sheets/10-trees-cheatsheet.md).

## 8. Practice ladder

**1700–2100**
- [ ] [CSES 1139 · Distinct Colors](https://cses.fi/problemset/task/1139)
- [ ] [CF 1923E · Count Paths](https://codeforces.com/problemset/problem/1923/E) — 2000
- [ ] [CF 1856E1 · PermuTree (easy version)](https://codeforces.com/problemset/problem/1856/E1) — 1800
- [ ] [CF 208E · Blood Cousins](https://codeforces.com/problemset/problem/208/E) — 2100

**2100–2400**
- [ ] [CF 570D · Tree Requests](https://codeforces.com/problemset/problem/570/D) — 2200
- [ ] [CF 600E · Lomsat gelral](https://codeforces.com/problemset/problem/600/E) — 2300
- [ ] [CF 1009F · Dominant Indices](https://codeforces.com/problemset/problem/1009/F) — 2300
- [ ] [CF 1805E · There Should Be a Lot of Maximums](https://codeforces.com/problemset/problem/1805/E) — 2300
- [ ] [CF 375D · Tree and Queries](https://codeforces.com/problemset/problem/375/D) — 2400
- [ ] [CF 246E · Blood Cousins Return](https://codeforces.com/problemset/problem/246/E) — 2400
- [ ] [CF 1709E · XOR Tree](https://codeforces.com/problemset/problem/1709/E) — 2400

**2400+**
- [ ] [CF 1824C · LuoTianyi and XOR-Tree](https://codeforces.com/problemset/problem/1824/C) — 2500
- [ ] [CF 778C · Peterson Polyglot](https://codeforces.com/problemset/problem/778/C) — 2500
- [ ] [CF 1856E2 · PermuTree (hard version)](https://codeforces.com/problemset/problem/1856/E2) — 2700
- [ ] [CF 741D · Arpa’s letter-marked tree and Mehrdad’s Dokhtar-kosh paths](https://codeforces.com/problemset/problem/741/D) — 2900
- [ ] [CF 1455G · Forbidden Value](https://codeforces.com/problemset/problem/1455/G) — 2900

## 9. LeetCode / FAANG cross-reference

Rare in interviews as a named technique; the underlying idea ("merge smaller into larger") does appear.

- [LC 1519 · Number of Nodes in the Sub-Tree With the Same Label](https://leetcode.com/problems/number-of-nodes-in-the-sub-tree-with-the-same-label/) — Medium — per-subtree counting; with 26 labels an array per vertex suffices, but the sack is the scalable version.
- [LC 2003 · Smallest Missing Genetic Value in Each Subtree](https://leetcode.com/problems/smallest-missing-genetic-value-in-each-subtree/) — Hard — subtree sets; small-to-large works, the intended trick walks only the path from value 1.
- [LC 2421 · Number of Good Paths](https://leetcode.com/problems/number-of-good-paths/) — Hard — DSU merging by increasing value; small-to-large maps are an alternative.
- [LC 1938 · Maximum Genetic Difference Query](https://leetcode.com/problems/maximum-genetic-difference-query/) — Hard — offline queries attached to vertices, answered while a structure (binary trie) holds the root path.

## 10. Self-check

1. Prove that small-to-large merging performs $O(n\log n)$ element moves.
2. Why does the sack never need to delete a single element, and why does that matter for "max frequency"?
3. Prove there are at most $\log_2 n$ light edges on any root path.
4. In the heavy-first preorder, which positions hold $v$'s light subtrees?
5. What goes wrong if you pick the *first* child instead of the heaviest one in the sack?
6. You need, for every vertex, the number of distinct values among its descendants at depth exactly $\mathrm{dep}(v) + k$ for a query-specific $k$. Which variant do you use?
7. Why must you read $v$'s answer before merging its container into the parent's?

<details><summary>Answers</summary>

1. Each move puts an element into a container at least as big as the one it left, so its container size at least doubles; sizes are bounded by $n$, so each element moves $\le \log_2 n$ times.
2. A light subtree's contribution is removed only by clearing the whole array (the array then holds exactly that subtree). So derived statistics can be reset to their empty values instead of being "undone" — max frequency, which is not invertible under single deletions, never needs to go down.
3. On a light edge $(p, c)$ the heavy sibling $h$ satisfies $sz(h) \ge sz(c)$, so $sz(p) \ge 1 + 2sz(c)$. Climbing a light edge more than doubles the size, which cannot exceed $n$.
4. $[\,i + 1 + sz(h),\; i + sz(v))$ where $i$ is $v$'s position and $h$ its heavy child (and $v$ itself is at $i$).
5. Correctness is unaffected, but the bound breaks: a vertex is re-added for every "light" edge above it, and with a bad choice that can be $\Theta(n)$ edges — $O(n^2)$ total on a caterpillar where the first child is always the small one.
6. Sack with a per-depth structure (e.g. `set` or count map per depth), or small-to-large maps `depth → set`; a classic instance is CF 246E. Answer each query when the sack holds subtree($v$), reading depth $\mathrm{dep}(v)+k$.
7. After the merge (and possibly a swap), $v$'s slot holds either nothing or the parent's old contents; its own subtree's data now lives in the parent's container mixed with other branches.

</details>
