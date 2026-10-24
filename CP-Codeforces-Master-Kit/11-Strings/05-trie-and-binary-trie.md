# Trie and binary (XOR) trie

> **Band:** 🔵 1400–2100 · **Priority:** 🔥 · **FAANG:** high · **Prerequisites:** [bit manipulation](../01-Foundations/03-bit-manipulation.md), [prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md) (prefix XOR), [tree DP](../06-Dynamic-Programming/08-tree-dp-and-rerooting.md) (DP over the trie)
> **You can say you know this when:** you can write an array-based trie with counts (insert, erase, exact and prefix counts) and a binary trie answering max-XOR, min-XOR and "how many $y$ with $x \oplus y < k$" in $O(B)$, both in C++ and Java, and you can explain why the greedy bit choice is optimal.

## 1. First principles — why this works

**The problem.** Store a set (or multiset) of strings and answer questions about *prefixes*: does a word exist, how many words start with $p$, which stored word shares the longest prefix with a query. A hash set answers only exact membership; a sorted array answers prefix counts in $O(L \log n)$ by binary search. Neither lets you *walk* the common prefixes of all words at once.

**The structure.** Merge all words into a rooted tree where each edge carries a character and each node is a distinct prefix of some word (the root is the empty prefix). Two words with a common prefix share the path for that prefix. This is the **trie** (prefix tree). It is also the minimal deterministic automaton that accepts exactly the stored prefixes, which is why it is the base of [Aho–Corasick](06-aho-corasick.md).

- Insert / search / prefix query: follow one edge per character, $O(L)$ independent of how many words are stored.
- Store at each node `pass` = number of words through the node and `end` = number of words ending there. Then "how many words have prefix $p$" is `pass` at the node of $p$, and deletion is "decrement along the path".
- Number of nodes $\le 1 + \sum |s_i|$. Array-based storage `next[node][c]` costs nodes $\times\ \Sigma$ integers — fast (no hashing, no pointers), but watch memory ($10^6$ nodes $\times 26 \times 4$ bytes $= 104$ MB).

**The binary trie.** Write each integer as a fixed-length bit string, most significant bit first ($B$ bits, e.g. $B = 30$ for values $< 2^{30}$), and insert those strings into a trie with alphabet $\{0,1\}$. Now prefix structure = shared high bits.

**Why greedy is optimal for max XOR.** To maximise $x \oplus y$ over stored $y$, decide the bits of the result from the top. Bit $b$ of the result is worth $2^b$, and all lower bits together are worth at most $2^b - 1$. So it is always right to make bit $b$ equal to 1 if *any* stored $y$ consistent with the choices so far allows it — i.e. go to the child with bit $\overline{x_b}$ if it is non-empty, else to the other child. The trie makes "is there any $y$ with this prefix" an $O(1)$ check (`cnt > 0`), so the query is $O(B)$. Min XOR is the mirror (prefer the same bit).

**Counting $y$ with $x \oplus y < k$.** Walk down along the path of $y$'s for which $x \oplus y$ agrees with $k$ on the high bits. At bit $b$: if $k_b = 1$, every $y$ whose bit makes $(x \oplus y)_b = 0$ gives a smaller XOR regardless of lower bits — add the whole subtree count of child $x_b$ — then continue into child $\overline{x_b}$ (keeping equality). If $k_b = 0$, continue into child $x_b$. The $y$ with $x \oplus y = k$ exactly is not counted. $O(B)$.

**Subarray XOR = prefix XOR pair.** With $P_0 = 0$, $P_i = a_1 \oplus \dots \oplus a_i$, the XOR of $a_{l..r}$ is $P_r \oplus P_{l-1}$ (the common prefix cancels). So "best subarray XOR" is "best pair of prefix values", one trie query per $r$.

## 2. Formulas, definitions and identities

| Quantity | Value | Note |
|---|---|---|
| nodes of a string trie | $\le 1 + \sum_i \lvert s_i\rvert$ | equality when no two words share a prefix |
| array memory | nodes $\times\ \Sigma \times 4$ bytes | 26 letters: 104 bytes per node |
| nodes of a binary trie | $\le 1 + nB$ | $n = 2\cdot 10^5$, $B = 30$: $6\cdot 10^6$ nodes, 48 MB for two `int` children |
| insert / erase / find | $O(L)$ or $O(B)$ | erase = decrement counts along the path |
| prefix count | `pass[node(p)]` | words having $p$ as a prefix |
| greedy dominance | $2^b > \sum_{j<b} 2^j = 2^b - 1$ | why max/min XOR is greedy |
| subarray XOR | $a_l \oplus \dots \oplus a_r = P_r \oplus P_{l-1}$ | $x \oplus x = 0$, associativity |
| pairs with XOR $< k$ | $\sum_j \#\{i<j : a_i \oplus a_j < k\}$, query then insert | $O(nB)$ |
| pairs with XOR in $[lo, hi]$ | $\mathrm{cnt}(<hi+1) - \mathrm{cnt}(<lo)$ | LC 1803 |
| min XOR of a pair | attained by two elements adjacent in sorted order | alternative to a trie for pairs |

