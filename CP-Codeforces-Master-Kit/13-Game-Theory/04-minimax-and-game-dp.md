# Minimax and Game DP — Scores, Series of Games, Draws, Interaction

> **Band:** 🔵 1500–2200 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [game fundamentals](01-game-fundamentals-winning-losing-states.md), [interval DP](../06-Dynamic-Programming/05-interval-dp.md), [bitmask DP](../06-Dynamic-Programming/06-bitmask-dp.md), [BFS/DFS](../09-Graphs/01-graph-representation-bfs-dfs.md)
> **You can say you know this when:** you can write the negamax recurrence for any zero-sum score game (interval, subset, tree states) and prove it, handle a *series* of games with the can-win/can-lose pair, label a cyclic game graph Win/Lose/Draw with retrograde BFS in O(V+E), and turn a theoretical strategy into a correct interactive "choose First or Second" program.

---

## 1. First principles — why this works

### 1.1 From win/lose to values

Files 01–03 answer "who wins". Many problems instead ask for the **outcome value**: final score difference, a player's total, lexicographic comparison of two strings, number of moves until the end. The principle is the same backward induction, with a number instead of a bit:

- A **zero-sum** game: what one player gains the other loses (score difference, or a fixed total split between them).
- The value of a position for the player to move, $V(s)$, satisfies the **negamax** recurrence
$$V(s) = \max_{m \in \text{moves}(s)} \big(\mathrm{gain}(m) - V(s_m)\big), \qquad V(\text{terminal}) = 0,$$
because after the move the opponent becomes "the player to move" and obtains $V(s_m)$ *relative to us*.
- Equivalent two-function form (**minimax**): $\mathrm{Max}(s) = \max_m(\mathrm{gain}+\mathrm{Min}(s_m))$, $\mathrm{Min}(s) = \min_m(-\mathrm{gain}+\mathrm{Max}(s_m))$. Negamax halves the code; minimax is clearer when the two players have *different* move sets (partisan).
- If the total $T$ is fixed (players split a pile of value $T$), maximising your own total is the same as maximising the difference: first player's total $= (T + V)/2$.

*Why is this optimal play?* Induction on the remaining length: if both players play optimally from every successor, the player to move picks the move maximising their result, and the recurrence is exactly that choice. Correctness needs only that the game is finite (acyclic state graph) and that both players' objectives are opposite (zero-sum).

**The naive approach** is the full game tree: $b^d$ leaves. The waste is that the *state* that matters (remaining interval, set of used items, current node) is tiny compared with the move history. Memoise on the state: cost = states × moves.

### 1.2 Designing the state

Ask: "What do I need to know about the past to play optimally from here?" — the same question as in any DP ([DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md)).

| Game shape | State | Typical cost |
|---|---|---|
| take from either end of a row (Deque, Stone Game) | interval $[l,r]$ (the turn is implied by the length) | $O(n^2)$ |
| take a prefix of length $1..2M$ (Stone Game II) | (position, $M$) | $O(n^3)$ or $O(n^2)$ |
| choose unused items (Can I Win, picks and bans) | bitmask of used items | $O(2^n n)$ |
| move a token in a tree / trie | node | $O(n)$ |
| decision-token games (Pie Rules) | (index, who holds the token) — often collapses to index | $O(n)$ |
| comparison games (lexicographic outcome) | interval + result in $\{-1,0,1\}$ | $O(n^2)$ |

If the turn is not implied by the state (e.g. players may pass, or move counts differ), add it explicitly.

### 1.3 Series of games: the can-win / can-lose pair

When $k$ games are played and "the loser of a game starts the next", controlling who *starts* the last game matters, so the first player may want to **lose** on purpose. Compute two booleans per state: $\mathrm{canWin}(v)$ (the mover can force a win) and $\mathrm{canLose}(v)$ (the mover can force a loss). Both follow the same "exists a child where the opponent cannot …" recurrence with different terminal values. Then:

- $\lnot\mathrm{canWin}$: the second player wins every game they want — `Second`.
- $\mathrm{canWin} \land \mathrm{canLose}$: lose games $1..k-1$ deliberately (staying the starter), win game $k$ — `First`.
- $\mathrm{canWin} \land \lnot\mathrm{canLose}$: the starter always wins and cannot avoid it, so the starter alternates; `First` iff $k$ odd.

### 1.4 Draws and cycles: retrograde analysis

If positions can repeat (moves on a cycle, pieces moving back and forth), the recursion has no base order and plain memoised recursion loops forever. The fix is to run the induction **backwards from the known results**:

1. Every terminal position is **Lose** for the player to move (normal play); put them in a queue.
2. Pop a decided position $u$. For each predecessor $p$ (a position with a move $p \to u$) that is undecided:
   - if $u$ is **Lose**, then $p$ is **Win** (move to $u$);
   - if $u$ is **Win**, decrement $\mathrm{cnt}[p]$ (its number of undecided-or-winning successors); when it hits 0, *every* move from $p$ goes to a Win, so $p$ is **Lose**.
3. Everything never decided is a **Draw** (infinite play).

*Why the leftovers are draws.* An undecided $p$ has a successor that is not Win (otherwise its counter would reach 0) and no successor that is Lose (otherwise it would be Win). So from an undecided position the mover can always move to an undecided position, and never has to move into a Win; neither player can force termination in their favour — with optimal play the game goes on forever. *Why the labels are right:* by induction on the BFS layer, a Win/Lose label corresponds to a strategy that forces the result within that many moves.

Cost $O(V + E)$ on the reversed graph. This is also how chess endgame tablebases are built. Games with **two different players** (partisan): the state is (position, player to move) and predecessors switch the player (Example 6).

### 1.5 Alpha-beta pruning (when you can't memoise)

When states cannot be memoised (too many, or no compact encoding) but the tree is shallow, search it with **alpha-beta**: keep a window $(\alpha,\beta)$ of values that still matter; as soon as one move proves the current node is worth $\ge \beta$, the opponent would never enter it — stop. With good move ordering the search visits about $O(b^{d/2})$ nodes instead of $b^d$. In CP it's a last resort (small board games, "simulate the opponent" heuristics); memoised DP wins whenever the state is small. Code in §3.4.

### 1.6 Interactive games: "choose First or Second"

The pattern: the judge describes a game; you print `First` or `Second`, then actually **play** against an adaptive judge. Structure every solution as:

