# 04 — Number Theory

Number theory in competitive programming is the study of **divisibility and remainders as computational objects**: how to compute with residues instead of huge numbers, how to factor, how to count things that depend on $\gcd$, and how to recover information from remainders. It appears in almost every Codeforces round — usually as one sub-step ("print it modulo $998244353$", "the answer depends only on $\gcd(a, m)$") and sometimes as the whole problem.

## First-principles overview of the domain

Everything in this folder grows from four ideas. If you can rederive these, the rest is technique.

1. **The set $\lbrace ax + by\rbrace$ is the multiples of $\gcd(a, b)$** (Bézout). From it: Euclid's algorithm, extended Euclid, solvability of $ax + by = c$, existence of inverses mod $m$, and the cancellation law. → [01](01-divisibility-gcd-and-extended-euclid.md), [02](02-modular-arithmetic-and-inverses.md)
2. **Residues form a ring; units form a group.** Reduction commutes with $+, -, \times$, division means multiplying by an inverse, and the group of units has size $\varphi(n)$, so $a^{\varphi(n)} \equiv 1$ (Euler). Exponents therefore live modulo the order of the base — which is why huge exponents, power towers and primitive roots are tractable. → [02](02-modular-arithmetic-and-inverses.md), [04](04-euler-phi-fermat-and-euler-theorem.md), [06](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)
3. **Unique factorisation + "let each prime announce its multiples".** Every number is a product of prime powers, and most functions we care about ($d$, $\sigma$, $\varphi$, $\mu$, gcd, lcm) act prime by prime. Sieves compute them for all $n \le N$ at once; Pollard's rho handles single numbers up to $10^{18}$. → [03](03-sieves-and-factorization.md), [06](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md)
4. **Swap the order of summation.** "For each pair, test a gcd condition" becomes "for each divisor $d$, count pairs divisible by $d$", corrected by Möbius coefficients; sums of $\lfloor n/i\rfloor$ collapse into $O(\sqrt n)$ blocks; lattice-point counts under a line become Euclid's algorithm. → [07](07-mobius-dirichlet-and-floor-sums.md)

The **Chinese Remainder Theorem** ties it together: a residue mod $m_1 m_2$ (coprime) *is* a pair of residues, so problems split into prime powers and recombine. → [05](05-crt-and-linear-congruences.md)

## Five formulas to have in your fingers

