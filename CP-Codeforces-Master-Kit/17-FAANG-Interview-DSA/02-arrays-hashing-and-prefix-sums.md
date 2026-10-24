# Arrays, Hashing and Prefix Sums

> **Band:** 🟢 ≤ 1400 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [interview framework](01-interview-framework-and-communication.md), [STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md)
> **You can say you know this when:** you turn any "find a pair / count subarrays / group equal things" question into a one-pass hash-map or prefix-sum solution in under 15 minutes, and can explain why it is O(n) expected and what the worst case is.

About one in four interview questions starts here, and most of the others use these tools as a sub-step. This file covers three ideas: **remember what you have seen** (hash sets and maps), **canonical keys** (group things that are equal under some transformation), and **prefix sums** (turn a range question into a question about two points).

## 1. First principles — why this works

### 1.1 Pair search becomes a lookup

The naive answer to "is there a pair $i < j$ with $a_i + a_j = T$?" checks all $\binom{n}{2}$ pairs, which is $O(n^2)$. The waste: for a fixed $j$ the only question is *"has the value $T - a_j$ appeared before index $j$?"*. That is a membership query. If you keep everything seen so far in a hash set, each query is $O(1)$ expected, and one left-to-right pass is $O(n)$.

The general move: **fix one end of the pair, and ask a data structure about the other end.** The data structure depends on the question:

| Question about earlier elements | Structure | Cost per step |
|---|---|---|
| does value $v$ exist? | hash set | $O(1)$ expected |
| how many times did $v$ appear? where first/last? | hash map value → count / index | $O(1)$ expected |
| is there a value in $[v-d, v+d]$? | ordered set (`std::set`, `TreeSet`) | $O(\log n)$ |
| smallest / largest so far | one variable | $O(1)$ |

### 1.2 Canonical keys

"Group words that are anagrams" asks you to group by an **equivalence relation**. Map each item to a *canonical representative* that is equal for exactly the equivalent items, then hash that key. For anagrams the key can be the sorted string ($O(L \log L)$) or the 26-letter count vector ($O(L)$). For "isomorphic strings" it is the pattern of first occurrences (`"paper"` → `0 1 0 2 3`). Correctness rests on one check: *two items are equivalent if and only if their keys are equal.*

### 1.3 Prefix sums turn ranges into pairs

Let $P_0 = 0$ and $P_{i+1} = P_i + a_i$. Then

$$\text{sum}(a_l..a_r) = P_{r+1} - P_l .$$

A question about a **subarray** becomes a question about a **pair of prefix values**. "Count subarrays with sum $k$" becomes "count pairs $i < j$ with $P_j - P_i = k$", which is Two Sum again: for each $j$, add the number of earlier prefixes equal to $P_j - k$. This works with negative numbers, which is exactly where the sliding window from [file 03](03-two-pointers-and-sliding-window.md) breaks.

The same idea with products gives "product of everything except me": $\text{left}_i \cdot \text{right}_i$, where $\text{left}_i = a_0 \cdots a_{i-1}$ and $\text{right}_i = a_{i+1} \cdots a_{n-1}$. No division is needed, so zeros are not a special case.

### 1.4 Why hashing is "O(1)", and when it is not

A hash table with $m$ buckets and $n$ keys has load factor $\alpha = n/m$. If the hash spreads keys uniformly, a lookup inspects $1 + \alpha$ entries on average, and tables resize to keep $\alpha \le$ a constant (about 1 in `unordered_map`, 0.75 in `HashMap`). Resizing doubles $m$, so the total rehash work over $n$ inserts is $O(n)$ (amortised $O(1)$). The worst case is $O(n)$ per operation when many keys collide. Interviews accept "O(1) expected". In Codeforces, adversaries build anti-hash tests, which is why CP code uses a randomised hash (see [randomised hashing](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md)).

## 2. Definitions, identities and complexities

