# Polygons: area, Pick's theorem, point in polygon

> **Band:** 🔵 1500–2100 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [vectors and cross products](01-vectors-dot-cross-and-precision.md), [segments](02-lines-segments-and-intersections.md), [gcd](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md)
> **You can say you know this when:** you can derive the shoelace formula from triangle fans, prove Pick's theorem's
> additivity step, write an exact point-in-polygon test (INSIDE / BOUNDARY / OUTSIDE) with the half-open rule, and an
> $O(\log n)$ point-in-convex-polygon query.

---

## 1. First principles — why this works

### 1.1 The shoelace formula from a fan of triangles

We want the area of a simple polygon $p_0,p_1,\dots,p_{n-1}$ (indices mod $n$). For a *convex* polygon and a point $O$ inside
it, the polygon is the union of triangles $Op_ip_{i+1}$, and each has area $\tfrac12\,(p_i-O)\times(p_{i+1}-O)$ when the
vertices go counter-clockwise. The surprise is that **the same sum works for any simple polygon and any $O$**, if we keep the
signs:

$$2\,\text{Area}_{\pm}=\sum_{i=0}^{n-1}(p_i-O)\times(p_{i+1}-O)=\sum_{i=0}^{n-1}p_i\times p_{i+1}\quad(\text{take }O=\text{origin}).$$

