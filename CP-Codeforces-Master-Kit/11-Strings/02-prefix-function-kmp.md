# Prefix function and KMP

> **Band:** 🔵 1500–2100 · **Priority:** 🔥 · **FAANG:** medium · **Prerequisites:** [complexity and amortised analysis](../01-Foundations/01-complexity-and-constraint-reading.md), [DP state design](../06-Dynamic-Programming/01-dp-first-principles-and-state-design.md) (for the automaton DP)
> **You can say you know this when:** you can write the prefix function and the online matcher without looking, prove the $O(n)$ bound, read borders/periods/occurrence counts straight off $\pi$, and build the KMP automaton to run a DP over "strings that avoid / contain a pattern".

## 1. First principles — why this works

**Definitions.** A *border* of a string $u$ is a string that is both a proper prefix and a proper suffix of $u$ ("ab" is a border of "abcab"). The **prefix function** of $s$ is

$$\pi[i] = \text{length of the longest border of } s[0..i] \qquad (\pi[0] = 0).$$

**The naive way.** For each $i$ try every length $k \le i$ and compare $s[0..k)$ with $s[i-k+1..i]$: $O(n^3)$, or $O(n^2)$ with hashing. We want $O(n)$, deterministic.

**Observation 1 — $\pi$ grows by at most one.** If $s[0..i]$ has a border of length $k$, then dropping the last character gives a border of $s[0..i-1]$ of length $k-1$. Hence $\pi[i] \le \pi[i-1] + 1$, and $\pi[i] = \pi[i-1]+1$ exactly when the character after the old border matches: $s[\pi[i-1]] = s[i]$.

**Observation 2 — the borders form a chain.** A border of a border is a border (prefix of a prefix, suffix of a suffix). Conversely, every border of $u$ shorter than its longest border $b$ is a border of $b$ (it is a prefix of $u$ shorter than $b$, so a prefix of $b$; it is a suffix of $u$ shorter than $b$, so a suffix of $b$). So **all** borders of $s[0..i]$ are

$$\pi[i] > \pi[\pi[i]-1] > \pi[\pi[\pi[i]-1]-1] > \dots > 0.$$

**The algorithm.** To compute $\pi[i]$: the candidates are (border of $s[0..i-1]$) + $s[i]$, longest first. Walk the chain of $s[0..i-1]$: $k = \pi[i-1]$; while $k > 0$ and $s[k] \ne s[i]$, set $k = \pi[k-1]$. Then if $s[k] = s[i]$, $k$ increases by one. That is $\pi[i]$.

**Why $O(n)$ (amortised).** Track the value $k$. Each step of $i$ increases it by at most 1, so the total increase over the run is $\le n$. Every iteration of the `while` loop strictly decreases $k$, and $k \ge 0$. Total decreases $\le$ total increases $\le n$. So the whole loop executes at most $2n$ comparisons.

**Pattern matching.** Run the same recurrence on $p + \# + t$ with a separator $\#$ that occurs in neither: no border can cross $\#$, so $\pi \le |p|$ everywhere, and $\pi[i] = |p|$ exactly at the positions where an occurrence of $p$ ends. Without building the concatenation: keep $k$ = length of the longest prefix of $p$ that is a suffix of the text read so far, and update it with $p$'s prefix function. That *online* form is KMP (Knuth–Morris–Pratt): $O(|p| + |t|)$ time, $O(|p|)$ memory, one pass over the text.

**The automaton view.** The state "$k$ characters of $p$ matched" plus the next character determine the next state. Precomputing that table $\delta(k, c)$ turns KMP into a DFA with $|p|+1$ states — exactly what a DP over "strings that do or do not contain $p$" needs.

## 2. Formulas, definitions and identities

