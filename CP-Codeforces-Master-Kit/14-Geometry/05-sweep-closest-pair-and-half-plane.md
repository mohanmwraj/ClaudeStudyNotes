# Sweep algorithms: closest pair, half-plane intersection, Manhattan tricks

> **Band:** 🔵 1500 – 🔴 2600 · **Priority:** 🔥 (Manhattan rotation, closest pair) · ⚡ (half-plane intersection) · 🧊 (Shamos–Hoey, Manhattan MST) · **FAANG:** medium (Manhattan tricks) · **Prerequisites:** [vectors](01-vectors-dot-cross-and-precision.md), [lines](02-lines-segments-and-intersections.md), [coordinate compression and sweep line](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md), [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md)
> **You can say you know this when:** you can prove the "constant number of candidates" packing bound for the closest pair,
> write the sweep with an ordered set, explain why the deque half-plane algorithm only ever pops from the two ends, and
> convert any Manhattan-distance question to a Chebyshev one (and back) without thinking.

---

## 1. First principles — why this works

### 1.1 The sweep paradigm

Many geometric questions are about *pairs* (closest points, intersecting segments, overlapping rectangles) — $O(n^2)$ naively.
A **sweep** orders the objects along one axis and processes them as a vertical line moves left to right, keeping an
**active set** of objects that can still interact with what comes next. The invariant that makes it fast is always a
*locality* statement: "only $O(1)$ active objects can interact with the new one" or "only neighbours in the active order can
interact first". Find that statement and the algorithm writes itself.

### 1.2 Closest pair of points

**Divide and conquer.** Sort by $x$, split at the median line $x=m$, recurse: $\delta=\min(\delta_L,\delta_R)$. A better pair must
cross the line and lie in the strip $\lvert x-m\rvert<\delta$. Sort the strip by $y$; for a strip point $p$, a partner within
distance $\delta$ lies in the $2\delta\times\delta$ rectangle above it. **Packing bound:** cut that rectangle into eight
$\frac\delta2\times\frac\delta2$ squares; two points in one square are at distance $\le\frac{\delta}{\sqrt2}<\delta$, impossible for points on
the same side, and each square lies entirely on one side, so the rectangle holds at most 8 points — $p$ needs to be compared with
at most 7 successors in $y$-order. Merging by $y$ during the recursion gives $T(n)=2T(n/2)+O(n)=O(n\log n)$.

**Sweep with an ordered set** (shorter to code). Sort by $x$. Keep the current best squared distance $D$ and $d=\lceil\sqrt D\rceil$.
Maintain the active set of points with $x\ge x_{\text{cur}}-d$, ordered by $y$. For the new point, only active points with
$y\in[y_{\text{cur}}-d,y_{\text{cur}}+d]$ can improve $D$; by the same packing argument there are $O(1)$ of them. Each point enters and
leaves the set once: $O(n\log n)$.

**Randomised grid (expected $O(n)$, 🧊).** Shuffle, keep a hash grid with cell size $d$; a new point checks the 9 neighbouring cells;
when $d$ shrinks, rebuild the grid. The probability that the $i$-th point shrinks $d$ is $\le\frac2i$ (it must be one of the two
points of the closest pair among the first $i$), so the expected rebuild cost is $\sum_i\frac2i\cdot i=O(n)$.

### 1.3 Does any pair of segments intersect? (Shamos–Hoey, 🧊)

Sweep a vertical line; the active segments (those crossing the line) are totally ordered by their $y$ at the sweep line,
and that order changes only at intersection points. **Key lemma:** if some pair intersects, take the leftmost intersection
point $X$; just before the sweep reaches $X$, the two segments meeting at $X$ are *adjacent* in the active order (any segment
between them would have to cross one of them earlier). So it suffices to test each segment against its neighbours when it is
inserted, and the two segments that become neighbours when one is deleted:

```text
events: left endpoints (insert) and right endpoints (delete), sorted by x (inserts before deletes at equal x)
on insert s:  find predecessor a and successor b in the ordered set; if s∩a or s∩b: report YES; insert s
on delete s:  a = pred(s), b = succ(s); remove s; if a∩b: report YES
report NO
```

The comparator compares two segments by their $y$ at the current sweep $x$ — exact with fractions or `__int128`. $O(n\log n)$.
Reporting *all* $k$ intersections is Bentley–Ottmann, $O((n+k)\log n)$ — ICPC material, rare on Codeforces.

### 1.4 Half-plane intersection

A half-plane is "the left side of a directed line $p+td$": $\{q:\ d\times(q-p)\ge0\}$. The intersection of $n$ half-planes is a
convex region; we want its polygon. Incremental clipping of a polygon by each half-plane is $O(n^2)$.

The $O(n\log n)$ algorithm rests on two observations:

1. **Boundary edges appear in angular order.** Walking a convex polygon counter-clockwise, edge directions increase. So if we sort
   half-planes by the angle of $d$ (keeping only the innermost of parallel same-direction ones), the half-planes that contribute
   edges appear in that order.
2. **A new half-plane can only cut off vertices at the ends of the current chain.** The current boundary is a convex chain of
   half-planes sorted by angle; the new half-plane has the largest angle so far, so the vertices it removes are a suffix (the most
   recent) — and, because the chain wraps around the circle, possibly a prefix.

So keep a **deque**: before pushing half-plane $h$, pop from the back while the intersection point of the last two lines is
outside $h$, and pop from the front while the intersection of the first two is outside $h$. At the end, pop from the back while
the last intersection is outside the first half-plane (and symmetrically). The remaining lines, intersected cyclically, give the
polygon. Each line enters and leaves once: $O(n)$ after sorting. Add four bounding-box half-planes so the result is always
bounded; then fewer than 3 remaining lines means "empty".

### 1.5 Manhattan and Chebyshev distance

**The rotation identity.** For reals $a,b$: $\lvert a\rvert+\lvert b\rvert=\max(\lvert a+b\rvert,\lvert a-b\rvert)$ (check the four sign cases; or note
$\lvert a\rvert+\lvert b\rvert=\max_{s,t\in\{\pm1\}}(sa+tb)$ and group the four terms). With $u=x+y$, $v=x-y$:

$$\lvert x_1-x_2\rvert+\lvert y_1-y_2\rvert=\max(\lvert u_1-u_2\rvert,\lvert v_1-v_2\rvert).$$

So **Manhattan distance in $(x,y)$ is Chebyshev distance in $(u,v)$**, and conversely
$\max(\lvert\Delta x\rvert,\lvert\Delta y\rvert)=\frac{\lvert\Delta u\rvert+\lvert\Delta v\rvert}{2}$. Geometrically the map is a $45^\circ$ rotation with scaling
$\sqrt2$: diamonds become axis-aligned squares. Consequences:

