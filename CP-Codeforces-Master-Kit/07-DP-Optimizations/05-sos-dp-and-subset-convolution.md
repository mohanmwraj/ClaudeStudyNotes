# SOS DP, Zeta/Möbius Transforms and Subset Convolution

> **Band:** 🟠 2000–2400 (subset convolution 🔴 2400+) · **Priority:** ⚡ (subset convolution 🧊) · **FAANG:** low · **Prerequisites:** [bit manipulation](../01-Foundations/03-bit-manipulation.md), [bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md), [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md), [inclusion–exclusion](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md)
> **You can say you know this when:** you can write the subset and superset zeta/Möbius loops from memory and explain why the in-place loop order is correct; you can turn "count pairs/subsets whose AND/OR/XOR satisfies …" into *transform → pointwise product → inverse transform*; and you know when a disjoint union needs subset convolution instead of OR convolution.

## 1. First principles — why this works

### 1.1 The problem and the two naive solutions

Given $a[0..2^n)$ indexed by bitmasks, compute for every mask $m$

$$F[m] = \sum_{s \subseteq m} a[s] \qquad (s \subseteq m \iff s \mathbin{\&} m = s).$$

- **Naive 1:** for every $m$ scan all $2^n$ masks: $4^n$. Dead for $n \ge 13$.
- **Naive 2:** enumerate only the submasks of $m$ with `for (s = m; ; s = (s - 1) & m)`. Mask $m$ has $2^{|m|}$ submasks, so the total is $\sum_k \binom{n}{k} 2^k = 3^n$ (binomial theorem on $(1+2)^n$). For $n = 20$ that is $3.5\cdot 10^9$ — still too slow.

The waste: $F[m]$ and $F[m \setminus \{i\}]$ share half of their terms, yet naive 2 recomputes each from scratch.

### 1.2 The hypercube view: it is just a prefix sum

Think of a mask as a point of the cube $\{0,1\}^n$. Then $s \subseteq m$ means $s_i \le m_i$ in *every* coordinate. So $F$ is an **$n$-dimensional prefix sum** over a $2\times2\times\dots\times2$ grid. You already know how to do 2-D prefix sums in two passes (rows, then columns): a $d$-dimensional prefix sum is $d$ one-dimensional passes, one per axis. Here every axis has length 2, so the 1-D prefix sum along axis $i$ is the single statement

```text
for every mask m with bit i set:   a[m] += a[m ^ (1 << i)]
```

$n$ passes of $2^n$ steps: $O(n\,2^n)$. That is the whole of "SOS DP" (sum over subsets).

### 1.3 Proof by an intermediate quantity

Define $F_i[m]$ = sum of $a[s]$ over the masks $s$ that are $\subseteq m$ **on bits $0..i-1$** and **equal** to $m$ on bits $i..n-1$. Then $F_0 = a$ and $F_n = F$. For pass $i$:

- if bit $i$ of $m$ is 0, every counted $s$ must also have bit $i = 0$: $F_{i+1}[m] = F_i[m]$;
- if bit $i$ of $m$ is 1, $s$ may have bit $i$ = 1 (that is $F_i[m]$) or 0 (that is $F_i[m \oplus 2^i]$), disjointly: $F_{i+1}[m] = F_i[m] + F_i[m \oplus 2^i]$.

Every $s \subseteq m$ is counted **exactly once**: the bits of $m \setminus s$ are dropped one at a time, each in its own pass, so there is a unique path from $s$ to $m$. This uniqueness is why the transform works with *any* commutative associative operation (sum, max, min, OR, gcd, "top-2" merge) — no idempotence is needed, and a top-$k$ merge never sees the same element twice.

**Why in place is safe.** In pass $i$ we read $a[m \oplus 2^i]$, a mask with bit $i$ *clear*; such entries are never written during pass $i$, so they still hold $F_i$. Consequently the order of $m$ inside a pass is irrelevant, and so is the order of the passes (prefix sums along different axes commute).

**The classic bug** is swapping the loops (mask outer, bit inner). Then $a[m]$ adds the *finished* $F[m \oplus 2^i]$ for every bit, and a mask $s$ with $|m \setminus s| = d$ gets counted $d!$ times along different paths. Bits outer, masks inner — always.

### 1.4 The inverse (Möbius) and supersets

Each pass is invertible: undo a 1-D prefix sum by a difference, `a[m] -= a[m ^ (1 << i)]`. Doing that for every bit gives the **Möbius transform**

$$a[m] = \sum_{s \subseteq m} (-1)^{|m \setminus s|}\, F[s],$$

which is exactly inclusion–exclusion. Algebraically, zeta is the tensor power $Z = \begin{pmatrix}1&0\\1&1\end{pmatrix}^{\otimes n}$ and Möbius is $Z^{-1} = \begin{pmatrix}1&0\\-1&1\end{pmatrix}^{\otimes n}$. Möbius needs subtraction, so it works for sums (mod $p$ too) but **not** for max/min.

Sums over **supersets** are the same thing on the complemented cube: for masks with bit $i$ clear, `a[m] += a[m | (1 << i)]`.

### 1.5 From transforms to convolutions

A transform is useful when it turns a hard combination into a pointwise product.

- **OR convolution** $h[k] = \sum_{i \lor j = k} f[i]\,g[j]$. Because $i \lor j \subseteq m \iff (i \subseteq m \text{ and } j \subseteq m)$,
  $$\hat h[m] = \sum_{k\subseteq m} h[k] = \Big(\sum_{i\subseteq m} f[i]\Big)\Big(\sum_{j\subseteq m} g[j]\Big) = \hat f[m]\,\hat g[m].$$
  So: zeta both, multiply, Möbius. $O(n 2^n)$ instead of $4^n$.
- **AND convolution** $h[k] = \sum_{i \land j = k} f[i]g[j]$: the same with supersets ($i \land j \supseteq m \iff i \supseteq m$ and $j \supseteq m$).
- **XOR convolution** $h[k] = \sum_{i \oplus j = k} f[i]g[j]$: use characters $\chi_m(s) = (-1)^{|s \land m|}$, which satisfy $\chi_m(s \oplus t) = \chi_m(s)\chi_m(t)$. The **Walsh–Hadamard transform** $\hat f[m] = \sum_s \chi_m(s) f[s]$ therefore turns XOR convolution into a pointwise product. Its matrix is $H = \begin{pmatrix}1&1\\1&-1\end{pmatrix}^{\otimes n}$ with $H^2 = 2^n I$, so the inverse is the same butterfly followed by division by $2^n$. It is the $\mathbb{Z}_2^n$ analogue of the FFT (see [FFT and NTT](../15-Advanced-Math/03-fft-and-ntt.md)).
- **Subset convolution** $h[S] = \sum_{T \subseteq S} f[T]\,g[S\setminus T]$ — the pair $(T, S \setminus T)$ must be *disjoint*. OR convolution over-counts overlapping pairs. The fix is one observation: for $i \lor j = S$, $\;i \land j = 0 \iff |i| + |j| = |S|$. So split $f$ by popcount ("rank"), $f_r[m] = f[m]\,[|m| = r]$, zeta each rank, multiply as polynomials in the rank, Möbius each rank, and read $h[S]$ from rank $|S|$:
  $$\hat h_r[m] = \sum_{a+b=r} \hat f_a[m]\,\hat g_b[m], \qquad h[S] = \mu(\hat h_{|S|})[S].$$
  Pairs with $|i|+|j| = |S|$ and $i \lor j = S$ are exactly the disjoint ones. Cost $O(n^2 2^n)$ versus $3^n$ for the direct submask loop ($n = 20$: $4\cdot10^8$ simple operations vs $3.5\cdot10^9$).

