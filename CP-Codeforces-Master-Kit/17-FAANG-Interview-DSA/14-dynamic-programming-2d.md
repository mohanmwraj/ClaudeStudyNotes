# Dynamic Programming (2D): Grids, Two Sequences, Knapsack, Intervals, State Machines

> **Band:** 🔵 1500 – 🟣 2000 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [1D DP](13-dynamic-programming-1d.md), [knapsack family (CP)](../06-Dynamic-Programming/02-knapsack-family.md)
> **You can say you know this when:** you can derive LCS and edit distance from "look at the last characters", explain why 0/1 knapsack iterates capacity backwards in a 1D array, set up interval DP by increasing length, and reduce any 2D table to two rows.

Two-dimensional DP appears whenever the state needs **two numbers**: a cell $(r, c)$; positions $(i, j)$ in two strings; (item index, capacity); an interval $[l, r]$; or (day, holding/not holding). The four-step method from [1D DP](13-dynamic-programming-1d.md) is unchanged. What changes is the evaluation order and the memory trick.

## 1. First principles — why this works

### 1.1 Two sequences: decide about the last characters

For strings $a$ (length $n$) and $b$ (length $m$), let $f(i, j)$ be the answer for the prefixes $a[0..i)$ and $b[0..j)$. Every optimal solution does *something* with the last characters $a_{i-1}$ and $b_{j-1}$, and there are only a few possibilities:

- **LCS:** if $a_{i-1} = b_{j-1}$, some LCS uses both (exchange argument: an LCS that does not can be modified to end with this match), so $f = 1 + f(i-1, j-1)$. Otherwise at least one of them is unused: $f = \max(f(i-1, j), f(i, j-1))$.
- **Edit distance:** the last operation either matches/replaces ($f(i-1, j-1) + [a_{i-1} \ne b_{j-1}]$), deletes $a_{i-1}$ ($f(i-1, j) + 1$), or inserts $b_{j-1}$ ($f(i, j-1) + 1$).

Base cases are the empty prefixes ($f(0, j)$ and $f(i, 0)$). The table has $(n+1)(m+1)$ cells, each $O(1)$. Since row $i$ only reads rows $i$ and $i - 1$, memory drops to $O(\min(n, m))$.

### 1.2 Grids: the last step came from above or the left

When moves are only right/down, every path to $(r, c)$ passes through $(r-1, c)$ or $(r, c-1)$ last, so $f(r, c) = \text{combine}(f(r-1, c), f(r, c-1)) + \text{cost}(r, c)$. Row-major order satisfies the dependencies. With moves in all four directions there is no such order. That becomes a graph problem (BFS/Dijkstra), or a DP over a DAG when the values strictly increase along paths (Longest Increasing Path in a Matrix, memoised DFS).

### 1.3 Knapsack: item index × capacity

$f(i, w)$ = best value using items $0..i-1$ with total weight $\le w$ (or "can reach exactly $w$"). For item $i$: skip it, $f(i, w)$, or take it, $f(i, w - w_i) + v_i$, and the result is $f(i+1, w)$. In one array indexed by $w$:

- **0/1 (each item at most once):** loop $w$ **downwards**, so `dp[w - wi]` still holds the value from *before* item $i$.
- **Unbounded (reuse allowed):** loop $w$ **upwards**, so `dp[w - wi]` may already include item $i$.

The direction of a single loop encodes the item rule. That is the most-asked detail in knapsack interviews.

### 1.4 Intervals: choose what happens last inside $[l, r]$

For problems where combining pieces depends on neighbours (Burst Balloons, matrix-chain, polygon triangulation), the state is an interval, and the key move is choosing the element that is processed **last** inside it. Choosing what happens *first* splits the problem into parts that still interact. Choosing what happens *last* makes the two sides independent, because the last element's neighbours at its moment are the interval's fixed boundaries. Evaluate by increasing interval length: $O(n^2)$ states × $O(n)$ split points = $O(n^3)$.

### 1.5 State machines

Stock problems with cooldowns, fees or a limited number of transactions keep, for each day, a small set of states ("holding", "not holding, free", "cooling down") and the transitions between them. This is 2D DP with a tiny second dimension, usually written as a few rolling variables.

## 2. Recurrences and complexities

