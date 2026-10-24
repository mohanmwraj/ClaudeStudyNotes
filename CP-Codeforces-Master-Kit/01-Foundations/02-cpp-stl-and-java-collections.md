# C++ STL and Java Collections side by side

> **Band:** 🟢 ≤ 1400 (used at every band) · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [complexity](01-complexity-and-constraint-reading.md), [environment & templates](../00-Roadmap-and-Strategy/06-environment-templates-cpp-java.md)
> **You can say you know this when:** for any "maintain a changing collection and ask X" requirement you pick the right container in both languages without looking anything up, know the exact complexity of each call you make, and can name the trap (iterator invalidation, boxing, anti-hash, `multiset::erase(value)`) that would bite you.

## 1. First principles — why this works

A container is a decision about **how elements are laid out in memory**, and every operation's cost follows from that layout.
There are only four layouts you need:

1. **Contiguous array** (`vector`, `ArrayList`, `int[]`): element $i$ lives at `base + i*size`. Index in $O(1)$, append amortised
   $O(1)$ (doubling, proof in [complexity](01-complexity-and-constraint-reading.md)), but inserting in the middle shifts
   everything after it: $O(n)$. Cache-friendly — scanning is as fast as memory allows.
2. **Ring buffer / chunked array** (`deque`, `ArrayDeque`): like an array but with free space at both ends, so push/pop at
   *either* end is $O(1)$.
3. **Balanced binary search tree** (`set`/`map`/`multiset`, `TreeSet`/`TreeMap`; red–black trees in both libraries): keeps elements
   sorted, height $O(\log n)$, so insert, erase, find, and "smallest element $\ge x$" all cost $O(\log n)$. Each element is a separate
   heap node with pointers — 10–50× slower per operation than array access.
4. **Hash table** (`unordered_map`, `HashMap`): a key's hash picks a bucket, giving expected $O(1)$ insert/find — *if* the hash spreads keys
   evenly. No order. An adversary who knows the hash function can force all keys into one bucket.

Plus one derived structure: a **binary heap** (`priority_queue`, `PriorityQueue`) stores a complete binary tree in an array with the
invariant "parent ≤ children" (or ≥). It gives $O(1)$ access to the extreme element and $O(\log n)$ push/pop — but no search and no
arbitrary deletion.

Choosing a container is therefore answering three questions: *Do I need order?* (tree, or sort once) *Do I need positional
access?* (array/deque) *Do I only ever need the extreme element?* (heap). The cheapest structure that answers the queries wins.
A very common strong-solver move is to avoid dynamic structures entirely: **read everything, sort once, then scan** — an
$O(n\log n)$ sort plus a linear pass beats $n$ tree operations by a large constant factor.

## 2. Formulas, definitions and identities

**Complexities (both libraries; $n$ = current size).**

| Operation | `vector` / `ArrayList` | `deque` / `ArrayDeque` | `set`,`map` / `TreeSet`,`TreeMap` | `unordered_map` / `HashMap` | `priority_queue` / `PriorityQueue` |
|---|---|---|---|---|---|
| access by index | $O(1)$ | $O(1)$ C++ / — Java | — | — | — |
| push/pop back | amortised $O(1)$ | $O(1)$ | — | — | $O(\log n)$ push, $O(\log n)$ pop |
| push/pop front | $O(n)$ | $O(1)$ | — | — | — |
| insert/erase middle | $O(n)$ | $O(n)$ | $O(\log n)$ | expected $O(1)$ | — |
| find key | $O(n)$ ($O(\log n)$ if sorted) | $O(n)$ | $O(\log n)$ | expected $O(1)$, worst $O(n)$ | — |
| min / max | $O(n)$ | $O(n)$ | $O(1)$ via `begin`/`rbegin` ($O(\log n)$ in Java `first`/`last`) | $O(n)$ | $O(1)$ (top) |
| next element $\ge x$ | $O(\log n)$ if sorted | — | $O(\log n)$ | — | — |
| iterate all | $O(n)$, fast | $O(n)$ | $O(n)$, slower | $O(n + \text{buckets})$ | $O(n)$ unordered |

**Heap invariant.** In an array heap, node $i$ (0-indexed) has children $2i+1$, $2i+2$ and parent $\lfloor (i-1)/2\rfloor$; height $\lfloor\log_2 n\rfloor$.
Building a heap from $n$ elements bottom-up costs $\sum_h \frac{n}{2^{h+1}} O(h) = O(n)$ (most nodes are near the leaves), while $n$
pushes cost $O(n\log n)$.

**Hash tables.** With load factor $\alpha = n/\text{buckets}$ and a hash that behaves randomly, an operation inspects $1+\alpha$ entries in expectation.
`unordered_map` defaults to $\alpha_{\max} = 1$; Java's `HashMap` resizes at $0.75$. Worst case (all keys in one bucket): $O(n)$
per operation in C++. In Java 8+, a bucket with at least 8 entries in a table of capacity $\ge 64$ is converted into a red–black tree
(`TREEIFY_THRESHOLD = 8`, `MIN_TREEIFY_CAPACITY = 64` in the OpenJDK 21 source), so the worst case for `Comparable` keys
(`Integer`, `Long`, `String`) degrades to $O(\log n)$ per operation — slow, but not quadratic.

