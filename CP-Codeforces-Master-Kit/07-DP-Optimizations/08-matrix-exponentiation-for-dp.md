# Matrix Exponentiation for DP

> **Band:** 🔵 1700–2100 (semiring powers, segment trees of matrices 🟠) · **Priority:** 🔥 · **FAANG:** low (the $O(\log n)$ Fibonacci follow-up is the interview face) · **Prerequisites:** [modular arithmetic and fast power](../04-Number-Theory/02-modular-arithmetic-and-inverses.md), [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md), [matrices and linear recurrences](../15-Advanced-Math/01-matrices-and-linear-recurrences.md), [shortest paths](../09-Graphs/02-shortest-paths.md) (for the $(\min,+)$ view)
> **You can say you know this when:** you can take a DP with a small state and $n$ up to $10^{18}$, write its transition as an $m\times m$ matrix (adding constants, the step index or a running sum to the state when needed), raise it in $O(m^3 \log n)$, and switch the semiring to $(\min,+)$ for "cheapest walk with exactly $k$ edges".

## 1. First principles — why this works

### 1.1 When a DP is a matrix product

Suppose a DP advances in steps $t = 0, 1, 2, \dots$, the state at step $t$ is a vector $v_t$ of **constant size $m$**, and the transition is **linear and the same at every step**:

$$v_{t+1}[j] = \sum_{i} v_t[i] \cdot T[i][j] \quad\Longleftrightarrow\quad v_{t+1} = v_t\,T.$$

Then $v_n = v_0\,T^n$. Iterating costs $O(n m^2)$ — hopeless for $n = 10^{18}$. But matrix multiplication is **associative**, so $T^n$ can be built by repeated squaring: $T^{2k} = (T^k)^2$, $T^{2k+1} = T^{2k}T$. Reading $n$ in binary, $\lfloor \log_2 n \rfloor$ squarings and at most as many extra products give $T^n$ in $O(m^3 \log n)$.

So the method is three questions:

1. **What is the state?** Everything the next step needs, and nothing that grows with $t$.
2. **Is the step linear in the state, and the same for every $t$?** (Or piecewise constant: then multiply the powers of the pieces.)
3. **Is $m^3 \log n$ affordable?** $m \le 100$ is comfortable, $m \approx 200$ is tight, beyond that use the tricks of §7.

### 1.2 Walks in a graph — the canonical example

Let $A[u][v]$ be the number of edges $u \to v$. Then $(A^k)[u][v]$ is the number of walks of length exactly $k$ from $u$ to $v$. *Proof by induction:* a walk of length $k+1$ from $u$ to $v$ is a walk of length $k$ from $u$ to some $w$ followed by an edge $w \to v$, so $(A^{k+1})[u][v] = \sum_w (A^k)[u][w]\,A[w][v]$ — the definition of the product. Every "count sequences of length $n$ where consecutive elements must be compatible" problem is this with letters as vertices.

### 1.3 Semirings: the same algebra for min-cost and reachability

The proof of associativity of matrix products only uses that "$+$" is associative and commutative, "$\times$" is associative, and "$\times$" distributes over "$+$". Replace them by $(\min, +)$:

$$(A \otimes B)[i][j] = \min_k \big(A[i][k] + B[k][j]\big).$$

$\min$ is associative and commutative, $+$ is associative, and $a + \min(b, c) = \min(a + b, a + c)$. So $A^{\otimes k}$ is well defined, repeated squaring works, and by the same induction as §1.2, $A^{\otimes k}[u][v]$ is the **cheapest walk with exactly $k$ edges**. The neutral elements change: "zero" is $+\infty$ (no walk), "one" is $0$, so the identity matrix has $0$ on the diagonal and $+\infty$ elsewhere.

| Semiring $(\oplus, \otimes)$ | $A^k[u][v]$ means | identity diagonal / off-diagonal |
|---|---|---|
| $(+, \times)$ | number of walks of length $k$ | 1 / 0 |
| $(\min, +)$ | cheapest walk with exactly $k$ edges | 0 / $+\infty$ |
| $(\max, +)$ | most valuable walk with exactly $k$ edges | 0 / $-\infty$ |
| $(\lor, \land)$ | is there a walk of length $k$ (bitsets: $m^3/64$) | true / false |
| $(\max, \min)$ | best bottleneck over walks of length $k$ | $+\infty$ / $-\infty$ |

"At most $k$ edges" in $(\min,+)$: add a zero-cost self-loop at every vertex (staying put is free).

### 1.4 Making a non-linear-looking step linear: augment the state

Linear means "each new coordinate is a fixed combination of old coordinates". Things that look non-linear often become linear after adding coordinates:

