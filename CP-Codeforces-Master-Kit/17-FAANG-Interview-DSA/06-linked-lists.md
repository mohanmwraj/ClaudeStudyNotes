# Linked Lists

> **Band:** 🟢 ≤ 1400 · **Priority:** 🔥 (interviews) / 🧊 (CP) · **FAANG:** high · **Prerequisites:** [interview framework](01-interview-framework-and-communication.md), [two pointers](03-two-pointers-and-sliding-window.md)
> **You can say you know this when:** you can reverse a list, a sub-list and k-groups without drawing more than once, find the middle and the cycle entry with fast/slow pointers *and prove why they work*, and you always reach for a dummy head when the head may change.

Linked lists almost never appear in Codeforces, because arrays are faster. They are an interview staple because they test **pointer discipline**: saving `next` before overwriting it, handling the empty and one-node cases, and never losing the rest of the list. A handful of patterns cover nearly every question: dummy head, reversal, fast/slow pointers, merge, and splice.

## 1. First principles — why this works

### 1.1 A list is a chain of `next` pointers, and you can only walk forward

There is no random access, so "go to the middle" or "go to the $k$-th from the end" must be replaced by **relative motion**: two pointers that move at different speeds or start with a gap. Every pattern below exists to get positional information in one pass with $O(1)$ extra memory.

### 1.2 Reversal: three pointers and one invariant

Invariant while reversing: `prev` is the head of the already-reversed prefix, and `cur` is the head of the untouched suffix. One step moves one node from the suffix to the front of the prefix. Save `next = cur->next` first, because the next line overwrites it. When `cur` is null, `prev` is the new head. The recursive version expresses the same thing: reverse the rest, then hang the current node at its end (`head->next->next = head`). It uses $O(n)$ stack.

### 1.3 Fast and slow pointers

- **Middle:** if `fast` moves 2 steps for every 1 step of `slow`, then when `fast` reaches the end, `slow` has covered half the distance.
- **$k$-th from the end:** start `fast` $k$ nodes ahead. When `fast` hits the end, `slow` is $k$ behind it.
- **Cycle detection (Floyd):** in a cycle of length $\lambda$, the gap between `fast` and `slow` decreases by 1 per step once both are inside, so they meet within $\lambda$ steps. Without a cycle `fast` reaches null.
- **Cycle entry:** let the tail (non-cycle prefix) have length $\mu$. At the meeting, `slow` has walked $k$ steps and `fast` $2k$, so $2k - k = k$ is a multiple of $\lambda$. Walking $\mu$ more steps from the meeting point puts a pointer at position $k + \mu \equiv \mu \pmod{\lambda}$ inside the cycle, which is the entry. A second pointer started at the head reaches the entry after exactly $\mu$ steps. So start one pointer at the head, keep one at the meeting point, and move both one step at a time. They meet at the entry.

The same argument works on any **functional graph** $i \to f(i)$, which is how Find the Duplicate Number (Example 4) becomes a cycle-entry problem.

### 1.4 The dummy head removes special cases

Any operation that may delete or replace the head (remove the $n$-th from the end when $n$ is the length, merge, partition, reverse in groups) is simpler if you prepend a sentinel `dummy` whose `next` is the head. Every real node then has a predecessor, and the answer is `dummy.next`.

## 2. Definitions, invariants and complexities

| Operation | Pointers | Invariant | Time / space |
|---|---|---|---|
| reverse whole list | `prev`, `cur`, `next` | `prev` = reversed prefix, `cur` = rest | $O(n)$ / $O(1)$ |
| reverse sub-list $[m, n]$ | node before $m$, then head-insertion | the sublist is rebuilt by moving each next node to its front | $O(n)$ / $O(1)$ |
| middle | `slow += 1`, `fast += 2` | `fast` is twice as far as `slow` | $O(n)$ / $O(1)$ |
| $k$-th from end | gap of $k$ | `fast` − `slow` $= k$ | $O(n)$ / $O(1)$ |
| cycle detect / entry | Floyd | $k \equiv 0 \pmod \lambda$; entry after $\mu$ more steps | $O(\mu + \lambda)$ / $O(1)$ |
| merge two sorted | `dummy`, `tail` | `dummy..tail` is sorted and holds the smallest taken elements | $O(n + m)$ / $O(1)$ |
| sort list | merge sort | bottom-up merges of runs of size $1, 2, 4, \dots$ | $O(n \log n)$ / $O(1)$ (bottom-up) |
| intersection of two lists | switch heads at the end | both pointers walk $a + b$ steps | $O(a + b)$ / $O(1)$ |

## 3. Reusable templates (C++ and Java)