- **Maximum Manhattan distance** in a set $=\max(u_{\max}-u_{\min},\ v_{\max}-v_{\min})$ — $O(n)$, even online.
- **Points within Manhattan distance $r$ of $q$** = an axis-aligned square in $(u,v)$ → 2D range counting.
- **Sum of pairwise Manhattan distances** is *separable*: $\sum\lvert\Delta x\rvert+\sum\lvert\Delta y\rvert$, each a sorted prefix-sum
  computation. **Sum of pairwise Chebyshev distances**: rotate, then it is $\frac12$(sum of Manhattan in $(u,v)$).
- In $k$ dimensions: $\sum_i\lvert\Delta x_i\rvert=\max_{s\in\{\pm1\}^k}s\cdot\Delta x$, so the farthest pair needs $2^{k-1}$ extreme
  projections.

**Manhattan MST (🔴).** For each point, split the plane around it into 8 octants; in each octant only the *nearest* point (in
Manhattan distance) needs an edge: if $q,r$ are in the same octant of $p$ with $d(p,q)\le d(p,r)$, then $d(q,r)\le d(p,r)$, so edge $pr$
is the longest in triangle $pqr$ and never needed (cycle property). By symmetry 4 octants suffice; each is found with a sweep
and a Fenwick tree of minima, giving $O(n)$ candidate edges and an $O(n\log n)$ MST
([minimum spanning trees](../09-Graphs/03-minimum-spanning-trees.md)).

---

## 2. Formulas, definitions and identities

| Formula | Meaning | Cost |
|---|---|---|
| packing: $2\delta\times\delta$ box holds $\le8$ points at pairwise distance $\ge\delta$ | closest-pair candidate bound | |
| $T(n)=2T(n/2)+O(n)=O(n\log n)$ | D&C closest pair | |
| $\Pr[\text{point } i \text{ shrinks } d]\le\frac2i$ | randomised grid, expected $O(n)$ | |
| $\lvert a\rvert+\lvert b\rvert=\max(\lvert a+b\rvert,\lvert a-b\rvert)$ | rotation identity | |
| $d_1(p,q)=d_\infty(R p,Rq)$, $R(x,y)=(x+y,x-y)$ | Manhattan → Chebyshev | |
| $d_\infty(p,q)=\frac12 d_1(Rp,Rq)$ | Chebyshev → Manhattan | |
| $\max_{p,q}d_1(p,q)=\max(u_{\max}-u_{\min},v_{\max}-v_{\min})$ | farthest Manhattan pair | $O(n)$ |
| $\sum_{i<j}\lvert a_i-a_j\rvert=\sum_{k}a_{(k)}(2k-n-1)$ (sorted, 1-indexed) | separable pair sums | $O(n\log n)$ |
| half-plane $\{q: d\times(q-p)\ge0\}$ | left of directed line | |
| intersection of lines: $p_1+d_1\frac{(p_2-p_1)\times d_2}{d_1\times d_2}$ | (file 02) | |
| half-plane intersection | sort by angle + deque | $O(n\log n)$ |
| Shamos–Hoey | any intersection among $n$ segments | $O(n\log n)$ |

**Derivation of the sorted pair-sum formula.** In sorted order, $a_{(k)}$ is the larger element in $k-1$ pairs (contributing $+a_{(k)}$)
and the smaller in $n-k$ pairs (contributing $-a_{(k)}$): coefficient $(k-1)-(n-k)=2k-n-1$.

---

## 3. Implementation (C++ and Java)

### 3.1 Closest pair (sweep with an ordered set), exact squared distance

```cpp
// Squared minimum distance among >= 2 points (duplicates allowed -> 0).
ll closestPair2(vector<pair<ll, ll>> p) {                 // (x, y)
    sort(p.begin(), p.end());
    multiset<pair<ll, ll>> act;                            // (y, x)
    ll best = LLONG_MAX;
    size_t left = 0;
    for (size_t i = 0; i < p.size(); i++) {
        ll d = (ll)ceill(sqrtl((ld)best));
        while (left < i && p[i].first - p[left].first > d) act.erase(act.find({p[left].second, p[left].first})), left++;
        for (auto it = act.lower_bound({p[i].second - d, LLONG_MIN}); it != act.end() && it->first <= p[i].second + d; ++it) {
            ll dx = p[i].first - it->second, dy = p[i].second - it->first;
            best = min(best, dx * dx + dy * dy);
        }
        act.insert({p[i].second, p[i].first});
    }
    return best;
}
```

```java
// Points packed as (y + OFF) << 32 | (x + OFF) in a TreeMap with multiplicities; coordinates |v| <= LIM = 1e9.
static final long OFF = 1_100_000_000L, LIM = 1_000_000_000L;
static long closestPair2(long[] xs, long[] ys) {
    int n = xs.length;
    Integer[] idx = new Integer[n];
    for (int i = 0; i < n; i++) idx[i] = i;
    Arrays.sort(idx, (a, b) -> xs[a] != xs[b] ? Long.compare(xs[a], xs[b]) : Long.compare(ys[a], ys[b]));
    TreeMap<Long, Integer> act = new TreeMap<>();
    long best = Long.MAX_VALUE;
    int left = 0;
    for (int k = 0; k < n; k++) {
        int i = idx[k];
        long d = (long) Math.ceil(Math.sqrt((double) best)) + 1;    // +1 absorbs double rounding
        while (left < k && xs[i] - xs[idx[left]] > d) {
            long key = ((ys[idx[left]] + OFF) << 32) | (xs[idx[left]] + OFF);
            if (act.merge(key, -1, Integer::sum) == 0) act.remove(key);
            left++;
        }
        // clamp to [-LIM, LIM]: (LIM + OFF) << 32 < 2^63, while (2 * OFF) << 32 would overflow
        long lo = (Math.max(ys[i] - d, -LIM) + OFF) << 32, hi = ((Math.min(ys[i] + d, LIM) + OFF) << 32) | 0xFFFFFFFFL;
        for (long key : act.subMap(lo, true, hi, true).keySet()) {
            long y = (key >>> 32) - OFF, x = (key & 0xFFFFFFFFL) - OFF;
            long dx = xs[i] - x, dy = ys[i] - y;
            best = Math.min(best, dx * dx + dy * dy);
        }
        act.merge(((ys[i] + OFF) << 32) | (xs[i] + OFF), 1, Integer::sum);
    }
    return best;
}
```

### 3.2 Half-plane intersection (floating point)

