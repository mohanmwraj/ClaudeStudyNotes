# Foundations cheat sheet

Revision only — derivations and examples are in [01-Foundations](../01-Foundations/README.md):
[complexity](../01-Foundations/01-complexity-and-constraint-reading.md) ·
[STL & Collections](../01-Foundations/02-cpp-stl-and-java-collections.md) ·
[bits](../01-Foundations/03-bit-manipulation.md) ·
[recursion](../01-Foundations/04-recursion-brute-force-and-backtracking.md) ·
[sorting](../01-Foundations/05-sorting-and-comparators.md) ·
[overflow, precision & I/O](../01-Foundations/06-integer-overflow-precision-and-fast-io.md) ·
templates: [environment](../00-Roadmap-and-Strategy/06-environment-templates-cpp-java.md).

## 1. Constraint → complexity (≈ 10⁸ simple steps per second, C++; Java slower)

| $n$ up to | Feasible | Work at max |
|---|---|---|
| 10–11 | $n!\cdot n$ | $11!\approx4\cdot10^7$ |
| 15–18 | $2^n n^2$, $3^n$ | $3^{16}\approx4.3\cdot10^7$ |
| 20–25 | $2^n n$ | $2^{20}\cdot20\approx2\cdot10^7$ |
| 35–45 | $2^{n/2}$ (MITM) | $2^{20}$ |
| 100–200 | $n^4$, $n^3\log n$ | $10^8$ |
| 300–500 | $n^3$ | $1.25\cdot10^8$ |
| 2000–5000 | $n^2$ | $2.5\cdot10^7$ |
| $10^5$–$2\cdot10^5$ | $n\log n$, $n\log^2n$, $n\sqrt n$ | $\le 10^8$ |
| $10^6$ | $n\log n$ (tight), $n$ | $2\cdot10^7$ |
| $10^7$–$10^8$ | $n$, sieve | — |
| $10^9$–$10^{12}$ | $\sqrt n$, $n^{1/3}$, $\log n$ | $10^6$ |
| $10^{18}$ | $\log n$, $\log^2 n$, $O(1)$ | 60 |

$\log_2$: $10^3\to10$, $10^5\to16.6$, $2\cdot10^5\to17.6$, $10^6\to20$, $10^9\to30$, $10^{18}\to60$.

**Multi-test:** "$\sum n\le X$" bounds per-test work proportional to $n$ only — never clear a global array per test (use touched-list or timestamps).

## 2. Sums, recurrences, amortisation

| Fact | Value |
|---|---|
| $\sum_{d\le n}\lfloor n/d\rfloor$ (loop over multiples) | $\Theta(n\log n)$; $nH_n\approx n\ln n$; $1.4\cdot10^7$ at $n=10^6$ |
| $\sum_{p\le n} n/p$ (sieve) | $O(n\log\log n)$ |
| distinct values of $\lfloor n/d\rfloor$ | $\le 2\sqrt n$ |
| pairs $i<j$ / triples | $\binom n2=\frac{n(n-1)}2$ / $\binom n3\approx\frac{n^3}6$ |
| $\sum 2^i$, $i\le k$ | $2^{k+1}-1$ (segment tree $<4n$ nodes) |
| Master theorem $T=aT(n/b)+n^c$ | $c<\log_ba$: $n^{\log_ba}$; $c=\log_ba$: $n^c\log n$; $c>\log_ba$: $n^c$ |
| $2T(n/2)+n$ / $2T(n/2)+n\log n$ / $3T(n/2)+n$ | $n\log n$ / $n\log^2 n$ / $n^{1.585}$ |
| $T(n-1)+n$ / $2T(n-1)+1$ / $nT(n-1)$ | $n^2$ / $2^n$ / $n!$ |
| balance $qB + qn/B$ | $B=\sqrt n$ |
| potential method | $\sum c_i = \sum\hat c_i - \Phi_m + \Phi_0$; doubling array: $\Phi=2\,\text{size}-\text{cap}$, $\hat c=3$ |

## 3. Memory

256 MB ≈ $2.7\cdot10^8$ B: 64 M `int` · 32 M `long long` · 2·10⁹ bits. `set<int>` node ≈ 40 B. Empty `vector` 24 B. Java `Integer` in a list ≈ 20–24 B
(4–6× `int[]`); Java array header 16 B. $5000^2$ `long long` = 200 MB.

## 4. Types and overflow

