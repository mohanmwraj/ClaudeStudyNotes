# Lines, segments and intersections

> **Band:** 🔵 1500–2400 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [vectors, dot, cross and precision](01-vectors-dot-cross-and-precision.md)
> **You can say you know this when:** you can write an exact segment-intersection test that handles touching and
> collinear-overlap cases, derive the intersection parameter $t=\frac{(C-A)\times e}{d\times e}$ on the spot, and compute
> point–segment and segment–segment distances without special-casing vertical lines.

---

## 1. First principles — why this works

### 1.1 Choosing a representation

A line can be stored three ways. Which one you pick decides how much casework you write.

| Representation | Stored as | Good for | Bad for |
|---|---|---|---|
| Two points / point + direction | $A$, $d=B-A$; points $A+td$ | intersections, projections, segments ($t\in[0,1]$) | equality/hashing of lines |
| Implicit $ax+by=c$ | integers $(a,b,c)$, normal $(a,b)$ | side tests, hashing, half-planes | constructing points |
| Slope-intercept $y=kx+m$ | $k,m$ | lines given that way in the statement | vertical lines, precision |

Conversions (all exact for integer input): from $A,B$ take $d=B-A$, normal $n=(a,b)=(-d_y,d_x)=\operatorname{perp}(d)$,
$c=n\cdot A$. Then $ax+by-c=n\cdot(P-A)=d\times(P-A)$: **the implicit form's value is the cross product**, so its sign is the
side of the line, and $\lvert ax+by-c\rvert/\lvert n\rvert$ is the distance.

**Canonical form for hashing lines** (count distinct lines, group collinear points): divide $(a,b,c)$ by
$\gcd(\lvert a\rvert,\lvert b\rvert,\lvert c\rvert)$ and fix the sign so that the first non-zero of $(a,b)$ is positive. For
*directions* only, normalise $(d_x,d_y)$ by $\gcd(\lvert d_x\rvert,\lvert d_y\rvert)$ with the same sign rule.

### 1.2 Intersecting two lines — derive, don't memorise

Lines $A+td$ and $C+se$. We want $t$ with $A+td=C+se$. The unknown $s$ is in the way; kill it by crossing both sides
with $e$ (because $e\times e=0$):

$$(A+td)\times e=(C+se)\times e \;\Longrightarrow\; A\times e+t\,(d\times e)=C\times e \;\Longrightarrow\; t=\frac{(C-A)\times e}{d\times e}.$$

- $d\times e=0$ ⇒ parallel. They coincide iff additionally $(C-A)\times d=0$.
- Symmetrically $s=\frac{(C-A)\times d}{d\times e}$ (cross with $d$ instead).
- For **segments** $AB$, $CD$ ($d=B-A$, $e=D-C$): they intersect at a single point iff $d\times e\ne0$ and
  $0\le t\le1$, $0\le s\le1$. With integers, compare numerators against $0$ and the denominator without dividing
  (flip signs so the denominator is positive first).

The intersection point $A+td$ is rational: numerator of order $C^3$ over a denominator of order $C^2$. For exact work
with $C=10^9$ the numerators need `__int128`; for output, `long double` is fine.

### 1.3 Segment intersection as a predicate

Often only *whether* two segments meet is asked. Avoid division entirely with orientations.
Let $o_1=\operatorname{orient}(A,B,C)$, $o_2=\operatorname{orient}(A,B,D)$, $o_3=\operatorname{orient}(C,D,A)$, $o_4=\operatorname{orient}(C,D,B)$.

- **Proper crossing**: $o_1o_2<0$ and $o_3o_4<0$ — $C,D$ are strictly on opposite sides of line $AB$ and vice versa, so
  each segment crosses the other's line inside the other segment.
- **Touching / collinear**: if some $o_k=0$, that endpoint lies on the other segment's *line*; the segments meet iff it lies on
  the other *segment*.

Why is that the complete list? Suppose no proper crossing and, say, $o_3=0$ but $o_4\ne0$. Then $AB$ meets line $CD$ only at
$A$ (a segment not contained in a line meets it at most once), so the segments meet iff $A\in CD$. If both $o_3=o_4=0$, the
segments are collinear; two collinear segments overlap iff one of the four endpoints lies on the other segment. And if all
$o_k\ne0$ but some product is positive, one segment is entirely on one side of the other's line: no intersection.

**Point on segment**: $P\in AB \iff (B-A)\times(P-A)=0$ and $(A-P)\cdot(B-P)\le0$ (the angle $APB$ is $180^\circ$, or $P$ is
an endpoint). The dot test replaces bounding-box checks and works for vertical segments too.

### 1.4 Distances

**Point to line.** Parallelogram area divided by base: $\operatorname{dist}(P,AB)=\frac{\lvert (B-A)\times(P-A)\rvert}{\lvert B-A\rvert}$.

**Point to segment.** The closest point of the *line* is the projection with parameter
$t^*=\frac{(P-A)\cdot(B-A)}{\lvert B-A\rvert^2}$. The squared distance $f(t)=\lvert A+t(B-A)-P\rvert^2$ is a convex parabola in $t$,
so on $[0,1]$ its minimum is at $\operatorname{clamp}(t^*,0,1)$. In words: if the projection falls outside, the nearest
endpoint wins.

**Segment to segment.** If they intersect, $0$. Otherwise the minimum over the parameter square $[0,1]^2$ of
$\lvert P(t)-Q(s)\rvert$ is attained with at least one parameter at $0$ or $1$: at an interior minimum both partial
derivatives vanish, i.e. $P-Q$ is perpendicular to both directions, which in 2D forces the segments to be parallel —
and then sliding along them keeps the distance constant until an endpoint is reached. Hence

$$\operatorname{dist}(AB,CD)=\min\{\operatorname{dist}(A,CD),\operatorname{dist}(B,CD),\operatorname{dist}(C,AB),\operatorname{dist}(D,AB)\}.$$

(In 3D this is false — skew segments can have both closest points interior.)

