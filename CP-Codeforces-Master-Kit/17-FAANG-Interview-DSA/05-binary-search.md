# Binary Search

> **Band:** 🟢 1200 – 🔵 1800 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md), [arrays and hashing](02-arrays-hashing-and-prefix-sums.md)
> **You can say you know this when:** you can write a binary search that never loops forever and never misses by one, by first naming the **monotone predicate** and the **invariant** on `lo`/`hi`. You also recognise "binary search on the answer" from the constraints alone.

Binary search is not "look in the middle of a sorted array". It is: **find the boundary of a monotone predicate**. Sorted arrays, rotated arrays, first bad versions, minimum feasible speeds, and the median partition of two arrays are all the same algorithm once the predicate is written down.

## 1. First principles — why this works

### 1.1 One predicate, one boundary

Let $P(x)$ be a predicate on integers $x \in [L, R]$ that is **monotone**: false, false, …, false, true, …, true. The task "find the first $x$ with $P(x)$ true" can be solved by evaluating $P$ at the midpoint. If $P(\text{mid})$ is true, the answer is $\le \text{mid}$. If it is false, the answer is $> \text{mid}$. Each step halves the candidate interval, so $\lceil \log_2(R - L + 1) \rceil + 1$ evaluations suffice.

Examples of predicates:

| Problem | $P(x)$ | Answer |
|---|---|---|
| lower bound of $t$ in sorted $a$ | $a_x \ge t$ | first true |
| first bad version | `isBad(x)` | first true |
| min in rotated sorted array | $a_x \le a_{n-1}$ | first true |
| minimum feasible speed / capacity | "speed $x$ finishes within the limit" | first true |
| largest $x$ with $x^2 \le n$ | $x^2 > n$ | (first true) − 1 |

### 1.2 The invariant decides the code

Write the loop around an invariant and every off-by-one disappears. The half-open form used throughout this kit:

> the answer (first true) lies in $[lo, hi)$, with $hi$ possibly "one past the end" meaning "no true".

- `mid = lo + (hi - lo) / 2` satisfies $lo \le mid < hi$.
- `P(mid)` true → the answer is in $[lo, mid]$, so set `hi = mid` (mid stays a candidate).
- `P(mid)` false → the answer is in $[mid+1, hi)$, so set `lo = mid + 1`.
- The loop runs while `lo < hi` and ends with `lo == hi` = the answer.

Termination: the interval strictly shrinks because $mid < hi$ and $mid + 1 > lo$. Infinite loops come from `lo = mid` with a floor midpoint, which this form never uses.

### 1.3 Binary search on the answer

When a problem asks for the **minimum $x$ such that something is feasible**, and feasibility is monotone in $x$ (a faster speed or a bigger capacity never hurts), you do not need a formula for $x$. You only need a *checker* for a given $x$. Total cost: $O(\text{check} \cdot \log(\text{range}))$. Signals: "minimise the maximum", "maximise the minimum", "at least / at most $h$ hours", and an answer range up to $10^9$ or $10^{18}$ with $n \le 10^5$.

### 1.4 Rotated arrays: one half is always sorted

A rotated sorted array (distinct values) split at any `mid` has at least one sorted half. Compare `a[lo]` with `a[mid]`: if `a[lo] <= a[mid]`, the left half is sorted, otherwise the right half is. In the sorted half, checking whether the target lies inside it takes two comparisons. That decides which half to keep. With duplicates (`a[lo] == a[mid] == a[hi]`) you cannot tell, and the worst case degrades to $O(n)$. That limit is a well-known follow-up question.

## 2. Definitions, formulas and complexities

