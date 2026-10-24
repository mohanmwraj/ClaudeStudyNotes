# Stacks and Monotonic Stacks

> **Band:** 🟢 1200 – 🔵 1700 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [arrays and hashing](02-arrays-hashing-and-prefix-sums.md), [two pointers and sliding window](03-two-pointers-and-sliding-window.md)
> **You can say you know this when:** you can derive "next greater element" in $O(n)$ with the amortised argument, handle ties (strict vs non-strict) deliberately, and parse a nested expression with an explicit stack instead of recursion.

A stack is the right structure whenever the most recent unfinished thing must be resolved first: matching brackets, nested expressions, undo, DFS. A **monotonic stack** is the same structure used as a *candidate filter*. It keeps only the elements that can still be the answer for some future query, and that keeps the total work linear.

## 1. First principles — why this works

### 1.1 Last-in, first-out matches nesting

In `{ [ ( ) ] }` the bracket that must close next is always the most recently opened one that is still open. That is exactly LIFO order. A string is balanced if and only if scanning left to right, every closer matches the stack top, and the stack is empty at the end. The same shape appears in expression evaluation (an open parenthesis suspends the current partial result), path simplification (`..` undoes the most recent directory), and iterative DFS.

### 1.2 Monotonic stack: candidates that can never win are discarded

"For every $i$, find the nearest $j > i$ with $a_j > a_i$" is $O(n^2)$ by scanning forward from each $i$. The waste: the scans from different $i$ re-read the same elements. Turn it around. Scan **left to right** and keep the indices whose answer is still unknown. When a new element $a_r$ is greater than $a_t$ for the index $t$ on top of the stack, $r$ *is* the answer for $t$. If some index $u$ between $t$ and $r$ had $a_u > a_t$, then $u$ would already have popped $t$ when it was processed (everything above $t$ on the stack is no larger than $a_t$, so $u$ pops down to $t$). Since $t$ is still on the stack, every element between them is $\le a_t$, and $a_r$ is the first greater one. Pop $t$, record the answer, and repeat with the new top. What stays on the stack is a sequence of non-increasing values, each one still waiting for something bigger, which is why the stack is called monotonic.

**Amortised cost:** each index is pushed once and popped at most once, so the total work is $O(n)$ even though one step may pop many elements.

### 1.3 Boundaries give "largest rectangle" and contribution counts

If $\text{left}_i$ is the index of the previous strictly smaller element and $\text{right}_i$ the next smaller one, then $a_i$ is the minimum of every subarray $(l, r)$ with $\text{left}_i < l \le i \le r < \text{right}_i$. That window has width $\text{right}_i - \text{left}_i - 1$ (the largest rectangle with height $a_i$). It is the minimum of exactly $(i - \text{left}_i)(\text{right}_i - i)$ subarrays (the contribution technique). With equal values you must break ties: strict on one side, non-strict on the other, or equal subarrays are counted twice.

### 1.4 Monotonic deque: a window that also expires

For "maximum of each window of size $k$", candidates leave for two reasons: a newer, larger element dominates them (pop from the **back**), or they fall out of the window (pop from the **front**). A deque supports both in $O(1)$. The front is always the window maximum, because the values decrease from front to back.

## 2. Definitions, invariants and complexities

| Structure | Invariant | Answer read at | Cost |
|---|---|---|---|
| bracket stack | stack = currently open brackets, in order | closer must match `top` | $O(n)$ |
| next greater (L→R) | stack values non-increasing from bottom to top | when an index is popped, its answer is the current $r$ | $O(n)$ amortised |
| previous smaller (L→R) | stack values strictly increasing | after popping, `top` is the previous smaller | $O(n)$ |
| histogram | increasing stack; popped bar's rectangle spans $(\text{newTop}, r)$ | at pop time | $O(n)$ |
| window max deque | indices increasing, values decreasing front → back | front | $O(n)$ |
| expression stack | saved (partial result, sign) per open paren | at `)` | $O(n)$ |

