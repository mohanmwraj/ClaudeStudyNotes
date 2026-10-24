# First-principles problem solving

> **Band:** all (the skill that separates 1900 from 2400 is mostly this) · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [environment & templates](06-environment-templates-cpp-java.md), [complexity](../01-Foundations/01-complexity-and-constraint-reading.md)
> **You can say you know this when:** facing a problem you have never seen, you can *generate* progress on demand — formal restatement, small cases, a brute force, a conjecture, a proof — instead of waiting for recognition; and you can explain afterwards which step produced the key idea.

## 1. Why a framework at all

Recognition ("this is a segment tree problem") solves problems you have effectively seen before. At 1900+ most problems are designed so that
recognition alone fails: the known structure is hidden behind a transformation, and the transformation is the problem. The cf-stats table in
[rating tiers](01-rating-tiers-and-what-each-level-solves.md) shows the other half of the story: `greedy`, `math` and `constructive algorithms`
together tag a large share of problems in *every* rating band (constructive stays at 16–22% from 800 to 3500), i.e. ad-hoc reasoning never stops
being tested.

What follows is a **repeatable procedure for generating ideas**. It is a synthesis of standard problem-solving practice (Pólya-style heuristics
adapted to competitive programming) and of how strong competitors describe their process in editorials and blogs — an opinionated method, not
a verified recipe. Its value is that when you are stuck, there is always a next concrete action.

## 2. The framework

```text
 1. Restate formally         -> what exactly is the input, the output, the objective? strip the story.
 2. Read the constraints     -> which complexities are allowed? which parameter is small? (complexity file)
 3. Small cases by hand      -> n = 1, 2, 3; draw them; what is the answer and WHY?
 4. Brute force              -> write the obviously-correct slow solution; print answers for many small inputs
 5. Look for structure       -> patterns in the brute-force table; invariants; monotonicity; what never changes?
 6. Simplify                 -> fix a variable, drop a constraint, reverse time, take the complement,
                                change variables, count contributions, go to the extreme case
 7. Reduce to known          -> sorting, prefix sums, two pointers, BFS, DSU, DP over ..., binary search on ...
 8. Prove                    -> exchange argument / invariant / induction / counting; or find the counterexample
 9. Implement                -> from the proof, not from the intuition; bound every value (overflow)
10. Stress test             -> brute force from step 4 vs. solution on random small inputs
```

The steps are not strictly sequential — you loop between 3–6 many times — but **every loop must produce an artefact**: a written restatement,
a table of small answers, a conjecture, a counterexample. If ten minutes pass without a new artefact, move to the next step.

### Step 1 — Restate formally

Write the problem in one or two lines of mathematics. "Valera reads books until his free time runs out" becomes "maximise $r-l+1$ subject to
$\sum_{i=l}^r a_i \le t$". The restatement removes irrelevant story, exposes the objective (count? maximise? decide?) and often already suggests
the structure (a sum over a contiguous range → prefix sums / two pointers). Check the restatement against the samples.

### Step 2 — Read the constraints

They tell you the target complexity and, often, the trick. Use the table in [complexity](../01-Foundations/01-complexity-and-constraint-reading.md):
$n\le 20$ → subsets; $n\le 5000$ → $O(n^2)$; $n\le 2\cdot10^5$ → $O(n\log n)$; $n\le10^{18}$ → math/bits/binary search. A suspiciously small parameter
(values $\le 100$, $k \le 20$, $m\le 1000$ next to $n\le 2\cdot10^5$) is where the solution lives.

### Step 3 — Small cases by hand

Solve $n = 1, 2, 3$ (and a slightly larger case) **on paper, with reasons**. The reasons are the point: "for $[1,2,-1,-2]$ I can take only one
positive because two positives would be adjacent in the subsequence" is already the key lemma of Example 1. Draw pictures: number lines,
grids, graphs, binary representations.

### Step 4 — Brute force

Write the simplest correct program (all subsets, all permutations, simulate literally). It has three uses: it **generates data** for step 5
(print the answer for $n = 1..20$ and stare at the table), it **checks conjectures** instantly, and it is the **oracle for stress testing** in step 10.
Writing it takes five minutes and saves hours; strong competitors do this whenever the fast solution is not obviously right.

### Step 5 — Look for structure