| Fact | Statement | Why |
|---|---|---|
| growth | $\pi[i] \le \pi[i-1] + 1$ | drop the last character of a border |
| border chain | borders of $s[0..i]$ are $\pi[i], \pi^{(2)}[i], \dots$ where $\pi^{(j+1)} = \pi[\pi^{(j)}-1]$ | border of a border is a border, and conversely |
| matching | $\pi_{p\#t}[i] = \lvert p\rvert \iff p$ ends at position $i - 2\lvert p\rvert$ of $t$ | separator stops borders from crossing |
| period ↔ border | $q$ is a period of $s$ (i.e. $s_i = s_{i+q}$ for all valid $i$) $\iff$ $s$ has a border of length $n - q$ | shift by $q$ overlays the prefix of length $n-q$ on the suffix |
| smallest period | $q_{\min} = n - \pi[n-1]$ | longest border ↔ shortest period |
| power test | $s = u^k$ with $k \ge 2$ $\iff$ $\pi[n-1] > 0$ and $q_{\min} \mid n$ | see self-check 5 |
| all periods | $\{\, n - b : b \text{ a border}\,\} \cup \{n\}$ | from period ↔ border |
| Fine–Wilf | if $p, q$ are periods and $p + q - \gcd(p,q) \le n$, then $\gcd(p,q)$ is a period | (classical; used to prove periodicity lemmas) |
| prefix occurrences | the prefixes ending at position $i$ are exactly the chain from $i+1$: $i+1, \pi[i], \pi^{(2)}[i], \dots$ | so counting occurrences of every prefix is a sum along chains |
| automaton | $\delta(k, c) = k+1$ if $k < m$ and $p_k = c$; else $\delta(\pi[k-1], c)$ for $k>0$; $\delta(0,c) = 0$ | first mismatching state falls back along the chain |

**Complexities.** Prefix function $O(n)$ time and memory. Online matching $O(|p| + |t|)$ time, $O(|p|)$ memory. All occurrence counts of all prefixes $O(n)$. Automaton $O(m\,\Sigma)$ time and memory. Automaton DP over strings of length $N$: $O(N\, m\, \Sigma)$.

**Counting occurrences of every prefix.** Let $c[j]$ be the number of positions $i$ at which the prefix of length $j$ ends. Start with $c[\pi[i]] \mathrel{+}= 1$ for every $i$ (the longest proper border ending at $i$), push counts down the chains from long to short: for $j = n-1, \dots, 1$, $c[\pi[j-1]] \mathrel{+}= c[j]$; finally add 1 to each $c[j]$ for the prefix itself ending at index $j-1$. $O(n)$.

## 3. Implementation (C++ and Java)

### 3.1 Prefix function and online matching

Driver: read text $t$ then pattern $p$; print the number of occurrences, then their 0-indexed starting positions on one line.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> prefix_function(const string& s) {
    int n = s.size();
    vector<int> pi(n, 0);
    for (int i = 1; i < n; i++) {
        int k = pi[i - 1];
        while (k > 0 && s[i] != s[k]) k = pi[k - 1];   // fall back along the border chain
        if (s[i] == s[k]) k++;
        pi[i] = k;
    }
    return pi;
}

vector<int> find_all(const string& t, const string& p) {   // KMP, online over t
    vector<int> pi = prefix_function(p), res;
    int m = p.size(), k = 0;
    for (int i = 0; i < (int)t.size(); i++) {
        while (k > 0 && (k == m || t[i] != p[k])) k = pi[k - 1];
        if (t[i] == p[k]) k++;
        if (k == m) res.push_back(i - m + 1);
    }
    return res;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string t, p;
    cin >> t >> p;
    vector<int> occ = find_all(t, p);
    cout << occ.size() << '\n';
    for (size_t i = 0; i < occ.size(); i++) cout << occ[i] << (i + 1 < occ.size() ? ' ' : '\n');
    if (occ.empty()) cout << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] prefixFunction(char[] s) {
        int n = s.length;
        int[] pi = new int[n];
        for (int i = 1; i < n; i++) {
            int k = pi[i - 1];
            while (k > 0 && s[i] != s[k]) k = pi[k - 1];
            if (s[i] == s[k]) k++;
            pi[i] = k;
        }
        return pi;
    }

    static int[] findAll(char[] t, char[] p) {
        int[] pi = prefixFunction(p);
        int m = p.length, k = 0, cnt = 0;
        int[] res = new int[Math.max(0, t.length - m + 1)];
        for (int i = 0; i < t.length; i++) {
            while (k > 0 && (k == m || t[i] != p[k])) k = pi[k - 1];
            if (t[i] == p[k]) k++;
            if (k == m) res[cnt++] = i - m + 1;
        }
        return Arrays.copyOf(res, cnt);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] t = in.next().toCharArray(), p = in.next().toCharArray();
        int[] occ = findAll(t, p);
        out.println(occ.length);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < occ.length; i++) { if (i > 0) sb.append(' '); sb.append(occ[i]); }
        out.println(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
abababa
aba
out:
3
0 2 4
-->
<!-- test
in:
aaaaa
aaaaa
out:
1
0
-->
<!-- test
in:
abc
abcd
out:
0
-->

### 3.2 Everything you can read off $\pi$: occurrence counts of every prefix, period, power test

Driver: read $s$; print $\pi$; print, for $j = 1..n$, the number of occurrences of the prefix of length $j$; print the smallest period and `1` if $s$ is a power $u^k$ ($k \ge 2$), else `0`.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> prefix_function(const string& s) {
    int n = s.size();
    vector<int> pi(n, 0);
    for (int i = 1; i < n; i++) {
        int k = pi[i - 1];
        while (k > 0 && s[i] != s[k]) k = pi[k - 1];
        if (s[i] == s[k]) k++;
        pi[i] = k;
    }
    return pi;
}

vector<long long> prefix_occurrences(const vector<int>& pi) {   // cnt[j] for j = 1..n
    int n = pi.size();
    vector<long long> cnt(n + 1, 0);
    for (int i = 0; i < n; i++) cnt[pi[i]]++;              // longest proper border ending at i
    for (int j = n - 1; j > 0; j--) cnt[pi[j - 1]] += cnt[j]; // push down the chain, long to short
    for (int j = 1; j <= n; j++) cnt[j]++;                 // the prefix itself
    return cnt;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size();
    vector<int> pi = prefix_function(s);
    vector<long long> cnt = prefix_occurrences(pi);
    for (int i = 0; i < n; i++) cout << pi[i] << (i + 1 < n ? ' ' : '\n');
    for (int j = 1; j <= n; j++) cout << cnt[j] << (j < n ? ' ' : '\n');
    int per = n - pi[n - 1];
    cout << per << ' ' << (pi[n - 1] > 0 && n % per == 0 ? 1 : 0) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] prefixFunction(char[] s) {
        int n = s.length;
        int[] pi = new int[n];
        for (int i = 1; i < n; i++) {
            int k = pi[i - 1];
            while (k > 0 && s[i] != s[k]) k = pi[k - 1];
            if (s[i] == s[k]) k++;
            pi[i] = k;
        }
        return pi;
    }

    static long[] prefixOccurrences(int[] pi) {
        int n = pi.length;
        long[] cnt = new long[n + 1];
        for (int i = 0; i < n; i++) cnt[pi[i]]++;
        for (int j = n - 1; j > 0; j--) cnt[pi[j - 1]] += cnt[j];
        for (int j = 1; j <= n; j++) cnt[j]++;
        return cnt;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] s = in.next().toCharArray();
        int n = s.length;
        int[] pi = prefixFunction(s);
        long[] cnt = prefixOccurrences(pi);
        StringBuilder a = new StringBuilder(), b = new StringBuilder();
        for (int i = 0; i < n; i++) { if (i > 0) a.append(' '); a.append(pi[i]); }
        for (int j = 1; j <= n; j++) { if (j > 1) b.append(' '); b.append(cnt[j]); }
        out.println(a); out.println(b);
        int per = n - pi[n - 1];
        out.println(per + " " + (pi[n - 1] > 0 && n % per == 0 ? 1 : 0));
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
abacaba
out:
0 0 1 0 1 2 3
4 2 2 1 1 1 1
4 0
-->
<!-- test
in:
abab
out:
0 0 1 2
2 2 1 1
2 1
-->
<!-- test
in:
z
out:
0
1
1 0
-->

### 3.3 KMP automaton

$\delta(k, c)$ for states $k = 0..m$ (state $m$ = "just matched the whole pattern"). Lowercase alphabet here; change `SIGMA` and the offset for other alphabets.

```cpp
vector<array<int, 26>> kmp_automaton(const string& p) {
    int m = p.size();
    vector<int> pi(m, 0);
    for (int i = 1; i < m; i++) {
        int k = pi[i - 1];
        while (k > 0 && p[i] != p[k]) k = pi[k - 1];
        if (p[i] == p[k]) k++;
        pi[i] = k;
    }
    vector<array<int, 26>> d(m + 1);
    for (int k = 0; k <= m; k++)
        for (int c = 0; c < 26; c++) {
            if (k < m && p[k] - 'a' == c) d[k][c] = k + 1;
            else d[k][c] = k == 0 ? 0 : d[pi[k - 1]][c];   // pi[k-1] < k: already filled
        }
    return d;
}
```

```java
static int[][] kmpAutomaton(char[] p) {
    final int SIGMA = 26;
    int m = p.length;
    int[] pi = new int[m];
    for (int i = 1; i < m; i++) {
        int k = pi[i - 1];
        while (k > 0 && p[i] != p[k]) k = pi[k - 1];
        if (p[i] == p[k]) k++;
        pi[i] = k;
    }
    int[][] d = new int[m + 1][SIGMA];
    for (int k = 0; k <= m; k++)
        for (int c = 0; c < SIGMA; c++) {
            if (k < m && p[k] - 'a' == c) d[k][c] = k + 1;
            else d[k][c] = k == 0 ? 0 : d[pi[k - 1]][c];
        }
    return d;
}
```

### 3.4 Matching through the concatenation $p\#t$

The offline form: one prefix function over $p + \# + t$; an occurrence ends wherever $\pi = |p|$. Costs $O(|p|+|t|)$ memory but needs no separate matcher. `sep` must occur in neither string.

```cpp
vector<int> find_all_concat(const string& t, const string& p, char sep = '#') {
    string s = p + sep + t;
    int n = s.size(), m = p.size();
    vector<int> pi(n, 0), res;
    for (int i = 1; i < n; i++) {
        int k = pi[i - 1];
        while (k > 0 && s[i] != s[k]) k = pi[k - 1];
        if (s[i] == s[k]) k++;
        pi[i] = k;
        if (k == m) res.push_back(i - 2 * m);       // start index in t
    }
    return res;
}
```

```java
static int[] findAllConcat(String t, String p, char sep) {
    char[] s = (p + sep + t).toCharArray();
    int n = s.length, m = p.length(), cnt = 0;
    int[] pi = new int[n], res = new int[Math.max(0, t.length() - m + 1)];
    for (int i = 1; i < n; i++) {
        int k = pi[i - 1];
        while (k > 0 && s[i] != s[k]) k = pi[k - 1];
        if (s[i] == s[k]) k++;
        pi[i] = k;
        if (k == m) res[cnt++] = i - 2 * m;
    }
    return Arrays.copyOf(res, cnt);
}
```

## 4. Recognising the pattern

- **"Borders", "prefix that is also a suffix", "period", "the string is a repetition of"** → $\pi[n-1]$ and its chain.
- **One pattern, one text, all occurrences**, especially with $|t|$ up to $10^6$ or streamed input → KMP (deterministic, no hashing risk).
- **"How many times does each prefix occur"** → chain sums over $\pi$ (§2).
- **Counting / optimising over strings that must (not) contain a pattern** → DP over (position, automaton state). With many patterns that becomes [Aho–Corasick](06-aho-corasick.md).
- **Merging strings with maximal overlap** → $\pi$ of `next + '#' + tail(current)`.
- **Confused with**: the [Z-function](03-z-function.md) (same power, different shape: $z[i]$ is "prefix match *starting* at $i$", $\pi[i]$ is "prefix match *ending* at $i$" — they convert into each other); [hashing](01-string-hashing.md) (handles arbitrary substring pairs but is probabilistic).

## 5. Worked examples (graded)

### Example 1 — Finding Borders · ★ ≈1300 (est.)

- **Source:** [CSES 1732 · Finding Borders](https://cses.fi/problemset/task/1732)
- **Difficulty:** ≈1300 (est.)
- **Problem:** $|s| \le 10^6$. Print the lengths of all borders of $s$ in increasing order.
- **Thinking from first principles:** the borders of $s$ are *exactly* the chain $\pi[n-1], \pi[\pi[n-1]-1], \dots$ (Observation 2). Walk it, collect, reverse.

<details><summary>Solution</summary>

$O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size();
    vector<int> pi(n, 0);
    for (int i = 1; i < n; i++) {
        int k = pi[i - 1];
        while (k > 0 && s[i] != s[k]) k = pi[k - 1];
        if (s[i] == s[k]) k++;
        pi[i] = k;
    }
    vector<int> b;
    for (int k = pi[n - 1]; k > 0; k = pi[k - 1]) b.push_back(k);
    reverse(b.begin(), b.end());
    for (size_t i = 0; i < b.size(); i++) cout << b[i] << (i + 1 < b.size() ? ' ' : '\n');
    if (b.empty()) cout << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] s = in.next().toCharArray();
        int n = s.length;
        int[] pi = new int[n];
        for (int i = 1; i < n; i++) {
            int k = pi[i - 1];
            while (k > 0 && s[i] != s[k]) k = pi[k - 1];
            if (s[i] == s[k]) k++;
            pi[i] = k;
        }
        int[] b = new int[n];
        int c = 0;
        for (int k = pi[n - 1]; k > 0; k = pi[k - 1]) b[c++] = k;
        StringBuilder sb = new StringBuilder();
        for (int i = c - 1; i >= 0; i--) { sb.append(b[i]); if (i > 0) sb.append(' '); }
        out.println(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
abcababcab
out:
2 5
-->
<!-- test
in:
aaaa
out:
1 2 3
-->
<!-- test
in:
a
out:
-->

</details>

### Example 2 — Finding Periods · ★ ≈1500 (est.)

- **Source:** [CSES 1733 · Finding Periods](https://cses.fi/problemset/task/1733)
- **Difficulty:** ≈1500 (est.)
- **Problem:** a *period* of $s$ is a prefix $u$ such that $s$ is a prefix of $uuu\dots$. Print the lengths of all periods in increasing order ($|s| \le 10^6$).
- **Thinking from first principles:** "$s$ is a prefix of $u^\infty$" with $|u| = q$ is exactly "$s_i = s_{i+q}$ for all valid $i$", i.e. shifting by $q$ overlays the prefix of length $n-q$ on the suffix of length $n-q$: a border of length $n-q$. So the periods are $n - b$ for every border $b$, plus $n$ itself. The border chain is decreasing, so $n - b$ comes out increasing.

<details><summary>Solution</summary>

$O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size();
    vector<int> pi(n, 0);
    for (int i = 1; i < n; i++) {
        int k = pi[i - 1];
        while (k > 0 && s[i] != s[k]) k = pi[k - 1];
        if (s[i] == s[k]) k++;
        pi[i] = k;
    }
    string out;
    for (int k = pi[n - 1]; k > 0; k = pi[k - 1]) out += to_string(n - k) + ' ';
    out += to_string(n);
    cout << out << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] s = in.next().toCharArray();
        int n = s.length;
        int[] pi = new int[n];
        for (int i = 1; i < n; i++) {
            int k = pi[i - 1];
            while (k > 0 && s[i] != s[k]) k = pi[k - 1];
            if (s[i] == s[k]) k++;
            pi[i] = k;
        }
        StringBuilder sb = new StringBuilder();
        for (int k = pi[n - 1]; k > 0; k = pi[k - 1]) sb.append(n - k).append(' ');
        sb.append(n);
        out.println(sb);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
abcabca
out:
3 6 7
-->
<!-- test
in:
aaa
out:
1 2 3
-->
<!-- test
in:
ab
out:
2
-->

</details>

### Example 3 — Password · ★ 1700

- **Source:** [CF 126B · Password](https://codeforces.com/problemset/problem/126/B) — 1700
- **Difficulty:** 1700
- **Problem:** $|s| \le 10^6$. Find the longest substring that is a prefix of $s$, a suffix of $s$, and also occurs somewhere strictly inside (neither as the prefix nor as the suffix occurrence). Print it, or `Just a legend`.
- **Thinking from first principles:** prefix-and-suffix means "border", so the candidates are the border chain of $s$, longest first. A border of length $b$ also occurs in the middle iff some $\pi[i] \ge b$ with $i \le n-2$: then the prefix of length $\pi[i]$ ends at $i$, and its first $b$ characters form an occurrence that starts at $i - \pi[i] + 1 \ge 1$ and ends before $n-1$. So test $b_1 = \pi[n-1]$ against $\max_{i \le n-2}\pi[i]$. If it fails, the next candidate $b_2 = \pi[b_1 - 1]$ *always* succeeds when non-zero: it is a border of the prefix of length $b_1$, so it ends at index $b_1 - 1 < n-1$ and starts at $b_1 - b_2 > 0$. Hence at most two candidates are ever checked — a solver who loops over the whole chain still passes, but the two-candidate argument is the insight.

<details><summary>Solution</summary>

$O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size();
    vector<int> pi(n, 0);
    for (int i = 1; i < n; i++) {
        int k = pi[i - 1];
        while (k > 0 && s[i] != s[k]) k = pi[k - 1];
        if (s[i] == s[k]) k++;
        pi[i] = k;
    }
    int b = pi[n - 1], inner = 0;
    for (int i = 0; i + 1 < n; i++) inner = max(inner, pi[i]);
    int ans = 0;
    if (b > 0 && inner >= b) ans = b;
    else if (b > 0) ans = pi[b - 1];                    // border of the border: always occurs inside
    if (ans == 0) cout << "Just a legend\n";
    else cout << s.substr(0, ans) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String str = in.next();
        char[] s = str.toCharArray();
        int n = s.length;
        int[] pi = new int[n];
        for (int i = 1; i < n; i++) {
            int k = pi[i - 1];
            while (k > 0 && s[i] != s[k]) k = pi[k - 1];
            if (s[i] == s[k]) k++;
            pi[i] = k;
        }
        int b = pi[n - 1], inner = 0;
        for (int i = 0; i + 1 < n; i++) inner = Math.max(inner, pi[i]);
        int ans = 0;
        if (b > 0 && inner >= b) ans = b;
        else if (b > 0) ans = pi[b - 1];
        out.println(ans == 0 ? "Just a legend" : str.substring(0, ans));
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
fixprefixsuffix
out:
fix
-->
<!-- test
in:
abcdabc
out:
Just a legend
-->
<!-- test
in:
aaaa
out:
aa
-->
<!-- test
in:
a
out:
Just a legend
-->

</details>

### Example 4 — Prefixes and Suffixes · ★ 2000

- **Source:** [CF 432D · Prefixes and Suffixes](https://codeforces.com/problemset/problem/432/D) — 2000
- **Difficulty:** 2000
- **Problem:** $|s| \le 10^5$ (uppercase letters). For every prefix that is also a suffix (including $s$ itself), print its length and its number of occurrences in $s$ as a substring, in increasing order of length; first print how many such prefixes there are.
- **Thinking from first principles:** two sub-questions, both answered by $\pi$. (a) Which prefixes are suffixes? The border chain of $s$, plus $s$. (b) How often does each prefix occur? The chain-sum counting of §2: the prefixes that end at position $i$ are exactly the chain from $i+1$, so push counts from long prefixes to short ones. Dead end: running KMP once per border is $O(n \cdot \#\text{borders})$, which is $O(n^2)$ for $s = $ `AAAA…`.

<details><summary>Solution</summary>

$O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size();
    vector<int> pi(n, 0);
    for (int i = 1; i < n; i++) {
        int k = pi[i - 1];
        while (k > 0 && s[i] != s[k]) k = pi[k - 1];
        if (s[i] == s[k]) k++;
        pi[i] = k;
    }
    vector<long long> cnt(n + 1, 0);
    for (int i = 0; i < n; i++) cnt[pi[i]]++;
    for (int j = n - 1; j > 0; j--) cnt[pi[j - 1]] += cnt[j];
    for (int j = 1; j <= n; j++) cnt[j]++;
    vector<int> lens = {n};
    for (int k = pi[n - 1]; k > 0; k = pi[k - 1]) lens.push_back(k);
    reverse(lens.begin(), lens.end());
    cout << lens.size() << '\n';
    for (int l : lens) cout << l << ' ' << cnt[l] << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] s = in.next().toCharArray();
        int n = s.length;
        int[] pi = new int[n];
        for (int i = 1; i < n; i++) {
            int k = pi[i - 1];
            while (k > 0 && s[i] != s[k]) k = pi[k - 1];
            if (s[i] == s[k]) k++;
            pi[i] = k;
        }
        long[] cnt = new long[n + 1];
        for (int i = 0; i < n; i++) cnt[pi[i]]++;
        for (int j = n - 1; j > 0; j--) cnt[pi[j - 1]] += cnt[j];
        for (int j = 1; j <= n; j++) cnt[j]++;
        int[] lens = new int[n + 1];
        int c = 0;
        lens[c++] = n;
        for (int k = pi[n - 1]; k > 0; k = pi[k - 1]) lens[c++] = k;
        out.println(c);
        for (int i = c - 1; i >= 0; i--) out.println(lens[i] + " " + cnt[lens[i]]);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
ABACABA
out:
3
1 4
3 2
7 1
-->
<!-- test
in:
AAA
out:
3
1 3
2 2
3 1
-->
<!-- test
in:
AB
out:
1
2 1
-->

</details>

### Example 5 — Required Substring (DP over the KMP automaton) · ★ ≈2000 (est.)

- **Source:** [CSES 1112 · Required Substring](https://cses.fi/problemset/task/1112)
- **Difficulty:** ≈2000 (est.)
- **Problem:** count strings of length $n \le 1000$ over `A`–`Z` that contain a given pattern ($|p| \le 100$) as a substring, modulo $10^9+7$.
- **Thinking from first principles:** "contains" is awkward to count directly (occurrences overlap, inclusion–exclusion explodes). Count the complement: strings that *avoid* $p$. Reading a string left to right, all we need to remember to know whether $p$ has appeared is the KMP state $k$ = longest prefix of $p$ that is a suffix of what we have read — that is exactly what the automaton tracks, and it is a *sufficient* state because the future only interacts with the past through that suffix. So $f_i[k]$ = number of length-$i$ strings in state $k$ that never reached $m$; transition by every letter through $\delta$. Answer $= 26^n - \sum_{k<m} f_n[k]$. (Equivalently, keep an absorbing state $m$.)

<details><summary>Solution</summary>

$O(n\,m\,26) = 2.6\cdot 10^6$.

```cpp
#include <bits/stdc++.h>
using namespace std;
const long long MOD = 1'000'000'007LL;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; string p;
    cin >> n >> p;
    int m = p.size();
    vector<int> pi(m, 0);
    for (int i = 1; i < m; i++) {
        int k = pi[i - 1];
        while (k > 0 && p[i] != p[k]) k = pi[k - 1];
        if (p[i] == p[k]) k++;
        pi[i] = k;
    }
    vector<array<int, 26>> d(m + 1);
    for (int k = 0; k <= m; k++)
        for (int c = 0; c < 26; c++) {
            if (k < m && p[k] - 'A' == c) d[k][c] = k + 1;
            else d[k][c] = k == 0 ? 0 : d[pi[k - 1]][c];
        }
    vector<long long> f(m, 0), g(m);
    f[0] = 1;
    long long total = 1;
    for (int i = 0; i < n; i++) {
        fill(g.begin(), g.end(), 0);
        for (int k = 0; k < m; k++) if (f[k])
            for (int c = 0; c < 26; c++) {
                int nk = d[k][c];
                if (nk < m) g[nk] = (g[nk] + f[k]) % MOD;   // reaching m = contains p: dropped
            }
        swap(f, g);
        total = total * 26 % MOD;
    }
    long long avoid = 0;
    for (int k = 0; k < m; k++) avoid = (avoid + f[k]) % MOD;
    cout << ((total - avoid) % MOD + MOD) % MOD << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        final long MOD = 1_000_000_007L;
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        char[] p = in.next().toCharArray();
        int m = p.length;
        int[] pi = new int[m];
        for (int i = 1; i < m; i++) {
            int k = pi[i - 1];
            while (k > 0 && p[i] != p[k]) k = pi[k - 1];
            if (p[i] == p[k]) k++;
            pi[i] = k;
        }
        int[][] d = new int[m + 1][26];
        for (int k = 0; k <= m; k++)
            for (int c = 0; c < 26; c++) {
                if (k < m && p[k] - 'A' == c) d[k][c] = k + 1;
                else d[k][c] = k == 0 ? 0 : d[pi[k - 1]][c];
            }
        long[] f = new long[m], g = new long[m];
        f[0] = 1;
        long total = 1;
        for (int i = 0; i < n; i++) {
            Arrays.fill(g, 0);
            for (int k = 0; k < m; k++) if (f[k] != 0)
                for (int c = 0; c < 26; c++) {
                    int nk = d[k][c];
                    if (nk < m) g[nk] = (g[nk] + f[k]) % MOD;
                }
            long[] t = f; f = g; g = t;
            total = total * 26 % MOD;
        }
        long avoid = 0;
        for (int k = 0; k < m; k++) avoid = (avoid + f[k]) % MOD;
        out.println(((total - avoid) % MOD + MOD) % MOD);
        out.flush();
    }

    static final class FastReader {
        private final DataInputStream in;
        private final byte[] buf = new byte[1 << 16];
        private int len = 0, ptr = 0;
        FastReader(InputStream is) { in = new DataInputStream(is); }
        private int read() throws IOException {
            if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
            return buf[ptr++];
        }
        private int skip() throws IOException { int c; while ((c = read()) != -1 && c <= ' ') { } return c; }
        int nextInt() throws IOException { return (int) nextLong(); }
        long nextLong() throws IOException {
            int c = skip(); boolean neg = c == '-'; if (neg) c = read();
            long r = 0;
            while (c >= '0' && c <= '9') { r = r * 10 + (c - '0'); c = read(); }
            return neg ? -r : r;
        }
        String next() throws IOException {
            int c = skip(); StringBuilder sb = new StringBuilder();
            while (c > ' ') { sb.append((char) c); c = read(); }
            return sb.toString();
        }
    }
}
```

<!-- test
in:
2
A
out:
51
-->
<!-- test
in:
3
AA
out:
51
-->
<!-- test
in:
3
AB
out:
52
-->
<!-- test
in:
1
AB
out:
0
-->
<!-- test
in:
1000
A
out:
578969911
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **`while`, not `if`.** The fallback must repeat until a match or $k = 0$; a single fallback gives wrong $\pi$ values (on `aaab` it yields $\pi[3] = 1$ instead of 0).
2. **The separator must occur in neither string** (and in the automaton DP, must not be an alphabet letter). With arbitrary bytes, use the online matcher instead of concatenation.
3. **In the online matcher, reset after a full match**: when $k = m$, fall back to $\pi[m-1]$ before reading the next character — otherwise you index $p[m]$ (out of bounds) or miss overlapping occurrences.
4. **Indices:** $\pi$ is defined on positions, chains use lengths. The next border after length $k$ is $\pi[k-1]$, not $\pi[k]$. Mixing them is the most common bug.
5. **Smallest period does not have to divide $n$.** `abcab` has period 3. "Is $s$ a repetition?" needs the divisibility check.
6. **Prefix occurrence counts can reach $n$**, and sums over them reach $n^2/2$: use `long long`.
7. **Memory for $p + \# + t$ at $|t| = 10^6$** is fine in C++, but in Java prefer the online matcher (one `int[]` of size $|p|$).
8. **Automaton DP:** precompute $\delta$ — recomputing fallbacks inside the DP multiplies the cost by $m$ in the worst case. Do the modular reduction once per addition.
9. **Java:** convert to `char[]` once; `String.charAt` in the inner loop is slower and `substring` allocates.
10. **Fallbacks are amortised, not worst-case per character.** A single character may trigger $\Theta(m)$ fallbacks. For *real-time* guarantees (or when you rewind states, as in a trie or persistent structure) use the automaton, where each step is $O(1)$.

## 7. Going further (toward 2400–2600+)

- **Prefix function on a changing string / with rollback.** Amortisation breaks when you undo appends (DFS over a trie of strings). Use the automaton ($O(\Sigma)$ per appended character) — the idea behind [CF 1721E · Prefix Function Queries](https://codeforces.com/problemset/problem/1721/E) — 2200.
- **Many patterns at once** → [Aho–Corasick](06-aho-corasick.md): a trie whose failure links are the multi-pattern generalisation of $\pi$.
- **Counting distinct substrings online** in $O(n^2)$: when appending $c$ to $s$, the new distinct substrings are the suffixes of $sc$ longer than the maximum of $\pi$ of $\mathrm{rev}(sc)$. Faster: [suffix automaton](08-suffix-automaton.md).
- **Periodicity lemma and runs.** Fine–Wilf, "a string has at most one period $\le n/2$ up to multiples" style arguments, and the "runs" theorem (number of maximal repetitions is $< n$) underlie the hardest repetition problems.
- **KMP-automaton DP with extra state**: bracket balance ([CF 1015F · Bracket Substring](https://codeforces.com/problemset/problem/1015/F) — 2300), two patterns at once ([CF 1163D · Mysterious Code](https://codeforces.com/problemset/problem/1163/D) — 2100), wildcard text ([CF 808G · Anthem of Berland](https://codeforces.com/problemset/problem/808/G) — 2300).

For revision, the formulas and templates of this file are condensed in the [strings cheat sheet](../99-Cheat-Sheets/11-strings-cheatsheet.md).

## 8. Practice ladder

**≤ 1600**
- [ ] [CSES 1753 · String Matching](https://cses.fi/problemset/task/1753) — online KMP
- [ ] [CSES 1732 · Finding Borders](https://cses.fi/problemset/task/1732)
- [ ] [CSES 1733 · Finding Periods](https://cses.fi/problemset/task/1733)
- [ ] [CF 1029A · Many Equal Substrings](https://codeforces.com/problemset/problem/1029/A) — 1300
- [ ] [CF 1137B · Camp Schedule](https://codeforces.com/problemset/problem/1137/B) — 1600

**1700–1900**
- [ ] [CF 126B · Password](https://codeforces.com/problemset/problem/126/B) — 1700
- [ ] [CF 2010C2 · Message Transmission Error (hard version)](https://codeforces.com/problemset/problem/2010/C2) — 1700
- [ ] [CF 471D · MUH and Cube Walls](https://codeforces.com/problemset/problem/471/D) — 1800
- [ ] [CF 535D · Tavas and Malekas](https://codeforces.com/problemset/problem/535/D) — 1900

**2000–2200**
- [ ] [CF 432D · Prefixes and Suffixes](https://codeforces.com/problemset/problem/432/D) — 2000
- [ ] [CF 1200E · Compress Words](https://codeforces.com/problemset/problem/1200/E) — 2000
- [ ] [CF 346B · Lucky Common Subsequence](https://codeforces.com/problemset/problem/346/B) — 2000
- [ ] [CSES 1112 · Required Substring](https://cses.fi/problemset/task/1112) — ≈2000 (est.)
- [ ] [CF 1163D · Mysterious Code](https://codeforces.com/problemset/problem/1163/D) — 2100
- [ ] [CF 25E · Test](https://codeforces.com/problemset/problem/25/E) — 2200
- [ ] [CF 526D · Om Nom and Necklace](https://codeforces.com/problemset/problem/526/D) — 2200
- [ ] [CF 1721E · Prefix Function Queries](https://codeforces.com/problemset/problem/1721/E) — 2200

**2300+**
- [ ] [CF 808G · Anthem of Berland](https://codeforces.com/problemset/problem/808/G) — 2300
- [ ] [CF 1015F · Bracket Substring](https://codeforces.com/problemset/problem/1015/F) — 2300
- [ ] [CF 1466G · Song of the Sirens](https://codeforces.com/problemset/problem/1466/G) — 2600

## 9. LeetCode / FAANG cross-reference

- [LC 28 · Find the Index of the First Occurrence in a String](https://leetcode.com/problems/find-the-index-of-the-first-occurrence-in-a-string/) — Easy — KMP is the expected "optimal" follow-up.
- [LC 1392 · Longest Happy Prefix](https://leetcode.com/problems/longest-happy-prefix/) — Hard — literally $\pi[n-1]$.
- [LC 459 · Repeated Substring Pattern](https://leetcode.com/problems/repeated-substring-pattern/) — Easy — power test: $\pi[n-1] > 0$ and $(n - \pi[n-1]) \mid n$.
- [LC 214 · Shortest Palindrome](https://leetcode.com/problems/shortest-palindrome/) — Hard — longest palindromic prefix $=\pi$ of $s + \# + \mathrm{rev}(s)$ at the end.
- [LC 686 · Repeated String Match](https://leetcode.com/problems/repeated-string-match/) — Medium — KMP over a few copies of $a$.
- [LC 796 · Rotate String](https://leetcode.com/problems/rotate-string/) — Easy — KMP for $goal$ in $s+s$.
- [LC 1367 · Linked List in Binary Tree](https://leetcode.com/problems/linked-list-in-binary-tree/) — Medium — KMP state carried down tree paths (the automaton avoids amortisation issues on branching).
- [LC 572 · Subtree of Another Tree](https://leetcode.com/problems/subtree-of-another-tree/) — Easy — serialise both trees, then string matching.
- [LC 3008 · Find Beautiful Indices in the Given Array II](https://leetcode.com/problems/find-beautiful-indices-in-the-given-array-ii/) — Hard — KMP occurrences of two patterns, then two pointers.
- [LC 3036 · Number of Subarrays That Match a Pattern II](https://leetcode.com/problems/number-of-subarrays-that-match-a-pattern-ii/) — Hard — convert the array to a $\{-1,0,1\}$ string, then KMP.

Interview note: KMP is asked mainly as a follow-up ("can you do it in linear time?"); being able to explain the border chain and the amortised bound in two minutes is what impresses.

## 10. Self-check

1. Define $\pi[i]$ and compute it for `aabaaab`.
2. Why does the `while` loop run at most $n$ times in total?
3. Why is every border of $s$ in the chain $\pi[n-1], \pi[\pi[n-1]-1], \dots$?
4. State and prove the relation between periods and borders.
5. Prove: $s = u^k$ ($k \ge 2$) iff $\pi[n-1] > 0$ and $(n - \pi[n-1]) \mid n$.
6. How do you count occurrences of every prefix in $O(n)$?
7. Define the KMP automaton and give its construction cost. Why is it needed for DP over strings?

<details><summary>Answers</summary>

1. `a a b a a a b` → $\pi = 0,1,0,1,2,2,3$.
2. $k$ rises by at most 1 per character and never drops below 0; each loop iteration lowers it by at least 1, so total iterations $\le$ total rises $\le n$.
3. Any border shorter than the longest border $b$ is a prefix and a suffix of $s$ shorter than $b$, hence a border of $b$; induct along the chain.
4. $q$ is a period iff $s_i = s_{i+q}$ for $0 \le i < n-q$, which says $s[0..n-q) = s[q..n)$: a border of length $n-q$.
5. If $s = u^k$, then $|u|$ is a period and $n - |u| > 0$ is a border length, so $\pi[n-1] \ge n - |u| > 0$; the smallest period $q$ satisfies $q + |u| \le n$ (as $q \le |u| \le n/2$), so by Fine–Wilf $\gcd(q, |u|)$ is a period; minimality gives $q \mid |u|$, and $|u| \mid n$, so $q \mid n$. Conversely, if $q \mid n$ and $q < n$, period $q$ means $s = (s[0..q))^{n/q}$ with $n/q \ge 2$.
6. $c[\pi[i]] \mathrel{+}= 1$ for all $i$; for $j = n-1..1$: $c[\pi[j-1]] \mathrel{+}= c[j]$; then $c[j] \mathrel{+}= 1$.
7. States $0..m$ (matched length), $\delta(k,c) = k+1$ on match, else $\delta(\pi[k-1], c)$; $O(m\Sigma)$. The DP needs an $O(1)$ deterministic transition per (state, letter) and the state must summarise the past completely — the matched length does.

</details>
