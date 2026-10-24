# Sorting and comparators

> **Band:** 🟢 ≤ 1400 → 🔵 1700 (comparator design and sorting invariants) · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [complexity](01-complexity-and-constraint-reading.md), [STL & Collections](02-cpp-stl-and-java-collections.md)
> **You can say you know this when:** you can write a comparator for any multi-key order in both languages and *prove* it is a strict weak ordering, count inversions with merge sort, explain why comparison sorting needs $\Omega(n\log n)$ and when counting/radix sort beats it, and you never get hacked through Java's `Arrays.sort(int[])` or a `<=` comparator.

## 1. First principles — why this works

**Why sorting is the most common first step.** Sorting replaces "an arbitrary arrangement" by a canonical one in which *order relations become
positions*: equal values are adjacent, "everything smaller than $x$" is a prefix, the $k$-th smallest is at index $k$, and many greedy choices
("always take the smallest that fits") become a single left-to-right scan. Whenever the answer does not depend on the input order — sums of
pairs, matchings, "how many are within distance $d$" — you are free to sort first. Paying $O(n\log n)$ once usually turns an $O(n^2)$ search into
two pointers or binary search ([two pointers](../02-Core-Techniques/03-two-pointers-and-sliding-window.md),
[binary search](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md)).

**The lower bound.** A comparison sort learns about the input only through yes/no answers to "$a_i < a_j$?". Model the algorithm as a
binary decision tree: each internal node is a comparison, each leaf an output order. All $n!$ permutations of distinct keys must reach
different leaves (otherwise two inputs needing different outputs get the same one), so the tree has $\ge n!$ leaves and height

$$h \ge \log_2 n! \ge \log_2\left(\tfrac n2\right)^{n/2} = \tfrac n2\log_2\tfrac n2 = \Omega(n\log n).$$

(Half of the factors of $n!$ are at least $n/2$.) Stirling sharpens it to $\log_2 n! = n\log_2 n - n\log_2 e + O(\log n)$. Merge sort uses at most
$n\lceil\log_2 n\rceil$ comparisons, so it is optimal up to lower-order terms.

**Escaping the bound.** The bound only holds for algorithms that *compare*. If keys are integers in a small range $[0, K)$, **counting sort**
places each key by direct indexing in $O(n + K)$. **Radix sort** applies a stable counting sort digit by digit from the least significant digit:
after pass $d$ the array is sorted by the last $d$ digits (induction: the stable pass on digit $d$ keeps the earlier order among equal digit-$d$
values), so $w$-bit keys in base $2^b$ take $\lceil w/b\rceil$ passes of $O(n + 2^b)$.

**What a comparator must satisfy.** `std::sort`, `std::set`, `Arrays.sort`, `Collections.sort`, `TreeMap` all assume the comparison
`comp(a, b)` ("$a$ goes before $b$") is a **strict weak ordering**:

1. irreflexive: `comp(a, a)` is false;
2. asymmetric: `comp(a, b)` implies not `comp(b, a)`;
3. transitive: `comp(a, b)` and `comp(b, c)` imply `comp(a, c)`;
4. *incomparability is transitive*: if $a\sim b$ (neither goes first) and $b \sim c$ then $a\sim c$ — so "equivalent" elements form classes.

The safest way to satisfy all four is to **map each element to a key in a totally ordered set and compare keys**: tuples of numbers compared
lexicographically, or a real-valued function (Example 5 proves its comparator this way). `<=` violates (1); a comparator on floating values with
NaN violates (4); "random" tie-breaking violates everything. In C++ a violation is undefined behaviour (with GCC's implementation `std::sort`
may run past the end of the array and crash when many elements compare "equal" — standard knowledge, not verified in this research); in Java,
TimSort may throw `IllegalArgumentException: Comparison method violates its general contract!` or silently mis-sort.

**Stability.** A sort is stable if equivalent elements keep their input order. It matters when you sort by one key after another (sort by
secondary key, then *stably* by primary key = sort by (primary, secondary)) and when the problem's tie-break is "earlier in the input first".
`std::sort` is not stable; `std::stable_sort` is. In Java, every sort of objects (`Arrays.sort(Object[])`, `Collections.sort`, `List.sort`) is stable
TimSort; sorts of primitive arrays are not (stability is meaningless for indistinguishable primitives anyway).

**Inversions measure disorder.** An inversion is a pair $i<j$ with $a_i > a_j$. Swapping two *adjacent* out-of-order elements removes exactly
one inversion and changes no other pair's relative order, so the minimum number of adjacent swaps to sort equals the number of inversions,
insertion sort runs in $O(n + \text{inv})$, and merge sort can count them: when merging, every time an element is taken from the right half,
all elements still waiting in the left half are larger and earlier — that many inversions (Example 4).