### 1.5 Lines given as $y=kx+m$

When a statement *gives* lines in slope form with integer $k,m$, the comparison "which line is higher at $x=x_0$" is just
$k_1x_0+m_1$ vs $k_2x_0+m_2$, exact in integers. Two such lines cross between $x_1$ and $x_2$ iff their order at $x_1$ differs
from their order at $x_2$ — the idea behind Example 3 and behind kinetic/sweep arguments in general.

---

## 2. Formulas, definitions and identities

| Formula | Meaning | Notes |
|---|---|---|
| $P(t)=A+t(B-A)$ | parametric line; segment for $t\in[0,1]$, ray for $t\ge0$ | |
| $n=\operatorname{perp}(B-A)=(-(B_y-A_y),\,B_x-A_x)$, $c=n\cdot A$ | implicit $n\cdot P=c$ | $n\cdot P-c=(B-A)\times(P-A)$ |
| $t=\dfrac{(C-A)\times e}{d\times e}$, $s=\dfrac{(C-A)\times d}{d\times e}$ | line–line intersection parameters | $d\times e=0$: parallel |
| $P\in AB \iff (B-A)\times(P-A)=0 \wedge (A-P)\cdot(B-P)\le0$ | point on segment | exact |
| $\operatorname{dist}(P,\text{line }AB)=\dfrac{\lvert(B-A)\times(P-A)\rvert}{\lvert B-A\rvert}$ | area / base | |
| $t^*=\operatorname{clamp}\!\Big(\dfrac{(P-A)\cdot(B-A)}{\lvert B-A\rvert^2},0,1\Big)$ | closest point of segment | convex parabola |
| $\operatorname{dist}(AB,CD)=0$ if intersecting, else min of 4 endpoint distances | segment–segment | 2D only |
| Lattice points on segment $AB$: $\gcd(\lvert\Delta x\rvert,\lvert\Delta y\rvert)+1$ | endpoints included | step $=\frac{(\Delta x,\Delta y)}{g}$ |
| Angle between lines with directions $d,e$: $\operatorname{atan2}(\lvert d\times e\rvert, d\cdot e)$ | in $[0,\pi]$; for undirected lines take $\min(\theta,\pi-\theta)$ | |
| Foot of perpendicular from $P$: $A+t^*_{\text{unclamped}}(B-A)$ | projection | |

**Lattice points on a segment — derivation.** With $g=\gcd(\lvert\Delta x\rvert,\lvert\Delta y\rvert)$ and primitive step
$u=(\Delta x/g,\Delta y/g)$, a point $A+\lambda(B-A)$ is a lattice point iff $\lambda g\cdot u$ is integral; since
$\gcd(u_x,u_y)=1$, Bézout gives integers $\alpha,\beta$ with $\alpha u_x+\beta u_y=1$, so $\lambda g=\alpha(\lambda g u_x)+\beta(\lambda g u_y)$ is
an integer. Hence the lattice points are exactly $A+ku$ for $k=0,\dots,g$.

---

## 3. Implementation (C++ and Java)

### 3.1 Exact predicates and floating constructions

```cpp
struct P { ll x, y; };
P operator-(P a, P b) { return {a.x - b.x, a.y - b.y}; }
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
ll dot(P a, P b) { return a.x * b.x + a.y * b.y; }
int sgn(ll v) { return (v > 0) - (v < 0); }
int orient(P a, P b, P c) { return sgn(cross(b - a, c - a)); }
bool onSegment(P a, P b, P p) { return cross(b - a, p - a) == 0 && dot(a - p, b - p) <= 0; }
bool segIntersect(P a, P b, P c, P d) {
    int o1 = orient(a, b, c), o2 = orient(a, b, d), o3 = orient(c, d, a), o4 = orient(c, d, b);
    if (o1 * o2 < 0 && o3 * o4 < 0) return true;                       // proper crossing
    return (o1 == 0 && onSegment(a, b, c)) || (o2 == 0 && onSegment(a, b, d)) ||
           (o3 == 0 && onSegment(c, d, a)) || (o4 == 0 && onSegment(c, d, b));
}
// Intersection point of lines AB and CD (caller ensures they are not parallel).
pair<ld, ld> lineIntersection(P a, P b, P c, P d) {
    P u = b - a, v = d - c;
    ld t = (ld)cross(c - a, v) / cross(u, v);
    return {a.x + t * u.x, a.y + t * u.y};
}
ld distPointSegment(P p, P a, P b) {
    P d = b - a;
    ld len2 = dot(d, d);
    ld t = len2 == 0 ? 0 : max((ld)0, min((ld)1, dot(p - a, d) / len2));
    ld qx = a.x + t * d.x - p.x, qy = a.y + t * d.y - p.y;
    return sqrtl(qx * qx + qy * qy);
}
ld distSegSeg(P a, P b, P c, P d) {
    if (segIntersect(a, b, c, d)) return 0;
    return min({distPointSegment(a, c, d), distPointSegment(b, c, d), distPointSegment(c, a, b), distPointSegment(d, a, b)});
}
```

