# Cheat sheet — Greedy, Constructive, Interactive

Revision sheet for [03-Greedy-Constructive-Interactive](../03-Greedy-Constructive-Interactive/README.md). Full derivations:
[greedy and exchange](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md) ·
[heaps and regret](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md) ·
[constructive](../03-Greedy-Constructive-Interactive/03-constructive-algorithms.md) ·
[invariants](../03-Greedy-Constructive-Interactive/04-invariants-parity-and-ad-hoc-observations.md) ·
[interactive](../03-Greedy-Constructive-Interactive/05-interactive-problems.md) ·
[problem ladder](../03-Greedy-Constructive-Interactive/problems.md).

## 1. Greedy proof toolkit

| Technique | Statement | Use when |
|---|---|---|
| Exchange argument | transform any optimum into greedy's answer without loss | choices of a set; orderings |
| Adjacent swap | if swapping an adjacent inverted pair never hurts, sorted order is optimal | "choose an order"; cost of a pair independent of the rest |
| Greedy stays ahead | after $k$ steps greedy's progress measure $\ge$ any solution's | interval scheduling, covering, jump games |
| Lower bound + construction | every solution needs $\ge X$; greedy achieves $X$ | rooms/platforms = max overlap |
| Matroid | hereditary + exchange axiom ⇒ sort by weight, add if independent | MST, XOR basis, unit jobs with deadlines |
| Brute force first | permutations / subsets for $n \le 8$ vs candidate rules | always, before proving |

## 2. Ordering keys (two-element inequality → comparator)

| Objective | Key ($i$ before $j$ iff …) | Derivation |
|---|---|---|
| $\min \sum C_i$ | $p_i \le p_j$ (SPT) | $\sum C = \sum (n-k+1) p_{(k)}$ |
| $\min \sum w_i C_i$ | $p_i w_j \le p_j w_i$ (Smith) | $\text{cost}(i,j)-\text{cost}(j,i) = w_j p_i - w_i p_j$ |
| $\min L_{\max}$ | $d_i \le d_j$ (EDF) | the pair ends at the same time; later deadline goes last |
| smallest concatenation | $a+b < b+a$ | $\text{val}(a)/(K^{\lvert a\rvert}-1)$ is a real key ⇒ transitive |
| projects $(a, b<0)$, rating $\ge a$ | $a_i + b_i \ge a_j + b_j$ | need $\max(a_i, a_j - b_i) \le \max(a_j, a_i - b_j)$ |
| projects $(a, b \ge 0)$ | $a_i \le a_j$ | do every affordable gain first |
| two machines (Johnson) | $a<b$ group by $a\uparrow$, then rest by $b\downarrow$ | pairwise rule alone is not transitive |
| pairing for max $\sum a_i b_{\sigma(i)}$ | sort both the same way | rearrangement inequality |

Comparator rules: irreflexive, asymmetric, transitive, transitive ties. Never `<=`. Cross-multiply ratios (watch
overflow and negative denominators). Java: `Integer.compare`, never `a - b`.

## 3. Interval patterns

| Task | Greedy | Complexity |
|---|---|---|
| max disjoint intervals | sort by right end, take if $l \ge$ last end | $O(n\log n)$ |
| min points stabbing all | same greedy; chosen right ends are the points | $O(n\log n)$ |
| min rooms | max overlap; events, end before start at ties (half-open) | $O(n\log n)$ |
| assign rooms explicitly | sort by start, min-heap of (end, room) | $O(n\log n)$ |
| min intervals covering $[0, L]$ | sort by $l$, extend reach maximally | $O(n\log n)$ |
| merge intervals | sort by $l$, extend current | $O(n\log n)$ |

## 4. Heap and regret patterns

