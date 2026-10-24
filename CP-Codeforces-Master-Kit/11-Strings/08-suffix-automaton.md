# Suffix automaton

> **Band:** 🟠 2200–2600 · **Priority:** ⚡ · **FAANG:** none · **Prerequisites:** [suffix array and LCP](07-suffix-array-and-lcp.md), [Aho–Corasick](06-aho-corasick.md), [DP on DAGs](../06-Dynamic-Programming/09-dp-on-dags-and-graphs.md)
> **You can say you know this when:** you can write the online construction with clones from memory, explain what a state and a suffix link *are* (endpos classes, the link tree), and answer distinct-substring counts, occurrence counts, longest common substring and $k$-th substring with one pass over states sorted by `len`.

## 1. First principles — why this works

### 1.1 The goal: one small automaton for all substrings

We want a structure for one string $s$ ($|s|=n$) that answers "is $t$ a substring?" in $O(|t|)$, and also counts: how many times $t$ occurs, how many distinct substrings exist, the $k$-th one.
A trie of all suffixes does this but has $\Theta(n^2)$ nodes. The waste: many trie nodes have **identical futures** — the same set of continuations — and an automaton only needs one state per future.

### 1.2 endpos classes

For a substring $t$ let $\mathrm{endpos}(t)$ be the set of positions where its occurrences end. Example: $s=\texttt{abcbc}$, $\mathrm{endpos}(\texttt{bc})=\mathrm{endpos}(\texttt{c})=\{2,4\}$, $\mathrm{endpos}(\texttt{abc})=\{2\}$.

Two substrings with the same endpos have the same set of continuations (a continuation $w$ is allowed iff some end position $e$ has $s[e+1..]$ starting with $w$). So merge substrings by endpos; each class is one state. Three lemmas make this tractable:

1. **Nested or disjoint.** For substrings $u,v$ with $|u|\le|v|$: if $u$ is a suffix of $v$ then $\mathrm{endpos}(v)\subseteq\mathrm{endpos}(u)$; otherwise the sets are disjoint (an end position shared by both would make $u$ a suffix of $v$).
2. **A class is an interval of suffix lengths.** All strings of one class are suffixes of the longest one, $\mathrm{longest}(v)$, and their lengths fill an interval $[\mathrm{minlen}(v),\mathrm{len}(v)]$: shortening a string can only grow its endpos (lemma 1), and once it grows it never shrinks back.
3. **Suffix links form a tree.** Let $\mathrm{link}(v)$ be the class of the longest suffix of $\mathrm{longest}(v)$ that is *not* in $v$. Then $\mathrm{len}(\mathrm{link}(v))=\mathrm{minlen}(v)-1$ and $\mathrm{endpos}(v)\subsetneq\mathrm{endpos}(\mathrm{link}(v))$. Links strictly decrease `len`, so they form a tree rooted at the class of the empty string; by lemma 1 the children of a state have disjoint endpos sets inside the parent's.

The link tree is a **laminar family** of subsets of $\{0..n-1\}$, which already bounds the number of states by $2n-1$ (a laminar family over $n$ elements in which every internal set either branches or contains an extra element has at most $2n-1$ members). It is also exactly the suffix tree of the reversed string.

### 1.3 Online construction: what changes when we append a character

Suppose the automaton of $s$ is built and we append $c$. The new substrings are suffixes of $sc$, all ending at the new position $n$.

1. $sc$ itself is new: create state `cur` with $\mathrm{len}=n+1$.
2. Walk the suffix chain of $s$ (from `last`, the state of the whole $s$, along links). A state $p$ with no $c$-transition means its strings followed by $c$ never occurred before; they now end only at $n$, exactly like $sc$, so they belong to `cur`: add $p\xrightarrow{c}$`cur` and continue.
3. If the chain runs out ($p=-1$), every suffix of $sc$ was new except the empty string: $\mathrm{link}(\text{cur})=\text{root}$.
4. Otherwise $p$ has a transition to $q$: the strings $x c$ for $x$ in $p$ already occurred. Two cases.
   - $\mathrm{len}(q)=\mathrm{len}(p)+1$: $\mathrm{longest}(q)=\mathrm{longest}(p)c$, every string of $q$ is a suffix of $sc$, so $q$'s endpos simply gains $n$. Set $\mathrm{link}(\text{cur})=q$.
   - $\mathrm{len}(q)>\mathrm{len}(p)+1$: $q$ also contains longer strings that do **not** end at $n$. The class splits: create `clone` with $\mathrm{len}=\mathrm{len}(p)+1$, the same outgoing transitions and link as $q$; then $\mathrm{link}(q)=\mathrm{link}(\text{cur})=\text{clone}$, and redirect every transition into $q$ from the rest of the chain ($p, \mathrm{link}(p),\dots$ while they point to $q$) to `clone`.

That is the entire algorithm. A clone represents strings whose endpos just became a proper superset of $q$'s.

### 1.4 Size and time bounds

- **States $\le 2n-1$ for $n\ge2$.** Each extension adds `cur` and at most one clone. The first two extensions cannot clone, so the count is at most $1+1+1+2(n-2)=2n-1$. Tight for `abbb…b`.
- **Transitions $\le 3n-4$ for $n\ge3$.** Take a spanning tree of the longest paths from the root: at most (states $-1$) $\le2n-2$ edges. Every non-tree transition $p\xrightarrow{c}q$ can be extended (tree path to $p$, then $c$, then the longest path from $q$ to a terminal) into a distinct suffix of $s$, and the full string uses tree edges only, so there are at most $n-1$ of them; a finer case analysis gives $3n-4$ (tight for `abbb…bc`).
- **Linear time.** Steps of the first loop each create a transition (bounded above). Each step of the redirect loop strictly increases the start position, as a suffix of the current text, of $\mathrm{longest}(\mathrm{link}(\mathrm{link}(\text{last})))$, which never exceeds $n$. So construction is $O(n\sigma)$ with array transitions (the clone copies a row) or $O(n\log\sigma)$ with maps.

### 1.5 Reading answers off the automaton

Every path from the root spells a distinct substring, and every substring is spelled by exactly one path; the state reached is its endpos class.

- **Distinct substrings:** state $v$ holds $\mathrm{len}(v)-\mathrm{len}(\mathrm{link}(v))$ strings, so $\#=\sum_{v\ne\text{root}}(\mathrm{len}(v)-\mathrm{len}(\mathrm{link}(v)))$. (Equivalently the number of root paths in the DAG.)
- **Occurrences:** $\mathrm{occ}(t)=|\mathrm{endpos}(v)|$. Each non-clone state is the `cur` of exactly one position $i$ (it contains the prefix $s[0..i]$), and $i$ belongs to the endpos of exactly the states on its link-tree path to the root. So set $\mathrm{cnt}=1$ on non-clones, $0$ on clones, and sum over link-tree subtrees.
- **Topological orders for free:** a transition $v\to u$ has $\mathrm{len}(u)\ge\mathrm{len}(v)+1$ and a link has smaller `len`. Sorting states by `len` (counting sort, $O(n)$) gives a topological order of the DAG *and* a children-before-parents order of the link tree. No recursion is ever needed.

## 2. Formulas, definitions and identities

