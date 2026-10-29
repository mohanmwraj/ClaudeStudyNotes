# KMP, Prefix Automaton, Z-Algorithm, Manacher and Rabin–Karp with Strong Hashing

> **Folder 06 · File 1 of 2** — linear-time string matching from one idea (reuse what you already know about the string), a matcher whose state is one integer, and why the contest favourite hash (natural 2⁶⁴ overflow) is broken by a 2,048-character string for **every** odd base.
> **Languages:** Java 21 (`--release 21 -Xlint:all -Werror`, JDK 25.0.4.1) and C++23 (GCC 16.2 and Clang 21.1, `-O2`, warnings as errors).

| Listing | File | What it proves |
|---|---|---|
| 6.1 | `StringAlgos.java` | Prefix function, streaming KMP (identical matches under random chunking), Z-function, Manacher, Rabin–Karp mod 2⁶¹−1 with verification, all against brute force. Thue–Morse collides for 5 of 5 bases under 2⁶⁴ overflow and not under mod 2⁶¹−1. Content-defined chunking keeps 99.6% reuse after a 1-byte insert vs 0% for fixed chunks |
| 6.2 | `string_algos.cpp` | The same, with a pedantic-clean 128-bit `mul_mod`; identical results |

**Verification.** Both listings were extracted from this file, compiled and run. Everything is **Output (verified)**: fully deterministic, identical between Java and both C++ builds apart from number formatting.

---

## 0. Orientation

| Contest habit | What breaks | L7 replacement |
|---|---|---|
| `unsigned long long` hash with natural overflow | Thue–Morse strings of length 2,048 collide for **any** odd base; adversarial input breaks a service | Mod 2⁶¹−1 with a **random** base per process; verify every hash hit |
| Hash-only equality | False positives are wrong answers, silently | Las Vegas: a hash match is a candidate; compare bytes to confirm |
| Fixed base 131 / 31 | An attacker can precompute collisions | Base drawn from OS entropy at start-up (the listings use a fixed seed for reproducibility) |
| Load the whole text, then search | Doesn't stream | KMP / Aho–Corasick state is one integer: carry it between chunks |
| Fixed-size chunks for deduplication | One inserted byte shifts every boundary: 0% reuse | Content-defined chunking: boundaries where a rolling hash of the content hits a pattern |

---

## 1. First principles

### 1.1 The prefix function and KMP

`π[i]` is the length of the longest proper **border** of `s[0..i]`: a prefix that is also a suffix. Matching pattern p against a text keeps `k`, the length of the current partial match. On a mismatch, instead of restarting, it falls back to `π[k − 1]`, the longest shorter prefix of p that still matches the text's suffix. Each text character advances k by at most one, and every fallback decreases k, so the total work is O(n + m). **The state between text characters is the single integer k**, which is why KMP is a streaming algorithm (and an automaton over the alphabet once the transitions are tabulated).

### 1.2 Z-function

`z[i]` is the length of the longest common prefix of s and `s[i..]`. Keep the rightmost segment `[l, r)` that matched a prefix of s. For i inside it, `z[i]` is at least `min(r − i, z[i − l])`, so extend only past r. Each extension moves r right, which makes it O(n). Searching `p + '#' + text` turns pattern matching into "z[i] ≥ |p|".

### 1.3 Manacher

To find every maximal palindrome in O(n), interleave separators (`|a|b|a|`) so that even and odd palindromes become odd. Keep the rightmost palindrome `[l, r]` found so far. A centre i inside it mirrors to `l + r − i`, whose radius is a lower bound (capped at r). Extend only beyond r. The same "reuse the box" idea as Z.

### 1.4 Polynomial hashing and why 2⁶⁴ fails

`H(s) = Σ s[i] · B^{n−1−i} mod M`. Two different strings collide when `Σ (s[i] − t[i]) · B^{n−1−i} ≡ 0 (mod M)`.

* **M = 2⁶⁴ (natural overflow):** take the Thue–Morse string S of length 2ᵏ and its complement S'. The difference polynomial factors as `±Π_{i<k} (B^{2ⁱ} − 1)`. For odd B each factor is even, and `B^{2ⁱ} − 1` is divisible by `2^{i+1}`, so the product is divisible by `2^{k(k+1)/2}`. At k = 11 that's 2⁶⁶: **zero mod 2⁶⁴ for every odd base.** (Even bases fail faster still.) The listing confirms it for 31, 131, 1,000,003, the golden-ratio constant and a random odd 64-bit base. A hash-only matcher then reports five matches where one exists.
* **M = 2⁶¹ − 1 (a Mersenne prime) with a random base:** for two fixed different strings of length n, the difference polynomial has at most n roots, so `P(collision) ≤ n / (2⁶¹ − 1)` over the random choice of base. That's about 10⁻¹⁵ for n = 2,048, independent of how the input was chosen, *provided the attacker can't see the base*. The Mersenne modulus makes the multiplication a 128-bit product plus two shift-and-add reductions: about as fast as overflow hashing.
* **"Double hashing"** (two moduli near 10⁹) is the contest fix. It works, but it is two computations for about 60 bits of security; one 61-bit Mersenne modulus is simpler and stronger.

Whatever the hash, **production code verifies**: a hash hit is a candidate, and a byte comparison confirms it. Correctness never depends on luck, and the hash only buys speed (a Las Vegas algorithm).

### 1.5 Rolling hashes beyond matching: content-defined chunking

Deduplicating storage and sync systems split files into chunks and store each distinct chunk once. With **fixed-size** chunks, inserting one byte shifts every later boundary, so no chunk matches the old version. **Content-defined chunking** places a boundary wherever a rolling hash of the last w bytes satisfies a condition (here: the top 12 bits of a Gear hash are zero, for about 4 KiB average), with minimum and maximum sizes. Boundaries depend on *local content*, so an insertion changes only the chunk it lands in. The listing measures **99.6% of bytes reused** after a one-byte insert, against **0%** for fixed 4 KiB chunks. That is why rsync-like tools, backup systems and content-addressed stores use rolling hashes, and it's the natural Extension B/C story for this file.

