# Greedy with heaps and regret ("take now, undo later")

> **Band:** 🔵–🔴 1400–2600 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [greedy and exchange arguments](01-greedy-and-exchange-arguments.md), [heaps and ordered sets](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md)
> **You can say you know this when:** you can turn "choose a subset subject to a prefix constraint" into a heap greedy that evicts the worst element, design a regret token that lets a greedy decision be reversed later at the right price (Buy Low Sell High, bracket repair, non-adjacent picks), and use lazy deletion without thinking.

## 1. First principles — why this works

Plain greedy commits to decisions in a fixed order. Many problems are scanned in a fixed order (time, position), but
the value of a decision only becomes clear later. Three standard fixes keep the greedy linear-ish while allowing
second thoughts.

### Fix A — keep the chosen set in a heap and evict the worst ("replace the worst so far")

Setting: items arrive in some order; the chosen set must satisfy a **prefix constraint** (after each prefix, the number
of chosen items is at most a capacity, or a running sum stays non-negative), and you maximise count or total value.

Algorithm: tentatively take every item; whenever the constraint breaks, remove the chosen item that hurts the
objective most (cheapest profit, most negative value, longest duration) — it is on top of a heap.

*Why it is safe (stays ahead).* Claim: after processing each prefix, the greedy's set has the maximum possible size
(or value), and among such sets it has the best "slack" (most capacity left / largest running sum). When the
constraint breaks, **every** feasible solution must omit at least one of the items seen so far relative to "take
everything"; omitting the one with the least value (or most damage) dominates any other single omission, and by the
induction hypothesis one omission suffices to restore feasibility. Unit-time jobs with deadlines are the cleanest
case — their feasible sets form a matroid (§2.1), so "sort, add, evict the minimum" is exactly the matroid greedy.

### Fix B — regret tokens (push an "undo" option into the heap)

When the greedy takes an action, it also pushes a **virtual option** whose later selection means "partially undo the
earlier action, at the correct marginal price". The greedy then never backtracks explicitly; it just keeps picking the
best option on the heap, and some of those options are corrections.

The canonical identity, from stock trading: buying at $p_i$, selling at $p_j$, and later "selling the same share again" at
$p_k$ telescopes:
$$(p_j - p_i) + (p_k - p_j) = p_k - p_i .$$
So after selling at $p_j$ we push $p_j$ back as if it were a purchase price: picking it later converts the trade
$i \to j$ into $i \to k$, and day $j$ becomes free again. That is CF 865D (Example 5).

*Why regret greedy is correct.* It is a hand-simulated **min-cost flow**: every greedy pick is a shortest augmenting
path, and every regret token is a reverse (residual) edge with negated cost. Successive shortest paths is optimal, and
for these special graphs the shortest path is the top of a heap. In a contest, you rarely re-derive the flow — you
design the token from the telescoping identity and stress-test against a brute force.

### Fix C — marginal gains with a heap (convex allocation)

Distribute $K$ identical units among items, item $i$ receiving $x_i \ge$ some minimum, to minimise $\sum f_i(x_i)$ where
each $f_i$ is **convex** (its marginal decrease $f_i(x) - f_i(x+1)$ is non-increasing in $x$). Greedy: give each next
unit to the item with the largest current marginal decrease (heap). Exchange proof: in any allocation where the next
unit of item $i$ would gain more than the last unit given to item $j$, moving that unit from $j$ to $i$ does not hurt;
convexity guarantees the multiset of chosen marginal gains is the $K$ largest available, because each item's gains are
consumed in decreasing order. Carrots for Rabbits (Example 3) is the model; so are "assign workers to queues",
"minimise sum of squares after $k$ decrements", and "maximise sum of $\lfloor$ ratios $\rfloor$".

### Lazy deletion

`priority_queue` / `PriorityQueue` cannot delete an arbitrary element efficiently (`PriorityQueue.remove(Object)` is
$O(n)$). Keep a record of deletions instead (a second heap of deleted values, a counter map, or a per-id version
stamp) and **discard stale entries only when they reach the top**. Each entry is pushed and popped once, so the
amortised cost stays $O(\log n)$. The same trick lets you "update a key": push the new version and ignore old ones
(this is exactly how Dijkstra with a binary heap works).

## 2. Formulas, definitions and identities

### 2.1 Unit jobs with deadlines and profits