| Fact | Formula / cost | Why |
|---|---|---|
| Range sum | $\sum_{t=l}^{r} a_t = P_{r+1} - P_l$ | telescoping |
| 2D range sum | $S = P_{r_2+1,c_2+1} - P_{r_1,c_2+1} - P_{r_2+1,c_1} + P_{r_1,c_1}$ | inclusion-exclusion on four corner rectangles |
| 2D build | $P_{i+1,j+1} = g_{ij} + P_{i,j+1} + P_{i+1,j} - P_{ij}$ | same identity, solved for the corner |
| Subarrays with sum $k$ | $\sum_j \#\{i<j : P_i = P_j - k\}$ | pair counting on prefixes |
| Subarray sum divisible by $k$ | count pairs with $P_i \equiv P_j \pmod k$ | difference divisible ⇔ same residue |
| Number of subarrays | $n(n+1)/2$ | choose $l \le r$ |
| Difference array | $D_l \mathrel{+}= v,\ D_{r+1} \mathrel{-}= v$, then prefix-sum $D$ | inverse of the prefix sum |
| Majority (Boyer–Moore) | the candidate survives because each "cancel" removes one majority and one other element | a value seen $> n/2$ times cannot be fully cancelled |
| Hash map insert / find | $O(1)$ expected, $O(n)$ worst | load factor argument above |
| Java `HashMap` worst case | $O(\log n)$ per bucket for `Comparable` keys | buckets with ≥ 8 entries become red-black trees once the table has ≥ 64 buckets (Java 8+) |
| Sort | $O(n \log n)$; counting sort $O(n + \sigma)$ for alphabet size $\sigma$ | |

## 3. Reusable templates (C++ and Java)

Prefix sums in one and two dimensions, plus the "first occurrence of each prefix" variant used for *longest* subarray questions.

```cpp
// P[i] = a[0] + ... + a[i-1], so sum(l..r) = P[r+1] - P[l]
vector<long long> prefixSums(const vector<int>& a) {
    vector<long long> P(a.size() + 1, 0);
    for (size_t i = 0; i < a.size(); ++i) P[i + 1] = P[i] + a[i];
    return P;
}

struct Prefix2D {
    vector<vector<long long>> P;   // one row and one column of zero padding
    explicit Prefix2D(const vector<vector<int>>& g) {
        int n = g.size(), m = n ? g[0].size() : 0;
        P.assign(n + 1, vector<long long>(m + 1, 0));
        for (int i = 0; i < n; ++i)
            for (int j = 0; j < m; ++j)
                P[i + 1][j + 1] = g[i][j] + P[i][j + 1] + P[i + 1][j] - P[i][j];
    }
    long long query(int r1, int c1, int r2, int c2) const {   // inclusive corners
        return P[r2 + 1][c2 + 1] - P[r1][c2 + 1] - P[r2 + 1][c1] + P[r1][c1];
    }
};

// Longest subarray with sum exactly k: keep the FIRST index where each prefix value appeared.
int longestSubarrayWithSum(const vector<int>& a, long long k) {
    unordered_map<long long, int> first;
    first[0] = -1;                              // empty prefix ends "before" index 0
    long long prefix = 0;
    int best = 0;
    for (int j = 0; j < (int)a.size(); ++j) {
        prefix += a[j];
        auto it = first.find(prefix - k);
        if (it != first.end()) best = max(best, j - it->second);
        first.emplace(prefix, j);               // emplace keeps the earlier index if present
    }
    return best;
}
```

```java
static long[] prefixSums(int[] a) {
    long[] p = new long[a.length + 1];
    for (int i = 0; i < a.length; i++) p[i + 1] = p[i] + a[i];
    return p;
}

static class Prefix2D {
    final long[][] p;
    Prefix2D(int[][] g) {
        int n = g.length, m = n == 0 ? 0 : g[0].length;
        p = new long[n + 1][m + 1];
        for (int i = 0; i < n; i++)
            for (int j = 0; j < m; j++)
                p[i + 1][j + 1] = g[i][j] + p[i][j + 1] + p[i + 1][j] - p[i][j];
    }
    long query(int r1, int c1, int r2, int c2) {
        return p[r2 + 1][c2 + 1] - p[r1][c2 + 1] - p[r2 + 1][c1] + p[r1][c1];
    }
}

static int longestSubarrayWithSum(int[] a, long k) {
    Map<Long, Integer> first = new HashMap<>();
    first.put(0L, -1);
    long prefix = 0;
    int best = 0;
    for (int j = 0; j < a.length; j++) {
        prefix += a[j];
        Integer i = first.get(prefix - k);
        if (i != null) best = Math.max(best, j - i);
        first.putIfAbsent(prefix, j);
    }
    return best;
}
```

Frequency counting over a small alphabet is faster and simpler with an array than with a map:

```cpp
bool isAnagram(const string& s, const string& t) {
    if (s.size() != t.size()) return false;
    array<int, 26> cnt{};
    for (char c : s) cnt[c - 'a']++;
    for (char c : t) if (--cnt[c - 'a'] < 0) return false;   // t uses a letter more often than s
    return true;
}
```

