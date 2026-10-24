# Game Theory — Cheat Sheet

Revision only. Full derivations: [fundamentals](../13-Game-Theory/01-game-fundamentals-winning-losing-states.md) · [Nim & Sprague–Grundy](../13-Game-Theory/02-nim-and-sprague-grundy.md) · [variants](../13-Game-Theory/03-game-variants-misere-staircase-hackenbush.md) · [minimax & game DP](../13-Game-Theory/04-minimax-and-game-dp.md) · [problem ladder](../13-Game-Theory/problems.md).

## 1. Definitions in one table

| Term | Meaning |
|---|---|
| normal play | player who cannot move **loses** |
| misère play | player who cannot move **wins** (last mover loses) |
| impartial | same moves for both players (Sprague–Grundy applies) |
| partisan | moves depend on the player (put the player in the state; minimax) |
| P-position | previous player wins = player to move **loses** |
| N-position | next player (to move) wins |
| P/N rule | N iff some move → P; P iff all moves → N (terminal = P in normal play) |
| mex | smallest non-negative integer not in a set |
| Grundy $g(v)$ | $\operatorname{mex}\{g(u): v\to u\}$; $g=0 \iff$ P |
| sum of games | move in exactly one component; $g = \bigoplus g_i$ |

**Three-condition proof** that $\mathcal{P}$ is the P-set: terminals $\in\mathcal{P}$ · every move from $\mathcal{P}$ leaves $\mathcal{P}$ · from outside there is a move into $\mathcal{P}$. (Misère: terminals are N, so they must be *outside* $\mathcal{P}$.)

## 2. Results to know cold

| Game | Answer (P-positions or $g$) |
|---|---|
| Bash: take $1..k$ | P $\iff n \equiv 0 \pmod{k+1}$; misère: $n \equiv 1$ |
| Nim | P $\iff \bigoplus a_i = 0$; winning move $a_i \to a_i \oplus s$ for a pile with the top bit of $s$ |
| subtraction $\{1..k\}$ per pile | $g(a) = a \bmod (k+1)$ |
| remove between $L$ and $R$ | $g(a) = \lfloor (a \bmod (L+R))/L \rfloor$ |
| remove $1..\lfloor a/2\rfloor$ | $g(2m)=m$, $g(2m+1)=g(m)$ |
| never repeat an amount on a pile | $g(s) = \max\{k: k(k+1)/2 \le s\}$ |
| $\{1,2,k\}$ (1-2-K) | $3\nmid k$: P iff $3\mid n$; $3\mid k$: $r=n \bmod (k+1)$, P iff $r\ne k$ and $3\mid r$ |
| split a pile of $2x$ into $k$ piles of $x$ | contributes $g(x)$ if $k$ odd, $0$ if $k$ even |
| Lasker's Nim (remove or split in two) | $g = n$ ($n\equiv1,2$), $n+1$ ($n\equiv3$), $n-1$ ($n\equiv0$) mod 4 |
| Kayles | period 12 from $n = 71$ |
| Grundy's game (split into unequal) | P only at 1, 2, 4, 7, 10, 20, 23, 26, 50, 53, 270, …, 1222 (none found later; empirical) |
| misère Nim | all piles $\le1$: P iff #ones odd; else P iff XOR $=0$ |
| staircase Nim (step 0 = sink) | P iff XOR of odd steps $=0$ (CSES Stair Game: stairs $2,4,\dots$) |
| one coin from each of a chosen set of piles | P iff all piles even |
| Moore's Nim$_k$ (up to $k$ piles per move) | P iff every bit column count $\equiv 0 \pmod{k+1}$ |
| Wythoff | P $=(\lfloor k\varphi\rfloor, \lfloor k\varphi^2\rfloor)$; $b_k = a_k + k$ |
| Euclid game ($a\ge b>0$) | P iff $b < a < \varphi b$; $a\ge 2b$ or $a=b$ is N |
| Chomp ($a\times b$) | First wins unless $1\times1$ (strategy stealing) |
| Green Hackenbush: stalk / tree / cycle | $n$ / $\bigoplus_c (g(c)+1)$ / fuse cycle → loops, cycle value $L \bmod 2$ |
| tokens on a DAG | $\bigoplus g(\text{token vertex})$; equal tokens cancel |
| Grundy bound | $g(v)\le\operatorname{outdeg}(v)$; in a DAG with $m$ edges $g\le\sqrt{2m}$ |
| $0\oplus1\oplus\dots\oplus n$ | $n, 1, n+1, 0$ for $n \bmod 4 = 0,1,2,3$ |
| SJ theorem (anti-SG) 🔴 | first wins iff (XOR$\ne0$ ∧ some $g>1$) ∨ (XOR$=0$ ∧ all $g\le1$) — verify on your game |

