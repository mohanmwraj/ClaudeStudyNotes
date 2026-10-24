# Sequence DP — LIS, LCS, Edit Distance and Subsequence Counting

> **Band:** 🟢→🟣 1300–2200 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [DP first principles](01-dp-first-principles-and-state-design.md), [binary search](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md), [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md) (for counting)
> **You can say you know this when:** you can derive the $O(n\log n)$ LIS from the "smallest tail" invariant and reconstruct a sequence from it; switch between strict and non-decreasing with one character; count LIS with a Fenwick tree; write LCS and edit distance with reconstruction and with $O(\min(n,m))$ memory; and count distinct subsequences without double counting.

Sequence DPs are the purest "fix the last element" problems: the state is a prefix (or a pair of prefixes), and the transition asks what happens to the last character(s). They are also where the most famous *speed-up by changing the state* lives — the patience-sorting LIS.

---

## 1. First principles — why this works

### 1.1 LIS in $O(n^2)$ — fix the last element

A strictly increasing subsequence is determined by its chosen indices. What does the future need to know about a partial subsequence to extend it? Only its **last value**. So classify increasing subsequences by their last index $i$:

$$f(i) = 1 + \max\{ f(j) : j < i,\ a_j < a_i \} \quad (\max \emptyset = 0), \qquad \text{LIS} = \max_i f(i).$$

$n$ states, $O(n)$ transitions each: $O(n^2)$, fine for $n \le 5000$.

### 1.2 LIS in $O(n \log n)$ — change the state

The $O(n^2)$ DP indexes by *position* and stores a *length*. Swap them: index by **length** and store the best possible **last value**.

> $T[k]$ = the smallest value that can end an increasing subsequence of length $k+1$ among the elements processed so far.

**Invariant: $T$ is strictly increasing.** If some subsequence of length $k+2$ ends in $x$, dropping its last element leaves one of length $k+1$ ending in some $y < x$; hence $T[k] \le y < x$, and minimising over $x$ gives $T[k] < T[k+1]$.

**Update with $a_i$.** Let $k$ be the first index with $T[k] \ge a_i$ (`lower_bound`).
- $a_i$ extends the length-$k$ subsequence ending in $T[k-1] < a_i$, so a length-$(k+1)$ subsequence can end in $a_i \le T[k]$: set $T[k] = a_i$ (append if $k = |T|$).
- It cannot help any other length: for lengths $\le k$ the current tails are already $< a_i$; for lengths $> k+1$, $a_i$ would have to follow a tail $T[k] \ge a_i$, which is not increasing.

So $|T|$ is the LIS length, each step costs a binary search, and as a bonus **$f(i) = k+1$** — we recover the $O(n^2)$ DP values in $O(\log n)$ each.

**Patience sorting picture.** Deal the numbers as cards onto piles: put each card on the leftmost pile whose top is $\ge$ the card, else start a new pile. Pile tops are exactly $T$. Each pile is a non-increasing sequence, so the piles cover the array with $|T|$ non-increasing subsequences — and no cover can use fewer, since an increasing subsequence uses at most one card per pile. This is Dilworth's theorem for this order: **the minimum number of non-increasing subsequences covering the array equals the length of the longest strictly increasing subsequence** ([matching theorems](../12-Flows-and-Matching/06-matching-theorems-konig-hall-dilworth.md)).

**Reconstruction.** Keep `pos[k]` = index whose value currently sits in $T[k]$, and when $a_i$ is placed at slot $k$, record `par[i] = pos[k-1]`. At that moment `pos[k-1]` is an index $j<i$ with $a_j = T[k-1] < a_i$ and $f(j) = k$, so the parent chain from `pos[len-1]` is a valid LIS.

**Variants by one character:**

| Wanted | Search for the first slot with | |
|---|---|---|
| strictly increasing | $T[k] \ge a_i$ | `lower_bound` |
| non-decreasing | $T[k] > a_i$ | `upper_bound` |
| strictly decreasing | run on $-a_i$ | |
| non-increasing | `upper_bound` on $-a_i$ | |

### 1.3 Counting LIS — carry (length, count) pairs

To count longest increasing subsequences we need, for each $i$, both $f(i)$ and $c(i)$ = the number of increasing subsequences of length $f(i)$ ending at $i$:

$$c(i) = \sum_{j<i,\ a_j<a_i,\ f(j)=f(i)-1} c(j) \qquad (c(i)=1 \text{ if } f(i)=1).$$

The predecessors are "all $j<i$ with smaller value", a prefix in **value order**. Process positions left to right and keep a Fenwick tree over compressed values whose nodes store the pair $(\text{best length}, \text{count})$ with the combine rule "larger length wins; equal lengths add counts". A prefix query over values $< a_i$ returns $(f(i)-1, c(i))$ directly. $O(n\log n)$. Lengths stay exact (they are compared); counts are taken mod $p$ (they are only added).

### 1.4 LCS — fix the last characters

$f(i, j)$ = LCS length of prefixes $a_{1..i}$ and $b_{1..j}$. Look at the last characters:

- If $a_i = b_j$: some LCS matches them to each other. (Take any LCS $Z$. If it uses neither, append the pair. If it uses $a_i$ matched to some $b_{j'}$ with $j'<j$, re-match it to $b_j$ — still a common subsequence of the same length. Symmetrically for $b_j$.) So $f(i,j) = f(i-1,j-1)+1$.
- Otherwise at least one of $a_i, b_j$ is unused: $f(i,j) = \max(f(i-1,j), f(i,j-1))$.

$O(nm)$ time. The table is needed for reconstruction (walk back from $(n,m)$: diagonal on a match, else move toward the larger neighbour). For the length alone, two rows suffice: $O(\min(n,m))$ memory.

### 1.5 Edit distance — fix the last operation

$f(i,j)$ = minimum number of insertions, deletions, substitutions turning $a_{1..i}$ into $b_{1..j}$. In an optimal edit script, the last characters are handled by one of: delete $a_i$; insert $b_j$; substitute (or keep, if equal) $a_i \to b_j$:

$$f(i,j) = \min\big( f(i-1,j)+1,\ f(i,j-1)+1,\ f(i-1,j-1)+[a_i \ne b_j] \big),\qquad f(i,0)=i,\ f(0,j)=j.$$

Weighted versions replace the 1s by costs. LCS is edit distance with only insertions and deletions: $\text{dist}_{\text{ins/del}} = n + m - 2\,\text{LCS}$.

### 1.6 Palindromic subsequences

The longest palindromic subsequence of $s$ equals $\text{LCS}(s, \text{reverse}(s))$, or directly by interval DP: $g(l,r) = g(l+1,r-1)+2$ if $s_l = s_r$, else $\max(g(l+1,r), g(l,r-1))$ ([interval DP](05-interval-dp.md)). Minimum insertions to make $s$ a palindrome $= n - \text{LPS}$.

### 1.7 Counting subsequences without double counting

**Occurrences of $t$ as a subsequence of $s$** (positions matter): classify by whether $s_i$ is used as the last character $t_j$:
$$h(i,j) = h(i-1,j) + [s_i = t_j]\, h(i-1,j-1), \qquad h(\cdot, 0) = 1.$$

**Number of distinct subsequences of $s$** (strings, not positions) is subtler — the same string arises from many index sets. Let $D(i)$ count distinct subsequences (including the empty one) of $s_{1..i}$. Appending $s_i$ to each of the $D(i-1)$ old subsequences gives new strings, but some of them were already created at the *previous occurrence* $p$ of the same character: exactly those obtained by appending $s_i$ to the $D(p-1)$ subsequences of $s_{1..p-1}$. Hence

$$D(i) = 2D(i-1) - D(p-1) \quad (\text{or } 2D(i-1) \text{ if } s_i \text{ is new}),\qquad D(0)=1 .$$

A subtraction-free alternative, needed when counts must be **capped** (comparisons with a threshold, as in CF 1183H): count paths in the **subsequence automaton**. Each distinct subsequence $z$ has a unique *greedy leftmost* embedding; from position $i$, the next character $c$ goes to $\text{nxt}(i, c)$ = first occurrence of $c$ after $i$. Then
$$F(i, L) = \sum_{c\ \text{occurs after } i} F(\text{nxt}(i,c), L-1), \qquad F(i, 0) = 1,$$
counts distinct subsequences of length $L$ starting after position $i$, using only additions (so `min(sum, cap)` is safe).

### 1.8 Memory and speed for large LCS

- **Hirschberg** (🧊): reconstruct an LCS in $O(nm)$ time and $O(n+m)$ memory by divide and conquer — run the forward DP on the first half of $a$ and the backward DP on the second half, find the column where the sums peak, recurse on the two quadrants. Useful when $n = m = 2\cdot10^4$ and the table would be $4\cdot10^8$ cells.
- **Bit-parallel LCS** (🧊): the row differences of the LCS table are 0/1 and can be updated with word operations in $O(nm/w)$.
- **LCS of permutations** reduces to LIS: map each value of $b$ to its position in $a$; an LCS is an increasing subsequence of the mapped $b$. $O(n \log n)$.

---

## 2. Formulas, definitions and identities

| Quantity | Recurrence | Time | Memory |
|---|---|---|---|
| LIS ending at $i$ | $f(i) = 1+\max_{j<i,a_j<a_i} f(j)$ | $O(n^2)$ | $O(n)$ |
| LIS length | tails $T$, `lower_bound` | $O(n\log n)$ | $O(n)$ |
| number of LIS | Fenwick of (len, cnt) over values | $O(n\log n)$ | $O(n)$ |
| LCS | $f(i,j) = f(i-1,j-1)+1$ or $\max(f(i-1,j),f(i,j-1))$ | $O(nm)$ | $O(\min)$ / $O(nm)$ to reconstruct |
| edit distance | $\min(f(i-1,j)+1, f(i,j-1)+1, f(i-1,j-1)+[a_i\ne b_j])$ | $O(nm)$ | $O(\min)$ |
| LPS | $\text{LCS}(s, s^R)$ | $O(n^2)$ | |
| occurrences of $t$ in $s$ | $h(i,j)=h(i-1,j)+[s_i=t_j]h(i-1,j-1)$ | $O(nm)$ | $O(m)$ |
| distinct subsequences | $D(i) = 2D(i-1) - D(p-1)$ | $O(n)$ | $O(n)$ |

**Identities:**
- $\text{ins/del distance}(a,b) = |a| + |b| - 2\,\text{LCS}(a,b)$.
- $\text{min insertions to palindrome}(s) = |s| - \text{LPS}(s)$.
- Dilworth (this order): min #non-increasing subsequences covering $a$ $=$ LIS (strict) length; symmetrically, min #strictly increasing subsequences covering $a$ $=$ longest non-increasing subsequence.
- Erdős–Szekeres: every sequence of $rs+1$ distinct numbers has an increasing subsequence of length $r+1$ or a decreasing one of length $s+1$ (pigeonhole on the pairs $(f_{\uparrow}(i), f_{\downarrow}(i))$).
- 2-D chains (envelopes): sort by first coordinate ascending and, **for equal first coordinates, second coordinate descending**; then a strict LIS on the second coordinate is a strict chain in both.
- Strictly increasing sequence of integers $\Leftrightarrow$ $a_i - i$ non-decreasing (turns "make it strictly increasing" into "make it non-decreasing", CF 713C).

---

## 3. Implementation (C++ and Java)

### 3.1 LIS with reconstruction

Prints the length and the 1-based indices of one longest strictly increasing subsequence.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    vector<long long> T;              // T[k]: smallest tail of an increasing subsequence of length k+1
    vector<int> pos, par(n, -1);      // pos[k]: index holding T[k]; par[i]: previous index in i's LIS
    for (int i = 0; i < n; i++) {
        int k = lower_bound(T.begin(), T.end(), a[i]) - T.begin();   // upper_bound for non-decreasing
        if (k == (int)T.size()) { T.push_back(a[i]); pos.push_back(i); }
        else { T[k] = a[i]; pos[k] = i; }
        par[i] = k > 0 ? pos[k - 1] : -1;
    }
    vector<int> seq;
    for (int v = pos.back(); v != -1; v = par[v]) seq.push_back(v + 1);
    reverse(seq.begin(), seq.end());
    cout << T.size() << "\n";
    for (size_t k = 0; k < seq.size(); k++) cout << seq[k] << " \n"[k + 1 == seq.size()];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = nl();
        long[] T = new long[n];
        int[] pos = new int[n], par = new int[n];
        int len = 0;
        for (int i = 0; i < n; i++) {
            int lo = 0, hi = len;                 // first k with T[k] >= a[i]
            while (lo < hi) {
                int mid = (lo + hi) >>> 1;
                if (T[mid] >= a[i]) hi = mid; else lo = mid + 1;
            }
            T[lo] = a[i];
            pos[lo] = i;
            par[i] = lo > 0 ? pos[lo - 1] : -1;
            if (lo == len) len++;
        }
        int[] seq = new int[len];
        for (int v = pos[len - 1], k = len - 1; v != -1; v = par[v]) seq[k--] = v + 1;
        StringBuilder sb = new StringBuilder();
        sb.append(len).append('\n');
        for (int k = 0; k < len; k++) sb.append(seq[k]).append(k + 1 == len ? '\n' : ' ');
        System.out.print(sb);
    }
}
```

<!-- test
in:
8
7 3 5 3 6 2 9 1
out:
4
2 3 5 7
-->
<!-- test
in:
1
42
out:
1
1
-->
<!-- test
in:
3
1 2 3
out:
3
1 2 3
-->

### 3.2 Non-decreasing LIS and the Dilworth cover

```cpp
// Longest non-decreasing subsequence: only the comparison changes (upper_bound).
int longestNonDecreasing(const vector<long long>& a) {
    vector<long long> T;
    for (long long x : a) {
        auto it = upper_bound(T.begin(), T.end(), x);
        if (it == T.end()) T.push_back(x); else *it = x;
    }
    return T.size();
}

