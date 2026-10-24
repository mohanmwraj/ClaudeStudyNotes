# Slope Trick

> **Band:** 🟠 2200–2500 (tree merging and 2-D variants 🔴) · **Priority:** ⚡ · **FAANG:** low · **Prerequisites:** [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md), [heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md), [greedy with heaps and regret](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md)
> **You can say you know this when:** you can look at a DP over a *value* coordinate, $dp_i(x)$, prove it is convex piecewise linear, and maintain it with two heaps under "add $|x-a|$", "prefix/suffix minimum" and "sliding-window minimum", reading off the minimum and an optimal solution in $O(n \log n)$.

## 1. First principles — why this works

### 1.1 The motivating DP

"Change an array into a non-decreasing one, minimising $\sum |a_i - b_i|$." Let $dp_i(x)$ = minimal cost of the first $i$ elements with $b_i = x$:

$$dp_i(x) = |x - a_i| + \min_{y \le x} dp_{i-1}(y).$$

Tabulating $x$ over all values is $O(nV)$; over the distinct values of $a$ (an optimal $b$ only uses values of $a$) it is $O(n^2)$ — the classic solution to [CF 13C · Sequence](https://codeforces.com/problemset/problem/13/C) — 2200. For $n = 2\cdot10^5$ we need something else: we must stop storing $dp_i$ as a table and store it as a **shape**.

### 1.2 The shape is convex piecewise linear with integer slopes

- $|x - a|$ is convex, piecewise linear, slopes $-1, +1$.
- The **prefix minimum** $x \mapsto \min_{y \le x} g(y)$ of a convex $g$ is convex: it equals $g$ left of the minimiser and is constant afterwards.
- A sum of convex piecewise-linear functions with integer slopes is again one.

By induction every $dp_i$ is convex piecewise linear with integer slopes. Such a function is determined by its minimum value and by **where its slope changes, and by how much**. Since slopes are integers, record each slope change of $+c$ as $c$ copies of the breakpoint.

### 1.3 The representation

$$f(x) = \mathrm{minF} + \sum_{l \in L} \max(0,\, l - x) + \sum_{r \in R} \max(0,\, x - r), \qquad \max L \le \min R.$$

- $L$ (a max-heap) holds the breakpoints left of the flat bottom: just left of $\max L$ the slope is $-1$, then $-2$, … Each element contributes a "$\backslash$" kink.
- $R$ (a min-heap) holds the breakpoints right of the bottom, each contributing a "$/$" kink.
- $f$ is minimal, with value $\mathrm{minF}$, on the whole interval $[\max L, \min R]$.

Every convex piecewise-linear function with integer slopes and a finite minimum has exactly this form. The heaps only ever expose $\max L$ and $\min R$ — which is all the operations below need.

### 1.4 The operations and why each is correct

Let $l_0 = \max L$, $r_0 = \min R$ ($-\infty$/$+\infty$ if empty).

1. **Add a constant $c$**: $\mathrm{minF} \mathrel{+}= c$.
2. **Add $\max(0, x - a)$** (a "$/$" kink at $a$).
   - If $a \ge l_0$: on $[l_0, \min(a, r_0)]$ the new term is 0, so the minimum value is unchanged; $a$ is a right-side breakpoint → it goes to $R$.
   - If $a < l_0$: the slope just left of $l_0$ was $-1$ and becomes $0$, so the new flat bottom ends at $l_0$, and its value is $f(l_0) + (l_0 - a) = \mathrm{minF} + l_0 - a$. The point $l_0$ is now where the slope goes $0 \to +1$, so it moves to $R$; $a$ joins $L$.
   - Both cases are the same code: `minF += max(0, l0 - a); L.push(a); R.push(L.pop_max());`
3. **Add $\max(0, a - x)$**: the mirror image — `minF += max(0, a - r0); R.push(a); L.push(R.pop_min());`
4. **Add $|x - a|$** = both of the above (two kinks at $a$, slope change $+2$).
5. **Prefix minimum** $g(x) = \min_{y \le x} f(y)$: everything right of the bottom becomes flat — **clear $R$**. Suffix minimum: clear $L$.
6. **Sliding-window minimum** $g(x) = \min_{x - b \le y \le x - a} f(y)$ with $a \le b$. If the window contains a minimiser, $g(x) = \mathrm{minF}$. If the window lies left of the bottom ($x - a \le l_0$), the best $y$ is its right end: $g(x) = f(x - a)$ — the left part shifted right by $a$. If it lies right of the bottom ($x - b \ge r_0$), $g(x) = f(x - b)$ — the right part shifted by $b$. So: **add $a$ to every element of $L$, add $b$ to every element of $R$**. Store a lazy offset per heap (`addL`, `addR`).
7. **Shift** $g(x) = f(x - a)$: the window with $a = b$.
8. **Evaluate $f(x_0)$**: $O(|L| + |R|)$ from the formula; usually done once at the end.

Each operation is $O(\log n)$; a DP of $n$ steps is $O(n \log n)$.

### 1.5 Why the 13C loop is so short

For the non-decreasing problem, the step is "prefix minimum, then add $|x - a_i|$". After a prefix minimum $R$ is empty, so adding $\max(0, a - x)$ just pushes $a$ into $L$; adding $\max(0, x - a)$ then raises the minimum by $\max(0, l_0 - a)$ and moves $l_0$ to $R$ — which the next prefix minimum discards. Net effect:

```text
push a into L
if top(L) > a:  answer += top(L) - a;  pop L;  push a into L
```

**Reconstruction.** Record $opt_i = \max L$ after step $i$ (a minimiser of $dp_i$). Then $b_n = opt_n$ and $b_i = \min(b_{i+1}, opt_i)$: among $x \le b_{i+1}$ the convex $dp_i$ is minimised at $\min(b_{i+1}, opt_i)$.

### 1.6 The same idea, concave side up

Maximisation DPs whose value function is **concave** in the coordinate (profit as a function of shares held, of items kept, …) are the negation of the above. The famous one-heap greedy for [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400 is exactly a slope-trick DP over "number of shares held" (Example 4).

## 2. Formulas, definitions and identities

| Name | Formula / rule | Cost |
|---|---|---|
| Representation | $f(x) = \mathrm{minF} + \sum_{l\in L}(l-x)^+ + \sum_{r\in R}(x-r)^+$, $\max L \le \min R$ | — |
| Slope at $x$ | $\#\{r \in R : r < x\} - \#\{l \in L : l > x\}$ | — |
| Minimiser set | $[\max L, \min R]$ | $O(1)$ |
| $f \mathrel{+}= c$ | $\mathrm{minF} \mathrel{+}= c$ | $O(1)$ |
| $f \mathrel{+}= (x-a)^+$ | $\mathrm{minF} \mathrel{+}= (\max L - a)^+$; push $a$ to $L$; move $\max L$ to $R$ | $O(\log n)$ |
| $f \mathrel{+}= (a-x)^+$ | $\mathrm{minF} \mathrel{+}= (a - \min R)^+$; push $a$ to $R$; move $\min R$ to $L$ | $O(\log n)$ |
| $f \mathrel{+}= \lvert x-a\rvert$ | both of the above | $O(\log n)$ |
| $f \mathrel{+}= w \lvert x - a\rvert$ | push $a$ with multiplicity $w$ (use a `map` of counts when $w$ is large) | $O(\log n)$ per distinct point |
| prefix min $\min_{y\le x}$ | clear $R$ | $O(1)$ (lazy) |
| suffix min $\min_{y\ge x}$ | clear $L$ | $O(1)$ |
| window min $\min_{y\in[x-b,\,x-a]}$, $a\le b$ | `addL += a`, `addR += b` | $O(1)$ |
| shift $f(x-a)$ | `addL += a`, `addR += a` | $O(1)$ |
| evaluate $f(x_0)$ | formula | $O(\lvert L\rvert + \lvert R\rvert)$ |
| strictly increasing $b$ | replace $a_i$ by $a_i - i$ | — |
| $\min_x \sum_i \lvert x - a_i\rvert$ | any median | the one-step special case |

## 3. Implementation (C++ and Java)

A complete structure with all operations, plus a driver used for stress testing. Commands: `1 a` add $|x-a|$, `2 a` add $(x-a)^+$, `3 a` add $(a-x)^+$, `4` prefix min, `5` suffix min, `6 a b` window min over $[x-b, x-a]$, `7 c` add $c$, `8` print the minimum. Checked against a brute force that tabulates $f$ on an integer grid.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

// Convex piecewise-linear f(x) = minF + sum_{l in L} max(0, l - x) + sum_{r in R} max(0, x - r),
// with max(L) <= min(R).  Heaps store values minus a lazy shift.
struct SlopeTrick {
    static constexpr ll INF = LLONG_MAX / 4;
    ll minF = 0, addL = 0, addR = 0;
    priority_queue<ll> L;                                   // left breakpoints (slope -|L| .. 0)
    priority_queue<ll, vector<ll>, greater<ll>> R;          // right breakpoints (slope 0 .. |R|)
    ll topL() const { return L.empty() ? -INF : L.top() + addL; }
    ll topR() const { return R.empty() ? INF : R.top() + addR; }
    void pushL(ll a) { L.push(a - addL); }
    void pushR(ll a) { R.push(a - addR); }
    ll popL() { ll v = topL(); L.pop(); return v; }
    ll popR() { ll v = topR(); R.pop(); return v; }

    void addConst(ll c) { minF += c; }
    void addXminusA(ll a) { minF += max(0LL, topL() - a); pushL(a); pushR(popL()); }   // += max(0, x - a)
    void addAminusX(ll a) { minF += max(0LL, a - topR()); pushR(a); pushL(popR()); }   // += max(0, a - x)
    void addAbs(ll a) { addXminusA(a); addAminusX(a); }                                 // += |x - a|
    void prefixMin() { R = {}; }                            // f(x) <- min_{y <= x} f(y)
    void suffixMin() { L = {}; }                            // f(x) <- min_{y >= x} f(y)
    void slide(ll a, ll b) { addL += a; addR += b; }        // f(x) <- min_{x-b <= y <= x-a} f(y), a <= b
    void shift(ll a) { slide(a, a); }                       // f(x) <- f(x - a)
    ll minimum() const { return minF; }                     // attained on [topL(), topR()]
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q;
    cin >> q;
    SlopeTrick st;
    string out;
    while (q--) {
        int t; cin >> t;
        ll a, b;
        if (t == 1) { cin >> a; st.addAbs(a); }
        else if (t == 2) { cin >> a; st.addXminusA(a); }
        else if (t == 3) { cin >> a; st.addAminusX(a); }
        else if (t == 4) st.prefixMin();
        else if (t == 5) st.suffixMin();
        else if (t == 6) { cin >> a >> b; st.slide(a, b); }
        else if (t == 7) { cin >> a; st.addConst(a); }
        else { out += to_string(st.minimum()); out += '\n'; }
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    // Same representation as the C++ version; PriorityQueue<Long> is fine for 2e5 operations.
    static class SlopeTrick {
        static final long INF = Long.MAX_VALUE / 4;
        long minF = 0, addL = 0, addR = 0;
        PriorityQueue<Long> L = new PriorityQueue<>(Collections.reverseOrder());
        PriorityQueue<Long> R = new PriorityQueue<>();
        long topL() { return L.isEmpty() ? -INF : L.peek() + addL; }
        long topR() { return R.isEmpty() ? INF : R.peek() + addR; }
        void pushL(long a) { L.add(a - addL); }
        void pushR(long a) { R.add(a - addR); }
        long popL() { long v = topL(); L.poll(); return v; }
        long popR() { long v = topR(); R.poll(); return v; }

        void addConst(long c) { minF += c; }
        void addXminusA(long a) { minF += Math.max(0, topL() - a); pushL(a); pushR(popL()); }
        void addAminusX(long a) { minF += Math.max(0, a - topR()); pushR(a); pushL(popR()); }
        void addAbs(long a) { addXminusA(a); addAminusX(a); }
        void prefixMin() { R.clear(); }
        void suffixMin() { L.clear(); }
        void slide(long a, long b) { addL += a; addR += b; }
        void shift(long a) { slide(a, a); }
        long minimum() { return minF; }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int q = in.nextInt();
        SlopeTrick st = new SlopeTrick();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int t = in.nextInt();
            if (t == 1) st.addAbs(in.nextLong());
            else if (t == 2) st.addXminusA(in.nextLong());
            else if (t == 3) st.addAminusX(in.nextLong());
            else if (t == 4) st.prefixMin();
            else if (t == 5) st.suffixMin();
            else if (t == 6) { long a = in.nextLong(), b = in.nextLong(); st.slide(a, b); }
            else if (t == 7) st.addConst(in.nextLong());
            else sb.append(st.minimum()).append('\n');
        }
        out.print(sb);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
6
1 3
1 7
8
6 -2 2
1 0
8
out:
4
5
-->
<!-- test
in:
9
2 5
3 -4
8
4
1 10
8
5
1 -6
8
out:
0
0
0
-->
<!-- test
in:
3
1 1000000000
1 -1000000000
8
out:
2000000000
-->

The first test by hand: $|x-3| + |x-7|$ has minimum 4 on $[3,7]$; the window $[x-2, x+2]$ widens the bottom to $[1, 9]$; adding $|x|$ gives $4 + 1 = 5$ at $x = 1$.

**Reconstruction for the non-decreasing problem** (§1.5), as functions:

```cpp
// Minimal sum |a_i - b_i| over non-decreasing b; also returns one optimal b.
ll makeNonDecreasing(const vector<ll>& a, vector<ll>& b) {
    int n = a.size();
    priority_queue<ll> L;
    vector<ll> opt(n);
    ll cost = 0;
    for (int i = 0; i < n; i++) {
        L.push(a[i]);
        if (L.top() > a[i]) { cost += L.top() - a[i]; L.pop(); L.push(a[i]); }
        opt[i] = L.top();                      // left end of the argmin interval of dp_i
    }
    b.assign(n, 0);
    b[n - 1] = opt[n - 1];
    for (int i = n - 2; i >= 0; i--) b[i] = min(b[i + 1], opt[i]);   // best x <= b[i+1] for convex dp_i
    return cost;
}
```

```java
// Minimal sum |a_i - b_i| over non-decreasing b; b receives one optimal sequence.
static long makeNonDecreasing(long[] a, long[] b) {
    int n = a.length;
    PriorityQueue<Long> L = new PriorityQueue<>(Collections.reverseOrder());
    long[] opt = new long[n];
    long cost = 0;
    for (int i = 0; i < n; i++) {
        L.add(a[i]);
        if (L.peek() > a[i]) { cost += L.poll() - a[i]; L.add(a[i]); }
        opt[i] = L.peek();
    }
    b[n - 1] = opt[n - 1];
    for (int i = n - 2; i >= 0; i--) b[i] = Math.min(b[i + 1], opt[i]);
    return cost;
}
```

Both were stress-tested: the returned $b$ is non-decreasing and $\sum |a_i - b_i|$ equals the returned cost, which equals the $O(n^2)$ DP.

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| DP over a **value** coordinate $x$ (the new value of an element, a position, a count held) with costs like $\lvert x - a\rvert$, $(x - a)^+$ | slope trick candidate |
| transitions "$\min_{y \le x}$", "$\min_{y \ge x}$", "$\min_{\lvert y - x\rvert \le d}$", "$\min_{y \in [x - b, x - a]}$" | prefix / suffix / window minimum — all $O(1)$ on the representation |
| "make the array non-decreasing / strictly increasing / with differences in $[a, b]$ at minimum total change" | slope trick (strict: subtract $i$) |
| "each step you may move by at most $d$, pay distance to targets" | window minimum + add $\lvert x - a\rvert$ |
| a greedy with one priority queue and a "push it back" step that you cannot justify | it is often a slope-trick DP in disguise (Example 4) |

**It fails when** the transition is $\max_y$ of a convex function, or when costs are not convex (e.g. $\min(\lvert x-a\rvert, c)$ capped costs). Then the function is no longer convex and two heaps cannot represent it.

**Confused with:** the [convex hull trick](02-convex-hull-trick-and-li-chao-tree.md) (that optimises over a *set of lines* for each $i$; here we keep *one convex function* of $x$ and edit it) and [Aliens](06-aliens-trick-wqs-binary-search.md) (which uses convexity in the *count* $k$, not in a value coordinate).

## 5. Worked examples (graded)

### Example 1 — Absolute Minima  ·  ★ ≈2003 (AtCoder estimate)

- **Source:** [AtCoder ABC127 F · Absolute Minima](https://atcoder.jp/contests/abc127/tasks/abc127_f)
- **Difficulty:** ≈2003 (AtCoder estimate)
- **Problem:** start with $f(x) = 0$. Process $Q \le 2\cdot10^5$ queries: `1 a b` sets $f(x) \leftarrow f(x) + |x - a| + b$; `2` asks for the smallest $x$ minimising $f$ and the minimum value. $|a|, |b| \le 10^9$; the first query is an update.
- **Thinking from first principles:** $f$ is always $\sum |x - a_j| + \sum b_j$ — the minimiser is a median of the $a_j$ and the minimum is the sum of distances to it. Maintaining a running median with two heaps is a known trick; the slope-trick view explains *why* two heaps and gives the minimum value for free: each update is "add $|x - a|$" plus a constant, and the smallest minimiser is $\max L$.

<details><summary>Solution</summary>

Exactly the operations 2–4 of §1.4. The minimum can reach $2\cdot10^5 \cdot 2\cdot10^9$ — use 64-bit. Time $O(Q \log Q)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q;
    cin >> q;
    priority_queue<ll> L;                                   // breakpoints left of the minimum
    priority_queue<ll, vector<ll>, greater<ll>> R;          // breakpoints right of the minimum
    ll minF = 0;
    string out;
    while (q--) {
        int t; cin >> t;
        if (t == 1) {
            ll a, b; cin >> a >> b;
            minF += b;
            // add max(0, x - a): minimum rises by max(0, topL - a)
            if (!L.empty() && L.top() > a) minF += L.top() - a;
            L.push(a); R.push(L.top()); L.pop();
            // add max(0, a - x): minimum rises by max(0, a - topR)
            if (R.top() < a) minF += a - R.top();
            R.push(a); L.push(R.top()); R.pop();
        } else {
            out += to_string(L.top()) + ' ' + to_string(minF) + '\n';   // smallest minimiser = top of L
        }
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int q = in.nextInt();
        PriorityQueue<Long> L = new PriorityQueue<>(Collections.reverseOrder());
        PriorityQueue<Long> R = new PriorityQueue<>();
        long minF = 0;
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int t = in.nextInt();
            if (t == 1) {
                long a = in.nextLong(), b = in.nextLong();
                minF += b;
                if (!L.isEmpty() && L.peek() > a) minF += L.peek() - a;
                L.add(a); R.add(L.poll());
                if (R.peek() < a) minF += a - R.peek();
                R.add(a); L.add(R.poll());
            } else {
                sb.append(L.peek()).append(' ').append(minF).append('\n');
            }
        }
        out.print(sb);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
4
1 4 2
2
1 1 -8
2
out:
4 2
1 -3
-->
<!-- test
in:
4
1 -1000000000 1000000000
1 -1000000000 1000000000
1 -1000000000 1000000000
2
out:
-1000000000 3000000000
-->
<!-- test
in:
5
1 3 0
1 1 0
2
1 2 5
2
out:
1 2
2 7
-->

</details>

### Example 2 — Sequence (non-decreasing, minimum total change)  ·  ★ 2200

- **Source:** [CF 13C · Sequence](https://codeforces.com/problemset/problem/13/C) — 2200
- **Difficulty:** 2200
- **Problem:** $n \le 5000$ integers with $|a_i| \le 10^9$. In one step you add or subtract 1 from an element. Minimum number of steps to make the sequence non-decreasing.
- **Thinking from first principles:** this is §1.1. The $O(n^2)$ DP over distinct values passes here, but the slope-trick loop of §1.5 is shorter, $O(n \log n)$, and scales to $n = 10^6$.

<details><summary>Solution</summary>

Correctness is §1.4 (operations 3, 2, 5 in that order each step) and §1.5. The answer can be about $n \cdot 2\cdot10^9 = 10^{13}$: 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n;
    cin >> n;
    priority_queue<ll> L;          // left breakpoints of dp_i; after the prefix-min step R is always empty
    ll ans = 0;
    for (int i = 0; i < n; i++) {
        ll a; cin >> a;
        L.push(a);                 // (a - x)^+ part of |x - a|: lands in L because R is empty
        if (L.top() > a) {         // (x - a)^+ part: raises the minimum by top - a
            ans += L.top() - a;
            L.pop();               // that breakpoint moves to R ...
            L.push(a);
        }                          // ... and R is discarded by the next prefix-min
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        PriorityQueue<Long> L = new PriorityQueue<>(Collections.reverseOrder());
        long ans = 0;
        for (int i = 0; i < n; i++) {
            long a = in.nextLong();
            L.add(a);
            if (L.peek() > a) {
                ans += L.poll() - a;
                L.add(a);
            }
        }
        out.println(ans);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
5
3 2 -1 2 11
out:
4
-->
<!-- test
in:
5
2 1 1 1 1
out:
1
-->
<!-- test
in:
1
-1000000000
out:
0
-->
<!-- test
in:
4
1000000000 -1000000000 1000000000 -1000000000
out:
4000000000
-->

</details>

### Example 3 — Strictly increasing  ·  ★ 2300

- **Source:** [CF 713C · Sonya and Problem Wihtout a Legend](https://codeforces.com/problemset/problem/713/C) — 2300
- **Difficulty:** 2300
- **Problem:** the same with $n \le 3000$, $1 \le a_i \le 10^9$, but the result must be **strictly** increasing (values may become zero or negative).
- **Thinking from first principles:** strictness breaks the "values of $a$ suffice" lemma and the prefix-min structure. Transform it away: $b_1 < b_2 < \dots$ over integers $\iff$ $b_i - i$ is non-decreasing. Set $c_i = a_i - i$, $d_i = b_i - i$; then $|a_i - b_i| = |c_i - d_i|$ and the problem *is* Example 2 on $c$.

<details><summary>Solution</summary>

One subtraction added to Example 2. The brute force used for stress testing solved the strict version directly (DP over a padded integer range with $\min_{y < x}$), so it checks the reduction too.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n;
    cin >> n;
    priority_queue<ll> L;
    ll ans = 0;
    for (int i = 0; i < n; i++) {
        ll a; cin >> a;
        a -= i;                    // b strictly increasing  <=>  b_i - i non-decreasing
        L.push(a);
        if (L.top() > a) { ans += L.top() - a; L.pop(); L.push(a); }
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        PriorityQueue<Long> L = new PriorityQueue<>(Collections.reverseOrder());
        long ans = 0;
        for (int i = 0; i < n; i++) {
            long a = in.nextLong() - i;
            L.add(a);
            if (L.peek() > a) { ans += L.poll() - a; L.add(a); }
        }
        out.println(ans);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
7
2 1 5 11 5 9 11
out:
9
-->
<!-- test
in:
5
5 4 3 2 1
out:
12
-->
<!-- test
in:
1
7
out:
0
-->
<!-- test
in:
4
1 1 1 1
out:
4
-->

</details>

### Example 4 — Buy Low Sell High  ·  ★ 2400

- **Source:** [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400
- **Difficulty:** 2400
- **Problem:** $n \le 3\cdot10^5$ daily prices $p_i \le 10^6$. Each day buy one share, sell one share, or do nothing; start and end with zero shares (short selling not allowed). Maximise profit.
- **Thinking from first principles:** DP over the number of shares held: $F_i(h) = \max(F_{i-1}(h),\ F_{i-1}(h+1) + p_i,\ F_{i-1}(h-1) - p_i)$ — $O(n^2)$. Claim: $F_i$ is concave in $h$; then it is described by its decreasing sequence of marginal values $F_i(h) - F_i(h+1)$ ("the price at which you would give up one share"), and day $i$'s step is a max-plus convolution with the kernel $\{-1 \mapsto +p,\ 0 \mapsto 0,\ +1 \mapsto -p\}$, which for concave functions **merges slope sequences**: it inserts $p_i$ twice and drops the extreme slope that would make $h$ negative. With a min-heap of these marginal prices that is the famous loop:

```text
for each price p:
    if heap not empty and heap.min < p:  profit += p - heap.min;  pop;  push p    # sell against the cheapest
    push p                                                                       # today is a candidate buy
```

  The second `push p` after a sale is the "regret" option: if a later price $q > p$ appears, selling at $q$ against the re-inserted $p$ adds $q - p$, which turns "buy at $c$, sell at $p$" into "buy at $c$, sell at $q$" while keeping $p$ unused.

<details><summary>Solution</summary>

Correctness: either via the concave slope-merge argument above or via the exchange argument of [greedy with regret](../03-Greedy-Constructive-Interactive/02-greedy-with-heaps-and-regret.md). Both are confirmed by the $O(n^2)$ DP over holdings on random inputs. Time $O(n \log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n;
    cin >> n;
    priority_queue<ll, vector<ll>, greater<ll>> H;   // marginal buy prices = breakpoints of -profit(h)
    ll ans = 0;
    for (int i = 0; i < n; i++) {
        ll p; cin >> p;
        if (!H.empty() && H.top() < p) {
            ans += p - H.top();                       // sell today against the cheapest open option
            H.pop();
            H.push(p);                                // regret: selling today can later be "undone"
        }
        H.push(p);                                    // today is also a possible buy day
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        PriorityQueue<Long> H = new PriorityQueue<>();
        long ans = 0;
        for (int i = 0; i < n; i++) {
            long p = in.nextLong();
            if (!H.isEmpty() && H.peek() < p) {
                ans += p - H.poll();
                H.add(p);
            }
            H.add(p);
        }
        out.println(ans);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
9
10 5 4 7 9 12 6 2 10
out:
20
-->
<!-- test
in:
20
3 1 4 1 5 9 2 6 5 3 5 8 9 7 9 3 2 3 8 4
out:
41
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
5 5 5 5
out:
0
-->

</details>

### Example 5 — NarrowRectangles (sliding-window minimum)  ·  ★ ≈3365 (AtCoder estimate)

- **Source:** [AtCoder ARC070 E · NarrowRectangles](https://atcoder.jp/contests/arc070/tasks/arc070_c)
- **Difficulty:** ≈3365 (AtCoder estimate; the idea is a direct slope-trick exercise once you know §1.4)
- **Problem:** $N \le 10^5$ unit-height rectangles stacked in rows; row $i$ covers $[l_i, r_i]$ horizontally. Moving a row horizontally by distance $d$ costs $d$. Make the union connected (each row must touch the row below it, touching edges count) at minimum total cost.
- **Thinking from first principles:** let $x$ = new left end of row $i$ and $w_i = r_i - l_i$. Rows $i-1$ (left end $y$) and $i$ touch iff $[y, y + w_{i-1}] \cap [x, x + w_i] \ne \emptyset$, i.e. $x - w_{i-1} \le y \le x + w_i$. So
  $$f_i(x) = |x - l_i| + \min_{y \in [x - w_{i-1},\ x + w_i]} f_{i-1}(y),$$
  a window minimum with $a = -w_i$, $b = w_{i-1}$ ($a \le b$ holds), then add $|x - l_i|$. The answer is the minimum of $f_N$.

<details><summary>Solution</summary>

Lazy offsets: `addL -= w[i]`, `addR += w[i-1]`, then add $|x - l_i|$, written here as a three-case insertion (left of, right of, or inside the bottom) — equivalent to doing operations 2 and 3 of §1.4. The lazy offsets reach $N \cdot 10^9 = 10^{14}$ and so can the minimum: 64-bit everywhere. Time $O(N \log N)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n;
    cin >> n;
    vector<ll> l(n), w(n);
    for (int i = 0; i < n; i++) { ll r; cin >> l[i] >> r; w[i] = r - l[i]; }
    // f(x) = min cost of rows 1..i with the left end of row i at x
    priority_queue<ll> L;                                   // stored value = real - addL
    priority_queue<ll, vector<ll>, greater<ll>> R;          // stored value = real - addR
    ll addL = 0, addR = 0, minF = 0;
    auto add_abs = [&](ll a) {                              // f += |x - a|
        ll tl = L.empty() ? LLONG_MIN / 4 : L.top() + addL;
        ll tr = R.empty() ? LLONG_MAX / 4 : R.top() + addR;
        if (a < tl) {                                       // a lies left of the flat bottom
            minF += tl - a;
            L.pop(); R.push(tl - addR);
            L.push(a - addL); L.push(a - addL);
        } else if (a > tr) {                                // a lies right of the flat bottom
            minF += a - tr;
            R.pop(); L.push(tr - addL);
            R.push(a - addR); R.push(a - addR);
        } else {                                            // inside the bottom: min unchanged
            L.push(a - addL); R.push(a - addR);
        }
    };
    add_abs(l[0]);
    for (int i = 1; i < n; i++) {
        // rows i-1 (left end y) and i (left end x) touch  <=>  x - w[i-1] <= y <= x + w[i]
        addL -= w[i];                                       // g(x) = min_{y in [x - w[i-1], x + w[i]]} f(y)
        addR += w[i - 1];
        add_abs(l[i]);
    }
    cout << minF << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static PriorityQueue<Long> L = new PriorityQueue<>(Collections.reverseOrder()), R = new PriorityQueue<>();
    static long addL = 0, addR = 0, minF = 0;

    static void addAbs(long a) {
        long tl = L.isEmpty() ? Long.MIN_VALUE / 4 : L.peek() + addL;
        long tr = R.isEmpty() ? Long.MAX_VALUE / 4 : R.peek() + addR;
        if (a < tl) {
            minF += tl - a;
            L.poll(); R.add(tl - addR);
            L.add(a - addL); L.add(a - addL);
        } else if (a > tr) {
            minF += a - tr;
            R.poll(); L.add(tr - addL);
            R.add(a - addR); R.add(a - addR);
        } else {
            L.add(a - addL); R.add(a - addR);
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long[] l = new long[n], w = new long[n];
        for (int i = 0; i < n; i++) { l[i] = in.nextLong(); w[i] = in.nextLong() - l[i]; }
        addAbs(l[0]);
        for (int i = 1; i < n; i++) {
            addL -= w[i];
            addR += w[i - 1];
            addAbs(l[i]);
        }
        out.println(minF);
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            for (; c >= '0' && c <= '9'; c = read()) r = r * 10 + (c - '0');
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

<!-- test
in:
3
1 3
5 7
1 3
out:
2
-->
<!-- test
in:
3
2 5
4 6
1 4
out:
0
-->
<!-- test
in:
1
1 40
out:
0
-->
<!-- test
in:
4
1 2
10 11
1 2
10 11
out:
16
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Get the DP order right.** "$dp_i(x) = \mathrm{cost}_i(x) + \min_{y \le x} dp_{i-1}(y)$" means *prefix-min the old function, then add the new cost*. Doing it in the other order solves a different recurrence.
2. **Lazy offsets are per heap.** Store `value - addL` in $L$ and `value - addR` in $R$; when moving an element between heaps convert through the real value. Forgetting this is the most common bug in window problems.
3. **Sentinels.** Use $\pm$`LLONG_MAX/4` for an empty heap's top and never add two sentinels. In Java `Long.MAX_VALUE / 4`.
4. **Multiplicities.** $|x - a|$ changes the slope by 2: it inserts $a$ once into each side (or twice into one side, as in Example 5). Weighted costs $w|x - a|$ need $w$ copies — use a `map<value, count>` if $w$ is large.
5. **Strict inequalities:** subtract $i$ (Example 3). For "differences in $[lo, hi]$" use a window with $a = lo$, $b = hi$.
6. **Answer = `minF`, minimiser = `[topL, topR]`.** If the problem wants the actual sequence, record a minimiser after each step and backtrack with $\min(b_{i+1}, opt_i)$ (§3).
7. **Overflow:** minima grow like $n \cdot \max|a|$ ($10^{14}$ at $n = 10^5$, values $10^9$); lazy offsets grow like $\sum w_i$. Everything 64-bit.
8. **Java `PriorityQueue<Long>`** boxes every element; $2\cdot10^5$–$10^6$ operations are fine, $10^7$ are not — write a primitive binary heap on `long[]` then. Use `Collections.reverseOrder()` for the max-heap, never a subtraction comparator (overflow).
9. **C++** `priority_queue` has no `clear()`; assign an empty queue (`R = {}`) for prefix/suffix minimum.
10. **Convexity check.** Every operation must preserve convexity: adding convex functions, prefix/suffix/window minima, shifts. A $\max_y$ transition or a capped cost breaks it — the heaps then silently give a wrong answer.

## 7. Going further (toward 2400–2600+)

- **Slope trick on trees.** When subtrees are combined by *adding* their functions, merge the heaps small-to-large (or with mergeable heaps) — total $O(n \log^2 n)$ or $O(n \log n)$. The classic is the APIO 2016 task "Fireworks". See [small-to-large](../10-Trees/03-small-to-large-and-dsu-on-tree.md).
- **Rotate first.** Chebyshev-distance problems become slope-trick problems after the $45°$ rotation $(x, y) \mapsto (x + y, x - y)$: [CF 1534G · A New Beginning](https://codeforces.com/problemset/problem/1534/G) — 3300.
- **Non-linear convex costs.** For quadratic costs, maintain the *derivative* (piecewise linear) instead of the function: [CF 280E · Sequence Transformation](https://codeforces.com/problemset/problem/280/E) — 3000.
- **Time-indexed windows.** "Be at position $x_i$ at time $t_i$, speed 1" is a window minimum of width $t_i - t_{i-1}$ between events: [AtCoder ABC217 H · Snuketoon](https://atcoder.jp/contests/abc217/tasks/abc217_h).
- **Extreme:** [CF 1210G · Mateusz and Escape Room](https://codeforces.com/problemset/problem/1210/G) — 3500 combines a cyclic structure with slope trick.
- **Relation to Aliens:** both exploit convexity; [Aliens](06-aliens-trick-wqs-binary-search.md) when convex in the *number of uses*, slope trick when convex in a *value* you choose.

## 8. Practice ladder

- [ ] [LC 462 · Minimum Moves to Equal Array Elements II](https://leetcode.com/problems/minimum-moves-to-equal-array-elements-ii/) — Medium
- [ ] [AtCoder ABC127 F · Absolute Minima](https://atcoder.jp/contests/abc127/tasks/abc127_f)
- [ ] [CF 13C · Sequence](https://codeforces.com/problemset/problem/13/C) — 2200
- [ ] [CF 713C · Sonya and Problem Wihtout a Legend](https://codeforces.com/problemset/problem/713/C) — 2300
- [ ] [CF 865D · Buy Low Sell High](https://codeforces.com/problemset/problem/865/D) — 2400
- [ ] [AtCoder ABC217 H · Snuketoon](https://atcoder.jp/contests/abc217/tasks/abc217_h)
- [ ] [AtCoder ARC070 E · NarrowRectangles](https://atcoder.jp/contests/arc070/tasks/arc070_c)
- [ ] [CF 280E · Sequence Transformation](https://codeforces.com/problemset/problem/280/E) — 3000
- [ ] [CF 1534G · A New Beginning](https://codeforces.com/problemset/problem/1534/G) — 3300
- [ ] [CF 1210G · Mateusz and Escape Room](https://codeforces.com/problemset/problem/1210/G) — 3500
- [ ] [LC 2263 · Make Array Non-decreasing or Non-increasing](https://leetcode.com/problems/make-array-non-decreasing-or-non-increasing/) — Hard 🔒

## 9. LeetCode / FAANG cross-reference

- [LC 462 · Minimum Moves to Equal Array Elements II](https://leetcode.com/problems/minimum-moves-to-equal-array-elements-ii/) — Medium — $\min_x \sum|x - a_i|$: the one-step slope trick, answer at the median.
- [LC 2448 · Minimum Cost to Make Array Equal](https://leetcode.com/problems/minimum-cost-to-make-array-equal/) — Hard — weighted $\sum c_i |x - a_i|$: the weighted median, i.e. the breakpoint where the slope crosses 0.
- [LC 2263 · Make Array Non-decreasing or Non-increasing](https://leetcode.com/problems/make-array-non-decreasing-or-non-increasing/) — Hard 🔒 — Example 2 run in both directions.

Rare in interviews beyond the median problems: interviewers accept the $O(n \cdot V)$ or $O(n^2)$ DP for LC 2263; the heap solution is a bonus that needs the convexity explanation.

## 10. Self-check

1. Why is $dp_i$ in the non-decreasing problem convex piecewise linear with integer slopes?
2. Write the representation of $f$ and say where its minimum is attained.
3. Derive the update for adding $\max(0, x - a)$ in both cases.
4. What does a prefix minimum do to the heaps? A window minimum over $[x-b, x-a]$?
5. How do you make "strictly increasing" fit the non-decreasing template?
6. How do you recover an optimal $b$ after running the heap loop?
7. Which transitions break slope trick?
8. In Buy Low Sell High, why is $p$ pushed a second time after a sale?

<details><summary>Answers</summary>

1. $|x - a_i|$ is, the prefix minimum of a convex function is convex, and sums of such functions stay convex piecewise linear with integer slopes.
2. $f = \mathrm{minF} + \sum_{l\in L}(l-x)^+ + \sum_{r\in R}(x-r)^+$ with $\max L \le \min R$; the minimum $\mathrm{minF}$ is attained on $[\max L, \min R]$.
3. If $a \ge \max L$ the minimum is unchanged and $a$ goes to $R$; otherwise the minimum rises by $\max L - a$, $\max L$ moves to $R$ and $a$ joins $L$. One code path: add $(\max L - a)^+$, push $a$ to $L$, move $\max L$ to $R$.
4. Prefix minimum clears $R$; the window adds $a$ to all of $L$ and $b$ to all of $R$ (lazily).
5. Replace $a_i$ by $a_i - i$; strictly increasing $b_i$ correspond to non-decreasing $b_i - i$.
6. Store $opt_i = \max L$ after each step; $b_n = opt_n$, $b_i = \min(b_{i+1}, opt_i)$.
7. Maximising over $y$, non-convex (capped, concave) costs, anything that is not a sum/shift/prefix-or-window minimum of convex functions.
8. It records the option of cancelling today's sale and selling later instead; in the slope view, the step inserts $p$ twice into the slope sequence.

</details>

Back to the [folder README](README.md) · [problems](problems.md) · [cheat sheet](../99-Cheat-Sheets/07-dp-optimizations-cheatsheet.md)