Constants: $\varphi = 1.6180339887498948482\ldots$, $\varphi^2 = \varphi+1$, $\lfloor k\varphi\rfloor = \lfloor (k + \lfloor\sqrt{5k^2}\rfloor)/2\rfloor$.

## 3. Signal → technique

| Statement says | Do |
|---|---|
| small state space, "who wins" | W/L DP / memo, reverse topological order |
| $n\le10^{18}$, one pile / number | brute force small $n$, find period/closed form, prove |
| several independent piles/boards | Grundy per component, XOR |
| a move splits a pile into parts | option value = XOR of parts |
| symmetric board | mirror strategy (occupy the centre/axis first) |
| two halves to balance | pairing strategy |
| every move removes exactly one thing | parity of the forced move count |
| last mover loses | misère — check the all-small exception |
| coins slide one level towards a sink | staircase Nim (odd levels) |
| same amount from both piles | Wythoff |
| "subtract a multiple of the other number" | Euclid recursion |
| scores, "maximise own total" | negamax $V=\max(\text{gain}-V')$ |
| $k$ games, loser starts the next | canWin + canLose |
| positions repeat / "infinite" / "draw" | retrograde BFS, leftovers = draw |
| "print First or Second" interactively | decide by theory, keep the invariant, flush |

## 4. Templates

### 4.1 Grundy values on a DAG (vertices $0..n-1$, any order)

```cpp
vector<int> grundyDag(const vector<vector<int>>& adj) {
    int n = adj.size();
    vector<int> indeg(n, 0), order, g(n, 0);
    for (int v = 0; v < n; v++) for (int u : adj[v]) indeg[u]++;
    for (int v = 0; v < n; v++) if (!indeg[v]) order.push_back(v);
    for (size_t i = 0; i < order.size(); i++) for (int u : adj[order[i]]) if (--indeg[u] == 0) order.push_back(u);
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i], d = adj[v].size();
        vector<char> seen(d + 1, 0);
        for (int u : adj[v]) if (g[u] <= d) seen[g[u]] = 1;
        while (seen[g[v]]) g[v]++;
    }
    return g;                                   // W/L: win[v] = g[v] != 0
}
```

```java
static int[] grundyDag(List<List<Integer>> adj) {
    int n = adj.size();
    int[] indeg = new int[n], order = new int[n], g = new int[n];
    for (List<Integer> l : adj) for (int u : l) indeg[u]++;
    int sz = 0;
    for (int v = 0; v < n; v++) if (indeg[v] == 0) order[sz++] = v;
    for (int i = 0; i < sz; i++) for (int u : adj.get(order[i])) if (--indeg[u] == 0) order[sz++] = u;
    for (int i = n - 1; i >= 0; i--) {
        int v = order[i], d = adj.get(v).size();
        boolean[] seen = new boolean[d + 1];
        for (int u : adj.get(v)) if (g[u] <= d) seen[g[u]] = true;
        while (seen[g[v]]) g[v]++;
    }
    return g;
}
```

### 4.2 Brute-force pattern finder skeleton (canonical state + memo)

```cpp
map<vector<int>, int> memoG;
// Grundy value of a multiset of piles under "remove 1..3 from one pile" -- edit moves() for your game
int grundyState(vector<int> s) {
    sort(s.begin(), s.end());                       // canonicalise
    auto it = memoG.find(s);
    if (it != memoG.end()) return it->second;
    set<int> opts;
    for (size_t i = 0; i < s.size(); i++)
        for (int x = 1; x <= 3 && x <= s[i]; x++) { auto t = s; t[i] -= x; opts.insert(grundyState(t)); }
    int m = 0;
    while (opts.count(m)) m++;
    return memoG[s] = m;
}
```

```java
static HashMap<List<Integer>, Integer> memoG = new HashMap<>();

static int grundyState(List<Integer> s0) {
    List<Integer> s = new ArrayList<>(s0);
    Collections.sort(s);
    Integer got = memoG.get(s);
    if (got != null) return got;
    TreeSet<Integer> opts = new TreeSet<>();
    for (int i = 0; i < s.size(); i++)
        for (int x = 1; x <= 3 && x <= s.get(i); x++) {
            List<Integer> t = new ArrayList<>(s);
            t.set(i, t.get(i) - x);
            opts.add(grundyState(t));
        }
    int m = 0;
    while (opts.contains(m)) m++;
    memoG.put(s, m);
    return m;
}
```

Print the values for all small states, compare your conjectured formula against **all** of them.

### 4.3 One-liners: misère Nim, staircase, Moore, Euclid

```cpp
bool misereWins(const vector<long long>& a) {
    long long x = 0; bool big = false; int ones = 0;
    for (long long v : a) { x ^= v; big |= v > 1; ones += v == 1; }
    return big ? x != 0 : ones % 2 == 0;
}
bool staircaseWins(const vector<long long>& step) {           // step[0] = sink
    long long x = 0;
    for (size_t i = 1; i < step.size(); i += 2) x ^= step[i];
    return x != 0;
}
bool mooreWins(const vector<long long>& a, int k) {
    for (int b = 0; b < 62; b++) { int c = 0; for (long long v : a) c += v >> b & 1; if (c % (k + 1)) return true; }
    return false;
}
bool euclidWins(long long a, long long b) {
    if (a < b) swap(a, b);
    if (b == 0) return false;
    if (a == b || a / b >= 2) return true;
    return !euclidWins(b, a - b);
}
```

```java
static boolean misereWins(long[] a) {
    long x = 0; boolean big = false; int ones = 0;
    for (long v : a) { x ^= v; if (v > 1) big = true; if (v == 1) ones++; }
    return big ? x != 0 : ones % 2 == 0;
}
static boolean staircaseWins(long[] step) {
    long x = 0;
    for (int i = 1; i < step.length; i += 2) x ^= step[i];
    return x != 0;
}
static boolean mooreWins(long[] a, int k) {
    for (int b = 0; b < 62; b++) { int c = 0; for (long v : a) c += (int) (v >> b & 1); if (c % (k + 1) != 0) return true; }
    return false;
}
static boolean euclidWins(long a, long b) {
    if (a < b) { long t = a; a = b; b = t; }
    if (b == 0) return false;
    if (a == b || a / b >= 2) return true;
    return !euclidWins(b, a - b);
}
```

### 4.4 Wythoff, exact up to $10^{18}$

```cpp
bool wythoffLosing(unsigned long long a, unsigned long long b) {   // true = P-position
    if (a > b) swap(a, b);
    unsigned long long k = b - a;
    unsigned __int128 t = (unsigned __int128)k * k * 5;
    unsigned long long r = (unsigned long long)sqrtl((long double)t);
    while ((unsigned __int128)r * r > t) r--;
    while ((unsigned __int128)(r + 1) * (r + 1) <= t) r++;
    return a == (unsigned long long)(((unsigned __int128)k + r) / 2);
}
```

```java
static boolean wythoffLosing(long a, long b) {
    if (a > b) { long t = a; a = b; b = t; }
    BigInteger k = BigInteger.valueOf(b - a);
    BigInteger ak = k.add(k.multiply(k).multiply(BigInteger.valueOf(5)).sqrt()).shiftRight(1);
    return ak.equals(BigInteger.valueOf(a));
}
```

### 4.5 Negamax on intervals (Deque / Predict the Winner)

```cpp
long long intervalNegamax(const vector<long long>& a) {      // mover's score minus opponent's
    int n = a.size();
    if (n == 0) return 0;
    vector<long long> dp(a);
    for (int len = 2; len <= n; len++)
        for (int l = 0; l + len - 1 < n; l++) dp[l] = max(a[l] - dp[l + 1], a[l + len - 1] - dp[l]);
    return dp[0];
}
```

```java
static long intervalNegamax(long[] a) {
    int n = a.length;
    if (n == 0) return 0;
    long[] dp = a.clone();
    for (int len = 2; len <= n; len++)
        for (int l = 0; l + len - 1 < n; l++) dp[l] = Math.max(a[l] - dp[l + 1], a[l + len - 1] - dp[l]);
    return dp[0];
}
```

### 4.6 Retrograde BFS: Win / Lose / Draw on any directed graph

```cpp
// res[v]: 1 win, 2 lose, 0 draw for the player to move at v (no moves = lose)
vector<int> retrograde(const vector<vector<int>>& adj) {
    int n = adj.size();
    vector<vector<int>> radj(n);
    vector<int> cnt(n), res(n, 0);
    for (int v = 0; v < n; v++) { cnt[v] = adj[v].size(); for (int u : adj[v]) radj[u].push_back(v); }
    queue<int> q;
    for (int v = 0; v < n; v++) if (!cnt[v]) { res[v] = 2; q.push(v); }
    while (!q.empty()) {
        int u = q.front(); q.pop();
        for (int p : radj[u]) {
            if (res[p]) continue;
            if (res[u] == 2) { res[p] = 1; q.push(p); }
            else if (--cnt[p] == 0) { res[p] = 2; q.push(p); }
        }
    }
    return res;
}
```

```java
static int[] retrograde(List<List<Integer>> adj) {
    int n = adj.size();
    List<List<Integer>> radj = new ArrayList<>();
    for (int i = 0; i < n; i++) radj.add(new ArrayList<>());
    int[] cnt = new int[n], res = new int[n];
    for (int v = 0; v < n; v++) { cnt[v] = adj.get(v).size(); for (int u : adj.get(v)) radj.get(u).add(v); }
    ArrayDeque<Integer> q = new ArrayDeque<>();
    for (int v = 0; v < n; v++) if (cnt[v] == 0) { res[v] = 2; q.add(v); }
    while (!q.isEmpty()) {
        int u = q.poll();
        for (int p : radj.get(u)) {
            if (res[p] != 0) continue;
            if (res[u] == 2) { res[p] = 1; q.add(p); }
            else if (--cnt[p] == 0) { res[p] = 2; q.add(p); }
        }
    }
    return res;
}
```

### 4.7 Green Hackenbush on a rooted tree (parent array, `par[root] = -1`, vertices in BFS order)

```cpp
int hackenbushTree(const vector<int>& bfsOrder, const vector<int>& par) {
    vector<int> g(par.size(), 0);
    for (int i = (int)bfsOrder.size() - 1; i >= 1; i--) { int v = bfsOrder[i]; g[par[v]] ^= g[v] + 1; }
    return g[bfsOrder[0]];
}
```

```java
static int hackenbushTree(int[] bfsOrder, int[] par) {
    int[] g = new int[par.length];
    for (int i = bfsOrder.length - 1; i >= 1; i--) { int v = bfsOrder[i]; g[par[v]] ^= g[v] + 1; }
    return g[bfsOrder[0]];
}
```

## 5. Complexity summary

| Task | Cost |
|---|---|
| W/L or Grundy DP over a DAG | $O(V+E)$ |
| subtraction game up to $N$ | $O(N\lvert S\rvert)$; period via first repeated window of length $s_{\max}$ |
| splitting into two parts up to $N$ | $O(N^2)$ |
| interval negamax | $O(n^2)$ time, $O(n)$ memory (roll by length) |
| bitmask minimax | $O(2^n n)$, $n\le 20$ |
| retrograde BFS | $O(V+E)$ on the reversed graph |
| Wythoff / Euclid / Nim | $O(1)$ / $O(\log V)$ / $O(n)$ |

## 6. Top 10 mistakes

1. Using the turn-free state for a **partisan** game (or forgetting the player in the state).
2. Mixing up **normal and misère** endings — re-read "the player who … wins/loses".
3. XORing raw pile sizes when each pile is a **different game** (apply $g$ per pile first: $\bigoplus (a_i \bmod 4)$).
4. Applying Sprague–Grundy when one move touches **two piles** (Wythoff, Moore) or when the game is **misère**.
5. Trusting a pattern seen on 20 values — Kayles is irregular until 70; check the formula on **every** brute-force value.
6. Floating-point golden ratio for big inputs — use the integer `isqrt(5k^2)` form.
7. Memoised recursion on a **cyclic** state graph — use retrograde BFS; unlabelled = draw.
8. Negamax sign error: `gain - V(next)`, never `+`.
9. Java: `Scanner`, recursion depth on $10^5$-node trees, $O(n^2)$ `long` tables (72 MB at $n=3000$).
10. Interactive: missing flush, debug output on stdout, not reading the judge's final reply.

## 7. Last-minute before contest

- Have the brute-force pattern finder (§4.2) ready in both languages; it takes 3 minutes to adapt.
- For any "who wins" problem: write the brute force **first**, print a 2-D table over two parameters.
- Remember the three-condition proof; use it to check a conjecture in your head before coding.
- Independent parts → XOR of Grundy. Interacting parts → don't.
- "Last mover loses" → misère; "positions repeat" → retrograde BFS; "scores" → negamax.
- Interactive game: decide side by theory, keep the invariant, flush after every move.
- Watch overflow in score games (`long long`) and in Wythoff (`__int128`).