| Quantity | Formula | Meaning |
|---|---|---|
| strings in state $v$ | $\mathrm{len}(v)-\mathrm{len}(\mathrm{link}(v))$ | lengths $\mathrm{len}(\mathrm{link}(v))+1..\mathrm{len}(v)$ |
| distinct substrings | $\sum_{v\ne0}\mathrm{len}(v)-\mathrm{len}(\mathrm{link}(v))$ | §1.5 |
| new substrings after appending | $\mathrm{len}(\text{cur})-\mathrm{len}(\mathrm{link}(\text{cur}))$ | online distinct count per prefix |
| $\mathrm{cnt}(v)=\lvert\mathrm{endpos}(v)\rvert$ | $[v\ \text{not a clone}]+\sum_{\mathrm{link}(u)=v}\mathrm{cnt}(u)$ | occurrences of every string in $v$ |
| $\sum_p\mathrm{occ}(p)^2$ | $\sum_v\mathrm{cnt}(v)^2\,(\mathrm{len}(v)-\mathrm{len}(\mathrm{link}(v)))$ | any $f(\mathrm{occ})$ summed over distinct substrings |
| paths from $v$ | $\mathrm{d}(v)=\sum_{c}\big(1+\mathrm{d}(\delta(v,c))\big)$ | distinct non-empty strings readable from $v$ |
| weighted paths | $\mathrm{tot}(v)=\mathrm{cnt}(v)+\sum_c\mathrm{tot}(\delta(v,c))$ | occurrences of all strings through $v$ |
| first occurrence end | $\mathrm{firstpos}(\text{cur})=\mathrm{len}(\text{cur})-1$, $\mathrm{firstpos}(\text{clone})=\mathrm{firstpos}(q)$ | first occurrence of $t$ starts at $\mathrm{firstpos}-\lvert t\rvert+1$ |
| longest repeated substring | $\max\{\mathrm{len}(v):\mathrm{cnt}(v)\ge2\}$ | |
| bounds | states $\le2n-1$ ($n\ge2$), transitions $\le3n-4$ ($n\ge3$) | memory $\approx 2n\sigma$ ints with arrays |

**Matching statistics** (for each prefix of $t$, the longest suffix that is a substring of $s$): keep $(v,\ell)$; on character $c$, while $v\ne\text{root}$ and $\delta(v,c)$ is undefined set $v=\mathrm{link}(v)$, $\ell=\mathrm{len}(v)$; then if $\delta(v,c)$ exists, $v=\delta(v,c)$, $\ell\mathrel{+}=1$, else $\ell=0$. Amortised $O(|t|)$: $\ell$ grows by at most one per character.

| Operation | Cost |
|---|---|
| build (array transitions / map) | $O(n\sigma)$ / $O(n\log\sigma)$ |
| substring test, occurrence count | $O(\lvert t\rvert)$ after $O(n)$ counting |
| distinct substrings | $O(n)$ after build |
| longest common substring with $t$ | $O(\lvert t\rvert)$ amortised |
| $k$-th substring | $O(n\sigma)$ preprocessing, $O(\lvert\text{answer}\rvert\cdot\sigma)$ per query |

## 3. Implementation (C++ and Java)

### 3.1 Array-transition automaton, distinct substrings and occurrence counts

