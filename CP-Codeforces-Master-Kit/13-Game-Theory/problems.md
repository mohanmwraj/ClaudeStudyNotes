# Game Theory — Consolidated Problem Ladder

A single ladder for the whole folder, easiest first inside each band. Hints name the technique, not the solution. Codeforces ratings are the official problem ratings; CSES and AtCoder problems carry an estimated rating (AtCoder's own difficulty estimate where it exists). Topic files: [fundamentals](01-game-fundamentals-winning-losing-states.md) · [Nim & Sprague–Grundy](02-nim-and-sprague-grundy.md) · [variants](03-game-variants-misere-staircase-hackenbush.md) · [minimax & game DP](04-minimax-and-game-dp.md) · [cheat sheet](../99-Cheat-Sheets/13-game-theory-cheatsheet.md).

How to use it: solve a band until you clear ~70% without hints, then move up. For every game problem, *write the brute force first* and print the W/L (or Grundy) table — that habit is worth more than any single trick.

## ≤ 1400

- [ ] [CF 1899A · Game with Integers](https://codeforces.com/problemset/problem/1899/A) — 800 — residues, one move lookahead
- [ ] [CF 959A · Mahmoud and Ehab and the even-odd game](https://codeforces.com/problemset/problem/959/A) — 800 — parity
- [ ] [CF 1373B · 01 Game](https://codeforces.com/problemset/problem/1373/B) — 900 — count the moves
- [ ] [CF 1419A · Digit Game](https://codeforces.com/problemset/problem/1419/A) — 900 — who controls the last digit
- [ ] [CF 1695B · Circle Game](https://codeforces.com/problemset/problem/1695/B) — 1000 — parity of $n$, then a minimum
- [ ] [CF 1365A · Matrix Game](https://codeforces.com/problemset/problem/1365/A) — 1100 — number of available moves is fixed
- [ ] [CF 1382B · Sequential Nim](https://codeforces.com/problemset/problem/1382/B) — 1100 — who gets control first
- [ ] [CF 2004C · Splitting Items](https://codeforces.com/problemset/problem/2004/C) — 1100 — sorted greedy minimax
- [ ] [CF 1472D · Even-Odd Game](https://codeforces.com/problemset/problem/1472/D) — 1200 — greedy over a sorted list
- [ ] [CF 1527B1 · Palindrome Game (easy version)](https://codeforces.com/problemset/problem/1527/B1) — 1200 — small case analysis
- [ ] [CF 276B · Little Girl and Game](https://codeforces.com/problemset/problem/276/B) — 1300 — parity of odd counts
- [ ] [AtCoder DP K · Stones](https://atcoder.jp/contests/dp/tasks/dp_k) — ≈1200 (est.) — subtraction game DP
- [ ] [CSES 1730 · Nim Game I](https://cses.fi/problemset/task/1730) — ≈1300 (est.) — Nim
- [ ] [AtCoder ABC201 D · Game in Momotetsu World](https://atcoder.jp/contests/abc201/tasks/abc201_d) — ≈1300 (AtCoder ≈1317) — grid minimax DP
- [ ] [CF 1370C · Number Game](https://codeforces.com/problemset/problem/1370/C) — 1400 — factor structure, small cases
- [ ] [CF 1965A · Everything Nim](https://codeforces.com/problemset/problem/1965/A) — 1400 — distinct sizes, who controls
- [ ] [CSES 1729 · Stick Game](https://cses.fi/problemset/task/1729) — ≈1400 (est.) — W/L DP

## 1400–1700

- [ ] [CSES 1098 · Nim Game II](https://cses.fi/problemset/task/1098) — ≈1500 (est.) — per-pile Grundy values
- [ ] [CF 859C · Pie Rules](https://codeforces.com/problemset/problem/859/C) — 1500 — decision-token DP
- [ ] [CF 1738C · Even Number Addicts](https://codeforces.com/problemset/problem/1738/C) — 1500 — game DP on counts
- [ ] [AtCoder DP L · Deque](https://atcoder.jp/contests/dp/tasks/dp_l) — ≈1600 (est.) — interval negamax
- [ ] [AtCoder ABC195 E · Lucky 7 Battle](https://atcoder.jp/contests/abc195/tasks/abc195_e) — ≈1600 (AtCoder ≈1609) — backward DP over residues
- [ ] [CF 197A · Plate Game](https://codeforces.com/problemset/problem/197/A) — 1600 — symmetry
- [ ] [CF 1363C · Game On Leaves](https://codeforces.com/problemset/problem/1363/C) — 1600 — forced move count
- [ ] [CF 346A · Alice and Bob](https://codeforces.com/problemset/problem/346/A) — 1600 — the final set is forced
- [ ] [CF 1033C · Permutation Game](https://codeforces.com/problemset/problem/1033/C) — 1600 — W/L on a DAG, order of processing
- [ ] [CF 1921E · Eat the Chip](https://codeforces.com/problemset/problem/1921/E) — 1600 — distance parity, chase
- [ ] [CSES 2208 · Another Game](https://cses.fi/problemset/task/2208) — ≈1600 (est.) — moves touch many piles

## 1700–1900

- [ ] [CF 1537D · Deleting Divisors](https://codeforces.com/problemset/problem/1537/D) — 1700 — brute-force the pattern, then prove
- [ ] [CF 1194D · 1-2-K Game](https://codeforces.com/problemset/problem/1194/D) — 1700 — pattern in two parameters
- [ ] [CF 1215D · Ticket Game](https://codeforces.com/problemset/problem/1215/D) — 1700 — pairing strategy
- [ ] [CF 493D · Vasya and Chess](https://codeforces.com/problemset/problem/493/D) — 1700 — parity / symmetry
- [ ] [CF 1451D · Circle Game](https://codeforces.com/problemset/problem/1451/D) — 1700 — symmetry about the diagonal
- [ ] [CF 917B · MADMAX](https://codeforces.com/problemset/problem/917/B) — 1700 — DAG game DP with extra state
- [ ] [CF 1772E · Permutation Game](https://codeforces.com/problemset/problem/1772/E) — 1700 — race counting
- [ ] [CF 1873H · Mad City](https://codeforces.com/problemset/problem/1873/H) — 1700 — pursuit on a graph with one cycle
- [ ] [CF 1970C2 · Game on Tree (Medium)](https://codeforces.com/problemset/problem/1970/C2) — 1700 — W/L on a tree, every root
- [ ] [CSES 1099 · Stair Game](https://cses.fi/problemset/task/1099) — ≈1700 (est.) — staircase Nim
- [ ] [CF 1396B · Stoned Game](https://codeforces.com/problemset/problem/1396/B) — 1800 — largest pile vs the rest
- [ ] [CF 1190B · Tokitsukaze, CSL and Stone Game](https://codeforces.com/problemset/problem/1190/B) — 1800 — legality of the first move
- [ ] [CF 1728D · Letter Picking](https://codeforces.com/problemset/problem/1728/D) — 1800 — interval DP with comparison outcome
- [ ] [CF 148D · Bag of mice](https://codeforces.com/problemset/problem/148/D) — 1800 — probability game DP
- [ ] [AtCoder ABC297 G · Constrained Nim 2](https://atcoder.jp/contests/abc297/tasks/abc297_g) — ≈1800 (AtCoder ≈1834) — per-pile Grundy formula

## 1900–2100

- [ ] [CF 1527B2 · Palindrome Game (hard version)](https://codeforces.com/problemset/problem/1527/B2) — 1900 — case analysis with a reverse move
- [ ] [CF 1404B · Tree Tag](https://codeforces.com/problemset/problem/1404/B) — 1900 — distances and diameter
- [ ] [CF 455B · A Lot of Games](https://codeforces.com/problemset/problem/455/B) — 1900 — series of games
- [ ] [CF 1383B · GameGame](https://codeforces.com/problemset/problem/1383/B) — 1900 — highest bit decides
- [ ] [CF 1495B · Let's Go Hiking](https://codeforces.com/problemset/problem/1495/B) — 1900 — longest monotone runs
- [ ] [CF 1991E · Coloring Game](https://codeforces.com/problemset/problem/1991/E) — 1900 — interactive, choose your role
- [ ] [CF 1970C3 · Game on Tree (Hard)](https://codeforces.com/problemset/problem/1970/C3) — 1900 — rerooting W/L
- [ ] [CF 55C · Pie or die](https://codeforces.com/problemset/problem/55/C) — 1900 — distance to the border
- [ ] [CF 786A · Berzerk](https://codeforces.com/problemset/problem/786/A) — 2000 — retrograde BFS with loops
- [ ] [CF 15C · Industrial Nim](https://codeforces.com/problemset/problem/15/C) — 2000 — XOR of ranges
- [ ] [CF 1147C · Thanos Nim](https://codeforces.com/problemset/problem/1147/C) — 2000 — multi-pile moves, minimum
- [ ] [CF 78C · Beaver Game](https://codeforces.com/problemset/problem/78/C) — 2000 — mirror strategy
- [ ] [CF 87C · Interesting Game](https://codeforces.com/problemset/problem/87/C) — 2000 — splitting game Grundy
- [ ] [CF 39E · What Has Dirichlet Got to Do with That?](https://codeforces.com/problemset/problem/39/E) — 2000 — game DP with draws
- [ ] [CF 63E · Sweets Game](https://codeforces.com/problemset/problem/63/E) — 2000 — bitmask W/L
- [ ] [CSES 2207 · Grundy's Game](https://cses.fi/problemset/task/2207) — ≈2000 (est.) — splitting Grundy for large $n$

## 2100–2400

- [ ] [CF 768E · Game of Stones](https://codeforces.com/problemset/problem/768/E) — 2100 — brute-force Grundy, find formula
- [ ] [CF 936B · Sleepy Game](https://codeforces.com/problemset/problem/936/B) — 2100 — parity-layered graph search, cycles
- [ ] [CF 2004E · Not a Nim Problem](https://codeforces.com/problemset/problem/2004/E) — 2100 — Grundy pattern by brute force
- [ ] [CF 282D · Yet Another Number Game](https://codeforces.com/problemset/problem/282/D) — 2100 — Wythoff
- [ ] [CF 1628D1 · Game on Sum (Easy Version)](https://codeforces.com/problemset/problem/1628/D1) — 2100 — minimax DP with averaging
- [ ] [AtCoder AGC017 D · Game on Tree](https://atcoder.jp/contests/agc017/tasks/agc017_d) — ≈2150 (AtCoder ≈2156) — Green Hackenbush
- [ ] [AtCoder ABC209 E · Shiritori](https://atcoder.jp/contests/abc209/tasks/abc209_e) — ≈2150 (AtCoder ≈2153) — retrograde with draws
- [ ] [AtCoder ABC172 F · Unfair Nim](https://atcoder.jp/contests/abc172/tasks/abc172_f) — ≈2200 (AtCoder ≈2216) — Nim + bitwise construction
- [ ] [AtCoder ABC206 F · Interval Game 2](https://atcoder.jp/contests/abc206/tasks/abc206_f) — ≈2200 (AtCoder ≈2221) — interval Grundy
- [ ] [CF 603C · Lieges of Legendre](https://codeforces.com/problemset/problem/603/C) — 2200 — splitting, parity of $k$
- [ ] [CF 850C · Arpa and a game with Mojtaba](https://codeforces.com/problemset/problem/850/C) — 2200 — Grundy of bitmasks per prime
- [ ] [CF 731E · Funny Game](https://codeforces.com/problemset/problem/731/E) — 2200 — negamax over prefix sums
- [ ] [CF 549C · The Game Of Parity](https://codeforces.com/problemset/problem/549/C) — 2200 — who controls the last moves
- [ ] [CF 377C · Captains Mode](https://codeforces.com/problemset/problem/377/C) — 2200 — bitmask minimax
- [ ] [CF 255E · Furlo and Rublo and Game](https://codeforces.com/problemset/problem/255/E) — 2200 — Grundy over value ranges
- [ ] [CF 167C · Wizards and Numbers](https://codeforces.com/problemset/problem/167/C) — 2300 — Euclid-type recursion
- [ ] [CF 812E · Sagheer and Apple Tree](https://codeforces.com/problemset/problem/812/E) — 2300 — staircase Nim on a tree
- [ ] [CF 305E · Playing with String](https://codeforces.com/problemset/problem/305/E) — 2300 — splitting Grundy on segments
- [ ] [CF 317D · Game with Powers](https://codeforces.com/problemset/problem/317/D) — 2300 — offline Grundy precomputation
- [ ] [CF 1190C · Tokitsukaze and Duel](https://codeforces.com/problemset/problem/1190/C) — 2300 — win now, or force a draw

## 2400+

- [ ] [CF 662A · Gambling Nim](https://codeforces.com/problemset/problem/662/A) — 2400 — Nim + XOR basis
- [ ] [CF 1934D2 · XOR Break --- Game Version](https://codeforces.com/problemset/problem/1934/D2) — 2400 — interactive, choose your role
- [ ] [CF 1628D2 · Game on Sum (Hard Version)](https://codeforces.com/problemset/problem/1628/D2) — 2400 — closed form of a minimax DP
- [ ] [CF 1099F · Cookies](https://codeforces.com/problemset/problem/1099/F) — 2400 — tree game DP + data structure
- [ ] [CF 1498F · Christmas Game](https://codeforces.com/problemset/problem/1498/F) — 2500 — staircase Nim on a tree, rerooting
- [ ] [CF 1312F · Attack on Red Kingdom](https://codeforces.com/problemset/problem/1312/F) — 2500 — Grundy periodicity detection
- [ ] [CF 1221E · Game With String](https://codeforces.com/problemset/problem/1221/E) — 2500 — partisan segment game, case analysis
- [ ] [CF 1823E · Removing Graph](https://codeforces.com/problemset/problem/1823/E) — 2500 — Grundy of cycles
- [ ] [AtCoder ABC278 G · Generalized Subtraction Game](https://atcoder.jp/contests/abc278/tasks/abc278_g) — ≈2550 (AtCoder ≈2533) — interactive, symmetry + Grundy
- [ ] [AtCoder ABC261 Ex · Game on Graph](https://atcoder.jp/contests/abc261/tasks/abc261_h) — ≈2550 (AtCoder ≈2531) — weighted retrograde analysis
- [ ] [CF 1375F · Integer Game](https://codeforces.com/problemset/problem/1375/F) — 2600 — interactive, choose your role
- [ ] [CF 1704F · Colouring Game](https://codeforces.com/problemset/problem/1704/F) — 2600 — octal-game periodicity
- [ ] [CF 919F · A Game With Numbers](https://codeforces.com/problemset/problem/919/F) — 2600 — retrograde BFS on a large state space
- [ ] [AtCoder ARC079 F · Namori Grundy](https://atcoder.jp/contests/arc079/tasks/arc079_d) — ≈2650 (AtCoder ≈2636) — Grundy on a functional graph
- [ ] [CF 1411G · No Game No Life](https://codeforces.com/problemset/problem/1411/G) — 2700 — small Grundy values + linear algebra
- [ ] [CF 1451F · Nullify The Matrix](https://codeforces.com/problemset/problem/1451/F) — 2700 — hidden Nim structure on diagonals
- [ ] [CF 2043F · Nim](https://codeforces.com/problemset/problem/2043/F) — 2700 — counting removals to reach XOR 0
- [ ] [AtCoder ABC255 G · Constrained Nim](https://atcoder.jp/contests/abc255/tasks/abc255_g) — ≈2750 (AtCoder ≈2734) — Grundy with forbidden moves
- [ ] [CF 1149E · Election Promises](https://codeforces.com/problemset/problem/1149/E) — 3200 — Grundy levels on a DAG
- [ ] [AtCoder AGC016 F · Games on DAG](https://atcoder.jp/contests/agc016/tasks/agc016_f) — ≈3750 (AtCoder ≈3754) — counting Grundy assignments

## LeetCode (interview-style game problems)

- [ ] [LC 292 · Nim Game](https://leetcode.com/problems/nim-game/) — Easy — Bash game
- [ ] [LC 1025 · Divisor Game](https://leetcode.com/problems/divisor-game/) — Easy — W/L table, then parity
- [ ] [LC 877 · Stone Game](https://leetcode.com/problems/stone-game/) — Medium — interval DP or a pairing argument
- [ ] [LC 486 · Predict the Winner](https://leetcode.com/problems/predict-the-winner/) — Medium — interval negamax
- [ ] [LC 464 · Can I Win](https://leetcode.com/problems/can-i-win/) — Medium — bitmask minimax
- [ ] [LC 1140 · Stone Game II](https://leetcode.com/problems/stone-game-ii/) — Medium — (index, M) state
- [ ] [LC 1690 · Stone Game VII](https://leetcode.com/problems/stone-game-vii/) — Medium — interval negamax with sums
- [ ] [LC 1686 · Stone Game VI](https://leetcode.com/problems/stone-game-vi/) — Medium — greedy by combined value
- [ ] [LC 2029 · Stone Game IX](https://leetcode.com/problems/stone-game-ix/) — Medium — residues mod 3
- [ ] [LC 1927 · Sum Game](https://leetcode.com/problems/sum-game/) — Medium — pairing strategy
- [ ] [LC 1145 · Binary Tree Coloring Game](https://leetcode.com/problems/binary-tree-coloring-game/) — Medium — component sizes
- [ ] [LC 375 · Guess Number Higher or Lower II](https://leetcode.com/problems/guess-number-higher-or-lower-ii/) — Medium — minimax cost on intervals
- [ ] [LC 1406 · Stone Game III](https://leetcode.com/problems/stone-game-iii/) — Hard — suffix negamax
- [ ] [LC 1510 · Stone Game IV](https://leetcode.com/problems/stone-game-iv/) — Hard — subtraction game with squares
- [ ] [LC 1563 · Stone Game V](https://leetcode.com/problems/stone-game-v/) — Hard — interval DP
- [ ] [LC 1872 · Stone Game VIII](https://leetcode.com/problems/stone-game-viii/) — Hard — negamax collapses to a running max
- [ ] [LC 810 · Chalkboard XOR Game](https://leetcode.com/problems/chalkboard-xor-game/) — Hard — parity argument
- [ ] [LC 913 · Cat and Mouse](https://leetcode.com/problems/cat-and-mouse/) — Hard — retrograde analysis with draws
- [ ] [LC 1728 · Cat and Mouse II](https://leetcode.com/problems/cat-and-mouse-ii/) — Hard — retrograde on a grid
- [ ] [LC 294 · Flip Game II](https://leetcode.com/problems/flip-game-ii/) — Medium 🔒 — memo or Grundy of segments
