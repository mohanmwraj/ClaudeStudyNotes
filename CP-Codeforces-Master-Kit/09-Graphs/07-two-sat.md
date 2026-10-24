# 2-SAT

> **Band:** 🟣 1900 → 🟠 2400 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [SCC and condensation](05-scc-and-condensation.md), [DFS](01-graph-representation-bfs-dfs.md)
> **You can say you know this when:** you can translate "each object has two options, some pairs of options are incompatible" into an implication graph in a few minutes, prove why "$x$ and $\neg x$ in different SCCs" is sufficient, read off an assignment from Tarjan's component ids, and encode XOR, equality and at-most-one constraints without blowing up the graph.

## 1. First principles — why this works

**The problem.** $n$ Boolean variables, $m$ clauses, each clause an OR of **two** literals ($x_i$ or $\neg x_i$). Is there an
assignment satisfying all clauses? With three literals per clause this is 3-SAT (NP-complete); with two it is linear time.

**Naive idea and why it is slow.** Try all $2^n$ assignments. Better: pick an unassigned variable, set it, and *propagate*:
a clause $(a \lor b)$ with $a$ false forces $b$ true. In 2-CNF every forced step is a single literal, so propagation never
branches. If propagation from "$x = 1$" hits a contradiction, $x$ must be $0$; set it and propagate. This already gives an
$O(n\,m)$ algorithm. The SCC algorithm is the same reasoning done for all variables at once.

**Clauses are implications.** $(a \lor b)$ is equivalent to $(\neg a \Rightarrow b)$ and to $(\neg b \Rightarrow a)$.
Build the **implication graph** on $2n$ literal nodes with both arcs for every clause. A path $u \leadsto v$ means "if $u$ is
true then $v$ is true" in every satisfying assignment. The graph is **skew-symmetric**: $u \to v$ is an arc iff $\neg v \to \neg u$ is
(each clause adds a contrapositive pair), so $u \leadsto v$ iff $\neg v \leadsto \neg u$.

**Necessity.** If $x$ and $\neg x$ are in one SCC, then $x \Rightarrow \neg x$ and $\neg x \Rightarrow x$: both values of $x$ are
contradictory. Unsatisfiable.

**Sufficiency, with an explicit assignment.** Suppose no variable shares an SCC with its negation. Contract SCCs into the
condensation DAG and take a topological order `topo`. Set

$$x = \text{true} \iff \text{topo}(\text{comp}(x)) > \text{topo}(\text{comp}(\neg x)),$$

i.e. choose the literal that is "later", closer to the sinks. *Proof that every clause $(a \lor b)$ holds:* suppose both $a$ and $b$
are false. Then $\text{topo}(a) < \text{topo}(\neg a)$ and $\text{topo}(b) < \text{topo}(\neg b)$ (comparing their components).
The clause gives arcs $\neg a \to b$ and $\neg b \to a$, and arcs never go backwards in a topological order, so
$\text{topo}(\neg a) \le \text{topo}(b)$ and $\text{topo}(\neg b) \le \text{topo}(a)$. Chaining:
$\text{topo}(a) < \text{topo}(\neg a) \le \text{topo}(b) < \text{topo}(\neg b) \le \text{topo}(a)$, a contradiction. ∎

Intuition: a literal late in the order implies few things (only things even later), so setting it true is "cheap"; its negation,
early in the order, may imply a lot, but it is set false and false premises imply nothing.

**Reading the order off an SCC algorithm.** Tarjan's algorithm completes SCCs in **reverse** topological order (the first
SCC popped is a sink of the condensation). So with Tarjan ids, $x = \text{true} \iff \text{id}(x) < \text{id}(\neg x)$.
Kosaraju's second pass discovers SCCs in topological order, so there the comparison flips. Getting this backwards produces
assignments that violate clauses — test on a forcing clause like $(x \lor x)$.

**Complexity.** $2n$ nodes, $2m$ arcs, one SCC pass: $O(n + m)$.

## 2. Formulas, definitions and identities

Literal encoding used below: variable $x \in [0, n)$, node $2x$ = "$x$ is true", node $2x+1$ = "$x$ is false"; negation is `^ 1`.

| Constraint | Clauses | Arcs |
|---|---|---|
| $a \lor b$ | $(a \lor b)$ | $\neg a \to b$, $\neg b \to a$ |
| force $a$ | $(a \lor a)$ | $\neg a \to a$ |
| $a \Rightarrow b$ | $(\neg a \lor b)$ | $a \to b$, $\neg b \to \neg a$ |
| not both ($\text{NAND}$) | $(\neg a \lor \neg b)$ | $a \to \neg b$, $b \to \neg a$ |
| $a \oplus b$ (exactly one) | $(a \lor b) \land (\neg a \lor \neg b)$ | 4 arcs |
| $a \Leftrightarrow b$ | $(\neg a \lor b) \land (a \lor \neg b)$ | 4 arcs |
| at least two of $a, b, c$ | $(a\lor b)\land(a\lor c)\land(b\lor c)$ | 6 arcs |
| at most one of $\ell_1..\ell_k$ (pairwise) | $(\neg\ell_i \lor \neg\ell_j)\ \forall i<j$ | $O(k^2)$ |
| at most one of $\ell_1..\ell_k$ (prefix) | new $p_i$: $\ell_i \Rightarrow p_i$, $p_{i-1} \Rightarrow p_i$, $p_{i-1} \Rightarrow \neg\ell_i$ | $O(k)$ |
| exactly one of $k \ge 3$ literals | needs the $k$-clause $\ell_1 \lor \dots \lor \ell_k$ | **not expressible** in 2-CNF in general |

*Prefix at-most-one proof.* If $\ell_i$ and $\ell_j$ ($i<j$) were both true: $\ell_i \Rightarrow p_i \Rightarrow \dots \Rightarrow p_{j-1} \Rightarrow \neg\ell_j$.
Conversely with at most one true literal, $p_i := \ell_1 \lor \dots \lor \ell_i$ satisfies all three clause families.

Other facts:
- Satisfiable $\iff \forall x: \text{comp}(x) \ne \text{comp}(\neg x)$; assignment $x = [\text{topo}(x) > \text{topo}(\neg x)]$.
- If $x \leadsto \neg x$ (but not back), then $x$ is false in **every** solution; this is how to find forced variables (one DFS from $x$ per variable, $O(n+m)$ each; for all variables at once use bitset reachability on the condensation, $O(n\,m/64)$).
- Counting satisfying assignments of 2-CNF is #P-complete; the lexicographically smallest assignment can be found greedily in $O(n(n+m))$ with propagation (try $x_1 = 0$, propagate, keep if no contradiction).
- Time $O(n + m)$, memory $O(n + m)$.

