# FAANG Interview DSA — Cheat Sheet

Revision sheet for [17 · FAANG Interview DSA](../17-FAANG-Interview-DSA/README.md). Learn from the pattern files; use this page the day before a mock or an interview. Problem lists and badges: [master list](../17-FAANG-Interview-DSA/18-leetcode-master-list.md).

## 1. The 45-minute timeline

| Minute | Step | Output |
|---|---|---|
| 0–4 | clarify | restated problem, constraints, edge cases agreed |
| 4–7 | examples | one normal + one edge example worked by hand |
| 7–9 | brute force | "$O(\cdot)$ because …", usually not coded |
| 9–17 | optimise | the waste removed, pattern named, complexity, interviewer buy-in |
| 17–32 | code | clean class code, narrated |
| 32–37 | test | trace an example with real values, then edge cases |
| 37–45 | complexity + follow-ups | exact time/space, variants |

Stuck for 3 minutes → say what you have and what's missing → try the pattern questions below → ask for a hint. Details: [file 01](../17-FAANG-Interview-DSA/01-interview-framework-and-communication.md).

## 2. Constraints → target → technique

| $n$ | Target | Usually |
|---|---|---|
| ≤ 12 | $O(n!)$ | permutations, backtracking |
| ≤ 20–25 | $O(2^n \cdot n)$ | subsets, bitmask DP |
| ≤ 500 | $O(n^3)$ | interval DP, Floyd–Warshall |
| ≤ 5000 | $O(n^2)$ | 2D DP, all pairs |
| ≤ $10^6$ | $O(n \log n)$ / $O(n)$ | sort, heap, hash, two pointers, binary search, linear DP |
| value ≤ $10^9$–$10^{18}$ | $O(\log V)$ | binary search on the answer, fast power |

## 3. Signal → pattern

| Signal in the statement | Pattern | File |
|---|---|---|
| pair / complement / "seen before" / duplicates | hash map / set | [02](../17-FAANG-Interview-DSA/02-arrays-hashing-and-prefix-sums.md) |
| group "equivalent" items | canonical key | [02](../17-FAANG-Interview-DSA/02-arrays-hashing-and-prefix-sums.md) |
| subarray sum = k (negatives) / divisible by k | prefix sums + count map | [02](../17-FAANG-Interview-DSA/02-arrays-hashing-and-prefix-sums.md) |
| sorted array, pair/triple sum, in-place filtering | two pointers | [03](../17-FAANG-Interview-DSA/03-two-pointers-and-sliding-window.md) |
| longest/shortest substring/subarray with a monotone condition | sliding window | [03](../17-FAANG-Interview-DSA/03-two-pointers-and-sliding-window.md) |
| brackets, nesting, "evaluate", undo | stack | [04](../17-FAANG-Interview-DSA/04-stacks-and-monotonic-stacks.md) |
| next/previous greater/smaller, histogram, span | monotonic stack | [04](../17-FAANG-Interview-DSA/04-stacks-and-monotonic-stacks.md) |
| max/min of every window | monotonic deque | [04](../17-FAANG-Interview-DSA/04-stacks-and-monotonic-stacks.md) |
| sorted / rotated / "O(log n)" / min feasible value | binary search (on index or answer) | [05](../17-FAANG-Interview-DSA/05-binary-search.md) |
| middle, k-th from end, cycle, reorder | fast/slow pointers, reversal | [06](../17-FAANG-Interview-DSA/06-linked-lists.md) |
| tree height/diameter/path sums/LCA/validate BST | DFS returning a value (+ global record) | [07](../17-FAANG-Interview-DSA/07-trees-and-bst.md) |
| per-level tree answers | BFS by levels | [07](../17-FAANG-Interview-DSA/07-trees-and-bst.md) |
| prefixes, autocomplete, many words in a grid | trie | [08](../17-FAANG-Interview-DSA/08-tries.md) |
| top k / k-th / k closest / merge k sorted / median stream | heap(s), quickselect | [09](../17-FAANG-Interview-DSA/09-heaps-and-top-k.md) |
| "all" subsets/permutations/combinations/placements | backtracking | [10](../17-FAANG-Interview-DSA/10-backtracking.md) |
| islands, components, flood fill, "nearest" from many sources | BFS/DFS, multi-source BFS | [11](../17-FAANG-Interview-DSA/11-graphs.md) |
| prerequisites, ordering, cycle in dependencies | topological sort | [11](../17-FAANG-Interview-DSA/11-graphs.md) |
| edges arrive over time, redundant edge, merge accounts | union-find | [11](../17-FAANG-Interview-DSA/11-graphs.md) |
| weighted minimum cost / time | Dijkstra (≥ 0), Bellman–Ford (k stops) | [12](../17-FAANG-Interview-DSA/12-advanced-graphs.md) |
| connect everything at minimum cost | MST | [12](../17-FAANG-Interview-DSA/12-advanced-graphs.md) |
| count ways / min cost / feasible, overlapping subproblems | DP | [13](../17-FAANG-Interview-DSA/13-dynamic-programming-1d.md), [14](../17-FAANG-Interview-DSA/14-dynamic-programming-2d.md) |
| two strings, grid paths, subset sums, burst/merge intervals | 2D DP | [14](../17-FAANG-Interview-DSA/14-dynamic-programming-2d.md) |
| intervals: merge / max non-overlapping / rooms | sort by start / by end / sweep | [15](../17-FAANG-Interview-DSA/15-greedy-and-intervals.md) |
| reach the end, circular gas route | greedy reach / restart rule | [15](../17-FAANG-Interview-DSA/15-greedy-and-intervals.md) |
| "appears twice except one", no `+`, power of two | bit tricks | [16](../17-FAANG-Interview-DSA/16-math-geometry-and-bit-manipulation.md) |
| O(1) get/put with eviction, O(1) random element | design: compose structures | [17](../17-FAANG-Interview-DSA/17-design-problems.md) |

