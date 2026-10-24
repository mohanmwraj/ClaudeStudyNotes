# How grandmasters think: heuristics, editorials and deliberate practice

> **Band:** every band, but written for the 2100 → 2600 transition · **Priority:** 🔥 (this is the file to reread every month) · **FAANG:** medium (the same heuristics crack "aha" interview questions) · **Prerequisites:** [first-principles problem solving](../00-Roadmap-and-Strategy/05-first-principles-problem-solving.md), [practice methodology](../00-Roadmap-and-Strategy/03-practice-methodology.md), [invariants, parity and ad-hoc observations](../03-Greedy-Constructive-Interactive/04-invariants-parity-and-ad-hoc-observations.md), [contribution technique](../05-Combinatorics-and-Probability/07-contribution-technique.md)
> **You can say you know this when:** stuck on a problem, you can run through a list of concrete transformations, each of which produces a *new* question to think about; you keep an idea journal and actually reread it; and every contest you take part in is followed by upsolving.

A note on sources. This file collects heuristics that appear again and again in editorials, in blogs by strong competitors, and in the author's own experience. Where something is a widely shared opinion rather than a fact, it is labelled as such. No quotations are attributed to named people, because quotes that circulate in the community are often unverifiable.

## 1. First principles — why this works

### 1.1 What actually changes above 2100

At 1900–2100 most problems are "know the technique, apply it carefully": the algorithm is usually standard once the problem is restated. From about 2300 — a widely shared observation rather than a measured fact — problems are typically built around **one to three observations** that turn an intractable statement into a standard one, and the observation is the hard part; the implementation afterwards is often short.

So the skill to train is not "know more algorithms" (folders 01–15 and the rest of this folder cover them) but **generating candidate observations quickly and testing them cheaply**. The heuristics below are generators. Each one turns "I'm stuck" into a specific question you can work on.

A widely shared opinion among strong competitors is that most of their speed comes from *recognising* a reduction they have seen before. That is the reason for the idea journal (§1.4): recognition is trainable.

### 1.2 The heuristics, with the question each one asks

1. **Reduce to a canonical form.** *"Which inputs are equivalent, and what is the simplest representative?"* Sort what can be sorted, factor out what can be factored (square-free parts, $\gcd$s, differences instead of values), and treat indistinguishable objects as identical. Two ants bouncing off each other are indistinguishable from two ants passing through each other; $\gcd(a_1 + b, \dots, a_n + b) = \gcd(a_1 + b, a_2 - a_1, \dots, a_n - a_1)$. Once inputs are canonical, "can A become B" often becomes "are their canonical forms equal" (Example 5).

2. **Guess by brute force, then prove.** *"What does the answer look like for $n = 1..30$?"* Write the exponential brute force, print a table, and look for periodicity, powers of two, parity, a formula, or a sequence you recognise. Then prove the pattern by induction or by exhibiting a strategy. Games and constructive problems almost always yield to this (Example 2). Never submit an unproved pattern without stress-testing it against the brute force on every $n$ you can afford.

3. **Consider the extremal element or the last operation.** *"What is true about the maximum / minimum / first / last thing?"* The maximum of an array splits it into independent parts; the last operation in a sequence sees the final state of its neighbours; the smallest counterexample cannot be reduced. Reversing the time order ("which balloon bursts *last*?") turns dependent subproblems into independent ones (Example 4).

4. **Fix one parameter, optimise the other.** *"If I knew $X$, would the rest be easy?"* Enumerate the smaller dimension, the position of the maximum, the value of the answer (then binary search if feasibility is monotone), the number of operations of type A. Many $O(n^2)$ problems are "fix $i$, optimise $j$" plus a data structure.

5. **Look for monotonicity.** *"If $x$ works, does $x+1$ work?"* Monotone feasibility gives binary search on the answer; monotone pointers give two pointers; monotone predicates over time give [parallel binary search](01-offline-techniques-cdq-parallel-binary-search.md).

6. **Think about what the answer can't be.** *"What bounds can I prove?"* Lower bounds from counting or invariants, upper bounds from a simple construction, pigeonhole ("with $n > V$ elements two must collide"), "the answer is at most 2". A tight bound frequently reveals the construction, and a weak bound often shrinks the search space to something brute-forceable (Example 3).

7. **Hunt for invariants.** *"What does the operation never change?"* Parity, sums modulo $k$, the multiset of differences, the relative order of a class of elements, the number of inversions modulo 2. If an invariant separates start and target, the answer is "no"; if the invariant classes are reachable within themselves, the invariant *is* the answer.

8. **Simplify the constraints, then generalise.** *"What if $n \le 3$? All values in $\{0, 1\}$? The tree is a path? $k = 1$?"* Solve the special case completely, then ask which step of that solution breaks for the general case. Many solutions are the special-case idea plus one data structure.

9. **Think in terms of contribution.** *"Instead of summing over structures, can I sum over elements?"* $\sum_{\text{structures } S}\ \sum_{x \in S} w(x) = \sum_x w(x)\cdot\#\{S \ni x\}$. Counting how many subarrays have $a_i$ as their maximum is easier than computing every subarray's maximum (Example 1; see also the [contribution technique](../05-Combinatorics-and-Probability/07-contribution-technique.md)).

10. **Read the setter's intention from the constraints.** *"Why is this limit so strange?"* $n \le 20$ suggests $2^n$; $n \le 5000$ suggests $O(n^2)$; $\sum n \le 2\cdot10^5$ over test cases suggests per-test $O(n\log n)$; a small parameter (like $k \le 100$ or $a_i \le n$) is almost always where the solution lives; an unusually generous time limit suggests $O(n\sqrt n)$ or bitsets. The [complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md) file has the full table.

