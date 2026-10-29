# Compressed Radix Tries, Aho–Corasick Automata and Bitwise XOR Tries

> **Folder 03 · File 3 of 3** — the trie as a router (longest-prefix match on path segments), as a multi-pattern automaton whose entire state is one integer (which makes streaming and sharding trivial), and as a binary trie that answers bitwise-optimization queries greedily.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 3.5 | `Tries.java` | 50,001 route keys: plain trie 890,298 nodes vs radix trie 66,314. 40,000 get/prefix-count checks vs `TreeSet`; segment-boundary longest-prefix match. Aho–Corasick vs `indexOf` on 2,000 random pattern sets; 2,000 patterns over 2 M chars streamed in random chunks and sharded with a halo. XOR trie vs brute force |
| 3.6 | `trie_family.cpp` | The same in C++23, with identical counts. (The file is not called `tries.cpp`: on Windows' case-insensitive file system it would collide with `Tries.java`'s output, and the harness refuses such pairs) |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)** except the Aho–Corasick timing line (**one measured run**).

---

## 0. Orientation

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| `int next[MAXNODES][26]` | Fixed alphabet; memory = nodes × 26 × 4 B, mostly zeros | Map or array children chosen by alphabet size; **compressed** edges for long keys |
| One node per character for URL-like keys | 13× more nodes than needed (measured) | Radix trie: edges carry substrings; nodes = O(keys) |
| Prefix match on raw strings | `/orders` routes `/ordersXYZ` | Match only at segment boundaries (`/` or end) |
| Aho–Corasick by following failure links at every position | O(n × depth) output walks | Output (dictionary) links: visit only states that end a pattern |
| Run the matcher over the whole text in memory | Doesn't stream; doesn't shard | Carry **one int** of automaton state between chunks; halo of `maxLen − 1` across shards |
| Bit tricks re-derived per problem | Off-by-one in bit order | One binary trie with subtree counts; greedy from the top bit |

---

## 1. First principles

### 1.1 Tries and their compressed form

A trie stores keys by shared prefixes: one node per distinct prefix. Lookup is O(|key|), independent of the number of keys, and every node's subtree is "all keys with this prefix". That gives prefix counting, autocomplete and longest-prefix match. The cost is nodes: a plain trie has a node for every character of every unshared suffix. A **radix (Patricia) trie** collapses chains of single-child nodes into edges labelled with substrings. Every internal node then has ≥ 2 children or ends a key, so **nodes ≤ 2 × keys**, independent of key length. Inserting splits an edge at the first mismatch.

**Longest-prefix match** is the routing primitive. An IP routing table returns the most specific prefix that contains an address; an HTTP router returns the most specific registered route for a path. Walk down while edges match and remember the last node that ends a key. For paths, a key must match at a **segment boundary**. Otherwise a route registered for `/api/v2/orders` captures `/api/v2/ordersXYZ`, a real class of authorization and routing bugs.

### 1.2 Aho–Corasick

Matching k patterns in a text naively costs O(n × k × m). Aho–Corasick builds the trie of the patterns and adds a **failure link** to each node: the longest proper suffix of that node's string that is also a trie path. This is KMP's failure function generalized to a trie. Filling in every missing transition with the failure state's transition gives a complete automaton: **one table lookup per text character**. **Output links** point to the nearest suffix state that ends a whole pattern, so reporting matches costs O(matches), not O(depth). Total: O(n + m + matches) after O(m × alphabet) construction.

The property that matters for Staff extensions: **between two characters, the matcher's entire state is one integer.** Streaming means carrying that integer across chunk boundaries. Sharding means each shard starts from state 0 a little early.

### 1.3 Binary tries for XOR

Insert numbers as 31-bit strings from the most significant bit. To maximize `x ⊕ v` over stored `v`, walk from the top bit and prefer the child whose bit differs from x's. A 1 in a higher bit outweighs every lower bit combined, so the greedy choice at each level is optimal. With **subtree counts**, the same walk answers "how many stored v have `v ⊕ x < k`". At each bit where k has a 1, every value that makes this XOR bit 0 is strictly smaller, so add that whole subtree and follow the other branch. The pattern solves LeetCode 421 (maximum XOR pair), 1707 (max XOR with a limit, offline by sorting) and XOR-range counting problems.

---

## 2. The listings

### 2.1 Listing 3.5 — Java

