# Vectors, dot and cross products, and precision

> **Band:** 🔵 1400–2100 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [integer overflow and precision](../01-Foundations/06-integer-overflow-precision-and-fast-io.md), [sorting and comparators](../01-Foundations/05-sorting-and-comparators.md)
> **You can say you know this when:** you can write an orientation test, an exact polar-angle comparator and a projection/rotation routine from memory, and for any constraint set you can say in one sentence whether `long long`, `__int128`, `double` or `long double` is required — and why.

Everything else in computational geometry (lines, polygons, hulls, sweeps, circles) is built from the two
primitives in this file. If they are exact and fast, the rest is bookkeeping; if they are sloppy, the rest is
random WA.

---

## 1. First principles — why this works

### 1.1 Points are vectors, and slopes are a trap

The naive way to reason about the plane is with slopes: "the line through $A$ and $B$ is
$y = mx + c$ with $m = \frac{y_B - y_A}{x_B - x_A}$". Every competitive programmer who does this pays for it:

- vertical lines have no slope (division by zero),
- slopes of nearly vertical lines are huge and lose precision,
- comparing slopes needs division, so even integer inputs become floating point.

The fix is to never divide. Treat a point $P=(x,y)$ as the vector from the origin to $P$, and express every
question as a **sign of a polynomial in the coordinates**. Polynomials of integer inputs are integers, so
the answer is exact. Two polynomials do almost all of the work:

$$a\cdot b = a_x b_x + a_y b_y \qquad\qquad a\times b = a_x b_y - a_y b_x .$$

### 1.2 Where the dot product comes from

Ask: "given two directions $a$ and $b$, how aligned are they?" The law of cosines on the triangle with sides
$a$, $b$, $a-b$ says $\lvert a-b\rvert^2 = \lvert a\rvert^2 + \lvert b\rvert^2 - 2\lvert a\rvert\lvert b\rvert\cos\theta$.
Expanding the left side coordinate-wise gives
$\lvert a-b\rvert^2 = (a_x-b_x)^2+(a_y-b_y)^2 = \lvert a\rvert^2+\lvert b\rvert^2-2(a_xb_x+a_yb_y)$. Comparing,

$$a\cdot b = \lvert a\rvert\,\lvert b\rvert\cos\theta .$$

So the **sign** of the dot product classifies the angle: $>0$ acute, $=0$ right, $<0$ obtuse — with no square
roots and no trigonometry. Its **value** divided by $\lvert b\rvert$ is the signed length of the shadow of $a$ on $b$
(projection).

### 1.3 Where the cross product comes from

Ask instead: "is $b$ counter-clockwise (to the left) of $a$?" Write $a=\lvert a\rvert(\cos\alpha,\sin\alpha)$ and
$b=\lvert b\rvert(\cos\beta,\sin\beta)$. Then

$$a_x b_y - a_y b_x = \lvert a\rvert\lvert b\rvert(\cos\alpha\sin\beta-\sin\alpha\cos\beta)=\lvert a\rvert\lvert b\rvert\sin(\beta-\alpha).$$

So $a\times b>0$ exactly when turning from $a$ to $b$ counter-clockwise takes less than $180^\circ$.
Geometrically $\lvert a\times b\rvert$ is the area of the parallelogram spanned by $a$ and $b$ (base $\lvert a\rvert$,
height $\lvert b\rvert\lvert\sin\theta\rvert$), and the sign records orientation. This one fact gives:

- **orientation test**: $\operatorname{orient}(A,B,C)=\operatorname{sign}\big((B-A)\times(C-A)\big)$ is $+1$ if $A\to B\to C$
  turns left, $-1$ if right, $0$ if collinear;
- **triangle area**: $\tfrac12\lvert (B-A)\times(C-A)\rvert$;
- **side of a line**: $C$ is left of the directed line $A\to B$ iff the orientation is $+1$.

### 1.4 Why integers win: exact predicates

A *predicate* is a yes/no geometric question (left or right? inside or outside? do they intersect?).
A *construction* produces a new point (an intersection, a rotated point). Predicates on integer input are
polynomials of degree 2 (orientation) or 3–4 (in-circle), so they can be evaluated **exactly** if the integer
type is wide enough. Constructions usually need division and are inherently approximate.

The strong solver's discipline therefore is:

1. Keep input integer as long as possible. Answer predicates with integer arithmetic.
2. Only construct floating-point points at the very end, and only when the output demands them.
3. If the input is decimal with a fixed number of digits, multiply by $10^k$ and go back to step 1.

Bound check (memorise the shape of this argument): if $\lvert x\rvert,\lvert y\rvert\le C$, the differences are at most
$2C$ and $(B-A)\times(C-A)$ is twice the area of a triangle inside a $2C\times2C$ square, so its absolute value is at most
$2\cdot\frac{(2C)^2}{2}=4C^2$. With $C=10^9$ that is $4\cdot10^{18}<9.22\cdot10^{18}=2^{63}$ — fits in `long long`,
barely. Anything of higher degree (or coordinates beyond $10^9$, or sums of cross products) needs `__int128` in C++
or `Math.multiplyHigh`/`BigInteger` in Java.

### 1.5 Floating point: what actually goes wrong

`double` has a 53-bit mantissa: relative error about $1.1\cdot10^{-16}$ per operation, and integers are exact only
up to $2^{53}\approx 9\cdot10^{15}$. GCC's `long double` on x86 (Codeforces, most judges) has a 64-bit mantissa:
relative error $5.4\cdot10^{-20}$, integers exact up to $2^{64}$. MSVC's `long double` is just `double`, and **Java has
no long double at all**.

Errors appear in three ways:

- **Cancellation.** $a\times b$ for nearly parallel vectors subtracts two almost equal products; the absolute
  error is about $\varepsilon\cdot\lvert a\rvert\lvert b\rvert$ even though the result is tiny.
- **Ill-conditioned functions.** $\arccos(x)$ near $x=\pm1$ has infinite slope: an input error of $10^{-16}$
  becomes an angle error of $10^{-8}$. Never compute an angle with `acos(dot/(|a||b|))`; use
  `atan2(cross, dot)`, which is well-conditioned everywhere.
- **Equality.** Two computations of the "same" value differ in the last bits, so `==` is meaningless.

Hence the epsilon rule: compare $x$ to $0$ as $x>\varepsilon$, $x<-\varepsilon$, else "zero", where $\varepsilon$ is
chosen from the **scale of the quantity being compared**, not as a magic `1e-9`. If coordinates are up to $10^4$ and you
test a cross product (magnitude up to $\sim10^8$, error $\sim10^8\cdot10^{-16}=10^{-8}$), then $\varepsilon=10^{-6}$ is
safe for "is it zero?" only if genuinely non-zero values are known to be larger than that — for integer input they are at
least $1$. When you cannot prove such a gap, switch to exact arithmetic.

