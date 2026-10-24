# Cheat sheet — 11 Strings

Revision only. Full derivations and tested programs: [README](../11-Strings/README.md) · [01 hashing](../11-Strings/01-string-hashing.md) · [02 KMP](../11-Strings/02-prefix-function-kmp.md) · [03 Z](../11-Strings/03-z-function.md) · [04 Manacher](../11-Strings/04-manacher-and-palindromes.md) · [05 trie](../11-Strings/05-trie-and-binary-trie.md) · [06 Aho–Corasick](../11-Strings/06-aho-corasick.md) · [07 suffix array](../11-Strings/07-suffix-array-and-lcp.md) · [08 suffix automaton](../11-Strings/08-suffix-automaton.md) · [09 eertree](../11-Strings/09-palindromic-tree-eertree.md) · [problems](../11-Strings/problems.md).

## 1. Formulas and facts

| Topic | Formula / fact |
|---|---|
| polynomial hash | $H(s[l,r)) = \big(h_r - h_l B^{\,r-l}\big) \bmod M$, $h_{i+1} = h_i B + s_i$ |
| collision (one pair) | $\Pr \le (L-1)/M$ for random $B$ (a nonzero polynomial of degree $< L$ has $< L$ roots) |
| birthday bound | $q$ hashed strings: $\Pr[\text{any collision}] \lesssim q^2 L / (2M)$ → use $M = 2^{61}-1$ (or two ~$10^9$ mods) |
| $2^{61}-1$ reduction | $x = hi \cdot 2^{61} + lo \Rightarrow x \equiv hi + lo$ |
| palindrome by hash | $s[l,r)$ palindrome ⇔ forward hash = hash of the mirrored range in $\mathrm{rev}(s)$ |
| prefix function | $\pi[i]$ = longest proper border of $s[0..i]$; $\pi[i] \le \pi[i-1] + 1$; total work $\le 2n$ |
| borders | chain $\pi[n-1], \pi[\pi[n-1]-1], \dots$ |
| smallest period | $p = n - \pi[n-1]$; $s$ is a power iff $\pi[n-1] > 0$ and $p \mid n$ |
| matching | $\pi$ of $p\#t$ equals $\lvert p\rvert$ exactly at occurrence ends |
| prefix occurrences | `cnt[pi[i]]++`; for $j = n-1..1$: `cnt[pi[j-1]] += cnt[j]`; then `cnt[j]++` |
| KMP automaton | $\delta(k,c) = k+1$ if $p_k = c$, else $\delta(\pi[k-1], c)$ ($\delta(0,c) = 0$) |
| Z-function | $z[i] = \mathrm{LCP}(s, s[i..])$, $z[0] = n$; box $[l, r)$; $O(n)$ |
| periods from $z$ | $p$ is a period ⇔ $p + z[p] = n$ (or $p = n$) |
| Manacher | $d_1[i]$ = # odd palindromes centred at $i$, $d_2[i]$ = # even ones centred between $i-1, i$; total palindromic substrings $= \sum d_1 + \sum d_2$ |
| longest palindrome | $\max(2d_1[i] - 1, 2d_2[i])$ |
| trie size | $\le 1 + \sum \lvert s_i\rvert$ nodes; binary trie $\le 1 + nB$ |
| XOR greedy | best bit first: $2^b > \sum_{j<b} 2^j$ |
| max XOR subarray | $\max_{i<j} P_i \oplus P_j$ with prefix XORs, $P_0 = 0$ |
| Aho–Corasick | $\le 1 + \sum\lvert p_i\rvert$ states; build $O(m\sigma)$; occurrences of all patterns: walk + push counts up the failure tree in reverse BFS order |
| suffix array | $sa$ = suffixes sorted; doubling $O(n\log n)$ (radix) or $O(n\log^2 n)$ (sort pairs) |
| Kasai | $lcp[rank[i]] \ge lcp[rank[i-1]] - 1$ ⇒ $O(n)$ |
| distinct substrings | $\sum_i (n - sa_i) - \sum_i lcp_i = \frac{n(n+1)}{2} - \sum lcp$ |
| LCP of suffixes $i, j$ | $\min lcp(rank_i + 1 .. rank_j]$ (sparse table) |
| longest repeated substring | $\max lcp$ |
| SAM size | $\le 2n - 1$ states, $\le 3n - 4$ transitions ($n \ge 3$) |
| SAM distinct substrings | $\sum_{v \ne 0} (len_v - len_{link_v})$ |
| SAM occurrences | `cnt = 1` on non-clones; by decreasing `len`: `cnt[link[v]] += cnt[v]` |
| eertree | $\le n$ distinct non-empty palindromes ⇒ $\le n + 2$ nodes; amortised $O(n)$ |

