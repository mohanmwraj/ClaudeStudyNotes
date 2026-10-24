# 05 — Combinatorics and Probability

Combinatorics is **counting without listing**: how many arrays, paths, colourings, partitions or subsets satisfy a condition — almost always "modulo $998244353$" or "modulo $10^9+7$". Probability is the same skill with weights: expected values and probabilities are sums over outcomes, and in contests they are usually printed as residues too. Together they appear in a large fraction of Codeforces rounds — as the whole problem at 1600–2400, and as the final counting step inside DP, graph and string problems at every level.

## First-principles overview of the domain

Five ideas generate almost everything here.

1. **Sum, product and bijection rules.** Every count is a case split (sum), a sequence of independent choices (product), or a one-to-one correspondence with something already counted. Binomials, multinomials, stars and bars, Catalan paths and Prüfer codes are all bijections in disguise. → [01](01-counting-principles-and-binomials.md), [02](02-stars-and-bars-and-multisets.md)
2. **Count the complement, then correct the overlaps.** When "avoid every bad event" is hard but "force these bad events" is easy, inclusion–exclusion (and its generalisations: binomial inversion, Möbius inversion, "first bad event" DP) converts one into the other. → [03](03-inclusion-exclusion.md)
3. **Decompose by the first / last / largest element.** Recurrences for Catalan (first return), Stirling and Bell (where does the last element go), derangements (where does $n$ go), partitions (smallest part) all come from asking one question about one distinguished element. → [04](04-catalan-stirling-bell-and-partitions.md)
4. **Count up to symmetry by averaging fixed points.** Burnside: distinct objects = average number of configurations fixed by a symmetry; with colourings, fixed points are counted by cycles. → [05](05-burnside-and-polya.md)
5. **Swap the order of summation.** "Sum over all structures of a value" equals "sum over elements of (value × number of structures containing it)". Linearity of expectation is the same identity divided by the number of outcomes, and it holds for dependent variables. → [06](06-probability-and-expected-value.md), [07](07-contribution-technique.md)

The computational substrate is modular arithmetic: factorial and inverse-factorial tables, Lucas for small primes, CRT for composite moduli — see [04 — Number Theory](../04-Number-Theory/README.md).

## Formulas to have in your fingers

| Formula | Typical use |
|---|---|
| $\binom nk = \frac{n!}{k!(n-k)!}$ with factorial / inverse-factorial tables | every "number of ways mod $p$" |
| $\binom{n+k-1}{k-1}$ (stars and bars) and $\binom{n-1}{k-1}$ (positive parts) | distributions, non-decreasing arrays |
| $\sum_S(-1)^{\lvert S\rvert}\lvert\bigcap_S A_i\rvert$; $D_n = (n-1)(D_{n-1}+D_{n-2})$ | avoiding all bad events |
| $C_n = \binom{2n}n - \binom{2n}{n+1}$ | brackets, trees, "never below zero" |
| $\frac1{\lvert G\rvert}\sum_g k^{\text{cycles}(g)}$ | counting up to symmetry |
| $E[\sum I_A] = \sum P(A)$; $E = 1/p$; $nH_n$ | expectations |
| $\sum_S f(S) = \sum_e w(e)\cdot\#\lbrace S \ni e\rbrace$ | sums over subarrays, subsets, pairs |

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 — Counting principles and binomials](01-counting-principles-and-binomials.md) | 🟢–🟠 | 🔥 | medium | Rules of counting, identities by bijection, every way to compute $\binom nk$ (Pascal, factorials, big $n$, Lucas, prime powers). |
| [02 — Stars and bars and multisets](02-stars-and-bars-and-multisets.md) | 🟢–🟠 | 🔥 | medium | The bijection, bounds by shifting and IE, gaps, multisets, the twelvefold way. |
| [03 — Inclusion–exclusion](03-inclusion-exclusion.md) | 🔵–🟠 | 🔥 | low | Indicator proof, derangements, surjections, binomial inversion, subset Möbius, obstacle-path DP. |
| [04 — Catalan, Stirling, Bell, partitions](04-catalan-stirling-bell-and-partitions.md) | 🔵–🔴 | 🔥 / ⚡ / 🧊 | medium | Reflection principle, bracket completions, both Stirling kinds, moments via falling factorials, pentagonal theorem, Fibonacci identities. |
| [05 — Burnside and Pólya](05-burnside-and-polya.md) | 🟣–🟠 | ⚡ | none | Orbit–stabiliser, Burnside, necklaces and bracelets, constrained necklaces, explicit symmetry groups. |
| [06 — Probability and expected value](06-probability-and-expected-value.md) | 🔵–🟠 | 🔥 | medium | Linearity and indicators, tail sums, geometric/coupon collector, probabilities mod $p$, self-referential expectations. |
| [07 — Contribution technique](07-contribution-technique.md) | 🔵–🟣 | 🔥 | high | Sums over subarrays/subsets/pairs/paths by element contribution, tie-breaking for min/max, per-bit counting. |
| [problems.md](problems.md) | all | — | — | ~90-problem ladder by rating band + 32 LeetCode problems. |
| [Cheat sheet](../99-Cheat-Sheets/05-combinatorics-and-probability-cheatsheet.md) | — | — | — | Identities, small values, templates in C++ and Java. |

