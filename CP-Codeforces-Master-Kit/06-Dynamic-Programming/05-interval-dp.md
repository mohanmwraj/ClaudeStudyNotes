# Interval DP

> **Band:** 🔵→🟠 1500–2400 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [DP first principles](01-dp-first-principles-and-state-design.md), [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md)
> **You can say you know this when:** you recognise when the "remaining structure" is always a contiguous segment; you can choose between "split at $k$", "fix the last operation" and "fix what happens to the first element"; you iterate by length without thinking; and you know when a third dimension (glued elements) is necessary and when Knuth's optimisation brings $O(n^3)$ down to $O(n^2)$.

When operations remove or merge elements of a sequence, the leftover pieces are contiguous segments, and the optimal way to handle one segment does not depend on what happens outside it. The state is then a segment $[l, r]$ — $O(n^2)$ states — and the work is in choosing a decomposition of a segment into smaller segments that is both *complete* (every solution is covered) and *independent* (the parts don't interact).

---

## 1. First principles — why this works

### 1.1 Why prefixes are not enough

A prefix DP works when decisions are made left to right. If an operation can touch both ends (take from either end of a deque), or merge two *neighbouring* blocks anywhere in the array, then after a few operations the "unfinished part" is a segment in the middle — so the state must name both ends: $f(l, r)$. A history is summarised by "which contiguous segment is left (or which segment has been merged into one block)"; whatever happened outside cannot influence the inside, provided the problem's cost of an operation depends only on the segment. That last condition is what you must check — when it fails (the cost depends on neighbours), you need either a different decomposition (§1.4) or an extra dimension (§1.6).

### 1.2 Split at $k$ — the last merge

**Merging adjacent piles** (AtCoder DP N *Slimes*, the stone-merging classic): merging two adjacent piles costs their total size; merge everything into one pile at minimum cost. Fix the **last merge** of segment $[l,r]$: it combines a pile made from $[l,k]$ and one made from $[k+1,r]$, which were built independently. The last merge costs $S(l,r) = \sum_{i=l}^r a_i$ regardless of $k$:

$$f(l,r) = S(l,r) + \min_{l \le k < r} \big(f(l,k) + f(k+1,r)\big), \qquad f(l,l) = 0.$$

**Matrix chain multiplication** is the same shape: the last multiplication of $A_l\cdots A_r$ splits at $k$ and costs $p_{l-1}\,p_k\,p_r$.

$O(n^2)$ states × $O(n)$ splits $= O(n^3)$; for $n = 400$ that is $\approx 10^7$ inner steps (the triple loop runs $\sim n^3/6$ times).

### 1.3 Order of evaluation

$f(l,r)$ reads strictly shorter segments. Two equivalent orders:

```text
for len = 1..n:                       for l = n-1 down to 0:
    for l = 0..n-len:                     for r = l..n-1:
        r = l + len - 1                       compute f(l, r)
        compute f(l, r)
```

The right-hand order works because $f(l, r)$ reads $f(l, k)$ (same $l$, smaller $r$ — already done in this row) and $f(k+1, r)$ (larger $l$ — an earlier row). The common bug is $l$ ascending with $r$ inner: it reads $f(l+1, r)$ before computing it.

### 1.4 Fix the last operation — Burst Balloons

$n$ balloons with values $v_i$; bursting $i$ scores $v_{\text{left}}\cdot v_i\cdot v_{\text{right}}$ where left/right are its *current* neighbours (1 beyond the ends). Maximise the total.

Try "fix the **first** balloon $k$ burst in the segment": after it disappears, $k-1$ and $k+1$ become neighbours, so the two sides interact — the decomposition is not independent. Now fix the **last** balloon $k$ burst in the open interval $(l, r)$, where $l$ and $r$ are boundaries that are still present. While the balloons of $(l,k)$ burst, $k$ is still there, so their neighbours lie in $[l, k]$ — the left side only sees $l$ and $k$ as walls. Same on the right. At the end $k$ bursts with neighbours exactly $l$ and $r$:

$$f(l,r) = \max_{l<k<r} \big(f(l,k) + f(k,r) + v_l\,v_k\,v_r\big), \qquad f(l, l+1) = 0,$$

over the padded array $v_0 = v_{n+1} = 1$. The general lesson: **choose the decomposition so that at the chosen moment, the parts are separated by fixed walls.** "Last" usually achieves that because everything else has already happened.

### 1.5 Fix what happens to the first element — deletions of equal blocks

**Clear the String** (CF 1132F): one operation deletes a contiguous block of equal letters; minimise the number of operations to delete everything. The segment $[l,r]$ is not split by a single "last operation" cleanly, because the last deletion may remove letters scattered across the segment that became adjacent. Instead, classify by **the operation that deletes $s_l$**:

- $s_l$ is deleted on its own (or with letters equal to it that are adjacent anyway): $1 + f(l+1, r)$.
- $s_l$ is deleted *together with* some later $s_k = s_l$, and $k$ is the **next** position in that operation. Everything strictly between them, $[l+1, k-1]$, must be gone before, and is independent; after that $s_l$ just joins whatever operation deletes $s_k$ in the segment $[k, r]$. So the cost is $f(l+1, k-1) + f(k, r)$ — the deletion of $s_l$ is "free" because it piggybacks on $s_k$'s.

$$f(l,r) = \min\Big(1 + f(l+1,r),\ \min_{l<k\le r,\ s_k=s_l} f(l+1,k-1) + f(k,r)\Big),\qquad f(l, l-1) = 0.$$

The same "what happens to the first element" pattern solves Zuma (CF 607B), Strange Printer (LC 664), and, with one more dimension, Remove Boxes (§1.6).

### 1.6 When the segment is not enough — glue a counter

**Remove Boxes / CF 1107E (*Vasya and Binary String*):** deleting a block of $x$ equal characters scores $a_x$ (not necessarily monotone or convex), maximise. Now the *score* of the operation that deletes $s_l$ depends on how many equal characters end up deleted with it — information that lives outside $[l+1, r]$ once we piggyback. Add it to the state:

> $f(l, r, k)$ = best score for segment $[l,r]$ when $k$ extra characters equal to $s_l$ are glued immediately before $l$ (they will be deleted together with $s_l$).

$$f(l,r,k) = \max\Big(\text{best}(k+1) + f(l+1, r, 0),\ \max_{l<m\le r,\ s_m = s_l} f(l+1, m-1, 0) + f(m, r, k+1)\Big),$$

where $\text{best}(x)$ = best score for deleting $x$ equal characters in possibly several operations ($\text{best}(x) = \max_{y\le x} a_y + \text{best}(x-y)$ — a small unbounded knapsack). $O(n^4)$ worst case, $\approx n^4/24$ in practice; fine for $n\le 100$.

This is "add a dimension for what breaks independence" — the interval-DP version of [first principles](01-dp-first-principles-and-state-design.md) §1.11.

### 1.7 Removal games on a segment

Two players alternately take an element from either end; each maximises their own total. Zero-sum, perfect information: let $g(l,r)$ = (current player's total − other player's total) on $[l,r]$ under optimal play:

$$g(l,r) = \max\big(a_l - g(l+1,r),\ a_r - g(l,r-1)\big),\qquad g(l,l) = a_l.$$

The minus sign is the whole minimax: after my move the opponent becomes "the current player" of the subsegment. First player's total $= (\text{sum} + g(1,n))/2$. $O(n^2)$ ([game DP](../13-Game-Theory/04-minimax-and-game-dp.md)).

### 1.8 Palindromic intervals

$\text{pal}(l,r) = [s_l = s_r] \wedge \text{pal}(l+1, r-1)$ fills an $n\times n$ boolean table in $O(n^2)$ (by length, or expand around centres). With it:
- minimum cuts into palindromes: prefix DP $c(i) = \min_{j \le i,\ \text{pal}(j,i)} c(j-1) + 1$ — $O(n^2)$;
- number of palindromic substrings inside $[l,r]$ for many queries: $P(l,r) = P(l+1,r) + P(l,r-1) - P(l+1,r-1) + \text{pal}(l,r)$ (CF 245H);
- longest palindromic subsequence: $g(l,r) = g(l+1,r-1)+2$ if $s_l=s_r$, else $\max(g(l+1,r), g(l,r-1))$.

Manacher gives the palindromic radii in $O(n)$ when only maximal palindromes are needed ([Manacher](../11-Strings/04-manacher-and-palindromes.md)).

### 1.9 Circular arrays

For merges on a circle, double the array ($a_1..a_n a_1..a_n$), run the interval DP for lengths $\le n$, and take $\min_i f(i, i+n-1)$. Same complexity up to a factor 4.

### 1.10 Faster than $O(n^3)$

If the cost satisfies the quadrangle inequality and monotonicity (true for $S(l,r)$ in stone merging, for optimal BSTs), then the optimal split points satisfy $\text{opt}(l, r-1) \le \text{opt}(l,r) \le \text{opt}(l+1,r)$, and scanning only that window gives $O(n^2)$ total — **Knuth's optimisation** ([Knuth](../07-DP-Optimizations/04-knuth-optimization.md)). Matrix chain does *not* satisfy it in general (Hu–Shing's $O(n\log n)$ algorithm exists, 🧊). Stone merging with $n \sim 10^5$ uses Garsia–Wachs (🧊).