*Why the signs make it work.* Fix a point $q$ in general position. Triangle $Op_ip_{i+1}$ contains $q$ iff the edge
$p_ip_{i+1}$ crosses the ray that starts at $q$ and points away from $O$; it then counts $+1$ or $-1$ according to the
direction in which the edge crosses that ray. So the total signed coverage of $q$ is the number of signed crossings of a ray
from $q$, which is the **winding number** of the polygon around $q$: $1$ inside a counter-clockwise simple polygon, $0$ outside. Integrating
coverage over the plane gives exactly the area. (This is Green's theorem $A=\frac12\oint x\,dy-y\,dx$ in discrete form.)

*Why the origin form equals the translated form.* By bilinearity,
$(p_i-O)\times(p_{i+1}-O)=p_i\times p_{i+1}-O\times p_{i+1}-p_i\times O$, and $\sum_i(O\times p_{i+1}+p_i\times O)=\sum_i O\times p_{i+1}-\sum_i O\times p_i=0$.

Consequences:

- The **sign** of $\sum p_i\times p_{i+1}$ is the orientation: positive ⇔ counter-clockwise.
- For integer vertices, $2A$ is an **integer**. Keep it doubled until output.
- Equivalent "trapezoid" form: $2A=\sum_i (x_i-x_{i+1})(y_i+y_{i+1})$ — each edge contributes the signed area of the
  trapezoid under it. Expanding shows it is the same sum.

### 1.2 Pick's theorem — and why it is true

For a simple polygon with integer vertices, let $I$ be the number of interior lattice points and $B$ the number on the boundary.

$$A=I+\frac B2-1.$$

*Proof sketch, the way you would rediscover it.* Define $f(P)=I+\frac B2-1$. We want $f(P)=A(P)$.

1. **$f$ is additive.** Cut $P$ by a lattice chord (a diagonal inside $P$) into $P_1,P_2$. Let the chord contain $k$ lattice
   points strictly between its two endpoints. Those $k$ points are interior to $P$ but boundary for both halves; the two
   endpoints are boundary everywhere. So $I=I_1+I_2+k$ and $B=B_1+B_2-2k-2$. Then
   $f(P_1)+f(P_2)=I_1+I_2+\frac{B_1+B_2}{2}-2=(I-k)+\frac{B+2k+2}{2}-2=I+\frac B2-1=f(P)$. Area is additive too.
2. **Every simple polygon has a diagonal** (classic), so by induction it suffices to prove $f=A$ for lattice triangles.
3. **Rectangles** $a\times b$ (axis-parallel): $I=(a-1)(b-1)$, $B=2a+2b$, so $f=ab$. ✓
4. **Right triangles** with legs $a,b$ on the axes: half of the rectangle; if the hypotenuse contains $c$ interior lattice
   points, $I=\frac{(a-1)(b-1)-c}{2}$, $B=a+b+c+1$, giving $f=\frac{ab}{2}$. ✓
5. **Any triangle** = its bounding rectangle minus at most three right triangles (and possibly a rectangle); additivity of
   both $f$ and $A$ finishes it.

**Computing $B$:** an edge from $p$ to $q$ contains $\gcd(\lvert\Delta x\rvert,\lvert\Delta y\rvert)$ lattice points if you count one
endpoint (see [segments](02-lines-segments-and-intersections.md)), so $B=\sum_i\gcd(\lvert\Delta x_i\rvert,\lvert\Delta y_i\rvert)$.
Then $I=\frac{2A-B+2}{2}$ — all integers, no division error.

### 1.3 Point in polygon: ray casting and the half-open rule

Shoot a ray from the query $q$ to the right. Each time it crosses the boundary it switches between inside and outside, so
**$q$ is inside iff the number of crossings is odd**. All the difficulty is degenerate cases: the ray through a vertex, or
along a horizontal edge.

The **half-open rule** removes them: an edge $a\to b$ counts iff exactly one endpoint is strictly above the ray,
`(a.y > q.y) != (b.y > q.y)`. Think of the ray as being at height $q_y+\varepsilon$: a vertex exactly at height $q_y$ is
treated as "below", so a ray through a vertex where the boundary passes straight through is counted once, and a ray touching
a vertex where the boundary turns back is counted $0$ or $2$ times. Horizontal edges never count.

For a counting edge, "the crossing is to the right of $q$" is an orientation test (no division): for an upward edge
($a_y\le q_y<b_y$) it is $\operatorname{orient}(a,b,q)>0$; for a downward edge, $<0$. Check "$q$ is on edge $ab$" first and report
BOUNDARY.

**Winding number** generalises this to self-intersecting polygons: add $+1$ for an upward edge with $q$ on its left, $-1$ for a
downward edge with $q$ on its right. The result is how many times the boundary winds around $q$ ("non-zero rule" vs the
"even–odd rule" above). For simple polygons both agree.

### 1.4 Point in a convex polygon in $O(\log n)$

For a convex polygon (counter-clockwise, $p_0$ any vertex), the diagonals from $p_0$ split it into a fan of triangles
$p_0p_ip_{i+1}$, and the directions $p_i-p_0$ rotate monotonically. So:

1. If $q$ is right of $p_0\to p_1$ or left of $p_0\to p_{n-1}$, it is outside the wedge at $p_0$: OUTSIDE.
2. Binary search the last $i$ with $(p_i-p_0)\times(q-p_0)\ge0$; then $q$ lies in the wedge of triangle $p_0p_ip_{i+1}$.
3. Decide by one more orientation: $\operatorname{orient}(p_i,p_{i+1},q)$. Zero means on the polygon edge $p_ip_{i+1}$; the
   fan edges $p_0p_1$ and $p_0p_{n-1}$ are also polygon edges and need a boundary check.

$O(\log n)$ per query after $O(n)$ preprocessing (orient counter-clockwise; remove collinear vertices if the input may
contain them).

### 1.5 Centroid (🧊)

The centre of mass of a uniform polygon is the area-weighted average of the centroids of the fan triangles $Op_ip_{i+1}$
(centroid $\frac{O+p_i+p_{i+1}}{3}$, signed area $\frac{c_i}{2}$ with $c_i=p_i\times p_{i+1}$). With $O$ the origin,

$$G=\frac{1}{A}\sum_i\frac{p_i+p_{i+1}}{3}\cdot\frac{c_i}{2}=\frac{1}{6A}\sum_i(p_i+p_{i+1})\,(p_i\times p_{i+1}).$$

Signs make it correct for non-convex polygons for the same reason as the area.

---

## 2. Formulas, definitions and identities

| Formula | Meaning | Cost |
|---|---|---|
| $2A=\sum_{i}p_i\times p_{i+1}=\sum_i(x_iy_{i+1}-x_{i+1}y_i)$ | shoelace, signed (CCW positive) | $O(n)$ |
| $2A=\sum_i(x_i-x_{i+1})(y_i+y_{i+1})$ | trapezoid form, same value | $O(n)$ |
| $A=I+\frac B2-1$ | Pick (simple lattice polygon) | |
| $B=\sum_i\gcd(\lvert x_{i+1}-x_i\rvert,\lvert y_{i+1}-y_i\rvert)$ | boundary lattice points | $O(n\log C)$ |
| $I=\frac{2A-B+2}{2}$ | interior lattice points | |
| $G=\frac{1}{6A}\sum_i(p_i+p_{i+1})(p_i\times p_{i+1})$ | centroid | $O(n)$ |
| interior-angle sum $=(n-2)\pi$; regular polygon angle $=\pi-\frac{2\pi}{n}$ | | |
| regular $n$-gon with circumradius $R$: $A=\frac n2R^2\sin\frac{2\pi}{n}$ | $n$ isosceles triangles | |
| convexity: all $(p_{i+1}-p_i)\times(p_{i+2}-p_{i+1})$ have the same sign (ignoring zeros) | and the total turn is $2\pi$ (no self-loops) | $O(n)$ |
| Pick for polygons with $h$ holes: $A=I+\frac B2-1+h$ | Euler-characteristic correction | |

**Generalised Pick (with holes).** Each hole adds one to the right-hand side: the additivity proof goes through, and a polygon
with one hole is two simple polygons glued along two chords. This rarely appears, but it explains why the "$-1$" is really
"$-\chi$" (Euler characteristic of a disc is 1).

**Area of a lattice triangle is a multiple of $\frac12$**: $2A=\lvert\text{cross}\rvert\in\mathbb{Z}$ — the reason for
[CF 1030D · Vasya and Triangle](https://codeforces.com/problemset/problem/1030/D) — 1800 (a triangle of area $\frac{nm}{k}$ exists
iff $2nm$ is divisible by $k$).

---

## 3. Implementation (C++ and Java)

### 3.1 Polygon kit (exact)

```cpp
struct P { ll x, y; };
P operator-(P a, P b) { return {a.x - b.x, a.y - b.y}; }
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
ll cross(P o, P a, P b) { return cross(a - o, b - o); }
ll dot(P a, P b) { return a.x * b.x + a.y * b.y; }
// Twice the signed area; __int128 accumulator because partial sums can exceed 2^63 for coordinates ~1e9.
__int128 area2(const vector<P>& p) {
    __int128 s = 0;
    for (size_t i = 0, n = p.size(); i < n; i++) s += (__int128)p[i].x * p[(i + 1) % n].y - (__int128)p[(i + 1) % n].x * p[i].y;
    return s;
}
ll boundaryPoints(const vector<P>& p) {
    ll b = 0;
    for (size_t i = 0, n = p.size(); i < n; i++) b += gcd(llabs(p[(i + 1) % n].x - p[i].x), llabs(p[(i + 1) % n].y - p[i].y));
    return b;
}
bool onSegment(P a, P b, P q) { return cross(a, b, q) == 0 && dot(a - q, b - q) <= 0; }
// 0 = outside, 1 = boundary, 2 = inside. Any simple polygon, any orientation.
int pointInPolygon(const vector<P>& p, P q) {
    bool in = false;
    for (size_t i = 0, n = p.size(); i < n; i++) {
        P a = p[i], b = p[(i + 1) % n];
        if (onSegment(a, b, q)) return 1;
        if ((a.y > q.y) != (b.y > q.y)) {                       // half-open crossing rule
            ll c = cross(a, b, q);
            if ((b.y > a.y) ? c > 0 : c < 0) in = !in;          // crossing lies to the right of q
        }
    }
    return in ? 2 : 0;
}
// Strictly convex polygon in counter-clockwise order, n >= 3. Same return codes.
int pointInConvex(const vector<P>& p, P q) {
    int n = p.size();
    if (cross(p[0], p[1], q) < 0 || cross(p[0], p[n - 1], q) > 0) return 0;
    int lo = 1, hi = n - 1;
    while (hi - lo > 1) {
        int mid = (lo + hi) / 2;
        if (cross(p[0], p[mid], q) >= 0) lo = mid; else hi = mid;
    }
    ll c = cross(p[lo], p[lo + 1], q);
    if (c < 0) return 0;
    if (c == 0) return 1;
    if ((lo == 1 && cross(p[0], p[1], q) == 0) || (lo + 1 == n - 1 && cross(p[0], p[n - 1], q) == 0)) return 1;
    return 2;
}
```

```java
// Polygon as parallel arrays x[], y[].
static long cross(long ox, long oy, long ax, long ay, long bx, long by) { return (ax - ox) * (by - oy) - (ay - oy) * (bx - ox); }
// Java long arithmetic wraps modulo 2^64 (defined behaviour), so if the true 2A fits in a long the result is exact
// even if partial sums overflow. Use BigInteger only if 2A itself may exceed 9.2e18.
static long area2(long[] x, long[] y) {
    long s = 0; int n = x.length;
    for (int i = 0; i < n; i++) { int j = (i + 1) % n; s += x[i] * y[j] - x[j] * y[i]; }
    return s;
}
static long gcd(long a, long b) { while (b != 0) { long t = a % b; a = b; b = t; } return a; }
static long boundaryPoints(long[] x, long[] y) {
    long b = 0; int n = x.length;
    for (int i = 0; i < n; i++) { int j = (i + 1) % n; b += gcd(Math.abs(x[j] - x[i]), Math.abs(y[j] - y[i])); }
    return b;
}
static boolean onSegment(long ax, long ay, long bx, long by, long qx, long qy) {
    return cross(ax, ay, bx, by, qx, qy) == 0 && (ax - qx) * (bx - qx) + (ay - qy) * (by - qy) <= 0;
}
static int pointInPolygon(long[] x, long[] y, long qx, long qy) {
    boolean in = false; int n = x.length;
    for (int i = 0; i < n; i++) {
        int j = (i + 1) % n;
        if (onSegment(x[i], y[i], x[j], y[j], qx, qy)) return 1;
        if ((y[i] > qy) != (y[j] > qy)) {
            long c = cross(x[i], y[i], x[j], y[j], qx, qy);
            if ((y[j] > y[i]) ? c > 0 : c < 0) in = !in;
        }
    }
    return in ? 2 : 0;
}
static int pointInConvex(long[] x, long[] y, long qx, long qy) {
    int n = x.length;
    if (cross(x[0], y[0], x[1], y[1], qx, qy) < 0 || cross(x[0], y[0], x[n - 1], y[n - 1], qx, qy) > 0) return 0;
    int lo = 1, hi = n - 1;
    while (hi - lo > 1) {
        int mid = (lo + hi) >>> 1;
        if (cross(x[0], y[0], x[mid], y[mid], qx, qy) >= 0) lo = mid; else hi = mid;
    }
    long c = cross(x[lo], y[lo], x[lo + 1], y[lo + 1], qx, qy);
    if (c < 0) return 0;
    if (c == 0) return 1;
    if ((lo == 1 && cross(x[0], y[0], x[1], y[1], qx, qy) == 0) || (lo + 1 == n - 1 && cross(x[0], y[0], x[n - 1], y[n - 1], qx, qy) == 0)) return 1;
    return 2;
}
```

### 3.2 Tested demo: area, orientation and centroid

Input: $n$, then $n$ vertices of a simple polygon. Output: $2A$ (absolute), `CCW`/`CW`, and the centroid.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
using ld = long double;
int main() {
    int n; cin >> n;
    vector<ll> x(n), y(n);
    for (int i = 0; i < n; i++) cin >> x[i] >> y[i];
    __int128 a2 = 0; ld gx = 0, gy = 0;
    for (int i = 0; i < n; i++) {
        int j = (i + 1) % n;
        ll c = x[i] * y[j] - x[j] * y[i];
        a2 += c;
        gx += (ld)(x[i] + x[j]) * c;
        gy += (ld)(y[i] + y[j]) * c;
    }
    ld A = (ld)a2 / 2;                                   // signed: the 1/(6A) formula needs the signed area
    cout << (ll)(a2 < 0 ? -a2 : a2) << ' ' << (a2 > 0 ? "CCW" : "CW") << '\n';
    cout << fixed << setprecision(6) << gx / (6 * A) << ' ' << gy / (6 * A) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        long[] x = new long[n], y = new long[n];
        for (int i = 0; i < n; i++) { st.nextToken(); x[i] = (long) st.nval; st.nextToken(); y[i] = (long) st.nval; }
        long a2 = 0; double gx = 0, gy = 0;
        for (int i = 0; i < n; i++) {
            int j = (i + 1) % n;
            long c = x[i] * y[j] - x[j] * y[i];
            a2 += c;
            gx += (double) (x[i] + x[j]) * c;
            gy += (double) (y[i] + y[j]) * c;
        }
        double A = a2 / 2.0;
        System.out.println(Math.abs(a2) + " " + (a2 > 0 ? "CCW" : "CW"));
        System.out.println(String.format(Locale.US, "%.6f %.6f", gx / (6 * A), gy / (6 * A)));
    }
}
```

<!-- test
in:
4
0 0
4 0
4 2
0 2
out:
16 CCW
2.000000 1.000000
-->
<!-- test
in:
6
0 0
0 3
1 3
1 1
3 1
3 0
out:
10 CW
1.100000 1.100000
-->

---

## 4. Recognising the pattern

| Statement says… | Think… |
|---|---|
| "area of the polygon", "print twice the area" | shoelace, integer, doubled |
| "number of lattice points inside / on the boundary" | Pick + gcd boundary count |
| "is the point inside the polygon" (few queries) | ray casting with half-open rule, boundary first |
| "many queries, convex polygon" | fan binary search, $O(\log n)$ |
| "is polygon B inside convex polygon A" | all vertices of B inside A (convexity of A makes that sufficient) |
| "lattice triangle with area $S$" | $2S$ must be an integer; construct with two axis vectors |
| "symmetric / similar polygon", "Minkowski difference" | central symmetry $p_i+p_{i+n/2}=\text{const}$ |
| "clockwise or counter-clockwise order" | sign of the shoelace sum |

Confusions: Pick needs a **simple lattice** polygon (no self-intersections). The ray-casting rule is even–odd; for
self-intersecting polygons decide whether the statement means even–odd or non-zero winding.

---

## 5. Worked examples (graded)

### Example 1 — Polygon Area  ·  ★ ≈1300

- **Source:** [CSES 2191 · Polygon Area](https://cses.fi/problemset/task/2191)
- **Difficulty:** ≈1300 (est.)
- **Problem:** A simple polygon with $n\le1000$ integer vertices ($\lvert x\rvert,\lvert y\rvert\le10^9$) in order. Print $2A$.
- **Thinking from first principles:** The shoelace sum is $2A$ exactly; the output is designed so that you never divide.
  The only trap is overflow: each term $x_iy_{i+1}-x_{i+1}y_i$ is up to $2\cdot10^{18}$ and the partial sums can exceed $2^{63}$
  even though the final $\lvert2A\rvert\le8\cdot10^{18}$ fits.

<details><summary>Solution</summary>

Accumulate in `__int128` (C++) or rely on Java's defined wrap-around (the true result fits in `long`, so arithmetic modulo
$2^{64}$ returns it exactly). Print the absolute value. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    int n; cin >> n;
    vector<ll> x(n), y(n);
    for (int i = 0; i < n; i++) cin >> x[i] >> y[i];
    __int128 s = 0;
    for (int i = 0; i < n; i++) {
        int j = (i + 1) % n;
        s += (__int128)x[i] * y[j] - (__int128)x[j] * y[i];
    }
    if (s < 0) s = -s;
    cout << (ll)s << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        long[] x = new long[n], y = new long[n];
        for (int i = 0; i < n; i++) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            x[i] = Long.parseLong(st.nextToken()); y[i] = Long.parseLong(st.nextToken());
        }
        long s = 0;                                     // wraps mod 2^64; the final value fits, so it is exact
        for (int i = 0; i < n; i++) { int j = (i + 1) % n; s += x[i] * y[j] - x[j] * y[i]; }
        System.out.println(Math.abs(s));
    }
}
```