Contribution identity for sum of subarray minimums:
$$\sum_{\text{subarrays}} \min = \sum_i a_i \,(i - \text{left}_i)\,(\text{right}_i - i),$$
with $\text{left}$ = previous **strictly** smaller and $\text{right}$ = next smaller **or equal** (one strict side, one non-strict side).

## 3. Reusable templates (C++ and Java)

Next greater element (index of the first strictly greater element to the right, or $n$), and previous smaller (index of the last strictly smaller element to the left, or $-1$):

```cpp
vector<int> nextGreater(const vector<int>& a) {
    int n = a.size();
    vector<int> res(n, n);
    vector<int> st;                                   // indices whose answer is unknown
    for (int r = 0; r < n; ++r) {
        while (!st.empty() && a[st.back()] < a[r]) {  // r is the first greater element for st.back()
            res[st.back()] = r;
            st.pop_back();
        }
        st.push_back(r);
    }
    return res;
}

vector<int> previousSmaller(const vector<int>& a) {
    int n = a.size();
    vector<int> res(n, -1), st;
    for (int i = 0; i < n; ++i) {
        while (!st.empty() && a[st.back()] >= a[i]) st.pop_back();   // >= : keep only strictly smaller
        if (!st.empty()) res[i] = st.back();
        st.push_back(i);
    }
    return res;
}
```

```java
static int[] nextGreater(int[] a) {
    int n = a.length;
    int[] res = new int[n];
    Arrays.fill(res, n);
    int[] st = new int[n];
    int top = 0;                                      // array-backed stack: faster than ArrayDeque<Integer>
    for (int r = 0; r < n; r++) {
        while (top > 0 && a[st[top - 1]] < a[r]) res[st[--top]] = r;
        st[top++] = r;
    }
    return res;
}

static int[] previousSmaller(int[] a) {
    int n = a.length;
    int[] res = new int[n], st = new int[n];
    int top = 0;
    for (int i = 0; i < n; i++) {
        while (top > 0 && a[st[top - 1]] >= a[i]) top--;
        res[i] = top > 0 ? st[top - 1] : -1;
        st[top++] = i;
    }
    return res;
}
```

