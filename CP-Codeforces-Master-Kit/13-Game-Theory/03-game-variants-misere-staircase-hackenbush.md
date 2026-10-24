# Game Variants — Misère, Staircase, Moore, Wythoff, Hackenbush, Euclid

> **Band:** 🟣 1900–2500 · **Priority:** ⚡ · **FAANG:** none · **Prerequisites:** [game fundamentals](01-game-fundamentals-winning-losing-states.md), [Nim and Sprague–Grundy](02-nim-and-sprague-grundy.md)
> **You can say you know this when:** you can state and prove the misère Nim and staircase Nim rules, decide a Wythoff position with exact integer arithmetic for values up to $10^{18}$, reduce a Hackenbush graph with the colon and fusion principles, and recognise when a "Nim-looking" game breaks the Sprague–Grundy assumptions (misère ending, moves touching several piles).

---

## 1. First principles — why this works

Sprague–Grundy (file 02) rests on two assumptions: **normal play** and **moves that touch exactly one component**. Every game in this file breaks one of them, or is a disguised Nim where the "real" components are not the obvious ones. The method stays the same — brute-force the small cases, guess the P-set, prove it with the three conditions of [file 01 §1.3](01-game-fundamentals-winning-losing-states.md) — but the answers are new.

### 1.1 Misère Nim

Same moves as Nim, but **whoever takes the last stone loses**.

**Rule.** If every pile has size $\le 1$, the first player wins iff the number of non-empty piles is **even**. Otherwise (some pile $\ge 2$), the first player wins iff the XOR is **non-zero** — exactly as in normal Nim.

*Intuition.* Play normal Nim until the moment your Nim move would leave only piles of size $\le 1$; at that moment, leave an **odd** number of 1-piles instead (you can, because exactly one pile is $\ge 2$ then and you choose to reduce it to 0 or 1).

*Proof.* Let $\mathcal{P}$ = {all piles $\le 1$ and an odd number of 1s} $\cup$ {some pile $\ge 2$ and XOR $=0$}. In misère play the terminal position (all empty) is a **win** for the player to move, and it is outside $\mathcal{P}$ (zero 1s is even). ✓
- *From $\mathcal{P}$ every move leaves $\mathcal{P}$.* From "all $\le 1$, odd count": a move removes a 1, the count becomes even. From "some $\ge 2$, XOR 0": XOR 0 with a pile $\ge 2$ forces **at least two** piles $\ge 2$ (a single one would leave its high bit uncancelled), so after changing one pile some pile $\ge 2$ remains, and the XOR is now non-zero.
- *From outside $\mathcal{P}$ (non-terminal) some move enters $\mathcal{P}$.* "All $\le 1$, even count $\ge 2$": remove a 1. "Some $\ge 2$, XOR $\ne 0$": if exactly one pile is $\ge 2$, reduce it to 0 or 1 so that the number of 1s is odd; if at least two piles are $\ge 2$, make the normal Nim move to XOR 0 — some pile $\ge 2$ survives. $\square$

### 1.2 Staircase Nim

Coins on steps $0,1,\dots,n$. A move takes any positive number of coins from step $i \ge 1$ and moves them to step $i-1$. Normal play (who cannot move loses — i.e. all coins on step 0).

**Rule.** The position is P iff the XOR of the coin counts on the **odd** steps is 0. Even steps are irrelevant.

*Why even steps don't matter.* A move from an even step $2j$ to the odd step $2j-1$ **adds** coins to an odd step. The opponent of whoever did that can immediately move exactly those coins on to step $2j-2$, restoring the odd-step counts. Such reversible moves can never help (the reverser keeps the invariant). Moves from odd steps to even steps are pure Nim moves on the odd-step piles.

*Proof.* $\mathcal{P}$ = {XOR of odd steps $= 0$}. Terminal: all on step 0, XOR 0 ✓. From $\mathcal{P}$: a move from odd $i$ decreases $a_i$ (XOR changes); a move from even $i$ increases $a_{i-1}$, an odd step (XOR changes) ✓. From outside: make the Nim move on the odd steps (decrease $a_i \to a_i \oplus s$ by moving $a_i - (a_i\oplus s)$ coins down) ✓. $\square$