```java
// Tries.java - radix trie as a longest-prefix router, Aho-Corasick over streams and shards, XOR trie for bitwise queries.
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

public final class Tries {

    static final class SplitMix64 {
        private long state;
        SplitMix64(long seed) { state = seed; }
        long next() {
            long z = (state += 0x9E3779B97F4A7C15L);
            z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9L;
            z = (z ^ (z >>> 27)) * 0x94D049BB133111EBL;
            return z ^ (z >>> 31);
        }
        int nextInt(int bound) { return (int) Long.remainderUnsigned(next(), bound); }
    }

    // ===================================================================== 1. plain trie vs compressed radix trie
    /** One node per character: simple, but a node per byte of every unshared suffix. */
    static final class PlainTrie {
        private final List<Map<Character, Integer>> next = new ArrayList<>();
        PlainTrie() { next.add(new HashMap<>()); }
        void insert(String s) {
            int v = 0;
            for (int i = 0; i < s.length(); i++) {
                Integer c = next.get(v).get(s.charAt(i));
                if (c == null) { c = next.size(); next.get(v).put(s.charAt(i), c); next.add(new HashMap<>()); }
                v = c;
            }
        }
        int nodes() { return next.size(); }
    }

    /**
     * Radix (compressed) trie: each edge carries a whole substring, so chains of single-child nodes collapse.
     * Nodes = O(number of keys), independent of key length. Longest-prefix match is what an HTTP router or an
     * IP routing table answers: the most specific registered route that is a prefix of the request.
     */
    static final class RadixTrie {
        private static final class Node {
            final Map<Character, Node> kids = new HashMap<>();
            String edge;     // label of the edge INTO this node
            String value;    // non-null if a key ends here
            int keysBelow;   // keys in this subtree (prefix counting)
            Node(String edge) { this.edge = edge; }
        }

        private final Node root = new Node("");
        private int nodes = 1;

        void put(String key, String value) {
            if (get(key) == null) addCount(key);
            Node v = root;
            int i = 0;
            while (true) {
                if (i == key.length()) { v.value = value; return; }
                Node c = v.kids.get(key.charAt(i));
                if (c == null) {
                    Node leaf = new Node(key.substring(i));
                    leaf.value = value;
                    leaf.keysBelow = 1;
                    v.kids.put(key.charAt(i), leaf);
                    nodes++;
                    return;
                }
                int common = 0;
                while (common < c.edge.length() && i + common < key.length() && c.edge.charAt(common) == key.charAt(i + common)) common++;
                if (common < c.edge.length()) {                  // split the edge at the mismatch
                    Node mid = new Node(c.edge.substring(0, common));
                    mid.keysBelow = c.keysBelow;   // already counts the new key (addCount ran first) ...
                    c.keysBelow--;                 // ... which does NOT live below the lower half
                    c.edge = c.edge.substring(common);
                    mid.kids.put(c.edge.charAt(0), c);
                    v.kids.put(mid.edge.charAt(0), mid);
                    nodes++;
                    c = mid;
                }
                v = c;
                i += common;
            }
        }

        private void addCount(String key) {  // called before insertion: bump counts along the existing path
            root.keysBelow++;
            Node v = root;
            int i = 0;
            while (i < key.length()) {
                Node c = v.kids.get(key.charAt(i));
                if (c == null || !key.startsWith(c.edge, i)) {
                    if (c != null) c.keysBelow++;              // the edge will be split; the lower half keeps its count
                    return;
                }
                c.keysBelow++;
                v = c;
                i += c.edge.length();
            }
        }

        String get(String key) {
            Node v = root;
            int i = 0;
            while (i < key.length()) {
                Node c = v.kids.get(key.charAt(i));
                if (c == null || !key.startsWith(c.edge, i)) return null;
                v = c;
                i += c.edge.length();
            }
            return v.value;
        }

        /**
         * Value of the longest key that is a prefix of `query`, or null. O(|query|). With segments = true a key only
         * matches at a path boundary ('/' or end of query): "/orders" must not route "/ordersXYZ".
         */
        String longestPrefixMatch(String query, boolean segments) {
            Node v = root;
            String best = v.value;
            int i = 0;
            while (i < query.length()) {
                Node c = v.kids.get(query.charAt(i));
                if (c == null || !query.startsWith(c.edge, i)) break;
                v = c;
                i += c.edge.length();
                if (v.value != null && (!segments || i == query.length() || query.charAt(i) == '/')) best = v.value;
            }
            return best;
        }

        /** Number of keys starting with `prefix`. O(|prefix|). */
        int countWithPrefix(String prefix) {
            Node v = root;
            int i = 0;
            while (i < prefix.length()) {
                Node c = v.kids.get(prefix.charAt(i));
                if (c == null) return 0;
                int k = 0;
                while (k < c.edge.length() && i + k < prefix.length() && c.edge.charAt(k) == prefix.charAt(i + k)) k++;
                if (i + k == prefix.length()) return c.keysBelow;   // prefix ends inside or at the end of this edge
                if (k < c.edge.length()) return 0;
                v = c;
                i += k;
            }
            return v.keysBelow;
        }

        int nodes() { return nodes; }
    }

    // ===================================================================== 2. Aho-Corasick
    /**
     * Trie of patterns + failure links (longest proper suffix that is also a trie path) + output links (nearest
     * suffix that is a whole pattern). Matching is one transition per text character: O(n + matches), and the
     * whole state between characters is ONE int -- which is what makes streaming and sharding easy.
     */
    static final class AhoCorasick {
        private final int[][] go;     // full goto function over the alphabet (dense: built once, read-only)
        private final int[] fail, out, patternAt;
        final int maxLen;

        AhoCorasick(List<String> patterns, int alphabet) {
            List<int[]> g = new ArrayList<>();
            List<Integer> pat = new ArrayList<>();
            g.add(new int[alphabet]);
            pat.add(-1);
            int longest = 0;
            for (int p = 0; p < patterns.size(); p++) {
                String s = patterns.get(p);
                if (s.isEmpty()) throw new IllegalArgumentException("empty pattern");
                longest = Math.max(longest, s.length());
                int v = 0;
                for (int i = 0; i < s.length(); i++) {
                    int ch = s.charAt(i) - 'a';
                    if (g.get(v)[ch] == 0) { g.get(v)[ch] = g.size(); g.add(new int[alphabet]); pat.add(-1); }
                    v = g.get(v)[ch];
                }
                if (pat.get(v) != -1) throw new IllegalArgumentException("duplicate pattern " + s);
                pat.set(v, p);
            }
            maxLen = longest;
            int n = g.size();
            go = g.toArray(new int[0][]);
            patternAt = pat.stream().mapToInt(Integer::intValue).toArray();
            fail = new int[n];
            out = new int[n];
            out[0] = -1;
            ArrayDeque<Integer> bfs = new ArrayDeque<>();
            for (int c = 0; c < alphabet; c++) if (go[0][c] != 0) { bfs.add(go[0][c]); out[go[0][c]] = -1; }
            while (!bfs.isEmpty()) {
                int v = bfs.poll();
                for (int c = 0; c < alphabet; c++) {
                    int u = go[v][c];
                    if (u == 0) { go[v][c] = go[fail[v]][c]; continue; }   // missing edge: borrow the failure state's
                    fail[u] = go[fail[v]][c];
                    out[u] = patternAt[fail[u]] != -1 ? fail[u] : out[fail[u]];
                    bfs.add(u);
                }
            }
        }

        int step(int state, char ch) { return go[state][ch - 'a']; }

        /** Calls back (patternId, endIndexExclusive) for every occurrence ending at this state. */
        void emit(int state, long endPos, long[] counts, long[] totalOut) {
            for (int v = patternAt[state] != -1 ? state : out[state]; v > 0; v = out[v]) {
                counts[patternAt[v]]++;
                totalOut[0]++;
            }
        }

        long[] countAll(String text, int patterns) {
            long[] counts = new long[patterns], total = new long[1];
            int s = 0;
            for (int i = 0; i < text.length(); i++) emit(s = step(s, text.charAt(i)), i + 1, counts, total);
            return counts;
        }
    }

    static long[] naiveCounts(String text, List<String> patterns) {
        long[] c = new long[patterns.size()];
        for (int p = 0; p < patterns.size(); p++)
            for (int i = text.indexOf(patterns.get(p)); i >= 0; i = text.indexOf(patterns.get(p), i + 1)) c[p]++;
        return c;
    }

    static String randomWord(SplitMix64 r, int maxLen, int alphabet) {
        StringBuilder sb = new StringBuilder();
        for (int i = 1 + r.nextInt(maxLen); i > 0; i--) sb.append((char) ('a' + r.nextInt(alphabet)));
        return sb.toString();
    }

    // ===================================================================== 3. binary (XOR) trie
    /** 31-level bit trie with subtree counts: max XOR partner and "how many stored values v have v ^ x < k". */
    static final class XorTrie {
        private static final int BITS = 31;
        private int[][] kid = new int[2][1 << 10];
        private int[] cnt = new int[1 << 10];
        private int nodes = 1;

        void insert(int x) {
            int v = 0;
            cnt[0]++;
            for (int b = BITS - 1; b >= 0; b--) {
                int bit = x >>> b & 1;
                if (kid[bit][v] == 0) {
                    if (nodes == cnt.length) grow();
                    kid[bit][v] = nodes++;
                }
                v = kid[bit][v];
                cnt[v]++;
            }
        }

        private void grow() {
            kid[0] = java.util.Arrays.copyOf(kid[0], nodes * 2);
            kid[1] = java.util.Arrays.copyOf(kid[1], nodes * 2);
            cnt = java.util.Arrays.copyOf(cnt, nodes * 2);
        }

        int maxXor(int x) {  // greedy from the top bit: prefer the child that makes this bit 1
            int v = 0, best = 0;
            for (int b = BITS - 1; b >= 0; b--) {
                int want = (x >>> b & 1) ^ 1;
                if (kid[want][v] != 0) { best |= 1 << b; v = kid[want][v]; } else v = kid[want ^ 1][v];
            }
            return best;
        }

        long countXorLess(int x, int k) {
            long total = 0;
            int v = 0;
            for (int b = BITS - 1; b >= 0 && v >= 0; b--) {
                int xb = x >>> b & 1, kb = k >>> b & 1;
                if (kb == 1) {                       // every value making this xor bit 0 is strictly smaller: count them
                    if (kid[xb][v] != 0) total += cnt[kid[xb][v]];
                    v = kid[xb ^ 1][v] != 0 ? kid[xb ^ 1][v] : -1;
                } else {
                    v = kid[xb][v] != 0 ? kid[xb][v] : -1;
                }
            }
            return total;
        }
    }

    public static void main(String[] args) {
        SplitMix64 r = new SplitMix64(71);
        String[] services = {"users", "orders", "payments", "inventory", "search", "auth"};
        RadixTrie router = new RadixTrie();
        PlainTrie plain = new PlainTrie();
        TreeSet<String> keys = new TreeSet<>();
        long chars = 0;
        for (int i = 0; i < 50_000; i++) {
            String path = "/api/v" + (1 + r.nextInt(3)) + "/" + services[r.nextInt(services.length)] + "/"
                    + String.format("%012x", r.next() & 0xFFFFFFFFFFFFL) + "/profile";
            router.put(path, "handler#" + i);
            plain.insert(path);
            if (keys.add(path)) chars += path.length();
        }
        router.put("/api/v2/orders", "orders-v2-collection");
        plain.insert("/api/v2/orders");
        if (keys.add("/api/v2/orders")) chars += "/api/v2/orders".length();
        int bad = 0;
        String[] keyArr = keys.toArray(new String[0]);  // sorted: half the queries are hits
        for (int q = 0; q < 20_000; q++) {
            String p = q % 2 == 0 ? keyArr[r.nextInt(keyArr.length)] : "/api/v" + (1 + r.nextInt(3)) + "/"
                    + services[r.nextInt(services.length)] + "/" + String.format("%012x", r.next() & 0xFFFFFFFFFFFFL) + "/profile";
            String prefix = p.substring(0, r.nextInt(p.length() + 1));
            int want = keys.subSet(prefix, prefix + Character.MAX_VALUE).size();
            if (router.countWithPrefix(prefix) != want) bad++;
            if ((router.get(p) != null) != keys.contains(p)) bad++;
        }
        System.out.printf("1. %,d distinct route keys (%,d chars): plain trie %,d nodes | radix trie %,d nodes | 40,000 get/prefix-count"
                + " checks vs TreeSet: %d mismatches%n", keys.size(), chars, plain.nodes(), router.nodes(), bad);
        System.out.printf("   longest-prefix match: /api/v2/orders/0123/items -> %s | /api/v9/x -> %s%n",
                router.longestPrefixMatch("/api/v2/orders/0123/items", true), router.longestPrefixMatch("/api/v9/x", true));
        System.out.printf("   /api/v2/ordersXYZ: string-prefix match -> %s | segment-boundary match -> %s%n",
                router.longestPrefixMatch("/api/v2/ordersXYZ", false), router.longestPrefixMatch("/api/v2/ordersXYZ", true));

        int acBad = 0, trials = 2_000;
        for (int t = 0; t < trials; t++) {
            List<String> pats = new ArrayList<>(new TreeSet<>(List.of(randomWord(r, 4, 3), randomWord(r, 4, 3), randomWord(r, 4, 3),
                    randomWord(r, 4, 3), randomWord(r, 4, 3))));
            String text = randomWord(r, 60, 3);
            if (!java.util.Arrays.equals(new AhoCorasick(pats, 3).countAll(text, pats.size()), naiveCounts(text, pats))) acBad++;
        }
        System.out.printf("2. Aho-Corasick vs indexOf per pattern, %,d random pattern sets over {a,b,c}: %d mismatches%n", trials, acBad);

        List<String> pats = new ArrayList<>();
        TreeSet<String> uniq = new TreeSet<>();
        while (uniq.size() < 2_000) uniq.add(randomWord(r, 8, 4));
        pats.addAll(uniq);
        AhoCorasick ac = new AhoCorasick(pats, 4);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 2_000_000; i++) sb.append((char) ('a' + r.nextInt(4)));
        String text = sb.toString();
        long t0 = System.nanoTime();
        long[] whole = ac.countAll(text, pats.size());
        double msWhole = (System.nanoTime() - t0) / 1e6;
        long[] streamed = new long[pats.size()], total = new long[1];   // B: arbitrary chunks, one int of carried state
        int state = 0, pos = 0;
        while (pos < text.length()) {
            int len = Math.min(text.length() - pos, 1 + r.nextInt(5_000));
            for (int i = pos; i < pos + len; i++) ac.emit(state = ac.step(state, text.charAt(i)), i + 1, streamed, total);
            pos += len;
        }
        int shards = 7;                                                  // C: shard i counts matches ENDING in its range
        long[] sharded = new long[pats.size()];
        for (int s = 0; s < shards; s++) {
            int lo = (int) ((long) text.length() * s / shards), hi = (int) ((long) text.length() * (s + 1) / shards);
            int st = 0;
            for (int i = Math.max(0, lo - (ac.maxLen - 1)); i < hi; i++) {
                st = ac.step(st, text.charAt(i));
                if (i >= lo) ac.emit(st, i + 1, sharded, new long[1]);
            }
        }
        long matches = 0;
        for (long c : whole) matches += c;
        System.out.printf("   %,d patterns (<= 8 chars), %,d-char text: %,d matches in %.0f ms (one measured run)%n", pats.size(),
                text.length(), matches, msWhole);
        System.out.printf("   B. fed in random chunks of 1..5,000 chars carrying one int of state: identical counts %b%n",
                java.util.Arrays.equals(whole, streamed));
        System.out.printf("   C. %d shards, each reading a halo of maxLen-1 = %d chars and counting matches that END in its range:"
                + " identical %b%n", shards, ac.maxLen - 1, java.util.Arrays.equals(whole, sharded));

        int xorBad = 0;
        for (int t = 0; t < 2_000; t++) {
            int n = 1 + r.nextInt(40);
            int[] a = new int[n];
            XorTrie trie = new XorTrie();
            for (int i = 0; i < n; i++) { a[i] = r.nextInt(1 << 20); trie.insert(a[i]); }
            int x = r.nextInt(1 << 20), k = r.nextInt(1 << 20), best = 0;
            long less = 0;
            for (int v : a) { best = Math.max(best, v ^ x); if ((v ^ x) < k) less++; }
            if (trie.maxXor(x) != best || trie.countXorLess(x, k) != less) xorBad++;
        }
        System.out.printf("3. XOR trie (max xor partner, count of v with v^x < k) vs brute force, 2,000 random sets: %d mismatches%n", xorBad);
    }
}
```

