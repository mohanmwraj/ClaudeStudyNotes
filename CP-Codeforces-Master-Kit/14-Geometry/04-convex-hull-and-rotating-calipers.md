# Convex hull, rotating calipers and Minkowski sums

> **Band:** 🔵 1700 – 🔴 2600 · **Priority:** 🔥 (hull, diameter) · ⚡ (Minkowski, width) · 🧊 (min-area rectangle) · **FAANG:** low · **Prerequisites:** [vectors and cross products](01-vectors-dot-cross-and-precision.md), [polygons](03-polygons-area-pick-point-in-polygon.md), [sorting](../01-Foundations/05-sorting-and-comparators.md)
> **You can say you know this when:** you can write Andrew's monotone chain with and without collinear points from memory,
> prove why each point is pushed and popped at most once, run rotating calipers for the diameter and width in $O(n)$,
> merge two convex polygons into their Minkowski sum, and recognise a hidden hull after a change of variables.

---

## 1. First principles — why this works

### 1.1 What the hull is, and why sorting is unavoidable

The convex hull of a point set $S$ is the smallest convex polygon containing $S$; its vertices are the points of $S$ that are
not convex combinations of others. Equivalently: $p$ is a hull vertex iff some direction $d$ makes $p$ the unique maximiser
of $d\cdot p$.

Brute force: an ordered pair $(p,q)$ is a hull edge iff all other points are on the left of $p\to q$: $O(n^3)$. We can do
$O(n\log n)$, and no better in general: hull of the points $(x_i,x_i^2)$ lists them in sorted order, so a faster hull
would sort faster than $\Omega(n\log n)$.

### 1.2 Andrew's monotone chain — derivation

Sort points by $(x,y)$. The leftmost point $p_0$ and the rightmost point $p_{n-1}$ are hull vertices and split the hull
into a **lower chain** and an **upper chain**, each $x$-monotone. Build the lower chain left to right with a stack:

> Before pushing $p$, pop the top $b$ (with $a$ below it) while $a\to b\to p$ does **not** turn left (cross $\le0$).

*Why a popped point is never needed again.* If $a\to b\to p$ turns right or goes straight, $b$ lies on or above segment
$ap$, and $a$, $p$ are both in the set. So $b$ is not a vertex of the lower hull of any superset — it can be discarded
forever. *Why the stack is exactly the lower hull of the prefix.* By induction: after processing $p$, consecutive triples in
the stack turn left (convex), and every discarded point lies above the chain. Each point is pushed once and popped at most
once, so the pass is $O(n)$; the sort dominates.

The upper chain is the same pass right to left. Concatenate both chains, dropping the duplicated endpoints. The result is
counter-clockwise, starting at the lexicographically smallest point.

**Collinear points.** With "pop while cross $\le0$" collinear points on hull edges are removed (strict hull, what you want
for calipers and Minkowski sums). With "pop while cross $<0$" they are kept (when the statement asks for *all* points on
the boundary). The keep-collinear version has one degenerate case: if **all** points are collinear, the upper pass
re-adds them in reverse; detect "all collinear" first and return the sorted points.

**Graham scan** sorts by polar angle around the lowest point instead and runs the same stack once. It needs the exact angular
comparator of [file 01](01-vectors-dot-cross-and-precision.md) and careful tie-breaking for collinear points with the pivot,
which is why Andrew's version (sort by coordinates) is the contest default.

### 1.3 Hulls of lattice points are small

A convex polygon with vertices in $\{0,\dots,C\}^2$ has $O(C^{2/3})$ vertices: its edge vectors are distinct primitive integer
directions (no two parallel edges in the same direction), and there are only $O(L^2)$ primitive vectors of length $\le L$
while the edge lengths sum to at most $4C$. Optimising gives $\Theta(C^{2/3})$. So with coordinates up to $10^6$ a hull has
at most about $10^4$ vertices — sometimes enough to justify an $O(h^2)$ step after building the hull.

### 1.4 Rotating calipers — the diameter in $O(n)$

The farthest pair of points is a pair of hull vertices (the distance to a fixed point is convex, so its maximum over a polygon
is at a vertex). Checking all pairs of hull vertices is $O(h^2)$.

Observation: for a hull edge $e_i=p_ip_{i+1}$, the vertex farthest from the line of $e_i$ — call it $p_{j(i)}$ — is where a line
parallel to $e_i$ last touches the polygon (a "caliper"). The two parallel lines through $e_i$ and $p_{j(i)}$ squeeze the
polygon, and **every farthest pair is among the pairs $(p_i,p_{j(i)})$, $(p_{i+1},p_{j(i)})$** (an antipodal pair: two
vertices admitting parallel supporting lines). As $i$ goes around counter-clockwise, the direction of $e_i$ rotates
monotonically, so $j(i)$ also only moves forward: two pointers, $O(h)$ total.

How to advance $j$ without computing distances: the height of $p_j$ above line $e_i$ is $\frac{e_i\times(p_j-p_i)}{\lvert e_i\rvert}$, and
moving from $j$ to $j+1$ changes it by $\frac{e_i\times(p_{j+1}-p_j)}{\lvert e_i\rvert}$. So advance while
$e_i\times e_j>0$ — pure integer arithmetic.

### 1.5 Width and minimum-area rectangle

The **width** (minimum distance between two parallel supporting lines) is attained with one line flush with a hull edge.
Let $n_\theta$ be the unit normal at angle $\theta$; the width in that direction is $w(\theta)=\max_p n_\theta\cdot p-\min_q n_\theta\cdot q$.
Between two consecutive angles at which a supporting line contains an edge, the two touching vertices $p,q$ are fixed, so
$w(\theta)=(p-q)\cdot n_\theta=\lvert p-q\rvert\cos(\theta-\varphi)$ for a constant $\varphi$ — a concave function on that interval
(cosine is concave where it is positive). A concave function attains its minimum at an endpoint of the interval, i.e. at an
angle where one supporting line is flush with an edge. So the width is
$\min_i \frac{e_i\times(p_{j(i)}-p_i)}{\lvert e_i\rvert}$ — the same calipers pass.