## Prerequisites

- [Modular arithmetic and inverses](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) — factorial tables, inverses, fast power.
- [Recursion and brute force](../01-Foundations/04-recursion-brute-force-and-backtracking.md) — every counting solution should be checked against a brute force on tiny inputs.
- [Prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md) and [monotonic stacks](../02-Core-Techniques/04-monotonic-stack-and-deque.md) — used by the contribution technique.
- Later: [DP](../06-Dynamic-Programming/README.md) (most hard counting problems are DP with a combinatorial transition), [generating functions and NTT](../15-Advanced-Math/04-polynomials-and-generating-functions.md).

## Recommended study order

1. **01 + 02** (one week): binomial identities, factorial tables, stars and bars. Solve the CSES Mathematics counting tasks.
2. **07** (a few days): the contribution technique — immediately useful in Div2 C/D and FAANG interviews.
3. **06** (one week): linearity of expectation and modular probabilities; expectation DP comes in [the DP folder](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md).
4. **03** (one week): inclusion–exclusion; this is where 1900–2200 counting problems live.
5. **04** (one week): Catalan/reflection first (🔥), Stirling numbers next (⚡), partitions/pentagonal last (🧊).
6. **05** (when it comes up): Burnside is rarer on Codeforces but standard on other judges and in ICPC.

## How to attack a counting or expectation problem

1. **Pin down what is distinguishable.** Are the items labelled? Are the boxes/positions labelled? Is order relevant? Are symmetric configurations identified? Write one tiny example of two objects that should count as *different* and two that should count as the *same* — this decides between $k^n$, $\binom{n+k-1}{k-1}$, $S(n,k)$, $p(n,k)$ and Burnside.
2. **Look for a bijection to a standard object** — a binary string, a lattice path, a multiset, a Dyck path, a sequence of choices. If you can encode objects reversibly, you can count them.
3. **If a condition is "none / all / every", count the complement** and correct with inclusion–exclusion; if it is "exactly $k$", count "at least these $k$" and invert.
4. **If the structure is recursive, distinguish one element** (first, last, largest, root) and write a recurrence — then look for a closed form or just DP it.
5. **If the answer is a sum or an expectation over many structures, swap the summation**: what does each element, pair, bit or edge contribute, and in how many structures?
6. **If the process is random and repeats, condition on the first step** ($E = 1 + \sum p_iE_i$) and solve the resulting equation or DP.
7. **Verify with a brute force** for $n \le 7$ and compare residues; recognise the sequence if you can.

## How this shows up in rounds

- **Div2 A–C (800–1500):** product rule, choosing pairs, small binomials, complement counting, "expected value" of a tiny process.
- **Div2 D–E (1600–2100):** factorial tables with a clever bijection (Two Arrays), contribution sums, inclusion–exclusion over a few properties, linearity of expectation over elements, modular probabilities.
- **Div1 C–E (2100–2600):** inclusion–exclusion with DP on the number of violated constraints, Stirling-number moment tricks, Vandermonde/hockey-stick collapses of a derived sum, expectation with self-reference or potentials, Burnside with constraints.
- **Above 2600:** generating functions with NTT, lattice-path determinants (LGV), exponential formula, min–max inclusion–exclusion.

A habit many strong solvers recommend: whenever you derive a counting formula, **brute-force $n \le 8$ and compare** — and look the small values up mentally (Catalan $1,2,5,14$, Bell $1,2,5,15$, derangements $0,1,2,9,44$) to recognise the structure.

## Links

- Consolidated ladder: [problems.md](problems.md)
- Revision sheet: [05 — combinatorics and probability cheat sheet](../99-Cheat-Sheets/05-combinatorics-and-probability-cheatsheet.md)
- Previous domain: [04 — Number Theory](../04-Number-Theory/README.md) · Next: [06 — Dynamic Programming](../06-Dynamic-Programming/README.md)
- Related: [SOS DP](../07-DP-Optimizations/05-sos-dp-and-subset-convolution.md), [matrix exponentiation](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md), [LGV lemma](../15-Advanced-Math/06-matrix-tree-theorem-lgv-and-linear-algebra-tricks.md)
