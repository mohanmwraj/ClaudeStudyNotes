# Aho–Corasick automaton

> **Band:** 🟠 2100–2400 · **Priority:** ⚡ · **FAANG:** low · **Prerequisites:** [prefix function / KMP](02-prefix-function-kmp.md), [trie](05-trie-and-binary-trie.md), [BFS](../09-Graphs/01-graph-representation-bfs-dfs.md), [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md)
> **You can say you know this when:** you can build the goto/failure automaton of a dictionary in $O(m\sigma)$ from memory, count the occurrences of *every* pattern in a text in $O(n+m)$ by pushing counts up the failure tree, and turn "strings that avoid / contain these words" into a DP over automaton states.

## 1. First principles — why this works

### 1.1 The problem and the naive approaches

We have a dictionary $P_1,\dots,P_k$ with total length $m=\sum|P_i|$, a text $T$ of length $n$, alphabet size $\sigma$.
Typical questions: which patterns occur in $T$, how many times each, where, or how many strings of length $L$ avoid all of them.

- Compare every pattern at every position: $O(n\cdot m)$.
- Run [KMP](02-prefix-function-kmp.md) once per pattern: $O(k\cdot n + m)$. With $k=10^5$ short patterns and $n=10^5$ this is $10^{10}$.
- Hash every distinct pattern length: $O(n\cdot D)$ where $D$ is the number of distinct lengths. Since $1+2+\dots+D\le m$, $D<\sqrt{2m}$, so this is $O(n\sqrt m)$ — sometimes enough, never optimal.

The waste in "KMP per pattern": we run $k$ matchers in parallel and each stores "how much of *my* pattern is matched".
All $k$ numbers are determined by a single quantity, which is what Aho–Corasick stores.

### 1.2 The one state that carries everything

Put the patterns in a [trie](05-trie-and-binary-trie.md). Each trie node $v$ spells a string $\mathrm{str}(v)$, a prefix of some pattern.
After reading $T[0..i]$ define

$$\mathrm{state}(i) = \text{the node spelling the longest suffix of } T[0..i] \text{ that is a trie node}$$

(the root, the empty string, always qualifies).

**Claim.** Every pattern occurrence ending at position $i$ is a suffix of $\mathrm{str}(\mathrm{state}(i))$.
*Proof.* If $P_j$ ends at $i$, then $P_j$ is a suffix of $T[0..i]$ and $P_j$ is a trie node, so $|P_j|\le|\mathrm{str}(\mathrm{state}(i))|$ by maximality. Two suffixes of the same string, the shorter is a suffix of the longer. ∎

So $\mathrm{state}(i)$ alone decides every match that ends at $i$. The "how far is pattern $j$ matched" numbers are just the lengths of the trie-node suffixes of $\mathrm{str}(\mathrm{state}(i))$.

### 1.3 Moving the state: failure links

Define the **failure link** $\mathrm{fail}(v)$ as the node spelling the longest *proper* suffix of $\mathrm{str}(v)$ that is a trie node.
By induction, the trie nodes that are suffixes of $\mathrm{str}(v)$ are exactly the chain

$$v,\ \mathrm{fail}(v),\ \mathrm{fail}^2(v),\ \dots,\ \mathrm{root},$$

in decreasing length (any shorter one is a suffix of $\mathrm{str}(\mathrm{fail}(v))$, so it appears later in the chain).

Reading one more character $c$: the longest suffix of $T[0..i]c$ in the trie is $Sc$ where $S$ is the *longest* trie-node suffix of $T[0..i]$ that has a child $c$.
By the claim, those suffixes are the chain of $\mathrm{state}(i)$. So: walk $v,\mathrm{fail}(v),\dots$ until a node has child $c$ and step into it; if even the root has no child $c$, stay at the root.

This is exactly the KMP loop. **KMP is Aho–Corasick on a one-pattern trie**: the trie is a path and $\mathrm{fail}$ is the prefix function.

### 1.4 Computing failure links in BFS order

For a trie edge $u=\mathrm{go}(v,c)$ we have $\mathrm{str}(u)=\mathrm{str}(v)c$. Its longest proper trie suffix is (longest proper trie suffix of $\mathrm{str}(v)$ that has child $c$) $+\,c$:
walk $w=\mathrm{fail}(v),\mathrm{fail}^2(v),\dots$ until $\mathrm{go}(w,c)$ exists; then $\mathrm{fail}(u)=\mathrm{go}(w,c)$, otherwise the root.
Only strictly shallower nodes are consulted, so processing nodes **by depth (BFS)** guarantees every link we read is already final.

### 1.5 The goto automaton: precompute every walk

Instead of walking failure chains at run time, define a total transition function

$$\delta(v,c)=\begin{cases}\mathrm{go}(v,c) & \text{if the trie edge exists}\\ \delta(\mathrm{fail}(v),c) & \text{otherwise } (v\ne\mathrm{root})\\ \mathrm{root} & v=\mathrm{root},\ \text{no edge}\end{cases}$$

and then $\mathrm{fail}(\mathrm{go}(v,c))=\delta(\mathrm{fail}(v),c)$ for $v\ne\mathrm{root}$ (children of the root fail to the root).
In BFS order every $\delta(\mathrm{fail}(v),\cdot)$ is complete before $v$ is processed, so each entry is one array copy:
$O(m\sigma)$ time and memory to build, $O(1)$ per text character to match. This is a genuine DFA, which is what makes the DP of §1.8 possible.

Without $\delta$ (failure walks only, e.g. with a hash map for children when $\sigma$ is huge) building is $O(m)$ amortised: along one pattern's trie path the depth of the current failure node rises by at most one per character and every failure step lowers it, exactly the KMP potential argument; matching the text is $O(n)$ amortised by the same argument.

### 1.6 Reporting matches: three levels of cost

1. **Enumerate every match.** The *dictionary link* $\mathrm{dict}(v)$ is the first node *after* $v$ on the failure chain that is the end of a pattern. Following $v$ (if terminal), $\mathrm{dict}(v)$, $\mathrm{dict}^2(v),\dots$ visits only terminal nodes, so the cost is $O(1)$ per reported match: $O(n+\mathrm{occ})$ total.
   But $\mathrm{occ}$ can be huge. Distinct patterns ending at one position are distinct suffixes, hence of distinct lengths, so there are fewer than $\sqrt{2m}$ of them; therefore $\mathrm{occ}\le n\sqrt{2m}$, and the bound is tight (patterns $a, aa, aaa,\dots$ against $aaaa\dots$).
2. **Count occurrences of every pattern** without enumerating. Mark $\mathrm{cnt}[\mathrm{state}(i)]{+}{+}$ for each $i$. Pattern $u$ ends at $i$ iff $u$ lies on the failure chain of $\mathrm{state}(i)$, i.e. iff $\mathrm{state}(i)$ is in the subtree of $u$ in the failure tree. So $\mathrm{occ}(u)=$ subtree sum of $\mathrm{cnt}$, computed by $\mathrm{cnt}[\mathrm{fail}(u)] \mathrel{+}= \mathrm{cnt}[u]$ in reverse BFS order. $O(n+m)$.
3. **Aggregate along the chain.** Anything of the form "combine something over all patterns that end here" — how many, the shortest, the cheapest — is $\mathrm{agg}(u)=\mathrm{own}(u)\oplus\mathrm{agg}(\mathrm{fail}(u))$, computed in BFS order.

### 1.7 The failure tree

Failure links point to strictly shorter strings, so they form a tree rooted at the root. The key equivalence:

$$\mathrm{str}(u)\ \text{is a suffix of}\ \mathrm{str}(v)\iff u \text{ is an ancestor of } v \text{ in the failure tree.}$$

Consequently "how many times does pattern $j$ occur inside string $s_i$" equals the number of prefix nodes of $s_i$ (nodes on its trie path) lying in the failure-subtree of $\mathrm{end}_j$. With an [Euler tour](../10-Trees/01-tree-basics-diameter-center-euler-tour.md) and a [Fenwick tree](../08-Data-Structures/01-fenwick-tree.md) these become subtree counts — the engine behind the hardest Aho–Corasick problems.

### 1.8 DP on the automaton