- **Constant term** $a_{t+1} = c\,a_t + d$: append the constant $1$ to the state; $d$ becomes the coefficient of that coordinate.
- **Polynomial in $t$** ($+\,r\,t$, $+\,t^2$): append $t$ (and $t^2$, …). $t+1 = t + 1$ and $(t+1)^2 = t^2 + 2t + 1$ are linear in $(t^2, t, 1)$.
- **Running sum** $S_t = \sum_{i \le t} a_i$: append $S$; $S_{t+1} = S_t + a_{t+1}$, and $a_{t+1}$ is already a combination of the state.
- **Sum of matrix powers** $I + A + \dots + A^{k-1}$: the block matrix $\begin{pmatrix} A & I \\ 0 & I\end{pmatrix}^k = \begin{pmatrix} A^k & I + A + \dots + A^{k-1} \\ 0 & I \end{pmatrix}$.
- **Products** $f_n = f_{n-1} f_{n-2}$: take logarithms in the exponent — the exponents follow a linear recurrence, computed modulo $p - 1$ by Fermat ([CF 1182E · Product Oriented Recurrence](https://codeforces.com/problemset/problem/1182/E) — 2300).

### 1.5 Many queries with different $n$

Precompute $T^{2^j}$ for $j < 60$ once ($O(m^3 \cdot 60)$). A query "$v\,T^k$" multiplies a **vector** by the powers selected by the bits of $k$: $O(m^2 \log k)$ per query instead of $O(m^3 \log k)$. Since the powers of one matrix commute, the order of the factors does not matter.

### 1.6 Complexity and limits

| $m$ | one product | $T^n$, $n \le 10^{18}$ ($\approx 120$ products) |
|---|---|---|
| 2–6 | negligible | negligible |
| 52 | $1.4\cdot10^5$ | $1.7\cdot10^7$ |
| 100 | $10^6$ | $1.2\cdot10^8$ — fine with the accumulation trick of §3 |
| 200 | $8\cdot10^6$ | $10^9$ — too slow; use §7 |

## 2. Formulas, definitions and identities

| Formula | Meaning / proof |
|---|---|
| $v_n = v_0\,T^n$ | linear time-invariant DP; associativity |
| $\begin{pmatrix}1&1\\1&0\end{pmatrix}^n = \begin{pmatrix}F_{n+1}&F_n\\F_n&F_{n-1}\end{pmatrix}$ | induction: multiply by the base matrix once more |
| $F_{2k} = F_k(2F_{k+1} - F_k)$, $F_{2k+1} = F_k^2 + F_{k+1}^2$ | **fast doubling**: compare entries of $Q^{2k} = (Q^k)^2$; $O(\log n)$ with tiny constant |
| $F_{n+1}F_{n-1} - F_n^2 = (-1)^n$ | Cassini: determinant of $Q^n$ is $(\det Q)^n$ |
| $\sum_{i=0}^{n} F_i = F_{n+2} - 1$ | telescoping $F_i = F_{i+2} - F_{i+1}$ |
| $a_n = \sum_{j=1}^{d} c_j a_{n-j}$ ⇒ companion matrix: first row $(c_1, \dots, c_d)$, sub-diagonal of ones | state $(a_n, \dots, a_{n-d+1})$ |
| $(A^k)[u][v]$ = #walks $u \to v$ of length $k$ | §1.2 |
| $A^{\otimes k}[u][v]$ = cheapest walk with exactly $k$ edges | §1.3, needs distributivity |
| $\begin{pmatrix} A & I \\ 0 & I\end{pmatrix}^k = \begin{pmatrix} A^k & \sum_{i<k} A^i \\ 0 & I \end{pmatrix}$ | geometric series of matrices, no division needed |
| cost $O(m^3 \log n)$; with precomputed powers $O(m^3\log n + Q\,m^2 \log n)$ | §1.5 |
| entries $< p \approx 10^9$: one product $< 1.0\cdot 10^{18}$, two products $< 2^{63}$ | why `(a*b + c*d) % p` is safe but long sums are not |

## 3. Implementation (C++ and Java)

General modular matrix product with the **accumulate-then-subtract** trick (keep the running sum below $p^2$ by subtracting $p^2$ when it reaches it — one comparison instead of a `%` per term), power by squaring, row-vector $\times$ matrix, and the precomputed-powers query loop. The driver answers $Q$ queries "number of walks $s \to t$ with exactly $k$ edges" ($k \le 10^{18}$) on a multigraph given by its adjacency counts.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
const ll M2 = MOD * MOD;                                   // accumulate products below 2*M2 < 2^63
using Mat = vector<vector<ll>>;

Mat mul(const Mat& A, const Mat& B) {                      // (n x K) * (K x m), entries in [0, MOD)
    int n = A.size(), K = B.size(), m = B[0].size();
    Mat C(n, vector<ll>(m, 0));
    for (int i = 0; i < n; i++)
        for (int k = 0; k < K; k++) {
            ll a = A[i][k];
            if (a == 0) continue;
            for (int j = 0; j < m; j++) {
                C[i][j] += a * B[k][j];
                if (C[i][j] >= M2) C[i][j] -= M2;
            }
        }
    for (auto& row : C) for (ll& x : row) x %= MOD;
    return C;
}
Mat eye(int n) { Mat I(n, vector<ll>(n, 0)); for (int i = 0; i < n; i++) I[i][i] = 1; return I; }
Mat power(Mat A, ll e) {                                    // O(n^3 log e)
    Mat R = eye(A.size());
    for (; e > 0; e >>= 1, A = mul(A, A)) if (e & 1) R = mul(R, A);
    return R;
}
vector<ll> vecMul(const vector<ll>& v, const Mat& A) {      // row vector times matrix, O(n^2)
    int n = A.size();
    vector<ll> r(n, 0);
    for (int k = 0; k < n; k++) {
        if (v[k] == 0) continue;
        for (int j = 0; j < n; j++) r[j] = (r[j] + v[k] * A[k][j]) % MOD;
    }
    return r;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q;
    cin >> n >> q;
    Mat A(n, vector<ll>(n));
    for (auto& row : A) for (ll& x : row) cin >> x;         // A[u][v] = number of edges u -> v
    const int LOG = 60;
    vector<Mat> P(LOG);                                     // P[j] = A^(2^j), built once: O(n^3 LOG)
    P[0] = A;
    for (int j = 1; j < LOG; j++) P[j] = mul(P[j - 1], P[j - 1]);
    string out;
    while (q--) {
        int s, t; ll k;
        cin >> s >> t >> k;                                 // walks s -> t with exactly k edges (1-indexed)
        vector<ll> v(n, 0);
        v[s - 1] = 1;
        for (int j = 0; j < LOG; j++) if (k >> j & 1) v = vecMul(v, P[j]);   // O(n^2 LOG) per query
        out += to_string(v[t - 1]);
        out += '\n';
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L, M2 = MOD * MOD;

    static long[][] mul(long[][] A, long[][] B) {
        int n = A.length, K = B.length, m = B[0].length;
        long[][] C = new long[n][m];
        for (int i = 0; i < n; i++) {
            long[] Ci = C[i];
            for (int k = 0; k < K; k++) {
                long a = A[i][k];
                if (a == 0) continue;
                long[] Bk = B[k];
                for (int j = 0; j < m; j++) {
                    Ci[j] += a * Bk[j];
                    if (Ci[j] >= M2) Ci[j] -= M2;
                }
            }
            for (int j = 0; j < m; j++) Ci[j] %= MOD;
        }
        return C;
    }
    static long[][] power(long[][] A, long e) {
        int n = A.length;
        long[][] R = new long[n][n];
        for (int i = 0; i < n; i++) R[i][i] = 1;
        for (; e > 0; e >>= 1, A = mul(A, A)) if ((e & 1) == 1) R = mul(R, A);
        return R;
    }
    static long[] vecMul(long[] v, long[][] A) {
        int n = A.length;
        long[] r = new long[n];
        for (int k = 0; k < n; k++) {
            if (v[k] == 0) continue;
            for (int j = 0; j < n; j++) r[j] = (r[j] + v[k] * A[k][j]) % MOD;
        }
        return r;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        long[][] A = new long[n][n];
        for (int i = 0; i < n; i++) for (int j = 0; j < n; j++) A[i][j] = in.nextLong();
        final int LOG = 60;
        long[][][] P = new long[LOG][][];
        P[0] = A;
        for (int j = 1; j < LOG; j++) P[j] = mul(P[j - 1], P[j - 1]);
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int s = in.nextInt(), t = in.nextInt();
            long k = in.nextLong();
            long[] v = new long[n];
            v[s - 1] = 1;
            for (int j = 0; j < LOG; j++) if ((k >> j & 1) == 1) v = vecMul(v, P[j]);
            sb.append(v[t - 1]).append('\n');
        }
        out.print(sb);
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
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
2 5
1 1
1 0
1 1 0
1 2 0
1 1 10
1 2 10
2 2 1
out:
1
0
89
55
0
-->
<!-- test
in:
3 2
0 1 1
1 0 1
1 1 0
1 1 3
1 2 2
out:
2
1
-->
<!-- test
in:
2 2
1 1
1 0
1 1 1000000000000000000
1 2 1000000000000000000
out:
680057396
209783453
-->

The first matrix is the Fibonacci matrix, so walks $1 \to 1$ of length $k$ number $F_{k+1}$; the last test was checked with an independent fast-doubling implementation ($F_{10^{18}+1}$ and $F_{10^{18}}$ mod $10^9+7$).

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| $n$ (length, number of steps, time) up to $10^{12}$–$10^{18}$, other parameters $\le 100$ | matrix power over a state of size $\le 100$ |
| "number of strings/sequences of length $n$" with rules on consecutive (or last $d$) elements | states = last element(s), $T$ = allowed transitions |
| tilings of a $w \times n$ board with small $w$ | states = column profiles ([broken profile DP](../06-Dynamic-Programming/11-broken-profile-dp.md)) |
| "apply this linear map $k$ times", affine maps $x \mapsto ax + b$ | $2 \times 2$ augmented matrix |
| "cheapest/longest route with exactly $k$ edges", $k$ huge | $(\min,+)$ / $(\max,+)$ power |
| linear recurrence with constant coefficients, $n$ huge | companion matrix; order $d > 200$ → Kitamasa/Berlekamp–Massey |
| point updates of a step + range "compose these steps" queries | segment tree whose nodes store transition matrices |

**Confused with:** periodicity (some sequences mod $p$ repeat with a short period, e.g. $f_{i} = f_{i-1} - f_{i-2}$ has period 6), and closed forms (geometric sums with an invertible ratio). Matrix power is the safe general tool when you do not see a formula.

## 5. Worked examples (graded)

### Example 1 — Fibonacci Numbers  ·  ★ ≈1500 (est.)

- **Source:** [CSES 1722 · Fibonacci Numbers](https://cses.fi/problemset/task/1722)
- **Difficulty:** ≈1500 (est.)
- **Problem:** $F_0 = 0$, $F_1 = 1$, $F_n = F_{n-1} + F_{n-2}$. Print $F_n \bmod 10^9+7$ for $n \le 10^{18}$.
- **Thinking from first principles:** the state $(F_{t+1}, F_t)$ advances by a fixed $2\times2$ linear map, so $F_n$ is an entry of $Q^n$. Iteration ($10^{18}$ steps) is impossible; squaring needs 60 steps.

<details><summary>Solution</summary>

$Q^n = \begin{pmatrix}F_{n+1}&F_n\\F_n&F_{n-1}\end{pmatrix}$, read entry $(0,1)$. With fixed-size arrays the product is four lines; each entry is a sum of two products $< 2^{61}$, so one `%` per entry is safe. Time $O(\log n)$. Fast doubling (§2) is an equivalent alternative.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
using M22 = array<array<ll, 2>, 2>;

M22 mul(const M22& A, const M22& B) {
    M22 C{};
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++)
            C[i][j] = (A[i][0] * B[0][j] + A[i][1] * B[1][j]) % MOD;   // two products < 2^61 each
    return C;
}

int main() {
    ll n;
    cin >> n;
    M22 R{{{1, 0}, {0, 1}}}, Q{{{1, 1}, {1, 0}}};    // Q^n = [[F(n+1), F(n)], [F(n), F(n-1)]]
    for (ll e = n; e > 0; e >>= 1, Q = mul(Q, Q))
        if (e & 1) R = mul(R, Q);
    cout << R[0][1] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;

    static long[][] mul(long[][] A, long[][] B) {
        long[][] C = new long[2][2];
        for (int i = 0; i < 2; i++)
            for (int j = 0; j < 2; j++)
                C[i][j] = (A[i][0] * B[0][j] + A[i][1] * B[1][j]) % MOD;
        return C;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        long n = in.nextLong();
        long[][] R = {{1, 0}, {0, 1}}, Q = {{1, 1}, {1, 0}};
        for (long e = n; e > 0; e >>= 1, Q = mul(Q, Q))
            if ((e & 1) == 1) R = mul(R, Q);
        System.out.println(R[0][1]);
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
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
10
out:
55
-->
<!-- test
in:
0
out:
0
-->
<!-- test
in:
1000000000000000000
out:
209783453
-->

</details>

### Example 2 — Throwing Dice  ·  ★ ≈1700 (est.)

- **Source:** [CSES 1096 · Throwing Dice](https://cses.fi/problemset/task/1096)
- **Difficulty:** ≈1700 (est.)
- **Problem:** count ordered sequences of dice throws (faces 1–6) with total $n \le 10^{18}$, modulo $10^9+7$.
- **Thinking from first principles:** $dp[n] = \sum_{d=1}^{6} dp[n-d]$, $dp[0] = 1$ (the last throw is $d$). The step needs the last six values — state $(dp[i], dp[i-1], \dots, dp[i-5])$, and the step is the companion matrix: first row all ones, ones on the sub-diagonal (shifting the window). Starting state at $i = 0$ is $(1, 0, 0, 0, 0, 0)$ (negative indices are 0), so $dp[n]$ is the $(0,0)$ entry of $T^n$.

<details><summary>Solution</summary>

$6^3 \cdot 120 \approx 2.6\cdot10^4$ operations. The program uses the column-vector convention ($v_{i+1} = T v_i$, answer $= (T^n v_0)_0 = (T^n)_{0,0}$); for the companion matrix either convention works as long as you are consistent.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
using Mat = vector<vector<ll>>;

Mat mul(const Mat& A, const Mat& B) {
    int n = A.size();
    Mat C(n, vector<ll>(n, 0));
    for (int i = 0; i < n; i++)
        for (int k = 0; k < n; k++)
            for (int j = 0; j < n; j++) C[i][j] = (C[i][j] + A[i][k] * B[k][j]) % MOD;
    return C;
}

int main() {
    ll n;
    cin >> n;
    // state (dp[i], dp[i-1], ..., dp[i-5]);  dp[i+1] = dp[i] + ... + dp[i-5]
    Mat T(6, vector<ll>(6, 0)), R(6, vector<ll>(6, 0));
    for (int j = 0; j < 6; j++) T[0][j] = 1;                // companion matrix
    for (int i = 1; i < 6; i++) T[i][i - 1] = 1;            // shift the window down
    for (int i = 0; i < 6; i++) R[i][i] = 1;
    for (ll e = n; e > 0; e >>= 1, T = mul(T, T))
        if (e & 1) R = mul(R, T);
    // initial state at i = 0: (dp[0], dp[-1], ..., dp[-5]) = (1, 0, ..., 0); answer = first coordinate
    cout << R[0][0] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;

    static long[][] mul(long[][] A, long[][] B) {
        int n = A.length;
        long[][] C = new long[n][n];
        for (int i = 0; i < n; i++)
            for (int k = 0; k < n; k++)
                for (int j = 0; j < n; j++) C[i][j] = (C[i][j] + A[i][k] * B[k][j]) % MOD;
        return C;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        long n = in.nextLong();
        long[][] T = new long[6][6], R = new long[6][6];
        for (int j = 0; j < 6; j++) T[0][j] = 1;
        for (int i = 1; i < 6; i++) T[i][i - 1] = 1;
        for (int i = 0; i < 6; i++) R[i][i] = 1;
        for (long e = n; e > 0; e >>= 1, T = mul(T, T))
            if ((e & 1) == 1) R = mul(R, T);
        System.out.println(R[0][0]);
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
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
3
out:
4
-->
<!-- test
in:
1
out:
1
-->
<!-- test
in:
7
out:
63
-->
<!-- test
in:
1000000000000000000
out:
106021903
-->

</details>

### Example 3 — Decoding Genome  ·  ★ 1900

- **Source:** [CF 222E · Decoding Genome](https://codeforces.com/problemset/problem/222/E) — 1900
- **Difficulty:** 1900
- **Problem:** strings of length $n \le 10^{15}$ over an alphabet of $m \le 52$ nucleotides (written `a`–`z`, then `A`–`Z`); $k$ ordered pairs "$y$ may not directly follow $x$" are forbidden. Count valid strings mod $10^9+7$.
- **Thinking from first principles:** state = last letter, $m$ states; $T[x][y] = 0$ for forbidden pairs, 1 otherwise. A string of length $n$ is a walk of $n - 1$ steps starting anywhere, so the answer is the sum of all entries of $T^{n-1}$ (§1.2). $52^3 \cdot 100 \approx 1.4\cdot10^7$.

<details><summary>Solution</summary>

The exponent is $n - 1$, not $n$ (a length-1 string has no transitions — the "$n = 1 \Rightarrow m$" test checks this). The accumulate-then-subtract product keeps the inner loop free of `%`.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
const ll M2 = MOD * MOD;
using Mat = vector<vector<ll>>;

Mat mul(const Mat& A, const Mat& B) {
    int n = A.size();
    Mat C(n, vector<ll>(n, 0));
    for (int i = 0; i < n; i++)
        for (int k = 0; k < n; k++) {
            ll a = A[i][k];
            if (!a) continue;
            for (int j = 0; j < n; j++) { C[i][j] += a * B[k][j]; if (C[i][j] >= M2) C[i][j] -= M2; }
        }
    for (auto& r : C) for (ll& x : r) x %= MOD;
    return C;
}
int id(char c) { return islower(c) ? c - 'a' : c - 'A' + 26; }

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    ll n; int m, k;
    cin >> n >> m >> k;
    Mat T(m, vector<ll>(m, 1));                       // T[u][v] = 1 if nucleotide v may follow u
    for (int i = 0; i < k; i++) {
        string s; cin >> s;
        T[id(s[0])][id(s[1])] = 0;
    }
    Mat R(m, vector<ll>(m, 0));
    for (int i = 0; i < m; i++) R[i][i] = 1;
    for (ll e = n - 1; e > 0; e >>= 1, T = mul(T, T))  // n letters = n - 1 transitions
        if (e & 1) R = mul(R, T);
    ll ans = 0;
    for (auto& r : R) for (ll x : r) ans = (ans + x) % MOD;   // any first letter, any last letter
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L, M2 = MOD * MOD;

    static long[][] mul(long[][] A, long[][] B) {
        int n = A.length;
        long[][] C = new long[n][n];
        for (int i = 0; i < n; i++) {
            long[] Ci = C[i];
            for (int k = 0; k < n; k++) {
                long a = A[i][k];
                if (a == 0) continue;
                long[] Bk = B[k];
                for (int j = 0; j < n; j++) { Ci[j] += a * Bk[j]; if (Ci[j] >= M2) Ci[j] -= M2; }
            }
            for (int j = 0; j < n; j++) Ci[j] %= MOD;
        }
        return C;
    }
    static int id(char c) { return Character.isLowerCase(c) ? c - 'a' : c - 'A' + 26; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        long n = in.nextLong();
        int m = in.nextInt(), k = in.nextInt();
        long[][] T = new long[m][m], R = new long[m][m];
        for (long[] row : T) Arrays.fill(row, 1);
        for (int i = 0; i < k; i++) {
            String s = in.next();
            T[id(s.charAt(0))][id(s.charAt(1))] = 0;
        }
        for (int i = 0; i < m; i++) R[i][i] = 1;
        for (long e = n - 1; e > 0; e >>= 1, T = mul(T, T))
            if ((e & 1) == 1) R = mul(R, T);
        long ans = 0;
        for (long[] row : R) for (long x : row) ans = (ans + x) % MOD;
        System.out.println(ans);
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
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
        String next() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            StringBuilder sb = new StringBuilder();
            for (; c > ' '; c = read()) sb.append((char) c);
            return sb.toString();
        }
    }
}
```

<!-- test
in:
3 3 2
ab
ba
out:
17
-->
<!-- test
in:
3 3 0
out:
27
-->
<!-- test
in:
2 1 1
aa
out:
0
-->
<!-- test
in:
1 52 0
out:
52
-->
<!-- test
in:
4 28 3
Ba
aB
BB
out:
607881
-->
<!-- test
in:
1000000000000000 2 0
out:
264444359
-->

</details>

The last test is $2^{10^{15}} \bmod (10^9+7)$ (no restrictions, two letters), computed independently with Python's `pow`.

### Example 4 — Graph Paths II (cheapest walk with exactly k edges)  ·  ★ ≈2000 (est.)

- **Source:** [CSES 1724 · Graph Paths II](https://cses.fi/problemset/task/1724)
- **Difficulty:** ≈2000 (est.)
- **Problem:** a directed graph with $n \le 100$ vertices and weighted edges (weights $\le 10^9$); find the minimum total weight of a route from $1$ to $n$ using **exactly** $k \le 10^9$ edges (vertices may repeat), or $-1$.
- **Thinking from first principles:** "exactly $k$ edges" rules out Dijkstra. The layered Bellman–Ford $d_{t+1}[v] = \min_u d_t[u] + w(u, v)$ is a $(\min,+)$ vector–matrix product — linear in the $(\min,+)$ semiring — so $d_k = d_0 \otimes W^{\otimes k}$ (§1.3). $100^3 \cdot 60 = 6\cdot10^7$ min-plus steps.

<details><summary>Solution</summary>

Identity: $0$ on the diagonal, $\infty$ elsewhere. Parallel edges: keep the minimum. Use $\infty = 2^{63}/4$ and *skip* infinite entries instead of adding them (avoids overflow); real costs are at most $k \cdot 10^9 = 10^{18}$, and a sum of two real partial costs is at most $2\cdot10^{18} < \infty$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll INF = LLONG_MAX / 4;                           // "no walk"; real costs stay below 1e18 + 1e18
using Mat = vector<vector<ll>>;

Mat mulMinPlus(const Mat& A, const Mat& B) {            // (A*B)[i][j] = min_k A[i][k] + B[k][j]
    int n = A.size();
    Mat C(n, vector<ll>(n, INF));
    for (int i = 0; i < n; i++)
        for (int k = 0; k < n; k++) {
            if (A[i][k] >= INF) continue;
            for (int j = 0; j < n; j++)
                if (B[k][j] < INF) C[i][j] = min(C[i][j], A[i][k] + B[k][j]);
        }
    return C;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; ll k;
    cin >> n >> m >> k;
    Mat A(n, vector<ll>(n, INF));
    for (int i = 0; i < m; i++) {
        int a, b; ll c; cin >> a >> b >> c;
        A[a - 1][b - 1] = min(A[a - 1][b - 1], c);      // parallel flights: keep the cheapest
    }
    Mat R(n, vector<ll>(n, INF));
    for (int i = 0; i < n; i++) R[i][i] = 0;            // identity of (min,+): 0 on the diagonal, INF elsewhere
    for (ll e = k; e > 0; e >>= 1, A = mulMinPlus(A, A))
        if (e & 1) R = mulMinPlus(R, A);
    cout << (R[0][n - 1] >= INF ? -1 : R[0][n - 1]) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long INF = Long.MAX_VALUE / 4;

    static long[][] mulMinPlus(long[][] A, long[][] B) {
        int n = A.length;
        long[][] C = new long[n][n];
        for (long[] row : C) Arrays.fill(row, INF);
        for (int i = 0; i < n; i++)
            for (int k = 0; k < n; k++) {
                long a = A[i][k];
                if (a >= INF) continue;
                long[] Bk = B[k], Ci = C[i];
                for (int j = 0; j < n; j++)
                    if (Bk[j] < INF && a + Bk[j] < Ci[j]) Ci[j] = a + Bk[j];
            }
        return C;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        long k = in.nextLong();
        long[][] A = new long[n][n], R = new long[n][n];
        for (long[] row : A) Arrays.fill(row, INF);
        for (int i = 0; i < m; i++) {
            int a = in.nextInt() - 1, b = in.nextInt() - 1;
            long c = in.nextLong();
            A[a][b] = Math.min(A[a][b], c);
        }
        for (int i = 0; i < n; i++) { Arrays.fill(R[i], INF); R[i][i] = 0; }
        for (long e = k; e > 0; e >>= 1, A = mulMinPlus(A, A))
            if ((e & 1) == 1) R = mulMinPlus(R, A);
        System.out.println(R[0][n - 1] >= INF ? -1 : R[0][n - 1]);
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
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
3 4 2
1 2 5
2 3 4
1 3 1
3 1 2
out:
9
-->
<!-- test
in:
3 4 3
1 2 5
2 3 4
1 3 1
3 1 2
out:
4
-->
<!-- test
in:
2 0 5
out:
-1
-->
<!-- test
in:
2 2 999999999
1 2 1000000000
2 1 1000000000
out:
999999999000000000
-->

</details>

In the last test the only walks alternate $1 \to 2 \to 1 \dots$; with an odd number of edges they end at 2 and cost $k \cdot 10^9$.

### Example 5 — Sum of a recurrence with a polynomial term  ·  ★ ≈2000 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈2000 (est.)
- **Problem:** given $a_0, a_1$ and $a_i = p\,a_{i-1} + q\,a_{i-2} + r\,i + s$ for $i \ge 2$ (all parameters in $[0, 10^9+7)$), print $S_n = \sum_{i=0}^{n} a_i \bmod 10^9+7$ for $n \le 10^{18}$.
- **Thinking from first principles:** the step is linear in $(a_{i}, a_{i-1})$ except for the "$r\,i + s$" part and the running sum. Augment (§1.4): state $v_i = (a_i, a_{i-1}, i, 1, S_i)$. Then
  $a_{i+1} = p a_i + q a_{i-1} + r\,i + (r + s)\cdot 1$, $\;i + 1 = i + 1$, $\;S_{i+1} = S_i + a_{i+1}$ — every new coordinate is a fixed combination of old ones: a $5\times5$ matrix.

<details><summary>Solution</summary>

$v_n = T^{n-1} v_1$ with $v_1 = (a_1, a_0, 1, 1, a_0 + a_1)$; handle $n = 0$ separately. The last row of $T$ equals the first row plus the "keep $S$" coefficient. Verified against direct iteration for $n \le 5000$; the $10^{18}$ test against an independent Python implementation.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;
using Mat = vector<vector<ll>>;

Mat mul(const Mat& A, const Mat& B) {
    int n = A.size();
    Mat C(n, vector<ll>(n, 0));
    for (int i = 0; i < n; i++)
        for (int k = 0; k < n; k++)
            for (int j = 0; j < n; j++) C[i][j] = (C[i][j] + A[i][k] * B[k][j]) % MOD;
    return C;
}

int main() {
    ll a0, a1, p, q, r, s, n;
    cin >> a0 >> a1 >> p >> q >> r >> s >> n;
    if (n == 0) { cout << a0 % MOD << '\n'; return 0; }
    // state v_i = (a_i, a_{i-1}, i, 1, S_i) with S_i = a_0 + ... + a_i
    // a_{i+1} = p a_i + q a_{i-1} + r (i+1) + s = p a_i + q a_{i-1} + r i + (r + s) * 1
    Mat T = {
        {p, q, r, (r + s) % MOD, 0},     // a_{i+1}
        {1, 0, 0, 0, 0},                 // a_i
        {0, 0, 1, 1, 0},                 // i + 1
        {0, 0, 0, 1, 0},                 // 1
        {p, q, r, (r + s) % MOD, 1},     // S_{i+1} = S_i + a_{i+1}
    };
    Mat R(5, vector<ll>(5, 0));
    for (int i = 0; i < 5; i++) R[i][i] = 1;
    for (ll e = n - 1; e > 0; e >>= 1, T = mul(T, T))
        if (e & 1) R = mul(R, T);
    vector<ll> v1 = {a1, a0, 1, 1, (a0 + a1) % MOD};
    ll ans = 0;
    for (int j = 0; j < 5; j++) ans = (ans + R[4][j] * v1[j]) % MOD;   // S_n = row 4 of T^(n-1) times v_1
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;

    static long[][] mul(long[][] A, long[][] B) {
        int n = A.length;
        long[][] C = new long[n][n];
        for (int i = 0; i < n; i++)
            for (int k = 0; k < n; k++)
                for (int j = 0; j < n; j++) C[i][j] = (C[i][j] + A[i][k] * B[k][j]) % MOD;
        return C;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        long a0 = in.nextLong(), a1 = in.nextLong(), p = in.nextLong(), q = in.nextLong();
        long r = in.nextLong(), s = in.nextLong(), n = in.nextLong();
        if (n == 0) { System.out.println(a0 % MOD); return; }
        long rs = (r + s) % MOD;
        long[][] T = {
            {p, q, r, rs, 0},
            {1, 0, 0, 0, 0},
            {0, 0, 1, 1, 0},
            {0, 0, 0, 1, 0},
            {p, q, r, rs, 1},
        };
        long[][] R = new long[5][5];
        for (int i = 0; i < 5; i++) R[i][i] = 1;
        for (long e = n - 1; e > 0; e >>= 1, T = mul(T, T))
            if ((e & 1) == 1) R = mul(R, T);
        long[] v1 = {a1, a0, 1, 1, (a0 + a1) % MOD};
        long ans = 0;
        for (int j = 0; j < 5; j++) ans = (ans + R[4][j] * v1[j]) % MOD;
        System.out.println(ans);
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
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
1 1 1 1 0 0 10
out:
232
-->
<!-- test
in:
7 9 1 1 1 1 0
out:
7
-->
<!-- test
in:
7 9 1 1 1 1 1
out:
16
-->
<!-- test
in:
3 5 2 7 11 13 30
out:
93068323
-->
<!-- test
in:
3 5 2 7 11 13 1000000000000000000
out:
839395240
-->

</details>

The first test is Fibonacci shifted by one ($a_i = F_{i+1}$), so $S_{10} = F_{13} - 1 = 232$.

## 6. Tricks, pitfalls and things to remember

1. **Off-by-one in the exponent.** Write down the state at a concrete index ($v_0$ or $v_1$) and the index you want; the exponent is their difference. Test $n = 0$ and $n = 1$ explicitly.
2. **Row vs column vectors.** $v_{t+1} = v_t T$ (row) uses $T[i][j]$ = "from $i$ to $j$"; $v_{t+1} = T v_t$ (column) uses the transpose. Mixing them is a silent WA for non-symmetric $T$.
3. **Overflow in the inner sum.** Entries $< p \approx 10^9$: a single product is $< 10^{18}$, but $m$ of them overflow `long long` once $m \ge 10$. Either `%` every term, or accumulate and subtract $p^2$ whenever the sum reaches $p^2$ (§3). Same in Java (no unsigned types; `Long` overflow wraps silently).
4. **Large moduli.** If $p \approx 10^{18}$, products need `__int128` in C++ and `Math.multiplyHigh` (or `BigInteger`) in Java.
5. **Negative coefficients** (e.g. $a_n = 2a_{n-1} - a_{n-2}$): store them as $p - c$; never let a negative value into the matrix.
6. **$(\min,+)$ identity and infinity.** Identity has $0$ on the diagonal and $\infty$ off it; skip $\infty$ operands instead of adding them; use parallel-edge minimum.
7. **Name clashes in C++20.** With `using namespace std`, a function called `identity` collides with `std::identity` (this file's first draft hit it). Prefer names like `eye`, `matPow`.
8. **Loop order and zeros.** Use $i$–$k$–$j$ order (contiguous inner access) and skip $A[i][k] = 0$; transition matrices are often sparse.
9. **Exponent 0** returns the identity — make sure your identity is the right one for the semiring.
10. **Java:** allocate `long[][]` per product (fine), hoist row references (`long[] Ci = C[i]`) out of the inner loop, and never use `Long` objects inside the product.
11. **Many queries with different $k$:** precompute $T^{2^j}$ and multiply a vector (§1.5); re-powering the matrix per query costs a factor $m$.
12. **Do not use floating point** for counting modulo $p$; for probabilities with huge $n$ use doubles (they converge) or exact rationals modulo $p$.

## 7. Going further (toward 2400–2600+)

- **Segment tree of matrices ("dynamic DP").** Store each step's transition matrix in a leaf; inner nodes store products; point updates and range compositions in $O(m^3 \log n)$: [CF 1252K · Addition Robot](https://codeforces.com/problemset/problem/1252/K) — 2100, [CF 718C · Sasha and Array](https://codeforces.com/problemset/problem/718/C) — 2300, and in $(\min,+)$ form [CF 1609E · William The Oblivious](https://codeforces.com/problemset/problem/1609/E) — 2400.
- **Boolean powers with bitsets** for reachability over huge times: [CF 576D · Flights for Regular Customers](https://codeforces.com/problemset/problem/576/D) — 2700.
- **$(\max,+)$ with binary lifting** to find the *smallest* $k$ with a property (e.g. a positive cycle of length $\le k$): [CF 147B · Smile House](https://codeforces.com/problemset/problem/147/B) — 2500.
- **Exponents modulo $p-1$**: [CF 1182E · Product Oriented Recurrence](https://codeforces.com/problemset/problem/1182/E) — 2300; with a discrete logarithm on top, [CF 1106F · Lunar New Year and a Recursive Sequence](https://codeforces.com/problemset/problem/1106/F) — 2400.
- **Large order $d$.** For a linear recurrence of order $d$, Kitamasa / Cayley–Hamilton gives $O(d^2 \log n)$ (or $O(d \log d \log n)$ with FFT), and Berlekamp–Massey recovers an unknown recurrence from $2d$ terms. See [matrices and linear recurrences](../15-Advanced-Math/01-matrices-and-linear-recurrences.md) and [Lagrange interpolation and Berlekamp–Massey](../15-Advanced-Math/05-lagrange-interpolation-and-berlekamp-massey.md).
- **Piecewise-constant transitions:** multiply the powers of each piece in order, e.g. obstacles that appear on intervals of columns ([CF 954F · Runner's Problem](https://codeforces.com/problemset/problem/954/F) — 2100, [CF 821E · Okabe and El Psy Kongroo](https://codeforces.com/problemset/problem/821/E) — 2100).

## 8. Practice ladder

**≤ 1700**
- [ ] [CSES 1722 · Fibonacci Numbers](https://cses.fi/problemset/task/1722)
- [ ] [CSES 1096 · Throwing Dice](https://cses.fi/problemset/task/1096)
- [ ] [CF 185A · Plant](https://codeforces.com/problemset/problem/185/A) — 1300
- [ ] [CF 166E · Tetrahedron](https://codeforces.com/problemset/problem/166/E) — 1500
- [ ] [CF 678D · Iterated Linear Function](https://codeforces.com/problemset/problem/678/D) — 1700

**1700–2100**
- [ ] [CSES 1723 · Graph Paths I](https://cses.fi/problemset/task/1723)
- [ ] [CSES 1724 · Graph Paths II](https://cses.fi/problemset/task/1724)
- [ ] [AtCoder DP R · Walk](https://atcoder.jp/contests/dp/tasks/dp_r)
- [ ] [CF 222E · Decoding Genome](https://codeforces.com/problemset/problem/222/E) — 1900
- [ ] [CF 691E · Xor-sequences](https://codeforces.com/problemset/problem/691/E) — 1900
- [ ] [CF 621E · Wet Shark and Blocks](https://codeforces.com/problemset/problem/621/E) — 2000
- [ ] [CF 1117D · Magic Gems](https://codeforces.com/problemset/problem/1117/D) — 2100
- [ ] [CF 551D · GukiZ and Binary Operations](https://codeforces.com/problemset/problem/551/D) — 2100
- [ ] [CF 954F · Runner's Problem](https://codeforces.com/problemset/problem/954/F) — 2100
- [ ] [CF 821E · Okabe and El Psy Kongroo](https://codeforces.com/problemset/problem/821/E) — 2100
- [ ] [CF 1252K · Addition Robot](https://codeforces.com/problemset/problem/1252/K) — 2100

**2100+**
- [ ] [CF 718C · Sasha and Array](https://codeforces.com/problemset/problem/718/C) — 2300
- [ ] [CF 1182E · Product Oriented Recurrence](https://codeforces.com/problemset/problem/1182/E) — 2300
- [ ] [CF 1609E · William The Oblivious](https://codeforces.com/problemset/problem/1609/E) — 2400
- [ ] [CF 1106F · Lunar New Year and a Recursive Sequence](https://codeforces.com/problemset/problem/1106/F) — 2400
- [ ] [CF 147B · Smile House](https://codeforces.com/problemset/problem/147/B) — 2500
- [ ] [CF 576D · Flights for Regular Customers](https://codeforces.com/problemset/problem/576/D) — 2700

Hints: 185A and 166E — two or three states suffice; 678D — affine map as a $2\times2$ matrix; 691E — vertices are array elements, edges where the XOR has popcount divisible by 3; 621E — states are remainders, one block is one step; 1117D — recurrence of order $M$; 551D — handle each bit independently, Fibonacci counts strings without two adjacent ones.

## 9. LeetCode / FAANG cross-reference

- [LC 509 · Fibonacci Number](https://leetcode.com/problems/fibonacci-number/) — Easy, [LC 70 · Climbing Stairs](https://leetcode.com/problems/climbing-stairs/) — Easy, [LC 1137 · N-th Tribonacci Number](https://leetcode.com/problems/n-th-tribonacci-number/) — Easy — the "can you do better than $O(n)$?" follow-up: $2\times2$ / $3\times3$ matrix power or fast doubling.
- [LC 935 · Knight Dialer](https://leetcode.com/problems/knight-dialer/) — Medium — walks on the 10-vertex knight graph of the keypad: $A^{n-1}$.
- [LC 1220 · Count Vowels Permutation](https://leetcode.com/problems/count-vowels-permutation/) — Hard — walks on a 5-vertex graph, Example 3 in miniature.
- [LC 552 · Student Attendance Record II](https://leetcode.com/problems/student-attendance-record-ii/) — Hard — 6 states (absences used, trailing lates).
- [LC 790 · Domino and Tromino Tiling](https://leetcode.com/problems/domino-and-tromino-tiling/) — Medium — derive $a_n = 2a_{n-1} + a_{n-3}$, then a companion matrix.
- [LC 2851 · String Transformation](https://leetcode.com/problems/string-transformation/) — Hard — KMP for the valid rotations plus a $2\times2$ matrix power for "$k$ operations".

Interviews: the linear DP is the expected answer; mentioning (and sketching) the $O(\log n)$ matrix power is a common bonus question for Fibonacci-like problems.

## 10. Self-check

1. What three properties must a DP have for matrix exponentiation to apply?
2. Prove that $(A^k)[u][v]$ counts walks of length $k$.
3. Which algebraic properties make $(\min,+)$ powers valid, and what is the $(\min,+)$ identity matrix?
4. How do you handle a "$+\,r\,i + s$" term and a running sum? Write the state vector.
5. Why is `(a * b) % p` safe for $p \approx 10^9$ but `sum of 50 products` is not, and what are two fixes?
6. You have $10^4$ queries with different $k$ and $m = 50$. How do you avoid $m^3 \log k$ per query?
7. When is $m^3 \log n$ too slow, and what replaces it for linear recurrences?
8. State the fast-doubling identities for Fibonacci.

<details><summary>Answers</summary>

1. Constant-size state, a step that is linear in the state (in some semiring), and the same step every time (or piecewise constant).
2. Induction on $k$: split a walk of length $k+1$ at its last edge; the sum over the penultimate vertex is the matrix product.
3. $\oplus = \min$ is associative and commutative, $\otimes = +$ is associative and distributes over $\min$. Identity: $0$ on the diagonal, $+\infty$ elsewhere.
4. Augment: $(a_i, a_{i-1}, i, 1, S_i)$; $i+1$ and the constant are linear in $(i, 1)$, and $S_{i+1} = S_i + a_{i+1}$.
5. A product of two values below $10^9+7$ is about $10^{18} < 9.2\cdot10^{18}$, but ten of them overflow. Reduce every term, or keep the running sum below $p^2$ by subtracting $p^2$.
6. Precompute $T^{2^j}$ once and multiply a vector by the needed powers: $O(m^2 \log k)$ per query.
7. Around $m \ge 200$ (with $n \approx 10^{18}$). For order-$d$ linear recurrences use Kitamasa/Cayley–Hamilton ($O(d^2\log n)$) and Berlekamp–Massey to find the recurrence.
8. $F_{2k} = F_k(2F_{k+1} - F_k)$, $F_{2k+1} = F_k^2 + F_{k+1}^2$.

</details>

Back to the [folder README](README.md) · [problems](problems.md) · [cheat sheet](../99-Cheat-Sheets/07-dp-optimizations-cheatsheet.md)
