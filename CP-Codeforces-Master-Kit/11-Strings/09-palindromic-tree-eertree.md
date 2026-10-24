# Palindromic tree (eertree)

> **Band:** 🔴 2300–2700 · **Priority:** 🧊 · **FAANG:** low · **Prerequisites:** [Manacher and palindromes](04-manacher-and-palindromes.md), [suffix automaton](08-suffix-automaton.md) (for the "links + counting by order" mindset)
> **You can say you know this when:** you can prove that a string has at most $n$ distinct non-empty palindromes, build the eertree with its two roots and suffix links in $O(n)$, and read off distinct palindromes, palindromes ending at each position, and the occurrence count of every palindrome; and you know what series links are for.

## 1. First principles — why this works

### 1.1 What Manacher does not give you

[Manacher](04-manacher-and-palindromes.md) gives, for every centre, the radius of the maximal palindrome. That answers "longest palindrome" and "how many palindromic substrings", but not questions about palindromes **as objects**: how many *distinct* palindromes, how often each occurs, which palindromes end at position $i$, the minimum number of palindromes a prefix splits into. For those we want one node per distinct palindrome, with structure between them — like a trie or a suffix automaton, but for palindromes only.

### 1.2 The key lemma: each new character adds at most one palindrome

**Lemma.** Appending a character $c$ to $s$ creates at most one new distinct palindrome, namely the longest palindromic suffix of $sc$ (if it did not occur before).

*Proof.* Let $P$ be the longest palindromic suffix of $sc$ and $Q$ a shorter palindromic suffix. $Q$ is a suffix of $P$; reversing, $\mathrm{rev}(Q)=Q$ is a prefix of $\mathrm{rev}(P)=P$. So $Q$ also occurs at the start of $P$, which ends before the last position: $Q$ is not new. ∎

Consequences: a string of length $n$ has **at most $n$ distinct non-empty palindromic substrings**, and a structure with one node per palindrome has $O(n)$ nodes. Building it online only ever needs to find *one* candidate per step.

### 1.3 Nodes, edges and suffix links

- **Nodes:** distinct palindromes, each with its length $\mathrm{len}(v)$. Two roots: an *imaginary* root of length $-1$ and the *empty* root of length $0$. With the $-1$ root, "add $c$ on both sides" of it yields the single character $c$ (length $-1+2=1$), so odd and even palindromes are handled by the same rule.
- **Edges:** $\mathrm{next}(v,c)=$ the node of $c\,\mathrm{str}(v)\,c$. Every non-root node has exactly one parent, so the edges form two trees (odd lengths under the $-1$ root, even under the $0$ root).
- **Suffix link** $\mathrm{link}(v)$: the longest *proper* palindromic suffix of $\mathrm{str}(v)$ (the empty root if none; the length-1 nodes link to the empty root; $\mathrm{link}(0\text{-root})=-1\text{-root}$).

The chain $v,\mathrm{link}(v),\mathrm{link}^2(v),\dots$ lists *all* palindromic suffixes of $\mathrm{str}(v)$ by decreasing length (same induction as for failure links in [Aho–Corasick](06-aho-corasick.md)).

### 1.4 Insertion

Keep `last` = node of the longest palindromic suffix of the current prefix $s[0..i-1]$. To add $c=s[i]$:

1. Find the longest palindromic suffix $X$ of $s[0..i-1]$ that can be extended: walk $X=\text{last},\mathrm{link}(\text{last}),\dots$ until $s[i-\mathrm{len}(X)-1]=c$. The $-1$ root always succeeds (it compares $s[i]$ with itself), so the walk terminates.
2. If $\mathrm{next}(X,c)$ exists, it is the longest palindromic suffix of $s[0..i]$ and nothing is new.
3. Otherwise create $v=cXc$ with $\mathrm{len}=\mathrm{len}(X)+2$. Its suffix link: if $\mathrm{len}(v)=1$ it is the empty root; else walk again from $\mathrm{link}(X)$ to find the longest $Y$ with $s[i-\mathrm{len}(Y)-1]=c$, and $\mathrm{link}(v)=\mathrm{next}(Y,c)$ — which exists by the lemma ($cYc$ is a shorter palindromic suffix of $s[0..i]$, hence old). Set the link **before** adding the edge $X\to v$.
4. `last` = that node.

**Why $O(n)$ amortised.** Track the start position of `last` in the text. Each link step in the first walk moves the candidate's start right by at least one; the new `last` $=cXc$ starts one position left of $X$. So over the whole run the number of steps is at most $2n$ (start positions never exceed $n$). The second walk is bounded the same way, tracking the start of $\mathrm{link}(\text{last})$. With array edges each step is $O(1)$; with per-node edge lists, $O(\sigma)$.

### 1.5 Reading off answers

