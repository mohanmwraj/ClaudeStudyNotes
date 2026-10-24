# Contest strategy and mindset

> **Band:** all (matters most from 1600, where speed starts to separate ratings) · **Priority:** 🔥 · **FAANG:** low (but the calm, systematic debugging carries over) · **Prerequisites:** [rating tiers](01-rating-tiers-and-what-each-level-solves.md), [environment & templates](06-environment-templates-cpp-java.md)
> **You can say you know this when:** you have a written plan for the first 30 minutes of any round, can compute what a wrong submission or 10 minutes of delay costs you in points, never lose a problem to a multi-test reset bug, and finish every round with the same post-contest routine regardless of the result.

## 1. Why strategy matters (the rating maths)

Rating changes come from **performance**, i.e. your rank among the rated participants, not from the hardest problem you solved
([rating tiers §3](01-rating-tiers-and-what-each-level-solves.md)). Two people who solve the same problems are separated by **time and
penalties**. At 1600–2100 a large share of the field solves the same first three or four problems, so the order, speed and cleanliness with which
you solve them decide most of your rating change — that is the part of contest skill that strategy controls.

## 2. Scoring rules you must know

**Standard Codeforces rounds (verified in the official contest rules, [blog entry 4088](https://codeforces.com/blog/entry/4088); individual
announcements may change details):**

- Solutions are judged on **pretests** during the round; only a solution that passed pretests scores preliminary points.
- A problem's value decreases by **$X/250$ points per minute**, where $X$ is its initial value (a 500-point problem loses 2 points per minute).
- **Penalty: 50 points per previous unsuccessful submission** of that problem. Compilation errors and submissions failing the **first** pretest are
  not counted.
- You never get less than **30% of the initial value** for a solved problem.
- If several submissions pass pretests, the **last** one is the one that counts; the earlier ones count as unsuccessful attempts.
- **Hacks**: after **locking** a problem (you can no longer resubmit it) you may view the solutions of others in your room and submit a test
  that breaks one. **+100 points** for a successful hack, **−50** for an unsuccessful one. A hacked solution loses its points and the hack test is added to
  that contestant's pretests.
- After the round, all pretests-passed solutions are run on the full **system tests**; "pretests passed" is not "accepted".

Worked numbers, all from these rules:

| Situation | Points |
|---|---|
| 500-pt A at minute 6, first try | $500 - 6\cdot2 = 488$ |
| same A at minute 16 | $468$ — ten minutes cost 20 points |
| 1000-pt B at minute 25 after one WA on pretest 3 | $1000 - 25\cdot4 - 50 = 850$ |
| 1500-pt C at minute 70, first try | $1500 - 70\cdot6 = 1080$ |
| 2000-pt D at minute 115 after two WAs | $\max(2000 - 115\cdot8 - 100,\ 600) = 980$ |

So one wrong submission costs as much as **12.5 minutes on a 1000-point problem** or **25 minutes on a 500-point problem**: a minute spent testing on the
samples and an edge case before submitting is almost always worth it.

**Educational, Div. 3 and Div. 4 rounds** use ICPC-style rules: rank by the number of solved problems, ties broken by penalty time (sum of
solve times plus a fixed penalty per rejected attempt, commonly 10 minutes), followed by an open hacking phase after the contest
(standard knowledge, not verified in this research — read the round announcement). The consequence is the
same: correctness first, then speed; and a solution that passes during the contest can still be hacked afterwards, so avoid anti-hash-vulnerable
`unordered_map` and unshuffled Java `Arrays.sort(int[])` ([STL & Collections](../01-Foundations/02-cpp-stl-and-java-collections.md),
[sorting](../01-Foundations/05-sorting-and-comparators.md)).

## 3. The first 30 minutes

1. **Before the start**: template compiled, editor open, problem folder created, [cheat sheet](../99-Cheat-Sheets/01-foundations-cheatsheet.md)
   "last-minute" list read, the announcement read (number of problems, scoring, interactive problems, unusual start time).
2. **Read A completely** — every constraint, the output format, the note under the samples. Solve it, check the samples by hand if they are small,
   test one edge case, submit.
3. **Then B the same way.** In Div. 2 the first problems are usually in increasing order of difficulty (cf-stats letter medians:
   A ≈ 800, B ≈ 1100, C ≈ 1400). Solving in order is the default.
4. **Glance at the standings** after ~20–30 minutes: the solve counts per problem show the real difficulty order. If a later problem has many more solves
   than the one you are on, read it.

## 4. Time allocation and when to skip

A plan written in advance prevents the most expensive mistake: sinking 60 minutes into one problem while easier points sit unread. These target
times are this kit's suggestions for a **2100 performance in a Div. 2** (adjust to your level):

| Problem | Target | Hard stop before re-planning |
|---|---|---|
| A | ≤ 8 min | 15 min |
| B | ≤ 15 min | 30 min |
| C | ≤ 30 min | 45 min |
| D | ≤ 45 min | — (this is where the round is decided) |
| E | remaining time | — |

**Skip rule (opinion):** at the hard stop, re-read the statement (a misread is the most common cause of being stuck), then decide: if another
unsolved problem has more solves in the standings, switch and come back later; otherwise continue, but switch to the
[framework](05-first-principles-problem-solving.md) steps (small cases, brute force) instead of staring.

**Div. 1 and after crossing 1900/2100.** In parallel rounds you are in Div. 1 from 1900, and from 2100 you are rated only in Div. 1,
Div. 1 + 2 and Global rounds ([rating tiers §2](01-rating-tiers-and-what-each-level-solves.md)). In Div. 1 the letter medians are A ≈ 1300, B ≈ 1900,
C ≈ 2300: **A fast and safe is worth more than anything else** (a failed A is a heavy loss against a strong field), B decides most rounds at
2100–2400, and C is the stretch. Common advice from strong competitors (opinion): in Div. 1 read A, B and C in the first 10 minutes, because
the "right" problem for you is not always the next letter.

## 5. Before you press submit

1. Samples pass (run them all — CPH or a script, [environment §6](06-environment-templates-cpp-java.md)).
2. One edge case by hand: $n = 1$, all values equal, maximum values (overflow), negative values if allowed.
3. Multi-test hygiene (the most common pretest-2 failure):
   - all per-test containers are re-created or cleared, including counters, `visited` arrays and global "best" variables;
   - you **read the whole input of a test** even when you can answer early (an early `break`/`return` out of the reading loop desynchronises all
     later tests);
   - no `memset` of a huge global array per test ([complexity §6](../01-Foundations/01-complexity-and-constraint-reading.md));
   - Java: static fields keep values between tests.
4. Output format: "YES"/"Yes" casing (most problems accept any case, but check), spaces vs newlines, exactly one line per test.
5. Remove or disable debug output (`dbg` is safe; a stray `cerr` is usually fine on Codeforces but a stray `cout` is not).

**After a wrong answer on pretest $k\ge2$**: do not resubmit within a minute "with a small fix". Re-read the statement, check overflow and
resets, think about which input your code mishandles. If the problem is worth it and no bug is visible after a few minutes, write a brute force and
stress test — five minutes of stress testing usually beats three blind resubmissions (150 points).

## 6. Pretests, system tests and hacking

- **Pretests are a subset** of the final tests. Strong pretests are common now, but anti-hash tests, maximum-size tests and corner cases sometimes
  appear only in system tests or as hacks.
- **Hacking in standard rounds** (rules in §2): worth trying at Div. 2 level only when you have a concrete, cheap attack — an `int` overflow on a
  maximal test, an `unordered_map` with the default hash, Java `Arrays.sort` on `int[]` without shuffling, a missing multi-test reset. Opinion:
  for most contestants below 2100, solving one more problem is worth more than hunting hacks.
- **Educational/Div. 3/Div. 4**: the open hacking phase after the contest means *your* solutions face the same attacks — use safe hashing and shuffling.

## 7. After the contest (same routine every time)

1. **Upsolve** the first unsolved problem within 48 hours (and the next one within a week) — [practice methodology §4](03-practice-methodology.md).
2. **Write a three-line post-mortem**: where the time went (reading, thinking, coding, debugging, waiting), the biggest avoidable loss (a WA, a
   misread, a slow problem), and one change for next time.
3. **Journal** every new idea with its trigger ([practice methodology §5](03-practice-methodology.md)).
4. **Look at the rating change last**, and only as one data point among the last 8–10 rounds.

## 8. Tilt and mindset

- **Decide the rules before the contest**: your time boxes, when to switch, "no resubmission within two minutes of a WA". Decisions taken in
  advance are immune to panic.
- **A bad round is noise.** Rating moves by tens of points per round in both directions; a capability change shows only over many rounds. Judge
  yourself against the quarterly checkpoints of the [roadmap](02-roadmap-nov-2026-to-dec-2027.md).
- **No revenge rounds**: after a bad result, do not register for another rated round the same day. Upsolve instead — it converts the bad round into learning.
- **Expect plateaus.** Long stretches without rating gain are common (opinion, but frequently reported). They usually end after a change of
  practice (harder problems, new topics, more upsolving), not after more of the same.
- **Physical basics**: sleep, water, a quiet room, and phone notifications off. They are worth more than any last-minute reading.
- **Integrity**: follow the third-party code and AI rules during rated rounds ([environment §2](06-environment-templates-cpp-java.md)); a
  rating obtained otherwise measures nothing.

## 9. Self-check

1. What does a 500-point problem lose per minute, and what does one rejected attempt cost?
2. Which submissions do *not* count as unsuccessful attempts in standard rounds?
3. Compute the score of a 1500-point problem solved at minute 40 after one WA.
4. What are the hack rewards and penalties, and what must you do before you can hack?
5. List three multi-test bugs that cause "wrong answer on pretest 2".
6. In Div. 1, why is a fast, safe A so valuable?

<details><summary>Answers</summary>

1. 2 points per minute ($X/250$); 50 points per previous unsuccessful submission.
2. Compilation errors and submissions that fail the first pretest.
3. $1500 - 40\cdot6 - 50 = 1210$ (above the 30% floor of 450).
4. +100 for a successful hack, −50 for an unsuccessful one; you must lock the problem first (you can then no longer resubmit it).
5. Containers or counters not reset between tests; breaking out of the input loop early so the next test reads leftover input; a global "answer"/"best" variable not reinitialised (also: `memset` on a huge array making it TLE, Java static fields).
6. The field is strong and almost everyone solves A; failing or being slow on it costs many ranks, and A's points are the cheapest points available (median rating ≈ 1300).

</details>
