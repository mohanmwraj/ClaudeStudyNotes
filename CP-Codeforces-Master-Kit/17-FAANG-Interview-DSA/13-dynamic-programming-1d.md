# Dynamic Programming (1D)

> **Band:** 🟢 1200 – 🔵 1800 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [backtracking](10-backtracking.md), [DP first principles and state design (CP)](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md)
> **You can say you know this when:** for a new problem you can write the state in one sentence, the recurrence with its base cases, the evaluation order and the answer cell, then turn a memoised recursion into a bottom-up loop with $O(1)$ or $O(n)$ memory.

DP is the topic candidates fear most, and Google in particular still asks it (the Blind 75 author says so on his own page, see [18](18-leetcode-master-list.md)). The fear disappears once DP is seen for what it is: **a recursive brute force that never solves the same subproblem twice.** This file covers one-dimensional states (index into one sequence, or an amount). Two-dimensional states (two sequences, grids, intervals, knapsack with an item index) are in [file 14](14-dynamic-programming-2d.md).

## 1. First principles — why this works

### 1.1 From brute force to DP in four steps

1. **Write the brute-force recursion** that makes one decision per call (rob house $i$ or not; which coin to take last; where the first word ends).
2. **Notice repeated subproblems.** The recursion tree for House Robber calls `best(i)` from both `best(i-1)` and `best(i-2)`, so the tree has $\Theta(\varphi^n)$ nodes but only $n$ distinct arguments.
3. **Memoise:** cache the answer for each distinct argument. The time becomes (number of states) × (work per state).
4. **Go bottom-up** (optional): fill the cache in an order where every dependency is computed first, then keep only the entries still needed (rolling variables).

A problem is a DP candidate when (a) the answer for a big input can be assembled from answers for smaller inputs of the same kind (*optimal substructure*), and (b) those smaller inputs repeat (*overlapping subproblems*). If they do not repeat, plain recursion or divide and conquer is enough.

### 1.2 The state must capture everything the future needs

A state is the minimal summary of the past that determines the best future. For House Robber, "the best total using houses $0..i$" is enough: whether house $i$ was robbed is decided inside the recurrence by comparing two options. For Maximum Product Subarray, "best product ending at $i$" is **not** enough, because a negative number turns the smallest product into the largest. The state must carry both the maximum and the minimum product ending at $i$. Choosing the state is where the problem is solved; the code follows.

### 1.3 Two shapes of 1D recurrence

- **Prefix DP:** $dp_i$ depends on a few earlier entries ($dp_{i-1}, dp_{i-2}$): Fibonacci, House Robber, Decode Ways, Kadane. These are $O(n)$ time and roll into $O(1)$ memory.
- **Choice-over-all-previous DP:** $dp_i = \text{best over } j < i$ of something, as in LIS, word break and coin change (where "previous" means amount minus coin). These are $O(n \cdot \text{choices})$. They are sometimes accelerated with binary search (LIS in $O(n \log n)$) or a trie (word break).

### 1.4 Why LIS can be $O(n \log n)$

Keep `tails[len]` = the smallest possible last element of an increasing subsequence of length `len + 1` seen so far. `tails` is strictly increasing: a length-$(L+1)$ subsequence contains a length-$L$ one with a smaller last element. For a new $x$, the longest subsequence it can extend ends with the largest tail $< x$. Replace the first tail $\ge x$ with $x$ (lower bound). That keeps every entry as small as possible, and the length of `tails` is the LIS length. Note that `tails` is not itself an increasing subsequence of the input; it only stores the best ending values per length.

## 2. Recurrences and complexities