**Why the default hashes are attackable.** `std::hash<long long>` in GCC's libstdc++ is the identity function (standard knowledge, not verified
in this research), and bucket = hash mod a known prime from a fixed growth sequence. Java's `Integer.hashCode()` returns the value itself,
and `HashMap` uses `h ^ (h >>> 16)` masked by the power-of-two capacity (both confirmed in the OpenJDK 21 source). In both cases an
attacker can pick keys that collide. A random **non-linear** remix of the key (splitmix64 with a per-run random offset) defeats this;
XOR-ing every key with one random constant does **not** — XOR preserves exactly the differences the attack relies on.

**Sorted-container query vocabulary (memorise both columns).**

| Want | C++ `set<T> s` | Java `TreeSet<T> s` |
|---|---|---|
| smallest $\ge x$ | `s.lower_bound(x)` | `s.ceiling(x)` |
| smallest $> x$ | `s.upper_bound(x)` | `s.higher(x)` |
| largest $\le x$ | `prev(s.upper_bound(x))` (check `!= begin`) | `s.floor(x)` |
| largest $< x$ | `prev(s.lower_bound(x))` (check `!= begin`) | `s.lower(x)` |
| min / max | `*s.begin()` / `*s.rbegin()` | `s.first()` / `s.last()` |
| remove min | `s.erase(s.begin())` | `s.pollFirst()` |
| "not found" | iterator `== s.end()` | returns `null` |

For maps the same calls exist as `m.lower_bound(k)` / `m.ceilingKey(k)`, `m.ceilingEntry(k)`, `m.floorKey(k)`, `m.firstKey()`, `m.pollFirstEntry()`.

**Iterator / reference invalidation (C++).**

| Container | Insertion | Erasure |
|---|---|---|
| `vector` | if reallocation happens: **all** iterators, pointers and references; otherwise those at/after the insertion point | at/after the erased element |
| `deque` | insertion at either end: all iterators (references stay valid); in the middle: everything | at the ends: only the erased one(s); in the middle: everything |
| `set`, `map`, `multiset`, `list` | none | only the erased element |
| `unordered_map/set` | rehash invalidates all iterators (references to elements stay valid) | only the erased element |

Java has no invalidation rules to memorise, only one: structurally modifying a collection while iterating over it with a for-each loop
throws `ConcurrentModificationException`. Use `iterator.remove()`, `removeIf`, or collect changes and apply them afterwards.

## 3. Implementation (C++ and Java)

### 3.1 Core containers, call by call

```cpp
void containerTour() {
    vector<int> v = {5, 1, 4};
    v.push_back(2);                       // amortised O(1)
    v.pop_back();
    v.reserve(1 << 20);                   // avoid repeated reallocation when the size is known
    vector<vector<int>> g(10);            // adjacency lists
    g[3].push_back(7);

    deque<int> dq;                        // O(1) at both ends, O(1) index
    dq.push_front(1); dq.push_back(2); dq.pop_front();

    set<int> s = {1, 5, 9};
    auto it = s.lower_bound(4);           // -> 5; use the MEMBER function: std::lower_bound on a set is O(n)
    if (it != s.begin()) { auto pv = prev(it); (void)pv; }  // largest < 4 -> 1
    s.erase(5);

    multiset<int> ms = {2, 2, 3};
    ms.erase(ms.find(2));                 // removes ONE copy; ms.erase(2) would remove both
    map<string, int> cnt;
    cnt["abc"]++;                         // operator[] inserts a default value if missing
    bool has = cnt.count("zzz") > 0;      // count/find/contains do not insert
    (void)has;

    priority_queue<int> maxHeap;                              // max-heap by default
    priority_queue<int, vector<int>, greater<int>> minHeap;   // min-heap
    maxHeap.push(3); minHeap.push(3);
    // pairs and tuples compare lexicographically, which gives multi-key ordering for free
    priority_queue<pair<long long, int>, vector<pair<long long, int>>, greater<>> pq;
    pq.push({10, 1});
    auto [d, node] = pq.top(); pq.pop();
    (void)d; (void)node;
}
```

```java
static void containerTour() {
    ArrayList<Integer> v = new ArrayList<>(List.of(5, 1, 4));
    v.add(2);
    v.remove(v.size() - 1);               // remove(int index); v.remove(Integer.valueOf(2)) removes a VALUE
    int[] prim = new int[1 << 20];        // prefer primitive arrays for big data: 4 bytes per element, no boxing

    ArrayDeque<Integer> dq = new ArrayDeque<>();   // stack AND queue; faster than Stack / LinkedList; no nulls
    dq.addFirst(1); dq.addLast(2); dq.pollFirst();

    TreeSet<Integer> s = new TreeSet<>(List.of(1, 5, 9));
    Integer c = s.ceiling(4);             // 5, or null if none
    Integer lo = s.lower(4);              // 1
    s.remove(5);

    TreeMap<Integer, Integer> ms = new TreeMap<>();   // Java has no multiset: keep value -> count
    ms.merge(2, 1, Integer::sum); ms.merge(2, 1, Integer::sum);
    if (ms.merge(2, -1, Integer::sum) == 0) ms.remove(2);   // remove ONE copy

    HashMap<String, Integer> cnt = new HashMap<>();
    cnt.merge("abc", 1, Integer::sum);
    int got = cnt.getOrDefault("zzz", 0);

    PriorityQueue<Integer> minHeap = new PriorityQueue<>();                       // MIN-heap by default
    PriorityQueue<Integer> maxHeap = new PriorityQueue<>(Comparator.reverseOrder());
    minHeap.add(3); maxHeap.add(3);
    PriorityQueue<long[]> pq = new PriorityQueue<>((x, y) -> Long.compare(x[0], y[0]));
    pq.add(new long[]{10, 1});
    long[] top = pq.poll();
}
```