| Problem | State | Recurrence | Time / memory |
|---|---|---|---|
| Unique Paths | $f(r,c)$ paths | $f(r,c) = f(r-1,c) + f(r,c-1)$; also $\binom{m+n-2}{m-1}$ | $O(mn)$ / $O(n)$ |
| Minimum Path Sum | $f(r,c)$ | $g_{rc} + \min(f(r-1,c), f(r,c-1))$ | $O(mn)$ / $O(n)$ |
| Maximal Square | $s(r,c)$ = side of the largest square with bottom-right $(r,c)$ | $1 + \min(s_{r-1,c}, s_{r,c-1}, s_{r-1,c-1})$ if cell is 1 | $O(mn)$ |
| LCS | $f(i,j)$ | match: $1 + f(i-1,j-1)$; else $\max(f(i-1,j), f(i,j-1))$ | $O(nm)$ / $O(\min)$ |
| Edit distance | $f(i,j)$ | $\min(f(i-1,j-1) + [\ne],\ f(i-1,j)+1,\ f(i,j-1)+1)$; $f(i,0)=i$, $f(0,j)=j$ | $O(nm)$ |
| Distinct subsequences | $f(i,j)$ ways | $f(i-1,j) + [a_{i-1} = b_{j-1}] f(i-1,j-1)$ | $O(nm)$ |
| 0/1 knapsack (subset sum) | $dp[w]$ | $dp[w] \mathrel{|}= dp[w - x]$, $w$ downwards | $O(nW)$ / $O(W)$ |
| Coin Change II (ways) | $dp[w]$ | $dp[w] \mathrel{+}= dp[w - c]$, coins outer, $w$ upwards | $O(mW)$ |
| Burst Balloons | $f(l,r)$ on open interval | $\max_{l<k<r} f(l,k) + f(k,r) + a_l a_k a_r$ | $O(n^3)$ / $O(n^2)$ |
| Stock with cooldown | (hold, sold, rest) per day | see the template | $O(n)$ / $O(1)$ |
| Longest increasing path in a grid | memo per cell | $1 + \max$ over strictly larger neighbours | $O(mn)$ |

## 3. Reusable templates (C++ and Java)

0/1 versus unbounded knapsack in one array, and the cooldown state machine ([LC 309 · Best Time to Buy and Sell Stock with Cooldown](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-with-cooldown/) — Medium):

```cpp
// Max value with capacity W; each item at most once (0/1).
long long knapsack01(const vector<int>& wt, const vector<int>& val, int W) {
    vector<long long> dp(W + 1, 0);
    for (size_t i = 0; i < wt.size(); ++i)
        for (int w = W; w >= wt[i]; --w)                 // downwards: dp[w - wt] is still "without item i"
            dp[w] = max(dp[w], dp[w - wt[i]] + val[i]);
    return dp[W];
}

// Max value with capacity W; unlimited copies of each item.
long long knapsackUnbounded(const vector<int>& wt, const vector<int>& val, int W) {
    vector<long long> dp(W + 1, 0);
    for (size_t i = 0; i < wt.size(); ++i)
        for (int w = wt[i]; w <= W; ++w)                 // upwards: dp[w - wt] may already use item i
            dp[w] = max(dp[w], dp[w - wt[i]] + val[i]);
    return dp[W];
}

int maxProfitCooldown(const vector<int>& prices) {
    int hold = INT_MIN / 2, sold = 0, rest = 0;          // best profit in each state at the end of a day
    for (int p : prices) {
        int newHold = max(hold, rest - p);               // keep holding, or buy (only from rest)
        int newSold = hold + p;                          // sell today
        int newRest = max(rest, sold);                   // do nothing; yesterday's sale ends its cooldown
        hold = newHold; sold = newSold; rest = newRest;
    }
    return max(sold, rest);
}
```

```java
static long knapsack01(int[] wt, int[] val, int W) {
    long[] dp = new long[W + 1];
    for (int i = 0; i < wt.length; i++)
        for (int w = W; w >= wt[i]; w--)
            dp[w] = Math.max(dp[w], dp[w - wt[i]] + val[i]);
    return dp[W];
}

static long knapsackUnbounded(int[] wt, int[] val, int W) {
    long[] dp = new long[W + 1];
    for (int i = 0; i < wt.length; i++)
        for (int w = wt[i]; w <= W; w++)
            dp[w] = Math.max(dp[w], dp[w - wt[i]] + val[i]);
    return dp[W];
}

static int maxProfitCooldown(int[] prices) {
    int hold = Integer.MIN_VALUE / 2, sold = 0, rest = 0;
    for (int p : prices) {
        int newHold = Math.max(hold, rest - p);
        int newSold = hold + p;
        int newRest = Math.max(rest, sold);
        hold = newHold; sold = newSold; rest = newRest;
    }
    return Math.max(sold, rest);
}
```

Interval DP skeleton (fill by increasing length so that every sub-interval is ready):