| Shape | Algorithm | Invariant / why |
|---|---|---|
| unit jobs, deadline $d$, profit $w$ | sort by $d$, push $w$ to min-heap, pop if size $> d$ | matroid; evict cheapest |
| same, reverse time | for $t = T..1$: add jobs with $d \ge t$, take max | most constrained slot first |
| max # on-time jobs (lengths $p$) | Moore–Hodgson: EDF, max-heap of $p$, drop longest when late | max count, min total length |
| prefix sums $\ge 0$, max count | take all, evict most negative when sum $< 0$ | max count, then max sum |
| buy/sell one unit per day | min-heap; if top $< p$: gain $p-$top, pop, push $p$; always push $p$ | $(q-p)+(p-c) = q-c$ |
| exactly $k$ non-adjacent, max sum | max-heap + linked list; token $a_l + a_r - a_i$, delete $l, r$ | augmenting path |
| `?` → `(`/`)` with costs | default `)`, push $a-b$; on balance $<0$ flip cheapest | all flips equally fix later prefixes |
| $K$ units, convex costs | heap of marginal gains | convex ⇒ gains non-increasing |
| top-$k$ of one key while sweeping another | sort by sweep key; size-$k$ heap + running sum | LC 857, 2542, CF 1140C |
| delete from a heap | lazy deletion (second heap / counter / version) | $O(\log n)$ amortised |

Regret greedy = min-cost flow simulation; slope trick and Aliens trick exploit the same convexity.

## 5. Constructive toolkit

| Idea | Example |
|---|---|
| necessity first (parity, counting, invariant) | $u \le v$ and $v-u$ even for XOR $u$ / sum $v$ |
| brute-force explorer, read the pattern | Special Permutation: odds ↓, then 4 2, then 6 8 … |
| induction $n \to n-2$, $n \to 2n$ | Gray code reflection, beautiful array (odds then evens) |
| extremes first | exactly $k$ inversions: largest first while $k \ge m-1$ |
| spend the free choice on a global structure | $+0/+1$ ⇒ parity $(i+j) \bmod 2$ |
| orient along a total order | topological order ⇒ DAG |
| pairs that cancel | $(x, x)$ adds $2x$ to the sum, 0 to the XOR |
| complement pairs | $i \oplus (2^k-1-i) = 2^k-1$, $i \,\&\, (2^k-1-i) = 0$ |
| operation budget ⇒ one fix per operation | "at most $n$ / $2n$ / $3n$ operations" |
| DFS tree dichotomy | long path *or* many same-depth vertices |
| pigeonhole existence | prefix sums mod $n$ ⇒ subarray divisible by $n$ |
| always write a checker | test every $n \le 8$ (or all small inputs) |

Key facts: inversions $\in [0, \binom n2]$, all achievable · $1..n$ splits into equal halves iff $n \bmod 4 \in \{0,3\}$ ·
Gray $g(i) = i \oplus (i \gg 1)$ · Erdős–Szekeres: $> (r-1)(s-1)$ terms ⇒ increasing $r$ or decreasing $s$.

## 6. Invariant checklist

| Preserved quantity | Typical operation |
|---|---|
| sum / sum mod $k$ / parity | transfers, $+k$ |
| XOR of all | replace $x, y$ by $x \oplus y, 0$; add pairs |
| gcd | $a_i \leftarrow a_i - a_j$; add the same $b$ to all |
| multiset of values | swaps |
| multiset of adjacent differences | $c_i \leftarrow c_{i-1} + c_{i+1} - c_i$ (swaps $d_i, d_{i+1}$) |
| first / last / min / max | interior-only or non-extreme operations (monovariants!) |
| permutation parity | 3-cycles, even numbers of swaps |
| colour counts | dominoes, tromino colourings mod 3 |

Then: monovariant (termination, bounds) → normal form (sufficiency) → BFS on tiny cases to confirm.

Other tools: pigeonhole ($n > m$ ⇒ two equal residues) · extremal element · reverse the process · if only the multiset
matters, sort · if operations commute, count them · simulate small → closed form.

## 7. XOR and MEX formulas

| Formula | Note |
|---|---|
| $F(n) = 0 \oplus \dots \oplus n = [n, 1, n+1, 0][n \bmod 4]$ | pairs $(2k, 2k+1)$ give 1 |
| $\bigoplus_{i=l}^{r} i = F(r) \oplus F(l-1)$ | $F(-1) = 0$ |
| $a + b = (a \oplus b) + 2(a \,\&\, b)$ | ⇒ $a \oplus b \le a + b$, same parity |
| $\gcd(a_1 + x, \dots, a_n + x) = \gcd(a_1 + x, a_2 - a_1, \dots, a_n - a_1)$ | one gcd per query |
| $\text{mex}(S) \le \lvert S\rvert$ | only values $\le n$ matter |
| mex $= a$ ⇔ contains $0..a-1$, not $a$ | MEXor Mixup: $a$, $a+1$ or $a+2$ |
| after "$+x$ any number of times" only $v \bmod x$ matters | MEX maximizing |

