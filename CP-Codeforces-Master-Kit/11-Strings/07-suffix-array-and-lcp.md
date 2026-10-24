# Suffix array and LCP array

> **Band:** 🟠 2000–2400 · **Priority:** ⚡ · **FAANG:** low · **Prerequisites:** [sorting and comparators](../01-Foundations/05-sorting-and-comparators.md), [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md), [string hashing](01-string-hashing.md), [monotonic stack](../02-Core-Techniques/04-monotonic-stack-and-deque.md)
> **You can say you know this when:** you can write the $O(n\log n)$ doubling suffix array and Kasai's LCP from memory, prove why both are correct, and reduce "distinct substrings", "longest repeated / common substring", "$k$-th substring" and "LCP of two arbitrary suffixes" to one pass or one RMQ over the LCP array.

## 1. First principles — why this works

### 1.1 What we want and why sorting suffixes is the right object

Almost every "substring" question is a question about **prefixes of suffixes**: a substring is a prefix of the suffix where it starts.
If all $n$ suffixes are sorted lexicographically, then:

- all occurrences of a pattern $p$ are suffixes starting with $p$, which form one **contiguous block** of the sorted order (binary search finds it);
- equal prefixes of different suffixes are shared by *neighbours* in the order, so the length of the common prefix of neighbours — the LCP array — tells us how substrings repeat.

The **suffix array** $\mathrm{SA}$ is the permutation of $0..n-1$ listing suffix start positions in sorted order; $\mathrm{rank}=\mathrm{SA}^{-1}$.
The **LCP array** is $\mathrm{lcp}[i]=\mathrm{LCP}(s[\mathrm{SA}[i-1]..],\ s[\mathrm{SA}[i]..])$ for $i\ge1$ ($\mathrm{lcp}[0]=0$).

### 1.2 The naive sort and where the waste is

`sort` with string comparisons is $O(n\log n)$ comparisons of cost up to $O(n)$ each: $O(n^2\log n)$ on `aaaa…a`.
The waste: comparing suffix $i$ with suffix $j$ re-reads characters that were already compared when $i+1$ was compared with $j+1$, and so on. Suffixes overlap; their comparisons should reuse each other.

### 1.3 Prefix doubling: reuse previous rounds

Let $r_k(i)$ be the rank of the length-$k$ prefix of suffix $i$ among all length-$k$ prefixes (equal prefixes get equal ranks; a prefix running off the end is just shorter).
The length-$2k$ prefix of suffix $i$ is (length-$k$ prefix of $i$) followed by (length-$k$ prefix of $i+k$). Lexicographic order on concatenations of two equal-length blocks is the order on pairs, so

$$r_{2k}(i)\ \text{is determined by the pair}\ \big(r_k(i),\ r_k(i+k)\big),\qquad r_k(i+k)=-1 \text{ if } i+k\ge n.$$

($-1$ because an empty block is smaller than anything: a shorter string is smaller than its extensions.)
Start with $r_1$ = character codes, double $k$ until all ranks are distinct ($\lceil\log_2 n\rceil$ rounds). Each round is a sort of $n$ pairs:

- comparison sort: $O(n\log n)$ per round, $O(n\log^2 n)$ total — short, often fast enough for $n\le2\cdot10^5$;
- **counting (radix) sort**: pairs have components in $[-1,n)$, so two stable counting passes (by second component, then by first) cost $O(n)$ per round, $O(n\log n)$ total.

A clean way to avoid the "$-1$ past the end" case: append a sentinel smaller than every character and sort **cyclic shifts** of $s\$$. Because $\$$ is unique and smallest, comparing two cyclic shifts is decided at or before the first $\$$, so the order of cyclic shifts equals the order of suffixes. Then $i+k$ is taken modulo $n+1$ and every block has full length.
Bonus of the radix version: the shifts are already sorted by their second halves — the shift starting at $\mathrm{SA}[j]-k$ has second half starting at $\mathrm{SA}[j]$ — so the first counting pass is free.

### 1.4 Kasai: the LCP array in $O(n)$

Computing each $\mathrm{lcp}[i]$ by direct comparison is $O(n^2)$ on `aaaa…`. Kasai's observation removes the waste:

**Lemma.** Let $h=\mathrm{LCP}(i,\mathrm{pred}(i))$ where $\mathrm{pred}(i)$ is the suffix just before $i$ in sorted order. Then $\mathrm{LCP}(i+1,\mathrm{pred}(i+1))\ge h-1$.

*Proof.* If $h\le1$ there is nothing to show. Otherwise write $j=\mathrm{pred}(i)$; suffixes $j$ and $i$ share their first character, so dropping it preserves the order: $j+1<i+1$ and $\mathrm{LCP}(j+1,i+1)=h-1$. $\mathrm{pred}(i+1)$ is the largest suffix below $i+1$, so it lies between $j+1$ and $i+1$ in sorted order (or equals $j+1$). Every suffix sorted between two strings that share a prefix of length $h-1$ also has that prefix. ∎

So process suffixes in text order $i=0,1,\dots$, keep the current $h$, decrease it by one per step and extend by direct comparison. $h\le n$ and it drops by at most $n$ in total, so all extensions cost $O(n)$.

### 1.5 LCP of any two suffixes = range minimum

**Lemma.** For ranks $a<b$: $\mathrm{LCP}(\mathrm{SA}[a],\mathrm{SA}[b])=\min_{a<t\le b}\mathrm{lcp}[t]$.

*Proof.* ($\le$) Every suffix sorted between $\mathrm{SA}[a]$ and $\mathrm{SA}[b]$ starts with their common prefix, so every adjacent LCP in the range is at least it. ($\ge$) $\mathrm{LCP}(x,z)\ge\min(\mathrm{LCP}(x,y),\mathrm{LCP}(y,z))$ for any strings; chain it along the range. ∎

With a [sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md) over $\mathrm{lcp}$ this is $O(1)$ per query after $O(n\log n)$ preprocessing — comparing any two substrings in $O(1)$, deterministically (the alternative is [hashing](01-string-hashing.md) + binary search in $O(\log n)$, with a failure probability).

### 1.6 Counting substrings with the LCP array

Walk the suffixes in sorted order. Suffix $\mathrm{SA}[i]$ has $n-\mathrm{SA}[i]$ prefixes; the first $\mathrm{lcp}[i]$ of them already appeared as prefixes of $\mathrm{SA}[i-1]$ (and by the RMQ lemma, any prefix shared with an *earlier* suffix is shared with the immediate predecessor). The others are new. Hence

$$\#\text{distinct substrings}=\sum_{i}\big(n-\mathrm{SA}[i]-\mathrm{lcp}[i]\big)=\frac{n(n+1)}{2}-\sum_i\mathrm{lcp}[i],$$

and the new substrings contributed by $\mathrm{SA}[i]$ — lengths $\mathrm{lcp}[i]+1,\dots,n-\mathrm{SA}[i]$ — come in increasing lexicographic order, after everything contributed by earlier suffixes. That single fact gives the $k$-th distinct substring by a linear walk.

## 2. Formulas, definitions and identities