11. **Change the viewpoint.** *"What is this as a graph / as an interval / backwards / as its complement?"* States become vertices, pairs become edges, "at least one" becomes "total minus none", deletions become insertions in reverse.

12. **When stuck for 15 minutes, write the brute force anyway.** It forces you to pin down the statement, it produces small cases to look at (heuristic 2), and you will need it to stress-test the real solution.

### 1.3 How to read an editorial and extract the transferable idea

An editorial explains *this* problem; your goal is to learn something that solves *the next* one. A process that many strong competitors describe in some form:

1. **Earn the editorial.** Work on the problem until you have genuinely run out of ideas — a common rule of thumb is 45–90 minutes for problems in your training range — and write down what you tried. Without that, the editorial's key step does not register as surprising, and surprise is what you remember.
2. **Read one hint at a time.** Read only the first paragraph (or the first hint, if the editorial has them), then close it and try again. Often one sentence is enough, and solving the rest yourself is worth much more than reading it.
3. **Name the idea in one line, in your own words** — not "use a segment tree" but "the answer only depends on the multiset of differences, and the operation swaps adjacent differences".
4. **Name the trigger:** which feature of the statement should have suggested the idea? ("Operation touches three consecutive elements and is linear" → look at differences.)
5. **Implement from scratch** without looking at the reference code; compare only afterwards.
6. **File it** in the idea journal and add 1–2 related problems to try later.

### 1.4 The idea journal

A plain text or spreadsheet file with one entry per problem that taught you something:

```text
Problem:     CF 1110E Magic Stones (2200)          Date: 2026-11-02
Trigger:     operation c_i <- c_{i-1} + c_{i+1} - c_i on inner elements
Key idea:    it swaps adjacent differences; invariants = c_1 + multiset of differences
Why I missed it: looked at values, never at differences
Related:     CF 1458A Row GCD (differences make gcd invariant)
Review:      +7d, +30d
```

Reread entries on a schedule (a week later, a month later). The "why I missed it" field is the most valuable: patterns in it show which heuristic you under-use.

### 1.5 Training at +300 to +500 above your rating

A common recommendation (an opinion, but a widely shared one) is to spend most practice time on problems rated about 200–500 above your current rating. The reasoning: problems you can already solve quickly do not change how you think; problems far above your level end with reading the editorial without the context to absorb it; the band in between forces you to find a new observation with effort, which is exactly the skill being trained. For the Dec-2027 Master target this means working mostly at 2000–2400 during 2027, and for the IGM direction afterwards 2400–2800. Keep a fraction of easier problems for speed and accuracy — contest rating also depends on solving A–C fast and without penalties.

### 1.6 Virtual contests and upsolving discipline

- **Virtual contests** train the contest skill (problem selection, time allocation, debugging under pressure), which is distinct from the problem-solving skill. Taking full rounds virtually, with no editorial, under the real time limit, is the closest substitute for live rounds.
- **Upsolving:** after every live or virtual round, solve every problem up to (at least) one beyond the last one you solved, within a day or two, while the problem is fresh. A frequently heard opinion is that upsolving is where most of the improvement from a contest comes from.
- **Measure:** keep a log of time-to-solve and wrong submissions per problem. Rating graphs are noisy; these numbers are not.

The roadmap files [practice methodology](../00-Roadmap-and-Strategy/03-practice-methodology.md) and [contest strategy and mindset](../00-Roadmap-and-Strategy/04-contest-strategy-and-mindset.md) turn this into a weekly schedule.

## 2. Formulas, definitions and identities

- **Operation budget:** about $10^8$–$10^9$ simple operations per second in C++ (Java usually within a factor 1–2). With $n = 2\cdot10^5$: $n\log n \approx 3.5\cdot10^6$, $n\sqrt n \approx 9\cdot10^7$, $n^2 = 4\cdot10^{10}$ (too slow).

| Constraint | Typical intended complexity |
|---|---|
| $n \le 10$–$12$ | $n!$, $n^n$ for tiny $n$ |
| $n \le 20$ | $2^n \cdot n$ |
| $n \le 40$ | $2^{n/2}$ (meet in the middle) |
| $n \le 500$ | $n^3$ |
| $n \le 5000$ | $n^2$ |
| $n \le 10^5$–$2\cdot10^5$ | $n\log n$, $n\log^2 n$, $n\sqrt n$ |
| $n \le 10^6$–$10^7$ | $n$ or $n\log\log n$ |
| $n \le 10^{18}$ | $\log n$, $\sqrt[3]{n}$, closed form, matrix power |

- **Contribution identity:** $\sum_{S} \sum_{x \in S} w(x) = \sum_x w(x)\,\#\{S : x \in S\}$; for subarrays, $\#\{[l,r] \ni i\} = i(n-i+1)$ (1-based).
- **Harmonic bound:** $\sum_{d=1}^{n} \lfloor n/d \rfloor = n\ln n + O(n)$ — "for each $d$, iterate over its multiples" is $O(n\log n)$.
- **Pigeonhole:** $n+1$ objects in $n$ boxes put two in one box; pairs of $k$ objects give $\binom{k}{2}$ sums, so if $\binom{k}{2}$ exceeds the number of possible sums, two pairs share a sum.
- **Invariant test:** if $I(\text{op}(s)) = I(s)$ for every operation, then $I(\text{start}) \ne I(\text{target})$ proves impossibility; if additionally every pair of states with equal $I$ is connected, $I(\text{start}) = I(\text{target})$ is the full answer.
- **Exchange argument:** if swapping two adjacent choices never makes the result worse when they are "out of order", sorting by that order is optimal (see [greedy and exchange arguments](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md)).

