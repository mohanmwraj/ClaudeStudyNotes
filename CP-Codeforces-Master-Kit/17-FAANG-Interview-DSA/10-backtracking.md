# Backtracking

> **Band:** 🟢 1200 – 🔵 1700 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [recursion, brute force and backtracking (CP)](../01-Foundations/04-recursion-brute-force-and-backtracking.md), [trees](07-trees-and-bst.md)
> **You can say you know this when:** you can write subsets, permutations and combinations from one template, deduplicate with "skip equal siblings", state the size of the search tree as the complexity, and add pruning that you can justify.

Backtracking is **exhaustive search over a decision tree**, done depth-first so that only one partial solution exists in memory at a time. Each recursive call makes one decision, recurses, then undoes the decision ("choose → explore → unchoose"). Interview problems ask you to enumerate all subsets, permutations, combinations or placements, or to find one that satisfies constraints. The skill being graded is a clean recursion with correct state restoration and pruning.

## 1. First principles — why this works

### 1.1 Every enumeration is a tree of decisions

Write down what the $i$-th level of the recursion decides:

| Problem | Level $i$ decides | Branching | Leaves |
|---|---|---|---|
| subsets | include element $i$ or not | 2 | $2^n$ |
| permutations | which unused element goes in position $i$ | $n - i$ | $n!$ |
| combinations $\binom{n}{k}$ | the next element, larger than the previous one | shrinking | $\binom{n}{k}$ |
| combination sum (reuse allowed) | the next candidate index $\ge$ the previous one | up to $m$ | number of combinations |
| N-Queens | the column of the queen in row $i$ | $\le n$, pruned by attacks | solutions |
| word search | the next neighbouring cell | $\le 3$ after the first step | paths |

The complexity is (number of nodes in the tree) × (work per node). Enumeration problems cannot beat the output size, so $O(n \cdot 2^n)$ for subsets and $O(n \cdot n!)$ for permutations are optimal. Say so: interviewers want to hear that you know it is optimal, not "exponential, sorry".

### 1.2 One mutable state, restored on the way back

Instead of copying the partial solution into every call ($O(n)$ per call), keep one mutable `path` (and `used` flags, a board, a visited mark). Modify it before recursing and restore it immediately after. The invariant is: **when a call returns, the state is exactly as it was when the call started.** Copy only at the leaves, when recording an answer.

### 1.3 Ordering kills duplicates

Two kinds of duplicates appear:

- **Same set, different order** (`[2,3]` and `[3,2]` in combination sum): force a canonical order by only choosing indices $\ge$ the last chosen one (`start` parameter).
- **Equal values in the input** (`[1,2,2]` in Subsets II): sort the input, and at a given tree level skip a candidate equal to the previous candidate *at the same level* (`if (i > start && a[i] == a[i-1]) continue`). Choosing the first copy at a level already explores every subtree the second copy would produce.

### 1.4 Pruning

Prune when a partial state provably cannot lead to an answer: remaining target negative (with positive candidates, sort them and `break`), a queen attacked, a word prefix absent from the trie, remaining elements too few to fill $k$ slots. Each prune must be a sound implication. Pruning does not change worst-case bounds in general, but in practice it changes running times by orders of magnitude.

## 2. Counts and complexities

| Object | Count | Enumeration cost |
|---|---|---|
| subsets of $n$ | $2^n$ | $O(n 2^n)$ |
| $k$-subsets | $\binom{n}{k}$ | $O(k \binom{n}{k})$ |
| permutations | $n!$ | $O(n \cdot n!)$ |
| permutations of a multiset | $\frac{n!}{\prod c_i!}$ | with dedup, $O(n \cdot \text{count})$ |
| balanced parentheses with $n$ pairs | Catalan $C_n = \frac{1}{n+1}\binom{2n}{n}$ | $O(n C_n)$ |
| phone letter combinations | $\le 4^{L}$ | $O(L \cdot 4^L)$ |
| N-Queens solutions | 1, 0, 0, 2, 10, 4, 40, 92 for $n = 1..8$ | well below $n!$ with pruning |
| word search paths | $\le RC \cdot 4 \cdot 3^{L-1}$ | |

Feasibility rule of thumb for interviews: $2^n$ is fine up to $n \approx 20$, $n!$ up to $n \approx 10$. Beyond that, look for DP ([file 13](13-dynamic-programming-1d.md)) or bitmask DP.

## 3. Reusable templates (C++ and Java)

Subsets, permutations and combinations from one skeleton, with the "skip equal siblings" deduplication (sort the input first).

