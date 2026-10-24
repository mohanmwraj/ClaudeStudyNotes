# Manacher's algorithm and palindromic substrings

> **Band:** 🔵 1600–2200 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [Z-function](03-z-function.md) (same "reuse the box" idea), [string hashing](01-string-hashing.md) (the alternative), [difference arrays](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md)
> **You can say you know this when:** you can write Manacher ($d_1$/$d_2$) without looking, explain why it is linear, turn the radii into "palindromes starting/ending at each index" with difference arrays, and you know when an $O(n\log n)$ hashing solution is good enough.

## 1. First principles — why this works

**Goal.** For every centre, the longest palindrome around it. There are $2n-1$ centres: $n$ characters (odd lengths) and $n-1$ gaps (even lengths). Define

- $d_1[i]$ = number of odd palindromes centred at $i$ = the largest $k$ with $s[i-k+1..i+k-1]$ a palindrome (so the longest one has length $2d_1[i]-1$);
- $d_2[i]$ = number of even palindromes centred between $i-1$ and $i$ = the largest $k$ with $s[i-k..i+k-1]$ a palindrome (length $2d_2[i]$, possibly $0$).

Why radii are enough: a palindrome stays a palindrome when you peel one character off each end, so the palindromes with a fixed centre are nested, and the *number* of them equals the maximal radius. Everything — counting palindromic substrings, the longest one, "is $s[l..r]$ a palindrome" — follows from $d_1$, $d_2$.

**Naive.** Expand around each centre: $O(n^2)$ on `aaaa…a`.

**The reuse.** Keep the palindrome $[l, r]$ (closed) with the largest right end found so far. For a centre $i \le r$, its mirror $j = l + r - i$ lies inside the same big palindrome, and the big palindrome maps the neighbourhood of $j$ onto the neighbourhood of $i$ (reversed). So whatever palindrome surrounds $j$ *inside* $[l, r]$ also surrounds $i$:

$$d_1[i] \ge \min\big(d_1[j],\; r - i + 1\big).$$

- If $d_1[j] < r - i + 1$, the mismatch that stopped $j$ is mirrored inside the box, so $d_1[i] = d_1[j]$ exactly.
- Otherwise we only know the palindrome reaches $r$; extend naively beyond $r$.

The same holds for $d_2$ with the mirror $j = l + r - i + 1$.

**Why $O(n)$.** Every successful comparison in the extension loop examines a character beyond $r$ and then the new palindrome's right end exceeds the old $r$ — so $r$ grows by one per successful comparison. $r < n$, and each centre has at most one failed comparison. Total $O(n)$, the same amortisation as the [Z-function](03-z-function.md).

**One array instead of two.** Insert a separator between characters: $t = \#s_0\#s_1\#\dots\#s_{n-1}\#$ (length $2n+1$). Every palindrome of $s$ becomes an odd palindrome of $t$ centred at a character (odd length in $s$) or at a $\#$ (even length). If $d[i]$ is the odd radius in $t$, the corresponding palindrome in $s$ has length $d[i] - 1$. Same algorithm, one loop; costs twice the memory.

**The hashing alternative.** With forward and reverse [hashes](01-string-hashing.md), "is $s[l..r)$ a palindrome" is $O(1)$, and the radius at a centre is monotone, so binary search it: $O(n \log n)$, probabilistic, but it generalises (palindromes under updates, palindromes in 2D, comparing a palindrome with something else).

## 2. Formulas, definitions and identities

| Quantity | Formula | Cost |
|---|---|---|
| odd palindromes at $i$ | $s[i-k+1..i+k-1]$ for $k = 1..d_1[i]$ | — |
| even palindromes at $i$ | $s[i-k..i+k-1]$ for $k = 1..d_2[i]$ | — |
| number of palindromic substrings (as positions) | $\sum_i d_1[i] + \sum_i d_2[i]$ | $O(n)$ |
| longest palindrome | $\max\big(\max_i (2d_1[i]-1),\ \max_i 2d_2[i]\big)$ | $O(n)$ |
| is $s[l..r]$ a palindrome | odd length: $d_1[c] \ge (r-l)/2 + 1$ with $c = (l+r)/2$; even: $d_2[c] \ge (r-l+1)/2$ with $c = (l+r+1)/2$ | $O(1)$ |
| transformed string | $t = \#s_0\#\dots\#$, palindrome length in $s$ $= d_t[i] - 1$ | $O(n)$ |
| palindromes starting at each index | odd centre $i$: $+1$ on $[i-d_1[i]+1,\ i]$; even centre $i$: $+1$ on $[i-d_2[i],\ i-1]$ | $O(n)$ with a difference array |
| palindromes ending at each index | odd: $+1$ on $[i,\ i+d_1[i]-1]$; even: $+1$ on $[i,\ i+d_2[i]-1]$ | same |
| distinct palindromes | at most $n$ (plus the empty one) | see below |

**At most $n$ distinct palindromic substrings.** Append characters one by one. Claim: only the *longest* palindromic suffix of the new prefix can be new. Any shorter palindromic suffix $u$ of a palindromic suffix $v$ is also a prefix of $v$ (reverse $v$), so it already occurred earlier, ending before the current position. Hence each step adds at most one new distinct palindrome: total $\le n$. This is why the [palindromic tree](09-palindromic-tree-eertree.md) has at most $n + 2$ nodes.

