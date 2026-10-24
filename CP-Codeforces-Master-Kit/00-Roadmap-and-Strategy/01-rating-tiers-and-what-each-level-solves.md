# Rating tiers and what each level solves

> **Band:** all · **Priority:** 🔥 (orientation: read once, revisit every quarter) · **FAANG:** none · **Prerequisites:** none
> **You can say you know this when:** you can say, from data rather than folklore, which problem letters a 2100, 2400 and 2600 performer solves in each round type, which topics grow in importance between 1900 and 2600, and what "Master capability" means for your practice.

Sources and method for everything below are collected in [research findings & sources](08-research-findings-and-sources.md). Two kinds of
evidence are used and labelled throughout:

- **Verified** — claims checked against primary sources in the deep-research run of 23 Oct 2026 (official Codeforces posts, Wikipedia, live pages).
- **Computed from the Codeforces API on 23 Oct 2026** — tables produced for this kit from the official `problemset.problems` and `contest.list`
  data (method in [08 §3](08-research-findings-and-sources.md)).

Everything else is labelled as opinion or heuristic.

## 1. The rating ladder

| Title | Rating | Colour | Kit band tag |
|---|---|---|---|
| Newbie | ≤ 1199 | grey | 🟢 |
| Pupil | 1200–1399 | green | 🟢 |
| Specialist | 1400–1599 | cyan | 🔵 |
| Expert | 1600–1899 | blue | 🔵 |
| Candidate Master | 1900–2099 | violet | 🟣 |
| **Master** | **2100–2299** | orange | 🟠 |
| International Master | 2300–2399 | orange | 🟠 |
| Grandmaster | 2400–2599 | red | 🔴 |
| International Grandmaster | 2600–2999 | red | 🔴 |
| Legendary Grandmaster | 3000–3999 | black first letter + red | 🔴 |