---

## 2. The listings

### 2.1 Listing 6.1 — Java

```java
// StringAlgos.java - prefix function / KMP stream, Z, Manacher, rolling hashes that survive adversaries, content-defined chunking.
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public final class StringAlgos {

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
        String word(int maxLen, int alphabet) {
            StringBuilder sb = new StringBuilder();
            for (int i = nextInt(maxLen + 1); i > 0; i--) sb.append((char) ('a' + nextInt(alphabet)));
            return sb.toString();
        }
    }

    // ===================================================================== 1. prefix function, KMP as a stream
    /** pi[i] = length of the longest proper border (prefix that is also a suffix) of s[0..i]. O(n) amortized. */
    static int[] prefixFunction(String s) {
        int[] pi = new int[s.length()];
        for (int i = 1, k = 0; i < s.length(); i++) {
            while (k > 0 && s.charAt(i) != s.charAt(k)) k = pi[k - 1];
            if (s.charAt(i) == s.charAt(k)) k++;
            pi[i] = k;
        }
        return pi;
    }

    /** KMP matcher whose whole state between characters is one int: feed it any chunking of the text. */
    static final class KmpStream {
        private final String p;
        private final int[] pi;
        private int k;
        private long pos;
        final List<Long> matches = new ArrayList<>();

        KmpStream(String pattern) {
            if (pattern.isEmpty()) throw new IllegalArgumentException("empty pattern");
            p = pattern;
            pi = prefixFunction(pattern);
        }

        void feed(CharSequence chunk) {
            for (int i = 0; i < chunk.length(); i++, pos++) {
                char c = chunk.charAt(i);
                while (k > 0 && c != p.charAt(k)) k = pi[k - 1];
                if (c == p.charAt(k)) k++;
                if (k == p.length()) { matches.add(pos - p.length() + 1); k = pi[k - 1]; }
            }
        }
    }

    // ===================================================================== 2. Z-function and Manacher
    /** z[i] = length of the longest common prefix of s and s[i..]. The [l, r) box reuses earlier work: O(n). */
    static int[] zFunction(String s) {
        int n = s.length();
        int[] z = new int[n];
        for (int i = 1, l = 0, r = 0; i < n; i++) {
            if (i < r) z[i] = Math.min(r - i, z[i - l]);
            while (i + z[i] < n && s.charAt(z[i]) == s.charAt(i + z[i])) z[i]++;
            if (i + z[i] > r) { l = i; r = i + z[i]; }
        }
        if (n > 0) z[0] = n;
        return z;
    }

    /** d[c] over the string with separators: radius of the longest palindrome centred at c, all centres in O(n). */
    static int longestPalindrome(String s) {
        StringBuilder t = new StringBuilder("|");
        for (char c : s.toCharArray()) t.append(c).append('|');
        int n = t.length(), best = 0;
        int[] d = new int[n];
        for (int i = 0, l = 0, r = -1; i < n; i++) {
            int k = i > r ? 1 : Math.min(d[l + r - i], r - i + 1);
            while (i - k >= 0 && i + k < n && t.charAt(i - k) == t.charAt(i + k)) k++;
            d[i] = k;
            if (i + k - 1 > r) { l = i - k + 1; r = i + k - 1; }
            best = Math.max(best, k - 1);  // radius in the separated string == length in the original
        }
        return best;
    }

    static int longestPalindromeBrute(String s) {
        int best = 0;
        for (int i = 0; i < s.length(); i++)
            for (int j = i; j < s.length(); j++) {
                boolean pal = true;
                for (int a = i, b = j; a < b && pal; a++, b--) pal = s.charAt(a) == s.charAt(b);
                if (pal) best = Math.max(best, j - i + 1);
            }
        return best;
    }

    // ===================================================================== 3. rolling hashes
    /** Contest habit: polynomial hash with natural 2^64 overflow. Fast; and broken by Thue-Morse for EVERY odd base. */
    static long hash64(CharSequence s, long base) {
        long h = 0;
        for (int i = 0; i < s.length(); i++) h = h * base + s.charAt(i);
        return h;
    }

    static final long MOD = (1L << 61) - 1;

    /** a * b mod 2^61 - 1 via the 128-bit product: the Mersenne modulus makes the reduction two shifts and an add. */
    static long mulMod(long a, long b) {
        long hi = Math.multiplyHigh(a, b), lo = a * b;
        long r = (lo & MOD) + ((lo >>> 61) | (hi << 3));
        r = (r & MOD) + (r >>> 61);
        return r >= MOD ? r - MOD : r;
    }

    /** Rolling hash mod 2^61 - 1 with a RANDOM base: collision probability <= n / 2^61 for any fixed input. */
    static final class RollingHash {
        private final long[] prefix, pow;

        RollingHash(CharSequence s, long base) {
            prefix = new long[s.length() + 1];
            pow = new long[s.length() + 1];
            pow[0] = 1;
            for (int i = 0; i < s.length(); i++) {
                prefix[i + 1] = (mulMod(prefix[i], base) + s.charAt(i)) % MOD;
                pow[i + 1] = mulMod(pow[i], base);
            }
        }

        long of(int from, int to) {  // hash of s[from, to)
            long h = prefix[to] - mulMod(prefix[from], pow[to - from]);
            return h < 0 ? h + MOD : h;
        }
    }

    /** Rabin-Karp with verification on every hash hit: a Las Vegas algorithm, always correct, fast when hashes are good. */
    static List<Integer> rabinKarp(String text, String pat, long base, boolean verify, int[] falseHits) {
        List<Integer> out = new ArrayList<>();
        if (pat.length() > text.length()) return out;
        RollingHash ht = new RollingHash(text, base), hp = new RollingHash(pat, base);
        long target = hp.of(0, pat.length());
        for (int i = 0; i + pat.length() <= text.length(); i++) {
            if (ht.of(i, i + pat.length()) != target) continue;
            if (verify && !text.regionMatches(i, pat, 0, pat.length())) { falseHits[0]++; continue; }
            out.add(i);
        }
        return out;
    }

    static String thueMorse(int n, boolean complement) {
        StringBuilder sb = new StringBuilder(n);
        for (int i = 0; i < n; i++) sb.append((Integer.bitCount(i) & 1) == (complement ? 0 : 1) ? 'b' : 'a');
        return sb.toString();
    }

    static List<Integer> naiveFind(String text, String pat) {
        List<Integer> out = new ArrayList<>();
        for (int i = text.indexOf(pat); i >= 0; i = text.indexOf(pat, i + 1)) out.add(i);
        return out;
    }

    // ===================================================================== Extension B/C: content-defined chunking
    /** Chunk boundary where the rolling Gear hash has its top 12 bits zero (~4 KiB average), within [1 KiB, 16 KiB]. */
    static List<int[]> cdcChunks(byte[] data, long[] gear) {
        List<int[]> out = new ArrayList<>();
        int start = 0;
        long h = 0;
        for (int i = 0; i < data.length; i++) {
            h = (h << 1) + gear[data[i] & 0xFF];                  // window = the last 64 bytes, implicitly
            int len = i - start + 1;
            if ((len >= 1_024 && (h >>> 52) == 0) || len == 16_384 || i == data.length - 1) {
                out.add(new int[] {start, i + 1});
                start = i + 1;
                h = 0;
            }
        }
        return out;
    }

    static List<int[]> fixedChunks(byte[] data, int size) {
        List<int[]> out = new ArrayList<>();
        for (int s = 0; s < data.length; s += size) out.add(new int[] {s, Math.min(data.length, s + size)});
        return out;
    }

    static long chunkId(byte[] d, int[] c) {
        long h = 0;
        for (int i = c[0]; i < c[1]; i++) h = (mulMod(h, 1_000_003) + (d[i] & 0xFF) + 1) % MOD;
        return h ^ ((long) (c[1] - c[0]) << 40);
    }

    static double reuse(byte[] oldD, List<int[]> oldC, byte[] newD, List<int[]> newC) {
        Set<Long> have = new HashSet<>();
        for (int[] c : oldC) have.add(chunkId(oldD, c));
        long reusedBytes = 0;
        for (int[] c : newC) if (have.contains(chunkId(newD, c))) reusedBytes += c[1] - c[0];
        return 100.0 * reusedBytes / newD.length;
    }

    public static void main(String[] args) {
        SplitMix64 r = new SplitMix64(141);
        int trials = 3_000, okKmp = 0, okZ = 0, okPal = 0, okRk = 0, okStream = 0;
        long base = (r.next() >>> 4) % (MOD - 256) + 256;  // production: seed from OS entropy, per process
        for (int t = 0; t < trials; t++) {
            String text = r.word(40, 2), pat = "a" + r.word(4, 2);
            List<Integer> want = naiveFind(text, pat);
            KmpStream whole = new KmpStream(pat);
            whole.feed(text);
            okKmp += whole.matches.stream().map(Long::intValue).toList().equals(want) ? 1 : 0;
            KmpStream chunked = new KmpStream(pat);
            for (int i = 0; i < text.length(); ) { int len = 1 + r.nextInt(7); chunked.feed(text.substring(i, Math.min(text.length(), i + len))); i += len; }
            okStream += chunked.matches.equals(whole.matches) ? 1 : 0;
            int[] z = zFunction(pat + "#" + text);
            List<Integer> viaZ = new ArrayList<>();
            for (int i = pat.length() + 1; i < z.length; i++) if (z[i] >= pat.length()) viaZ.add(i - pat.length() - 1);
            okZ += viaZ.equals(want) ? 1 : 0;
            okPal += longestPalindrome(text) == longestPalindromeBrute(text) ? 1 : 0;
            okRk += rabinKarp(text, pat, base, true, new int[1]).equals(want) ? 1 : 0;
        }
        System.out.printf("random binary texts (%,d) vs indexOf / brute force:%n", trials);
        System.out.printf("   KMP %d/%d | same matches when fed in random 1..7-char chunks %d/%d | Z-function %d/%d | Manacher %d/%d |"
                + " Rabin-Karp mod 2^61-1 %d/%d%n", okKmp, trials, okStream, trials, okZ, trials, okPal, trials, okRk, trials);

        String s = thueMorse(2_048, false), tbar = thueMorse(2_048, true);
        System.out.println("Thue-Morse attack, |S| = |S'| = 2,048, S != S':");
        for (long b : new long[] {31, 131, 1_000_003, 0x9E3779B97F4A7C15L | 1, (r.next() | 1)}) {
            System.out.printf("   2^64-overflow hash, base %-20s : hash(S) == hash(S')? %b%n", Long.toUnsignedString(b), hash64(s, b) == hash64(tbar, b));
        }
        RollingHash h1 = new RollingHash(s, base), h2 = new RollingHash(tbar, base);
        System.out.printf("   mod 2^61-1, random base                        : hash(S) == hash(S')? %b%n", h1.of(0, 2_048) == h2.of(0, 2_048));
        String text = s + tbar + s;
        int[] falseHits = new int[1];
        List<Integer> noVerify = new ArrayList<>();
        long target = hash64(tbar, 131);
        for (int i = 0; i + 2_048 <= text.length(); i++) if (hash64(text.substring(i, i + 2_048), 131) == target) noVerify.add(i);
        System.out.printf("   searching S' in S+S'+S: hash-only 2^64 matcher reports %s | true matches %s | verified mod-2^61-1 matcher %s (%d false hits)%n",
                noVerify, naiveFind(text, tbar), rabinKarp(text, tbar, base, true, falseHits), falseHits[0]);

        byte[] data = new byte[2_000_000];
        for (int i = 0; i < data.length; i++) data[i] = (byte) r.next();
        long[] gear = new long[256];
        for (int i = 0; i < 256; i++) gear[i] = r.next();
        byte[] edited = new byte[data.length + 1];                  // insert ONE byte near the front
        System.arraycopy(data, 0, edited, 0, 100);
        edited[100] = 42;
        System.arraycopy(data, 100, edited, 101, data.length - 100);
        List<int[]> oldCdc = cdcChunks(data, gear), newCdc = cdcChunks(edited, gear);
        System.out.printf("B/C. dedup after inserting 1 byte at offset 100 of 2,000,000: fixed 4 KiB chunks reuse %.1f%% of bytes |"
                + " content-defined chunks (%,d chunks, avg %,d B) reuse %.1f%%%n",
                reuse(data, fixedChunks(data, 4_096), edited, fixedChunks(edited, 4_096)), oldCdc.size(), data.length / oldCdc.size(),
                reuse(data, oldCdc, edited, newCdc));
    }
}
```