| Formula | Why it matters |
|---|---|
| $\gcd(a,b) = \gcd(b, a \bmod b)$, $ax + by = \gcd(a,b)$ | every inverse, Diophantine equation and CRT merge |
| $a^{-1} \equiv a^{p-2} \pmod p$; $\text{inv}[i] = -\lfloor p/i\rfloor\,\text{inv}[p \bmod i]$ | division modulo a prime |
| $a^{\varphi(n)} \equiv 1$; $a^e \equiv a^{(e \bmod \varphi) + \varphi}$ for large $e$ | huge exponents |
| $\varphi(n) = n\prod(1 - 1/p)$; $\sum_{d\mid n}\varphi(d) = n$; $\sum_{d\mid n}\mu(d) = [n=1]$ | gcd-conditioned counting |
| $\lfloor n/i\rfloor$ takes $\le 2\sqrt n$ values; block end $\lfloor n/\lfloor n/l\rfloor\rfloor$ | sums up to $10^{12}$ |

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 — Divisibility, gcd, extended Euclid](01-divisibility-gcd-and-extended-euclid.md) | 🟢–🟣 | 🔥 | medium | Bézout from scratch, Lamé, gcd identities, Diophantine equations in a box, subarray-gcd lists. |
| [02 — Modular arithmetic and inverses](02-modular-arithmetic-and-inverses.md) | 🟢–🔵 | 🔥 | medium | Why mod commutes, inverses (Fermat / Euclid / linear table / batch), factorials, 128-bit mulmod, Montgomery/Barrett. |
| [03 — Sieves and factorisation](03-sieves-and-factorization.md) | 🟢–🟣 | 🔥 | medium | Eratosthenes, linear sieve with φ/μ/d/σ, segmented sieve, divisor-count bounds, harmonic loops. |
| [04 — Euler's φ, Fermat, Euler, Wilson](04-euler-phi-fermat-and-euler-theorem.md) | 🔵–🔴 | 🔥 / ⚡ | low | φ formulas and Σφ(d)=n, exponent reduction, generalised Euler, power towers, Wilson. |
| [05 — CRT and linear congruences](05-crt-and-linear-congruences.md) | 🔵–🟠 | 🔥 / ⚡ | low | $ax \equiv b$, non-coprime CRT merging without overflow, counting in ranges, Garner. |
| [06 — Primitive roots, discrete log, Miller–Rabin, Pollard rho](06-primitive-roots-discrete-log-miller-rabin-pollard-rho.md) | 🟣–🔴 | ⚡ / 🧊 | none | Orders, primitive roots, BSGS (incl. non-coprime), deterministic 64-bit MR, Pollard–Brent, Tonelli–Shanks. |
| [07 — Möbius, Dirichlet, floor sums](07-mobius-dirichlet-and-floor-sums.md) | 🟣–🔴 | 🔥 / ⚡ / 🧊 | none | μ and inversion, Dirichlet algebra, gcd sums, floor blocks, floor_sum, Legendre/Kummer/LTE, Du's sieve. |
| [problems.md](problems.md) | all | — | — | ~90-problem ladder by rating band + LeetCode list. |
| [Cheat sheet](../99-Cheat-Sheets/04-number-theory-cheatsheet.md) | — | — | — | Formulas, constants, templates in C++ and Java. |

## Prerequisites

- [Complexity and constraint reading](../01-Foundations/01-complexity-and-constraint-reading.md) — recognising $O(\sqrt n)$, $O(n\log\log n)$, $O(\log)$ budgets.
- [Integer overflow and precision](../01-Foundations/06-integer-overflow-precision-and-fast-io.md) — 64-bit limits, `__int128`, Java `long`.
- [Bit manipulation](../01-Foundations/03-bit-manipulation.md) — binary exponentiation, `__builtin_ctzll`.
- Helpful later: [inclusion–exclusion](../05-Combinatorics-and-Probability/03-inclusion-exclusion.md) (μ is IE over primes), [binomials](../05-Combinatorics-and-Probability/01-counting-principles-and-binomials.md) (factorial tables, Lucas).

## Recommended study order

1. **01 → 02** (one week): gcd, Bézout, modular arithmetic, inverses, factorial tables. These are used in ~30% of Div2 C–E problems.
2. **03** (one week): sieves, spf factorisation, divisor bounds, harmonic loops — the bread and butter of 1600–2000 problems.
3. **04** (a few days): φ and exponent reduction; skip power towers on the first pass.
4. **05** (a few days): CRT merge and range counting; Garner can wait.
5. **07, first half** (one week): μ over gcd conditions, floor blocks. This is the jump from 1900 to 2100+ in number theory.
6. **06** (when you meet it): Miller–Rabin + Pollard as a template; primitive roots before learning NTT.
7. **07, second half** and the 🧊/🔴 items: floor_sum, Du's sieve, LTE — after reaching ~2100.

## How to attack a number-theory problem

Ask these questions in order; most problems fall at one of them.

1. **What are the true sizes?** Values up to $10^7$ → sieve; up to $10^{12}$ → $\sqrt n$ trial division or floor blocks; up to $10^{18}$ → Miller–Rabin / Pollard / `__int128`. The constraint usually names the tool.
2. **Is only a residue needed?** If the answer is "mod $p$", reduce everything, replace division by inverses, and reduce exponents modulo $p - 1$ (only for bases coprime to $p$).
3. **Does the quantity depend only on a gcd, a residue or prime exponents?** Many statements hide that $f(x)$ depends only on $\gcd(x, m)$ (→ $\varphi$), on $x \bmod L$ (→ periodicity, CRT), or on $v_p(x)$ for each $p$ (→ factorise, work per prime, recombine).
4. **Is there a sum over pairs with a gcd/coprimality condition?** Insert $\sum_{d \mid \gcd}\mu(d)$ or $\sum_{d\mid\gcd}\varphi(d)$ and swap the sums; then count multiples of $d$ (harmonic loop) or block $\lfloor n/d\rfloor$.
5. **Is there a "for every multiple / every divisor" structure?** A harmonic loop ($\sum N/d = O(N\log N)$) is almost always affordable; enumerating divisors costs at most $d(n)$ (1344 for $n \le 10^9$).
6. **Is something periodic or a system of remainders?** Merge with CRT; count solutions in a range with floor division; watch the lcm for overflow.
7. **Brute force small cases.** Print the answer for $n \le 30$ and look at it — primes, divisors, $\varphi$ and powers of two jump out of tables.

Useful constants: $\pi(10^6) = 78\,498$; max $d(n)$ is 240 / 1344 / 103 680 for $n \le 10^6 / 10^9 / 10^{18}$; at most 9 / 15 distinct primes below $10^9 / 10^{18}$; prime gaps below $10^{18}$ are at most 1442. More in the [cheat sheet](../99-Cheat-Sheets/04-number-theory-cheatsheet.md).

## How this shows up in rounds

- **Div2 A–B (800–1300):** parity, gcd/lcm observations, "the answer is $\gcd$ of the array", small factorisations.
- **Div2 C–D (1300–1900):** sieve + spf factorisation, gcd of differences, divisors enumeration with the $d(n)$ bound, modular combinatorics, "answer depends on $\gcd(a, m)$" → φ.
- **Div2 E–F / Div1 B–C (1900–2400):** Möbius over gcd conditions, harmonic-sum DP over multiples, CRT with periodic events, generalised Euler, prime-exponent reasoning on lcm/gcd segment trees.
- **Div1 D+ (2400+):** Du/Min_25 sieves, floor_sum variants, discrete logs and primitive roots inside larger constructions, randomised factorisation (Pollard, "pick a random element and factor it").

Many red coders describe number-theory problems as "observation first, technique second": the winning move is usually noticing that the answer depends only on residues, prime exponents or a gcd — the algorithms in this folder then finish the job.

## Links

- Consolidated ladder: [problems.md](problems.md)
- Revision sheet: [04 — number theory cheat sheet](../99-Cheat-Sheets/04-number-theory-cheatsheet.md)
- Next domain: [05 — Combinatorics and Probability](../05-Combinatorics-and-Probability/README.md)
- Related advanced topics: [FFT/NTT](../15-Advanced-Math/03-fft-and-ntt.md), [matrix exponentiation](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md), [randomised algorithms](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md)
