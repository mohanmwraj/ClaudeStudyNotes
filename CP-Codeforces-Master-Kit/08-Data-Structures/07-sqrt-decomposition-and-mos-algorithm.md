# Sqrt Decomposition and Mo's Algorithm

> **Band:** 🟣–🟠 1900–2600 · **Priority:** 🔥 (blocks, thresholds, Mo) · ⚡ (Mo with updates, sqrt on queries) · 🧊 (Hilbert order, Mo on trees) · **FAANG:** low · **Prerequisites:** [complexity and constraints](../01-Foundations/01-complexity-and-constraint-reading.md), [segment tree basics](02-segment-tree-basics.md), [two pointers](../02-Core-Techniques/03-two-pointers-and-sliding-window.md)
> **You can say you know this when:** you can pick a block size by balancing two costs on paper, use a frequency/size threshold to split a problem into "few heavy" and "many light" cases, implement Mo's algorithm with the odd–even trick and prove $O((n+q)\sqrt n)$, and extend it with a time dimension ($O(n^{5/3})$).

## 1. First principles — why this works

### 1.1 The balancing principle

Many problems have two naive solutions whose costs move in opposite directions with some parameter $B$: "do more work per update, less per query" vs the reverse.
If the total cost is $f(B) + g(B)$ with $f$ increasing and $g$ decreasing, the optimum is (up to a constant) where $f(B) = g(B)$. For $f = qB$ and $g = qn/B$, this gives
$B = \sqrt n$ and cost $O(q\sqrt n)$. **Always write the two costs down and solve for $B$**; "$\sqrt n$" is only the answer when the two sides are symmetric.

### 1.2 Block decomposition

Cut the array into $\lceil n/B\rceil$ blocks of size $B$. Each block keeps a summary (sum, a lazy tag, a sorted copy, a frequency table…).
A range operation touches at most two *partial* blocks element by element ($O(B)$) and the *full* blocks through their summaries ($O(n/B)$ summaries).
With $O(1)$ summaries that is $O(B + n/B) = O(\sqrt n)$ — worse than a segment tree. Blocks win when the summary is something a segment tree cannot merge cheaply:

- *"count elements $< x$ in $[l, r]$" with range adds* — each block keeps a sorted copy and an add tag: full block = one binary search, partial block = rebuild the sorted copy.
  Query $O(B + \frac nB\log B)$, update $O(B\log B + \frac nB)$; balancing gives $B \approx \sqrt{n\log n}$.