## 2. Complexity table

| Structure | Build | Query | Memory |
|---|---|---|---|
| rolling hash | $O(n)$ | substring hash $O(1)$, LCP $O(\log n)$ | $O(n)$ |
| prefix function / Z / Manacher | $O(n)$ | — | $O(n)$ |
| KMP automaton | $O(m\sigma)$ | step $O(1)$ | $O(m\sigma)$ |
| trie | $O(\sum\lvert s\rvert \cdot \sigma)$ array / $O(\sum\lvert s\rvert)$ map | $O(\lvert s\rvert)$ | nodes $\times \sigma$ |
| binary trie | $O(nB)$ | max/min XOR, count $< k$: $O(B)$ | $O(nB)$ |
| Aho–Corasick | $O(m\sigma)$ | text $O(n)$ | $O(m\sigma)$ |
| suffix array + LCP | $O(n\log n)$ + $O(n)$ | LCP of two suffixes $O(1)$ with sparse table | $O(n\log n)$ with table |
| suffix automaton | $O(n\sigma)$ arrays / $O(n\log\sigma)$ map | walk $O(\lvert p\rvert)$ | $O(n\sigma)$ |
| eertree | $O(n\sigma)$ | — | $O(n\sigma)$ |

## 3. Signal → technique

| Signal | Technique |
|---|---|
| one pattern, all occurrences, $10^6$ | prefix function or Z on $p\#t$ |
| "prefix that is also a suffix", "period", "repetition of" | prefix function |
| "longest common prefix of $s$ and every suffix" | Z-function |
| compare arbitrary substrings, LCP queries, "is $s[a..b]$ = $s[c..d]$" | hashing (+ binary search); suffix array + RMQ if deterministic |
| longest palindrome / count palindromes / palindromes at each index | Manacher (+ difference arrays) |
| distinct palindromes and their occurrence counts | eertree |
| many words: prefix counts, autocomplete, "word break" | trie |
| max XOR pair / subarray, count pairs with XOR $< k$ | binary trie on (prefix) XORs |
| many patterns in one text, or DP over strings avoiding a dictionary | Aho–Corasick |
| count strings of length $N$ avoiding one pattern | KMP automaton DP (matrix power if $N$ huge) |
| distinct substrings, $k$-th substring, longest repeat | suffix array / suffix automaton |
| longest common substring of two strings | SAM of one + matching statistics, or SA of $s\#t$ |
| occurrences of every substring, $\sum \mathrm{occ}^2$ | SAM `cnt` / SA + stack |
| online appends + substring queries | suffix automaton |

## 4. Templates (part 1)

### 4.1 Hashing mod $2^{61}-1$ with a random base

```cpp
struct Hash61 {
    static constexpr ull MOD = (1ULL << 61) - 1;
    static ull mul(ull a, ull b) { __uint128_t c = (__uint128_t)a * b; ull r = (ull)(c & MOD) + (ull)(c >> 61); return r >= MOD ? r - MOD : r; }
    static ull base() { static ull B = mt19937_64(chrono::steady_clock::now().time_since_epoch().count())() % (MOD - 1024) + 512; return B; }
    vector<ull> h, p;
    explicit Hash61(const string& s) : h(s.size() + 1, 0), p(s.size() + 1, 1) {
        ull B = base();
        for (size_t i = 0; i < s.size(); i++) {
            h[i + 1] = mul(h[i], B) + (unsigned char)s[i]; if (h[i + 1] >= MOD) h[i + 1] -= MOD;
            p[i + 1] = mul(p[i], B);
        }
    }
    ull get(int l, int r) const { ull x = h[r] + MOD - mul(h[l], p[r - l]); return x >= MOD ? x - MOD : x; }   // [l, r)
};
```