### 3.2 A hash map that survives anti-hash tests

```cpp
struct SplitMix64Hash {
    static uint64_t mix(uint64_t x) {                 // splitmix64 finaliser: a bijection with strong avalanche
        x += 0x9e3779b97f4a7c15ULL;
        x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
        x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
        return x ^ (x >> 31);
    }
    size_t operator()(uint64_t x) const {
        static const uint64_t SEED = chrono::steady_clock::now().time_since_epoch().count();  // unknown to the hacker
        return mix(x + SEED);
    }
};

void hashDemo() {
    unordered_map<long long, int, SplitMix64Hash> freq;
    freq.reserve(1 << 18);                            // fewer rehashes; also speeds things up noticeably
    freq[123456789012LL]++;
}
```

```java
static final long SEED = System.nanoTime();
static long mix(long x) {                             // same bijection: distinct keys stay distinct after mixing
    x += 0x9e3779b97f4a7c15L + SEED;
    x = (x ^ (x >>> 30)) * 0xbf58476d1ce4e5b9L;
    x = (x ^ (x >>> 27)) * 0x94d049bb133111ebL;
    return x ^ (x >>> 31);
}

static void hashDemo() {
    HashMap<Long, Integer> freq = new HashMap<>(1 << 18);
    long key = 123456789012L;
    freq.merge(mix(key), 1, Integer::sum);           // store mix(key); look up with mix(key) too
}
```

Because `mix` is a bijection on 64-bit integers, using `mix(key)` as the stored key loses nothing (if you need the original key back,
store it in the value). The most robust alternative in both languages is to avoid hashing: sort, deduplicate and binary-search
(coordinate compression, see [coordinate compression](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md)).

### 3.3 Algorithms you call every day, and their Java equivalents

| C++ `<algorithm>` / `<numeric>` | Java |
|---|---|
| `sort(a.begin(), a.end())` — introsort, $O(n\log n)$ worst case, not stable | `Arrays.sort(int[])` — dual-pivot quicksort; `Arrays.sort(Object[])`, `Collections.sort`, `List.sort` — TimSort, **stable** |
| `sort(..., greater<>())` | `Arrays.sort(Integer[], Collections.reverseOrder())`; for primitives sort then reverse |
| `stable_sort` | object sorts are already stable |
| `lower_bound`, `upper_bound`, `equal_range` | none for "first $\ge x$": `Arrays.binarySearch` returns *some* matching index, or `-(insertion point) - 1`. Write `lowerBound` (below) |
| `binary_search` | `Arrays.binarySearch(a, x) >= 0` |
| `next_permutation` | none — write it (below) |
| `accumulate(a.begin(), a.end(), 0LL)` — the init value's type is the sum's type | loop with a `long`; `Arrays.stream(int[]).sum()` returns **`int`** and overflows |
| `iota(a.begin(), a.end(), 0)` | `Arrays.setAll(a, i -> i)` |
| `a.erase(unique(a.begin(), a.end()), a.end())` after sorting | sort, then compact manually |
| `reverse`, `rotate` | `Collections.reverse`, `Collections.rotate` (lists); arrays: manual |
| `nth_element` — expected $O(n)$ | none; shuffle + quickselect, or just sort |
| `*max_element(...)`, `count`, `count_if`, `fill` | loops / `Arrays.fill` / `Collections.max` |
| `__builtin_popcount`, `std::gcd`, `std::lcm` | `Integer.bitCount`, `BigInteger.gcd` or a 3-line Euclid |

```cpp
void algorithmsDemo() {
    vector<int> a = {3, 1, 2, 3, 1};
    sort(a.begin(), a.end());                                          // 1 1 2 3 3
    a.erase(unique(a.begin(), a.end()), a.end());                      // 1 2 3 (dedupe needs sorted input)
    int idx = lower_bound(a.begin(), a.end(), 2) - a.begin();          // first >= 2  -> 1
    int cntLess = lower_bound(a.begin(), a.end(), 3) - a.begin();      // number of elements < 3 -> 2
    long long total = accumulate(a.begin(), a.end(), 0LL);             // 0LL, not 0: the sum is computed in the init type
    vector<int> p(4);
    iota(p.begin(), p.end(), 0);
    do { /* visits all 4! permutations of p in lexicographic order */ } while (next_permutation(p.begin(), p.end()));
    vector<int> order(5);
    iota(order.begin(), order.end(), 0);
    vector<int> key = {50, 10, 40, 10, 30};
    stable_sort(order.begin(), order.end(), [&](int i, int j) { return key[i] < key[j]; });  // sort INDICES by key
    (void)idx; (void)cntLess; (void)total;
}
```