---

## 2. Formulas, definitions and identities

| Problem | Recurrence | Time |
|---|---|---|
| merge adjacent piles | $f(l,r) = S(l,r) + \min_k f(l,k)+f(k+1,r)$ | $O(n^3)$, Knuth $O(n^2)$ |
| matrix chain | $f(l,r) = \min_k f(l,k)+f(k+1,r)+p_{l-1}p_kp_r$ | $O(n^3)$ |
| burst balloons | $f(l,r) = \max_{l<k<r} f(l,k)+f(k,r)+v_lv_kv_r$ | $O(n^3)$ |
| delete equal blocks (min ops) | $\min(1+f(l+1,r), \min_{s_k=s_l} f(l+1,k-1)+f(k,r))$ | $O(n^3)$ |
| delete blocks, score $a_x$ | $f(l,r,k)$, glued counter | $O(n^4)$ |
| removal game (difference) | $g(l,r) = \max(a_l - g(l+1,r), a_r - g(l,r-1))$ | $O(n^2)$ |
| palindrome table | $\text{pal}(l,r) = [s_l=s_r]\wedge\text{pal}(l+1,r-1)$ | $O(n^2)$ |
| min palindrome cuts | $c(i) = \min_{\text{pal}(j,i)} c(j-1)+1$ | $O(n^2)$ |
| optimal BST | $e(i,j) = \min_r e(i,r-1)+e(r+1,j)+w(i,j)$ | $O(n^2)$ with Knuth |

