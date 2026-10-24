# Ordered Sets, PBDS, Heaps and Hashing

> **Band:** 🟢–🔵 1200–1900 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [C++ STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md), [sorting and comparators](../01-Foundations/05-sorting-and-comparators.md), [Fenwick tree](01-fenwick-tree.md)
> **You can say you know this when:** you use `multiset`/`TreeMap` neighbour queries without off-by-ones, get order statistics from PBDS in C++ and from a BIT (or treap) in Java, write max- and min-heaps with correct comparators in both languages, maintain a running median with two heaps (including deletions via lazy deletion), defend hash maps against anti-hash tests, and implement an $O(1)$ LRU cache.

## 1. First principles — why this works

### 1.1 Balanced BST containers

`std::set`/`multiset`/`map` and Java's `TreeSet`/`TreeMap` are red–black trees: height $\le 2\log_2(n+1)$, so insert, erase, find and **ordered neighbour queries** cost $O(\log n)$.
The neighbour queries are the reason to use them instead of hash tables:

| Want | C++ (`s` is a `set`/`multiset`) | Java `TreeSet` / `TreeMap` |
|---|---|---|
| smallest $\ge x$ | `s.lower_bound(x)` | `ceiling(x)` / `ceilingKey(x)` |
| smallest $> x$ | `s.upper_bound(x)` | `higher(x)` / `higherKey(x)` |
| largest $\le x$ | `prev(s.upper_bound(x))` if not `begin()` | `floor(x)` / `floorKey(x)` |
| largest $< x$ | `prev(s.lower_bound(x))` if not `begin()` | `lower(x)` / `lowerKey(x)` |
| min / max | `*s.begin()`, `*s.rbegin()` | `first()`, `last()` / `firstKey()`, `lastKey()` |

Java returns `null` when no such element exists — unboxing that `null` into an `int` throws. C++ returns `end()`/requires a `begin()` check before `prev`.

**Multiset pitfalls.** `ms.erase(x)` erases **all** copies of $x$; erase one with `ms.erase(ms.find(x))` (check `find != end` first). Java has no multiset: use `TreeMap<K, Integer>` of counts
(decrement, remove the key at 0), or make elements unique by pairing them with an index (`value * N + index` in a `long`, or a record with a tie-breaking comparator).

**Never call the free function `std::lower_bound` on a `set`** — set iterators are bidirectional, so it is $O(n)$ per call. Use the member `s.lower_bound`.

**Neighbours after insertion.** `auto it = s.insert(x).first;` then `prev(it)` and `next(it)` are the closest elements — the standard way to maintain "minimum gap" or "nearest
occupied position" online. Interval sets (disjoint segments keyed by left end, merged on insertion) are the same idea with `map<int,int>`.

### 1.2 Order statistics: PBDS in C++, workarounds in Java

The red–black trees above do not store subtree sizes, so "k-th element" and "how many elements are $< x$" are not available. GCC's policy-based data structures add them:

```text
tree<Key, null_type, less<Key>, rb_tree_tag, tree_order_statistics_node_update>
  find_by_order(k)   -> iterator to the k-th smallest (0-based), end() if k >= size
  order_of_key(x)    -> number of keys strictly less than x
```

Both $O(\log n)$. It is a *set* (unique keys). For a multiset store `pair<value, unique id>`: `order_of_key({x, -inf})` counts values $< x$; erase one copy by locating
`find_by_order(order_of_key({x, -inf}))`. (Using `less_equal` as the comparator "works" for insertion but breaks `find`, `erase` and `lower_bound` — avoid it.)

**Java has no equivalent.** Options, in order of preference:

1. **BIT over compressed values** when all values are known in advance (read the whole input first): count per value, k-th by descent, rank by prefix sum — [Fenwick tree](01-fenwick-tree.md).
2. **BIT over positions** for "remove the k-th remaining element" (Josephus, list removals).
3. **Segment tree** descent for richer queries ([advanced segment trees](04-segment-tree-advanced-descent-merging-beats.md)).
4. **Treap with sizes** when values are online and unbounded ([treaps](09-treaps-and-implicit-treaps.md)).

### 1.3 Binary heaps

A heap is a complete binary tree in an array where each parent beats its children. `push` sifts up, `pop` sifts down: $O(\log n)$; `top` $O(1)$; building from $n$ elements by sifting down
from the last internal node is $O(n)$, because at most $\lceil n/2^{h+1}\rceil$ nodes have height $h$, so $\sum_{h} (\text{nodes at height } h)\cdot h \le \sum_{h \le \log_2 n} \big(\frac{n}{2^{h+1}} + 1\big) h = n + O(\log^2 n) = O(n)$.

| | C++ `priority_queue` | Java `PriorityQueue` |
|---|---|---|
| default | **max**-heap (`less<T>`) | **min**-heap (natural order) |
| other direction | `priority_queue<T, vector<T>, greater<T>>` | `new PriorityQueue<>(Comparator.reverseOrder())` |
| custom | comparator returns true if `a` has *lower* priority than `b` | `Comparator` with `Integer.compare` / `Long.compare` |
| delete arbitrary | not supported | `remove(Object)` is $O(n)$ |

