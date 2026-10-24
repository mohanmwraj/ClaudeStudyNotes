# Complexity and constraint reading

> **Band:** 🟢 ≤ 1400 (used at every band) · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [environment & templates](../00-Roadmap-and-Strategy/06-environment-templates-cpp-java.md)
> **You can say you know this when:** you can read a problem's constraints and, within a minute, list which complexity classes fit and which approaches are already dead; and you can prove the $O(n \log n)$ bound of a "loop over multiples" and the $O(n)$ bound of two pointers without hand-waving.

## 1. First principles — why this works

**The budget.** A judge gives you a time limit $T$ (usually 1–2 s on Codeforces) and a machine that executes some number $B$
of "simple operations" per second. Your solution is feasible when

$$\text{(number of basic steps)} \times \text{(cost per step)} \le B \cdot T .$$

Nobody knows $B$ exactly, so strong solvers use a deliberately crude planning number and a safety margin:

| Planning number (estimate, not a judge measurement) | C++ (`-O2`) | Java (as run on Codeforces) |
|---|---|---|
| Simple array/arithmetic steps per second, "normal" constant | $\approx 10^8$–$3\cdot 10^8$ | roughly 1.5–3× fewer |
| Tight sequential loop the compiler can vectorise | up to $\sim 10^9$ | lower |
| Random memory accesses into an array larger than the cache | $\sim 10^7$–$5\cdot10^7$ | similar or lower |
| `std::set` / `TreeMap` operations | $\sim 10^6$–$5\cdot10^6$ | lower |

Why the spread is so wide: the cost of a "step" is dominated by memory, not arithmetic. A quick local run with this kit's toolchain
(a shared Windows laptop, so treat only the ratios as meaningful) gave: 100 million sequential reads of an `int` array in
≈ 0.07 s, but 100 million *random* reads from a 64 MB array in ≈ 2.2 s — about **30× slower** — and inserting 1 million random
`int`s into a `std::set` took about **15×** longer than sorting the same million numbers.
Codeforces runs Java with `-XX:TieredStopAtLevel=1` (only the C1 JIT; verified in the Codeforces command-lines post, see
[08](../00-Roadmap-and-Strategy/08-research-findings-and-sources.md)), which is one reason heavy Java loops are slower there than on a default JVM.

**Constraints are a message from the problem setter.** The setter chose $n$ so that the intended solution passes comfortably and the
obvious slower one fails. Reverse the process: plug the largest $n$ into each candidate complexity and keep the ones that land
below $\sim 10^8$.

| $n$ up to | Typical feasible complexity | Work at the maximum $n$ | What it usually means |
|---|---|---|---|
| 10–11 | $O(n!\cdot n)$ | $11! \approx 4\cdot10^7$ | try all permutations |
| 15–18 | $O(2^n n^2)$, $O(3^n)$ | $2^{18}\cdot 18^2 \approx 8.5\cdot10^7$, $3^{16}\approx 4.3\cdot10^7$ | bitmask DP, submask enumeration |
| 20–25 | $O(2^n \cdot n)$ | $2^{20}\cdot 20 \approx 2\cdot10^7$ | all subsets |
| 35–45 | $O(2^{n/2}\cdot n)$ | $2^{20}\cdot 20$ | meet in the middle |
| 100–200 | $O(n^4)$, $O(n^3\log n)$ | $100^4=10^8$ | small DP with many dimensions |
| 300–500 | $O(n^3)$ | $500^3 = 1.25\cdot10^8$ | interval DP, Floyd–Warshall |
| 2000–5000 | $O(n^2)$, $O(n^2\log n)$ for $\approx 2000$ | $5000^2=2.5\cdot10^7$ | all pairs, quadratic DP |
| $10^5$–$2\cdot10^5$ | $O(n\log n)$, $O(n\log^2 n)$, $O(n\sqrt n)$ | $2\cdot10^5\cdot 18^2\approx 6.5\cdot10^7$; $2\cdot10^5\cdot 447\approx 9\cdot10^7$ | sorting, segment trees, binary search, sqrt decomposition |
| $10^6$ | $O(n\log n)$ (tight), $O(n)$ | $2\cdot10^7$ | linear scans, sieve, two pointers |
| $10^7$–$10^8$ | $O(n)$ with a tiny constant, $O(n\log\log n)$ | — | sieve, simple counting |
| $10^9$–$10^{12}$ | $O(\sqrt n)$, $O(n^{1/3})$, $O(\log n)$ | $\sqrt{10^{12}} = 10^6$ | divisor enumeration, math |
| $10^{18}$ | $O(\log n)$, $O(\log^2 n)$, $O(1)$ | $\log_2 10^{18}\approx 60$ | binary search, bits, closed forms |

Two refinements make the table far more useful:

1. **Read every constraint, not just $n$.** "$a_i \le 10^6$" means you may index an array by value; "$k \le 20$" means a bitmask over
   $k$ is affordable even if $n = 2\cdot10^5$; "$n\cdot m \le 10^6$" means a grid that may be $1 \times 10^6$ — store it flat.
   An asymmetric pair like $n \le 2\cdot10^5,\ m \le 1000$ is a strong hint that the answer is trivial when $n > m$ (see Example 5).