Call a state *bad* if some pattern ends there: $\mathrm{bad}(v)=\mathrm{terminal}(v)\lor\mathrm{bad}(\mathrm{fail}(v))$.
A string contains no pattern iff its run from the root never enters a bad state. So "count length-$L$ strings avoiding all patterns" is a walk count in the DFA restricted to good states: $dp_{i+1}[\delta(v,c)] \mathrel{+}= dp_i[v]$, $O(L\cdot m\cdot\sigma)$, or matrix exponentiation on the $(m+1)\times(m+1)$ transition matrix when $L$ is huge (see [matrix exponentiation for DP](../07-DP-Optimizations/08-matrix-exponentiation-for-dp.md)).
"Contains at least one" is the complement; "maximise total weight of matches" adds $\mathrm{agg}(v)$ on each step.

## 2. Formulas, definitions and identities

| Quantity | Definition / recurrence | Meaning |
|---|---|---|
| $\mathrm{fail}(u)$, $u=\mathrm{go}(v,c)$ | $\mathrm{root}$ if $v=\mathrm{root}$, else $\delta(\mathrm{fail}(v),c)$ | longest proper suffix of $\mathrm{str}(u)$ in the trie |
| $\delta(v,c)$ | $\mathrm{go}(v,c)$ if it exists, else $\delta(\mathrm{fail}(v),c)$; $\delta(\mathrm{root},c)=\mathrm{root}$ if no edge | DFA transition |
| suffix chain | $\{w:\mathrm{str}(w)\ \text{suffix of}\ \mathrm{str}(v)\}=\{v,\mathrm{fail}(v),\dots,\mathrm{root}\}$ | all trie suffixes of a state |
| $\mathrm{dict}(u)$ | $\mathrm{fail}(u)$ if $\mathrm{fail}(u)$ is terminal, else $\mathrm{dict}(\mathrm{fail}(u))$ | next terminal on the chain |
| $\mathrm{occ}(P_j,T)$ | $\sum_{w\in\mathrm{subtree}_{\mathrm{fail}}(\mathrm{end}_j)}\mathrm{cnt}(w)$ | occurrences of every pattern |
| $\mathrm{agg}(u)$ | $\mathrm{own}(u)\oplus\mathrm{agg}(\mathrm{fail}(u))$ | combine over all patterns ending at $u$ |
| $\mathrm{bad}(u)$ | $\mathrm{terminal}(u)\lor\mathrm{bad}(\mathrm{fail}(u))$ | some pattern ends here |

- **Size:** at most $m+1$ nodes; the goto table has $(m+1)\sigma$ entries (for $m=10^6$, $\sigma=26$: 104 MB of `int` — use failure walks or a smaller alphabet then).
- **Depth:** $|\mathrm{str}(\mathrm{fail}(u))|\le|\mathrm{str}(u)|-1$, so failure links form a tree and reverse BFS order is a valid bottom-up order.
- **Distinct lengths bound:** distinct patterns ending at one text position $<\sqrt{2m}$ (their lengths are distinct and sum to at most $m$); so $\mathrm{occ}\le n\sqrt{2m}$.
- **Avoiding count:** $dp_0[\mathrm{root}]=1$, $dp_{i+1}[u]=\sum_{v\ \text{good},\ \delta(v,c)=u,\ u\ \text{good}} dp_i[v]$, answer $\sum_v dp_L[v]$. Cost $O(Lm\sigma)$, or $O(m^3\log L)$ with matrix power.
- **Two-sided counts:** with a second automaton on reversed patterns run on reversed $T$, $\mathrm{start}[i]$ = number of patterns starting at $i$; pairs "pattern ending at $i$ then pattern starting at $i+1$" number $\sum_i \mathrm{end}[i]\cdot\mathrm{start}[i+1]$.

| Operation | Goto table | Failure walks + map |
|---|---|---|
| build | $O(m\sigma)$ | $O(m\log\sigma)$ amortised |
| feed one character | $O(1)$ | $O(1)$ amortised |
| count all patterns' occurrences | $O(n+m)$ | $O(n+m)$ (+map cost) |
| enumerate all matches | $O(n+\mathrm{occ})$ | $O(n+\mathrm{occ})$ |
| memory | $O(m\sigma)$ | $O(m)$ |

## 3. Implementation (C++ and Java)

### 3.1 Goto automaton and the occurrence count of every pattern

