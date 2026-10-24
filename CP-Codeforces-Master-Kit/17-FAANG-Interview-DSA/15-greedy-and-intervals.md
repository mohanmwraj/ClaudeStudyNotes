# Greedy and Intervals

> **Band:** 🟢 1200 – 🔵 1800 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [sorting and comparators](../01-Foundations/05-sorting-and-comparators.md), [heaps](09-heaps-and-top-k.md)
> **You can say you know this when:** you can justify a greedy choice with an exchange argument or an invariant in two sentences, and you know the three interval moves cold: sort by start to merge, sort by end to select, sweep events to count overlaps.

A greedy algorithm makes the locally best choice and never revisits it. It is the fastest and shortest kind of solution, and the most dangerous: many plausible greedy rules are wrong. In interviews the bar is simple. **State the rule, then prove it** with an exchange argument ("any optimal solution can be changed to agree with my first choice without getting worse") or an invariant ("after step $i$, my partial answer is the best possible for the first $i$ items"). If you cannot, fall back to DP.

## 1. First principles — why this works

### 1.1 Exchange argument

Let $g$ be the greedy's first choice and $O$ any optimal solution. Show that swapping some element of $O$ for $g$ keeps $O$ feasible and no worse. Then an optimal solution starts with $g$, and the same argument applies to the remaining subproblem, so the greedy solution is optimal by induction. Activity selection (keep as many non-overlapping intervals as possible) is the model case: **pick the interval that ends first.** Any optimal solution's first interval ends no earlier, so swapping it for the earliest-ending interval keeps everything after it compatible.

### 1.2 The three interval moves

| Goal | Sort by | Rule | Why |
|---|---|---|---|
| merge overlapping intervals / union length | start | extend the current block while `next.start <= current.end` | with sorted starts, an interval that does not touch the current block cannot touch any earlier block either |
| maximum non-overlapping subset / minimum removals / minimum arrows | end | take an interval if it starts after the last taken end | exchange argument of §1.1 |
| maximum overlap / minimum rooms / car pooling | events | +1 at a start, −1 at an end, sweep in time order | the depth at time $t$ is the number of intervals containing $t$, and the maximum depth is the minimum number of rooms (a lower bound that greedy room assignment attains) |

Tie-breaking at equal times decides whether touching intervals overlap. For meeting rooms, an end at time $t$ frees the room for a start at $t$, so process ends before starts. Write it down.

### 1.3 Reach and potential arguments

Jump Game keeps the farthest reachable index `reach`. Index $i$ is reachable iff $i \le$ `reach` after processing $0..i-1$, because reachable positions form a prefix: if $j$ is reachable, so is everything before $j$ on the way. Gas Station uses a potential argument: if the running tank drops below zero at station $i$ when starting from $s$, then **no** start in $[s, i]$ works (each of them starts with a tank no larger than the one we had when passing it), so restart at $i + 1$. If the total gas is at least the total cost, the last restart works.

### 1.4 When greedy fails

Coin change with `{1, 3, 4}`, 0/1 knapsack by value density, longest path, and "take the biggest number first" in most scheduling-with-deadlines variants all fail. Interviewers like to ask "why not greedy?" for DP problems. A two-line counterexample is the answer.

## 2. Formulas, rules and complexities

| Problem | Rule | Time |
|---|---|---|
| Merge Intervals | sort by start, extend `end = max(end, next.end)` | $O(n \log n)$ |
| Insert Interval (sorted input) | copy the ones ending before, merge the overlapping, copy the rest | $O(n)$ |
| Non-overlapping Intervals | sort by end, count kept; answer $n - \text{kept}$ | $O(n \log n)$ |
| Minimum arrows | same as above with closed intervals (touching counts as overlap) | $O(n \log n)$ |
| Meeting Rooms II | sweep sorted starts and ends with two pointers, or a min-heap of end times | $O(n \log n)$ |
| Jump Game | `reach = max(reach, i + a[i])` while `i <= reach` | $O(n)$ |
| Jump Game II | BFS by levels: `[start, end]` of the current jump, next level ends at the max reach | $O(n)$ |
| Gas Station | restart after a negative tank; valid iff $\sum \text{gas} \ge \sum \text{cost}$ | $O(n)$ |
| Partition Labels | last occurrence of each letter; cut when `i == max last seen` | $O(n)$ |
| Candy | two passes (left-to-right for the left neighbour rule, right-to-left for the right) | $O(n)$ |
| Largest Number | sort strings by `a + b > b + a` (a total preorder) | $O(n \log n \cdot L)$ |