| Problem | State | Recurrence | Answer | Time / space |
|---|---|---|---|---|
| Climbing Stairs | $f_i$ = ways to reach step $i$ | $f_i = f_{i-1} + f_{i-2}$, $f_0 = f_1 = 1$ | $f_n$ | $O(n)$ / $O(1)$ |
| House Robber | $b_i$ = best using houses $< i$ | $b_{i+1} = \max(b_i, b_{i-1} + a_i)$ | $b_n$ | $O(n)$ / $O(1)$ |
| Max subarray (Kadane) | $e_i$ = best sum ending at $i$ | $e_i = \max(a_i, e_{i-1} + a_i)$ | $\max_i e_i$ | $O(n)$ / $O(1)$ |
| Max product subarray | $(M_i, m_i)$ ending at $i$ | $M_i = \max(a_i, M_{i-1}a_i, m_{i-1}a_i)$, same for $m_i$ with min | $\max_i M_i$ | $O(n)$ / $O(1)$ |
| Coin Change (min coins) | $c_v$ = fewest coins for amount $v$ | $c_v = 1 + \min_{k \le v} c_{v-k}$, $c_0 = 0$ | $c_A$ | $O(A \cdot m)$ / $O(A)$ |
| Combination Sum IV (ordered ways) | $w_v$ | $w_v = \sum_k w_{v-k}$, $w_0 = 1$ | $w_T$ | $O(T m)$ |
| Word Break | $ok_i$ = prefix of length $i$ splits | $ok_i = \exists j < i: ok_j \wedge s[j..i) \in D$ | $ok_n$ | $O(n \cdot L_{\max})$ checks |
| Decode Ways | $d_i$ = ways for prefix of length $i$ | $d_i = [s_{i-1} \ne 0] d_{i-1} + [10 \le s_{i-2}s_{i-1} \le 26] d_{i-2}$ | $d_n$ | $O(n)$ / $O(1)$ |
| LIS | `tails` | lower bound + replace | `tails.size()` | $O(n \log n)$ |
| Weighted interval scheduling | $p_i$ = best using jobs sorted by end, first $i$ | $p_i = \max(p_{i-1}, w_i + p_{\text{last compatible}})$ | $p_n$ | $O(n \log n)$ |

## 3. Reusable templates (C++ and Java)

