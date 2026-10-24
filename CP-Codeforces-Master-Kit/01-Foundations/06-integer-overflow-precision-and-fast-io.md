# Integer overflow, precision and fast I/O

> **Band:** 🟢 ≤ 1400 (and the cause of WA at every band) · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [complexity](01-complexity-and-constraint-reading.md), [environment & templates](../00-Roadmap-and-Strategy/06-environment-templates-cpp-java.md)
> **You can say you know this when:** before submitting you can bound every intermediate value and name its type, you compute floor/ceil division and remainders of negative numbers correctly in both languages, you replace floating-point comparisons with exact integer ones whenever possible, and your I/O never decides whether you get TLE.

## 1. First principles — why this works

**Fixed-width integers are arithmetic modulo $2^w$.** A 32-bit `int` stores values in $[-2^{31}, 2^{31})$; an operation whose true result leaves
that range wraps around (Java: defined wrap-around; C++: *undefined behaviour* for signed types — the optimiser may assume it never happens and
generate code that does something even stranger than wrapping). Overflow is never reported. The only defence is **bounding every intermediate
value from the constraints before writing the code**:

- $a_i \le 10^9$ and you multiply two of them: up to $10^{18}$ — needs 64 bits ($2^{63}\approx9.22\cdot10^{18}$).
- $n \le 2\cdot10^5$ values of $10^9$ summed: $2\cdot10^{14}$ — 64 bits.
- number of pairs $\binom n2$ for $n = 2\cdot10^5$: $\approx 2\cdot10^{10}$ — 64 bits.
- a product of three values $10^6\cdot10^6\cdot10^6 = 10^{18}$ — barely fits; one more factor of 10 does not.

**The type of an expression is decided by its operands, not by where you store it.** `long long x = a * b;` with `int a, b` multiplies in 32 bits
and then widens the already-wrong result. Same in Java. Force the wide type on the first operand: `1LL * a * b`, `(long) a * b`.

**Floating point is a finite set of binary fractions.** A `double` has a 53-bit significand: integers are exact only up to $2^{53}\approx9.0\cdot10^{15}$,
relative rounding error per operation is up to $2^{-53}\approx1.1\cdot10^{-16}$, and decimal numbers like 0.1 are not representable. Two
consequences decide most precision bugs:

1. **Exact questions need exact arithmetic.** "Is $p_1/q_1 < p_2/q_2$?" with values up to $10^9$ can differ by $10^{-18}$ — far below double
   resolution near 1. Cross-multiply instead: $p_1q_2 < p_2q_1$ (for positive denominators), exact in 64-bit integers (Example 4).
2. **Subtracting nearly equal numbers destroys relative precision** (catastrophic cancellation). Rearrange formulas to avoid it, or compare
   with a tolerance chosen from the problem's scale.

**Integer division truncates toward zero in C++ and Java** ($-7/2 = -3$, $-7 \% 2 = -1$), but mathematics (and Python) floors. Whenever a dividend
can be negative — coordinates, differences, "$i + a_i$" — you must normalise explicitly (Example 3).

**I/O is part of the running time.** Reading $10^6$ numbers with C++ streams *synchronised with C stdio*, or with Java's `Scanner`, can take longer
than the algorithm. The fix costs one line in C++ (`ios::sync_with_stdio(false); cin.tie(nullptr);`) and one small class in Java (a buffered
byte reader). Output is the same story: flush once, not per line — except in interactive problems, where you **must** flush after every query.

## 2. Formulas, definitions and identities

**Type ranges.**

| Type | Bits | Range / precision | Notes |
|---|---|---|---|
| `int`, Java `int` | 32 | $[-2147483648,\ 2147483647]\approx\pm2.1\cdot10^9$ | `INT_MAX`, `Integer.MAX_VALUE` |
| `unsigned int` | 32 | $[0, 4294967295]\approx4.3\cdot10^9$ | no Java equivalent (use `long` or `Integer.toUnsignedLong`) |
| `long long`, Java `long` | 64 | $\approx\pm9.22\cdot10^{18}$ | $2^{63}-1 = 9223372036854775807$ |
| `unsigned long long` | 64 | $[0,\ \approx1.84\cdot10^{19}]$ | Java: `Long.compareUnsigned`, `Long.divideUnsigned` |
| `__int128` (GCC, 64-bit targets only) | 128 | $\approx\pm1.7\cdot10^{38}$ | no `cin`/`cout` support: print manually; Java: `BigInteger` or `Math.multiplyHigh` |
| `float` | 32 | 24-bit significand, ~7 decimal digits | avoid |
| `double` | 64 | 53-bit significand, ~15–16 digits; exact integers $\le 2^{53}$ | Java `double` identical |
| `long double` (GCC on x86) | 80 | 64-bit significand, ~18–19 digits; exact integers $\le 2^{64}$ | MSVC: same as `double` |
| Java `char` / `byte` / `short` | 16 / 8 / 16 | $[0,65535]$ / $[-128,127]$ / $[-32768,32767]$ | `byte` is signed! |

On Codeforces, `__int128` works with the 64-bit G++ compilers (the command-lines post lists "GNU G++20 11.2.0 (64 bit, winlibs)" and
"GNU G++23 14.2 (64 bit, msys 2)") but not with the 32-bit "GNU G++17 7.3.0"; `long double` is 80-bit under MinGW G++ (standard knowledge,
not verified in this research).