$n$ jobs, each takes one time slot, job $i$ has deadline $d_i$ (must occupy a slot $\le d_i$) and profit $w_i$. A set $S$
can be scheduled iff (Hall's condition on slots)
$$\forall t:\quad |\{ i \in S : d_i \le t \}| \le t .$$
These sets form a matroid (a transversal matroid), so the optimum is greedy. Two equivalent implementations,
both $O(n \log n)$:

- **Forward, evict the minimum:** sort by $d$; push $w_i$ into a min-heap; if heap size $> d_i$, pop the minimum.
  Answer = sum of the heap.
- **Backward, take the maximum:** for $t = T, T-1, \dots, 1$, add all jobs with $d_i \ge t$ that are not yet available, pop
  the maximum into slot $t$. (Latest slots are the most constrained, so fill them first.)

### 2.2 Moore–Hodgson (maximise the number of on-time jobs, arbitrary lengths)

Sort by deadline. Add job $i$ to a max-heap of lengths, $T \mathrel{+}= p_i$; if $T > d_i$, pop the longest job, $T \mathrel{-}= p_{\max}$.
The heap size at the end is the answer (LC 630 "Course Schedule III" is literally this). Invariant: the kept set is a
maximum on-time subset of the prefix with the **minimum total length**.

### 2.3 Prefix-sum constraint (Potions pattern)

Choose a subsequence of $a_1..a_n$ maximising its size so that every prefix sum of the chosen subsequence is $\ge 0$:
take each $a_i$; if the running sum drops below 0, remove the most negative chosen element. Invariant: maximum size,
and among maximum-size choices, maximum running sum.

### 2.4 Regret identities

| Problem shape | Action | Regret token pushed | Meaning of picking the token |
|---|---|---|---|
| buy/sell one unit per day | sell today at $p$ against cheapest $c$ | price $p$ (extra copy) | "resell" that share later at $q$: total $q - c$ |
| choose $k$ non-adjacent elements | take $a_i$ (neighbours $l, r$) | $a_l + a_r - a_i$ at $i$, delete $l, r$ | swap $i$ out, take both neighbours |
| bracket repair with costs | set `?` to `)` (cost $b$) | $a - b$ | flip that `?` to `(` |
| assignment with two kinds | assign to kind 1 | (gain2 − gain1) | move the item to kind 2 |

### 2.5 Convex allocation

For a carrot of length $a$ split into $p$ positive integer pieces, the minimum sum of squares uses pieces as equal as
possible: with $q = \lfloor a/p \rfloor$, $r = a \bmod p$,
$$f(a, p) = r (q+1)^2 + (p - r) q^2 .$$
The marginal gain $g(a,p) = f(a,p) - f(a,p+1)$ is non-increasing in $p$ (convexity of $x \mapsto x^2$ lifts to $f$),
which is exactly the condition for Fix C. Heap greedy over $K$ steps: $O((n + K) \log n)$.

### 2.6 Complexities

| Operation | Binary heap | Notes |
|---|---|---|
| push / pop / top | $O(\log n)$ / $O(\log n)$ / $O(1)$ | `std::priority_queue` is a max-heap; `PriorityQueue` is a min-heap |
| build from $n$ items | $O(n)$ | constructor from a range / `new PriorityQueue<>(collection)` |
| delete arbitrary (lazy) | $O(\log n)$ amortised | stale entries skipped at the top |
| delete arbitrary (`multiset` / `TreeMap`) | $O(\log n)$ | use when you also need min *and* max, or k-th via order statistics |

## 3. Implementation (C++ and Java)

### 3.1 Heap with lazy deletion, and "replace the worst" schedulers

```cpp
// Max-heap supporting erase(x) for values that are currently present.
struct LazyHeap {
    priority_queue<long long> live, dead;
    void push(long long x) { live.push(x); }
    void erase(long long x) { dead.push(x); }
    void clean() { while (!dead.empty() && live.top() == dead.top()) { live.pop(); dead.pop(); } }
    long long top() { clean(); return live.top(); }
    void pop() { clean(); live.pop(); }
    size_t size() const { return live.size() - dead.size(); }
};
// Unit jobs (deadline d >= 1, profit w): maximum total profit.
long long maxProfitUnitJobs(vector<pair<long long, long long>> jobs) {  // (deadline, profit)
    sort(jobs.begin(), jobs.end());
    priority_queue<long long, vector<long long>, greater<long long>> chosen;
    long long sum = 0;
    for (auto& [d, w] : jobs) {
        chosen.push(w); sum += w;
        if ((long long)chosen.size() > d) { sum -= chosen.top(); chosen.pop(); }   // evict the cheapest
    }
    return sum;
}
// Moore-Hodgson: maximum number of jobs (length p, deadline d) finished on time.
int maxOnTime(vector<pair<long long, long long>> jobs) {  // (deadline, length)
    sort(jobs.begin(), jobs.end());
    priority_queue<long long> lens;
    long long t = 0;
    for (auto& [d, p] : jobs) {
        lens.push(p); t += p;
        if (t > d) { t -= lens.top(); lens.pop(); }   // drop the longest job kept so far
    }
    return lens.size();
}
```

```java
static class LazyHeap {                    // max-heap with erase(x) for present values
    PriorityQueue<Long> live = new PriorityQueue<>(Comparator.reverseOrder());
    PriorityQueue<Long> dead = new PriorityQueue<>(Comparator.reverseOrder());
    void push(long x) { live.add(x); }
    void erase(long x) { dead.add(x); }
    private void clean() { while (!dead.isEmpty() && live.peek().equals(dead.peek())) { live.poll(); dead.poll(); } }
    long top() { clean(); return live.peek(); }
    void pop() { clean(); live.poll(); }
    int size() { return live.size() - dead.size(); }
}
static long maxProfitUnitJobs(long[][] jobs) {     // jobs[i] = {deadline, profit}
    long[][] a = jobs.clone();
    Arrays.sort(a, (x, y) -> Long.compare(x[0], y[0]));
    PriorityQueue<Long> chosen = new PriorityQueue<>();
    long sum = 0;
    for (long[] j : a) {
        chosen.add(j[1]); sum += j[1];
        if (chosen.size() > j[0]) sum -= chosen.poll();
    }
    return sum;
}
static int maxOnTime(long[][] jobs) {               // jobs[i] = {deadline, length}
    long[][] a = jobs.clone();
    Arrays.sort(a, (x, y) -> Long.compare(x[0], y[0]));
    PriorityQueue<Long> lens = new PriorityQueue<>(Comparator.reverseOrder());
    long t = 0;
    for (long[] j : a) {
        lens.add(j[1]); t += j[1];
        if (t > j[0]) t -= lens.poll();
    }
    return lens.size();
}
```

`live.peek().equals(dead.peek())` — never compare boxed `Long` with `==` (identity, false outside the cache $[-128, 127]$).

### 3.2 Regret on a linked list: choose exactly $k$ non-adjacent elements with maximum sum

```cpp
// a[0..n-1], 1 <= k <= (n+1)/2. Returns the maximum sum of k pairwise non-adjacent elements.
long long kNonAdjacent(vector<long long> a, int k) {
    const long long NEG = LLONG_MIN / 4;
    int n = a.size();
    vector<long long> val(n + 2, NEG);           // 1-based with sentinels 0 and n+1 worth -infinity
    vector<int> L(n + 2), R(n + 2);
    vector<char> gone(n + 2, 0);
    for (int i = 1; i <= n; i++) val[i] = a[i - 1];
    for (int i = 0; i <= n + 1; i++) { L[i] = i - 1; R[i] = i + 1; }
    priority_queue<pair<long long, int>> pq;
    for (int i = 1; i <= n; i++) pq.push({val[i], i});
    long long ans = 0;
    while (k--) {
        while (gone[pq.top().second] || pq.top().first != val[pq.top().second]) pq.pop();   // lazy deletion
        auto [v, i] = pq.top(); pq.pop();
        ans += v;
        int l = L[i], r = R[i];
        long long nv = (val[l] <= NEG / 2 || val[r] <= NEG / 2) ? NEG : val[l] + val[r] - val[i];
        val[i] = nv;                               // regret token: "drop i, take both neighbours"
        if (l >= 1) { gone[l] = 1; L[i] = L[l]; R[L[l]] = i; }   // splice out l
        if (r <= n) { gone[r] = 1; R[i] = R[r]; L[R[r]] = i; }   // splice out r
        if (l < 1 || r > n) val[i] = NEG;          // at a border the token can never be useful
        pq.push({val[i], i});
    }
    return ans;
}
```

```java
static long kNonAdjacent(long[] a, int k) {
    final long NEG = Long.MIN_VALUE / 4;
    int n = a.length;
    long[] val = new long[n + 2];
    int[] L = new int[n + 2], R = new int[n + 2];
    boolean[] gone = new boolean[n + 2];
    val[0] = val[n + 1] = NEG;
    for (int i = 1; i <= n; i++) val[i] = a[i - 1];
    for (int i = 0; i <= n + 1; i++) { L[i] = i - 1; R[i] = i + 1; }
    PriorityQueue<long[]> pq = new PriorityQueue<>((x, y) -> Long.compare(y[0], x[0]));
    for (int i = 1; i <= n; i++) pq.add(new long[]{val[i], i});
    long ans = 0;
    while (k-- > 0) {
        while (gone[(int) pq.peek()[1]] || pq.peek()[0] != val[(int) pq.peek()[1]]) pq.poll();
        long[] top = pq.poll();
        int i = (int) top[1];
        ans += top[0];
        int l = L[i], r = R[i];
        val[i] = (val[l] <= NEG / 2 || val[r] <= NEG / 2) ? NEG : val[l] + val[r] - val[i];
        if (l >= 1) { gone[l] = true; L[i] = L[l]; R[L[l]] = i; }
        if (r <= n) { gone[r] = true; R[i] = R[r]; L[R[r]] = i; }
        if (l < 1 || r > n) val[i] = NEG;
        pq.add(new long[]{val[i], i});
    }
    return ans;
}
```

Why it works: taking $a_i$ and later its token $a_l + a_r - a_i$ yields $a_l + a_r$ with $i$ dropped — exactly the
augmenting path that swaps one chosen element for its two neighbours. Merged nodes behave like single elements, so the
argument recurses. Stress-tested against an $O(nk)$ DP in Example 4.

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "each task takes one day, deadline, profit" / "reward arrives $A_i$ days later" | unit jobs with deadlines: sort + min-heap eviction, or reverse-time max-heap |
| "keep the running total non-negative, maximise how many you take" | take everything, evict most negative (Fix A) |
| "maximise number of courses / tasks finished before their deadlines" | Moore–Hodgson (evict longest) |
| "maximise profit trading one unit per step", "each day buy or sell one" | regret token: push the sell price back |
| "choose $k$ items, no two adjacent" / "$k$ disjoint segments" / "$k$ pairs of neighbours" | linked-list regret ($a_l + a_r - a_i$) |
| "replace each `?` by one of two options with costs; validity is a prefix condition" | default to the cheap option, regret-flip the cheapest correction when invalid |
| "distribute $K$ units / cuts / workers to minimise a sum of convex costs" | marginal-gain heap |
| "top $k$ by one key while sweeping another key" (Playlist, LC 857, LC 2542) | sort by the sweep key, keep a size-$k$ heap of the other with its sum |
| "remove arbitrary elements from a priority queue" | lazy deletion or `multiset`/`TreeMap` |

**Commonly confused with:** DP over (position, count) — correct but $O(nk)$; the heap greedy is the "fast" version when
the DP value is concave in the count (that concavity is also what [Aliens trick](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md)
and [slope trick](../07-DP-Optimizations/07-slope-trick.md) exploit — regret greedy and slope trick are two views of the same convexity).

## 5. Worked examples (graded)

### Example 1 — Summer Vacation  ·  ★ ≈1300

- **Source:** [AtCoder ABC137 D · Summer Vacation](https://atcoder.jp/contests/abc137/tasks/abc137_d)
- **Difficulty:** ≈1300 (est.; AtCoder difficulty ≈1313)
- **Problem:** $N \le 10^5$ one-day jobs; doing job $i$ on some day pays $B_i$ exactly $A_i$ days later. At most one job
  per day starting today; each job at most once. Maximise the total reward received within $M \le 10^5$ days (a job done
  on day $t$, counting from 0, pays in time iff $t + A_i \le M$).
- **Thinking from first principles:** job $i$ must be done on a day $\le M - A_i$, so it is a unit job with deadline
  $M - A_i + 1$ slots. Brute force over assignments is hopeless; the matroid structure (§2.1) says greedy works. The
  reverse-time form is the cleanest to code: the day with $k$ days remaining can host exactly the jobs with
  $A_i \le k$; fill the most constrained day first ($k = 1$), each time with the best available job.

<details><summary>Solution</summary>

For $k = 1..M$: add all jobs with $A_i = k$ to a max-heap; if the heap is non-empty, pop its maximum into the answer.
Exchange argument: the day with $k$ days left accepts a superset of the jobs acceptable at $k-1$, so giving the best
currently eligible job to the more constrained day is never worse. $O((N + M) \log N)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<vector<int>> byDelay(m + 1);
    for (int i = 0; i < n; i++) {
        int a, b; cin >> a >> b;
        if (a <= m) byDelay[a].push_back(b);
    }
    priority_queue<int> pq;
    long long ans = 0;
    for (int k = 1; k <= m; k++) {
        for (int b : byDelay[k]) pq.push(b);
        if (!pq.empty()) { ans += pq.top(); pq.pop(); }
    }
    cout << ans << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        List<List<Integer>> byDelay = new ArrayList<>();
        for (int i = 0; i <= m; i++) byDelay.add(new ArrayList<>());
        for (int i = 0; i < n; i++) {
            int a = in.nextInt(), b = in.nextInt();
            if (a <= m) byDelay.get(a).add(b);
        }
        PriorityQueue<Integer> pq = new PriorityQueue<>(Comparator.reverseOrder());
        long ans = 0;
        for (int k = 1; k <= m; k++) {
            pq.addAll(byDelay.get(k));
            if (!pq.isEmpty()) ans += pq.poll();
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
3 4
4 3
4 1
2 2
out:
5
-->
<!-- test
in:
1 1
2 10
out:
0
-->
<!-- test
in:
5 3
1 2
1 3
1 4
2 1
3 5
out:
12
-->

</details>

### Example 2 — Potions (Hard Version)  ·  ★ 1600

- **Source:** [CF 1526C2 · Potions (Hard Version)](https://codeforces.com/problemset/problem/1526/C2) — 1600
- **Difficulty:** 1600
- **Problem:** $n \le 2 \cdot 10^5$ potions in a row with effects $a_i$ ($|a_i| \le 10^9$). Walking left to right with health
  starting at 0, you may drink each potion (health $\mathrel{+}= a_i$); health must never be negative. Maximise the number
  of potions drunk.
- **Thinking from first principles:** the easy version ($n \le 2000$) is a DP over (position, count) storing the best
  health. Look at what the DP keeps: for each count, the maximum health — and the transitions only ever drop the worst
  potion. So: drink everything; when health goes negative, "un-drink" the most harmful potion so far. It restores
  feasibility (the removed value is $\le$ the current one, which made health negative), keeps the count as large as
  possible, and leaves the most health for the future.

<details><summary>Solution</summary>

Min-heap of drunk potions; push $a_i$, add to health; while health $< 0$, pop the minimum and subtract it. The heap
size is the answer. Invariant: maximum count for the prefix, and maximum health among maximum-count choices.
$O(n \log n)$; health needs 64 bits.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    priority_queue<long long, vector<long long>, greater<long long>> drunk;
    long long health = 0;
    for (int i = 0; i < n; i++) {
        long long a; cin >> a;
        drunk.push(a); health += a;
        if (health < 0) { health -= drunk.top(); drunk.pop(); }   // one removal always suffices
    }
    cout << drunk.size() << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        PriorityQueue<Long> drunk = new PriorityQueue<>();
        long health = 0;
        for (int i = 0; i < n; i++) {
            long a = in.nextLong();
            drunk.add(a); health += a;
            if (health < 0) health -= drunk.poll();
        }
        System.out.println(drunk.size());
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
5
-1 2 -3 -1 4
out:
3
-->
<!-- test
in:
1
-5
out:
0
-->
<!-- test
in:
3
0 0 0
out:
3
-->

</details>

### Example 3 — Carrots for Rabbits  ·  ★ 2200

- **Source:** [CF 1428E · Carrots for Rabbits](https://codeforces.com/problemset/problem/1428/E) — 2200
- **Difficulty:** 2200
- **Problem:** $n$ carrots of lengths $a_i \le 10^6$ must be cut into exactly $k$ pieces of positive integer length in total
  ($n \le k \le 10^5$, $\sum a_i \ge k$). A piece of length $x$ costs $x^2$. Minimise the total cost.
- **Thinking from first principles:** two separate decisions: how many pieces each carrot gets ($p_i$, with
  $\sum p_i = k$), and how to cut a carrot into $p$ pieces. The second is easy — as equal as possible (sum of squares
  with fixed sum is minimised by balancing; an exchange of one unit between two pieces differing by $\ge 2$ helps).
  For the first, $f(a,p)$ is convex in $p$ (§2.5), so hand out the $k-n$ extra cuts one by one to the carrot whose next
  cut saves the most.

<details><summary>Solution</summary>

Start with $p_i = 1$ and cost $\sum a_i^2$. Max-heap of $g(a_i, p_i) = f(a_i,p_i) - f(a_i,p_i+1)$. Repeat $k-n$ times: pop the
best, subtract the gain, increment $p_i$, push the new gain. Convexity makes the greedy optimal (Fix C).
$O(k \log n)$; costs up to $10^{5} \cdot 10^{12}$ need 64 bits.

```cpp
#include <bits/stdc++.h>
using namespace std;
long long f(long long a, long long p) {   // min sum of squares splitting a into p parts
    long long q = a / p, r = a % p;
    return r * (q + 1) * (q + 1) + (p - r) * q * q;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k; cin >> n >> k;
    vector<long long> a(n);
    vector<long long> parts(n, 1);
    long long cost = 0;
    priority_queue<pair<long long, int>> pq;              // (gain of one more cut, carrot)
    for (int i = 0; i < n; i++) {
        cin >> a[i];
        cost += a[i] * a[i];
        if (a[i] > 1) pq.push({f(a[i], 1) - f(a[i], 2), i});
    }
    for (int step = 0; step < k - n; step++) {
        auto [g, i] = pq.top(); pq.pop();
        cost -= g;
        parts[i]++;
        if (parts[i] < a[i]) pq.push({f(a[i], parts[i]) - f(a[i], parts[i] + 1), i});
    }
    cout << cost << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static long f(long a, long p) {
        long q = a / p, r = a % p;
        return r * (q + 1) * (q + 1) + (p - r) * q * q;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt();
        long[] a = new long[n], parts = new long[n];
        long cost = 0;
        PriorityQueue<long[]> pq = new PriorityQueue<>((x, y) -> Long.compare(y[0], x[0]));
        for (int i = 0; i < n; i++) {
            a[i] = in.nextLong(); parts[i] = 1;
            cost += a[i] * a[i];
            if (a[i] > 1) pq.add(new long[]{f(a[i], 1) - f(a[i], 2), i});
        }
        for (int step = 0; step < k - n; step++) {
            long[] t = pq.poll();
            int i = (int) t[1];
            cost -= t[0];
            parts[i]++;
            if (parts[i] < a[i]) pq.add(new long[]{f(a[i], parts[i]) - f(a[i], parts[i] + 1), i});
        }
        System.out.println(cost);
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
1 4
10
out:
26
-->
<!-- test
in:
2 2
7 1
out:
50
-->
<!-- test
in:
2 5
6 4
out:
20
-->

</details>

### Example 4 — Exactly $k$ non-adjacent elements  ·  ★ ≈2200 (est.)

- **Source:** Original problem (the core of [CF 958E2 · Guard Duty (medium)](https://codeforces.com/problemset/problem/958/E2) — 2200, after sorting the times and taking adjacent gaps).
- **Difficulty:** ≈2200 (est.)
- **Problem:** array $a_1..a_n$ ($n \le 2 \cdot 10^5$, $|a_i| \le 10^9$) and $1 \le k \le \lceil n/2 \rceil$. Choose exactly $k$ indices, no
  two adjacent, maximising the sum.
- **Thinking from first principles:** the DP $dp[i][j]$ is $O(nk)$ — too slow for $k \sim n/2$. Greedy "take the
  maximum, delete its neighbours" fails on $[9, 10, 9]$ with $k = 2$ (takes 10, stuck; optimum $9+9$). The fix is to make
  the greedy's mistake *reversible*: after taking 10, offer the option "worth $9 + 9 - 10 = 8$" in its place, meaning
  "give back 10, take both neighbours". The merged node is again a single element of a shorter list, so the same rule
  applies recursively.

<details><summary>Solution</summary>

The routine `kNonAdjacent` from §3.2, wrapped in I/O. Each round: pop the maximum valid node $i$ (lazy deletion), add it,
replace its value by $a_l + a_r - a_i$, and splice out $l$ and $r$. At the borders the token is $-\infty$ (there is no
second neighbour to take). $O((n + k) \log n)$. Correctness follows from the min-cost-flow view (each token is a residual
path) and was stress-tested against the DP.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k; cin >> n >> k;
    const long long NEG = LLONG_MIN / 4;
    vector<long long> val(n + 2, NEG);
    vector<int> L(n + 2), R(n + 2);
    vector<char> gone(n + 2, 0);
    for (int i = 1; i <= n; i++) cin >> val[i];
    for (int i = 0; i <= n + 1; i++) { L[i] = i - 1; R[i] = i + 1; }
    priority_queue<pair<long long, int>> pq;
    for (int i = 1; i <= n; i++) pq.push({val[i], i});
    long long ans = 0;
    while (k--) {
        while (gone[pq.top().second] || pq.top().first != val[pq.top().second]) pq.pop();
        auto [v, i] = pq.top(); pq.pop();
        ans += v;
        int l = L[i], r = R[i];
        val[i] = (val[l] <= NEG / 2 || val[r] <= NEG / 2) ? NEG : val[l] + val[r] - val[i];
        if (l >= 1) { gone[l] = 1; L[i] = L[l]; R[L[l]] = i; }
        if (r <= n) { gone[r] = 1; R[i] = R[r]; L[R[r]] = i; }
        if (l < 1 || r > n) val[i] = NEG;
        pq.push({val[i], i});
    }
    cout << ans << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt();
        final long NEG = Long.MIN_VALUE / 4;
        long[] val = new long[n + 2];
        int[] L = new int[n + 2], R = new int[n + 2];
        boolean[] gone = new boolean[n + 2];
        val[0] = val[n + 1] = NEG;
        for (int i = 1; i <= n; i++) val[i] = in.nextLong();
        for (int i = 0; i <= n + 1; i++) { L[i] = i - 1; R[i] = i + 1; }
        PriorityQueue<long[]> pq = new PriorityQueue<>((x, y) -> Long.compare(y[0], x[0]));
        for (int i = 1; i <= n; i++) pq.add(new long[]{val[i], i});
        long ans = 0;
        while (k-- > 0) {
            while (gone[(int) pq.peek()[1]] || pq.peek()[0] != val[(int) pq.peek()[1]]) pq.poll();
            long[] top = pq.poll();
            int i = (int) top[1];
            ans += top[0];
            int l = L[i], r = R[i];
            val[i] = (val[l] <= NEG / 2 || val[r] <= NEG / 2) ? NEG : val[l] + val[r] - val[i];
            if (l >= 1) { gone[l] = true; L[i] = L[l]; R[L[l]] = i; }
            if (r <= n) { gone[r] = true; R[i] = R[r]; L[R[r]] = i; }
            if (l < 1 || r > n) val[i] = NEG;
            pq.add(new long[]{val[i], i});
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
3 2
9 10 9
out:
18
-->
<!-- test
in:
1 1
-7
out:
-7
-->
<!-- test
in:
4 2
1 9 10 1
out:
11
-->
<!-- test
in:
5 2
3 5 4 1 2
out:
7
-->

</details>

### Example 5 — Buy Low Sell High  ·  ★ 2400

- **Source:** [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400
- **Difficulty:** 2400
- **Problem:** prices $p_1..p_n$ ($n \le 3 \cdot 10^5$, $p_i \le 10^6$) for one stock. Each day you may buy one share, sell one
  share (if you own one), or do nothing. You start and must end with zero shares. Maximise the profit.
- **Thinking from first principles:** an $O(n^2)$ DP over (day, shares held) is easy and too slow. Greedy attempt: on
  each day, sell against the cheapest earlier unused day if that is profitable. It fails on $1, 2, 10$: on day 2 it sells
  against day 1 (+1), and on day 10 no unused earlier day is left, so it ends with 1. The optimum is $10 - 1 = 9$: day 2
  should have stayed idle. The fix is the telescoping identity (§1, Fix B): after selling at 2 against 1, push 2 back
  into the heap as a "purchase". On day 10 the heap top is that 2, and selling against it adds $10 - 2$, turning the
  trade into $1 \to 10$ with day 2 idle — total 9.

<details><summary>Solution</summary>

Min-heap of candidate purchase prices. For each price $p$: if the heap's minimum $c < p$, gain $p - c$, pop it, and push
$p$ (the regret token); in every case push $p$ (today as a potential purchase). Each day ends up either idle, a buy, or a
sell; the token makes "sold today" convertible to "idle today, sold later". $O(n \log n)$. The same answer comes out of
slope trick on the concave DP, see [slope trick](../07-DP-Optimizations/07-slope-trick.md).

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    priority_queue<long long, vector<long long>, greater<long long>> pq;
    long long profit = 0;
    for (int i = 0; i < n; i++) {
        long long p; cin >> p;
        if (!pq.empty() && pq.top() < p) {
            profit += p - pq.top(); pq.pop();
            pq.push(p);               // regret token: selling today can be postponed to a later day
        }
        pq.push(p);                   // today as a possible purchase
    }
    cout << profit << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        PriorityQueue<Long> pq = new PriorityQueue<>();
        long profit = 0;
        for (int i = 0; i < n; i++) {
            long p = in.nextLong();
            if (!pq.isEmpty() && pq.peek() < p) {
                profit += p - pq.poll();
                pq.add(p);
            }
            pq.add(p);
        }
        System.out.println(profit);
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
5
1 2 3 4 5
out:
6
-->
<!-- test
in:
1
7
out:
0
-->
<!-- test
in:
3
1 2 10
out:
9
-->
<!-- test
in:
4
3 1 4 2
out:
3
-->

</details>

### Example 6 — Least Cost Bracket Sequence  ·  ★ 2600

- **Source:** [CF 3D · Least Cost Bracket Sequence](https://codeforces.com/problemset/problem/3/D) — 2600
- **Difficulty:** 2600
- **Problem:** a pattern of length $\le 5 \cdot 10^4$ over `(`, `)`, `?`. The $i$-th `?` costs $a_i$ to turn into `(` and $b_i$ to
  turn into `)` ($1 \le a_i, b_i \le 10^6$). Produce a regular bracket sequence of minimum total cost (print the cost and the
  sequence), or `-1`.
- **Thinking from first principles:** validity is a prefix condition: balance $\ge 0$ everywhere, 0 at the end. Default
  every `?` to `)` (paying $b_i$) and repair only when forced: when the balance goes negative, *some* earlier `?` must
  become `(`; flipping `?` $i$ changes the cost by $a_i - b_i$ and the balance of every later prefix by $+2$. Any earlier
  `?` repairs the current prefix equally well, so pick the cheapest flip — and since later prefixes benefit equally from
  any flip, choosing the cheapest now never blocks a future repair. That is Fix A with "evict" meaning "flip".

<details><summary>Solution</summary>

Scan; on `?` choose `)`, add $b_i$, push $(a_i - b_i, \text{position})$ into a min-heap. Whenever the balance becomes $-1$, pop
the cheapest flip (if none, answer `-1`), add its delta, set that position to `(`, balance $\mathrel{+}= 2$. At the end require
balance $= 0$. $O(n \log n)$. Total cost up to $5 \cdot 10^4 \cdot 10^6$ — 64 bits.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    priority_queue<pair<long long, int>, vector<pair<long long, int>>, greater<>> flips;   // (a-b, position)
    long long cost = 0; int bal = 0;
    for (int i = 0; i < (int)s.size(); i++) {
        if (s[i] == '(') bal++;
        else if (s[i] == ')') bal--;
        else {
            long long a, b; cin >> a >> b;
            s[i] = ')'; cost += b; bal--;
            flips.push({a - b, i});
        }
        if (bal < 0) {
            if (flips.empty()) { cout << -1 << '\n'; return 0; }
            auto [d, pos] = flips.top(); flips.pop();
            cost += d; s[pos] = '('; bal += 2;
        }
    }
    if (bal != 0) { cout << -1 << '\n'; return 0; }
    cout << cost << '\n' << s << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        char[] s = in.next().toCharArray();
        PriorityQueue<long[]> flips = new PriorityQueue<>((x, y) -> Long.compare(x[0], y[0]));
        long cost = 0; int bal = 0;
        for (int i = 0; i < s.length; i++) {
            if (s[i] == '(') bal++;
            else if (s[i] == ')') bal--;
            else {
                long a = in.nextLong(), b = in.nextLong();
                s[i] = ')'; cost += b; bal--;
                flips.add(new long[]{a - b, i});
            }
            if (bal < 0) {
                if (flips.isEmpty()) { System.out.println(-1); return; }
                long[] f = flips.poll();
                cost += f[0]; s[(int) f[1]] = '('; bal += 2;
            }
        }
        if (bal != 0) { System.out.println(-1); return; }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(cost);
        out.println(new String(s));
        out.flush();
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
        String next() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
??
5 1
3 4
out:
9
()
-->
<!-- test
in:
))((
out:
-1
-->
<!-- test
in:
?()?
2 7
6 1
out:
3
(())
-->
<!-- test
in:
????
1 10
10 1
1 10
10 1
out:
4
()()
-->

</details>

Examples 1–6 were stress-tested against brute force (assignment search, subset enumeration, $O(nk)$ DPs, and
enumeration of all `?` replacements, checking both the cost and the validity of the printed sequence).

## 6. Tricks, pitfalls and things to remember

1. **Heap direction.** `std::priority_queue<T>` is a *max*-heap; `PriorityQueue<T>` is a *min*-heap. Write the comparator
   explicitly (`greater<>` / `Comparator.reverseOrder()`) and say it out loud while coding.
2. **One eviction or a loop?** In Potions one pop always suffices (the evicted value is $\le$ the current one). In general
   prefix-constraint problems use `while (violated) pop()`; it costs nothing to be safe.
3. **Regret greedy must be stress-tested.** The tokens are easy to get subtly wrong (wrong price, missing border case).
   The DP brute force is usually 10 lines; write it.
4. **Java boxing.** `PriorityQueue<Long>` allocates per element and compares through `compareTo`; for $10^6$ operations it is
   fine, for $10^7$ encode pairs into a primitive `long` (`value << 20 | index`) or write an array heap.
5. **Never compare boxed values with `==`** (`Long`, `Integer` outside $[-128, 127]$): use `.equals` or unbox.
6. **`PriorityQueue.remove(Object)` is $O(n)$** — use lazy deletion or a `TreeMap<value, count>`.
7. **Lazy deletion validity check** must be exact: compare the stored value with the current value (or a version
   number), not just an "alive" flag, when keys can be updated.
8. **Sentinels in linked-list regret:** borders must produce a $-\infty$ token, and $-\infty$ arithmetic must not overflow
   (`LLONG_MIN/4`, and clamp sums that involve it).
9. **Reverse-time scanning** (Summer Vacation) is often simpler than forward eviction: the most constrained slot is
   filled first with the best eligible item.
10. **Marginal gains need convexity.** Before using a gain heap, check that each item's gains are non-increasing; if not
    (e.g. a fixed setup cost), the greedy can be arbitrarily bad.
11. **Ties in heaps** of pairs compare the second component; make sure that does not matter, or include an index so
    the order is deterministic (important when the output is a construction).

## 7. Going further (toward 2400–2600+)

- **Regret greedy = min-cost flow simulation.** CF 730I (two kinds of assignments, three heaps of "switch" options) and
  CF 436E "Cardboard Box" (stars with 1 or 2 levels, five heap candidates per step) are the next steps.
- **"Simulate flow with heaps" on trees/lines:** matching on a line with capacities (mice and holes, CF 797F) uses the
  same tokens plus monotone stacks.
- **Slope trick** ([07-DP-Optimizations/07](../07-DP-Optimizations/07-slope-trick.md)) maintains the breakpoints of a convex
  piecewise-linear DP in a heap; Buy Low Sell High is its simplest instance.
- **Aliens trick / WQS binary search** ([07-DP-Optimizations/06](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md))
  solves "exactly $k$" problems with concave answers — the same concavity that makes the $k$ non-adjacent regret work.
- **Mergeable heaps** (leftist/skew heaps, or small-to-large with `priority_queue`) for tree versions: "for every subtree,
  keep the best $k$ chosen items" ([small-to-large](../10-Trees/03-small-to-large-and-dsu-on-tree.md)).

## 8. Practice ladder

**≤ 1700**
- [ ] [CF 1498B · Box Fitting](https://codeforces.com/problemset/problem/1498/B) — 1300
- [ ] [CF 1515C · Phoenix and Towers](https://codeforces.com/problemset/problem/1515/C) — 1400
- [ ] [CF 1526C1 · Potions (Easy Version)](https://codeforces.com/problemset/problem/1526/C1) — 1500
- [ ] [CF 1526C2 · Potions (Hard Version)](https://codeforces.com/problemset/problem/1526/C2) — 1600
- [ ] [CF 1140C · Playlist](https://codeforces.com/problemset/problem/1140/C) — 1600
- [ ] [CF 1779C · Least Prefix Sum](https://codeforces.com/problemset/problem/1779/C) — 1600
- [ ] [AtCoder ABC137 D · Summer Vacation](https://atcoder.jp/contests/abc137/tasks/abc137_d)
- [ ] [CSES 1164 · Room Allocation](https://cses.fi/problemset/task/1164)
- [ ] [CSES 1632 · Movie Festival II](https://cses.fi/problemset/task/1632)

**1700–2300**
- [ ] [CF 730I · Olympiad in Programming and Sports](https://codeforces.com/problemset/problem/730/I) — 2000
- [ ] [CF 1271D · Portals](https://codeforces.com/problemset/problem/1271/D) — 2100
- [ ] [CF 1428E · Carrots for Rabbits](https://codeforces.com/problemset/problem/1428/E) — 2200
- [ ] [CF 958E2 · Guard Duty (medium)](https://codeforces.com/problemset/problem/958/E2) — 2200

**2300+**
- [ ] [CF 1251E2 · Voting (Hard Version)](https://codeforces.com/problemset/problem/1251/E2) — 2400
- [ ] [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400
- [ ] [CF 3D · Least Cost Bracket Sequence](https://codeforces.com/problemset/problem/3/D) — 2600
- [ ] [CF 436E · Cardboard Box](https://codeforces.com/problemset/problem/436/E) — 2600
- [ ] [CF 797F · Mice and Holes](https://codeforces.com/problemset/problem/797/F) — 2600

## 9. LeetCode / FAANG cross-reference

- [LC 630 · Course Schedule III](https://leetcode.com/problems/course-schedule-iii/) — Hard — Moore–Hodgson: sort by deadline, evict the longest.
- [LC 1353 · Maximum Number of Events That Can Be Attended](https://leetcode.com/problems/maximum-number-of-events-that-can-be-attended/) — Medium — sweep days, min-heap of end days, attend the one ending soonest.
- [LC 871 · Minimum Number of Refueling Stops](https://leetcode.com/problems/minimum-number-of-refueling-stops/) — Hard — "take now, decide later": stations passed go into a max-heap, refuel retroactively when stuck.
- [LC 1642 · Furthest Building You Can Reach](https://leetcode.com/problems/furthest-building-you-can-reach/) — Medium — ladders on the largest climbs: min-heap of size = #ladders, bricks for evicted climbs.
- [LC 502 · IPO](https://leetcode.com/problems/ipo/) — Hard — sweep by capital, max-heap of profits.
- [LC 857 · Minimum Cost to Hire K Workers](https://leetcode.com/problems/minimum-cost-to-hire-k-workers/) — Hard — sort by ratio, keep the $k$ smallest qualities in a max-heap.
- [LC 2542 · Maximum Subsequence Score](https://leetcode.com/problems/maximum-subsequence-score/) — Medium — sort by the multiplier, top-$k$ sum heap.
- [LC 1383 · Maximum Performance of a Team](https://leetcode.com/problems/maximum-performance-of-a-team/) — Hard — same pattern as 2542.
- [LC 621 · Task Scheduler](https://leetcode.com/problems/task-scheduler/) — Medium — most frequent first (heap simulation or a closed form).
- [LC 1705 · Maximum Number of Eaten Apples](https://leetcode.com/problems/maximum-number-of-eaten-apples/) — Medium — eat the apple that rots first; lazy-discard rotten ones.
- [LC 122 · Best Time to Buy and Sell Stock II](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-ii/) — Medium — unlimited shares: sum of positive differences (the regret-free special case).
- [LC 480 · Sliding Window Median](https://leetcode.com/problems/sliding-window-median/) — Hard — two heaps with lazy deletion.
- [LC 295 · Find Median from Data Stream](https://leetcode.com/problems/find-median-from-data-stream/) — Hard — two balanced heaps.
- [LC 2402 · Meeting Rooms III](https://leetcode.com/problems/meeting-rooms-iii/) — Hard — two heaps: free rooms by index, busy rooms by end time.

Heap greedies are very common in interviews (LC 630, 871, 1642, 502 are frequent); interviewers look for the
"defer the decision, fix it with a heap later" insight and a clear invariant.

## 10. Self-check

1. Why does "sort by deadline, push profit, pop the minimum when size exceeds the deadline" maximise profit?
2. In Potions, why is one eviction enough, and why evict the most negative potion?
3. Write the regret token for Buy Low Sell High and the identity that justifies it.
4. Why does the plain "take the max, delete neighbours" fail for $k$ non-adjacent picks, and what does the token $a_l+a_r-a_i$ mean?
5. What property of the cost functions makes the marginal-gain heap optimal? Give an example where it fails.
6. How do you delete an arbitrary element from a binary heap in $O(\log n)$ amortised?
7. In Least Cost Bracket Sequence, why is flipping the *cheapest* earlier `?` always safe?

<details><summary>Answers</summary>

1. Feasible job sets form a matroid (Hall's condition per prefix of deadlines). At a violation, any feasible solution
   must omit one of the jobs seen so far; omitting the cheapest is best, and one omission restores feasibility.
2. Let $h \ge 0$ be the health before potion $i$. If $h + a_i < 0$ then $a_i < 0$, and the heap minimum $m$ satisfies
   $m \le a_i$, so the health after removing $m$ is $h + a_i - m \ge h \ge 0$. Removing the most negative potion
   maximises the remaining health for the same count.
3. After selling at $p$ against $c$, push $p$ again. Later selling at $q$ against that $p$ adds $q-p$, and
   $(p-c)+(q-p) = q-c$: the trade becomes $c \to q$ with day $p$ idle.
4. On $[9,10,9]$, $k=2$ it takes 10 and is stuck. The token means "give back $a_i$ and take both neighbours" — an
   augmenting path; merged nodes behave like single elements.
5. Convexity: each item's marginal gains are non-increasing. With a fixed setup cost (first unit gains little, later units a
   lot) the greedy never starts the right item.
6. Lazy deletion: record deletions (second heap / counter / version) and skip stale entries when they reach the top.
7. Every earlier `?` fixes the current prefix and adds $+2$ to all later prefixes identically, so all candidates are
   interchangeable for feasibility; only cost differs.

</details>