## 4. Operation costs (C++ / Java)

| Structure | C++ | Java | Cost |
|---|---|---|---|
| dynamic array | `vector` | `ArrayList` | push back $O(1)$ amortised, insert middle $O(n)$ |
| hash map / set | `unordered_map` / `unordered_set` | `HashMap` / `HashSet` | $O(1)$ expected |
| ordered map / set | `map` / `set` | `TreeMap` / `TreeSet` | $O(\log n)$; floor/ceiling: `lower_bound` vs `floorKey`/`ceilingKey` |
| heap | `priority_queue` (**max** by default) | `PriorityQueue` (**min** by default) | push/pop $O(\log n)$ |
| deque / queue / stack | `deque`, `queue`, `vector` | `ArrayDeque` | $O(1)$ |
| linked list | `list` (`splice` $O(1)$) | `LinkedList` | $O(1)$ at a known node |
| sort | `sort` (introsort) | `Arrays.sort` (primitives: dual-pivot quicksort; objects: TimSort, stable) | $O(n \log n)$ |

## 5. Templates (C++ and Java)

First true in `[lo, hi)`, prefix-sum counting and the longest valid window:

```cpp
long long firstTrue(long long lo, long long hi, const function<bool(long long)>& ok) {
    while (lo < hi) { long long mid = lo + (hi - lo) / 2; if (ok(mid)) hi = mid; else lo = mid + 1; }
    return lo;                                           // hi if ok is false everywhere
}
int countSubarraysWithSum(const vector<int>& a, int k) {
    unordered_map<long long, int> cnt{{0, 1}};           // empty prefix
    long long p = 0; int res = 0;
    for (int x : a) { p += x; if (auto it = cnt.find(p - k); it != cnt.end()) res += it->second; ++cnt[p]; }
    return res;
}
int longestAtMostKDistinct(const vector<int>& a, int k) {
    unordered_map<int, int> c; int best = 0;
    for (int l = 0, r = 0; r < (int)a.size(); ++r) {
        ++c[a[r]];
        while ((int)c.size() > k) { if (--c[a[l]] == 0) c.erase(a[l]); ++l; }
        best = max(best, r - l + 1);
    }
    return best;
}
```