Questions that find structure:

- **Pattern in the table?** Differences, ratios, OEIS-like sequences, dependence on parity or on the binary representation (Example 2).
- **Invariant**: a quantity no operation changes (parity of positions, sum modulo $k$, the multiset of something). It gives impossibility proofs and
  characterisations ([invariants & parity](../03-Greedy-Constructive-Interactive/04-invariants-parity-and-ad-hoc-observations.md)).
- **Monovariant / monotonicity**: something that only increases (enables two pointers, binary search on the answer, greedy).
- **Extremal element**: what happens to the largest/smallest element, the first/last position, the deepest leaf? It is often forced.
- **Independence**: do bits, coordinates, or residues behave independently? Then solve each separately (bits: [bit manipulation](../01-Foundations/03-bit-manipulation.md)).

### Step 6 — Simplify (the toolbox)

| Move | What you do | Typical payoff |
|---|---|---|
| **Fix a variable** | iterate over one quantity (the right end, the maximum, the value of the answer, the first element) and solve the rest | turns 2D/3D searches into 1D; "for each $r$, the best $l$" |
| **Drop a constraint** | solve without the hardest condition, then ask how the condition changes the answer | reveals the core structure; sometimes the condition is automatically satisfied |
| **Reverse time** | process operations backwards: deletions become insertions, splits become merges | DSU handles merges but not splits (Example 4) |
| **Complement** | count the bad objects, or consider the elements *not* chosen | "at least one" → total minus "none"; the removed set is small (Example 6) |
| **Change variables** | $b_i = a_i - 1$, $c_i = a_i - b_i$, $x\pm y$ rotation, prefix sums, differences | a condition on a range becomes equality of two prefix values (Example 3) |
| **Count contributions** | instead of summing over objects, sum over elements/bits/edges how many objects they belong to | $\sum_{\text{pairs}}$ → per-bit counts; Example 2 ([contribution technique](../05-Combinatorics-and-Probability/07-contribution-technique.md)) |
| **Go to the extreme** | consider the largest element, the case where all values are equal, $k = 1$ or $k = n$ | forced moves, the base of an induction, counterexamples |
| **Binary search the answer** | ask "can the answer be $\ge x$?" when feasibility is monotone in $x$ | decision problems are often greedy ([binary search on answer](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md)) |
| **Think about primes / factorisation** | split a number-theory condition prime by prime | gcd/lcm/coprimality conditions decouple (Example 5) |
| **Pigeonhole** | more objects than boxes | "if $n > m$ the answer is trivial" ([complexity Example 5](../01-Foundations/01-complexity-and-constraint-reading.md)) |

### Step 7 — Reduce to something known

After simplification, name the known structure: sort + scan, prefix sums + hashing, two pointers, monotonic stack, BFS on states, DSU, shortest
path on a modelled graph, DP with state "(position, last choice)", binary search over a monotone predicate. The kit's folders are organised so
that this step is a lookup; the cheat sheets ([99-Cheat-Sheets](../99-Cheat-Sheets/01-foundations-cheatsheet.md) and the others) have
"signal → technique" tables.

### Step 8 — Prove (or break) it

A conjecture is not a solution. Standard proof shapes:

- **Exchange argument** — take an optimal solution that differs from yours; swap one decision to agree with yours without making it worse.
- **Invariant + construction** — the invariant shows necessity; an explicit procedure shows sufficiency.
- **Induction** on $n$ or on the bit position (decide the top bit, recurse).
- **Double counting** — count the same set two ways (contribution sums).
- **Monotonicity** — the predicate for binary search really is monotone.

If the proof keeps failing at the same spot, try to build a counterexample there — with the brute force. Finding out in minute 15 that a greedy is
wrong is cheap; finding out at system testing is not.

### Step 9 — Implement from the proof

Translate the proved statement, not the intuition. Before typing, bound every intermediate value (overflow), decide the data structure for each
operation in the proof, and list the edge cases the proof mentions ($n = 1$, empty sets, equal values).

### Step 10 — Stress test

Run the step-4 brute force against the solution on thousands of random small inputs ([stress scripts](06-environment-templates-cpp-java.md)). In
upsolving, do it every time; in contests, do it whenever the solution has a subtle case analysis or the problem is worth the time.

## 3. Worked examples (graded)

