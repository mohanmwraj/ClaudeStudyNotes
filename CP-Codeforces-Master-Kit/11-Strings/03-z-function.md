# Z-function

> **Band:** 🔵 1500–2200 · **Priority:** 🔥 · **FAANG:** low · **Prerequisites:** [prefix function / KMP](02-prefix-function-kmp.md), [two pointers](../02-Core-Techniques/03-two-pointers-and-sliding-window.md)
> **You can say you know this when:** you can write the Z-algorithm with its half-open Z-box from memory, prove the $O(n)$ bound, use $p\#t$ for matching and *mismatch-tolerant* matching, read periods off $z$, and convert between $z$ and $\pi$ in $O(n)$.

## 1. First principles — why this works

**Definition.** For a string $s$ of length $n$,

$$z[i] = \text{length of the longest common prefix of } s \text{ and } s[i..n), \qquad 1 \le i < n.$$

$z[0]$ is a convention: either $0$ or $n$ (this file uses $z[0] = n$; some judges, e.g. CSES, print $0$). Example: `aabxaab` → $z = 7,1,0,0,3,1,0$.

**Naive.** Compare character by character from every $i$: $O(n^2)$ on `aaaa…a`. The waste: after computing $z[4] = 3$ in `aabxaab` we *know* $s[4..7) = s[0..3)$, yet the naive algorithm re-reads those characters when it computes $z[5]$ and $z[6]$.

**Key invariant — the Z-box.** Maintain the segment $[l, r)$ with the largest $r$ found so far such that $s[l..r) = s[0..r-l)$ (a copy of a prefix). For a new $i$:

- If $i < r$, then $s[i..r)$ is a copy of $s[i-l..r-l)$, so the comparison of $s[i..]$ with the prefix *starts out* identical to that of $s[i-l..]$ with the prefix. Therefore $z[i] \ge \min(r - i,\; z[i-l])$ for free.
  - If $z[i-l] < r - i$, the mismatch that stopped $z[i-l]$ lies inside the copied region and reappears at $i$: $z[i] = z[i-l]$ exactly.
  - Otherwise we know at least $r - i$ characters and must compare beyond $r$.
- If $i \ge r$, we know nothing: start from 0.

Then extend naively and, if $i + z[i] > r$, move the box to $[i, i + z[i])$.

**Why $O(n)$.** Every successful character comparison in the extension loop happens at a position $\ge r$ (positions before $r$ were skipped by the free bound), and after it the box's right end moves past that position. So $r$ increases by one per successful comparison and never decreases; $r \le n$. Each $i$ also has at most one failing comparison. Total: $\le 2n$ comparisons.

**Why it is the "mirror" of the prefix function.** $\pi[j]$ looks at prefix copies *ending* at $j$; $z[i]$ looks at prefix copies *starting* at $i$. Both encode the same set of facts "$s[i..i+k) = s[0..k)$", so each can be computed from the other (§2). Pick whichever reads more naturally: Z is usually easier for "how far does the prefix match from here", $\pi$ for "longest border" and automata.

## 2. Formulas, definitions and identities