```java
static long cross(long ax, long ay, long bx, long by) { return ax * by - ay * bx; }
static int orient(long[] a, long[] b, long[] c) {
    return Long.signum(cross(b[0] - a[0], b[1] - a[1], c[0] - a[0], c[1] - a[1]));
}
static boolean onSegment(long[] a, long[] b, long[] p) {
    return cross(b[0] - a[0], b[1] - a[1], p[0] - a[0], p[1] - a[1]) == 0
        && (a[0] - p[0]) * (b[0] - p[0]) + (a[1] - p[1]) * (b[1] - p[1]) <= 0;
}
static boolean segIntersect(long[] a, long[] b, long[] c, long[] d) {
    int o1 = orient(a, b, c), o2 = orient(a, b, d), o3 = orient(c, d, a), o4 = orient(c, d, b);
    if (o1 * o2 < 0 && o3 * o4 < 0) return true;
    return (o1 == 0 && onSegment(a, b, c)) || (o2 == 0 && onSegment(a, b, d))
        || (o3 == 0 && onSegment(c, d, a)) || (o4 == 0 && onSegment(c, d, b));
}
static double[] lineIntersection(long[] a, long[] b, long[] c, long[] d) {
    long ux = b[0] - a[0], uy = b[1] - a[1], vx = d[0] - c[0], vy = d[1] - c[1];
    double t = (double) cross(c[0] - a[0], c[1] - a[1], vx, vy) / cross(ux, uy, vx, vy);
    return new double[]{a[0] + t * ux, a[1] + t * uy};
}
static double distPointSegment(long[] p, long[] a, long[] b) {
    long dx = b[0] - a[0], dy = b[1] - a[1];
    double len2 = (double) dx * dx + (double) dy * dy;
    double t = len2 == 0 ? 0 : Math.max(0, Math.min(1, ((double) (p[0] - a[0]) * dx + (double) (p[1] - a[1]) * dy) / len2));
    double qx = a[0] + t * dx - p[0], qy = a[1] + t * dy - p[1];
    return Math.sqrt(qx * qx + qy * qy);
}
static double distSegSeg(long[] a, long[] b, long[] c, long[] d) {
    if (segIntersect(a, b, c, d)) return 0;
    return Math.min(Math.min(distPointSegment(a, c, d), distPointSegment(b, c, d)),
                    Math.min(distPointSegment(c, a, b), distPointSegment(d, a, b)));
}
```

### 3.2 Canonical line / direction (for hashing)

```cpp
// Direction of the line through two distinct integer points, normalised so equal lines-through-a-point compare equal.
pair<ll, ll> canonDir(ll dx, ll dy) {
    ll g = gcd(llabs(dx), llabs(dy));
    dx /= g; dy /= g;
    if (dx < 0 || (dx == 0 && dy < 0)) { dx = -dx; dy = -dy; }
    return {dx, dy};
}
// Whole line a*x + b*y = c through P and Q, as a canonical triple.
array<ll, 3> canonLine(ll px, ll py, ll qx, ll qy) {
    ll a = qy - py, b = px - qx, c = a * px + b * py;
    ll g = gcd(gcd(llabs(a), llabs(b)), llabs(c));
    a /= g; b /= g; c /= g;
    if (a < 0 || (a == 0 && b < 0)) { a = -a; b = -b; c = -c; }
    return {a, b, c};
}
```

```java
static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return Math.abs(a); }
static long[] canonDir(long dx, long dy) {
    long g = gcd(Math.abs(dx), Math.abs(dy));
    dx /= g; dy /= g;
    if (dx < 0 || (dx == 0 && dy < 0)) { dx = -dx; dy = -dy; }
    return new long[]{dx, dy};
}
static long[] canonLine(long px, long py, long qx, long qy) {
    long a = qy - py, b = px - qx, c = a * px + b * py;
    long g = gcd(gcd(Math.abs(a), Math.abs(b)), Math.abs(c));
    a /= g; b /= g; c /= g;
    if (a < 0 || (a == 0 && b < 0)) { a = -a; b = -b; c = -c; }
    return new long[]{a, b, c};
}
```

### 3.3 Tested demo: classify the intersection of two segments