```java
static final class Hash61 {
    static final long MOD = (1L << 61) - 1;
    static final long BASE = 512 + Math.floorMod(new Random().nextLong(), MOD - 1024);
    static long mul(long a, long b) {                      // a, b < 2^61
        long hi = Math.multiplyHigh(a, b), lo = a * b;
        long r = (lo & MOD) + ((lo >>> 61) | (hi << 3));
        return r >= MOD ? r - MOD : r;
    }
    final long[] h, p;
    Hash61(String s) {
        int n = s.length(); h = new long[n + 1]; p = new long[n + 1]; p[0] = 1;
        for (int i = 0; i < n; i++) {
            h[i + 1] = mul(h[i], BASE) + s.charAt(i); if (h[i + 1] >= MOD) h[i + 1] -= MOD;
            p[i + 1] = mul(p[i], BASE);
        }
    }
    long get(int l, int r) { long x = h[r] - mul(h[l], p[r - l]); return x < 0 ? x + MOD : x; }
}
```

LCP of $s[i..]$ and $s[j..]$: binary search the largest $L$ with `get(i, i+L) == get(j, j+L)`; compare substrings by the first differing character after the LCP.

### 4.2 Prefix function, Z-function, Manacher

```cpp
vector<int> prefixFunction(const string& s) {
    int n = s.size(); vector<int> pi(n, 0);
    for (int i = 1; i < n; i++) { int k = pi[i - 1]; while (k > 0 && s[i] != s[k]) k = pi[k - 1]; if (s[i] == s[k]) k++; pi[i] = k; }
    return pi;
}
vector<int> zFunction(const string& s) {                   // z[0] = n, half-open box [l, r)
    int n = s.size(); vector<int> z(n, 0); if (n) z[0] = n;
    for (int i = 1, l = 0, r = 0; i < n; i++) {
        if (i < r) z[i] = min(r - i, z[i - l]);
        while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
        if (i + z[i] > r) { l = i; r = i + z[i]; }
    }
    return z;
}
void manacher(const string& s, vector<int>& d1, vector<int>& d2) {
    int n = s.size(); d1.assign(n, 0); d2.assign(n, 0);
    for (int i = 0, l = 0, r = -1; i < n; i++) {           // odd: s[i-k+1 .. i+k-1]
        int k = i > r ? 1 : min(d1[l + r - i], r - i + 1);
        while (i - k >= 0 && i + k < n && s[i - k] == s[i + k]) k++;
        d1[i] = k--; if (i + k > r) { l = i - k; r = i + k; }
    }
    for (int i = 0, l = 0, r = -1; i < n; i++) {           // even: s[i-k .. i+k-1]
        int k = i > r ? 0 : min(d2[l + r - i + 1], r - i + 1);
        while (i - k - 1 >= 0 && i + k < n && s[i - k - 1] == s[i + k]) k++;
        d2[i] = k--; if (i + k > r) { l = i - k - 1; r = i + k; }
    }
}
```

```java
static int[] prefixFunction(char[] s) {
    int n = s.length; int[] pi = new int[n];
    for (int i = 1; i < n; i++) { int k = pi[i - 1]; while (k > 0 && s[i] != s[k]) k = pi[k - 1]; if (s[i] == s[k]) k++; pi[i] = k; }
    return pi;
}
static int[] zFunction(char[] s) {
    int n = s.length; int[] z = new int[n]; if (n > 0) z[0] = n;
    for (int i = 1, l = 0, r = 0; i < n; i++) {
        if (i < r) z[i] = Math.min(r - i, z[i - l]);
        while (i + z[i] < n && s[z[i]] == s[i + z[i]]) z[i]++;
        if (i + z[i] > r) { l = i; r = i + z[i]; }
    }
    return z;
}
static int[][] manacher(char[] s) {                        // returns {d1, d2}
    int n = s.length; int[] d1 = new int[n], d2 = new int[n];
    for (int i = 0, l = 0, r = -1; i < n; i++) {
        int k = i > r ? 1 : Math.min(d1[l + r - i], r - i + 1);
        while (i - k >= 0 && i + k < n && s[i - k] == s[i + k]) k++;
        d1[i] = k--; if (i + k > r) { l = i - k; r = i + k; }
    }
    for (int i = 0, l = 0, r = -1; i < n; i++) {
        int k = i > r ? 0 : Math.min(d2[l + r - i + 1], r - i + 1);
        while (i - k - 1 >= 0 && i + k < n && s[i - k - 1] == s[i + k]) k++;
        d2[i] = k--; if (i + k > r) { l = i - k - 1; r = i + k; }
    }
    return new int[][]{d1, d2};
}
```