```java
static long firstTrue(long lo, long hi, LongPredicate ok) {
    while (lo < hi) { long mid = lo + (hi - lo) / 2; if (ok.test(mid)) hi = mid; else lo = mid + 1; }
    return lo;
}
static int countSubarraysWithSum(int[] a, int k) {
    Map<Long, Integer> cnt = new HashMap<>();
    cnt.put(0L, 1);
    long p = 0; int res = 0;
    for (int x : a) { p += x; res += cnt.getOrDefault(p - k, 0); cnt.merge(p, 1, Integer::sum); }
    return res;
}
static int longestAtMostKDistinct(int[] a, int k) {
    Map<Integer, Integer> c = new HashMap<>(); int best = 0;
    for (int l = 0, r = 0; r < a.length; r++) {
        c.merge(a[r], 1, Integer::sum);
        while (c.size() > k) { if (c.merge(a[l], -1, Integer::sum) == 0) c.remove(a[l]); l++; }
        best = Math.max(best, r - l + 1);
    }
    return best;
}
```

Next greater element and top-k with a min-heap:

```cpp
vector<int> nextGreaterIndex(const vector<int>& a) {     // n if none
    vector<int> res(a.size(), a.size()), st;
    for (int i = 0; i < (int)a.size(); ++i) {
        while (!st.empty() && a[st.back()] < a[i]) { res[st.back()] = i; st.pop_back(); }
        st.push_back(i);
    }
    return res;
}
vector<int> topKLargest(const vector<int>& a, int k) {
    priority_queue<int, vector<int>, greater<int>> h;     // min-heap holds the k largest
    for (int x : a) { h.push(x); if ((int)h.size() > k) h.pop(); }
    vector<int> out;
    while (!h.empty()) { out.push_back(h.top()); h.pop(); }
    return out;
}
```

```java
static int[] nextGreaterIndex(int[] a) {
    int n = a.length; int[] res = new int[n], st = new int[n]; int top = 0;
    Arrays.fill(res, n);
    for (int i = 0; i < n; i++) {
        while (top > 0 && a[st[top - 1]] < a[i]) res[st[--top]] = i;
        st[top++] = i;
    }
    return res;
}
static List<Integer> topKLargest(int[] a, int k) {
    PriorityQueue<Integer> h = new PriorityQueue<>();
    for (int x : a) { h.add(x); if (h.size() > k) h.poll(); }
    return new ArrayList<>(h);
}
```

Grid BFS (multi-source), DSU and Kahn's topological sort:

```cpp
vector<vector<int>> gridDistances(const vector<string>& g, char src, char wall) {
    int R = g.size(), C = g[0].size();
    vector<vector<int>> d(R, vector<int>(C, -1));
    queue<pair<int, int>> q;
    for (int r = 0; r < R; ++r) for (int c = 0; c < C; ++c) if (g[r][c] == src) { d[r][c] = 0; q.push({r, c}); }
    int dr[4] = {1, -1, 0, 0}, dc[4] = {0, 0, 1, -1};
    while (!q.empty()) {
        auto [r, c] = q.front(); q.pop();
        for (int k = 0; k < 4; ++k) {
            int nr = r + dr[k], nc = c + dc[k];
            if (nr < 0 || nr >= R || nc < 0 || nc >= C || g[nr][nc] == wall || d[nr][nc] != -1) continue;
            d[nr][nc] = d[r][c] + 1; q.push({nr, nc});            // mark when pushing
        }
    }
    return d;
}
struct DSU {
    vector<int> p, s;
    DSU(int n) : p(n), s(n, 1) { iota(p.begin(), p.end(), 0); }
    int find(int x) { while (p[x] != x) x = p[x] = p[p[x]]; return x; }
    bool unite(int a, int b) { a = find(a); b = find(b); if (a == b) return false; if (s[a] < s[b]) swap(a, b); p[b] = a; s[a] += s[b]; return true; }
};
vector<int> kahn(int n, const vector<vector<int>>& adj) {        // empty if a cycle exists
    vector<int> in(n, 0), order; queue<int> q;
    for (auto& es : adj) for (int v : es) ++in[v];
    for (int u = 0; u < n; ++u) if (!in[u]) q.push(u);
    while (!q.empty()) { int u = q.front(); q.pop(); order.push_back(u); for (int v : adj[u]) if (!--in[v]) q.push(v); }
    if ((int)order.size() < n) order.clear();
    return order;
}
```