```java
static int lowerBound(int[] a, int x) {           // first index with a[i] >= x, or a.length
    int lo = 0, hi = a.length;
    while (lo < hi) { int mid = (lo + hi) >>> 1; if (a[mid] < x) lo = mid + 1; else hi = mid; }
    return lo;
}

static int upperBound(int[] a, int x) {           // first index with a[i] > x
    int lo = 0, hi = a.length;
    while (lo < hi) { int mid = (lo + hi) >>> 1; if (a[mid] <= x) lo = mid + 1; else hi = mid; }
    return lo;
}

static boolean nextPermutation(int[] p) {         // same contract as std::next_permutation
    int i = p.length - 2;
    while (i >= 0 && p[i] >= p[i + 1]) i--;       // longest non-increasing suffix starts at i+1
    if (i < 0) { reverse(p, 0, p.length - 1); return false; }
    int j = p.length - 1;
    while (p[j] <= p[i]) j--;                     // rightmost element larger than p[i]
    int t = p[i]; p[i] = p[j]; p[j] = t;
    reverse(p, i + 1, p.length - 1);
    return true;
}

static void reverse(int[] a, int l, int r) {
    while (l < r) { int t = a[l]; a[l++] = a[r]; a[r--] = t; }
}

static int dedupeSorted(int[] a) {                // returns the new logical length
    int k = 0;
    for (int i = 0; i < a.length; i++) if (k == 0 || a[i] != a[k - 1]) a[k++] = a[i];
    return k;
}

static Integer[] sortIndicesByKey(int[] key) {    // stable: equal keys keep index order
    Integer[] order = new Integer[key.length];
    for (int i = 0; i < key.length; i++) order[i] = i;
    Arrays.sort(order, Comparator.comparingInt(i -> key[i]));
    return order;
}
```

### 3.4 Pairs, tuples and keys in Java

C++ gets lexicographic `pair`/`tuple` comparison and hashing-by-composition for free. In Java you choose between a `record`
(clear, but one object per element) and **packing two `int`s into one `long`** (no objects; sorts correctly with `Arrays.sort(long[])`).

```java
record Point(int x, int y) {}                     // equals, hashCode, toString generated (Java 16+)

static final Comparator<Point> BY_X_THEN_Y = Comparator.comparingInt(Point::x).thenComparingInt(Point::y);

// Pack (x, y) so that numeric order of the long == lexicographic order of (x, y), negatives included.
static long pack(int x, int y) {
    return ((long) x << 32) | ((y ^ 0x80000000L) & 0xffffffffL);   // flip y's sign bit so negative y sorts first
}
static int unpackX(long k) { return (int) (k >> 32); }
static int unpackY(long k) { return (int) ((k & 0xffffffffL) ^ 0x80000000L); }
```

The sign-bit flip matters: with the naive `(y & 0xffffffffL)`, a negative `y` would sort *after* every positive `y`.

### 3.5 A growable primitive list for Java

`ArrayList<Integer>` stores references to boxed objects: 4–6× the memory of an `int[]` and a pointer dereference per access.
For adjacency lists and large buffers, a 15-line primitive list pays for itself.

```java
static final class IntList {
    int[] a = new int[4];
    int size = 0;
    void add(int x) { if (size == a.length) a = Arrays.copyOf(a, size * 2); a[size++] = x; }
    int get(int i) { return a[i]; }
    int pop() { return a[--size]; }
    boolean isEmpty() { return size == 0; }
}
```

## 4. Recognising the pattern

| Requirement in the statement | Container |
|---|---|
| count occurrences, keys are small integers | plain array indexed by value |
| count occurrences, keys are large/strings | sort + scan; or a hash map with a randomised hash |
| "the smallest available value $\ge x$" while values are removed | `set` / `TreeSet` (`lower_bound` / `ceiling`); with duplicates `multiset` / `TreeMap` counts |
| repeatedly take the best item, add new items | heap |
| repeatedly take the best item, *and* delete arbitrary items | `set` of pairs, or a heap with lazy deletion |
| maximum of a sliding window | monotonic `deque` ([monotonic deque](../02-Core-Techniques/04-monotonic-stack-and-deque.md)) |
| maintain the multiset of gaps between chosen points | `set` of points + `multiset` of gaps (Example 4) |
| "k-th smallest" in a changing set | order-statistics tree ([PBDS](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md)) or Fenwick tree on compressed values |
| BFS frontier | `queue` / `ArrayDeque`; 0-1 BFS needs a `deque` |
| process items sorted by several keys | sort with a comparator, or pairs/tuples |

Often confused: `priority_queue` cannot answer "is $x$ present?" or delete $x$; `set` can, at a higher constant. And
`unordered_map` is not automatically faster than `map` for $\le 10^5$ operations with string keys — measure, or sort instead.

## 5. Worked examples (graded)

Every Java solution below uses the same `FastReader` (a `DataInputStream`-based tokenizer; full explanation in
[environment & templates](../00-Roadmap-and-Strategy/06-environment-templates-cpp-java.md)).

### Example 1 — Distinct Numbers  ·  ★ ≈1000 (est.)