## 3. Implementation (C++ and Java)

API: `addOr(a, va, b, vb)` adds the clause "$x_a = va$ or $x_b = vb$". Everything else is sugar on top of it.
Tarjan is iterative (an explicit call stack with a per-node edge iterator), so $2n = 2\cdot10^6$ nodes is safe.

```cpp
struct TwoSat {
    int n;
    vector<vector<int>> g;
    vector<char> value;
    explicit TwoSat(int n) : n(n), g(2 * n) {}
    static int lit(int x, bool val) { return 2 * x + (val ? 0 : 1); }
    void addOr(int a, bool va, int b, bool vb) {
        int A = lit(a, va), B = lit(b, vb);
        g[A ^ 1].push_back(B);                       // not A  ->  B
        g[B ^ 1].push_back(A);                       // not B  ->  A  (contrapositive keeps the graph skew-symmetric)
    }
    void force(int a, bool va) { addOr(a, va, a, va); }
    void addImplies(int a, bool va, int b, bool vb) { addOr(a, !va, b, vb); }
    void addXor(int a, int b) { addOr(a, true, b, true); addOr(a, false, b, false); }
    void addEqual(int a, int b) { addOr(a, false, b, true); addOr(a, true, b, false); }
    int newVar() { g.emplace_back(); g.emplace_back(); return n++; }
    void atMostOne(const vector<pair<int,bool>>& lits) {     // prefix encoding, O(k) clauses
        int prev = -1;
        for (auto [x, vx] : lits) {
            int p = newVar();
            addImplies(x, vx, p, true);
            if (prev != -1) { addImplies(prev, true, p, true); addImplies(prev, true, x, !vx); }
            prev = p;
        }
    }
    bool solve() {
        int N = 2 * n, timer = 0, C = 0;
        vector<int> idx(N, -1), low(N), comp(N, -1), it(N, 0), stk, call;
        for (int s = 0; s < N; s++) {
            if (idx[s] != -1) continue;
            idx[s] = low[s] = timer++; stk.push_back(s); call.push_back(s);
            while (!call.empty()) {
                int v = call.back();
                if (it[v] < (int)g[v].size()) {
                    int w = g[v][it[v]++];
                    if (idx[w] == -1) { idx[w] = low[w] = timer++; stk.push_back(w); call.push_back(w); }
                    else if (comp[w] == -1) low[v] = min(low[v], idx[w]);   // w still on the Tarjan stack
                } else {
                    call.pop_back();
                    if (!call.empty()) low[call.back()] = min(low[call.back()], low[v]);
                    if (low[v] == idx[v]) {
                        while (true) { int w = stk.back(); stk.pop_back(); comp[w] = C; if (w == v) break; }
                        C++;
                    }
                }
            }
        }
        value.assign(n, 0);
        for (int x = 0; x < n; x++) {
            if (comp[2 * x] == comp[2 * x + 1]) return false;
            value[x] = comp[2 * x] < comp[2 * x + 1];    // Tarjan ids are a REVERSE topological order
        }
        return true;
    }
};
```

```java
static class TwoSat {
    int n, m = 0;
    int[] eu = new int[16], ev = new int[16];
    boolean[] value;
    TwoSat(int n) { this.n = n; }
    static int lit(int x, boolean val) { return 2 * x + (val ? 0 : 1); }
    void arc(int a, int b) {
        if (m == eu.length) { eu = Arrays.copyOf(eu, 2 * m); ev = Arrays.copyOf(ev, 2 * m); }
        eu[m] = a; ev[m++] = b;
    }
    void addOr(int a, boolean va, int b, boolean vb) {
        int A = lit(a, va), B = lit(b, vb);
        arc(A ^ 1, B); arc(B ^ 1, A);
    }
    void force(int a, boolean va) { addOr(a, va, a, va); }
    void addImplies(int a, boolean va, int b, boolean vb) { addOr(a, !va, b, vb); }
    void addXor(int a, int b) { addOr(a, true, b, true); addOr(a, false, b, false); }
    void addEqual(int a, int b) { addOr(a, false, b, true); addOr(a, true, b, false); }
    int newVar() { return n++; }
    void atMostOne(int[] xs, boolean[] vs) {
        int prev = -1;
        for (int i = 0; i < xs.length; i++) {
            int p = newVar();
            addImplies(xs[i], vs[i], p, true);
            if (prev != -1) { addImplies(prev, true, p, true); addImplies(prev, true, xs[i], !vs[i]); }
            prev = p;
        }
    }
    boolean solve() {
        int N = 2 * n;
        int[] head = new int[N], nxt = new int[m];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) { nxt[i] = head[eu[i]]; head[eu[i]] = i; }
        int[] idx = new int[N], low = new int[N], comp = new int[N], it = new int[N], stk = new int[N], call = new int[N];
        Arrays.fill(idx, -1); Arrays.fill(comp, -1);
        int timer = 0, C = 0, sp = 0;
        for (int s = 0; s < N; s++) {
            if (idx[s] != -1) continue;
            int cp = 0;
            idx[s] = low[s] = timer++; stk[sp++] = s; it[s] = head[s]; call[cp++] = s;
            while (cp > 0) {
                int v = call[cp - 1];
                if (it[v] != -1) {
                    int e = it[v]; it[v] = nxt[e]; int w = ev[e];
                    if (idx[w] == -1) { idx[w] = low[w] = timer++; stk[sp++] = w; it[w] = head[w]; call[cp++] = w; }
                    else if (comp[w] == -1) low[v] = Math.min(low[v], idx[w]);
                } else {
                    cp--;
                    if (cp > 0) low[call[cp - 1]] = Math.min(low[call[cp - 1]], low[v]);
                    if (low[v] == idx[v]) { while (true) { int w = stk[--sp]; comp[w] = C; if (w == v) break; } C++; }
                }
            }
        }
        value = new boolean[n];
        for (int x = 0; x < n; x++) {
            if (comp[2 * x] == comp[2 * x + 1]) return false;
            value[x] = comp[2 * x] < comp[2 * x + 1];
        }
        return true;
    }
}
```

