# 13 · Game Theory

Two players, perfect information, no chance, both "play optimally": who wins, or what is the outcome? Codeforces asks this in almost every Div 2 round at some level — from 800-rated parity observations to 2600-rated Grundy-periodicity and interactive "choose your side" problems. FAANG interviews ask the score-game versions (Stone Game I–IX, Predict the Winner, Can I Win, Cat and Mouse).

## First-principles overview of the whole domain

Everything in this folder is one idea applied with increasing cleverness: **backward induction on the graph of positions**.

1. **A position is losing iff every move leads to a winning position** (and terminal positions lose under normal play). Positions form a DAG if the game is finite, so labels exist and a DP computes them in O(V+E) — [file 01](01-game-fundamentals-winning-losing-states.md).
2. When the position graph is too large, compute small cases by **brute force**, guess the pattern, and **prove** it with the three-condition P-set argument — or bypass labels entirely with a **mirror, pairing, parity or strategy-stealing** argument (file 01).
3. When the game is a **sum of independent components**, W/L labels don't compose but **Grundy values** do: $g = \operatorname{mex}$ of option values, and the sum's value is the XOR (Sprague–Grundy). Nim is the prototype — [file 02](02-nim-and-sprague-grundy.md).
4. When the assumptions of Sprague–Grundy break — **misère** endings, moves touching **several piles** (Wythoff, Moore), coins sliding down a **staircase**, graphs with **cycles** in Hackenbush — new P-sets appear, found by the same brute-force-then-prove loop — [file 03](03-game-variants-misere-staircase-hackenbush.md).
5. When the outcome is a **score** (or a comparison, or a series of games), replace the bit by a value: **negamax** $V = \max(\text{gain} - V(\text{next}))$. When positions can **repeat**, run induction backwards from terminal positions (**retrograde BFS**) and label the rest as draws. Interactive problems add a third step: *play* the strategy — [file 04](04-minimax-and-game-dp.md).

The skill that separates ratings is not memorising formulas but the loop **brute force → table → conjecture → proof (or massive check)**. Every file shows that loop on real problems.

## Files

| File | Band | Priority | FAANG | Summary |
|---|---|---|---|---|
| [01 · Fundamentals: winning and losing states](01-game-fundamentals-winning-losing-states.md) | 🟢 1000–1700 | 🔥 | medium | P/N positions, the three-condition proof, backward induction, mirror/pairing/parity/strategy stealing (Chomp), brute-force pattern finding |
| [02 · Nim and Sprague–Grundy](02-nim-and-sprague-grundy.md) | 🔵 1600–2300 | 🔥 | low | Nim proof, mex, Grundy values, sum theorem, subtraction-game periodicity, splitting games, DAG tokens, Green Hackenbush on trees |
| [03 · Variants: misère, staircase, Hackenbush, Wythoff](03-game-variants-misere-staircase-hackenbush.md) | 🟣 1900–2500 | ⚡ | none | misère Nim, staircase Nim, Moore's Nim$_k$ 🧊, Wythoff (exact golden-ratio test), colon/fusion principles, Euclid game 🧊, multi-pile moves, SJ theorem 🔴 |
| [04 · Minimax and game DP](04-minimax-and-game-dp.md) | 🔵 1500–2200 | 🔥 | high | negamax on intervals/subsets/trees, series of games (can-win/can-lose), retrograde BFS with draws, alpha-beta, interactive "choose First/Second" |
| [problems.md](problems.md) | all | — | — | 99 problems by rating band + 20 LeetCode problems |
| [Cheat sheet](../99-Cheat-Sheets/13-game-theory-cheatsheet.md) | — | — | — | formulas, signals, templates in C++ and Java |

## Prerequisites

- [Recursion, brute force and backtracking](../01-Foundations/04-recursion-brute-force-and-backtracking.md) — the brute force you write for every game.
- [Bit manipulation](../01-Foundations/03-bit-manipulation.md) — XOR, highest set bit.
- [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md), [interval DP](../06-Dynamic-Programming/05-interval-dp.md), [bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md).
- [Topological sort and DAG DP](../09-Graphs/04-topological-sort-and-dag-dp.md), [BFS/DFS](../09-Graphs/01-graph-representation-bfs-dfs.md).

## Recommended study order