```cpp
// Subsets with duplicates allowed in the input (LC 90): sort first.
void subsetsDedup(const vector<int>& a, int start, vector<int>& path, vector<vector<int>>& out) {
    out.push_back(path);                                   // every node is a subset
    for (int i = start; i < (int)a.size(); ++i) {
        if (i > start && a[i] == a[i - 1]) continue;       // same value at the same level: skip
        path.push_back(a[i]);                              // choose
        subsetsDedup(a, i + 1, path, out);                 // explore
        path.pop_back();                                   // unchoose
    }
}

// Permutations with duplicates allowed (LC 47): sort first, use flags.
void permsDedup(const vector<int>& a, vector<bool>& used, vector<int>& path, vector<vector<int>>& out) {
    if (path.size() == a.size()) { out.push_back(path); return; }
    for (int i = 0; i < (int)a.size(); ++i) {
        if (used[i]) continue;
        if (i > 0 && a[i] == a[i - 1] && !used[i - 1]) continue;   // equal copies are used left to right
        used[i] = true; path.push_back(a[i]);
        permsDedup(a, used, path, out);
        path.pop_back(); used[i] = false;
    }
}

// All k-combinations of 1..n (LC 77), pruning when too few numbers remain.
void combine(int n, int k, int start, vector<int>& path, vector<vector<int>>& out) {
    if ((int)path.size() == k) { out.push_back(path); return; }
    for (int x = start; x <= n - (k - (int)path.size()) + 1; ++x) {   // leave room for the rest
        path.push_back(x);
        combine(n, k, x + 1, path, out);
        path.pop_back();
    }
}
```

```java
static void subsetsDedup(int[] a, int start, Deque<Integer> path, List<List<Integer>> out) {
    out.add(new ArrayList<>(path));
    for (int i = start; i < a.length; i++) {
        if (i > start && a[i] == a[i - 1]) continue;
        path.addLast(a[i]);
        subsetsDedup(a, i + 1, path, out);
        path.removeLast();
    }
}

static void permsDedup(int[] a, boolean[] used, Deque<Integer> path, List<List<Integer>> out) {
    if (path.size() == a.length) { out.add(new ArrayList<>(path)); return; }
    for (int i = 0; i < a.length; i++) {
        if (used[i]) continue;
        if (i > 0 && a[i] == a[i - 1] && !used[i - 1]) continue;
        used[i] = true; path.addLast(a[i]);
        permsDedup(a, used, path, out);
        path.removeLast(); used[i] = false;
    }
}

static void combine(int n, int k, int start, Deque<Integer> path, List<List<Integer>> out) {
    if (path.size() == k) { out.add(new ArrayList<>(path)); return; }
    for (int x = start; x <= n - (k - path.size()) + 1; x++) {
        path.addLast(x);
        combine(n, k, x + 1, path, out);
        path.removeLast();
    }
}
```

Bitmask enumeration is the iterative alternative for subsets when $n \le 20$:

```cpp
vector<vector<int>> subsetsByMask(const vector<int>& a) {
    int n = a.size();
    vector<vector<int>> out;
    for (int mask = 0; mask < (1 << n); ++mask) {
        vector<int> s;
        for (int i = 0; i < n; ++i) if (mask >> i & 1) s.push_back(a[i]);
        out.push_back(s);
    }
    return out;
}
```