Input: $s$, then $q$ patterns. Output: the number of distinct substrings of $s$, then for each pattern the number of its occurrences in $s$ (0 if absent).
`order` is the list of states by increasing `len`; walking it backwards pushes `cnt` up the link tree.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct SuffixAutomaton {
    static constexpr int A = 26;
    vector<array<int, A>> next;
    vector<int> link, len;
    vector<char> isClone;
    int last = 0;
    explicit SuffixAutomaton(int maxLen) {
        next.reserve(2 * maxLen + 2); link.reserve(2 * maxLen + 2); len.reserve(2 * maxLen + 2);
        newState(0, -1, false);
    }
    int newState(int l, int lk, bool clone) {
        array<int, A> row; row.fill(-1);
        next.push_back(row); len.push_back(l); link.push_back(lk); isClone.push_back(clone);
        return (int)len.size() - 1;
    }
    void extend(int c) {
        int cur = newState(len[last] + 1, -1, false), p = last;
        while (p != -1 && next[p][c] == -1) { next[p][c] = cur; p = link[p]; }
        if (p == -1) link[cur] = 0;
        else {
            int q = next[p][c];
            if (len[p] + 1 == len[q]) link[cur] = q;
            else {
                int cl = newState(len[p] + 1, link[q], true);
                next[cl] = next[q];
                while (p != -1 && next[p][c] == q) { next[p][c] = cl; p = link[p]; }
                link[q] = link[cur] = cl;
            }
        }
        last = cur;
    }
    vector<int> orderByLen() const {                  // counting sort: increasing len
        int S = len.size(), mx = *max_element(len.begin(), len.end());
        vector<int> bucket(mx + 2, 0), order(S);
        for (int v = 0; v < S; v++) bucket[len[v] + 1]++;
        for (int i = 1; i <= mx + 1; i++) bucket[i] += bucket[i - 1];
        for (int v = 0; v < S; v++) order[bucket[len[v]]++] = v;
        return order;
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; int q;
    cin >> s >> q;
    SuffixAutomaton sam(s.size());
    for (char ch : s) sam.extend(ch - 'a');
    int S = sam.len.size();
    long long distinct = 0;
    for (int v = 1; v < S; v++) distinct += sam.len[v] - sam.len[sam.link[v]];
    vector<int> order = sam.orderByLen();
    vector<long long> cnt(S);
    for (int v = 1; v < S; v++) cnt[v] = sam.isClone[v] ? 0 : 1;
    for (int i = S - 1; i > 0; i--) { int v = order[i]; cnt[sam.link[v]] += cnt[v]; }   // children first
    cout << distinct << '\n';
    while (q--) {
        string t; cin >> t;
        int v = 0;
        for (char ch : t) { v = sam.next[v][ch - 'a']; if (v == -1) break; }
        cout << (v == -1 ? 0 : cnt[v]) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class SuffixAutomaton {
        static final int A = 26;
        final int[] next, link, len;
        final boolean[] isClone;
        int size = 1, last = 0;
        SuffixAutomaton(int maxLen) {
            int cap = 2 * maxLen + 2;
            next = new int[cap * A]; Arrays.fill(next, -1);
            link = new int[cap]; len = new int[cap]; isClone = new boolean[cap];
            link[0] = -1;
        }
        void extend(int c) {
            int cur = size++, p = last;
            len[cur] = len[last] + 1;
            while (p != -1 && next[p * A + c] == -1) { next[p * A + c] = cur; p = link[p]; }
            if (p == -1) link[cur] = 0;
            else {
                int q = next[p * A + c];
                if (len[p] + 1 == len[q]) link[cur] = q;
                else {
                    int cl = size++;
                    len[cl] = len[p] + 1; link[cl] = link[q]; isClone[cl] = true;
                    System.arraycopy(next, q * A, next, cl * A, A);
                    while (p != -1 && next[p * A + c] == q) { next[p * A + c] = cl; p = link[p]; }
                    link[q] = cl; link[cur] = cl;
                }
            }
            last = cur;
        }
        int[] orderByLen() {                               // counting sort: increasing len
            int mx = 0;
            for (int v = 0; v < size; v++) mx = Math.max(mx, len[v]);
            int[] bucket = new int[mx + 2], order = new int[size];
            for (int v = 0; v < size; v++) bucket[len[v] + 1]++;
            for (int i = 1; i <= mx + 1; i++) bucket[i] += bucket[i - 1];
            for (int v = 0; v < size; v++) order[bucket[len[v]]++] = v;
            return order;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        int q = in.nextInt();
        SuffixAutomaton sam = new SuffixAutomaton(s.length());
        for (int i = 0; i < s.length(); i++) sam.extend(s.charAt(i) - 'a');
        int S = sam.size;
        long distinct = 0;
        for (int v = 1; v < S; v++) distinct += sam.len[v] - sam.len[sam.link[v]];
        int[] order = sam.orderByLen();
        long[] cnt = new long[S];
        for (int v = 1; v < S; v++) cnt[v] = sam.isClone[v] ? 0 : 1;
        for (int i = S - 1; i > 0; i--) { int v = order[i]; cnt[sam.link[v]] += cnt[v]; }
        StringBuilder sb = new StringBuilder();
        sb.append(distinct).append('\n');
        while (q-- > 0) {
            String t = in.next();
            int v = 0;
            for (int i = 0; i < t.length() && v != -1; i++) v = sam.next[v * 26 + (t.charAt(i) - 'a')];
            sb.append(v == -1 ? 0 : cnt[v]).append('\n');
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
4
ana
a
nab
banana
out:
15
2
3
0
1
-->
<!-- test
in:
aaaa
3
aa
aaaaa
a
out:
4
3
0
4
-->
<!-- test
in:
z
1
z
out:
1
1
-->

### 3.2 Map transitions for large alphabets (distinct subarrays)

When the "characters" are arbitrary integers, store transitions in a map; a clone copies the map. Input: $n$ and an array of $n$ integers ($|a_i|\le10^9$). Output: the number of distinct contiguous subarrays.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct MapSAM {
    vector<map<int, int>> next;
    vector<int> link, len;
    int last = 0;
    MapSAM() { next.emplace_back(); link.push_back(-1); len.push_back(0); }
    long long extend(int c) {                          // returns the number of new distinct substrings
        int cur = next.size();
        next.emplace_back(); len.push_back(len[last] + 1); link.push_back(0);
        int p = last;
        while (p != -1 && !next[p].count(c)) { next[p][c] = cur; p = link[p]; }
        if (p != -1) {
            int q = next[p][c];
            if (len[p] + 1 == len[q]) link[cur] = q;
            else {
                int cl = next.size();
                map<int, int> copy = next[q];       // copy first: push_back may reallocate
                next.push_back(move(copy)); len.push_back(len[p] + 1); link.push_back(link[q]);
                while (p != -1) {
                    auto it = next[p].find(c);
                    if (it == next[p].end() || it->second != q) break;
                    it->second = cl; p = link[p];
                }
                link[q] = link[cur] = cl;
            }
        }
        last = cur;
        return len[cur] - len[link[cur]];
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    MapSAM sam;
    long long total = 0;
    for (int i = 0; i < n; i++) { int x; cin >> x; total += sam.extend(x); }
    cout << total << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class MapSAM {
        final ArrayList<HashMap<Integer, Integer>> next = new ArrayList<>();
        int[] link, len;
        int size = 1, last = 0;
        MapSAM(int maxLen) {
            link = new int[2 * maxLen + 2]; len = new int[2 * maxLen + 2];
            link[0] = -1; next.add(new HashMap<>());
        }
        long extend(int c) {
            int cur = size++;
            next.add(new HashMap<>()); len[cur] = len[last] + 1;
            int p = last;
            while (p != -1 && !next.get(p).containsKey(c)) { next.get(p).put(c, cur); p = link[p]; }
            if (p == -1) link[cur] = 0;
            else {
                int q = next.get(p).get(c);
                if (len[p] + 1 == len[q]) link[cur] = q;
                else {
                    int cl = size++;
                    next.add(new HashMap<>(next.get(q))); len[cl] = len[p] + 1; link[cl] = link[q];
                    while (p != -1) {
                        Integer to = next.get(p).get(c);
                        if (to == null || to != q) break;
                        next.get(p).put(c, cl); p = link[p];
                    }
                    link[q] = cl; link[cur] = cl;
                }
            }
            last = cur;
            return len[cur] - len[link[cur]];
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        MapSAM sam = new MapSAM(n);
        long total = 0;
        for (int i = 0; i < n; i++) total += sam.extend(in.nextInt());
        out.println(total);
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
1000000000 -5 1000000000 -5
out:
7
-->
<!-- test
in:
3
7 7 7
out:
3
-->
<!-- test
in:
1
42
out:
1
-->

`to != q` compares an `Integer` with an `int`, which unboxes — safe. Comparing two `Integer` objects with `!=` would compare references and break above 127.

## 4. Recognising the pattern

- **"Over all distinct substrings, sum / count / maximise something that depends on the number of occurrences"** → states with `cnt`, each contributing $\mathrm{len}-\mathrm{len}(\mathrm{link})$ substrings with identical occurrence counts.
- **Online appends:** "after each character, how many distinct substrings" → each `extend` adds $\mathrm{len}(\text{cur})-\mathrm{len}(\mathrm{link}(\text{cur}))$.
- **Longest common substring of two strings**, or matching statistics of one string against another → walk $t$ on the automaton of $s$.
- **One fixed text, many pattern queries** asking for counts or first positions → $O(|t|)$ per query after $O(n)$ preprocessing (no binary search, unlike the suffix array).
- **$k$-th substring with repetitions** → path counts weighted by `cnt` on the DAG.
- **Cyclic shifts / rotations of a query** → walk $x+x$ with matching statistics and shrink to length $|x|$.
- **Confused with:** [suffix array](07-suffix-array-and-lcp.md) (lexicographic order and LCP of positions are more natural there), [Aho–Corasick](06-aho-corasick.md) (patterns known first, text streamed). Many problems accept all three; pick the one whose primitive matches the question.

## 5. Worked examples (graded)

### Example 1 — Longest common substring via matching statistics · ★ ≈2000 (est.)

- **Source:** Original problem (compare with the suffix-array solution in [07 Example 2](07-suffix-array-and-lcp.md)).
- **Difficulty:** ≈2000 (est.)
- **Problem:** strings $a,b$ (lengths $\le2.5\cdot10^5$, lowercase). Output the length of their longest common substring.
- **Thinking from first principles:** a common substring ends at some position of $b$. For each position $i$ of $b$ we want the longest suffix of $b[0..i]$ that is a substring of $a$ — the matching statistic. Knowing it for $i$, the answer for $i+1$ is obtained by appending $b[i+1]$ if possible, otherwise dropping characters from the *front* until it is possible. Dropping from the front while staying inside $a$'s substrings is exactly following suffix links (each link removes the shortest prefixes that change the endpos class).

<details><summary>Solution</summary>

Automaton of $a$; walk $b$ keeping $(v,\ell)$ as in §2; the answer is $\max\ell$. When following a link, $\ell=\mathrm{len}(v)$ is correct because the new state's longest string is a suffix of the old match. $O(|a|\sigma+|b|)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct SuffixAutomaton {                              // §3.1, compacted
    static constexpr int A = 26;
    vector<array<int, A>> next; vector<int> link, len; vector<char> isClone; int last = 0;
    explicit SuffixAutomaton(int maxLen) { next.reserve(2 * maxLen + 2); newState(0, -1, false); }
    int newState(int l, int lk, bool clone) {
        array<int, A> row; row.fill(-1);
        next.push_back(row); len.push_back(l); link.push_back(lk); isClone.push_back(clone);
        return (int)len.size() - 1;
    }
    void extend(int c) {
        int cur = newState(len[last] + 1, -1, false), p = last;
        while (p != -1 && next[p][c] == -1) { next[p][c] = cur; p = link[p]; }
        if (p == -1) link[cur] = 0;
        else {
            int q = next[p][c];
            if (len[p] + 1 == len[q]) link[cur] = q;
            else {
                int cl = newState(len[p] + 1, link[q], true);
                next[cl] = next[q];
                while (p != -1 && next[p][c] == q) { next[p][c] = cl; p = link[p]; }
                link[q] = link[cur] = cl;
            }
        }
        last = cur;
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string a, b;
    cin >> a >> b;
    SuffixAutomaton sam(a.size());
    for (char ch : a) sam.extend(ch - 'a');
    int v = 0, l = 0, best = 0;
    for (char ch : b) {
        int c = ch - 'a';
        while (v != 0 && sam.next[v][c] == -1) { v = sam.link[v]; l = sam.len[v]; }
        if (sam.next[v][c] != -1) { v = sam.next[v][c]; l++; }
        else l = 0;                                    // v is the root here
        best = max(best, l);
    }
    cout << best << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class SuffixAutomaton {               // §3.1, compacted
        static final int A = 26;
        final int[] next, link, len; final boolean[] isClone; int size = 1, last = 0;
        SuffixAutomaton(int maxLen) {
            int cap = 2 * maxLen + 2;
            next = new int[cap * A]; Arrays.fill(next, -1); link = new int[cap]; len = new int[cap]; isClone = new boolean[cap]; link[0] = -1;
        }
        void extend(int c) {
            int cur = size++, p = last;
            len[cur] = len[last] + 1;
            while (p != -1 && next[p * A + c] == -1) { next[p * A + c] = cur; p = link[p]; }
            if (p == -1) link[cur] = 0;
            else {
                int q = next[p * A + c];
                if (len[p] + 1 == len[q]) link[cur] = q;
                else {
                    int cl = size++;
                    len[cl] = len[p] + 1; link[cl] = link[q]; isClone[cl] = true;
                    System.arraycopy(next, q * A, next, cl * A, A);
                    while (p != -1 && next[p * A + c] == q) { next[p * A + c] = cl; p = link[p]; }
                    link[q] = cl; link[cur] = cl;
                }
            }
            last = cur;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String a = in.next(), b = in.next();
        SuffixAutomaton sam = new SuffixAutomaton(a.length());
        for (int i = 0; i < a.length(); i++) sam.extend(a.charAt(i) - 'a');
        int v = 0, l = 0, best = 0;
        for (int i = 0; i < b.length(); i++) {
            int c = b.charAt(i) - 'a';
            while (v != 0 && sam.next[v * 26 + c] == -1) { v = sam.link[v]; l = sam.len[v]; }
            if (sam.next[v * 26 + c] != -1) { v = sam.next[v * 26 + c]; l++; }
            else l = 0;
            best = Math.max(best, l);
        }
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
xabcyabcd
zzabcdq
out:
4
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

### Example 2 — Self-similarity $\sum_p \mathrm{occ}(p)^2$ · ★ 2300

- **Source:** [CF 802G3 · Fake News (hard)](https://codeforces.com/problemset/problem/802/G3) — 2300
- **Difficulty:** 2300
- **Problem:** $T\le10$ strings, each of length $\le10^5$. For each, output $\sum_p\mathrm{occ}(p)^2$ over all non-empty strings $p$ ($\mathrm{occ}$ = number of occurrences as a substring).
- **Thinking from first principles:** only substrings contribute, and there are $\Theta(n^2)$ of them — but they come in at most $2n-1$ groups with *identical* occurrence counts: the strings of one state share endpos. So the sum is $\sum_v\mathrm{cnt}(v)^2(\mathrm{len}(v)-\mathrm{len}(\mathrm{link}(v)))$. (The suffix-array route is $\frac{n(n+1)}2+2\sum_{i<j}\mathrm{LCP}(i,j)$, like [07 Example 4](07-suffix-array-and-lcp.md).)

<details><summary>Solution</summary>

Build, count `cnt` in decreasing `len` order, sum. Values reach $\sum_L (n-L+1)^2\approx n^3/3\approx3.3\cdot10^{14}$: 64-bit. $O(n\sigma)$ per string.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct SuffixAutomaton {                              // §3.1, compacted
    static constexpr int A = 26;
    vector<array<int, A>> next; vector<int> link, len; vector<char> isClone; int last = 0;
    explicit SuffixAutomaton(int maxLen) { next.reserve(2 * maxLen + 2); newState(0, -1, false); }
    int newState(int l, int lk, bool clone) {
        array<int, A> row; row.fill(-1);
        next.push_back(row); len.push_back(l); link.push_back(lk); isClone.push_back(clone);
        return (int)len.size() - 1;
    }
    void extend(int c) {
        int cur = newState(len[last] + 1, -1, false), p = last;
        while (p != -1 && next[p][c] == -1) { next[p][c] = cur; p = link[p]; }
        if (p == -1) link[cur] = 0;
        else {
            int q = next[p][c];
            if (len[p] + 1 == len[q]) link[cur] = q;
            else {
                int cl = newState(len[p] + 1, link[q], true);
                next[cl] = next[q];
                while (p != -1 && next[p][c] == q) { next[p][c] = cl; p = link[p]; }
                link[q] = link[cur] = cl;
            }
        }
        last = cur;
    }
    vector<int> orderByLen() const {
        int S = len.size(), mx = *max_element(len.begin(), len.end());
        vector<int> bucket(mx + 2, 0), order(S);
        for (int v = 0; v < S; v++) bucket[len[v] + 1]++;
        for (int i = 1; i <= mx + 1; i++) bucket[i] += bucket[i - 1];
        for (int v = 0; v < S; v++) order[bucket[len[v]]++] = v;
        return order;
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int T; cin >> T;
    while (T--) {
        string s; cin >> s;
        SuffixAutomaton sam(s.size());
        for (char ch : s) sam.extend(ch - 'a');
        int S = sam.len.size();
        vector<int> order = sam.orderByLen();
        vector<long long> cnt(S, 0);
        for (int v = 1; v < S; v++) cnt[v] = sam.isClone[v] ? 0 : 1;
        for (int i = S - 1; i > 0; i--) { int v = order[i]; cnt[sam.link[v]] += cnt[v]; }
        long long ans = 0;
        for (int v = 1; v < S; v++) ans += cnt[v] * cnt[v] * (sam.len[v] - sam.len[sam.link[v]]);
        cout << ans << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class SuffixAutomaton {               // §3.1, compacted
        static final int A = 26;
        final int[] next, link, len; final boolean[] isClone; int size = 1, last = 0;
        SuffixAutomaton(int maxLen) {
            int cap = 2 * maxLen + 2;
            next = new int[cap * A]; Arrays.fill(next, -1); link = new int[cap]; len = new int[cap]; isClone = new boolean[cap]; link[0] = -1;
        }
        void extend(int c) {
            int cur = size++, p = last;
            len[cur] = len[last] + 1;
            while (p != -1 && next[p * A + c] == -1) { next[p * A + c] = cur; p = link[p]; }
            if (p == -1) link[cur] = 0;
            else {
                int q = next[p * A + c];
                if (len[p] + 1 == len[q]) link[cur] = q;
                else {
                    int cl = size++;
                    len[cl] = len[p] + 1; link[cl] = link[q]; isClone[cl] = true;
                    System.arraycopy(next, q * A, next, cl * A, A);
                    while (p != -1 && next[p * A + c] == q) { next[p * A + c] = cl; p = link[p]; }
                    link[q] = cl; link[cur] = cl;
                }
            }
            last = cur;
        }
        int[] orderByLen() {
            int mx = 0;
            for (int v = 0; v < size; v++) mx = Math.max(mx, len[v]);
            int[] bucket = new int[mx + 2], order = new int[size];
            for (int v = 0; v < size; v++) bucket[len[v] + 1]++;
            for (int i = 1; i <= mx + 1; i++) bucket[i] += bucket[i - 1];
            for (int v = 0; v < size; v++) order[bucket[len[v]]++] = v;
            return order;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int T = in.nextInt();
        while (T-- > 0) {
            String s = in.next();
            SuffixAutomaton sam = new SuffixAutomaton(s.length());
            for (int i = 0; i < s.length(); i++) sam.extend(s.charAt(i) - 'a');
            int S = sam.size;
            int[] order = sam.orderByLen();
            long[] cnt = new long[S];
            for (int v = 1; v < S; v++) cnt[v] = sam.isClone[v] ? 0 : 1;
            for (int i = S - 1; i > 0; i--) { int v = order[i]; cnt[sam.link[v]] += cnt[v]; }
            long ans = 0;
            for (int v = 1; v < S; v++) ans += cnt[v] * cnt[v] * (sam.len[v] - sam.len[sam.link[v]]);
            out.println(ans);
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
3
aaa
abc
abab
out:
14
6
16
-->
<!-- test
in:
1
z
out:
1
-->

</details>

Hand check: `aaa` gives $3^2+2^2+1^2=14$; `abc` has six substrings occurring once; `abab`: $a,b,ab$ occur twice ($3\cdot2^2=12$) and $ba,aba,bab,abab$ once ($4$): $16$.

### Example 3 — $k$-th smallest substring counting repetitions · ★ ≈2300 (est.)

- **Source:** [CSES 2109 · Substring Order II](https://cses.fi/problemset/task/2109)
- **Difficulty:** ≈2300 (est.)
- **Problem:** consider all $\frac{n(n+1)}2$ substrings of $s$ ($n\le10^5$) *with* repetitions, sorted lexicographically. Print the $k$-th.
- **Thinking from first principles:** in the sorted list with repetitions, a string $t$ appears $\mathrm{occ}(t)$ times, immediately followed by all strings having $t$ as a proper prefix, in order. A greedy descent from the root picks the first letter, then the second, ..., as long as we know, for every state $u$, how many list entries start with "the path to $u$". All paths into $u$ have the same set of continuations and the same counts, so this is a per-state number: $\mathrm{tot}(u)=\mathrm{cnt}(u)+\sum_c\mathrm{tot}(\delta(u,c))$, computed in decreasing `len` order (a reverse topological order of the DAG).

<details><summary>Solution</summary>

At state $v$ with $k$ remaining: scan letters $a..z$; skip $u=\delta(v,c)$ while $k>\mathrm{tot}(u)$ (subtract it); otherwise append $c$, subtract $\mathrm{cnt}(u)$ (the copies of the current string itself), and stop if $k\le0$, else descend. The root's `cnt` is 0 (the empty string is not listed). $O(n\sigma)$ preprocessing, $O(|\text{answer}|\cdot\sigma)$ descent; all counts in 64-bit.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct SuffixAutomaton {                              // §3.1, compacted
    static constexpr int A = 26;
    vector<array<int, A>> next; vector<int> link, len; vector<char> isClone; int last = 0;
    explicit SuffixAutomaton(int maxLen) { next.reserve(2 * maxLen + 2); newState(0, -1, false); }
    int newState(int l, int lk, bool clone) {
        array<int, A> row; row.fill(-1);
        next.push_back(row); len.push_back(l); link.push_back(lk); isClone.push_back(clone);
        return (int)len.size() - 1;
    }
    void extend(int c) {
        int cur = newState(len[last] + 1, -1, false), p = last;
        while (p != -1 && next[p][c] == -1) { next[p][c] = cur; p = link[p]; }
        if (p == -1) link[cur] = 0;
        else {
            int q = next[p][c];
            if (len[p] + 1 == len[q]) link[cur] = q;
            else {
                int cl = newState(len[p] + 1, link[q], true);
                next[cl] = next[q];
                while (p != -1 && next[p][c] == q) { next[p][c] = cl; p = link[p]; }
                link[q] = link[cur] = cl;
            }
        }
        last = cur;
    }
    vector<int> orderByLen() const {
        int S = len.size(), mx = *max_element(len.begin(), len.end());
        vector<int> bucket(mx + 2, 0), order(S);
        for (int v = 0; v < S; v++) bucket[len[v] + 1]++;
        for (int i = 1; i <= mx + 1; i++) bucket[i] += bucket[i - 1];
        for (int v = 0; v < S; v++) order[bucket[len[v]]++] = v;
        return order;
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; long long k;
    cin >> s >> k;
    SuffixAutomaton sam(s.size());
    for (char ch : s) sam.extend(ch - 'a');
    int S = sam.len.size();
    vector<int> order = sam.orderByLen();
    vector<long long> cnt(S, 0), tot(S, 0);
    for (int v = 1; v < S; v++) cnt[v] = sam.isClone[v] ? 0 : 1;
    for (int i = S - 1; i > 0; i--) { int v = order[i]; cnt[sam.link[v]] += cnt[v]; }
    cnt[0] = 0;                                         // the empty string is not in the list
    for (int i = S - 1; i >= 0; i--) {                  // reverse topological order of the DAG
        int v = order[i];
        tot[v] = cnt[v];
        for (int c = 0; c < 26; c++) if (sam.next[v][c] != -1) tot[v] += tot[sam.next[v][c]];
    }
    string ans;
    int v = 0;
    while (k > 0) {
        for (int c = 0; c < 26; c++) {
            int u = sam.next[v][c];
            if (u == -1) continue;
            if (k > tot[u]) { k -= tot[u]; continue; }
            ans += char('a' + c);
            k -= cnt[u];
            v = u;
            break;
        }
    }
    cout << ans << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class SuffixAutomaton {               // §3.1, compacted
        static final int A = 26;
        final int[] next, link, len; final boolean[] isClone; int size = 1, last = 0;
        SuffixAutomaton(int maxLen) {
            int cap = 2 * maxLen + 2;
            next = new int[cap * A]; Arrays.fill(next, -1); link = new int[cap]; len = new int[cap]; isClone = new boolean[cap]; link[0] = -1;
        }
        void extend(int c) {
            int cur = size++, p = last;
            len[cur] = len[last] + 1;
            while (p != -1 && next[p * A + c] == -1) { next[p * A + c] = cur; p = link[p]; }
            if (p == -1) link[cur] = 0;
            else {
                int q = next[p * A + c];
                if (len[p] + 1 == len[q]) link[cur] = q;
                else {
                    int cl = size++;
                    len[cl] = len[p] + 1; link[cl] = link[q]; isClone[cl] = true;
                    System.arraycopy(next, q * A, next, cl * A, A);
                    while (p != -1 && next[p * A + c] == q) { next[p * A + c] = cl; p = link[p]; }
                    link[q] = cl; link[cur] = cl;
                }
            }
            last = cur;
        }
        int[] orderByLen() {
            int mx = 0;
            for (int v = 0; v < size; v++) mx = Math.max(mx, len[v]);
            int[] bucket = new int[mx + 2], order = new int[size];
            for (int v = 0; v < size; v++) bucket[len[v] + 1]++;
            for (int i = 1; i <= mx + 1; i++) bucket[i] += bucket[i - 1];
            for (int v = 0; v < size; v++) order[bucket[len[v]]++] = v;
            return order;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        long k = in.nextLong();
        SuffixAutomaton sam = new SuffixAutomaton(s.length());
        for (int i = 0; i < s.length(); i++) sam.extend(s.charAt(i) - 'a');
        int S = sam.size;
        int[] order = sam.orderByLen();
        long[] cnt = new long[S], tot = new long[S];
        for (int v = 1; v < S; v++) cnt[v] = sam.isClone[v] ? 0 : 1;
        for (int i = S - 1; i > 0; i--) { int v = order[i]; cnt[sam.link[v]] += cnt[v]; }
        cnt[0] = 0;
        for (int i = S - 1; i >= 0; i--) {
            int v = order[i];
            tot[v] = cnt[v];
            for (int c = 0; c < 26; c++) { int u = sam.next[v * 26 + c]; if (u != -1) tot[v] += tot[u]; }
        }
        StringBuilder ans = new StringBuilder();
        int v = 0;
        while (k > 0) {
            for (int c = 0; c < 26; c++) {
                int u = sam.next[v * 26 + c];
                if (u == -1) continue;
                if (k > tot[u]) { k -= tot[u]; continue; }
                ans.append((char) ('a' + c));
                k -= cnt[u];
                v = u;
                break;
            }
        }
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
banana 4
out:
an
-->
<!-- test
in:
banana 21
out:
nana
-->
<!-- test
in:
aaa 6
out:
aaa
-->

</details>

For `banana` the sorted list with repetitions begins `a, a, a, an, an, ana, ana, anan, anana, b, …`, so the 4th entry is `an`; the last (21st) entry is `nana`.

### Example 4 — Counting all rotations of a query · ★ 2700

- **Source:** [CF 235C · Cyclical Quest](https://codeforces.com/problemset/problem/235/C) — 2700
- **Difficulty:** 2700
- **Problem:** a text $s$ ($|s|\le10^6$) and queries $x_1,\dots,x_q$ (total length $\le10^6$). For each query, count the substrings of $s$ (occurrences, i.e. pairs of positions) that equal *some* cyclic rotation of $x$.
- **Thinking from first principles:** the answer is $\sum_{r}\mathrm{occ}(r)$ over the **distinct** rotations $r$ of $x$ (a periodic $x$ like `abab` has fewer distinct rotations than $|x|$). Every rotation is a length-$m$ window of $x+x$, so run matching statistics over $x+x[0..m-2]$: whenever the current match length $\ell\ge m$, the window of length $m$ ending here is a rotation that occurs. To find its state, climb links while $\mathrm{len}(\mathrm{link}(v))\ge m$ — then $m\in(\mathrm{len}(\mathrm{link}(v)),\mathrm{len}(v)]$, so $v$ is exactly the state of that rotation. A state holds at most one string of each length, so "distinct rotation" = "distinct state": mark states with the query id to count each once.

<details><summary>Solution</summary>

Precompute `cnt`. Per query: walk the doubled string with $(v,\ell)$; after each step, if $\ell\ge m$ climb as described (resetting $\ell=\mathrm{len}(v)\ge m$, which keeps all information needed for later windows of length $m$), and add $\mathrm{cnt}(v)$ if $v$ is unmarked. $O(|s|\sigma+\sum|x_i|)$ amortised. Memory: $2|s|\cdot26$ ints is about 208 MB at $|s|=10^6$; if the limit is tighter, switch to a compact transition store.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct SuffixAutomaton {                              // §3.1, compacted
    static constexpr int A = 26;
    vector<array<int, A>> next; vector<int> link, len; vector<char> isClone; int last = 0;
    explicit SuffixAutomaton(int maxLen) { next.reserve(2 * maxLen + 2); newState(0, -1, false); }
    int newState(int l, int lk, bool clone) {
        array<int, A> row; row.fill(-1);
        next.push_back(row); len.push_back(l); link.push_back(lk); isClone.push_back(clone);
        return (int)len.size() - 1;
    }
    void extend(int c) {
        int cur = newState(len[last] + 1, -1, false), p = last;
        while (p != -1 && next[p][c] == -1) { next[p][c] = cur; p = link[p]; }
        if (p == -1) link[cur] = 0;
        else {
            int q = next[p][c];
            if (len[p] + 1 == len[q]) link[cur] = q;
            else {
                int cl = newState(len[p] + 1, link[q], true);
                next[cl] = next[q];
                while (p != -1 && next[p][c] == q) { next[p][c] = cl; p = link[p]; }
                link[q] = link[cur] = cl;
            }
        }
        last = cur;
    }
    vector<int> orderByLen() const {
        int S = len.size(), mx = *max_element(len.begin(), len.end());
        vector<int> bucket(mx + 2, 0), order(S);
        for (int v = 0; v < S; v++) bucket[len[v] + 1]++;
        for (int i = 1; i <= mx + 1; i++) bucket[i] += bucket[i - 1];
        for (int v = 0; v < S; v++) order[bucket[len[v]]++] = v;
        return order;
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string s; int q;
    cin >> s >> q;
    SuffixAutomaton sam(s.size());
    for (char ch : s) sam.extend(ch - 'a');
    int S = sam.len.size();
    vector<int> order = sam.orderByLen();
    vector<long long> cnt(S, 0);
    for (int v = 1; v < S; v++) cnt[v] = sam.isClone[v] ? 0 : 1;
    for (int i = S - 1; i > 0; i--) { int v = order[i]; cnt[sam.link[v]] += cnt[v]; }
    vector<int> mark(S, -1);
    string out;
    for (int id = 0; id < q; id++) {
        string x; cin >> x;
        int m = x.size();
        string t = x + x.substr(0, m - 1);
        int v = 0, l = 0;
        long long ans = 0;
        for (char ch : t) {
            int c = ch - 'a';
            while (v != 0 && sam.next[v][c] == -1) { v = sam.link[v]; l = sam.len[v]; }
            if (sam.next[v][c] != -1) { v = sam.next[v][c]; l++; } else l = 0;
            if (l >= m) {
                while (sam.len[sam.link[v]] >= m) { v = sam.link[v]; l = sam.len[v]; }
                if (mark[v] != id) { mark[v] = id; ans += cnt[v]; }
            }
        }
        out += to_string(ans); out += '\n';
    }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class SuffixAutomaton {               // §3.1, compacted
        static final int A = 26;
        final int[] next, link, len; final boolean[] isClone; int size = 1, last = 0;
        SuffixAutomaton(int maxLen) {
            int cap = 2 * maxLen + 2;
            next = new int[cap * A]; Arrays.fill(next, -1); link = new int[cap]; len = new int[cap]; isClone = new boolean[cap]; link[0] = -1;
        }
        void extend(int c) {
            int cur = size++, p = last;
            len[cur] = len[last] + 1;
            while (p != -1 && next[p * A + c] == -1) { next[p * A + c] = cur; p = link[p]; }
            if (p == -1) link[cur] = 0;
            else {
                int q = next[p * A + c];
                if (len[p] + 1 == len[q]) link[cur] = q;
                else {
                    int cl = size++;
                    len[cl] = len[p] + 1; link[cl] = link[q]; isClone[cl] = true;
                    System.arraycopy(next, q * A, next, cl * A, A);
                    while (p != -1 && next[p * A + c] == q) { next[p * A + c] = cl; p = link[p]; }
                    link[q] = cl; link[cur] = cl;
                }
            }
            last = cur;
        }
        int[] orderByLen() {
            int mx = 0;
            for (int v = 0; v < size; v++) mx = Math.max(mx, len[v]);
            int[] bucket = new int[mx + 2], order = new int[size];
            for (int v = 0; v < size; v++) bucket[len[v] + 1]++;
            for (int i = 1; i <= mx + 1; i++) bucket[i] += bucket[i - 1];
            for (int v = 0; v < size; v++) order[bucket[len[v]]++] = v;
            return order;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String s = in.next();
        int q = in.nextInt();
        SuffixAutomaton sam = new SuffixAutomaton(s.length());
        for (int i = 0; i < s.length(); i++) sam.extend(s.charAt(i) - 'a');
        int S = sam.size;
        int[] order = sam.orderByLen(), mark = new int[S];
        long[] cnt = new long[S];
        for (int v = 1; v < S; v++) cnt[v] = sam.isClone[v] ? 0 : 1;
        for (int i = S - 1; i > 0; i--) { int v = order[i]; cnt[sam.link[v]] += cnt[v]; }
        Arrays.fill(mark, -1);
        StringBuilder sb = new StringBuilder();
        for (int id = 0; id < q; id++) {
            String x = in.next();
            int m = x.length();
            String t = x + x.substring(0, m - 1);
            int v = 0, l = 0;
            long ans = 0;
            for (int i = 0; i < t.length(); i++) {
                int c = t.charAt(i) - 'a';
                while (v != 0 && sam.next[v * 26 + c] == -1) { v = sam.link[v]; l = sam.len[v]; }
                if (sam.next[v * 26 + c] != -1) { v = sam.next[v * 26 + c]; l++; } else l = 0;
                if (l >= m) {
                    while (sam.len[sam.link[v]] >= m) { v = sam.link[v]; l = sam.len[v]; }
                    if (mark[v] != id) { mark[v] = id; ans += cnt[v]; }
                }
            }
            sb.append(ans).append('\n');
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
abab
4
ab
ba
aa
abab
out:
3
3
0
1
-->
<!-- test
in:
aaa
2
a
aaaa
out:
3
0
-->

</details>

In the first test, `ab` has rotations `ab` (2 occurrences) and `ba` (1): 3. `abab` has only two distinct rotations, `abab` (1) and `baba` (0).

## 6. Tricks, pitfalls and things to remember

1. **Clones start with `cnt = 0`.** A clone does not correspond to a new end position; only `cur` states do. Giving clones 1 overcounts every occurrence query.
2. **Root is special.** $\mathrm{link}(\mathrm{root})=-1$; skip it in distinct-substring sums, and set its `cnt` to 0 when weighting paths (the empty string is not a substring to count).
3. **Never recurse** over links or the DAG: `aaaa…a` of length $10^6$ gives depth $10^6$. Counting sort by `len` gives both orders (§1.5). In Java the counting sort also avoids `Integer` boxing.
4. **Memory.** States $\le2n$, so arrays of $2n+2$; transitions as `int[2n·26]` are 208 MB at $n=10^6$. For big $n$ or big alphabets use maps (§3.2) or a sorted edge list; for DNA-sized alphabets arrays are tiny.
5. **The clone copies the transitions and the link of $q$, not of `cur`.** Writing `link[cl] = link[cur]` or forgetting `next[cl] = next[q]` breaks only some strings — stress test against brute force (the bugs survive small hand tests).
6. **The redirect loop must stop at the first $p$ whose $c$-transition is not $q$.** Redirecting further corrupts states that were correct.
7. **Matching statistics:** after following a link set $\ell=\mathrm{len}(v)$ *before* trying the transition, and when no transition exists even at the root set $\ell=0$.
8. **Multiple strings.** Concatenating with separators works but the separators need their own alphabet symbols and inflate $\sigma$; the generalised automaton (reset `last` to the root before each string, with the extra checks for an existing transition) is cleaner — see §7.
9. **Overflow:** distinct-substring counts and $\sum\mathrm{occ}^2$ exceed 32 bits for $n\ge10^5$; $k$ in "$k$-th substring" can be $5\cdot10^9$.
10. **Java `HashMap<Integer,Integer>` transitions:** compare unboxed values (`int to = map.get(c)` after a null check); `Integer != Integer` compares references and fails above 127.

## 7. Going further (toward 2400–2600+)

- **Generalised suffix automaton** (all substrings of a set of strings): insert each string starting from the root; when the transition already exists, either reuse it (if `len` matches) or clone. Count, per state, how many different strings reach it — [CF 316G3 · Good Substrings](https://codeforces.com/problemset/problem/316/G3) — 2400, [CF 452E · Three strings](https://codeforces.com/problemset/problem/452/E) — 2400, [CF 616F · Expensive Strings](https://codeforces.com/problemset/problem/616/F) — 2700, [CF 204E · Little Elephant and Strings](https://codeforces.com/problemset/problem/204/E) — 2800.
- **endpos sets on demand.** Merge segment trees (or small-to-large sets) up the link tree to know *where* each class occurs: "does $t$ occur inside $s[l..r]$?" — [CF 1037H · Security](https://codeforces.com/problemset/problem/1037/H) — 3200, [CF 666E · Forensic Examination](https://codeforces.com/problemset/problem/666/E) — 3100, [CF 700E · Cool Slogans](https://codeforces.com/problemset/problem/700/E) — 3300. See [segment tree merging](../08-Data-Structures/04-segment-tree-advanced-descent-merging-beats.md).
- **Link tree = suffix tree of the reversed string.** Problems about longest common suffixes of prefixes become LCA on the link tree; problems about the suffix tree of $s$ use the automaton of $\mathrm{rev}(s)$.
- **Occurrence positions.** `firstpos` gives the first occurrence; to list all, walk the link-subtree of the state (children lists) — output-sensitive.
- **Lexicographically smallest rotation, longest substring occurring $\ge k$ times, shortest non-occurring string** are all one DAG/link-tree DP each.
- **Hard combinations:** SAM + DSU / small-to-large over the link tree mirrors the suffix-array "merge by decreasing LCP" technique — [CF 873F · Forbidden Indices](https://codeforces.com/problemset/problem/873/F) — 2400. And [CF 1276F · Asterisk Substrings](https://codeforces.com/problemset/problem/1276/F) — 3400 combines both automata of $s$ and $\mathrm{rev}(s)$.

## 8. Practice ladder

**1900–2100**
- [ ] [CSES 2102 · Finding Patterns](https://cses.fi/problemset/task/2102) — ≈1800 (est.) — substring test per query
- [ ] [CSES 2103 · Counting Patterns](https://cses.fi/problemset/task/2103) — ≈1900 (est.) — `cnt`
- [ ] [CSES 2104 · Pattern Positions](https://cses.fi/problemset/task/2104) — ≈1900 (est.) — `firstpos`
- [ ] [CSES 2105 · Distinct Substrings](https://cses.fi/problemset/task/2105) — ≈1900 (est.)
- [ ] [CSES 2106 · Repeating Substring](https://cses.fi/problemset/task/2106) — ≈1900 (est.)
- [ ] [CSES 2110 · Substring Distribution](https://cses.fi/problemset/task/2110) — ≈2000 (est.) — each state is an interval of lengths

**2100–2400**
- [ ] [CSES 2108 · Substring Order I](https://cses.fi/problemset/task/2108) — ≈2100 (est.) — unweighted path counts
- [ ] [CF 128B · String](https://codeforces.com/problemset/problem/128/B) — 2100
- [ ] [CF 427D · Match & Catch](https://codeforces.com/problemset/problem/427/D) — 2200
- [ ] [CSES 2109 · Substring Order II](https://cses.fi/problemset/task/2109) — ≈2300 (est.) — Example 3
- [ ] [CF 123D · String](https://codeforces.com/problemset/problem/123/D) — 2300
- [ ] [CF 802G3 · Fake News (hard)](https://codeforces.com/problemset/problem/802/G3) — 2300 — Example 2
- [ ] [CF 316G3 · Good Substrings](https://codeforces.com/problemset/problem/316/G3) — 2400
- [ ] [CF 452E · Three strings](https://codeforces.com/problemset/problem/452/E) — 2400
- [ ] [CF 873F · Forbidden Indices](https://codeforces.com/problemset/problem/873/F) — 2400

**2400+**
- [ ] [CF 235C · Cyclical Quest](https://codeforces.com/problemset/problem/235/C) — 2700 — Example 4
- [ ] [CF 616F · Expensive Strings](https://codeforces.com/problemset/problem/616/F) — 2700
- [ ] [CF 204E · Little Elephant and Strings](https://codeforces.com/problemset/problem/204/E) — 2800
- [ ] [CF 666E · Forensic Examination](https://codeforces.com/problemset/problem/666/E) — 3100
- [ ] [CF 1037H · Security](https://codeforces.com/problemset/problem/1037/H) — 3200
- [ ] [CF 700E · Cool Slogans](https://codeforces.com/problemset/problem/700/E) — 3300
- [ ] [CF 1276F · Asterisk Substrings](https://codeforces.com/problemset/problem/1276/F) — 3400

## 9. LeetCode / FAANG cross-reference

- [LC 1044 · Longest Duplicate Substring](https://leetcode.com/problems/longest-duplicate-substring/) — Hard — $\max\{\mathrm{len}(v):\mathrm{cnt}(v)\ge2\}$; output via `firstpos`.
- [LC 1698 · Number of Distinct Substrings in a String](https://leetcode.com/problems/number-of-distinct-substrings-in-a-string/) — Medium 🔒 — $\sum\mathrm{len}-\mathrm{len}(\mathrm{link})$.
- [LC 1062 · Longest Repeating Substring](https://leetcode.com/problems/longest-repeating-substring/) — Medium 🔒 — same as LC 1044.
- [LC 1923 · Longest Common Subpath](https://leetcode.com/problems/longest-common-subpath/) — Hard — generalised automaton over integer paths with map transitions, keeping for each state the minimum matched length across all paths (or binary search + hashing, the expected solution).

Rare in interviews: no interviewer expects a suffix automaton; hashing, tries or DP are the interview answers. Its value is in contests, where it turns many "all substrings" problems into a linear pass.

## 10. Self-check

1. Define $\mathrm{endpos}$ and prove that two endpos sets are either nested or disjoint.
2. Why do the strings of one state have consecutive lengths, and what is $\mathrm{len}(\mathrm{link}(v))$?
3. Walk through `extend`: when exactly is a clone created, what does it copy, and which transitions are redirected?
4. Prove the bound of $2n-1$ states. Which string attains it?
5. How do you count occurrences of every state's strings, and why are clones initialised to 0?
6. Why does sorting by `len` give a topological order of the DAG and a bottom-up order of the link tree?
7. Describe matching statistics and how they give the longest common substring.
8. How do you find the $k$-th substring with repetitions, and what is `tot`?

<details><summary>Answers</summary>

1. $\mathrm{endpos}(t)$ is the set of end positions of occurrences of $t$. If $|u|\le|v|$ and some position ends both, $u$ is a suffix of $v$ there, hence everywhere $v$ occurs: $\mathrm{endpos}(v)\subseteq\mathrm{endpos}(u)$. Otherwise no position is shared.
2. Shortening a string from the left can only enlarge its endpos, and the sets are nested, so the lengths with the *same* endpos form an interval. $\mathrm{len}(\mathrm{link}(v))=\mathrm{minlen}(v)-1$: the link is the class of the first suffix that leaves the interval.
3. After walking the chain from `last` and adding transitions to `cur`, if a state $p$ already has $\delta(p,c)=q$ with $\mathrm{len}(q)>\mathrm{len}(p)+1$, the class of $q$ splits: `clone` gets $\mathrm{len}(p)+1$, $q$'s transitions and $q$'s link; $q$ and `cur` link to the clone; transitions to $q$ from $p$ and its link-ancestors (while they point to $q$) go to the clone.
4. Each extension adds `cur` and at most one clone; the first two extensions cannot clone; so $1+1+1+2(n-2)=2n-1$. `abbb…b` attains it.
5. `cnt = 1` on non-clone states (each is the `cur` of one position), 0 on clones; then add each state's count to its link in decreasing `len` order. A position belongs to the endpos of exactly the states on its link path, so subtree sums are endpos sizes; clones add no position of their own.
6. A transition $v\to u$ means $\mathrm{longest}(v)c\in u$, so $\mathrm{len}(u)>\mathrm{len}(v)$; a link goes to a strictly smaller `len`. Increasing `len` is therefore topological for the DAG, and decreasing `len` visits link-children before parents.
7. For each prefix of $t$, keep the state and length of its longest suffix that is a substring of $s$; on a missing transition follow links (setting $\ell=\mathrm{len}$) until one exists or the root is reached. The maximum $\ell$ is the longest common substring.
8. $\mathrm{tot}(u)=\mathrm{cnt}(u)+\sum_c\mathrm{tot}(\delta(u,c))$ counts list entries that begin with any string leading to $u$. Descend from the root choosing the first letter whose `tot` is at least $k$ (subtracting skipped `tot`s), subtract `cnt` of the chosen state, stop when $k\le0$.

</details>
