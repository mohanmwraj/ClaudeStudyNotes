# Tries

> **Band:** 🔵 1500–1900 · **Priority:** ⚡ · **FAANG:** medium · **Prerequisites:** [trees](07-trees-and-bst.md), [backtracking](10-backtracking.md)
> **You can say you know this when:** you can implement insert / search / startsWith without hesitation, extend nodes with counts or stored words, prune a trie during a grid DFS, and use a binary trie for maximum XOR.

A trie (prefix tree) stores a set of strings so that **all strings sharing a prefix share the path for that prefix**. Interviews use it in three ways: as a dictionary with prefix queries (autocomplete), as a **simultaneous matcher** that tests a growing string against many words at once (Word Search II, word break), and, less often, as a binary trie over bits (maximum XOR).

## 1. First principles — why this works

### 1.1 Prefix queries without scanning the dictionary

"Does any word start with `pre`?" against a hash set of $W$ words means scanning all of them: $O(W L)$. Sorting the words and binary searching gives $O(L \log W)$. A trie spends $O(L)$: walk the characters of `pre` from the root, and either fall off (no word has this prefix) or arrive at a node whose subtree is exactly the set of words with that prefix. The walk does not depend on how many words there are. That is the defining property: **the node reached by a prefix represents all strings with that prefix.**

### 1.2 Matching many words at once

In Word Search II the naive approach runs one grid DFS per word: $O(W \cdot RC \cdot 4^L)$. The waste is that words sharing a prefix repeat the same exploration. Building a trie of the words and running **one** DFS per starting cell, advancing a trie pointer with every step, explores each grid path once for all words simultaneously. A path stops the moment the trie has no child for the next letter. Pruning found words out of the trie (deleting leaves) shrinks the search further.

The same idea speeds up "split a string into dictionary words": from position $i$, walking the trie along $s[i..]$ enumerates **every** dictionary word that starts at $i$ in one pass of length $\le L_{\max}$, instead of hashing each substring separately.

### 1.3 Binary trie: greedy on bits

Insert numbers as 31-bit strings from the most significant bit. To maximise $x \oplus y$ over $y$ in the set, walk from the root and at each bit prefer the child with the **opposite** bit of $x$. A higher bit outweighs all lower bits together ($2^k > \sum_{j<k} 2^j$), so the greedy choice is optimal. Each query is $O(31)$.

## 2. Definitions and complexities

| Operation | Time | Space |
|---|---|---|
| insert word of length $L$ | $O(L)$ | up to $L$ new nodes |
| search / startsWith | $O(L)$ | |
| wildcard search (`.` matches any) | $O(26^{d} \cdot L)$ worst case for $d$ wildcards | recursion $O(L)$ |
| total nodes | $\le \sum_w |w| + 1$ | each node: 26 pointers (array) or a map |
| binary trie insert / max-XOR query | $O(B)$, $B$ = bit width | $\le nB$ nodes |
| sorted iteration | DFS in child order yields words in lexicographic order | |

Memory trade-off: an array of 26 child pointers per node is fastest, about 208 bytes per node with 8-byte pointers in C++. For large or unknown alphabets (Unicode, path segments in a file system) use a hash map per node. A pool (`vector<array<int,26>>`) with integer indices halves the memory and is what CP code uses.

Node fields you can add: `isEnd` / `word` (the stored word, to avoid rebuilding it), `prefixCount` (how many words pass through), `endCount` (duplicates), and the best or top-$k$ completions for autocomplete.

## 3. Reusable templates (C++ and Java)

A pooled trie with prefix counts. It supports insert, erase, exact count and prefix count. Erase assumes the word is present.

```cpp
struct Trie {
    vector<array<int, 26>> next;
    vector<int> pass, ends;                        // words passing through / ending at each node
    Trie() { newNode(); }
    int newNode() {
        next.push_back({});                        // zero-initialised: 0 means "no child" (root is 0)
        pass.push_back(0);
        ends.push_back(0);
        return (int)next.size() - 1;
    }
    void insert(const string& w) {
        int v = 0;
        pass[v]++;
        for (char ch : w) {
            int c = ch - 'a';
            if (!next[v][c]) { int u = newNode(); next[v][c] = u; }   // newNode may reallocate `next`
            v = next[v][c];
            pass[v]++;
        }
        ends[v]++;
    }
    void erase(const string& w) {                  // precondition: w was inserted
        int v = 0;
        pass[v]--;
        for (char ch : w) { v = next[v][ch - 'a']; pass[v]--; }
        ends[v]--;
    }
    int countWord(const string& w) const { int v = walk(w); return v < 0 ? 0 : ends[v]; }
    int countPrefix(const string& p) const { int v = walk(p); return v < 0 ? 0 : pass[v]; }
private:
    int walk(const string& s) const {
        int v = 0;
        for (char ch : s) {
            v = next[v][ch - 'a'];
            if (!v || !pass[v]) return -1;        // fell off, or only erased words remain here
        }
        return v;
    }
};
```

