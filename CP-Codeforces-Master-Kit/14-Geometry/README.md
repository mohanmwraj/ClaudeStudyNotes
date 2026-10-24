# 14 — Computational Geometry

Geometry turns pictures into arithmetic. Everything in this folder reduces to a handful of exact predicates
(dot and cross products, orientations, squared distances) plus a few constructions (intersection points, rotations,
circumcentres) that are computed only when the output needs them.

**Honest frequency note.** On Codeforces, pure geometry is *less* common than on ICPC: maybe one problem in a few rounds is
tagged `geometry`, and many of those are really "coordinates + greedy/math". But a Master-level coder must handle the basics
flawlessly — orientation tests, polygon area, hulls, Manhattan rotations and precision discipline appear inside problems from
other domains (convex hull trick in DP, closest pair in disguise, Manhattan distance in graph problems). And when a real geometry
problem *does* appear in Div. 1, it is usually solved by few people — a cheap source of rating for those who prepared.

---

## First-principles overview of the domain

1. **Never divide, never use slopes.** Represent points as vectors and ask every yes/no question as the sign of a polynomial in
   the coordinates: $a\times b$ (orientation, area, side of a line), $a\cdot b$ (angle type, projection), $\lvert p-q\rvert^2$ (distance).
   For integer input these are exact — the question becomes "is my integer type wide enough?" ([file 01](01-vectors-dot-cross-and-precision.md)).
2. **Signed area is additive.** The shoelace formula, polygon orientation, Pick's theorem, centroids and point-in-polygon all come
   from summing signed triangle areas or counting signed crossings ([file 03](03-polygons-area-pick-point-in-polygon.md)).
3. **Convexity gives monotonicity.** On a convex polygon, directions rotate monotonically, so extreme points move monotonically —
   that is why monotone chain, rotating calipers, Minkowski sums and binary search on a convex polygon are linear or logarithmic
   ([file 04](04-convex-hull-and-rotating-calipers.md)).
4. **Sweeps turn pair problems into neighbour problems.** Order objects along an axis or by angle and maintain an active set; a
   packing or adjacency lemma says only $O(1)$ neighbours matter ([file 05](05-sweep-closest-pair-and-half-plane.md)).
5. **Change coordinates to simplify the metric or the shape.** $(x+y,x-y)$ turns Manhattan into Chebyshev; $y-x^2$ turns parabolas
   into lines; $(k,b)$ duality turns line envelopes into hulls.
6. **Precision is designed, not hoped for.** Keep predicates exact, compute cancelling differences algebraically (Heron's formula
   paired into exact integer brackets), use `atan2` not `acos`, choose epsilons from magnitudes
   ([file 06](06-circles-and-advanced-geometry.md), Example 4).

---

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 · Vectors, dot/cross, precision](01-vectors-dot-cross-and-precision.md) | 🔵 1400–2100 | 🔥 | medium | dot/cross from first principles, orientation, exact polar sort, rotation, epsilon strategy, integer-type bounds |
| [02 · Lines, segments, intersections](02-lines-segments-and-intersections.md) | 🔵 1500–2400 | 🔥 | low | line forms, intersection parameter $t$, exact segment intersection, distances, lattice points on segments |
| [03 · Polygons: area, Pick, point in polygon](03-polygons-area-pick-point-in-polygon.md) | 🔵 1500–2100 | 🔥 | low | shoelace derivation, Pick's theorem with proof, ray casting with half-open rule, $O(\log n)$ convex query, centroid |
| [04 · Convex hull, calipers, Minkowski](04-convex-hull-and-rotating-calipers.md) | 🔵 1700 – 🔴 2600 | 🔥/⚡/🧊 | low | monotone chain (collinear policy), diameter/width/min-area rectangle, Minkowski sum, CHT duality |
| [05 · Sweep: closest pair, half-planes, Manhattan](05-sweep-closest-pair-and-half-plane.md) | 🔵 1500 – 🔴 2600 | 🔥/⚡/🧊 | medium | closest pair (packing bound), Shamos–Hoey, half-plane intersection deque, Manhattan↔Chebyshev, Manhattan MST |
| [06 · Circles and advanced](06-circles-and-advanced-geometry.md) | 🔵 1700 – 🔴 2600 | ⚡/🧊 | low | circle intersections, tangents, circumcircle, Welzl MEC, stable lens area, union of circles, Euler's formula, 3D basics |
| [problems.md](problems.md) | all | — | — | ~85 graded problems for the whole folder + LeetCode list |
| [cheat sheet](../99-Cheat-Sheets/14-geometry-cheatsheet.md) | — | — | — | formulas, templates (C++/Java), mistakes, pre-contest checklist |

---

## Prerequisites

- [Integer overflow, precision and fast I/O](../01-Foundations/06-integer-overflow-precision-and-fast-io.md) — `__int128`, `long double`, Java's lack of it.
- [Sorting and comparators](../01-Foundations/05-sorting-and-comparators.md) — strict weak orders (polar sort!).
- [GCD](../04-Number-Theory/01-divisibility-gcd-and-extended-euclid.md) — lattice points, direction normalisation.
- [Sweep line and coordinate compression](../02-Core-Techniques/05-coordinate-compression-and-sweep-line.md), [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md).
- [Binary and ternary search](../02-Core-Techniques/06-ternary-search-and-meet-in-the-middle.md) — "binary search the radius / time".

## Recommended study order

1. **01 → 02 → 03** in one block (about a week): these are the predicates every other file uses. Write the exact kit once and keep it.
2. **05 §1.5 (Manhattan)** early — it is the most frequent geometry idea in non-geometry Codeforces problems.
3. **04 (hull, diameter)** next; connect it to [CHT](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md) while it is fresh.
4. **05 (closest pair, half-planes)** and **06 (circles, MEC, Euler)** when you are around 1900+.
5. The 🧊 items (min-area rectangle, Shamos–Hoey, union of circles, 3D) only after the rest is automatic.

## How geometry shows up in rounds

- **Div. 2 A–C (≤1600):** coordinates and casework — triangle inequalities, rectangles, Manhattan moves, "is it collinear". Exactness and
  `long long` are the whole difficulty.
- **Div. 2 D–E / Div. 1 B (1800–2200):** a real predicate in disguise (orientation counting, polar sort with two pointers, closest pair,
  hull of transformed points), or a precision trap (CF 598C, CF 600D).
- **Div. 1 C+ (2300+):** hull + data structure (dynamic hull, Minkowski with offline queries), sweeps with Euler's formula, half-plane
  intersection inside a binary search, geometry hidden in DP (CHT, Li Chao).
- **Educational / ICPC-style rounds** carry more classic geometry (circles, half-planes, MEC) than regular rounds.

Many strong competitors keep a personal, pre-tested geometry library (exact integer kit + `long double` kit) because writing it
under time pressure is where the WAs come from. Build yours from the code in this folder.

## Links

- Folder ladder: [problems.md](problems.md)
- Revision: [geometry cheat sheet](../99-Cheat-Sheets/14-geometry-cheatsheet.md)
- Related: [CHT and Li Chao](../07-DP-Optimizations/02-convex-hull-trick-and-li-chao-tree.md) ·
  [math, geometry and bits for interviews](../17-FAANG-Interview-DSA/16-math-geometry-and-bit-manipulation.md) ·
  [advanced math](../15-Advanced-Math/README.md)