**Triple-loop count:** $\sum_{\text{len}=1}^{n} (n-\text{len}+1)(\text{len}-1) = \frac{n^3-n}{6}$, so $n = 500$ gives $2\cdot10^7$.

**Knuth's condition:** if $w$ satisfies the quadrangle inequality $w(a,c)+w(b,d) \le w(a,d)+w(b,c)$ for $a\le b\le c\le d$ and is monotone on inclusion, then $\text{opt}(l,r-1)\le\text{opt}(l,r)\le\text{opt}(l+1,r)$ and the total work telescopes to $O(n^2)$.

**Number of full parenthesisations** of $n$ factors (= binary trees with $n$ leaves) is the Catalan number $C_{n-1}$ — the reason brute force is exponential.

---

## 3. Implementation (C++ and Java)

### 3.1 Matrix chain with parenthesisation

Input: $n$, then dimensions $p_0..p_n$ (matrix $A_i$ is $p_{i-1}\times p_i$). Prints the minimum cost and an optimal parenthesisation; ties go to the **smallest** split $k$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
vector<vector<int>> split;

string build(int l, int r) {
    if (l == r) return "A" + to_string(l + 1);
    int k = split[l][r];
    return "(" + build(l, k) + build(k + 1, r) + ")";
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    cin >> n;
    vector<long long> p(n + 1);
    for (auto& x : p) cin >> x;
    vector<vector<long long>> f(n, vector<long long>(n, 0));
    split.assign(n, vector<int>(n, -1));
    for (int len = 2; len <= n; len++)
        for (int l = 0; l + len - 1 < n; l++) {
            int r = l + len - 1;
            f[l][r] = LLONG_MAX;
            for (int k = l; k < r; k++) {
                long long c = f[l][k] + f[k + 1][r] + p[l] * p[k + 1] * p[r + 1];
                if (c < f[l][r]) { f[l][r] = c; split[l][r] = k; }   // strict: smallest k on ties
            }
        }
    cout << f[0][n - 1] << "\n" << build(0, n - 1) << "\n";
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

    static int[][] split;

    static void build(int l, int r, StringBuilder sb) {
        if (l == r) { sb.append('A').append(l + 1); return; }
        sb.append('(');
        build(l, split[l][r], sb);
        build(split[l][r] + 1, r, sb);
        sb.append(')');
    }

    public static void main(String[] args) throws IOException {
        int n = (int) nl();
        long[] p = new long[n + 1];
        for (int i = 0; i <= n; i++) p[i] = nl();
        long[][] f = new long[n][n];
        split = new int[n][n];
        for (int len = 2; len <= n; len++)
            for (int l = 0; l + len - 1 < n; l++) {
                int r = l + len - 1;
                f[l][r] = Long.MAX_VALUE;
                for (int k = l; k < r; k++) {
                    long c = f[l][k] + f[k + 1][r] + p[l] * p[k + 1] * p[r + 1];
                    if (c < f[l][r]) { f[l][r] = c; split[l][r] = k; }
                }
            }
        StringBuilder sb = new StringBuilder();
        build(0, n - 1, sb);
        System.out.println(f[0][n - 1] + "\n" + sb);
    }
}
```

<!-- test
in:
3
10 30 5 60
out:
4500
((A1A2)A3)
-->
<!-- test
in:
1
5 7
out:
0
A1
-->
<!-- test
in:
4
40 20 30 10 30
out:
26000
((A1(A2A3))A4)
-->

### 3.2 Palindrome table and minimum palindromic cuts

Input: one string ($|s| \le 2000$). Output: the minimum number of cuts so that every piece is a palindrome.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string s;
    cin >> s;
    int n = s.size();
    vector<vector<char>> pal(n, vector<char>(n, 0));
    for (int l = n - 1; l >= 0; l--)                  // l descending, r ascending
        for (int r = l; r < n; r++)
            pal[l][r] = s[l] == s[r] && (r - l < 2 || pal[l + 1][r - 1]);
    vector<int> cut(n + 1, INT_MAX);                   // cut[i]: min pieces for prefix of length i
    cut[0] = 0;
    for (int i = 1; i <= n; i++)
        for (int j = 1; j <= i; j++)                  // last piece is s[j-1 .. i-1]
            if (pal[j - 1][i - 1]) cut[i] = min(cut[i], cut[j - 1] + 1);
    cout << cut[n] - 1 << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        String s = br.readLine().trim();
        int n = s.length();
        boolean[][] pal = new boolean[n][n];
        for (int l = n - 1; l >= 0; l--)
            for (int r = l; r < n; r++)
                pal[l][r] = s.charAt(l) == s.charAt(r) && (r - l < 2 || pal[l + 1][r - 1]);
        int[] cut = new int[n + 1];
        Arrays.fill(cut, Integer.MAX_VALUE);
        cut[0] = 0;
        for (int i = 1; i <= n; i++)
            for (int j = 1; j <= i; j++)
                if (pal[j - 1][i - 1]) cut[i] = Math.min(cut[i], cut[j - 1] + 1);
        System.out.println(cut[n] - 1);
    }
}
```