| Type | Max | Exact landmarks |
|---|---|---|
| `int` | $2147483647\approx2.1\cdot10^9$ | `0x3f3f3f3f` ≈ 1.06e9 (memset INF) |
| `long long` / `long` | $9223372036854775807\approx9.22\cdot10^{18}$ | $20!$, $F_{92}$, $\binom{66}{33}$ fit; $10^9\cdot10^9$ fits |
| `unsigned long long` | $\approx1.84\cdot10^{19}$ | $10^{19}$ fits |
| `__int128` (64-bit G++ only) | $\approx1.7\cdot10^{38}$ | print by hand |
| `double` | exact ints $\le2^{53}\approx9\cdot10^{15}$ | rel. error $\approx1.1\cdot10^{-16}$ |
| `long double` (G++ x86) | exact ints $\le2^{64}$ | MSVC = double |

Rules: `1LL * a * b`, `(long) a * b` · `INF = 1e18` so `INF + INF` fits · `mid = lo + (hi - lo) / 2` · `abs(INT_MIN)` overflows ·
`__builtin_mul_overflow` / `Math.multiplyExact`.

## 5. Division, remainders, exact comparisons

| Want | C++ | Java |
|---|---|---|
| $\lfloor a/b\rfloor$ | `a / b - ((a % b != 0) && ((a < 0) != (b < 0)))` | `Math.floorDiv(a, b)` |
| $\lceil a/b\rceil$ | `a / b + ((a % b != 0) && ((a < 0) == (b < 0)))` | `-Math.floorDiv(-a, b)` (Java 18+: `Math.ceilDiv`) |
| $\lceil a/b\rceil$, $a\ge0,b>0$ | `(a + b - 1) / b` | same |
| $a \bmod m\in[0,m)$ | `((a % m) + m) % m` | `Math.floorMod(a, m)` |
| $(a-b)\bmod m$ | `(a - b + m) % m` | same |
| $\frac ab<\frac cd$ ($b,d>0$) | `a * d < c * b` (128-bit if values $>10^9$) | same / `Math.multiplyHigh` / `BigInteger` |
| $\lfloor\sqrt x\rfloor$ | `sqrtl` then fix with integer checks | `Math.sqrt` then fix with `x / r` checks |

C++/Java truncate toward zero: `-7 / 2 == -3`, `-7 % 2 == -1`. Floats: compare $|a-b|\le\varepsilon\max(1,|a|,|b|)$; prefer exact integers;
`(long long)(x + 0.5)` is wrong for negatives (`llround`).

## 6. Bits

| Identity | Meaning |
|---|---|
| `x & -x` | lowest set bit |
| `x & (x - 1)` | clear lowest set bit; `== 0` ⇔ power of two (x>0) |
| `x \| (x + 1)` | set lowest clear bit |
| `(x >> k) & 1` | bit $k$ |
| $a+b=(a\oplus b)+2(a\mathbin\&b)=(a\mathbin\|b)+(a\mathbin\&b)$ | carry identity |
| $0\oplus\cdots\oplus n$ | $n,1,n+1,0$ for $n\bmod4=0,1,2,3$ |
| $\sum_{i<j}a_i\oplus a_j$ | $\sum_k2^kc_k(n-c_k)$ |
| $\sum_{i<j}a_i\mathbin\&a_j$ / $\mathbin\|$ | $\sum_k2^k\binom{c_k}2$ / $\sum_k2^k[\binom n2-\binom{n-c_k}2]$ |
| set bit $k$ count in $[0,n]$ | $\lfloor\frac{n+1}{2^{k+1}}\rfloor2^k+\max(0,(n+1)\bmod2^{k+1}-2^k)$ |
| submasks of all masks | $3^n$ total; `for (s = m; s; s = (s - 1) & m)` |
| supermasks | `for (s = m; s < (1 << n); s = (s + 1) \| m)` |
| Gray code | $g=i\oplus(i\gg1)$; inverse = prefix XOR of shifts |
| max $a\oplus b$ in $[l,r]$, $l<r$ | $2^{k+1}-1$, $k$ = top bit of $l\oplus r$ |
| same top bit | $a\mathbin\&b\ge a\oplus b$ |

| C++ | C++20 `<bit>` | Java |
|---|---|---|
| `__builtin_popcountll` | `std::popcount` | `Long.bitCount` |
| `__builtin_ctzll` (UB at 0) | `std::countr_zero` | `Long.numberOfTrailingZeros` |
| `63 - __builtin_clzll` | `std::bit_width(x) - 1` | `63 - Long.numberOfLeadingZeros` |

Java: `>>>` logical shift; shift counts are mod 32/64 (`1 << 32 == 1`); `byte` is signed (`b & 0xff`).

## 7. Containers (C++ ↔ Java)