// Minimum number of non-increasing subsequences that cover a = length of the strict LIS (Dilworth).
int minNonIncreasingCover(const vector<long long>& a) {
    vector<long long> T;
    for (long long x : a) {
        auto it = lower_bound(T.begin(), T.end(), x);
        if (it == T.end()) T.push_back(x); else *it = x;
    }
    return T.size();
}
```

```java
static int longestNonDecreasing(long[] a) {
    long[] T = new long[a.length];
    int len = 0;
    for (long x : a) {
        int lo = 0, hi = len;                     // first k with T[k] > x
        while (lo < hi) { int mid = (lo + hi) >>> 1; if (T[mid] > x) hi = mid; else lo = mid + 1; }
        T[lo] = x;
        if (lo == len) len++;
    }
    return len;
}

static int minNonIncreasingCover(long[] a) {
    long[] T = new long[a.length];
    int len = 0;
    for (long x : a) {
        int lo = 0, hi = len;                     // first k with T[k] >= x
        while (lo < hi) { int mid = (lo + hi) >>> 1; if (T[mid] >= x) hi = mid; else lo = mid + 1; }
        T[lo] = x;
        if (lo == len) len++;
    }
    return len;
}
```

### 3.3 Subsequence counting kernels

```cpp
const long long MOD = 1'000'000'007;

// Number of distinct subsequences of s, including the empty one.
long long distinctSubsequences(const string& s) {
    int n = s.size();
    vector<long long> D(n + 1);
    vector<int> last(256, 0);                          // last[c]: 1-based position of previous c, 0 if none
    D[0] = 1;
    for (int i = 1; i <= n; i++) {
        unsigned char c = s[i - 1];
        D[i] = 2 * D[i - 1] % MOD;
        if (last[c]) D[i] = (D[i] - D[last[c] - 1] + MOD) % MOD;
        last[c] = i;
    }
    return D[n];
}

// Number of index sets at which t occurs as a subsequence of s.
long long countOccurrences(const string& s, const string& t) {
    int m = t.size();
    vector<long long> h(m + 1, 0);
    h[0] = 1;
    for (char c : s)
        for (int j = m; j >= 1; j--)                   // downward: s_i used at most once
            if (t[j - 1] == c) h[j] = (h[j] + h[j - 1]) % MOD;
    return h[m];
}
```

```java
static final long MOD = 1_000_000_007L;

static long distinctSubsequences(String s) {
    int n = s.length();
    long[] D = new long[n + 1];
    int[] last = new int[65536];
    D[0] = 1;
    for (int i = 1; i <= n; i++) {
        char c = s.charAt(i - 1);
        D[i] = 2 * D[i - 1] % MOD;
        if (last[c] != 0) D[i] = (D[i] - D[last[c] - 1] + MOD) % MOD;
        last[c] = i;
    }
    return D[n];
}

