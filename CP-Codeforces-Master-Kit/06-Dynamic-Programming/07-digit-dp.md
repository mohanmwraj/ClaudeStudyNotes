# Digit DP

> **Band:** 🔵→🟠 1700–2500 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [DP first principles](01-dp-first-principles-and-state-design.md), [modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md)
> **You can say you know this when:** you can count (or sum) the integers in $[L, R]$ with a digit property for $R$ up to $10^{18}$ or a 10 000-digit string; you know why the `tight` flag is correct and why only non-tight states need memoisation; you handle leading zeros deliberately; you can return (count, sum) pairs; and you can run the DP with both bounds at once when subtracting $L-1$ is awkward.

Digit DP answers "how many $x \le N$ have property $P$?" when $N$ is far too large to iterate but $P$ only needs a small amount of information about the digits read so far. It is the purest example of "states are equivalence classes of histories": a history is a prefix of digits, and two prefixes are equivalent when they agree on (a) whether they still equal $N$'s prefix and (b) the few bits of information $P$ needs.

---

## 1. First principles — why this works

### 1.1 From $[L, R]$ to "$\le N$"

Counting is additive over disjoint ranges, so $\#[L,R] = F(R) - F(L-1)$ with $F(N) = \#\{0 \le x \le N : P(x)\}$. (For huge $L$ given as a string, either decrement the string or compute $F(R) - F(L) + [P(L)]$.) Everything below computes $F(N)$.

### 1.2 The decision sequence and the tight flag

Write every $x \le N$ with exactly $\text{len}(N)$ digits, padding with leading zeros. Building $x$ digit by digit from the most significant one, the only constraint from "$x \le N$" is:

- while the prefix of $x$ **equals** the prefix of $N$ (we are *tight*), the next digit can be at most $N$'s next digit;
- the moment we place a smaller digit, $x < N$ is guaranteed and all later digits are free (0–9).

So the constraint needs one bit of memory: `tight`. Every $x \le N$ corresponds to exactly one path: either it equals $N$, or there is a unique first position where it is smaller. That uniqueness is why counting with this scheme never double counts.

### 1.3 What else to remember — the property's state

Ask what the future needs to know about the prefix in order to decide $P$:

| Property | Extra state | Size |
|---|---|---|
| digit sum $\equiv 0 \pmod D$ | prefix digit sum mod $D$ | $D$ |
| $x \equiv 0 \pmod m$ | prefix value mod $m$ ($r \to 10r + d$) | $m$ |
| at most $k$ nonzero digits | count of nonzero digits so far (capped at $k+1$) | $k+2$ |
| all digits distinct | set of digits used | $2^{10}$ |
| at most $k$ distinct digits | set of digits used | $2^{10}$ |
| no two adjacent equal digits | last digit (and "started") | 11 |
| digits non-decreasing | last digit | 10 |
| contains the substring "13" | KMP state of the pattern | $|p|+1$ |
| divisible by each of its non-zero digits | value mod $\text{lcm}(1..9)=2520$, lcm of digits used | $2520 \times 48$ |

The DP state is $(\text{pos}, \text{tight}, \text{started}, \text{extra})$. Time $= \text{len} \times 2 \times 2 \times |\text{extra}| \times 10$.

### 1.4 Leading zeros — the `started` flag

Padding $x$ with leading zeros is harmless for properties that ignore zeros at the front (digit sum, value mod $m$, number of nonzero digits). It is **wrong** for properties where a leading zero would count as a digit: "all digits distinct" (`007` has two zeros, but 7 is fine), "no two adjacent equal", "number of zero digits", "at most $k$ distinct digits". For these, add a flag `started` (have we placed a nonzero digit yet?) and ignore digits while not started. Also decide whether $x = 0$ (the all-zero path, never started) should be counted.

### 1.5 Memoise only the non-tight states — and index by *remaining length*

A tight state can only be reached along one path (the prefix of $N$), so there are at most $\text{len}$ tight states and caching them is pointless. Free (non-tight, started) states are where the repetition is: the number of ways to complete $r$ free digits from extra-state $e$ does not depend on $N$ at all. So:

- memoise $g(r, e)$ = number of ways to fill **$r$ remaining free digits** starting from extra-state $e$;
- because $g$ does not depend on $N$, the same table answers $F(L-1)$, $F(R)$, and every query of a multi-query problem — compute it once (Example 3 answers $10^4$ queries this way).

Keying the memo by *position* instead of remaining length is a classic bug: positions mean different things for $N$ of different lengths, so the memo must be cleared between calls — and forgetting to clear it gives wrong answers on the second call.

### 1.6 The iterative view

Equivalently, enumerate the first position $i$ where $x$ goes below $N$, and the digit $d < N_i$ placed there: the prefix $N_0..N_{i-1}d$ determines the extra-state $e$, and the remaining $\text{len}-1-i$ digits are free, contributing $g(\text{len}-1-i, e)$. Add $[P(N)]$ for $x = N$. This form is handy when $g$ has a closed form (e.g. "at most $k$ nonzero digits in $r$ free positions" $= \sum_{j\le k}\binom{r}{j}9^j$, or "distinct digits": $\frac{(10-|e|)!}{(10-|e|-r)!}$), turning the "DP" into a sum of formulas.