**Landmarks that fit in signed 64 bits.** $20! \approx 2.43\cdot10^{18}$ (21! does not); Fibonacci $F_{92}\approx7.5\cdot10^{18}$ ($F_{93}$ does not);
$\binom{66}{33}\approx7.2\cdot10^{18}$; $10^{18}$ and $2\cdot10^{18}$ yes, $10^{19}$ no (but it fits in `unsigned long long`).

**Safe "infinity".** Choose `INF` so that `INF + INF` still fits: `const long long INF = 1e18;` (or `LLONG_MAX / 4`) for 64-bit DP;
`0x3f3f3f3f` ($\approx1.06\cdot10^9$) for 32-bit values set with `memset` byte patterns.

**Division and remainder with negative numbers** ($b > 0$ unless stated; in C++ and Java `a / b` truncates toward zero and `a % b` has the sign of $a$):

$$\left\lfloor \frac ab \right\rfloor = \texttt{a / b} - [\texttt{a \% b} \ne 0 \land (a<0) \ne (b<0)], \qquad \left\lceil \frac ab\right\rceil = \texttt{a / b} + [\texttt{a \% b} \ne 0 \land (a<0) = (b<0)],$$

$$a \bmod m \in [0, m):\quad ((a \% m) + m) \% m, \qquad (a - b) \bmod m = (a - b + m) \% m \ \ (0\le a,b<m).$$

