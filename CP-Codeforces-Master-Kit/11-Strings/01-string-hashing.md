# String hashing (polynomial rolling hash)

> **Band:** 🔵 1500–2100 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md), [binary search on the answer](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md), [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md)
> **You can say you know this when:** you can write a randomised mod $2^{61}-1$ hash (C++ and Java) from memory, compare any two substrings or find their LCP in $O(\log n)$, and you can state the collision probability of your solution for the given constraints instead of hoping.

## 1. First principles — why this works

**The problem.** Many string problems reduce to "are these two substrings equal?" asked millions of times. Comparing character by character costs $O(L)$ per question. With $n = 2\cdot 10^5$ and $n \log n$ comparisons that is $10^{11}$ operations.

**The idea: a fingerprint.** Map every string to a number so that equal strings get equal numbers (always) and different strings get different numbers (almost always). Then a comparison is one integer comparison. The fingerprint must be

1. *cheap for every substring* — we cannot recompute it from scratch per query, and
2. *hard to fool* — the probability of two different strings sharing a fingerprint must be tiny, even for an adversarial test (Codeforces has hacks).

**Why a polynomial.** Read the string $s_0 s_1 \dots s_{n-1}$ as the digits of a number in base $B$, reduced modulo a prime $p$:

$$H(s) = \Big(\sum_{i=0}^{n-1} s_i\, B^{\,n-1-i}\Big) \bmod p .$$

This is Horner's rule: $H(s c) = H(s)\cdot B + c$. Write $h_i = H(s_0\dots s_{i-1})$ (prefix hashes). Shifting a number left by $k$ digits multiplies it by $B^k$, so the prefix of length $r$ equals the prefix of length $l$ shifted by $r-l$ digits plus the digits of $s[l..r)$:

$$h_r = h_l \cdot B^{\,r-l} + H(s[l..r)) \quad\Longrightarrow\quad H(s[l..r)) = h_r - h_l\cdot B^{\,r-l} \pmod p.$$

That is the whole trick: **prefix sums for strings**, where "subtract the prefix" needs a multiplication by a precomputed power. $O(n)$ preprocessing, $O(1)$ per substring.

**Why it is hard to fool (if $B$ is random).** Two strings $a \ne b$ of the same length $L$ collide iff $D(x) = \sum_i (a_i - b_i)\,x^{L-1-i} \equiv 0$ at $x = B$. $D$ is a non-zero polynomial of degree $< L$ over the field $\mathbb{Z}_p$, so it has at most $L-1$ roots. If $B$ is chosen **uniformly at random after the input is fixed**, then

$$\Pr[\text{collision}] \le \frac{L-1}{p}.$$

This is the Schwartz–Zippel bound for one variable, and it holds for *every* pair of strings, including ones a hacker designed. The randomness is in your base, not in the test. (Strings of different lengths also behave: their difference polynomial is non-zero as long as no character maps to 0 — see pitfall 2.)

**Why $p$ must be huge.** A solution performs $Q$ comparisons; by the union bound the failure probability is at most $Q(L-1)/p$. Practical estimate (collisions behave roughly like random values): about $Q/p$. With $p \approx 10^9$ and $Q = 10^7$ comparisons per test, you fail about once per 100 tests — and a problem with 100 tests will eventually catch you. Worse, when you put $m$ hashes into a set to count distinct values, *every pair* is a comparison: $\binom{m}{2}/p$ (the birthday paradox). With $m = 10^6$ and $p = 10^9$ a collision is essentially certain. Hence the modern default: **one hash modulo the Mersenne prime $p = 2^{61}-1$** ($\approx 2.3\cdot 10^{18}$), or two independent 31-bit primes in Java when you do not want 128-bit arithmetic.

**Why $2^{61}-1$ is fast.** Since $2^{61} \equiv 1 \pmod p$, a 122-bit product $x = x_{hi}\cdot 2^{61} + x_{lo}$ reduces to $x_{hi} + x_{lo}$ — one shift, one mask, one add and one conditional subtraction instead of a division.

**What not to do.** "Natural overflow" (mod $2^{64}$) is broken by the Thue–Morse string for *every* base. For odd $B$, the hash difference of $T_k$ and $\overline{T_k}$ (bits flipped, length $2^k$) is $\pm\prod_{j<k}(B^{2^j}-1)$, and $B^{2^j}-1$ is divisible by $2^{j+1}$, so the product is divisible by $2^{k(k+1)/2}$ — zero mod $2^{64}$ at the latest for $k = 11$ (length 2048). For even $B$ it is worse: $B^{64} \equiv 0$, so everything beyond the last 64 characters is ignored. A fixed public base with a fixed prime can be broken offline by birthday search or lattice reduction. Randomising the base at run time defeats both.

## 2. Formulas, definitions and identities

| Quantity | Formula | Cost |
|---|---|---|
| prefix hash | $h_0 = 0,\; h_{i+1} = h_i B + \mathrm{val}(s_i) \bmod p$ | $O(n)$ total |
| powers | $P_0 = 1,\; P_{i+1} = P_i B \bmod p$ | $O(n)$ total |
| substring $[l,r)$ | $H(l,r) = h_r - h_l P_{r-l} \bmod p$ | $O(1)$ |
| concatenation | $H(st) = H(s)\,B^{\lvert t\rvert} + H(t)$ | $O(1)$ |
| append / pop front (sliding window of length $m$) | $H \leftarrow H B + c_{\text{new}} - c_{\text{old}} B^{m}$ | $O(1)$ |
| reversed hash | $\overline{h}_{i} = H(s_{n-1}\dots s_{n-i})$, or the "suffix" form $g_{i+1} = g_i + s_i B^{i}$ | $O(n)$ |
| palindrome test of $s[l..r)$ | $H(s[l..r)) = H(\mathrm{rev}(s)[n-r..n-l))$ | $O(1)$ |
| LCP of positions $i, j$ | largest $k$ with $H(i,i+k)=H(j,j+k)$, binary search | $O(\log n)$ |
| lexicographic compare | LCP $k$, then compare $s_{i+k}$ and $s_{j+k}$ | $O(\log n)$ |

