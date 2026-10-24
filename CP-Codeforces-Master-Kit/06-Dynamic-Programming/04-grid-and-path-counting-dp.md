# Grid and Path-Counting DP

> **Band:** 🟢→🟠 1100–2300 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [DP first principles](01-dp-first-principles-and-state-design.md), [binomials](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md), [modular inverses](../04-Number-Theory/02-modular-arithmetic-and-inverses.md)
> **You can say you know this when:** you can count or optimise monotone paths with obstacles in $O(nm)$; switch to binomials + "first obstacle" inclusion–exclusion when the grid is huge but obstacles are few; run two walkers in lock-step to handle "each cell counts once"; build a lexicographically minimal path by diagonals; and remove a range transition with running prefix sums.

A grid with right/down moves is the friendliest DAG there is: the topological order is simply row-major (or by anti-diagonal), and every problem in this file is a variation of "what do I need to remember at a cell?". The interesting cases are the ones where *the grid is too big*, *two paths interact*, or *transitions come from a whole range*.

---

## 1. First principles — why this works

### 1.1 Monotone paths form a DAG

Moves right $(i, j+1)$ and down $(i+1, j)$ strictly increase $i + j$, so the cell graph is acyclic and any order that visits $(i-1,j)$ and $(i,j-1)$ before $(i,j)$ works (row-major does). Classify paths ending at $(i,j)$ by their last move:

$$\text{count: } f(i,j) = f(i-1,j) + f(i,j-1), \qquad \text{cost: } g(i,j) = a_{ij} + \min(g(i-1,j), g(i,j-1)).$$