- **Source:** [CSES 1621 · Distinct Numbers](https://cses.fi/problemset/task/1621)
- **Difficulty:** ≈1000 (est.)
- **Problem:** Count the distinct values among $n \le 2\cdot10^5$ integers $x_i \le 10^9$.
- **Thinking from first principles:** values are too large to index an array. Options: a hash set (expected $O(n)$, but only if the
  hash is not attacked — on Codeforces, with hacks, assume it will be), a tree set ($O(n\log n)$ with a large constant), or
  **sort and count positions where the value changes** — $O(n\log n)$ with the best constant and no bad worst case.

<details><summary>Solution</summary>

Sort; the answer is 1 plus the number of $i$ with $a_i \ne a_{i-1}$ (C++: `unique`). In Java, shuffle before `Arrays.sort(int[])` — cheap
insurance against adversarial inputs for quicksort-based primitive sorting (details in [sorting](05-sorting-and-comparators.md)).

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
    sort(a.begin(), a.end());
    cout << unique(a.begin(), a.end()) - a.begin() << '\n';
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
        Random rnd = new Random();
        for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = a[i]; a[i] = a[j]; a[j] = t; }
        Arrays.sort(a);
        int distinct = n == 0 ? 0 : 1;
        for (int i = 1; i < n; i++) if (a[i] != a[i - 1]) distinct++;
        System.out.println(distinct);
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
1000000000 1 1000000000 5 5 1
out:
3
-->
<!-- test
in:
1
7
out:
1
-->
<!-- test
in:
4
4 3 2 1
out:
4
-->

### Example 2 — Registration System  ·  ★ 1300