**Output (verified; one line is a measured run):**

```text
1. 50,001 distinct route keys (1,766,689 chars): plain trie 890,298 nodes | radix trie 66,314 nodes | 40,000 get/prefix-count checks vs TreeSet: 0 mismatches
   longest-prefix match: /api/v2/orders/0123/items -> orders-v2-collection | /api/v9/x -> null
   /api/v2/ordersXYZ: string-prefix match -> orders-v2-collection | segment-boundary match -> null
2. Aho-Corasick vs indexOf per pattern, 2,000 random pattern sets over {a,b,c}: 0 mismatches
   2,000 patterns (<= 8 chars), 2,000,000-char text: 8,730,862 matches in 44 ms (one measured run)
   B. fed in random chunks of 1..5,000 chars carrying one int of state: identical counts true
   C. 7 shards, each reading a halo of maxLen-1 = 7 chars and counting matches that END in its range: identical true
3. XOR trie (max xor partner, count of v with v^x < k) vs brute force, 2,000 random sets: 0 mismatches
```

### 2.2 Listing 3.6 — C++23

```cpp
// trie_family.cpp - radix trie as a longest-prefix router, Aho-Corasick over streams and shards, XOR trie for bitwise queries.
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <deque>
#include <format>
#include <map>
#include <memory>
#include <optional>
#include <print>
#include <set>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

inline std::size_t U(int x) { return static_cast<std::size_t>(x); }

struct SplitMix64 {
    std::uint64_t state;
    std::uint64_t next() noexcept {
        std::uint64_t z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    int next_int(int bound) noexcept { return static_cast<int>(next() % static_cast<std::uint64_t>(bound)); }
};

// ======================================================================= 1. plain trie vs compressed radix trie
class PlainTrie {  // one node per character
public:
    void insert(std::string_view s) {
        std::size_t v = 0;
        for (char ch : s) {
            auto [it, fresh] = next_[v].try_emplace(ch, next_.size());
            if (fresh) next_.emplace_back();
            v = it->second;
        }
    }
    std::size_t nodes() const { return next_.size(); }

private:
    std::vector<std::unordered_map<char, std::size_t>> next_{1};
};

// Radix (compressed) trie: each edge carries a whole substring, so single-child chains collapse. Nodes = O(keys).
// Longest-prefix match is what an HTTP router or an IP routing table answers.
class RadixTrie {
    struct Node {
        std::string edge;                 // label of the edge INTO this node
        std::optional<std::string> value;
        int keys_below = 0;
        std::map<char, std::unique_ptr<Node>> kids;
    };

public:
    void put(std::string_view key, std::string value) {
        if (!get(key)) add_count(key);
        Node* v = &root_;
        std::size_t i = 0;
        while (true) {
            if (i == key.size()) {
                v->value = std::move(value);
                return;
            }
            auto it = v->kids.find(key[i]);
            if (it == v->kids.end()) {
                auto leaf = std::make_unique<Node>();
                leaf->edge = std::string(key.substr(i));
                leaf->value = std::move(value);
                leaf->keys_below = 1;
                v->kids.emplace(key[i], std::move(leaf));
                ++nodes_;
                return;
            }
            Node* c = it->second.get();
            std::size_t common = 0;
            while (common < c->edge.size() && i + common < key.size() && c->edge[common] == key[i + common]) ++common;
            if (common < c->edge.size()) {  // split the edge at the mismatch
                auto mid = std::make_unique<Node>();
                mid->edge = c->edge.substr(0, common);
                mid->keys_below = c->keys_below;  // already counts the new key (add_count ran first) ...
                --c->keys_below;                  // ... which does NOT live below the lower half
                c->edge = c->edge.substr(common);
                char lower_first = c->edge[0];
                mid->kids.emplace(lower_first, std::move(it->second));
                it->second = std::move(mid);
                ++nodes_;
                c = it->second.get();
            }
            v = c;
            i += common;
        }
    }
    const std::string* get(std::string_view key) const {
        const Node* v = &root_;
        std::size_t i = 0;
        while (i < key.size()) {
            auto it = v->kids.find(key[i]);
            if (it == v->kids.end() || !key.substr(i).starts_with(it->second->edge)) return nullptr;
            v = it->second.get();
            i += v->edge.size();
        }
        return v->value ? &*v->value : nullptr;
    }
    // Longest key that is a prefix of `query`; with segments, a key only matches at '/' or at the end of the query.
    std::optional<std::string> longest_prefix_match(std::string_view query, bool segments) const {
        const Node* v = &root_;
        std::optional<std::string> best = v->value;
        std::size_t i = 0;
        while (i < query.size()) {
            auto it = v->kids.find(query[i]);
            if (it == v->kids.end() || !query.substr(i).starts_with(it->second->edge)) break;
            v = it->second.get();
            i += v->edge.size();
            if (v->value && (!segments || i == query.size() || query[i] == '/')) best = v->value;
        }
        return best;
    }
    int count_with_prefix(std::string_view prefix) const {
        const Node* v = &root_;
        std::size_t i = 0;
        while (i < prefix.size()) {
            auto it = v->kids.find(prefix[i]);
            if (it == v->kids.end()) return 0;
            const Node* c = it->second.get();
            std::size_t k = 0;
            while (k < c->edge.size() && i + k < prefix.size() && c->edge[k] == prefix[i + k]) ++k;
            if (i + k == prefix.size()) return c->keys_below;  // prefix ends inside or at the end of this edge
            if (k < c->edge.size()) return 0;
            v = c;
            i += k;
        }
        return v->keys_below;
    }
    std::size_t nodes() const { return nodes_; }

private:
    void add_count(std::string_view key) {  // called before insertion: bump counts along the existing path
        ++root_.keys_below;
        Node* v = &root_;
        std::size_t i = 0;
        while (i < key.size()) {
            auto it = v->kids.find(key[i]);
            if (it == v->kids.end()) return;
            Node* c = it->second.get();
            ++c->keys_below;  // if the edge will be split, put() hands this count to the new middle node
            if (!key.substr(i).starts_with(c->edge)) return;
            v = c;
            i += c->edge.size();
        }
    }
    Node root_;
    std::size_t nodes_ = 1;
};

// ======================================================================= 2. Aho-Corasick
// Trie of patterns + failure links + output links. One transition per text character: O(n + matches), and the whole
// state between characters is ONE int -- which is what makes streaming and sharding easy.
class AhoCorasick {
public:
    AhoCorasick(const std::vector<std::string>& patterns, int alphabet) : a_(U(alphabet)) {
        go_.assign(a_, 0);
        pattern_at_.push_back(-1);
        for (std::size_t p = 0; p < patterns.size(); ++p) {
            const auto& s = patterns[p];
            if (s.empty()) throw std::invalid_argument("empty pattern");
            max_len = std::max(max_len, s.size());
            std::size_t v = 0;
            for (char ch : s) {
                std::size_t c = U(ch - 'a');
                if (go_[v * a_ + c] == 0) {
                    go_[v * a_ + c] = static_cast<int>(pattern_at_.size());
                    go_.resize(go_.size() + a_, 0);
                    pattern_at_.push_back(-1);
                }
                v = U(go_[v * a_ + c]);
            }
            if (pattern_at_[v] != -1) throw std::invalid_argument("duplicate pattern " + s);
            pattern_at_[v] = static_cast<int>(p);
        }
        std::size_t n = pattern_at_.size();
        fail_.assign(n, 0);
        out_.assign(n, -1);
        std::deque<std::size_t> bfs;
        for (std::size_t c = 0; c < a_; ++c)
            if (go_[c] != 0) bfs.push_back(U(go_[c]));
        while (!bfs.empty()) {
            std::size_t v = bfs.front();
            bfs.pop_front();
            for (std::size_t c = 0; c < a_; ++c) {
                int u = go_[v * a_ + c];
                if (u == 0) {
                    go_[v * a_ + c] = go_[U(fail_[v]) * a_ + c];  // missing edge: borrow the failure state's
                    continue;
                }
                fail_[U(u)] = go_[U(fail_[v]) * a_ + c];
                out_[U(u)] = pattern_at_[U(fail_[U(u)])] != -1 ? fail_[U(u)] : out_[U(fail_[U(u)])];
                bfs.push_back(U(u));
            }
        }
    }
    int step(int state, char ch) const { return go_[U(state) * a_ + U(ch - 'a')]; }
    void emit(int state, std::vector<std::int64_t>& counts) const {
        for (int v = pattern_at_[U(state)] != -1 ? state : out_[U(state)]; v > 0; v = out_[U(v)]) ++counts[U(pattern_at_[U(v)])];
    }
    std::vector<std::int64_t> count_all(std::string_view text, std::size_t patterns) const {
        std::vector<std::int64_t> counts(patterns);
        int s = 0;
        for (char ch : text) emit(s = step(s, ch), counts);
        return counts;
    }
    std::size_t max_len = 0;

private:
    std::size_t a_;
    std::vector<int> go_, fail_, out_, pattern_at_;
};

std::vector<std::int64_t> naive_counts(std::string_view text, const std::vector<std::string>& patterns) {
    std::vector<std::int64_t> c(patterns.size());
    for (std::size_t p = 0; p < patterns.size(); ++p)
        for (auto i = text.find(patterns[p]); i != std::string_view::npos; i = text.find(patterns[p], i + 1)) ++c[p];
    return c;
}

std::string random_word(SplitMix64& r, int max_len, int alphabet) {
    std::string s;
    for (int i = 1 + r.next_int(max_len); i > 0; --i) s += static_cast<char>('a' + r.next_int(alphabet));
    return s;
}

// ======================================================================= 3. binary (XOR) trie
// 31-level bit trie with subtree counts: max XOR partner and "how many stored values v have v ^ x < k".
class XorTrie {
public:
    void insert(int x) {
        std::size_t v = 0;
        ++cnt_[0];
        for (int b = kBits - 1; b >= 0; --b) {
            std::size_t bit = U(x >> b & 1);
            if (kid_[bit][v] == 0) {
                kid_[bit][v] = static_cast<int>(cnt_.size());
                kid_[0].push_back(0), kid_[1].push_back(0), cnt_.push_back(0);
            }
            v = U(kid_[bit][v]);
            ++cnt_[v];
        }
    }
    int max_xor(int x) const {  // greedy from the top bit: prefer the child that makes this bit 1
        std::size_t v = 0;
        int best = 0;
        for (int b = kBits - 1; b >= 0; --b) {
            std::size_t want = U((x >> b & 1) ^ 1);
            if (kid_[want][v] != 0) best |= 1 << b, v = U(kid_[want][v]);
            else v = U(kid_[want ^ 1][v]);
        }
        return best;
    }
    std::int64_t count_xor_less(int x, int k) const {
        std::int64_t total = 0;
        int v = 0;
        for (int b = kBits - 1; b >= 0 && v >= 0; --b) {
            std::size_t xb = U(x >> b & 1);
            if (k >> b & 1) {  // every value making this xor bit 0 is strictly smaller: count them
                if (kid_[xb][U(v)] != 0) total += cnt_[U(kid_[xb][U(v)])];
                v = kid_[xb ^ 1][U(v)] != 0 ? kid_[xb ^ 1][U(v)] : -1;
            } else {
                v = kid_[xb][U(v)] != 0 ? kid_[xb][U(v)] : -1;
            }
        }
        return total;
    }

private:
    static constexpr int kBits = 31;
    std::vector<int> kid_[2] = {{0}, {0}};
    std::vector<int> cnt_{0};
};

int main() {
    SplitMix64 r{71};
    const char* services[] = {"users", "orders", "payments", "inventory", "search", "auth"};
    RadixTrie router;
    PlainTrie plain;
    std::set<std::string> keys;
    std::size_t chars = 0;
    auto route = [&](SplitMix64& g) {
        int ver = 1 + g.next_int(3);
        const char* svc = services[g.next_int(6)];
        std::uint64_t id = g.next() & 0xFFFFFFFFFFFFULL;
        return std::format("/api/v{}/{}/{:012x}/profile", ver, svc, id);
    };
    for (int i = 0; i < 50'000; ++i) {
        std::string path = route(r);
        router.put(path, std::format("handler#{}", i));
        plain.insert(path);
        if (keys.insert(path).second) chars += path.size();
    }
    router.put("/api/v2/orders", "orders-v2-collection");
    plain.insert("/api/v2/orders");
    if (keys.insert("/api/v2/orders").second) chars += 14;
    std::vector<std::string> key_arr(keys.begin(), keys.end());  // sorted: half the queries are hits
    int bad = 0;
    for (int q = 0; q < 20'000; ++q) {
        std::string p = q % 2 == 0 ? key_arr[U(r.next_int(static_cast<int>(key_arr.size())))] : route(r);
        std::string prefix = p.substr(0, U(r.next_int(static_cast<int>(p.size()) + 1)));
        int want = 0;
        for (auto it = keys.lower_bound(prefix); it != keys.end() && it->starts_with(prefix); ++it) ++want;
        bad += router.count_with_prefix(prefix) != want;
        bad += (router.get(p) != nullptr) != keys.contains(p);
    }
    std::println("1. {} distinct route keys ({} chars): plain trie {} nodes | radix trie {} nodes | 40,000 get/prefix-count checks"
                 " vs std::set: {} mismatches", keys.size(), chars, plain.nodes(), router.nodes(), bad);
    auto show = [](const std::optional<std::string>& s) { return s.value_or("null"); };
    std::println("   longest-prefix match: /api/v2/orders/0123/items -> {} | /api/v9/x -> {}",
                 show(router.longest_prefix_match("/api/v2/orders/0123/items", true)), show(router.longest_prefix_match("/api/v9/x", true)));
    std::println("   /api/v2/ordersXYZ: string-prefix match -> {} | segment-boundary match -> {}",
                 show(router.longest_prefix_match("/api/v2/ordersXYZ", false)), show(router.longest_prefix_match("/api/v2/ordersXYZ", true)));

    int ac_bad = 0;
    for (int t = 0; t < 2'000; ++t) {
        std::set<std::string> uniq;
        for (int i = 0; i < 5; ++i) uniq.insert(random_word(r, 4, 3));
        std::vector<std::string> pats(uniq.begin(), uniq.end());
        std::string text = random_word(r, 60, 3);
        ac_bad += AhoCorasick(pats, 3).count_all(text, pats.size()) != naive_counts(text, pats);
    }
    std::println("2. Aho-Corasick vs find per pattern, 2,000 random pattern sets over {{a,b,c}}: {} mismatches", ac_bad);

    std::set<std::string> uniq;
    while (uniq.size() < 2'000) uniq.insert(random_word(r, 8, 4));
    std::vector<std::string> pats(uniq.begin(), uniq.end());
    AhoCorasick ac(pats, 4);
    std::string text(2'000'000, ' ');
    for (char& c : text) c = static_cast<char>('a' + r.next_int(4));
    auto t0 = std::chrono::steady_clock::now();
    auto whole = ac.count_all(text, pats.size());
    double ms_whole = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    std::vector<std::int64_t> streamed(pats.size());  // B: arbitrary chunks, one int of carried state
    int state = 0;
    for (std::size_t pos = 0; pos < text.size();) {
        std::size_t len = std::min(text.size() - pos, U(1 + r.next_int(5'000)));
        for (std::size_t i = pos; i < pos + len; ++i) ac.emit(state = ac.step(state, text[i]), streamed);
        pos += len;
    }
    constexpr std::size_t shards = 7;  // C: shard s counts matches ENDING in its range
    std::vector<std::int64_t> sharded(pats.size());
    for (std::size_t s = 0; s < shards; ++s) {
        std::size_t lo = text.size() * s / shards, hi = text.size() * (s + 1) / shards;
        int st = 0;
        for (std::size_t i = lo >= ac.max_len - 1 ? lo - (ac.max_len - 1) : 0; i < hi; ++i) {
            st = ac.step(st, text[i]);
            if (i >= lo) ac.emit(st, sharded);
        }
    }
    std::int64_t matches = 0;
    for (auto c : whole) matches += c;
    std::println("   {} patterns (<= 8 chars), {}-char text: {} matches in {:.0f} ms (one measured run)", pats.size(), text.size(),
                 matches, ms_whole);
    std::println("   B. fed in random chunks of 1..5,000 chars carrying one int of state: identical counts {}", whole == streamed);
    std::println("   C. {} shards, each reading a halo of maxLen-1 = {} chars and counting matches that END in its range: identical {}",
                 shards, ac.max_len - 1, whole == sharded);

    int xor_bad = 0;
    for (int t = 0; t < 2'000; ++t) {
        int n = 1 + r.next_int(40);
        std::vector<int> a(U(n));
        XorTrie trie;
        for (int& v : a) v = r.next_int(1 << 20), trie.insert(v);
        int x = r.next_int(1 << 20), k = r.next_int(1 << 20), best = 0;
        std::int64_t less = 0;
        for (int v : a) best = std::max(best, v ^ x), less += (v ^ x) < k;
        xor_bad += trie.max_xor(x) != best || trie.count_xor_less(x, k) != less;
    }
    std::println("3. XOR trie (max xor partner, count of v with v^x < k) vs brute force, 2,000 random sets: {} mismatches", xor_bad);
}
```