### 4.3 Binary trie (multiset, counts, max XOR, count $x \oplus y < k$)

```cpp
struct BinTrie {
    static const int B = 30;
    vector<array<int, 2>> ch; vector<int> cnt;              // node 0 = root; child index 0 = null
    BinTrie() { ch.push_back({0, 0}); cnt.push_back(0); }
    void add(int x, int d) {                                // d = +1 insert, -1 erase (must exist)
        int v = 0; cnt[v] += d;
        for (int b = B - 1; b >= 0; b--) {
            int c = x >> b & 1;
            if (!ch[v][c]) { ch[v][c] = ch.size(); ch.push_back({0, 0}); cnt.push_back(0); }
            v = ch[v][c]; cnt[v] += d;
        }
    }
    int maxXor(int x) const {                               // multiset must be non-empty
        int v = 0, r = 0;
        for (int b = B - 1; b >= 0; b--) {
            int c = x >> b & 1, w = ch[v][c ^ 1];
            if (w && cnt[w] > 0) { r |= 1 << b; v = w; } else v = ch[v][c];
        }
        return r;
    }
    long long countLess(int x, int k) const {               // #y with (x ^ y) < k
        long long res = 0; int v = 0;
        for (int b = B - 1; b >= 0; b--) {
            int xb = x >> b & 1, kb = k >> b & 1;
            if (kb) { if (ch[v][xb]) res += cnt[ch[v][xb]]; v = ch[v][xb ^ 1]; }
            else v = ch[v][xb];
            if (!v) break;
        }
        return res;
    }
};
```

```java
static final class BinTrie {
    static final int B = 30;
    int[][] ch; int[] cnt; int size = 1;
    BinTrie(int maxInserts) { ch = new int[2][maxInserts * B + 2]; cnt = new int[maxInserts * B + 2]; }
    void add(int x, int d) {
        int v = 0; cnt[v] += d;
        for (int b = B - 1; b >= 0; b--) {
            int c = x >> b & 1;
            if (ch[c][v] == 0) ch[c][v] = size++;
            v = ch[c][v]; cnt[v] += d;
        }
    }
    int maxXor(int x) {
        int v = 0, r = 0;
        for (int b = B - 1; b >= 0; b--) {
            int c = x >> b & 1, w = ch[c ^ 1][v];
            if (w != 0 && cnt[w] > 0) { r |= 1 << b; v = w; } else v = ch[c][v];
        }
        return r;
    }
    long countLess(int x, int k) {
        long res = 0; int v = 0;
        for (int b = B - 1; b >= 0; b--) {
            int xb = x >> b & 1, kb = k >> b & 1;
            if (kb == 1) { if (ch[xb][v] != 0) res += cnt[ch[xb][v]]; v = ch[xb ^ 1][v]; }
            else v = ch[xb][v];
            if (v == 0) break;
        }
        return res;
    }
}
```

String trie: same shape with 26 children per node, `pass[v]` (words through $v$) and `end[v]` (words ending at $v$); prefix count = `pass` of the node reached.

## 5. Templates (part 2)

### 5.1 Aho–Corasick (lowercase): goto + failure links, occurrences of every pattern