```java
static class Trie {
    private int[][] next = new int[16][];
    private int[] pass = new int[16], ends = new int[16];
    private int size = 0;
    Trie() { newNode(); }
    private int newNode() {
        if (size == next.length) {
            next = Arrays.copyOf(next, size * 2);
            pass = Arrays.copyOf(pass, size * 2);
            ends = Arrays.copyOf(ends, size * 2);
        }
        next[size] = new int[26];
        return size++;
    }
    void insert(String w) {
        int v = 0;
        pass[v]++;
        for (int i = 0; i < w.length(); i++) {
            int c = w.charAt(i) - 'a';
            if (next[v][c] == 0) { int u = newNode(); next[v][c] = u; }
            v = next[v][c];
            pass[v]++;
        }
        ends[v]++;
    }
    void erase(String w) {
        int v = 0;
        pass[v]--;
        for (int i = 0; i < w.length(); i++) { v = next[v][w.charAt(i) - 'a']; pass[v]--; }
        ends[v]--;
    }
    int countWord(String w) { int v = walk(w); return v < 0 ? 0 : ends[v]; }
    int countPrefix(String p) { int v = walk(p); return v < 0 ? 0 : pass[v]; }
    private int walk(String s) {
        int v = 0;
        for (int i = 0; i < s.length(); i++) {
            v = next[v][s.charAt(i) - 'a'];
            if (v == 0 || pass[v] == 0) return -1;
        }
        return v;
    }
}
```

## 4. Recognising the pattern

| Signal | Think |
|---|---|
| "starts with", "prefix", "autocomplete", "search suggestions" | trie (or sorted list + binary search when the dictionary is static) |
| many words searched in one grid / text at once | trie of the words + one DFS / scan with a trie pointer |
| wildcard `.` in queries | trie + DFS branching on all children at a wildcard |
| "replace words by their shortest root" | walk the trie, stop at the first `isEnd` |
| "split $s$ into dictionary words", dictionary of many short words | DP over positions, trie to enumerate words starting at $i$ ([file 13](13-dynamic-programming-1d.md)) |
| "maximum XOR of a pair / with a query" | binary trie, greedy from the top bit |
| hierarchical keys (paths `/a/b/c`) | trie keyed by path segments (hash map children) |
| "longest common prefix of all words" | the trie path until the first branch or word end. Simpler: compare characters column by column |
| suffix questions ("ends with") | trie of reversed words |

When **not** to use a trie: exact-membership queries only (a hash set is simpler), or a single pattern in a single text (KMP / Z-function, [CP strings](../11-Strings/02-prefix-function-kmp.md)).

## 5. Worked examples

### Example 1 — Implement Trie (Prefix Tree) · Medium