```java
static List<List<Integer>> subsetsByMask(int[] a) {
    int n = a.length;
    List<List<Integer>> out = new ArrayList<>();
    for (int mask = 0; mask < (1 << n); mask++) {
        List<Integer> s = new ArrayList<>();
        for (int i = 0; i < n; i++) if ((mask >> i & 1) == 1) s.add(a[i]);
        out.add(s);
    }
    return out;
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "return **all** subsets / permutations / combinations / partitions / placements" | backtracking; the output size sets the complexity |
| small $n$ ($\le 15$–$20$) and "all valid" or "any valid arrangement" | backtracking with pruning (or bitmask DP if only a count or optimum is needed) |
| "generate all valid parentheses / IP addresses / expressions" | build left to right with a validity counter, prune invalid prefixes |
| grid + word + adjacency, "cells used once" | DFS with in-place visited marking, restored on return |
| constraint placement (queens, sudoku) | row-by-row (or cell-by-cell) choice with $O(1)$ conflict checks via sets or bitmasks |
| duplicates in the input and "unique results" | sort + skip equal siblings |
| "count the number of …" with overlapping subproblems | not backtracking: memoise or DP |
| "partition into $k$ equal-sum subsets" | backtracking over buckets with strong pruning (sort descending, skip equal bucket states), or bitmask DP |

## 5. Worked examples

Drivers print the results in a canonical (sorted) order so the tests do not depend on enumeration order. Each list is printed in LeetCode's `[a,b]` format.

### Example 1 — Subsets · Medium

- **Source:** [LC 78 · Subsets](https://leetcode.com/problems/subsets/) — Medium · `G75` `NC150`
- **Difficulty:** LeetCode Medium (≈ 1100 CF, est.)
- **Problem:** return all subsets of $n \le 10$ **distinct** integers.
- **Thinking from first principles:** each element is in or out, so there are $2^n$ subsets. Two equivalent recursions exist. The *binary* tree asks "take $a_i$?" at depth $i$ and records at the leaves. The *start-index* tree records at every node and lets each node choose the next element from `start` onward. The second extends directly to Subsets II and combinations, so learn it. The output has $2^n$ subsets of average size $n/2$, so $O(n 2^n)$ is optimal.

<details><summary>Solution</summary>

Start-index recursion: every node of the tree is a distinct subset (in increasing index order), and every subset appears exactly once. Time $O(n 2^n)$, recursion depth $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<vector<int>> subsets(vector<int>& nums) {
        vector<vector<int>> out;
        vector<int> path;
        dfs(nums, 0, path, out);
        return out;
    }
private:
    void dfs(const vector<int>& a, int start, vector<int>& path, vector<vector<int>>& out) {
        out.push_back(path);                       // the current node is a subset
        for (int i = start; i < (int)a.size(); ++i) {
            path.push_back(a[i]);
            dfs(a, i + 1, path, out);
            path.pop_back();
        }
    }
};

int main() {
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    auto res = Solution().subsets(a);
    for (auto& s : res) sort(s.begin(), s.end());
    sort(res.begin(), res.end());
    cout << res.size() << '\n';
    for (auto& s : res) {
        cout << '[';
        for (size_t i = 0; i < s.size(); ++i) cout << (i ? "," : "") << s[i];
        cout << "]\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public List<List<Integer>> subsets(int[] nums) {
        List<List<Integer>> out = new ArrayList<>();
        dfs(nums, 0, new ArrayDeque<>(), out);
        return out;
    }
    private void dfs(int[] a, int start, Deque<Integer> path, List<List<Integer>> out) {
        out.add(new ArrayList<>(path));
        for (int i = start; i < a.length; i++) {
            path.addLast(a[i]);
            dfs(a, i + 1, path, out);
            path.removeLast();
        }
    }
}

public class Main {
    static int compareLists(List<Integer> x, List<Integer> y) {
        for (int i = 0; i < Math.min(x.size(), y.size()); i++) {
            int c = Integer.compare(x.get(i), y.get(i));
            if (c != 0) return c;
        }
        return Integer.compare(x.size(), y.size());
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        List<List<Integer>> res = new Solution().subsets(a);
        for (List<Integer> s : res) Collections.sort(s);
        res.sort(Main::compareLists);
        StringBuilder sb = new StringBuilder().append(res.size()).append('\n');
        for (List<Integer> s : res) {
            sb.append('[');
            for (int i = 0; i < s.size(); i++) sb.append(i > 0 ? "," : "").append(s.get(i));
            sb.append("]\n");
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
3
1 2 3
out:
8
[]
[1]
[1,2]
[1,2,3]
[1,3]
[2]
[2,3]
[3]
-->
<!-- test
in:
1
0
out:
2
[]
[0]
-->

### Example 2 — Permutations · Medium

- **Source:** [LC 46 · Permutations](https://leetcode.com/problems/permutations/) — Medium · `G75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1100 CF, est.)
- **Problem:** all permutations of $n \le 6$ distinct integers.
- **Thinking from first principles:** position $i$ can hold any element not used in positions $0..i-1$. Track usage with a boolean array (clear and easy to extend to duplicates), or swap elements into place in the array itself ($a[i] \leftrightarrow a[j]$ for $j \ge i$, recurse, swap back), which needs no extra arrays. Both explore $n!$ leaves, with $O(n)$ work each to copy the result.

<details><summary>Solution</summary>

Swap-based recursion. Invariant: `a[0..i-1]` is the fixed prefix, and `a[i..n-1]` holds exactly the unused elements. Time $O(n \cdot n!)$, depth $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<vector<int>> permute(vector<int>& nums) {
        vector<vector<int>> out;
        dfs(nums, 0, out);
        return out;
    }
private:
    void dfs(vector<int>& a, int i, vector<vector<int>>& out) {
        if (i == (int)a.size()) { out.push_back(a); return; }
        for (int j = i; j < (int)a.size(); ++j) {
            swap(a[i], a[j]);                    // put a[j] at position i
            dfs(a, i + 1, out);
            swap(a[i], a[j]);                    // restore
        }
    }
};

