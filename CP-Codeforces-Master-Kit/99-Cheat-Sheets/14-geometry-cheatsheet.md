# Geometry cheat sheet

Revision only — derivations live in [14-Geometry](../14-Geometry/README.md): [vectors](../14-Geometry/01-vectors-dot-cross-and-precision.md) ·
[lines](../14-Geometry/02-lines-segments-and-intersections.md) · [polygons](../14-Geometry/03-polygons-area-pick-point-in-polygon.md) ·
[hull](../14-Geometry/04-convex-hull-and-rotating-calipers.md) · [sweep](../14-Geometry/05-sweep-closest-pair-and-half-plane.md) ·
[circles](../14-Geometry/06-circles-and-advanced-geometry.md).

## 1. Core formulas

| Quantity | Formula | Note |
|---|---|---|
| dot | $a\cdot b=a_xb_x+a_yb_y=\lvert a\rvert\lvert b\rvert\cos\theta$ | sign: acute / right / obtuse |
| cross | $a\times b=a_xb_y-a_yb_x=\lvert a\rvert\lvert b\rvert\sin\theta$ | $>0$: $b$ is CCW of $a$ |
| orientation | $\operatorname{sgn}((B-A)\times(C-A))$ | $+1$ left turn |
| angle $a\to b$ | $\operatorname{atan2}(a\times b,\ a\cdot b)$ | never `acos` |
| rotation | $(x\cos\theta-y\sin\theta,\ x\sin\theta+y\cos\theta)$; $90^\circ$: $(-y,x)$ | |
| projection on $AB$ | $A+\frac{(P-A)\cdot(B-A)}{\lvert B-A\rvert^2}(B-A)$ | reflection $=2\,\text{proj}-P$ |
| dist to line | $\frac{\lvert(B-A)\times(P-A)\rvert}{\lvert B-A\rvert}$ | |
| line ∩ line | $t=\frac{(C-A)\times e}{d\times e}$ for $A+td$, $C+se$ | $d\times e=0$: parallel |
| on segment | $(B-A)\times(P-A)=0\ \wedge\ (A-P)\cdot(B-P)\le0$ | exact |
| lattice pts on segment | $\gcd(\lvert\Delta x\rvert,\lvert\Delta y\rvert)+1$ | |
| shoelace | $2A=\sum p_i\times p_{i+1}$ | sign = orientation |
| Pick | $A=I+\frac B2-1$, $B=\sum\gcd$ | $I=\frac{2A-B+2}{2}$ |
| centroid | $\frac{1}{6A}\sum(p_i+p_{i+1})(p_i\times p_{i+1})$ | signed $A$ |
| regular $n$-gon | area $\frac n2R^2\sin\frac{2\pi}n$, angle $\pi-\frac{2\pi}n$ | |
| circle ∩ circle | $a=\frac{d^2+r_1^2-r_2^2}{2d}$, $h=\sqrt{r_1^2-a^2}$ | |
| tangent from $p$ | length $\sqrt{d^2-r^2}$, angle at centre $\arccos\frac rd$ | |
| circumcentre | $A+\frac{(b_y\lvert a\rvert^2-a_y\lvert b\rvert^2,\ a_x\lvert b\rvert^2-b_x\lvert a\rvert^2)}{2(a\times b)}$, $a=B-A$, $b=C-A$ | $R=\frac{abc}{4K}$ |
| segment area | $\frac{r^2}2(\theta-\sin\theta)$ | small $\theta$: series |
| stable Heron | $16K^2=((r_1+r_2)^2-d^2)(d^2-(r_1-r_2)^2)$ | exact integer brackets |
| Manhattan ↔ Chebyshev | $\lvert\Delta x\rvert+\lvert\Delta y\rvert=\max(\lvert\Delta u\rvert,\lvert\Delta v\rvert)$, $u=x+y$, $v=x-y$ | Cheb $=\frac{\lvert\Delta u\rvert+\lvert\Delta v\rvert}2$ |
| sorted pair sum | $\sum_{i<j}\lvert a_i-a_j\rvert=\sum_k a_{(k)}(2k-n-1)$ | 1-indexed |
| Euler | $V-E+F=1+C$ | $F$ includes outer face |
| regions | lines: $1+n+\binom n2$; chords: $1+\binom n2+\binom n4$ | general position |
| 3D cross | $(a_yb_z-a_zb_y,\ a_zb_x-a_xb_z,\ a_xb_y-a_yb_x)$ | volume $=\frac16\lvert a\cdot(b\times c)\rvert$ |