<!-- test
in:
aab
out:
1
-->
<!-- test
in:
abcba
out:
0
-->
<!-- test
in:
abacdc
out:
1
-->
<!-- test
in:
a
out:
0
-->

---

## 4. Recognising the pattern

| Signal | Interval DP flavour |
|---|---|
| "merge adjacent", cost = size/sum of the merged block, $n \le 500$ | split at $k$ (last merge), Knuth for $n \le 5000$ |
| "parenthesise / order the operations of an associative chain" | split at $k$ |
| "remove an element; score depends on its current neighbours" | last element removed in $(l,r)$ with walls $l, r$ |
| "delete a block of equal elements", "paint a segment with one colour" | what happens to $s_l$ — piggyback on the next equal element |
| score of deleting $x$ equal things is arbitrary in $x$ | add a glued-count dimension |
| "players take from either end" | difference DP $g(l,r)$ |
| palindromes inside substrings, many queries | $O(n^2)$ table + 2-D inclusion–exclusion |
| circle of piles | double the array |
| $n \le 100$ with a third small parameter | $O(n^3)$–$O(n^4)$ interval DP is intended |
| $n \ge 10^5$ | not interval DP (unless a greedy/stack replaces it) |

Often confused with: **prefix DP with segment partition** ($f(i) = \min_j f(j) + \text{cost}(j+1,i)$) — that is a 1-D DP over prefixes where each segment's cost is independent; interval DP is needed when segments are *built recursively* from smaller segments.

---

## 5. Worked examples (graded)

### Example 1 — Deque (removal game)  ·  ★ ≈1500 (est.)