2. **Multi-test constraints.** "The sum of $n$ over all test cases does not exceed $2\cdot10^5$" bounds the *total* work:
   $\sum_i n_i\log n_i \le (\sum_i n_i)\log(\max n_i)$, so per-test $O(n\log n)$ is fine. It does **not** bound anything you do
   per test that is independent of $n$ — clearing a global array of size $10^6$ in each of $10^4$ tests is $10^{10}$ steps.

**Amortised analysis** answers "an operation is sometimes expensive — is the *total* still small?". The cleanest tool is the
*potential method*: pick a non-negative function $\Phi$ of the data structure's state, define the amortised cost of operation $i$
as $\hat c_i = c_i + \Phi_i - \Phi_{i-1}$, and telescope:

$$\sum_{i=1}^{m} c_i = \sum_{i=1}^{m} \hat c_i - \Phi_m + \Phi_0 \le \sum_{i=1}^{m}\hat c_i \quad (\text{when } \Phi_m \ge \Phi_0).$$

So bounding every $\hat c_i$ bounds the true total. Three proofs you will reuse constantly:

- **Dynamic array (`vector`, `ArrayList`) doubling.** Let $\Phi = 2\cdot\text{size} - \text{capacity}$. A push without resize costs 1
  and raises $\Phi$ by 2: $\hat c = 3$. A push that doubles capacity $k \to 2k$ copies $k$ elements, costs $k+1$, and changes
  $\Phi$ from $2k-k = k$ to $2(k+1)-2k = 2$, so $\hat c = (k+1) + 2 - k = 3$. Every push is amortised $O(1)$.
- **Two pointers.** If the left pointer $l$ and right pointer $r$ only move forward and each is at most $n$, the total number of
  pointer moves is at most $2n$, regardless of how the moves are distributed. (Potential: $\Phi = 2n - l - r$.)
  The argument dies the moment a pointer is ever reset backwards — that is the usual bug in "two pointers" that is really $O(n^2)$.
- **Monotonic stack / queue.** Each element is pushed once and popped at most once, so all pops together cost $\le n$.

**Harmonic sums.** "For every $d$, iterate over its multiples" looks like $O(n^2)$ but costs

$$\sum_{d=1}^{n} \left\lfloor \frac{n}{d}\right\rfloor \le n \sum_{d=1}^{n}\frac1d = n H_n, \qquad \ln(n+1) \le H_n \le 1 + \ln n,$$

so it is $O(n\log n)$. Proof of the bounds on $H_n$: compare the sum with $\int_1^{n+1} \frac{dx}{x}$ from below and with
$1 + \int_1^{n}\frac{dx}{x}$ from above (each term $\frac1d$ is the area of a unit-wide bar sitting above/below the curve $1/x$).
For $n = 10^6$, $nH_n \approx 1.4\cdot10^7$. This one fact gives the complexity of the divisor sieve, of "DP over multiples",
of iterating over all pairs $(d, kd)$, and of the Eratosthenes sieve ($\sum_{p\le n} n/p = O(n\log\log n)$ by Mertens' theorem —
standard knowledge, not verified in this research).

**Divide and conquer: the recursion tree.** For $T(n) = aT(n/b) + f(n)$, level $i$ of the recursion tree has $a^i$ nodes, each of
size $n/b^i$, so the total is $\sum_{i=0}^{\log_b n} a^i f(n/b^i)$. With $f(n) = n^c$ the level costs form a geometric series with ratio
$r = a/b^c$:

- $r < 1$: the root dominates, $T(n) = \Theta(n^c)$;
- $r = 1$: all $\log_b n$ levels cost the same, $T(n) = \Theta(n^c \log n)$;
- $r > 1$: the leaves dominate, $T(n) = \Theta(a^{\log_b n}) = \Theta(n^{\log_b a})$.

That is the whole Master theorem; the formal statement in §2 only adds the precise conditions.

## 2. Formulas, definitions and identities

**Asymptotic notation.** $f = O(g)$: $f(n) \le Cg(n)$ for large $n$; $f = \Omega(g)$: $f(n) \ge cg(n)$; $f = \Theta(g)$: both.
Amortised cost bounds a *worst-case sequence* of operations; expected cost averages over the algorithm's own randomness
(hashing, treaps, random pivots). Neither is the same as "average over inputs".

**Master theorem** (for $a\ge1$, $b>1$): with $T(n) = aT(n/b) + f(n)$ and critical exponent $c^* = \log_b a$,

1. $f(n) = O(n^{c^*-\varepsilon})$ for some $\varepsilon>0$ $\Rightarrow$ $T(n) = \Theta(n^{c^*})$;
2. $f(n) = \Theta(n^{c^*}\log^k n)$ with $k \ge 0$ $\Rightarrow$ $T(n) = \Theta(n^{c^*}\log^{k+1} n)$;
3. $f(n) = \Omega(n^{c^*+\varepsilon})$ and $af(n/b)\le \kappa f(n)$ for some $\kappa<1$ $\Rightarrow$ $T(n) = \Theta(f(n))$.

Proof sketch: the recursion tree of §1; case 2 has $\log_b n$ levels each costing $\Theta(n^{c^*}\log^k(n/b^i))$, which sums to
$\Theta(n^{c^*}\log^{k+1}n)$.