Top-down memoisation and bottom-up tabulation of the same recurrence (Climbing Stairs, [LC 70 · Climbing Stairs](https://leetcode.com/problems/climbing-stairs/) — Easy), plus Kadane ([LC 53 · Maximum Subarray](https://leetcode.com/problems/maximum-subarray/) — Medium):

```cpp
long long waysMemo(int i, vector<long long>& memo) {      // memo[i] = -1 means "not computed"
    if (i <= 1) return 1;
    if (memo[i] != -1) return memo[i];
    return memo[i] = waysMemo(i - 1, memo) + waysMemo(i - 2, memo);
}

long long waysBottomUp(int n) {                           // same recurrence, O(1) memory
    long long prev2 = 1, prev1 = 1;                       // f(i-2), f(i-1)
    for (int i = 2; i <= n; ++i) {
        long long cur = prev1 + prev2;
        prev2 = prev1;
        prev1 = cur;
    }
    return prev1;
}

int maxSubArray(const vector<int>& a) {                   // Kadane
    int bestEndingHere = a[0], best = a[0];
    for (size_t i = 1; i < a.size(); ++i) {
        bestEndingHere = max(a[i], bestEndingHere + a[i]); // extend, or start fresh at i
        best = max(best, bestEndingHere);
    }
    return best;
}
```

```java
static long waysMemo(int i, long[] memo) {
    if (i <= 1) return 1;
    if (memo[i] != -1) return memo[i];
    return memo[i] = waysMemo(i - 1, memo) + waysMemo(i - 2, memo);
}

static long waysBottomUp(int n) {
    long prev2 = 1, prev1 = 1;
    for (int i = 2; i <= n; i++) {
        long cur = prev1 + prev2;
        prev2 = prev1;
        prev1 = cur;
    }
    return prev1;
}

static int maxSubArray(int[] a) {
    int bestEndingHere = a[0], best = a[0];
    for (int i = 1; i < a.length; i++) {
        bestEndingHere = Math.max(a[i], bestEndingHere + a[i]);
        best = Math.max(best, bestEndingHere);
    }
    return best;
}
```

The DP checklist to say out loud in an interview:

```text
1. State:       dp[i] = <meaning in one sentence, with units>
2. Recurrence:  dp[i] = <formula over smaller states>   (why: the last decision is ...)
3. Base cases:  dp[0] = ..., dp[1] = ...
4. Order:       i increasing (every dependency is smaller)
5. Answer:      dp[n]  or  max over i of dp[i]
6. Complexity:  #states x work per state; memory can roll to O(1) if only k previous values are used
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "number of ways", "minimum / maximum cost", "is it possible", over a sequence | DP over prefixes |
| "cannot take adjacent", "cooldown", "at most one of each pair" | prefix DP with a take / skip choice |
| "fewest coins / squares / steps to reach an amount" | unbounded knapsack over the amount (1D) |
| "split a string into valid pieces" | $ok_i$ over prefixes; trie if the dictionary is large |
| "maximum subarray sum / product" | Kadane (keep max *and* min for products) |
| "longest increasing / chain / nested" | LIS: $O(n^2)$ DP or $O(n \log n)$ patience sorting |
| "pick non-overlapping jobs to maximise profit" | sort by end + DP + binary search for the last compatible job |
| "game: both play optimally, take 1–3 from the end" | $dp_i$ = best score difference from position $i$ (minimax) |
| greedy feels plausible but you can't prove it | write the DP; then look for a greedy shortcut |
| $n \le 20$ and subsets | bitmask DP, not 1D ([CP](../06-Dynamic-Programming/06-bitmask-dp.md)) |

## 5. Worked examples

### Example 1 — House Robber · Medium

- **Source:** [LC 198 · House Robber](https://leetcode.com/problems/house-robber/) — Medium · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1100 CF, est.)
- **Problem:** non-negative amounts $a_0..a_{n-1}$ ($n \le 100$, $a_i \le 400$). Choose houses with no two adjacent to maximise the total.
- **Thinking from first principles:** greedy "take every other house" fails on `2 1 1 2` (best is 4, using houses 0 and 3). Brute force decides each house in or out, giving $2^n$ choices. Decide from the end: either house $n-1$ is skipped (best of the first $n-1$), or it is taken, which forbids $n-2$ (best of the first $n-2$, plus $a_{n-1}$). Both subproblems are prefixes, and only two previous values are ever needed.

<details><summary>Solution</summary>

$b_{i+1} = \max(b_i,\ b_{i-1} + a_i)$, with $b_0 = 0$ (no houses) and $b_1 = a_0$. Rolling variables `skip` = $b_{i-1}$ and `take` = $b_i$. $O(n)$ time, $O(1)$ space.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int rob(vector<int>& nums) {
        int prev = 0, cur = 0;                    // best for houses [0, i-2] and [0, i-1]
        for (int x : nums) {
            int next = max(cur, prev + x);        // skip house i, or take it on top of [0, i-2]
            prev = cur;
            cur = next;
        }
        return cur;
    }
};

int main() {
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << Solution().rob(a) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int rob(int[] nums) {
        int prev = 0, cur = 0;
        for (int x : nums) {
            int next = Math.max(cur, prev + x);
            prev = cur;
            cur = next;
        }
        return cur;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        System.out.println(new Solution().rob(a));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
4
1 2 3 1
out:
4
-->
<!-- test
in:
5
2 7 9 3 1
out:
12
-->
<!-- test
in:
4
2 1 1 2
out:
4
-->
<!-- test
in:
1
0
out:
0
-->

### Example 2 — Coin Change · Medium

- **Source:** [LC 322 · Coin Change](https://leetcode.com/problems/coin-change/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** coin denominations ($\le 12$ of them, values up to $2^{31}-1$) with unlimited supply and an amount $A \le 10^4$. Return the fewest coins that make $A$, or $-1$.
- **Thinking from first principles:** greedy (largest coin first) fails for `{1, 3, 4}` and 6 (greedy gives 4+1+1 = 3 coins, the optimum is 3+3 = 2). Think about the **last coin** in an optimal multiset: if it is $k$, the rest is an optimal solution for $A - k$. So $c_v = 1 + \min_k c_{v-k}$ over coins $k \le v$, with $c_0 = 0$, and unreachable amounts are $\infty$. The states are the amounts $0..A$, there are $m$ choices each, and every dependency is a smaller amount, so a single increasing loop computes everything.

<details><summary>Solution</summary>

Use `A + 1` as infinity (no answer needs more than $A$ coins, since every coin is $\ge 1$), which avoids overflow in `+1`. Coins larger than $A$ are skipped, which also avoids `v - coin` overflow concerns. $O(A \cdot m)$ time, $O(A)$ space. BFS over amounts (each coin is an edge of weight 1) is an equivalent view.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int coinChange(vector<int>& coins, int amount) {
        vector<int> dp(amount + 1, amount + 1);          // amount + 1 acts as infinity
        dp[0] = 0;
        for (int v = 1; v <= amount; ++v)
            for (int c : coins)
                if (c <= v) dp[v] = min(dp[v], dp[v - c] + 1);   // c is the last coin used
        return dp[amount] > amount ? -1 : dp[amount];
    }
};

int main() {
    int m, amount;
    cin >> m >> amount;
    vector<int> coins(m);
    for (int& c : coins) cin >> c;
    cout << Solution().coinChange(coins, amount) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int coinChange(int[] coins, int amount) {
        int[] dp = new int[amount + 1];
        Arrays.fill(dp, amount + 1);
        dp[0] = 0;
        for (int v = 1; v <= amount; v++)
            for (int c : coins)
                if (c <= v) dp[v] = Math.min(dp[v], dp[v - c] + 1);
        return dp[amount] > amount ? -1 : dp[amount];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int m = in.nextInt(), amount = in.nextInt();
        int[] coins = new int[m];
        for (int i = 0; i < m; i++) coins[i] = in.nextInt();
        System.out.println(new Solution().coinChange(coins, amount));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
3 11
1 2 5
out:
3
-->
<!-- test
in:
1 3
2
out:
-1
-->
<!-- test
in:
1 0
1
out:
0
-->
<!-- test
in:
3 6
1 3 4
out:
2
-->
<!-- test
in:
2 7
2147483647 2
out:
-1
-->

### Example 3 — Word Break · Medium

- **Source:** [LC 139 · Word Break](https://leetcode.com/problems/word-break/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** can $s$ ($|s| \le 300$) be split into a sequence of dictionary words ($\le 1000$ words of length $\le 20$, reuse allowed)?
- **Thinking from first principles:** backtracking tries every first word and recurses on the rest. On `aaaa…ab` with words `a, aa, aaa` the same suffixes are re-solved exponentially often. The only thing a suffix's answer depends on is where it starts, so memoise on the position. Bottom-up: $ok_i$ means the prefix of length $i$ can be split, and $ok_i$ holds if some $j < i$ has $ok_j$ and $s[j..i) \in D$. Only $j \ge i - L_{\max}$ can work, which bounds the inner loop by the longest word.

<details><summary>Solution</summary>

Hash set of words plus the length bound. $O(n \cdot L_{\max})$ substring checks, each $O(L_{\max})$ to hash: $O(n L_{\max}^2)$ in total. A trie walk from each $j$ removes the hashing factor ([file 08](08-tries.md)). The driver reads $s$, $k$ and the words.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    bool wordBreak(string s, vector<string>& wordDict) {
        unordered_set<string> dict(wordDict.begin(), wordDict.end());
        size_t maxLen = 0;
        for (auto& w : wordDict) maxLen = max(maxLen, w.size());
        int n = s.size();
        vector<bool> ok(n + 1, false);
        ok[0] = true;                                          // the empty prefix
        for (int i = 1; i <= n; ++i)
            for (int j = i - 1; j >= 0 && i - j <= (int)maxLen; --j)
                if (ok[j] && dict.count(s.substr(j, i - j))) { ok[i] = true; break; }   // last word s[j, i)
        return ok[n];
    }
};

int main() {
    string s;
    int k;
    cin >> s >> k;
    vector<string> words(k);
    for (auto& w : words) cin >> w;
    cout << (Solution().wordBreak(s, words) ? "true" : "false") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public boolean wordBreak(String s, List<String> wordDict) {
        Set<String> dict = new HashSet<>(wordDict);
        int maxLen = 0;
        for (String w : wordDict) maxLen = Math.max(maxLen, w.length());
        int n = s.length();
        boolean[] ok = new boolean[n + 1];
        ok[0] = true;
        for (int i = 1; i <= n; i++)
            for (int j = i - 1; j >= 0 && i - j <= maxLen; j--)
                if (ok[j] && dict.contains(s.substring(j, i))) { ok[i] = true; break; }
        return ok[n];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        String s = in.next();
        int k = in.nextInt();
        List<String> words = new ArrayList<>();
        for (int i = 0; i < k; i++) words.add(in.next());
        System.out.println(new Solution().wordBreak(s, words));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
leetcode 2
leet code
out:
true
-->
<!-- test
in:
applepenapple 2
apple pen
out:
true
-->
<!-- test
in:
catsandog 5
cats dog sand and cat
out:
false
-->
<!-- test
in:
aaaaaaaaaaaaaaaaaaaaaaaaaaaaab 3
a aa aaa
out:
false
-->

### Example 4 — Longest Increasing Subsequence · Medium

- **Source:** [LC 300 · Longest Increasing Subsequence](https://leetcode.com/problems/longest-increasing-subsequence/) — Medium · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1500 CF, est.)
- **Problem:** length of the longest **strictly** increasing subsequence of $n \le 2500$ integers. Follow-up: $O(n \log n)$.
- **Thinking from first principles:** the $O(n^2)$ DP comes first. $L_i$ = the longest increasing subsequence ending at $i$, $L_i = 1 + \max\{L_j : j < i, a_j < a_i\}$. To speed it up, notice that for a fixed length only the **smallest possible ending value** matters, since a smaller tail can be extended by more future elements. Keeping one best tail per length gives the `tails` array of §1.4. It is sorted, so each new element is placed with a binary search.

<details><summary>Solution</summary>

For each $x$: `lower_bound(tails, x)` finds the first tail $\ge x$. If there is none, $x$ extends the longest subsequence (append). Otherwise $x$ becomes a better tail for that length (replace). Using the lower bound (first $\ge$) makes the subsequence strictly increasing. For non-decreasing subsequences, use the upper bound. $O(n \log n)$ time, $O(n)$ space.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int lengthOfLIS(vector<int>& nums) {
        vector<int> tails;                                // tails[k]: smallest tail of a length-(k+1) LIS
        for (int x : nums) {
            auto it = lower_bound(tails.begin(), tails.end(), x);
            if (it == tails.end()) tails.push_back(x);    // extends the longest one
            else *it = x;                                 // a smaller tail for this length
        }
        return tails.size();
    }
};

int main() {
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << Solution().lengthOfLIS(a) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int lengthOfLIS(int[] nums) {
        int[] tails = new int[nums.length];
        int size = 0;
        for (int x : nums) {
            int lo = 0, hi = size;                        // first index with tails[i] >= x
            while (lo < hi) {
                int mid = (lo + hi) >>> 1;
                if (tails[mid] >= x) hi = mid; else lo = mid + 1;
            }
            tails[lo] = x;
            if (lo == size) size++;
        }
        return size;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        System.out.println(new Solution().lengthOfLIS(a));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
8
10 9 2 5 3 7 101 18
out:
4
-->
<!-- test
in:
6
0 1 0 3 2 3
out:
4
-->
<!-- test
in:
7
7 7 7 7 7 7 7
out:
1
-->
<!-- test
in:
1
-5
out:
1
-->

### Example 5 — Maximum Product Subarray · Medium

- **Source:** [LC 152 · Maximum Product Subarray](https://leetcode.com/problems/maximum-product-subarray/) — Medium · `G169` `B75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1500 CF, est.)
- **Problem:** the largest product of a non-empty contiguous subarray. $n \le 2 \cdot 10^4$, $a_i \in [-10, 10]$, and every prefix or suffix product fits in 32 bits.
- **Thinking from first principles:** Kadane's "best ending here" fails because multiplying by a negative number turns the *most negative* product into the *most positive* one. So the state must remember both extremes: $M_i$ (largest product ending at $i$) and $m_i$ (smallest). The best subarray ending at $i$ is $a_i$ alone, or $a_i$ times one of the previous extremes. A zero resets both to 0, which the formula handles automatically because "$a_i$ alone" restarts the product after it.

<details><summary>Solution</summary>

$M_i = \max(a_i, a_i M_{i-1}, a_i m_{i-1})$ and $m_i = \min(a_i, a_i M_{i-1}, a_i m_{i-1})$, computed from the *old* values (use temporaries). $O(n)$ time, $O(1)$ space. An alternative argument: the answer is the maximum over all prefix products and suffix products, restarting after zeros.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int maxProduct(vector<int>& nums) {
        int hi = nums[0], lo = nums[0], best = nums[0];   // largest / smallest product ending here
        for (size_t i = 1; i < nums.size(); ++i) {
            int x = nums[i];
            int a = hi * x, b = lo * x;                   // use the old hi and lo
            hi = max({x, a, b});
            lo = min({x, a, b});
            best = max(best, hi);
        }
        return best;
    }
};