int main() {
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    auto res = Solution().permute(a);
    sort(res.begin(), res.end());
    cout << res.size() << '\n';
    for (auto& p : res) {
        cout << '[';
        for (size_t i = 0; i < p.size(); ++i) cout << (i ? "," : "") << p[i];
        cout << "]\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public List<List<Integer>> permute(int[] nums) {
        List<List<Integer>> out = new ArrayList<>();
        dfs(nums, 0, out);
        return out;
    }
    private void dfs(int[] a, int i, List<List<Integer>> out) {
        if (i == a.length) {
            List<Integer> p = new ArrayList<>(a.length);
            for (int x : a) p.add(x);
            out.add(p);
            return;
        }
        for (int j = i; j < a.length; j++) {
            int t = a[i]; a[i] = a[j]; a[j] = t;
            dfs(a, i + 1, out);
            t = a[i]; a[i] = a[j]; a[j] = t;
        }
    }
}

public class Main {
    static int compareLists(List<Integer> x, List<Integer> y) {
        for (int i = 0; i < Math.min(x.size(), y.size()); i++) {
            int c = Integer.compare(x.get(i), y.get(i));
            if (c != 0) return c;
        }
        return Integer.compare(x.size(), y.size());
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        List<List<Integer>> res = new Solution().permute(a);
        res.sort(Main::compareLists);
        StringBuilder sb = new StringBuilder().append(res.size()).append('\n');
        for (List<Integer> p : res) {
            sb.append('[');
            for (int i = 0; i < p.size(); i++) sb.append(i > 0 ? "," : "").append(p.get(i));
            sb.append("]\n");
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
3
1 2 3
out:
6
[1,2,3]
[1,3,2]
[2,1,3]
[2,3,1]
[3,1,2]
[3,2,1]
-->
<!-- test
in:
1
5
out:
1
[5]
-->
<!-- test
in:
2
0 -1
out:
2
[-1,0]
[0,-1]
-->

### Example 3 — Combination Sum · Medium

- **Source:** [LC 39 · Combination Sum](https://leetcode.com/problems/combination-sum/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1300 CF, est.)
- **Problem:** distinct candidates in $[2, 40]$ ($\le 30$ of them) and a target $\le 40$. Return every multiset of candidates (each usable unlimited times) summing to the target.
- **Thinking from first principles:** to avoid `[2,3]` vs `[3,2]`, generate each multiset in non-decreasing index order: after choosing candidate $i$, the next choice is again from $i$ onward (reuse allowed, so $i$, not $i+1$). Sort the candidates so that once `candidates[i] > remaining` every later one is too, and `break` instead of `continue`. If only the **count** were asked, this would be a knapsack DP ([file 14](14-dynamic-programming-2d.md)). Enumeration needs the search.

<details><summary>Solution</summary>

The search tree is bounded by the output size times the depth ($\le \text{target} / \min$). Time $O(\text{\#results} \cdot \text{target}/\min + \text{pruned branches})$. The driver prints the combinations in sorted order.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<vector<int>> combinationSum(vector<int>& candidates, int target) {
        sort(candidates.begin(), candidates.end());
        vector<vector<int>> out;
        vector<int> path;
        dfs(candidates, 0, target, path, out);
        return out;
    }
private:
    void dfs(const vector<int>& c, int start, int remaining, vector<int>& path, vector<vector<int>>& out) {
        if (remaining == 0) { out.push_back(path); return; }
        for (int i = start; i < (int)c.size(); ++i) {
            if (c[i] > remaining) break;              // sorted: every later candidate is too big
            path.push_back(c[i]);
            dfs(c, i, remaining - c[i], path, out);   // i, not i + 1: reuse allowed
            path.pop_back();
        }
    }
};

int main() {
    int n, target;
    cin >> n >> target;
    vector<int> c(n);
    for (int& x : c) cin >> x;
    auto res = Solution().combinationSum(c, target);
    sort(res.begin(), res.end());
    cout << res.size() << '\n';
    for (auto& s : res) {
        cout << '[';
        for (size_t i = 0; i < s.size(); ++i) cout << (i ? "," : "") << s[i];
        cout << "]\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public List<List<Integer>> combinationSum(int[] candidates, int target) {
        Arrays.sort(candidates);
        List<List<Integer>> out = new ArrayList<>();
        dfs(candidates, 0, target, new ArrayDeque<>(), out);
        return out;
    }
    private void dfs(int[] c, int start, int remaining, Deque<Integer> path, List<List<Integer>> out) {
        if (remaining == 0) { out.add(new ArrayList<>(path)); return; }
        for (int i = start; i < c.length; i++) {
            if (c[i] > remaining) break;
            path.addLast(c[i]);
            dfs(c, i, remaining - c[i], path, out);
            path.removeLast();
        }
    }
}

public class Main {
    static int compareLists(List<Integer> x, List<Integer> y) {
        for (int i = 0; i < Math.min(x.size(), y.size()); i++) {
            int c = Integer.compare(x.get(i), y.get(i));
            if (c != 0) return c;
        }
        return Integer.compare(x.size(), y.size());
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), target = in.nextInt();
        int[] c = new int[n];
        for (int i = 0; i < n; i++) c[i] = in.nextInt();
        List<List<Integer>> res = new Solution().combinationSum(c, target);
        res.sort(Main::compareLists);
        StringBuilder sb = new StringBuilder().append(res.size()).append('\n');
        for (List<Integer> s : res) {
            sb.append('[');
            for (int i = 0; i < s.size(); i++) sb.append(i > 0 ? "," : "").append(s.get(i));
            sb.append("]\n");
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
4 7
2 3 6 7
out:
2
[2,2,3]
[7]
-->
<!-- test
in:
3 8
2 3 5
out:
3
[2,2,2,2]
[2,3,3]
[3,5]
-->
<!-- test
in:
1 1
2
out:
0
-->

### Example 4 — N-Queens · Hard

- **Source:** [LC 51 · N-Queens](https://leetcode.com/problems/n-queens/) — Hard · `G169` `NC150`
- **Difficulty:** LeetCode Hard (≈ 1500 CF, est.)
- **Problem:** place $n \le 9$ queens on an $n \times n$ board so that no two attack each other. Return all boards.
- **Thinking from first principles:** brute force over all $\binom{n^2}{n}$ placements is hopeless. Two facts shrink it. (1) Exactly one queen per row, so recurse row by row and choose a column: at most $n^n$, and with "one per column" at most $n!$. (2) Conflicts are checked in $O(1)$ with three occupancy sets: columns, "\" diagonals (constant $r - c$) and "/" diagonals (constant $r + c$). A placement is safe iff its column and both diagonals are free. Most branches die within a few rows.

<details><summary>Solution</summary>

State: `cols`, `diag1[r - c + n - 1]`, `diag2[r + c]` and the board rows. The `+ n - 1` offset keeps the index non-negative. Choose, recurse into the next row, unchoose. Search is $O(n!)$ in the worst case (much less in practice), plus $O(n^2)$ per solution to copy the board. The driver prints the number of boards and then each board's rows, boards in sorted order.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    vector<vector<string>> solveNQueens(int n) {
        this->n = n;
        board.assign(n, string(n, '.'));
        cols.assign(n, false);
        diag1.assign(2 * n - 1, false);
        diag2.assign(2 * n - 1, false);
        out.clear();
        place(0);
        return out;
    }
private:
    int n = 0;
    vector<string> board;
    vector<bool> cols, diag1, diag2;          // diag1: r - c constant, diag2: r + c constant
    vector<vector<string>> out;
    void place(int r) {
        if (r == n) { out.push_back(board); return; }
        for (int c = 0; c < n; ++c) {
            if (cols[c] || diag1[r - c + n - 1] || diag2[r + c]) continue;   // attacked
            cols[c] = diag1[r - c + n - 1] = diag2[r + c] = true;
            board[r][c] = 'Q';
            place(r + 1);
            board[r][c] = '.';
            cols[c] = diag1[r - c + n - 1] = diag2[r + c] = false;
        }
    }
};

int main() {
    int n;
    cin >> n;
    auto res = Solution().solveNQueens(n);
    sort(res.begin(), res.end());
    cout << res.size() << '\n';
    for (auto& b : res)
        for (auto& row : b) cout << row << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    private int n;
    private char[][] board;
    private boolean[] cols, diag1, diag2;
    private List<List<String>> out;

    public List<List<String>> solveNQueens(int n) {
        this.n = n;
        board = new char[n][n];
        for (char[] row : board) Arrays.fill(row, '.');
        cols = new boolean[n];
        diag1 = new boolean[2 * n - 1];
        diag2 = new boolean[2 * n - 1];
        out = new ArrayList<>();
        place(0);
        return out;
    }

    private void place(int r) {
        if (r == n) {
            List<String> b = new ArrayList<>(n);
            for (char[] row : board) b.add(new String(row));
            out.add(b);
            return;
        }
        for (int c = 0; c < n; c++) {
            if (cols[c] || diag1[r - c + n - 1] || diag2[r + c]) continue;
            cols[c] = diag1[r - c + n - 1] = diag2[r + c] = true;
            board[r][c] = 'Q';
            place(r + 1);
            board[r][c] = '.';
            cols[c] = diag1[r - c + n - 1] = diag2[r + c] = false;
        }
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        List<List<String>> res = new Solution().solveNQueens(n);
        res.sort((x, y) -> {
            for (int i = 0; i < x.size(); i++) {
                int c = x.get(i).compareTo(y.get(i));
                if (c != 0) return c;
            }
            return 0;
        });
        StringBuilder sb = new StringBuilder().append(res.size()).append('\n');
        for (List<String> b : res) for (String row : b) sb.append(row).append('\n');
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
4
out:
2
..Q.
Q...
...Q
.Q..
.Q..
...Q
Q...
..Q.
-->
<!-- test
in:
1
out:
1
Q
-->
<!-- test
in:
3
out:
0
-->

### Example 5 — Word Search · Medium

- **Source:** [LC 79 · Word Search](https://leetcode.com/problems/word-search/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** an $R \times C$ grid of letters ($R, C \le 6$) and a word of length $\le 15$. Can the word be traced through horizontally or vertically adjacent cells, using each cell at most once?
- **Thinking from first principles:** the first letter can start anywhere, and after that each step has at most 3 unvisited neighbours (it cannot go back). So the search tree from one start has $\le 4 \cdot 3^{L-1}$ nodes, and the total is $O(RC \cdot 3^L)$. Mark visited cells *in place* (overwrite with `#`) instead of keeping a separate set, and restore them when unwinding. Cheap prunes that interviewers like: return false if the grid's letter counts cannot cover the word, and search from the rarer end of the word (reverse the word if its last letter is rarer than its first).

<details><summary>Solution</summary>

`dfs(r, c, i)`: does the suffix `word[i..]` start at cell `(r, c)`? Check bounds and the letter, then mark, recurse on 4 neighbours, unmark. Time $O(RC \cdot 3^L)$, space $O(L)$ recursion. The driver reads `R C`, the rows and the word.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    bool exist(vector<vector<char>>& board, string word) {
        R = board.size();
        C = board[0].size();
        for (int r = 0; r < R; ++r)
            for (int c = 0; c < C; ++c)
                if (dfs(board, word, r, c, 0)) return true;
        return false;
    }
private:
    int R = 0, C = 0;
    bool dfs(vector<vector<char>>& b, const string& w, int r, int c, int i) {
        if (r < 0 || r >= R || c < 0 || c >= C || b[r][c] != w[i]) return false;
        if (i + 1 == (int)w.size()) return true;
        char saved = b[r][c];
        b[r][c] = '#';                                    // visited on the current path
        bool found = dfs(b, w, r + 1, c, i + 1) || dfs(b, w, r - 1, c, i + 1) ||
                     dfs(b, w, r, c + 1, i + 1) || dfs(b, w, r, c - 1, i + 1);
        b[r][c] = saved;                                  // restore before returning
        return found;
    }
};

int main() {
    int R, C;
    cin >> R >> C;
    vector<vector<char>> board(R, vector<char>(C));
    for (int r = 0; r < R; ++r) {
        string row;
        cin >> row;
        for (int c = 0; c < C; ++c) board[r][c] = row[c];
    }
    string word;
    cin >> word;
    cout << (Solution().exist(board, word) ? "true" : "false") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    private int R, C;
    public boolean exist(char[][] board, String word) {
        R = board.length;
        C = board[0].length;
        for (int r = 0; r < R; r++)
            for (int c = 0; c < C; c++)
                if (dfs(board, word, r, c, 0)) return true;
        return false;
    }
    private boolean dfs(char[][] b, String w, int r, int c, int i) {
        if (r < 0 || r >= R || c < 0 || c >= C || b[r][c] != w.charAt(i)) return false;
        if (i + 1 == w.length()) return true;
        char saved = b[r][c];
        b[r][c] = '#';
        boolean found = dfs(b, w, r + 1, c, i + 1) || dfs(b, w, r - 1, c, i + 1)
                     || dfs(b, w, r, c + 1, i + 1) || dfs(b, w, r, c - 1, i + 1);
        b[r][c] = saved;
        return found;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int R = in.nextInt(), C = in.nextInt();
        char[][] board = new char[R][];
        for (int r = 0; r < R; r++) board[r] = in.next().toCharArray();
        String word = in.next();
        System.out.println(new Solution().exist(board, word));
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
3 4
ABCE
SFCS
ADEE
ABCCED
out:
true
-->
<!-- test
in:
3 4
ABCE
SFCS
ADEE
SEE
out:
true
-->
<!-- test
in:
3 4
ABCE
SFCS
ADEE
ABCB
out:
false
-->
<!-- test
in:
1 1
A
A
out:
true
-->

## 6. Pitfalls and things to remember

1. **Copy at the leaf, not the reference.** `out.add(path)` in Java stores the same mutable list every time, so all results end up equal (usually empty). Use `new ArrayList<>(path)`.
2. **Restore every piece of state** you modified: path, `used[]`, board cells, diagonal flags. A missing restore shows up only on some branches.
3. **`start` vs `start + 1` vs `0`:** `i + 1` = each element once (subsets, combinations), `i` = reuse allowed (combination sum), `0` with `used[]` = order matters (permutations).
4. **Dedup needs sorting**, and the skip rule is `i > start && a[i] == a[i-1]` (same level). Writing `i > 0` skips valid deeper choices such as `[1,2,2]`.
5. **`break` vs `continue` in pruning:** `break` is valid only when the candidates are sorted, so that every later one is also too large.
6. **Return early on the first success** for decision problems (Word Search). `||` short-circuits, but a loop needs an explicit `return true`.
7. **Recursion depth** is the path length (≤ $n$), which is rarely a problem here. The *output size* is the real limit: $2^{20} \cdot 20$ integers is already 80 MB.
8. **N-Queens diagonal indexing:** `r - c` ranges over $[-(n-1), n-1]$. Offset by `n - 1` or use a hash set.
9. **Strings in Java:** building strings with `+` inside the recursion copies at every level. Use a `StringBuilder` with `setLength` to undo, or a `char[]`.
10. **Counting ≠ enumerating.** If only the number of solutions or the best value is needed and subproblems overlap, memoise (it is DP). Interviewers ask this as a follow-up.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| Subsets → "with duplicates" | sort + skip equal siblings ([LC 90 · Subsets II](https://leetcode.com/problems/subsets-ii/) — Medium) |
| Permutations → "with duplicates" | sort + `used[]` + skip `a[i] == a[i-1] && !used[i-1]` ([LC 47 · Permutations II](https://leetcode.com/problems/permutations-ii/) — Medium) |
| → "next permutation in place" / "k-th permutation" | the standard suffix algorithm ([file 02](02-arrays-hashing-and-prefix-sums.md)); factorial number system for the $k$-th |
| Combination sum → "each candidate once, duplicates in the input" | `i + 1` and skip equal siblings ([LC 40 · Combination Sum II](https://leetcode.com/problems/combination-sum-ii/) — Medium) |
| → "only count the combinations" | unbounded knapsack DP, $O(m \cdot T)$ ([LC 377 · Combination Sum IV](https://leetcode.com/problems/combination-sum-iv/) — Medium counts ordered sequences) |
| N-Queens → "only count, as fast as possible" | bitmask version: `cols`, `d1`, `d2` as integers, `avail = ~(cols|d1|d2) & full`, iterate the lowest bit ([LC 52 · N-Queens II](https://leetcode.com/problems/n-queens-ii/) — Hard) |
| Word Search → "many words" | trie of words + one DFS ([Word Search II](08-tries.md)) |
| "Can you make it iterative?" | explicit stack of (state, next choice index), or bitmask enumeration for subsets |
| "What is the complexity, exactly?" | count the nodes of the decision tree (e.g. $\sum_{k} n!/(n-k)! \approx e \cdot n!$ for permutations) times the work per node |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium.

**Easy** (1)

- [ ] [LC 1863 · Sum of All Subset XOR Totals](https://leetcode.com/problems/sum-of-all-subset-xor-totals/) — Easy · `NC250`

**Medium** (13)

- [ ] [LC 17 · Letter Combinations of a Phone Number](https://leetcode.com/problems/letter-combinations-of-a-phone-number/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 22 · Generate Parentheses](https://leetcode.com/problems/generate-parentheses/) — Medium · `G169` `NC150` `TI150`
- [ ] [LC 39 · Combination Sum](https://leetcode.com/problems/combination-sum/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 40 · Combination Sum II](https://leetcode.com/problems/combination-sum-ii/) — Medium · `NC150`
- [ ] [LC 46 · Permutations](https://leetcode.com/problems/permutations/) — Medium · `G75` `NC150` `TI150`
- [ ] [LC 47 · Permutations II](https://leetcode.com/problems/permutations-ii/) — Medium · `NC250`
- [ ] [LC 77 · Combinations](https://leetcode.com/problems/combinations/) — Medium · `NC250` `TI150`
- [ ] [LC 78 · Subsets](https://leetcode.com/problems/subsets/) — Medium · `G75` `NC150`
- [ ] [LC 79 · Word Search](https://leetcode.com/problems/word-search/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 90 · Subsets II](https://leetcode.com/problems/subsets-ii/) — Medium · `NC150`
- [ ] [LC 131 · Palindrome Partitioning](https://leetcode.com/problems/palindrome-partitioning/) — Medium · `NC150`
- [ ] [LC 473 · Matchsticks to Square](https://leetcode.com/problems/matchsticks-to-square/) — Medium · `NC250`
- [ ] [LC 698 · Partition to K Equal Sum Subsets](https://leetcode.com/problems/partition-to-k-equal-sum-subsets/) — Medium · `NC250`

**Hard** (4)

- [ ] [LC 37 · Sudoku Solver](https://leetcode.com/problems/sudoku-solver/) — Hard · `G169`
- [ ] [LC 51 · N-Queens](https://leetcode.com/problems/n-queens/) — Hard · `G169` `NC150`
- [ ] [LC 52 · N-Queens II](https://leetcode.com/problems/n-queens-ii/) — Hard · `NC250` `TI150`
- [ ] [LC 140 · Word Break II](https://leetcode.com/problems/word-break-ii/) — Hard · `NC250`

**Beyond the lists:**

- [ ] [LC 784 · Letter Case Permutation](https://leetcode.com/problems/letter-case-permutation/) — Medium — binary choice per letter
- [ ] [LC 93 · Restore IP Addresses](https://leetcode.com/problems/restore-ip-addresses/) — Medium — 4 segments, prune by remaining length
- [ ] [LC 216 · Combination Sum III](https://leetcode.com/problems/combination-sum-iii/) — Medium — combinations with a sum constraint
- [ ] [LC 1239 · Maximum Length of a Concatenated String with Unique Characters](https://leetcode.com/problems/maximum-length-of-a-concatenated-string-with-unique-characters/) — Medium — bitmask state
- [ ] [LC 1219 · Path with Maximum Gold](https://leetcode.com/problems/path-with-maximum-gold/) — Medium — grid DFS with restore
- [ ] [LC 2305 · Fair Distribution of Cookies](https://leetcode.com/problems/fair-distribution-of-cookies/) — Medium — buckets + pruning
- [ ] [LC 980 · Unique Paths III](https://leetcode.com/problems/unique-paths-iii/) — Hard — visit every cell exactly once
- [ ] [LC 301 · Remove Invalid Parentheses](https://leetcode.com/problems/remove-invalid-parentheses/) — Hard — minimum removals then enumerate
- [ ] [LC 282 · Expression Add Operators](https://leetcode.com/problems/expression-add-operators/) — Hard — track the last operand for `*`

## 9. CP counterpart

- [Recursion, brute force and backtracking (CP)](../01-Foundations/04-recursion-brute-force-and-backtracking.md): the same template, plus iterating subsets of a mask and generating test brute forces for stress testing.
- [Meet in the middle](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md): when $2^n$ is too slow but $2^{n/2}$ is fine ($n \approx 40$).
- [Bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md): the replacement for backtracking when only a count or optimum over subsets is needed.

In CP, backtracking is mostly a *testing tool* (brute force to stress-test a clever solution). In interviews it is a primary topic, and clean state restoration is what gets graded.

## 10. Self-check

1. What does each level of the recursion decide in subsets, permutations and combination sum?
2. Why is $O(n \cdot 2^n)$ optimal for "all subsets"?
3. Explain the dedup rule `i > start && a[i] == a[i-1]` and why `i > 0` is wrong.
4. In permutations with duplicates, what does `!used[i-1]` enforce?
5. How do you check in $O(1)$ whether a queen at $(r, c)$ is attacked?
6. Why must Word Search restore the cell, and what goes wrong if it does not?
7. When should you switch from backtracking to DP?

<details><summary>Answers</summary>

1. Subsets: the next element to add (or in/out per element). Permutations: which unused element fills position $i$. Combination sum: the next candidate index, at least the previous one.
2. The output itself has $2^n$ subsets with total size $n 2^{n-1}$, so writing it out already costs that much.
3. At one tree level (same `start`), choosing the second equal value generates exactly the subtrees the first one did. `i > start` restricts the skip to siblings. `i > 0` would also forbid using the second copy as a deeper choice, losing `[2,2]`.
4. Equal values are used in left-to-right order: copy $i$ may be placed only if copy $i-1$ is already in the prefix, so each multiset permutation is produced once.
5. Keep boolean arrays for columns, `r - c + n - 1` diagonals and `r + c` anti-diagonals. A position is safe iff all three are free.
6. The marking means "on the current path". Without restoring, cells used by a failed branch stay blocked for other branches and other start cells, giving false negatives.
7. When only a count or an optimum is needed and the same subproblem (state) is reached by many paths: memoise on the state, which is DP.

</details>
