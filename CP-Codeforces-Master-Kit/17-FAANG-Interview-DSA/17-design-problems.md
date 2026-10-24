# Design Problems (Data-Structure Design)

> **Band:** 🔵 1400–1900 (as DS skill) · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [hashing](02-arrays-hashing-and-prefix-sums.md), [linked lists](06-linked-lists.md), [heaps](09-heaps-and-top-k.md), [binary search](05-binary-search.md)
> **You can say you know this when:** given an API with required complexities (`get`/`put` in $O(1)$, `getRandom` in $O(1)$, "10 most recent"), you can pick the composition of structures that meets every bound, state the invariant that ties them together, and implement it cleanly as a class in C++ and Java.

"Design X" coding questions (not system design) ask for a class with several operations and per-operation complexity targets. Almost every answer is a **composition of two standard structures** whose weaknesses cancel: a hash map gives $O(1)$ lookup but no order, a linked list gives $O(1)$ reordering but no lookup, an array gives $O(1)$ random access but slow deletion, a heap gives the minimum but no search. The skill is to see which pair to combine and which invariant keeps them consistent.

This file covers the classics: Min Stack, LRU, LFU, Insert-Delete-GetRandom, Time-Based Key-Value Store, Peeking and Flatten-Nested iterators, Hit Counter (with rate limiters), Design Twitter and a string codec. The tree codec is [Example 6 of the trees file](07-trees-and-bst.md).

## 1. First principles — why this works

### 1.1 Start from the operation table

Write each operation with its required cost, then ask, for each candidate structure, which operations it makes cheap:

| Need | Gives it | Misses |
|---|---|---|
| find by key | hash map $O(1)$ | order, min/max, random element |
| move / remove an arbitrary element in an order | doubly linked list $O(1)$ **given the node** | finding the node |
| uniform random element, index access | dynamic array $O(1)$ | deletion from the middle |
| min / max of a changing set | heap $O(\log n)$ | arbitrary deletion, search |
| ordered queries (floor, range, k-th) | balanced BST (`std::map`, `TreeMap`) $O(\log n)$ | $O(1)$ anything |
| "the last $W$ seconds" | ring buffer / deque | random access by key |

A composition works when every operation is cheap in **at least one** structure and the structures can be kept consistent in the same time bound. LRU: the hash map finds the node and the list moves it. Randomized set: the hash map finds the index, and the array gives random access plus $O(1)$ deletion by swapping with the last element.

### 1.2 State the invariant that ties the structures together

Every design bug is a broken invariant between two structures. Write it down before coding:

- **LRU:** the map contains exactly the keys in the list, and each map value points to that key's node. The list is ordered from most to least recently used.
- **LFU:** for every frequency $f$, `lists[f]` holds exactly the keys with that frequency, most recent first, and `minFreq` is the smallest $f$ with a non-empty list.
- **Randomized set:** `vals[pos[x]] == x` for every stored $x$, and `vals` has no holes.

### 1.3 Amortised costs are allowed (say so)

Many designs rely on amortisation: a queue from two stacks, lazy deletion in heaps, iterators that skip empty nested lists, dynamic array growth. Interviewers accept amortised $O(1)$ if you name it and justify it with "each element is moved at most once".

## 2. Complexities of the designs in this file

| Design | Structures | Operations |
|---|---|---|
| Min Stack | stack of (value, min so far) | all $O(1)$ |
| LRU Cache | hash map + doubly linked list | `get`, `put` $O(1)$ |
| LFU Cache | key → (value, freq, list position); freq → list; `minFreq` | `get`, `put` $O(1)$ |
| Randomized Set | array + value → index map | `insert`, `remove`, `getRandom` $O(1)$ average |
| Time-Based KV | key → sorted vector of (timestamp, value) | `set` $O(1)$ amortised (timestamps increase), `get` $O(\log n)$ |
| Peeking Iterator | wrapped iterator + one cached element | all $O(1)$ |
| Flatten Nested List | stack of (list, index) frames | `next`/`hasNext` amortised $O(1)$ |
| Hit Counter | ring buffer of 300 (time, count) slots | `hit`, `getHits` $O(1)$ / $O(300)$ |
| Twitter | follow sets + per-user tweet lists + heap merge | `post` $O(1)$, `feed` $O(F \log F)$ for $F$ followees, `follow` $O(1)$ |
| String codec | length-prefixed framing | $O(\text{total length})$ |
| BST Iterator | stack of the left spine | `next` amortised $O(1)$, $O(h)$ memory |

## 3. Reusable templates (C++ and Java)