```cpp
const ld EPS = 1e-9;
struct PD { ld x, y; };
PD operator+(PD a, PD b) { return {a.x + b.x, a.y + b.y}; }
PD operator-(PD a, PD b) { return {a.x - b.x, a.y - b.y}; }
PD operator*(PD a, ld k) { return {a.x * k, a.y * k}; }
ld cross(PD a, PD b) { return a.x * b.y - a.y * b.x; }
ld dot(PD a, PD b) { return a.x * b.x + a.y * b.y; }
struct HP {                                               // left side of p + t*d
    PD p, d; ld ang;
    HP(PD p_, PD d_) : p(p_), d(d_), ang(atan2l(d_.y, d_.x)) {}
    bool out(PD q) const { return cross(d, q - p) < -EPS; }
};
PD inter(const HP& a, const HP& b) { return a.p + a.d * (cross(b.p - a.p, b.d) / cross(a.d, b.d)); }
// Returns the vertices (CCW) of the intersection; empty if it is empty or degenerate. Caller adds a bounding box.
vector<PD> halfPlaneIntersection(vector<HP> h) {
    sort(h.begin(), h.end(), [](const HP& a, const HP& b) { return a.ang < b.ang; });
    deque<HP> dq;
    for (auto& cur : h) {
        while (dq.size() >= 2 && cur.out(inter(dq[dq.size() - 1], dq[dq.size() - 2]))) dq.pop_back();
        while (dq.size() >= 2 && cur.out(inter(dq[0], dq[1]))) dq.pop_front();
        if (!dq.empty() && fabsl(cross(cur.d, dq.back().d)) < EPS) {
            if (dot(cur.d, dq.back().d) < 0) return {};          // opposite parallel planes facing away
            if (cur.out(dq.back().p)) { dq.pop_back(); dq.push_back(cur); }   // same direction: keep the inner one
            continue;
        }
        dq.push_back(cur);
    }
    while (dq.size() >= 3 && dq[0].out(inter(dq[dq.size() - 1], dq[dq.size() - 2]))) dq.pop_back();
    while (dq.size() >= 3 && dq[dq.size() - 1].out(inter(dq[0], dq[1]))) dq.pop_front();
    if (dq.size() < 3) return {};
    vector<PD> res;
    for (size_t i = 0; i < dq.size(); i++) res.push_back(inter(dq[i], dq[(i + 1) % dq.size()]));
    return res;
}
```

```java
static final double EPS = 1e-9;
static final class HP {                                  // left side of (px,py) + t*(dx,dy)
    final double px, py, dx, dy, ang;
    HP(double px, double py, double dx, double dy) { this.px = px; this.py = py; this.dx = dx; this.dy = dy; ang = Math.atan2(dy, dx); }
    boolean out(double[] q) { return dx * (q[1] - py) - dy * (q[0] - px) < -EPS; }
}
static double[] inter(HP a, HP b) {
    double t = ((b.px - a.px) * b.dy - (b.py - a.py) * b.dx) / (a.dx * b.dy - a.dy * b.dx);
    return new double[]{a.px + a.dx * t, a.py + a.dy * t};
}
static List<double[]> halfPlaneIntersection(List<HP> hs) {
    List<HP> h = new ArrayList<>(hs);
    h.sort((a, b) -> Double.compare(a.ang, b.ang));
    ArrayDeque<HP> dq = new ArrayDeque<>();
    for (HP cur : h) {
        while (dq.size() >= 2 && cur.out(inter(dq.peekLast(), secondLast(dq)))) dq.pollLast();
        while (dq.size() >= 2 && cur.out(inter(dq.peekFirst(), secondFirst(dq)))) dq.pollFirst();
        if (!dq.isEmpty() && Math.abs(cur.dx * dq.peekLast().dy - cur.dy * dq.peekLast().dx) < EPS) {
            if (cur.dx * dq.peekLast().dx + cur.dy * dq.peekLast().dy < 0) return new ArrayList<>();
            if (cur.out(new double[]{dq.peekLast().px, dq.peekLast().py})) { dq.pollLast(); dq.addLast(cur); }
            continue;
        }
        dq.addLast(cur);
    }
    while (dq.size() >= 3 && dq.peekFirst().out(inter(dq.peekLast(), secondLast(dq)))) dq.pollLast();
    while (dq.size() >= 3 && dq.peekLast().out(inter(dq.peekFirst(), secondFirst(dq)))) dq.pollFirst();
    List<double[]> res = new ArrayList<>();
    if (dq.size() < 3) return res;
    HP[] arr = dq.toArray(new HP[0]);
    for (int i = 0; i < arr.length; i++) res.add(inter(arr[i], arr[(i + 1) % arr.length]));
    return res;
}
static HP secondLast(ArrayDeque<HP> dq) { HP last = dq.pollLast(); HP r = dq.peekLast(); dq.addLast(last); return r; }
static HP secondFirst(ArrayDeque<HP> dq) { HP first = dq.pollFirst(); HP r = dq.peekFirst(); dq.addFirst(first); return r; }
```

### 3.3 Manhattan helpers

```cpp
// Farthest Manhattan pair value among points (x, y).
ll maxManhattan(const vector<pair<ll, ll>>& p) {
    ll umax = LLONG_MIN, umin = LLONG_MAX, vmax = LLONG_MIN, vmin = LLONG_MAX;
    for (auto [x, y] : p) {
        umax = max(umax, x + y); umin = min(umin, x + y);
        vmax = max(vmax, x - y); vmin = min(vmin, x - y);
    }
    return max(umax - umin, vmax - vmin);
}
// Sum over pairs of |a_i - a_j| (128-bit: can exceed 2^63).
__int128 pairAbsSum(vector<ll> a) {
    sort(a.begin(), a.end());
    __int128 s = 0, pre = 0;
    for (size_t k = 0; k < a.size(); k++) { s += (__int128)a[k] * (ll)k - pre; pre += a[k]; }
    return s;
}
```

```java
static long maxManhattan(long[] x, long[] y) {
    long umax = Long.MIN_VALUE, umin = Long.MAX_VALUE, vmax = Long.MIN_VALUE, vmin = Long.MAX_VALUE;
    for (int i = 0; i < x.length; i++) {
        umax = Math.max(umax, x[i] + y[i]); umin = Math.min(umin, x[i] + y[i]);
        vmax = Math.max(vmax, x[i] - y[i]); vmin = Math.min(vmin, x[i] - y[i]);
    }
    return Math.max(umax - umin, vmax - vmin);
}
static BigInteger pairAbsSum(long[] a0) {
    long[] a = a0.clone();
    Arrays.sort(a);                                      // primitive sort: shuffle first if inputs may be adversarial
    BigInteger total = BigInteger.ZERO;
    long acc = 0, pre = 0;
    for (int k = 0; k < a.length; k++) {
        acc += a[k] * k - pre;                           // each term is in [0, 4e14]
        pre += a[k];
        if (acc > 4_000_000_000_000_000_000L) { total = total.add(BigInteger.valueOf(acc)); acc = 0; }
    }
    return total.add(BigInteger.valueOf(acc));
}
```

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "minimum distance between two points", $n\ge10^5$ | closest pair (sweep or D&C) |
| "minimise $(i-j)^2+(\text{something}_i-\text{something}_j)^2$" | closest pair of points $(i,\text{something}_i)$ |
| "Manhattan distance", "$\lvert x_1-x_2\rvert+\lvert y_1-y_2\rvert$", "taxicab", "king moves" | rotate $(x+y,x-y)$; Chebyshev ↔ Manhattan |
| "maximum Manhattan distance", "farthest pair in $L_1$" | extremes of $u$ and $v$ |
| "sum of distances over all pairs" | separability: each coordinate on its own (rotate first for Chebyshev) |
| "points inside a diamond / within distance $r$" | square in rotated coordinates → 2D range counting (offline BIT) |
| "region satisfying many linear inequalities", "kernel of a polygon", "visible from everywhere" | half-plane intersection |
| "do any two segments intersect", $n=10^5$ | Shamos–Hoey sweep |
| "MST with Manhattan weights" | octant nearest neighbours + Kruskal |