```cpp
long long intervalDP(int n, const function<long long(int, int, int)>& joinCost) {
    // f[l][r] for 0 <= l <= r < n; f[i][i] = 0; split point k in [l, r)
    vector<vector<long long>> f(n, vector<long long>(n, 0));
    for (int len = 2; len <= n; ++len)
        for (int l = 0; l + len - 1 < n; ++l) {
            int r = l + len - 1;
            f[l][r] = LLONG_MAX;
            for (int k = l; k < r; ++k)
                f[l][r] = min(f[l][r], f[l][k] + f[k + 1][r] + joinCost(l, k, r));
        }
    return n ? f[0][n - 1] : 0;
}
```

```java
interface JoinCost { long cost(int l, int k, int r); }

static long intervalDP(int n, JoinCost joinCost) {
    long[][] f = new long[n][n];
    for (int len = 2; len <= n; len++)
        for (int l = 0; l + len - 1 < n; l++) {
            int r = l + len - 1;
            f[l][r] = Long.MAX_VALUE;
            for (int k = l; k < r; k++)
                f[l][r] = Math.min(f[l][r], f[l][k] + f[k + 1][r] + joinCost.cost(l, k, r));
        }
    return n > 0 ? f[0][n - 1] : 0;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| two strings, "common", "transform", "interleave", "matches pattern" | $f(i, j)$ over prefixes |
| grid, moves only right/down | grid DP, row by row |
| grid, 4-directional, strictly increasing path | memoised DFS on the DAG of cells |
| "subset with sum $S$", "split into two equal halves", "assign + / −" | 0/1 knapsack over sums (offset negatives) |
| "number of ways to make an amount", unordered | unbounded knapsack, coins outer |
| "burst / merge / cut / triangulate", cost depends on neighbours | interval DP; pick the **last** operation |
| "two players take from either end" | interval DP on the score difference |
| buy/sell with cooldown / fee / at most $k$ transactions | state machine over days (× transactions) |
| "largest square / rectangle of 1s" | `min` of three neighbours (square); histogram per row (rectangle, [file 04](04-stacks-and-monotonic-stacks.md)) |
| `*` and `.` wildcards | two-string DP with special transitions |

## 5. Worked examples

### Example 1 — Unique Paths · Medium

- **Source:** [LC 62 · Unique Paths](https://leetcode.com/problems/unique-paths/) — Medium · `G75` `B75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1000 CF, est.)
- **Problem:** count right/down paths from the top-left to the bottom-right of an $m \times n$ grid ($m, n \le 100$, answer $\le 2 \cdot 10^9$).
- **Thinking from first principles:** the last step into $(r, c)$ came from above or from the left, and those path sets are disjoint, so the counts add. Boundary cells have exactly one path. A rolling row suffices: `row[c] += row[c-1]` updates "from above" (old `row[c]`) plus "from the left" (new `row[c-1]`). The closed form: a path is an arrangement of $m-1$ downs and $n-1$ rights, so there are $\binom{m+n-2}{m-1}$ paths. Compute it multiplicatively in 64-bit, dividing at each step so every intermediate value is an integer.

<details><summary>Solution</summary>

DP with one row: $O(mn)$ time, $O(n)$ space. The binomial is $O(\min(m, n))$ and is a good follow-up answer.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int uniquePaths(int m, int n) {
        vector<long long> row(n, 1);                   // first row: one path to each cell
        for (int r = 1; r < m; ++r)
            for (int c = 1; c < n; ++c)
                row[c] += row[c - 1];                  // from above (old row[c]) + from the left
        return (int)row[n - 1];
    }
    long long uniquePathsBinomial(int m, int n) {      // C(m + n - 2, m - 1)
        long long res = 1;
        int k = min(m, n) - 1, total = m + n - 2;
        for (int i = 1; i <= k; ++i) res = res * (total - k + i) / i;   // exact at every step
        return res;
    }
};

int main() {
    int m, n;
    cin >> m >> n;
    Solution s;
    cout << s.uniquePaths(m, n) << ' ' << s.uniquePathsBinomial(m, n) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int uniquePaths(int m, int n) {
        long[] row = new long[n];
        Arrays.fill(row, 1);
        for (int r = 1; r < m; r++)
            for (int c = 1; c < n; c++) row[c] += row[c - 1];
        return (int) row[n - 1];
    }
    public long uniquePathsBinomial(int m, int n) {
        long res = 1;
        int k = Math.min(m, n) - 1, total = m + n - 2;
        for (int i = 1; i <= k; i++) res = res * (total - k + i) / i;
        return res;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int m = Integer.parseInt(st.nextToken()), n = Integer.parseInt(st.nextToken());
        Solution s = new Solution();
        System.out.println(s.uniquePaths(m, n) + " " + s.uniquePathsBinomial(m, n));
    }
}
```

</details>

<!-- test
in:
3 7
out:
28 28
-->
<!-- test
in:
3 2
out:
3 3
-->
<!-- test
in:
1 1
out:
1 1
-->
<!-- test
in:
17 18
out:
1166803110 1166803110
-->

### Example 2 — Longest Common Subsequence · Medium

- **Source:** [LC 1143 · Longest Common Subsequence](https://leetcode.com/problems/longest-common-subsequence/) — Medium · `B75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** the length of the longest common subsequence of two lowercase strings ($\le 1000$ each).
- **Thinking from first principles:** brute force enumerates the $2^n$ subsequences of one string. Look at the last characters (§1.1). If they are equal, match them. If not, one of them is not part of the LCS, so drop it and take the better result. The subproblems are pairs of prefix lengths: $(n+1)(m+1)$ of them, $O(1)$ each. For two rows, keep `prev` (row $i-1$) and `cur` (row $i$).