## 2. Integer-type bounds ($\lvert\text{coord}\rvert\le C$)

| Expression | Max magnitude | $C=10^9$ |
|---|---|---|
| $B-A$ | $2C$ | needs `long long` |
| $(B-A)\times(C-A)$ | $4C^2$ | $4\cdot10^{18}$ ✓ `ll` |
| squared distance, dot of differences | $8C^2$ | $8\cdot10^{18}$ ✓ `ll` (no slack) |
| shoelace partial sums | can exceed $2^{63}$ | `__int128` / Java `long` wraps (final fits) |
| intersection point numerators | $\sim C^3$ | `__int128` or `long double` |
| in-circle / triple product | $\sim C^4$ / $C^3$ | 128-bit only for small $C$ |
| `double` exact integers | $2^{53}\approx9\cdot10^{15}$ | cross exact only for $C\le\sim4\cdot10^7$ |
| `long double` (GCC x86) mantissa | 64 bits | Java has none; MSVC `long double` = `double` |

## 3. Complexities

| Task | Algorithm | Time |
|---|---|---|
| hull | monotone chain | $O(n\log n)$ |
| diameter / width / min-area rectangle | rotating calipers | $O(h)$ after hull |
| point in convex polygon | fan binary search | $O(\log n)$ |
| point in polygon | ray casting / winding | $O(n)$ |
| Minkowski sum of convex polygons | edge merge by angle | $O(n+m)$ |
| closest pair | sweep + set / D&C | $O(n\log n)$ |
| any segment intersection | Shamos–Hoey | $O(n\log n)$ |
| half-plane intersection | sort by angle + deque | $O(n\log n)$ |
| min enclosing circle | Welzl, shuffled | expected $O(n)$ |
| union of circles | arcs + Green | $O(n^2\log n)$ |
| Manhattan MST | 4 octant sweeps + Kruskal | $O(n\log n)$ |

## 4. Signal → technique

| Signal | Technique |
|---|---|
| "left/right/clockwise", "collinear" | cross product sign |
| "sort by angle", "sweep a ray" | half-plane split + cross comparator, doubled array two pointers |
| "decimal input with $k$ digits" | scale by $10^k$, integers |
| "lines $y=kx+b$, max at many $x$" | CHT / upper hull of $(k,b)$ |
| "parabolas $y=x^2+bx+c$" | $z=y-x^2$ → lines |
| "$(i-j)^2+(S_i-S_j)^2$" | closest pair of $(i,S_i)$ |
| "Manhattan", "king moves" | rotate $(x+y,x-y)$ |
| "farthest pair" | hull + calipers (Euclid) / $u,v$ extremes (Manhattan) |
| "regions / pieces" | Euler's formula, crossings ± 1 per cut |
| "smallest circle covering points" | Welzl |
| "lattice points inside polygon" | Pick |
| "polygon strictly inside convex polygon" | all vertices strictly inside, $O(\log n)$ each |

## 5. Templates

### 5.1 Exact kit + polar sort

```cpp
struct P { ll x, y; };
P operator-(P a, P b) { return {a.x - b.x, a.y - b.y}; }
ll cross(P a, P b) { return a.x * b.y - a.y * b.x; }
ll dot(P a, P b) { return a.x * b.x + a.y * b.y; }
ll cross(P o, P a, P b) { return cross(a - o, b - o); }
int half(P p) { return p.y < 0 || (p.y == 0 && p.x < 0); }
bool polarLess(P a, P b) { return half(a) != half(b) ? half(a) < half(b) : cross(a, b) > 0; }
bool onSeg(P a, P b, P p) { return cross(a, b, p) == 0 && dot(a - p, b - p) <= 0; }
bool segInter(P a, P b, P c, P d) {
    auto s = [](ll v) { return (v > 0) - (v < 0); };
    int o1 = s(cross(a, b, c)), o2 = s(cross(a, b, d)), o3 = s(cross(c, d, a)), o4 = s(cross(c, d, b));
    if (o1 * o2 < 0 && o3 * o4 < 0) return true;
    return (!o1 && onSeg(a, b, c)) || (!o2 && onSeg(a, b, d)) || (!o3 && onSeg(c, d, a)) || (!o4 && onSeg(c, d, b));
}
```