### 1.7 Sums, not just counts

To compute $\sum x$ (or $\sum f(x)$ for additive $f$) over valid $x$, carry a pair $(\text{cnt}, \text{sum})$ per state. Appending digit $d$ at a position with place value $p = 10^{r-1}$ (when $r$ digits remain, including this one) to all completions $(\text{cnt}', \text{sum}')$ of the rest gives

$$\text{cnt} \mathrel{+}= \text{cnt}', \qquad \text{sum} \mathrel{+}= d \cdot p \cdot \text{cnt}' + \text{sum}'.$$

Proof: each of the $\text{cnt}'$ completions $y$ yields the number $d\cdot p + y$. The same trick gives sums of squares (carry $\sum y^2$ too, using $(dp+y)^2$), sums of digit sums, etc. — a vector of moments per state.

### 1.8 Huge $N$ given as a string

When $N$ has $10^4$ digits, the DP is over positions $0..\text{len}$ — just loop over the string. For $L-1$, decrement the decimal string (borrow from the right, strip a leading zero), or use $F(R) - F(L) + [P(L)]$, which needs no arithmetic on big numbers. Everything else is identical; complexity $\text{len} \times |\text{extra}| \times 10$.

### 1.9 Both bounds at once

Instead of $F(R) - F(L-1)$, pad $L$ to the length of $R$ and run one DP with two flags: `lo` (prefix equals $L$'s prefix, so the next digit must be $\ge L_i$) and `hi` (prefix equals $R$'s prefix, next digit $\le R_i$). Valid when the property is checked on the padded representation (careful with leading zeros: if $L$ and $R$ have different lengths, numbers of intermediate lengths have leading zeros, which interacts with `started`). It avoids big-number subtraction and is necessary when the answer is not a difference of prefix counts — e.g. counting **pairs** $(x, y)$ with $x \le A$, $y \le B$ and a bitwise condition, where each number carries its own tight flag.

---

## 2. Formulas, definitions and identities

**Range counting:** $\#\{x\in[L,R]: P\} = F(R) - F(L-1) = F(R) - F(L) + [P(L)]$.

**Tight transition:** from tight state at position $i$, digit $d \le N_i$; new tight $=$ (tight $\wedge\ d = N_i$). From free states, $d\in[0,9]$, stays free.

**Remainder update:** appending digit $d$: $r' = (10r + d) \bmod m$. Digit sum: $s' = (s + d) \bmod D$.

**Free completions (closed forms):**
- digit strings of length $r$ with digit sum $\equiv t$: coefficient extraction from $(1+x+\dots+x^9)^r$ mod $x^D-1$;
- with at most $k$ nonzero digits: $\sum_{j=0}^{k}\binom{r}{j}9^j$;
- with all digits distinct given $u$ used digits: $\frac{(10-u)!}{(10-u-r)!}$ (0 if $u+r > 10$).