Merge two sorted lists, find the middle, detect a cycle and find its entry ([LC 21 · Merge Two Sorted Lists](https://leetcode.com/problems/merge-two-sorted-lists/) — Easy, [LC 876 · Middle of the Linked List](https://leetcode.com/problems/middle-of-the-linked-list/) — Easy, [LC 141 · Linked List Cycle](https://leetcode.com/problems/linked-list-cycle/) — Easy, [LC 142 · Linked List Cycle II](https://leetcode.com/problems/linked-list-cycle-ii/) — Medium):

```cpp
struct ListNode {
    int val;
    ListNode* next;
    ListNode(int x) : val(x), next(nullptr) {}
};

ListNode* mergeTwoLists(ListNode* a, ListNode* b) {
    ListNode dummy(0);
    ListNode* tail = &dummy;
    while (a && b) {
        ListNode*& smaller = (a->val <= b->val) ? a : b;   // <= keeps the merge stable
        tail->next = smaller;
        tail = smaller;
        smaller = smaller->next;
    }
    tail->next = a ? a : b;                                // append the leftover run
    return dummy.next;
}

ListNode* middleNode(ListNode* head) {      // second middle for even length (LC 876)
    ListNode *slow = head, *fast = head;
    while (fast && fast->next) { slow = slow->next; fast = fast->next->next; }
    return slow;
}

ListNode* detectCycle(ListNode* head) {     // entry node, or nullptr if acyclic
    ListNode *slow = head, *fast = head;
    while (fast && fast->next) {
        slow = slow->next;
        fast = fast->next->next;
        if (slow == fast) {                 // inside the cycle: k is a multiple of its length
            ListNode* p = head;
            while (p != slow) { p = p->next; slow = slow->next; }
            return p;
        }
    }
    return nullptr;
}
```

```java
static class ListNode {
    int val;
    ListNode next;
    ListNode(int x) { val = x; }
}

static ListNode mergeTwoLists(ListNode a, ListNode b) {
    ListNode dummy = new ListNode(0), tail = dummy;
    while (a != null && b != null) {
        if (a.val <= b.val) { tail.next = a; a = a.next; }
        else { tail.next = b; b = b.next; }
        tail = tail.next;
    }
    tail.next = (a != null) ? a : b;
    return dummy.next;
}

static ListNode middleNode(ListNode head) {
    ListNode slow = head, fast = head;
    while (fast != null && fast.next != null) { slow = slow.next; fast = fast.next.next; }
    return slow;
}

static ListNode detectCycle(ListNode head) {
    ListNode slow = head, fast = head;
    while (fast != null && fast.next != null) {
        slow = slow.next;
        fast = fast.next.next;
        if (slow == fast) {
            ListNode p = head;
            while (p != slow) { p = p.next; slow = slow.next; }
            return p;
        }
    }
    return null;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "the head may be removed / replaced" | dummy node |
| "reverse", "reorder", "palindrome list", "twin sum" | reversal (whole list, second half, or sub-list) |
| "middle", "split in half", "k-th from end", "in one pass" | fast/slow or gap pointers |
| "cycle", "loop", "where does it start", array of values in $[1, n]$ with one repeat | Floyd on the list or on the functional graph $i \to a_i$ |
| "merge sorted lists", "sort a list in $O(n \log n)$" | merge with dummy + tail; merge sort |
| "merge $k$ sorted lists" | min-heap of heads ([file 09](09-heaps-and-top-k.md)) or pairwise merging |
| "copy with random pointers" | hash map old → new, or interleave copies ($O(1)$ extra) |
| "O(1) get/put with eviction order" | hash map + doubly linked list ([LRU cache](17-design-problems.md)) |
| digits stored in a list, "add two numbers" | simulate carry with a dummy head; reverse first if digits are most-significant-first |

## 5. Worked examples

All drivers read `n` then `n` values, build the list, and print it in LeetCode's `[a,b,c]` format (`[]` for an empty list).

### Example 1 — Reverse Linked List · Easy

- **Source:** [LC 206 · Reverse Linked List](https://leetcode.com/problems/reverse-linked-list/) — Easy · `G75` `B75` `NC150`
- **Difficulty:** LeetCode Easy (≈ 800 CF, est.)
- **Problem:** reverse a singly linked list of up to 5000 nodes, iteratively and recursively.
- **Thinking from first principles:** copying values into an array and writing them back works, but it is $O(n)$ extra and dodges the point. Re-point each `next` backwards: with the invariant from §1.2 the loop writes itself. For the recursive version, trust the recursion to reverse `head->next ...`. Afterwards the old second node is the tail of the reversed rest, so attach `head` after it and cut `head->next`.

<details><summary>Solution</summary>

Iterative: $O(n)$ time, $O(1)$ space. Recursive: $O(n)$ time, $O(n)$ stack, about 5000 frames here, which is fine (a $10^6$-node list would overflow a default stack). The driver reverses iteratively, prints, then reverses back recursively and prints again, which tests both.

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
    ListNode* reverseList(ListNode* head) {
        ListNode* prev = nullptr;                 // reversed prefix
        while (head) {
            ListNode* next = head->next;          // save before overwriting
            head->next = prev;
            prev = head;
            head = next;
        }
        return prev;
    }
    ListNode* reverseListRecursive(ListNode* head) {
        if (!head || !head->next) return head;
        ListNode* newHead = reverseListRecursive(head->next);
        head->next->next = head;                  // old second node now points back to head
        head->next = nullptr;
        return newHead;
    }
};

ListNode* build(const vector<int>& v) {
    ListNode dummy(0);
    ListNode* t = &dummy;
    for (int x : v) { t->next = new ListNode(x); t = t->next; }
    return dummy.next;
}

string show(ListNode* h) {
    string s = "[";
    for (; h; h = h->next) s += to_string(h->val) + (h->next ? "," : "");
    return s + "]";
}

int main() {
    int n;
    cin >> n;
    vector<int> v(n);
    for (int& x : v) cin >> x;
    Solution sol;
    ListNode* r = sol.reverseList(build(v));
    cout << show(r) << '\n';
    cout << show(sol.reverseListRecursive(r)) << '\n';
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
    public ListNode reverseList(ListNode head) {
        ListNode prev = null;
        while (head != null) {
            ListNode next = head.next;
            head.next = prev;
            prev = head;
            head = next;
        }
        return prev;
    }
    public ListNode reverseListRecursive(ListNode head) {
        if (head == null || head.next == null) return head;
        ListNode newHead = reverseListRecursive(head.next);
        head.next.next = head;
        head.next = null;
        return newHead;
    }
}

public class Main {
    static ListNode build(int[] v) {
        ListNode dummy = new ListNode(0), t = dummy;
        for (int x : v) { t.next = new ListNode(x); t = t.next; }
        return dummy.next;
    }
    static String show(ListNode h) {
        StringBuilder sb = new StringBuilder("[");
        for (; h != null; h = h.next) sb.append(h.val).append(h.next != null ? "," : "");
        return sb.append("]").toString();
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] v = new int[n];
        for (int i = 0; i < n; i++) v[i] = in.nextInt();
        Solution sol = new Solution();
        ListNode r = sol.reverseList(build(v));
        System.out.println(show(r));
        System.out.println(show(sol.reverseListRecursive(r)));
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
out:
[5,4,3,2,1]
[1,2,3,4,5]
-->
<!-- test
in:
0
out:
[]
[]
-->
<!-- test
in:
1
7
out:
[7]
[7]
-->

### Example 2 — Remove Nth Node From End of List · Medium

- **Source:** [LC 19 · Remove Nth Node From End of List](https://leetcode.com/problems/remove-nth-node-from-end-of-list/) — Medium · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1100 CF, est.)
- **Problem:** remove the $n$-th node from the end ($1 \le n \le$ length $\le 30$) in one pass.
- **Thinking from first principles:** two passes (count the length $L$, then delete node $L - n$) is correct and a fine first answer. One pass: deleting a node requires its **predecessor**, so we want a pointer $n + 1$ nodes behind the end. Start both pointers at a dummy node, advance `fast` by $n$, then move both until `fast` is on the last node. `slow` is then right before the target. The dummy handles $n = L$ (removing the head) with no special case.

<details><summary>Solution</summary>

After the first loop, `fast` is $n$ nodes ahead of `slow`. When `fast->next == nullptr`, `fast` is the last node, so `slow` is $n$ nodes before it, which is the predecessor of the $n$-th from the end. Time $O(L)$, space $O(1)$.

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
    ListNode* removeNthFromEnd(ListNode* head, int n) {
        ListNode dummy(0);
        dummy.next = head;
        ListNode *fast = &dummy, *slow = &dummy;
        for (int i = 0; i < n; ++i) fast = fast->next;        // gap of n nodes
        while (fast->next) { fast = fast->next; slow = slow->next; }
        ListNode* victim = slow->next;                        // slow is the predecessor
        slow->next = victim->next;
        delete victim;                                        // nodes were allocated with new
        return dummy.next;
    }
};

ListNode* build(const vector<int>& v) {
    ListNode dummy(0);
    ListNode* t = &dummy;
    for (int x : v) { t->next = new ListNode(x); t = t->next; }
    return dummy.next;
}

string show(ListNode* h) {
    string s = "[";
    for (; h; h = h->next) s += to_string(h->val) + (h->next ? "," : "");
    return s + "]";
}

int main() {
    int len, n;
    cin >> len >> n;
    vector<int> v(len);
    for (int& x : v) cin >> x;
    cout << show(Solution().removeNthFromEnd(build(v), n)) << '\n';
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
    public ListNode removeNthFromEnd(ListNode head, int n) {
        ListNode dummy = new ListNode(0);
        dummy.next = head;
        ListNode fast = dummy, slow = dummy;
        for (int i = 0; i < n; i++) fast = fast.next;
        while (fast.next != null) { fast = fast.next; slow = slow.next; }
        slow.next = slow.next.next;
        return dummy.next;
    }
}

public class Main {
    static ListNode build(int[] v) {
        ListNode dummy = new ListNode(0), t = dummy;
        for (int x : v) { t.next = new ListNode(x); t = t.next; }
        return dummy.next;
    }
    static String show(ListNode h) {
        StringBuilder sb = new StringBuilder("[");
        for (; h != null; h = h.next) sb.append(h.val).append(h.next != null ? "," : "");
        return sb.append("]").toString();
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int len = in.nextInt(), n = in.nextInt();
        int[] v = new int[len];
        for (int i = 0; i < len; i++) v[i] = in.nextInt();
        System.out.println(show(new Solution().removeNthFromEnd(build(v), n)));
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
5 2
1 2 3 4 5
out:
[1,2,3,5]
-->
<!-- test
in:
1 1
1
out:
[]
-->
<!-- test
in:
2 2
1 2
out:
[2]
-->
<!-- test
in:
2 1
1 2
out:
[1]
-->

### Example 3 — Reorder List · Medium

- **Source:** [LC 143 · Reorder List](https://leetcode.com/problems/reorder-list/) — Medium · `G169` `B75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** rearrange $L_0, L_1, \dots, L_{n-1}$ into $L_0, L_{n-1}, L_1, L_{n-2}, \dots$ in place, by relinking nodes. $n \le 5 \cdot 10^4$.
- **Thinking from first principles:** with an array of node pointers this is two pointers from both ends: $O(n)$ extra space. To do it in $O(1)$, note that the result interleaves the first half with the **reversed** second half. That decomposes into three templates: find the middle, reverse the second half, merge alternately. Pick the middle so that the first half has $\lceil n/2 \rceil$ nodes. Then the second half is never longer, and the interleave loop can run "while the second half has nodes".

<details><summary>Solution</summary>

`while (fast->next && fast->next->next)` stops `slow` at the last node of the first half (node $\lceil n/2 \rceil - 1$). Cut there, reverse the rest, then splice one node from each half at a time. Time $O(n)$, space $O(1)$.

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
    void reorderList(ListNode* head) {
        if (!head || !head->next) return;
        ListNode *slow = head, *fast = head;                  // 1. end of the first half
        while (fast->next && fast->next->next) { slow = slow->next; fast = fast->next->next; }
        ListNode* second = slow->next;                        // 2. cut and reverse the second half
        slow->next = nullptr;
        ListNode* prev = nullptr;
        while (second) { ListNode* nx = second->next; second->next = prev; prev = second; second = nx; }
        ListNode* first = head;                               // 3. interleave
        second = prev;
        while (second) {
            ListNode* n1 = first->next;
            ListNode* n2 = second->next;
            first->next = second;
            second->next = n1;
            first = n1;
            second = n2;
        }
    }
};

ListNode* build(const vector<int>& v) {
    ListNode dummy(0);
    ListNode* t = &dummy;
    for (int x : v) { t->next = new ListNode(x); t = t->next; }
    return dummy.next;
}

string show(ListNode* h) {
    string s = "[";
    for (; h; h = h->next) s += to_string(h->val) + (h->next ? "," : "");
    return s + "]";
}

int main() {
    int n;
    cin >> n;
    vector<int> v(n);
    for (int& x : v) cin >> x;
    ListNode* head = build(v);
    Solution().reorderList(head);
    cout << show(head) << '\n';
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
    public void reorderList(ListNode head) {
        if (head == null || head.next == null) return;
        ListNode slow = head, fast = head;
        while (fast.next != null && fast.next.next != null) { slow = slow.next; fast = fast.next.next; }
        ListNode second = slow.next, prev = null;
        slow.next = null;
        while (second != null) { ListNode nx = second.next; second.next = prev; prev = second; second = nx; }
        ListNode first = head;
        second = prev;
        while (second != null) {
            ListNode n1 = first.next, n2 = second.next;
            first.next = second;
            second.next = n1;
            first = n1;
            second = n2;
        }
    }
}

public class Main {
    static ListNode build(int[] v) {
        ListNode dummy = new ListNode(0), t = dummy;
        for (int x : v) { t.next = new ListNode(x); t = t.next; }
        return dummy.next;
    }
    static String show(ListNode h) {
        StringBuilder sb = new StringBuilder("[");
        for (; h != null; h = h.next) sb.append(h.val).append(h.next != null ? "," : "");
        return sb.append("]").toString();
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] v = new int[n];
        for (int i = 0; i < n; i++) v[i] = in.nextInt();
        ListNode head = build(v);
        new Solution().reorderList(head);
        System.out.println(show(head));
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
[1,4,2,3]
-->
<!-- test
in:
5
1 2 3 4 5
out:
[1,5,2,4,3]
-->
<!-- test
in:
1
9
out:
[9]
-->
<!-- test
in:
2
1 2
out:
[1,2]
-->

### Example 4 — Find the Duplicate Number · Medium

- **Source:** [LC 287 · Find the Duplicate Number](https://leetcode.com/problems/find-the-duplicate-number/) — Medium · `G169` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1700 CF, est.)
- **Problem:** an array of $n + 1$ integers in $[1, n]$ contains exactly one value that repeats (possibly many times). Find it **without modifying the array** and with $O(1)$ extra space. $n \le 10^5$.
- **Thinking from first principles:** sort (modifies), hash set ($O(n)$ space) and marking negatives (modifies) all break a constraint. Binary search on the value with a counting predicate ("more than $v$ elements are $\le v$") works in $O(n \log n)$. For $O(n)$: view the array as a function $f(i) = a_i$ on indices $0..n$. Every value is in $[1, n]$, so nothing maps to 0 and the walk $0 \to a_0 \to a_{a_0} \to \dots$ never returns to 0: it is a tail entering a cycle. The cycle's entry node has two predecessors (one on the tail, one on the cycle), meaning two indices hold the same value. The entry *is* the duplicate. That is exactly Floyd's cycle-entry problem from §1.3.

<details><summary>Solution</summary>

Phase 1 finds a meeting point inside the cycle. Phase 2 walks one pointer from index 0 and one from the meeting point, one step each, and they meet at the entry. Time $O(n)$, space $O(1)$, and the array is read-only.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int findDuplicate(vector<int>& nums) {
        int slow = 0, fast = 0;
        do {                                        // phase 1: meet inside the cycle
            slow = nums[slow];
            fast = nums[nums[fast]];
        } while (slow != fast);
        int p = 0;                                  // phase 2: tail length mu from both sides
        while (p != slow) { p = nums[p]; slow = nums[slow]; }
        return p;                                   // the node with two incoming edges
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int m;
    cin >> m;                                       // m = n + 1 values
    vector<int> a(m);
    for (int& x : a) cin >> x;
    cout << Solution().findDuplicate(a) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int findDuplicate(int[] nums) {
        int slow = 0, fast = 0;
        do {
            slow = nums[slow];
            fast = nums[nums[fast]];
        } while (slow != fast);
        int p = 0;
        while (p != slow) { p = nums[p]; slow = nums[slow]; }
        return p;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int m = in.nextInt();
        int[] a = new int[m];
        for (int i = 0; i < m; i++) a[i] = in.nextInt();
        System.out.println(new Solution().findDuplicate(a));
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
1 3 4 2 2
out:
2
-->
<!-- test
in:
5
3 1 3 4 2
out:
3
-->
<!-- test
in:
5
3 3 3 3 3
out:
3
-->
<!-- test
in:
2
1 1
out:
1
-->

### Example 5 — Reverse Nodes in k-Group · Hard

- **Source:** [LC 25 · Reverse Nodes in k-Group](https://leetcode.com/problems/reverse-nodes-in-k-group/) — Hard · `G169` `NC150` `TI150`
- **Difficulty:** LeetCode Hard (≈ 1600 CF, est.)
- **Problem:** reverse the nodes of the list $k$ at a time ($1 \le k \le n \le 5000$). A final group with fewer than $k$ nodes stays as it is. Use $O(1)$ extra memory.
- **Thinking from first principles:** this is "reverse a sub-list" repeated. For each group we need four handles: the node before the group (`groupPrev`), the group's first and $k$-th nodes, and the node after the group (`groupNext`). Before reversing, check that $k$ nodes exist. Reverse the group with the standard loop, but start `prev` at `groupNext` so the reversed group's tail already points onward. Then hook `groupPrev->next` to the old $k$-th node and move `groupPrev` to the old first node, which is now the group's tail. A dummy head makes the first group identical to every other.

<details><summary>Solution</summary>

Each node is visited twice (once by the $k$-step probe, once by the reversal): $O(n)$ time, $O(1)$ space. The recursive formulation is shorter but uses $O(n/k)$ stack.

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
    ListNode* reverseKGroup(ListNode* head, int k) {
        ListNode dummy(0);
        dummy.next = head;
        ListNode* groupPrev = &dummy;
        while (true) {
            ListNode* kth = groupPrev;
            for (int i = 0; i < k && kth; ++i) kth = kth->next;
            if (!kth) break;                                   // fewer than k nodes left
            ListNode* groupNext = kth->next;
            ListNode *prev = groupNext, *cur = groupPrev->next;  // reversed group will point to groupNext
            while (cur != groupNext) { ListNode* nx = cur->next; cur->next = prev; prev = cur; cur = nx; }
            ListNode* oldFirst = groupPrev->next;              // becomes the tail of this group
            groupPrev->next = kth;
            groupPrev = oldFirst;
        }
        return dummy.next;
    }
};

ListNode* build(const vector<int>& v) {
    ListNode dummy(0);
    ListNode* t = &dummy;
    for (int x : v) { t->next = new ListNode(x); t = t->next; }
    return dummy.next;
}

string show(ListNode* h) {
    string s = "[";
    for (; h; h = h->next) s += to_string(h->val) + (h->next ? "," : "");
    return s + "]";
}

int main() {
    int n, k;
    cin >> n >> k;
    vector<int> v(n);
    for (int& x : v) cin >> x;
    cout << show(Solution().reverseKGroup(build(v), k)) << '\n';
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
    public ListNode reverseKGroup(ListNode head, int k) {
        ListNode dummy = new ListNode(0);
        dummy.next = head;
        ListNode groupPrev = dummy;
        while (true) {
            ListNode kth = groupPrev;
            for (int i = 0; i < k && kth != null; i++) kth = kth.next;
            if (kth == null) break;
            ListNode groupNext = kth.next, prev = groupNext, cur = groupPrev.next;
            while (cur != groupNext) { ListNode nx = cur.next; cur.next = prev; prev = cur; cur = nx; }
            ListNode oldFirst = groupPrev.next;
            groupPrev.next = kth;
            groupPrev = oldFirst;
        }
        return dummy.next;
    }
}

public class Main {
    static ListNode build(int[] v) {
        ListNode dummy = new ListNode(0), t = dummy;
        for (int x : v) { t.next = new ListNode(x); t = t.next; }
        return dummy.next;
    }
    static String show(ListNode h) {
        StringBuilder sb = new StringBuilder("[");
        for (; h != null; h = h.next) sb.append(h.val).append(h.next != null ? "," : "");
        return sb.append("]").toString();
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt();
        int[] v = new int[n];
        for (int i = 0; i < n; i++) v[i] = in.nextInt();
        System.out.println(show(new Solution().reverseKGroup(build(v), k)));
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
5 2
1 2 3 4 5
out:
[2,1,4,3,5]
-->
<!-- test
in:
5 3
1 2 3 4 5
out:
[3,2,1,4,5]
-->
<!-- test
in:
4 1
1 2 3 4
out:
[1,2,3,4]
-->
<!-- test
in:
6 6
1 2 3 4 5 6
out:
[6,5,4,3,2,1]
-->

## 6. Pitfalls and things to remember

1. **Save `next` before you overwrite it.** Almost every linked-list bug is a lost suffix.
2. **Null-check order:** `while (fast && fast->next)` is safe, `while (fast->next && fast)` is not. Short-circuit evaluation goes left to right.
3. **Which middle?** `while (fast && fast->next)` gives the *second* middle for even lengths (LC 876). `while (fast->next && fast->next->next)` stops at the *first* middle, which is what splitting into halves needs.
4. **Cut the list when splitting** (`slow->next = nullptr`). Otherwise the halves still share nodes and you create a cycle or loop forever when printing.
5. **Dummy nodes in C++:** a stack-allocated `ListNode dummy(0)` is fine, but return `dummy.next`, never `&dummy`.
6. **Memory in C++:** LeetCode does not require `delete`, and deleting nodes the caller still references is undefined behaviour. In production code ask who owns the nodes. Smart pointers are rarely used for lists in interviews.
7. **Recursion depth:** recursive reversal or recursive merge on $10^5$+ nodes can overflow the stack (Java default ≈ 512 KB – 1 MB). Say so and prefer the iterative form.
8. **Comparing nodes vs values:** cycle detection and intersection compare **node identity** (`==` on pointers/references), not `val`.
9. **Floyd needs both phases.** The meeting point is generally *not* the cycle entry. Only phase 2 finds the entry.
10. **Java:** there is no pointer arithmetic, so `ListNode` references play the role of pointers. Using `java.util.LinkedList` in an interview that asks you to manipulate nodes misses the point.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| "Reverse only positions $m..n$" | walk to the node before $m$, then move each following node to the sublist front $n - m$ times ([LC 92 · Reverse Linked List II](https://leetcode.com/problems/reverse-linked-list-ii/) — Medium) |
| "Is the list a palindrome in $O(1)$ space?" | find the middle, reverse the second half, compare, then reverse it back to restore the input |
| "Cycle length?" | after phase 1, keep one pointer still and count steps of the other until they meet again |
| "Do two lists intersect, and where?" | walk A then B and B then A; the pointers meet at the intersection or both reach null after $a + b$ steps ([LC 160 · Intersection of Two Linked Lists](https://leetcode.com/problems/intersection-of-two-linked-lists/) — Easy) |
| "Sort a list in $O(n \log n)$ with $O(1)$ space" | bottom-up merge sort with run sizes 1, 2, 4, …; top-down uses $O(\log n)$ stack |
| "Copy a list with random pointers without a hash map" | interleave clones `A A' B B'`, set `A'.random = A.random.next`, then unweave |
| "Find the duplicate if the array may be modified" | index marking or cyclic sort, $O(n)$ with $O(1)$ space |
| Find the Duplicate → "prove the entry is the duplicate" | the entry is the only node with two incoming edges, and an incoming edge $i \to v$ means $a_i = v$ |
| "Doubly linked list — why for LRU?" | $O(1)$ removal of an arbitrary node needs its predecessor; see [design problems](17-design-problems.md) |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium. LRU Cache is under [design problems](17-design-problems.md), Merge k Sorted Lists under [heaps](09-heaps-and-top-k.md).

**Easy** (5)

- [ ] [LC 21 · Merge Two Sorted Lists](https://leetcode.com/problems/merge-two-sorted-lists/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 141 · Linked List Cycle](https://leetcode.com/problems/linked-list-cycle/) — Easy · `G75` `B75` `NC150` `TI150`
- [ ] [LC 206 · Reverse Linked List](https://leetcode.com/problems/reverse-linked-list/) — Easy · `G75` `B75` `NC150`
- [ ] [LC 234 · Palindrome Linked List](https://leetcode.com/problems/palindrome-linked-list/) — Easy · `G169`
- [ ] [LC 876 · Middle of the Linked List](https://leetcode.com/problems/middle-of-the-linked-list/) — Easy · `G75`

**Medium** (13)

- [ ] [LC 2 · Add Two Numbers](https://leetcode.com/problems/add-two-numbers/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 19 · Remove Nth Node From End of List](https://leetcode.com/problems/remove-nth-node-from-end-of-list/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 24 · Swap Nodes in Pairs](https://leetcode.com/problems/swap-nodes-in-pairs/) — Medium · `G169`
- [ ] [LC 61 · Rotate List](https://leetcode.com/problems/rotate-list/) — Medium · `G169` `TI150`
- [ ] [LC 82 · Remove Duplicates from Sorted List II](https://leetcode.com/problems/remove-duplicates-from-sorted-list-ii/) — Medium · `TI150`
- [ ] [LC 86 · Partition List](https://leetcode.com/problems/partition-list/) — Medium · `TI150`
- [ ] [LC 92 · Reverse Linked List II](https://leetcode.com/problems/reverse-linked-list-ii/) — Medium · `NC250` `TI150`
- [ ] [LC 138 · Copy List with Random Pointer](https://leetcode.com/problems/copy-list-with-random-pointer/) — Medium · `NC150` `TI150`
- [ ] [LC 143 · Reorder List](https://leetcode.com/problems/reorder-list/) — Medium · `G169` `B75` `NC150`
- [ ] [LC 148 · Sort List](https://leetcode.com/problems/sort-list/) — Medium · `G169` `TI150`
- [ ] [LC 287 · Find the Duplicate Number](https://leetcode.com/problems/find-the-duplicate-number/) — Medium · `G169` `NC150`
- [ ] [LC 328 · Odd Even Linked List](https://leetcode.com/problems/odd-even-linked-list/) — Medium · `G169`
- [ ] [LC 2807 · Insert Greatest Common Divisors in Linked List](https://leetcode.com/problems/insert-greatest-common-divisors-in-linked-list/) — Medium · `NC250`

**Hard** (1)

- [ ] [LC 25 · Reverse Nodes in k-Group](https://leetcode.com/problems/reverse-nodes-in-k-group/) — Hard · `G169` `NC150` `TI150`

**Beyond the lists:**

- [ ] [LC 83 · Remove Duplicates from Sorted List](https://leetcode.com/problems/remove-duplicates-from-sorted-list/) — Easy — skip equal neighbours
- [ ] [LC 160 · Intersection of Two Linked Lists](https://leetcode.com/problems/intersection-of-two-linked-lists/) — Easy — switch heads trick
- [ ] [LC 203 · Remove Linked List Elements](https://leetcode.com/problems/remove-linked-list-elements/) — Easy — dummy head
- [ ] [LC 142 · Linked List Cycle II](https://leetcode.com/problems/linked-list-cycle-ii/) — Medium — Floyd phase 2
- [ ] [LC 445 · Add Two Numbers II](https://leetcode.com/problems/add-two-numbers-ii/) — Medium — stacks or reversal
- [ ] [LC 2095 · Delete the Middle Node of a Linked List](https://leetcode.com/problems/delete-the-middle-node-of-a-linked-list/) — Medium — first-middle predecessor
- [ ] [LC 2130 · Maximum Twin Sum of a Linked List](https://leetcode.com/problems/maximum-twin-sum-of-a-linked-list/) — Medium — reverse the second half
- [ ] [LC 1721 · Swapping Nodes in a Linked List](https://leetcode.com/problems/swapping-nodes-in-a-linked-list/) — Medium — gap pointers
- [ ] [LC 430 · Flatten a Multilevel Doubly Linked List](https://leetcode.com/problems/flatten-a-multilevel-doubly-linked-list/) — Medium — DFS with an explicit stack

## 9. CP counterpart

Linked lists as such are 🧊 in CP. The ideas live elsewhere:

- [Functional graphs and special graphs](../09-Graphs/10-functional-graphs-and-special-graphs.md): Floyd's algorithm, tail/cycle decomposition and binary lifting on $i \to f(i)$, which is Example 4 generalised.
- [C++ STL and Java collections](../01-Foundations/02-cpp-stl-and-java-collections.md): `std::list` / `LinkedList` costs, and why arrays usually win.
- [Treaps and implicit treaps](../08-Data-Structures/09-treaps-and-implicit-treaps.md): the CP answer to "split, reverse and splice a sequence quickly", which is reverse-in-groups at scale.

What doesn't transfer: CP code would store the list in arrays (`nxt[i]`). In interviews you must manipulate real node objects.

## 10. Self-check

1. State the invariant of iterative reversal.
2. Why does starting both pointers at a dummy node make "remove $n$-th from end" work for $n = L$?
3. Prove Floyd's phase 2: why do the pointers meet at the cycle entry?
4. Why is the duplicate in Find the Duplicate Number the cycle entry?
5. Which loop condition gives the first middle, and why does Reorder List need it?
6. In reverse-k-group, why is `prev` initialised to `groupNext`?
7. How do you detect whether two lists intersect in $O(1)$ space?

<details><summary>Answers</summary>

1. `prev` is the reversed version of the nodes already processed, `cur` is the first unprocessed node, and every processed node points into `prev`'s list.
2. The node to remove is the head, whose predecessor is the dummy. With the gap of $n$, `slow` stays at the dummy because `fast` reaches the last node after exactly $L - n = 0$ further steps.
3. At the meeting, slow has taken $k$ steps with $k \equiv 0 \pmod{\lambda}$ and $k \ge \mu$. A pointer at cycle position $k$ that walks $\mu$ more steps sits at position $\equiv \mu$, which is the entry. A pointer from the head reaches the entry after $\mu$ steps too, and before that they cannot meet because one is still on the tail.
4. Index 0 has no incoming edge, so the walk from 0 has a tail. The entry has one predecessor on the tail and one on the cycle, two different indices $i \ne j$ with $a_i = a_j =$ entry.
5. `while (fast->next && fast->next->next)`. It leaves the first half with $\lceil n/2 \rceil$ nodes, so the reversed second half is never longer and the interleave loop can stop when it runs out.
6. The first node of the group becomes the group's last node after reversal, and it must point to the rest of the list. Seeding `prev = groupNext` does that during the loop.
7. Walk pointer `a` over A then B, and `b` over B then A. Both walk $|A| + |B|$ steps in total, so they meet at the first shared node, or both become null together if there is none.

</details>