<details><summary>Solution</summary>

$O(nm)$ time, $O(m)$ memory with two rows. The driver reads the two strings.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int longestCommonSubsequence(string a, string b) {
        int n = a.size(), m = b.size();
        vector<int> prev(m + 1, 0), cur(m + 1, 0);       // rows i-1 and i of f(i, j)
        for (int i = 1; i <= n; ++i) {
            for (int j = 1; j <= m; ++j)
                cur[j] = (a[i - 1] == b[j - 1]) ? prev[j - 1] + 1     // match the last characters
                                                : max(prev[j], cur[j - 1]);   // drop one of them
            swap(prev, cur);
        }
        return prev[m];
    }
};

int main() {
    string a, b;
    cin >> a >> b;
    cout << Solution().longestCommonSubsequence(a, b) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int longestCommonSubsequence(String a, String b) {
        int n = a.length(), m = b.length();
        int[] prev = new int[m + 1], cur = new int[m + 1];
        for (int i = 1; i <= n; i++) {
            for (int j = 1; j <= m; j++)
                cur[j] = a.charAt(i - 1) == b.charAt(j - 1) ? prev[j - 1] + 1 : Math.max(prev[j], cur[j - 1]);
            int[] t = prev; prev = cur; cur = t;
        }
        return prev[m];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        String a = st.nextToken(), b = st.nextToken();
        System.out.println(new Solution().longestCommonSubsequence(a, b));
    }
}
```

</details>

<!-- test
in:
abcde ace
out:
3
-->
<!-- test
in:
abc abc
out:
3
-->
<!-- test
in:
abc def
out:
0
-->
<!-- test
in:
bsbininm jmjkbkjkv
out:
1
-->

### Example 3 — Edit Distance · Medium

- **Source:** [LC 72 · Edit Distance](https://leetcode.com/problems/edit-distance/) — Medium · `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1500 CF, est.)
- **Problem:** minimum insertions, deletions and replacements to turn `word1` into `word2` (lengths $\le 500$, possibly empty).
- **Thinking from first principles:** consider an optimal edit script and what happens to the last characters. Either $a_{i-1}$ ends up aligned with $b_{j-1}$ (free if equal, else one replacement), or $a_{i-1}$ is deleted, or $b_{j-1}$ is inserted at the end. Those three cases cover every script, and each leaves a smaller prefix pair. The base cases are transforming to or from the empty string: $f(i, 0) = i$ deletions and $f(0, j) = j$ insertions.

<details><summary>Solution</summary>

Two rows, with `diag` holding $f(i-1, j-1)$ before it is overwritten. $O(nm)$ time, $O(m)$ space. The driver reads two tokens, where `#` stands for the empty string.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int minDistance(string a, string b) {
        int n = a.size(), m = b.size();
        vector<int> row(m + 1);
        iota(row.begin(), row.end(), 0);                 // f(0, j) = j insertions
        for (int i = 1; i <= n; ++i) {
            int diag = row[0];                           // f(i-1, 0)
            row[0] = i;                                  // f(i, 0) = i deletions
            for (int j = 1; j <= m; ++j) {
                int up = row[j];                         // f(i-1, j)
                row[j] = min({diag + (a[i - 1] != b[j - 1]),   // match / replace
                              up + 1,                          // delete a[i-1]
                              row[j - 1] + 1});                // insert b[j-1]
                diag = up;
            }
        }
        return row[m];
    }
};