### 1.6 Complexity summary

| Operation | Time | Memory |
|---|---|---|
| submask enumeration of all masks | $3^n$ | $O(1)$ extra |
| zeta / Möbius (subset or superset) | $n 2^n$ | in place |
| OR / AND convolution | $3 \cdot n 2^n$ | $2 \cdot 2^n$ |
| XOR convolution (WHT) | $3 \cdot n 2^n$ + one modular inverse | $2 \cdot 2^n$ |
| subset convolution (ranked) | $O(n^2 2^n)$ | $O(n 2^n)$ |

$n = 20$: $2^n \approx 10^6$, $n2^n \approx 2\cdot10^7$ (fast in both languages); $n=23$: $1.9\cdot10^8$ — still fine in C++ with `int` arrays (32 MB).

## 2. Formulas, definitions and identities

| Name | Formula | Meaning / proof |
|---|---|---|
| Submask count | $\sum_m 2^{\lvert m\rvert} = 3^n$ | each bit is "not in $m$" / "in $m$, not in $s$" / "in both" |
| Subset zeta | $\zeta a[m] = \sum_{s \subseteq m} a[s]$ | $n$ axis-wise prefix sums (§1.3) |
| Subset Möbius | $\mu F[m] = \sum_{s \subseteq m} (-1)^{\lvert m\setminus s\rvert} F[s]$ | inverse tensor factor $\begin{pmatrix}1&0\\-1&1\end{pmatrix}$ |
| Superset zeta | $\zeta^{\uparrow} a[m] = \sum_{s \supseteq m} a[s]$ | complement the cube |
| "exactly" from "at least" | $\mathrm{exact}[m] = \sum_{s \supseteq m} (-1)^{\lvert s\setminus m\rvert}\,\mathrm{atLeast}[s]$ | superset Möbius = inclusion–exclusion |
| OR convolution | $\zeta(f \ast_{\lor} g) = \zeta f \cdot \zeta g$ | §1.5 |
| AND convolution | $\zeta^{\uparrow}(f \ast_{\land} g) = \zeta^{\uparrow} f \cdot \zeta^{\uparrow} g$ | §1.5 |
| WHT | $\hat f[m] = \sum_s (-1)^{\lvert s \land m\rvert} f[s]$; butterfly $(u,v)\mapsto(u+v,\,u-v)$ | characters of $\mathbb{Z}_2^n$ |
| WHT inverse | $f = \frac{1}{2^n} H \hat f$ | $H^2 = 2^n I$ |
| XOR convolution | $\widehat{f \ast_{\oplus} g} = \hat f \cdot \hat g$; $k$-fold: $\hat f^{\,k}$ | $\chi_m(s\oplus t)=\chi_m(s)\chi_m(t)$ |
| Subset convolution | $h[S] = \sum_{T\subseteq S} f[T] g[S\setminus T]$ via ranks | $i \lor j = S,\ \lvert i\rvert+\lvert j\rvert=\lvert S\rvert \iff i\land j=0$ |
| Subsets with AND $= 0$ | $\sum_m (-1)^{\lvert m\rvert}\,(2^{c[m]}-1)$, $c = \zeta^{\uparrow}(\mathrm{cnt})$ | Example 4 |
| Pairs with $a_i \land a_j = 0$ | $\sum_i \zeta(\mathrm{cnt})[\lnot a_i]$ | $a_j \land a_i = 0 \iff a_j \subseteq \lnot a_i$ |
| Pairs with $a_i \lor a_j \subseteq m$ | $\zeta(\mathrm{cnt})[m]^2$ | both must be submasks of $m$ |
| Divisor-lattice zeta | $F[x] = \sum_{d \mid x} a[d]$: for each prime $p$, for $x$ ascending, $a[px] \mathrel{+}= a[x]$ | same "one axis at a time" idea on exponent vectors, $O(V \log\log V)$ |

Two facts that save you in contests:

1. **Superset sums of `cnt` count elements; $2^{c}$ counts subsets.** "Number of non-empty subsets whose AND contains $m$" is $2^{c[m]} - 1$ because a subset's AND contains $m$ iff every element does.
2. **Möbius of a product is not the product of Möbius.** Multiply only in the transformed domain.

## 3. Implementation (C++ and Java)

One program with every transform: it reads $n$, then $f$ and $g$ of length $2^n$ (values $< 998244353$) and prints the OR, AND, XOR and subset convolutions modulo $998244353$. Stress-tested against the $4^n$ definitions.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 998244353;

