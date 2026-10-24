# Bit manipulation

> **Band:** 🟢 ≤ 1400 → 🟣 2000 (bit tricks appear at every band; the reasoning gets deeper) · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [complexity](01-complexity-and-constraint-reading.md), [integer overflow](06-integer-overflow-precision-and-fast-io.md)
> **You can say you know this when:** you can derive every identity below from two's complement instead of remembering it, decide answers "bit by bit from the highest bit" with a proof, count a pairwise XOR/AND/OR sum by per-bit contributions, and enumerate submasks while explaining why it costs $3^n$.

## 1. First principles — why this works

**Numbers are vectors of bits, and the bitwise operators act on each coordinate independently.** `a & b`, `a | b`, `a ^ b` compute
bit $k$ of the result from bit $k$ of the inputs only. This *independence across bits* is the single most useful fact in the topic:
any quantity built from bitwise operators can be studied **one bit at a time**, and a sum like $\sum (a_i \oplus a_j)$ splits into
$\sum_k 2^k\cdot(\text{number of pairs that differ at bit } k)$.

**Arithmetic is not bitwise** — addition carries information to higher bits. The bridge between the two worlds is:

$$a + b = (a \oplus b) + 2(a \mathbin{\&} b),$$

because XOR is "addition without carry" and the carries are produced exactly where both bits are 1, shifted left by one.

**Numeric order is lexicographic order of bits, from the top.** Bit $k$ is worth $2^k > 2^{k-1}+\dots+2^0 = 2^k - 1$, i.e. more than all lower
bits together. So to maximise (or minimise) a quantity bit by bit, decide the **highest** bit first; once it is fixed favourably, no
choice of lower bits can undo that. This is the proof behind every "greedy from the highest bit" solution, binary tries for maximum XOR,
and the divide-and-conquer of Example 5.

**Two's complement.** A $w$-bit signed integer stores $x$ as $x \bmod 2^w$. Then $-x = \lnot x + 1$ (flip all bits and add one: $x + \lnot x$
is all ones $= -1$). Every lowest-bit trick follows from what $x - 1$ and $-x$ look like. Write $x = \underbrace{\cdots}_{P}\,1\,\underbrace{0\cdots0}_{t}$:

- $x - 1 = P\,0\,1\cdots1$ (the lowest 1 becomes 0, the zeros below become 1);
- $-x = \lnot x + 1 = \lnot P\,1\,0\cdots0$ (the prefix is flipped, the lowest 1 and the zeros survive).

Hence $x \mathbin{\&} (x-1) = P\,0\,0\cdots0$ (lowest set bit cleared) and $x \mathbin{\&} (-x) = 0\cdots0\,1\,0\cdots0$ (only the lowest set bit kept).

**Subsets are bitmasks.** A subset of $\{0,\dots,n-1\}$ is an integer in $[0, 2^n)$; union, intersection, difference and complement are `|`,
`&`, `& ~`, `^ full`. Enumerating all $2^n$ integers enumerates all subsets, in an order where every subset comes after its proper
submasks — exactly the order subset DPs need ([bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md)).

## 2. Formulas, definitions and identities

**Single-bit operations** ($k$ is a bit index; use `1LL << k` / `1L << k` when $k \ge 31$):

| Goal | Expression | Why |
|---|---|---|
| test bit $k$ | `(x >> k) & 1` | shift bit $k$ to position 0 |
| set / clear / toggle bit $k$ | `x \| (1<<k)`, `x & ~(1<<k)`, `x ^ (1<<k)` | per-bit truth tables |
| lowest set bit (as a value) | `x & -x` | two's complement, §1 |
| clear lowest set bit | `x & (x - 1)` | §1 |
| set lowest clear bit | `x \| (x + 1)` | $x+1$ turns the lowest 0 into 1 and the 1s below into 0 |
| $x > 0$ is a power of two | `(x & (x - 1)) == 0` | exactly one set bit |
| lowest $k$ bits | `x & ((1 << k) - 1)` | mask of $k$ ones |
| index of highest set bit ($x>0$) | `63 - __builtin_clzll(x)`, `std::bit_width(x) - 1`, `63 - Long.numberOfLeadingZeros(x)` | count leading zeros |
| index of lowest set bit ($x>0$) | `__builtin_ctzll(x)`, `std::countr_zero(x)`, `Long.numberOfTrailingZeros(x)` | count trailing zeros |
| number of set bits | `__builtin_popcountll(x)`, `std::popcount(x)`, `Long.bitCount(x)` | |

**XOR algebra.** XOR is addition in $\mathbb{F}_2$ on each bit: commutative, associative, $x\oplus x = 0$, $x\oplus 0 = x$, so
$a\oplus b = c \iff a = b\oplus c$. Prefix XORs work like prefix sums: with $P_i = a_1\oplus\dots\oplus a_i$, the XOR of $a_l..a_r$ is $P_r\oplus P_{l-1}$.

**XOR of $1..n$** (and of $0..n$):

$$1\oplus2\oplus\cdots\oplus n = \begin{cases} n & n\equiv 0 \pmod 4\\ 1 & n\equiv 1\\ n+1 & n\equiv 2\\ 0 & n\equiv 3\end{cases}$$