int main() {
    string a, b;
    cin >> a >> b;
    if (a == "#") a = "";
    if (b == "#") b = "";
    cout << Solution().minDistance(a, b) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int minDistance(String a, String b) {
        int n = a.length(), m = b.length();
        int[] row = new int[m + 1];
        for (int j = 0; j <= m; j++) row[j] = j;
        for (int i = 1; i <= n; i++) {
            int diag = row[0];
            row[0] = i;
            for (int j = 1; j <= m; j++) {
                int up = row[j];
                int replace = diag + (a.charAt(i - 1) != b.charAt(j - 1) ? 1 : 0);
                row[j] = Math.min(replace, Math.min(up + 1, row[j - 1] + 1));
                diag = up;
            }
        }
        return row[m];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        String a = st.nextToken(), b = st.nextToken();
        if (a.equals("#")) a = "";
        if (b.equals("#")) b = "";
        System.out.println(new Solution().minDistance(a, b));
    }
}
```

</details>

<!-- test
in:
horse ros
out:
3
-->
<!-- test
in:
intention execution
out:
5
-->
<!-- test
in:
# abc
out:
3
-->
<!-- test
in:
abc #
out:
3
-->
<!-- test
in:
same same
out:
0
-->

### Example 4 — Partition Equal Subset Sum · Medium

- **Source:** [LC 416 · Partition Equal Subset Sum](https://leetcode.com/problems/partition-equal-subset-sum/) — Medium · `G75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1500 CF, est.)
- **Problem:** can $n \le 200$ positive integers ($\le 100$ each) be split into two subsets with equal sums?
- **Thinking from first principles:** the two halves each sum to $S/2$, so if $S$ is odd the answer is no. Otherwise the question is "is there a subset with sum exactly $S/2$?", which is 0/1 knapsack with booleans. $reach[w]$ = some subset of the items seen so far sums to $w$. Adding item $x$: $reach[w] \mathrel{|}= reach[w - x]$, looping $w$ **downwards** so $x$ is used at most once. $S/2 \le 10^4$ and $n \le 200$, so this is $2 \cdot 10^6$ steps. In C++ a `bitset` does the whole update as `bits |= bits << x`, 64 sums per machine word.

<details><summary>Solution</summary>

Boolean 0/1 knapsack, $O(n \cdot S/2)$ time, $O(S/2)$ space, with an early exit once $S/2$ is reachable. The bitset version is shown as a second method in the C++ code.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    bool canPartition(vector<int>& nums) {
        int total = accumulate(nums.begin(), nums.end(), 0);
        if (total % 2) return false;
        int half = total / 2;
        vector<bool> reach(half + 1, false);
        reach[0] = true;                                  // the empty subset
        for (int x : nums) {
            for (int w = half; w >= x; --w)               // downwards: each item at most once
                if (reach[w - x]) reach[w] = true;
            if (reach[half]) return true;
        }
        return reach[half];
    }
    bool canPartitionBitset(vector<int>& nums) {
        int total = accumulate(nums.begin(), nums.end(), 0);
        if (total % 2) return false;
        bitset<10001> bits;                               // max half-sum for n = 200, a_i = 100
        bits[0] = 1;
        for (int x : nums) bits |= bits << x;             // shifting adds x to every reachable sum
        return bits[total / 2];
    }
};