```cpp
struct AhoCorasick {
    vector<array<int, 26>> go; vector<int> link, order;
    AhoCorasick() { go.push_back({}); go[0].fill(-1); link.push_back(0); }
    int insert(const string& s) {                           // returns the terminal node of s
        int v = 0;
        for (char ch : s) {
            int c = ch - 'a';
            if (go[v][c] < 0) { go[v][c] = go.size(); go.push_back({}); go.back().fill(-1); link.push_back(0); }
            v = go[v][c];
        }
        return v;
    }
    void build() {                                          // BFS; missing edges become automaton edges
        order.clear(); queue<int> q;
        for (int c = 0; c < 26; c++) { int u = go[0][c]; if (u < 0) go[0][c] = 0; else { link[u] = 0; q.push(u); } }
        while (!q.empty()) {
            int v = q.front(); q.pop(); order.push_back(v);
            for (int c = 0; c < 26; c++) {
                int u = go[v][c];
                if (u < 0) go[v][c] = go[link[v]][c]; else { link[u] = go[link[v]][c]; q.push(u); }
            }
        }
    }
    vector<long long> countAll(const string& t) {           // cnt[terminal(p)] = occurrences of p in t
        vector<long long> cnt(go.size(), 0);
        int v = 0;
        for (char ch : t) { v = go[v][ch - 'a']; cnt[v]++; }
        for (int i = (int)order.size() - 1; i >= 0; i--) cnt[link[order[i]]] += cnt[order[i]];
        return cnt;
    }
};
```

```java
static final class AhoCorasick {
    final int[] go, link, order; int size = 1, ordLen = 0;
    AhoCorasick(int maxNodes) { go = new int[maxNodes * 26]; Arrays.fill(go, -1); link = new int[maxNodes]; order = new int[maxNodes]; }
    int insert(String s) {
        int v = 0;
        for (int i = 0; i < s.length(); i++) { int c = s.charAt(i) - 'a'; if (go[v * 26 + c] < 0) go[v * 26 + c] = size++; v = go[v * 26 + c]; }
        return v;
    }
    void build() {
        int head = 0;
        for (int c = 0; c < 26; c++) { int u = go[c]; if (u < 0) go[c] = 0; else { link[u] = 0; order[ordLen++] = u; } }
        while (head < ordLen) {
            int v = order[head++];
            for (int c = 0; c < 26; c++) {
                int u = go[v * 26 + c];
                if (u < 0) go[v * 26 + c] = go[link[v] * 26 + c]; else { link[u] = go[link[v] * 26 + c]; order[ordLen++] = u; }
            }
        }
    }
    long[] countAll(String t) {
        long[] cnt = new long[size];
        int v = 0;
        for (int i = 0; i < t.length(); i++) { v = go[v * 26 + t.charAt(i) - 'a']; cnt[v]++; }
        for (int i = ordLen - 1; i >= 0; i--) cnt[link[order[i]]] += cnt[order[i]];
        return cnt;
    }
}
```

### 5.2 Suffix array ($O(n\log n)$ radix doubling) + Kasai LCP

```cpp
vector<int> suffixArray(const string& s) {                  // s must not contain '\0'
    string t = s + char(0);
    int n = t.size(), classes = 1;
    vector<int> p(n), c(n), pn(n), cn(n), cnt(max(256, n), 0);
    for (char ch : t) cnt[(unsigned char)ch]++;
    for (int i = 1; i < 256; i++) cnt[i] += cnt[i - 1];
    for (int i = n - 1; i >= 0; i--) p[--cnt[(unsigned char)t[i]]] = i;
    c[p[0]] = 0;
    for (int i = 1; i < n; i++) { if (t[p[i]] != t[p[i - 1]]) classes++; c[p[i]] = classes - 1; }
    for (int h = 1; h < n; h <<= 1) {
        for (int i = 0; i < n; i++) { pn[i] = p[i] - h; if (pn[i] < 0) pn[i] += n; }   // sorted by second half already
        fill(cnt.begin(), cnt.begin() + classes, 0);
        for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
        for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
        cn[p[0]] = 0; classes = 1;
        for (int i = 1; i < n; i++) {
            if (c[p[i]] != c[p[i - 1]] || c[(p[i] + h) % n] != c[(p[i - 1] + h) % n]) classes++;
            cn[p[i]] = classes - 1;
        }
        c.swap(cn);
    }
    p.erase(p.begin());                                     // drop the sentinel suffix
    return p;
}
vector<int> lcpArray(const string& s, const vector<int>& sa) {   // lcp[i] = LCP(sa[i-1], sa[i]), lcp[0] = 0
    int n = s.size(); vector<int> rnk(n), lcp(n, 0);
    for (int i = 0; i < n; i++) rnk[sa[i]] = i;
    for (int i = 0, k = 0; i < n; i++) {
        if (rnk[i] == 0) { k = 0; continue; }
        int j = sa[rnk[i] - 1];
        while (i + k < n && j + k < n && s[i + k] == s[j + k]) k++;
        lcp[rnk[i]] = k; if (k) k--;
    }
    return lcp;
}
```