ll power(ll b, ll e) {
    ll r = 1; b %= MOD;
    for (; e > 0; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD;
    return r;
}
// f[m] <- sum of f[s] over s subset of m            (zeta on the subset lattice)
void zetaSub(vector<ll>& f, int B) {
    for (int i = 0; i < B; i++)
        for (int m = 0; m < (1 << B); m++)
            if (m >> i & 1) { f[m] += f[m ^ (1 << i)]; if (f[m] >= MOD) f[m] -= MOD; }
}
// inverse of zetaSub: f[m] <- sum of (-1)^{|m \ s|} f[s]
void mobiusSub(vector<ll>& f, int B) {
    for (int i = 0; i < B; i++)
        for (int m = 0; m < (1 << B); m++)
            if (m >> i & 1) { f[m] -= f[m ^ (1 << i)]; if (f[m] < 0) f[m] += MOD; }
}
// f[m] <- sum of f[s] over s superset of m
void zetaSup(vector<ll>& f, int B) {
    for (int i = 0; i < B; i++)
        for (int m = 0; m < (1 << B); m++)
            if (!(m >> i & 1)) { f[m] += f[m | (1 << i)]; if (f[m] >= MOD) f[m] -= MOD; }
}
void mobiusSup(vector<ll>& f, int B) {
    for (int i = 0; i < B; i++)
        for (int m = 0; m < (1 << B); m++)
            if (!(m >> i & 1)) { f[m] -= f[m | (1 << i)]; if (f[m] < 0) f[m] += MOD; }
}
// Walsh-Hadamard: f[m] <- sum of (-1)^{popcount(s & m)} f[s]; the inverse also divides by 2^B
void wht(vector<ll>& f, int B, bool inverse) {
    int N = 1 << B;
    for (int len = 1; len < N; len <<= 1)
        for (int i = 0; i < N; i += len << 1)
            for (int j = i; j < i + len; j++) {
                ll u = f[j], v = f[j + len];
                f[j] = (u + v) % MOD;
                f[j + len] = (u - v + MOD) % MOD;
            }
    if (inverse) {
        ll inv = power(N, MOD - 2);
        for (ll& x : f) x = x * inv % MOD;
    }
}
vector<ll> orConv(vector<ll> f, vector<ll> g, int B) {      // h[k] = sum_{i|j=k} f[i] g[j]
    zetaSub(f, B); zetaSub(g, B);
    for (int m = 0; m < (1 << B); m++) f[m] = f[m] * g[m] % MOD;
    mobiusSub(f, B);
    return f;
}
vector<ll> andConv(vector<ll> f, vector<ll> g, int B) {     // h[k] = sum_{i&j=k} f[i] g[j]
    zetaSup(f, B); zetaSup(g, B);
    for (int m = 0; m < (1 << B); m++) f[m] = f[m] * g[m] % MOD;
    mobiusSup(f, B);
    return f;
}
vector<ll> xorConv(vector<ll> f, vector<ll> g, int B) {     // h[k] = sum_{i^j=k} f[i] g[j]
    wht(f, B, false); wht(g, B, false);
    for (int m = 0; m < (1 << B); m++) f[m] = f[m] * g[m] % MOD;
    wht(f, B, true);
    return f;
}
// h[S] = sum over T subset of S of f[T] * g[S \ T]   (ranked zeta, O(B^2 2^B))
vector<ll> subsetConv(const vector<ll>& f, const vector<ll>& g, int B) {
    int N = 1 << B;
    vector<vector<ll>> F(B + 1, vector<ll>(N, 0)), G(B + 1, vector<ll>(N, 0)), H(B + 1, vector<ll>(N, 0));
    for (int m = 0; m < N; m++) {
        F[__builtin_popcount(m)][m] = f[m];
        G[__builtin_popcount(m)][m] = g[m];
    }
    for (int r = 0; r <= B; r++) { zetaSub(F[r], B); zetaSub(G[r], B); }
    for (int m = 0; m < N; m++)
        for (int r = 0; r <= B; r++) {
            ll acc = 0;
            for (int a = 0; a <= r; a++) acc = (acc + F[a][m] * G[r - a][m]) % MOD;
            H[r][m] = acc;
        }
    for (int r = 0; r <= B; r++) mobiusSub(H[r], B);
    vector<ll> h(N);
    for (int m = 0; m < N; m++) h[m] = H[__builtin_popcount(m)][m];   // keep only rank = |S|
    return h;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int B; cin >> B;
    int N = 1 << B;
    vector<ll> f(N), g(N);
    for (auto& x : f) cin >> x;
    for (auto& x : g) cin >> x;
    for (const auto& h : {orConv(f, g, B), andConv(f, g, B), xorConv(f, g, B), subsetConv(f, g, B)})
        for (int m = 0; m < N; m++) cout << h[m] << (m == N - 1 ? '\n' : ' ');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L;

    static long power(long b, long e) {
        long r = 1; b %= MOD;
        for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD;
        return r;
    }
    static void zetaSub(long[] f, int B) {
        for (int i = 0; i < B; i++)
            for (int m = 0; m < (1 << B); m++)
                if ((m >> i & 1) == 1) { f[m] += f[m ^ (1 << i)]; if (f[m] >= MOD) f[m] -= MOD; }
    }
    static void mobiusSub(long[] f, int B) {
        for (int i = 0; i < B; i++)
            for (int m = 0; m < (1 << B); m++)
                if ((m >> i & 1) == 1) { f[m] -= f[m ^ (1 << i)]; if (f[m] < 0) f[m] += MOD; }
    }
    static void zetaSup(long[] f, int B) {
        for (int i = 0; i < B; i++)
            for (int m = 0; m < (1 << B); m++)
                if ((m >> i & 1) == 0) { f[m] += f[m | (1 << i)]; if (f[m] >= MOD) f[m] -= MOD; }
    }
    static void mobiusSup(long[] f, int B) {
        for (int i = 0; i < B; i++)
            for (int m = 0; m < (1 << B); m++)
                if ((m >> i & 1) == 0) { f[m] -= f[m | (1 << i)]; if (f[m] < 0) f[m] += MOD; }
    }
    static void wht(long[] f, int B, boolean inverse) {
        int N = 1 << B;
        for (int len = 1; len < N; len <<= 1)
            for (int i = 0; i < N; i += len << 1)
                for (int j = i; j < i + len; j++) {
                    long u = f[j], v = f[j + len];
                    f[j] = (u + v) % MOD;
                    f[j + len] = (u - v + MOD) % MOD;
                }
        if (inverse) {
            long inv = power(N, MOD - 2);
            for (int i = 0; i < N; i++) f[i] = f[i] * inv % MOD;
        }
    }
    static long[] orConv(long[] f0, long[] g0, int B) {
        long[] f = f0.clone(), g = g0.clone();
        zetaSub(f, B); zetaSub(g, B);
        for (int m = 0; m < (1 << B); m++) f[m] = f[m] * g[m] % MOD;
        mobiusSub(f, B);
        return f;
    }
    static long[] andConv(long[] f0, long[] g0, int B) {
        long[] f = f0.clone(), g = g0.clone();
        zetaSup(f, B); zetaSup(g, B);
        for (int m = 0; m < (1 << B); m++) f[m] = f[m] * g[m] % MOD;
        mobiusSup(f, B);
        return f;
    }
    static long[] xorConv(long[] f0, long[] g0, int B) {
        long[] f = f0.clone(), g = g0.clone();
        wht(f, B, false); wht(g, B, false);
        for (int m = 0; m < (1 << B); m++) f[m] = f[m] * g[m] % MOD;
        wht(f, B, true);
        return f;
    }
    static long[] subsetConv(long[] f, long[] g, int B) {
        int N = 1 << B;
        long[][] F = new long[B + 1][N], G = new long[B + 1][N], H = new long[B + 1][N];
        for (int m = 0; m < N; m++) { F[Integer.bitCount(m)][m] = f[m]; G[Integer.bitCount(m)][m] = g[m]; }
        for (int r = 0; r <= B; r++) { zetaSub(F[r], B); zetaSub(G[r], B); }
        for (int m = 0; m < N; m++)
            for (int r = 0; r <= B; r++) {
                long acc = 0;
                for (int a = 0; a <= r; a++) acc = (acc + F[a][m] * G[r - a][m]) % MOD;
                H[r][m] = acc;
            }
        for (int r = 0; r <= B; r++) mobiusSub(H[r], B);
        long[] h = new long[N];
        for (int m = 0; m < N; m++) h[m] = H[Integer.bitCount(m)][m];
        return h;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int B = in.nextInt(), N = 1 << B;
        long[] f = new long[N], g = new long[N];
        for (int i = 0; i < N; i++) f[i] = in.nextLong();
        for (int i = 0; i < N; i++) g[i] = in.nextLong();
        for (long[] h : new long[][]{orConv(f, g, B), andConv(f, g, B), xorConv(f, g, B), subsetConv(f, g, B)}) {
            StringBuilder sb = new StringBuilder();
            for (int m = 0; m < N; m++) sb.append(h[m]).append(m == N - 1 ? '\n' : ' ');
            out.print(sb);
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
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
1
1 2
3 4
out:
3 18
13 8
11 10
3 10
-->
<!-- test
in:
0
5
7
out:
35
35
35
35
-->
<!-- test
in:
2
1 2 3 4
5 6 7 998244352
out:
5 28 43 94
94 34 46 998244349
34 41 44 51
5 16 22 51
-->

Notes on the code:

- `zetaSub` uses a conditional subtract instead of `%`: the loop is otherwise a load, an add and a store, so a division per element is a large relative cost.
- For plain counts (no modulus) use `int`/`long long` arrays and skip the reductions; 2^20 `int`s is 4 MB.
- In the ranked product only $a \le |m|$ and $r - a \le |m|$ give non-zero terms; skipping the rest halves subset convolution, but keep the simple version until you need the speed.

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| values $\le 10^6$ or $\le 2^{20}$–$2^{23}$, "AND / OR equals / contains / is zero" | zeta over subsets or supersets of a count array |
| "for each element find another with $a_i \land a_j = 0$" | best/any submask of $\lnot a_i$ |
| "number of subsets whose AND (OR) is exactly $x$" | superset (subset) zeta of counts → $2^c - 1$ → Möbius |
| $n \le 20$ items, "for each subset $S$ of items, combine the values of all its subsets" | zeta on item masks (often after an exponential precompute per mask) |
| "split $S$ into two disjoint parts", $3^n$ too slow ($n \ge 18$) | subset convolution |
| "XOR of chosen elements equals $t$", counts for every $t$, or $k$-fold choices | Walsh–Hadamard (power pointwise for $k$-fold) |
| query "max over all $i \subseteq m$" or "top two over $i \subseteq m$" | zeta with a max / top-2 monoid (no inverse needed) |
| $\gcd$/$\operatorname{lcm}$/divisibility conditions with values $\le 10^6$ | the divisor-lattice version (Dirichlet prefix sums) |

**Often confused with:** bitmask DP over subsets (that is DP *on* the lattice with transitions between states; SOS is the *aggregate over all submasks* step), and with the binary trie (good for XOR max/min queries, not for "submask" conditions).

## 5. Worked examples (graded)

### Example 1 — SOS Bit Problem  ·  ★ ≈1900 (est.)

- **Source:** [CSES 1654 · SOS Bit Problem](https://cses.fi/problemset/task/1654)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n \le 2\cdot10^5$ integers $x_i < 2^{20}$. For every $x$ in the array output three counts over the array elements $y$: those with $x \lor y = x$, those with $x \land y = x$, and those with $x \land y \ne 0$.
- **Thinking from first principles:** $x \lor y = x$ means $y$ adds no new bit, i.e. $y \subseteq x$ — a subset sum of the count array. $x \land y = x$ means $y \supseteq x$ — a superset sum. $x \land y \ne 0$ is the complement of $y \subseteq \lnot x$. Brute force is $O(n^2) = 4\cdot10^{10}$; the submask loop is $3^{20}$; two zeta transforms are $2\cdot 20 \cdot 2^{20} \approx 4\cdot10^7$.

<details><summary>Solution</summary>

Build `cnt`, copy it into `sub` and `sup`, run the subset and superset zeta in the same pass loop (they touch different arrays), answer each query in $O(1)$. Time $O(B 2^B + n)$ with $B = 20$, memory two arrays of $2^{20}$ ints.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int B = 20, N = 1 << B;
    int n;
    cin >> n;
    vector<int> x(n), sub(N, 0), sup(N, 0);
    for (int& v : x) { cin >> v; sub[v]++; sup[v]++; }
    for (int i = 0; i < B; i++)
        for (int m = 0; m < N; m++) {
            if (m >> i & 1) sub[m] += sub[m ^ (1 << i)];   // sub[m] = #y with y subset of m
            else sup[m] += sup[m | (1 << i)];              // sup[m] = #y with y superset of m
        }
    string out;
    for (int v : x) {
        out += to_string(sub[v]);                          // x | y == x  <=>  y subset of x
        out += ' ';
        out += to_string(sup[v]);                          // x & y == x  <=>  y superset of x
        out += ' ';
        out += to_string(n - sub[(N - 1) ^ v]);            // x & y != 0  <=>  y not inside ~x
        out += '\n';
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        final int B = 20, N = 1 << B;
        int n = in.nextInt();
        int[] x = new int[n], sub = new int[N], sup = new int[N];
        for (int i = 0; i < n; i++) { x[i] = in.nextInt(); sub[x[i]]++; sup[x[i]]++; }
        for (int i = 0; i < B; i++)
            for (int m = 0; m < N; m++) {
                if ((m >> i & 1) == 1) sub[m] += sub[m ^ (1 << i)];
                else sup[m] += sup[m | (1 << i)];
            }
        StringBuilder sb = new StringBuilder();
        for (int v : x)
            sb.append(sub[v]).append(' ').append(sup[v]).append(' ').append(n - sub[(N - 1) ^ v]).append('\n');
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
5
3 7 2 9 2
out:
3 2 5
4 1 5
2 4 4
1 1 3
2 4 4
-->
<!-- test
in:
1
1000000
out:
1 1 1
-->

</details>

### Example 2 — Compatible Numbers  ·  ★ 2200

- **Source:** [CF 165E · Compatible Numbers](https://codeforces.com/problemset/problem/165/E) — 2200
- **Difficulty:** 2200
- **Problem:** $n \le 10^6$ numbers $1 \le a_i \le 4\cdot10^6$. For every $i$ print some element $a_j$ of the array with $a_i \land a_j = 0$, or $-1$. (Any valid element is accepted; we print the **largest**, which makes the output unique.)
- **Thinking from first principles:** $a_i \land a_j = 0 \iff a_j \subseteq \lnot a_i$ (complement inside 22 bits, since $4\cdot10^6 < 2^{22}$). So we need, for every mask $m$, *some* array element that is a submask of $m$: a zeta transform with the operation "max" instead of "+". Max has no inverse, but we never need one.

<details><summary>Solution</summary>

`best[v] = v` for present values, $-1$ elsewhere; run the subset zeta with `max`; the answer for $a_i$ is `best[(2^22 - 1) ^ a_i]`. Correctness: `best[m]` is the maximum over all present $s \subseteq m$ by §1.3. Time $22 \cdot 2^{22} \approx 9\cdot10^7$ simple operations, memory 16 MB.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int B = 22, N = 1 << B;           // 4e6 < 2^22
    int n;
    cin >> n;
    vector<int> a(n), best(N, -1);          // best[m] = largest a_j that is a submask of m
    for (int& v : a) { cin >> v; best[v] = v; }
    for (int i = 0; i < B; i++)
        for (int m = 0; m < N; m++)
            if (m >> i & 1) best[m] = max(best[m], best[m ^ (1 << i)]);
    string out;
    for (int i = 0; i < n; i++) {
        out += to_string(best[(N - 1) ^ a[i]]);   // a_j & a_i == 0  <=>  a_j subset of ~a_i
        out += (i + 1 < n ? ' ' : '\n');
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        final int B = 22, N = 1 << B;
        int n = in.nextInt();
        int[] a = new int[n], best = new int[N];
        Arrays.fill(best, -1);
        for (int i = 0; i < n; i++) { a[i] = in.nextInt(); best[a[i]] = a[i]; }
        for (int i = 0; i < B; i++)
            for (int m = 0; m < N; m++)
                if ((m >> i & 1) == 1 && best[m ^ (1 << i)] > best[m]) best[m] = best[m ^ (1 << i)];
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.append(best[(N - 1) ^ a[i]]).append(i + 1 < n ? ' ' : '\n');
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
4
90 36 1 6
out:
36 90 90 1
-->
<!-- test
in:
3
1 1 1
out:
-1 -1 -1
-->
<!-- test
in:
5
4000000 1 2 3 3999999
out:
3 4000000 4000000 4000000 -1
-->

</details>

### Example 3 — Or Plus Max  ·  ★ ≈2111 (AtCoder estimate)

- **Source:** [AtCoder ARC100 E · Or Plus Max](https://atcoder.jp/contests/arc100/tasks/arc100_c)
- **Difficulty:** ≈2111 (AtCoder estimate)
- **Problem:** a sequence $A_0, \dots, A_{2^N-1}$ ($N \le 18$, $A_i \le 10^9$). For every $K = 1, \dots, 2^N - 1$ print $\max A_i + A_j$ over $0 \le i < j \le 2^N-1$ with $(i \lor j) \le K$.
- **Thinking from first principles:** "$i \lor j \le K$" is awkward, "$i \lor j = m$" is awkward too, but "$i, j \subseteq m$" is easy — it is a submask aggregate. Every pair with $i \lor j \le K$ has both indices inside $m = i \lor j \le K$, and conversely any pair inside some $m \le K$ has $i \lor j \subseteq m$, so $i \lor j \le m \le K$. So answer$(K) = \max_{m \le K} \text{best2}(m)$, where best2$(m)$ is the sum of the two largest $A_i$ with $i \subseteq m$ (distinct indices). Top-2 is a commutative associative merge, and §1.3 guarantees the two merged index sets are disjoint, so no index is taken twice.

<details><summary>Solution</summary>

Store a (largest, second largest) pair per mask, merge along each bit, then a prefix maximum over $K$. Time $O(N 2^N)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n;
    cin >> n;
    int N = 1 << n;
    // top[m] = {largest, second largest} A_i over indices i that are submasks of m (distinct indices)
    vector<array<ll, 2>> top(N, {LLONG_MIN / 4, LLONG_MIN / 4});
    for (int i = 0; i < N; i++) cin >> top[i][0];
    for (int b = 0; b < n; b++)
        for (int m = 0; m < N; m++)
            if (m >> b & 1) {
                // the two index sets (bit b = 1 / bit b = 0) are disjoint, so a plain top-2 merge is safe
                auto& x = top[m];
                const auto& y = top[m ^ (1 << b)];
                for (ll v : y) {
                    if (v > x[0]) { x[1] = x[0]; x[0] = v; }
                    else if (v > x[1]) x[1] = v;
                }
            }
    string out;
    ll ans = LLONG_MIN;
    for (int k = 1; k < N; k++) {
        ans = max(ans, top[k][0] + top[k][1]);   // i|j <= K  <=>  i|j = m for some m <= K
        out += to_string(ans);
        out += '\n';
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), N = 1 << n;
        final long NEG = Long.MIN_VALUE / 4;
        long[] t0 = new long[N], t1 = new long[N];   // largest and second largest over submask indices
        Arrays.fill(t1, NEG);
        for (int i = 0; i < N; i++) t0[i] = in.nextLong();
        for (int b = 0; b < n; b++)
            for (int m = 0; m < N; m++)
                if ((m >> b & 1) == 1) {
                    int s = m ^ (1 << b);
                    for (long v : new long[]{t0[s], t1[s]}) {
                        if (v > t0[m]) { t1[m] = t0[m]; t0[m] = v; }
                        else if (v > t1[m]) t1[m] = v;
                    }
                }
        StringBuilder sb = new StringBuilder();
        long ans = Long.MIN_VALUE;
        for (int k = 1; k < N; k++) {
            ans = Math.max(ans, t0[k] + t1[k]);
            sb.append(ans).append('\n');
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
2
1 2 3 1
out:
3
4
5
-->
<!-- test
in:
1
5 5
out:
10
-->
<!-- test
in:
3
10 8 4 1 1 1 1 1000000000
out:
18
18
18
18
18
18
1000000010
-->

</details>

### Example 4 — Jzzhu and Numbers  ·  ★ 2400

- **Source:** [CF 449D · Jzzhu and Numbers](https://codeforces.com/problemset/problem/449/D) — 2400
- **Difficulty:** 2400
- **Problem:** $n \le 10^6$ numbers $0 \le a_i \le 10^6$. Count the non-empty sets of indices whose AND is $0$, modulo $10^9+7$.
- **Thinking from first principles:** "AND $= 0$" is an *exact* condition — hard to count directly. The *monotone* version is easy: the AND of a subset contains $m$ iff every element contains $m$; if $c[m]$ elements are supersets of $m$, exactly $2^{c[m]} - 1$ non-empty subsets have AND $\supseteq m$. That is "at least" counting; inclusion–exclusion (superset Möbius) turns it into "exactly", and we only need the value at $m = 0$:
  $$\#\{\text{AND} = 0\} = \sum_{m} (-1)^{|m|}\,\big(2^{c[m]} - 1\big).$$

<details><summary>Solution</summary>

$c = $ superset zeta of the count array; precompute powers of two up to $n$; sum with signs. Proof of the formula: a subset with AND $= t$ is counted in the term $m$ iff $m \subseteq t$, so it contributes $\sum_{m \subseteq t} (-1)^{|m|} = [t = 0]$. Time $20 \cdot 2^{20} + n$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 1'000'000'007;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int B = 20, N = 1 << B;          // a_i <= 1e6 < 2^20
    int n;
    cin >> n;
    vector<int> c(N, 0);
    for (int i = 0; i < n; i++) { int a; cin >> a; c[a]++; }
    for (int b = 0; b < B; b++)            // c[m] = #elements that are supersets of m
        for (int m = 0; m < N; m++)
            if (!(m >> b & 1)) c[m] += c[m | (1 << b)];
    vector<ll> pw(n + 1, 1);
    for (int i = 1; i <= n; i++) pw[i] = pw[i - 1] * 2 % MOD;
    ll ans = 0;
    for (int m = 0; m < N; m++) {
        ll ways = (pw[c[m]] - 1 + MOD) % MOD;   // non-empty subsets whose AND contains m
        if (__builtin_popcount(m) & 1) ans = (ans - ways + MOD) % MOD;
        else ans = (ans + ways) % MOD;
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
        final long MOD = 1_000_000_007L;
        final int B = 20, N = 1 << B;
        int n = in.nextInt();
        int[] c = new int[N];
        for (int i = 0; i < n; i++) c[in.nextInt()]++;
        for (int b = 0; b < B; b++)
            for (int m = 0; m < N; m++)
                if ((m >> b & 1) == 0) c[m] += c[m | (1 << b)];
        long[] pw = new long[n + 1];
        pw[0] = 1;
        for (int i = 1; i <= n; i++) pw[i] = pw[i - 1] * 2 % MOD;
        long ans = 0;
        for (int m = 0; m < N; m++) {
            long ways = (pw[c[m]] - 1 + MOD) % MOD;
            if ((Integer.bitCount(m) & 1) == 1) ans = (ans - ways + MOD) % MOD;
            else ans = (ans + ways) % MOD;
        }
        out.println(ans);
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
3
2 3 3
out:
0
-->
<!-- test
in:
4
0 1 2 3
out:
10
-->
<!-- test
in:
6
5 2 0 5 2 1
out:
53
-->
<!-- test
in:
1
1000000
out:
0
-->

</details>

### Example 5 — XOR of k choices for every target  ·  ★ ≈2200 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈2200 (est.)
- **Problem:** $B \le 17$, $n \le 2\cdot10^5$ values $a_i < 2^B$ and $k \le 10^{18}$. For every $t \in [0, 2^B)$ count sequences of $k$ indices $(i_1, \dots, i_k)$ (repetition allowed) with $a_{i_1} \oplus \dots \oplus a_{i_k} = t$, modulo $998244353$.
- **Thinking from first principles:** with $f = $ count array, the answer is the $k$-fold XOR convolution $f^{\ast k}$. Repeated squaring of convolutions costs $\log k$ transforms — but we can do better: in the Walsh–Hadamard domain convolution is a pointwise product, so $\widehat{f^{\ast k}} = \hat f^{\,k}$ pointwise. One forward transform, $2^B$ modular powers, one inverse transform.

<details><summary>Solution</summary>

$O(B 2^B + 2^B \log k)$. The modular exponent $k$ is used as is (do **not** reduce $k$ modulo $p-1$ unless you also treat $\hat f[m] \equiv 0$ separately; using $k$ directly is always correct). Division by $2^B$ uses the inverse modulo the prime.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 998244353;

ll power(ll b, ll e) {
    ll r = 1; b %= MOD;
    for (; e > 0; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD;
    return r;
}
void wht(vector<ll>& f) {                     // unnormalised Walsh-Hadamard transform, in place
    int N = f.size();
    for (int len = 1; len < N; len <<= 1)
        for (int i = 0; i < N; i += len << 1)
            for (int j = i; j < i + len; j++) {
                ll u = f[j], v = f[j + len];
                f[j] = (u + v) % MOD;
                f[j + len] = (u - v + MOD) % MOD;
            }
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int B, n; ll k;
    cin >> B >> n >> k;
    int N = 1 << B;
    vector<ll> f(N, 0);
    for (int i = 0; i < n; i++) { int a; cin >> a; f[a]++; }
    wht(f);
    for (ll& x : f) x = power(x, k);          // k-fold XOR convolution = k-th power pointwise
    wht(f);
    ll invN = power(N, MOD - 2);
    for (int t = 0; t < N; t++) cout << f[t] * invN % MOD << (t + 1 < N ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L;

    static long power(long b, long e) {
        long r = 1; b %= MOD;
        for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD;
        return r;
    }
    static void wht(long[] f) {
        int N = f.length;
        for (int len = 1; len < N; len <<= 1)
            for (int i = 0; i < N; i += len << 1)
                for (int j = i; j < i + len; j++) {
                    long u = f[j], v = f[j + len];
                    f[j] = (u + v) % MOD;
                    f[j + len] = (u - v + MOD) % MOD;
                }
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int B = in.nextInt(), n = in.nextInt();
        long k = in.nextLong();
        int N = 1 << B;
        long[] f = new long[N];
        for (int i = 0; i < n; i++) f[in.nextInt()]++;
        wht(f);
        for (int i = 0; i < N; i++) f[i] = power(f[i], k);
        wht(f);
        long invN = power(N, MOD - 2);
        StringBuilder sb = new StringBuilder();
        for (int t = 0; t < N; t++) sb.append(f[t] * invN % MOD).append(t + 1 < N ? ' ' : '\n');
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
2 3 2
1 2 3
out:
3 2 2 2
-->
<!-- test
in:
1 1 1
1
out:
0 1
-->
<!-- test
in:
3 4 7
0 1 6 7
out:
4096 4096 0 0 0 0 4096 4096
-->
<!-- test
in:
1 2 1000000000000000000
0 1
out:
121099884 121099884
-->

</details>

The last test has $k = 10^{18}$: $\hat f = (2, 0)$, so the answer is $2^{k-1}$ for both targets, checked independently with Python's `pow(2, 10**18 - 1, 998244353)`.

### Example 6 — Disjoint pairs meet XOR pairs  ·  ★ ≈2600 (est.)

- **Source:** Original problem (same flavour as [CF 914G · Sum the Fibonacci](https://codeforces.com/problemset/problem/914/G) — 2600).
- **Difficulty:** ≈2600 (est.)
- **Problem:** $B \le 17$, $n \le 2\cdot10^5$ values $s_i < 2^B$. Count ordered quadruples of indices $(a, b, c, d)$ with $s_a \land s_b = 0$ and $(s_a \lor s_b) \land (s_c \oplus s_d)$ having **exactly one** set bit, modulo $998244353$.
- **Thinking from first principles:** the condition factors into three independent "mask-valued" pieces glued by AND. Name the intermediate distributions:
  - $A[S]$ = number of ordered $(a,b)$ with $s_a \land s_b = 0$, $s_a \lor s_b = S$ — a **subset convolution** of `cnt` with itself (OR convolution would wrongly include overlapping pairs);
  - $D[T]$ = number of $(c,d)$ with $s_c \oplus s_d = T$ — an **XOR convolution**;
  - $H[U] = \sum_{x \land y = U} A[x] D[y]$ — an **AND convolution**; the answer is $\sum_b H[2^b]$.
  Each step is a transform pipeline; total $O(B^2 2^B)$, dominated by the subset convolution ($17^2 \cdot 2^{17} \approx 4\cdot10^7$).

<details><summary>Solution</summary>

Proof of the subset-convolution step: after ranking, the product at rank $r$ and mask $m$ counts pairs $(i, j)$ with $i, j \subseteq m$ and $|i| + |j| = r$. Möbius over $m$ restricts to $i \lor j = m$ exactly; choosing $r = |m|$ forces $|i| + |j| = |i \lor j|$, i.e. $i \land j = 0$. The other two steps are §1.5 directly.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const ll MOD = 998244353;
int B, N;

ll power(ll b, ll e) {
    ll r = 1; b %= MOD;
    for (; e > 0; e >>= 1, b = b * b % MOD) if (e & 1) r = r * b % MOD;
    return r;
}
void zetaSub(vector<ll>& f, int sign) {        // sign=+1: zeta, sign=-1: Mobius (subset lattice)
    for (int i = 0; i < B; i++)
        for (int m = 0; m < N; m++)
            if (m >> i & 1) f[m] = (f[m] + sign * f[m ^ (1 << i)] + MOD) % MOD;
}
void zetaSup(vector<ll>& f, int sign) {        // same on the superset lattice
    for (int i = 0; i < B; i++)
        for (int m = 0; m < N; m++)
            if (!(m >> i & 1)) f[m] = (f[m] + sign * f[m | (1 << i)] + MOD) % MOD;
}
void wht(vector<ll>& f) {
    for (int len = 1; len < N; len <<= 1)
        for (int i = 0; i < N; i += len << 1)
            for (int j = i; j < i + len; j++) {
                ll u = f[j], v = f[j + len];
                f[j] = (u + v) % MOD;
                f[j + len] = (u - v + MOD) % MOD;
            }
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n;
    cin >> B >> n;
    N = 1 << B;
    vector<ll> cnt(N, 0);
    for (int i = 0; i < n; i++) { int s; cin >> s; cnt[s]++; }

    // A[S] = #(a,b) with s_a & s_b = 0 and s_a | s_b = S      (subset convolution of cnt with itself)
    vector<vector<ll>> R(B + 1, vector<ll>(N, 0)), P(B + 1, vector<ll>(N, 0));
    for (int m = 0; m < N; m++) R[__builtin_popcount(m)][m] = cnt[m];
    for (int r = 0; r <= B; r++) zetaSub(R[r], +1);
    for (int m = 0; m < N; m++)
        for (int r = 0; r <= B; r++)
            for (int a = 0; a <= r; a++) P[r][m] = (P[r][m] + R[a][m] * R[r - a][m]) % MOD;
    for (int r = 0; r <= B; r++) zetaSub(P[r], -1);
    vector<ll> A(N);
    for (int m = 0; m < N; m++) A[m] = P[__builtin_popcount(m)][m];

    // D[T] = #(c,d) with s_c ^ s_d = T                         (XOR convolution)
    vector<ll> D = cnt;
    wht(D);
    for (ll& x : D) x = x * x % MOD;
    wht(D);
    ll invN = power(N, MOD - 2);
    for (ll& x : D) x = x * invN % MOD;

    // H[U] = sum over x & y = U of A[x] D[y]                   (AND convolution)
    zetaSup(A, +1); zetaSup(D, +1);
    vector<ll> H(N);
    for (int m = 0; m < N; m++) H[m] = A[m] * D[m] % MOD;
    zetaSup(H, -1);
    ll ans = 0;
    for (int b = 0; b < B; b++) ans = (ans + H[1 << b]) % MOD;
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L;
    static int B, N;

    static long power(long b, long e) {
        long r = 1; b %= MOD;
        for (; e > 0; e >>= 1, b = b * b % MOD) if ((e & 1) == 1) r = r * b % MOD;
        return r;
    }
    static void zetaSub(long[] f, int sign) {
        for (int i = 0; i < B; i++)
            for (int m = 0; m < N; m++)
                if ((m >> i & 1) == 1) f[m] = (f[m] + sign * f[m ^ (1 << i)] + MOD) % MOD;
    }
    static void zetaSup(long[] f, int sign) {
        for (int i = 0; i < B; i++)
            for (int m = 0; m < N; m++)
                if ((m >> i & 1) == 0) f[m] = (f[m] + sign * f[m | (1 << i)] + MOD) % MOD;
    }
    static void wht(long[] f) {
        for (int len = 1; len < N; len <<= 1)
            for (int i = 0; i < N; i += len << 1)
                for (int j = i; j < i + len; j++) {
                    long u = f[j], v = f[j + len];
                    f[j] = (u + v) % MOD;
                    f[j + len] = (u - v + MOD) % MOD;
                }
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        B = in.nextInt();
        int n = in.nextInt();
        N = 1 << B;
        long[] cnt = new long[N];
        for (int i = 0; i < n; i++) cnt[in.nextInt()]++;

        long[][] R = new long[B + 1][N], P = new long[B + 1][N];
        for (int m = 0; m < N; m++) R[Integer.bitCount(m)][m] = cnt[m];
        for (int r = 0; r <= B; r++) zetaSub(R[r], +1);
        for (int m = 0; m < N; m++)
            for (int r = 0; r <= B; r++)
                for (int a = 0; a <= r; a++) P[r][m] = (P[r][m] + R[a][m] * R[r - a][m]) % MOD;
        for (int r = 0; r <= B; r++) zetaSub(P[r], -1);
        long[] A = new long[N];
        for (int m = 0; m < N; m++) A[m] = P[Integer.bitCount(m)][m];

        long[] D = cnt.clone();
        wht(D);
        for (int m = 0; m < N; m++) D[m] = D[m] * D[m] % MOD;
        wht(D);
        long invN = power(N, MOD - 2);
        for (int m = 0; m < N; m++) D[m] = D[m] * invN % MOD;

        zetaSup(A, +1); zetaSup(D, +1);
        long[] H = new long[N];
        for (int m = 0; m < N; m++) H[m] = A[m] * D[m] % MOD;
        zetaSup(H, -1);
        long ans = 0;
        for (int b = 0; b < B; b++) ans = (ans + H[1 << b]) % MOD;
        out.println(ans);
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
2 3
1 2 3
out:
8
-->
<!-- test
in:
1 1
0
out:
0
-->
<!-- test
in:
3 5
0 1 2 4 7
out:
156
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Bits outer, masks inner.** Swapping the loops over-counts (a submask $d$ bits away is counted $d!$ times). If your result is too large, check this first.
2. **Choose $B$ from the value bound, not from $n$.** $4\cdot10^6 < 2^{22}$, $10^6 < 2^{20}$. One bit too few silently drops values; one bit too many doubles time and memory.
3. **Complement inside $B$ bits:** `(1 << B) - 1 ^ x`, never `~x` (that is negative in both languages and indexes out of bounds).
4. **Max/min/top-k need no inverse, but cannot be "un-zeta'd".** If you need an exact-equality answer with max, restructure the problem (e.g. Example 3's prefix maximum over $K$).
5. **Top-2 with indices:** in the standard pass order, the two sides merged at each step are disjoint index sets, so storing values is enough. If you write a *different* traversal (e.g. memoised recursion over submasks) duplicates can appear — then store indices and deduplicate.
6. **Overflow of counts.** $\zeta(\mathrm{cnt})[m]^2$ for $n = 10^6$ is $10^{12}$: use 64-bit. Under a modulus, keep values in $[0, p)$ and use conditional add/subtract; `(x - y) % p` is negative in C++ and Java when $x < y$.
7. **WHT under a modulus needs $2^B$ invertible** — fine for odd primes. Without a modulus (exact integers) the inverse is a right shift by $B$ after the butterfly, and intermediate values can reach $2^B \cdot \max \lvert f\rvert$ — check the range.
8. **Do not reduce the exponent $k$ mod $p-1$ blindly** in $\hat f^k$: $0^{k}$ with $k \equiv 0 \pmod{p-1}$ becomes $0^0 = 1$. Use $k$ itself.
9. **Subset convolution memory:** $(B+1)$ ranks $\times 2^B$ values $\times$ 3 arrays. For $B = 20$ that is $3 \cdot 21 \cdot 2^{20}$ 8-byte values ≈ 530 MB — too much. Use 32-bit storage (values mod $p < 2^{30}$), reuse arrays, and only keep ranks $\le |m|$; or transpose to `[mask][rank]` for cache locality.
10. **Java:** `int[1 << 22]` is fine (16 MB); `long[22][1 << 22]` is not. Use `Integer.bitCount`, and avoid `Integer`/boxing inside the $n 2^n$ loops. Plain `for` loops over `long[]`/`int[]` are what the JIT optimises best; keep `%` out of the innermost loop where a conditional subtraction suffices.
11. **C++:** `vector<int>` of $2^{23}$ is 32 MB — fine on a 256 MB limit, but `vector<long long>` of the same size plus a copy is already 128 MB. Size arrays to exactly $2^B$, and use `__builtin_popcount` (not a loop) for ranks.
12. **Count the empty set deliberately.** $2^{c} - 1$ (non-empty) versus $2^{c}$ — read the statement.

## 7. Going further (toward 2400–2600+)

- **Other bases.** Decimal digits with "digit-wise $\le$" ([CF 772D · Varying Kibibits](https://codeforces.com/problemset/problem/772/D) — 2700) is SOS on a $10\times10\times\dots$ grid: one prefix pass per digit position. Sums of squares need moments $(\sum 1, \sum x, \sum x^2)$ carried through the passes.
- **Divisor lattice.** $\gcd$/divisibility conditions use the same "one prime axis at a time" prefix sums (Dirichlet prefix sums), e.g. counting subsets with $\gcd = 1$ in [CF 1043F · Make It One](https://codeforces.com/problemset/problem/1043/F) — 2500. See [Möbius and Dirichlet](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md).
- **Set power series.** Ranked zeta turns the subset lattice into polynomials in the rank, so you can take the *exponential* or *logarithm* of a set function in $O(n^2 2^n)$ (count partitions of $[n]$ into "good" blocks, or connected spanning subgraphs from all spanning subgraphs). [CF 1326F2 · Wise Men (Hard Version)](https://codeforces.com/problemset/problem/1326/F2) — 3200 mixes OR transforms with integer partitions of $n$.
- **WHT with structure.** When $f$ has only a few distinct values per position, $\hat f[m]$ takes few values and can be found by solving small linear systems: [CF 1119H · Triple](https://codeforces.com/problemset/problem/1119/H) — 3200. [CF 662C · Binary Table](https://codeforces.com/problemset/problem/662/C) — 2600 is the clean "XOR convolution of a count array with a cost function" problem.
- **Inclusion–exclusion over column subsets** with per-row products ([CF 1530F · Bingo](https://codeforces.com/problemset/problem/1530/F) — 2600) is the same lattice thinking applied to probabilities.

## 8. Practice ladder

**≈1700–2100**
- [ ] [CSES 1654 · SOS Bit Problem](https://cses.fi/problemset/task/1654)
- [ ] [CSES 3141 · And Subset Count](https://cses.fi/problemset/task/3141)
- [ ] [CF 1829H · Don't Blame Me](https://codeforces.com/problemset/problem/1829/H) — 1700
- [ ] [AtCoder ARC100 E · Or Plus Max](https://atcoder.jp/contests/arc100/tasks/arc100_c)

**2100–2400**
- [ ] [CF 165E · Compatible Numbers](https://codeforces.com/problemset/problem/165/E) — 2200
- [ ] [CF 1234F · Yet Another Substring Reverse](https://codeforces.com/problemset/problem/1234/F) — 2200
- [ ] [CF 449D · Jzzhu and Numbers](https://codeforces.com/problemset/problem/449/D) — 2400
- [ ] [CF 1679E · Typical Party in Dorm](https://codeforces.com/problemset/problem/1679/E) — 2400
- [ ] [CF 1620G · Subsequences Galore](https://codeforces.com/problemset/problem/1620/G) — 2400

**2400+**
- [ ] [CF 1043F · Make It One](https://codeforces.com/problemset/problem/1043/F) — 2500
- [ ] [CF 1208F · Bits And Pieces](https://codeforces.com/problemset/problem/1208/F) — 2600
- [ ] [CF 662C · Binary Table](https://codeforces.com/problemset/problem/662/C) — 2600
- [ ] [CF 914G · Sum the Fibonacci](https://codeforces.com/problemset/problem/914/G) — 2600
- [ ] [CF 1530F · Bingo](https://codeforces.com/problemset/problem/1530/F) — 2600
- [ ] [CF 383E · Vowels](https://codeforces.com/problemset/problem/383/E) — 2700
- [ ] [CF 772D · Varying Kibibits](https://codeforces.com/problemset/problem/772/D) — 2700
- [ ] [CF 1326F2 · Wise Men (Hard Version)](https://codeforces.com/problemset/problem/1326/F2) — 3200
- [ ] [CF 1119H · Triple](https://codeforces.com/problemset/problem/1119/H) — 3200

Hints without spoilers: 1829H — exact AND counts via superset Möbius (a 64-state DP also works); 1234F — max over submasks of the complement; 1208F — keep the two largest *indices* per superset; 1679E — one SOS per possible query size; 1620G — inclusion–exclusion value per subset, then zeta; 383E — count the complement.

## 9. LeetCode / FAANG cross-reference

- [LC 982 · Triples with Bitwise AND Equal To Zero](https://leetcode.com/problems/triples-with-bitwise-and-equal-to-zero/) — Hard — count pairs by their AND (or use superset sums), then for each third element look up pairs that are submasks of its complement.
- [LC 1178 · Number of Valid Words for Each Puzzle](https://leetcode.com/problems/number-of-valid-words-for-each-puzzle/) — Hard — words become 26-bit masks; each puzzle enumerates the $2^6$ submasks that contain its first letter (submask enumeration, the $3^n$ idea at tiny $n$).

Rare in interviews: interviewers stop at "enumerate submasks of a 7-letter mask". Knowing the $3^n$ bound and the `(s - 1) & m` loop is the interview-relevant part.

## 10. Self-check

1. Why does $\sum_m 2^{|m|} = 3^n$?
2. State the intermediate quantity $F_i[m]$ and prove the in-place update is correct in any mask order.
3. What goes wrong if the mask loop is outside the bit loop?
4. Why can you zeta with `max` but not Möbius with it?
5. Derive the OR-convolution theorem in one line. Which transform handles AND?
6. Why is the WHT its own inverse up to $2^n$?
7. What does the rank dimension buy in subset convolution, and what is its complexity?
8. How do you count subsets with AND exactly $0$?

<details><summary>Answers</summary>

1. Each of the $n$ bits independently is outside $m$, inside $m$ but not $s$, or inside both: 3 choices per bit.
2. $F_i[m]$ sums $a[s]$ over $s$ that are submasks of $m$ on bits $< i$ and equal $m$ on bits $\ge i$. Pass $i$ only writes masks with bit $i$ set and only reads masks with bit $i$ clear, so reads see $F_i$ regardless of order.
3. Each $s \subseteq m$ is reached along every ordering of the missing bits: counted $|m \setminus s|!$ times.
4. Zeta only combines values (needs associativity and commutativity); Möbius must *remove* contributions, which needs an inverse, and max has none.
5. $\sum_{k \subseteq m} \sum_{i\lor j=k} f_ig_j = \sum_{i \subseteq m}\sum_{j \subseteq m} f_ig_j$. AND uses superset sums.
6. $H = \begin{pmatrix}1&1\\1&-1\end{pmatrix}^{\otimes n}$ and $\begin{pmatrix}1&1\\1&-1\end{pmatrix}^2 = 2I$, so $H^2 = 2^n I$.
7. It distinguishes disjoint from overlapping pairs: $i \lor j = S$ with $|i| + |j| = |S|$ iff $i \land j = 0$. $O(n^2 2^n)$.
8. $c = $ superset sums of counts, answer $= \sum_m (-1)^{|m|}(2^{c[m]} - 1)$.

</details>

Back to the [folder README](README.md) · [problems](problems.md) · [cheat sheet](../99-Cheat-Sheets/07-dp-optimizations-cheatsheet.md)
