# The Contribution Technique (Swapping the Order of Summation)

> **Band:** 🔵 1400 – 🟣 2100 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [binomials](01-counting-principles-and-binomials.md), [monotonic stack](../02-Core-Techniques/04-monotonic-stack-and-deque.md), [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md)
> **You can say you know this when:** faced with "sum over all subarrays / subsets / pairs / paths of $f$", your first move is "how much does each element (or bit, or edge) contribute, and in how many structures?", and you can do subarray min/max sums with correct tie-breaking, subset max–min sums, pairwise distance sums and bitwise pair sums in $O(n\log)$ or better.

---

## 1. First principles — why this works

### 1.1 One identity

Almost every "sum over exponentially or quadratically many structures" collapses by exchanging two sums. If each structure $S$ (subarray, subset, pair, path, permutation…) has value $f(S) = \sum_{e\in S} w(e, S)$ built from elements $e$, then

$$\sum_{S} f(S) = \sum_{S}\sum_{e \in S} w(e,S) = \sum_{e}\ \sum_{S \ni e} w(e, S).$$

When $w$ depends only on $e$ (sums), the inner sum is $w(e)\cdot\#\lbrace S \ni e\rbrace$ — a pure counting question. When $f$ is a **max or min**, rewrite it as a sum first: $\max(S) = \sum_{e} a_e\cdot[e \text{ is the (designated) maximum of } S]$, and count the structures in which $e$ is the maximum. When $f$ is a bitwise operation, split it into bits: $x = \sum_b 2^b[\text{bit } b \text{ of } x]$, and each bit is a 0/1 quantity you can count.

This is the same identity as **linearity of expectation** ([probability §1.2](06-probability-and-expected-value.md)) — expected values are contribution sums divided by the number of structures — and as **double counting** ([counting §1.1](01-counting-principles-and-binomials.md)).

### 1.2 Counting the structures that contain an element

| Structure | # containing position $i$ (1-indexed, length $n$) | Why |
|---|---|---|
| subarray $[l, r]$ | $i\,(n - i + 1)$ | choose $l \le i$ ($i$ ways), $r \ge i$ ($n - i + 1$ ways) |
| subset | $2^{n-1}$ | include $i$; the rest free |
| subset of size $k$ | $\binom{n-1}{k-1}$ | choose the other $k - 1$ |
| subsequence pair positions $i < j$ both in a $k$-subset | $\binom{n-2}{k-2}$ | |
| subarray containing both $i < j$ | $i\,(n - j + 1)$ | |
| permutation with element $x$ at position $p$ | $(n-1)!$ | |
| tree path through edge $e$ splitting sizes $s, n - s$ | $s\,(n - s)$ | choose an endpoint on each side |

### 1.3 Max and min need a tie-breaking rule

"$a_i$ is the minimum of subarray $[l, r]$" is ambiguous when values repeat — counting naively double-counts subarrays with two equal minima. Fix a rule: **the minimum is the leftmost minimal element**. Then $a_i$ is *the* minimum of $[l, r]$ iff $l > L_i$ and $r < R_i$, where $L_i$ is the last index $< i$ with $a_{L_i} \le a_i$ (a value that would take precedence or tie on the left) and $R_i$ the first index $> i$ with $a_{R_i} < a_i$ (strictly smaller on the right). So

$$\sum_{l\le r}\min(a_l..a_r) = \sum_i a_i\,(i - L_i)(R_i - i),$$

and $L_i, R_i$ come from a [monotonic stack](../02-Core-Techniques/04-monotonic-stack-and-deque.md) in $O(n)$. Use $\le$ on one side and $<$ on the other — never the same on both.

For subsets the order is free: **sort**, break ties by index, and $a_i$ (0-indexed in sorted order) is the maximum of exactly the subsets of $\lbrace a_0..a_{i-1}\rbrace$ with $a_i$ added: $2^i$ of them, or $\binom{i}{k-1}$ of size $k$.

---

## 2. Formulas, definitions and identities

