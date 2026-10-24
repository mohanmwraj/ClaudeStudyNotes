# Constructive algorithms

> **Band:** 🟢–🟠 800–2400 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [brute force and backtracking](../01-Foundations/04-recursion-brute-force-and-backtracking.md), [bit manipulation](../01-Foundations/03-bit-manipulation.md), [invariants and parity](04-invariants-parity-and-ad-hoc-observations.md)
> **You can say you know this when:** faced with "print any object with property P, or −1", you brute-force small sizes to learn *which* cases are possible and what answers look like, prove impossibility with an invariant, give a construction (pattern, induction, extremes, bits, graph order) for every other case, and verify it with a checker before submitting.

## 1. First principles — why this works

A constructive problem asks for a **witness**: an array, permutation, grid, graph or sequence of operations with a
property, or a proof that none exists. The judge runs a checker, so any valid answer is accepted. That changes how you
think: you do not need the best object, only *an* object, and you are free to pick one with extra structure that makes
the property easy to verify.

Every constructive problem has two halves, and strong solvers do them in this order:

1. **Necessity — when is it impossible?** Find conditions every valid answer must satisfy: parity, sums modulo $k$,
   counting (pigeonhole), an invariant of the allowed operations, a colouring. This narrows the cases your construction
   must handle, and it is usually where the "−1" cases come from.
2. **Sufficiency — build it in every remaining case.** Now look for a construction that works whenever the necessary
   condition holds. If you cannot, the condition is probably not sufficient yet: go back to step 1.

### Where constructions come from

**(a) Small cases by brute force.** Enumerate all objects for $n = 1..8$ (permutations, binary strings, small arrays),
print how many valid ones exist and the lexicographically smallest. Within a minute you learn which $n$ are impossible
(the "−1" set), whether answers exist for all large $n$, and often the shape of a solution (descending odds, alternating
blocks, a period). §3.1 is a reusable explorer. This is the single most effective habit for Div2 B–D constructives.

**(b) Induction / recursion.** Reduce $n$ to $n-1$, $n-2$ or $n/2$: if you can extend a valid object of size $n-2$ by two
elements while keeping the property, you need only the base cases. Gray codes (reflect and prefix a bit), Tower of Hanoi,
"beautiful array" (odds of a smaller beautiful array, then evens) are pure induction. When extending at the end is
hard, try extending at the front, in the middle, or by doubling.

**(c) Extremes first.** Place the element that is most constrained or most powerful first: the largest value (it creates
the most inversions, it can only be adjacent to few values), the smallest, the vertex of largest degree, the longest
string. After it is placed the remainder is often an unconstrained smaller instance.

**(d) Choose a canonical shape with a free parameter.** "Answer always exists" in the statement is a hint that a
uniform construction works — for instance "make every cell's parity equal to $(i+j) \bmod 2$" or "orient every edge
along one fixed total order". The trick is to spend the freedom the problem gives (here: $+0$ or $+1$) on enforcing a
global structure that implies the local property.

**(e) Bits and XOR.** Build answers bit by bit, use $a \oplus a = 0$ to cancel, pad with pairs $(x, x)$ that change the sum
but not the XOR, pair $i$ with its complement $2^k - 1 - i$ to get disjoint bits.

**(f) Graph orders.** A DAG is exactly a graph that admits a topological order; orienting every edge from earlier to
later in *any* total order gives a DAG. Bipartite colouring, DFS trees (non-tree edges join ancestor and descendant),
stars and paths (extreme diameters) are the stock shapes.

### Verify, don't trust

A construction that "looks right" fails on the case you did not draw. Always write the checker (it is usually 15 lines
and much easier than the construction), then run the construction for **every** small input against it, and run the
brute force to confirm the impossibility condition in **both** directions (no valid object exists exactly when you
print −1).

### Output-format pitfalls

Constructive problems are where most "Wrong answer on test 1" verdicts come from:

- **Multiple test cases with $\sum n \le 2\cdot 10^5$:** reset every array per test (or size them per test); never
  allocate $O(\max n)$ per test case in a loop of $10^4$ tests.
- Print exactly what is asked: `YES`/`NO` first if requested (case usually does not matter, but check), the length
  before the elements, `-1` on its own line, an empty line for an empty array if the format expects one.
- Large outputs ($10^5$–$10^6$ numbers): build one string / use `PrintWriter`; avoid `endl` in C++ and
  `System.out.println` per number in Java.
- 1-indexed vs 0-indexed vertices and positions.

## 2. Formulas, definitions and identities

- **Inversions.** A permutation of $n$ has between $0$ and $\binom{n}{2}$ inversions, and every value in between is
  achievable. Placing the largest of $m$ remaining values first creates exactly $m-1$ inversions; placing the
  $(t+1)$-th smallest creates exactly $t$.