**Output, GCC 16.2 (verified; one line is a measured run):**

```text
1. 50001 distinct route keys (1766689 chars): plain trie 890298 nodes | radix trie 66314 nodes | 40,000 get/prefix-count checks vs std::set: 0 mismatches
   longest-prefix match: /api/v2/orders/0123/items -> orders-v2-collection | /api/v9/x -> null
   /api/v2/ordersXYZ: string-prefix match -> orders-v2-collection | segment-boundary match -> null
2. Aho-Corasick vs find per pattern, 2,000 random pattern sets over {a,b,c}: 0 mismatches
   2000 patterns (<= 8 chars), 2000000-char text: 8730862 matches in 35 ms (one measured run)
   B. fed in random chunks of 1..5,000 chars carrying one int of state: identical counts true
   C. 7 shards, each reading a halo of maxLen-1 = 7 chars and counting matches that END in its range: identical true
3. XOR trie (max xor partner, count of v with v^x < k) vs brute force, 2,000 random sets: 0 mismatches
```

**Output, Clang 21.1 (verified; one line is a measured run):**

```text
1. 50001 distinct route keys (1766689 chars): plain trie 890298 nodes | radix trie 66314 nodes | 40,000 get/prefix-count checks vs std::set: 0 mismatches
   longest-prefix match: /api/v2/orders/0123/items -> orders-v2-collection | /api/v9/x -> null
   /api/v2/ordersXYZ: string-prefix match -> orders-v2-collection | segment-boundary match -> null
2. Aho-Corasick vs find per pattern, 2,000 random pattern sets over {a,b,c}: 0 mismatches
   2000 patterns (<= 8 chars), 2000000-char text: 8730862 matches in 24 ms (one measured run)
   B. fed in random chunks of 1..5,000 chars carrying one int of state: identical counts true
   C. 7 shards, each reading a halo of maxLen-1 = 7 chars and counting matches that END in its range: identical true
3. XOR trie (max xor partner, count of v with v^x < k) vs brute force, 2,000 random sets: 0 mismatches
```