## 2. Formulas, definitions and identities

| Algorithm | Time | Extra memory | Stable | Notes |
|---|---|---|---|---|
| `std::sort` (introsort) | $O(n\log n)$ worst case (required since C++11) | $O(\log n)$ | no | quicksort + heapsort fallback + insertion sort |
| `std::stable_sort` (merge sort) | $O(n\log n)$; $O(n\log^2 n)$ without spare memory | $O(n)$ | yes | |
| `std::partial_sort`, `nth_element` | $O(n\log k)$, expected $O(n)$ | $O(1)$ | no | top-$k$, median |
| Java `Arrays.sort(int[]/long[]/double[])` (dual-pivot quicksort) | expected $O(n\log n)$; JDK 17/21 fall back to heapsort beyond a recursion-depth limit, JDK 11 does not | $O(\log n)$ | n/a | see the hack warning in §6 |
| Java `Arrays.sort(T[])`, `Collections.sort`, `List.sort` (TimSort) | $O(n\log n)$ worst, $O(n)$ on sorted runs | $O(n)$ | yes | boxing cost for `Integer[]` |
| counting sort | $O(n + K)$ | $O(n + K)$ | yes (prefix-sum version) | keys in $[0, K)$ |
| LSD radix sort, base $2^b$, $w$-bit keys | $O(\lceil w/b\rceil (n + 2^b))$ | $O(n + 2^b)$ | yes | $b=8$, $w=32$: 4 passes |

The JDK claim was checked in the OpenJDK source: `DualPivotQuicksort` in the jdk17u and jdk21u repositories has a `MAX_RECURSION_DEPTH` check that
switches to `heapSort`; the jdk11u version has no such fallback (verified 23 Oct 2026).

**Comparison lower bound:** $\lceil\log_2 n!\rceil$ comparisons in the worst case (and on average).

**Inversions:** $0 \le \text{inv}(a) \le \binom n2$; $\text{inv}$ = minimum adjacent swaps to sort = number of swaps bubble sort performs. Counting
"pairs $i<j$ with $a_i \ge a_j$" (non-strict) is the same algorithm with the merge tie-break flipped (take from the right on ties).

**Rearrangement inequality.** For sequences $x_1\le\cdots\le x_n$ and $y_1\le\cdots\le y_n$ and any permutation $\sigma$:

$$\sum_i x_i y_{n+1-i} \le \sum_i x_i y_{\sigma(i)} \le \sum_i x_i y_i .$$