**Why the minimum-XOR pair is adjacent in sorted order.** If $a < b < c$, then $a \oplus c \ge \min(a \oplus b,\ b \oplus c)$: let $t$ be the highest bit where $a$ and $c$ differ ($a_t = 0, c_t = 1$); $b$ agrees with both above $t$, and $b_t$ equals $a_t$ or $c_t$, so one of the pairs $(a,b)$, $(b,c)$ agrees on bits $\ge t$ and its XOR is $< 2^t \le a \oplus c$.

## 3. Implementation (C++ and Java)

### 3.1 String trie with counts (array-based)

Driver: $q$ operations on lowercase words. `1 s` insert, `2 s` erase one copy (guaranteed present), `3 s` print how many copies of $s$ are stored, `4 s` print how many stored words have prefix $s$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct Trie {
    vector<array<int, 26>> nxt;                     // 0 = no child (node 0 is the root, never a child)
    vector<int> pass, ends;                          // words through / ending at the node
    Trie() { newNode(); }
    int newNode() { nxt.push_back({}); nxt.back().fill(0); pass.push_back(0); ends.push_back(0); return (int)nxt.size() - 1; }
    void add(const string& s, int d) {               // d = +1 insert, -1 erase
        int v = 0; pass[v] += d;
        for (char ch : s) {
            int c = ch - 'a';
            if (!nxt[v][c]) { int u = newNode(); nxt[v][c] = u; }   // newNode may reallocate nxt
            v = nxt[v][c]; pass[v] += d;
        }
        ends[v] += d;
    }
    int find(const string& s) const {
        int v = 0;
        for (char ch : s) { v = nxt[v][ch - 'a']; if (!v) return -1; }
        return v;
    }
    int countExact(const string& s) const { int v = find(s); return v < 0 ? 0 : ends[v]; }
    int countPrefix(const string& s) const { int v = find(s); return v < 0 ? 0 : pass[v]; }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> q;
    Trie t;
    while (q--) {
        int op; string s; cin >> op >> s;
        if (op == 1) t.add(s, 1);
        else if (op == 2) t.add(s, -1);
        else if (op == 3) cout << t.countExact(s) << '\n';
        else cout << t.countPrefix(s) << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class Trie {
        int[] nxt = new int[26 * 16], pass = new int[16], ends = new int[16];   // node v's children: nxt[26v .. 26v+25]
        int size = 1;
        int newNode() {
            if (size == pass.length) {
                int cap = size * 2;
                nxt = Arrays.copyOf(nxt, 26 * cap); pass = Arrays.copyOf(pass, cap); ends = Arrays.copyOf(ends, cap);
            }
            return size++;
        }
        void add(String s, int d) {
            int v = 0; pass[v] += d;
            for (int i = 0; i < s.length(); i++) {
                int c = s.charAt(i) - 'a';
                if (nxt[v * 26 + c] == 0) { int u = newNode(); nxt[v * 26 + c] = u; }   // never nxt[..] = newNode()
                v = nxt[v * 26 + c]; pass[v] += d;
            }
            ends[v] += d;
        }
        int find(String s) {
            int v = 0;
            for (int i = 0; i < s.length(); i++) { v = nxt[v * 26 + s.charAt(i) - 'a']; if (v == 0) return -1; }
            return v;
        }
        int countExact(String s) { int v = find(s); return v < 0 ? 0 : ends[v]; }
        int countPrefix(String s) { int v = find(s); return v < 0 ? 0 : pass[v]; }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int q = in.nextInt();
        Trie t = new Trie();
        while (q-- > 0) {
            int op = in.nextInt();
            String s = in.next();
            if (op == 1) t.add(s, 1);
            else if (op == 2) t.add(s, -1);
            else if (op == 3) out.println(t.countExact(s));
            else out.println(t.countPrefix(s));
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
10
1 apple
1 app
1 apple
3 apple
4 app
2 apple
3 apple
4 ap
3 ap
4 b
out:
2
3
1
2
0
0
-->
<!-- test
in:
5
1 a
4 a
2 a
4 a
3 a
out:
1
0
0
-->

### 3.2 Binary trie (multiset of integers $< 2^{30}$)

Driver: `1 x` insert, `2 x` erase one copy (present), `3 x` max $x \oplus y$, `4 x` min $x \oplus y$ (multiset non-empty), `5 x k` number of stored $y$ with $x \oplus y < k$ ($k < 2^{30}$).

```cpp
#include <bits/stdc++.h>
using namespace std;

struct BinaryTrie {
    static constexpr int B = 30;                     // values in [0, 2^30)
    vector<array<int, 2>> ch;
    vector<int> cnt;                                 // how many stored values pass through the node
    BinaryTrie() { ch.push_back({0, 0}); cnt.push_back(0); }
    void add(int x, int d) {
        int v = 0; cnt[v] += d;
        for (int b = B - 1; b >= 0; b--) {
            int t = x >> b & 1;
            if (!ch[v][t]) { int u = ch.size(); ch.push_back({0, 0}); cnt.push_back(0); ch[v][t] = u; }
            v = ch[v][t]; cnt[v] += d;
        }
    }
    bool has(int v) const { return v && cnt[v] > 0; }
    int maxXor(int x) const {                        // greedy: take the opposite bit when possible
        int v = 0, res = 0;
        for (int b = B - 1; b >= 0; b--) {
            int want = (x >> b & 1) ^ 1;
            if (has(ch[v][want])) res |= 1 << b, v = ch[v][want];
            else v = ch[v][want ^ 1];
        }
        return res;
    }
    int minXor(int x) const {
        int v = 0, res = 0;
        for (int b = B - 1; b >= 0; b--) {
            int want = x >> b & 1;
            if (has(ch[v][want])) v = ch[v][want];
            else res |= 1 << b, v = ch[v][want ^ 1];
        }
        return res;
    }
    long long countLess(int x, int k) const {        // #y with (x ^ y) < k
        int v = 0; long long res = 0;
        for (int b = B - 1; b >= 0 && v >= 0; b--) {
            int xb = x >> b & 1, kb = k >> b & 1;
            if (kb) {
                if (ch[v][xb]) res += cnt[ch[v][xb]];   // XOR bit 0 here, k bit 1: all smaller
                v = ch[v][xb ^ 1] ? ch[v][xb ^ 1] : -1;
            } else v = ch[v][xb] ? ch[v][xb] : -1;
        }
        return res;
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> q;
    BinaryTrie t;
    while (q--) {
        int op, x; cin >> op >> x;
        if (op == 1) t.add(x, 1);
        else if (op == 2) t.add(x, -1);
        else if (op == 3) cout << t.maxXor(x) << '\n';
        else if (op == 4) cout << t.minXor(x) << '\n';
        else { int k; cin >> k; cout << t.countLess(x, k) << '\n'; }
    }
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    static final class BinaryTrie {
        static final int B = 30;
        int[] c0, c1, cnt;                            // children for bit 0 / bit 1, pass counts
        int size = 1;
        BinaryTrie(int maxInserts) {
            int cap = maxInserts * B + 1;
            c0 = new int[cap]; c1 = new int[cap]; cnt = new int[cap];
        }
        void add(int x, int d) {
            int v = 0; cnt[v] += d;
            for (int b = B - 1; b >= 0; b--) {
                if ((x >> b & 1) == 0) { if (c0[v] == 0) c0[v] = size++; v = c0[v]; }
                else { if (c1[v] == 0) c1[v] = size++; v = c1[v]; }
                cnt[v] += d;
            }
        }
        boolean has(int v) { return v != 0 && cnt[v] > 0; }
        int child(int v, int bit) { return bit == 0 ? c0[v] : c1[v]; }
        int maxXor(int x) {
            int v = 0, res = 0;
            for (int b = B - 1; b >= 0; b--) {
                int want = (x >> b & 1) ^ 1;
                if (has(child(v, want))) { res |= 1 << b; v = child(v, want); }
                else v = child(v, want ^ 1);
            }
            return res;
        }
        int minXor(int x) {
            int v = 0, res = 0;
            for (int b = B - 1; b >= 0; b--) {
                int want = x >> b & 1;
                if (has(child(v, want))) v = child(v, want);
                else { res |= 1 << b; v = child(v, want ^ 1); }
            }
            return res;
        }
        long countLess(int x, int k) {
            int v = 0; long res = 0;
            for (int b = B - 1; b >= 0 && v >= 0; b--) {
                int xb = x >> b & 1, kb = k >> b & 1;
                if (kb == 1) {
                    int same = child(v, xb), other = child(v, xb ^ 1);
                    if (same != 0) res += cnt[same];
                    v = other != 0 ? other : -1;
                } else {
                    int same = child(v, xb);
                    v = same != 0 ? same : -1;
                }
            }
            return res;
        }
    }

    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int q = in.nextInt();
        BinaryTrie t = new BinaryTrie(q);
        while (q-- > 0) {
            int op = in.nextInt(), x = in.nextInt();
            if (op == 1) t.add(x, 1);
            else if (op == 2) t.add(x, -1);
            else if (op == 3) out.println(t.maxXor(x));
            else if (op == 4) out.println(t.minXor(x));
            else out.println(t.countLess(x, in.nextInt()));
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
9
1 5
1 9
1 3
3 6
4 6
5 6 6
2 9
3 6
5 0 4
out:
15
3
2
5
1
-->
<!-- test
in:
4
1 0
3 0
4 1073741823
5 7 0
out:
0
1073741823
0
-->

## 4. Recognising the pattern

- **Many strings + questions about prefixes** (count words with a prefix, longest common prefix with a query, autocomplete, "is any stored word a prefix of this text") → string trie.
- **"Maximise / minimise $a \oplus b$"**, "count pairs with XOR $< k$ / in a range", "XOR of a subarray" with $n$ up to $10^5$–$10^6$ → binary trie, usually over prefix XORs.
- **Greedy over bits from the top** with a set that changes (insert/erase) → binary trie with counts.
- **Games or DP on a dictionary** (players append letters, words must stay prefixes) → DP over trie nodes; children always have larger indices than parents, so a reverse loop is a valid post-order.
- **Pattern occurrences of many words inside a text** → trie + failure links = [Aho–Corasick](06-aho-corasick.md).
- **Confused with**: [XOR basis / Gaussian elimination](../15-Advanced-Math/02-gaussian-elimination-and-xor-basis.md) (XOR of *any subset*, not of a pair); hashing (exact equality only).

## 5. Worked examples (graded)

### Example 1 — Maximum Xor Subarray · ★ ≈1700 (est.)

- **Source:** [CSES 1655 · Maximum Xor Subarray](https://cses.fi/problemset/task/1655)
- **Difficulty:** ≈1700 (est.)
- **Problem:** $n \le 2\cdot 10^5$, $0 \le a_i \le 10^9$. Find the maximum XOR of a non-empty subarray.
- **Thinking from first principles:** brute force over $O(n^2)$ subarrays is too slow, and XOR has no monotonicity for two pointers. Rewrite: subarray $(l, r]$ has XOR $P_r \oplus P_l$. So we need $\max_{l < r} P_r \oplus P_l$ — a "best partner" query against a growing set, exactly what the binary trie answers in $O(B)$. Insert $P_0 = 0$ first so that prefixes themselves count.

<details><summary>Solution</summary>

$O(n B)$ with $B = 30$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    const int B = 30;
    vector<array<int, 2>> ch(1, {0, 0});
    auto insert = [&](int x) {
        int v = 0;
        for (int b = B - 1; b >= 0; b--) {
            int t = x >> b & 1;
            if (!ch[v][t]) { int u = ch.size(); ch.push_back({0, 0}); ch[v][t] = u; }
            v = ch[v][t];
        }
    };
    auto best = [&](int x) {                          // max x ^ y over inserted y (set non-empty)
        int v = 0, res = 0;
        for (int b = B - 1; b >= 0; b--) {
            int want = (x >> b & 1) ^ 1;
            if (ch[v][want]) res |= 1 << b, v = ch[v][want];
            else v = ch[v][want ^ 1];
        }
        return res;
    };
    insert(0);
    int P = 0, ans = 0;
    for (int i = 0; i < n; i++) {
        int a; cin >> a;
        P ^= a;
        ans = max(ans, best(P));
        insert(P);
    }
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
        int n = in.nextInt();
        final int B = 30;
        int cap = (n + 1) * B + 1, size = 1;
        int[] c0 = new int[cap], c1 = new int[cap];
        int P = 0, ans = 0;
        for (int i = 0; i <= n; i++) {
            if (i > 0) {
                P ^= in.nextInt();
                int v = 0, res = 0;                       // query before inserting P
                for (int b = B - 1; b >= 0; b--) {
                    if ((P >> b & 1) == 0) { if (c1[v] != 0) { res |= 1 << b; v = c1[v]; } else v = c0[v]; }
                    else { if (c0[v] != 0) { res |= 1 << b; v = c0[v]; } else v = c1[v]; }
                }
                ans = Math.max(ans, res);
            }
            int v = 0;                                    // insert P (P_0 = 0 when i == 0)
            for (int b = B - 1; b >= 0; b--) {
                if ((P >> b & 1) == 0) { if (c0[v] == 0) c0[v] = size++; v = c0[v]; }
                else { if (c1[v] == 0) c1[v] = size++; v = c1[v]; }
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
4
5 1 5 9
out:
13
-->
<!-- test
in:
1
0
out:
0
-->
<!-- test
in:
3
1000000000 1000000000 7
out:
1000000007
-->

</details>

### Example 2 — Perfect Security · ★ 1800

- **Source:** [CF 923C · Perfect Security](https://codeforces.com/problemset/problem/923/C) — 1800
- **Difficulty:** 1800
- **Problem:** arrays $A$ and $P$ of length $N \le 3\cdot 10^5$, values $< 2^{30}$. Permute $P$ so that $O_i = A_i \oplus P_{\pi(i)}$ is lexicographically smallest; print $O$.
- **Thinking from first principles:** lexicographic order means: minimise $O_1$ first, then $O_2$ given $O_1$, and so on. Any assignment of the remaining keys is still possible later (it is a permutation, no other constraint), so greedily taking the key that minimises $A_i \oplus p$ is optimal — and the minimiser is unique as a *value* because $p \mapsto A_i \oplus p$ is injective. We need "min XOR with deletion" on a multiset: a binary trie with counts, $O(B)$ per step.

<details><summary>Solution</summary>

Insert all keys; for each $i$, walk the min-XOR path, output, erase that key. $O(NB)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; cin >> n;
    const int B = 30;
    vector<int> a(n);
    for (auto& x : a) cin >> x;
    vector<array<int, 2>> ch(1, {0, 0});
    vector<int> cnt(1, 0);
    for (int i = 0; i < n; i++) {
        int p; cin >> p;
        int v = 0; cnt[v]++;
        for (int b = B - 1; b >= 0; b--) {
            int t = p >> b & 1;
            if (!ch[v][t]) { int u = ch.size(); ch.push_back({0, 0}); cnt.push_back(0); ch[v][t] = u; }
            v = ch[v][t]; cnt[v]++;
        }
    }
    for (int i = 0; i < n; i++) {
        int v = 0, res = 0;
        cnt[0]--;
        for (int b = B - 1; b >= 0; b--) {
            int want = a[i] >> b & 1;                    // same bit -> XOR bit 0
            int u = ch[v][want];
            if (!u || cnt[u] == 0) { u = ch[v][want ^ 1]; res |= 1 << b; }
            v = u; cnt[v]--;                              // erase while walking down
        }
        cout << res << (i + 1 < n ? ' ' : '\n');
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
        int n = in.nextInt();
        final int B = 30;
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        int cap = n * B + 1, size = 1;
        int[][] ch = new int[2][cap];
        int[] cnt = new int[cap];
        for (int i = 0; i < n; i++) {
            int p = in.nextInt(), v = 0;
            cnt[v]++;
            for (int b = B - 1; b >= 0; b--) {
                int t = p >> b & 1;
                if (ch[t][v] == 0) ch[t][v] = size++;
                v = ch[t][v]; cnt[v]++;
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) {
            int v = 0, res = 0;
            cnt[0]--;
            for (int b = B - 1; b >= 0; b--) {
                int want = a[i] >> b & 1;
                int u = ch[want][v];
                if (u == 0 || cnt[u] == 0) { u = ch[want ^ 1][v]; res |= 1 << b; }
                v = u; cnt[v]--;
            }
            if (i > 0) sb.append(' ');
            sb.append(res);
        }
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
3
8 4 13
17 2 7
out:
10 3 28
-->
<!-- test
in:
1
5
5
out:
0
-->
<!-- test
in:
4
0 0 0 0
3 1 2 1
out:
1 1 2 3
-->

</details>

### Example 3 — A Lot of Games (DP on a trie) · ★ 1900

- **Source:** [CF 455B · A Lot of Games](https://codeforces.com/problemset/problem/455/B) — 1900
- **Difficulty:** 1900
- **Problem:** $n$ words (total length $\le 10^5$) and $k \le 10^9$ games. In a game, players alternately append a letter to a common string that must stay a prefix of some word; whoever cannot move loses. The loser of game $i$ moves first in game $i+1$; the winner of game $k$ wins overall. Print `First` or `Second` (who wins with optimal play).
- **Thinking from first principles:** the positions of one game are exactly the trie nodes, and the moves are the edges — a game on a tree. Compute for the player to move at node $v$: $\mathrm{win}[v]$ = can force a win (some child is a losing position for the opponent: $\exists c: \neg\mathrm{win}[c]$; leaves: false), and $\mathrm{lose}[v]$ = can force *losing* (leaves: true — you are stuck; otherwise $\exists c: \neg\mathrm{lose}[c]$). Then the series:
  - $\mathrm{win} \wedge \mathrm{lose}$ at the root: First loses games $1..k-1$ on purpose (so keeps starting) and wins game $k$ → `First`.
  - $\mathrm{win} \wedge \neg\mathrm{lose}$: the starter of each game wins it, so the winner alternates; game $k$ is won by First iff $k$ is odd.
  - $\neg\mathrm{win}$: the starter always loses, so the loser (First) starts again and loses every game → `Second`.
  Implementation note: nodes are created in insertion order, so every child has a larger index than its parent — iterating indices downward is a post-order. No recursion (Java-safe at depth $10^5$).

<details><summary>Solution</summary>

$O(\sum|s| \cdot 26)$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n; long long k;
    cin >> n >> k;
    vector<array<int, 26>> nxt(1);
    nxt[0].fill(0);
    for (int i = 0; i < n; i++) {
        string s; cin >> s;
        int v = 0;
        for (char ch : s) {
            int c = ch - 'a';
            if (!nxt[v][c]) { int u = nxt.size(); nxt.emplace_back(); nxt.back().fill(0); nxt[v][c] = u; }
            v = nxt[v][c];
        }
    }
    int m = nxt.size();
    vector<char> win(m), lose(m);
    for (int v = m - 1; v >= 0; v--) {                  // children have larger indices
        bool leaf = true, w = false, l = false;
        for (int c = 0; c < 26; c++) if (int u = nxt[v][c]) {
            leaf = false;
            if (!win[u]) w = true;
            if (!lose[u]) l = true;
        }
        win[v] = w; lose[v] = leaf ? true : l;
    }
    bool first;
    if (win[0] && lose[0]) first = true;
    else if (win[0]) first = (k % 2 == 1);
    else first = false;
    cout << (first ? "First" : "Second") << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt();
        long k = in.nextLong();
        String[] words = new String[n];
        int total = 1;
        for (int i = 0; i < n; i++) { words[i] = in.next(); total += words[i].length(); }
        int[] nxt = new int[26 * total];
        int size = 1;
        for (String s : words) {
            int v = 0;
            for (int i = 0; i < s.length(); i++) {
                int c = s.charAt(i) - 'a';
                if (nxt[v * 26 + c] == 0) nxt[v * 26 + c] = size++;
                v = nxt[v * 26 + c];
            }
        }
        boolean[] win = new boolean[size], lose = new boolean[size];
        for (int v = size - 1; v >= 0; v--) {
            boolean leaf = true, w = false, l = false;
            for (int c = 0; c < 26; c++) {
                int u = nxt[v * 26 + c];
                if (u == 0) continue;
                leaf = false;
                if (!win[u]) w = true;
                if (!lose[u]) l = true;
            }
            win[v] = w; lose[v] = leaf || l;
        }
        boolean first;
        if (win[0] && lose[0]) first = true;
        else if (win[0]) first = (k % 2 == 1);
        else first = false;
        out.println(first ? "First" : "Second");
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
2 2
a
bc
out:
First
-->

</details>

### Example 4 — Choosing The Commander (count XOR $< k$) · ★ 2000

- **Source:** [CF 817E · Choosing The Commander](https://codeforces.com/problemset/problem/817/E) — 2000
- **Difficulty:** 2000
- **Problem:** $q \le 10^5$ events on a multiset of integers $\le 10^8$: `1 p` add $p$, `2 p` remove one $p$, `3 p l` print how many stored $x$ satisfy $x \oplus p < l$.
- **Thinking from first principles:** a sorted structure does not help — the condition $x \oplus p < l$ is not an interval in $x$. Compare $x \oplus p$ with $l$ bit by bit from the top: as long as they agree, keep walking; at the first bit where $l$ has a 1 and $x \oplus p$ has a 0, *all* lower bits are irrelevant — the whole subtree is counted at once. That is exactly the `countLess` walk of §3.2, with insertions and deletions as count updates. $10^8 < 2^{27}$, so 27 bits suffice.

<details><summary>Solution</summary>

$O(qB)$, $B = 27$.

```cpp
#include <bits/stdc++.h>
using namespace std;
int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int q; cin >> q;
    const int B = 27;
    vector<array<int, 2>> ch(1, {0, 0});
    vector<int> cnt(1, 0);
    while (q--) {
        int op, p; cin >> op >> p;
        if (op <= 2) {
            int d = op == 1 ? 1 : -1, v = 0;
            for (int b = B - 1; b >= 0; b--) {
                int t = p >> b & 1;
                if (!ch[v][t]) { int u = ch.size(); ch.push_back({0, 0}); cnt.push_back(0); ch[v][t] = u; }
                v = ch[v][t]; cnt[v] += d;
            }
        } else {
            int l; cin >> l;
            long long res = 0;
            int v = 0;
            for (int b = B - 1; b >= 0 && v >= 0; b--) {
                int pb = p >> b & 1, lb = l >> b & 1;
                if (lb) {
                    if (ch[v][pb]) res += cnt[ch[v][pb]];      // XOR bit 0 < l bit 1
                    v = ch[v][pb ^ 1] ? ch[v][pb ^ 1] : -1;
                } else v = ch[v][pb] ? ch[v][pb] : -1;
            }
            cout << res << '\n';
        }
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
        int q = in.nextInt();
        final int B = 27;
        int cap = q * B + 1, size = 1;
        int[][] ch = new int[2][cap];
        int[] cnt = new int[cap];
        while (q-- > 0) {
            int op = in.nextInt(), p = in.nextInt();
            if (op <= 2) {
                int d = op == 1 ? 1 : -1, v = 0;
                for (int b = B - 1; b >= 0; b--) {
                    int t = p >> b & 1;
                    if (ch[t][v] == 0) ch[t][v] = size++;
                    v = ch[t][v]; cnt[v] += d;
                }
            } else {
                int l = in.nextInt(), v = 0;
                long res = 0;
                for (int b = B - 1; b >= 0 && v >= 0; b--) {
                    int pb = p >> b & 1, lb = l >> b & 1;
                    if (lb == 1) {
                        if (ch[pb][v] != 0) res += cnt[ch[pb][v]];
                        v = ch[pb ^ 1][v] != 0 ? ch[pb ^ 1][v] : -1;
                    } else v = ch[pb][v] != 0 ? ch[pb][v] : -1;
                }
                out.println(res);
            }
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
5
1 3
1 4
3 6 3
2 4
3 6 3
out:
1
0
-->
<!-- test
in:
6
1 100000000
1 100000000
3 0 100000001
3 100000000 1
2 100000000
3 100000000 0
out:
2
2
0
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Fix the bit width from the constraints** ($B = 30$ for $< 2^{30}$, 31 for `int` up to $2^{31}-1$, 60+ for `long long`). A too-small $B$ silently drops high bits.
2. **Pre-size the arrays.** Nodes $\le 1 + nB$ (binary) or $1 + \sum|s|$ (strings). Growing `vector`s is fine in C++; in Java allocate `int[]` of the exact bound — `ArrayList<int[]>` per node is several times slower and heavier.
3. **Java evaluation order trap:** in `nxt[i] = newNode()`, Java evaluates the array reference `nxt` *before* calling `newNode()`; if `newNode()` reallocates, the write goes to the old array. Store the result in a local first. (C++17 sequences the right side first, but the same local-variable habit is safest with `vector::push_back`.)
4. **Erasure with counts**: keep `cnt` on nodes and test `cnt > 0`, not just "child exists", in max/min queries — otherwise you walk into emptied subtrees.
5. **Memory for 26-ary tries**: $10^6$ nodes $\times 26$ ints = 104 MB. If memory is tight, use a binary trie on the bits of characters, a `map` per node (slower), or sort-based alternatives.
6. **Insert $P_0 = 0$** before subarray-XOR queries, otherwise subarrays starting at index 1 are missed.
7. **Ties in count-less queries**: $x \oplus y = k$ is *not* less than $k$; the walk ends after bit 0 without adding the equal path.
8. **Recursion on tries**: depth = longest word ($10^5$–$10^6$). Use the "children have larger indices" order (reverse index loop) or an explicit stack.
9. **Prefix queries on an empty string**: `pass[root]` is the number of stored words — make sure the root's `pass` is maintained.

## 7. Going further (toward 2400–2600+)

- **Persistent binary trie (🔴).** Insert prefix XORs one by one, creating a new root per version by copying only the $B$ nodes on the insertion path; node counts make version $r$ minus version $l-1$ a trie of the values in a range. "Max $x \oplus a_i$ over $i \in [l, r]$" then walks both roots simultaneously, choosing a child when its count difference is positive — $O(B)$ per query, $O(nB)$ memory. See [persistent data structures](../08-Data-Structures/08-persistent-data-structures.md) and [CF 1777F · Comfortably Numb](https://codeforces.com/problemset/problem/1777/F) — 2400.
- **XOR-MST** ([CF 888G · Xor-MST](https://codeforces.com/problemset/problem/888/G) — 2300): Borůvka / divide and conquer on the binary trie — the two subtrees of a node are connected by exactly one edge whose weight is a min-XOR query.
- **Trie merging (small-to-large)** on trees: keep a binary trie per subtree and merge smaller into larger, see [small-to-large](../10-Trees/03-small-to-large-and-dsu-on-tree.md).
- **DP whose state is "the trie node"** with a binary trie over *indices*: [CF 1720D2 · Xor-Subsequence (hard version)](https://codeforces.com/problemset/problem/1720/D2) — 2400 stores the best DP value per trie path.
- **Global XOR shift**: queries "XOR every element with $x$" on a binary trie are handled lazily by flipping the meaning of children at the bits of an accumulated mask — [CF 842D · Vitya and Strange Lesson](https://codeforces.com/problemset/problem/842/D) — 2000.
- **Suffix trie → suffix tree / automaton**: inserting all suffixes into a trie gives $O(n^2)$ nodes; compressing it is the [suffix automaton](08-suffix-automaton.md) / suffix tree story.

For revision, the formulas and templates of this file are condensed in the [strings cheat sheet](../99-Cheat-Sheets/11-strings-cheatsheet.md).

## 8. Practice ladder

**≤ 1800**
- [ ] [CSES 1655 · Maximum Xor Subarray](https://cses.fi/problemset/task/1655) — ≈1700 (est.)
- [ ] [CF 706D · Vasiliy's Multiset](https://codeforces.com/problemset/problem/706/D) — 1800
- [ ] [CF 923C · Perfect Security](https://codeforces.com/problemset/problem/923/C) — 1800
- [ ] [CSES 1731 · Word Combinations](https://cses.fi/problemset/task/1731) — trie + DP, ≈1800 (est.)

**1900–2100**
- [ ] [CF 455B · A Lot of Games](https://codeforces.com/problemset/problem/455/B) — 1900
- [ ] [CF 1285D · Dr. Evil Underscores](https://codeforces.com/problemset/problem/1285/D) — 1900
- [ ] [CF 1902E · Collapsing Strings](https://codeforces.com/problemset/problem/1902/E) — 1900
- [ ] [CF 633C · Spy Syndrome 2](https://codeforces.com/problemset/problem/633/C) — 1900
- [ ] [CF 817E · Choosing The Commander](https://codeforces.com/problemset/problem/817/E) — 2000
- [ ] [CF 842D · Vitya and Strange Lesson](https://codeforces.com/problemset/problem/842/D) — 2000
- [ ] [CF 665E · Beautiful Subarrays](https://codeforces.com/problemset/problem/665/E) — 2100

**2200–2400**
- [ ] [CF 282E · Sausage Maximization](https://codeforces.com/problemset/problem/282/E) — 2200
- [ ] [CF 979D · Kuro and GCD and XOR and SUM](https://codeforces.com/problemset/problem/979/D) — 2200
- [ ] [CF 888G · Xor-MST](https://codeforces.com/problemset/problem/888/G) — 2300
- [ ] [CF 1658D2 · 388535 (Hard Version)](https://codeforces.com/problemset/problem/1658/D2) — 2300
- [ ] [CF 1720D2 · Xor-Subsequence (hard version)](https://codeforces.com/problemset/problem/1720/D2) — 2400
- [ ] [CF 1777F · Comfortably Numb](https://codeforces.com/problemset/problem/1777/F) — 2400

**2500+**
- [ ] [CF 1055F · Tree and XOR](https://codeforces.com/problemset/problem/1055/F) — 2900

## 9. LeetCode / FAANG cross-reference

Tries are an interview favourite: they test data-structure design, recursion/iteration over a tree, and memory reasoning. The interview-style walkthrough lives in [FAANG: tries](../17-FAANG-Interview-DSA/08-tries.md).

- [LC 208 · Implement Trie (Prefix Tree)](https://leetcode.com/problems/implement-trie-prefix-tree/) — Medium — §3.1 without counts.
- [LC 211 · Design Add and Search Words Data Structure](https://leetcode.com/problems/design-add-and-search-words-data-structure/) — Medium — `.` wildcard = DFS over all children at that depth.
- [LC 212 · Word Search II](https://leetcode.com/problems/word-search-ii/) — Hard — trie of the words drives the grid DFS; prune emptied branches.
- [LC 1268 · Search Suggestions System](https://leetcode.com/problems/search-suggestions-system/) — Medium — autocomplete: store the 3 lexicographically smallest words per node (or sort + binary search).
- [LC 642 · Design Search Autocomplete System](https://leetcode.com/problems/design-search-autocomplete-system/) — Hard 🔒 — autocomplete with frequencies: top-3 per node, updated on insert.
- [LC 677 · Map Sum Pairs](https://leetcode.com/problems/map-sum-pairs/) — Medium — `pass`-style sums on nodes.
- [LC 648 · Replace Words](https://leetcode.com/problems/replace-words/) — Medium — shortest stored prefix of each word.
- [LC 720 · Longest Word in Dictionary](https://leetcode.com/problems/longest-word-in-dictionary/) — Medium — DFS through nodes that end words.
- [LC 2416 · Sum of Prefix Scores of Strings](https://leetcode.com/problems/sum-of-prefix-scores-of-strings/) — Hard — sum of `pass` along each word's path.
- [LC 3093 · Longest Common Suffix Queries](https://leetcode.com/problems/longest-common-suffix-queries/) — Hard — trie of reversed words, best index stored per node.
- [LC 3045 · Count Prefix and Suffix Pairs II](https://leetcode.com/problems/count-prefix-and-suffix-pairs-ii/) — Hard — trie keyed by (prefix char, suffix char) pairs.
- [LC 421 · Maximum XOR of Two Numbers in an Array](https://leetcode.com/problems/maximum-xor-of-two-numbers-in-an-array/) — Medium — binary trie, greedy opposite bit.
- [LC 1707 · Maximum XOR With an Element From Array](https://leetcode.com/problems/maximum-xor-with-an-element-from-array/) — Hard — offline: sort queries by limit, insert numbers as the limit grows.
- [LC 1803 · Count Pairs With XOR in a Range](https://leetcode.com/problems/count-pairs-with-xor-in-a-range/) — Hard — $\mathrm{cnt}(< high+1) - \mathrm{cnt}(< low)$.
- [LC 2935 · Maximum Strong Pair XOR II](https://leetcode.com/problems/maximum-strong-pair-xor-ii/) — Hard — sliding window with insert/erase in a binary trie.
- [LC 1938 · Maximum Genetic Difference Query](https://leetcode.com/problems/maximum-genetic-difference-query/) — Hard — DFS over the tree with insert on entry, erase on exit.
- [LC 14 · Longest Common Prefix](https://leetcode.com/problems/longest-common-prefix/) — Easy — the trie answer is the path while nodes have one child and no word ends.
- [LC 745 · Prefix and Suffix Search](https://leetcode.com/problems/prefix-and-suffix-search/) — Hard — insert `suffix + '{' + word` for every suffix, query `suffix{prefix`.

## 10. Self-check

1. What do `pass` and `end` store, and how do they give exact counts, prefix counts and deletion?
2. How many nodes can a trie of $n$ words of total length $S$ have? What does a `next[node][26]` array cost at $S = 10^6$?
3. Prove that the greedy "take the opposite bit" gives the maximum XOR.
4. Derive the `countLess(x, k)` walk. Why is the path where $x \oplus y = k$ not counted?
5. Why is the XOR of $a_l..a_r$ equal to $P_r \oplus P_{l-1}$, and why must $P_0 = 0$ be inserted?
6. Show that the minimum XOR over pairs is achieved by two elements adjacent in sorted order.
7. In Example 3, why does iterating node indices from high to low give a valid post-order?

<details><summary>Answers</summary>

1. `pass[v]` = number of stored words whose path goes through $v$; `end[v]` = number ending exactly at $v$. Exact count = `end` at the word's node; prefix count = `pass` at the prefix's node; deletion = decrement both along the path (nodes may stay with zero counts).
2. At most $S + 1$ nodes. $26 \cdot 4 \cdot 10^6$ bytes $\approx 104$ MB for the child array alone.
3. At bit $b$, any $y$ giving result bit 1 beats any $y$ giving 0, because the lower bits contribute at most $2^b - 1 < 2^b$. Among the remaining candidates (those consistent with the higher choices) the trie tells whether one with the opposite bit exists, so choosing it whenever possible yields the maximum by induction from the top.
4. Walk the path along which $x \oplus y$ equals $k$ on all processed bits. At a bit where $k$ has 1, the subtree giving XOR bit 0 is entirely smaller — add its count — and the equal-path continues into the other child; where $k$ has 0, the equal path continues into the child giving XOR bit 0 (bit 1 would make it larger). After the last bit the remaining path equals $k$, which is not strictly smaller.
5. $P_r \oplus P_{l-1} = (a_1 \oplus \dots \oplus a_{l-1}) \oplus (a_1 \oplus \dots \oplus a_r)$ and each $a_i$ with $i < l$ appears twice, cancelling. Subarrays with $l = 1$ need the partner $P_0 = 0$.
6. For $a < b < c$, with $t$ the highest differing bit of $a$ and $c$, $b$ shares bit $t$ with one of them and agrees with both above $t$, so that pair's XOR is $< 2^t \le a \oplus c$. Hence a non-adjacent pair is never strictly better than some adjacent pair.
7. A node is created when its parent already exists, so its index is larger; processing indices in decreasing order visits every child before its parent.

</details>