int main() {
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    Solution s;
    bool r1 = s.canPartition(a), r2 = s.canPartitionBitset(a);
    cout << (r1 ? "true" : "false") << ' ' << (r2 ? "true" : "false") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public boolean canPartition(int[] nums) {
        int total = 0;
        for (int x : nums) total += x;
        if (total % 2 == 1) return false;
        int half = total / 2;
        boolean[] reach = new boolean[half + 1];
        reach[0] = true;
        for (int x : nums) {
            for (int w = half; w >= x; w--) if (reach[w - x]) reach[w] = true;
            if (reach[half]) return true;
        }
        return reach[half];
    }
    public boolean canPartitionBitset(int[] nums) {
        int total = 0;
        for (int x : nums) total += x;
        if (total % 2 == 1) return false;
        BitSet bits = new BitSet(total + 1);
        bits.set(0);
        for (int x : nums) {
            BitSet shifted = new BitSet(total + 1);       // BitSet has no shift: rebuild it
            for (int i = bits.nextSetBit(0); i >= 0 && i + x <= total; i = bits.nextSetBit(i + 1)) shifted.set(i + x);
            bits.or(shifted);
        }
        return bits.get(total / 2);
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        StringTokenizer st = new StringTokenizer(br.readLine());
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = Integer.parseInt(st.nextToken());
        Solution s = new Solution();
        System.out.println(s.canPartition(a) + " " + s.canPartitionBitset(a));
    }
}
```

</details>

<!-- test
in:
4
1 5 11 5
out:
true true
-->
<!-- test
in:
4
1 2 3 5
out:
false false
-->
<!-- test
in:
1
2
out:
false false
-->
<!-- test
in:
2
100 100
out:
true true
-->

### Example 5 — Burst Balloons · Hard

- **Source:** [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard · `NC150`
- **Difficulty:** LeetCode Hard (≈ 2000 CF, est.)
- **Problem:** balloons with values $a_0..a_{n-1}$ ($n \le 300$, $a_i \le 100$). Bursting balloon $i$ earns $a_{\text{left}} \cdot a_i \cdot a_{\text{right}}$, where left and right are its current neighbours (treated as 1 past the ends). Maximise the total.
- **Thinking from first principles:** choosing which balloon to burst *first* fails as a recurrence, because the remaining balloons' neighbours change and the two sides interact. Instead pick the balloon $k$ burst **last** inside an open interval $(l, r)$ whose ends are still present. At that moment its neighbours are exactly $l$ and $r$, so it earns $a_l a_k a_r$. Before it, the balloons in $(l, k)$ and $(k, r)$ were burst independently, since $k$ separates them throughout. Pad the array with 1 at both ends: $f(l, r) = \max_{l < k < r} f(l, k) + f(k, r) + a_l a_k a_r$, with $f(l, l+1) = 0$, filled by increasing $r - l$.

<details><summary>Solution</summary>

Interval DP on the padded array of length $n + 2$. $O(n^3) \approx 2.7 \cdot 10^7$ for $n = 300$, $O(n^2)$ memory. Each product is at most $10^6$ and the total at most about $3 \cdot 10^8$, which fits in 32 bits, but 64-bit costs nothing.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int maxCoins(vector<int>& nums) {
        vector<int> a(nums.size() + 2, 1);
        copy(nums.begin(), nums.end(), a.begin() + 1);    // pad with virtual 1s at both ends
        int m = a.size();
        vector<vector<long long>> f(m, vector<long long>(m, 0));   // f[l][r]: best for the open interval (l, r)
        for (int len = 2; len < m; ++len)
            for (int l = 0; l + len < m; ++l) {
                int r = l + len;
                for (int k = l + 1; k < r; ++k)           // k is the last balloon burst in (l, r)
                    f[l][r] = max(f[l][r], f[l][k] + f[k][r] + 1LL * a[l] * a[k] * a[r]);
            }
        return (int)f[0][m - 1];
    }
};

int main() {
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << Solution().maxCoins(a) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int maxCoins(int[] nums) {
        int m = nums.length + 2;
        int[] a = new int[m];
        a[0] = a[m - 1] = 1;
        System.arraycopy(nums, 0, a, 1, nums.length);
        long[][] f = new long[m][m];
        for (int len = 2; len < m; len++)
            for (int l = 0; l + len < m; l++) {
                int r = l + len;
                for (int k = l + 1; k < r; k++)
                    f[l][r] = Math.max(f[l][r], f[l][k] + f[k][r] + (long) a[l] * a[k] * a[r]);
            }
        return (int) f[0][m - 1];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        StringTokenizer st = new StringTokenizer(br.readLine());
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = Integer.parseInt(st.nextToken());
        System.out.println(new Solution().maxCoins(a));
    }
}
```

</details>

<!-- test
in:
4
3 1 5 8
out:
167
-->
<!-- test
in:
2
1 5
out:
10
-->
<!-- test
in:
1
7
out:
7
-->
<!-- test
in:
3
0 0 0
out:
0
-->

## 6. Pitfalls and things to remember

