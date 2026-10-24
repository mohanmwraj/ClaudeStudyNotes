# Recursion, brute force and backtracking

> **Band:** 🟢 ≤ 1400 → 🔵 1900 (pruned searches) · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [complexity](01-complexity-and-constraint-reading.md), [bit manipulation](03-bit-manipulation.md)
> **You can say you know this when:** you can generate subsets, permutations and combinations in both languages without a reference, estimate the size of a search tree before writing it, add a pruning rule with a correctness argument, and keep any recursion from overflowing the stack (C++ and Java).

## 1. First principles — why this works

**Recursion is induction run backwards.** To solve an instance, assume you can already solve every *smaller* instance, and describe how to
combine those answers. Correctness is an induction proof: the base cases are right, and each step is right if the smaller calls are.
Complexity is a counting problem: **(number of nodes in the recursion tree) × (work per node)**.

**Brute force is a search over an explicitly described solution space.** Before writing one, describe the space and count it:

| Space | Size | Feasible for |
|---|---|---|
| subsets of $n$ items | $2^n$ | $n \le 20$–$25$ |
| ordered selections / permutations | $n!$ | $n \le 10$–$11$ |
| $k$-element combinations | $\binom nk$ | e.g. $\binom{30}{5}\approx1.4\cdot10^5$ |
| assignments of $c$ values to $n$ slots | $c^n$ | $3^{12}\approx5.3\cdot10^5$, $4^{10}\approx10^6$ |
| distinct rearrangements of a multiset | $\frac{n!}{c_1!\cdots c_k!}$ | strings of length $\le 8$–$10$ |

If the count is below roughly $10^7$–$10^8$ (times the per-candidate check), the brute force **is** the solution. If not, the count tells you
how much the search has to be cut.

**Backtracking** builds a candidate one decision at a time (a DFS over *partial* solutions) and abandons a partial solution as soon as it
cannot be completed. The template is always *choose → recurse → un-choose*, with the state restored exactly on the way back. Its power
comes from **pruning**: if a rule removes a subtree near the root, it removes exponentially many leaves. Two kinds of pruning:

1. **Feasibility pruning** — the partial solution already violates a constraint, or can be proved impossible to complete (Example 6: a
   path that splits the unvisited cells into two regions can never visit both).
2. **Branch and bound** — for optimisation, keep the best answer found so far and an *optimistic bound* on what the current subtree can
   achieve; if the bound cannot beat the best, skip the subtree. The bound must be optimistic (never worse than the truth), otherwise you
   prune the optimum. Good move ordering (try promising choices first) makes the best answer good early, which makes the bound bite more.

**Divide and conquer** is recursion where the subproblems are disjoint pieces (halves of an array). Its cost is a recurrence such as
$T(n) = 2T(n/2) + O(n) = O(n\log n)$ (Example 5; recurrences in [complexity](01-complexity-and-constraint-reading.md)).

**Meet in the middle** splits a $2^n$ search into two $2^{n/2}$ searches and combines them by sorting/hashing — the step after brute force
when $n\approx 40$ ([meet in the middle](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md)). When the same
subproblem is reached by many paths, memoise it: that is dynamic programming ([DP first principles](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md)).

**Brute force is also your best debugging tool.** A slow but obviously correct solution plus a random generator finds the bug in your fast
solution in minutes (stress testing — scripts in [environment & templates](../00-Roadmap-and-Strategy/06-environment-templates-cpp-java.md),
workflow in [practice methodology](../00-Roadmap-and-Strategy/03-practice-methodology.md)). Strong contestants write the brute force
*first* whenever the fast solution is subtle.

## 2. Formulas, definitions and identities

- **Recursion-tree sizes.** Include/exclude subset recursion: $2^{n+1}-1$ nodes ($2^n$ leaves). Permutation recursion (choose the next
  unused element): $\sum_{k=0}^{n}\frac{n!}{(n-k)!} = n!\sum_{j=0}^{n}\frac{1}{j!} < e\cdot n!$ nodes — so the internal nodes are cheap
  compared with the $n!$ leaves.
- **Recurrences.** $T(n) = T(n-1) + T(n-2) + O(1)$ grows like $\varphi^n$ ($\varphi\approx1.618$) — naive Fibonacci; $T(n) = nT(n-1)+O(1) = O(n!)$;
  $T(n) = 2T(n-1)+O(1) = O(2^n)$; Tower of Hanoi needs exactly $2^n-1$ moves ($H_n = 2H_{n-1}+1$).
- **Multiset permutations.** A string with letter counts $c_1,\dots,c_k$ has $\binom{n}{c_1,\dots,c_k} = \frac{n!}{c_1!\cdots c_k!}$ distinct
  rearrangements — "aabac" has $\frac{5!}{3!\,1!\,1!}=20$.
- **Combinations.** $\binom nk = \binom{n-1}{k-1}+\binom{n-1}{k}$ (the element is in or out) — exactly the recursion that generates them.
- **N-Queens.** Queens at $(r, c)$ and $(r', c')$ attack iff $c=c'$, $r-c = r'-c'$ or $r+c = r'+c'$. Index the diagonals by $r-c+n-1$ and $r+c$
  ($2n-1$ of each). On a free $8\times8$ board there are 92 solutions (standard knowledge, checked by the test of Example 3).