The **minimum-area enclosing rectangle** (🧊) also has a side flush with a hull edge (Freeman–Shapira). For edge $e_i$, keep
three pointers: the farthest point (height), and the points with maximum and minimum projection onto $e_i$ (length).
All three move monotonically: $O(h)$.

### 1.6 Minkowski sum

$P\oplus Q=\{p+q\}$. For convex $P,Q$ the sum is convex, and its boundary is traced by walking both boundaries "in parallel":
for any direction $d$, the extreme point of $P\oplus Q$ in direction $d$ is the sum of the extreme points of $P$ and $Q$
(because $\max_{p,q}d\cdot(p+q)=\max_p d\cdot p+\max_q d\cdot q$). As $d$ rotates, the extreme point of $P\oplus Q$ moves
along an edge of $P$ or of $Q$, whichever comes first in angular order. Hence:

> Start at the sum of the bottom-most (then left-most) vertices. Repeatedly append the edge vector of $P$ or of $Q$ with the
> smaller polar angle (both, if parallel). The result has at most $n+m$ vertices.

Applications: distance between convex polygons ($\min\lvert p-q\rvert$ = distance from the origin to $P\oplus(-Q)$), collision
tests, "translations $t$ with $P\cap(Q+t)\ne\varnothing$" $=P\oplus(-Q)$, and counting vertices of sums of many polygons
(each vertex of the sum corresponds to a distinct edge direction —
[CF 1195F · Geometers Anonymous Club](https://codeforces.com/problemset/problem/1195/F) — 2500).

### 1.7 The hull in disguise: convex hull trick

$\max_i(k_ix+b_i)=\max_i\,(k_i,b_i)\cdot(x,1)$ is "the extreme point of $\{(k_i,b_i)\}$ in direction $(x,1)$" — it is always a
vertex of the **upper hull** of the points $(k_i,b_i)$. That is the convex hull trick for DP
([CHT and Li Chao tree](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md)): the "lines" are hull points, and a
query is a binary search for the extreme point. Similarly, transformations like $(x,y)\mapsto(x,y-x^2)$ turn parabolas into
lines (Example 3).

---

## 2. Formulas, definitions and identities

| Fact | Formula / statement | Cost |
|---|---|---|
| Hull vertex test | $p$ is extreme in some direction $d$ | |
| Monotone chain pop rule | pop while $(b-a)\times(p-b)\le0$ (strict) or $<0$ (keep collinear) | $O(n)$ after sort |
| Hull lower bound | $\Omega(n\log n)$ (reduction from sorting) | |
| Lattice hull size | $O(C^{2/3})$ vertices in a $C\times C$ box | |
| Diameter | $\max_i\max(\lvert p_i-p_{j(i)}\rvert,\lvert p_{i+1}-p_{j(i)}\rvert)$, advance $j$ while $e_i\times e_j>0$ | $O(h)$ |
| Width | $\min_i\dfrac{e_i\times(p_{j(i)}-p_i)}{\lvert e_i\rvert}$ | $O(h)$ |
| Min-area rectangle | $\min_i\dfrac{\big(e_i\times(p_{j}-p_i)\big)\cdot\big(e_i\cdot(p_r-p_l)\big)}{\lvert e_i\rvert^2}$ | $O(h)$ |
| Minkowski sum | edges of $P$ and $Q$ merged by polar angle; $\lvert P\oplus Q\rvert\le n+m$ | $O(n+m)$ |
| Support function | $h_{P\oplus Q}(d)=h_P(d)+h_Q(d)$ with $h_P(d)=\max_{p\in P}d\cdot p$ | |
| Perimeter of Minkowski sum | $\operatorname{per}(P\oplus Q)=\operatorname{per}(P)+\operatorname{per}(Q)$ | |
| CHT duality | $\max_i(k_ix+b_i)$ = extreme point of $\{(k_i,b_i)\}$ in direction $(x,1)$ | |
| Diameter bound (integers) | $\lvert p-q\rvert^2\le(2C)^2\cdot2=8C^2$ | `long long` for $C=10^9$ |

**Perimeter identity derivation.** Every edge of $P\oplus Q$ is an edge of $P$, an edge of $Q$, or (for parallel edges) their
sum; each edge of $P$ and $Q$ is used exactly once. Summing lengths gives the identity. (Area does *not* add: by Steiner's
formula $\operatorname{area}(P\oplus tQ)$ is a quadratic polynomial in $t$, whose middle coefficient is twice the mixed area.)

---

## 3. Implementation (C++ and Java)

### 3.1 Convex hull, diameter, width, Minkowski sum

```cpp
struct P {
    ll x, y;
    P operator+(const P& o) const { return {x + o.x, y + o.y}; }
    P operator-(const P& o) const { return {x - o.x, y - o.y}; }
    bool operator<(const P& o) const { return x < o.x || (x == o.x && y < o.y); }
    bool operator==(const P& o) const { return x == o.x && y == o.y; }
};
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
ll cross(P o, P a, P b) { return cross(a - o, b - o); }
ll norm2(P a) { return a.x * a.x + a.y * a.y; }

// Counter-clockwise hull starting at the smallest point. keepCollinear: also return points on hull edges.
vector<P> convexHull(vector<P> p, bool keepCollinear = false) {
    sort(p.begin(), p.end());
    p.erase(unique(p.begin(), p.end()), p.end());
    int n = p.size();
    if (n <= 2) return p;
    if (keepCollinear) {
        bool allCol = true;
        for (int i = 1; i < n - 1 && allCol; i++) allCol = cross(p[0], p[n - 1], p[i]) == 0;
        if (allCol) return p;
    }
    vector<P> h(2 * n);
    int k = 0;
    auto bad = [&](const P& a, const P& b, const P& c) { ll v = cross(a, b, c); return keepCollinear ? v < 0 : v <= 0; };
    for (int i = 0; i < n; i++) { while (k >= 2 && bad(h[k - 2], h[k - 1], p[i])) k--; h[k++] = p[i]; }
    for (int i = n - 2, t = k + 1; i >= 0; i--) { while (k >= t && bad(h[k - 2], h[k - 1], p[i])) k--; h[k++] = p[i]; }
    h.resize(k - 1);
    return h;
}
// Squared diameter of a strict convex hull (CCW), rotating calipers.
ll diameter2(const vector<P>& h) {
    int n = h.size();
    if (n == 1) return 0;
    if (n == 2) return norm2(h[1] - h[0]);
    ll best = 0;
    for (int i = 0, j = 1; i < n; i++) {
        int ni = (i + 1) % n;
        while (cross(h[ni] - h[i], h[(j + 1) % n] - h[j]) > 0) j = (j + 1) % n;
        best = max({best, norm2(h[i] - h[j]), norm2(h[ni] - h[j])});
    }
    return best;
}
// Width of a strict convex hull with >= 3 vertices.
ld width(const vector<P>& h) {
    int n = h.size();
    ld best = 1e30L;
    for (int i = 0, j = 1; i < n; i++) {
        int ni = (i + 1) % n;
        P e = h[ni] - h[i];
        while (cross(e, h[(j + 1) % n] - h[j]) > 0) j = (j + 1) % n;
        best = min(best, (ld)cross(e, h[j] - h[i]) / sqrtl((ld)norm2(e)));
    }
    return best;
}
// Minkowski sum of two strictly convex CCW polygons.
vector<P> minkowski(vector<P> a, vector<P> b) {
    auto rot = [](vector<P>& p) {
        int k = 0;
        for (int i = 1; i < (int)p.size(); i++) if (p[i].y < p[k].y || (p[i].y == p[k].y && p[i].x < p[k].x)) k = i;
        rotate(p.begin(), p.begin() + k, p.end());
    };
    rot(a); rot(b);
    int n = a.size(), m = b.size();
    vector<P> res;
    int i = 0, j = 0;
    while (i < n || j < m) {
        res.push_back(a[i % n] + b[j % m]);
        P ea = a[(i + 1) % n] - a[i % n], eb = b[(j + 1) % m] - b[j % m];
        ll c = (i < n && j < m) ? cross(ea, eb) : (i < n ? 1 : -1);   // which edge has the smaller polar angle
        if (c >= 0) i++;
        if (c <= 0) j++;
    }
    return res;
}
```

```java
static final class P {
    final long x, y;
    P(long x, long y) { this.x = x; this.y = y; }
    P add(P o) { return new P(x + o.x, y + o.y); }
    P sub(P o) { return new P(x - o.x, y - o.y); }
}
static long cross(P a, P b) { return a.x * b.y - a.y * b.x; }
static long cross(P o, P a, P b) { return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x); }
static long norm2(P a) { return a.x * a.x + a.y * a.y; }

static List<P> convexHull(P[] pts, boolean keepCollinear) {
    P[] p = pts.clone();
    Arrays.sort(p, (u, v) -> u.x != v.x ? Long.compare(u.x, v.x) : Long.compare(u.y, v.y));
    int n = 0;
    for (int i = 0; i < p.length; i++) if (n == 0 || p[i].x != p[n - 1].x || p[i].y != p[n - 1].y) p[n++] = p[i];
    if (n <= 2) return new ArrayList<>(Arrays.asList(p).subList(0, n));
    if (keepCollinear) {
        boolean allCol = true;
        for (int i = 1; i < n - 1 && allCol; i++) allCol = cross(p[0], p[n - 1], p[i]) == 0;
        if (allCol) return new ArrayList<>(Arrays.asList(p).subList(0, n));
    }
    P[] h = new P[2 * n];
    int k = 0;
    for (int i = 0; i < n; i++) {
        while (k >= 2 && (keepCollinear ? cross(h[k - 2], h[k - 1], p[i]) < 0 : cross(h[k - 2], h[k - 1], p[i]) <= 0)) k--;
        h[k++] = p[i];
    }
    for (int i = n - 2, t = k + 1; i >= 0; i--) {
        while (k >= t && (keepCollinear ? cross(h[k - 2], h[k - 1], p[i]) < 0 : cross(h[k - 2], h[k - 1], p[i]) <= 0)) k--;
        h[k++] = p[i];
    }
    return new ArrayList<>(Arrays.asList(h).subList(0, k - 1));
}
static long diameter2(List<P> h) {
    int n = h.size();
    if (n == 1) return 0;
    if (n == 2) return norm2(h.get(1).sub(h.get(0)));
    long best = 0;
    for (int i = 0, j = 1; i < n; i++) {
        int ni = (i + 1) % n;
        while (cross(h.get(ni).sub(h.get(i)), h.get((j + 1) % n).sub(h.get(j))) > 0) j = (j + 1) % n;
        best = Math.max(best, Math.max(norm2(h.get(i).sub(h.get(j))), norm2(h.get(ni).sub(h.get(j)))));
    }
    return best;
}
static double width(List<P> h) {
    int n = h.size();
    double best = Double.MAX_VALUE;
    for (int i = 0, j = 1; i < n; i++) {
        P e = h.get((i + 1) % n).sub(h.get(i));
        while (cross(e, h.get((j + 1) % n).sub(h.get(j))) > 0) j = (j + 1) % n;
        best = Math.min(best, cross(e, h.get(j).sub(h.get(i))) / Math.sqrt((double) norm2(e)));
    }
    return best;
}
static List<P> minkowski(List<P> a0, List<P> b0) {
    List<P> a = rotBottom(a0), b = rotBottom(b0);
    int n = a.size(), m = b.size(), i = 0, j = 0;
    List<P> res = new ArrayList<>();
    while (i < n || j < m) {
        res.add(a.get(i % n).add(b.get(j % m)));
        P ea = a.get((i + 1) % n).sub(a.get(i % n)), eb = b.get((j + 1) % m).sub(b.get(j % m));
        long c = (i < n && j < m) ? cross(ea, eb) : (i < n ? 1 : -1);
        if (c >= 0) i++;
        if (c <= 0) j++;
    }
    return res;
}
static List<P> rotBottom(List<P> p) {
    int k = 0;
    for (int i = 1; i < p.size(); i++) if (p.get(i).y < p.get(k).y || (p.get(i).y == p.get(k).y && p.get(i).x < p.get(k).x)) k = i;
    List<P> r = new ArrayList<>(p.subList(k, p.size()));
    r.addAll(p.subList(0, k));
    return r;
}
```

### 3.2 Minimum-area enclosing rectangle (🧊), tested

Input: $n$ points. Output: the hull's width and the minimum area of an enclosing rectangle (any orientation).
Pointers are kept as unbounded counters (index `mod h`) so that "$l$ never falls behind $j$" is a simple `max`.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ld = long double;
struct P { ll x, y; bool operator<(const P& o) const { return x < o.x || (x == o.x && y < o.y); } };
P operator-(P a, P b) { return {a.x - b.x, a.y - b.y}; }
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
ll dot(P a, P b) { return a.x * b.x + a.y * b.y; }
vector<P> hull(vector<P> p) {
    sort(p.begin(), p.end());
    p.erase(unique(p.begin(), p.end(), [](P a, P b) { return a.x == b.x && a.y == b.y; }), p.end());
    int n = p.size(), k = 0;
    if (n <= 2) return p;
    vector<P> h(2 * n);
    for (int i = 0; i < n; i++) { while (k >= 2 && cross(h[k - 1] - h[k - 2], p[i] - h[k - 1]) <= 0) k--; h[k++] = p[i]; }
    for (int i = n - 2, t = k + 1; i >= 0; i--) { while (k >= t && cross(h[k - 1] - h[k - 2], p[i] - h[k - 1]) <= 0) k--; h[k++] = p[i]; }
    h.resize(k - 1);
    return h;
}
int main() {
    int n; cin >> n;
    vector<P> p(n);
    for (auto& q : p) cin >> q.x >> q.y;
    vector<P> h = hull(p);
    int m = h.size();
    cout << fixed << setprecision(6);
    if (m < 3) { cout << 0.0 << ' ' << 0.0 << '\n'; return 0; }
    auto at = [&](long long i) { return h[i % m]; };
    ld bestW = 1e30L, bestA = 1e30L;
    long long j = 1, r = 1, l = 1;
    for (long long i = 0; i < m; i++) {
        P e = at(i + 1) - at(i);
        j = max(j, i + 1); r = max(r, i + 1);
        while (cross(e, at(j + 1) - at(j)) > 0) j++;           // farthest from the edge line
        while (dot(e, at(r + 1) - at(r)) > 0) r++;             // max projection on e
        l = max(l, j);
        while (dot(e, at(l + 1) - at(l)) < 0) l++;             // min projection on e
        ld len2 = (ld)dot(e, e);
        ld hgt = (ld)cross(e, at(j) - at(i));
        bestW = min(bestW, hgt / sqrtl(len2));
        bestA = min(bestA, hgt * (ld)dot(e, at(r) - at(l)) / len2);
    }
    cout << bestW << ' ' << bestA << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long cr(long[] o, long[] a, long[] b) { return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]); }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        long[][] p = new long[n][2];
        for (int i = 0; i < n; i++) { st.nextToken(); p[i][0] = (long) st.nval; st.nextToken(); p[i][1] = (long) st.nval; }
        Arrays.sort(p, (a, b) -> a[0] != b[0] ? Long.compare(a[0], b[0]) : Long.compare(a[1], b[1]));
        long[][] h = new long[2 * n][];
        int k = 0;
        for (int i = 0; i < n; i++) { while (k >= 2 && cr(h[k - 2], h[k - 1], p[i]) <= 0) k--; h[k++] = p[i]; }
        for (int i = n - 2, t = k + 1; i >= 0; i--) { while (k >= t && cr(h[k - 2], h[k - 1], p[i]) <= 0) k--; h[k++] = p[i]; }
        int m = Math.max(k - 1, 1);
        if (m < 3) { System.out.println("0.000000 0.000000"); return; }
        double bestW = Double.MAX_VALUE, bestA = Double.MAX_VALUE;
        long j = 1, r = 1, l = 1;
        for (long i = 0; i < m; i++) {
            long[] a = h[(int) (i % m)], b = h[(int) ((i + 1) % m)];
            long ex = b[0] - a[0], ey = b[1] - a[1];
            j = Math.max(j, i + 1); r = Math.max(r, i + 1);
            while (true) { long[] u = h[(int) (j % m)], v = h[(int) ((j + 1) % m)]; if (ex * (v[1] - u[1]) - ey * (v[0] - u[0]) > 0) j++; else break; }
            while (true) { long[] u = h[(int) (r % m)], v = h[(int) ((r + 1) % m)]; if (ex * (v[0] - u[0]) + ey * (v[1] - u[1]) > 0) r++; else break; }
            l = Math.max(l, j);
            while (true) { long[] u = h[(int) (l % m)], v = h[(int) ((l + 1) % m)]; if (ex * (v[0] - u[0]) + ey * (v[1] - u[1]) < 0) l++; else break; }
            long[] pj = h[(int) (j % m)], pr = h[(int) (r % m)], pl = h[(int) (l % m)];
            double len2 = (double) (ex * ex + ey * ey);
            double hgt = (double) (ex * (pj[1] - a[1]) - ey * (pj[0] - a[0]));
            bestW = Math.min(bestW, hgt / Math.sqrt(len2));
            bestA = Math.min(bestA, hgt * (double) (ex * (pr[0] - pl[0]) + ey * (pr[1] - pl[1])) / len2);
        }
        System.out.println(String.format(Locale.US, "%.6f %.6f", bestW, bestA));
    }
}
```

<!-- test
in:
4
0 0
4 0
4 3
0 3
out:
3.000000 12.000000
-->
<!-- test
in:
4
0 0
2 2
4 0
2 -2
out:
2.828427 8.000000
-->
<!-- test
in:
5
0 0
10 0
5 1
3 0
7 0
out:
1.000000 10.000000
-->

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "smallest fence / polygon enclosing all points", "points on the boundary" | convex hull (keep collinear if "all points on the boundary") |
| "farthest pair", "diameter", "max distance between two points" | hull + rotating calipers |
| "thinnest strip", "minimum width", "fit through a corridor" | width via calipers |
| "smallest rectangle covering the points" | calipers with 4 pointers (side flush with an edge) |
| "sum of shapes", "all translations that collide", "vertices of $A+B$" | Minkowski sum: merge edges by angle |
| "maximise $a_ix+b_i$ over $i$" for many $x$ | upper hull of $(a_i,b_i)$ = convex hull trick |
| "parabolas $y=x^2+bx+c$ through points" | substitute $z=y-x^2$: lines in $(x,z)$ |
| "points with coordinates up to $10^6$, hull vertices" | lattice hull has $O(C^{2/3})$ vertices |

Confusions: "farthest pair" in **Manhattan** distance is not a hull problem — it is the $(x+y,x-y)$ rotation trick of
[sweep and distances](05-sweep-closest-pair-and-half-plane.md).

---

## 5. Worked examples (graded)

### Example 1 — Convex Hull (all boundary points)  ·  ★ ≈1800

- **Source:** [CSES 2195 · Convex Hull](https://cses.fi/problemset/task/2195)
- **Difficulty:** ≈1800 (est.)
- **Problem:** $n\le2\cdot10^5$ distinct points, $\lvert x\rvert,\lvert y\rvert\le10^9$, hull has positive area. Print the number of points
  on the hull boundary (vertices *and* points in the middle of edges), then the points (any order; here counter-clockwise
  from the smallest point).
- **Thinking from first principles:** Monotone chain with "pop while strictly right turn" keeps collinear points. The
  "all collinear" degenerate case is excluded by the statement (positive area), but the implementation handles it anyway.
  Cross products of differences up to $2\cdot10^9$ stay within $4\cdot10^{18}$ for the triangle form used here.

<details><summary>Solution</summary>

`convexHull(p, true)`. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
struct P { ll x, y; };
ll cross(P o, P a, P b) { return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x); }
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<P> p(n);
    for (auto& q : p) cin >> q.x >> q.y;
    sort(p.begin(), p.end(), [](P a, P b) { return a.x < b.x || (a.x == b.x && a.y < b.y); });
    vector<P> h(2 * n);
    int k = 0;
    for (int i = 0; i < n; i++) { while (k >= 2 && cross(h[k - 2], h[k - 1], p[i]) < 0) k--; h[k++] = p[i]; }
    for (int i = n - 2, t = k + 1; i >= 0; i--) { while (k >= t && cross(h[k - 2], h[k - 1], p[i]) < 0) k--; h[k++] = p[i]; }
    h.resize(k - 1);
    cout << h.size() << '\n';
    for (auto& q : h) cout << q.x << ' ' << q.y << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long cross(long[] o, long[] a, long[] b) { return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]); }
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) readLong(in);
        long[][] p = new long[n][];
        for (int i = 0; i < n; i++) p[i] = new long[]{readLong(in), readLong(in)};
        Arrays.sort(p, (a, b) -> a[0] != b[0] ? Long.compare(a[0], b[0]) : Long.compare(a[1], b[1]));
        long[][] h = new long[2 * n][];
        int k = 0;
        for (int i = 0; i < n; i++) { while (k >= 2 && cross(h[k - 2], h[k - 1], p[i]) < 0) k--; h[k++] = p[i]; }
        for (int i = n - 2, t = k + 1; i >= 0; i--) { while (k >= t && cross(h[k - 2], h[k - 1], p[i]) < 0) k--; h[k++] = p[i]; }
        StringBuilder sb = new StringBuilder();
        sb.append(k - 1).append('\n');
        for (int i = 0; i < k - 1; i++) sb.append(h[i][0]).append(' ').append(h[i][1]).append('\n');
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
6
0 0
2 0
4 0
2 2
1 1
3 1
out:
6
0 0
2 0
4 0
3 1
2 2
1 1
-->
<!-- test
in:
5
0 0
5 0
5 5
0 5
2 3
out:
4
0 0
5 0
5 5
0 5
-->
<!-- test
in:
4
-1000000000 -1000000000
1000000000 1000000000
0 0
1000000000 -1000000000
out:
4
-1000000000 -1000000000
1000000000 -1000000000
1000000000 1000000000
0 0
-->

### Example 2 — Farthest pair of points  ·  ★ ≈1900

- **Source:** Original problem.
- **Difficulty:** ≈1900 (est.)
- **Problem:** $n\le2\cdot10^5$ points (not necessarily distinct), $\lvert x\rvert,\lvert y\rvert\le10^9$. Print the maximum squared distance
  between two of them.
- **Thinking from first principles:** The squared distance to a fixed point is convex, so the maximum over the set is at a hull
  vertex; then for a fixed hull vertex the farthest partner is found by calipers. The answer is at most $8\cdot10^{18}$: fits in a
  signed 64-bit integer. Duplicates and $n\le2$ (hull of size 1 or 2) need the guard cases.

<details><summary>Solution</summary>

Strict hull, then `diameter2`. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
struct P { ll x, y; };
P operator-(P a, P b) { return {a.x - b.x, a.y - b.y}; }
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
ll norm2(P a) { return a.x * a.x + a.y * a.y; }
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<P> p(n);
    for (auto& q : p) cin >> q.x >> q.y;
    sort(p.begin(), p.end(), [](P a, P b) { return a.x < b.x || (a.x == b.x && a.y < b.y); });
    p.erase(unique(p.begin(), p.end(), [](P a, P b) { return a.x == b.x && a.y == b.y; }), p.end());
    n = p.size();
    vector<P> h;
    if (n <= 2) h = p;
    else {
        h.resize(2 * n);
        int k = 0;
        for (int i = 0; i < n; i++) { while (k >= 2 && cross(h[k - 1] - h[k - 2], p[i] - h[k - 1]) <= 0) k--; h[k++] = p[i]; }
        for (int i = n - 2, t = k + 1; i >= 0; i--) { while (k >= t && cross(h[k - 1] - h[k - 2], p[i] - h[k - 1]) <= 0) k--; h[k++] = p[i]; }
        h.resize(k - 1);
    }
    int m = h.size();
    ll best = 0;
    if (m == 2) best = norm2(h[1] - h[0]);
    else if (m >= 3)
        for (int i = 0, j = 1; i < m; i++) {
            int ni = (i + 1) % m;
            while (cross(h[ni] - h[i], h[(j + 1) % m] - h[j]) > 0) j = (j + 1) % m;
            best = max({best, norm2(h[i] - h[j]), norm2(h[ni] - h[j])});
        }
    cout << best << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long cross(long ax, long ay, long bx, long by) { return ax * by - ay * bx; }
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) readLong(in);
        long[][] p = new long[n][];
        for (int i = 0; i < n; i++) p[i] = new long[]{readLong(in), readLong(in)};
        Arrays.sort(p, (a, b) -> a[0] != b[0] ? Long.compare(a[0], b[0]) : Long.compare(a[1], b[1]));
        int u = 0;
        for (int i = 0; i < n; i++) if (u == 0 || p[i][0] != p[u - 1][0] || p[i][1] != p[u - 1][1]) p[u++] = p[i];
        n = u;
        long[][] h;
        int m;
        if (n <= 2) { h = p; m = n; }
        else {
            h = new long[2 * n][];
            int k = 0;
            for (int i = 0; i < n; i++) {
                while (k >= 2 && cross(h[k - 1][0] - h[k - 2][0], h[k - 1][1] - h[k - 2][1], p[i][0] - h[k - 1][0], p[i][1] - h[k - 1][1]) <= 0) k--;
                h[k++] = p[i];
            }
            for (int i = n - 2, t = k + 1; i >= 0; i--) {
                while (k >= t && cross(h[k - 1][0] - h[k - 2][0], h[k - 1][1] - h[k - 2][1], p[i][0] - h[k - 1][0], p[i][1] - h[k - 1][1]) <= 0) k--;
                h[k++] = p[i];
            }
            m = k - 1;
        }
        long best = 0;
        if (m == 2) best = d2(h[0], h[1]);
        else if (m >= 3)
            for (int i = 0, j = 1; i < m; i++) {
                int ni = (i + 1) % m, nj = (j + 1) % m;
                while (cross(h[ni][0] - h[i][0], h[ni][1] - h[i][1], h[nj][0] - h[j][0], h[nj][1] - h[j][1]) > 0) { j = nj; nj = (j + 1) % m; }
                best = Math.max(best, Math.max(d2(h[i], h[j]), d2(h[ni], h[j])));
            }
        System.out.println(best);
    }
    static long d2(long[] a, long[] b) { long dx = a[0] - b[0], dy = a[1] - b[1]; return dx * dx + dy * dy; }
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
3 4
1 1
-2 1
2 -1
out:
34
-->
<!-- test
in:
3
7 7
7 7
7 7
out:
0
-->
<!-- test
in:
4
-1000000000 -1000000000
1000000000 1000000000
5 5
1000000000 -1000000000
out:
8000000000000000000
-->

### Example 3 — U2  ·  ★ 2400

- **Source:** [CF 1142C · U2](https://codeforces.com/problemset/problem/1142/C) — 2400
- **Difficulty:** 2400
- **Problem:** $n\le10^5$ distinct points with $\lvert x\rvert,\lvert y\rvert\le10^6$. Through every two points with different $x$
  passes exactly one parabola $y=x^2+bx+c$. Count such parabolas (distinct curves) that have no given point strictly above them.
- **Thinking from first principles:** The $x^2$ term is the obstacle; subtract it. With $z=y-x^2$ the parabola becomes the
  **line** $z=bx+c$, and "point strictly above the parabola" becomes "point strictly above the line" (we subtracted the same
  $x^2$ from both sides). So we count lines through $\ge2$ transformed points with no point strictly above: these are exactly
  the **edges of the upper hull** of the transformed set, where collinear points on one edge give one line. For equal $x$ only
  the point with maximal $z$ can matter. Magnitudes: $z$ up to $\sim10^{12}$, cross products up to $8\cdot10^{18}$ — 64-bit, just.

<details><summary>Solution</summary>

Transform, keep max $z$ per $x$, build the upper hull right to left with "pop while cross $\le0$" (removes collinear points so
each line counts once), answer $=$ number of hull vertices $-1$. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<pair<ll, ll>> p(n);
    for (auto& [x, z] : p) { ll y; cin >> x >> y; z = y - x * x; }
    sort(p.begin(), p.end());
    vector<pair<ll, ll>> q;                                    // max z for each x
    for (int i = 0; i < n; i++) if (i + 1 == n || p[i + 1].first != p[i].first) q.push_back(p[i]);
    vector<pair<ll, ll>> h;
    for (int i = (int)q.size() - 1; i >= 0; i--) {             // right to left: upper hull is a left-turning chain
        while (h.size() >= 2) {
            auto [ax, az] = h[h.size() - 2];
            auto [bx, bz] = h.back();
            ll c = (bx - ax) * (q[i].second - bz) - (bz - az) * (q[i].first - bx);
            if (c <= 0) h.pop_back(); else break;
        }
        h.push_back(q[i]);
    }
    cout << (ll)h.size() - 1 << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        long[][] p = new long[n][];
        for (int i = 0; i < n; i++) {
            st.nextToken(); long x = (long) st.nval;
            st.nextToken(); long y = (long) st.nval;
            p[i] = new long[]{x, y - x * x};
        }
        Arrays.sort(p, (a, b) -> a[0] != b[0] ? Long.compare(a[0], b[0]) : Long.compare(a[1], b[1]));
        List<long[]> q = new ArrayList<>();
        for (int i = 0; i < n; i++) if (i + 1 == n || p[i + 1][0] != p[i][0]) q.add(p[i]);
        long[][] h = new long[q.size()][];
        int k = 0;
        for (int i = q.size() - 1; i >= 0; i--) {
            long[] c = q.get(i);
            while (k >= 2) {
                long[] a = h[k - 2], b = h[k - 1];
                long cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]);
                if (cr <= 0) k--; else break;
            }
            h[k++] = c;
        }
        System.out.println(k - 1);
    }
}
```