---

## 3. What the results show

* **Compression is worth 13× in nodes on realistic keys.** 50,001 keys of the form `/api/v2/orders/<12 hex digits>/profile` (1.77 M characters) need 890,298 nodes in a plain trie and 66,314 in a radix trie. That's under 2 per key, as the bound predicts. The unique 12-character IDs and the shared `/profile` suffix are exactly what a plain trie can't share.
* **The first version of the radix trie had a counting bug, found by the oracle.** `countWithPrefix` disagreed with a `TreeSet` 2,197 times out of 40,000. The pre-insert pass incremented the count of an edge that the insert then **split**, and the split copied that count to both halves. The fix is one line plus a comment, but without the oracle the bug would have shipped. The routing demo also exposed a design bug in the first dataset: plain string-prefix matching sent `/api/v2/orders/99999/items` to the handler registered for `/api/v2/orders/9999`. Segment-boundary matching is now in the API.
* **Aho–Corasick:** 0 mismatches against per-pattern `indexOf`/`find` on 2,000 random pattern sets. With 2,000 patterns over a 2 M-character text it found 8.7 M matches in 24–54 ms.
* **Streaming is one integer of state.** Feeding the same text in random chunks of 1–5,000 characters, carrying only the automaton state between chunks, gives identical counts for all 2,000 patterns.
* **Sharding is a halo plus an ownership rule.** Seven shards each start `maxLen − 1 = 7` characters early from state 0 and count only matches that **end** inside their own range. The counts are identical to the single pass: each match is counted exactly once, by the shard that owns its last character.
* **XOR trie:** maximum-XOR partner and "count with `v ⊕ x < k`" match brute force on 2,000 random sets.

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads"