| Item | Formula / cost |
|---|---|
| Iterations on $N$ candidates | $\lceil \log_2 N \rceil$ (+1 for the last check); $10^9 \to 30$, $10^{18} \to 60$ |
| Safe midpoint | `lo + (hi - lo) / 2`; with negative bounds in C++ use `lo + (hi - lo) / 2` too (floor toward `lo` since `hi - lo >= 0`) |
| `lower_bound(t)` | first $i$ with $a_i \ge t$ |
| `upper_bound(t)` | first $i$ with $a_i > t$; count of $t$ = upper − lower |
| last $i$ with $a_i \le t$ | `upper_bound(t) - 1` |
| Ceiling division ($p, k > 0$) | $\lceil p/k \rceil = \lfloor (p + k - 1)/k \rfloor$ |
| Real-valued search | fixed 60–100 iterations, or stop when $hi - lo < \varepsilon$ |
| Answer search cost | $O(\log(\text{range}) \cdot T_{\text{check}})$ |
| Median partition | pick $i$ from $A$, $j = \lfloor (m+n+1)/2 \rfloor - i$ from $B$; valid iff $A_{i-1} \le B_j$ and $B_{j-1} \le A_i$ |

C++: `lower_bound`, `upper_bound`, `equal_range`, `partition_point(first, last, pred)` (first element where `pred` is false), and `std::set::lower_bound` (use the member function, not the free function, on sets). Java: `Arrays.binarySearch` returns *some* matching index or `-(insertionPoint) - 1`, with no guarantee of the first occurrence among duplicates. `TreeMap.floorKey/ceilingKey` cover ordered lookups.

## 3. Reusable templates (C++ and Java)

The single template behind everything in this file: first $x \in [lo, hi)$ with `pred(x)` true, or `hi` if none.

```cpp
// First x in [lo, hi) with pred(x) == true; returns hi if pred is false everywhere.
// pred must be monotone: false ... false true ... true.
long long firstTrue(long long lo, long long hi, const function<bool(long long)>& pred) {
    while (lo < hi) {
        long long mid = lo + (hi - lo) / 2;
        if (pred(mid)) hi = mid;      // mid is a candidate: keep it
        else lo = mid + 1;            // mid and everything left of it are false
    }
    return lo;
}

int lowerBound(const vector<int>& a, int t) {     // first i with a[i] >= t
    return (int)firstTrue(0, a.size(), [&](long long i) { return a[i] >= t; });
}

long long isqrtFloor(long long n) {               // largest x with x*x <= n, n >= 0
    long long firstTooBig = firstTrue(0, 3'000'000'001LL, [&](long long x) { return x * x > n; });
    return firstTooBig - 1;
}

double realSearch(double lo, double hi, const function<bool(double)>& pred) {
    for (int it = 0; it < 100; ++it) {            // 100 halvings: far below double precision
        double mid = (lo + hi) / 2;
        if (pred(mid)) hi = mid; else lo = mid;
    }
    return hi;
}
```

```java
static long firstTrue(long lo, long hi, LongPredicate pred) {
    while (lo < hi) {
        long mid = lo + (hi - lo) / 2;
        if (pred.test(mid)) hi = mid;
        else lo = mid + 1;
    }
    return lo;
}

static int lowerBound(int[] a, int t) {
    return (int) firstTrue(0, a.length, i -> a[(int) i] >= t);
}

static long isqrtFloor(long n) {
    return firstTrue(0, 3_000_000_001L, x -> x * x > n) - 1;
}

static double realSearch(double lo, double hi, DoublePredicate pred) {
    for (int it = 0; it < 100; it++) {
        double mid = (lo + hi) / 2;
        if (pred.test(mid)) hi = mid; else lo = mid;
    }
    return hi;
}
```

In an interview, inline the loop rather than passing a lambda. The template is for your head: **predicate, half-open interval, `hi = mid` / `lo = mid + 1`**.

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| sorted input, "find / insert position / first / last occurrence" | lower/upper bound |
| "$O(\log n)$ required" | binary search on index or value, whatever the data looks like |
| rotated sorted array, "pivot", "minimum" | compare with an endpoint; one half is sorted |
| "minimum speed / capacity / days / largest minimum distance such that …" | binary search on the answer + greedy checker |
| "minimise the maximum" / "maximise the minimum" | binary search on the answer (or a heap, if it is a running process) |
| matrix sorted by rows and columns | staircase walk $O(R + C)$, or search on the value with a counting checker |
| "k-th smallest" in an implicit sorted structure (pair distances, multiplication table) | search on the value $v$, count how many are $\le v$ |
| unimodal / mountain array, "peak" | compare $a_{mid}$ with $a_{mid+1}$ (the predicate is "descending from here") |
| timestamps, "value at time $t$" | per-key sorted list + upper bound ([time-based KV store](17-design-problems.md)) |
| median / k-th of two sorted arrays | partition search on the shorter array |