- **Source:** [AtCoder DP L · Deque](https://atcoder.jp/contests/dp/tasks/dp_l)
- **Difficulty:** ≈1500 (est.)
- **Problem:** A sequence of $n \le 3000$ integers ($\le 10^9$). Two players alternately remove the first or the last element and add it to their score; the first player wants to maximise $X - Y$, the second to minimise it. Print $X - Y$ under optimal play.
- **Thinking from first principles:** The remaining elements always form a segment, and whose turn it is follows from the segment length — but we don't even need that: define the value from the point of view of *whoever moves*. Then both players maximise the same function, and the opponent's optimal value enters with a minus sign. $n^2/2 = 4.5\cdot10^6$ states, 2 transitions each. Values reach $3\cdot10^{12}$: 64-bit.

<details><summary>Solution</summary>

$g(l,r) = \max(a_l - g(l+1,r), a_r - g(l,r-1))$, $g$ of an empty segment $= 0$; answer $g(0,n-1)$. Order: $l$ descending, $r$ ascending. A 1-D array suffices: `g[r]` for the current $l$ overwrites the row of $l+1$. $O(n^2)$ time, $O(n)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> a(n), g(n);
    for (auto& x : a) cin >> x;
    for (int l = n - 1; l >= 0; l--) {
        g[l] = a[l];
        for (int r = l + 1; r < n; r++)                // g[r] still holds g(l+1, r); g[r-1] is g(l, r-1)
            g[r] = max(a[l] - g[r], a[r] - g[r - 1]);
    }
    cout << g[n - 1] << "\n";
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
        long[] a = new long[n], g = new long[n];
        for (int i = 0; i < n; i++) a[i] = nl();
        for (int l = n - 1; l >= 0; l--) {
            g[l] = a[l];
            for (int r = l + 1; r < n; r++) g[r] = Math.max(a[l] - g[r], a[r] - g[r - 1]);
        }
        System.out.println(g[n - 1]);
    }
}
```

</details>

<!-- test
in:
3
1 100 1
out:
-98
-->
<!-- test
in:
1
7
out:
7
-->
<!-- test
in:
6
3 9 1 2 8 5
out:
4
-->

### Example 2 — Slimes (merge adjacent piles)  ·  ★ ≈1600 (est.)

- **Source:** [AtCoder DP N · Slimes](https://atcoder.jp/contests/dp/tasks/dp_n)
- **Difficulty:** ≈1600 (est.)
- **Problem:** $n \le 400$ slimes in a row with sizes $a_i \le 10^9$. Merging two adjacent slimes of sizes $x, y$ costs $x+y$ and creates one of size $x+y$. Minimum total cost to merge all into one.
- **Thinking from first principles:** Greedy "merge the smallest adjacent pair" fails: on $4,3,3,4$ it merges the 3s first and pays $6+10+14=30$, while $(4+3)+(3+4)$ then $14$ pays $28$ (Huffman's greedy needs *any* pair, not adjacent ones). The final merge of $[l,r]$ joins a slime built from $[l,k]$ and one from $[k+1,r]$, built independently, and costs $S(l,r)$ whatever $k$ is. Sizes sum to $4\cdot10^{11}$ and costs to more — 64-bit.

<details><summary>Solution</summary>

Prefix sums for $S$; by length. $O(n^3/6) \approx 10^7$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> P(n + 1, 0);
    for (int i = 0; i < n; i++) { long long x; cin >> x; P[i + 1] = P[i] + x; }
    vector<vector<long long>> f(n, vector<long long>(n, 0));
    for (int len = 2; len <= n; len++)
        for (int l = 0; l + len - 1 < n; l++) {
            int r = l + len - 1;
            long long best = LLONG_MAX;
            for (int k = l; k < r; k++) best = min(best, f[l][k] + f[k + 1][r]);
            f[l][r] = best + P[r + 1] - P[l];
        }
    cout << f[0][n - 1] << "\n";
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
        long[] P = new long[n + 1];
        for (int i = 0; i < n; i++) P[i + 1] = P[i] + nl();
        long[][] f = new long[n][n];
        for (int len = 2; len <= n; len++)
            for (int l = 0; l + len - 1 < n; l++) {
                int r = l + len - 1;
                long best = Long.MAX_VALUE;
                for (int k = l; k < r; k++) best = Math.min(best, f[l][k] + f[k + 1][r]);
                f[l][r] = best + P[r + 1] - P[l];
            }
        System.out.println(f[0][n - 1]);
    }
}
```

</details>

<!-- test
in:
5
3 1 4 1 5
out:
32
-->
<!-- test
in:
1
10
out:
0
-->
<!-- test
in:
3
1000000000 1000000000 1000000000
out:
5000000000
-->

### Example 3 — Burst balloons  ·  ★ ≈1900 (est.)