```java
static long cross(long ox, long oy, long ax, long ay, long bx, long by) { return (ax - ox) * (by - oy) - (ay - oy) * (bx - ox); }
static int half(long x, long y) { return (y < 0 || (y == 0 && x < 0)) ? 1 : 0; }
static final Comparator<long[]> POLAR = (a, b) -> {
    int ha = half(a[0], a[1]), hb = half(b[0], b[1]);
    if (ha != hb) return ha - hb;
    long c = a[0] * b[1] - a[1] * b[0];
    return c > 0 ? -1 : (c < 0 ? 1 : 0);
};
static boolean onSeg(long[] a, long[] b, long[] p) {
    return cross(a[0], a[1], b[0], b[1], p[0], p[1]) == 0 && (a[0] - p[0]) * (b[0] - p[0]) + (a[1] - p[1]) * (b[1] - p[1]) <= 0;
}
static boolean segInter(long[] a, long[] b, long[] c, long[] d) {
    int o1 = Long.signum(cross(a[0], a[1], b[0], b[1], c[0], c[1])), o2 = Long.signum(cross(a[0], a[1], b[0], b[1], d[0], d[1]));
    int o3 = Long.signum(cross(c[0], c[1], d[0], d[1], a[0], a[1])), o4 = Long.signum(cross(c[0], c[1], d[0], d[1], b[0], b[1]));
    if (o1 * o2 < 0 && o3 * o4 < 0) return true;
    return (o1 == 0 && onSeg(a, b, c)) || (o2 == 0 && onSeg(a, b, d)) || (o3 == 0 && onSeg(c, d, a)) || (o4 == 0 && onSeg(c, d, b));
}
```

### 5.2 Hull (monotone chain) + diameter

```cpp
// pts sorted & unique, n >= 3 not all collinear. keep = keep collinear boundary points.
vector<pair<ll, ll>> hull(vector<pair<ll, ll>> p, bool keep) {
    sort(p.begin(), p.end()); p.erase(unique(p.begin(), p.end()), p.end());
    int n = p.size(), k = 0;
    if (n <= 2) return p;
    vector<pair<ll, ll>> h(2 * n);
    auto cr = [](pair<ll, ll> o, pair<ll, ll> a, pair<ll, ll> b) { return (a.first - o.first) * (b.second - o.second) - (a.second - o.second) * (b.first - o.first); };
    auto bad = [&](ll c) { return keep ? c < 0 : c <= 0; };
    for (int i = 0; i < n; i++) { while (k >= 2 && bad(cr(h[k - 2], h[k - 1], p[i]))) k--; h[k++] = p[i]; }
    for (int i = n - 2, t = k + 1; i >= 0; i--) { while (k >= t && bad(cr(h[k - 2], h[k - 1], p[i]))) k--; h[k++] = p[i]; }
    h.resize(k - 1);
    return h;
}
ll diam2(const vector<pair<ll, ll>>& h) {               // strict hull, size >= 3
    int m = h.size(); ll best = 0;
    auto d2 = [](pair<ll, ll> a, pair<ll, ll> b) { ll dx = a.first - b.first, dy = a.second - b.second; return dx * dx + dy * dy; };
    for (int i = 0, j = 1; i < m; i++) {
        int ni = (i + 1) % m;
        auto ex = h[ni].first - h[i].first, ey = h[ni].second - h[i].second;
        while (ex * (h[(j + 1) % m].second - h[j].second) - ey * (h[(j + 1) % m].first - h[j].first) > 0) j = (j + 1) % m;
        best = max({best, d2(h[i], h[j]), d2(h[ni], h[j])});
    }
    return best;
}
```

```java
static long[][] hull(long[][] pts, boolean keep) {          // pts distinct; returns CCW hull
    long[][] p = pts.clone();
    Arrays.sort(p, (a, b) -> a[0] != b[0] ? Long.compare(a[0], b[0]) : Long.compare(a[1], b[1]));
    int n = p.length, k = 0;
    if (n <= 2) return p;
    long[][] h = new long[2 * n][];
    for (int i = 0; i < n; i++) {
        while (k >= 2 && (keep ? cr(h[k - 2], h[k - 1], p[i]) < 0 : cr(h[k - 2], h[k - 1], p[i]) <= 0)) k--;
        h[k++] = p[i];
    }
    for (int i = n - 2, t = k + 1; i >= 0; i--) {
        while (k >= t && (keep ? cr(h[k - 2], h[k - 1], p[i]) < 0 : cr(h[k - 2], h[k - 1], p[i]) <= 0)) k--;
        h[k++] = p[i];
    }
    return Arrays.copyOf(h, k - 1);
}
static long cr(long[] o, long[] a, long[] b) { return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]); }
```