</details>

<!-- test
in:
4
2 0
7 1
5 6
0 4
out:
51
-->
<!-- test
in:
4
-1000000000 -1000000000
1000000000 -1000000000
1000000000 1000000000
-1000000000 1000000000
out:
8000000000000000000
-->
<!-- test
in:
3
0 0
0 5
7 0
out:
35
-->

### Example 2 — Polygon Lattice Points  ·  ★ ≈1600

- **Source:** [CSES 2193 · Polygon Lattice Points](https://cses.fi/problemset/task/2193)
- **Difficulty:** ≈1600 (est.)
- **Problem:** Same input format as Example 1, now with $n\le10^5$ (coordinates up to $10^9$). Print the number of lattice
  points strictly inside and on the boundary.
- **Thinking from first principles:** Counting inside points directly is hopeless (area up to $10^{12}$). Boundary points are
  easy edge by edge with gcd. Pick's theorem links the three quantities, so the interior count falls out:
  $I=\frac{2A-B+2}{2}$.

<details><summary>Solution</summary>

$2A$ by shoelace (in `__int128` in C++, wrapping `long` in Java — see Example 1), $B=\sum\gcd$, $I=(2A-B+2)/2$. $O(n\log C)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<ll> x(n), y(n);
    for (int i = 0; i < n; i++) cin >> x[i] >> y[i];
    __int128 s = 0;
    ll b = 0;
    for (int i = 0; i < n; i++) {
        int j = (i + 1) % n;
        s += (__int128)x[i] * y[j] - (__int128)x[j] * y[i];
        b += gcd(llabs(x[j] - x[i]), llabs(y[j] - y[i]));
    }
    ll a2 = (ll)(s < 0 ? -s : s);
    cout << (a2 - b + 2) / 2 << ' ' << b << '\n';
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
        long[] x = new long[n], y = new long[n];
        for (int i = 0; i < n; i++) { st.nextToken(); x[i] = (long) st.nval; st.nextToken(); y[i] = (long) st.nval; }
        long a2 = 0, b = 0;
        for (int i = 0; i < n; i++) {
            int j = (i + 1) % n;
            a2 += x[i] * y[j] - x[j] * y[i];
            b += gcd(Math.abs(x[j] - x[i]), Math.abs(y[j] - y[i]));
        }
        a2 = Math.abs(a2);
        System.out.println((a2 - b + 2) / 2 + " " + b);
    }
}
```

</details>

<!-- test
in:
4
2 0
7 1
5 6
0 4
out:
24 5
-->
<!-- test
in:
5
0 0
6 0
6 6
3 2
0 6
out:
15 20
-->
<!-- test
in:
3
0 0
1 0
0 1
out:
0 3
-->
<!-- test
in:
4
-1000000 -1000000
1000000 -1000000
1000000 1000000
-1000000 1000000
out:
3999996000001 8000000
-->

### Example 3 — Point in Polygon  ·  ★ ≈1700

- **Source:** [CSES 2192 · Point in Polygon](https://cses.fi/problemset/task/2192)
- **Difficulty:** ≈1700 (est.)
- **Problem:** A simple polygon with $n\le1000$ vertices and $m\le1000$ query points, coordinates up to $10^9$. For each query print
  INSIDE, OUTSIDE or BOUNDARY.
- **Thinking from first principles:** $O(nm)=10^6$ allows the plain ray cast per query. Boundary is checked first with the exact
  on-segment test. Then the half-open rule makes vertices and horizontal edges harmless, and the "crossing is to the right"
  question is an orientation sign — so the whole thing is integer.

<details><summary>Solution</summary>

`pointInPolygon` from §3.1. $O(nm)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<ll> x(n), y(n);
    for (int i = 0; i < n; i++) cin >> x[i] >> y[i];
    auto cr = [](ll ox, ll oy, ll ax, ll ay, ll bx, ll by) { return (ax - ox) * (by - oy) - (ay - oy) * (bx - ox); };
    while (m--) {
        ll qx, qy; cin >> qx >> qy;
        bool in = false, bd = false;
        for (int i = 0; i < n && !bd; i++) {
            int j = (i + 1) % n;
            ll c = cr(x[i], y[i], x[j], y[j], qx, qy);
            if (c == 0 && (x[i] - qx) * (x[j] - qx) + (y[i] - qy) * (y[j] - qy) <= 0) bd = true;
            else if ((y[i] > qy) != (y[j] > qy) && ((y[j] > y[i]) ? c > 0 : c < 0)) in = !in;
        }
        cout << (bd ? "BOUNDARY" : in ? "INSIDE" : "OUTSIDE") << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long cr(long ox, long oy, long ax, long ay, long bx, long by) { return (ax - ox) * (by - oy) - (ay - oy) * (bx - ox); }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        st.nextToken(); int m = (int) st.nval;
        long[] x = new long[n], y = new long[n];
        for (int i = 0; i < n; i++) { st.nextToken(); x[i] = (long) st.nval; st.nextToken(); y[i] = (long) st.nval; }
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        while (m-- > 0) {
            st.nextToken(); long qx = (long) st.nval;
            st.nextToken(); long qy = (long) st.nval;
            boolean in = false, bd = false;
            for (int i = 0; i < n && !bd; i++) {
                int j = (i + 1) % n;
                long c = cr(x[i], y[i], x[j], y[j], qx, qy);
                if (c == 0 && (x[i] - qx) * (x[j] - qx) + (y[i] - qy) * (y[j] - qy) <= 0) bd = true;
                else if ((y[i] > qy) != (y[j] > qy) && ((y[j] > y[i]) ? c > 0 : c < 0)) in = !in;
            }
            out.println(bd ? "BOUNDARY" : in ? "INSIDE" : "OUTSIDE");
        }
        out.flush();
    }
}
```