1. **File 01** §1–§3, then its examples 1–5. Make the brute-force pattern finder (§3.2) your own template — you will reuse it in every game problem.
2. **File 04** §1.1–§1.3 and examples 1, 2, 4 (score games; also the interview-relevant part).
3. **File 02** in full. Prove Nim and the sum theorem on paper once without notes.
4. **File 04** §1.4 (retrograde) and examples 5–6, then the interactive example 3 together with [interactive problems](../03-Greedy-Constructive-Interactive/05-interactive-problems.md).
5. **File 03** — misère and staircase first (🔵/🟣 problems use them), Wythoff and Hackenbush next, Moore/Euclid/SJ last.
6. Work the [problems.md](problems.md) ladder band by band; revise with the [cheat sheet](../99-Cheat-Sheets/13-game-theory-cheatsheet.md) before contests.

Suggested time for the Dec-2027 Master target: ~2 weeks of focused study plus a steady trickle of game problems (one or two a week) in mixed practice.

## How game theory shows up in rounds

- **Div 2 A–B (800–1300):** parity, symmetry, "count the moves", one-move lookahead. The trap is overthinking — brute-force a few cases and the answer is usually a one-liner.
- **Div 2 C–D (1400–2000):** a hidden P-set to conjecture and prove (Deleting Divisors, 1-2-K), Nim in disguise (Sequential Nim, Stair Game), minimax DP on intervals or counts (Letter Picking, Even Number Addicts), tree games (Game on Leaves, Tree Tag).
- **Div 2 E / Div 1 B–C (2000–2400):** Sprague–Grundy with splitting or brute-forced Grundy formulas (Lieges of Legendre, Game of Stones, Not a Nim Problem), retrograde analysis with draws (Berzerk), Euclid-type recursions, staircase Nim on trees.
- **Div 1 D+ (2400+):** Grundy periodicity on octal-like games, Grundy + linear algebra / counting, interactive role-choice games, large-state retrograde analysis.
- **Interactive game problems** (any level from ~1900): you must output `First`/`Second` and then play; correctness of the strategy *and* of the I/O protocol both matter.

Many experienced competitors give the same advice: in a game problem, the first five minutes should be spent writing a brute force and staring at its output, not at the statement.

## The first five minutes of any game problem

1. **Classify.** Impartial or partisan? Normal or misère ending? Win/lose, score, or draw possible (can positions repeat)? Independent components or one big position?
2. **Encode the state** canonically (sorted piles, interval, mask, node + player to move).
3. **Brute force** with memoisation; print a table over the two most natural parameters (W/L, Grundy value, or score).
4. **Conjecture** (period, residue, parity, powers of two, golden ratio, "only these lose").
5. **Prove** with the three conditions — or at least compare formula vs brute force on every value you can compute.
6. Only then optimise: formula, Grundy XOR, DP over a compact state, or retrograde BFS.

## Five results that solve a surprising number of problems

| Result | Where |
|---|---|
| Nim: P $\iff \bigoplus a_i = 0$ | [file 02 §1.2](02-nim-and-sprague-grundy.md) |
| Sprague–Grundy: sum $\Rightarrow$ XOR of mex-values | [file 02 §1.4](02-nim-and-sprague-grundy.md) |
| Bash game: P $\iff n \equiv 0 \pmod{k+1}$ | [file 01 §1.3](01-game-fundamentals-winning-losing-states.md) |
| Staircase Nim: only odd steps count | [file 03 §1.2](03-game-variants-misere-staircase-hackenbush.md) |
| Negamax: $V = \max(\text{gain} - V(\text{next}))$; retrograde BFS for cycles | [file 04 §1.1, §1.4](04-minimax-and-game-dp.md) |

## Common traps across the folder

- Confusing misère with normal play, or misère with "the complement of normal play".
- XORing raw sizes when each pile is a different game; XORing at all when a move touches several piles.
- Accepting a pattern seen on 20 values (Kayles only becomes periodic at 71; Grundy's game has a last P-position at 1222).
- Memoised recursion on a cyclic state graph (use retrograde BFS).
- Floating-point golden ratio for $10^{18}$-sized Wythoff positions.
- Interactive: forgetting to flush, or not keeping the invariant on every move.

## Links

- Consolidated ladder: [problems.md](problems.md)
- Revision: [Game theory cheat sheet](../99-Cheat-Sheets/13-game-theory-cheatsheet.md)
- Related: [interactive problems](../03-Greedy-Constructive-Interactive/05-interactive-problems.md), [invariants and parity](../03-Greedy-Constructive-Interactive/04-invariants-parity-and-ad-hoc-observations.md), [XOR basis](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md), [probability DP](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md)