## 3. Implementation (C++ and Java)

The tool that makes heuristic 2 and heuristic 12 cheap: a self-contained **stress tester**. It generates many tiny random inputs from a seed, runs the fast solution and a brute force, and prints the first counterexample. The demo problem is the maximum subarray sum (Kadane vs. all subarrays); replace `fast` and `brute` with your own. The seed is fixed on purpose here: a failing case must be reproducible.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

// Self-contained stress tester: replace fast() and brute() with your solution and a trivially correct one.
// Demo problem: maximum sum of a non-empty subarray.
ll fast(const vector<ll>& a) {                     // Kadane, O(n)
    ll best = a[0], cur = 0;
    for (ll x : a) { cur = max(cur + x, x); best = max(best, cur); }
    return best;
}
ll brute(const vector<ll>& a) {                    // every subarray, O(n^2)
    ll best = LLONG_MIN;
    for (size_t l = 0; l < a.size(); l++) {
        ll s = 0;
        for (size_t r = l; r < a.size(); r++) { s += a[r]; best = max(best, s); }
    }
    return best;
}

int main() {
    unsigned long long seed;
    int iters;
    cin >> seed >> iters;
    mt19937_64 rng(seed);                          // fixed seed here: we WANT reproducible failures
    for (int it = 0; it < iters; it++) {
        int n = rng() % 8 + 1;                     // tiny inputs: easy to read when they fail
        int range = vector<int>{1, 3, 10, 1000000000}[rng() % 4];
        vector<ll> a(n);
        for (auto& x : a) x = (ll)(rng() % (2 * range + 1)) - range;
        ll f = fast(a), b = brute(a);
        if (f != b) {
            cout << "FAIL on iteration " << it << "\n" << n << "\n";
            for (ll x : a) cout << x << ' ';
            cout << "\nfast=" << f << " brute=" << b << '\n';
            return 0;
        }
    }
    cout << "OK\n";
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static long fast(long[] a) {
        long best = a[0], cur = 0;
        for (long x : a) { cur = Math.max(cur + x, x); best = Math.max(best, cur); }
        return best;
    }
    static long brute(long[] a) {
        long best = Long.MIN_VALUE;
        for (int l = 0; l < a.length; l++) {
            long s = 0;
            for (int r = l; r < a.length; r++) { s += a[r]; best = Math.max(best, s); }
        }
        return best;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        long seed = Long.parseLong(st.nextToken());
        int iters = Integer.parseInt(st.nextToken());
        SplittableRandom rng = new SplittableRandom(seed);      // reproducible on purpose
        int[] ranges = {1, 3, 10, 1000000000};
        for (int it = 0; it < iters; it++) {
            int n = rng.nextInt(8) + 1, range = ranges[rng.nextInt(4)];
            long[] a = new long[n];
            for (int i = 0; i < n; i++) a[i] = rng.nextLong(2L * range + 1) - range;
            long f = fast(a), b = brute(a);
            if (f != b) {
                System.out.println("FAIL on iteration " + it + "\n" + n + "\n" + Arrays.toString(a) + "\nfast=" + f + " brute=" + b);
                return;
            }
        }
        System.out.println("OK");
    }
}
```

<!-- test
in:
12345 2000
out:
OK
-->
<!-- test
in:
7 1
out:
OK
-->

## 4. Recognising the pattern

| Statement feature | Heuristic to try first |
|---|---|
| "Sum / count over all subarrays, subsets, pairs, paths" | contribution (9) |
| A game, or "for which $n$ is it possible?" | brute force + pattern (2) |
| An operation that can be applied any number of times; "can $A$ become $B$?" | invariants (7), canonical form (1) |
| Removing or merging elements where neighbours change | last operation / extremal element (3) |
| "Minimise the maximum", "smallest $k$ such that" | monotonicity → binary search (5) |
| A suspiciously small parameter ($k \le 100$, $a_i \le n$, $\sum$ of something small) | constraints reveal intent (10), bound the answer (6) |
| Many objects, few possible values | pigeonhole / bound (6) |
| Deletions over time | reverse time (11) |
| Two interacting parameters | fix one (4) |
| You have no idea at all after 15 minutes | special cases (8) and brute force (12) |

## 5. Worked examples (graded)

### Example 1 — Contribution: sum of (max − min) over all subarrays  ·  ★ ≈1700 (est.)

- **Source:** [LC 2104 · Sum of Subarray Ranges](https://leetcode.com/problems/sum-of-subarray-ranges/) — Medium (here with $n \le 10^5$ instead of LeetCode's small limit).
- **Difficulty:** ≈1700 (est.)
- **Problem:** Array of $n \le 10^5$ integers in $[0, 10^9]$. Compute $\sum_{l \le r} (\max a[l..r] - \min a[l..r])$.
- **Thinking from first principles:** Enumerating subarrays is $\Theta(n^2)$ even with running max/min. Heuristic 9: swap the order of summation. $\sum_{[l,r]} \max = \sum_i a_i \cdot \#\{[l,r] : a_i \text{ is its maximum}\}$. For a fixed $i$, the subarrays where $a_i$ is the maximum are those with $l$ after the previous larger element and $r$ before the next larger element — the nearest-greater elements, found for all $i$ with a monotonic stack. The only subtlety is ties: decide that the *leftmost* maximum gets the credit, so use "$\ge$" on one side and "$>$" on the other.

<details><summary>Solution</summary>

For the maximum: $L_i$ = nearest $j < i$ with $a_j \ge a_i$, $R_i$ = nearest $j > i$ with $a_j > a_i$; $a_i$ is the credited maximum of exactly $(i - L_i)(R_i - i)$ subarrays. Same for the minimum with reversed comparisons. Answer $= \sum_i a_i (i - L_i)(R_i - i)\big|_{\max} - \sum_i a_i (i-L_i)(R_i-i)\big|_{\min}$. Each subarray has exactly one credited maximum and one credited minimum, which proves correctness. $O(n)$. The sum of maxima is at most $\binom{n+1}{2} \cdot 10^9 \approx 5\cdot10^{18}$, inside signed 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

// Sum over all subarrays of (max - min) = sum_i a_i * (#subarrays where a_i is the max)
//                                       - sum_i a_i * (#subarrays where a_i is the min).
// Ties: a subarray's max is credited to its leftmost maximal element (strict on the left,
// non-strict on the right), so every subarray is counted exactly once.
ll contribution(const vector<ll>& a, bool wantMax) {
    int n = a.size();
    auto beats = [&](ll x, ll y) { return wantMax ? x > y : x < y; };
    vector<int> L(n), R(n), st;
    for (int i = 0; i < n; i++) {                  // L[i]: nearest j < i with a[j] beating-or-equal a[i]
        while (!st.empty() && beats(a[i], a[st.back()])) st.pop_back();
        L[i] = st.empty() ? -1 : st.back();
        st.push_back(i);
    }
    st.clear();
    for (int i = n - 1; i >= 0; i--) {             // R[i]: nearest j > i with a[j] strictly beating a[i]
        while (!st.empty() && !beats(a[st.back()], a[i])) st.pop_back();
        R[i] = st.empty() ? n : st.back();
        st.push_back(i);
    }
    ll s = 0;
    for (int i = 0; i < n; i++) s += a[i] * (ll)(i - L[i]) * (R[i] - i);
    return s;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<ll> a(n);
    for (auto& x : a) cin >> x;
    cout << contribution(a, true) - contribution(a, false) << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static long contribution(long[] a, boolean wantMax) {
        int n = a.length;
        int[] L = new int[n], R = new int[n], st = new int[n];
        int top = 0;
        for (int i = 0; i < n; i++) {
            while (top > 0 && beats(a[i], a[st[top - 1]], wantMax)) top--;
            L[i] = top == 0 ? -1 : st[top - 1];
            st[top++] = i;
        }
        top = 0;
        for (int i = n - 1; i >= 0; i--) {
            while (top > 0 && !beats(a[st[top - 1]], a[i], wantMax)) top--;
            R[i] = top == 0 ? n : st[top - 1];
            st[top++] = i;
        }
        long s = 0;
        for (int i = 0; i < n; i++) s += a[i] * (long) (i - L[i]) * (R[i] - i);
        return s;
    }
    static boolean beats(long x, long y, boolean wantMax) { return wantMax ? x > y : x < y; }

    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) readLong(in);
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = readLong(in);
        System.out.println(contribution(a, true) - contribution(a, false));
    }

    static long readLong(DataInputStream in) throws IOException {
        int c = in.read();
        while (c != '-' && (c < '0' || c > '9')) c = in.read();
        boolean neg = c == '-';
        if (neg) c = in.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = in.read(); }
        return neg ? -r : r;
    }
}
```