Obstacles are cells with $f = 0$ (or $g = \infty$). That is the whole of [CSES 1638](https://cses.fi/problemset/task/1638) and [LC 62](https://leetcode.com/problems/unique-paths/)/[LC 64](https://leetcode.com/problems/minimum-path-sum/). With one rolling row the memory is $O(m)$.

**Multiplicative or non-additive objectives** need a transformation. Minimising the trailing zeros of a product along the path (CF 2B) is not additive — but the number of trailing zeros of a product is $\min(\#2, \#5)$ of the factor counts, and $\min_{\text{path}} \min(\#2, \#5) = \min(\min_{\text{path}} \#2, \min_{\text{path}} \#5)$, so two independent additive DPs solve it (Example 4). The general move: if the objective is $\min/\max$ of several additive quantities, swap the order of the two $\min$s and run one DP per quantity.

### 1.2 Huge grid, few obstacles — count by the first obstacle

Without obstacles, a path from $(r_1,c_1)$ to $(r_2,c_2)$ is a word of $\Delta r$ D's and $\Delta c$ R's:
$$P\big((r_1,c_1)\to(r_2,c_2)\big) = \binom{\Delta r + \Delta c}{\Delta r}, \qquad \Delta r, \Delta c \ge 0.$$

With $h, w \le 10^5$ the table has $10^{10}$ cells, but if there are only $k \le 2000$ obstacles we can count *bad* paths through them. Overlaps make naive subtraction wrong (a path can hit several obstacles), so classify bad paths by **the first obstacle they hit** — a canonical choice, so each bad path is counted once. Sort obstacles by $(r, c)$; then

$$g(i) = P(\text{start} \to o_i) - \sum_{j \ne i,\ o_j \le o_i} g(j)\, P(o_j \to o_i),$$

where $g(i)$ = number of paths from the start to $o_i$ that avoid every other obstacle, and $o_j \le o_i$ means $r_j \le r_i, c_j \le c_i$. Treat the target as obstacle $k+1$: the answer is $g(k+1)$. $O(k^2)$ after $O(h+w)$ factorial precomputation. This is inclusion–exclusion organised as a DP ([inclusion–exclusion](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md)).

### 1.3 Two walkers — synchronise to detect shared cells

"Go from the top-left to the bottom-right and back, collecting values; each cell counts once" (CF 213C, LC 741). A round trip is two forward paths. Running the DP on the two paths *independently* fails because the "count once" rule couples them. The state must contain both walkers — $(r_1, c_1, r_2, c_2)$ is $O(n^4)$.

The reduction: move both walkers **one step at a time together**. After $d$ steps each walker satisfies $r + c = d$, so a walker is determined by its row, and the state is $(d, r_1, r_2)$: $O(n^3)$. Lock-step has a second, crucial benefit: two monotone paths can share a cell $(r,c)$ only by visiting it at the same step $d = r+c$, so "shared cell" is exactly "$r_1 = r_2$ in the same state" — checkable locally. Values are added once per state: $a(r_1, d-r_1) + [r_1 \ne r_2]\, a(r_2, d-r_2)$.

### 1.4 DP over anti-diagonals — lexicographically smallest path

All cells reachable in exactly $d$ steps lie on the anti-diagonal $r + c = d$. To build the lexicographically smallest string along a path ([CSES 3359](https://cses.fi/problemset/task/3359)), note that the first character on which two strings differ decides — so at each diagonal, among the cells reachable with the *current minimal prefix*, keep only those whose letter equals the minimum letter of the next diagonal. The "state" is a **set** of cells (all equivalent: same prefix, and any of them may lead to the best future), the transition is a BFS step. $O(nm)$. Trying a min-string DP per cell instead stores strings of length $O(n)$ per cell — $O(n^3)$ memory.

### 1.5 Range transitions — running sums

If a move may jump any distance right or down (a rook) without crossing obstacles, then $f(i,j) = \sum_{k} f(i,k) + \sum_{k} f(k,j)$ over the contiguous free run to the left and above: $O(n+m)$ per cell. The predecessors form a contiguous range in a row and in a column, so keep a running sum per row run and per column run, reset at obstacles: $O(1)$ per cell (Example 5, and [prefix-sum optimisation](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md)).

### 1.6 Adding a dimension for a path property

"Number of paths whose sum is divisible by $K$" (LC 2435) or "a path with an even number of $X$" needs the property in the state: $f(i,j,s)$ with $s$ = sum mod $K$. The rule from [first principles](01-dp-first-principles-and-state-design.md) §1.11 applies verbatim.

When a property is a *binary* choice over two extreme values (CF 1695C *Zero Path*: can the path sum be exactly 0 with $\pm1$ cells?), it is often enough to compute the **minimum and maximum** achievable values: neighbouring paths differ by a small step, so every value of the right parity between min and max is achievable.

### 1.7 Lattice-path combinatorics you should know

- **Reflection principle:** paths from $(0,0)$ to $(n,n)$ never going above the diagonal $=\binom{2n}{n} - \binom{2n}{n+1} = C_n$ (Catalan). Paths that touch the forbidden line are in bijection (reflect the part before the first touch) with paths to a reflected endpoint ([Catalan and friends](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md)).
- **LGV lemma:** the number of tuples of *vertex-disjoint* paths $A_i \to B_i$ in a DAG equals $\det\big[e(A_i, B_j)\big]$ when only the identity pairing can be disjoint. For two paths: $e(A_1,B_1)e(A_2,B_2) - e(A_1,B_2)e(A_2,B_1)$ (CF 348D Turtles; [LGV](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)).
- **Delannoy numbers** (moves right, down, diagonal): $D(m,n) = \sum_k \binom{m}{k}\binom{n}{k}2^k$.
- **Narrow grids, huge length:** a fixed transition between columns of height $h \le 6$ is a $2^h$-or-smaller matrix — use matrix exponentiation ([matrix power](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md)); tilings are [broken profile DP](11-broken-profile-dp.md).

---

## 2. Formulas, definitions and identities

| Quantity | Formula | Cost |
|---|---|---|
| paths $(0,0)\to(n,m)$ | $\binom{n+m}{n}$ | $O(1)$ after factorials |
| paths with obstacles | $f(i,j) = f(i-1,j)+f(i,j-1)$, $f = 0$ on obstacles | $O(nm)$ |
| few obstacles, huge grid | $g(i) = P(s\to o_i) - \sum_{o_j\le o_i} g(j)P(o_j\to o_i)$ | $O(k^2)$ |
| min path sum | $g(i,j) = a_{ij} + \min(g(i-1,j), g(i,j-1))$ | $O(nm)$ |
| two walkers | state $(d, r_1, r_2)$, $c = d - r$ | $O((n+m) n^2)$ |
| paths below diagonal | $C_n = \frac{1}{n+1}\binom{2n}{n}$ | |
| ballot / first-passage | $\binom{2n}{n} - \binom{2n}{n+1}$ (reflection) | |
| two disjoint paths (LGV) | $e_{11}e_{22} - e_{12}e_{21}$ | |
| Delannoy | $D(m,n) = \sum_k \binom{m}{k}\binom{n}{k}2^k$ | |

**Binomials mod a prime $p$:** precompute $n!$ and $(n!)^{-1}$ up to $N$ in $O(N)$ using one inverse ($\text{inv}(N!) = (N!)^{p-2}$) and $\text{inv}((i-1)!) = i\cdot\text{inv}(i!)$; then $\binom{n}{k} = n!\,(k!)^{-1}((n-k)!)^{-1}$.

**Trailing zeros of a product:** $\text{tz}(\prod x_i) = \min(\sum v_2(x_i), \sum v_5(x_i))$ for non-zero factors.

**Cells on anti-diagonal $d$** in an $n\times m$ grid: $r \in [\max(0, d-m+1), \min(n-1, d)]$.

---

## 3. Implementation (C++ and Java)

### 3.1 Count paths and min-cost path with reconstruction

```cpp
const long long MOD = 1'000'000'007;

// grid[i][j] == '#' is blocked. Number of right/down paths from (0,0) to (n-1,m-1).
long long countPaths(const vector<string>& grid) {
    int n = grid.size(), m = grid[0].size();
    vector<long long> f(m, 0);                         // rolling row
    for (int i = 0; i < n; i++)
        for (int j = 0; j < m; j++) {
            if (grid[i][j] == '#') { f[j] = 0; continue; }
            if (i == 0 && j == 0) { f[j] = 1; continue; }
            if (j > 0) f[j] = (f[j] + f[j - 1]) % MOD;   // f[j] still holds the row above
        }
    return f[m - 1];
}

// Minimum path sum and one optimal path as a string of 'R'/'D'.
pair<long long, string> minPath(const vector<vector<long long>>& a) {
    int n = a.size(), m = a[0].size();
    vector<vector<long long>> g(n, vector<long long>(m));
    for (int i = 0; i < n; i++)
        for (int j = 0; j < m; j++) {
            long long best = (i == 0 && j == 0) ? 0 : LLONG_MAX;
            if (i > 0) best = min(best, g[i - 1][j]);
            if (j > 0) best = min(best, g[i][j - 1]);
            g[i][j] = best + a[i][j];
        }
    string path;
    for (int i = n - 1, j = m - 1; i > 0 || j > 0;) {
        if (i > 0 && g[i - 1][j] + a[i][j] == g[i][j]) { path += 'D'; i--; }
        else { path += 'R'; j--; }
    }
    reverse(path.begin(), path.end());
    return {g[n - 1][m - 1], path};
}
```

```java
static final long MOD = 1_000_000_007L;

static long countPaths(String[] grid) {
    int n = grid.length, m = grid[0].length();
    long[] f = new long[m];
    for (int i = 0; i < n; i++)
        for (int j = 0; j < m; j++) {
            if (grid[i].charAt(j) == '#') { f[j] = 0; continue; }
            if (i == 0 && j == 0) { f[j] = 1; continue; }
            if (j > 0) f[j] = (f[j] + f[j - 1]) % MOD;
        }
    return f[m - 1];
}

// Returns the minimum sum; the path ('R'/'D') is written into out[0].
static long minPath(long[][] a, String[] out) {
    int n = a.length, m = a[0].length;
    long[][] g = new long[n][m];
    for (int i = 0; i < n; i++)
        for (int j = 0; j < m; j++) {
            long best = (i == 0 && j == 0) ? 0 : Long.MAX_VALUE;
            if (i > 0) best = Math.min(best, g[i - 1][j]);
            if (j > 0) best = Math.min(best, g[i][j - 1]);
            g[i][j] = best + a[i][j];
        }
    StringBuilder path = new StringBuilder();
    for (int i = n - 1, j = m - 1; i > 0 || j > 0;) {
        if (i > 0 && g[i - 1][j] + a[i][j] == g[i][j]) { path.append('D'); i--; }
        else { path.append('R'); j--; }
    }
    out[0] = path.reverse().toString();
    return g[n - 1][m - 1];
}
```

### 3.2 Binomial coefficients mod $p$

```cpp
struct Binom {
    static constexpr long long MOD = 1'000'000'007;
    vector<long long> fact, inv;
    static long long power(long long b, long long e) {
        long long r = 1;
        for (b %= MOD; e > 0; e >>= 1, b = b * b % MOD)
            if (e & 1) r = r * b % MOD;
        return r;
    }
    explicit Binom(int N) : fact(N + 1), inv(N + 1) {
        fact[0] = 1;
        for (int i = 1; i <= N; i++) fact[i] = fact[i - 1] * i % MOD;
        inv[N] = power(fact[N], MOD - 2);
        for (int i = N; i > 0; i--) inv[i - 1] = inv[i] * i % MOD;
    }
    long long C(int n, int k) const {
        if (k < 0 || k > n) return 0;
        return fact[n] * inv[k] % MOD * inv[n - k] % MOD;
    }
};
```

```java
static final class Binom {
    static final long MOD = 1_000_000_007L;
    final long[] fact, inv;

    static long power(long b, long e) {
        long r = 1;
        b %= MOD;
        for (; e > 0; e >>= 1, b = b * b % MOD)
            if ((e & 1) == 1) r = r * b % MOD;
        return r;
    }

    Binom(int N) {
        fact = new long[N + 1];
        inv = new long[N + 1];
        fact[0] = 1;
        for (int i = 1; i <= N; i++) fact[i] = fact[i - 1] * i % MOD;
        inv[N] = power(fact[N], MOD - 2);
        for (int i = N; i > 0; i--) inv[i - 1] = inv[i] * i % MOD;
    }

    long C(int n, int k) {
        if (k < 0 || k > n) return 0;
        return fact[n] * inv[k] % MOD * inv[n - k] % MOD;
    }
}
```

---

## 4. Recognising the pattern

| Signal | Technique |
|---|---|
| moves only right/down (or a fixed DAG of directions) | row-major DP |
| "number of paths", grid up to $10^3 \times 10^3$ | $f(i,j)=f(i-1,j)+f(i,j-1)$ |
| grid up to $10^5\times10^5$ (or $10^9$), $\le 3000$ blocked cells | binomials + first-obstacle DP |
| "go there and back", "two robots", "each cell collected once" | two walkers in lock-step, $(d, r_1, r_2)$ |
| "lexicographically smallest string along a path" | BFS by anti-diagonal keeping the set of best cells |
| move any distance in a row/column | running prefix sums per row/column run |
| "sum divisible by $K$", "XOR equals $x$" along the path | add the residue/XOR to the state (or meet in the middle on the diagonal for XOR with huge range: CF 1006F) |
| product / trailing zeros / sign along path | factor into additive parts, one DP per part |
| moves in all four directions | not a DAG — BFS/Dijkstra ([shortest paths](../09-Graphs/02-shortest-paths.md)) |
| grid height $\le 10$, cover/tile | [broken profile DP](11-broken-profile-dp.md) |

---

## 5. Worked examples (graded)

### Example 1 — Grid Paths  ·  ★ ≈1100 (est.)

- **Source:** [CSES 1638 · Grid Paths I](https://cses.fi/problemset/task/1638)
- **Difficulty:** ≈1100 (est.)
- **Problem:** An $n \times n$ grid ($n \le 1000$) with free cells `.` and traps `*`. Count right/down paths from the top-left to the bottom-right avoiding traps, mod $10^9+7$.
- **Thinking from first principles:** Fix the last move. A trap is a state with zero paths — including the start cell (answer 0). One rolling row suffices.

<details><summary>Solution</summary>

$O(n^2)$ time, $O(n)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const long long MOD = 1'000'000'007;
    int n;
    cin >> n;
    vector<string> g(n);
    for (auto& row : g) cin >> row;
    vector<long long> f(n, 0);
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            if (g[i][j] == '*') { f[j] = 0; continue; }
            if (i == 0 && j == 0) { f[j] = 1; continue; }
            if (j > 0) f[j] = (f[j] + f[j - 1]) % MOD;
        }
    cout << f[n - 1] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static String ns() throws IOException {
        int c = IN.read();
        while (c <= ' ') c = IN.read();
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = IN.read(); }
        return sb.toString();
    }

    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        int n = Integer.parseInt(ns());
        long[] f = new long[n];
        for (int i = 0; i < n; i++) {
            String row = ns();
            for (int j = 0; j < n; j++) {
                if (row.charAt(j) == '*') { f[j] = 0; continue; }
                if (i == 0 && j == 0) { f[j] = 1; continue; }
                if (j > 0) f[j] = (f[j] + f[j - 1]) % MOD;
            }
        }
        System.out.println(f[n - 1]);
    }
}
```

</details>

<!-- test
in:
4
....
.*..
...*
*...
out:
3
-->
<!-- test
in:
1
*
out:
0
-->
<!-- test
in:
2
..
..
out:
2
-->

### Example 2 — Minimal Grid Path  ·  ★ ≈1700 (est.)

- **Source:** [CSES 3359 · Minimal Grid Path](https://cses.fi/problemset/task/3359)
- **Difficulty:** ≈1700 (est.)
- **Problem:** An $n \times n$ grid of uppercase letters ($n \le 3000$). Among right/down paths from the top-left to the bottom-right, print the lexicographically smallest string of letters.
- **Thinking from first principles:** All strings have length $2n-1$, so lexicographic order is decided greedily: the $d$-th character must be as small as possible given that the first $d-1$ are already minimal. After $d$ steps the walker is on anti-diagonal $d$. The cells on diagonal $d$ that can be reached *with the minimal prefix* are all equivalent for the future, so the state is the set $S_d$ of such cells. Next character = minimum letter among successors of $S_d$; $S_{d+1}$ = successors with that letter. Storing a best string per cell would cost $O(n^3)$.

<details><summary>Solution</summary>

Two boolean rows indexed by the row number $r$ (the column is $d - r$). $O(n^2)$ time.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<string> g(n);
    for (auto& row : g) cin >> row;
    vector<char> cur(n, 0), nxt(n, 0);                 // cur[r]: cell (r, d-r) is in the best set
    cur[0] = 1;
    string ans(1, g[0][0]);
    for (int d = 0; d < 2 * n - 2; d++) {
        char best = 'Z' + 1;
        for (int r = max(0, d - n + 1); r <= min(n - 1, d); r++) {
            if (!cur[r]) continue;
            int c = d - r;
            if (r + 1 < n) best = min(best, g[r + 1][c]);
            if (c + 1 < n) best = min(best, g[r][c + 1]);
        }
        fill(nxt.begin(), nxt.end(), 0);
        for (int r = max(0, d - n + 1); r <= min(n - 1, d); r++) {
            if (!cur[r]) continue;
            int c = d - r;
            if (r + 1 < n && g[r + 1][c] == best) nxt[r + 1] = 1;
            if (c + 1 < n && g[r][c + 1] == best) nxt[r] = 1;
        }
        ans += best;
        swap(cur, nxt);
    }
    cout << ans << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static String ns() throws IOException {
        int c = IN.read();
        while (c <= ' ') c = IN.read();
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = IN.read(); }
        return sb.toString();
    }

    public static void main(String[] args) throws IOException {
        int n = Integer.parseInt(ns());
        char[][] g = new char[n][];
        for (int i = 0; i < n; i++) g[i] = ns().toCharArray();
        boolean[] cur = new boolean[n], nxt = new boolean[n];
        cur[0] = true;
        StringBuilder ans = new StringBuilder();
        ans.append(g[0][0]);
        for (int d = 0; d < 2 * n - 2; d++) {
            char best = (char) ('Z' + 1);
            int lo = Math.max(0, d - n + 1), hi = Math.min(n - 1, d);
            for (int r = lo; r <= hi; r++) {
                if (!cur[r]) continue;
                int c = d - r;
                if (r + 1 < n && g[r + 1][c] < best) best = g[r + 1][c];
                if (c + 1 < n && g[r][c + 1] < best) best = g[r][c + 1];
            }
            Arrays.fill(nxt, false);
            for (int r = lo; r <= hi; r++) {
                if (!cur[r]) continue;
                int c = d - r;
                if (r + 1 < n && g[r + 1][c] == best) nxt[r + 1] = true;
                if (c + 1 < n && g[r][c + 1] == best) nxt[r] = true;
            }
            ans.append(best);
            boolean[] t = cur; cur = nxt; nxt = t;
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
4
AACA
BABC
ABDA
AACA
out:
AAABACA
-->
<!-- test
in:
3
ZZZ
ZAZ
ZZA
out:
ZZAZA
-->
<!-- test
in:
1
Q
out:
Q
-->

### Example 3 — Rook paths with running sums  ·  ★ ≈1700 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈1700 (est.)
- **Problem:** An $n\times m$ grid ($n, m \le 2000$) of `.` (free) and `#` (blocked); the top-left cell is free. A rook starts at the top-left and wants to reach the bottom-right. Each move goes **any positive number of cells** to the right or down, and may not land on or pass over a `#`. Count move sequences mod $10^9+7$ (0 if the target is blocked).
- **Thinking from first principles:** Fix the last move: it came from some cell to the left in the same row, or above in the same column, with no `#` in between. So $f(i,j) = \sum_{k \in \text{run left}} f(i,k) + \sum_{k\in\text{run above}} f(k,j)$ — $O(n+m)$ per cell, $8\cdot10^9$ total: too slow. The predecessors are a *contiguous run*; a running sum per row (reset at `#`) and per column (reset at `#`) gives each sum in $O(1)$.

<details><summary>Solution</summary>

Row-major. `rowAcc` = sum of $f$ over the current free run in this row to the left; `colAcc[j]` = sum over the current free run above in column $j$. Read both before adding $f(i,j)$ to them. $O(nm)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const long long MOD = 1'000'000'007;
    int n, m;
    cin >> n >> m;
    vector<string> g(n);
    for (auto& row : g) cin >> row;
    vector<long long> colAcc(m, 0);
    long long last = 0;
    for (int i = 0; i < n; i++) {
        long long rowAcc = 0;
        for (int j = 0; j < m; j++) {
            if (g[i][j] == '#') { rowAcc = 0; colAcc[j] = 0; last = 0; continue; }
            long long f = (i == 0 && j == 0) ? 1 : (rowAcc + colAcc[j]) % MOD;
            rowAcc = (rowAcc + f) % MOD;            // the run now includes (i, j)
            colAcc[j] = (colAcc[j] + f) % MOD;
            last = f;
        }
    }
    cout << last << "\n";                             // f at (n-1, m-1), or 0 if blocked
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static String ns() throws IOException {
        int c = IN.read();
        while (c <= ' ') c = IN.read();
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = IN.read(); }
        return sb.toString();
    }

    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        int n = Integer.parseInt(ns()), m = Integer.parseInt(ns());
        long[] colAcc = new long[m];
        long last = 0;
        for (int i = 0; i < n; i++) {
            String row = ns();
            long rowAcc = 0;
            for (int j = 0; j < m; j++) {
                if (row.charAt(j) == '#') { rowAcc = 0; colAcc[j] = 0; last = 0; continue; }
                long f = (i == 0 && j == 0) ? 1 : (rowAcc + colAcc[j]) % MOD;
                rowAcc = (rowAcc + f) % MOD;
                colAcc[j] = (colAcc[j] + f) % MOD;
                last = f;
            }
        }
        System.out.println(last);
    }
}
```

</details>

<!-- test
in:
3 3
...
.#.
...
out:
8
-->
<!-- test
in:
2 4
....
#...
out:
8
-->
<!-- test
in:
1 1
.
out:
1
-->

### Example 4 — The least round way  ·  ★ 2000

- **Source:** [CF 2B · The least round way](https://codeforces.com/problemset/problem/2/B) — 2000
- **Difficulty:** 2000
- **Problem:** An $n \times n$ matrix ($2 \le n \le 1000$) of non-negative integers $\le 10^9$. Find a right/down path from the top-left to the bottom-right whose product has the fewest trailing zeros; print the count and the path (`R`/`D`). (The number 0 has one trailing zero.)
- **Thinking from first principles:** The product's trailing zeros are $\min(\#2, \#5)$, not additive. But $\min_{\text{path}}\min(\#2,\#5) = \min(\min_{\text{path}}\#2, \min_{\text{path}}\#5)$: run two independent min-sum DPs and take the better. Dead end to avoid: a single DP storing $(\#2, \#5)$ pairs and comparing $\min$s — the min of a pair is not a monotone key, so the DP would discard paths that become optimal later. **Zeros:** a path through a 0 has exactly one trailing zero. Treat each 0 as the number 10 (one 2, one 5) inside the DPs — then any DP path through a zero scores $\ge 1$, which is honest — and if the DP optimum exceeds 1 while a zero exists, answer 1 with a path through that zero.

<details><summary>Solution</summary>

Factor counts $c_2, c_5$ per cell; two min-sum tables; reconstruct from the better table; zero override. $O(n^2 \log a)$ for factoring, $O(n^2)$ DP.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<vector<int>> c[2];                          // c[0]: count of 2s, c[1]: count of 5s
    c[0].assign(n, vector<int>(n)); c[1].assign(n, vector<int>(n));
    int zr = -1, zc = -1;
    for (int i = 0; i < n; i++)
        for (int j = 0; j < n; j++) {
            long long x;
            cin >> x;
            if (x == 0) { zr = i; zc = j; x = 10; }   // a zero behaves like 10 inside the DPs
            int a = 0, b = 0;
            while (x % 2 == 0) { x /= 2; a++; }
            while (x % 5 == 0) { x /= 5; b++; }
            c[0][i][j] = a; c[1][i][j] = b;
        }
    int bestVal = INT_MAX;
    string bestPath;
    for (int t = 0; t < 2; t++) {
        vector<vector<int>> g(n, vector<int>(n));
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++) {
                int b = (i == 0 && j == 0) ? 0 : INT_MAX;
                if (i > 0) b = min(b, g[i - 1][j]);
                if (j > 0) b = min(b, g[i][j - 1]);
                g[i][j] = b + c[t][i][j];
            }
        if (g[n - 1][n - 1] < bestVal) {
            bestVal = g[n - 1][n - 1];
            string p;
            for (int i = n - 1, j = n - 1; i > 0 || j > 0;) {
                if (i > 0 && g[i - 1][j] + c[t][i][j] == g[i][j]) { p += 'D'; i--; }
                else { p += 'R'; j--; }
            }
            reverse(p.begin(), p.end());
            bestPath = p;
        }
    }
    if (zr != -1 && bestVal > 1) {                    // go right to the zero's column, down, then right
        bestVal = 1;
        bestPath = string(zc, 'R') + string(n - 1, 'D') + string(n - 1 - zc, 'R');
    }
    cout << bestVal << "\n" << bestPath << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        int[][][] c = new int[2][n][n];
        int zr = -1, zc = -1;
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++) {
                long x = nl();
                if (x == 0) { zr = i; zc = j; x = 10; }
                int a = 0, b = 0;
                while (x % 2 == 0) { x /= 2; a++; }
                while (x % 5 == 0) { x /= 5; b++; }
                c[0][i][j] = a; c[1][i][j] = b;
            }
        int bestVal = Integer.MAX_VALUE;
        String bestPath = "";
        for (int t = 0; t < 2; t++) {
            int[][] g = new int[n][n];
            for (int i = 0; i < n; i++)
                for (int j = 0; j < n; j++) {
                    int b = (i == 0 && j == 0) ? 0 : Integer.MAX_VALUE;
                    if (i > 0) b = Math.min(b, g[i - 1][j]);
                    if (j > 0) b = Math.min(b, g[i][j - 1]);
                    g[i][j] = b + c[t][i][j];
                }
            if (g[n - 1][n - 1] < bestVal) {
                bestVal = g[n - 1][n - 1];
                StringBuilder p = new StringBuilder();
                for (int i = n - 1, j = n - 1; i > 0 || j > 0;) {
                    if (i > 0 && g[i - 1][j] + c[t][i][j] == g[i][j]) { p.append('D'); i--; }
                    else { p.append('R'); j--; }
                }
                bestPath = p.reverse().toString();
            }
        }
        if (zr != -1 && bestVal > 1) {
            bestVal = 1;
            bestPath = "R".repeat(zc) + "D".repeat(n - 1) + "R".repeat(n - 1 - zc);
        }
        System.out.println(bestVal + "\n" + bestPath);
    }
}
```

