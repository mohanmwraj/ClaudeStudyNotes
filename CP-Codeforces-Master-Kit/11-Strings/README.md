# 11 — Strings

String problems on Codeforces range from "count something about substrings" at 1500 to suffix structures at 2400+. The techniques in this folder all answer one of three questions fast: **does $p$ occur in $t$ (and where, how often)?**, **how do two substrings compare?**, and **what is the structure of all substrings / all palindromes of $s$?** Interview DSA uses the lower half heavily (hashing, KMP, palindromes, tries); contests use all of it.

## First-principles overview

The naive way to compare or search is character by character, which wastes work in two ways. Every algorithm here removes one of those wastes.

1. **Comparing the same characters again and again.** Fix: compress a substring to a number. A polynomial hash makes "are these two substrings equal?" an $O(1)$ question after $O(n)$ preprocessing, and LCP becomes a binary search ([01 hashing](01-string-hashing.md)). The price is a (provably tiny, if randomised) collision probability.
2. **Forgetting what a failed comparison already told us.** When a match breaks after $k$ characters, we know those $k$ characters. The longest *border* (prefix = suffix) of what matched tells us where the next candidate match can start — that is the prefix function and KMP ([02](02-prefix-function-kmp.md)). The Z-function stores the same knowledge from the other side ("how far does $s$ match itself starting at $i$"), reusing a rightmost "Z-box" ([03](03-z-function.md)). Manacher applies the box trick to palindromes, reflecting known radii through a centre ([04](04-manacher-and-palindromes.md)).
3. **Many patterns at once.** Put the patterns in a **trie** so shared prefixes are stored once ([05](05-trie-and-binary-trie.md) — the same structure over bits answers XOR-maximisation). Add KMP's failure idea to the trie and you get **Aho–Corasick**: one pass over the text finds every pattern, and the automaton supports DP over "strings avoiding these words" ([06](06-aho-corasick.md)).
4. **All substrings at once.** A string has $\Theta(n^2)$ substrings, but they are prefixes of $n$ suffixes. Sorting the suffixes (**suffix array**) and recording adjacent LCPs (Kasai) turns distinct-substring counts, repeats and $k$-th substrings into one pass over an array ([07](07-suffix-array-and-lcp.md)). Grouping substrings by their set of end positions gives the **suffix automaton**: $\le 2n-1$ states, built online, ideal for occurrence counts and matching statistics ([08](08-suffix-automaton.md)). For palindromes, a string has at most $n$ distinct non-empty palindromes, and the **eertree** stores them all with suffix links ([09](09-palindromic-tree-eertree.md)).

Rule of thumb from strong solvers (opinion, but widely shared): reach for the **simplest deterministic linear tool** that answers the question — prefix function / Z / Manacher — and use hashing when you need arbitrary substring comparisons; reserve suffix structures for genuinely "all substrings" questions.

## Files

| File | Band | Priority | FAANG | One-line summary |
|---|---|---|---|---|
| [01 · String hashing](01-string-hashing.md) | 🔵 1500–2100 | 🔥 | medium | Randomised mod $2^{61}-1$ (and double mod) rolling hash, $O(1)$ substring compare, LCP by binary search, anti-hack, palindromes by hashing |
| [02 · Prefix function and KMP](02-prefix-function-kmp.md) | 🔵 1500–2100 | 🔥 | medium | Borders, $O(n)$ proof, matching via $p\#t$, prefix occurrence counts, periods, KMP automaton + DP |
| [03 · Z-function](03-z-function.md) | 🔵 1500–2200 | 🔥 | low | Z-box, matching, periods and compression, $z \leftrightarrow \pi$ conversions |
| [04 · Manacher and palindromes](04-manacher-and-palindromes.md) | 🔵 1600–2200 | 🔥 | high | $d_1/d_2$ radii in $O(n)$, counting palindromic substrings, longest palindrome, hashing alternative |
| [05 · Trie and binary trie](05-trie-and-binary-trie.md) | 🔵 1400–2100 | 🔥 | high | Array trie with counts, max-XOR pair/subarray, count $x \oplus y < k$, DP on a trie, autocomplete |
| [06 · Aho–Corasick](06-aho-corasick.md) | 🟠 2100–2400 | ⚡ | low | Failure links by BFS, dictionary links, counts of every pattern, automaton DP, failure tree |
| [07 · Suffix array and LCP](07-suffix-array-and-lcp.md) | 🟠 2000–2400 | ⚡ | low | $O(n\log n)$ doubling, Kasai, distinct substrings, LCS, $k$-th substring, LCP of any two suffixes |
| [08 · Suffix automaton](08-suffix-automaton.md) | 🟠 2200–2600 | ⚡ | none | endpos classes, clones, $2n-1$ / $3n-4$ bounds, occurrence counts, LCS, $k$-th substring |
| [09 · Palindromic tree (eertree)](09-palindromic-tree-eertree.md) | 🔴 2300–2700 | 🧊 | low | $\le n+2$ nodes, suffix links, palindrome counts and occurrences, series links |
| [problems.md](problems.md) | all | — | — | ~90 graded problems + LeetCode list |
| [Cheat sheet](../99-Cheat-Sheets/11-strings-cheatsheet.md) | — | — | — | formulas, templates (C++ and Java), signals, pitfalls |