- **Distinct palindromes** = number of nodes $-2$.
- **Palindromes ending at position $i$** = number of palindromic suffixes of $s[0..i]$ = depth of `last` in the link tree: $\mathrm{dep}(v)=\mathrm{dep}(\mathrm{link}(v))+1$, roots $0$. Summing over $i$ gives the number of palindromic substrings with multiplicity.
- **Occurrences of each palindrome:** each position contributes one occurrence to every node on the link chain of its `last`. So $\mathrm{occ}(\text{last}_i)\mathrel{+}=1$, then push up: in *reverse creation order* $\mathrm{occ}(\mathrm{link}(v))\mathrel{+}=\mathrm{occ}(v)$ (a link points to a shorter palindrome, created earlier).
- **Palindromes starting at $i$:** run the eertree on the reversed string.

### 1.6 Series links (🔴)

Let $\mathrm{diff}(v)=\mathrm{len}(v)-\mathrm{len}(\mathrm{link}(v))$. A classical fact: the lengths of the palindromic suffixes of any string form $O(\log n)$ **arithmetic progressions** with differences $\mathrm{diff}$ — because if $u$ is a palindromic suffix of a palindrome $v$ with $|u|\ge|v|/2$, then $|v|-|u|$ is a period of $v$, so suffixes with the same $\mathrm{diff}$ continue the progression, and each change of $\mathrm{diff}$ at least halves the length. The **series link** $\mathrm{slink}(v)$ jumps to the first node whose $\mathrm{diff}$ differs:

$$\mathrm{slink}(v)=\begin{cases}\mathrm{slink}(\mathrm{link}(v)) & \mathrm{diff}(v)=\mathrm{diff}(\mathrm{link}(v))\\ \mathrm{link}(v) & \text{otherwise}\end{cases}$$

DPs of the form "$dp[i]=\min/\sum$ over palindromic suffixes $P$ of $s[0..i)$ of $dp[i-|P|]$" — palindromic factorisation — then cost $O(\log n)$ per position instead of $O(\text{number of palindromic suffixes})$, by storing one aggregate per series (Example 3).

## 2. Formulas, definitions and identities

| Quantity | Formula | Meaning |
|---|---|---|
| distinct non-empty palindromes | $\le n$ | §1.2 lemma |
| nodes | $\le n+2$ | plus two roots |
| new node | $\mathrm{len}(cXc)=\mathrm{len}(X)+2$ | $X$ = longest extendable palindromic suffix |
| extension test | $s[i-\mathrm{len}(X)-1]=s[i]$ | the $-1$ root always passes |
| link of a new node | $\mathrm{next}(Y,c)$, $Y$ = longest extendable proper suffix of $X$; empty root if $\mathrm{len}=1$ | longest proper palindromic suffix |
| $\mathrm{dep}(v)$ | $\mathrm{dep}(\mathrm{link}(v))+1$, roots $0$ | palindromic suffixes of $\mathrm{str}(v)$ |
| palindromes ending at $i$ | $\mathrm{dep}(\text{last}_i)$ | |
| all palindromic substrings | $\sum_i\mathrm{dep}(\text{last}_i)=\sum_v\mathrm{occ}(v)$ | with multiplicity |
| $\mathrm{occ}(v)$ | $\#\{i:\text{last}_i=v\}+\sum_{\mathrm{link}(u)=v}\mathrm{occ}(u)$ | occurrences of each palindrome |
| $\mathrm{diff}(v)$, $\mathrm{slink}(v)$ | $\mathrm{len}(v)-\mathrm{len}(\mathrm{link}(v))$; jump to the next different $\mathrm{diff}$ | $O(\log n)$ series per position |
| intersecting pairs | $\binom{P}{2}-\sum_i\big(\sum_{j\le i}\mathrm{end}_j\big)\mathrm{start}_{i+1}$ | $P$ = number of palindromic occurrences |

| Operation | Cost |
|---|---|
| build with array edges | $O(n)$ time, $O(n\sigma)$ memory |
| build with edge lists | $O(n\sigma)$ time, $O(n)$ memory |
| occurrences of all palindromes | $O(n)$ after build |
| palindromic factorisation DP with series links | $O(n\log n)$ |

## 3. Implementation (C++ and Java)

### 3.1 Array eertree: distinct palindromes, total count, longest palindrome ending at each position