</details>

<!-- test
in:
3
4 1 3
out:
8
-->
<!-- test
in:
1
5
out:
0
-->
<!-- test
in:
4
2 2 2 2
out:
0
-->
<!-- test
in:
2
0 1000000000
out:
1000000000
-->

### Example 2 — Guess by brute force, then prove: a divisor game  ·  ★ 1700

- **Source:** [CF 1537D · Deleting Divisors](https://codeforces.com/problemset/problem/1537/D) — 1700
- **Difficulty:** 1700
- **Problem:** Starting from $n$ ($n \le 10^9$, up to $10^4$ test cases), players alternately subtract from the current number one of its divisors $d$ with $1 < d < n$. A player who cannot move loses. Who wins with optimal play?
- **Thinking from first principles:** Heuristic 2: write the brute force (`win[n]` = some move reaches a losing state), print the losing $n$ up to 100: $1, 2, 3, 5, 7, 8, 9, 11, \dots, 31, 32, 33, \dots$ — every odd number, plus $2, 8, 32, 128$. Conjecture: odd $n$ loses; even $n$ wins unless $n = 2^k$ with $k$ odd. Then prove it.

<details><summary>Solution</summary>

*Proof of the conjecture.* (a) **Odd $n$ loses.** Every divisor $d$ of an odd $n$ is odd, so $n - d$ is even; and $n - d$ is not a power of two, because $d \mid n - d$ and $d > 1$ is odd. So from an odd number you always move to an even non-power-of-two. (b) **Even non-power-of-two wins:** such $n$ has an odd divisor $d > 1$; $n - d$ is odd, which loses by (a) — the two claims are proved together by induction on $n$. (c) **Powers of two:** from $2^k$ the only useful moves go to $2^{k-1}$ (subtracting any other divisor $2^j$, $j < k-1$, gives an even non-power-of-two, which wins for the opponent by (b)). So the players walk down $2^k, 2^{k-1}, \dots, 2$, and $2$ has no move: $2^k$ wins iff $k$ is even.

The brute force used to find the pattern is kept below as a fragment; it also served as the stress-test oracle for $n \le 600$.

```cpp
// Brute force for small n: win[n] = some move (subtract a divisor d, 1 < d < n) reaches a losing state.
// Print the losing n up to 100 and stare at the list: 1 2 3 5 7 8 9 11 13 15 17 ... 31 32 33 ...
vector<bool> bruteWins(int N) {
    vector<bool> win(N + 1, false);
    for (int n = 1; n <= N; n++)
        for (int d = 2; d * d <= n && !win[n]; d++)
            if (n % d == 0 && (!win[n - d] || !win[n - n / d])) win[n] = true;
    return win;
}
```

```java
// win[n] is true iff the player to move at n wins; moves subtract a divisor d with 1 < d < n.
static boolean[] bruteWins(int N) {
    boolean[] win = new boolean[N + 1];
    for (int n = 1; n <= N; n++)
        for (int d = 2; (long) d * d <= n && !win[n]; d++)
            if (n % d == 0 && (!win[n - d] || !win[n - n / d])) win[n] = true;
    return win;
}
```

```cpp
#include <bits/stdc++.h>
using namespace std;

// Pattern found by brute force (see bruteWins) and then proved:
// odd n loses; even n that is not a power of two wins; n = 2^k wins iff k is even.
bool firstPlayerWins(long long n) {
    if (n % 2 == 1) return false;
    if ((n & (n - 1)) != 0) return true;
    int k = __builtin_ctzll(n);
    return k % 2 == 0;
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        long long n;
        cin >> n;
        cout << (firstPlayerWins(n) ? "Alice" : "Bob") << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    static boolean firstPlayerWins(long n) {
        if (n % 2 == 1) return false;
        if ((n & (n - 1)) != 0) return true;
        return Long.numberOfTrailingZeros(n) % 2 == 0;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in), 1 << 16);
        StreamTokenizer st = new StreamTokenizer(br);
        st.nextToken();
        int t = (int) st.nval;
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            st.nextToken();
            long n = (long) st.nval;                 // n <= 1e9 is exact in a double
            sb.append(firstPlayerWins(n) ? "Alice" : "Bob").append('\n');
        }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.print(sb);
        out.flush();
    }
}
```

</details>

<!-- test
in:
8
1
2
4
6
8
12
16
999
out:
Bob
Bob
Alice
Alice
Bob
Alice
Alice
Bob
-->
<!-- test
in:
1
999999999
out:
Bob
-->

### Example 3 — What the answer can't be: only the last indices matter  ·  ★ 1700

- **Source:** [CF 1554B · Cobb](https://codeforces.com/problemset/problem/1554/B) — 1700
- **Difficulty:** 1700
- **Problem:** Given $n$ ($\sum n \le 3\cdot10^5$ over test cases), $k \le \min(n, 100)$ and $0 \le a_i \le n$, maximise $i \cdot j - k\cdot(a_i \mid a_j)$ over $1 \le i < j \le n$.
- **Thinking from first principles:** $O(n^2)$ pairs is too many. Heuristic 10: why is $k \le 100$ and $a_i \le n$? The penalty is small: $k(a_i \mid a_j) < 2kn$, while $i\cdot j$ ranges up to $n(n-1)$. Heuristic 6: bound what the optimum can be. The pair $(n-1, n)$ already scores more than $n(n-1) - 2kn$. Any pair with $i \le n - 2k - 1$ scores at most $i \cdot j \le (n - 2k - 1)\,n = n(n-1) - 2kn$. So the optimum uses only indices $\ge n - 2k$: check those $O(k^2)$ pairs.

<details><summary>Solution</summary>

For each test case enumerate $i$ from $\max(1, n - 2k - 1)$ to $n$ and $j > i$; $O(k^2) \le 4\cdot10^4$ pairs per test, and the number of tests with large $k$ is bounded by $\sum n$. The bound in the comment of the code is exactly the argument above; $a_i \mid a_j \le 2n - 1$ because both values are at most $n$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int t;
    cin >> t;
    while (t--) {
        int n;
        ll k;
        cin >> n >> k;
        vector<ll> a(n + 1);
        for (int i = 1; i <= n; i++) cin >> a[i];
        // The pair (n-1, n) scores > n(n-1) - 2kn, while any pair with i < n - 2k scores
        // at most i*j <= (n-2k-1)*n = n(n-1) - 2kn. So only the last ~2k indices matter.
        int from = max(1LL, (ll)n - 2 * k - 1);
        ll best = LLONG_MIN;
        for (int i = from; i <= n; i++)
            for (int j = i + 1; j <= n; j++)
                best = max(best, (ll)i * j - k * (a[i] | a[j]));
        cout << best << '\n';
    }
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int t = (int) readLong(in);
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            int n = (int) readLong(in);
            long k = readLong(in);
            long[] a = new long[n + 1];
            for (int i = 1; i <= n; i++) a[i] = readLong(in);
            int from = (int) Math.max(1, n - 2 * k - 1);
            long best = Long.MIN_VALUE;
            for (int i = from; i <= n; i++)
                for (int j = i + 1; j <= n; j++)
                    best = Math.max(best, (long) i * j - k * (a[i] | a[j]));
            sb.append(best).append('\n');
        }
        System.out.print(sb);
    }

    static long readLong(DataInputStream in) throws IOException {
        int c = in.read();
        while (c != '-' && (c < '0' || c > '9')) c = in.read();
        boolean neg = c == '-';
        if (neg) c = in.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = in.read(); }
        return neg ? -r : r;
    }
}
```

</details>

<!-- test
in:
2
3 1
1 1 3
2 2
0 0
out:
3
2
-->
<!-- test
in:
1
4 3
0 1 2 3
out:
3
-->

### Example 4 — The last operation: bursting balloons  ·  ★ ≈2000 (est.)

- **Source:** [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard
- **Difficulty:** ≈2000 (est.)
- **Problem:** Values $v_1..v_n$ ($n \le 300$, $0 \le v_i \le 100$). Bursting balloon $i$ earns $v_{\text{left}}\cdot v_i\cdot v_{\text{right}}$, where left/right are its current neighbours (missing neighbours count as 1). Maximise the total over an order that bursts all balloons.
- **Thinking from first principles:** The natural DP "which balloon do I burst first?" fails: after the first burst, the two sides become adjacent and the subproblems are not independent. Heuristic 3: look at the **last** balloon $k$ burst inside an interval. While the balloons to its left and right are being burst, $k$ is still there, so it separates them: the left part only ever sees $k$ (and the interval's left border) as its right neighbour. When $k$ is finally burst, its neighbours are the interval's borders. Independence restored.

<details><summary>Solution</summary>

Add sentinels $v_0 = v_{n+1} = 1$. $dp[l][r]$ = maximum coins for bursting every balloon strictly between $l$ and $r$ while $l$ and $r$ stay. $dp[l][r] = \max_{l<k<r} dp[l][k] + dp[k][r] + v_l v_k v_r$, by increasing interval length; answer $dp[0][n+1]$. $O(n^3)$ ($2.7\cdot10^7$ for $n = 300$). Stress-tested against trying every burst order for $n \le 7$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<long long> v(n + 2, 1);                 // sentinels v[0] = v[n+1] = 1
    for (int i = 1; i <= n; i++) cin >> v[i];
    // dp[l][r] = best coins from bursting every balloon strictly between l and r,
    // where l and r are still present. Think about the LAST balloon k burst in (l, r):
    // its neighbours at that moment are exactly l and r.
    vector<vector<long long>> dp(n + 2, vector<long long>(n + 2, 0));
    for (int len = 2; len <= n + 1; len++)
        for (int l = 0; l + len <= n + 1; l++) {
            int r = l + len;
            for (int k = l + 1; k < r; k++)
                dp[l][r] = max(dp[l][r], dp[l][k] + dp[k][r] + v[l] * v[k] * v[r]);
        }
    cout << dp[0][n + 1] << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken();
        int n = (int) st.nval;
        long[] v = new long[n + 2];
        v[0] = 1; v[n + 1] = 1;
        for (int i = 1; i <= n; i++) { st.nextToken(); v[i] = (long) st.nval; }
        long[][] dp = new long[n + 2][n + 2];
        for (int len = 2; len <= n + 1; len++)
            for (int l = 0; l + len <= n + 1; l++) {
                int r = l + len;
                long best = 0;
                for (int k = l + 1; k < r; k++) best = Math.max(best, dp[l][k] + dp[k][r] + v[l] * v[k] * v[r]);
                dp[l][r] = best;
            }
        System.out.println(dp[0][n + 1]);
    }
}
```