Each query gives $A,B,C,D$ (non-degenerate segments). Print `NONE`, `POINT x y` (6 decimals) or `OVERLAP`
(collinear with a common sub-segment of positive length).

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ld = long double;
struct P { ll x, y; };
P operator-(P a, P b) { return {a.x - b.x, a.y - b.y}; }
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
ll dot(P a, P b) { return a.x * b.x + a.y * b.y; }
int sgn(ll v) { return (v > 0) - (v < 0); }
int main() {
    int q; cin >> q;
    cout << fixed << setprecision(6);
    while (q--) {
        P a, b, c, d;
        cin >> a.x >> a.y >> b.x >> b.y >> c.x >> c.y >> d.x >> d.y;
        P u = b - a, v = d - c;
        ll den = cross(u, v);
        if (den == 0) {
            if (cross(u, c - a) != 0) { cout << "NONE\n"; continue; }      // parallel, distinct lines
            // collinear: project onto u and compare parameter intervals (scaled by |u|^2)
            ll t0 = dot(c - a, u), t1 = dot(d - a, u), L = dot(u, u);
            if (t0 > t1) swap(t0, t1);
            ll lo = max(t0, 0LL), hi = min(t1, L);
            if (lo > hi) cout << "NONE\n";
            else if (lo < hi) cout << "OVERLAP\n";
            else { ld t = (ld)lo / L; cout << "POINT " << a.x + t * u.x << ' ' << a.y + t * u.y << '\n'; }
            continue;
        }
        ll tn = cross(c - a, v), sn = cross(c - a, u);
        if (den < 0) { den = -den; tn = -tn; sn = -sn; }
        if (tn < 0 || tn > den || sn < 0 || sn > den) { cout << "NONE\n"; continue; }
        ld t = (ld)tn / den;
        cout << "POINT " << a.x + t * u.x << ' ' << a.y + t * u.y << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken();
        int q = (int) st.nval;
        PrintWriter out = new PrintWriter(System.out);
        while (q-- > 0) {
            long[] v = new long[8];
            for (int i = 0; i < 8; i++) { st.nextToken(); v[i] = (long) st.nval; }
            long ax = v[0], ay = v[1], ux = v[2] - ax, uy = v[3] - ay;
            long cx = v[4] - ax, cy = v[5] - ay, wx = v[6] - v[4], wy = v[7] - v[5];
            long den = ux * wy - uy * wx;
            if (den == 0) {
                if (ux * cy - uy * cx != 0) { out.println("NONE"); continue; }
                long t0 = cx * ux + cy * uy, t1 = (v[6] - ax) * ux + (v[7] - ay) * uy, L = ux * ux + uy * uy;
                if (t0 > t1) { long tmp = t0; t0 = t1; t1 = tmp; }
                long lo = Math.max(t0, 0), hi = Math.min(t1, L);
                if (lo > hi) out.println("NONE");
                else if (lo < hi) out.println("OVERLAP");
                else { double t = (double) lo / L; out.println(String.format(Locale.US, "POINT %.6f %.6f", ax + t * ux, ay + t * uy)); }
                continue;
            }
            long tn = cx * wy - cy * wx, sn = cx * uy - cy * ux;
            if (den < 0) { den = -den; tn = -tn; sn = -sn; }
            if (tn < 0 || tn > den || sn < 0 || sn > den) { out.println("NONE"); continue; }
            double t = (double) tn / den;
            out.println(String.format(Locale.US, "POINT %.6f %.6f", ax + t * ux, ay + t * uy));
        }
        out.flush();
    }
}
```

<!-- test
in:
6
0 0 4 4 0 4 4 0
0 0 2 0 2 0 3 5
0 0 1 1 2 2 3 3
0 0 2 2 1 1 3 3
0 0 2 2 2 2 5 5
0 0 1 0 0 1 1 1
out:
POINT 2.000000 2.000000
POINT 2.000000 0.000000
NONE
OVERLAP
POINT 2.000000 2.000000
NONE
-->
<!-- test
in:
3
0 0 0 10 -5 3 5 3
0 0 3 1 3 1 0 0
1 1 4 4 2 3 5 0
out:
POINT 0.000000 3.000000
OVERLAP
POINT 2.500000 2.500000
-->

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "do the segments intersect / touch", "does the path cross itself" | four orientations + on-segment checks |
| "on which side", "separate the two points", "number of lines crossed" | sign of $ax+by+c$ (= a cross product); compare signs, don't multiply |
| "lines $y=kx+b$", "intersection inside the strip $x_1<x<x_2$" | sort by value at $x_1$, look for inversions at $x_2$ |
| "count distinct lines / directions through a point" | gcd-normalised direction in a set |
| "closest distance between segments / to a wall" | clamped projection; min of 4 endpoint distances |
| "how many lattice points on the segment" | $\gcd(\lvert\Delta x\rvert,\lvert\Delta y\rvert)+1$ |
| "segments, count points covered" | per-segment gcd count, subtract overcounted intersections |

Often confused with: half-plane problems (many lines bounding a region → [half-plane intersection](05-sweep-closest-pair-and-half-plane.md))
and "many segments, any intersection?" (→ sweep line, Shamos–Hoey, same file).

---

## 5. Worked examples (graded)

### Example 1 — Han Solo and Lazer Gun  ·  ★ 1400

- **Source:** [CF 514B · Han Solo and Lazer Gun](https://codeforces.com/problemset/problem/514/B) — 1400
- **Difficulty:** 1400
- **Problem:** A gun at $(x_0,y_0)$ destroys, per shot, every target on one line through the gun. Given $n\le1000$ targets
  (integer coordinates up to $10^4$, none at the gun), find the minimum number of shots.
- **Thinking from first principles:** Each shot is a line through the gun; a line through a fixed point is determined by its
  direction up to sign. Slopes $\frac{dy}{dx}$ break on vertical lines and floating slopes can collide or split. The exact key is
  the reduced direction $(dx,dy)/\gcd$ with a sign convention. The answer is the number of distinct keys.

<details><summary>Solution</summary>

For each target compute $(dx,dy)=(x-x_0,y-y_0)$, divide by $\gcd(\lvert dx\rvert,\lvert dy\rvert)$, flip the sign if $dx<0$ or
($dx=0$ and $dy<0$), insert into a set. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int n, x0, y0; cin >> n >> x0 >> y0;
    set<pair<int, int>> dirs;
    for (int i = 0; i < n; i++) {
        int x, y; cin >> x >> y;
        int dx = x - x0, dy = y - y0, g = gcd(abs(dx), abs(dy));
        dx /= g; dy /= g;
        if (dx < 0 || (dx == 0 && dy < 0)) { dx = -dx; dy = -dy; }
        dirs.insert({dx, dy});
    }
    cout << dirs.size() << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int gcd(int a, int b) { while (b != 0) { int t = a % b; a = b; b = t; } return a; }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int x0 = (int) st.nval;
        st.nextToken(); int y0 = (int) st.nval;
        HashSet<Long> dirs = new HashSet<>();
        for (int i = 0; i < n; i++) {
            st.nextToken(); int x = (int) st.nval;
            st.nextToken(); int y = (int) st.nval;
            int dx = x - x0, dy = y - y0, g = gcd(Math.abs(dx), Math.abs(dy));
            dx /= g; dy /= g;
            if (dx < 0 || (dx == 0 && dy < 0)) { dx = -dx; dy = -dy; }
            dirs.add((long) dx * 100000L + dy);           // |dy| <= 2*10^4 < 10^5: injective key
        }
        System.out.println(dirs.size());
    }
}
```

</details>

<!-- test
in:
5 0 0
1 1
2 2
-3 -3
0 5
0 -1
out:
2
-->
<!-- test
in:
1 7 7
-10000 10000
out:
1
-->
<!-- test
in:
4 1 1
3 2
5 3
-1 0
1 9
out:
2
-->

### Example 2 — Line Segment Intersection  ·  ★ ≈1500