Input: $s$. Output: line 1 the number of distinct palindromic substrings, line 2 the number of palindromic substrings with multiplicity, line 3 for each position $i$ the length of the longest palindrome ending at $i$.
Node 0 is the $-1$ root, node 1 the empty root; nodes are numbered in creation order, which is what the occurrence push-up needs.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct Eertree {
    static constexpr int A = 26;
    vector<array<int, A>> next;
    vector<int> len, link, dep;
    vector<long long> occ;
    string s;
    int last = 1;
    explicit Eertree(int n) {
        next.reserve(n + 2); len.reserve(n + 2); link.reserve(n + 2);
        addNode(-1, 0); addNode(0, 0);          // node 0: length -1, node 1: empty; both link to node 0
    }
    int addNode(int l, int lk) {
        array<int, A> row; row.fill(-1);
        next.push_back(row); len.push_back(l); link.push_back(lk);
        dep.push_back(l <= 0 ? 0 : dep[lk] + 1); occ.push_back(0);
        return (int)len.size() - 1;
    }
    int extendable(int v, int i) const {         // longest palindromic suffix on v's chain that c can wrap
        while (true) {
            int j = i - len[v] - 1;
            if (j >= 0 && s[j] == s[i]) return v;
            v = link[v];
        }
    }
    void add(char ch) {
        s.push_back(ch);
        int i = s.size() - 1, c = ch - 'a';
        int x = extendable(last, i);
        if (next[x][c] == -1) {
            int lk = len[x] == -1 ? 1 : next[extendable(link[x], i)][c];
            int v = addNode(len[x] + 2, lk);     // link computed before the edge x -> v exists
            next[x][c] = v;
        }
        last = next[x][c];
        occ[last]++;
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s;
    cin >> s;
    Eertree t(s.size());
    long long total = 0;
    string ends;
    for (char ch : s) {
        t.add(ch);
        total += t.dep[t.last];
        ends += to_string(t.len[t.last]); ends += ' ';
    }
    ends.pop_back();
    cout << t.len.size() - 2 << '\n' << total << '\n' << ends << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class Eertree {
        static final int A = 26;
        final int[] next, len, link, dep;
        final long[] occ;
        final char[] s;
        int n = 0, size = 2, last = 1;
        Eertree(int maxLen) {
            int cap = maxLen + 2;
            next = new int[cap * A]; Arrays.fill(next, -1);
            len = new int[cap]; link = new int[cap]; dep = new int[cap]; occ = new long[cap];
            s = new char[maxLen];
            len[0] = -1; link[0] = 0; len[1] = 0; link[1] = 0;      // node 0: length -1, node 1: empty
        }
        int extendable(int v, int i) {
            while (true) {
                int j = i - len[v] - 1;
                if (j >= 0 && s[j] == s[i]) return v;
                v = link[v];
            }
        }
        void add(char ch) {
            int i = n++, c = ch - 'a';
            s[i] = ch;
            int x = extendable(last, i);
            if (next[x * A + c] == -1) {
                int lk = len[x] == -1 ? 1 : next[extendable(link[x], i) * A + c];
                int v = size++;
                len[v] = len[x] + 2; link[v] = lk; dep[v] = dep[lk] + 1;
                next[x * A + c] = v;
            }
            last = next[x * A + c];
            occ[last]++;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        Eertree t = new Eertree(s.length());
        long total = 0;
        StringBuilder ends = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            t.add(s.charAt(i));
            total += t.dep[t.last];
            if (i > 0) ends.append(' ');
            ends.append(t.len[t.last]);
        }
        out.println(t.size - 2);
        out.println(total);
        out.println(ends);
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
7
12
1 1 3 1 3 5 7
-->
<!-- test
in:
aaaa
out:
4
10
1 2 3 4
-->
<!-- test
in:
z
out:
1
1
1
-->

For `abacaba` the distinct palindromes are `a, b, c, aba, aca, bacab, abacaba` (7) and the per-position counts $1,1,2,1,2,2,3$ sum to 12.

## 4. Recognising the pattern

- **"Distinct palindromic substrings"** (count, list, or a function of each one's occurrences) → eertree; Manacher cannot deduplicate without hashing.
- **"For every position, palindromes ending (or starting) here"** → `dep[last]`, and the reversed string for starts.
- **"Split into the minimum number of palindromes / count palindromic factorisations"** with $n\ge10^5$ → series links, $O(n\log n)$ (the $O(n^2)$ DP is the interview version).
- **Online appends with palindrome questions after each character** → eertree is naturally online; Manacher is not.
- **Pairs of palindromes** (intersecting, nested, adjacent) → counts per position from two eertrees (forward and reversed) plus prefix sums.
- **Confused with:** [Manacher](04-manacher-and-palindromes.md) (centres and radii, $O(n)$ memory, enough for "longest" and "how many"), [hashing](01-string-hashing.md) (palindrome check of a given substring in $O(1)$).

## 5. Worked examples (graded)

### Example 1 — The most valuable palindrome · ★ ≈2200 (est.)

- **Source:** Original problem (the second quantity is the core of the well-known APIO 2014 task "Palindromes").
- **Difficulty:** ≈2200 (est.)
- **Problem:** for a string $s$ ($n\le3\cdot10^5$), output the number of distinct palindromic substrings and $\max_p |p|\cdot\mathrm{occ}(p)$ over palindromic substrings $p$.
- **Thinking from first principles:** listing palindromes by centre with Manacher produces $\Theta(n^2)$ occurrences and loses identity. The eertree has one node per distinct palindrome; its occurrence count is the number of positions whose longest palindromic suffix chain passes through it, i.e. a subtree sum in the link tree, computed by one reverse pass over creation order.

<details><summary>Solution</summary>

Build; `occ[last]++` per position; for $v$ from the last created node down to 2, `occ[link[v]] += occ[v]`; answer $\max\mathrm{len}(v)\,\mathrm{occ}(v)$ in 64-bit. $O(n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct Eertree {                                      // §3.1, compacted
    static constexpr int A = 26;
    vector<array<int, A>> next; vector<int> len, link, dep; vector<long long> occ; string s; int last = 1;
    explicit Eertree(int n) { next.reserve(n + 2); addNode(-1, 0); addNode(0, 0); }
    int addNode(int l, int lk) {
        array<int, A> row; row.fill(-1);
        next.push_back(row); len.push_back(l); link.push_back(lk); dep.push_back(l <= 0 ? 0 : dep[lk] + 1); occ.push_back(0);
        return (int)len.size() - 1;
    }
    int extendable(int v, int i) const {
        while (true) { int j = i - len[v] - 1; if (j >= 0 && s[j] == s[i]) return v; v = link[v]; }
    }
    void add(char ch) {
        s.push_back(ch);
        int i = s.size() - 1, c = ch - 'a', x = extendable(last, i);
        if (next[x][c] == -1) {
            int lk = len[x] == -1 ? 1 : next[extendable(link[x], i)][c];
            int v = addNode(len[x] + 2, lk);
            next[x][c] = v;
        }
        last = next[x][c];
        occ[last]++;
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s;
    cin >> s;
    Eertree t(s.size());
    for (char ch : s) t.add(ch);
    int N = t.len.size();
    for (int v = N - 1; v >= 2; v--) t.occ[t.link[v]] += t.occ[v];   // links point to older nodes
    long long best = 0;
    for (int v = 2; v < N; v++) best = max(best, t.len[v] * t.occ[v]);
    cout << N - 2 << '\n' << best << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class Eertree {                       // §3.1, compacted
        static final int A = 26;
        final int[] next, len, link, dep; final long[] occ; final char[] s; int n = 0, size = 2, last = 1;
        Eertree(int maxLen) {
            int cap = maxLen + 2;
            next = new int[cap * A]; Arrays.fill(next, -1);
            len = new int[cap]; link = new int[cap]; dep = new int[cap]; occ = new long[cap]; s = new char[maxLen];
            len[0] = -1;
        }
        int extendable(int v, int i) {
            while (true) { int j = i - len[v] - 1; if (j >= 0 && s[j] == s[i]) return v; v = link[v]; }
        }
        void add(char ch) {
            int i = n++, c = ch - 'a';
            s[i] = ch;
            int x = extendable(last, i);
            if (next[x * A + c] == -1) {
                int lk = len[x] == -1 ? 1 : next[extendable(link[x], i) * A + c];
                int v = size++;
                len[v] = len[x] + 2; link[v] = lk; dep[v] = dep[lk] + 1;
                next[x * A + c] = v;
            }
            last = next[x * A + c];
            occ[last]++;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        Eertree t = new Eertree(s.length());
        for (int i = 0; i < s.length(); i++) t.add(s.charAt(i));
        for (int v = t.size - 1; v >= 2; v--) t.occ[t.link[v]] += t.occ[v];
        long best = 0;
        for (int v = 2; v < t.size; v++) best = Math.max(best, t.len[v] * t.occ[v]);
        out.println(t.size - 2);
        out.println(best);
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
7
7
-->
<!-- test
in:
aaaa
out:
4
6
-->
<!-- test
in:
ab
out:
2
1
-->

</details>

`abacaba`: `a` occurs 4 times ($4$), `aba` twice ($6$), `abacaba` once ($7$) — the maximum is 7. `aaaa`: `aa` ($2\cdot3$) and `aaa` ($3\cdot2$) tie at 6.

### Example 2 — Intersecting palindromic pairs · ★ 2900

- **Source:** [CF 17E · Palisection](https://codeforces.com/problemset/problem/17/E) — 2900
- **Difficulty:** 2900
- **Problem:** a string of length $n\le2\cdot10^6$. Consider all occurrences of palindromic substrings (different positions are different). Count unordered pairs of different occurrences that share at least one position, modulo $51123987$.
- **Thinking from first principles:** direct counting of intersections is hard; the complement is easy. Two different occurrences either intersect or one ends strictly before the other starts. With $P$ = total number of palindromic occurrences, the answer is $\binom P2$ minus the disjoint pairs. A disjoint pair is determined by its "gap": the left one ends at some $j\le i$ and the right one starts at $i+1$. So we need, per position, $\mathrm{end}_i$ (palindromes ending at $i$) and $\mathrm{start}_i$ (palindromes starting at $i$) — `dep[last]` of a forward eertree and of an eertree on the reversed string.

<details><summary>Solution</summary>

Disjoint $=\sum_{i=0}^{n-2}\big(\sum_{j\le i}\mathrm{end}_j\big)\cdot\mathrm{start}_{i+1}$, all modulo $M$. $P\le n(n+1)/2\approx2\cdot10^{12}$ fits in 64 bits; compute $\binom P2\bmod M$ by halving the even factor first. Memory matters at $n=2\cdot10^6$: a $26$-wide edge table would be $208$ MB per tree, so edges are stored as **per-node linked lists** (each node has one incoming edge, so $O(n)$ memory) and child lookup scans at most $\sigma$ entries; only the per-position counts are kept, the second tree reuses the arrays. $O(n\sigma)$ time.

```cpp
#include <bits/stdc++.h>
using namespace std;

// Eertree with edge lists: memory O(n). Returns dep[last] after each character.
vector<int> palSuffixCounts(const string& s) {
    int n = s.size();
    vector<int> len(n + 2), link(n + 2), dep(n + 2, 0), head(n + 2, -1), sib(n + 2, -1);
    vector<char> ch(n + 2);
    len[0] = -1; link[0] = 0; len[1] = 0; link[1] = 0;
    int size = 2, last = 1;
    auto child = [&](int v, char c) { for (int u = head[v]; u != -1; u = sib[u]) if (ch[u] == c) return u; return -1; };
    auto extendable = [&](int v, int i) {
        while (true) { int j = i - len[v] - 1; if (j >= 0 && s[j] == s[i]) return v; v = link[v]; }
    };
    vector<int> res(n);
    for (int i = 0; i < n; i++) {
        char c = s[i];
        int x = extendable(last, i), v = child(x, c);
        if (v == -1) {
            int lk = len[x] == -1 ? 1 : child(extendable(link[x], i), c);
            v = size++;
            len[v] = len[x] + 2; link[v] = lk; dep[v] = dep[lk] + 1;
            ch[v] = c; sib[v] = head[x]; head[x] = v;
        }
        last = v;
        res[i] = dep[v];
    }
    return res;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const long long M = 51123987;
    int n; string s;
    cin >> n >> s;
    vector<int> endAt = palSuffixCounts(s);
    string r(s.rbegin(), s.rend());
    vector<int> revEnd = palSuffixCounts(r);              // palindromes starting at i = revEnd[n-1-i]
    long long P = 0;
    for (int x : endAt) P += x;
    long long pairs = (P % 2 == 0) ? (P / 2 % M) * ((P - 1) % M) % M : (P % M) * ((P - 1) / 2 % M) % M;
    long long pref = 0, disjoint = 0;
    for (int i = 0; i + 1 < n; i++) {
        pref = (pref + endAt[i]) % M;
        disjoint = (disjoint + pref * revEnd[n - 2 - i]) % M;   // start at i+1
    }
    cout << ((pairs - disjoint) % M + M) % M << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    // Eertree with edge lists: memory O(n). Returns dep[last] after each character.
    static int[] palSuffixCounts(byte[] s) {
        int n = s.length;
        int[] len = new int[n + 2], link = new int[n + 2], dep = new int[n + 2], head = new int[n + 2], sib = new int[n + 2];
        byte[] ch = new byte[n + 2];
        Arrays.fill(head, -1);
        len[0] = -1;
        int size = 2, last = 1;
        int[] res = new int[n];
        for (int i = 0; i < n; i++) {
            byte c = s[i];
            int x = last;
            while (true) { int j = i - len[x] - 1; if (j >= 0 && s[j] == c) break; x = link[x]; }
            int v = -1;
            for (int u = head[x]; u != -1; u = sib[u]) if (ch[u] == c) { v = u; break; }
            if (v == -1) {
                int lk = 1;
                if (len[x] != -1) {
                    int y = link[x];
                    while (true) { int j = i - len[y] - 1; if (j >= 0 && s[j] == c) break; y = link[y]; }
                    for (int u = head[y]; u != -1; u = sib[u]) if (ch[u] == c) { lk = u; break; }
                }
                v = size++;
                len[v] = len[x] + 2; link[v] = lk; dep[v] = dep[lk] + 1;
                ch[v] = c; sib[v] = head[x]; head[x] = v;
            }
            last = v;
            res[i] = dep[v];
        }
        return res;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        final long M = 51123987L;
        int n = in.nextInt();
        byte[] s = in.next().getBytes();
        byte[] r = new byte[n];
        for (int i = 0; i < n; i++) r[i] = s[n - 1 - i];
        int[] endAt = palSuffixCounts(s), revEnd = palSuffixCounts(r);
        long P = 0;
        for (int x : endAt) P += x;
        long pairs = (P % 2 == 0) ? (P / 2 % M) * ((P - 1) % M) % M : (P % M) * ((P - 1) / 2 % M) % M;
        long pref = 0, disjoint = 0;
        for (int i = 0; i + 1 < n; i++) {
            pref = (pref + endAt[i]) % M;
            disjoint = (disjoint + pref * revEnd[n - 2 - i]) % M;
        }
        out.println(((pairs - disjoint) % M + M) % M);
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
3
aaa
out:
10
-->
<!-- test
in:
1
z
out:
0
-->
<!-- test
in:
4
abba
out:
7
-->

</details>

Hand check for `aaa`: the palindromic occurrences are $[0,0],[1,1],[2,2],[0,1],[1,2],[0,2]$, so $P=6$ and $\binom62=15$. The disjoint pairs are $[0,0]|[1,1]$, $[0,0]|[2,2]$, $[1,1]|[2,2]$, $[0,0]|[1,2]$, $[0,1]|[2,2]$ — five — so the answer is $10$. The formula agrees: $\mathrm{end}=[1,2,3]$, $\mathrm{start}=[3,2,1]$, disjoint $=1\cdot2+3\cdot1=5$.

### Example 3 — Minimum palindromic factorisation with series links · ★ ≈2600 (est.)

- **Source:** [LC 132 · Palindrome Partitioning II](https://leetcode.com/problems/palindrome-partitioning-ii/) — Hard, solved here for $n\le10^6$ instead of $2000$ (the same series-link machinery drives [CF 932G · Palindrome Partition](https://codeforces.com/problemset/problem/932/G) — 2900).
- **Difficulty:** ≈2600 (est.) for the $O(n\log n)$ method.
- **Problem:** split $s$ into the minimum number of palindromes; print the minimum number of cuts (pieces $-1$).
- **Thinking from first principles:** $dp[i]=1+\min\{dp[i-|P|]: P \text{ palindromic suffix of } s[0..i)\}$ is correct but a prefix can have $\Theta(n)$ palindromic suffixes (`aaaa…`), giving $O(n^2)$. The suffixes come in $O(\log n)$ arithmetic progressions (§1.6). For one progression $v, \mathrm{link}(v),\dots$ (same $\mathrm{diff}=d$) ending just above $\mathrm{slink}(v)$, the candidate positions are $i-\mathrm{len}(v), i-\mathrm{len}(v)+d,\dots, i-\mathrm{len}(\mathrm{slink}(v))-d$. All but the last of them were *exactly* the candidate set of the progression of $\mathrm{link}(v)$ at position $i-d$ — so store one aggregate per node, `best[v]`, and update it in $O(1)$: `best[v] = dp[i - len(slink v) - diff v]`, combined with `best[link v]` when $\mathrm{link}(v)$ is in the same progression.

<details><summary>Solution</summary>

For each $i$: add $s[i-1]$; walk $v=\text{last}$ along series links while $\mathrm{len}(v)>0$; set $\mathrm{best}[v]=dp[i-(\mathrm{len}(\mathrm{slink}(v))+\mathrm{diff}(v))]$; if $\mathrm{diff}(v)=\mathrm{diff}(\mathrm{link}(v))$, $\mathrm{best}[v]=\min(\mathrm{best}[v],\mathrm{best}[\mathrm{link}(v)])$; $dp[i]=\min(dp[i],\mathrm{best}[v]+1)$. The correctness of reusing $\mathrm{best}[\mathrm{link}(v)]$ is the lemma that $\mathrm{link}(v)$ was a palindromic suffix at position $i-\mathrm{diff}(v)$ and was last updated there (Kosolobov–Rubinchik–Shur). Answer $dp[n]-1$. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s;
    cin >> s;
    int n = s.size();
    vector<array<int, 26>> next(n + 2);
    vector<int> len(n + 2), link(n + 2), diff(n + 2, 0), slink(n + 2, 0), best(n + 2, 0), dp(n + 1, INT_MAX);
    for (auto& row : next) row.fill(-1);
    len[0] = -1; link[0] = 0; len[1] = 0; link[1] = 0;       // diff/slink of the roots stay 0
    int size = 2, last = 1;
    auto extendable = [&](int v, int i) {
        while (true) { int j = i - len[v] - 1; if (j >= 0 && s[j] == s[i]) return v; v = link[v]; }
    };
    dp[0] = 0;
    for (int i = 0; i < n; i++) {
        int c = s[i] - 'a', x = extendable(last, i);
        if (next[x][c] == -1) {
            int lk = len[x] == -1 ? 1 : next[extendable(link[x], i)][c];
            int v = size++;
            len[v] = len[x] + 2; link[v] = lk;
            diff[v] = len[v] - len[lk];
            slink[v] = diff[v] == diff[lk] ? slink[lk] : lk;
            next[x][c] = v;
        }
        last = next[x][c];
        int pos = i + 1;                                     // dp index of the prefix s[0..i]
        for (int v = last; len[v] > 0; v = slink[v]) {
            best[v] = dp[pos - (len[slink[v]] + diff[v])];
            if (diff[v] == diff[link[v]]) best[v] = min(best[v], best[link[v]]);
            dp[pos] = min(dp[pos], best[v] + 1);
        }
    }
    cout << dp[n] - 1 << '\n';
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
        int[] next = new int[(n + 2) * 26];
        Arrays.fill(next, -1);
        int[] len = new int[n + 2], link = new int[n + 2], diff = new int[n + 2], slink = new int[n + 2], best = new int[n + 2], dp = new int[n + 1];
        Arrays.fill(dp, Integer.MAX_VALUE);
        len[0] = -1;
        int size = 2, last = 1;
        dp[0] = 0;
        for (int i = 0; i < n; i++) {
            int c = s[i] - 'a', x = last;
            while (true) { int j = i - len[x] - 1; if (j >= 0 && s[j] == s[i]) break; x = link[x]; }
            if (next[x * 26 + c] == -1) {
                int lk = 1;
                if (len[x] != -1) {
                    int y = link[x];
                    while (true) { int j = i - len[y] - 1; if (j >= 0 && s[j] == s[i]) break; y = link[y]; }
                    lk = next[y * 26 + c];
                }
                int v = size++;
                len[v] = len[x] + 2; link[v] = lk;
                diff[v] = len[v] - len[lk];
                slink[v] = diff[v] == diff[lk] ? slink[lk] : lk;
                next[x * 26 + c] = v;
            }
            last = next[x * 26 + c];
            int pos = i + 1;
            for (int v = last; len[v] > 0; v = slink[v]) {
                best[v] = dp[pos - (len[slink[v]] + diff[v])];
                if (diff[v] == diff[link[v]]) best[v] = Math.min(best[v], best[link[v]]);
                dp[pos] = Math.min(dp[pos], best[v] + 1);
            }
        }
        out.println(dp[n] - 1);
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
aab
out:
1
-->
<!-- test
in:
abacabad
out:
1
-->
<!-- test
in:
abcd
out:
3
-->
<!-- test
in:
a
out:
0
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Two roots, and their links.** Node of length $-1$ links to itself; the empty node links to the $-1$ node. The $-1$ root makes every walk terminate (it "extends" with $s[i]$ itself) and turns $c$ into a length-1 palindrome. Getting either link wrong produces infinite loops.
2. **Bounds check in the extension test.** $j=i-\mathrm{len}(X)-1$ can be $-1$ (when $X$ is the whole prefix); test `j >= 0` before reading `s[j]`, or put a sentinel character at the front.
3. **Compute the new node's link before adding the edge $X\to v$, and give length-1 nodes the empty root explicitly.** When $X$ is the $-1$ root, the second walk starts at $\mathrm{link}(X)=X$ and would return $\mathrm{next}(X,c)$ — the new node itself — once that edge exists.
4. **The empty root is not a guaranteed stop.** Its extension test compares $s[i-1]$ with $s[i]$ (even palindromes); only the $-1$ root always succeeds. A walk that stops at the empty root creates wrong even palindromes.
5. **Occurrence push-up order** is reverse *creation* order, which is a valid bottom-up order because a node's link always exists before it. No sort and no recursion needed.
6. **Memory.** Array edges cost $(n+2)\sigma$ ints: $2\cdot10^6\cdot26\cdot4$ B $=208$ MB. Each node has exactly one parent, so edge lists (`head`, `sibling`, `char`) cost $O(n)$ (Example 2), at $O(\sigma)$ per lookup.
7. **Counts overflow.** Palindromic occurrences are up to $n(n+1)/2$ (all-equal string): 64-bit, and reduce before multiplying under a modulus.
8. **Palindromes *starting* at a position** need a second eertree on the reversed string; there is no cheap way to get them from the forward tree.
9. **Java:** keep everything in flat `int[]`; a `char[]`/`byte[]` copy of the string avoids `charAt` bounds checks in the hot loop, and both walks are plain `while` loops (no recursion anywhere).
10. **Series-link DP needs `diff` of the roots to differ from every real `diff`.** With roots' `diff = 0` and real `diff ≥ 1` the test `diff[v] == diff[link[v]]` is automatically false when the link is a root.

## 7. Going further (toward 2400–2600+)

- **Palindromic factorisation counts.** Replace `min` by `+` in Example 3 to count factorisations into palindromes; with parity conditions you get [CF 932G · Palindrome Partition](https://codeforces.com/problemset/problem/932/G) — 2900 (map $s$ to $s_0s_{n-1}s_1s_{n-2}\dots$ so that "equal blocks from both ends" becomes "even palindromic factorisation").
- **Factorisation into palindromes of bounded count** ("is $s$ a concatenation of $k$ palindromes?") and **reverses** problems use the same $O(\log n)$ series per position — [CF 906E · Reverses](https://codeforces.com/problemset/problem/906/E) — 3300.
- **Double-ended eertree.** Supports adding characters on both sides (keep a `last` for each end); a palindrome that becomes a prefix and a suffix updates both.
- **Persistent / on-tree eertree.** Building over a trie (each node extends its parent's tree) needs "quick links" (`quick[v][c]`) to bound the walk, since amortisation fails on branching.
- **Palindromic richness and the $n$ bound** connect to combinatorics on words: strings attaining $n$ distinct palindromes are called *rich*.
- **Hard combinations** with hashing or suffix structures: [CF 1081H · Palindromic Magic](https://codeforces.com/problemset/problem/1081/H) — 3500 (counting distinct concatenations of palindromes).

## 8. Practice ladder

**≤1900**
- [ ] [LC 647 · Palindromic Substrings](https://leetcode.com/problems/palindromic-substrings/) — Medium — $\sum\mathrm{dep}$
- [ ] [LC 5 · Longest Palindromic Substring](https://leetcode.com/problems/longest-palindromic-substring/) — Medium — max of `len[last]`
- [ ] [CSES 1111 · Longest Palindrome](https://cses.fi/problemset/task/1111) — ≈1700 (est.)
- [ ] [CF 159D · Palindrome pairs](https://codeforces.com/problemset/problem/159/D) — 1500 — palindromes ending / starting at each position
- [ ] [CF 245H · Queries for Number of Palindromes](https://codeforces.com/problemset/problem/245/H) — 1800
- [ ] [CF 835D · Palindromic characteristics](https://codeforces.com/problemset/problem/835/D) — 1900

**1900–2400**
- [ ] [CSES 3138 · All Palindromes](https://cses.fi/problemset/task/3138) — ≈2000 (est.) — per-position palindrome information
- [ ] [LC 132 · Palindrome Partitioning II](https://leetcode.com/problems/palindrome-partitioning-ii/) — Hard — Example 3 (also solvable in $O(n^2)$)
- [ ] [LC 214 · Shortest Palindrome](https://leetcode.com/problems/shortest-palindrome/) — Hard — eertree of the reversed string: `len[last]` is the longest palindromic prefix

**2400+**
- [ ] [CF 17E · Palisection](https://codeforces.com/problemset/problem/17/E) — 2900 — Example 2
- [ ] [CF 932G · Palindrome Partition](https://codeforces.com/problemset/problem/932/G) — 2900 — series links
- [ ] [CF 906E · Reverses](https://codeforces.com/problemset/problem/906/E) — 3300
- [ ] [CF 1081H · Palindromic Magic](https://codeforces.com/problemset/problem/1081/H) — 3500

## 9. LeetCode / FAANG cross-reference

- [LC 647 · Palindromic Substrings](https://leetcode.com/problems/palindromic-substrings/) — Medium — the sum of `dep[last]`; the interview answer is expand-around-centre $O(n^2)$.
- [LC 5 · Longest Palindromic Substring](https://leetcode.com/problems/longest-palindromic-substring/) — Medium — $\max_i \mathrm{len}(\text{last}_i)$; Manacher is the usual linear answer.
- [LC 132 · Palindrome Partitioning II](https://leetcode.com/problems/palindrome-partitioning-ii/) — Hard — Example 3; $O(n^2)$ DP is expected.
- [LC 214 · Shortest Palindrome](https://leetcode.com/problems/shortest-palindrome/) — Hard — longest palindromic prefix (KMP on $s\#\mathrm{rev}(s)$ is the standard answer).
- [LC 1745 · Palindrome Partitioning IV](https://leetcode.com/problems/palindrome-partitioning-iv/) — Hard — "three palindromes?" — palindromic prefixes and suffixes from two eertrees, then check middles with Manacher.

Rare in interviews: the eertree is a contest structure; interviews expect expand-around-centre, Manacher at most, and $O(n^2)$ DP for partitioning.

## 10. Self-check

1. Prove that appending one character creates at most one new distinct palindrome. What bound on distinct palindromes follows?
2. Why are there two roots, what are their lengths and links, and why does every walk terminate?
3. Describe how the suffix link of a newly created node is found, and why the required edge already exists.
4. Why is the construction amortised $O(n)$?
5. How do you get the number of palindromic substrings ending at each position, and the number of occurrences of every distinct palindrome?
6. How would you count palindromes *starting* at each position?
7. What are $\mathrm{diff}$ and series links, and why are there $O(\log n)$ series per position?
8. In the series-link DP, what does `best[v]` store and when may it reuse `best[link[v]]`?

<details><summary>Answers</summary>

1. Any shorter palindromic suffix $Q$ of the longest palindromic suffix $P$ is also a prefix of $P$ (reflection), so it occurred earlier. Hence at most $n$ distinct non-empty palindromes.
2. Length $-1$ (links to itself) and length $0$ (links to the $-1$ root). Wrapping the $-1$ root with $c$ gives the single letter $c$; the extension test for the $-1$ root compares $s[i]$ with itself and always succeeds, so walks stop there at the latest.
3. Walk from $\mathrm{link}(X)$ to the longest $Y$ with $s[i-\mathrm{len}(Y)-1]=s[i]$; the link is $\mathrm{next}(Y,c)$ (or the empty root if the new length is 1). $cYc$ is a proper palindromic suffix of the new palindrome, hence (lemma) it occurred before and its node exists.
4. Every link step moves the start position of the current candidate right; the new `last` starts only one position left of $X$; start positions are bounded by $n$, so the total number of steps is $O(n)$ (similarly for the second walk).
5. $\mathrm{dep}(\text{last}_i)$, with $\mathrm{dep}(v)=\mathrm{dep}(\mathrm{link}(v))+1$. Occurrences: `occ[last_i]++`, then `occ[link[v]] += occ[v]` in reverse creation order.
6. Build a second eertree on the reversed string; palindromes starting at $i$ are those ending at $n-1-i$ in the reversed string.
7. $\mathrm{diff}(v)=\mathrm{len}(v)-\mathrm{len}(\mathrm{link}(v))$; $\mathrm{slink}$ jumps over a maximal run of equal $\mathrm{diff}$. Within a palindrome, a palindromic suffix of at least half its length gives a period, so equal differences continue a progression and each change of difference at least halves the length: $O(\log n)$ runs.
8. `best[v]` is the minimum of $dp$ over the start positions of the series headed by $v$ at the current position. If $\mathrm{diff}(v)=\mathrm{diff}(\mathrm{link}(v))$, all but one of those positions form the series of $\mathrm{link}(v)$ computed at position $i-\mathrm{diff}(v)$, so `best[v] = min(dp[i - len(slink v) - diff v], best[link v])`.

</details>
