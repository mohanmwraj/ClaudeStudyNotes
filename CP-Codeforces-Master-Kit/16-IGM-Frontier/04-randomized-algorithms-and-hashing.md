# Randomised algorithms and hashing

> **Band:** 🟣→🟠 1900–2600 (Schwartz–Zippel and colour coding: 🔴) · **Priority:** 🔥 for XOR/sum hashing, anti-hack seeding and random sampling; ⚡ for Freivalds; 🧊 for colour coding and polynomial identity testing · **FAANG:** medium (random pivot, reservoir sampling, shuffling, weighted picks) · **Prerequisites:** [probability and expected value](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md), [string hashing](../11-Strings/01-string-hashing.md), [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md), [STL and collections](../01-Foundations/02-cpp-stl-and-java-collections.md)
> **You can say you know this when:** you can turn "is this subarray a permutation / a rearrangement of that one / made of values with even counts" into an $O(1)$ hash comparison and state its failure probability; you seed every random generator so it cannot be hacked; and you recognise when "pick a random element" finds the answer with probability at least $1/2$.

## 1. First principles — why this works

### 1.1 Why randomness helps: the adversary moves first

In a Codeforces round your code is attacked twice: by the author's tests and by hackers who *read your code*. A deterministic algorithm has a fixed worst case, and a hacker who can see the code can build it (sorted input for a naive quicksort, colliding keys for `unordered_map`, a string pair colliding under your fixed hash base). If the algorithm makes its random choices **after** the input is fixed, no single input is bad for all choices: the adversary can only make you unlucky with small probability.

Two kinds of randomised algorithm:

- **Las Vegas:** always correct, running time is random (random-pivot quicksort, treaps, hashing with a final exact check). You analyse the *expected* time.
- **Monte Carlo:** running time fixed, the answer is wrong with small probability (hash comparisons, Freivalds, Miller–Rabin, random sampling). You analyse the *error probability* and push it below $10^{-9}$ or so.

A Monte Carlo test is **one-sided** if one answer is always right (Freivalds: "not equal" is certain, "equal" may be wrong). Then $k$ independent repetitions drive the error from $p$ to $p^k$.

### 1.2 Hashing sets and multisets: random labels

The problem: compare two multisets (say, two subarrays) quickly. Sorting costs $O(L\log L)$ per comparison. The idea: give every possible value $v$ an independent uniformly random 64-bit **label** $r(v)$, and summarise a multiset $M$ with counts $c_v$ by one number.

- **Sum hash:** $H_+(M) = \sum_v c_v\, r(v) \bmod 2^{64}$. It is *additive*, so prefix sums give the hash of any subarray in $O(1)$: $H_+(a[l..r]) = S_r - S_{l-1}$.
- **XOR hash:** $H_\oplus(M) = \bigoplus_{x \in M} r(x)$ = XOR of $r(v)$ over values with **odd** count. Also prefix-computable. It sees only parities.

Equal multisets always give equal hashes. Why do different ones rarely collide? Let $\Delta_v = c_v - c'_v$, not all zero. A collision means $\sum_v \Delta_v r(v) \equiv 0 \pmod{2^{64}}$. Fix every label except one $r(u)$ with $\Delta_u \ne 0$: the equation becomes $\Delta_u r(u) \equiv t$, which has at most $2^{\nu_2(\Delta_u)}$ solutions out of $2^{64}$ ($\nu_2$ = exponent of 2 in $\Delta_u$). So

$$\Pr[\text{collision}] \le 2^{\nu_2(\Delta_u) - 64} \le \frac{|\Delta_u|}{2^{64}},$$

which is below $2^{-46}$ when counts are at most $2^{18}$. For XOR hashing, $\Delta$ is replaced by the parity difference and the bound is exactly $2^{-64}$ when the parity vectors differ.

What each hash can decide:

| Question | Hash | Why |
|---|---|---|
| Are two subarrays rearrangements of each other? | sum (plus equal length) | multiset equality |
| Does every value occur an even number of times in $a[l..r]$? | XOR $= 0$ | parity vector is zero |
| Is $a[l..r]$ a permutation of $1..\text{len}$? | XOR $= r(1)\oplus\dots\oplus r(\text{len})$ | odd counts exactly on $1..\text{len}$ and length $\text{len}$ force each once |
| Does every value occur a multiple of $k$ times? | labels in $\mathbb{Z}_k^d$, add mod $k$ | counts mod $k$ |
| Is the set of neighbours of $u$ equal to that of $v$? | sum or XOR over the adjacency list | set equality |

### 1.3 Random sampling finds heavy elements