## 5. Worked examples

### Example 1 — Binary Search · Easy

- **Source:** [LC 704 · Binary Search](https://leetcode.com/problems/binary-search/) — Easy · `G75` `NC150`
- **Difficulty:** LeetCode Easy (≈ 800 CF, est.)
- **Problem:** sorted array of $n \le 10^4$ distinct integers and a target. Return its index or $-1$ in $O(\log n)$.
- **Thinking from first principles:** the closed-interval "three-way" search (`==` returns, else move left/right) works for distinct values. The lower-bound form is better to internalise because it also answers "first occurrence" and "insert position" without changes: find the first index with $a_i \ge t$, then check whether it holds $t$.

<details><summary>Solution</summary>

Invariant: the first index with `nums[i] >= target` lies in `[lo, hi)`. Time $O(\log n)$, space $O(1)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int search(vector<int>& nums, int target) {
        int lo = 0, hi = nums.size();                 // answer in [lo, hi)
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            if (nums[mid] >= target) hi = mid;        // mid could be the first >= target
            else lo = mid + 1;
        }
        return (lo < (int)nums.size() && nums[lo] == target) ? lo : -1;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, target;
    cin >> n >> target;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << Solution().search(a, target) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int search(int[] nums, int target) {
        int lo = 0, hi = nums.length;
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            if (nums[mid] >= target) hi = mid;
            else lo = mid + 1;
        }
        return lo < nums.length && nums[lo] == target ? lo : -1;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), target = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        System.out.println(new Solution().search(a, target));
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
6 9
-1 0 3 5 9 12
out:
4
-->
<!-- test
in:
6 2
-1 0 3 5 9 12
out:
-1
-->
<!-- test
in:
1 5
5
out:
0
-->
<!-- test
in:
3 100
1 2 3
out:
-1
-->

### Example 2 — Find Minimum in Rotated Sorted Array · Medium