### 1.6 Sorting by angle without computing angles

Many problems need points sorted around the origin (sweeping a ray, angular two pointers, convex hull of a star).
`atan2` sorts are fast to write but fail when two angles differ by less than about $10^{-15}$ — and with coordinates
up to $10^9$, distinct lattice directions can differ by $10^{-18}$.

The exact comparator uses the cross product, but the cross product alone is **not** a valid comparator over the whole
circle: it is not transitive (each of $0^\circ$, $120^\circ$, $240^\circ$ is "less" than the next). The fix: split the plane
into two half-open halves

$$H_0=\{\text{angle}\in[0,\pi)\},\qquad H_1=\{\text{angle}\in[\pi,2\pi)\}.$$

Inside one half the angle difference lies in $(-\pi,\pi)$, where $\sin$ has the same sign as its argument, so
$a<b \iff a\times b>0$ is a strict weak order. Compare halves first, then cross products.
The point $(0,0)$ has no angle — exclude it or handle it first.

---

## 2. Formulas, definitions and identities

| Quantity | Formula | Meaning / derivation | Cost |
|---|---|---|---|
| Dot product | $a\cdot b=a_xb_x+a_yb_y=\lvert a\rvert\lvert b\rvert\cos\theta$ | law of cosines (§1.2) | $O(1)$ |
| Cross product | $a\times b=a_xb_y-a_yb_x=\lvert a\rvert\lvert b\rvert\sin\theta$ | angle-difference formula (§1.3) | $O(1)$ |
| Lagrange identity | $(a\cdot b)^2+(a\times b)^2=\lvert a\rvert^2\lvert b\rvert^2$ | $\cos^2+\sin^2=1$ | — |
| Norm | $\lvert a\rvert=\sqrt{a\cdot a}$ | Pythagoras | 1 sqrt |
| Orientation | $\operatorname{orient}(A,B,C)=\operatorname{sgn}((B-A)\times(C-A))$ | left turn $+1$ | exact in `ll` if $\lvert\text{coord}\rvert\le10^9$ |
| Triangle area | $\tfrac12\lvert(B-A)\times(C-A)\rvert$ | half a parallelogram | exact ×2 |
| Signed angle $a\to b$ | $\operatorname{atan2}(a\times b,\ a\cdot b)\in(-\pi,\pi]$ | (§1.5: well-conditioned) | 1 atan2 |
| Unsigned angle | $\operatorname{atan2}(\lvert a\times b\rvert,\ a\cdot b)\in[0,\pi]$ | | |
| Rotation by $\theta$ | $(x\cos\theta-y\sin\theta,\ x\sin\theta+y\cos\theta)$ | multiply $x+iy$ by $e^{i\theta}$ | |
| Rotation by $90^\circ$ | $\operatorname{perp}(x,y)=(-y,x)$ | exact; note $a\times b=\operatorname{perp}(a)\cdot b$ | exact |
| Projection of $p$ on direction $d$ | $\dfrac{p\cdot d}{d\cdot d}\,d$ | shadow length $\frac{p\cdot d}{\lvert d\rvert}$ times unit vector | |
| Projection of $P$ on line $AB$ | $A+\dfrac{(P-A)\cdot(B-A)}{\lvert B-A\rvert^2}(B-A)$ | | |
| Reflection of $P$ over line $AB$ | $2\,\operatorname{proj}_{AB}(P)-P$ | projection is the midpoint | |
| Distance $P$ to line $AB$ | $\dfrac{\lvert (B-A)\times(P-A)\rvert}{\lvert B-A\rvert}$ | parallelogram area / base | |
| Angle comparison | $\angle(a)<\angle(b)$ in the same half $\iff a\times b>0$ | §1.6 | exact |

**Rotation derivation.** A point at angle $\varphi$ and radius $r$ is $(r\cos\varphi, r\sin\varphi)$. Rotating adds $\theta$
to the angle: $(r\cos(\varphi+\theta), r\sin(\varphi+\theta)) = (r\cos\varphi\cos\theta - r\sin\varphi\sin\theta,\;
r\sin\varphi\cos\theta + r\cos\varphi\sin\theta)$, which is the formula above. Rotation about a centre $C$:
translate, rotate, translate back: $C + \operatorname{rot}_\theta(P-C)$.

**Cross product is anti-symmetric and bilinear:** $a\times b=-(b\times a)$, $a\times a=0$,
$(a+b)\times c=a\times c+b\times c$. Bilinearity is why $(B-A)\times(C-A)=A\times B+B\times C+C\times A$, the identity behind the
shoelace formula ([polygons](03-polygons-area-pick-point-in-polygon.md)).

**Magnitude table** (coordinates bounded by $C$, inputs integer):

| Expression | Bound | Type needed for $C=10^9$ |
|---|---|---|
| difference $B-A$ | $2C$ | `int` overflows! use `ll` |
| $(B-A)\times(C-A)$, $(B-A)\cdot(C-A)$ | $4C^2$ / $8C^2$ | `ll` for cross; dot of two differences can reach $8\cdot10^{18}$, still $<2^{63}$ |
| squared distance | $8C^2$ | `ll` |
| sum of $n$ cross products (polygon area) | $\le$ area of bounding box $\times2 = 8C^2$ | `ll` (cancellation keeps it bounded), but partial sums can exceed: use `__int128` if unsure |
| degree-3 / degree-4 predicates (in-circle) | $\sim C^4$ | `__int128` for $C\le10^4$… beyond that, rethink |

**Double precision rule of thumb.** If every exact integer intermediate is below $2^{53}\approx9\cdot10^{15}$, `double`
evaluates it exactly. For coordinates up to $10^6$ a cross product is below $4\cdot10^{12}$ — `double` is exact; at
$10^9$ it is not.

---

## 3. Implementation (C++ and Java)

### 3.1 Exact integer vector kit

```cpp
struct P {
    ll x, y;
    P operator+(const P& o) const { return {x + o.x, y + o.y}; }
    P operator-(const P& o) const { return {x - o.x, y - o.y}; }
    P operator*(ll k) const { return {x * k, y * k}; }
    bool operator==(const P& o) const { return x == o.x && y == o.y; }
    bool operator<(const P& o) const { return x < o.x || (x == o.x && y < o.y); }
};
ll dot(P a, P b) { return a.x * b.x + a.y * b.y; }
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
ll cross(P o, P a, P b) { return cross(a - o, b - o); }          // > 0: o->a->b turns left
int sgn(ll v) { return (v > 0) - (v < 0); }
int orient(P a, P b, P c) { return sgn(cross(a, b, c)); }
ll norm2(P a) { return dot(a, a); }

// Exact polar order around the origin, angle in [0, 2*pi), ties (same direction) by length.
int half(P p) { return p.y < 0 || (p.y == 0 && p.x < 0); }      // 0: [0,pi), 1: [pi,2pi)
bool polarLess(P a, P b) {
    int ha = half(a), hb = half(b);
    if (ha != hb) return ha < hb;
    ll c = cross(a, b);
    if (c != 0) return c > 0;
    return norm2(a) < norm2(b);
}
// Exact sign of a*b - c*d for |values| up to ~9e18 (e.g. cross products of large vectors).
int sgnDet128(ll a, ll b, ll c, ll d) {
    __int128 v = (__int128)a * b - (__int128)c * d;
    return (v > 0) - (v < 0);
}
```