- **Stack usage.** Each call frame stores the return address, saved registers and locals: tens to hundreds of bytes. Depth $10^6$ with
  100-byte frames needs ~100 MB of stack.

## 3. Implementation (C++ and Java)

### 3.1 Subsets, combinations, permutations

```cpp
// All subsets by include/exclude. cur holds the chosen elements.
void subsets(const vector<int>& a, int i, vector<int>& cur, vector<vector<int>>& out) {
    if (i == (int)a.size()) { out.push_back(cur); return; }
    subsets(a, i + 1, cur, out);                 // exclude a[i]
    cur.push_back(a[i]);
    subsets(a, i + 1, cur, out);                 // include a[i]
    cur.pop_back();                              // un-choose: restore the state exactly
}

// All k-combinations of {start, ..., n-1} in lexicographic order.
void combinations(int n, int k, int start, vector<int>& cur, vector<vector<int>>& out) {
    if ((int)cur.size() == k) { out.push_back(cur); return; }
    for (int x = start; x <= n - (k - (int)cur.size()); x++) {   // leave room for the remaining picks
        cur.push_back(x);
        combinations(n, k, x + 1, cur, out);
        cur.pop_back();
    }
}

// All permutations of a (distinct or not: duplicates handled by skipping equal choices at the same depth).
void permutations(vector<int>& a, vector<char>& used, vector<int>& cur, vector<vector<int>>& out) {
    if (cur.size() == a.size()) { out.push_back(cur); return; }
    for (int i = 0; i < (int)a.size(); i++) {
        if (used[i]) continue;
        if (i > 0 && a[i] == a[i - 1] && !used[i - 1]) continue;  // a must be sorted; avoids duplicate permutations
        used[i] = 1; cur.push_back(a[i]);
        permutations(a, used, cur, out);
        cur.pop_back(); used[i] = 0;
    }
}
```

```java
static void subsets(int[] a, int i, ArrayDeque<Integer> cur, List<List<Integer>> out) {
    if (i == a.length) { out.add(new ArrayList<>(cur)); return; }
    subsets(a, i + 1, cur, out);
    cur.addLast(a[i]);
    subsets(a, i + 1, cur, out);
    cur.removeLast();
}

static void combinations(int n, int k, int start, ArrayDeque<Integer> cur, List<List<Integer>> out) {
    if (cur.size() == k) { out.add(new ArrayList<>(cur)); return; }
    for (int x = start; x <= n - (k - cur.size()); x++) {
        cur.addLast(x);
        combinations(n, k, x + 1, cur, out);
        cur.removeLast();
    }
}

static void permutations(int[] a, boolean[] used, ArrayDeque<Integer> cur, List<List<Integer>> out) {
    if (cur.size() == a.length) { out.add(new ArrayList<>(cur)); return; }
    for (int i = 0; i < a.length; i++) {
        if (used[i]) continue;
        if (i > 0 && a[i] == a[i - 1] && !used[i - 1]) continue;   // a sorted
        used[i] = true; cur.addLast(a[i]);
        permutations(a, used, cur, out);
        cur.removeLast(); used[i] = false;
    }
}
```

For "all permutations in lexicographic order" the library way is a sorted array plus `next_permutation` (C++) or the Java
`nextPermutation` written in [STL & Collections §3.3](02-cpp-stl-and-java-collections.md); it also handles duplicates.

### 3.2 Branch and bound: closest subset sum to a target

Sort descending (big items first make good answers early), keep suffix sums, and prune with two optimistic facts: the reachable sums from
here lie in $[\text{cur}, \text{cur} + \text{suffix}]$.

```cpp
struct ClosestSubsetSum {
    vector<long long> a, suf;
    long long target, best;
    void dfs(int i, long long cur) {
        best = min(best, llabs(cur - target));
        if (i == (int)a.size() || best == 0) return;
        if (cur > target) return;                                   // adding more only moves further away
        if (cur + suf[i] <= target) { best = min(best, target - cur - suf[i]); return; }   // take everything left
        dfs(i + 1, cur + a[i]);
        dfs(i + 1, cur);
    }
    long long solve(vector<long long> v, long long t) {
        sort(v.rbegin(), v.rend());
        a = v; target = t; best = LLONG_MAX;
        suf.assign(a.size() + 1, 0);
        for (int i = (int)a.size() - 1; i >= 0; i--) suf[i] = suf[i + 1] + a[i];
        dfs(0, 0);
        return best;
    }
};
```

```java
static final class ClosestSubsetSum {
    long[] a, suf;
    long target, best;
    void dfs(int i, long cur) {
        best = Math.min(best, Math.abs(cur - target));
        if (i == a.length || best == 0) return;
        if (cur > target) return;
        if (cur + suf[i] <= target) { best = Math.min(best, target - cur - suf[i]); return; }
        dfs(i + 1, cur + a[i]);
        dfs(i + 1, cur);
    }
    long solve(long[] v, long t) {                     // values must be non-negative
        a = v.clone();
        Arrays.sort(a);
        for (int i = 0, j = a.length - 1; i < j; i++, j--) { long x = a[i]; a[i] = a[j]; a[j] = x; }
        target = t; best = Long.MAX_VALUE;
        suf = new long[a.length + 1];
        for (int i = a.length - 1; i >= 0; i--) suf[i] = suf[i + 1] + a[i];
        dfs(0, 0);
        return best;
    }
}
```

