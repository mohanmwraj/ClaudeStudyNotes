# 11 — Strings: consolidated problem ladder

Graded by rating band, easiest first within each band. Hints name the technique family only. CSES/AtCoder ratings are estimates and marked `(est.)`. Files: [01 hashing](01-string-hashing.md) · [02 KMP](02-prefix-function-kmp.md) · [03 Z](03-z-function.md) · [04 Manacher](04-manacher-and-palindromes.md) · [05 trie](05-trie-and-binary-trie.md) · [06 Aho–Corasick](06-aho-corasick.md) · [07 suffix array](07-suffix-array-and-lcp.md) · [08 suffix automaton](08-suffix-automaton.md) · [09 eertree](09-palindromic-tree-eertree.md) · [cheat sheet](../99-Cheat-Sheets/11-strings-cheatsheet.md).

## ≤ 1400

- [ ] [CF 1800D · Remove Two Letters](https://codeforces.com/problemset/problem/1800/D) — 1200 — when do two deletions give the same string
- [ ] [CF 625B · War of the Corporations](https://codeforces.com/problemset/problem/625/B) — 1200 — greedy over occurrences
- [ ] [CF 1029A · Many Equal Substrings](https://codeforces.com/problemset/problem/1029/A) — 1300 — longest border
- [ ] [CSES 1753 · String Matching](https://cses.fi/problemset/task/1753) — ≈1300 (est.) — one pattern, all occurrences
- [ ] [CSES 1732 · Finding Borders](https://cses.fi/problemset/task/1732) — ≈1300 (est.) — the border chain

## 1400 – 1700

- [ ] [CF 1326D1 · Prefix-Suffix Palindrome (Easy version)](https://codeforces.com/problemset/problem/1326/D1) — 1500 — trim, then a palindromic prefix
- [ ] [CF 159D · Palindrome pairs](https://codeforces.com/problemset/problem/159/D) — 1500 — palindromes starting/ending at each index
- [ ] [CF 1137B · Camp Schedule](https://codeforces.com/problemset/problem/1137/B) — 1600 — period from the longest border
- [ ] [CF 126B · Password](https://codeforces.com/problemset/problem/126/B) — 1700 — border that also occurs inside
- [ ] [CF 2010C2 · Message Transmission Error (hard version)](https://codeforces.com/problemset/problem/2010/C2) — 1700 — a long border
- [ ] [CSES 1733 · Finding Periods](https://cses.fi/problemset/task/1733) — ≈1500 (est.) — periods from $\pi$ or $z$
- [ ] [CSES 2107 · String Functions](https://cses.fi/problemset/task/2107) — ≈1500 (est.) — Z and prefix function side by side
- [ ] [CSES 1111 · Longest Palindrome](https://cses.fi/problemset/task/1111) — ≈1500 (est.) — Manacher
- [ ] [CSES 1110 · Minimal Rotation](https://cses.fi/problemset/task/1110) — ≈1700 (est.) — compare rotations (hashing or Booth)
- [ ] [CSES 1655 · Maximum Xor Subarray](https://cses.fi/problemset/task/1655) — ≈1700 (est.) — prefix XOR + binary trie
- [ ] [CSES 1731 · Word Combinations](https://cses.fi/problemset/task/1731) — ≈1700 (est.) — trie + DP over the text
- [ ] [AtCoder ABC362 G · Count Substring Query](https://atcoder.jp/contests/abc362/tasks/abc362_g) — ≈1625 (est.) — many patterns, one text

## 1700 – 1900

- [ ] [CF 271D · Good Substrings](https://codeforces.com/problemset/problem/271/D) — 1800 — distinct substrings under a constraint
- [ ] [CF 471D · MUH and Cube Walls](https://codeforces.com/problemset/problem/471/D) — 1800 — match difference sequences
- [ ] [CF 1326D2 · Prefix-Suffix Palindrome (Hard version)](https://codeforces.com/problemset/problem/1326/D2) — 1800 — longest palindromic prefix in linear time
- [ ] [CF 245H · Queries for Number of Palindromes](https://codeforces.com/problemset/problem/245/H) — 1800 — palindromic substrings per interval
- [ ] [CF 706D · Vasiliy's Multiset](https://codeforces.com/problemset/problem/706/D) — 1800 — binary trie with deletions
- [ ] [CF 923C · Perfect Security](https://codeforces.com/problemset/problem/923/C) — 1800 — greedy minimum XOR
- [ ] [CF 835D · Palindromic characteristics](https://codeforces.com/problemset/problem/835/D) — 1900 — palindromes and their halves
- [ ] [CF 535D · Tavas and Malekas](https://codeforces.com/problemset/problem/535/D) — 1900 — consistency of overlapping occurrences
- [ ] [CF 1968G1 · Division + LCP (easy version)](https://codeforces.com/problemset/problem/1968/G1) — 1900 — binary search on length + Z
- [ ] [CF 1285D · Dr. Evil Underscores](https://codeforces.com/problemset/problem/1285/D) — 1900 — recursion on bits of a trie
- [ ] [CF 1902E · Collapsing Strings](https://codeforces.com/problemset/problem/1902/E) — 1900 — trie of reversed strings, LCP sums
- [ ] [CF 633C · Spy Syndrome 2](https://codeforces.com/problemset/problem/633/C) — 1900 — trie + DP with reconstruction
- [ ] [CF 455B · A Lot of Games](https://codeforces.com/problemset/problem/455/B) — 1900 — win/lose states on a trie
- [ ] [CSES 2102 · Finding Patterns](https://cses.fi/problemset/task/2102) — ≈1800 (est.) — many patterns: which occur
- [ ] [CSES 2103 · Counting Patterns](https://cses.fi/problemset/task/2103) — ≈1900 (est.) — occurrence count of every pattern
- [ ] [CSES 2104 · Pattern Positions](https://cses.fi/problemset/task/2104) — ≈1900 (est.) — first occurrence of every pattern
- [ ] [CSES 2105 · Distinct Substrings](https://cses.fi/problemset/task/2105) — ≈1900 (est.) — $\sum (n - sa_i) - \sum lcp$

## 1900 – 2100

- [ ] [CF 514C · Watto and Mechanism](https://codeforces.com/problemset/problem/514/C) — 2000 — hash every one-change variant
- [ ] [CF 113B · Petr#](https://codeforces.com/problemset/problem/113/B) — 2000 — distinct substrings with a start/end condition
- [ ] [CF 1200E · Compress Words](https://codeforces.com/problemset/problem/1200/E) — 2000 — maximal overlap, growing string
- [ ] [CF 346B · Lucky Common Subsequence](https://codeforces.com/problemset/problem/346/B) — 2000 — LCS DP with a KMP state
- [ ] [CF 432D · Prefixes and Suffixes](https://codeforces.com/problemset/problem/432/D) — 2000 — border chain + occurrence counts of prefixes
- [ ] [CF 842D · Vitya and Strange Lesson](https://codeforces.com/problemset/problem/842/D) — 2000 — mex under a global XOR, trie descent
- [ ] [CF 817E · Choosing The Commander](https://codeforces.com/problemset/problem/817/E) — 2000 — count $x \oplus y < k$
- [ ] [CF 1163D · Mysterious Code](https://codeforces.com/problemset/problem/1163/D) — 2100 — DP over two KMP automata
- [ ] [CF 1056E · Check Transcription](https://codeforces.com/problemset/problem/1056/E) — 2100 — enumerate lengths, compare by hash
- [ ] [CF 665E · Beautiful Subarrays](https://codeforces.com/problemset/problem/665/E) — 2100 — prefix XOR + trie counting
- [ ] [CF 128B · String](https://codeforces.com/problemset/problem/128/B) — 2100 — $k$-th substring with repetitions
- [ ] [CSES 1112 · Required Substring](https://cses.fi/problemset/task/1112) — ≈2000 (est.) — DP over the KMP automaton
- [ ] [CSES 2106 · Repeating Substring](https://cses.fi/problemset/task/2106) — ≈1900 (est.) — longest repeat (LCP array or binary search + hash)
- [ ] [CSES 2108 · Substring Order I](https://cses.fi/problemset/task/2108) — ≈2100 (est.) — $k$-th distinct substring
- [ ] [CSES 2109 · Substring Order II](https://cses.fi/problemset/task/2109) — ≈2200 (est.) — $k$-th substring counting repetitions
- [ ] [CSES 2110 · Substring Distribution](https://cses.fi/problemset/task/2110) — ≈2000 (est.) — distinct substrings per length
- [ ] [AtCoder PRACTICE2 I · Number of Substrings](https://atcoder.jp/contests/practice2/tasks/practice2_i) — ≈1900 (est.) — suffix array + LCP

## 2100 – 2400

- [ ] [CF 25E · Test](https://codeforces.com/problemset/problem/25/E) — 2200 — overlaps of three strings
- [ ] [CF 526D · Om Nom and Necklace](https://codeforces.com/problemset/problem/526/D) — 2200 — periods of every prefix
- [ ] [CF 1721E · Prefix Function Queries](https://codeforces.com/problemset/problem/1721/E) — 2200 — extending $\pi$ with an automaton
- [ ] [CF 1537E2 · Erase and Extend (Hard Version)](https://codeforces.com/problemset/problem/1537/E2) — 2200 — best prefix to repeat
- [ ] [CF 1003F · Abbreviation](https://codeforces.com/problemset/problem/1003/F) — 2200 — equal word segments
- [ ] [CF 1968G2 · Division + LCP (hard version)](https://codeforces.com/problemset/problem/1968/G2) — 2200 — Z + harmonic counting
- [ ] [CF 7D · Palindrome Degree](https://codeforces.com/problemset/problem/7/D) — 2200 — palindromic prefixes online
- [ ] [CF 427D · Match & Catch](https://codeforces.com/problemset/problem/427/D) — 2200 — shortest unique common substring
- [ ] [CF 282E · Sausage Maximization](https://codeforces.com/problemset/problem/282/E) — 2200 — prefix vs suffix XOR in a trie
- [ ] [CF 979D · Kuro and GCD and XOR and SUM](https://codeforces.com/problemset/problem/979/D) — 2200 — one binary trie per divisor
- [ ] [CF 808G · Anthem of Berland](https://codeforces.com/problemset/problem/808/G) — 2300 — DP with the prefix function over wildcards
- [ ] [CF 1015F · Bracket Substring](https://codeforces.com/problemset/problem/1015/F) — 2300 — automaton state × balance DP
- [ ] [CF 727E · Games on a CD](https://codeforces.com/problemset/problem/727/E) — 2300 — hashing words around a circle
- [ ] [CF 888G · Xor-MST](https://codeforces.com/problemset/problem/888/G) — 2300 — divide and conquer on a binary trie
- [ ] [CF 123D · String](https://codeforces.com/problemset/problem/123/D) — 2300 — occurrence-weighted substring sum
- [ ] [CF 802G3 · Fake News (hard)](https://codeforces.com/problemset/problem/802/G3) — 2300 — $\sum \mathrm{occ}^2$
- [ ] [CF 1080E · Sonya and Matrix Beauty](https://codeforces.com/problemset/problem/1080/E) — 2400 — palindromes over column signatures
- [ ] [CF 1202E · You Are Given Some Strings...](https://codeforces.com/problemset/problem/1202/E) — 2400 — automaton in both directions
- [ ] [CF 710F · String Set Queries](https://codeforces.com/problemset/problem/710/F) — 2400 — dynamic dictionary, binary grouping
- [ ] [CF 873F · Forbidden Indices](https://codeforces.com/problemset/problem/873/F) — 2400 — occurrences avoiding marked ends
- [ ] [CF 316G3 · Good Substrings](https://codeforces.com/problemset/problem/316/G3) — 2400 — counts across several strings
- [ ] [CF 452E · Three strings](https://codeforces.com/problemset/problem/452/E) — 2400 — common substrings of three strings
- [ ] [CF 1720D2 · Xor-Subsequence (hard version)](https://codeforces.com/problemset/problem/1720/D2) — 2400 — trie DP over bits

## 2400+

- [ ] [CF 580E · Kefa and Watch](https://codeforces.com/problemset/problem/580/E) — 2500 — segment tree of hashes
- [ ] [CF 963D · Frequency of String](https://codeforces.com/problemset/problem/963/D) — 2500 — few distinct pattern lengths
- [ ] [CF 696D · Legen...](https://codeforces.com/problemset/problem/696/D) — 2500 — automaton + max-plus matrix power
- [ ] [CF 86C · Genetic engineering](https://codeforces.com/problemset/problem/86/C) — 2500 — automaton DP with coverage
- [ ] [CF 1437G · Death DBMS](https://codeforces.com/problemset/problem/1437/G) — 2600 — failure tree + path maximum
- [ ] [CF 1073G · Yet Another LCP Problem](https://codeforces.com/problemset/problem/1073/G) — 2600 — LCP sums with a monotonic stack
- [ ] [CF 1051E · Vasya and Big Integers](https://codeforces.com/problemset/problem/1051/E) — 2600 — Z-function comparisons inside a DP
- [ ] [CF 1827C · Palindrome Partition](https://codeforces.com/problemset/problem/1827/C) — 2600 — even palindromes, shortest decomposition
- [ ] [CF 1207G · Indie Album](https://codeforces.com/problemset/problem/1207/G) — 2700 — failure tree + offline trie walk
- [ ] [CF 235C · Cyclical Quest](https://codeforces.com/problemset/problem/235/C) — 2700 — rotations via suffix automaton
- [ ] [CF 616F · Expensive Strings](https://codeforces.com/problemset/problem/616/F) — 2700 — weighted substring occurrences
- [ ] [CF 1313E · Concatenation with intersection](https://codeforces.com/problemset/problem/1313/E) — 2700 — Z + Fenwick sweeps
- [ ] [CF 547E · Mike and Friends](https://codeforces.com/problemset/problem/547/E) — 2800 — failure tree + Fenwick, offline
- [ ] [CF 163E · e-Government](https://codeforces.com/problemset/problem/163/E) — 2800 — toggled patterns on the failure tree
- [ ] [CF 1327G · Letters and Question Marks](https://codeforces.com/problemset/problem/1327/G) — 2800 — automaton DP over masks
- [ ] [CF 1400F · x-prime Substrings](https://codeforces.com/problemset/problem/1400/F) — 2800 — enumerate bad strings, then automaton DP
- [ ] [CF 932G · Palindrome Partition](https://codeforces.com/problemset/problem/932/G) — 2900 — eertree series links
- [ ] [CF 17E · Palisection](https://codeforces.com/problemset/problem/17/E) — 2900 — palindrome radii + difference arrays
- [ ] [CF 666E · Forensic Examination](https://codeforces.com/problemset/problem/666/E) — 3100 — automaton + segment-tree merging
- [ ] [CF 1037H · Security](https://codeforces.com/problemset/problem/1037/H) — 3200 — automaton + endpos sets
- [ ] [CF 700E · Cool Slogans](https://codeforces.com/problemset/problem/700/E) — 3300 — DP on the suffix-link tree
- [ ] [CF 906E · Reverses](https://codeforces.com/problemset/problem/906/E) — 3300 — palindromic factorisation
- [ ] [CF 1081H · Palindromic Magic](https://codeforces.com/problemset/problem/1081/H) — 3500 — distinct concatenations of palindromes

## LeetCode (strings — interview side)

- [ ] [LC 28 · Find the Index of the First Occurrence in a String](https://leetcode.com/problems/find-the-index-of-the-first-occurrence-in-a-string/) — Easy — KMP / Z / Rabin–Karp
- [ ] [LC 459 · Repeated Substring Pattern](https://leetcode.com/problems/repeated-substring-pattern/) — Easy — period from the prefix function
- [ ] [LC 796 · Rotate String](https://leetcode.com/problems/rotate-string/) — Easy — search inside $s + s$
- [ ] [LC 14 · Longest Common Prefix](https://leetcode.com/problems/longest-common-prefix/) — Easy — trie or pairwise scan
- [ ] [LC 5 · Longest Palindromic Substring](https://leetcode.com/problems/longest-palindromic-substring/) — Medium — Manacher / expand around centre
- [ ] [LC 647 · Palindromic Substrings](https://leetcode.com/problems/palindromic-substrings/) — Medium — sum of radii
- [ ] [LC 187 · Repeated DNA Sequences](https://leetcode.com/problems/repeated-dna-sequences/) — Medium — fixed-length rolling hash
- [ ] [LC 718 · Maximum Length of Repeated Subarray](https://leetcode.com/problems/maximum-length-of-repeated-subarray/) — Medium — binary search + hashing
- [ ] [LC 208 · Implement Trie (Prefix Tree)](https://leetcode.com/problems/implement-trie-prefix-tree/) — Medium — the trie
- [ ] [LC 211 · Design Add and Search Words Data Structure](https://leetcode.com/problems/design-add-and-search-words-data-structure/) — Medium — trie with wildcards
- [ ] [LC 421 · Maximum XOR of Two Numbers in an Array](https://leetcode.com/problems/maximum-xor-of-two-numbers-in-an-array/) — Medium — binary trie
- [ ] [LC 1268 · Search Suggestions System](https://leetcode.com/problems/search-suggestions-system/) — Medium — autocomplete on a trie
- [ ] [LC 212 · Word Search II](https://leetcode.com/problems/word-search-ii/) — Hard — trie-guided DFS
- [ ] [LC 214 · Shortest Palindrome](https://leetcode.com/problems/shortest-palindrome/) — Hard — longest palindromic prefix via the prefix function
- [ ] [LC 1392 · Longest Happy Prefix](https://leetcode.com/problems/longest-happy-prefix/) — Hard — the last value of the prefix function
- [ ] [LC 1044 · Longest Duplicate Substring](https://leetcode.com/problems/longest-duplicate-substring/) — Hard — binary search + hashing, or the LCP array
- [ ] [LC 1923 · Longest Common Subpath](https://leetcode.com/problems/longest-common-subpath/) — Hard — binary search + hashing over many arrays
- [ ] [LC 1032 · Stream of Characters](https://leetcode.com/problems/stream-of-characters/) — Hard — Aho–Corasick or a reversed trie
- [ ] [LC 132 · Palindrome Partitioning II](https://leetcode.com/problems/palindrome-partitioning-ii/) — Hard — palindromic DP
- [ ] [LC 2223 · Sum of Scores of Built Strings](https://leetcode.com/problems/sum-of-scores-of-built-strings/) — Hard — sum of the Z-function
- [ ] [LC 2781 · Length of the Longest Valid Substring](https://leetcode.com/problems/length-of-the-longest-valid-substring/) — Hard — forbidden words + sliding window