```java
static int[][] gridDistances(String[] g, char src, char wall) {
    int R = g.length, C = g[0].length();
    int[][] d = new int[R][C];
    for (int[] row : d) Arrays.fill(row, -1);
    ArrayDeque<int[]> q = new ArrayDeque<>();
    for (int r = 0; r < R; r++) for (int c = 0; c < C; c++) if (g[r].charAt(c) == src) { d[r][c] = 0; q.add(new int[]{r, c}); }
    int[] dr = {1, -1, 0, 0}, dc = {0, 0, 1, -1};
    while (!q.isEmpty()) {
        int[] cur = q.poll();
        for (int k = 0; k < 4; k++) {
            int nr = cur[0] + dr[k], nc = cur[1] + dc[k];
            if (nr < 0 || nr >= R || nc < 0 || nc >= C || g[nr].charAt(nc) == wall || d[nr][nc] != -1) continue;
            d[nr][nc] = d[cur[0]][cur[1]] + 1; q.add(new int[]{nr, nc});
        }
    }
    return d;
}
static int[] parent, size;
static int find(int x) { while (parent[x] != x) x = parent[x] = parent[parent[x]]; return x; }
static boolean unite(int a, int b) {
    a = find(a); b = find(b); if (a == b) return false;
    if (size[a] < size[b]) { int t = a; a = b; b = t; }
    parent[b] = a; size[a] += size[b]; return true;
}
static int[] kahn(int n, List<List<Integer>> adj) {
    int[] in = new int[n], order = new int[n]; int k = 0;
    for (List<Integer> es : adj) for (int v : es) in[v]++;
    ArrayDeque<Integer> q = new ArrayDeque<>();
    for (int u = 0; u < n; u++) if (in[u] == 0) q.add(u);
    while (!q.isEmpty()) { int u = q.poll(); order[k++] = u; for (int v : adj.get(u)) if (--in[v] == 0) q.add(v); }
    return k == n ? order : new int[0];
}
```

Dijkstra, backtracking skeleton and 0/1 vs unbounded knapsack:

```cpp
vector<long long> dijkstra(const vector<vector<pair<int, int>>>& adj, int s) {
    vector<long long> d(adj.size(), LLONG_MAX);
    priority_queue<pair<long long, int>, vector<pair<long long, int>>, greater<>> pq;
    d[s] = 0; pq.push({0, s});
    while (!pq.empty()) {
        auto [du, u] = pq.top(); pq.pop();
        if (du > d[u]) continue;                                  // stale
        for (auto [v, w] : adj[u]) if (du + w < d[v]) { d[v] = du + w; pq.push({d[v], v}); }
    }
    return d;
}
void combos(const vector<int>& a, int start, vector<int>& path, vector<vector<int>>& out) {   // a sorted
    out.push_back(path);
    for (int i = start; i < (int)a.size(); ++i) {
        if (i > start && a[i] == a[i - 1]) continue;              // skip equal siblings
        path.push_back(a[i]); combos(a, i + 1, path, out); path.pop_back();
    }
}
int subsetSumMaxValue(const vector<int>& w, const vector<int>& v, int W, bool unbounded) {
    vector<int> dp(W + 1, 0);
    for (size_t i = 0; i < w.size(); ++i)
        if (unbounded) { for (int c = w[i]; c <= W; ++c) dp[c] = max(dp[c], dp[c - w[i]] + v[i]); }
        else           { for (int c = W; c >= w[i]; --c) dp[c] = max(dp[c], dp[c - w[i]] + v[i]); }
    return dp[W];
}
```