## 3. Implementation (C++ and Java)

### 3.1 Manacher ($d_1$, $d_2$)

Driver: read $s$; print $d_1$, $d_2$, the number of palindromic substrings, and the start and length of the leftmost longest palindrome.

```cpp
#include <bits/stdc++.h>
using namespace std;

void manacher(const string& s, vector<int>& d1, vector<int>& d2) {
    int n = s.size();
    d1.assign(n, 0); d2.assign(n, 0);
    for (int i = 0, l = 0, r = -1; i < n; i++) {         // [l, r] = rightmost palindrome found
        int k = (i > r) ? 1 : min(d1[l + r - i], r - i + 1);
        while (i - k >= 0 && i + k < n && s[i - k] == s[i + k]) k++;
        d1[i] = k--;
        if (i + k > r) l = i - k, r = i + k;
    }
    for (int i = 0, l = 0, r = -1; i < n; i++) {
        int k = (i > r) ? 0 : min(d2[l + r - i + 1], r - i + 1);
        while (i - k - 1 >= 0 && i + k < n && s[i - k - 1] == s[i + k]) k++;
        d2[i] = k--;
        if (i + k > r) l = i - k - 1, r = i + k;
    }
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size();
    vector<int> d1, d2;
    manacher(s, d1, d2);
    long long cnt = 0;
    int bestLen = 0, bestStart = 0;
    auto consider = [&](int start, int len) {
        if (len > bestLen || (len == bestLen && start < bestStart)) bestLen = len, bestStart = start;
    };
    for (int i = 0; i < n; i++) {
        cnt += d1[i] + d2[i];
        consider(i - d1[i] + 1, 2 * d1[i] - 1);
        if (d2[i] > 0) consider(i - d2[i], 2 * d2[i]);
    }
    for (int i = 0; i < n; i++) cout << d1[i] << (i + 1 < n ? ' ' : '\n');
    for (int i = 0; i < n; i++) cout << d2[i] << (i + 1 < n ? ' ' : '\n');
    cout << cnt << '\n' << bestStart << ' ' << bestLen << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] d1, d2;
    static void manacher(char[] s) {
        int n = s.length;
        d1 = new int[n]; d2 = new int[n];
        for (int i = 0, l = 0, r = -1; i < n; i++) {
            int k = (i > r) ? 1 : Math.min(d1[l + r - i], r - i + 1);
            while (i - k >= 0 && i + k < n && s[i - k] == s[i + k]) k++;
            d1[i] = k--;
            if (i + k > r) { l = i - k; r = i + k; }
        }
        for (int i = 0, l = 0, r = -1; i < n; i++) {
            int k = (i > r) ? 0 : Math.min(d2[l + r - i + 1], r - i + 1);
            while (i - k - 1 >= 0 && i + k < n && s[i - k - 1] == s[i + k]) k++;
            d2[i] = k--;
            if (i + k > r) { l = i - k - 1; r = i + k; }
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] s = in.next().toCharArray();
        int n = s.length;
        manacher(s);
        long cnt = 0;
        int bestLen = 0, bestStart = 0;
        for (int i = 0; i < n; i++) {
            cnt += d1[i] + d2[i];
            int st = i - d1[i] + 1, len = 2 * d1[i] - 1;
            if (len > bestLen || (len == bestLen && st < bestStart)) { bestLen = len; bestStart = st; }
            if (d2[i] > 0) {
                st = i - d2[i]; len = 2 * d2[i];
                if (len > bestLen || (len == bestLen && st < bestStart)) { bestLen = len; bestStart = st; }
            }
        }
        StringBuilder a = new StringBuilder(), b = new StringBuilder();
        for (int i = 0; i < n; i++) { if (i > 0) { a.append(' '); b.append(' '); } a.append(d1[i]); b.append(d2[i]); }
        out.println(a); out.println(b);
        out.println(cnt);
        out.println(bestStart + " " + bestLen);
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
out:
1 2 1 4 1 2 1
0 0 0 0 0 0 0
12
0 7
-->
<!-- test
in:
aaaa
out:
1 2 2 1
0 1 2 1
10
0 4
-->
<!-- test
in:
ab
out:
1 1
0 0
2
0 1
-->

### 3.2 The same radii by hashing + binary search ($O(n\log n)$)

Same input and output as §3.1. Useful when the palindrome test must be combined with other hash comparisons, or when the string changes (put the hashes in a segment tree).

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
int n;
vector<u64> hf, hr, pw;                                    // prefix hashes of s and of rev(s)
u64 get(const vector<u64>& h, int l, int r) { u64 x = h[r] + M - mul(h[l], pw[r - l]); return x >= M ? x - M : x; }
bool isPal(int l, int r) { return get(hf, l, r) == get(hr, n - r, n - l); }   // s[l..r)

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    n = s.size();
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    u64 B = rng() % (M - (1ULL << 20)) + (1ULL << 20);
    hf.assign(n + 1, 0); hr.assign(n + 1, 0); pw.assign(n + 1, 1);
    for (int i = 0; i < n; i++) {
        hf[i + 1] = mul(hf[i], B) + (unsigned char)s[i]; if (hf[i + 1] >= M) hf[i + 1] -= M;
        hr[i + 1] = mul(hr[i], B) + (unsigned char)s[n - 1 - i]; if (hr[i + 1] >= M) hr[i + 1] -= M;
        pw[i + 1] = mul(pw[i], B);
    }
    vector<int> d1(n), d2(n);
    for (int i = 0; i < n; i++) {
        int lo = 1, hi = min(i + 1, n - i);               // odd: radius k means s[i-k+1 .. i+k-1]
        while (lo < hi) { int k = (lo + hi + 1) / 2; if (isPal(i - k + 1, i + k)) lo = k; else hi = k - 1; }
        d1[i] = lo;
        lo = 0, hi = min(i, n - i);                       // even: radius k means s[i-k .. i+k-1]
        while (lo < hi) { int k = (lo + hi + 1) / 2; if (isPal(i - k, i + k)) lo = k; else hi = k - 1; }
        d2[i] = lo;
    }
    long long cnt = 0;
    int bestLen = 0, bestStart = 0;
    auto consider = [&](int start, int len) {
        if (len > bestLen || (len == bestLen && start < bestStart)) bestLen = len, bestStart = start;
    };
    for (int i = 0; i < n; i++) {
        cnt += d1[i] + d2[i];
        consider(i - d1[i] + 1, 2 * d1[i] - 1);
        if (d2[i] > 0) consider(i - d2[i], 2 * d2[i]);
    }
    for (int i = 0; i < n; i++) cout << d1[i] << (i + 1 < n ? ' ' : '\n');
    for (int i = 0; i < n; i++) cout << d2[i] << (i + 1 < n ? ' ' : '\n');
    cout << cnt << '\n' << bestStart << ' ' << bestLen << '\n';
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
    static int n;
    static long[] hf, hr, pw;
    static long get(long[] h, int l, int r) { long x = h[r] - mul(h[l], pw[r - l]); return x < 0 ? x + M : x; }
    static boolean isPal(int l, int r) { return get(hf, l, r) == get(hr, n - r, n - l); }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] s = in.next().toCharArray();
        n = s.length;
        long B = (new SplittableRandom(System.nanoTime()).nextLong() >>> 4) % (M - (1L << 20)) + (1L << 20);
        hf = new long[n + 1]; hr = new long[n + 1]; pw = new long[n + 1]; pw[0] = 1;
        for (int i = 0; i < n; i++) {
            long x = mul(hf[i], B) + s[i]; hf[i + 1] = x >= M ? x - M : x;
            x = mul(hr[i], B) + s[n - 1 - i]; hr[i + 1] = x >= M ? x - M : x;
            pw[i + 1] = mul(pw[i], B);
        }
        int[] d1 = new int[n], d2 = new int[n];
        for (int i = 0; i < n; i++) {
            int lo = 1, hi = Math.min(i + 1, n - i);
            while (lo < hi) { int k = (lo + hi + 1) >>> 1; if (isPal(i - k + 1, i + k)) lo = k; else hi = k - 1; }
            d1[i] = lo;
            lo = 0; hi = Math.min(i, n - i);
            while (lo < hi) { int k = (lo + hi + 1) >>> 1; if (isPal(i - k, i + k)) lo = k; else hi = k - 1; }
            d2[i] = lo;
        }
        long cnt = 0;
        int bestLen = 0, bestStart = 0;
        for (int i = 0; i < n; i++) {
            cnt += d1[i] + d2[i];
            int st = i - d1[i] + 1, len = 2 * d1[i] - 1;
            if (len > bestLen || (len == bestLen && st < bestStart)) { bestLen = len; bestStart = st; }
            if (d2[i] > 0) {
                st = i - d2[i]; len = 2 * d2[i];
                if (len > bestLen || (len == bestLen && st < bestStart)) { bestLen = len; bestStart = st; }
            }
        }
        StringBuilder a = new StringBuilder(), b = new StringBuilder();
        for (int i = 0; i < n; i++) { if (i > 0) { a.append(' '); b.append(' '); } a.append(d1[i]); b.append(d2[i]); }
        out.println(a); out.println(b);
        out.println(cnt);
        out.println(bestStart + " " + bestLen);
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
out:
1 2 1 4 1 2 1
0 0 0 0 0 0 0
12
0 7
-->
<!-- test
in:
aaaa
out:
1 2 2 1
0 1 2 1
10
0 4
-->
<!-- test
in:
abba
out:
1 1 1 1
0 0 2 0
6
0 4
-->

## 4. Recognising the pattern

- **"Longest palindromic substring"**, "count palindromic substrings", "is each query substring a palindrome" with $n$ up to $10^6$–$10^7$ → Manacher.
- **Palindromes as building blocks** (split into palindromes, pairs of palindromes, palindromes touching a prefix/suffix) → Manacher + [difference arrays](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md) to get "how many palindromes start/end at each index".
- **"Longest palindromic prefix/suffix"** → centres whose palindrome touches the boundary (or KMP on $s\#\mathrm{rev}(s)$).
- **Distinct palindromes, palindromes with multiplicities, palindromic factorisation** → [palindromic tree](09-palindromic-tree-eertree.md).
- **Palindromes under updates** → hashing in a segment tree, not Manacher.
- **Confused with**: palindromic *subsequences* (LC 516 style) — that is interval DP ([interval DP](../06-Dynamic-Programming/05-interval-dp.md)), Manacher does not apply.

## 5. Worked examples (graded)

### Example 1 — Longest Palindrome · ★ ≈1500 (est.)

- **Source:** [CSES 1111 · Longest Palindrome](https://cses.fi/problemset/task/1111)
- **Difficulty:** ≈1500 (est.)
- **Problem:** $|s| \le 10^6$. Print a longest palindromic substring (any one).
- **Thinking from first principles:** the longest palindrome is the maximal palindrome at *some* centre, so scanning $d_1$ and $d_2$ suffices. $O(n^2)$ expansion is too slow at $10^6$; $O(n\log n)$ hashing would pass but Manacher is shorter and exact.

<details><summary>Solution</summary>

Transformed-string version (one loop): $t = \#s_0\#s_1\dots\#$, $d[i]$ = odd radius in $t$; the palindrome in $s$ has length $d[i]-1$ and starts at $(i - d[i] + 1)/2$. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size(), m = 2 * n + 1;
    string t(m, '#');
    for (int i = 0; i < n; i++) t[2 * i + 1] = s[i];
    vector<int> d(m);
    int bestLen = 0, bestStart = 0;
    for (int i = 0, l = 0, r = -1; i < m; i++) {
        int k = (i > r) ? 1 : min(d[l + r - i], r - i + 1);
        while (i - k >= 0 && i + k < m && t[i - k] == t[i + k]) k++;
        d[i] = k--;
        if (i + k > r) l = i - k, r = i + k;
        int len = d[i] - 1, start = (i - d[i] + 1) / 2;     // back to coordinates in s
        if (len > bestLen) bestLen = len, bestStart = start;
    }
    cout << s.substr(bestStart, bestLen) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        int n = s.length(), m = 2 * n + 1;
        char[] t = new char[m];
        Arrays.fill(t, '#');
        for (int i = 0; i < n; i++) t[2 * i + 1] = s.charAt(i);
        int[] d = new int[m];
        int bestLen = 0, bestStart = 0;
        for (int i = 0, l = 0, r = -1; i < m; i++) {
            int k = (i > r) ? 1 : Math.min(d[l + r - i], r - i + 1);
            while (i - k >= 0 && i + k < m && t[i - k] == t[i + k]) k++;
            d[i] = k--;
            if (i + k > r) { l = i - k; r = i + k; }
            int len = d[i] - 1, start = (i - d[i] + 1) / 2;
            if (len > bestLen) { bestLen = len; bestStart = start; }
        }
        out.println(s.substring(bestStart, bestStart + bestLen));
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
aybabtu
out:
bab
-->
<!-- test
in:
abba
out:
abba
-->
<!-- test
in:
x
out:
x
-->

</details>

### Example 2 — Longest palindrome ending at every position · ★ ≈1800 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1800 (est.)
- **Problem:** $|s| \le 10^6$. For every $e$, print the length of the longest palindromic substring that ends at $e$.
- **Thinking from first principles:** Manacher gives palindromes per *centre*, but the question is per *end*. A centre $c$ (write it as a doubled index $C = 2i$ for odd centres and $C = 2i-1$ for the gap before $i$) covers the ends $e$ from its centre up to its reach $R(C)$, and the palindrome ending at $e$ has length $2e - C + 1$ — longer for smaller $C$. So for each $e$ we want the **smallest** centre whose reach is at least $e$. Sweep the centres in increasing $C$ with a pointer $p$ = last end already answered: centre $C$ answers all ends in $(p, R(C)]$, then $p = R(C)$. Each end is answered once, by the first (smallest) centre that reaches it; the pointer never needs to go back because the centre at $e$ itself reaches $e$. Dead end: a segment tree "min centre covering $e$" also works but is $O(n\log n)$ and heavier.

<details><summary>Solution</summary>

$O(n)$ after Manacher.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size();
    vector<int> d1(n), d2(n);
    for (int i = 0, l = 0, r = -1; i < n; i++) {
        int k = (i > r) ? 1 : min(d1[l + r - i], r - i + 1);
        while (i - k >= 0 && i + k < n && s[i - k] == s[i + k]) k++;
        d1[i] = k--;
        if (i + k > r) l = i - k, r = i + k;
    }
    for (int i = 0, l = 0, r = -1; i < n; i++) {
        int k = (i > r) ? 0 : min(d2[l + r - i + 1], r - i + 1);
        while (i - k - 1 >= 0 && i + k < n && s[i - k - 1] == s[i + k]) k++;
        d2[i] = k--;
        if (i + k > r) l = i - k - 1, r = i + k;
    }
    vector<int> ans(n, 0);
    int p = -1;                                           // ends 0..p are answered
    for (int C = 0; C <= 2 * n - 2; C++) {                // doubled centres in increasing order
        int reach;
        if (C % 2 == 0) reach = C / 2 + d1[C / 2] - 1;
        else { int i = (C + 1) / 2; if (d2[i] == 0) continue; reach = i + d2[i] - 1; }
        for (int e = p + 1; e <= reach; e++) ans[e] = 2 * e - C + 1;
        p = max(p, reach);
    }
    for (int e = 0; e < n; e++) cout << ans[e] << (e + 1 < n ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] s = in.next().toCharArray();
        int n = s.length;
        int[] d1 = new int[n], d2 = new int[n];
        for (int i = 0, l = 0, r = -1; i < n; i++) {
            int k = (i > r) ? 1 : Math.min(d1[l + r - i], r - i + 1);
            while (i - k >= 0 && i + k < n && s[i - k] == s[i + k]) k++;
            d1[i] = k--;
            if (i + k > r) { l = i - k; r = i + k; }
        }
        for (int i = 0, l = 0, r = -1; i < n; i++) {
            int k = (i > r) ? 0 : Math.min(d2[l + r - i + 1], r - i + 1);
            while (i - k - 1 >= 0 && i + k < n && s[i - k - 1] == s[i + k]) k++;
            d2[i] = k--;
            if (i + k > r) { l = i - k - 1; r = i + k; }
        }
        int[] ans = new int[n];
        int p = -1;
        for (int C = 0; C <= 2 * n - 2; C++) {
            int reach;
            if (C % 2 == 0) reach = C / 2 + d1[C / 2] - 1;
            else { int i = (C + 1) / 2; if (d2[i] == 0) continue; reach = i + d2[i] - 1; }
            for (int e = p + 1; e <= reach; e++) ans[e] = 2 * e - C + 1;
            p = Math.max(p, reach);
        }
        StringBuilder sb = new StringBuilder();
        for (int e = 0; e < n; e++) { if (e > 0) sb.append(' '); sb.append(ans[e]); }
        out.println(sb);
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
out:
1 1 3 1 3 5 7
-->
<!-- test
in:
aaaa
out:
1 2 3 4
-->
<!-- test
in:
abbac
out:
1 1 2 4 1
-->

</details>

### Example 3 — Prefix-Suffix Palindrome (Hard version) · ★ 1800

- **Source:** [CF 1326D2 · Prefix-Suffix Palindrome (Hard version)](https://codeforces.com/problemset/problem/1326/D2) — 1800
- **Difficulty:** 1800
- **Problem:** $t$ tests, $\sum |s| \le 10^6$. Find the longest palindrome $a + b$ where $a$ is a prefix of $s$, $b$ a suffix, and $|a| + |b| \le |s|$. Print any optimal one.
- **Thinking from first principles:** let $k$ be the largest value with $s[i] = s[n-1-i]$ for all $i < k$ and $2k \le n$. Claim: some optimal answer is $s[0..k) + P + s[n-k..n)$, where $P$ is the longer of the longest palindromic prefix and the longest palindromic suffix of the middle $m = s[k..n-k)$.
  *Proof.* Take an optimal $t = a b$ with $|a| = x \ge |b| = y$ (the other case is symmetric). Since $t$ is a palindrome, $a = \mathrm{rev}(b)\,c$ with $c = s[y..x)$ a palindrome, and $\mathrm{rev}(b) = s[0..y)$ forces $y \le k$. If $x \le k$ then $|t| \le 2k$, already achieved. Otherwise strip $k - y$ characters from both ends of $c$: $s[k..x+y-k)$ is still a palindrome, it starts at the beginning of $m$ and fits inside it (because $x + y \le n$). So the longest palindromic prefix of $m$ has length $\ge x + y - 2k$ and our construction is at least as long as $t$. $\square$
  Finding the longest palindromic prefix of $m$: the centres whose palindrome touches index 0 of $m$ — straight from $d_1$/$d_2$.

<details><summary>Solution</summary>

$O(n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int longestPalPrefix(const string& m) {
    int n = m.size(), best = 0;
    vector<int> d1(n), d2(n);
    for (int i = 0, l = 0, r = -1; i < n; i++) {
        int k = (i > r) ? 1 : min(d1[l + r - i], r - i + 1);
        while (i - k >= 0 && i + k < n && m[i - k] == m[i + k]) k++;
        d1[i] = k--;
        if (i + k > r) l = i - k, r = i + k;
        if (d1[i] == i + 1) best = max(best, 2 * i + 1);   // odd palindrome reaching index 0
    }
    for (int i = 0, l = 0, r = -1; i < n; i++) {
        int k = (i > r) ? 0 : min(d2[l + r - i + 1], r - i + 1);
        while (i - k - 1 >= 0 && i + k < n && m[i - k - 1] == m[i + k]) k++;
        d2[i] = k--;
        if (i + k > r) l = i - k - 1, r = i + k;
        if (i > 0 && d2[i] == i) best = max(best, 2 * i);   // even palindrome reaching index 0
    }
    return best;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        string s; cin >> s;
        int n = s.size(), k = 0;
        while (2 * (k + 1) <= n && s[k] == s[n - 1 - k]) k++;
        string mid = s.substr(k, n - 2 * k), rmid(mid.rbegin(), mid.rend());
        int pre = longestPalPrefix(mid), suf = longestPalPrefix(rmid);
        string P = pre >= suf ? mid.substr(0, pre) : mid.substr(mid.size() - suf);
        cout << s.substr(0, k) << P << s.substr(n - k) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int longestPalPrefix(char[] m) {
        int n = m.length, best = 0;
        int[] d1 = new int[n], d2 = new int[n];
        for (int i = 0, l = 0, r = -1; i < n; i++) {
            int k = (i > r) ? 1 : Math.min(d1[l + r - i], r - i + 1);
            while (i - k >= 0 && i + k < n && m[i - k] == m[i + k]) k++;
            d1[i] = k--;
            if (i + k > r) { l = i - k; r = i + k; }
            if (d1[i] == i + 1) best = Math.max(best, 2 * i + 1);
        }
        for (int i = 0, l = 0, r = -1; i < n; i++) {
            int k = (i > r) ? 0 : Math.min(d2[l + r - i + 1], r - i + 1);
            while (i - k - 1 >= 0 && i + k < n && m[i - k - 1] == m[i + k]) k++;
            d2[i] = k--;
            if (i + k > r) { l = i - k - 1; r = i + k; }
            if (i > 0 && d2[i] == i) best = Math.max(best, 2 * i);
        }
        return best;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            String s = in.next();
            int n = s.length(), k = 0;
            while (2 * (k + 1) <= n && s.charAt(k) == s.charAt(n - 1 - k)) k++;
            String mid = s.substring(k, n - k);
            String rmid = new StringBuilder(mid).reverse().toString();
            int pre = longestPalPrefix(mid.toCharArray()), suf = longestPalPrefix(rmid.toCharArray());
            String P = pre >= suf ? mid.substring(0, pre) : mid.substring(mid.length() - suf);
            out.println(s.substring(0, k) + P + s.substring(n - k));
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
5
a
abcdfdcecba
abbaxyzyx
codeforces
acbba
out:
a
abcdfdcba
xyzyx
c
abba
-->
<!-- test
in:
2
abccba
abcxyzyxba
out:
abccba
abxyzyxba
-->

</details>

### Example 4 — Palisection · ★ 2900

- **Source:** [CF 17E · Palisection](https://codeforces.com/problemset/problem/17/E) — 2900
- **Difficulty:** 2900
- **Problem:** $n \le 2\cdot 10^6$. Count unordered pairs of *different* palindromic substrings (as position intervals) that share at least one position, modulo $51123987$.
- **Thinking from first principles:** the number of palindromic substrings $P$ can be $\Theta(n^2)$, so pairs cannot be listed. Count the **complement**: pairs that are disjoint. Two intervals are disjoint iff one ends strictly before the other starts, and that ordered description counts each disjoint unordered pair exactly once. So
  $$\text{disjoint} = \sum_{j} \mathrm{start}[j] \cdot \#\{\text{palindromes ending at an index} < j\},\qquad \text{answer} = \binom{P}{2} - \text{disjoint}.$$
  $\mathrm{start}[j]$ and $\mathrm{end}[j]$ come from Manacher: centre $i$ contributes $+1$ to $\mathrm{start}$ on a contiguous range of indices (its nested palindromes start at consecutive positions) and $+1$ to $\mathrm{end}$ on another range — difference arrays, $O(n)$. This is the "palindromes starting/ending at each index" trick from §2 — the most reusable idea in this file.

<details><summary>Solution</summary>

$O(n)$ time; four `int` arrays of size $n$. All products reduced modulo $51123987$; $\binom{P}{2}$ is computed by halving the even factor first ($P$ fits in 64 bits).

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 51123987LL;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; string s;
    cin >> n >> s;
    vector<int> d1(n), d2(n);
    for (int i = 0, l = 0, r = -1; i < n; i++) {
        int k = (i > r) ? 1 : min(d1[l + r - i], r - i + 1);
        while (i - k >= 0 && i + k < n && s[i - k] == s[i + k]) k++;
        d1[i] = k--;
        if (i + k > r) l = i - k, r = i + k;
    }
    for (int i = 0, l = 0, r = -1; i < n; i++) {
        int k = (i > r) ? 0 : min(d2[l + r - i + 1], r - i + 1);
        while (i - k - 1 >= 0 && i + k < n && s[i - k - 1] == s[i + k]) k++;
        d2[i] = k--;
        if (i + k > r) l = i - k - 1, r = i + k;
    }
    vector<int> st(n + 1, 0), en(n + 1, 0);               // difference arrays
    long long P = 0;
    for (int i = 0; i < n; i++) {
        P += d1[i] + d2[i];
        st[i - d1[i] + 1]++; st[i + 1]--;                 // odd: starts in [i-d1+1, i]
        en[i]++; en[i + d1[i]]--;                         //      ends in [i, i+d1-1]
        if (d2[i]) {
            st[i - d2[i]]++; st[i]--;                     // even: starts in [i-d2, i-1]
            en[i]++; en[i + d2[i]]--;                     //       ends in [i, i+d2-1]
        }
    }
    for (int i = 1; i < n; i++) st[i] += st[i - 1], en[i] += en[i - 1];
    long long disjoint = 0, endedBefore = 0;
    for (int j = 0; j < n; j++) {
        disjoint = (disjoint + st[j] % MOD * endedBefore) % MOD;
        endedBefore = (endedBefore + en[j]) % MOD;
    }
    long long a = P, b = P - 1;
    if (a % 2 == 0) a /= 2; else b /= 2;
    long long total = (a % MOD) * (b % MOD) % MOD;
    cout << ((total - disjoint) % MOD + MOD) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final long MOD = 51123987L;
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        char[] s = in.next().toCharArray();
        int[] d1 = new int[n], d2 = new int[n];
        for (int i = 0, l = 0, r = -1; i < n; i++) {
            int k = (i > r) ? 1 : Math.min(d1[l + r - i], r - i + 1);
            while (i - k >= 0 && i + k < n && s[i - k] == s[i + k]) k++;
            d1[i] = k--;
            if (i + k > r) { l = i - k; r = i + k; }
        }
        for (int i = 0, l = 0, r = -1; i < n; i++) {
            int k = (i > r) ? 0 : Math.min(d2[l + r - i + 1], r - i + 1);
            while (i - k - 1 >= 0 && i + k < n && s[i - k - 1] == s[i + k]) k++;
            d2[i] = k--;
            if (i + k > r) { l = i - k - 1; r = i + k; }
        }
        int[] st = new int[n + 1], en = new int[n + 1];
        long P = 0;
        for (int i = 0; i < n; i++) {
            P += d1[i] + d2[i];
            st[i - d1[i] + 1]++; st[i + 1]--;
            en[i]++; en[i + d1[i]]--;
            if (d2[i] > 0) {
                st[i - d2[i]]++; st[i]--;
                en[i]++; en[i + d2[i]]--;
            }
        }
        for (int i = 1; i < n; i++) { st[i] += st[i - 1]; en[i] += en[i - 1]; }
        long disjoint = 0, endedBefore = 0;
        for (int j = 0; j < n; j++) {
            disjoint = (disjoint + st[j] % MOD * endedBefore) % MOD;
            endedBefore = (endedBefore + en[j]) % MOD;
        }
        long a = P, b = P - 1;
        if (a % 2 == 0) a /= 2; else b /= 2;
        long total = (a % MOD) * (b % MOD) % MOD;
        out.println(((total - disjoint) % MOD + MOD) % MOD);
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
4
babb
out:
6
-->
<!-- test
in:
2
aa
out:
2
-->
<!-- test
in:
1
a
out:
0
-->
<!-- test
in:
7
abacaba
out:
30
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Two conventions, never mix them.** $d_1[i]$ counts the centre itself ($d_1 \ge 1$); $d_2[i]$ is centred *before* $i$ ($d_2 \ge 0$). The mirror index is $l + r - i$ for $d_1$ and $l + r - i + 1$ for $d_2$.
2. **Transformed string separators** must not occur in $s$. If the alphabet is arbitrary, run Manacher on an `int` array with $-1$ as separator.
3. **Counts overflow `int`**: the number of palindromic substrings is up to $n(n+1)/2$ ($2\cdot 10^{12}$ for $n = 2\cdot 10^6$). Use 64-bit and reduce modulo where required.
4. **"Number of palindromic substrings" usually means occurrences** ($\sum d_1 + \sum d_2$). If the problem says *distinct*, that is at most $n$ and needs the [eertree](09-palindromic-tree-eertree.md) or hashing.
5. **Leftmost / rightmost / any.** Many judges accept any longest palindrome; when they do not, decide the tie-break explicitly (strict `>` keeps the leftmost in a left-to-right scan of centres ordered by start).
6. **Difference-array ranges** for "palindromes starting at $j$": odd centre $i$ gives $[i-d_1[i]+1, i]$, even centre $i$ gives $[i-d_2[i], i-1]$ — derive them once from the definitions; they are the source of most WA in Example 4-type problems.
7. **Memory at $n = 10^7$** (some problems): $d_1, d_2$ as `int` is 80 MB. The transformed version needs $2n+1$ ints. Reuse arrays or compute only what you need.
8. **Java**: read the string once into `char[]`; `String.charAt` in the inner loop is a bounds-checked call. Avoid recursion entirely (none is needed).
9. **Hashing alternative caveats**: two hashes per comparison and a $\log$ factor — at $n = 10^6$ that is $\approx 4\cdot 10^7$ mulmods, fine in C++, tight in Java.

## 7. Going further (toward 2400–2600+)

- **Palindromic tree (eertree)**: one node per distinct palindrome, suffix links, occurrence counts, and *series links* for $O(n\log n)$ palindromic factorisation DP — see [palindromic tree](09-palindromic-tree-eertree.md) and [CF 932G · Palindrome Partition](https://codeforces.com/problemset/problem/932/G) — 2900.
- **2D palindromes**: hash each candidate row segment into a symbol, then Manacher over the column sequence — [CF 1080E · Sonya and Matrix Beauty](https://codeforces.com/problemset/problem/1080/E) — 2400.
- **Even-palindrome decompositions**: the shortest even palindromic suffix ending at each index (from $d_2$) drives a linear DP — [CF 1827C · Palindrome Partition](https://codeforces.com/problemset/problem/1827/C) — 2600.
- **Palindromes combined with matching**: Manacher + KMP/hash to glue a palindrome between a prefix and a reversed suffix — [CF 30E · Tricky and Clever Password](https://codeforces.com/problemset/problem/30/E) — 2800.
- **Palindromes under point updates**: forward/backward hashes in a Fenwick or segment tree — [CSES 2420 · Palindrome Queries](https://cses.fi/problemset/task/2420).
- **Structure facts**: the palindromic suffixes of a string form $O(\log n)$ arithmetic progressions by length — the basis of series links and of several 2600+ problems.

For revision, the formulas and templates of this file are condensed in the [strings cheat sheet](../99-Cheat-Sheets/11-strings-cheatsheet.md).

## 8. Practice ladder

**≤ 1600**
- [ ] [CSES 1111 · Longest Palindrome](https://cses.fi/problemset/task/1111)
- [ ] [CSES 3138 · All Palindromes](https://cses.fi/problemset/task/3138)
- [ ] [CF 1326D1 · Prefix-Suffix Palindrome (Easy version)](https://codeforces.com/problemset/problem/1326/D1) — 1500
- [ ] [CF 159D · Palindrome pairs](https://codeforces.com/problemset/problem/159/D) — 1500

**1700–2000**
- [ ] [CF 1326D2 · Prefix-Suffix Palindrome (Hard version)](https://codeforces.com/problemset/problem/1326/D2) — 1800
- [ ] [CF 245H · Queries for Number of Palindromes](https://codeforces.com/problemset/problem/245/H) — 1800
- [ ] [CF 835D · Palindromic characteristics](https://codeforces.com/problemset/problem/835/D) — 1900

**2100–2400**
- [ ] [CF 7D · Palindrome Degree](https://codeforces.com/problemset/problem/7/D) — 2200
- [ ] [CSES 2420 · Palindrome Queries](https://cses.fi/problemset/task/2420) — ≈2100 (est.)
- [ ] [CF 1080E · Sonya and Matrix Beauty](https://codeforces.com/problemset/problem/1080/E) — 2400

**2500+**
- [ ] [CF 1827C · Palindrome Partition](https://codeforces.com/problemset/problem/1827/C) — 2600
- [ ] [CF 30E · Tricky and Clever Password](https://codeforces.com/problemset/problem/30/E) — 2800
- [ ] [CF 17E · Palisection](https://codeforces.com/problemset/problem/17/E) — 2900

## 9. LeetCode / FAANG cross-reference

- [LC 5 · Longest Palindromic Substring](https://leetcode.com/problems/longest-palindromic-substring/) — Medium — the interview classic: expand-around-centre $O(n^2)$ is expected, Manacher is the strong follow-up.
- [LC 647 · Palindromic Substrings](https://leetcode.com/problems/palindromic-substrings/) — Medium — $\sum d_1 + \sum d_2$.
- [LC 214 · Shortest Palindrome](https://leetcode.com/problems/shortest-palindrome/) — Hard — longest palindromic prefix (centres touching index 0).
- [LC 1960 · Maximum Product of the Length of Two Palindromic Substrings](https://leetcode.com/problems/maximum-product-of-the-length-of-two-palindromic-substrings/) — Hard — odd radii from Manacher, then best palindrome ending before / starting after each split (the Example 2 sweep, twice).
- [LC 131 · Palindrome Partitioning](https://leetcode.com/problems/palindrome-partitioning/) — Medium — backtracking with an $O(1)$ palindrome test.
- [LC 132 · Palindrome Partitioning II](https://leetcode.com/problems/palindrome-partitioning-ii/) — Hard — min-cut DP; enumerate palindromes by centre to make it $O(n^2)$.

## 10. Self-check

1. Define $d_1$ and $d_2$; compute them for `abba`.
2. Why does the mirror bound $\min(d_1[j], r-i+1)$ hold, and when is it exact?
3. Prove that Manacher is $O(n)$.
4. How many palindromic substrings (counted by position) does a string have, in terms of $d_1, d_2$?
5. Prove that a string has at most $n$ distinct non-empty palindromic substrings.
6. How do you get the number of palindromes *starting* at each index in $O(n)$?
7. How do you find the longest palindromic prefix with Manacher?

<details><summary>Answers</summary>

1. `abba`: $d_1 = 1,1,1,1$; $d_2 = 0,0,2,0$.
2. $[l,r]$ is a palindrome, so reflecting through its centre maps $s[j-x]$ to $s[i+x]$ and $s[j+x]$ to $s[i-x]$ while both stay inside $[l,r]$; a palindrome around $j$ inside the box reflects to one around $i$. If $d_1[j] < r-i+1$, the first mismatch around $j$ is also inside the box, so it reflects too and $d_1[i] = d_1[j]$.
3. Each successful extension compares a character beyond $r$ and then $r$ moves past it; $r$ only increases and is $< n$. Plus one failed comparison per centre: $O(n)$.
4. $\sum_i d_1[i] + \sum_i d_2[i]$.
5. When a character is appended, only the longest palindromic suffix can be new: every shorter palindromic suffix is a suffix — hence, by symmetry, also a prefix — of that longest one, so it occurred earlier. One new palindrome per character at most.
6. Each odd centre $i$ adds 1 on $[i-d_1[i]+1, i]$, each even centre adds 1 on $[i-d_2[i], i-1]$; do it with a difference array and prefix sums.
7. Take the centres whose palindrome reaches index 0: odd $i$ with $d_1[i] = i+1$ (length $2i+1$) and even $i$ with $d_2[i] = i$ (length $2i$); the maximum length is the answer.

</details>