For non-negative $a$ and positive $b$: $\lceil a/b\rceil = (a + b - 1)/b$ (beware overflow when $a$ is near the type's maximum). Java provides
`Math.floorDiv`, `Math.floorMod` (Java 8+) and `Math.ceilDiv` (Java 18+).

**Rounding.** `(long long)x` truncates toward zero; `floor`, `ceil`, `llround` round as named; `(long long)(x + 0.5)` is wrong for negative $x$.

**Overflow-checked arithmetic.** GCC/Clang: `__builtin_add_overflow(a, b, &r)`, `__builtin_mul_overflow(a, b, &r)` return `true` on overflow.
Java: `Math.addExact`, `Math.multiplyExact`, `Math.toIntExact` throw `ArithmeticException`. Pre-check without builtins: for $a, b > 0$,
$a\cdot b > L \iff a > \lfloor L/b \rfloor$.

**Exact comparisons.** For $b, d > 0$: $\frac ab < \frac cd \iff ad < cb$. With $|a|,|c|\le10^9$ and $b,d\le10^9$ the products are $\le10^{18}$ (64-bit);
with values up to $10^{18}$ use `__int128` / `Math.multiplyHigh` / `BigInteger`. To compare $\sqrt x$ with an integer $k\ge0$: $\sqrt x < k \iff x < k^2$.

**Floating comparisons.** If exactness is impossible, compare $|a-b| \le \varepsilon\cdot\max(1, |a|, |b|)$ (mixed absolute/relative tolerance).
Typical $\varepsilon$ between $10^{-9}$ and $10^{-6}$; it must be smaller than the smallest true difference you need to detect and larger than the
accumulated rounding error.

**Precision of `sqrt` on large integers.** `sqrt` of a 64-bit value goes through `double`: `(long long)sqrt(999999999999999999)` gives
$10^9$, but the true floor square root is $999999999$. Always correct the result with integer checks (§3).

## 3. Implementation (C++ and Java)

### 3.1 Division, remainders, roots, safe products

```cpp
ll floorDiv(ll a, ll b) { return a / b - ((a % b != 0) && ((a < 0) != (b < 0))); }
ll ceilDiv(ll a, ll b) { return a / b + ((a % b != 0) && ((a < 0) == (b < 0))); }
ll normMod(ll a, ll m) { a %= m; return a < 0 ? a + m : a; }

ll isqrtFloor(ll x) {                         // largest r with r*r <= x, for 0 <= x <= 9e18
    ll r = (ll)sqrtl((ld)x);
    while (r > 0 && (__int128)r * r > x) r--;
    while ((__int128)(r + 1) * (r + 1) <= x) r++;
    return r;
}

ll mulmod(ll a, ll b, ll m) { return (ll)((__int128)a * b % m); }   // 0 <= a, b < m <= 9e18

bool mulOverflows(ll a, ll b, ll& out) { return __builtin_mul_overflow(a, b, &out); }

string toString128(__int128 x) {              // cout cannot print __int128
    if (x == 0) return "0";
    bool neg = x < 0;
    unsigned __int128 u = neg ? -(unsigned __int128)x : (unsigned __int128)x;
    string s;
    while (u > 0) { s += char('0' + (int)(u % 10)); u /= 10; }
    if (neg) s += '-';
    reverse(s.begin(), s.end());
    return s;
}
```

```java
static long floorDiv(long a, long b) { return Math.floorDiv(a, b); }
static long ceilDiv(long a, long b) { return -Math.floorDiv(-a, b); }      // Math.ceilDiv exists from Java 18
static long normMod(long a, long m) { return Math.floorMod(a, m); }

static long isqrtFloor(long x) {                // 0 <= x <= Long.MAX_VALUE
    long r = (long) Math.sqrt((double) x);
    while (r > 0 && r > x / r) r--;             // r*r > x, tested without overflow
    while ((r + 1) <= x / (r + 1)) r++;         // (r+1)^2 <= x
    return r;
}

static long mulmod(long a, long b, long m) {    // 0 <= a, b < m < 2^62, no 128-bit type needed
    long res = 0;
    a %= m;
    while (b > 0) {
        if ((b & 1) == 1) { res += a; if (res >= m) res -= m; }
        a += a; if (a >= m) a -= m;             // a < 2^62, so a + a cannot overflow
        b >>= 1;
    }
    return res;
}

static long mulExactOrClamp(long a, long b, long cap) {   // min(a*b, cap) for a, b >= 0
    try { return Math.min(Math.multiplyExact(a, b), cap); }
    catch (ArithmeticException e) { return cap; }
}
```

`mulmod` by doubling costs $O(\log b)$; it is only needed for 64-bit moduli (Miller–Rabin, Pollard rho in
[number theory](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)). For moduli below $2^{31}$ a plain `long` product is exact.

**Decimal input without floating point.** When the input has a fixed number of decimal places ("prices with two decimals",
"coordinates with at most 3 digits after the point") and the answer needs exact comparisons, parse the text straight into scaled integers:

```cpp
// "12.5" with scale 3 -> 12500; "-0.075" -> -75. Assumes at most `scale` digits after the point.
ll parseFixed(const string& s, int scale) {
    ll intPart = 0, frac = 0;
    int i = 0, fracDigits = 0;
    bool neg = s[0] == '-';
    if (neg || s[0] == '+') i++;
    for (; i < (int)s.size() && s[i] != '.'; i++) intPart = intPart * 10 + (s[i] - '0');
    if (i < (int)s.size()) for (i++; i < (int)s.size(); i++, fracDigits++) frac = frac * 10 + (s[i] - '0');
    for (; fracDigits < scale; fracDigits++) frac *= 10;
    ll pow10 = 1;
    for (int k = 0; k < scale; k++) pow10 *= 10;
    ll v = intPart * pow10 + frac;
    return neg ? -v : v;
}
```

```java
static long parseFixed(String s, int scale) {        // same contract; BigDecimal does it in one line, more slowly:
    // new java.math.BigDecimal(s).movePointRight(scale).longValueExact()
    long intPart = 0, frac = 0;
    int i = 0, fracDigits = 0;
    boolean neg = s.charAt(0) == '-';
    if (neg || s.charAt(0) == '+') i++;
    for (; i < s.length() && s.charAt(i) != '.'; i++) intPart = intPart * 10 + (s.charAt(i) - '0');
    if (i < s.length()) for (i++; i < s.length(); i++, fracDigits++) frac = frac * 10 + (s.charAt(i) - '0');
    for (; fracDigits < scale; fracDigits++) frac *= 10;
    long pow10 = 1;
    for (int k = 0; k < scale; k++) pow10 *= 10;
    long v = intPart * pow10 + frac;
    return neg ? -v : v;
}
```

**`BigInteger` and `BigDecimal` (Java).** `BigInteger` gives exact integers of any size (Example 6) — fine for $10^5$–$10^6$ operations on
numbers of a few machine words, too slow for heavy loops. `BigDecimal` gives exact *decimal* arithmetic: exact parsing of `"0.1"`, exact sums and
products, and division with an explicit `MathContext`/scale and rounding mode. Use it for the rare problem that needs exact decimal output or
huge-precision intermediate values; in C++ the equivalent is usually scaled integers or `__int128`.

### 3.2 Fast input and output

**C++.** `ios::sync_with_stdio(false); cin.tie(nullptr);` makes `cin`/`cout` fast enough for $\sim10^6$–$10^7$ tokens. Never mix
`scanf`/`printf` with `cin`/`cout` after turning sync off. For the largest inputs, a `fread`-based reader is several times faster still
(`getchar_unlocked` is a POSIX function and is not available on the Windows judge):

```cpp
static char ibuf[1 << 25];                    // 32 MB: enough for most inputs; raise it if needed
size_t ilen = 0, ipos = 0;

void readAll() { ilen = fread(ibuf, 1, sizeof(ibuf), stdin); }

ll readLL() {
    while (ipos < ilen && (ibuf[ipos] < '0' || ibuf[ipos] > '9') && ibuf[ipos] != '-') ipos++;
    bool neg = false;
    if (ipos < ilen && ibuf[ipos] == '-') { neg = true; ipos++; }
    ll x = 0;
    while (ipos < ilen && ibuf[ipos] >= '0' && ibuf[ipos] <= '9') x = x * 10 + (ibuf[ipos++] - '0');
    return neg ? -x : x;
}

// The same parser one character at a time with getchar(): simpler, no big buffer, slower than fread
// (and never mix it with cin after ios::sync_with_stdio(false)).
ll readLLGetchar() {
    int c = getchar();
    while (c != EOF && c != '-' && (c < '0' || c > '9')) c = getchar();
    bool neg = c == '-';
    if (neg) c = getchar();
    ll x = 0;
    while (c >= '0' && c <= '9') { x = x * 10 + (c - '0'); c = getchar(); }
    return neg ? -x : x;
}
```

**Java.** `Scanner` parses with regular expressions — roughly an order of magnitude slower than a byte reader (standard knowledge). Options:

- a `DataInputStream`-based byte reader (the kit's `FastReader`, full version in
  [environment & templates](../00-Roadmap-and-Strategy/06-environment-templates-cpp-java.md)) — handles `int`, `long`, strings;
- `BufferedReader` + `StringTokenizer` — fine for most problems;
- `StreamTokenizer` — fast, but it converts every number to a `double` (`nval`), so it is **only safe for values up to $2^{53}$**: a 64-bit input such as
  `999999999999999999` comes back as `1.0000000000000001E18`, i.e. `1000000000000000128` after the cast (checked with JDK 21).
  Use it for `int` input only.

```java
static int[] readIntsStreamTokenizer(int n) throws IOException {   // ints only: nval is a double
    StreamTokenizer st = new StreamTokenizer(new BufferedInputStream(System.in));
    int[] a = new int[n];
    for (int i = 0; i < n; i++) { st.nextToken(); a[i] = (int) st.nval; }
    return a;
}

static void outputPatterns(long[] ans) {
    PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out), 1 << 16));
    StringBuilder sb = new StringBuilder();
    for (long x : ans) sb.append(x).append(' ');
    out.println(sb.toString().trim());
    out.flush();                     // forget this and nothing is printed
}
```

**Interactive problems.** After printing a query, flush: C++ `cout << "? " << x << endl;` (`endl` flushes) or `cout.flush()`; Java
`out.println(...); out.flush();`. Read the reply only after flushing. Buffered output without flushes leads to "Idleness limit exceeded"
([interactive problems](../03-Greedy-Constructive-Interactive/05-interactive-problems.md)).

**Printing floating-point answers.** C++: `cout << fixed << setprecision(10) << x;`; Java: `out.printf("%.10f%n", x);` — and remember Java's
`printf` uses the default locale: on a machine with a comma decimal separator it prints `0,5`. The Java command lines in the Codeforces post set no
locale (only the Kotlin ones pass `-Duser.language=en`), so do not depend on the default: use `String.format(Locale.US, ...)` / `out.printf(Locale.US, ...)`.

## 4. Recognising the pattern

| Signal | Risk / action |
|---|---|
| values up to $10^9$ multiplied, or summed over $10^5$+ items | 64-bit accumulators; `1LL *` / `(long)` on the first operand |
| "print the answer modulo $10^9+7$" with subtraction anywhere | add `MOD` before `%`; normalise at the end |
| coordinates or differences that can be negative, then `/` or `%` | floor/ceil helpers, `floorMod` (Example 3) |
| comparing ratios, slopes, averages | cross-multiplication (Examples 4–5) |
| "print with absolute or relative error $\le10^{-6}$" | floating point is intended; still prefer exact intermediate steps |
| answer can exceed $9\cdot10^{18}$ | `unsigned long long`, `__int128`, `BigInteger` (Example 6) |
| $10^6$+ input numbers or tight TL | fast reader; one output buffer |
| interactive problem | flush after every query |
| `sqrt`, `pow`, `log2` on integers | integer-corrected versions; bit operations for powers of two |

## 5. Worked examples (graded)

### Example 1 — Theatre Square  ·  ★ 1000

- **Source:** [CF 1A · Theatre Square](https://codeforces.com/problemset/problem/1/A) — 1000
- **Difficulty:** 1000
- **Problem:** Cover an $n\times m$ rectangle with $a\times a$ flagstones (may stick out, no cutting), $n, m, a\le10^9$. Minimum number of stones.
- **Thinking from first principles:** each dimension independently needs $\lceil n/a\rceil$ and $\lceil m/a\rceil$ stones; the answer is the product, up to
  $10^9\cdot10^9 = 10^{18}$ — a 32-bit product overflows on the worst case. Ceil division without floating point: $(n + a - 1)/a$ (safe: $n + a\le 2\cdot10^9$
  fits in 64 bits).

<details><summary>Solution</summary>

64-bit arithmetic throughout. $O(1)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    long long n, m, a;
    cin >> n >> m >> a;
    cout << ((n + a - 1) / a) * ((m + a - 1) / a) << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        long n = Long.parseLong(st.nextToken()), m = Long.parseLong(st.nextToken()), a = Long.parseLong(st.nextToken());
        System.out.println(((n + a - 1) / a) * ((m + a - 1) / a));
    }
}
```

</details>

<!-- test
in:
1000000000 1000000000 1
out:
1000000000000000000
-->
<!-- test
in:
5 7 3
out:
6
-->
<!-- test
in:
1 1 1000000000
out:
1
-->

### Example 2 — Pashmak and Flowers  ·  ★ 1300

- **Source:** [CF 459B · Pashmak and Flowers](https://codeforces.com/problemset/problem/459/B) — 1300
- **Difficulty:** 1300
- **Problem:** Given $n\le2\cdot10^5$ beauties $b_i\le10^9$, output the maximum difference between two chosen flowers and the number of
  (unordered) pairs achieving it.
- **Thinking from first principles:** the maximum difference is $\max - \min$; the pairs are (any maximum, any minimum): $c_{\max}\cdot c_{\min}$.
  The edge case is $\max = \min$: then any two flowers form a pair, $\binom n2 = n(n-1)/2\approx2\cdot10^{10}$ — this is the overflow trap, and the
  product $c_{\max}c_{\min}$ ($\le 10^{10}$) overflows too.

<details><summary>Solution</summary>

One pass for min, max and their counts; 64-bit counts. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    long long n;
    cin >> n;
    vector<long long> b(n);
    for (auto& x : b) cin >> x;
    long long mn = *min_element(b.begin(), b.end()), mx = *max_element(b.begin(), b.end());
    long long cmn = count(b.begin(), b.end(), mn), cmx = count(b.begin(), b.end(), mx);
    long long pairs = (mn == mx) ? n * (n - 1) / 2 : cmn * cmx;
    cout << mx - mn << ' ' << pairs << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long mn = Long.MAX_VALUE, mx = Long.MIN_VALUE, cmn = 0, cmx = 0;
        long[] b = new long[n];
        for (int i = 0; i < n; i++) { b[i] = in.nextLong(); mn = Math.min(mn, b[i]); mx = Math.max(mx, b[i]); }
        for (long x : b) { if (x == mn) cmn++; if (x == mx) cmx++; }
        long pairs = (mn == mx) ? (long) n * (n - 1) / 2 : cmn * cmx;   // (long) BEFORE the multiplication
        System.out.println((mx - mn) + " " + pairs);
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
2
1 2
out:
1 1
-->
<!-- test
in:
5
3 1 2 3 1
out:
2 4
-->
<!-- test
in:
4
7 7 7 7
out:
0 6
-->
<!-- test
in:
1
5
out:
0 0
-->

### Example 3 — Hilbert's Hotel  ·  ★ 1600

- **Source:** [CF 1344A · Hilbert's Hotel](https://codeforces.com/problemset/problem/1344/A) — 1600
- **Difficulty:** 1600
- **Problem:** Rooms are all integers, one guest each. Given $a_0..a_{n-1}$ ($|a_i|\le10^9$, $\sum n\le2\cdot10^5$), the guest in room $k$ moves to
  $k + a_{k \bmod n}$. Is the result still exactly one guest per room?
- **Thinking from first principles:** rooms $k$ and $k+n$ use the same $a$ and move by the same amount, so the map shifts each residue class mod $n$
  rigidly: class $i$ goes to class $(i + a_i) \bmod n$. The map is a bijection iff these $n$ target classes are all distinct (each class is then hit by a
  shifted copy of itself, which covers it exactly once). Implementation trap: $i + a_i$ is often negative, and `%` in C++/Java returns a negative
  remainder — normalise.

<details><summary>Solution</summary>

Mark $((i + a_i) \bmod n + n) \bmod n$ for every $i$; answer YES iff no class is marked twice. $O(n)$.

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
        vector<char> hit(n, 0);
        bool ok = true;
        for (int i = 0; i < n; i++) {
            long long a;
            cin >> a;
            long long r = ((i + a) % n + n) % n;          // C++ % keeps the sign of the dividend
            if (hit[r]) ok = false;
            hit[r] = 1;
        }
        cout << (ok ? "YES" : "NO") << '\n';
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
            boolean[] hit = new boolean[n];
            boolean ok = true;
            for (int i = 0; i < n; i++) {
                long a = in.nextLong();
                int r = (int) Math.floorMod(i + a, (long) n);   // floorMod is always in [0, n)
                if (hit[r]) ok = false;
                hit[r] = true;
            }
            out.println(ok ? "YES" : "NO");
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
6
1
14
2
1 -1
2
0 1
3
-3 -2 -1
3
1000000000 -1000000000 0
3
0 0 1
out:
YES
YES
NO
YES
YES
NO
-->

### Example 4 — Sorting Fractions Exactly  ·  ★ ≈1400 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈1400 (est.)
- **Problem:** $n\le2\cdot10^5$ fractions $p_i/q_i$ with $|p_i|\le10^9$, $1\le|q_i|\le10^9$. Print the indices (1-based) in increasing order of value,
  equal values by increasing index.
- **Thinking from first principles:** sorting by `(double)p/q` looks fine and fails: $\frac{999999999}{1000000000}$ and $\frac{999999998}{999999999}$
  differ by about $10^{-18}$, and both round to the **same** `double` (checked while writing this file), so the tie-break puts them in the wrong
  order. Exact comparison: make every denominator positive (negate both parts if $q<0$), then $\frac ab<\frac cd \iff ad < cb$, and
  $|ad|\le10^{18}$ fits in a signed 64-bit integer. The comparator is a strict weak ordering because it compares the exact rational values.

<details><summary>Solution</summary>

Normalise signs, sort indices with the cross-multiplication comparator, break ties by index. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> p(n), q(n);
    for (int i = 0; i < n; i++) {
        cin >> p[i] >> q[i];
        if (q[i] < 0) { p[i] = -p[i]; q[i] = -q[i]; }       // denominators positive
    }
    vector<int> idx(n);
    iota(idx.begin(), idx.end(), 0);
    sort(idx.begin(), idx.end(), [&](int i, int j) {
        long long lhs = p[i] * q[j], rhs = p[j] * q[i];      // |value| <= 1e18: exact
        if (lhs != rhs) return lhs < rhs;
        return i < j;
    });
    for (int k = 0; k < n; k++) cout << idx[k] + 1 << (k + 1 < n ? ' ' : '\n');
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] p = new long[n], q = new long[n];
        for (int i = 0; i < n; i++) {
            p[i] = in.nextLong(); q[i] = in.nextLong();
            if (q[i] < 0) { p[i] = -p[i]; q[i] = -q[i]; }
        }
        Integer[] idx = new Integer[n];
        for (int i = 0; i < n; i++) idx[i] = i;
        Arrays.sort(idx, (i, j) -> {
            int c = Long.compare(p[i] * q[j], p[j] * q[i]);
            return c != 0 ? c : Integer.compare(i, j);
        });
        StringBuilder sb = new StringBuilder();
        for (int k = 0; k < n; k++) sb.append(idx[k] + 1).append(k + 1 < n ? ' ' : '\n');
        System.out.print(sb);
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
2
999999999 1000000000
999999998 999999999
out:
2 1
-->
<!-- test
in:
5
1 2
-1 -2
2 -4
0 5
1000000000 1
out:
3 4 1 2 5
-->
<!-- test
in:
1
-7 3
out:
1
-->

### Example 5 — Mixing Water  ·  ★ 1700

- **Source:** [CF 1359C · Mixing Water](https://codeforces.com/problemset/problem/1359/C) — 1700
- **Difficulty:** 1700
- **Problem:** Hot water has temperature $h$, cold $c$ ($1\le c<h\le10^6$). You pour cups alternately hot, cold, hot, … (at least one); the result is
  the average. For a target $t\in[c,h]$, output the smallest number of cups whose average is as close as possible to $t$. Up to $3\cdot10^4$ tests.
- **Thinking from first principles:** even counts always average exactly $\frac{h+c}2$. With $2m+1$ cups the average is
  $T(m) = \frac{(m+1)h+mc}{2m+1}$, which decreases from $h$ (at $m=0$) toward $\frac{h+c}2$. So if $2t\le h+c$, every odd average is above $\frac{h+c}2\ge t$
  and 2 cups are best. Otherwise solve $T(m)=t$: $m^\* = \frac{h-t}{2t-h-c}$; the best odd count is at $\lfloor m^\*\rfloor$ or $\lfloor m^\*\rfloor+1$ (monotonicity),
  and 2 cups can never win (the second candidate is already between $\frac{h+c}2$ and $t$). The two candidates can differ from $t$ by amounts that
  agree to ~12 significant digits, so comparing them with `double` is risky: compare $|T(m)-t| = \frac{|m(h+c-2t)+h-t|}{2m+1}$ exactly by
  cross-multiplication (numerators $\le10^6$, denominators $\le 2\cdot10^6+1$: products $\le 2\cdot10^{12}$).

<details><summary>Solution</summary>

Cases: $2t\le h+c\Rightarrow 2$. Else $m_0=\lfloor(h-t)/(2t-h-c)\rfloor$; choose $m_0$ unless $m_0+1$ is strictly closer; answer $2m+1$. $O(1)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int T;
    cin >> T;
    while (T--) {
        long long h, c, t;
        cin >> h >> c >> t;
        if (2 * t <= h + c) { cout << 2 << '\n'; continue; }
        long long m0 = (h - t) / (2 * t - h - c);
        // distance of T(m) from t, as numerator/denominator
        auto num = [&](long long m) { return llabs(m * (h + c - 2 * t) + h - t); };
        long long n0 = num(m0), d0 = 2 * m0 + 1, n1 = num(m0 + 1), d1 = 2 * m0 + 3;
        long long m = (n1 * d0 < n0 * d1) ? m0 + 1 : m0;      // strictly closer wins; ties keep fewer cups
        cout << 2 * m + 1 << '\n';
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
        int T = in.nextInt();
        while (T-- > 0) {
            long h = in.nextLong(), c = in.nextLong(), t = in.nextLong();
            if (2 * t <= h + c) { out.println(2); continue; }
            long m0 = (h - t) / (2 * t - h - c);
            long n0 = Math.abs(m0 * (h + c - 2 * t) + h - t), d0 = 2 * m0 + 1;
            long n1 = Math.abs((m0 + 1) * (h + c - 2 * t) + h - t), d1 = 2 * m0 + 3;
            long m = (n1 * d0 < n0 * d1) ? m0 + 1 : m0;
            out.println(2 * m + 1);
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
7
30 10 20
30 10 30
100 1 60
50 20 36
7 3 6
1000 999 1000
1000000 1 500001
out:
2
1
5
15
3
1
999999
-->

### Example 6 — Exact Big Sum  ·  ★ ≈1200 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈1200 (est.)
- **Problem:** Print the exact sum of $n\le2\cdot10^5$ integers with $|a_i|\le10^{18}$.
- **Thinking from first principles:** the sum can reach $2\cdot10^{23}$ in absolute value — beyond 64 bits. Three exact options: C++ `__int128`
  (64-bit G++ only) with a hand-written printer; Java `BigInteger` (simple, fast enough for $2\cdot10^5$ additions); or two 64-bit limbs in base $10^{18}$.
  Reading the numbers is the other trap: a `double`-based reader (`StreamTokenizer`) would already corrupt each input.

<details><summary>Solution</summary>

Accumulate in a 128-bit integer / `BigInteger`. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

string toString128(__int128 x) {
    if (x == 0) return "0";
    bool neg = x < 0;
    unsigned __int128 u = neg ? -(unsigned __int128)x : (unsigned __int128)x;
    string s;
    while (u > 0) { s += char('0' + (int)(u % 10)); u /= 10; }
    if (neg) s += '-';
    reverse(s.begin(), s.end());
    return s;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    __int128 sum = 0;
    for (int i = 0; i < n; i++) { long long a; cin >> a; sum += a; }
    cout << toString128(sum) << '\n';
}
```