| Quantity | Formula | Proof sketch |
|---|---|---|
| $\sum_{\text{subarrays}}\text{sum}$ | $\sum_i a_i\,i(n-i+1)$ | §1.2 |
| $\sum_{\text{subsets}}\text{sum}$ | $2^{n-1}\sum_i a_i$ | §1.2 |
| $\sum_{\lvert S\rvert = k}\text{sum}$ | $\binom{n-1}{k-1}\sum_i a_i$ | §1.2 |
| $\sum_{\text{subarrays}}\min$ | $\sum_i a_i(i - L_i)(R_i - i)$ | §1.3; $\max$ symmetric |
| $\sum_{\text{subarrays}}(\max - \min)$ | difference of the two | |
| $\sum_{\text{subsets}}\max$ (sorted asc, 0-indexed) | $\sum_i a_i 2^i$; $\min$: $\sum_i a_i2^{n-1-i}$ | §1.3 |
| $\sum_{\lvert S\rvert=k}(\max - \min)$ | $\sum_i a_i\left(\binom{i}{k-1} - \binom{n-1-i}{k-1}\right)$ | §1.3 |
| $\sum_{i<j}\lvert a_i - a_j\rvert$ (sorted, 0-indexed) | $\sum_i a_i\,(2i - n + 1)$ | $a_i$ is the larger in $i$ pairs, the smaller in $n - 1 - i$ |
| $\sum_{i<j}a_ia_j$ | $\frac{(\sum a)^2 - \sum a^2}{2}$ | expand the square |
| $\sum_{i<j}(a_i \oplus a_j)$ | $\sum_b 2^b\,c_b(n - c_b)$ | a pair has bit $b$ set iff exactly one has it; $c_b$ = count with bit $b$ |
| $\sum_{i<j}(a_i \mathbin\& a_j)$, $(a_i \mathbin| a_j)$ | $\sum_b 2^b\binom{c_b}{2}$; $\sum_b 2^b\left(\binom n2 - \binom{n-c_b}{2}\right)$ | both / at least one |
| $\sum_{l\le r}\bigoplus_{k=l}^{r}a_k$ | per bit: #pairs of prefix-xor indices $i<j$ with different bit $b$ | $\bigoplus_{l..r} = P_r \oplus P_{l-1}$ |
| $\sum_{\text{pairs } u<v}\operatorname{dist}(u,v)$ on a tree | $\sum_{\text{edges}} s_e(n - s_e)$ | §1.2 |
| $\sum_{\text{subarrays}}\text{length}$ | $\sum_{k=1}^{n}k(n-k+1) = \binom{n+2}{3}$ | hockey stick |
| $\sum_{\text{perms}}(\text{fixed points}) = n!$ | each $i$ is fixed in $(n-1)!$ perms | |
| $\sum_{\text{perms}}\text{inversions} = n!\binom n2/2$ | each pair inverted in half | |
| expectation = contribution sum / #structures | linearity | [probability](06-probability-and-expected-value.md) |

**Complexity.** Most formulas are $O(n)$ after sorting ($O(n\log n)$) or a monotonic stack ($O(n)$); bitwise ones are $O(n\log A)$.

---

## 3. Implementation (C++ and Java)

```cpp
// Subarray min/max sums (monotonic stacks), pairwise |difference| sum, subset max-min sum, XOR pair sum, tree distance sum.
long long sum_subarray_min(const vector<long long> &a) {     // exact; caller ensures no overflow
    int n = a.size();
    vector<int> L(n), R(n), st;
    for (int i = 0; i < n; i++) {                            // L[i]: last j < i with a[j] <= a[i]
        while (!st.empty() && a[st.back()] > a[i]) st.pop_back();
        L[i] = st.empty() ? -1 : st.back();
        st.push_back(i);
    }
    st.clear();
    for (int i = n - 1; i >= 0; i--) {                       // R[i]: first j > i with a[j] < a[i]
        while (!st.empty() && a[st.back()] >= a[i]) st.pop_back();
        R[i] = st.empty() ? n : st.back();
        st.push_back(i);
    }
    long long s = 0;
    for (int i = 0; i < n; i++) s += a[i] * (long long)(i - L[i]) * (R[i] - i);
    return s;
}
long long sum_subarray_max(vector<long long> a) {            // max = -min(-a)
    for (auto &x : a) x = -x;
    return -sum_subarray_min(a);
}
long long sum_pairwise_abs(vector<long long> a) {
    sort(a.begin(), a.end());
    long long s = 0, n = a.size();
    for (long long i = 0; i < n; i++) s += a[i] * (2 * i - n + 1);
    return s;
}
long long sum_pair_xor(const vector<long long> &a) {         // values < 2^30, n <= ~1e5 to stay in 64-bit
    long long s = 0, n = a.size();
    for (int b = 0; b < 31; b++) {
        long long c = 0;
        for (long long x : a) c += x >> b & 1;
        s += (1LL << b) * c * (n - c);
    }
    return s;
}
long long tree_distance_sum(int n, const vector<vector<int>> &g) {   // vertices 0..n-1, iterative DFS
    vector<int> parent(n, -1), order; order.reserve(n);
    vector<int> st = {0}; parent[0] = 0;
    while (!st.empty()) { int v = st.back(); st.pop_back(); order.push_back(v); for (int u : g[v]) if (parent[u] == -1) { parent[u] = v; st.push_back(u); } }
    vector<long long> sz(n, 1); long long s = 0;
    for (int k = n - 1; k > 0; k--) { int v = order[k]; sz[parent[v]] += sz[v]; s += sz[v] * (n - sz[v]); }
    return s;
}
```