**Collision bounds** (random $B$, prime $p$, strings of length $\le L$):

- one comparison: $\Pr \le (L-1)/p$ (at most $L-1$ roots of a non-zero polynomial);
- $Q$ comparisons: $\Pr \le Q(L-1)/p$ (union bound);
- $m$ distinct hashes in a set (birthday): $\Pr[\text{some collision}] \approx 1 - e^{-m^2/(2p)} \approx m^2/(2p)$ for random-like values. Setting this to $1/2$ gives the familiar $m \approx 1.18\sqrt{p}$: about $3.7\cdot 10^{4}$ for $p = 10^9+7$, about $1.8\cdot 10^{9}$ for $2^{61}-1$;
- double hashing with independent random bases modulo $p_1, p_2$: per comparison $\Pr \le \frac{L-1}{p_1}\cdot\frac{L-1}{p_2}$ (independence), effectively a modulus of $p_1 p_2 \approx 10^{18}$.

**Mersenne reduction.** For $p = 2^{61}-1$ and $0 \le a, b < p$: $x = ab < 2^{122}$, write $x = q\cdot 2^{61} + r$ with $r < 2^{61}$. Then $x \equiv q + r \pmod p$ and $q + r < 2p$, so one conditional subtraction finishes. In Java, `Math.multiplyHigh(a, b)` gives the high 64 bits $x_{hi}$ and `a * b` the low 64 bits $x_{lo}$; then $r = x_{lo} \mathbin{\&} p$ and $q = (x_{hi} \ll 3) \mid (x_{lo} \ggg 61)$.

**Choosing parameters.** Base $B$ uniform in $[2^{20}, p-1]$ (anything larger than the alphabet works; random is what matters). Character values must be non-zero: use the byte value of the character (all printable characters are $\ge 32$), or `c - 'a' + 1`.

## 3. Implementation (C++ and Java)

### 3.1 Randomised mod $2^{61}-1$ hash with LCP and comparison

Driver: read $s$, then $q$ queries `a b c d` meaning substrings $s[a..b)$ and $s[c..d)$ (0-indexed, half-open). Print their LCP and `<`, `=` or `>`.