```java
static int[] suffixArray(String s) {                          // chars < 256, no '\0'
    int n = s.length() + 1, classes = 1;
    int[] p = new int[n], c = new int[n], pn = new int[n], cn = new int[n], cnt = new int[Math.max(256, n)];
    for (int i = 0; i < n; i++) cnt[i < n - 1 ? s.charAt(i) : 0]++;
    for (int i = 1; i < 256; i++) cnt[i] += cnt[i - 1];
    for (int i = n - 1; i >= 0; i--) p[--cnt[i < n - 1 ? s.charAt(i) : 0]] = i;
    for (int i = 1; i < n; i++) {
        int a = p[i] < n - 1 ? s.charAt(p[i]) : 0, b = p[i - 1] < n - 1 ? s.charAt(p[i - 1]) : 0;
        if (a != b) classes++;
        c[p[i]] = classes - 1;
    }
    for (int h = 1; h < n; h <<= 1) {
        for (int i = 0; i < n; i++) { pn[i] = p[i] - h; if (pn[i] < 0) pn[i] += n; }
        Arrays.fill(cnt, 0, classes, 0);
        for (int i = 0; i < n; i++) cnt[c[pn[i]]]++;
        for (int i = 1; i < classes; i++) cnt[i] += cnt[i - 1];
        for (int i = n - 1; i >= 0; i--) p[--cnt[c[pn[i]]]] = pn[i];
        cn[p[0]] = 0; classes = 1;
        for (int i = 1; i < n; i++) {
            if (c[p[i]] != c[p[i - 1]] || c[(p[i] + h) % n] != c[(p[i - 1] + h) % n]) classes++;
            cn[p[i]] = classes - 1;
        }
        int[] t = c; c = cn; cn = t;
    }
    return Arrays.copyOfRange(p, 1, n);
}
static int[] lcpArray(String s, int[] sa) {
    int n = s.length(); int[] rnk = new int[n], lcp = new int[n];
    for (int i = 0; i < n; i++) rnk[sa[i]] = i;
    for (int i = 0, k = 0; i < n; i++) {
        if (rnk[i] == 0) { k = 0; continue; }
        int j = sa[rnk[i] - 1];
        while (i + k < n && j + k < n && s.charAt(i + k) == s.charAt(j + k)) k++;
        lcp[rnk[i]] = k; if (k > 0) k--;
    }
    return lcp;
}
```

### 5.3 Suffix automaton (lowercase): distinct substrings and occurrence counts

```cpp
struct SAM {
    vector<array<int, 26>> nxt; vector<int> link, len; vector<long long> cnt; int last = 0;
    int newState(int l) { nxt.emplace_back(); nxt.back().fill(-1); link.push_back(-1); len.push_back(l); cnt.push_back(0); return nxt.size() - 1; }
    SAM() { newState(0); }
    void extend(int c) {
        int cur = newState(len[last] + 1); cnt[cur] = 1;    // clones get cnt 0
        int p = last;
        while (p != -1 && nxt[p][c] == -1) { nxt[p][c] = cur; p = link[p]; }
        if (p == -1) link[cur] = 0;
        else {
            int q = nxt[p][c];
            if (len[p] + 1 == len[q]) link[cur] = q;
            else {
                int cl = newState(len[p] + 1);
                nxt[cl] = nxt[q]; link[cl] = link[q];
                while (p != -1 && nxt[p][c] == q) { nxt[p][c] = cl; p = link[p]; }
                link[q] = link[cur] = cl;
            }
        }
        last = cur;
    }
    long long distinct() const { long long r = 0; for (size_t v = 1; v < len.size(); v++) r += len[v] - len[link[v]]; return r; }
    vector<long long> occurrences() const {                  // endpos sizes, by counting sort on len
        int m = len.size(), maxL = *max_element(len.begin(), len.end());
        vector<int> bucket(maxL + 1, 0), ord(m);
        for (int v = 0; v < m; v++) bucket[len[v]]++;
        for (int i = 1; i <= maxL; i++) bucket[i] += bucket[i - 1];
        for (int v = m - 1; v >= 0; v--) ord[--bucket[len[v]]] = v;
        vector<long long> occ = cnt;
        for (int i = m - 1; i > 0; i--) occ[link[ord[i]]] += occ[ord[i]];
        return occ;
    }
};
```