- **Source:** [CSES 2190 · Line Segment Intersection](https://cses.fi/problemset/task/2190)
- **Difficulty:** ≈1500 (est.)
- **Problem:** $t\le10^5$ pairs of segments with integer endpoints $\lvert x\rvert,\lvert y\rvert\le10^9$. Print YES if they share at least
  one point, else NO.
- **Thinking from first principles:** The proper-crossing condition is "each segment straddles the other's line", i.e. two
  pairs of opposite orientations. Then enumerate the degenerate ways to touch: an endpoint lying on the other segment
  (covers T-junctions, shared endpoints and collinear overlaps). Products of orientations are in $\{-1,0,1\}$, so no overflow
  from multiplying signs — but never multiply the raw cross products (each up to $4\cdot10^{18}$).

<details><summary>Solution</summary>

Exactly the `segIntersect` of §3.1. $O(1)$ per test, all in 64-bit integers.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
struct P { ll x, y; };
P operator-(P a, P b) { return {a.x - b.x, a.y - b.y}; }
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
ll dot(P a, P b) { return a.x * b.x + a.y * b.y; }
int orient(P a, P b, P c) { ll v = cross(b - a, c - a); return (v > 0) - (v < 0); }
bool onSeg(P a, P b, P p) { return cross(b - a, p - a) == 0 && dot(a - p, b - p) <= 0; }
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        P a, b, c, d;
        cin >> a.x >> a.y >> b.x >> b.y >> c.x >> c.y >> d.x >> d.y;
        int o1 = orient(a, b, c), o2 = orient(a, b, d), o3 = orient(c, d, a), o4 = orient(c, d, b);
        bool ok = (o1 * o2 < 0 && o3 * o4 < 0) || (o1 == 0 && onSeg(a, b, c)) || (o2 == 0 && onSeg(a, b, d))
               || (o3 == 0 && onSeg(c, d, a)) || (o4 == 0 && onSeg(c, d, b));
        cout << (ok ? "YES" : "NO") << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long cr(long ax, long ay, long bx, long by) { return ax * by - ay * bx; }
    static int orient(long[] a, long[] b, long[] c) { return Long.signum(cr(b[0] - a[0], b[1] - a[1], c[0] - a[0], c[1] - a[1])); }
    static boolean onSeg(long[] a, long[] b, long[] p) {
        return cr(b[0] - a[0], b[1] - a[1], p[0] - a[0], p[1] - a[1]) == 0
            && (a[0] - p[0]) * (b[0] - p[0]) + (a[1] - p[1]) * (b[1] - p[1]) <= 0;
    }
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = (int) readLong(in);
        while (t-- > 0) {
            long[] a = {readLong(in), readLong(in)}, b = {readLong(in), readLong(in)};
            long[] c = {readLong(in), readLong(in)}, d = {readLong(in), readLong(in)};
            int o1 = orient(a, b, c), o2 = orient(a, b, d), o3 = orient(c, d, a), o4 = orient(c, d, b);
            boolean ok = (o1 * o2 < 0 && o3 * o4 < 0) || (o1 == 0 && onSeg(a, b, c)) || (o2 == 0 && onSeg(a, b, d))
                      || (o3 == 0 && onSeg(c, d, a)) || (o4 == 0 && onSeg(c, d, b));
            out.println(ok ? "YES" : "NO");
        }
        out.flush();
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
1 1 5 3 1 2 4 3
1 1 5 3 1 1 4 3
1 1 5 3 2 3 4 1
1 1 5 3 2 4 4 1
1 1 5 5 3 3 7 7
1 1 3 3 4 4 6 6
out:
NO
YES
YES
YES
YES
NO
-->
<!-- test
in:
3
-1000000000 -1000000000 1000000000 1000000000 -1000000000 1000000000 1000000000 -1000000000
0 0 0 10 0 11 0 20
0 0 0 10 0 10 5 10
out:
YES
NO
YES
-->

### Example 3 — Anton and Lines  ·  ★ 1600

- **Source:** [CF 593B · Anton and Lines](https://codeforces.com/problemset/problem/593/B) — 1600
- **Difficulty:** 1600
- **Problem:** $n\le10^5$ distinct lines $y=k_ix+b_i$ ($\lvert k\rvert,\lvert b\rvert\le10^6$) and a strip $x_1<x_2$ ($\lvert x\rvert\le10^6$).
  Is there an intersection point of two lines strictly inside the strip ($x_1<x<x_2$)?
- **Thinking from first principles:** All pairs is $5\cdot10^9$. Look at the lines only at the two walls: line $i$ enters at
  $L_i=k_ix_1+b_i$ and leaves at $R_i=k_ix_2+b_i$. Two lines cross strictly inside iff their vertical order *flips*:
  $(L_i-L_j)(R_i-R_j)<0$. (If $L_i=L_j$ they cross on the wall $x_1$ — not inside.) So sort by $(L,R)$ — ties on $L$ broken
  by $R$, which encodes "touching at $x_1$ is not a crossing" — and ask whether $R$ is non-decreasing. If some pair
  inverts, some *adjacent* pair inverts (a sequence with no adjacent descent is sorted).

<details><summary>Solution</summary>

Compute $(L_i,R_i)$ exactly in 64-bit (values $\le10^{12}+10^6$), sort lexicographically, answer YES iff some
$R_{i+1}<R_i$. Ties $R_{i+1}=R_i$ with $L_{i+1}>L_i$ mean crossing on the wall $x_2$: not inside, correctly ignored. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; ll x1, x2; cin >> n >> x1 >> x2;
    vector<pair<ll, ll>> v(n);
    for (auto& [l, r] : v) { ll k, b; cin >> k >> b; l = k * x1 + b; r = k * x2 + b; }
    sort(v.begin(), v.end());
    bool cross = false;
    for (int i = 0; i + 1 < n; i++) if (v[i + 1].second < v[i].second) cross = true;
    cout << (cross ? "YES" : "NO") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); long x1 = (long) st.nval;
        st.nextToken(); long x2 = (long) st.nval;
        long[][] v = new long[n][];
        for (int i = 0; i < n; i++) {
            st.nextToken(); long k = (long) st.nval;
            st.nextToken(); long b = (long) st.nval;
            v[i] = new long[]{k * x1 + b, k * x2 + b};
        }
        // Arrays.sort on objects is a merge sort: no quicksort worst case to fear here.
        Arrays.sort(v, (p, q) -> p[0] != q[0] ? Long.compare(p[0], q[0]) : Long.compare(p[1], q[1]));
        boolean cross = false;
        for (int i = 0; i + 1 < n; i++) if (v[i + 1][1] < v[i][1]) cross = true;
        System.out.println(cross ? "YES" : "NO");
    }
}
```

</details>

<!-- test
in:
4
1 2
1 2
1 0
0 1
0 2
out:
NO
-->
<!-- test
in:
2
1 3
1 0
-1 3
out:
YES
-->
<!-- test
in:
2
1 3
1 0
0 1
out:
NO
-->
<!-- test
in:
2
1 3
1 0
-1 6
out:
NO
-->

### Example 4 — Distance between segments  ·  ★ ≈1700

- **Source:** Original problem.
- **Difficulty:** ≈1700 (est.)
- **Problem:** $q\le10^5$ queries, each two segments with integer endpoints $\lvert x\rvert,\lvert y\rvert\le10^6$ (possibly degenerate,
  i.e. a point). Print the Euclidean distance between them with absolute error $\le10^{-6}$.
- **Thinking from first principles:** A segment-to-segment distance is a minimum over a 2-parameter square; §1.4 shows that in
  2D the minimum is either $0$ (they intersect) or attained at an endpoint of one of them. So the whole problem reduces to
  an exact intersection test plus four clamped projections. Degenerate segments need one guard: $\lvert B-A\rvert^2=0$.

<details><summary>Solution</summary>

`distSegSeg` from §3.1. The intersection test is exact; the distances are `long double` / `double` with values $\le3\cdot10^6$ —
far inside double precision. $O(1)$ per query.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ld = long double;
struct P { ll x, y; };
P operator-(P a, P b) { return {a.x - b.x, a.y - b.y}; }
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
ll dot(P a, P b) { return a.x * b.x + a.y * b.y; }
int orient(P a, P b, P c) { ll v = cross(b - a, c - a); return (v > 0) - (v < 0); }
bool onSeg(P a, P b, P p) { return cross(b - a, p - a) == 0 && dot(a - p, b - p) <= 0; }
bool inter(P a, P b, P c, P d) {
    int o1 = orient(a, b, c), o2 = orient(a, b, d), o3 = orient(c, d, a), o4 = orient(c, d, b);
    return (o1 * o2 < 0 && o3 * o4 < 0) || (o1 == 0 && onSeg(a, b, c)) || (o2 == 0 && onSeg(a, b, d))
        || (o3 == 0 && onSeg(c, d, a)) || (o4 == 0 && onSeg(c, d, b));
}
ld ps(P p, P a, P b) {
    P d = b - a; ld L = dot(d, d);
    ld t = L == 0 ? 0 : max((ld)0, min((ld)1, dot(p - a, d) / L));
    ld qx = a.x + t * d.x - p.x, qy = a.y + t * d.y - p.y;
    return sqrtl(qx * qx + qy * qy);
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> q;
    cout << fixed << setprecision(9);
    while (q--) {
        P a, b, c, d;
        cin >> a.x >> a.y >> b.x >> b.y >> c.x >> c.y >> d.x >> d.y;
        ld r = inter(a, b, c, d) ? 0 : min({ps(a, c, d), ps(b, c, d), ps(c, a, b), ps(d, a, b)});
        cout << r << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long cr(long ax, long ay, long bx, long by) { return ax * by - ay * bx; }
    static int orient(long[] a, long[] b, long[] c) { return Long.signum(cr(b[0] - a[0], b[1] - a[1], c[0] - a[0], c[1] - a[1])); }
    static boolean onSeg(long[] a, long[] b, long[] p) {
        return cr(b[0] - a[0], b[1] - a[1], p[0] - a[0], p[1] - a[1]) == 0
            && (a[0] - p[0]) * (b[0] - p[0]) + (a[1] - p[1]) * (b[1] - p[1]) <= 0;
    }
    static boolean inter(long[] a, long[] b, long[] c, long[] d) {
        int o1 = orient(a, b, c), o2 = orient(a, b, d), o3 = orient(c, d, a), o4 = orient(c, d, b);
        return (o1 * o2 < 0 && o3 * o4 < 0) || (o1 == 0 && onSeg(a, b, c)) || (o2 == 0 && onSeg(a, b, d))
            || (o3 == 0 && onSeg(c, d, a)) || (o4 == 0 && onSeg(c, d, b));
    }
    static double ps(long[] p, long[] a, long[] b) {
        long dx = b[0] - a[0], dy = b[1] - a[1];
        double L = (double) (dx * dx + dy * dy);
        double t = L == 0 ? 0 : Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L));
        double qx = a[0] + t * dx - p[0], qy = a[1] + t * dy - p[1];
        return Math.sqrt(qx * qx + qy * qy);
    }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int q = (int) st.nval;
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        while (q-- > 0) {
            long[][] p = new long[4][2];
            for (int i = 0; i < 4; i++) for (int j = 0; j < 2; j++) { st.nextToken(); p[i][j] = (long) st.nval; }
            double r = inter(p[0], p[1], p[2], p[3]) ? 0
                : Math.min(Math.min(ps(p[0], p[2], p[3]), ps(p[1], p[2], p[3])), Math.min(ps(p[2], p[0], p[1]), ps(p[3], p[0], p[1])));
            out.println(String.format(Locale.US, "%.9f", r));
        }
        out.flush();
    }
}
```