**Output (verified):**

```text
random binary texts (3,000) vs indexOf / brute force:
   KMP 3000/3000 | same matches when fed in random 1..7-char chunks 3000/3000 | Z-function 3000/3000 | Manacher 3000/3000 | Rabin-Karp mod 2^61-1 3000/3000
Thue-Morse attack, |S| = |S'| = 2,048, S != S':
   2^64-overflow hash, base 31                   : hash(S) == hash(S')? true
   2^64-overflow hash, base 131                  : hash(S) == hash(S')? true
   2^64-overflow hash, base 1000003              : hash(S) == hash(S')? true
   2^64-overflow hash, base 11400714819323198485 : hash(S) == hash(S')? true
   2^64-overflow hash, base 16826346834226493747 : hash(S) == hash(S')? true
   mod 2^61-1, random base                        : hash(S) == hash(S')? false
   searching S' in S+S'+S: hash-only 2^64 matcher reports [0, 1024, 2048, 3072, 4096] | true matches [2048] | verified mod-2^61-1 matcher [2048] (0 false hits)
B/C. dedup after inserting 1 byte at offset 100 of 2,000,000: fixed 4 KiB chunks reuse 0.0% of bytes | content-defined chunks (397 chunks, avg 5,037 B) reuse 99.6%
```