Each example follows the framework explicitly. The Java `FastReader` is the one from the [Java template](06-environment-templates-cpp-java.md).

### Example 1 — Alternating Subsequence  ·  ★ 1200

- **Source:** [CF 1343C · Alternating Subsequence](https://codeforces.com/problemset/problem/1343/C) — 1200
- **Difficulty:** 1200
- **Problem:** A sequence of non-zero integers ($|a_i|\le10^9$, $\sum n\le2\cdot10^5$). Among the longest subsequences whose signs alternate, find the
  maximum possible sum.
- **Thinking from first principles:**
  1. *Restate:* maximise (length, then sum) lexicographically over alternating-sign subsequences.
  2. *Constraints:* $O(n)$ or $O(n\log n)$.
  3. *Small cases:* $[1,2,-1,-2]$: any alternating subsequence uses at most one of $\{1,2\}$ (two positives taken from that run would be adjacent in the
     subsequence, with nothing negative between them) and at most one of $\{-1,-2\}$. So length $\le 2$, and the best is $2 + (-1) = 1$.
  4. *Structure:* split the array into **maximal runs of equal sign**. The lemma from the small case generalises: at most one element per run, and one
     per run is achievable (consecutive runs have opposite signs). So the maximum length = number of runs.
  5. *Simplify:* with the length fixed, the runs are independent — choose the maximum of each run.
  6. *Prove:* any optimal subsequence takes exactly one element per run; replacing it by the run maximum keeps it alternating and does not decrease the sum.

<details><summary>Solution</summary>

Scan runs; add each run's maximum. $O(n)$. Sums need 64 bits.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        int n;
        cin >> n;
        vector<long long> a(n);
        for (auto& x : a) cin >> x;
        long long total = 0;
        for (int i = 0; i < n;) {
            int j = i;
            long long best = a[i];
            while (j < n && (a[j] > 0) == (a[i] > 0)) best = max(best, a[j++]);   // one maximal run
            total += best;
            i = j;
        }
        cout << total << '\n';
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
            long[] a = new long[n];
            for (int i = 0; i < n; i++) a[i] = in.nextLong();
            long total = 0;
            for (int i = 0; i < n; ) {
                int j = i;
                long best = a[i];
                while (j < n && (a[j] > 0) == (a[i] > 0)) best = Math.max(best, a[j++]);
                total += best;
                i = j;
            }
            out.println(total);
        }
        out.flush();
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
4
4
1 2 -1 -2
1
-5
6
5 -3 4 -2 -7 1
5
-1 -2 -3 7 8
out:
1
-5
5
7
-->
<!-- test
in:
1
3
1000000000 -1000000000 1000000000
out:
1000000000
-->

### Example 2 — Johnny and Another Rating Drop  ·  ★ 1400