```java
static boolean isAnagram(String s, String t) {
    if (s.length() != t.length()) return false;
    int[] cnt = new int[26];
    for (int i = 0; i < s.length(); i++) cnt[s.charAt(i) - 'a']++;
    for (int i = 0; i < t.length(); i++) if (--cnt[t.charAt(i) - 'a'] < 0) return false;
    return true;
}
```

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| "two numbers that add up to", "pair with difference $d$" | one pass, hash map of earlier values |
| "contains duplicate", "first repeated", "seen before" | hash set |
| "group", "anagram", "same pattern", "isomorphic" | canonical key → hash map of lists |
| "subarray sum equals / divisible by $k$", negatives allowed | prefix sums + hash map of prefix counts |
| "longest subarray with equal 0s and 1s" | map 0 → −1, then longest subarray with sum 0 (first-occurrence map) |
| many range-sum queries on a fixed array or grid | 1D / 2D prefix sums |
| many range *updates*, read at the end | difference array |
| "except self", "left and right of $i$" | prefix and suffix arrays (or two passes) |
| "$O(n)$ time" with an unsorted array and a sorting-like goal | hash set (consecutive runs) or counting / bucket sort |
| values in $[1, n]$, $O(1)$ extra space | use the array itself as the hash table (index marking, cyclic sort) |

Often confused with: **sliding window** (only valid when extending the window moves the quantity monotonically, e.g. all numbers positive) and **sorting + two pointers** (fine when indices need not be returned, or the input is already sorted).

## 5. Worked examples

### Example 1 — Two Sum · Easy