</details>

<!-- test
in:
3
-1 0
0 2
1 0
out:
2
-->
<!-- test
in:
5
1 0
1 -1
0 -1
-1 0
-1 -1
out:
1
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
0 0
1 1
2 4
3 9
out:
1
-->

### Example 4 — Area of a Minkowski sum  ·  ★ ≈2200

- **Source:** Original problem.
- **Difficulty:** ≈2200 (est.)
- **Problem:** Two strictly convex polygons $P$ ($n$ vertices) and $Q$ ($m$ vertices), each given counter-clockwise,
  $n,m\le10^5$, coordinates up to $10^8$. Print twice the area of $P\oplus Q$.
- **Thinking from first principles:** Brute force (hull of all $nm$ sums) is $10^{10}$. The support-function identity says the
  extreme point of the sum in any direction is the sum of the extreme points, so walking both boundaries by increasing edge
  angle traces the sum's boundary — $O(n+m)$. Start both walks at their bottom-most vertices, the extreme points in direction
  $(0,-1)$. Parallel edges are merged into one edge (advance both pointers), which keeps the output strictly convex.

<details><summary>Solution</summary>

`minkowski` from §3.1, then the shoelace formula. Coordinates of the sum are up to $2\cdot10^8$, the doubled area up to
$\sim1.6\cdot10^{17}$, and partial shoelace sums stay below $2^{63}$ for this range. $O(n+m)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
struct P { ll x, y; };
P operator+(P a, P b) { return {a.x + b.x, a.y + b.y}; }
P operator-(P a, P b) { return {a.x - b.x, a.y - b.y}; }
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
vector<P> readPoly() {
    int n; cin >> n;
    vector<P> p(n);
    for (auto& q : p) cin >> q.x >> q.y;
    int k = 0;
    for (int i = 1; i < n; i++) if (p[i].y < p[k].y || (p[i].y == p[k].y && p[i].x < p[k].x)) k = i;
    rotate(p.begin(), p.begin() + k, p.end());
    return p;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    vector<P> a = readPoly(), b = readPoly();
    int n = a.size(), m = b.size(), i = 0, j = 0;
    vector<P> s;
    while (i < n || j < m) {
        s.push_back(a[i % n] + b[j % m]);
        ll c = (i < n && j < m) ? cross(a[(i + 1) % n] - a[i % n], b[(j + 1) % m] - b[j % m]) : (i < n ? 1 : -1);
        if (c >= 0) i++;
        if (c <= 0) j++;
    }
    ll area2 = 0;
    for (size_t k = 0; k < s.size(); k++) area2 += cross(s[k], s[(k + 1) % s.size()]);
    cout << area2 << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
    static long next() throws IOException { st.nextToken(); return (long) st.nval; }
    static long[][] readPoly() throws IOException {
        int n = (int) next();
        long[][] p = new long[n][];
        for (int i = 0; i < n; i++) p[i] = new long[]{next(), next()};
        int k = 0;
        for (int i = 1; i < n; i++) if (p[i][1] < p[k][1] || (p[i][1] == p[k][1] && p[i][0] < p[k][0])) k = i;
        long[][] r = new long[n][];
        for (int i = 0; i < n; i++) r[i] = p[(i + k) % n];
        return r;
    }
    public static void main(String[] args) throws IOException {
        long[][] a = readPoly(), b = readPoly();
        int n = a.length, m = b.length, i = 0, j = 0;
        List<long[]> s = new ArrayList<>();
        while (i < n || j < m) {
            long[] pa = a[i % n], pb = b[j % m], qa = a[(i + 1) % n], qb = b[(j + 1) % m];
            s.add(new long[]{pa[0] + pb[0], pa[1] + pb[1]});
            long c = (i < n && j < m) ? (qa[0] - pa[0]) * (qb[1] - pb[1]) - (qa[1] - pa[1]) * (qb[0] - pb[0]) : (i < n ? 1 : -1);
            if (c >= 0) i++;
            if (c <= 0) j++;
        }
        long area2 = 0;
        for (int k = 0; k < s.size(); k++) {
            long[] u = s.get(k), v = s.get((k + 1) % s.size());
            area2 += u[0] * v[1] - u[1] * v[0];
        }
        System.out.println(area2);
    }
}
```

</details>

<!-- test
in:
4
0 0
1 0
1 1
0 1
3
0 0
2 0
0 2
out:
14
-->
<!-- test
in:
3
5 5
6 5
5 6
3
-1 -1
0 -1
-1 0
out:
4
-->
<!-- test
in:
4
0 0
2 0
2 1
0 1
4
0 0
1 0
1 3
0 3
out:
24
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Decide collinear policy before coding.** "All points on the fence" → keep (`< 0`); calipers/Minkowski/CHT → strict (`<= 0`).
2. **Keep-collinear + all points collinear** returns duplicates unless special-cased.
3. **Duplicates** make `cross == 0` everywhere: `unique` after sorting, or the strict hull may degenerate.
4. **Hull of $\le2$ points** — calipers loop forever or index out of range; guard $h\le2$.
5. **Calipers advance condition** uses edge vectors, not distances: `cross(e_i, e_j) > 0`. Using `>=` can spin forever on
   parallel edges.
6. **Squared distances only**: the diameter is $\sqrt{\max d^2}$ — compute in integers, take one square root at the end.
7. **Overflow**: coordinates $10^9$ → squared distance $8\cdot10^{18}$ (fits), but the *sum* of two such values does not.
8. **Minkowski start vertex**: both polygons must start at the extreme point in the *same* direction (bottom-most, then
   left-most) and be counter-clockwise.
9. **Java sorting**: `Arrays.sort(long[][])` with a comparator is a stable merge sort (no anti-quicksort worry), but boxing-free
   parallel primitive arrays are faster — sort an index array or pack $(x,y)$ into one `long` when coordinates are small.
10. **Recognise transforms**: $z=y-x^2$ (parabolas), $(k,b)$ duality (lines ↔ points), $(x+y,x-y)$ (Manhattan) turn
    non-geometric statements into hull problems.

---

## 7. Going further (toward 2400–2600+)

- **Dynamic hull** (insertions with queries "is the point inside"): two ordered sets for the upper and lower chains —
  [CF 70D · Professor's task](https://codeforces.com/problemset/problem/70/D) — 2700.
- **Hull + string matching**: two convex polygons are congruent up to rotation iff the cyclic sequences
  (edge length², angle encoded by dot/cross) match — [CF 1017E · The Supersonic Rocket](https://codeforces.com/problemset/problem/1017/E) — 2400
  (uses [KMP](../11-Strings/02-prefix-function-kmp.md)).
- **Offline hull of a time-varying set**: segment tree on time with hulls in nodes —
  [CF 678F · Lena and Queries](https://codeforces.com/problemset/problem/678/F) — 2500, see
  [segment tree on time](../16-IGM-Frontier/02-segment-tree-on-time-and-dsu-rollback.md).
- **Minkowski sums at scale**: [CF 1195F · Geometers Anonymous Club](https://codeforces.com/problemset/problem/1195/F) — 2500
  (vertices of a sum = distinct normalised edge directions → offline distinct-values-in-range with a Fenwick tree).
- **CHT / Li Chao**: [CSES 3429 · Lines and Queries I](https://cses.fi/problemset/task/3429),
  [CSES 3430 · Lines and Queries II](https://cses.fi/problemset/task/3430) — the upper envelope view of §1.7.
- **3D hull** ($O(n\log n)$ randomised incremental, or $O(n^2)$ gift wrapping) is ICPC material; on Codeforces it is
  very rare.

---

## 8. Practice ladder

**1400–1900**
- [ ] [CSES 2195 · Convex Hull](https://cses.fi/problemset/task/2195)
- [ ] [LC 587 · Erect the Fence](https://leetcode.com/problems/erect-the-fence/) — Hard
- [ ] [CF 1299B · Aerodynamic](https://codeforces.com/problemset/problem/1299/B) — 1800

**1900–2300**
- [ ] [CF 166B · Polygons](https://codeforces.com/problemset/problem/166/B) — 2100
- [ ] [CF 340B · Maximal Area Quadrilateral](https://codeforces.com/problemset/problem/340/B) — 2100
- [ ] [CF 319C · Kalila and Dimna in the Logging Industry](https://codeforces.com/problemset/problem/319/C) — 2100
- [ ] [CSES 3427 · Line Segments Trace I](https://cses.fi/problemset/task/3427)
- [ ] [CSES 3429 · Lines and Queries I](https://cses.fi/problemset/task/3429)

**2400+**
- [ ] [CF 1142C · U2](https://codeforces.com/problemset/problem/1142/C) — 2400
- [ ] [CF 1083E · The Fair Nut and Rectangles](https://codeforces.com/problemset/problem/1083/E) — 2400
- [ ] [CF 1017E · The Supersonic Rocket](https://codeforces.com/problemset/problem/1017/E) — 2400
- [ ] [CSES 3428 · Line Segments Trace II](https://cses.fi/problemset/task/3428)
- [ ] [CSES 3430 · Lines and Queries II](https://cses.fi/problemset/task/3430)
- [ ] [CF 1195F · Geometers Anonymous Club](https://codeforces.com/problemset/problem/1195/F) — 2500
- [ ] [CF 678F · Lena and Queries](https://codeforces.com/problemset/problem/678/F) — 2500
- [ ] [CF 70D · Professor's task](https://codeforces.com/problemset/problem/70/D) — 2700
- [ ] [CF 932F · Escape Through Leaf](https://codeforces.com/problemset/problem/932/F) — 2700

---

## 9. LeetCode / FAANG cross-reference

- [LC 587 · Erect the Fence](https://leetcode.com/problems/erect-the-fence/) — Hard — monotone chain keeping collinear points; the "all collinear" trap is in the tests.
- [LC 1924 · Erect the Fence II](https://leetcode.com/problems/erect-the-fence-ii/) — Hard 🔒 — minimum enclosing circle ([file 06](06-circles-and-advanced-geometry.md)).
- [LC 963 · Minimum Area Rectangle II](https://leetcode.com/problems/minimum-area-rectangle-ii/) — Medium — rectangles from point pairs sharing midpoint and length; not calipers, but the same "rectangle from geometry" thinking.
- [LC 469 · Convex Polygon](https://leetcode.com/problems/convex-polygon/) — Medium 🔒 — convexity by consecutive cross products.

Convex hull is rare in interviews (LC 587 is the one that appears); the CHT duality is never asked.

---

## 10. Self-check

1. Prove that a point popped during the monotone chain is never a hull vertex.
2. Why is Andrew's algorithm $O(n)$ after sorting?
3. What changes to keep collinear boundary points, and which input breaks the naive version of that change?
4. Why does the calipers pointer $j$ only move forward?
5. Give the support-function argument that the Minkowski sum of convex polygons has at most $n+m$ vertices.
6. In U2, why does subtracting $x^2$ preserve "strictly above"?
7. Why must the minimum-area rectangle have a side on a hull edge (state the result you rely on)?

<details><summary>Answers</summary>

1. When $b$ is popped because $a\to b\to p$ is not a left turn, $b$ lies on or above segment $ap$ with $a,p$ in the set, so it is
   not strictly extreme downward in any direction for the lower chain; nothing added later changes that.
2. Every point is pushed once and popped at most once; the inner `while` is amortised.
3. Pop only on strict right turns (`< 0`). If all points are collinear, the upper pass re-adds the interior points in reverse
   and the output contains duplicates — special-case it.
4. The edge direction $e_i$ rotates monotonically counter-clockwise, and the vertex of maximal height in direction
   $\operatorname{perp}(e_i)$ rotates with it.
5. $h_{P\oplus Q}(d)=h_P(d)+h_Q(d)$; the maximiser of the sum changes only when the maximiser of $P$ or of $Q$ changes, which
   happens at the $n$ edge normals of $P$ and the $m$ of $Q$.
6. $y>x^2+bx+c \iff y-x^2>bx+c$: the same quantity is subtracted from both sides.
7. The Freeman–Shapira theorem: some minimum-area enclosing rectangle has a side collinear with an edge of the hull; so trying
   each edge with calipers suffices.

</details>