```cpp
#include <bits/stdc++.h>
using namespace std;
using u64 = unsigned long long;

struct Hash61 {
    static constexpr u64 M = (1ULL << 61) - 1;
    static u64 B;                                    // one random base per run (anti-hack)
    static u64 mul(u64 a, u64 b) {
        __uint128_t x = (__uint128_t)a * b;
        u64 r = (u64)(x & M) + (u64)(x >> 61);       // 2^61 == 1 (mod M)
        return r >= M ? r - M : r;
    }
    vector<u64> h, pw;                               // h[i] = hash of s[0..i)
    explicit Hash61(const string& s) : h(s.size() + 1, 0), pw(s.size() + 1, 1) {
        for (size_t i = 0; i < s.size(); i++) {
            h[i + 1] = mul(h[i], B) + (unsigned char)s[i];   // char values are >= 32, never 0
            if (h[i + 1] >= M) h[i + 1] -= M;
            pw[i + 1] = mul(pw[i], B);
        }
    }
    u64 get(int l, int r) const {                    // hash of s[l..r)
        u64 x = h[r] + M - mul(h[l], pw[r - l]);
        return x >= M ? x - M : x;
    }
};
u64 Hash61::B = [] {
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    return rng() % (Hash61::M - (1ULL << 20)) + (1ULL << 20);
}();

// longest common prefix of s[a..a+len) and s[c..c+len), by binary search on equal hashes
int lcp(const Hash61& H, int a, int c, int len) {
    int lo = 0, hi = len;
    while (lo < hi) {
        int mid = (lo + hi + 1) / 2;
        if (H.get(a, a + mid) == H.get(c, c + mid)) lo = mid; else hi = mid - 1;
    }
    return lo;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; int q;
    cin >> s >> q;
    Hash61 H(s);
    while (q--) {
        int a, b, c, d;
        cin >> a >> b >> c >> d;
        int k = lcp(H, a, c, min(b - a, d - c));
        char sign;
        if (k == b - a && k == d - c) sign = '=';
        else if (k == b - a) sign = '<';                    // first is a proper prefix of second
        else if (k == d - c) sign = '>';
        else sign = s[a + k] < s[c + k] ? '<' : '>';
        cout << k << ' ' << sign << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class Hash61 {
        static final long M = (1L << 61) - 1;
        static final long B = (new SplittableRandom(System.nanoTime()).nextLong() >>> 4) % (M - (1L << 20)) + (1L << 20);
        static long mul(long a, long b) {                 // a, b in [0, M)
            long hi = Math.multiplyHigh(a, b), lo = a * b;  // 128-bit product = hi:lo
            long r = (lo & M) + ((lo >>> 61) | (hi << 3));  // low 61 bits + (product >> 61)
            return r >= M ? r - M : r;
        }
        final long[] h, pw;
        Hash61(char[] s) {
            h = new long[s.length + 1]; pw = new long[s.length + 1]; pw[0] = 1;
            for (int i = 0; i < s.length; i++) {
                long x = mul(h[i], B) + s[i];
                h[i + 1] = x >= M ? x - M : x;
                pw[i + 1] = mul(pw[i], B);
            }
        }
        long get(int l, int r) {
            long x = h[r] - mul(h[l], pw[r - l]);
            return x < 0 ? x + M : x;
        }
    }

    static int lcp(Hash61 H, int a, int c, int len) {
        int lo = 0, hi = len;
        while (lo < hi) {
            int mid = (lo + hi + 1) >>> 1;
            if (H.get(a, a + mid) == H.get(c, c + mid)) lo = mid; else hi = mid - 1;
        }
        return lo;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] s = in.next().toCharArray();
        int q = in.nextInt();
        Hash61 H = new Hash61(s);
        while (q-- > 0) {
            int a = in.nextInt(), b = in.nextInt(), c = in.nextInt(), d = in.nextInt();
            int k = lcp(H, a, c, Math.min(b - a, d - c));
            char sign;
            if (k == b - a && k == d - c) sign = '=';
            else if (k == b - a) sign = '<';
            else if (k == d - c) sign = '>';
            else sign = s[a + k] < s[c + k] ? '<' : '>';
            out.println(k + " " + sign);
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
abacaba
5
0 3 4 7
0 7 1 7
0 2 4 7
2 5 6 7
1 4 5 7
out:
3 =
0 <
2 <
1 >
2 >
-->
<!-- test
in:
a
2
0 1 0 1
0 0 0 1
out:
1 =
0 <
-->

### 3.2 Double hashing with two 31-bit primes (no 128-bit arithmetic)

Use this when you want plain `long` arithmetic (every product is below $2^{60}$). The pair is packed into one `long` key so it can go into a sorted array or a hash set.

```cpp
struct DoubleHash {
    static constexpr long long M1 = 1'000'000'007LL, M2 = 998'244'353LL;
    static inline long long B1 = 0, B2 = 0;
    vector<long long> h1, h2, p1, p2;
    explicit DoubleHash(const string& s) {
        if (B1 == 0) {                                   // independent random bases, chosen once
            mt19937 rng(chrono::steady_clock::now().time_since_epoch().count());
            B1 = 256 + rng() % (M1 - 512); B2 = 256 + rng() % (M2 - 512);
        }
        int n = s.size();
        h1.assign(n + 1, 0); h2.assign(n + 1, 0); p1.assign(n + 1, 1); p2.assign(n + 1, 1);
        for (int i = 0; i < n; i++) {
            h1[i + 1] = (h1[i] * B1 + (unsigned char)s[i]) % M1;
            h2[i + 1] = (h2[i] * B2 + (unsigned char)s[i]) % M2;
            p1[i + 1] = p1[i] * B1 % M1;
            p2[i + 1] = p2[i] * B2 % M2;
        }
    }
    long long get(int l, int r) const {                  // both residues packed into one key
        long long a = (h1[r] - h1[l] * p1[r - l] % M1 + M1) % M1;
        long long b = (h2[r] - h2[l] * p2[r - l] % M2 + M2) % M2;
        return a << 32 | b;
    }
};
```

```java
static final class DoubleHash {
    static final long M1 = 1_000_000_007L, M2 = 998_244_353L;
    static final SplittableRandom RNG = new SplittableRandom(System.nanoTime());
    static final long B1 = 256 + RNG.nextLong(M1 - 512), B2 = 256 + RNG.nextLong(M2 - 512);
    final long[] h1, h2, p1, p2;
    DoubleHash(char[] s) {
        int n = s.length;
        h1 = new long[n + 1]; h2 = new long[n + 1]; p1 = new long[n + 1]; p2 = new long[n + 1];
        p1[0] = p2[0] = 1;
        for (int i = 0; i < n; i++) {
            h1[i + 1] = (h1[i] * B1 + s[i]) % M1;
            h2[i + 1] = (h2[i] * B2 + s[i]) % M2;
            p1[i + 1] = p1[i] * B1 % M1;
            p2[i + 1] = p2[i] * B2 % M2;
        }
    }
    long get(int l, int r) {                              // Java % keeps the sign: add M before %
        long a = (h1[r] - h1[l] * p1[r - l] % M1 + M1) % M1;
        long b = (h2[r] - h2[l] * p2[r - l] % M2 + M2) % M2;
        return a << 32 | b;
    }
}
```

## 4. Recognising the pattern

- **"Compare many substrings"**, "is $s[l_1..r_1]$ equal to $s[l_2..r_2]$", "how many distinct substrings of length $k$ / satisfying a property" with $n \le 5000$ (enumerate $O(n^2)$ substrings and hash them).
- **Monotone length questions** — "longest substring that appears twice / in all strings / satisfies P": if length $L$ works, so does $L-1$, so binary search $L$ and test with a set of window hashes. $O(n\log^2 n)$ or $O(n \log n)$ with a hash table.
- **LCP of two arbitrary positions / lexicographic comparison** of substrings in $O(\log n)$: the hash stands in for a suffix array when $n\log n$ is affordable ([suffix array & LCP](07-suffix-array-and-lcp.md) gives $O(1)$ with more code).
- **Palindromes of substrings**: forward hash vs reverse hash; binary search the radius (an alternative to [Manacher](04-manacher-and-palindromes.md)).
- **Growing strings** (append-only): prefix hashes extend in $O(1)$ per character.
- **Point updates**: store $s_i B^{i}$ in a [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md) or [segment tree](../08-Data-Structures/02-segment-tree-basics.md); a range sum is a substring hash times a known power.
- **Confused with**: KMP/Z (deterministic, $O(n)$, but only compare against *one* pattern or the string's own prefix — prefer them when they suffice); sum/XOR hashing of *multisets* ([randomised hashing](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md)) where order does not matter.

## 5. Worked examples (graded)

### Example 1 — String Matching by Rabin–Karp · ★ ≈1300 (est.)

- **Source:** [CSES 1753 · String Matching](https://cses.fi/problemset/task/1753)
- **Difficulty:** ≈1300 (est.)
- **Problem:** given a text $t$ and a pattern $p$ ($1 \le |t|, |p| \le 10^6$), count the positions where $p$ occurs in $t$.
- **Thinking from first principles:** the naive check at each of the $|t|-|p|+1$ starts costs $O(|p|)$, i.e. $10^{12}$. The window hash $H(t[i..i+m))$ is $O(1)$ from prefix hashes, and $H(p)$ is computed once, so each start is one integer comparison. Expected false positives: at most $|t| \cdot |p| / 2^{61} \approx 4\cdot 10^{-7}$.

<details><summary>Solution</summary>

Prefix hashes of $t$; hash of $p$; count $i$ with $H(i, i+m) = H(p)$. $O(|t|+|p|)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using u64 = unsigned long long;
const u64 M = (1ULL << 61) - 1;
u64 mul(u64 a, u64 b) {
    __uint128_t x = (__uint128_t)a * b;
    u64 r = (u64)(x & M) + (u64)(x >> 61);
    return r >= M ? r - M : r;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string t, p;
    cin >> t >> p;
    int n = t.size(), m = p.size();
    if (m > n) { cout << 0 << '\n'; return 0; }
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    u64 B = rng() % (M - (1ULL << 20)) + (1ULL << 20);
    vector<u64> h(n + 1, 0);
    for (int i = 0; i < n; i++) { h[i + 1] = mul(h[i], B) + (unsigned char)t[i]; if (h[i + 1] >= M) h[i + 1] -= M; }
    u64 hp = 0, pm = 1;                                   // hash of p and B^m
    for (int i = 0; i < m; i++) { hp = mul(hp, B) + (unsigned char)p[i]; if (hp >= M) hp -= M; pm = mul(pm, B); }
    int cnt = 0;
    for (int i = 0; i + m <= n; i++) {
        u64 x = h[i + m] + M - mul(h[i], pm);
        if (x >= M) x -= M;
        cnt += (x == hp);
    }
    cout << cnt << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long M = (1L << 61) - 1;
    static long mul(long a, long b) {
        long hi = Math.multiplyHigh(a, b), lo = a * b;
        long r = (lo & M) + ((lo >>> 61) | (hi << 3));
        return r >= M ? r - M : r;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] t = in.next().toCharArray(), p = in.next().toCharArray();
        int n = t.length, m = p.length;
        if (m > n) { out.println(0); out.flush(); return; }
        long B = (new SplittableRandom(System.nanoTime()).nextLong() >>> 4) % (M - (1L << 20)) + (1L << 20);
        long[] h = new long[n + 1];
        for (int i = 0; i < n; i++) { long x = mul(h[i], B) + t[i]; h[i + 1] = x >= M ? x - M : x; }
        long hp = 0, pm = 1;
        for (int i = 0; i < m; i++) { long x = mul(hp, B) + p[i]; hp = x >= M ? x - M : x; pm = mul(pm, B); }
        int cnt = 0;
        for (int i = 0; i + m <= n; i++) {
            long x = h[i + m] - mul(h[i], pm);
            if (x < 0) x += M;
            if (x == hp) cnt++;
        }
        out.println(cnt);
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
saippuakauppias
pp
out:
2
-->
<!-- test
in:
aaaaa
aa
out:
4
-->
<!-- test
in:
ab
abc
out:
0
-->

</details>

### Example 2 — Good Substrings · ★ 1800

- **Source:** [CF 271D · Good Substrings](https://codeforces.com/problemset/problem/271/D) — 1800
- **Difficulty:** 1800
- **Problem:** a string $s$ ($|s| \le 1500$, lowercase), a 26-character 0/1 mask saying which letters are good (`1`) or bad (`0`), and $k$. Count *distinct* substrings that contain at most $k$ bad letters.
- **Thinking from first principles:** there are only $\binom{1501}{2} \approx 1.1\cdot 10^6$ substrings, so enumerating them is fine; the problem is *distinctness*. Inserting the actual strings into a set costs $O(n^3)$ characters. A trie of all substrings works ($O(n^2)$ nodes, see [tries](05-trie-and-binary-trie.md)) but costs $26 \cdot 1.1\cdot 10^6$ ints. Hashing: fix the start $i$, extend the end $j$ one character at a time so the hash updates in $O(1)$ (Horner), stop when the bad count exceeds $k$. Sort all hashes and count unique values. Birthday check: $m^2/(2p) = (1.1\cdot 10^6)^2 / 4.6\cdot 10^{18} \approx 3\cdot 10^{-7}$ — safe with $2^{61}-1$; with a single $10^9+7$ it would almost surely fail.

<details><summary>Solution</summary>

For each start, extend while the bad count is $\le k$, pushing the running hash. Sort, unique. $O(n^2 \log n)$ time, $O(n^2)$ memory (8.6 MB). Different lengths are safe because character values are never 0.

```cpp
#include <bits/stdc++.h>
using namespace std;
using u64 = unsigned long long;
const u64 M = (1ULL << 61) - 1;
u64 mul(u64 a, u64 b) {
    __uint128_t x = (__uint128_t)a * b;
    u64 r = (u64)(x & M) + (u64)(x >> 61);
    return r >= M ? r - M : r;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s, good; int k;
    cin >> s >> good >> k;
    int n = s.size();
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    u64 B = rng() % (M - (1ULL << 20)) + (1ULL << 20);
    vector<u64> all;
    all.reserve((size_t)n * (n + 1) / 2);
    for (int i = 0; i < n; i++) {
        u64 h = 0; int bad = 0;
        for (int j = i; j < n; j++) {
            bad += good[s[j] - 'a'] == '0';
            if (bad > k) break;
            h = mul(h, B) + (unsigned char)s[j];
            if (h >= M) h -= M;
            all.push_back(h);
        }
    }
    sort(all.begin(), all.end());
    cout << (unique(all.begin(), all.end()) - all.begin()) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long M = (1L << 61) - 1;
    static long mul(long a, long b) {
        long hi = Math.multiplyHigh(a, b), lo = a * b;
        long r = (lo & M) + ((lo >>> 61) | (hi << 3));
        return r >= M ? r - M : r;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] s = in.next().toCharArray();
        char[] good = in.next().toCharArray();
        int k = in.nextInt(), n = s.length;
        long B = (new SplittableRandom(System.nanoTime()).nextLong() >>> 4) % (M - (1L << 20)) + (1L << 20);
        long[] all = new long[n * (n + 1) / 2];
        int m = 0;
        for (int i = 0; i < n; i++) {
            long h = 0; int bad = 0;
            for (int j = i; j < n; j++) {
                if (good[s[j] - 'a'] == '0') bad++;
                if (bad > k) break;
                long x = mul(h, B) + s[j];
                h = x >= M ? x - M : x;
                all[m++] = h;
            }
        }
        Arrays.sort(all, 0, m);          // primitive sort is safe here: the values are random hashes
        int distinct = 0;
        for (int i = 0; i < m; i++) if (i == 0 || all[i] != all[i - 1]) distinct++;
        out.println(distinct);
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
ababab
01000000000000000000000000
1
out:
5
-->
<!-- test
in:
acbacbacaa
11111111111111111111111111
2
out:
38
-->
<!-- test
in:
a
00000000000000000000000000
0
out:
0
-->

</details>

### Example 3 — Repeating Substring (binary search on length) · ★ ≈1900 (est.)

- **Source:** [CSES 2106 · Repeating Substring](https://cses.fi/problemset/task/2106)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $|s| \le 10^5$. Print a longest substring that occurs at least twice (occurrences may overlap), or `-1` if none exists.
- **Thinking from first principles:** the answer is monotone: if some string of length $L$ repeats, its length-$(L-1)$ prefix repeats too. So binary search the largest feasible $L$. Feasibility of $L$: are two of the $n-L+1$ window hashes equal? Sort (hash, start) pairs and look at neighbours. That is $O(n \log n)$ per check and $O(n \log^2 n)$ overall. (The deterministic alternative is $\max$ LCP over adjacent suffixes of the [suffix array](07-suffix-array-and-lcp.md).)

<details><summary>Solution</summary>

`check(L)` returns a start of a repeated window or $-1$. Binary search over $L \in [1, n-1]$. $O(n\log^2 n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using u64 = unsigned long long;
const u64 M = (1ULL << 61) - 1;
u64 mul(u64 a, u64 b) {
    __uint128_t x = (__uint128_t)a * b;
    u64 r = (u64)(x & M) + (u64)(x >> 61);
    return r >= M ? r - M : r;
}
string s; int n;
vector<u64> h, pw;
u64 get(int l, int r) { u64 x = h[r] + M - mul(h[l], pw[r - l]); return x >= M ? x - M : x; }
int check(int L) {                                     // start of a repeated length-L window, or -1
    vector<pair<u64, int>> w;
    for (int i = 0; i + L <= n; i++) w.push_back({get(i, i + L), i});
    sort(w.begin(), w.end());
    for (size_t i = 1; i < w.size(); i++) if (w[i].first == w[i - 1].first) return w[i].second;
    return -1;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    cin >> s; n = s.size();
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    u64 B = rng() % (M - (1ULL << 20)) + (1ULL << 20);
    h.assign(n + 1, 0); pw.assign(n + 1, 1);
    for (int i = 0; i < n; i++) {
        h[i + 1] = mul(h[i], B) + (unsigned char)s[i]; if (h[i + 1] >= M) h[i + 1] -= M;
        pw[i + 1] = mul(pw[i], B);
    }
    int lo = 0, hi = n - 1, best = -1;                // lo = largest length known to repeat
    while (lo < hi) {
        int mid = (lo + hi + 1) / 2, p = check(mid);
        if (p >= 0) lo = mid, best = p; else hi = mid - 1;
    }
    if (lo == 0) cout << -1 << '\n';
    else cout << s.substr(best, lo) << '\n';          // best came from the check that set lo
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long M = (1L << 61) - 1;
    static long mul(long a, long b) {
        long hi = Math.multiplyHigh(a, b), lo = a * b;
        long r = (lo & M) + ((lo >>> 61) | (hi << 3));
        return r >= M ? r - M : r;
    }
    static long[] h, pw;
    static int n;
    static long get(int l, int r) { long x = h[r] - mul(h[l], pw[r - l]); return x < 0 ? x + M : x; }
    static int check(int L) {
        int m = n - L + 1;
        long[] key = new long[m];
        for (int i = 0; i < m; i++) key[i] = get(i, i + L);
        long[] sorted = key.clone();
        Arrays.sort(sorted);                                 // random hashes: no anti-quicksort risk
        long dup = -1; boolean found = false;
        for (int i = 1; i < m; i++) if (sorted[i] == sorted[i - 1]) { dup = sorted[i]; found = true; break; }
        if (!found) return -1;
        for (int i = 0; i < m; i++) if (key[i] == dup) return i;
        return -1;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        n = s.length();
        long B = (new SplittableRandom(System.nanoTime()).nextLong() >>> 4) % (M - (1L << 20)) + (1L << 20);
        h = new long[n + 1]; pw = new long[n + 1]; pw[0] = 1;
        for (int i = 0; i < n; i++) {
            long x = mul(h[i], B) + s.charAt(i); h[i + 1] = x >= M ? x - M : x;
            pw[i + 1] = mul(pw[i], B);
        }
        int lo = 0, hi = n - 1;
        while (lo < hi) {
            int mid = (lo + hi + 1) >>> 1;
            if (check(mid) >= 0) lo = mid; else hi = mid - 1;
        }
        if (lo == 0) out.println(-1);
        else { int p = check(lo); out.println(s.substring(p, p + lo)); }
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
aabbaabb
out:
aabb
-->
<!-- test
in:
abc
out:
-1
-->
<!-- test
in:
aaaa
out:
aaa
-->

</details>

### Example 4 — Compress Words (hash of a growing string) · ★ 2000

- **Source:** [CF 1200E · Compress Words](https://codeforces.com/problemset/problem/1200/E) — 2000
- **Difficulty:** 2000
- **Problem:** $n \le 10^5$ words (letters and digits, total length $\le 10^6$) are merged left to right: when appending word $w$ to the current result $r$, delete the longest prefix of $w$ that equals a suffix of $r$. Print the final string.
- **Thinking from first principles:** the overlap test "suffix of $r$ of length $L$ equals prefix of $w$ of length $L$" is a substring comparison between two strings. Only $L \le \min(|r|, |w|)$ matters, and we can try $L$ from large to small. Each attempt is $O(1)$ with hashes, so a word costs $O(|w|)$ — total $O(\sum |w|)$. Dead end: recomputing a prefix function of $w + \# + r$ costs $O(|r|)$ per word, $O(n\cdot|r|)$ total — unless you only take the last $|w|$ characters of $r$, which is the KMP solution (see [prefix function](02-prefix-function-kmp.md)). Hashing needs no such care: the prefix hashes of $r$ simply grow as characters are appended.

<details><summary>Solution</summary>

Maintain prefix hashes of the result (append-only). For each word, compute its prefix hashes, find the largest $L$ with $H_r(|r|-L, |r|) = H_w(0, L)$, append $w[L..]$. $O(\sum|w|)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using u64 = unsigned long long;
const u64 M = (1ULL << 61) - 1;
u64 mul(u64 a, u64 b) {
    __uint128_t x = (__uint128_t)a * b;
    u64 r = (u64)(x & M) + (u64)(x >> 61);
    return r >= M ? r - M : r;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    u64 B = rng() % (M - (1ULL << 20)) + (1ULL << 20);
    vector<u64> pw(1, 1), hr(1, 0), hw;               // powers, prefix hashes of result, of word
    auto power = [&](size_t k) { while (pw.size() <= k) pw.push_back(mul(pw.back(), B)); return pw[k]; };
    string res, w;
    for (int it = 0; it < n; it++) {
        cin >> w;
        int m = w.size(), R = res.size();
        hw.assign(m + 1, 0);
        for (int i = 0; i < m; i++) { hw[i + 1] = mul(hw[i], B) + (unsigned char)w[i]; if (hw[i + 1] >= M) hw[i + 1] -= M; }
        int L = min(m, R);
        for (; L > 0; L--) {
            u64 suf = hr[R] + M - mul(hr[R - L], power(L));
            if (suf >= M) suf -= M;
            if (suf == hw[L]) break;
        }
        for (int i = L; i < m; i++) {
            res.push_back(w[i]);
            u64 x = mul(hr.back(), B) + (unsigned char)w[i];
            hr.push_back(x >= M ? x - M : x);
        }
    }
    cout << res << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long M = (1L << 61) - 1;
    static long mul(long a, long b) {
        long hi = Math.multiplyHigh(a, b), lo = a * b;
        long r = (lo & M) + ((lo >>> 61) | (hi << 3));
        return r >= M ? r - M : r;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long B = (new SplittableRandom(System.nanoTime()).nextLong() >>> 4) % (M - (1L << 20)) + (1L << 20);
        final int CAP = 1_000_001;                      // total length bound
        long[] pw = new long[CAP + 1], hr = new long[CAP + 1], hw = new long[CAP + 1];
        pw[0] = 1;
        for (int i = 1; i <= CAP; i++) pw[i] = mul(pw[i - 1], B);
        char[] res = new char[CAP];
        int R = 0;
        for (int it = 0; it < n; it++) {
            char[] w = in.next().toCharArray();
            int m = w.length;
            for (int i = 0; i < m; i++) { long x = mul(hw[i], B) + w[i]; hw[i + 1] = x >= M ? x - M : x; }
            int L = Math.min(m, R);
            for (; L > 0; L--) {
                long suf = hr[R] - mul(hr[R - L], pw[L]);
                if (suf < 0) suf += M;
                if (suf == hw[L]) break;
            }
            for (int i = L; i < m; i++) {
                res[R] = w[i];
                long x = mul(hr[R], B) + w[i];
                hr[R + 1] = x >= M ? x - M : x;
                R++;
            }
        }
        out.println(new String(res, 0, R));
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
I want to order pizza
out:
Iwantorderpizza
-->
<!-- test
in:
3
ab ba ab
out:
abab
-->
<!-- test
in:
2
sample please
out:
samplease
-->
<!-- test
in:
1
x
out:
x
-->

</details>

### Example 5 — Palindrome Degree (forward vs reverse hash, online) · ★ 2200

- **Source:** [CF 7D · Palindrome Degree](https://codeforces.com/problemset/problem/7/D) — 2200
- **Difficulty:** 2200
- **Problem:** every string is a 0-palindrome; a string of length $L$ is a $k$-palindrome if it is a palindrome and its prefix of length $\lfloor L/2\rfloor$ is a $(k-1)$-palindrome. The degree is the largest such $k$. Given $s$ ($|s| \le 5\cdot 10^6$, letters and digits), print the sum of the degrees of all prefixes.
- **Thinking from first principles:** the definition is already a recurrence: $\deg(L) = \deg(\lfloor L/2\rfloor) + 1$ if the prefix of length $L$ is a palindrome, else $0$ (with $\deg(0) = 0$). So the only question is "is each prefix a palindrome?" — $n$ yes/no questions in $O(1)$ each. A prefix is a palindrome iff it equals its reverse. Maintain both hashes online: forward $F \leftarrow F\cdot B + c$ (Horner, the new character becomes the lowest digit) and backward $G \leftarrow G + c\cdot B^{i}$ (the new character becomes the highest digit of the reversed prefix). They are equal exactly when the prefix reads the same both ways. Memory matters at $5\cdot 10^6$: no prefix arrays, only the degree array.

<details><summary>Solution</summary>

One pass, two multiplications per character. $O(n)$ time, $O(n)$ ints.

```cpp
#include <bits/stdc++.h>
using namespace std;
using u64 = unsigned long long;
const u64 M = (1ULL << 61) - 1;
u64 mul(u64 a, u64 b) {
    __uint128_t x = (__uint128_t)a * b;
    u64 r = (u64)(x & M) + (u64)(x >> 61);
    return r >= M ? r - M : r;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size();
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    u64 B = rng() % (M - (1ULL << 20)) + (1ULL << 20);
    vector<int> deg(n + 1, 0);
    u64 F = 0, G = 0, P = 1;                            // P = B^i
    long long total = 0;
    for (int i = 0; i < n; i++) {
        u64 c = (unsigned char)s[i];
        F = mul(F, B) + c; if (F >= M) F -= M;
        G = G + mul(c, P); if (G >= M) G -= M;
        P = mul(P, B);
        if (F == G) deg[i + 1] = deg[(i + 1) / 2] + 1;
        total += deg[i + 1];
    }
    cout << total << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long M = (1L << 61) - 1;
    static long mul(long a, long b) {
        long hi = Math.multiplyHigh(a, b), lo = a * b;
        long r = (lo & M) + ((lo >>> 61) | (hi << 3));
        return r >= M ? r - M : r;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        int n = s.length();
        long B = (new SplittableRandom(System.nanoTime()).nextLong() >>> 4) % (M - (1L << 20)) + (1L << 20);
        int[] deg = new int[n + 1];
        long F = 0, G = 0, P = 1, total = 0;
        for (int i = 0; i < n; i++) {
            long c = s.charAt(i);
            F = mul(F, B) + c; if (F >= M) F -= M;
            G = G + mul(c, P); if (G >= M) G -= M;
            P = mul(P, B);
            if (F == G) deg[i + 1] = deg[(i + 1) / 2] + 1;
            total += deg[i + 1];
        }
        out.println(total);
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
a2A
out:
1
-->
<!-- test
in:
abacaba
out:
6
-->
<!-- test
in:
aaaa
out:
8
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Randomise the base, keep the modulus prime and big.** The proof of the collision bound needs $B$ random *after* the test is fixed. A hard-coded base like 31 or 131 is hackable; seeding from the clock is enough.
2. **Never map a character to 0.** If `'a' -> 0` then "a", "aa", "aaa" all hash to 0 (leading zeros). Use the byte value or `c - 'a' + 1`.
3. **Mod $2^{64}$ (unsigned overflow) is broken by Thue–Morse** for every base — including odd ones. Do not use it on Codeforces.
4. **Birthday paradox when counting distinct values.** $m$ hashes in a set means $\approx m^2/2$ comparisons. $10^6$ values need $p \gg 10^{12}$: use $2^{61}-1$ or a double hash.
5. **Java `%` keeps the sign.** `(h[r] - h[l] * p % M) % M` can be negative; add `M` before the final `%`, or subtract and fix with one `if`.
6. **Java `Math.multiplyHigh` is signed.** It is correct for inputs in $[0, 2^{63})$, which holds for residues below $2^{61}-1$. Use `>>>` (not `>>`) for the low word.
7. **Sorting a vector of hashes beats a hash set** (cache-friendly, no anti-hash issues). If you do use a hash set in C++, wrap the key with a splitmix64-based hash; in Java prefer a sorted `long[]` over `HashSet<Long>` (boxing + memory).
8. **Precompute powers once, to the maximum length you will need** — computing $B^k$ by fast exponentiation per query adds a $\log$ factor.
9. **Compare lengths too** when hashing strings of different lengths into one map, unless all character values are non-zero (they are, with pitfall 2 respected). Packing the length into the key costs nothing and removes the doubt.
10. **The binary search in an LCP must have equal-hash ⇒ "go right"** and start with `hi = min(len1, len2)`; the classic off-by-one is reading `s[i + k]` when $k$ equals a length.
11. **Hashing is Monte Carlo.** For deterministic guarantees (e.g. interactive problems, or when a WA costs too much) use KMP/Z/suffix structures; for counting palindromes use [Manacher](04-manacher-and-palindromes.md).
12. **Double hashing doubles the constant.** On tight limits a single $2^{61}-1$ hash with one `__int128` multiply is faster than two `%` operations.

## 7. Going further (toward 2400–2600+)

- **Hashing with updates.** Store $s_i B^{i}$ in a segment tree; a range sum is $H(s[l..r))\cdot B^{l}$ (compare after multiplying the other side by the matching power). Palindromes under point updates keep a second tree for the reversed string — see [CSES 2420 · Palindrome Queries](https://cses.fi/problemset/task/2420) and [CF 580E · Kefa and Watch](https://codeforces.com/problemset/problem/580/E) — 2500 (range assignment + period checks).
- **Suffix array by hashing**: sort suffixes with an LCP-by-hash comparator, $O(n\log^2 n)$; a quick replacement for [suffix array](07-suffix-array-and-lcp.md) when $n \le 2\cdot 10^5$.
- **2D hashing**: hash rows with base $B_1$, then columns of row-hashes with base $B_2$; sub-rectangle hash by 2D inclusion–exclusion.
- **Hashing trees and multisets**: rooted-tree isomorphism (see [tree basics](../10-Trees/01-tree-basics-diameter-center-euler-tour.md)), and order-independent sum/XOR hashing of random 64-bit values per element ([randomised algorithms and hashing](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md)).
- **Cyclic shifts**: hash $s+s$; the minimal rotation (Booth's or Duval's algorithm, $O(n)$) can also be found by $n$ LCP-by-hash comparisons in $O(n\log n)$ — [CSES 1110 · Minimal Rotation](https://cses.fi/problemset/task/1110).
- **Breaking weak hashes** (useful to understand hacks): birthday search on $\approx\sqrt{p}$ random strings breaks a single 32-bit modulus; the Thue–Morse construction breaks $2^{64}$; lattice reduction (LLL) breaks fixed-base double hashes.

For revision, the formulas and templates of this file are condensed in the [strings cheat sheet](../99-Cheat-Sheets/11-strings-cheatsheet.md).

## 8. Practice ladder

**≤ 1600**
- [ ] [CSES 1753 · String Matching](https://cses.fi/problemset/task/1753) — Rabin–Karp warm-up
- [ ] [CF 1800D · Remove Two Letters](https://codeforces.com/problemset/problem/1800/D) — 1200
- [ ] [CF 1326D1 · Prefix-Suffix Palindrome (Easy version)](https://codeforces.com/problemset/problem/1326/D1) — 1500
- [ ] [CF 1137B · Camp Schedule](https://codeforces.com/problemset/problem/1137/B) — 1600

**1700–1900**
- [ ] [CF 126B · Password](https://codeforces.com/problemset/problem/126/B) — 1700
- [ ] [CF 271D · Good Substrings](https://codeforces.com/problemset/problem/271/D) — 1800
- [ ] [CF 1326D2 · Prefix-Suffix Palindrome (Hard version)](https://codeforces.com/problemset/problem/1326/D2) — 1800
- [ ] [CF 835D · Palindromic characteristics](https://codeforces.com/problemset/problem/835/D) — 1900
- [ ] [CF 535D · Tavas and Malekas](https://codeforces.com/problemset/problem/535/D) — 1900
- [ ] [CF 1968G1 · Division + LCP (easy version)](https://codeforces.com/problemset/problem/1968/G1) — 1900
- [ ] [CSES 2106 · Repeating Substring](https://cses.fi/problemset/task/2106) — ≈1900 (est.)

**2000–2200**
- [ ] [CF 514C · Watto and Mechanism](https://codeforces.com/problemset/problem/514/C) — 2000
- [ ] [CF 1200E · Compress Words](https://codeforces.com/problemset/problem/1200/E) — 2000
- [ ] [CF 113B · Petr#](https://codeforces.com/problemset/problem/113/B) — 2000
- [ ] [CF 1056E · Check Transcription](https://codeforces.com/problemset/problem/1056/E) — 2100
- [ ] [CF 7D · Palindrome Degree](https://codeforces.com/problemset/problem/7/D) — 2200
- [ ] [CF 1537E2 · Erase and Extend (Hard Version)](https://codeforces.com/problemset/problem/1537/E2) — 2200
- [ ] [CF 1003F · Abbreviation](https://codeforces.com/problemset/problem/1003/F) — 2200
- [ ] [CF 1968G2 · Division + LCP (hard version)](https://codeforces.com/problemset/problem/1968/G2) — 2200
- [ ] [CSES 1110 · Minimal Rotation](https://cses.fi/problemset/task/1110) — ≈2000 (est.)
- [ ] [CSES 2420 · Palindrome Queries](https://cses.fi/problemset/task/2420) — ≈2100 (est.)

**2300+**
- [ ] [CF 727E · Games on a CD](https://codeforces.com/problemset/problem/727/E) — 2300
- [ ] [CF 898F · Restoring the Expression](https://codeforces.com/problemset/problem/898/F) — 2300
- [ ] [CF 580E · Kefa and Watch](https://codeforces.com/problemset/problem/580/E) — 2500

## 9. LeetCode / FAANG cross-reference

- [LC 28 · Find the Index of the First Occurrence in a String](https://leetcode.com/problems/find-the-index-of-the-first-occurrence-in-a-string/) — Easy — Rabin–Karp (interviewers accept it if you discuss collisions; KMP is the deterministic answer).
- [LC 187 · Repeated DNA Sequences](https://leetcode.com/problems/repeated-dna-sequences/) — Medium — fixed-length window hash (here $4^{10}$ fits exactly: a perfect, collision-free hash).
- [LC 1044 · Longest Duplicate Substring](https://leetcode.com/problems/longest-duplicate-substring/) — Hard — exactly Example 3: binary search on length + window hashes.
- [LC 718 · Maximum Length of Repeated Subarray](https://leetcode.com/problems/maximum-length-of-repeated-subarray/) — Medium — binary search on length + hashing of both arrays (or $O(nm)$ DP).
- [LC 1316 · Distinct Echo Substrings](https://leetcode.com/problems/distinct-echo-substrings/) — Hard — $O(n^2)$ substring comparisons by hash, deduplicate hashes.
- [LC 1923 · Longest Common Subpath](https://leetcode.com/problems/longest-common-subpath/) — Hard — binary search + intersect hash sets across arrays; needs a strong (double / 61-bit) hash.
- [LC 2156 · Find Substring With Given Hash Value](https://leetcode.com/problems/find-substring-with-given-hash-value/) — Hard — the window must slide right-to-left because the given hash weights $s_i p^{i}$ (the "reversed" form).
- [LC 214 · Shortest Palindrome](https://leetcode.com/problems/shortest-palindrome/) — Hard — longest palindromic prefix via forward/backward hash (or KMP on $s\#\mathrm{rev}(s)$).
- [LC 1392 · Longest Happy Prefix](https://leetcode.com/problems/longest-happy-prefix/) — Hard — longest border: compare prefix and suffix hashes for every length.
- [LC 796 · Rotate String](https://leetcode.com/problems/rotate-string/) — Easy — $t$ occurs in $s+s$.
- [LC 49 · Group Anagrams](https://leetcode.com/problems/group-anagrams/) — Medium — order-independent key (sorted string or letter counts): the multiset-hashing idea.

## 10. Self-check

1. Derive $H(s[l..r))$ from prefix hashes, and say why the power is $B^{r-l}$ and not $B^{l}$.
2. Why must the base be random *at run time* for the bound $(L-1)/p$ to apply to a hacked test?
3. You insert $5\cdot 10^5$ substring hashes modulo $10^9+7$ into a set. Estimate the probability of at least one collision.
4. Why does `'a' -> 0` break hashing of strings with different lengths?
5. Show that $x \bmod (2^{61}-1) = (x \mathbin{\&} (2^{61}-1)) + (x \gg 61)$ up to one subtraction.
6. How do you test whether $s[l..r)$ is a palindrome in $O(1)$ with hashing?
7. How do you compare $s[a..b)$ and $s[c..d)$ lexicographically, and what is the complexity?
8. When should you prefer KMP or the Z-function over hashing?

<details><summary>Answers</summary>

1. $h_r = h_l\,B^{r-l} + H(s[l..r))$: the first $l$ characters are shifted left by the $r-l$ digits that follow them, so subtract $h_l B^{r-l}$.
2. The bound counts roots of a fixed non-zero polynomial; it holds when $B$ is independent of the strings. A fixed base lets the hacker pick strings whose difference polynomial vanishes at that base.
3. $m^2/(2p) = 2.5\cdot 10^{11} / (2\cdot 10^9) = 125 \gg 1$: a collision is essentially certain ($1 - e^{-125}$).
4. Leading zeros: "a" is the number 0 and "aa" is $0\cdot B + 0 = 0$; the difference polynomial is identically zero, so no base can separate them.
5. Write $x = q\,2^{61} + r$; since $2^{61} \equiv 1$, $x \equiv q + r$; for $x < 2^{122}$ we get $q + r < 2(2^{61}-1)$, so one conditional subtraction gives the residue.
6. Keep prefix hashes of $s$ and of $\mathrm{rev}(s)$; $s[l..r)$ is a palindrome iff $H_s(l, r) = H_{\mathrm{rev}}(n-r, n-l)$.
7. Binary search the LCP $k$ with $O(1)$ hash comparisons, then compare the characters at offset $k$ (or the lengths if $k$ reaches one of them): $O(\log n)$.
8. When the question is "occurrences of one pattern" or "borders/periods of one string": they are $O(n)$, deterministic and unhackable. Hashing wins when you need *arbitrary pairs* of substrings.

</details>