* **Routers and pattern automata are build-once, read-many.** Build the radix trie or the Aho–Corasick tables, publish them immutably, and serve every request thread lock-free. Route-table updates build a new trie and swap the reference atomically: copy-on-write, with no reader ever blocking. That's the model of most production HTTP routers and of high-throughput multi-pattern scanners.
* **The Aho–Corasick goto table is a dense `int[states][alphabet]`.** For a byte alphabet that's 256 ints per state, so 1 M states is 1 GB. Production engines compress it (only the root's row dense, sorted sparse transitions elsewhere, or alphabet reduction through equivalence classes) and accept a slightly slower step. Saying that is a Staff signal.
* **Concurrent inserts into a mutable trie** need per-node locks or a lock-free design (CAS on child pointers). Keyed sharding is simpler: route keys to N independent tries by first byte or hash.

### 4.2 Extension B — "the text is an endless stream"

The measured property is the answer. The automaton state is one integer, so a stream processor keeps one int per stream and per pattern set. Matches spanning chunk boundaries are found because the state carries the partial match. Memory is O(automaton), independent of stream length. The same holds for KMP (Folder 06), and it is why multi-pattern scanners can run inline on network streams.

### 4.3 Extension C — "the corpus is sharded over 100 machines"

* **Text sharded by byte range:** each shard starts `maxLen − 1` characters early and counts only matches ending in its own range: exact, as measured. Alternatively a shard can receive the **automaton state** at its start position from its predecessor, but that serializes the shards. The halo keeps them independent.
* **Patterns too many for one machine:** partition the *patterns* (by hash) and replicate the text stream to each pattern shard, or partition the text and replicate a compressed automaton. Which one to choose depends on which side is larger.
* **Routing tables across a fleet:** the radix trie is small (it scales with keys, not characters), so it is usually replicated to every edge node rather than sharded. Updates are versioned and published atomically, and in-flight requests finish on the version they started with.
* **Distributed prefix counts** (autocomplete over a sharded corpus): shard by key range so that a prefix maps to one shard, or to a few adjacent ones. Or shard by hash and fan out, summing the per-shard counts. Counts add, so that's exact.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Plain trie over long, unique keys | 10× more nodes than keys; memory blow-up | Radix trie (nodes ≤ 2 × keys) |
| F2 | String-prefix routing | `/orders` captures `/ordersXYZ` | Match at segment boundaries; test the near-miss |
| F3 | Counts not adjusted on edge split | Prefix counts wrong (2,197 / 40,000 in the first version) | Oracle (`TreeSet` / `std::set`) on random prefixes |
| F4 | Walking failure links to report matches | O(n × depth) on pattern families like `a, aa, aaa` | Output (dictionary-suffix) links |
| F5 | Dense goto table over a large alphabet | GBs of mostly-empty rows | Sparse transitions, alphabet classes, a dense root only |
| F6 | Chunked matching that resets state | Misses matches spanning chunks | Carry the automaton state; it's one int |
| F7 | Sharded text without a halo or an ownership rule | Missed or double-counted matches | Halo `maxLen − 1`; count matches ending in your range |
| F8 | Mutating a shared trie while serving | Torn reads, inconsistent routes | Build new, swap the reference (copy-on-write) |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Design the data structure behind an HTTP router."</b></summary>