If some value occupies a fraction $f$ of a range, a uniformly random position hits it with probability $f$; $k$ independent samples all miss with probability $(1-f)^k \le e^{-fk}$. For a majority ($f > 1/2$), 30 samples fail with probability below $2^{-30} \approx 10^{-9}$. Each sample is then **verified** exactly (count occurrences with binary search on the value's position list), so the answer is never wrong when it says "found"; it can only miss. The same idea gives "an answer divisor is a divisor of a random element with probability $\ge 1/2$" ([CF 364D · Ghd](https://codeforces.com/problemset/problem/364/D) — 2900) and "a random element changes by at most 1 in an optimal solution with probability $\ge 1/2$" ([CF 1305F · Kuroni and the Punishment](https://codeforces.com/problemset/problem/1305/F) — 2500).

### 1.4 Verifying instead of computing: Freivalds and Schwartz–Zippel

Checking $AB = C$ for $n\times n$ matrices by multiplying costs $O(n^3)$. Instead pick a random vector $x$ and compare $A(Bx)$ with $Cx$: three matrix–vector products, $O(n^2)$. If $D = AB - C \ne 0$, some row $d$ of $D$ is non-zero, and $d\cdot x = 0$ is one linear equation in the random coordinates; over $\mathbb{F}_p$ with $x$ uniform it holds with probability exactly $1/p$. With $x \in \{0,1\}^n$ the bound is $1/2$ per round.

This is the simplest case of the **Schwartz–Zippel lemma** (🔴): a non-zero polynomial $P$ of total degree $d$ over a field vanishes at a uniformly random point of $S^n$ with probability at most $d/|S|$. Polynomial string hashing is the same lemma (two different strings are different polynomials in the base), and so is the randomised perfect-matching test (substitute random values into the Tutte matrix and check that the determinant is non-zero).

### 1.5 Birthday paradox: how many values can a hash space hold?

With $k$ uniformly random values in a space of size $M$,

$$\Pr[\text{some two collide}] = 1 - \prod_{i<k}\Big(1 - \frac{i}{M}\Big) \approx 1 - e^{-k^2/(2M)} \approx \frac{k^2}{2M}.$$

What matters is **how many pairs you implicitly compare**. Comparing $q$ specific pairs costs $q/M$; putting $k$ hashes into a set (counting distinct substrings, deduplicating) compares all $\binom{k}{2}$ pairs. With a single modulus $M \approx 10^9$ and $k = 10^6$ distinct strings, the expected number of colliding pairs is $\approx 10^{12}/(2\cdot10^9) = 500$: certain failure. With $M = 2^{61}-1$ it is $\approx 2\cdot10^{-7}$.

### 1.6 Random order defeats adversarial order

A structure whose cost depends on the input order (BST insertion, quicksort pivots, incremental geometry) has a bad order that a hacker can supply. Randomising the order (shuffle, random pivot, random treap priorities) makes the expected cost the average over all orders, e.g. expected treap depth $O(\log n)$ and expected minimum enclosing circle time $O(n)$. Java's `Arrays.sort(int[])` is a dual-pivot quicksort with known killer inputs: shuffle first.

### 1.7 Colour coding and random partitions (🔴)

To find a simple path (or tree) with $k$ vertices in a large graph, colour each vertex uniformly with one of $k$ colours and search only for *colourful* paths (all colours distinct) by DP over colour subsets in $O(2^k m)$. A fixed optimal path is colourful with probability $k!/k^k \ge e^{-k}$, so $O(e^k)$ repetitions find it with constant probability. The cheap special case — a random **2-colouring** forcing a structure to alternate sides — appears in [CF 1310D · Tourism](https://codeforces.com/problemset/problem/1310/D) — 2300.

### 1.8 Seeding: the anti-hack rule

A fixed seed makes a randomised algorithm deterministic, and hackable. Seed from a clock (`chrono::steady_clock` in C++, `System.nanoTime()` in Java). On MinGW/Windows `rand()` returns only 15 bits (`RAND_MAX = 32767`), so `rand() % n` is both biased and tiny; use `mt19937`/`mt19937_64`.

## 2. Formulas, definitions and identities

- **Amplification (one-sided):** error $p$ per run → $p^k$ after $k$ independent runs. $(1-f)^k \le e^{-fk}$, so $k = \lceil \ln(1/\varepsilon)/f\rceil$ samples suffice for miss probability $\varepsilon$.
- **Expected tries to first success:** $1/p$ (geometric distribution); Las Vegas "retry until it works" with success $p$ costs $T/p$ expected.
- **Sum hash collision:** $\Pr\big[\sum_v \Delta_v r(v) \equiv 0 \pmod{2^{64}}\big] \le 2^{\nu_2(\Delta_u)-64}$ for any $u$ with $\Delta_u \ne 0$.
- **XOR hash:** $H_\oplus(M) = \bigoplus_{v:\, c_v \text{ odd}} r(v)$; collision probability $2^{-64}$ when parity vectors differ.
- **Union bound:** $q$ comparisons each failing with probability $\le p$ fail together with probability $\le qp$.
- **Birthday:** $k$ values in $M$ slots: $\Pr[\text{collision}] \approx 1 - e^{-k^2/2M}$; expected colliding pairs $\binom{k}{2}/M$.
- **Schwartz–Zippel:** $\Pr_{x \in S^n}[P(x) = 0] \le \deg P / |S|$ for non-zero $P$.
- **Freivalds:** $\Pr[A(Bx) = Cx \mid AB \ne C] \le 1/|S|$ for $x$ uniform in $S^n$ over a field ($= 1/2$ for $S = \{0,1\}$ even over $\mathbb{Q}$).
- **Colour coding:** $\Pr[\text{fixed } k\text{-set colourful}] = k!/k^k \ge e^{-k}$.
- **Random sampling for frequency $> 1/k$:** each sample hits a fixed such value with probability $> 1/k$; $ck$ samples miss it with probability $< e^{-c}$.
- **Expected treap depth:** $2\ln n + O(1)$; expected comparisons of random-pivot quicksort $2n\ln n$.

## 3. Implementation (C++ and Java)

Random number generation, a hack-proof hash for `unordered_map`, and random labels. The C++ `SafeHash` is the widely used splitmix64 finaliser with a per-run offset; the Java side has the shuffle-before-sort helper and a small open-addressing `long → int` map that avoids both boxing and predictable hashing.

```cpp
// Seed from a high-resolution clock: hackers cannot predict it, and every run differs.
mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
ull randBetween(ull lo, ull hi) { return uniform_int_distribution<ull>(lo, hi)(rng); }

// splitmix64 finaliser + a per-run random offset: safe hash for unordered_map / gp_hash_table.
struct SafeHash {
    static ull splitmix64(ull x) {
        x += 0x9e3779b97f4a7c15ULL;
        x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
        x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
        return x ^ (x >> 31);
    }
    size_t operator()(ull x) const {
        static const ull OFFSET = chrono::steady_clock::now().time_since_epoch().count();
        return splitmix64(x + OFFSET);
    }
};
// usage: unordered_map<ll, int, SafeHash> cnt; cnt.reserve(1 << 20);

// Random 64-bit label per distinct value: the building block of XOR / sum hashing.
vector<ull> randomLabels(int n) {
    vector<ull> r(n);
    for (auto& x : r) x = rng();
    return r;
}
```

```java
// SplittableRandom is fast and not shared; seed it from nanoTime so tests cannot be prepared against it.
static final SplittableRandom RNG = new SplittableRandom(System.nanoTime() ^ 0x9E3779B97F4A7C15L);

// Shuffle before Arrays.sort on primitives: the dual-pivot quicksort has O(n^2) killer inputs.
static void shuffleSort(int[] a) {
    for (int i = a.length - 1; i > 0; i--) { int j = RNG.nextInt(i + 1); int t = a[i]; a[i] = a[j]; a[j] = t; }
    Arrays.sort(a);
}

static long splitmix64(long x) {
    x += 0x9E3779B97F4A7C15L;
    x = (x ^ (x >>> 30)) * 0xBF58476D1CE4E5B9L;
    x = (x ^ (x >>> 27)) * 0x94D049BB133111EBL;
    return x ^ (x >>> 31);
}

// Open-addressing long -> int map with a salted splitmix64 hash: no boxing, no anti-hash worst case.
static final class LongIntMap {
    private static final long SALT = System.nanoTime();
    private long[] keys;
    private int[] vals;
    private boolean[] used;
    private int size, mask;
    LongIntMap(int expected) {
        int cap = Integer.highestOneBit(Math.max(4, expected * 2 - 1)) << 1;
        keys = new long[cap]; vals = new int[cap]; used = new boolean[cap]; mask = cap - 1;
    }
    private int slot(long k) {
        int i = (int) splitmix64(k + SALT) & mask;
        while (used[i] && keys[i] != k) i = (i + 1) & mask;
        return i;
    }
    int get(long k, int def) { int i = slot(k); return used[i] ? vals[i] : def; }
    void put(long k, int v) {
        int i = slot(k);
        if (!used[i]) { used[i] = true; keys[i] = k; size++; }
        vals[i] = v;
        if (2 * size > keys.length) grow();
    }
    private void grow() {
        long[] ok = keys; int[] ov = vals; boolean[] ou = used;
        keys = new long[ok.length * 2]; vals = new int[ok.length * 2]; used = new boolean[ok.length * 2];
        mask = keys.length - 1; size = 0;
        for (int i = 0; i < ok.length; i++) if (ou[i]) put(ok[i], ov[i]);
    }
}
```

## 4. Recognising the pattern

- **"Is $a[l..r]$ a permutation?", "can $a[l_1..r_1]$ be rearranged into $a[l_2..r_2]$?", "does every value occur an even number of times?"** with many queries → random labels + XOR or sum prefix hashes.
- **"Count subarrays such that each value's count is ≡ 0 mod $k$"** → hash the vector of counts mod $k$, then count equal prefix hashes (a hash map of prefix values).
- **"Some value occurs more than half / a third of the range"** → random sampling with exact verification (or a Boyer–Moore style segment tree when it must be deterministic).
- **"The answer is a divisor (or a value) shared by at least half of the elements"** → pick random elements, try their divisors.
- **"Check whether a big product / identity holds"** → evaluate at random points (Freivalds, Schwartz–Zippel).
- **"Find a structure on $k \le 10$–$20$ vertices in a big graph"** → colour coding / random partition.
- **Any `unordered_map` or `HashMap` on input-controlled keys, any sort on input-controlled data in Java, any hash base** in a round with hacks → randomise.
- Commonly confused: XOR hashing (parities only — cannot tell count 1 from count 3) vs. sum hashing (exact counts); "random" as a heuristic (simulated annealing: no guarantee) vs. randomised algorithms with a proof.

## 5. Worked examples (graded)

### Example 1 — Are two subarrays rearrangements of each other?  ·  ★ ≈1900 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈1900 (est.)
- **Problem:** Array $a_1..a_n$ ($1 \le a_i \le 10^9$, $n, q \le 2\cdot10^5$). Each query $(l_1, r_1, l_2, r_2)$: can $a[l_1..r_1]$ be permuted into $a[l_2..r_2]$?
- **Thinking from first principles:** Sorting both ranges is $O(L\log L)$ per query — too slow. Counting arrays per query are $O(n)$. Prefix count arrays per value need $O(n \cdot \#\text{values})$ memory. We want a *summary* of a multiset that is additive (so prefix sums work) and almost injective: random labels with a sum mod $2^{64}$. Lengths must match too (cheap to check, and it removes the only "structured" source of failure).

<details><summary>Solution</summary>

Compress values, draw a random 64-bit label per distinct value, build prefix sums $S_i = \sum_{j \le i} r(a_j)$ with unsigned wrap-around, and answer YES iff the lengths match and $S_{r_1} - S_{l_1-1} = S_{r_2} - S_{l_2-1}$. A wrong YES needs $\sum_v \Delta_v r(v) \equiv 0$ with some $|\Delta_v| \le 2\cdot10^5 < 2^{18}$, probability $< 2^{-46}$ per query; over $2\cdot10^5$ queries the union bound gives $< 3\cdot10^{-9}$. $O((n+q) + n\log n)$.

Java note: `long` arithmetic wraps modulo $2^{64}$ exactly like `unsigned long long`, so no masking is needed; only the comparison of *values* must not mix signed and unsigned interpretations (here we compare for equality only).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ull = unsigned long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, q;
    cin >> n >> q;
    vector<int> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    vector<int> vals(a.begin() + 1, a.end());
    sort(vals.begin(), vals.end());
    vals.erase(unique(vals.begin(), vals.end()), vals.end());
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    vector<ull> label(vals.size());
    for (auto& x : label) x = rng();                 // one random 64-bit label per distinct value
    vector<ull> H(n + 1, 0);                         // prefix sums modulo 2^64 (unsigned overflow wraps)
    for (int i = 1; i <= n; i++)
        H[i] = H[i - 1] + label[lower_bound(vals.begin(), vals.end(), a[i]) - vals.begin()];
    while (q--) {
        int l1, r1, l2, r2;
        cin >> l1 >> r1 >> l2 >> r2;
        bool same = r1 - l1 == r2 - l2 && H[r1] - H[l1 - 1] == H[r2] - H[l2 - 1];
        cout << (same ? "YES" : "NO") << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), q = in.nextInt();
        int[] a = new int[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextInt();
        SplittableRandom rng = new SplittableRandom(System.nanoTime());
        int[] vals = Arrays.copyOfRange(a, 1, n + 1);
        for (int i = n - 1; i > 0; i--) { int j = rng.nextInt(i + 1); int t = vals[i]; vals[i] = vals[j]; vals[j] = t; }
        Arrays.sort(vals);
        int d = 0;
        for (int i = 0; i < n; i++) if (d == 0 || vals[d - 1] != vals[i]) vals[d++] = vals[i];
        long[] label = new long[d];
        for (int i = 0; i < d; i++) label[i] = rng.nextLong();
        long[] H = new long[n + 1];                    // long arithmetic wraps modulo 2^64, exactly what we want
        for (int i = 1; i <= n; i++) H[i] = H[i - 1] + label[Arrays.binarySearch(vals, 0, d, a[i])];
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int l1 = in.nextInt(), r1 = in.nextInt(), l2 = in.nextInt(), r2 = in.nextInt();
            boolean same = r1 - l1 == r2 - l2 && H[r1] - H[l1 - 1] == H[r2] - H[l2 - 1];
            sb.append(same ? "YES" : "NO").append('\n');
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
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
        int nextInt() throws IOException {
            int ret = 0, b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
    }
}
```

</details>

<!-- test
in:
6 5
1 2 3 2 1 3
1 3 4 6
1 2 2 3
1 6 1 6
2 2 4 4
1 2 1 3
out:
YES
NO
YES
YES
NO
-->
<!-- test
in:
1 1
1000000000
1 1 1 1
out:
YES
-->

### Example 2 — Range majority by random sampling  ·  ★ ≈2000 (est.)

- **Source:** Original problem (the sampling idea is the standard one for [CF 1514D · Cut and Stick](https://codeforces.com/problemset/problem/1514/D) — 2000 and [LC 1157 · Online Majority Element In Subarray](https://leetcode.com/problems/online-majority-element-in-subarray/) — Hard).
- **Difficulty:** ≈2000 (est.)
- **Problem:** Array of $n \le 3\cdot10^5$ integers, $q \le 3\cdot10^5$ queries $[l, r]$: print a value occurring more than $(r-l+1)/2$ times in $a[l..r]$, or $-1$.
- **Thinking from first principles:** A deterministic route exists (a segment tree of Boyer–Moore candidates, or a persistent segment tree), but it is longer to write. Observation: if a majority exists, more than half of the positions hold it, so a random position is the majority with probability $> 1/2$. Checking a candidate exactly is a pair of binary searches in the sorted position list of that value. Thirty tries miss an existing majority with probability $< 2^{-30}$; a candidate is only reported after exact verification, so the algorithm never reports a wrong value.

<details><summary>Solution</summary>

Precompute for each compressed value the sorted list of its positions. Per query: up to 30 random positions in $[l, r]$; for a new candidate $v$, its count in $[l,r]$ is `upper_bound(r) - lower_bound(l)` on its list; stop at the first candidate with $2c > \text{len}$. Cost $O(30\log n)$ per query. Error: only "$-1$ although a majority exists", probability $< 2^{-30}$ per query.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, q;
    cin >> n >> q;
    vector<int> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    vector<int> vals(a.begin() + 1, a.end());
    sort(vals.begin(), vals.end());
    vals.erase(unique(vals.begin(), vals.end()), vals.end());
    vector<vector<int>> pos(vals.size());                  // sorted positions of every value
    vector<int> id(n + 1);
    for (int i = 1; i <= n; i++) {
        id[i] = lower_bound(vals.begin(), vals.end(), a[i]) - vals.begin();
        pos[id[i]].push_back(i);
    }
    mt19937 rng(chrono::steady_clock::now().time_since_epoch().count());
    const int TRIES = 30;                                   // miss probability < 2^-30 per query
    while (q--) {
        int l, r;
        cin >> l >> r;
        int len = r - l + 1, ans = -1, last = -1;
        for (int t = 0; t < TRIES && ans == -1; t++) {
            int v = id[l + rng() % len];
            if (v == last) continue;                        // same candidate, already rejected
            last = v;
            auto& p = pos[v];
            int c = upper_bound(p.begin(), p.end(), r) - lower_bound(p.begin(), p.end(), l);
            if (2 * c > len) ans = vals[v];
        }
        cout << ans << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), q = in.nextInt();
        int[] a = new int[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextInt();
        SplittableRandom rng = new SplittableRandom(System.nanoTime());
        int[] vals = Arrays.copyOfRange(a, 1, n + 1);
        for (int i = n - 1; i > 0; i--) { int j = rng.nextInt(i + 1); int t = vals[i]; vals[i] = vals[j]; vals[j] = t; }
        Arrays.sort(vals);
        int d = 0;
        for (int i = 0; i < n; i++) if (d == 0 || vals[d - 1] != vals[i]) vals[d++] = vals[i];
        int[] id = new int[n + 1], start = new int[d + 1], pos = new int[n];
        for (int i = 1; i <= n; i++) { id[i] = Arrays.binarySearch(vals, 0, d, a[i]); start[id[i] + 1]++; }
        for (int v = 0; v < d; v++) start[v + 1] += start[v];
        int[] fill = Arrays.copyOf(start, d + 1);
        for (int i = 1; i <= n; i++) pos[fill[id[i]]++] = i;   // positions of value v: pos[start[v] .. start[v+1])
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int l = in.nextInt(), r = in.nextInt();
            int len = r - l + 1, ans = Integer.MIN_VALUE, last = -1;
            boolean found = false;
            for (int t = 0; t < 30 && !found; t++) {
                int v = id[l + rng.nextInt(len)];
                if (v == last) continue;
                last = v;
                int c = lowerBound(pos, start[v], start[v + 1], r + 1) - lowerBound(pos, start[v], start[v + 1], l);
                if (2 * c > len) { found = true; ans = vals[v]; }
            }
            sb.append(found ? ans : -1).append('\n');
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }

    static int lowerBound(int[] a, int lo, int hi, int x) {
        while (lo < hi) { int m = (lo + hi) >>> 1; if (a[m] < x) lo = m + 1; else hi = m; }
        return lo;
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
        int nextInt() throws IOException {
            int ret = 0, b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
    }
}
```

</details>

<!-- test
in:
7 5
3 3 1 3 2 3 3
1 7
2 3
3 5
4 4
5 7
out:
3
-1
-1
3
3
-->
<!-- test
in:
1 1
-5
1 1
out:
-5
-->

### Example 3 — Verify a matrix product in $O(n^2)$ (Freivalds)  ·  ★ ≈2200 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈2200 (est.)
- **Problem:** Three $n \times n$ matrices $A, B, C$ with entries in $[0, p)$, $p = 998244353$, $n \le 1000$. Decide whether $AB \equiv C \pmod p$.
- **Thinking from first principles:** $n^3 = 10^9$ multiply–mod operations is too slow. We only need a *yes/no*. A linear map that is non-zero is non-zero on most vectors: if $D = AB - C \ne 0$, then $Dx \ne 0$ for all but a $1/p$ fraction of uniformly random $x$. And $Dx = A(Bx) - Cx$ costs three matrix–vector products. A "NO" is always correct (a witness vector), a "YES" is wrong with probability $\le 1/p$ per round.

<details><summary>Solution</summary>

Two rounds with $x$ uniform in $\mathbb{F}_p^n$: compute $y = Bx$, $z = Ay$, $w = Cx$; if $z \ne w$ answer NO. Error $\le p^{-2} \approx 10^{-18}$. Each product entry is $< p^2 < 2^{60}$, so a 64-bit accumulator with one `%` per term is safe in both languages. $O(n^2)$ time; reading the $3n^2$ numbers dominates.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ull = unsigned long long;

const ull MOD = 998244353;

// y = M x (mod MOD), M stored row-major
vector<ull> mul(const vector<ull>& M, const vector<ull>& x, int n) {
    vector<ull> y(n, 0);
    for (int i = 0; i < n; i++) {
        ull acc = 0;
        const ull* row = &M[(size_t)i * n];
        for (int j = 0; j < n; j++) acc = (acc + row[j] * x[j]) % MOD;   // product < 2^60, no overflow
        y[i] = acc;
    }
    return y;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<ull> A((size_t)n * n), B((size_t)n * n), C((size_t)n * n);
    for (auto* M : {&A, &B, &C})
        for (auto& v : *M) cin >> v;
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    bool equal = true;
    for (int round = 0; round < 2 && equal; round++) {     // one-sided error <= (1/MOD)^2
        vector<ull> x(n);
        for (auto& v : x) v = rng() % MOD;
        equal = mul(A, mul(B, x, n), n) == mul(C, x, n);  // A(Bx) vs Cx: O(n^2) instead of O(n^3)
    }
    cout << (equal ? "YES" : "NO") << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static final long MOD = 998244353L;

    static long[] mul(long[] M, long[] x, int n) {
        long[] y = new long[n];
        for (int i = 0; i < n; i++) {
            long acc = 0;
            int base = i * n;
            for (int j = 0; j < n; j++) acc = (acc + M[base + j] * x[j]) % MOD;
            y[i] = acc;
        }
        return y;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[][] mats = new long[3][n * n];
        for (long[] M : mats) for (int i = 0; i < n * n; i++) M[i] = in.nextInt();
        SplittableRandom rng = new SplittableRandom(System.nanoTime());
        boolean equal = true;
        for (int round = 0; round < 2 && equal; round++) {
            long[] x = new long[n];
            for (int i = 0; i < n; i++) x[i] = rng.nextLong(MOD);
            equal = Arrays.equals(mul(mats[0], mul(mats[1], x, n), n), mul(mats[2], x, n));
        }
        System.out.println(equal ? "YES" : "NO");
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
        int nextInt() throws IOException {
            int ret = 0, b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
    }
}
```

</details>

<!-- test
in:
2
1 2
3 4
5 6
7 8
19 22
43 50
out:
YES
-->
<!-- test
in:
2
1 2
3 4
5 6
7 8
19 22
43 51
out:
NO
-->
<!-- test
in:
1
998244352
998244352
1
out:
YES
-->

### Example 4 — Count subarrays that are permutations  ·  ★ 2500

- **Source:** [CF 1175F · The Number of Subpermutations](https://codeforces.com/problemset/problem/1175/F) — 2500
- **Difficulty:** 2500
- **Problem:** Array of $n \le 3\cdot10^5$ values in $[1, n]$. Count subarrays $a[l..r]$ that contain every integer $1..(r-l+1)$ exactly once.
- **Thinking from first principles:** A subpermutation of length $m$ has maximum $m$ and contains exactly one $1$. Two facts make it fast. (1) Testing one candidate is $O(1)$ with XOR hashing: $H(a[l..r]) = r(1)\oplus\dots\oplus r(m)$ and the length is $m$ (§1.2). (2) Fix the unique $1$ at position $p$ and assume the maximum lies at or to the right of $p$. Scanning $r = p, p+1, \dots$ up to the next $1$, the maximum $m$ of $a[p..r]$ determines the only possible left end $l = r - m + 1$, so each $r$ yields **one** candidate. The ranges scanned for consecutive 1s are disjoint, so this is $O(n)$. Subpermutations whose maximum is strictly left of the 1 are found by the same scan on the reversed array (skipping $r = p$, so the single-element $[1]$ is counted once).

<details><summary>Solution</summary>

Random 64-bit labels $r(1..n)$, prefix XORs $H$, and $P_m = r(1)\oplus\dots\oplus r(m)$. For each 1 at $p$ and each $r$ from $p$ to just before the next 1, with $m = \max a[p..r]$ and $l = r-m+1$: count it if $1 \le l \le p$ and $H_r \oplus H_{l-1} = P_m$. Then reverse and repeat with $r > p$. Each subpermutation has a unique maximum position, so it is counted in exactly one pass; a non-subpermutation passes the hash test with probability $2^{-64}$, and there are at most $2n$ tests. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ull = unsigned long long;
using ll = long long;

// Counts subarrays that are permutations of 1..len, for one orientation of the array:
// only subarrays whose maximum lies at or to the right of their single 1 (strictly right if strict).
ll countOneSide(const vector<int>& a, const vector<ull>& lab, const vector<ull>& P, bool strict) {
    int n = a.size() - 1;
    vector<ull> H(n + 1, 0);
    for (int i = 1; i <= n; i++) H[i] = H[i - 1] ^ lab[a[i]];
    ll cnt = 0;
    for (int p = 1; p <= n; p++) {
        if (a[p] != 1) continue;
        int mx = 1;
        for (int r = p; r <= n; r++) {
            if (r > p && a[r] == 1) break;              // the next 1 starts another block
            mx = max(mx, a[r]);
            if (strict && r == p) continue;             // [1] itself is counted by the other pass
            int l = r - mx + 1;                         // the only possible left end with this maximum
            if (l >= 1 && l <= p && (H[r] ^ H[l - 1]) == P[mx]) cnt++;
        }
    }
    return cnt;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    mt19937_64 rng(chrono::steady_clock::now().time_since_epoch().count());
    vector<ull> lab(n + 1), P(n + 1, 0);
    for (int v = 1; v <= n; v++) { lab[v] = rng(); P[v] = P[v - 1] ^ lab[v]; }   // P[k] = hash of {1..k}
    ll ans = countOneSide(a, lab, P, false);
    reverse(a.begin() + 1, a.end());
    ans += countOneSide(a, lab, P, true);              // maximum strictly left of the 1 in the original
    cout << ans << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static long countOneSide(int[] a, long[] lab, long[] P, boolean strict) {
        int n = a.length - 1;
        long[] H = new long[n + 1];
        for (int i = 1; i <= n; i++) H[i] = H[i - 1] ^ lab[a[i]];
        long cnt = 0;
        for (int p = 1; p <= n; p++) {
            if (a[p] != 1) continue;
            int mx = 1;
            for (int r = p; r <= n; r++) {
                if (r > p && a[r] == 1) break;
                mx = Math.max(mx, a[r]);
                if (strict && r == p) continue;
                int l = r - mx + 1;
                if (l >= 1 && l <= p && (H[r] ^ H[l - 1]) == P[mx]) cnt++;
            }
        }
        return cnt;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextInt();
        SplittableRandom rng = new SplittableRandom(System.nanoTime());
        long[] lab = new long[n + 1], P = new long[n + 1];
        for (int v = 1; v <= n; v++) { lab[v] = rng.nextLong(); P[v] = P[v - 1] ^ lab[v]; }
        long ans = countOneSide(a, lab, P, false);
        for (int i = 1, j = n; i < j; i++, j--) { int t = a[i]; a[i] = a[j]; a[j] = t; }
        ans += countOneSide(a, lab, P, true);
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
        int nextInt() throws IOException {
            int ret = 0, b = read();
            while (b <= ' ') b = read();
            boolean neg = b == '-';
            if (neg) b = read();
            while (b >= '0' && b <= '9') { ret = ret * 10 + (b - '0'); b = read(); }
            return neg ? -ret : ret;
        }
    }
}
```

</details>

<!-- test
in:
6
2 4 1 3 4 2
out:
3
-->
<!-- test
in:
1
1
out:
1
-->
<!-- test
in:
3
1 1 1
out:
3
-->
<!-- test
in:
5
5 4 3 2 1
out:
5
-->

All four programs were stress-tested against brute force (Counter comparison, Counter majority, direct matrix multiplication, sorting every subarray) on 250 random cases each with tiny value ranges, plus Java-vs-C++ comparison.

## 6. Tricks, pitfalls and things to remember

1. **Never use a fixed seed** (`mt19937 rng(42)`, `new Random(1)`) in a round with hacks: the generator becomes a deterministic function a hacker can simulate.
2. **`rand()` on Windows/MinGW returns 15 bits.** `rand() % 100000` is biased and covers only 32768 values. Use `mt19937`.
3. **`std::random_shuffle` is removed in C++17**; use `shuffle(v.begin(), v.end(), rng)`.
4. **`unordered_map<long long, …>` with the default hash is hackable** (identity hash + known bucket counts). Use the `SafeHash` from §3 or a sorted vector.
5. **Java `HashMap` treeifies colliding buckets**, so attacks degrade it to $O(\log n)$ per operation rather than $O(n)$, but boxing already makes it slow; for $10^6$ operations prefer a primitive open-addressing map.
6. **Shuffle before `Arrays.sort` on `int[]`/`long[]`.** Sorting `Integer[]` or `int[][]` uses merge sort (TimSort) and is safe but slow.
7. **XOR hashing sees only parity.** It cannot distinguish $\{x, x, x\}$ from $\{x\}$. If counts matter, use sum hashing, and check lengths.
8. **Sum hashing mod $2^{64}$ is weak for counts divisible by large powers of two** (the bound is $2^{\nu_2(\Delta)-64}$). For the usual $n \le 10^6$ this is irrelevant; for adversarial huge multiplicities use a prime modulus such as $2^{61}-1$.
9. **Single 32-bit-sized modulus + many strings = birthday failure.** Use $2^{61}-1$ or two moduli whenever you store many hashes in a set.
10. **Random sampling must verify.** Report a candidate only after an exact count; otherwise a Monte Carlo error becomes a wrong answer instead of a missed one.
11. **Modulo bias** (`rng() % n` with a 32-bit generator and large $n$) is negligible for sampling but matters for exact uniformity; `uniform_int_distribution` avoids it.
12. **Debugging randomised code:** print the seed on stderr when a stress test fails, then rerun with it fixed.

## 7. Going further (toward 2400–2600+)

- **Random weights inside data structures:** give each inserted rectangle a random weight and use a 2D Fenwick tree of sums — two points are "in the same set of rectangles" iff their sums match ([CF 869E · The Untended Antiquity](https://codeforces.com/problemset/problem/869/E) — 2400).
- **Hashing counts modulo $k$:** "every value occurs a multiple of 3 times" ([CF 1418G · Three Occurrences](https://codeforces.com/problemset/problem/1418/G) — 2500).
- **Random subsets for frequency tests:** choose random subsets of values and maintain a Fenwick tree per subset; "every count in $[l,r]$ divisible by $k$" passes each subset test ([CF 1746F · Kazaee](https://codeforces.com/problemset/problem/1746/F) — 2800).
- **Random person + SOS DP:** an optimal set is liked by at least half of the people, so a random person likes it with probability $\ge 1/2$; enumerate subsets of that person's likes ([CF 1523D · Love-Hate](https://codeforces.com/problemset/problem/1523/D) — 2400, see [SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md)).
- **Primality and factorisation:** Miller–Rabin and Pollard's rho are Monte Carlo / Las Vegas algorithms ([primitive roots, Miller–Rabin, Pollard rho](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)).
- **Tutte matrix:** a general graph has a perfect matching iff its Tutte matrix is non-singular; substituting random field elements and running Gaussian elimination tests it in $O(n^3)$ ([Gaussian elimination](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)).
- **Randomised incremental geometry:** minimum enclosing circle in expected $O(n)$ after a shuffle ([circles and advanced geometry](../14-Geometry/06-circles-and-advanced-geometry.md)).
- **Data that is random by construction:** some problems generate their data from a pseudo-random generator, which makes amortised "interval assignment" structures fast in expectation ([CF 896C · Willem, Chtholly and Seniorious](https://codeforces.com/problemset/problem/896/C) — 2600).

## 8. Practice ladder

1900–2100
- [ ] [CF 2014H · Robin Hood Archery](https://codeforces.com/problemset/problem/2014/H) — 1900 — XOR hashing of a range
- [ ] [CF 1514D · Cut and Stick](https://codeforces.com/problemset/problem/1514/D) — 2000 — random sampling for the frequent value
- [ ] [CF 843B · Interactive LowerBound](https://codeforces.com/problemset/problem/843/B) — 2000 — random probes, then walk
- [ ] [CF 1284D · New Year and Conference](https://codeforces.com/problemset/problem/1284/D) — 2100 — random weights for sets of overlapping intervals

2200–2400
- [ ] [CF 1114E · Arithmetic Progression](https://codeforces.com/problemset/problem/1114/E) — 2200 — binary search + random sample gcd
- [ ] [CF 154C · Double Profiles](https://codeforces.com/problemset/problem/154/C) — 2300 — hash neighbourhoods
- [ ] [CF 1310D · Tourism](https://codeforces.com/problemset/problem/1310/D) — 2300 — random 2-colouring
- [ ] [CF 1394B · Boboniu Walks on Graph](https://codeforces.com/problemset/problem/1394/B) — 2300 — sum hashing of a choice
- [ ] [CF 869E · The Untended Antiquity](https://codeforces.com/problemset/problem/869/E) — 2400 — random weights in a 2D Fenwick tree
- [ ] [CF 1830C · Hyperregular Bracket Strings](https://codeforces.com/problemset/problem/1830/C) — 2400 — XOR hashing of interval coverage
- [ ] [CF 1523D · Love-Hate](https://codeforces.com/problemset/problem/1523/D) — 2400 — random pivot person + SOS

2500+
- [ ] [CF 1175F · The Number of Subpermutations](https://codeforces.com/problemset/problem/1175/F) — 2500 — Example 4
- [ ] [CF 1418G · Three Occurrences](https://codeforces.com/problemset/problem/1418/G) — 2500 — counts mod 3
- [ ] [CF 1305F · Kuroni and the Punishment](https://codeforces.com/problemset/problem/1305/F) — 2500 — random elements, factor neighbours
- [ ] [CF 840D · Destiny](https://codeforces.com/problemset/problem/840/D) — 2500 — frequency above $1/k$
- [ ] [CF 896C · Willem, Chtholly and Seniorious](https://codeforces.com/problemset/problem/896/C) — 2600 — random data, interval map
- [ ] [CF 1746F · Kazaee](https://codeforces.com/problemset/problem/1746/F) — 2800 — random subsets + Fenwick
- [ ] [CF 364D · Ghd](https://codeforces.com/problemset/problem/364/D) — 2900 — random element, divisor counting
- [ ] [CF 1622F · Quadratic Set](https://codeforces.com/problemset/problem/1622/F) — 2900 — XOR hashing of prime exponent parities

## 9. LeetCode / FAANG cross-reference

- [LC 215 · Kth Largest Element in an Array](https://leetcode.com/problems/kth-largest-element-in-an-array/) — Medium — random-pivot quickselect, expected $O(n)$ (Las Vegas).
- [LC 384 · Shuffle an Array](https://leetcode.com/problems/shuffle-an-array/) — Medium — Fisher–Yates; know why "swap with any index" is biased.
- [LC 382 · Linked List Random Node](https://leetcode.com/problems/linked-list-random-node/) — Medium — reservoir sampling: keep the $i$-th item with probability $1/i$.
- [LC 398 · Random Pick Index](https://leetcode.com/problems/random-pick-index/) — Medium — reservoir sampling over matching indices.
- [LC 528 · Random Pick with Weight](https://leetcode.com/problems/random-pick-with-weight/) — Medium — prefix sums + binary search on a uniform draw.
- [LC 470 · Implement Rand10() Using Rand7()](https://leetcode.com/problems/implement-rand10-using-rand7/) — Medium — rejection sampling; expected number of calls.
- [LC 710 · Random Pick with Blacklist](https://leetcode.com/problems/random-pick-with-blacklist/) — Hard — remap blacklisted values.
- [LC 380 · Insert Delete GetRandom O(1)](https://leetcode.com/problems/insert-delete-getrandom-o1/) — Medium — array + hash map, swap-delete.
- [LC 169 · Majority Element](https://leetcode.com/problems/majority-element/) — Easy — random sampling works; Boyer–Moore is the deterministic answer.
- [LC 229 · Majority Element II](https://leetcode.com/problems/majority-element-ii/) — Medium — generalised Boyer–Moore for $> n/3$.
- [LC 1157 · Online Majority Element In Subarray](https://leetcode.com/problems/online-majority-element-in-subarray/) — Hard — Example 2.
- [LC 1044 · Longest Duplicate Substring](https://leetcode.com/problems/longest-duplicate-substring/) — Hard — binary search + rolling hash; the birthday bound decides the modulus.
- [LC 187 · Repeated DNA Sequences](https://leetcode.com/problems/repeated-dna-sequences/) — Medium — exact 2-bit encoding beats hashing here.

## 10. Self-check

1. What is the difference between Las Vegas and Monte Carlo algorithms? Give one of each from this file.
2. Why does the sum hash mod $2^{64}$ fail with probability at most $2^{\nu_2(\Delta)-64}$?
3. Which question can the XOR hash answer that the sum hash cannot answer as directly, and vice versa?
4. How many random samples guarantee that a value with frequency $> 1/3$ is missed with probability below $10^{-9}$?
5. You hash $10^6$ distinct substrings modulo $10^9+7$ and insert them into a set. Estimate the expected number of colliding pairs.
6. Why does Freivalds' "NO" never lie, and what is the error of a "YES" after $k$ rounds over $\mathbb{F}_p$?
7. Why must you shuffle before `Arrays.sort(int[])` but not before `Arrays.sort(Integer[])`?
8. In the subpermutation example, why is each subpermutation counted exactly once across the two passes?

<details><summary>Answers</summary>

1. Las Vegas: always correct, random time (random-pivot quickselect, treap). Monte Carlo: fixed time, small error (Freivalds, hash comparison, sampling majority — which errs only by missing).
2. Fix all labels but one with $\Delta_u \ne 0$; $\Delta_u x \equiv t \pmod{2^{64}}$ has at most $2^{\nu_2(\Delta_u)}$ solutions.
3. XOR: "all counts even" is $H = 0$ (sum hash would need the counts themselves). Sum: exact multiset equality including counts like 1 vs 3.
4. $(2/3)^k < 10^{-9}$ → $k \ge 52$.
5. $\binom{10^6}{2}/(10^9+7) \approx 500$.
6. A NO comes with a vector $x$ where $A(Bx) \ne Cx$, which proves $AB \ne C$. YES errs with probability $\le p^{-k}$.
7. Primitive arrays use dual-pivot quicksort with known $O(n^2)$ inputs; object arrays use merge-sort-based TimSort, $O(n\log n)$ worst case.
8. A subpermutation has a unique maximum; pass 1 finds it iff the maximum is at or right of the 1, pass 2 iff strictly left.

</details>