| Recurrence | Where it appears | Solution |
|---|---|---|
| $T(n) = T(n/2) + O(1)$ | binary search | $O(\log n)$ |
| $T(n) = 2T(n/2) + O(1)$ | building a segment tree | $O(n)$ |
| $T(n) = 2T(n/2) + O(n)$ | merge sort, D&C on arrays | $O(n\log n)$ |
| $T(n) = 2T(n/2) + O(n\log n)$ | D&C with a sort inside (CDQ) | $O(n\log^2 n)$ |
| $T(n) = 3T(n/2) + O(n)$ | Karatsuba multiplication | $O(n^{\log_2 3}) \approx O(n^{1.585})$ |
| $T(n) = T(n-1) + O(n)$ | naive selection / insertion | $O(n^2)$ |
| $T(n) = 2T(n-1) + O(1)$ | naive subset recursion, Hanoi | $O(2^n)$ |
| $T(n) = T(n/2) + T(n/4) + O(n)$ | uneven splits with fractions summing to $<1$ | $O(n)$ (level costs shrink geometrically) |

**Sums you need.**

- $\sum_{i=1}^{n} i = \frac{n(n+1)}{2}$ — so a loop over pairs $i<j$ is $\binom n2 = \frac{n(n-1)}2$ steps, half of $n^2$.
- $\sum_{i=1}^{n} i^2 = \frac{n(n+1)(2n+1)}{6}$; triples $i<j<k$: $\binom n3 \approx n^3/6$ — an $O(n^3)$ loop over sorted triples with $n=500$ is only $2\cdot10^7$.
- $\sum_{i=0}^{k} 2^i = 2^{k+1}-1$ — a complete binary tree over $n$ leaves has fewer than $2\cdot 2^{\lceil\log_2 n\rceil} \le 4n$ nodes.
- $\sum_{d=1}^n \lfloor n/d\rfloor = \Theta(n\log n)$; $\lfloor n/d\rfloor$ takes at most $2\sqrt n$ distinct values (for $d\le\sqrt n$ there are $\sqrt n$ values of $d$; for $d>\sqrt n$ the quotient is $<\sqrt n$).
- $\log_2 n!\;=\;n\log_2 n - n\log_2 e + O(\log n)$ (Stirling) — the comparison-sorting lower bound, see [sorting](05-sorting-and-comparators.md).

**Balancing two terms.** If a method costs $qB + qn/B$ for a block size $B$ of your choice, the minimum is at $B=\sqrt n$
(derivative $q - qn/B^2 = 0$), giving $O(q\sqrt n)$. This is how every sqrt-decomposition block size is chosen
([sqrt decomposition](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md)).

**Logarithms to memorise.** $\log_2 10^3\approx 10$, $\log_2 10^5 \approx 16.6$, $\log_2(2\cdot10^5)\approx 17.6$,
$\log_2 10^6\approx 20$, $\log_2 10^9 \approx 30$, $\log_2 10^{18}\approx 60$. One $\log$ factor at $n=2\cdot10^5$ is $\times18$; two are $\times 320$.

**Memory.** 256 MB $= 2^{28}$ bytes $\approx 2.7\cdot10^8$ bytes.

| Item | Bytes | 256 MB holds about |
|---|---|---|
| `char` / `bool` / Java `byte`, `boolean` (in arrays) | 1 | $2.6\cdot10^8$ |
| `int` / Java `int` | 4 | $6.7\cdot10^7$ (≈ 64 M) |
| `long long`, `double` / Java `long`, `double` | 8 | $3.3\cdot10^7$ |
| `vector<bool>` / `bitset` / Java `long[]` used as bits | 1/8 | $2\cdot10^9$ bits |
| `std::set<int>` node (3 pointers + colour + value, padded) | ≈ 40 | $6\cdot10^6$ |
| empty `std::vector` object | 24 | — |
| Java `Integer` object + reference in an `ArrayList` | ≈ 16 + 4–8 | 4–6× an `int[]` |
| Java array header | 16 | — (matters for millions of tiny arrays) |

These are typical 64-bit figures (standard knowledge, not verified in this research); always leave headroom for the program itself and the stack.

## 3. Implementation (C++ and Java)

**Loop over multiples — all divisor lists in $O(n\log n)$.** The harmonic bound of §1 in code. Use it whenever you need
"for each $x$, something about its divisors" for all $x \le n$.

```cpp
// divs[x] = all divisors of x, for 1 <= x <= n.  Total size = sum_{d<=n} floor(n/d) = O(n log n).
vector<vector<int>> divisorLists(int n) {
    vector<vector<int>> divs(n + 1);
    for (int d = 1; d <= n; d++)
        for (int m = d; m <= n; m += d) divs[m].push_back(d);
    return divs;
}

// Cheaper when you only need counts: d(x) for all x <= n, no per-x vectors.
vector<int> divisorCounts(int n) {
    vector<int> cnt(n + 1, 0);
    for (int d = 1; d <= n; d++)
        for (int m = d; m <= n; m += d) cnt[m]++;
    return cnt;
}
```

