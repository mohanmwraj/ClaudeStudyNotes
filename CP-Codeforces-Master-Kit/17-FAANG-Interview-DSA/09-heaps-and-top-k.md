# Heaps and Top-K

> **Band:** 🔵 1400–1900 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [trees](07-trees-and-bst.md), [sorting and comparators](../01-Foundations/05-sorting-and-comparators.md)
> **You can say you know this when:** you pick the right heap direction for "top $k$" without thinking (min-heap for the $k$ largest), write comparators correctly in both languages, and can derive the two-heaps median and the $k$-way merge from the heap invariant.

A heap answers one question fast: **"what is the current minimum (or maximum)?"** while elements keep arriving and leaving. Interview problems use it in four shapes: keep the best $k$ of a stream, merge $k$ sorted sources, maintain a split point (median) with two heaps, and simulate a process that always picks the most urgent item next (schedulers, Dijkstra, greedy).

## 1. First principles — why this works

### 1.1 The heap invariant

A binary heap is a complete binary tree stored in an array, where every parent is $\le$ its children (min-heap). Only the root is guaranteed to be the minimum. Siblings and cousins are unordered. That partial order is exactly enough for:

- **push:** append at the end and *sift up* (swap with the parent while smaller). The height is $\lfloor \log_2 n \rfloor$, so this is $O(\log n)$.
- **pop:** move the last element to the root and *sift down* (swap with the smaller child while larger), $O(\log n)$.
- **build from $n$ items:** sift down every internal node from the bottom up, $O(n)$ in total, because $\sum_h \frac{n}{2^{h+1}} \cdot h = O(n)$.

A heap is weaker than a sorted array or a balanced BST (no search, no ordered iteration), and that is why it is cheaper and simpler.

### 1.2 Top $k$: keep the $k$ best, evict the worst of them

To keep the $k$ **largest** of a stream, maintain a **min-heap of size $k$**. Its root is the smallest of the current top $k$, the one that should leave first if something better arrives. Each new element costs $O(\log k)$, so the total is $O(n \log k)$ time and $O(k)$ space. Using a max-heap of everything costs $O(n \log n)$ time and $O(n)$ space. It works but misses the point, and interviewers ask about it.

When the whole array is available and only the $k$-th value is needed, **quickselect** partitions around a pivot and recurses into one side: $O(n)$ expected and $O(n^2)$ worst case, with a random pivot making the bad case unlikely. With a small value range, **bucket/counting sort** gives $O(n)$ deterministically (Top K Frequent).

### 1.3 $k$-way merge: the next output is the minimum of $k$ heads

Merging $k$ sorted lists: the next element of the output is the smallest of the $k$ current heads. A min-heap of the heads gives it in $O(\log k)$, and after popping a head we push its successor. Total: $O(N \log k)$ for $N$ elements. The same shape solves "k-th smallest in a sorted matrix", "smallest range covering $k$ lists", and "k pairs with smallest sums" (the heads are frontier candidates).

### 1.4 Two heaps maintain a split

For the running median keep a **max-heap `low`** (the smaller half) and a **min-heap `high`** (the larger half) with two invariants: every element of `low` $\le$ every element of `high`, and `size(low)` $\in \{\text{size(high)}, \text{size(high)} + 1\}$. The median is `low.top()`, or the average of both tops. An insert pushes into `low`, moves `low`'s top to `high` (which restores the order invariant), and moves one back if `high` became larger (which restores the size invariant). That is $O(\log n)$ per insert and $O(1)$ per query. The same split shows up in "IPO" (available projects in one heap, locked ones in a sorted list) and "sliding window median" (two heaps plus lazy deletion).

## 2. Definitions, formulas and complexities

| Operation | Binary heap | Note |
|---|---|---|
| top | $O(1)$ | |
| push / pop | $O(\log n)$ | |
| build (heapify) | $O(n)$ | `make_heap`, `PriorityQueue(Collection)` |
| delete arbitrary / decrease key | not supported directly | use lazy deletion, or a `set` / `TreeMap` |
| top $k$ of $n$ with a size-$k$ heap | $O(n \log k)$ time, $O(k)$ space | |
| quickselect | $O(n)$ expected | `std::nth_element` |
| heap sort | $O(n \log n)$, in place, not stable | |
| array indices (0-based) | children $2i+1, 2i+2$; parent $\lfloor (i-1)/2 \rfloor$ | |
| task-scheduler lower bound | $\max\big(N,\ (f_{\max} - 1)(n + 1) + c_{\max}\big)$ | $f_{\max}$ = highest frequency, $c_{\max}$ = number of tasks with it |