</details>

<!-- test
in:
4 5
2 0
7 1
5 6
0 4
3 3
7 1
8 8
1 2
6 3
out:
INSIDE
BOUNDARY
OUTSIDE
BOUNDARY
INSIDE
-->
<!-- test
in:
6 6
0 0
4 0
4 4
2 2
0 4
0 2
1 2
3 3
2 3
4 2
0 3
-1 2
out:
INSIDE
BOUNDARY
OUTSIDE
BOUNDARY
BOUNDARY
OUTSIDE
-->

### Example 4 — Polygons  ·  ★ 2100

- **Source:** [CF 166B · Polygons](https://codeforces.com/problemset/problem/166/B) — 2100
- **Difficulty:** 2100
- **Problem:** Polygon $A$ is strictly convex with $n\le10^5$ vertices given clockwise; polygon $B$ is simple with $m\le2\cdot10^4$
  vertices given clockwise. Coordinates up to $10^9$. Is $B$ strictly inside $A$ (no point of $B$ on or outside $A$'s boundary)?
- **Thinking from first principles:** Because $A$ is convex, $B\subseteq\operatorname{int}A$ iff every **vertex** of $B$ is strictly inside $A$:
  the interior of a convex set is convex, so it contains every edge of $B$ once it contains both endpoints. So the question is
  $m$ point-in-convex-polygon queries; $O(nm)=2\cdot10^9$ is too slow, the fan binary search gives $O(m\log n)$. Convert $A$ to
  counter-clockwise first (reverse).

<details><summary>Solution</summary>

Reverse $A$, then for each vertex of $B$ require `pointInConvex == 2`. Cross products of differences of coordinates up to
$10^9$ stay below $4\cdot10^{18}$. $O(n+m\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<ll> x(n), y(n);
    for (int i = 0; i < n; i++) cin >> x[i] >> y[i];
    reverse(x.begin(), x.end()); reverse(y.begin(), y.end());      // clockwise -> counter-clockwise
    auto cr = [&](int o, int a, ll qx, ll qy) { return (x[a] - x[o]) * (qy - y[o]) - (y[a] - y[o]) * (qx - x[o]); };
    auto strictlyInside = [&](ll qx, ll qy) {
        if (cr(0, 1, qx, qy) <= 0 || cr(0, n - 1, qx, qy) >= 0) return false;   // includes the boundary edges at p0
        int lo = 1, hi = n - 1;
        while (hi - lo > 1) { int mid = (lo + hi) / 2; if (cr(0, mid, qx, qy) >= 0) lo = mid; else hi = mid; }
        return cr(lo, lo + 1, qx, qy) > 0;
    };
    int m; cin >> m;
    bool ok = true;
    for (int i = 0; i < m; i++) { ll qx, qy; cin >> qx >> qy; if (!strictlyInside(qx, qy)) ok = false; }
    cout << (ok ? "YES" : "NO") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[] x, y;
    static int n;
    static long cr(int o, int a, long qx, long qy) { return (x[a] - x[o]) * (qy - y[o]) - (y[a] - y[o]) * (qx - x[o]); }
    static boolean strictlyInside(long qx, long qy) {
        if (cr(0, 1, qx, qy) <= 0 || cr(0, n - 1, qx, qy) >= 0) return false;
        int lo = 1, hi = n - 1;
        while (hi - lo > 1) { int mid = (lo + hi) >>> 1; if (cr(0, mid, qx, qy) >= 0) lo = mid; else hi = mid; }
        return cr(lo, lo + 1, qx, qy) > 0;
    }
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); n = (int) st.nval;
        x = new long[n]; y = new long[n];
        for (int i = n - 1; i >= 0; i--) { st.nextToken(); x[i] = (long) st.nval; st.nextToken(); y[i] = (long) st.nval; }
        st.nextToken(); int m = (int) st.nval;
        boolean ok = true;
        for (int i = 0; i < m; i++) {
            st.nextToken(); long qx = (long) st.nval;
            st.nextToken(); long qy = (long) st.nval;
            if (!strictlyInside(qx, qy)) ok = false;
        }
        System.out.println(ok ? "YES" : "NO");
    }
}
```

</details>

<!-- test
in:
4
0 0
0 10
10 10
10 0
3
1 1
1 9
9 1
out:
YES
-->
<!-- test
in:
4
0 0
0 10
10 10
10 0
3
1 1
0 5
9 1
out:
NO
-->
<!-- test
in:
3
0 0
5 10
10 0
3
2 4
5 8
6 1
out:
NO
-->
<!-- test
in:
3
0 0
5 10
10 0
3
4 1
5 8
6 1
out:
YES
-->

### Example 5 — Aerodynamic  ·  ★ 1800

- **Source:** [CF 1299B · Aerodynamic](https://codeforces.com/problemset/problem/1299/B) — 1800
- **Difficulty:** 1800
- **Problem:** A strictly convex polygon $P$ ($n\le10^5$, counter-clockwise, coordinates up to $10^9$). $T$ is the set of all
  vectors $u-v$ with $u,v\in P$ (equivalently, all translations $t$ with $P\cap(P+t)\ne\varnothing$). Are $P$ and $T$ similar?
- **Thinking from first principles:** $T=P+(-P)$ is a Minkowski sum ([convex hull](04-convex-hull-and-rotating-calipers.md)):
  its edges are the edges of $P$ and of $-P$ merged by angle, so $T$ is centrally symmetric and has $2n$ edges unless the
  edges of $P$ pair up with opposite parallel edges. Similar to $P$ forces $P$ to have $n$ edges and be centrally symmetric.
  Conversely if $P$ is centrally symmetric about $c$, then $-P=P-2c$ and $T=P+P-2c=2P-2c$, a scaled copy. So the test is:
  **$n$ even and $p_i+p_{i+n/2}$ is the same vector for all $i$**.

<details><summary>Solution</summary>

Check parity, then compare $p_i+p_{i+n/2}$ with $p_0+p_{n/2}$. Sums are up to $2\cdot10^9$: use 64-bit. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
using ll = long long;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<ll> x(n), y(n);
    for (int i = 0; i < n; i++) cin >> x[i] >> y[i];
    bool ok = n % 2 == 0;
    for (int i = 0; ok && i < n / 2; i++)
        if (x[i] + x[i + n / 2] != x[0] + x[n / 2] || y[i] + y[i + n / 2] != y[0] + y[n / 2]) ok = false;
    cout << (ok ? "YES" : "NO") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        long[] x = new long[n], y = new long[n];
        for (int i = 0; i < n; i++) { st.nextToken(); x[i] = (long) st.nval; st.nextToken(); y[i] = (long) st.nval; }
        boolean ok = n % 2 == 0;
        for (int i = 0; ok && i < n / 2; i++)
            if (x[i] + x[i + n / 2] != x[0] + x[n / 2] || y[i] + y[i + n / 2] != y[0] + y[n / 2]) ok = false;
        System.out.println(ok ? "YES" : "NO");
    }
}
```