## 3. Reusable templates (C++ and Java)

Merge, select by end, and event sweep:

```cpp
vector<vector<int>> mergeIntervals(vector<vector<int>> v) {
    sort(v.begin(), v.end());                            // by start (then end)
    vector<vector<int>> out;
    for (auto& iv : v) {
        if (!out.empty() && iv[0] <= out.back()[1]) out.back()[1] = max(out.back()[1], iv[1]);
        else out.push_back(iv);                          // starts after the current block ends
    }
    return out;
}

int maxNonOverlapping(vector<vector<int>> v) {           // half-open: [s, e) and [e, f) do not overlap
    sort(v.begin(), v.end(), [](const vector<int>& a, const vector<int>& b) { return a[1] < b[1]; });
    int kept = 0;
    long long lastEnd = LLONG_MIN;
    for (auto& iv : v)
        if (iv[0] >= lastEnd) { ++kept; lastEnd = iv[1]; }   // earliest end first
    return kept;
}

int maxOverlap(const vector<vector<int>>& v) {           // ends before starts at equal times
    vector<pair<int, int>> ev;
    for (auto& iv : v) { ev.push_back({iv[0], +1}); ev.push_back({iv[1], -1}); }
    sort(ev.begin(), ev.end());                          // (t, -1) sorts before (t, +1)
    int cur = 0, best = 0;
    for (auto& [t, d] : ev) best = max(best, cur += d);
    return best;
}
```