**Initial Prompt.** Routes like `/api/v2/orders`, `/api/v2/orders/{id}`; find the handler for a request path.

**L5 Answer.** "A hash map from path to handler."

**Why L5 Stalls.** Exact-match maps can't answer "most specific prefix" or parameterized segments without trying every route.

**L7 Answer.** "A radix trie keyed by path. Nodes scale with routes, not characters (I measured 66k nodes vs 890k for a plain trie), and lookup is O(path length). The query is longest-prefix match, but only at segment boundaries, so `/orders` doesn't capture `/ordersXYZ`. Parameterized segments become wildcard children tried after static ones. The table is built once and published immutably, so request threads read it lock-free, and route changes swap in a new trie."
</details>

<details><summary><b>Q2 · "Find all occurrences of 10,000 banned words in a stream of messages."</b></summary>

**Initial Prompt.** Content filtering.

**L5 Answer.** "For each word, search each message."

**Why L5 Stalls.** O(words × text) per message.

**L7 Answer.** "Aho–Corasick: a trie of the words, failure links (the longest suffix that is also a trie path) and output links to the nearest pattern-ending suffix. Matching is one table lookup per character plus one step per match: O(text + matches), independent of the number of words. The automaton is immutable, so all request threads share it. And since its whole state is one int, messages that arrive in fragments are handled by carrying that int."
</details>

