# Practice methodology

> **Band:** all · **Priority:** 🔥 · **FAANG:** medium (the same habits work for LeetCode) · **Prerequisites:** [rating tiers](01-rating-tiers-and-what-each-level-solves.md), [first-principles problem solving](05-first-principles-problem-solving.md)
> **You can say you know this when:** every practice session has a chosen difficulty, a time box, an upsolving step and a journal entry, and once a month you can show from the Codeforces API that the problems you solve are getting harder.

**Status of the advice.** The deep-research run of 23 Oct 2026 found that **practice methodology is a matter of opinion, not a fixed rule**
([08](08-research-findings-and-sources.md), finding 13). Below, the few verified statements are marked *verified*; everything else is labelled
as opinion or as this kit's recommendation.

## 1. Choosing problems

**The "how hard it feels" rule (verified as the USACO Guide's advice).** The USACO Guide's practice page ([usaco.guide/general/practicing](https://usaco.guide/general/practicing))
judges difficulty by *how it feels to you*: a problem is **too easy** if you solve it at once, **too hard** if you are missing several steps, and
**right** if you struggle for a while or need the solution for only a small part.

**The "+200–300 above your rating" rule (unverified heuristic).** It is popular on Codeforces blogs to practise problems rated 200–300 above
your current rating. This research did **not** verify it, and the USACO Guide gives no rating offset. Use it only as a starting guess for the
"right" zone, and correct it with the feel rule: if you solve almost everything at $R+200$ quickly, move up; if you rarely solve them even with
time, move down.

**Moving up (heuristic seen in Codeforces threads).** A rule of thumb in the Codeforces discussions collected by the research: move up a band
once you solve about **80%** of the problems at your current one.

**A practical mix (this kit's recommendation).**

| Share of practice problems | Difficulty | Purpose |
|---|---|---|
| ~20% | at your level ($R$) | speed, clean implementation, confidence |
| ~60% | $R+100$ … $R+300$ | the "struggle zone" where most learning happens |
| ~20% | $R+400$ and above, or topic ladders of new material | stretch, exposure to ideas you will need next |

**Where problems come from:** the topic ladders in each kit file (tagged — you know the technique), the folders' `problems.md` (mixed by band),
and **untagged** problems from the Codeforces problemset or AtCoder ARC (§6). Prefer classics with many solvers: they have editorials and
discussion.

## 2. How long to try before reading the solution

**There is no agreed time (verified).** The USACO Guide presents the views of several individuals as opinions:

| Person (as quoted on the USACO Guide page) | When to look at the solution |
|---|---|
| Nathan Chen | when progress stops — which could be 1–5 hours |
| Benjamin Qi | keep going while new ideas are still coming |
| Darren Yao | after 15–20 minutes without meaningful progress on Bronze problems, 30–40 minutes on Silver |
| Nathan Wang | anywhere from about 15 minutes to five hours |

Codeforces threads show the same spread (at least 1 hour; 20 minutes for A and 40 for B; 1–4 hours in polls). Note that Yao's limits start
only after *no meaningful progress* and apply to USACO Bronze/Silver, not to Master-level problems.

**This kit's default** (an opinion you should adjust): the time box grows with the band, and the clock is about *progress*, not elapsed time.

| Problem relative to you | Time box before the first hint |
|---|---|
| at your level | 30–45 min |
| $R+200$ … $R+300$ | 60–90 min, as long as you produce new artefacts (cases, conjectures, a brute force) |
| $R+400$ and above | 90–120 min, then read hints one at a time |

"Progress" means a new artefact from the [framework](05-first-principles-problem-solving.md): a restatement, a table of small cases, a brute
force, a conjecture, a counterexample. Twenty minutes of re-reading the statement is not progress.

## 3. Reading editorials without wasting the problem

The editorial is a resource you can spend once per problem; spend it in small coins.

1. **First, write down what you know**: your best idea, where it breaks, the constraint you could not exploit.
2. **Read only the first hint** (many Codeforces editorials have hints in spoilers; otherwise read the first paragraph only). Close it.
3. **Retry for 15–30 minutes** with the hint. If solved, implement — this counts as a solve with hint.
4. **Next hint / next paragraph**, retry again.
5. **Full solution**: read it, then **close it and implement from memory**. Do not copy code.
6. **Explain the key idea in one sentence** in your journal (§5), including the *trigger*: "the constraint $m\le1000$ next to $n\le2\cdot10^5$ should
   have made me think of pigeonhole".
7. **Re-solve after a delay** (§5) — the test of whether you learned it.

If the editorial uses a technique you do not know, stop and study that topic file first; then return to the problem.

## 4. Contests, virtual contests and upsolving

- **Rated contests** measure performance under time pressure and train the skills practice cannot: problem selection, speed, nerves
  ([contest strategy](04-contest-strategy-and-mindset.md)).
- **Virtual participation** (Codeforces lets you replay a past contest with its original timer and a simulated standings position) turns any
  past round into a full contest at a convenient time. Use it for placement ([roadmap §1](02-roadmap-nov-2026-to-dec-2027.md)), for Div. 1
  practice before you are 1900+, and when a live round conflicts with work.
- **Upsolving** = after the contest, solve the problems you could not, up to about one or two above your last solved letter. Opinion widely held
  among strong competitors: upsolving is where most of a contest's learning value lies. This kit's rule: **within 48 hours, upsolve the first unsolved
  problem; within a week, the second.**

## 5. The idea journal and spaced repetition

**Idea journal.** One line per insight, not per problem, in a plain file or spreadsheet:

| Date | Problem | Key idea (one sentence) | Trigger (what should have made me think of it) | Topic file |
|---|---|---|---|---|
| 2026-11-12 | CF 1398C | subtract 1 from each digit → equal prefix sums | "sum equals length" = sum of $(a_i - 1)$ is 0 | [02/01 prefix sums](../02-Core-Techniques/01-prefix-sums-and-difference-arrays.md) |

After a few hundred entries the trigger column *is* your intuition, written down.

**Spaced repetition (a well-established learning technique; schedule below is this kit's).** Re-solve journal problems without notes after
about **3 days, 2 weeks and 2 months**. If you fail, the interval restarts. Revise the relevant [cheat sheet](../99-Cheat-Sheets/01-foundations-cheatsheet.md)
the evening before a contest (each cheat sheet has a "last-minute before contest" list). Re-implement each 🔥 reference implementation from
memory in both languages once a month until it takes under 10 minutes.

## 6. Practising untagged problems

Tags tell you the technique, which removes the hardest part of the problem (steps 5–7 of the [framework](05-first-principles-problem-solving.md)).
Codeforces lets you hide tags in the problemset settings. This kit's split: **topic ladders tagged** (you are learning that technique), **everything
else untagged**, including the mixed sets in each folder's `problems.md`. The cf-stats tag table shows why: constructive algorithms is 16–22% of
problems at *every* band, and those problems do not announce themselves.

## 7. Stress testing as a habit

For every wrong answer in practice whose bug you cannot see within 10 minutes, write a brute force and a generator and run the stress script
([environment & templates §5](06-environment-templates-cpp-java.md)). The habit pays twice: it finds the bug, and it trains you to write
brute forces quickly — which is step 4 of the framework. During contests, stress testing is worth it when the problem is worth many points
and the solution has a case analysis.

## 8. Tracking progress with the Codeforces API

The official API ([codeforces.com/apiHelp](https://codeforces.com/apiHelp)) needs no key for public data. The two calls you need:
`user.status?handle=H` (all submissions, newest first, each with `verdict`, `creationTimeSeconds` and `problem.rating`) and `user.rating?handle=H`
(rated contests with rank and rating change). Both scripts below were run against the live API while writing this file and printed the same counts.

```powershell
# usage: powershell -ExecutionPolicy Bypass -File .\cf-progress.ps1 -Handle your_handle -Since 2026-11-01
param([Parameter(Mandatory = $true)][string]$Handle, [string]$Since = "2026-11-01")
$sinceUnix = [DateTimeOffset]::new([DateTime]::Parse($Since), [TimeSpan]::Zero).ToUnixTimeSeconds()
$subs = (Invoke-RestMethod "https://codeforces.com/api/user.status?handle=$Handle").result
$solved = $subs | Where-Object { $_.verdict -eq "OK" -and $_.creationTimeSeconds -ge $sinceUnix } |
    Group-Object { "$($_.problem.contestId)$($_.problem.index)" } | ForEach-Object { $_.Group[-1] }   # first AC (list is newest first)
"Solved since ${Since}: $(@($solved).Count) distinct problems"
$solved | Group-Object { if ($_.problem.rating) { [int]$_.problem.rating } else { 0 } } |
    Sort-Object { [int]$_.Name } | ForEach-Object { "{0,6}  {1}" -f ($(if ($_.Name -eq "0") { "unrated" } else { $_.Name })), $_.Count }
$contests = (Invoke-RestMethod "https://codeforces.com/api/user.rating?handle=$Handle").result |
    Where-Object { $_.ratingUpdateTimeSeconds -ge $sinceUnix }
"Rated contests since ${Since}: $(@($contests).Count)"
$contests | Select-Object -Last 10 | ForEach-Object { "{0,-60} rank {1,6}  {2} -> {3}" -f $_.contestName.Substring(0, [Math]::Min(60, $_.contestName.Length)), $_.rank, $_.oldRating, $_.newRating }
```

```python
"""usage: python cf_progress.py HANDLE [YYYY-MM-DD]   -- distinct problems solved per rating, and recent rated contests"""
import json, sys, urllib.request
from collections import Counter
from datetime import datetime, timezone

def api(method):
    with urllib.request.urlopen(f"https://codeforces.com/api/{method}", timeout=30) as r:
        data = json.load(r)
    if data["status"] != "OK":
        sys.exit(data.get("comment", "API error"))
    return data["result"]

handle = sys.argv[1]
since = datetime.fromisoformat(sys.argv[2] if len(sys.argv) > 2 else "2026-11-01").replace(tzinfo=timezone.utc).timestamp()
solved = {}
for s in api(f"user.status?handle={handle}"):
    if s["verdict"] == "OK" and s["creationTimeSeconds"] >= since:
        p = s["problem"]
        solved[(p.get("contestId"), p["index"])] = p.get("rating", 0)
print(f"Solved since {sys.argv[2] if len(sys.argv) > 2 else '2026-11-01'}: {len(solved)} distinct problems")
for rating, cnt in sorted(Counter(solved.values()).items()):
    print(f"{rating or 'unrated':>8}  {cnt}")
contests = [c for c in api(f"user.rating?handle={handle}") if c["ratingUpdateTimeSeconds"] >= since]
print(f"Rated contests: {len(contests)}")
for c in contests[-10:]:
    print(f"{c['contestName'][:60]:<60} rank {c['rank']:>6}  {c['oldRating']} -> {c['newRating']}")
```

What to look at monthly (this kit's suggestion): the number of distinct problems solved in your "struggle zone" ($R+100$…$R+300$); the median
rating of problems solved this month vs. last month; your performance (not rating) in the last 4–8 rated rounds; and the quarterly checkpoints
in the [roadmap](02-roadmap-nov-2026-to-dec-2027.md). Performance per contest is shown on Codeforces' contest pages and by third-party sites; the
API gives rank and rating change.

## 9. Burnout and sustainability

You are training for 14 months next to a full-time job; sustainability beats intensity (opinion, but a near-universal one among people who
reached high ratings as adults).

- **Fixed slots, bounded hours.** Pick a weekly template ([roadmap §4](02-roadmap-nov-2026-to-dec-2027.md)) and treat the hours as a ceiling, not a floor.
- **One full rest day per week**, and a lighter "deload" week roughly every 6–8 weeks (half volume, only enjoyable problems).
- **Decouple mood from rating.** Rating swings of ±100 over a few rounds are normal; judge yourself by the quarterly capability checks.
- **Keep it interesting.** Rotate sources (Codeforces, AtCoder, CSES), alternate hard thinking problems with implementation-heavy ones, and
  sometimes solve something just because it looks fun.
- **Warning signs:** dreading contests, not upsolving for weeks, practising only easy problems to "feel productive". Respond by cutting volume, not
  by pushing harder.
- **Sleep before contests** beats a last-minute cram.

## 10. Self-check

1. What does the USACO Guide's "how hard it feels" rule say, and what is the status of the "+200–300" rule?
2. Name two of the individual opinions on when to read the editorial and what they say.
3. Describe the editorial-reading protocol in four steps.
4. What goes into the idea journal, and which column matters most later?
5. Which two API methods give you solved problems and contest history?
6. Why practise mostly untagged problems?

<details><summary>Answers</summary>

1. Too easy if solved at once, too hard if several steps are missing, right if you struggle for a while or need the solution only for a small part. "+200–300" is a popular heuristic that this research did not verify.
2. Any two of: Nathan Chen — when progress stops (1–5 h); Benjamin Qi — while new ideas still come; Darren Yao — 15–20 min without progress (Bronze), 30–40 min (Silver); Nathan Wang — 15 min to 5 h.
3. Write down what you know; read one hint; retry 15–30 min; repeat; finally read the full solution, close it and implement from memory (then journal and re-solve later).
4. One line per insight: date, problem, key idea, trigger, topic file. The trigger column.
5. `user.status` and `user.rating`.
6. Tags give away the technique, skipping the idea-generation steps that contests test; constructive/ad-hoc problems (16–22% at every band) are never labelled in a contest.

</details>