### 2.2 Listing 6.2 — C++23

```cpp
// string_algos.cpp - prefix function / KMP stream, Z, Manacher, rolling hashes that survive adversaries, content-defined chunking.
#include <algorithm>
#include <bit>
#include <cstdint>
#include <format>
#include <print>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_set>
#include <vector>

using u64 = std::uint64_t;
__extension__ typedef unsigned __int128 u128;  // GCC/Clang extension; __extension__ keeps -Wpedantic quiet
using Vec = std::vector<int>;

struct SplitMix64 {
    u64 state;
    u64 next() noexcept {
        u64 z = (state += 0x9E3779B97F4A7C15ULL);
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }
    int next_int(int bound) noexcept { return static_cast<int>(next() % static_cast<u64>(bound)); }
    std::string word(int max_len, int alphabet) {
        std::string s;
        for (int i = next_int(max_len + 1); i > 0; --i) s += static_cast<char>('a' + next_int(alphabet));
        return s;
    }
};

// ======================================================================= 1. prefix function, KMP as a stream
std::vector<std::size_t> prefix_function(std::string_view s) {
    std::vector<std::size_t> pi(s.size());
    for (std::size_t i = 1, k = 0; i < s.size(); ++i) {
        while (k > 0 && s[i] != s[k]) k = pi[k - 1];
        if (s[i] == s[k]) ++k;
        pi[i] = k;
    }
    return pi;
}

// KMP matcher whose whole state between characters is one integer: feed it any chunking of the text.
class KmpStream {
public:
    explicit KmpStream(std::string pattern) : p_(std::move(pattern)), pi_(prefix_function(p_)) {
        if (p_.empty()) throw std::invalid_argument("empty pattern");
    }
    void feed(std::string_view chunk) {
        for (char c : chunk) {
            while (k_ > 0 && c != p_[k_]) k_ = pi_[k_ - 1];
            if (c == p_[k_]) ++k_;
            if (k_ == p_.size()) matches.push_back(pos_ + 1 - p_.size()), k_ = pi_[k_ - 1];
            ++pos_;
        }
    }
    std::vector<std::size_t> matches;

private:
    std::string p_;
    std::vector<std::size_t> pi_;
    std::size_t k_ = 0, pos_ = 0;
};

// ======================================================================= 2. Z-function and Manacher
std::vector<std::size_t> z_function(std::string_view s) {
    std::size_t n = s.size();
    std::vector<std::size_t> z(n);
    for (std::size_t i = 1, l = 0, r = 0; i < n; ++i) {
        if (i < r) z[i] = std::min(r - i, z[i - l]);
        while (i + z[i] < n && s[z[i]] == s[i + z[i]]) ++z[i];
        if (i + z[i] > r) l = i, r = i + z[i];
    }
    if (n > 0) z[0] = n;
    return z;
}

std::size_t longest_palindrome(std::string_view s) {
    std::string t = "|";
    for (char c : s) t += c, t += '|';
    std::size_t n = t.size(), best = 0;
    std::vector<std::size_t> d(n);
    for (std::size_t i = 0, l = 0, r = 0; i < n; ++i) {  // [l, r] = rightmost palindrome found so far (r exclusive-1)
        std::size_t k = i >= r ? 1 : std::min(d[l + r - 1 - i], r - i);
        while (k <= i && i + k < n && t[i - k] == t[i + k]) ++k;
        d[i] = k;
        if (i + k > r) l = i + 1 - k, r = i + k;
        best = std::max(best, k - 1);
    }
    return best;
}

std::size_t longest_palindrome_brute(std::string_view s) {
    std::size_t best = 0;
    for (std::size_t i = 0; i < s.size(); ++i)
        for (std::size_t j = i; j < s.size(); ++j) {
            bool pal = true;
            for (std::size_t a = i, b = j; a < b && pal; ++a, --b) pal = s[a] == s[b];
            if (pal) best = std::max(best, j - i + 1);
        }
    return best;
}

// ======================================================================= 3. rolling hashes
u64 hash64(std::string_view s, u64 base) {  // natural 2^64 overflow: unsigned, so defined -- and broken by Thue-Morse
    u64 h = 0;
    for (char c : s) h = h * base + static_cast<unsigned char>(c);
    return h;
}

constexpr u64 kMod = (u64{1} << 61) - 1;
u64 mul_mod(u64 a, u64 b) {  // the Mersenne modulus makes the reduction two shifts and an add
    u128 p = static_cast<u128>(a) * b;
    u64 r = (static_cast<u64>(p) & kMod) + static_cast<u64>(p >> 61);
    r = (r & kMod) + (r >> 61);
    return r >= kMod ? r - kMod : r;
}

class RollingHash {  // mod 2^61 - 1 with a RANDOM base: collision probability <= n / 2^61 for any fixed input
public:
    RollingHash(std::string_view s, u64 base) : prefix_(s.size() + 1), pow_(s.size() + 1) {
        pow_[0] = 1;
        for (std::size_t i = 0; i < s.size(); ++i) {
            prefix_[i + 1] = (mul_mod(prefix_[i], base) + static_cast<unsigned char>(s[i])) % kMod;
            pow_[i + 1] = mul_mod(pow_[i], base);
        }
    }
    u64 of(std::size_t from, std::size_t to) const {
        u64 sub = mul_mod(prefix_[from], pow_[to - from]);
        return prefix_[to] >= sub ? prefix_[to] - sub : prefix_[to] + kMod - sub;
    }

private:
    std::vector<u64> prefix_, pow_;
};

// Rabin-Karp with verification on every hash hit: Las Vegas -- always correct, fast when hashes are good.
std::vector<std::size_t> rabin_karp(std::string_view text, std::string_view pat, u64 base, int& false_hits) {
    std::vector<std::size_t> out;
    if (pat.size() > text.size()) return out;
    RollingHash ht(text, base), hp(pat, base);
    u64 target = hp.of(0, pat.size());
    for (std::size_t i = 0; i + pat.size() <= text.size(); ++i) {
        if (ht.of(i, i + pat.size()) != target) continue;
        if (text.substr(i, pat.size()) != pat) {
            ++false_hits;
            continue;
        }
        out.push_back(i);
    }
    return out;
}

std::string thue_morse(std::size_t n, bool complement) {
    std::string s(n, 'a');
    for (std::size_t i = 0; i < n; ++i) s[i] = (std::popcount(i) & 1) == (complement ? 0 : 1) ? 'b' : 'a';
    return s;
}

std::vector<std::size_t> naive_find(std::string_view text, std::string_view pat) {
    std::vector<std::size_t> out;
    for (auto i = text.find(pat); i != std::string_view::npos; i = text.find(pat, i + 1)) out.push_back(i);
    return out;
}

std::string show(const std::vector<std::size_t>& v) {
    std::string s = "[";
    for (std::size_t i = 0; i < v.size(); ++i) s += std::format("{}{}", i ? ", " : "", v[i]);
    return s + "]";
}

// ======================================================================= Extension B/C: content-defined chunking
struct Chunk {
    std::size_t begin, end;
};
// Boundary where the rolling Gear hash has its top 12 bits zero (~4 KiB average), within [1 KiB, 16 KiB].
std::vector<Chunk> cdc_chunks(const std::vector<std::uint8_t>& data, const std::vector<u64>& gear) {
    std::vector<Chunk> out;
    std::size_t start = 0;
    u64 h = 0;
    for (std::size_t i = 0; i < data.size(); ++i) {
        h = (h << 1) + gear[data[i]];  // the window is the last 64 bytes, implicitly
        std::size_t len = i - start + 1;
        if ((len >= 1'024 && (h >> 52) == 0) || len == 16'384 || i + 1 == data.size()) out.push_back({start, i + 1}), start = i + 1, h = 0;
    }
    return out;
}
std::vector<Chunk> fixed_chunks(std::size_t n, std::size_t size) {
    std::vector<Chunk> out;
    for (std::size_t s = 0; s < n; s += size) out.push_back({s, std::min(n, s + size)});
    return out;
}
u64 chunk_id(const std::vector<std::uint8_t>& d, Chunk c) {
    u64 h = 0;
    for (std::size_t i = c.begin; i < c.end; ++i) h = (mul_mod(h, 1'000'003) + d[i] + 1) % kMod;
    return h ^ (static_cast<u64>(c.end - c.begin) << 40);
}
double reuse(const std::vector<std::uint8_t>& old_d, const std::vector<Chunk>& old_c, const std::vector<std::uint8_t>& new_d,
             const std::vector<Chunk>& new_c) {
    std::unordered_set<u64> have;
    for (Chunk c : old_c) have.insert(chunk_id(old_d, c));
    std::size_t reused = 0;
    for (Chunk c : new_c)
        if (have.contains(chunk_id(new_d, c))) reused += c.end - c.begin;
    return 100.0 * static_cast<double>(reused) / static_cast<double>(new_d.size());
}

int main() {
    SplitMix64 r{141};
    constexpr int trials = 3'000;
    int ok_kmp = 0, ok_z = 0, ok_pal = 0, ok_rk = 0, ok_stream = 0;
    u64 base = (r.next() >> 4) % (kMod - 256) + 256;  // production: seed from OS entropy, per process
    for (int t = 0; t < trials; ++t) {
        std::string text = r.word(40, 2);
        std::string pat = "a" + r.word(4, 2);
        auto want = naive_find(text, pat);
        KmpStream whole(pat);
        whole.feed(text);
        ok_kmp += whole.matches == want;
        KmpStream chunked(pat);
        for (std::size_t i = 0; i < text.size();) {
            auto len = static_cast<std::size_t>(1 + r.next_int(7));
            chunked.feed(std::string_view(text).substr(i, len));
            i += len;
        }
        ok_stream += chunked.matches == whole.matches;
        auto z = z_function(pat + "#" + text);
        std::vector<std::size_t> via_z;
        for (std::size_t i = pat.size() + 1; i < z.size(); ++i)
            if (z[i] >= pat.size()) via_z.push_back(i - pat.size() - 1);
        ok_z += via_z == want;
        ok_pal += longest_palindrome(text) == longest_palindrome_brute(text);
        int fh = 0;
        ok_rk += rabin_karp(text, pat, base, fh) == want;
    }
    std::println("random binary texts ({}) vs find / brute force:", trials);
    std::println("   KMP {}/{} | same matches when fed in random 1..7-char chunks {}/{} | Z-function {}/{} | Manacher {}/{} |"
                 " Rabin-Karp mod 2^61-1 {}/{}", ok_kmp, trials, ok_stream, trials, ok_z, trials, ok_pal, trials, ok_rk, trials);

    std::string s = thue_morse(2'048, false), tbar = thue_morse(2'048, true);
    std::println("Thue-Morse attack, |S| = |S'| = 2,048, S != S':");
    for (u64 b : {u64{31}, u64{131}, u64{1'000'003}, 0x9E3779B97F4A7C15ULL | 1, r.next() | 1})
        std::println("   2^64-overflow hash, base {:<20} : hash(S) == hash(S')? {}", b, hash64(s, b) == hash64(tbar, b));
    std::println("   mod 2^61-1, random base                        : hash(S) == hash(S')? {}",
                 RollingHash(s, base).of(0, 2'048) == RollingHash(tbar, base).of(0, 2'048));
    std::string text = s + tbar + s;
    std::vector<std::size_t> no_verify;
    u64 target = hash64(tbar, 131);
    for (std::size_t i = 0; i + 2'048 <= text.size(); ++i)
        if (hash64(std::string_view(text).substr(i, 2'048), 131) == target) no_verify.push_back(i);
    int false_hits = 0;
    auto verified = rabin_karp(text, tbar, base, false_hits);
    std::println("   searching S' in S+S'+S: hash-only 2^64 matcher reports {} | true matches {} | verified mod-2^61-1 matcher {} ({} false hits)",
                 show(no_verify), show(naive_find(text, tbar)), show(verified), false_hits);

    std::vector<std::uint8_t> data(2'000'000);
    for (auto& b : data) b = static_cast<std::uint8_t>(r.next());
    std::vector<u64> gear(256);
    for (auto& g : gear) g = r.next();
    std::vector<std::uint8_t> edited;  // insert ONE byte near the front
    edited.reserve(data.size() + 1);   // (reserve first: GCC 16 -O2 reports a false -Warray-bounds on the grow path)
    edited.insert(edited.end(), data.begin(), data.begin() + 100);
    edited.push_back(42);
    edited.insert(edited.end(), data.begin() + 100, data.end());
    auto old_cdc = cdc_chunks(data, gear), new_cdc = cdc_chunks(edited, gear);
    std::println("B/C. dedup after inserting 1 byte at offset 100 of 2,000,000: fixed 4 KiB chunks reuse {:.1f}% of bytes |"
                 " content-defined chunks ({} chunks, avg {} B) reuse {:.1f}%",
                 reuse(data, fixed_chunks(data.size(), 4'096), edited, fixed_chunks(edited.size(), 4'096)), old_cdc.size(),
                 data.size() / old_cdc.size(), reuse(data, old_cdc, edited, new_cdc));
}
```

