# Research findings and sources

> **Band:** all · **Priority:** ⚡ (reference) · **FAANG:** low · **Prerequisites:** none
> **What this file is:** the evidence base for folder 00 — every verified claim with its sources, the caveats and refuted claims, the open questions (and which ones this kit answered with its own Codeforces API analysis), the method and full tables of that analysis, additional facts checked while writing the kit, and the complete source list.

## 1. Verified findings (deep-research run, 23 Oct 2026)

The research pipeline extracted 115 claims from 23 fetched sources, verified 25 of them with three independent verifiers each, confirmed 23
(2 refuted), and merged them into 13 findings. Confidence and vote are as reported by the pipeline.

1. **Title bands (high, 3-0).** Candidate Master 1900–2099, Master 2100–2299 (orange), International Master 2300–2399 (also orange),
   Grandmaster 2400–2599, International Grandmaster 2600–2999, Legendary Grandmaster 3000+. Mike Mirzayanov's official post of 3 May 2018
   lowered the orange/Master bound to 2100 and raised the LGM bound to 3000 ("14 participants meet this requirement" — a May 2018 snapshot).
   Wikipedia's current table adds a separate 4000+ tier. Orange alone does not identify Master. *Sources:* blog 59228, topic 68229, Wikipedia.
2. **Division eligibility (high, 3-0).** Div. 2 and Educational rounds are rated only below 2100; a Master is rated in Div. 1, Div. 1 + 2 and Global
   rounds and may enter Div. 2 unofficially. In parallel rounds 1900 is the Div. 1/Div. 2 split; Div. 3 is for ratings below 1600. Confirmed in round
   769 (Jan 2022) and 2026 Div. 2 rounds 1075, 1095, 1102, 1115. *Sources:* blog Igorfardoc (round announcements), blog 59228.