## 4. Recognising the pattern

| Statement signal | Think |
|---|---|
| every object picks one of **two** options; some option pairs conflict | variable per object, NAND clause per conflict |
| "if A is chosen then B must be", "at least one of these two" | implications / OR clauses |
| switches/toggles where each target depends on **exactly two** switches | XOR / equality clauses (or DSU with parity) |
| "assign each of $n$ intervals/chords to side 1 or side 2 so no two on the same side cross" | 2-SAT (crossing pairs → XOR) or bipartiteness |
| maximise the minimum distance / minimise the maximum conflict with binary choices | binary search on the answer + 2-SAT check |
| a grid where each row/column can be flipped | 2-SAT or parity DSU |
| three or more options per object | usually **not** 2-SAT (graph 3-coloring is NP-hard) unless the structure collapses to two |
| "exactly one of $k$ things" for $k \ge 3$ | not 2-SAT; look for matching/flow instead |

Confusions: bipartite 2-coloring is the special case "all clauses are XOR" ([bipartite graphs](09-bipartite-graphs-and-cycles.md));
DSU with parity handles pure XOR/equality systems faster ([DSU](../08-Data-Structures/06-dsu-and-variants.md)).

## 5. Worked examples (graded)

### Example 1 — Giant Pizza  ·  ★ ≈1900