```java
static final class P {
    final long x, y;
    P(long x, long y) { this.x = x; this.y = y; }
    P add(P o) { return new P(x + o.x, y + o.y); }
    P sub(P o) { return new P(x - o.x, y - o.y); }
}
static long dot(P a, P b) { return a.x * b.x + a.y * b.y; }
static long cross(P a, P b) { return a.x * b.y - a.y * b.x; }
static long cross(P o, P a, P b) { return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x); }
static int orient(P a, P b, P c) { return Long.signum(cross(a, b, c)); }
static long norm2(P a) { return a.x * a.x + a.y * a.y; }

static int half(P p) { return (p.y < 0 || (p.y == 0 && p.x < 0)) ? 1 : 0; }
static final Comparator<P> POLAR = (a, b) -> {
    int ha = half(a), hb = half(b);
    if (ha != hb) return Integer.compare(ha, hb);
    long c = cross(a, b);
    if (c != 0) return c > 0 ? -1 : 1;
    return Long.compare(norm2(a), norm2(b));
};
// Exact sign of a*b - c*d using the high 64 bits of the 128-bit products.
static int sgnDet128(long a, long b, long c, long d) {
    long h1 = Math.multiplyHigh(a, b), l1 = a * b;
    long h2 = Math.multiplyHigh(c, d), l2 = c * d;
    if (h1 != h2) return h1 < h2 ? -1 : 1;
    return Integer.signum(Long.compareUnsigned(l1, l2));
}
```

### 3.2 Floating-point kit (`long double` in C++, `double` in Java)

```cpp
const ld EPS = 1e-9;
int sgnd(ld v) { return (v > EPS) - (v < -EPS); }
struct PD {
    ld x, y;
    PD operator+(const PD& o) const { return {x + o.x, y + o.y}; }
    PD operator-(const PD& o) const { return {x - o.x, y - o.y}; }
    PD operator*(ld k) const { return {x * k, y * k}; }
};
ld dot(PD a, PD b) { return a.x * b.x + a.y * b.y; }
ld cross(PD a, PD b) { return a.x * b.y - a.y * b.x; }
ld len(PD a) { return sqrtl(dot(a, a)); }
PD perp(PD a) { return {-a.y, a.x}; }
PD rot(PD a, ld t) { ld c = cosl(t), s = sinl(t); return {a.x * c - a.y * s, a.x * s + a.y * c}; }
ld angleBetween(PD a, PD b) { return atan2l(cross(a, b), dot(a, b)); }      // signed, (-pi, pi]
PD projLine(PD p, PD a, PD b) { PD d = b - a; return a + d * (dot(p - a, d) / dot(d, d)); }
PD reflectLine(PD p, PD a, PD b) { return projLine(p, a, b) * 2 - p; }
ld distLine(PD p, PD a, PD b) { return fabsl(cross(b - a, p - a)) / len(b - a); }
```

```java
static final double EPS = 1e-9;
static int sgnd(double v) { return v > EPS ? 1 : (v < -EPS ? -1 : 0); }
static double dotd(double ax, double ay, double bx, double by) { return ax * bx + ay * by; }
static double crossd(double ax, double ay, double bx, double by) { return ax * by - ay * bx; }
static double[] rot(double x, double y, double t) {
    double c = Math.cos(t), s = Math.sin(t);
    return new double[]{x * c - y * s, x * s + y * c};
}
static double angleBetween(double ax, double ay, double bx, double by) {
    return Math.atan2(crossd(ax, ay, bx, by), dotd(ax, ay, bx, by));
}
static double[] projLine(double px, double py, double ax, double ay, double bx, double by) {
    double dx = bx - ax, dy = by - ay;
    double t = dotd(px - ax, py - ay, dx, dy) / dotd(dx, dy, dx, dy);
    return new double[]{ax + dx * t, ay + dy * t};
}
static double distLine(double px, double py, double ax, double ay, double bx, double by) {
    double dx = bx - ax, dy = by - ay;
    return Math.abs(crossd(dx, dy, px - ax, py - ay)) / Math.sqrt(dx * dx + dy * dy);
}
```

### 3.3 Tested demo of the floating kit