- **Source:** [CF 4C · Registration System](https://codeforces.com/problemset/problem/4/C) — 1300
- **Difficulty:** 1300
- **Problem:** $n \le 10^5$ registration requests, each a lowercase name of at most 32 letters. A new name gets "OK"; a taken name gets
  `name` + the smallest positive integer $i$ such that `name`$i$ is not yet in the database, and that new name is stored too.
- **Thinking from first principles:** the statement suggests a search "try 1, 2, 3, … until free", which could cost $O(n)$ per request.
  But requests contain **letters only**, so a generated name like `abc3` can never collide with a *requested* name; the only names of the
  form `abc`$i$ in the database are the ones we generated for `abc`, and we generated them as 1, 2, 3, … in order. Hence the smallest free
  $i$ is simply (number of previous requests for `abc`). One hash-map counter per name: expected $O(n \cdot |s|)$. Reading the input
  alphabet carefully turned a search into a counter.

<details><summary>Solution</summary>

`cnt[name]` = how many times this name was requested before. Print OK if 0, else `name + cnt`. Strings as hash keys are fine here; for an
ordered alternative use `map`/`TreeMap` ($O(|s|\log n)$ per request).

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    unordered_map<string, int> cnt;
    cnt.reserve(2 * n);
    string s;
    for (int i = 0; i < n; i++) {
        cin >> s;
        int& c = cnt[s];
        if (c == 0) cout << "OK\n";
        else cout << s << c << '\n';
        c++;
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
        int n = in.nextInt();
        HashMap<String, Integer> cnt = new HashMap<>(2 * n);
        for (int i = 0; i < n; i++) {
            String s = in.next();
            int c = cnt.getOrDefault(s, 0);
            out.println(c == 0 ? "OK" : s + c);
            cnt.put(s, c + 1);
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
        String next() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

</details>

<!-- test
in:
6
abacaba
acaba
abacaba
acab
abacaba
acaba
out:
OK
OK
abacaba1
OK
abacaba2
acaba1
-->
<!-- test
in:
3
z
z
z
out:
OK
z1
z2
-->
<!-- test
in:
1
a
out:
OK
-->

### Example 3 — Concert Tickets  ·  ★ ≈1400 (est.)

- **Source:** [CSES 1091 · Concert Tickets](https://cses.fi/problemset/task/1091)
- **Difficulty:** ≈1400 (est.)
- **Problem:** $n$ tickets with prices $h_i$ and $m$ customers ($n, m \le 2\cdot10^5$, values $\le10^9$) arrive in order; each takes the most
  expensive remaining ticket not exceeding their maximum $t_j$ (print its price, or $-1$), and that ticket disappears.
- **Thinking from first principles:** each customer asks "largest element $\le t$" in a set that loses elements, with duplicates allowed.
  Sorting once does not help by itself because deletions punch holes into the sorted array (a DSU "next free slot" trick does work — see
  [DSU](../08-Data-Structures/06-dsu-and-variants.md)). The direct tool is an ordered multiset: $O(\log n)$ per query.

<details><summary>Solution</summary>

C++: `multiset`; `upper_bound(t)` is the first price $> t$, so the answer is the element just before it (if any). Erase **that iterator**,
not the value (erasing the value would delete every ticket with that price). Java has no multiset: `TreeMap<price, count>` with `floorKey`.
$O((n+m)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, m;
    cin >> n >> m;
    multiset<int> prices;
    for (int i = 0; i < n; i++) { int h; cin >> h; prices.insert(h); }
    for (int j = 0; j < m; j++) {
        int t;
        cin >> t;
        auto it = prices.upper_bound(t);
        if (it == prices.begin()) { cout << -1 << '\n'; continue; }
        --it;                                   // largest price <= t
        cout << *it << '\n';
        prices.erase(it);                       // erase ONE ticket
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
        int n = in.nextInt(), m = in.nextInt();
        TreeMap<Integer, Integer> prices = new TreeMap<>();
        for (int i = 0; i < n; i++) prices.merge(in.nextInt(), 1, Integer::sum);
        for (int j = 0; j < m; j++) {
            int t = in.nextInt();
            Integer p = prices.floorKey(t);
            if (p == null) { out.println(-1); continue; }
            out.println(p);
            if (prices.get(p) == 1) prices.remove(p);
            else prices.put(p, prices.get(p) - 1);
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
3 4
5 5 1
5 5 5 2
out:
5
5
1
-1
-->
<!-- test
in:
1 1
10
9
out:
-1
-->
<!-- test
in:
4 3
1 2 3 4
10 2 1
out:
4
2
1
-->

### Example 4 — Traffic Lights  ·  ★ ≈1500 (est.)

- **Source:** [CSES 1163 · Traffic Lights](https://cses.fi/problemset/task/1163)
- **Difficulty:** ≈1500 (est.)
- **Problem:** A street $[0, x]$ ($x \le 10^9$) receives $n \le 2\cdot10^5$ traffic lights at distinct positions, one at a time. After each
  addition print the length of the longest stretch without lights.
- **Thinking from first principles:** adding a light at $p$ only changes the one gap $(l, r)$ that contains $p$: it disappears and two
  gaps $p-l$ and $r-p$ appear. So we need (a) "neighbours of $p$" — an ordered set of positions — and (b) "current maximum of a multiset
  of gap lengths that supports deleting one specific value" — an ordered multiset. Two trees, $O(\log n)$ per light.
  (An elegant alternative: process in reverse, *removing* lights, where gaps only merge and the maximum only grows — the
  "reverse time" trick from [first-principles problem solving](../00-Roadmap-and-Strategy/05-first-principles-problem-solving.md).)

<details><summary>Solution</summary>

Positions set starts as $\{0, x\}$, gaps multiset as $\{x\}$. For each $p$: find $r$ = successor, $l$ = predecessor; remove one copy of
$r-l$; insert $p-l$ and $r-p$; print the largest gap. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int x, n;
    cin >> x >> n;
    set<int> pos = {0, x};
    multiset<int> gaps = {x};
    for (int i = 0; i < n; i++) {
        int p;
        cin >> p;
        auto it = pos.upper_bound(p);
        int r = *it, l = *prev(it);
        gaps.erase(gaps.find(r - l));
        gaps.insert(p - l);
        gaps.insert(r - p);
        pos.insert(p);
        cout << *gaps.rbegin() << (i + 1 < n ? ' ' : '\n');
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
        int x = in.nextInt(), n = in.nextInt();
        TreeSet<Integer> pos = new TreeSet<>(List.of(0, x));
        TreeMap<Integer, Integer> gaps = new TreeMap<>();
        gaps.put(x, 1);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) {
            int p = in.nextInt();
            int r = pos.higher(p), l = pos.lower(p);
            int g = r - l;
            if (gaps.get(g) == 1) gaps.remove(g); else gaps.put(g, gaps.get(g) - 1);
            gaps.merge(p - l, 1, Integer::sum);
            gaps.merge(r - p, 1, Integer::sum);
            pos.add(p);
            sb.append(gaps.lastKey()).append(i + 1 < n ? ' ' : '\n');
        }
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
10 2
5 1
out:
5 5
-->
<!-- test
in:
10 3
1 2 3
out:
9 8 7
-->
<!-- test
in:
2 1
1
out:
1
-->

### Example 5 — Constructing the Array  ·  ★ 1600

- **Source:** [CF 1353D · Constructing the Array](https://codeforces.com/problemset/problem/1353/D) — 1600
- **Difficulty:** 1600
- **Problem:** An array of $n$ zeros ($\sum n \le 2\cdot10^5$ over tests). For $i = 1..n$: take the longest maximal run of zeros (leftmost if
  tied), and write $i$ into its middle cell (the left-middle one if the length is even). Output the final array.
- **Thinking from first principles:** simulating by scanning for the longest run is $O(n^2)$. But the set of runs evolves very simply:
  each step removes one run and adds at most two smaller ones. "Repeatedly remove the best, insert new items" is a heap; the tie-break
  "leftmost" is just a second key. With 1-indexed $[l, r]$, the middle is $\lfloor (l+r)/2 \rfloor$ in both parity cases (for even length
  $l+r$ is odd, and $\lfloor (l+r)/2\rfloor = (l+r-1)/2$).

<details><summary>Solution</summary>

Heap ordered by (length descending, left end ascending). C++: push `(len, -l)` into a max-heap — negating `l` turns "smaller $l$ first"
into "larger $-l$ first". Java: a `PriorityQueue<int[]>` with an explicit two-key comparator. $O(n\log n)$.

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
        vector<int> a(n + 1);
        priority_queue<pair<int, int>> pq;            // (length, -left)
        pq.push({n, -1});
        for (int i = 1; i <= n; i++) {
            auto [len, negL] = pq.top();
            pq.pop();
            int l = -negL, r = l + len - 1, mid = (l + r) / 2;
            a[mid] = i;
            if (mid > l) pq.push({mid - l, -l});
            if (r > mid) pq.push({r - mid, -(mid + 1)});
        }
        for (int i = 1; i <= n; i++) cout << a[i] << (i < n ? ' ' : '\n');
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
            int[] a = new int[n + 1];
            PriorityQueue<int[]> pq = new PriorityQueue<>((p, q) -> p[0] != q[0] ? Integer.compare(q[0], p[0]) : Integer.compare(p[1], q[1]));
            pq.add(new int[]{n, 1});                  // {length, left}
            for (int i = 1; i <= n; i++) {
                int[] s = pq.poll();
                int l = s[1], r = l + s[0] - 1, mid = (l + r) / 2;
                a[mid] = i;
                if (mid > l) pq.add(new int[]{mid - l, l});
                if (r > mid) pq.add(new int[]{r - mid, mid + 1});
            }
            StringBuilder sb = new StringBuilder();
            for (int i = 1; i <= n; i++) sb.append(a[i]).append(i < n ? ' ' : '\n');
            out.print(sb);
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
1
2
5
6
out:
1
1 2
2 4 1 3 5
3 4 1 5 2 6
-->
<!-- test
in:
1
3
out:
2 1 3
-->

## 6. Tricks, pitfalls and things to remember

1. **`std::lower_bound(s.begin(), s.end(), x)` on a `set`/`map` is $O(n)$** — the iterators are not random-access, so the generic
   algorithm walks. Always call the member `s.lower_bound(x)`.
2. **`multiset::erase(value)` removes every copy.** Use `ms.erase(ms.find(value))` (and check `find != end`).
3. **`map[key]` inserts.** Checking `if (mp[x])` adds `x` with value 0 — the map grows and later iteration sees phantom keys. Use
   `count`, `find` or C++20 `contains`. Java's `get` returns `null` for missing keys; unboxing that `null` into an `int` throws `NullPointerException`.
4. **Iterator invalidation in `vector`:** holding `auto& ref = v[0]` or an iterator across a `push_back` that reallocates is undefined
   behaviour — often "works" locally and fails on the judge.
5. **Java `Integer` identity:** `a == b` on two `Integer`s compares references. It happens to work for values in $[-128, 127]$ (the
   `Integer` cache — confirmed: default upper bound 127 in the OpenJDK 21 source) and silently fails above. Compare with `.equals` or unbox first.
   Classic bug: `if (map.get(x) == map.get(y))`.
6. **Java `list.remove(5)`** removes *index* 5; `list.remove(Integer.valueOf(5))` removes the value 5.
7. **Java `PriorityQueue.remove(Object)` is $O(n)$**, and its iterator is not in priority order. For deletions use a `TreeMap`/`TreeSet` or
   lazy deletion (push a "deleted" marker, skip stale tops).
8. **Java `PriorityQueue` is a min-heap; C++ `priority_queue` is a max-heap.** Port code between languages carefully.
9. **Comparator subtraction overflow:** `(a, b) -> a - b` overflows when values span more than $2^{31}$. Use `Integer.compare` /
   `Long.compare`.
10. **`vector<bool>` is a bit-packed proxy:** `auto& x = vb[i]` does not compile, `&vb[0]` is not a `bool*`, and it is slow under heavy
    random access. Use `vector<char>` unless you need the memory saving.
11. **Unsigned `size()`:** `for (int i = 0; i < v.size() - 1; ++i)` with empty `v` loops ~$2^{64}$ times. `(int)v.size() - 1`.
12. **`unordered_map` default hash** is attackable on Codeforces (hacks and uphacks happen); use the splitmix64 hash or sort.
    `reserve()` also matters for speed: rehashing a table of $10^6$ elements several times is expensive.
13. **Java `TreeSet.headSet(x).size()` is $O(n)$**, not $O(\log n)$ — the views do not store subtree sizes. For rank queries use a Fenwick tree
    over compressed values ([Fenwick tree](../08-Data-Structures/01-fenwick-tree.md)).
14. **`Arrays.asList(int[])`** gives a `List<int[]>` of one element, not a list of ints. And `Arrays.stream(int[]).sum()` is an `int`.
15. **Java strings:** `String` is immutable; `s += c` in a loop is $O(n^2)$. `substring` copies ($O(len)$) in modern JDKs. Use
    `StringBuilder` and `char[]`.
16. **`endl` vs `'\n'`, `System.out.println` vs `PrintWriter`:** output buffering is part of the container story — one buffered writer per program.

## 7. Going further (toward 2400–2600+)

- **Order statistics** (k-th element, rank) in $O(\log n)$: GNU PBDS `tree` in C++, a Fenwick/segment tree on compressed coordinates in
  both languages — [ordered sets & PBDS](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md).
- **Mergeable heaps** (leftist/pairing) and "heap with deletion" via two heaps; **small-to-large merging of sets** in
  $O(n\log^2 n)$ — [small to large](../10-Trees/03-small-to-large-and-dsu-on-tree.md).
- **Implicit treaps** as a "vector with $O(\log n)$ insert/erase/reverse in the middle" — [treaps](../08-Data-Structures/09-treaps-and-implicit-treaps.md).
- **`bitset<N>`** for 64× faster set operations on dense small universes — [bitset optimisation](../16-IGM-Frontier/05-bitset-optimization.md).
- **Custom allocators / arena memory** for millions of tree nodes, and flattening adjacency lists into CSR arrays (one `int[]` for
  all edges plus an offset array) — the standard way top Java solvers keep graphs fast.

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1621 · Distinct Numbers](https://cses.fi/problemset/task/1621)
- [ ] [CF 4C · Registration System](https://codeforces.com/problemset/problem/4/C) — 1300
- [ ] [CF 1520D · Same Differences](https://codeforces.com/problemset/problem/1520/D) — 1200
- [ ] [CSES 1084 · Apartments](https://cses.fi/problemset/task/1084)
- [ ] [CSES 1090 · Ferris Wheel](https://cses.fi/problemset/task/1090)
- [ ] [CSES 1091 · Concert Tickets](https://cses.fi/problemset/task/1091)
- [ ] [CSES 1141 · Playlist](https://cses.fi/problemset/task/1141)

**1400–1700**
- [ ] [CF 2A · Winner](https://codeforces.com/problemset/problem/2/A) — 1500
- [ ] [CSES 1073 · Towers](https://cses.fi/problemset/task/1073)
- [ ] [CSES 1163 · Traffic Lights](https://cses.fi/problemset/task/1163)
- [ ] [CSES 1164 · Room Allocation](https://cses.fi/problemset/task/1164)
- [ ] [CSES 2162 · Josephus Problem I](https://cses.fi/problemset/task/2162)
- [ ] [CF 1353D · Constructing the Array](https://codeforces.com/problemset/problem/1353/D) — 1600
- [ ] [CF 1490F · Equalize the Array](https://codeforces.com/problemset/problem/1490/F) — 1500
- [ ] [CF 1462E1 · Close Tuples (easy version)](https://codeforces.com/problemset/problem/1462/E1) — 1500

**1700+**
- [ ] [CF 1474C · Array Destruction](https://codeforces.com/problemset/problem/1474/C) — 1700
- [ ] [CSES 2163 · Josephus Problem II](https://cses.fi/problemset/task/2163)
- [ ] [CSES 1632 · Movie Festival II](https://cses.fi/problemset/task/1632)
- [ ] [CF 706D · Vasiliy's Multiset](https://codeforces.com/problemset/problem/706/D) — 1800

## 9. LeetCode / FAANG cross-reference

Interviews test exactly this layer: picking the structure and stating its costs. All of these are high-frequency patterns.

- [LC 1 · Two Sum](https://leetcode.com/problems/two-sum/) — Easy — hash map from value to index.
- [LC 217 · Contains Duplicate](https://leetcode.com/problems/contains-duplicate/) — Easy — hash set vs sort.
- [LC 242 · Valid Anagram](https://leetcode.com/problems/valid-anagram/) — Easy — 26-entry count array beats a map.
- [LC 49 · Group Anagrams](https://leetcode.com/problems/group-anagrams/) — Medium — canonical key (sorted string or count signature) into a hash map.
- [LC 347 · Top K Frequent Elements](https://leetcode.com/problems/top-k-frequent-elements/) — Medium — count map + heap of size $k$ (or bucket sort).
- [LC 215 · Kth Largest Element in an Array](https://leetcode.com/problems/kth-largest-element-in-an-array/) — Medium — size-$k$ min-heap, or quickselect.
- [LC 146 · LRU Cache](https://leetcode.com/problems/lru-cache/) — Medium — hash map + doubly linked list (`LinkedHashMap` in Java).
- [LC 380 · Insert Delete GetRandom O(1)](https://leetcode.com/problems/insert-delete-getrandom-o1/) — Medium — array + index map, swap-with-last deletion.
- [LC 706 · Design HashMap](https://leetcode.com/problems/design-hashmap/) — Easy — implement buckets yourself; discuss load factor.
- [LC 56 · Merge Intervals](https://leetcode.com/problems/merge-intervals/) — Medium — sort by start, then one scan.

## 10. Self-check

1. Which call gives "largest element $< x$" in a C++ `set` and in a Java `TreeSet`?
2. Why is `std::lower_bound` on a `std::set` slow, and what do you call instead?
3. You need a multiset in Java. What do you use, and how do you delete one copy?
4. Why doesn't XOR-ing all keys with a random constant protect a Java `HashMap` from collision attacks?
5. What is wrong with `if (map.get(a) == map.get(b))` in Java?
6. A `vector<int> v` holds 5 elements with capacity 5. You keep `int* p = &v[0]` and call `v.push_back(1)`. Is `*p` still valid?
7. Name two Java collection calls that look $O(1)$ or $O(\log n)$ but are $O(n)$.
8. Why are `pair<int,int>` heaps convenient for multi-key ordering, and how do you get "largest first, then smallest index"?

<details><summary>Answers</summary>

1. C++: `auto it = s.lower_bound(x); if (it != s.begin()) --it;` → `*it`. Java: `s.lower(x)` (returns `null` if none).
2. Set iterators are bidirectional, so the generic binary search degenerates into $O(n)$ iterator steps; use `s.lower_bound(x)`.
3. `TreeMap<value, count>`; decrement the count and `remove` the key when it reaches 0.
4. `HashMap` buckets on `h ^ (h >>> 16)` masked by the capacity; XOR by a constant $c$ maps that to `(h ^ (h>>>16)) ^ (c ^ (c>>>16))`, a fixed XOR offset, so keys that collided still collide. A non-linear mix (splitmix64) breaks the structure.
5. It compares `Integer` references; it can be false for equal values above 127 (and throws if either is `null` and auto-unboxed elsewhere).
6. No — the push reallocates (capacity was full), invalidating all pointers, references and iterators.
7. `PriorityQueue.remove(Object)`, `TreeSet.headSet(x).size()`, `ArrayList.remove(0)`, `String +=` in a loop (any two).
8. Pairs compare lexicographically. Push `(value, -index)` into a max-heap: larger value first; for equal values, larger `-index` = smaller index first.

</details>