3. **CSES: 400 problems in 18 sections (high, 3-0).** Introductory 24, Sorting and Searching 35, Dynamic Programming 23, Graph Algorithms 36, Range
   Queries 25, Tree Algorithms 16, Mathematics 37, String Algorithms 21, Geometry 16, Advanced Techniques 25, Sliding Window 11, Interactive 6,
   Bitwise Operations 11, Construction 8, Advanced Graph 28, Counting 18, Additional I 30, Additional II 30 (script-counted from the live page;
   400 unique task IDs; one summariser's "416" was an arithmetic slip; grew from an older 300-problem set). *Source:* cses.fi/problemset.
4. **The CSES DP section is a graded ladder (high, 3-0)** from counting/knapsack through sequence DP to bitmask (Elevator Rides), broken profile
   (Counting Tilings), digit DP (Counting Numbers) and Increasing Subsequence II; technique labels are the standard reading, not stated on the page.
5. **Modular binomial toolkit (high, 3-0).** Prime modulus $> \text{MAXN}$: factorials in $O(\text{MAXN})$, queries $O(\log m)$ or $O(1)$ with inverse
   factorials; small prime with huge $n$: Lucas, $O(m + \log_m n)$; composite modulus: prime powers + CRT. *Source:* CP-Algorithms binomial coefficients.
   Caveats: the prime must exceed MAXN; the $O(\text{MAXN})$ inverse pass still needs one modular inverse; Lucas needs a prime modulus.
6. **Binomial identities (high, 3-0):** symmetry, row sum $2^n$, hockey stick, $\sum\binom nk^2=\binom{2n}n$, $\sum k\binom nk = n2^{n-1}$,
   $\sum\binom{n-k}{k} = F_{n+1}$, $\binom nk = \frac nk\binom{n-1}{k-1}$, $\sum_{k=0}^m\binom{n+k}{k} = \binom{n+m+1}{m}$.
7. **Burnside / Pólya / necklaces (high, 3-0):** classes $=\frac1{|G|}\sum_\pi I(\pi)$; unweighted Pólya $\frac1{|G|}\sum_\pi k^{C(\pi)}$; necklaces under rotation
   $\frac1n\sum_{i=1}^n k^{\gcd(i,n)} = \frac1n\sum_{d\mid n}\varphi(n/d)k^d$ (brute-force checked for $n\le7$, $k\le3$; $n=6,k=2$ gives 14).
8. **Kirchhoff's matrix-tree theorem (high, 3-0):** every cofactor of $L = D - A$ (multi-edges allowed, self-loops removed) equals the number of
   spanning trees.
9. **CP-Algorithms coverage (high, 3-0)** of HLD, centroid decomposition (new, March 2026), flows, matchings, 2-SAT, D&C DP, Knuth, CHT/Li Chao (under
   Geometry), Burnside, Kirchhoff, Pick, Prüfer, Sprague–Grundy; **gaps:** DSU on tree/small-to-large, virtual tree, link-cut tree, blossom matching,
   SOS DP, Aliens/WQS, slope trick.
10. **USACO Guide Platinum frequency labels (medium, 3-0):** only *More Applications of Segment Tree* and *Binary Jumping* reach "Somewhat Frequent";
    Small-to-Large, HLD, Centroid, Kruskal Reconstruction Tree "Rare"; Virtual Tree "Has Not Appeared"; Convex Hull, CHT, SOS DP, sweep-line range
    queries "Not Frequent". They measure USACO history, not Codeforces relevance.
11. **USACO Guide Advanced (medium, 3-0):** 41 modules, 376 problems in 8 sections (DS 46, Convexity 30, Graphs 80, DP 24, Flows 30, Polynomials 12,
    Strings 62, Misc. 92); some topics "have not appeared in Platinum and probably never will (ex. Matroid Intersection)". Single community source; snapshot.
12. **Grind 75 / 169 (high, 3-0):** by Yangshun Tay, author of Blind 75 (self-described ex-Meta Staff Engineer); 169 questions chosen by popularity,
    frequency, topic coverage and like-rating, top 75 = core list; "you probably don't need to go beyond 169". The 75/169 problem numbers were not verified.
13. **Practice methodology is opinion (medium, 3-0):** pick problems by how hard they feel (too easy / too hard / right); no agreed time before
    reading the editorial — Nathan Chen (when progress stops, 1–5 h), Benjamin Qi (while new ideas come), Darren Yao (15–20 min without meaningful
    progress on Bronze, 30–40 on Silver), Nathan Wang (15 min to 5 h); Codeforces threads show the same spread and a rule of thumb to move up a band at ~80%
    solved. The "+200–300 above your rating" rule was **not** verified.

## 2. Caveats, refuted claims, open questions

**Not verified in the research run** (kit content on these points is labelled as standard knowledge or opinion): which letters/ratings a Master vs. an
IGM solves consistently; a topic syllabus by rating band; opinions of specific top coders on overrated vs. essential topics; the "+200–300" rule;
realistic timelines and problem counts to reach Master; the contents of Blind 75, NeetCode 150/250 and LeetCode Top Interview 150; most individual
formulas (Fermat, CRT, Möbius, Euler phi, Catalan closed forms, stars and bars, harmonic bounds, Master theorem, Pick, Dilworth, Kőnig, Hall) beyond
the existence of CP-Algorithms articles; the lower title thresholds (later confirmed for this kit, §4).

**Refuted — must not be used:**
- "USACO Guide Advanced labels FFT, suffix automata, game theory, etc. as *Has Not Appeared*" (vote 1-2).
- "USACO Guide time-boxes practice by division and gives no Gold/Platinum figure" (vote 0-3) — the timing advice is presented only as individuals' opinions.

**Source limits:** several Codeforces pages returned HTTP 403 to the research verifiers (they used curl, search snippets and Wikipedia); topic 68229 is
a user blog. **Time sensitivity:** CSES and USACO Guide counts are 23 Oct 2026 snapshots; Codeforces rules have been stable since 2018 but may change.

**Open questions from the research, and what this kit did with them:**

| Open question | Status in the kit |
|---|---|
| Which problem ratings and Div. 1 / Div. 1 + 2 letters do 2100- vs. 2600-rated users solve in contest? | **Partly answered** by the letter table (§3.2): the rating distribution of each letter per round type, read through the reliable/usually/sometimes rule in [rating tiers §5](01-rating-tiers-and-what-each-level-solves.md). Not answered: measured solve rates of individual users. |
| How many problems / months from Specialist, Expert or CM to 2100, and does "+200–300" beat other strategies? | **Not answered.** The [roadmap](02-roadmap-nov-2026-to-dec-2027.md) is explicitly a plan, not a prediction. |
| Which advanced topics appear at 2100–2600 vs. only at 2800+? | **Answered approximately** by the tag table (§3.3): e.g. fft 0.7% (2100–2399) → 1.7% (2400–2599) → 2.9% (2600–2999) → 5.1% (3000+); flows 1.8% → 3.1% → 3.3% → 4.6%. Tags are imperfect. |
| Contents and overlap of Blind 75, NeetCode, Top Interview 150 vs. Grind 169 | **Not answered.** The kit's LeetCode references come from the LeetCode problem table downloaded on 23 Oct 2026 ([LeetCode master list](../17-FAANG-Interview-DSA/18-leetcode-master-list.md)). |

## 3. The kit's Codeforces API analysis ("cf-stats")

### 3.1 Method

Computed on 23 Oct 2026 from two official API responses downloaded the same day: `problemset.problems` (all problems with `rating` and `tags`) and
`contest.list` (names, phases, start times).

- **Letter table:** contests with phase `FINISHED` that started between 2023-01-01 and 2026-10-23, classified by name (case-insensitive):
  "educational" → Educational; "div. 1 + div. 2" / "div.1 + div.2" / "div. 1 and div. 2" → Div. 1 + Div. 2; "global round" → Global; then "div. 1",
  "div. 2", "div. 3", "div. 4". Rounds matching none (e.g. team or special contests) are excluded. A problem's letter is the first character of its
  index (C1/C2 → C). Statistics: median and quartiles (Python `statistics.quantiles`, n = 4) of Codeforces' own problem ratings; cells with fewer
  than 5 problems are omitted.
- **Tag table:** every rated problem of all years, bucketed by rating band; share = (problems in the band carrying the tag) / (problems in the band).
  Tags beginning with `*` (such as `*special`) are excluded. A problem can carry several tags.
- **Observed artefact:** Global Rounds 29–31 are named "Codeforces Global Round N (Div. 1 + Div. 2)" and fall into the Div. 1 + Div. 2 row; only
  Global Rounds 25–28 remain in the Global row (hence $n=5$ there). Div. 1 A medians of 1300 were spot-checked against individual rounds (many
  Div. 1 A problems in 2023–2026 are rated 1200–1400).

### 3.2 Problem rating by round type and letter

Median (25th–75th percentile, count).

| Round type | A | B | C | D | E | F | G | H |
|---|---|---|---|---|---|---|---|---|
| Div. 4 | **800** (800–800, n=19) | **800** (800–800, n=19) | **800** (800–975, n=20) | **1100** (900–1100, n=19) | **1300** (1200–1500, n=19) | **1600** (1500–1700, n=19) | **1700** (1550–1900, n=25) | **2000** (1700–2200, n=10) |
| Div. 3 | **800** (800–800, n=71) | **800** (800–900, n=71) | **1100** (1000–1200, n=76) | **1300** (1200–1400, n=70) | **1500** (1400–1600, n=73) | **1900** (1800–2000, n=73) | **2200** (2000–2200, n=78) | **2400** (2200–2525, n=18) |
| Div. 2 | **800** (800–800, n=176) | **1100** (900–1200, n=174) | **1400** (1300–1600, n=136) | **1900** (1800–2100, n=139) | **2400** (2200–2600, n=144) | **2700** (2500–2900, n=119) | **2900** (2600–3000, n=13) | — |
| Educational (Div. 2) | **800** (800–800, n=55) | **1100** (1000–1100, n=55) | **1300** (1300–1500, n=55) | **1800** (1650–1900, n=57) | **2200** (2150–2400, n=57) | **2700** (2550–2850, n=57) | **2900** (2725–3000, n=16) | — |
| Div. 1 + Div. 2 | **800** (800–800, n=40) | **1100** (1000–1100, n=40) | **1400** (1300–1575, n=44) | **1800** (1700–2000, n=44) | **2200** (2100–2325, n=42) | **2600** (2500–2800, n=51) | **3100** (2900–3400, n=44) | **3500** (3300–3500, n=47) |
| Global Round | — | — | **1400** (1250–1550, n=5) | — | — | — | **3200** (2950–3400, n=5) | — |
| Div. 1 | **1300** (1300–1525, n=54) | **1900** (1700–2000, n=59) | **2300** (2100–2400, n=59) | **2700** (2500–2900, n=56) | **3200** (3000–3400, n=63) | **3500** (3300–3500, n=55) | **3500** (3400–3500, n=11) | — |

### 3.3 Share of problems carrying each tag, by rating band (all rated problems, all years)

| Tag | 800–1399 | 1400–1699 | 1700–1899 | 1900–2099 | 2100–2399 | 2400–2599 | 2600–2999 | 3000–3500 |
|---|---|---|---|---|---|---|---|---|
| greedy | 39.2% | 40.0% | 37.2% | 35.3% | 29.0% | 22.7% | 19.5% | 14.6% |
| math | 37.8% | 31.5% | 31.2% | 27.3% | 28.9% | 27.6% | 28.6% | 23.7% |
| implementation | 43.7% | 34.5% | 27.8% | 21.4% | 18.3% | 15.3% | 11.7% | 7.5% |
| dp | 6.1% | 17.2% | 24.6% | 30.9% | 36.4% | 36.4% | 35.2% | 28.1% |
| constructive algorithms | 19.4% | 19.3% | 21.9% | 20.1% | 17.7% | 18.4% | 16.0% | 17.5% |
| data structures | 4.2% | 13.8% | 16.9% | 24.3% | 28.9% | 30.7% | 27.5% | 29.7% |
| brute force | 19.3% | 21.0% | 19.4% | 18.6% | 18.7% | 16.6% | 15.3% | 8.7% |
| binary search | 4.8% | 14.5% | 15.0% | 18.3% | 15.9% | 16.2% | 9.9% | 11.0% |
| sortings | 13.0% | 13.8% | 13.7% | 12.7% | 12.1% | 9.5% | 5.4% | 4.4% |
| graphs | 1.7% | 7.3% | 12.0% | 14.9% | 18.0% | 19.5% | 17.6% | 15.1% |
| dfs and similar | 1.7% | 7.8% | 11.4% | 16.3% | 18.6% | 16.2% | 12.5% | 7.9% |
| trees | 0.6% | 4.2% | 7.2% | 11.5% | 15.4% | 15.8% | 16.0% | 16.9% |
| number theory | 7.0% | 8.7% | 9.0% | 7.7% | 9.6% | 8.8% | 8.6% | 6.5% |
| combinatorics | 2.0% | 5.4% | 6.5% | 8.4% | 12.5% | 12.9% | 14.3% | 9.6% |
| strings | 9.8% | 7.3% | 7.3% | 6.8% | 6.7% | 4.8% | 5.4% | 4.4% |
| bitmasks | 3.0% | 4.3% | 6.4% | 9.0% | 8.5% | 11.3% | 9.6% | 6.8% |
| two pointers | 3.7% | 8.2% | 8.6% | 9.3% | 6.6% | 7.4% | 4.3% | 3.3% |
| geometry | 2.2% | 2.6% | 3.4% | 3.2% | 3.6% | 5.3% | 7.3% | 6.2% |
| dsu | 0.7% | 3.2% | 3.5% | 5.9% | 6.5% | 8.1% | 5.3% | 3.0% |
| divide and conquer | 0.1% | 0.9% | 2.3% | 2.6% | 4.8% | 6.9% | 8.4% | 7.5% |
| games | 2.7% | 2.4% | 2.5% | 2.7% | 3.1% | 3.1% | 2.7% | 3.3% |
| shortest paths | 0.3% | 1.6% | 3.7% | 4.2% | 4.7% | 4.0% | 4.2% | 3.1% |
| interactive | 0.2% | 1.4% | 2.6% | 3.9% | 3.3% | 3.7% | 4.9% | 6.5% |
| probabilities | 0.2% | 0.5% | 1.8% | 2.3% | 4.4% | 4.4% | 6.4% | 3.8% |
| hashing | 0.3% | 1.2% | 2.5% | 2.8% | 3.3% | 4.9% | 3.9% | 2.5% |
| flows | 0.1% | 0.1% | 0.7% | 1.1% | 1.8% | 3.1% | 3.3% | 4.6% |
| matrices | 0.1% | 0.4% | 0.4% | 1.0% | 1.7% | 2.9% | 3.6% | 2.6% |
| fft | 0.0% | 0.0% | 0.1% | 0.4% | 0.7% | 1.7% | 2.9% | 5.1% |
| graph matchings | 0.2% | 0.1% | 0.7% | 0.6% | 1.3% | 2.4% | 1.9% | 2.1% |
| string suffix structures | 0.0% | 0.1% | 0.4% | 0.8% | 1.3% | 1.8% | 2.5% | 2.3% |
| ternary search | 0.1% | 0.6% | 0.9% | 1.4% | 1.5% | 1.0% | 0.1% | 0.3% |
| meet-in-the-middle | 0.0% | 0.1% | 0.5% | 0.5% | 0.7% | 0.7% | 1.1% | 1.0% |
| 2-sat | 0.0% | 0.3% | 0.1% | 0.8% | 0.4% | 0.8% | 0.8% | 0.5% |
| expression parsing | 0.2% | 0.5% | 0.9% | 0.3% | 0.4% | 0.1% | 0.3% | 0.2% |
| chinese remainder theorem | 0.1% | 0.0% | 0.2% | 0.3% | 0.4% | 0.2% | 0.5% | 0.4% |
| schedules | 0.2% | 0.2% | 0.2% | 0.1% | 0.0% | 0.1% | 0.0% | 0.2% |
| communication | 0.0% | 0.0% | 0.0% | 0.1% | 0.1% | 0.0% | 0.2% | 0.1% |
| **problems in band** | 3262 | 1474 | 1017 | 1037 | 1353 | 884 | 1157 | 1010 |

Interpretation is in [rating tiers §5–6](01-rating-tiers-and-what-each-level-solves.md).

## 4. Additional facts checked while writing this kit (23 Oct 2026)

| Fact | How it was checked | Used in |
|---|---|---|
| Newbie ≤ 1199, Pupil 1200–1399, Specialist 1400–1599, Expert 1600–1899; Div. 4 for Newbie/Pupil, Div. 3 up to Specialist; ≥ 4000 personal-title tier | fetched the Wikipedia Codeforces article; colours from the topic-68229 table (cached copy) | [01](01-rating-tiers-and-what-each-level-solves.md) |
| Codeforces compilers and command lines (G++17 7.3.0 32-bit; G++17 9.2.0, G++20 11.2.0, G++23 14.2 64-bit; Java 11.0.6 32-bit, Java 17/21 64-bit; `--stack=268435456`; Java `-XX:TieredStopAtLevel=1 -Xss64M`; change log to 2025-08-09) | downloaded blog entry 121114 | [06](06-environment-templates-cpp-java.md), [01-Foundations](../01-Foundations/01-complexity-and-constraint-reading.md) |
| Standard-round scoring ($X/250$ per minute, 50-point penalty per earlier failed submission, 30% floor, CE / first-pretest failures not counted), hacks (+100/−50, lock first), solutions run under Windows | downloaded the official contest rules, blog entry 4088 | [04](04-contest-strategy-and-mindset.md) |
| Third-party code rule (own code always allowed; others' code only if written and published before the round, within its licence) | downloaded blog entry 8790 | [06](06-environment-templates-cpp-java.md) |
| AI rule (revision 2024-09-14): applies to rated rounds; no AI for solution logic/code or for debugging from verdicts; translation and syntax-level completion allowed | downloaded blog entry 133941 | [06](06-environment-templates-cpp-java.md), [04](04-contest-strategy-and-mindset.md) |
| JDK 17 and 21 `DualPivotQuicksort` fall back to heapsort beyond `MAX_RECURSION_DEPTH`; JDK 11 has no fallback | read the OpenJDK jdk11u/jdk17u/jdk21u sources on GitHub | [sorting](../01-Foundations/05-sorting-and-comparators.md) |
| Java `HashMap`: `hash = h ^ (h >>> 16)`, `TREEIFY_THRESHOLD = 8`, `MIN_TREEIFY_CAPACITY = 64`; `Integer.hashCode(v) = v`; `Integer` cache upper bound 127 | read the OpenJDK jdk21u sources | [STL & Collections](../01-Foundations/02-cpp-stl-and-java-collections.md) |
| `StreamTokenizer` parses `999999999999999999` as `1.0000000000000001E18`; `Arrays.stream(int[]).sum()` overflows; `1 << 32 == 1` in Java | ran on JDK 21 | [fast I/O](../01-Foundations/06-integer-overflow-precision-and-fast-io.md), [bits](../01-Foundations/03-bit-manipulation.md) |
| MinGW-w64 GCC (WinLibs build 16.2): `-fsanitize=address/undefined` fail to link; `-D_GLIBCXX_DEBUG` catches `vector` out-of-bounds; `-fsanitize=undefined -fsanitize-undefined-trap-on-error` and `-ftrapv` stop on signed overflow | compiled and ran test programs | [06](06-environment-templates-cpp-java.md) |
| Stress-test scripts (Git Bash and PowerShell 5.1) detect a planted bug and pass the fixed solution; PowerShell needs `cmd /c` redirection, `.\exe` paths and `-static` builds | ran both scripts with C++ and Java solutions | [06](06-environment-templates-cpp-java.md) |
| Relative cost of memory access patterns (random vs. sequential reads ≈ 30×; `std::set` insertion of $10^6$ ints ≈ 15× a sort) | quick benchmark on a shared laptop — ratios only | [complexity](../01-Foundations/01-complexity-and-constraint-reading.md) |
| Codeforces API calls `user.status` and `user.rating` for progress tracking | ran the PowerShell and Python scripts against the live API | [03](03-practice-methodology.md) |

## 5. Sources

**Primary and official**
- Codeforces — *Updates in rating and rounds* (M. Mirzayanov, 2018): https://codeforces.com/blog/entry/59228
- Codeforces — round announcements (rating cut-offs), via blog of Igorfardoc: https://codeforces.com/blog/Igorfardoc
- Codeforces — *Codeforces Contest Rules*: https://codeforces.com/blog/entry/4088
- Codeforces — *Rule about third-party code is changing*: https://codeforces.com/blog/entry/8790
- Codeforces — *Rule Restricting the Use of AI*: https://codeforces.com/blog/entry/133941
- Codeforces — *Codeforces Command Lines (2023-10-06)*: https://codeforces.com/blog/entry/121114
- Codeforces API help: https://codeforces.com/apiHelp
- CSES Problem Set: https://cses.fi/problemset/
- Grind 75 — about: https://www.techinterviewhandbook.org/grind75/about
- Tech Interview Handbook repository: https://github.com/yangshun/tech-interview-handbook
- OpenJDK sources: https://github.com/openjdk/jdk21u, https://github.com/openjdk/jdk17u, https://github.com/openjdk/jdk11u

**Secondary references**
- Wikipedia — Codeforces: https://en.wikipedia.org/wiki/Codeforces
- Wikipedia — Burnside's lemma: https://en.wikipedia.org/wiki/Burnside%27s_lemma
- Wikipedia — Pólya enumeration theorem: https://en.wikipedia.org/wiki/P%C3%B3lya_enumeration_theorem
- Wikipedia — Kirchhoff's theorem: https://en.wikipedia.org/wiki/Kirchhoff%27s_theorem
- CP-Algorithms (index): https://cp-algorithms.com/
- CP-Algorithms — Binomial coefficients: https://cp-algorithms.com/combinatorics/binomial-coefficients.html
- CP-Algorithms — Burnside's lemma / Pólya: https://cp-algorithms.com/combinatorics/burnside.html
- CP-Algorithms — Kirchhoff's theorem: https://cp-algorithms.com/graph/kirchhoff-theorem.html
- CP-Algorithms — Heavy-light decomposition: https://cp-algorithms.com/graph/hld.html
- CP-Algorithms — Centroid decomposition: https://cp-algorithms.com/graph/centroid_decomposition.html
- CP-Algorithms — Convex hull trick and Li Chao tree: https://cp-algorithms.com/geometry/convex_hull_trick.html
- USACO Guide — Platinum: https://usaco.guide/plat
- USACO Guide — Advanced: https://usaco.guide/adv
- USACO Guide — Practicing: https://usaco.guide/general/practicing
- USACO Guide repository: https://github.com/cpinitiative/usaco-guide

**Blogs and community pages (opinion-level sources)**
- Codeforces topic 68229 (rating/colour table, user blog): https://codeforces.com/topic/68229/en9
- Codeforces blog entries 89276, 138405, 98806, 92248, 91363, 53925, 118001: https://codeforces.com/blog/entry/89276,
  https://codeforces.com/blog/entry/138405, https://codeforces.com/blog/entry/98806, https://codeforces.com/blog/entry/92248,
  https://codeforces.com/blog/entry/91363, https://codeforces.com/blog/entry/53925, https://codeforces.com/blog/entry/118001
- Codeforces blog of ali1011 ("What to do if you've reached Candidate Master"): https://codeforces.com/blog/ali1011
- Codeforces practice-advice threads cited by the research (entries 76737, 126214, 53187, 86476, 77406; topic 53444)
- Tech Interview Handbook — study plan: https://www.techinterviewhandbook.org/coding-interview-study-plan/
- Tech Interview Handbook — best practice questions: https://www.techinterviewhandbook.org/best-practice-questions/
- LeetCode Patterns (Sean Prashad): https://seanprashad.com/leetcode-patterns/

**Data**
- Codeforces API `problemset.problems` and `contest.list`, downloaded 23 Oct 2026 (cf-stats tables, all problem IDs and ratings in the kit).
- LeetCode, CSES and AtCoder (AtCoder Problems difficulty estimates) problem lists downloaded 23 Oct 2026 (all problem references in the kit).