Queries: `ROT x y deg` (rotate about the origin counter-clockwise), `PROJ px py ax ay bx by`,
`REFL px py ax ay bx by`, `ANG ax ay bx by` (signed angle from $a$ to $b$ in degrees),
`DIST px py ax ay bx by` (distance from $P$ to line $AB$).

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
PD projLine(PD p, PD a, PD b) { PD d = b - a; return a + d * (dot(p - a, d) / dot(d, d)); }
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const ld PI = acosl(-1.0L);
    int q; cin >> q;
    cout << fixed << setprecision(6);
    while (q--) {
        string op; cin >> op;
        if (op == "ROT") {
            ld x, y, d; cin >> x >> y >> d;
            ld t = d * PI / 180, c = cosl(t), s = sinl(t);
            cout << x * c - y * s << ' ' << x * s + y * c << '\n';
        } else if (op == "ANG") {
            PD a, b; cin >> a.x >> a.y >> b.x >> b.y;
            cout << atan2l(cross(a, b), dot(a, b)) * 180 / PI << '\n';
        } else {
            PD p, a, b; cin >> p.x >> p.y >> a.x >> a.y >> b.x >> b.y;
            PD pr = projLine(p, a, b);
            if (op == "PROJ") cout << pr.x << ' ' << pr.y << '\n';
            else if (op == "REFL") { PD r = pr * 2 - p; cout << r.x << ' ' << r.y << '\n'; }
            else cout << fabsl(cross(b - a, p - a)) / sqrtl(dot(b - a, b - a)) << '\n';
        }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int q = Integer.parseInt(br.readLine().trim());
        while (q-- > 0) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            String op = st.nextToken();
            double[] v = new double[6];
            int k = 0;
            while (st.hasMoreTokens()) v[k++] = Double.parseDouble(st.nextToken());
            if (op.equals("ROT")) {
                double t = Math.toRadians(v[2]), c = Math.cos(t), s = Math.sin(t);
                out.println(String.format(Locale.US, "%.6f %.6f", v[0] * c - v[1] * s, v[0] * s + v[1] * c));
            } else if (op.equals("ANG")) {
                double cr = v[0] * v[3] - v[1] * v[2], dt = v[0] * v[2] + v[1] * v[3];
                out.println(String.format(Locale.US, "%.6f", Math.toDegrees(Math.atan2(cr, dt))));
            } else {
                double px = v[0], py = v[1], ax = v[2], ay = v[3], dx = v[4] - ax, dy = v[5] - ay;
                double t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy);
                double qx = ax + dx * t, qy = ay + dy * t;
                if (op.equals("PROJ")) out.println(String.format(Locale.US, "%.6f %.6f", qx, qy));
                else if (op.equals("REFL")) out.println(String.format(Locale.US, "%.6f %.6f", 2 * qx - px, 2 * qy - py));
                else out.println(String.format(Locale.US, "%.6f", Math.abs(dx * (py - ay) - dy * (px - ax)) / Math.sqrt(dx * dx + dy * dy)));
            }
        }
        out.flush();
    }
}
```

<!-- test
in:
7
ROT 1 0 90
ROT 2 1 180
PROJ 3 4 0 0 1 0
REFL 3 4 0 0 1 1
ANG 1 0 0 -1
ANG 1 0 -1 0
DIST 0 5 -2 1 4 1
out:
0.000000 1.000000
-2.000000 -1.000000
3.000000 0.000000
4.000000 3.000000
-90.000000
180.000000
4.000000
-->
<!-- test
in:
3
ROT 1 1 45
PROJ 1 1 0 0 0 7
DIST 2 2 0 0 3 3
out:
0.000000 1.414214
0.000000 1.000000
0.000000
-->

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "left of / right of / on the line", "clockwise", "turns" | orientation sign of a cross product |
| "acute / obtuse / right angle", "is the foot inside the segment" | sign of a dot product |
| "area of triangle", "collinear" | cross product $=0$ means collinear; area is half its absolute value |
| "sort by angle", "sweep a ray around a point", "points within an angle" | exact polar comparator, then two pointers on the doubled array |
| coordinates given with "at most $k$ digits after the decimal point" | multiply by $10^k$, solve in integers |
| output a real number with $10^{-6}$ tolerance | constructions are fine in floating point; predicates still exact |
| $\lvert x\rvert\le10^9$ and a degree-2 predicate | `long long` is enough; degree $\ge3$ → `__int128` |
| "minimal angle between vectors" | sort by polar angle, adjacent pairs only, compare angles exactly |

Common confusion: the cross product's sign tells *orientation*, not *distance*. "Closest to a line" needs
$\lvert\text{cross}\rvert/\lvert d\rvert$, and comparing such distances for different lines needs the denominators.

---

## 5. Worked examples (graded)

### Example 1 — Point Location Test  ·  ★ ≈1200

- **Source:** [CSES 2189 · Point Location Test](https://cses.fi/problemset/task/2189)
- **Difficulty:** ≈1200 (est.)
- **Problem:** $t\le10^5$ queries; each gives $p_1,p_2,p_3$ with $\lvert x\rvert,\lvert y\rvert\le10^9$, $p_1\ne p_2$. Say whether $p_3$ is
  LEFT of, RIGHT of, or on (TOUCH) the directed line $p_1\to p_2$.
- **Thinking from first principles:** "Left of a directed line" is the definition of a positive cross product
  $(p_2-p_1)\times(p_3-p_1)$. The only real question is the type: the value is twice a triangle area inside a
  $2\cdot10^9$ square, at most $4\cdot10^{18}$ — `long long` suffices and no floating point is needed. A slope-based
  approach would divide by $x_2-x_1$ and break on vertical lines.

<details><summary>Solution</summary>

Compute the cross product in 64-bit integers; print by its sign. $O(1)$ per query.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        ll x1, y1, x2, y2, x3, y3;
        cin >> x1 >> y1 >> x2 >> y2 >> x3 >> y3;
        ll c = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1);
        cout << (c > 0 ? "LEFT" : c < 0 ? "RIGHT" : "TOUCH") << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
    static long nextLong() throws IOException {
        int c = in.read();
        while (c != '-' && (c < '0' || c > '9')) c = in.read();
        boolean neg = c == '-';
        if (neg) c = in.read();
        long r = 0;
        while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = in.read(); }
        return neg ? -r : r;
    }
    public static void main(String[] args) throws IOException {
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = (int) nextLong();
        while (t-- > 0) {
            long x1 = nextLong(), y1 = nextLong(), x2 = nextLong(), y2 = nextLong(), x3 = nextLong(), y3 = nextLong();
            long c = (x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1);
            out.println(c > 0 ? "LEFT" : c < 0 ? "RIGHT" : "TOUCH");
        }
        out.flush();
    }
}
```

</details>

<!-- test
in:
3
1 1 5 3 2 3
1 1 5 3 4 1
1 1 5 3 3 2
out:
LEFT
RIGHT
TOUCH
-->
<!-- test
in:
3
1000000000 -1000000000 -1000000000 1000000000 -1000000000 -1000000000
1000000000 -1000000000 -1000000000 1000000000 1000000000 1000000000
-1000000000 -1000000000 1000000000 1000000000 0 0
out:
LEFT
RIGHT
TOUCH
-->

### Example 2 — Five Dimensional Points  ·  ★ 1700