- **Source:** [CF 1362C · Johnny and Another Rating Drop](https://codeforces.com/problemset/problem/1362/C) — 1400
- **Difficulty:** 1400
- **Problem:** For the sequence $0, 1, \dots, n$ ($n\le10^{18}$, up to $10^4$ tests), sum the Hamming distances (number of differing bits) between
  consecutive numbers.
- **Thinking from first principles:**
  1. *Restate:* $S(n) = \sum_{i=1}^{n} \operatorname{popcount}((i-1)\oplus i)$.
  2. *Constraints:* $n\le10^{18}$ → $O(\log n)$ per test; no loop over $i$.
  3. *Brute force table:* $S(1..8) = 1, 3, 4, 7, 8, 10, 11, 15$ (computed by brute force for this file).
  4. *Structure:* increments $S(i) - S(i-1)$: $1, 2, 1, 3, 1, 2, 1, 4$ — the "ruler sequence": $1 + (\text{number of trailing zeros of } i)$. Why: adding
     1 to $i-1$ turns its trailing ones into zeros and the next zero into a one, so $(i-1)\oplus i$ is a block of $\operatorname{ctz}(i)+1$ ones.
  5. *Count contributions (swap the order of summation):* $\operatorname{ctz}(i)+1 = \#\{k\ge0 : 2^k \mid i\}$, so
     $$S(n) = \sum_{i=1}^n \sum_{k\ge0}[2^k\mid i] = \sum_{k\ge0}\left\lfloor \frac{n}{2^k}\right\rfloor .$$
     Check: $S(5) = 5 + 2 + 1 = 8$. ✓

<details><summary>Solution</summary>

Sum $\lfloor n/2^k\rfloor$ while positive: about 60 terms, the total stays below $2n \le 2\cdot10^{18}$ (fits in signed 64 bits). $O(\log n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        long long n;
        cin >> n;
        long long s = 0;
        for (; n > 0; n >>= 1) s += n;     // n + n/2 + n/4 + ...
        cout << s << '\n';
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
            long n = in.nextLong(), s = 0;
            for (; n > 0; n >>= 1) s += n;
            out.println(s);
        }
        out.flush();
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
5
5
7
1
2000000000000
1000000000000000000
out:
8
11
1
3999999999987
1999999999999999976
-->
<!-- test
in:
3
2
3
4
out:
3
4
7
-->

### Example 3 — Good Subarrays  ·  ★ 1600

- **Source:** [CF 1398C · Good Subarrays](https://codeforces.com/problemset/problem/1398/C) — 1600
- **Difficulty:** 1600
- **Problem:** A digit string $a$ ($\sum n\le10^5$). Count subarrays whose digit sum equals their length.
- **Thinking from first principles:**
  1. *Restate:* count $(l, r)$ with $\sum_{i=l}^{r} a_i = r - l + 1$.
  2. *Constraints:* $O(n\log n)$; there are $\sim5\cdot10^9$ subarrays, so we must count without enumerating.
  3. *Small cases:* `111` — every subarray is good (6). `0` — none. A digit 1 contributes "+1 to sum, +1 to length": neutral. A digit $d$ contributes
     $d-1$ to "sum minus length". That suggests a change of variables.
  4. *Change variables:* $b_i = a_i - 1$. The condition becomes $\sum_{i=l}^r b_i = 0$, i.e. **$P_r = P_{l-1}$** for prefix sums $P$ of $b$.
  5. *Reduce:* count pairs of equal values among $P_0, P_1, \dots, P_n$ — a counting problem solved by one pass with a frequency map: when reaching $P_r$,
     add the number of earlier occurrences of the same value.
  6. *Prove:* the transformation is an equivalence, and each pair $(l-1, r)$ with $l-1<r$ is counted once.

<details><summary>Solution</summary>

$P$ ranges over $[-n, 8n]$, so an offset array replaces the hash map. $O(n)$ per test; the answer can reach $\binom{n+1}{2}$ — 64 bits.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        int n;
        string s;
        cin >> n >> s;
        vector<int> freq(9 * n + 1, 0);           // prefix values in [-n, 8n], shifted by n
        long long good = 0;
        int p = 0;
        freq[p + n]++;                            // P_0 = 0
        for (char ch : s) {
            p += (ch - '0') - 1;
            good += freq[p + n];                  // earlier prefixes equal to the current one
            freq[p + n]++;
        }
        cout << good << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = Integer.parseInt(br.readLine().trim());
        while (t-- > 0) {
            int n = Integer.parseInt(br.readLine().trim());
            String s = br.readLine().trim();
            int[] freq = new int[9 * n + 1];
            long good = 0;
            int p = 0;
            freq[p + n]++;
            for (int i = 0; i < n; i++) {
                p += (s.charAt(i) - '0') - 1;
                good += freq[p + n];
                freq[p + n]++;
            }
            out.println(good);
        }
        out.flush();
    }
}
```

</details>

<!-- test
in:
5
3
111
1
0
1
1
4
2002
7
1201000
out:
6
0
1
3
6
-->

### Example 4 — Destroying Array  ·  ★ 1600

- **Source:** [CF 722C · Destroying Array](https://codeforces.com/problemset/problem/722/C) — 1600
- **Difficulty:** 1600
- **Problem:** Array of $n\le10^5$ non-negative values ($\le10^9$). Elements are destroyed one by one in a given order (a permutation). After each
  destruction print the maximum sum of a contiguous block of non-destroyed elements (0 if none).
- **Thinking from first principles:**
  1. *Restate:* maintain the maximum segment sum while segments **split**.
  2. *Constraints:* $O(n\log n)$ or $O(n\,\alpha(n))$.
  3. *Dead end:* forward simulation needs "split a segment" and "maximum over a changing set" — doable with a `set` of segments plus a `multiset` of
     sums (like [Traffic Lights](../01-Foundations/02-cpp-stl-and-java-collections.md)), but heavy.
  4. *Reverse time:* read the destructions backwards and they become **insertions**: start from an empty array and restore elements in reverse
     order. Segments now only **merge**, which DSU does in near-constant time, and the maximum only **grows** (sums are non-negative and segments
     only get larger), so a single running maximum suffices — no multiset.
  5. *Align the answers:* the answer after the $i$-th destruction equals the state in which elements $p_{i+1},\dots,p_n$ are present; the answer after
     the last destruction is 0.

<details><summary>Solution</summary>

Process $i = n, n-1, \dots, 2$: restore $p_i$, union with restored neighbours, update the running maximum, record it as the answer after the
$(i-1)$-th destruction. DSU with path compression and union by size. $O(n\,\alpha(n))$; sums need 64 bits.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> par, sz_;
vector<long long> segSum;

int findRoot(int x) {
    while (par[x] != x) x = par[x] = par[par[x]];      // path halving
    return x;
}

void unite(int a, int b) {
    a = findRoot(a); b = findRoot(b);
    if (a == b) return;
    if (sz_[a] < sz_[b]) swap(a, b);
    par[b] = a; sz_[a] += sz_[b]; segSum[a] += segSum[b];
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> a(n + 2, 0);
    for (int i = 1; i <= n; i++) cin >> a[i];
    vector<int> p(n + 1);
    for (int i = 1; i <= n; i++) cin >> p[i];
    par.resize(n + 2); sz_.assign(n + 2, 1); segSum.assign(n + 2, 0);
    iota(par.begin(), par.end(), 0);
    vector<char> alive(n + 2, 0);
    vector<long long> ans(n + 1, 0);                  // ans[i] = answer after i destructions; ans[n] = 0
    long long best = 0;
    for (int i = n; i >= 2; i--) {
        int x = p[i];
        alive[x] = 1; segSum[x] = a[x];
        if (alive[x - 1]) unite(x, x - 1);
        if (alive[x + 1]) unite(x, x + 1);
        best = max(best, segSum[findRoot(x)]);
        ans[i - 1] = best;
    }
    string out;
    for (int i = 1; i <= n; i++) out += to_string(ans[i]) + '\n';
    cout << out;
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static int[] par, size;
    static long[] segSum;

    static int findRoot(int x) {
        while (par[x] != x) { par[x] = par[par[x]]; x = par[x]; }
        return x;
    }

    static void unite(int a, int b) {
        a = findRoot(a); b = findRoot(b);
        if (a == b) return;
        if (size[a] < size[b]) { int t = a; a = b; b = t; }
        par[b] = a; size[a] += size[b]; segSum[a] += segSum[b];
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] a = new long[n + 2];
        for (int i = 1; i <= n; i++) a[i] = in.nextLong();
        int[] p = new int[n + 1];
        for (int i = 1; i <= n; i++) p[i] = in.nextInt();
        par = new int[n + 2]; size = new int[n + 2]; segSum = new long[n + 2];
        for (int i = 0; i < n + 2; i++) { par[i] = i; size[i] = 1; }
        boolean[] alive = new boolean[n + 2];
        long[] ans = new long[n + 1];
        long best = 0;
        for (int i = n; i >= 2; i--) {
            int x = p[i];
            alive[x] = true; segSum[x] = a[x];
            if (alive[x - 1]) unite(x, x - 1);
            if (alive[x + 1]) unite(x, x + 1);
            best = Math.max(best, segSum[findRoot(x)]);
            ans[i - 1] = best;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= n; i++) sb.append(ans[i]).append('\n');
        System.out.print(sb);
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
3
1 2 3
2 1 3
out:
3
3
0
-->
<!-- test
in:
4
1 3 2 5
3 4 1 2
out:
5
4
3
0
-->
<!-- test
in:
1
5
1
out:
0
-->
<!-- test
in:
5
1000000000 1000000000 0 1000000000 1000000000
3 1 5 2 4
out:
2000000000
2000000000
1000000000
1000000000
0
-->

### Example 5 — Two Divisors  ·  ★ 2000

- **Source:** [CF 1366D · Two Divisors](https://codeforces.com/problemset/problem/1366/D) — 2000
- **Difficulty:** 2000
- **Problem:** For each of $n\le5\cdot10^5$ numbers $2\le a_i\le10^7$, find divisors $d_1, d_2 > 1$ of $a_i$ with $\gcd(d_1+d_2, a_i) = 1$, or report
  that none exist (print $-1\ -1$). Any valid pair is accepted.
- **Thinking from first principles:**
  1. *Restate:* $\gcd(d_1+d_2, a)=1 \iff$ no prime $q\mid a$ divides $d_1+d_2$.
  2. *Think prime by prime:* for a fixed prime $q \mid a$: if $q$ divides both $d_1$ and $d_2$, it divides the sum — bad. If it divides exactly one of
     them, it cannot divide the sum (sum ≡ the other one ≢ 0 mod $q$) — good. If it divides neither, the sum may or may not be divisible.
  3. *Conjecture from the safe case:* make **every** prime of $a$ divide exactly one of $d_1, d_2$. That is exactly a split $a = d_1 d_2$ with
     $\gcd(d_1, d_2) = 1$ and both $>1$. Such a split exists iff $a$ has at least two distinct primes: take $d_1 = p^k$ (the full power of the smallest
     prime $p$) and $d_2 = a/p^k$.
  4. *Extreme / impossibility case:* if $a = p^k$, every divisor $>1$ is a multiple of $p$, so $p$ divides $d_1+d_2$: impossible. ✓ The two cases cover everything.
  5. *Reduce:* we need the smallest prime factor of numbers up to $10^7$ — a sieve ([sieves](../04-Number-Theory/03-sieves-and-factorization.md)).

<details><summary>Solution</summary>

Smallest-prime-factor sieve up to $\max a_i$; strip the full power of $p$; if nothing remains print $-1\ -1$. The judge accepts any valid pair; the
hidden tests below check this canonical choice (each pair was verified by hand). Sieve $O(A\log\log A)$, then $O(\log a)$ per number.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> a(n);
    for (auto& x : a) cin >> x;
    int A = *max_element(a.begin(), a.end());
    vector<int> spf(A + 1, 0);
    for (int i = 2; i <= A; i++)
        if (spf[i] == 0)
            for (int j = i; j <= A; j += i)
                if (spf[j] == 0) spf[j] = i;
    string l1, l2;
    for (int x : a) {
        int p = spf[x], pk = 1, rest = x;
        while (rest % p == 0) { rest /= p; pk *= p; }
        if (rest == 1) { l1 += "-1 "; l2 += "-1 "; }
        else { l1 += to_string(pk) + ' '; l2 += to_string(rest) + ' '; }
    }
    cout << l1 << '\n' << l2 << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        int A = 2;
        for (int i = 0; i < n; i++) { a[i] = in.nextInt(); A = Math.max(A, a[i]); }
        int[] spf = new int[A + 1];
        for (int i = 2; i <= A; i++)
            if (spf[i] == 0)
                for (int j = i; j <= A; j += i)
                    if (spf[j] == 0) spf[j] = i;
        StringBuilder l1 = new StringBuilder(), l2 = new StringBuilder();
        for (int x : a) {
            int p = spf[x], pk = 1, rest = x;
            while (rest % p == 0) { rest /= p; pk *= p; }
            if (rest == 1) { l1.append("-1 "); l2.append("-1 "); }
            else { l1.append(pk).append(' '); l2.append(rest).append(' '); }
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(l1);
        out.println(l2);
        out.flush();
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
5
2 12 30 8 1000000
out:
-1 4 2 -1 64
-1 3 15 -1 15625
-->
<!-- test
in:
3
10000000 9 77
out:
128 -1 7
78125 -1 11
-->

### Example 6 — Binary Median  ·  ★ 2100

- **Source:** [CF 1360H · Binary Median](https://codeforces.com/problemset/problem/1360/H) — 2100
- **Difficulty:** 2100
- **Problem:** All $2^m$ binary strings of length $m\le60$; $n\le\min(2^m-1, 100)$ distinct ones are removed. Sort the remaining $k = 2^m - n$ strings and
  print the one at index $\lfloor (k-1)/2\rfloor$ (0-based). Up to 1000 tests.
- **Thinking from first principles:**
  1. *Restate:* binary strings of length $m$ are the numbers $0..2^m-1$ in order; we need the $j$-th smallest **non-removed** number, $j = \lfloor(k-1)/2\rfloor$.
  2. *Constraints:* $2^{60}$ numbers — no enumeration; but only $\le 100$ removed: **think about the complement** (the small removed set).
  3. *Small case:* $m = 3$, removed $\{000, 111, 011\}$: remaining $\{1,2,4,5,6\}$, $k=5$, $j=2$, answer $4 = 100$. Without removals the $j$-th number
     would be $j$ itself; each removed number $\le$ the candidate pushes the answer one step right.
  4. *Simplify:* start from $x = j$ and walk through the removed numbers **in increasing order**; whenever a removed value is $\le x$, increment $x$.
     Invariant: after processing the removed values $r_1<\dots<r_i$, $x$ is the $j$-th smallest number not in $\{r_1..r_i\}$. Adding $r_{i+1}$: if
     $r_{i+1} > x$ nothing changes; otherwise every number from $r_{i+1}$ up shifts by one, so $x$ moves to $x+1$ (which is not removed among the processed
     ones, since $r_{i+1}\le x < x+1$ and the earlier ones are smaller still).
  5. *Implement:* parse strings as 64-bit integers, sort, walk, print with leading zeros. $O(n\log n + nm)$.

<details><summary>Solution</summary>

$k = 2^m - n$ fits in 64 bits for $m\le60$. Print the $m$ low bits of $x$, most significant first.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        int n, m;
        cin >> n >> m;
        vector<long long> rem(n);
        for (auto& r : rem) {
            string s;
            cin >> s;
            r = stoll(s, nullptr, 2);
        }
        sort(rem.begin(), rem.end());
        long long k = (1LL << m) - n, x = (k - 1) / 2;
        for (long long r : rem) if (r <= x) x++;
        string out(m, '0');
        for (int b = 0; b < m; b++) if (x >> b & 1) out[m - 1 - b] = '1';
        cout << out << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = Integer.parseInt(br.readLine().trim());
        while (t-- > 0) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            int n = Integer.parseInt(st.nextToken()), m = Integer.parseInt(st.nextToken());
            long[] rem = new long[n];
            for (int i = 0; i < n; i++) rem[i] = Long.parseLong(br.readLine().trim(), 2);
            Arrays.sort(rem);                       // n <= 100: no anti-quicksort concern
            long k = (1L << m) - n, x = (k - 1) / 2;
            for (long r : rem) if (r <= x) x++;
            char[] s = new char[m];
            for (int b = 0; b < m; b++) s[m - 1 - b] = ((x >> b) & 1) == 1 ? '1' : '0';
            out.println(new String(s));
        }
        out.flush();
    }
}
```