</details>

<!-- test
in:
3
25 4 2
4 25 20
4 1 2
out:
2
DDRR
-->
<!-- test
in:
2
1 2
5 4
out:
0
RD
-->
<!-- test
in:
2
4 0
25 1
out:
1
RD
-->

### Example 5 — Relay Race (two walkers)  ·  ★ 2000

- **Source:** [CF 213C · Relay Race](https://codeforces.com/problemset/problem/213/C) — 2000
- **Difficulty:** 2000
- **Problem:** An $n\times n$ grid ($n \le 300$) of integers in $[-1000, 1000]$. One runner goes from $(1,1)$ to $(n,n)$ moving right/down, then another returns from $(n,n)$ to $(1,1)$ moving left/up. Maximise the sum of values of visited cells, each cell counted once.
- **Thinking from first principles:** Reverse the second run: two forward paths from $(1,1)$ to $(n,n)$. Separate DPs fail on shared cells; joint state $(r_1,c_1,r_2,c_2)$ is $8\cdot10^9$. Moving both in lock-step, after $d$ steps $c = d - r$, so $(d, r_1, r_2)$ has $2n\cdot n^2 = 5.4\cdot10^7$ states with 4 transitions — and two monotone paths can only meet at a cell at the same step, so "count once" is the local test $r_1 = r_2$. Values can be negative, so unreachable states need $-\infty$.

<details><summary>Solution</summary>

$F_d(r_1, r_2) = \text{val} + \max$ over the four predecessor pairs in $F_{d-1}$, with $\text{val} = a(r_1, d-r_1) + [r_1\ne r_2]\,a(r_2, d-r_2)$. Answer $F_{2n-2}(n-1, n-1)$. $O(n^3)$ time, $O(n^2)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<vector<int>> a(n, vector<int>(n));
    for (auto& row : a) for (auto& x : row) cin >> x;
    const int NEG = INT_MIN / 4;
    vector<vector<int>> F(n, vector<int>(n, NEG)), G(n, vector<int>(n, NEG));
    F[0][0] = a[0][0];
    for (int d = 1; d <= 2 * n - 2; d++) {
        int lo = max(0, d - (n - 1)), hi = min(n - 1, d);
        for (auto& row : G) fill(row.begin(), row.end(), NEG);
        for (int r1 = lo; r1 <= hi; r1++)
            for (int r2 = lo; r2 <= hi; r2++) {
                int best = NEG;
                for (int d1 = 0; d1 < 2; d1++)          // d1 = 1: walker 1 came from above
                    for (int d2 = 0; d2 < 2; d2++) {
                        int p1 = r1 - d1, p2 = r2 - d2;
                        if (p1 < 0 || p2 < 0) continue;
                        best = max(best, F[p1][p2]);
                    }
                if (best == NEG) continue;
                int val = a[r1][d - r1] + (r1 != r2 ? a[r2][d - r2] : 0);
                G[r1][r2] = best + val;
            }
        swap(F, G);
    }
    cout << F[n - 1][n - 1] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        int[][] a = new int[n][n];
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) a[i][j] = (int) nl();
        final int NEG = Integer.MIN_VALUE / 4;
        int[][] F = new int[n][n], G = new int[n][n];
        for (int[] row : F) Arrays.fill(row, NEG);
        F[0][0] = a[0][0];
        for (int d = 1; d <= 2 * n - 2; d++) {
            int lo = Math.max(0, d - (n - 1)), hi = Math.min(n - 1, d);
            for (int[] row : G) Arrays.fill(row, NEG);
            for (int r1 = lo; r1 <= hi; r1++)
                for (int r2 = lo; r2 <= hi; r2++) {
                    int best = F[r1][r2];
                    if (r1 > 0) best = Math.max(best, F[r1 - 1][r2]);
                    if (r2 > 0) best = Math.max(best, F[r1][r2 - 1]);
                    if (r1 > 0 && r2 > 0) best = Math.max(best, F[r1 - 1][r2 - 1]);
                    if (best == NEG) continue;
                    int val = a[r1][d - r1] + (r1 != r2 ? a[r2][d - r2] : 0);
                    G[r1][r2] = best + val;
                }
            int[][] t = F; F = G; G = t;
        }
        System.out.println(F[n - 1][n - 1]);
    }
}
```

</details>

<!-- test
in:
3
1 -5 3
2 8 -1
-4 6 7
out:
24
-->
<!-- test
in:
1
5
out:
5
-->
<!-- test
in:
2
1 2
3 4
out:
10
-->

### Example 6 — Gerald and Giant Chess  ·  ★ 2200

- **Source:** [CF 559C · Gerald and Giant Chess](https://codeforces.com/problemset/problem/559/C) — 2200 (same idea: [CSES 1078 · Grid Paths II](https://cses.fi/problemset/task/1078))
- **Difficulty:** 2200
- **Problem:** An $h\times w$ board ($h, w \le 10^5$) with $k \le 2000$ black cells (the corners are white). Count right/down paths from $(1,1)$ to $(h,w)$ avoiding black cells, mod $10^9+7$.
- **Thinking from first principles:** $10^{10}$ cells — no table. Few obstacles suggests "total minus bad", but bad paths may pass several black cells, so subtracting $\sum_i P(\text{through } o_i)$ over-subtracts. Make the decomposition canonical: classify each bad path by the **first** black cell it visits. Then $g(i)$ = paths to $o_i$ avoiding all other black cells satisfies $g(i) = P(s \to o_i) - \sum_{o_j \le o_i} g(j) P(o_j \to o_i)$, and the target is just one more "cell" in the list.

<details><summary>Solution</summary>

Sort cells by $(r,c)$, append $(h,w)$. Factorials up to $h+w$. $O(h + w + k^2)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

const long long MOD = 1'000'000'007;
long long power(long long b, long long e) {
    long long r = 1;
    for (b %= MOD; e > 0; e >>= 1, b = b * b % MOD)
        if (e & 1) r = r * b % MOD;
    return r;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int h, w, k;
    cin >> h >> w >> k;
    vector<pair<int, int>> p(k);
    for (auto& [r, c] : p) cin >> r >> c;
    sort(p.begin(), p.end());
    p.push_back({h, w});
    int N = h + w;
    vector<long long> fact(N + 1), inv(N + 1);
    fact[0] = 1;
    for (int i = 1; i <= N; i++) fact[i] = fact[i - 1] * i % MOD;
    inv[N] = power(fact[N], MOD - 2);
    for (int i = N; i > 0; i--) inv[i - 1] = inv[i] * i % MOD;
    auto paths = [&](int dr, int dc) -> long long {      // monotone paths with dr downs, dc rights
        if (dr < 0 || dc < 0) return 0;
        return fact[dr + dc] * inv[dr] % MOD * inv[dc] % MOD;
    };
    vector<long long> g(k + 1);
    for (int i = 0; i <= k; i++) {
        auto [ri, ci] = p[i];
        g[i] = paths(ri - 1, ci - 1);
        for (int j = 0; j < i; j++) {                    // j sorted before i; paths() is 0 unless j <= i
            auto [rj, cj] = p[j];
            g[i] = (g[i] - g[j] * paths(ri - rj, ci - cj)) % MOD;
        }
        if (g[i] < 0) g[i] += MOD;
    }
    cout << g[k] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    static final long MOD = 1_000_000_007L;
    static long[] fact, inv;

    static long power(long b, long e) {
        long r = 1;
        b %= MOD;
        for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD;
        return r;
    }

    static long paths(int dr, int dc) {
        if (dr < 0 || dc < 0) return 0;
        return fact[dr + dc] * inv[dr] % MOD * inv[dc] % MOD;
    }

    public static void main(String[] args) throws IOException {
        int h = (int) nl(), w = (int) nl(), k = (int) nl();
        long[] key = new long[k];
        for (int i = 0; i < k; i++) key[i] = nl() * 200000L + nl();   // sort by (r, c)
        Arrays.sort(key);                                            // k <= 2000: no anti-sort risk
        int[] R = new int[k + 1], C = new int[k + 1];
        for (int i = 0; i < k; i++) { R[i] = (int) (key[i] / 200000L); C[i] = (int) (key[i] % 200000L); }
        R[k] = h; C[k] = w;
        int N = h + w;
        fact = new long[N + 1];
        inv = new long[N + 1];
        fact[0] = 1;
        for (int i = 1; i <= N; i++) fact[i] = fact[i - 1] * i % MOD;
        inv[N] = power(fact[N], MOD - 2);
        for (int i = N; i > 0; i--) inv[i - 1] = inv[i] * i % MOD;
        long[] g = new long[k + 1];
        for (int i = 0; i <= k; i++) {
            g[i] = paths(R[i] - 1, C[i] - 1);
            for (int j = 0; j < i; j++) g[i] = (g[i] - g[j] * paths(R[i] - R[j], C[i] - C[j])) % MOD;
            if (g[i] < 0) g[i] += MOD;
        }
        System.out.println(g[k]);
    }
}
```