- *"jump" structures* (next position after jumping, number of jumps to leave the block) where an update only invalidates one block: [CF 13E · Holes](https://codeforces.com/problemset/problem/13/E) — 2700.
- *operations with no associative summary* but cheap per-block rebuilds.

### 1.3 Thresholds: heavy and light

Split objects by a size/frequency threshold $T$. Objects larger than $T$ are **heavy** — there are few of them (at most $N/T$ if sizes sum to $N$), so we can afford
precomputation per heavy object. Objects of size $\le T$ are **light** — each can be brute-forced in $O(T)$. Examples:

- *Sums over arithmetic progressions* $\sum_{i \equiv y \ (\mathrm{mod}\ x)} a_i$: for $x \le T$ maintain a table `small[x][y]` (update costs $O(T)$); for $x > T$ the progression has $\le n/x < n/T$ terms. Balance $T = \sqrt n$.
- *Jumping with step $a_p + k$*: for $k > T$ each query makes $< n/T$ jumps; for $k \le T$ precompute an $O(n)$ DP per distinct $k$.
- *Graphs*: vertices of degree $> \sqrt m$ are heavy (at most $2\sqrt m$ of them); triangle counting in $O(m\sqrt m)$ orients edges from lower to higher degree.

### 1.4 Mo's algorithm

**Setting.** $q$ offline range queries on a static array, where the answer is easy to maintain under **adding or removing one element at an end** of the current window
(counts of values, number of pairs with a property, a sum of a function of counts) — but not decomposable into a segment-tree merge.

**Idea.** Keep a window $[L, R]$ and its answer; to answer $[l, r]$, move $L$ and $R$ one step at a time. The cost is the total pointer movement, so **order the queries** to make it small:
sort by $(\lfloor l/B\rfloor, r)$.

**Proof of $O(n\cdot\frac nB + qB)$.** Within one block of left ends, $r$ is sorted, so $R$ moves $O(n)$ in total for that block; there are $n/B$ blocks: $O(n^2/B)$.
$L$ stays inside the current block: $\le B$ per query, plus $O(B)$ (amortised $O(n)$ overall) when moving to the next block: $O(qB + n)$.
Total $O(n^2/B + qB)$, minimised at $B = n/\sqrt q$: $O(n\sqrt q)$. With $B = \sqrt n$ and $q \approx n$: $O((n + q)\sqrt n)$ add/remove operations.

**Odd–even trick.** Sort $r$ ascending in even blocks and descending in odd blocks: $R$ then sweeps back and forth instead of jumping back to the left after each block,
roughly halving $R$'s movement. **Hilbert order** (🧊): sort queries by the index of $(l, r)$ along a Hilbert curve; locality in both coordinates gives a further constant-factor gain.

**Pointer discipline.** Expand before shrinking (`L--`, `R++` first, then `L++`, `R--`), so that the window is never "negative" — otherwise removals happen before additions and counters go below zero.

### 1.5 Mo with updates (🟠)

Point assignments interleaved with queries: give each query a **time** $t$ = number of updates before it; a state is $(L, R, T)$. Moving $T$ forward/backward applies/reverts one update
(if its position lies in the window, remove the old value and add the new one). Sort by $(\lfloor l/B\rfloor, \lfloor r/B\rfloor, t)$.
With $n \approx q$: $T$ moves $O(q)$ per pair of blocks, i.e. $O(q\cdot (n/B)^2)$; $L$ and $R$ move $O(B)$ per query plus $O(n)$ per block change, $O(qB + n^2/B)$.
Balancing $qn^2/B^2 = qB$ gives $B = n^{2/3}$ and **total $O(n^{5/3})$** — about $2\cdot10^8$ simple steps for $n = 10^5$: fine in C++, tight in Java.

### 1.6 Mo on trees (🔴, know it exists)

Path queries on a tree: write the Euler tour with both entry and exit times; a vertex appears twice. For a path $u \to v$ (with $\mathrm{in}_u \le \mathrm{in}_v$),
if $u$ is an ancestor of $v$ the path is the tour range $[\mathrm{in}_u, \mathrm{in}_v]$; otherwise it is $[\mathrm{out}_u, \mathrm{in}_v]$ plus the LCA separately. Vertices appearing twice in the
range are *not* on the path, so "add/remove" becomes "toggle". Subtree queries need no Mo at all (a subtree is a contiguous Euler range).

### 1.7 Sqrt decomposition on queries (rebuild every $B$ updates)

When updates make the structure dynamic but a **static** version is easy to build in $O(n)$ (or $O(n\log n)$): keep a list of pending updates; answer a query from the static
structure plus a brute-force correction over the pending updates; when the list reaches $B$, rebuild. Cost $O(\frac qB\cdot n + q\cdot B\cdot c)$ where $c$ is the cost of correcting for one
pending update; balance $B = \sqrt{n/c}$. Classic: distance to the nearest marked vertex (rebuild = multi-source BFS, correction = LCA distance).

## 2. Formulas, definitions and identities

| Technique | Cost | Optimal parameter |
|---|---|---|
| plain blocks, $O(1)$ summaries | $O(B + n/B)$ per op | $B = \sqrt n$ |
| blocks with sorted copies (count $< x$) | query $O(B + \frac nB\log B)$, update $O(B\log B)$ | $B \approx \sqrt{n \log n}$ |
| heavy/light threshold, total size $N$ | heavy objects $\le N/T$; light brute force $O(T)$ | $T = \sqrt N$ (balance the two sides) |
| Mo's algorithm | $O(n^2/B + qB)$ add/remove steps | $B = n/\sqrt q$, i.e. $O(n\sqrt q)$ |
| Mo with updates | $O(qn^2/B^2 + qB + n^2/B)$ | $B = n^{2/3}$, total $O(n^{5/3})$ |
| sqrt on queries | $O(\frac qB\cdot\text{rebuild} + qB\cdot c)$ | $B = \sqrt{\text{rebuild}/c}$ |
| mex of counts in a window of length $L$ | answer $m$ needs $1 + 2 + \dots + (m-1) \le L$ | $m = O(\sqrt L)$, brute-force scan is fine |

Powerful-array update rule: adding value $s$ with current count $K$ changes $\sum K_s^2 s$ by $(2K+1)s$; removing changes it by $-(2K-1)s$.
Prefix-xor pairs: the number of $i \le j$ with $a_i \oplus\dots\oplus a_j = k$ equals the number of pairs $x < y$ of prefix indices with $P_x \oplus P_y = k$.

## 3. Implementation (C++ and Java)

### 3.1 Block decomposition: range add, count elements below $x$

Original task: `n q`, the array, then `1 l r x` (add $x$ to $a_l..a_r$) or `2 l r x` (print $\#\{i \in [l, r] : a_i < x\}$). Each block keeps a lazy add and a sorted copy of its *untagged* values.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    int B = max(1, (int)sqrt(n * max(1.0, log2(n))));        // balance the B log B rebuild against n/B binary searches
    int nb = (n + B - 1) / B;
    vector<long long> tag(nb, 0);
    vector<vector<long long>> srt(nb);
    auto rebuild = [&](int b) {
        srt[b].assign(a.begin() + b * B, a.begin() + min(n, (b + 1) * B));
        sort(srt[b].begin(), srt[b].end());
    };
    for (int b = 0; b < nb; b++) rebuild(b);
    while (q--) {
        int t, l, r; long long x; cin >> t >> l >> r >> x; l--; r--;
        int bl = l / B, br = r / B;
        if (t == 1) {
            if (bl == br) { for (int i = l; i <= r; i++) a[i] += x; rebuild(bl); continue; }
            for (int i = l; i < (bl + 1) * B; i++) a[i] += x;
            rebuild(bl);
            for (int b = bl + 1; b < br; b++) tag[b] += x;
            for (int i = br * B; i <= r; i++) a[i] += x;
            rebuild(br);
        } else {
            long long cnt = 0;
            if (bl == br) { for (int i = l; i <= r; i++) cnt += a[i] + tag[bl] < x; }
            else {
                for (int i = l; i < (bl + 1) * B; i++) cnt += a[i] + tag[bl] < x;
                for (int b = bl + 1; b < br; b++) cnt += lower_bound(srt[b].begin(), srt[b].end(), x - tag[b]) - srt[b].begin();
                for (int i = br * B; i <= r; i++) cnt += a[i] + tag[br] < x;
            }
            cout << cnt << '\n';
        }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n, B; static long[] a, tag; static long[][] srt;
    static void rebuild(int b) {
        int lo = b * B, hi = Math.min(n, (b + 1) * B);
        srt[b] = Arrays.copyOfRange(a, lo, hi);
        Arrays.sort(srt[b]);                                   // block-local, size <= B: no anti-quicksort risk worth worrying about
    }
    static int lowerBound(long[] s, long x) { int lo = 0, hi = s.length; while (lo < hi) { int m = (lo + hi) >>> 1; if (s[m] < x) lo = m + 1; else hi = m; } return lo; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        n = in.nextInt(); int q = in.nextInt();
        a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        B = Math.max(1, (int) Math.sqrt(n * Math.max(1.0, Math.log(n) / Math.log(2))));
        int nb = (n + B - 1) / B;
        tag = new long[nb]; srt = new long[nb][];
        for (int b = 0; b < nb; b++) rebuild(b);
        while (q-- > 0) {
            int t = in.nextInt(), l = in.nextInt() - 1, r = in.nextInt() - 1; long x = in.nextLong();
            int bl = l / B, br = r / B;
            if (t == 1) {
                if (bl == br) { for (int i = l; i <= r; i++) a[i] += x; rebuild(bl); continue; }
                for (int i = l; i < (bl + 1) * B; i++) a[i] += x;
                rebuild(bl);
                for (int b = bl + 1; b < br; b++) tag[b] += x;
                for (int i = br * B; i <= r; i++) a[i] += x;
                rebuild(br);
            } else {
                long cnt = 0;
                if (bl == br) { for (int i = l; i <= r; i++) if (a[i] + tag[bl] < x) cnt++; }
                else {
                    for (int i = l; i < (bl + 1) * B; i++) if (a[i] + tag[bl] < x) cnt++;
                    for (int b = bl + 1; b < br; b++) cnt += lowerBound(srt[b], x - tag[b]);
                    for (int i = br * B; i <= r; i++) if (a[i] + tag[br] < x) cnt++;
                }
                out.println(cnt);
            }
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
6 5
5 1 4 2 8 3
2 1 6 4
1 2 5 3
2 1 6 4
2 3 3 8
2 2 5 5
out:
3
1
1
1
-->
<!-- test
in:
1 3
-5
2 1 1 -5
1 1 1 -1000000000
2 1 1 -5
out:
0
1
-->

### 3.2 Mo's algorithm skeleton (odd–even order)

```cpp
// Answers q offline queries [l, r] (0-indexed, inclusive). add(i)/remove(i) update the window state; get() reads the answer.
template <class Add, class Remove, class Get>
vector<long long> mo(int n, const vector<pair<int,int>>& qs, Add add, Remove remove, Get get) {
    int q = qs.size(), B = max(1, (int)(n / max(1.0, sqrt((double)q))));
    vector<int> ord(q);
    iota(ord.begin(), ord.end(), 0);
    sort(ord.begin(), ord.end(), [&](int x, int y) {
        int bx = qs[x].first / B, by = qs[y].first / B;
        if (bx != by) return bx < by;
        return (bx & 1) ? qs[x].second > qs[y].second : qs[x].second < qs[y].second;
    });
    vector<long long> ans(q);
    int L = 0, R = -1;
    for (int id : ord) {
        auto [l, r] = qs[id];
        while (L > l) add(--L);
        while (R < r) add(++R);
        while (L < l) remove(L++);
        while (R > r) remove(R--);
        ans[id] = get();
    }
    return ans;
}
```

```java
// Packs (block, r in odd-even order, id) into one long so that a primitive sort orders the queries; needs n, q < 2^20.
static long[] mo(int n, int[] ql, int[] qr, IntConsumer add, IntConsumer remove, LongSupplier get) {
    int q = ql.length, B = Math.max(1, (int) (n / Math.max(1.0, Math.sqrt(q))));
    long[] key = new long[q];
    for (int i = 0; i < q; i++) {
        long b = ql[i] / B, rr = (b & 1) == 1 ? (1 << 20) - 1 - qr[i] : qr[i];
        key[i] = b << 40 | rr << 20 | i;
    }
    Random rnd = new Random(3);
    for (int i = q - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = key[i]; key[i] = key[j]; key[j] = t; }
    Arrays.sort(key);
    long[] ans = new long[q];
    int L = 0, R = -1;
    for (long k : key) {
        int id = (int) (k & ((1 << 20) - 1)), l = ql[id], r = qr[id];
        while (L > l) add.accept(--L);
        while (R < r) add.accept(++R);
        while (L < l) remove.accept(L++);
        while (R > r) remove.accept(R--);
        ans[id] = get.getAsLong();
    }
    return ans;
}
```

In contest code, inline `add`/`remove` (lambdas and interface calls cost a few nanoseconds each, and Mo performs $\sim 10^8$ of them); the worked examples below do that.

## 4. Recognising the pattern

- **$n, q \le 10^5$ (sometimes $2\cdot10^5$), time limit 3–5 s, offline, the answer is a "count/frequency" statistic of a range** (distinct values, pairs with a property, $\sum f(\text{count})$, mex of counts) → Mo.
- **The same, but with point updates** → Mo with updates ($n \le 10^5$, generous TL).
- **A parameter $k$ or modulus $x$ that makes the work $O(n/k)$** → threshold at $\sqrt n$: precompute for small, brute force for large.
- **Few big objects, many small ones** (frequencies, set sizes, degrees) → heavy/light split.
- **Updates are rare relative to the cost of a static rebuild, and a single pending update can be "corrected" cheaply** → rebuild every $\sqrt q$ queries.
- **A segment tree would need a non-mergeable summary** (sorted copies, jump pointers) → block decomposition.
- Confused with: problems that *look* like Mo but have a mergeable summary (use a segment tree, $O(\log n)$); offline distinct counting (use the BIT trick in [Fenwick](01-fenwick-tree.md), $O(\log n)$).

## 5. Worked examples (graded)

### Example 1 — Array Queries (threshold on $k$)  ·  ★ 2000

- **Source:** [CF 797E · Array Queries](https://codeforces.com/problemset/problem/797/E) — 2000
- **Difficulty:** 2000
- **Problem:** $n \le 10^5$, $1 \le a_i \le n$; $q \le 10^5$ queries $(p, k)$ with $1 \le p, k \le n$: repeat $p \leftarrow p + a_p + k$ while $p \le n$; print the number of steps.
- **Thinking from first principles:** each step moves right by more than $k$, so a query takes $< n/k$ steps: cheap when $k$ is large. For a fixed small $k$, the answer from every $p$ is a DP
  over $p$ from right to left: $\text{dp}_k[p] = 1 + \text{dp}_k[p + a_p + k]$ (or 1 if that exceeds $n$), $O(n)$ per $k$. Threshold $T = \sqrt n$: total $O(n\sqrt n + q\sqrt n)$.
  Storing all $T$ tables is $3\cdot10^7$ ints; instead group queries by $k$ offline and keep one DP array at a time — memory $O(n)$.

<details><summary>Solution</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    int q; cin >> q;
    int T = max(1, (int)sqrt(n));
    vector<int> P(q), K(q), ans(q);
    vector<vector<int>> byK(T + 1);
    for (int i = 0; i < q; i++) {
        cin >> P[i] >> K[i];
        if (K[i] <= T) byK[K[i]].push_back(i);
        else { int c = 0; for (int p = P[i]; p <= n; p += a[p] + K[i]) c++; ans[i] = c; }   // < n / T steps
    }
    vector<int> dp(n + 1);
    for (int k = 1; k <= T; k++) {
        if (byK[k].empty()) continue;
        for (int p = n; p >= 1; p--) { int nx = p + a[p] + k; dp[p] = nx > n ? 1 : 1 + dp[nx]; }
        for (int i : byK[k]) ans[i] = dp[P[i]];
    }
    for (int i = 0; i < q; i++) cout << ans[i] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        int[] a = new int[n + 1];
        for (int i = 1; i <= n; i++) a[i] = in.nextInt();
        int q = in.nextInt(), T = Math.max(1, (int) Math.sqrt(n));
        int[] P = new int[q], K = new int[q], ans = new int[q], head = new int[T + 1], nxt = new int[q];
        Arrays.fill(head, -1);
        for (int i = 0; i < q; i++) {
            P[i] = in.nextInt(); K[i] = in.nextInt();
            if (K[i] <= T) { nxt[i] = head[K[i]]; head[K[i]] = i; }
            else { int c = 0; for (int p = P[i]; p <= n; p += a[p] + K[i]) c++; ans[i] = c; }
        }
        int[] dp = new int[n + 1];
        for (int k = 1; k <= T; k++) {
            if (head[k] == -1) continue;
            for (int p = n; p >= 1; p--) { int nx = p + a[p] + k; dp[p] = nx > n ? 1 : 1 + dp[nx]; }
            for (int i = head[k]; i != -1; i = nxt[i]) ans[i] = dp[P[i]];
        }
        for (int i = 0; i < q; i++) out.println(ans[i]);
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
3
1 1 1
3
1 1
2 1
3 1
out:
2
1
1
-->
<!-- test
in:
6
1 2 1 3 1 1
4
1 1
1 6
6 1
2 2
out:
3
1
1
2
-->
<!-- test
in:
1
1
2
1 1
1 1
out:
1
1
-->

</details>

### Example 2 — Remainder Problem (small/large modulus)  ·  ★ 2100

- **Source:** [CF 1207F · Remainder Problem](https://codeforces.com/problemset/problem/1207/F) — 2100
- **Difficulty:** 2100
- **Problem:** an array of $N = 500000$ zeros; $q \le 5\cdot10^5$ queries: `1 x y` — $a_x \mathrel{+}= y$ ($|y| \le 1000$); `2 x y` — print $\sum a_i$ over $1 \le i \le N$ with $i \bmod x = y$ ($0 \le y < x$).
- **Thinking from first principles:** a type-2 query visits $N/x$ positions: fine for large $x$. For small $x$, there are only $x$ residues, so we can maintain `small[x][y]` for every $x \le T$:
  an update touches one residue per small modulus, $O(T)$. Costs: update $O(T)$, query $O(N/T)$ → $T = \sqrt N \approx 708$. The table is $708^2$ 64-bit cells, 4 MB.

<details><summary>Solution</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const int N = 500000, T = 708;
    vector<long long> a(N + 1, 0);
    vector<vector<long long>> small(T + 1);
    for (int x = 1; x <= T; x++) small[x].assign(x, 0);
    int q; cin >> q;
    while (q--) {
        int t, x, y; cin >> t >> x >> y;
        if (t == 1) {
            a[x] += y;
            for (int m = 1; m <= T; m++) small[m][x % m] += y;
        } else if (x <= T) cout << small[x][y] << '\n';
        else {
            long long s = 0;
            for (int i = (y == 0 ? x : y); i <= N; i += x) s += a[i];
            cout << s << '\n';
        }
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
        final int N = 500000, T = 708;
        long[] a = new long[N + 1];
        long[][] small = new long[T + 1][];
        for (int x = 1; x <= T; x++) small[x] = new long[x];
        int q = in.nextInt();
        while (q-- > 0) {
            int t = in.nextInt(), x = in.nextInt(), y = in.nextInt();
            if (t == 1) {
                a[x] += y;
                for (int m = 1; m <= T; m++) small[m][x % m] += y;
            } else if (x <= T) out.println(small[x][y]);
            else {
                long s = 0;
                for (int i = (y == 0 ? x : y); i <= N; i += x) s += a[i];
                out.println(s);
            }
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
5
1 3 4
2 3 0
2 4 3
1 4 -4
2 1 0
out:
4
4
0
-->
<!-- test
in:
6
1 500000 1000
1 1000 -7
2 500000 0
2 1000 0
2 709 155
2 1 0
out:
1000
993
1000
993
-->

</details>

### Example 3 — Powerful array (Mo)  ·  ★ 2200

- **Source:** [CF 86D · Powerful array](https://codeforces.com/problemset/problem/86/D) — 2200
- **Difficulty:** 2200
- **Problem:** $n, t \le 2\cdot10^5$, $a_i \le 10^6$. For each query $[l, r]$ print $\sum_s K_s^2\cdot s$, where $K_s$ is the number of occurrences of $s$ in the subarray.
- **Thinking from first principles:** the statistic depends on the whole frequency table — no segment-tree merge of two halves is cheaper than merging tables. But adding one $s$ changes $K_s^2 s$ to $(K_s+1)^2 s$:
  a change of $(2K_s + 1)s$, $O(1)$. That is exactly Mo's precondition. $\approx (n + t)\sqrt n \approx 1.8\cdot10^8$ updates in the worst case: inline them and use the odd–even order.

<details><summary>Solution</summary>

Counts live in an array indexed by value (values $\le 10^6$, no compression needed). Answers satisfy $\sum K_s^2 s \le (\max K)\cdot\sum K_s s \le n \cdot n\cdot 10^6 = 4\cdot10^{16}$ → 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, t; cin >> n >> t;
    vector<int> a(n);
    for (auto& x : a) cin >> x;
    vector<int> L(t), R(t), ord(t);
    for (int i = 0; i < t; i++) { cin >> L[i] >> R[i]; L[i]--; R[i]--; }
    int B = max(1, (int)(n / max(1.0, sqrt((double)t))));
    iota(ord.begin(), ord.end(), 0);
    sort(ord.begin(), ord.end(), [&](int x, int y) {
        int bx = L[x] / B, by = L[y] / B;
        if (bx != by) return bx < by;
        return (bx & 1) ? R[x] > R[y] : R[x] < R[y];
    });
    vector<int> cnt(1000001, 0);
    vector<long long> ans(t);
    long long cur = 0;
    int curL = 0, curR = -1;
    for (int id : ord) {
        while (curL > L[id]) { int s = a[--curL]; cur += (2LL * cnt[s] + 1) * s; cnt[s]++; }
        while (curR < R[id]) { int s = a[++curR]; cur += (2LL * cnt[s] + 1) * s; cnt[s]++; }
        while (curL < L[id]) { int s = a[curL++]; cnt[s]--; cur -= (2LL * cnt[s] + 1) * s; }
        while (curR > R[id]) { int s = a[curR--]; cnt[s]--; cur -= (2LL * cnt[s] + 1) * s; }
        ans[id] = cur;
    }
    for (auto v : ans) cout << v << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), t = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        int[] L = new int[t], R = new int[t];
        int B = Math.max(1, (int) (n / Math.max(1.0, Math.sqrt(t))));
        long[] key = new long[t];
        for (int i = 0; i < t; i++) {
            L[i] = in.nextInt() - 1; R[i] = in.nextInt() - 1;
            long b = L[i] / B, rr = (b & 1) == 1 ? (1 << 20) - 1 - R[i] : R[i];
            key[i] = b << 40 | rr << 20 | i;
        }
        Random rnd = new Random(5);
        for (int i = t - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long x = key[i]; key[i] = key[j]; key[j] = x; }
        Arrays.sort(key);
        int[] cnt = new int[1_000_001];
        long[] ans = new long[t];
        long cur = 0;
        int curL = 0, curR = -1;
        for (long k : key) {
            int id = (int) (k & ((1 << 20) - 1));
            while (curL > L[id]) { int s = a[--curL]; cur += (2L * cnt[s] + 1) * s; cnt[s]++; }
            while (curR < R[id]) { int s = a[++curR]; cur += (2L * cnt[s] + 1) * s; cnt[s]++; }
            while (curL < L[id]) { int s = a[curL++]; cnt[s]--; cur -= (2L * cnt[s] + 1) * s; }
            while (curR > R[id]) { int s = a[curR--]; cnt[s]--; cur -= (2L * cnt[s] + 1) * s; }
            ans[id] = cur;
        }
        for (long v : ans) out.println(v);
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
3 2
1 2 1
1 2
1 3
out:
3
6
-->
<!-- test
in:
8 3
1 1 2 2 1 3 1 1
2 7
1 6
2 7
out:
20
20
20
-->
<!-- test
in:
1 1
1000000
1 1
out:
1000000
-->

</details>

### Example 4 — XOR and Favorite Number (Mo on prefix indices)  ·  ★ 2200

- **Source:** [CF 617E · XOR and Favorite Number](https://codeforces.com/problemset/problem/617/E) — 2200
- **Difficulty:** 2200
- **Problem:** $n, m \le 10^5$, $0 \le a_i, k \le 10^6$. For each query $[l, r]$ count pairs $l \le i \le j \le r$ with $a_i \oplus a_{i+1}\oplus\dots\oplus a_j = k$.
- **Thinking from first principles:** subarray xor $= P_j \oplus P_{i-1}$ with prefix xors $P$. So the query counts pairs $x < y$ in the *prefix-index range* $[l-1, r]$ with $P_x \oplus P_y = k$.
  A pair-count is Mo-friendly: adding an index with value $v$ creates `cnt[v ^ k]` new pairs. Values stay below $2^{20}$. Answers reach $\binom{10^5}{2}$ → 64-bit.
  Order of operations matters when $k = 0$: count partners *before* inserting $v$, and remove $v$ *before* subtracting its partners, so an element never pairs with itself.

<details><summary>Solution</summary>

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m, k; cin >> n >> m >> k;
    vector<int> P(n + 1, 0);
    for (int i = 1; i <= n; i++) { int x; cin >> x; P[i] = P[i - 1] ^ x; }
    vector<int> L(m), R(m), ord(m);
    for (int i = 0; i < m; i++) { cin >> L[i] >> R[i]; L[i]--; }       // prefix-index range [l-1, r]
    int N = n + 1, B = max(1, (int)(N / max(1.0, sqrt((double)m))));
    iota(ord.begin(), ord.end(), 0);
    sort(ord.begin(), ord.end(), [&](int x, int y) {
        int bx = L[x] / B, by = L[y] / B;
        if (bx != by) return bx < by;
        return (bx & 1) ? R[x] > R[y] : R[x] < R[y];
    });
    vector<int> cnt(1 << 20, 0);
    vector<long long> ans(m);
    long long cur = 0;
    int curL = 0, curR = -1;
    for (int id : ord) {
        while (curL > L[id]) { int v = P[--curL]; cur += cnt[v ^ k]; cnt[v]++; }
        while (curR < R[id]) { int v = P[++curR]; cur += cnt[v ^ k]; cnt[v]++; }
        while (curL < L[id]) { int v = P[curL++]; cnt[v]--; cur -= cnt[v ^ k]; }
        while (curR > R[id]) { int v = P[curR--]; cnt[v]--; cur -= cnt[v ^ k]; }
        ans[id] = cur;
    }
    for (auto v : ans) cout << v << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), m = in.nextInt(), k = in.nextInt();
        int[] P = new int[n + 1];
        for (int i = 1; i <= n; i++) P[i] = P[i - 1] ^ in.nextInt();
        int[] L = new int[m], R = new int[m];
        int N = n + 1, B = Math.max(1, (int) (N / Math.max(1.0, Math.sqrt(m))));
        long[] key = new long[m];
        for (int i = 0; i < m; i++) {
            L[i] = in.nextInt() - 1; R[i] = in.nextInt();
            long b = L[i] / B, rr = (b & 1) == 1 ? (1 << 20) - 1 - R[i] : R[i];
            key[i] = b << 40 | rr << 20 | i;
        }
        Random rnd = new Random(9);
        for (int i = m - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long x = key[i]; key[i] = key[j]; key[j] = x; }
        Arrays.sort(key);
        int[] cnt = new int[1 << 20];
        long[] ans = new long[m];
        long cur = 0;
        int curL = 0, curR = -1;
        for (long kk : key) {
            int id = (int) (kk & ((1 << 20) - 1));
            while (curL > L[id]) { int v = P[--curL]; cur += cnt[v ^ k]; cnt[v]++; }
            while (curR < R[id]) { int v = P[++curR]; cur += cnt[v ^ k]; cnt[v]++; }
            while (curL < L[id]) { int v = P[curL++]; cnt[v]--; cur -= cnt[v ^ k]; }
            while (curR > R[id]) { int v = P[curR--]; cnt[v]--; cur -= cnt[v ^ k]; }
            ans[id] = cur;
        }
        for (long v : ans) out.println(v);
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
6 2 3
1 2 1 1 0 3
1 6
3 5
out:
7
0
-->
<!-- test
in:
5 3 1
1 1 1 1 1
1 5
2 4
1 1
out:
9
4
1
-->
<!-- test
in:
3 1 0
5 5 0
1 3
out:
3
-->

</details>

### Example 5 — Xenia and Tree (sqrt decomposition on queries)  ·  ★ 2400

- **Source:** [CF 342E · Xenia and Tree](https://codeforces.com/problemset/problem/342/E) — 2400
- **Difficulty:** 2400
- **Problem:** a tree with $n \le 10^5$ vertices; vertex 1 is red, the rest blue. $m \le 10^5$ queries: `1 v` paints $v$ red; `2 v` prints the distance from $v$ to the nearest red vertex.
- **Thinking from first principles:** with no updates, one multi-source BFS from all red vertices answers every query in $O(1)$ — $O(n)$ to build. With updates, rebuilding per paint is $O(nm)$.
  Keep the BFS distances `dist[]` from the last rebuild plus a list of red vertices painted since. A query is `min(dist[v], min over pending u of d(u, v))`, with $d(u, v)$ from an $O(1)$ LCA.
  Rebuild when the list reaches $B$: cost $O(\frac mB n + mB)$ → $B \approx \sqrt n \approx 316$. (Centroid decomposition gives $O(\log^2 n)$ per query — see [centroid decomposition](../10-Trees/05-centroid-decomposition.md).)

<details><summary>Solution</summary>

Euler tour + sparse table for LCA (as in [the sparse-table file](05-sparse-table-and-rmq.md)); the rebuild is an incremental BFS from the pending vertices (distances only decrease).
$O((n + m)\sqrt n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<vector<int>> g(n + 1);
    for (int i = 0; i < n - 1; i++) { int a, b; cin >> a >> b; g[a].push_back(b); g[b].push_back(a); }
    vector<int> dep(n + 1, 0), first(n + 1), par(n + 1, 0), it(n + 1, 0), tour;
    tour.reserve(2 * n);
    vector<int> st = {1}; tour.push_back(1); first[1] = 0;
    while (!st.empty()) {
        int v = st.back();
        if (it[v] < (int)g[v].size()) {
            int u = g[v][it[v]++];
            if (u == par[v]) continue;
            par[u] = v; dep[u] = dep[v] + 1; first[u] = tour.size(); tour.push_back(u); st.push_back(u);
        } else { st.pop_back(); if (!st.empty()) tour.push_back(st.back()); }
    }
    int E = tour.size(), K = 1; while ((1 << K) <= E) K++;
    vector<vector<int>> sp(K, vector<int>(E));
    sp[0] = tour;
    for (int k = 1; k < K; k++)
        for (int i = 0; i + (1 << k) <= E; i++) {
            int x = sp[k - 1][i], y = sp[k - 1][i + (1 << (k - 1))];
            sp[k][i] = dep[x] < dep[y] ? x : y;
        }
    auto dist2 = [&](int u, int v) {
        int l = first[u], r = first[v]; if (l > r) swap(l, r);
        int k = __lg(r - l + 1), x = sp[k][l], y = sp[k][r - (1 << k) + 1];
        int w = dep[x] < dep[y] ? x : y;
        return dep[u] + dep[v] - 2 * dep[w];
    };
    const int INF = INT_MAX / 2;
    vector<int> dist(n + 1, INF), pending = {1}, q(n + 1);
    auto rebuild = [&]() {                                         // BFS from pending reds, relaxing existing distances
        int h = 0, t = 0;
        for (int v : pending) if (dist[v] > 0) { dist[v] = 0; q[t++] = v; }
        while (h < t) {
            int v = q[h++];
            for (int u : g[v]) if (dist[u] > dist[v] + 1) { dist[u] = dist[v] + 1; q[t++] = u; }
        }
        pending.clear();
    };
    rebuild();
    int B = max(1, (int)sqrt(n));
    while (m--) {
        int t, v; cin >> t >> v;
        if (t == 1) { pending.push_back(v); if ((int)pending.size() >= B) rebuild(); }
        else {
            int best = dist[v];
            for (int u : pending) best = min(best, dist2(u, v));
            cout << best << '\n';
        }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] dist, bfsQ, pending; static int pc = 0;
    static void rebuild(int[] head, int[] nxt, int[] to) {     // BFS from pending reds, relaxing existing distances
        int h = 0, t = 0;
        for (int i = 0; i < pc; i++) if (dist[pending[i]] > 0) { dist[pending[i]] = 0; bfsQ[t++] = pending[i]; }
        while (h < t) {
            int v = bfsQ[h++];
            for (int e = head[v]; e != -1; e = nxt[e]) { int u = to[e]; if (dist[u] > dist[v] + 1) { dist[u] = dist[v] + 1; bfsQ[t++] = u; } }
        }
        pc = 0;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), m = in.nextInt();
        int[] head = new int[n + 1], nxt = new int[2 * (n - 1)], to = new int[2 * (n - 1)];
        Arrays.fill(head, -1);
        for (int i = 0; i < n - 1; i++) {
            int a = in.nextInt(), b = in.nextInt();
            to[2 * i] = b; nxt[2 * i] = head[a]; head[a] = 2 * i;
            to[2 * i + 1] = a; nxt[2 * i + 1] = head[b]; head[b] = 2 * i + 1;
        }
        int[] dep = new int[n + 1], first = new int[n + 1], par = new int[n + 1], it = new int[n + 1], tour = new int[2 * n], st = new int[n];
        for (int v = 1; v <= n; v++) it[v] = head[v];
        int E = 0, sp0 = 0;
        st[sp0++] = 1; tour[E++] = 1;
        while (sp0 > 0) {
            int v = st[sp0 - 1];
            if (it[v] != -1) {
                int e = it[v]; it[v] = nxt[e]; int u = to[e];
                if (u == par[v]) continue;
                par[u] = v; dep[u] = dep[v] + 1; first[u] = E; tour[E++] = u; st[sp0++] = u;
            } else { sp0--; if (sp0 > 0) tour[E++] = st[sp0 - 1]; }
        }
        int K = 1; while ((1 << K) <= E) K++;
        int[][] sp = new int[K][];
        sp[0] = Arrays.copyOf(tour, E);
        for (int k = 1; k < K; k++) {
            sp[k] = new int[E - (1 << k) + 1];
            for (int i = 0; i < sp[k].length; i++) {
                int x = sp[k - 1][i], y = sp[k - 1][i + (1 << (k - 1))];
                sp[k][i] = dep[x] < dep[y] ? x : y;
            }
        }
        final int INF = Integer.MAX_VALUE / 2;
        dist = new int[n + 1]; bfsQ = new int[n + 1];
        Arrays.fill(dist, INF);
        int B = Math.max(1, (int) Math.sqrt(n));
        pending = new int[B + 1];
        pending[pc++] = 1;
        rebuild(head, nxt, to);
        while (m-- > 0) {
            int type = in.nextInt(), v = in.nextInt();
            if (type == 1) { pending[pc++] = v; if (pc >= B) rebuild(head, nxt, to); }
            else {
                int best = dist[v];
                for (int i = 0; i < pc; i++) {
                    int u = pending[i], l = Math.min(first[u], first[v]), r = Math.max(first[u], first[v]);
                    int k = 31 - Integer.numberOfLeadingZeros(r - l + 1), x = sp[k][l], y = sp[k][r - (1 << k) + 1];
                    int w = dep[x] < dep[y] ? x : y;
                    best = Math.min(best, dep[u] + dep[v] - 2 * dep[w]);
                }
                out.println(best);
            }
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
5 4
1 2
2 3
2 4
4 5
2 1
2 5
1 2
2 5
out:
0
3
2
-->
<!-- test
in:
2 3
1 2
2 2
1 2
2 2
out:
1
0
-->

</details>

### Example 6 — Machine Learning (Mo with updates)  ·  ★ 2600

- **Source:** [CF 940F · Machine Learning](https://codeforces.com/problemset/problem/940/F) — 2600
- **Difficulty:** 2600
- **Problem:** $n, q \le 10^5$, values $\le 10^9$. `1 l r`: let $c_i$ be the number of occurrences of $i$ in $a[l..r]$; print $\operatorname{mex}\{c_0, c_1, c_2, \dots\}$ (note $c_0 = 0$, so the answer is $\ge 1$). `2 p x`: set $a_p = x$.
- **Thinking from first principles:** the answer depends on the *multiset of counts* — maintain `cnt[value]` and `cc[c]` = how many values occur exactly $c$ times; both change in $O(1)$ per add/remove.
  The mex of counts is small: having counts $1, 2, \dots, m-1$ present needs $1 + \dots + (m-1) \le r - l + 1$ elements, so $m = O(\sqrt n)$ and a linear scan per query is fine.
  Updates force the time dimension: Mo with updates, $B = n^{2/3}$, $O(n^{5/3})$. Compress all values, including those introduced by updates.

<details><summary>Solution</summary>

Precompute for update $j$: position, previous value, new value (by simulating the updates once). Moving time forward applies $j$; backward restores the previous value;
if the position is inside the window, remove the old value and add the new one.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<int> a(n);
    for (auto& x : a) cin >> x;
    struct Qr { int l, r, t, id; };
    vector<Qr> qs; vector<int> up, ux;                             // update positions and new values
    for (int i = 0; i < q; i++) {
        int type, x, y; cin >> type >> x >> y;
        if (type == 1) qs.push_back({x - 1, y - 1, (int)up.size(), (int)qs.size()});
        else { up.push_back(x - 1); ux.push_back(y); }
    }
    vector<int> vals(a.begin(), a.end());
    vals.insert(vals.end(), ux.begin(), ux.end());
    sort(vals.begin(), vals.end()); vals.erase(unique(vals.begin(), vals.end()), vals.end());
    auto id = [&](int v) { return int(lower_bound(vals.begin(), vals.end(), v) - vals.begin()); };
    for (auto& x : a) x = id(x);
    for (auto& x : ux) x = id(x);
    int U = up.size();
    vector<int> uprev(U), cur = a;
    for (int j = 0; j < U; j++) { uprev[j] = cur[up[j]]; cur[up[j]] = ux[j]; }
    int B = max(1, (int)cbrt((double)n * n));
    sort(qs.begin(), qs.end(), [&](const Qr& x, const Qr& y) {
        if (x.l / B != y.l / B) return x.l < y.l;
        if (x.r / B != y.r / B) return x.r < y.r;
        return x.t < y.t;
    });
    vector<int> cnt(vals.size(), 0), cc(n + 2, 0), ans(qs.size());
    auto add = [&](int v) { cc[cnt[v]]--; cnt[v]++; cc[cnt[v]]++; };
    auto rem = [&](int v) { cc[cnt[v]]--; cnt[v]--; cc[cnt[v]]++; };
    int L = 0, R = -1, T = 0;
    for (auto& Q : qs) {
        while (T < Q.t) { int p = up[T]; if (L <= p && p <= R) { rem(a[p]); add(ux[T]); } a[p] = ux[T]; T++; }
        while (T > Q.t) { T--; int p = up[T]; if (L <= p && p <= R) { rem(a[p]); add(uprev[T]); } a[p] = uprev[T]; }
        while (L > Q.l) add(a[--L]);
        while (R < Q.r) add(a[++R]);
        while (L < Q.l) rem(a[L++]);
        while (R > Q.r) rem(a[R--]);
        int mex = 1;
        while (cc[mex] > 0) mex++;
        ans[Q.id] = mex;
    }
    for (int v : ans) cout << v << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] cnt, cc;
    static void add(int v) { cc[cnt[v]]--; cnt[v]++; cc[cnt[v]]++; }
    static void rem(int v) { cc[cnt[v]]--; cnt[v]--; cc[cnt[v]]++; }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        int[] ql = new int[q], qr = new int[q], qt = new int[q], up = new int[q], ux = new int[q];
        int Q = 0, U = 0;
        for (int i = 0; i < q; i++) {
            int type = in.nextInt(), x = in.nextInt(), y = in.nextInt();
            if (type == 1) { ql[Q] = x - 1; qr[Q] = y - 1; qt[Q] = U; Q++; }
            else { up[U] = x - 1; ux[U] = y; U++; }
        }
        int[] vals = new int[n + U];
        System.arraycopy(a, 0, vals, 0, n); System.arraycopy(ux, 0, vals, n, U);
        Random rnd = new Random(11);
        for (int i = vals.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = vals[i]; vals[i] = vals[j]; vals[j] = t; }
        Arrays.sort(vals);
        int V = 0;
        for (int i = 0; i < vals.length; i++) if (i == 0 || vals[i] != vals[i - 1]) vals[V++] = vals[i];
        for (int i = 0; i < n; i++) a[i] = Arrays.binarySearch(vals, 0, V, a[i]);
        for (int j = 0; j < U; j++) ux[j] = Arrays.binarySearch(vals, 0, V, ux[j]);
        int[] uprev = new int[U], cur = a.clone();
        for (int j = 0; j < U; j++) { uprev[j] = cur[up[j]]; cur[up[j]] = ux[j]; }
        int B = Math.max(1, (int) Math.cbrt((double) n * n));
        long[] key = new long[Q];
        for (int i = 0; i < Q; i++) key[i] = (long) (ql[i] / B) << 50 | (long) (qr[i] / B) << 40 | (long) qt[i] << 20 | i;
        for (int i = Q - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = key[i]; key[i] = key[j]; key[j] = t; }
        Arrays.sort(key);
        cnt = new int[V]; cc = new int[n + 2];
        int[] ans = new int[Q];
        int L = 0, R = -1, T = 0;
        for (long k : key) {
            int id = (int) (k & ((1 << 20) - 1));
            while (T < qt[id]) { int p = up[T]; if (L <= p && p <= R) { rem(a[p]); add(ux[T]); } a[p] = ux[T]; T++; }
            while (T > qt[id]) { T--; int p = up[T]; if (L <= p && p <= R) { rem(a[p]); add(uprev[T]); } a[p] = uprev[T]; }
            while (L > ql[id]) add(a[--L]);
            while (R < qr[id]) add(a[++R]);
            while (L < ql[id]) rem(a[L++]);
            while (R > qr[id]) rem(a[R--]);
            int mex = 1;
            while (cc[mex] > 0) mex++;
            ans[id] = mex;
        }
        for (int i = 0; i < Q; i++) out.println(ans[i]);
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

Note `cc[0]` is decremented below zero by the first `add` of each value; it is never read (the mex scan starts at 1), so it does not matter.

<!-- test
in:
10 4
1 2 3 1 1 2 2 2 9 9
1 1 1
1 2 8
2 7 1
1 2 8
out:
2
3
2
-->
<!-- test
in:
1 3
1000000000
1 1 1
2 1 5
1 1 1
out:
2
2
-->
<!-- test
in:
6 3
4 4 5 5 5 6
1 1 6
2 6 5
1 1 6
out:
4
1
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Compute $B$ from the actual costs.** Mo: $B = n/\sqrt q$ (not $\sqrt n$ when $q \ll n$). Mo with updates: $B = n^{2/3}$. Thresholds: equalise the two sides, including log factors.
2. **Expand before shrinking** in Mo, or counters go negative (and `cc[-1]` crashes).
3. **Odd–even ordering** is free speed; Hilbert order is more but needs a careful implementation.
4. **Inline add/remove** in hot Mo loops; avoid `std::function` and Java interfaces there. Use arrays indexed by (compressed) value, never `map`/`HashMap`.
5. **Java query sorting**: pack `(block, r', id)` into a `long` and sort primitives after a shuffle — sorting `Integer[]` with a comparator is several times slower.
6. **Compress values** for count arrays when values reach $10^9$; for Mo with updates include the updated values in the compression.
7. **Mo with updates time pointer**: store the *previous* value of each update when simulating them once; reverting uses it. Apply to the array even when the position is outside the window.
8. **Prefix-index transformations** (Example 4) shift ranges by one; write $[l-1, r]$ explicitly and allocate $n + 1$ positions.
9. **Thresholds with modulus 0 residue**: in 1207F, $i \equiv 0 \pmod x$ starts at $x$, not 0 (indices are 1-based).
10. **Rebuild-every-$B$** structures: after a rebuild clear the pending list; when the rebuild is incremental (BFS relaxation), seed it with the pending items only.
11. **Mo is offline.** "Forced online" (answers xor-encoded into the next query) rules it out; switch to persistent structures or blocks with precomputed answers between block boundaries.
12. **Memory of per-block tables** (e.g. `small[x][y]` up to $T$) is $O(T^2)$ — check it fits, especially with 64-bit cells in Java.

## 7. Going further (toward 2400–2600+)

- **Mo on trees** (Euler tour with toggling, LCA special case): [CF 375D · Tree and Queries](https://codeforces.com/problemset/problem/375/D) — 2400 is a subtree version (no Mo needed with small-to-large, but Mo works).
- **Block-based "jump" structures** with $O(\sqrt n)$ updates: [CF 13E · Holes](https://codeforces.com/problemset/problem/13/E) — 2700.
- **Threshold on frequency** for range "count of values appearing exactly $k$ times" and **randomised** alternatives: [CF 1514D · Cut and Stick](https://codeforces.com/problemset/problem/1514/D) — 2000, [CF 840D · Destiny](https://codeforces.com/problemset/problem/840/D) — 2500.
- **Rollback Mo** ("Mo without removals") for statistics that support add but not remove (max, union-find): sort as usual, rebuild from the block boundary for each query's left part and roll back. See [advanced sqrt techniques](../16-IGM-Frontier/06-advanced-sqrt-techniques.md).
- **Sqrt on queries with heavy precomputation**: [CF 103D · Time to Raid Cowavans](https://codeforces.com/problemset/problem/103/D) — 2100 (offline by step size, like Example 1).
- **Bitset + sqrt** combinations for $O(n^2/64)$-style problems: [bitset optimisation](../16-IGM-Frontier/05-bitset-optimization.md).

## 8. Practice ladder

**1800–2100**
- [ ] [CF 220B · Little Elephant and Array](https://codeforces.com/problemset/problem/220/B) — 1800
- [ ] [CSES 1734 · Distinct Values Queries](https://cses.fi/problemset/task/1734) (solve it with Mo, then with a BIT)
- [ ] [CF 797E · Array Queries](https://codeforces.com/problemset/problem/797/E) — 2000
- [ ] [CF 1514D · Cut and Stick](https://codeforces.com/problemset/problem/1514/D) — 2000
- [ ] [CF 1207F · Remainder Problem](https://codeforces.com/problemset/problem/1207/F) — 2100
- [ ] [CF 103D · Time to Raid Cowavans](https://codeforces.com/problemset/problem/103/D) — 2100

**2100–2400**
- [ ] [CF 86D · Powerful array](https://codeforces.com/problemset/problem/86/D) — 2200
- [ ] [CF 617E · XOR and Favorite Number](https://codeforces.com/problemset/problem/617/E) — 2200
- [ ] [CF 342E · Xenia and Tree](https://codeforces.com/problemset/problem/342/E) — 2400
- [ ] [CF 375D · Tree and Queries](https://codeforces.com/problemset/problem/375/D) — 2400
- [ ] [CF 1000F · One Occurrence](https://codeforces.com/problemset/problem/1000/F) — 2400

**2400+**
- [ ] [CF 840D · Destiny](https://codeforces.com/problemset/problem/840/D) — 2500
- [ ] [CF 940F · Machine Learning](https://codeforces.com/problemset/problem/940/F) — 2600
- [ ] [CF 13E · Holes](https://codeforces.com/problemset/problem/13/E) — 2700

## 9. LeetCode / FAANG cross-reference

- [LC 1157 · Online Majority Element In Subarray](https://leetcode.com/problems/online-majority-element-in-subarray/) — Hard — threshold idea: values with frequency $\ge \sqrt n$ are few (check each with prefix counts); otherwise brute force a short range. Randomised sampling also works.
- [LC 1508 · Range Sum of Sorted Subarray Sums](https://leetcode.com/problems/range-sum-of-sorted-subarray-sums/) — Medium — $n \le 1000$ makes $O(n^2\log n)$ fine; illustrates reading constraints before reaching for structures.
- [LC 327 · Count of Range Sum](https://leetcode.com/problems/count-of-range-sum/) — Hard — offline counting; a BIT is the intended tool, Mo is overkill.

Rare in interviews: sqrt decomposition and Mo essentially never appear; the transferable skill is the *balancing argument* when discussing trade-offs.

## 10. Self-check

1. Derive Mo's complexity $O(n^2/B + qB)$ and the optimal $B$.
2. Why does the odd–even trick help, and by roughly how much?
3. In Mo with updates, why is $B = n^{2/3}$, and what is the total complexity?
4. Give the cost formula for "sqrt on queries" and explain what the correction step must support.
5. In Example 2, why is $T = \sqrt N$ optimal, and what are the per-operation costs?
6. Why is the mex of counts in a window of length $L$ at most $O(\sqrt L)$?
7. When should you *not* use Mo even though it fits?

<details><summary>Answers</summary>

1. Right pointer: monotone within each of $n/B$ left-blocks, $O(n)$ each → $O(n^2/B)$. Left pointer: $O(B)$ per query → $O(qB)$. Equalise: $B = n/\sqrt q$, total $O(n\sqrt q)$.
2. Without it, after each block the right pointer jumps from $\approx n$ back to the left; alternating direction lets it sweep back, saving about half of the right-pointer movement.
3. Time moves $O(q)$ per (left-block, right-block) pair: $O(q n^2/B^2)$; left/right move $O(B)$ per query plus $O(n)$ per block change: $O(qB + n^2/B)$. Balance at $B = n^{2/3}$: $O(n^{5/3})$ for $q \approx n$.
4. $O(\frac qB R + qB c)$ with rebuild cost $R$ and correction cost $c$ per pending update; the static answer must be combinable with each pending update independently (e.g. min of distances).
5. Update $O(T)$ (one residue per small modulus), large-modulus query $O(N/T)$; equal at $T = \sqrt N$, giving $O(q\sqrt N)$.
6. Mex $m$ requires counts $1..m-1$ to appear for distinct values, which needs at least $1 + 2 + \dots + (m-1) = m(m-1)/2 \le L$ elements.
7. When the statistic is mergeable (segment tree in $O(\log n)$), when queries are forced online, or when an $O(\log n)$ offline sweep (BIT by right endpoint) exists.

</details>
