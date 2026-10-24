# 07 — DP Optimisations

A DP is correct long before it is fast. This folder is about the second step: you have a correct recurrence that is a factor of $n$ (or $k$, or $2^n$, or $10^{18}$) too slow, and you need to remove the waste **without changing the answer**. Every technique here is a theorem of the form "if the recurrence has shape X and property Y, then this cheaper computation gives the same values" — so the skill is half algebra (recognise the shape) and half proof (check the property, or refute it with a brute force).

## First-principles overview

The running time of a DP is (number of states) × (work per state). Each optimisation attacks one factor, and there are only a few kinds of waste:

1. **Recomputing an aggregate over overlapping predecessor sets.** $dp[i] = h(i) + \bigoplus_{j \in S(i)} g(j)$ where consecutive $S(i)$ overlap. If $\oplus$ is invertible use prefix sums; if it is $\min/\max$ over a sliding window use a monotonic deque; if $S(i)$ is a growing prefix keep a running best. → [01](01-prefix-sum-and-monotonic-queue-optimization.md)
2. **A transition that is a product of an $i$-term and a $j$-term.** $dp[i] = \min_j (m_j x_i + b_j) + d_i$ — every earlier state is a line, every new state a query on the lower envelope. → [02](02-convex-hull-trick-and-li-chao-tree.md)
3. **Scanning split points that can't be optimal.** If the optimal split point is monotone — guaranteed by the *quadrangle inequality* of the cost — you never need to look left of the previous optimum: divide & conquer ($O(kn\log n)$) or Knuth's two-sided bound ($O(n^2)$). → [03](03-divide-and-conquer-optimization.md), [04](04-knuth-optimization.md)
4. **Summing over all submasks one by one.** $\sum_{T \subseteq S} f(T)$ for every $S$ costs $3^n$ naively; doing it one bit at a time (the zeta transform) costs $n 2^n$, and it turns OR/AND/XOR/subset convolutions into pointwise products. → [05](05-sos-dp-and-subset-convolution.md)
5. **A dimension that only counts how many things you used.** When the optimum is convex in that count $k$, price each use at $\lambda$ and drop the dimension; binary search the price (Lagrangian relaxation). → [06](06-aliens-trick-wqs-binary-search.md)
6. **Storing a whole function value-by-value when it is convex piecewise linear.** Keep only the breakpoints in two heaps; "add $|x - a|$" and "take prefix minimum" become $O(\log n)$ heap operations. → [07](07-slope-trick.md)
7. **Iterating a fixed linear (or $(\min,+)$) step $10^{18}$ times.** A constant-size state with a fixed transition is a matrix; repeated squaring does $n$ steps in $O(m^3 \log n)$. → [08](08-matrix-exponentiation-for-dp.md)

A useful habit, shared by many strong competitors: **write the naive DP first, always**. It is the specification, the stress-test oracle, and usually the thing whose algebra tells you which of the seven optimisations applies. Every optimised solution in this folder was checked against its naive DP on random inputs.

## Which optimisation? (decision table)

| Your recurrence looks like | Check | Use |
|---|---|---|
| $\sum_{j=L_i}^{R_i} dp[j]$ | — | prefix sums ([01](01-prefix-sum-and-monotonic-queue-optimization.md)) |
| $\min_{j \in [L_i, R_i]} dp[j]$ | $L_i, R_i$ non-decreasing | monotonic deque ([01](01-prefix-sum-and-monotonic-queue-optimization.md)) |
| $\min_j dp[j] + m_j x_i + b_j$ | slopes / queries sorted? | deque hull, Li Chao, LineContainer ([02](02-convex-hull-trick-and-li-chao-tree.md)) |
| $\min_{j<i} dp_{t-1}[j] + C(j, i)$, $k$ layers | $C$ has QI | D&C $O(kn\log n)$ ([03](03-divide-and-conquer-optimization.md)) or layered Knuth $O(n^2)$ ([04](04-knuth-optimization.md)) |
| $\min_{j<i} dp[j] + C(j, i)$, one layer | $C$ has QI | deque + binary search ([03](03-divide-and-conquer-optimization.md)) |
| $C(i,j) + \min_k dp[i][k] + dp[k+1][j]$ | QI + monotone, $C$ independent of $k$ | Knuth $O(n^2)$ ([04](04-knuth-optimization.md)) |
| $\sum_{T \subseteq S} f(T)$, $\bigoplus$ over $A \cup B = S$ | $n \le 20..23$ | SOS / zeta–Möbius / Walsh–Hadamard ([05](05-sos-dp-and-subset-convolution.md)) |
| "exactly / at most $k$" adds a dimension | $f(k)$ convex | Aliens ([06](06-aliens-trick-wqs-binary-search.md)) |
| $dp_i(x) = \min_{y \text{ near } x} dp_{i-1}(y) + |x - a_i|$ | functions convex piecewise linear | slope trick ([07](07-slope-trick.md)) |
| $v_{t+1} = T v_t$, $t$ up to $10^{18}$ | state size $m \le 100$ | matrix power ([08](08-matrix-exponentiation-for-dp.md)) |

## The shared proof toolkit

Five mathematical facts carry almost the whole folder; learn them once and the files become variations:

| Fact | Where it is used |
|---|---|
| **Domination:** an older candidate that is no better than a newer one can be deleted when windows only move right | monotonic deque (01), CHT deque (02), monotone-decision deque (03) |
| **Single crossing:** two lines (or two candidates under the quadrangle inequality) swap order at most once | CHT hull and Li Chao (02), D&C and Knuth bounds (03, 04) |
| **Quadrangle inequality** $C(a,c) + C(b,d) \le C(a,d) + C(b,c)$ ⇒ optimal split points are monotone | D&C (03), Knuth (04), convexity in $k$ for Aliens (06) |
| **Convexity is preserved** by adding convex functions, taking infimal convolutions and prefix minima | Aliens (06), slope trick (07) |
| **Associativity of the step** (ordinary or $(\min,+)$ matrix product) ⇒ repeated squaring | matrix power (08), segment trees of matrices |