</details>

<!-- test
in:
3 4 2
2 2
2 3
out:
2
-->
<!-- test
in:
2 2 1
1 2
out:
1
-->
<!-- test
in:
100000 100000 0
out:
691090292
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Blocked start or target** ⇒ answer 0 — make sure your base case doesn't set $f(0,0)=1$ on a blocked cell.
2. **Rolling row in place:** `f[j] += f[j-1]` works because `f[j]` still holds the row above and `f[j-1]` already holds the current row. Reset `f[j] = 0` on obstacles — don't skip them.
3. **Negative values and $-\infty$:** with negative cell values (Example 5), an unreachable state must not look like value 0.
4. **Two walkers:** iterate rows in the *valid range* $[\max(0,d-m+1), \min(n-1,d)]$ for each walker; out-of-range rows silently read garbage columns.
5. **Count-once rule** only works in lock-step; with independent step counters, shared cells are invisible.
6. **First-obstacle DP needs sorted obstacles** (by row, then column) so all predecessors are processed first; `paths()` must return 0 for negative displacements.
7. **Factorials up to $h + w$**, not $\max(h,w)$; and $\binom{n}{k}$ with $k>n$ must return 0.
8. **Java memory:** `int[3][1000][1000]` is fine (12 MB); `long[3000][3000]` is 72 MB — use rows of `boolean`/`int` where possible.
9. **Path printing:** reconstruct by re-checking the recurrence ($g(i-1,j) + a_{ij} = g(i,j)$); store the table, not just a rolling row, when the path is required.
10. **Lexicographic paths:** don't compare whole strings per cell; keep the frontier set per anti-diagonal (Example 2).
11. **Zero in a product** (Example 4): the product is 0 regardless of the rest; handle it outside the DP.
12. **Grids with all four directions** are not DAGs: BFS (unit costs), 0-1 BFS, or Dijkstra.