## 8. Interactive

**Protocol:** read data → print query → **flush** → read answer → … → print answer → **flush**. Exit on `-1`. Debug to
stderr only. Reset per test case.

| Language | Flush | Read |
|---|---|---|
| C++ | `cout << ... << endl;` or `cout << flush;` / `fflush(stdout)` | `cin >> x` |
| Java | `out.println(...); out.flush();` | `BufferedReader.readLine()` + `StringTokenizer` |

| Budget | Strategy |
|---|---|
| $\lceil\log_2 n\rceil$: 10 / 17 / 18 / 20 / 30 / 60 for $10^3$ / $10^5$ / $2\cdot10^5$ / $10^6$ / $10^9$ / $10^{18}$ | exact halving |
| $\approx 2\log_2 n$ | two probes per step (local min), or two searches |
| $\log_2 n + c$ | setup queries then binary search |
| $n + c$, $\lceil 3n/2 \rceil$ | scan / tournament (min+max in $\lceil 3n/2\rceil - 2$) |
| two queries of 100 numbers | split bits between the queries |

Lower bound: $q \ge \lceil \log_k N \rceil$ for $k$-ary answers; tight against an adaptive judge (adversary keeps the larger part).
Local min invariant: $a_{lo-1} > a_{lo}$ and $a_{hi} < a_{hi+1}$.
Test: in-process judge (stress the strategy) + real interactor via a pipe runner (catch protocol bugs).

## 9. Templates

```cpp
// Activity selection (touching allowed) and minimum rooms for half-open intervals.
int maxDisjoint(vector<pair<long long, long long>> iv) {
    sort(iv.begin(), iv.end(), [](auto& a, auto& b) { return a.second < b.second; });
    long long last = LLONG_MIN; int c = 0;
    for (auto& [l, r] : iv) if (l >= last) { c++; last = r; }
    return c;
}
int minRooms(const vector<pair<long long, long long>>& iv) {
    vector<pair<long long, int>> ev;
    for (auto& [l, r] : iv) { ev.push_back({l, 1}); ev.push_back({r, -1}); }
    sort(ev.begin(), ev.end());                         // -1 before +1 at equal times
    int cur = 0, best = 0;
    for (auto& e : ev) best = max(best, cur += e.second);
    return best;
}
long long huffman(const vector<long long>& f) {
    priority_queue<long long, vector<long long>, greater<>> pq(f.begin(), f.end());
    long long cost = 0;
    while (pq.size() > 1) { long long a = pq.top(); pq.pop(); long long b = pq.top(); pq.pop(); cost += a + b; pq.push(a + b); }
    return cost;
}
long long unitJobs(vector<pair<long long, long long>> jobs) {      // (deadline, profit)
    sort(jobs.begin(), jobs.end());
    priority_queue<long long, vector<long long>, greater<>> h; long long s = 0;
    for (auto& [d, w] : jobs) { h.push(w); s += w; if ((long long)h.size() > d) { s -= h.top(); h.pop(); } }
    return s;
}
int mooreHodgson(vector<pair<long long, long long>> jobs) {        // (deadline, length)
    sort(jobs.begin(), jobs.end());
    priority_queue<long long> h; long long t = 0;
    for (auto& [d, p] : jobs) { h.push(p); t += p; if (t > d) { t -= h.top(); h.pop(); } }
    return h.size();
}
long long buyLowSellHigh(const vector<long long>& p) {
    priority_queue<long long, vector<long long>, greater<>> h; long long g = 0;
    for (long long x : p) { if (!h.empty() && h.top() < x) { g += x - h.top(); h.pop(); h.push(x); } h.push(x); }
    return g;
}
unsigned long long xorUpTo(unsigned long long n) { unsigned long long r[4] = {n, 1, n + 1, 0}; return r[n % 4]; }
int gray(int i) { return i ^ (i >> 1); }
long long ask(long long i) {                                       // interactive query
    cout << "? " << i << endl;
    long long r; if (!(cin >> r) || r == -1) exit(0);
    return r;
}
```