<details><summary><b>Q3 · "The text arrives in chunks of arbitrary size."</b></summary>

**Initial Prompt.** Extension B for multi-pattern matching.

**L5 Answer.** "Concatenate chunks into a buffer, then search."

**Why L5 Stalls.** Memory grows with the stream; matches straddling chunks need special handling.

**L7 Answer.** "Keep the automaton state between chunks: it's a single integer that already encodes the longest partial match. Process each chunk character by character from the carried state. No buffering, and matches across boundaries are found automatically. I verified that random chunk sizes from 1 to 5,000 give counts identical to a single pass."
</details>

<details><summary><b>Q4 · "Now the 10 TB corpus is split across 100 machines."</b></summary>

**Initial Prompt.** Extension C.

**L5 Answer.** "Each machine searches its part; sum the counts."

**Why L5 Stalls.** Matches crossing machine boundaries are lost, and naive overlap double-counts.

**L7 Answer.** "Each machine reads `maxLen − 1` bytes before its range, starts the automaton from state 0 there, and counts only matches that *end* inside its own range. Every match has exactly one end position, so nothing is lost or double-counted. I checked it with 7 shards against one pass. The alternative, passing the automaton state from shard to shard, is exact too but serializes the machines."
</details>

<details><summary><b>Q5 · "Count how many stored keys start with a prefix, with inserts happening."</b></summary>

**Initial Prompt.** Autocomplete counts.

**L5 Answer.** "Walk to the prefix node and count all keys below with a DFS."

**Why L5 Stalls.** O(subtree) per query: millions for a short prefix.

**L7 Answer.** "Keep a count of keys in each node's subtree, maintained on insert, so a query is O(prefix length). In a radix trie the subtle case is the edge split: the new middle node inherits the old count, which already includes the key being inserted, and the lower half must not. My first version got that wrong, and a random comparison against a sorted set caught it 2,197 times in 40,000 queries."
</details>

<details><summary><b>Q6 · "Maximum XOR of any two numbers in an array."</b></summary>

**Initial Prompt.** LeetCode 421.

**L5 Answer.** Brute force O(n²), or a bit-mask-and-hash-set trick without explanation.

**Why L5 Stalls.** No invariant stated, and it doesn't extend to "with constraints" variants.

**L7 Answer.** "Insert each number into a binary trie from the top bit. For each number, walk down preferring the opposite bit at each level. A 1 in bit b outweighs all lower bits combined, so the greedy choice is optimal: O(n × 31). With subtree counts the same walk counts values whose XOR with x is below k, and offline sorting by limit handles 'max XOR with values ≤ m' queries."
</details>

<details><summary><b>Q7 · "Your automaton has 1 M states over a byte alphabet. Memory?"</b></summary>

**Initial Prompt.** Scaling probe.

**L5 Answer.** "It's fine, it's just an array."

**Why L5 Stalls.** 1 M × 256 × 4 B = 1 GB for a dense goto table, mostly zeros.

**L7 Answer.** "A dense table is 1 GB, so I'd compress it. Keep the root's row dense, because it's the hottest. Store other states' transitions sparsely, sorted with binary search or in a small hash, and fall back to failure links on a miss. Or reduce the alphabet with equivalence classes of bytes that behave identically. That trades a few nanoseconds per character for 10–100× less memory, and I'd measure which side of that trade the workload is on."
</details>

<details><summary><b>Q8 · "Route updates arrive while requests are being served."</b></summary>

**Initial Prompt.** Extension A for the router.

**L5 Answer.** "Lock the trie during updates."

**Why L5 Stalls.** Every request contends on the lock; an update blocks all traffic.

**L7 Answer.** "Copy-on-write. Build the new trie off to the side (it's small, since nodes scale with routes) and publish it with one atomic reference swap. In-flight requests finish on the version they started with, new requests see the new one, and readers never block. For very large tables, a persistent trie that copies only the changed path makes each update O(depth)."
</details>

---

## 7. Checklist

* [ ] Choose children storage by alphabet size; compress edges when keys are long or unique.
* [ ] Longest-prefix match at segment boundaries for routes; test the near-miss.
* [ ] Subtree counts maintained on insert, including edge splits; oracle-tested.
* [ ] Aho–Corasick with output links; O(n + matches).
* [ ] Automaton state carried across chunks; halo `maxLen − 1` and the "ends in my range" rule across shards.
* [ ] Binary trie: top bit first; subtree counts for counting queries.
* [ ] Extension A: immutable build, copy-on-write publish; sparse transitions for large alphabets.
* [ ] Extension B: one int of state per stream.
* [ ] Extension C: halo + ownership for text; replicate small tries; partition patterns or text by size.

---

## 8. References

* A. V. Aho, M. J. Corasick, *Efficient String Matching: An Aid to Bibliographic Search*, CACM 18(6), 1975 — DOI 10.1145/360825.360855
* D. R. Morrison, *PATRICIA — Practical Algorithm To Retrieve Information Coded in Alphanumeric*, JACM 15(4), 1968 — DOI 10.1145/321479.321481
* V. Leis, A. Kemper, T. Neumann, *The Adaptive Radix Tree: ARTful Indexing for Main-Memory Databases*, ICDE 2013 — DOI 10.1109/ICDE.2013.6544812
* cp-algorithms: [Aho–Corasick](https://cp-algorithms.com/string/aho_corasick.html), [Trie / prefix function background](https://cp-algorithms.com/string/prefix-function.html)
* LeetCode anchors: [208 Implement Trie](https://leetcode.com/problems/implement-trie-prefix-tree/), [421 Maximum XOR of Two Numbers](https://leetcode.com/problems/maximum-xor-of-two-numbers-in-an-array/), [1707 Maximum XOR With an Element From Array](https://leetcode.com/problems/maximum-xor-with-an-element-from-array/), [1032 Stream of Characters](https://leetcode.com/problems/stream-of-characters/)

*Folder 03:* [01 — LCA, Euler tour, HLD](01-binary-lifting-lca-euler-tour-flattening-and-heavy-light-decomposition.md) · [02 — Fenwick, lazy and sparse segment trees](02-fenwick-bit-and-lazy-segment-trees-with-sparse-dynamic-nodes.md)
