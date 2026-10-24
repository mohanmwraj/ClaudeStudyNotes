# Game Fundamentals — Winning and Losing States

> **Band:** 🟢 1000–1700 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [recursion and brute force](../01-Foundations/04-recursion-brute-force-and-backtracking.md), [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md), [topological sort and DAG DP](../09-Graphs/04-topological-sort-and-dag-dp.md)
> **You can say you know this when:** you can label every position of a small game W/L by backward induction in O(V+E), and for a game with $n$ up to $10^{18}$ you can brute-force the first 50 positions, guess the pattern, and *prove* it with the three-condition P-set argument — or replace the whole computation by a mirror, pairing, parity or strategy-stealing argument.

---

## 1. First principles — why this works

### 1.1 What "a game" means in competitive programming

Almost every CF game problem has the same skeleton:

- two players alternate; both play **optimally**;
- **perfect information** (both see everything) and **no chance**;
- the game is **finite**: every play ends after finitely many moves;
- under **normal play** the player who cannot move **loses**. Under **misère play** the player who cannot move **wins** (equivalently: whoever makes the last move loses).

Model it as a directed graph: vertices are *positions* (the entire state, including whose turn it is if the moves depend on it), edges are legal moves. Finiteness means the graph reachable from the start is a DAG (no position can repeat; if positions can repeat, the game may be infinite and you need the draw-aware method of [file 04](04-minimax-and-game-dp.md)).

Two classes of games behave very differently:

| | Impartial | Partisan |
|---|---|---|
| Moves available | depend only on the position | depend on who moves |
| Examples | Nim, subtraction games, "remove a leaf" | chess, "Alice removes red, Bob removes blue", Ticket Game |
| Theory | Sprague–Grundy ([file 02](02-nim-and-sprague-grundy.md)) | minimax DP ([file 04](04-minimax-and-game-dp.md)), ad hoc arguments |

For an impartial game the turn is irrelevant to the position, so a single label per position suffices. For a partisan game, put the player to move into the state.

### 1.2 P-positions and N-positions

Define two labels recursively:

- a position is **N** (the **N**ext player — the one about to move — wins) if **some** move leads to a P-position;
- a position is **P** (the **P**revious player wins) if **every** move leads to an N-position. Under normal play a terminal position is P (vacuously: no moves).

Why is this well defined? Because the game graph is a finite DAG: process positions in reverse topological order (or by induction on the length of the longest remaining play); when you reach $v$, all successors are already labelled. This is the content of **Zermelo's theorem**: in a finite two-player game of perfect information without chance or draws, exactly one player has a winning strategy.

The labels are not just bookkeeping — they *are* the strategy. From an N-position, move to a P-position. Your opponent, at a P-position, must move to an N-position. You repeat. Since the game is finite, the opponent eventually stands at a terminal P-position with no move and loses.

### 1.3 The three-condition proof template (the tool you will use most)

To prove that a set $\mathcal{P}$ of positions is *exactly* the set of P-positions, check:

1. every terminal position is in $\mathcal{P}$ (normal play);
2. **every** move from a position in $\mathcal{P}$ leads outside $\mathcal{P}$;
3. from **every** position outside $\mathcal{P}$ there is **some** move into $\mathcal{P}$.

Proof: induct over the reverse topological order. A position in $\mathcal{P}$ has only successors outside $\mathcal{P}$, which are N by induction, so it is P. A position outside $\mathcal{P}$ has a successor in $\mathcal{P}$, which is P by induction, so it is N. $\square$

Every "pattern" in this folder — $n \bmod (k+1)$, XOR $=0$, $\lfloor k\varphi \rfloor$ — is proved with these three lines. When you guess a pattern from a brute-force table, write these three conditions down; if one fails you learn exactly where the guess is wrong.

*Example (Bash game).* One pile of $n$ stones, remove $1..k$ per move, normal play. Claim $\mathcal{P}=\{n : n \equiv 0 \pmod{k+1}\}$. (1) $0\in\mathcal{P}$. (2) From a multiple of $k+1$, removing $x\in[1,k]$ gives a non-multiple. (3) From $n$ with $r = n \bmod (k+1) \ne 0$, remove $r \le k$. $\square$

### 1.4 The naive approach and why it is slow

Searching the game tree without memory is exponential: the same position is reached by many move orders. Memoising on the position turns it into DP on the DAG of positions: **O(V + E)**, i.e. (number of positions) × (moves per position). That is the whole algorithm when $V$ is small (say $\le 10^7$).

When $V$ is astronomically large ($n \le 10^{18}$, or a board of $10^5$ cells), you cannot visit the positions. Then you either

- find a **pattern** (compute small cases with the DP, guess, prove with §1.3), or
- find a **structural strategy** that avoids labelling positions at all (§1.5), or
- decompose the game into independent parts and use Sprague–Grundy ([file 02](02-nim-and-sprague-grundy.md)).

### 1.5 Structural strategies that need no table