```java
static List<Integer>[] divisorLists(int n) {
    @SuppressWarnings("unchecked")
    List<Integer>[] divs = new List[n + 1];
    for (int i = 0; i <= n; i++) divs[i] = new ArrayList<>();
    for (int d = 1; d <= n; d++)
        for (int m = d; m <= n; m += d) divs[m].add(d);
    return divs;
}

static int[] divisorCounts(int n) {
    int[] cnt = new int[n + 1];
    for (int d = 1; d <= n; d++)
        for (int m = d; m <= n; m += d) cnt[m]++;
    return cnt;
}
```

For $n = 10^6$ the lists hold $\approx 1.4\cdot10^7$ entries: fine as `int`s in C++, heavy as boxed `Integer`s in Java (prefer the
counts version or a flattened CSR layout: one `int[]` of all divisors plus an offsets array).

**Per-test reset without paying for the whole array.** When values are bounded globally (say $\le 10^6$) but only the sum of $n$ is
bounded, never clear the whole counting array per test. Either undo exactly what you touched, or use timestamps:

```cpp
// cnt[] is shared across tests; stamp[v] != curTest means "cnt[v] is stale, treat as 0".
const int MAXV = 1'000'000;
int cnt[MAXV + 1], stampOf[MAXV + 1], curTest = 0;

int getCount(int v) { return stampOf[v] == curTest ? cnt[v] : 0; }
void addCount(int v) {
    if (stampOf[v] != curTest) { stampOf[v] = curTest; cnt[v] = 0; }
    cnt[v]++;
}
// at the start of each test: curTest++;   O(1) instead of O(MAXV)
```

```java
static final int MAXV = 1_000_000;
static int[] cnt = new int[MAXV + 1], stampOf = new int[MAXV + 1];
static int curTest = 0;

static int getCount(int v) { return stampOf[v] == curTest ? cnt[v] : 0; }
static void addCount(int v) {
    if (stampOf[v] != curTest) { stampOf[v] = curTest; cnt[v] = 0; }
    cnt[v]++;
}
// at the start of each test: curTest++;
```

**Two pointers skeleton with the amortisation visible.** `l` never moves left, so the inner `while` runs at most $n$ times in total.

```cpp
// Longest window [l, r] whose sum is <= limit (all a[i] >= 0).
int longestWindow(const vector<long long>& a, long long limit) {
    int best = 0, l = 0;
    long long sum = 0;
    for (int r = 0; r < (int)a.size(); r++) {
        sum += a[r];
        while (sum > limit) sum -= a[l++];     // total iterations over the whole loop <= n
        best = max(best, r - l + 1);
    }
    return best;
}
```

```java
static int longestWindow(long[] a, long limit) {
    int best = 0, l = 0;
    long sum = 0;
    for (int r = 0; r < a.length; r++) {
        sum += a[r];
        while (sum > limit) sum -= a[l++];
        best = Math.max(best, r - l + 1);
    }
    return best;
}
```

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| $n \le 20$ (or a second parameter $\le 20$) | iterate over all $2^n$ subsets, bitmask DP ([bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md)) |
| $n \le 40$ | split in halves: meet in the middle ([MITM](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md)) |
| $n \le 500$ | $O(n^3)$: interval DP, Floyd–Warshall, triple loops over sorted triples |
| $n \le 5000$ | $O(n^2)$ is intended; an $O(n^2)$ *memory* table may still be too big ($5000^2$ `long long` = 200 MB) |
| $n \le 2\cdot10^5$ and "$q$ queries" | $O((n+q)\log n)$: prefix sums, sorting + binary search, Fenwick/segment tree |
| values $\le 10^6$ | arrays indexed by value, sieve, harmonic loops over multiples |
| $n \le 10^{18}$ | binary search on the answer, bit-by-bit reasoning, closed-form formula, matrix power |
| "sum of $n$ over all test cases $\le X$" | per-test cost must depend only on that test's $n$ — no global clears |
| "sum of $n^2$ over all test cases $\le X$" | an $O(n^2)$ (or $O(n^2\log n)$) per-test solution is explicitly invited |
| two parameters with very different limits | the small one is the exponent or the loop you can afford; check whether the large one makes the answer trivial |
| time limit 3–5 s | an $O(n\sqrt n)$ or heavy-constant solution is probably intended |
| memory limit below 256 MB | no $O(n^2)$ tables, no boxed collections of millions of items |

Often confused: "$q \le 2\cdot10^5$ queries" does not mean each query may cost $O(n)$ — $q\cdot n = 4\cdot10^{10}$. And output size
counts: printing $n^2$ numbers for $n = 5000$ is $2.5\cdot10^7$ tokens and needs buffered output.

## 5. Worked examples (graded)

### Example 1 — Petr and a Combination Lock  ·  ★ 1200