</details>

<!-- test
in:
4
1 0
4 1
3 4
0 3
out:
YES
-->
<!-- test
in:
3
100 86
50 0
150 0
out:
NO
-->
<!-- test
in:
6
0 0
2 0
3 1
2 2
0 2
-1 1
out:
YES
-->
<!-- test
in:
4
0 0
3 0
3 1
0 2
out:
NO
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Keep $2A$, not $A$.** It is an integer; halve only when printing (and print `.5` yourself if needed:
   `a2/2` then `a2%2 ? ".5" : ""`).
2. **Shoelace overflow**: partial sums can exceed $2^{63}$ for coordinates $\sim10^9$. C++: `__int128` (signed overflow is
   undefined behaviour). Java: `long` wraps, so the final result is right if it fits.
3. **Orientation of input**: many statements give clockwise order; algorithms (convex query, hull merging) assume
   counter-clockwise. Normalise with the sign of the area and `reverse`.
4. **Point-in-polygon: check BOUNDARY before the parity**, or a point on an edge flips randomly.
5. **Half-open rule** `(a.y > q.y) != (b.y > q.y)`: both comparisons strict in the same direction. Mixing `>=` and `>` double-counts vertices.
6. **Pick needs a simple polygon with lattice vertices.** For rational vertices, scale first; for self-intersecting polygons
   it fails.