**Sum pairs:** $(c, s) \oplus_d (c', s') = (c + c',\ s + d\cdot 10^{r-1}c' + s')$.

**Complexity:** $O(\text{len}\cdot 2^{\#\text{flags}}\cdot|\text{extra}|\cdot B)$ for base $B$; with remaining-length memo shared across $Q$ queries: $O(\text{len}\cdot|\text{extra}|\cdot B + Q\cdot \text{len}\cdot B)$.

**Counts of $k$-digit numbers with all digits distinct:** $9 \cdot \frac{9!}{(10-k)!}$; total for $k \le 10$ is $8\,877\,690$ — there are no such numbers with more than 10 digits.

---

## 3. Implementation (C++ and Java)

A generic memoised template: count $x \in [0, N]$ whose digit sum is divisible by $D$ ($D \le 200$, $N \le 10^{18}$), with the memo keyed by remaining length and shared across calls.

```cpp
struct DigitSumCounter {
    int D;
    vector<vector<long long>> memo;                    // memo[rem][s]: free completions of rem digits from sum s
    explicit DigitSumCounter(int d) : D(d), memo(20, vector<long long>(d, -1)) {}

    long long freeWays(int rem, int s) {               // rem free digits, current sum mod D = s
        if (rem == 0) return s == 0;
        long long& r = memo[rem][s];
        if (r != -1) return r;
        r = 0;
        for (int d = 0; d <= 9; d++) r += freeWays(rem - 1, (s + d) % D);
        return r;
    }

    long long countUpTo(long long N) {                  // x in [0, N] with digit sum % D == 0
        if (N < 0) return 0;
        string s = to_string(N);
        int len = s.size(), sum = 0;
        long long total = 0;
        for (int i = 0; i < len; i++) {                 // first position where x < N
            int lim = s[i] - '0';
            for (int d = 0; d < lim; d++) total += freeWays(len - 1 - i, (sum + d) % D);
            sum = (sum + lim) % D;                      // stay tight
        }
        return total + (sum == 0);                      // x == N itself
    }
};
```

```java
static final class DigitSumCounter {
    final int D;
    final long[][] memo;

    DigitSumCounter(int d) {
        D = d;
        memo = new long[20][d];
        for (long[] row : memo) Arrays.fill(row, -1);
    }

    long freeWays(int rem, int s) {
        if (rem == 0) return s == 0 ? 1 : 0;
        if (memo[rem][s] != -1) return memo[rem][s];
        long r = 0;
        for (int d = 0; d <= 9; d++) r += freeWays(rem - 1, (s + d) % D);
        return memo[rem][s] = r;
    }

    long countUpTo(long N) {
        if (N < 0) return 0;
        String s = Long.toString(N);
        int len = s.length(), sum = 0;
        long total = 0;
        for (int i = 0; i < len; i++) {
            int lim = s.charAt(i) - '0';
            for (int d = 0; d < lim; d++) total += freeWays(len - 1 - i, (sum + d) % D);
            sum = (sum + lim) % D;
        }
        return total + (sum == 0 ? 1 : 0);
    }
}
```

`countUpTo(R) - countUpTo(L - 1)` answers a range; both calls share `memo`. Counts never exceed $10^{18}$, so no modulus is needed here.

---

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "how many integers in $[L, R]$" with $R$ up to $10^{18}$ (or a string of $10^5$ digits) | digit DP |
| property defined by the decimal (or binary) digits | the extra state is what the property needs about a prefix |
| "sum of all such numbers" | carry (count, sum) |
| $T$ up to $10^4$–$10^5$ queries | memo by remaining length, independent of $N$ |
| "$k$-th smallest number with property" | digit DP counts + greedy descent digit by digit |
| pairs $(x, y)$ with bitwise constraint, $x\le A$, $y \le B$ | binary digit DP with a tight flag per number |
| "divisible by its digits", "by the sum of its digits" | fix the target (e.g. the digit sum $S$), run one DP per target |
| property of $x$ and $x+1$ / carries | digit DP from the least significant digit with a carry state |

Often confused with: **pure combinatorics** — if the property only counts digits (e.g. "exactly $k$ ones in binary"), the free part has a closed form and the "DP" is a sum of binomials (§1.6).

---

## 5. Worked examples (graded)

### Example 1 — Digit Sum (huge $K$)  ·  ★ ≈1800 (est.)

- **Source:** [AtCoder DP S · Digit Sum](https://atcoder.jp/contests/dp/tasks/dp_s)
- **Difficulty:** ≈1800 (est.)
- **Problem:** $K < 10^{10000}$ (given as a string) and $D \le 100$. Count $x \in [1, K]$ whose digit sum is a multiple of $D$, mod $10^9+7$.
- **Thinking from first principles:** The future needs the digit sum only mod $D$ and the tight flag: $2D$ states per position, $10^4$ positions, 10 digits — $2\cdot10^7$. Leading zeros don't change the digit sum, so no `started` flag; but the all-zero string ($x = 0$) has digit sum 0 and is counted — subtract 1.

<details><summary>Solution</summary>

Tabulate over positions: `f[s]` = number of free prefixes with sum $\equiv s$, plus one tight prefix with known sum. $O(10\,|K|\,D)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const long long MOD = 1'000'000'007;
    string K;
    int D;
    cin >> K >> D;
    vector<long long> f(D, 0), g(D);                  // f[s]: free prefixes (already < K) with sum s
    int tightSum = 0;                                 // digit sum of the tight prefix (= K's prefix)
    for (char ch : K) {
        int lim = ch - '0';
        fill(g.begin(), g.end(), 0);
        for (int s = 0; s < D; s++) {
            if (!f[s]) continue;
            for (int d = 0; d <= 9; d++) {
                int t = (s + d) % D;
                g[t] = (g[t] + f[s]) % MOD;
            }
        }
        for (int d = 0; d < lim; d++) {               // leave the tight path here
            int t = (tightSum + d) % D;
            g[t] = (g[t] + 1) % MOD;
        }
        tightSum = (tightSum + lim) % D;
        swap(f, g);
    }
    long long ans = (f[0] + (tightSum == 0 ? 1 : 0) - 1 + MOD) % MOD;   // add x = K, remove x = 0
    cout << ans << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        String[] tok = new String(System.in.readAllBytes()).trim().split("\\s+");
        String K = tok[0];
        int D = Integer.parseInt(tok[1]);
        final long MOD = 1_000_000_007L;
        long[] f = new long[D], g = new long[D];
        int tightSum = 0;
        for (int i = 0; i < K.length(); i++) {
            int lim = K.charAt(i) - '0';
            Arrays.fill(g, 0);
            for (int s = 0; s < D; s++) {
                if (f[s] == 0) continue;
                for (int d = 0; d <= 9; d++) {
                    int t = (s + d) % D;
                    g[t] = (g[t] + f[s]) % MOD;
                }
            }
            for (int d = 0; d < lim; d++) {
                int t = (tightSum + d) % D;
                g[t] = (g[t] + 1) % MOD;
            }
            tightSum = (tightSum + lim) % D;
            long[] tmp = f; f = g; g = tmp;
        }
        long ans = (f[0] + (tightSum == 0 ? 1 : 0) - 1 + MOD) % MOD;
        System.out.println(ans);
    }
}
```

</details>

<!-- test
in:
30
4
out:
6
-->
<!-- test
in:
1
1
out:
1
-->
<!-- test
in:
1000000000000000000000
7
out:
149774710
-->

### Example 2 — Numbers with distinct digits  ·  ★ ≈1800 (est.)

- **Source:** Original problem (the range version of [LC 2376 · Count Special Integers](https://leetcode.com/problems/count-special-integers/) — Hard).
- **Difficulty:** ≈1800 (est.)
- **Problem:** Given $1 \le L \le R \le 10^{18}$, count $x \in [L, R]$ whose decimal digits are pairwise distinct.
- **Thinking from first principles:** The future needs the **set** of digits already used (10 bits) — and whether we have started: with padding, `0007` would "use" the digit 0 three times. State $(\text{rem}, \text{mask})$ for free started states; tight and not-started states are few and handled by the recursion. Memo by remaining length so both $F(R)$ and $F(L-1)$ share it.

<details><summary>Solution</summary>

$F(N)$ counts $x \in [1, N]$. Recursive with `(pos, mask, tight, started)`; cache only when `!tight && started`. $O(\text{len}\cdot 2^{10}\cdot 10)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

string s;
long long memo[20][1 << 10];
bool seen[20][1 << 10];

long long go(int pos, int mask, bool tight, bool started) {
    int rem = s.size() - pos;
    if (rem == 0) return started ? 1 : 0;              // x = 0 is not counted
    if (!tight && started && seen[rem][mask]) return memo[rem][mask];
    int lim = tight ? s[pos] - '0' : 9;
    long long res = 0;
    for (int d = 0; d <= lim; d++) {
        bool nt = tight && d == lim;
        if (!started && d == 0) res += go(pos + 1, 0, nt, false);       // still a leading zero
        else if (!(mask >> d & 1)) res += go(pos + 1, mask | 1 << d, nt, true);
    }
    if (!tight && started) { seen[rem][mask] = true; memo[rem][mask] = res; }
    return res;
}

long long F(long long N) {
    if (N <= 0) return 0;
    s = to_string(N);
    return go(0, 0, true, false);
}

int main() {
    long long L, R;
    cin >> L >> R;
    cout << F(R) - F(L - 1) << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static char[] s;
    static long[][] memo = new long[20][1 << 10];
    static boolean[][] seen = new boolean[20][1 << 10];

    static long go(int pos, int mask, boolean tight, boolean started) {
        int rem = s.length - pos;
        if (rem == 0) return started ? 1 : 0;
        if (!tight && started && seen[rem][mask]) return memo[rem][mask];
        int lim = tight ? s[pos] - '0' : 9;
        long res = 0;
        for (int d = 0; d <= lim; d++) {
            boolean nt = tight && d == lim;
            if (!started && d == 0) res += go(pos + 1, 0, nt, false);
            else if ((mask >> d & 1) == 0) res += go(pos + 1, mask | 1 << d, nt, true);
        }
        if (!tight && started) { seen[rem][mask] = true; memo[rem][mask] = res; }
        return res;
    }

    static long F(long N) {
        if (N <= 0) return 0;
        s = Long.toString(N).toCharArray();
        return go(0, 0, true, false);
    }

    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long L = Long.parseLong(st.nextToken()), R = Long.parseLong(st.nextToken());
        System.out.println(F(R) - F(L - 1));
    }
}
```

</details>

<!-- test
in:
1 100
out:
90
-->
<!-- test
in:
123 123
out:
1
-->
<!-- test
in:
11 11
out:
0
-->
<!-- test
in:
1 1000000000000000000
out:
8877690
-->

### Example 3 — Classy Numbers (many queries)  ·  ★ 1900

- **Source:** [CF 1036C · Classy Numbers](https://codeforces.com/problemset/problem/1036/C) — 1900
- **Difficulty:** 1900
- **Problem:** $T \le 10^4$ queries $[L, R]$ with $1 \le L \le R \le 10^{18}$. A number is *classy* if it has at most 3 nonzero digits. Count classy numbers in each range.
- **Thinking from first principles:** Extra state = number of nonzero digits so far (0..3). Leading zeros are zeros — harmless, no `started` needed. The free-completion count $g(r, c)$ = strings of $r$ digits with at most $3-c$ nonzero digits does not depend on $N$: compute once (or use $\sum_{j\le 3-c}\binom{r}{j}9^j$), then each query walks the digits of $L-1$ and $R$ in $O(19\cdot 10)$.

<details><summary>Solution</summary>

Precompute $g(r, c)$ for $r \le 19$, $c \le 3$; iterative "first position below $N$". $O(19\cdot4\cdot10 + T\cdot 19\cdot 10)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

long long g[20][5];                                    // g[r][c]: r free digits, c nonzero used so far

long long F(long long N) {                             // classy x in [0, N]
    if (N < 0) return 0;
    string s = to_string(N);
    int len = s.size(), c = 0;
    long long total = 0;
    for (int i = 0; i < len && c <= 3; i++) {
        int lim = s[i] - '0';
        for (int d = 0; d < lim; d++) {
            int nc = c + (d != 0);
            if (nc <= 3) total += g[len - 1 - i][nc];
        }
        c += lim != 0;
    }
    return total + (c <= 3);                           // N itself
}

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    for (int c = 0; c <= 4; c++) g[0][c] = c <= 3;
    for (int r = 1; r < 20; r++)
        for (int c = 0; c <= 3; c++)
            g[r][c] = g[r - 1][c] + 9 * g[r - 1][min(4, c + 1)];   // place a zero, or one of 9 nonzeros
    int T;
    cin >> T;
    while (T--) {
        long long L, R;
        cin >> L >> R;
        cout << F(R) - F(L - 1) << "\n";
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static long[][] g = new long[20][5];

    static long F(long N) {
        if (N < 0) return 0;
        String s = Long.toString(N);
        int len = s.length(), c = 0;
        long total = 0;
        for (int i = 0; i < len && c <= 3; i++) {
            int lim = s.charAt(i) - '0';
            for (int d = 0; d < lim; d++) {
                int nc = c + (d != 0 ? 1 : 0);
                if (nc <= 3) total += g[len - 1 - i][nc];
            }
            if (lim != 0) c++;
        }
        return total + (c <= 3 ? 1 : 0);
    }

    public static void main(String[] args) throws IOException {
        for (int c = 0; c <= 4; c++) g[0][c] = c <= 3 ? 1 : 0;
        for (int r = 1; r < 20; r++)
            for (int c = 0; c <= 3; c++) g[r][c] = g[r - 1][c] + 9 * g[r - 1][Math.min(4, c + 1)];
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        int T = Integer.parseInt(br.readLine().trim());
        StringBuilder sb = new StringBuilder();
        while (T-- > 0) {
            StringTokenizer st = new StringTokenizer(br.readLine());
            long L = Long.parseLong(st.nextToken()), R = Long.parseLong(st.nextToken());
            sb.append(F(R) - F(L - 1)).append('\n');
        }
        System.out.print(sb);
    }
}
```

</details>

<!-- test
in:
3
1 100
1 2000
12345 12345
out:
100
1271
0
-->
<!-- test
in:
1
1 1000000000000000000
out:
607420
-->

### Example 4 — Magic Numbers (both bounds, huge strings)  ·  ★ 2200

- **Source:** [CF 628D · Magic Numbers](https://codeforces.com/problemset/problem/628/D) — 2200
- **Difficulty:** 2200
- **Problem:** $m \le 2000$, a digit $d$, and two numbers $a \le b$ with the same number of digits (up to 2000, no leading zeros). A number is *$d$-magic* if $d$ appears at every even position (1-indexed from the left) and nowhere else. Count $d$-magic multiples of $m$ in $[a, b]$, mod $10^9+7$.
- **Thinking from first principles:** Extra state = value mod $m$. The bounds are 2000-digit strings, so $a-1$ needs big-number arithmetic — or run both bounds at once: flags `lo` (still equal to $a$'s prefix) and `hi` (still equal to $b$'s prefix). Since $a$ and $b$ have the same length, there are no leading-zero issues: every candidate has exactly that length, and its first digit is $\ge a_0 \ge 1$. Only the free state $(\text{lo}=\text{hi}=0)$ has many remainders; skipping zero entries makes the flagged states cost almost nothing. Positions force the digit (even positions) or forbid one digit (odd positions), so about $9$ digits per step: $2000\cdot 2000 \cdot 9 \approx 3.6\cdot10^7$.

<details><summary>Solution</summary>

`cnt[lo][hi][r]` over positions, push digits allowed by the position rule and by the active bounds. Answer: $\sum_{lo,hi} \text{cnt}[lo][hi][0]$. $O(\text{len}\cdot m\cdot 10)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    const int MOD = 1'000'000'007;
    int m, dg;
    string a, b;
    cin >> m >> dg >> a >> b;
    int len = a.size();
    vector<int> cur(4 * m, 0), nxt(4 * m);            // index (lo * 2 + hi) * m + r
    cur[(1 * 2 + 1) * m + 0] = 1;                     // empty prefix: equal to both bounds
    for (int i = 0; i < len; i++) {
        fill(nxt.begin(), nxt.end(), 0);
        bool even = (i + 1) % 2 == 0;                 // 1-indexed even position
        for (int lo = 0; lo < 2; lo++)
            for (int hi = 0; hi < 2; hi++)
                for (int r = 0; r < m; r++) {
                    int c = cur[(lo * 2 + hi) * m + r];
                    if (!c) continue;
                    int dLo = lo ? a[i] - '0' : 0, dHi = hi ? b[i] - '0' : 9;
                    for (int x = dLo; x <= dHi; x++) {
                        if (even != (x == dg)) continue;   // even position must be d, odd must not
                        int nlo = lo && x == dLo, nhi = hi && x == dHi;
                        int& t = nxt[(nlo * 2 + nhi) * m + (r * 10 + x) % m];
                        t += c;
                        if (t >= MOD) t -= MOD;
                    }
                }
        swap(cur, nxt);
    }
    long long ans = 0;
    for (int f = 0; f < 4; f++) ans += cur[f * m + 0];
    cout << ans % MOD << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        BufferedReader br = new BufferedReader(new InputStreamReader(System.in));
        StringTokenizer st = new StringTokenizer(br.readLine());
        int m = Integer.parseInt(st.nextToken()), dg = Integer.parseInt(st.nextToken());
        String a = br.readLine().trim(), b = br.readLine().trim();
        final int MOD = 1_000_000_007;
        int len = a.length();
        int[] cur = new int[4 * m], nxt = new int[4 * m];
        cur[3 * m] = 1;
        for (int i = 0; i < len; i++) {
            Arrays.fill(nxt, 0);
            boolean even = (i + 1) % 2 == 0;
            for (int lo = 0; lo < 2; lo++)
                for (int hi = 0; hi < 2; hi++)
                    for (int r = 0; r < m; r++) {
                        int c = cur[(lo * 2 + hi) * m + r];
                        if (c == 0) continue;
                        int dLo = lo == 1 ? a.charAt(i) - '0' : 0, dHi = hi == 1 ? b.charAt(i) - '0' : 9;
                        for (int x = dLo; x <= dHi; x++) {
                            if (even != (x == dg)) continue;
                            int nlo = (lo == 1 && x == dLo) ? 1 : 0, nhi = (hi == 1 && x == dHi) ? 1 : 0;
                            int idx = (nlo * 2 + nhi) * m + (r * 10 + x) % m;
                            int t = nxt[idx] + c;
                            nxt[idx] = t >= MOD ? t - MOD : t;
                        }
                    }
            int[] tmp = cur; cur = nxt; nxt = tmp;
        }
        long ans = 0;
        for (int f = 0; f < 4; f++) ans += cur[f * m];
        System.out.println(ans % MOD);
    }
}
```

</details>

<!-- test
in:
3 7
100
999
out:
25
-->
<!-- test
in:
5 0
1
9
out:
1
-->
<!-- test
in:
7 4
1234
5678
out:
5
-->

### Example 5 — Segment Sum (sums, not counts)  ·  ★ 2300

- **Source:** [CF 1073E · Segment Sum](https://codeforces.com/problemset/problem/1073/E) — 2300
- **Difficulty:** 2300
- **Problem:** $1 \le l \le r < 10^{18}$, $1 \le k \le 10$. Sum of all $x \in [l, r]$ that contain at most $k$ distinct digits, mod $998244353$.
- **Thinking from first principles:** Extra state = set of digits used (only after `started` — leading zeros are not digits). We need a sum, so each state returns $(\text{cnt}, \text{sum})$ of its valid completions; placing digit $d$ with $r$ digits remaining (this one included) adds $d\cdot 10^{r-1}$ to each of $\text{cnt}'$ numbers (§1.7). Memo by (remaining length, mask) for free started states. Prune masks with more than $k$ bits immediately.

<details><summary>Solution</summary>

$F(N) = $ sum over valid $x \in [1, N]$; answer $F(r) - F(l-1)$. $O(19\cdot 2^{10}\cdot 10)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

const long long MOD = 998244353;
string s;
int K;
long long pw10[20];
pair<long long, long long> memo[20][1 << 10];
bool seen[20][1 << 10];

pair<long long, long long> go(int pos, int mask, bool tight, bool started) {   // (count, sum)
    if (__builtin_popcount(mask) > K) return {0, 0};
    int rem = s.size() - pos;
    if (rem == 0) return {started ? 1 : 0, 0};
    if (!tight && started && seen[rem][mask]) return memo[rem][mask];
    int lim = tight ? s[pos] - '0' : 9;
    long long cnt = 0, sum = 0;
    for (int d = 0; d <= lim; d++) {
        bool nt = tight && d == lim;
        bool ns = started || d != 0;
        auto [c, sm] = go(pos + 1, ns ? mask | 1 << d : 0, nt, ns);
        cnt = (cnt + c) % MOD;
        sum = (sum + d * pw10[rem - 1] % MOD * c + sm) % MOD;     // digit d at place 10^(rem-1)
    }
    if (!tight && started) { seen[rem][mask] = true; memo[rem][mask] = {cnt, sum}; }
    return {cnt, sum};
}

long long F(long long N) {
    if (N <= 0) return 0;
    s = to_string(N);
    return go(0, 0, true, false).second;
}

int main() {
    long long l, r;
    cin >> l >> r >> K;
    pw10[0] = 1;
    for (int i = 1; i < 20; i++) pw10[i] = pw10[i - 1] * 10 % MOD;
    cout << ((F(r) - F(l - 1)) % MOD + MOD) % MOD << "\n";
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final long MOD = 998244353L;
    static char[] s;
    static int K;
    static long[] pw10 = new long[20];
    static long[][] mc = new long[20][1 << 10], ms = new long[20][1 << 10];
    static boolean[][] seen = new boolean[20][1 << 10];
    static long retC, retS;                            // results of go() (avoids allocating pairs)

    static void go(int pos, int mask, boolean tight, boolean started) {
        if (Integer.bitCount(mask) > K) { retC = 0; retS = 0; return; }
        int rem = s.length - pos;
        if (rem == 0) { retC = started ? 1 : 0; retS = 0; return; }
        if (!tight && started && seen[rem][mask]) { retC = mc[rem][mask]; retS = ms[rem][mask]; return; }
        int lim = tight ? s[pos] - '0' : 9;
        long cnt = 0, sum = 0;
        for (int d = 0; d <= lim; d++) {
            boolean nt = tight && d == lim;
            boolean ns = started || d != 0;
            go(pos + 1, ns ? mask | 1 << d : 0, nt, ns);
            cnt = (cnt + retC) % MOD;
            sum = (sum + d * pw10[rem - 1] % MOD * retC + retS) % MOD;
        }
        if (!tight && started) { seen[rem][mask] = true; mc[rem][mask] = cnt; ms[rem][mask] = sum; }
        retC = cnt; retS = sum;
    }

    static long F(long N) {
        if (N <= 0) return 0;
        s = Long.toString(N).toCharArray();
        go(0, 0, true, false);
        return retS;
    }

    public static void main(String[] args) throws IOException {
        StringTokenizer st = new StringTokenizer(new BufferedReader(new InputStreamReader(System.in)).readLine());
        long l = Long.parseLong(st.nextToken()), r = Long.parseLong(st.nextToken());
        K = Integer.parseInt(st.nextToken());
        pw10[0] = 1;
        for (int i = 1; i < 20; i++) pw10[i] = pw10[i - 1] * 10 % MOD;
        System.out.println(((F(r) - F(l - 1)) % MOD + MOD) % MOD);
    }
}
```

</details>

<!-- test
in:
100 200 1
out:
111
-->
<!-- test
in:
101 120 2
out:
1246
-->
<!-- test
in:
1 1000000000000000000 10
out:
75433847
-->

---

## 6. Tricks, pitfalls and things to remember

1. **$F(L-1)$ with $L = 0$ or $1$:** make $F$ of a negative argument return 0, and decide whether $x = 0$ is counted (Examples 1, 2, 5 exclude it explicitly).
2. **Memo keyed by position** is only valid for one $N$; key by **remaining length** to share across calls, or clear the memo between calls.
3. **Never memoise tight states** in a shared memo — their value depends on $N$'s remaining digits.
4. **Leading zeros:** use `started` whenever a leading zero would be mistaken for a real digit (distinct digits, digit sets, adjacency constraints, counting zeros).
5. **`started` resets the mask:** while not started, pass mask 0 — don't record digit 0 (Example 5).
6. **Remainder update** is $(10r + d) \bmod m$, not $(r + d\cdot10^{\text{pos}})$ — the latter needs the place value and is easy to get wrong.
7. **Big strings:** never convert to `long long`; iterate characters. For $L-1$ use $F(R)-F(L)+[P(L)]$ or a careful string decrement (`"1000" → "999"`).
8. **Sums mod $p$:** multiply $d \cdot 10^{r-1} \bmod p$ by the count *after* reducing; $d\cdot 10^{18}$ overflows.
9. **Both-bounds DP:** works cleanly when $L$ and $R$ have the same length; otherwise pad $L$ with zeros *and* track `started`, or fall back to $F(R) - F(L-1)$.
10. **Java recursion depth** is only $\text{len} \le 20$ for 64-bit inputs — fine; for $10^4$-digit strings use the iterative form (Example 1, Example 4).
11. **Speed:** skip zero entries in tabulated digit DPs (Example 4) — flagged states are sparse.
12. **Divisibility by digits:** use $\text{lcm}(1..9) = 2520$ for the value mod and the lcm of used digits (48 divisors of 2520) as extra state (CF 55D).

---

## 7. Going further (toward 2400–2600+)

- **CF 55D (*Beautiful numbers*)** — divisible by all nonzero digits: state (value mod 2520, index of lcm among 48 divisors), $19\cdot 2520\cdot 48 \cdot 10 \approx 2.3\cdot10^7$, shared across test cases.
- **$k$-th number with a property** — compute free-completion counts, then descend: at each position choose the smallest digit whose completion count is $\ge k$, subtracting skipped counts.
- **Digit DP on two numbers** — count pairs $(x,y)$, $x \le A$, $y \le B$ with $x \,\&\, y = 0$ or $x \oplus y \le C$: binary digits, one tight flag per bound (up to $2^3$ flag combinations).
- **Least-significant-first digit DP with carries** — properties of $x + c$ or $x \cdot c$ digit by digit ("how many $x$ have digit sum of $x$ equal to digit sum of $2x$"): state = carry.
- **Digit DP + automaton** — "contains one of these patterns": the extra state is the Aho–Corasick node ([Aho–Corasick](../11-Strings/06-aho-corasick.md)).
- **Digit sums of all numbers up to $N$ in base $b$** — closed forms via the contribution technique ([contribution](../05-Combinatorics-and-Probability/07-contribution-technique.md)).

---

## 8. Practice ladder

**≤ 1900**
- [ ] [CF 1926C · Vlad and a Sum of Sum of Digits](https://codeforces.com/problemset/problem/1926/C) — 1200 — warm-up (precompute)
- [ ] [AtCoder DP S · Digit Sum](https://atcoder.jp/contests/dp/tasks/dp_s)
- [ ] [AtCoder ABC135 D · Digits Parade](https://atcoder.jp/contests/abc135/tasks/abc135_d) — ≈1300 (AtCoder est.) — remainders with wildcards
- [ ] [CSES 2220 · Counting Numbers](https://cses.fi/problemset/task/2220) — no two adjacent equal digits: `started` + last digit
- [ ] [CF 914C · Travelling Salesman and Special Numbers](https://codeforces.com/problemset/problem/914/C) — 1800
- [ ] [CF 1036C · Classy Numbers](https://codeforces.com/problemset/problem/1036/C) — 1900
- [ ] [CF 258B · Little Elephant and Elections](https://codeforces.com/problemset/problem/258/B) — 1900

**2000–2300**
- [ ] [AtCoder ABC208 E · Digit Products](https://atcoder.jp/contests/abc208/tasks/abc208_e) — ≈2000 (AtCoder est.) — state = product (few distinct values)
- [ ] [AtCoder ABC235 F · Variety of Digits](https://atcoder.jp/contests/abc235/tasks/abc235_f) — ≈2100 (AtCoder est.) — (count, sum) with a digit mask
- [ ] [CF 628D · Magic Numbers](https://codeforces.com/problemset/problem/628/D) — 2200
- [ ] [CF 1073E · Segment Sum](https://codeforces.com/problemset/problem/1073/E) — 2300

**2400+**
- [ ] [CF 55D · Beautiful numbers](https://codeforces.com/problemset/problem/55/D) — 2500

---

## 9. LeetCode / FAANG cross-reference

- [LC 233 · Number of Digit One](https://leetcode.com/problems/number-of-digit-one/) — Hard — count digit 1 over $[1,N]$: carry (count, number of ones).
- [LC 902 · Numbers At Most N Given Digit Set](https://leetcode.com/problems/numbers-at-most-n-given-digit-set/) — Hard — tight flag with a restricted digit set; shorter lengths by formula.
- [LC 1012 · Numbers With Repeated Digits](https://leetcode.com/problems/numbers-with-repeated-digits/) — Hard — complement of Example 2.
- [LC 2376 · Count Special Integers](https://leetcode.com/problems/count-special-integers/) — Hard — Example 2 with $L = 1$.
- [LC 357 · Count Numbers with Unique Digits](https://leetcode.com/problems/count-numbers-with-unique-digits/) — Medium — the closed form $9\cdot 9\cdot 8\cdots$.
- [LC 600 · Non-negative Integers without Consecutive Ones](https://leetcode.com/problems/non-negative-integers-without-consecutive-ones/) — Hard — binary digit DP with "last bit"; free part is Fibonacci.
- [LC 2719 · Count of Integers](https://leetcode.com/problems/count-of-integers/) — Hard — digit-sum window on huge strings: $F(R) - F(L) + [P(L)]$.

Rare in interviews except at companies that like "hard" counting questions; when it appears, the expected answer is the memoised `(pos, tight, …)` recursion.

---

## 10. Self-check

1. Why does every $x \le N$ correspond to exactly one path of the tight/free DP?
2. Why is memoising only non-tight states enough, and why should the memo be keyed by remaining length?
3. Give two properties that need a `started` flag and one that does not.
4. How do you compute $F(L-1)$ when $L$ has 5000 digits?
5. Derive the sum-update rule for appending digit $d$.
6. What is the state for "divisible by all its nonzero digits", and how large is it?
7. When is the two-flag (both bounds) DP preferable to $F(R) - F(L-1)$?

<details><summary>Answers</summary>

1. Either $x = N$ (the all-tight path), or there is a unique first position where $x$'s digit is smaller than $N$'s; the path is tight before it, takes that smaller digit, and is free afterwards.
2. Tight states lie on a single path (at most len of them), so caching them saves nothing. Free completions depend only on the number of remaining digits and the extra state — not on $N$ — so keying by remaining length makes them reusable across different $N$ and queries.
3. Need it: all digits distinct; no two adjacent equal digits (also "count zeros", "at most $k$ distinct digits"). Don't: digit sum mod $D$ (leading zeros add 0).
4. Use $F(R) - F(L) + [P(L)]$, or decrement the string by borrowing from the right (and strip a new leading zero).
5. Each of the $\text{cnt}'$ completions $y$ of the remaining $r-1$ digits becomes $d\cdot10^{r-1}+y$; summing gives $d\cdot 10^{r-1}\text{cnt}' + \text{sum}'$.
6. (value mod 2520, lcm of the digits used so far — one of the 48 divisors of 2520), plus position and tight: about $19\times2520\times48$ free states.
7. When $L$ is a huge string (no easy decrement), when the property is checked on fixed-length representations, or when several numbers are bounded simultaneously (pairs $(x,y)$).

</details>
