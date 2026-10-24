# Invariants, parity and ad-hoc observations

> **Band:** 🟢–🟠 800–2400 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [bit manipulation](../01-Foundations/03-bit-manipulation.md), [constructive algorithms](03-constructive-algorithms.md), [first-principles problem solving](../00-Roadmap-and-Strategy/05-first-principles-problem-solving.md)
> **You can say you know this when:** for any "apply this operation any number of times" problem you can list, within a few minutes, what the operation preserves and what it changes monotonically, turn that into an exact description of the reachable states (necessity *and* sufficiency), and you know the standard tools — parity, colouring, pigeonhole, extremal element, reverse thinking, XOR and MEX facts.

## 1. First principles — why this works

"Ad hoc" problems are not unstructured; they are problems whose structure is not a named algorithm. The most common
shape is an **operation problem**: a state, an allowed operation, and a question — *can the target be reached? what is
the minimum number of operations? what is the best final value?* The state space is astronomically large, so search is
out. The way in is to stop looking at states and start looking at **functions of the state**.

- An **invariant** is a quantity the operation never changes (sum, parity, gcd, the multiset of something). If
  start and target have different invariants, the target is unreachable. Invariants give *necessity*.
- A **monovariant** is a quantity that moves in one direction only (strictly decreases, or never increases). It proves
  termination, bounds the number of operations, and constrains the final state ("the first element can only grow").
- **Sufficiency** is the harder half: show that every state with the right invariants *is* reachable. The standard
  method is a **normal form**: show that from any state you can reach a canonical state determined only by the
  invariants. If operations are reversible, start and target then connect through the normal form.

### The "what does the operation preserve?" checklist

Run through this list for every operation you meet; write down each candidate and test it on two or three hand
examples. Most Div2 B–D ad-hoc problems fall to one line of it.

| Quantity | Typical operation that preserves it |
|---|---|
| total sum | moving units between elements, $a_i \mathrel{-}= x, a_j \mathrel{+}= x$ |
| sum mod $k$, parity of the sum | adding $k$ (or an even amount) somewhere |
| XOR of everything | replacing two elements $x, y$ by $x \oplus y$ and $0$; inserting a pair $(x, x)$ |
| $\gcd$ of the array / of differences | $a_i \leftarrow a_i - a_j$ (Euclid), adding the same $b$ to all |
| multiset of values | swaps of any kind (only the order changes) |
| multiset of adjacent differences | $c_i \leftarrow c_{i-1} + c_{i+1} - c_i$ (swaps two neighbouring differences) |
| first / last element, min / max | operations restricted to the interior, or that only remove non-extreme elements |
| relative order of some class | swaps allowed only between different classes |
| parity of the permutation | 3-cycles, reversals of length $\equiv 0, 1 \pmod 4$, pairs of swaps |
| count of black minus white cells | placing dominoes, moving tokens two steps |
| connectivity / bipartiteness | edge flips that keep endpoints in the same component / side |

### Parity and colouring

**Parity** is the invariant "mod 2"; it is common because many operations change a count by exactly 2 (or flip two
things at once). **Colouring** generalises parity to geometry: colour the board so that every allowed piece or move
covers colours in a fixed ratio; then the colour counts are invariant. The classic: a chessboard with two opposite
corners removed has 30 cells of one colour and 32 of the other, while each domino covers one of each, so no tiling
exists. Weighted colourings (colour $(i, j)$ by $(i + j) \bmod 3$, or by $i \bmod 2$ only) handle trominoes and
straight pieces.

### Pigeonhole

$n+1$ objects in $n$ boxes put two in one box. In contests it appears as: prefix sums modulo $n$ (some subarray has
sum divisible by $n$), "if $n > m$ two values are congruent mod $m$, so a product of differences is 0 mod $m$"
(Example 5), and "a walk of more than $|S|$ steps in a finite state space repeats a state" (cycle detection — see
[functional graphs](../09-Graphs/10-functional-graphs-and-special-graphs.md)).

### Extremal principle

Look at the extreme object — the maximum element, the first position where something happens, the longest path, the
vertex of minimum degree. It is constrained in ways a typical object is not. "The first element of the array can only
increase under the operation" (Example 3) and "the largest value must end up at the end, so look at where it is" are
the everyday forms.

### Thinking in reverse

Operations that branch forward are often forced backward. From $n$ you may double or decrement — two choices per step;
from the target $m$ the reverse operations are halve (only if even) or increment, and a short exchange argument shows
which one is right (Example 4). Reverse thinking also turns "delete" into "insert", "merge" into "split" (Huffman), and
"last operation wins" painting problems into "first operation in reverse order wins".