7. **Point in convex polygon**: collinear vertices in the input break the strict monotonicity — remove them (or build the hull).
8. **Floating centroid**: divide by the *signed* $6A$, not $\lvert A\rvert$, or the sign flips for clockwise input.
9. **"B strictly inside convex A"**: vertices suffice only because $A$ is convex. For non-convex $A$ you also need edge-crossing checks.
10. **Java input**: `StreamTokenizer` parses numbers as `double`; it is exact up to $2^{53}$, fine for $10^9$ coordinates but not for
    $10^{18}$ — use a byte reader for 64-bit inputs.

---

## 7. Going further (toward 2400–2600+)

- **Polygon triangulation counting/DP**: interval DP over vertices with validity of diagonals —
  [CF 437E · The Child and Polygon](https://codeforces.com/problemset/problem/437/E) — 2500, and
  [interval DP](../06-Dynamic-Programming/05-interval-dp.md).
- **Pick's theorem in reverse** (counting lattice polygons by parity of $2A$ and $B$):
  [AtCoder ABC202 F · Integer Convex Hull](https://atcoder.jp/contests/abc202/tasks/abc202_f) — diff≈2905.
- **Polygon clipping** (Sutherland–Hodgman) is half-plane intersection one plane at a time:
  [half-planes](05-sweep-closest-pair-and-half-plane.md).
- **Point location among many polygons** (planar subdivisions) → sweep + persistent structures (IGM-level, rarely set on CF).
- **Rectilinear polygons and sweeps**: [AtCoder ABC211 F · Rectilinear Polygons](https://atcoder.jp/contests/abc211/tasks/abc211_f) — diff≈2350.

---

## 8. Practice ladder

**≤1400**
- [ ] [CF 270A · Fancy Fence](https://codeforces.com/problemset/problem/270/A) — 1100
- [ ] [CF 1312A · Two Regular Polygons](https://codeforces.com/problemset/problem/1312/A) — 800
- [ ] [CSES 2191 · Polygon Area](https://cses.fi/problemset/task/2191)
- [ ] [CF 820B · Mister B and Angle in Polygon](https://codeforces.com/problemset/problem/820/B) — 1300

**1400–1900**
- [ ] [CSES 2193 · Polygon Lattice Points](https://cses.fi/problemset/task/2193)
- [ ] [CSES 2192 · Point in Polygon](https://cses.fi/problemset/task/2192)
- [ ] [CF 559A · Gerald's Hexagon](https://codeforces.com/problemset/problem/559/A) — 1600
- [ ] [CF 1096C · Polygon for the Angle](https://codeforces.com/problemset/problem/1096/C) — 1600
- [ ] [CF 1030D · Vasya and Triangle](https://codeforces.com/problemset/problem/1030/D) — 1800
- [ ] [CF 1299B · Aerodynamic](https://codeforces.com/problemset/problem/1299/B) — 1800

**1900–2300**
- [ ] [CF 166B · Polygons](https://codeforces.com/problemset/problem/166/B) — 2100
- [ ] [CF 1044C · Optimal Polygon Perimeter](https://codeforces.com/problemset/problem/1044/C) — 2100
- [ ] [AtCoder ABC296 G · Polygon and Points](https://atcoder.jp/contests/abc296/tasks/abc296_g) — diff≈2241
- [ ] [AtCoder ABC211 F · Rectilinear Polygons](https://atcoder.jp/contests/abc211/tasks/abc211_f) — diff≈2350

**2400+**
- [ ] [AtCoder ABC251 G · Intersection of Polygons](https://atcoder.jp/contests/abc251/tasks/abc251_g) — diff≈2468
- [ ] [CF 437E · The Child and Polygon](https://codeforces.com/problemset/problem/437/E) — 2500
- [ ] [AtCoder ABC202 F · Integer Convex Hull](https://atcoder.jp/contests/abc202/tasks/abc202_f) — diff≈2905

---

## 9. LeetCode / FAANG cross-reference

- [LC 469 · Convex Polygon](https://leetcode.com/problems/convex-polygon/) — Medium 🔒 — sign of consecutive edge crosses (§2).
- [LC 1039 · Minimum Score Triangulation of Polygon](https://leetcode.com/problems/minimum-score-triangulation-of-polygon/) — Medium — interval DP over a convex polygon's vertices.
- [LC 812 · Largest Triangle Area](https://leetcode.com/problems/largest-triangle-area/) — Easy — shoelace on three points.
- [LC 223 · Rectangle Area](https://leetcode.com/problems/rectangle-area/) — Medium — union area of two axis rectangles.
- [LC 850 · Rectangle Area II](https://leetcode.com/problems/rectangle-area-ii/) — Hard — union of many rectangles: sweep + segment tree.
- [LC 391 · Perfect Rectangle](https://leetcode.com/problems/perfect-rectangle/) — Hard — area sum + corner parity.

Polygon algorithms beyond these are rare in interviews.

---

## 10. Self-check

1. Why does the shoelace sum give the correct area for a non-convex polygon?
2. State Pick's theorem and prove the additivity step.
3. How many lattice points are on the boundary of the triangle $(0,0),(6,4),(2,8)$? How many inside?
4. In ray casting, why is the rule `(a.y > q.y) != (b.y > q.y)` immune to the ray passing through a vertex?
5. Why does "every vertex of $B$ inside convex $A$" imply "$B$ inside $A$"?
6. Write the centroid formula and explain where the factor $\frac16$ comes from.

<details><summary>Answers</summary>

1. Signed triangle areas from any fixed point cover each point of the plane exactly (winding number) times: $1$ inside a CCW
   simple polygon, $0$ outside.
2. $A=I+\frac B2-1$. Cutting along a chord with $k$ interior lattice points: $I=I_1+I_2+k$, $B=B_1+B_2-2k-2$; substituting gives
   $f(P)=f(P_1)+f(P_2)$.
3. Edges: $\gcd(6,4)=2$, $\gcd(4,4)=4$, $\gcd(2,8)=2$, so $B=8$. $2A=\lvert6\cdot8-4\cdot2\rvert=40$, so $I=(40-8+2)/2=17$.
4. A vertex at exactly the ray's height is treated as "below"; the two incident edges count once in total if the boundary crosses
   there and $0$ or $2$ times if it turns back — parity is right either way.
5. The interior of a convex set is convex; it contains both endpoints of each edge of $B$, hence the whole edge, hence the
   boundary of $B$, hence $B$.
6. $G=\frac{1}{6A}\sum(p_i+p_{i+1})(p_i\times p_{i+1})$: triangle centroid $\frac{p_i+p_{i+1}}{3}$ (third vertex at the origin) times
   signed area $\frac{p_i\times p_{i+1}}{2}$, divided by $A$: $\frac13\cdot\frac12=\frac16$.

</details>