| Need | C++ | Java | Cost |
|---|---|---|---|
| dynamic array | `vector` | `ArrayList` / `int[]` / `IntList` | push amortised $O(1)$ |
| both ends | `deque` | `ArrayDeque` | $O(1)$ |
| ordered set / multiset | `set` / `multiset` | `TreeSet` / `TreeMap<v, count>` | $O(\log n)$ |
| ordered map | `map` | `TreeMap` | $O(\log n)$ |
| hash map | `unordered_map` + splitmix64 | `HashMap` with mixed `long` keys | expected $O(1)$ |
| heap | `priority_queue` (**max**) | `PriorityQueue` (**min**) | $O(\log n)$ |
| smallest $\ge x$ | `s.lower_bound(x)` | `s.ceiling(x)` | |
| smallest $> x$ | `s.upper_bound(x)` | `s.higher(x)` | |
| largest $\le x$ | `prev(s.upper_bound(x))` | `s.floor(x)` | |
| largest $< x$ | `prev(s.lower_bound(x))` | `s.lower(x)` | |
| erase one copy | `ms.erase(ms.find(x))` | decrement count | |

Java `HashMap`: bucket = `(h ^ (h >>> 16)) & (cap - 1)`, `Integer.hashCode(v) = v`; bins of ≥ 8 treeify (cap ≥ 64) → worst $O(\log n)$.

## 8. Sorting

| | C++ | Java |
|---|---|---|
| default | `sort` introsort, $O(n\log n)$, unstable | primitives: dual-pivot quicksort (JDK 17/21 heapsort fallback; JDK 11 none) — **shuffle first** |
| stable | `stable_sort` | object sorts (TimSort) are stable |
| reverse | `greater<>()` | `Collections.reverseOrder()` (objects) |
| comparator | strict weak ordering; never `<=` | `Integer.compare`, never `a - b` |

Lower bound $\log_2 n!\approx n\log_2n-1.44n$. Counting sort $O(n+K)$; LSD radix (stable passes) $O(\frac wb(n+2^b))$. Inversions = min adjacent swaps;
merge sort counts them ($\ge$ variant: take from the right on ties). Concatenation order: `a + b < b + a`. Rearrangement: pair sorted with sorted to maximise $\sum x_iy_i$.

## 9. Search and recursion

| Space | Size |
|---|---|
| subsets | $2^n$ (tree $2^{n+1}-1$ nodes) |
| permutations | $n!$ (tree $<e\cdot n!$ nodes) |
| multiset permutations | $\frac{n!}{\prod c_i!}$ |
| $k$-combinations | $\binom nk$ |
| N-Queens diagonals | `r - c + n - 1`, `r + c` (8×8: 92 solutions) |

Choose → recurse → **un-choose**. Prune only with an optimistic bound. Stack: Codeforces C++ 256 MB, Java main thread `-Xss64M`;
locally `-Wl,--stack=268435456`; Java `new Thread(null, r, "s", 1 << 28)`.

## 10. Signal → technique

| Signal | Technique |
|---|---|
| $n\le20$ / a parameter $\le20$ | bitmask enumeration / bitmask DP |
| $n\le40$ | meet in the middle |
| order of input irrelevant | sort first |
| pairs $i<j$ with condition on $a_i-b_i$ | define $c_i$, sort, binary search / two pointers |
| sum of a range equals something | prefix sums; equal prefix values (change of variables) |
| `^ & \|` sums over pairs | per-bit contribution |
| maximise/minimise a bitwise expression | decide bits from the top |
| small answer space ($<2^9$) | try every answer |
| huge $n$, tiny $m$ | pigeonhole / residues |
| deletions only | reverse time (insertions, DSU) |
| comparing ratios | cross-multiply |
| answer $>9\cdot10^{18}$ | `__int128` / `BigInteger` |
| "minimum adjacent swaps" | inversions |

## 11. Templates (C++ and Java)

```cpp
// Hash for unordered_map that resists anti-hash tests.
struct SplitMix64Hash {
    static uint64_t mix(uint64_t x) {
        x += 0x9e3779b97f4a7c15ULL;
        x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
        x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
        return x ^ (x >> 31);
    }
    size_t operator()(uint64_t x) const {
        static const uint64_t SEED = chrono::steady_clock::now().time_since_epoch().count();
        return mix(x + SEED);
    }
};

ll floorDiv(ll a, ll b) { return a / b - ((a % b != 0) && ((a < 0) != (b < 0))); }
ll ceilDiv(ll a, ll b) { return a / b + ((a % b != 0) && ((a < 0) == (b < 0))); }
ll normMod(ll a, ll m) { a %= m; return a < 0 ? a + m : a; }

ll isqrtFloor(ll x) {                                   // 0 <= x <= 9e18
    ll r = (ll)sqrtl((ld)x);
    while (r > 0 && (__int128)r * r > x) r--;
    while ((__int128)(r + 1) * (r + 1) <= x) r++;
    return r;
}

long long mergeCount(vector<int>& a, vector<int>& tmp, int l, int r) {   // inversions in a[l, r), sorts it
    if (r - l <= 1) return 0;
    int m = (l + r) / 2;
    long long inv = mergeCount(a, tmp, l, m) + mergeCount(a, tmp, m, r);
    int i = l, j = m, k = l;
    while (i < m || j < r) {
        if (j == r || (i < m && a[i] <= a[j])) tmp[k++] = a[i++];
        else { inv += m - i; tmp[k++] = a[j++]; }
    }
    for (int t = l; t < r; t++) a[t] = tmp[t];
    return inv;
}

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
```