```java
static final class SAM {
    final int[] next, link, len; final long[] cnt; int size = 1, last = 0;
    SAM(int maxLen) { int m = 2 * maxLen + 2; next = new int[m * 26]; Arrays.fill(next, -1); link = new int[m]; len = new int[m]; cnt = new long[m]; link[0] = -1; }
    void extend(int c) {
        int cur = size++; len[cur] = len[last] + 1; cnt[cur] = 1;
        int p = last;
        while (p != -1 && next[p * 26 + c] == -1) { next[p * 26 + c] = cur; p = link[p]; }
        if (p == -1) link[cur] = 0;
        else {
            int q = next[p * 26 + c];
            if (len[p] + 1 == len[q]) link[cur] = q;
            else {
                int cl = size++; len[cl] = len[p] + 1; link[cl] = link[q];
                System.arraycopy(next, q * 26, next, cl * 26, 26);
                while (p != -1 && next[p * 26 + c] == q) { next[p * 26 + c] = cl; p = link[p]; }
                link[q] = cl; link[cur] = cl;
            }
        }
        last = cur;
    }
    long distinct() { long r = 0; for (int v = 1; v < size; v++) r += len[v] - len[link[v]]; return r; }
    long[] occurrences() {
        int maxL = len[last]; int[] bucket = new int[maxL + 1], ord = new int[size];
        for (int v = 0; v < size; v++) bucket[len[v]]++;
        for (int i = 1; i <= maxL; i++) bucket[i] += bucket[i - 1];
        for (int v = size - 1; v >= 0; v--) ord[--bucket[len[v]]] = v;
        long[] occ = Arrays.copyOf(cnt, size);
        for (int i = size - 1; i > 0; i--) occ[link[ord[i]]] += occ[ord[i]];
        return occ;
    }
}
```

### 5.4 Eertree (lowercase): node 0 has length $-1$, node 1 is the empty palindrome

```cpp
struct Eertree {
    vector<array<int, 26>> nxt; vector<int> len, link, occ; string s; int last = 1;
    int node(int l, int lk) { nxt.emplace_back(); nxt.back().fill(0); len.push_back(l); link.push_back(lk); occ.push_back(0); return len.size() - 1; }
    Eertree() { node(-1, 0); node(0, 0); }
    int getLink(int v, int i) const { while (!(i - 1 - len[v] >= 0 && s[i - 1 - len[v]] == s[i])) v = link[v]; return v; }
    void add(char ch) {
        s.push_back(ch); int i = s.size() - 1, c = ch - 'a';
        int cur = getLink(last, i);
        if (!nxt[cur][c]) {
            int lk = len[cur] == -1 ? 1 : nxt[getLink(link[cur], i)][c];
            int v = node(len[cur] + 2, lk);
            nxt[cur][c] = v;
        }
        last = nxt[cur][c]; occ[last]++;
    }
    int distinct() const { return (int)len.size() - 2; }
    vector<long long> occurrences() const {                  // links point to earlier nodes
        vector<long long> o(occ.begin(), occ.end());
        for (int v = (int)len.size() - 1; v >= 2; v--) o[link[v]] += o[v];
        return o;
    }
};
```

