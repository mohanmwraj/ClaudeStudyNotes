# 15 — Advanced Mathematics: linear algebra, transforms, polynomials

This folder is the algebra toolbox that sits on top of [number theory](../04-Number-Theory/README.md) and
[combinatorics](../05-Combinatorics-and-Probability/README.md): matrices and recurrences, Gaussian elimination and XOR bases, FFT/NTT and
Walsh–Hadamard transforms, generating functions and power-series algebra, interpolation and Berlekamp–Massey, and determinant tricks
(matrix-tree, LGV, expectation systems).

**Where it shows up.** Matrix power and the XOR basis appear regularly from about 1900. NTT and generating functions are standard in
Div. 1 D–F and in "mod 998244353" problems (that modulus is a strong hint). Interpolation, Berlekamp–Massey and Kirchhoff are rarer but are
exactly the tools that turn an "impossible" 2600 into a template application. For the Master target the 🔥 items are mandatory; the 🔴 items
are what separates 2400 from 2700.

---

## First-principles overview of the domain

1. **Linearity is the superpower.** If tomorrow's state is a *linear* function of today's, the $n$-th state is a matrix power — computable in
   $O(\log n)$ multiplications ([01](01-matrices-and-linear-recurrences.md)). If a set is closed under XOR, it is a vector space over GF(2) and
   has a basis of at most 60 numbers ([02](02-gaussian-elimination-and-xor-basis.md)).
2. **Change of basis makes hard operations pointwise.** Convolution is pointwise multiplication after the DFT (roots of unity), XOR-convolution
   after Walsh–Hadamard, OR/AND-convolution after zeta transforms ([03](03-fft-and-ntt.md)). Choosing the right "coordinates" is the whole trick.
3. **Sequences are power series.** Counting problems become algebra on generating functions: products for independent choices, $\frac1{1-A}$ for
   sequences, $e^{A}$ for sets of labelled pieces. Newton's method turns $1/A$, $\ln A$, $e^A$ into $O(n\log n)$ operations
   ([04](04-polynomials-and-generating-functions.md)).
4. **Structure bounds the degrees of freedom.** A polynomial of degree $d$ is fixed by $d+1$ values; a linear recurrence of order $L$ by $2L$ terms.
   So compute a few small cases by brute force and *extrapolate* exactly — Lagrange interpolation and Berlekamp–Massey
   ([05](05-lagrange-interpolation-and-berlekamp-massey.md)).
5. **Determinants count.** With the right matrix, $\det$ counts spanning trees (Kirchhoff), arborescences (Tutte), or non-intersecting path systems
   (LGV), because sign-reversing involutions cancel everything else ([06](06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)).
6. **Exactness first.** Work modulo a prime when you can; know when `double` FFT is exact (results $\lesssim10^{14}$), when to use three NTT primes,
   and when to randomise to make a "zero test" modulo $p$ trustworthy.