- **Source:** Original problem (stdin version of [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard).
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n \le 300$ balloons with values $0 \le v_i \le 100$. Bursting balloon $i$ scores $v_L \cdot v_i \cdot v_R$ where $L$, $R$ are its current neighbours (value 1 beyond the ends); it then disappears. Maximise the total score.
- **Thinking from first principles:** The first-burst decomposition couples the two sides (§1.4). The last-burst decomposition with walls $l, r$ makes them independent, and the final burst's score $v_l v_k v_r$ is known. Pad with 1s and work on open intervals.

<details><summary>Solution</summary>

$f(l,r)$ over open intervals of the padded array $w_0..w_{n+1}$; $f(l,l+1)=0$; answer $f(0,n+1)$. $O(n^3)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> w(n + 2, 1);
    for (int i = 1; i <= n; i++) cin >> w[i];
    vector<vector<long long>> f(n + 2, vector<long long>(n + 2, 0));
    for (int len = 2; len <= n + 1; len++)            // len = r - l
        for (int l = 0; l + len <= n + 1; l++) {
            int r = l + len;
            long long best = 0;
            for (int k = l + 1; k < r; k++)           // k is the last balloon burst inside (l, r)
                best = max(best, f[l][k] + f[k][r] + w[l] * w[k] * w[r]);
            f[l][r] = best;
        }
    cout << f[0][n + 1] << "\n";
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
        long[] w = new long[n + 2];
        w[0] = w[n + 1] = 1;
        for (int i = 1; i <= n; i++) w[i] = nl();
        long[][] f = new long[n + 2][n + 2];
        for (int len = 2; len <= n + 1; len++)
            for (int l = 0; l + len <= n + 1; l++) {
                int r = l + len;
                long best = 0;
                for (int k = l + 1; k < r; k++) best = Math.max(best, f[l][k] + f[k][r] + w[l] * w[k] * w[r]);
                f[l][r] = best;
            }
        System.out.println(f[0][n + 1]);
    }
}
```

</details>

<!-- test
in:
5
1 2 3 4 5
out:
110
-->
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
9 0
out:
9
-->

### Example 4 — Clear the String  ·  ★ 2000

- **Source:** [CF 1132F · Clear the String](https://codeforces.com/problemset/problem/1132/F) — 2000
- **Difficulty:** 2000
- **Problem:** A string of length $n \le 500$ (lowercase). One operation deletes a contiguous substring whose letters are all equal. Minimum number of operations to delete the whole string.
- **Thinking from first principles:** After deletions, letters that were far apart become adjacent and can go in one operation — so "split at $k$" with independent halves misses solutions where one operation spans both halves. Look instead at the operation that deletes $s_l$: either it deletes nothing else useful (cost $1 + f(l+1,r)$), or the next letter it deletes is some $s_k = s_l$; then $[l+1,k-1]$ is cleared first, independently, and $s_l$ rides along with $s_k$ (cost $f(l+1,k-1) + f(k,r)$). Every solution falls in exactly one of these cases, and the parts are independent.

<details><summary>Solution</summary>

$f(l, r)$ with $f(l, l-1) = 0$; $l$ descending, $r$ ascending. $O(n^3)$ worst case ($\approx 2\cdot10^7$).

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    string s;
    cin >> n >> s;
    vector<vector<int>> f(n + 1, vector<int>(n + 1, 0));    // f[l][r], empty when r < l
    auto F = [&](int l, int r) { return r < l ? 0 : f[l][r]; };
    for (int l = n - 1; l >= 0; l--)
        for (int r = l; r < n; r++) {
            int best = 1 + F(l + 1, r);                      // s[l] deleted by its own operation
            for (int k = l + 1; k <= r; k++)
                if (s[k] == s[l]) best = min(best, F(l + 1, k - 1) + F(k, r));   // s[l] rides with s[k]
            f[l][r] = best;
        }
    cout << f[0][n - 1] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        char[] s = br.readLine().trim().toCharArray();
        int[][] f = new int[n + 1][n + 1];             // f[l][r] for r >= l; f[l][l-1] stays 0
        for (int l = n - 1; l >= 0; l--)
            for (int r = l; r < n; r++) {
                int best = 1 + (l + 1 <= r ? f[l + 1][r] : 0);
                for (int k = l + 1; k <= r; k++)
                    if (s[k] == s[l]) {
                        int left = l + 1 <= k - 1 ? f[l + 1][k - 1] : 0;
                        best = Math.min(best, left + f[k][r]);
                    }
                f[l][r] = best;
            }
        System.out.println(f[0][n - 1]);
    }
}
```

</details>

<!-- test
in:
7
abacaba
out:
4
-->
<!-- test
in:
1
z
out:
1
-->
<!-- test
in:
6
aabbaa
out:
2
-->

### Example 5 — Vasya and Binary String  ·  ★ 2400