```java
static final class FastReader {                        // DataInputStream tokenizer: ints, longs, strings
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
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
}

static void shuffleSort(int[] a) {                     // defeats anti-quicksort inputs
    Random rnd = new Random();
    for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = a[i]; a[i] = a[j]; a[j] = t; }
    Arrays.sort(a);
}

static int lowerBound(int[] a, int x) {                // first index with a[i] >= x
    int lo = 0, hi = a.length;
    while (lo < hi) { int mid = (lo + hi) >>> 1; if (a[mid] < x) lo = mid + 1; else hi = mid; }
    return lo;
}

static boolean nextPermutation(int[] p) {
    int i = p.length - 2;
    while (i >= 0 && p[i] >= p[i + 1]) i--;
    if (i < 0) return false;
    int j = p.length - 1;
    while (p[j] <= p[i]) j--;
    int t = p[i]; p[i] = p[j]; p[j] = t;
    for (int l = i + 1, r = p.length - 1; l < r; l++, r--) { t = p[l]; p[l] = p[r]; p[r] = t; }
    return true;
}

static long mix(long x) {                              // use HashMap<Long, V> with key mix(k)
    x += 0x9e3779b97f4a7c15L;
    x = (x ^ (x >>> 30)) * 0xbf58476d1ce4e5b9L;
    x = (x ^ (x >>> 27)) * 0x94d049bb133111ebL;
    return x ^ (x >>> 31);
}

static long mergeCount(int[] a, int[] tmp, int l, int r) {
    if (r - l <= 1) return 0;
    int m = (l + r) >>> 1;
    long inv = mergeCount(a, tmp, l, m) + mergeCount(a, tmp, m, r);
    int i = l, j = m, k = l;
    while (i < m || j < r) {
        if (j == r || (i < m && a[i] <= a[j])) tmp[k++] = a[i++];
        else { inv += m - i; tmp[k++] = a[j++]; }
    }
    System.arraycopy(tmp, l, a, l, r - l);
    return inv;
}

static long pack(int x, int y) { return ((long) x << 32) | ((y ^ 0x80000000L) & 0xffffffffL); }   // sorts like (x, y)
```

## 12. Top 10 mistakes

1. `int` overflow in products, sums, pair counts — bound every value first.
2. Multi-test state not reset (or `memset` of a huge array per test → TLE).
3. Breaking out of the input loop early, desynchronising later tests.
4. `%` / `/` on negative numbers without normalising.
5. Java `Arrays.sort(int[])` on adversarial input without shuffling; C++ `unordered_map` with the default hash.
6. `<=` or `a - b` in a comparator.
7. `std::lower_bound` on a `set` ($O(n)$), `multiset::erase(value)` deleting all copies, `map[x]` inserting.
8. Floating-point equality or `double` for exact ratios; `(long long)sqrt(x)` off by one.
9. Slow I/O: `Scanner`, `System.out.println` in loops, `endl`; forgetting `out.flush()`; not flushing in interactive problems.
10. `1 << k` with $k\ge31$ (`1LL`), `__builtin_popcount` on 64-bit values, Java `Integer == Integer`.

## 13. Last-minute before a contest

- Template compiles in both languages; 64-bit G++ / Java 21 selected; samples runner (CPH) works.
- Multi-test line present/absent as needed; per-test containers inside `solve`.
- Before submit: all samples, then $n=1$, all-equal, maximum values, negatives.
- Bound the answer: does it need `long long`? A modulus? `__int128`?
- Sorting primitives in Java → shuffle; hashing → splitmix64.
- Deep recursion → C++ fine on Codeforces; Java → `Thread` with `1 << 28`.
- Interactive → flush after every query.
- WA on pretest 2+ → reset bug, overflow, misread — then brute force + stress script, not blind resubmits (each costs 50 points).