- **Permutation parity.** A transposition changes the number of inversions by an odd amount, so it flips the parity;
  a permutation that is a product of $c$ disjoint cycles (including fixed points) has parity $n - c$. Used for
  impossibility ("each operation is an even permutation, the target is odd").
- **Gray code.** $g(i) = i \oplus (i \gg 1)$; consecutive codes differ in one bit, and $g$ is a bijection on $[0, 2^k)$.
  Reflection: $G_{k+1} = 0G_k, 1G_k^{\text{rev}}$.
- **Sum and XOR.** $a + b = (a \oplus b) + 2(a \mathbin{\&} b)$. Hence an array with XOR $u$ and sum $v$ needs $v \ge u$ and
  $v - u$ even (each element's contribution to the sum and to the XOR agrees modulo 2). If $c = (v-u)/2$: $[u, c, c]$
  always works; $[u + c, c]$ works iff $u \mathbin{\&} c = 0$.
- **Complement pairing.** For $0 \le i < 2^k$: $i \oplus (2^k - 1 - i) = 2^k - 1$ and $i \mathbin{\&} (2^k-1-i) = 0$.
- **Two equal-sum halves of $1..n$** exist iff $n(n+1)/2$ is even, i.e. $n \bmod 4 \in \{0, 3\}$; greedily take the
  largest numbers into one half until it reaches half the sum (CSES "Two Sets").
- **Erdős–Szekeres.** Every sequence of more than $(r-1)(s-1)$ distinct numbers has an increasing subsequence of length
  $r$ or a decreasing one of length $s$; the bound is tight: concatenate $r-1$ decreasing blocks of length $s-1$, each
  block larger than the previous one (CSES "Monotone Subsequences").
- **Chessboard colouring.** Grid cells with $(i+j) \bmod 2$ form a bipartition: side-adjacent cells always differ.
- **DAG orientation.** For any total order $\pi$ of the vertices, orienting each edge $\{x,y\}$ as $x \to y$ iff
  $\pi(x) < \pi(y)$ gives an acyclic graph (every edge increases $\pi$).
- **Pigeonhole existence.** Among prefix sums $S_0..S_n$ taken modulo $n$, two coincide, so some non-empty subarray has
  sum divisible by $n$ — a guaranteed-existence construction in $O(n)$.

## 3. Implementation (C++ and Java)

### 3.1 Small-case explorer (find the pattern before you think)

Reads $N$ and, for every $n \le N$, prints the number of permutations of $1..n$ with the property and the
lexicographically smallest one (or −1). Swap the predicate `ok` for your problem; here it is "adjacent differences
between 2 and 4" (CF 1352G).

```cpp
#include <bits/stdc++.h>
using namespace std;
bool ok(const vector<int>& p) {                     // the property under study
    for (size_t i = 0; i + 1 < p.size(); i++) {
        int d = abs(p[i] - p[i + 1]);
        if (d < 2 || d > 4) return false;
    }
    return true;
}
int main() {
    int N; cin >> N;
    for (int n = 1; n <= N; n++) {
        vector<int> p(n);
        iota(p.begin(), p.end(), 1);
        long long cnt = 0; vector<int> first;
        do {
            if (ok(p)) { if (cnt == 0) first = p; cnt++; }
        } while (next_permutation(p.begin(), p.end()));   // lexicographic order, so 'first' is the smallest
        cout << n << ' ' << cnt;
        if (cnt == 0) cout << " -1";
        for (int x : first) cout << ' ' << x;
        cout << '\n';
    }
}
```

```java
import java.util.*;

public class Main {
    static boolean ok(int[] p) {
        for (int i = 0; i + 1 < p.length; i++) {
            int d = Math.abs(p[i] - p[i + 1]);
            if (d < 2 || d > 4) return false;
        }
        return true;
    }
    static boolean nextPermutation(int[] a) {
        int i = a.length - 2;
        while (i >= 0 && a[i] >= a[i + 1]) i--;
        if (i < 0) return false;
        int j = a.length - 1;
        while (a[j] <= a[i]) j--;
        int t = a[i]; a[i] = a[j]; a[j] = t;
        for (int l = i + 1, r = a.length - 1; l < r; l++, r--) { t = a[l]; a[l] = a[r]; a[r] = t; }
        return true;
    }
    public static void main(String[] args) {
        int N = new Scanner(System.in).nextInt();           // tiny input: Scanner is fine outside contest templates
        StringBuilder sb = new StringBuilder();
        for (int n = 1; n <= N; n++) {
            int[] p = new int[n];
            for (int i = 0; i < n; i++) p[i] = i + 1;
            long cnt = 0; int[] first = null;
            do {
                if (ok(p)) { if (cnt == 0) first = p.clone(); cnt++; }
            } while (nextPermutation(p));
            sb.append(n).append(' ').append(cnt);
            if (cnt == 0) sb.append(" -1");
            else for (int x : first) sb.append(' ').append(x);
            sb.append('\n');
        }
        System.out.print(sb);
    }
}
```

<!-- test
in:
5
out:
1 1 1
2 0 -1
3 0 -1
4 2 2 4 1 3
5 14 1 3 5 2 4
-->

Reading the output: $n = 2, 3$ are impossible, everything from 4 on works, and the smallest answers start with the
odd numbers. The construction in Example 2 is one step away.

### 3.2 Checker and two classic generators

```cpp
// Checker: is p a permutation of 1..n with |p[i] - p[i+1]| in [lo, hi]?
bool checkPerm(const vector<int>& p, int lo, int hi) {
    int n = p.size();
    vector<char> seen(n + 1, 0);
    for (int x : p) { if (x < 1 || x > n || seen[x]) return false; seen[x] = 1; }
    for (int i = 0; i + 1 < n; i++) { int d = abs(p[i] - p[i + 1]); if (d < lo || d > hi) return false; }
    return true;
}
// Gray code of k bits: consecutive values differ in exactly one bit.
vector<int> grayCode(int k) {
    vector<int> g(1 << k);
    for (int i = 0; i < (1 << k); i++) g[i] = i ^ (i >> 1);
    return g;
}
// Split 1..n into two sets of equal sum (empty vector if impossible): take the largest numbers greedily.
vector<int> twoSetsFirstHalf(long long n) {
    long long total = n * (n + 1) / 2;
    if (total % 2) return {};
    long long need = total / 2;
    vector<int> a;
    for (long long x = n; x >= 1 && need > 0; x--)
        if (x <= need) { a.push_back((int)x); need -= x; }   // the remaining 'need' is always < x afterwards
    return a;
}
```

```java
static boolean checkPerm(int[] p, int lo, int hi) {
    int n = p.length;
    boolean[] seen = new boolean[n + 1];
    for (int x : p) { if (x < 1 || x > n || seen[x]) return false; seen[x] = true; }
    for (int i = 0; i + 1 < n; i++) { int d = Math.abs(p[i] - p[i + 1]); if (d < lo || d > hi) return false; }
    return true;
}
static int[] grayCode(int k) {
    int[] g = new int[1 << k];
    for (int i = 0; i < (1 << k); i++) g[i] = i ^ (i >> 1);
    return g;
}
static List<Integer> twoSetsFirstHalf(long n) {
    long total = n * (n + 1) / 2;
    List<Integer> a = new ArrayList<>();
    if (total % 2 != 0) return a;
    long need = total / 2;
    for (long x = n; x >= 1 && need > 0; x--)
        if (x <= need) { a.add((int) x); need -= x; }
    return a;
}
```

Why the greedy in `twoSetsFirstHalf` always finishes: while `need` $\ge x$ we take $x$; the first time `need` $< x$
the value `need` itself is still available (all numbers below $x$ are unused), so it is taken when the loop reaches it.

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| "print any …", "if there are multiple answers, print any", "or report that it is impossible" | constructive: necessity first, then construction, then checker |
| tiny-looking constraints on a weird property ("adjacent differences between 2 and 4") | brute-force explorer for $n \le 8$, read the pattern |
| "it can be shown that an answer always exists" | a uniform construction with a free parameter (parity, order, colouring) |
| "exactly $k$ inversions / exactly $k$ distinct values / exactly $k$ …" | extremes first: spend $k$ greedily with the most powerful element |
| sums and XORs of the same array | $a+b = (a\oplus b) + 2(a\,\&\,b)$, parity, padding with equal pairs |
| "orient / direct the edges so that …acyclic…" | topological order of the fixed part |
| grid, "no two adjacent equal" | chessboard colouring, parity of $i+j$ |
| "at most $n$ / $2n$ / $3n$ operations" | each operation fixes one element (selection-sort style) or a pair; the budget hints at the construction |
| "find a long path *or* a large independent set" | DFS tree depth dichotomy (Going further) |

**Commonly confused with:** greedy optimisation. In a constructive problem you need *feasibility*, not optimality —
if you are trying to prove that something is optimal, check whether the statement asks for it at all.

## 5. Worked examples (graded)

### Example 1 — Inverse Inversions  ·  ★ ≈1500 (est.)

- **Source:** [CSES 2214 · Inverse Inversions](https://cses.fi/problemset/task/2214)
- **Difficulty:** ≈1500 (est.)
- **Problem:** given $n \le 10^6$ and $0 \le k \le \binom{n}{2}$, print a permutation of $1..n$ with exactly $k$ inversions.
- **Thinking from first principles:** which element "spends" inversions most efficiently? Putting the largest of the
  $m$ remaining values in front creates $m-1$ inversions with everything after it, and the rest is a smaller instance.
  So spend greedily: while $k \ge m-1$, emit the largest remaining value. Once $k < m-1$, emit the $(k+1)$-th smallest
  remaining value — exactly $k$ smaller values follow it — and then the rest in increasing order (0 more inversions).

<details><summary>Solution</summary>

Remaining values always form a contiguous range $[lo, hi]$ while we only take the largest, so no data structure is
needed. $O(n)$. Correctness: each step creates exactly the claimed number of inversions, and the greedy never gets stuck
because $\binom{m}{2} \ge k$ is preserved ($k - (m-1) \le \binom{m-1}{2}$ when $k \le \binom{m}{2}$).

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    long long n, k; cin >> n >> k;
    string out;
    long long lo = 1, hi = n;
    for (long long m = n; m >= 1; m--) {
        if (k >= m - 1) { out += to_string(hi--); out += ' '; k -= m - 1; continue; }
        long long pick = lo + k;                        // k smaller values remain after it
        out += to_string(pick); out += ' ';
        for (long long x = lo; x <= hi; x++) if (x != pick) { out += to_string(x); out += ' '; }
        break;
    }
    out.back() = '\n';
    cout << out;
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken()), k = Long.parseLong(st.nextToken());
        StringBuilder sb = new StringBuilder();
        long lo = 1, hi = n;
        for (long m = n; m >= 1; m--) {
            if (k >= m - 1) { sb.append(hi--).append(' '); k -= m - 1; continue; }
            long pick = lo + k;
            sb.append(pick).append(' ');
            for (long x = lo; x <= hi; x++) if (x != pick) sb.append(x).append(' ');
            break;
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(sb.toString().trim());
        out.flush();
    }
}
```

<!-- test
in:
5 4
out:
5 1 2 3 4
-->
<!-- test
in:
4 6
out:
4 3 2 1
-->
<!-- test
in:
1 0
out:
1
-->
<!-- test
in:
5 5
out:
5 2 1 3 4
-->

</details>

### Example 2 — Special Permutation  ·  ★ 1600

- **Source:** [CF 1352G · Special Permutation](https://codeforces.com/problemset/problem/1352/G) — 1600
- **Difficulty:** 1600
- **Problem:** $t$ test cases, each with $2 \le n \le 1000$. Print a permutation of $1..n$ in which every two adjacent
  values differ by at least 2 and at most 4, or −1 if none exists.
- **Thinking from first principles:** run the explorer (§3.1): $n = 2, 3$ impossible (for $n=3$, value 2 differs by 1
  from both others), all $n \ge 4$ possible, and the smallest answers begin $1, 3, 5, \dots$. Odd numbers in a row differ
  by 2, even numbers in a row differ by 2; we only need one good junction between the two runs. Ending the odd run at 1
  and starting the even run at 4 gives difference 3, then $4 \to 2$ is 2 and $2 \to 6$ is 4. So: odds descending to 1,
  then $4, 2$, then $6, 8, 10, \dots$

<details><summary>Solution</summary>

For $n \ge 4$ print the odd numbers from the largest down to 1, then 4, 2, then the even numbers from 6 upward. Every
adjacent pair is checked above. $O(n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        if (n < 4) { cout << -1 << '\n'; continue; }
        vector<int> p;
        for (int x = (n % 2 ? n : n - 1); x >= 1; x -= 2) p.push_back(x);
        p.push_back(4); p.push_back(2);
        for (int x = 6; x <= n; x += 2) p.push_back(x);
        for (int i = 0; i < n; i++) cout << p[i] << " \n"[i == n - 1];
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt();
            if (n < 4) { out.println(-1); continue; }
            StringBuilder sb = new StringBuilder();
            for (int x = (n % 2 == 1 ? n : n - 1); x >= 1; x -= 2) sb.append(x).append(' ');
            sb.append("4 2");
            for (int x = 6; x <= n; x += 2) sb.append(' ').append(x);
            out.println(sb);
        }
        out.flush();
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
3
2
4
7
out:
-1
3 1 4 2
7 5 3 1 4 2 6
-->
<!-- test
in:
2
3
6
out:
-1
5 3 1 4 2 6
-->

</details>

Any valid permutation is accepted by the real checker; the tests above show this construction's output, and the
construction was checked with `checkPerm` for every $n \le 1000$.

### Example 3 — Ehab the Xorcist  ·  ★ 1700

- **Source:** [CF 1325D · Ehab the Xorcist](https://codeforces.com/problemset/problem/1325/D) — 1700
- **Difficulty:** 1700
- **Problem:** given $0 \le u, v \le 10^{18}$, print the shortest array of non-negative integers whose XOR is $u$ and whose sum is
  $v$ (length, then the elements), or −1.
- **Thinking from first principles:** brute force the minimal length for small $u, v$ (search all arrays of length
  $\le 4$):

  | $v \backslash u$ | 0 | 1 | 2 | 3 | 4 | 5 |
  |---|---|---|---|---|---|---|
  | 0 | 0 | −1 | −1 | −1 | −1 | −1 |
  | 1 | −1 | 1 | −1 | −1 | −1 | −1 |
  | 2 | 2 | −1 | 1 | −1 | −1 | −1 |
  | 3 | −1 | 3 | −1 | 1 | −1 | −1 |
  | 4 | 2 | −1 | 2 | −1 | 1 | −1 |
  | 5 | −1 | 2 | −1 | 3 | −1 | 1 |
  | 6 | 2 | −1 | 3 | −1 | 2 | −1 |

  Observations: never more than 3; −1 exactly when $u > v$ or $u, v$ have different parity; length 1 iff $u = v \ne 0$.
  Explain them: $\text{XOR} \le \text{sum}$ and both have the same parity (bit 0 of the sum and of the XOR are both
  the parity of the number of odd elements) — necessity. With $c = (v-u)/2$, the array $[u, c, c]$ has XOR $u$ and sum
  $v$ — so 3 always suffices. Length 2: $a + b = (a\oplus b) + 2(a\,\&\,b)$ forces $a \,\&\, b = c$ and $a \oplus b = u$, which is
  possible iff $u \,\&\, c = 0$ (a bit cannot be both "in both" and "in exactly one"); then $[u + c, c]$ works.

<details><summary>Solution</summary>

Cases in order: $u > v$ or $(v - u)$ odd → −1; $u = v = 0$ → length 0; $u = v$ → $[u]$; $u \,\&\, c = 0$ → $[u + c, c]$; else
$[u, c, c]$. Values up to $10^{18}$ fit in signed 64-bit, and $u + c \le v$. $O(1)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    unsigned long long u, v; cin >> u >> v;
    if (u > v || (v - u) % 2) { cout << -1 << '\n'; return 0; }
    if (v == 0) { cout << 0 << '\n'; return 0; }
    if (u == v) { cout << 1 << '\n' << u << '\n'; return 0; }
    unsigned long long c = (v - u) / 2;
    if ((u & c) == 0) cout << 2 << '\n' << (u + c) << ' ' << c << '\n';
    else cout << 3 << '\n' << u << ' ' << c << ' ' << c << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long u = Long.parseLong(st.nextToken()), v = Long.parseLong(st.nextToken());
        PrintWriter out = new PrintWriter(System.out);
        if (u > v || (v - u) % 2 != 0) out.println(-1);
        else if (v == 0) out.println(0);
        else if (u == v) { out.println(1); out.println(u); }
        else {
            long c = (v - u) / 2;
            if ((u & c) == 0) { out.println(2); out.println((u + c) + " " + c); }
            else { out.println(3); out.println(u + " " + c + " " + c); }
        }
        out.flush();
    }
}
```