---

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 · Matrices and linear recurrences](01-matrices-and-linear-recurrences.md) | 🔵 1500 – 🔴 2600 | 🔥/⚡/🧊 | low | companion matrix, walks, Fibonacci doubling, geometric series of matrices, exponents mod $p-1$, Kitamasa |
| [02 · Gaussian elimination and XOR basis](02-gaussian-elimination-and-xor-basis.md) | 🔵 1700 – 🔴 2600 | 🔥/⚡/🧊 | low | Gauss over $\mathbb{R}$, $\mathbb{Z}_p$, GF(2); rank, det, $p^{m-r}$; XOR basis (max, $k$-th, count); prefix basis; cycle space |
| [03 · FFT and NTT](03-fft-and-ntt.md) | 🟣 1900 – 🔴 2600 | 🔥/⚡/🔴 | none | DFT derivation, iterative NTT mod 998244353, double-FFT precision, 3-prime CRT, wildcard matching, Walsh–Hadamard |
| [04 · Polynomials and generating functions](04-polynomials-and-generating-functions.md) | 🔵 1600 – 🔴 2800 | ⚡/🔴 | none | OGF/EGF modelling, closed forms, Catalan derivation, Newton inverse/log/exp, D&C products, pentagonal theorem |
| [05 · Lagrange interpolation and Berlekamp–Massey](05-lagrange-interpolation-and-berlekamp-massey.md) | 🟣 2000 – 🔴 2700 | ⚡/🔴 | none | $O(n)$ interpolation on consecutive points, $\sum i^k$, polynomial-valued DPs, BM + Kitamasa pipeline |
| [06 · Matrix-tree, LGV, linear-algebra tricks](06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md) | 🟣 2100 – 🔴 2700 | ⚡/🔴/🧊 | none | Kirchhoff (proof), Tutte, BEST, LGV (proof), det mod composite, tridiagonal expectation systems, weighted Kirchhoff + interpolation |
| [problems.md](problems.md) | all | — | — | ~70 graded problems for the folder + LeetCode list |
| [cheat sheet](../99-Cheat-Sheets/15-advanced-math-cheatsheet.md) | — | — | — | formulas, constants (NTT primes), templates in C++/Java, mistakes |

---

## Prerequisites

- [Modular arithmetic and inverses](../04-Number-Theory/02-modular-arithmetic-and-inverses.md), [Fermat/Euler](../04-Number-Theory/04-euler-phi-fermat-and-euler-theorem.md),
  [primitive roots](../04-Number-Theory/06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) (why $3$ generates $\mathbb{Z}_{998244353}^*$).
- [Binomials and stars and bars](../05-Combinatorics-and-Probability/02-stars-and-bars-and-multisets.md), [Catalan/Stirling/partitions](../05-Combinatorics-and-Probability/04-catalan-stirling-bell-and-partitions.md).
- [Matrix exponentiation for DP](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md) and [SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md).
- [Bit manipulation](../01-Foundations/03-bit-manipulation.md) for XOR bases and Walsh–Hadamard.

## Recommended study order

1. **01** (matrix power, fast doubling) — the most frequent tool; do the CSES Mathematics matrix problems.
2. **02 §1.3–1.5** (XOR basis) — short, high payoff; then Gauss mod $p$.
3. **03** (NTT, pair-sum counting, wildcard matching) — write your own NTT once and keep it.
4. **04** (GF modelling, D&C products) — then Newton's inverse/log/exp when you start Div. 1 D–E.
5. **05** (interpolation, BM) — after 01 and 03; BM is a shortcut worth having.
6. **06** — Kirchhoff and LGV when you meet them; the expectation-system part pairs with
   [probability DP](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md).

## How this domain shows up in rounds

- **Div. 2 C–D (1600–2000):** small matrix powers, Fibonacci-type recurrences, XOR-basis counting ($2^{n-r}$), stars and bars.
- **Div. 2 E / Div. 1 B–C (2100–2400):** matrix power on a derived state, linear basis with a twist (prefix basis, graph cycles), NTT pair counting,
  polynomial power with a "pointwise power" trick.
- **Div. 1 D+ (2400+):** power-series exp/log, D&C NTT, interpolation of a polynomial DP, Kirchhoff with weights, LGV.
- **The modulus is a hint:** $998244353$ ⇒ NTT likely; $10^9+7$ with convolution ⇒ three primes or a smarter formula; small odd moduli (1009) ⇒
  `double` FFT.

Many strong competitors keep pre-tested implementations of NTT, power-series inverse/log/exp, BM and Kitamasa; under contest time
pressure writing these from scratch is where errors happen. The code in this folder is a reasonable starting library.

## Links

- Folder ladder: [problems.md](problems.md) · revision: [advanced math cheat sheet](../99-Cheat-Sheets/15-advanced-math-cheatsheet.md)
- Related: [geometry](../14-Geometry/README.md) (cross products are determinants too) · [IGM frontier](../16-IGM-Frontier/README.md) ·
  [master formula sheet](../99-Cheat-Sheets/00-master-formula-sheet.md)