```java
static long[] dijkstra(List<List<int[]>> adj, int s) {
    long[] d = new long[adj.size()];
    Arrays.fill(d, Long.MAX_VALUE);
    PriorityQueue<long[]> pq = new PriorityQueue<>((x, y) -> Long.compare(x[0], y[0]));
    d[s] = 0; pq.add(new long[]{0, s});
    while (!pq.isEmpty()) {
        long[] t = pq.poll(); int u = (int) t[1];
        if (t[0] > d[u]) continue;
        for (int[] e : adj.get(u)) if (t[0] + e[1] < d[e[0]]) { d[e[0]] = t[0] + e[1]; pq.add(new long[]{d[e[0]], e[0]}); }
    }
    return d;
}
static void combos(int[] a, int start, Deque<Integer> path, List<List<Integer>> out) {
    out.add(new ArrayList<>(path));                              // copy, not the live path
    for (int i = start; i < a.length; i++) {
        if (i > start && a[i] == a[i - 1]) continue;
        path.addLast(a[i]); combos(a, i + 1, path, out); path.removeLast();
    }
}
static int subsetSumMaxValue(int[] w, int[] v, int W, boolean unbounded) {
    int[] dp = new int[W + 1];
    for (int i = 0; i < w.length; i++)
        if (unbounded) { for (int c = w[i]; c <= W; c++) dp[c] = Math.max(dp[c], dp[c - w[i]] + v[i]); }
        else           { for (int c = W; c >= w[i]; c--) dp[c] = Math.max(dp[c], dp[c - w[i]] + v[i]); }
    return dp[W];
}
```

## 6. Key facts to have at your fingertips

| Fact | Value |
|---|---|
| LRU | hash map + doubly linked list; C++ `list::splice` moves a node in $O(1)$ |
| LFU | key → (value, freq, pos), freq → LRU list, `minFreq` (reset to 1 on insert) |
| randomized set | array + value→index; delete by swapping with the last element |
| two-heap median | max-heap `low`, min-heap `high`, `size(low) ∈ {size(high), size(high)+1}` |
| Floyd cycle entry | after meeting, restart one pointer at the head; both step 1 until they meet |
| BST validity | bounds from all ancestors, 64-bit sentinels |
| Kadane | `cur = max(x, cur + x)`; products: keep max **and** min |
| LIS $O(n \log n)$ | `lower_bound` into `tails` (strict); `upper_bound` for non-decreasing |
| interval sorting | merge: by start; max non-overlapping / arrows: by end; rooms: sweep with ends first |
| Bellman–Ford, at most $k$ stops | $k+1$ rounds, relax from a copy |
| knapsack loop direction | 0/1: capacity downwards; unbounded: upwards |
| coin-change counting | coins outer = combinations; amount outer = ordered sequences |
| rotate 90° clockwise | transpose, then reverse rows |
| `x & (x-1)` / `x & -x` | clear / isolate the lowest set bit |

## 7. Top 10 mistakes

1. Coding before clarifying (empty input? duplicates? negatives? return indices or values?).
2. Marking BFS nodes visited on pop instead of on push.
3. Wrong heap direction (k largest needs a **min**-heap) or an inverted C++ comparator.
4. Sliding window on a non-monotone condition (sum = k with negatives → prefix sums).
5. Integer overflow: prefix sums, products, `mid = (lo + hi) / 2`, `-INT_MIN`, `dist + w` with `INT_MAX`.
6. Off-by-one in windows (`r - l + 1`), binary-search bounds, and "k stops = k + 1 edges".
7. Forgetting to restore state in backtracking, or storing the live `path` instead of a copy.
8. Validating a BST by comparing only with the children.
9. Losing `next` while relinking a linked list; not cutting a list when splitting it.
10. Not testing out loud: no hand trace, no edge cases, unstated complexity.

## 8. Last-minute list (the day before)

- [ ] Re-read §3 (signal → pattern) and §6 (key facts).
- [ ] Write from memory, in your interview language: binary search first-true, BFS on a grid, DSU, Dijkstra, LRU.
- [ ] Re-solve two `G75` problems from different patterns in under 25 minutes each, speaking aloud.
- [ ] Prepare the opening line ("Let me restate the problem…") and the closing line ("Time is … space is …; for a stream I would …").
- [ ] Check the setup: editor without autocomplete, a working microphone, water, a pen and paper for examples.
- [ ] Sleep. A rested brain beats one more problem.