</details>

<!-- test
in:
4
1 1
0
1 2
00
3 3
000
111
011
1 60
000000000000000000000000000000000000000000000000000000000000
out:
1
10
100
100000000000000000000000000000000000000000000000000000000000
-->
<!-- test
in:
1
2 2
10
01
out:
00
-->

## 4. Questions to ask a problem (checklist)

Run through these whenever you are stuck; each "yes" points to a move.

**About the statement**
1. Can I restate it in one formula? What exactly is counted/optimised/decided?
2. Does the order of the input matter? If not — sort.
3. Is the answer monotone in some parameter? → binary search on the answer.
4. Is there a hidden graph (states and moves, elements and relations)?

**About the constraints**
5. Which complexity do the limits allow? Which parameter is small enough to iterate over or to use as a bitmask?
6. Do two limits differ wildly ($n$ vs. $m$, $n$ vs. values)? Is the answer trivial in one regime (pigeonhole)?
7. Is there a "sum of $n$" or "sum of $n^2$" bound that invites an otherwise too-slow per-test algorithm?

**About structure**
8. What do small cases look like? What does the brute force print for $n = 1..10$?
9. What is invariant under the allowed operations? What only increases?
10. What happens to the extreme element (largest, smallest, first, last, deepest)?
11. Can I fix one variable (the right end, the maximum, the answer's value, the first move) and solve the rest greedily?
12. Do bits / prime factors / coordinates / residues decouple?
13. Would it be easier backwards in time, or for the complement?
14. Can I count by contribution (each element/bit/edge counted in how many objects)?
15. Is there a substitution ($b_i = a_i - i$, $a_i - 1$, $x+y$ / $x-y$, prefix sums) that makes the condition an equality or a sort order?

**About the solution**
16. Can I prove it? If not, can I find a counterexample with the brute force?
17. What are the edge cases ($n=1$, all equal, maximum values, empty answer)? Do intermediate values overflow?
18. Is this the simplest correct solution I can implement in the time left?

## 5. Failure modes and how to break out of them

| Symptom | Likely cause | Action |
|---|---|---|
| Staring at the statement, no ideas | no artefacts produced | do steps 3–4: small cases + brute force table |
| A greedy that "obviously works" keeps getting WA | unproved conjecture | stress test against brute force; try to prove the exchange step |
| Stuck on one approach for 30+ minutes | anchoring | list three *different* simplification moves from §2 and try each for 5 minutes |
| Solution is right but TLE | missed reduction | re-read constraints; which quantity is small; can the same work be shared (prefix sums, sorting, DP)? |
| Editorial idea "seems obvious" afterwards | recognition gap | write the idea in your journal with the *trigger* that should have led to it ([practice methodology](03-practice-methodology.md)) |
| Many small implementation bugs | coding from intuition | write the proof/algorithm in 5–10 lines of plain text before coding |

## 6. Training the skill

First-principles ability is trained like any other skill — by deliberate practice on problems slightly beyond reach (methodology and the
evidence on time limits in [practice methodology](03-practice-methodology.md)):

1. **Solve without tags.** Tags short-circuit steps 5–7. Hide them (Codeforces has a setting for this) for most practice.
2. **Write the artefacts.** For each practice problem keep the restatement, the small-case table and the key observation in your idea journal.
3. **After every solve, name the step that cracked it** ("reverse time", "change of variables", "pigeonhole"). Over months this builds the
   personal trigger list that later feels like intuition.
4. **Upsolve with the framework.** When reading an editorial, stop after each hint and try to continue on your own (protocol in
   [practice methodology](03-practice-methodology.md)).
5. **Constructive and ad-hoc sets** (Div. 2 B–D, AtCoder ARC A–B) train exactly this skill —
   [constructive algorithms](../03-Greedy-Constructive-Interactive/03-constructive-algorithms.md),
   [invariants & ad-hoc](../03-Greedy-Constructive-Interactive/04-invariants-parity-and-ad-hoc-observations.md),
   [how grandmasters think](../16-IGM-Frontier/07-how-grandmasters-think.md).

## 7. Self-check

1. List the ten steps of the framework from memory.
2. Which simplification move turned Destroying Array into a DSU problem, and why does it also remove the need for a multiset?
3. In Good Subarrays, what substitution converts the condition into equality of prefix sums?
4. Why is the Johnny sum equal to $\sum_k\lfloor n/2^k\rfloor$? Name the technique.
5. For Two Divisors, why is $a = p^k$ impossible, and why does $d_1 = p^k$ (full power) work otherwise?
6. Which move does Binary Median rely on, and what invariant justifies the "increment while walking the sorted removed list" rule?

<details><summary>Answers</summary>

1. Restate; read constraints; small cases; brute force; look for structure; simplify; reduce to known; prove; implement; stress test.
2. Reverse time: deletions become insertions, so segments only merge (DSU) and, with non-negative values, the maximum only grows, so a running maximum suffices.
3. $b_i = a_i - 1$: the condition becomes $\sum b = 0$ over the subarray, i.e. $P_r = P_{l-1}$.
4. $(i-1)\oplus i$ has $\operatorname{ctz}(i)+1$ bits, and $\operatorname{ctz}(i)+1$ counts the $k$ with $2^k\mid i$; swapping the order of summation (contribution counting) gives $\sum_k \lfloor n/2^k\rfloor$.
5. If $a=p^k$ both divisors are multiples of $p$, so $p\mid d_1+d_2$. Otherwise every prime of $a$ divides exactly one of $p^k$ and $a/p^k$, so it cannot divide their sum.
6. The complement (only $\le100$ removed numbers matter). Invariant: after processing the smallest $i$ removed values, $x$ is the $j$-th smallest number avoiding them; a newly processed removed value $\le x$ shifts the answer by exactly one.

</details>