**Output, both compilers (verified; GCC shown, Clang identical):**

```text
random binary texts (3000) vs find / brute force:
   KMP 3000/3000 | same matches when fed in random 1..7-char chunks 3000/3000 | Z-function 3000/3000 | Manacher 3000/3000 | Rabin-Karp mod 2^61-1 3000/3000
Thue-Morse attack, |S| = |S'| = 2,048, S != S':
   2^64-overflow hash, base 31                   : hash(S) == hash(S')? true
   2^64-overflow hash, base 131                  : hash(S) == hash(S')? true
   2^64-overflow hash, base 1000003              : hash(S) == hash(S')? true
   2^64-overflow hash, base 11400714819323198485 : hash(S) == hash(S')? true
   2^64-overflow hash, base 16826346834226493747 : hash(S) == hash(S')? true
   mod 2^61-1, random base                        : hash(S) == hash(S')? false
   searching S' in S+S'+S: hash-only 2^64 matcher reports [0, 1024, 2048, 3072, 4096] | true matches [2048] | verified mod-2^61-1 matcher [2048] (0 false hits)
B/C. dedup after inserting 1 byte at offset 100 of 2,000,000: fixed 4 KiB chunks reuse 0.0% of bytes | content-defined chunks (397 chunks, avg 5037 B) reuse 99.6%
```