- **Master and above — verified.** Mike Mirzayanov's official post of 3 May 2018 ([blog entry 59228](https://codeforces.com/blog/entry/59228))
  lowered the orange/Master bound to **2100** and raised the Legendary Grandmaster bound to **3000** ("14 participants meet this requirement" — a May
  2018 snapshot). The bands CM 1900–2099, Master 2100–2299, IM 2300–2399, GM 2400–2599, IGM 2600–2999, LGM 3000+ agree across the official post,
  a user-blog table ([topic 68229](https://codeforces.com/topic/68229/en9)) and Wikipedia. Orange alone does not mean Master: IM is orange too.
- **Lower tiers — confirmed for this kit on 23 Oct 2026** by fetching the [Wikipedia Codeforces article](https://en.wikipedia.org/wiki/Codeforces):
  Newbie ≤ 1199, Pupil 1200–1399, Specialist 1400–1599, Expert 1600–1899. The colours come from the topic-68229 table (Wikipedia's table lists
  ranges, titles and divisions but no colours). The deep-research run itself had not confirmed these lower bounds.
- **Above LGM:** Wikipedia's current table adds a tier at ≥ 4000 whose holders receive their handle as a title (it names tourist and jiangly).

## 2. Who is rated in which round (verified)

| Round type | Rated for | Source |
|---|---|---|
| Div. 2 (stand-alone) and Educational | rating **below 2100** | 2018 post; 2022 and 2026 round announcements (rounds 1075, 1095, 1102, 1115) |
| Parallel Div. 1 / Div. 2 | Div. 1: **1900 and above**; Div. 2: below 1900 | 2018 post |
| Div. 3 | below **1600** (with extra "trusted participant" conditions) | 2018 post |
| Div. 4 | below 1400 | Wikipedia's division column (Newbie/Pupil: 2/3/4, Specialist: 2/3) |
| Div. 1 + Div. 2 (combined), Global rounds | everyone | standard practice; consistent with the cf-stats round names |

Consequence for the goal: **after reaching 2100 you are rated only in Div. 1, Div. 1 + 2 and Global rounds**; you may still enter Div. 2 rounds
unofficially (announcements of 2026 Div. 2 rounds say "Division 1 participants are welcome to take part unofficially"). Div. 1-level problems
become the place where a 2100+ player is measured. Rules have been stable since 2018 but could change before the end-2027 target — check current
announcements.

## 3. What a problem rating means

The commonly described definition used by Codeforces is: **a problem rated $R$ is one that a contestant rated $R$ would solve during the contest
with probability about 50%.** The exact estimation procedure was not verified in this research. Practical consequences:

- Ratings are assigned **after** the round from in-contest results; they are multiples of 100 between 800 and 3500 (the range observed in the API data).
- "I can solve 2100-rated problems when I practise" is weaker than "I perform at 2100": in a contest you also have to *find* the right problem,
  solve it **fast**, avoid penalties, and solve the easier ones first. Rating gains come from performance (your rank among rated participants), not
  from the hardest problem you solved.
- The first problems of a round are noisy (many are pinned at 800), and a Div. 1 problem's rating reflects the strong field that attempted it.

## 4. Problem rating by round type and letter (computed from the Codeforces API on 23 Oct 2026)

Rounds that started between 2023-01-01 and 2026-10-23; median rating, with the 25th–75th percentile in brackets and the number of problems.
Sub-problems such as C1/C2 are merged into their letter. Cells with fewer than 5 problems are left empty.

| Round type | A | B | C | D | E | F | G | H |
|---|---|---|---|---|---|---|---|---|
| Div. 4 | **800** (800–800, n=19) | **800** (800–800, n=19) | **800** (800–975, n=20) | **1100** (900–1100, n=19) | **1300** (1200–1500, n=19) | **1600** (1500–1700, n=19) | **1700** (1550–1900, n=25) | **2000** (1700–2200, n=10) |
| Div. 3 | **800** (800–800, n=71) | **800** (800–900, n=71) | **1100** (1000–1200, n=76) | **1300** (1200–1400, n=70) | **1500** (1400–1600, n=73) | **1900** (1800–2000, n=73) | **2200** (2000–2200, n=78) | **2400** (2200–2525, n=18) |
| Div. 2 | **800** (800–800, n=176) | **1100** (900–1200, n=174) | **1400** (1300–1600, n=136) | **1900** (1800–2100, n=139) | **2400** (2200–2600, n=144) | **2700** (2500–2900, n=119) | **2900** (2600–3000, n=13) | — |
| Educational (Div. 2) | **800** (800–800, n=55) | **1100** (1000–1100, n=55) | **1300** (1300–1500, n=55) | **1800** (1650–1900, n=57) | **2200** (2150–2400, n=57) | **2700** (2550–2850, n=57) | **2900** (2725–3000, n=16) | — |
| Div. 1 + Div. 2 | **800** (800–800, n=40) | **1100** (1000–1100, n=40) | **1400** (1300–1575, n=44) | **1800** (1700–2000, n=44) | **2200** (2100–2325, n=42) | **2600** (2500–2800, n=51) | **3100** (2900–3400, n=44) | **3500** (3300–3500, n=47) |
| Global Round | — | — | **1400** (1250–1550, n=5) | — | — | — | **3200** (2950–3400, n=5) | — |
| Div. 1 | **1300** (1300–1525, n=54) | **1900** (1700–2000, n=59) | **2300** (2100–2400, n=59) | **2700** (2500–2900, n=56) | **3200** (3000–3400, n=63) | **3500** (3300–3500, n=55) | **3500** (3400–3500, n=11) | — |

Notes on the table:

- **Global Round row is tiny on purpose:** recent Global Rounds (29–31) are named "… (Div. 1 + Div. 2)" in the contest list and are therefore
  counted in the Div. 1 + Div. 2 row; only Global Rounds 25–28 fall in the Global row (checked in the downloaded contest list).
- **Div. 1 A is not hard any more:** its median is 1300 in this period (a quick check of individual rounds shows many Div. 1 A problems rated
  1200–1400). The real Div. 1 filter is B (median 1900) and C (median 2300).
- The cf-stats tables use Codeforces' own ratings; individual rounds vary a lot — the interquartile range for Div. 2 E spans 2200–2600.

## 5. What a 2100 / 2400 / 2600 performer solves

Reading rule used here (a heuristic of this kit, not a Codeforces definition): a letter is **reliable** at performance $P$ if its 75th percentile is
$\le P$ (at least three quarters of such problems are at or below your level), **usually** if its median is $\le P$, **sometimes** if its 25th
percentile is $\le P$, and **rarely** otherwise. Applying it to the table of §4:

| Performance | Div. 2 | Educational | Div. 1 + 2 | Div. 1 | Div. 3 |
|---|---|---|---|---|---|
| **1400** | A–B reliable, C usually | A–B reliable, C usually | A–B reliable, C usually | A usually | A–D reliable, E sometimes |
| **1600** | A–C reliable, D rarely | A–C reliable, D rarely | A–C reliable, D rarely | A reliable, B rarely | A–E reliable, F rarely |
| **1900** | A–C reliable, **D usually**, E rarely | A–D reliable, E rarely | A–C reliable, D usually, E rarely | A reliable, **B usually** | A–E reliable, F usually |
| **2100 (Master)** | **A–D reliable**, E rarely (25th pct 2200) | A–D reliable, E rarely | A–D reliable, **E sometimes** | **A–B reliable, C sometimes** | — (not rated) |
| **2400 (GM)** | A–D reliable, **E usually**, F rarely | A–E reliable, F rarely | A–E reliable, F rarely | **A–C reliable**, D rarely | — |
| **2600 (IGM)** | A–E reliable, F sometimes | A–E reliable, F sometimes | A–E reliable, **F usually** | A–C reliable, **D sometimes** | — |

So, concretely:

- **To perform at 2100** you must reliably and *quickly* solve Div. 2 A–D (and, at Master level, Div. 1 A–B), with Div. 2 E / Div. 1 + 2 E / Div. 1 C
  sometimes. The data do **not** support the folk claim "a 2100 player often solves Div. 2 E": fewer than a quarter of recent Div. 2 E problems are
  rated ≤ 2100. What gets a 2100 performance in a Div. 2 is usually *A–D fast with few wrong submissions*.
- **To perform at 2400** you need Div. 1 A–C reliably (C's 75th percentile is exactly 2400) and Div. 2 E about half the time.
- **To perform at 2600** you add Div. 1 D sometimes and Div. 1 + 2 F about half the time.
- The step from 2100 to 2600 is mostly **one more problem per round at the 2300–2700 level** — which is where the topic mix of §6 changes.

## 6. Which topics matter at which band (computed from the Codeforces API on 23 Oct 2026)

Share of rated problems carrying each tag, by rating band (all rated problems, all years; a problem can have several tags, so columns do not
sum to 100%; tags are set by authors/coordinators and are imperfect). Selected rows; the full table is in [08](08-research-findings-and-sources.md).

| Tag | 800–1399 | 1400–1699 | 1700–1899 | 1900–2099 | 2100–2399 | 2400–2599 | 2600–2999 | 3000–3500 | Kit folder |
|---|---|---|---|---|---|---|---|---|---|
| greedy | 39.2% | 40.0% | 37.2% | 35.3% | 29.0% | 22.7% | 19.5% | 14.6% | [03](../03-Greedy-Constructive-Interactive/README.md) |
| math | 37.8% | 31.5% | 31.2% | 27.3% | 28.9% | 27.6% | 28.6% | 23.7% | [04](../04-Number-Theory/README.md), [05](../05-Combinatorics-and-Probability/README.md), [15](../15-Advanced-Math/README.md) |
| implementation | 43.7% | 34.5% | 27.8% | 21.4% | 18.3% | 15.3% | 11.7% | 7.5% | [01](../01-Foundations/README.md) |
| dp | 6.1% | 17.2% | 24.6% | 30.9% | 36.4% | 36.4% | 35.2% | 28.1% | [06](../06-Dynamic-Programming/README.md), [07](../07-DP-Optimizations/README.md) |
| constructive algorithms | 19.4% | 19.3% | 21.9% | 20.1% | 17.7% | 18.4% | 16.0% | 17.5% | [03](../03-Greedy-Constructive-Interactive/README.md) |
| data structures | 4.2% | 13.8% | 16.9% | 24.3% | 28.9% | 30.7% | 27.5% | 29.7% | [08](../08-Data-Structures/README.md) |
| brute force | 19.3% | 21.0% | 19.4% | 18.6% | 18.7% | 16.6% | 15.3% | 8.7% | [01](../01-Foundations/04-recursion-brute-force-and-backtracking.md) |
| binary search | 4.8% | 14.5% | 15.0% | 18.3% | 15.9% | 16.2% | 9.9% | 11.0% | [02](../02-Core-Techniques/README.md) |
| graphs | 1.7% | 7.3% | 12.0% | 14.9% | 18.0% | 19.5% | 17.6% | 15.1% | [09](../09-Graphs/README.md) |
| trees | 0.6% | 4.2% | 7.2% | 11.5% | 15.4% | 15.8% | 16.0% | 16.9% | [10](../10-Trees/README.md) |
| number theory | 7.0% | 8.7% | 9.0% | 7.7% | 9.6% | 8.8% | 8.6% | 6.5% | [04](../04-Number-Theory/README.md) |
| combinatorics | 2.0% | 5.4% | 6.5% | 8.4% | 12.5% | 12.9% | 14.3% | 9.6% | [05](../05-Combinatorics-and-Probability/README.md) |
| strings | 9.8% | 7.3% | 7.3% | 6.8% | 6.7% | 4.8% | 5.4% | 4.4% | [11](../11-Strings/README.md) |
| bitmasks | 3.0% | 4.3% | 6.4% | 9.0% | 8.5% | 11.3% | 9.6% | 6.8% | [01](../01-Foundations/03-bit-manipulation.md), [06](../06-Dynamic-Programming/06-bitmask-dp.md) |
| dsu | 0.7% | 3.2% | 3.5% | 5.9% | 6.5% | 8.1% | 5.3% | 3.0% | [08](../08-Data-Structures/06-dsu-and-variants.md) |
| divide and conquer | 0.1% | 0.9% | 2.3% | 2.6% | 4.8% | 6.9% | 8.4% | 7.5% | [16](../16-IGM-Frontier/README.md) |
| geometry | 2.2% | 2.6% | 3.4% | 3.2% | 3.6% | 5.3% | 7.3% | 6.2% | [14](../14-Geometry/README.md) |
| probabilities | 0.2% | 0.5% | 1.8% | 2.3% | 4.4% | 4.4% | 6.4% | 3.8% | [05](../05-Combinatorics-and-Probability/06-probability-and-expected-value.md) |
| games | 2.7% | 2.4% | 2.5% | 2.7% | 3.1% | 3.1% | 2.7% | 3.3% | [13](../13-Game-Theory/README.md) |
| interactive | 0.2% | 1.4% | 2.6% | 3.9% | 3.3% | 3.7% | 4.9% | 6.5% | [03](../03-Greedy-Constructive-Interactive/05-interactive-problems.md) |
| flows | 0.1% | 0.1% | 0.7% | 1.1% | 1.8% | 3.1% | 3.3% | 4.6% | [12](../12-Flows-and-Matching/README.md) |
| matrices | 0.1% | 0.4% | 0.4% | 1.0% | 1.7% | 2.9% | 3.6% | 2.6% | [15](../15-Advanced-Math/README.md) |
| fft | 0.0% | 0.0% | 0.1% | 0.4% | 0.7% | 1.7% | 2.9% | 5.1% | [15](../15-Advanced-Math/03-fft-and-ntt.md) |
| string suffix structures | 0.0% | 0.1% | 0.4% | 0.8% | 1.3% | 1.8% | 2.5% | 2.3% | [11](../11-Strings/07-suffix-array-and-lcp.md) |
| **problems in band** | 3262 | 1474 | 1017 | 1037 | 1353 | 884 | 1157 | 1010 | |

What the table says (all numbers from the table above):

1. **Rising sharply from 1900–2099 to 2400–2599:** dp (30.9% → 36.4%), data structures (24.3% → 30.7%), graphs (14.9% → 19.5%), trees (11.5% → 15.8%),
   combinatorics (8.4% → 12.9%), divide and conquer (2.6% → 6.9%), probabilities (2.3% → 4.4%), plus the specialist topics that start from almost
   nothing: flows (1.1% → 3.1%), matrices (1.0% → 2.9%), fft (0.4% → 1.7%). **This is the Master → IGM syllabus**: DP and its optimisations, segment
   trees and friends, tree techniques, counting.
2. **Staying roughly flat:** math stays at 27–29% from 1900 upward; constructive algorithms stays at 16–22% in *every* band from 800 to 3500; brute force
   stays at 15–21% up to 2999; games stay near 3%. **Ad-hoc thinking never stops mattering** — at 2400–2599 the greedy, math and constructive tags
   together still mark a large share of problems (they overlap, so the shares cannot simply be added). This is why
   [first-principles problem solving](05-first-principles-problem-solving.md) is the most important file of the kit.
3. **Declining but not disappearing:** implementation (43.7% → 15.3% at 2400–2599), greedy (39.2% → 22.7% — still about one problem in four at
   2400–2599), sortings, two pointers (peaks at 9.3% in 1900–2099).
4. **IGM frontier (2600+):** fft (2.9–5.1%), flows (3.3–4.6%), string suffix structures (~2.5%), interactive rises to 6.5% at 3000+. These are real but small
   shares — learn them after the core (the kit's 🧊 items).

## 7. Caveats (read before drawing conclusions)

- **Tags are imperfect and overlapping**; a "dp" tag can mean a one-line recurrence or a heavy optimisation.
- **Different periods**: the letter table covers rounds from 2023-01-01 to 2026-10-23; the tag table covers all rated problems of all years. Older
  problems may follow older trends.
- **Problem rating ≠ performance**: speed and penalties matter (see [contest strategy](04-contest-strategy-and-mindset.md)); a 2100 performance can come
  from solving A–D quickly without ever touching a 2100-rated problem.
- **The reliable/usually/sometimes thresholds** are this kit's reading rule, not a measured probability of *you* solving a problem.
- **No timeline is implied.** How long it takes to move between these levels was not verified in this research; see the
  [roadmap](02-roadmap-nov-2026-to-dec-2027.md) for a plan that is explicit about that.

## 8. What "Master capability by December 2027" means in practice

Combining §5 and §6, a working definition this kit uses for its checkpoints (a target, not a verified standard):

1. **Speed core:** Div. 2 A–C in about 45 minutes total, Div. 2 D within the contest in most rounds; Div. 1 A–B in most Div. 1 rounds.
2. **Reach:** solve a 2100–2300-rated problem in contest at least sometimes (Div. 1 C, Div. 1 + 2 E).
3. **Syllabus:** every 🔥 item of folders 01–11 (DP and data structures in depth, graphs, trees, combinatorics, number theory), the 🔥 items of 12 and 07.
4. **Depth toward IGM:** the ⚡/🧊 items of 07, 12, 15 and 16 — the topics whose shares grow from 2400 upward in §6.
5. **Practice volume at the right band**: see [practice methodology](03-practice-methodology.md) and the quarterly checkpoints in the
   [roadmap](02-roadmap-nov-2026-to-dec-2027.md).

## 9. Self-check

1. What rating range is Master? International Master? What changed in May 2018?
2. Once you are rated 2150, in which round types are you rated?
3. What is the commonly described meaning of a problem rated 1900?
4. Using the §4 table: is "a 2100 player often solves Div. 2 E" supported by the data? Why or why not?
5. Name four tags whose share grows clearly from 1900–2099 to 2400–2599, and two that stay flat.
6. Why is the Global Round row of the letter table so small?

<details><summary>Answers</summary>

1. Master 2100–2299, IM 2300–2399. The Master/orange floor was lowered to 2100 and the LGM floor raised to 3000.
2. Div. 1, Div. 1 + 2 (combined) and Global rounds; Div. 2 and Educational only unofficially.
3. A contestant rated 1900 would solve it in contest with about 50% probability.
4. No: Div. 2 E has median 2400 and 25th percentile 2200, so fewer than a quarter of recent Div. 2 E problems are rated ≤ 2100.
5. Growing: dp, data structures, graphs, trees, combinatorics, divide and conquer, probabilities (any four). Flat: math, constructive algorithms (also brute force, games).
6. Recent Global Rounds are named "(Div. 1 + Div. 2)" and are counted in that row; only rounds 25–28 remain in the Global row.

</details>