- **Source:** [CSES 1684 · Giant Pizza](https://cses.fi/problemset/task/1684)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $m \le 10^5$ toppings, $n \le 10^5$ family members. Each member states two wishes of the form "topping $x$ on"
  (`+ x`) or "topping $x$ off" (`- x`) and is happy if at least one wish holds. Print a `+`/`-` string for the toppings that
  makes everyone happy, or `IMPOSSIBLE`. (Any valid string is accepted; ours is the SCC assignment. The tests have a unique answer.)
- **Thinking from first principles:** Each member is literally a 2-clause; this is the textbook instance. The only work is
  parsing the signs and remembering the contrapositive arc.

<details><summary>Solution</summary>

One variable per topping, one `addOr` per member, Tarjan, read the assignment. $O(n + m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct TwoSat {
    int n;
    vector<vector<int>> g;
    vector<char> value;
    explicit TwoSat(int n) : n(n), g(2 * n) {}
    static int lit(int x, bool val) { return 2 * x + (val ? 0 : 1); }
    void addOr(int a, bool va, int b, bool vb) {
        int A = lit(a, va), B = lit(b, vb);
        g[A ^ 1].push_back(B);
        g[B ^ 1].push_back(A);
    }
    bool solve() {
        int N = 2 * n, timer = 0, C = 0;
        vector<int> idx(N, -1), low(N), comp(N, -1), it(N, 0), stk, call;
        for (int s = 0; s < N; s++) {
            if (idx[s] != -1) continue;
            idx[s] = low[s] = timer++; stk.push_back(s); call.push_back(s);
            while (!call.empty()) {
                int v = call.back();
                if (it[v] < (int)g[v].size()) {
                    int w = g[v][it[v]++];
                    if (idx[w] == -1) { idx[w] = low[w] = timer++; stk.push_back(w); call.push_back(w); }
                    else if (comp[w] == -1) low[v] = min(low[v], idx[w]);
                } else {
                    call.pop_back();
                    if (!call.empty()) low[call.back()] = min(low[call.back()], low[v]);
                    if (low[v] == idx[v]) {
                        while (true) { int w = stk.back(); stk.pop_back(); comp[w] = C; if (w == v) break; }
                        C++;
                    }
                }
            }
        }
        value.assign(n, 0);
        for (int x = 0; x < n; x++) {
            if (comp[2 * x] == comp[2 * x + 1]) return false;
            value[x] = comp[2 * x] < comp[2 * x + 1];
        }
        return true;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    TwoSat ts(m);
    for (int i = 0; i < n; i++) {
        char c1, c2; int x1, x2;
        cin >> c1 >> x1 >> c2 >> x2;
        ts.addOr(x1 - 1, c1 == '+', x2 - 1, c2 == '+');
    }
    if (!ts.solve()) { cout << "IMPOSSIBLE\n"; return 0; }
    string s(m, '-');
    for (int x = 0; x < m; x++) if (ts.value[x]) s[x] = '+';
    cout << s << "\n";
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
    static char nextSign() throws IOException {              // reads the next '+' or '-'
        int b = readByte();
        while (b != '+' && b != '-') b = readByte();
        return (char) b;
    }

    static class TwoSat {
        int n, m = 0;
        int[] eu = new int[16], ev = new int[16];
        boolean[] value;
        TwoSat(int n) { this.n = n; }
        static int lit(int x, boolean val) { return 2 * x + (val ? 0 : 1); }
        void arc(int a, int b) {
            if (m == eu.length) { eu = Arrays.copyOf(eu, 2 * m); ev = Arrays.copyOf(ev, 2 * m); }
            eu[m] = a; ev[m++] = b;
        }
        void addOr(int a, boolean va, int b, boolean vb) {
            int A = lit(a, va), B = lit(b, vb);
            arc(A ^ 1, B); arc(B ^ 1, A);
        }
        boolean solve() {
            int N = 2 * n;
            int[] head = new int[N], nxt = new int[m];
            Arrays.fill(head, -1);
            for (int i = 0; i < m; i++) { nxt[i] = head[eu[i]]; head[eu[i]] = i; }
            int[] idx = new int[N], low = new int[N], comp = new int[N], it = new int[N], stk = new int[N], call = new int[N];
            Arrays.fill(idx, -1); Arrays.fill(comp, -1);
            int timer = 0, C = 0, sp = 0;
            for (int s = 0; s < N; s++) {
                if (idx[s] != -1) continue;
                int cp = 0;
                idx[s] = low[s] = timer++; stk[sp++] = s; it[s] = head[s]; call[cp++] = s;
                while (cp > 0) {
                    int v = call[cp - 1];
                    if (it[v] != -1) {
                        int e = it[v]; it[v] = nxt[e]; int w = ev[e];
                        if (idx[w] == -1) { idx[w] = low[w] = timer++; stk[sp++] = w; it[w] = head[w]; call[cp++] = w; }
                        else if (comp[w] == -1) low[v] = Math.min(low[v], idx[w]);
                    } else {
                        cp--;
                        if (cp > 0) low[call[cp - 1]] = Math.min(low[call[cp - 1]], low[v]);
                        if (low[v] == idx[v]) { while (true) { int w = stk[--sp]; comp[w] = C; if (w == v) break; } C++; }
                    }
                }
            }
            value = new boolean[n];
            for (int x = 0; x < n; x++) {
                if (comp[2 * x] == comp[2 * x + 1]) return false;
                value[x] = comp[2 * x] < comp[2 * x + 1];
            }
            return true;
        }
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        TwoSat ts = new TwoSat(m);
        for (int i = 0; i < n; i++) {
            char c1 = nextSign(); int x1 = nextInt();
            char c2 = nextSign(); int x2 = nextInt();
            ts.addOr(x1 - 1, c1 == '+', x2 - 1, c2 == '+');
        }
        if (!ts.solve()) { System.out.println("IMPOSSIBLE"); return; }
        StringBuilder sb = new StringBuilder();
        for (int x = 0; x < m; x++) sb.append(ts.value[x] ? '+' : '-');
        System.out.println(sb);
    }
}
```

</details>

<!-- test
in:
3 3
+ 1 + 1
- 1 + 2
- 2 - 3
out:
++-
-->
<!-- test
in:
2 1
+ 1 + 1
- 1 - 1
out:
IMPOSSIBLE
-->
<!-- test
in:
1 1
- 1 - 1
out:
-
-->
<!-- test
in:
5 3
+ 1 + 2
- 1 - 2
+ 2 + 3
- 2 - 3
+ 3 + 3
out:
+-+
-->

### Example 2 — The Door Problem  ·  ★ 2000

- **Source:** [CF 776D · The Door Problem](https://codeforces.com/problemset/problem/776/D) — 2000
- **Difficulty:** 2000
- **Problem:** $n$ doors, each currently locked ($0$) or unlocked ($1$); $m$ switches, switch $i$ toggles a given list of doors;
  every door is controlled by exactly two switches ($n, m \le 10^5$). Input: `n m`, the $n$ states, then for each switch its count
  followed by its doors. Can some set of switch presses unlock all doors at once? Print `YES`/`NO`.
- **Thinking from first principles:** Pressing a switch twice is useless, so each switch is a Boolean $s_i$. Door $d$ with
  controllers $a, b$ ends unlocked iff $r_d \oplus s_a \oplus s_b = 1$, i.e. $s_a \oplus s_b = 1 - r_d$. Each door is an XOR or an
  equality between two variables: exactly the 2-SAT encodings above. (A parity DSU solves it too; 2-SAT generalises when mixed clauses appear.)

<details><summary>Solution</summary>

Collect the two switches of each door, add `addXor` when the door is locked and `addEqual` when it is unlocked, solve. $O(n + m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct TwoSat {
    int n;
    vector<vector<int>> g;
    explicit TwoSat(int n) : n(n), g(2 * n) {}
    static int lit(int x, bool val) { return 2 * x + (val ? 0 : 1); }
    void addOr(int a, bool va, int b, bool vb) {
        int A = lit(a, va), B = lit(b, vb);
        g[A ^ 1].push_back(B);
        g[B ^ 1].push_back(A);
    }
    void addXor(int a, int b) { addOr(a, true, b, true); addOr(a, false, b, false); }
    void addEqual(int a, int b) { addOr(a, false, b, true); addOr(a, true, b, false); }
    bool solve() {
        int N = 2 * n, timer = 0, C = 0;
        vector<int> idx(N, -1), low(N), comp(N, -1), it(N, 0), stk, call;
        for (int s = 0; s < N; s++) {
            if (idx[s] != -1) continue;
            idx[s] = low[s] = timer++; stk.push_back(s); call.push_back(s);
            while (!call.empty()) {
                int v = call.back();
                if (it[v] < (int)g[v].size()) {
                    int w = g[v][it[v]++];
                    if (idx[w] == -1) { idx[w] = low[w] = timer++; stk.push_back(w); call.push_back(w); }
                    else if (comp[w] == -1) low[v] = min(low[v], idx[w]);
                } else {
                    call.pop_back();
                    if (!call.empty()) low[call.back()] = min(low[call.back()], low[v]);
                    if (low[v] == idx[v]) {
                        while (true) { int w = stk.back(); stk.pop_back(); comp[w] = C; if (w == v) break; }
                        C++;
                    }
                }
            }
        }
        for (int x = 0; x < n; x++) if (comp[2 * x] == comp[2 * x + 1]) return false;
        return true;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> r(n);
    for (auto& x : r) cin >> x;
    vector<vector<int>> ctrl(n);
    for (int i = 0; i < m; i++) {
        int k; cin >> k;
        while (k--) { int d; cin >> d; ctrl[d - 1].push_back(i); }
    }
    TwoSat ts(m);
    for (int d = 0; d < n; d++) {
        int a = ctrl[d][0], b = ctrl[d][1];
        if (r[d] == 1) ts.addEqual(a, b);    // already unlocked: press both or neither
        else ts.addXor(a, b);                // locked: press exactly one
    }
    cout << (ts.solve() ? "YES" : "NO") << "\n";
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

    static class TwoSat {
        int n, m = 0;
        int[] eu = new int[16], ev = new int[16];
        TwoSat(int n) { this.n = n; }
        static int lit(int x, boolean val) { return 2 * x + (val ? 0 : 1); }
        void arc(int a, int b) {
            if (m == eu.length) { eu = Arrays.copyOf(eu, 2 * m); ev = Arrays.copyOf(ev, 2 * m); }
            eu[m] = a; ev[m++] = b;
        }
        void addOr(int a, boolean va, int b, boolean vb) {
            int A = lit(a, va), B = lit(b, vb);
            arc(A ^ 1, B); arc(B ^ 1, A);
        }
        void addXor(int a, int b) { addOr(a, true, b, true); addOr(a, false, b, false); }
        void addEqual(int a, int b) { addOr(a, false, b, true); addOr(a, true, b, false); }
        boolean solve() {
            int N = 2 * n;
            int[] head = new int[N], nxt = new int[m];
            Arrays.fill(head, -1);
            for (int i = 0; i < m; i++) { nxt[i] = head[eu[i]]; head[eu[i]] = i; }
            int[] idx = new int[N], low = new int[N], comp = new int[N], it = new int[N], stk = new int[N], call = new int[N];
            Arrays.fill(idx, -1); Arrays.fill(comp, -1);
            int timer = 0, C = 0, sp = 0;
            for (int s = 0; s < N; s++) {
                if (idx[s] != -1) continue;
                int cp = 0;
                idx[s] = low[s] = timer++; stk[sp++] = s; it[s] = head[s]; call[cp++] = s;
                while (cp > 0) {
                    int v = call[cp - 1];
                    if (it[v] != -1) {
                        int e = it[v]; it[v] = nxt[e]; int w = ev[e];
                        if (idx[w] == -1) { idx[w] = low[w] = timer++; stk[sp++] = w; it[w] = head[w]; call[cp++] = w; }
                        else if (comp[w] == -1) low[v] = Math.min(low[v], idx[w]);
                    } else {
                        cp--;
                        if (cp > 0) low[call[cp - 1]] = Math.min(low[call[cp - 1]], low[v]);
                        if (low[v] == idx[v]) { while (true) { int w = stk[--sp]; comp[w] = C; if (w == v) break; } C++; }
                    }
                }
            }
            for (int x = 0; x < n; x++) if (comp[2 * x] == comp[2 * x + 1]) return false;
            return true;
        }
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt();
        int[] r = new int[n];
        for (int i = 0; i < n; i++) r[i] = nextInt();
        int[][] ctrl = new int[n][2];
        int[] cnt = new int[n];
        for (int i = 0; i < m; i++) {
            int k = nextInt();
            for (int j = 0; j < k; j++) { int d = nextInt() - 1; ctrl[d][cnt[d]++] = i; }
        }
        TwoSat ts = new TwoSat(m);
        for (int d = 0; d < n; d++) {
            if (r[d] == 1) ts.addEqual(ctrl[d][0], ctrl[d][1]);
            else ts.addXor(ctrl[d][0], ctrl[d][1]);
        }
        System.out.println(ts.solve() ? "YES" : "NO");
    }
}
```

</details>

<!-- test
in:
2 2
0 0
2 1 2
2 1 2
out:
YES
-->
<!-- test
in:
2 2
0 1
2 1 2
2 1 2
out:
NO
-->
<!-- test
in:
3 3
0 0 0
2 1 2
2 2 3
2 1 3
out:
NO
-->
<!-- test
in:
3 3
0 0 1
2 1 2
2 2 3
2 1 3
out:
YES
-->

### Example 3 — ±1  ·  ★ 2100

- **Source:** [CF 1971H · ±1](https://codeforces.com/problemset/problem/1971/H) — 2100
- **Difficulty:** 2100
- **Problem:** A $3 \times n$ grid; each cell holds $a_x$ (written as $x > 0$) or $-a_x$ (written as $-x$) for some
  $1 \le x \le n$. Alice chooses every $a_x \in \{-1, 1\}$, then every column is sorted. Alice wins if the middle row is all $1$.
  For each of $t$ test cases ($n \le 500$) print `YES` if Alice can win.
- **Thinking from first principles:** The middle of three sorted $\pm1$ values is $1$ iff **at least two** of them are $1$.
  Let variable $x$ mean $a_x = 1$; a cell $x$ is the literal $x$, a cell $-x$ is $\neg x$. "At least two of $\ell_1, \ell_2, \ell_3$"
  is exactly $(\ell_1 \lor \ell_2) \land (\ell_1 \lor \ell_3) \land (\ell_2 \lor \ell_3)$: if two literals were false, the clause on that pair fails.
  So the game is a 2-SAT instance with $3n$ clauses.

<details><summary>Solution</summary>

For each column add the three pair clauses; answer `YES` iff satisfiable. $O(n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct TwoSat {
    int n;
    vector<vector<int>> g;
    explicit TwoSat(int n) : n(n), g(2 * n) {}
    static int lit(int x, bool val) { return 2 * x + (val ? 0 : 1); }
    void addOr(int a, bool va, int b, bool vb) {
        int A = lit(a, va), B = lit(b, vb);
        g[A ^ 1].push_back(B);
        g[B ^ 1].push_back(A);
    }
    bool solve() {
        int N = 2 * n, timer = 0, C = 0;
        vector<int> idx(N, -1), low(N), comp(N, -1), it(N, 0), stk, call;
        for (int s = 0; s < N; s++) {
            if (idx[s] != -1) continue;
            idx[s] = low[s] = timer++; stk.push_back(s); call.push_back(s);
            while (!call.empty()) {
                int v = call.back();
                if (it[v] < (int)g[v].size()) {
                    int w = g[v][it[v]++];
                    if (idx[w] == -1) { idx[w] = low[w] = timer++; stk.push_back(w); call.push_back(w); }
                    else if (comp[w] == -1) low[v] = min(low[v], idx[w]);
                } else {
                    call.pop_back();
                    if (!call.empty()) low[call.back()] = min(low[call.back()], low[v]);
                    if (low[v] == idx[v]) {
                        while (true) { int w = stk.back(); stk.pop_back(); comp[w] = C; if (w == v) break; }
                        C++;
                    }
                }
            }
        }
        for (int x = 0; x < n; x++) if (comp[2 * x] == comp[2 * x + 1]) return false;
        return true;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        int n;
        cin >> n;
        vector<array<int, 3>> col(n);
        for (int r = 0; r < 3; r++)
            for (int j = 0; j < n; j++) cin >> col[j][r];
        TwoSat ts(n);
        for (int j = 0; j < n; j++)
            for (int p = 0; p < 3; p++)
                for (int q = p + 1; q < 3; q++) {
                    int u = col[j][p], v = col[j][q];
                    ts.addOr(abs(u) - 1, u > 0, abs(v) - 1, v > 0);
                }
        cout << (ts.solve() ? "YES" : "NO") << "\n";
    }
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

    static class TwoSat {
        int n, m = 0;
        int[] eu = new int[16], ev = new int[16];
        TwoSat(int n) { this.n = n; }
        static int lit(int x, boolean val) { return 2 * x + (val ? 0 : 1); }
        void arc(int a, int b) {
            if (m == eu.length) { eu = Arrays.copyOf(eu, 2 * m); ev = Arrays.copyOf(ev, 2 * m); }
            eu[m] = a; ev[m++] = b;
        }
        void addOr(int a, boolean va, int b, boolean vb) {
            int A = lit(a, va), B = lit(b, vb);
            arc(A ^ 1, B); arc(B ^ 1, A);
        }
        boolean solve() {
            int N = 2 * n;
            int[] head = new int[N], nxt = new int[m];
            Arrays.fill(head, -1);
            for (int i = 0; i < m; i++) { nxt[i] = head[eu[i]]; head[eu[i]] = i; }
            int[] idx = new int[N], low = new int[N], comp = new int[N], it = new int[N], stk = new int[N], call = new int[N];
            Arrays.fill(idx, -1); Arrays.fill(comp, -1);
            int timer = 0, C = 0, sp = 0;
            for (int s = 0; s < N; s++) {
                if (idx[s] != -1) continue;
                int cp = 0;
                idx[s] = low[s] = timer++; stk[sp++] = s; it[s] = head[s]; call[cp++] = s;
                while (cp > 0) {
                    int v = call[cp - 1];
                    if (it[v] != -1) {
                        int e = it[v]; it[v] = nxt[e]; int w = ev[e];
                        if (idx[w] == -1) { idx[w] = low[w] = timer++; stk[sp++] = w; it[w] = head[w]; call[cp++] = w; }
                        else if (comp[w] == -1) low[v] = Math.min(low[v], idx[w]);
                    } else {
                        cp--;
                        if (cp > 0) low[call[cp - 1]] = Math.min(low[call[cp - 1]], low[v]);
                        if (low[v] == idx[v]) { while (true) { int w = stk[--sp]; comp[w] = C; if (w == v) break; } C++; }
                    }
                }
            }
            for (int x = 0; x < n; x++) if (comp[2 * x] == comp[2 * x + 1]) return false;
            return true;
        }
    }

    public static void main(String[] args) throws IOException {
        int t = nextInt();
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            int n = nextInt();
            int[][] g = new int[3][n];
            for (int r = 0; r < 3; r++) for (int j = 0; j < n; j++) g[r][j] = nextInt();
            TwoSat ts = new TwoSat(n);
            for (int j = 0; j < n; j++)
                for (int p = 0; p < 3; p++)
                    for (int q = p + 1; q < 3; q++) {
                        int u = g[p][j], v = g[q][j];
                        ts.addOr(Math.abs(u) - 1, u > 0, Math.abs(v) - 1, v > 0);
                    }
            sb.append(ts.solve() ? "YES" : "NO").append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
2
2
1 2
-1 -2
1 2
2
1 1
-1 -1
2 -2
out:
YES
NO
-->
<!-- test
in:
1
3
1 -2 3
-1 2 -3
2 3 1
out:
YES
-->
<!-- test
in:
1
2
1 -1
-1 1
1 -1
out:
NO
-->

### Example 4 — Clauses with "at most one per group"  ·  ★ ≈2200

- **Source:** Original problem.
- **Difficulty:** ≈2200 (est.)
- **Problem:** $n$ variables ($n \le 10^5$), $m$ two-literal clauses and $k$ groups of literals (total group size $\le 2\cdot10^5$).
  Literals are signed integers: $+x$ means $x$ is true, $-x$ means $x$ is false. Every clause must hold and in every group at most
  one literal may be true. Input: `n m k`, then $m$ lines `a b`, then $k$ lines `s l_1 … l_s`. Print `YES` or `NO`.
- **Thinking from first principles:** At-most-one is a set of pairwise NAND clauses, but a group of size $10^5$ would need
  $5\cdot10^9$ of them. Introduce prefix variables $p_i$ = "some literal among the first $i$ is true". The chain
  $\ell_i \Rightarrow p_i$, $p_{i-1} \Rightarrow p_i$, $p_{i-1} \Rightarrow \neg\ell_i$ forbids two true literals with $3s$ clauses
  (proof in §2). This is the standard way to keep 2-SAT linear when "pick at most one from a big set" appears (CF 1215F uses the same chain idea).

<details><summary>Solution</summary>

Variables $0..n-1$ plus one fresh variable per group member; total clauses $m + 3\sum s$. $O(n + m + \sum s)$.
A brute force over all $2^n$ assignments was used to stress-test this on random small instances.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct TwoSat {
    int n;
    vector<vector<int>> g;
    explicit TwoSat(int n) : n(n), g(2 * n) {}
    static int lit(int x, bool val) { return 2 * x + (val ? 0 : 1); }
    void addOr(int a, bool va, int b, bool vb) {
        int A = lit(a, va), B = lit(b, vb);
        g[A ^ 1].push_back(B);
        g[B ^ 1].push_back(A);
    }
    void addImplies(int a, bool va, int b, bool vb) { addOr(a, !va, b, vb); }
    int newVar() { g.emplace_back(); g.emplace_back(); return n++; }
    void atMostOne(const vector<pair<int,bool>>& lits) {
        int prev = -1;
        for (auto [x, vx] : lits) {
            int p = newVar();
            addImplies(x, vx, p, true);
            if (prev != -1) { addImplies(prev, true, p, true); addImplies(prev, true, x, !vx); }
            prev = p;
        }
    }
    bool solve() {
        int N = 2 * n, timer = 0, C = 0;
        vector<int> idx(N, -1), low(N), comp(N, -1), it(N, 0), stk, call;
        for (int s = 0; s < N; s++) {
            if (idx[s] != -1) continue;
            idx[s] = low[s] = timer++; stk.push_back(s); call.push_back(s);
            while (!call.empty()) {
                int v = call.back();
                if (it[v] < (int)g[v].size()) {
                    int w = g[v][it[v]++];
                    if (idx[w] == -1) { idx[w] = low[w] = timer++; stk.push_back(w); call.push_back(w); }
                    else if (comp[w] == -1) low[v] = min(low[v], idx[w]);
                } else {
                    call.pop_back();
                    if (!call.empty()) low[call.back()] = min(low[call.back()], low[v]);
                    if (low[v] == idx[v]) {
                        while (true) { int w = stk.back(); stk.pop_back(); comp[w] = C; if (w == v) break; }
                        C++;
                    }
                }
            }
        }
        for (int x = 0; x < n; x++) if (comp[2 * x] == comp[2 * x + 1]) return false;
        return true;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m, k;
    cin >> n >> m >> k;
    TwoSat ts(n);
    for (int i = 0; i < m; i++) {
        int a, b; cin >> a >> b;
        ts.addOr(abs(a) - 1, a > 0, abs(b) - 1, b > 0);
    }
    for (int i = 0; i < k; i++) {
        int s; cin >> s;
        vector<pair<int,bool>> lits(s);
        for (auto& [x, v] : lits) { int l; cin >> l; x = abs(l) - 1; v = l > 0; }
        ts.atMostOne(lits);
    }
    cout << (ts.solve() ? "YES" : "NO") << "\n";
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

    static class TwoSat {
        int n, m = 0;
        int[] eu = new int[16], ev = new int[16];
        TwoSat(int n) { this.n = n; }
        static int lit(int x, boolean val) { return 2 * x + (val ? 0 : 1); }
        void arc(int a, int b) {
            if (m == eu.length) { eu = Arrays.copyOf(eu, 2 * m); ev = Arrays.copyOf(ev, 2 * m); }
            eu[m] = a; ev[m++] = b;
        }
        void addOr(int a, boolean va, int b, boolean vb) {
            int A = lit(a, va), B = lit(b, vb);
            arc(A ^ 1, B); arc(B ^ 1, A);
        }
        void addImplies(int a, boolean va, int b, boolean vb) { addOr(a, !va, b, vb); }
        int newVar() { return n++; }
        void atMostOne(int[] xs, boolean[] vs) {
            int prev = -1;
            for (int i = 0; i < xs.length; i++) {
                int p = newVar();
                addImplies(xs[i], vs[i], p, true);
                if (prev != -1) { addImplies(prev, true, p, true); addImplies(prev, true, xs[i], !vs[i]); }
                prev = p;
            }
        }
        boolean solve() {
            int N = 2 * n;
            int[] head = new int[N], nxt = new int[m];
            Arrays.fill(head, -1);
            for (int i = 0; i < m; i++) { nxt[i] = head[eu[i]]; head[eu[i]] = i; }
            int[] idx = new int[N], low = new int[N], comp = new int[N], it = new int[N], stk = new int[N], call = new int[N];
            Arrays.fill(idx, -1); Arrays.fill(comp, -1);
            int timer = 0, C = 0, sp = 0;
            for (int s = 0; s < N; s++) {
                if (idx[s] != -1) continue;
                int cp = 0;
                idx[s] = low[s] = timer++; stk[sp++] = s; it[s] = head[s]; call[cp++] = s;
                while (cp > 0) {
                    int v = call[cp - 1];
                    if (it[v] != -1) {
                        int e = it[v]; it[v] = nxt[e]; int w = ev[e];
                        if (idx[w] == -1) { idx[w] = low[w] = timer++; stk[sp++] = w; it[w] = head[w]; call[cp++] = w; }
                        else if (comp[w] == -1) low[v] = Math.min(low[v], idx[w]);
                    } else {
                        cp--;
                        if (cp > 0) low[call[cp - 1]] = Math.min(low[call[cp - 1]], low[v]);
                        if (low[v] == idx[v]) { while (true) { int w = stk[--sp]; comp[w] = C; if (w == v) break; } C++; }
                    }
                }
            }
            for (int x = 0; x < n; x++) if (comp[2 * x] == comp[2 * x + 1]) return false;
            return true;
        }
    }

    public static void main(String[] args) throws IOException {
        int n = nextInt(), m = nextInt(), k = nextInt();
        TwoSat ts = new TwoSat(n);
        for (int i = 0; i < m; i++) {
            int a = nextInt(), b = nextInt();
            ts.addOr(Math.abs(a) - 1, a > 0, Math.abs(b) - 1, b > 0);
        }
        for (int i = 0; i < k; i++) {
            int s = nextInt();
            int[] xs = new int[s]; boolean[] vs = new boolean[s];
            for (int j = 0; j < s; j++) { int l = nextInt(); xs[j] = Math.abs(l) - 1; vs[j] = l > 0; }
            ts.atMostOne(xs, vs);
        }
        System.out.println(ts.solve() ? "YES" : "NO");
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
3 1 2 3
out:
NO
-->
<!-- test
in:
3 2 1
1 2
2 3
2 1 3
out:
YES
-->
<!-- test
in:
1 0 1
2 1 -1
out:
YES
-->
<!-- test
in:
2 2 1
1 1
2 2
2 1 2
out:
NO
-->
<!-- test
in:
4 2 2
1 2
3 4
2 1 3
2 2 4
out:
YES
-->

## 6. Tricks, pitfalls and things to remember

1. **Always add both arcs** of a clause. Missing the contrapositive breaks skew symmetry and the assignment proof; solutions then fail randomly.
2. **Direction of the comparison:** Tarjan ids are reverse-topological → `value[x] = comp[x] < comp[¬x]`. Kosaraju (second pass on the transposed graph in decreasing finish time) numbers components topologically → use `>`. Verify on a single forcing clause.
3. **Forcing a literal** is the clause $(a \lor a)$: one arc $\neg a \to a$ (added twice, harmless).
4. **Node layout** $2x / 2x+1$ with `^1` negation avoids off-by-$n$ bugs of the $x / x+n$ layout when you add fresh variables later.
5. **Fresh variables** (prefix encodings, segment-tree helpers) change $n$: create them before calling `solve`, and size arrays from the final $n$.
6. **"Exactly one of three or more"** is not 2-SAT. If a statement needs it, the intended solution is something else (matching, greedy, or the structure guarantees two options).
7. **Recursion depth:** recursive Tarjan on $2\cdot10^5$ nodes overflows the Java stack; the iterative version above is safe.
8. **Pure XOR/equality systems** (bipartiteness, The Door Problem) are faster and simpler with a parity DSU; reach for 2-SAT when OR/implication clauses are mixed in.
9. **Binary search + 2-SAT:** rebuild the graph per check; clauses depend on the threshold. Reuse arrays to avoid $O(\log C)$ reallocations in Java.
10. **Unmentioned variables** are free; any value works, but the program must still print one.
11. **Multiple test cases:** clear the graph per test (`g.assign`), not just the result arrays.

## 7. Going further (toward 2400–2600+)

- **Prefix/suffix chains for ordered domains.** If each object chooses a value from an ordered range and constraints are
  "$v \ge f$" style, use variables $[v \ge f]$ with implications $[v \ge f+1] \Rightarrow [v \ge f]$ — see
  [CF 1215F · Radio Stations](https://codeforces.com/problemset/problem/1215/F) — 2700.
- **Segment-tree-shaped implication graphs:** "if $x$ then all of $y \in [l, r]$ are false" with $O(\log n)$ helper nodes per clause
  (same idea as [segment-tree edges](10-functional-graphs-and-special-graphs.md)).
- **Binary search on the answer** with a 2-SAT feasibility check: [CF 587D · Duff in Mafia](https://codeforces.com/problemset/problem/587/D) — 3100
  (also needs the prefix at-most-one trick).
- **2-SAT on trees / paths:** each path chooses one of two words, constraints along edges — [CF 1657F · Words on Tree](https://codeforces.com/problemset/problem/1657/F) — 2600.
- **Lexicographically smallest assignment / incremental 2-SAT:** greedy with propagation and rollback.
- **Theory:** 2-SAT is NL-complete; Horn-SAT is also linear (unit propagation); MAX-2-SAT and #2-SAT are hard.

## 8. Practice ladder

**1700–2000**
- [ ] [AtCoder PRACTICE2 H · Two SAT](https://atcoder.jp/contests/practice2/tasks/practice2_h) — library practice — each flag has two positions; close pairs become NAND clauses
- [ ] [CSES 1684 · Giant Pizza](https://cses.fi/problemset/task/1684) — the template
- [ ] [CF 1475F · Unusual Matrix](https://codeforces.com/problemset/problem/1475/F) — 1900 — row/column flips as XOR clauses
- [ ] [CF 228E · The Road to Berland is Paved With Good Intentions](https://codeforces.com/problemset/problem/228/E) — 1900 — XOR per road
- [ ] [CF 1715D · 2+ doors](https://codeforces.com/problemset/problem/1715/D) — 1900 — per-bit forced zeros, greedy (2-SAT flavour)
- [ ] [CF 780D · Innokenty and a Football League](https://codeforces.com/problemset/problem/780/D) — 1900 — two candidate names per club
- [ ] [CF 776D · The Door Problem](https://codeforces.com/problemset/problem/776/D) — 2000 — XOR / equality
- [ ] [CF 468B · Two Sets](https://codeforces.com/problemset/problem/468/B) — 2000 — implications between complements

**2100–2400**
- [ ] [CF 875C · National Property](https://codeforces.com/problemset/problem/875/C) — 2100 — capitalisation implications
- [ ] [CF 1971H · ±1](https://codeforces.com/problemset/problem/1971/H) — 2100 — at least two of three
- [ ] [CF 27D · Ring Road 2](https://codeforces.com/problemset/problem/27/D) — 2200 — crossing chords
- [ ] [CF 1635E · Cars](https://codeforces.com/problemset/problem/1635/E) — 2200 — orientation by 2-coloring then topo sort
- [ ] [CF 1385G · Columns Swaps](https://codeforces.com/problemset/problem/1385/G) — 2300 — XOR clauses, minimise swaps per component
- [ ] [CF 1239D · Catowice City](https://codeforces.com/problemset/problem/1239/D) — 2400 — SCC view of a 2-choice model
- [ ] [CF 1844E · Great Grids](https://codeforces.com/problemset/problem/1844/E) — 2400 — diagonal type per cell, parity constraints

**2400+**
- [ ] [CF 1903F · Babysitting](https://codeforces.com/problemset/problem/1903/F) — 2500 — binary search + segment-tree 2-SAT
- [ ] [CF 568C · New Language](https://codeforces.com/problemset/problem/568/C) — 2600 — lexicographic greedy with 2-SAT checks
- [ ] [CF 1657F · Words on Tree](https://codeforces.com/problemset/problem/1657/F) — 2600
- [ ] [CF 1215F · Radio Stations](https://codeforces.com/problemset/problem/1215/F) — 2700 — prefix chains over frequencies
- [ ] [CF 587D · Duff in Mafia](https://codeforces.com/problemset/problem/587/D) — 3100

## 9. LeetCode / FAANG cross-reference

Rare in interviews: 2-SAT needs SCCs plus a non-obvious proof, which is beyond the usual 45-minute scope. The degenerate cases do appear:

- [LC 886 · Possible Bipartition](https://leetcode.com/problems/possible-bipartition/) — Medium — every "dislike" is an XOR clause; 2-coloring suffices.
- [LC 990 · Satisfiability of Equality Equations](https://leetcode.com/problems/satisfiability-of-equality-equations/) — Medium — only equalities/inequalities over letters; DSU, the 2-SAT idea of "contradiction = same component".
- [LC 2307 · Check for Contradictions in Equations](https://leetcode.com/problems/check-for-contradictions-in-equations/) — Hard 🔒 — weighted DSU consistency, the multiplicative cousin of parity constraints.

## 10. Self-check

1. Convert $(a \lor \neg b)$ into arcs of the implication graph.
2. Why is "$x$ and $\neg x$ in the same SCC" a proof of unsatisfiability?
3. State the assignment rule in terms of a topological order and prove one clause cannot be violated.
4. With Tarjan's component ids, is $x$ true when `comp[x] < comp[¬x]` or `>`? Why?
5. Encode "exactly one of $a, b$" and "$a$ equals $b$".
6. How do you encode "at most one of $k$ literals" with $O(k)$ clauses?
7. Why can't "exactly one of three literals" be written in 2-CNF in general?
8. When would you prefer a parity DSU over 2-SAT?

<details><summary>Answers</summary>

1. $\neg a \to \neg b$ and $b \to a$.
2. The SCC contains paths $x \leadsto \neg x$ and $\neg x \leadsto x$; both truth values of $x$ force their own negation.
3. $x$ is true iff $\text{topo}(x) > \text{topo}(\neg x)$. If $(a \lor b)$ failed: $\text{topo}(a) < \text{topo}(\neg a) \le \text{topo}(b) < \text{topo}(\neg b) \le \text{topo}(a)$ using arcs $\neg a\to b$, $\neg b \to a$ — contradiction.
4. `<`: Tarjan finishes sink components first, so smaller id = later in topological order.
5. XOR: $(a\lor b)\land(\neg a\lor\neg b)$. Equality: $(\neg a\lor b)\land(a\lor\neg b)$.
6. Prefix variables $p_i$: $\ell_i\Rightarrow p_i$, $p_{i-1}\Rightarrow p_i$, $p_{i-1}\Rightarrow\neg\ell_i$.
7. "Exactly one of three" requires excluding the all-false assignment, which needs the 3-clause $(a\lor b\lor c)$; the set of solutions $\{100, 010, 001\}$ is not closed under the bitwise majority operation, and every 2-CNF solution set is closed under majority.
8. When every constraint is "$x = y$" or "$x \ne y$" (XOR systems): union–find with parity is $O(\alpha)$ per constraint, needs no graph, and supports online checks.

</details>