```java
static List<int[]> mergeIntervals(int[][] v) {
    int[][] a = v.clone();
    Arrays.sort(a, (x, y) -> x[0] != y[0] ? Integer.compare(x[0], y[0]) : Integer.compare(x[1], y[1]));
    List<int[]> out = new ArrayList<>();
    for (int[] iv : a) {
        if (!out.isEmpty() && iv[0] <= out.get(out.size() - 1)[1])
            out.get(out.size() - 1)[1] = Math.max(out.get(out.size() - 1)[1], iv[1]);
        else out.add(new int[]{iv[0], iv[1]});
    }
    return out;
}

static int maxNonOverlapping(int[][] v) {
    int[][] a = v.clone();
    Arrays.sort(a, (x, y) -> Integer.compare(x[1], y[1]));
    int kept = 0;
    long lastEnd = Long.MIN_VALUE;
    for (int[] iv : a) if (iv[0] >= lastEnd) { kept++; lastEnd = iv[1]; }
    return kept;
}

static int maxOverlap(int[][] v) {
    int[][] ev = new int[2 * v.length][];
    for (int i = 0; i < v.length; i++) { ev[2 * i] = new int[]{v[i][0], 1}; ev[2 * i + 1] = new int[]{v[i][1], -1}; }
    Arrays.sort(ev, (x, y) -> x[0] != y[0] ? Integer.compare(x[0], y[0]) : Integer.compare(x[1], y[1]));
    int cur = 0, best = 0;
    for (int[] e : ev) { cur += e[1]; best = Math.max(best, cur); }
    return best;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| intervals + "merge", "union", "total covered length" | sort by start, sweep |
| intervals + "maximum number that don't overlap", "minimum to remove", "arrows" | sort by end, earliest-end greedy |
| intervals + "how many at once", "minimum rooms / platforms", "capacity never exceeded" | event sweep or a min-heap of end times |
| "can you reach the end", "minimum jumps" | farthest reach; BFS levels over ranges |
| circular route with gains and costs | restart-after-deficit + total check |
| "assign / pair to maximise matches" (cookies, boats) | sort both, two pointers |
| "arrange to form the largest / smallest number" | custom comparator on concatenations |
| "each child more than its neighbour", two-sided constraints | two passes, take the max |
| "schedule with deadlines and durations to maximise count" | sort by deadline + max-heap with regret ([CP](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md)) |
| any greedy you cannot prove | try a counterexample on 3–4 elements, then DP |

## 5. Worked examples

### Example 1 — Jump Game · Medium

- **Source:** [LC 55 · Jump Game](https://leetcode.com/problems/jump-game/) — Medium · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** `a[i]` is the maximum jump length from index $i$ ($n \le 10^4$, $a_i \le 10^5$). Starting at index 0, can you reach the last index?
- **Thinking from first principles:** DP ("is $i$ reachable?" from every $j$ that can jump to it) is $O(n^2)$. The reachable set is always a prefix $[0, \text{reach}]$: from any reachable $j$ you can land on every index up to $j + a_j$. So one number describes it. Scan $i$ while $i \le \text{reach}$ and extend $\text{reach} = \max(\text{reach}, i + a_i)$. If the scan reaches the end, the answer is yes. If $i$ exceeds `reach`, there is a gap that nothing crosses.

<details><summary>Solution</summary>

Invariant: after processing indices $0..i$, `reach` is the farthest index reachable using jumps from those indices, and every index up to it is reachable. $O(n)$ time, $O(1)$ space.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    bool canJump(vector<int>& nums) {
        int reach = 0, n = nums.size();
        for (int i = 0; i < n && i <= reach; ++i) {     // only reachable indices may extend reach
            reach = max(reach, i + nums[i]);
            if (reach >= n - 1) return true;
        }
        return false;
    }
};

int main() {
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << (Solution().canJump(a) ? "true" : "false") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public boolean canJump(int[] nums) {
        int reach = 0, n = nums.length;
        for (int i = 0; i < n && i <= reach; i++) {
            reach = Math.max(reach, i + nums[i]);
            if (reach >= n - 1) return true;
        }
        return false;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        System.out.println(new Solution().canJump(a));
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
2 3 1 1 4
out:
true
-->
<!-- test
in:
5
3 2 1 0 4
out:
false
-->
<!-- test
in:
1
0
out:
true
-->
<!-- test
in:
2
0 1
out:
false
-->

### Example 2 — Merge Intervals · Medium

- **Source:** [LC 56 · Merge Intervals](https://leetcode.com/problems/merge-intervals/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** merge all overlapping closed intervals ($n \le 10^4$, $0 \le s \le e \le 10^4$). Touching intervals such as `[1,4]` and `[4,5]` overlap.
- **Thinking from first principles:** comparing every pair and merging repeatedly is $O(n^2)$ or worse. After sorting by start, each interval can only overlap the **current merged block** (the last one in the output). If it started after the block's end, then because starts are sorted, every later interval also starts after that end, so the block is final. Otherwise it overlaps, so extend the block's end to the larger of the two ends.

<details><summary>Solution</summary>

Sort by start, then one pass. Correctness follows from the observation above, by induction on the sorted order. $O(n \log n)$ time, $O(n)$ output. The driver prints LeetCode's nested format.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<vector<int>> merge(vector<vector<int>>& intervals) {
        sort(intervals.begin(), intervals.end());
        vector<vector<int>> out;
        for (auto& iv : intervals) {
            if (!out.empty() && iv[0] <= out.back()[1])
                out.back()[1] = max(out.back()[1], iv[1]);   // overlaps the current block
            else
                out.push_back(iv);                           // the current block is final
        }
        return out;
    }
};

int main() {
    int n;
    cin >> n;
    vector<vector<int>> v(n, vector<int>(2));
    for (auto& iv : v) cin >> iv[0] >> iv[1];
    auto res = Solution().merge(v);
    string s = "[";
    for (size_t i = 0; i < res.size(); ++i)
        s += (i ? ",[" : "[") + to_string(res[i][0]) + "," + to_string(res[i][1]) + "]";
    cout << s << "]\n";
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int[][] merge(int[][] intervals) {
        Arrays.sort(intervals, (a, b) -> Integer.compare(a[0], b[0]));
        List<int[]> out = new ArrayList<>();
        for (int[] iv : intervals) {
            if (!out.isEmpty() && iv[0] <= out.get(out.size() - 1)[1])
                out.get(out.size() - 1)[1] = Math.max(out.get(out.size() - 1)[1], iv[1]);
            else out.add(new int[]{iv[0], iv[1]});
        }
        return out.toArray(new int[0][]);
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[][] v = new int[n][2];
        for (int i = 0; i < n; i++) { v[i][0] = in.nextInt(); v[i][1] = in.nextInt(); }
        int[][] res = new Solution().merge(v);
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < res.length; i++) sb.append(i > 0 ? ",[" : "[").append(res[i][0]).append(',').append(res[i][1]).append(']');
        System.out.println(sb.append(']'));
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
1 3
2 6
8 10
15 18
out:
[[1,6],[8,10],[15,18]]
-->
<!-- test
in:
2
1 4
4 5
out:
[[1,5]]
-->
<!-- test
in:
3
1 10
2 3
4 5
out:
[[1,10]]
-->
<!-- test
in:
1
0 0
out:
[[0,0]]
-->

### Example 3 — Non-overlapping Intervals · Medium

- **Source:** [LC 435 · Non-overlapping Intervals](https://leetcode.com/problems/non-overlapping-intervals/) — Medium · `G169` `B75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** the minimum number of intervals to remove so the rest do not overlap. Touching intervals (`[1,2]` and `[2,3]`) do **not** overlap. $n \le 10^5$.
- **Thinking from first principles:** minimising removals is the same as maximising the number kept, which is activity selection. Sorting by start is the tempting wrong rule (a long interval that starts first can block many short ones). Sorting by length is also wrong. **Sort by end**: the interval that ends first leaves the most room for the rest, and the exchange argument in §1.1 makes that rigorous. Keep an interval when its start is $\ge$ the last kept end.