int main() {
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << Solution().maxProduct(a) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int maxProduct(int[] nums) {
        int hi = nums[0], lo = nums[0], best = nums[0];
        for (int i = 1; i < nums.length; i++) {
            int x = nums[i], a = hi * x, b = lo * x;
            hi = Math.max(x, Math.max(a, b));
            lo = Math.min(x, Math.min(a, b));
            best = Math.max(best, hi);
        }
        return best;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        System.out.println(new Solution().maxProduct(a));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
4
2 3 -2 4
out:
6
-->
<!-- test
in:
3
-2 0 -1
out:
0
-->
<!-- test
in:
1
-3
out:
-3
-->
<!-- test
in:
4
-2 3 -4 -1
out:
24
-->
<!-- test
in:
3
-2 -3 0
out:
6
-->

## 6. Pitfalls and things to remember

1. **Say the state in words before coding.** "dp[i] is the best total using houses 0..i−1" prevents index bugs. Mixing "length $i$" and "index $i$" is the most common off-by-one.
2. **Base cases and the empty prefix:** `dp[0]` usually means "nothing chosen yet" (0 coins, 1 way, `true`). Forgetting it breaks the first real step.
3. **Infinity that overflows:** `INT_MAX + 1` wraps to negative. Use a safe sentinel (`amount + 1`, `INF / 2`) or check before adding.
4. **Update from old values:** in rolling DPs (max product, two-state DPs) compute all new values from the previous ones before overwriting anything.
5. **Counting order matters:** for *ordered* sequences (Combination Sum IV) loop amount outside, coins inside. For *unordered* combinations (Coin Change II) loop coins outside ([file 14](14-dynamic-programming-2d.md)).
6. **Counts overflow:** "number of ways" grows exponentially. Use 64-bit or the requested modulus. LeetCode sometimes guarantees 32-bit answers but intermediate values can exceed them (Combination Sum IV).
7. **Memoisation in Java:** a `HashMap<Integer, …>` memo is slow and boxes keys. Use an array with a sentinel. Deep recursion (memoised top-down on $10^5$ states) can overflow the stack, so go bottom-up.
8. **LIS with `lower_bound` vs `upper_bound`:** lower bound for strictly increasing, upper bound for non-decreasing.
9. **`substr` in hot loops** allocates. Fine at these sizes, but mention the trie or rolling-hash alternative.
10. **Greedy temptation:** "largest coin first", "rob every other house" fail. Test a greedy on a small counterexample before committing.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| House Robber → "houses in a circle" | the first and last can't both be taken: max of the line DP on `[0, n-2]` and on `[1, n-1]` ([LC 213 · House Robber II](https://leetcode.com/problems/house-robber-ii/) — Medium) |
| → "houses on a binary tree" | tree DP returning (best with root robbed, best without) ([LC 337 · House Robber III](https://leetcode.com/problems/house-robber-iii/) — Medium) |
| Coin Change → "number of ways" | unordered: coins outer loop; ordered: amount outer loop ([LC 518 · Coin Change II](https://leetcode.com/problems/coin-change-ii/) — Medium, [LC 377 · Combination Sum IV](https://leetcode.com/problems/combination-sum-iv/) — Medium) |
| → "return the coins used" | store `choice[v]` = the last coin; walk back from $A$ |
| Word Break → "return all sentences" | memoise the list of sentences per suffix; the output can be exponential ([LC 140 · Word Break II](https://leetcode.com/problems/word-break-ii/) — Hard) |
| LIS → "reconstruct the subsequence" | store, for each element, the index of its predecessor (the element at `tails[pos-1]` when it was placed) |
| → "number of LIS" | $O(n^2)$ DP with (length, count) per index ([LC 673 · Number of Longest Increasing Subsequence](https://leetcode.com/problems/number-of-longest-increasing-subsequence/) — Medium) |
| → "2D: envelopes" | sort by width ascending and height **descending**, then LIS on heights ([LC 354 · Russian Doll Envelopes](https://leetcode.com/problems/russian-doll-envelopes/) — Hard) |
| Max product → "what if values can be large?" | products overflow fast: use 64-bit, or log-sums with sign tracking |
| "Top-down or bottom-up?" | top-down is easier to derive and only visits reachable states; bottom-up avoids recursion depth and allows rolling arrays |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium.

**Easy** (3)

- [ ] [LC 70 · Climbing Stairs](https://leetcode.com/problems/climbing-stairs/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 746 · Min Cost Climbing Stairs](https://leetcode.com/problems/min-cost-climbing-stairs/) — Easy · `NC150`
- [ ] [LC 1137 · N-th Tribonacci Number](https://leetcode.com/problems/n-th-tribonacci-number/) — Easy · `NC250`

**Medium** (15)

- [ ] [LC 5 · Longest Palindromic Substring](https://leetcode.com/problems/longest-palindromic-substring/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 53 · Maximum Subarray](https://leetcode.com/problems/maximum-subarray/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 91 · Decode Ways](https://leetcode.com/problems/decode-ways/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 120 · Triangle](https://leetcode.com/problems/triangle/) — Medium · `TI150`
- [ ] [LC 139 · Word Break](https://leetcode.com/problems/word-break/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 152 · Maximum Product Subarray](https://leetcode.com/problems/maximum-product-subarray/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 198 · House Robber](https://leetcode.com/problems/house-robber/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 213 · House Robber II](https://leetcode.com/problems/house-robber-ii/) — Medium · `B75` `NC150`
- [ ] [LC 279 · Perfect Squares](https://leetcode.com/problems/perfect-squares/) — Medium · `NC250`
- [ ] [LC 300 · Longest Increasing Subsequence](https://leetcode.com/problems/longest-increasing-subsequence/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 322 · Coin Change](https://leetcode.com/problems/coin-change/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 343 · Integer Break](https://leetcode.com/problems/integer-break/) — Medium · `NC250`
- [ ] [LC 377 · Combination Sum IV](https://leetcode.com/problems/combination-sum-iv/) — Medium · `G169` `NC250`
- [ ] [LC 647 · Palindromic Substrings](https://leetcode.com/problems/palindromic-substrings/) — Medium · `B75` `NC150`
- [ ] [LC 918 · Maximum Sum Circular Subarray](https://leetcode.com/problems/maximum-sum-circular-subarray/) — Medium · `NC250` `TI150`

**Hard** (2)

- [ ] [LC 1235 · Maximum Profit in Job Scheduling](https://leetcode.com/problems/maximum-profit-in-job-scheduling/) — Hard · `G75`
- [ ] [LC 1406 · Stone Game III](https://leetcode.com/problems/stone-game-iii/) — Hard · `NC250`

Longest Palindromic Substring and Palindromic Substrings are listed here as the lists file them, but the expected interview solution is **expand around centre**: for each of the $2n - 1$ centres, grow while the ends match, $O(n^2)$ time and $O(1)$ space. Manacher's algorithm gives $O(n)$ ([CP: Manacher](../11-Strings/04-manacher-and-palindromes.md)).

**Beyond the lists:**

- [ ] [LC 740 · Delete and Earn](https://leetcode.com/problems/delete-and-earn/) — Medium — House Robber on value buckets
- [ ] [LC 983 · Minimum Cost For Tickets](https://leetcode.com/problems/minimum-cost-for-tickets/) — Medium — dp over days
- [ ] [LC 2140 · Solving Questions With Brainpower](https://leetcode.com/problems/solving-questions-with-brainpower/) — Medium — suffix DP with jumps
- [ ] [LC 1048 · Longest String Chain](https://leetcode.com/problems/longest-string-chain/) — Medium — sort by length, hash of predecessors
- [ ] [LC 646 · Maximum Length of Pair Chain](https://leetcode.com/problems/maximum-length-of-pair-chain/) — Medium — LIS or greedy by end
- [ ] [LC 673 · Number of Longest Increasing Subsequence](https://leetcode.com/problems/number-of-longest-increasing-subsequence/) — Medium — (length, count) pairs
- [ ] [LC 935 · Knight Dialer](https://leetcode.com/problems/knight-dialer/) — Medium — 10-state DP over steps
- [ ] [LC 368 · Largest Divisible Subset](https://leetcode.com/problems/largest-divisible-subset/) — Medium — LIS-style with reconstruction
- [ ] [LC 354 · Russian Doll Envelopes](https://leetcode.com/problems/russian-doll-envelopes/) — Hard — sort trick + LIS
- [ ] [LC 32 · Longest Valid Parentheses](https://leetcode.com/problems/longest-valid-parentheses/) — Hard — $dp_i$ = longest valid ending at $i$ (or the stack method)

## 9. CP counterpart

- [DP first principles and state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md): the same four steps, with harder state design at 1700–2100.
- [Knapsack family](../06-Dynamic-Programming/02-knapsack-family.md): coin change and its relatives in full.
- [Sequence DP: LIS, LCS, edit distance](../06-Dynamic-Programming/03-sequence-dp-lis-lcs-edit-distance.md): LIS with segment trees, counting LIS, Dilworth.
- [Minimax and game DP](../13-Game-Theory/04-minimax-and-game-dp.md): Stone Game style problems.

Transfers: all of it. CP needs faster transitions (prefix sums, monotone queues, convex hull trick, [DP optimisations](../07-DP-Optimizations/README.md)), which are overkill in interviews. Interviews reward a clearly stated state and a clean rolling-array implementation.

## 10. Self-check

1. What two properties make a problem suitable for DP?
2. Why does greedy fail for Coin Change, and what is the recurrence?
3. Why must Maximum Product Subarray track the minimum as well as the maximum?
4. Prove that `tails` in the LIS algorithm stays sorted.
5. In Word Break, why can the inner loop stop after `maxLen` characters?
6. Convert House Robber's recurrence into $O(1)$ memory and name the two variables.
7. When do you loop coins outside vs amount outside in counting problems, and why?
8. What is the time complexity of a memoised recursion in general?

<details><summary>Answers</summary>

1. Optimal substructure (an optimal answer is built from optimal answers to subproblems) and overlapping subproblems (the same subproblems recur).
2. For `{1, 3, 4}` and 6 greedy uses 4+1+1 while 3+3 is better. $c_v = 1 + \min_{k \le v} c_{v-k}$, $c_0 = 0$.
3. A negative factor maps the smallest product ending at $i-1$ to the largest product ending at $i$, so the maximum alone loses that candidate.
4. If `tails[k] >= tails[k+1]`, take the increasing subsequence of length $k+2$ ending at `tails[k+1]`. Its first $k+1$ elements form an increasing subsequence of length $k+1$ whose last element is smaller than `tails[k+1]` and therefore smaller than `tails[k]`, contradicting minimality.
5. A word longer than the longest dictionary word cannot be in the dictionary, so $s[j..i)$ with $i - j > L_{\max}$ never matches.
6. `prev` = best for houses up to $i-2$, `cur` = best up to $i-1$; `next = max(cur, prev + a[i])`, then shift.
7. Coins outside counts each multiset once (coins are added in a fixed order). Amount outside counts ordered sequences, since every coin can be the last one for every amount.
8. (Number of distinct states reachable) × (work per state, excluding the recursive calls).

</details>