### Order independence ("sorting changes nothing")

If the answer depends only on the multiset of inputs (sums, counts, which values occur), sort the input first — it
cannot change the answer and it exposes structure. Likewise, if operations commute, only *how many times* each
operation is applied matters, not the order: a sequence of operations collapses to a vector of counts, and the problem
becomes algebra.

### MEX and XOR facts you use without thinking

- $\text{mex}(S)$ is the smallest non-negative integer not in $S$; $\text{mex}(S) \le |S|$; to have $\text{mex} = a$ the set
  must contain $0, \dots, a-1$ and not $a$. Adding $x$ raises the mex iff $x = \text{mex}$.
- XOR is addition without carries: commutative, associative, $a \oplus a = 0$, $a \oplus 0 = a$; XOR of a range is
  $P_r \oplus P_{l-1}$ with prefix XORs; $0 \oplus 1 \oplus \dots \oplus n$ has period 4 (§2).

### Simulation → closed form

When the process is deterministic, simulate it for small inputs, print the results in a table, and look for the closed
form (period, linear growth, powers of two). Then prove the closed form — usually by an invariant or by induction on the
number of operations. This is the ad-hoc twin of the explorer in [constructive algorithms](03-constructive-algorithms.md).

## 2. Formulas, definitions and identities

- **XOR of $0..n$.**
  $$F(n) = 0 \oplus 1 \oplus \dots \oplus n = \begin{cases} n & n \equiv 0 \\ 1 & n \equiv 1 \\ n+1 & n \equiv 2 \\ 0 & n \equiv 3 \end{cases} \pmod 4.$$
  Proof: for even $k$, $k \oplus (k+1) = 1$, so each aligned pair contributes 1 and four consecutive numbers starting
  at a multiple of 4 XOR to 0. XOR of $[l, r]$ is $F(r) \oplus F(l-1)$.
- **Sum vs XOR.** $a + b = (a \oplus b) + 2(a \,\&\, b)$, so $a \oplus b \le a + b$ and $a \oplus b \equiv a + b \pmod 2$.
- **GCD invariance.** $\gcd(a, b) = \gcd(a - b, b)$; hence $\gcd(a_1 + x, \dots, a_n + x) = \gcd(a_1 + x, a_2 - a_1, \dots, a_n - a_1)$.
- **Inversion parity.** An adjacent swap changes the inversion count by exactly $\pm 1$; reversing a segment of length $L$
  changes it by an amount $\equiv \binom{L}{2} \pmod 2$; a 3-cycle is an even permutation.
- **Monovariant bound.** If an integer potential $\Phi$ lies in $[0, M]$ and every operation lowers it by at least 1,
  at most $M$ operations can be performed.
- **Pigeonhole.** $n$ items in $k$ boxes: some box has $\ge \lceil n/k \rceil$. Prefix sums $S_0, \dots, S_n \bmod n$: some
  $S_i \equiv S_j$, so $a_{i+1} + \dots + a_j \equiv 0$.
- **Neighbour-difference operation.** For $c_i \leftarrow c_{i-1} + c_{i+1} - c_i$ with differences $d_k = c_k - c_{k-1}$:
  $d_i' = c_{i+1} - c_i = d_{i+1}$ and $d_{i+1}' = c_i - c_{i-1} = d_i$ — the operation swaps two adjacent differences
  and leaves $c_1$ (and $c_n$) unchanged. Adjacent swaps generate all permutations, so the reachable set is exactly
  "same $c_1$, same multiset of differences".
- **Colouring count.** If every piece covers exactly one black and one white cell, $\#\text{black} = \#\text{white}$ is
  necessary for a tiling.
- **Erdős–Szekeres** (extremal + pigeonhole): any sequence of $rs + 1$ distinct numbers has an increasing subsequence of
  length $r+1$ or a decreasing one of length $s+1$.

## 3. Implementation (C++ and Java)

### 3.1 XOR helpers

```cpp
// XOR of 0..n (n >= 0) and of the range [l, r].
unsigned long long xorUpTo(unsigned long long n) {
    switch (n % 4) { case 0: return n; case 1: return 1; case 2: return n + 1; default: return 0; }
}
unsigned long long xorRange(unsigned long long l, unsigned long long r) {   // l >= 1
    return xorUpTo(r) ^ xorUpTo(l - 1);
}
```