Proof: for even $m$, $m\oplus(m+1) = 1$; group $0,1 \mid 2,3 \mid \dots$ into pairs, each contributing 1. Four consecutive numbers starting at a
multiple of 4 XOR to 0, so only the last partial group matters, which gives the four cases.

**Sum identities.** $a+b = (a\oplus b) + 2(a\mathbin\& b) = (a\mathbin| b) + (a\mathbin\& b)$, and $a \oplus b = (a\mathbin|b) - (a\mathbin\&b)$.
Inequalities: $a\oplus b \le a + b$, $a\mathbin\& b \le \min(a,b)$, $a\mathbin|b \ge \max(a,b)$.

**Pairwise sums by per-bit counting.** Let $c_k$ be how many of the $n$ numbers have bit $k$ set. Over unordered pairs $i<j$:

$$\sum_{i<j}(a_i\oplus a_j) = \sum_k 2^k c_k(n-c_k),\qquad \sum_{i<j}(a_i\mathbin\&a_j) = \sum_k 2^k\binom{c_k}{2},\qquad \sum_{i<j}(a_i\mathbin|a_j) = \sum_k 2^k\left[\binom n2 - \binom{n-c_k}2\right].$$

Each follows from bit independence: a pair contributes $2^k$ at bit $k$ iff its two bits are (different / both 1 / not both 0).
The same idea counts *subarray* XOR sums: bit $k$ of the XOR of $a_l..a_r$ is 1 iff the prefix XORs $P_{l-1}$ and $P_r$ differ at bit $k$.

**Count of set bits in $[0, n]$ at position $k$.** The pattern of bit $k$ repeats with period $2^{k+1}$ ($2^k$ zeros then $2^k$ ones), so

$$\#\{0\le x\le n : \text{bit } k \text{ of } x = 1\} = \left\lfloor\frac{n+1}{2^{k+1}}\right\rfloor 2^k + \max\!\left(0,\ (n+1)\bmod 2^{k+1} - 2^k\right).$$

**Submask enumeration.** `for (s = m; s > 0; s = (s - 1) & m)` visits every non-empty submask of $m$ in decreasing order:
$s-1$ clears the lowest set bit of $s$ and sets all bits below it, and `& m` keeps only bits of $m$ — which is the largest submask of $m$ below $s$.
Over all $m \in [0, 2^n)$ the total number of steps is

$$\sum_{m}2^{\mathrm{popcount}(m)} = \sum_{k=0}^{n}\binom nk 2^k = (1+2)^n = 3^n$$

by the binomial theorem — equivalently, each element is independently "not in $m$", "in $m$ but not in $s$", or "in both". $3^{15}\approx1.4\cdot10^7$,
$3^{18}\approx3.9\cdot10^8$.

**Supermasks** of $m$ within $n$ bits: `for (s = m; s < (1 << n); s = (s + 1) | m)`.