```java
static final class Eertree {
    final int[] next, len, link, occ; final char[] s; int size = 2, last = 1, n = 0;
    Eertree(int maxLen) { int m = maxLen + 3; next = new int[m * 26]; len = new int[m]; link = new int[m]; occ = new int[m]; s = new char[maxLen]; len[0] = -1; }
    int getLink(int v, int i) { while (!(i - 1 - len[v] >= 0 && s[i - 1 - len[v]] == s[i])) v = link[v]; return v; }
    void add(char ch) {
        int i = n; s[n++] = ch; int c = ch - 'a';
        int cur = getLink(last, i);
        if (next[cur * 26 + c] == 0) {
            int lk = len[cur] == -1 ? 1 : next[getLink(link[cur], i) * 26 + c];
            int v = size++; len[v] = len[cur] + 2; link[v] = lk;
            next[cur * 26 + c] = v;
        }
        last = next[cur * 26 + c]; occ[last]++;
    }
    int distinct() { return size - 2; }
    long[] occurrences() { long[] o = new long[size]; for (int v = 0; v < size; v++) o[v] = occ[v]; for (int v = size - 1; v >= 2; v--) o[link[v]] += o[v]; return o; }
}
```

## 6. Edge cases and constants

| Case | Check |
|---|---|
| empty pattern / $n = 1$ | $\pi = [0]$, $z = [1]$, $d_1 = [1]$, SA = [0], one SAM state + root |
| separator in $p\#t$ | must not occur in either string; for integer alphabets use a value outside the range |
| all-equal string `aaaa` | worst case for naive matching, $\pi[i] = i$, $n$ distinct palindromes |
| uppercase / digits | adjust the `- 'a'` offset and $\sigma$ |
| large alphabets (integers) | map transitions (SAM / trie) or coordinate compression |
| overflow | pair counts $\approx n^2/2$, occurrence sums, $\sum \mathrm{occ}^2$: 64-bit |
| hash mod | $2^{61}-1$ (128-bit mul) or two mods $10^9+7$, $998244353$; **random** base, never 31/131 on CF |
| memory | SAM arrays $2n \times 26$ ints: $n = 10^6$ → 208 MB — use maps or `int` + smaller $\sigma$ |

## 7. Top 10 mistakes

1. Fixed hash base or mod on Codeforces (anti-hash tests break `B = 131`, `M = 2^{64}` overflow hashing is broken by Thue–Morse strings).
2. Forgetting `p[r - l]` scaling in substring hashes, or negative values after subtraction (Java `%`).
3. In KMP matching, not resetting `k = pi[k-1]` after a full match ($k = m$).
4. Z-function: confusing closed and half-open boxes; forgetting $z[0]$ convention.
5. Manacher: off-by-one between $d_2$ centres (between $i-1$ and $i$).
6. Aho–Corasick: pushing counts in BFS order instead of **reverse** BFS order; forgetting dictionary links when listing all matches.
7. Suffix array: no sentinel (cyclic shifts ≠ suffixes) or comparing ranks of $(p + h) \bmod n$ without the sentinel.
8. Kasai: `lcp[i]` meaning LCP with the **previous** suffix in SA order — mixing it with "next" shifts every formula.
9. SAM: giving clones `cnt = 1`, or recursing on the link tree (depth up to $n$) instead of counting sort by `len`.
10. Eertree: wrong link for single-character palindromes (must be the empty node), or node 0/1 role mix-up.

## 8. Last-minute before the contest

- [ ] Random-base mod $2^{61}-1$ hash compiles in both languages (`__uint128_t` / `Math.multiplyHigh`).
- [ ] Prefix function, Z, Manacher written from memory and checked on `abacaba`, `aaaa`, `ab`.
- [ ] Binary trie: array sizes $n \cdot B$; erase decrements counts along the path.
- [ ] Aho–Corasick: BFS order stored; reverse it for count propagation.
- [ ] SA + Kasai: distinct substrings of `abab` = 7; of `aaa` = 3.
- [ ] SAM: `2n` states; occurrences by counting sort on `len`; distinct substrings of `abab` = 7.
- [ ] Eertree: `abacaba` has 7 distinct palindromes (`a, b, c, aba, aca, bacab, abacaba`).
- [ ] Java: read strings with the byte-buffer reader, build output in one `StringBuilder`.