</details>

<!-- test
in:
5
0 0 4 0 2 3 2 1
0 0 4 0 6 3 8 3
0 0 4 0 2 -1 2 1
0 0 0 0 3 4 3 4
0 0 2 2 0 2 1 3
out:
1.000000000
3.605551275
0.000000000
5.000000000
1.414213562
-->
<!-- test
in:
2
-1000000 -1000000 1000000 1000000 -1000000 -999999 -1000000 -999999
5 5 5 5 5 5 5 5
out:
0.707106781
0.000000000
-->

### Example 5 — Covered Points  ·  ★ 2400

- **Source:** [CF 1036E · Covered Points](https://codeforces.com/problemset/problem/1036/E) — 2400
- **Difficulty:** 2400
- **Problem:** $n\le1000$ segments with integer endpoints ($\lvert x\rvert,\lvert y\rvert\le10^6$), non-degenerate, no two on the
  same line. Count lattice points covered by at least one segment.
- **Thinking from first principles:** Segment $i$ alone covers $g_i+1$ lattice points ($g_i=\gcd$ of its coordinate
  differences). Summing overcounts exactly the points lying on several segments. Since no two segments share a line,
  two segments share at most one point, so the overlaps are just pairwise intersection points that happen to be lattice
  points. A point on $c$ segments is counted $c$ times and must be counted once: subtract $c-1$. Clean way to subtract
  exactly $c-1$: for each segment $i$, collect the *distinct* lattice points where it meets segments $j<i$, and subtract their
  number. A point on segments $i_1<\dots<i_c$ is collected by $i_2,\dots,i_c$ once each: $c-1$ times.
  Integrality of the intersection is the delicate part: do it without floating point (below).

<details><summary>Solution</summary>

Let segment $i$ be $A+ku$ with primitive step $u=(B-A)/g$, $k\in[0,g]$, and segment $j$ be $C+se$. By §1.2 with $u$ in place
of $d$: $k=\frac{(C-A)\times e}{u\times e}$. If $u\times e=0$ the lines are parallel (and distinct): skip. Otherwise the
intersection is a lattice point **iff $k$ is an integer** (Bézout, §2), and it lies on segment $i$ iff $0\le k\le g$. The point
$Q=A+ku$ is then exact; check it lies within the bounding box of segment $j$ (it is on line $j$ already).
Magnitudes: crosses $\le8\cdot10^{12}$, fine in 64-bit. Total $O(n^2\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    int n; cin >> n;
    vector<ll> ax(n), ay(n), bx(n), by(n);
    for (int i = 0; i < n; i++) cin >> ax[i] >> ay[i] >> bx[i] >> by[i];
    ll ans = 0;
    for (int i = 0; i < n; i++) {
        ll dx = bx[i] - ax[i], dy = by[i] - ay[i], g = gcd(llabs(dx), llabs(dy));
        ll ux = dx / g, uy = dy / g;
        ans += g + 1;
        set<pair<ll, ll>> seen;
        for (int j = 0; j < i; j++) {
            ll ex = bx[j] - ax[j], ey = by[j] - ay[j];
            ll den = ux * ey - uy * ex;
            if (den == 0) continue;
            ll num = (ax[j] - ax[i]) * ey - (ay[j] - ay[i]) * ex;
            if (num % den != 0) continue;
            ll k = num / den;
            if (k < 0 || k > g) continue;
            ll qx = ax[i] + k * ux, qy = ay[i] + k * uy;
            if (qx < min(ax[j], bx[j]) || qx > max(ax[j], bx[j]) || qy < min(ay[j], by[j]) || qy > max(ay[j], by[j])) continue;
            seen.insert({qx, qy});
        }
        ans -= (ll)seen.size();
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        long[] ax = new long[n], ay = new long[n], bx = new long[n], by = new long[n];
        for (int i = 0; i < n; i++) {
            st.nextToken(); ax[i] = (long) st.nval; st.nextToken(); ay[i] = (long) st.nval;
            st.nextToken(); bx[i] = (long) st.nval; st.nextToken(); by[i] = (long) st.nval;
        }
        long ans = 0;
        for (int i = 0; i < n; i++) {
            long dx = bx[i] - ax[i], dy = by[i] - ay[i], g = gcd(Math.abs(dx), Math.abs(dy));
            long ux = dx / g, uy = dy / g;
            ans += g + 1;
            HashSet<Long> seen = new HashSet<>();
            for (int j = 0; j < i; j++) {
                long ex = bx[j] - ax[j], ey = by[j] - ay[j];
                long den = ux * ey - uy * ex;
                if (den == 0) continue;
                long num = (ax[j] - ax[i]) * ey - (ay[j] - ay[i]) * ex;
                if (num % den != 0) continue;                  // Java % keeps the sign of num; == 0 test is still exact
                long k = num / den;
                if (k < 0 || k > g) continue;
                long qx = ax[i] + k * ux, qy = ay[i] + k * uy;
                if (qx < Math.min(ax[j], bx[j]) || qx > Math.max(ax[j], bx[j]) || qy < Math.min(ay[j], by[j]) || qy > Math.max(ay[j], by[j])) continue;
                seen.add((qx + 2000000L) * 4000001L + (qy + 2000000L));
            }
            ans -= seen.size();
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
2
0 0 4 4
0 4 4 0
out:
9
-->
<!-- test
in:
3
0 0 4 0
2 -2 2 2
0 -2 4 2
out:
13
-->
<!-- test
in:
1
-1000000 -1000000 1000000 1000000
out:
2000001
-->
<!-- test
in:
3
0 0 3 1
0 1 3 0
1 0 1 5
out:
10
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Compare signs, never multiply raw cross products.** `cross1 * cross2 < 0` overflows at $10^{18}\cdot10^{18}$; use
   `sgn(cross1) * sgn(cross2) < 0`. (CF 498A Crazy Town is lost by many exactly this way.)
2. **The on-segment test needs both conditions.** `cross == 0` alone accepts points on the infinite line.
3. **Collinear overlap needs its own branch** when you construct the intersection: the parametric formula divides by
   $d\times e=0$. Project onto the direction and intersect the parameter intervals.
4. **Degenerate segments** (a point): the orientation formulas still work, but distance code divides by $\lvert B-A\rvert^2$. Guard it.
5. **Exact integrality tests:** "is the intersection a lattice point?" must be decided with integer divisibility, never by
   rounding a double. Using a primitive direction keeps numbers small (Example 5).
6. **Distances: compare squared values** when only order matters; take one `sqrt` at the end.
7. **Line hashing:** gcd-normalise *and* fix the sign; forgetting the sign double-counts every line.
   In Java, hash a pair as a single `long` instead of `List<Integer>` or string keys (boxing is slow).
8. **Parameter comparisons without division:** to test $0\le\frac{num}{den}\le1$, first make $den>0$ by negating both, then test
   $0\le num\le den$.
9. **Java `%` with negatives:** `num % den` can be negative, but `num % den != 0` is still an exact divisibility test.
10. **Lines through a strip (Example 3)**: ties at the walls decide the "strictly inside" semantics — encode them in the sort
    order rather than with special cases.

---

## 7. Going further (toward 2400–2600+)

- **Many segments, does any pair intersect?** Sweep line with an ordered set of active segments, checking only neighbours
  (Shamos–Hoey, $O(n\log n)$) — see [sweep algorithms](05-sweep-closest-pair-and-half-plane.md).
- **Counting intersections of axis-parallel segments**: sweep + Fenwick tree,
  [CSES 1740 · Intersection Points](https://cses.fi/problemset/task/1740); used with Euler's formula in
  [CF 1401E · Divide Square](https://codeforces.com/problemset/problem/1401/E) — 2400 (see
  [circles and advanced](06-circles-and-advanced-geometry.md)).
- **Union length/area of segments with thickness**: [CF 610D · Vika and Segments](https://codeforces.com/problemset/problem/610/D) — 2300.
- **Self-intersecting paths**: [CSES 1742 · Robot Path](https://cses.fi/problemset/task/1742) — first time an axis-parallel
  path touches itself.
- **Upper envelope of lines** (max of $k_ix+b_i$) is the convex hull trick:
  [convex hull trick and Li Chao tree](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md).

---

## 8. Practice ladder

**≤1400**
- [ ] [CF 1620B · Triangles on a Rectangle](https://codeforces.com/problemset/problem/1620/B) — 1000
- [ ] [CF 514B · Han Solo and Lazer Gun](https://codeforces.com/problemset/problem/514/B) — 1400

**1400–1900**
- [ ] [CSES 2190 · Line Segment Intersection](https://cses.fi/problemset/task/2190)
- [ ] [CF 593B · Anton and Lines](https://codeforces.com/problemset/problem/593/B) — 1600
- [ ] [CF 498A · Crazy Town](https://codeforces.com/problemset/problem/498/A) — 1700
- [ ] [CF 1216C · White Sheet](https://codeforces.com/problemset/problem/1216/C) — 1700
- [ ] [CF 24C · Sequence of points](https://codeforces.com/problemset/problem/24/C) — 1800
- [ ] [AtCoder ADT_ALL_20260925_2 H · K-colinear Line](https://atcoder.jp/contests/adt_all_20260925_2/tasks/abc248_e) — line hashing

**1900–2300**
- [ ] [CF 961D · Pair Of Lines](https://codeforces.com/problemset/problem/961/D) — 2000
- [ ] [CF 1059D · Nature Reserve](https://codeforces.com/problemset/problem/1059/D) — 2200
- [ ] [CF 610D · Vika and Segments](https://codeforces.com/problemset/problem/610/D) — 2300
- [ ] [CSES 1740 · Intersection Points](https://cses.fi/problemset/task/1740)

**2400+**
- [ ] [CF 1036E · Covered Points](https://codeforces.com/problemset/problem/1036/E) — 2400
- [ ] [CF 1401E · Divide Square](https://codeforces.com/problemset/problem/1401/E) — 2400
- [ ] [CSES 1742 · Robot Path](https://cses.fi/problemset/task/1742)

---

## 9. LeetCode / FAANG cross-reference

- [LC 149 · Max Points on a Line](https://leetcode.com/problems/max-points-on-a-line/) — Hard — canonical direction per anchor point (§3.2).
- [LC 2280 · Minimum Lines to Represent a Line Chart](https://leetcode.com/problems/minimum-lines-to-represent-a-line-chart/) — Medium — consecutive collinearity by cross product; the famous floating-slope WA.
- [LC 1232 · Check If It Is a Straight Line](https://leetcode.com/problems/check-if-it-is-a-straight-line/) — Easy — cross with the first segment.
- [LC 335 · Self Crossing](https://leetcode.com/problems/self-crossing/) — Hard — a spiral path; only the last few segments can intersect.
- [LC 836 · Rectangle Overlap](https://leetcode.com/problems/rectangle-overlap/) — Easy — interval intersection per axis.
- [LC 2152 · Minimum Number of Lines to Cover Points](https://leetcode.com/problems/minimum-number-of-lines-to-cover-points/) — Medium 🔒 — bitmask over canonical lines.

Interview geometry is almost always "avoid slopes, use cross products and gcd-normalised keys".

---

## 10. Self-check

1. Derive $t$ for the intersection of $A+td$ and $C+se$.
2. List all the ways two segments can share a point and show how the four-orientation test covers each.
3. Why is the segment–segment distance in 2D the minimum of four point–segment distances? Why does this fail in 3D?
4. How do you test whether the intersection of two integer segments is a lattice point without floating point?
5. In Anton and Lines, why is checking adjacent pairs after sorting sufficient?
6. Why must you avoid `c1 * c2 < 0` for cross products, and what do you write instead?

<details><summary>Answers</summary>

1. Cross both sides with $e$: $A\times e+t(d\times e)=C\times e$, so $t=\frac{(C-A)\times e}{d\times e}$.
2. Proper crossing (both straddle), endpoint on the interior of the other (T), shared endpoint, collinear overlap. The first is
   $o_1o_2<0\wedge o_3o_4<0$; all others have some endpoint on the other segment, detected by $o_k=0$ plus the on-segment test.
3. An interior minimum makes the connecting vector orthogonal to both directions; in 2D that forces parallel segments, and then
   an endpoint attains the same distance. In 3D, skew lines have a unique common perpendicular with interior feet.
4. Use the primitive direction $u$ of one segment: the intersection is $A+ku$ with $k=\frac{(C-A)\times e}{u\times e}$; it is a lattice
   point iff the division is exact.
5. A sequence with no adjacent descent is non-decreasing; any inversion implies an adjacent one.
6. Each cross can be $\sim4\cdot10^{18}$; the product overflows. Compare `sgn(c1) * sgn(c2) < 0`.

</details>