static long countOccurrences(String s, String t) {
    int m = t.length();
    long[] h = new long[m + 1];
    h[0] = 1;
    for (int i = 0; i < s.length(); i++) {
        char c = s.charAt(i);
        for (int j = m; j >= 1; j--)
            if (t.charAt(j - 1) == c) h[j] = (h[j] + h[j - 1]) % MOD;
    }
    return h[m];
}
```

---

## 4. Recognising the pattern

| Signal | Technique |
|---|---|
| "longest strictly increasing / non-decreasing subsequence", $n \le 2\cdot10^5$ | tails + binary search |
| "minimum number of decreasing (non-increasing) chains / piles / trains to cover" | LIS by Dilworth |
| nested boxes, envelopes, chains in two coordinates | sort (asc, desc on ties) + LIS |
| "number of longest …", "number of increasing subsequences of length $k$" | Fenwick over values, (len, count) or one Fenwick per length |
| two strings, "common", "align", "match characters in order" | LCS table $(i, j)$ |
| "minimum operations to transform string $a$ into $b$" | edit distance (check which operations are allowed) |
| "make a palindrome by deleting/inserting" | LPS = LCS with reverse |
| "how many times does $t$ appear as a subsequence" | $h(i,j)$ occurrence DP |
| "how many *different* subsequences" | last-occurrence subtraction, or subsequence automaton when capping |
| two permutations | LCS → LIS in $O(n\log n)$ |
| "make the array strictly increasing with min total change" | $a_i - i$, then non-decreasing version (slope trick / DP over sorted values) |

Often confused: **subarray** (contiguous — usually two pointers or Kadane) vs **subsequence** (any indices — DP).

---

## 5. Worked examples (graded)

### Example 1 — Increasing Subsequence  ·  ★ ≈1300 (est.)

- **Source:** [CSES 1145 · Increasing Subsequence](https://cses.fi/problemset/task/1145)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $n \le 2\cdot10^5$, $a_i \le 10^9$. Length of the longest strictly increasing subsequence.
- **Thinking from first principles:** $O(n^2)$ is $4\cdot10^{10}$ — too slow. The $O(n^2)$ DP stores, for each end position, a length; but among all subsequences of the same length only the one with the smallest tail matters for the future (a smaller tail can be extended by everything a larger one can). So keep "best tail per length" — the tails array — and update it with a binary search.

<details><summary>Solution</summary>

`lower_bound` in the tails; the answer is the number of tails. $O(n \log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> T;
    for (int i = 0; i < n; i++) {
        int x;
        cin >> x;
        auto it = lower_bound(T.begin(), T.end(), x);
        if (it == T.end()) T.push_back(x); else *it = x;
    }
    cout << T.size() << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        int[] T = new int[n];
        int len = 0;
        for (int i = 0; i < n; i++) {
            int x = (int) nl();
            int lo = 0, hi = len;
            while (lo < hi) { int mid = (lo + hi) >>> 1; if (T[mid] >= x) hi = mid; else lo = mid + 1; }
            T[lo] = x;
            if (lo == len) len++;
        }
        System.out.println(len);
    }
}
```

</details>

<!-- test
in:
8
7 3 5 3 6 2 9 8
out:
4
-->
<!-- test
in:
1
5
out:
1
-->
<!-- test
in:
6
1 1 2 2 3 3
out:
3
-->

### Example 2 — LCS with reconstruction  ·  ★ ≈1400 (est.)

- **Source:** [AtCoder DP F · LCS](https://atcoder.jp/contests/dp/tasks/dp_f)
- **Difficulty:** ≈1400 (est.)
- **Problem:** Strings $s, t$ of length $\le 3000$. Print one longest common subsequence (any, if several).
- **Thinking from first principles:** The length DP is the classic $(i,j)$ table. Reconstruction must follow decisions that are *consistent with the table*: from $(i,j)$, if $s_i = t_j$ the diagonal is always safe (§1.4 exchange argument); otherwise move to whichever neighbour carries the value $f(i,j)$. $3001^2 \approx 9\cdot10^6$ cells — store them as `short`/`int` (Java: `int[][]` is 36 MB; use `short`, LCS $\le 3000$ fits).

<details><summary>Solution</summary>

Fill the table, then walk back from $(n,m)$. $O(nm)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string s, t;
    cin >> s >> t;
    int n = s.size(), m = t.size();
    vector<vector<short>> f(n + 1, vector<short>(m + 1, 0));
    for (int i = 1; i <= n; i++)
        for (int j = 1; j <= m; j++)
            f[i][j] = s[i - 1] == t[j - 1] ? f[i - 1][j - 1] + 1 : max(f[i - 1][j], f[i][j - 1]);
    string z;
    for (int i = n, j = m; i > 0 && j > 0;) {
        if (s[i - 1] == t[j - 1]) { z += s[i - 1]; i--; j--; }
        else if (f[i - 1][j] >= f[i][j - 1]) i--;
        else j--;
    }
    reverse(z.begin(), z.end());
    cout << z << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static String ns() throws IOException {
        int c = IN.read();
        while (c <= ' ') c = IN.read();
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = IN.read(); }
        return sb.toString();
    }

    public static void main(String[] args) throws IOException {
        char[] s = ns().toCharArray(), t = ns().toCharArray();
        int n = s.length, m = t.length;
        short[][] f = new short[n + 1][m + 1];
        for (int i = 1; i <= n; i++)
            for (int j = 1; j <= m; j++)
                f[i][j] = s[i - 1] == t[j - 1] ? (short) (f[i - 1][j - 1] + 1) : (short) Math.max(f[i - 1][j], f[i][j - 1]);
        StringBuilder z = new StringBuilder();
        for (int i = n, j = m; i > 0 && j > 0;) {
            if (s[i - 1] == t[j - 1]) { z.append(s[i - 1]); i--; j--; }
            else if (f[i - 1][j] >= f[i][j - 1]) i--;
            else j--;
        }
        System.out.println(z.reverse());
    }
}
```

</details>

<!-- test
in:
abcde
xbydz
out:
bd
-->
<!-- test
in:
zzz
zzz
out:
zzz
-->
<!-- test
in:
a
b
out:

-->

### Example 3 — Edit Distance  ·  ★ ≈1400 (est.)

- **Source:** [CSES 1639 · Edit Distance](https://cses.fi/problemset/task/1639)
- **Difficulty:** ≈1400 (est.)
- **Problem:** Strings of length $\le 5000$ (uppercase). Minimum number of single-character insertions, deletions and replacements turning the first into the second.
- **Thinking from first principles:** An optimal script, read backwards, ends with something happening to the last characters — and there are only three possibilities. That is the whole recurrence. $2.5\cdot10^7$ cells; the full table would be 100 MB as `int`, so roll two rows (only row $i-1$ is read).

<details><summary>Solution</summary>

Two rows `prv`, `cur`; $f(i,0) = i$ for the first column of each row. $O(nm)$ time, $O(m)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string a, b;
    cin >> a >> b;
    int n = a.size(), m = b.size();
    vector<int> prv(m + 1), cur(m + 1);
    iota(prv.begin(), prv.end(), 0);                  // f(0, j) = j
    for (int i = 1; i <= n; i++) {
        cur[0] = i;
        for (int j = 1; j <= m; j++)
            cur[j] = min({prv[j] + 1, cur[j - 1] + 1, prv[j - 1] + (a[i - 1] != b[j - 1])});
        swap(prv, cur);
    }
    cout << prv[m] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static String ns() throws IOException {
        int c = IN.read();
        while (c <= ' ') c = IN.read();
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = IN.read(); }
        return sb.toString();
    }

    public static void main(String[] args) throws IOException {
        char[] a = ns().toCharArray(), b = ns().toCharArray();
        int n = a.length, m = b.length;
        int[] prv = new int[m + 1], cur = new int[m + 1];
        for (int j = 0; j <= m; j++) prv[j] = j;
        for (int i = 1; i <= n; i++) {
            cur[0] = i;
            for (int j = 1; j <= m; j++) {
                int best = Math.min(prv[j] + 1, cur[j - 1] + 1);
                cur[j] = Math.min(best, prv[j - 1] + (a[i - 1] != b[j - 1] ? 1 : 0));
            }
            int[] tmp = prv; prv = cur; cur = tmp;
        }
        System.out.println(prv[m]);
    }
}
```