1. decide the winner with the theory (P/N analysis, invariant);
2. maintain the invariant that makes your side win (e.g. "after my move the pile is a multiple of $k+1$");
3. flush after every output; read and validate the judge's moves; stop exactly when the game ends.

Always test the strategy offline against a simulated judge (random and greedy opponents) before submitting. See [interactive problems](../03-Greedy-Constructive-Interactive/05-interactive-problems.md) for I/O mechanics.

### 1.7 When the DP collapses to greedy

Sometimes optimal play is greedy, and the DP is only needed to *discover* that: e.g. both players picking items where each item gives $a_i$ to one player and removes $b_i$ from the other — sorting by $a_i + b_i$ is optimal ([LC 1686 · Stone Game VI](https://leetcode.com/problems/stone-game-vi/) — Medium). But "always take the larger end" is **not** optimal for Deque: on $[5,4,10,8]$ taking 8 gives a difference of $-1$, while taking the smaller 5 gives $+3$ (it denies the opponent the 10). Compare against the DP before believing a greedy.

---

## 2. Formulas, definitions and identities

| Formula | Meaning |
|---|---|
| $V(s) = \max_m(\mathrm{gain}(m) - V(s_m))$, $V(\text{end}) = 0$ | negamax value for the mover |
| first player's total $=(T + V(s_0))/2$ | constant-sum games with total $T$ |
| Deque: $D[l][r] = \max(a_l - D[l+1][r],\ a_r - D[l][r-1])$, $D[l][l] = a_l$ | interval negamax, $O(n^2)$ |
| Pie Rules: $H_i = \max(a_i + (S_{i+1} - H_{i+1}),\ H_{i+1})$ | token-holder value, $S$ = suffix sums |
| comparison games: $R = \mathrm{inner} \ne 0\ ?\ \mathrm{inner} : \mathrm{cmp}(x,y)$ | later picks are prepended, so the inner result is more significant |
| canWin(leaf) = false, canLose(leaf) = true; canX(v) = $\exists$ child $c$: $\lnot$canX($c$) | series of games |
| retrograde: Lose $\to$ predecessors Win; Win $\to$ decrement; count 0 $\to$ Lose; rest Draw | cyclic graphs, $O(V+E)$ |
| alpha-beta child window: $(\mathrm{gain} - \beta,\ \mathrm{gain} - \alpha)$ | negamax with pruning |
| subset games: states $2^n$, transitions $n$ $\Rightarrow O(n2^n)$; $n \le 20$ | Can I Win |

---

## 3. Implementation (C++ and Java)

### 3.1 Retrograde analysis on a general directed graph (Win / Lose / Draw)

Input: $n, m$ and $m$ moves $u \to v$ (cycles allowed). Normal play: a vertex with no moves is Lose for the player to move. Output one character per vertex: `W`, `L` or `D`.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, m; cin >> n >> m;
    vector<vector<int>> radj(n + 1);
    vector<int> cnt(n + 1, 0), res(n + 1, 0);            // res: 0 draw/unknown, 1 win, 2 lose
    for (int i = 0; i < m; i++) { int u, v; cin >> u >> v; radj[v].push_back(u); cnt[u]++; }
    queue<int> q;
    for (int v = 1; v <= n; v++) if (cnt[v] == 0) { res[v] = 2; q.push(v); }
    while (!q.empty()) {
        int u = q.front(); q.pop();
        for (int p : radj[u]) {
            if (res[p]) continue;
            if (res[u] == 2) { res[p] = 1; q.push(p); }     // p can move into a losing position
            else if (--cnt[p] == 0) { res[p] = 2; q.push(p); }   // every move of p reaches a win
        }
    }
    string s;
    for (int v = 1; v <= n; v++) s += "DWL"[res[v]];
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
        int[] head = new int[n + 1], nxt = new int[m], from = new int[m], cnt = new int[n + 1], res = new int[n + 1];
        Arrays.fill(head, -1);
        for (int i = 0; i < m; i++) {
            int u = in.nextInt(), v = in.nextInt();
            from[i] = u; nxt[i] = head[v]; head[v] = i; cnt[u]++;   // reverse adjacency: v -> u
        }
        int[] q = new int[n]; int qh = 0, qt = 0;
        for (int v = 1; v <= n; v++) if (cnt[v] == 0) { res[v] = 2; q[qt++] = v; }
        while (qh < qt) {
            int u = q[qh++];
            for (int e = head[u]; e != -1; e = nxt[e]) {
                int p = from[e];
                if (res[p] != 0) continue;
                if (res[u] == 2) { res[p] = 1; q[qt++] = p; }
                else if (--cnt[p] == 0) { res[p] = 2; q[qt++] = p; }
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int v = 1; v <= n; v++) sb.append("DWL".charAt(res[v]));
        System.out.println(sb);
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
3 3
1 2
2 1
2 3
out:
LWL
-->
<!-- test
in:
2 2
1 2
2 1
out:
DD
-->
<!-- test
in:
4 4
1 2
2 1
1 3
3 4
out:
DDWL
-->
<!-- test
in:
4 4
1 2
2 3
3 1
3 4
out:
WLWL
-->

### 3.2 Interval negamax (fragment)

```cpp
// value (mover's total minus opponent's total) of the "take from either end" game
long long dequeValue(const vector<long long>& a) {
    int n = a.size();
    vector<long long> dp(a);                       // dp[l] = value of a[l..l+len-1]
    for (int len = 2; len <= n; len++)
        for (int l = 0; l + len - 1 < n; l++)
            dp[l] = max(a[l] - dp[l + 1], a[l + len - 1] - dp[l]);
    return n ? dp[0] : 0;
}
```

```java
static long dequeValue(long[] a) {
    int n = a.length;
    if (n == 0) return 0;
    long[] dp = a.clone();
    for (int len = 2; len <= n; len++)
        for (int l = 0; l + len - 1 < n; l++)
            dp[l] = Math.max(a[l] - dp[l + 1], a[l + len - 1] - dp[l]);
    return dp[0];
}
```

### 3.3 Subset-state minimax: "Can I Win" (fragment)

Numbers $1..m$ ($m \le 20$); players alternately take an unused number and add it to a running total; whoever brings the total to $\ge$ `target` wins. The remaining target is determined by the used set, so the mask alone is the state.

```cpp
bool canIWin(int m, int target) {
    if (target <= 0) return true;
    if (m * (m + 1) / 2 < target) return false;        // nobody can ever reach it
    vector<signed char> memo(1 << m, -1);
    function<bool(int, int)> win = [&](int used, int rem) -> bool {
        signed char& r = memo[used];
        if (r != -1) return r;
        for (int i = 0; i < m; i++)
            if (!(used >> i & 1) && (i + 1 >= rem || !win(used | 1 << i, rem - i - 1))) return r = 1;
        return r = 0;
    };
    return win(0, target);
}
```

```java
static byte[] memoCIW;

static boolean canIWin(int m, int target) {
    if (target <= 0) return true;
    if (m * (m + 1) / 2 < target) return false;
    memoCIW = new byte[1 << m];                        // 0 unknown, 1 win, 2 lose
    return winCIW(m, 0, target);
}

static boolean winCIW(int m, int used, int rem) {
    if (memoCIW[used] != 0) return memoCIW[used] == 1;
    boolean res = false;
    for (int i = 0; i < m && !res; i++)
        if ((used >> i & 1) == 0 && (i + 1 >= rem || !winCIW(m, used | 1 << i, rem - i - 1))) res = true;
    memoCIW[used] = (byte) (res ? 1 : 2);
    return res;
}
```

### 3.4 Alpha-beta negamax (fragment, illustrated on the deque game)

```cpp
// value for the player to move on a[l..r]; only values inside (alpha, beta) are exact
long long alphabeta(const vector<long long>& a, int l, int r, long long alpha, long long beta) {
    if (l > r) return 0;
    long long best = LLONG_MIN / 4;
    for (int side = 0; side < 2; side++) {
        long long gain = side == 0 ? a[l] : a[r];
        long long v = gain - alphabeta(a, side == 0 ? l + 1 : l, side == 0 ? r : r - 1, gain - beta, gain - alpha);
        best = max(best, v);
        alpha = max(alpha, v);
        if (alpha >= beta) break;                       // opponent will never allow this line: prune
    }
    return best;
}
```

```java
static long alphabeta(long[] a, int l, int r, long alpha, long beta) {
    if (l > r) return 0;
    long best = Long.MIN_VALUE / 4;
    for (int side = 0; side < 2; side++) {
        long gain = side == 0 ? a[l] : a[r];
        long v = gain - alphabeta(a, side == 0 ? l + 1 : l, side == 0 ? r : r - 1, gain - beta, gain - alpha);
        best = Math.max(best, v);
        alpha = Math.max(alpha, v);
        if (alpha >= beta) break;
    }
    return best;
}
```

Call with `alphabeta(a, 0, n-1, -INF, +INF)` (use $\pm 10^{18}$, not `LLONG_MIN`, to keep the negations from overflowing).

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "both play optimally to maximise their own score" | zero-sum value DP (negamax); first total $= (T+V)/2$ |
| take from the left or right end | interval DP on $[l,r]$ |
| pick from a small set ($n \le 20$) | bitmask state |
| token moves down a tree / trie / DAG | DP over nodes in reverse topological order |
| several games in a row, "the loser starts the next" | canWin / canLose pair |
| moves can return to earlier positions; "or the game lasts forever" | retrograde BFS, Win / Lose / Draw |
| lexicographic or "who is smaller" outcomes | DP with values in $\{-1,0,1\}$; think about which choices are most significant |
| "print First or Second, then play" | theory decides the side; implement the invariant interactively |
| a huge state but a shallow game tree | alpha-beta search |

Confusions: a game where one player maximises the *number of moves* and the other minimises it is still minimax (value = length). Probability + choice games (one player decides, then chance) are expected-value DP ([probability DP](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md)), not minimax.

---

## 5. Worked examples (graded)

### Example 1 — Pie Rules (decision-token game)  ·  ★ 1500

- **Source:** [CF 859C · Pie Rules](https://codeforces.com/problemset/problem/859/C) — 1500
- **Difficulty:** 1500
- **Problem:** $n \le 50$ slices of sizes $a_i \le 10^5$, handed out in the given order. Whoever holds the "decider" token gives the next slice to one participant and the token to the other. Bob starts with the token; each maximises their own total. Print Alice's total and Bob's total.
- **Thinking from first principles:** At slice $i$ the only thing that matters is who holds the token; the past totals are irrelevant to future choices. By symmetry the holder's best total $H_i$ from slices $i..n-1$ doesn't depend on *who* holds it. Two options: keep the slice (then the other side holds the token for the rest, and you get the rest minus their best), or give the slice away and keep the token.

<details><summary>Solution</summary>

$H_n = 0$, $H_i = \max\big(a_i + (S_{i+1} - H_{i+1}),\ H_{i+1}\big)$ with $S_i = \sum_{j\ge i} a_j$. Bob $=H_0$, Alice $=S_0 - H_0$. Correctness: constant-sum game, so maximising one's total is negamax; induction on $i$. Checked against an exhaustive search on random inputs ($n \le 10$). $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    int n; cin >> n;
    vector<long long> a(n), suf(n + 1, 0), dp(n + 1, 0);
    for (auto& x : a) cin >> x;
    for (int i = n - 1; i >= 0; i--) suf[i] = suf[i + 1] + a[i];
    for (int i = n - 1; i >= 0; i--)                       // dp[i]: best total of the token holder on slices i..n-1
        dp[i] = max(a[i] + (suf[i + 1] - dp[i + 1]),         // take the slice, hand over the token
                    dp[i + 1]);                              // give the slice away, keep the token
    cout << suf[0] - dp[0] << " " << dp[0] << "\n";          // Bob starts with the token
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        StreamTokenizer st = new StreamTokenizer(new BufferedReader(new InputStreamReader(System.in)));
        st.nextToken(); int n = (int) st.nval;
        long[] a = new long[n], suf = new long[n + 1], dp = new long[n + 1];
        for (int i = 0; i < n; i++) { st.nextToken(); a[i] = (long) st.nval; }
        for (int i = n - 1; i >= 0; i--) suf[i] = suf[i + 1] + a[i];
        for (int i = n - 1; i >= 0; i--) dp[i] = Math.max(a[i] + (suf[i + 1] - dp[i + 1]), dp[i + 1]);
        System.out.println((suf[0] - dp[0]) + " " + dp[0]);
    }
}
```

</details>

<!-- test
in:
3
141 592 653
out:
653 733
-->
<!-- test
in:
5
10 21 10 21 10
out:
31 41
-->
<!-- test
in:
1
5
out:
0 5
-->

### Example 2 — Deque (interval negamax)  ·  ★ ≈1600

- **Source:** [AtCoder DP L · Deque](https://atcoder.jp/contests/dp/tasks/dp_l)
- **Difficulty:** ≈1600 (est.)
- **Problem:** A row $a_1..a_n$ ($n \le 3000$, $a_i \le 10^9$). Players alternately remove the first or last element and add it to their score. Taro (first) maximises $X - Y$, Jiro minimises it. Print $X - Y$.
- **Thinking from first principles:** Greedy "take the larger end" fails: on $[5,4,10,8]$ it takes 8 and ends at $-1$, while taking 5 first ends at $+3$. The remaining row is always a contiguous interval, and the score difference from here on doesn't depend on the past. Negamax over intervals: the mover takes an end and subtracts the opponent's value on the rest.

<details><summary>Solution</summary>

$D[l][r] = \max(a_l - D[l+1][r],\ a_r - D[l][r-1])$, $D[l][l] = a_l$; answer $D[1][n]$. Iterate by length with a rolling 1-D array (in Java a $3000\times3000$ `long` table is 72 MB — avoid it). Values reach $3\cdot10^{12}$: use 64-bit. Checked against exhaustive minimax for $n \le 10$. $O(n^2)$ time, $O(n)$ memory.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<long long> a(n);
    for (auto& x : a) cin >> x;
    vector<long long> dp(a);                       // length 1: dp[l] = a[l]
    for (int len = 2; len <= n; len++)
        for (int l = 0; l + len - 1 < n; l++) {    // dp[l] holds [l, l+len-2], dp[l+1] holds [l+1, l+len-1]
            int r = l + len - 1;
            dp[l] = max(a[l] - dp[l + 1], a[r] - dp[l]);
        }
    cout << dp[0] << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        long[] a = new long[n];
        for (int i = 0; i < n; i++) a[i] = in.nextLong();
        long[] dp = a.clone();
        for (int len = 2; len <= n; len++)
            for (int l = 0; l + len - 1 < n; l++)
                dp[l] = Math.max(a[l] - dp[l + 1], a[l + len - 1] - dp[l]);
        System.out.println(dp[0]);
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
10 80 90 30
out:
10
-->
<!-- test
in:
3
10 100 10
out:
-80
-->
<!-- test
in:
1
10
out:
10
-->
<!-- test
in:
10
1000000000 1 1000000000 1 1000000000 1 1000000000 1 1000000000 1
out:
4999999995
-->
<!-- test
in:
6
4 2 9 7 1 5
out:
2
-->

### Example 3 — Choose your side (interactive Bash game)  ·  ★ ≈1600

- **Source:** Original problem
- **Difficulty:** ≈1600 (est.)
- **Problem (interactive):** The judge gives $n \le 10^{12}$ stones and $k \le 10^6$. You print `First` or `Second`; then players alternately remove $1..k$ stones (you move first iff you chose `First`); whoever takes the last stone wins. On your turn print the number you take; on the judge's turn read the judge's number. The judge is adaptive.
- **Thinking from first principles:** The theory is the Bash game ([file 01](01-game-fundamentals-winning-losing-states.md)): P iff $n \equiv 0 \pmod{k+1}$. So choose `Second` iff $n \bmod (k+1) = 0$. The *playing* part is the invariant "after my move, the pile is a multiple of $k+1$": the judge then takes $y\in[1,k]$, leaving residue $(k+1-y) \in [1,k]$, and I take exactly that residue.

<details><summary>Solution</summary>

Interactive program (untestable offline as written — flush after every move):

<!-- notest -->
```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    long long n, k; cin >> n >> k;
    bool myTurn = n % (k + 1) != 0;
    cout << (myTurn ? "First" : "Second") << endl;          // endl flushes
    while (n > 0) {
        if (myTurn) { long long x = n % (k + 1); cout << x << endl; n -= x; }
        else { long long y; cin >> y; if (y < 1) return 0; n -= y; }   // y < 1: judge signals an error
        myTurn = !myTurn;
    }
}
```

<!-- notest -->
```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        long n = Long.parseLong(st.nextToken()), k = Long.parseLong(st.nextToken());
        boolean myTurn = n % (k + 1) != 0;
        System.out.println(myTurn ? "First" : "Second");
        System.out.flush();
        while (n > 0) {
            if (myTurn) { long x = n % (k + 1); System.out.println(x); System.out.flush(); n -= x; }
            else { long y = Long.parseLong(br.readLine().trim()); if (y < 1) return; n -= y; }
            myTurn = !myTurn;
        }
    }
}
```

Offline verification: the same strategy against a simulated adaptive judge (it plays the winning move when it has one, otherwise a pseudo-random legal move from the given seed). Input `n k seed`; output the side chosen and `WIN`/`LOSE`. The strategy must print `WIN` for every input; the side is $n \bmod (k+1) \ne 0$ ? `First` : `Second`.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    long long n, k; unsigned long long seed; cin >> n >> k >> seed;
    auto rnd = [&]() { seed = seed * 6364136223846793005ULL + 1442695040888963407ULL; return seed >> 33; };
    bool myTurn = n % (k + 1) != 0;
    string side = myTurn ? "First" : "Second";
    bool iWon = false;
    while (n > 0) {
        long long take;
        if (myTurn) take = n % (k + 1);                                  // the strategy under test
        else {                                                            // simulated judge
            long long r = n % (k + 1);
            take = r != 0 ? r : 1 + (long long)(rnd() % min<long long>(k, n));
        }
        if (take < 1 || take > k || take > n) { cout << side << " ILLEGAL\n"; return 0; }
        n -= take;
        if (n == 0) iWon = myTurn;
        myTurn = !myTurn;
    }
    cout << side << " " << (iWon ? "WIN" : "LOSE") << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long seed;

    static long rnd() {
        seed = seed * 6364136223846793005L + 1442695040888963407L;
        return seed >>> 33;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        long n = Long.parseLong(st.nextToken()), k = Long.parseLong(st.nextToken());
        seed = Long.parseUnsignedLong(st.nextToken());
        boolean myTurn = n % (k + 1) != 0;
        String side = myTurn ? "First" : "Second";
        boolean iWon = false;
        while (n > 0) {
            long take;
            if (myTurn) take = n % (k + 1);
            else {
                long r = n % (k + 1);
                take = r != 0 ? r : 1 + rnd() % Math.min(k, n);
            }
            if (take < 1 || take > k || take > n) { System.out.println(side + " ILLEGAL"); return; }
            n -= take;
            if (n == 0) iWon = myTurn;
            myTurn = !myTurn;
        }
        System.out.println(side + " " + (iWon ? "WIN" : "LOSE"));
    }
}
```

