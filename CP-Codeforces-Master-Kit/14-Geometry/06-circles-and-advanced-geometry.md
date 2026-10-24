# Circles and advanced geometry

> **Band:** 🔵 1700 – 🔴 2600 · **Priority:** ⚡ (circle intersections, circumcircle, Euler's formula, minimum enclosing circle) · 🧊 (area of union of circles, 3D) · **FAANG:** low · **Prerequisites:** [vectors and precision](01-vectors-dot-cross-and-precision.md), [lines](02-lines-segments-and-intersections.md), [sweep](05-sweep-closest-pair-and-half-plane.md)
> **You can say you know this when:** you can derive circle–line and circle–circle intersections from Pythagoras, write the
> circumcentre by Cramer's rule, implement Welzl's minimum enclosing circle and explain its expected $O(n)$ bound, compute a
> lens area that stays accurate when the lens is tiny, and count regions of a planar subdivision with Euler's formula.

---

## 1. First principles — why this works

### 1.1 A circle is a set of points at fixed distance

$\{p:\lvert p-c\rvert=r\}$. Membership is the exact integer test $\lvert p-c\rvert^2\le r^2$ when everything is integral — never compare
$\sqrt{\cdot}$ with $r$. All intersection constructions follow from Pythagoras and the projection of §1 of
[file 02](02-lines-segments-and-intersections.md).

### 1.2 Circle and line

Let the line be $A+t\,d$ and the circle $(c,r)$. Project the centre: the foot is $f=A+\frac{(c-A)\cdot d}{d\cdot d}d$ and the distance
is $h=\lvert c-f\rvert=\frac{\lvert d\times(c-A)\rvert}{\lvert d\rvert}$. The intersection points are at distance $r$ from $c$ and on the line, so they
are $f\pm\frac{d}{\lvert d\rvert}\sqrt{r^2-h^2}$: two points if $h<r$, one (tangent) if $h=r$, none if $h>r$.

(Equivalently, substitute the line into $\lvert p-c\rvert^2=r^2$: $(d\cdot d)t^2+2t\,d\cdot(A-c)+\lvert A-c\rvert^2-r^2=0$ and read off the
discriminant; the projection form is numerically better because it never subtracts two large $t$-values.)

### 1.3 Circle and circle — the radical line

Circles $(c_1,r_1)$, $(c_2,r_2)$, $d=\lvert c_2-c_1\rvert$. An intersection point $X$ projects onto the centre line at distance $a$ from
$c_1$, at height $h$. Pythagoras twice: $a^2+h^2=r_1^2$ and $(d-a)^2+h^2=r_2^2$. Subtracting eliminates $h$:

$$a=\frac{d^2+r_1^2-r_2^2}{2d},\qquad h=\sqrt{r_1^2-a^2},\qquad X=c_1+a\,e\pm h\operatorname{perp}(e),\ e=\frac{c_2-c_1}{d}.$$

Cases: $d>r_1+r_2$ (apart) or $d<\lvert r_1-r_2\rvert$ (one inside the other): no points; equality: tangent, one point; $d=0,r_1=r_2$:
the same circle. The points with $h$ eliminated lie on the **radical line** — the set where the *power*
$\operatorname{pow}_i(p)=\lvert p-c_i\rvert^2-r_i^2$ is equal for both circles: $2(c_2-c_1)\cdot p=\lvert c_2\rvert^2-\lvert c_1\rvert^2-r_2^2+r_1^2$, a linear equation.

### 1.4 Tangents

**From a point $p$ outside the circle.** The tangent point $T$ makes a right angle at $T$, so $\lvert p-T\rvert=\sqrt{\lvert p-c\rvert^2-r^2}$ and
the angle at $c$ between $cp$ and $cT$ is $\varphi=\arccos\frac{r}{\lvert p-c\rvert}$. So $T=c+r\cdot\operatorname{rot}_{\pm\varphi}\!\big(\tfrac{p-c}{\lvert p-c\rvert}\big)$.

**Common tangents of two circles.** A line $\{x:n\cdot x=k\}$ with $\lvert n\rvert=1$ is tangent to $(c,r)$ iff its signed distance
$n\cdot c-k=\pm r$. For both circles: $n\cdot c_1-k=s_1r_1$ and $n\cdot c_2-k=s_2r_2$ with $s_i\in\{\pm1\}$. Subtract:
$n\cdot v=R$ where $v=c_2-c_1$, $R=s_2r_2-s_1r_1$. A unit vector with prescribed dot product with $v$ is

$$n=\frac{R\,v\pm\sqrt{\lvert v\rvert^2-R^2}\operatorname{perp}(v)}{\lvert v\rvert^2},\qquad k=n\cdot c_1-s_1r_1 .$$

$s_1=s_2$ gives the two **external** tangents (exist iff $\lvert v\rvert\ge\lvert r_1-r_2\rvert$), $s_1=-s_2$ the two **internal** ones
(exist iff $\lvert v\rvert\ge r_1+r_2$). That is the whole case analysis: 4, 3, 2, 1 or 0 tangents, by comparing $\lvert v\rvert$ with
$r_1+r_2$ and $\lvert r_1-r_2\rvert$.

### 1.5 Circumcircle

The centre $O$ of the circle through $A,B,C$ is equidistant: with $a=B-A$, $b=C-A$, $z=O-A$:
$\lvert z\rvert^2=\lvert z-a\rvert^2=\lvert z-b\rvert^2$, i.e. $2z\cdot a=\lvert a\rvert^2$ and $2z\cdot b=\lvert b\rvert^2$ — a $2\times2$ linear system. Cramer's rule:

$$z=\frac{\big(b_y\lvert a\rvert^2-a_y\lvert b\rvert^2,\ a_x\lvert b\rvert^2-b_x\lvert a\rvert^2\big)}{2\,(a\times b)},\qquad R=\lvert z\rvert=\frac{\lvert a\rvert\,\lvert b\rvert\,\lvert a-b\rvert}{4K}.$$

$a\times b=0$ means collinear (no circle). The second form of $R$ uses $K=\frac12\lvert a\times b\rvert$ (law of sines: $\frac{\lvert a-b\rvert}{\sin\angle A}=2R$).
The **incircle** centre is $\frac{\ell_aA+\ell_bB+\ell_cC}{\ell_a+\ell_b+\ell_c}$ (side lengths opposite each vertex), radius $\frac{2K}{\text{perimeter}}$.

### 1.6 Minimum enclosing circle (Welzl, expected $O(n)$)

The smallest circle containing all points is unique (two different smallest circles of radius $\rho$ would contain the set in their
lens, which fits in a circle of radius $<\rho$) and is determined by at most 3 boundary points.

**Key lemma.** If $p$ is *outside* the MEC of a set $S$, then $p$ is *on the boundary* of $\operatorname{MEC}(S\cup\{p\})$. (Otherwise the new
MEC would be a circle determined by points of $S$ only, enclosing $S$ minimally — i.e. $\operatorname{MEC}(S)$ by uniqueness — but $p$ is
outside it.)

That gives a recursive algorithm; unrolled, it is three nested loops over a **randomly shuffled** array:

```text
C = circle of radius 0 at p1
for i: if p_i outside C:            C = circle(p_i)                 # p_i on boundary
    for j < i: if p_j outside C:    C = circle with diameter p_i p_j # p_i, p_j on boundary
        for k < j: if p_k outside C: C = circumcircle(p_i, p_j, p_k)
```

**Why expected $O(n)$ (backwards analysis).** Consider the first $i$ points in random order. $p_i$ triggers the inner loop only if it
is one of the $\le3$ points that determine $\operatorname{MEC}$ of the first $i$ points: probability $\le\frac3i$. The inner loop costs $O(i)$
(by the same argument one level down, the innermost loop's expected work is linear too). So the expected total is
$\sum_i\frac3i\cdot O(i)=O(n)$. Without the shuffle an adversarial order makes it $\Theta(n^3)$.

### 1.7 Areas: segments, lenses, unions

A circular **segment** cut by a chord with central angle $\theta$ has area $\frac{r^2}{2}(\theta-\sin\theta)$ (sector minus triangle). The **lens**
of two intersecting circles is the sum of two segments: $r_1^2(\alpha_1-\sin\alpha_1\cos\alpha_1)+r_2^2(\alpha_2-\sin\alpha_2\cos\alpha_2)$ with
half-angles $\alpha_i$ at the centres.

**Precision.** For a thin lens $\alpha$ is tiny and $\alpha-\sin\alpha\cos\alpha\approx\frac23\alpha^3$ — a catastrophic cancellation, and
$\alpha=\arccos(\dots)$ near $1$ loses half the digits. The stable route (Example 4):

- $16K^2=\big((r_1+r_2)^2-d^2\big)\big(d^2-(r_1-r_2)^2\big)$ where $K$ is the area of triangle $c_1c_2X$ — Heron's formula with the
  four factors paired so that **both brackets are exact integers**. Then $h=\frac{2K}{d}$ is accurate to full relative precision.
- $\alpha_1=\operatorname{atan2}(h,a_1)$ with $a_1=\frac{d^2+r_1^2-r_2^2}{2d}$ (numerator an exact integer).
- $\alpha-\sin\alpha\cos\alpha=\frac{t-\sin t}{2}$ with $t=2\alpha$, evaluated by its Taylor series $\frac12\big(\frac{t^3}{3!}-\frac{t^5}{5!}+\dots\big)$ when
  $t$ is small.

**Area of a union of circles (🔴).** By Green's theorem, area $=\frac12\oint(x\,dy-y\,dx)$ over the boundary of the union. The boundary
consists of arcs of circles not covered by any other circle: for each circle, compute the angular intervals covered by the others
(circle–circle intersections), take the complement, and integrate each uncovered arc $[\theta_1,\theta_2]$ of $(c,r)$ in closed form:

$$\tfrac12\!\int_{\theta_1}^{\theta_2}\!\big(x\,dy-y\,dx\big)=\tfrac12\Big(r^2(\theta_2-\theta_1)+r\,c_x(\sin\theta_2-\sin\theta_1)-r\,c_y(\cos\theta_2-\cos\theta_1)\Big)$$

(substitute $x=c_x+r\cos\theta$, $y=c_y+r\sin\theta$). Remove duplicate circles first and skip circles contained in others.
$O(n^2\log n)$. The same idea computes areas of unions of polygons (integrate uncovered edge pieces).

### 1.8 Euler's formula: counting regions

For a connected planar graph drawn without crossings, $V-E+F=2$ (counting the outer face). *Proof sketch:* a spanning tree has
$E=V-1$, $F=1$; each further edge closes a cycle and splits one face into two ($E$ and $F$ both $+1$). With $C$ connected
components, $V-E+F=1+C$.

To count regions cut out by segments/lines/chords, make every crossing a vertex and every piece an edge, then
$F=E-V+1+C$. Classic consequences:

- $n$ lines in general position cut the plane into $1+n+\binom n2$ regions.
- $n$ points on a circle, all chords drawn, no three concurrent: $1+\binom n2+\binom n4$ regions (Moser's circle problem — the
  famous sequence $1,2,4,8,16,31$).
- A simple planar graph has $E\le3V-6$ (each face has $\ge3$ edges, so $2E\ge3F$).

A cleaner way to *use* it in contests: add the segments one at a time; a new segment that crosses $k$ existing pieces increases the
number of bounded regions by $k-1$, $k$, or $k+1$ depending on how many of its two ends are attached to the existing drawing (0, 1, or 2).
Example 3 is exactly this.

### 1.9 3D in two paragraphs (🧊)

The 3D cross product $a\times b=(a_yb_z-a_zb_y,\ a_zb_x-a_xb_z,\ a_xb_y-a_yb_x)$ is a vector perpendicular to both with length
$\lvert a\rvert\lvert b\rvert\sin\theta$ (parallelogram area). The **triple product** $a\cdot(b\times c)=\det[a\,b\,c]$ is the signed volume of the
parallelepiped: $D$ is above the plane $ABC$ (in the right-hand-rule sense) iff $(B-A)\times(C-A)\cdot(D-A)>0$; tetrahedron volume is
$\frac16$ of its absolute value; four points are coplanar iff it is $0$. Point–plane distance: $\frac{\lvert n\cdot(P-A)\rvert}{\lvert n\rvert}$ with
$n=(B-A)\times(C-A)$. With coordinates up to $10^6$ the triple product is up to $\sim10^{19}$: use `__int128`.

---

## 2. Formulas, definitions and identities

| Formula | Meaning |
|---|---|
| $\lvert p-c\rvert^2\le r^2$ | point in closed disc (exact for integers) |
| $h=\frac{\lvert d\times(c-A)\rvert}{\lvert d\rvert}$, points $f\pm\hat d\sqrt{r^2-h^2}$ | circle ∩ line |
| $a=\frac{d^2+r_1^2-r_2^2}{2d}$, $h=\sqrt{r_1^2-a^2}$ | circle ∩ circle |
| $\operatorname{pow}(p)=\lvert p-c\rvert^2-r^2$; radical line $2(c_2-c_1)\cdot p=\lvert c_2\rvert^2-\lvert c_1\rvert^2-r_2^2+r_1^2$ | equal power |
| tangent length from $p$: $\sqrt{\lvert p-c\rvert^2-r^2}$; angle $\arccos\frac{r}{\lvert p-c\rvert}$ | tangents from a point |
| $n=\frac{Rv\pm\sqrt{\lvert v\rvert^2-R^2}\operatorname{perp}(v)}{\lvert v\rvert^2}$, $R=s_2r_2-s_1r_1$ | common tangents |
| $z=\frac{(b_y\lvert a\rvert^2-a_y\lvert b\rvert^2,\ a_x\lvert b\rvert^2-b_x\lvert a\rvert^2)}{2(a\times b)}$ | circumcentre (relative to $A$) |
| $R=\frac{abc}{4K}$, $r_{\text{in}}=\frac{2K}{a+b+c}$ | circum- and in-radius |
| $16K^2=((r_1+r_2)^2-d^2)(d^2-(r_1-r_2)^2)$ | Heron, paired for exactness |
| segment: $\frac{r^2}{2}(\theta-\sin\theta)$; lens: sum of two segments | areas |
| $\frac{t-\sin t}{2}=\frac12\sum_{k\ge1}(-1)^{k+1}\frac{t^{2k+1}}{(2k+1)!}$ | stable for small $t$ |
| regular $n$-gon, circumradius $R$: area $\frac n2R^2\sin\frac{2\pi}n$, side $2R\sin\frac\pi n$ | |
| inscribed angle $=\frac12$ central angle on the same arc | (Example 1) |
| $V-E+F=1+C$ | Euler (planar, $F$ includes the outer face) |
| $1+n+\binom n2$; $1+\binom n2+\binom n4$ | regions of lines; of chords (Moser) |
| $\Pr[p_i\text{ on MEC boundary}]\le\frac3i$ | Welzl expected $O(n)$ |
| arc integral $\frac12(r^2\Delta\theta+rc_x\Delta\sin-rc_y\Delta\cos)$ | union of circles via Green |
| $a\times b$ (3D), $[a,b,c]=a\cdot(b\times c)$, $V_{\text{tet}}=\frac{\lvert[a,b,c]\rvert}{6}$ | 3D |

---

## 3. Implementation (C++ and Java)

### 3.1 Circle kit

```cpp
struct PD { ld x, y; };
PD operator+(PD a, PD b) { return {a.x + b.x, a.y + b.y}; }
PD operator-(PD a, PD b) { return {a.x - b.x, a.y - b.y}; }
PD operator*(PD a, ld k) { return {a.x * k, a.y * k}; }
ld dot(PD a, PD b) { return a.x * b.x + a.y * b.y; }
ld cross(PD a, PD b) { return a.x * b.y - a.y * b.x; }
ld len(PD a) { return sqrtl(dot(a, a)); }
PD perp(PD a) { return {-a.y, a.x}; }
const ld EPS = 1e-9;
// Circle (c, r) and line through a, b.
vector<PD> circleLine(PD c, ld r, PD a, PD b) {
    PD d = b - a;
    PD f = a + d * (dot(c - a, d) / dot(d, d));
    ld h2 = r * r - dot(c - f, c - f);
    if (h2 < -EPS) return {};
    if (h2 < EPS) return {f};
    PD u = d * (sqrtl(h2) / len(d));
    return {f - u, f + u};
}
// Two circles; returns {} also for identical circles (infinitely many points).
vector<PD> circleCircle(PD c1, ld r1, PD c2, ld r2) {
    PD v = c2 - c1;
    ld d = len(v);
    if (d < EPS || d > r1 + r2 + EPS || d < fabsl(r1 - r2) - EPS) return {};
    ld a = (d * d + r1 * r1 - r2 * r2) / (2 * d), h2 = r1 * r1 - a * a;
    PD m = c1 + v * (a / d);
    if (h2 < EPS) return {m};
    PD off = perp(v) * (sqrtl(h2) / d);
    return {m - off, m + off};
}
// Tangent points on circle (c, r) as seen from p.
vector<PD> tangentsFromPoint(PD c, ld r, PD p) {
    PD v = p - c;
    ld d2 = dot(v, v);
    if (d2 < r * r - EPS) return {};
    if (d2 < r * r + EPS) return {p};
    ld k = r / d2;                                  // T = c + r*cos(phi)*u +- r*sin(phi)*perp(u), u = v/|v|
    PD base = c + v * (r * k), off = perp(v) * (k * sqrtl(d2 - r * r));
    return {base - off, base + off};
}
// Common tangents: each as a pair of tangent points (on circle 1, on circle 2).
vector<pair<PD, PD>> commonTangents(PD c1, ld r1, PD c2, ld r2) {
    vector<pair<PD, PD>> res;
    PD v = c2 - c1;
    ld v2 = dot(v, v);
    if (v2 < EPS) return res;
    const int s1 = 1;                                   // (s1,s2) and (-s1,-s2) describe the same lines
    for (int s2 : {1, -1}) {                            // s2 = +1: external pair, s2 = -1: internal pair
        ld R = s2 * r2 - s1 * r1, disc = v2 - R * R;
        if (disc < -EPS) continue;
        ld sq = sqrtl(max((ld)0, disc));
        for (int sg : {1, -1}) {
            PD n = (v * R + perp(v) * (sg * sq)) * (1 / v2);
            res.push_back({c1 - n * (s1 * r1), c2 - n * (s2 * r2)});   // foot of the centre on the line
            if (sq == 0) break;
        }
    }
    return res;
}
// Circumcentre of a, b, c (caller guarantees non-collinear).
PD circumcenter(PD A, PD B, PD C) {
    PD a = B - A, b = C - A;
    ld d = 2 * cross(a, b), a2 = dot(a, a), b2 = dot(b, b);
    return A + PD{(b.y * a2 - a.y * b2) / d, (a.x * b2 - b.x * a2) / d};
}
// Welzl minimum enclosing circle, expected O(n).
pair<PD, ld> minEnclosingCircle(vector<PD> p) {
    mt19937 rng(20261023);
    shuffle(p.begin(), p.end(), rng);
    PD c = p[0]; ld r = 0;
    auto in = [&](PD q) { return len(q - c) <= r + 1e-9L * max((ld)1, r); };
    for (size_t i = 1; i < p.size(); i++) if (!in(p[i])) {
        c = p[i]; r = 0;
        for (size_t j = 0; j < i; j++) if (!in(p[j])) {
            c = (p[i] + p[j]) * 0.5L; r = len(p[i] - c);
            for (size_t k = 0; k < j; k++) if (!in(p[k])) {
                if (fabsl(cross(p[j] - p[i], p[k] - p[i])) < 1e-12L) continue;   // collinear: cannot happen exactly
                c = circumcenter(p[i], p[j], p[k]); r = len(p[i] - c);
            }
        }
    }
    return {c, r};
}
```

```java
static final double EPS = 1e-9;
static double dot(double ax, double ay, double bx, double by) { return ax * bx + ay * by; }
static double cross(double ax, double ay, double bx, double by) { return ax * by - ay * bx; }
static List<double[]> circleLine(double cx, double cy, double r, double ax, double ay, double bx, double by) {
    double dx = bx - ax, dy = by - ay, t = dot(cx - ax, cy - ay, dx, dy) / dot(dx, dy, dx, dy);
    double fx = ax + dx * t, fy = ay + dy * t, h2 = r * r - dot(cx - fx, cy - fy, cx - fx, cy - fy);
    List<double[]> res = new ArrayList<>();
    if (h2 < -EPS) return res;
    if (h2 < EPS) { res.add(new double[]{fx, fy}); return res; }
    double k = Math.sqrt(h2) / Math.sqrt(dx * dx + dy * dy);
    res.add(new double[]{fx - dx * k, fy - dy * k});
    res.add(new double[]{fx + dx * k, fy + dy * k});
    return res;
}
static List<double[]> circleCircle(double x1, double y1, double r1, double x2, double y2, double r2) {
    double vx = x2 - x1, vy = y2 - y1, d = Math.sqrt(vx * vx + vy * vy);
    List<double[]> res = new ArrayList<>();
    if (d < EPS || d > r1 + r2 + EPS || d < Math.abs(r1 - r2) - EPS) return res;
    double a = (d * d + r1 * r1 - r2 * r2) / (2 * d), h2 = r1 * r1 - a * a;
    double mx = x1 + vx * a / d, my = y1 + vy * a / d;
    if (h2 < EPS) { res.add(new double[]{mx, my}); return res; }
    double k = Math.sqrt(h2) / d;
    res.add(new double[]{mx + vy * k, my - vx * k});
    res.add(new double[]{mx - vy * k, my + vx * k});
    return res;
}
static List<double[]> tangentsFromPoint(double cx, double cy, double r, double px, double py) {
    double vx = px - cx, vy = py - cy, d2 = vx * vx + vy * vy;
    List<double[]> res = new ArrayList<>();
    if (d2 < r * r - EPS) return res;
    if (d2 < r * r + EPS) { res.add(new double[]{px, py}); return res; }
    double k = r / d2, s = k * Math.sqrt(d2 - r * r);
    double bx = cx + vx * r * k, by = cy + vy * r * k;
    res.add(new double[]{bx + vy * s, by - vx * s});
    res.add(new double[]{bx - vy * s, by + vx * s});
    return res;
}
static double[] circumcenter(double ax, double ay, double bx, double by, double cx, double cy) {
    double ux = bx - ax, uy = by - ay, wx = cx - ax, wy = cy - ay;
    double d = 2 * cross(ux, uy, wx, wy), u2 = dot(ux, uy, ux, uy), w2 = dot(wx, wy, wx, wy);
    return new double[]{ax + (wy * u2 - uy * w2) / d, ay + (ux * w2 - wx * u2) / d};
}
// Returns {cx, cy, r}.
static double[] minEnclosingCircle(double[][] pts) {
    double[][] p = pts.clone();
    Random rng = new Random(20261023);
    for (int i = p.length - 1; i > 0; i--) { int j = rng.nextInt(i + 1); double[] t = p[i]; p[i] = p[j]; p[j] = t; }
    double cx = p[0][0], cy = p[0][1], r = 0;
    for (int i = 1; i < p.length; i++) if (Math.hypot(p[i][0] - cx, p[i][1] - cy) > r + 1e-9 * Math.max(1, r)) {
        cx = p[i][0]; cy = p[i][1]; r = 0;
        for (int j = 0; j < i; j++) if (Math.hypot(p[j][0] - cx, p[j][1] - cy) > r + 1e-9 * Math.max(1, r)) {
            cx = (p[i][0] + p[j][0]) / 2; cy = (p[i][1] + p[j][1]) / 2; r = Math.hypot(p[i][0] - cx, p[i][1] - cy);
            for (int k = 0; k < j; k++) if (Math.hypot(p[k][0] - cx, p[k][1] - cy) > r + 1e-9 * Math.max(1, r)) {
                if (Math.abs(cross(p[j][0] - p[i][0], p[j][1] - p[i][1], p[k][0] - p[i][0], p[k][1] - p[i][1])) < 1e-12) continue;
                double[] o = circumcenter(p[i][0], p[i][1], p[j][0], p[j][1], p[k][0], p[k][1]);
                cx = o[0]; cy = o[1]; r = Math.hypot(p[i][0] - cx, p[i][1] - cy);
            }
        }
    }
    return new double[]{cx, cy, r};
}
```

### 3.2 Tested demo: intersections, tangents, circumcircle

Queries (all reals): `CL cx cy r ax ay bx by`, `CC x1 y1 r1 x2 y2 r2`, `TAN cx cy r px py`, `CIRC ax ay bx by cx cy`.
For the first three print the number of points, then the points sorted by $(x,y)$; for `CIRC` print centre and radius.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ld = long double;
struct PD { ld x, y; };
PD operator+(PD a, PD b) { return {a.x + b.x, a.y + b.y}; }
PD operator-(PD a, PD b) { return {a.x - b.x, a.y - b.y}; }
PD operator*(PD a, ld k) { return {a.x * k, a.y * k}; }
ld dot(PD a, PD b) { return a.x * b.x + a.y * b.y; }
ld cross(PD a, PD b) { return a.x * b.y - a.y * b.x; }
ld len(PD a) { return sqrtl(dot(a, a)); }
PD perp(PD a) { return {-a.y, a.x}; }
const ld EPS = 1e-9;
vector<PD> circleLine(PD c, ld r, PD a, PD b) {
    PD d = b - a, f = a + d * (dot(c - a, d) / dot(d, d));
    ld h2 = r * r - dot(c - f, c - f);
    if (h2 < -EPS) return {};
    if (h2 < EPS) return {f};
    PD u = d * (sqrtl(h2) / len(d));
    return {f - u, f + u};
}
vector<PD> circleCircle(PD c1, ld r1, PD c2, ld r2) {
    PD v = c2 - c1; ld d = len(v);
    if (d < EPS || d > r1 + r2 + EPS || d < fabsl(r1 - r2) - EPS) return {};
    ld a = (d * d + r1 * r1 - r2 * r2) / (2 * d), h2 = r1 * r1 - a * a;
    PD m = c1 + v * (a / d);
    if (h2 < EPS) return {m};
    PD off = perp(v) * (sqrtl(h2) / d);
    return {m - off, m + off};
}
vector<PD> tangentsFromPoint(PD c, ld r, PD p) {
    PD v = p - c; ld d2 = dot(v, v);
    if (d2 < r * r - EPS) return {};
    if (d2 < r * r + EPS) return {p};
    ld k = r / d2;
    PD base = c + v * (r * k), off = perp(v) * (k * sqrtl(d2 - r * r));
    return {base - off, base + off};
}
int main() {
    int q; cin >> q;
    cout << fixed << setprecision(6);
    while (q--) {
        string op; cin >> op;
        vector<PD> res;
        if (op == "CL") { PD c, a, b; ld r; cin >> c.x >> c.y >> r >> a.x >> a.y >> b.x >> b.y; res = circleLine(c, r, a, b); }
        else if (op == "CC") { PD c1, c2; ld r1, r2; cin >> c1.x >> c1.y >> r1 >> c2.x >> c2.y >> r2; res = circleCircle(c1, r1, c2, r2); }
        else if (op == "TAN") { PD c, p; ld r; cin >> c.x >> c.y >> r >> p.x >> p.y; res = tangentsFromPoint(c, r, p); }
        else {
            PD A, B, C; cin >> A.x >> A.y >> B.x >> B.y >> C.x >> C.y;
            PD a = B - A, b = C - A;
            ld d = 2 * cross(a, b), a2 = dot(a, a), b2 = dot(b, b);
            PD o = A + PD{(b.y * a2 - a.y * b2) / d, (a.x * b2 - b.x * a2) / d};
            cout << o.x << ' ' << o.y << ' ' << len(o - A) << '\n';
            continue;
        }
        sort(res.begin(), res.end(), [](PD a, PD b) { return a.x < b.x - EPS || (fabsl(a.x - b.x) <= EPS && a.y < b.y); });
        cout << res.size();
        for (auto& p : res) cout << ' ' << p.x << ' ' << p.y;
        cout << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final double EPS = 1e-9;
    static List<double[]> circleLine(double cx, double cy, double r, double ax, double ay, double bx, double by) {
        double dx = bx - ax, dy = by - ay, t = ((cx - ax) * dx + (cy - ay) * dy) / (dx * dx + dy * dy);
        double fx = ax + dx * t, fy = ay + dy * t, h2 = r * r - ((cx - fx) * (cx - fx) + (cy - fy) * (cy - fy));
        List<double[]> res = new ArrayList<>();
        if (h2 < -EPS) return res;
        if (h2 < EPS) { res.add(new double[]{fx, fy}); return res; }
        double k = Math.sqrt(h2) / Math.sqrt(dx * dx + dy * dy);
        res.add(new double[]{fx - dx * k, fy - dy * k});
        res.add(new double[]{fx + dx * k, fy + dy * k});
        return res;
    }
    static List<double[]> circleCircle(double x1, double y1, double r1, double x2, double y2, double r2) {
        double vx = x2 - x1, vy = y2 - y1, d = Math.sqrt(vx * vx + vy * vy);
        List<double[]> res = new ArrayList<>();
        if (d < EPS || d > r1 + r2 + EPS || d < Math.abs(r1 - r2) - EPS) return res;
        double a = (d * d + r1 * r1 - r2 * r2) / (2 * d), h2 = r1 * r1 - a * a;
        double mx = x1 + vx * a / d, my = y1 + vy * a / d;
        if (h2 < EPS) { res.add(new double[]{mx, my}); return res; }
        double k = Math.sqrt(h2) / d;
        res.add(new double[]{mx + vy * k, my - vx * k});
        res.add(new double[]{mx - vy * k, my + vx * k});
        return res;
    }
    static List<double[]> tangentsFromPoint(double cx, double cy, double r, double px, double py) {
        double vx = px - cx, vy = py - cy, d2 = vx * vx + vy * vy;
        List<double[]> res = new ArrayList<>();
        if (d2 < r * r - EPS) return res;
        if (d2 < r * r + EPS) { res.add(new double[]{px, py}); return res; }
        double k = r / d2, s = k * Math.sqrt(d2 - r * r), bx = cx + vx * r * k, by = cy + vy * r * k;
        res.add(new double[]{bx + vy * s, by - vx * s});
        res.add(new double[]{bx - vy * s, by + vx * s});
        return res;
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int q = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            String op = st.nextToken();
            double[] v = new double[7];
            int k = 0;
            while (st.hasMoreTokens()) v[k++] = Double.parseDouble(st.nextToken());
            List<double[]> res;
            if (op.equals("CL")) res = circleLine(v[0], v[1], v[2], v[3], v[4], v[5], v[6]);
            else if (op.equals("CC")) res = circleCircle(v[0], v[1], v[2], v[3], v[4], v[5]);
            else if (op.equals("TAN")) res = tangentsFromPoint(v[0], v[1], v[2], v[3], v[4]);
            else {
                double ux = v[2] - v[0], uy = v[3] - v[1], wx = v[4] - v[0], wy = v[5] - v[1];
                double d = 2 * (ux * wy - uy * wx), u2 = ux * ux + uy * uy, w2 = wx * wx + wy * wy;
                double ox = v[0] + (wy * u2 - uy * w2) / d, oy = v[1] + (ux * w2 - wx * u2) / d;
                sb.append(String.format(Locale.US, "%.6f %.6f %.6f%n", ox, oy, Math.hypot(ox - v[0], oy - v[1])));
                continue;
            }
            res.sort((a, b) -> a[0] < b[0] - EPS ? -1 : (b[0] < a[0] - EPS ? 1 : Double.compare(a[1], b[1])));
            sb.append(res.size());
            for (double[] p : res) sb.append(String.format(Locale.US, " %.6f %.6f", p[0], p[1]));
            sb.append('\n');
        }
        System.out.print(sb);
    }
}
```

<!-- test
in:
8
CL 0 0 5 -10 3 10 3
CL 0 0 5 -10 5 10 5
CL 0 0 5 -10 6 10 6
CC 0 0 5 8 0 5
CC 0 0 2 4 0 2
CC 0 0 1 0 0 3
TAN 0 0 5 13 0
CIRC 0 0 4 0 0 2
out:
2 -4.000000 3.000000 4.000000 3.000000
1 0.000000 5.000000
0
2 4.000000 -3.000000 4.000000 3.000000
1 2.000000 0.000000
0
2 1.923077 -4.615385 1.923077 4.615385
2.000000 1.000000 2.236068
-->

### 3.3 3D kit (🧊)

```cpp
struct P3 { ll x, y, z; };
P3 operator-(P3 a, P3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
P3 cross3(P3 a, P3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
__int128 dot3(P3 a, P3 b) { return (__int128)a.x * b.x + (__int128)a.y * b.y + (__int128)a.z * b.z; }
// Sign of the volume of tetrahedron ABCD (> 0: D on the side of ABC given by the right-hand rule).
int orient3(P3 a, P3 b, P3 c, P3 d) {
    __int128 v = dot3(cross3(b - a, c - a), d - a);
    return (v > 0) - (v < 0);
}
```

```java
static long[] cross3(long[] a, long[] b) {
    return new long[]{a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]};
}
// Exact triple product via BigInteger (safe for coordinates up to ~1e9).
static BigInteger triple(long[] a, long[] b, long[] c) {
    long[] n = cross3(b, c);                       // |entries| <= 2e18 for |coords| <= 1e9
    return BigInteger.valueOf(a[0]).multiply(BigInteger.valueOf(n[0]))
        .add(BigInteger.valueOf(a[1]).multiply(BigInteger.valueOf(n[1])))
        .add(BigInteger.valueOf(a[2]).multiply(BigInteger.valueOf(n[2])));
}
```

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "three points of a regular polygon", "vertices on a circle" | circumcircle + inscribed angles |
| "smallest circle covering all points", "best place for a tower" (minimise max distance) | Welzl MEC |
| "area of intersection of two circles" | lens with stable formulas (Example 4) |
| "area covered by circles" | union via Green's theorem on uncovered arcs |
| "number of regions / pieces after cutting" | Euler's formula, or "each new cut adds crossings ± 1" |
| "point visible / tangent from a point" | tangent angle $\arccos(r/d)$ |
| "two moving circles / robots touch" | distance between centres vs $r_1+r_2$, often with ternary/binary search on time |
| integer centres and radii, "inside / touching" | exact squared comparisons, no floating point at all |
| "3D points coplanar / above a plane" | triple product sign |

---

## 5. Worked examples (graded)

### Example 1 — Ancient Berland Circus  ·  ★ 2100

- **Source:** [CF 1C · Ancient Berland Circus](https://codeforces.com/problemset/problem/1/C) — 2100
- **Difficulty:** 2100
- **Problem:** Three vertices of a regular polygon (real coordinates, $\le1000$ in absolute value, $\le6$ decimals) are given; the
  polygon has at most 100 vertices. Print the smallest possible area of such a polygon.
- **Thinking from first principles:** All vertices of a regular $n$-gon lie on one circle — the circumcircle of the three given points,
  so $R$ is determined. Consecutive vertices subtend central angle $\frac{2\pi}{n}$, so each arc between given points is a multiple of
  $\frac{2\pi}n$. By the inscribed angle theorem, the angle of the triangle at a vertex is half the central angle of the opposite arc:
  each triangle angle must be a multiple of $\frac\pi n$. Area $\frac n2R^2\sin\frac{2\pi}n$ increases with $n$, so the smallest valid $n$ wins.
  Try $n=3..100$. Tolerance: if an angle is $\frac{k\pi}{N}$ but not a multiple of $\frac\pi n$, then $\frac{kn}{N}$ is at least $\frac1N\ge0.01$ away from an
  integer, so a tolerance of $10^{-4}$ cannot accept a wrong $n$.

<details><summary>Solution</summary>

Angles via `atan2(|cross|, dot)` (well-conditioned), $R=\frac{\lvert BC\rvert}{2\sin A}$, smallest $n$ with all $\frac{\angle\cdot n}{\pi}$ within $10^{-4}$ of
an integer. $O(100)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ld = long double;
int main() {
    ld x[3], y[3];
    for (int i = 0; i < 3; i++) cin >> x[i] >> y[i];
    const ld PI = acosl(-1.0L);
    ld ang[3];
    for (int i = 0; i < 3; i++) {
        int j = (i + 1) % 3, k = (i + 2) % 3;
        ld ax = x[j] - x[i], ay = y[j] - y[i], bx = x[k] - x[i], by = y[k] - y[i];
        ang[i] = atan2l(fabsl(ax * by - ay * bx), ax * bx + ay * by);
    }
    ld side = hypotl(x[1] - x[2], y[1] - y[2]);
    ld R = side / (2 * sinl(ang[0]));
    for (int n = 3; n <= 100; n++) {
        bool ok = true;
        for (int i = 0; i < 3; i++) { ld v = ang[i] * n / PI; if (fabsl(v - roundl(v)) > 1e-4L) ok = false; }
        if (ok) { cout << fixed << setprecision(8) << n / 2.0L * R * R * sinl(2 * PI / n) << '\n'; return 0; }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        double[] x = new double[3], y = new double[3];
        for (int i = 0; i < 3; i++) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            x[i] = Double.parseDouble(st.nextToken()); y[i] = Double.parseDouble(st.nextToken());
        }
        double[] ang = new double[3];
        for (int i = 0; i < 3; i++) {
            int j = (i + 1) % 3, k = (i + 2) % 3;
            double ax = x[j] - x[i], ay = y[j] - y[i], bx = x[k] - x[i], by = y[k] - y[i];
            ang[i] = Math.atan2(Math.abs(ax * by - ay * bx), ax * bx + ay * by);
        }
        double R = Math.hypot(x[1] - x[2], y[1] - y[2]) / (2 * Math.sin(ang[0]));
        for (int n = 3; n <= 100; n++) {
            boolean ok = true;
            for (int i = 0; i < 3; i++) { double v = ang[i] * n / Math.PI; if (Math.abs(v - Math.rint(v)) > 1e-4) ok = false; }
            if (ok) { System.out.println(String.format(Locale.US, "%.8f", n / 2.0 * R * R * Math.sin(2 * Math.PI / n))); return; }
        }
    }
}
```

</details>

<!-- test
in:
0.000000 0.000000
1.000000 0.000000
1.000000 1.000000
out:
1.00000000
-->
<!-- test
in:
0 0
2 0
1 1.732051
out:
1.73205100
-->
<!-- test
in:
1000.000000 0.000000
684.547106 728.968627
-904.827052 -425.779292
out:
3139525.97530128
-->
<!-- test
in:
51.091711 3.671925
22.828075 2.591711
43.410404 -30.10673
out:
1199.99999315
-->

### Example 2 — Enclose All (minimum enclosing circle)  ·  ★ ≈1700

- **Source:** [AtCoder ABC151 F · Enclose All](https://atcoder.jp/contests/abc151/tasks/abc151_f) — diff≈1671
- **Difficulty:** ≈1700 (AtCoder model estimate)
- **Problem:** $n\le50$ distinct integer points in $[0,1000]^2$. Print the minimum radius of a circle containing all of them.
- **Thinking from first principles:** The optimal circle is pinned by 2 points (a diameter) or 3 points (a circumcircle), so an
  $O(n^4)$ brute force over pairs and triples works for $n=50$. Welzl's algorithm does the same search in expected $O(n)$ by only
  "repairing" the circle when a point falls outside it, and the key lemma tells it which points are on the boundary.

<details><summary>Solution</summary>

`minEnclosingCircle` from §3.1. Expected $O(n)$ after a random shuffle.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ld = long double;
struct PD { ld x, y; };
PD operator+(PD a, PD b) { return {a.x + b.x, a.y + b.y}; }
PD operator-(PD a, PD b) { return {a.x - b.x, a.y - b.y}; }
PD operator*(PD a, ld k) { return {a.x * k, a.y * k}; }
ld dot(PD a, PD b) { return a.x * b.x + a.y * b.y; }
ld cross(PD a, PD b) { return a.x * b.y - a.y * b.x; }
ld len(PD a) { return sqrtl(dot(a, a)); }
PD circumcenter(PD A, PD B, PD C) {
    PD a = B - A, b = C - A;
    ld d = 2 * cross(a, b), a2 = dot(a, a), b2 = dot(b, b);
    return A + PD{(b.y * a2 - a.y * b2) / d, (a.x * b2 - b.x * a2) / d};
}
int main() {
    int n; cin >> n;
    vector<PD> p(n);
    for (auto& q : p) cin >> q.x >> q.y;
    mt19937 rng(20261023);
    shuffle(p.begin(), p.end(), rng);
    PD c = p[0]; ld r = 0;
    auto in = [&](PD q) { return len(q - c) <= r + 1e-9L * max((ld)1, r); };
    for (int i = 1; i < n; i++) if (!in(p[i])) {
        c = p[i]; r = 0;
        for (int j = 0; j < i; j++) if (!in(p[j])) {
            c = (p[i] + p[j]) * 0.5L; r = len(p[i] - c);
            for (int k = 0; k < j; k++) if (!in(p[k])) {
                if (fabsl(cross(p[j] - p[i], p[k] - p[i])) < 1e-12L) continue;
                c = circumcenter(p[i], p[j], p[k]); r = len(p[i] - c);
            }
        }
    }
    cout << fixed << setprecision(10) << r << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static double[] circumcenter(double ax, double ay, double bx, double by, double cx, double cy) {
        double ux = bx - ax, uy = by - ay, wx = cx - ax, wy = cy - ay;
        double d = 2 * (ux * wy - uy * wx), u2 = ux * ux + uy * uy, w2 = wx * wx + wy * wy;
        return new double[]{ax + (wy * u2 - uy * w2) / d, ay + (ux * w2 - wx * u2) / d};
    }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        double[][] p = new double[n][2];
        for (int i = 0; i < n; i++) { st.nextToken(); p[i][0] = st.nval; st.nextToken(); p[i][1] = st.nval; }
        Random rng = new Random(20261023);
        for (int i = n - 1; i > 0; i--) { int j = rng.nextInt(i + 1); double[] t = p[i]; p[i] = p[j]; p[j] = t; }
        double cx = p[0][0], cy = p[0][1], r = 0;
        for (int i = 1; i < n; i++) if (Math.hypot(p[i][0] - cx, p[i][1] - cy) > r + 1e-9 * Math.max(1, r)) {
            cx = p[i][0]; cy = p[i][1]; r = 0;
            for (int j = 0; j < i; j++) if (Math.hypot(p[j][0] - cx, p[j][1] - cy) > r + 1e-9 * Math.max(1, r)) {
                cx = (p[i][0] + p[j][0]) / 2; cy = (p[i][1] + p[j][1]) / 2; r = Math.hypot(p[i][0] - cx, p[i][1] - cy);
                for (int k = 0; k < j; k++) if (Math.hypot(p[k][0] - cx, p[k][1] - cy) > r + 1e-9 * Math.max(1, r)) {
                    double cr = (p[j][0] - p[i][0]) * (p[k][1] - p[i][1]) - (p[j][1] - p[i][1]) * (p[k][0] - p[i][0]);
                    if (Math.abs(cr) < 1e-12) continue;
                    double[] o = circumcenter(p[i][0], p[i][1], p[j][0], p[j][1], p[k][0], p[k][1]);
                    cx = o[0]; cy = o[1]; r = Math.hypot(p[i][0] - cx, p[i][1] - cy);
                }
            }
        }
        System.out.println(String.format(Locale.US, "%.10f", r));
    }
}
```

</details>

<!-- test
in:
2
0 0
1 0
out:
0.5000000000
-->
<!-- test
in:
3
0 0
4 0
2 1
out:
2.0000000000
-->
<!-- test
in:
3
0 0
2 0
1 3
out:
1.6666666667
-->
<!-- test
in:
1
7 7
out:
0.0000000000
-->

### Example 3 — Divide Square (Euler's formula)  ·  ★ 2400

- **Source:** [CF 1401E · Divide Square](https://codeforces.com/problemset/problem/1401/E) — 2400
- **Difficulty:** 2400
- **Problem:** The square $[0,10^6]^2$ is cut by $n\le10^5$ horizontal and $m\le10^5$ vertical segments. Each segment lies strictly
  inside in its fixed coordinate, touches at least one side of the square, and no two segments share a line. Count the pieces.
- **Thinking from first principles:** Pieces are faces of a planar graph, so Euler's formula decides everything; the question is how
  to count without building the graph. Add segments one at a time. A segment touching the boundary at both ends and crossing $k$
  existing segments is cut into $k+1$ pieces, each of which splits a region: $+(k+1)$. A segment touching only one side ends inside a
  region; its $k$ crossings each close a region, the dangling tail closes none: $+k$. (A crossing that is exactly an endpoint lying on
  another segment behaves the same.) Every intersection is counted once — by the later of its two segments. Hence
  $$\text{pieces}=1+\#\{\text{segments spanning the whole square}\}+\#\{\text{intersection points}\}.$$
  Counting horizontal–vertical intersections is a sweep over $x$ with a Fenwick tree over $y$.

<details><summary>Solution</summary>

Events by $x$: insert horizontal at $l_x$, query verticals at $x$ (count active $y\in[l_y,r_y]$), remove horizontal at $r_x$ — with that
order at equal $x$, so closed segments touching at endpoints count. Answer up to $\approx10^{10}$: 64-bit. $O((n+m)\log C)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
const int C = 1000000;
int bit[C + 2];
void add(int i, int v) { for (i++; i <= C + 1; i += i & -i) bit[i] += v; }
int pref(int i) { int s = 0; for (i++; i > 0; i -= i & -i) s += bit[i]; return s; }   // sum over [0, i]
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    ll ans = 1;
    vector<array<int, 4>> ev;                     // {x, type (0 add, 1 query, 2 remove), a, b}
    for (int i = 0; i < n; i++) {
        int y, lx, rx; cin >> y >> lx >> rx;
        if (lx == 0 && rx == C) ans++;
        ev.push_back({lx, 0, y, 0}); ev.push_back({rx, 2, y, 0});
    }
    for (int i = 0; i < m; i++) {
        int x, ly, ry; cin >> x >> ly >> ry;
        if (ly == 0 && ry == C) ans++;
        ev.push_back({x, 1, ly, ry});
    }
    sort(ev.begin(), ev.end());
    for (auto& e : ev) {
        if (e[1] == 0) add(e[2], 1);
        else if (e[1] == 2) add(e[2], -1);
        else ans += pref(e[3]) - (e[2] > 0 ? pref(e[2] - 1) : 0);
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final int C = 1000000;
    static int[] bit = new int[C + 2];
    static void add(int i, int v) { for (i++; i <= C + 1; i += i & -i) bit[i] += v; }
    static int pref(int i) { int s = 0; for (i++; i > 0; i -= i & -i) s += bit[i]; return s; }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int m = (int) st.nval;
        long ans = 1;
        long[] ev = new long[2 * n + m];                   // packed: x * 4e12 + type * 1e12 + a * 1e6 + b  (fits in a long)
        int k = 0;
        for (int i = 0; i < n; i++) {
            st.nextToken(); int y = (int) st.nval; st.nextToken(); int lx = (int) st.nval; st.nextToken(); int rx = (int) st.nval;
            if (lx == 0 && rx == C) ans++;
            ev[k++] = pack(lx, 0, y, 0); ev[k++] = pack(rx, 2, y, 0);
        }
        for (int i = 0; i < m; i++) {
            st.nextToken(); int x = (int) st.nval; st.nextToken(); int ly = (int) st.nval; st.nextToken(); int ry = (int) st.nval;
            if (ly == 0 && ry == C) ans++;
            ev[k++] = pack(x, 1, ly, ry);
        }
        Random rnd = new Random(1401);                    // shuffle: Arrays.sort(long[]) has an adversarial O(n^2) case
        for (int i = ev.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); long t = ev[i]; ev[i] = ev[j]; ev[j] = t; }
        Arrays.sort(ev);
        for (long e : ev) {
            int b = (int) (e % 1000001), a = (int) (e / 1000001 % 1000001), type = (int) (e / (1000001L * 1000001) % 3);
            if (type == 0) add(a, 1);
            else if (type == 2) add(a, -1);
            else ans += pref(b) - (a > 0 ? pref(a - 1) : 0);
        }
        System.out.println(ans);
    }
    static long pack(long x, long type, long a, long b) { return ((x * 3 + type) * 1000001L + a) * 1000001L + b; }
}
```

</details>

<!-- test
in:
1 1
500000 0 1000000
500000 0 1000000
out:
4
-->
<!-- test
in:
2 1
300 0 500
600 400 1000000
450 0 1000000
out:
4
-->
<!-- test
in:
1 1
10 0 5
5 0 20
out:
2
-->

### Example 4 — Area of Two Circles' Intersection (the precision example)  ·  ★ 2000

- **Source:** [CF 600D · Area of Two Circles' Intersection](https://codeforces.com/problemset/problem/600/D) — 2000
- **Difficulty:** 2000
- **Problem:** Two circles with integer centres ($\lvert x\rvert,\lvert y\rvert\le10^9$) and integer radii ($1\le r\le10^9$). Print the area of their
  intersection with absolute or relative error $10^{-6}$.
- **Thinking from first principles:** The formula is textbook (two circular segments). The rating comes from precision: with
  $r=10^9$ and centres $2\cdot10^9-1$ apart the lens area is about $4.2\cdot10^4$ while the terms of the naive formula are $\sim10^{18}$ —
  `double` cancellation leaves no correct digits, and even `long double` with `acos` is fragile. Java has no `long double`, so the fix
  must be *algebraic*: compute every cancelling difference exactly in integers first.

<details><summary>Solution</summary>

1. $D=d^2$ exactly (64-bit: $\le8\cdot10^{18}$). Apart if $D\ge(r_1+r_2)^2$; contained if $D\le(r_1-r_2)^2$ (area $\pi\min(r)^2$).
2. Otherwise $P=(r_1+r_2)^2-D>0$ and $Q=D-(r_1-r_2)^2>0$ are exact integers, and the half-chord is $h=\frac{\sqrt P\sqrt Q}{2d}$ with full
   relative precision (no subtraction of floating values).
3. $a_i=\frac{D+r_i^2-r_j^2}{2d}$ (integer numerator), $\alpha_i=\operatorname{atan2}(h,a_i)\in(0,\pi)$.
4. Lens $=\sum_i r_i^2\,g(2\alpha_i)$ with $g(t)=\frac{t-\sin t}{2}$, evaluated by the Taylor series for $t<\frac12$ (12 terms are plenty).

Every floating operation is now a product, quotient, square root or well-conditioned `atan2`, so the relative error is $\sim10^{-15}$
even in `double`. $O(1)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ld = long double;
ld g(ld t) {                                     // (t - sin t) / 2, stable for small t
    if (t >= 0.5L) return (t - sinl(t)) / 2;
    ld term = t * t * t / 6, s = 0;
    for (int k = 1; k <= 12; k++) { s += term; term *= -t * t / ((2 * k + 2) * (2 * k + 3)); }
    return s / 2;
}
int main() {
    ll x1, y1, r1, x2, y2, r2;
    cin >> x1 >> y1 >> r1 >> x2 >> y2 >> r2;
    ll dx = x2 - x1, dy = y2 - y1, D = dx * dx + dy * dy, S = r1 + r2, T = llabs(r1 - r2);
    const ld PI = acosl(-1.0L);
    cout << fixed << setprecision(10);
    if (D >= S * S) { cout << 0.0L << '\n'; return 0; }
    if (D <= T * T) { ld r = min(r1, r2); cout << PI * r * r << '\n'; return 0; }
    ld d = sqrtl((ld)D);
    ld h = sqrtl((ld)(S * S - D)) * sqrtl((ld)(D - T * T)) / (2 * d);
    ld a1 = (ld)(D + r1 * r1 - r2 * r2) / (2 * d), a2 = (ld)(D + r2 * r2 - r1 * r1) / (2 * d);
    ld area = (ld)r1 * r1 * g(2 * atan2l(h, a1)) + (ld)r2 * r2 * g(2 * atan2l(h, a2));
    cout << area << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static double g(double t) {
        if (t >= 0.5) return (t - Math.sin(t)) / 2;
        double term = t * t * t / 6, s = 0;
        for (int k = 1; k <= 12; k++) { s += term; term *= -t * t / ((2 * k + 2) * (2 * k + 3)); }
        return s / 2;
    }
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine() + " " + br.readLine());   // one reader: a second one would miss buffered input
        long x1 = Long.parseLong(st.nextToken()), y1 = Long.parseLong(st.nextToken()), r1 = Long.parseLong(st.nextToken());
        long x2 = Long.parseLong(st.nextToken()), y2 = Long.parseLong(st.nextToken()), r2 = Long.parseLong(st.nextToken());
        long dx = x2 - x1, dy = y2 - y1, D = dx * dx + dy * dy, S = r1 + r2, T = Math.abs(r1 - r2);
        if (D >= S * S) { System.out.println("0.0000000000"); return; }
        if (D <= T * T) { double r = Math.min(r1, r2); System.out.println(String.format(Locale.US, "%.10f", Math.PI * r * r)); return; }
        double d = Math.sqrt((double) D);
        double h = Math.sqrt((double) (S * S - D)) * Math.sqrt((double) (D - T * T)) / (2 * d);
        double a1 = (double) (D + r1 * r1 - r2 * r2) / (2 * d), a2 = (double) (D + r2 * r2 - r1 * r1) / (2 * d);
        double area = (double) r1 * r1 * g(2 * Math.atan2(h, a1)) + (double) r2 * r2 * g(2 * Math.atan2(h, a2));
        System.out.println(String.format(Locale.US, "%.10f", area));
    }
}
```

</details>

<!-- test
in:
0 0 4
6 0 4
out:
7.2529880636
-->
<!-- test
in:
0 0 1000000000
1999999999 0 1000000000
out:
42163.7021324161
-->
<!-- test
in:
0 0 1000000000
2 0 999999999
out:
3141592645936901422.3649437220
-->
<!-- test
in:
-1000000000 -1000000000 1000000000
1000000000 1000000000 1000000000
out:
0.0000000000
-->
<!-- test
in:
0 0 1
1 0 1
out:
1.2283696986
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Clamp before `sqrt`/`acos`**: $r^2-h^2$ can be $-10^{-15}$ for tangent configurations; `sqrt` of a negative is NaN.
2. **Compare squared distances** for membership; only construct floating points when the output requires them.
3. **Tangency needs an epsilon policy**: decide whether "touching" counts, then test $d^2$ vs $(r_1\pm r_2)^2$ exactly when inputs are integers.
4. **Coincident circles** (same centre and radius) have infinitely many intersection points — handle before dividing by $d$.
5. **Welzl without shuffling is $\Theta(n^3)$** on sorted input; use a fixed-seed shuffle (deterministic) or `mt19937` with time seed.
6. **Collinear triples in MEC** cannot occur in exact arithmetic (the lemma), but floating noise can trigger the innermost loop; skip
   degenerate circumcircles.
7. **Cancellation in areas**: thin lenses, tiny segments, nearly tangent circles. Rewrite $(a-b)$ as $\frac{a^2-b^2}{a+b}$ with the numerator
   computed exactly; use series for $t-\sin t$.
8. **Java on precision-heavy geometry**: no `long double` — the algebraic rewriting of Example 4 is the standard escape. `Math.hypot` is
   accurate but slow; inside tight loops use `Math.sqrt(dx*dx+dy*dy)` when there is no overflow risk.
9. **Euler's formula counts the outer face** and needs the number of connected components when the drawing is disconnected.
10. **Regular polygon from points**: test angle multiplicity with a tolerance justified by a gap argument (Example 1), not a random `1e-9`.

---

## 7. Going further (toward 2400–2600+)

- **Point of equal viewing angles** (Apollonius circles, or numeric descent): [CF 2C · Commentator problem](https://codeforces.com/problemset/problem/2/C) — 2600.
- **Binary search on radius + circle–line geometry**: [CF 1059D · Nature Reserve](https://codeforces.com/problemset/problem/1059/D) — 2200.
- **Moving circles / relative motion**: [CF 590B · Chip 'n Dale Rescue Rangers](https://codeforces.com/problemset/problem/590/B) — 2100.
- **Maximum points covered by a circle of radius $r$**: angular sweep of entry/exit events around each point, $O(n^2\log n)$ —
  [LC 1453 · Maximum Number of Darts Inside of a Circular Dartboard](https://leetcode.com/problems/maximum-number-of-darts-inside-of-a-circular-dartboard/) — Hard.
- **Area of union of circles / polygons**: Green's theorem on uncovered boundary pieces (§1.7).
- **Hard circle problems**: [CF 549E · Sasha Circle](https://codeforces.com/problemset/problem/549/E) — 2700,
  [CF 1936F · Grand Finale: Circles](https://codeforces.com/problemset/problem/1936/F) — 3300.
- **3D convex hull and Delaunay triangulation** (Delaunay = lifted 3D lower hull via $(x,y)\mapsto(x,y,x^2+y^2)$; the in-circle test is the
  lifted orientation test) — ICPC/IGM depth.

---

## 8. Practice ladder

**≤1400**
- [ ] [CF 2002C · Black Circles](https://codeforces.com/problemset/problem/2002/C) — 1200
- [ ] [CF 507B · Amr and Pins](https://codeforces.com/problemset/problem/507/B) — 1400

**1400–1900**
- [ ] [CF 1971F · Circle Perimeter](https://codeforces.com/problemset/problem/1971/F) — 1600
- [ ] [CF 935C · Fifa and Fafa](https://codeforces.com/problemset/problem/935/C) — 1600
- [ ] [CF 1451D · Circle Game](https://codeforces.com/problemset/problem/1451/D) — 1700
- [ ] [AtCoder ABC151 F · Enclose All](https://atcoder.jp/contests/abc151/tasks/abc151_f) — diff≈1671
- [ ] [AtCoder ABC191 D · Circle Lattice Points](https://atcoder.jp/contests/abc191/tasks/abc191_d) — diff≈1953

**1900–2300**
- [ ] [CF 600D · Area of Two Circles' Intersection](https://codeforces.com/problemset/problem/600/D) — 2000
- [ ] [CF 1C · Ancient Berland Circus](https://codeforces.com/problemset/problem/1/C) — 2100
- [ ] [CF 590B · Chip 'n Dale Rescue Rangers](https://codeforces.com/problemset/problem/590/B) — 2100
- [ ] [CF 1059D · Nature Reserve](https://codeforces.com/problemset/problem/1059/D) — 2200
- [ ] [CSES 1741 · Area of Rectangles](https://cses.fi/problemset/task/1741)

**2400+**
- [ ] [CF 1401E · Divide Square](https://codeforces.com/problemset/problem/1401/E) — 2400
- [ ] [CF 2C · Commentator problem](https://codeforces.com/problemset/problem/2/C) — 2600
- [ ] [CF 549E · Sasha Circle](https://codeforces.com/problemset/problem/549/E) — 2700

---

## 9. LeetCode / FAANG cross-reference

- [LC 1401 · Circle and Rectangle Overlapping](https://leetcode.com/problems/circle-and-rectangle-overlapping/) — Medium — clamp the centre into the rectangle, compare squared distance.
- [LC 2249 · Count Lattice Points Inside a Circle](https://leetcode.com/problems/count-lattice-points-inside-a-circle/) — Medium — exact $dx^2+dy^2\le r^2$.
- [LC 1828 · Queries on Number of Points Inside a Circle](https://leetcode.com/problems/queries-on-number-of-points-inside-a-circle/) — Medium — same test, per query.
- [LC 478 · Generate Random Point in a Circle](https://leetcode.com/problems/generate-random-point-in-a-circle/) — Medium — radius $r\sqrt U$ (area density), not $rU$.
- [LC 1453 · Maximum Number of Darts Inside of a Circular Dartboard](https://leetcode.com/problems/maximum-number-of-darts-inside-of-a-circular-dartboard/) — Hard — circles through pairs of points / angular sweep.
- [LC 1515 · Best Position for a Service Centre](https://leetcode.com/problems/best-position-for-a-service-centre/) — Hard — geometric median: convex objective, gradient or nested ternary search.
- [LC 1924 · Erect the Fence II](https://leetcode.com/problems/erect-the-fence-ii/) — Hard 🔒 — Welzl's MEC.

Circle problems in interviews are almost all "compare squared distances"; LC 478's density argument is a favourite follow-up.

---

## 10. Self-check

1. Derive $a=\frac{d^2+r_1^2-r_2^2}{2d}$ for the circle–circle intersection.
2. Why is the minimum enclosing circle unique?
3. State and prove the key lemma behind Welzl's algorithm; where does $\frac3i$ come from?
4. How many common tangents do two circles have when $\lvert r_1-r_2\rvert<d<r_1+r_2$? When $d=r_1+r_2$?
5. Why does the naive lens formula fail for $r=10^9$, $d=2\cdot10^9-1$, and what exactly fixes it?
6. Use Euler's formula to show that $n$ lines in general position make $1+n+\binom n2$ regions.
7. In Ancient Berland Circus, why can a tolerance of $10^{-4}$ never accept a wrong $n$?

<details><summary>Answers</summary>

1. $a^2+h^2=r_1^2$ and $(d-a)^2+h^2=r_2^2$; subtract: $2ad-d^2=r_1^2-r_2^2$.
2. Two different minimal discs of radius $\rho$ contain the set in their intersection, a lens that fits in a disc of radius $<\rho$.
3. If $p\notin\operatorname{MEC}(S)$ then $p\in\partial\operatorname{MEC}(S\cup\{p\})$ (else the new MEC is determined by $S$ alone and equals $\operatorname{MEC}(S)$ by
   uniqueness, contradiction). In random order, the last of $i$ points is one of the $\le3$ defining points with probability $\le\frac3i$.
4. Two (the external ones). Three (two external, one internal through the touching point).
5. Its terms are $\sim10^{18}$ while the answer is $\sim4\cdot10^4$: cancellation destroys all digits, and `acos` near 1 is ill-conditioned.
   Computing $(r_1+r_2)^2-d^2$ and $d^2-(r_1-r_2)^2$ exactly in integers, $h$ from their product, $\alpha$ by `atan2`, and $t-\sin t$ by series.
6. Clip to a huge disc: $V=\binom n2+2n$, $E=n^2+2n$ (each line cut into $n$ pieces by $n-1$ crossings and the circle; plus $2n$ arcs),
   $C=1$; $F=E-V+2=1+n+\binom n2+1$, minus the outer face.
7. If the true angle is $\frac{k\pi}{N}$ and $n$ is wrong, $\frac{kn}{N}$ differs from an integer by at least $\frac1N\ge\frac1{100}$.

</details>