Input: text $T$, then $k$, then $k$ patterns (lowercase; duplicates allowed). Output: the number of occurrences of each pattern (this is the format of [CSES 2103 · Counting Patterns](https://cses.fi/problemset/task/2103)).
The `bfs` array (non-root nodes by depth) is kept because reverse BFS order is the bottom-up order of the failure tree.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct AhoCorasick {
    static constexpr int A = 26;
    vector<array<int, A>> go;   // trie edges; after build() the full goto function delta
    vector<int> fail, bfs;      // bfs = non-root nodes in BFS (depth) order
    AhoCorasick() { addNode(); }
    int addNode() {
        array<int, A> row; row.fill(-1);
        go.push_back(row); fail.push_back(0);
        return (int)go.size() - 1;
    }
    int insert(const string& s) {          // returns the node where s ends
        int v = 0;
        for (char ch : s) {
            int c = ch - 'a';
            if (go[v][c] == -1) { int u = addNode(); go[v][c] = u; }  // addNode may reallocate go
            v = go[v][c];
        }
        return v;
    }
    void build() {
        bfs.clear();
        for (int c = 0; c < A; c++) {
            int u = go[0][c];
            if (u == -1) go[0][c] = 0;            // missing root edge loops to the root
            else { fail[u] = 0; bfs.push_back(u); }
        }
        for (size_t h = 0; h < bfs.size(); h++) {
            int v = bfs[h];
            for (int c = 0; c < A; c++) {
                int u = go[v][c];
                if (u == -1) go[v][c] = go[fail[v]][c];   // borrow the transition of fail(v)
                else { fail[u] = go[fail[v]][c]; bfs.push_back(u); }
            }
        }
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string text; int k;
    cin >> text >> k;
    AhoCorasick ac;
    vector<int> endNode(k);
    for (int i = 0; i < k; i++) { string p; cin >> p; endNode[i] = ac.insert(p); }
    ac.build();
    vector<long long> cnt(ac.go.size(), 0);
    int v = 0;
    for (char ch : text) { v = ac.go[v][ch - 'a']; cnt[v]++; }
    for (int i = (int)ac.bfs.size() - 1; i >= 0; i--) {   // subtree sums in the failure tree
        int u = ac.bfs[i];
        cnt[ac.fail[u]] += cnt[u];
    }
    string out;
    for (int i = 0; i < k; i++) { out += to_string(cnt[endNode[i]]); out += '\n'; }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String text = in.next();
        int k = in.nextInt();
        String[] pat = new String[k];
        int total = 1;
        for (int i = 0; i < k; i++) { pat[i] = in.next(); total += pat[i].length(); }
        AhoCorasick ac = new AhoCorasick(total);
        int[] endNode = new int[k];
        for (int i = 0; i < k; i++) endNode[i] = ac.insert(pat[i]);
        ac.build();
        long[] cnt = new long[ac.size];
        int v = 0;
        for (int i = 0; i < text.length(); i++) { v = ac.go[v * 26 + (text.charAt(i) - 'a')]; cnt[v]++; }
        for (int i = ac.bfsLen - 1; i >= 0; i--) { int u = ac.bfs[i]; cnt[ac.fail[u]] += cnt[u]; }
        for (int i = 0; i < k; i++) out.println(cnt[endNode[i]]);
        out.flush();
    }

    static final class AhoCorasick {
        static final int A = 26;
        final int[] go, fail, bfs;        // go is a flat table: go[node * A + c]
        int size = 1, bfsLen = 0;
        AhoCorasick(int maxNodes) {
            go = new int[maxNodes * A]; Arrays.fill(go, -1);
            fail = new int[maxNodes]; bfs = new int[maxNodes];
        }
        int insert(String s) {
            int v = 0;
            for (int i = 0; i < s.length(); i++) {
                int c = s.charAt(i) - 'a';
                if (go[v * A + c] == -1) go[v * A + c] = size++;
                v = go[v * A + c];
            }
            return v;
        }
        void build() {
            for (int c = 0; c < A; c++) {
                int u = go[c];
                if (u == -1) go[c] = 0; else { fail[u] = 0; bfs[bfsLen++] = u; }
            }
            for (int h = 0; h < bfsLen; h++) {
                int v = bfs[h];
                for (int c = 0; c < A; c++) {
                    int u = go[v * A + c];
                    if (u == -1) go[v * A + c] = go[fail[v] * A + c];
                    else { fail[u] = go[fail[v] * A + c]; bfs[bfsLen++] = u; }
                }
            }
        }
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
4
aba
bab
abababab
a
out:
3
2
0
4
-->
<!-- test
in:
aaaa
4
a
aa
aaa
aa
out:
4
3
2
3
-->
<!-- test
in:
z
1
z
out:
1
-->

### 3.2 Dictionary links: listing every match

Output the total number of (position, pattern) matches, then for every end position $i$ (1-based) that has a match, the line `i id id …` with pattern ids (1-based) in decreasing pattern length, equal patterns by increasing id.
`dict[u]` skips non-terminal nodes so each step of the inner loop reports something.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct AhoCorasick {                       // identical to §3.1, compacted
    static constexpr int A = 26;
    vector<array<int, A>> go; vector<int> fail, bfs;
    AhoCorasick() { addNode(); }
    int addNode() { array<int, A> r; r.fill(-1); go.push_back(r); fail.push_back(0); return (int)go.size() - 1; }
    int insert(const string& s) {
        int v = 0;
        for (char ch : s) { int c = ch - 'a'; if (go[v][c] == -1) { int u = addNode(); go[v][c] = u; } v = go[v][c]; }
        return v;
    }
    void build() {
        for (int c = 0; c < A; c++) { int u = go[0][c]; if (u == -1) go[0][c] = 0; else { fail[u] = 0; bfs.push_back(u); } }
        for (size_t h = 0; h < bfs.size(); h++) for (int v = bfs[h], c = 0; c < A; c++) {
            int u = go[v][c];
            if (u == -1) go[v][c] = go[fail[v]][c]; else { fail[u] = go[fail[v]][c]; bfs.push_back(u); }
        }
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string text; int k;
    cin >> text >> k;
    AhoCorasick ac;
    vector<int> endNode(k);
    for (int i = 0; i < k; i++) { string p; cin >> p; endNode[i] = ac.insert(p); }
    ac.build();
    int N = ac.go.size();
    vector<vector<int>> ids(N);
    for (int i = 0; i < k; i++) ids[endNode[i]].push_back(i + 1);
    vector<int> dict(N, -1);                                  // -1 = no terminal on the rest of the chain
    for (int u : ac.bfs) { int f = ac.fail[u]; dict[u] = ids[f].empty() ? dict[f] : f; }
    long long total = 0;
    string body;
    int v = 0;
    for (int i = 0; i < (int)text.size(); i++) {
        v = ac.go[v][text[i] - 'a'];
        int x = ids[v].empty() ? dict[v] : v;
        if (x == -1) continue;
        body += to_string(i + 1);
        for (; x != -1; x = dict[x])
            for (int id : ids[x]) { body += ' '; body += to_string(id); total++; }
        body += '\n';
    }
    cout << total << '\n' << body;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String text = in.next();
        int k = in.nextInt();
        String[] pat = new String[k];
        int total = 1;
        for (int i = 0; i < k; i++) { pat[i] = in.next(); total += pat[i].length(); }
        AhoCorasick ac = new AhoCorasick(total);
        int[] endNode = new int[k];
        for (int i = 0; i < k; i++) endNode[i] = ac.insert(pat[i]);
        ac.build();
        int N = ac.size;
        int[] head = new int[N], nextId = new int[k];
        Arrays.fill(head, -1);
        for (int i = k - 1; i >= 0; i--) { nextId[i] = head[endNode[i]]; head[endNode[i]] = i; } // lists by increasing id
        int[] dict = new int[N];
        dict[0] = -1;
        for (int h = 0; h < ac.bfsLen; h++) { int u = ac.bfs[h], f = ac.fail[u]; dict[u] = head[f] == -1 ? dict[f] : f; }
        long matches = 0;
        StringBuilder body = new StringBuilder();
        int v = 0;
        for (int i = 0; i < text.length(); i++) {
            v = ac.go[v * 26 + (text.charAt(i) - 'a')];
            int x = head[v] == -1 ? dict[v] : v;
            if (x == -1) continue;
            body.append(i + 1);
            for (; x != -1; x = dict[x])
                for (int id = head[x]; id != -1; id = nextId[id]) { body.append(' ').append(id + 1); matches++; }
            body.append('\n');
        }
        out.println(matches);
        out.print(body);
        out.flush();
    }

    static final class AhoCorasick {                 // identical to §3.1, compacted
        static final int A = 26;
        final int[] go, fail, bfs; int size = 1, bfsLen = 0;
        AhoCorasick(int maxNodes) { go = new int[maxNodes * A]; Arrays.fill(go, -1); fail = new int[maxNodes]; bfs = new int[maxNodes]; }
        int insert(String s) {
            int v = 0;
            for (int i = 0; i < s.length(); i++) { int c = s.charAt(i) - 'a'; if (go[v * A + c] == -1) go[v * A + c] = size++; v = go[v * A + c]; }
            return v;
        }
        void build() {
            for (int c = 0; c < A; c++) { int u = go[c]; if (u == -1) go[c] = 0; else { fail[u] = 0; bfs[bfsLen++] = u; } }
            for (int h = 0; h < bfsLen; h++) for (int v = bfs[h], c = 0; c < A; c++) {
                int u = go[v * A + c];
                if (u == -1) go[v * A + c] = go[fail[v] * A + c]; else { fail[u] = go[fail[v] * A + c]; bfs[bfsLen++] = u; }
            }
        }
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
ushers
4
he
she
his
hers
out:
3
4 2 1
6 4
-->
<!-- test
in:
abab
3
b
ab
ab
out:
6
2 2 3 1
4 2 3 1
-->
<!-- test
in:
xyz
1
q
out:
0
-->

## 4. Recognising the pattern

- **Many patterns, one (or few) texts, total length bounded** ("$\sum|s_i|\le 10^6$"): Aho–Corasick. One pattern: plain [KMP](02-prefix-function-kmp.md) or [Z-function](03-z-function.md).
- **"For each of the $k$ words, how many times does it occur"** → count at states, then push up the failure tree. Never enumerate matches when only counts are asked.
- **"Count / optimise strings of length $L$ that do (not) contain any of these words"** → DP over automaton states (§1.8); $L\le10^{18}$ → matrix power (min-plus or max-plus if it's an optimisation).
- **"Occurrences of $s_j$ inside $s_i$" over a family of strings** → failure tree + Euler tour + Fenwick, often offline.
- **A stream of characters, answer after each one "does some word end here?"** → feed the automaton, check $\mathrm{bad}(\text{state})$.
- **Patterns over a tiny alphabet with lengths $\le 10$, huge $L$** (e.g. $\{a,b\}$, $L=10^{18}$) → automaton has few states → matrix exponentiation.
- **Confused with:** suffix automaton (one text, many *queries* arriving later, or questions about all substrings of the text) and suffix array (lexicographic questions). If the patterns are known up front and the text is scanned, it is Aho–Corasick; if the text is known and patterns come as queries, any of the three can work — pick by what else is asked.

## 5. Worked examples (graded)

### Example 1 — Longest substring avoiding forbidden words · ★ ≈1900 (est.)

- **Source:** [LC 2781 · Length of the Longest Valid Substring](https://leetcode.com/problems/length-of-the-longest-valid-substring/) — Hard
- **Difficulty:** ≈1900 (est.)
- **Problem:** given a word $w$ ($|w|\le10^5$) and $k$ forbidden strings (total length $\le 2\cdot10^5$), find the length of the longest substring of $w$ that contains no forbidden string as a substring.
- **Thinking from first principles:** a substring $[l,r]$ is valid iff no forbidden occurrence lies inside it. Sweep $r$ left to right and keep the smallest valid $l$ — it only moves right (two pointers). Occurrences *ending* at $r$ start at $r-L+1$ for each forbidden length $L$ ending there; they force $l\ge r-L+2$, and the binding one is the **shortest** forbidden string ending at $r$. Brute force checks up to $10$ lengths per $r$ with hashing (fine on LeetCode where lengths $\le10$); in general we want "shortest pattern ending at this state", which is the chain aggregate $\mathrm{sh}(u)=\min(\mathrm{own}(u),\mathrm{sh}(\mathrm{fail}(u)))$ from §1.6.

<details><summary>Solution</summary>

Build the automaton; $\mathrm{sh}[\mathrm{end}_j]=|P_j|$, everything else $\infty$; in BFS order $\mathrm{sh}[u]=\min(\mathrm{sh}[u],\mathrm{sh}[\mathrm{fail}(u)])$. Scan $w$: after character $r$ (0-based) at state $v$, if $\mathrm{sh}[v]<\infty$ set $l=\max(l,\,r-\mathrm{sh}[v]+2)$; answer $\max(r-l+1)$.
Correctness: the forbidden strings ending at $r$ are exactly the terminal nodes on the chain of $v$ (§1.2), and the shortest gives the largest start. $O((n+m)\sigma)$ build, $O(n)$ scan.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct AhoCorasick {                       // identical to §3.1, compacted
    static constexpr int A = 26;
    vector<array<int, A>> go; vector<int> fail, bfs;
    AhoCorasick() { addNode(); }
    int addNode() { array<int, A> r; r.fill(-1); go.push_back(r); fail.push_back(0); return (int)go.size() - 1; }
    int insert(const string& s) {
        int v = 0;
        for (char ch : s) { int c = ch - 'a'; if (go[v][c] == -1) { int u = addNode(); go[v][c] = u; } v = go[v][c]; }
        return v;
    }
    void build() {
        for (int c = 0; c < A; c++) { int u = go[0][c]; if (u == -1) go[0][c] = 0; else { fail[u] = 0; bfs.push_back(u); } }
        for (size_t h = 0; h < bfs.size(); h++) for (int v = bfs[h], c = 0; c < A; c++) {
            int u = go[v][c];
            if (u == -1) go[v][c] = go[fail[v]][c]; else { fail[u] = go[fail[v]][c]; bfs.push_back(u); }
        }
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string w; int k;
    cin >> w >> k;
    AhoCorasick ac;
    vector<pair<int, int>> ends;                     // (node, length)
    for (int i = 0; i < k; i++) { string p; cin >> p; ends.push_back({ac.insert(p), (int)p.size()}); }
    ac.build();
    const int INF = INT_MAX;
    vector<int> sh(ac.go.size(), INF);
    for (auto [node, len] : ends) sh[node] = min(sh[node], len);
    for (int u : ac.bfs) sh[u] = min(sh[u], sh[ac.fail[u]]);   // fail(u) is processed earlier
    int v = 0, l = 0, best = 0;
    for (int r = 0; r < (int)w.size(); r++) {
        v = ac.go[v][w[r] - 'a'];
        if (sh[v] != INF) l = max(l, r - sh[v] + 2);
        best = max(best, r - l + 1);
    }
    cout << best << '\n';
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        String w = in.next();
        int k = in.nextInt();
        String[] pat = new String[k];
        int total = 1;
        for (int i = 0; i < k; i++) { pat[i] = in.next(); total += pat[i].length(); }
        AhoCorasick ac = new AhoCorasick(total);
        int[] sh = new int[total];
        Arrays.fill(sh, Integer.MAX_VALUE);
        for (int i = 0; i < k; i++) { int e = ac.insert(pat[i]); sh[e] = Math.min(sh[e], pat[i].length()); }
        ac.build();
        for (int h = 0; h < ac.bfsLen; h++) { int u = ac.bfs[h]; sh[u] = Math.min(sh[u], sh[ac.fail[u]]); }
        int v = 0, l = 0, best = 0;
        for (int r = 0; r < w.length(); r++) {
            v = ac.go[v * 26 + (w.charAt(r) - 'a')];
            if (sh[v] != Integer.MAX_VALUE) l = Math.max(l, r - sh[v] + 2);
            best = Math.max(best, r - l + 1);
        }
        out.println(best);
        out.flush();
    }

    static final class AhoCorasick {                 // identical to §3.1, compacted
        static final int A = 26;
        final int[] go, fail, bfs; int size = 1, bfsLen = 0;
        AhoCorasick(int maxNodes) { go = new int[maxNodes * A]; Arrays.fill(go, -1); fail = new int[maxNodes]; bfs = new int[maxNodes]; }
        int insert(String s) {
            int v = 0;
            for (int i = 0; i < s.length(); i++) { int c = s.charAt(i) - 'a'; if (go[v * A + c] == -1) go[v * A + c] = size++; v = go[v * A + c]; }
            return v;
        }
        void build() {
            for (int c = 0; c < A; c++) { int u = go[c]; if (u == -1) go[c] = 0; else { fail[u] = 0; bfs[bfsLen++] = u; } }
            for (int h = 0; h < bfsLen; h++) for (int v = bfs[h], c = 0; c < A; c++) {
                int u = go[v * A + c];
                if (u == -1) go[v * A + c] = go[fail[v] * A + c]; else { fail[u] = go[fail[v] * A + c]; bfs[bfsLen++] = u; }
            }
        }
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
cbaaaabc
2
aaa
cb
out:
4
-->
<!-- test
in:
a
1
a
out:
0
-->
<!-- test
in:
abcde
2
xy
bd
out:
5
-->

</details>

### Example 2 — Counting strings that avoid a dictionary · ★ ≈2000 (est.)

- **Source:** Original problem (the same automaton DP drives [CSES 1112 · Required Substring](https://cses.fi/problemset/task/1112) and, with matrix power, [AtCoder ABC305 Ex · Banned Substrings](https://atcoder.jp/contests/abc305/tasks/abc305_g)).
- **Difficulty:** ≈2000 (est.)
- **Problem:** count strings of length $n$ over the first $\sigma$ lowercase letters that contain none of $k$ given patterns as a substring, modulo $10^9+7$. $n\le1000$, $\sigma\le26$, total pattern length $\le100$.
- **Thinking from first principles:** inclusion–exclusion over patterns explodes ($2^k$ terms with overlaps). A left-to-right generator must remember "enough of the suffix to know whether a pattern could still complete" — that is precisely $\mathrm{state}(i)$ of §1.2. Two strings with the same state have identical futures, so the count only needs (length, state). Bad states are those on whose chain a pattern ends.

<details><summary>Solution</summary>

$\mathrm{bad}(u)=\mathrm{terminal}(u)\lor\mathrm{bad}(\mathrm{fail}(u))$ in BFS order. $dp[\mathrm{root}]=1$; repeat $n$ times: for each good $v$ and letter $c<\sigma$, if $u=\delta(v,c)$ is good add $dp[v]$ to $ndp[u]$. Answer $\sum dp$. A string avoids all patterns iff no prefix ends with a pattern iff no visited state is bad. $O(n\cdot m\cdot\sigma)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct AhoCorasick {                       // identical to §3.1, compacted
    static constexpr int A = 26;
    vector<array<int, A>> go; vector<int> fail, bfs;
    AhoCorasick() { addNode(); }
    int addNode() { array<int, A> r; r.fill(-1); go.push_back(r); fail.push_back(0); return (int)go.size() - 1; }
    int insert(const string& s) {
        int v = 0;
        for (char ch : s) { int c = ch - 'a'; if (go[v][c] == -1) { int u = addNode(); go[v][c] = u; } v = go[v][c]; }
        return v;
    }
    void build() {
        for (int c = 0; c < A; c++) { int u = go[0][c]; if (u == -1) go[0][c] = 0; else { fail[u] = 0; bfs.push_back(u); } }
        for (size_t h = 0; h < bfs.size(); h++) for (int v = bfs[h], c = 0; c < A; c++) {
            int u = go[v][c];
            if (u == -1) go[v][c] = go[fail[v]][c]; else { fail[u] = go[fail[v]][c]; bfs.push_back(u); }
        }
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    const long long MOD = 1'000'000'007LL;
    int n, sigma, k;
    cin >> n >> sigma >> k;
    AhoCorasick ac;
    vector<int> ends;
    for (int i = 0; i < k; i++) { string p; cin >> p; ends.push_back(ac.insert(p)); }
    ac.build();
    int N = ac.go.size();
    vector<char> bad(N, 0);
    for (int e : ends) bad[e] = 1;
    for (int u : ac.bfs) bad[u] |= bad[ac.fail[u]];
    vector<long long> dp(N, 0), ndp(N);
    dp[0] = 1;
    for (int step = 0; step < n; step++) {
        fill(ndp.begin(), ndp.end(), 0);
        for (int v = 0; v < N; v++) {
            if (bad[v] || dp[v] == 0) continue;
            for (int c = 0; c < sigma; c++) {
                int u = ac.go[v][c];
                if (!bad[u]) ndp[u] = (ndp[u] + dp[v]) % MOD;
            }
        }
        swap(dp, ndp);
    }
    long long ans = 0;
    for (int v = 0; v < N; v++) ans = (ans + dp[v]) % MOD;
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
        final long MOD = 1_000_000_007L;
        int n = in.nextInt(), sigma = in.nextInt(), k = in.nextInt();
        String[] pat = new String[k];
        int total = 1;
        for (int i = 0; i < k; i++) { pat[i] = in.next(); total += pat[i].length(); }
        AhoCorasick ac = new AhoCorasick(total);
        boolean[] bad = new boolean[total];
        for (int i = 0; i < k; i++) bad[ac.insert(pat[i])] = true;
        ac.build();
        int N = ac.size;
        for (int h = 0; h < ac.bfsLen; h++) { int u = ac.bfs[h]; bad[u] |= bad[ac.fail[u]]; }
        long[] dp = new long[N], ndp = new long[N];
        dp[0] = 1;
        for (int step = 0; step < n; step++) {
            Arrays.fill(ndp, 0);
            for (int v = 0; v < N; v++) {
                if (bad[v] || dp[v] == 0) continue;
                for (int c = 0; c < sigma; c++) {
                    int u = ac.go[v * 26 + c];
                    if (!bad[u]) ndp[u] = (ndp[u] + dp[v]) % MOD;
                }
            }
            long[] t = dp; dp = ndp; ndp = t;
        }
        long ans = 0;
        for (int v = 0; v < N; v++) ans = (ans + dp[v]) % MOD;
        out.println(ans);
        out.flush();
    }

    static final class AhoCorasick {                 // identical to §3.1, compacted
        static final int A = 26;
        final int[] go, fail, bfs; int size = 1, bfsLen = 0;
        AhoCorasick(int maxNodes) { go = new int[maxNodes * A]; Arrays.fill(go, -1); fail = new int[maxNodes]; bfs = new int[maxNodes]; }
        int insert(String s) {
            int v = 0;
            for (int i = 0; i < s.length(); i++) { int c = s.charAt(i) - 'a'; if (go[v * A + c] == -1) go[v * A + c] = size++; v = go[v * A + c]; }
            return v;
        }
        void build() {
            for (int c = 0; c < A; c++) { int u = go[c]; if (u == -1) go[c] = 0; else { fail[u] = 0; bfs[bfsLen++] = u; } }
            for (int h = 0; h < bfsLen; h++) for (int v = bfs[h], c = 0; c < A; c++) {
                int u = go[v * A + c];
                if (u == -1) go[v * A + c] = go[fail[v] * A + c]; else { fail[u] = go[fail[v] * A + c]; bfs[bfsLen++] = u; }
            }
        }
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
3 26 1
ab
out:
17524
-->
<!-- test
in:
4 2 2
aa
bb
out:
2
-->
<!-- test
in:
5 2 1
a
out:
1
-->
<!-- test
in:
1000 26 1
zz
out:
188399000
-->

</details>

The second test: over $\{a,b\}$ avoiding $aa$ and $bb$ leaves only the two alternating strings. The last test was checked independently with the recurrence $x_n = 25x_{n-1}+25x_{n-2}$, $x_0=1$, $x_1=26$ (a string avoiding $zz$ ends either in a non-$z$ letter, or in a $z$ preceded by a non-$z$ letter).

### Example 3 — Concatenated pattern pairs · ★ 2400

- **Source:** [CF 1202E · You Are Given Some Strings...](https://codeforces.com/problemset/problem/1202/E) — 2400
- **Difficulty:** 2400
- **Problem:** text $t$ and strings $s_1..s_k$ (all lengths and sums $\le 2\cdot10^5$). Compute $\sum_{i=1}^{k}\sum_{j=1}^{k}\mathrm{occ}(s_i+s_j,\ t)$ where $+$ is concatenation.
- **Thinking from first principles:** the $k^2$ concatenations are too many to build. Look at one occurrence of $s_i+s_j$ in $t$: there is a unique *cut* position $p$ where $s_i$ ends at $p$ and $s_j$ starts at $p+1$. Conversely every pair (an $s_i$ ending at $p$, an $s_j$ starting at $p+1$) is one occurrence. So the answer factorises per cut: $\sum_p \mathrm{end}[p]\cdot\mathrm{start}[p+1]$. "Number of patterns ending at $p$" is the chain aggregate "count of terminals" (§1.6, level 3); "starting at $p$" is the same on reversed strings.

<details><summary>Solution</summary>

Automaton $F$ on $s_i$, automaton $R$ on reversed $s_i$. $\mathrm{tc}[u]$ = number of patterns ending exactly at node $u$ (duplicates counted), then $\mathrm{tc}[u]\mathrel{+}=\mathrm{tc}[\mathrm{fail}(u)]$ in BFS order. Run $F$ over $t$: $\mathrm{end}[p]=\mathrm{tc}_F[\text{state}]$; run $R$ over $t$ from right to left: $\mathrm{start}[p]=\mathrm{tc}_R[\text{state}]$. Answer $\sum_{p=0}^{|t|-2}\mathrm{end}[p]\,\mathrm{start}[p+1]$ in 64-bit: with duplicate patterns $\mathrm{end}[p],\mathrm{start}[p]\le k$, so the answer is at most $|t|\,k^2\le 8\cdot10^{15}$. $O((|t|+m)\sigma)$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct AhoCorasick {                       // identical to §3.1, compacted
    static constexpr int A = 26;
    vector<array<int, A>> go; vector<int> fail, bfs;
    AhoCorasick() { addNode(); }
    int addNode() { array<int, A> r; r.fill(-1); go.push_back(r); fail.push_back(0); return (int)go.size() - 1; }
    int insert(const string& s) {
        int v = 0;
        for (char ch : s) { int c = ch - 'a'; if (go[v][c] == -1) { int u = addNode(); go[v][c] = u; } v = go[v][c]; }
        return v;
    }
    void build() {
        for (int c = 0; c < A; c++) { int u = go[0][c]; if (u == -1) go[0][c] = 0; else { fail[u] = 0; bfs.push_back(u); } }
        for (size_t h = 0; h < bfs.size(); h++) for (int v = bfs[h], c = 0; c < A; c++) {
            int u = go[v][c];
            if (u == -1) go[v][c] = go[fail[v]][c]; else { fail[u] = go[fail[v]][c]; bfs.push_back(u); }
        }
    }
};

// tc[u] = number of patterns that are suffixes of str(u)
vector<long long> terminalCounts(AhoCorasick& ac, const vector<int>& ends) {
    vector<long long> tc(ac.go.size(), 0);
    for (int e : ends) tc[e]++;
    for (int u : ac.bfs) tc[u] += tc[ac.fail[u]];
    return tc;
}

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    string t; int k;
    cin >> t >> k;
    AhoCorasick F, R;
    vector<int> eF(k), eR(k);
    for (int i = 0; i < k; i++) {
        string s; cin >> s;
        eF[i] = F.insert(s);
        reverse(s.begin(), s.end());
        eR[i] = R.insert(s);
    }
    F.build(); R.build();
    vector<long long> tcF = terminalCounts(F, eF), tcR = terminalCounts(R, eR);
    int n = t.size();
    vector<long long> endAt(n), startAt(n);
    for (int p = 0, v = 0; p < n; p++) { v = F.go[v][t[p] - 'a']; endAt[p] = tcF[v]; }
    for (int p = n - 1, v = 0; p >= 0; p--) { v = R.go[v][t[p] - 'a']; startAt[p] = tcR[v]; }
    long long ans = 0;
    for (int p = 0; p + 1 < n; p++) ans += endAt[p] * startAt[p + 1];
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
        String t = in.next();
        int k = in.nextInt();
        String[] s = new String[k];
        int total = 1;
        for (int i = 0; i < k; i++) { s[i] = in.next(); total += s[i].length(); }
        AhoCorasick F = new AhoCorasick(total), R = new AhoCorasick(total);
        long[] tcF = new long[total], tcR = new long[total];
        for (int i = 0; i < k; i++) {
            tcF[F.insert(s[i])]++;
            tcR[R.insert(new StringBuilder(s[i]).reverse().toString())]++;
        }
        F.build(); R.build();
        for (int h = 0; h < F.bfsLen; h++) { int u = F.bfs[h]; tcF[u] += tcF[F.fail[u]]; }
        for (int h = 0; h < R.bfsLen; h++) { int u = R.bfs[h]; tcR[u] += tcR[R.fail[u]]; }
        int n = t.length();
        long[] endAt = new long[n], startAt = new long[n];
        for (int p = 0, v = 0; p < n; p++) { v = F.go[v * 26 + (t.charAt(p) - 'a')]; endAt[p] = tcF[v]; }
        for (int p = n - 1, v = 0; p >= 0; p--) { v = R.go[v * 26 + (t.charAt(p) - 'a')]; startAt[p] = tcR[v]; }
        long ans = 0;
        for (int p = 0; p + 1 < n; p++) ans += endAt[p] * startAt[p + 1];
        out.println(ans);
        out.flush();
    }

    static final class AhoCorasick {                 // identical to §3.1, compacted
        static final int A = 26;
        final int[] go, fail, bfs; int size = 1, bfsLen = 0;
        AhoCorasick(int maxNodes) { go = new int[maxNodes * A]; Arrays.fill(go, -1); fail = new int[maxNodes]; bfs = new int[maxNodes]; }
        int insert(String s) {
            int v = 0;
            for (int i = 0; i < s.length(); i++) { int c = s.charAt(i) - 'a'; if (go[v * A + c] == -1) go[v * A + c] = size++; v = go[v * A + c]; }
            return v;
        }
        void build() {
            for (int c = 0; c < A; c++) { int u = go[c]; if (u == -1) go[c] = 0; else { fail[u] = 0; bfs[bfsLen++] = u; } }
            for (int h = 0; h < bfsLen; h++) for (int v = bfs[h], c = 0; c < A; c++) {
                int u = go[v * A + c];
                if (u == -1) go[v * A + c] = go[fail[v] * A + c]; else { fail[u] = go[fail[v] * A + c]; bfs[bfsLen++] = u; }
            }
        }
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
2
a
b
out:
3
-->
<!-- test
in:
aaaa
2
a
aa
out:
8
-->
<!-- test
in:
a
1
a
out:
0
-->

</details>

Hand check of the second test: $\mathrm{end}=[1,2,2,2]$ and $\mathrm{start}=[2,2,2,1]$, so the sum over cuts is $1\cdot2+2\cdot2+2\cdot1=8$; directly, $(a,a)\to aa$ occurs 3 times, $(a,aa)$ and $(aa,a)\to aaa$ twice each, $(aa,aa)\to aaaa$ once: $3+2+2+1=8$.

### Example 4 — Occurrences inside a family of strings (failure tree + Fenwick) · ★ 2800

- **Source:** [CF 547E · Mike and Friends](https://codeforces.com/problemset/problem/547/E) — 2800
- **Difficulty:** 2800
- **Problem:** strings $s_1..s_n$ ($n\le2\cdot10^5$, $\sum|s_i|\le2\cdot10^5$). Let $\mathrm{call}(i,j)$ be the number of occurrences of $s_j$ in $s_i$. Answer $q\le5\cdot10^5$ queries $(l,r,k)$: $\sum_{i=l}^{r}\mathrm{call}(i,k)$.
- **Thinking from first principles:** an occurrence of $s_k$ inside $s_i$ ends at some prefix of $s_i$, and "$s_k$ is a suffix of that prefix" is, by §1.7, "the prefix node lies in the failure-subtree of $\mathrm{end}_k$". So $\mathrm{call}(i,k)$ = number of prefix nodes of $s_i$ inside $\mathrm{subtree}(\mathrm{end}_k)$. With an Euler tour, a subtree is a contiguous range of $\mathrm{tin}$. The sum over $i\in[l,r]$ is a difference of two prefix sums over $i$, so sweep $i=1..n$, insert $s_i$'s prefix nodes into a Fenwick tree indexed by $\mathrm{tin}$, and answer each query as $\mathrm{F}(r)-\mathrm{F}(l-1)$ with a range count.

<details><summary>Solution</summary>

1. Build the automaton over all $s_i$; build the failure tree (children of $\mathrm{fail}(u)$) and an **iterative** Euler tour: $\mathrm{tin}$, $\mathrm{tout}$ with $\mathrm{subtree}(u)=[\mathrm{tin}_u,\mathrm{tout}_u]$.
2. Split each query into events $(r,+)$ and $(l-1,-)$.
3. For $i=1..n$: walk $s_i$ from the root along trie edges (they survive inside `go`), adding $+1$ at $\mathrm{tin}$ of every prefix node; then answer the events at $i$ with a range sum over $[\mathrm{tin}_{e},\mathrm{tout}_{e}]$, $e=\mathrm{end}_k$.

$O((m+q)\log m + m\sigma)$. The Euler tour is iterative because the failure tree can be a path of depth $2\cdot10^5$.

```cpp
#include <bits/stdc++.h>
using namespace std;

struct AhoCorasick {                       // identical to §3.1, compacted
    static constexpr int A = 26;
    vector<array<int, A>> go; vector<int> fail, bfs;
    AhoCorasick() { addNode(); }
    int addNode() { array<int, A> r; r.fill(-1); go.push_back(r); fail.push_back(0); return (int)go.size() - 1; }
    int insert(const string& s) {
        int v = 0;
        for (char ch : s) { int c = ch - 'a'; if (go[v][c] == -1) { int u = addNode(); go[v][c] = u; } v = go[v][c]; }
        return v;
    }
    void build() {
        for (int c = 0; c < A; c++) { int u = go[0][c]; if (u == -1) go[0][c] = 0; else { fail[u] = 0; bfs.push_back(u); } }
        for (size_t h = 0; h < bfs.size(); h++) for (int v = bfs[h], c = 0; c < A; c++) {
            int u = go[v][c];
            if (u == -1) go[v][c] = go[fail[v]][c]; else { fail[u] = go[fail[v]][c]; bfs.push_back(u); }
        }
    }
};

int main() {
    ios::sync_with_stdio(false); cin.tie(nullptr);
    int n, q;
    cin >> n >> q;
    vector<string> s(n);
    AhoCorasick ac;
    vector<int> endNode(n);
    for (int i = 0; i < n; i++) { cin >> s[i]; endNode[i] = ac.insert(s[i]); }
    ac.build();
    int N = ac.go.size();
    // failure tree in CSR form, then iterative preorder
    vector<int> start(N + 1, 0), child(max(N - 1, 1));
    for (int u = 1; u < N; u++) start[ac.fail[u] + 1]++;
    for (int v = 0; v < N; v++) start[v + 1] += start[v];
    vector<int> pos(start.begin(), start.end() - 1);
    for (int u = 1; u < N; u++) child[pos[ac.fail[u]]++] = u;
    vector<int> tin(N), tout(N), order, st = {0};
    order.reserve(N);
    while (!st.empty()) {
        int v = st.back(); st.pop_back();
        tin[v] = order.size(); order.push_back(v);
        for (int e = start[v]; e < start[v + 1]; e++) st.push_back(child[e]);
    }
    vector<int> sz(N, 1);
    for (int i = N - 1; i > 0; i--) sz[ac.fail[order[i]]] += sz[order[i]];
    for (int v = 0; v < N; v++) tout[v] = tin[v] + sz[v] - 1;
    // offline events
    vector<vector<array<int, 3>>> ev(n + 1);          // (k, sign, query id)
    for (int i = 0; i < q; i++) {
        int l, r, k; cin >> l >> r >> k;
        ev[r].push_back({k - 1, +1, i});
        ev[l - 1].push_back({k - 1, -1, i});
    }
    vector<int> bit(N + 1, 0);
    auto add = [&](int i) { for (i++; i <= N; i += i & -i) bit[i]++; };
    auto pref = [&](int i) { long long r = 0; for (i++; i > 0; i -= i & -i) r += bit[i]; return r; };
    vector<long long> ans(q, 0);
    for (int i = 1; i <= n; i++) {
        int v = 0;
        for (char ch : s[i - 1]) { v = ac.go[v][ch - 'a']; add(tin[v]); }
        for (auto [k, sign, id] : ev[i]) {
            int e = endNode[k];
            ans[id] += sign * (pref(tout[e]) - pref(tin[e] - 1));
        }
    }
    string out;
    for (int i = 0; i < q; i++) { out += to_string(ans[i]); out += '\n'; }
    cout << out;
}
```

```java
import java.util.*;
import java.io.*;

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        PrintWriter out = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        int n = in.nextInt(), q = in.nextInt();
        String[] s = new String[n];
        int total = 1;
        for (int i = 0; i < n; i++) { s[i] = in.next(); total += s[i].length(); }
        AhoCorasick ac = new AhoCorasick(total);
        int[] endNode = new int[n];
        for (int i = 0; i < n; i++) endNode[i] = ac.insert(s[i]);
        ac.build();
        int N = ac.size;
        int[] start = new int[N + 1], child = new int[Math.max(N - 1, 1)];
        for (int u = 1; u < N; u++) start[ac.fail[u] + 1]++;
        for (int v = 0; v < N; v++) start[v + 1] += start[v];
        int[] pos = Arrays.copyOf(start, N);
        for (int u = 1; u < N; u++) child[pos[ac.fail[u]]++] = u;
        int[] tin = new int[N], tout = new int[N], order = new int[N], stack = new int[N], sz = new int[N];
        int sp = 0, cnt = 0;
        stack[sp++] = 0;
        while (sp > 0) {
            int v = stack[--sp];
            tin[v] = cnt; order[cnt++] = v;
            for (int e = start[v]; e < start[v + 1]; e++) stack[sp++] = child[e];
        }
        Arrays.fill(sz, 1);
        for (int i = N - 1; i > 0; i--) sz[ac.fail[order[i]]] += sz[order[i]];
        for (int v = 0; v < N; v++) tout[v] = tin[v] + sz[v] - 1;
        // events as linked lists per position: (k, sign, id)
        int[] evHead = new int[n + 1], evNext = new int[2 * q], evK = new int[2 * q], evSign = new int[2 * q], evId = new int[2 * q];
        Arrays.fill(evHead, -1);
        int ec = 0;
        for (int i = 0; i < q; i++) {
            int l = in.nextInt(), r = in.nextInt(), k = in.nextInt() - 1;
            evK[ec] = k; evSign[ec] = 1; evId[ec] = i; evNext[ec] = evHead[r]; evHead[r] = ec++;
            evK[ec] = k; evSign[ec] = -1; evId[ec] = i; evNext[ec] = evHead[l - 1]; evHead[l - 1] = ec++;
        }
        int[] bit = new int[N + 1];
        long[] ans = new long[q];
        for (int i = 1; i <= n; i++) {
            int v = 0;
            String str = s[i - 1];
            for (int j = 0; j < str.length(); j++) {
                v = ac.go[v * 26 + (str.charAt(j) - 'a')];
                for (int x = tin[v] + 1; x <= N; x += x & -x) bit[x]++;
            }
            for (int e = evHead[i]; e != -1; e = evNext[e]) {
                int node = endNode[evK[e]];
                ans[evId[e]] += evSign[e] * (prefix(bit, tout[node]) - prefix(bit, tin[node] - 1));
            }
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < q; i++) sb.append(ans[i]).append('\n');
        out.print(sb);
        out.flush();
    }

    static long prefix(int[] bit, int i) {
        long r = 0;
        for (i++; i > 0; i -= i & -i) r += bit[i];
        return r;
    }

    static final class AhoCorasick {                 // identical to §3.1, compacted
        static final int A = 26;
        final int[] go, fail, bfs; int size = 1, bfsLen = 0;
        AhoCorasick(int maxNodes) { go = new int[maxNodes * A]; Arrays.fill(go, -1); fail = new int[maxNodes]; bfs = new int[maxNodes]; }
        int insert(String s) {
            int v = 0;
            for (int i = 0; i < s.length(); i++) { int c = s.charAt(i) - 'a'; if (go[v * A + c] == -1) go[v * A + c] = size++; v = go[v * A + c]; }
            return v;
        }
        void build() {
            for (int c = 0; c < A; c++) { int u = go[c]; if (u == -1) go[c] = 0; else { fail[u] = 0; bfs[bfsLen++] = u; } }
            for (int h = 0; h < bfsLen; h++) for (int v = bfs[h], c = 0; c < A; c++) {
                int u = go[v * A + c];
                if (u == -1) go[v * A + c] = go[fail[v] * A + c]; else { fail[u] = go[fail[v] * A + c]; bfs[bfsLen++] = u; }
            }
        }
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
3 4
ab
abab
b
1 2 1
1 3 3
3 3 2
2 2 2
out:
3
4
0
1
-->
<!-- test
in:
1 1
a
1 1 1
out:
1
-->

</details>

## 6. Tricks, pitfalls and things to remember

1. **Forgetting the chain.** Marking only `terminal[state]` misses every pattern that is a proper suffix of the current state (`he` inside `she`). Either follow dictionary links, aggregate along the chain in BFS order, or push counts up the failure tree. This is the most common WA.
2. **Count, don't enumerate.** Enumerating matches is $O(n\sqrt m)$ in the worst case (patterns `a`, `aa`, `aaa`…). If only per-pattern counts are needed, use the reverse-BFS accumulation: $O(n+m)$.
3. **Duplicate patterns** end at the same node. Store a count or a list per node, and map each pattern to its end node (`endNode[i]`) instead of assuming one pattern per node.
4. **BFS order is the topological order.** Top-down aggregates (`bad`, `sh`, `tc`) go forward over `bfs`; bottom-up sums (`cnt`) go backward. Never recurse over the failure tree: a pattern `aaaa…a` of length $10^6$ gives a failure path of depth $10^6$.
5. **Children of the root fail to the root**, not to $\delta(\mathrm{fail}(\mathrm{root}),c)$ — that would be the child itself. The loop over `go[0][c]` before the main BFS handles this.
6. **Memory of the goto table** is $(m+1)\sigma$ ints: $m=10^6$, $\sigma=26$ is 104 MB. Options: reduce the alphabet (DNA, bits), use failure walks with a sorted edge list, or build $\delta$ only for the characters that occur.
7. **Java:** use a flat `int[]` for `go` (one allocation, cache-friendly) and size everything from $\sum|P_i|+1$ read up front. `int[][]` with $10^6$ rows costs about 16 bytes of header per row and is several times slower to allocate.
8. **Rebuild per test case.** With multiple test cases, re-create or clear the automaton; a static array reused without resetting `go` to $-1$ silently merges dictionaries.
9. **Automaton DP state count** is the number of trie nodes ($\le m+1$), not $m\cdot\sigma$. Skip bad states entirely; they are absorbing for "avoid" questions.
10. **Online patterns.** The automaton is static: inserting a pattern after `build()` invalidates `fail`. For insertions interleaved with queries use binary grouping (§7), or pre-insert every pattern and "activate" them with Fenwick updates on the failure tree (CF 163E style).

## 7. Going further (toward 2400–2600+)

- **Failure tree + data structures.** "Occurrences of $s_j$ in $s_i$" questions reduce to subtree counting (Example 4). With activation/deactivation of patterns, add $\pm1$ on the subtree range of the pattern's node and query a point (the number of active patterns on the root path of a state) — [CF 163E · e-Government](https://codeforces.com/problemset/problem/163/E) — 2800. A maximum over active patterns on a chain needs [HLD](../10-Trees/04-heavy-light-decomposition.md) over the failure tree — [CF 1437G · Death DBMS](https://codeforces.com/problemset/problem/1437/G) — 2600.
- **Matrix power over the automaton.** Huge lengths with few states: counting uses ordinary matrix power, optimising uses max-plus matrix power — [CF 696D · Legen...](https://codeforces.com/problemset/problem/696/D) — 2500.
- **Bitmask DP over automaton states.** When the answer depends on a small set of letters or an ordering of keys, combine the automaton with a bitmask: [CF 1327G · Letters and Question Marks](https://codeforces.com/problemset/problem/1327/G) — 2800, [CF 1739F · Keyboard Design](https://codeforces.com/problemset/problem/1739/F) — 2600.
- **Online insertions: binary grouping.** Keep automata over groups of sizes $2^i$ (like a binary counter); an insertion merges equal-sized groups and rebuilds. Each pattern is rebuilt $O(\log k)$ times and a query runs over $O(\log k)$ automata; deletions are a second structure with negative counts — [CF 710F · String Set Queries](https://codeforces.com/problemset/problem/710/F) — 2400.
- **Distinct-lengths trick.** Many problems with $\sum|P|\le10^5$ are secretly "$O(n\sqrt m)$ is fine": at most $\sqrt{2m}$ distinct lengths, so enumerating matches through dictionary links is affordable — [CF 963D · Frequency of String](https://codeforces.com/problemset/problem/963/D) — 2500.
- **Generalised suffix automaton** answers many of the same questions when the *text set* is fixed and patterns arrive online; see [suffix automaton](08-suffix-automaton.md).
- **2D matching (Baker–Bird).** Run Aho–Corasick on the rows of a 2D pattern, replace each text cell by the id of the pattern row ending there, then run KMP down the columns over those ids.

## 8. Practice ladder

**1700–2100**
- [ ] [CSES 2102 · Finding Patterns](https://cses.fi/problemset/task/2102) — ≈1800 (est.) — existence for every pattern
- [ ] [CSES 2103 · Counting Patterns](https://cses.fi/problemset/task/2103) — ≈1900 (est.) — §3.1
- [ ] [CSES 2104 · Pattern Positions](https://cses.fi/problemset/task/2104) — ≈1900 (est.) — first occurrence: a minimum over the failure subtree
- [ ] [AtCoder ABC362 G · Count Substring Query](https://atcoder.jp/contests/abc362/tasks/abc362_g) — ≈1625 (AtCoder est.)
- [ ] [CSES 1112 · Required Substring](https://cses.fi/problemset/task/1112) — ≈2000 (est.) — automaton DP with one pattern
- [ ] [AtCoder ABC305 Ex · Banned Substrings](https://atcoder.jp/contests/abc305/tasks/abc305_g) — ≈1989 (AtCoder est.) — automaton + matrix power

**2100–2400**
- [ ] [CF 808G · Anthem of Berland](https://codeforces.com/problemset/problem/808/G) — 2300
- [ ] [CF 1015F · Bracket Substring](https://codeforces.com/problemset/problem/1015/F) — 2300
- [ ] [CF 1202E · You Are Given Some Strings...](https://codeforces.com/problemset/problem/1202/E) — 2400
- [ ] [CF 710F · String Set Queries](https://codeforces.com/problemset/problem/710/F) — 2400

**2400+**
- [ ] [CF 963D · Frequency of String](https://codeforces.com/problemset/problem/963/D) — 2500
- [ ] [CF 696D · Legen...](https://codeforces.com/problemset/problem/696/D) — 2500
- [ ] [CF 86C · Genetic engineering](https://codeforces.com/problemset/problem/86/C) — 2500
- [ ] [CF 1437G · Death DBMS](https://codeforces.com/problemset/problem/1437/G) — 2600
- [ ] [CF 1739F · Keyboard Design](https://codeforces.com/problemset/problem/1739/F) — 2600
- [ ] [CF 1207G · Indie Album](https://codeforces.com/problemset/problem/1207/G) — 2700
- [ ] [CF 547E · Mike and Friends](https://codeforces.com/problemset/problem/547/E) — 2800
- [ ] [CF 163E · e-Government](https://codeforces.com/problemset/problem/163/E) — 2800
- [ ] [CF 1327G · Letters and Question Marks](https://codeforces.com/problemset/problem/1327/G) — 2800
- [ ] [CF 1400F · x-prime Substrings](https://codeforces.com/problemset/problem/1400/F) — 2800
- [ ] [CF 1801G · A task for substrings](https://codeforces.com/problemset/problem/1801/G) — 3400

## 9. LeetCode / FAANG cross-reference

- [LC 1032 · Stream of Characters](https://leetcode.com/problems/stream-of-characters/) — Hard — the textbook use: feed each character, answer `bad[state]`. The usual interview answer is a trie of reversed words checked against the last maxLen characters; Aho–Corasick makes each query $O(1)$.
- [LC 2781 · Length of the Longest Valid Substring](https://leetcode.com/problems/length-of-the-longest-valid-substring/) — Hard — Example 1 (shortest pattern on the chain).
- [LC 3213 · Construct String with Minimum Cost](https://leetcode.com/problems/construct-string-with-minimum-cost/) — Hard — DP over target positions; the transitions are the words ending at each position, enumerated by dictionary links (at most $\sqrt{2m}$ distinct lengths).
- [LC 616 · Add Bold Tag in String](https://leetcode.com/problems/add-bold-tag-in-string/) — Medium 🔒 and [LC 758 · Bold Words in String](https://leetcode.com/problems/bold-words-in-string/) — Medium 🔒 — mark the interval of the longest word ending at each position, then merge intervals.
- [LC 1408 · String Matching in an Array](https://leetcode.com/problems/string-matching-in-an-array/) — Easy — brute force is intended; Aho–Corasick over all words is the scalable version.

Rare in interviews: the expected interview tools are a trie plus brute force or hashing; mention Aho–Corasick as the follow-up for "what if there are $10^5$ words?".

## 10. Self-check

1. Define $\mathrm{state}(i)$ and prove that every pattern ending at $i$ is a suffix of $\mathrm{str}(\mathrm{state}(i))$.
2. Why must failure links be computed in BFS order, and why do children of the root fail to the root?
3. Write the recurrences for $\delta(v,c)$ and $\mathrm{fail}(\mathrm{go}(v,c))$ and state the build cost.
4. How do you get the number of occurrences of every pattern in $O(n+m)$? In which order do you traverse nodes, and why is it valid?
5. Why is the total number of matches at most $n\sqrt{2m}$? Give an input that attains $\Theta(n\sqrt m)$.
6. What does "$u$ is an ancestor of $v$ in the failure tree" mean for the strings, and how does that turn "$s_j$ inside $s_i$" into a Fenwick query?
7. How do you count length-$L$ strings containing none of the patterns for $L\le10^3$? For $L\le10^{18}$?
8. Explain why KMP is a special case.

<details><summary>Answers</summary>

1. $\mathrm{state}(i)$ is the trie node of the longest suffix of $T[0..i]$ that is in the trie. A pattern ending at $i$ is a suffix of $T[0..i]$ and a trie node, hence no longer than $\mathrm{str}(\mathrm{state}(i))$; both are suffixes of $T[0..i]$, so it is a suffix of it.
2. $\mathrm{fail}(u)$ is computed from $\mathrm{fail}$ and $\delta$ of strictly shallower nodes, and BFS finalises all of them first. For a root child $u=\mathrm{go}(\mathrm{root},c)$ the only proper suffix is empty, so $\mathrm{fail}(u)=\mathrm{root}$; the general formula would return $u$ itself.
3. $\delta(v,c)=\mathrm{go}(v,c)$ if present, else $\delta(\mathrm{fail}(v),c)$ (root: root); $\mathrm{fail}(\mathrm{go}(v,c))=\delta(\mathrm{fail}(v),c)$ for $v\neq$ root. $O(m\sigma)$ time and memory.
4. `cnt[state]++` per text character, then over nodes in reverse BFS order `cnt[fail[u]] += cnt[u]`. Reverse BFS handles every node before its failure parent (which is strictly shallower), so each subtree sum is complete when it is pushed up.
5. Distinct patterns ending at one position have distinct lengths summing to at most $m$, so there are fewer than $\sqrt{2m}$. Patterns $a,aa,\dots,a^{D}$ ($m\approx D^2/2$) against $a^n$ give about $nD$ matches.
6. $\mathrm{str}(u)$ is a suffix of $\mathrm{str}(v)$. Occurrences of $s_j$ in $s_i$ = prefix nodes of $s_i$ inside $\mathrm{subtree}(\mathrm{end}_j)$; the Euler tour makes that subtree a range of $\mathrm{tin}$; add $+1$ at the $\mathrm{tin}$ of every prefix node of $s_i$ and query the range.
7. $dp$ over (length, good state) with transitions $\delta$: $O(Lm\sigma)$. For huge $L$, raise the transition matrix over good states to the power $L$: $O(m^3\log L)$.
8. With a single pattern the trie is a path, the failure link of the node at depth $q$ is the node at depth $\pi[q-1]$, and the matching loop is identical.

</details>
