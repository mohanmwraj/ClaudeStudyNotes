# Two Pointers and Sliding Window

> **Band:** 🟢 1200–1600 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [arrays and hashing](02-arrays-hashing-and-prefix-sums.md), [sorting and comparators](../01-Foundations/05-sorting-and-comparators.md)
> **You can say you know this when:** you can state the monotonicity property that makes a two-pointer scan correct *before* coding it, and write the "longest valid window" and "shortest valid window" templates without off-by-one errors.

Two pointers is about **discarding candidates in bulk**. Both pointers only move forward (or toward each other), so the total work is $O(n)$ even though the search space has $O(n^2)$ pairs or windows. Every correct use rests on a monotonicity argument, and stating it is what separates a confident interview answer from a lucky one.

## 1. First principles — why this works

### 1.1 Opposite ends on a sorted array

Search a sorted array for $a_l + a_r = T$. The candidate set is all pairs $l < r$. Start at $l = 0, r = n-1$:

- if $a_l + a_r < T$, then **every** pair $(l, r')$ with $r' \le r$ also has sum $< T$, since $a_{r'} \le a_r$. So $l$ can be discarded entirely: `l++`.
- if $a_l + a_r > T$, every pair $(l', r)$ with $l' \ge l$ is too big: `r--`.

Each step removes a whole row or column of the pair matrix, so the scan is $O(n)$ and can never skip the answer. This exchange-style argument (also used for Container With Most Water and Trapping Rain Water) is the proof you say out loud.

### 1.2 Same-direction windows

For a subarray question, let $f(l, r)$ be a property of the window $a_l..a_r$. A sliding window works when the property is **monotone in the window**:

- *valid windows are closed under shrinking* (if $[l, r]$ is valid then so is every $[l', r']$ inside it), e.g. "at most $k$ distinct", "no repeated character", "sum $\le S$ with non-negative numbers". Then, for each $r$, the set of valid left ends is an interval $[L(r), r]$, and $L(r)$ never decreases as $r$ grows. One pointer chases the other, which gives the **longest valid window**.
- *valid windows are closed under growing* (e.g. "contains all of $t$", "sum $\ge S$ with non-negative numbers"). For each $r$ the *smallest* valid window ending at $r$ starts at a left end that also never decreases, which gives the **shortest valid window**.

If the property is not monotone, as with "sum exactly $k$" with negative numbers, the window is wrong. Use prefix sums instead ([file 02](02-arrays-hashing-and-prefix-sums.md)).

### 1.3 Counting windows

When valid windows are closed under shrinking, the number of valid subarrays ending at $r$ is $r - L(r) + 1$, so $\sum_r (r - L(r) + 1)$ counts all of them in $O(n)$. "Exactly $k$" properties that are not monotone become monotone through
$$\text{exactly}(k) = \text{atMost}(k) - \text{atMost}(k-1).$$

### 1.4 Read/write pointers

In-place filtering (remove duplicates, move zeroes, remove element) uses a *write* pointer $w$ and a *read* pointer $r$. Invariant: $a_0..a_{w-1}$ is the answer for the prefix $a_0..a_{r-1}$. Each read either appends to the answer (`a[w++] = a[r]`) or skips. The invariant gives correctness, and $r$ moves $n$ times.

## 2. Definitions, invariants and complexities

| Technique | Invariant | Time | Space |
|---|---|---|---|
| opposite ends | the answer pair (if any) lies in $[l, r]$ | $O(n)$ after an $O(n \log n)$ sort | $O(1)$ |
| k-Sum | fix $k-2$ elements, two-pointer the rest | $O(n^{k-1})$ | $O(1)$ extra |
| longest valid window | $[l, r]$ is valid, $l = L(r)$ | $O(n)$ amortised: each index enters and leaves once | $O(\sigma)$ counts |
| shortest valid window | shrink while still valid | $O(n)$ | $O(\sigma)$ |
| count valid windows | add $r - l + 1$ per $r$ | $O(n)$ | $O(\sigma)$ |
| exactly $k$ | $\text{atMost}(k) - \text{atMost}(k-1)$ | $2 \times O(n)$ | |
| fixed size $w$ | add $a_r$, remove $a_{r-w}$ | $O(n)$ | |
| Dutch national flag | $[0,lo)$ = 0s, $[lo, mid)$ = 1s, $(hi, n)$ = 2s | $O(n)$, one pass | $O(1)$ |
| fast/slow pointers | see [linked lists](06-linked-lists.md) | $O(n)$ | $O(1)$ |

## 3. Reusable templates (C++ and Java)

Opposite ends, shown on Container With Most Water ([LC 11 · Container With Most Water](https://leetcode.com/problems/container-with-most-water/) — Medium). Area $= (r - l) \cdot \min(h_l, h_r)$. Moving the **taller** side inward can only shrink the width without raising the minimum, so it can never help. Move the shorter side.

```cpp
int maxArea(const vector<int>& h) {
    int l = 0, r = (int)h.size() - 1, best = 0;
    while (l < r) {
        best = max(best, (r - l) * min(h[l], h[r]));
        if (h[l] < h[r]) ++l; else --r;     // the shorter wall limits every narrower container that keeps it
    }
    return best;
}
```

```java
static int maxArea(int[] h) {
    int l = 0, r = h.length - 1, best = 0;
    while (l < r) {
        best = Math.max(best, (r - l) * Math.min(h[l], h[r]));
        if (h[l] < h[r]) l++; else r--;
    }
    return best;
}
```

Variable window: **longest** window satisfying a shrink-closed property, and **shortest** window satisfying a grow-closed property. Shown here for "at most $k$ distinct values" and "sum $\ge S$" with positive numbers.

```cpp
int longestAtMostKDistinct(const vector<int>& a, int k) {
    unordered_map<int, int> cnt;
    int best = 0;
    for (int l = 0, r = 0; r < (int)a.size(); ++r) {
        cnt[a[r]]++;
        while ((int)cnt.size() > k) {             // restore validity by shrinking from the left
            if (--cnt[a[l]] == 0) cnt.erase(a[l]);
            ++l;
        }
        best = max(best, r - l + 1);              // [l, r] is the longest valid window ending at r
    }
    return best;
}

int shortestWithSumAtLeast(const vector<int>& a, long long S) {   // all a[i] > 0
    long long sum = 0;
    int best = INT_MAX;
    for (int l = 0, r = 0; r < (int)a.size(); ++r) {
        sum += a[r];
        while (sum >= S) {                        // valid: record, then try a shorter one
            best = min(best, r - l + 1);
            sum -= a[l++];
        }
    }
    return best == INT_MAX ? 0 : best;
}
```

```java
static int longestAtMostKDistinct(int[] a, int k) {
    Map<Integer, Integer> cnt = new HashMap<>();
    int best = 0;
    for (int l = 0, r = 0; r < a.length; r++) {
        cnt.merge(a[r], 1, Integer::sum);
        while (cnt.size() > k) {
            if (cnt.merge(a[l], -1, Integer::sum) == 0) cnt.remove(a[l]);
            l++;
        }
        best = Math.max(best, r - l + 1);
    }
    return best;
}

static int shortestWithSumAtLeast(int[] a, long s) {
    long sum = 0;
    int best = Integer.MAX_VALUE;
    for (int l = 0, r = 0; r < a.length; r++) {
        sum += a[r];
        while (sum >= s) {
            best = Math.min(best, r - l + 1);
            sum -= a[l++];
        }
    }
    return best == Integer.MAX_VALUE ? 0 : best;
}
```

Read/write pointers (remove duplicates from a sorted array, keep at most `keep` copies; `keep = 1` is LC 26, `keep = 2` is LC 80):

```cpp
int removeDuplicatesKeep(vector<int>& a, int keep) {
    int w = 0;
    for (int x : a)
        if (w < keep || a[w - keep] != x) a[w++] = x;   // x is not the (keep+1)-th copy
    return w;
}
```

```java
static int removeDuplicatesKeep(int[] a, int keep) {
    int w = 0;
    for (int x : a)
        if (w < keep || a[w - keep] != x) a[w++] = x;
    return w;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| sorted array (or "you may sort"), pair/triple with a target sum | opposite ends; k-Sum = sort + fix + two pointers |
| "in place", "O(1) extra space", "remove / move / partition" | read/write pointers; Dutch flag for 3 classes |
| "longest / maximum length substring/subarray such that …" with a shrink-closed condition | longest-window template |
| "minimum length / smallest window that contains / reaches …" | shortest-window template |
| "number of subarrays with at most / exactly k …" | count windows; exactly = atMost(k) − atMost(k−1) |
| "every window of size k" | fixed window (or monotonic deque for max/min, [file 04](04-stacks-and-monotonic-stacks.md)) |
| "anagram / permutation of t inside s" | fixed window of length $|t|$ with a 26-count difference |
| subarray sum with negatives | **not** a window, use prefix sums |
| water between bars, container | opposite ends with the "smaller side moves" argument |

## 5. Worked examples

### Example 1 — 3Sum · Medium

- **Source:** [LC 15 · 3Sum](https://leetcode.com/problems/3sum/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** given $3 \le n \le 3000$ integers in $[-10^5, 10^5]$, return all **distinct** value-triplets $\{a, b, c\}$ from different positions with $a + b + c = 0$.
- **Thinking from first principles:** brute force is $O(n^3)$ plus deduplication. Fixing the smallest element $a_i$ leaves "find pairs summing to $-a_i$ in the rest", which is the opposite-ends scan on a sorted suffix: $O(n)$ per $i$, $O(n^2)$ total. Duplicates are handled by the sorted order: skip an $a_i$ equal to the previous one (it would produce the same triplets), and after recording a triplet skip equal values of $a_l$. A hash-set-of-triplets also works but costs memory and hides the reasoning.

<details><summary>Solution</summary>

Sort, then for each first index run the two-pointer scan. Early exit: if $a_i > 0$ all three are positive. Time $O(n^2)$, extra space $O(1)$ beyond the output (plus the sort). The driver prints the number of triplets and then each one, in sorted order.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<vector<int>> threeSum(vector<int>& nums) {
        sort(nums.begin(), nums.end());
        vector<vector<int>> res;
        int n = nums.size();
        for (int i = 0; i + 2 < n; ++i) {
            if (nums[i] > 0) break;                        // smallest element positive: no more zeros
            if (i > 0 && nums[i] == nums[i - 1]) continue; // same first value -> same triplets
            int l = i + 1, r = n - 1;
            while (l < r) {
                int s = nums[i] + nums[l] + nums[r];
                if (s < 0) ++l;
                else if (s > 0) --r;
                else {
                    res.push_back({nums[i], nums[l], nums[r]});
                    ++l; --r;
                    while (l < r && nums[l] == nums[l - 1]) ++l;   // skip duplicate second values
                }
            }
        }
        return res;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> nums(n);
    for (int& x : nums) cin >> x;
    auto res = Solution().threeSum(nums);
    sort(res.begin(), res.end());
    cout << res.size() << '\n';
    for (auto& t : res) cout << t[0] << ' ' << t[1] << ' ' << t[2] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public List<List<Integer>> threeSum(int[] nums) {
        Arrays.sort(nums);
        List<List<Integer>> res = new ArrayList<>();
        int n = nums.length;
        for (int i = 0; i + 2 < n; i++) {
            if (nums[i] > 0) break;
            if (i > 0 && nums[i] == nums[i - 1]) continue;
            int l = i + 1, r = n - 1;
            while (l < r) {
                int s = nums[i] + nums[l] + nums[r];
                if (s < 0) l++;
                else if (s > 0) r--;
                else {
                    res.add(List.of(nums[i], nums[l], nums[r]));
                    l++; r--;
                    while (l < r && nums[l] == nums[l - 1]) l++;
                }
            }
        }
        return res;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] nums = new int[n];
        for (int i = 0; i < n; i++) nums[i] = in.nextInt();
        List<List<Integer>> res = new ArrayList<>(new Solution().threeSum(nums));
        res.sort((x, y) -> {
            for (int i = 0; i < 3; i++) if (!x.get(i).equals(y.get(i))) return Integer.compare(x.get(i), y.get(i));
            return 0;
        });
        StringBuilder sb = new StringBuilder().append(res.size()).append('\n');
        for (List<Integer> t : res) sb.append(t.get(0)).append(' ').append(t.get(1)).append(' ').append(t.get(2)).append('\n');
        System.out.print(sb);
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
-1 0 1 2 -1 -4
out:
2
-1 -1 2
-1 0 1
-->
<!-- test
in:
3
0 1 1
out:
0
-->
<!-- test
in:
5
0 0 0 0 0
out:
1
0 0 0
-->
<!-- test
in:
8
-2 0 1 1 2 -1 -4 2
out:
4
-4 2 2
-2 0 2
-2 1 1
-1 0 1
-->

### Example 2 — Trapping Rain Water · Hard

- **Source:** [LC 42 · Trapping Rain Water](https://leetcode.com/problems/trapping-rain-water/) — Hard · `G75` `NC150` `TI150`
- **Difficulty:** LeetCode Hard (≈ 1600 CF, est.)
- **Problem:** bars of non-negative heights $h_0..h_{n-1}$ ($n \le 2 \cdot 10^4$) and width 1. How much water is trapped after rain?
- **Thinking from first principles:** water above bar $i$ is $\min(\text{maxLeft}_i, \text{maxRight}_i) - h_i$, where both maxima include $i$. Computing the two arrays gives $O(n)$ time and $O(n)$ space. To drop the arrays, note that we only need the **smaller** of the two maxima. Keep pointers at both ends. If $h_l < h_r$, the true right maximum for $l$ is at least $h_r > h_l$, and every bar we already passed on the left was smaller than some bar still to the right. So $\text{leftMax}$ is the binding side for $l$ and the water at $l$ is $\text{leftMax} - h_l$. The other case is symmetric.

<details><summary>Solution</summary>

Proof of the key step: when the left pointer moved past index $j$, it was because $h_j < h_{r'}$ for the right pointer $r'$ of that moment, and $r' \ge$ the current $r \ge l$. So every bar contributing to $\text{leftMax}$ is dominated by some bar in $[l, n)$, and $h_l < h_r$ as well. Hence $\text{leftMax} \le \text{maxRight}_l$, and $\min(\text{maxLeft}_l, \text{maxRight}_l) = \text{leftMax}$. Time $O(n)$, space $O(1)$. A monotonic stack solution (fill layer by layer) is the other standard answer, see [file 04](04-stacks-and-monotonic-stacks.md).

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int trap(vector<int>& height) {
        int l = 0, r = (int)height.size() - 1, leftMax = 0, rightMax = 0, water = 0;
        while (l < r) {
            if (height[l] < height[r]) {                // the left side is the binding one
                leftMax = max(leftMax, height[l]);
                water += leftMax - height[l++];
            } else {
                rightMax = max(rightMax, height[r]);
                water += rightMax - height[r--];
            }
        }
        return water;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> h(n);
    for (int& x : h) cin >> x;
    cout << Solution().trap(h) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int trap(int[] height) {
        int l = 0, r = height.length - 1, leftMax = 0, rightMax = 0, water = 0;
        while (l < r) {
            if (height[l] < height[r]) {
                leftMax = Math.max(leftMax, height[l]);
                water += leftMax - height[l++];
            } else {
                rightMax = Math.max(rightMax, height[r]);
                water += rightMax - height[r--];
            }
        }
        return water;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] h = new int[n];
        for (int i = 0; i < n; i++) h[i] = in.nextInt();
        System.out.println(new Solution().trap(h));
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
12
0 1 0 2 1 0 1 3 2 1 2 1
out:
6
-->
<!-- test
in:
6
4 2 0 3 2 5
out:
9
-->
<!-- test
in:
1
5
out:
0
-->
<!-- test
in:
5
3 3 3 3 3
out:
0
-->

### Example 3 — Longest Substring Without Repeating Characters · Medium

- **Source:** [LC 3 · Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** length of the longest substring with all characters distinct. $|s| \le 5 \cdot 10^4$, ASCII characters including spaces.
- **Thinking from first principles:** "all distinct" is closed under shrinking, so the longest-window template applies. Instead of shrinking one step at a time with a count array, remember the **last index** of every character. When $s_r$ was last seen at $p \ge l$, the left end must jump to $p + 1$, since any window containing both copies is invalid. $l$ never moves backwards, which is why `max` with the old $l$ matters (the check `last[c] >= left` does the same thing).

<details><summary>Solution</summary>

Each index is visited once, so the time is $O(n)$ and the space $O(\sigma)$ with $\sigma = 256$. The driver reads the whole line, so spaces count as characters and an empty line is the empty string.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int lengthOfLongestSubstring(string s) {
        array<int, 256> last;
        last.fill(-1);                                  // last index where each byte was seen
        int best = 0, left = 0;
        for (int right = 0; right < (int)s.size(); ++right) {
            unsigned char c = s[right];                 // unsigned: chars > 127 must not index negatively
            if (last[c] >= left) left = last[c] + 1;    // jump past the previous copy
            last[c] = right;
            best = max(best, right - left + 1);
        }
        return best;
    }
};

int main() {
    string s;
    getline(cin, s);
    if (!s.empty() && s.back() == '\r') s.pop_back();
    cout << Solution().lengthOfLongestSubstring(s) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int lengthOfLongestSubstring(String s) {
        int[] last = new int[256];
        Arrays.fill(last, -1);
        int best = 0, left = 0;
        for (int right = 0; right < s.length(); right++) {
            int c = s.charAt(right) & 0xFF;
            if (last[c] >= left) left = last[c] + 1;
            last[c] = right;
            best = Math.max(best, right - left + 1);
        }
        return best;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        String s = br.readLine();
        if (s == null) s = "";
        System.out.println(new Solution().lengthOfLongestSubstring(s));
    }
}
```

</details>

<!-- test
in:
abcabcbb
out:
3
-->
<!-- test
in:
bbbbb
out:
1
-->
<!-- test
in:
pwwkew
out:
3
-->
<!-- test
in:
abba
out:
2
-->
<!-- test
in:
a b c
out:
3
-->

### Example 4 — Longest Repeating Character Replacement · Medium

- **Source:** [LC 424 · Longest Repeating Character Replacement](https://leetcode.com/problems/longest-repeating-character-replacement/) — Medium · `G169` `B75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1500 CF, est.)
- **Problem:** uppercase string $s$ ($|s| \le 10^5$) and $k$. You may change at most $k$ characters. Return the longest substring that can be made of one repeated letter.
- **Thinking from first principles:** a window can be made uniform if and only if $\text{len} - \text{maxFreq} \le k$: keep the most frequent letter and change the rest. This property is closed under shrinking, so the window applies. Recomputing `maxFreq` after each shrink costs $O(26)$, which is fine. The well-known trick goes further: **never decrease `maxFreq` and never shrink the window, only slide it.** We only care about windows longer than the best found so far, and such a window needs a letter frequency larger than any seen before. A stale (too large) `maxFreq` can only keep the window at its current best length, never inflate the answer.

<details><summary>Solution</summary>

The window length is non-decreasing and always equals the best answer so far. When `len - maxFreq > k`, slide it right by one (remove `s[left]`, `left++`) so its length stays the same. It grows only when a new character pushes `maxFreq` to a new record, which is exactly when a longer valid window ending at `right` exists. Time $O(n)$, space $O(26)$. The textbook version with `while` and a recomputed `maxFreq` is equally acceptable. Say which one you are writing.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int characterReplacement(string s, int k) {
        array<int, 26> cnt{};
        int left = 0, maxFreq = 0, best = 0;
        for (int right = 0; right < (int)s.size(); ++right) {
            maxFreq = max(maxFreq, ++cnt[s[right] - 'A']);
            if (right - left + 1 - maxFreq > k) {      // too many changes needed: slide, don't shrink
                --cnt[s[left] - 'A'];
                ++left;
            }
            best = max(best, right - left + 1);
        }
        return best;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string s;
    int k;
    cin >> s >> k;
    cout << Solution().characterReplacement(s, k) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int characterReplacement(String s, int k) {
        int[] cnt = new int[26];
        int left = 0, maxFreq = 0, best = 0;
        for (int right = 0; right < s.length(); right++) {
            maxFreq = Math.max(maxFreq, ++cnt[s.charAt(right) - 'A']);
            if (right - left + 1 - maxFreq > k) {
                cnt[s.charAt(left) - 'A']--;
                left++;
            }
            best = Math.max(best, right - left + 1);
        }
        return best;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        String s = in.next();
        int k = in.nextInt();
        System.out.println(new Solution().characterReplacement(s, k));
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
ABAB 2
out:
4
-->
<!-- test
in:
AABABBA 1
out:
4
-->
<!-- test
in:
A 0
out:
1
-->
<!-- test
in:
ABCDE 0
out:
1
-->
<!-- test
in:
ABBBCA 5
out:
6
-->

### Example 5 — Minimum Window Substring · Hard

- **Source:** [LC 76 · Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/) — Hard · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Hard (≈ 1700 CF, est.)
- **Problem:** strings $s, t$ (letters, $|s|, |t| \le 10^5$). Return the shortest substring of $s$ that contains every character of $t$ **with multiplicity**, or `""`. The answer is unique when it exists.
- **Thinking from first principles:** "contains all of $t$" is closed under growing, so use the shortest-window template: extend $r$ until the window covers $t$, then shrink $l$ while it still covers, recording the length. Checking coverage by comparing 52 counts each step gives $O(52n)$, which is fine. The cleaner $O(n)$ way keeps `need[c]` (how many more of $c$ we still need, negative for surplus) and a single integer `missing`, the total still needed. Coverage is then `missing == 0`.

<details><summary>Solution</summary>

`need[c]` starts as the count of $c$ in $t$. Adding $s_r$: if `need[s_r] > 0` before the decrement, this copy was useful and `missing--`. Removing $s_l$: increment `need[s_l]`, and if it becomes positive the window just lost a required copy, so `missing++`. Each index enters and leaves the window once: $O(|s| + |t|)$ time, $O(\sigma)$ space. Updating only on a strictly shorter length keeps the leftmost minimum.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    string minWindow(string s, string t) {
        array<int, 128> need{};
        for (char c : t) need[c]++;
        int missing = t.size();                       // copies of t's chars not yet in the window
        int left = 0, bestL = 0, bestLen = INT_MAX;
        for (int right = 0; right < (int)s.size(); ++right) {
            if (need[s[right]]-- > 0) --missing;      // this copy was still needed
            while (missing == 0) {                    // window covers t: record and shrink
                if (right - left + 1 < bestLen) { bestLen = right - left + 1; bestL = left; }
                if (++need[s[left]] > 0) ++missing;   // dropping s[left] breaks coverage
                ++left;
            }
        }
        return bestLen == INT_MAX ? "" : s.substr(bestL, bestLen);
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string s, t;
    cin >> s >> t;
    cout << '"' << Solution().minWindow(s, t) << '"' << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public String minWindow(String s, String t) {
        int[] need = new int[128];
        for (int i = 0; i < t.length(); i++) need[t.charAt(i)]++;
        int missing = t.length(), left = 0, bestL = 0, bestLen = Integer.MAX_VALUE;
        for (int right = 0; right < s.length(); right++) {
            if (need[s.charAt(right)]-- > 0) missing--;
            while (missing == 0) {
                if (right - left + 1 < bestLen) { bestLen = right - left + 1; bestL = left; }
                if (++need[s.charAt(left)] > 0) missing++;
                left++;
            }
        }
        return bestLen == Integer.MAX_VALUE ? "" : s.substring(bestL, bestL + bestLen);
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        String s = in.next(), t = in.next();
        System.out.println("\"" + new Solution().minWindow(s, t) + "\"");
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
}
```

</details>

<!-- test
in:
ADOBECODEBANC ABC
out:
"BANC"
-->
<!-- test
in:
a a
out:
"a"
-->
<!-- test
in:
a aa
out:
""
-->
<!-- test
in:
aaflslflsldkalskaaa aaa
out:
"aaa"
-->

## 6. Pitfalls and things to remember

1. **State the monotonicity.** If you cannot say "valid windows are closed under shrinking/growing", the window is probably wrong (classic trap: subarray sum $= k$ with negatives).
2. **`while`, not `if`, when shrinking** in the standard templates. One removal may not restore validity. The `if` in Example 4 is deliberate and needs its own argument.
3. **Window length is `r - l + 1`.** Count of valid subarrays ending at `r` is the same expression.
4. **Deduplicate in k-Sum by skipping equal neighbours** after sorting, both for the fixed element and after recording a match. Forgetting the inner skip outputs duplicates; skipping before recording loses answers like `[-1, -1, 2]`.
5. **Signed `char` indexes negative in C++** for bytes ≥ 128. Cast to `unsigned char`, or use `& 0xFF` in Java.
6. **Overflow in k-Sum targets:** 4Sum with values up to $10^9$ needs 64-bit sums (`1LL * a + b + c + d`).
7. **Count arrays vs maps:** `int[26]`/`int[128]` is faster and clearer than a map. Reach for a map only when the alphabet is large or unknown (integers).
8. **`map.size()` as "distinct count"** requires erasing keys whose count drops to 0. Forgetting the erase is the classic bug in "at most k distinct".
9. **Sorting destroys indices.** If the problem wants indices (Two Sum), sort pairs `(value, index)` or use a hash map instead.
10. **Java:** `List.of(...)` is immutable and rejects `null`. `Integer` comparisons with `==` fail outside −128..127.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| 3Sum → "4Sum / kSum?" | recursive kSum: fix one element, recurse to (k−1)Sum, base case two pointers; $O(n^{k-1})$ |
| 3Sum → "closest to target?" | same scan, track $\min |s - T|$; no dedup needed |
| "Return the count of triplets with sum < T" | sorted; when $a_i + a_l + a_r < T$, all $r - l$ pairs with this $l$ work: add $r - l$, `l++` |
| Trapping Rain Water → "2D height map?" | min-heap of boundary cells, flood inward (Dijkstra-like), $O(RC \log RC)$ ([LC 407 · Trapping Rain Water II](https://leetcode.com/problems/trapping-rain-water-ii/) — Hard) |
| Longest substring → "return the substring itself / Unicode input?" | store `bestL`; use a hash map keyed by code point |
| "At most k distinct" → "exactly k distinct, count subarrays" | atMost(k) − atMost(k−1) ([LC 992 · Subarrays with K Different Integers](https://leetcode.com/problems/subarrays-with-k-different-integers/) — Hard) |
| Min window → "t is a subsequence, not a multiset" | different problem: DP or two-pass greedy ([LC 727 · Minimum Window Subsequence](https://leetcode.com/problems/minimum-window-subsequence/) — Hard 🔒) |
| "The input is a stream; you cannot store it" | windows only need the window's contents. If the window is unbounded, discuss memory limits honestly |
| "Can it be done in one pass without sorting?" | for pair sums: hash map; for 3Sum no algorithm substantially faster than $O(n^2)$ is known (the 3SUM conjecture) |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend and sources in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium.

**Easy** (13)

- [ ] [LC 26 · Remove Duplicates from Sorted Array](https://leetcode.com/problems/remove-duplicates-from-sorted-array/) — Easy · `NC250` `TI150`
- [ ] [LC 27 · Remove Element](https://leetcode.com/problems/remove-element/) — Easy · `NC250` `TI150`
- [ ] [LC 88 · Merge Sorted Array](https://leetcode.com/problems/merge-sorted-array/) — Easy · `NC250` `TI150`
- [ ] [LC 121 · Best Time to Buy and Sell Stock](https://leetcode.com/problems/best-time-to-buy-and-sell-stock/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 125 · Valid Palindrome](https://leetcode.com/problems/valid-palindrome/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 219 · Contains Duplicate II](https://leetcode.com/problems/contains-duplicate-ii/) — Easy · `NC250` `TI150`
- [ ] [LC 283 · Move Zeroes](https://leetcode.com/problems/move-zeroes/) — Easy · `G169`
- [ ] [LC 344 · Reverse String](https://leetcode.com/problems/reverse-string/) — Easy · `NC250`
- [ ] [LC 392 · Is Subsequence](https://leetcode.com/problems/is-subsequence/) — Easy · `TI150`
- [ ] [LC 680 · Valid Palindrome II](https://leetcode.com/problems/valid-palindrome-ii/) — Easy · `NC250`
- [ ] [LC 844 · Backspace String Compare](https://leetcode.com/problems/backspace-string-compare/) — Easy · `G169`
- [ ] [LC 977 · Squares of a Sorted Array](https://leetcode.com/problems/squares-of-a-sorted-array/) — Easy · `G169`
- [ ] [LC 1768 · Merge Strings Alternately](https://leetcode.com/problems/merge-strings-alternately/) — Easy · `NC250`

**Medium** (14)

- [ ] [LC 3 · Longest Substring Without Repeating Characters](https://leetcode.com/problems/longest-substring-without-repeating-characters/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 11 · Container With Most Water](https://leetcode.com/problems/container-with-most-water/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 15 · 3Sum](https://leetcode.com/problems/3sum/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 16 · 3Sum Closest](https://leetcode.com/problems/3sum-closest/) — Medium · `G169`
- [ ] [LC 18 · 4Sum](https://leetcode.com/problems/4sum/) — Medium · `NC250`
- [ ] [LC 75 · Sort Colors](https://leetcode.com/problems/sort-colors/) — Medium · `G75` `NC250`
- [ ] [LC 80 · Remove Duplicates from Sorted Array II](https://leetcode.com/problems/remove-duplicates-from-sorted-array-ii/) — Medium · `TI150`
- [ ] [LC 167 · Two Sum II - Input Array Is Sorted](https://leetcode.com/problems/two-sum-ii-input-array-is-sorted/) — Medium · `NC150` `TI150`
- [ ] [LC 189 · Rotate Array](https://leetcode.com/problems/rotate-array/) — Medium · `G169` `NC250` `TI150`
- [ ] [LC 209 · Minimum Size Subarray Sum](https://leetcode.com/problems/minimum-size-subarray-sum/) — Medium · `NC250` `TI150`
- [ ] [LC 424 · Longest Repeating Character Replacement](https://leetcode.com/problems/longest-repeating-character-replacement/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 438 · Find All Anagrams in a String](https://leetcode.com/problems/find-all-anagrams-in-a-string/) — Medium · `G75`
- [ ] [LC 567 · Permutation in String](https://leetcode.com/problems/permutation-in-string/) — Medium · `NC150`
- [ ] [LC 881 · Boats to Save People](https://leetcode.com/problems/boats-to-save-people/) — Medium · `NC250`

**Hard** (3)

- [ ] [LC 30 · Substring with Concatenation of All Words](https://leetcode.com/problems/substring-with-concatenation-of-all-words/) — Hard · `TI150`
- [ ] [LC 42 · Trapping Rain Water](https://leetcode.com/problems/trapping-rain-water/) — Hard · `G75` `NC150` `TI150`
- [ ] [LC 76 · Minimum Window Substring](https://leetcode.com/problems/minimum-window-substring/) — Hard · `G75` `B75` `NC150` `TI150`

**Beyond the lists:**

- [ ] [LC 1004 · Max Consecutive Ones III](https://leetcode.com/problems/max-consecutive-ones-iii/) — Medium — window with at most $k$ zeros
- [ ] [LC 904 · Fruit Into Baskets](https://leetcode.com/problems/fruit-into-baskets/) — Medium — at most 2 distinct
- [ ] [LC 713 · Subarray Product Less Than K](https://leetcode.com/problems/subarray-product-less-than-k/) — Medium — count windows, add `r - l + 1`
- [ ] [LC 1423 · Maximum Points You Can Obtain from Cards](https://leetcode.com/problems/maximum-points-you-can-obtain-from-cards/) — Medium — complement: minimum window of size $n-k$
- [ ] [LC 1658 · Minimum Operations to Reduce X to Zero](https://leetcode.com/problems/minimum-operations-to-reduce-x-to-zero/) — Medium — complement: longest middle window with sum total − x
- [ ] [LC 1838 · Frequency of the Most Frequent Element](https://leetcode.com/problems/frequency-of-the-most-frequent-element/) — Medium — sort + window with a cost formula
- [ ] [LC 992 · Subarrays with K Different Integers](https://leetcode.com/problems/subarrays-with-k-different-integers/) — Hard — exactly = atMost(k) − atMost(k−1)
- [ ] [LC 2302 · Count Subarrays With Score Less Than K](https://leetcode.com/problems/count-subarrays-with-score-less-than-k/) — Hard — count windows with a product-like score

## 9. CP counterpart

- [Two pointers and sliding window (CP)](../02-Core-Techniques/03-two-pointers-and-sliding-window.md): the same monotonicity argument, applied to 1400–2000 rated problems, plus two pointers over two sorted sequences and over answers.
- [Monotonic stack and deque](../02-Core-Techniques/04-monotonic-stack-and-deque.md): window maximum/minimum in $O(n)$.
- [Prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md): the fallback when monotonicity fails.

Transfers directly: everything. The interview difference is narration. Say the invariant ("`[l, r]` is always the longest valid window ending at `r`") before typing, and trace a small example afterwards.

## 10. Self-check

1. Why may the opposite-ends scan discard the whole row of $l$ when $a_l + a_r < T$?
2. In Container With Most Water, why is it never useful to move the taller side?
3. What property must "valid window" have for the longest-window template? Give one property that lacks it.
4. How do you count subarrays with *exactly* $k$ distinct values using only "at most" windows?
5. In Example 4, why is it safe never to decrease `maxFreq`?
6. In Minimum Window Substring, what do negative values of `need[c]` mean?
7. 3Sum: where exactly do you skip duplicates, and what goes wrong if you skip before recording a match?
8. Which in-place invariant does `removeDuplicatesKeep` maintain?

<details><summary>Answers</summary>

1. For every $r' \le r$, $a_l + a_{r'} \le a_l + a_r < T$ because the array is sorted, so no pair using $l$ (with the right end still in range) can hit $T$.
2. Moving the taller side keeps the same shorter wall (or a shorter one) and reduces the width, so the area cannot increase. Only moving the shorter side can find a taller limiting wall.
3. Closed under shrinking (every sub-window of a valid window is valid). "Sum exactly $k$" with negative numbers lacks it.
4. $\text{exactly}(k) = \text{atMost}(k) - \text{atMost}(k-1)$, each computed by counting $r - l + 1$ per right end.
5. A stale, larger `maxFreq` only stops the window from sliding when it should. The window keeps its length, which equals the best answer already achieved, so the answer is never overstated. A longer window can only be accepted when a real frequency reaches a new maximum.
6. The window holds that many surplus copies of `c` beyond what $t$ needs. Removing them does not break coverage.
7. Skip equal first elements before starting a scan, and after recording a triplet skip equal `nums[l]` values. Skipping before recording would drop triplets that use two equal values, e.g. `-1 -1 2`.
8. `a[0..w-1]` holds the elements read so far with each value kept at most `keep` times, in sorted order.

</details>