Comparator rules: C++ comparators must be strict weak orderings (`<`, never `<=`); in Java never write `(a, b) -> b - a` (overflow for large values) — use `Integer.compare(b, a)`.

**Two heaps for a running median.** Keep a max-heap `lo` with the smaller half and a min-heap `hi` with the larger half, with $|lo| = |hi|$ or $|lo| = |hi| + 1$. Every element of `lo` is $\le$ every element of `hi`,
so the (lower) median is `lo.top()`. Insertion: push into `lo` if $x \le$ `lo.top()`, else into `hi`; then move one element across if the size invariant broke. $O(\log n)$ per insertion.

**Lazy deletion.** Heaps cannot delete arbitrary elements, but we can *pretend*: record the element as deleted (a counter map, or a flag by id), keep logical sizes, and whenever a deleted element reaches
the top, pop and discard it. Each element is physically popped at most once, so the amortised cost stays $O(\log n)$. This is how Dijkstra handles "decrease-key" in practice (push the new distance, skip stale
entries when popped), and how sliding-window medians work with heaps.

**Indexed heap / decrease-key.** If you need true decrease-key (e.g. Prim/Dijkstra on dense graphs), store `pos[key]` = index in the heap array and sift from there. In contests the alternatives are
(a) lazy duplicates as above, (b) `std::set<pair<dist, v>>` with erase+insert — also $O(\log n)$, no stale entries, larger constant.

### 1.4 Hash tables and anti-hash tests

`unordered_map<long long, …>` hashes an integer to itself, and the bucket is `key mod p` for a prime $p$ from a fixed list. A test full of multiples of that prime puts all keys in one bucket:
every operation becomes $O(n)$, the whole program $O(n^2)$ — a standard Codeforces hack. The fix is a hash the adversary cannot predict: **splitmix64 of (key + random seed)**, seeded from the clock at runtime.

Java's `HashMap` spreads `hashCode` with `h ^ (h >>> 16)` and turns long chains into red–black trees (for `Comparable` keys), so the worst case is $O(\log n)$ per operation rather than $O(n)$ — but with a big
constant, and anti-Java-hash tests for `HashMap<Long, …>` exist. Defences: map each key through a random bijection before inserting (splitmix64 is a bijection on 64-bit values, so equality is preserved), or
avoid hashing entirely by **sorting and compressing**. Note that xoring keys with a constant salt does *not* help in Java: colliding keys stay colliding, because the hash is linear in xor.

### 1.5 LRU cache

"Get/put with capacity $c$, evict the least recently used key" in $O(1)$: a **hash map** from key to a node of a **doubly linked list** ordered by recency. `get` moves the node to the front;
`put` inserts at the front (or updates and moves) and evicts from the back when over capacity. In C++: `list<pair<K,V>>` + `unordered_map<K, list::iterator>` (`splice` moves a node in $O(1)$
without invalidating iterators). In Java: `LinkedHashMap(cap, 0.75f, true)` with `removeEldestEntry`, or the explicit list for interviews. See [design problems](../17-FAANG-Interview-DSA/17-design-problems.md).

## 2. Formulas, definitions and identities

| Operation | Cost |
|---|---|
| `set`/`map`/`TreeMap` insert, erase, find, lower/upper bound | $O(\log n)$, height $\le 2\log_2(n+1)$ |
| `multiset::count(x)` | $O(\log n + \text{count})$ — avoid in loops on heavy duplicates |
| PBDS `find_by_order`, `order_of_key` | $O(\log n)$ |
| heap push / pop | $O(\log n)$; top $O(1)$; heapify $O(n)$ |
| two-heap median insert | $O(\log n)$; median $O(1)$ |
| lazy-deletion heap | amortised $O(\log n)$ per operation (each element popped once) |
| `unordered_map` with splitmix64 | expected $O(1)$; `reserve(n)` avoids rehashing |
| LRU get / put | $O(1)$ expected |

Heapify bound: $\sum_{h=0}^{\lfloor\log_2 n\rfloor} \lceil n/2^{h+1}\rceil\, h \le n\sum_{h \ge 0} \frac{h}{2^{h+1}} + \sum_{h \le \log_2 n} h = n + O(\log^2 n) = O(n)$ (the ceilings are why it is not simply $\le n$).
Lower median of $k$ elements: the $\lceil k/2\rceil$-th smallest, i.e. index $(k-1)/2$ (0-based) — what `lo.top()` holds when $|lo| = \lceil k/2 \rceil$.

## 3. Implementation (C++ and Java)

### 3.1 C++: multiset idioms and PBDS order statistics