BST Iterator ([LC 173 · Binary Search Tree Iterator](https://leetcode.com/problems/binary-search-tree-iterator/) — Medium), the "controlled in-order traversal" that underlies most tree iterators:

```cpp
struct TreeNode {
    int val;
    TreeNode *left, *right;
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
};

class BSTIterator {
    vector<TreeNode*> st;                          // the left spine of the unvisited part
    void pushLeft(TreeNode* n) { for (; n; n = n->left) st.push_back(n); }
public:
    explicit BSTIterator(TreeNode* root) { pushLeft(root); }
    bool hasNext() const { return !st.empty(); }
    int next() {                                   // amortised O(1): each node is pushed and popped once
        TreeNode* n = st.back(); st.pop_back();
        pushLeft(n->right);
        return n->val;
    }
};
```

```java
static class TreeNode {
    int val;
    TreeNode left, right;
    TreeNode(int x) { val = x; }
}

static class BSTIterator {
    private final Deque<TreeNode> st = new ArrayDeque<>();
    BSTIterator(TreeNode root) { pushLeft(root); }
    private void pushLeft(TreeNode n) { for (; n != null; n = n.left) st.push(n); }
    boolean hasNext() { return !st.isEmpty(); }
    int next() {
        TreeNode n = st.pop();
        pushLeft(n.right);
        return n.val;
    }
}
```

Two rate limiters that interviewers ask about as variations of the hit counter. A **token bucket** allows bursts up to `capacity` and refills at `rate` tokens per second. A **sliding-window log** allows at most `limit` requests in any window of `window` seconds.

```cpp
class TokenBucket {
    double capacity, rate, tokens, last;           // last = time of the previous refill (seconds)
public:
    TokenBucket(double capacity, double ratePerSec) : capacity(capacity), rate(ratePerSec), tokens(capacity), last(0) {}
    bool allow(double now) {
        tokens = min(capacity, tokens + (now - last) * rate);   // lazy refill
        last = now;
        if (tokens >= 1) { tokens -= 1; return true; }
        return false;
    }
};

class SlidingWindowLog {
    deque<long long> times;
    int limit;
    long long window;
public:
    SlidingWindowLog(int limit, long long window) : limit(limit), window(window) {}
    bool allow(long long now) {
        while (!times.empty() && times.front() <= now - window) times.pop_front();   // expire old entries
        if ((int)times.size() >= limit) return false;
        times.push_back(now);
        return true;
    }
};
```

```java
static class TokenBucket {
    private final double capacity, rate;
    private double tokens, last;
    TokenBucket(double capacity, double ratePerSec) { this.capacity = capacity; this.rate = ratePerSec; this.tokens = capacity; }
    boolean allow(double now) {
        tokens = Math.min(capacity, tokens + (now - last) * rate);
        last = now;
        if (tokens >= 1) { tokens -= 1; return true; }
        return false;
    }
}

static class SlidingWindowLog {
    private final ArrayDeque<Long> times = new ArrayDeque<>();
    private final int limit;
    private final long window;
    SlidingWindowLog(int limit, long window) { this.limit = limit; this.window = window; }
    boolean allow(long now) {
        while (!times.isEmpty() && times.peekFirst() <= now - window) times.pollFirst();
        if (times.size() >= limit) return false;
        times.addLast(now);
        return true;
    }
}
```

## 4. Recognising the pattern

| Requirement in the prompt | Composition |
|---|---|
| "$O(1)$ get and put, evict the least recently used" | hash map + doubly linked list (LRU) |
| "evict the least frequently used, ties by recency" | key map + frequency → list map + `minFreq` (LFU) |
| "$O(1)$ insert, delete and get a uniformly random element" | array + index map, delete by swapping with the last |
| "value at time $t$", "snapshot", "versioned" | per-key sorted list of (time, value) + binary search |
| "min / max in $O(1)$ along with push/pop" | augment each stack entry with the running min |
| "peek without consuming", "iterate over a nested / tree structure" | cache one element; explicit stack of frames |
| "count events in the last $N$ seconds" | ring buffer keyed by `t mod N`, or a deque of timestamps |
| "top / most recent $k$ across many sources" | per-source lists + heap merge |
| "encode a list (or a tree) into a string and back" | length-prefixed framing / pre-order with null markers |
| "frequency stack: pop the most frequent, ties by recency" | freq → stack map + `maxFreq` |
| "design a file system / autocomplete" | trie keyed by path segments / characters ([tries](08-tries.md)) |

## 5. Worked examples

All drivers read a list of operations from stdin and print one line per operation that returns a value. Java drivers read the whole input at once (`System.in.readAllBytes()`) and split it into tokens.

### Example 1 — Min Stack · Medium

- **Source:** [LC 155 · Min Stack](https://leetcode.com/problems/min-stack/) — Medium · `G75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1100 CF, est.)
- **Problem:** a stack with `push`, `pop`, `top` and `getMin`, all in $O(1)$.
- **Thinking from first principles:** a single "current min" variable breaks on `pop`: when the minimum leaves, the previous minimum is unknown. The minimum *at each depth* never changes while that element sits on the stack, so store it alongside: each entry is (value, min of this entry and everything below). `getMin` reads the top's second field. An alternative uses a second stack that holds only new minima (push when `x <= currentMin`, pop when the popped value equals it). It uses less memory when minima are rare.

<details><summary>Solution</summary>

Each entry stores its own minimum prefix. Every operation is $O(1)$, and memory is $O(n)$ pairs. Driver operations: `push x`, `pop`, `top`, `getMin`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class MinStack {
    vector<pair<int, int>> st;                         // (value, min of the stack up to here)
public:
    void push(int val) { st.push_back({val, st.empty() ? val : min(val, st.back().second)}); }
    void pop() { st.pop_back(); }
    int top() { return st.back().first; }
    int getMin() { return st.back().second; }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> q;
    MinStack ms;
    while (q--) {
        string op;
        cin >> op;
        if (op == "push") { int x; cin >> x; ms.push(x); }
        else if (op == "pop") ms.pop();
        else if (op == "top") cout << ms.top() << '\n';
        else cout << ms.getMin() << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

class MinStack {
    private int[] vals = new int[16], mins = new int[16];
    private int size = 0;
    public void push(int val) {
        if (size == vals.length) { vals = Arrays.copyOf(vals, size * 2); mins = Arrays.copyOf(mins, size * 2); }
        mins[size] = size == 0 ? val : Math.min(val, mins[size - 1]);
        vals[size++] = val;
    }
    public void pop() { size--; }
    public int top() { return vals[size - 1]; }
    public int getMin() { return mins[size - 1]; }
}

public class Main {
    public static void main(String[] args) throws IOException {
        String[] t = new String(System.in.readAllBytes()).trim().split("\\s+");
        int p = 0, q = Integer.parseInt(t[p++]);
        MinStack ms = new MinStack();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = t[p++];
            switch (op) {
                case "push" -> ms.push(Integer.parseInt(t[p++]));
                case "pop" -> ms.pop();
                case "top" -> sb.append(ms.top()).append('\n');
                default -> sb.append(ms.getMin()).append('\n');
            }
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
8
push -2
push 0
push -3
getMin
pop
top
getMin
pop
out:
-3
0
-2
-->
<!-- test
in:
6
push 5
push 5
getMin
pop
getMin
top
out:
5
5
5
-->

### Example 2 — LRU Cache · Medium

- **Source:** [LC 146 · LRU Cache](https://leetcode.com/problems/lru-cache/) — Medium · `G75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1500 CF, est.)
- **Problem:** a cache of fixed capacity with `get(key)` (value or −1) and `put(key, value)`, both $O(1)$ average. When full, `put` of a new key evicts the least recently used key. A `get` hit and any `put` count as a use.
- **Thinking from first principles:** we need recency order with $O(1)$ "move to front" and "remove the oldest", which is a doubly linked list. We also need to find a key's node in $O(1)$, which is a hash map from key to node. Neither works alone: a list needs $O(n)$ to find a key, and a map has no order. Together: the map finds the node, the list moves it. A singly linked list is not enough, because unlinking a node needs its predecessor.

<details><summary>Solution</summary>

C++: `std::list` with `splice` (an $O(1)$ relink that keeps iterators valid) and a map from key to list iterator. Java: a hand-written doubly linked list with sentinel `head`/`tail` nodes, which removes all null checks. (`LinkedHashMap` with `accessOrder = true` and an overridden `removeEldestEntry` is the library shortcut. Mention it, then implement the real thing.) Driver operations: the first line is `capacity q`, then `get k` / `put k v`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class LRUCache {
    int capacity;
    list<pair<int, int>> order;                                 // front = most recently used
    unordered_map<int, list<pair<int, int>>::iterator> where;   // key -> its node in `order`
public:
    explicit LRUCache(int capacity) : capacity(capacity) {}
    int get(int key) {
        auto it = where.find(key);
        if (it == where.end()) return -1;
        order.splice(order.begin(), order, it->second);         // mark as most recent, O(1)
        return it->second->second;
    }
    void put(int key, int value) {
        auto it = where.find(key);
        if (it != where.end()) {
            it->second->second = value;
            order.splice(order.begin(), order, it->second);
            return;
        }
        if ((int)order.size() == capacity) {                    // evict the least recently used
            where.erase(order.back().first);
            order.pop_back();
        }
        order.push_front({key, value});
        where[key] = order.begin();
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int cap, q;
    cin >> cap >> q;
    LRUCache cache(cap);
    while (q--) {
        string op;
        cin >> op;
        if (op == "get") { int k; cin >> k; cout << cache.get(k) << '\n'; }
        else { int k, v; cin >> k >> v; cache.put(k, v); }
    }
}
```

```java
import java.util.*;
import java.io.*;

class LRUCache {
    private static class Node {
        int key, value;
        Node prev, next;
        Node(int k, int v) { key = k; value = v; }
    }
    private final int capacity;
    private final Map<Integer, Node> where = new HashMap<>();
    private final Node head = new Node(0, 0), tail = new Node(0, 0);   // sentinels: head.next is the most recent

    public LRUCache(int capacity) {
        this.capacity = capacity;
        head.next = tail;
        tail.prev = head;
    }
    private void unlink(Node n) { n.prev.next = n.next; n.next.prev = n.prev; }
    private void addFront(Node n) { n.next = head.next; n.prev = head; head.next.prev = n; head.next = n; }

    public int get(int key) {
        Node n = where.get(key);
        if (n == null) return -1;
        unlink(n);
        addFront(n);
        return n.value;
    }
    public void put(int key, int value) {
        Node n = where.get(key);
        if (n != null) { n.value = value; unlink(n); addFront(n); return; }
        if (where.size() == capacity) {
            Node lru = tail.prev;
            unlink(lru);
            where.remove(lru.key);
        }
        n = new Node(key, value);
        addFront(n);
        where.put(key, n);
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        String[] t = new String(System.in.readAllBytes()).trim().split("\\s+");
        int p = 0, cap = Integer.parseInt(t[p++]), q = Integer.parseInt(t[p++]);
        LRUCache cache = new LRUCache(cap);
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = t[p++];
            if (op.equals("get")) sb.append(cache.get(Integer.parseInt(t[p++]))).append('\n');
            else { int k = Integer.parseInt(t[p++]), v = Integer.parseInt(t[p++]); cache.put(k, v); }
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
2 9
put 1 1
put 2 2
get 1
put 3 3
get 2
put 4 4
get 1
get 3
get 4
out:
1
-1
-1
3
4
-->
<!-- test
in:
1 5
put 2 1
get 2
put 3 2
get 2
get 3
out:
1
-1
2
-->
<!-- test
in:
2 5
put 2 1
put 2 2
get 2
put 1 1
get 2
out:
2
2
-->

### Example 3 — LFU Cache · Hard

- **Source:** [LC 460 · LFU Cache](https://leetcode.com/problems/lfu-cache/) — Hard · `NC250`
- **Difficulty:** LeetCode Hard (≈ 1900 CF, est.)
- **Problem:** like LRU, but evict the key with the **lowest use count**, breaking ties by least recent use. `get` and `put` must be $O(1)$ average. Capacity may be 0.
- **Thinking from first principles:** a heap keyed by (count, last use) gives $O(\log n)$, which is the honest first answer. For $O(1)$, notice that counts only ever increase by exactly 1. So group keys by count: `lists[f]` is an LRU-ordered list of the keys used exactly $f$ times. A use moves a key from `lists[f]` to the front of `lists[f+1]`. The eviction victim is the back of `lists[minFreq]`. `minFreq` is easy to maintain: a new key resets it to 1, and a use bumps it only when the key leaves the last element of `lists[minFreq]`.

<details><summary>Solution</summary>

C++: `key → {value, freq, iterator into lists[freq]}` and `freq → list<int>`. Java: `LinkedHashSet` per frequency keeps insertion order with $O(1)$ removal, so the oldest key is `iterator().next()`. Driver: `capacity q`, then `get k` / `put k v`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class LFUCache {
    struct Entry { int value, freq; list<int>::iterator pos; };
    int capacity, minFreq = 0;
    unordered_map<int, Entry> entries;
    unordered_map<int, list<int>> lists;             // freq -> keys, front = most recent
    void touch(int key, Entry& e) {                  // one more use of key
        lists[e.freq].erase(e.pos);
        if (lists[e.freq].empty()) {
            lists.erase(e.freq);
            if (minFreq == e.freq) ++minFreq;        // the key moves to freq + 1, which is now non-empty
        }
        ++e.freq;
        lists[e.freq].push_front(key);
        e.pos = lists[e.freq].begin();
    }
public:
    explicit LFUCache(int capacity) : capacity(capacity) {}
    int get(int key) {
        auto it = entries.find(key);
        if (it == entries.end()) return -1;
        touch(key, it->second);
        return it->second.value;
    }
    void put(int key, int value) {
        if (capacity == 0) return;
        auto it = entries.find(key);
        if (it != entries.end()) { it->second.value = value; touch(key, it->second); return; }
        if ((int)entries.size() == capacity) {       // evict LFU, oldest among ties
            int victim = lists[minFreq].back();
            lists[minFreq].pop_back();
            if (lists[minFreq].empty()) lists.erase(minFreq);
            entries.erase(victim);
        }
        lists[1].push_front(key);
        entries[key] = {value, 1, lists[1].begin()};
        minFreq = 1;                                 // a new key always has the lowest count
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int cap, q;
    cin >> cap >> q;
    LFUCache cache(cap);
    while (q--) {
        string op;
        cin >> op;
        if (op == "get") { int k; cin >> k; cout << cache.get(k) << '\n'; }
        else { int k, v; cin >> k >> v; cache.put(k, v); }
    }
}
```

```java
import java.util.*;
import java.io.*;

class LFUCache {
    private final int capacity;
    private int minFreq = 0;
    private final Map<Integer, Integer> values = new HashMap<>(), freqs = new HashMap<>();
    private final Map<Integer, LinkedHashSet<Integer>> lists = new HashMap<>();   // insertion order = recency

    public LFUCache(int capacity) { this.capacity = capacity; }

    private void touch(int key) {
        int f = freqs.get(key);
        LinkedHashSet<Integer> set = lists.get(f);
        set.remove(key);
        if (set.isEmpty()) {
            lists.remove(f);
            if (minFreq == f) minFreq++;
        }
        freqs.put(key, f + 1);
        lists.computeIfAbsent(f + 1, x -> new LinkedHashSet<>()).add(key);   // appended = most recent
    }
    public int get(int key) {
        Integer v = values.get(key);
        if (v == null) return -1;
        touch(key);
        return v;
    }
    public void put(int key, int value) {
        if (capacity == 0) return;
        if (values.containsKey(key)) { values.put(key, value); touch(key); return; }
        if (values.size() == capacity) {
            LinkedHashSet<Integer> set = lists.get(minFreq);
            int victim = set.iterator().next();                                 // oldest with min count
            set.remove(victim);
            if (set.isEmpty()) lists.remove(minFreq);
            values.remove(victim);
            freqs.remove(victim);
        }
        values.put(key, value);
        freqs.put(key, 1);
        lists.computeIfAbsent(1, x -> new LinkedHashSet<>()).add(key);
        minFreq = 1;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        String[] t = new String(System.in.readAllBytes()).trim().split("\\s+");
        int p = 0, cap = Integer.parseInt(t[p++]), q = Integer.parseInt(t[p++]);
        LFUCache cache = new LFUCache(cap);
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = t[p++];
            if (op.equals("get")) sb.append(cache.get(Integer.parseInt(t[p++]))).append('\n');
            else { int k = Integer.parseInt(t[p++]), v = Integer.parseInt(t[p++]); cache.put(k, v); }
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
2 10
put 1 1
put 2 2
get 1
put 3 3
get 2
get 3
put 4 4
get 1
get 3
get 4
out:
1
-1
3
-1
3
4
-->
<!-- test
in:
0 2
put 0 0
get 0
out:
-1
-->
<!-- test
in:
2 6
put 3 1
put 2 1
put 2 2
put 4 4
get 2
get 3
out:
2
-1
-->

### Example 4 — Insert Delete GetRandom O(1) · Medium

- **Source:** [LC 380 · Insert Delete GetRandom O(1)](https://leetcode.com/problems/insert-delete-getrandom-o1/) — Medium · `G169` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1500 CF, est.)
- **Problem:** a set with `insert(x)` and `remove(x)` (each returning whether the set changed) and `getRandom()` returning each present element with equal probability, all in average $O(1)$.
- **Thinking from first principles:** a hash set does insert/remove in $O(1)$, but drawing a uniform random element needs random *index* access, which it does not have. An array has random access but $O(n)$ deletion from the middle. Combine them: store the values in an array and keep a map from value to index. Deleting $x$: move the **last** element into $x$'s slot, update its index in the map, and pop the back. Order does not matter for a set, so the swap is free, and the array never has holes. `getRandom` is a uniform index into the array.

<details><summary>Solution</summary>

Invariant: `vals[pos[x]] == x` for every stored $x$, and `vals` holds exactly the set. The driver checks that each `getRandom` result is a current member (and prints `ok`), so the test is deterministic even though the value is random. Driver operations: `insert x`, `remove x`, `getRandom`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class RandomizedSet {
    vector<int> vals;
    unordered_map<int, int> pos;                  // value -> index in vals
    mt19937 rng{12345};
public:
    bool insert(int val) {
        if (pos.count(val)) return false;
        pos[val] = vals.size();
        vals.push_back(val);
        return true;
    }
    bool remove(int val) {
        auto it = pos.find(val);
        if (it == pos.end()) return false;
        int i = it->second, last = vals.back();
        vals[i] = last;                           // move the last element into the hole
        pos[last] = i;
        vals.pop_back();
        pos.erase(val);                           // erase after updating `last` (val may equal last)
        return true;
    }
    int getRandom() { return vals[rng() % vals.size()]; }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> q;
    RandomizedSet rs;
    set<int> shadow;                              // independent model used only by the driver
    while (q--) {
        string op;
        cin >> op;
        if (op == "insert") { int x; cin >> x; bool r = rs.insert(x); shadow.insert(x); cout << (r ? "true" : "false") << '\n'; }
        else if (op == "remove") { int x; cin >> x; bool r = rs.remove(x); shadow.erase(x); cout << (r ? "true" : "false") << '\n'; }
        else cout << (shadow.count(rs.getRandom()) ? "ok" : "BAD") << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

class RandomizedSet {
    private final List<Integer> vals = new ArrayList<>();
    private final Map<Integer, Integer> pos = new HashMap<>();
    private final Random rng = new Random(12345);

    public boolean insert(int val) {
        if (pos.containsKey(val)) return false;
        pos.put(val, vals.size());
        vals.add(val);
        return true;
    }
    public boolean remove(int val) {
        Integer i = pos.get(val);
        if (i == null) return false;
        int last = vals.get(vals.size() - 1);
        vals.set(i, last);
        pos.put(last, i);
        vals.remove(vals.size() - 1);             // remove by index (an int), O(1) at the end
        pos.remove(val);
        return true;
    }
    public int getRandom() { return vals.get(rng.nextInt(vals.size())); }
}

public class Main {
    public static void main(String[] args) throws IOException {
        String[] t = new String(System.in.readAllBytes()).trim().split("\\s+");
        int p = 0, q = Integer.parseInt(t[p++]);
        RandomizedSet rs = new RandomizedSet();
        Set<Integer> shadow = new HashSet<>();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = t[p++];
            if (op.equals("insert")) { int x = Integer.parseInt(t[p++]); sb.append(rs.insert(x)).append('\n'); shadow.add(x); }
            else if (op.equals("remove")) { int x = Integer.parseInt(t[p++]); sb.append(rs.remove(x)).append('\n'); shadow.remove(x); }
            else sb.append(shadow.contains(rs.getRandom()) ? "ok" : "BAD").append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
7
insert 1
remove 2
insert 2
getRandom
remove 1
insert 2
getRandom
out:
true
false
true
ok
true
false
ok
-->
<!-- test
in:
5
insert 5
remove 5
remove 5
insert 5
getRandom
out:
true
true
false
true
ok
-->

### Example 5 — Time Based Key-Value Store · Medium

- **Source:** [LC 981 · Time Based Key-Value Store](https://leetcode.com/problems/time-based-key-value-store/) — Medium · `G75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** `set(key, value, timestamp)` and `get(key, timestamp)`, which returns the value with the largest stored timestamp $\le$ the query timestamp, or `""`. Timestamps of `set` calls are strictly increasing.
- **Thinking from first principles:** per key we need "the latest version at or before $t$", which is a floor query on timestamps. A `TreeMap`/`std::map` per key gives $O(\log n)$ floor queries. The increasing-timestamp guarantee allows something leaner: append `(timestamp, value)` to a vector per key, which stays sorted for free, then binary-search with `upper_bound(t) - 1` ([file 05](05-binary-search.md)). `set` is $O(1)$ amortised and `get` $O(\log n)$.

<details><summary>Solution</summary>

`upper_bound` on timestamps finds the first entry with timestamp $> t$, and the entry before it is the answer (if any). The driver prints values in quotes so the empty string is visible. Operations: `set key value t`, `get key t`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class TimeMap {
    unordered_map<string, vector<pair<int, string>>> history;   // sorted by timestamp per key
public:
    void set(string key, string value, int timestamp) { history[key].push_back({timestamp, value}); }
    string get(string key, int timestamp) {
        auto it = history.find(key);
        if (it == history.end()) return "";
        auto& v = it->second;
        auto pos = upper_bound(v.begin(), v.end(), timestamp,
                               [](int t, const pair<int, string>& e) { return t < e.first; });
        return pos == v.begin() ? "" : prev(pos)->second;      // last entry with time <= timestamp
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> q;
    TimeMap tm;
    while (q--) {
        string op, key;
        cin >> op >> key;
        if (op == "set") { string v; int t; cin >> v >> t; tm.set(key, v, t); }
        else { int t; cin >> t; cout << '"' << tm.get(key, t) << '"' << '\n'; }
    }
}
```

```java
import java.util.*;
import java.io.*;

class TimeMap {
    private final Map<String, List<Integer>> times = new HashMap<>();
    private final Map<String, List<String>> vals = new HashMap<>();

    public void set(String key, String value, int timestamp) {
        times.computeIfAbsent(key, k -> new ArrayList<>()).add(timestamp);
        vals.computeIfAbsent(key, k -> new ArrayList<>()).add(value);
    }
    public String get(String key, int timestamp) {
        List<Integer> ts = times.get(key);
        if (ts == null) return "";
        int lo = 0, hi = ts.size();                   // first index with time > timestamp
        while (lo < hi) {
            int mid = (lo + hi) >>> 1;
            if (ts.get(mid) > timestamp) hi = mid; else lo = mid + 1;
        }
        return lo == 0 ? "" : vals.get(key).get(lo - 1);
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        String[] t = new String(System.in.readAllBytes()).trim().split("\\s+");
        int p = 0, q = Integer.parseInt(t[p++]);
        TimeMap tm = new TimeMap();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = t[p++], key = t[p++];
            if (op.equals("set")) { String v = t[p++]; int ts = Integer.parseInt(t[p++]); tm.set(key, v, ts); }
            else sb.append('"').append(tm.get(key, Integer.parseInt(t[p++]))).append("\"\n");
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
6
set foo bar 1
get foo 1
get foo 3
set foo bar2 4
get foo 4
get foo 5
out:
"bar"
"bar"
"bar2"
"bar2"
-->
<!-- test
in:
4
set love high 10
set love low 20
get love 5
get hate 30
out:
""
""
-->

### Example 6 — Peeking Iterator · Medium

- **Source:** [LC 284 · Peeking Iterator](https://leetcode.com/problems/peeking-iterator/) — Medium (not in the fetched lists; the standard iterator-design question)
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** wrap an iterator that only supports `next()` and `hasNext()` so that it also supports `peek()` (return the next element without advancing).
- **Thinking from first principles:** the underlying iterator cannot un-read an element, so the wrapper must **cache one element ahead**. Invariant: `hasCached` says whether `cached` holds the next element of the overall sequence. `peek` fills the cache if needed and returns it. `next` returns the cache (and clears it) or delegates. `hasNext` is true if the cache is full or the inner iterator has more. Filling the cache lazily (on demand) instead of eagerly in the constructor also works for iterators whose `next` is expensive or has side effects.

<details><summary>Solution</summary>

The C++ version derives from a minimal `Iterator` base class that mirrors LeetCode's interface. The Java version wraps `java.util.Iterator<Integer>`. Every operation is $O(1)$. The driver reads `n` values and then operations `peek`, `next`, `hasNext`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Iterator {                                   // the given interface: next() and hasNext() only
    const vector<int>* data;
    size_t idx = 0;
public:
    explicit Iterator(const vector<int>& nums) : data(&nums) {}
    virtual ~Iterator() = default;
    virtual int next() { return (*data)[idx++]; }
    virtual bool hasNext() const { return idx < data->size(); }
};

class PeekingIterator : public Iterator {
    bool hasCached = false;
    int cached = 0;
public:
    explicit PeekingIterator(const vector<int>& nums) : Iterator(nums) {}
    int peek() {
        if (!hasCached) { cached = Iterator::next(); hasCached = true; }   // read one ahead, lazily
        return cached;
    }
    int next() override {
        if (hasCached) { hasCached = false; return cached; }
        return Iterator::next();
    }
    bool hasNext() const override { return hasCached || Iterator::hasNext(); }
};

int main() {
    int n, q;
    cin >> n;
    vector<int> nums(n);
    for (int& x : nums) cin >> x;
    cin >> q;
    PeekingIterator it(nums);
    while (q--) {
        string op;
        cin >> op;
        if (op == "peek") cout << it.peek() << '\n';
        else if (op == "next") cout << it.next() << '\n';
        else cout << (it.hasNext() ? "true" : "false") << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

class PeekingIterator implements Iterator<Integer> {
    private final Iterator<Integer> inner;
    private boolean hasCached = false;
    private Integer cached;

    public PeekingIterator(Iterator<Integer> iterator) { inner = iterator; }
    public Integer peek() {
        if (!hasCached) { cached = inner.next(); hasCached = true; }
        return cached;
    }
    @Override public Integer next() {
        if (hasCached) { hasCached = false; return cached; }
        return inner.next();
    }
    @Override public boolean hasNext() { return hasCached || inner.hasNext(); }
}

public class Main {
    public static void main(String[] args) throws IOException {
        String[] t = new String(System.in.readAllBytes()).trim().split("\\s+");
        int p = 0, n = Integer.parseInt(t[p++]);
        List<Integer> nums = new ArrayList<>();
        for (int i = 0; i < n; i++) nums.add(Integer.parseInt(t[p++]));
        int q = Integer.parseInt(t[p++]);
        PeekingIterator it = new PeekingIterator(nums.iterator());
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = t[p++];
            if (op.equals("peek")) sb.append(it.peek()).append('\n');
            else if (op.equals("next")) sb.append(it.next()).append('\n');
            else sb.append(it.hasNext()).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
3
1 2 3
5
next
peek
next
next
hasNext
out:
1
2
2
3
false
-->
<!-- test
in:
1
7
5
hasNext
peek
peek
next
hasNext
out:
true
7
7
7
false
-->

### Example 7 — Flatten Nested List Iterator · Medium

- **Source:** [LC 341 · Flatten Nested List Iterator](https://leetcode.com/problems/flatten-nested-list-iterator/) — Medium (not in the fetched lists; the standard nested-iterator question)
- **Difficulty:** LeetCode Medium (≈ 1500 CF, est.)
- **Problem:** given a nested list like `[1,[4,[6]],[],[[]],2]`, implement an iterator over its integers in order (`1 4 6 2`). Lists may be empty at any depth.
- **Thinking from first principles:** flattening everything in the constructor ($O(N)$ time and memory) is acceptable and worth offering first. A true iterator should be **lazy**: keep a stack of frames `(list, next index)`, which is the recursion of a DFS made explicit. `hasNext` does the real work. It advances the top frame until it points at an integer, pushing a frame for each nested list and popping frames that are exhausted. Doing this in `hasNext` (not `next`) is what makes empty lists like `[[]]` safe. Each element is pushed and popped once, so the operations are amortised $O(1)$.

<details><summary>Solution</summary>

`NestedInteger` mimics LeetCode's interface (`isInteger`, `getInteger`, `getList`). The driver parses the bracket notation into it, then prints every element via `hasNext`/`next`, or `empty` if there are none. Memory is $O(\text{depth})$.

```cpp
#include <bits/stdc++.h>
using namespace std;

class NestedInteger {                              // LeetCode-style interface
    bool isInt;
    int val = 0;
    vector<NestedInteger> items;
public:
    explicit NestedInteger(int v) : isInt(true), val(v) {}
    NestedInteger() : isInt(false) {}
    bool isInteger() const { return isInt; }
    int getInteger() const { return val; }
    const vector<NestedInteger>& getList() const { return items; }
    void add(const NestedInteger& x) { items.push_back(x); }
};

class NestedIterator {
    vector<pair<const vector<NestedInteger>*, size_t>> st;   // frames: (list, next index)
public:
    explicit NestedIterator(const vector<NestedInteger>& nestedList) { st.push_back({&nestedList, 0}); }
    bool hasNext() {                               // advance to the next integer, if any
        while (!st.empty()) {
            auto& [lst, i] = st.back();
            if (i == lst->size()) { st.pop_back(); continue; }   // this list is exhausted
            const NestedInteger& x = (*lst)[i];
            if (x.isInteger()) return true;
            ++i;                                   // step past the sublist in this frame
            st.push_back({&x.getList(), 0});       // and descend into it
        }
        return false;
    }
    int next() {                                   // precondition: hasNext() was true
        hasNext();
        auto& [lst, i] = st.back();
        return (*lst)[i++].getInteger();
    }
};

NestedInteger parseList(const string& s, size_t& i) {    // s[i] == '['
    NestedInteger res;
    ++i;
    while (s[i] != ']') {
        if (s[i] == ',') { ++i; continue; }
        if (s[i] == '[') res.add(parseList(s, i));
        else {
            size_t j = i;
            while (s[j] == '-' || isdigit((unsigned char)s[j])) ++j;
            res.add(NestedInteger(stoi(s.substr(i, j - i))));
            i = j;
        }
    }
    ++i;
    return res;
}

int main() {
    string s;
    cin >> s;
    size_t i = 0;
    NestedInteger root = parseList(s, i);
    NestedIterator it(root.getList());
    vector<int> out;
    while (it.hasNext()) out.push_back(it.next());
    if (out.empty()) cout << "empty\n";
    for (size_t k = 0; k < out.size(); ++k) cout << out[k] << (k + 1 < out.size() ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

class NestedInteger {
    private final Integer val;
    private final List<NestedInteger> items = new ArrayList<>();
    NestedInteger(int v) { val = v; }
    NestedInteger() { val = null; }
    public boolean isInteger() { return val != null; }
    public Integer getInteger() { return val; }
    public List<NestedInteger> getList() { return items; }
    void add(NestedInteger x) { items.add(x); }
}

class NestedIterator implements Iterator<Integer> {
    private final Deque<Iterator<NestedInteger>> st = new ArrayDeque<>();
    private Integer nextVal = null;                 // the integer found by hasNext, not yet returned

    public NestedIterator(List<NestedInteger> nestedList) { st.push(nestedList.iterator()); }
    @Override public boolean hasNext() {
        while (nextVal == null && !st.isEmpty()) {
            Iterator<NestedInteger> top = st.peek();
            if (!top.hasNext()) { st.pop(); continue; }
            NestedInteger x = top.next();
            if (x.isInteger()) nextVal = x.getInteger();
            else st.push(x.getList().iterator());
        }
        return nextVal != null;
    }
    @Override public Integer next() {
        hasNext();
        Integer v = nextVal;
        nextVal = null;
        return v;
    }
}

public class Main {
    static int pos;
    static NestedInteger parseList(String s) {      // s.charAt(pos) == '['
        NestedInteger res = new NestedInteger();
        pos++;
        while (s.charAt(pos) != ']') {
            char c = s.charAt(pos);
            if (c == ',') { pos++; continue; }
            if (c == '[') res.add(parseList(s));
            else {
                int j = pos;
                while (s.charAt(j) == '-' || Character.isDigit(s.charAt(j))) j++;
                res.add(new NestedInteger(Integer.parseInt(s.substring(pos, j))));
                pos = j;
            }
        }
        pos++;
        return res;
    }
    public static void main(String[] args) throws IOException {
        String s = new String(System.in.readAllBytes()).trim();
        pos = 0;
        NestedIterator it = new NestedIterator(parseList(s).getList());
        List<Integer> out = new ArrayList<>();
        while (it.hasNext()) out.add(it.next());
        StringBuilder sb = new StringBuilder();
        if (out.isEmpty()) sb.append("empty");
        for (int k = 0; k < out.size(); k++) sb.append(k > 0 ? " " : "").append(out.get(k));
        System.out.println(sb);
    }
}
```

</details>

<!-- test
in:
[[1,1],2,[1,1]]
out:
1 1 2 1 1
-->
<!-- test
in:
[1,[4,[6]],[],[[]],-2]
out:
1 4 6 -2
-->
<!-- test
in:
[[],[[]]]
out:
empty
-->

### Example 8 — Design Hit Counter · Medium 🔒

- **Source:** [LC 362 · Design Hit Counter](https://leetcode.com/problems/design-hit-counter/) — Medium 🔒 · `G169`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** `hit(timestamp)` records a hit and `getHits(timestamp)` returns the number of hits in the past 300 seconds, i.e. with time in $(t - 300, t]$. Timestamps (in seconds) are non-decreasing. Follow-up: what if there are many hits per second?
- **Thinking from first principles:** a queue of timestamps (pop from the front while older than $t - 300$) is correct and simple, but stores one entry per hit, which is a problem when hits per second are huge. Only 300 distinct seconds matter at any time, so use a **ring buffer** of 300 slots indexed by `t % 300`, each storing (the second it currently represents, the hit count). A hit at second $t$ either increments the slot (same second) or overwrites it (a stale second $\le t - 300$). `getHits` sums the slots whose second lies in the window. That is $O(1)$ per hit, $O(300)$ per query and constant memory regardless of the hit rate.

<details><summary>Solution</summary>

Slot `t % 300` can only hold seconds congruent to $t$ modulo 300, so when it holds a different second, that second is at least 300 seconds old and can be overwritten. Driver operations: `hit t`, `getHits t`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class HitCounter {
    static const int W = 300;
    int times[W] = {}, counts[W] = {};             // slot s holds hits of second times[s]
public:
    void hit(int timestamp) {
        int s = timestamp % W;
        if (times[s] != timestamp) { times[s] = timestamp; counts[s] = 0; }   // stale second: reuse
        counts[s]++;
    }
    int getHits(int timestamp) {
        int total = 0;
        for (int s = 0; s < W; ++s)
            if (timestamp - times[s] < W) total += counts[s];   // second in (t - 300, t]
        return total;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> q;
    HitCounter hc;
    while (q--) {
        string op;
        int t;
        cin >> op >> t;
        if (op == "hit") hc.hit(t);
        else cout << hc.getHits(t) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

class HitCounter {
    private static final int W = 300;
    private final int[] times = new int[W], counts = new int[W];
    public void hit(int timestamp) {
        int s = timestamp % W;
        if (times[s] != timestamp) { times[s] = timestamp; counts[s] = 0; }
        counts[s]++;
    }
    public int getHits(int timestamp) {
        int total = 0;
        for (int s = 0; s < W; s++) if (timestamp - times[s] < W) total += counts[s];
        return total;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        String[] t = new String(System.in.readAllBytes()).trim().split("\\s+");
        int p = 0, q = Integer.parseInt(t[p++]);
        HitCounter hc = new HitCounter();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = t[p++];
            int ts = Integer.parseInt(t[p++]);
            if (op.equals("hit")) hc.hit(ts);
            else sb.append(hc.getHits(ts)).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
7
hit 1
hit 2
hit 3
getHits 4
hit 300
getHits 300
getHits 301
out:
3
4
3
-->
<!-- test
in:
5
hit 1
hit 1
hit 1
getHits 300
getHits 301
out:
3
0
-->

### Example 9 — Design Twitter · Medium

- **Source:** [LC 355 · Design Twitter](https://leetcode.com/problems/design-twitter/) — Medium · `NC150`
- **Difficulty:** LeetCode Medium (≈ 1600 CF, est.)
- **Problem:** `postTweet(user, tweetId)`, `getNewsFeed(user)` (the 10 most recent tweet ids from the user and the users they follow, newest first), `follow(a, b)` and `unfollow(a, b)`. A user cannot unfollow themselves.
- **Thinking from first principles:** store each user's tweets in posting order with a global timestamp. The feed is "the 10 largest timestamps across $F + 1$ sorted lists", which is a $k$-way merge ([heaps](09-heaps-and-top-k.md)). Push the newest tweet of each source into a max-heap, pop 10 times, and after each pop push that source's next-older tweet. The cost is $O(F + 10 \log F)$ per feed, independent of how many tweets exist. Follows are a hash set per user. The alternative "fan-out on write" (push each tweet into every follower's feed) makes reads $O(1)$ and writes expensive, which is the real-world trade-off interviewers like to hear.

<details><summary>Solution</summary>

Heap entries are `(time, user, index into that user's tweet list)`. Driver operations: `post u id`, `feed u`, `follow a b`, `unfollow a b`. Feeds are printed as `[id1,id2,...]`.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Twitter {
    int clock = 0;
    unordered_map<int, vector<pair<int, int>>> tweets;     // user -> (time, tweetId), oldest first
    unordered_map<int, unordered_set<int>> follows;
public:
    void postTweet(int userId, int tweetId) { tweets[userId].push_back({clock++, tweetId}); }
    vector<int> getNewsFeed(int userId) {
        priority_queue<tuple<int, int, int>> pq;           // (time, user, index), newest on top
        auto pushNewest = [&](int u) {
            auto it = tweets.find(u);
            if (it != tweets.end() && !it->second.empty()) {
                int idx = it->second.size() - 1;
                pq.push({it->second[idx].first, u, idx});
            }
        };
        pushNewest(userId);
        if (follows.count(userId))
            for (int f : follows[userId]) if (f != userId) pushNewest(f);
        vector<int> feed;
        while (!pq.empty() && feed.size() < 10) {
            auto [time, u, idx] = pq.top(); pq.pop();
            feed.push_back(tweets[u][idx].second);
            if (idx > 0) pq.push({tweets[u][idx - 1].first, u, idx - 1});   // next older from the same user
        }
        return feed;
    }
    void follow(int a, int b) { if (a != b) follows[a].insert(b); }
    void unfollow(int a, int b) { if (follows.count(a)) follows[a].erase(b); }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> q;
    Twitter tw;
    while (q--) {
        string op;
        cin >> op;
        if (op == "post") { int u, id; cin >> u >> id; tw.postTweet(u, id); }
        else if (op == "feed") {
            int u;
            cin >> u;
            vector<int> f = tw.getNewsFeed(u);
            cout << '[';
            for (size_t i = 0; i < f.size(); ++i) cout << (i ? "," : "") << f[i];
            cout << "]\n";
        } else if (op == "follow") { int a, b; cin >> a >> b; tw.follow(a, b); }
        else { int a, b; cin >> a >> b; tw.unfollow(a, b); }
    }
}
```

```java
import java.util.*;
import java.io.*;

class Twitter {
    private int clock = 0;
    private final Map<Integer, List<int[]>> tweets = new HashMap<>();     // user -> {time, tweetId}
    private final Map<Integer, Set<Integer>> follows = new HashMap<>();

    public void postTweet(int userId, int tweetId) {
        tweets.computeIfAbsent(userId, k -> new ArrayList<>()).add(new int[]{clock++, tweetId});
    }
    public List<Integer> getNewsFeed(int userId) {
        PriorityQueue<int[]> pq = new PriorityQueue<>((a, b) -> Integer.compare(b[0], a[0]));   // {time, user, idx}
        Set<Integer> sources = new HashSet<>(follows.getOrDefault(userId, Set.of()));
        sources.add(userId);
        for (int u : sources) {
            List<int[]> list = tweets.get(u);
            if (list != null && !list.isEmpty()) pq.add(new int[]{list.get(list.size() - 1)[0], u, list.size() - 1});
        }
        List<Integer> feed = new ArrayList<>();
        while (!pq.isEmpty() && feed.size() < 10) {
            int[] top = pq.poll();
            List<int[]> list = tweets.get(top[1]);
            feed.add(list.get(top[2])[1]);
            if (top[2] > 0) pq.add(new int[]{list.get(top[2] - 1)[0], top[1], top[2] - 1});
        }
        return feed;
    }
    public void follow(int a, int b) { if (a != b) follows.computeIfAbsent(a, k -> new HashSet<>()).add(b); }
    public void unfollow(int a, int b) { Set<Integer> s = follows.get(a); if (s != null) s.remove(b); }
}

public class Main {
    public static void main(String[] args) throws IOException {
        String[] t = new String(System.in.readAllBytes()).trim().split("\\s+");
        int p = 0, q = Integer.parseInt(t[p++]);
        Twitter tw = new Twitter();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = t[p++];
            switch (op) {
                case "post" -> { int u = Integer.parseInt(t[p++]), id = Integer.parseInt(t[p++]); tw.postTweet(u, id); }
                case "feed" -> {
                    List<Integer> f = tw.getNewsFeed(Integer.parseInt(t[p++]));
                    sb.append('[');
                    for (int i = 0; i < f.size(); i++) sb.append(i > 0 ? "," : "").append(f.get(i));
                    sb.append("]\n");
                }
                case "follow" -> { int a = Integer.parseInt(t[p++]), b = Integer.parseInt(t[p++]); tw.follow(a, b); }
                default -> { int a = Integer.parseInt(t[p++]), b = Integer.parseInt(t[p++]); tw.unfollow(a, b); }
            }
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
7
post 1 5
feed 1
follow 1 2
post 2 6
feed 1
unfollow 1 2
feed 1
out:
[5]
[6,5]
[5]
-->
<!-- test
in:
13
post 1 1
post 1 2
post 1 3
post 1 4
post 1 5
post 1 6
post 1 7
post 1 8
post 1 9
post 1 10
post 1 11
feed 1
feed 2
out:
[11,10,9,8,7,6,5,4,3,2]
[]
-->

### Example 10 — Encode and Decode Strings · Medium 🔒

- **Source:** [LC 271 · Encode and Decode Strings](https://leetcode.com/problems/encode-and-decode-strings/) — Medium 🔒 · `G169` `B75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** encode a list of arbitrary strings (any characters, possibly empty) into one string, and decode it back exactly.
- **Thinking from first principles:** joining with a delimiter fails as soon as a string contains the delimiter. Escaping works but is fiddly. **Length-prefix framing** is the standard robust answer, the same idea network protocols use: write `len#content` for each string. The decoder reads digits up to the first `#`, then takes exactly `len` characters, whatever they are, so `#` and digits inside the content are harmless. The tree codec in [Example 6 of the trees file](07-trees-and-bst.md) is the same principle applied to structure.

<details><summary>Solution</summary>

Encoding is $O(\text{total length})$, and so is decoding. The driver reads `n` strings, where the token `<empty>` stands for the empty string. It prints the encoded form, then the decoded strings one per line (with `<empty>` for empty ones), so a round-trip error would show.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Codec {
public:
    string encode(const vector<string>& strs) {
        string out;
        for (const string& s : strs) out += to_string(s.size()) + "#" + s;   // length prefix, then raw bytes
        return out;
    }
    vector<string> decode(const string& s) {
        vector<string> res;
        size_t i = 0;
        while (i < s.size()) {
            size_t hash = s.find('#', i);                // the first '#' after i ends the length
            size_t len = stoul(s.substr(i, hash - i));
            res.push_back(s.substr(hash + 1, len));       // take exactly len characters
            i = hash + 1 + len;
        }
        return res;
    }
};

int main() {
    int n;
    cin >> n;
    vector<string> strs(n);
    for (auto& s : strs) { cin >> s; if (s == "<empty>") s = ""; }
    Codec c;
    string enc = c.encode(strs);
    cout << enc << '\n';
    for (auto& s : c.decode(enc)) cout << (s.empty() ? "<empty>" : s) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Codec {
    public String encode(List<String> strs) {
        StringBuilder sb = new StringBuilder();
        for (String s : strs) sb.append(s.length()).append('#').append(s);
        return sb.toString();
    }
    public List<String> decode(String s) {
        List<String> res = new ArrayList<>();
        int i = 0;
        while (i < s.length()) {
            int hash = s.indexOf('#', i);
            int len = Integer.parseInt(s.substring(i, hash));
            res.add(s.substring(hash + 1, hash + 1 + len));
            i = hash + 1 + len;
        }
        return res;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        String[] t = new String(System.in.readAllBytes()).trim().split("\\s+");
        int p = 0, n = Integer.parseInt(t[p++]);
        List<String> strs = new ArrayList<>();
        for (int i = 0; i < n; i++) { String s = t[p++]; strs.add(s.equals("<empty>") ? "" : s); }
        Codec c = new Codec();
        String enc = c.encode(strs);
        StringBuilder sb = new StringBuilder(enc).append('\n');
        for (String s : c.decode(enc)) sb.append(s.isEmpty() ? "<empty>" : s).append('\n');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
2
hello world
out:
5#hello5#world
hello
world
-->
<!-- test
in:
3
4#ab <empty> ##
out:
4#4#ab0#2###
4#ab
<empty>
##
-->

## 6. Pitfalls and things to remember

1. **Write the invariant between the structures first.** Most bugs are a map entry pointing to a removed node, or a node missing from the map.
2. **Update both structures in every branch**, including the "key already exists" path of `put` (update the value **and** the recency).
3. **Order of erasure** in swap-with-last deletion: update the moved element's index *before* erasing the removed key, since they may be the same element when it is the last one.
4. **C++ iterator validity:** `std::list` iterators survive `splice`, `push_front` and the erasure of *other* elements. `vector` iterators and indices do not survive reallocation, so store indices only when you control growth.
5. **Java `List.remove(int)` vs `remove(Object)`:** `vals.remove(vals.size() - 1)` removes by index. Passing an `Integer` removes by value in $O(n)$.
6. **LFU `minFreq`:** reset it to 1 on every new insertion, and bump it only when the key being touched was the last one at `minFreq`.
7. **Capacity 0** (LFU/LRU edge case): `put` must do nothing, or it will evict from an empty structure.
8. **Iterators:** do the "advance to the next real element" work in `hasNext`, and make `next` call it. This handles empty nested lists and repeated `hasNext` calls.
9. **Time windows:** be explicit about inclusive/exclusive ends (`(t - 300, t]`). Off-by-one at the window edge is the classic hit-counter bug.
10. **Randomness:** use one seeded generator per object (`mt19937`, `java.util.Random`) and never `rand() % n` with a small `RAND_MAX` (Windows: 32767), which is biased and too small for large sets.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| LRU → "make it thread-safe" | one lock around both structures (simple), or lock striping / sharded caches; `ConcurrentHashMap` alone is not enough because the list must change atomically with the map |
| LRU → "time-based expiry (TTL)" | store an expiry per entry; lazy check on `get` plus a min-heap or timer wheel to purge |
| LRU → "distributed" | consistent hashing of keys to nodes, one LRU per node; approximate global LRU |
| LFU → "why not a heap?" | a heap gives $O(\log n)$ and needs decrease-key; the frequency-bucket lists exploit $+1$ increments for $O(1)$ |
| Randomized set → "duplicates allowed" | value → set of indices; remove any index, then the same swap ([LC 381 · Insert Delete GetRandom O(1) - Duplicates allowed](https://leetcode.com/problems/insert-delete-getrandom-o1-duplicates-allowed/) — Hard) |
| Time map → "timestamps not increasing" | a `TreeMap`/`std::map` per key for $O(\log n)$ insert and floor |
| → "snapshots of an array" | per-index version lists + binary search ([LC 1146 · Snapshot Array](https://leetcode.com/problems/snapshot-array/) — Medium) |
| Hit counter → "huge hit rates / distributed" | per-second buckets (this design) per server, aggregated by a central counter; or approximate counting |
| Rate limiter → "which algorithm?" | token bucket (allows bursts, smooth rate), sliding-window log (exact, memory per request), fixed window (cheap, boundary bursts), sliding-window counter (approximate, cheap) |
| Twitter → "millions of followers" | fan-out on write for normal users, fan-out on read for celebrities (hybrid); cache feeds |
| Codec → "binary data / unknown alphabet" | fixed 4-byte length headers instead of decimal + `#` |
| "Max stack with `popMax`" | two stacks fail for `popMax`; use a doubly linked list + ordered map (value → nodes) for $O(\log n)$ ([LC 716 · Max Stack](https://leetcode.com/problems/max-stack/) — Hard 🔒) |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium. Encode and Decode Strings is filed under [arrays and hashing](02-arrays-hashing-and-prefix-sums.md) and Serialize/Deserialize under [trees](07-trees-and-bst.md) in the master list.

**Easy** (2)

- [ ] [LC 705 · Design HashSet](https://leetcode.com/problems/design-hashset/) — Easy · `NC250`
- [ ] [LC 706 · Design HashMap](https://leetcode.com/problems/design-hashmap/) — Easy · `NC250`

**Medium** (8)

- [ ] [LC 146 · LRU Cache](https://leetcode.com/problems/lru-cache/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 155 · Min Stack](https://leetcode.com/problems/min-stack/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 173 · Binary Search Tree Iterator](https://leetcode.com/problems/binary-search-tree-iterator/) — Medium · `TI150`
- [ ] [LC 355 · Design Twitter](https://leetcode.com/problems/design-twitter/) — Medium · `NC150`
- [ ] [LC 362 · Design Hit Counter](https://leetcode.com/problems/design-hit-counter/) — Medium 🔒 · `G169`
- [ ] [LC 380 · Insert Delete GetRandom O(1)](https://leetcode.com/problems/insert-delete-getrandom-o1/) — Medium · `G169` `TI150`
- [ ] [LC 622 · Design Circular Queue](https://leetcode.com/problems/design-circular-queue/) — Medium · `NC250`
- [ ] [LC 981 · Time Based Key-Value Store](https://leetcode.com/problems/time-based-key-value-store/) — Medium · `G75` `NC150`

**Hard** (3)

- [ ] [LC 460 · LFU Cache](https://leetcode.com/problems/lfu-cache/) — Hard · `NC250`
- [ ] [LC 588 · Design In-Memory File System](https://leetcode.com/problems/design-in-memory-file-system/) — Hard 🔒 · `G169`
- [ ] [LC 895 · Maximum Frequency Stack](https://leetcode.com/problems/maximum-frequency-stack/) — Hard · `G169` `NC250`

**Beyond the lists:**

- [ ] [LC 284 · Peeking Iterator](https://leetcode.com/problems/peeking-iterator/) — Medium — cache one element
- [ ] [LC 341 · Flatten Nested List Iterator](https://leetcode.com/problems/flatten-nested-list-iterator/) — Medium — stack of frames, work in `hasNext`
- [ ] [LC 1146 · Snapshot Array](https://leetcode.com/problems/snapshot-array/) — Medium — per-index version lists
- [ ] [LC 1472 · Design Browser History](https://leetcode.com/problems/design-browser-history/) — Medium — array + cursor + logical end
- [ ] [LC 641 · Design Circular Deque](https://leetcode.com/problems/design-circular-deque/) — Medium — ring buffer with two indices
- [ ] [LC 2034 · Stock Price Fluctuation ](https://leetcode.com/problems/stock-price-fluctuation/) — Medium — map + two heaps with lazy deletion
- [ ] [LC 2353 · Design a Food Rating System](https://leetcode.com/problems/design-a-food-rating-system/) — Medium — map of ordered sets
- [ ] [LC 359 · Logger Rate Limiter](https://leetcode.com/problems/logger-rate-limiter/) — Easy 🔒 — last-printed map
- [ ] [LC 381 · Insert Delete GetRandom O(1) - Duplicates allowed](https://leetcode.com/problems/insert-delete-getrandom-o1-duplicates-allowed/) — Hard — value → index set
- [ ] [LC 432 · All O`one Data Structure](https://leetcode.com/problems/all-oone-data-structure/) — Hard — LFU-style buckets for both min and max
- [ ] [LC 1206 · Design Skiplist](https://leetcode.com/problems/design-skiplist/) — Hard — randomised levels
- [ ] [LC 2296 · Design a Text Editor](https://leetcode.com/problems/design-a-text-editor/) — Hard — two stacks around the cursor

## 9. CP counterpart

- [Ordered sets, PBDS and heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md): the library structures these designs compose, and order-statistics trees for "k-th" variants.
- [Randomised algorithms and hashing](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md): randomness quality, hashing pitfalls, skip lists and treaps as randomised designs.
- [Treaps and implicit treaps](../08-Data-Structures/09-treaps-and-implicit-treaps.md): the CP answer to "text editor" and "rope" designs.

CP rarely asks for API-style classes, but it constantly asks for the same compositions inside algorithms (a map plus a heap with lazy deletion, buckets by frequency). The interview-specific part is **API hygiene**: clear method contracts, edge cases (capacity 0, missing keys), and stating per-operation complexity.

## 10. Self-check

1. Why does LRU need a *doubly* linked list, and what does the hash map store?
2. State the LFU invariants and explain when `minFreq` changes.
3. In the randomized set, why does deletion swap with the last element, and what order of updates avoids a bug when the deleted element is the last one?
4. Why can the time-based store use a vector plus binary search instead of a balanced BST?
5. In the Flatten Nested List iterator, why is the work done in `hasNext`?
6. Why does a 300-slot ring buffer count hits correctly for non-decreasing timestamps?
7. What is the cost of `getNewsFeed`, and what is the alternative design with cheaper reads?
8. Why is length-prefix framing robust where delimiter-joining is not?

<details><summary>Answers</summary>

1. Removing an arbitrary node in $O(1)$ needs its predecessor, which a singly linked list cannot give without a scan. The map stores key → node (or a list iterator), so the node is found in $O(1)$.
2. `lists[f]` holds exactly the keys with count $f$, most recent first; each key's stored position points into its list; `minFreq` is the smallest $f$ with a non-empty list. It becomes 1 on every insertion of a new key, and increases by 1 when the touched key was the last key at `minFreq`.
3. Deleting from the end of an array is $O(1)$, and the order of a set's elements does not matter. Update the moved element's index first, then pop the back and erase the deleted key, so that when they are the same element the erase is the last word.
4. Timestamps arrive in increasing order, so appending keeps each per-key vector sorted, and a floor query is a binary search.
5. Empty lists (at any depth) mean that "is there another integer?" requires advancing past them. Doing that in `hasNext`, and calling it from `next`, makes both correct and idempotent.
6. Slot `t % 300` only ever holds seconds congruent to $t$ modulo 300. If it holds a different second when $t$ arrives, that second is $\le t - 300$ and no longer in any future window, so it is safe to overwrite. A query counts the slots whose second is in $(t - 300, t]$.
7. $O(F + 10 \log F)$ for $F$ followees (heap merge). Fan-out on write pushes each new tweet into every follower's precomputed feed: $O(1)$ reads, $O(\text{followers})$ writes.
8. The decoder never searches for a delimiter inside the content. It reads a length and takes exactly that many characters, so content may contain any characters, including the separator and digits.

</details>