<!-- test
in:
2 4
out:
2
3 1
-->
<!-- test
in:
1 3
out:
3
1 1 1
-->
<!-- test
in:
8 5
out:
-1
-->
<!-- test
in:
0 0
out:
0
-->
<!-- test
in:
1 2
out:
-1
-->
<!-- test
in:
1000000000000000000 1000000000000000000
out:
1
1000000000000000000
-->

</details>

### Example 4 — Engineer Artem  ·  ★ 2000

- **Source:** [CF 1438C · Engineer Artem](https://codeforces.com/problemset/problem/1438/C) — 2000
- **Difficulty:** 2000
- **Problem:** $t$ test cases; an $n \times m$ grid ($n, m \le 100$) of integers $1 \le a_{ij} \le 10^9$. Increase each cell by 0
  or 1 so that no two side-adjacent cells are equal. Print the resulting grid (an answer always exists).
- **Thinking from first principles:** local repair (scan and fix conflicts) gets tangled: fixing one cell can break a
  neighbour already fixed. "An answer always exists" suggests a global rule. Each cell has a free bit — spend it on
  *parity*: the $+0/+1$ choice can make $a_{ij}$ have any parity we like. If every cell's parity equals $(i + j) \bmod 2$
  (chessboard colouring), adjacent cells have different parities, hence are different. No case analysis left.

<details><summary>Solution</summary>

Add 1 to $a_{ij}$ exactly when $a_{ij} \bmod 2 \ne (i+j) \bmod 2$. $O(nm)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n, m; cin >> n >> m;
        for (int i = 0; i < n; i++)
            for (int j = 0; j < m; j++) {
                long long a; cin >> a;
                if (a % 2 != (i + j) % 2) a++;
                cout << a << " \n"[j == m - 1];
            }
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt(), m = in.nextInt();
            for (int i = 0; i < n; i++) {
                StringBuilder sb = new StringBuilder();
                for (int j = 0; j < m; j++) {
                    long a = in.nextLong();
                    if (a % 2 != (i + j) % 2) a++;
                    sb.append(a).append(j == m - 1 ? "" : " ");
                }
                out.println(sb);
            }
        }
        out.flush();
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
1
2 2
1 2
3 4
out:
2 3
3 4
-->
<!-- test
in:
2
1 1
5
1 3
7 7 7
out:
6
8 7 8
-->