Both prunings are safe because all values are non-negative: once `cur > target` every completion is even larger, and if taking everything
left still does not exceed the target, that completion is the closest one in the subtree. The worst case is still $O(2^n)$; the pruning
only helps on typical inputs — which is the honest description of every branch-and-bound.

### 3.3 Iterative deepening 🧊

When the answer is a *minimum number of moves* but BFS would store too many states, run a depth-limited DFS for limits $0, 1, 2, \dots$.
Each round re-explores the shallower levels, but in a tree with branching factor $b\ge2$ the last level dominates
($\sum_{d\le D} b^d < \frac{b}{b-1} b^D$), so the total is within a constant factor of one search to depth $D$. With an admissible heuristic
this becomes IDA\*. Rare in Codeforces rounds; know it exists.

```cpp
// Generic shape: returns true if a goal is reachable within `limit` more moves.
template <class State, class Expand, class IsGoal>
bool depthLimited(const State& s, int limit, Expand expand, IsGoal isGoal) {
    if (isGoal(s)) return true;
    if (limit == 0) return false;
    for (const State& t : expand(s))
        if (depthLimited(t, limit - 1, expand, isGoal)) return true;
    return false;
}
// for (int lim = 0; ; lim++) if (depthLimited(start, lim, expand, isGoal)) { answer = lim; break; }
```

```java
static <S> boolean depthLimited(S s, int limit, Function<S, List<S>> expand, Predicate<S> isGoal) {
    if (isGoal.test(s)) return true;
    if (limit == 0) return false;
    for (S t : expand.apply(s))
        if (depthLimited(t, limit - 1, expand, isGoal)) return true;
    return false;
}
```

### 3.4 Deep recursion without stack overflow

Codeforces links C++ with a 256 MB stack (`-Wl,--stack=268435456` in its command-lines post) and starts Java with `-Xss64M`; locally
your defaults are much smaller (MinGW's default is about 1–2 MB unless you pass the same linker flag — standard knowledge, not verified
here). In Java, run the solution in a thread with an explicit stack size; this program recurses $n$ levels deep:

```cpp
#include <bits/stdc++.h>
using namespace std;

long long depthSum(int n) { return n == 0 ? 0 : n + depthSum(n - 1); }   // recursion depth n

int main() {
    int n;
    cin >> n;
    cout << depthSum(n) << '\n';      // locally: compile with -Wl,--stack=268435456 to match Codeforces
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static long depthSum(int n) { return n == 0 ? 0 : n + depthSum(n - 1); }

    public static void main(String[] args) throws Exception {
        Thread t = new Thread(null, () -> {
            try {
                BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
                int n = Integer.parseInt(br.readLine().trim());
                System.out.println(depthSum(n));
            } catch (IOException e) {
                throw new UncheckedIOException(e);
            }
        }, "solver", 1 << 28);                       // 256 MB stack for this thread
        t.start();
        t.join();
    }
}
```

<!-- test
in:
1000000
out:
500000500000
-->
<!-- test
in:
0
out:
0
-->

If you would rather not depend on stack size at all, convert the recursion to an explicit stack: push `(node, state)` frames and emulate
"after the children return" with a second visit (shown for tree DFS in [graph BFS/DFS](../09-Graphs/01-graph-representation-bfs-dfs.md)).

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| $n\le 8$–$10$ and "arrange / order" | try all permutations (`next_permutation`) |
| $n\le 15$–$20$ and "choose some" | all $2^n$ subsets, by recursion or bitmask |
| several independent small choices ($\le 3$–$4$ options each, $\le 10$–$12$ slots) | $c^n$ assignments |
| a fixed small board (chess $8\times8$, $7\times7$ grid paths) | backtracking with constraint arrays; pruning decides the running time |
| "minimum number of operations", answer provably small (e.g. $\le 15$) | iterative deepening or BFS over states |
| self-similar definitions ("$s$ is good if one half is … and the other half is good") | divide-and-conquer recursion |
| $n\approx40$ subset problems | meet in the middle |
| the same arguments recur in the search | memoise → DP |
| you are not sure your clever solution is right | write the brute force anyway and stress test |

Often confused: a recursion that recomputes overlapping subproblems (naive Fibonacci, exponential) versus divide and conquer on disjoint
parts (polynomial). Draw two levels of the recursion tree and check whether the same argument appears twice.

## 5. Worked examples (graded)

### Example 1 — Apple Division  ·  ★ ≈1100 (est.)