| Fact | Statement | Cost |
|---|---|---|
| Z-box bound | $i < r \Rightarrow z[i] \ge \min(r-i, z[i-l])$, with equality when $z[i-l] < r-i$ | $O(1)$ |
| matching | in $p\#t$ (separator in neither), $z[\lvert p\rvert + 1 + j] = \lvert p\rvert \iff p$ occurs at $t_j$ | $O(\lvert p\rvert + \lvert t\rvert)$ |
| LCP with another string | $\mathrm{LCP}(t[j..], p) = z_{p\#t}[\lvert p\rvert + 1 + j]$ | all $j$ in $O(\lvert p\rvert+\lvert t\rvert)$ |
| longest common *suffix* | run Z on $\mathrm{rev}(p)\#\mathrm{rev}(t)$ | same |
| period | $q$ ($1 \le q < n$) is a period $\iff q + z[q] = n$ | $O(1)$ per $q$ |
| compression | the shortest $u$ with $s = u^{k}$: smallest $q \mid n$ with $q + z[q] = n$ (or $q = n$) | $O(n)$ |
| border | a border of length $b$ exists $\iff z[n-b] = b$ | $O(1)$ per $b$ |
| $z \to \pi$ | $\pi[i + z[i] - 1] \mathrel{\max}= z[i]$, then $\pi[j] \mathrel{\max}= \pi[j+1]-1$ for $j = n-2..0$ | $O(n)$ |
| $\pi \to z$ | build a canonical string with the same $\pi$, then run Z | $O(n)$ |
| $\le 1$ mismatch at $j$ | $\mathrm{pre}[j] + \mathrm{suf}[j + m - 1] \ge m - 1$ | $O(1)$ per $j$ |

**Proof of $z \to \pi$.** $\pi[j] = \max\{\, j - i + 1 : 1 \le i \le j,\ z[i] \ge j - i + 1 \,\}$ (a border of $s[0..j]$ of length $k$ is a prefix copy starting at $i = j - k + 1$). For a fixed start $i$, the covered end positions $j \in [i, i + z[i] - 1]$ get value $j - i + 1$, which is $z[i]$ at the right end and drops by 1 per step left. Writing $z[i]$ at $i + z[i] - 1$ and sweeping right-to-left with $\pi[j] = \max(\pi[j], \pi[j+1] - 1)$ realises exactly these values (values that sweep past $i$ become $\le 0$ and are harmless).

**Proof of $\pi \to z$.** (1) $z$ is determined by $\pi$: for $j \ge 1$, $s[j..j+k) = s[0..k)$ iff $k$ is a border length of $s[0..j+k-1]$, i.e. $k$ is in the border chain at position $j+k-1$, which $\pi$ determines. (2) A string with the given $\pi$: set $c_0 = 0$ and $c_i = c_{\pi[i]-1}$ if $\pi[i] > 0$, otherwise a fresh symbol. Every equality in $c$ is a real equality of $s$ (it copies $s_i = s_{\pi[i]-1}$), so borders of $c$ are borders of $s$ and $\pi_c \le \pi$; conversely, by induction on $i$, the border of length $\pi[i]$ is reproduced (its last character by construction, the rest because $\pi[i]-1$ is in the chain at $i-1$, where $\pi_c = \pi$). Hence $\pi_c = \pi$, and by (1) $z_c = z_s$.

**Counting distinct substrings in $O(n^2)$ with Z.** Appending $c$ to $s$ creates the new suffixes of $sc$; the new *distinct* substrings are those suffixes longer than $\max_i z_{\mathrm{rev}(sc)}[i]$. Summing over all prefixes gives an $O(n^2)$ algorithm (use a [suffix array](07-suffix-array-and-lcp.md) or [suffix automaton](08-suffix-automaton.md) for more).

## 3. Implementation (C++ and Java)

### 3.1 Z-function

Driver: read $s$, print $z$ with $z[0] = n$.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> z_function(const string& s) {
    int n = s.size();
    vector<int> z(n, 0);
    if (n) z[0] = n;
    for (int i = 1, l = 0, r = 0; i < n; i++) {          // Z-box [l, r): s[l..r) == s[0..r-l)
        if (i < r) z[i] = min(r - i, z[i - l]);
        while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
        if (i + z[i] > r) l = i, r = i + z[i];
    }
    return z;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    vector<int> z = z_function(s);
    for (size_t i = 0; i < z.size(); i++) cout << z[i] << (i + 1 < z.size() ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] zFunction(char[] s) {
        int n = s.length;
        int[] z = new int[n];
        if (n > 0) z[0] = n;
        for (int i = 1, l = 0, r = 0; i < n; i++) {
            if (i < r) z[i] = Math.min(r - i, z[i - l]);
            while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
            if (i + z[i] > r) { l = i; r = i + z[i]; }
        }
        return z;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int[] z = zFunction(in.next().toCharArray());
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < z.length; i++) { if (i > 0) sb.append(' '); sb.append(z[i]); }
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
aabxaab
out:
7 1 0 0 3 1 0
-->
<!-- test
in:
aaaaa
out:
5 4 3 2 1
-->
<!-- test
in:
a
out:
1
-->

### 3.2 Conversions $z \to \pi$ and $\pi \to z$

Driver: read $s$; print $\pi$ computed **from $z$**, then $z$ computed **from $\pi$** (each input array is computed directly from $s$).

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> z_function(const vector<int>& s) {
    int n = s.size();
    vector<int> z(n, 0);
    if (n) z[0] = n;
    for (int i = 1, l = 0, r = 0; i < n; i++) {
        if (i < r) z[i] = min(r - i, z[i - l]);
        while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
        if (i + z[i] > r) l = i, r = i + z[i];
    }
    return z;
}
vector<int> prefix_function(const vector<int>& s) {
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
vector<int> z_to_pi(const vector<int>& z) {
    int n = z.size();
    vector<int> pi(n, 0);
    for (int i = 1; i < n; i++)
        if (z[i] > 0) pi[i + z[i] - 1] = max(pi[i + z[i] - 1], z[i]);   // copy [i, i+z[i]) ends there
    for (int j = n - 2; j >= 0; j--) pi[j] = max(pi[j], pi[j + 1] - 1);
    return pi;
}
vector<int> pi_to_z(const vector<int>& pi) {
    int n = pi.size(), fresh = 0;
    vector<int> c(n);                                   // canonical string with the same pi
    for (int i = 0; i < n; i++) c[i] = pi[i] > 0 ? c[pi[i] - 1] : fresh++;
    return z_function(c);
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string str; cin >> str;
    vector<int> s(str.begin(), str.end());
    vector<int> a = z_to_pi(z_function(s)), b = pi_to_z(prefix_function(s));
    for (size_t i = 0; i < a.size(); i++) cout << a[i] << (i + 1 < a.size() ? ' ' : '\n');
    for (size_t i = 0; i < b.size(); i++) cout << b[i] << (i + 1 < b.size() ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] zFunction(int[] s) {
        int n = s.length;
        int[] z = new int[n];
        if (n > 0) z[0] = n;
        for (int i = 1, l = 0, r = 0; i < n; i++) {
            if (i < r) z[i] = Math.min(r - i, z[i - l]);
            while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
            if (i + z[i] > r) { l = i; r = i + z[i]; }
        }
        return z;
    }
    static int[] prefixFunction(int[] s) {
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
    static int[] zToPi(int[] z) {
        int n = z.length;
        int[] pi = new int[n];
        for (int i = 1; i < n; i++)
            if (z[i] > 0) pi[i + z[i] - 1] = Math.max(pi[i + z[i] - 1], z[i]);
        for (int j = n - 2; j >= 0; j--) pi[j] = Math.max(pi[j], pi[j + 1] - 1);
        return pi;
    }
    static int[] piToZ(int[] pi) {
        int n = pi.length, fresh = 0;
        int[] c = new int[n];
        for (int i = 0; i < n; i++) c[i] = pi[i] > 0 ? c[pi[i] - 1] : fresh++;
        return zFunction(c);
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        char[] str = in.next().toCharArray();
        int[] s = new int[str.length];
        for (int i = 0; i < s.length; i++) s[i] = str[i];
        int[] a = zToPi(zFunction(s)), b = piToZ(prefixFunction(s));
        StringBuilder sa = new StringBuilder(), sb = new StringBuilder();
        for (int i = 0; i < a.length; i++) { if (i > 0) { sa.append(' '); sb.append(' '); } sa.append(a[i]); sb.append(b[i]); }
        out.println(sa); out.println(sb);
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
aabxaab
out:
0 1 0 0 1 2 3
7 1 0 0 3 1 0
-->
<!-- test
in:
abaabca
out:
0 0 1 1 2 0 1
7 0 1 2 0 0 1
-->
<!-- test
in:
b
out:
0
1
-->

### 3.3 Periods and compression from $z$

Smallest $q$ such that $s = u^{n/q}$ with $|u| = q$ (returns $n$ when $s$ is primitive), and the list of all periods.

```cpp
int compression_period(const vector<int>& z) {    // z[0] = n convention
    int n = z.size();
    for (int q = 1; q < n; q++)
        if (n % q == 0 && q + z[q] == n) return q;
    return n;
}
vector<int> all_periods(const vector<int>& z) {
    int n = z.size();
    vector<int> res;
    for (int q = 1; q < n; q++) if (q + z[q] == n) res.push_back(q);
    res.push_back(n);
    return res;
}
```

```java
static int compressionPeriod(int[] z) {
    int n = z.length;
    for (int q = 1; q < n; q++)
        if (n % q == 0 && q + z[q] == n) return q;
    return n;
}
static int[] allPeriods(int[] z) {
    int n = z.length, c = 0;
    int[] res = new int[n];
    for (int q = 1; q < n; q++) if (q + z[q] == n) res[c++] = q;
    res[c++] = n;
    return Arrays.copyOf(res, c);
}
```

## 4. Recognising the pattern

- **"For every position, how long does the prefix match from here?"** — that *is* $z$. Typical disguises: "for each suffix, the LCP with the whole string", "count positions where the string can be split so the parts start the same way".
- **Matching one pattern against a text, and you need more than yes/no**: the match length at each position ($z$ on $p\#t$) lets you allow a mismatch, glue two half-matches, or score partial matches.
- **Periods and "is $s$ a repetition / built from copies of its prefix"** → $q + z[q] = n$.
- **Binary search on a prefix length, then greedily place copies of that prefix** → $z[i] \ge L$ tells you every legal place in $O(1)$.
- **Confused with**: [prefix function](02-prefix-function-kmp.md) (equivalent information; $\pi$ is the natural tool for borders and automata); [hashing](01-string-hashing.md) (arbitrary substring pairs, but probabilistic and $O(\log n)$ per LCP).

## 5. Worked examples (graded)

### Example 1 — String Functions · ★ ≈1500 (est.)

- **Source:** [CSES 2107 · String Functions](https://cses.fi/problemset/task/2107)
- **Difficulty:** ≈1500 (est.)
- **Problem:** for $s$ ($|s| \le 10^6$), print the Z-function with the convention $z[0] = 0$ on one line and the prefix function on the next.
- **Thinking from first principles:** this is a calibration problem: both arrays, with the right conventions, in linear time. Writing $\pi$ via the $z \to \pi$ conversion is a good self-test that you understood §2.

<details><summary>Solution</summary>

$z$ by the Z-algorithm; $\pi$ from $z$ by the backward sweep. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; cin >> s;
    int n = s.size();
    vector<int> z(n, 0), pi(n, 0);
    for (int i = 1, l = 0, r = 0; i < n; i++) {
        if (i < r) z[i] = min(r - i, z[i - l]);
        while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
        if (i + z[i] > r) l = i, r = i + z[i];
    }
    for (int i = 1; i < n; i++) if (z[i]) pi[i + z[i] - 1] = max(pi[i + z[i] - 1], z[i]);
    for (int j = n - 2; j >= 0; j--) pi[j] = max(pi[j], pi[j + 1] - 1);
    string a, b;
    for (int i = 0; i < n; i++) { a += to_string(z[i]); a += i + 1 < n ? ' ' : '\n'; }
    for (int i = 0; i < n; i++) { b += to_string(pi[i]); b += i + 1 < n ? ' ' : '\n'; }
    cout << a << b;
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
        int[] z = new int[n], pi = new int[n];
        for (int i = 1, l = 0, r = 0; i < n; i++) {
            if (i < r) z[i] = Math.min(r - i, z[i - l]);
            while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
            if (i + z[i] > r) { l = i; r = i + z[i]; }
        }
        for (int i = 1; i < n; i++) if (z[i] > 0) pi[i + z[i] - 1] = Math.max(pi[i + z[i] - 1], z[i]);
        for (int j = n - 2; j >= 0; j--) pi[j] = Math.max(pi[j], pi[j + 1] - 1);
        StringBuilder a = new StringBuilder(), b = new StringBuilder();
        for (int i = 0; i < n; i++) { if (i > 0) { a.append(' '); b.append(' '); } a.append(z[i]); b.append(pi[i]); }
        out.println(a); out.println(b);
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
abaabca
out:
0 0 1 2 0 0 1
0 0 1 1 2 0 1
-->
<!-- test
in:
aaaa
out:
0 3 2 1
0 1 2 3
-->
<!-- test
in:
x
out:
0
0
-->

</details>

### Example 2 — Division + LCP (easy version) · ★ 1900

- **Source:** [CF 1968G1 · Division + LCP (easy version)](https://codeforces.com/problemset/problem/1968/G1) — 1900
- **Difficulty:** 1900
- **Problem:** $t$ test cases, $\sum n \le 2\cdot 10^5$. Split $s$ into exactly $k$ contiguous non-empty parts to maximise the longest common prefix of all parts; print that maximum. (Input per test: `n l r` with $l = r = k$, then $s$.)
- **Thinking from first principles:** the first part starts at 0, so every part must start with $s[0..L)$ for the LCP to be $\ge L$. Conversely, if we can choose $k$ starting positions $0 = i_1 < i_2 < \dots < i_k$ with gaps $\ge L$ and $z[i_j] \ge L$, cutting there works (each part has length $\ge L$ and starts with the prefix; the last part absorbs the tail). Feasibility is monotone in $L$ (shorter prefixes match wherever longer ones do), so **binary search $L$** and check greedily: scan left to right and take every position with $z[i] \ge L$ that is at least $L$ after the previous one — taking the earliest possible start never hurts (exchange argument). Each check is $O(n)$.

<details><summary>Solution</summary>

$O(n\log n)$ per test.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int t; cin >> t;
    while (t--) {
        int n, l, r; string s;
        cin >> n >> l >> r >> s;
        vector<int> z(n, 0);
        z[0] = n;
        for (int i = 1, a = 0, b = 0; i < n; i++) {
            if (i < b) z[i] = min(b - i, z[i - a]);
            while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
            if (i + z[i] > b) a = i, b = i + z[i];
        }
        auto parts = [&](int L) {                        // greedy count of disjoint prefix copies
            int cnt = 0;
            for (int i = 0; i < n; ) {
                if (z[i] >= L) cnt++, i += L; else i++;
            }
            return cnt;
        };
        for (int k = l; k <= r; k++) {
            int lo = 0, hi = n / k;
            while (lo < hi) {
                int mid = (lo + hi + 1) / 2;
                if (parts(mid) >= k) lo = mid; else hi = mid - 1;
            }
            cout << lo << (k < r ? ' ' : '\n');
        }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int n;
    static int[] z;
    static int parts(int L) {
        int cnt = 0;
        for (int i = 0; i < n; ) {
            if (z[i] >= L) { cnt++; i += L; } else i++;
        }
        return cnt;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int t = in.nextInt();
        while (t-- > 0) {
            n = in.nextInt();
            int l = in.nextInt(), r = in.nextInt();
            char[] s = in.next().toCharArray();
            z = new int[n];
            z[0] = n;
            for (int i = 1, a = 0, b = 0; i < n; i++) {
                if (i < b) z[i] = Math.min(b - i, z[i - a]);
                while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
                if (i + z[i] > b) { a = i; b = i + z[i]; }
            }
            StringBuilder sb = new StringBuilder();
            for (int k = l; k <= r; k++) {
                int lo = 0, hi = n / k;
                while (lo < hi) {
                    int mid = (lo + hi + 1) >>> 1;
                    if (parts(mid) >= k) lo = mid; else hi = mid - 1;
                }
                if (k > l) sb.append(' ');
                sb.append(lo);
            }
            out.println(sb);
        }
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
4
3 3 3
aba
6 2 2
abcabc
5 2 2
aaaaa
1 1 1
z
out:
0
3
2
1
-->
<!-- test
in:
2
7 3 3
abababa
8 2 2
abcdabce
out:
2
3
-->

</details>

### Example 3 — Occurrences with at most one mismatch · ★ ≈1900 (est.)

- **Source:** Original problem
- **Difficulty:** ≈1900 (est.)
- **Problem:** text $t$ and pattern $p$ ($|t|, |p| \le 10^6$, lowercase). Count the positions $j$ such that $t[j..j+|p|)$ differs from $p$ in at most one character.
- **Thinking from first principles:** KMP and the exact Z-match only answer "all characters equal". A window with exactly one mismatch at offset $a$ means: the first $a$ characters match (a forward LCP) *and* the last $m - 1 - a$ match (a backward LCP). Both quantities are available for *every* window at once: $\mathrm{pre}[j] = \mathrm{LCP}(t[j..], p)$ from $z$ on $p\#t$, and $\mathrm{suf}[e]$ = longest common suffix of $t[..e]$ and $p$ from $z$ on $\mathrm{rev}(p)\#\mathrm{rev}(t)$. The window is good iff $\mathrm{pre}[j] + \mathrm{suf}[j+m-1] \ge m - 1$: if the forward match stops at offset $a$, the backward match must reach back to offset $a+1$. Hashing + binary search would be $O(|t| \log |p|)$ and probabilistic; this is $O(|t| + |p|)$ and exact. The same idea with $k$ "kangaroo jumps" handles $k$ mismatches in $O(k)$ per window using LCP queries.

<details><summary>Solution</summary>

Two Z-arrays, then one $O(1)$ check per window. $O(|t| + |p|)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
vector<int> z_function(const string& s) {
    int n = s.size();
    vector<int> z(n, 0);
    if (n) z[0] = n;
    for (int i = 1, l = 0, r = 0; i < n; i++) {
        if (i < r) z[i] = min(r - i, z[i - l]);
        while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
        if (i + z[i] > r) l = i, r = i + z[i];
    }
    return z;
}
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string t, p;
    cin >> t >> p;
    int n = t.size(), m = p.size();
    if (m > n) { cout << 0 << '\n'; return 0; }
    vector<int> zf = z_function(p + '#' + t);
    string rp(p.rbegin(), p.rend()), rt(t.rbegin(), t.rend());
    vector<int> zb = z_function(rp + '#' + rt);
    long long cnt = 0;
    for (int j = 0; j + m <= n; j++) {
        int pre = zf[m + 1 + j];
        int e = j + m - 1;                               // window end in t; in rev(t) it is n-1-e
        int suf = zb[m + 1 + (n - 1 - e)];
        if (pre + suf >= m - 1) cnt++;
    }
    cout << cnt << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] zFunction(char[] s) {
        int n = s.length;
        int[] z = new int[n];
        if (n > 0) z[0] = n;
        for (int i = 1, l = 0, r = 0; i < n; i++) {
            if (i < r) z[i] = Math.min(r - i, z[i - l]);
            while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
            if (i + z[i] > r) { l = i; r = i + z[i]; }
        }
        return z;
    }
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String t = in.next(), p = in.next();
        int n = t.length(), m = p.length();
        if (m > n) { out.println(0); out.flush(); return; }
        int[] zf = zFunction((p + '#' + t).toCharArray());
        String rp = new StringBuilder(p).reverse().toString(), rt = new StringBuilder(t).reverse().toString();
        int[] zb = zFunction((rp + '#' + rt).toCharArray());
        long cnt = 0;
        for (int j = 0; j + m <= n; j++) {
            int pre = zf[m + 1 + j];
            int e = j + m - 1;
            int suf = zb[m + 1 + (n - 1 - e)];
            if (pre + suf >= m - 1) cnt++;
        }
        out.println(cnt);
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
abcabd
abc
out:
2
-->
<!-- test
in:
aaaa
b
out:
4
-->
<!-- test
in:
ab
abc
out:
0
-->

</details>

### Example 4 — Om Nom and Necklace · ★ 2200

- **Source:** [CF 526D · Om Nom and Necklace](https://codeforces.com/problemset/problem/526/D) — 2200
- **Difficulty:** 2200
- **Problem:** $n, k \le 10^6$. A string is *regular* if it equals $A\,B\,A\,B \dots A$ with $k+1$ copies of $A$ and $k$ copies of $B$ alternating ($A$, $B$ may be empty). For every prefix of $s$, print `1` if it is regular, else `0`.
- **Thinking from first principles:** rename $P = AB$, $q = \lvert P\rvert$. Then the string is $P^k A$ where $A$ is a prefix of $P$ — so its length $i$ satisfies $kq \le i \le kq + q$. Fix $q$ (at most $n/k$ choices). Two conditions:
  1. $s[0..kq) = P^k$, i.e. $s$ has period $q$ on its first $kq$ characters: $k = 1$, or $z[q] \ge (k-1)q$.
  2. The extra $A$ of length $a \in [0, q]$ is a prefix of $s$ placed at $kq$: $a \le z[kq]$ (take $z[n] = 0$).

  So for each valid $q$, every $i \in [kq,\; kq + \min(q, z[kq])]$ is regular. Mark these ranges with a difference array. Total $O(n/k + n)$. A naive "try every $(|A|, |B|)$" is $O(n^2)$.

<details><summary>Solution</summary>

$O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, k; string s;
    cin >> n >> k >> s;
    vector<int> z(n + 1, 0);                             // z[n] = 0 as a sentinel
    z[0] = n;
    for (int i = 1, l = 0, r = 0; i < n; i++) {
        if (i < r) z[i] = min(r - i, z[i - l]);
        while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
        if (i + z[i] > r) l = i, r = i + z[i];
    }
    vector<int> diff(n + 2, 0);
    for (long long q = 1; q * k <= n; q++) {
        if (k > 1 && z[q] < (k - 1) * q) continue;     // s[0..kq) is not P^k
        int lo = q * k, hi = min<long long>(n, q * k + min<long long>(q, z[q * k]));
        diff[lo]++; diff[hi + 1]--;
    }
    string ans(n, '0');
    for (int i = 1, run = diff[0]; i <= n; i++) { run += diff[i]; if (run > 0) ans[i - 1] = '1'; }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), k = in.nextInt();
        char[] s = in.next().toCharArray();
        int[] z = new int[n + 1];
        z[0] = n;
        for (int i = 1, l = 0, r = 0; i < n; i++) {
            if (i < r) z[i] = Math.min(r - i, z[i - l]);
            while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
            if (i + z[i] > r) { l = i; r = i + z[i]; }
        }
        int[] diff = new int[n + 2];
        for (long q = 1; q * k <= n; q++) {
            if (k > 1 && z[(int) q] < (k - 1) * q) continue;
            int lo = (int) (q * k);
            int hi = (int) Math.min(n, q * k + Math.min(q, z[lo]));
            diff[lo]++; diff[hi + 1]--;
        }
        char[] ans = new char[n];
        int run = diff[0];
        for (int i = 1; i <= n; i++) { run += diff[i]; ans[i - 1] = run > 0 ? '1' : '0'; }
        out.println(new String(ans));
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
7 2
bcabcab
out:
0000011
-->
<!-- test
in:
3 1
aba
out:
111
-->
<!-- test
in:
6 3
aaaaaa
out:
001101
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Half-open Z-box.** Keep $[l, r)$ with $r$ exclusive and the bound $\min(r - i, z[i - l])$. Mixing closed and half-open conventions produces off-by-one errors that pass small tests.
2. **$z[0]$ convention.** Decide whether $z[0]$ is $0$ or $n$ and stay consistent; the free-bound step never reads $z[0]$ for $i \ge 1$ when $l \ge 1$, but your *own* loops (e.g. greedy placement starting at 0) usually want $z[0] = n$.
3. **Separator in $p\#t$** must not occur in $p$ or $t$; otherwise matches can extend across it and exceed $|p|$. With arbitrary bytes, use an `int` array and a value outside the alphabet (e.g. $-1$).
4. **Index arithmetic for reversed strings**: position $e$ in $t$ is $n - 1 - e$ in $\mathrm{rev}(t)$. Write it down once, test on a 3-letter example.
5. **Periods: $q + z[q] = n$**, not $z[q] = n - q$ — they are equal, but the first form reminds you to check $q < n$ before reading $z[q]$.
6. **Sentinel for $z[n]$**: in "next block starts at $kq$" arguments, $kq = n$ is legal; allocate $n+1$ entries.
7. **Overflow**: products like $q\cdot k$ with $q, k \le 10^6$ need 64-bit.
8. **Java memory**: `p + '#' + t` creates a new `String` and a `char[]` copy (two allocations of $|p|+|t|$); fine at $10^6$, but avoid doing it inside a loop.

## 7. Going further (toward 2400–2600+)

- **Z on concatenations for "glue two halves" problems.** Count pairs (prefix of $a$, suffix of $b$) forming $s$ with overlap constraints: Z of $s\#a$ and of $\mathrm{rev}(s)\#\mathrm{rev}(b)$ plus a Fenwick tree — [CF 1313E · Concatenation with intersection](https://codeforces.com/problemset/problem/1313/E) — 2700.
- **Z + DP**: compare a substring with a bound string via LCP, then decide the next digit — [CF 1051E · Vasya and Big Integers](https://codeforces.com/problemset/problem/1051/E) — 2600.
- **$k$ mismatches** in $O(nk)$ with LCP queries ("kangaroo method"): needs LCP between arbitrary positions of $p$ and $t$ — use a [suffix array](07-suffix-array-and-lcp.md) of $p\#t$ with a [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md) for $O(1)$ LCP.
- **Main–Lorentz** (all tandem repeats in $O(n\log n)$) is divide and conquer with Z-functions on each half.
- **All $k$ at once** (hard version of Example 2, [CF 1968G2 · Division + LCP (hard version)](https://codeforces.com/problemset/problem/1968/G2) — 2200): for each $L$ the greedy count $c(L)$ is non-increasing, and $\sum_L c(L) = O(n \log n)$ by a harmonic argument.

For revision, the formulas and templates of this file are condensed in the [strings cheat sheet](../99-Cheat-Sheets/11-strings-cheatsheet.md).

## 8. Practice ladder

**≤ 1700**
- [ ] [CSES 2107 · String Functions](https://cses.fi/problemset/task/2107)
- [ ] [CSES 1753 · String Matching](https://cses.fi/problemset/task/1753) — via $p\#t$
- [ ] [CSES 1733 · Finding Periods](https://cses.fi/problemset/task/1733) — $q + z[q] = n$
- [ ] [CF 1326D1 · Prefix-Suffix Palindrome (Easy version)](https://codeforces.com/problemset/problem/1326/D1) — 1500
- [ ] [CF 126B · Password](https://codeforces.com/problemset/problem/126/B) — 1700
- [ ] [CF 2010C2 · Message Transmission Error (hard version)](https://codeforces.com/problemset/problem/2010/C2) — 1700

**1800–2000**
- [ ] [CF 471D · MUH and Cube Walls](https://codeforces.com/problemset/problem/471/D) — 1800
- [ ] [CF 1968G1 · Division + LCP (easy version)](https://codeforces.com/problemset/problem/1968/G1) — 1900
- [ ] [CF 535D · Tavas and Malekas](https://codeforces.com/problemset/problem/535/D) — 1900
- [ ] [CF 432D · Prefixes and Suffixes](https://codeforces.com/problemset/problem/432/D) — 2000

**2100–2300**
- [ ] [CF 1537E2 · Erase and Extend (Hard Version)](https://codeforces.com/problemset/problem/1537/E2) — 2200
- [ ] [CF 1968G2 · Division + LCP (hard version)](https://codeforces.com/problemset/problem/1968/G2) — 2200
- [ ] [CF 526D · Om Nom and Necklace](https://codeforces.com/problemset/problem/526/D) — 2200
- [ ] [CF 25E · Test](https://codeforces.com/problemset/problem/25/E) — 2200

**2400+**
- [ ] [CF 1051E · Vasya and Big Integers](https://codeforces.com/problemset/problem/1051/E) — 2600
- [ ] [CF 1313E · Concatenation with intersection](https://codeforces.com/problemset/problem/1313/E) — 2700

## 9. LeetCode / FAANG cross-reference

- [LC 2223 · Sum of Scores of Built Strings](https://leetcode.com/problems/sum-of-scores-of-built-strings/) — Hard — the answer is literally $\sum z[i]$ with $z[0] = n$.
- [LC 3031 · Minimum Time to Revert Word to Initial State II](https://leetcode.com/problems/minimum-time-to-revert-word-to-initial-state-ii/) — Hard — smallest multiple $tk$ with $z[tk] = n - tk$ (a suffix that is a prefix).
- [LC 3036 · Number of Subarrays That Match a Pattern II](https://leetcode.com/problems/number-of-subarrays-that-match-a-pattern-ii/) — Hard — encode comparisons as a string, match with Z on $p\#t$.
- [LC 28 · Find the Index of the First Occurrence in a String](https://leetcode.com/problems/find-the-index-of-the-first-occurrence-in-a-string/) — Easy — Z on $p\#t$, first $j$ with $z = |p|$.
- [LC 214 · Shortest Palindrome](https://leetcode.com/problems/shortest-palindrome/) — Hard — longest palindromic prefix: largest $i$ with $i + z[i] = |w|$ in $w = \mathrm{rev}(s)\ldots$ (or KMP).
- [LC 1392 · Longest Happy Prefix](https://leetcode.com/problems/longest-happy-prefix/) — Hard — smallest $i \ge 1$ with $i + z[i] = n$.
- [LC 459 · Repeated Substring Pattern](https://leetcode.com/problems/repeated-substring-pattern/) — Easy — some $q \mid n$, $q < n$, with $q + z[q] = n$.

Rare by name in interviews (interviewers ask for KMP), but it is the fastest correct thing to write when you need "match length at every position".

## 10. Self-check

1. Compute $z$ for `abacaba` (with $z[0] = 7$).
2. Why is $z[i] = z[i-l]$ exactly when $z[i-l] < r - i$?
3. Give the $O(n)$ argument in two sentences.
4. How do you get all periods of $s$ from $z$? All borders?
5. How do you count occurrences with at most one mismatch, and why is the condition $\mathrm{pre} + \mathrm{suf} \ge m-1$?
6. Convert $z \to \pi$ for `aabxaab` by hand.
7. Why does a canonical string built from $\pi$ have the same Z-function as the original?

<details><summary>Answers</summary>

1. $7,0,1,0,3,0,1$.
2. Inside the box, $s[i..r)$ copies $s[i-l..r-l)$. If the match from $i-l$ stops at offset $z[i-l] < r-i$, the mismatching pair of characters is copied too, so the match from $i$ stops at the same offset.
3. Each successful comparison is at a position $\ge r$ and pushes $r$ forward by one; $r \le n$. Each $i$ has at most one failed comparison, so there are $\le 2n$ comparisons.
4. Periods: all $q$ with $q + z[q] = n$, plus $n$. Borders: lengths $b = n - q$ for those $q$, i.e. $z[n-b] = b$.
5. $z$ on $p\#t$ gives the forward match $\mathrm{pre}[j]$; $z$ on reversed strings gives the backward match $\mathrm{suf}$ at the window end. If the first mismatch is at offset $a = \mathrm{pre}[j] < m$, the rest is equal iff the backward match covers offsets $a+1..m-1$, i.e. $\mathrm{suf} \ge m - 1 - a$.
6. $z = 7,1,0,0,3,1,0$: write $\pi[1] = 1$ (from $i=1$), $\pi[6] = 3$ (from $i=4$), $\pi[5] = 1$ (from $i=5$); sweep: $\pi[5] = \max(1, 2) = 2$, $\pi[4] = 1$, … giving $0,1,0,0,1,2,3$.
7. $z$ depends only on which prefix lengths are borders of which prefixes, i.e. only on $\pi$; the canonical string reproduces $\pi$ exactly (it has no extra equalities and keeps every border).

</details>