```cpp
#include <ext/pb_ds/assoc_container.hpp>
#include <ext/pb_ds/tree_policy.hpp>
using namespace __gnu_pbds;
template <class T> using ordered_set = tree<T, null_type, less<T>, rb_tree_tag, tree_order_statistics_node_update>;

bool eraseOne(multiset<long long>& ms, long long x) {          // erase(x) would remove every copy
    auto it = ms.find(x);
    if (it == ms.end()) return false;
    ms.erase(it); return true;
}
optional<long long> largestAtMost(const multiset<long long>& ms, long long x) {
    auto it = ms.upper_bound(x);
    if (it == ms.begin()) return nullopt;
    return *prev(it);
}
// multiset with order statistics: (value, unique id) pairs
struct OrderedMultiset {
    ordered_set<pair<long long, int>> s; int uid = 0;
    void insert(long long x) { s.insert({x, uid++}); }
    bool eraseOne(long long x) {
        auto it = s.lower_bound({x, INT_MIN});
        if (it == s.end() || it->first != x) return false;
        s.erase(it); return true;
    }
    int countLess(long long x) const { return s.order_of_key({x, INT_MIN}); }
    long long kth(int k) const { return s.find_by_order(k)->first; }   // 0-based, k < size
};
```

```java
// Multiset on a TreeMap of counts; floor/ceiling return null when absent.
static void add(TreeMap<Long, Integer> ms, long x) { ms.merge(x, 1, Integer::sum); }
static boolean eraseOne(TreeMap<Long, Integer> ms, long x) {
    Integer c = ms.get(x);
    if (c == null) return false;
    if (c == 1) ms.remove(x); else ms.put(x, c - 1);
    return true;
}
static Long largestAtMost(TreeMap<Long, Integer> ms, long x) { return ms.floorKey(x); }   // null if none
// Duplicates in a TreeSet: encode (value, index) into one long when value < 2^31 and index < 2^31
static long encode(long value, int index) { return (value << 31) | index; }
```

### 3.2 Hashing that survives anti-hash tests

```cpp
struct SplitMix {                                              // use as unordered_map<long long, int, SplitMix>
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
// unordered_map<long long, int, SplitMix> cnt; cnt.reserve(1 << 20);
```

```java
// Store mix(key) instead of key: a random bijection on longs, so equal keys stay equal and adversarial keys scatter.
static final long SEED = System.nanoTime();
static long mix(long x) {
    x += 0x9e3779b97f4a7c15L + SEED;
    x = (x ^ (x >>> 30)) * 0xbf58476d1ce4e5b9L;
    x = (x ^ (x >>> 27)) * 0x94d049bb133111ebL;
    return x ^ (x >>> 31);
}
// HashMap<Long, Integer> cnt = new HashMap<>(); cnt.merge(mix(key), 1, Integer::sum);
```

### 3.3 Running median with two heaps