- **Source:** [CSES 1623 · Apple Division](https://cses.fi/problemset/task/1623)
- **Difficulty:** ≈1100 (est.)
- **Problem:** Split $n\le20$ apples with weights $p_i\le10^9$ into two groups minimising the difference of the group weights.
- **Thinking from first principles:** a split is a subset (the first group), $2^{20}\approx10^6$ of them. Total weight is up to $2\cdot10^{10}$,
  so sums need 64 bits, and a weight-indexed DP is impossible. Symmetry halves the work: apple 0 may be fixed in group 1.

<details><summary>Solution</summary>

Recursively decide each apple's group, carrying the current sum of group 1; at a leaf the difference is $|S - 2\cdot\text{cur}|$. $O(2^n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<long long> p;
long long total, best;

void go(int i, long long cur) {
    if (i == n) { best = min(best, llabs(total - 2 * cur)); return; }
    go(i + 1, cur + p[i]);
    go(i + 1, cur);
}

int main() {
    cin >> n;
    p.resize(n);
    for (auto& x : p) cin >> x;
    total = accumulate(p.begin(), p.end(), 0LL);
    best = LLONG_MAX;
    go(1, p[0]);                         // apple 0 fixed in group 1 (symmetry)
    cout << best << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int n;
    static long[] p;
    static long total, best;

    static void go(int i, long cur) {
        if (i == n) { best = Math.min(best, Math.abs(total - 2 * cur)); return; }
        go(i + 1, cur + p[i]);
        go(i + 1, cur);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        n = in.nextInt();
        p = new long[n];
        for (int i = 0; i < n; i++) { p[i] = in.nextLong(); total += p[i]; }
        best = Long.MAX_VALUE;
        go(1, p[0]);
        System.out.println(best);
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 - (c - '0'); c = read(); }
            return neg ? r : -r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
1
7
out:
7
-->
<!-- test
in:
2
1000000000 1000000000
out:
0
-->
<!-- test
in:
4
1 2 3 4
out:
0
-->
<!-- test
in:
3
1 1 5
out:
3
-->

### Example 2 — Creating Strings  ·  ★ ≈1200 (est.)

- **Source:** [CSES 1622 · Creating Strings](https://cses.fi/problemset/task/1622)
- **Difficulty:** ≈1200 (est.)
- **Problem:** Given a string of length $\le 8$, print the number of distinct rearrangements, then all of them in alphabetical order.
- **Thinking from first principles:** $8! = 40320$ orders at most — tiny. The only issues are duplicates and ordering. Generating all $n!$
  orders and deduplicating with a set works but wastes effort. `next_permutation` on the **sorted** string steps through the *distinct*
  permutations in lexicographic order by construction (it produces the next larger arrangement, and equal letters never create a new one),
  so the count is $\frac{n!}{\prod c_i!}$ automatically.

<details><summary>Solution</summary>

Sort, then loop `do { collect } while (next_permutation)`. Collect into a buffer because the count must be printed first.
$O(\frac{n!}{\prod c_i!}\cdot n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    string s;
    cin >> s;
    sort(s.begin(), s.end());
    vector<string> all;
    do all.push_back(s); while (next_permutation(s.begin(), s.end()));
    string out = to_string(all.size()) + "\n";
    for (auto& t : all) out += t + "\n";
    cout << out;
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static boolean nextPermutation(char[] p) {
        int i = p.length - 2;
        while (i >= 0 && p[i] >= p[i + 1]) i--;
        if (i < 0) return false;
        int j = p.length - 1;
        while (p[j] <= p[i]) j--;
        char t = p[i]; p[i] = p[j]; p[j] = t;
        for (int l = i + 1, r = p.length - 1; l < r; l++, r--) { t = p[l]; p[l] = p[r]; p[r] = t; }
        return true;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        char[] s = br.readLine().trim().toCharArray();
        Arrays.sort(s);
        StringBuilder body = new StringBuilder();
        int count = 0;
        do { body.append(s).append('\n'); count++; } while (nextPermutation(s));
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(count);
        out.print(body);
        out.flush();
    }
}
```

</details>

<!-- test
in:
aab
out:
3
aab
aba
baa
-->
<!-- test
in:
zzzz
out:
1
zzzz
-->
<!-- test
in:
cba
out:
6
abc
acb
bac
bca
cab
cba
-->

### Example 3 — Chessboard and Queens  ·  ★ ≈1300 (est.)

- **Source:** [CSES 1624 · Chessboard and Queens](https://cses.fi/problemset/task/1624)
- **Difficulty:** ≈1300 (est.)
- **Problem:** Place 8 non-attacking queens on an $8\times8$ board where some squares are reserved (no queen may stand there; reserved
  squares do not block attacks). Count the placements.
- **Thinking from first principles:** choosing 8 squares out of 64 is $\binom{64}{8}\approx4.4\cdot10^9$ — too many. But each row holds exactly
  one queen, so place row by row: at most $8^8\approx1.7\cdot10^7$ leaves, and with column/diagonal pruning far fewer (the search visits a few
  thousand nodes). Keep three boolean arrays — columns, "$r-c$" diagonals, "$r+c$" anti-diagonals — so each check is $O(1)$.

<details><summary>Solution</summary>

Backtrack over rows; at row $r$ try every free column $c$ whose column and both diagonals are unused. Choose → recurse → un-choose.

```cpp
#include <bits/stdc++.h>
using namespace std;

string board[8];
bool col[8], diag1[15], diag2[15];       // diag1 index r-c+7, diag2 index r+c
int ways = 0;

void place(int r) {
    if (r == 8) { ways++; return; }
    for (int c = 0; c < 8; c++) {
        if (board[r][c] == '*' || col[c] || diag1[r - c + 7] || diag2[r + c]) continue;
        col[c] = diag1[r - c + 7] = diag2[r + c] = true;
        place(r + 1);
        col[c] = diag1[r - c + 7] = diag2[r + c] = false;
    }
}

int main() {
    for (auto& row : board) cin >> row;
    place(0);
    cout << ways << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static char[][] board = new char[8][];
    static boolean[] col = new boolean[8], diag1 = new boolean[15], diag2 = new boolean[15];
    static int ways = 0;

    static void place(int r) {
        if (r == 8) { ways++; return; }
        for (int c = 0; c < 8; c++) {
            if (board[r][c] == '*' || col[c] || diag1[r - c + 7] || diag2[r + c]) continue;
            col[c] = diag1[r - c + 7] = diag2[r + c] = true;
            place(r + 1);
            col[c] = diag1[r - c + 7] = diag2[r + c] = false;
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        for (int i = 0; i < 8; i++) board[i] = br.readLine().trim().toCharArray();
        place(0);
        System.out.println(ways);
    }
}
```

</details>

<!-- test
in:
........
........
........
........
........
........
........
........
out:
92
-->
<!-- test
in:
........
........
........
********
........
........
........
........
out:
0
-->
<!-- test
in:
*.......
........
........
........
........
........
........
.......*
out:
84
-->

### Example 4 — Preparing Olympiad  ·  ★ 1400

- **Source:** [CF 550B · Preparing Olympiad](https://codeforces.com/problemset/problem/550/B) — 1400
- **Difficulty:** 1400
- **Problem:** $n\le15$ problems with difficulties $c_i\le10^6$. Count subsets of at least two problems whose total difficulty lies in $[l, r]$
  ($r\le10^9$) and whose hardest and easiest problems differ by at least $x$.
- **Thinking from first principles:** $2^{15} = 32768$ subsets — enumerate them all. Carrying the running sum, minimum, maximum and size
  through the recursion makes each leaf check $O(1)$ (the bitmask version recomputes them in $O(n)$ per mask, also fine).

<details><summary>Solution</summary>

Include/exclude recursion with state (count, sum, min, max). $O(2^n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
long long l, r, x;
vector<long long> c;
int answer = 0;

void go(int i, int cnt, long long sum, long long mn, long long mx) {
    if (i == n) {
        if (cnt >= 2 && l <= sum && sum <= r && mx - mn >= x) answer++;
        return;
    }
    go(i + 1, cnt, sum, mn, mx);                                          // skip problem i
    go(i + 1, cnt + 1, sum + c[i], min(mn, c[i]), max(mx, c[i]));         // take problem i
}

int main() {
    cin >> n >> l >> r >> x;
    c.resize(n);
    for (auto& v : c) cin >> v;
    go(0, 0, 0, LLONG_MAX, LLONG_MIN);
    cout << answer << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int n, answer = 0;
    static long l, r, x;
    static long[] c;

    static void go(int i, int cnt, long sum, long mn, long mx) {
        if (i == n) {
            if (cnt >= 2 && l <= sum && sum <= r && mx - mn >= x) answer++;
            return;
        }
        go(i + 1, cnt, sum, mn, mx);
        go(i + 1, cnt + 1, sum + c[i], Math.min(mn, c[i]), Math.max(mx, c[i]));
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        n = in.nextInt(); l = in.nextLong(); r = in.nextLong(); x = in.nextLong();
        c = new long[n];
        for (int i = 0; i < n; i++) c[i] = in.nextLong();
        go(0, 0, 0, Long.MAX_VALUE, Long.MIN_VALUE);
        System.out.println(answer);
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 - (c - '0'); c = read(); }
            return neg ? r : -r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
4 10 20 5
1 5 10 15
out:
5
-->
<!-- test
in:
1 1 10 1
5
out:
0
-->
<!-- test
in:
2 2 2 0
1 1
out:
1
-->

### Example 5 — a-Good String  ·  ★ 1500

- **Source:** [CF 1385D · a-Good String](https://codeforces.com/problemset/problem/1385/D) — 1500
- **Difficulty:** 1500
- **Problem:** A string of length $n = 2^k$ is *c-good* if it is the single letter $c$ (when $n=1$), or one half consists only of $c$ and the other
  half is $(c{+}1)$-good. Given $s$ ($\sum n \le 2\cdot10^5$), find the minimum number of character changes making it 'a'-good.
- **Thinking from first principles:** the definition is already a recursion — turn it into one for the cost. $f(\text{segment}, c)$ =
  $\min$(cost of making the left half all $c$ + $f(\text{right}, c+1)$, cost of making the right half all $c$ + $f(\text{left}, c+1)$). Is it fast? Each call
  does $O(\text{len})$ counting and makes two calls on halves: $T(n) = 2T(n/2) + O(n) = O(n\log n)$. There is no overlap between
  subproblems, so no memoisation is needed — this is divide and conquer, not DP.

<details><summary>Solution</summary>

Recurse on $[l, r)$ with letter $c$; count mismatches in each half directly. Depth $\log_2 n \le 18$. $O(n\log n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;

string s;

int cost(int l, int r, char c) {              // min changes to make s[l, r) c-good
    if (r - l == 1) return s[l] != c;
    int m = (l + r) / 2;
    int leftBad = 0, rightBad = 0;
    for (int i = l; i < m; i++) leftBad += s[i] != c;
    for (int i = m; i < r; i++) rightBad += s[i] != c;
    return min(leftBad + cost(m, r, c + 1), rightBad + cost(l, m, c + 1));
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        int n;
        cin >> n >> s;
        cout << cost(0, n, 'a') << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static char[] s;

    static int cost(int l, int r, char c) {
        if (r - l == 1) return s[l] != c ? 1 : 0;
        int m = (l + r) / 2, leftBad = 0, rightBad = 0;
        for (int i = l; i < m; i++) if (s[i] != c) leftBad++;
        for (int i = m; i < r; i++) if (s[i] != c) rightBad++;
        char d = (char) (c + 1);
        return Math.min(leftBad + cost(m, r, d), rightBad + cost(l, m, d));
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int t = Integer.parseInt(br.readLine().trim());
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        while (t-- > 0) {
            br.readLine();                                  // n (the string's own length is used)
            s = br.readLine().trim().toCharArray();
            out.println(cost(0, s.length, 'a'));
        }
        out.flush();
    }
}
```

</details>

<!-- test
in:
5
1
a
1
z
2
ba
4
aaaa
8
abcdabcd
out:
0
1
0
2
4
-->
<!-- test
in:
1
8
aaaabbcd
out:
0
-->

### Example 6 — Grid Path Description  ·  ★ ≈2000 (est.)

- **Source:** [CSES 1625 · Grid Path Description](https://cses.fi/problemset/task/1625)
- **Difficulty:** ≈2000 (est.) — the difficulty is entirely in the pruning
- **Problem:** Paths in a $7\times7$ grid from the upper-left to the lower-left corner visiting every cell exactly once are described by 48
  letters from `DULR`. Given a 48-character pattern of `D`,`U`,`L`,`R`,`?` (`?` = any), count matching paths.
- **Thinking from first principles:** the plain DFS explores an astronomical number of self-avoiding partial walks. Ask *why a partial path
  can be hopeless before it fails*, and turn each answer into an $O(1)$ check:
  1. **The target is the last cell.** Reaching the lower-left corner before step 48 is a dead end: stop.
  2. **A split.** Suppose the walk arrives at a cell whose neighbours above and below are both blocked (visited or wall) while left and right are
     both free. Since we arrived from one of the vertical neighbours, the path now forms a wall through this cell: the free cells to the left
     and to the right lie in different regions, and a single path cannot visit both and still end at the target. Stop. Same rule rotated
     (left and right blocked, up and down free).
  A border of permanently "visited" cells around the grid makes walls and visited cells the same thing and removes bounds checks.

<details><summary>Solution</summary>

DFS over the walk with the two prunings; follow the pattern letter when it is not `?`. The answer for an all-`?` pattern is 88418 (the number of
such paths, stated in the problem). On a slow shared laptop the all-`?` case took about 1.8 s in C++ and 2.5 s in Java with these two rules;
the classic further speed-up is a third rule — if a free neighbour has only one free neighbour of its own (a dead end), the walk is forced to
go there next — which is left as an exercise.

```cpp
#include <bits/stdc++.h>
using namespace std;

string s;
bool vis[9][9];                       // grid in rows/cols 1..7; border cells are permanently "visited"
long long cnt = 0;
const int DR[4] = {1, -1, 0, 0}, DC[4] = {0, 0, -1, 1};
const char DCH[4] = {'D', 'U', 'L', 'R'};

void dfs(int r, int c, int step) {
    if (r == 7 && c == 1) { if (step == 48) cnt++; return; }       // pruning 1
    if (step == 48) return;
    if (vis[r - 1][c] && vis[r + 1][c] && !vis[r][c - 1] && !vis[r][c + 1]) return;   // pruning 2
    if (vis[r][c - 1] && vis[r][c + 1] && !vis[r - 1][c] && !vis[r + 1][c]) return;
    vis[r][c] = true;
    for (int d = 0; d < 4; d++) {
        if (s[step] != '?' && s[step] != DCH[d]) continue;
        int nr = r + DR[d], nc = c + DC[d];
        if (!vis[nr][nc]) dfs(nr, nc, step + 1);
    }
    vis[r][c] = false;
}

int main() {
    cin >> s;
    for (int i = 0; i < 9; i++) vis[0][i] = vis[8][i] = vis[i][0] = vis[i][8] = true;
    dfs(1, 1, 0);
    cout << cnt << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static char[] s;
    static boolean[][] vis = new boolean[9][9];
    static long cnt = 0;
    static final int[] DR = {1, -1, 0, 0}, DC = {0, 0, -1, 1};
    static final char[] DCH = {'D', 'U', 'L', 'R'};

    static void dfs(int r, int c, int step) {
        if (r == 7 && c == 1) { if (step == 48) cnt++; return; }
        if (step == 48) return;
        if (vis[r - 1][c] && vis[r + 1][c] && !vis[r][c - 1] && !vis[r][c + 1]) return;
        if (vis[r][c - 1] && vis[r][c + 1] && !vis[r - 1][c] && !vis[r + 1][c]) return;
        vis[r][c] = true;
        for (int d = 0; d < 4; d++) {
            if (s[step] != '?' && s[step] != DCH[d]) continue;
            int nr = r + DR[d], nc = c + DC[d];
            if (!vis[nr][nc]) dfs(nr, nc, step + 1);
        }
        vis[r][c] = false;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        s = br.readLine().trim().toCharArray();
        for (int i = 0; i < 9; i++) vis[0][i] = vis[8][i] = vis[i][0] = vis[i][8] = true;
        dfs(1, 1, 0);
        System.out.println(cnt);
    }
}
```

</details>

<!-- test
in:
RRRRRRDDDDDDLUUUUULDDDDDLUUUUULDDDDDLUUUUULDDDDD
out:
1
-->
<!-- test
in:
RRRRRRDDDDDDLUUUUULDDDDD????????????????????????
out:
55
-->
<!-- test
in:
????????????????????????LUUUUULDDDDDLUUUUULDDDDD
out:
32
-->
<!-- test
in:
????????????????????????????????????????????????
out:
88418
-->

## 6. Tricks, pitfalls and things to remember

1. **Forgetting to un-choose.** Every state change before the recursive call must be undone after it, in reverse order — including
   counters, `used[]` flags and container pushes. A missed undo gives answers that depend on exploration order.
2. **Copying state into every call.** Passing a `vector`/`string` by value, or `new ArrayList<>(cur)` at every node instead of only at the
   leaves, multiplies the cost by $n$. Mutate one shared state and copy only when recording an answer.
3. **Duplicate outputs** with repeated elements: sort, then skip an element equal to the previous one at the same depth if the previous one is
   unused (§3.1), or use `next_permutation`.
4. **Stack overflow.** C++ on Windows locally: compile with `-Wl,--stack=268435456`; Java: the `Thread` trick (§3.4). Recursion depth
   $\sim n$ on paths/linked structures is the usual culprit, not branching recursion (whose depth is only $n\le 20$).
5. **Pruning that is not safe.** A bound must be optimistic. Test the pruned search against the unpruned one on small inputs — the same
   stress-testing discipline as for any other optimisation.
6. **Overflow in sums of subsets**: $20$ values of $10^9$ sum to $2\cdot10^{10}$ — use `long long`/`long` (Example 1).
7. **Global state across test cases**: reset counters and `used[]` arrays per test; in Java, static fields keep their values between tests.
8. **Java recursion is slower** than C++ (method-call overhead, no inlining of deep recursion); for $10^7$+ recursive calls consider the
   bitmask/iterative form.
9. **Output size**: printing $8! = 40320$ strings is fine; printing all subsets of 20 elements is $2^{20}\cdot 20 \approx 2\cdot10^7$ characters —
   buffer it.

## 7. Going further (toward 2400–2600+)

- **Meet in the middle** for $n\approx40$ — [MITM](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md),
  e.g. [CF 1006F · Xor-Paths](https://codeforces.com/problemset/problem/1006/F) — 2100.
- **Memoised search → DP**: digit DP, bitmask DP over visited sets — [bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md),
  [digit DP](../06-Dynamic-Programming/07-digit-dp.md).
- **Game trees**: minimax with memoisation and alpha–beta pruning — [minimax & game DP](../13-Game-Theory/04-minimax-and-game-dp.md).
- **Randomised search and heuristics** when exact search is impossible (and randomised correctness arguments) —
  [randomised algorithms](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md).
- **Divide and conquer as an algorithmic paradigm**: CDQ, offline D&C over time —
  [offline techniques](../16-IGM-Frontier/01-offline-techniques-cdq-parallel-binary-search.md).

## 8. Practice ladder

**≤ 1400**
- [ ] [CSES 1623 · Apple Division](https://cses.fi/problemset/task/1623)
- [ ] [CSES 1622 · Creating Strings](https://cses.fi/problemset/task/1622)
- [ ] [CSES 1624 · Chessboard and Queens](https://cses.fi/problemset/task/1624)
- [ ] [CSES 2165 · Tower of Hanoi](https://cses.fi/problemset/task/2165)
- [ ] [AtCoder ABC079 C · Train Ticket](https://atcoder.jp/contests/abc079/tasks/abc079_c) — diff≈331
- [ ] [AtCoder ABC145 C · Average Length](https://atcoder.jp/contests/abc145/tasks/abc145_c) — diff≈335
- [ ] [AtCoder ABC150 C · Count Order](https://atcoder.jp/contests/abc150/tasks/abc150_c) — diff≈422
- [ ] [AtCoder ABC147 C · HonestOrUnkind2](https://atcoder.jp/contests/abc147/tasks/abc147_c) — diff≈977
- [ ] [CF 1097B · Petr and a Combination Lock](https://codeforces.com/problemset/problem/1097/B) — 1200
- [ ] [CF 96B · Lucky Numbers (easy)](https://codeforces.com/problemset/problem/96/B) — 1300
- [ ] [CF 476B · Dreamoon and WiFi](https://codeforces.com/problemset/problem/476/B) — 1300
- [ ] [CF 550B · Preparing Olympiad](https://codeforces.com/problemset/problem/550/B) — 1400

**1400–1900**
- [ ] [AtCoder ABC045 C · Many Formulas](https://atcoder.jp/contests/abc045/tasks/arc061_a) — diff≈1089
- [ ] [CF 550C · Divisibility by Eight](https://codeforces.com/problemset/problem/550/C) — 1500
- [ ] [CF 1385D · a-Good String](https://codeforces.com/problemset/problem/1385/D) — 1500
- [ ] [CF 1646C · Factorials and Powers of Two](https://codeforces.com/problemset/problem/1646/C) — 1500
- [ ] [CSES 1625 · Grid Path Description](https://cses.fi/problemset/task/1625)

**1900+**
- [ ] [CF 1006F · Xor-Paths](https://codeforces.com/problemset/problem/1006/F) — 2100

## 9. LeetCode / FAANG cross-reference

Backtracking is one of the most frequent interview categories; interviewers look for the choose/recurse/un-choose structure, duplicate
handling, and a stated complexity like $O(n\cdot 2^n)$ or $O(n\cdot n!)$.

- [LC 78 · Subsets](https://leetcode.com/problems/subsets/) — Medium — include/exclude.
- [LC 90 · Subsets II](https://leetcode.com/problems/subsets-ii/) — Medium — sort + skip equal siblings.
- [LC 46 · Permutations](https://leetcode.com/problems/permutations/) — Medium — `used[]` array.
- [LC 47 · Permutations II](https://leetcode.com/problems/permutations-ii/) — Medium — the duplicate rule of §3.1.
- [LC 77 · Combinations](https://leetcode.com/problems/combinations/) — Medium — start index + "leave room" bound.
- [LC 39 · Combination Sum](https://leetcode.com/problems/combination-sum/) — Medium — reuse allowed: recurse with the same start.
- [LC 40 · Combination Sum II](https://leetcode.com/problems/combination-sum-ii/) — Medium — no reuse + duplicates.
- [LC 22 · Generate Parentheses](https://leetcode.com/problems/generate-parentheses/) — Medium — prune when closes exceed opens.
- [LC 17 · Letter Combinations of a Phone Number](https://leetcode.com/problems/letter-combinations-of-a-phone-number/) — Medium — $c^n$ assignments.
- [LC 79 · Word Search](https://leetcode.com/problems/word-search/) — Medium — grid DFS with visited marking and un-marking.
- [LC 131 · Palindrome Partitioning](https://leetcode.com/problems/palindrome-partitioning/) — Medium — cut positions as decisions.
- [LC 51 · N-Queens](https://leetcode.com/problems/n-queens/) — Hard — Example 3 without reserved squares.
- [LC 37 · Sudoku Solver](https://leetcode.com/problems/sudoku-solver/) — Hard — constraint arrays + most-constrained-cell ordering.
- [LC 698 · Partition to K Equal Sum Subsets](https://leetcode.com/problems/partition-to-k-equal-sum-subsets/) — Medium — sort descending, prune equal buckets.

## 10. Self-check

1. How many nodes does the include/exclude recursion over $n$ items have? And the permutation recursion?
2. Why does `next_permutation` on a sorted string produce each distinct arrangement exactly once?
3. State the condition under which a branch-and-bound pruning is safe.
4. Why is the a-Good String recursion $O(n\log n)$ and not exponential, even though each call makes two recursive calls?
5. What are the three arrays that make an N-Queens check $O(1)$, and how are diagonals indexed?
6. Your Java DFS on a path graph of $2\cdot10^5$ vertices crashes with `StackOverflowError`. Give two fixes.
7. In the grid-path problem, why is "blocked above and below, free left and right" a valid reason to stop?

<details><summary>Answers</summary>

1. $2^{n+1}-1$; permutations: $\sum_{k=0}^n n!/(n-k)! < e\cdot n!$.
2. It always moves to the next lexicographically larger *sequence*; swapping equal letters gives the same sequence, which is never "larger", so it is never produced twice; starting from the smallest (sorted) sequence it reaches the largest.
3. The bound must never be worse than the best value actually achievable in the subtree (optimistic); then a subtree whose bound cannot beat the current best contains nothing better.
4. The two calls work on disjoint halves, so the total length per recursion level is $n$; $\log n$ levels give $O(n\log n)$. Exponential blow-up needs overlapping or non-shrinking subproblems.
5. Column used, `r - c + (n-1)` diagonal used, `r + c` anti-diagonal used.
6. Run the solver in `new Thread(null, runnable, "name", 1 << 28)`; or rewrite the DFS iteratively with an explicit stack.
7. We arrived from one vertical neighbour; with the other blocked, the visited path plus walls separate the free left and right cells into different regions; one path cannot visit both regions and finish at the target.

</details>