- **Source:** [LC 153 · Find Minimum in Rotated Sorted Array](https://leetcode.com/problems/find-minimum-in-rotated-sorted-array/) — Medium · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** a sorted array of $n \le 5000$ **distinct** values, rotated an unknown number of times. Return the minimum in $O(\log n)$.
- **Thinking from first principles:** the array is two increasing runs, and every element of the second run (which starts at the minimum) is smaller than every element of the first. So $P(i) = (a_i \le a_{n-1})$ is false on the first run and true on the second, and the minimum is the first true. Comparing with $a_0$ instead fails on an unrotated array, where every element is $\ge a_0$. Comparing with the last element handles that case for free.

<details><summary>Solution</summary>

In the loop below, `nums[mid] > nums[hi]` means mid is in the first run (the min is strictly right). Otherwise mid is in the second run (the min is at mid or left). Comparing with the moving `hi` is equivalent to comparing with the last element, because `hi` always stays in the second run. Time $O(\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int findMin(vector<int>& nums) {
        int lo = 0, hi = (int)nums.size() - 1;        // min index in [lo, hi]
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            if (nums[mid] > nums[hi]) lo = mid + 1;   // mid in the first (larger) run
            else hi = mid;                            // mid in the run that starts at the min
        }
        return nums[lo];
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << Solution().findMin(a) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int findMin(int[] nums) {
        int lo = 0, hi = nums.length - 1;
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            if (nums[mid] > nums[hi]) lo = mid + 1;
            else hi = mid;
        }
        return nums[lo];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        System.out.println(new Solution().findMin(a));
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
5
3 4 5 1 2
out:
1
-->
<!-- test
in:
7
4 5 6 7 0 1 2
out:
0
-->
<!-- test
in:
4
11 13 15 17
out:
11
-->
<!-- test
in:
1
42
out:
42
-->
<!-- test
in:
2
2 1
out:
1
-->

### Example 3 — Search in Rotated Sorted Array · Medium

- **Source:** [LC 33 · Search in Rotated Sorted Array](https://leetcode.com/problems/search-in-rotated-sorted-array/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** distinct values, sorted then rotated; find the index of a target or $-1$ in $O(\log n)$.
- **Thinking from first principles:** two-step solution: find the rotation point with Example 2, then binary-search the correct run. That is clean and $O(\log n)$. The one-pass version uses §1.4: at every `mid`, one of `[lo, mid]` and `[mid, hi]` is sorted, and in a sorted range "is the target inside?" is just two comparisons. Keep the half that can contain the target.

<details><summary>Solution</summary>

Closed interval `[lo, hi]` here, because we return as soon as `nums[mid] == target`. `nums[lo] <= nums[mid]` (with `<=` for the case `lo == mid`) means the left half is sorted. Time $O(\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int search(vector<int>& nums, int target) {
        int lo = 0, hi = (int)nums.size() - 1;
        while (lo <= hi) {
            int mid = lo + (hi - lo) / 2;
            if (nums[mid] == target) return mid;
            if (nums[lo] <= nums[mid]) {                          // left half sorted
                if (nums[lo] <= target && target < nums[mid]) hi = mid - 1;
                else lo = mid + 1;
            } else {                                              // right half sorted
                if (nums[mid] < target && target <= nums[hi]) lo = mid + 1;
                else hi = mid - 1;
            }
        }
        return -1;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, target;
    cin >> n >> target;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << Solution().search(a, target) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int search(int[] nums, int target) {
        int lo = 0, hi = nums.length - 1;
        while (lo <= hi) {
            int mid = lo + (hi - lo) / 2;
            if (nums[mid] == target) return mid;
            if (nums[lo] <= nums[mid]) {
                if (nums[lo] <= target && target < nums[mid]) hi = mid - 1;
                else lo = mid + 1;
            } else {
                if (nums[mid] < target && target <= nums[hi]) lo = mid + 1;
                else hi = mid - 1;
            }
        }
        return -1;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), target = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        System.out.println(new Solution().search(a, target));
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
7 0
4 5 6 7 0 1 2
out:
4
-->
<!-- test
in:
7 3
4 5 6 7 0 1 2
out:
-1
-->
<!-- test
in:
1 0
1
out:
-1
-->
<!-- test
in:
2 1
3 1
out:
1
-->

### Example 4 — Koko Eating Bananas · Medium

- **Source:** [LC 875 · Koko Eating Bananas](https://leetcode.com/problems/koko-eating-bananas/) — Medium · `NC150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** $n \le 10^4$ piles with up to $10^9$ bananas each, and $h$ hours ($n \le h \le 10^9$). Each hour Koko eats up to $k$ bananas from one pile. Find the minimum integer speed $k$ that finishes within $h$ hours.
- **Thinking from first principles:** there is no direct formula for $k$, but for a *given* $k$ the time is easy: $\sum_i \lceil p_i / k \rceil$. That sum is non-increasing in $k$, so "finishes in time" is a monotone predicate on $k$, which is the binary-search-on-answer signal. Bounds: $k = 1$ is the smallest candidate, and $k = \max p_i$ always works because each pile then takes one hour and $h \ge n$. The time at $k = 1$ can reach $10^{13}$, so the sum needs 64-bit.

<details><summary>Solution</summary>

Search the first $k \in [1, \max p]$ with `hours(k) <= h`. Time $O(n \log \max p)$, about $30n$ operations. Space $O(1)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int minEatingSpeed(vector<int>& piles, int h) {
        auto hoursNeeded = [&](long long k) {
            long long hours = 0;
            for (int p : piles) hours += (p + k - 1) / k;    // ceil(p / k)
            return hours;
        };
        int lo = 1, hi = *max_element(piles.begin(), piles.end());
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            if (hoursNeeded(mid) <= h) hi = mid;             // feasible: answer is mid or smaller
            else lo = mid + 1;
        }
        return lo;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, h;
    cin >> n >> h;
    vector<int> piles(n);
    for (int& x : piles) cin >> x;
    cout << Solution().minEatingSpeed(piles, h) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int minEatingSpeed(int[] piles, int h) {
        int lo = 1, hi = 0;
        for (int p : piles) hi = Math.max(hi, p);
        while (lo < hi) {
            int mid = lo + (hi - lo) / 2;
            if (hoursNeeded(piles, mid) <= h) hi = mid;
            else lo = mid + 1;
        }
        return lo;
    }

    private long hoursNeeded(int[] piles, long k) {
        long hours = 0;
        for (int p : piles) hours += (p + k - 1) / k;
        return hours;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), h = in.nextInt();
        int[] piles = new int[n];
        for (int i = 0; i < n; i++) piles[i] = in.nextInt();
        System.out.println(new Solution().minEatingSpeed(piles, h));
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
4 8
3 6 7 11
out:
4
-->
<!-- test
in:
5 5
30 11 23 4 20
out:
30
-->
<!-- test
in:
5 6
30 11 23 4 20
out:
23
-->
<!-- test
in:
1 1000000000
1000000000
out:
1
-->
<!-- test
in:
2 2
1000000000 1000000000
out:
1000000000
-->

### Example 5 — Median of Two Sorted Arrays · Hard

- **Source:** [LC 4 · Median of Two Sorted Arrays](https://leetcode.com/problems/median-of-two-sorted-arrays/) — Hard · `G169` `NC150` `TI150`
- **Difficulty:** LeetCode Hard (≈ 2000 CF, est.)
- **Problem:** sorted arrays $A$ ($m$) and $B$ ($n$), $m + n \ge 1$, sizes up to 1000, values in $[-10^6, 10^6]$. Return the median of the merged multiset in $O(\log(m + n))$.
- **Thinking from first principles:** merging is $O(m + n)$, which is the honest first answer. To beat it, describe the median structurally: split the merged order into a left part of size $\lceil (m+n)/2 \rceil$ and a right part. Such a split takes some prefix $A[0..i)$ and $B[0..j)$ with $i + j = \text{half}$, and it is the correct split iff $A_{i-1} \le B_j$ and $B_{j-1} \le A_i$. As $i$ grows, $A_{i-1}$ grows and $B_j$ shrinks, so "$A_{i-1} > B_j$" is a monotone predicate: binary search on $i$ over the shorter array. Missing neighbours at the boundaries are treated as $\mp\infty$.

<details><summary>Solution</summary>

When the partition is valid, the median is $\max(A_{i-1}, B_{j-1})$ for odd total length, else the average of that and $\min(A_i, B_j)$. If $A_{i-1} > B_j$ we took too many from $A$ (move left), otherwise too few (move right). Searching the shorter array guarantees $0 \le j \le n$. Time $O(\log \min(m, n))$, space $O(1)$. The driver reads $m$, $n$ and the two arrays, and prints five decimals.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    double findMedianSortedArrays(vector<int>& a, vector<int>& b) {
        if (a.size() > b.size()) swap(a, b);              // search the shorter array
        int m = a.size(), n = b.size();
        int half = (m + n + 1) / 2;                       // size of the left part
        int lo = 0, hi = m;
        while (lo <= hi) {
            int i = lo + (hi - lo) / 2, j = half - i;     // i from a, j from b
            int aLeft = i > 0 ? a[i - 1] : INT_MIN, aRight = i < m ? a[i] : INT_MAX;
            int bLeft = j > 0 ? b[j - 1] : INT_MIN, bRight = j < n ? b[j] : INT_MAX;
            if (aLeft <= bRight && bLeft <= aRight) {     // correct split
                if ((m + n) % 2) return max(aLeft, bLeft);
                return (max(aLeft, bLeft) + (double)min(aRight, bRight)) / 2.0;
            }
            if (aLeft > bRight) hi = i - 1;               // too many taken from a
            else lo = i + 1;                              // too few taken from a
        }
        return 0.0;                                       // unreachable for sorted input
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int m, n;
    cin >> m >> n;
    vector<int> a(m), b(n);
    for (int& x : a) cin >> x;
    for (int& x : b) cin >> x;
    cout << fixed << setprecision(5) << Solution().findMedianSortedArrays(a, b) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public double findMedianSortedArrays(int[] a, int[] b) {
        if (a.length > b.length) { int[] t = a; a = b; b = t; }
        int m = a.length, n = b.length, half = (m + n + 1) / 2;
        int lo = 0, hi = m;
        while (lo <= hi) {
            int i = lo + (hi - lo) / 2, j = half - i;
            int aLeft = i > 0 ? a[i - 1] : Integer.MIN_VALUE, aRight = i < m ? a[i] : Integer.MAX_VALUE;
            int bLeft = j > 0 ? b[j - 1] : Integer.MIN_VALUE, bRight = j < n ? b[j] : Integer.MAX_VALUE;
            if (aLeft <= bRight && bLeft <= aRight) {
                if ((m + n) % 2 == 1) return Math.max(aLeft, bLeft);
                return (Math.max(aLeft, bLeft) + (double) Math.min(aRight, bRight)) / 2.0;
            }
            if (aLeft > bRight) hi = i - 1;
            else lo = i + 1;
        }
        return 0.0;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int m = in.nextInt(), n = in.nextInt();
        int[] a = new int[m], b = new int[n];
        for (int i = 0; i < m; i++) a[i] = in.nextInt();
        for (int i = 0; i < n; i++) b[i] = in.nextInt();
        System.out.printf(Locale.US, "%.5f%n", new Solution().findMedianSortedArrays(a, b));
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
2 1
1 3
2
out:
2.00000
-->
<!-- test
in:
2 2
1 2
3 4
out:
2.50000
-->
<!-- test
in:
0 1

1
out:
1.00000
-->
<!-- test
in:
3 4
1 5 9
2 3 4 10
out:
4.00000
-->
<!-- test
in:
2 2
-1000000 -1000000
1000000 1000000
out:
0.00000
-->

## 6. Pitfalls and things to remember

1. **Name the predicate and the invariant first.** "First index with `a[i] >= t`, answer in `[lo, hi)`." The code follows mechanically.
2. **Never write `lo = mid` with `mid = (lo + hi) / 2`.** When `hi = lo + 1`, `mid == lo` and the loop never ends. If you need "last true", search "first false" and subtract one.
3. **Midpoint overflow:** `(lo + hi) / 2` overflows `int` when both are near $2^{31}$. Use `lo + (hi - lo) / 2`. Java's `(lo + hi) >>> 1` also works for non-negative bounds.
4. **Answer-search bounds must contain the answer.** `lo` must be a valid candidate (often 1, not 0, for speeds and capacities, because 0 divides by zero), and `hi` must be feasible.
5. **The checker's arithmetic overflows quietly.** Koko's hours at speed 1 reach $10^{13}$, and `mid * mid` in a square-root search overflows `int` at 46341. Use 64-bit.
6. **Rotated arrays with duplicates** (`[1, 1, 1, 0, 1]`): when `a[lo] == a[mid] == a[hi]` you cannot tell which half is sorted. Shrink with `lo++, hi--`. The worst case is $O(n)$, so say it.
7. **Java `Arrays.binarySearch`** returns an arbitrary match among duplicates and a negative encoded insertion point otherwise. Write your own lower bound when "first" matters.
8. **C++ `lower_bound` on a `std::set`** must be `s.lower_bound(x)`. The free function `std::lower_bound(s.begin(), s.end(), x)` is $O(n)$ on non-random-access iterators.
9. **Real-valued searches:** loop a fixed number of times instead of `while (hi - lo > eps)`. With large magnitudes the gap may never drop below a tiny absolute epsilon.
10. **Monotonicity is a claim you must justify.** "More speed never hurts" is true for Koko. "More capacity never hurts" is true for shipping. Things like "more workers" can be non-monotone if workers have costs.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| "First and last position of the target" | lower bound and upper bound − 1 (two searches), $O(\log n)$ |
| Rotated search → "duplicates allowed?" | shrink both ends when `a[lo] == a[mid] == a[hi]`; worst case $O(n)$ ([LC 81 · Search in Rotated Sorted Array II](https://leetcode.com/problems/search-in-rotated-sorted-array-ii/) — Medium, [LC 154 · Find Minimum in Rotated Sorted Array II](https://leetcode.com/problems/find-minimum-in-rotated-sorted-array-ii/) — Hard) |
| Koko → "what if speeds can be real numbers?" | real-valued search with 100 iterations; or note the minimum is at a breakpoint $p_i / t$ |
| "Split array into $k$ parts minimising the largest sum" | search the answer $S$; greedy checker counts parts with sums $\le S$ ([LC 410 · Split Array Largest Sum](https://leetcode.com/problems/split-array-largest-sum/) — Hard) |
| Median → "k-th smallest of two sorted arrays" | same partition with $\text{half} = k$, or discard $k/2$ elements per step |
| Median → "the arrays are huge and on different machines" | binary search on the *value*: each machine answers "how many $\le v$" in $O(\log)$; $O(\log V \cdot \log n)$ round trips |
| "Search a row- and column-sorted matrix" | staircase from the top-right corner, $O(R + C)$; for k-th smallest, value search with a staircase count |
| "Unknown length / infinite array" | exponential search: probe indices 1, 2, 4, … until overshoot, then binary search; $O(\log p)$ |
| "Why $O(\log n)$ and not $O(\log^2 n)$?" | each step does $O(1)$ work, and the interval halves |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium. Time Based Key-Value Store is under [design problems](17-design-problems.md).

**Easy** (5)

- [ ] [LC 35 · Search Insert Position](https://leetcode.com/problems/search-insert-position/) — Easy · `NC250` `TI150`
- [ ] [LC 69 · Sqrt(x)](https://leetcode.com/problems/sqrtx/) — Easy · `NC250` `TI150`
- [ ] [LC 278 · First Bad Version](https://leetcode.com/problems/first-bad-version/) — Easy · `G75`
- [ ] [LC 374 · Guess Number Higher or Lower](https://leetcode.com/problems/guess-number-higher-or-lower/) — Easy · `NC250`
- [ ] [LC 704 · Binary Search](https://leetcode.com/problems/binary-search/) — Easy · `G75` `NC150`

**Medium** (10)

- [ ] [LC 33 · Search in Rotated Sorted Array](https://leetcode.com/problems/search-in-rotated-sorted-array/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 34 · Find First and Last Position of Element in Sorted Array](https://leetcode.com/problems/find-first-and-last-position-of-element-in-sorted-array/) — Medium · `TI150`
- [ ] [LC 74 · Search a 2D Matrix](https://leetcode.com/problems/search-a-2d-matrix/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 81 · Search in Rotated Sorted Array II](https://leetcode.com/problems/search-in-rotated-sorted-array-ii/) — Medium · `NC250`
- [ ] [LC 153 · Find Minimum in Rotated Sorted Array](https://leetcode.com/problems/find-minimum-in-rotated-sorted-array/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 162 · Find Peak Element](https://leetcode.com/problems/find-peak-element/) — Medium · `TI150`
- [ ] [LC 528 · Random Pick with Weight](https://leetcode.com/problems/random-pick-with-weight/) — Medium · `G169`
- [ ] [LC 658 · Find K Closest Elements](https://leetcode.com/problems/find-k-closest-elements/) — Medium · `G169` `NC250`
- [ ] [LC 875 · Koko Eating Bananas](https://leetcode.com/problems/koko-eating-bananas/) — Medium · `NC150`
- [ ] [LC 1011 · Capacity To Ship Packages Within D Days](https://leetcode.com/problems/capacity-to-ship-packages-within-d-days/) — Medium · `NC250`

**Hard** (3)

- [ ] [LC 4 · Median of Two Sorted Arrays](https://leetcode.com/problems/median-of-two-sorted-arrays/) — Hard · `G169` `NC150` `TI150`
- [ ] [LC 410 · Split Array Largest Sum](https://leetcode.com/problems/split-array-largest-sum/) — Hard · `NC250`
- [ ] [LC 1095 · Find in Mountain Array](https://leetcode.com/problems/find-in-mountain-array/) — Hard · `NC250`

**Beyond the lists:**

- [ ] [LC 852 · Peak Index in a Mountain Array](https://leetcode.com/problems/peak-index-in-a-mountain-array/) — Medium — predicate `a[i] > a[i+1]`
- [ ] [LC 540 · Single Element in a Sorted Array](https://leetcode.com/problems/single-element-in-a-sorted-array/) — Medium — predicate on pair parity
- [ ] [LC 1283 · Find the Smallest Divisor Given a Threshold](https://leetcode.com/problems/find-the-smallest-divisor-given-a-threshold/) — Medium — Koko in disguise
- [ ] [LC 1482 · Minimum Number of Days to Make m Bouquets](https://leetcode.com/problems/minimum-number-of-days-to-make-m-bouquets/) — Medium — answer search + greedy count
- [ ] [LC 2187 · Minimum Time to Complete Trips](https://leetcode.com/problems/minimum-time-to-complete-trips/) — Medium — 64-bit bounds
- [ ] [LC 378 · Kth Smallest Element in a Sorted Matrix](https://leetcode.com/problems/kth-smallest-element-in-a-sorted-matrix/) — Medium — value search + staircase count
- [ ] [LC 1201 · Ugly Number III](https://leetcode.com/problems/ugly-number-iii/) — Medium — value search + inclusion–exclusion count
- [ ] [LC 154 · Find Minimum in Rotated Sorted Array II](https://leetcode.com/problems/find-minimum-in-rotated-sorted-array-ii/) — Hard — duplicates, $O(n)$ worst case
- [ ] [LC 719 · Find K-th Smallest Pair Distance](https://leetcode.com/problems/find-k-th-smallest-pair-distance/) — Hard — value search + two-pointer count
- [ ] [LC 2141 · Maximum Running Time of N Computers](https://leetcode.com/problems/maximum-running-time-of-n-computers/) — Hard — answer search with a capped-sum checker

## 9. CP counterpart

- [Binary search and binary search on answer (CP)](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md): the same template, plus parallel binary search hints, searching on real numbers and fractional answers.
- [Ternary search and meet in the middle](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md): unimodal functions, the cousin of "find peak".
- [Aliens trick / WQS binary search](../07-DP-Optimizations/06-aliens-trick-wqs-binary-search.md): binary search on a Lagrange multiplier. IGM depth, never in interviews.

Transfers: everything. In interviews, write the loop inline with descriptive names (`lo`, `hi`, `feasible(mid)`) and say the invariant out loud.

## 10. Self-check

1. State the half-open invariant and the two update rules of the "first true" template.
2. Why does `lo = mid` with a floor midpoint loop forever, and how do you avoid it?
3. In "find min in rotated array", why compare `nums[mid]` with `nums[hi]` rather than `nums[lo]`?
4. Koko: why is "hours(k) ≤ h" monotone, and what are safe initial bounds?
5. Median of two arrays: write the validity condition of a partition and explain why we search the shorter array.
6. How do you compute "last index with `a[i] <= t`" using only lower/upper bound?
7. Rotated search with duplicates: what is the worst-case complexity and why?
8. How many iterations does a binary search over $[0, 10^{18}]$ need?

<details><summary>Answers</summary>

1. The answer lies in `[lo, hi)`. If `pred(mid)` is true, `hi = mid`. Otherwise `lo = mid + 1`. Stop when `lo == hi`.
2. When `hi == lo + 1`, `mid == lo`, so `lo = mid` does not shrink the interval. Use the first-true form, or a ceiling midpoint with the mirrored invariant.
3. On an unrotated array every element is `>= nums[lo]`, so comparing with `nums[lo]` cannot tell the two runs apart. `nums[hi]` always belongs to the run that starts at the minimum, so `nums[mid] > nums[hi]` exactly means mid is in the first run.
4. Each $\lceil p_i / k \rceil$ is non-increasing in $k$, so the sum is too. Bounds: `lo = 1` (0 is invalid) and `hi = max(piles)`, which is feasible since $h \ge n$.
5. $A_{i-1} \le B_j$ and $B_{j-1} \le A_i$, with missing neighbours as $\mp\infty$. Searching the shorter array keeps $j = \text{half} - i$ inside $[0, n]$ and gives $O(\log \min(m,n))$.
6. `upper_bound(t) - 1` (and check that it is $\ge 0$).
7. $O(n)$: for arrays like `[1,1,…,1,0,1,…,1]`, `a[lo] == a[mid] == a[hi]` gives no information, and each step can only discard one element from each end.
8. $\lceil \log_2(10^{18} + 1) \rceil = 60$ iterations.

</details>