Library defaults (the classic source of bugs):

| | C++ `priority_queue<T>` | Java `PriorityQueue<T>` |
|---|---|---|
| default order | **max**-heap (uses `less<T>`, top is the largest) | **min**-heap (natural order, head is the smallest) |
| min-heap / max-heap | `priority_queue<T, vector<T>, greater<T>>` | `new PriorityQueue<>(Comparator.reverseOrder())` |
| custom | comparator returns `true` if `a` should be **below** `b` | comparator returns negative if `a` comes **first** |
| iteration order | not sorted | not sorted (`toString` is not sorted either) |

## 3. Reusable templates (C++ and Java)

A from-scratch binary min-heap. Interviewers occasionally ask for it, and writing it once makes sift-up and sift-down automatic.

```cpp
struct MinHeap {
    vector<int> a;
    void push(int x) {
        a.push_back(x);
        for (size_t i = a.size() - 1; i > 0 && a[(i - 1) / 2] > a[i]; i = (i - 1) / 2)
            swap(a[i], a[(i - 1) / 2]);                     // sift up
    }
    int top() const { return a[0]; }
    void pop() {
        a[0] = a.back();
        a.pop_back();
        size_t i = 0, n = a.size();
        while (true) {                                       // sift down to the smaller child
            size_t l = 2 * i + 1, r = l + 1, m = i;
            if (l < n && a[l] < a[m]) m = l;
            if (r < n && a[r] < a[m]) m = r;
            if (m == i) break;
            swap(a[i], a[m]);
            i = m;
        }
    }
    bool empty() const { return a.empty(); }
};

// k-th largest via quickselect (expected O(n)); k is 1-based.
int kthLargestQuickselect(vector<int> a, int k) {
    mt19937 rng(12345);
    int lo = 0, hi = (int)a.size() - 1, target = (int)a.size() - k;   // index in ascending order
    while (true) {
        int p = lo + (int)(rng() % (hi - lo + 1));
        swap(a[p], a[hi]);
        int store = lo;
        for (int i = lo; i < hi; ++i) if (a[i] < a[hi]) swap(a[i], a[store++]);
        swap(a[store], a[hi]);                               // pivot now at its sorted position
        if (store == target) return a[store];
        if (store < target) lo = store + 1; else hi = store - 1;
    }
}
```

```java
static class MinHeap {
    private int[] a = new int[16];
    private int n = 0;
    void push(int x) {
        if (n == a.length) a = Arrays.copyOf(a, 2 * n);
        a[n] = x;
        for (int i = n++; i > 0 && a[(i - 1) / 2] > a[i]; i = (i - 1) / 2) {
            int t = a[i]; a[i] = a[(i - 1) / 2]; a[(i - 1) / 2] = t;
        }
    }
    int top() { return a[0]; }
    void pop() {
        a[0] = a[--n];
        int i = 0;
        while (true) {
            int l = 2 * i + 1, r = l + 1, m = i;
            if (l < n && a[l] < a[m]) m = l;
            if (r < n && a[r] < a[m]) m = r;
            if (m == i) break;
            int t = a[i]; a[i] = a[m]; a[m] = t;
            i = m;
        }
    }
    boolean isEmpty() { return n == 0; }
}

static int kthLargestQuickselect(int[] input, int k) {
    int[] a = input.clone();
    Random rng = new Random(12345);
    int lo = 0, hi = a.length - 1, target = a.length - k;
    while (true) {
        int p = lo + rng.nextInt(hi - lo + 1);
        int t = a[p]; a[p] = a[hi]; a[hi] = t;
        int store = lo;
        for (int i = lo; i < hi; i++) if (a[i] < a[hi]) { t = a[i]; a[i] = a[store]; a[store++] = t; }
        t = a[store]; a[store] = a[hi]; a[hi] = t;
        if (store == target) return a[store];
        if (store < target) lo = store + 1; else hi = store - 1;
    }
}
```

Comparators for pairs and objects, written the way they read in an interview:

```cpp
void comparatorExamples() {
    // min-heap of (distance, node)
    priority_queue<pair<long long, int>, vector<pair<long long, int>>, greater<>> pq;
    pq.push({5, 1});
    // max-heap by frequency, ties broken by smaller value first
    auto cmp = [](const pair<int, int>& a, const pair<int, int>& b) {   // (freq, value)
        if (a.first != b.first) return a.first < b.first;               // true = a sinks below b
        return a.second > b.second;
    };
    priority_queue<pair<int, int>, vector<pair<int, int>>, decltype(cmp)> byFreq(cmp);
    byFreq.push({3, 7});
}
```

```java
static void comparatorExamples() {
    PriorityQueue<long[]> pq = new PriorityQueue<>((a, b) -> Long.compare(a[0], b[0]));   // min by distance
    pq.add(new long[]{5, 1});
    PriorityQueue<int[]> byFreq = new PriorityQueue<>((a, b) ->
        a[0] != b[0] ? Integer.compare(b[0], a[0]) : Integer.compare(a[1], b[1]));         // max freq, then min value
    byFreq.add(new int[]{3, 7});
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "k largest / smallest / closest / most frequent" | size-$k$ heap of the opposite direction, or quickselect, or buckets |
| "k-th largest in a stream", "running top k" | size-$k$ min-heap kept across calls |
| "merge k sorted …", "k-th smallest in sorted rows", "smallest range covering k lists" | $k$-way merge with a heap of heads |
| "median of a stream", "balance two halves" | two heaps |
| "always process the most urgent / cheapest / earliest next" | heap-driven simulation (CPU scheduling, meeting rooms, Dijkstra) |
| "rearrange so equal items are $\ge k$ apart" | greedy: max-heap by remaining count + cooldown queue |
| "maximise profit with capital constraints over time" | sort by unlock condition + max-heap of unlocked options (IPO) |
| "remove / update arbitrary elements" | lazy deletion (mark and skip on pop) or an ordered set |
| "connect sticks / merge files at minimum cost" | Huffman-style: repeatedly combine the two smallest |

## 5. Worked examples

### Example 1 — Kth Largest Element in an Array · Medium

- **Source:** [LC 215 · Kth Largest Element in an Array](https://leetcode.com/problems/kth-largest-element-in-an-array/) — Medium · `G169` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** return the $k$-th largest element (counting duplicates) of an array of $n \le 10^5$ values in $[-10^4, 10^4]$.
- **Thinking from first principles:** sorting is $O(n \log n)$, which is the baseline to state. The $k$ largest elements are a "keep the best $k$" set, so use a min-heap of size $k$ whose root is the weakest member. Every element bigger than the root replaces it. At the end the root is the $k$-th largest. $O(n \log k)$. Quickselect gives $O(n)$ expected, and because of the bounded range, counting sort over 20001 values gives $O(n + 20001)$ deterministically. Offer the heap first because it is the one that works on a stream.

<details><summary>Solution</summary>

Invariant: after processing a prefix, the heap holds the $\min(k, \text{prefix length})$ largest values of that prefix. Time $O(n \log k)$, space $O(k)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int findKthLargest(vector<int>& nums, int k) {
        priority_queue<int, vector<int>, greater<int>> heap;    // min-heap of the k largest so far
        for (int x : nums) {
            if ((int)heap.size() < k) heap.push(x);
            else if (x > heap.top()) { heap.pop(); heap.push(x); }   // evict the weakest member
        }
        return heap.top();
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n, k;
    cin >> n >> k;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << Solution().findKthLargest(a, k) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int findKthLargest(int[] nums, int k) {
        PriorityQueue<Integer> heap = new PriorityQueue<>();
        for (int x : nums) {
            if (heap.size() < k) heap.add(x);
            else if (x > heap.peek()) { heap.poll(); heap.add(x); }
        }
        return heap.peek();
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        System.out.println(new Solution().findKthLargest(a, k));
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
6 2
3 2 1 5 6 4
out:
5
-->
<!-- test
in:
9 4
3 2 3 1 2 4 5 5 6
out:
4
-->
<!-- test
in:
1 1
-7
out:
-7
-->
<!-- test
in:
4 4
2 2 2 2
out:
2
-->

### Example 2 — Top K Frequent Elements · Medium

- **Source:** [LC 347 · Top K Frequent Elements](https://leetcode.com/problems/top-k-frequent-elements/) — Medium · `B75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** return the $k$ most frequent values ($n \le 10^5$). The answer is guaranteed to be unique and may be returned in any order. Required: better than $O(n \log n)$.
- **Thinking from first principles:** count the frequencies with a hash map. Sorting the distinct values by frequency is $O(m \log m)$. A size-$k$ min-heap keyed by frequency gives $O(m \log k)$. To beat both, note that **a frequency is an integer in $[1, n]$**: put each value into bucket `freq`, then read the buckets from high to low until $k$ values are collected. That is $O(n)$ time and space.

