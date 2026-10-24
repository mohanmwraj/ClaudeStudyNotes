# Nim and the Sprague–Grundy Theorem

> **Band:** 🔵 1600–2300 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [game fundamentals](01-game-fundamentals-winning-losing-states.md), [bit manipulation](../01-Foundations/03-bit-manipulation.md), [topological sort and DAG DP](../09-Graphs/04-topological-sort-and-dag-dp.md)
> **You can say you know this when:** you can prove the Nim XOR rule and the Sprague–Grundy sum theorem from scratch, compute Grundy values of any impartial game by DP (including splitting moves), detect a period exactly, and evaluate Green Hackenbush on a tree in O(n).

---

## 1. First principles — why this works

### 1.1 Why W/L labels break on sums

Many games are **sums**: several independent components (piles, boards, tokens), and a move is made in exactly one component of your choice; the player who cannot move in any component loses. Knowing whether each component is W or L does not determine the sum: two piles of 3 in Nim are each W, yet the sum is L (the second player copies). We need a finer invariant — one number per component that composes. That number is the Grundy value, and the composition is XOR.

### 1.2 Nim

Piles $a_1,\dots,a_n$; a move removes any positive number of stones from one pile; normal play.

**Theorem (Bouton).** The position is P iff $a_1 \oplus a_2 \oplus \dots \oplus a_n = 0$.

*Proof* with the three conditions of [file 01 §1.3](01-game-fundamentals-winning-losing-states.md):
1. the terminal position (all zero) has XOR 0;
2. from XOR 0, a move changes exactly one pile $a_i \to a_i' \ne a_i$, so the XOR becomes $a_i \oplus a_i' \ne 0$;
3. from XOR $s \ne 0$: let $h$ be the highest set bit of $s$. Some pile $a_i$ has bit $h$ set (otherwise bit $h$ of $s$ would be 0). Then $a_i \oplus s < a_i$ (bit $h$ turns off, higher bits unchanged), so reducing $a_i$ to $a_i \oplus s$ is legal and makes the XOR $s \oplus s = 0$. $\square$

The number of winning moves from $s \ne 0$ equals the number of piles with bit $h$ set.

### 1.3 mex and Grundy values

For a finite set $A$ of non-negative integers, $\operatorname{mex}(A)$ is the smallest non-negative integer not in $A$. For a position $v$ of an impartial game,

$$g(v) = \operatorname{mex}\{\, g(u) : v \to u \,\}, \qquad g(\text{terminal}) = 0 .$$

Two facts follow immediately from the definition:

- $g(v) = 0 \iff v$ is P. (If $g(v)=0$, no option has value 0, so all options are N; if $g(v)>0$, some option has value 0.)
- From $v$ you can reach a position of **every** value $0,1,\dots,g(v)-1$ and none of value $g(v)$. That is exactly what a Nim pile of size $g(v)$ allows. (Options with *larger* values may exist; they don't matter, because any move to a larger value can be answered by moving back down to $g(v)$.) So **every impartial position is equivalent to a Nim pile of size $g(v)$.**

### 1.4 The Sprague–Grundy sum theorem

**Theorem.** For a sum of independent impartial games, $g(G_1 + \dots + G_n) = g(G_1) \oplus \dots \oplus g(G_n)$. In particular the sum is P iff the XOR is 0.

*Proof (two components, then induct).* Let $a = g(G)$, $b = g(H)$; induct on the total remaining length of play, so options of $G+H$ (which are $G'+H$ or $G+H'$) already satisfy the theorem. We must show the set of option values $\{g(G')\oplus b\} \cup \{a \oplus g(H')\}$ (i) does not contain $a\oplus b$ and (ii) contains every $c < a \oplus b$.

- (i) $g(G') \ne a$ (by the mex definition no option of $G$ has value $a$), so $g(G') \oplus b \ne a \oplus b$; same for $H$.
- (ii) Let $d = c \oplus a \oplus b \ne 0$ and $h$ its highest bit. Since $c < a\oplus b$, at bit $h$ the number $a \oplus b$ has a 1 and $c$ a 0, so exactly one of $a,b$ has bit $h$ — say $a$. Then $a \oplus d < a$, so $G$ has an option $G'$ with $g(G') = a\oplus d$, and $g(G'+H) = a \oplus d \oplus b = c$. $\square$

This is the same argument as Nim's condition 3 — Nim is the special case where each component *is* a pile.

### 1.5 Computing Grundy values

Same DP as W/L ([file 01 §3.1](01-game-fundamentals-winning-losing-states.md)), but take the mex of successor values instead of "any successor is L". Implementation detail: to take a mex of the values of $d$ successors you only need a boolean array of size $d+1$ (the mex is at most $d$).

**Bounds that make arrays small.**
- $g(v) \le \operatorname{outdeg}(v)$ (mex of $d$ numbers is $\le d$).
- In a DAG with $m$ edges, every Grundy value $k$ satisfies $k(k+1)/2 \le m$, i.e. $k \le \sqrt{2m}$: a vertex of value $k$ has successors of values $0..k-1$; pick one witness vertex of each value $j<k$; witness $j$ has out-degree $\ge j$; summing gives $\ge 0+1+\dots+k = k(k+1)/2$ distinct edges. Used in [CF 1411G · No Game No Life](https://codeforces.com/problemset/problem/1411/G) — 2700.

### 1.6 Subtraction games and periodicity

A **subtraction game** $S$ is a one-pile game where a move removes $s \in S$ stones. With $S$ finite and $s_{\max} = \max S$:

- $g(n) \le |S|$, and $g(n)$ depends only on the window $(g(n-s_{\max}),\dots,g(n-1))$.
- The window is a state of a deterministic finite automaton with at most $(|S|+1)^{s_{\max}}$ states, so the sequence of windows is "rho-shaped": a tail of length $n_0$, then a cycle of length $p$. Hence **$g$ is eventually periodic**, and the *first repeated window* gives the exact preperiod and period (§3.1).
- Examples: $S=\{1..k\}$: $g(n) = n \bmod (k+1)$. $S = \{1,2,k\}$: period 3 if $3 \nmid k$, period $k+1$ if $3 \mid k$ (Example 3). $S = \{2,4,7\}$: preperiod 8, period 3.

**Games with splitting** (octal games such as Kayles) are not finite automata — a heap of size $n$ looks at *pairs* of smaller heaps. The **Guy–Smith periodicity theorem** says: for an octal game whose moves remove at most $t$ tokens, if $g(n+p) = g(n)$ holds for all $n_0 \le n < 2n_0 + p + t$, then it holds for all $n \ge n_0$. So "compute far enough, check the window" is a proof. Kayles ($t=2$) has period 12 from $n_0 = 71$ on (verified to $n = 2000$ in scratch work). Some games are believed *never* to become periodic — Grundy's game is the famous one.

### 1.7 Splitting games

If a move replaces one heap by several independent heaps, the resulting position is a *sum*, so its value is the XOR of the parts. That one line is all you need:

$$g(n) = \operatorname{mex}\{\, g(a) \oplus g(b) : \text{a move splits } n \text{ into } a, b \,\} \cup \{\dots \text{other moves}\}.$$

- **Lasker's Nim** (remove any number, or split a heap into two non-empty heaps): $g(4k+1)=4k+1$, $g(4k+2)=4k+2$, $g(4k+3)=4k+4$, $g(4k+4)=4k+3$.
- **Kayles** (remove 1 or 2 adjacent pins from a row; the row splits): period 12 eventually.
- **Grundy's game** (split a heap into two *unequal* non-empty heaps): $O(n^2)$ DP. Its P-positions up to $4\cdot 10^4$ (scratch computation) are exactly 1, 2, 4, 7, 10, 20, 23, 26, 50, 53, 270, …, 932, 1222; extensive published computations have found no P-position beyond 1222, which is why [CSES 2207 · Grundy's Game](https://cses.fi/problemset/task/2207) is solvable for huge $n$ (an empirical fact, not a theorem).

### 1.8 Games on graphs and DAGs

Tokens sit on vertices of a DAG; a move slides one token along an edge; normal play. Each token is a component, so the answer is $\bigoplus_{\text{tokens}} g(\text{vertex})$, with $g$ computed in reverse topological order. Two tokens on the same vertex cancel ($x \oplus x = 0$). Many problems are this in disguise: a "state" per object that only gets smaller, objects independent.

### 1.9 Green Hackenbush on rooted trees

A rooted tree drawn from the ground (the root). A move deletes an edge; everything no longer connected to the root disappears. Normal play.

**Claim.** $g(v) = \bigoplus_{c \text{ child of } v} \big(g(c)+1\big)$, and the game value is $g(\text{root})$.

*Proof sketch.*
1. *A stalk* (path of $n$ edges hanging from the ground) is a Nim heap of size $n$: cutting the $i$-th edge leaves a stalk of $i-1$ edges, so the options are stalks of $0..n-1$ edges.
2. *Edge on top of a tree.* Let $T$ have value $g(T)$, and let $e+T$ be $T$ hung under one extra edge. Options of $e+T$: cut $e$ (value 0), or move inside $T$ to $T'$, giving $e+T'$ of value $g(T')+1$ by induction. The values $g(T')$ cover $0..g(T)-1$ and miss $g(T)$, so the option values cover $0..g(T)$ and miss $g(T)+1$: $g(e+T) = g(T)+1$.
3. *Branches at one vertex are independent* (a move in one branch never changes another), so the vertex's value is the XOR of its branches. $\square$

Step 2–3 together are the tree case of the **colon principle** ([file 03](03-game-variants-misere-staircase-hackenbush.md) treats general graphs).

---

## 2. Formulas, definitions and identities

| Formula | Meaning / proof |
|---|---|
| Nim: P $\iff \bigoplus a_i = 0$ | §1.2 |
| winning move from $s=\bigoplus a_i \ne 0$: $a_i \to a_i \oplus s$ for any $a_i$ with the top bit of $s$ | §1.2 |
| $\operatorname{mex}(A) = \min(\mathbb{Z}_{\ge 0}\setminus A)$; $\operatorname{mex}$ of $d$ values $\le d$ | definition |
| $g(v) = \operatorname{mex}\{g(u)\}$, $g=0 \iff$ P | §1.3 |
| $g(G+H) = g(G) \oplus g(H)$ | Sprague–Grundy, §1.4 |
| $g(G+G) = 0$ | copycat strategy; $x\oplus x = 0$ |
| subtraction $\{1..k\}$: $g(n) = n \bmod (k+1)$ | Nim with a cap (CSES Nim II: $k=3$) |
| subtraction $\{1,2,\dots\}$ (unlimited): $g(n)=n$ | plain Nim |
| remove $1..\lfloor n/2 \rfloor$: $g(2m)=m$, $g(2m+1)=g(m)$ | brute-force checked to $5000$ |
| "never remove the same amount twice from a pile": $g(s)=\max\{k : k(k+1)/2 \le s\}$ | Example 4 |
| Lasker's Nim: $g = n$ for $n\equiv 1,2$; $n+1$ for $n\equiv 3$; $n-1$ for $n\equiv 0 \pmod 4$ | checked to 200 |
| Kayles: period 12 from $n=71$ | Guy–Smith + check to 2000 |
| Grundy bound in a DAG with $m$ edges: $g \le \sqrt{2m}$ | §1.5 |
| $0\oplus 1 \oplus \dots \oplus n = n,\ 1,\ n+1,\ 0$ for $n \bmod 4 = 0,1,2,3$ | used in [CF 15C · Industrial Nim](https://codeforces.com/problemset/problem/15/C) — 2000 |
| Green Hackenbush tree: $g(v) = \bigoplus_c (g(c)+1)$ | §1.9 |
| Complexity: Grundy DP $O(V + E)$; subtraction game to $N$: $O(N\lvert S\rvert)$; splitting into two: $O(N^2)$ | |

---

## 3. Implementation (C++ and Java)

### 3.1 Subtraction game: exact preperiod and period

Input: $k$, then the set $S$ ($1 \le s \le 20$). Output: `n0 p`, then $g(0), \dots, g(n_0+p-1)$. Uses the first repeated window of length $s_{\max}$ (§1.6), which is exact.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int k; cin >> k;
    vector<int> S(k);
    for (auto& s : S) cin >> s;
    int smax = *max_element(S.begin(), S.end());
    vector<int> g;
    map<vector<int>, int> firstSeen;                 // window g[i..i+smax-1] -> i
    for (int n = 0;; n++) {
        vector<char> seen(k + 2, 0);
        for (int s : S) if (s <= n) seen[g[n - s]] = 1;
        int m = 0;
        while (seen[m]) m++;
        g.push_back(m);
        int i = n - smax + 1;                        // window ending at n starts at i
        if (i < 0) continue;
        vector<int> w(g.begin() + i, g.end());
        auto it = firstSeen.find(w);
        if (it != firstSeen.end()) {
            int n0 = it->second, p = i - n0;
            cout << n0 << " " << p << "\n";
            for (int j = 0; j < n0 + p; j++) cout << g[j] << " \n"[j + 1 == n0 + p];
            return 0;
        }
        firstSeen[w] = i;
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int k = (int) st.nval;
        int[] S = new int[k]; int smax = 0;
        for (int i = 0; i < k; i++) { st.nextToken(); S[i] = (int) st.nval; smax = Math.max(smax, S[i]); }
        ArrayList<Integer> g = new ArrayList<>();
        HashMap<List<Integer>, Integer> firstSeen = new HashMap<>();
        for (int n = 0; ; n++) {
            boolean[] seen = new boolean[k + 2];
            for (int s : S) if (s <= n) seen[g.get(n - s)] = true;
            int m = 0;
            while (seen[m]) m++;
            g.add(m);
            int i = n - smax + 1;
            if (i < 0) continue;
            List<Integer> w = new ArrayList<>(g.subList(i, n + 1));
            Integer prev = firstSeen.get(w);
            if (prev != null) {
                int n0 = prev, p = i - n0;
                StringBuilder sb = new StringBuilder();
                sb.append(n0).append(' ').append(p).append('\n');
                for (int j = 0; j < n0 + p; j++) sb.append(g.get(j)).append(j + 1 == n0 + p ? '\n' : ' ');
                System.out.print(sb);
                return;
            }
            firstSeen.put(w, i);
        }
    }
}
```

<!-- test
in:
3
1 2 3
out:
0 4
0 1 2 3
-->
<!-- test
in:
3
2 4 7
out:
8 3
0 0 1 1 2 2 0 3 1 0 2
-->
<!-- test
in:
1
1
out:
0 2
0 1
-->

### 3.2 Grundy values on a DAG with several tokens

Input: $n, m$, $m$ edges $u\to v$ of a DAG, then $k$ and the $k$ token positions. Output: $g(1..n)$, then `First` if the XOR of the tokens' values is non-zero, else `Second`.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<vector<int>> adj(n + 1);
    vector<int> indeg(n + 1, 0);
    for (int i = 0; i < m; i++) { int u, v; cin >> u >> v; adj[u].push_back(v); indeg[v]++; }
    vector<int> order;
    for (int v = 1; v <= n; v++) if (!indeg[v]) order.push_back(v);
    for (size_t i = 0; i < order.size(); i++) for (int u : adj[order[i]]) if (--indeg[u] == 0) order.push_back(u);
    vector<int> g(n + 1, 0);
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i], d = adj[v].size();
        vector<char> seen(d + 1, 0);                 // mex of d values is at most d
        for (int u : adj[v]) if (g[u] <= d) seen[g[u]] = 1;
        while (seen[g[v]]) g[v]++;
    }
    int k; cin >> k;
    int x = 0;
    for (int i = 0; i < k; i++) { int p; cin >> p; x ^= g[p]; }
    for (int v = 1; v <= n; v++) cout << g[v] << " \n"[v == n];
    cout << (x ? "First" : "Second") << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        int[] head = new int[n + 1], nxt = new int[m], to = new int[m], indeg = new int[n + 1], deg = new int[n + 1];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            int u = in.nextInt(), v = in.nextInt();
            to[i] = v; nxt[i] = head[u]; head[u] = i; indeg[v]++; deg[u]++;
        }
        int[] order = new int[n]; int sz = 0;
        for (int v = 1; v <= n; v++) if (indeg[v] == 0) order[sz++] = v;
        for (int i = 0; i < sz; i++)
            for (int e = head[order[i]]; e != -1; e = nxt[e]) if (--indeg[to[e]] == 0) order[sz++] = to[e];
        int[] g = new int[n + 1];
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i], d = deg[v];
            boolean[] seen = new boolean[d + 1];
            for (int e = head[v]; e != -1; e = nxt[e]) if (g[to[e]] <= d) seen[g[to[e]]] = true;
            while (seen[g[v]]) g[v]++;
        }
        int k = in.nextInt(), x = 0;
        for (int i = 0; i < k; i++) x ^= g[in.nextInt()];
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(g[v]).append(v == n ? "\n" : " ");
        out.print(sb);
        out.println(x != 0 ? "First" : "Second");
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
5 5
1 2
2 3
3 4
4 5
1 3
2
1 4
out:
2 1 0 1 0
First
-->
<!-- test
in:
5 5
1 2
2 3
3 4
4 5
1 3
2
2 4
out:
2 1 0 1 0
Second
-->
<!-- test
in:
1 0
1
1
out:
0
Second
-->

### 3.3 mex helper (fragment)

```cpp
// mex of a small list; values > size are irrelevant
int mex(const vector<int>& vals) {
    vector<char> seen(vals.size() + 1, 0);
    for (int x : vals) if (x <= (int)vals.size()) seen[x] = 1;
    int m = 0;
    while (seen[m]) m++;
    return m;
}
```

```java
static int mex(int[] vals) {
    boolean[] seen = new boolean[vals.length + 1];
    for (int x : vals) if (x <= vals.length) seen[x] = true;
    int m = 0;
    while (seen[m]) m++;
    return m;
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| several piles / boards / tokens, a move touches exactly one | Sprague–Grundy: XOR of component values |
| "remove any number from one pile" | Nim |
| "remove $1..k$" or a fixed set of amounts | subtraction game: $n \bmod (k+1)$ or compute + period |
| a move breaks one object into independent smaller objects | splitting game: option value = XOR of parts |
| per-object state that only decreases, objects independent | DAG Grundy per object |
| rooted tree, cutting an edge drops the detached part | Green Hackenbush: $\bigoplus (g(c)+1)$ |
| $a_i$ up to $10^{18}$ but the move rule is "local" | compute $g$ for small values, find formula/period, check against brute force |
| "the player who makes the XOR zero…" or anything with explicit XOR in the statement | not necessarily Sprague–Grundy — often a direct bit argument ([CF 1383B · GameGame](https://codeforces.com/problemset/problem/1383/B) — 1900) |

Confusions: the XOR rule needs **normal play** and **independent** components. Misère changes it (file 03); a move touching two piles at once (Wythoff, Moore) breaks independence (file 03).

---

## 5. Worked examples (graded)

### Example 1 — Nim Game I  ·  ★ ≈1300

- **Source:** [CSES 1730 · Nim Game I](https://cses.fi/problemset/task/1730)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $t$ tests; $n$ heaps $x_i$; a move removes any positive number of sticks from one heap; whoever removes the last stick wins. Print `first` or `second`. $\sum n \le 2\cdot 10^5$, $x_i \le 10^9$.
- **Thinking from first principles:** "Removes the last stick wins" = normal play. Direct application of Bouton's theorem.

<details><summary>Solution</summary>

XOR all heaps; `first` iff non-zero (§1.2). $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        long long x = 0;
        for (int i = 0; i < n; i++) { long long a; cin >> a; x ^= a; }
        cout << (x ? "first" : "second") << "\n";
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
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt();
            long x = 0;
            for (int i = 0; i < n; i++) x ^= in.nextLong();
            out.println(x != 0 ? "first" : "second");
        }
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
3
4
5 7 2 5
2
4 1
3
3 5 6
out:
first
first
second
-->
<!-- test
in:
2
1
1000000000
2
7 7
out:
first
second
-->

### Example 2 — Nim Game II  ·  ★ ≈1500

- **Source:** [CSES 1098 · Nim Game II](https://cses.fi/problemset/task/1098)
- **Difficulty:** ≈1500 (est.)
- **Problem:** As Nim Game I, but a move removes 1, 2 or 3 sticks from one heap.
- **Thinking from first principles:** The heaps are independent components, each a subtraction game $\{1,2,3\}$, whose Grundy value is $x \bmod 4$ (§2). XOR them. Dead end: "XOR the heaps and then take mod 4" — the mod must be applied per heap *before* XORing, because each component is replaced by its own equivalent Nim heap.

<details><summary>Solution</summary>

`first` iff $\bigoplus (x_i \bmod 4) \ne 0$ (Sprague–Grundy with $g(x) = x \bmod 4$). $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        int x = 0;
        for (int i = 0; i < n; i++) { long long a; cin >> a; x ^= (int)(a % 4); }
        cout << (x ? "first" : "second") << "\n";
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
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt(), x = 0;
            for (int i = 0; i < n; i++) x ^= (int) (in.nextLong() % 4);
            out.println(x != 0 ? "first" : "second");
        }
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
3
4
5 7 2 5
2
4 1
3
3 5 6
out:
first
first
second
-->
<!-- test
in:
2
2
4 8
2
5 9
out:
second
second
-->

### Example 3 — 1-2-K Game  ·  ★ 1700

- **Source:** [CF 1194D · 1-2-K Game](https://codeforces.com/problemset/problem/1194/D) — 1700
- **Difficulty:** 1700
- **Problem:** A chip on cell $n$ of a strip $0..n$; a move shifts it left by 1, 2 or $k$ cells (not past 0). Who cannot move loses; Alice first. $T \le 100$ queries, $0 \le n \le 10^9$, $3 \le k \le 10^9$.
- **Thinking from first principles:** A subtraction game $\{1,2,k\}$. Brute force a table over $(n,k)$: for $k=4,5,7,8$ the L positions are exactly multiples of 3 — the $k$-move never helps because $k \not\equiv 0 \pmod 3$ jumps between residues the same way a 1- or 2-move does. For $k = 3,6,9$ the pattern breaks and repeats with period $k+1$. Inside one period of length $k+1$: residues $r = n \bmod (k+1)$; L iff $r \bmod 3 = 0$ and $r \ne k$ (position $k$ itself jumps to $0$).

<details><summary>Solution</summary>

- If $3 \nmid k$: Bob wins iff $3 \mid n$. Proof by the template: from a multiple of 3, moves of 1, 2, $k$ all leave a non-multiple (since $k \not\equiv 0$); from a non-multiple, a 1- or 2-move reaches a multiple.
- If $3 \mid k$: let $r = n \bmod (k+1)$. Alice wins iff $r = k$ or $r \bmod 3 \ne 0$. (Inside a block, the $k$-move from $r=k$ lands on the block's start, which is L; positions $r<k$ behave like the $\{1,2\}$ game; and the block start $k+1 \equiv 0$ can't reach an L position because $k+1-k = 1$ and $k+1-1 = k$, $k+1-2=k-1$ are all W.)

Both cases were checked against the subtraction-game DP for all $k \le 40$, $n < 400$. $O(1)$ per query.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int T; cin >> T;
    while (T--) {
        long long n, k; cin >> n >> k;
        bool alice;
        if (k % 3 != 0) alice = n % 3 != 0;
        else { long long r = n % (k + 1); alice = (r == k) || (r % 3 != 0); }
        cout << (alice ? "Alice" : "Bob") << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int T = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        while (T-- > 0) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            long n = Long.parseLong(st.nextToken()), k = Long.parseLong(st.nextToken());
            boolean alice;
            if (k % 3 != 0) alice = n % 3 != 0;
            else { long r = n % (k + 1); alice = r == k || r % 3 != 0; }
            sb.append(alice ? "Alice" : "Bob").append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
4
0 3
3 3
3 4
4 4
out:
Bob
Alice
Bob
Alice
-->
<!-- test
in:
5
7 6
6 6
14 6
1000000000 1000000000
999999999 4
out:
Bob
Alice
Bob
Alice
Bob
-->

### Example 4 — Game of Stones (Grundy by brute force, then a formula)  ·  ★ 2100

- **Source:** [CF 768E · Game of Stones](https://codeforces.com/problemset/problem/768/E) — 2100
- **Difficulty:** 2100
- **Problem:** $n \le 10^6$ piles, $s_i \le 60$. A move removes some stones from one pile, but the same number may never be removed twice from the same pile. Sam moves first, Jon second; print `YES` if Jon wins.
- **Thinking from first principles:** Piles are independent ⇒ Sprague–Grundy. The state of a single pile is (remaining, set of amounts already used) — huge in principle but tiny for $s \le 25$ by memoised brute force. Printing $g(s)$ for $s = 0..25$ gives $0,1,1,2,2,2,3,3,3,3,4,\dots$: the value $k$ appears $k+1$ times. So $g(s) = \max\{k : 1+2+\dots+k \le s\}$. Why? From a fresh pile you can make at most $k$ moves with distinct amounts summing to $\le s$; the game on a single pile with distinct removals is equivalent to a Nim heap of that size. Precompute for $s \le 60$ (values $\le 10$).

<details><summary>Solution</summary>

$g(s)$ = largest $k$ with $k(k+1)/2 \le s$ (checked against the exhaustive brute force for $s \le 25$). Jon (second) wins iff $\bigoplus g(s_i) = 0$. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    int x = 0;
    for (int i = 0; i < n; i++) {
        int s; cin >> s;
        int k = 0;
        while ((k + 1) * (k + 2) / 2 <= s) k++;
        x ^= k;
    }
    cout << (x == 0 ? "YES" : "NO") << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), x = 0;
        for (int i = 0; i < n; i++) {
            int s = in.nextInt(), k = 0;
            while ((k + 1) * (k + 2) / 2 <= s) k++;
            x ^= k;
        }
        System.out.println(x == 0 ? "YES" : "NO");
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
1
5
out:
NO
-->
<!-- test
in:
2
1
2
out:
YES
-->
<!-- test
in:
3
60
55
3
out:
NO
-->

### Example 5 — Lieges of Legendre (splitting + parity)  ·  ★ 2200

- **Source:** [CF 603C · Lieges of Legendre](https://codeforces.com/problemset/problem/603/C) — 2200
- **Difficulty:** 2200
- **Problem:** $n \le 10^5$ piles $a_i \le 10^9$ and a number $k \le 10^9$. A move either removes one cow from a pile, or replaces a pile of even size $2x$ by $k$ piles of size $x$. Kevin first; who wins?
- **Thinking from first principles:** Independent piles ⇒ XOR. Splitting $2x$ into $k$ equal piles has value $g(x)\oplus\dots\oplus g(x)$ ($k$ times) $= 0$ if $k$ even, $g(x)$ if $k$ odd — so only the **parity of $k$** matters. Brute-force both parities to 50: for even $k$: $0,1,2,0,1,0,1,0,\dots$ (from 3 on: even→1, odd→0). For odd $k$: $0,1,0,1,2,0,2,0,1,0,\dots$ (from 5 on: odd→0; even $n$: $\operatorname{mex}\{g(n-1)=0,\ g(n/2)\}$, i.e. 1 unless $g(n/2)=1$, then 2).

<details><summary>Solution</summary>

$k$ even: $g(0..2) = 0,1,2$; for $n\ge 3$: $g(n) = 1$ if $n$ even, else $0$.
$k$ odd: $g(0..4) = 0,1,0,1,2$; for $n \ge 5$: odd $\Rightarrow 0$; even $\Rightarrow 2$ if $g(n/2)=1$ else $1$ (recursion depth $O(\log n)$).
Proof: induction using $g(n) = \operatorname{mex}\{g(n-1),\ [n \text{ even}]\cdot(k \bmod 2)\cdot g(n/2) \text{ or } 0\}$; checked against the brute force for $k \le 8$, $n \le 2000$. Kevin wins iff the XOR is non-zero. $O(n \log a)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int grundy(long long n, bool kodd) {
    if (!kodd) {
        if (n <= 2) return (int)n;
        return n % 2 == 0 ? 1 : 0;
    }
    if (n <= 4) { static const int t[5] = {0, 1, 0, 1, 2}; return t[n]; }
    if (n % 2 == 1) return 0;
    return grundy(n / 2, kodd) == 1 ? 2 : 1;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long k; cin >> n >> k;
    int x = 0;
    for (int i = 0; i < n; i++) { long long a; cin >> a; x ^= grundy(a, k % 2 == 1); }
    cout << (x ? "Kevin" : "Nicky") << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final int[] SMALL = {0, 1, 0, 1, 2};

    static int grundy(long n, boolean kodd) {
        if (!kodd) return n <= 2 ? (int) n : (n % 2 == 0 ? 1 : 0);
        if (n <= 4) return SMALL[(int) n];
        if (n % 2 == 1) return 0;
        return grundy(n / 2, true) == 1 ? 2 : 1;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long k = in.nextLong();
        int x = 0;
        for (int i = 0; i < n; i++) x ^= grundy(in.nextLong(), k % 2 == 1);
        System.out.println(x != 0 ? "Kevin" : "Nicky");
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
2 1
3 4
out:
Kevin
-->
<!-- test
in:
1 2
3
out:
Nicky
-->
<!-- test
in:
3 3
6 2 1
out:
Kevin
-->
<!-- test
in:
3 3
6 4 7
out:
Nicky
-->
<!-- test
in:
2 1000000000
1000000000 999999999
out:
Kevin
-->

### Example 6 — Game on Tree (Green Hackenbush)  ·  ★ ≈2100

- **Source:** [AtCoder AGC017 D · Game on Tree](https://atcoder.jp/contests/agc017/tasks/agc017_d)
- **Difficulty:** ≈2100 (est.; AtCoder difficulty ≈2156)
- **Problem:** A tree with $N \le 10^5$ vertices rooted at vertex 1. A move deletes an edge together with the component that no longer contains vertex 1. Alice first; who cannot move loses.
- **Thinking from first principles:** This is Green Hackenbush on a rooted tree. Subtrees of different children never interact, so each child branch is a component; a branch = one edge on top of the child's subtree, value $g(c)+1$ (§1.9).

<details><summary>Solution</summary>

$g(v) = \bigoplus_{c} (g(c)+1)$; Alice wins iff $g(1) \ne 0$. Compute with an explicit BFS order (no recursion — $N=10^5$ deep paths). Verified against exhaustive play on random trees with $\le 12$ vertices. $O(N)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<vector<int>> adj(n + 1);
    for (int i = 0; i < n - 1; i++) { int x, y; cin >> x >> y; adj[x].push_back(y); adj[y].push_back(x); }
    vector<int> order, par(n + 1, 0), g(n + 1, 0);
    order.push_back(1); par[1] = -1;
    for (size_t i = 0; i < order.size(); i++)
        for (int u : adj[order[i]]) if (u != par[order[i]]) { par[u] = order[i]; order.push_back(u); }
    for (int i = n - 1; i >= 1; i--) { int v = order[i]; g[par[v]] ^= g[v] + 1; }   // children before parents
    cout << (g[1] ? "Alice" : "Bob") << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] head = new int[n + 1], nxt = new int[2 * (n - 1)], to = new int[2 * (n - 1)];
        Arrays.fill(head, -1);
        for (int i = 0, e = 0; i < n - 1; i++) {
            int x = in.nextInt(), y = in.nextInt();
            to[e] = y; nxt[e] = head[x]; head[x] = e++;
            to[e] = x; nxt[e] = head[y]; head[y] = e++;
        }
        int[] order = new int[n], par = new int[n + 1], g = new int[n + 1];
        int sz = 0;
        order[sz++] = 1; par[1] = -1;
        for (int i = 0; i < sz; i++) {
            int v = order[i];
            for (int e = head[v]; e != -1; e = nxt[e]) if (to[e] != par[v]) { par[to[e]] = v; order[sz++] = to[e]; }
        }
        for (int i = n - 1; i >= 1; i--) { int v = order[i]; g[par[v]] ^= g[v] + 1; }
        System.out.println(g[1] != 0 ? "Alice" : "Bob");
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
5
1 2
2 3
2 4
4 5
out:
Alice
-->
<!-- test
in:
3
1 2
1 3
out:
Bob
-->
<!-- test
in:
2
1 2
out:
Alice
-->
<!-- test
in:
5
1 2
2 3
1 4
4 5
out:
Bob
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Apply the per-component transform before XOR.** $\bigoplus (a_i \bmod 4)$, not $(\bigoplus a_i) \bmod 4$. Each component becomes its own Nim heap.
2. **Splitting into $k$ equal parts only depends on $k \bmod 2$.** $x \oplus x = 0$ — don't simulate $k$ piles.
3. **Bound the mex array by the out-degree.** A `seen` array of size $d+1$ per vertex keeps Grundy DP linear; a global `set<int>` is a 10× slowdown.
4. **Grundy values can be large** (Nim heaps up to $10^9$; Grundy's game reaches $\sim 200$ by $n=4\cdot 10^4$). Don't store them in `char` without checking.
5. **Periodicity needs proof or an exact certificate.** For subtraction games, the first repeated window of length $s_{\max}$ is exact (§3.1). For splitting games use the Guy–Smith bound; "it looked periodic for 100 terms" has failed many people (Kayles' pre-period is 71).
6. **Sprague–Grundy needs independence and normal play.** If one move can touch two components (Wythoff, Moore's Nim) or the last mover loses (misère), the XOR rule is wrong — see [file 03](03-game-variants-misere-staircase-hackenbush.md).
7. **XOR of tokens on a DAG:** tokens on the same vertex cancel; tokens that *interact* (blocking, capturing) are not independent.
8. **Hackenbush on trees: process children before parents iteratively.** Recursive DFS on a $10^5$-path overflows the Java stack (use an explicit order, or `new Thread(null, r, "", 1 << 28)`).
9. **Java `HashMap<List<Integer>,…>` for windows** is fine for small $s_{\max}$; for large windows hash them into a `long` instead.
10. **Memoised brute force for pattern finding** must use the *full* state (Example 4: remaining stones *and* the set of used amounts), or you'll "discover" a wrong pattern.

---

## 7. Going further (toward 2400–2600+)

- **Grundy values with huge state but small value**: compute only the *distribution* of values ([CF 1411G · No Game No Life](https://codeforces.com/problemset/problem/1411/G) — 2700, Grundy $\le \sqrt{2m}$, then linear algebra on probabilities).
- **Grundy on functional graphs / cycles**: [AtCoder ARC079 F · Namori Grundy](https://atcoder.jp/contests/arc079/tasks/arc079_d) — Grundy values on a graph with one cycle, solved by trying two values on the cycle.
- **Counting positions with XOR 0**: combine Sprague–Grundy with DP / linear basis ([CF 662A · Gambling Nim](https://codeforces.com/problemset/problem/662/A) — 2400, see [XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)), or XOR convolution with Walsh–Hadamard ([FFT/NTT file](../15-Advanced-Math/03-fft-and-ntt.md)).
- **Grundy of products / Nim multiplication** (Tartan theorem, coin-turning games) is IGM-level lore — rare.
- **Octal games and periodicity certificates** ([CF 1704F · Colouring Game](https://codeforces.com/problemset/problem/1704/F) — 2600 has a long eventual period).
- Misère, staircase, Wythoff, Hackenbush with cycles: [file 03](03-game-variants-misere-staircase-hackenbush.md).

---

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1730 · Nim Game I](https://cses.fi/problemset/task/1730)
- [ ] [CSES 1098 · Nim Game II](https://cses.fi/problemset/task/1098)
- [ ] [AtCoder DP K · Stones](https://atcoder.jp/contests/dp/tasks/dp_k)
- [ ] [CF 1382B · Sequential Nim](https://codeforces.com/problemset/problem/1382/B) — 1100
- [ ] [CF 1965A · Everything Nim](https://codeforces.com/problemset/problem/1965/A) — 1400

**1400–1900**
- [ ] [CF 1033C · Permutation Game](https://codeforces.com/problemset/problem/1033/C) — 1600
- [ ] [CF 1194D · 1-2-K Game](https://codeforces.com/problemset/problem/1194/D) — 1700
- [ ] [AtCoder ABC368 F · Dividing Game](https://atcoder.jp/contests/abc368/tasks/abc368_f)
- [ ] [AtCoder ABC297 G · Constrained Nim 2](https://atcoder.jp/contests/abc297/tasks/abc297_g)
- [ ] [CSES 2207 · Grundy's Game](https://cses.fi/problemset/task/2207)
- [ ] [CF 1383B · GameGame](https://codeforces.com/problemset/problem/1383/B) — 1900

**1900–2300**
- [ ] [CF 15C · Industrial Nim](https://codeforces.com/problemset/problem/15/C) — 2000
- [ ] [CF 87C · Interesting Game](https://codeforces.com/problemset/problem/87/C) — 2000
- [ ] [CF 1147C · Thanos Nim](https://codeforces.com/problemset/problem/1147/C) — 2000
- [ ] [CF 768E · Game of Stones](https://codeforces.com/problemset/problem/768/E) — 2100
- [ ] [CF 2004E · Not a Nim Problem](https://codeforces.com/problemset/problem/2004/E) — 2100
- [ ] [AtCoder AGC017 D · Game on Tree](https://atcoder.jp/contests/agc017/tasks/agc017_d)
- [ ] [AtCoder ABC206 F · Interval Game 2](https://atcoder.jp/contests/abc206/tasks/abc206_f)
- [ ] [CF 603C · Lieges of Legendre](https://codeforces.com/problemset/problem/603/C) — 2200
- [ ] [CF 850C · Arpa and a game with Mojtaba](https://codeforces.com/problemset/problem/850/C) — 2200
- [ ] [CF 255E · Furlo and Rublo and Game](https://codeforces.com/problemset/problem/255/E) — 2200
- [ ] [CF 305E · Playing with String](https://codeforces.com/problemset/problem/305/E) — 2300
- [ ] [CF 317D · Game with Powers](https://codeforces.com/problemset/problem/317/D) — 2300

**2400+**
- [ ] [CF 1312F · Attack on Red Kingdom](https://codeforces.com/problemset/problem/1312/F) — 2500
- [ ] [CF 1823E · Removing Graph](https://codeforces.com/problemset/problem/1823/E) — 2500
- [ ] [CF 1704F · Colouring Game](https://codeforces.com/problemset/problem/1704/F) — 2600
- [ ] [AtCoder ARC079 F · Namori Grundy](https://atcoder.jp/contests/arc079/tasks/arc079_d)
- [ ] [CF 1411G · No Game No Life](https://codeforces.com/problemset/problem/1411/G) — 2700
- [ ] [CF 1149E · Election Promises](https://codeforces.com/problemset/problem/1149/E) — 3200

---

## 9. LeetCode / FAANG cross-reference

- [LC 292 · Nim Game](https://leetcode.com/problems/nim-game/) — Easy — one pile, subtraction $\{1,2,3\}$: $g(n)=n \bmod 4$.
- [LC 1908 · Game of Nim](https://leetcode.com/problems/game-of-nim/) — Medium 🔒 — plain Nim: XOR of piles.
- [LC 1510 · Stone Game IV](https://leetcode.com/problems/stone-game-iv/) — Hard — subtraction game with perfect squares; W/L DP in $O(n\sqrt n)$.
- [LC 294 · Flip Game II](https://leetcode.com/problems/flip-game-ii/) — Medium 🔒 — each maximal run of `+` is an independent component (a Kayles-like splitting game); Grundy DP turns the exponential memo into $O(n^2)$.

Sprague–Grundy is rare in interviews: interviewers expect the memoised win/lose recursion. Mentioning that independent components combine by XOR is a strong signal if the problem has them (Flip Game II).

---

## 10. Self-check

1. Prove Bouton's theorem, including why $a_i \oplus s < a_i$ for the chosen pile.
2. Why is $g(v) = 0$ exactly the P-positions?
3. Prove the Sprague–Grundy sum theorem for two components.
4. Why is a subtraction game with finite $S$ eventually periodic, and how do you find the exact preperiod?
5. What is the value of "a pile of $2x$ split into $k$ piles of $x$"?
6. Derive $g(v) = \bigoplus (g(c)+1)$ for Green Hackenbush on a tree.
7. Why does a vertex of Grundy value $k$ in a DAG force $m \ge k(k+1)/2$ edges?
8. Name two situations where XOR of Grundy values is *not* the answer.

<details><summary>Answers</summary>

1. §1.2; bit $h$ (the top bit of $s$) is set in $a_i$ and cleared in $a_i\oplus s$, bits above $h$ are unchanged, so the number decreases.
2. Value 0 means no option has value 0 (all options N); value $>0$ means some option has value 0 (by mex). Induction gives the equivalence.
3. §1.4: no option has value $a\oplus b$; for $c<a\oplus b$, the top bit of $c\oplus a\oplus b$ lies in exactly one of $a,b$, reduce that component to the right value.
4. $g(n)$ depends only on the last $s_{\max}$ values; the window sequence of a finite automaton is rho-shaped. The first window seen twice gives $n_0$ and $p$ exactly.
5. $g(x)$ XORed $k$ times: $0$ if $k$ even, $g(x)$ if $k$ odd.
6. §1.9: stalk = Nim heap; an edge on top of a tree of value $t$ has value $t+1$ (options $0$ and $g(T')+1$); independent branches XOR.
7. Pick witnesses of values $0..k$; the witness of value $j$ has $\ge j$ out-edges; they are distinct vertices, so the edges are distinct.
8. Misère play; moves that touch several components (Wythoff, Moore's Nim); games with scores; partisan games; components that interact.

</details>