### 5.3 Point in polygon (exact) and in convex polygon

```cpp
// 0 out, 1 boundary, 2 in.
int pip(const vector<pair<ll, ll>>& p, ll qx, ll qy) {
    bool in = false; int n = p.size();
    for (int i = 0; i < n; i++) {
        auto [ax, ay] = p[i]; auto [bx, by] = p[(i + 1) % n];
        ll c = (bx - ax) * (qy - ay) - (by - ay) * (qx - ax);
        if (c == 0 && (ax - qx) * (bx - qx) + (ay - qy) * (by - qy) <= 0) return 1;
        if ((ay > qy) != (by > qy) && ((by > ay) ? c > 0 : c < 0)) in = !in;
    }
    return in ? 2 : 0;
}
```

```java
static int pip(long[] x, long[] y, long qx, long qy) {
    boolean in = false; int n = x.length;
    for (int i = 0; i < n; i++) {
        int j = (i + 1) % n;
        long c = (x[j] - x[i]) * (qy - y[i]) - (y[j] - y[i]) * (qx - x[i]);
        if (c == 0 && (x[i] - qx) * (x[j] - qx) + (y[i] - qy) * (y[j] - qy) <= 0) return 1;
        if ((y[i] > qy) != (y[j] > qy) && ((y[j] > y[i]) ? c > 0 : c < 0)) in = !in;
    }
    return in ? 2 : 0;
}
```

Convex $O(\log n)$ (CCW, strictly convex): reject if right of $p_0p_1$ or left of $p_0p_{n-1}$; binary search last $i$ with
$(p_i-p_0)\times(q-p_0)\ge0$; answer by $\operatorname{orient}(p_i,p_{i+1},q)$; boundary also on $p_0p_1$ ($i=1$) and $p_0p_{n-1}$ ($i=n-2$).

### 5.4 Welzl minimum enclosing circle

```cpp
array<ld, 3> mec(vector<array<ld, 2>> p) {             // {cx, cy, r}
    shuffle(p.begin(), p.end(), mt19937(7));
    auto dist = [](ld ax, ld ay, ld bx, ld by) { return hypotl(ax - bx, ay - by); };
    ld cx = p[0][0], cy = p[0][1], r = 0;
    auto out = [&](const array<ld, 2>& q) { return dist(q[0], q[1], cx, cy) > r + 1e-9L * max((ld)1, r); };
    for (size_t i = 1; i < p.size(); i++) if (out(p[i])) {
        cx = p[i][0]; cy = p[i][1]; r = 0;
        for (size_t j = 0; j < i; j++) if (out(p[j])) {
            cx = (p[i][0] + p[j][0]) / 2; cy = (p[i][1] + p[j][1]) / 2; r = dist(p[i][0], p[i][1], cx, cy);
            for (size_t k = 0; k < j; k++) if (out(p[k])) {
                ld ux = p[j][0] - p[i][0], uy = p[j][1] - p[i][1], wx = p[k][0] - p[i][0], wy = p[k][1] - p[i][1];
                ld d = 2 * (ux * wy - uy * wx);
                if (fabsl(d) < 1e-12L) continue;
                ld u2 = ux * ux + uy * uy, w2 = wx * wx + wy * wy;
                cx = p[i][0] + (wy * u2 - uy * w2) / d; cy = p[i][1] + (ux * w2 - wx * u2) / d;
                r = dist(p[i][0], p[i][1], cx, cy);
            }
        }
    }
    return {cx, cy, r};
}
```