## Prerequisites

- [Modular arithmetic](../04-Number-Theory/02-modular-arithmetic-and-inverses.md) (hashing), [binary search on the answer](../02-Core-Techniques/02-binary-search-and-binary-search-on-answer.md) (LCP / longest repeat by binary search), [prefix sums and difference arrays](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md).
- [Bit manipulation](../01-Foundations/03-bit-manipulation.md) for the binary trie; [BFS](../09-Graphs/01-graph-representation-bfs-dfs.md) for Aho–Corasick.
- [Sparse table](../08-Data-Structures/05-sparse-table-and-rmq.md) and [monotonic stack](../02-Core-Techniques/04-monotonic-stack-and-deque.md) for LCP-array problems; [DP on DAGs](../06-Dynamic-Programming/09-dp-on-dags-and-graphs.md) for automaton counting.
- [Randomised algorithms and hashing](../16-IGM-Frontier/04-randomized-algorithms-and-hashing.md) for the deeper probability arguments.

## Recommended study order

1. **02 prefix function** first (two days): it is the cleanest example of amortised linear-time string processing, and borders/periods recur everywhere. CSES 1753, 1732, 1733; CF 126B.
2. **03 Z-function** (one day) — the same idea from the other side; learn the conversions.
3. **01 hashing** (two days) — the Swiss-army knife; do the anti-hack and collision analysis properly. CF 271D, 1200E, 7D.
4. **04 Manacher** (one day). CSES 1111, CF 1326D2.
5. **05 trie / binary trie** (two days) — high FAANG value; CSES 1655, CF 706D, 923C.
6. **06 Aho–Corasick** (two days) — CSES 2102–2104, CF 1202E.
7. **07 suffix array** (three days) — CSES 2105, 2106, 2108; CF 123D.
8. **08 suffix automaton** (three days) — redo 07's problems with it, then CF 235C.
9. **09 eertree** (one day, later) — when palindromic structure problems start appearing at your level.

For Master by Dec 2027: 01–05 are must-know; 06–07 are expected at 2100+; 08–09 are IGM depth.

## Choosing a technique

| Question | First choice | Alternatives |
|---|---|---|
| all occurrences of one pattern | prefix function / Z on $p\#t$ | hashing |
| occurrences of many patterns in one text | Aho–Corasick | suffix automaton/array of the text |
| compare / LCP of arbitrary substring pairs | hashing + binary search | suffix array + sparse table (deterministic) |
| borders, periods, "is $s$ a power" | prefix function | Z-function |
| longest palindrome / count palindromic substrings | Manacher | hashing + binary search, eertree |
| distinct palindromes, their occurrences | eertree | Manacher + hashing |
| max XOR pair / subarray, count XOR $< k$ | binary trie | — |
| number of distinct substrings | suffix array ($\sum (n - sa_i) - \sum lcp$) | suffix automaton |
| longest common substring of two strings | suffix automaton (matching statistics) | SA of $s\#t$, hashing + binary search |
| $k$-th lexicographic substring | suffix automaton / suffix array | — |
| count strings of length $N$ avoiding patterns | KMP automaton (one) / Aho–Corasick (many) + DP | matrix power for huge $N$ |

## How strings show up in rounds

- **Div. 2 A–C (≤ 1600):** counting, palindrome checks, greedy on characters, simple prefix/suffix reasoning. Hashing is rarely required but often makes C easier.
- **Div. 2 D–E (1700–2200):** prefix function / Z tricks (borders, periods, "longest prefix that is also a suffix"), hashing with binary search, binary trie, Manacher, DP over a KMP automaton.
- **Div. 2 F / Div. 1 C–E (2200+):** Aho–Corasick + DP or + data structure on the failure tree, suffix array with RMQ / DSU over LCP, suffix automaton with link-tree DP, eertree with series links.
- **Hacks:** on open-hack rounds and Educational rounds, fixed-base / fixed-mod hashes and `unordered_map` with default hashes get hacked. Always randomise the base, or use mod $2^{61}-1$.

## Where next

- [problems.md](problems.md) — the consolidated ladder.
- [Cheat sheet](../99-Cheat-Sheets/11-strings-cheatsheet.md) — revision before contests.
- Further: [FFT for wildcard matching](../15-Advanced-Math/03-fft-and-ntt.md), [bitset matching](../16-IGM-Frontier/05-bitset-optimization.md), [FAANG tries](../17-FAANG-Interview-DSA/08-tries.md), [persistent tries](../08-Data-Structures/08-persistent-data-structures.md).