- **Source:** [CF 1097B · Petr and a Combination Lock](https://codeforces.com/problemset/problem/1097/B) — 1200
- **Difficulty:** 1200
- **Problem:** A dial starts at 0. You must perform $n \le 15$ rotations by given angles $a_i$ ($1\le a_i\le180$), each either clockwise
  or counter-clockwise. Can the pointer end at 0 again?
- **Thinking from first principles:** each rotation has 2 choices, so there are $2^n \le 32768$ sign patterns — the constraint
  $n\le15$ is shouting "try them all". Ending at 0 means the signed sum is divisible by 360. A cleverer DP over residues mod 360
  exists ($O(360n)$), but with $2^{15}\cdot15 \approx 5\cdot10^5$ steps the brute force is already instant; spending time on the DP would be
  a contest mistake.

<details><summary>Solution</summary>

Enumerate every mask; bit $i$ set means rotation $i$ is clockwise. Check whether $\sum \pm a_i \equiv 0 \pmod{360}$.
`s % 360 == 0` is correct even for negative `s` in both languages, because only zero-ness is tested. $O(2^n n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> a(n);
    for (auto& x : a) cin >> x;
    bool ok = false;
    for (int mask = 0; mask < (1 << n) && !ok; mask++) {
        int s = 0;
        for (int i = 0; i < n; i++) s += (mask >> i & 1) ? a[i] : -a[i];
        if (s % 360 == 0) ok = true;
    }
    cout << (ok ? "YES" : "NO") << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        boolean ok = false;
        for (int mask = 0; mask < (1 << n) && !ok; mask++) {
            int s = 0;
            for (int i = 0; i < n; i++) s += ((mask >> i) & 1) == 1 ? a[i] : -a[i];
            if (s % 360 == 0) ok = true;
        }
        System.out.println(ok ? "YES" : "NO");
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
10
20
30
out:
YES
-->
<!-- test
in:
1
180
out:
NO
-->
<!-- test
in:
3
100
100
100
out:
NO
-->
<!-- test
in:
2
120
240
out:
YES
-->

### Example 2 — Books  ·  ★ 1400

- **Source:** [CF 279B · Books](https://codeforces.com/problemset/problem/279/B) — 1400
- **Difficulty:** 1400
- **Problem:** $n \le 10^5$ books with reading times $a_i \le 10^4$ and free time $t \le 10^9$. Choose a starting book and read books
  $i, i+1, \dots$ in order until the next one does not fit. Maximise the number of books read.
- **Thinking from first principles:** the naive answer tries every start and walks forward: $O(n^2) = 10^{10}$ — dead. Observe
  monotonicity: if the window $[l, r]$ fits, then $[l+1, r]$ fits too (times are positive). So when $r$ advances, the best $l$ for
  this $r$ can only move right. That is exactly the two-pointer invariant, and the potential argument of §1 gives $O(n)$ total.
  Binary search on prefix sums ($O(n\log n)$) also passes; two pointers is shorter.

<details><summary>Solution</summary>

Maintain the longest window ending at $r$ with sum $\le t$; shrink from the left while it is too long. Each index enters and
leaves the window once: $O(n)$. If a single book exceeds $t$, the window becomes empty and contributes 0.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    long long t;
    cin >> n >> t;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    int best = 0, l = 0;
    long long sum = 0;
    for (int r = 0; r < n; r++) {
        sum += a[r];
        while (sum > t) sum -= a[l++];
        best = max(best, r - l + 1);
    }
    cout << best << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long t = in.nextLong();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        int best = 0, l = 0;
        long sum = 0;
        for (int r = 0; r < n; r++) {
            sum += a[r];
            while (sum > t) sum -= a[l++];
            best = Math.max(best, r - l + 1);
        }
        System.out.println(best);
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
4 5
3 1 2 1
out:
3
-->
<!-- test
in:
3 1
2 2 3
out:
0
-->
<!-- test
in:
1 10
10
out:
1
-->

### Example 3 — Orac and Models  ·  ★ 1400

- **Source:** [CF 1350B · Orac and Models](https://codeforces.com/problemset/problem/1350/B) — 1400
- **Difficulty:** 1400
- **Problem:** Models $1..n$ have sizes $s_i \le 10^9$. Pick indices $i_1 < i_2 < \dots$ such that each index divides the next and sizes
  strictly increase. Maximise the count. Multiple tests, $\sum n \le 10^5$.
- **Thinking from first principles:** "each index divides the next" is a DAG on indices with edges $i \to ki$. Longest path in a DAG
  ordered by index = DP: $dp[j] = 1 + \max\{dp[i] : i \mid j,\ i<j,\ s_i < s_j\}$. How many edges? Index $i$ has $\lfloor n/i\rfloor - 1$
  multiples, so the edge count is $\sum_i n/i = O(n\log n)$ — the harmonic sum. Pushing forward along multiples avoids factorising.

<details><summary>Solution</summary>

Process $i = 1..n$ in increasing order; $dp[i]$ is final when reached because all its divisors are smaller. Relax every multiple.
$O(n\log n)$ per test, and the sum over tests is bounded by $\sum n \log n$.

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
        vector<long long> s(n + 1);
        for (int i = 1; i <= n; i++) cin >> s[i];
        vector<int> dp(n + 1, 1);
        int best = 1;
        for (int i = 1; i <= n; i++) {
            best = max(best, dp[i]);
            for (int j = 2 * i; j <= n; j += i)
                if (s[i] < s[j]) dp[j] = max(dp[j], dp[i] + 1);
        }
        cout << best << '\n';
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
            long[] s = new long[n + 1];
            for (int i = 1; i <= n; i++) s[i] = in.nextLong();
            int[] dp = new int[n + 1];
            Arrays.fill(dp, 1);
            int best = 1;
            for (int i = 1; i <= n; i++) {
                best = Math.max(best, dp[i]);
                for (int j = 2 * i; j <= n; j += i)
                    if (s[i] < s[j]) dp[j] = Math.max(dp[j], dp[i] + 1);
            }
            out.println(best);
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
4
5 3 4 6
1
9
8
1 2 3 4 5 6 7 8
5
5 4 3 2 1
out:
2
1
4
1
-->
<!-- test
in:
1
12
1 1 2 1 1 3 1 1 1 1 1 4
out:
4
-->

### Example 4 — Special Elements  ·  ★ 1500

- **Source:** [CF 1352E · Special Elements](https://codeforces.com/problemset/problem/1352/E) — 1500
- **Difficulty:** 1500
- **Problem:** Array of $n \le 8000$ values with $1 \le a_i \le n$ ($\sum n \le 8000$). An element is *special* if it equals the sum of some
  contiguous segment of length $\ge 2$. Count special elements (each position counts separately).
- **Thinking from first principles:** there are $\binom n2 \approx 3.2\cdot10^7$ segments — affordable, but only with a tiny constant:
  no `set`, no hashing, no recomputing sums. Two observations make it cheap. (1) Extend segments from each left end, so each new
  sum costs one addition. (2) Since $a_i \le n$, a segment sum above $n$ can never be matched, and sums only grow as the segment
  extends ($a_i\ge1$) — so break early and record hits in a boolean array of size $n+1$ instead of a hash set.

<details><summary>Solution</summary>

`mark[s] = 1` for every segment sum $s \le n$ of length $\ge2$; then count positions $i$ with `mark[a[i]]`. $O(n^2)$ time,
$O(n)$ memory per test.

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
        vector<int> a(n);
        for (auto& x : a) cin >> x;
        vector<char> mark(n + 1, 0);
        for (int l = 0; l < n; l++) {
            int s = a[l];
            for (int r = l + 1; r < n; r++) {
                s += a[r];
                if (s > n) break;          // sums only grow; values never exceed n
                mark[s] = 1;
            }
        }
        int cnt = 0;
        for (int x : a) cnt += mark[x];
        cout << cnt << '\n';
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
            int[] a = new int[n];
            for (int i = 0; i < n; i++) a[i] = in.nextInt();
            boolean[] mark = new boolean[n + 1];
            for (int l = 0; l < n; l++) {
                int s = a[l];
                for (int r = l + 1; r < n; r++) {
                    s += a[r];
                    if (s > n) break;
                    mark[s] = true;
                }
            }
            int cnt = 0;
            for (int x : a) if (mark[x]) cnt++;
            out.println(cnt);
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
5
1 1 2 3 5
1
1
4
1 1 1 1
3
1 2 3
out:
3
0
0
1
-->
<!-- test
in:
1
6
2 2 4 4 6 6
out:
4
-->

### Example 5 — Kuroni and Impossible Calculation  ·  ★ 1600

- **Source:** [CF 1305C · Kuroni and Impossible Calculation](https://codeforces.com/problemset/problem/1305/C) — 1600
- **Difficulty:** 1600
- **Problem:** Given $n \le 2\cdot10^5$ numbers $a_i \le 10^9$ and a modulus $m \le 1000$, output $\prod_{i<j}|a_i - a_j| \bmod m$.
- **Thinking from first principles:** the product has $\sim 2\cdot10^{10}$ factors — impossible directly. The asymmetric constraints
  ($n$ large, $m$ tiny) are the hint. Consider residues mod $m$: there are only $m$ of them. If $n > m$, two numbers share a residue
  (pigeonhole), their difference is divisible by $m$, and the whole product is $0 \bmod m$. Otherwise $n \le m \le 1000$, and the
  direct $O(n^2) \le 5\cdot10^5$ product is trivial.

<details><summary>Solution</summary>

If $n>m$ print 0; else multiply $|a_i-a_j| \bmod m$ over all pairs, reducing after each multiplication (operands $< 1000$, so `int`
products are safe). Note $m=1$ always gives 0, which both branches handle.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    if (n > m) { cout << 0 << '\n'; return 0; }   // pigeonhole: two equal residues
    long long prod = 1 % m;
    for (int i = 0; i < n; i++)
        for (int j = i + 1; j < n; j++)
            prod = prod * (llabs(a[i] - a[j]) % m) % m;
    cout << prod << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        if (n > m) { System.out.println(0); return; }
        long prod = 1 % m;
        for (int i = 0; i < n; i++)
            for (int j = i + 1; j < n; j++)
                prod = prod * (Math.abs(a[i] - a[j]) % m) % m;
        System.out.println(prod);
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
2 10
8 5
out:
3
-->
<!-- test
in:
3 1000
1 4 5
out:
12
-->
<!-- test
in:
3 12
1 4 5
out:
0
-->
<!-- test
in:
4 3
1 2 3 4
out:
0
-->
<!-- test
in:
2 1
5 5
out:
0
-->

## 6. Tricks, pitfalls and things to remember

1. **Clearing global arrays per test** (`memset`, `Arrays.fill` over `MAXN`) turns "sum of $n \le 2\cdot10^5$" into $t \cdot \text{MAXN}$
   work. Allocate per test with size $n$, undo what you touched, or use timestamps (§3).
2. **`for (int i = 0; i < v.size() - 1; i++)`** with an empty `v`: `size()` is unsigned, `0 - 1` wraps to $2^{64}-1$, the loop runs
   forever or crashes. Cast: `(int)v.size() - 1`.
3. **Hidden linear work in a loop condition**: `strlen(s)` in `for (i = 0; i < strlen(s); i++)` is $O(n)$ per check → $O(n^2)$.
4. **Passing containers by value** into recursive functions copies them on every call. Pass `const vector<int>&` (C++); in Java
   references are passed anyway, but `new ArrayList<>(list)` / `substring` in a recursion are copies.
5. **`endl` flushes.** $2\cdot10^5$ lines with `endl` can cost far more than the algorithm. Use `'\n'`; in Java, one `PrintWriter`
   flushed once at the end — never `System.out.println` in a loop.
6. **String building**: Java `s += c` in a loop is $O(n^2)$ (new string each time); C++ `s = s + c` is also $O(n^2)$, while `s += c`
   is amortised $O(1)$. Use `StringBuilder` / `+=`.
7. **A `map` where an array would do.** Keys bounded by $10^6$ → use an array: no $\log$ factor, no 40-byte nodes, no cache misses.
8. **Recursion depth.** A DFS on a path of $10^6$ vertices needs a deep stack. Codeforces links C++ with a 256 MB stack
   (`-Wl,--stack=268435456`, per its command-lines post); Java needs the `Thread` trick or an iterative rewrite
   ([recursion](04-recursion-brute-force-and-backtracking.md)).
9. **Two "independent" loops that are really nested.** `while` inside `for` is still $O(n)$ only if the inner variable never resets.
   Before trusting an amortised bound, name the potential (what only moves one way).
10. **Output size is part of the complexity.** If the answer has $n^2$ numbers, the solution is at least $\Omega(n^2)$.
11. **Memory of 2D containers.** `vector<vector<int>>` with $10^6$ rows of length 1 costs 24 MB of headers plus allocator overhead;
    in Java, `int[1000000][1]` costs ~16 MB of headers. Flatten to `a[i * m + j]` when one dimension may be tiny.
12. **Constant factors you can usually ignore up to ~$10^8$, and must not ignore beyond.** Random access, `std::set`, `TreeMap`,
    `HashMap<Long,…>` and boxing are the 10–50× multipliers. Sorting plus a linear scan almost always beats a balanced tree.

## 7. Going further (toward 2400–2600+)

- **Akra–Bazzi** generalises the Master theorem to uneven splits $T(n) = \sum a_i T(b_i n) + f(n)$: find $p$ with $\sum a_i b_i^p = 1$, then
  $T(n) = \Theta\!\big(n^p(1 + \int_1^n \frac{f(u)}{u^{p+1}}du)\big)$ (standard knowledge, not verified in this research).
- **Small-to-large merging** costs $O(n\log n)$ because an element moves only when the set it lives in at least doubles — the
  potential is $\sum \log(\text{size of own set})$. See [small to large](../10-Trees/03-small-to-large-and-dsu-on-tree.md).
- **DSU** with union by size and path compression is $O(\alpha(n))$ amortised; with rollback you lose path compression and the
  amortisation, so you keep only union by size: $O(\log n)$ ([DSU](../08-Data-Structures/06-dsu-and-variants.md),
  [DSU rollback](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md)).
- **Choosing thresholds** (heavy/light by degree $\sqrt m$, block size in Mo's algorithm $n/\sqrt q$) is the "balance two terms" idea
  applied with care; see [advanced sqrt](../16-IGM-Frontier/06-advanced-sqrt-techniques.md).
- **Bitset speed-ups** divide a quadratic inner loop by 64 ($n^2/64$ for $n = 10^5$ is $1.6\cdot10^8$ word operations):
  [bitset optimisation](../16-IGM-Frontier/05-bitset-optimization.md).
- **Floor-division blocks**: iterating over the $O(\sqrt n)$ distinct values of $\lfloor n/d\rfloor$ is the core of many number-theory
  sums ([floor sums](../04-Number-Theory/07-mobius-dirichlet-and-floor-sums.md)).

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1068 · Weird Algorithm](https://cses.fi/problemset/task/1068) — values exceed 32 bits
- [ ] [CSES 1083 · Missing Number](https://cses.fi/problemset/task/1083)
- [ ] [CF 1520D · Same Differences](https://codeforces.com/problemset/problem/1520/D) — 1200
- [ ] [CF 1097B · Petr and a Combination Lock](https://codeforces.com/problemset/problem/1097/B) — 1200
- [ ] [AtCoder ABC128 C · Switches](https://atcoder.jp/contests/abc128/tasks/abc128_c) — diff≈805
- [ ] [CF 1692F · 3SUM](https://codeforces.com/problemset/problem/1692/F) — 1300
- [ ] [CF 1661B · Getting Zero](https://codeforces.com/problemset/problem/1661/B) — 1300
- [ ] [CF 476B · Dreamoon and WiFi](https://codeforces.com/problemset/problem/476/B) — 1300
- [ ] [CF 279B · Books](https://codeforces.com/problemset/problem/279/B) — 1400
- [ ] [CF 1350B · Orac and Models](https://codeforces.com/problemset/problem/1350/B) — 1400
- [ ] [CF 550B · Preparing Olympiad](https://codeforces.com/problemset/problem/550/B) — 1400
- [ ] [CF 1904C · Array Game](https://codeforces.com/problemset/problem/1904/C) — 1400

**1400–1700**
- [ ] [CSES 1640 · Sum of Two Values](https://cses.fi/problemset/task/1640)
- [ ] [CSES 1641 · Sum of Three Values](https://cses.fi/problemset/task/1641)
- [ ] [CSES 1642 · Sum of Four Values](https://cses.fi/problemset/task/1642)
- [ ] [CF 1352E · Special Elements](https://codeforces.com/problemset/problem/1352/E) — 1500
- [ ] [CF 1385D · a-Good String](https://codeforces.com/problemset/problem/1385/D) — 1500
- [ ] [CF 1915F · Greetings](https://codeforces.com/problemset/problem/1915/F) — 1500
- [ ] [CF 1305C · Kuroni and Impossible Calculation](https://codeforces.com/problemset/problem/1305/C) — 1600
- [ ] [CF 1920C · Partitioning the Array](https://codeforces.com/problemset/problem/1920/C) — 1600

**1700+**
- [ ] [CF 1554B · Cobb](https://codeforces.com/problemset/problem/1554/B) — 1700
- [ ] [CF 466C · Number of Ways](https://codeforces.com/problemset/problem/466/C) — 1700
- [ ] [CF 1288D · Minimax Problem](https://codeforces.com/problemset/problem/1288/D) — 2000

## 9. LeetCode / FAANG cross-reference

Interviewers expect you to state time and space complexity unprompted and to explain *why* (amortisation, harmonic sums).

- [LC 1 · Two Sum](https://leetcode.com/problems/two-sum/) — Easy — trade $O(n^2)$ pairs for an $O(n)$ hash lookup.
- [LC 15 · 3Sum](https://leetcode.com/problems/3sum/) — Medium — sort + two pointers turns $O(n^3)$ into $O(n^2)$.
- [LC 18 · 4Sum](https://leetcode.com/problems/4sum/) — Medium — the same reduction one level deeper.
- [LC 209 · Minimum Size Subarray Sum](https://leetcode.com/problems/minimum-size-subarray-sum/) — Medium — amortised two pointers.
- [LC 3 · Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/) — Medium — the left pointer never moves back.
- [LC 204 · Count Primes](https://leetcode.com/problems/count-primes/) — Medium — sieve, $O(n\log\log n)$.
- [LC 50 · Pow(x, n)](https://leetcode.com/problems/powx-n/) — Medium — $O(\log n)$ by halving the exponent.
- [LC 1010 · Pairs of Songs With Total Durations Divisible by 60](https://leetcode.com/problems/pairs-of-songs-with-total-durations-divisible-by-60/) — Medium — count residues instead of pairs.

## 10. Self-check

1. $n = 2\cdot10^5$ and $q = 2\cdot10^5$. Which of $O(nq)$, $O((n+q)\log n)$, $O((n+q)\sqrt n)$, $O(n\log^2 n + q\log^2 n)$ are safe in 2 s C++?
2. Prove that pushing $m$ elements into a doubling array costs $O(m)$ in total.
3. What is $\sum_{d=1}^{n}\lfloor n/d\rfloor$ asymptotically, and why?
4. Solve $T(n) = 4T(n/2) + n$ and $T(n) = 2T(n/2) + n\log n$.
5. A problem has $t \le 10^4$ tests, $\sum n \le 2\cdot10^5$, values $\le 10^6$. What goes wrong with `memset(cnt, 0, sizeof cnt)` per test, and what do you do instead?
6. How many `long long` fit in 256 MB? Can you store a $5000\times5000$ `long long` DP table?
7. When does a two-pointer loop stop being $O(n)$?

<details><summary>Answers</summary>

1. $O(nq) = 4\cdot10^{10}$ no; $O((n+q)\log n)\approx 7\cdot10^6$ yes; $O((n+q)\sqrt n)\approx 1.8\cdot10^8$ usually yes with a small constant; $O((n+q)\log^2 n)\approx 1.3\cdot10^8$ yes.
2. Potential $\Phi = 2\cdot\text{size}-\text{capacity}$; every push has amortised cost 3 (derivation in §1), and $\Phi\ge0$ after the first push, so the total is $\le 3m$.
3. $\Theta(n\log n)$: it is at most $nH_n \le n(1+\ln n)$ and at least $n\ln(n+1) - n$.
4. $a=4,b=2$: $c^*=2 > 1$, so $\Theta(n^2)$. $a=2,b=2$, $f = n\log n$: case 2 with $k=1$, so $\Theta(n\log^2 n)$.
5. $10^4 \times 4\cdot10^6$ bytes $= 4\cdot10^{10}$ bytes written — TLE. Reset only the touched entries (or use a timestamp array).
6. $2^{28}/8 \approx 3.3\cdot10^7$. A $5000^2 = 2.5\cdot10^7$ table needs 200 MB — technically under 256 MB but leaves little room; roll the DP to two rows if a row depends only on the previous one.
7. When either pointer can move backwards (e.g. resetting `l` for each `r`), or the inner step is not $O(1)$ (e.g. a `set` operation, which makes it $O(n\log n)$).

</details>