</details>

<!-- test
in:
10 3 7
out:
First WIN
-->
<!-- test
in:
12 3 5
out:
Second WIN
-->
<!-- test
in:
1 1 1
out:
First WIN
-->
<!-- test
in:
1000000000000 1000000 42
out:
First WIN
-->
<!-- test
in:
999999 999999 3
out:
First WIN
-->

### Example 4 — Letter Picking (comparison outcome on intervals)  ·  ★ 1800

- **Source:** [CF 1728D · Letter Picking](https://codeforces.com/problemset/problem/1728/D) — 1800
- **Difficulty:** 1800
- **Problem:** A string $s$ of even length ($\sum |s| \le 2000$). Alice and Bob alternately (Alice first) take the first or last letter of $s$ and **prepend** it to their own initially empty string. At the end the lexicographically smaller string wins; equal is a draw. Print `Alice`, `Bob` or `Draw`.
- **Thinking from first principles:** The remaining letters always form an interval. Group moves in **rounds** (Alice then Bob): the remaining interval always has even length at the start of a round. Because letters are *prepended*, the letters taken in later rounds end up **in front**. So the result of the inner interval (later rounds) is more significant than this round's pair of letters, which only matters if the inner result is a draw. Dead end: trying to track whole strings — unnecessary, the outcome of the inner game is a value in $\{-1,0,+1\}$.

<details><summary>Solution</summary>

For even-length $[l,r]$: $D[l][r] = \max_{\text{Alice's end } x} \min_{\text{Bob's end } y} \mathrm{comb}(D[\text{inner}], x, y)$, where $\mathrm{comb}(v,x,y) = v$ if $v \ne 0$, else $+1$ if $x<y$, $0$ if $x=y$, $-1$ if $x>y$; $D[\varnothing] = 0$. Output by the sign of $D[0][n-1]$. Both strings have the same length after each round, so comparing "inner part first, then this round's letters" is exactly the lexicographic comparison. Checked against a brute force that builds the actual strings, for random strings of length $\le 10$. (The answer is never `Bob` — a nice fact you can prove by a pairing argument, but the DP doesn't need it.) $O(n^2)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        string s; cin >> s;
        int n = s.size();
        // dp[l][r] on even-length s[l..r]: +1 Alice wins, 0 draw, -1 Bob wins (Alice maximises)
        vector<vector<signed char>> dp(n + 1, vector<signed char>(n + 1, 0));
        auto cmp = [](char x, char y) { return x < y ? 1 : (x == y ? 0 : -1); };
        auto inner = [&](int i, int j) { return i > j ? 0 : (int)dp[i][j]; };
        auto comb = [&](int in, char x, char y) { return in != 0 ? in : cmp(x, y); };
        for (int len = 2; len <= n; len += 2)
            for (int l = 0; l + len - 1 < n; l++) {
                int r = l + len - 1;
                int takeL = min(comb(inner(l + 2, r), s[l], s[l + 1]), comb(inner(l + 1, r - 1), s[l], s[r]));
                int takeR = min(comb(inner(l + 1, r - 1), s[r], s[l]), comb(inner(l, r - 2), s[r], s[r - 1]));
                dp[l][r] = max(takeL, takeR);
            }
        int res = dp[0][n - 1];
        cout << (res > 0 ? "Alice" : res == 0 ? "Draw" : "Bob") << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static byte[][] dp;

    static int inner(int i, int j) { return i > j ? 0 : dp[i][j]; }

    static int comb(int in, char x, char y) { return in != 0 ? in : (x < y ? 1 : (x == y ? 0 : -1)); }

    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int t = Integer.parseInt(br.readLine().trim());
        StringBuilder out = new StringBuilder();
        while (t-- > 0) {
            char[] s = br.readLine().trim().toCharArray();
            int n = s.length;
            dp = new byte[n + 1][n + 1];
            for (int len = 2; len <= n; len += 2)
                for (int l = 0; l + len - 1 < n; l++) {
                    int r = l + len - 1;
                    int takeL = Math.min(comb(inner(l + 2, r), s[l], s[l + 1]), comb(inner(l + 1, r - 1), s[l], s[r]));
                    int takeR = Math.min(comb(inner(l + 1, r - 1), s[r], s[l]), comb(inner(l, r - 2), s[r], s[r - 1]));
                    dp[l][r] = (byte) Math.max(takeL, takeR);
                }
            int res = dp[0][n - 1];
            out.append(res > 0 ? "Alice" : res == 0 ? "Draw" : "Bob").append('\n');
        }
        System.out.print(out);
    }
}
```

</details>

<!-- test
in:
2
forces
abba
out:
Alice
Draw
-->
<!-- test
in:
4
aa
ab
bbaa
zazbzc
out:
Draw
Alice
Draw
Alice
-->

### Example 5 — A Lot of Games (trie game DP, series of games)  ·  ★ 1900

- **Source:** [CF 455B · A Lot of Games](https://codeforces.com/problemset/problem/455/B) — 1900
- **Difficulty:** 1900
- **Problem:** $n$ strings (total length $\le 10^5$). A game builds a word letter by letter; each player appends a letter so that the word stays a prefix of some given string; who cannot move loses. $k \le 10^9$ games are played; the loser of game $i$ starts game $i+1$; whoever wins the **last** game wins overall. Who wins, the first player of game 1 (`First`) or the other (`Second`)?
- **Thinking from first principles:** A single game is a token moving down the trie from the root; leaves are terminal (mover loses). With several games, the first player may prefer to *lose* game 1 to keep starting. So compute both "can force a win" and "can force a loss" (§1.3). Dead end: simulating $k$ games — $k$ is $10^9$, but only three cases exist.

<details><summary>Solution</summary>

Trie; process nodes in decreasing id (children are created after parents, so this is a valid bottom-up order — no recursion). Leaf: canWin = false, canLose = true. Internal: canWin = some child has canWin = false; canLose = some child has canLose = false. Answer: ¬canWin → `Second`; canWin ∧ canLose → `First`; canWin ∧ ¬canLose → `First` iff $k$ odd. Checked against an exhaustive search over the whole series (state = game index, node, mover) for random small tries and $k \le 6$. $O(26\cdot L)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long k; cin >> n >> k;
    vector<array<int, 26>> ch(1);
    ch[0].fill(0);
    for (int i = 0; i < n; i++) {
        string s; cin >> s;
        int v = 0;
        for (char c : s) {
            if (!ch[v][c - 'a']) { ch[v][c - 'a'] = ch.size(); ch.push_back({}); ch.back().fill(0); }
            v = ch[v][c - 'a'];
        }
    }
    int m = ch.size();
    vector<char> canWin(m, 0), canLose(m, 0);
    for (int v = m - 1; v >= 0; v--) {                 // children always have larger ids than parents
        bool leaf = true;
        for (int c = 0; c < 26; c++) if (ch[v][c]) {
            leaf = false;
            int u = ch[v][c];
            if (!canWin[u]) canWin[v] = 1;
            if (!canLose[u]) canLose[v] = 1;
        }
        if (leaf) { canWin[v] = 0; canLose[v] = 1; }     // the mover cannot move: loses this game
    }
    bool first;
    if (!canWin[0]) first = false;
    else if (canLose[0]) first = true;
    else first = (k % 2 == 1);
    cout << (first ? "First" : "Second") << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int n = Integer.parseInt(st.nextToken());
        long k = Long.parseLong(st.nextToken());
        int cap = 1;
        String[] w = new String[n];
        for (int i = 0; i < n; i++) { w[i] = br.readLine().trim(); cap += w[i].length(); }
        int[][] ch = new int[cap][26];
        int m = 1;
        for (String s : w) {
            int v = 0;
            for (int i = 0; i < s.length(); i++) {
                int c = s.charAt(i) - 'a';
                if (ch[v][c] == 0) ch[v][c] = m++;
                v = ch[v][c];
            }
        }
        boolean[] canWin = new boolean[m], canLose = new boolean[m];
        for (int v = m - 1; v >= 0; v--) {
            boolean leaf = true;
            for (int c = 0; c < 26; c++) if (ch[v][c] != 0) {
                leaf = false;
                int u = ch[v][c];
                if (!canWin[u]) canWin[v] = true;
                if (!canLose[u]) canLose[v] = true;
            }
            if (leaf) { canWin[v] = false; canLose[v] = true; }
        }
        boolean first;
        if (!canWin[0]) first = false;
        else if (canLose[0]) first = true;
        else first = k % 2 == 1;
        System.out.println(first ? "First" : "Second");
    }
}
```