```java
import java.io.*;
import java.math.BigInteger;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        BigInteger sum = BigInteger.ZERO;
        long chunk = 0;                                  // add into a long until it would overflow, then flush to BigInteger
        for (int i = 0; i < n; i++) {
            long a = in.nextLong();
            long s = chunk + a;
            if (((chunk ^ s) & (a ^ s)) < 0) { sum = sum.add(BigInteger.valueOf(chunk)); s = a; }   // signed overflow test
            chunk = s;
        }
        sum = sum.add(BigInteger.valueOf(chunk));
        System.out.println(sum);
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
1000000000000000000 1000000000000000000 1000000000000000000
out:
3000000000000000000
-->
<!-- test
in:
12
1000000000000000000 1000000000000000000 1000000000000000000 1000000000000000000 1000000000000000000 1000000000000000000 1000000000000000000 1000000000000000000 1000000000000000000 1000000000000000000 1000000000000000000 1
out:
11000000000000000001
-->
<!-- test
in:
4
-1000000000000000000 -1000000000000000000 -1000000000000000000 -999999999999999999
out:
-3999999999999999999
-->
<!-- test
in:
2
5 -5
out:
0
-->

The overflow test `((chunk ^ s) & (a ^ s)) < 0` works because a signed addition overflows exactly when both operands have the same sign and the
result's sign differs — then `s` disagrees in sign with both `chunk` and `a`.

## 6. Tricks, pitfalls and things to remember

1. **`int * int` stays `int`.** `long long x = a * b;` overflows before the assignment; write `1LL * a * b` / `(long) a * b`. In Java,
   `(long) (a * b)` is still wrong — the cast must apply to an operand.
2. **`mid = (lo + hi) / 2` overflows** for large bounds; use `lo + (hi - lo) / 2` (C++) or `(lo + hi) >>> 1` (Java, non-negative values).
3. **`abs(INT_MIN)`/`Math.abs(Integer.MIN_VALUE)`** is negative; `-x` overflows for the minimum value.
4. **`%` of a negative number is negative** in C++ and Java. Normalise: `((a % m) + m) % m`, `Math.floorMod`.
5. **Modular subtraction**: `(a - b) % MOD` can be negative; add `MOD` first. Modular multiplication of two values below $\approx10^9$ fits in
   64 bits; three factors do not — reduce after each multiplication.
6. **`1 << 40`** is an `int` shift; Java silently computes `1 << 8` (see [bit manipulation](03-bit-manipulation.md)).
7. **`pow(a, b)` returns a `double`**: `pow(10, 18)` is not guaranteed to convert to exactly $10^{18}$, and `(int)pow(5, 2)` has been reported to give 24 with
   some old MinGW versions. Use integer loops or binary exponentiation.
8. **`sqrt`/`cbrt`/`log2` of large integers** are off by one at boundaries; correct with integer checks (§3).
9. **Floating equality**: never `==` on computed doubles; but also never use an $\varepsilon$ where an exact integer formulation exists.
10. **Accumulated error**: summing $10^6$ doubles of very different magnitudes loses digits; sort by magnitude or use `long double` / exact integers.
11. **`INF + INF` overflow** in DP relaxations (`dist[u] + w` with `dist[u] = LLONG_MAX`): pick `INF = 1e18` or check before adding.
12. **Java `Scanner` and `System.out.println` in loops** are the two classic Java TLE causes; `String.format`/`printf` in a loop is also slow.
13. **`StreamTokenizer` loses 64-bit precision** (it parses into `double`); use it for `int` input only.
14. **`endl` flushes** (slow in normal problems, required in interactive ones); `'\n'` does not.
15. **Locale**: Java `printf("%.3f")` may print a comma on a non-English machine; use `Locale.US` when testing locally.
16. **`unsigned` comparisons**: `-1 < 1u` is false in C++ (the `-1` converts to $2^{32}-1$); avoid mixing signed and unsigned, including `v.size()`.
17. **`cin >> double` is slow on MinGW** (the Windows toolchain behind Codeforces' G++): $4\cdot10^5$ doubles took about 1.2 s in this kit's
    tests versus 0.2 s for the same values read as integers. If the input is integral, read `long long` and convert; otherwise read the token
    and call `strtod`. Java's `Double.parseDouble` on tokens is fine. Details: [ternary search & meet in the middle, pitfall 12](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md).

## 7. Going further (toward 2400–2600+)

- **Modular arithmetic and inverses**, Montgomery/Barrett reduction for speed — [modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md).
- **64-bit modular multiplication** in Miller–Rabin / Pollard rho — [Miller–Rabin & Pollard rho](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md).
- **Exact geometry**: integer cross products, avoiding `atan2`, when `long double` is enough — [vectors & precision](../14-Geometry/01-vectors-dot-cross-and-precision.md).
- **FFT precision** (double-based FFT for large values, splitting into 15-bit pieces) vs NTT — [FFT & NTT](../15-Advanced-Math/03-fft-and-ntt.md).
- **Hashing with 64-bit / two moduli** and its collision probability — [string hashing](../11-Strings/01-string-hashing.md).
- **Probability outputs modulo a prime** (expected values as $p\cdot q^{-1}$) — [probability & expected value](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md).

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 1A · Theatre Square](https://codeforces.com/problemset/problem/1/A) — 1000
- [ ] [CSES 1068 · Weird Algorithm](https://cses.fi/problemset/task/1068)
- [ ] [CSES 1071 · Number Spiral](https://cses.fi/problemset/task/1071)
- [ ] [CSES 1072 · Two Knights](https://cses.fi/problemset/task/1072)
- [ ] [CSES 1617 · Bit Strings](https://cses.fi/problemset/task/1617)
- [ ] [CSES 1618 · Trailing Zeros](https://cses.fi/problemset/task/1618)
- [ ] [CSES 2431 · Digit Queries](https://cses.fi/problemset/task/2431)
- [ ] [CF 459B · Pashmak and Flowers](https://codeforces.com/problemset/problem/459/B) — 1300
- [ ] [CF 1215B · The Number of Products](https://codeforces.com/problemset/problem/1215/B) — 1400

**1400–1700**
- [ ] [CF 1B · Spreadsheet](https://codeforces.com/problemset/problem/1/B) — 1600
- [ ] [CF 1344A · Hilbert's Hotel](https://codeforces.com/problemset/problem/1344/A) — 1600
- [ ] [CF 1475E · Advertising Agency](https://codeforces.com/problemset/problem/1475/E) — 1600
- [ ] [CF 1359C · Mixing Water](https://codeforces.com/problemset/problem/1359/C) — 1700

**1700+**
- [ ] [CF 2B · The least round way](https://codeforces.com/problemset/problem/2/B) — 2000
- [ ] [CF 1C · Ancient Berland Circus](https://codeforces.com/problemset/problem/1/C) — 2100

## 9. LeetCode / FAANG cross-reference

Overflow and division edge cases are favourite interview follow-ups ("what if the input is `INT_MIN`?").

- [LC 7 · Reverse Integer](https://leetcode.com/problems/reverse-integer/) — Medium — detect 32-bit overflow before it happens.
- [LC 8 · String to Integer (atoi)](https://leetcode.com/problems/string-to-integer-atoi/) — Medium — clamping, sign, overflow pre-checks.
- [LC 29 · Divide Two Integers](https://leetcode.com/problems/divide-two-integers/) — Medium — `INT_MIN / -1`, truncation toward zero.
- [LC 50 · Pow(x, n)](https://leetcode.com/problems/powx-n/) — Medium — `n = INT_MIN` cannot be negated in 32 bits.
- [LC 69 · Sqrt(x)](https://leetcode.com/problems/sqrtx/) — Easy — integer square root with overflow-safe `mid * mid`.
- [LC 367 · Valid Perfect Square](https://leetcode.com/problems/valid-perfect-square/) — Easy — exact integer check instead of `sqrt`.
- [LC 43 · Multiply Strings](https://leetcode.com/problems/multiply-strings/) — Medium — big-number arithmetic by hand.
- [LC 67 · Add Binary](https://leetcode.com/problems/add-binary/) — Easy — carries in string arithmetic.
- [LC 166 · Fraction to Recurring Decimal](https://leetcode.com/problems/fraction-to-recurring-decimal/) — Medium — negative operands, `INT_MIN`, remainders.

## 10. Self-check

1. Which of these overflow 64-bit signed integers: $10^9\cdot10^9$, $3\cdot10^9\cdot3\cdot10^9$, $20!$, $\binom{2\cdot10^5}{2}$?
2. Compute $\lfloor -7/2\rfloor$, $\lceil -7/2\rceil$ and $-7 \bmod 3$ (in $[0,3)$) with C++/Java operators.
3. Why is `long long x = a * b;` wrong for `int a, b`, and what are the two correct spellings?
4. How do you compare $\frac{p_1}{q_1}$ and $\frac{p_2}{q_2}$ exactly when denominators can be negative?
5. Why is `(long long)sqrt(x)` unsafe for $x$ near $10^{18}$, and how do you fix it?
6. Name three Java I/O choices that cause TLE or WA on large inputs.
7. What must you do after every query in an interactive problem?

<details><summary>Answers</summary>

1. $10^{18}$ fits; $9\cdot10^{18}$ fits (just below $9.22\cdot10^{18}$); $20!\approx2.43\cdot10^{18}$ fits; $\binom{2\cdot10^5}{2}\approx2\cdot10^{10}$ fits. None overflow — but $3\cdot10^9$ itself does not fit in `int`.
2. `-7 / 2 = -3`, `-7 % 2 = -1`, so floor is $-3-1=-4$ and ceil is $-3$; `((-7 % 3) + 3) % 3 = (-1 + 3) % 3 = 2`.
3. The product is computed in `int` and overflows before widening; write `1LL * a * b` or `(long long)a * b`.
4. Make denominators positive (negate numerator and denominator together), then compare $p_1q_2$ with $p_2q_1$ in 64 bits (or 128 bits for larger values).
5. `double` cannot represent all integers near $10^{18}$ and `sqrt` rounds; adjust `r` down while `r*r > x` and up while `(r+1)^2 <= x` with overflow-safe checks.
6. `Scanner`, `System.out.println` per line, `StreamTokenizer` for 64-bit values (also: string concatenation for output, forgetting to flush `PrintWriter`).
7. Flush the output stream before reading the answer.

</details>