```java
// Subarray min/max sums (monotonic stacks), pairwise |difference| sum, subset max-min sum, XOR pair sum, tree distance sum.
static long sumSubarrayMin(long[] a) {
    int n = a.length;
    int[] L = new int[n], R = new int[n], st = new int[n]; int top = 0;
    for (int i = 0; i < n; i++) {
        while (top > 0 && a[st[top - 1]] > a[i]) top--;
        L[i] = top == 0 ? -1 : st[top - 1];
        st[top++] = i;
    }
    top = 0;
    for (int i = n - 1; i >= 0; i--) {
        while (top > 0 && a[st[top - 1]] >= a[i]) top--;
        R[i] = top == 0 ? n : st[top - 1];
        st[top++] = i;
    }
    long s = 0;
    for (int i = 0; i < n; i++) s += a[i] * (long) (i - L[i]) * (R[i] - i);
    return s;
}
static long sumSubarrayMax(long[] a) {
    long[] b = new long[a.length];
    for (int i = 0; i < a.length; i++) b[i] = -a[i];
    return -sumSubarrayMin(b);
}
static long sumPairwiseAbs(long[] a) {
    long[] b = a.clone(); Arrays.sort(b);                  // primitive sort = dual-pivot quicksort: shuffle first if input can be adversarial
    long s = 0, n = b.length;
    for (int i = 0; i < n; i++) s += b[i] * (2L * i - n + 1);
    return s;
}
static long sumPairXor(long[] a) {
    long s = 0, n = a.length;
    for (int bit = 0; bit < 31; bit++) {
        long c = 0;
        for (long x : a) c += x >> bit & 1;
        s += (1L << bit) * c * (n - c);
    }
    return s;
}
static long treeDistanceSum(int n, List<List<Integer>> g) {
    int[] parent = new int[n], order = new int[n], st = new int[n];
    Arrays.fill(parent, -1);
    int top = 0, cnt = 0; st[top++] = 0; parent[0] = 0;
    while (top > 0) { int v = st[--top]; order[cnt++] = v; for (int u : g.get(v)) if (parent[u] == -1) { parent[u] = v; st[top++] = u; } }
    long[] sz = new long[n]; Arrays.fill(sz, 1); long s = 0;
    for (int k = n - 1; k > 0; k--) { int v = order[k]; sz[parent[v]] += sz[v]; s += sz[v] * (n - sz[v]); }
    return s;
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "sum over all subarrays / subsequences / subsets / pairs of …" | contribution of each element; never enumerate structures |
| … of min / max / range (max − min) | monotonic stack with asymmetric tie rule (Example 3) |
| … over subsets of a fixed size of max − min | sort, binomial counts (Example 2) |
| sum of distances between all pairs (1D, 2D Manhattan, tree) | sort per coordinate / edge sizes (Example 1) |
| XOR / AND / OR over pairs or subarrays | per-bit counting with prefix parities (Example 4) |
| expected value over random structures | contribution × probability (Example 5) |
| a weight that depends on the structure's length or position | carry sums of indices along with counts (Example 4) |
| "count pairs (structure, element) with property" | double counting |

Common confusion: contribution works on **sums**. A product over a structure becomes a sum only after taking logs, or via DP — and "number of distinct values" needs a tie rule like "count each value at its first occurrence" (LC 828 / 2262).

---

## 5. Worked examples (graded)

### Example 1 — Weird Sum  ·  ★ 1400

- **Source:** [CF 1648A · Weird Sum](https://codeforces.com/problemset/problem/1648/A) — 1400
- **Difficulty:** 1400
- **Problem:** An $n\times m$ grid ($nm \le 10^5$) of colours $c_{ij} \le 10^5$. Print the sum, over all unordered pairs of cells with the same colour, of their Manhattan distance.
- **Thinking from first principles:** $O((nm)^2)$ pairs is $10^{10}$. Manhattan distance separates: $\lvert r_1 - r_2\rvert + \lvert c_1 - c_2\rvert$, so the total is (sum of row differences) + (sum of column differences), per colour. Each is a 1D "sum of pairwise absolute differences": sort and use $\sum_i x_i(2i - k + 1)$ (§2). Rows and columns come pre-sorted if we scan the grid in row-major order (for rows) and column-major order (for columns).

<details><summary>Solution</summary>

Bucket coordinates by colour in the two scan orders, apply the formula. $O(nm)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<vector<int>> c(n, vector<int>(m));
    for (auto &row : c) for (auto &x : row) cin >> x;
    const int C = 100000;
    vector<vector<long long>> rows(C + 1), cols(C + 1);
    for (int i = 0; i < n; i++) for (int j = 0; j < m; j++) rows[c[i][j]].push_back(i);   // non-decreasing
    for (int j = 0; j < m; j++) for (int i = 0; i < n; i++) cols[c[i][j]].push_back(j);   // non-decreasing
    long long ans = 0;
    auto add = [&](const vector<long long> &v) { long long k = v.size(); for (long long i = 0; i < k; i++) ans += v[i] * (2 * i - k + 1); };
    for (int col = 1; col <= C; col++) { add(rows[col]); add(cols[col]); }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = nextInt(in), m = nextInt(in);
        int[][] c = new int[n][m];
        final int C = 100000;
        int[] cnt = new int[C + 1];
        for (int i = 0; i < n; i++) for (int j = 0; j < m; j++) { c[i][j] = nextInt(in); cnt[c[i][j]]++; }
        int[] start = new int[C + 2];
        for (int col = 1; col <= C; col++) start[col + 1] = start[col] + cnt[col];
        long[] rows = new long[n * m], cols = new long[n * m];
        int[] pr = Arrays.copyOf(start, C + 2), pc = Arrays.copyOf(start, C + 2);
        for (int i = 0; i < n; i++) for (int j = 0; j < m; j++) rows[pr[c[i][j]]++] = i;
        for (int j = 0; j < m; j++) for (int i = 0; i < n; i++) cols[pc[c[i][j]]++] = j;
        long ans = 0;
        for (int col = 1; col <= C; col++) {
            long k = cnt[col];
            for (long t = 0; t < k; t++) {
                ans += rows[(int) (start[col] + t)] * (2 * t - k + 1);
                ans += cols[(int) (start[col] + t)] * (2 * t - k + 1);
            }
        }
        System.out.println(ans);
    }
    private static int nextInt(DataInputStream in) throws IOException {
        int r = 0, b = in.read();
        while (b < '0') b = in.read();
        while (b >= '0') { r = r * 10 + b - '0'; b = in.read(); }
        return r;
    }
}
```