Original task: $n$ integers arrive one at a time; after each, print the lower median of everything seen so far.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    priority_queue<long long> lo;                              // max-heap: smaller half
    priority_queue<long long, vector<long long>, greater<long long>> hi;   // min-heap: larger half
    for (int i = 0; i < n; i++) {
        long long x; cin >> x;
        if (lo.empty() || x <= lo.top()) lo.push(x); else hi.push(x);
        if (lo.size() > hi.size() + 1) { hi.push(lo.top()); lo.pop(); }   // keep |lo| in {|hi|, |hi| + 1}
        else if (lo.size() < hi.size()) { lo.push(hi.top()); hi.pop(); }
        cout << lo.top() << (i + 1 < n ? ' ' : '\n');
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedInputStream(System.in));
        st.nextToken(); int n = (int) st.nval;
        PriorityQueue<Long> lo = new PriorityQueue<>(Comparator.reverseOrder());   // max-heap
        PriorityQueue<Long> hi = new PriorityQueue<>();                             // min-heap
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) {
            st.nextToken(); long x = (long) st.nval;
            if (lo.isEmpty() || x <= lo.peek()) lo.add(x); else hi.add(x);
            if (lo.size() > hi.size() + 1) hi.add(lo.poll());
            else if (lo.size() < hi.size()) lo.add(hi.poll());
            sb.append(lo.peek()).append(i + 1 < n ? ' ' : '\n');
        }
        System.out.print(sb);
    }
}
```

`StreamTokenizer` parses numbers as `double`; it is exact for integers up to $2^{53}$ and fine here ($|x| \le 10^9$), but do not use it for 64-bit values near $10^{18}$.

<!-- test
in:
6
5 15 1 3 8 7
out:
5 5 5 3 5 5
-->
<!-- test
in:
3
-1000000000 -1000000000 1000000000
out:
-1000000000 -1000000000 -1000000000
-->

## 4. Recognising the pattern

- **"Smallest element $\ge x$ that is still available", "nearest occupied seat", assignments with removal** → `multiset`/`TreeMap` with lower/upper bound and erase-one.
- **"k-th smallest", "rank of $x$" in a changing set** → PBDS (C++), BIT over compressed values or a treap (Java).
- **Repeatedly take the best remaining item; new items arrive** (scheduling, merging $k$ lists, greedy with regret) → heap. See [greedy with heaps](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md).
- **Median / percentile of a stream or window** → two heaps (insert-only) or two multisets / lazy-deletion heaps (with removals).
- **Counting pairs/subarrays by equality of a key** (prefix sums, hashes) → hash map with a safe hash, or sort + two pointers.
- **"Least recently used", "most frequent with recency ties"** → hash map + linked list (LRU), hash map + buckets of lists (LFU).
- Confused with: monotonic deque (sliding max/min is $O(n)$ with a deque — [monotonic stack and deque](../02-Core-Techniques/04-monotonic-stack-and-deque.md)); a heap is overkill there.

## 5. Worked examples (graded)

### Example 1 — Concert Tickets (multiset neighbour query)  ·  ★ ≈1200

- **Source:** [CSES 1091 · Concert Tickets](https://cses.fi/problemset/task/1091)
- **Difficulty:** ≈1200 (est.)
- **Problem:** $n, m \le 2\cdot10^5$ ticket prices; customers arrive in order, each with a maximum price $t$, and buys the most expensive remaining ticket with price $\le t$. Print each customer's price or $-1$.
- **Thinking from first principles:** "largest $\le t$ among remaining" with removals: sorting once does not survive removals, a scan is $O(nm)$. A multiset gives `prev(upper_bound(t))` and erase-one in $O(\log n)$.

<details><summary>Solution</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    multiset<int> tickets;
    for (int i = 0; i < n; i++) { int h; cin >> h; tickets.insert(h); }
    for (int j = 0; j < m; j++) {
        int t; cin >> t;
        auto it = tickets.upper_bound(t);
        if (it == tickets.begin()) cout << -1 << '\n';
        else { --it; cout << *it << '\n'; tickets.erase(it); }   // erase by iterator: one copy only
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), m = in.nextInt();
        TreeMap<Integer, Integer> tickets = new TreeMap<>();
        for (int i = 0; i < n; i++) tickets.merge(in.nextInt(), 1, Integer::sum);
        for (int j = 0; j < m; j++) {
            Integer p = tickets.floorKey(in.nextInt());
            if (p == null) { out.println(-1); continue; }
            out.println(p);
            int c = tickets.get(p);
            if (c == 1) tickets.remove(p); else tickets.put(p, c - 1);
        }
        out.flush();
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        int nextInt() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            int r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
    }
}
```

<!-- test
in:
5 3
5 3 7 8 5
4 8 3
out:
3
8
-1
-->
<!-- test
in:
2 3
1000000000 1000000000
1000000000 999999999 1000000000
out:
1000000000
-1
1000000000
-->

</details>

### Example 2 — Subarray Sums II (prefix sums + hack-proof hashing)  ·  ★ ≈1400