</details>

<!-- test
in:
2 3
a
b
out:
First
-->
<!-- test
in:
3 1
a
b
c
out:
First
-->
<!-- test
in:
1 2
ab
out:
Second
-->
<!-- test
in:
1 1000000000
a
out:
Second
-->
<!-- test
in:
2 2
ab
b
out:
First
-->

### Example 6 — Berzerk (retrograde analysis with draws, two players)  ·  ★ 2000

- **Source:** [CF 786A · Berzerk](https://codeforces.com/problemset/problem/786/A) — 2000
- **Difficulty:** 2000
- **Problem:** $n \le 7000$ objects on a circle, object 1 is a black hole. A monster starts on some object $2..n$. Rick has a set $s_1$ of step sizes, Morty a set $s_2$ (sizes in $[1,n-1]$). On a turn the player moves the monster clockwise by a step from **their own** set; whoever moves it into the black hole wins. For every start object and each choice of first player, print `Win`, `Lose` or `Loop` (the game never ends) for the first player.
- **Thinking from first principles:** The state is (position, player to move): $2n$ states, $\le n$ moves each — $O(n^2) \approx 5\cdot10^7$ edges total, fine. Positions repeat (it's a circle), so memoised recursion is wrong — use retrograde BFS (§1.4). Terminal: monster in the hole with either player to move = **Lose** for that player (the other just won). Predecessors of $(p, w)$ are $(p - x, 1-w)$ for $x$ in the *other* player's set.

<details><summary>Solution</summary>

Initialise `res[w][0] = Lose` for both $w$, `cnt[w][p] = |s_w|`. BFS: popping $(p,w)$, for each $x \in s_{1-w}$, $q = p-x \bmod n$, skip $q=0$ (no moves out of the hole) and decided states; if $(p,w)$ is Lose then $(q,1-w)$ is Win; else decrement `cnt[1-w][q]` and mark Lose at 0. Undecided = `Loop`. Proof §1.4. Checked against a naive fixed-point iteration on random small inputs (and it reproduces the two official samples). $O(n(|s_1|+|s_2|))$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    vector<int> s[2];
    for (int p = 0; p < 2; p++) { int k; cin >> k; s[p].resize(k); for (auto& x : s[p]) cin >> x; }
    // position 0 = black hole; state (p, w): monster at p, player w to move
    vector<int> res[2], cnt[2];                          // res: 0 unknown (loop), 1 win, 2 lose for the mover
    for (int w = 0; w < 2; w++) { res[w].assign(n, 0); cnt[w].assign(n, (int)s[w].size()); }
    queue<pair<int, int>> q;
    res[0][0] = res[1][0] = 2;                           // monster in the hole: the player to move has lost
    q.push({0, 0}); q.push({0, 1});
    while (!q.empty()) {
        auto [p, w] = q.front(); q.pop();
        int o = 1 - w;                                   // the player who moved into (p, w)
        for (int x : s[o]) {
            int prv = ((p - x) % n + n) % n;
            if (prv == 0 || res[o][prv]) continue;       // no moves out of the hole; already decided
            if (res[w][p] == 2) { res[o][prv] = 1; q.push({prv, o}); }
            else if (--cnt[o][prv] == 0) { res[o][prv] = 2; q.push({prv, o}); }
        }
    }
    const char* name[3] = {"Loop", "Win", "Lose"};
    for (int w = 0; w < 2; w++)
        for (int p = 1; p < n; p++) cout << name[res[w][p]] << " \n"[p == n - 1];
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[][] s = new int[2][];
        for (int p = 0; p < 2; p++) { int k = in.nextInt(); s[p] = new int[k]; for (int i = 0; i < k; i++) s[p][i] = in.nextInt(); }
        int[][] res = new int[2][n], cnt = new int[2][n];
        for (int w = 0; w < 2; w++) Arrays.fill(cnt[w], s[w].length);
        int[] qp = new int[2 * n], qw = new int[2 * n];
        int qh = 0, qt = 0;
        res[0][0] = res[1][0] = 2;
        qp[qt] = 0; qw[qt++] = 0; qp[qt] = 0; qw[qt++] = 1;
        while (qh < qt) {
            int p = qp[qh], w = qw[qh++], o = 1 - w;
            for (int x : s[o]) {
                int prv = ((p - x) % n + n) % n;
                if (prv == 0 || res[o][prv] != 0) continue;
                if (res[w][p] == 2) { res[o][prv] = 1; qp[qt] = prv; qw[qt++] = o; }
                else if (--cnt[o][prv] == 0) { res[o][prv] = 2; qp[qt] = prv; qw[qt++] = o; }
            }
        }
        String[] name = {"Loop", "Win", "Lose"};
        StringBuilder sb = new StringBuilder();
        for (int w = 0; w < 2; w++)
            for (int p = 1; p < n; p++) sb.append(name[res[w][p]]).append(p == n - 1 ? '\n' : ' ');
        System.out.print(sb);
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
5
2 3 2
3 1 2 3
out:
Lose Win Win Loop
Loop Win Win Win
-->
<!-- test
in:
8
4 6 2 3 4
2 3 6
out:
Win Win Win Win Win Win Win
Lose Win Lose Lose Win Lose Lose
-->
<!-- test
in:
2
1 1
1 1
out:
Win
Win
-->

---

## 6. Tricks, pitfalls and things to remember

1. **Negamax sign errors** are the #1 bug: the child's value is from the *opponent's* perspective; always `gain - V(child)`, never `gain + V(child)`.
2. **The turn is often implied by the state** (interval length parity, number of used items). If it is not, add it — or the DP silently mixes up the players.
3. **Greedy is usually wrong for score games.** Before trusting "take the bigger one", run the DP on random small arrays and compare.
4. **Overflow:** Deque values reach $n\cdot 10^9 = 3\cdot10^{12}$ — `long long`. Alpha-beta with `LLONG_MIN` overflows on negation; use $\pm10^{18}$.
5. **Java memory for $O(n^2)$ tables:** $3000^2$ `long` = 72 MB; roll by length, or use `int`/`byte` when values allow (Letter Picking stores $\{-1,0,1\}$ in `byte`).
6. **Cycles kill memoised recursion.** If a state can repeat, recursion either loops or returns garbage from a half-filled memo. Use retrograde BFS; "Draw/Loop" = never decided.
7. **Retrograde: do not expand moves out of terminal states** (Berzerk: no moves out of the black hole), and count *all* moves of a state in `cnt`, including duplicates if the problem allows parallel moves.
8. **Series of games: compute canLose separately.** canLose is *not* $\lnot$canWin; a leaf is "can lose = true, can win = false".
9. **Interactive:** flush after every line (`endl` / `cout.flush()` / `System.out.flush()`); never print extra debug lines to stdout; read the judge's move even when you know the game is decided, if the protocol says so.
10. **Recursion depth in Java:** trie/tree DPs on $10^5$ nodes — iterate in id order or BFS order instead of recursing.

---

## 7. Going further (toward 2400–2600+)

- **Minimax with prefix-sum structure**: [CF 731E · Funny Game](https://codeforces.com/problemset/problem/731/E) — 2200 (the negamax reduces to a suffix maximum), [CF 1628D2 · Game on Sum (Hard Version)](https://codeforces.com/problemset/problem/1628/D2) — 2400 (the DP has a closed form via binomials).
- **Picks and bans over bitmasks**: [CF 377C · Captains Mode](https://codeforces.com/problemset/problem/377/C) — 2200.
- **Retrograde analysis on huge state spaces**: [CF 919F · A Game With Numbers](https://codeforces.com/problemset/problem/919/F) — 2600 (states = pairs of multisets), [AtCoder ABC261 Ex · Game on Graph](https://atcoder.jp/contests/abc261/tasks/abc261_h) (min/max lengths with cycles — a Dijkstra-like retrograde).
- **Tree games with binary search on the answer**: [CF 1099F · Cookies](https://codeforces.com/problemset/problem/1099/F) — 2400.
- **Interactive role choice at the top level**: [CF 1375F · Integer Game](https://codeforces.com/problemset/problem/1375/F) — 2600, [CF 1934D2 · XOR Break --- Game Version](https://codeforces.com/problemset/problem/1934/D2) — 2400.
- **Probabilistic games** (a player optimises an expected value): [expected value DP](../06-Dynamic-Programming/10-probability-and-expected-value-dp.md), e.g. [CF 148D · Bag of mice](https://codeforces.com/problemset/problem/148/D) — 1800.

---

## 8. Practice ladder

**≤ 1600**
- [ ] [CF 1472D · Even-Odd Game](https://codeforces.com/problemset/problem/1472/D) — 1200
- [ ] [AtCoder ABC195 E · Lucky 7 Battle](https://atcoder.jp/contests/abc195/tasks/abc195_e)
- [ ] [AtCoder ABC201 D · Game in Momotetsu World](https://atcoder.jp/contests/abc201/tasks/abc201_d)
- [ ] [CF 859C · Pie Rules](https://codeforces.com/problemset/problem/859/C) — 1500
- [ ] [CF 1738C · Even Number Addicts](https://codeforces.com/problemset/problem/1738/C) — 1500
- [ ] [AtCoder DP L · Deque](https://atcoder.jp/contests/dp/tasks/dp_l)

**1600–2000**
- [ ] [CF 917B · MADMAX](https://codeforces.com/problemset/problem/917/B) — 1700
- [ ] [CF 1728D · Letter Picking](https://codeforces.com/problemset/problem/1728/D) — 1800
- [ ] [CF 148D · Bag of mice](https://codeforces.com/problemset/problem/148/D) — 1800
- [ ] [CF 1404B · Tree Tag](https://codeforces.com/problemset/problem/1404/B) — 1900
- [ ] [CF 455B · A Lot of Games](https://codeforces.com/problemset/problem/455/B) — 1900
- [ ] [CF 1970C2 · Game on Tree (Medium)](https://codeforces.com/problemset/problem/1970/C2) — 1700
- [ ] [CF 1991E · Coloring Game](https://codeforces.com/problemset/problem/1991/E) — 1900
- [ ] [CF 786A · Berzerk](https://codeforces.com/problemset/problem/786/A) — 2000
- [ ] [CF 39E · What Has Dirichlet Got to Do with That?](https://codeforces.com/problemset/problem/39/E) — 2000

**2000–2400**
- [ ] [CF 63E · Sweets Game](https://codeforces.com/problemset/problem/63/E) — 2000
- [ ] [CF 936B · Sleepy Game](https://codeforces.com/problemset/problem/936/B) — 2100
- [ ] [CF 1628D1 · Game on Sum (Easy Version)](https://codeforces.com/problemset/problem/1628/D1) — 2100
- [ ] [AtCoder ABC209 E · Shiritori](https://atcoder.jp/contests/abc209/tasks/abc209_e)
- [ ] [CF 731E · Funny Game](https://codeforces.com/problemset/problem/731/E) — 2200
- [ ] [CF 377C · Captains Mode](https://codeforces.com/problemset/problem/377/C) — 2200
- [ ] [AtCoder ABC278 G · Generalized Subtraction Game](https://atcoder.jp/contests/abc278/tasks/abc278_g)

**2400+**
- [ ] [CF 1099F · Cookies](https://codeforces.com/problemset/problem/1099/F) — 2400
- [ ] [CF 1375F · Integer Game](https://codeforces.com/problemset/problem/1375/F) — 2600
- [ ] [CF 919F · A Game With Numbers](https://codeforces.com/problemset/problem/919/F) — 2600

---

## 9. LeetCode / FAANG cross-reference

Game DP is a FAANG favourite: it tests whether you can define a state and write a clean memoised recursion.

- [LC 486 · Predict the Winner](https://leetcode.com/problems/predict-the-winner/) — Medium — exactly Deque (§3.2); answer `value >= 0`.
- [LC 877 · Stone Game](https://leetcode.com/problems/stone-game/) — Medium — Deque DP works; the pairing argument ([file 01](01-game-fundamentals-winning-losing-states.md)) gives `true` in $O(1)$.
- [LC 1140 · Stone Game II](https://leetcode.com/problems/stone-game-ii/) — Medium — state (index, $M$); negamax with suffix sums.
- [LC 1406 · Stone Game III](https://leetcode.com/problems/stone-game-iii/) — Hard — linear negamax over the suffix, take 1–3 stones.
- [LC 1690 · Stone Game VII](https://leetcode.com/problems/stone-game-vii/) — Medium — interval negamax where the gain is the remaining sum.
- [LC 1563 · Stone Game V](https://leetcode.com/problems/stone-game-v/) — Hard — interval DP (not zero-sum; one player's score only); $O(n^2)$ with prefix maxima.
- [LC 1686 · Stone Game VI](https://leetcode.com/problems/stone-game-vi/) — Medium — greedy by $a_i+b_i$ (§1.7).
- [LC 1872 · Stone Game VIII](https://leetcode.com/problems/stone-game-viii/) — Hard — negamax over prefix sums collapses to a running maximum.
- [LC 2029 · Stone Game IX](https://leetcode.com/problems/stone-game-ix/) — Medium — case analysis on residues mod 3 (derive it with a small brute force).
- [LC 464 · Can I Win](https://leetcode.com/problems/can-i-win/) — Medium — bitmask minimax (§3.3).
- [LC 375 · Guess Number Higher or Lower II](https://leetcode.com/problems/guess-number-higher-or-lower-ii/) — Medium — minimax cost over intervals: $\min_k(k + \max(L, R))$.
- [LC 913 · Cat and Mouse](https://leetcode.com/problems/cat-and-mouse/) — Hard — retrograde analysis with draws (§3.1), state (mouse, cat, turn).
- [LC 1728 · Cat and Mouse II](https://leetcode.com/problems/cat-and-mouse-ii/) — Hard — same retrograde method on a grid.

Interview tip: say "this is a zero-sum game, the state is X, the value is the score difference for the player to move, and $V = \max(\text{gain} - V(\text{next}))$" — then code the memo. For Cat and Mouse, explain why plain DFS memo is wrong (cycles) before writing the BFS.

---

## 10. Self-check

1. Write the negamax recurrence and explain why the child's value is subtracted.
2. In a constant-sum game with total $T$, how do you get the first player's total from the difference?
3. Why is the Deque DP's state just the interval? How do you fit it into Java memory for $n=3000$?
4. In Letter Picking, why is the inner interval's result more significant than this round's letters?
5. Define canWin/canLose and give the answer of the $k$-game series in all three cases.
6. Describe retrograde analysis. Why are the unlabelled states draws?
7. What does alpha-beta prune, and why can't it beat memoisation when the state space is small?
8. For an interactive "choose First/Second" problem, what three things does a correct solution do?

<details><summary>Answers</summary>

1. $V(s)=\max_m(\mathrm{gain}(m)-V(s_m))$; after the move the opponent is the mover and $V(s_m)$ is their advantage over us.
2. $(T+V)/2$, since first $-$ second $= V$ and first $+$ second $= T$.
3. The removed elements are always a prefix and a suffix; the future depends only on what remains. Roll the table by length into a 1-D array (or store `int` differences if they fit).
4. Letters are prepended, so letters taken later are in front of the final strings; both strings have equal length after each round, so the comparison is decided by the later rounds first.
5. Leaf: win false, lose true; internal: exists a child where the opponent can't. ¬canWin → Second; canWin ∧ canLose → First; else First iff $k$ odd.
6. Seed terminals as Lose; a predecessor of a Lose is Win; a state all of whose moves lead to Win is Lose (counter); leftovers can always move to a leftover and never must move into a Win, so neither side can force an end.
7. It skips subtrees that cannot change the root's value given the current window; it still explores each *path* separately, so repeated states are re-searched — memo DP visits each state once.
8. Decide the winning side from theory; maintain the winning invariant with every move; flush and follow the protocol exactly (read every judge move, stop at the end).

</details>
