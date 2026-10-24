# Broken Profile DP

> **Band:** 🟠 2000–2400 (plug DP 🔴 2400+) · **Priority:** ⚡ · **FAANG:** low · **Prerequisites:** [bitmask DP](06-bitmask-dp.md), [grid DP](04-grid-and-path-counting-dp.md)
> **You can say you know this when:** you can count domino tilings of an $n \times m$ board ($n \le 10$–$12$) with obstacles in $O(nm2^n)$ by processing one cell at a time; you can explain exactly which cells the $n$ profile bits describe at each moment; and you can adapt the same "frontier window" to adjacency-constrained selections (no two chosen cells adjacent) and to whole-column states.

When a grid has one **short side** ($\le 10$–$12$) and the constraints are **local** (a piece covers adjacent cells, a choice conflicts with its neighbours), the only part of the past that matters for the future is the **frontier**: the boundary between processed and unprocessed cells. Encoding the frontier as a bitmask gives a DP with $2^{\text{short side}}$ states per position. Processing **one cell at a time** keeps each transition trivial; that "broken" line between processed and unprocessed cells is the *broken profile*.

---

## 1. First principles — why this works

### 1.1 What does the future need? The frontier

Count tilings of an $n\times m$ board by $1\times2$ dominoes. Fill the board column by column ($n$ = number of rows, the short side). Suppose columns $0..j-1$ are completely decided. The only way the past affects column $j$ is through **horizontal dominoes sticking out of column $j-1$ into column $j$**. So the state between columns is a mask of $n$ bits: which cells of column $j$ are already covered. Two partial tilings with the same mask have identical sets of completions — that is the equivalence-class argument of [first principles](01-dp-first-principles-and-state-design.md) §1.2.

**Column-at-a-time:** for each mask, enumerate all ways to fill column $j$ (vertical dominoes inside the column, horizontal ones sticking into column $j+1$), producing the next mask. Correct, but each mask can have many successors; precomputing all transitions costs up to $O(4^n)$ pairs per column, and enumerating them is fiddly.

### 1.2 Cell-at-a-time — the broken profile

Process cells in column-major order: $(0,0), (1,0), \dots, (n-1,0), (0,1), \dots$ When we are about to process cell $(i, j)$, keep $n$ bits with a **moving meaning**:

- bits $r < i$ describe cells $(r, j+1)$ of the **next** column (already decided whether a horizontal domino from $(r, j)$ covers them);
- bits $r \ge i$ describe cells $(r, j)$ of the **current** column (covered already by a horizontal domino from $(r, j-1)$, or by a vertical domino from $(r-1, j)$).

The boundary between the two groups sits between rows $i-1$ and $i$ — the profile is "broken" there. These $n$ cells are exactly the frontier: every cell before $(i,j)$ in processing order is decided, and every undecided cell that could already be covered is one of these $n$.

**Transition at cell $(i,j)$ with profile mask $s$** (bit $i$ currently describes $(i,j)$):

1. If bit $i$ is set, $(i,j)$ is already covered: nothing to place. Bit $i$ now describes $(i, j+1)$, which nothing covers yet → clear it.
2. Otherwise we must cover $(i,j)$ now (nothing later can reach it):
   - **horizontal** domino $(i,j)$–$(i,j+1)$ (needs $j+1 < m$): bit $i$ now describes $(i,j+1)$, which is covered → set it;
   - **vertical** domino $(i,j)$–$(i+1,j)$ (needs $i+1 < n$ and bit $i+1$ clear): bit $i+1$ (still describing $(i+1,j)$) becomes set; bit $i$ describes $(i,j+1)$, uncovered → stays clear.

After the last cell, the answer is the count for mask $0$ (nothing sticks out of the board). Each step has at most 2 transitions per mask: $O(nm\,2^n)$ time, $O(2^n)$ memory with two rolling arrays. For $n = 10$, $m = 1000$: $10^7$ updates.