```java
static double[] mec(double[][] pts) {
    double[][] p = pts.clone();
    Random rnd = new Random(7);
    for (int i = p.length - 1; i > 0; i--) { int j = rnd.nextInt(i + 1); double[] t = p[i]; p[i] = p[j]; p[j] = t; }
    double cx = p[0][0], cy = p[0][1], r = 0;
    for (int i = 1; i < p.length; i++) if (Math.hypot(p[i][0] - cx, p[i][1] - cy) > r + 1e-9 * Math.max(1, r)) {
        cx = p[i][0]; cy = p[i][1]; r = 0;
        for (int j = 0; j < i; j++) if (Math.hypot(p[j][0] - cx, p[j][1] - cy) > r + 1e-9 * Math.max(1, r)) {
            cx = (p[i][0] + p[j][0]) / 2; cy = (p[i][1] + p[j][1]) / 2; r = Math.hypot(p[i][0] - cx, p[i][1] - cy);
            for (int k = 0; k < j; k++) if (Math.hypot(p[k][0] - cx, p[k][1] - cy) > r + 1e-9 * Math.max(1, r)) {
                double ux = p[j][0] - p[i][0], uy = p[j][1] - p[i][1], wx = p[k][0] - p[i][0], wy = p[k][1] - p[i][1];
                double d = 2 * (ux * wy - uy * wx);
                if (Math.abs(d) < 1e-12) continue;
                double u2 = ux * ux + uy * uy, w2 = wx * wx + wy * wy;
                cx = p[i][0] + (wy * u2 - uy * w2) / d; cy = p[i][1] + (ux * w2 - wx * u2) / d;
                r = Math.hypot(p[i][0] - cx, p[i][1] - cy);
            }
        }
    }
    return new double[]{cx, cy, r};
}
```

### 5.5 Closest pair (sweep, exact squared distance)

```cpp
ll closest2(vector<pair<ll, ll>> p) {                  // (x, y), n >= 2
    sort(p.begin(), p.end());
    multiset<pair<ll, ll>> s;                           // (y, x)
    ll best = LLONG_MAX; size_t l = 0;
    for (size_t i = 0; i < p.size(); i++) {
        ll d = (ll)ceill(sqrtl((ld)best));
        while (l < i && p[i].first - p[l].first > d) s.erase(s.find({p[l].second, p[l].first})), l++;
        for (auto it = s.lower_bound({p[i].second - d, LLONG_MIN}); it != s.end() && it->first <= p[i].second + d; ++it) {
            ll dx = p[i].first - it->second, dy = p[i].second - it->first;
            best = min(best, dx * dx + dy * dy);
        }
        s.insert({p[i].second, p[i].first});
    }
    return best;
}
```

Java: same loop with a `TreeSet<Long>` of packed keys `((y + OFF) << 32) | (x + OFF)`, clamping the query range to the coordinate
limit so `(LIM + OFF) << 32` stays below $2^{63}$ (see [file 05](../14-Geometry/05-sweep-closest-pair-and-half-plane.md) §3.1).

## 6. Top 10 mistakes

1. Using slopes / dividing — vertical lines, precision. Use cross products.
2. `int` differences of $10^9$ coordinates; Java `(long)(a*b)` instead of `(long)a*b`.
3. Polar sort with `cross` alone (not transitive) or with `atan2` on large coordinates.
4. `acos(dot/(|a||b|))` for angles — use `atan2(cross, dot)`.
5. Point-in-polygon without the boundary check first, or with mixed `>`/`>=` in the half-open rule.
6. Hull: wrong collinear policy; all-collinear input with keep-collinear; duplicates; $h\le2$ in calipers.
7. Comparing `sqrt` values instead of squared integers; epsilon chosen as a magic constant.
8. Shoelace overflow in C++ (`__int128`), forgetting $2A$ is the exact quantity.
9. Thin lens / tiny segment areas computed with naive formulas (catastrophic cancellation).
10. Java output with the default locale (`String.format(Locale.US, ...)`) and `Arrays.sort(long[])` on adversarial data.

## 7. Last-minute before contest

- [ ] Integer kit (`P`, `cross`, `dot`, `orient`, `onSeg`, `segInter`) and polar comparator pasted and compiling.
- [ ] Know the bound table: `ll` is enough for orientation with $10^9$ coordinates, not for degree-3 predicates.
- [ ] Hull function with a `keepCollinear` flag; calipers loop guarded for $h\le2$.
- [ ] Manhattan → $(x+y,x-y)$ reflex.
- [ ] Output: `fixed << setprecision(10)` (C++), `String.format(Locale.US, "%.10f", v)` (Java).
- [ ] If Java and the problem needs `long double`-level precision: rewrite algebraically first, or switch to C++.