- **Source:** [CSES 1661 · Subarray Sums II](https://cses.fi/problemset/task/1661)
- **Difficulty:** ≈1400 (est.)
- **Problem:** $n \le 2\cdot10^5$ values in $[-10^9, 10^9]$ and a target $x$; count subarrays with sum exactly $x$.
- **Thinking from first principles:** with negative values two pointers fail (sums are not monotone). Subarray $(i, j]$ has sum $P_j - P_i$; for each $j$ count earlier prefixes equal to $P_j - x$ — a frequency map.
  Prefix sums are adversary-controlled 64-bit keys, the classic anti-hash target, so use splitmix64 (or an ordered map at $O(\log n)$).

<details><summary>Solution</summary>

$O(n)$ expected. The answer can reach $\binom{n+1}{2} \approx 2\cdot10^{10}$ → 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct SplitMix {
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

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long x; cin >> n >> x;
    unordered_map<long long, int, SplitMix> cnt;
    cnt.reserve(2 * n + 2);
    cnt[0] = 1;
    long long pre = 0, ans = 0;
    for (int i = 0; i < n; i++) {
        long long a; cin >> a; pre += a;
        auto it = cnt.find(pre - x);
        if (it != cnt.end()) ans += it->second;
        cnt[pre]++;
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long SEED = System.nanoTime();
    static long mix(long x) {
        x += 0x9e3779b97f4a7c15L + SEED;
        x = (x ^ (x >>> 30)) * 0xbf58476d1ce4e5b9L;
        x = (x ^ (x >>> 27)) * 0x94d049bb133111ebL;
        return x ^ (x >>> 31);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(); long x = in.nextLong();
        HashMap<Long, Integer> cnt = new HashMap<>(4 * n + 4);
        cnt.put(mix(0), 1);
        long pre = 0, ans = 0;
        for (int i = 0; i < n; i++) {
            pre += in.nextLong();
            Integer c = cnt.get(mix(pre - x));
            if (c != null) ans += c;
            cnt.merge(mix(pre), 1, Integer::sum);
        }
        System.out.println(ans);
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
5 7
2 -1 3 5 -2
out:
2
-->
<!-- test
in:
4 0
0 0 0 0
out:
10
-->
<!-- test
in:
1 -1000000000
-1000000000
out:
1
-->

</details>

### Example 3 — Josephus Problem II (order statistics: PBDS vs BIT)  ·  ★ ≈1700

- **Source:** [CSES 2163 · Josephus Problem II](https://cses.fi/problemset/task/2163)
- **Difficulty:** ≈1700 (est.)
- **Problem:** $n \le 2\cdot10^5$ children in a circle; repeatedly skip $k$ children ($0 \le k \le 10^9$) and remove the next one. Print the removal order.
- **Thinking from first principles:** in the list of remaining children, if the current index is $p$ (0-based), the removed child is at index $p' = (p + k) \bmod \text{size}$, and the next count starts at $p'$
  (the child after the removed one slides into that index). So we need "remove the element with index $p'$" in a shrinking list — order statistics. C++: PBDS `find_by_order`. Java: BIT of alive flags + descent.

<details><summary>Solution</summary>

$O(n \log n)$ in both.

```cpp
#include <bits/stdc++.h>
#include <ext/pb_ds/assoc_container.hpp>
#include <ext/pb_ds/tree_policy.hpp>
using namespace std;
using namespace __gnu_pbds;
template <class T> using ordered_set = tree<T, null_type, less<T>, rb_tree_tag, tree_order_statistics_node_update>;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long k; cin >> n >> k;
    ordered_set<int> s;
    for (int i = 1; i <= n; i++) s.insert(i);
    long long p = 0;
    for (int sz = n; sz >= 1; sz--) {
        p = (p + k) % sz;
        auto it = s.find_by_order(p);
        cout << *it << (sz > 1 ? ' ' : '\n');
        s.erase(it);
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int n = Integer.parseInt(st.nextToken()); long k = Long.parseLong(st.nextToken());
        int[] t = new int[n + 1];
        for (int i = 1; i <= n; i++) t[i] = i & -i;              // BIT of all ones
        int log = 1; while ((log << 1) <= n) log <<= 1;
        StringBuilder sb = new StringBuilder();
        long p = 0;
        for (int sz = n; sz >= 1; sz--) {
            p = (p + k) % sz;
            int want = (int) p + 1, pos = 0;                       // (p+1)-th alive child
            for (int step = log; step > 0; step >>= 1)
                if (pos + step <= n && t[pos + step] < want) { pos += step; want -= t[pos]; }
            int child = pos + 1;
            sb.append(child).append(sz > 1 ? ' ' : '\n');
            for (int j = child; j <= n; j += j & -j) t[j]--;
        }
        System.out.print(sb);
    }
}
```

<!-- test
in:
7 2
out:
3 6 2 7 5 1 4
-->
<!-- test
in:
1 1000000000
out:
1
-->
<!-- test
in:
5 0
out:
1 2 3 4 5
-->

</details>

### Example 4 — Sliding Window Median (two multisets / lazy-deletion heaps)  ·  ★ ≈1700

- **Source:** [CSES 1076 · Sliding Window Median](https://cses.fi/problemset/task/1076)
- **Difficulty:** ≈1700 (est.)
- **Problem:** $n \le 2\cdot10^5$ values up to $10^9$ and a window size $k$; print the median of every window of $k$ consecutive values (for even $k$, the smaller of the two middle values).
- **Thinking from first principles:** the two-heap median needs *deletions* when the window slides. C++: replace heaps by two `multiset`s (they support erase-one) and keep $|lo| = \lceil k/2\rceil$.
  Java: `PriorityQueue.remove(Object)` is $O(k)$, so use **lazy deletion**: give every element a unique key `value * 2^18 + index`, mark leaving indices as deleted, keep logical sizes,
  and discard deleted keys only when they surface at a heap top. Membership of the leaving element is decided by comparing with `lo`'s (clean) top, valid because all keys are distinct.

<details><summary>Solution</summary>

$O(n \log k)$ in both.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k; cin >> n >> k;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    multiset<long long> lo, hi;                                  // lo: smallest ceil(k/2) values of the window
    auto rebalance = [&]() {
        while (lo.size() > hi.size() + 1) { auto it = prev(lo.end()); hi.insert(*it); lo.erase(it); }
        while (lo.size() < hi.size()) { auto it = hi.begin(); lo.insert(*it); hi.erase(it); }
    };
    auto insert = [&](long long x) { if (lo.empty() || x <= *lo.rbegin()) lo.insert(x); else hi.insert(x); rebalance(); };
    auto erase = [&](long long x) {
        if (x <= *lo.rbegin()) lo.erase(lo.find(x)); else hi.erase(hi.find(x));
        rebalance();
    };
    for (int i = 0; i < n; i++) {
        insert(a[i]);
        if (i >= k) erase(a[i - k]);
        if (i >= k - 1) cout << *lo.rbegin() << (i + 1 < n ? ' ' : '\n');
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static PriorityQueue<Long> lo = new PriorityQueue<>(Comparator.reverseOrder()), hi = new PriorityQueue<>();
    static boolean[] dead;
    static int loSize = 0, hiSize = 0;                            // logical sizes (excluding lazily deleted keys)
    static final int SHIFT = 18;                                  // index < 2^18 >= 200000
    static void clean(PriorityQueue<Long> h) { while (!h.isEmpty() && dead[(int) (h.peek() & ((1 << SHIFT) - 1))]) h.poll(); }
    static void rebalance() {
        while (loSize > hiSize + 1) { clean(lo); hi.add(lo.poll()); loSize--; hiSize++; }
        while (loSize < hiSize) { clean(hi); lo.add(hi.poll()); hiSize--; loSize++; }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt();
        long[] key = new long[n];
        for (int i = 0; i < n; i++) key[i] = in.nextLong() << SHIFT | i;
        dead = new boolean[n];
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) {
            clean(lo);
            if (loSize == 0 || key[i] <= lo.peek()) { lo.add(key[i]); loSize++; } else { hi.add(key[i]); hiSize++; }
            rebalance();
            if (i >= k) {
                long out = key[i - k];
                clean(lo);
                if (out <= lo.peek()) loSize--; else hiSize--;    // distinct keys: membership by comparison
                dead[i - k] = true;
                rebalance();
            }
            if (i >= k - 1) { clean(lo); sb.append(lo.peek() >> SHIFT).append(i + 1 < n ? ' ' : '\n'); }
        }
        System.out.print(sb);
    }

    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

Why the Java `rebalance` cleans before moving: a lazily deleted key may sit on top; moving it to the other heap would resurrect it. `clean` keeps the invariant "physical tops are alive" exactly when we read them.

<!-- test
in:
8 3
2 4 3 5 8 1 2 1
out:
3 4 5 5 2 1
-->
<!-- test
in:
5 2
5 5 5 1 9
out:
5 5 1 1
-->
<!-- test
in:
1 1
1000000000
out:
1000000000
-->

</details>

### Example 5 — LRU cache in $O(1)$  ·  ★ ≈1500

- **Source:** Original I/O version of [LC 146 · LRU Cache](https://leetcode.com/problems/lru-cache/) — Medium.
- **Difficulty:** ≈1500 (est.)
- **Problem:** capacity $c \ge 1$, $q \le 2\cdot10^5$ operations: `get k` prints the value of key $k$ or $-1$ (and marks $k$ as most recently used); `put k v` sets the value (marking it most recent) and, if the cache now holds more than $c$ keys, evicts the least recently used key.
- **Thinking from first principles:** we need "find by key" ($O(1)$ → hash map) and "move to front / remove from back" ($O(1)$ → doubly linked list). Neither alone suffices; the map stores *pointers into the list*.
  C++'s `list::splice` moves a node without invalidating iterators. Java's `LinkedHashMap` in access order is exactly this structure.

<details><summary>Solution</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int cap, q; cin >> cap >> q;
    list<pair<long long, long long>> order;                       // front = most recently used
    unordered_map<long long, list<pair<long long, long long>>::iterator> where;
    where.reserve(2 * cap + 2);
    while (q--) {
        string op; long long k; cin >> op >> k;
        auto it = where.find(k);
        if (op == "get") {
            if (it == where.end()) { cout << -1 << '\n'; continue; }
            order.splice(order.begin(), order, it->second);        // O(1) move to front
            cout << it->second->second << '\n';
        } else {
            long long v; cin >> v;
            if (it != where.end()) { it->second->second = v; order.splice(order.begin(), order, it->second); continue; }
            order.emplace_front(k, v); where[k] = order.begin();
            if ((int)order.size() > cap) { where.erase(order.back().first); order.pop_back(); }
        }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in), 1 << 16);
        StringTokenizer st = new StringTokenizer(br.readLine());
        final int cap = Integer.parseInt(st.nextToken()); int q = Integer.parseInt(st.nextToken());
        LinkedHashMap<Long, Long> cache = new LinkedHashMap<>(16, 0.75f, true) {   // access order = recency
            @Override protected boolean removeEldestEntry(Map.Entry<Long, Long> e) { return size() > cap; }
        };
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            st = new StringTokenizer(br.readLine());
            String op = st.nextToken(); long k = Long.parseLong(st.nextToken());
            if (op.equals("get")) { Long v = cache.get(k); sb.append(v == null ? -1 : v).append('\n'); }
            else cache.put(k, Long.parseLong(st.nextToken()));
        }
        System.out.print(sb);
    }
}
```

In an interview, expect to be asked for the explicit doubly linked list in Java as well; `LinkedHashMap` is the production answer.

<!-- test
in:
2 9
put 1 1
put 2 2
get 1
put 3 3
get 2
put 4 4
get 1
get 3
get 4
out:
1
-1
-1
3
4
-->
<!-- test
in:
1 5
get 7
put 7 70
put 7 71
get 7
put 8 80
out:
-1
71
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **`multiset::erase(value)` removes every copy.** Erase by iterator (`erase(find(x))`) — and check `find(x) != end()` first.
2. **`prev(begin())` is undefined behaviour.** Always test `it == s.begin()` before stepping back.
3. **Java `null` from `floorKey`/`ceilingKey`/`get`.** Assigning to `int` auto-unboxes and throws `NullPointerException`; keep it as `Integer`/`Long` until checked.
4. **Member `lower_bound`, not `std::lower_bound`**, on sets and maps ($O(\log n)$ vs $O(n)$).
5. **Heap direction**: C++ `priority_queue` is a *max*-heap; Java `PriorityQueue` is a *min*-heap. For a min-heap of pairs in C++ use `greater<pair<...>>`, or push negated keys.
6. **Comparator overflow in Java**: `(a, b) -> b - a` fails for values near $\pm 2^{31}$; use `Integer.compare(b, a)` / `Long.compare`.
7. **Boxing cost**: `PriorityQueue<Long>`/`TreeMap<Long,…>` allocate objects per element — for $10^6$ operations consider packing into `long` and a primitive heap, or offline BIT solutions.
8. **PBDS multiset**: use `pair<value, id>`, not `less_equal` (which silently breaks `erase`/`find`).
9. **Hash maps**: never ship `unordered_map<long long, …>` with the default hash on Codeforces — use splitmix64 with a time-based seed, plus `reserve`. In Java, mix keys before inserting; a constant xor salt is useless.
10. **Lazy deletion bookkeeping**: track *logical* sizes separately from `heap.size()`, clean the top before every `peek`/`poll`, and give equal values unique ids so "is it deleted?" is well-defined.
11. **Iterator invalidation**: erasing from a `set`/`map` invalidates only the erased iterator; `unordered_map` rehashing invalidates all iterators (but not references to elements). `list::splice` invalidates none.
12. **`map[key]` inserts a default value** when the key is missing — use `find`/`count` for lookups that must not insert (and to avoid growing the map in loops).

## 7. Going further (toward 2400–2600+)

- **Greedy with heaps and regret** (undoable choices, "buy low sell high"): [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400; see [greedy with heaps](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md).
- **Mergeable heaps** (leftist / skew / pairing heaps) for "merge two priority queues" in $O(\log n)$; small-to-large merging of `priority_queue`s as the contest substitute.
- **Interval maps** (`map<int, int>` of disjoint segments) for painting/assignment problems — the "Chtholly tree" idea in [advanced segment trees](04-segment-tree-advanced-descent-merging-beats.md).
- **Order statistics on sliding windows with updates** → BIT/segment tree over compressed values instead of balanced trees.
- **Randomised hashing beyond maps**: hashing sets/multisets by random weights (xor or sum hashing), see [randomised algorithms and hashing](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md).

## 8. Practice ladder

**≤ 1500**
- [ ] [CSES 1091 · Concert Tickets](https://cses.fi/problemset/task/1091)
- [ ] [CSES 1164 · Room Allocation](https://cses.fi/problemset/task/1164)
- [ ] [CSES 1661 · Subarray Sums II](https://cses.fi/problemset/task/1661)
- [ ] [CF 4C · Registration System](https://codeforces.com/problemset/problem/4/C) — 1300
- [ ] [CF 1520D · Same Differences](https://codeforces.com/problemset/problem/1520/D) — 1200
- [ ] [CF 1526C2 · Potions (Hard Version)](https://codeforces.com/problemset/problem/1526/C2) — 1600

**1500–1900**
- [ ] [CF 1029C · Maximal Intersection](https://codeforces.com/problemset/problem/1029/C) — 1600
- [ ] [CF 1353D · Constructing the Array](https://codeforces.com/problemset/problem/1353/D) — 1600
- [ ] [CSES 2163 · Josephus Problem II](https://cses.fi/problemset/task/2163)
- [ ] [CSES 1076 · Sliding Window Median](https://cses.fi/problemset/task/1076)
- [ ] [CSES 1077 · Sliding Window Cost](https://cses.fi/problemset/task/1077)
- [ ] [CSES 2168 · Nested Ranges Check](https://cses.fi/problemset/task/2168)
- [ ] [CSES 2169 · Nested Ranges Count](https://cses.fi/problemset/task/2169)
- [ ] [CF 1462F · The Treasure of The Segments](https://codeforces.com/problemset/problem/1462/F) — 1800

**1900+**
- [ ] [CF 1974G · Money Buys Less Happiness Now ](https://codeforces.com/problemset/problem/1974/G) — 2000
- [ ] [CF 1428E · Carrots for Rabbits](https://codeforces.com/problemset/problem/1428/E) — 2200
- [ ] [CF 85D · Sum of Medians](https://codeforces.com/problemset/problem/85/D) — 2300
- [ ] [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400

## 9. LeetCode / FAANG cross-reference

- [LC 146 · LRU Cache](https://leetcode.com/problems/lru-cache/) — Medium — Example 5; the most-asked design question.
- [LC 460 · LFU Cache](https://leetcode.com/problems/lfu-cache/) — Hard — map key → (value, freq) + map freq → list; track the minimum frequency.
- [LC 295 · Find Median from Data Stream](https://leetcode.com/problems/find-median-from-data-stream/) — Hard — two heaps (§3.3).
- [LC 480 · Sliding Window Median](https://leetcode.com/problems/sliding-window-median/) — Hard — two multisets or lazy-deletion heaps (Example 4).
- [LC 215 · Kth Largest Element in an Array](https://leetcode.com/problems/kth-largest-element-in-an-array/) — Medium — size-$k$ min-heap, or quickselect.
- [LC 703 · Kth Largest Element in a Stream](https://leetcode.com/problems/kth-largest-element-in-a-stream/) — Easy — size-$k$ min-heap.
- [LC 347 · Top K Frequent Elements](https://leetcode.com/problems/top-k-frequent-elements/) — Medium — hash counts + heap (or bucket sort).
- [LC 23 · Merge k Sorted Lists](https://leetcode.com/problems/merge-k-sorted-lists/) — Hard — heap of list heads.
- [LC 973 · K Closest Points to Origin](https://leetcode.com/problems/k-closest-points-to-origin/) — Medium — max-heap of size $k$.
- [LC 621 · Task Scheduler](https://leetcode.com/problems/task-scheduler/) — Medium — greedy by counts (formula) or heap simulation.
- [LC 220 · Contains Duplicate III](https://leetcode.com/problems/contains-duplicate-iii/) — Hard — ordered set over a window: `ceiling(x - t)`.
- [LC 352 · Data Stream as Disjoint Intervals](https://leetcode.com/problems/data-stream-as-disjoint-intervals/) — Hard — `TreeMap` interval merging with floor/ceiling.
- [LC 855 · Exam Room](https://leetcode.com/problems/exam-room/) — Medium — ordered set of seats, neighbours after insertion.
- [LC 2034 · Stock Price Fluctuation ](https://leetcode.com/problems/stock-price-fluctuation/) — Medium — map + lazy-deletion heaps (or a multiset).
- [LC 2353 · Design a Food Rating System](https://leetcode.com/problems/design-a-food-rating-system/) — Medium — per-cuisine ordered set or lazy heap.
- [LC 895 · Maximum Frequency Stack](https://leetcode.com/problems/maximum-frequency-stack/) — Hard — frequency buckets of stacks.
- [LC 1438 · Longest Continuous Subarray With Absolute Diff Less Than or Equal to Limit](https://leetcode.com/problems/longest-continuous-subarray-with-absolute-diff-less-than-or-equal-to-limit/) — Medium — multiset window (or two deques).

Interview frequency: very high. Heaps, ordered maps and hash maps are the workhorses of FAANG coding rounds; know the Java and C++ APIs cold.

## 10. Self-check

1. How do you get "largest element $< x$" from a `multiset`, and from a `TreeMap`? What must you check first?
2. Why is `ms.erase(5)` a bug when you meant to remove one 5?
3. How do you emulate a multiset with order statistics in PBDS, and why not `less_equal`?
4. Your Java solution needs k-th smallest of a dynamic multiset, values known offline. What do you use?
5. Write the comparators for a min-heap of `pair<long long,int>` in C++ and a max-heap of `long` in Java.
6. Explain lazy deletion and why its amortised cost is $O(\log n)$.
7. Why does the default `unordered_map<long long,int>` get hacked, and how does splitmix64 with a random seed fix it? Why does xoring keys with a salt not fix Java's `HashMap`?
8. Sketch an $O(1)$ LRU cache.

<details><summary>Answers</summary>

1. C++: `auto it = ms.lower_bound(x); if (it != ms.begin()) ans = *prev(it);`. Java: `Long y = map.lowerKey(x); if (y != null) ...`.
2. It erases *all* copies of 5. Use `ms.erase(ms.find(5))` after checking the iterator.
3. Store `pair<value, unique id>`; count $< x$ with `order_of_key({x, INT_MIN})`. `less_equal` breaks the equivalence relation the tree relies on, so `find`/`erase` stop working.
4. A BIT over compressed values with the k-th descent; or a treap if values are online.
5. C++: `priority_queue<pair<ll,int>, vector<pair<ll,int>>, greater<pair<ll,int>>>`. Java: `new PriorityQueue<Long>(Comparator.reverseOrder())` or `(a, b) -> Long.compare(b, a)`.
6. Mark deleted elements and keep logical sizes; discard deleted elements only when they reach the top. Each element is pushed once and popped once, so total work is $O(\log n)$ per element.
7. The default hash is the identity and buckets are `key mod p` for known primes; an adversary sends multiples of $p$. A random-seeded nonlinear mix makes bucket indices unpredictable. In Java the hash is linear in xor ($h(k\oplus s) = h(k)\oplus h(s)$), so colliding keys still collide.
8. Hash map key → node in a doubly linked list ordered by recency; get moves the node to the front; put inserts at the front and evicts from the back when over capacity.

</details>