**Next mask with the same popcount** (Gosper's hack), to iterate all $\binom nk$ subsets of size $k$ in increasing order:
`c = x & -x; r = x + c; x = (((r ^ x) >> 2) / c) | r;` — adding the lowest set bit $c$ carries the lowest block of ones one step left; the
bits that "fell off" are shifted back down to the bottom.

**Gray code.** $g(i) = i \oplus (i \gg 1)$; consecutive values differ in exactly one bit (going from $i$ to $i+1$ flips a block of low bits
$0 1\cdots1 \to 1 0\cdots0$; after XOR with the shifted copy only the top bit of that block survives). Inverse: $i = g \oplus (g\gg1)\oplus(g\gg2)\oplus\cdots$ (prefix XOR of the bits from the top).

**Maximum XOR of two numbers in $[l, r]$** with $l<r$: let $k$ be the highest bit where $l$ and $r$ differ; the answer is $2^{k+1}-1$ (Example 4).

## 3. Implementation (C++ and Java)

```cpp
// Every identity of §2 as a named one-liner. Use unsigned/64-bit types for the builtins.
inline bool testBit(ll x, int k) { return (x >> k) & 1; }
inline ll lowbit(ll x) { return x & -x; }
inline int highBit(ull x) { return 63 - __builtin_clzll(x); }    // x > 0; C++20: std::bit_width(x) - 1
inline int lowBitIndex(ull x) { return __builtin_ctzll(x); }     // x > 0; C++20: std::countr_zero(x)
inline int popcnt(ull x) { return __builtin_popcountll(x); }     // NOT __builtin_popcount: that takes 32-bit unsigned
inline bool isPow2(ll x) { return x > 0 && (x & (x - 1)) == 0; }
inline ll xorUpTo(ll n) {                                          // 0 ^ 1 ^ ... ^ n
    switch (n & 3) { case 0: return n; case 1: return 1; case 2: return n + 1; default: return 0; }
}
inline ll gray(ll i) { return i ^ (i >> 1); }
inline ll grayInverse(ll g) { for (int s = 1; s < 64; s <<= 1) g ^= g >> s; return g; }

// number of x in [0, n] with bit k set (n >= 0)
inline ll countBitUpTo(ll n, int k) {
    ll period = 1LL << (k + 1), half = 1LL << k;
    return (n + 1) / period * half + max(0LL, (n + 1) % period - half);
}

void enumerationDemo(int n, int m) {
    for (int s = m; s > 0; s = (s - 1) & m) { /* every non-empty submask of m */ }
    for (int s = m; s < (1 << n); s = (s + 1) | m) { /* every supermask of m inside n bits */ }
    for (int k = 0; k < n; k++) if (m >> k & 1) { /* every set bit of m */ }
    for (int x = m; x; x &= x - 1) { int k = __builtin_ctz(x); (void)k; /* set bits, lowest first, O(popcount) */ }
    int k = 3;
    if (k <= n)
        for (int x = (1 << k) - 1; x < (1 << n); ) {   // all k-subsets in increasing order (Gosper's hack)
            int c = x & -x, r = x + c;
            x = (((r ^ x) >> 2) / c) | r;
        }
}
```

```java
static boolean testBit(long x, int k) { return ((x >> k) & 1) == 1; }
static long lowbit(long x) { return x & -x; }
static int highBit(long x) { return 63 - Long.numberOfLeadingZeros(x); }   // x > 0
static int lowBitIndex(long x) { return Long.numberOfTrailingZeros(x); }  // x > 0
static int popcnt(long x) { return Long.bitCount(x); }
static boolean isPow2(long x) { return x > 0 && (x & (x - 1)) == 0; }
static long xorUpTo(long n) {
    switch ((int) (n & 3)) { case 0: return n; case 1: return 1; case 2: return n + 1; default: return 0; }
}
static long gray(long i) { return i ^ (i >>> 1); }
static long grayInverse(long g) { for (int s = 1; s < 64; s <<= 1) g ^= g >>> s; return g; }

static long countBitUpTo(long n, int k) {
    long period = 1L << (k + 1), half = 1L << k;
    return (n + 1) / period * half + Math.max(0L, (n + 1) % period - half);
}

static void enumerationDemo(int n, int m) {
    for (int s = m; s > 0; s = (s - 1) & m) { /* every non-empty submask of m */ }
    for (int s = m; s < (1 << n); s = (s + 1) | m) { /* every supermask of m */ }
    for (int x = m; x != 0; x &= x - 1) { int k = Integer.numberOfTrailingZeros(x); }
    int k = 3;
    if (k <= n)
        for (int x = (1 << k) - 1; x < (1 << n); ) {
            int c = x & -x, r = x + c;
            x = (((r ^ x) >> 2) / c) | r;
        }
}
```

**C++20 `<bit>` and Java equivalents** (the `std::` functions require an *unsigned* argument):

| C++ builtin | C++20 `<bit>` | Java (`Integer`/`Long` static methods) |
|---|---|---|
| `__builtin_popcount(u)`, `__builtin_popcountll(ull)` | `std::popcount(x)` | `bitCount(x)` |
| `__builtin_ctz(u)` (UB for 0) | `std::countr_zero(x)` (defined for 0) | `numberOfTrailingZeros(x)` (32/64 for 0) |
| `__builtin_clz(u)` (UB for 0) | `std::countl_zero(x)` | `numberOfLeadingZeros(x)` |
| `31 - __builtin_clz(u)` | `std::bit_width(x) - 1` | `31 - numberOfLeadingZeros(x)` |
| `1u << (31 - __builtin_clz(u))` | `std::bit_floor(x)` | `highestOneBit(x)` |
| — | `std::bit_ceil(x)` | — (compute from `highestOneBit`) |
| — | `std::has_single_bit(x)` | `bitCount(x) == 1` |
| — | `std::rotl`, `std::rotr` | `rotateLeft`, `rotateRight`, `reverse`, `reverseBytes` |

A full program that checks the identities of §2 by brute force (also a good template for testing your own bit formulas):

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    int n;
    cin >> n;                                   // check every identity for 0 <= x, y <= n
    bool ok = true;
    ll acc = 0;
    for (ll x = 0; x <= n; x++) {
        acc ^= x;
        ll f = (x & 3) == 0 ? x : (x & 3) == 1 ? 1 : (x & 3) == 2 ? x + 1 : 0;
        ok &= acc == f;                                                 // XOR 0..x
        if (x > 0) ok &= (x & -x) == (1LL << __builtin_ctzll(x));       // lowbit
        ll g = x ^ (x >> 1), inv = g;
        for (int s = 1; s < 64; s <<= 1) inv ^= inv >> s;
        ok &= inv == x;                                                 // Gray inverse
        if (x > 0) ok &= __builtin_popcountll(g ^ ((x - 1) ^ ((x - 1) >> 1))) == 1;  // Gray step
        for (ll y = 0; y <= n; y++) ok &= x + y == (x ^ y) + 2 * (x & y);
    }
    ll submaskSteps = 0;
    for (int m = 0; m < (1 << 10); m++) for (int s = m; ; s = (s - 1) & m) { submaskSteps++; if (s == 0) break; }
    ok &= submaskSteps == 59049;                                        // 3^10
    cout << (ok ? "all identities hold" : "MISMATCH") << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        boolean ok = true;
        long acc = 0;
        for (long x = 0; x <= n; x++) {
            acc ^= x;
            long f = (x & 3) == 0 ? x : (x & 3) == 1 ? 1 : (x & 3) == 2 ? x + 1 : 0;
            ok &= acc == f;
            if (x > 0) ok &= (x & -x) == (1L << Long.numberOfTrailingZeros(x));
            long g = x ^ (x >>> 1), inv = g;
            for (int s = 1; s < 64; s <<= 1) inv ^= inv >>> s;
            ok &= inv == x;
            if (x > 0) ok &= Long.bitCount(g ^ ((x - 1) ^ ((x - 1) >>> 1))) == 1;
            for (long y = 0; y <= n; y++) ok &= x + y == (x ^ y) + 2 * (x & y);
        }
        long submaskSteps = 0;
        for (int m = 0; m < (1 << 10); m++) for (int s = m; ; s = (s - 1) & m) { submaskSteps++; if (s == 0) break; }
        ok &= submaskSteps == 59049;
        System.out.println(ok ? "all identities hold" : "MISMATCH");
    }
}
```

<!-- test
in:
300
out:
all identities hold
-->

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| a sum over all pairs/subarrays of `^`, `&`, `\|` | split by bit, count contributions $2^k\cdot(\dots)$ |
| "minimise/maximise the value of an expression built with bitwise ops" | decide bits from the highest; check feasibility of the prefix so far |
| maximum XOR of a pair / with a query value | binary trie ([trie](../11-Strings/05-trie-and-binary-trie.md)) or highest-differing-bit reasoning |
| XOR of a range, "find a segment with XOR $= x$" | prefix XORs + hashing/counting, like prefix sums |
| $n \le 20$ objects, "choose a subset" | iterate masks; $n\le 15$–$18$ with "subset of a subset" → $3^n$ submasks |
| condition like $a \mathbin\& b \ge a\oplus b$, or comparing $a+b$ with $a\oplus b$ | compare highest set bits; use $a+b = (a\oplus b)+2(a\mathbin\&b)$ |
| the answer is a small bitmask ($< 2^9$, $< 2^{10}$) | try every candidate answer and check it (Example 3) |
| "linearly independent" XOR, "maximum XOR subset" | XOR basis ([Gaussian elimination & XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)) |
| sums over all submasks/supermasks for every mask | SOS DP ([SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md)) |

Often confused: XOR is *not* monotone (`a < b` says nothing about `a ^ x` vs `b ^ x`), whereas `&` and `|` are monotone in the subset order:
adding elements to an AND can only clear bits, to an OR only set bits — the basis of "at most 30–60 distinct prefix ANDs/ORs".

## 5. Worked examples (graded)

### Example 1 — Rock and Lever  ·  ★ 1200

- **Source:** [CF 1420B · Rock and Lever](https://codeforces.com/problemset/problem/1420/B) — 1200
- **Difficulty:** 1200
- **Problem:** Count pairs $i<j$ with $a_i \mathbin\& a_j \ge a_i \oplus a_j$, for $n\le10^5$ positive integers per test ($\sum n\le10^5$).
- **Thinking from first principles:** try small cases: $(2,3)$: $2 \ge 1$ yes; $(1,2)$: $0 \ge 3$ no; $(4,7)$: $4\ge3$ yes. The pattern is about the
  top bits. Compare the two numbers' highest set bits $h_i, h_j$. If $h_i = h_j = h$: bit $h$ is 1 in the AND and 0 in the XOR, and
  all higher bits are 0 in both, so AND $>$ XOR (numeric order is decided by the highest differing bit). If $h_i > h_j$: bit $h_i$ is 1 in the
  XOR, 0 in the AND, so XOR $>$ AND. The condition is exactly "same highest bit".

<details><summary>Solution</summary>

Bucket numbers by highest set bit and add $\binom{c}{2}$ per bucket (use 64-bit: up to $\approx 5\cdot10^9$ pairs). $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        int n;
        cin >> n;
        long long cnt[32] = {};
        for (int i = 0; i < n; i++) {
            unsigned x;
            cin >> x;
            cnt[31 - __builtin_clz(x)]++;          // x >= 1, so clz is defined
        }
        long long pairs = 0;
        for (long long c : cnt) pairs += c * (c - 1) / 2;
        cout << pairs << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt();
            long[] cnt = new long[32];
            for (int i = 0; i < n; i++) cnt[31 - Integer.numberOfLeadingZeros(in.nextInt())]++;
            long pairs = 0;
            for (long c : cnt) pairs += c * (c - 1) / 2;
            out.println(pairs);
        }
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
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 - (c - '0'); c = read(); }
            return neg ? r : -r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
4
3
1 2 3
4
4 5 6 7
1
1
5
1 1 1 1 1
out:
1
6
0
10
-->
<!-- test
in:
1
4
1000000000 536870912 1073741823 2
out:
3
-->

### Example 2 — Xor Sum 4  ·  ★ AtCoder diff≈1205

- **Source:** [AtCoder ABC147 D · Xor Sum 4](https://atcoder.jp/contests/abc147/tasks/abc147_d) — diff≈1205
- **Difficulty:** ≈1400 (est.; AtCoder Problems estimate 1205 on AtCoder's scale)
- **Problem:** $N \le 3\cdot10^5$ numbers $0\le A_i<2^{60}$. Output $\sum_{i<j}(A_i\oplus A_j) \bmod (10^9+7)$.
- **Thinking from first principles:** $\binom N2\approx4.5\cdot10^{10}$ pairs — too many. Bit independence: the pair contributes $2^k$ at bit $k$
  exactly when its two bits differ. With $c_k$ ones at bit $k$ there are $c_k(N-c_k)$ such pairs. Sixty bits × $N$ numbers to count, then
  sixty multiplications.

<details><summary>Solution</summary>

Answer $=\sum_{k<60} (2^k \bmod p)\cdot\big(c_k(N-c_k) \bmod p\big) \bmod p$. Overflow care: $c_k(N-c_k)\le 2.25\cdot10^{10}$ fits in 64 bits;
reduce it mod $p$ before multiplying by $2^k \bmod p$ so the product stays below $p^2 < 1.1\cdot10^{18}$. $O(60N)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const long long MOD = 1'000'000'007;
    int n;
    cin >> n;
    vector<long long> cnt(60, 0);
    for (int i = 0; i < n; i++) {
        unsigned long long a;
        cin >> a;
        for (int k = 0; k < 60; k++) cnt[k] += (a >> k) & 1;
    }
    long long ans = 0;
    for (int k = 0; k < 60; k++) {
        long long pairs = cnt[k] * (n - cnt[k]) % MOD;
        long long w = (1LL << k) % MOD;
        ans = (ans + pairs * w) % MOD;
    }
    cout << ans << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        final long MOD = 1_000_000_007L;
        int n = in.nextInt();
        long[] cnt = new long[60];
        for (int i = 0; i < n; i++) {
            long a = in.nextLong();
            for (int k = 0; k < 60; k++) cnt[k] += (a >>> k) & 1L;
        }
        long ans = 0;
        for (int k = 0; k < 60; k++) {
            long pairs = cnt[k] * (n - cnt[k]) % MOD;
            long w = (1L << k) % MOD;
            ans = (ans + pairs * w) % MOD;
        }
        System.out.println(ans);
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
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 - (c - '0'); c = read(); }
            return neg ? r : -r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
3
1 2 3
out:
6
-->
<!-- test
in:
2
1152921504606846975 0
out:
536396503
-->
<!-- test
in:
6
589016108321111109 826726605746716825 574276327398429556 119565462741922389 361674531236047419 857297115108020470
out:
719498446
-->
<!-- test
in:
4
5 5 5 5
out:
0
-->

### Example 3 — Boboniu and Bit Operations  ·  ★ 1600

- **Source:** [CF 1395C · Boboniu and Bit Operations](https://codeforces.com/problemset/problem/1395/C) — 1600
- **Difficulty:** 1600
- **Problem:** Arrays $a$ ($n\le200$) and $b$ ($m\le200$) of values $<2^9$. For each $i$ choose any $j$ and let $c_i = a_i\mathbin\&b_j$. Minimise
  $c_1\mathbin|c_2\mathbin|\cdots\mathbin|c_n$.
- **Thinking from first principles:** the greedy "pick the smallest $c_i$ for each $i$" fails, because OR rewards *sharing* bits: if
  position 1 can produce $\{4, 5\}$ and position 2 can produce $\{2, 5\}$, the minima give $4\mid2 = 6$, while $5\mid5 = 5$ is better.
  Change viewpoint: the answer is a 9-bit number, so there are only **512 candidate answers**. A candidate $A$ is achievable iff every $i$ has some $j$ with
  $(a_i\mathbin\&b_j)$ a submask of $A$, i.e. $((a_i\mathbin\&b_j)\mathbin|A) = A$ — and if each $c_i\subseteq A$ then the OR is $\subseteq A$, so its
  value is $\le A$. The smallest feasible $A$ is the answer.

<details><summary>Solution</summary>

Try $A = 0, 1, \dots, 511$ and return the first feasible one. $O(512\cdot n\cdot m)\approx 2\cdot10^7$. The smallest feasible $A$ is optimal: the
true optimum $A^\*$ is itself feasible (use the optimal choices), so the first feasible value found is $\le A^\*$, and any feasible $A$ yields an OR $\le A$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<int> a(n), b(m);
    for (auto& x : a) cin >> x;
    for (auto& x : b) cin >> x;
    for (int A = 0; A < 512; A++) {
        bool ok = true;
        for (int i = 0; i < n && ok; i++) {
            bool found = false;
            for (int j = 0; j < m && !found; j++) found = ((a[i] & b[j]) | A) == A;
            ok = found;
        }
        if (ok) { cout << A << '\n'; return 0; }
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        int[] a = new int[n], b = new int[m];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        for (int j = 0; j < m; j++) b[j] = in.nextInt();
        for (int A = 0; A < 512; A++) {
            boolean ok = true;
            for (int i = 0; i < n && ok; i++) {
                boolean found = false;
                for (int j = 0; j < m && !found; j++) found = ((a[i] & b[j]) | A) == A;
                ok = found;
            }
            if (ok) { System.out.println(A); return; }
        }
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
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 - (c - '0'); c = read(); }
            return neg ? r : -r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
2 3
7 8
1 2 12
out:
1
-->
<!-- test
in:
2 2
0 511
0 0
out:
0
-->
<!-- test
in:
2 2
1 2
3 3
out:
3
-->
<!-- test
in:
1 1
5
3
out:
1
-->

### Example 4 — Little Girl and Maximum XOR  ·  ★ 1700

- **Source:** [CF 276D · Little Girl and Maximum XOR](https://codeforces.com/problemset/problem/276/D) — 1700
- **Difficulty:** 1700
- **Problem:** Given $1\le l\le r\le10^{18}$, find $\max\{a\oplus b : l\le a\le b\le r\}$.
- **Thinking from first principles:** brute force on small ranges ($l=5,r=6$: $5\oplus6=3$; $l=8,r=16$: $15\oplus16=31$) suggests "all ones".
  Why? Write $l$ and $r$ in binary and find the highest bit $k$ where they differ. Every number in $[l,r]$ shares the bits above $k$ (they
  are a common prefix of the two endpoints, and everything between has the same prefix), so any XOR has zeros above $k$: the answer is at most
  $2^{k+1}-1$. It is achieved by $a = \text{prefix}\,0\,11\cdots1$ and $b = \text{prefix}\,1\,00\cdots0$: since $l$ has 0 at bit $k$, $l\le a$; since
  $r$ has 1 at bit $k$, $b\le r$; and $a<b$.

<details><summary>Solution</summary>

If $l=r$ the answer is 0; otherwise $2^{k+1}-1$ with $k$ the highest set bit of $l\oplus r$. $O(1)$. Note $r<2^{60}$, so the answer fits in a signed 64-bit integer.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    unsigned long long l, r;
    cin >> l >> r;
    if (l == r) { cout << 0 << '\n'; return 0; }
    int k = 63 - __builtin_clzll(l ^ r);
    cout << ((1ULL << (k + 1)) - 1) << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        long l = Long.parseLong(st.nextToken()), r = Long.parseLong(st.nextToken());
        if (l == r) { System.out.println(0); return; }
        int k = 63 - Long.numberOfLeadingZeros(l ^ r);
        System.out.println((1L << (k + 1)) - 1);
    }
}
```