- **Source:** [LC 208 · Implement Trie (Prefix Tree)](https://leetcode.com/problems/implement-trie-prefix-tree/) — Medium · `G75` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1200 CF, est.)
- **Problem:** implement `insert(word)`, `search(word)` (exact) and `startsWith(prefix)`, with lowercase words of length ≤ 2000 and up to $3 \cdot 10^4$ calls.
- **Thinking from first principles:** a hash set answers `search` but not `startsWith` without scanning. The trie answers both with the same walk, and the only difference is the final check: `search` needs the node to be marked as a word end, while `startsWith` only needs the walk to succeed. Each node has 26 child slots and an end flag.

<details><summary>Solution</summary>

Pointer-based nodes, which is what interviewers expect to read. Every operation is $O(L)$, and the memory is $O(\text{total characters} \cdot 26)$. The driver reads `q` operations such as `insert apple` and prints `true`/`false` for each query. In C++ the nodes are never freed. Mention a destructor or a node pool if asked about memory.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Trie {
    struct Node {
        Node* child[26] = {};
        bool isEnd = false;
    };
    Node* root = new Node();
    Node* walk(const string& s) const {                // node reached by s, or nullptr
        Node* v = root;
        for (char ch : s) {
            v = v->child[ch - 'a'];
            if (!v) return nullptr;
        }
        return v;
    }
public:
    void insert(string word) {
        Node* v = root;
        for (char ch : word) {
            int c = ch - 'a';
            if (!v->child[c]) v->child[c] = new Node();
            v = v->child[c];
        }
        v->isEnd = true;
    }
    bool search(string word) { Node* v = walk(word); return v && v->isEnd; }
    bool startsWith(string prefix) { return walk(prefix) != nullptr; }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> q;
    Trie trie;
    while (q--) {
        string op, w;
        cin >> op >> w;
        if (op == "insert") trie.insert(w);
        else if (op == "search") cout << (trie.search(w) ? "true" : "false") << '\n';
        else cout << (trie.startsWith(w) ? "true" : "false") << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

class Trie {
    private static class Node {
        Node[] child = new Node[26];
        boolean isEnd;
    }
    private final Node root = new Node();
    private Node walk(String s) {
        Node v = root;
        for (int i = 0; i < s.length() && v != null; i++) v = v.child[s.charAt(i) - 'a'];
        return v;
    }
    public void insert(String word) {
        Node v = root;
        for (int i = 0; i < word.length(); i++) {
            int c = word.charAt(i) - 'a';
            if (v.child[c] == null) v.child[c] = new Node();
            v = v.child[c];
        }
        v.isEnd = true;
    }
    public boolean search(String word) { Node v = walk(word); return v != null && v.isEnd; }
    public boolean startsWith(String prefix) { return walk(prefix) != null; }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int q = in.nextInt();
        Trie trie = new Trie();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = in.next(), w = in.next();
            if (op.equals("insert")) trie.insert(w);
            else if (op.equals("search")) sb.append(trie.search(w)).append('\n');
            else sb.append(trie.startsWith(w)).append('\n');
        }
        System.out.print(sb);
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
6
insert apple
search apple
search app
startsWith app
insert app
search app
out:
true
false
true
true
-->
<!-- test
in:
4
search a
startsWith a
insert a
startsWith a
out:
false
false
true
-->

### Example 2 — Design Add and Search Words Data Structure · Medium

- **Source:** [LC 211 · Design Add and Search Words Data Structure](https://leetcode.com/problems/design-add-and-search-words-data-structure/) — Medium · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Medium (≈ 1400 CF, est.)
- **Problem:** `addWord(word)` and `search(pattern)`, where `.` matches any single letter. Words have length ≤ 25, queries contain at most 2 dots, and there are up to $10^4$ calls.
- **Thinking from first principles:** a hash set would need to try all $26^d$ expansions of the dots, or scan all words of the same length. With a trie, a literal character follows one edge, and a dot branches into every existing child. The DFS explores only prefixes that actually exist in the dictionary, which is far fewer than $26^d$ in practice. A useful extra prune is to bucket words by length (a pattern can only match words of the same length).

<details><summary>Solution</summary>

`match(node, i)` asks whether the pattern's suffix starting at `i` can be read from `node`. Worst case $O(26^d \cdot L)$, typically close to $O(L)$. The driver reads operations `add w` / `search p` and prints the search results.

```cpp
#include <bits/stdc++.h>
using namespace std;

class WordDictionary {
    struct Node {
        Node* child[26] = {};
        bool isEnd = false;
    };
    Node* root = new Node();
    bool match(Node* v, const string& p, int i) {
        if (i == (int)p.size()) return v->isEnd;
        if (p[i] != '.') {
            Node* nx = v->child[p[i] - 'a'];
            return nx && match(nx, p, i + 1);
        }
        for (Node* nx : v->child)                       // '.' tries every existing child
            if (nx && match(nx, p, i + 1)) return true;
        return false;
    }
public:
    void addWord(string word) {
        Node* v = root;
        for (char ch : word) {
            int c = ch - 'a';
            if (!v->child[c]) v->child[c] = new Node();
            v = v->child[c];
        }
        v->isEnd = true;
    }
    bool search(string word) { return match(root, word, 0); }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int q;
    cin >> q;
    WordDictionary d;
    while (q--) {
        string op, w;
        cin >> op >> w;
        if (op == "add") d.addWord(w);
        else cout << (d.search(w) ? "true" : "false") << '\n';
    }
}
```

```java
import java.util.*;
import java.io.*;

class WordDictionary {
    private static class Node {
        Node[] child = new Node[26];
        boolean isEnd;
    }
    private final Node root = new Node();
    public void addWord(String word) {
        Node v = root;
        for (int i = 0; i < word.length(); i++) {
            int c = word.charAt(i) - 'a';
            if (v.child[c] == null) v.child[c] = new Node();
            v = v.child[c];
        }
        v.isEnd = true;
    }
    public boolean search(String word) { return match(root, word, 0); }
    private boolean match(Node v, String p, int i) {
        if (i == p.length()) return v.isEnd;
        char ch = p.charAt(i);
        if (ch != '.') {
            Node nx = v.child[ch - 'a'];
            return nx != null && match(nx, p, i + 1);
        }
        for (Node nx : v.child) if (nx != null && match(nx, p, i + 1)) return true;
        return false;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int q = in.nextInt();
        WordDictionary d = new WordDictionary();
        StringBuilder sb = new StringBuilder();
        while (q-- > 0) {
            String op = in.next(), w = in.next();
            if (op.equals("add")) d.addWord(w);
            else sb.append(d.search(w)).append('\n');
        }
        System.out.print(sb);
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
7
add bad
add dad
add mad
search pad
search bad
search .ad
search b..
out:
false
true
true
true
-->
<!-- test
in:
4
add a
search .
search ..
search a.
out:
true
false
false
-->

### Example 3 — Word Search II · Hard

- **Source:** [LC 212 · Word Search II](https://leetcode.com/problems/word-search-ii/) — Hard · `G169` `B75` `NC150` `TI150`
- **Difficulty:** LeetCode Hard (≈ 1900 CF, est.)
- **Problem:** an $R \times C$ letter grid ($R, C \le 12$) and up to $3 \cdot 10^4$ distinct words (length ≤ 10). Return every word that can be traced by a path of horizontally or vertically adjacent cells, using each cell at most once per word.
- **Thinking from first principles:** running Word Search I ([file 10](10-backtracking.md)) once per word repeats the same prefixes $W$ times. Build a trie of the words. From each cell, DFS while carrying the trie node of the path spelled so far. If the next letter has no child, the whole branch is dead for *every* word. Store the complete word at its end node so it can be reported without rebuilding the string. Clear it after reporting so it is found only once, and remove trie leaves that are no longer needed so later searches skip exhausted branches.

<details><summary>Solution</summary>

DFS state: cell and trie node. Mark the cell visited by overwriting it with `#` and restore it on return (backtracking). Worst case $O(RC \cdot 4 \cdot 3^{L-1})$ trie steps, since after the first move a path has at most 3 unvisited neighbours. Pruning makes it much faster in practice. The driver reads `R C`, the rows, then `k` words, and prints the found words sorted, one per line, after their count.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
    struct Node {
        Node* child[26] = {};
        string word;                                         // non-empty at a word end
        int children = 0;                                    // live children, for pruning
    };
    vector<string> found;
    int R = 0, C = 0;
    void dfs(vector<vector<char>>& b, int r, int c, Node* parent) {
        char ch = b[r][c];
        Node* v = parent->child[ch - 'a'];
        if (!v) return;
        if (!v->word.empty()) { found.push_back(v->word); v->word.clear(); }   // report once
        b[r][c] = '#';                                       // visited on this path
        static const int dr[4] = {1, -1, 0, 0}, dc[4] = {0, 0, 1, -1};
        for (int d = 0; d < 4; ++d) {
            int nr = r + dr[d], nc = c + dc[d];
            if (nr >= 0 && nr < R && nc >= 0 && nc < C && b[nr][nc] != '#') dfs(b, nr, nc, v);
        }
        b[r][c] = ch;                                        // backtrack
        if (v->children == 0 && v->word.empty()) {           // exhausted leaf: prune it
            parent->child[ch - 'a'] = nullptr;
            parent->children--;
        }
    }
public:
    vector<string> findWords(vector<vector<char>>& board, vector<string>& words) {
        Node* root = new Node();
        for (const string& w : words) {
            Node* v = root;
            for (char ch : w) {
                int c = ch - 'a';
                if (!v->child[c]) { v->child[c] = new Node(); v->children++; }
                v = v->child[c];
            }
            v->word = w;
        }
        R = board.size();
        C = board[0].size();
        found.clear();
        for (int r = 0; r < R; ++r)
            for (int c = 0; c < C; ++c) dfs(board, r, c, root);
        return found;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int R, C, k;
    cin >> R >> C;
    vector<vector<char>> board(R, vector<char>(C));
    for (int r = 0; r < R; ++r) {
        string row;
        cin >> row;
        for (int c = 0; c < C; ++c) board[r][c] = row[c];
    }
    cin >> k;
    vector<string> words(k);
    for (auto& w : words) cin >> w;
    auto res = Solution().findWords(board, words);
    sort(res.begin(), res.end());
    cout << res.size() << '\n';
    for (auto& w : res) cout << w << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    private static class Node {
        Node[] child = new Node[26];
        String word;
        int children;
    }
    private final List<String> found = new ArrayList<>();
    private int R, C;
    private static final int[] DR = {1, -1, 0, 0}, DC = {0, 0, 1, -1};

    public List<String> findWords(char[][] board, String[] words) {
        Node root = new Node();
        for (String w : words) {
            Node v = root;
            for (int i = 0; i < w.length(); i++) {
                int c = w.charAt(i) - 'a';
                if (v.child[c] == null) { v.child[c] = new Node(); v.children++; }
                v = v.child[c];
            }
            v.word = w;
        }
        R = board.length;
        C = board[0].length;
        found.clear();
        for (int r = 0; r < R; r++)
            for (int c = 0; c < C; c++) dfs(board, r, c, root);
        return found;
    }

    private void dfs(char[][] b, int r, int c, Node parent) {
        char ch = b[r][c];
        Node v = parent.child[ch - 'a'];
        if (v == null) return;
        if (v.word != null) { found.add(v.word); v.word = null; }
        b[r][c] = '#';
        for (int d = 0; d < 4; d++) {
            int nr = r + DR[d], nc = c + DC[d];
            if (nr >= 0 && nr < R && nc >= 0 && nc < C && b[nr][nc] != '#') dfs(b, nr, nc, v);
        }
        b[r][c] = ch;
        if (v.children == 0 && v.word == null) { parent.child[ch - 'a'] = null; parent.children--; }
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int R = in.nextInt(), C = in.nextInt();
        char[][] board = new char[R][];
        for (int r = 0; r < R; r++) board[r] = in.next().toCharArray();
        int k = in.nextInt();
        String[] words = new String[k];
        for (int i = 0; i < k; i++) words[i] = in.next();
        List<String> res = new ArrayList<>(new Solution().findWords(board, words));
        Collections.sort(res);
        StringBuilder sb = new StringBuilder().append(res.size()).append('\n');
        for (String w : res) sb.append(w).append('\n');
        System.out.print(sb);
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
4 4
oaan
etae
ihkr
iflv
4
oath pea eat rain
out:
2
eat
oath
-->
<!-- test
in:
2 2
ab
cd
1
abcb
out:
0
-->
<!-- test
in:
1 1
a
2
a b
out:
1
a
-->
<!-- test
in:
2 3
abc
fed
4
abcdef ab fe cbad
out:
3
ab
abcdef
fe
-->

### Example 4 — Extra Characters in a String · Medium

- **Source:** [LC 2707 · Extra Characters in a String](https://leetcode.com/problems/extra-characters-in-a-string/) — Medium · `NC250`
- **Difficulty:** LeetCode Medium (≈ 1600 CF, est.)
- **Problem:** split $s$ ($|s| \le 50$) into non-overlapping dictionary words (dictionary of ≤ 50 words of length ≤ 50) plus leftover characters. Minimise the number of leftover characters.
- **Thinking from first principles:** define $dp_i$ = minimum leftovers for the suffix $s[i..]$. At position $i$ either skip $s_i$ (cost 1, then $dp_{i+1}$), or use a dictionary word $s[i..j]$ (then $dp_{j+1}$). Checking every $j$ with a hash set costs $O(n)$ per substring for hashing, so $O(n^3)$ overall. Walking a trie from $i$ along $s$ discovers every word starting at $i$ during one $O(n)$ walk, which gives $O(n^2)$ in total and stops early when no word continues.

<details><summary>Solution</summary>

Fill $dp$ from right to left, with $dp_n = 0$. Time $O(n^2 + \sum |w|)$, space $O(n + \text{trie})$. A pooled trie keeps the code short. The driver reads $s$, $k$ and the $k$ words.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int minExtraChar(string s, vector<string>& dictionary) {
        vector<array<int, 26>> next(1);                     // node 0 = root; 0 also means "none"
        vector<bool> isEnd(1, false);
        for (const string& w : dictionary) {
            int v = 0;
            for (char ch : w) {
                int c = ch - 'a';
                if (!next[v][c]) {
                    next[v][c] = next.size();
                    next.push_back({});
                    isEnd.push_back(false);
                }
                v = next[v][c];
            }
            isEnd[v] = true;
        }
        int n = s.size();
        vector<int> dp(n + 1, 0);                           // dp[i]: best for suffix s[i..]
        for (int i = n - 1; i >= 0; --i) {
            dp[i] = 1 + dp[i + 1];                          // leave s[i] unused
            int v = 0;
            for (int j = i; j < n; ++j) {                   // every word starting at i
                v = next[v][s[j] - 'a'];
                if (!v) break;
                if (isEnd[v]) dp[i] = min(dp[i], dp[j + 1]);
            }
        }
        return dp[0];
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    string s;
    int k;
    cin >> s >> k;
    vector<string> dict(k);
    for (auto& w : dict) cin >> w;
    cout << Solution().minExtraChar(s, dict) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int minExtraChar(String s, String[] dictionary) {
        List<int[]> next = new ArrayList<>();
        List<Boolean> isEnd = new ArrayList<>();
        next.add(new int[26]);
        isEnd.add(false);
        for (String w : dictionary) {
            int v = 0;
            for (int i = 0; i < w.length(); i++) {
                int c = w.charAt(i) - 'a';
                if (next.get(v)[c] == 0) {
                    next.get(v)[c] = next.size();
                    next.add(new int[26]);
                    isEnd.add(false);
                }
                v = next.get(v)[c];
            }
            isEnd.set(v, true);
        }
        int n = s.length();
        int[] dp = new int[n + 1];
        for (int i = n - 1; i >= 0; i--) {
            dp[i] = 1 + dp[i + 1];
            int v = 0;
            for (int j = i; j < n; j++) {
                v = next.get(v)[s.charAt(j) - 'a'];
                if (v == 0) break;
                if (isEnd.get(v)) dp[i] = Math.min(dp[i], dp[j + 1]);
            }
        }
        return dp[0];
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        String s = in.next();
        int k = in.nextInt();
        String[] dict = new String[k];
        for (int i = 0; i < k; i++) dict[i] = in.next();
        System.out.println(new Solution().minExtraChar(s, dict));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
leetscode 3
leet code leetcode
out:
1
-->
<!-- test
in:
sayhelloworld 2
hello world
out:
3
-->
<!-- test
in:
abc 1
d
out:
3
-->
<!-- test
in:
aaa 2
a aa
out:
0
-->

### Example 5 — Maximum XOR of Two Numbers in an Array · Medium

- **Source:** [LC 421 · Maximum XOR of Two Numbers in an Array](https://leetcode.com/problems/maximum-xor-of-two-numbers-in-an-array/) — Medium (not in the fetched lists; it is the standard binary-trie question)
- **Difficulty:** LeetCode Medium (≈ 1800 CF, est.)
- **Problem:** $n \le 2 \cdot 10^5$ non-negative integers below $2^{31}$. Return $\max_{i, j} a_i \oplus a_j$.
- **Thinking from first principles:** all pairs is $O(n^2) = 4 \cdot 10^{10}$, which is too slow. XOR is maximised bit by bit from the top: getting bit 30 set beats any combination of lower bits. So for a fixed $a_i$, we want the stored number that **differs** from $a_i$ in the highest possible bit, then, among those, in the next bit, and so on. That is a walk down a trie of bit strings, choosing the opposite child whenever it exists. Insert each number before querying it, or insert all numbers first. Both work, since $a_i \oplus a_i = 0$ never beats a real pair unless all values are equal.

<details><summary>Solution</summary>

Binary trie with two children per node, 31 levels. Each insert and query is $O(31)$, so the total is $O(31 n)$ time and up to $31n + 1$ nodes. The driver reads $n$ and the numbers.

```cpp
#include <bits/stdc++.h>
using namespace std;

class Solution {
public:
    int findMaximumXOR(vector<int>& nums) {
        vector<array<int, 2>> next(1, {0, 0});             // node 0 = root
        next.reserve(nums.size() * 31 + 1);
        int best = 0;
        for (int x : nums) {
            int v = 0;                                      // insert x, bits 30..0
            for (int b = 30; b >= 0; --b) {
                int bit = (x >> b) & 1;
                if (!next[v][bit]) { next[v][bit] = next.size(); next.push_back({0, 0}); }
                v = next[v][bit];
            }
            int u = 0, cur = 0;                             // best partner for x among inserted values
            for (int b = 30; b >= 0; --b) {
                int want = ((x >> b) & 1) ^ 1;              // the opposite bit sets bit b of the XOR
                if (next[u][want]) { cur |= 1 << b; u = next[u][want]; }
                else u = next[u][want ^ 1];
            }
            best = max(best, cur);
        }
        return best;
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    vector<int> a(n);
    for (int& x : a) cin >> x;
    cout << Solution().findMaximumXOR(a) << '\n';
}
```

```java
import java.util.*;
import java.io.*;

class Solution {
    public int findMaximumXOR(int[] nums) {
        int[][] next = new int[nums.length * 31 + 1][2];
        int size = 1, best = 0;
        for (int x : nums) {
            int v = 0;
            for (int b = 30; b >= 0; b--) {
                int bit = (x >> b) & 1;
                if (next[v][bit] == 0) next[v][bit] = size++;
                v = next[v][bit];
            }
            int u = 0, cur = 0;
            for (int b = 30; b >= 0; b--) {
                int want = ((x >> b) & 1) ^ 1;
                if (next[u][want] != 0) { cur |= 1 << b; u = next[u][want]; }
                else u = next[u][want ^ 1];
            }
            best = Math.max(best, cur);
        }
        return best;
    }
}

public class Main {
    public static void main(String[] args) throws IOException {
        FastReader in = new FastReader(System.in);
        int n = in.nextInt();
        int[] a = new int[n];
        for (int i = 0; i < n; i++) a[i] = in.nextInt();
        System.out.println(new Solution().findMaximumXOR(a));
    }
}

class FastReader {
    private final DataInputStream in;
    private final byte[] buf = new byte[1 << 16];
    private int len = 0, ptr = 0;
    FastReader(InputStream is) { in = new DataInputStream(is); }
    private int read() throws IOException {
        if (ptr == len) { len = in.read(buf, 0, buf.length); ptr = 0; if (len <= 0) { len = 0; return -1; } }
        return buf[ptr++];
    }
    String next() throws IOException {
        int c = read();
        while (c != -1 && c <= ' ') c = read();
        if (c == -1) return null;
        StringBuilder sb = new StringBuilder();
        while (c > ' ') { sb.append((char) c); c = read(); }
        return sb.toString();
    }
    int nextInt() throws IOException { return Integer.parseInt(next()); }
}
```

</details>

<!-- test
in:
6
3 10 5 25 2 8
out:
28
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
8
14 70 53 83 49 91 36 80
out:
127
-->
<!-- test
in:
2
2147483647 0
out:
2147483647
-->

## 6. Pitfalls and things to remember

1. **`search` vs `startsWith`:** only `search` checks `isEnd`. Forgetting it makes `search("app")` true after inserting `"apple"`.
2. **Pool-based tries in C++:** `newNode()` can reallocate the vector, so `next[v][c] = newNode()` may write into freed memory (the left side is evaluated before or after the call depending on the compiler). Store the new index in a local variable first, as the template does.
3. **Character mapping:** `ch - 'a'` assumes lowercase. Validate it or use a map for mixed alphabets. Uppercase and digits need 62 slots or a map.
4. **Word Search II duplicates:** the same word can be found along several paths. Clear `word` after reporting (or use a set).
5. **Restore the grid cell** after DFS, even on early return paths. A missed restore corrupts later searches.
6. **Pruning bookkeeping:** decrement the parent's child count only when you actually remove a child. Removing a node that still ends a word loses that word.
7. **Memory:** $3 \cdot 10^4$ words × 10 letters × 26 pointers × 8 bytes ≈ 62 MB worst case with pointer nodes. Mention it and the pooled or map-based alternative when the interviewer asks about scale.
8. **Binary trie bit width:** use 31 bits for non-negative `int`, 32 for unsigned values, and handle negatives by flipping the sign bit (offset by $2^{31}$).
9. **Java:** `Node[] child = new Node[26]` per node is fine for interviews. In tight loops, `charAt` is faster than `toCharArray()` copies for long strings only when you avoid the copy entirely.

## 7. Follow-up questions interviewers ask

| Follow-up | Strong answer |
|---|---|
| "Support delete" | store `pass` counts; decrement along the path; a node with `pass == 0` is logically gone (or physically unlink it) |
| "Autocomplete: top 3 suggestions per prefix" | store the 3 best (or lexicographically smallest) completions at each node during insert, so a query is $O(L)$ ([LC 1268 · Search Suggestions System](https://leetcode.com/problems/search-suggestions-system/) — Medium, [LC 642 · Design Search Autocomplete System](https://leetcode.com/problems/design-search-autocomplete-system/) — Hard 🔒) |
| "The dictionary is huge and static" | sorted array + binary search for prefix ranges, or a compressed trie (radix tree / DAWG) to save memory |
| "Wildcard `*` (any sequence)" | trie DFS where `*` may consume zero or more characters, memoised on (node, index) |
| Word Search II → "complexity?" | $O(RC \cdot 4 \cdot 3^{L-1})$ trie steps, plus $O(\sum |w|)$ to build; pruning makes it output-sensitive in practice |
| "Stream of characters, report when a suffix is a word" | trie of reversed words and walk back over the last $L_{\max}$ characters, or Aho–Corasick for $O(1)$ amortised per character ([CP: Aho–Corasick](../11-Strings/06-aho-corasick.md)) |
| Max XOR → "with a constraint $a_j \le m_i$ per query" | sort queries by $m_i$, insert numbers offline in increasing order ([LC 1707 · Maximum XOR With an Element From Array](https://leetcode.com/problems/maximum-xor-with-an-element-from-array/) — Hard) |
| "Count pairs with XOR < k" | binary trie with subtree counts, walk while comparing with the bits of $k$ |

## 8. Problem list

Badges come only from the lists fetched on 23 Oct 2026 (legend in [18-leetcode-master-list.md](18-leetcode-master-list.md)): `G75` · `G169` · `B75` · `NC150` · `NC250` · `TI150`; 🔒 = Premium. Only four list problems are trie-first; Design In-Memory File System (a trie of path segments) is under [design problems](17-design-problems.md).

**Medium** (3)

- [ ] [LC 208 · Implement Trie (Prefix Tree)](https://leetcode.com/problems/implement-trie-prefix-tree/) — Medium · `G75` `B75` `NC150` `TI150`
- [ ] [LC 211 · Design Add and Search Words Data Structure](https://leetcode.com/problems/design-add-and-search-words-data-structure/) — Medium · `G169` `B75` `NC150` `TI150`
- [ ] [LC 2707 · Extra Characters in a String](https://leetcode.com/problems/extra-characters-in-a-string/) — Medium · `NC250`

**Hard** (1)

- [ ] [LC 212 · Word Search II](https://leetcode.com/problems/word-search-ii/) — Hard · `G169` `B75` `NC150` `TI150`

**Beyond the lists** (tries come up more often in interviews than the lists suggest):

- [ ] [LC 648 · Replace Words](https://leetcode.com/problems/replace-words/) — Medium — first `isEnd` on the walk
- [ ] [LC 677 · Map Sum Pairs](https://leetcode.com/problems/map-sum-pairs/) — Medium — prefix sums stored in nodes
- [ ] [LC 720 · Longest Word in Dictionary](https://leetcode.com/problems/longest-word-in-dictionary/) — Medium — DFS through `isEnd` nodes only
- [ ] [LC 1268 · Search Suggestions System](https://leetcode.com/problems/search-suggestions-system/) — Medium — top-3 per node, or sort + binary search
- [ ] [LC 421 · Maximum XOR of Two Numbers in an Array](https://leetcode.com/problems/maximum-xor-of-two-numbers-in-an-array/) — Medium — binary trie
- [ ] [LC 820 · Short Encoding of Words](https://leetcode.com/problems/short-encoding-of-words/) — Medium — trie of reversed words, count leaves
- [ ] [LC 1233 · Remove Sub-Folders from the Filesystem](https://leetcode.com/problems/remove-sub-folders-from-the-filesystem/) — Medium — trie of path segments
- [ ] [LC 2416 · Sum of Prefix Scores of Strings](https://leetcode.com/problems/sum-of-prefix-scores-of-strings/) — Hard — `pass` counts
- [ ] [LC 1032 · Stream of Characters](https://leetcode.com/problems/stream-of-characters/) — Hard — reversed-word trie
- [ ] [LC 745 · Prefix and Suffix Search](https://leetcode.com/problems/prefix-and-suffix-search/) — Hard — insert `suffix#word` for all suffixes
- [ ] [LC 1707 · Maximum XOR With an Element From Array](https://leetcode.com/problems/maximum-xor-with-an-element-from-array/) — Hard — offline + binary trie

## 9. CP counterpart

- [Trie and binary trie (CP)](../11-Strings/05-trie-and-binary-trie.md): pooled tries, persistent binary tries, XOR-basis comparisons.
- [Aho–Corasick](../11-Strings/06-aho-corasick.md): a trie plus failure links matches all dictionary words in a text in linear time. It is the industrial-strength version of Word Search II's "match many words at once".
- [Persistent data structures](../08-Data-Structures/08-persistent-data-structures.md): persistent binary tries answer "max XOR with an element in a range".

Interview difference: pointer-based nodes with named fields (`isEnd`, `word`) read better than `nxt[v][c]` pools, unless the interviewer asks about memory.

## 10. Self-check

1. What does the node reached by walking a prefix represent?
2. Why is `search` not the same as `startsWith`, and what single field distinguishes them?
3. In Word Search II, what are the two pruning steps, and why is each safe?
4. Why does the binary-trie greedy (prefer the opposite bit from the top) give the maximum XOR?
5. What is the memory cost of a 26-pointer trie on $N$ total characters, and two ways to reduce it?
6. How do you support `delete(word)` without breaking other words that share its prefix?
7. Give a problem where a hash set is better than a trie, and one where the trie wins.

<details><summary>Answers</summary>

1. The set of all inserted strings that start with that prefix (its subtree).
2. `startsWith` succeeds whenever the walk does not fall off. `search` additionally needs the node to end a word: `isEnd` (or `endCount > 0`).
3. (a) Stop the DFS when the trie has no child for the next letter, since no remaining word has this prefix. (b) After a node's word is reported and its subtree is empty, unlink it, since no future search can find anything through it.
4. Bit $b$ of the XOR is worth $2^b > \sum_{j<b} 2^j$. So among all candidates, the best one must set the highest achievable bit, and among those the next one, and so on. The walk keeps exactly the candidates consistent with the choices so far.
5. About $26 \times 8$ bytes per node, i.e. $O(26N)$ pointers. Reduce it with an integer-indexed pool, map-based children, or a compressed (radix) trie.
6. Keep `pass` counts per node and `endCount` at word ends, and decrement them along the path. A node is gone only when `pass == 0`, so shared prefixes survive.
7. A hash set is better for exact membership only (Two Sum, contains duplicate). The trie wins for prefix queries, wildcard search, simultaneous matching of many words (Word Search II), and max-XOR.

</details>