1. **Index prefixes by length** ($f(i, j)$ over `a[0..i)`, `b[0..j)`) so the empty prefix is row 0. Mixing "length" and "last index" causes most off-by-one bugs.
2. **Rolling arrays need care with the diagonal.** In edit distance, save $f(i-1, j-1)$ in a variable before overwriting `row[j]`. In LCS, swapping two rows avoids it.
3. **0/1 vs unbounded is the loop direction.** Downwards for at most once, upwards for unlimited. In a 2D table both work naturally, so the direction only matters after compressing to 1D.
4. **Counting combinations vs permutations:** coins outer counts multisets (Coin Change II), amount outer counts sequences (Combination Sum IV).
5. **Interval DP order:** iterate by length, not by $l$ then $r$ ascending, or `f[k][r]` is read before it is computed.
6. **Negative sums in knapsack** (Target Sum): offset by the total, or transform. With $P - N = T$ and $P + N = S$, you get $P = (S + T)/2$, a plain subset-sum count. Check parity and $|T| \le S$.
7. **Overflow in path counts:** Unique Paths fits in `int` only by the problem's promise. The binomial needs 64-bit intermediates, and division must be exact at each step (multiply first, then divide).
8. **Memory:** $10^3 \times 10^3$ `int`s is 4 MB, fine. $10^4 \times 10^4$ is 400 MB, so roll the rows.
9. **Java `BitSet` has no shift.** Use `long[]` words manually or the boolean array. C++ `bitset` sizes must be compile-time constants.
10. **Stock state machines:** initialise "holding" to $-\infty$ (you cannot hold before buying), not 0.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| Unique Paths → "with obstacles" | zero the cells that are blocked; same recurrence ([LC 63 · Unique Paths II](https://leetcode.com/problems/unique-paths-ii/) — Medium) |
| LCS → "return the subsequence" | keep the full table and walk back from $(n, m)$ following the choices |
| → "LCS of two permutations" | map one onto positions in the other, then LIS in $O(n \log n)$ |
| → "memory for 10^5 × 10^5?" | two rows give $O(m)$ memory but $O(nm)$ time stays; Hirschberg recovers the sequence in linear memory |
| Edit distance → "only check distance ≤ 1" | linear two-pointer scan ("one edit away"), not the full table |
| → "weighted operations" | same recurrence with costs in place of 1 |
| Partition → "split into $k$ equal subsets" | backtracking with pruning or bitmask DP ([LC 698 · Partition to K Equal Sum Subsets](https://leetcode.com/problems/partition-to-k-equal-sum-subsets/) — Medium) |
| → "minimise the difference of the two halves" | subset-sum reachability up to $S/2$, take the largest reachable $w$: answer $S - 2w$ ([LC 1049 · Last Stone Weight II](https://leetcode.com/problems/last-stone-weight-ii/) — Medium) |
| Burst Balloons → "why last, not first?" | choosing last fixes the neighbours to the interval ends, which makes the two sides independent |
| Stocks → "at most $k$ transactions" | states (transactions used, holding) per day: $O(nk)$ ([LC 188 · Best Time to Buy and Sell Stock IV](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-iv/) — Hard) |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium.

**Medium** (14)

- [ ] [LC 62 · Unique Paths](https://leetcode.com/problems/unique-paths/) — Medium · `G75` `B75` `NC150`
- [ ] [LC 63 · Unique Paths II](https://leetcode.com/problems/unique-paths-ii/) — Medium · `NC250` `TI150`
- [ ] [LC 64 · Minimum Path Sum](https://leetcode.com/problems/minimum-path-sum/) — Medium · `NC250` `TI150`
- [ ] [LC 72 · Edit Distance](https://leetcode.com/problems/edit-distance/) — Medium · `NC150` `TI150`
- [ ] [LC 97 · Interleaving String](https://leetcode.com/problems/interleaving-string/) — Medium · `NC150` `TI150`
- [ ] [LC 221 · Maximal Square](https://leetcode.com/problems/maximal-square/) — Medium · `G169` `TI150`
- [ ] [LC 309 · Best Time to Buy and Sell Stock with Cooldown](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-with-cooldown/) — Medium · `NC150`
- [ ] [LC 416 · Partition Equal Subset Sum](https://leetcode.com/problems/partition-equal-subset-sum/) — Medium · `G75` `NC150`
- [ ] [LC 494 · Target Sum](https://leetcode.com/problems/target-sum/) — Medium · `NC150`
- [ ] [LC 518 · Coin Change II](https://leetcode.com/problems/coin-change-ii/) — Medium · `NC150`
- [ ] [LC 877 · Stone Game](https://leetcode.com/problems/stone-game/) — Medium · `NC250`
- [ ] [LC 1049 · Last Stone Weight II](https://leetcode.com/problems/last-stone-weight-ii/) — Medium · `NC250`
- [ ] [LC 1140 · Stone Game II](https://leetcode.com/problems/stone-game-ii/) — Medium · `NC250`
- [ ] [LC 1143 · Longest Common Subsequence](https://leetcode.com/problems/longest-common-subsequence/) — Medium · `B75` `NC150`

**Hard** (6)

- [ ] [LC 10 · Regular Expression Matching](https://leetcode.com/problems/regular-expression-matching/) — Hard · `NC150`
- [ ] [LC 115 · Distinct Subsequences](https://leetcode.com/problems/distinct-subsequences/) — Hard · `NC150`
- [ ] [LC 123 · Best Time to Buy and Sell Stock III](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-iii/) — Hard · `TI150`
- [ ] [LC 188 · Best Time to Buy and Sell Stock IV](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-iv/) — Hard · `TI150`
- [ ] [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard · `NC150`
- [ ] [LC 329 · Longest Increasing Path in a Matrix](https://leetcode.com/problems/longest-increasing-path-in-a-matrix/) — Hard · `G169` `NC150`

**Beyond the lists:**

- [ ] [LC 931 · Minimum Falling Path Sum](https://leetcode.com/problems/minimum-falling-path-sum/) — Medium — grid DP with three parents
- [ ] [LC 516 · Longest Palindromic Subsequence](https://leetcode.com/problems/longest-palindromic-subsequence/) — Medium — interval DP, or LCS with the reverse
- [ ] [LC 583 · Delete Operation for Two Strings](https://leetcode.com/problems/delete-operation-for-two-strings/) — Medium — $n + m - 2\,\text{LCS}$
- [ ] [LC 712 · Minimum ASCII Delete Sum for Two Strings](https://leetcode.com/problems/minimum-ascii-delete-sum-for-two-strings/) — Medium — weighted LCS
- [ ] [LC 474 · Ones and Zeroes](https://leetcode.com/problems/ones-and-zeroes/) — Medium — 0/1 knapsack with two capacities
- [ ] [LC 1155 · Number of Dice Rolls With Target Sum](https://leetcode.com/problems/number-of-dice-rolls-with-target-sum/) — Medium — (dice, sum) counting mod $10^9+7$
- [ ] [LC 1039 · Minimum Score Triangulation of Polygon](https://leetcode.com/problems/minimum-score-triangulation-of-polygon/) — Medium — interval DP, last triangle
- [ ] [LC 174 · Dungeon Game](https://leetcode.com/problems/dungeon-game/) — Hard — grid DP from the end
- [ ] [LC 1547 · Minimum Cost to Cut a Stick](https://leetcode.com/problems/minimum-cost-to-cut-a-stick/) — Hard — interval DP over cut positions
- [ ] [LC 1312 · Minimum Insertion Steps to Make a String Palindrome](https://leetcode.com/problems/minimum-insertion-steps-to-make-a-string-palindrome/) — Hard — $n - \text{LPS}$
- [ ] [LC 741 · Cherry Pickup](https://leetcode.com/problems/cherry-pickup/) — Hard — two walkers at once, state (step, r1, r2)

## 9. CP counterpart

- [Sequence DP: LIS, LCS, edit distance](../06-Dynamic-Programming/03-sequence-dp-lis-lcs-edit-distance.md)
- [Grid and path-counting DP](../06-Dynamic-Programming/04-grid-and-path-counting-dp.md): obstacles via inclusion–exclusion and binomials when grids are huge.
- [Interval DP](../06-Dynamic-Programming/05-interval-dp.md) and [Knuth optimisation](../07-DP-Optimizations/04-knuth-optimization.md), which brings some interval DPs from $O(n^3)$ to $O(n^2)$.
- [Knapsack family](../06-Dynamic-Programming/02-knapsack-family.md): bounded knapsack, bitset tricks, meet in the middle.
- [Minimax and game DP](../13-Game-Theory/04-minimax-and-game-dp.md): the Stone Game series.

Interview difference: interviewers expect the $O(nm)$ table with a clear recurrence and then the memory reduction. CP optimisations (Knuth, divide and conquer, bitset at scale) are bonus remarks at most.

## 10. Self-check

1. Derive the edit-distance recurrence from the three things that can happen to the last characters.
2. Why does 0/1 knapsack loop the capacity downwards in a 1D array?
3. In Burst Balloons, why is the recurrence over the **last** balloon to burst?
4. Give the base cases of LCS and edit distance.
5. How do you reduce LCS memory to $O(\min(n, m))$, and what do you lose?
6. Transform Target Sum into a subset-sum count.
7. What is the evaluation order for interval DP, and why?
8. Write the three-state cooldown recurrence.

<details><summary>Answers</summary>

1. Align $a_{i-1}$ with $b_{j-1}$ (cost 0 if equal, else 1 replacement) + $f(i-1, j-1)$; delete $a_{i-1}$: $f(i-1, j) + 1$; insert $b_{j-1}$: $f(i, j-1) + 1$. Take the minimum.
2. So that `dp[w - x]` still holds the value from before item $x$ was considered. Upwards it could already include $x$, which allows reuse.
3. The last balloon's neighbours at its moment are the fixed interval ends, so its gain is known, and it separates the interval into two independent subproblems.
4. LCS: $f(0, j) = f(i, 0) = 0$. Edit distance: $f(i, 0) = i$, $f(0, j) = j$.
5. Keep only two rows (make the shorter string the column dimension). You lose the ability to reconstruct the sequence by walking back (Hirschberg's algorithm restores it with divide and conquer).
6. With $P$ the sum of the `+` numbers and $N$ of the `−` numbers, $P - N = T$ and $P + N = S$, so $P = (S+T)/2$. Count subsets with that sum (0 if $S + T$ is odd or $|T| > S$).
7. By increasing length, so that every strictly shorter sub-interval used on the right side is already final.
8. `hold' = max(hold, rest - p)`, `sold' = hold + p`, `rest' = max(rest, sold)`. The answer is `max(sold, rest)` on the last day.

</details>