```java
static int maxDisjoint(long[][] iv) {
    long[][] a = iv.clone();
    Arrays.sort(a, (x, y) -> Long.compare(x[1], y[1]));
    long last = Long.MIN_VALUE; int c = 0;
    for (long[] p : a) if (p[0] >= last) { c++; last = p[1]; }
    return c;
}
static int minRooms(long[][] iv) {                                 // non-negative times
    long[] ev = new long[2 * iv.length];
    for (int i = 0; i < iv.length; i++) { ev[2 * i] = iv[i][0] * 2 + 1; ev[2 * i + 1] = iv[i][1] * 2; }
    Arrays.sort(ev);                                               // end (even) before start (odd) at equal time
    int cur = 0, best = 0;
    for (long e : ev) { cur += (e & 1) == 1 ? 1 : -1; best = Math.max(best, cur); }
    return best;
}
static long huffman(long[] f) {
    PriorityQueue<Long> pq = new PriorityQueue<>();
    for (long x : f) pq.add(x);
    long cost = 0;
    while (pq.size() > 1) { long a = pq.poll(), b = pq.poll(); cost += a + b; pq.add(a + b); }
    return cost;
}
static long unitJobs(long[][] jobs) {                              // {deadline, profit}
    long[][] a = jobs.clone();
    Arrays.sort(a, (x, y) -> Long.compare(x[0], y[0]));
    PriorityQueue<Long> h = new PriorityQueue<>(); long s = 0;
    for (long[] j : a) { h.add(j[1]); s += j[1]; if (h.size() > j[0]) s -= h.poll(); }
    return s;
}
static int mooreHodgson(long[][] jobs) {                           // {deadline, length}
    long[][] a = jobs.clone();
    Arrays.sort(a, (x, y) -> Long.compare(x[0], y[0]));
    PriorityQueue<Long> h = new PriorityQueue<>(Comparator.reverseOrder()); long t = 0;
    for (long[] j : a) { h.add(j[1]); t += j[1]; if (t > j[0]) t -= h.poll(); }
    return h.size();
}
static long buyLowSellHigh(long[] p) {
    PriorityQueue<Long> h = new PriorityQueue<>(); long g = 0;
    for (long x : p) { if (!h.isEmpty() && h.peek() < x) { g += x - h.poll(); h.add(x); } h.add(x); }
    return g;
}
static long xorUpTo(long n) { long[] r = {n, 1, n + 1, 0}; return r[(int) (n % 4)]; }
static int gray(int i) { return i ^ (i >> 1); }
static final BufferedReader BR = new BufferedReader(new InputStreamReader(System.in));
static final PrintWriter OUT = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
static long ask(long i) throws IOException {                       // interactive query (one number per line)
    OUT.println("? " + i); OUT.flush();
    String line = BR.readLine();
    if (line == null) System.exit(0);
    long r = Long.parseLong(line.trim());
    if (r == -1) System.exit(0);
    return r;
}
```

## 10. Top 10 mistakes

1. Submitting a greedy without a brute-force comparison on small cases.
2. Comparator with `<=`, or a non-transitive key (ratio with floating point, mixed-sign denominators, Johnson's raw rule).
3. Java `Arrays.sort(int[])` / `long[]` on adversarial input without shuffling; `(a, b) -> a - b` overflow.
4. Wrong heap direction (`priority_queue` is max, `PriorityQueue` is min); boxed `Long` compared with `==`.
5. Regret token at the wrong price or missing border sentinels (overflowing $-\infty$).
6. Invariant found, sufficiency not proven — "Yes iff invariant" fails on a case the BFS would have shown.
7. Constructive: printing −1 for a solvable small $n$ ($n = 1, 2, 3$ special cases), or not resetting per-test arrays.
8. Unbuffered output of $10^6$ numbers (`endl`, `System.out.println` per element).
9. Interactive: missing flush (Idleness limit), not exiting on −1, off-by-one in the query budget, debug prints on stdout.
10. `%` on negative numbers in parity/residue invariants (use `& 1` or `((x % m) + m) % m`).

## 11. Last-minute before contest

- [ ] Brute-force template ready (permutations / subsets / BFS over tiny states) and a stress script.
- [ ] Checker skeleton for constructive problems.
- [ ] Interactive template with `endl`/`flush`, −1 handling, and a local judge stub.
- [ ] For each greedy: write the two-element inequality; check the tie case.
- [ ] For each operation problem: go through the invariant table (sum, parity, XOR, gcd, multiset, differences, extremes).
- [ ] Read the output format twice: `YES`/`NO` case, length line, −1, 1-indexing, multiple test cases.
- [ ] Use 64-bit for sums, completion times and costs.