*Where it hides.* Coins that move "towards a sink" one level at a time: stairs, depths in a tree (move apples from a node to its parent — the **depth parity** plays the role of step parity; [CF 812E · Sagheer and Apple Tree](https://codeforces.com/problemset/problem/812/E) — 2300), "move chips left" games on a line where the gaps between chips are the steps.

### 1.3 Moore's Nim$_k$ 🧊

A move reduces **between 1 and $k$ piles** (each by any positive amount). $k=1$ is Nim.

**Rule.** Write the piles in binary. The position is P iff, **for every bit position**, the number of piles having that bit set is divisible by $k+1$.

*Proof sketch.* (2) From such a position, a move changes $1..k$ piles; at the highest bit where some changed pile changes, every pile that changes there goes $1 \to 0$ (it decreased and its higher bits are unchanged), so that column's count drops by $1..k$ and is no longer $\equiv 0 \pmod{k+1}$. (3) From a non-P position, fix bits from high to low, keeping a set $T$ of "touched" piles ($|T| \le k$): piles in $T$ have already been decreased at a higher bit, so their lower bits are free; at each bit, let $c$ = column count mod $(k+1)$, use free piles of $T$ to set or clear this bit, and if that is not enough, add new piles with this bit set to $T$ (clearing the bit) — the counting shows $|T|$ never exceeds $k$. For $k=1$ this is exactly Bouton's argument. (Rule checked against brute force for $k \le 3$, up to 4 piles of size $<6$.)

### 1.4 Wythoff's game

Two piles. A move removes any positive number from **one** pile, or the **same** positive number from **both**. Normal play. (Equivalently: a chess queen moving towards the corner $(0,0)$.)

This breaks independence (the diagonal move touches both piles), so XOR is useless. Brute force the P-positions with $a\le b$:
$(0,0),(1,2),(3,5),(4,7),(6,10),(8,13),(9,15),(11,18),(12,20),\dots$

Two observations jump out: the differences $b_k - a_k$ are $0,1,2,3,\dots$, and every positive integer appears **exactly once** among all $a_k, b_k$. Greedy description: $a_k = \operatorname{mex}\{a_0,b_0,\dots,a_{k-1},b_{k-1}\}$, $b_k = a_k + k$.

*Proof of the greedy description.* (1) $(0,0)$ is P. (2) No move connects two of these positions: a one-pile move keeps one coordinate, but each integer occurs in only one pair; a diagonal move keeps the difference, but the differences are distinct. (3) From any other $(a,b)$, $a\le b$: if $a = a_k$ and $b > b_k$, reduce $b$ to $b_k$; if $a = a_k$ and $b < b_k$, then $d = b-a < k$ and the diagonal move to $(a_d,b_d)$ is legal ($a_d < a_k$); if $a = b_k$, reduce $b$ to $a_k$. Every $a$ is some $a_k$ or $b_k$. $\square$

**Closed form (Beatty sequences).** With $\varphi = \frac{1+\sqrt5}{2}$: $a_k = \lfloor k\varphi \rfloor$, $b_k = \lfloor k\varphi^2 \rfloor = a_k + k$. The sequences $\lfloor k\alpha\rfloor$, $\lfloor k\beta \rfloor$ partition the positive integers when $\alpha,\beta$ are irrational with $1/\alpha + 1/\beta = 1$ (Rayleigh–Beatty), and $1/\varphi + 1/\varphi^2 = 1$; combined with $\varphi^2 = \varphi + 1$ this matches the greedy description.

**Exact test without floating point.** $\lfloor k\varphi \rfloor = \left\lfloor \frac{k + \sqrt{5k^2}}{2} \right\rfloor = \left\lfloor \frac{k + \lfloor\sqrt{5k^2}\rfloor}{2}\right\rfloor$ (for $k>0$, $\sqrt{5k^2}$ is irrational, and flooring the numerator first does not change the result). So $(a,b)$ with $a\le b$ is P iff $a = \lfloor (k + \operatorname{isqrt}(5k^2))/2 \rfloor$ with $k = b-a$. For $k \le 10^{18}$, $5k^2 < 2^{127}$ fits in `__int128` / `BigInteger`.

Generalisation: if the diagonal move may remove $x$ from one pile and $y$ from the other with $|x-y| < t$, the P-positions are again Beatty pairs: $a_k = \lfloor k\alpha \rfloor$, $b_k = a_k + tk$ with $\alpha = \frac{2-t+\sqrt{t^2+4}}{2}$ ($t=1$ gives $\varphi$; brute-force checked for $t \le 4$ on a $120\times120$ board). Always confirm such a claim with a brute-force table before trusting it.

### 1.5 Green Hackenbush on general graphs

A graph with some vertices on the ground. A move deletes an edge; everything no longer connected to the ground disappears. Normal play.

- **Stalk** of $n$ edges from the ground = Nim heap $n$.
- **Colon principle.** If a subgraph hanging from a single vertex $v$ is replaced by another subgraph with the same Grundy value, the value of the whole graph is unchanged. Consequence for trees: replace each branch by a stalk of length $g(\text{child})+1$ and XOR at the vertex ([file 02 §1.9](02-nim-and-sprague-grundy.md)).
- **Fusion principle.** All vertices on a cycle can be fused into a single vertex without changing the value; the cycle's edges become **loops**, and a loop counts as a stalk of length 1. So an **odd** cycle at a vertex contributes 1 and an **even** cycle contributes 0. (Brute-force check in scratch work: a cycle of length $L$ through the ground has value $L \bmod 2$ for $L \le 9$; the same cycle hung under one extra edge has value $1 + (L \bmod 2)$, matching fusion.)

With colon + fusion, any Green Hackenbush graph reduces to a tree of loops and stalks: fuse each 2-edge-connected component (via bridges-and-cycles decomposition, see [bridges and BCC](../09-Graphs/06-bridges-articulation-points-and-bcc.md)), then evaluate the tree.

### 1.6 Euclid's game and its relatives 🧊

Two numbers $(a,b)$, $a \ge b > 0$. A move subtracts a positive multiple of the smaller from the larger, keeping it $\ge 0$. A player who faces a zero cannot move and loses (equivalently: whoever produces a zero wins).

- If $a = b$ or $a \ge 2b$: the player to move **wins**. If $a=b$ (or $b\mid a$), subtract everything. If $a \ge 2b$ with $r = a \bmod b \ne 0$: from $(r+b, b)$ the *only* move is to $(b, r)$, so exactly one of $(r+b,b)$ and $(b,r)$ is P — and from $(a,b)$ you can reach both. Choose that one.
- If $b < a < 2b$: the only move is to $(b, a-b)$; the status flips.

This gives an $O(\log)$ recursion like Euclid's algorithm. Unrolled: **$(a,b)$ with $a \ge b>0$ is P iff $b < a < \varphi b$** (brute-force checked for $a,b<200$; note $a=b$ is a win, not a loss, despite $1<\varphi$).

The **Bash game** (take $1..k$ from one pile, $n \bmod (k+1)$) was proved in [file 01](01-game-fundamentals-winning-losing-states.md). [CF 167C · Wizards and Numbers](https://codeforces.com/problemset/problem/167/C) — 2300 is a Euclid game with extra "subtract a power" moves (Example 6).

### 1.7 Games that take from several piles at once

When a move touches several piles, look for a **per-pile invariant** that the opponent cannot keep:

- *Take one coin from each of any non-empty set of piles* ([CSES 2208](https://cses.fi/problemset/task/2208), Example 1): only parities matter.
- *Decrease one pile, or all piles by the same amount* ([CF 282D · Yet Another Number Game](https://codeforces.com/problemset/problem/282/D) — 2100, Example 5): two piles = Wythoff; three piles = plain XOR (a brute-force surprise).
- *Take from up to $k$ piles*: Moore's Nim (§1.3).
- *Take from both piles in a fixed ratio*: tabulate, look for Beatty-type pairs.

### 1.8 Nim with per-move limits

Still independent components, so Sprague–Grundy applies — only the per-pile value changes:

| Move on a pile of size $a$ | $g(a)$ |
|---|---|
| remove $1..k$ | $a \bmod (k+1)$ |
| remove between $L$ and $R$ ([AtCoder ABC297 G](https://atcoder.jp/contests/abc297/tasks/abc297_g)) | $\lfloor (a \bmod (L+R)) / L \rfloor$ |
| remove $1..\lfloor a/2 \rfloor$ | $a/2$ if $a$ even, $g(\lfloor a/2\rfloor)$ if odd |
| never repeat an amount on the same pile | $\max\{k: k(k+1)/2 \le a\}$ |

(All four brute-force verified in scratch work.)

### 1.9 Misère sums in general, and the SJ theorem 🔴

Misère Nim is easy; **misère sums of arbitrary games are not** — there is no XOR-like rule in general (Conway's genus theory and Plambeck's misère quotients handle special classes; IGM-and-beyond). One result from the Chinese olympiad literature that does appear in problems is the **Sprague–Jia (SJ) theorem** for "anti-SG" games (sums where the player who makes the last move loses): with the extra stipulation that the game counts as ended when every component has Grundy value 0, the first player wins iff

- the XOR of the components' Grundy values is non-zero **and** some component has value $>1$, **or**
- the XOR is zero **and** every component has value $\le 1$.

For Nim this is exactly §1.1. The stipulation matters, so before using the theorem on a new component game, check it against a brute force (scratch work confirms it on misère sums of subtraction games $\{1..L\}$, $L \le 4$).

---

## 2. Formulas, definitions and identities

| Game | P-positions / value | Proof |
|---|---|---|
| Misère Nim | all piles $\le1$: #ones odd; else XOR $=0$ | §1.1 |
| Staircase Nim (step 0 = ground) | XOR of odd steps $=0$ | §1.2 |
| CSES Stair Game (stairs $1..n$, stair 1 = ground) | XOR of $p_2, p_4, \dots = 0$ | §1.2 shifted by one |
| Moore's Nim$_k$ | every bit column count $\equiv 0 \pmod{k+1}$ | §1.3 |
| Wythoff | $(\lfloor k\varphi\rfloor, \lfloor k\varphi^2\rfloor)$, $b_k = a_k + k$ | §1.4 |
| $\lfloor k\varphi \rfloor$ exactly | $\lfloor (k + \lfloor\sqrt{5k^2}\rfloor)/2 \rfloor$ | §1.4 |
| Euclid game, $a\ge b>0$ | P $\iff b < a < \varphi b$ | §1.6 |
| Bash game | $n \equiv 0 \pmod{k+1}$; misère $n \equiv 1$ | file 01 |
| One coin from each of a chosen set of piles | P $\iff$ all piles even | Example 1 |
| Green Hackenbush stalk / tree / cycle | $n$ / $\bigoplus(g(c)+1)$ / cycle length mod 2 after fusion | §1.5 |
| SJ theorem (anti-SG) | first wins iff (XOR$\ne0$ and some $g>1$) or (XOR$=0$ and all $g\le1$) | §1.9 |
| Golden ratio | $\varphi = \frac{1+\sqrt5}2 \approx 1.6180339887$, $\varphi^2=\varphi+1$, $1/\varphi + 1/\varphi^2 = 1$ | |
| Complexities | misère/staircase/Moore $O(n \log V)$; Wythoff $O(1)$ with isqrt; Euclid $O(\log V)$ | |

---

## 3. Implementation (C++ and Java)

### 3.1 Rules as functions (misère Nim, staircase Nim, Moore's Nim$_k$, Euclid game)

```cpp
// misère Nim: true if the player to move wins
bool misereNimWins(const vector<long long>& a) {
    long long x = 0; bool big = false; int ones = 0;
    for (long long v : a) { x ^= v; if (v > 1) big = true; if (v == 1) ones++; }
    return big ? x != 0 : ones % 2 == 0;
}
// staircase Nim, steps[0] is the ground
bool staircaseWins(const vector<long long>& steps) {
    long long x = 0;
    for (size_t i = 1; i < steps.size(); i += 2) x ^= steps[i];
    return x != 0;
}
// Moore's Nim_k: may reduce up to k piles per move
bool mooreWins(const vector<long long>& a, int k) {
    for (int b = 0; b < 62; b++) {
        int c = 0;
        for (long long v : a) c += (v >> b) & 1;
        if (c % (k + 1) != 0) return true;
    }
    return false;
}
// Euclid game: subtract a multiple of the smaller from the larger; facing a zero loses
bool euclidWins(long long a, long long b) {
    if (a < b) swap(a, b);
    if (b == 0) return false;
    if (a / b >= 2 || a == b) return true;
    return !euclidWins(b, a - b);
}
```

```java
static boolean misereNimWins(long[] a) {
    long x = 0; boolean big = false; int ones = 0;
    for (long v : a) { x ^= v; if (v > 1) big = true; if (v == 1) ones++; }
    return big ? x != 0 : ones % 2 == 0;
}

static boolean staircaseWins(long[] steps) {
    long x = 0;
    for (int i = 1; i < steps.length; i += 2) x ^= steps[i];
    return x != 0;
}

static boolean mooreWins(long[] a, int k) {
    for (int b = 0; b < 62; b++) {
        int c = 0;
        for (long v : a) c += (int) ((v >> b) & 1);
        if (c % (k + 1) != 0) return true;
    }
    return false;
}

static boolean euclidWins(long a, long b) {
    if (a < b) { long t = a; a = b; b = t; }
    if (b == 0) return false;
    if (a / b >= 2 || a == b) return true;
    return !euclidWins(b, a - b);
}
```

### 3.2 Exact Wythoff test for values up to $10^{18}$

```cpp
// floor(sqrt(x)) for x < 2^127
unsigned long long isqrt128(unsigned __int128 x) {
    unsigned long long r = (unsigned long long)sqrtl((long double)x);
    while ((unsigned __int128)r * r > x) r--;
    while ((unsigned __int128)(r + 1) * (r + 1) <= x) r++;
    return r;
}
// true if (a, b) is a P-position of Wythoff's game
bool wythoffP(unsigned long long a, unsigned long long b) {
    if (a > b) swap(a, b);
    unsigned long long k = b - a;
    unsigned __int128 five = (unsigned __int128)k * k * 5;
    unsigned long long ak = (unsigned long long)(((unsigned __int128)k + isqrt128(five)) / 2);   // floor(k*phi)
    return a == ak;
}
```

```java
// true if (a, b) is a P-position of Wythoff's game
static boolean wythoffP(long a, long b) {
    if (a > b) { long t = a; a = b; b = t; }
    BigInteger k = BigInteger.valueOf(b - a);
    BigInteger ak = k.add(k.multiply(k).multiply(BigInteger.valueOf(5)).sqrt()).shiftRight(1);   // floor(k*phi)
    return ak.equals(BigInteger.valueOf(a));
}
```

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| Nim, but "the player who takes the last stone **loses**" | misère Nim: special case when all piles $\le 1$ |
| objects move one level towards a sink (stairs, depth, leftward chips) | staircase Nim: only odd levels count |
| "choose up to $k$ piles and remove from each" | Moore's Nim$_k$: bit columns mod $k+1$ |
| two piles, "same amount from both" allowed | Wythoff: golden ratio |
| two numbers, "subtract a multiple of the other" | Euclid game: ratio vs $2$ and $\varphi$ |
| graph with ground, deleting edges drops disconnected parts | Hackenbush: colon + fusion |
| a move touches several piles, but pile *parities* look decisive | per-pile invariant; brute force first |
| "remove between $L$ and $R$" / "at most half" | per-pile Grundy formula, then XOR |
| misère and several different component games | SJ theorem (check it) or brute force |

Confusions: Wythoff positions look like Fibonacci pairs — they *are* related ($a_k$ is the lower Wythoff sequence) but don't test "consecutive Fibonacci numbers". Staircase games where coins move *two* steps down are staircase Nim on residues mod 2 of the step index divided by 2 — rederive, don't pattern-match.

---

## 5. Worked examples (graded)

### Example 1 — Another Game (one coin from each chosen pile)  ·  ★ ≈1600

- **Source:** [CSES 2208 · Another Game](https://cses.fi/problemset/task/2208)
- **Difficulty:** ≈1600 (est.)
- **Problem:** $n$ heaps $x_i$. A move chooses some non-empty set of non-empty heaps and removes **one** coin from each. Whoever removes the last coin wins. Print `first` or `second`. $\sum n \le 2\cdot10^5$.
- **Thinking from first principles:** A move touches several heaps — not a sum. Brute force with 1–3 small heaps: P-positions are exactly "all heaps even". Why parity? Removing one coin flips the parity of each touched heap.

<details><summary>Solution</summary>

$\mathcal{P}$ = all heaps even. Terminal (all zero) ✓. From all-even, any move makes the touched heaps odd ✓. From a position with some odd heap, remove one coin from **each odd heap** — all heaps become even ✓. So `first` iff some $x_i$ is odd. (Checked by brute force on up to 4 heaps of size $< 5$.) $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        bool odd = false;
        for (int i = 0; i < n; i++) { long long x; cin >> x; if (x & 1) odd = true; }
        cout << (odd ? "first" : "second") << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt();
            boolean odd = false;
            for (int i = 0; i < n; i++) if ((in.nextLong() & 1) == 1) odd = true;
            out.println(odd ? "first" : "second");
        }
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
3
3
1 2 3
2
2 2
4
2 4 6 8
out:
first
second
second
-->
<!-- test
in:
1
1
1
out:
first
-->

### Example 2 — Stair Game (staircase Nim)  ·  ★ ≈1700

- **Source:** [CSES 1099 · Stair Game](https://cses.fi/problemset/task/1099)
- **Difficulty:** ≈1700 (est.)
- **Problem:** Stairs $1..n$ with $p_i$ balls. A move picks a stair $k \ne 1$ with a ball and moves any positive number of its balls to stair $k-1$. The player who moves last wins. Print `first` or `second`.
- **Thinking from first principles:** Stair 1 is the sink ("step 0" of staircase Nim). Re-index: stair $i$ is step $i-1$. Odd steps are stairs $2,4,6,\dots$ — those counts XOR to the answer; balls on odd-numbered stairs are irrelevant (moves from them can be undone).

<details><summary>Solution</summary>

`first` iff $p_2 \oplus p_4 \oplus p_6 \oplus \dots \ne 0$ (§1.2; checked by brute force). $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        long long x = 0;
        for (int i = 1; i <= n; i++) { long long p; cin >> p; if (i % 2 == 0) x ^= p; }
        cout << (x ? "first" : "second") << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt();
            long x = 0;
            for (int i = 1; i <= n; i++) { long p = in.nextLong(); if (i % 2 == 0) x ^= p; }
            out.println(x != 0 ? "first" : "second");
        }
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
3
3
0 2 1
4
1 1 1 1
2
5 0
out:
first
second
second
-->
<!-- test
in:
2
1
7
5
9 3 9 5 9
out:
second
first
-->

### Example 3 — Misère Nim  ·  ★ ≈1800

- **Source:** Original problem
- **Difficulty:** ≈1800 (est.)
- **Problem:** $t$ tests; $n$ piles $a_i \le 10^{18}$; Nim moves; **whoever takes the last stone loses**. Print `First` or `Second`.
- **Thinking from first principles:** Brute force on 1–4 piles of size $<5$: the table agrees with normal Nim everywhere except where all piles are 0/1 — there it is inverted (an even number of 1-piles wins). The proof is §1.1. The dead end to avoid: "misère = complement of normal" — it is not (two piles $\{2,2\}$ are P in both).

<details><summary>Solution</summary>

If some pile $\ge 2$: `First` iff XOR $\ne 0$. Else `First` iff the number of 1-piles is even. Proof §1.1; checked against exhaustive search on 1500 random small positions. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n; cin >> n;
        long long x = 0; bool big = false; int ones = 0;
        for (int i = 0; i < n; i++) { long long a; cin >> a; x ^= a; if (a > 1) big = true; if (a == 1) ones++; }
        bool first = big ? x != 0 : ones % 2 == 0;
        cout << (first ? "First" : "Second") << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            int n = in.nextInt(), ones = 0;
            long x = 0; boolean big = false;
            for (int i = 0; i < n; i++) { long a = in.nextLong(); x ^= a; if (a > 1) big = true; if (a == 1) ones++; }
            boolean first = big ? x != 0 : ones % 2 == 0;
            out.println(first ? "First" : "Second");
        }
        out.flush();
    }

    static class FastReader {
        private final DataInputStream st;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { st = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = st.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        long nextLong() throws IOException {
            int c = read();
            while (c != -1 && c <= ' ') c = read();
            boolean neg = c == '-';
            if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        int nextInt() throws IOException { return (int) nextLong(); }
    }
}
```

</details>

<!-- test
in:
6
1
1
2
1 1
1
5
3
1 2 3
2
2 2
3
1 1 1
out:
Second
First
First
Second
Second
Second
-->
<!-- test
in:
3
2
1 1000000000000000000
4
0 0 1 0
3
1 1 2
out:
First
Second
First
-->

### Example 4 — Wythoff's game for huge piles  ·  ★ ≈2000

- **Source:** Original problem
- **Difficulty:** ≈2000 (est.)
- **Problem:** $q \le 10^5$ queries $(a,b)$, $0 \le a,b \le 10^{18}$. Moves: remove any positive amount from one pile, or the same positive amount from both. Normal play. Print `First` or `Second`.
- **Thinking from first principles:** A DP table is $10^{36}$ cells. Brute-force $300\times300$, list P-positions, notice differences $0,1,2,\dots$ and the "each integer once" property (§1.4) — that is a Beatty pair with ratio $\varphi$. The remaining trap is precision: `(long long)(k * 1.618…)` with `double` is wrong already near $k \approx 10^{16}$; even `long double` is risky at $10^{18}$. Use the exact integer form.

<details><summary>Solution</summary>

With $a\le b$, $k=b-a$: P iff $a = \lfloor (k + \operatorname{isqrt}(5k^2))/2\rfloor$. Proof §1.4; exact formula checked against the $300\times300$ brute-force table. $O(1)$ per query (`__int128` in C++, `BigInteger.sqrt` in Java).

```cpp
#include <bits/stdc++.h>
using namespace std;
typedef unsigned long long u64;
typedef unsigned __int128 u128;
u64 isqrt128(u128 x) {
    u64 r = (u64)sqrtl((long double)x);
    while ((u128)r * r > x) r--;
    while ((u128)(r + 1) * (r + 1) <= x) r++;
    return r;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> q;
    while (q--) {
        u64 a, b; cin >> a >> b;
        if (a > b) swap(a, b);
        u64 k = b - a;
        u64 ak = (u64)(((u128)k + isqrt128((u128)k * k * 5)) / 2);
        cout << (a == ak ? "Second" : "First") << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;
import java.math.BigInteger;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int q = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        BigInteger five = BigInteger.valueOf(5);
        while (q-- > 0) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            long a = Long.parseLong(st.nextToken()), b = Long.parseLong(st.nextToken());
            if (a > b) { long t = a; a = b; b = t; }
            BigInteger k = BigInteger.valueOf(b - a);
            BigInteger ak = k.add(k.multiply(k).multiply(five).sqrt()).shiftRight(1);
            sb.append(ak.longValue() == a ? "Second" : "First").append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
8
0 0
1 2
2 1
3 5
3 4
5 5
0 7
13 8
out:
Second
Second
Second
Second
First
First
First
Second
-->
<!-- test
in:
3
161803398874989484 261803398874989484
161803398874989485 261803398874989485
1000000000000000000 1000000000000000000
out:
Second
First
First
-->

### Example 5 — Yet Another Number Game (Wythoff and a three-pile surprise)  ·  ★ 2100

- **Source:** [CF 282D · Yet Another Number Game](https://codeforces.com/problemset/problem/282/D) — 2100
- **Difficulty:** 2100
- **Problem:** $n \le 3$ numbers $a_i < 300$. A move either decreases one number by some $x \ge 1$, or decreases **all** numbers by the same $x \ge 1$ (not below zero). Who cannot move loses. BitLGM moves first; print `BitLGM` or `BitAryo`.
- **Thinking from first principles:** $n=1$: win iff $a_1>0$. $n=2$: this is exactly Wythoff's game. $n=3$: a $300^3$ DP with $O(300)$ moves per state is $\approx 10^{10}$ — too slow without optimisation. Brute-force small values (all $<36$) instead: the P-positions are **exactly XOR $=0$** — the all-three move never helps. (Plausible reason: from XOR 0, subtracting the same $x$ from three numbers can never keep the XOR 0 — a parity argument on the lowest bit where the subtraction borrows; the brute force is the real evidence here.)

<details><summary>Solution</summary>

$n=1$: `BitLGM` iff $a_1 > 0$. $n=2$: `BitAryo` iff $(a,b)$ is a Wythoff P-position (exact test of §3.2; values are small, so `double` would also do). $n=3$: `BitLGM` iff $a_1\oplus a_2\oplus a_3 \ne 0$ (verified against the full DP for all values $<36$). $O(1)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int n; cin >> n;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    bool first;
    if (n == 1) first = a[0] > 0;
    else if (n == 2) {
        long long lo = min(a[0], a[1]), hi = max(a[0], a[1]), k = hi - lo;
        long long s = (long long)sqrtl((long double)(5 * k * k));
        while (s * s > 5 * k * k) s--;
        while ((s + 1) * (s + 1) <= 5 * k * k) s++;
        first = lo != (k + s) / 2;                       // P iff lo == floor(k*phi)
    } else first = (a[0] ^ a[1] ^ a[2]) != 0;
    cout << (first ? "BitLGM" : "BitAryo") << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        StringTokenizer st = new StringTokenizer(br.readLine());
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = Long.parseLong(st.nextToken());
        boolean first;
        if (n == 1) first = a[0] > 0;
        else if (n == 2) {
            long lo = Math.min(a[0], a[1]), hi = Math.max(a[0], a[1]), k = hi - lo;
            long s = (long) Math.sqrt((double) (5 * k * k));
            while (s * s > 5 * k * k) s--;
            while ((s + 1) * (s + 1) <= 5 * k * k) s++;
            first = lo != (k + s) / 2;
        } else first = (a[0] ^ a[1] ^ a[2]) != 0;
        System.out.println(first ? "BitLGM" : "BitAryo");
    }
}
```

</details>

<!-- test
in:
2
1 1
out:
BitLGM
-->
<!-- test
in:
2
1 2
out:
BitAryo
-->
<!-- test
in:
3
1 2 1
out:
BitLGM
-->
<!-- test
in:
3
1 2 3
out:
BitAryo
-->
<!-- test
in:
1
0
out:
BitAryo
-->
<!-- test
in:
2
0 0
out:
BitAryo
-->

### Example 6 — Wizards and Numbers (a Euclid game with powers)  ·  ★ 2300

- **Source:** [CF 167C · Wizards and Numbers](https://codeforces.com/problemset/problem/167/C) — 2300
- **Difficulty:** 2300
- **Problem:** Two numbers $a \le b$ (order irrelevant), $0 \le a,b \le 10^{18}$, $t \le 10^4$ tests. A move replaces $b$ by $b - a^k$ for some $k \ge 1$ with $a^k \le b$, or by $b \bmod a$. If a number is 0, the player to move loses. Print `First` or `Second`.
- **Thinking from first principles:** As in Euclid's game, the position $(a,b)$ is "stuck at the same $a$" until $b$ drops below $a$. Let $r = b \bmod a$, $q = \lfloor b/a\rfloor$. Step 1: if $(r, a)$ is a loss for the player to move there, take $b \bmod a$ and win. Step 2: otherwise $(r,a)$ is a win for whoever reaches it *as the mover*, so neither player wants to be the one who makes $q = 0$. Every power move keeps $b \equiv r \pmod a$ and reduces $q$ by $a^{k-1}$ (a power of $a$, including $1$). So we play a subtraction game on $q$ with moves $\{1, a, a^2, \dots\}$, where reaching $q=0$ hands the opponent a win. Since $a^j \equiv (-1)^j \pmod{a+1}$, this game depends only on $q \bmod (a+1)$, and tabulating shows the mover wins iff $q \bmod (a+1)$ is **even**.

<details><summary>Solution</summary>

`win(a,b)` with $a\le b$: if $a=0$ return false; if `!win(b mod a, a)` return true; else return $(\lfloor b/a\rfloor \bmod (a+1)) \bmod 2 = 0$. Recursion depth $O(\log b)$ (Euclid). Verified against an exhaustive DP of the original game for all $a,b<400$. Care: $a+1$ does not overflow for $a\le10^{18}$; in C++ use `long long`, in Java `long`.

```cpp
#include <bits/stdc++.h>
using namespace std;
bool win(long long a, long long b) {
    if (a > b) swap(a, b);
    if (a == 0) return false;
    if (!win(b % a, a)) return true;
    long long q = b / a;
    return (q % (a + 1)) % 2 == 0;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        long long a, b; cin >> a >> b;
        cout << (win(a, b) ? "First" : "Second") << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static boolean win(long a, long b) {
        if (a > b) { long t = a; a = b; b = t; }
        if (a == 0) return false;
        if (!win(b % a, a)) return true;
        long q = b / a;
        return (q % (a + 1)) % 2 == 0;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int t = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        while (t-- > 0) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            long a = Long.parseLong(st.nextToken()), b = Long.parseLong(st.nextToken());
            sb.append(win(a, b) ? "First" : "Second").append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
4
10 21
31 10
0 1
10 30
out:
First
Second
Second
First
-->
<!-- test
in:
4
1 1000000000000000000
3 10
0 0
2 1000000000000000000
out:
First
Second
Second
First
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Misère Nim's exception is "all piles $\le 1$", not "all piles equal 1".** Zero-piles count as $\le 1$; a position like $\{0,0,1\}$ is in the exceptional case.
2. **Misère is not the complement of normal play.** $\{2,2\}$ is P in both. Never flip the answer blindly.
3. **Staircase: identify the sink correctly.** In the CSES version stair 1 is the sink, so the *even* stairs count. Off-by-one here flips every answer.
4. **Wythoff with floating point fails at large values.** `double` has 53 bits; $k\varphi$ for $k \approx 10^{16}$ is already wrong. Use $\lfloor (k + \lfloor\sqrt{5k^2}\rfloor)/2\rfloor$ with `__int128` / `BigInteger`.
5. **Integer square root: always correct the estimate.** `sqrtl` can be off by one; loop down/up with 128-bit products.
6. **Euclid game: $a=b$ is a win** (take everything), even though $a/b=1<\varphi$. State the golden-ratio rule as $b<a<\varphi b$.
7. **Moore's Nim with $k \ge$ number of piles** is trivial (take everything at once): first wins iff any pile is non-empty — consistent with the rule since every column count $\le n < k+1$.
8. **Hackenbush fusion applies to Green (impartial) Hackenbush only.** Red-Blue Hackenbush is partisan and has fractional values.
9. **SJ theorem has a side condition.** Check it with a brute force on your component game before relying on it.
10. **Recursion in Java** for Euclid-type recursions is $O(\log)$ deep — safe; for Hackenbush on big graphs, use iterative DFS.

---

## 7. Going further (toward 2400–2600+)

- **Staircase Nim on trees** with step size $k$ and rerooting: [CF 1498F · Christmas Game](https://codeforces.com/problemset/problem/1498/F) — 2500 (depth $\lfloor d/k\rfloor$ parity, XOR per residue class, rerooted).
- **Hackenbush with cycles** in problems: reduce with bridges/BCC, then apply fusion; Red-Blue and Red-Green-Blue Hackenbush lead to surreal numbers (IGM lore).
- **Misère quotients** (Plambeck–Siegel) solve many misère octal games; rarely needed in CP but explain why misère is hard.
- **Nim variants with XOR-basis structure**: [CF 662A · Gambling Nim](https://codeforces.com/problemset/problem/662/A) — 2400, [CF 1451F · Nullify The Matrix](https://codeforces.com/problemset/problem/1451/F) — 2700 (anti-diagonal XORs act as staircase-like components).
- **Wythoff generalisations** (Beatty pairs, $t$-Wythoff, three-pile Wythoff is open) — the *method* (greedy mex construction + Beatty) is what transfers.

---

## 8. Practice ladder

**≤ 1900**
- [ ] [CSES 2208 · Another Game](https://cses.fi/problemset/task/2208)
- [ ] [CSES 1099 · Stair Game](https://cses.fi/problemset/task/1099)
- [ ] [AtCoder ABC297 G · Constrained Nim 2](https://atcoder.jp/contests/abc297/tasks/abc297_g)
- [ ] [CF 1190B · Tokitsukaze, CSL and Stone Game](https://codeforces.com/problemset/problem/1190/B) — 1800

**1900–2300**
- [ ] [CF 1147C · Thanos Nim](https://codeforces.com/problemset/problem/1147/C) — 2000
- [ ] [CF 282D · Yet Another Number Game](https://codeforces.com/problemset/problem/282/D) — 2100
- [ ] [AtCoder ABC172 F · Unfair Nim](https://atcoder.jp/contests/abc172/tasks/abc172_f)
- [ ] [AtCoder AGC017 D · Game on Tree](https://atcoder.jp/contests/agc017/tasks/agc017_d)
- [ ] [CF 812E · Sagheer and Apple Tree](https://codeforces.com/problemset/problem/812/E) — 2300
- [ ] [CF 167C · Wizards and Numbers](https://codeforces.com/problemset/problem/167/C) — 2300

**2400+**
- [ ] [CF 662A · Gambling Nim](https://codeforces.com/problemset/problem/662/A) — 2400
- [ ] [CF 1498F · Christmas Game](https://codeforces.com/problemset/problem/1498/F) — 2500
- [ ] [AtCoder ABC255 G · Constrained Nim](https://atcoder.jp/contests/abc255/tasks/abc255_g)
- [ ] [CF 1451F · Nullify The Matrix](https://codeforces.com/problemset/problem/1451/F) — 2700
- [ ] [CF 2043F · Nim](https://codeforces.com/problemset/problem/2043/F) — 2700

---

## 9. LeetCode / FAANG cross-reference

Rare in interviews: misère, staircase, Wythoff and Hackenbush essentially never appear in FAANG interviews, because the solutions are theorems rather than coding. The nearest interview problems are covered in [file 01 §9](01-game-fundamentals-winning-losing-states.md) and [file 04 §9](04-minimax-and-game-dp.md):

- [LC 292 · Nim Game](https://leetcode.com/problems/nim-game/) — Easy — the Bash game; a good place to mention the misère variant ($n \equiv 1 \pmod 4$ loses) as a follow-up.
- [LC 1908 · Game of Nim](https://leetcode.com/problems/game-of-nim/) — Medium 🔒 — normal Nim; asking "what if the last mover loses?" leads to §1.1.

---

## 10. Self-check

1. State the misère Nim rule and explain why "at least two piles $\ge 2$" follows from "some pile $\ge 2$ and XOR $= 0$".
2. Why are even steps irrelevant in staircase Nim?
3. In the CSES Stair Game, which stairs count, and why?
4. State Moore's Nim$_k$ rule. What does it reduce to for $k=1$?
5. Describe the Wythoff P-positions greedily and in closed form; how do you test a position with $a,b \le 10^{18}$ exactly?
6. What are the colon and fusion principles? What is the value of a triangle attached to the ground at one vertex?
7. When is a Euclid-game position $(a,b)$ with $a \ge b>0$ losing?
8. Why does Sprague–Grundy fail for Wythoff's game?

<details><summary>Answers</summary>

1. §1.1. If only one pile were $\ge 2$, its bits above bit 0 would not be cancelled by the 0/1 piles, so the XOR would be non-zero.
2. A move from an even step adds coins to an odd step; the opponent can move them on immediately, restoring the odd-step XOR. So only odd-step moves matter, and they form Nim.
3. Stairs $2,4,6,\dots$: stair 1 is the sink (step 0), so stair $i$ is step $i-1$, odd steps are even stairs.
4. Each binary column has a count divisible by $k+1$; for $k=1$: every column count even, i.e. XOR $=0$.
5. $a_k$ = mex of all earlier numbers, $b_k = a_k + k$; $a_k = \lfloor k\varphi\rfloor$, $b_k = \lfloor k\varphi^2\rfloor$. Test $a = \lfloor (k+\operatorname{isqrt}(5k^2))/2\rfloor$ with $k = b-a$ in 128-bit arithmetic.
6. Colon: a subgraph hanging at a vertex can be replaced by any subgraph of equal value. Fusion: vertices of a cycle can be merged, edges become loops (value 1 each). Triangle: 3 loops, value $1\oplus1\oplus1 = 1$.
7. Iff $b < a < \varphi b$ (in particular $a \ne b$ and $a<2b$).
8. A diagonal move changes both piles at once, so the position is not a sum of independent one-pile games.

</details>