---

## 5. Worked examples (graded)

### Example 1 — Maximum Manhattan Distances (online)  ·  ★ ≈1500

- **Source:** [CSES 3410 · Maximum Manhattan Distances](https://cses.fi/problemset/task/3410)
- **Difficulty:** ≈1500 (est.)
- **Problem:** $n\le2\cdot10^5$ distinct points are added one by one ($\lvert x\rvert,\lvert y\rvert\le10^9$). After each addition print the
  maximum Manhattan distance between two points currently in the set.
- **Thinking from first principles:** Recomputing all pairs is $O(n^2)$ per step. The rotation turns the distance into
  $\max(\lvert\Delta u\rvert,\lvert\Delta v\rvert)$, so the farthest pair is decided by the four extremes $u_{\max},u_{\min},v_{\max},v_{\min}$ —
  maintain them online.

<details><summary>Solution</summary>

$O(1)$ per point. Values up to $4\cdot10^9$: 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    ll umax = LLONG_MIN, umin = LLONG_MAX, vmax = LLONG_MIN, vmin = LLONG_MAX;
    string out;
    for (int i = 0; i < n; i++) {
        ll x, y; cin >> x >> y;
        umax = max(umax, x + y); umin = min(umin, x + y);
        vmax = max(vmax, x - y); vmin = min(vmin, x - y);
        out += to_string(max(umax - umin, vmax - vmin)) + '\n';
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) readLong(in);
        long umax = Long.MIN_VALUE, umin = Long.MAX_VALUE, vmax = Long.MIN_VALUE, vmin = Long.MAX_VALUE;
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) {
            long x = readLong(in), y = readLong(in);
            umax = Math.max(umax, x + y); umin = Math.min(umin, x + y);
            vmax = Math.max(vmax, x - y); vmin = Math.min(vmin, x - y);
            sb.append(Math.max(umax - umin, vmax - vmin)).append('\n');
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
4
0 0
3 1
-1 2
2 -4
out:
0
4
5
9
-->
<!-- test
in:
2
-1000000000 -1000000000
1000000000 1000000000
out:
0
4000000000
-->

### Example 2 — All Manhattan Distances  ·  ★ ≈1600

- **Source:** [CSES 3411 · All Manhattan Distances](https://cses.fi/problemset/task/3411)
- **Difficulty:** ≈1600 (est.)
- **Problem:** $n\le2\cdot10^5$ distinct points with $\lvert x\rvert,\lvert y\rvert\le10^9$. Print the sum of Manhattan distances over all pairs.
- **Thinking from first principles:** The distance is a sum of two independent terms, so the total splits into
  $\sum_{i<j}\lvert x_i-x_j\rvert+\sum_{i<j}\lvert y_i-y_j\rvert$; each is the sorted-coefficient formula of §2. The trap is size:
  $\binom{2\cdot10^5}{2}\cdot4\cdot10^9\approx8\cdot10^{19}>2^{63}$. The answer needs 128-bit arithmetic.

<details><summary>Solution</summary>

`pairAbsSum` on $x$ and on $y$; print the 128-bit total (C++ has no `<<` for `__int128`, so convert manually). $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
__int128 pairAbsSum(vector<ll> a) {
    sort(a.begin(), a.end());
    __int128 s = 0, pre = 0;
    for (size_t k = 0; k < a.size(); k++) { s += (__int128)a[k] * (ll)k - pre; pre += a[k]; }
    return s;
}
string toString(__int128 v) {
    if (v == 0) return "0";
    string s;
    while (v > 0) { s += char('0' + (int)(v % 10)); v /= 10; }
    reverse(s.begin(), s.end());
    return s;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<ll> x(n), y(n);
    for (int i = 0; i < n; i++) cin >> x[i] >> y[i];
    cout << toString(pairAbsSum(x) + pairAbsSum(y)) << '\n';
}
```

```java
import java.util.*;
import java.io.*;
import java.math.BigInteger;

public class Main {
    static BigInteger pairAbsSum(long[] a) {
        // shuffle before a primitive sort to avoid the dual-pivot quicksort worst case
        Random rnd = new Random(12345);
        for (int i = a.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = a[i]; a[i] = a[j]; a[j] = t; }
        Arrays.sort(a);
        BigInteger total = BigInteger.ZERO;
        long acc = 0, pre = 0;
        for (int k = 0; k < a.length; k++) {
            acc += a[k] * k - pre;
            pre += a[k];
            if (acc > 4_000_000_000_000_000_000L) { total = total.add(BigInteger.valueOf(acc)); acc = 0; }
        }
        return total.add(BigInteger.valueOf(acc));
    }
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) readLong(in);
        long[] x = new long[n], y = new long[n];
        for (int i = 0; i < n; i++) { x[i] = readLong(in); y[i] = readLong(in); }
        System.out.println(pairAbsSum(x).add(pairAbsSum(y)));
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
0 0
2 1
-1 3
out:
12
-->
<!-- test
in:
1
5 5
out:
0
-->
<!-- test
in:
4
-1000000000 -1000000000
1000000000 1000000000
-1000000000 1000000000
1000000000 -1000000000
out:
16000000000
-->

### Example 3 — Minimum Euclidean Distance  ·  ★ ≈1900

- **Source:** [CSES 2194 · Minimum Euclidean Distance](https://cses.fi/problemset/task/2194)
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n\le2\cdot10^5$ distinct points, $\lvert x\rvert,\lvert y\rvert\le10^9$. Print $d^2$ for the minimum distance $d$.
- **Thinking from first principles:** All pairs is $2\cdot10^{10}$. The packing bound says that once a candidate distance $d$ is
  known, a new point has only $O(1)$ possible improvers in the $2d\times d$ box behind it — so sweep by $x$ with a $y$-ordered set.
  Keep everything as exact squared integers; the only floating operation is $\lceil\sqrt D\rceil$ for the window width, which may
  be safely over-estimated.

<details><summary>Solution</summary>

`closestPair2` from §3.1. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ld = long double;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<pair<ll, ll>> p(n);
    for (auto& [x, y] : p) cin >> x >> y;
    sort(p.begin(), p.end());
    set<pair<ll, ll>> act;                                 // (y, x); points are distinct
    ll best = LLONG_MAX;
    size_t left = 0;
    for (size_t i = 0; i < p.size(); i++) {
        ll d = (ll)ceill(sqrtl((ld)best));
        while (left < i && p[i].first - p[left].first > d) { act.erase({p[left].second, p[left].first}); left++; }
        for (auto it = act.lower_bound({p[i].second - d, LLONG_MIN}); it != act.end() && it->first <= p[i].second + d; ++it) {
            ll dx = p[i].first - it->second, dy = p[i].second - it->first;
            best = min(best, dx * dx + dy * dy);
        }
        act.insert({p[i].second, p[i].first});
    }
    cout << best << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long OFF = 1_100_000_000L, LIM = 1_000_000_000L;
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) readLong(in);
        long[] xs = new long[n], ys = new long[n];
        for (int i = 0; i < n; i++) { xs[i] = readLong(in); ys[i] = readLong(in); }
        Integer[] idx = new Integer[n];
        for (int i = 0; i < n; i++) idx[i] = i;
        Arrays.sort(idx, (a, b) -> xs[a] != xs[b] ? Long.compare(xs[a], xs[b]) : Long.compare(ys[a], ys[b]));
        TreeSet<Long> act = new TreeSet<>();
        long best = Long.MAX_VALUE;
        int left = 0;
        for (int k = 0; k < n; k++) {
            int i = idx[k];
            long d = (long) Math.ceil(Math.sqrt((double) best)) + 1;
            while (left < k && xs[i] - xs[idx[left]] > d) { act.remove(((ys[idx[left]] + OFF) << 32) | (xs[idx[left]] + OFF)); left++; }
            long lo = (Math.max(ys[i] - d, -LIM) + OFF) << 32, hi = ((Math.min(ys[i] + d, LIM) + OFF) << 32) | 0xFFFFFFFFL;
            for (long key : act.subSet(lo, true, hi, true)) {
                long dx = xs[i] - ((key & 0xFFFFFFFFL) - OFF), dy = ys[i] - ((key >>> 32) - OFF);
                best = Math.min(best, dx * dx + dy * dy);
            }
            act.add(((ys[i] + OFF) << 32) | (xs[i] + OFF));
        }
        System.out.println(best);
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
5
0 0
5 5
1 7
3 3
9 0
out:
8
-->
<!-- test
in:
2
-1000000000 -1000000000
1000000000 1000000000
out:
8000000000000000000
-->
<!-- test
in:
4
0 0
0 10
0 20
1 15
out:
26
-->

### Example 4 — Counting points in a Manhattan ball  ·  ★ ≈2000

- **Source:** Original problem.
- **Difficulty:** ≈2000 (est.)
- **Problem:** $n\le2\cdot10^5$ points and $q\le2\cdot10^5$ queries $(x,y,r)$, coordinates up to $10^9$, $0\le r\le4\cdot10^9$. For each query
  count the points with $\lvert x_i-x\rvert+\lvert y_i-y\rvert\le r$.
- **Thinking from first principles:** A Manhattan ball is a diamond — awkward for data structures. Rotating by $45^\circ$
  ($u=x+y$, $v=x-y$) turns it into the axis-aligned square $\lvert u_i-u\rvert\le r,\ \lvert v_i-v\rvert\le r$. Counting points in axis-aligned
  rectangles offline is the standard sweep: answer $=F(u+r)-F(u-r-1)$ where $F(a)$ counts points with $u_i\le a$ and $v_i$ in the
  range; sort points and "prefix events" by $u$, insert points into a Fenwick tree over compressed $v$.

<details><summary>Solution</summary>

Each query produces two prefix events $(a,\pm1)$. Process events in increasing $a$, inserting all points with $u_i\le a$ first.
Each Fenwick query counts $v_i\in[v-r,v+r]$ via binary search in the sorted $v$ list. $O((n+q)\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q; cin >> n >> q;
    vector<pair<ll, ll>> pts(n);                           // (u, v)
    vector<ll> vs(n);
    for (int i = 0; i < n; i++) { ll x, y; cin >> x >> y; pts[i] = {x + y, x - y}; vs[i] = x - y; }
    sort(pts.begin(), pts.end());
    sort(vs.begin(), vs.end());
    vs.erase(unique(vs.begin(), vs.end()), vs.end());
    int m = vs.size();
    vector<int> bit(m + 1, 0);
    auto add = [&](int i) { for (i++; i <= m; i += i & -i) bit[i]++; };
    auto pref = [&](int i) { int s = 0; for (; i > 0; i -= i & -i) s += bit[i]; return s; };   // count of first i values
    struct Ev { ll a, lo, hi; int id, sign; };
    vector<Ev> ev;
    for (int i = 0; i < q; i++) {
        ll x, y, r; cin >> x >> y >> r;
        ll u = x + y, v = x - y;
        ev.push_back({u + r, v - r, v + r, i, +1});
        ev.push_back({u - r - 1, v - r, v + r, i, -1});
    }
    sort(ev.begin(), ev.end(), [](const Ev& a, const Ev& b) { return a.a < b.a; });
    vector<ll> ans(q, 0);
    size_t j = 0;
    for (auto& e : ev) {
        while (j < pts.size() && pts[j].first <= e.a) { add(lower_bound(vs.begin(), vs.end(), pts[j].second) - vs.begin()); j++; }
        int L = lower_bound(vs.begin(), vs.end(), e.lo) - vs.begin(), R = upper_bound(vs.begin(), vs.end(), e.hi) - vs.begin();
        ans[e.id] += e.sign * (pref(R) - pref(L));
    }
    for (int i = 0; i < q; i++) cout << ans[i] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int lowerBound(long[] a, int len, long key) { int lo = 0, hi = len; while (lo < hi) { int mid = (lo + hi) >>> 1; if (a[mid] < key) lo = mid + 1; else hi = mid; } return lo; }
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) readLong(in), q = (int) readLong(in);
        long[][] pts = new long[n][];
        long[] vs = new long[n];
        for (int i = 0; i < n; i++) { long x = readLong(in), y = readLong(in); pts[i] = new long[]{x + y, x - y}; vs[i] = x - y; }
        Arrays.sort(pts, (a, b) -> Long.compare(a[0], b[0]));
        Long[] boxed = new Long[n];
        for (int i = 0; i < n; i++) boxed[i] = vs[i];
        Arrays.sort(boxed);                                  // object sort: immune to anti-quicksort inputs
        int m = 0;
        for (int i = 0; i < n; i++) if (m == 0 || boxed[i] != vs[m - 1]) vs[m++] = boxed[i];
        int[] bit = new int[m + 1];
        long[][] ev = new long[2 * q][];                     // {a, lo, hi, id, sign}
        for (int i = 0; i < q; i++) {
            long x = readLong(in), y = readLong(in), r = readLong(in), u = x + y, v = x - y;
            ev[2 * i] = new long[]{u + r, v - r, v + r, i, 1};
            ev[2 * i + 1] = new long[]{u - r - 1, v - r, v + r, i, -1};
        }
        Arrays.sort(ev, (a, b) -> Long.compare(a[0], b[0]));
        long[] ans = new long[q];
        int j = 0;
        for (long[] e : ev) {
            while (j < n && pts[j][0] <= e[0]) { for (int k = lowerBound(vs, m, pts[j][1]) + 1; k <= m; k += k & -k) bit[k]++; j++; }
            int L = lowerBound(vs, m, e[1]), R = lowerBound(vs, m, e[2] + 1);
            int s = 0;
            for (int k = R; k > 0; k -= k & -k) s += bit[k];
            for (int k = L; k > 0; k -= k & -k) s -= bit[k];
            ans[(int) e[3]] += e[4] * s;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < q; i++) sb.append(ans[i]).append('\n');
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
5 4
0 0
1 1
2 0
-1 3
5 5
0 0 0
0 0 2
1 1 3
0 0 100
out:
1
3
3
5
-->
<!-- test
in:
1 2
1000000000 -1000000000
-1000000000 1000000000 4000000000
-1000000000 1000000000 3999999999
out:
1
0
-->

### Example 5 — Tricky Function  ·  ★ 2200

- **Source:** [CF 429D · Tricky Function](https://codeforces.com/problemset/problem/429/D) — 2200
- **Difficulty:** 2200
- **Problem:** An array $a_1..a_n$ ($n\le10^5$, $\lvert a_i\rvert\le10^4$). For $i\ne j$ let $f(i,j)=(i-j)^2+g(i,j)^2$, where $g(i,j)$ is the
  sum of $a_k$ over $\min(i,j)<k\le\max(i,j)$. Print $\min f$.
- **Thinking from first principles:** $g(i,j)=S_j-S_i$ with prefix sums $S$ (sign irrelevant after squaring). So
  $f(i,j)=(i-j)^2+(S_i-S_j)^2$ — the squared distance between points $P_i=(i,S_i)$. The "array problem" is a closest pair
  in disguise. $\lvert S_i\rvert\le10^9$, squared distances $\le10^{18}$: 64-bit.

<details><summary>Solution</summary>

Closest pair of $(i,S_i)$, $i=1..n$. The points are already sorted by $x=i$. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ld = long double;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<ll> S(n + 1, 0);
    for (int i = 1; i <= n; i++) { ll a; cin >> a; S[i] = S[i - 1] + a; }
    set<pair<ll, ll>> act;                                 // (S_i, i)
    ll best = LLONG_MAX;
    int left = 1;
    for (int i = 1; i <= n; i++) {
        ll d = (ll)ceill(sqrtl((ld)best));
        while (left < i && i - left > d) { act.erase({S[left], left}); left++; }
        for (auto it = act.lower_bound({S[i] - d, LLONG_MIN}); it != act.end() && it->first <= S[i] + d; ++it) {
            ll dx = i - it->second, dy = S[i] - it->first;
            best = min(best, dx * dx + dy * dy);
        }
        act.insert({S[i], i});
    }
    cout << best << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        long[] S = new long[n + 1];
        for (int i = 1; i <= n; i++) { st.nextToken(); S[i] = S[i - 1] + (long) st.nval; }
        final long OFF = 2_000_000_000L;
        TreeSet<Long> act = new TreeSet<>();                // key = (S + OFF) * 2^20 + i, with i < 2^20
        long best = Long.MAX_VALUE;
        int left = 1;
        for (int i = 1; i <= n; i++) {
            long d = (long) Math.ceil(Math.sqrt((double) best)) + 1;
            while (left < i && i - left > d) { act.remove(((S[left] + OFF) << 20) | left); left++; }
            long lo = Math.max(S[i] - d + OFF, 0) << 20, hi = ((Math.min(S[i] + d, OFF) + OFF) << 20) | ((1 << 20) - 1);
            for (long key : act.subSet(lo, true, hi, true)) {
                long j = key & ((1 << 20) - 1), sj = (key >> 20) - OFF;
                long dx = i - j, dy = S[i] - sj;
                best = Math.min(best, dx * dx + dy * dy);
            }
            act.add(((S[i] + OFF) << 20) | i);
        }
        System.out.println(best);
    }
}
```

</details>

<!-- test
in:
4
1 0 0 -1
out:
1
-->
<!-- test
in:
2
1 -1
out:
2
-->
<!-- test
in:
3
10000 -10000 10000
out:
4
-->

### Example 6 — Area of a half-plane intersection  ·  ★ ≈2400

- **Source:** Original problem.
- **Difficulty:** ≈2400 (est.)
- **Problem:** $n\le10^5$ directed lines, each through two distinct integer points with coordinates $\le10^4$ in absolute value;
  each keeps the closed half-plane on its left. Intersect them all with the square $[-10^4,10^4]^2$ and print the area of the result
  ($0$ if it is empty or degenerate), absolute or relative error $10^{-6}$.
- **Thinking from first principles:** Clipping a polygon by each half-plane costs $O(n)$ each — $O(n^2)$. The region is convex, its
  edges appear in angular order of the lines, and a new line (in that order) can only remove vertices at the two ends of the
  current chain, so a deque gives $O(n\log n)$. The square is added as four more half-planes, which keeps every intermediate
  region bounded. Degenerate results (a point or a segment) come out as fewer than 3 lines or zero area.

<details><summary>Solution</summary>

`halfPlaneIntersection` from §3.2 with the four box half-planes, then the shoelace area. Coordinates are small, so `long double`
(C++) and `double` (Java) intersection points are accurate to $\sim10^{-9}$. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ld = long double;
const ld EPS = 1e-9;
struct PD { ld x, y; };
PD operator+(PD a, PD b) { return {a.x + b.x, a.y + b.y}; }
PD operator-(PD a, PD b) { return {a.x - b.x, a.y - b.y}; }
PD operator*(PD a, ld k) { return {a.x * k, a.y * k}; }
ld cross(PD a, PD b) { return a.x * b.y - a.y * b.x; }
ld dot(PD a, PD b) { return a.x * b.x + a.y * b.y; }
struct HP {
    PD p, d; ld ang;
    HP(PD p_, PD d_) : p(p_), d(d_), ang(atan2l(d_.y, d_.x)) {}
    bool out(PD q) const { return cross(d, q - p) < -EPS; }
};
PD inter(const HP& a, const HP& b) { return a.p + a.d * (cross(b.p - a.p, b.d) / cross(a.d, b.d)); }
vector<PD> hpi(vector<HP> h) {
    sort(h.begin(), h.end(), [](const HP& a, const HP& b) { return a.ang < b.ang; });
    deque<HP> dq;
    for (auto& cur : h) {
        while (dq.size() >= 2 && cur.out(inter(dq[dq.size() - 1], dq[dq.size() - 2]))) dq.pop_back();
        while (dq.size() >= 2 && cur.out(inter(dq[0], dq[1]))) dq.pop_front();
        if (!dq.empty() && fabsl(cross(cur.d, dq.back().d)) < EPS) {
            if (dot(cur.d, dq.back().d) < 0) return {};
            if (cur.out(dq.back().p)) { dq.pop_back(); dq.push_back(cur); }
            continue;
        }
        dq.push_back(cur);
    }
    while (dq.size() >= 3 && dq[0].out(inter(dq[dq.size() - 1], dq[dq.size() - 2]))) dq.pop_back();
    while (dq.size() >= 3 && dq[dq.size() - 1].out(inter(dq[0], dq[1]))) dq.pop_front();
    if (dq.size() < 3) return {};
    vector<PD> res;
    for (size_t i = 0; i < dq.size(); i++) res.push_back(inter(dq[i], dq[(i + 1) % dq.size()]));
    return res;
}
int main() {
    int n; cin >> n;
    vector<HP> h;
    for (int i = 0; i < n; i++) {
        ld x1, y1, x2, y2; cin >> x1 >> y1 >> x2 >> y2;
        h.emplace_back(PD{x1, y1}, PD{x2 - x1, y2 - y1});
    }
    const ld B = 10000;
    h.emplace_back(PD{-B, -B}, PD{1, 0}); h.emplace_back(PD{B, -B}, PD{0, 1});
    h.emplace_back(PD{B, B}, PD{-1, 0}); h.emplace_back(PD{-B, B}, PD{0, -1});
    vector<PD> poly = hpi(h);
    ld a2 = 0;
    for (size_t i = 0; i < poly.size(); i++) a2 += cross(poly[i], poly[(i + 1) % poly.size()]);
    cout << fixed << setprecision(6) << max((ld)0, a2 / 2) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final double EPS = 1e-9;
    static final class HP {
        final double px, py, dx, dy, ang;
        HP(double px, double py, double dx, double dy) { this.px = px; this.py = py; this.dx = dx; this.dy = dy; ang = Math.atan2(dy, dx); }
        boolean out(double[] q) { return dx * (q[1] - py) - dy * (q[0] - px) < -EPS; }
    }
    static double[] inter(HP a, HP b) {
        double t = ((b.px - a.px) * b.dy - (b.py - a.py) * b.dx) / (a.dx * b.dy - a.dy * b.dx);
        return new double[]{a.px + a.dx * t, a.py + a.dy * t};
    }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        List<HP> h = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            double[] v = new double[4];
            for (int k = 0; k < 4; k++) { st.nextToken(); v[k] = st.nval; }
            h.add(new HP(v[0], v[1], v[2] - v[0], v[3] - v[1]));
        }
        double B = 10000;
        h.add(new HP(-B, -B, 1, 0)); h.add(new HP(B, -B, 0, 1)); h.add(new HP(B, B, -1, 0)); h.add(new HP(-B, B, 0, -1));
        h.sort((a, b) -> Double.compare(a.ang, b.ang));
        HP[] dq = new HP[h.size()];                         // array deque: [head, tail)
        int head = 0, tail = 0;
        boolean empty = false;
        for (HP cur : h) {
            while (tail - head >= 2 && cur.out(inter(dq[tail - 1], dq[tail - 2]))) tail--;
            while (tail - head >= 2 && cur.out(inter(dq[head], dq[head + 1]))) head++;
            if (tail > head && Math.abs(cur.dx * dq[tail - 1].dy - cur.dy * dq[tail - 1].dx) < EPS) {
                if (cur.dx * dq[tail - 1].dx + cur.dy * dq[tail - 1].dy < 0) { empty = true; break; }
                if (cur.out(new double[]{dq[tail - 1].px, dq[tail - 1].py})) dq[tail - 1] = cur;
                continue;
            }
            dq[tail++] = cur;
        }
        double area2 = 0;
        if (!empty) {
            while (tail - head >= 3 && dq[head].out(inter(dq[tail - 1], dq[tail - 2]))) tail--;
            while (tail - head >= 3 && dq[tail - 1].out(inter(dq[head], dq[head + 1]))) head++;
            int k = tail - head;
            if (k >= 3) {
                double[][] poly = new double[k][];
                for (int i = 0; i < k; i++) poly[i] = inter(dq[head + i], dq[head + (i + 1) % k]);
                for (int i = 0; i < k; i++) area2 += poly[i][0] * poly[(i + 1) % k][1] - poly[i][1] * poly[(i + 1) % k][0];
            }
        }
        System.out.println(String.format(Locale.US, "%.6f", Math.max(0, area2 / 2)));
    }
}
```

</details>

<!-- test
in:
3
0 0 10 0
10 0 0 10
0 10 0 0
out:
50.000000
-->
<!-- test
in:
2
0 0 1 0
0 5 -1 5
out:
100000.000000
-->
<!-- test
in:
2
0 0 1 0
0 -1 -1 -1
out:
0.000000
-->
<!-- test
in:
4
0 0 1 1
1 0 0 1
-5 8 -5 7
3 -20 4 -20
out:
30.250000
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Closest pair: compare squared distances**, take a ceiling square root only for the window, and over-estimate it (`+1`)
   when using `double`.
2. **Duplicates** make the answer 0 — use a `multiset` (C++) or counted map (Java) if the statement allows them.
3. **Java `TreeSet<long[]>` with a comparator** works but is slow and makes `remove` depend on comparator ties; packing $(y,x)$
   into one `long` key is faster and exact.
4. **Manhattan rotation doubles the range**: $u=x+y$ is up to $2\cdot10^9$ — `int` overflow if you forget.
5. **Chebyshev → Manhattan halves**: $\max(\lvert\Delta x\rvert,\lvert\Delta y\rvert)=\frac{\lvert\Delta u\rvert+\lvert\Delta v\rvert}2$; with integer input
   $\lvert\Delta u\rvert+\lvert\Delta v\rvert$ is always even (same parity of $u$ and $v$), so integer division is exact.
6. **Rotated lattice has parity**: $(u,v)$ comes from an integer point iff $u\equiv v\pmod 2$ — matters when you construct a point
   in rotated space and map it back.
7. **Pair sums overflow**: $\sum_{i<j}\lvert\Delta\rvert$ for $2\cdot10^5$ points at $10^9$ is $\sim10^{19}$. Use `__int128`/`BigInteger`.
8. **Half-plane intersection**: always add a bounding box; treat same-direction parallel lines by keeping the inner one;
   opposite parallel lines that are adjacent in the deque mean "empty".
9. **Sorting by `atan2` in half-plane intersection** is fine for moderate coordinates; for $10^9$ coordinates use the exact polar
   comparator and `__int128` side tests.
10. **Java `Arrays.sort(long[])`** is a dual-pivot quicksort with an $O(n^2)$ adversarial case — shuffle first or sort boxed/objects.

---

## 7. Going further (toward 2400–2600+)

- **Manhattan + binary search + bipartiteness**: [CF 85E · Guard Towers](https://codeforces.com/problemset/problem/85/E) — 2600.
- **Manhattan triangles via the rotated grid**: [CF 1979E · Manhattan Triangle](https://codeforces.com/problemset/problem/1979/E) — 2400.
- **Rotated-coordinate range structures**: [AtCoder ABC233 Ex · Manhattan Christmas Tree ](https://atcoder.jp/contests/abc233/tasks/abc233_h) — diff≈2530
  (binary search on the radius + Example 4's counting).
- **Grid hashing for pairs within distance $K$**: [AtCoder ABC234 Ex · Enumerate Pairs](https://atcoder.jp/contests/abc234/tasks/abc234_h) — diff≈2505.
- **Max-weight Manhattan matching as a flow with four rotations**: [AtCoder AGC034 D · Manhattan Max Matching](https://atcoder.jp/contests/agc034/tasks/agc034_d) — diff≈3665
  ([min-cost flow](../12-Flows-and-Matching/04-min-cost-flow.md)).
- **Ordering points for a short Manhattan tour** (Hilbert / Mo-like strips): [CF 576C · Points on Plane](https://codeforces.com/problemset/problem/576/C) — 2100,
  and [Mo's algorithm](../08-Data-Structures/07-sqrt-decomposition-and-mos-algorithm.md).
- **Kinetic / time-sweep**: [CF 1710B · Rain](https://codeforces.com/problemset/problem/1710/B) — 2100 (piecewise-linear sums, max of $a_i-\lvert x-x_i\rvert$ via the rotation).

---

## 8. Practice ladder

**≤1400**
- [ ] [CF 1047B · Cover Points](https://codeforces.com/problemset/problem/1047/B) — 900
- [ ] [CF 1869B · 2D Traveling](https://codeforces.com/problemset/problem/1869/B) — 1100
- [ ] [CF 1648A · Weird Sum](https://codeforces.com/problemset/problem/1648/A) — 1400

**1400–1900**
- [ ] [CSES 3410 · Maximum Manhattan Distances](https://cses.fi/problemset/task/3410)
- [ ] [CSES 3411 · All Manhattan Distances](https://cses.fi/problemset/task/3411)
- [ ] [CF 1550C · Manhattan Subarrays](https://codeforces.com/problemset/problem/1550/C) — 1700
- [ ] [CSES 2194 · Minimum Euclidean Distance](https://cses.fi/problemset/task/2194)
- [ ] [CF 1689D · Lena and Matrix](https://codeforces.com/problemset/problem/1689/D) — 1900

**1900–2300**
- [ ] [CSES 1740 · Intersection Points](https://cses.fi/problemset/task/1740)
- [ ] [CSES 1741 · Area of Rectangles](https://cses.fi/problemset/task/1741)
- [ ] [CF 1044C · Optimal Polygon Perimeter](https://codeforces.com/problemset/problem/1044/C) — 2100
- [ ] [CF 576C · Points on Plane](https://codeforces.com/problemset/problem/576/C) — 2100
- [ ] [CF 1710B · Rain](https://codeforces.com/problemset/problem/1710/B) — 2100
- [ ] [CF 429D · Tricky Function](https://codeforces.com/problemset/problem/429/D) — 2200

**2400+**
- [ ] [CF 1979E · Manhattan Triangle](https://codeforces.com/problemset/problem/1979/E) — 2400
- [ ] [AtCoder ABC234 Ex · Enumerate Pairs](https://atcoder.jp/contests/abc234/tasks/abc234_h) — diff≈2505
- [ ] [AtCoder ABC233 Ex · Manhattan Christmas Tree ](https://atcoder.jp/contests/abc233/tasks/abc233_h) — diff≈2530
- [ ] [CF 85E · Guard Towers](https://codeforces.com/problemset/problem/85/E) — 2600

---

## 9. LeetCode / FAANG cross-reference

- [LC 1131 · Maximum of Absolute Value Expression](https://leetcode.com/problems/maximum-of-absolute-value-expression/) — Medium — expand absolute values into $\max$ over sign patterns (the rotation identity in 3D).
- [LC 3102 · Minimize Manhattan Distances](https://leetcode.com/problems/minimize-manhattan-distances/) — Hard — farthest pair via $u,v$ extremes; try removing each extreme point.
- [LC 1584 · Min Cost to Connect All Points](https://leetcode.com/problems/min-cost-to-connect-all-points/) — Medium — $n\le1000$: dense Prim is enough; the octant trick is the scalable answer.
- [LC 1266 · Minimum Time Visiting All Points](https://leetcode.com/problems/minimum-time-visiting-all-points/) — Easy — Chebyshev distance.
- [LC 973 · K Closest Points to Origin](https://leetcode.com/problems/k-closest-points-to-origin/) — Medium — squared norms + quickselect/heap.
- [LC 850 · Rectangle Area II](https://leetcode.com/problems/rectangle-area-ii/) — Hard — sweep line + coverage segment tree.
- [LC 1828 · Queries on Number of Points Inside a Circle](https://leetcode.com/problems/queries-on-number-of-points-inside-a-circle/) — Medium — brute force suffices; the Manhattan analogue is Example 4.

The rotation identity is the most interview-relevant idea in this file (LC 1131 and 3102 are standard FAANG hard questions).

---

## 10. Self-check

1. Prove that in the closest-pair strip each point needs at most 7 comparisons.
2. Why does the sweep version only need points with $x\ge x_{\text{cur}}-d$ and $y\in[y-d,y+d]$?
3. Derive $\lvert a\rvert+\lvert b\rvert=\max(\lvert a+b\rvert,\lvert a-b\rvert)$.
4. How do you compute the sum of pairwise **Chebyshev** distances in $O(n\log n)$?
5. In the deque half-plane algorithm, why can a new half-plane only remove vertices from the two ends?
6. Why is checking neighbours enough in Shamos–Hoey?
7. In Tricky Function, what is the "hidden geometry"?

<details><summary>Answers</summary>

1. A partner lies in a $2\delta\times\delta$ rectangle split into eight $\frac\delta2$-squares, each containing at most one point (two points in
   one square would be closer than $\delta$ on the same side); excluding $p$ leaves 7.
2. Any improving partner is at distance $<\sqrt D\le d$, hence within $d$ in both $x$ and $y$.
3. If $a,b$ have the same sign, $\lvert a\rvert+\lvert b\rvert=\lvert a+b\rvert\ge\lvert a-b\rvert$; otherwise $\lvert a\rvert+\lvert b\rvert=\lvert a-b\rvert\ge\lvert a+b\rvert$.
4. Rotate to $(u,v)$; Chebyshev $=\frac12(\lvert\Delta u\rvert+\lvert\Delta v\rvert)$, so it is half of the separable Manhattan pair sum in $(u,v)$.
5. The current boundary is a convex chain sorted by angle; the new half-plane has the largest angle, so the region it cuts off is
   contiguous along the chain, and contiguous on a cyclic chain whose ends meet means a suffix and/or a prefix.
6. Just before the leftmost intersection point the two intersecting segments are adjacent in the sweep order; adjacency is
   created by an insertion or a deletion, and both events test the new neighbours.
7. $f(i,j)$ is the squared Euclidean distance between $(i,S_i)$ and $(j,S_j)$, so the answer is a closest pair.

</details>