</details>

<!-- test
in:
KITTEN
SITTING
out:
3
-->
<!-- test
in:
A
A
out:
0
-->
<!-- test
in:
ABC
XYZW
out:
4
-->

### Example 4 — Nested envelopes (2-D chains)  ·  ★ ≈1900 (est.)

- **Source:** Original problem (the stdin version of [LC 354 · Russian Doll Envelopes](https://leetcode.com/problems/russian-doll-envelopes/) — Hard, with $n$ up to $2\cdot10^5$).
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n \le 2\cdot10^5$ envelopes $(w_i, h_i)$, $1 \le w_i,h_i \le 10^9$. Envelope $A$ fits in $B$ if $w_A < w_B$ and $h_A < h_B$. Find the longest chain.
- **Thinking from first principles:** If all widths were distinct, sorting by width would turn the problem into a strict LIS on heights. Equal widths break this: after sorting, two envelopes with the same width and increasing heights would wrongly chain. The trick is to make them *impossible* to chain by ordering equal widths by **decreasing** height — a strictly increasing subsequence of heights can then take at most one envelope per width. No extra dimension needed; the tie-break is the whole idea. (Dead end: sorting ties by increasing height and then "skipping equal widths" inside the binary search — it breaks the tails invariant.)

<details><summary>Solution</summary>

Sort by $(w \uparrow, h \downarrow)$, then strict LIS on $h$. $O(n\log n)$. In Java, pack each envelope into one `long` key $w\cdot 2^{31} + (2^{31}-1-h)$, so that ascending keys mean $(w\uparrow, h\downarrow)$; shuffle and sort the primitive `long[]` — no boxing, and the shuffle defeats anti-quicksort inputs.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<pair<int, int>> e(n);
    for (auto& [w, h] : e) cin >> w >> h;
    sort(e.begin(), e.end(), [](const pair<int, int>& x, const pair<int, int>& y) {
        return x.first != y.first ? x.first < y.first : x.second > y.second;   // equal width: taller first
    });
    vector<int> T;
    for (auto [w, h] : e) {
        auto it = lower_bound(T.begin(), T.end(), h);
        if (it == T.end()) T.push_back(h); else *it = h;
    }
    cout << T.size() << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long[] key = new long[n];
        final long B = 1L << 31;
        for (int i = 0; i < n; i++) {
            long w = nl(), h = nl();
            key[i] = w * B + (B - 1 - h);            // ascending key = (w asc, h desc)
        }
        Random rnd = new Random(12345);
        for (int i = n - 1; i > 0; i--) {             // shuffle: defeats anti-quicksort inputs
            int j = rnd.nextInt(i + 1);
            long t = key[i]; key[i] = key[j]; key[j] = t;
        }
        Arrays.sort(key);
        int[] T = new int[n];
        int len = 0;
        for (int i = 0; i < n; i++) {
            int h = (int) (B - 1 - key[i] % B);
            int lo = 0, hi = len;
            while (lo < hi) { int mid = (lo + hi) >>> 1; if (T[mid] >= h) hi = mid; else lo = mid + 1; }
            T[lo] = h;
            if (lo == len) len++;
        }
        System.out.println(len);
    }
}
```

</details>

<!-- test
in:
5
5 4
6 4
6 7
2 3
7 8
out:
4
-->
<!-- test
in:
3
1 1
1 2
1 3
out:
1
-->
<!-- test
in:
1
10 10
out:
1
-->

### Example 5 — Number of longest increasing subsequences  ·  ★ ≈2000 (est.)

- **Source:** Original problem (the large-$n$ version of [LC 673 · Number of Longest Increasing Subsequence](https://leetcode.com/problems/number-of-longest-increasing-subsequence/) — Medium).
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n \le 2\cdot10^5$, $a_i \le 10^9$. Count strictly increasing subsequences (as index sets) of maximum length, mod $10^9+7$.
- **Thinking from first principles:** The $O(n^2)$ DP carries $(f(i), c(i))$. Its inner loop aggregates over "$j<i$ with $a_j<a_i$": the position condition is handled by processing left to right, and the value condition is a **prefix of the value axis**. An aggregate over a prefix with point updates is a Fenwick tree, provided the aggregate is associative — and "(max length, sum of counts at that max)" is: it is a monoid with identity $(0,0)$. Tails-array LIS gives lengths but not counts, because counting needs *all* predecessors of the right length, not just the best tail.

<details><summary>Solution</summary>

Compress values. For each $i$: $(L, C) = \text{query}(\text{rank}(a_i) - 1)$; $f = L+1$, $c = C$ if $L>0$ else 1; $\text{update}(\text{rank}(a_i), (f, c))$. Answer: the count of the overall maximum (a final query over all values). $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

const long long MOD = 1'000'000'007;
struct Node { int len; long long cnt; };
Node comb(Node a, Node b) {                          // max length; on ties add counts
    if (a.len != b.len) return a.len > b.len ? a : b;
    return {a.len, (a.cnt + b.cnt) % MOD};
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> a(n);
    for (auto& x : a) cin >> x;
    vector<int> vals(a);
    sort(vals.begin(), vals.end());
    vals.erase(unique(vals.begin(), vals.end()), vals.end());
    int m = vals.size();
    vector<Node> fw(m + 1, {0, 0});
    auto query = [&](int p) { Node r{0, 0}; for (; p > 0; p -= p & -p) r = comb(r, fw[p]); return r; };
    auto update = [&](int p, Node v) { for (; p <= m; p += p & -p) fw[p] = comb(fw[p], v); };
    for (int i = 0; i < n; i++) {
        int r = lower_bound(vals.begin(), vals.end(), a[i]) - vals.begin() + 1;
        Node best = query(r - 1);                     // predecessors with strictly smaller value
        Node cur{best.len + 1, best.len == 0 ? 1 : best.cnt};
        update(r, cur);
    }
    cout << query(m).cnt << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static long nl() throws IOException {
        int c = IN.read();
        while (c != '-' && (c < '0' || c > '9')) c = IN.read();
        boolean neg = c == '-';
        if (neg) c = IN.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + c - '0'; c = IN.read(); }
        return neg ? -r : r;
    }

    static final long MOD = 1_000_000_007L;
    static int m;
    static int[] fl;
    static long[] fc;
    static int qLen;
    static long qCnt;

    static void query(int p) {                       // result in (qLen, qCnt)
        qLen = 0; qCnt = 0;
        for (; p > 0; p -= p & -p) {
            if (fl[p] > qLen) { qLen = fl[p]; qCnt = fc[p]; }
            else if (fl[p] == qLen) qCnt = (qCnt + fc[p]) % MOD;
        }
    }

    static void update(int p, int len, long cnt) {
        for (; p <= m; p += p & -p) {
            if (len > fl[p]) { fl[p] = len; fc[p] = cnt; }
            else if (len == fl[p]) fc[p] = (fc[p] + cnt) % MOD;
        }
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = (int) nl();
        int[] vals = a.clone();
        Random rnd = new Random(7);
        for (int i = n - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); int t = vals[i]; vals[i] = vals[j]; vals[j] = t; }
        Arrays.sort(vals);
        int k = 0;
        for (int i = 0; i < n; i++) if (i == 0 || vals[i] != vals[i - 1]) vals[k++] = vals[i];
        m = k;
        fl = new int[m + 1];
        fc = new long[m + 1];
        for (int i = 0; i < n; i++) {
            int r = Arrays.binarySearch(vals, 0, m, a[i]) + 1;
            query(r - 1);
            int len = qLen + 1;
            long cnt = qLen == 0 ? 1 : qCnt;
            update(r, len, cnt);
        }
        query(m);
        System.out.println(qCnt);
    }
}
```