---

## 3. What the results show

* **KMP, Z, Manacher and verified Rabin–Karp** agree with brute force on 3,000 random binary texts (small alphabets maximize repeated structure, which is where these algorithms' fallbacks get exercised). KMP fed in random chunks of 1–7 characters produces identical matches: one integer of carried state.
* **Thue–Morse breaks natural-overflow hashing for every base tried, including random odd 64-bit ones,** exactly as the 2-adic argument predicts. The mod 2⁶¹−1 hash with a random base separates the two strings. The hash-only matcher reports `[0, 1024, 2048, 3072, 4096]`; the truth is `[2048]`.
* **Content-defined chunking:** 397 chunks averaging about 5 KiB. One inserted byte left 99.6% of the bytes in chunks already stored; fixed chunks kept 0%.
* **A toolchain note from the C++ build:** GCC 16 at `-O2` raised a `-Warray-bounds` error on `push_back` after a 100-byte range construction, which inlining analysis wrongly flagged. Reserving capacity first sidesteps the false positive, and the comment in the listing records why.

---

## 4. The last 10 minutes: Extensions A, B and C

### 4.1 Extension A — "64 threads search a huge text"

* **Split the text into chunks with a halo of `|p| − 1`** and count only matches that start (or end) in a thread's own range. That's the same ownership rule as Folder 03's Aho–Corasick shards. Matching is read-only over an immutable pattern table, so there's no synchronization except the final merge of match lists.
* **Rolling hashes parallelize** because prefix hashes compose: `H(a·b) = H(a) · B^{|b|} + H(b)`. Each thread computes its chunk's hash and the chunks combine in order. That's a parallel prefix scan over a monoid, as in Folder 02.
* **Per-process random base, shared by all threads**: the base is part of the immutable configuration, so threads must agree on it or their hashes won't compare.

### 4.2 Extension B — "the text is an endless stream"

* **KMP:** one integer of state (measured with random chunking). **Rolling-hash windows:** O(window) memory to subtract the outgoing character. **Aho–Corasick** for many patterns: one integer of state (Folder 03).
* **Content-defined chunking is a streaming algorithm:** it decides boundaries looking only at the last w bytes. A backup agent can chunk and deduplicate a 100 TB stream with constant memory, plus the index of chunk hashes already stored.
* **Palindromes over a stream** (Manacher) need the whole string in the worst case. Say so; bound the maximum palindrome length if the product allows it.

### 4.3 Extension C — "100 machines"

* **Distributed grep:** shard the corpus by byte range with a halo (above), or shard by file. Patterns ship as one compiled automaton. Results merge by sorting (file, offset).
* **Deduplication across a fleet:** the chunk hash *is* the key in a distributed key-value store. Content-defined boundaries mean that identical content written by different machines produces identical chunks, so the store deduplicates globally without coordination. The hash must be a strong, **specified** function, a cryptographic one such as SHA-256 when collisions would mean data loss. A 61-bit polynomial hash is for matching, not for content addressing.
* **Consistency of hashing across machines:** the random base must be shared configuration (or the hash must be a fixed published function). A per-process random base is right for in-memory matching under adversarial input and wrong for anything persisted or compared across machines. That trade-off is worth saying out loud.

---

## 5. Failure modes

| # | Failure | Symptom | Prevention |
|---|---|---|---|
| F1 | Natural 2⁶⁴ overflow hash | Thue–Morse collisions for every base; adversarial inputs | Mod 2⁶¹−1, random base |
| F2 | Hash equality treated as string equality | Silent false matches | Verify every hit |
| F3 | Fixed, public base on untrusted input | Precomputed anti-hash tests | Random base from OS entropy at start-up |
| F4 | Per-process random base used in persisted keys | Data unreadable after restart; machines disagree | Fixed specified hash for anything stored or shared |
| F5 | KMP restarting on chunk boundaries | Missed matches across chunks | Carry k between chunks |
| F6 | Fixed-size chunking for dedup | One insert invalidates every later chunk | Content-defined chunking with min/max sizes |
| F7 | Polynomial hash for content addressing | Collision = silent data corruption | Cryptographic hash for identities |
| F8 | Sharded matching without a halo | Missed matches at boundaries | Halo `|p| − 1` + ownership rule |

---

## 6. Bar-raiser chains

<details><summary><b>Q1 · "Find all occurrences of a pattern in a text."</b></summary>

**Initial Prompt.** The classic.

**L5 Answer.** "Rabin–Karp with a polynomial hash" or "indexOf in a loop".

**Why L5 Stalls.** The loop is O(nm) worst case. The hash version without verification is wrong under adversarial input.

**L7 Answer.** "KMP: the prefix function gives, for each prefix of the pattern, its longest border, so on a mismatch I fall back without re-reading text. O(n + m), and the matcher's whole state is the matched length, so it works on streams. If I use Rabin–Karp, for multiple pattern lengths or 2-D search, the hash is mod 2⁶¹−1 with a random base, and every hit is verified."
</details>

<details><summary><b>Q2 · "Your hash uses unsigned overflow. Is that safe?"</b></summary>

**Initial Prompt.** The candidate used `h = h * 131 + c` on a 64-bit unsigned.

**L5 Answer.** "2⁶⁴ is huge, collisions are basically impossible."

**Why L5 Stalls.** True for random strings; false for constructed ones. Thue–Morse strings of length 2,048 collide for *every* odd base, measured for five bases including random ones.

**L7 Answer.** "Not against adversarial input. With modulus 2⁶⁴ the difference of hashes of a Thue–Morse string and its complement factors into terms divisible by 2^{k(k+1)/2}, which is zero mod 2⁶⁴ at length 2,048 regardless of base. I'd use the Mersenne prime 2⁶¹−1, where the multiplication is a 128-bit product and two shifts, with a base drawn randomly at start-up, so collision probability is at most n/2⁶¹ for any input the attacker fixes in advance. And I'd verify matches anyway."
</details>

<details><summary><b>Q3 · "Double hashing or a single 61-bit modulus?"</b></summary>

**Initial Prompt.** Probe on hash design.

**L5 Answer.** "Double hashing, it's safer."

**Why L5 Stalls.** Two moduli near 10⁹ give about 60 bits at twice the work. Without a random base, either is attackable.

**L7 Answer.** "One Mersenne modulus 2⁶¹−1: about the same security as two 30-bit moduli, one multiplication path, and a cheap reduction. What matters more is that the base is random and secret per process. And for anything persisted or compared across machines, I'd use a fixed, specified hash, cryptographic if a collision means data loss."
</details>

<details><summary><b>Q4 · "The text arrives in network packets."</b></summary>

**Initial Prompt.** Extension B.

**L5 Answer.** "Reassemble the stream, then search."

**Why L5 Stalls.** Unbounded buffering; latency waits for the end of the stream.

**L7 Answer.** "KMP's state is the current matched length, one integer per stream. I process each packet from that state and carry it to the next one, so matches spanning packet boundaries are found and memory is O(pattern). I checked that random chunkings give exactly the matches of a single pass. For many patterns, Aho–Corasick has the same one-integer state."
</details>

<details><summary><b>Q5 · "Longest palindromic substring."</b></summary>

**Initial Prompt.** LeetCode 5.

**L5 Answer.** Expand around each centre: O(n²).

**Why L5 Stalls.** Fine for 10³, slow for 10⁶.

**L7 Answer.** "Manacher, O(n). Interleave separators so every palindrome has odd length, and keep the rightmost palindrome found. A centre inside it inherits its mirror's radius, capped at the boundary, so I only extend beyond the right edge, which moves right monotonically. I'd validate against brute force on random binary strings, where palindromes are frequent."
</details>

<details><summary><b>Q6 · "Deduplicate backups of files that change slightly every day."</b></summary>

**Initial Prompt.** Extension C, storage flavour.

**L5 Answer.** "Split into 4 KB blocks and hash each block."

**Why L5 Stalls.** One inserted byte shifts every block boundary. Measured: 0% reuse after a 1-byte insert.

**L7 Answer.** "Content-defined chunking: place a boundary where a rolling hash of the last ~64 bytes matches a pattern, with min and max chunk sizes, so boundaries move with the content. An insert changes only the chunk it lands in; I measured 99.6% byte reuse after a one-byte insert. Chunks are identified by a cryptographic hash in a content-addressed store, so identical data from any machine deduplicates without coordination."
</details>

<details><summary><b>Q7 · "Search a 10 TB log on 100 machines."</b></summary>

**Initial Prompt.** Extension C.

**L5 Answer.** "Split the file in 100 parts and search each."

**Why L5 Stalls.** Matches across part boundaries are lost or double-counted.

**L7 Answer.** "Each machine reads its byte range plus a halo of pattern-length minus one bytes, and reports only matches *starting* in its own range. Every match has exactly one start, so the union is exact with no duplicates. The pattern automaton is compiled once and shipped; results merge by (file, offset)."
</details>

<details><summary><b>Q8 · "Why did you use a fixed seed for the random base in your code?"</b></summary>

**Initial Prompt.** Review of the listing.

**L5 Answer.** "For reproducibility."

**Why L5 Stalls.** Correct for a test, but it should be framed as a test seam, not production behaviour.

**L7 Answer.** "Reproducible tests need a fixed seed; production needs the base from OS entropy at start-up, otherwise the randomization buys nothing against an attacker who reads the code. I'd make the base an injected parameter: fixed in tests, secure-random in production, and never persisted."
</details>

---

## 7. Checklist

* [ ] KMP / prefix function: O(n + m); state = matched length; streams.
* [ ] Z-function and Manacher: the "reuse the box" invariant.
* [ ] Hashing: mod 2⁶¹−1, random base from entropy, verify every hit.
* [ ] Never 2⁶⁴ overflow on untrusted input.
* [ ] Persisted or shared hashes: fixed, specified, cryptographic where collisions are catastrophic.
* [ ] Extension A: halo + ownership; hash composition for parallel prefix.
* [ ] Extension B: one-integer matcher state; content-defined chunking streams.
* [ ] Extension C: halo-sharded grep; content-addressed dedup.

---

## 8. References

* D. E. Knuth, J. H. Morris, V. R. Pratt, *Fast Pattern Matching in Strings*, SIAM J. Computing 6(2), 1977 — DOI 10.1137/0206024
* R. M. Karp, M. O. Rabin, *Efficient randomized pattern-matching algorithms*, IBM J. Res. Dev. 31(2), 1987 — DOI 10.1147/rd.312.0249
* G. Manacher, *A New Linear-Time "On-Line" Algorithm for Finding the Smallest Initial Palindrome of a String*, JACM 22(3), 1975 — DOI 10.1145/321892.321896
* A. Muthitacharoen, B. Chen, D. Mazières, *A Low-bandwidth Network File System* (content-defined chunking), SOSP 2001 — DOI 10.1145/502034.502052
* W. Xia et al., *FastCDC: a Fast and Efficient Content-Defined Chunking Approach for Data Deduplication*, USENIX ATC 2016 — <https://www.usenix.org/conference/atc16/technical-sessions/presentation/xia>
* dacin21, *On the mathematics behind rolling hashes and anti-hash tests* (Codeforces; covers the Thue–Morse attack on 2⁶⁴ hashing and parameter choice) — <https://codeforces.com/topic/60786/en2>
* cp-algorithms: [Prefix function / KMP](https://cp-algorithms.com/string/prefix-function.html), [Z-function](https://cp-algorithms.com/string/z-function.html), [Manacher](https://cp-algorithms.com/string/manacher.html), [String hashing](https://cp-algorithms.com/string/string-hashing.html)
* LeetCode anchors: [28 Find the Index of the First Occurrence](https://leetcode.com/problems/find-the-index-of-the-first-occurrence-in-a-string/), [5 Longest Palindromic Substring](https://leetcode.com/problems/longest-palindromic-substring/), [214 Shortest Palindrome](https://leetcode.com/problems/shortest-palindrome/), [1044 Longest Duplicate Substring](https://leetcode.com/problems/longest-duplicate-substring/)

*Folder 06:* [02 — Bloom, Count-Min, HyperLogLog, reservoir sampling](02-bloom-filters-count-min-sketch-hyperloglog-and-reservoir-sampling.md)