Sum of subarray minimums by contribution (modulo $10^9 + 7$, as in [LC 907 · Sum of Subarray Minimums](https://leetcode.com/problems/sum-of-subarray-minimums/) — Medium), with the tie-breaking rule from §2:

```cpp
long long sumSubarrayMins(const vector<int>& a) {
    const long long MOD = 1'000'000'007;
    int n = a.size();
    vector<int> left(n), right(n), st;
    for (int i = 0; i < n; ++i) {                     // previous strictly smaller
        while (!st.empty() && a[st.back()] >= a[i]) st.pop_back();
        left[i] = st.empty() ? -1 : st.back();
        st.push_back(i);
    }
    st.clear();
    for (int i = n - 1; i >= 0; --i) {                // next smaller-or-equal
        while (!st.empty() && a[st.back()] > a[i]) st.pop_back();
        right[i] = st.empty() ? n : st.back();
        st.push_back(i);
    }
    long long total = 0;
    for (int i = 0; i < n; ++i)
        total = (total + 1LL * a[i] * (i - left[i]) % MOD * (right[i] - i)) % MOD;
    return total;
}
```

```java
static long sumSubarrayMins(int[] a) {
    final long MOD = 1_000_000_007L;
    int n = a.length;
    int[] left = new int[n], right = new int[n], st = new int[n];
    int top = 0;
    for (int i = 0; i < n; i++) {
        while (top > 0 && a[st[top - 1]] >= a[i]) top--;
        left[i] = top > 0 ? st[top - 1] : -1;
        st[top++] = i;
    }
    top = 0;
    for (int i = n - 1; i >= 0; i--) {
        while (top > 0 && a[st[top - 1]] > a[i]) top--;
        right[i] = top > 0 ? st[top - 1] : n;
        st[top++] = i;
    }
    long total = 0;
    for (int i = 0; i < n; i++) total = (total + (long) a[i] * (i - left[i]) % MOD * (right[i] - i)) % MOD;
    return total;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| brackets, "valid", "balanced", nested tags | stack of open symbols |
| "evaluate", "calculator", "decode `3[a2[c]]`" | stack of suspended partial results (or recursion on the nesting) |
| "next / previous greater / smaller", "how many days until warmer", "span" | monotonic stack |
| "largest rectangle", "maximal area under bars", "visible people" | boundaries from a monotonic stack |
| "sum over all subarrays of min / max / range" | contribution with prev/next smaller, careful ties |
| "max / min of every window of size $k$" | monotonic deque |
| "remove $k$ digits to get the smallest number", "smallest subsequence" | greedy with a monotonic stack (pop while a smaller one can replace the top) |
| collisions that resolve against the latest survivor (asteroids, car fleets) | stack of survivors |
| "implement queue with stacks" | two stacks, amortised $O(1)$ |

## 5. Worked examples

### Example 1 — Valid Parentheses · Easy

- **Source:** [LC 20 · Valid Parentheses](https://leetcode.com/problems/valid-parentheses/) — Easy · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Easy (≈ 900 CF, est.)
- **Problem:** a string of `()[]{}` ($|s| \le 10^4$). Is every bracket closed by the same type in the correct order?
- **Thinking from first principles:** counting each type separately fails on `([)]`, where the counts are fine but the nesting is crossed. The right check is LIFO: every closer must match the most recent unmatched opener. Push openers; on a closer, the stack must be non-empty and its top must be the matching opener. At the end the stack must be empty.

<details><summary>Solution</summary>

Time $O(n)$, space $O(n)$. Early exit: an odd length can never be valid.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    bool isValid(string s) {
        if (s.size() % 2) return false;
        string st;                                    // a string works as a char stack
        for (char c : s) {
            if (c == '(' || c == '[' || c == '{') { st.push_back(c); continue; }
            char want = c == ')' ? '(' : c == ']' ? '[' : '{';
            if (st.empty() || st.back() != want) return false;
            st.pop_back();
        }
        return st.empty();
    }
};

int main() {
    string s;
    cin >> s;
    cout << (Solution().isValid(s) ? "true" : "false") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public boolean isValid(String s) {
        if (s.length() % 2 == 1) return false;
        Deque<Character> st = new ArrayDeque<>();
        for (char c : s.toCharArray()) {
            if (c == '(' || c == '[' || c == '{') { st.push(c); continue; }
            char want = c == ')' ? '(' : c == ']' ? '[' : '{';
            if (st.isEmpty() || st.pop() != want) return false;
        }
        return st.isEmpty();
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        String s = br.readLine().trim();
        System.out.println(new Solution().isValid(s));
    }
}
```

</details>

<!-- test
in:
()[]{}
out:
true
-->
<!-- test
in:
([)]
out:
false
-->
<!-- test
in:
{[]}
out:
true
-->
<!-- test
in:
(((
out:
false
-->
<!-- test
in:
])
out:
false
-->

### Example 2 — Daily Temperatures · Medium

- **Source:** [LC 739 · Daily Temperatures](https://leetcode.com/problems/daily-temperatures/) — Medium · `G169` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** for each day, how many days until a **strictly** warmer day (0 if none)? $n \le 10^5$, temperatures in $[30, 100]$.
- **Thinking from first principles:** this is next-greater-element with the answer reported as a distance. Brute force scans forward from each day: $O(n^2)$ on a decreasing sequence. Keep the days still waiting for a warmer one on a stack. A new day $r$ resolves every waiting day colder than it, and those are exactly the ones on top, because the stack is non-increasing. (The small value range also allows an $O(71 n)$ "next occurrence of each temperature" scan from the right, which is a nice remark but not needed.)

<details><summary>Solution</summary>

Pop while `T[top] < T[r]`, so equal temperatures stay and wait (strictly warmer is required). Each day is pushed and popped at most once: $O(n)$ time, $O(n)$ space.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<int> dailyTemperatures(vector<int>& temperatures) {
        int n = temperatures.size();
        vector<int> ans(n, 0), st;                    // st: days still waiting for a warmer day
        for (int r = 0; r < n; ++r) {
            while (!st.empty() && temperatures[st.back()] < temperatures[r]) {
                ans[st.back()] = r - st.back();
                st.pop_back();
            }
            st.push_back(r);
        }
        return ans;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> t(n);
    for (int& x : t) cin >> x;
    vector<int> ans = Solution().dailyTemperatures(t);
    for (int i = 0; i < n; ++i) cout << ans[i] << (i + 1 < n ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int[] dailyTemperatures(int[] temperatures) {
        int n = temperatures.length;
        int[] ans = new int[n], st = new int[n];
        int top = 0;
        for (int r = 0; r < n; r++) {
            while (top > 0 && temperatures[st[top - 1]] < temperatures[r]) {
                int d = st[--top];
                ans[d] = r - d;
            }
            st[top++] = r;
        }
        return ans;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] t = new int[n];
        for (int i = 0; i < n; i++) t[i] = in.nextInt();
        int[] ans = new Solution().dailyTemperatures(t);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.append(ans[i]).append(i + 1 < n ? ' ' : '\n');
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
8
73 74 75 71 69 72 76 73
out:
1 1 4 2 1 1 0 0
-->
<!-- test
in:
4
30 40 50 60
out:
1 1 1 0
-->
<!-- test
in:
1
50
out:
0
-->
<!-- test
in:
3
50 50 50
out:
0 0 0
-->

### Example 3 — Largest Rectangle in Histogram · Hard

- **Source:** [LC 84 · Largest Rectangle in Histogram](https://leetcode.com/problems/largest-rectangle-in-histogram/) — Hard · `G75` `NC150`
- **Difficulty:** LeetCode Hard (≈ 1800 CF, est.)
- **Problem:** bars of width 1 and heights $h_i$ ($n \le 10^5$, $h_i \le 10^4$). Find the largest rectangle inside the histogram.
- **Thinking from first principles:** the best rectangle has the height of some bar $i$ (otherwise it could be raised). With height $h_i$ it extends left and right until the first strictly lower bar. So the answer is $\max_i h_i \cdot (\text{right}_i - \text{left}_i - 1)$ with previous/next smaller indices. Two monotonic passes compute those boundaries. They can be fused into one pass: when bar $j$ is popped by a lower bar $r$, its right boundary is $r$ and its left boundary is the new stack top.

<details><summary>Solution</summary>

Keep a stack of indices with increasing heights, and treat position $n$ as a sentinel bar of height 0 so every bar is popped at the end. Bar $j$ is popped by the first $r$ with $h_r \le h_j$, and its rectangle spans from the new stack top (exclusive) to $r$ (exclusive): width $= r - \text{top} - 1$, or $r$ if the stack is empty. Popping on `>=` instead of `>` is safe with equal heights: the earlier of two equal bars gets a rectangle that is too narrow, but the later one extends over both and records the correct width. Time $O(n)$, space $O(n)$. The area is at most $10^5 \cdot 10^4 = 10^9$, which fits in a 32-bit `int`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int largestRectangleArea(vector<int>& heights) {
        int n = heights.size(), best = 0;
        vector<int> st;                                       // increasing heights
        for (int r = 0; r <= n; ++r) {
            int h = (r == n) ? 0 : heights[r];                // sentinel flushes the stack
            while (!st.empty() && heights[st.back()] >= h) {
                int height = heights[st.back()];
                st.pop_back();
                int leftBound = st.empty() ? -1 : st.back();  // previous smaller bar
                best = max(best, height * (r - leftBound - 1));
            }
            st.push_back(r);
        }
        return best;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> h(n);
    for (int& x : h) cin >> x;
    cout << Solution().largestRectangleArea(h) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int largestRectangleArea(int[] heights) {
        int n = heights.length, best = 0, top = 0;
        int[] st = new int[n + 1];
        for (int r = 0; r <= n; r++) {
            int h = r == n ? 0 : heights[r];
            while (top > 0 && heights[st[top - 1]] >= h) {
                int height = heights[st[--top]];
                int leftBound = top > 0 ? st[top - 1] : -1;
                best = Math.max(best, height * (r - leftBound - 1));
            }
            st[top++] = r;
        }
        return best;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] h = new int[n];
        for (int i = 0; i < n; i++) h[i] = in.nextInt();
        System.out.println(new Solution().largestRectangleArea(h));
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
2 1 5 6 2 3
out:
10
-->
<!-- test
in:
2
2 4
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
<!-- test
in:
5
3 3 3 3 3
out:
15
-->
<!-- test
in:
5
5 4 3 2 1
out:
9
-->

### Example 4 — Basic Calculator · Hard

- **Source:** [LC 224 · Basic Calculator](https://leetcode.com/problems/basic-calculator/) — Hard · `G75` `TI150`
- **Difficulty:** LeetCode Hard (≈ 1700 CF, est.)
- **Problem:** evaluate an expression with non-negative integers, `+`, `-`, parentheses and spaces ($|s| \le 3 \cdot 10^5$). `-` may be unary (`-(2+3)`, `1-(-2)`). `eval` is not allowed.
- **Thinking from first principles:** without parentheses, the value is a running sum $\sum \pm \text{number}$: keep `result`, the `sign` of the next number, and the digits being read. A parenthesis starts an independent sub-expression whose value is later combined as `outerResult + outerSign * inner`. So on `(` save `(result, sign)` and restart, and on `)` finish the inner value and combine it with what was saved. Unary minus needs no special case: `-(` just sets `sign = -1` before the parenthesis, and a leading `-` is `0 - …`.

<details><summary>Solution</summary>

The stack depth equals the nesting depth. Each character is processed once: $O(n)$ time, $O(\text{depth})$ space. Intermediate values use 64-bit to be safe, and the final answer fits in 32 bits per the problem. The recursive-descent alternative is shorter for `+ - * /` with precedence (Basic Calculator III), but its recursion depth equals the nesting depth.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int calculate(string s) {
        long long result = 0, number = 0;
        int sign = 1;
        vector<pair<long long, int>> st;                  // (result outside the paren, sign before it)
        for (char c : s) {
            if (c >= '0' && c <= '9') {
                number = number * 10 + (c - '0');
            } else if (c == '+' || c == '-') {
                result += sign * number;
                number = 0;
                sign = (c == '+') ? 1 : -1;
            } else if (c == '(') {
                st.push_back({result, sign});
                result = 0;
                sign = 1;
            } else if (c == ')') {
                result += sign * number;
                number = 0;
                auto [outer, outerSign] = st.back();
                st.pop_back();
                result = outer + outerSign * result;
            }                                             // spaces are ignored
        }
        return (int)(result + sign * number);
    }
};

int main() {
    string s;
    getline(cin, s);
    cout << Solution().calculate(s) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int calculate(String s) {
        long result = 0, number = 0;
        int sign = 1;
        Deque<long[]> st = new ArrayDeque<>();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c >= '0' && c <= '9') {
                number = number * 10 + (c - '0');
            } else if (c == '+' || c == '-') {
                result += sign * number;
                number = 0;
                sign = c == '+' ? 1 : -1;
            } else if (c == '(') {
                st.push(new long[]{result, sign});
                result = 0;
                sign = 1;
            } else if (c == ')') {
                result += sign * number;
                number = 0;
                long[] outer = st.pop();
                result = outer[0] + outer[1] * result;
            }
        }
        return (int) (result + sign * number);
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        System.out.println(new Solution().calculate(br.readLine()));
    }
}
```

</details>

<!-- test
in:
1 + 1
out:
2
-->
<!-- test
in:
(1+(4+5+2)-3)+(6+8)
out:
23
-->
<!-- test
in:
- (3 + (4 + 5))
out:
-12
-->
<!-- test
in:
1-(     -2)
out:
3
-->
<!-- test
in:
2147483647
out:
2147483647
-->

### Example 5 — Sliding Window Maximum · Hard

- **Source:** [LC 239 · Sliding Window Maximum](https://leetcode.com/problems/sliding-window-maximum/) — Hard · `G169` `NC150`
- **Difficulty:** LeetCode Hard (≈ 1700 CF, est.)
- **Problem:** array of $n \le 10^5$ integers and window size $k$. Output the maximum of each of the $n - k + 1$ windows.
- **Thinking from first principles:** recomputing each window is $O(nk)$. A max-heap with lazy deletion gives $O(n \log n)$ and is a fine first answer. For $O(n)$: an element $a_i$ can never be a future window maximum once a later element $a_j \ge a_i$ has arrived, because $a_j$ stays in the window at least as long as $a_i$. So keep a deque of indices with strictly decreasing values. Drop dominated elements from the back, drop expired ones from the front, and read the maximum at the front.

<details><summary>Solution</summary>

Invariant: the deque holds, in index order, exactly the window elements not dominated by a later element, so their values are decreasing and the front is the maximum. Each index enters and leaves once: $O(n)$ time, $O(k)$ space.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<int> maxSlidingWindow(vector<int>& nums, int k) {
        deque<int> dq;                                    // indices, values decreasing
        vector<int> res;
        for (int i = 0; i < (int)nums.size(); ++i) {
            while (!dq.empty() && nums[dq.back()] <= nums[i]) dq.pop_back();   // dominated forever
            dq.push_back(i);
            if (dq.front() <= i - k) dq.pop_front();      // expired
            if (i >= k - 1) res.push_back(nums[dq.front()]);
        }
        return res;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, k;
    cin >> n >> k;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    vector<int> res = Solution().maxSlidingWindow(a, k);
    for (size_t i = 0; i < res.size(); ++i) cout << res[i] << (i + 1 < res.size() ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int[] maxSlidingWindow(int[] nums, int k) {
        int n = nums.length;
        int[] dq = new int[n], res = new int[n - k + 1];
        int head = 0, tail = 0;                           // array deque of indices: dq[head..tail-1]
        for (int i = 0; i < n; i++) {
            while (tail > head && nums[dq[tail - 1]] <= nums[i]) tail--;
            dq[tail++] = i;
            if (dq[head] <= i - k) head++;
            if (i >= k - 1) res[i - k + 1] = nums[dq[head]];
        }
        return res;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        int[] res = new Solution().maxSlidingWindow(a, k);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < res.length; i++) sb.append(res[i]).append(i + 1 < res.length ? ' ' : '\n');
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
8 3
1 3 -1 -3 5 3 6 7
out:
3 3 5 5 6 7
-->
<!-- test
in:
1 1
1
out:
1
-->
<!-- test
in:
5 2
4 4 4 4 4
out:
4 4 4 4
-->
<!-- test
in:
4 4
1 2 3 4
out:
4
-->

## 6. Pitfalls and things to remember

1. **Decide ties explicitly.** "Strictly greater" pops on `<`, "greater or equal" on `<=`. For contribution sums use one strict and one non-strict side, or equal elements are double counted.
2. **Store indices, not values.** You almost always need the distance or the boundary, and the value is one lookup away.
3. **Sentinels** (height 0 at the end, or $-\infty$ at the bottom) remove the "flush the stack after the loop" code and its bugs.
4. **Empty-stack checks** before `top()`/`back()`. In C++ calling `back()` on an empty vector is undefined behaviour, not an exception.
5. **Java `Stack` is legacy** (synchronised, extends `Vector`). Use `ArrayDeque` (`push`/`pop`/`peek`) or a plain `int[]` with a top index. The latter avoids boxing and is several times faster.
6. **`ArrayDeque` rejects `null`.** `Deque<Character>` comparisons with `!=` against a `char` unbox safely, but two `Character` objects compared with `!=` compare references.
7. **Calculator parsing:** multi-digit numbers (`number = number*10 + d`), spaces, unary minus, and finishing the last number after the loop are the four classic misses.
8. **Window deque:** pop expired indices with `dq.front() <= i - k`, checked after pushing. Forgetting expiry gives the global prefix maximum.
9. **Recursion for nested structures** (decode string, calculators) is fine in interviews if you state the depth. For $10^5$ nesting levels prefer the explicit stack.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| Valid Parentheses → "only `(` and `)`?" | a counter suffices: never negative, zero at the end |
| → "minimum removals to make it valid" | counter for unmatched `)`, plus what remains open at the end ([LC 1249 · Minimum Remove to Make Valid Parentheses](https://leetcode.com/problems/minimum-remove-to-make-valid-parentheses/) — Medium) |
| Daily Temperatures → "circular array" | iterate $2n$ indices modulo $n$ ([LC 503 · Next Greater Element II](https://leetcode.com/problems/next-greater-element-ii/) — Medium) |
| → "values arrive as a stream, answer each query online" | the "previous greater" direction works online (stock span); "next greater" needs the future, so answers are emitted late |
| Histogram → "binary matrix, largest rectangle of 1s" | per row build heights of consecutive 1s and run the histogram: $O(RC)$ ([LC 85 · Maximal Rectangle](https://leetcode.com/problems/maximal-rectangle/) — Hard) |
| Calculator → "add `*` and `/` with precedence" | keep the last term separate (`last`), apply `*`/`/` to it immediately, add it at `+`/`-`; or two stacks (shunting-yard) |
| Sliding max → "median of each window" | two heaps with lazy deletion, or an order-statistics tree: $O(n \log k)$ |
| "Min stack in O(1)" | see [design problems](17-design-problems.md): store `(value, min so far)` pairs |
| "Queue using two stacks — complexity?" | amortised $O(1)$: each element moves from the in-stack to the out-stack once |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium. Min Stack and Maximum Frequency Stack are listed under [design problems](17-design-problems.md).

**Easy** (4)

- [ ] [LC 20 · Valid Parentheses](https://leetcode.com/problems/valid-parentheses/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 225 · Implement Stack using Queues](https://leetcode.com/problems/implement-stack-using-queues/) — Easy · `NC250`
- [ ] [LC 232 · Implement Queue using Stacks](https://leetcode.com/problems/implement-queue-using-stacks/) — Easy · `G75` `NC250`
- [ ] [LC 682 · Baseball Game](https://leetcode.com/problems/baseball-game/) — Easy · `NC250`

**Medium** (8)

- [ ] [LC 71 · Simplify Path](https://leetcode.com/problems/simplify-path/) — Medium · `NC250` `TI150`
- [ ] [LC 150 · Evaluate Reverse Polish Notation](https://leetcode.com/problems/evaluate-reverse-polish-notation/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 227 · Basic Calculator II](https://leetcode.com/problems/basic-calculator-ii/) — Medium · `G169`
- [ ] [LC 394 · Decode String](https://leetcode.com/problems/decode-string/) — Medium · `G169` `NC250`
- [ ] [LC 735 · Asteroid Collision](https://leetcode.com/problems/asteroid-collision/) — Medium · `G169` `NC250`
- [ ] [LC 739 · Daily Temperatures](https://leetcode.com/problems/daily-temperatures/) — Medium · `G169` `NC150`
- [ ] [LC 853 · Car Fleet](https://leetcode.com/problems/car-fleet/) — Medium · `NC150`
- [ ] [LC 901 · Online Stock Span](https://leetcode.com/problems/online-stock-span/) — Medium · `NC250`

**Hard** (4)

- [ ] [LC 32 · Longest Valid Parentheses](https://leetcode.com/problems/longest-valid-parentheses/) — Hard · `G169`
- [ ] [LC 84 · Largest Rectangle in Histogram](https://leetcode.com/problems/largest-rectangle-in-histogram/) — Hard · `G75` `NC150`
- [ ] [LC 224 · Basic Calculator](https://leetcode.com/problems/basic-calculator/) — Hard · `G75` `TI150`
- [ ] [LC 239 · Sliding Window Maximum](https://leetcode.com/problems/sliding-window-maximum/) — Hard · `G169` `NC150`

**Beyond the lists:**

- [ ] [LC 496 · Next Greater Element I](https://leetcode.com/problems/next-greater-element-i/) — Easy — the base template plus a map
- [ ] [LC 503 · Next Greater Element II](https://leetcode.com/problems/next-greater-element-ii/) — Medium — circular: two passes
- [ ] [LC 907 · Sum of Subarray Minimums](https://leetcode.com/problems/sum-of-subarray-minimums/) — Medium — contribution with tie-breaking
- [ ] [LC 2104 · Sum of Subarray Ranges](https://leetcode.com/problems/sum-of-subarray-ranges/) — Medium — sum of maxima minus sum of minima
- [ ] [LC 402 · Remove K Digits](https://leetcode.com/problems/remove-k-digits/) — Medium — greedy monotonic stack
- [ ] [LC 316 · Remove Duplicate Letters](https://leetcode.com/problems/remove-duplicate-letters/) — Medium — greedy stack with "seen" and "last occurrence"
- [ ] [LC 456 · 132 Pattern](https://leetcode.com/problems/132-pattern/) — Medium — scan right to left with a decreasing stack
- [ ] [LC 1856 · Maximum Subarray Min-Product](https://leetcode.com/problems/maximum-subarray-min-product/) — Medium — boundaries + prefix sums
- [ ] [LC 85 · Maximal Rectangle](https://leetcode.com/problems/maximal-rectangle/) — Hard — histogram per row
- [ ] [LC 862 · Shortest Subarray with Sum at Least K](https://leetcode.com/problems/shortest-subarray-with-sum-at-least-k/) — Hard — monotonic deque over prefix sums (negatives allowed)

## 9. CP counterpart

- [Monotonic stack and deque (CP)](../02-Core-Techniques/04-monotonic-stack-and-deque.md): the same structures, plus "all nearest smaller values", Cartesian trees and deque-optimised DP.
- [Prefix-sum and monotonic-queue DP optimisation](../07-DP-Optimizations/01-prefix-sum-and-monotonic-queue-optimization.md): the window-max deque used inside $dp_i = \max_{i-k \le j < i} dp_j + c_i$.
- [Contribution technique](../05-Combinatorics-and-Probability/07-contribution-technique.md): sum-over-subarrays identities like the one in §2.

Transfers: all of it. Interview-specific: name the stacks (`open`, `waiting`), prefer `ArrayDeque`/`vector`, and say the amortised argument in one sentence.

## 10. Self-check

1. Prove that next-greater-element with a stack is $O(n)$.
2. What does the monotonic stack contain after processing $a_0..a_r$ for "next greater"?
3. In the histogram, when bar $j$ is popped by $r$, why is the new stack top its left boundary?
4. Which side is strict and which non-strict in the subarray-minimum contribution formula, and what goes wrong otherwise?
5. Why does the window-max deque pop from the back with `<=` and from the front by index?
6. In Basic Calculator, what exactly is saved on `(`, and how is it combined on `)`?
7. How do you get amortised $O(1)$ for a queue built from two stacks?

<details><summary>Answers</summary>

1. Every index is pushed exactly once and popped at most once, so the total number of stack operations is at most $2n$, no matter how many pops a single step performs.
2. The indices $\le r$ whose next greater element has not yet appeared, in increasing index order with non-increasing values.
3. The stack is increasing, so the element below $j$ is the nearest earlier index with a smaller (or equal, then handled by a later bar) height. Everything between it and $j$ was popped by $j$ or earlier elements and is taller, so the rectangle of height $h_j$ spans exactly $(\text{top}, r)$.
4. Previous strictly smaller and next smaller-or-equal (or the mirror). With both strict, a subarray whose minimum value appears twice is counted for both copies. With both non-strict, it is counted for neither.
5. Back: a newer element at least as large dominates the older one for every future window. Front: the oldest index leaves the window first, which is a property of indices, not values.
6. The result accumulated outside the parenthesis and the sign in front of it. On `)`: `result = savedResult + savedSign * innerResult`.
7. Push to `in`. On pop/peek, if `out` is empty, move everything from `in` to `out` (reversing the order). Each element is moved once, so $n$ operations cost $O(n)$ in total.

</details>