- **Source:** [CF 1107E · Vasya and Binary String](https://codeforces.com/problemset/problem/1107/E) — 2400
- **Difficulty:** 2400
- **Problem:** A binary string of length $n \le 100$ and scores $a_1..a_n$ ($\le 10^9$). One operation erases a contiguous block of $x$ equal characters and scores $a_x$; the rest closes up. Maximise the total score of erasing the whole string.
- **Thinking from first principles:** Example 4's "piggyback" idea applies, but now the score of the operation that erases $s_l$ depends on *how many* characters it erases — information that a pure segment state cannot hold. Add exactly that: the number $k$ of characters equal to $s_l$ already glued in front of it. Also, an operation erasing $x$ glued equal characters may be better split into several operations (scores are arbitrary), so precompute $\text{best}(x)$, an unbounded knapsack over block sizes.

<details><summary>Solution</summary>

$f(l, r, k)$ as in §1.6; answer $f(0, n-1, 0)$. Memoised recursion over $(l, r, k)$ with $k \le l$ keeps the reachable states small. $O(n^4)$ worst case, fast in practice.

```cpp
#include <bits/stdc++.h>
using namespace std;

int n;
string s;
vector<long long> best;
long long memo[101][101][101];
bool seen[101][101][101];

long long f(int l, int r, int k) {                    // k copies of s[l] glued before l
    if (l > r) return 0;
    if (seen[l][r][k]) return memo[l][r][k];
    long long res = best[k + 1] + f(l + 1, r, 0);     // erase s[l] with its glued copies now
    for (int m = l + 1; m <= r; m++)
        if (s[m] == s[l]) res = max(res, f(l + 1, m - 1, 0) + f(m, r, k + 1));   // glue s[l] onto s[m]
    seen[l][r][k] = true;
    return memo[l][r][k] = res;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    cin >> n >> s;
    vector<long long> a(n + 1);
    for (int i = 1; i <= n; i++) cin >> a[i];
    best.assign(n + 1, 0);
    for (int x = 1; x <= n; x++)
        for (int y = 1; y <= x; y++) best[x] = max(best[x], a[y] + best[x - y]);
    cout << f(0, n - 1, 0) << "\n";
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

    static char[] s;
    static long[] best;
    static long[][][] memo;
    static boolean[][][] seen;

    static long f(int l, int r, int k) {
        if (l > r) return 0;
        if (seen[l][r][k]) return memo[l][r][k];
        long res = best[k + 1] + f(l + 1, r, 0);
        for (int m = l + 1; m <= r; m++)
            if (s[m] == s[l]) res = Math.max(res, f(l + 1, m - 1, 0) + f(m, r, k + 1));
        seen[l][r][k] = true;
        return memo[l][r][k] = res;
    }

    public static void main(String[] args) throws IOException {
        int n = Integer.parseInt(ns());
        s = ns().toCharArray();
        long[] a = new long[n + 1];
        for (int i = 1; i <= n; i++) a[i] = Long.parseLong(ns());
        best = new long[n + 1];
        for (int x = 1; x <= n; x++)
            for (int y = 1; y <= x; y++) best[x] = Math.max(best[x], a[y] + best[x - y]);
        memo = new long[n][n][n + 1];
        seen = new boolean[n][n][n + 1];
        System.out.println(f(0, n - 1, 0));
    }
}
```

</details>

<!-- test
in:
5
10110
2 9 3 1 20
out:
20
-->
<!-- test
in:
1
1
5
out:
5
-->
<!-- test
in:
4
0000
1 1 1 100
out:
100
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Iterate by length** (or $l$ descending, $r$ ascending). Write the loop order *before* the transition and check every read is to a shorter segment.
2. **Empty segments:** decide $f(l, l-1)$ explicitly (usually 0) and guard index $l+1 > r$ — Example 4's helper `F` keeps the code clean.
3. **Open vs closed intervals:** Burst Balloons is cleanest on open intervals with padded walls; mixing open and closed conventions causes off-by-one bugs.
4. **First vs last:** if the parts after your chosen operation still interact, switch from "first" to "last" (or to "what happens to the first element").
5. **Overflow:** merge costs reach $n \cdot \sum a$; matrix-chain products of three dimensions overflow `int`.
6. **Memory:** $n = 5000$ gives $2.5\cdot10^7$ cells = 100 MB as `int`, over most limits. Use `short` when values fit, store only the triangle $l \le r$, or roll by $l$ when the recurrence allows (Example 1 uses $O(n)$).
7. **Game DPs:** store the difference, not each player's score; it makes the recurrence symmetric and avoids a "whose turn" dimension.
8. **Glued-counter DPs** (Example 5): the counter can be bounded by the number of equal characters to the left; memoise only reachable states.
9. **Java recursion** in memoised interval DPs is shallow (depth $\le n$), but 3-D `long` arrays of $101^3$ are 8 MB — fine; $500^3$ would not be.
10. **Knuth bounds:** when using Knuth, initialise $\text{opt}(l,l) = l$ and iterate by length; the window $[\text{opt}(l,r-1), \text{opt}(l+1,r)]$ must be non-empty.

---

## 7. Going further (toward 2400–2600+)

- **Knuth / quadrangle inequality** for $O(n^2)$ merges and optimal BSTs ([Knuth](../07-DP-Optimizations/04-knuth-optimization.md)).
- **Zuma** (CF 607B) and **Strange Printer** (LC 664): the same "first element joins a later equal element" decomposition with different base cases.
- **Interval DP on bracket structures** (CF 149D *Coloring Brackets*): segments correspond to matched pairs; the state adds the colours at the two ends.
- **Interval DP + number theory** (CF 1025D *Recovering BST*): state $(l, r, \text{side})$ — can the segment hang below its left/right neighbour as parent.
- **Paint with few occurrences per colour** (CF 1572C, 🔴): $O(n^2 \cdot 20)$ by only trying split points with equal colour.
- **Interval DP over a polygon** (triangulation, LC 1039): vertices of a convex polygon play the role of positions; the last triangle containing edge $(l, r)$ fixes $k$.
- **Removing segments as a 2-D interval DP** (CSES 1744 *Rectangle Cutting*): the state is a rectangle $(w, h)$, splits along either axis.

---

## 8. Practice ladder

**1400–1800**
- [ ] [AtCoder DP L · Deque](https://atcoder.jp/contests/dp/tasks/dp_l)
- [ ] [CSES 1097 · Removal Game](https://cses.fi/problemset/task/1097) — the same game, print the first player's total
- [ ] [AtCoder DP N · Slimes](https://atcoder.jp/contests/dp/tasks/dp_n)
- [ ] [CSES 1744 · Rectangle Cutting](https://cses.fi/problemset/task/1744)
- [ ] [CF 245H · Queries for Number of Palindromes](https://codeforces.com/problemset/problem/245/H) — 1800
- [ ] [CF 983B · XOR-pyramid](https://codeforces.com/problemset/problem/983/B) — 1800
- [ ] [CF 1509C · The Sports Festival](https://codeforces.com/problemset/problem/1509/C) — 1800

**1900–2200**
- [ ] [CF 1114D · Flood Fill](https://codeforces.com/problemset/problem/1114/D) — 1900
- [ ] [CF 149D · Coloring Brackets](https://codeforces.com/problemset/problem/149/D) — 1900
- [ ] [CF 607B · Zuma](https://codeforces.com/problemset/problem/607/B) — 1900
- [ ] [CF 1132F · Clear the String](https://codeforces.com/problemset/problem/1132/F) — 2000
- [ ] [CF 1312E · Array Shrinking](https://codeforces.com/problemset/problem/1312/E) — 2100
- [ ] [CF 1025D · Recovering BST](https://codeforces.com/problemset/problem/1025/D) — 2100
- [ ] [CF 1336C · Kaavi and Magic Spell](https://codeforces.com/problemset/problem/1336/C) — 2200

**2300+**
- [ ] [CF 1198D · Rectangle Painting 1](https://codeforces.com/problemset/problem/1198/D) — 2300
- [ ] [CF 1107E · Vasya and Binary String](https://codeforces.com/problemset/problem/1107/E) — 2400
- [ ] [CF 1572C · Paint](https://codeforces.com/problemset/problem/1572/C) — 2700

---

## 9. LeetCode / FAANG cross-reference

- [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard — last balloon (Example 3).
- [LC 1039 · Minimum Score Triangulation of Polygon](https://leetcode.com/problems/minimum-score-triangulation-of-polygon/) — Medium — triangle on edge $(l,r)$.
- [LC 1000 · Minimum Cost to Merge Stones](https://leetcode.com/problems/minimum-cost-to-merge-stones/) — Hard — $K$-way merges: state $(l, r)$ plus "number of piles mod $K-1$".
- [LC 1547 · Minimum Cost to Cut a Stick](https://leetcode.com/problems/minimum-cost-to-cut-a-stick/) — Hard — first cut = split at $k$ over the sorted cut positions.
- [LC 132 · Palindrome Partitioning II](https://leetcode.com/problems/palindrome-partitioning-ii/) — Hard — palindrome table + prefix DP (§3.2).
- [LC 516 · Longest Palindromic Subsequence](https://leetcode.com/problems/longest-palindromic-subsequence/) — Medium — $g(l,r)$.
- [LC 486 · Predict the Winner](https://leetcode.com/problems/predict-the-winner/) — Medium — difference DP.
- [LC 877 · Stone Game](https://leetcode.com/problems/stone-game/) — Medium — same DP (and a parity trick shows the first player always wins).
- [LC 375 · Guess Number Higher or Lower II](https://leetcode.com/problems/guess-number-higher-or-lower-ii/) — Medium — minimax over a split point.
- [LC 664 · Strange Printer](https://leetcode.com/problems/strange-printer/) — Hard — first character rides with a later equal one.
- [LC 546 · Remove Boxes](https://leetcode.com/problems/remove-boxes/) — Hard — glued-count dimension (Example 5 with $a_x = x^2$).
- [LC 1312 · Minimum Insertion Steps to Make a String Palindrome](https://leetcode.com/problems/minimum-insertion-steps-to-make-a-string-palindrome/) — Hard — $n - \text{LPS}$.

---

## 10. Self-check

1. Give a loop order other than "by length" that is valid for $f(l,r)$ depending on $f(l,k)$ and $f(k+1,r)$.
2. In Burst Balloons, why do the walls $l$ and $r$ make the two sides independent?
3. Why is "split at $k$ into independent halves" wrong for Clear the String?
4. What extra information does Remove Boxes need, and why can't it be recovered from the segment?
5. Write the removal-game recurrence and explain the minus sign.
6. How many iterations does the triple loop of an $O(n^3)$ interval DP perform for $n = 400$?
7. When can Knuth's optimisation be applied, and what does it give?

<details><summary>Answers</summary>

1. $l$ from $n-1$ down to 0, $r$ from $l$ up to $n-1$: $f(l,k)$ with $k<r$ is computed earlier in the same row, $f(k+1,r)$ in an earlier row.
2. When $k$ is the last balloon burst in $(l,r)$, while the left part's balloons burst, $k$ is still present, so each of them has neighbours inside $[l,k]$; the right part only sees $[k, r]$. The final burst of $k$ sees exactly $l$ and $r$.
3. One operation can delete equal letters from both halves after the letters between them disappear; a split into independently cleared halves cannot express that.
4. How many boxes equal to the first one are glued to it from earlier merges; the score of the operation depends on that count, which comes from outside the segment.
5. $g(l,r) = \max(a_l - g(l+1,r), a_r - g(l,r-1))$: after my move, the opponent plays optimally on the rest and achieves difference $g$ from *their* point of view, which is $-g$ from mine.
6. $(n^3-n)/6 \approx 1.07\cdot10^7$.
7. When the cost satisfies the quadrangle inequality and monotonicity, so $\text{opt}(l,r-1)\le\text{opt}(l,r)\le\text{opt}(l+1,r)$; scanning only that window makes the total $O(n^2)$.

</details>