</details>

<!-- test
in:
3
2 4 3
out:
33
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
0 5
out:
5
-->

### Example 5 — Invariants and canonical form: magic stones  ·  ★ 2200

- **Source:** [CF 1110E · Magic Stones](https://codeforces.com/problemset/problem/1110/E) — 2200
- **Difficulty:** 2200
- **Problem:** Arrays $c$ and $t$ of length $n \le 10^5$ (values up to $2\cdot10^9$). An operation picks an inner index $2 \le i \le n-1$ and replaces $c_i$ by $c_{i-1} + c_{i+1} - c_i$. Can $c$ be turned into $t$?
- **Thinking from first principles:** Simulation is hopeless (infinitely many sequences). Heuristic 7: what does the operation preserve? Obviously $c_1$ and $c_n$. Heuristic 1: the operation is linear and local — look at differences $d_j = c_{j+1} - c_j$. Before: $d_{i-1} = c_i - c_{i-1}$, $d_i = c_{i+1} - c_i$. After: $c_i' - c_{i-1} = c_{i+1} - c_i = d_i$ and $c_{i+1} - c_i' = c_i - c_{i-1} = d_{i-1}$. **The operation swaps two adjacent differences.** So the invariants are $c_1$ and the multiset of differences, and since adjacent swaps generate all permutations, those invariants are also sufficient.

<details><summary>Solution</summary>

Answer "Yes" iff $c_1 = t_1$ and the sorted difference arrays are equal ($c_n = t_n$ then follows, because the differences sum to $c_n - c_1$). Sufficiency: any permutation of the differences is a product of adjacent swaps, each realised by one operation, and an array is determined by its first element and its difference sequence. $O(n\log n)$; use 64-bit values (differences reach $\pm 2\cdot10^9$). Stress-tested against a BFS over all reachable arrays for $n \le 6$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<ll> c(n), t(n);
    for (auto& x : c) cin >> x;
    for (auto& x : t) cin >> x;
    // c_i -> c_{i-1} + c_{i+1} - c_i swaps the adjacent differences d_{i-1}, d_i (d_j = c_{j+1} - c_j).
    // Invariants: c_1 and the multiset of differences. Adjacent swaps reach every permutation.
    vector<ll> dc, dt;
    for (int i = 0; i + 1 < n; i++) { dc.push_back(c[i + 1] - c[i]); dt.push_back(t[i + 1] - t[i]); }
    sort(dc.begin(), dc.end());
    sort(dt.begin(), dt.end());
    cout << (c[0] == t[0] && dc == dt ? "Yes" : "No") << '\n';
}
```

```java
import java.io.*;
import java.util.*;