```java
static long xorUpTo(long n) {               // n >= 0
    switch ((int) (n % 4)) { case 0: return n; case 1: return 1; case 2: return n + 1; default: return 0; }
}
static long xorRange(long l, long r) { return xorUpTo(r) ^ xorUpTo(l - 1); }   // l >= 1
```

### 3.2 Reachability explorer: discover invariants by BFS on tiny instances

For an operation you do not understand yet, enumerate all states reachable from a small start state and look at what
they have in common. This program does it for the neighbour-difference operation $c_i \leftarrow c_{i-1} + c_{i+1} - c_i$
($2 \le i \le n-1$): it prints the number of reachable arrays and whether every one of them keeps $c_1$, $c_n$ and the
sorted multiset of differences. Replace `apply` to study another operation.

```cpp
#include <bits/stdc++.h>
using namespace std;
vector<long long> diffsSorted(const vector<long long>& c) {
    vector<long long> d;
    for (size_t i = 1; i < c.size(); i++) d.push_back(c[i] - c[i - 1]);
    sort(d.begin(), d.end());
    return d;
}
int main() {
    int n; cin >> n;
    vector<long long> start(n);
    for (auto& x : start) cin >> x;
    set<vector<long long>> seen = {start};
    queue<vector<long long>> q; q.push(start);
    while (!q.empty()) {
        auto c = q.front(); q.pop();
        for (int i = 1; i + 1 < n; i++) {                 // apply the operation at interior position i
            auto d = c; d[i] = c[i - 1] + c[i + 1] - c[i];
            if (seen.insert(d).second) q.push(d);
        }
    }
    bool inv = true;
    for (auto& c : seen)
        inv &= c[0] == start[0] && c[n - 1] == start[n - 1] && diffsSorted(c) == diffsSorted(start);
    cout << seen.size() << ' ' << (inv ? "invariant-holds" : "invariant-broken") << '\n';
}
```

```java
import java.util.*;

public class Main {
    static List<Long> diffsSorted(List<Long> c) {
        List<Long> d = new ArrayList<>();
        for (int i = 1; i < c.size(); i++) d.add(c.get(i) - c.get(i - 1));
        Collections.sort(d);
        return d;
    }
    public static void main(String[] args) {
        Scanner sc = new Scanner(System.in);               // tiny exploratory input: Scanner is acceptable here
        int n = sc.nextInt();
        List<Long> start = new ArrayList<>();
        for (int i = 0; i < n; i++) start.add(sc.nextLong());
        Set<List<Long>> seen = new HashSet<>();
        Deque<List<Long>> q = new ArrayDeque<>();
        seen.add(start); q.add(start);
        while (!q.isEmpty()) {
            List<Long> c = q.poll();
            for (int i = 1; i + 1 < n; i++) {
                List<Long> d = new ArrayList<>(c);
                d.set(i, c.get(i - 1) + c.get(i + 1) - c.get(i));
                if (seen.add(d)) q.add(d);
            }
        }
        boolean inv = true;
        for (List<Long> c : seen)
            inv &= c.get(0).equals(start.get(0)) && c.get(n - 1).equals(start.get(n - 1)) && diffsSorted(c).equals(diffsSorted(start));
        System.out.println(seen.size() + " " + (inv ? "invariant-holds" : "invariant-broken"));
    }
}
```

<!-- test
in:
4
1 3 2 6
out:
6 invariant-holds
-->
<!-- test
in:
3
5 5 5
out:
1 invariant-holds
-->

The counts match the theory: three distinct differences $(2, -1, 4)$ have $3! = 6$ orders; equal differences give one state.

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "you may perform the operation any number of times", "is it possible to obtain …" | invariant (necessity) + normal form (sufficiency) |
| "minimum number of operations" with a simple operation | monovariant; or reverse the process and make choices forced |
| an operation that touches two elements at once | parity of a count, sum mod something, XOR |
| board, tiles, pieces, tokens moving on a grid | colouring argument (chessboard, mod 3, rows only) |
| $n$ large compared with a modulus or a value range | pigeonhole: some two coincide |
| "MEX" in the statement | which of $0..k-1$ are present; mex $\le$ size; only residues matter after "+x" |
| "XOR" of a range / of everything | prefix XOR, $F(n)$ period 4, $a \oplus a = 0$ |
| answer seems to depend on the arrangement but the operation is very free | maybe only the multiset matters: sort, count |
| deterministic process, huge $n$ or huge number of steps | simulate small, find the period / closed form |

**Commonly confused with:** greedy simulation. If you catch yourself simulating the operations to see whether the
target is reached, stop and look for what the operation preserves — the simulation is usually exponential.