| Identity | Meaning / proof sketch |
|---|---|
| $r_{2k}(i)\leftrightarrow(r_k(i),r_k(i+k))$ | doubling (§1.3); $\lceil\log_2 n\rceil$ rounds |
| $\mathrm{LCP}(i+1,\mathrm{pred}(i+1))\ge\mathrm{LCP}(i,\mathrm{pred}(i))-1$ | Kasai (§1.4), $O(n)$ |
| $\mathrm{LCP}(\mathrm{SA}[a],\mathrm{SA}[b])=\min_{a<t\le b}\mathrm{lcp}[t]$ | RMQ lemma (§1.5) |
| $\#\text{distinct}=\tfrac{n(n+1)}2-\sum\mathrm{lcp}$ | new prefixes per suffix (§1.6) |
| longest repeated substring $=\max_i\mathrm{lcp}[i]$ | a repeat is a common prefix of two suffixes, maximised by neighbours |
| $\#\text{distinct of length }L=\#\{i:n-\mathrm{SA}[i]\ge L\}-\#\{i:\mathrm{lcp}[i]\ge L\}$ | per-length version of §1.6 (difference array) |
| $\mathrm{occ}(p)=$ size of the SA block of suffixes with prefix $p$ | two binary searches, $O(\lvert p\rvert\log n)$ |
| $\sum_{i<j}\mathrm{LCP}(i,j)=\sum_{1\le a\le b<n}\min\mathrm{lcp}[a..b]$ | sum of subarray minima, monotonic stack $O(n)$ |
| $\sum_{p}\binom{\mathrm{occ}(p)+1}{2}=\tfrac{n(n+1)}2+\sum_{i<j}\mathrm{LCP}(i,j)$ | each pair of equal occurrences ↔ a pair of suffixes and a length $\le$ their LCP |
| LCS$(a,b)=\max\{\mathrm{lcp}[i]:\mathrm{SA}[i-1],\mathrm{SA}[i]$ on different sides of $a\#b\}$ | the optimal pair's SA range contains an adjacent cross pair |
| comparing $s[i..i+L)$ with $s[j..j+L)$ | equal iff $\mathrm{LCP}(i,j)\ge L$, else compare the first differing character |

| Operation | Cost |
|---|---|
| SA by comparison-sort doubling | $O(n\log^2 n)$ |
| SA by radix doubling | $O(n\log n)$ time, $O(n)$ memory |
| SA-IS / DC3 (linear) | $O(n)$, rarely needed |
| Kasai LCP | $O(n)$ |
| sparse table on LCP | $O(n\log n)$ build, $O(1)$ query |
| pattern occurrence count | $O(\lvert p\rvert\log n)$ |

## 3. Implementation (C++ and Java)

### 3.1 The short $O(n\log^2 n)$ version

Input: a string $s$. Output: $\mathrm{SA}$ (0-based) on one line. Use this when $n\le2\cdot10^5$ and time is not tight; it is the version to write under pressure.
In Java, the pair and the index are packed into one `long` and sorted as primitives — no `Integer[]`, no comparator objects.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> suffixArraySimple(const string& s) {
    int n = s.size();
    vector<int> sa(n), rk(n), tmp(n);
    for (int i = 0; i < n; i++) { sa[i] = i; rk[i] = (unsigned char)s[i]; }
    for (int k = 1;; k <<= 1) {
        auto key = [&](int i) { return pair<int, int>(rk[i], i + k < n ? rk[i + k] : -1); };
        sort(sa.begin(), sa.end(), [&](int a, int b) { return key(a) < key(b); });
        tmp[sa[0]] = 0;
        for (int i = 1; i < n; i++) tmp[sa[i]] = tmp[sa[i - 1]] + (key(sa[i - 1]) < key(sa[i]) ? 1 : 0);
        rk = tmp;
        if (rk[sa[n - 1]] == n - 1) break;     // all ranks distinct: fully sorted
    }
    return sa;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s;
    cin >> s;
    vector<int> sa = suffixArraySimple(s);
    for (int i = 0; i < (int)sa.size(); i++) cout << sa[i] << (i + 1 < (int)sa.size() ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    // n < 2^21: key = rank (21 bits) | second rank + 1 (21 bits) | index (21 bits)
    static int[] suffixArraySimple(String s) {
        int n = s.length();
        int[] rk = new int[n], sa = new int[n];
        long[] key = new long[n];
        final long MASK = (1L << 21) - 1;
        for (int i = 0; i < n; i++) rk[i] = s.charAt(i);
        for (int k = 1;; k <<= 1) {
            for (int i = 0; i < n; i++) {
                long second = i + k < n ? rk[i + k] + 1 : 0;          // 0 = block runs off the end
                key[i] = ((long) rk[i] << 42) | (second << 21) | i;
            }
            Arrays.sort(key);
            int[] tmp = new int[n];
            for (int i = 0; i < n; i++) sa[i] = (int) (key[i] & MASK);
            for (int i = 1; i < n; i++) tmp[sa[i]] = tmp[sa[i - 1]] + ((key[i] >>> 21) != (key[i - 1] >>> 21) ? 1 : 0);
            rk = tmp;
            if (rk[sa[n - 1]] == n - 1) break;
        }
        return sa;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int[] sa = suffixArraySimple(in.next());
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < sa.length; i++) sb.append(sa[i]).append(i + 1 < sa.length ? ' ' : '\n');
        out.print(sb);
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
banana
out:
5 3 1 0 4 2
-->
<!-- test
in:
aaaa
out:
3 2 1 0
-->
<!-- test
in:
x
out:
0
-->

### 3.2 $O(n\log n)$ radix doubling and Kasai's LCP

Input: $s$. Output: line 1 the suffix array, line 2 the LCP array ($\mathrm{lcp}[0]=0$, $\mathrm{lcp}[i]=\mathrm{LCP}(\mathrm{SA}[i-1],\mathrm{SA}[i])$).
`suffixArray` sorts the cyclic shifts of $s$ + sentinel (value 0, smaller than every character) and drops the sentinel at the end.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> suffixArray(const string& str) {
    int n = str.size() + 1;                       // + sentinel
    vector<int> s(n, 0);
    for (int i = 0; i + 1 < n; i++) s[i] = (unsigned char)str[i] + 1;
    vector<int> p(n), c(n), pn(n), cn(n), cnt(max(n, 257), 0);
    for (int x : s) cnt[x]++;
    for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
    for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
    int classes = 1;
    c[p[0]] = 0;
    for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
    for (int len = 1; len < n && classes < n; len <<= 1) {
        for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;    // sorted by second half already
        fill(cnt.begin(), cnt.begin() + classes, 0);
        for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
        for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];  // stable sort by first half
        cn[p[0]] = 0; classes = 1;
        for (int i = 1; i < n; i++) {
            int a = p[i], b = p[i - 1];
            if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
            cn[a] = classes - 1;
        }
        swap(c, cn);
    }
    p.erase(p.begin());                           // p[0] is the sentinel
    return p;
}

vector<int> lcpArray(const string& s, const vector<int>& sa) {   // Kasai
    int n = s.size();
    vector<int> rank(n), lcp(n, 0);
    for (int i = 0; i < n; i++) rank[sa[i]] = i;
    for (int i = 0, h = 0; i < n; i++) {
        if (rank[i] == 0) { h = 0; continue; }
        int j = sa[rank[i] - 1];
        while (i + h < n && j + h < n && s[i + h] == s[j + h]) h++;
        lcp[rank[i]] = h;
        if (h > 0) h--;                           // the lemma: next LCP >= h - 1
    }
    return lcp;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s;
    cin >> s;
    vector<int> sa = suffixArray(s), lcp = lcpArray(s, sa);
    int n = s.size();
    for (int i = 0; i < n; i++) cout << sa[i] << (i + 1 < n ? ' ' : '\n');
    for (int i = 0; i < n; i++) cout << lcp[i] << (i + 1 < n ? ' ' : '\n');
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] suffixArray(String str) {
        int n = str.length() + 1;
        int[] s = new int[n];
        for (int i = 0; i + 1 < n; i++) s[i] = str.charAt(i) + 1;    // ASCII input assumed
        int[] p = new int[n], c = new int[n], pn = new int[n], cn = new int[n], cnt = new int[Math.max(n, 257)];
        for (int x : s) cnt[x]++;
        for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
        int classes = 1;
        for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
        for (int len = 1; len < n && classes < n; len <<= 1) {
            for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
            Arrays.fill(cnt, 0, classes, 0);
            for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
            for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
            for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
            cn[p[0]] = 0; classes = 1;
            for (int i = 1; i < n; i++) {
                int a = p[i], b = p[i - 1];
                if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
                cn[a] = classes - 1;
            }
            int[] t = c; c = cn; cn = t;
        }
        return Arrays.copyOfRange(p, 1, n);
    }

    static int[] lcpArray(String s, int[] sa) {
        int n = s.length();
        int[] rank = new int[n], lcp = new int[n];
        for (int i = 0; i < n; i++) rank[sa[i]] = i;
        for (int i = 0, h = 0; i < n; i++) {
            if (rank[i] == 0) { h = 0; continue; }
            int j = sa[rank[i] - 1];
            while (i + h < n && j + h < n && s.charAt(i + h) == s.charAt(j + h)) h++;
            lcp[rank[i]] = h;
            if (h > 0) h--;
        }
        return lcp;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        int[] sa = suffixArray(s), lcp = lcpArray(s, sa);
        int n = s.length();
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.append(sa[i]).append(i + 1 < n ? ' ' : '\n');
        for (int i = 0; i < n; i++) sb.append(lcp[i]).append(i + 1 < n ? ' ' : '\n');
        out.print(sb);
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
banana
out:
5 3 1 0 4 2
0 1 3 0 0 2
-->
<!-- test
in:
abab
out:
2 0 3 1
0 2 0 1
-->
<!-- test
in:
z
out:
0
0
-->

### 3.3 LCP of arbitrary suffixes and pattern counting

Input: $s$, then $q$ queries, each `1 i j` (1-based positions: print $\mathrm{LCP}$ of the suffixes starting at $i$ and $j$) or `2 p` (print the number of occurrences of $p$ in $s$).
The suffix-array and Kasai functions are those of §3.2, compacted.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> suffixArray(const string& str) {        // §3.2
    int n = str.size() + 1;
    vector<int> s(n, 0), p(n), c(n), pn(n), cn(n), cnt(max(n, 257), 0);
    for (int i = 0; i + 1 < n; i++) s[i] = (unsigned char)str[i] + 1;
    for (int x : s) cnt[x]++;
    for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
    for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
    int classes = 1;
    for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
    for (int len = 1; len < n && classes < n; len <<= 1) {
        for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
        fill(cnt.begin(), cnt.begin() + classes, 0);
        for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
        for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
        cn[p[0]] = 0; classes = 1;
        for (int i = 1; i < n; i++) {
            int a = p[i], b = p[i - 1];
            if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
            cn[a] = classes - 1;
        }
        swap(c, cn);
    }
    p.erase(p.begin());
    return p;
}
vector<int> lcpArray(const string& s, const vector<int>& sa) {
    int n = s.size();
    vector<int> rank(n), lcp(n, 0);
    for (int i = 0; i < n; i++) rank[sa[i]] = i;
    for (int i = 0, h = 0; i < n; i++) {
        if (rank[i] == 0) { h = 0; continue; }
        int j = sa[rank[i] - 1];
        while (i + h < n && j + h < n && s[i + h] == s[j + h]) h++;
        lcp[rank[i]] = h;
        if (h > 0) h--;
    }
    return lcp;
}

struct SparseMin {
    vector<vector<int>> t;
    explicit SparseMin(const vector<int>& a) {
        int n = a.size(), K = 1;
        while ((1 << K) <= n) K++;
        t.assign(K, a);
        for (int k = 1; k < K; k++)
            for (int i = 0; i + (1 << k) <= n; i++) t[k][i] = min(t[k - 1][i], t[k - 1][i + (1 << (k - 1))]);
    }
    int query(int l, int r) const {                  // min of a[l..r], l <= r
        int k = 31 - __builtin_clz(r - l + 1);
        return min(t[k][l], t[k][r - (1 << k) + 1]);
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; int q;
    cin >> s >> q;
    int n = s.size();
    vector<int> sa = suffixArray(s), lcp = lcpArray(s, sa), rank(n);
    for (int i = 0; i < n; i++) rank[sa[i]] = i;
    SparseMin rmq(lcp);
    auto cmpPrefix = [&](int start, const string& p) {  // compare s[start..start+|p|) with p
        return s.compare(start, p.size(), p);
    };
    while (q--) {
        int type; cin >> type;
        if (type == 1) {
            int i, j; cin >> i >> j; i--; j--;
            if (i == j) { cout << n - i << '\n'; continue; }
            int a = rank[i], b = rank[j];
            if (a > b) swap(a, b);
            cout << rmq.query(a + 1, b) << '\n';
        } else {
            string p; cin >> p;
            int lo = 0, hi = n;                           // first suffix with prefix >= p
            while (lo < hi) { int m = (lo + hi) / 2; if (cmpPrefix(sa[m], p) < 0) lo = m + 1; else hi = m; }
            int first = lo;
            hi = n;                                       // first suffix with prefix > p
            while (lo < hi) { int m = (lo + hi) / 2; if (cmpPrefix(sa[m], p) <= 0) lo = m + 1; else hi = m; }
            cout << lo - first << '\n';
        }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] suffixArray(String str) {               // §3.2
        int n = str.length() + 1;
        int[] s = new int[n], p = new int[n], c = new int[n], pn = new int[n], cn = new int[n], cnt = new int[Math.max(n, 257)];
        for (int i = 0; i + 1 < n; i++) s[i] = str.charAt(i) + 1;
        for (int x : s) cnt[x]++;
        for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
        int classes = 1;
        for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
        for (int len = 1; len < n && classes < n; len <<= 1) {
            for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
            Arrays.fill(cnt, 0, classes, 0);
            for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
            for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
            for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
            cn[p[0]] = 0; classes = 1;
            for (int i = 1; i < n; i++) {
                int a = p[i], b = p[i - 1];
                if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
                cn[a] = classes - 1;
            }
            int[] t = c; c = cn; cn = t;
        }
        return Arrays.copyOfRange(p, 1, n);
    }
    static int[] lcpArray(String s, int[] sa) {
        int n = s.length();
        int[] rank = new int[n], lcp = new int[n];
        for (int i = 0; i < n; i++) rank[sa[i]] = i;
        for (int i = 0, h = 0; i < n; i++) {
            if (rank[i] == 0) { h = 0; continue; }
            int j = sa[rank[i] - 1];
            while (i + h < n && j + h < n && s.charAt(i + h) == s.charAt(j + h)) h++;
            lcp[rank[i]] = h;
            if (h > 0) h--;
        }
        return lcp;
    }

    // negative / zero / positive like compareTo; a suffix shorter than p that is a prefix of p is smaller
    static int cmpPrefix(String s, int start, String p) {
        for (int t = 0; t < p.length(); t++) {
            if (start + t == s.length()) return -1;
            int d = s.charAt(start + t) - p.charAt(t);
            if (d != 0) return d;
        }
        return 0;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        int q = in.nextInt(), n = s.length();
        int[] sa = suffixArray(s), lcp = lcpArray(s, sa), rank = new int[n];
        for (int i = 0; i < n; i++) rank[sa[i]] = i;
        int K = 1;
        while ((1 << K) <= n) K++;
        int[][] sp = new int[K][];
        sp[0] = lcp;
        for (int k = 1; k < K; k++) {
            sp[k] = new int[n];
            for (int i = 0; i + (1 << k) <= n; i++) sp[k][i] = Math.min(sp[k - 1][i], sp[k - 1][i + (1 << (k - 1))]);
        }
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            int type = in.nextInt();
            if (type == 1) {
                int i = in.nextInt() - 1, j = in.nextInt() - 1;
                if (i == j) { sb.append(n - i).append('\n'); continue; }
                int a = Math.min(rank[i], rank[j]) + 1, b = Math.max(rank[i], rank[j]);
                int k = 31 - Integer.numberOfLeadingZeros(b - a + 1);
                sb.append(Math.min(sp[k][a], sp[k][b - (1 << k) + 1])).append('\n');
            } else {
                String p = in.next();
                int lo = 0, hi = n;
                while (lo < hi) { int m = (lo + hi) >>> 1; if (cmpPrefix(s, sa[m], p) < 0) lo = m + 1; else hi = m; }
                int first = lo;
                hi = n;
                while (lo < hi) { int m = (lo + hi) >>> 1; if (cmpPrefix(s, sa[m], p) <= 0) lo = m + 1; else hi = m; }
                sb.append(lo - first).append('\n');
            }
        }
        out.print(sb);
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
banana
6
1 2 4
1 1 6
1 3 3
2 ana
2 nab
2 a
out:
3
0
4
2
0
3
-->
<!-- test
in:
aaaa
3
1 1 2
2 aaaaa
2 aa
out:
3
0
3
-->

## 4. Recognising the pattern

- **"Number of distinct substrings"**, "distinct substrings of each length", "distinct substrings satisfying a prefix-monotone property" → SA + LCP, one pass (§1.6). Same for "longest substring occurring at least twice" ($\max\mathrm{lcp}$).
- **"$k$-th lexicographically smallest substring"** → walk the SA, each suffix contributes $n-\mathrm{SA}[i]-\mathrm{lcp}[i]$ new substrings in order.
- **Lexicographic comparisons of substrings, many times** (sorting substrings, comparing $s[l_1..r_1]$ with $s[l_2..r_2]$) → rank + LCP-RMQ in $O(1)$.
- **Two or more strings, "longest common substring", "shortest substring unique to both"** → SA of the concatenation with distinct separators; scan adjacent pairs / windows of the SA.
- **"Sum over all pairs of suffixes of LCP"**, "sum over substrings of $\mathrm{occ}^2$" → LCP array + monotonic stack (sum of subarray minima) or DSU merging by decreasing LCP.
- **Queries "how many times does $p$ occur"** with the text fixed → binary search on SA (or a suffix automaton).
- **Confused with:** hashing + binary search (simpler, $O(\log n)$ per comparison, probabilistic), [suffix automaton](08-suffix-automaton.md) (better for online/occurrence counting, worse for lexicographic order), [Z-function](03-z-function.md) (only LCPs with the *whole* string).

## 5. Worked examples (graded)

### Example 1 — Distinct substrings · ★ ≈1900 (est.)

- **Source:** [CSES 2105 · Distinct Substrings](https://cses.fi/problemset/task/2105) (also [AtCoder PRACTICE2 I · Number of Substrings](https://atcoder.jp/contests/practice2/tasks/practice2_i)).
- **Difficulty:** ≈1900 (est.)
- **Problem:** count the distinct substrings of a string of length $n\le10^5$.
- **Thinking from first principles:** a hash set of all substrings is $\Theta(n^2)$ items. Every substring is a prefix of a suffix; in sorted order, a prefix shared with any earlier suffix is shared with the immediate predecessor (RMQ lemma), so each suffix adds exactly $n-\mathrm{SA}[i]-\mathrm{lcp}[i]$ new substrings.

<details><summary>Solution</summary>

Answer $=\frac{n(n+1)}2-\sum\mathrm{lcp}[i]$, in 64-bit ($\approx5\cdot10^9$ for $n=10^5$). $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> suffixArray(const string& str) {        // §3.2
    int n = str.size() + 1;
    vector<int> s(n, 0), p(n), c(n), pn(n), cn(n), cnt(max(n, 257), 0);
    for (int i = 0; i + 1 < n; i++) s[i] = (unsigned char)str[i] + 1;
    for (int x : s) cnt[x]++;
    for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
    for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
    int classes = 1;
    for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
    for (int len = 1; len < n && classes < n; len <<= 1) {
        for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
        fill(cnt.begin(), cnt.begin() + classes, 0);
        for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
        for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
        cn[p[0]] = 0; classes = 1;
        for (int i = 1; i < n; i++) {
            int a = p[i], b = p[i - 1];
            if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
            cn[a] = classes - 1;
        }
        swap(c, cn);
    }
    p.erase(p.begin());
    return p;
}
vector<int> lcpArray(const string& s, const vector<int>& sa) {
    int n = s.size();
    vector<int> rank(n), lcp(n, 0);
    for (int i = 0; i < n; i++) rank[sa[i]] = i;
    for (int i = 0, h = 0; i < n; i++) {
        if (rank[i] == 0) { h = 0; continue; }
        int j = sa[rank[i] - 1];
        while (i + h < n && j + h < n && s[i + h] == s[j + h]) h++;
        lcp[rank[i]] = h;
        if (h > 0) h--;
    }
    return lcp;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s;
    cin >> s;
    long long n = s.size(), ans = n * (n + 1) / 2;
    for (int x : lcpArray(s, suffixArray(s))) ans -= x;
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] suffixArray(String str) {               // §3.2
        int n = str.length() + 1;
        int[] s = new int[n], p = new int[n], c = new int[n], pn = new int[n], cn = new int[n], cnt = new int[Math.max(n, 257)];
        for (int i = 0; i + 1 < n; i++) s[i] = str.charAt(i) + 1;
        for (int x : s) cnt[x]++;
        for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
        int classes = 1;
        for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
        for (int len = 1; len < n && classes < n; len <<= 1) {
            for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
            Arrays.fill(cnt, 0, classes, 0);
            for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
            for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
            for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
            cn[p[0]] = 0; classes = 1;
            for (int i = 1; i < n; i++) {
                int a = p[i], b = p[i - 1];
                if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
                cn[a] = classes - 1;
            }
            int[] t = c; c = cn; cn = t;
        }
        return Arrays.copyOfRange(p, 1, n);
    }
    static int[] lcpArray(String s, int[] sa) {
        int n = s.length();
        int[] rank = new int[n], lcp = new int[n];
        for (int i = 0; i < n; i++) rank[sa[i]] = i;
        for (int i = 0, h = 0; i < n; i++) {
            if (rank[i] == 0) { h = 0; continue; }
            int j = sa[rank[i] - 1];
            while (i + h < n && j + h < n && s.charAt(i + h) == s.charAt(j + h)) h++;
            lcp[rank[i]] = h;
            if (h > 0) h--;
        }
        return lcp;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        long n = s.length(), ans = n * (n + 1) / 2;
        for (int x : lcpArray(s, suffixArray(s))) ans -= x;
        out.println(ans);
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
abaa
out:
8
-->
<!-- test
in:
aaaa
out:
4
-->
<!-- test
in:
q
out:
1
-->

</details>

### Example 2 — Longest common substring of two strings · ★ ≈2000 (est.)

- **Source:** Original problem (the array version is [LC 718 · Maximum Length of Repeated Subarray](https://leetcode.com/problems/maximum-length-of-repeated-subarray/) — Medium, where $O(nm)$ DP is intended).
- **Difficulty:** ≈2000 (est.)
- **Problem:** given strings $a,b$ ($|a|,|b|\le10^5$, lowercase), find the length of their longest common substring.
- **Thinking from first principles:** the $O(|a||b|)$ DP is $10^{10}$. A common substring is a common prefix of a suffix of $a$ and a suffix of $b$. Put both families of suffixes in one sorted list: build the SA of $u=a\#b$ with a separator that occurs nowhere else (it stops every common prefix from crossing the boundary). Take the best pair $(x\in A, y\in B)$; somewhere in the SA range between them there is an *adjacent* pair with one suffix from each side, and by the RMQ lemma its LCP is at least $\mathrm{LCP}(x,y)$. So only adjacent pairs need checking.

<details><summary>Solution</summary>

Answer $=\max\{\mathrm{lcp}[i] : (\mathrm{SA}[i-1]<|a|)\ne(\mathrm{SA}[i]<|a|)\}$. The suffix starting at the separator itself is on the "$b$ side" by this test but its LCP with anything is 0, so it is harmless. $O((|a|+|b|)\log)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> suffixArray(const string& str) {        // §3.2
    int n = str.size() + 1;
    vector<int> s(n, 0), p(n), c(n), pn(n), cn(n), cnt(max(n, 257), 0);
    for (int i = 0; i + 1 < n; i++) s[i] = (unsigned char)str[i] + 1;
    for (int x : s) cnt[x]++;
    for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
    for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
    int classes = 1;
    for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
    for (int len = 1; len < n && classes < n; len <<= 1) {
        for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
        fill(cnt.begin(), cnt.begin() + classes, 0);
        for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
        for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
        cn[p[0]] = 0; classes = 1;
        for (int i = 1; i < n; i++) {
            int a = p[i], b = p[i - 1];
            if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
            cn[a] = classes - 1;
        }
        swap(c, cn);
    }
    p.erase(p.begin());
    return p;
}
vector<int> lcpArray(const string& s, const vector<int>& sa) {
    int n = s.size();
    vector<int> rank(n), lcp(n, 0);
    for (int i = 0; i < n; i++) rank[sa[i]] = i;
    for (int i = 0, h = 0; i < n; i++) {
        if (rank[i] == 0) { h = 0; continue; }
        int j = sa[rank[i] - 1];
        while (i + h < n && j + h < n && s[i + h] == s[j + h]) h++;
        lcp[rank[i]] = h;
        if (h > 0) h--;
    }
    return lcp;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string a, b;
    cin >> a >> b;
    string u = a + '#' + b;                        // '#' < 'a' and occurs nowhere else
    vector<int> sa = suffixArray(u), lcp = lcpArray(u, sa);
    int A = a.size(), best = 0;
    for (int i = 1; i < (int)u.size(); i++)
        if ((sa[i - 1] < A) != (sa[i] < A)) best = max(best, lcp[i]);
    cout << best << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] suffixArray(String str) {               // §3.2
        int n = str.length() + 1;
        int[] s = new int[n], p = new int[n], c = new int[n], pn = new int[n], cn = new int[n], cnt = new int[Math.max(n, 257)];
        for (int i = 0; i + 1 < n; i++) s[i] = str.charAt(i) + 1;
        for (int x : s) cnt[x]++;
        for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
        int classes = 1;
        for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
        for (int len = 1; len < n && classes < n; len <<= 1) {
            for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
            Arrays.fill(cnt, 0, classes, 0);
            for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
            for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
            for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
            cn[p[0]] = 0; classes = 1;
            for (int i = 1; i < n; i++) {
                int a = p[i], b = p[i - 1];
                if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
                cn[a] = classes - 1;
            }
            int[] t = c; c = cn; cn = t;
        }
        return Arrays.copyOfRange(p, 1, n);
    }
    static int[] lcpArray(String s, int[] sa) {
        int n = s.length();
        int[] rank = new int[n], lcp = new int[n];
        for (int i = 0; i < n; i++) rank[sa[i]] = i;
        for (int i = 0, h = 0; i < n; i++) {
            if (rank[i] == 0) { h = 0; continue; }
            int j = sa[rank[i] - 1];
            while (i + h < n && j + h < n && s.charAt(i + h) == s.charAt(j + h)) h++;
            lcp[rank[i]] = h;
            if (h > 0) h--;
        }
        return lcp;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String a = in.next(), b = in.next(), u = a + "#" + b;
        int[] sa = suffixArray(u), lcp = lcpArray(u, sa);
        int A = a.length(), best = 0;
        for (int i = 1; i < u.length(); i++)
            if ((sa[i - 1] < A) != (sa[i] < A)) best = Math.max(best, lcp[i]);
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
xabcy
zabcw
out:
3
-->
<!-- test
in:
aaa
b
out:
0
-->
<!-- test
in:
abab
baba
out:
3
-->

</details>

### Example 3 — The $k$-th smallest distinct substring · ★ ≈2100 (est.)

- **Source:** [CSES 2108 · Substring Order I](https://cses.fi/problemset/task/2108)
- **Difficulty:** ≈2100 (est.)
- **Problem:** string $s$ ($n\le10^5$) and $k$ (at most the number of distinct substrings). Print the $k$-th smallest distinct substring in lexicographic order.
- **Thinking from first principles:** we cannot list $\Theta(n^2)$ substrings. Group them by the first suffix (in sorted order) that has them as a prefix: suffix $\mathrm{SA}[i]$ "owns" its prefixes of lengths $\mathrm{lcp}[i]+1..n-\mathrm{SA}[i]$. A substring owned by $\mathrm{SA}[i]$ is longer than its common prefix with every earlier suffix, so it is larger than everything owned by earlier suffixes; within one owner, longer prefixes are larger. So the owned groups are consecutive blocks of the sorted list.

<details><summary>Solution</summary>

For $i=0..n-1$: $\mathrm{new}=n-\mathrm{SA}[i]-\mathrm{lcp}[i]$; if $k\le\mathrm{new}$ the answer is $s.\mathrm{substr}(\mathrm{SA}[i],\ \mathrm{lcp}[i]+k)$, else $k\mathrel{-}=\mathrm{new}$. $O(n\log n)$; $k$ needs 64 bits.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> suffixArray(const string& str) {        // §3.2
    int n = str.size() + 1;
    vector<int> s(n, 0), p(n), c(n), pn(n), cn(n), cnt(max(n, 257), 0);
    for (int i = 0; i + 1 < n; i++) s[i] = (unsigned char)str[i] + 1;
    for (int x : s) cnt[x]++;
    for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
    for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
    int classes = 1;
    for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
    for (int len = 1; len < n && classes < n; len <<= 1) {
        for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
        fill(cnt.begin(), cnt.begin() + classes, 0);
        for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
        for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
        cn[p[0]] = 0; classes = 1;
        for (int i = 1; i < n; i++) {
            int a = p[i], b = p[i - 1];
            if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
            cn[a] = classes - 1;
        }
        swap(c, cn);
    }
    p.erase(p.begin());
    return p;
}
vector<int> lcpArray(const string& s, const vector<int>& sa) {
    int n = s.size();
    vector<int> rank(n), lcp(n, 0);
    for (int i = 0; i < n; i++) rank[sa[i]] = i;
    for (int i = 0, h = 0; i < n; i++) {
        if (rank[i] == 0) { h = 0; continue; }
        int j = sa[rank[i] - 1];
        while (i + h < n && j + h < n && s[i + h] == s[j + h]) h++;
        lcp[rank[i]] = h;
        if (h > 0) h--;
    }
    return lcp;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; long long k;
    cin >> s >> k;
    int n = s.size();
    vector<int> sa = suffixArray(s), lcp = lcpArray(s, sa);
    for (int i = 0; i < n; i++) {
        long long fresh = n - sa[i] - lcp[i];
        if (k <= fresh) { cout << s.substr(sa[i], lcp[i] + k) << '\n'; return 0; }
        k -= fresh;
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] suffixArray(String str) {               // §3.2
        int n = str.length() + 1;
        int[] s = new int[n], p = new int[n], c = new int[n], pn = new int[n], cn = new int[n], cnt = new int[Math.max(n, 257)];
        for (int i = 0; i + 1 < n; i++) s[i] = str.charAt(i) + 1;
        for (int x : s) cnt[x]++;
        for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
        int classes = 1;
        for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
        for (int len = 1; len < n && classes < n; len <<= 1) {
            for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
            Arrays.fill(cnt, 0, classes, 0);
            for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
            for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
            for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
            cn[p[0]] = 0; classes = 1;
            for (int i = 1; i < n; i++) {
                int a = p[i], b = p[i - 1];
                if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
                cn[a] = classes - 1;
            }
            int[] t = c; c = cn; cn = t;
        }
        return Arrays.copyOfRange(p, 1, n);
    }
    static int[] lcpArray(String s, int[] sa) {
        int n = s.length();
        int[] rank = new int[n], lcp = new int[n];
        for (int i = 0; i < n; i++) rank[sa[i]] = i;
        for (int i = 0, h = 0; i < n; i++) {
            if (rank[i] == 0) { h = 0; continue; }
            int j = sa[rank[i] - 1];
            while (i + h < n && j + h < n && s.charAt(i + h) == s.charAt(j + h)) h++;
            lcp[rank[i]] = h;
            if (h > 0) h--;
        }
        return lcp;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        long k = in.nextLong();
        int n = s.length();
        int[] sa = suffixArray(s), lcp = lcpArray(s, sa);
        for (int i = 0; i < n; i++) {
            long fresh = n - sa[i] - lcp[i];
            if (k <= fresh) { out.println(s.substring(sa[i], sa[i] + lcp[i] + (int) k)); break; }
            k -= fresh;
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
banana 7
out:
ba
-->
<!-- test
in:
abc 3
out:
abc
-->
<!-- test
in:
aaa 3
out:
aaa
-->

</details>

### Example 4 — Sum of $\binom{\mathrm{occ}+1}{2}$ over all substrings · ★ 2300

- **Source:** [CF 123D · String](https://codeforces.com/problemset/problem/123/D) — 2300
- **Difficulty:** 2300
- **Problem:** for a string $s$ ($n\le10^5$), compute $\sum_{p}\frac{\mathrm{occ}(p)(\mathrm{occ}(p)+1)}2$ over all distinct substrings $p$, where $\mathrm{occ}(p)$ is the number of occurrences of $p$ in $s$ (in the statement this appears as the number of contiguous runs in the sorted list of occurrences).
- **Thinking from first principles:** there are $\Theta(n^2)$ distinct substrings, so we must count by a different index. Split $\binom{\mathrm{occ}+1}{2}=\mathrm{occ}+\binom{\mathrm{occ}}{2}$. The first part sums to the total number of substring occurrences, $\frac{n(n+1)}2$. The second counts triples (two different start positions $i<j$, a length $L$) with equal substrings — for a fixed pair that is $\mathrm{LCP}(i,j)$ choices of $L$. So we need $\sum_{i<j}\mathrm{LCP}(i,j)$, which by the RMQ lemma is the sum over all ranges $[a,b]$ of $\min\mathrm{lcp}[a..b]$: the classic "sum of subarray minima", solved by a monotonic stack (each $\mathrm{lcp}[t]$ is the minimum of $(t-\mathrm{prevLess}_t)(\mathrm{nextLessEq}_t-t)$ ranges).

<details><summary>Solution</summary>

Answer $=\frac{n(n+1)}2+\sum_{t=1}^{n-1}\mathrm{lcp}[t]\,(t-L_t)(R_t-t)$ with $L_t$ the previous index (in $1..n-1$, or $0$) with $\mathrm{lcp}<\mathrm{lcp}[t]$ and $R_t$ the next index with $\mathrm{lcp}\le\mathrm{lcp}[t]$ (or $n$). Strict on one side and non-strict on the other attributes each range to exactly one minimum (its rightmost). The result is at most about $n^3/6\approx1.7\cdot10^{14}$: 64-bit. $O(n\log n)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

vector<int> suffixArray(const string& str) {        // §3.2
    int n = str.size() + 1;
    vector<int> s(n, 0), p(n), c(n), pn(n), cn(n), cnt(max(n, 257), 0);
    for (int i = 0; i + 1 < n; i++) s[i] = (unsigned char)str[i] + 1;
    for (int x : s) cnt[x]++;
    for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
    for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
    int classes = 1;
    for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
    for (int len = 1; len < n && classes < n; len <<= 1) {
        for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
        fill(cnt.begin(), cnt.begin() + classes, 0);
        for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
        for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
        cn[p[0]] = 0; classes = 1;
        for (int i = 1; i < n; i++) {
            int a = p[i], b = p[i - 1];
            if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
            cn[a] = classes - 1;
        }
        swap(c, cn);
    }
    p.erase(p.begin());
    return p;
}
vector<int> lcpArray(const string& s, const vector<int>& sa) {
    int n = s.size();
    vector<int> rank(n), lcp(n, 0);
    for (int i = 0; i < n; i++) rank[sa[i]] = i;
    for (int i = 0, h = 0; i < n; i++) {
        if (rank[i] == 0) { h = 0; continue; }
        int j = sa[rank[i] - 1];
        while (i + h < n && j + h < n && s[i + h] == s[j + h]) h++;
        lcp[rank[i]] = h;
        if (h > 0) h--;
    }
    return lcp;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s;
    cin >> s;
    int n = s.size();
    vector<int> lcp = lcpArray(s, suffixArray(s));
    vector<int> L(n), R(n), st;
    for (int t = 1; t < n; t++) {                       // previous strictly smaller
        while (!st.empty() && lcp[st.back()] >= lcp[t]) st.pop_back();
        L[t] = st.empty() ? 0 : st.back();
        st.push_back(t);
    }
    st.clear();
    for (int t = n - 1; t >= 1; t--) {                  // next smaller or equal
        while (!st.empty() && lcp[st.back()] > lcp[t]) st.pop_back();
        R[t] = st.empty() ? n : st.back();
        st.push_back(t);
    }
    long long ans = 1LL * n * (n + 1) / 2;
    for (int t = 1; t < n; t++) ans += 1LL * lcp[t] * (t - L[t]) * (R[t] - t);
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static int[] suffixArray(String str) {               // §3.2
        int n = str.length() + 1;
        int[] s = new int[n], p = new int[n], c = new int[n], pn = new int[n], cn = new int[n], cnt = new int[Math.max(n, 257)];
        for (int i = 0; i + 1 < n; i++) s[i] = str.charAt(i) + 1;
        for (int x : s) cnt[x]++;
        for (int i = 1; i < 257; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[s[i]]] = i;
        int classes = 1;
        for (int i = 1; i < n; i++) { if (s[p[i]] != s[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
        for (int len = 1; len < n && classes < n; len <<= 1) {
            for (int i = 0; i < n; i++) pn[i] = (p[i] - len + n) % n;
            Arrays.fill(cnt, 0, classes, 0);
            for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
            for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
            for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
            cn[p[0]] = 0; classes = 1;
            for (int i = 1; i < n; i++) {
                int a = p[i], b = p[i - 1];
                if (c[a] != c[b] || c[(a + len) % n] != c[(b + len) % n]) classes++;
                cn[a] = classes - 1;
            }
            int[] t = c; c = cn; cn = t;
        }
        return Arrays.copyOfRange(p, 1, n);
    }
    static int[] lcpArray(String s, int[] sa) {
        int n = s.length();
        int[] rank = new int[n], lcp = new int[n];
        for (int i = 0; i < n; i++) rank[sa[i]] = i;
        for (int i = 0, h = 0; i < n; i++) {
            if (rank[i] == 0) { h = 0; continue; }
            int j = sa[rank[i] - 1];
            while (i + h < n && j + h < n && s.charAt(i + h) == s.charAt(j + h)) h++;
            lcp[rank[i]] = h;
            if (h > 0) h--;
        }
        return lcp;
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        int n = s.length();
        int[] lcp = lcpArray(s, suffixArray(s));
        int[] L = new int[n], R = new int[n], st = new int[n];
        int sp = 0;
        for (int t = 1; t < n; t++) {
            while (sp > 0 && lcp[st[sp - 1]] >= lcp[t]) sp--;
            L[t] = sp == 0 ? 0 : st[sp - 1];
            st[sp++] = t;
        }
        sp = 0;
        for (int t = n - 1; t >= 1; t--) {
            while (sp > 0 && lcp[st[sp - 1]] > lcp[t]) sp--;
            R[t] = sp == 0 ? n : st[sp - 1];
            st[sp++] = t;
        }
        long ans = (long) n * (n + 1) / 2;
        for (int t = 1; t < n; t++) ans += (long) lcp[t] * (t - L[t]) * (R[t] - t);
        out.println(ans);
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
aaaa
out:
20
-->
<!-- test
in:
abcdef
out:
21
-->
<!-- test
in:
abab
out:
13
-->

</details>

For `abab`: $a,b$ occur twice ($3+3$), $ab$ twice ($3$), $ba,aba,bab,abab$ once ($1+1+1+1$): $9+4=13$; via the formula, $\frac{4\cdot5}{2}=10$ plus the pair LCPs $\mathrm{LCP}(abab,ab)=2$ and $\mathrm{LCP}(bab,b)=1$ gives $13$.

## 6. Tricks, pitfalls and things to remember

1. **Sentinel and separators must be smaller than every real character and unique.** In §3.2 the sentinel is 0 and characters are shifted by $+1$. For several strings use distinct separators (or the sentinel trick on integer arrays: map strings to values $\ge K$ and use $0..K-1$ as separators), otherwise a common prefix can run across two separators.
2. **`lcp[i]` pairs $\mathrm{SA}[i-1]$ with $\mathrm{SA}[i]$** in this file; some libraries pair $i$ with $i+1$ and have length $n-1$. Off-by-one here breaks the RMQ range ($a+1..b$).
3. **Kasai is indexed by text position**, not by rank: the loop runs $i=0..n-1$ over positions and writes `lcp[rank[i]]`. Iterating by rank loses the amortisation and becomes $O(n^2)$.
4. **Reset $h$ when `rank[i] == 0`** (no predecessor). Forgetting it reads `sa[-1]`.
5. **$O(n\log^2 n)$ in Java**: never sort `Integer[]` with a lambda comparator for $n=2\cdot10^5$ — pack `(rank, rank2, index)` into a `long` and sort primitives (§3.1). Arrays.sort on `long[]` is a dual-pivot quicksort; inputs here are not adversarial for it, but if you sort values an opponent controls, shuffle first.
6. **Early exit when all classes are distinct** saves most rounds on random strings ($\approx\log_\sigma n$ rounds instead of $\log_2 n$).
7. **Distinct-substring counts overflow `int`** ($n=10^5$ gives $5\cdot10^9$). Use 64-bit for every sum over the LCP array.
8. **Binary search for a pattern compares only $|p|$ characters**; a suffix that is a proper prefix of $p$ is *smaller* than $p$. `std::string::compare(pos, len, p)` handles this; the Java helper in §3.3 returns $-1$ when the suffix ends first.
9. **Cyclic shifts for free.** §3.2 without the sentinel sorts cyclic shifts — exactly what "minimal rotation" ([CSES 1110 · Minimal Rotation](https://cses.fi/problemset/task/1110)) and the Burrows–Wheeler transform need.
10. **Memory:** the sparse table over LCP is $n\log n$ ints ($2\cdot10^5\cdot18\cdot4$ B $\approx$ 14 MB) — fine, but allocate it once, not per test case.

## 7. Going further (toward 2400–2600+)

- **LCP + DSU / small-to-large.** Process adjacent LCP values in *decreasing* order and union neighbouring SA positions: the components are exactly the sets of suffixes sharing a prefix of length $\ge$ the current value. Aggregates over components answer "best substring by $|t|\cdot f(\text{occurrences})$" — [CF 873F · Forbidden Indices](https://codeforces.com/problemset/problem/873/F) — 2400, [CF 1780G · Delicious Dessert](https://codeforces.com/problemset/problem/1780/G) — 2400. See [DSU](../08-Data-Structures/06-dsu-and-variants.md).
- **Sum of LCP over a query set of pairs.** Sort the query positions by rank, take adjacent LCPs via RMQ, and run the monotonic-stack sum per query — [CF 1073G · Yet Another LCP Problem](https://codeforces.com/problemset/problem/1073/G) — 2600.
- **Several strings at once.** SA of $s_1\#_1s_2\#_2\dots$ plus a sliding window over the SA that contains at least $k$ distinct owners gives "longest substring common to $\ge k$ strings" and per-string counts — [CF 204E · Little Elephant and Strings](https://codeforces.com/problemset/problem/204/E) — 2800, [CF 616F · Expensive Strings](https://codeforces.com/problemset/problem/616/F) — 2700.
- **Suffix tree for free.** The LCP array is the string depth of the lowest common ancestors of adjacent leaves; a Cartesian tree over it *is* the suffix tree's internal structure (a stack builds it in $O(n)$).
- **Linear-time construction.** SA-IS (induced sorting) and DC3 are $O(n)$; they matter for $n\ge10^7$ or many test cases. In contests the radix doubling is almost always enough.
- **Burrows–Wheeler transform** $\mathrm{BWT}[i]=s[\mathrm{SA}[i]-1]$ and its inverse via the LF-mapping — [CSES 1113 · String Transform](https://cses.fi/problemset/task/1113); FM-index pattern counting in $O(|p|)$.
- **Substrings with repetitions.** $k$-th substring counting duplicates needs, per suffix, how many *occurrences* each new prefix has — easier with a [suffix automaton](08-suffix-automaton.md) (its Example 3).

## 8. Practice ladder

**≤1900**
- [ ] [AtCoder ABC141 E · Who Says a Pun?](https://atcoder.jp/contests/abc141/tasks/abc141_e) — ≈1459 (AtCoder est.) — longest repeat that does not overlap
- [ ] [AtCoder PRACTICE2 I · Number of Substrings](https://atcoder.jp/contests/practice2/tasks/practice2_i) — ≈1700 (est.)
- [ ] [CSES 2105 · Distinct Substrings](https://cses.fi/problemset/task/2105) — ≈1900 (est.) — Example 1
- [ ] [CSES 2106 · Repeating Substring](https://cses.fi/problemset/task/2106) — ≈1900 (est.)
- [ ] [CSES 1110 · Minimal Rotation](https://cses.fi/problemset/task/1110) — ≈1800 (est.) — cyclic shifts
- [ ] [CF 271D · Good Substrings](https://codeforces.com/problemset/problem/271/D) — 1800 — distinct substrings under a constraint

**1900–2400**
- [ ] [CSES 2110 · Substring Distribution](https://cses.fi/problemset/task/2110) — ≈2000 (est.) — per-length counts
- [ ] [CSES 2108 · Substring Order I](https://cses.fi/problemset/task/2108) — ≈2100 (est.) — Example 3
- [ ] [CSES 3225 · Inverse Suffix Array](https://cses.fi/problemset/task/3225) — ≈2100 (est.)
- [ ] [CSES 1113 · String Transform](https://cses.fi/problemset/task/1113) — ≈2000 (est.) — BWT inverse
- [ ] [CF 128B · String](https://codeforces.com/problemset/problem/128/B) — 2100
- [ ] [CF 427D · Match & Catch](https://codeforces.com/problemset/problem/427/D) — 2200
- [ ] [CF 123D · String](https://codeforces.com/problemset/problem/123/D) — 2300 — Example 4
- [ ] [CF 802G3 · Fake News (hard)](https://codeforces.com/problemset/problem/802/G3) — 2300
- [ ] [AtCoder ARC044 D · suffix array](https://atcoder.jp/contests/arc044/tasks/arc044_d) — ≈2335 (AtCoder est.)

**2400+**
- [ ] [CF 873F · Forbidden Indices](https://codeforces.com/problemset/problem/873/F) — 2400
- [ ] [CF 1780G · Delicious Dessert](https://codeforces.com/problemset/problem/1780/G) — 2400
- [ ] [CF 653F · Paper task](https://codeforces.com/problemset/problem/653/F) — 2600
- [ ] [CF 1073G · Yet Another LCP Problem](https://codeforces.com/problemset/problem/1073/G) — 2600
- [ ] [CF 616F · Expensive Strings](https://codeforces.com/problemset/problem/616/F) — 2700
- [ ] [CF 204E · Little Elephant and Strings](https://codeforces.com/problemset/problem/204/E) — 2800
- [ ] [AtCoder ABC280 Ex · Substring Sort](https://atcoder.jp/contests/abc280/tasks/abc280_h) — ≈3307 (AtCoder est.)
- [ ] [CF 1063F · String Journey](https://codeforces.com/problemset/problem/1063/F) — 3300

## 9. LeetCode / FAANG cross-reference

- [LC 1044 · Longest Duplicate Substring](https://leetcode.com/problems/longest-duplicate-substring/) — Hard — $\max\mathrm{lcp}$; the usual interview answer is binary search + rolling hash, the SA answer is deterministic.
- [LC 1698 · Number of Distinct Substrings in a String](https://leetcode.com/problems/number-of-distinct-substrings-in-a-string/) — Medium 🔒 — Example 1.
- [LC 1062 · Longest Repeating Substring](https://leetcode.com/problems/longest-repeating-substring/) — Medium 🔒 — $\max\mathrm{lcp}$.
- [LC 718 · Maximum Length of Repeated Subarray](https://leetcode.com/problems/maximum-length-of-repeated-subarray/) — Medium — Example 2 on integer arrays (DP is intended for $n\le1000$).
- [LC 1923 · Longest Common Subpath](https://leetcode.com/problems/longest-common-subpath/) — Hard — SA over all paths with separators, then a window over the SA covering every path (or binary search + hashing).
- [LC 1163 · Last Substring in Lexicographical Order](https://leetcode.com/problems/last-substring-in-lexicographical-order/) — Hard — the answer is the suffix $\mathrm{SA}[n-1]$ (an $O(n)$ two-pointer trick exists).
- [LC 1754 · Largest Merge Of Two Strings](https://leetcode.com/problems/largest-merge-of-two-strings/) — Medium — greedy that repeatedly compares suffixes; SA of $a\#b$ makes each comparison $O(1)$.

Rare in interviews: suffix arrays are long to write and rarely expected; know that they exist and give $O(n\log n)$ deterministic answers where interviewers expect hashing.

## 10. Self-check

1. Why does the pair $(r_k(i),r_k(i+k))$ determine the order of length-$2k$ prefixes? What value represents "past the end", and why must it be the smallest?
2. Why does sorting cyclic shifts of $s\$$ give the suffix array of $s$?
3. State and prove Kasai's lemma. Why is the algorithm $O(n)$?
4. Prove $\mathrm{LCP}(\mathrm{SA}[a],\mathrm{SA}[b])=\min_{a<t\le b}\mathrm{lcp}[t]$.
5. Derive the number of distinct substrings from the LCP array.
6. How do you find the $k$-th distinct substring, and why are the substrings "owned" by one suffix consecutive in sorted order?
7. How do you get the longest common substring of two strings, and why do only adjacent SA pairs matter?
8. Express $\sum_p \binom{\mathrm{occ}(p)}{2}$ in terms of the LCP array and say how to compute it in $O(n)$.

<details><summary>Answers</summary>

1. The length-$2k$ prefix is the concatenation of two length-$k$ blocks; comparing concatenations of equal-length blocks is comparing the pairs lexicographically. "Past the end" is $-1$ (or 0 with ranks shifted): a string that ends is smaller than any extension of it.
2. The sentinel is unique and smallest, so two different cyclic shifts differ no later than the first sentinel in either; what comes after it never matters. The order of the shifts is therefore the order of the suffixes of $s\$$, whose first element is the suffix "$\$$" itself.
3. If $j=\mathrm{pred}(i)$ and $h=\mathrm{LCP}(i,j)>0$ then $j+1<i+1$ with LCP $h-1$, and $\mathrm{pred}(i+1)$ is sorted between them, so it shares those $h-1$ characters. $h$ decreases by at most one per position and never exceeds $n$, so the total number of character comparisons is $O(n)$.
4. Every suffix between two sorted suffixes shares their common prefix, so each adjacent LCP is at least it; conversely $\mathrm{LCP}(x,z)\ge\min(\mathrm{LCP}(x,y),\mathrm{LCP}(y,z))$ chained along the range.
5. Suffix $\mathrm{SA}[i]$ has $n-\mathrm{SA}[i]$ prefixes, of which exactly $\mathrm{lcp}[i]$ appeared earlier; sum: $\frac{n(n+1)}2-\sum\mathrm{lcp}$.
6. Walk the SA subtracting $n-\mathrm{SA}[i]-\mathrm{lcp}[i]$ from $k$; when it fits, output the prefix of length $\mathrm{lcp}[i]+k$. A substring owned by $\mathrm{SA}[i]$ is longer than its LCP with any earlier suffix, so it is larger than everything owned earlier, and smaller than anything owned later by symmetry.
7. SA of $a\#b$; maximum $\mathrm{lcp}[i]$ over adjacent pairs whose suffixes come from different strings. Between the optimal cross pair in SA order there is an adjacent cross pair, and its LCP is at least the range minimum, which equals the optimal pair's LCP.
8. It equals $\sum_{i<j}\mathrm{LCP}(i,j)=\sum_{1\le a\le b\le n-1}\min\mathrm{lcp}[a..b]$, the sum of subarray minima: monotonic stacks give previous-smaller and next-smaller-or-equal indices, and each $\mathrm{lcp}[t]$ contributes $\mathrm{lcp}[t]\cdot(t-L_t)\cdot(R_t-t)$.

</details>