---

## 7. Going further (toward 2400–2600+)

- **Non-intersecting path pairs** (CF 348D Turtles): LGV with two sources/targets shifted by one cell; [LGV](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md).
- **XOR along a path with huge values** (CF 1006F): meet in the middle on the middle anti-diagonal, $O(2^{(n+m)/2})$ with hash maps per cell ([meet in the middle](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md)).
- **Counting paths with $\le k$ turns / direction changes**: add (direction, turns) to the state.
- **Paths below a line with steps of several types** (Motzkin, Schröder): kernel method / generating functions.
- **Grid path counting with obstacles in many queries**: divide and conquer on rows with bitsets (offline reachability), or the "first obstacle" DP per query batch.
- **Sum over all paths of a function of the path** (CF 1467D *Sum of Paths*): count, for each cell, how many times it is visited over all paths (forward count × backward count), then answer updates in $O(1)$ — the contribution technique ([contribution](../05-Combinatorics-and-Probability/07-contribution-technique.md)).

---

## 8. Practice ladder

**≤ 1500**
- [ ] [AtCoder DP H · Grid 1](https://atcoder.jp/contests/dp/tasks/dp_h) — obstacles, row-major
- [ ] [CSES 1638 · Grid Paths I](https://cses.fi/problemset/task/1638)
- [ ] [CF 1937B · Binary Path](https://codeforces.com/problemset/problem/1937/B) — 1300
- [ ] [CF 1948C · Arrow Path](https://codeforces.com/problemset/problem/1948/C) — 1300

**1500–1900**
- [ ] [CF 429B · Working out](https://codeforces.com/problemset/problem/429/B) — 1600
- [ ] [CSES 3359 · Minimal Grid Path](https://cses.fi/problemset/task/3359)
- [ ] [CSES 1744 · Rectangle Cutting](https://cses.fi/problemset/task/1744) — 2-D state, cut lines as transitions
- [ ] [CF 1695C · Zero Path](https://codeforces.com/problemset/problem/1695/C) — 1700
- [ ] [CF 1955G · GCD on a grid](https://codeforces.com/problemset/problem/1955/G) — 1900

**1900–2300**
- [ ] [CF 2B · The least round way](https://codeforces.com/problemset/problem/2/B) — 2000
- [ ] [CF 213C · Relay Race](https://codeforces.com/problemset/problem/213/C) — 2000
- [ ] [CF 1006F · Xor-Paths](https://codeforces.com/problemset/problem/1006/F) — 2100
- [ ] [CF 559C · Gerald and Giant Chess](https://codeforces.com/problemset/problem/559/C) — 2200
- [ ] [CSES 1078 · Grid Paths II](https://cses.fi/problemset/task/1078)
- [ ] [AtCoder DP Y · Grid 2](https://atcoder.jp/contests/dp/tasks/dp_y) — first-obstacle DP
- [ ] [CF 1467D · Sum of Paths](https://codeforces.com/problemset/problem/1467/D) — 2200

**2400+**
- [ ] [CF 1739E · Cleaning Robot](https://codeforces.com/problemset/problem/1739/E) — 2400
- [ ] [CF 348D · Turtles](https://codeforces.com/problemset/problem/348/D) — 2500

---

## 9. LeetCode / FAANG cross-reference

- [LC 62 · Unique Paths](https://leetcode.com/problems/unique-paths/) — Medium — $\binom{m+n-2}{m-1}$ or the table.
- [LC 63 · Unique Paths II](https://leetcode.com/problems/unique-paths-ii/) — Medium — obstacles, rolling row.
- [LC 64 · Minimum Path Sum](https://leetcode.com/problems/minimum-path-sum/) — Medium — min-plus table.
- [LC 120 · Triangle](https://leetcode.com/problems/triangle/) — Medium — bottom-up removes boundary cases.
- [LC 931 · Minimum Falling Path Sum](https://leetcode.com/problems/minimum-falling-path-sum/) — Medium — three predecessors.
- [LC 1289 · Minimum Falling Path Sum II](https://leetcode.com/problems/minimum-falling-path-sum-ii/) — Hard — keep the best and second-best of the previous row.
- [LC 221 · Maximal Square](https://leetcode.com/problems/maximal-square/) — Medium — $f = 1+\min$ of three neighbours.
- [LC 174 · Dungeon Game](https://leetcode.com/problems/dungeon-game/) — Hard — DP from the target backwards (the constraint is on prefixes).
- [LC 741 · Cherry Pickup](https://leetcode.com/problems/cherry-pickup/) — Hard — two walkers in lock-step (Example 5 with obstacles).
- [LC 1463 · Cherry Pickup II](https://leetcode.com/problems/cherry-pickup-ii/) — Hard — two walkers row by row, state $(r, c_1, c_2)$.
- [LC 2435 · Paths in Matrix Whose Sum Is Divisible by K](https://leetcode.com/problems/paths-in-matrix-whose-sum-is-divisible-by-k/) — Hard — residue as a third index.
- [LC 1301 · Number of Paths with Max Score](https://leetcode.com/problems/number-of-paths-with-max-score/) — Hard — optimisation + counting together: carry (best, count).
- [LC 576 · Out of Boundary Paths](https://leetcode.com/problems/out-of-boundary-paths/) — Medium — four directions but bounded steps: layer by step count.
- [LC 329 · Longest Increasing Path in a Matrix](https://leetcode.com/problems/longest-increasing-path-in-a-matrix/) — Hard — four directions, but "strictly increasing" makes it a DAG: memoised DFS.

---

## 10. Self-check

1. Why is row-major order a valid evaluation order for right/down moves?
2. Derive the first-obstacle recurrence and explain why classifying by "any obstacle on the path" would be wrong.
3. Why does lock-step make the "count each cell once" rule local?
4. In Example 4, why can't one DP track $\min(\#2,\#5)$ directly?
5. How many cells are on anti-diagonal $d$ of an $n \times m$ grid? Give the row range.
6. How would you count paths whose sum is divisible by $K$, and what does it cost?
7. When does a four-direction grid still admit a DP?

<details><summary>Answers</summary>

1. Both predecessors $(i-1,j)$ and $(i,j-1)$ come earlier in row-major order, and every move increases $i+j$, so the graph is acyclic.
2. Paths to $o_i$ avoiding everything else = all paths to $o_i$ minus those that hit some other obstacle; each such path has a unique first obstacle $o_j$, after which it is an arbitrary path $o_j \to o_i$. Classifying by "some obstacle" counts a path once per obstacle it visits.
3. Two monotone paths visit cell $(r,c)$ only at step $r+c$; in lock-step both walkers are at step $d$, so they share a cell iff they are in the same cell in the same state ($r_1 = r_2$).
4. The key $\min(\#2,\#5)$ is not monotone under extension: a prefix with a worse min may have a better balance and win later, so keeping only the best key per cell is wrong. Swapping the two minima gives two additive DPs.
5. $r \in [\max(0, d-m+1), \min(n-1, d)]$, i.e. $\min(n-1,d) - \max(0,d-m+1) + 1$ cells.
6. State $(i, j, s)$ with $s$ = sum mod $K$: $O(nmK)$ time, $O(mK)$ memory with a rolling row.
7. When some quantity strictly increases along every allowed move (e.g. moves only to strictly larger values, or a bounded number of steps used as a layer index), making the state graph acyclic.

</details>