- **Source:** [CF 850A · Five Dimensional Points](https://codeforces.com/problemset/problem/850/A) — 1700
- **Difficulty:** 1700
- **Problem:** $n\le1000$ distinct points in $\mathbb{R}^5$ with integer coordinates $\le10^3$ in absolute value. A point $a$
  is *bad* if there are two other distinct points $b,c$ with $\angle bac$ strictly acute, otherwise *good*. Print the
  number of good points and their indices in increasing order.
- **Thinking from first principles:** "Acute" is $\,(b-a)\cdot(c-a)>0$ — a dot product, works in any dimension.
  Brute force is $O(n^3\cdot5)=5\cdot10^9$: too slow. So ask the structural question: *how many vectors can pairwise have
  non-positive dot products?* In the plane at most 4 (the axis directions); in $\mathbb{R}^d$ the answer is $2d$.
  A good point needs its $n-1$ difference vectors to be such a family, so $n-1\le10$.

<details><summary>Solution</summary>

**Lemma.** Non-zero vectors $v_1,\dots,v_m\in\mathbb{R}^d$ with $v_i\cdot v_j\le0$ for all $i\ne j$ satisfy $m\le2d$.

*Proof by induction on $d$.* $d=1$: at most one positive and one negative number. Step: project every
$v_i$ ($i\ge2$) onto the hyperplane orthogonal to $v_1$: $w_i=v_i-\frac{v_i\cdot v_1}{\lvert v_1\rvert^2}v_1$. Then
$w_i\cdot w_j=v_i\cdot v_j-\frac{(v_i\cdot v_1)(v_j\cdot v_1)}{\lvert v_1\rvert^2}\le v_i\cdot v_j\le0$ because both factors
$v_i\cdot v_1,v_j\cdot v_1$ are $\le0$, so their product is $\ge0$. At most one $w_i$ is zero (two negative multiples of
$v_1$ would have a positive dot product). The non-zero $w_i$ live in $\mathbb{R}^{d-1}$, so there are at most
$2(d-1)$ of them; total $m\le1+1+2(d-1)=2d$. $\square$

So if $n>11$ print `0`; otherwise brute force all triples, $O(11^3)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int n; cin >> n;
    vector<array<int, 5>> a(n);
    for (auto& p : a) for (int& v : p) cin >> v;
    if (n > 11) { cout << 0 << '\n'; return 0; }
    vector<int> good;
    for (int i = 0; i < n; i++) {
        bool ok = true;
        for (int j = 0; j < n && ok; j++) for (int k = j + 1; k < n && ok; k++) {
            if (j == i || k == i) continue;
            long long d = 0;
            for (int t = 0; t < 5; t++) d += 1LL * (a[j][t] - a[i][t]) * (a[k][t] - a[i][t]);
            if (d > 0) ok = false;
        }
        if (ok) good.push_back(i + 1);
    }
    cout << good.size() << '\n';
    for (int g : good) cout << g << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken();
        int n = (int) st.nval;
        int[][] a = new int[n][5];
        for (int i = 0; i < n; i++) for (int t = 0; t < 5; t++) { st.nextToken(); a[i][t] = (int) st.nval; }
        PrintWriter out = new PrintWriter(System.out);
        if (n > 11) { out.println(0); out.flush(); return; }
        List<Integer> good = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            boolean ok = true;
            for (int j = 0; j < n && ok; j++) for (int k = j + 1; k < n && ok; k++) {
                if (j == i || k == i) continue;
                long d = 0;
                for (int t = 0; t < 5; t++) d += (long) (a[j][t] - a[i][t]) * (a[k][t] - a[i][t]);
                if (d > 0) ok = false;
            }
            if (ok) good.add(i + 1);
        }
        out.println(good.size());
        for (int g : good) out.println(g);
        out.flush();
    }
}
```

</details>

<!-- test
in:
3
0 0 0 0 0
1 0 0 0 0
0 1 0 0 0
out:
1
1
-->
<!-- test
in:
1
5 5 5 5 5
out:
1
1
-->
<!-- test
in:
12
0 0 0 0 0
1 0 0 0 0
-1 0 0 0 0
0 1 0 0 0
0 -1 0 0 0
0 0 1 0 0
0 0 -1 0 0
0 0 0 1 0
0 0 0 -1 0
0 0 0 0 1
0 0 0 0 -1
3 3 3 3 3
out:
0
-->
<!-- test
in:
11
0 0 0 0 0
1 0 0 0 0
-1 0 0 0 0
0 1 0 0 0
0 -1 0 0 0
0 0 1 0 0
0 0 -1 0 0
0 0 0 1 0
0 0 0 -1 0
0 0 0 0 1
0 0 0 0 -1
out:
1
1
-->

### Example 3 — Circle Lattice Points (decimal input)  ·  ★ ≈1950

- **Source:** [AtCoder ABC191 D · Circle Lattice Points](https://atcoder.jp/contests/abc191/tasks/abc191_d) — diff≈1953
- **Difficulty:** ≈1950 (AtCoder model estimate)
- **Problem:** Real $X,Y,R$ with at most 4 digits after the decimal point, $\lvert X\rvert,\lvert Y\rvert\le10^5$, $0<R\le10^5$.
  Count integer points $(x,y)$ with $(x-X)^2+(y-Y)^2\le R^2$ (boundary included).
- **Thinking from first principles:** The obvious loop "for each integer $x$, $h=\sqrt{R^2-(x-X)^2}$, count $y$ in
  $[Y-h,Y+h]$" is right in exact arithmetic. In `double`, $0.1$ is not representable, $R^2-(x-X)^2$ suffers cancellation,
  and lattice points exactly on the circle (the boundary is *included*) flip in and out. This is precisely the problem
  that punishes floating point — and the statement hands you the cure: "at most 4 decimals" means
  $10^4X,10^4Y,10^4R$ are integers. Scale everything by $10^4$, then every comparison is between integers up to
  $(2\cdot10^9)^2$, which fits in 64 bits.

<details><summary>Solution</summary>

Parse $X,Y,R$ as strings into integers $\hat X=10^4X$ etc. (pad the fraction to 4 digits). For each integer $x$ with
$10^4x\in[\hat X-\hat R,\hat X+\hat R]$, let $D=\hat R^2-(10^4x-\hat X)^2\ge0$ and $s=\lfloor\sqrt D\rfloor$ computed exactly
(floating guess, then correct by $\pm1$). A $y$ is inside iff $\lvert10^4y-\hat Y\rvert\le\sqrt D$; the left side is an integer,
so this is $\lvert10^4y-\hat Y\rvert\le s$, i.e. $y\in\big[\lceil(\hat Y-s)/10^4\rceil,\ \lfloor(\hat Y+s)/10^4\rfloor\big]$.
Floor/ceil division must be correct for negative numerators. $O(R)$ iterations, all exact.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
ll parseScaled(const string& s) {            // exact value * 10^4
    size_t i = 0; bool neg = false;
    if (s[i] == '-') { neg = true; i++; }
    ll ip = 0, fp = 0; int digits = 0;
    while (i < s.size() && s[i] != '.') ip = ip * 10 + (s[i++] - '0');
    if (i < s.size()) for (i++; i < s.size(); i++) { fp = fp * 10 + (s[i] - '0'); digits++; }
    while (digits < 4) { fp *= 10; digits++; }
    ll v = ip * 10000 + fp;
    return neg ? -v : v;
}
ll floorDiv(ll a, ll b) { return a / b - ((a % b != 0) && ((a < 0) != (b < 0))); }
ll ceilDiv(ll a, ll b) { return -floorDiv(-a, b); }
ll isqrtll(ll v) {
    ll r = (ll)sqrtl((long double)v);
    while (r * r > v) r--;
    while ((r + 1) * (r + 1) <= v) r++;
    return r;
}
int main() {
    string sx, sy, sr; cin >> sx >> sy >> sr;
    ll X = parseScaled(sx), Y = parseScaled(sy), R = parseScaled(sr), ans = 0;
    for (ll x = ceilDiv(X - R, 10000); x <= floorDiv(X + R, 10000); x++) {
        ll dx = x * 10000 - X, D = R * R - dx * dx;
        if (D < 0) continue;
        ll s = isqrtll(D);
        ans += floorDiv(Y + s, 10000) - ceilDiv(Y - s, 10000) + 1;
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long parseScaled(String s) {
        int i = 0; boolean neg = false;
        if (s.charAt(0) == '-') { neg = true; i++; }
        long ip = 0, fp = 0; int digits = 0;
        while (i < s.length() && s.charAt(i) != '.') ip = ip * 10 + (s.charAt(i++) - '0');
        if (i < s.length()) for (i++; i < s.length(); i++) { fp = fp * 10 + (s.charAt(i) - '0'); digits++; }
        while (digits < 4) { fp *= 10; digits++; }
        long v = ip * 10000 + fp;
        return neg ? -v : v;
    }
    static long isqrt(long v) {
        long r = (long) Math.sqrt((double) v);
        while (r * r > v) r--;
        while ((r + 1) * (r + 1) <= v) r++;
        return r;
    }
    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long X = parseScaled(st.nextToken()), Y = parseScaled(st.nextToken()), R = parseScaled(st.nextToken());
        long ans = 0;
        // Math.floorDiv / ceilDiv are exact for negative numerators (Java 18+ for ceilDiv)
        for (long x = Math.ceilDiv(X - R, 10000); x <= Math.floorDiv(X + R, 10000); x++) {
            long dx = x * 10000 - X, D = R * R - dx * dx;
            if (D < 0) continue;
            long s = isqrt(D);
            ans += Math.floorDiv(Y + s, 10000) - Math.ceilDiv(Y - s, 10000) + 1;
        }
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
0 0 1
out:
5
-->
<!-- test
in:
0 0 1.5
out:
9
-->
<!-- test
in:
0.5 0.5 0.5
out:
0
-->
<!-- test
in:
-2.5 3.25 2.0001
out:
14
-->
<!-- test
in:
0.0001 -0.9999 0.0001
out:
0
-->
<!-- test
in:
100000 -100000 100000
out:
31415925457
-->

### Example 4 — Nearest vectors  ·  ★ 2300

- **Source:** [CF 598C · Nearest vectors](https://codeforces.com/problemset/problem/598/C) — 2300
- **Difficulty:** 2300 (the rating is high mostly because of the precision trap)
- **Problem:** $n\le10^5$ non-zero vectors from the origin, integer coordinates $\lvert x\rvert,\lvert y\rvert\le10^4$, no two with the
  same direction (opposite directions allowed). Output a pair with the smallest non-oriented angle ($\in[0,\pi]$).
- **Thinking from first principles:** The smallest angle must be between two vectors that are *adjacent* in angular order:
  if $u,w$ are not adjacent, some vector lies inside the smaller arc between them and forms a smaller angle with $u$.
  So sort by angle and check $n$ cyclically adjacent pairs. The trap: with `double atan2`, two adjacent angle *gaps* can
  differ by less than $10^{-16}$ (the official tests contain such cases), so even `long double` is borderline. The exact
  route: sort with the half-plane + cross comparator, and represent the angle between $u,w$ by the vector
  $(u\cdot w,\ \lvert u\times w\rvert)$ — it lies in the closed upper half-plane, its polar angle *is* the non-oriented angle,
  and two such angles compare by one more cross product. Magnitudes: dot and cross $\le2\cdot10^8$, their products
  $\le8\cdot10^{16}$: `long long` is exact.

<details><summary>Solution</summary>

Sort indices by exact polar angle. For each $i$, take $j=(i+1)\bmod n$ and $g=(d,c)=(v_i\cdot v_j,\lvert v_i\times v_j\rvert)$.
Angle $g_1<g_2$ iff $d_1c_2-c_1d_2>0$. Since no two vectors share a direction, every angle is in $(0,\pi]$, so all
compared angles differ by less than $\pi$ and the comparison is valid. $O(n\log n)$.

The non-oriented angle of an adjacent pair is the smaller of the two arcs; $(d,\lvert c\rvert)$ gives exactly that, so
the case "the wrap-around gap exceeds $\pi$" (all vectors in one half-plane) needs no special code.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<ll> x(n), y(n);
    for (int i = 0; i < n; i++) cin >> x[i] >> y[i];
    auto half = [&](int i) { return y[i] < 0 || (y[i] == 0 && x[i] < 0); };
    vector<int> id(n);
    iota(id.begin(), id.end(), 0);
    sort(id.begin(), id.end(), [&](int a, int b) {
        if (half(a) != half(b)) return half(a) < half(b);
        return x[a] * y[b] - y[a] * x[b] > 0;
    });
    ll bd = 0, bc = 0; int bi = -1, bj = -1;
    for (int k = 0; k < n; k++) {
        int i = id[k], j = id[(k + 1) % n];
        ll d = x[i] * x[j] + y[i] * y[j], c = llabs(x[i] * y[j] - y[i] * x[j]);
        if (bi < 0 || d * bc - c * bd > 0) { bd = d; bc = c; bi = i; bj = j; }
    }
    cout << min(bi, bj) + 1 << ' ' << max(bi, bj) + 1 << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) readLong(in);
        long[] x = new long[n], y = new long[n];
        for (int i = 0; i < n; i++) { x[i] = readLong(in); y[i] = readLong(in); }
        Integer[] id = new Integer[n];
        for (int i = 0; i < n; i++) id[i] = i;
        Arrays.sort(id, (a, b) -> {                       // object sort: merge sort, no anti-quicksort issue
            int ha = (y[a] < 0 || (y[a] == 0 && x[a] < 0)) ? 1 : 0;
            int hb = (y[b] < 0 || (y[b] == 0 && x[b] < 0)) ? 1 : 0;
            if (ha != hb) return ha - hb;
            long c = x[a] * y[b] - y[a] * x[b];
            return c > 0 ? -1 : (c < 0 ? 1 : 0);
        });
        long bd = 0, bc = 0; int bi = -1, bj = -1;
        for (int k = 0; k < n; k++) {
            int i = id[k], j = id[(k + 1) % n];
            long d = x[i] * x[j] + y[i] * y[j], c = Math.abs(x[i] * y[j] - y[i] * x[j]);
            if (bi < 0 || d * bc - c * bd > 0) { bd = d; bc = c; bi = i; bj = j; }
        }
        System.out.println((Math.min(bi, bj) + 1) + " " + (Math.max(bi, bj) + 1));
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
1 0
0 1
-1 0
2 1
out:
1 4
-->
<!-- test
in:
3
1 1
-1 0
1 -1
out:
1 3
-->
<!-- test
in:
2
1 0
-1 0
out:
1 2
-->
<!-- test
in:
4
10000 9999
-10000 -9998
9999 9998
-9999 -9997
out:
1 3
-->

### Example 5 — Triangles containing the origin  ·  ★ ≈2100

- **Source:** Original problem (a classic angular-sweep pattern).
- **Difficulty:** ≈2100 (est.)
- **Problem:** $n\le2\cdot10^5$ points, $\lvert x\rvert,\lvert y\rvert\le10^9$, none at the origin and no two collinear with the origin.
  Count triples whose triangle strictly contains the origin.
- **Thinking from first principles:** $O(n^3)$ checks are hopeless; count the complement. A triangle misses the origin
  iff its three vertices lie in an open half-plane through the origin (if the origin is outside a convex set, a line
  through the origin separates it; the general-position assumption keeps the origin off the edges). In such a triple,
  exactly one vertex $p$ "sees" the other two within the next $180^\circ$ counter-clockwise. So if $k_p$ is the number of
  points strictly within $(\theta_p,\theta_p+\pi)$, the number of bad triangles is $\sum_p\binom{k_p}{2}$ — each counted once.
  The $k_p$ come from two pointers over the polar-sorted array, "doubled" to handle the wrap.

<details><summary>Solution</summary>

Answer $=\binom n3-\sum_p\binom{k_p}2$. Sort by exact polar angle; for index $i$ advance a pointer $j$ (in $i+1..i+n-1$,
indices mod $n$) while $p_i\times p_{j}>0$; then $k_i=j-i-1$. The pointer is monotone because the half-turn window slides
forward with $i$. $O(n\log n)$. The answer is up to $\binom{2\cdot10^5}{3}\approx1.3\cdot10^{15}$: `long long`.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
struct P { ll x, y; };
ll cross(const P& a, const P& b) { return a.x * b.y - a.y * b.x; }
int half(const P& p) { return p.y < 0 || (p.y == 0 && p.x < 0); }
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<P> p(n);
    for (auto& q : p) cin >> q.x >> q.y;
    sort(p.begin(), p.end(), [](const P& a, const P& b) {
        if (half(a) != half(b)) return half(a) < half(b);
        return cross(a, b) > 0;
    });
    ll N = n, bad = 0;
    int j = 0;
    for (int i = 0; i < n; i++) {
        if (j < i + 1) j = i + 1;
        while (j < i + n && cross(p[i], p[j % n]) > 0) j++;
        ll k = j - i - 1;
        bad += k * (k - 1) / 2;
    }
    cout << N * (N - 1) * (N - 2) / 6 - bad << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in, 1 << 16));
        int n = (int) readLong(in);
        long[][] p = new long[n][];
        for (int i = 0; i < n; i++) p[i] = new long[]{readLong(in), readLong(in)};
        Arrays.sort(p, (a, b) -> {
            int ha = (a[1] < 0 || (a[1] == 0 && a[0] < 0)) ? 1 : 0;
            int hb = (b[1] < 0 || (b[1] == 0 && b[0] < 0)) ? 1 : 0;
            if (ha != hb) return ha - hb;
            long c = a[0] * b[1] - a[1] * b[0];
            return c > 0 ? -1 : (c < 0 ? 1 : 0);
        });
        long N = n, bad = 0;
        int j = 0;
        for (int i = 0; i < n; i++) {
            if (j < i + 1) j = i + 1;
            while (j < i + n && p[i][0] * p[j % n][1] - p[i][1] * p[j % n][0] > 0) j++;
            long k = j - i - 1;
            bad += k * (k - 1) / 2;
        }
        System.out.println(N * (N - 1) * (N - 2) / 6 - bad);
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
1 0
0 1
-1 1
-1 -2
out:
2
-->
<!-- test
in:
1
5 7
out:
0
-->
<!-- test
in:
3
1000000000 1
-1000000000 1000000000
-1000000000 -1000000000
out:
1
-->
<!-- test
in:
6
2 1
1 3
-1 2
-3 -1
-1 -4
2 -2
out:
8
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Never use slopes.** Every line/angle question has a cross/dot formulation without division. Vertical lines are
   then not special.
2. **Bound every product before choosing a type.** Cross of differences of coordinates $\le C$: at most $4C^2$ in magnitude
   for triangle-type expressions, $8C^2$ for a dot of two differences. $C=10^9$ → `long long` (no slack); $C=2\cdot10^9$ or
   a degree-3 predicate → `__int128` / `Math.multiplyHigh`.
3. **Read coordinates into `long long`/`long`, not `int`.** `x2 - x1` with `int` coordinates up to $10^9$ overflows before
   you multiply. Java: `(long) a * b` casts *before* the multiply; `(long) (a * b)` is the classic bug.
4. **`acos` is the enemy; `atan2(cross, dot)` is the friend.** `acos` loses half the digits near $0$ and $\pi$.
5. **Polar sort: never use `cross` alone over the full circle** — it is not transitive. Split into halves first.
   Decide where $\theta=0$ and $\theta=\pi$ go (here: $[0,\pi)$ and $[\pi,2\pi)$) and be consistent.
6. **`atan2` sorting is acceptable only when coordinates are small** (say $\le10^4$ *and* you don't need to detect equal
   angles). For equal-angle detection always use exact cross $=0$.
7. **Epsilon is a unit, not a constant.** Pick it from the magnitude of the compared quantity; for integer-derived
   predicates prefer no epsilon at all.
8. **Decimal input with $k$ fixed digits** → parse as a string into an integer scaled by $10^k$. Do not read a `double` and
   multiply: `0.29*100` is `28.999999999999996`.
9. **Output formatting in Java:** `String.format(Locale.US, "%.9f", v)` — the default locale on some machines prints a
   decimal comma. Also `-0.000000` can appear; most checkers accept it, some string comparisons do not.
10. **C++ `long double` I/O:** `printf("%Lf")` is broken on some MinGW builds; use `cout << fixed << setprecision(k)`.
11. **`hypot` is slow** (it guards against overflow). Use `sqrt(x*x+y*y)` when magnitudes are safe.
12. **Java has no `long double`.** If a problem needs 64-bit mantissas (e.g. coordinates up to $10^9$ and a construction
    that must be accurate to $10^{-6}$ relative), Java solutions need exact integer reasoning, `BigDecimal`, or
    a reformulation — check this before choosing Java for a geometry problem.

---

## 7. Going further (toward 2400–2600+)

- **Exact rational constructions.** Intersection points of integer lines have rational coordinates
  $\frac{\text{num}}{\text{den}}$ with $\lvert\text{num}\rvert\sim C^3$. Comparing them exactly needs `__int128`; this is how
  robust half-plane intersection and arrangement code avoids epsilons
  ([sweep and half-planes](05-sweep-closest-pair-and-half-plane.md)).
- **Angular sweeps around every point** ($O(n^2\log n)$): count triangles/quadrilaterals with a property, e.g.
  [CF 1284E · New Year and Castle Construction](https://codeforces.com/problemset/problem/1284/E) — 2500.
- **Interactive geometry** with orientation queries only:
  [CF 1254C · Point Ordering](https://codeforces.com/problemset/problem/1254/C) — 2300 (sort by angle using cross queries,
  then split by area queries).
- **Randomised vector tricks**: [CF 995C · Leaving the Bar](https://codeforces.com/problemset/problem/995/C) — 2300
  (combine vectors so that the sum stays short; the key fact is that among three vectors of length $\le r$ some
  sum or difference of two has length $\le r$).
- Higher dimensions: the dot/cross ideas extend; the 3D cross product is in
  [circles and advanced geometry](06-circles-and-advanced-geometry.md).

---

## 8. Practice ladder

**≤1400**
- [ ] [AtCoder ABC181 C · Collinearity](https://atcoder.jp/contests/abc181/tasks/abc181_c) — collinear triple, cross $=0$
- [ ] [CF 6A · Triangle](https://codeforces.com/problemset/problem/6/A) — 900
- [ ] [CF 1047B · Cover Points](https://codeforces.com/problemset/problem/1047/B) — 900
- [ ] [CSES 2189 · Point Location Test](https://cses.fi/problemset/task/2189)
- [ ] [CF 514B · Han Solo and Lazer Gun](https://codeforces.com/problemset/problem/514/B) — 1400
- [ ] [CF 507B · Amr and Pins](https://codeforces.com/problemset/problem/507/B) — 1400

**1400–1900**
- [ ] [CF 1971F · Circle Perimeter](https://codeforces.com/problemset/problem/1971/F) — 1600
- [ ] [CF 850A · Five Dimensional Points](https://codeforces.com/problemset/problem/850/A) — 1700
- [ ] [CF 498A · Crazy Town](https://codeforces.com/problemset/problem/498/A) — 1700
- [ ] [CF 1030D · Vasya and Triangle](https://codeforces.com/problemset/problem/1030/D) — 1800
- [ ] [CF 552D · Vanya and Triangles](https://codeforces.com/problemset/problem/552/D) — 1900
- [ ] [CF 660D · Number of Parallelograms](https://codeforces.com/problemset/problem/660/D) — 1900
- [ ] [AtCoder ABC191 D · Circle Lattice Points](https://atcoder.jp/contests/abc191/tasks/abc191_d) — exact scaling

**1900–2300**
- [ ] [CF 961D · Pair Of Lines](https://codeforces.com/problemset/problem/961/D) — 2000
- [ ] [AtCoder ABC207 D · Congruence Points](https://atcoder.jp/contests/abc207/tasks/abc207_d) — rotation + translation
- [ ] [CF 1477C · Nezzar and Nice Beatmap](https://codeforces.com/problemset/problem/1477/C) — 2200
- [ ] [CF 598C · Nearest vectors](https://codeforces.com/problemset/problem/598/C) — 2300
- [ ] [CF 995C · Leaving the Bar](https://codeforces.com/problemset/problem/995/C) — 2300
- [ ] [CF 1254C · Point Ordering](https://codeforces.com/problemset/problem/1254/C) — 2300

**2400+**
- [ ] [CF 1284E · New Year and Castle Construction](https://codeforces.com/problemset/problem/1284/E) — 2500

---

## 9. LeetCode / FAANG cross-reference

- [LC 1232 · Check If It Is a Straight Line](https://leetcode.com/problems/check-if-it-is-a-straight-line/) — Easy — cross product with the first two points; no slopes.
- [LC 1037 · Valid Boomerang](https://leetcode.com/problems/valid-boomerang/) — Easy — non-collinearity is cross $\ne0$.
- [LC 812 · Largest Triangle Area](https://leetcode.com/problems/largest-triangle-area/) — Easy — $\tfrac12\lvert\text{cross}\rvert$ over all triples.
- [LC 593 · Valid Square](https://leetcode.com/problems/valid-square/) — Medium — six squared distances, integer only.
- [LC 149 · Max Points on a Line](https://leetcode.com/problems/max-points-on-a-line/) — Hard — normalise direction by gcd and sign (exact), hash per anchor.
- [LC 1610 · Maximum Number of Visible Points](https://leetcode.com/problems/maximum-number-of-visible-points/) — Hard — polar sort + sliding window on the doubled array.
- [LC 973 · K Closest Points to Origin](https://leetcode.com/problems/k-closest-points-to-origin/) — Medium — compare squared norms; never take `sqrt`.

Interviews rarely go beyond these, but "use the cross product instead of slopes" is a frequent follow-up on LC 149.

---

## 10. Self-check

1. Derive $a\cdot b=\lvert a\rvert\lvert b\rvert\cos\theta$ from the law of cosines.
2. Why is the cross product alone not a valid comparator for sorting by angle, and what makes it valid?
3. Coordinates are up to $10^9$. Is `long long` enough for the orientation test? For comparing two squared distances?
   For the in-circle determinant?
4. Why is `atan2(cross, dot)` better than `acos(dot / (|a||b|))`?
5. Write the rotation of $P$ by $\theta$ about a centre $C$.
6. In Example 4, why does the minimal angle occur between angularly adjacent vectors?
7. Input has 3 decimal digits. What do you do before writing any geometry?

<details><summary>Answers</summary>

1. $\lvert a-b\rvert^2=\lvert a\rvert^2+\lvert b\rvert^2-2\,a\cdot b$ by expansion and $=\lvert a\rvert^2+\lvert b\rvert^2-2\lvert a\rvert\lvert b\rvert\cos\theta$ by the
   law of cosines; compare.
2. Over the full circle it is cyclic ($0^\circ<120^\circ<240^\circ<0^\circ$), not transitive. Restricted to a half-open half-plane,
   angle differences are in $(-\pi,\pi)$ where $\operatorname{sign}\sin\Delta=\operatorname{sign}\Delta$, so it is a strict weak order.
3. Orientation: yes ($\le4\cdot10^{18}$). Squared distances: yes ($\le8\cdot10^{18}$). In-circle (degree 4, $\sim10^{36}$): no —
   needs 128-bit or more, or a reformulation.
4. `acos` has unbounded derivative at $\pm1$ so tiny input errors become large angle errors; `atan2` is well-conditioned and
   also returns the sign.
5. $C+\big((P-C)_x\cos\theta-(P-C)_y\sin\theta,\ (P-C)_x\sin\theta+(P-C)_y\cos\theta\big)$.
6. If $u,w$ are not adjacent, a vector $v$ lies strictly inside the smaller arc from $u$ to $w$, and $\angle(u,v)<\angle(u,w)$.
7. Parse each number as a string and scale by $10^3$ to an exact integer; solve with integer predicates.

</details>