## 5. Worked examples (graded)

### Example 1 — MEXor Mixup  ·  ★ 1000

- **Source:** [CF 1567B · MEXor Mixup](https://codeforces.com/problemset/problem/1567/B) — 1000
- **Difficulty:** 1000
- **Problem:** $t \le 5\cdot 10^4$ queries, each with $1 \le a \le 3\cdot 10^5$ and $0 \le b \le 3 \cdot 10^5$: the minimum length of an
  array of non-negative integers with MEX exactly $a$ and XOR exactly $b$.
- **Thinking from first principles:** MEX $= a$ forces $0, 1, \dots, a-1$ to be present — that is $a$ elements with XOR
  $x = F(a-1)$ — and forbids $a$. Everything else is padding. If $x = b$ we are done with $a$ elements. Otherwise we need
  extra elements XOR-ing to $x \oplus b$: one element $y = x \oplus b$ works unless $y = a$ (forbidden). If $y = a$, two
  elements are needed and suffice: e.g. $a \oplus z$ and $z$ for a large $z$ (both differ from $a$).

<details><summary>Solution</summary>

$x = F(a-1)$; answer $a$ if $x = b$, else $a+1$ if $x \oplus b \ne a$, else $a+2$. $O(1)$ per query.

```cpp
#include <bits/stdc++.h>
using namespace std;
long long xorUpTo(long long n) { long long r[4] = {n, 1, n + 1, 0}; return r[n % 4]; }
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        long long a, b; cin >> a >> b;
        long long x = xorUpTo(a - 1);
        if (x == b) cout << a << '\n';
        else if ((x ^ b) != a) cout << a + 1 << '\n';
        else cout << a + 2 << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static long xorUpTo(long n) { long[] r = {n, 1, n + 1, 0}; return r[(int) (n % 4)]; }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            long a = in.nextLong(), b = in.nextLong();
            long x = xorUpTo(a - 1);
            out.println(x == b ? a : ((x ^ b) != a ? a + 1 : a + 2));
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
5
3 3
3 0
5 7
300000 1
4 0
out:
3
5
6
300001
4
-->
<!-- test
in:
1
1 0
out:
1
-->

</details>

### Example 2 — Trouble Sort  ·  ★ 1300

- **Source:** [CF 1365B · Trouble Sort](https://codeforces.com/problemset/problem/1365/B) — 1300
- **Difficulty:** 1300
- **Problem:** $t$ tests; $n \le 500$ values $a_i$, each with a type $b_i \in \{0, 1\}$. You may swap two elements only if their
  types differ. Can you sort $a$ non-decreasingly? Print `Yes`/`No`.
- **Thinking from first principles:** what is preserved? If all types are equal, *nothing* can move — the array is
  frozen, so the answer is "already sorted?". If both types exist, claim: any permutation is reachable. Pick $x$ of type
  0 and $y$ of type 1; any two elements $p, q$ of the same type can be swapped through an element $r$ of the other type
  with three swaps ($p \leftrightarrow r$, $r \leftrightarrow q$, $p \leftrightarrow r$ — each between different types).
  So all transpositions are available, and they generate every permutation. The answer depends only on "both types
  present?" — the order of $a$ is irrelevant except in the frozen case.

<details><summary>Solution</summary>

`Yes` iff $a$ is already sorted or both types occur. $O(n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        vector<int> a(n), b(n);
        for (auto& x : a) cin >> x;
        for (auto& x : b) cin >> x;
        bool sorted = is_sorted(a.begin(), a.end());
        bool both = count(b.begin(), b.end(), 0) > 0 && count(b.begin(), b.end(), 1) > 0;
        cout << (sorted || both ? "Yes" : "No") << '\n';
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
            int[] a = new int[n];
            for (int i = 0; i < n; i++) a[i] = in.nextInt();
            boolean sorted = true, has0 = false, has1 = false;
            for (int i = 1; i < n; i++) if (a[i - 1] > a[i]) sorted = false;
            for (int i = 0; i < n; i++) { if (in.nextInt() == 0) has0 = true; else has1 = true; }
            out.println(sorted || (has0 && has1) ? "Yes" : "No");
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
4
3
3 1 2
0 0 0
3
3 1 2
1 0 1
1
7
1
4
5 5 6 6
1 1 1 1
out:
No
Yes
Yes
Yes
-->

<!-- test
in:
3
2
2 1
1 1
2
2 1
0 1
5
1 2 2 3 3
0 0 0 0 0
out:
No
Yes
Yes
-->

</details>

### Example 3 — Element Extermination  ·  ★ 1400

- **Source:** [CF 1375C · Element Extermination](https://codeforces.com/problemset/problem/1375/C) — 1400
- **Difficulty:** 1400
- **Problem:** $t$ tests; a permutation $a$ of $1..n$ ($2 \le n$, $\sum n \le 3 \cdot 10^5$). Operation: pick $i$ with $a_i < a_{i+1}$ and delete
  one of these two elements. Can the array be reduced to a single element? Print `YES`/`NO`.
- **Thinking from first principles:** monovariants on the extremes. The first element can only be deleted when it is
  smaller than its right neighbour, and then the new first element is larger: **the first element never decreases**.
  Symmetrically **the last element never increases**. At the end first = last = the survivor $s$, so
  $a_1 \le s \le a_n$, which forces $a_1 < a_n$ (distinct values). Sufficiency (extremal again): if $a_1 < a_n$ and
  $n \ge 3$, some interior element is deletable — an interior $a_i$ is stuck only if $a_{i-1} > a_i > a_{i+1}$, and if all
  interior elements were stuck the whole array would be decreasing, contradicting $a_1 < a_n$. Deleting an interior
  element keeps $a_1, a_n$, so induct down to $n = 2$.

<details><summary>Solution</summary>

`YES` iff $a_1 < a_n$ (the code also accepts $n = 1$, which is trivially done). $O(n)$ per test (reading input).

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        vector<int> a(n);
        for (auto& x : a) cin >> x;
        cout << (n == 1 || a[0] < a[n - 1] ? "YES" : "NO") << '\n';
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
            int first = 0, last = 0;
            for (int i = 0; i < n; i++) { int x = in.nextInt(); if (i == 0) first = x; last = x; }
            out.println(n == 1 || first < last ? "YES" : "NO");
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
4
2 4 1 3
3
3 2 1
2
1 2
out:
YES
NO
YES
-->
<!-- test
in:
1
5
4 5 1 2 3
out:
NO
-->

</details>

### Example 4 — Two Buttons (thinking in reverse)  ·  ★ 1400

- **Source:** [CF 520B · Two Buttons](https://codeforces.com/problemset/problem/520/B) — 1400
- **Difficulty:** 1400
- **Problem:** a display shows $n$; one button doubles the number, the other subtracts 1. Minimum number of presses to
  show $m$ ($1 \le n, m \le 10^4$).
- **Thinking from first principles:** BFS works for these limits, but the reverse view gives an $O(\log m)$ proof-backed
  rule. Reverse operations from $m$: halve (only when even) or add 1. If $m \le n$, only "+1" in reverse (−1 forward)
  makes sense: $n - m$ more steps. If $m > n$ and $m$ is odd, halving is impossible, so add 1 (forced). If $m > n$ and $m$
  is even, halve: adding 1 twice and halving ($m \to (m+2)/2$) takes 3 steps to reach what halving then adding 1 reaches
  in 2, so delaying the halving never helps (an exchange argument on reverse operations).

<details><summary>Solution</summary>

Loop while $m > n$: if $m$ is even halve it, else increment; count steps. Then add $n - m$. $O(\log m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    long long n, m; cin >> n >> m;
    long long steps = 0;
    while (m > n) {
        if (m % 2 == 0) m /= 2; else m++;
        steps++;
    }
    cout << steps + (n - m) << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long n = Long.parseLong(st.nextToken()), m = Long.parseLong(st.nextToken());
        long steps = 0;
        while (m > n) {
            if (m % 2 == 0) m /= 2; else m++;
            steps++;
        }
        System.out.println(steps + (n - m));
    }
}
```

<!-- test
in:
3 8
out:
3
-->
<!-- test
in:
5 5
out:
0
-->
<!-- test
in:
1 10000
out:
20
-->
<!-- test
in:
7 3
out:
4
-->
<!-- test
in:
9999 10000
out:
5000
-->

</details>

### Example 5 — Kuroni and Impossible Calculation (pigeonhole)  ·  ★ 1600

- **Source:** [CF 1305C · Kuroni and Impossible Calculation](https://codeforces.com/problemset/problem/1305/C) — 1600
- **Difficulty:** 1600
- **Problem:** $n \le 2 \cdot 10^5$ numbers $0 \le a_i \le 10^9$ and a modulus $1 \le m \le 1000$. Print
  $\prod_{i<j} |a_i - a_j| \bmod m$.
- **Thinking from first principles:** the product has $\sim 2 \cdot 10^{10}$ factors — far too many. But only residues
  mod $m$ matter, and there are $m \le 1000$ residues. If $n > m$, two numbers share a residue (pigeonhole), their
  difference is divisible by $m$, and the whole product is $0 \bmod m$. Otherwise $n \le 1000$ and the $O(n^2)$ product is
  about $5 \cdot 10^5$ multiplications.

<details><summary>Solution</summary>

If $n > m$ print 0; else multiply $|a_i - a_j| \bmod m$ over all pairs. $O(\min(n, m)^2)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long m; cin >> n >> m;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    if (n > m) { cout << 0 << '\n'; return 0; }
    long long prod = 1 % m;
    for (int i = 0; i < n; i++)
        for (int j = i + 1; j < n; j++) prod = prod * (llabs(a[i] - a[j]) % m) % m;
    cout << prod << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(); long m = in.nextLong();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        if (n > m) { System.out.println(0); return; }
        long prod = 1 % m;
        for (int i = 0; i < n; i++)
            for (int j = i + 1; j < n; j++) prod = prod * (Math.abs(a[i] - a[j]) % m) % m;
        System.out.println(prod);
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
3 100
2 7 3
out:
20
-->
<!-- test
in:
4 3
1 2 3 4
out:
0
-->
<!-- test
in:
2 1
5 9
out:
0
-->
<!-- test
in:
3 997
1000000000 0 5
out:
976
-->

</details>

### Example 6 — Magic Stones (invariant + normal form)  ·  ★ 2200

- **Source:** [CF 1110E · Magic Stones](https://codeforces.com/problemset/problem/1110/E) — 2200
- **Difficulty:** 2200
- **Problem:** arrays $c$ and $t$ of length $n \le 10^5$ ($0 \le c_i, t_i \le 2\cdot 10^9$). Operation: choose $2 \le i \le n-1$ and set
  $c_i \leftarrow c_{i-1} + c_{i+1} - c_i$. Can $c$ be turned into $t$? Print `Yes`/`No`.
- **Thinking from first principles:** the operation looks like a reflection of $c_i$ around the midpoint of its
  neighbours. Run the explorer (§3.2) on a small array: the reachable count is the number of orderings of the adjacent
  differences, and $c_1, c_n$ never change. The algebra (§2) confirms it: the operation swaps $d_i$ and $d_{i+1}$.
  Necessity: $c_1 = t_1$ and equal multisets of differences. Sufficiency: adjacent transpositions generate every
  permutation of $(d_2, \dots, d_n)$, so any reordering — in particular the one producing $t$ — is reachable.

<details><summary>Solution</summary>

Compare $c_1$ with $t_1$, sort both difference arrays and compare. $O(n \log n)$. Differences reach $\pm 2\cdot 10^9$, so use
64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long long> c(n), t(n);
    for (auto& x : c) cin >> x;
    for (auto& x : t) cin >> x;
    vector<long long> dc, dt;
    for (int i = 1; i < n; i++) { dc.push_back(c[i] - c[i - 1]); dt.push_back(t[i] - t[i - 1]); }
    sort(dc.begin(), dc.end()); sort(dt.begin(), dt.end());
    cout << (c[0] == t[0] && dc == dt ? "Yes" : "No") << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] c = new long[n], t = new long[n];
        for (int i = 0; i < n; i++) c[i] = in.nextLong();
        for (int i = 0; i < n; i++) t[i] = in.nextLong();
        long[] dc = new long[n - 1], dt = new long[n - 1];
        for (int i = 1; i < n; i++) { dc[i - 1] = c[i] - c[i - 1]; dt[i - 1] = t[i] - t[i - 1]; }
        shuffle(dc); shuffle(dt);                 // defeat anti-quicksort tests on primitive arrays
        Arrays.sort(dc); Arrays.sort(dt);
        System.out.println(c[0] == t[0] && Arrays.equals(dc, dt) ? "Yes" : "No");
    }
    static void shuffle(long[] a) {
        Random r = new Random();
        for (int i = a.length - 1; i > 0; i--) { int j = r.nextInt(i + 1); long x = a[i]; a[i] = a[j]; a[j] = x; }
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
4
0 3 3 10
0 7 7 10
out:
Yes
-->
<!-- test
in:
3
1 5 3
1 0 3
out:
No
-->
<!-- test
in:
2
5 6
5 7
out:
No
-->
<!-- test
in:
1
4
4
out:
Yes
-->

</details>

Examples 1, 3, 4, 5 and 6 were stress-tested against brute force (BFS over reachable states or exhaustive search on
small inputs); Example 2 against a BFS over all arrangements reachable by allowed swaps.

## 6. Tricks, pitfalls and things to remember

1. **Write the checklist down.** Sum, parity, XOR, gcd, multiset, differences, extremes, order, permutation parity,
   colour counts — five minutes with the table in §1 solves most operation problems.
2. **Invariant ≠ answer.** An invariant proves necessity only. Before submitting "Yes iff invariant matches", prove
   sufficiency (normal form) or at least confirm with a BFS on small cases.
3. **BFS on tiny instances is the experiment.** States of 4–6 small numbers are enough to see reachable sets; compare
   them with your conjectured invariant automatically (§3.2).
4. **Monovariants on extremes** (first element only grows, maximum only shrinks) are the quickest necessity proofs for
   deletion/merge operations.
5. **Reverse the process** when forward choices branch and backward ones are forced (doubling/halving, merges, painting).
6. **Pigeonhole cuts complexity:** when $n$ exceeds the number of residues/values, the answer is often trivially 0 or
   "Yes" — check this before the $O(n^2)$ loop.
7. **`%` on negatives** in C++ and Java returns a negative remainder: use `((x % m) + m) % m` for parity/residue
   invariants of possibly negative numbers, or test parity with `x & 1`.
8. **Overflow in invariants:** sums of $10^5$ values up to $10^9$, differences of values up to $2\cdot10^9$ — 64-bit.
9. **Java `Arrays.sort(long[])` on adversarial input** can be $O(n^2)$; shuffle first (Example 6) or sort boxed values.
10. **MEX pitfalls:** MEX is over non-negative integers starting at 0; computing it needs a boolean array of size $n+1$,
    not $\max a_i$; values above $n$ never matter.
11. **XOR of $1..n$ vs $0..n$** is the same; XOR of $l..r$ needs $F(l-1)$, with $F(-1)$ treated as 0.
12. **Order-independence check:** if shuffling the input cannot change the answer, sort it; if shuffling the operations
    cannot change the result, reason about counts.

## 7. Going further (toward 2400–2600+)

- **Linear-algebra invariants:** operations that add rows/vectors over GF(2) preserve the span — reachable sets are
  cosets of a subspace ([XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md)).
- **Potential functions in amortised analysis** are monovariants with weights; the same idea proves bounds for
  segment tree beats and splay trees ([segment tree beats](../08-Data-Structures/04-segment-tree-advanced-descent-merging-beats.md)).
- **Games:** winning/losing positions are invariants of optimal play; Sprague–Grundy values are XOR invariants
  ([Nim and Sprague–Grundy](../13-Game-Theory/02-nim-and-sprague-grundy.md)).
- **Permutation-group reachability:** which permutations are generated by a set of allowed swaps or rotations
  (connected components of a swap graph; parity when only 3-cycles are allowed).
- **Hard ad-hoc at 2400+** is mostly *several* weak invariants combined, plus a normal form that needs a clever
  construction; practise by always writing the BFS experiment first.

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 1406A · Subset Mex](https://codeforces.com/problemset/problem/1406/A) — 900
- [ ] [CF 1567B · MEXor Mixup](https://codeforces.com/problemset/problem/1567/B) — 1000
- [ ] [CF 1352B · Same Parity Summands](https://codeforces.com/problemset/problem/1352/B) — 1200
- [ ] [CF 1365B · Trouble Sort](https://codeforces.com/problemset/problem/1365/B) — 1300
- [ ] [CF 1401C · Mere Array](https://codeforces.com/problemset/problem/1401/C) — 1300
- [ ] [CF 1375C · Element Extermination](https://codeforces.com/problemset/problem/1375/C) — 1400
- [ ] [CF 520B · Two Buttons](https://codeforces.com/problemset/problem/520/B) — 1400
- [ ] [CSES 1754 · Coin Piles](https://cses.fi/problemset/task/1754)
- [ ] [CSES 1083 · Missing Number](https://cses.fi/problemset/task/1083)

**1400–1900**
- [ ] [CF 1458A · Row GCD](https://codeforces.com/problemset/problem/1458/A) — 1600
- [ ] [CF 1294D · MEX maximizing](https://codeforces.com/problemset/problem/1294/D) — 1600
- [ ] [CF 1305C · Kuroni and Impossible Calculation](https://codeforces.com/problemset/problem/1305/C) — 1600
- [ ] [CF 1364C · Ehab and Prefix MEXs](https://codeforces.com/problemset/problem/1364/C) — 1600
- [ ] [CF 1516C · Baby Ehab Partitions Again](https://codeforces.com/problemset/problem/1516/C) — 1700
- [ ] [CSES 1670 · Swap Game](https://cses.fi/problemset/task/1670)

**1900–2400**
- [ ] [CF 1375D · Replace by MEX](https://codeforces.com/problemset/problem/1375/D) — 1900
- [ ] [CF 1349B · Orac and Medians](https://codeforces.com/problemset/problem/1349/B) — 2000
- [ ] [CF 1416B · Make Them Equal](https://codeforces.com/problemset/problem/1416/B) — 2000
- [ ] [CF 1110E · Magic Stones](https://codeforces.com/problemset/problem/1110/E) — 2200

**2400+**
- [ ] [CF 1270G · Subset with Zero Sum](https://codeforces.com/problemset/problem/1270/G) — 2700

## 9. LeetCode / FAANG cross-reference

- [LC 136 · Single Number](https://leetcode.com/problems/single-number/) — Easy — $a \oplus a = 0$ cancels pairs.
- [LC 268 · Missing Number](https://leetcode.com/problems/missing-number/) — Easy — XOR of indices and values, or the sum invariant.
- [LC 287 · Find the Duplicate Number](https://leetcode.com/problems/find-the-duplicate-number/) — Medium — pigeonhole guarantees a duplicate; Floyd cycle on $i \to a_i$.
- [LC 41 · First Missing Positive](https://leetcode.com/problems/first-missing-positive/) — Hard — the answer (a MEX) is at most $n+1$; place each value at its index.
- [LC 292 · Nim Game](https://leetcode.com/problems/nim-game/) — Easy — invariant "$n \bmod 4 = 0$ is losing".
- [LC 877 · Stone Game](https://leetcode.com/problems/stone-game/) — Medium — colouring argument (even vs odd indices): the first player always wins.
- [LC 991 · Broken Calculator](https://leetcode.com/problems/broken-calculator/) — Medium — exactly Two Buttons with reverse thinking.
- [LC 780 · Reaching Points](https://leetcode.com/problems/reaching-points/) — Hard — reverse the moves; subtracting repeatedly becomes a modulo (Euclid).
- [LC 1529 · Minimum Suffix Flips](https://leetcode.com/problems/minimum-suffix-flips/) — Medium — count changes between adjacent bits (order-independent counting).

Interview versions are mostly the XOR/pigeonhole/reverse-thinking ones above; being able to *state* the invariant is
what separates a hire from a no-hire on them.

## 10. Self-check

1. What is the difference between an invariant and a monovariant, and what does each prove?
2. Why does an invariant alone not prove that a target is reachable? What is a normal-form argument?
3. Compute $0 \oplus 1 \oplus \dots \oplus 22$ and justify the period-4 formula.
4. In Trouble Sort, why does having both types allow every permutation?
5. Prove that in Element Extermination the first element never decreases.
6. Why does Two Buttons prefer halving whenever the target is even and larger than $n$?
7. What does $c_i \leftarrow c_{i-1} + c_{i+1} - c_i$ do to the difference array?
8. State a colouring argument that shows a board cannot be tiled by dominoes.

<details><summary>Answers</summary>

1. Invariant: unchanged by every operation — proves unreachability when values differ (necessity). Monovariant: moves
   in one direction — proves termination, bounds operation counts, constrains final states.
2. Equal invariants are necessary, not sufficient. Normal form: show every state with given invariants can reach a
   canonical state depending only on the invariants; with reversible operations, start and target connect through it.
3. $22 \equiv 2 \pmod 4$, so $F(22) = 23$. Pairs $(2k, 2k+1)$ XOR to 1, two pairs cancel, which gives period 4.
4. Two same-type elements swap via an element of the other type in three allowed swaps, so every transposition is
   available, and transpositions generate the symmetric group.
5. $a_1$ can be deleted only when $a_1 < a_2$, and then $a_2$ becomes first; otherwise $a_1$ stays.
6. Reverse ops are "halve" and "+1". Doing "+1, +1, halve" reaches $(m+2)/2$ in 3 steps; "halve, +1" reaches it in 2, so
   postponing a possible halving never helps.
7. It swaps $d_i = c_i - c_{i-1}$ and $d_{i+1} = c_{i+1} - c_i$ and keeps $c_1$, $c_n$.
8. Chessboard-colour the board; every domino covers one black and one white cell; if the board has unequal numbers of
   black and white cells (e.g. two opposite corners removed), no tiling exists.

</details>