public class Main {
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) readLong(in);
        long[] c = new long[n], t = new long[n];
        for (int i = 0; i < n; i++) c[i] = readLong(in);
        for (int i = 0; i < n; i++) t[i] = readLong(in);
        long[] dc = new long[n - 1], dt = new long[n - 1];
        for (int i = 0; i + 1 < n; i++) { dc[i] = c[i + 1] - c[i]; dt[i] = t[i + 1] - t[i]; }
        shuffleSort(dc);
        shuffleSort(dt);
        System.out.println(c[0] == t[0] && Arrays.equals(dc, dt) ? "Yes" : "No");
    }

    static void shuffleSort(long[] a) {             // shuffle first: Arrays.sort(long[]) is a quicksort
        SplittableRandom r = new SplittableRandom(System.nanoTime());
        for (int i = a.length - 1; i > 0; i--) { int j = r.nextInt(i + 1); long x = a[i]; a[i] = a[j]; a[j] = x; }
        Arrays.sort(a);
    }

    static long readLong(DataInputStream in) throws IOException {
        int c = in.read();
        while (c != '-' && (c < '0' || c > '9')) c = in.read();
        boolean neg = c == '-';
        if (neg) c = in.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = in.read(); }
        return neg ? -r : r;
    }
}
```

</details>

<!-- test
in:
3
1 3 2
1 0 2
out:
Yes
-->
<!-- test
in:
2
5 5
5 6
out:
No
-->
<!-- test
in:
4
0 0 0 0
0 0 0 0
out:
Yes
-->
<!-- test
in:
4
2000000000 0 0 2000000000
2000000000 2000000000 0 2000000000
out:
Yes
-->

## 6. Tricks, pitfalls and things to remember

1. **Fixating on the first idea.** If an approach has not produced progress in 15–20 minutes, deliberately switch heuristic. Write down why the first idea fails — that sentence is often the observation you need.
2. **Not writing the brute force.** It costs 5 minutes and pays three times: small cases to look at, a check of your understanding of the statement, and a stress-test oracle.
3. **Trusting a pattern without proof or stress test.** Patterns from $n \le 10$ can break at $n = 30$ (powers of two, primes, periods that start late). Stress-test up to the largest $n$ the brute force allows.
4. **Ignoring the constraints.** The strange limit is usually the hint (Example 3). Read every number in the input section and ask why it is there.
5. **Reading the editorial too early** (nothing sticks) **or too late** (hours spent with no new idea). Use the one-hint-at-a-time rule.
6. **Reading without implementing.** An idea you have not coded from scratch tends to fail under contest pressure.
7. **Practising only comfortable problems.** It feels productive and changes little; schedule most problems in the +200 to +500 band.
8. **Skipping upsolving after bad rounds** — the rounds that went badly contain exactly the problems worth upsolving.
9. **Implementing before the solution is complete.** At 2300+, code written for a half-finished idea is usually rewritten. Finish the argument (including complexity and edge cases) first.
10. **Over-generalising.** Solve the problem in front of you; the general version is often much harder (heuristic 8 works in the other direction too).

## 7. Going further (toward 2400–2600+)

- **Build a personal catalogue of reductions.** After a few hundred journal entries, group them by trigger ("operation on three consecutive elements", "sum over all subarrays", "parity of permutations"). Rereading by trigger is the fastest way to turn individual problems into recognisable patterns.
- **Learn proof techniques deliberately:** exchange arguments, potential functions, extremal principle, double counting, induction on structure. Each heuristic above is backed by one of them; see [greedy and exchange arguments](../03-Greedy-Constructive-Interactive/01-greedy-and-exchange-arguments.md) and [constructive algorithms](../03-Greedy-Constructive-Interactive/03-constructive-algorithms.md).
- **Study problem sets built around ideas** rather than algorithms: AtCoder ARC and AGC rounds are a common recommendation for observation-heavy training; Codeforces Div 1 C–E for the 2400–2800 range.
- **Track transfer:** when a journal idea solves a new problem, note it. Ideas that never transfer were probably filed too specifically.
- **Pair heuristics with techniques** in this folder: "monotone predicate over time" → [parallel binary search](01-offline-techniques-cdq-parallel-binary-search.md); "deletions" → [segment tree on time](02-segment-tree-on-time-and-dsu-rollback.md); "equal multisets" → [hashing](04-randomized-algorithms-and-hashing.md); "two regimes" → [square-root split](06-advanced-sqrt-techniques.md).

## 8. Practice ladder

Each problem's key step is one of the heuristics above (named in the hint).

1600–1900
- [ ] [CF 1458A · Row GCD](https://codeforces.com/problemset/problem/1458/A) — 1600 — canonical form via differences
- [ ] [CF 1336A · Linova and Kingdom](https://codeforces.com/problemset/problem/1336/A) — 1600 — contribution per vertex
- [ ] [CF 722C · Destroying Array](https://codeforces.com/problemset/problem/722/C) — 1600 — reverse time
- [ ] [CF 1537D · Deleting Divisors](https://codeforces.com/problemset/problem/1537/D) — 1700 — Example 2
- [ ] [CF 1554B · Cobb](https://codeforces.com/problemset/problem/1554/B) — 1700 — Example 3
- [ ] [CF 1225D · Power Products](https://codeforces.com/problemset/problem/1225/D) — 1800 — canonical form of exponents
- [ ] [CF 1500A · Going Home](https://codeforces.com/problemset/problem/1500/A) — 1800 — pigeonhole bounds the search
- [ ] [CF 1470B · Strange Definition](https://codeforces.com/problemset/problem/1470/B) — 1900 — canonical form (square-free part)

2000–2300
- [ ] [CF 1009E · Intercity Travelling](https://codeforces.com/problemset/problem/1009/E) — 2000 — contribution
- [ ] [CF 1338C · Perfect Triples](https://codeforces.com/problemset/problem/1338/C) — 2200 — brute force, find the pattern
- [ ] [CF 1110E · Magic Stones](https://codeforces.com/problemset/problem/1110/E) — 2200 — Example 5
- [ ] [CF 280C · Game on Tree](https://codeforces.com/problemset/problem/280/C) — 2200 — contribution via linearity of expectation
- [ ] [CF 1167F · Scalar Queries](https://codeforces.com/problemset/problem/1167/F) — 2300 — contribution with a data structure
- [ ] [CF 1188B · Count Pairs](https://codeforces.com/problemset/problem/1188/B) — 2300 — algebraic canonical form

2400+
- [ ] [CF 1392F · Omkar and Landslide](https://codeforces.com/problemset/problem/1392/F) — 2400 — think about the final state
- [ ] [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400 — make choices reversible

## 9. LeetCode / FAANG cross-reference

- [LC 2104 · Sum of Subarray Ranges](https://leetcode.com/problems/sum-of-subarray-ranges/) — Medium — Example 1.
- [LC 907 · Sum of Subarray Minimums](https://leetcode.com/problems/sum-of-subarray-minimums/) — Medium — half of Example 1.
- [LC 828 · Count Unique Characters of All Substrings of a Given String](https://leetcode.com/problems/count-unique-characters-of-all-substrings-of-a-given-string/) — Hard — contribution of each occurrence.
- [LC 2262 · Total Appeal of A String](https://leetcode.com/problems/total-appeal-of-a-string/) — Hard — contribution of the first occurrence in each substring.
- [LC 891 · Sum of Subsequence Widths](https://leetcode.com/problems/sum-of-subsequence-widths/) — Hard — sort, then contribution as max and as min.
- [LC 312 · Burst Balloons](https://leetcode.com/problems/burst-balloons/) — Hard — Example 4.
- [LC 1503 · Last Moment Before All Ants Fall Out of a Plank](https://leetcode.com/problems/last-moment-before-all-ants-fall-out-of-a-plank/) — Medium — canonical form: bouncing ants pass through.
- [LC 2731 · Movement of Robots](https://leetcode.com/problems/movement-of-robots/) — Medium — the same pass-through argument, then sort.
- [LC 780 · Reaching Points](https://leetcode.com/problems/reaching-points/) — Hard — work backwards, the predecessor is unique.
- [LC 991 · Broken Calculator](https://leetcode.com/problems/broken-calculator/) — Medium — reverse the operations to make greedy optimal.
- [LC 1025 · Divisor Game](https://leetcode.com/problems/divisor-game/) — Easy — brute force shows parity decides it.
- [LC 877 · Stone Game](https://leetcode.com/problems/stone-game/) — Medium — the first player can always take all even or all odd positions.
- [LC 292 · Nim Game](https://leetcode.com/problems/nim-game/) — Easy — losing positions are multiples of 4.

In interviews these heuristics are exactly what "aha" questions test; saying the heuristic out loud ("let me think about which balloon goes last") is also good communication.

## 10. Self-check

1. Name the question that each of heuristics 1, 3, 7 and 10 makes you ask.
2. Why does "which balloon bursts first" fail while "which bursts last" works?
3. In Example 3, prove that pairs with $i \le n - 2k - 1$ can never be optimal.
4. In Example 5, show that the operation swaps adjacent differences, and explain why the invariants are also sufficient.
5. What four things should an idea-journal entry contain, and which field is most useful later?
6. Why is it a mistake to read an editorial after 5 minutes, and why is it also a mistake after 5 hours?
7. What is the purpose of virtual contests if you already practise problems every day?
8. Give the contribution formula for the sum of subarray maxima, including the tie rule.

<details><summary>Answers</summary>

1. Canonical form: which inputs are equivalent and what is the simplest representative? Extremal/last: what is true about the max/min/last operation? Invariants: what does the operation never change? Constraints: why is this limit here, and what complexity does it allow?
2. After the first burst, the two sides become adjacent and interact. The last balloon in an interval stays until the end, so the two sides never interact and are independent subproblems.
3. Such pairs score at most $i\cdot j \le (n-2k-1)n = n(n-1) - 2kn$, while $(n-1, n)$ scores at least $n(n-1) - k(2n-1) > n(n-1) - 2kn$.
4. New differences around $i$ are $(c_{i+1} - c_i, c_i - c_{i-1}) = (d_i, d_{i-1})$. Adjacent swaps generate every permutation, and $c$ is determined by $c_1$ and its differences, so equal invariants imply reachability.
5. Trigger, key idea, why you missed it, related problems (plus review dates). "Why I missed it" reveals which heuristic you under-use.
6. After 5 minutes the key step is not surprising, so it is not remembered; after 5 hours with no new idea, the time would have been better spent on another problem plus the editorial.
7. They train contest skills — selection, timing, debugging under pressure — that untimed practice does not.
8. $\sum_i a_i (i - L_i)(R_i - i)$ with $L_i$ the nearest index to the left with $a \ge a_i$ and $R_i$ the nearest to the right with $a > a_i$ (or the mirror choice), so each subarray credits exactly one maximum.

</details>