Proof (exchange argument): if $x_i<x_j$ but $y_{\sigma(i)}>y_{\sigma(j)}$, swapping the two $y$'s changes the sum by
$(x_j-x_i)(y_{\sigma(i)}-y_{\sigma(j)}) \ge 0$; repeat until sorted. This justifies "pair the largest with the largest" greedies
(e.g. [CF 276C · Little Girl and Maximum Sum](https://codeforces.com/problemset/problem/276/C) — 1500).

**Median minimises absolute deviations:** $\sum_i |a_i - x|$ is minimised at any median of the $a_i$ (moving $x$ by $\delta$ toward the side with more
points decreases the sum). Sorting finds it ([CSES 1074 · Stick Lengths](https://cses.fi/problemset/task/1074)).

## 3. Implementation (C++ and Java)

### 3.1 Comparator patterns

```cpp
struct Item { int score; long long time; string name; };

void comparatorPatterns(vector<Item>& v, vector<pair<int, int>>& pr) {
    // (1) Lexicographic multi-key with tie(): score DESC, time ASC, name ASC. Negate or swap sides for DESC.
    sort(v.begin(), v.end(), [](const Item& a, const Item& b) {
        return tie(b.score, a.time, a.name) < tie(a.score, b.time, b.name);
    });
    // (2) pairs already compare lexicographically; greater<> reverses everything
    sort(pr.begin(), pr.end());
    sort(pr.begin(), pr.end(), greater<>());
    // (3) by a computed key: compute keys once, sort indices (avoids recomputing an expensive key O(n log n) times)
    vector<long long> key(v.size());
    for (size_t i = 0; i < v.size(); i++) key[i] = v[i].time * 3 + v[i].score;
    vector<int> idx(v.size());
    iota(idx.begin(), idx.end(), 0);
    stable_sort(idx.begin(), idx.end(), [&](int i, int j) { return key[i] < key[j]; });   // ties keep input order
}
```

```java
record Item(int score, long time, String name) {}

static void comparatorPatterns(List<Item> v, int[][] pr) {
    // (1) score DESC, time ASC, name ASC
    v.sort(Comparator.comparingInt((Item it) -> -it.score())       // negation is safe here: scores are not Integer.MIN_VALUE
            .thenComparingLong(Item::time)
            .thenComparing(Item::name));
    // (2) explicit lambda; never return a - b (overflow), use Integer.compare
    Arrays.sort(pr, (a, b) -> a[0] != b[0] ? Integer.compare(a[0], b[0]) : Integer.compare(a[1], b[1]));
    // (3) sort indices by a precomputed key; object sort is stable
    long[] key = new long[v.size()];
    for (int i = 0; i < key.length; i++) key[i] = v.get(i).time() * 3 + v.get(i).score();
    Integer[] idx = new Integer[key.length];
    for (int i = 0; i < idx.length; i++) idx[i] = i;
    Arrays.sort(idx, Comparator.comparingLong(i -> key[i]));
}
```

A Java trap with chained comparators: `Comparator.comparingInt(f).reversed().thenComparing(g)` reverses only the first key, but
`comparing(f).thenComparing(g).reversed()` reverses **both**. Write the direction into each key instead.

### 3.2 Safe primitive sorting in Java, counting sort, radix sort

```java
static void shuffleSort(int[] a) {                  // shuffle first: no adversarial input can target the pivot choice
    Random rnd = new Random();
    for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = a[i]; a[i] = a[j]; a[j] = t; }
    Arrays.sort(a);
}

static int[] countingSort(int[] a, int K) {         // values in [0, K); stable, O(n + K)
    int[] cnt = new int[K + 1];
    for (int x : a) cnt[x + 1]++;
    for (int v = 0; v < K; v++) cnt[v + 1] += cnt[v];   // cnt[v] = first output position of value v
    int[] out = new int[a.length];
    for (int x : a) out[cnt[x]++] = x;
    return out;
}

static void radixSort(int[] a) {                    // signed 32-bit ints, 4 passes of 8 bits
    int n = a.length;
    int[] buf = new int[n];
    for (int shift = 0; shift < 32; shift += 8) {
        int[] cnt = new int[257];
        for (int x : a) cnt[(((x ^ 0x80000000) >>> shift) & 255) + 1]++;   // flip the sign bit so negatives come first
        for (int b = 0; b < 256; b++) cnt[b + 1] += cnt[b];
        for (int x : a) buf[cnt[((x ^ 0x80000000) >>> shift) & 255]++] = x;
        System.arraycopy(buf, 0, a, 0, n);
    }
}
```

```cpp
vector<int> countingSort(const vector<int>& a, int K) {     // values in [0, K)
    vector<int> cnt(K + 1, 0), out(a.size());
    for (int x : a) cnt[x + 1]++;
    for (int v = 0; v < K; v++) cnt[v + 1] += cnt[v];
    for (int x : a) out[cnt[x]++] = x;
    return out;
}

void radixSort(vector<unsigned>& a) {                       // for signed ints: sort (x ^ 0x80000000u) then flip back
    vector<unsigned> buf(a.size());
    for (int shift = 0; shift < 32; shift += 8) {
        array<int, 257> cnt{};
        for (unsigned x : a) cnt[((x >> shift) & 255) + 1]++;
        for (int b = 0; b < 256; b++) cnt[b + 1] += cnt[b];
        for (unsigned x : a) buf[cnt[(x >> shift) & 255]++] = x;
        a.swap(buf);
    }
}
```

### 3.3 Merge sort with inversion counting

```cpp
// Sorts a[l, r) and returns the number of pairs i < j with a[i] > a[j].
long long mergeCount(vector<int>& a, vector<int>& tmp, int l, int r) {
    if (r - l <= 1) return 0;
    int m = (l + r) / 2;
    long long inv = mergeCount(a, tmp, l, m) + mergeCount(a, tmp, m, r);
    int i = l, j = m, k = l;
    while (i < m || j < r) {
        if (j == r || (i < m && a[i] <= a[j])) tmp[k++] = a[i++];   // "<=": equal values are not inversions
        else { inv += m - i; tmp[k++] = a[j++]; }                   // a[j] is smaller than all of a[i..m)
    }
    for (int t = l; t < r; t++) a[t] = tmp[t];
    return inv;
}
```

```java
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
```

A Fenwick tree over compressed values counts inversions in $O(n\log n)$ too and generalises to "pairs with $a_i > a_j + d$"
([Fenwick tree](../08-Data-Structures/01-fenwick-tree.md)).

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| answer does not depend on input order (pairs, matching, choosing a subset) | sort first, then scan / two pointers / binary search |
| "minimum adjacent swaps", "how unsorted" | inversions (merge sort or Fenwick) |
| "arrange strings/numbers so the concatenation is smallest/largest" | comparator `a+b < b+a` (Example 5) |
| a condition on pairs $i<j$ involving $a_i - b_i$ and $a_j - b_j$ | define $c_i = a_i - b_i$; the index order no longer matters for unordered pairs (Example 2) |
| "is it possible to sort with operation X?" | find what X preserves (parity of position, multiset of a class) and compare with the sorted array (Example 3) |
| values $\le 10^6$ and $n$ huge, or a tight TL | counting sort / radix sort |
| sort by one key, ties in input order | stable sort (or add the index as the last key) |
| scheduling / intervals | sort by end (activity selection) or by start (merging, sweep) — [greedy](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md) |

## 5. Worked examples (graded)

### Example 1 — Leaderboard  ·  ★ ≈1100 (est.)

- **Source:** Original problem.
- **Difficulty:** ≈1100 (est.)
- **Problem:** $n\le2\cdot10^5$ contestants, each with a unique lowercase name ($\le 10$ letters), solved count $s\le 20$ and penalty
  $p\le10^{12}$. Print the names ordered by solved count (more first), then penalty (less first), then name (alphabetical).
- **Thinking from first principles:** the requested order is lexicographic on the key $(-s,\ p,\ \text{name})$, which is a total order (names are
  unique), so any correct comparator gives the same output and stability is irrelevant. Penalties exceed 32 bits. In Java, sorting objects is
  $O(n\log n)$ TimSort — safe from anti-quicksort inputs.

<details><summary>Solution</summary>

C++: `tie` with the descending key negated. Java: a chained `Comparator`. $O(n\log n)$ comparisons, each $O(1)$ except name comparisons.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct Row { string name; int solved; long long penalty; };

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<Row> v(n);
    for (auto& r : v) cin >> r.name >> r.solved >> r.penalty;
    sort(v.begin(), v.end(), [](const Row& a, const Row& b) {
        if (a.solved != b.solved) return a.solved > b.solved;     // key 1: more solved first
        if (a.penalty != b.penalty) return a.penalty < b.penalty; // key 2: less penalty first
        return a.name < b.name;                                   // key 3: alphabetical
    });
    string out;
    for (auto& r : v) out += r.name + '\n';
    cout << out;
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    record Row(String name, int solved, long penalty) {}

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        Row[] v = new Row[n];
        for (int i = 0; i < n; i++) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            v[i] = new Row(st.nextToken(), Integer.parseInt(st.nextToken()), Long.parseLong(st.nextToken()));
        }
        Arrays.sort(v, Comparator.comparingInt((Row r) -> -r.solved())
                .thenComparingLong(Row::penalty)
                .thenComparing(Row::name));
        StringBuilder sb = new StringBuilder();
        for (Row r : v) sb.append(r.name()).append('\n');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
5
ann 3 100
bob 5 900
cid 3 50
dan 3 100
eve 5 900
out:
bob
eve
cid
ann
dan
-->
<!-- test
in:
2
zed 0 1000000000000
amy 0 999999999999
out:
amy
zed
-->

### Example 2 — Pair of Topics  ·  ★ 1400

- **Source:** [CF 1324D · Pair of Topics](https://codeforces.com/problemset/problem/1324/D) — 1400
- **Difficulty:** 1400
- **Problem:** $n\le2\cdot10^5$ topics with interest $a_i$ for the teacher and $b_i$ for students ($\le10^9$). Count pairs $i<j$ with
  $a_i + a_j > b_i + b_j$.
- **Thinking from first principles:** rearrange the inequality so each side depends on one index: $(a_i - b_i) + (a_j - b_j) > 0$. With
  $c_i = a_i - b_i$ the condition is symmetric in $i, j$, so "pairs $i<j$" is just "unordered pairs" — and the order of the array no longer
  matters. **Sort $c$**; for each $i$ count $j>i$ with $c_j > -c_i$ by binary search (or two pointers from both ends). Up to $2\cdot10^{10}$ pairs: 64-bit count.

<details><summary>Solution</summary>

After sorting, for each $i$ the valid partners $j>i$ form a suffix of $c[i+1..]$ starting at `upper_bound(-c[i])`. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> a(n), c(n);
    for (auto& x : a) cin >> x;
    for (int i = 0; i < n; i++) { long long b; cin >> b; c[i] = a[i] - b; }
    sort(c.begin(), c.end());
    long long pairs = 0;
    for (int i = 0; i < n; i++) {
        auto it = upper_bound(c.begin() + i + 1, c.end(), -c[i]);   // first c[j] > -c[i] with j > i
        pairs += c.end() - it;
    }
    cout << pairs << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] a = new long[n], c = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        for (int i = 0; i < n; i++) c[i] = a[i] - in.nextLong();
        Random rnd = new Random();
        for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = c[i]; c[i] = c[j]; c[j] = t; }
        Arrays.sort(c);
        long pairs = 0;
        for (int i = 0; i < n; i++) {
            int lo = i + 1, hi = n;                       // first index in [i+1, n) with c[idx] > -c[i]
            while (lo < hi) { int mid = (lo + hi) >>> 1; if (c[mid] > -c[i]) hi = mid; else lo = mid + 1; }
            pairs += n - lo;
        }
        System.out.println(pairs);
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
3 1 4 1
1 5 9 2
out:
1
-->
<!-- test
in:
5
10 10 10 10 10
1 1 1 1 1
out:
10
-->
<!-- test
in:
3
1 1 1
1 1 1
out:
0
-->
<!-- test
in:
2
5 1
1 1
out:
1
-->

### Example 3 — AquaMoon and Strange Sort  ·  ★ 1500

- **Source:** [CF 1545A · AquaMoon and Strange Sort](https://codeforces.com/problemset/problem/1545/A) — 1500
- **Difficulty:** 1500
- **Problem:** $n$ people with numbers $a_i\le10^5$ stand in a row, all facing right ($\sum n\le10^5$). An operation swaps two adjacent people
  and flips the direction of both. Can the row become non-decreasing with everybody facing right again?
- **Thinking from first principles:** look for an invariant. A person's direction flips once per swap they take part in, so facing right at the
  end means **an even number of swaps** for every person. Each swap moves a person by exactly one position, so an even number of swaps means
  the person ends at a position of the **same parity** as where they started. Equal values are interchangeable, so the condition becomes: for
  every value $v$, the number of copies of $v$ on even positions must be the same in $a$ and in $\text{sorted}(a)$ (then the odd counts match too).
  That this is also sufficient is the content of the official analysis; a brute-force BFS over small arrays (positions × directions) agrees with
  it on every array tried while preparing this kit.

<details><summary>Solution</summary>

Count `even[v]` over the original array and subtract over the sorted array (counting sort, values $\le10^5$); answer YES iff everything is zero.
Reset only the touched entries between tests. $O(n + \max a)$ per test without the reset trick, $O(n\log n)$ with `sort`.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    vector<int> diff(100001, 0);
    while (t--) {
        int n;
        cin >> n;
        vector<int> a(n);
        for (auto& x : a) cin >> x;
        vector<int> s = a;
        sort(s.begin(), s.end());
        for (int i = 0; i < n; i += 2) { diff[a[i]]++; diff[s[i]]--; }   // even positions (0-indexed)
        bool ok = true;
        for (int x : a) { if (diff[x] != 0) ok = false; }
        for (int x : a) diff[x] = 0;                                     // reset only what we touched
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
        int[] diff = new int[100001];
        while (t-- > 0) {
            int n = in.nextInt();
            int[] a = new int[n];
            for (int i = 0; i < n; i++) a[i] = in.nextInt();
            int[] s = a.clone();
            Random rnd = new Random();
            for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int tmp = s[i]; s[i] = s[j]; s[j] = tmp; }
            Arrays.sort(s);
            for (int i = 0; i < n; i += 2) { diff[a[i]]++; diff[s[i]]--; }
            boolean ok = true;
            for (int x : a) if (diff[x] != 0) ok = false;
            for (int x : a) diff[x] = 0;
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
7
1
5
2
2 1
3
3 2 1
4
1 1 2 2
4
2 2 1 1
3
3 1 2
5
2 3 1 1 2
out:
YES
NO
YES
YES
YES
NO
NO
-->

### Example 4 — Maximum Crossings (Hard Version)  ·  ★ 1500

- **Source:** [CF 1676H2 · Maximum Crossings (Hard Version)](https://codeforces.com/problemset/problem/1676/H2) — 1500
- **Difficulty:** 1500
- **Problem:** Wire $i$ goes from top terminal $i$ to bottom terminal $a_i$ ($1\le a_i\le n$, $\sum n\le2\cdot10^5$). Wires $i<j$ can be drawn
  crossing iff $a_i \ge a_j$ (equal bottom terminals can always be made to cross). Output the maximum number of crossings.
- **Thinking from first principles:** the answer is the number of pairs $i<j$ with $a_i\ge a_j$ — inversions with a non-strict comparison. The
  $O(n^2)$ count is $2\cdot10^{10}$; merge sort counts them in $O(n\log n)$. The only change from §3.3 is the tie rule: on equal values take the
  **right** element first, so the left equal elements still waiting are counted.

<details><summary>Solution</summary>

Merge sort; when `a[j] <= a[i]` take `a[j]` and add `m - i`. 64-bit answer. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

long long mergeCountGE(vector<int>& a, vector<int>& tmp, int l, int r) {   // pairs i<j with a[i] >= a[j]
    if (r - l <= 1) return 0;
    int m = (l + r) / 2;
    long long inv = mergeCountGE(a, tmp, l, m) + mergeCountGE(a, tmp, m, r);
    int i = l, j = m, k = l;
    while (i < m || j < r) {
        if (j == r || (i < m && a[i] < a[j])) tmp[k++] = a[i++];   // strict: ties go to the right element first
        else { inv += m - i; tmp[k++] = a[j++]; }
    }
    for (int q = l; q < r; q++) a[q] = tmp[q];
    return inv;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        int n;
        cin >> n;
        vector<int> a(n), tmp(n);
        for (auto& x : a) cin >> x;
        cout << mergeCountGE(a, tmp, 0, n) << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static long mergeCountGE(int[] a, int[] tmp, int l, int r) {
        if (r - l <= 1) return 0;
        int m = (l + r) >>> 1;
        long inv = mergeCountGE(a, tmp, l, m) + mergeCountGE(a, tmp, m, r);
        int i = l, j = m, k = l;
        while (i < m || j < r) {
            if (j == r || (i < m && a[i] < a[j])) tmp[k++] = a[i++];
            else { inv += m - i; tmp[k++] = a[j++]; }
        }
        System.arraycopy(tmp, l, a, l, r - l);
        return inv;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt();
            int[] a = new int[n];
            for (int i = 0; i < n; i++) a[i] = in.nextInt();
            out.println(mergeCountGE(a, new int[n], 0, n));
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
2
1 1
3
3 2 1
1
1
5
2 2 1 3 1
out:
1
3
0
7
-->

### Example 5 — The Smallest String Concatenation  ·  ★ 1700

- **Source:** [CF 632C · The Smallest String Concatenation](https://codeforces.com/problemset/problem/632/C) — 1700
- **Difficulty:** 1700
- **Problem:** Given $n\le5\cdot10^4$ lowercase strings (each $\le 50$ letters), concatenate all of them in some order to get the
  lexicographically smallest result.
- **Thinking from first principles:** plain lexicographic sorting fails: `b` < `ba`, so it would output `bba`, but `bab` is smaller —
  `ba` must come first even though `b` < `ba`. Exchange argument: in
  an optimal order, swapping two *adjacent* strings $x, y$ only changes the middle part $xy \to yx$, so optimality requires $xy \le yx$ for every
  adjacent pair. Define `comp(x, y)` $\iff xy < yx$. Is it a strict weak ordering? Map a string $s$ (letters as digits 1..26, base $B=27$, value
  $S$, length $|s|$) to the real number $f(s) = S/(B^{|s|}-1)$. Equal-length strings compare lexicographically like their values, so
  $xy < yx \iff X B^{|y|} + Y < Y B^{|x|} + X \iff X(B^{|y|}-1) < Y(B^{|x|}-1) \iff f(x) < f(y)$. Comparing real keys is a strict weak ordering. ✓
  Finally, any order can be turned into the sorted one by adjacent swaps that never make the string larger, so the sorted order is optimal.

<details><summary>Solution</summary>

Sort with `a + b < b + a`, then concatenate. Each comparison costs $O(L)$ with $L\le100$: $O(nL\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<string> s(n);
    for (auto& x : s) cin >> x;
    sort(s.begin(), s.end(), [](const string& a, const string& b) { return a + b < b + a; });
    string res;
    for (auto& x : s) res += x;
    cout << res << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        String[] s = new String[n];
        for (int i = 0; i < n; i++) s[i] = br.readLine().trim();
        Arrays.sort(s, (a, b) -> (a + b).compareTo(b + a));
        StringBuilder sb = new StringBuilder();
        for (String x : s) sb.append(x);
        System.out.println(sb);
    }
}
```

</details>

<!-- test
in:
3
b
ba
bab
out:
bababb
-->
<!-- test
in:
4
ab
aba
abab
b
out:
abaabababb
-->
<!-- test
in:
3
c
cb
cba
out:
cbacbc
-->
<!-- test
in:
1
xyz
out:
xyz
-->

## 6. Tricks, pitfalls and things to remember

1. **Java `Arrays.sort(int[])` and anti-quicksort tests.** Dual-pivot quicksort has inputs that drive it toward quadratic time. On Java 11
   (still listed on Codeforces) there is no fallback; on 17/21 a heapsort fallback bounds the worst case at $O(n\log n)$, with a worse constant.
   **Shuffle before sorting primitives**, or sort `Integer[]`/`Long[]` (TimSort, guaranteed $O(n\log n)$ but 3–5× slower because of boxing).
   Sorting a `long[]` instead of an `int[]` does *not* help — it is the same algorithm.
2. **Never use `<=` (or `>=`) in a comparator.** It breaks irreflexivity: undefined behaviour in C++, contract violation in Java.
3. **Subtraction comparators overflow:** `(a, b) -> a - b` is wrong when $|a-b|$ can exceed $2^{31}-1$. Use `Integer.compare`/`Long.compare`.
4. **Floating-point keys**: sort by an exact integer key (cross-multiplication for fractions, see
   [precision](06-integer-overflow-precision-and-fast-io.md)) or compare with care; NaN breaks every sort.
5. **Expensive keys inside the comparator** run $O(n\log n)$ times. Precompute keys and sort indices (§3.1).
6. **Sorting indices by value with ties**: if the problem wants "smaller index first" on ties, add the index as the last key or use a stable sort.
7. **Sorting a 2D Java array `int[][]`** sorts row references with TimSort — fine, but each comparison dereferences; for millions of pairs pack
   into `long` keys ([STL & Collections §3.4](02-cpp-stl-and-java-collections.md)) and sort a `long[]` (after shuffling).
8. **Inversion counts overflow `int`** ($\binom{2\cdot10^5}{2}\approx2\cdot10^{10}$).
9. **`std::sort` on a `std::list`** does not compile (needs random access); use `list::sort`.
10. **The comparator must not depend on mutable external state** that changes during sorting (e.g. a global "current time").
11. **`reversed()` in Java comparator chains** applies to the whole chain built so far (§3.1).
12. **Strings: `compareTo` is lexicographic by UTF-16 code unit**, which for lowercase ASCII is the expected order; for numbers stored as strings,
    compare by length first, then lexicographically.

## 7. Going further (toward 2400–2600+)

- **Sorting as a proof technique**: exchange arguments for greedy orderings (e.g. the "$a_i/b_i$" scheduling rule, sort by $a+b$ / $\max$ keys) —
  [greedy & exchange arguments](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md).
- **Sorting by angle** (polar sort with cross products, no `atan2`) — [vectors & precision](../14-Geometry/01-vectors-dot-cross-and-precision.md).
- **Suffix sorting** in $O(n\log n)$ with radix passes — [suffix array](../11-Strings/07-suffix-array-and-lcp.md).
- **Offline queries sorted by a key**, Mo's order, sweep lines — [sweep line](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md),
  [Mo's algorithm](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md).
- **Counting inversions under constraints** (pairs with $a_i > 2a_j$, 2D dominance) — CDQ divide and conquer,
  [offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md).

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 977C · Less or Equal](https://codeforces.com/problemset/problem/977/C) — 1200
- [ ] [CF 492B · Vanya and Lanterns](https://codeforces.com/problemset/problem/492/B) — 1200
- [ ] [CF 489B · BerSU Ball](https://codeforces.com/problemset/problem/489/B) — 1200
- [ ] [CF 451B · Sort the Array](https://codeforces.com/problemset/problem/451/B) — 1300
- [ ] [CSES 1074 · Stick Lengths](https://cses.fi/problemset/task/1074)
- [ ] [CSES 1629 · Movie Festival](https://cses.fi/problemset/task/1629)
- [ ] [CSES 1619 · Restaurant Customers](https://cses.fi/problemset/task/1619)
- [ ] [CF 1324D · Pair of Topics](https://codeforces.com/problemset/problem/1324/D) — 1400

**1400–1700**
- [ ] [CF 276C · Little Girl and Maximum Sum](https://codeforces.com/problemset/problem/276/C) — 1500
- [ ] [CF 580B · Kefa and Company](https://codeforces.com/problemset/problem/580/B) — 1500
- [ ] [CF 1545A · AquaMoon and Strange Sort](https://codeforces.com/problemset/problem/1545/A) — 1500
- [ ] [CF 1676H2 · Maximum Crossings (Hard Version)](https://codeforces.com/problemset/problem/1676/H2) — 1500
- [ ] [CF 1253C · Sweets Eating](https://codeforces.com/problemset/problem/1253/C) — 1500
- [ ] [CF 1203E · Boxers](https://codeforces.com/problemset/problem/1203/E) — 1500
- [ ] [CF 372A · Counting Kangaroos is Fun](https://codeforces.com/problemset/problem/372/A) — 1600
- [ ] [CF 1475E · Advertising Agency](https://codeforces.com/problemset/problem/1475/E) — 1600
- [ ] [CSES 1630 · Tasks and Deadlines](https://cses.fi/problemset/task/1630)
- [ ] [CSES 2168 · Nested Ranges Check](https://cses.fi/problemset/task/2168)

**1700–1900+**
- [ ] [CF 632C · The Smallest String Concatenation](https://codeforces.com/problemset/problem/632/C) — 1700
- [ ] [CSES 2169 · Nested Ranges Count](https://cses.fi/problemset/task/2169)
- [ ] [CF 1430E · String Reversal](https://codeforces.com/problemset/problem/1430/E) — 1900

## 9. LeetCode / FAANG cross-reference

Interviewers rarely ask you to implement a sort, but they often ask for merge sort/quickselect internals and for custom comparators.

- [LC 912 · Sort an Array](https://leetcode.com/problems/sort-an-array/) — Medium — implement merge sort or heapsort; discuss stability.
- [LC 75 · Sort Colors](https://leetcode.com/problems/sort-colors/) — Medium — counting sort / Dutch national flag partition.
- [LC 179 · Largest Number](https://leetcode.com/problems/largest-number/) — Medium — exactly Example 5's comparator (reversed).
- [LC 56 · Merge Intervals](https://leetcode.com/problems/merge-intervals/) — Medium — sort by start.
- [LC 215 · Kth Largest Element in an Array](https://leetcode.com/problems/kth-largest-element-in-an-array/) — Medium — quickselect / heap.
- [LC 164 · Maximum Gap](https://leetcode.com/problems/maximum-gap/) — Medium — linear time via bucket/radix sort.
- [LC 274 · H-Index](https://leetcode.com/problems/h-index/) — Medium — sort or counting sort.
- [LC 148 · Sort List](https://leetcode.com/problems/sort-list/) — Medium — merge sort on a linked list.
- [LC 315 · Count of Smaller Numbers After Self](https://leetcode.com/problems/count-of-smaller-numbers-after-self/) — Hard — merge sort with indices / Fenwick.
- [LC 493 · Reverse Pairs](https://leetcode.com/problems/reverse-pairs/) — Hard — merge-sort counting with a different condition.

## 10. Self-check

1. Prove that any comparison sort needs $\Omega(n\log n)$ comparisons in the worst case.
2. List the four properties of a strict weak ordering. Which one does `<=` violate?
3. Why is LSD radix sort correct, and why must each pass be stable?
4. How do you count pairs $i<j$ with $a_i > a_j$ in $O(n\log n)$? What changes for $a_i \ge a_j$?
5. Give a two-string example where sorting by plain lexicographic order gives a non-optimal concatenation.
6. Why does shuffling an `int[]` before `Arrays.sort` defend against anti-quicksort tests, but switching to `long[]` does not?
7. You sort `(value, index)` pairs and get a different order from the expected output on ties. What are two fixes?

<details><summary>Answers</summary>

1. Decision tree with at least $n!$ leaves has height $\ge\log_2 n! \ge \frac n2\log_2\frac n2$.
2. Irreflexivity, asymmetry, transitivity, transitivity of incomparability; `<=` violates irreflexivity (and asymmetry for equal elements).
3. Induction: after the pass on digit $d$, the array is sorted by the last $d$ digits; stability keeps the order established by earlier (lower) digits among elements with equal digit $d$.
4. Merge sort; when taking from the right half add the number of remaining left elements. For $\ge$, take from the right on ties (compare with strict `<` when deciding to take from the left).
5. `b` and `ba`: sorted gives `bba`, optimal is `bab`.
6. The adversarial input is built against a deterministic pivot choice on a specific order; shuffling destroys that order. `long[]` uses the same deterministic algorithm.
7. Make the index part of the key in the desired direction, or use a stable sort keyed only on the value.

</details>