</details>

<!-- test
in:
1 2
out:
3
-->
<!-- test
in:
8 16
out:
31
-->
<!-- test
in:
5 5
out:
0
-->
<!-- test
in:
1 1000000000000000000
out:
1152921504606846975
-->

### Example 5 — Dr. Evil Underscores  ·  ★ 1900

- **Source:** [CF 1285D · Dr. Evil Underscores](https://codeforces.com/problemset/problem/1285/D) — 1900
- **Difficulty:** 1900
- **Problem:** Given $n\le10^5$ numbers $0\le a_i<2^{30}$, choose $X$ to minimise $\max_i (a_i\oplus X)$. Output that minimum.
- **Thinking from first principles:** decide $X$ from the top bit (numeric order is decided there first). Look at bit 29 of all numbers.
  If they all agree, set $X$'s bit equal to theirs: every $a_i\oplus X$ gets a 0 there — clearly optimal, recurse on bit 28. If they disagree,
  whatever $X$'s bit is, some $a_i\oplus X$ has a 1 at bit 29, so the maximum is at least $2^{29}$ — and that cost is paid by exactly one side:
  choosing $X$'s bit = 0 makes the "ones" group the dangerous one, and the maximum becomes $2^{29} + (\text{best for the ones group alone})$;
  symmetrically for 1. So $f(S, k) = f(S, k-1)$ if all of $S$ agree at bit $k$, else $2^k + \min(f(S_0,k-1), f(S_1,k-1))$. Every number sits in
  exactly one subproblem per level: $O(30n)$ total, a binary-trie walk in disguise.

<details><summary>Solution</summary>

Sort the array: within a range that shares all bits above $k$, the numbers with bit $k = 0$ come first, so each subproblem is a contiguous
range and no lists are copied. Recursion depth $\le 31$. $O(n\log n + 30n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> a;

// a[lo..hi) agree on all bits above k
long long solve(int lo, int hi, int k) {
    if (k < 0 || hi - lo <= 1) return 0;
    int mid = lo;
    while (mid < hi && !((a[mid] >> k) & 1)) mid++;   // first element with bit k set
    if (mid == lo || mid == hi) return solve(lo, hi, k - 1);
    return (1LL << k) + min(solve(lo, mid, k - 1), solve(mid, hi, k - 1));
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    a.resize(n);
    for (auto& x : a) cin >> x;
    sort(a.begin(), a.end());
    cout << solve(0, n, 29) << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int[] a;

    static long solve(int lo, int hi, int k) {
        if (k < 0 || hi - lo <= 1) return 0;
        int mid = lo;
        while (mid < hi && ((a[mid] >> k) & 1) == 0) mid++;
        if (mid == lo || mid == hi) return solve(lo, hi, k - 1);
        return (1L << k) + Math.min(solve(lo, mid, k - 1), solve(mid, hi, k - 1));
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        Random rnd = new Random();
        for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = a[i]; a[i] = a[j]; a[j] = t; }
        Arrays.sort(a);
        System.out.println(solve(0, n, 29));
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
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 - (c - '0'); c = read(); }
            return neg ? r : -r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
3
1 2 3
out:
2
-->
<!-- test
in:
2
1 5
out:
4
-->
<!-- test
in:
1
7
out:
0
-->
<!-- test
in:
4
0 0 0 0
out:
0
-->
<!-- test
in:
2
0 1073741823
out:
536870912
-->

## 6. Tricks, pitfalls and things to remember

1. **`1 << k` is an `int`.** For $k\ge31$ use `1LL << k` (C++) / `1L << k` (Java). In C++ shifting by $\ge$ the bit width is undefined
   behaviour; in **Java the shift count is taken mod 32 (mod 64 for `long`)**, so `1 << 32 == 1` and `1L << 64 == 1` — silently wrong, no crash.
2. **`__builtin_popcount(x)` with a `long long` argument** silently truncates to 32 bits. Use `__builtin_popcountll`; same for `clz`/`ctz`.
   `__builtin_clz(0)` and `__builtin_ctz(0)` are undefined.
3. **Operator precedence:** `x & 1 == 0` parses as `x & (1 == 0)`. Comparison binds tighter than `&`, `^`, `|` in both languages — always
   parenthesise: `(x & 1) == 0`. Likewise `1 << k - 1` is `1 << (k - 1)`.
4. **Java `>>` vs `>>>`:** `>>` copies the sign bit (arithmetic), `>>>` shifts in zeros. For hashing, Gray codes and unsigned reasoning on
   `long`, use `>>>`. In C++, right-shifting a negative signed value is arithmetic since C++20; use unsigned types when you mean bits.
5. **Java `byte` is signed:** `b & 0xff` before using it as an unsigned value or an index.
6. **Highest bit of 0** does not exist: guard `x > 0` before `clz`/`numberOfLeadingZeros`-based formulas.
7. **XOR is not order-preserving:** sorting by `a ^ x` requires recomputing; tries, not binary search, answer "max XOR with $x$".
8. **Prefix AND/OR has few distinct values:** moving the right end, the AND of $a_l..a_r$ over all $l$ takes at most $\log_2(\max a)+1$ distinct
   values (each change clears at least one bit) — the key to many "count subarrays with OR $\ge k$" problems.
9. **`vector<bool>` / `bitset`** are bit containers: `bitset<N>` needs a compile-time $N$; for runtime sizes use `vector<ull>` words
   ([bitset optimisation](../16-IGM-Frontier/05-bitset-optimization.md)).
10. **Signed overflow in `x & -x` for `INT_MIN`/`LLONG_MIN`** is undefined in C++ ($-$ overflows); use unsigned if that value can occur.
11. **Mask loops over $2^n$ with `int`:** `for (int m = 0; m < (1 << n); m++)` is fine for $n\le30$; with $n=31$ use `long long`/unsigned.

## 7. Going further (toward 2400–2600+)

- **XOR basis / linear algebra over $\mathbb F_2$:** maximum subset XOR, counting representable values, $k$-th smallest subset XOR —
  [XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md).
- **SOS DP** (sum over subsets in $O(n2^n)$ instead of $3^n$) and subset convolution —
  [SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md).
- **Binary trie** for max/min XOR queries and "count pairs with XOR $<k$" — [binary trie](../11-Strings/05-trie-and-binary-trie.md).
- **Bitset-accelerated DP and graph algorithms** — [bitset optimisation](../16-IGM-Frontier/05-bitset-optimization.md).
- **Bitmask DP** over subsets, Hamiltonian paths, broken profile — [bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md),
  [broken profile](../06-Dynamic-Programming/11-broken-profile-dp.md).
- **Walsh–Hadamard transform** (XOR convolution) — [FFT & NTT](../15-Advanced-Math/03-fft-and-ntt.md).

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 1421A · XORwice](https://codeforces.com/problemset/problem/1421/A) — 800
- [ ] [CF 579A · Raising Bacteria](https://codeforces.com/problemset/problem/579/A) — 1000
- [ ] [CF 1567B · MEXor Mixup](https://codeforces.com/problemset/problem/1567/B) — 1000
- [ ] [CF 1420B · Rock and Lever](https://codeforces.com/problemset/problem/1420/B) — 1200
- [ ] [CF 1514B · AND 0, Sum Big](https://codeforces.com/problemset/problem/1514/B) — 1200
- [ ] [CF 1669H · Maximal AND](https://codeforces.com/problemset/problem/1669/H) — 1300
- [ ] [CSES 2205 · Gray Code](https://cses.fi/problemset/task/2205)
- [ ] [AtCoder ABC147 D · Xor Sum 4](https://atcoder.jp/contests/abc147/tasks/abc147_d) — diff≈1205

**1400–1700**
- [ ] [CF 1338A · Powered Addition](https://codeforces.com/problemset/problem/1338/A) — 1500
- [ ] [CF 1516B · AGAGA XOOORRR](https://codeforces.com/problemset/problem/1516/B) — 1500
- [ ] [CF 1742G · Orray](https://codeforces.com/problemset/problem/1742/G) — 1500
- [ ] [CF 1722G · Even-Odd XOR](https://codeforces.com/problemset/problem/1722/G) — 1500
- [ ] [CF 1395C · Boboniu and Bit Operations](https://codeforces.com/problemset/problem/1395/C) — 1600
- [ ] [CSES 1146 · Counting Bits](https://cses.fi/problemset/task/1146)

**1700–1900**
- [ ] [CF 276D · Little Girl and Maximum XOR](https://codeforces.com/problemset/problem/276/D) — 1700
- [ ] [CF 484A · Bits](https://codeforces.com/problemset/problem/484/A) — 1700
- [ ] [CF 1325D · Ehab the Xorcist](https://codeforces.com/problemset/problem/1325/D) — 1700
- [ ] [CF 1368D · AND, OR and square sum](https://codeforces.com/problemset/problem/1368/D) — 1700
- [ ] [CF 1554B · Cobb](https://codeforces.com/problemset/problem/1554/B) — 1700
- [ ] [CF 706D · Vasiliy's Multiset](https://codeforces.com/problemset/problem/706/D) — 1800
- [ ] [CSES 1655 · Maximum Xor Subarray](https://cses.fi/problemset/task/1655)
- [ ] [CF 1285D · Dr. Evil Underscores](https://codeforces.com/problemset/problem/1285/D) — 1900

**1900+**
- [ ] [CF 1288D · Minimax Problem](https://codeforces.com/problemset/problem/1288/D) — 2000
- [ ] [CF 1006F · Xor-Paths](https://codeforces.com/problemset/problem/1006/F) — 2100
- [ ] [CSES 1654 · SOS Bit Problem](https://cses.fi/problemset/task/1654)
- [ ] [CF 165E · Compatible Numbers](https://codeforces.com/problemset/problem/165/E) — 2200

## 9. LeetCode / FAANG cross-reference

Bit questions are a recurring "medium" interview category; interviewers want the identity *and* a one-line justification.

- [LC 136 · Single Number](https://leetcode.com/problems/single-number/) — Easy — XOR cancels pairs.
- [LC 137 · Single Number II](https://leetcode.com/problems/single-number-ii/) — Medium — count each bit mod 3.
- [LC 260 · Single Number III](https://leetcode.com/problems/single-number-iii/) — Medium — split by the lowest set bit of the total XOR (`x & -x`).
- [LC 191 · Number of 1 Bits](https://leetcode.com/problems/number-of-1-bits/) — Easy — `x &= x - 1` loop.
- [LC 338 · Counting Bits](https://leetcode.com/problems/counting-bits/) — Easy — `bits[i] = bits[i >> 1] + (i & 1)`.
- [LC 190 · Reverse Bits](https://leetcode.com/problems/reverse-bits/) — Easy — Java `>>>`, `Integer.reverse`.
- [LC 268 · Missing Number](https://leetcode.com/problems/missing-number/) — Easy — XOR of indices and values.
- [LC 371 · Sum of Two Integers](https://leetcode.com/problems/sum-of-two-integers/) — Medium — $a+b=(a\oplus b)+2(a\mathbin\&b)$ iterated.
- [LC 201 · Bitwise AND of Numbers Range](https://leetcode.com/problems/bitwise-and-of-numbers-range/) — Medium — common binary prefix of $l$ and $r$.
- [LC 231 · Power of Two](https://leetcode.com/problems/power-of-two/) — Easy — `x > 0 && (x & (x-1)) == 0`.
- [LC 461 · Hamming Distance](https://leetcode.com/problems/hamming-distance/) — Easy — popcount of XOR.
- [LC 477 · Total Hamming Distance](https://leetcode.com/problems/total-hamming-distance/) — Medium — per-bit $c_k(n-c_k)$, Example 2's idea.
- [LC 89 · Gray Code](https://leetcode.com/problems/gray-code/) — Medium — $i\oplus(i\gg1)$.
- [LC 421 · Maximum XOR of Two Numbers in an Array](https://leetcode.com/problems/maximum-xor-of-two-numbers-in-an-array/) — Medium — binary trie or bit-by-bit prefix sets.
- [LC 78 · Subsets](https://leetcode.com/problems/subsets/) — Medium — iterate masks $0..2^n-1$.
- [LC 1318 · Minimum Flips to Make a OR b Equal to c](https://leetcode.com/problems/minimum-flips-to-make-a-or-b-equal-to-c/) — Medium — per-bit case analysis.

## 10. Self-check

1. Derive `x & -x` and `x & (x - 1)` from two's complement.
2. What is $1\oplus2\oplus\cdots\oplus 10^{18}$?
3. Why does submask enumeration over all masks of $n$ bits cost $3^n$ and not $4^n$?
4. Write $\sum_{i<j}(a_i \mathbin| a_j)$ in terms of per-bit counts.
5. In Java, what are `1 << 35`, `-8 >> 1` and `-8 >>> 60`?
6. Why is "decide the highest bit first" a valid greedy for minimising/maximising?
7. For $l<r$, why can no pair in $[l,r]$ have an XOR with a 1 above the highest differing bit of $l$ and $r$?

<details><summary>Answers</summary>

1. With $x = P10\cdots0$: $x-1 = P01\cdots1$, so $x\mathbin\&(x-1) = P00\cdots0$; $-x = \lnot x+1 = \bar P10\cdots0$, so $x\mathbin\&(-x) = 0\cdots010\cdots0$.
2. $10^{18}\equiv 0 \pmod 4$, so the answer is $10^{18}$.
3. Each element has three states (not in $m$; in $m$ not in $s$; in both); the pair $(m,s)$ with $s\subseteq m$ never has "in $s$ but not in $m$".
4. $\sum_k 2^k\left[\binom n2-\binom{n-c_k}2\right]$: subtract the pairs where both bits are 0.
5. `1 << 35` is `1 << 3` $=8$ (count mod 32); `-8 >> 1` $=-4$; `-8 >>> 60` $=15$ (`-8` is an `int`, so the count is $60 \bmod 32 = 28$, leaving the top four bits of `0xFFFFFFF8`; `-8L >>> 60` is also 15).
6. Bit $k$ outweighs all lower bits combined ($2^k > 2^k-1$), so a better choice at bit $k$ beats any combination below it.
7. All numbers between $l$ and $r$ share the common prefix above that bit, so the prefix bits cancel in every XOR.

</details>
