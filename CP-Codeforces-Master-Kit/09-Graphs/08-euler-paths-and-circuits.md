# Euler Paths and Circuits

> **Band:** 🔵 1700 → 🟠 2500 · **Priority:** 🔥 (conditions + Hierholzer) · ⚡ (de Bruijn, balancing trick) · **FAANG:** medium · **Prerequisites:** [BFS/DFS](01-graph-representation-bfs-dfs.md), [DSU](../08-Data-Structures/06-dsu-and-variants.md)
> **You can say you know this when:** you can state the existence conditions for directed and undirected Euler paths and circuits (including the connectivity clause), write iterative Hierholzer in a few minutes without recursion, model "strings from overlapping pieces" as an Euler path, and use the virtual-vertex trick to orient edges with $|\text{in}-\text{out}| \le 1$.

## 1. First principles — why this works

**The question.** An *Euler trail* uses every **edge** exactly once; an *Euler circuit* is a trail that ends where it started.
(A *Hamiltonian* path visits every **vertex** once — NP-hard, a different problem; don't mix them up.)

**Necessity by counting.** Walk along a trail. Every time it passes *through* a vertex it uses one edge to arrive and one to
leave. So in an undirected circuit every vertex has even degree; in a trail only the two endpoints may be odd. In a directed
circuit every vertex has $\text{in} = \text{out}$; in a directed trail the start has $\text{out} - \text{in} = 1$, the end has
$\text{in} - \text{out} = 1$. Also all edges must lie in one connected component (isolated vertices are irrelevant).

**Sufficiency by construction (Hierholzer).** Assume the degree conditions hold and all edges are connected. Start at the
designated vertex and walk greedily along unused edges until stuck. For a circuit you can only get stuck at the start:
entering any other vertex $v$ uses an odd number of its edges so far, and $v$ has even degree, so an unused edge remains. The
closed walk $W$ found may miss edges; but since the graph is connected, some vertex $u$ on $W$ still has unused edges, and the
remaining graph still has all degrees even, so a closed walk from $u$ exists and can be **spliced** into $W$ at $u$. Repeat until
no edges are left. For a trail between the two odd vertices, add a virtual edge between them, take a circuit, and cut it there
(or just start at an odd vertex — the stack algorithm below handles it directly).

**The stack form (what you actually code).** Keep a stack, initially the start vertex. Look at the top $v$:
- if $v$ has an unused edge $v \to w$, mark it used and push $w$ (keep walking);
- otherwise pop $v$ and append it to the answer.

The answer comes out **reversed**. Why it is correct: a vertex is popped only when all its edges are used; the popped sequence
records, in reverse, the walk with all sub-circuits spliced in at the moment their junction vertex got stuck. Each edge is pushed
exactly once, so the time is $O(n + m)$ with a per-vertex pointer to the next candidate edge (never rescan used edges).

**Checking connectivity for free.** After the algorithm, the answer has $m+1$ vertices iff every edge was reached. If the edges
were in several components, it has fewer: print "impossible". This avoids a separate DSU.

**Directed connectivity subtlety.** For a directed graph with $\text{in} = \text{out}$ everywhere, *weak* connectivity of the
non-isolated vertices already implies strong connectivity (a balanced digraph has no cut separating "only outgoing" edges).
The $m+1$ length check covers this too.

**Why this matters beyond "draw without lifting the pen".** Euler trails are the tool whenever a string or sequence must be
built from **overlapping pieces**: pieces are edges, overlaps are vertices. The de Bruijn graph (vertices = words of length
$n-1$, edges = words of length $n$) makes "a shortest string containing every $n$-letter word" an Euler circuit problem, which is
linear, whereas the vertex version ("visit every word once") would be Hamiltonian and hopeless.

**The balancing trick.** In any undirected graph the number of odd vertices is even (handshake lemma). Add a virtual vertex
$X$ joined to every odd vertex: now all degrees are even, so every component has an Euler circuit. Orient each edge in the
direction the circuit traverses it, then delete the virtual edges. Every real vertex had $\text{in} = \text{out}$ in the augmented
graph and lost at most one virtual edge, so $|\text{in} - \text{out}| \le 1$, with equality exactly for odd vertices. Many
"balance the rows and columns" constructions (CF 547D, CF 723E, CF 1186F) are this trick in disguise.

## 2. Formulas, definitions and identities

| Graph | Euler circuit exists iff | Euler trail (not closed) exists iff |
|---|---|---|
| undirected | all degrees even, edges connected | exactly 2 odd vertices, edges connected (they are the endpoints) |
| directed | $\text{in}(v) = \text{out}(v)\ \forall v$, edges weakly connected | one vertex with $\text{out}-\text{in}=1$ (start), one with $\text{in}-\text{out}=1$ (end), rest balanced, edges weakly connected |

- **Handshake lemma:** $\sum_v \deg(v) = 2m$, so the number of odd-degree vertices is even.
- **Minimum number of trails covering every edge exactly once** (undirected): for each connected component with at least one
  edge and $2k$ odd vertices, $\max(1, k)$ trails; sum over components. (Lower bound: each odd vertex is an endpoint of some trail;
  upper bound: add $k$ virtual edges pairing odd vertices, take one circuit, cut at the virtual edges — $k$ cuts give $k$ trails.)
- **Directed analogue:** a weakly connected component with imbalance $D = \sum_v \max(0, \text{out}(v) - \text{in}(v))$ needs $\max(1, D)$ trails.
- **de Bruijn sequence** $B(k, n)$: cyclic sequence over a $k$-letter alphabet in which every length-$n$ word occurs exactly once;
  cyclic length $k^n$, linear length $k^n + n - 1$. Graph: $k^{n-1}$ vertices, $k^n$ edges, every vertex has $\text{in} = \text{out} = k$.
- **Number of Euler circuits (BEST theorem, 🧊):** for a connected balanced digraph,
  $\text{ec}(G) = t_w(G) \prod_v (\text{out}(v) - 1)!$ where $t_w$ is the number of spanning arborescences rooted at any fixed $w$
  (matrix-tree theorem, see [linear-algebra tricks](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)).
  Counting is hard for undirected graphs.
- **Number of de Bruijn sequences:** $\dfrac{(k!)^{k^{n-1}}}{k^n}$ (from BEST); for binary, $2^{2^{n-1} - n}$.
- **Eulerian subgraphs (cycle space):** the number of edge subsets in which every degree is even is $2^{m - n + c}$ ($c$ = components);
  these form the cycle space over $\mathbb{F}_2$ (see [bipartite graphs and cycles](09-bipartite-graphs-and-cycles.md)).
- **Chinese postman** (shortest closed walk using every edge at least once, undirected): total weight + minimum-weight perfect matching
  of odd vertices under shortest-path distances. With $\le 20$ odd vertices: bitmask DP ([bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md)).
- Complexity of Hierholzer: $O(n + m)$ time and memory.

## 3. Implementation (C++ and Java)

Both functions return the vertex sequence of an Euler trail starting at `start`, or an empty sequence if the edges cannot all be
used from there. The caller checks the degree conditions (which also decides the start). Edges are arcs in `head/nxt/to` lists;
for undirected graphs, arc `a` and `a ^ 1` are the same edge, so a `used[a >> 1]` flag prevents walking it twice.

```cpp
// undirected: edges (eu[i], ev[i]); vertices 0..n-1
vector<int> eulerUndirected(int n, const vector<int>& eu, const vector<int>& ev, int start) {
    int m = eu.size();
    vector<int> head(n, -1), nxt(2 * m), to(2 * m);
    for (int i = 0; i < m; i++) {
        to[2 * i] = ev[i]; nxt[2 * i] = head[eu[i]]; head[eu[i]] = 2 * i;
        to[2 * i + 1] = eu[i]; nxt[2 * i + 1] = head[ev[i]]; head[ev[i]] = 2 * i + 1;
    }
    vector<char> used(m, 0);
    vector<int> it = head, stk = {start}, path;
    while (!stk.empty()) {
        int v = stk.back();
        while (it[v] != -1 && used[it[v] >> 1]) it[v] = nxt[it[v]];     // skip edges already walked from the other side
        if (it[v] == -1) { path.push_back(v); stk.pop_back(); }
        else { int a = it[v]; used[a >> 1] = 1; it[v] = nxt[a]; stk.push_back(to[a]); }
    }
    if ((int)path.size() != m + 1) return {};                        // some edge unreachable from start
    reverse(path.begin(), path.end());
    return path;
}

// directed: arcs eu[i] -> ev[i]
vector<int> eulerDirected(int n, const vector<int>& eu, const vector<int>& ev, int start) {
    int m = eu.size();
    vector<int> head(n, -1), nxt(m);
    for (int i = 0; i < m; i++) { nxt[i] = head[eu[i]]; head[eu[i]] = i; }
    vector<int> it = head, stk = {start}, path;
    while (!stk.empty()) {
        int v = stk.back();
        if (it[v] == -1) { path.push_back(v); stk.pop_back(); }
        else { int a = it[v]; it[v] = nxt[a]; stk.push_back(ev[a]); }   // each arc is consumed exactly once
    }
    if ((int)path.size() != m + 1) return {};
    reverse(path.begin(), path.end());
    return path;
}
```

```java
static int[] eulerUndirected(int n, int[] eu, int[] ev, int start) {
    int m = eu.length;
    int[] head = new int[n], nxt = new int[2 * m], to = new int[2 * m];
    Arrays.fill(head, -1);
    for (int i = 0; i < m; i++) {
        to[2 * i] = ev[i]; nxt[2 * i] = head[eu[i]]; head[eu[i]] = 2 * i;
        to[2 * i + 1] = eu[i]; nxt[2 * i + 1] = head[ev[i]]; head[ev[i]] = 2 * i + 1;
    }
    boolean[] used = new boolean[m];
    int[] it = head.clone(), stk = new int[m + 1], path = new int[m + 1];
    int sp = 0, len = 0;
    stk[sp++] = start;
    while (sp > 0) {
        int v = stk[sp - 1];
        while (it[v] != -1 && used[it[v] >> 1]) it[v] = nxt[it[v]];
        if (it[v] == -1) { path[len++] = v; sp--; }
        else { int a = it[v]; used[a >> 1] = true; it[v] = nxt[a]; stk[sp++] = to[a]; }
    }
    if (len != m + 1) return new int[0];
    for (int i = 0, j = len - 1; i < j; i++, j--) { int t = path[i]; path[i] = path[j]; path[j] = t; }
    return path;
}

static int[] eulerDirected(int n, int[] eu, int[] ev, int start) {
    int m = eu.length;
    int[] head = new int[n], nxt = new int[m];
    Arrays.fill(head, -1);
    for (int i = 0; i < m; i++) { nxt[i] = head[eu[i]]; head[eu[i]] = i; }
    int[] it = head.clone(), stk = new int[m + 1], path = new int[m + 1];
    int sp = 0, len = 0;
    stk[sp++] = start;
    while (sp > 0) {
        int v = stk[sp - 1];
        if (it[v] == -1) { path[len++] = v; sp--; }
        else { int a = it[v]; it[v] = nxt[a]; stk[sp++] = ev[a]; }
    }
    if (len != m + 1) return new int[0];
    for (int i = 0, j = len - 1; i < j; i++, j--) { int t = path[i]; path[i] = path[j]; path[j] = t; }
    return path;
}
```

Stack sizes: the explicit stack holds at most $m + 1$ entries (each push consumes an edge), so no recursion limit applies.

## 4. Recognising the pattern

| Statement signal | Think |
|---|---|
| "use every road / edge exactly once", "draw the figure without lifting the pen" | Euler trail/circuit; check degrees first |
| "restore a string from all its substrings of length $k$" | vertices = $(k-1)$-grams, edges = $k$-grams, directed Euler path |
| "shortest string containing every length-$n$ word", "crack a lock with all codes" | de Bruijn circuit |
| "arrange dominoes / pairs so consecutive ones match" | Euler path on values as vertices |
| "orient edges so every vertex has in ≈ out", "color edges red/blue so each vertex is balanced" | virtual vertex on odd vertices + Euler circuit |
| "cover all edges with fewest paths/strokes" | count odd vertices per component |
| "walk that uses each edge at least once, minimum length" | Chinese postman (matching on odd vertices) |
| "visit every **vertex** once" | Hamiltonian — bitmask DP for $n \le 20$, not Euler |

## 5. Worked examples (graded)

Euler outputs are rarely unique. The programs below use the same deterministic rule in C++ and Java (adjacency lists in
"last inserted first" order, explicit stack), and every expected output in the tests was validated with an independent checker.

### Example 1 — Mail Delivery  ·  ★ ≈1700

- **Source:** [CSES 1691 · Mail Delivery](https://cses.fi/problemset/task/1691)
- **Difficulty:** ≈1700 (est.)
- **Problem:** Undirected graph, $n \le 10^5$, $m \le 2\cdot10^5$, no repeated streets. Find a route that starts and ends at
  vertex $1$ and uses every street exactly once; print its $m + 1$ vertices, or `IMPOSSIBLE`.
- **Thinking from first principles:** Degrees must all be even. The other condition is that every edge is reachable from $1$,
  which the length check of Hierholzer verifies. A recursive DFS would hit depth $2\cdot10^5$, so use the explicit stack.

<details><summary>Solution</summary>

Check parity, run iterative Hierholzer from $1$, verify $m+1$ vertices. $O(n + m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> head(n + 1, -1), nxt(2 * m), to(2 * m), deg(n + 1, 0);
    for (int i = 0; i < m; i++) {
        int a, b; cin >> a >> b;
        to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
        to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
        deg[a]++; deg[b]++;
    }
    for (int v = 1; v <= n; v++) if (deg[v] % 2) { cout << "IMPOSSIBLE\n"; return 0; }
    vector<char> used(m, 0);
    vector<int> it = head, stk = {1}, path;
    while (!stk.empty()) {
        int v = stk.back();
        while (it[v] != -1 && used[it[v] >> 1]) it[v] = nxt[it[v]];
        if (it[v] == -1) { path.push_back(v); stk.pop_back(); }
        else { int a = it[v]; used[a >> 1] = 1; it[v] = nxt[a]; stk.push_back(to[a]); }
    }
    if ((int)path.size() != m + 1) { cout << "IMPOSSIBLE\n"; return 0; }
    reverse(path.begin(), path.end());
    for (int i = 0; i <= m; i++) cout << path[i] << " \n"[i == m];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int readByte() throws IOException { return in.read(); }
    static int nextInt() throws IOException {
        int b = readByte();
        while (b != '-' && (b < '0' || b > '9')) b = readByte();
        boolean neg = b == '-';
        if (neg) b = readByte();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = readByte(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] head = new int[n + 1], nxt = new int[2 * m], to = new int[2 * m], deg = new int[n + 1];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            int a = nextInt(), b = nextInt();
            to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
            to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
            deg[a]++; deg[b]++;
        }
        for (int v = 1; v <= n; v++) if (deg[v] % 2 != 0) { System.out.println("IMPOSSIBLE"); return; }
        boolean[] used = new boolean[m];
        int[] it = head.clone(), stk = new int[m + 1], path = new int[m + 1];
        int sp = 0, len = 0;
        stk[sp++] = 1;
        while (sp > 0) {
            int v = stk[sp - 1];
            while (it[v] != -1 && used[it[v] >> 1]) it[v] = nxt[it[v]];
            if (it[v] == -1) { path[len++] = v; sp--; }
            else { int a = it[v]; used[a >> 1] = true; it[v] = nxt[a]; stk[sp++] = to[a]; }
        }
        if (len != m + 1) { System.out.println("IMPOSSIBLE"); return; }
        StringBuilder sb = new StringBuilder();
        for (int i = len - 1; i >= 0; i--) sb.append(path[i]).append(i == 0 ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
3 3
1 2
2 3
3 1
out:
1 3 2 1
-->
<!-- test
in:
5 6
1 2
2 3
3 1
3 4
4 5
5 3
out:
1 3 5 4 3 2 1
-->
<!-- test
in:
4 3
1 2
2 3
3 4
out:
IMPOSSIBLE
-->
<!-- test
in:
6 6
1 2
2 3
3 1
4 5
5 6
6 4
out:
IMPOSSIBLE
-->

### Example 2 — Teleporters Path  ·  ★ ≈1800

- **Source:** [CSES 1693 · Teleporters Path](https://cses.fi/problemset/task/1693)
- **Difficulty:** ≈1800 (est.)
- **Problem:** Directed graph, $2 \le n \le 10^5$, $m \le 2\cdot10^5$. Find a path from $1$ to $n$ that uses every teleporter (arc)
  exactly once; print the $m+1$ vertices, or `IMPOSSIBLE`.
- **Thinking from first principles:** Directed trail conditions with fixed endpoints: $\text{out}(1) - \text{in}(1) = 1$,
  $\text{in}(n) - \text{out}(n) = 1$, everyone else balanced. Then Hierholzer from $1$; with those degrees a full trail must end at $n$.
  Unreachable arcs again show up as a short answer.

<details><summary>Solution</summary>

Degree check, directed Hierholzer from $1$, length check. $O(n + m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> head(n + 1, -1), nxt(m), to(m), indeg(n + 1, 0), outdeg(n + 1, 0);
    for (int i = 0; i < m; i++) {
        int a, b; cin >> a >> b;
        to[i] = b; nxt[i] = head[a]; head[a] = i;
        outdeg[a]++; indeg[b]++;
    }
    bool ok = outdeg[1] - indeg[1] == 1 && indeg[n] - outdeg[n] == 1;
    for (int v = 2; v < n && ok; v++) if (indeg[v] != outdeg[v]) ok = false;
    vector<int> path;
    if (ok) {
        vector<int> it = head, stk = {1};
        while (!stk.empty()) {
            int v = stk.back();
            if (it[v] == -1) { path.push_back(v); stk.pop_back(); }
            else { int a = it[v]; it[v] = nxt[a]; stk.push_back(to[a]); }
        }
        ok = (int)path.size() == m + 1;
    }
    if (!ok) { cout << "IMPOSSIBLE\n"; return 0; }
    reverse(path.begin(), path.end());
    for (int i = 0; i <= m; i++) cout << path[i] << " \n"[i == m];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int readByte() throws IOException { return in.read(); }
    static int nextInt() throws IOException {
        int b = readByte();
        while (b != '-' && (b < '0' || b > '9')) b = readByte();
        boolean neg = b == '-';
        if (neg) b = readByte();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = readByte(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] head = new int[n + 1], nxt = new int[m], to = new int[m], indeg = new int[n + 1], outdeg = new int[n + 1];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            int a = nextInt(), b = nextInt();
            to[i] = b; nxt[i] = head[a]; head[a] = i;
            outdeg[a]++; indeg[b]++;
        }
        boolean ok = outdeg[1] - indeg[1] == 1 && indeg[n] - outdeg[n] == 1;
        for (int v = 2; v < n && ok; v++) if (indeg[v] != outdeg[v]) ok = false;
        int[] path = new int[m + 1];
        int len = 0;
        if (ok) {
            int[] it = head.clone(), stk = new int[m + 1];
            int sp = 0;
            stk[sp++] = 1;
            while (sp > 0) {
                int v = stk[sp - 1];
                if (it[v] == -1) { path[len++] = v; sp--; }
                else { int a = it[v]; it[v] = nxt[a]; stk[sp++] = to[a]; }
            }
            ok = len == m + 1;
        }
        if (!ok) { System.out.println("IMPOSSIBLE"); return; }
        StringBuilder sb = new StringBuilder();
        for (int i = len - 1; i >= 0; i--) sb.append(path[i]).append(i == 0 ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5 6
1 2
2 3
3 1
1 4
4 5
5 1
out:
IMPOSSIBLE
-->
<!-- test
in:
4 5
1 2
2 3
3 1
1 4
2 1
out:
IMPOSSIBLE
-->
<!-- test
in:
4 5
1 2
2 3
3 1
1 4
3 3
out:
1 2 3 3 1 4
-->
<!-- test
in:
4 3
1 4
2 3
3 2
out:
IMPOSSIBLE
-->
<!-- test
in:
4 6
1 2
2 3
3 1
1 4
4 2
2 4
out:
1 4 2 3 1 2 4
-->
<!-- test
in:
2 1
1 2
out:
1 2
-->

### Example 3 — De Bruijn Sequence  ·  ★ ≈1900

- **Source:** [CSES 1692 · De Bruijn Sequence](https://cses.fi/problemset/task/1692)
- **Difficulty:** ≈1900 (est.)
- **Problem:** Given $n \le 15$, print a shortest bit string that contains every length-$n$ bit string as a substring.
- **Thinking from first principles:** Each of the $2^n$ words must start at a different position, so the length is at least
  $2^n + n - 1$. To achieve it, consecutive windows must overlap in $n - 1$ bits: a window is an *edge* from its first $n-1$ bits
  to its last $n-1$ bits. Every $(n-1)$-bit vertex has out-degree 2 and in-degree 2, and the graph is connected (shift in any target
  word bit by bit), so an Euler circuit exists. Walking it from $0^{n-1}$ and writing the appended bit of each edge yields the string.
  The graph is implicit: vertex $v$ has edges to $(2v + b) \bmod 2^{n-1}$ for $b \in \{0,1\}$.

<details><summary>Solution</summary>

Iterative Hierholzer on the implicit graph; the stack stores (vertex, bit used to enter it). Output $0^{n-1}$ followed by the
bits in circuit order. $O(2^n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int n;
    cin >> n;
    int V = 1 << (n - 1), mask = V - 1;
    vector<int> ptr(V, 0);                         // next bit to try at each vertex (0, 1, then exhausted)
    vector<pair<int,int>> stk = {{0, -1}};
    string bits;
    while (!stk.empty()) {
        auto [v, b] = stk.back();
        if (ptr[v] < 2) { int c = ptr[v]++; stk.push_back({((v << 1) | c) & mask, c}); }
        else { if (b >= 0) bits.push_back(char('0' + b)); stk.pop_back(); }
    }
    reverse(bits.begin(), bits.end());
    cout << string(n - 1, '0') + bits << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        int V = 1 << (n - 1), mask = V - 1, E = 1 << n;
        int[] ptr = new int[V], sv = new int[E + 1], sb = new int[E + 1];
        int sp = 0;
        sv[sp] = 0; sb[sp++] = -1;
        StringBuilder bits = new StringBuilder();
        while (sp > 0) {
            int v = sv[sp - 1], b = sb[sp - 1];
            if (ptr[v] < 2) { int c = ptr[v]++; sv[sp] = ((v << 1) | c) & mask; sb[sp++] = c; }
            else { if (b >= 0) bits.append((char) ('0' + b)); sp--; }
        }
        bits.reverse();
        StringBuilder out = new StringBuilder();
        for (int i = 0; i < n - 1; i++) out.append('0');
        out.append(bits);
        System.out.println(out);
    }
}
```

</details>

<!-- test
in:
1
out:
01
-->
<!-- test
in:
2
out:
00110
-->
<!-- test
in:
3
out:
0001011100
-->

### Example 4 — Tanya and Password  ·  ★ 2500

- **Source:** [CF 508D · Tanya and Password](https://codeforces.com/problemset/problem/508/D) — 2500
- **Difficulty:** 2500
- **Problem:** A password of length $n + 2$ (letters and digits, case-sensitive) produced $n \le 2\cdot10^5$ substrings of length 3,
  one per starting position, given in arbitrary order (with repetitions). Print `YES` and any password consistent with them, or `NO`.
- **Thinking from first principles:** Treating each triple as a vertex and asking for an order is Hamiltonian — hopeless. Instead,
  make every **2-character string a vertex** and every triple $abc$ an **edge** $ab \to bc$. Consecutive triples overlap in two
  characters, i.e. share a vertex, so a valid password is exactly a directed Euler trail using all $n$ edges. $62^2 = 3844$ vertices.
  Check: at most one vertex with $\text{out}-\text{in}=1$ (the start), at most one with $\text{in}-\text{out}=1$, the rest balanced;
  if all are balanced, start anywhere with outgoing edges (we use the first triple's prefix). Then Hierholzer and the length check.

<details><summary>Solution</summary>

Map characters to $0..61$, vertex $= 62\,c_1 + c_2$, edge label $= c_3$. The answer is the start vertex's two characters followed by
the labels in trail order. $O(n + 62^2)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int id(char c) { return isdigit(c) ? c - '0' : islower(c) ? 10 + c - 'a' : 36 + c - 'A'; }
char ch(int x) { return x < 10 ? char('0' + x) : x < 36 ? char('a' + x - 10) : char('A' + x - 36); }
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    const int V = 62 * 62;
    vector<int> head(V, -1), nxt(n), to(n), lab(n), indeg(V, 0), outdeg(V, 0);
    int first = -1;
    for (int i = 0; i < n; i++) {
        string s; cin >> s;
        int u = id(s[0]) * 62 + id(s[1]), w = id(s[1]) * 62 + id(s[2]);
        to[i] = w; lab[i] = id(s[2]); nxt[i] = head[u]; head[u] = i;
        outdeg[u]++; indeg[w]++;
        if (i == 0) first = u;
    }
    int start = first, plus = 0, minus = 0;
    bool ok = true;
    for (int v = 0; v < V; v++) {
        int d = outdeg[v] - indeg[v];
        if (d == 1) { plus++; start = v; }
        else if (d == -1) minus++;
        else if (d != 0) ok = false;
    }
    if (plus > 1 || minus > 1 || plus != minus) ok = false;
    string res;
    if (ok) {
        vector<int> it = head, stk = {-1}, cur = {start};   // stk: arc used to enter, cur: vertex
        vector<int> labels;
        while (!cur.empty()) {
            int v = cur.back();
            if (it[v] == -1) { if (stk.back() >= 0) labels.push_back(lab[stk.back()]); stk.pop_back(); cur.pop_back(); }
            else { int a = it[v]; it[v] = nxt[a]; stk.push_back(a); cur.push_back(to[a]); }
        }
        if ((int)labels.size() != n) ok = false;
        else {
            reverse(labels.begin(), labels.end());
            res += ch(start / 62); res += ch(start % 62);
            for (int x : labels) res += ch(x);
        }
    }
    if (!ok) cout << "NO\n";
    else cout << "YES\n" << res << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int id(char c) { return Character.isDigit(c) ? c - '0' : Character.isLowerCase(c) ? 10 + c - 'a' : 36 + c - 'A'; }
    static char ch(int x) { return x < 10 ? (char) ('0' + x) : x < 36 ? (char) ('a' + x - 10) : (char) ('A' + x - 36); }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in), 1 << 16);
        int n = Integer.parseInt(br.readLine().trim());
        final int V = 62 * 62;
        int[] head = new int[V], nxt = new int[n], to = new int[n], lab = new int[n], indeg = new int[V], outdeg = new int[V];
        Arrays.fill(head, -1);
        int first = -1;
        for (int i = 0; i < n; i++) {
            String s = br.readLine().trim();
            int u = id(s.charAt(0)) * 62 + id(s.charAt(1)), w = id(s.charAt(1)) * 62 + id(s.charAt(2));
            to[i] = w; lab[i] = id(s.charAt(2)); nxt[i] = head[u]; head[u] = i;
            outdeg[u]++; indeg[w]++;
            if (i == 0) first = u;
        }
        int start = first, plus = 0, minus = 0;
        boolean ok = true;
        for (int v = 0; v < V; v++) {
            int d = outdeg[v] - indeg[v];
            if (d == 1) { plus++; start = v; }
            else if (d == -1) minus++;
            else if (d != 0) ok = false;
        }
        if (plus > 1 || minus > 1 || plus != minus) ok = false;
        StringBuilder res = new StringBuilder();
        if (ok) {
            int[] it = head.clone(), stk = new int[n + 1], cur = new int[n + 1], labels = new int[n];
            int sp = 0, cnt = 0;
            stk[sp] = -1; cur[sp++] = start;
            while (sp > 0) {
                int v = cur[sp - 1];
                if (it[v] == -1) { if (stk[sp - 1] >= 0) labels[cnt++] = lab[stk[sp - 1]]; sp--; }
                else { int a = it[v]; it[v] = nxt[a]; stk[sp] = a; cur[sp++] = to[a]; }
            }
            if (cnt != n) ok = false;
            else {
                res.append(ch(start / 62)).append(ch(start % 62));
                for (int i = cnt - 1; i >= 0; i--) res.append(ch(labels[i]));
            }
        }
        System.out.println(ok ? "YES\n" + res : "NO");
    }
}
```

</details>

<!-- test
in:
5
aca
aba
aba
cab
bac
out:
YES
abacaba
-->
<!-- test
in:
4
abc
bCb
cb1
b13
out:
NO
-->
<!-- test
in:
7
aaa
aaa
aaa
aaa
aaa
aaa
aaa
out:
YES
aaaaaaaaa
-->
<!-- test
in:
2
abc
xyz
out:
NO
-->

### Example 5 — Fewest strokes to draw every edge  ·  ★ ≈1800

- **Source:** Original problem.
- **Difficulty:** ≈1800 (est.)
- **Problem:** An undirected multigraph ($n, m \le 2\cdot10^5$, self-loops allowed). Cover every edge exactly once with the
  smallest number of trails (pen strokes; a stroke may start and end anywhere). Print that number.
- **Thinking from first principles:** Components don't interact, so solve each one with at least one edge. If it has $2k$ odd
  vertices: every odd vertex must be an endpoint of some stroke (passing through a vertex uses edges in pairs), and a stroke
  has two endpoints, so at least $k$ strokes; and at least $1$ if $k = 0$. Achievability: pair the odd vertices with $k$ virtual
  edges; now an Euler circuit exists; deleting the $k$ virtual edges cuts the circuit into exactly $k$ trails (or keeps one circuit if $k=0$).
  Answer $=\sum_{\text{components with edges}} \max(1, k)$. A self-loop adds 2 to a degree and never changes parity.

<details><summary>Solution</summary>

DSU over endpoints, count odd vertices and edge presence per component. $O((n + m)\,\alpha(n))$.
Stress-tested against an exhaustive search over edge subsets on random multigraphs with $m \le 8$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> par(n + 1), deg(n + 1, 0);
    iota(par.begin(), par.end(), 0);
    auto find = [&](int x) { while (par[x] != x) x = par[x] = par[par[x]]; return x; };
    for (int i = 0; i < m; i++) {
        int a, b; cin >> a >> b;
        deg[a]++; deg[b]++;
        par[find(a)] = find(b);
    }
    vector<long long> odd(n + 1, 0);
    vector<char> hasEdge(n + 1, 0);
    for (int v = 1; v <= n; v++) {
        int r = find(v);
        if (deg[v] > 0) hasEdge[r] = 1;
        if (deg[v] % 2) odd[r]++;
    }
    long long ans = 0;
    for (int v = 1; v <= n; v++) if (find(v) == v && hasEdge[v]) ans += max(1LL, odd[v] / 2);
    cout << ans << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static int readByte() throws IOException { return in.read(); }
    static int nextInt() throws IOException {
        int b = readByte();
        while (b != '-' && (b < '0' || b > '9')) b = readByte();
        boolean neg = b == '-';
        if (neg) b = readByte();
        int r = 0;
        while (b >= '0' && b <= '9') { r = r * 10 + (b - '0'); b = readByte(); }
        return neg ? -r : r;
    }
    static int[] par;
    static int find(int x) { while (par[x] != x) x = par[x] = par[par[x]]; return x; }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        par = new int[n + 1];
        int[] deg = new int[n + 1];
        for (int i = 0; i <= n; i++) par[i] = i;
        for (int i = 0; i < m; i++) {
            int a = nextInt(), b = nextInt();
            deg[a]++; deg[b]++;
            par[find(a)] = find(b);
        }
        long[] odd = new long[n + 1];
        boolean[] hasEdge = new boolean[n + 1];
        for (int v = 1; v <= n; v++) {
            int r = find(v);
            if (deg[v] > 0) hasEdge[r] = true;
            if (deg[v] % 2 != 0) odd[r]++;
        }
        long ans = 0;
        for (int v = 1; v <= n; v++) if (find(v) == v && hasEdge[v]) ans += Math.max(1, odd[v] / 2);
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
4 3
1 2
1 3
1 4
out:
2
-->
<!-- test
in:
6 6
1 2
2 3
3 1
4 5
5 6
6 4
out:
2
-->
<!-- test
in:
3 1
2 2
out:
1
-->
<!-- test
in:
5 0
out:
0
-->
<!-- test
in:
6 5
1 2
1 3
1 4
1 5
1 6
out:
3
-->

## 6. Tricks, pitfalls and things to remember

1. **Check degrees before walking**, but rely on the $m + 1$ length check for connectivity — it is exact and costs nothing.
2. **Never rescan used edges.** A per-vertex pointer (`it[v]`) that only moves forward makes Hierholzer linear; restarting the scan
   from the head of the adjacency list is $O(m \cdot \deg)$ and times out on stars.
3. **Undirected edges appear twice:** mark `used[a >> 1]`, and skip used arcs when advancing the pointer.
4. **Recursion depth:** the recursive Hierholzer recurses up to $m$ deep ($2\cdot10^5$) — iterative or a big-stack thread in Java.
5. **The result is reversed** in the stack form; for a directed path you *must* reverse it (for undirected circuits either orientation is valid).
6. **Start vertex matters** for trails: the vertex with $\text{out} - \text{in} = 1$ (directed) or an odd vertex (undirected). Starting
   elsewhere silently produces a shorter sequence.
7. **Isolated vertices** don't break Eulerian-ness; connectivity is about vertices that have edges.
8. **Self-loops** count 2 toward an undirected degree (1 in, 1 out when directed). Make sure the arc representation handles them.
9. **De Bruijn for $n = 1$**: the graph is one vertex with two self-loops; the code above handles it without a special case (output `01`).
10. **Lexicographically smallest Euler path** (LC 332): sort adjacency lists and still use Hierholzer; greedy "take the smallest edge
    that is not a bridge" (Fleury) is $O(m^2)$ and unnecessary.
11. **Java I/O for strings** (CF 508D): read lines with a `BufferedReader`; `Scanner` on $2\cdot10^5$ tokens costs ~1 s.

## 7. Going further (toward 2400–2600+)

- **Edge orientation / balanced coloring** with the virtual vertex: [CF 723E · One-Way Reform](https://codeforces.com/problemset/problem/723/E) — 2200
  (maximise vertices with $\text{in} = \text{out}$: exactly the even-degree ones), [CF 547D · Mike and Fish](https://codeforces.com/problemset/problem/547/D) — 2600
  (bipartite rows × columns, balance colors), [CF 1186F · Vus the Cossack and a Graph](https://codeforces.com/problemset/problem/1186/F) — 2400
  (delete every second edge along an Euler circuit).
- **Making a graph Eulerian with extra edges:** [CF 527E · Data Center Drama](https://codeforces.com/problemset/problem/527/E) — 2600 (pair odd vertices, fix the parity of $m$ with a self-loop).
- **Euler paths over values:** [CF 1152E · Neko and Flashback](https://codeforces.com/problemset/problem/1152/E) — 2400,
  [CF 1361C · Johnny and Megan's Necklace](https://codeforces.com/problemset/problem/1361/C) — 2500 (binary search on the answer + Euler circuit on residues).
- **Counting:** BEST theorem with the matrix-tree theorem; number of Eulerian subgraphs $2^{m-n+c}$ ([CSES 2078 · Eulerian Subgraphs](https://cses.fi/problemset/task/2078)).
- **Chinese postman with few odd vertices:** [CF 21D · Traveling Graph](https://codeforces.com/problemset/problem/21/D) — 2400 (Floyd–Warshall + bitmask matching).
  The directed version is a min-cost flow on the imbalances ([min-cost flow](../12-Flows-and-Matching/04-min-cost-flow.md)).

## 8. Practice ladder

**1700–2100**
- [ ] [CSES 1691 · Mail Delivery](https://cses.fi/problemset/task/1691) — undirected circuit
- [ ] [CSES 1693 · Teleporters Path](https://cses.fi/problemset/task/1693) — directed path
- [ ] [CSES 1692 · De Bruijn Sequence](https://cses.fi/problemset/task/1692) — implicit graph
- [ ] [CF 1334D · Minimum Euler Cycle](https://codeforces.com/problemset/problem/1334/D) — 1800 — lexicographically smallest circuit of $K_n$, print a segment
- [ ] [CF 788B · Weird journey](https://codeforces.com/problemset/problem/788/B) — 2100 — count edge pairs that make degrees work (self-loops!)
- [ ] [AtCoder ABC286 G · Unique Walk](https://atcoder.jp/contests/abc286/tasks/abc286_g) — ≈2135 (est.) — contract free edges, count odd components

**2100–2400**
- [ ] [CF 723E · One-Way Reform](https://codeforces.com/problemset/problem/723/E) — 2200 — virtual vertex
- [ ] [AtCoder AGC032 C · Three Circuits](https://atcoder.jp/contests/agc032/tasks/agc032_c) — ≈2284 (est.) — degree case analysis
- [ ] [CF 1152E · Neko and Flashback](https://codeforces.com/problemset/problem/1152/E) — 2400 — values as vertices
- [ ] [CF 1186F · Vus the Cossack and a Graph](https://codeforces.com/problemset/problem/1186/F) — 2400 — alternate deletion along a circuit
- [ ] [CF 21D · Traveling Graph](https://codeforces.com/problemset/problem/21/D) — 2400 — Chinese postman

**2400+**
- [ ] [CF 508D · Tanya and Password](https://codeforces.com/problemset/problem/508/D) — 2500 — 2-grams as vertices
- [ ] [CF 1361C · Johnny and Megan's Necklace](https://codeforces.com/problemset/problem/1361/C) — 2500 — binary search + Euler circuit
- [ ] [CF 527E · Data Center Drama](https://codeforces.com/problemset/problem/527/E) — 2600 — make everything even, then orient
- [ ] [CF 547D · Mike and Fish](https://codeforces.com/problemset/problem/547/D) — 2600 — balanced bipartite coloring

## 9. LeetCode / FAANG cross-reference

- [LC 332 · Reconstruct Itinerary](https://leetcode.com/problems/reconstruct-itinerary/) — Hard — directed Euler path from "JFK", lexicographically smallest: sort adjacency, Hierholzer, reverse.
- [LC 753 · Cracking the Safe](https://leetcode.com/problems/cracking-the-safe/) — Hard — de Bruijn sequence over $k$ digits.
- [LC 2097 · Valid Arrangement of Pairs](https://leetcode.com/problems/valid-arrangement-of-pairs/) — Hard — pairs are edges between values; start at the vertex with $\text{out}-\text{in}=1$.

Euler problems are a known "hard" interview category: the expected answer is Hierholzer with a clear explanation of the degree conditions.

## 10. Self-check

1. State the conditions for an undirected Euler trail that is not a circuit.
2. Why can the greedy walk of a circuit only get stuck at its start vertex?
3. In the stack form of Hierholzer, when is a vertex appended to the answer, and why is the answer reversed?
4. How do you detect "edges in more than one component" without a separate DSU?
5. Why is "restore a string from its 3-letter substrings" an Euler problem and not a Hamiltonian one?
6. What is the length of a binary de Bruijn sequence for $n$, and why can't it be shorter?
7. Explain how to orient the edges of any undirected graph so that $|\text{in} - \text{out}| \le 1$ at every vertex.
8. How many strokes are needed to draw a star with 5 leaves, and why?

<details><summary>Answers</summary>

1. Exactly two vertices of odd degree, all edges in one connected component; the trail runs between the two odd vertices.
2. Entering any other vertex $v$ leaves an odd number of its edges used; $\deg(v)$ is even, so an unused edge remains.
3. When it has no unused edge left. Vertices are emitted when the walk "backs out", i.e. from the end of the trail to its start.
4. Check that the produced sequence has $m + 1$ vertices; any unreachable edge makes it shorter.
5. Make 2-letter strings the vertices and triples the edges; consecutive triples share a vertex. Using every triple once is using every edge once.
6. $2^n + n - 1$: each of the $2^n$ words needs a distinct start position, and the last start position is at index $\ge 2^n - 1$, so length $\ge 2^n + n - 1$.
7. Join a new vertex to every odd vertex, take an Euler circuit of each component, orient edges along it, drop the new edges; each real vertex loses at most one edge from a balanced state.
8. Three: 6 odd vertices (5 leaves of degree 1 and the center of degree 5), so $6/2 = 3$ trails.

</details>