</details>

<!-- test
in:
2 3
1 2 3
3 2 1
out:
7
-->
<!-- test
in:
3 4
1 1 2 2
2 1 1 2
2 2 1 1
out:
76
-->
<!-- test
in:
4 4
1 1 2 3
2 1 1 2
3 1 2 1
1 1 2 1
out:
129
-->
<!-- test
in:
1 1
5
out:
0
-->

### Example 2 — Max-Min Sums  ·  ★ ≈1400 (est.)

- **Source:** [AtCoder ABC151 E · Max-Min Sums](https://atcoder.jp/contests/abc151/tasks/abc151_e)
- **Difficulty:** ≈1400 (est.; AtCoder Problems diff ≈1344)
- **Problem:** $N \le 10^5$ integers ($\lvert A_i\rvert \le 10^9$) and $K \le N$. Over all $\binom NK$ choices of $K$ elements (by index), sum $\max - \min$, modulo $10^9+7$.
- **Thinking from first principles:** Split: $\sum\max - \sum\min$. Sort ascending (ties by index): $A_i$ is the maximum of a $K$-subset iff the other $K - 1$ elements come from the $i$ elements before it — $\binom{i}{K-1}$ subsets; minimum iff they come from the $N - 1 - i$ after it. So the answer is $\sum_i A_i\bigl(\binom i{K-1} - \binom{N-1-i}{K-1}\bigr)$. Values are negative: reduce with $((x \bmod p) + p) \bmod p$.

<details><summary>Solution</summary>

Sort, factorials to $N$, one pass. $O(N\log N)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
long long power(long long a, long long e) { long long r = 1; a %= MOD; for (; e; e >>= 1, a = a * a % MOD) if (e & 1) r = r * a % MOD; return r; }
int main() {
    int n, k; cin >> n >> k;
    vector<long long> a(n);
    for (auto &x : a) cin >> x;
    sort(a.begin(), a.end());
    vector<long long> f(n + 1), fi(n + 1);
    f[0] = 1;
    for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
    fi[n] = power(f[n], MOD - 2);
    for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
    auto C = [&](int x, int y) -> long long { return (y < 0 || y > x) ? 0 : f[x] * fi[y] % MOD * fi[x - y] % MOD; };
    long long ans = 0;
    for (int i = 0; i < n; i++) {
        long long coef = (C(i, k - 1) - C(n - 1 - i, k - 1) + MOD) % MOD;
        long long v = (a[i] % MOD + MOD) % MOD;
        ans = (ans + v * coef) % MOD;
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 1_000_000_007L;
    static long[] f, fi;
    static long power(long a, long e) { long r = 1; a %= MOD; for (; e > 0; e >>= 1, a = a * a % MOD) if ((e & 1) == 1) r = r * a % MOD; return r; }
    static long C(int x, int y) { return (y < 0 || y > x) ? 0 : f[x] * fi[y] % MOD * fi[x - y] % MOD; }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int n = Integer.parseInt(st.nextToken()), k = Integer.parseInt(st.nextToken());
        st = new StringTokenizer(br.readLine());
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = Long.parseLong(st.nextToken());
        Arrays.sort(a);
        f = new long[n + 1]; fi = new long[n + 1]; f[0] = 1;
        for (int i = 1; i <= n; i++) f[i] = f[i - 1] * i % MOD;
        fi[n] = power(f[n], MOD - 2);
        for (int i = n; i > 0; i--) fi[i - 1] = fi[i] * i % MOD;
        long ans = 0;
        for (int i = 0; i < n; i++) {
            long coef = (C(i, k - 1) - C(n - 1 - i, k - 1) + MOD) % MOD;
            ans = (ans + Math.floorMod(a[i], MOD) * coef) % MOD;
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
4 2
1 1 3 4
out:
11
-->
<!-- test
in:
6 3
10 10 10 -10 -10 -10
out:
360
-->
<!-- test
in:
3 1
1 1 1
out:
0
-->
<!-- test
in:
10 6
1000000000 1000000000 1000000000 1000000000 1000000000 0 0 0 0 0
out:
999998537
-->

### Example 3 — Sum of ranges over all subarrays  ·  ★ ≈1800 (est.)

- **Source:** Original problem (the large-$n$ version of [LC 2104 · Sum of Subarray Ranges](https://leetcode.com/problems/sum-of-subarray-ranges/) — Medium)
- **Difficulty:** ≈1800 (est.)
- **Problem:** $n \le 10^5$, $0 \le a_i \le 10^9$. Print $\sum_{l \le r}\bigl(\max(a_l..a_r) - \min(a_l..a_r)\bigr)$ (fits in signed 64-bit).
- **Thinking from first principles:** $\sum(\max - \min) = \sum\max - \sum\min$ — two contribution sums. For the minimum, $a_i$ "owns" the subarrays where it is the leftmost minimum: $l \in (L_i, i]$, $r \in [i, R_i)$ with $L_i$ = previous index with value $\le a_i$ and $R_i$ = next index with value $< a_i$ (§1.3). Each is found with a monotonic stack. The maximum is the same on $-a$.

<details><summary>Solution</summary>

Two stack passes per extremum; $O(n)$. The answer is at most $\frac{n(n+1)}{2}\cdot10^9 \approx 5\cdot10^{18}$, within `long long`; the partial sums of maxima alone stay below that bound too.

```cpp
#include <bits/stdc++.h>
using namespace std;
long long sum_min(const vector<long long> &a) {
    int n = a.size();
    vector<int> L(n), R(n), st;
    for (int i = 0; i < n; i++) { while (!st.empty() && a[st.back()] > a[i]) st.pop_back(); L[i] = st.empty() ? -1 : st.back(); st.push_back(i); }
    st.clear();
    for (int i = n - 1; i >= 0; i--) { while (!st.empty() && a[st.back()] >= a[i]) st.pop_back(); R[i] = st.empty() ? n : st.back(); st.push_back(i); }
    long long s = 0;
    for (int i = 0; i < n; i++) s += a[i] * (long long)(i - L[i]) * (R[i] - i);
    return s;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long long> a(n), b(n);
    for (int i = 0; i < n; i++) { cin >> a[i]; b[i] = -a[i]; }
    cout << -sum_min(b) - sum_min(a) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long sumMin(long[] a) {
        int n = a.length;
        int[] L = new int[n], R = new int[n], st = new int[n]; int top = 0;
        for (int i = 0; i < n; i++) { while (top > 0 && a[st[top - 1]] > a[i]) top--; L[i] = top == 0 ? -1 : st[top - 1]; st[top++] = i; }
        top = 0;
        for (int i = n - 1; i >= 0; i--) { while (top > 0 && a[st[top - 1]] >= a[i]) top--; R[i] = top == 0 ? n : st[top - 1]; st[top++] = i; }
        long s = 0;
        for (int i = 0; i < n; i++) s += a[i] * (long) (i - L[i]) * (R[i] - i);
        return s;
    }
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) nextLong(in);
        long[] a = new long[n], b = new long[n];
        for (int i = 0; i < n; i++) { a[i] = nextLong(in); b[i] = -a[i]; }
        System.out.println(-sumMin(b) - sumMin(a));
    }
    private static long nextLong(DataInputStream in) throws IOException {
        long r = 0; int b = in.read();
        while (b < '0') b = in.read();
        while (b >= '0') { r = r * 10 + b - '0'; b = in.read(); }
        return r;
    }
}
```

</details>

<!-- test
in:
3
1 2 3
out:
4
-->
<!-- test
in:
3
1 3 3
out:
4
-->
<!-- test
in:
4
7 7 7 7
out:
0
-->
<!-- test
in:
6
5 1 4 1 5 9
out:
73
-->

### Example 4 — Sum of XOR Functions  ·  ★ 1700

- **Source:** [CF 1879D · Sum of XOR Functions](https://codeforces.com/problemset/problem/1879/D) — 1700
- **Difficulty:** 1700
- **Problem:** $n \le 3\cdot10^5$, $a_i \le 10^9$. Print $\sum_{1\le l\le r\le n}f(l, r)\cdot(r - l + 1) \bmod 998244353$, where $f(l, r) = a_l \oplus \dots \oplus a_r$.
- **Thinking from first principles:** With prefix XORs $P_0 = 0$, $P_r = a_1\oplus\dots\oplus a_r$, a subarray $(l, r)$ is a pair of prefix indices $i = l - 1 < j = r$, with $f = P_i \oplus P_j$ and length $j - i$. Split into bits: bit $b$ contributes $2^b(j - i)$ exactly when $P_i$ and $P_j$ differ in bit $b$. Sweep $j$ and keep, for each bit value $v \in \lbrace 0, 1\rbrace$, the count and the sum of earlier indices $i$ with that bit: the contribution of $j$ is $2^b(\text{cnt}\cdot j - \text{sumIdx})$ over the opposite group.

<details><summary>Solution</summary>

$O(n\log A)$. Index sums reach $\sim 4.5\cdot10^{10}$ — keep them exact in 64-bit, reduce when multiplying.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 998244353LL;
int main() {
    int n; scanf("%d", &n);
    vector<long long> a(n);
    for (auto &x : a) scanf("%lld", &x);
    long long ans = 0;
    for (int b = 0; b < 30; b++) {
        long long cnt[2] = {1, 0}, sumIdx[2] = {0, 0};   // prefix index 0 has P_0 = 0
        int cur = 0; long long add = 0;
        for (int j = 1; j <= n; j++) {
            cur ^= (a[j - 1] >> b) & 1;
            int o = cur ^ 1;
            add = (add + (cnt[o] % MOD * j - sumIdx[o] % MOD + MOD) % MOD) % MOD;
            cnt[cur]++; sumIdx[cur] += j;
        }
        ans = (ans + add * ((1LL << b) % MOD)) % MOD;
    }
    printf("%lld\n", ans);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final long MOD = 998244353L;
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) nextLong(in);
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = nextLong(in);
        long ans = 0;
        for (int b = 0; b < 30; b++) {
            long[] cnt = {1, 0}, sumIdx = {0, 0};
            int cur = 0; long add = 0;
            for (int j = 1; j <= n; j++) {
                cur ^= (int) ((a[j - 1] >> b) & 1);
                int o = cur ^ 1;
                add = (add + (cnt[o] % MOD * j - sumIdx[o] % MOD + MOD) % MOD) % MOD;
                cnt[cur]++; sumIdx[cur] += j;
            }
            ans = (ans + add * ((1L << b) % MOD)) % MOD;
        }
        System.out.println(ans);
    }
    private static long nextLong(DataInputStream in) throws IOException {
        long r = 0; int b = in.read();
        while (b < '0') b = in.read();
        while (b >= '0') { r = r * 10 + b - '0'; b = in.read(); }
        return r;
    }
}
```

</details>

<!-- test
in:
3
1 3 2
out:
12
-->
<!-- test
in:
4
39 68 31 80
out:
1337
-->
<!-- test
in:
7
313539461 779847196 221612534 488613315 633203958 394620685 761188160
out:
257421502
-->
<!-- test
in:
1
0
out:
0
-->

### Example 5 — Intercity Travelling (expected value as contribution)  ·  ★ 2000

- **Source:** [CF 1009E · Intercity Travelling](https://codeforces.com/problemset/problem/1009/E) — 2000
- **Difficulty:** 2000
- **Problem:** A trip of $n \le 10^6$ km; after resting, the $i$-th km has difficulty $a_i$ ($a_1 \le \dots \le a_n \le 10^6$). Each of the $n - 1$ intermediate integer points independently has a rest site or not (all $2^{n-1}$ configurations equally likely); resting resets the counter. Print (expected total difficulty)$\cdot 2^{n-1}$ modulo $998244353$ — i.e. the sum over all configurations.
- **Thinking from first principles:** Sum over configurations of total difficulty = $\sum_i a_i\cdot$(number of (configuration, km) pairs where that km is the $i$-th since the last rest). Count them per position $j$ (the km from $j-1$ to $j$): it is the $i$-th km iff the last rest before it was at point $j - i$ (or the start if $j = i$) and points $j - i + 1..j-1$ have no rest.
  - $j = i$: points $1..i-1$ fixed empty, the other $n - 1 - (i-1)$ free: $2^{n-i}$.
  - $j > i$: point $j - i$ fixed as rest, $i - 1$ points fixed empty: $2^{n-1-i}$ configurations, for each of the $n - i$ values of $j$.

  So $c_i = 2^{n-i} + (n - i)\,2^{n-i-1}$ (and $c_n = 1$), answer $\sum_i a_ic_i$.

<details><summary>Solution</summary>

Powers of 2 up to $n$, one pass. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 998244353LL;
int main() {
    int n; scanf("%d", &n);
    vector<long long> pw(n + 1); pw[0] = 1;
    for (int i = 1; i <= n; i++) pw[i] = pw[i - 1] * 2 % MOD;
    long long ans = 0;
    for (int i = 1; i <= n; i++) {
        long long a; scanf("%lld", &a);
        long long c = pw[n - i];
        if (i < n) c = (c + (long long)(n - i) * pw[n - i - 1]) % MOD;
        ans = (ans + a % MOD * c) % MOD;
    }
    printf("%lld\n", ans);
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final long MOD = 998244353L;
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) nextLong(in);
        long[] pw = new long[n + 1]; pw[0] = 1;
        for (int i = 1; i <= n; i++) pw[i] = pw[i - 1] * 2 % MOD;
        long ans = 0;
        for (int i = 1; i <= n; i++) {
            long a = nextLong(in);
            long c = pw[n - i];
            if (i < n) c = (c + (long) (n - i) * pw[n - i - 1]) % MOD;
            ans = (ans + a % MOD * c) % MOD;
        }
        System.out.println(ans);
    }
    private static long nextLong(DataInputStream in) throws IOException {
        long r = 0; int b = in.read();
        while (b < '0') b = in.read();
        while (b >= '0') { r = r * 10 + b - '0'; b = in.read(); }
        return r;
    }
}
```

</details>

<!-- test
in:
2
1 2
out:
5
-->
<!-- test
in:
4
1 3 3 7
out:
60
-->
<!-- test
in:
1
1000000
out:
1000000
-->
<!-- test
in:
6
1 2 2 3 5 8
out:
295
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Tie-breaking**: strict inequality on one side, non-strict on the other (§1.3). Using `>=` on both sides undercounts, `>` on both overcounts — test with all-equal arrays (Example 3, last test).
2. **Overflow**: $\sum_i a_i\cdot i(n - i + 1)$ with $n = 2\cdot10^5$, $a_i = 10^9$ is $\approx 1.3\cdot10^{24}$ — beyond 64-bit; reduce mod $p$ or use `__int128` when the statement gives no modulus.
3. **Negative values modulo $p$**: `(a % MOD + MOD) % MOD` (Example 2); in Java `Math.floorMod`.
4. **Sorting first is allowed** for subsets/pairs (order-free structures) but **not** for subarrays (positions matter).
5. **Java `Arrays.sort(int[])` is a quicksort** that hackers can drive to $O(n^2)$; sort `Integer[]`/`long[]` after shuffling, or sort objects. (`long[]` uses the same algorithm, so shuffle when hacks are possible.)
6. **Bit loops**: iterate up to the highest bit of the maximum value (30 for $10^9$); `1 << 31` overflows `int`.
7. **Weighted contributions** (length, position) need running sums of indices alongside counts (Example 4).
8. **Expected value problems in disguise**: "print the answer multiplied by $2^{n-1}$" means "sum over all configurations" — count, don't compute probabilities (Example 5).

---

## 7. Going further (toward 2400–2600+)

- **Contribution + data structures**: when the contribution of an element depends on a range query (e.g. sum over subarrays of $\min\cdot\text{length}$, or second-maximum), combine monotonic stacks with Fenwick trees — [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md).
- **Divide and conquer on the array** for subarray functions that are not decomposable by a single extremum (e.g. sum over subarrays of $\max\cdot\min$): split at the middle, sweep two pointers across — [CDQ / offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md).
- **Contribution over the Cartesian tree**: the monotonic-stack boundaries are exactly the subtree ranges of the Cartesian tree — useful for "count subarrays where the max is at position $i$ and something holds".
- **Small-to-large / centroid decomposition** for sums over all tree paths of non-additive functions — [centroid decomposition](../10-Trees/05-centroid-decomposition.md).
- **Linearity with squares**: $E[X^2]$ via pairs of elements, the standard 2200+ upgrade of contribution problems ([probability](06-probability-and-expected-value.md)).

---

## 8. Practice ladder

**≤ 1600**
- [ ] [AtCoder ABC186 D · Sum of difference](https://atcoder.jp/contests/abc186/tasks/abc186_d) — diff≈436
- [ ] [CF 1648A · Weird Sum](https://codeforces.com/problemset/problem/1648/A) — 1400
- [ ] [AtCoder ABC151 E · Max-Min Sums](https://atcoder.jp/contests/abc151/tasks/abc151_e) — diff≈1344
- [ ] [CF 1215B · The Number of Products](https://codeforces.com/problemset/problem/1215/B) — 1400
- [ ] [CF 2000E · Photoshoot for Gorillas](https://codeforces.com/problemset/problem/2000/E) — 1400
- [ ] [CF 1996E · Decode](https://codeforces.com/problemset/problem/1996/E) — 1600

**1600–2000**
- [ ] [CF 1715C · Monoblock](https://codeforces.com/problemset/problem/1715/C) — 1700
- [ ] [CF 1879D · Sum of XOR Functions](https://codeforces.com/problemset/problem/1879/D) — 1700
- [ ] [CF 1420D · Rescue Nibel!](https://codeforces.com/problemset/problem/1420/D) — 1800
- [ ] [CF 1401D · Maximum Distributed Tree](https://codeforces.com/problemset/problem/1401/D) — 1800
- [ ] [CF 1444B · Divide and Sum](https://codeforces.com/problemset/problem/1444/B) — 1900
- [ ] [CF 1777D · Score of a Tree](https://codeforces.com/problemset/problem/1777/D) — 1900
- [ ] [CF 1009E · Intercity Travelling](https://codeforces.com/problemset/problem/1009/E) — 2000

**2000+**
- [ ] [CF 1467D · Sum of Paths](https://codeforces.com/problemset/problem/1467/D) — 2200

---

## 9. LeetCode / FAANG cross-reference

- [LC 907 · Sum of Subarray Minimums](https://leetcode.com/problems/sum-of-subarray-minimums/) — Medium — Example 3's stack with the asymmetric tie rule.
- [LC 2104 · Sum of Subarray Ranges](https://leetcode.com/problems/sum-of-subarray-ranges/) — Medium — max-sum minus min-sum.
- [LC 891 · Sum of Subsequence Widths](https://leetcode.com/problems/sum-of-subsequence-widths/) — Hard — sorted $a_i(2^i - 2^{n-1-i})$.
- [LC 828 · Count Unique Characters of All Substrings of a Given String](https://leetcode.com/problems/count-unique-characters-of-all-substrings-of-a-given-string/) — Hard — each occurrence contributes (distance to previous same char)·(distance to next).
- [LC 2262 · Total Appeal of A String](https://leetcode.com/problems/total-appeal-of-a-string/) — Hard — count each character at its first occurrence in the substring.
- [LC 2063 · Vowels of All Substrings](https://leetcode.com/problems/vowels-of-all-substrings/) — Medium — $(i+1)(n-i)$ per vowel.
- [LC 1588 · Sum of All Odd Length Subarrays](https://leetcode.com/problems/sum-of-all-odd-length-subarrays/) — Easy — count odd-length subarrays through $i$.
- [LC 1685 · Sum of Absolute Differences in a Sorted Array](https://leetcode.com/problems/sum-of-absolute-differences-in-a-sorted-array/) — Medium — prefix sums of the sorted array.
- [LC 2281 · Sum of Total Strength of Wizards](https://leetcode.com/problems/sum-of-total-strength-of-wizards/) — Hard — min-contribution with prefix sums of prefix sums.
- [LC 1863 · Sum of All Subset XOR Totals](https://leetcode.com/problems/sum-of-all-subset-xor-totals/) — Easy — $(\text{OR of all})\cdot2^{n-1}$ by per-bit contribution.

This technique is a FAANG favourite: interviewers expect the $O(n)$ stack solution for LC 907 and a clean argument about ties.

---

## 10. Self-check

1. State the swap-of-summation identity and give two problems it solves.
2. How many subarrays of an array of length $n$ contain position $i$?
3. Write the tie-breaking rule for subarray minima and explain why it counts each subarray once.
4. Derive $\sum_{i<j}\lvert a_i - a_j\rvert = \sum_i a_i(2i - n + 1)$ for sorted $a$.
5. What is $\sum$ over all subsets of $\max$ for $a = (1, 2, 3)$?
6. Derive the per-bit formula for $\sum_{i<j}(a_i\oplus a_j)$.
7. In Intercity Travelling, why is the coefficient of $a_n$ equal to $1$?
8. Sum of all pairwise distances in a path of $n$ vertices?

<details><summary>Answers</summary>

1. $\sum_S\sum_{e\in S}w = \sum_e\sum_{S\ni e}w$; sum of subarray sums, subarray minima, pairwise distances, expected counts.
2. $i(n - i + 1)$ (1-indexed).
3. The owner is the leftmost minimum: left boundary stops at a value $\le a_i$, right boundary at a value $< a_i$. Exactly one element of each subarray satisfies both conditions.
4. In sorted order $a_i$ is the larger element of $i$ pairs (plus sign) and the smaller of $n - 1 - i$ pairs (minus sign).
5. Sorted: $1\cdot2^0 + 2\cdot2^1 + 3\cdot2^2 = 17$ (check: the maxima of the 7 non-empty subsets are $1, 2, 2, 3, 3, 3, 3$).
6. Bit $b$ of $a_i\oplus a_j$ is 1 iff exactly one has it: $c_b(n - c_b)$ pairs, each worth $2^b$.
7. The $n$-th km since the last rest can only be the last km with no rest anywhere — one configuration.
8. Edge $k$ splits $k$ and $n - k$ vertices: $\sum_{k=1}^{n-1}k(n-k) = \binom{n+1}{3}$.

</details>