<details><summary>Solution</summary>

Bucket sort by frequency. Since the answer is unique, the $k$-th and $(k+1)$-th frequencies differ, so ties inside a bucket never split the answer. The driver sorts the output so it is deterministic.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<int> topKFrequent(vector<int>& nums, int k) {
        unordered_map<int, int> freq;
        for (int x : nums) freq[x]++;
        vector<vector<int>> bucket(nums.size() + 1);         // bucket[f] = values seen f times
        for (auto& [value, f] : freq) bucket[f].push_back(value);
        vector<int> res;
        for (int f = nums.size(); f >= 1 && (int)res.size() < k; --f)
            for (int value : bucket[f]) {
                res.push_back(value);
                if ((int)res.size() == k) break;
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
    vector<int> res = Solution().topKFrequent(a, k);
    sort(res.begin(), res.end());
    for (size_t i = 0; i < res.size(); ++i) cout << res[i] << (i + 1 < res.size() ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int[] topKFrequent(int[] nums, int k) {
        Map<Integer, Integer> freq = new HashMap<>();
        for (int x : nums) freq.merge(x, 1, Integer::sum);
        List<List<Integer>> bucket = new ArrayList<>();
        for (int i = 0; i <= nums.length; i++) bucket.add(new ArrayList<>());
        for (Map.Entry<Integer, Integer> e : freq.entrySet()) bucket.get(e.getValue()).add(e.getKey());
        int[] res = new int[k];
        int idx = 0;
        for (int f = nums.length; f >= 1 && idx < k; f--)
            for (int value : bucket.get(f)) {
                res[idx++] = value;
                if (idx == k) break;
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
        int[] res = new Solution().topKFrequent(a, k);
        Arrays.sort(res);
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
6 2
1 1 1 2 2 3
out:
1 2
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
10 3
4 -1 -1 4 4 9 9 9 9 2
out:
-1 4 9
-->

### Example 3 — Merge k Sorted Lists · Hard

- **Source:** [LC 23 · Merge k Sorted Lists](https://leetcode.com/problems/merge-k-sorted-lists/) — Hard · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Hard (≈ 1500 CF, est.)
- **Problem:** merge $k \le 10^4$ sorted linked lists with $N \le 10^4$ nodes in total into one sorted list.
- **Thinking from first principles:** merging the lists one after another into an accumulator costs $O(kN)$, because the accumulator is re-walked each time. The next output node is always the smallest current head, so keep the heads in a min-heap: pop the minimum, append it, push its successor. $O(N \log k)$. The divide-and-conquer alternative (merge pairs of lists in $\log k$ rounds) has the same complexity and $O(1)$ extra space, which makes it a good follow-up answer.

<details><summary>Solution</summary>

The heap holds at most $k$ nodes, one per non-empty list. In C++ the comparator orders `ListNode*` by value in a min-heap (returns `true` when `a` should sink, i.e. `a->val > b->val`). The driver reads $k$, then each list as `len v1 .. vlen`, and prints the merged list.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct ListNode {
    int val;
    ListNode* next;
    ListNode(int x) : val(x), next(nullptr) {}
};

class Solution {
public:
    ListNode* mergeKLists(vector<ListNode*>& lists) {
        auto cmp = [](ListNode* a, ListNode* b) { return a->val > b->val; };   // min-heap by value
        priority_queue<ListNode*, vector<ListNode*>, decltype(cmp)> heap(cmp);
        for (ListNode* h : lists) if (h) heap.push(h);
        ListNode dummy(0);
        ListNode* tail = &dummy;
        while (!heap.empty()) {
            ListNode* node = heap.top(); heap.pop();
            tail->next = node;
            tail = node;
            if (node->next) heap.push(node->next);      // its successor becomes that list's head
        }
        return dummy.next;
    }
};

int main() {
    int k;
    cin >> k;
    vector<ListNode*> lists(k, nullptr);
    for (int i = 0; i < k; ++i) {
        int len;
        cin >> len;
        ListNode dummy(0);
        ListNode* t = &dummy;
        for (int j = 0; j < len; ++j) { int v; cin >> v; t->next = new ListNode(v); t = t->next; }
        lists[i] = dummy.next;
    }
    string s = "[";
    for (ListNode* h = Solution().mergeKLists(lists); h; h = h->next) s += to_string(h->val) + (h->next ? "," : "");
    cout << s << "]\n";
}
```

```java
import java.util.*;
import java.io.*;

class ListNode {
    int val;
    ListNode next;
    ListNode(int x) { val = x; }
}

class Solution {
    public ListNode mergeKLists(ListNode[] lists) {
        PriorityQueue<ListNode> heap = new PriorityQueue<>((a, b) -> Integer.compare(a.val, b.val));
        for (ListNode h : lists) if (h != null) heap.add(h);
        ListNode dummy = new ListNode(0), tail = dummy;
        while (!heap.isEmpty()) {
            ListNode node = heap.poll();
            tail.next = node;
            tail = node;
            if (node.next != null) heap.add(node.next);
        }
        return dummy.next;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int k = in.nextInt();
        ListNode[] lists = new ListNode[k];
        for (int i = 0; i < k; i++) {
            int len = in.nextInt();
            ListNode dummy = new ListNode(0), t = dummy;
            for (int j = 0; j < len; j++) { t.next = new ListNode(in.nextInt()); t = t.next; }
            lists[i] = dummy.next;
        }
        StringBuilder sb = new StringBuilder("[");
        for (ListNode h = new Solution().mergeKLists(lists); h != null; h = h.next) sb.append(h.val).append(h.next != null ? "," : "");
        System.out.println(sb.append("]"));
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
3 1 4 5
3 1 3 4
2 2 6
out:
[1,1,2,3,4,4,5,6]
-->
<!-- test
in:
0
out:
[]
-->
<!-- test
in:
2
0
1 -5
out:
[-5]
-->

### Example 4 — Find Median from Data Stream · Hard

- **Source:** [LC 295 · Find Median from Data Stream](https://leetcode.com/problems/find-median-from-data-stream/) — Hard · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Hard (≈ 1600 CF, est.)
- **Problem:** support `addNum(x)` and `findMedian()` over up to $5 \cdot 10^4$ operations, values in $[-10^5, 10^5]$.
- **Thinking from first principles:** a sorted array with insertion is $O(n)$ per add. The median only needs the *boundary* between the lower and upper halves, never the full order inside each half. A max-heap exposes the largest of the lower half and a min-heap the smallest of the upper half, and the median is read from those two tops. Keep the halves balanced (the lower half may hold one extra element) and ordered (`low.top() <= high.top()`). The three-step insert in §1.4 maintains both invariants with no case analysis.

<details><summary>Solution</summary>

`add`: push into `low`, move `low.top()` to `high`, and if `high` is now bigger, move its top back. Both invariants hold after each step. `addNum` is $O(\log n)$ and `findMedian` is $O(1)$. The driver reads operations `add x` / `median` and prints the medians with one decimal.

```cpp
#include <bits/stdc++.h>
using namespace std;

class MedianFinder {
    priority_queue<int> low;                                  // max-heap: smaller half
    priority_queue<int, vector<int>, greater<int>> high;      // min-heap: larger half
public:
    void addNum(int num) {
        low.push(num);
        high.push(low.top());                                 // largest of low moves up: order holds
        low.pop();
        if (high.size() > low.size()) {                       // size(low) must be size(high) or +1
            low.push(high.top());
            high.pop();
        }
    }
    double findMedian() {
        if (low.size() > high.size()) return low.top();
        return (low.top() + (double)high.top()) / 2.0;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> q;
    MedianFinder mf;
    cout << fixed << setprecision(1);
    while (q--) {
        string op;
        cin >> op;
        if (op == "add") { int x; cin >> x; mf.addNum(x); }
        else cout << mf.findMedian() << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

class MedianFinder {
    private final PriorityQueue<Integer> low = new PriorityQueue<>(Comparator.reverseOrder());
    private final PriorityQueue<Integer> high = new PriorityQueue<>();
    public void addNum(int num) {
        low.add(num);
        high.add(low.poll());
        if (high.size() > low.size()) low.add(high.poll());
    }
    public double findMedian() {
        if (low.size() > high.size()) return low.peek();
        return (low.peek() + (double) high.peek()) / 2.0;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int q = in.nextInt();
        MedianFinder mf = new MedianFinder();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = in.next();
            if (op.equals("add")) mf.addNum(in.nextInt());
            else sb.append(String.format(Locale.US, "%.1f", mf.findMedian())).append('\n');
        }
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
5
add 1
add 2
median
add 3
median
out:
1.5
2.0
-->
<!-- test
in:
8
add -100000
median
add 100000
median
add 5
add 5
median
median
out:
-100000.0
0.0
5.0
5.0
-->

### Example 5 — Task Scheduler · Medium

- **Source:** [LC 621 · Task Scheduler](https://leetcode.com/problems/task-scheduler/) — Medium · `G75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1600 CF, est.)
- **Problem:** tasks labelled `A`–`Z` ($\le 10^4$), each taking one interval. Two equal tasks must be at least $n$ intervals apart ($0 \le n \le 100$), and idle intervals are allowed. Minimise the total number of intervals.
- **Thinking from first principles:** simulation answer: at every step run the available task with the most remaining copies (max-heap), and park used tasks in a cooldown queue until they are allowed again. That is $O(T \log 26)$ and generalises well. The closed form comes from looking at the most frequent task. If it occurs $f$ times, it needs $f - 1$ gaps of length $n$ between its copies, so there are at least $(f-1)(n+1) + c$ slots, where $c$ is the number of tasks tied at frequency $f$ (they all occupy the last row). If there are more tasks than idle slots, the gaps simply widen and no idle time is needed, so the answer is $\max(T, (f-1)(n+1) + c)$.

<details><summary>Solution</summary>

Proof sketch of achievability: arrange $f$ rows of width $n + 1$, and fill the columns with tasks in decreasing frequency order, column by column. Two copies of a task are then in different rows, separated by at least $n$ slots. If all idle slots fill up, extra tasks extend the rows without breaking the gaps, so the length is $T$. The heap simulation is the other standard answer and is worth knowing for variants that return the schedule. $O(T)$ time, $O(26)$ space.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int leastInterval(vector<char>& tasks, int n) {
        array<int, 26> cnt{};
        for (char t : tasks) cnt[t - 'A']++;
        int f = *max_element(cnt.begin(), cnt.end());
        int c = count(cnt.begin(), cnt.end(), f);             // tasks tied at the top frequency
        return max((int)tasks.size(), (f - 1) * (n + 1) + c);
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string s;
    int n;
    cin >> s >> n;
    vector<char> tasks(s.begin(), s.end());
    cout << Solution().leastInterval(tasks, n) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int leastInterval(char[] tasks, int n) {
        int[] cnt = new int[26];
        for (char t : tasks) cnt[t - 'A']++;
        int f = 0, c = 0;
        for (int x : cnt) f = Math.max(f, x);
        for (int x : cnt) if (x == f) c++;
        return Math.max(tasks.length, (f - 1) * (n + 1) + c);
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        char[] tasks = in.next().toCharArray();
        int n = in.nextInt();
        System.out.println(new Solution().leastInterval(tasks, n));
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
AAABBB 2
out:
8
-->
<!-- test
in:
ACABDB 1
out:
6
-->
<!-- test
in:
AAABBB 3
out:
10
-->
<!-- test
in:
A 100
out:
1
-->
<!-- test
in:
AAAAAABCDEFG 2
out:
16
-->

## 6. Pitfalls and things to remember

1. **Heap direction for top $k$:** the $k$ *largest* need a *min*-heap (evict the smallest), and vice versa. Saying this out loud prevents the most common bug.
2. **C++ comparators are inverted:** `priority_queue` puts the element that is "largest" under the comparator on top. For a min-heap by value the lambda returns `a->val > b->val`.
3. **Java comparator overflow:** `(a, b) -> a - b` overflows for large or negative values. Use `Integer.compare` / `Long.compare`.
4. **`PriorityQueue` iteration is not sorted.** Printing or iterating the heap does not give sorted order. Poll repeatedly instead.
5. **Lazy deletion** for "remove arbitrary element": keep a `toDelete` count map and discard tops that are marked. Sizes must then be tracked separately.
6. **Average of two ints:** `(a + b) / 2.0` can overflow in `int` before the conversion. Cast one side to `double` or `long` first, as in Example 4.
7. **Ties:** problems like Top K Frequent Words need a secondary key (lexicographic order). Make the comparator total, or the output order becomes implementation-defined.
8. **`std::nth_element` vs sort:** `nth_element` is $O(n)$ expected and leaves the array partially ordered. Say that it mutates the input.
9. **Heap of pairs in Java:** `int[]` / `long[]` entries avoid boxing. Records (Java 16+) are clearer but box their fields when they are `Integer`.
10. **Quickselect worst case** is $O(n^2)$ on adversarial or all-equal input with a naive partition. Use random pivots and a three-way partition for many duplicates.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| Kth largest → "the data is a stream" | keep the size-$k$ min-heap across calls ([LC 703 · Kth Largest Element in a Stream](https://leetcode.com/problems/kth-largest-element-in-a-stream/) — Easy) |
| → "can you do $O(n)$?" | quickselect (expected), introselect / median of medians (worst case), counting sort for small ranges |
| Top K Frequent → "billions of items, limited memory" | count-min sketch + heap of candidates (approximate), or partition by hash across machines and merge per-machine top $k$ |
| Merge k lists → "without extra memory" | pairwise divide and conquer: $\log k$ rounds of linear merges |
| Median → "most numbers are in [0, 100]" | counting array for that range plus overflow counters on each side; $O(100)$ per query |
| Median → "sliding window of size $w$" | two heaps with lazy deletion, or two multisets: $O(n \log w)$ ([LC 480 · Sliding Window Median](https://leetcode.com/problems/sliding-window-median/) — Hard) |
| Task Scheduler → "output the schedule" | heap simulation with a cooldown queue keyed by the next allowed time |
| "Why not a balanced BST?" | it supports everything a heap does plus deletion and order statistics, at a higher constant; use it when arbitrary removal is needed |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium. Network delay / Dijkstra problems are in [advanced graphs](12-advanced-graphs.md), meeting-room heaps in [greedy and intervals](15-greedy-and-intervals.md).

**Easy** (2)

- [ ] [LC 703 · Kth Largest Element in a Stream](https://leetcode.com/problems/kth-largest-element-in-a-stream/) — Easy · `NC150`
- [ ] [LC 1046 · Last Stone Weight](https://leetcode.com/problems/last-stone-weight/) — Easy · `NC150`

**Medium** (9)

- [ ] [LC 215 · Kth Largest Element in an Array](https://leetcode.com/problems/kth-largest-element-in-an-array/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 347 · Top K Frequent Elements](https://leetcode.com/problems/top-k-frequent-elements/) — Medium · `B75` `NC150`
- [ ] [LC 373 · Find K Pairs with Smallest Sums](https://leetcode.com/problems/find-k-pairs-with-smallest-sums/) — Medium · `TI150`
- [ ] [LC 621 · Task Scheduler](https://leetcode.com/problems/task-scheduler/) — Medium · `G75` `NC150`
- [ ] [LC 692 · Top K Frequent Words](https://leetcode.com/problems/top-k-frequent-words/) — Medium · `G169`
- [ ] [LC 767 · Reorganize String](https://leetcode.com/problems/reorganize-string/) — Medium · `NC250`
- [ ] [LC 973 · K Closest Points to Origin](https://leetcode.com/problems/k-closest-points-to-origin/) — Medium · `G75` `NC150`
- [ ] [LC 1405 · Longest Happy String](https://leetcode.com/problems/longest-happy-string/) — Medium · `NC250`
- [ ] [LC 1834 · Single-Threaded CPU](https://leetcode.com/problems/single-threaded-cpu/) — Medium · `NC250`

**Hard** (4)

- [ ] [LC 23 · Merge k Sorted Lists](https://leetcode.com/problems/merge-k-sorted-lists/) — Hard · `G75` `B75` `NC150` `TI150`
- [ ] [LC 295 · Find Median from Data Stream](https://leetcode.com/problems/find-median-from-data-stream/) — Hard · `G75` `B75` `NC150` `TI150`
- [ ] [LC 502 · IPO](https://leetcode.com/problems/ipo/) — Hard · `NC250` `TI150`
- [ ] [LC 632 · Smallest Range Covering Elements from K Lists](https://leetcode.com/problems/smallest-range-covering-elements-from-k-lists/) — Hard · `G169`

**Beyond the lists:**

- [ ] [LC 378 · Kth Smallest Element in a Sorted Matrix](https://leetcode.com/problems/kth-smallest-element-in-a-sorted-matrix/) — Medium — $k$-way merge over rows
- [ ] [LC 1642 · Furthest Building You Can Reach](https://leetcode.com/problems/furthest-building-you-can-reach/) — Medium — min-heap of ladder uses
- [ ] [LC 1353 · Maximum Number of Events That Can Be Attended](https://leetcode.com/problems/maximum-number-of-events-that-can-be-attended/) — Medium — sweep days, heap of end days
- [ ] [LC 2542 · Maximum Subsequence Score](https://leetcode.com/problems/maximum-subsequence-score/) — Medium — sort by one key, size-$k$ heap on the other
- [ ] [LC 2462 · Total Cost to Hire K Workers](https://leetcode.com/problems/total-cost-to-hire-k-workers/) — Medium — two heaps on both ends
- [ ] [LC 1167 · Minimum Cost to Connect Sticks](https://leetcode.com/problems/minimum-cost-to-connect-sticks/) — Medium 🔒 — Huffman merging
- [ ] [LC 871 · Minimum Number of Refueling Stops](https://leetcode.com/problems/minimum-number-of-refueling-stops/) — Hard — greedy with regret (max-heap of passed stations)
- [ ] [LC 857 · Minimum Cost to Hire K Workers](https://leetcode.com/problems/minimum-cost-to-hire-k-workers/) — Hard — sort by ratio, max-heap of qualities
- [ ] [LC 480 · Sliding Window Median](https://leetcode.com/problems/sliding-window-median/) — Hard — two heaps + lazy deletion

## 9. CP counterpart

- [Ordered sets, PBDS and heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md): `priority_queue`, `multiset` as a deletable heap, order-statistics trees.
- [Greedy with heaps and regret](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md): the CP generalisation of "furthest building" and "refuelling stops", where you take greedily and undo the worst choice when a constraint breaks.
- [Shortest paths](../09-Graphs/02-shortest-paths.md): Dijkstra is a heap-driven simulation.

What transfers: everything, especially heap + sort combinations. Interview-specific: be explicit about heap direction and comparator semantics, because interviewers watch for that.

## 10. Self-check

1. Why does "k largest" use a min-heap, and what is the complexity?
2. Prove that building a heap bottom-up is $O(n)$.
3. State the two invariants of the two-heaps median and the three-step insert.
4. Why does the $k$-way merge cost $O(N \log k)$ rather than $O(N \log N)$?
5. Write a C++ min-heap of `ListNode*` by value and the equivalent Java `PriorityQueue`.
6. Derive the Task Scheduler formula and explain when the answer is just the number of tasks.
7. When is quickselect worse than a heap, and how do you protect against its worst case?

<details><summary>Answers</summary>

1. The heap must expose the weakest of the current top $k$ so it can be evicted. $O(n \log k)$ time, $O(k)$ space.
2. Sifting down from height $h$ costs $O(h)$, and at most $\lceil n / 2^{h+1} \rceil$ nodes have height $h$, so the total is $\sum_h h \cdot n/2^{h+1} = O(n)$ because $\sum h/2^h$ converges.
3. Every element of `low` (max-heap) is $\le$ every element of `high` (min-heap), and `size(low)` is `size(high)` or one more. Insert: push into `low`, move `low.top()` to `high`, and if `high` is larger, move `high.top()` back.
4. The heap never holds more than $k$ elements (one head per list), so each of the $N$ push/pop pairs costs $O(\log k)$.
5. C++: `auto cmp = [](ListNode* a, ListNode* b){ return a->val > b->val; }; priority_queue<ListNode*, vector<ListNode*>, decltype(cmp)> pq(cmp);`. Java: `new PriorityQueue<ListNode>((a, b) -> Integer.compare(a.val, b.val))`.
6. The most frequent task (count $f$) needs $f - 1$ full gaps of $n + 1$ slots, plus one final slot per task tied at $f$: $(f-1)(n+1) + c$. When the other tasks more than fill the idle slots, no idle time is needed and the answer is $T$. Hence $\max(T, \dots)$.
7. On streams (it needs the whole array), when the input must not be modified, or on adversarial / all-equal input with a deterministic pivot ($O(n^2)$). Use a random pivot and three-way partitioning.

</details>