- **Source:** [LC 1 · Two Sum](https://leetcode.com/problems/two-sum/) — Easy · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Easy (≈ 800 CF, est.)
- **Problem:** given $n \le 10^4$ integers in $[-10^9, 10^9]$ and a target, return the indices of the two distinct positions whose values sum to the target. Exactly one answer exists.
- **Thinking from first principles:** brute force tries every pair, $O(n^2)$. Sorting plus two pointers is $O(n \log n)$ but loses the original indices unless you sort index pairs. For each $j$ the only question is whether $T - a_j$ appeared earlier, which is a hash-map lookup. Insert $a_j$ *after* the lookup so that an element never pairs with itself, while two equal values (`3 3`, target 6) still work.

<details><summary>Solution</summary>

One pass with a map from value to index. Correctness: the answer pair $(i, j)$ with $i < j$ is found at step $j$, because $a_i$ was inserted at step $i$. Time $O(n)$ expected, space $O(n)$. `target - nums[i]` lies in $[-2 \cdot 10^9, 2 \cdot 10^9]$, which fits in a 32-bit `int` ($2^{31} - 1 \approx 2.147 \cdot 10^9$). With wider ranges you would need 64-bit arithmetic.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<int> twoSum(vector<int>& nums, int target) {
        unordered_map<int, int> seen;            // value -> index where it appeared
        seen.reserve(nums.size() * 2);
        for (int i = 0; i < (int)nums.size(); ++i) {
            auto it = seen.find(target - nums[i]);
            if (it != seen.end()) return {it->second, i};
            seen[nums[i]] = i;                    // insert after the lookup: no self-pairing
        }
        return {};
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, target;
    cin >> n >> target;
    vector<int> nums(n);
    for (int& x : nums) cin >> x;
    vector<int> ans = Solution().twoSum(nums, target);
    cout << ans[0] << ' ' << ans[1] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int[] twoSum(int[] nums, int target) {
        Map<Integer, Integer> seen = new HashMap<>();
        for (int i = 0; i < nums.length; i++) {
            Integer j = seen.get(target - nums[i]);
            if (j != null) return new int[]{j, i};
            seen.put(nums[i], i);
        }
        return new int[0];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), target = in.nextInt();
        int[] nums = new int[n];
        for (int i = 0; i < n; i++) nums[i] = in.nextInt();
        int[] ans = new Solution().twoSum(nums, target);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(ans[0] + " " + ans[1]);
        out.flush();
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
4 9
2 7 11 15
out:
0 1
-->
<!-- test
in:
2 6
3 3
out:
0 1
-->
<!-- test
in:
5 -8
-1 -2 -3 -4 -5
out:
2 4
-->
<!-- test
in:
3 0
1000000000 5 -1000000000
out:
0 2
-->

### Example 2 — Group Anagrams · Medium

- **Source:** [LC 49 · Group Anagrams](https://leetcode.com/problems/group-anagrams/) — Medium · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1100 CF, est.)
- **Problem:** given up to $10^4$ lowercase words of length ≤ 100, group the words that are anagrams of each other. Groups may be returned in any order.
- **Thinking from first principles:** comparing every pair of words is $O(n^2 L)$. "Is an anagram of" is an equivalence relation, so give every word a key that is equal exactly for anagrams. The sorted letters are such a key: two words are anagrams if and only if they sort to the same string. Then one hash map from key to group does the grouping.

<details><summary>Solution</summary>

Key = sorted word. Time $O(n L \log L)$, space $O(nL)$. A count-vector key (26 counts joined into a string) gives $O(nL)$. Mention it as the follow-up answer, but the sorted key is shorter to write and fine for $L \le 100$. The driver sorts each group and then the list of groups, so the printed output does not depend on hash-map iteration order.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<vector<string>> groupAnagrams(vector<string>& strs) {
        unordered_map<string, vector<string>> groups;
        for (const string& s : strs) {
            string key = s;
            sort(key.begin(), key.end());          // anagrams share their sorted letters
            groups[key].push_back(s);
        }
        vector<vector<string>> res;
        res.reserve(groups.size());
        for (auto& [key, g] : groups) res.push_back(move(g));
        return res;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<string> strs(n);
    for (auto& s : strs) cin >> s;
    auto groups = Solution().groupAnagrams(strs);
    for (auto& g : groups) sort(g.begin(), g.end());
    sort(groups.begin(), groups.end());
    cout << groups.size() << '\n';
    for (auto& g : groups) {
        for (size_t i = 0; i < g.size(); ++i) cout << (i ? " " : "") << g[i];
        cout << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public List<List<String>> groupAnagrams(String[] strs) {
        Map<String, List<String>> groups = new HashMap<>();
        for (String s : strs) {
            char[] c = s.toCharArray();
            Arrays.sort(c);
            groups.computeIfAbsent(new String(c), k -> new ArrayList<>()).add(s);
        }
        return new ArrayList<>(groups.values());
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        String[] strs = new String[n];
        for (int i = 0; i < n; i++) strs[i] = in.next();
        List<List<String>> groups = new Solution().groupAnagrams(strs);
        for (List<String> g : groups) Collections.sort(g);
        groups.sort((a, b) -> {                       // lexicographic order on lists of strings
            for (int i = 0; i < Math.min(a.size(), b.size()); i++) {
                int c = a.get(i).compareTo(b.get(i));
                if (c != 0) return c;
            }
            return Integer.compare(a.size(), b.size());
        });
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(groups.size());
        for (List<String> g : groups) out.println(String.join(" ", g));
        out.flush();
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
6
eat tea tan ate nat bat
out:
3
ate eat tea
bat
nat tan
-->
<!-- test
in:
1
a
out:
1
a
-->
<!-- test
in:
4
ab ba ab abc
out:
2
ab ab ba
abc
-->

### Example 3 — Product of Array Except Self · Medium

- **Source:** [LC 238 · Product of Array Except Self](https://leetcode.com/problems/product-of-array-except-self/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** for each index return the product of all other elements, in $O(n)$ time, **without division**. $2 \le n \le 10^5$; every prefix and suffix product fits in 32 bits.
- **Thinking from first principles:** "total product / $a_i$" fails on zeros and is forbidden anyway. Split the product at $i$: everything to the left times everything to the right. Both sides are prefix products, one from each end. Build the left products in the output array, then sweep right-to-left with a single running suffix variable. That gives $O(1)$ extra space, since the output array is not counted.

<details><summary>Solution</summary>

`ans[i]` first holds $a_0 \cdots a_{i-1}$ (empty product 1). The backward pass multiplies in $a_{i+1} \cdots a_{n-1}$. Time $O(n)$, extra space $O(1)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<int> productExceptSelf(vector<int>& nums) {
        int n = nums.size();
        vector<int> ans(n, 1);
        for (int i = 1; i < n; ++i) ans[i] = ans[i - 1] * nums[i - 1];   // prefix product
        int suffix = 1;
        for (int i = n - 1; i >= 0; --i) {
            ans[i] *= suffix;            // times product of nums[i+1..n-1]
            suffix *= nums[i];
        }
        return ans;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> nums(n);
    for (int& x : nums) cin >> x;
    vector<int> ans = Solution().productExceptSelf(nums);
    for (int i = 0; i < n; ++i) cout << ans[i] << (i + 1 < n ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int[] productExceptSelf(int[] nums) {
        int n = nums.length;
        int[] ans = new int[n];
        ans[0] = 1;
        for (int i = 1; i < n; i++) ans[i] = ans[i - 1] * nums[i - 1];
        int suffix = 1;
        for (int i = n - 1; i >= 0; i--) {
            ans[i] *= suffix;
            suffix *= nums[i];
        }
        return ans;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] nums = new int[n];
        for (int i = 0; i < n; i++) nums[i] = in.nextInt();
        int[] ans = new Solution().productExceptSelf(nums);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.append(ans[i]).append(i + 1 < n ? ' ' : '\n');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
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
1 2 3 4
out:
24 12 8 6
-->
<!-- test
in:
5
-1 1 0 -3 3
out:
0 0 9 0 0
-->
<!-- test
in:
2
5 7
out:
7 5
-->
<!-- test
in:
4
0 2 0 3
out:
0 0 0 0
-->

### Example 4 — Subarray Sum Equals K · Medium

- **Source:** [LC 560 · Subarray Sum Equals K](https://leetcode.com/problems/subarray-sum-equals-k/) — Medium · `G169` `NC250`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** count the contiguous subarrays whose sum is exactly $k$. $n \le 2 \cdot 10^4$, $|a_i| \le 1000$, $|k| \le 10^7$; **negative values allowed**.
- **Thinking from first principles:** $O(n^2)$ by fixing the left end and extending is acceptable for $n = 2 \cdot 10^4$ in C++ but not in the interview's eyes. A sliding window fails: with negative numbers, growing the window can decrease the sum, so there is no monotone rule for moving the left end. Rewrite with prefix sums: subarray $(i, j]$ has sum $P_j - P_i$. For each $j$ count the earlier $i$ with $P_i = P_j - k$, which is Two Sum with counts. Seed the map with $P_0 = 0$ so subarrays that start at index 0 are counted.

<details><summary>Solution</summary>

Map prefix value → number of times it occurred. Each step adds `count[prefix - k]` and then records `prefix`. The order matters: look up before inserting, or a zero-length subarray would be counted when $k = 0$. Time $O(n)$ expected, space $O(n)$. $|P| \le 2 \cdot 10^7$ fits in an `int`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int subarraySum(vector<int>& nums, int k) {
        unordered_map<int, int> count;   // prefix value -> occurrences so far
        count[0] = 1;                    // the empty prefix
        int prefix = 0, res = 0;
        for (int x : nums) {
            prefix += x;
            auto it = count.find(prefix - k);
            if (it != count.end()) res += it->second;
            ++count[prefix];
        }
        return res;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, k;
    cin >> n >> k;
    vector<int> nums(n);
    for (int& x : nums) cin >> x;
    cout << Solution().subarraySum(nums, k) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int subarraySum(int[] nums, int k) {
        Map<Integer, Integer> count = new HashMap<>();
        count.put(0, 1);
        int prefix = 0, res = 0;
        for (int x : nums) {
            prefix += x;
            res += count.getOrDefault(prefix - k, 0);
            count.merge(prefix, 1, Integer::sum);
        }
        return res;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt();
        int[] nums = new int[n];
        for (int i = 0; i < n; i++) nums[i] = in.nextInt();
        System.out.println(new Solution().subarraySum(nums, k));
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
3 2
1 1 1
out:
2
-->
<!-- test
in:
3 3
1 2 3
out:
2
-->
<!-- test
in:
4 0
1 -1 1 -1
out:
4
-->
<!-- test
in:
1 5
5
out:
1
-->
<!-- test
in:
3 0
0 0 0
out:
6
-->

### Example 5 — Longest Consecutive Sequence · Medium

- **Source:** [LC 128 · Longest Consecutive Sequence](https://leetcode.com/problems/longest-consecutive-sequence/) — Medium · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** given up to $10^5$ unsorted integers (duplicates allowed), return the length of the longest run of consecutive values $v, v+1, \dots$ that all appear. Required: $O(n)$.
- **Thinking from first principles:** sorting gives $O(n \log n)$ and is the honest first answer. To get $O(n)$, put everything in a hash set. A run is determined by its smallest element $v$, characterised by "$v - 1$ is absent". Start counting **only** from such $v$. Every element is then visited by at most one counting walk, so the total work is $O(n)$.

<details><summary>Solution</summary>

Amortised argument: each value $x$ in the set is touched once as a candidate start and at most once inside the `while` walk of the unique run containing it. That is $\le 2|S|$ set lookups in total. Iterate over the **set**, not the input: with many duplicates of a run's start, iterating the input repeats the same walk and degrades to $O(n^2)$. Time $O(n)$ expected, space $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int longestConsecutive(vector<int>& nums) {
        unordered_set<int> s(nums.begin(), nums.end());
        int best = 0;
        for (int x : s) {
            if (s.count(x - 1)) continue;          // not the start of a run
            int len = 1;
            while (s.count(x + len)) ++len;
            best = max(best, len);
        }
        return best;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> nums(n);
    for (int& x : nums) cin >> x;
    cout << Solution().longestConsecutive(nums) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int longestConsecutive(int[] nums) {
        Set<Integer> s = new HashSet<>();
        for (int x : nums) s.add(x);
        int best = 0;
        for (int x : s) {
            if (s.contains(x - 1)) continue;
            int len = 1;
            while (s.contains(x + len)) len++;
            best = Math.max(best, len);
        }
        return best;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] nums = new int[n];
        for (int i = 0; i < n; i++) nums[i] = in.nextInt();
        System.out.println(new Solution().longestConsecutive(nums));
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
6
100 4 200 1 3 2
out:
4
-->
<!-- test
in:
10
0 3 7 2 5 8 4 6 0 1
out:
9
-->
<!-- test
in:
0
out:
0
-->
<!-- test
in:
5
-1000000000 1000000000 7 7 7
out:
1
-->

## 6. Pitfalls and things to remember

1. **Insert after lookup** in one-pass pair problems. Inserting first lets an element pair with itself (Two Sum with `target = 2·a[i]`) or counts empty subarrays (Subarray Sum with $k = 0$).
2. **Seed the prefix map** with `0 → 1` (counting) or `0 → -1` (longest length). Forgetting it misses every subarray that starts at index 0.
3. **Count vs first index vs last index.** Counting problems store counts. "Longest" stores the *first* index of each prefix (`putIfAbsent` / `emplace`). "Shortest" stores the *latest* index.
4. **Negative numbers kill sliding windows** but not prefix sums. Say this out loud when choosing the approach, because interviewers check that you know why.
5. **Overflow:** prefix sums of $10^5$ values up to $10^9$ need 64-bit (`long long` / `long`). Products overflow even faster. LC 238 promises 32-bit prefixes, but most problems do not.
6. **Java boxing:** `Map<Integer, Integer>` boxes every key. `==` between two `Integer` objects compares references (it works only for −128..127 by caching), so use `.equals` or unbox. `getOrDefault` and `merge` keep code short.
7. **Java `Arrays.sort(int[])`** is a dual-pivot quicksort. On older JDKs it can be driven to $O(n^2)$ by crafted input (Codeforces anti-quicksort tests). It is fine on LeetCode. In CP, shuffle first or sort an `Integer[]` (TimSort). `Arrays.sort(char[])` for anagram keys is safe in practice.
8. **C++ `unordered_map` iteration order is unspecified.** Never let printed output depend on it (sort first, as the drivers above do). `reserve()` avoids rehashing when the size is known.
9. **`map[key]` in C++ inserts a default value.** Use `find`/`count` for pure lookups, or a loop over a map can grow it while you read.
10. **String keys cost $O(L)$ to hash.** A "hash map of strings" is $O(nL)$, not $O(n)$. State that in the complexity.
11. **Mutable keys:** never mutate an object (e.g. a `List` in Java) after using it as a hash key, because its bucket no longer matches.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| "The array is sorted — can you use less memory?" | two pointers from both ends, $O(1)$ space ([file 03](03-two-pointers-and-sliding-window.md)) |
| "Return *all* pairs / count pairs with duplicates" | value → count map; for each $x$ add `cnt[T - x]` before inserting $x$ |
| "Data does not fit in memory" | partition by `hash(x) mod M` into $M$ files so complementary values land in matching buckets, then solve each bucket in memory; or external sort + merge |
| "Streaming input, many queries" (Two Sum III) | trade-off: `add` $O(1)$ with `find` $O(n)$ over a count map, or `add` $O(n)$ precomputing all sums with `find` $O(1)$; pick by the read/write ratio |
| "Group Anagrams with Unicode / long strings" | count-map key (sorted `(char, count)` pairs) instead of a 26-array; complexity $O(nL)$ |
| "Subarray sum equals k, all values positive" | sliding window, $O(1)$ extra space |
| "Subarray sum divisible by k" | prefix residues; normalise negatives with `((p % k) + k) % k` |
| "2D version: count submatrices with sum k" | fix a pair of rows ($O(R^2)$), compress columns into a 1D array, run the 1D prefix-count: $O(R^2 C)$ |
| "Product except self without the output array trick" | prefix and suffix arrays, $O(n)$ extra; then show the $O(1)$ version |
| "Longest consecutive in $O(1)$ extra space" | sort in place, $O(n \log n)$; say that $O(n)$ time needs the hash set |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (sources and legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` Grind 75 core (implies Grind 169) · `G169` Grind 169 beyond the core 75 · `B75` Blind 75 (author's LeetCode list) · `NC150` NeetCode 150 (implies NeetCode 250) · `NC250` NeetCode 250 beyond the 150 · `TI150` LeetCode Top Interview 150. 🔒 = LeetCode Premium.

**Easy** (13)

- [ ] [LC 1 · Two Sum](https://leetcode.com/problems/two-sum/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 14 · Longest Common Prefix](https://leetcode.com/problems/longest-common-prefix/) — Easy · `G169` `NC250` `TI150`
- [ ] [LC 28 · Find the Index of the First Occurrence in a String](https://leetcode.com/problems/find-the-index-of-the-first-occurrence-in-a-string/) — Easy · `TI150`
- [ ] [LC 58 · Length of Last Word](https://leetcode.com/problems/length-of-last-word/) — Easy · `TI150`
- [ ] [LC 169 · Majority Element](https://leetcode.com/problems/majority-element/) — Easy · `G75` `NC250` `TI150`
- [ ] [LC 205 · Isomorphic Strings](https://leetcode.com/problems/isomorphic-strings/) — Easy · `TI150`
- [ ] [LC 217 · Contains Duplicate](https://leetcode.com/problems/contains-duplicate/) — Easy · `G75` `B75` `NC150`
- [ ] [LC 242 · Valid Anagram](https://leetcode.com/problems/valid-anagram/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 290 · Word Pattern](https://leetcode.com/problems/word-pattern/) — Easy · `TI150`
- [ ] [LC 383 · Ransom Note](https://leetcode.com/problems/ransom-note/) — Easy · `G75` `TI150`
- [ ] [LC 409 · Longest Palindrome](https://leetcode.com/problems/longest-palindrome/) — Easy · `G75`
- [ ] [LC 953 · Verifying an Alien Dictionary](https://leetcode.com/problems/verifying-an-alien-dictionary/) — Easy · `NC250`
- [ ] [LC 1929 · Concatenation of Array](https://leetcode.com/problems/concatenation-of-array/) — Easy · `NC250`

**Medium** (15)

- [ ] [LC 6 · Zigzag Conversion](https://leetcode.com/problems/zigzag-conversion/) — Medium · `TI150`
- [ ] [LC 8 · String to Integer (atoi)](https://leetcode.com/problems/string-to-integer-atoi/) — Medium · `G75`
- [ ] [LC 31 · Next Permutation](https://leetcode.com/problems/next-permutation/) — Medium · `G169`
- [ ] [LC 36 · Valid Sudoku](https://leetcode.com/problems/valid-sudoku/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 49 · Group Anagrams](https://leetcode.com/problems/group-anagrams/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 128 · Longest Consecutive Sequence](https://leetcode.com/problems/longest-consecutive-sequence/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 151 · Reverse Words in a String](https://leetcode.com/problems/reverse-words-in-a-string/) — Medium · `TI150`
- [ ] [LC 229 · Majority Element II](https://leetcode.com/problems/majority-element-ii/) — Medium · `NC250`
- [ ] [LC 238 · Product of Array Except Self](https://leetcode.com/problems/product-of-array-except-self/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 271 · Encode and Decode Strings](https://leetcode.com/problems/encode-and-decode-strings/) — Medium 🔒 · `G169` `B75` `NC150`
- [ ] [LC 274 · H-Index](https://leetcode.com/problems/h-index/) — Medium · `TI150`
- [ ] [LC 304 · Range Sum Query 2D - Immutable](https://leetcode.com/problems/range-sum-query-2d-immutable/) — Medium · `NC250`
- [ ] [LC 525 · Contiguous Array](https://leetcode.com/problems/contiguous-array/) — Medium · `G169`
- [ ] [LC 560 · Subarray Sum Equals K](https://leetcode.com/problems/subarray-sum-equals-k/) — Medium · `G169` `NC250`
- [ ] [LC 912 · Sort an Array](https://leetcode.com/problems/sort-an-array/) — Medium · `NC250`

**Hard** (3)

- [ ] [LC 41 · First Missing Positive](https://leetcode.com/problems/first-missing-positive/) — Hard · `G169` `NC250`
- [ ] [LC 68 · Text Justification](https://leetcode.com/problems/text-justification/) — Hard · `TI150`
- [ ] [LC 336 · Palindrome Pairs](https://leetcode.com/problems/palindrome-pairs/) — Hard · `G169`

**Beyond the lists** (same pattern, not in any fetched list; good for depth):

- [ ] [LC 303 · Range Sum Query - Immutable](https://leetcode.com/problems/range-sum-query-immutable/) — Easy — 1D prefix sums
- [ ] [LC 523 · Continuous Subarray Sum](https://leetcode.com/problems/continuous-subarray-sum/) — Medium — prefix residues, first-index map
- [ ] [LC 974 · Subarray Sums Divisible by K](https://leetcode.com/problems/subarray-sums-divisible-by-k/) — Medium — residue counting, negative modulo
- [ ] [LC 930 · Binary Subarrays With Sum](https://leetcode.com/problems/binary-subarrays-with-sum/) — Medium — prefix counts (or "at most k" windows)
- [ ] [LC 1248 · Count Number of Nice Subarrays](https://leetcode.com/problems/count-number-of-nice-subarrays/) — Medium — map odd → 1, even → 0
- [ ] [LC 454 · 4Sum II](https://leetcode.com/problems/4sum-ii/) — Medium — meet in the middle with a hash map
- [ ] [LC 1109 · Corporate Flight Bookings](https://leetcode.com/problems/corporate-flight-bookings/) — Medium — difference array
- [ ] [LC 1074 · Number of Submatrices That Sum to Target](https://leetcode.com/problems/number-of-submatrices-that-sum-to-target/) — Hard — row pairs + 1D prefix counts

## 9. CP counterpart

- [Prefix sums and difference arrays](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md): the same identities, plus 2D difference arrays, prefix XOR and contribution counting at Codeforces scale.
- [C++ STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md): hash-map internals and costs.
- [Randomised algorithms and hashing](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md): why CP code needs a custom hash, and set hashing tricks.
- [String hashing](../11-Strings/01-string-hashing.md): turns "compare substrings" into $O(1)$ hash comparisons, which helps on interview string questions too (Repeated DNA Sequences, Longest Duplicate Substring).

What transfers: the prefix-pair rewrite, used constantly in CP. What doesn't: in interviews you name variables (`prefix`, `count`), never use global arrays or `#define`, and you discuss expected vs worst-case hashing instead of pasting a splitmix64 hash.

## 10. Self-check

1. Why must Two Sum insert the current element *after* the lookup?
2. Subarray Sum Equals K: what breaks if you forget `count[0] = 1`? What if you insert before looking up?
3. Why does the sliding window fail for Subarray Sum Equals K, and for which input class does it work?
4. Prove that Longest Consecutive Sequence is $O(n)$. What input makes the "iterate over `nums`" version quadratic?
5. Give a canonical key for "strings equal up to a rotation" (`abcd` ~ `cdab`).
6. Write the 2D prefix-sum query formula from memory and explain each term.
7. For "longest subarray with sum $k$", which index do you store per prefix value, and why?
8. What is the worst case of a Java `HashMap` lookup since Java 8, and why is it not $O(n)$ for `Integer` keys?

<details><summary>Answers</summary>

1. Otherwise $a_i$ can match itself when $a_i = T/2$, returning the same index twice.
2. Without the seed, subarrays starting at index 0 are never counted. Inserting first adds the empty subarray $(j, j]$ whenever $k = 0$.
3. With negatives, extending the window can decrease the sum, so "shrink when too big" is not a valid rule. It works when all values are positive (non-negative needs care with zeros).
4. Each set element starts at most one walk (only run starts do) and is walked over at most once (it belongs to one run), so $\le 2n$ lookups. With input `[1,1,1,...,1,2,3,...,m]` the start `1` is processed once per copy, giving $O(n \cdot m)$.
5. The lexicographically smallest rotation (Booth's algorithm, or $O(L^2)$ by trying all rotations), or a rotation-invariant hash.
6. $P[r_2+1][c_2+1] - P[r_1][c_2+1] - P[r_2+1][c_1] + P[r_1][c_1]$: the big rectangle, minus the strip above, minus the strip to the left, plus the top-left corner that was subtracted twice.
7. The first index. For a fixed right end $j$, the longest subarray uses the smallest $i$ with $P_i = P_j - k$.
8. $O(\log n)$: a bucket with 8 or more entries (in a table of at least 64 buckets) becomes a red-black tree ordered by `compareTo` for `Comparable` keys, and `Integer` is `Comparable`.

</details>