<details><summary>Solution</summary>

Answer $= n - \text{kept}$. $O(n \log n)$ time, $O(1)$ extra beyond the sort.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int eraseOverlapIntervals(vector<vector<int>>& intervals) {
        sort(intervals.begin(), intervals.end(),
             [](const vector<int>& a, const vector<int>& b) { return a[1] < b[1]; });   // earliest end first
        int kept = 0;
        long long lastEnd = LLONG_MIN;
        for (auto& iv : intervals)
            if (iv[0] >= lastEnd) { ++kept; lastEnd = iv[1]; }     // compatible with everything kept
        return (int)intervals.size() - kept;
    }
};

int main() {
    int n;
    cin >> n;
    vector<vector<int>> v(n, vector<int>(2));
    for (auto& iv : v) cin >> iv[0] >> iv[1];
    cout << Solution().eraseOverlapIntervals(v) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int eraseOverlapIntervals(int[][] intervals) {
        Arrays.sort(intervals, (a, b) -> Integer.compare(a[1], b[1]));
        int kept = 0;
        long lastEnd = Long.MIN_VALUE;
        for (int[] iv : intervals) if (iv[0] >= lastEnd) { kept++; lastEnd = iv[1]; }
        return intervals.length - kept;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[][] v = new int[n][2];
        for (int i = 0; i < n; i++) { v[i][0] = in.nextInt(); v[i][1] = in.nextInt(); }
        System.out.println(new Solution().eraseOverlapIntervals(v));
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
1 2
2 3
3 4
1 3
out:
1
-->
<!-- test
in:
3
1 2
1 2
1 2
out:
2
-->
<!-- test
in:
2
1 2
2 3
out:
0
-->
<!-- test
in:
4
1 100
11 22
1 11
2 12
out:
2
-->

### Example 4 — Meeting Rooms II · Medium 🔒

- **Source:** [LC 253 · Meeting Rooms II](https://leetcode.com/problems/meeting-rooms-ii/) — Medium 🔒 · `G169` `B75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** meeting intervals `[start, end)` ($n \le 10^4$). What is the minimum number of rooms so that no two meetings in the same room overlap? A meeting ending at $t$ frees its room for one starting at $t$.
- **Thinking from first principles:** at any time $t$, all meetings in progress need different rooms, so the answer is at least the maximum number of simultaneous meetings. That many rooms also suffice: process meetings by start time and reuse any room whose meeting has ended (if none has, open a new room). The number of rooms open only grows when every room is busy, i.e. when the overlap depth increases. So answer = maximum depth. Compute it by sorting starts and ends separately and merging them with two pointers, counting ends before starts at equal times. The min-heap of end times is the equivalent "room assignment" view.

<details><summary>Solution</summary>

Two sorted arrays and two pointers: when the next start is before the earliest unprocessed end, a room is added; otherwise a meeting ended, so a room is freed. $O(n \log n)$ time, $O(n)$ space.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int minMeetingRooms(vector<vector<int>>& intervals) {
        int n = intervals.size();
        vector<int> starts(n), ends(n);
        for (int i = 0; i < n; ++i) { starts[i] = intervals[i][0]; ends[i] = intervals[i][1]; }
        sort(starts.begin(), starts.end());
        sort(ends.begin(), ends.end());
        int rooms = 0, best = 0;
        for (int i = 0, j = 0; i < n; ++i) {
            if (starts[i] < ends[j]) ++rooms;        // all rooms busy: open one
            else ++j;                                 // a meeting ended at or before this start: reuse
            best = max(best, rooms);
        }
        return best;
    }
};

int main() {
    int n;
    cin >> n;
    vector<vector<int>> v(n, vector<int>(2));
    for (auto& iv : v) cin >> iv[0] >> iv[1];
    cout << Solution().minMeetingRooms(v) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int minMeetingRooms(int[][] intervals) {
        int n = intervals.length;
        int[] starts = new int[n], ends = new int[n];
        for (int i = 0; i < n; i++) { starts[i] = intervals[i][0]; ends[i] = intervals[i][1]; }
        Arrays.sort(starts);
        Arrays.sort(ends);
        int rooms = 0, best = 0;
        for (int i = 0, j = 0; i < n; i++) {
            if (starts[i] < ends[j]) rooms++;
            else j++;
            best = Math.max(best, rooms);
        }
        return best;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[][] v = new int[n][2];
        for (int i = 0; i < n; i++) { v[i][0] = in.nextInt(); v[i][1] = in.nextInt(); }
        System.out.println(new Solution().minMeetingRooms(v));
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
3
0 30
5 10
15 20
out:
2
-->
<!-- test
in:
2
7 10
2 4
out:
1
-->
<!-- test
in:
3
1 5
5 10
10 15
out:
1
-->
<!-- test
in:
4
1 10
2 9
3 8
4 7
out:
4
-->

### Example 5 — Gas Station · Medium

- **Source:** [LC 134 · Gas Station](https://leetcode.com/problems/gas-station/) — Medium · `G169` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1500 CF, est.)
- **Problem:** $n \le 10^5$ stations on a circle. Station $i$ gives `gas[i]`, and driving to station $i+1$ costs `cost[i]`. Return the start index from which a full circle is possible (unique if it exists), or $-1$.
- **Thinking from first principles:** trying every start is $O(n^2)$. Two facts give $O(n)$. (1) If $\sum (\text{gas} - \text{cost}) < 0$, no start works, since the total fuel is not enough. (2) If you start at $s$ and the tank first becomes negative after station $i$, then no start in $s..i$ works: starting at some $k$ in between, you arrive at $k$ with the tank $\ge 0$ that you had on the way from $s$, so starting at $k$ with an empty tank leaves you no better off. So restart at $i + 1$ with an empty tank. If the total is non-negative, the last restart point completes the circle. The deficits before it are covered by the surplus after it, because the total is non-negative.

<details><summary>Solution</summary>

One pass with `total` (overall balance) and `tank` (balance since the current start). $O(n)$ time, $O(1)$ space. Sums fit in 64-bit (`int` also suffices for LeetCode's bounds, $10^5 \times 10^4$).

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int canCompleteCircuit(vector<int>& gas, vector<int>& cost) {
        long long total = 0, tank = 0;
        int start = 0;
        for (int i = 0; i < (int)gas.size(); ++i) {
            int diff = gas[i] - cost[i];
            total += diff;
            tank += diff;
            if (tank < 0) {                          // no start in [start, i] can work
                start = i + 1;
                tank = 0;
            }
        }
        return total < 0 ? -1 : start;
    }
};

int main() {
    int n;
    cin >> n;
    vector<int> gas(n), cost(n);
    for (int& x : gas) cin >> x;
    for (int& x : cost) cin >> x;
    cout << Solution().canCompleteCircuit(gas, cost) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int canCompleteCircuit(int[] gas, int[] cost) {
        long total = 0, tank = 0;
        int start = 0;
        for (int i = 0; i < gas.length; i++) {
            int diff = gas[i] - cost[i];
            total += diff;
            tank += diff;
            if (tank < 0) { start = i + 1; tank = 0; }
        }
        return total < 0 ? -1 : start;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] gas = new int[n], cost = new int[n];
        for (int i = 0; i < n; i++) gas[i] = in.nextInt();
        for (int i = 0; i < n; i++) cost[i] = in.nextInt();
        System.out.println(new Solution().canCompleteCircuit(gas, cost));
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
1 2 3 4 5
3 4 5 1 2
out:
3
-->
<!-- test
in:
3
2 3 4
3 4 3
out:
-1
-->
<!-- test
in:
1
5
4
out:
0
-->
<!-- test
in:
4
0 0 0 10
1 1 1 1
out:
3
-->

## 6. Pitfalls and things to remember

1. **Prove or test the greedy.** Try 3–4 element counterexamples (a long interval covering short ones, equal ends, zero-length intervals) before coding.
2. **Open vs closed intervals:** "non-overlapping" in LC 435 treats touching as fine (`>=`), while arrows (LC 452) treat touching as overlapping (`>`). Read the examples and say which one applies.
3. **Sort key:** merge sorts by start, selection sorts by end. Mixing them is the classic wrong answer.
4. **Event ties:** decide whether an end and a start at the same time overlap, and order the events accordingly.
5. **Comparator overflow in Java:** `(a, b) -> a[0] - b[0]` overflows for values near $\pm 2^{31}$. Use `Integer.compare`.
6. **Java sorting of `int[][]`:** `Arrays.sort` on object arrays is a stable merge sort (TimSort), safe from the quicksort worst case. Sorting `int[]` uses dual-pivot quicksort, which matters only against adversarial CP tests, not on LeetCode.
7. **`lastEnd` initial value** must be below any start. Use `LLONG_MIN` / `Long.MIN_VALUE` or the first interval itself.
8. **Mutating input:** sorting `intervals` in place is usually acceptable, but say so.
9. **Gas station uniqueness:** the problem promises a unique answer. The algorithm returns the last restart point, which is the answer whenever one exists.
10. **Jump Game II** is BFS over index ranges, not "jump to the farthest". Track the current range end and the next range end.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| Jump Game → "minimum number of jumps" | level-by-level reach: when `i` passes the current level end, jump++ and move to the next end ([LC 45 · Jump Game II](https://leetcode.com/problems/jump-game-ii/) — Medium) |
| Merge → "intervals arrive one by one, keep them merged" | ordered map from start to end; on insert, merge with the floor neighbour and every overlapping successor: $O(\log n)$ amortised |
| → "insert one interval into a sorted, disjoint list" | linear scan: before, overlapping (merge), after ([LC 57 · Insert Interval](https://leetcode.com/problems/insert-interval/) — Medium) |
| Non-overlapping → "maximise total weight, not count" | weighted interval scheduling: DP + binary search ([LC 1235 · Maximum Profit in Job Scheduling](https://leetcode.com/problems/maximum-profit-in-job-scheduling/) — Hard) |
| Meeting rooms → "which room does each meeting get?" | min-heap of (end time, room id) plus a min-heap of free room ids ([LC 2402 · Meeting Rooms III](https://leetcode.com/problems/meeting-rooms-iii/) — Hard) |
| → "free time common to all employees" | merge all intervals, report the gaps ([LC 759 · Employee Free Time](https://leetcode.com/problems/employee-free-time/) — Hard 🔒) |
| Gas station → "prove the restart rule" | arriving at any $k \in (s, i]$ from $s$ you had tank $\ge 0$, so starting at $k$ empty is no better; therefore none of them reaches past $i$ |
| "Is this greedy or DP?" | if a choice can be undone by a later better option, it is DP or greedy-with-regret (heap); if an exchange argument works, it is greedy |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium.

**Easy** (3)

- [ ] [LC 228 · Summary Ranges](https://leetcode.com/problems/summary-ranges/) — Easy · `TI150`
- [ ] [LC 252 · Meeting Rooms](https://leetcode.com/problems/meeting-rooms/) — Easy 🔒 · `G169` `B75` `NC150`
- [ ] [LC 860 · Lemonade Change](https://leetcode.com/problems/lemonade-change/) — Easy · `NC250`

**Medium** (18)

- [ ] [LC 45 · Jump Game II](https://leetcode.com/problems/jump-game-ii/) — Medium · `NC150` `TI150`
- [ ] [LC 55 · Jump Game](https://leetcode.com/problems/jump-game/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 56 · Merge Intervals](https://leetcode.com/problems/merge-intervals/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 57 · Insert Interval](https://leetcode.com/problems/insert-interval/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 122 · Best Time to Buy and Sell Stock II](https://leetcode.com/problems/best-time-to-buy-and-sell-stock-ii/) — Medium · `NC250` `TI150`
- [ ] [LC 134 · Gas Station](https://leetcode.com/problems/gas-station/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 179 · Largest Number](https://leetcode.com/problems/largest-number/) — Medium · `G169`
- [ ] [LC 253 · Meeting Rooms II](https://leetcode.com/problems/meeting-rooms-ii/) — Medium 🔒 · `G169` `B75` `NC150`
- [ ] [LC 435 · Non-overlapping Intervals](https://leetcode.com/problems/non-overlapping-intervals/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 452 · Minimum Number of Arrows to Burst Balloons](https://leetcode.com/problems/minimum-number-of-arrows-to-burst-balloons/) — Medium · `TI150`
- [ ] [LC 649 · Dota2 Senate](https://leetcode.com/problems/dota2-senate/) — Medium · `NC250`
- [ ] [LC 678 · Valid Parenthesis String](https://leetcode.com/problems/valid-parenthesis-string/) — Medium · `NC150`
- [ ] [LC 763 · Partition Labels](https://leetcode.com/problems/partition-labels/) — Medium · `NC150`
- [ ] [LC 846 · Hand of Straights](https://leetcode.com/problems/hand-of-straights/) — Medium · `NC150`
- [ ] [LC 978 · Longest Turbulent Subarray](https://leetcode.com/problems/longest-turbulent-subarray/) — Medium · `NC250`
- [ ] [LC 1094 · Car Pooling](https://leetcode.com/problems/car-pooling/) — Medium · `NC250`
- [ ] [LC 1871 · Jump Game VII](https://leetcode.com/problems/jump-game-vii/) — Medium · `NC250`
- [ ] [LC 1899 · Merge Triplets to Form Target Triplet](https://leetcode.com/problems/merge-triplets-to-form-target-triplet/) — Medium · `NC150`

**Hard** (4)

- [ ] [LC 135 · Candy](https://leetcode.com/problems/candy/) — Hard · `NC250` `TI150`
- [ ] [LC 759 · Employee Free Time](https://leetcode.com/problems/employee-free-time/) — Hard 🔒 · `G169`
- [ ] [LC 1851 · Minimum Interval to Include Each Query](https://leetcode.com/problems/minimum-interval-to-include-each-query/) — Hard · `NC150`
- [ ] [LC 2402 · Meeting Rooms III](https://leetcode.com/problems/meeting-rooms-iii/) — Hard · `NC250`

**Beyond the lists:**

- [ ] [LC 455 · Assign Cookies](https://leetcode.com/problems/assign-cookies/) — Easy — sort both, two pointers
- [ ] [LC 1710 · Maximum Units on a Truck](https://leetcode.com/problems/maximum-units-on-a-truck/) — Easy — fractional-knapsack style greedy (works because items are divisible into boxes)
- [ ] [LC 986 · Interval List Intersections](https://leetcode.com/problems/interval-list-intersections/) — Medium — two pointers, advance the earlier end
- [ ] [LC 1288 · Remove Covered Intervals](https://leetcode.com/problems/remove-covered-intervals/) — Medium — sort by start asc, end desc
- [ ] [LC 2406 · Divide Intervals Into Minimum Number of Groups](https://leetcode.com/problems/divide-intervals-into-minimum-number-of-groups/) — Medium — meeting rooms with closed intervals
- [ ] [LC 1024 · Video Stitching](https://leetcode.com/problems/video-stitching/) — Medium — Jump Game II on intervals
- [ ] [LC 1029 · Two City Scheduling](https://leetcode.com/problems/two-city-scheduling/) — Medium — sort by cost difference
- [ ] [LC 406 · Queue Reconstruction by Height](https://leetcode.com/problems/queue-reconstruction-by-height/) — Medium — tallest first, insert at index $k$
- [ ] [LC 1326 · Minimum Number of Taps to Open to Water a Garden](https://leetcode.com/problems/minimum-number-of-taps-to-open-to-water-a-garden/) — Hard — interval covering
- [ ] [LC 630 · Course Schedule III](https://leetcode.com/problems/course-schedule-iii/) — Hard — deadline sort + max-heap with regret
- [ ] [LC 330 · Patching Array](https://leetcode.com/problems/patching-array/) — Hard — "everything below `miss` is reachable" invariant

## 9. CP counterpart

- [Greedy and exchange arguments](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md): the proof techniques at full strength, with sorting by a derived key ($a_i b_j < a_j b_i$).
- [Greedy with heaps and regret](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md): scheduling with deadlines, "undo the worst choice".
- [Coordinate compression and sweep line](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md): event sweeps over huge coordinates, union of rectangles.
- [Prefix sums and difference arrays](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md): car pooling as a difference array when coordinates are small.

CP greedy problems are much harder to *find* (the rule is the whole problem). Interview greedy problems usually have a known rule, and the evaluation is whether you can justify it.

## 10. Self-check

1. Prove that "earliest end first" maximises the number of non-overlapping intervals.
2. Why does merging require sorting by start, while selection requires sorting by end?
3. Why is the minimum number of meeting rooms equal to the maximum overlap depth?
4. In Jump Game, why does a single number `reach` describe the set of reachable indices?
5. Prove the Gas Station restart rule.
6. Give a counterexample to "sort by start" for Non-overlapping Intervals.
7. How do touching intervals change the comparisons in merge, selection and sweep?

<details><summary>Answers</summary>

1. Let $g$ end first among all intervals and let $O$ be optimal. Replace $O$'s first interval by $g$. Since $g$ ends no later, it is still compatible with $O$'s second interval onward, and the count is unchanged. Recurse on the intervals starting at or after $g$'s end.
2. Merging needs every interval that touches the current block to come before the first one that does not, and sorted starts give that. Selection needs the choice that leaves the most room, which is the earliest end.
3. Meetings that overlap at one time need distinct rooms, so the depth is a lower bound. The greedy assignment by start time opens a new room only when all rooms are busy, which happens only when the depth increases, so it uses exactly the maximum depth.
4. If $j$ is reachable, every index between 0 and $j$ is reachable as well (the jumps that reached $j$ can stop earlier), so the reachable set is a prefix, described by its last index.
5. If the tank from start $s$ first goes negative after $i$, then for any $k \in (s, i]$ we arrived at $k$ with tank $\ge 0$. Starting at $k$ with 0 is no better, so it also fails by $i$. With total $\ge 0$, the final start $r$ never goes negative on $r..n-1$, and the deficit of $0..r-1$ is at most the surplus collected on $r..n-1$, so the wrap-around succeeds.
6. `[1,100], [2,3], [4,5]`: by start you keep `[1,100]` and must drop the other two (2 removals). By end you keep `[2,3]` and `[4,5]` (1 removal).
7. Merge: `<=` merges touching intervals (closed intervals). Selection: `>=` keeps touching ones (half-open). Sweep: process ends before starts at equal times if touching does not overlap, starts first otherwise.

</details>