**Mirror (symmetry) strategy.** Find an involution $\sigma$ on positions such that (a) the *current* position is symmetric (or you can make it symmetric with your first move), (b) whenever the opponent plays a move $m$ from a symmetric position, the mirrored move $\sigma(m)$ is legal afterwards and restores symmetry. Then the player who maintains symmetry always has a reply, so (by finiteness) the opponent runs out of moves first. The danger is (b): $m$ and $\sigma(m)$ must not interfere (e.g. a move on the axis of symmetry has no distinct mirror — that's why the first player of the plate game takes the centre). Examples: placing plates on a table (first player takes the centre, then point-reflects), two equal Nim piles (second player copies), $n\ge 3$ coins in a circle, remove 1 or 2 adjacent (second player splits the remaining line into two equal halves and mirrors).

**Pairing strategy.** Partition the "resources" into pairs such that whenever the opponent uses one element of a pair, you use its partner, and this keeps your target invariant. Ticket Game (Example 4) is the archetype: every left '?' is paired with a right '?' and Bicarp copies the digit. Maker–breaker tic-tac-toe variants are pairing strategies too.

**Strategy stealing.** Proves the first player wins *without telling you how*. Chomp: an $a\times b$ chocolate bar whose bottom-left square is poisoned; a move picks a square and eats it together with everything above and to the right of it; whoever eats the poison loses. Suppose the *second* player had a winning strategy. Let the first player eat only the top-right square. The second player now has a winning reply $r$. But every move eats the top-right square too, so the position after $r$ is also reachable in **one** move from the start: the first player could have played $r$ immediately and then followed the second player's strategy. Contradiction — unless the board is $1\times 1$, where the only move is to eat the poison. Ingredients: no draws, and a "harmless extra move" that is absorbed by every other move. (Hex is the other classic.) In CF this usually appears as "the answer is always First" — and the expected solution prints it.

**Parity / fixed move count.** If every play of the game lasts **exactly $M$ moves** no matter what the players do, the first player wins iff $M$ is odd. Look for a quantity that changes by exactly one per move and a fixed terminal value of it (each move removes one stone / one leaf / one inversion; the final set is forced). Game on Leaves (Example 5) and [CF 346A · Alice and Bob](https://codeforces.com/problemset/problem/346/A) are of this type.

**Reduction to a known game.** "Sequential Nim", "staircase", "two piles where you can take equal amounts from both" are Nim, staircase Nim and Wythoff in disguise — see [file 02](02-nim-and-sprague-grundy.md) and [file 03](03-game-variants-misere-staircase-hackenbush.md).

### 1.6 Finding the pattern by brute force — the real contest skill

Strong solvers do not stare at a game with $n \le 10^{18}$. They spend five minutes on a brute force:

1. encode the state canonically (sort piles; use the multiset, not the order, if order is irrelevant);
2. memoised recursion `win(state) = any(!win(next))`;
3. print the W/L table for all small parameters (and the Grundy value, file 02, if components are independent);
4. look for: periodicity in $n$, dependence on $n \bmod m$, powers of two, parity of the number of something, "only these few positions lose", Fibonacci / golden-ratio growth;
5. prove the guess with §1.3, or at least check it against the brute force on far more cases than you looked at.

Section 3.2 gives a ready-to-adapt brute force (Chomp) in both languages. The same five steps solve Example 2.

---

## 2. Formulas, definitions and identities

| Statement | Meaning / proof sketch |
|---|---|
| $\mathrm{win}(v) = \exists\, u \in \mathrm{moves}(v): \lnot\,\mathrm{win}(u)$ | backward induction; terminal $\Rightarrow$ lose (normal play), win (misère) |
| Cost of labelling: $O(V+E)$ | each position and move examined once (memo or reverse topological order) |
| Bash game, take $1..k$: P $\iff n \equiv 0 \pmod{k+1}$ | §1.3 |
| Misère Bash (taker of the last stone loses): P $\iff n \equiv 1 \pmod{k+1}$ | terminal $0$ is now W; same template with residue 1 |
| Subtraction set $S$, $s=\max S$: W/L sequence is eventually periodic with period $\le 2^{s}$ | $\mathrm{win}(n)$ depends only on the window $\mathrm{win}(n-s..n-1)$: a finite automaton with $2^s$ states must cycle |
| Divisor game ([LC 1025](https://leetcode.com/problems/divisor-game/)): $n \to n-d$, $d\mid n$, $d<n$; P $\iff n$ odd | odd $n$ has only odd divisors $\Rightarrow n-d$ even; even $n$ subtracts $1$ |
| Deleting Divisors ($d \mid n$, $1<d<n$): P $\iff n$ odd or $n=2^k$ with $k$ odd | Example 2 |
| Chomp $a \times b$: first player wins $\iff (a,b) \ne (1,1)$ | strategy stealing (§1.5) |
| Circle of $n$ coins, remove 1 or 2 adjacent: first wins $\iff n \le 2$ | second player splits the remaining line symmetrically |
| Fixed-length play: exactly $M$ moves in every play $\Rightarrow$ first wins $\iff M$ odd | trivial, but finding the invariant is the problem |
| Mirror: symmetric position + non-interfering mirrored replies $\Rightarrow$ player to move loses | the symmetric-keeping player always has a reply |

Brute-force verified (scratch work): Bash and misère Bash for $k\le 7$, $n<80$; divisor game $n<500$; Deleting Divisors $n<5000$; Chomp up to $5 \times 6$; circle game $n<40$.

---

## 3. Implementation (C++ and Java)

### 3.1 Win/lose labels on an explicit DAG

Input: $n$ positions, $m$ moves $u \to v$ (the graph is a DAG). Output: a string whose $v$-th character is `W` if the player to move from $v$ wins, else `L`. Iterative (Kahn) so it never overflows the stack.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<vector<int>> adj(n + 1);
    vector<int> indeg(n + 1, 0);
    for (int i = 0; i < m; i++) { int u, v; cin >> u >> v; adj[u].push_back(v); indeg[v]++; }
    vector<int> order;
    for (int v = 1; v <= n; v++) if (indeg[v] == 0) order.push_back(v);
    for (size_t i = 0; i < order.size(); i++)
        for (int u : adj[order[i]]) if (--indeg[u] == 0) order.push_back(u);
    vector<char> win(n + 1, 0);
    for (int i = n - 1; i >= 0; i--) {              // reverse topological order: successors already final
        int v = order[i];
        for (int u : adj[v]) if (!win[u]) { win[v] = 1; break; }
    }
    string s;
    for (int v = 1; v <= n; v++) s += win[v] ? 'W' : 'L';
    cout << s << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), m = in.nextInt();
        int[] head = new int[n + 1], nxt = new int[m], to = new int[m], indeg = new int[n + 1];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            int u = in.nextInt(), v = in.nextInt();
            to[i] = v; nxt[i] = head[u]; head[u] = i; indeg[v]++;
        }
        int[] order = new int[n]; int sz = 0;
        for (int v = 1; v <= n; v++) if (indeg[v] == 0) order[sz++] = v;
        for (int i = 0; i < sz; i++)
            for (int e = head[order[i]]; e != -1; e = nxt[e]) if (--indeg[to[e]] == 0) order[sz++] = to[e];
        boolean[] win = new boolean[n + 1];
        for (int i = n - 1; i >= 0; i--) {
            int v = order[i];
            for (int e = head[v]; e != -1; e = nxt[e]) if (!win[to[e]]) { win[v] = true; break; }
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append(win[v] ? 'W' : 'L');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(sb);
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

<!-- test
in:
5 5
1 2
2 3
3 4
4 5
1 3
out:
WWLWL
-->
<!-- test
in:
1 0
out:
L
-->
<!-- test
in:
4 3
1 4
2 4
3 1
out:
WWLL
-->

### 3.2 Brute-force pattern finder (Chomp)

Input `R C`; output an $R \times C$ table whose entry $(a,b)$ is `W` if the first player wins Chomp on an $a\times b$ board. The state is the vector of column heights (non-increasing), packed 4 bits per column — the same skeleton (canonical state + memo + "any move to a losing state") is what you adapt in contest.

```cpp
#include <bits/stdc++.h>
using namespace std;
int C;
unordered_map<unsigned long long, bool> memo;
// state: height of each column, 4 bits per column; poison = cell (column 0, row 0)
bool win(unsigned long long s) {
    auto it = memo.find(s);
    if (it != memo.end()) return it->second;
    int h[16];
    for (int c = 0; c < C; c++) h[c] = (s >> (4 * c)) & 15;
    bool res = false;
    for (int c = 0; c < C && !res; c++)
        for (int r = 0; r < h[c] && !res; r++) {
            if (c == 0 && r == 0) continue;                 // eating the poison is never a winning move
            unsigned long long t = 0;
            for (int d = 0; d < C; d++) t |= (unsigned long long)(d >= c ? min(h[d], r) : h[d]) << (4 * d);
            if (!win(t)) res = true;
        }
    return memo[s] = res;
}
int main() {
    int R; cin >> R >> C;                                    // R <= 15, C <= 16
    for (int a = 1; a <= R; a++) {
        string line;
        for (int b = 1; b <= C; b++) {
            unsigned long long s = 0;
            for (int c = 0; c < b; c++) s |= (unsigned long long)a << (4 * c);
            line += win(s) ? 'W' : 'L';
        }
        cout << line << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int C;
    static HashMap<Long, Boolean> memo = new HashMap<>();

    static boolean win(long s) {
        Boolean got = memo.get(s);
        if (got != null) return got;
        int[] h = new int[C];
        for (int c = 0; c < C; c++) h[c] = (int) ((s >> (4 * c)) & 15);
        boolean res = false;
        for (int c = 0; c < C && !res; c++)
            for (int r = 0; r < h[c] && !res; r++) {
                if (c == 0 && r == 0) continue;
                long t = 0;
                for (int d = 0; d < C; d++) t |= (long) (d >= c ? Math.min(h[d], r) : h[d]) << (4 * d);
                if (!win(t)) res = true;
            }
        memo.put(s, res);
        return res;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int R = Integer.parseInt(st.nextToken()); C = Integer.parseInt(st.nextToken());
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        for (int a = 1; a <= R; a++) {
            StringBuilder line = new StringBuilder();
            for (int b = 1; b <= C; b++) {
                long s = 0;
                for (int c = 0; c < b; c++) s |= (long) a << (4 * c);
                line.append(win(s) ? 'W' : 'L');
            }
            out.println(line);
        }
        out.flush();
    }
}
```

<!-- test
in:
3 4
out:
LWWW
WWWW
WWWW
-->
<!-- test
in:
1 1
out:
L
-->

The table confirms the strategy-stealing theorem; the brute force also tells you *which* move wins (record the `t` that makes `res` true), which the theorem never does — for general $a\times b$ no simple winning rule is known.

---

## 4. Recognising the pattern

| Signal in the statement | Think |
|---|---|
| "both play optimally, who wins", small state space ($\le 10^7$ positions) | backward induction / memo DP (§3.1) |
| single number $n \le 10^{18}$, a fixed rule for moves | brute force small $n$, find period or closed form (§1.6) |
| "subtract any element of a fixed set" | subtraction game: periodic; compute with DP up to $n$ or find the period |
| board / arrangement that is symmetric, or can be made symmetric by one move | mirror strategy |
| two "halves" that must balance (sums, counts) and a player wanting balance | pairing strategy |
| every move removes exactly one object and the end state is forced | parity of the number of moves |
| first player has a "harmless" move and draws are impossible | strategy stealing $\Rightarrow$ First |
| several independent piles/boards, a move touches only one | Sprague–Grundy ([file 02](02-nim-and-sprague-grundy.md)) |
| players have different move sets or collect scores | partisan / minimax ([file 04](04-minimax-and-game-dp.md)) |
| positions can repeat | draws possible — retrograde BFS ([file 04](04-minimax-and-game-dp.md)) |

Common confusion: a game where you **collect points** is not a win/lose game; labels W/L are insufficient — you need the optimal value (minimax). A game where one player wants to win and the other wants to **delay** is also minimax (value = game length).

---

## 5. Worked examples (graded)

### Example 1 — Stick Game  ·  ★ ≈1400

- **Source:** [CSES 1729 · Stick Game](https://cses.fi/problemset/task/1729)
- **Difficulty:** ≈1400 (est.)
- **Problem:** A heap has $n$ sticks; a move removes exactly $p$ sticks for some $p$ in a given set $P$ of $k$ values. The player who cannot move loses. For every heap size $1..n$ output `W` if the first player wins, else `L`. $n \le 10^6$, $k \le 100$.
- **Thinking from first principles:** The position is just the heap size. Size 0 has no move, so it is L. Size $i$ is W iff some $p \le i$ leads to an L size. Sizes only decrease, so computing in increasing order is a valid topological order. $O(nk) = 10^8$ simple operations — fine in C++ and Java with an early `break`.

<details><summary>Solution</summary>

`win[0] = false`; for $i = 1..n$: `win[i] = OR over p in P with p ≤ i of !win[i-p]`. Correctness is §1.2 applied to a DAG whose topological order is $0,1,2,\dots$. Time $O(nk)$, memory $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k; cin >> n >> k;
    vector<int> p(k);
    for (auto& x : p) cin >> x;
    vector<char> win(n + 1, 0);
    for (int i = 1; i <= n; i++)
        for (int x : p) if (x <= i && !win[i - x]) { win[i] = 1; break; }
    string s(n, 'L');
    for (int i = 1; i <= n; i++) if (win[i]) s[i - 1] = 'W';
    cout << s << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt(), k = in.nextInt();
        int[] p = new int[k];
        for (int i = 0; i < k; i++) p[i] = in.nextInt();
        boolean[] win = new boolean[n + 1];
        for (int i = 1; i <= n; i++)
            for (int x : p) if (x <= i && !win[i - x]) { win[i] = true; break; }
        StringBuilder sb = new StringBuilder(n);
        for (int i = 1; i <= n; i++) sb.append(win[i] ? 'W' : 'L');
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        out.println(sb);
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
10 3
1 3 4
out:
WLWWWWLWLW
-->
<!-- test
in:
1 1
1
out:
W
-->
<!-- test
in:
5 1
2
out:
LWWLL
-->

### Example 2 — Deleting Divisors  ·  ★ 1700

- **Source:** [CF 1537D · Deleting Divisors](https://codeforces.com/problemset/problem/1537/D) — 1700
- **Difficulty:** 1700
- **Problem:** Start with $n$. A move replaces $n$ by $n-d$ where $d$ is a divisor of $n$ with $1<d<n$. The player who cannot move loses; Alice moves first. Answer $t \le 10^4$ queries, $n \le 10^9$.
- **Thinking from first principles:** $10^9$ positions is too many, so brute-force $n \le 100$ and look: L at 1, 2, 3, 5, 7, 8, 9, 11, … The odd numbers are all L. Among evens, 2 and 8 and 32 are L, while 4, 16, 6, 10, 12 are W. So the guess is: **L iff $n$ is odd or $n=2^k$ with $k$ odd.** Now prove it with the template (§1.3).

<details><summary>Solution</summary>

Let $\mathcal{P}$ = odd numbers $\cup \{2^k : k \text{ odd}\}$.

- *Odd $n$ only reaches even non-powers of two.* Every divisor $d$ of an odd $n$ is odd, so $n-d$ is even, and $d \mid n-d$ with $d>1$ odd, so $n-d$ has an odd factor $>1$: not a power of two.
- *An even non-power of two reaches an odd number.* It has an odd divisor $d>1$, $d<n$; $n-d$ is odd.
- *Powers of two.* From $2^k$ the divisors are $2^j$, $1\le j<k$. Subtracting $2^j$ with $j<k-1$ gives $2^j(2^{k-j}-1)$: an even non-power of two (outside $\mathcal{P}$). Subtracting $2^{k-1}$ gives $2^{k-1}$. So $2^k$ is in $\mathcal{P}$ iff $2^{k-1}$ is not, and $2^1=2$ has no move (P). Hence $2^k \in \mathcal{P}$ iff $k$ odd.

All three conditions hold (terminal positions — 1 and the odd primes and 2 — are in $\mathcal{P}$), so $\mathcal{P}$ is exactly the losing set. Alice wins iff $n \notin \mathcal{P}$. $O(1)$ per query.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        long long n; cin >> n;
        bool alice;
        if (n % 2 == 1) alice = false;
        else if (n & (n - 1)) alice = true;                       // even, not a power of two
        else alice = (__builtin_ctzll(n) % 2 == 0);               // n = 2^k: Alice wins iff k even
        cout << (alice ? "Alice" : "Bob") << "\n";
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
            long n = in.nextLong();
            boolean alice;
            if (n % 2 == 1) alice = false;
            else if ((n & (n - 1)) != 0) alice = true;
            else alice = Long.numberOfTrailingZeros(n) % 2 == 0;
            out.println(alice ? "Alice" : "Bob");
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
4
1
4
12
69
out:
Bob
Alice
Alice
Bob
-->
<!-- test
in:
7
2
8
16
1000000000
536870912
268435456
999999999
out:
Bob
Bob
Alice
Alice
Bob
Alice
Bob
-->

### Example 3 — Plate Game (mirror strategy)  ·  ★ 1600

- **Source:** [CF 197A · Plate Game](https://codeforces.com/problemset/problem/197/A) — 1600
- **Difficulty:** 1600
- **Problem:** A rectangular table $a \times b$; players alternately place round plates of radius $r$ that must lie entirely on the table and must not overlap previously placed plates (touching is fine). Whoever cannot place a plate loses. Who wins? $1 \le a,b,r \le 100$.
- **Thinking from first principles:** The state space is continuous — no DP. Dead end: trying to count how many plates fit (the count depends on play). Look for a symmetry instead: the table is centrally symmetric. If the first player can put a plate exactly at the centre, the position becomes symmetric, and from then on every legal placement at $p$ has a legal mirror placement at $-p$ (the mirrored disc does not overlap anything, because the position before the opponent's move was symmetric, and it does not overlap the opponent's new disc, because two mirror discs overlap only if each contains the centre — impossible, the centre is covered by the first plate).

<details><summary>Solution</summary>

If $2r \le a$ and $2r \le b$, the first player places a plate at the centre and then answers every placement at point $p$ (relative to the centre) by a placement at $-p$; by the argument above this is always legal, so the second player runs out of moves first. Otherwise not even one plate fits and the first player loses immediately. $O(1)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int a, b, r;
    cin >> a >> b >> r;
    cout << (2 * r <= a && 2 * r <= b ? "First" : "Second") << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int a = Integer.parseInt(st.nextToken()), b = Integer.parseInt(st.nextToken()), r = Integer.parseInt(st.nextToken());
        System.out.println(2 * r <= a && 2 * r <= b ? "First" : "Second");
    }
}
```

</details>

<!-- test
in:
5 5 2
out:
First
-->
<!-- test
in:
6 7 4
out:
Second
-->
<!-- test
in:
4 4 2
out:
First
-->
<!-- test
in:
1 100 1
out:
Second
-->

### Example 4 — Ticket Game (pairing strategy)  ·  ★ 1700

- **Source:** [CF 1215D · Ticket Game](https://codeforces.com/problemset/problem/1215/D) — 1700
- **Difficulty:** 1700
- **Problem:** A ticket of even length $n$ has digits and an even number of `?`. Monocarp and Bicarp alternately (Monocarp first) replace one `?` with a digit 0–9. When none remain, Bicarp wins iff the sum of the first half equals the sum of the second half; otherwise Monocarp. $n \le 2\cdot 10^5$.
- **Thinking from first principles:** A partisan game (different goals). Brute force on small cases: the only things that matter are $D = s_L - s_R$ (known-digit sums) and $q_L, q_R$ (numbers of `?` per half). Running a minimax over $(q_L,q_R,D)$ (scratch work) shows Bicarp wins exactly when $2D = 9(q_R-q_L)$. Why 9 and the factor 2? Think pairing: Bicarp can neutralise a `?` pair across halves by copying the digit (net 0), and a pair within the same half by completing the sum to 9 (Monocarp writes $x$, Bicarp writes $9-x$). So Bicarp can force exactly "each excess pair on the right contributes 9".

<details><summary>Solution</summary>

Compare the halves via $D = s_L - s_R$ and the surplus $e = q_R - q_L$; $e$ is even because $q_L + q_R$ is even.

*Bicarp wins if $2D = 9e$.* Pair every left `?` with a right `?` while both sides have some, and pair the remaining $|e|$ `?` (all on one side) among themselves. Whenever Monocarp fills one element of a pair, Bicarp fills its partner: a cross pair gets the same digit (contributes $0$ to the difference), a same-side pair gets digits summing to 9. Final difference $= D - 9\cdot e/2 = 0$.

*Monocarp wins otherwise.* If $2D > 9e$, Monocarp always writes 9 into a left `?` if one exists, else 0 into a right `?` (mirror image if $2D < 9e$): every one of his moves pushes the difference away from 0 by the maximum possible, and Bicarp's moves cannot cancel the initial imbalance in addition to Monocarp's pushes. Both directions — the pairing strategy and this push strategy against an optimal Bicarp — were confirmed exhaustively for $q_L,q_R \le 7$, $|D| \le 40$ in scratch work.

$O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; string s;
    cin >> n >> s;
    long long sl = 0, sr = 0, ql = 0, qr = 0;
    for (int i = 0; i < n; i++) {
        bool left = i < n / 2;
        if (s[i] == '?') (left ? ql : qr)++;
        else (left ? sl : sr) += s[i] - '0';
    }
    cout << (2 * (sl - sr) == 9 * (qr - ql) ? "Bicarp" : "Monocarp") << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int n = Integer.parseInt(br.readLine().trim());
        String s = br.readLine().trim();
        long sl = 0, sr = 0, ql = 0, qr = 0;
        for (int i = 0; i < n; i++) {
            boolean left = i < n / 2;
            char c = s.charAt(i);
            if (c == '?') { if (left) ql++; else qr++; }
            else { if (left) sl += c - '0'; else sr += c - '0'; }
        }
        System.out.println(2 * (sl - sr) == 9 * (qr - ql) ? "Bicarp" : "Monocarp");
    }
}
```

</details>

<!-- test
in:
4
0523
out:
Bicarp
-->
<!-- test
in:
2
??
out:
Bicarp
-->
<!-- test
in:
8
?054??0?
out:
Bicarp
-->
<!-- test
in:
6
???00?
out:
Monocarp
-->

### Example 5 — Game On Leaves (parity of a forced move count)  ·  ★ 1600

- **Source:** [CF 1363C · Game On Leaves](https://codeforces.com/problemset/problem/1363/C) — 1600
- **Difficulty:** 1600
- **Problem:** A tree with $n$ nodes and a special node $x$. Players alternately remove a leaf (a node of degree $\le 1$) with its edge; whoever removes $x$ wins. Ayush moves first. $t \le 10$ tests, $n \le 1000$.
- **Thinking from first principles:** If $x$ is already a leaf (degree $\le 1$), Ayush takes it. Otherwise nobody wants to be the one who makes $x$ a leaf, because the opponent then takes it. When is $x$ forced to become a leaf? Only when *everything else* is gone except $x$ and one neighbour: a tree with $\ge 3$ nodes where $x$ has degree $\ge 2$ always has a leaf other than $x$ — in fact at least two leaves, neither being $x$. So the game always proceeds until exactly 2 nodes remain; then the player to move removes $x$'s last neighbour or $x$ — either way $x$ is a leaf and that player takes it. The number of removals before that point is $n-2$, fixed regardless of play. **Parity decides.**

<details><summary>Solution</summary>

If $\deg(x) \le 1$: Ayush. Otherwise the player to move when 2 nodes remain wins; that is after $n-2$ moves, i.e. Ayush iff $n-2$ is even iff $n$ is even. (Verified against an exhaustive search over all leaf-removal orders for random trees with $n \le 10$.) $O(n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n, x; cin >> n >> x;
        int deg = 0;
        for (int i = 0; i < n - 1; i++) { int u, v; cin >> u >> v; if (u == x || v == x) deg++; }
        bool ayush = deg <= 1 || n % 2 == 0;
        cout << (ayush ? "Ayush" : "Ashish") << "\n";
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
            int n = in.nextInt(), x = in.nextInt(), deg = 0;
            for (int i = 0; i < n - 1; i++) { int u = in.nextInt(), v = in.nextInt(); if (u == x || v == x) deg++; }
            out.println(deg <= 1 || n % 2 == 0 ? "Ayush" : "Ashish");
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
2
3 1
2 1
3 1
3 2
1 2
1 3
out:
Ashish
Ayush
-->
<!-- test
in:
3
1 1
4 1
1 2
1 3
1 4
5 3
1 2
2 3
3 4
4 5
out:
Ayush
Ayush
Ashish
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Put the turn into the state for partisan games.** For impartial games one label per position suffices; for "Alice may only…" games, `win[pos][player]`. Forgetting this gives answers that are right only for the first player.
2. **Terminal convention decides everything.** Normal play: terminal = L. Misère: terminal = W. Some statements say "the player who takes the last stone wins" (normal) or "…loses" (misère); some say "whoever makes $x$ disappear wins" (neither — the target event is the terminal). Re-read the ending condition twice.
3. **Brute force first, think second.** Five minutes of brute force beats thirty minutes of guessing; print tables in two parameters, not one — the pattern often depends on a second parameter (as in [CF 1194D · 1-2-K Game](https://codeforces.com/problemset/problem/1194/D), where it changes when $3 \mid k$).
4. **Verify the guess beyond what you looked at.** Patterns with an exception at a large value (e.g. Kayles is periodic only from $n = 71$ on, file 02) are common. Compare formula vs brute force for all $n$ up to the brute-force limit, not just the first 20.
5. **Mirror strategies need non-interference.** Check that the opponent's move and your mirrored reply cannot conflict (same cell, overlapping plates, moves on the symmetry axis). The usual fix is to occupy the axis/centre first.
6. **"Every play has the same length" is a strong lemma — prove it.** The Game-on-Leaves argument needs "a tree with $\ge 3$ nodes and $\deg(x)\ge 2$ has a non-$x$ leaf"; without that lemma, the parity argument is unjustified.
7. **Strategy stealing is non-constructive.** It answers "who wins", never "with which move". If the problem asks for the first move, you still need search.
8. **Recursion depth.** Memoised recursion over $10^6$ positions overflows the default stack (especially in Java and on Windows). Use an explicit topological order (§3.1), iterate in increasing $n$, or in Java run inside `new Thread(null, task, "", 1 << 28)`.
9. **Memo keys.** Canonicalise (sort piles, normalise rotations) before hashing; in Java avoid `HashMap<List<Integer>,…>` in hot loops — pack the state into a `long`.
10. **Multi-test reset.** Clear memo tables between test cases only if the game definition changes between tests; if it doesn't, keep them — recomputation is a common TLE.

---

## 7. Going further (toward 2400–2600+)

- **Sums of games**: when the position splits into independent parts, labels W/L are not enough (W + W can be L). You need Grundy values — [file 02](02-nim-and-sprague-grundy.md).
- **Misère and other endings**: [file 03](03-game-variants-misere-staircase-hackenbush.md) — misère Nim, staircase Nim, Wythoff, Hackenbush.
- **Games with scores, draws or cycles**: [file 04](04-minimax-and-game-dp.md) — minimax DP, retrograde analysis.
- **Strategy stealing in harder clothing**: "prove First always wins and output any winning first move" problems combine stealing with search; **pairing strategies** appear in Div1 constructive games (Maker–Breaker, Erdős–Selfridge potential arguments: the breaker wins if $\sum_{\text{winning sets } A} 2^{-|A|} < \tfrac12$).
- **Interactive "choose First or Second"** problems: the whole of this file becomes the decision, then you must *play* — see [interactive problems](../03-Greedy-Constructive-Interactive/05-interactive-problems.md) and [file 04 §5](04-minimax-and-game-dp.md).
- Combinatorial game theory for partisan games (surreal numbers, temperature) is IGM-and-beyond; it shows up in maybe one problem a year.

---

## 8. Practice ladder

**≤ 1400**
- [ ] [CF 1899A · Game with Integers](https://codeforces.com/problemset/problem/1899/A) — 800
- [ ] [CF 959A · Mahmoud and Ehab and the even-odd game](https://codeforces.com/problemset/problem/959/A) — 800
- [ ] [CF 1373B · 01 Game](https://codeforces.com/problemset/problem/1373/B) — 900
- [ ] [CF 1419A · Digit Game](https://codeforces.com/problemset/problem/1419/A) — 900
- [ ] [CF 1695B · Circle Game](https://codeforces.com/problemset/problem/1695/B) — 1000
- [ ] [CF 1365A · Matrix Game](https://codeforces.com/problemset/problem/1365/A) — 1100
- [ ] [CF 1527B1 · Palindrome Game (easy version)](https://codeforces.com/problemset/problem/1527/B1) — 1200
- [ ] [CF 276B · Little Girl and Game](https://codeforces.com/problemset/problem/276/B) — 1300
- [ ] [CF 1370C · Number Game](https://codeforces.com/problemset/problem/1370/C) — 1400
- [ ] [CSES 1729 · Stick Game](https://cses.fi/problemset/task/1729)

**1400–1900**
- [ ] [CF 197A · Plate Game](https://codeforces.com/problemset/problem/197/A) — 1600
- [ ] [CF 1363C · Game On Leaves](https://codeforces.com/problemset/problem/1363/C) — 1600
- [ ] [CF 346A · Alice and Bob](https://codeforces.com/problemset/problem/346/A) — 1600
- [ ] [CF 1537D · Deleting Divisors](https://codeforces.com/problemset/problem/1537/D) — 1700
- [ ] [CF 1215D · Ticket Game](https://codeforces.com/problemset/problem/1215/D) — 1700
- [ ] [CF 493D · Vasya and Chess](https://codeforces.com/problemset/problem/493/D) — 1700
- [ ] [CF 1451D · Circle Game](https://codeforces.com/problemset/problem/1451/D) — 1700
- [ ] [CF 1396B · Stoned Game](https://codeforces.com/problemset/problem/1396/B) — 1800
- [ ] [CF 1190B · Tokitsukaze, CSL and Stone Game](https://codeforces.com/problemset/problem/1190/B) — 1800
- [ ] [CF 1527B2 · Palindrome Game (hard version)](https://codeforces.com/problemset/problem/1527/B2) — 1900

**1900+**
- [ ] [CF 55C · Pie or die](https://codeforces.com/problemset/problem/55/C) — 1900
- [ ] [CF 78C · Beaver Game](https://codeforces.com/problemset/problem/78/C) — 2000
- [ ] [CF 549C · The Game Of Parity](https://codeforces.com/problemset/problem/549/C) — 2200

---

## 9. LeetCode / FAANG cross-reference

- [LC 292 · Nim Game](https://leetcode.com/problems/nim-game/) — Easy — Bash game with $k=3$: lose iff $n \equiv 0 \pmod 4$.
- [LC 1025 · Divisor Game](https://leetcode.com/problems/divisor-game/) — Easy — brute force the table, see "even wins", prove with the template.
- [LC 877 · Stone Game](https://leetcode.com/problems/stone-game/) — Medium — even number of piles: the first player can take all even-indexed or all odd-indexed piles (a pairing/colouring argument), so the answer is always true.
- [LC 1927 · Sum Game](https://leetcode.com/problems/sum-game/) — Medium — exactly the Ticket Game pairing argument.
- [LC 2038 · Remove Colored Pieces if Both Neighbors are the Same Color](https://leetcode.com/problems/remove-colored-pieces-if-both-neighbors-are-the-same-color/) — Medium — each player's number of available moves is fixed regardless of play; compare counts.
- [LC 1145 · Binary Tree Coloring Game](https://leetcode.com/problems/binary-tree-coloring-game/) — Medium — the second player's best move is adjacent to the first; counting argument on the three components.
- [LC 810 · Chalkboard XOR Game](https://leetcode.com/problems/chalkboard-xor-game/) — Hard — parity argument: with an even count the first player always has a safe move.
- [LC 294 · Flip Game II](https://leetcode.com/problems/flip-game-ii/) — Medium 🔒 — memoised brute force; Grundy values (file 02) make it polynomial.

Interviews ask these mainly to see whether you can write a memoised "can the current player force a win" recursion and then simplify it; say the P/N definition out loud.

---

## 10. Self-check

1. State the recursive definition of P- and N-positions and explain why it is well defined only for finite games.
2. Write the three conditions that prove a set is exactly the set of P-positions.
3. Prove the Bash game rule and its misère version.
4. Why does the Chomp strategy-stealing argument fail to give a winning move? Which property of Chomp makes the stealing possible?
5. In the plate game, why must the first plate go exactly at the centre?
6. Give a game where every play has the same length, and one where it does not but parity still decides.
7. Why is a W/L table not enough when the position is a sum of two independent games?
8. You brute-forced a pattern up to $n=30$. What do you do before submitting?

<details><summary>Answers</summary>

1. N if some move reaches P; P if all moves reach N (terminal is P in normal play). It needs induction from the terminal positions, which exists only if every play is finite (the position graph is a DAG).
2. Terminals are in $\mathcal{P}$; no move stays inside $\mathcal{P}$; from outside there is always a move into $\mathcal{P}$.
3. §1.3: multiples of $k+1$; misère: residue 1 (0 is now a win for the player to move).
4. It is a proof by contradiction: it shows a winning move exists among "eat the corner" or "the second player's reply", without identifying it. The property used: eating the top-right square is subsumed by every other move.
5. A plate covering the centre removes the only point whose mirror image is itself; afterwards a placement and its mirror cannot overlap each other.
6. Game on Leaves (always $n-2$ moves before $x$ becomes takeable); CF 346A (the final set is forced). Example where length varies: Nim — parity alone does not decide.
7. Two N-games can sum to a P-game (two equal Nim piles) or to an N-game; the label does not determine the sum. Grundy values do.
8. Compare the formula against the brute force for every case the brute force can reach (hundreds or thousands), and try to prove it with the three-condition template.

</details>