</details>

### Example 5 — Directing Edges  ·  ★ 2000

- **Source:** [CF 1385E · Directing Edges](https://codeforces.com/problemset/problem/1385/E) — 2000
- **Difficulty:** 2000
- **Problem:** $t$ test cases ($\sum n, \sum m \le 2 \cdot 10^5$). A graph has $m$ edges, some already directed, some undirected
  (no self-loops or multi-edges). Direct every undirected edge so that the whole graph is acyclic: print `NO`, or `YES` and
  all $m$ edges with their final directions.
- **Thinking from first principles:** necessity: if the directed edges alone contain a cycle, no orientation helps → `NO`.
  Sufficiency: otherwise the directed part has a topological order $\pi$. Orient every undirected edge from smaller $\pi$
  to larger $\pi$ — now *every* edge increases $\pi$, so no cycle exists (§2, DAG orientation). The undirected edges never
  influence the order, which is why we compute $\pi$ from the directed edges only.

<details><summary>Solution</summary>

Kahn's algorithm on the directed edges gives $\pi$ (if it does not reach all vertices, there is a cycle). Then print the
directed edges unchanged and each undirected edge $\{x, y\}$ as `x y` if $\pi(x) < \pi(y)$, else `y x`. $O(n + m)$ per test;
all arrays are rebuilt per test case.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n, m; cin >> n >> m;
        vector<array<int, 3>> e(m);
        vector<vector<int>> adj(n + 1);
        vector<int> indeg(n + 1, 0);
        for (auto& [tp, x, y] : e) {
            cin >> tp >> x >> y;
            if (tp == 1) { adj[x].push_back(y); indeg[y]++; }
        }
        vector<int> pos(n + 1), q;
        for (int v = 1; v <= n; v++) if (indeg[v] == 0) q.push_back(v);
        for (size_t h = 0; h < q.size(); h++) {
            int v = q[h]; pos[v] = h;
            for (int w : adj[v]) if (--indeg[w] == 0) q.push_back(w);
        }
        if ((int)q.size() < n) { cout << "NO\n"; continue; }   // directed part has a cycle
        cout << "YES\n";
        for (auto& [tp, x, y] : e) {
            if (tp == 0 && pos[x] > pos[y]) swap(x, y);
            cout << x << ' ' << y << '\n';
        }
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt(), m = in.nextInt();
            int[] tp = new int[m], ex = new int[m], ey = new int[m];
            int[] head = new int[n + 1], nxt = new int[m], to = new int[m], indeg = new int[n + 1];
            Arrays.fill(head, -1);
            for (int i = 0; i < m; i++) {
                tp[i] = in.nextInt(); ex[i] = in.nextInt(); ey[i] = in.nextInt();
                if (tp[i] == 1) { to[i] = ey[i]; nxt[i] = head[ex[i]]; head[ex[i]] = i; indeg[ey[i]]++; }
            }
            int[] q = new int[n], pos = new int[n + 1];
            int qt = 0;
            for (int v = 1; v <= n; v++) if (indeg[v] == 0) q[qt++] = v;
            for (int h = 0; h < qt; h++) {
                int v = q[h]; pos[v] = h;
                for (int i = head[v]; i != -1; i = nxt[i]) if (--indeg[to[i]] == 0) q[qt++] = to[i];
            }
            if (qt < n) { out.println("NO"); continue; }
            out.println("YES");
            for (int i = 0; i < m; i++) {
                int x = ex[i], y = ey[i];
                if (tp[i] == 0 && pos[x] > pos[y]) { int s = x; x = y; y = s; }
                out.println(x + " " + y);
            }
        }
        out.flush();
    }
    static class FastReader {
        private final DataInputStream in; private final byte[] buf = new byte[1 << 16]; private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read(); while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-'; if (neg) c = read();
            long r = 0; while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
1
3 3
1 1 2
0 2 3
0 1 3
out:
YES
1 2
3 2
1 3
-->
<!-- test
in:
1
2 2
1 1 2
1 2 1
out:
NO
-->
<!-- test
in:
2
2 1
0 2 1
3 3
1 1 2
1 2 3
1 3 1
out:
YES
1 2
NO
-->

</details>

Examples 1, 2, 4 and 5 were verified with checkers on all small inputs (Example 5 also against a brute force over all
orientations, to confirm `NO` exactly when no acyclic orientation exists); Example 3 was compared with the exhaustive
minimal-length search for all $u, v \le 40$.

## 6. Tricks, pitfalls and things to remember

1. **Run the explorer before thinking hard.** Counting valid objects for $n \le 8$ tells you the −1 set and often the
   construction; it is the cheapest observation you can buy.
2. **Prove necessity, then build.** If your construction covers fewer cases than your impossibility proof excludes,
   one of the two is wrong — the brute force tells you which.
3. **Check impossibility in both directions** with the brute force: printing −1 for a solvable case is the most common
   WA in constructives.
4. **Spend the problem's freedom on structure.** A free $\pm1$, a free order, a free colour: use it to impose parity,
   a topological order, or a colouring that makes the property automatic.
5. **Extremes are the most constrained.** Place the largest/smallest/highest-degree element first, or last if it is the
   most flexible.
6. **Small $n$ special cases** ($n = 1, 2, 3$) are where patterns break; handle them by table if needed.
7. **Multiple test cases:** clear adjacency lists and counters per test; size arrays by the current $n$, not the max, when
   $t$ is large.
8. **Output volume:** $10^6$ numbers need buffered output; in Java build a `StringBuilder` or use `PrintWriter`.
9. **Big values:** constructions often produce sums like $u + c$ or $2^{60}$ — check the type (`long long`, `unsigned`).
10. **Deterministic output** matters when you compare against your own reference in stress tests; use a checker instead
    of `diff` for constructive problems.
11. **Read "any" carefully:** sometimes the statement demands the lexicographically smallest or the minimum length —
    then it is an optimisation problem with a constructive flavour (Example 3 asks for the minimum length).

## 7. Going further (toward 2400–2600+)

- **DFS tree dichotomies:** "find a path of length $\ge n/k$ or $k$ disjoint pairs / an independent set" — the DFS tree
  either has a deep path or many vertices at the same depth with no edges between same-level non-ancestors
  (CF 1391E "Pairs of Pairs").
- **Pigeonhole as an algorithm:** CF 1270G "Subset with Zero Sum" turns $i - n \le a_i \le i - 1$ into a functional graph
  $i \to i - a_i$ whose cycle is the answer ([functional graphs](../09-Graphs/10-functional-graphs-and-special-graphs.md)).
- **Operation-budget constructions:** "sort with at most $n$ prefix reversals" (CF 1381A2), "make all equal with $3n$
  operations" (CF 1416B) — design one operation family that fixes one element while keeping the others under control.
- **Tree constructions with degree and diameter constraints:** build the diameter path first, then hang subtrees
  greedily while respecting depth limits (CF 1003E, CF 1311E).
- **Randomised constructions** where a random object works with high probability ([randomized algorithms](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md)).
- **Gadgets for impossibility at IGM level:** invariants of permutation parity, of the multiset of differences, and of
  linear algebra over GF(2) ([XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)).

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 1343B · Balanced Array](https://codeforces.com/problemset/problem/1343/B) — 800
- [ ] [CF 1454A · Special Permutation](https://codeforces.com/problemset/problem/1454/A) — 800
- [ ] [CF 1352B · Same Parity Summands](https://codeforces.com/problemset/problem/1352/B) — 1200
- [ ] [CF 1335D · Anti-Sudoku](https://codeforces.com/problemset/problem/1335/D) — 1300
- [ ] [CF 1521B · Nastia and a Good Array](https://codeforces.com/problemset/problem/1521/B) — 1300
- [ ] [CF 1381A1 · Prefix Flip (Easy Version)](https://codeforces.com/problemset/problem/1381/A1) — 1300
- [ ] [CF 1988C · Increasing Sequence with Fixed OR](https://codeforces.com/problemset/problem/1988/C) — 1300
- [ ] [CF 1463B · Find The Array](https://codeforces.com/problemset/problem/1463/B) — 1400
- [ ] [CSES 1070 · Permutations](https://cses.fi/problemset/task/1070)
- [ ] [CSES 1092 · Two Sets](https://cses.fi/problemset/task/1092)
- [ ] [CSES 2205 · Gray Code](https://cses.fi/problemset/task/2205)

**1400–1900**
- [ ] [CF 1352G · Special Permutation](https://codeforces.com/problemset/problem/1352/G) — 1600
- [ ] [CF 1364C · Ehab and Prefix MEXs](https://codeforces.com/problemset/problem/1364/C) — 1600
- [ ] [CF 1503A · Balance the Bits](https://codeforces.com/problemset/problem/1503/A) — 1600
- [ ] [CF 1396A · Multiples of Length](https://codeforces.com/problemset/problem/1396/A) — 1600
- [ ] [CF 1371D · Grid-00100](https://codeforces.com/problemset/problem/1371/D) — 1600
- [ ] [CF 1325D · Ehab the Xorcist](https://codeforces.com/problemset/problem/1325/D) — 1700
- [ ] [CF 1381A2 · Prefix Flip (Hard Version)](https://codeforces.com/problemset/problem/1381/A2) — 1700
- [ ] [CF 1144F · Graph Without Long Directed Paths](https://codeforces.com/problemset/problem/1144/F) — 1700
- [ ] [CSES 2214 · Inverse Inversions](https://cses.fi/problemset/task/2214)
- [ ] [CSES 2215 · Monotone Subsequences](https://cses.fi/problemset/task/2215)
- [ ] [CSES 2423 · Filling Trominos](https://cses.fi/problemset/task/2423)

**1900–2400**
- [ ] [CF 1375D · Replace by MEX](https://codeforces.com/problemset/problem/1375/D) — 1900
- [ ] [CF 1385E · Directing Edges](https://codeforces.com/problemset/problem/1385/E) — 2000
- [ ] [CF 1438C · Engineer Artem](https://codeforces.com/problemset/problem/1438/C) — 2000
- [ ] [CF 1416B · Make Them Equal](https://codeforces.com/problemset/problem/1416/B) — 2000
- [ ] [CF 1003E · Tree Constructing](https://codeforces.com/problemset/problem/1003/E) — 2100
- [ ] [CF 1311E · Construct the Binary Tree](https://codeforces.com/problemset/problem/1311/E) — 2200
- [ ] [CF 1305E · Kuroni and the Score Distribution](https://codeforces.com/problemset/problem/1305/E) — 2200

**2400+**
- [ ] [CF 1375E · Inversion SwapSort](https://codeforces.com/problemset/problem/1375/E) — 2500
- [ ] [CF 1391E · Pairs of Pairs](https://codeforces.com/problemset/problem/1391/E) — 2600
- [ ] [CF 1270G · Subset with Zero Sum](https://codeforces.com/problemset/problem/1270/G) — 2700

## 9. LeetCode / FAANG cross-reference

- [LC 942 · DI String Match](https://leetcode.com/problems/di-string-match/) — Easy — extremes: take the smallest remaining on `I`, the largest on `D`.
- [LC 2375 · Construct Smallest Number From DI String](https://leetcode.com/problems/construct-smallest-number-from-di-string/) — Medium — ascending base, reverse each `D` block.
- [LC 667 · Beautiful Arrangement II](https://leetcode.com/problems/beautiful-arrangement-ii/) — Medium — exactly $k$ distinct differences: zig-zag $1, k+1, 2, k, \dots$ then ascending.
- [LC 932 · Beautiful Array](https://leetcode.com/problems/beautiful-array/) — Medium — induction: odds from a smaller beautiful array, then evens.
- [LC 89 · Gray Code](https://leetcode.com/problems/gray-code/) — Medium — $i \oplus (i \gg 1)$ or reflection.
- [LC 1238 · Circular Permutation in Binary Representation](https://leetcode.com/problems/circular-permutation-in-binary-representation/) — Medium — Gray code XOR the start value.
- [LC 31 · Next Permutation](https://leetcode.com/problems/next-permutation/) — Medium — the explorer's engine; constructive reasoning about the suffix.

Pure constructive problems are uncommon in interviews (they reward contest-specific pattern hunting); the ones that
appear are the extremes/induction kind above, and interviewers expect a short correctness argument for the pattern.

## 10. Self-check

1. What are the two halves of a constructive solution, and in which order should you attack them?
2. How do you produce a permutation of $1..n$ with exactly $k$ inversions in $O(n)$?
3. When does an array with XOR $u$ and sum $v$ exist, and why is length 3 always enough?
4. Why does making each cell's parity equal $(i+j) \bmod 2$ solve Engineer Artem?
5. Why does orienting undirected edges along a topological order of the directed part never create a cycle?
6. Give three output-format mistakes that turn a correct construction into WA or TLE.
7. Why should a constructive solution be stress-tested with a checker rather than `diff`?

<details><summary>Answers</summary>

1. Necessity (what every answer must satisfy, which gives the impossible cases) first, then a construction covering
   every remaining case; then verify with a checker.
2. With $m$ values remaining: while $k \ge m-1$ emit the largest ($m-1$ inversions); then emit the $(k+1)$-th smallest
   and the rest ascending.
3. Iff $u \le v$ and $v - u$ is even. With $c = (v-u)/2$, $[u, c, c]$ has XOR $u$ and sum $u + 2c = v$.
4. Adjacent cells have different $(i+j)$ parity, so their values have different parity and cannot be equal; the $+0/+1$
   freedom lets every cell reach the required parity.
5. Every directed edge already goes forward in the order, and every oriented undirected edge goes forward by
   construction; a cycle would need an edge going backward.
6. Not resetting per-test arrays; missing `YES`/length line or wrong `-1` format; unbuffered output of $10^6$ numbers
   (`endl`, `System.out.println` per number); 0- vs 1-indexing.
7. Many answers are valid, so your output can legitimately differ from a reference; a checker verifies the property.

</details>