**Obstacles** are just cells that must not be covered: if bit $i$ is set at a blocked cell, the configuration is invalid (drop it); otherwise skip the cell (bit $i$ stays clear for the next column). Equivalently, never place a domino onto a blocked cell.

### 1.3 Why "one cell at a time" is the right granularity

Column-at-a-time needs to enumerate all fillings of a column for each mask — the transition is itself a small search. Cell-at-a-time makes every decision **local and constant-size** (two choices), at the price of $n$ times more "layers". This is the same trade as Example 5 in [first principles](01-dp-first-principles-and-state-design.md): make the decision sequence finer until each step's choices are trivial, and let the state carry the bookkeeping.

### 1.4 The same window for adjacency constraints

"Choose cells, no two 4-adjacent, maximise total weight" on an $n\times m$ grid with $m \le 10$ columns: process cells in **row-major** order and keep the last $m$ decisions. At cell $(i,j)$, bits $c<j$ hold row $i$'s decisions (columns $< j$) and bits $c \ge j$ hold row $i-1$'s. The up-neighbour is bit $j$, the left-neighbour is bit $j-1$ — both in the window, so the constraint is checkable locally, and after deciding we overwrite bit $j$ with the new choice. $O(nm2^m)$. Variants: counting independent sets, at most $k$ chosen (add a counter), seats with broken chairs ([LC 1349](https://leetcode.com/problems/maximum-students-taking-exam/)), or a ternary window when cells have three types ([LC 1659](https://leetcode.com/problems/maximize-grid-happiness/)).

### 1.5 Whole-column states with extra counters

When the grid height is tiny (2 or 3 rows), keep the *entire* column as the state and add whatever the objective needs. CF 1051D *Bicolorings* counts colourings of a $2\times n$ grid with exactly $k$ connected components: state = (column colouring $\in \{0,1\}^2$, components so far); appending a column changes the count by an amount that depends only on the two adjacent columns (Example 1).

### 1.6 Beyond dominoes

- Pieces that reach **two rows/columns ahead** (L-trominoes, $1\times3$ bars) need a wider frontier: more than one bit per row, or a profile of $n+1$ cells. Design the profile as "every undecided cell that some already-placed piece may cover".
- **Plug DP** (🔴): counting Hamiltonian cycles or paths on grids, or polyomino-like connectivity constraints. The frontier must also record **which frontier cells are connected to each other** by already-placed path segments — encoded as a bracket sequence or a minimal labelling of components, stored in a hash map because only a tiny fraction of encodings is reachable. Same cell-at-a-time scan, much richer state.

---

## 2. Formulas, definitions and identities

| Method | States per step | Transitions | Total |
|---|---|---|---|
| column-at-a-time | $2^n$ | up to $2^n$ (precomputed lists) | $O(m\cdot T)$, $T \le 4^n$ (tilings: $T \approx 2^n \cdot 1.6^n$) |
| cell-at-a-time (broken profile) | $2^n$ | $\le 2$ | $O(nm2^n)$ |
| window for adjacency | $2^w$ ($w$ = width) | $\le 2$ | $O(nm2^w)$ |
| ternary window | $3^w$ | $\le 3$ | $O(nm3^w)$ |

**Domino tilings, closed forms:**
- $2\times n$: Fibonacci, $T_n = T_{n-1} + T_{n-2}$, $T_0 = T_1 = 1$.
- $3\times n$ ($n$ even): $T_n = 4T_{n-2} - T_{n-4}$, $T_0 = 1$, $T_2 = 3$.
- Any $n\times m$ with $nm$ odd: 0 (each domino covers 2 cells).
- Kasteleyn's formula: $T(n,m) = \prod_{j=1}^{\lceil n/2\rceil}\prod_{k=1}^{\lceil m/2\rceil}\left(4\cos^2\frac{\pi j}{n+1} + 4\cos^2\frac{\pi k}{m+1}\right)$ — exact over the reals, useless mod $p$, but a good sanity check.

**Bit meaning at cell $(i,j)$ (column-major scan):** bit $r$ describes $(r, j+1)$ if $r < i$, $(r, j)$ if $r \ge i$.

**Coloured-cell constraint by colouring argument:** a board with a different number of black and white squares (chessboard colouring) has no domino tiling — a quick pre-check with obstacles.

---

## 3. Implementation (C++ and Java)

The broken-profile kernel: count domino tilings of an $n\times m$ grid (`'.'` free, `'#'` blocked), $n$ = number of rows (the profile side), mod $10^9+7$.

```cpp
long long countDominoTilings(const vector<string>& g) {
    const long long MOD = 1'000'000'007;
    int n = g.size(), m = g[0].size();
    vector<long long> f(1 << n, 0), h(1 << n);
    f[0] = 1;
    for (int j = 0; j < m; j++)
        for (int i = 0; i < n; i++) {                 // process cell (i, j)
            fill(h.begin(), h.end(), 0);
            for (int s = 0; s < (1 << n); s++) {
                if (!f[s]) continue;
                long long v = f[s];
                bool covered = s >> i & 1;
                if (g[i][j] == '#') {                  // blocked: must not be covered
                    if (!covered) h[s] = (h[s] + v) % MOD;
                    continue;
                }
                if (covered) { h[s ^ (1 << i)] = (h[s ^ (1 << i)] + v) % MOD; continue; }
                if (j + 1 < m && g[i][j + 1] == '.')   // horizontal: covers (i, j+1)
                    h[s | 1 << i] = (h[s | 1 << i] + v) % MOD;
                if (i + 1 < n && !(s >> (i + 1) & 1) && g[i + 1][j] == '.')   // vertical: covers (i+1, j)
                    h[s | 1 << (i + 1)] = (h[s | 1 << (i + 1)] + v) % MOD;
            }
            swap(f, h);
        }
    return f[0];
}
```

```java
static long countDominoTilings(char[][] g) {
    final long MOD = 1_000_000_007L;
    int n = g.length, m = g[0].length;
    long[] f = new long[1 << n], h = new long[1 << n];
    f[0] = 1;
    for (int j = 0; j < m; j++)
        for (int i = 0; i < n; i++) {
            Arrays.fill(h, 0);
            for (int s = 0; s < (1 << n); s++) {
                if (f[s] == 0) continue;
                long v = f[s];
                boolean covered = (s >> i & 1) != 0;
                if (g[i][j] == '#') {
                    if (!covered) h[s] = (h[s] + v) % MOD;
                    continue;
                }
                if (covered) { h[s ^ (1 << i)] = (h[s ^ (1 << i)] + v) % MOD; continue; }
                if (j + 1 < m && g[i][j + 1] == '.') h[s | 1 << i] = (h[s | 1 << i] + v) % MOD;
                if (i + 1 < n && (s >> (i + 1) & 1) == 0 && g[i + 1][j] == '.')
                    h[s | 1 << (i + 1)] = (h[s | 1 << (i + 1)] + v) % MOD;
            }
            long[] t = f; f = h; h = t;
        }
    return f[0];
}
```

If the input's short side is the number of columns, transpose the grid first so that the profile runs over the short side.

---

## 4. Recognising the pattern

| Signal | Technique |
|---|---|
| grid with one side $\le 10$–$12$, the other up to $10^3$ (or more) | profile over the short side |
| "number of ways to tile / cover with dominoes (and obstacles)" | broken profile, cell at a time |
| "choose cells with no two adjacent", "seat students", "place non-attacking kings" | window of the last $w$ decisions |
| grid of height 2–3 with a global counter (components, number of chosen) | whole-column state + counter |
| the long side is $10^{18}$ | column transfer matrix + [matrix power](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md) |
| Hamiltonian cycles / connectivity of chosen cells on a small-width grid | plug DP (🔴) |
| both sides large, bipartite structure | not DP — matching or a closed form ([flows and matching](../12-Flows-and-Matching/03-bipartite-matching-kuhn-hopcroft-karp.md)) |

---

## 5. Worked examples (graded)

### Example 1 — Bicolorings (whole-column states)  ·  ★ 1700

- **Source:** [CF 1051D · Bicolorings](https://codeforces.com/problemset/problem/1051/D) — 1700
- **Difficulty:** 1700
- **Problem:** Colour each cell of a $2\times n$ grid ($n \le 1000$) black or white. Components are maximal 4-connected monochromatic regions. Count colourings with exactly $k$ components ($k \le 2n$), mod $998244353$.
- **Thinking from first principles:** Scanning columns left to right, a new column interacts only with the previous column. The four possible columns (both white, both black, top white/bottom black, the reverse) are the profile; the component count is a counter dimension. The change in components when column $t$ follows column $s$ depends only on $(s,t)$: e.g. after a uniform column, an equal uniform column adds 0, the opposite uniform column adds 1, a split column adds 1; after a split column, the mirrored split adds 2, everything else 0.

<details><summary>Solution</summary>

$f(\text{col}, s, c)$ with $s\in\{0..3\}$ (bit 0 = top colour, bit 1 = bottom colour); precompute $\Delta(s,t)$. $O(16\,n\,k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    const long long MOD = 998244353;
    int n, k;
    cin >> n >> k;
    auto delta = [](int s, int t) {                   // new components created by column t after column s
        bool sUni = (s == 0 || s == 3), tUni = (t == 0 || t == 3);
        if (sUni && tUni) return s == t ? 0 : 1;
        if (sUni) return 1;                           // split after uniform: one cell matches, one is new
        if (tUni) return 0;                           // uniform after split: joins one side (and merges)
        return s == t ? 0 : 2;                        // split after split
    };
    vector<vector<long long>> f(4, vector<long long>(k + 3, 0)), g = f;
    f[0][1] = f[3][1] = 1;
    f[1][2] = f[2][2] = 1;
    for (int col = 1; col < n; col++) {
        for (auto& row : g) fill(row.begin(), row.end(), 0);
        for (int s = 0; s < 4; s++)
            for (int c = 1; c <= k; c++) {
                if (!f[s][c]) continue;
                for (int t = 0; t < 4; t++) {
                    int nc = c + delta(s, t);
                    if (nc <= k) g[t][nc] = (g[t][nc] + f[s][c]) % MOD;
                }
            }
        swap(f, g);
    }
    long long ans = 0;
    for (int s = 0; s < 4; s++) ans += f[s][k];
    cout << ans % MOD << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int delta(int s, int t) {
        boolean sUni = s == 0 || s == 3, tUni = t == 0 || t == 3;
        if (sUni && tUni) return s == t ? 0 : 1;
        if (sUni) return 1;
        if (tUni) return 0;
        return s == t ? 0 : 2;
    }

    public static void main(String[] args) throws IOException {
        final long MOD = 998244353L;
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        int n = Integer.parseInt(st.nextToken()), k = Integer.parseInt(st.nextToken());
        long[][] f = new long[4][k + 3], g = new long[4][k + 3];
        f[0][1] = f[3][1] = 1;
        f[1][2] = f[2][2] = 1;
        for (int col = 1; col < n; col++) {
            for (long[] row : g) Arrays.fill(row, 0);
            for (int s = 0; s < 4; s++)
                for (int c = 1; c <= k; c++) {
                    if (f[s][c] == 0) continue;
                    for (int t = 0; t < 4; t++) {
                        int nc = c + delta(s, t);
                        if (nc <= k) g[t][nc] = (g[t][nc] + f[s][c]) % MOD;
                    }
                }
            long[][] tmp = f; f = g; g = tmp;
        }
        long ans = 0;
        for (int s = 0; s < 4; s++) ans += f[s][k];
        System.out.println(ans % MOD);
    }
}
```

</details>

<!-- test
in:
2 2
out:
12
-->
<!-- test
in:
5 5
out:
194
-->
<!-- test
in:
6 1
out:
2
-->
<!-- test
in:
1000 2000
out:
2
-->

### Example 2 — Counting Tilings  ·  ★ ≈2000 (est.)

- **Source:** [CSES 2181 · Counting Tilings](https://cses.fi/problemset/task/2181)
- **Difficulty:** ≈2000 (est.)
- **Problem:** Count tilings of an $n\times m$ grid by $1\times2$ and $2\times1$ dominoes, $n \le 10$, $m \le 1000$, mod $10^9+7$.
- **Thinking from first principles:** The short side is $n$, so the frontier has $n$ cells. Cell-at-a-time keeps two transitions per state (§1.2): $10\cdot1000\cdot1024\cdot 2 = 2\cdot10^7$ updates. Odd $nm$ gives 0 automatically (no path ends at mask 0) — no special case needed.

<details><summary>Solution</summary>

The kernel of §3 without obstacles. $O(nm2^n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    const int MOD = 1'000'000'007;
    int n, m;
    cin >> n >> m;
    vector<int> f(1 << n, 0), h(1 << n);
    f[0] = 1;
    for (int j = 0; j < m; j++)
        for (int i = 0; i < n; i++) {
            fill(h.begin(), h.end(), 0);
            for (int s = 0; s < (1 << n); s++) {
                int v = f[s];
                if (!v) continue;
                auto add = [&](int t) { h[t] += v; if (h[t] >= MOD) h[t] -= MOD; };
                if (s >> i & 1) { add(s ^ (1 << i)); continue; }           // already covered
                if (j + 1 < m) add(s | 1 << i);                            // horizontal
                if (i + 1 < n && !(s >> (i + 1) & 1)) add(s | 1 << (i + 1)); // vertical
            }
            swap(f, h);
        }
    cout << f[0] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final int MOD = 1_000_000_007;
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
        int[] f = new int[1 << n], h = new int[1 << n];
        f[0] = 1;
        for (int j = 0; j < m; j++)
            for (int i = 0; i < n; i++) {
                Arrays.fill(h, 0);
                for (int s = 0; s < (1 << n); s++) {
                    int v = f[s];
                    if (v == 0) continue;
                    if ((s >> i & 1) != 0) { int t = s ^ (1 << i); h[t] = (h[t] + v) % MOD; continue; }
                    if (j + 1 < m) { int t = s | 1 << i; h[t] = (h[t] + v) % MOD; }
                    if (i + 1 < n && (s >> (i + 1) & 1) == 0) { int t = s | 1 << (i + 1); h[t] = (h[t] + v) % MOD; }
                }
                int[] tmp = f; f = h; h = tmp;
            }
        System.out.println(f[0]);
    }
}
```

</details>

<!-- test
in:
2 3
out:
3
-->
<!-- test
in:
3 4
out:
11
-->
<!-- test
in:
1 1
out:
0
-->
<!-- test
in:
6 100
out:
907768777
-->
<!-- test
in:
10 20
out:
505817930
-->

### Example 3 — Maximum-weight independent set on a narrow grid  ·  ★ ≈2000 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈2000 (est.)
- **Problem:** An $n\times m$ grid ($n \le 1000$, $m \le 10$) of non-negative weights $\le 10^9$. Choose cells, no two sharing a side, to maximise the total weight.
- **Thinking from first principles:** A choice conflicts only with its up and left neighbours (in row-major order, right and down neighbours are decided later and will check against this cell). In row-major order, the last $m$ decisions are exactly "row $i$ to the left of $j$" and "row $i-1$ from $j$ onward" — the window of §1.4. So the state is the $m$-bit window, the up neighbour is bit $j$, the left neighbour is bit $j-1$. $O(nm2^m) = 10^7$. Row-by-row DP with "compatible row masks" also works, but its transition is over pairs of masks: $O(n\cdot 4^m)$ in the worst case.

<details><summary>Solution</summary>

$f(s)$ = best total so far for window $s$; at cell $(i,j)$: "skip" sets bit $j$ to 0; "take" (allowed if bits $j$ and $j-1$ are 0, the latter only for $j>0$) sets bit $j$ to 1 and adds $w_{ij}$. Unreachable states are $-1$. $O(nm2^m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<long long> f(1 << m, -1), h(1 << m);
    f[0] = 0;
    for (int i = 0; i < n; i++)
        for (int j = 0; j < m; j++) {
            long long w;
            cin >> w;
            fill(h.begin(), h.end(), -1);
            for (int s = 0; s < (1 << m); s++) {
                if (f[s] < 0) continue;
                int skip = s & ~(1 << j);                          // bit j now describes (i, j): not chosen
                h[skip] = max(h[skip], f[s]);
                bool up = s >> j & 1, left = j > 0 && (s >> (j - 1) & 1);
                if (!up && !left) h[s | 1 << j] = max(h[s | 1 << j], f[s] + w);
            }
            swap(f, h);
        }
    cout << *max_element(f.begin(), f.end()) << "\n";
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
        int n = (int) nl(), m = (int) nl();
        long[] f = new long[1 << m], h = new long[1 << m];
        Arrays.fill(f, -1);
        f[0] = 0;
        for (int i = 0; i < n; i++)
            for (int j = 0; j < m; j++) {
                long w = nl();
                Arrays.fill(h, -1);
                for (int s = 0; s < (1 << m); s++) {
                    if (f[s] < 0) continue;
                    int skip = s & ~(1 << j);
                    if (f[s] > h[skip]) h[skip] = f[s];
                    boolean up = (s >> j & 1) != 0, left = j > 0 && (s >> (j - 1) & 1) != 0;
                    if (!up && !left) {
                        int t = s | 1 << j;
                        if (f[s] + w > h[t]) h[t] = f[s] + w;
                    }
                }
                long[] tmp = f; f = h; h = tmp;
            }
        long best = 0;
        for (long v : f) best = Math.max(best, v);
        System.out.println(best);
    }
}
```

</details>

<!-- test
in:
2 3
1 9 1
9 1 9
out:
27
-->
<!-- test
in:
1 1
5
out:
5
-->
<!-- test
in:
3 3
5 1 5
1 5 1
5 1 5
out:
25
-->

### Example 4 — Domino tilings with obstacles  ·  ★ ≈2100 (est.)

- **Source:** Original problem (the obstacle version of Example 2).
- **Difficulty:** ≈2100 (est.)
- **Problem:** An $n\times m$ grid ($n \le 10$ rows, $m \le 1000$ columns) of `.` (free) and `#` (blocked). Count tilings of the free cells by dominoes, mod $10^9+7$.
- **Thinking from first principles:** Obstacles change nothing in the state: the frontier still has $n$ cells. A blocked cell must never be covered — never place a domino onto it, and if the profile says it is covered, that configuration is impossible (it cannot even arise if placements check the target). At a blocked cell we simply move on with bit $i$ clear. The chessboard argument gives a quick sanity check: unequal numbers of free black and white cells ⇒ 0.

<details><summary>Solution</summary>

The §3 kernel verbatim, reading the grid first. $O(nm2^n)$.

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
    vector<long long> f(1 << n, 0), h(1 << n);
    f[0] = 1;
    for (int j = 0; j < m; j++)
        for (int i = 0; i < n; i++) {
            fill(h.begin(), h.end(), 0);
            for (int s = 0; s < (1 << n); s++) {
                if (!f[s]) continue;
                long long v = f[s];
                bool covered = s >> i & 1;
                if (g[i][j] == '#') {                  // blocked cells are never covered
                    if (!covered) h[s] = (h[s] + v) % MOD;
                    continue;
                }
                if (covered) { h[s ^ (1 << i)] = (h[s ^ (1 << i)] + v) % MOD; continue; }
                if (j + 1 < m && g[i][j + 1] == '.') h[s | 1 << i] = (h[s | 1 << i] + v) % MOD;
                if (i + 1 < n && !(s >> (i + 1) & 1) && g[i + 1][j] == '.')
                    h[s | 1 << (i + 1)] = (h[s | 1 << (i + 1)] + v) % MOD;
            }
            swap(f, h);
        }
    cout << f[0] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
        char[][] g = new char[n][];
        for (int i = 0; i < n; i++) g[i] = br.readLine().trim().toCharArray();
        long[] f = new long[1 << n], h = new long[1 << n];
        f[0] = 1;
        for (int j = 0; j < m; j++)
            for (int i = 0; i < n; i++) {
                Arrays.fill(h, 0);
                for (int s = 0; s < (1 << n); s++) {
                    if (f[s] == 0) continue;
                    long v = f[s];
                    boolean covered = (s >> i & 1) != 0;
                    if (g[i][j] == '#') {
                        if (!covered) h[s] = (h[s] + v) % MOD;
                        continue;
                    }
                    if (covered) { h[s ^ (1 << i)] = (h[s ^ (1 << i)] + v) % MOD; continue; }
                    if (j + 1 < m && g[i][j + 1] == '.') h[s | 1 << i] = (h[s | 1 << i] + v) % MOD;
                    if (i + 1 < n && (s >> (i + 1) & 1) == 0 && g[i + 1][j] == '.')
                        h[s | 1 << (i + 1)] = (h[s | 1 << (i + 1)] + v) % MOD;
                }
                long[] t = f; f = h; h = t;
            }
        System.out.println(f[0]);
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
2
-->
<!-- test
in:
2 4
#..#
....
out:
1
-->
<!-- test
in:
2 2
##
##
out:
1
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Profile over the short side.** Transpose the grid if needed; $2^{12}$ is fine, $2^{20}$ per cell is not.
2. **Know what each bit means *now*.** At cell $(i,j)$ in column-major order, bits $<i$ describe column $j+1$, bits $\ge i$ describe column $j$. Write it as a comment above the loop.
3. **Clear the target array** before each cell (or the counts leak between layers).
4. **The answer is mask 0** after the last cell: nothing may stick out of the board.
5. **Horizontal at the last column** is invalid ($j+1 < m$), **vertical at the last row** is invalid ($i+1<n$), and the vertical target bit must be clear.
6. **Obstacles:** check the *target* cell of every domino; an obstacle reached with its bit set means an earlier bug — the invariant is that blocked cells are never marked.
7. **Modular addition:** use `if (x >= MOD) x -= MOD` with `int` arrays (Example 2) — twice as fast as `%` on `long long`.
8. **Skip zero states:** most masks are unreachable for long stretches; `if (!f[s]) continue;` is a large constant-factor win.
9. **Window DPs for adjacency** (Example 3) use row-major order and the window of the last $w$ cells; don't mix it up with the column-major tiling profile.
10. **Large long side:** if $m$ is huge, build the $2^n \times 2^n$ column transfer matrix and exponentiate it ($O(8^n\log m)$ — only for $n \le 6$ or so).
11. **Java speed:** the inner loop over $2^n$ masks is hot; avoid lambdas and boxing, use `int[]` counts with conditional subtraction.

---

## 7. Going further (toward 2400–2600+)

- **Plug DP** (🔴) for Hamiltonian cycles on grids with obstacles ("Formula 1"-style problems), connectivity constraints (polyominoes, "all chosen cells connected"): the profile carries a connectivity encoding (bracket sequence for non-crossing paths), stored in a hash map; cell-at-a-time transitions handle each combination of left/up plugs.
- **Profile DP with counters**: "exactly $k$ chosen cells", "at most $k$ horizontal dominoes" — add a dimension and keep the same scan.
- **Ternary profiles** for three-state cells (LC 1659) or for "covered by a vertical piece started above" vs "covered by a horizontal piece" distinctions in larger polyominoes.
- **Transfer-matrix method + Berlekamp–Massey**: the number of tilings of $n\times m$ for fixed $n$ satisfies a linear recurrence in $m$; compute the first terms with the profile DP and recover the recurrence ([Berlekamp–Massey](../15-Advanced-Math/05-lagrange-interpolation-and-berlekamp-massey.md)).
- **Kasteleyn / Pfaffian method** (🧊): planar perfect matchings counted by a determinant — tilings of large boards in polynomial time, exactly (over the integers or mod $p$ with care).

---

## 8. Practice ladder

- [ ] [CF 1051D · Bicolorings](https://codeforces.com/problemset/problem/1051/D) — 1700
- [ ] [CSES 2413 · Counting Towers](https://cses.fi/problemset/task/2413) — a 2-wide "profile" of whether the top row is split
- [ ] [CSES 2181 · Counting Tilings](https://cses.fi/problemset/task/2181)
- [ ] [CF 1990D · Grid Puzzle](https://codeforces.com/problemset/problem/1990/D) — 1800 — small row states with greedy transitions
- [ ] [CF 1739E · Cleaning Robot](https://codeforces.com/problemset/problem/1739/E) — 2400 — 2-row column states
- [ ] [AtCoder TDPC S · マス目](https://atcoder.jp/contests/tdpc/tasks/tdpc_grid) — connectivity profile on a narrow grid (plug-DP flavour)

---

## 9. LeetCode / FAANG cross-reference

- [LC 790 · Domino and Tromino Tiling](https://leetcode.com/problems/domino-and-tromino-tiling/) — Medium — $2\times n$ with L-trominoes: a 1-D profile (is the top or bottom cell of the next column filled).
- [LC 1411 · Number of Ways to Paint N × 3 Grid](https://leetcode.com/problems/number-of-ways-to-paint-n-3-grid/) — Hard — whole-row states (12 valid rows), transitions between compatible rows.
- [LC 1931 · Painting a Grid With Three Different Colors](https://leetcode.com/problems/painting-a-grid-with-three-different-colors/) — Hard — ternary column states, $m \le 5$.
- [LC 1349 · Maximum Students Taking Exam](https://leetcode.com/problems/maximum-students-taking-exam/) — Hard — row masks with diagonal conflicts (or the cell window of Example 3).
- [LC 1659 · Maximize Grid Happiness](https://leetcode.com/problems/maximize-grid-happiness/) — Hard — ternary window of the last $n$ cells plus two counters.
- [LC 1240 · Tiling a Rectangle with the Fewest Squares](https://leetcode.com/problems/tiling-a-rectangle-with-the-fewest-squares/) — Hard — skyline-profile search (backtracking over the profile, not a DP table).

Rare in interviews; LC 790 and LC 1411 are the realistic ones.

---

## 10. Self-check

1. In the column-major broken profile at cell $(i,j)$, which cells do the $n$ bits describe?
2. Why is it enough to remember only frontier cells?
3. Write the two placements at an uncovered cell and the resulting masks.
4. Why must the final answer be read at mask 0?
5. How do obstacles change the transitions?
6. For "no two chosen cells adjacent", which bits are the up and left neighbours at cell $(i,j)$ in row-major order?
7. When would you switch from the cell-at-a-time DP to matrix exponentiation?

<details><summary>Answers</summary>

1. Bits $r<i$: cells $(r, j+1)$; bits $r\ge i$: cells $(r, j)$.
2. Every processed cell is decided, and the only undecided cells that a placed domino can already cover are the next cells in each row — exactly the frontier; the rest of the past cannot influence the future.
3. Horizontal: $s \mid (1\ll i)$ (needs $j+1<m$); vertical: $s \mid (1 \ll (i+1))$ with bit $i$ left clear (needs $i+1<n$ and bit $i+1$ clear).
4. After the last cell, a set bit would mean a domino sticks out beyond the last column.
5. Never place a domino whose cells include an obstacle; at an obstacle cell, the bit must be clear and simply stays clear for the next column.
6. Up: bit $j$ (it still holds row $i-1$, column $j$); left: bit $j-1$ (already overwritten with row $i$, column $j-1$), only when $j>0$.
7. When the long side is huge (e.g. $10^{18}$) and the short side is tiny ($n \le 6$), so the $2^n\times2^n$ column transfer matrix can be raised to the $m$-th power.

</details>