When a proof is not obvious, a brute-force check is: compare the optimised and naive DPs on thousands of random tiny inputs, or test the local quadrangle inequality / second differences directly. Every "this technique is not valid here" claim in the folder (matrix chain, group maxima, distinct-count minimisation) comes with a concrete counterexample found that way.

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 Prefix-sum & monotonic-queue](01-prefix-sum-and-monotonic-queue-optimization.md) | 🔵 1600–2100 | 🔥 | medium | Range-sum transitions, sliding-window min/max, bounded knapsack by residues, running best |
| [02 Convex hull trick & Li Chao](02-convex-hull-trick-and-li-chao-tree.md) | 🟣 1900–2400 (🔴 variants) | 🔥 | low | States as lines; deque hull, LineContainer, Li Chao (also on segments); exact 128-bit comparisons |
| [03 Divide & conquer optimisation](03-divide-and-conquer-optimization.md) | 🟠 2100–2600 | 🔥 | low | Quadrangle inequality ⇒ monotone optimum; $O(kn\log n)$ layers, moving-window costs, 1D monotone decisions |
| [04 Knuth optimisation](04-knuth-optimization.md) | 🟠 2100–2500 | ⚡ | low | $\mathrm{opt}[i][j-1] \le \mathrm{opt}[i][j] \le \mathrm{opt}[i+1][j]$, Yao's conditions, optimal BST, layered $O(n^2)$ |
| [05 SOS DP & subset convolution](05-sos-dp-and-subset-convolution.md) | 🟠 2000–2400 (🔴 subset conv.) | ⚡ | low | Zeta/Möbius on the subset lattice, OR/AND/XOR convolution, ranked subset convolution |
| [06 Aliens trick / WQS](06-aliens-trick-wqs-binary-search.md) | 🟠 2200–2600 | ⚡ | low | Convex $f(k)$: price each use, binary search $\lambda$, the tie-breaking rule that always works |
| [07 Slope trick](07-slope-trick.md) | 🟠 2200–2500 | ⚡ | low | Convex piecewise-linear functions as two heaps of breakpoints; non-decreasing array with min changes |
| [08 Matrix exponentiation for DP](08-matrix-exponentiation-for-dp.md) | 🔵 1700–2100 (🟠 semirings) | 🔥 | low | Linear recurrences, walks of length $k$, $(\min,+)$ powers, augmented states for sums and constants |

## Prerequisites

- [06 Dynamic Programming](../06-Dynamic-Programming/README.md) — all of it; especially [state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md), [knapsack](../06-Dynamic-Programming/02-knapsack-family.md), [interval DP](../06-Dynamic-Programming/05-interval-dp.md) and [bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md).
- [Prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md), [monotonic stack and deque](../02-Core-Techniques/04-monotonic-stack-and-deque.md), [binary search on the answer](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md).
- [Segment trees](../08-Data-Structures/02-segment-tree-basics.md) and [heaps](../08-Data-Structures/10-ordered-sets-pbds-and-heaps.md) for Li Chao and slope trick; [modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) and [matrices](../15-Advanced-Math/01-matrices-and-linear-recurrences.md) for 08.

## Recommended study order

1. **01** (prefix sums / deque) — the most frequent by far, from Div 2 C upwards.
2. **08** (matrix power) — mechanical, appears at 1700–2100, and teaches "a DP step is a linear map".
3. **02** (CHT / Li Chao) — the first "algebraic" optimisation; learn Li Chao as the default and the deque for speed.
4. **03** (D&C) — learn the quadrangle inequality here; it is the key to 04 and 06.
5. **05** (SOS) — independent of the others; do it when bitmask problems start appearing in your rounds.
6. **04** (Knuth) — short once 03 is understood.
7. **06** (Aliens) and **07** (slope trick) — Master-level; both reward the convexity intuition built in 03.

## How this shows up in rounds

- **Div 2 C–D (1500–2000):** prefix-sum transitions and sliding-window minima inside a DP; small matrix powers ("$n \le 10^{18}$, state of size 2–5"); the occasional SOS counting task.
- **Div 2 E–F / Div 1 B–C (2000–2400):** CHT with an overflow trap, D&C optimisation on "split into $k$ groups", SOS with inclusion–exclusion, slope trick on "make the array monotone".
- **Div 1 D+ (2400+):** combinations — Aliens + CHT, D&C with a data-structure cost, Li Chao merging on trees, subset convolution, segment trees of matrices. At this level the optimisation is rarely the whole problem; recognising which one the final recurrence needs is the last step of a longer reduction.
- **Educational rounds** like the classic forms (Frog 3-style CHT, Kittens-style deques) and reward exact arithmetic.

## Links

- Consolidated ladder: [problems.md](problems.md)
- Revision sheet: [DP optimisations cheat sheet](../99-Cheat-Sheets/07-dp-optimizations-cheatsheet.md)
- Next domains that reuse these ideas: [08 Data Structures](../08-Data-Structures/README.md) (Li Chao, segment trees of matrices), [15 Advanced Math](../15-Advanced-Math/README.md) (FFT/NTT, Berlekamp–Massey), [16 IGM Frontier](../16-IGM-Frontier/README.md) (CDQ, offline tricks)