</details>

<!-- test
in:
5
1 3 5 4 7
out:
2
-->
<!-- test
in:
5
2 2 2 2 2
out:
5
-->
<!-- test
in:
1
9
out:
1
-->

### Example 6 — Subsequences (hard version)  ·  ★ 1900

- **Source:** [CF 1183H · Subsequences (hard version)](https://codeforces.com/problemset/problem/1183/H) — 1900
- **Difficulty:** 1900
- **Problem:** A string $s$ of length $n \le 100$ and $k \le 10^{12}$. Adding a subsequence $t$ to a set costs $n - |t|$. Build a set of exactly $k$ **distinct** subsequences (the empty one allowed) with minimum total cost, or print $-1$ if $s$ has fewer than $k$ distinct subsequences.
- **Thinking from first principles:** Cost depends only on length, so greedily take the longest subsequences first; we only need $\text{cnt}[L]$ = number of distinct subsequences of length $L$, and only up to $k$ (we never take more than $k$). The classic "$2D(i-1) - D(p-1)$" counting involves subtraction, which breaks if we cap values at $k$; exact values reach $\binom{100}{50} \approx 10^{29}$ and overflow 64-bit. Count with the subsequence automaton instead — additions only, so capping is safe (§1.7).

<details><summary>Solution</summary>

$\text{nxt}(i,c)$ = first position $> i$ holding $c$ (positions $1..n$, start $0$). $F(i,0)=1$, $F(i,L) = \min(\text{CAP}, \sum_c F(\text{nxt}(i,c), L-1))$ with $\text{CAP} = 10^{12}$. $\text{cnt}[L] = F(0, L)$. Take $\min(\text{remaining}, \text{cnt}[L])$ for $L = n, n-1, \dots, 0$. $O(26 n^2)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    long long k;
    string s;
    cin >> n >> k >> s;
    const long long CAP = 1'000'000'000'000LL;
    vector<array<int, 26>> nxt(n + 1);                // nxt[i][c]: first position > i with letter c, -1 if none
    for (int c = 0; c < 26; c++) nxt[n][c] = -1;
    for (int i = n - 1; i >= 0; i--) {
        nxt[i] = nxt[i + 1];
        nxt[i][s[i] - 'a'] = i + 1;
    }
    vector<vector<long long>> F(n + 1, vector<long long>(n + 1, 0));   // F[i][L]
    for (int i = n; i >= 0; i--) {
        F[i][0] = 1;
        for (int L = 1; L <= n - i; L++) {
            long long sum = 0;
            for (int c = 0; c < 26; c++)
                if (nxt[i][c] != -1) sum = min(CAP, sum + F[nxt[i][c]][L - 1]);
            F[i][L] = sum;
        }
    }
    long long cost = 0, need = k;
    for (int L = n; L >= 0 && need > 0; L--) {
        long long take = min(need, F[0][L]);
        cost += take * (n - L);
        need -= take;
    }
    cout << (need > 0 ? -1 : cost) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final DataInputStream IN = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));

    static String ns() throws IOException {
        int c = IN.read();
        while (c <= ' ') c = IN.read();
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = IN.read(); }
        return sb.toString();
    }

    public static void main(String[] args) throws IOException {
        int n = Integer.parseInt(ns());
        long k = Long.parseLong(ns());
        String s = ns();
        final long CAP = 1_000_000_000_000L;
        int[][] nxt = new int[n + 1][26];
        Arrays.fill(nxt[n], -1);
        for (int i = n - 1; i >= 0; i--) {
            nxt[i] = nxt[i + 1].clone();
            nxt[i][s.charAt(i) - 'a'] = i + 1;
        }
        long[][] F = new long[n + 1][n + 1];
        for (int i = n; i >= 0; i--) {
            F[i][0] = 1;
            for (int L = 1; L <= n - i; L++) {
                long sum = 0;
                for (int c = 0; c < 26; c++)
                    if (nxt[i][c] != -1) sum = Math.min(CAP, sum + F[nxt[i][c]][L - 1]);
                F[i][L] = sum;
            }
        }
        long cost = 0, need = k;
        for (int L = n; L >= 0 && need > 0; L--) {
            long take = Math.min(need, F[0][L]);
            cost += take * (n - L);
            need -= take;
        }
        System.out.println(need > 0 ? -1 : cost);
    }
}
```

</details>

<!-- test
in:
3 8
aaa
out:
-1
-->
<!-- test
in:
3 3
aba
out:
2
-->
<!-- test
in:
5 7
abcab
out:
7
-->
<!-- test
in:
1 2
z
out:
1
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Strict vs non-strict is `lower_bound` vs `upper_bound`.** Re-read the statement for "increasing" vs "non-decreasing" and test with equal elements.
2. **The tails array is not an LIS.** $T$ mixes elements from different subsequences; reconstruct with `pos`/`par`, never by printing $T$.
3. **LIS length via `lower_bound` on `int` values** fails silently if you forgot to read values as 64-bit when they can exceed $2^{31}$.
4. **2-D chains: ties in the first coordinate** must be sorted descending by the second (Example 4); otherwise equal-width items chain.
5. **Counting LIS needs exact lengths** and modular counts; combine "max then add on ties". Initialising the Fenwick with $(0,1)$ instead of $(0,0)$ adds phantom predecessors.
6. **Coordinate compression in Java:** shuffle before `Arrays.sort(int[])` (anti-quicksort tests exist), or sort `long[]`/use `Arrays.sort` on objects (merge sort, but boxing costs).
7. **LCS reconstruction tie-breaks** don't affect correctness, but they decide *which* LCS you print; if a checker wants a specific one (lexicographically smallest), you need a different walk (suffix DP + forward greedy).
8. **Memory:** a $5000 \times 5000$ `int` table is 100 MB — roll rows whenever only the value is needed; use `short` when values fit (LCS ≤ 3000 → `short`).
9. **Distinct subsequence counting with subtraction** cannot be capped; use the automaton form when you need comparisons with $k$ (Example 6).
10. **Empty subsequence:** decide whether it counts (formulas above include it in $D(0)=1$); subtract 1 if the statement wants non-empty.
11. **Edit distance variants:** if only insertions/deletions are allowed, it is $n+m-2\text{LCS}$; if a swap of adjacent characters is allowed (Damerau), add a transition from $f(i-2,j-2)$.
12. **Subarray vs subsequence:** "contiguous" means a different (usually easier) problem; LIS techniques don't apply to longest increasing *run*.

---

## 7. Going further (toward 2400–2600+)

- **LIS with one modification / LIS through each element**: compute $f_{\text{left}}(i)$ and $f_{\text{right}}(i)$; $i$ is in some LIS iff $f_{\text{left}}(i)+f_{\text{right}}(i)-1 = \text{LIS}$, and in *every* LIS iff it is the unique element with its $f_{\text{left}}$ value among those (CF 486E, CF 650D with offline queries).
- **LIS with gaps filled optimally** (CF 568E, 🔴): tails array with "wildcard" positions processed by merging the sorted candidate list into $T$ in linear time.
- **Make a sequence non-decreasing with minimum $\sum |a_i - b_i|$**: DP over sorted candidate values in $O(n^2)$ (CF 13C) or slope trick in $O(n \log n)$ ([slope trick](../07-DP-Optimizations/07-slope-trick.md)); the strictly increasing version via $a_i - i$ (CF 713C).
- **LCS of $k$ permutations** → longest path in a DAG of "value $x$ before $y$ in every permutation" (CF 463D).
- **LCS + forbidden substring**: add the KMP state of the forbidden string as a third dimension (CF 346B) — the automaton trick from [first principles](01-dp-first-principles-and-state-design.md) Example 5.
- **Hirschberg** and **bit-parallel LCS** (§1.8) for memory/time-critical LCS.
- **Counting increasing subsequences of length $k$**: one Fenwick per length, $O(kn\log n)$ (CF 597C).

---

## 8. Practice ladder

**≤ 1500**
- [ ] [CSES 1145 · Increasing Subsequence](https://cses.fi/problemset/task/1145) — tails
- [ ] [CSES 3403 · Longest Common Subsequence](https://cses.fi/problemset/task/3403) — LCS with reconstruction
- [ ] [CF 1178B · WOW Factor](https://codeforces.com/problemset/problem/1178/B) — 1300
- [ ] [CF 340D · Bubble Sort Graph](https://codeforces.com/problemset/problem/340/D) — 1500

**1500–1900**
- [ ] [CSES 1639 · Edit Distance](https://cses.fi/problemset/task/1639)
- [ ] [CF 4D · Mysterious Present](https://codeforces.com/problemset/problem/4/D) — 1700
- [ ] [CF 1061C · Multiplicity](https://codeforces.com/problemset/problem/1061/C) — 1700
- [ ] [CF 1446B · Catching Cheaters](https://codeforces.com/problemset/problem/1446/B) — 1800
- [ ] [CSES 1748 · Increasing Subsequence II](https://cses.fi/problemset/task/1748) — count increasing subsequences with a Fenwick
- [ ] [CSES 1149 · Distinct Subsequences](https://cses.fi/problemset/task/1149)
- [ ] [CF 597C · Subsequences](https://codeforces.com/problemset/problem/597/C) — 1900
- [ ] [CF 463D · Gargari and Permutations](https://codeforces.com/problemset/problem/463/D) — 1900

**1900–2300**
- [ ] [CF 1183E · Subsequences (easy version)](https://codeforces.com/problemset/problem/1183/E) — 2000
- [ ] [CF 1426F · Number of Subsequences](https://codeforces.com/problemset/problem/1426/F) — 2000
- [ ] [CF 346B · Lucky Common Subsequence](https://codeforces.com/problemset/problem/346/B) — 2000
- [ ] [CF 1409F · Subsequences of Length Two](https://codeforces.com/problemset/problem/1409/F) — 2100
- [ ] [CF 13C · Sequence](https://codeforces.com/problemset/problem/13/C) — 2200
- [ ] [CF 486E · LIS of Sequence](https://codeforces.com/problemset/problem/486/E) — 2200
- [ ] [CF 713C · Sonya and Problem Wihtout a Legend](https://codeforces.com/problemset/problem/713/C) — 2300

**2400+**
- [ ] [CF 650D · Zip-line](https://codeforces.com/problemset/problem/650/D) — 2600
- [ ] [CF 568E · Longest Increasing Subsequence](https://codeforces.com/problemset/problem/568/E) — 3000

---

## 9. LeetCode / FAANG cross-reference

- [LC 300 · Longest Increasing Subsequence](https://leetcode.com/problems/longest-increasing-subsequence/) — Medium — expect to be asked for the $O(n\log n)$ version and its proof.
- [LC 354 · Russian Doll Envelopes](https://leetcode.com/problems/russian-doll-envelopes/) — Hard — sort with the descending tie-break, then LIS (Example 4).
- [LC 673 · Number of Longest Increasing Subsequence](https://leetcode.com/problems/number-of-longest-increasing-subsequence/) — Medium — $O(n^2)$ (len, cnt); Fenwick for large $n$.
- [LC 1143 · Longest Common Subsequence](https://leetcode.com/problems/longest-common-subsequence/) — Medium — the $(i,j)$ table.
- [LC 72 · Edit Distance](https://leetcode.com/problems/edit-distance/) — Medium — three last operations.
- [LC 583 · Delete Operation for Two Strings](https://leetcode.com/problems/delete-operation-for-two-strings/) — Medium — $n+m-2\,\text{LCS}$.
- [LC 712 · Minimum ASCII Delete Sum for Two Strings](https://leetcode.com/problems/minimum-ascii-delete-sum-for-two-strings/) — Medium — weighted deletions.
- [LC 516 · Longest Palindromic Subsequence](https://leetcode.com/problems/longest-palindromic-subsequence/) — Medium — LCS with the reverse.
- [LC 1312 · Minimum Insertion Steps to Make a String Palindrome](https://leetcode.com/problems/minimum-insertion-steps-to-make-a-string-palindrome/) — Hard — $n - \text{LPS}$.
- [LC 115 · Distinct Subsequences](https://leetcode.com/problems/distinct-subsequences/) — Hard — occurrence counting $h(i,j)$.
- [LC 940 · Distinct Subsequences II](https://leetcode.com/problems/distinct-subsequences-ii/) — Hard — last-occurrence subtraction.
- [LC 1092 · Shortest Common Supersequence](https://leetcode.com/problems/shortest-common-supersequence/) — Hard — LCS reconstruction, interleave the rest.
- [LC 97 · Interleaving String](https://leetcode.com/problems/interleaving-string/) — Medium — feasibility over $(i, j)$.
- [LC 1458 · Max Dot Product of Two Subsequences](https://leetcode.com/problems/max-dot-product-of-two-subsequences/) — Hard — LCS-shaped table with "non-empty" care.
- [LC 1048 · Longest String Chain](https://leetcode.com/problems/longest-string-chain/) — Medium — LIS on a DAG of words.
- [LC 368 · Largest Divisible Subset](https://leetcode.com/problems/largest-divisible-subset/) — Medium — sort, then $O(n^2)$ LIS with divisibility, with reconstruction.

---

## 10. Self-check

1. Prove that the tails array is strictly increasing.
2. Why is the element written into `pos[k-1]` at the moment $a_i$ is placed a valid predecessor of $a_i$?
3. Which single change turns strict LIS into non-decreasing LIS? Into strictly decreasing?
4. Why can't the tails array count the number of LIS?
5. Justify the diagonal move in LCS when $a_i = b_j$.
6. Derive $D(i) = 2D(i-1) - D(p-1)$ and say why it cannot be used with capped counts.
7. Envelopes: what goes wrong if equal widths are sorted by increasing height?
8. What is the minimum number of strictly increasing subsequences needed to cover a sequence?

<details><summary>Answers</summary>

1. If a length-$(k+2)$ subsequence ends in $x$, removing its last element leaves a length-$(k+1)$ subsequence ending in some $y<x$, so $T[k]\le y<x$; take $x = T[k+1]$.
2. `pos[k-1]` holds an index $j$ processed before $i$ with $a_j = T[k-1] < a_i$ (by the choice of $k$) and an increasing subsequence of length $k$ ending at $j$; appending $i$ gives length $k+1$.
3. `lower_bound` → `upper_bound` for non-decreasing; negate the values (or reverse the comparison) for strictly decreasing.
4. It keeps one best tail per length and forgets all other subsequences of that length, while counting needs every predecessor of length $f(i)-1$.
5. From any LCS, either append the pair $(a_i, b_j)$ if both are unused, or re-match whichever of them is used to the other — the length does not change, so some LCS matches $a_i$ with $b_j$.
6. Appending $s_i$ to the $D(i-1)$ old subsequences doubles the count, but the strings obtained by appending $s_i$ to subsequences of $s_{1..p-1}$ were already produced at position $p$. Capping makes $D$ values wrong after the cap, and the subtraction can then produce garbage (even negative values).
7. Two envelopes with the same width and heights $h_1 < h_2$ would appear in increasing order, and the LIS would chain them although widths are equal.
8. The length of the longest non-increasing subsequence (the dual Dilworth statement).

</details>
