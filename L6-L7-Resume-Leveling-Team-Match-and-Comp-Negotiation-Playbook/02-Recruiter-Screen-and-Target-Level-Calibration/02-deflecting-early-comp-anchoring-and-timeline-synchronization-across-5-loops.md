# 02.2 · Deflecting early comp anchoring and synchronizing timelines across 5 loops

> Folder 02 · Recruiter screen and target-level calibration · File 2 of 3 · [KB home](../README.md) · Previous: [02.1 The first recruiter call](01-the-initial-recruiter-call-securing-an-l6-or-l7-loop-instead-of-l5.md) · Next: [02.3 Insider intel](03-getting-insider-intel-extracting-exact-round-rubrics-from-your-recruiter.md)

<!-- lint-pack: recruiter -->

| | |
|---|---|
| **Reader** | A candidate fielding "current CTC / expected CTC" questions early, and running several loops that must produce offers in the same week |
| **Running exhibit** | Candidate V's five loops G, A, N, U, F ([02.1 §1.4](01-the-initial-recruiter-call-securing-an-l6-or-l7-loop-instead-of-l5.md#14-candidate-vs-five-loops-composite)); all numbers illustrative |
| **Listing** | `loop_sync.py`: finds a single decision date when every offer is alive, and the asks needed to get there (§9) |
| **Verification** | The listing is byte-identical to the file that was run. §9.3 is a real run over the two plans in §6: before the asks, F can't fit; after F extends its deadline, all five loops land together. The 8 pairs in §7 are checked with `script_lint.py` (recruiter pack). |
| **Marks** | ⚠ = field practice, not published policy. The salary-history notes describe the law in general terms; they aren't legal advice. |

**Integrity rule.** Deflecting a question is legitimate; lying in answer to it is not. You may decline to share your current pay, and you may wait to name a number. You may not invent a number, an offer or a deadline. Every timeline update you send a recruiter must be true when you send it.

---

## 0. The 60-second version

1. **Numbers set early become anchors.** Whoever names the first number pulls the final one toward it; that's one of the best-replicated findings in negotiation research (§1). Before the level is set, any number you give is anchored on the wrong thing.
2. **Current pay anchors to your past.** Expected pay named before leveling anchors to a level that isn't decided. Deflect both until the level is set, then talk in terms of *their* band for *that* level.
3. **Use the deflection ladder:** redirect to level → ask for the band → confirm you're inside it → name a number only when it's anchored on the target level's market, never on your current pay.
4. **Know the law where it helps you.** In California and a growing list of US states and cities, employers may not ask for your salary history, and you can ask for the pay scale. In India there's no such law, and current CTC is routinely asked; the ladder still works, but don't lie if payslips are required later.
5. **Synchronize before you start, not after the first offer.** List every loop's natural time to offer, how much each can speed up or slow down, and how long each offer stays open. Then pick one decision date (§5, `loop_sync.py`).
6. **Start the slowest process first, and slow the fastest one down early,** before it produces an exploding offer.
7. **Every update must be true.** "I'm in final rounds with two companies and expect decisions around [date]" is leverage. An invented offer is a career risk.

---

## 1. Why early numbers hurt

### 1.1 The research in two lines

Anchoring is the tendency of an initial number to pull later estimates toward it, even when the anchor is arbitrary ([Tversky & Kahneman, 1974](https://doi.org/10.1126/science.185.4157.1124)). In negotiation experiments, the party that made the first offer tended to get the better outcome, because the first offer anchored the final price ([Galinsky & Mussweiler, 2001](https://doi.org/10.1037/0022-3514.81.4.657)).

That second finding seems to say "name a number first". In comp negotiations, there's a catch: **the first number only helps you if it's well-informed.** On a first recruiter call you don't yet know the level, the band or the equity mix. So the right move is to make sure the first number on the table is anchored on *the target level's band*. That's either their band, or your number once you know it.

### 1.2 What each early number does

| Number | What it anchors to | Typical damage |
|---|---|---|
| **Your current pay** | Your past employer's pay scale | The offer becomes "current + X%", not "market for the level". This is worst when you're underpaid today |
| **Your expected pay, named before leveling** | A level that hasn't been decided | If it's high for L5, they may level you at L5 and say it's out of range; if it's low for L6, it caps the offer |
| **A range** | Its bottom | They hear the low end |
| **Their band, for the confirmed level** | The market for the role | This is the anchor you want |

### 1.3 The India specifics

In Indian tech hiring, "current CTC, expected CTC, notice period" is often the first question, and offers have historically been framed as a percentage hike on current CTC ⚠. Some companies ask for payslips or the last appraisal letter at the offer stage. That changes the tactics, not the principle:

- **You can decline to share current CTC early,** politely and repeatedly (Script 1). Many recruiters will proceed.
- **If a company's process requires proof of current pay before an offer,** don't misstate it. Share it with framing: "My current fixed pay is X. I'm not using it as the basis, because the role is a level up and my unvested equity of Y would be forfeited" (Script 3).
- **"Hike percentage" framing** is the anchor to resist. Move the conversation to the band for the level, and to what you'd forfeit by leaving (Folder 05.2).

---

## 2. The deflection ladder

Use the rungs in order. Most conversations end at rung 1 or 2.

| Rung | What you say | When to move to the next rung |
|---|---|---|
| **1. Redirect to level** | "Let's set the level first; comp follows from it." | They insist a number is needed to proceed |
| **2. Ask for the band** | "What's the band for L6 on this team?" | They won't share it |
| **3. Confirm range fit** | "If the L6 band is in line with the market for Staff roles in Bengaluru, we're in range." | They need a specific figure for a form |
| **4. A band-anchored number** | "For L6 here, I'm targeting total comp around the upper half of your band; I'll be specific once the level is confirmed." | It's still required as a number |
| **5. A market-anchored number** | A total-comp figure at the 75th percentile of the *target level's* market data, stated as total comp, with "depending on the mix" | — |

Two rules hold on every rung:

- **Always talk total comp,** not base. A base-only number gives them room to cut equity.
- **Never give a range.** A range hands them the bottom.

### 2.1 The US: salary-history bans and pay scales

California's Labor Code prohibits employers from seeking an applicant's salary history, and gives an applicant the right to the pay scale for the position on reasonable request (§ 432.3; [California Labor Commissioner FAQ](https://www.dir.ca.gov/dlse/California_Equal_Pay_Act.htm)). Many other states and cities have salary-history bans or pay-range posting rules, and the list keeps growing; counts differ between trackers, so check the rules for the job's location. Where they apply:

- **You don't have to answer** a salary-history question, and you can say so politely (Script 5).
- **You can ask for the pay scale.** In posting-rule jurisdictions, the job ad may already show it.
- **Volunteering is still allowed,** which is exactly why you shouldn't do it by reflex.

### 2.2 Where the band comes from if they won't say

- Posted ranges (in pay-transparency jurisdictions).
- Levels.fyi and similar self-reported data, filtered by company, level and city ([Levels.fyi comparison](https://www.levels.fyi/reports/examples/leveling-comparison-report.html)).
- Peers at the company, asked about *ranges for a level*, never their personal pay.
- Your other offers, as they arrive.

---

## 3. When a number is mandatory

Some forms and some recruiters can't proceed without a figure. Then:

1. **Make it a total-comp figure for the target level,** from market data at about the 75th percentile, not from your current pay.
2. **Attach the condition:** "for L6, depending on the mix of base, equity and sign-on".
3. **Write it down once,** in the form or email, and don't repeat it unprompted.
4. **If the form only accepts current CTC,** enter the true number. The ladder protects you from volunteering it, not from a hard requirement, and a misstatement here is the kind background checks find.

---

## 4. The timeline problem

### 4.1 Five loops never finish together by themselves

| Process type | Typical shape, recruiter call → offer ⚠ | What can be sped up | What can be slowed |
|---|---|---|---|
| Committee + team match (G) | 7–10+ weeks | Scheduling, committee review, team-match outreach | The onsite date |
| Debrief + bar raiser (A) | 4–6 weeks | Scheduling | The loop date |
| HM-driven team (N) | 4–7 weeks | Depends on the HM's urgency | The onsite date |
| Committee-like (U) | 5–8 weeks | Scheduling, review | The onsite date |
| Growth company (F) | 2–4 weeks, sometimes with a short offer deadline | Little | The final round; the deadline, if you ask |

The fast process produces an offer first, often with a short deadline. The slow one is often the one you want most. Left alone, you'll be asked to decide on F before G has even reached its committee.

### 4.2 The four moves

1. **Start the slowest process first.** Take G's recruiter call before F's.
2. **Slow the fast ones early,** by scheduling their final rounds later. It's much easier to schedule an onsite two weeks out than to stretch an exploding offer.
3. **Ask the slow ones to accelerate,** with a true reason: "I expect decisions from other processes around [date]." Recruiters can often expedite scheduling and reviews when a candidate has competing timelines ⚠.
4. **Ask for deadline extensions** when an offer arrives early. Asking is common and often works; there's a small, real risk that a company withdraws instead, so ask politely, give a date, and decide in advance what you'll do if they refuse (Script 8).

### 4.3 Practice order

Loops also have *practice value*. If you can, schedule a loop you care less about before the one you care most about. V schedules U's onsite before G's, so the G design rounds aren't V's first design rounds in years.

---

## 5. Finding the decision date

The question is: **is there a single week when every offer you care about is still open?**

For each loop you need four numbers: weeks to an offer if nothing changes; how much the recruiter says it can speed up; how much you can slow it (by scheduling later); and how long its offer stays open. Then each loop can be "alive" in a window, and the decision date has to sit inside every window. If one loop's window doesn't overlap with the others, that loop needs a specific ask: more days on its deadline, or more acceleration.

`loop_sync.py` does this arithmetic (§9). It adds loops in priority order and places the decision date half a week after the earliest feasible point, so the plan doesn't depend on every loop moving at its fastest. It also keeps every offer open at least 3 days past the decision date: an offer that expires on decision day leaves no room for one last question. Then it prints each loop's change and margin.

---

## 6. Candidate V's plan

**Before any asks.** V's honest estimates after the first recruiter calls, with priorities (1 = most wanted):

<!-- loops:start name=v-before-asks slack=0.5 expect=drop:F -->
| Loop | Priority | Weeks to offer | Can accelerate (w) | Can delay (w) | Offer valid (days) |
|---|---|---|---|---|---|
| G | 1 | 9.0 | 2.0 | 1.0 | 14 |
| A | 1 | 5.0 | 0.5 | 3.0 | 7 |
| N | 2 | 6.0 | 1.0 | 2.0 | 10 |
| U | 2 | 6.5 | 1.0 | 2.0 | 7 |
| F | 3 | 3.0 | 0.0 | 2.0 | 7 |
<!-- loops:end -->

The run (§9.3) puts the decision date at week 7.5. G must accelerate 1.5 weeks. A, N and U each move a little later (A's loop by about two weeks), so that every offer is still open at least 3 days after the decision date. F doesn't fit: even with its final round pushed back, its offer would expire about 11 days before the decision date, and the tool computes the ask that fixes it, a 21-day deadline instead of 7. That produces concrete asks, all true:

- **To G** (Script 6): "I expect decisions from other processes around [week 7.5]. Is there any way to expedite scheduling and the committee?"
- **To A** (a scheduling email like Script 7): hold the loop about two weeks later than first proposed.
- **To F** (Script 7): push the final round back two weeks, and when the offer comes, ask for a 21-day deadline instead of 7.

**After the asks.** F agreed to a later final round and a 21-day deadline; G's recruiter confirmed an expedited committee review:

<!-- loops:start name=v-after-asks slack=0.5 expect=all -->
| Loop | Priority | Weeks to offer | Can accelerate (w) | Can delay (w) | Offer valid (days) |
|---|---|---|---|---|---|
| G | 1 | 9.0 | 2.0 | 1.0 | 14 |
| A | 1 | 5.0 | 0.5 | 3.0 | 7 |
| N | 2 | 6.0 | 1.0 | 2.0 | 10 |
| U | 2 | 6.5 | 1.0 | 2.0 | 7 |
| F | 3 | 3.0 | 0.0 | 2.0 | 21 |
<!-- loops:end -->

Now all five land inside one window. **What V doesn't do:** tell F there's an offer from G (there isn't one yet), or tell G there's an exploding offer that requires an answer in a week (F's deadline is now 21 days).

---

## 7. Before → After: comp and timeline answers

#### S11 · "What's your current CTC?"

| Version | Answer |
|---|---|
| **Weak** | My current CTC is 1.4 crore, around 78 lakhs fixed plus RSUs. |
| **Strong** | I'd rather not anchor on my current package, because this role is a level up and the comp should follow the level. Once we've confirmed L6, I'll share what I need, and I'm confident we'll be in range. |

#### S12 · "What are you expecting?"

| Version | Answer |
|---|---|
| **Weak** | I'm expecting at least 2 crore, but I'm flexible on level if the number works. |
| **Strong** | It depends on the level and the mix. What's the band for L6 on this team? If it's in line with the market for Staff roles in Bengaluru, we'll be in range. |

#### S13 · "I need a number for the form."

| Version | Answer |
|---|---|
| **Weak** | Okay, put down 1.8 to 2.2 crore, whatever works for you. |
| **Strong** | Please put "open, to discuss after leveling". If it must be a number, put total comp in the upper half of your L6 band, depending on the mix, and I'll confirm specifics once the level is set. |

#### S14 · "If we make an offer, will you accept?"

| Version | Answer |
|---|---|
| **Weak** | Yes, definitely, you're my dream job and I'm not interviewing anywhere else. |
| **Strong** | This is one of the roles I'm most excited about. I'm in process with a few companies and I'll make one decision, around [date]. If the level and offer are right, I expect to say yes quickly. |

#### S15 · "How's the rest of your search going?"

| Version | Answer |
|---|---|
| **Weak** | Hopefully okay, I'm not sure if anything will come through, sorry for the slow updates. |
| **Strong** | Two processes are in final rounds and I expect decisions around [date]. I'd like yours to be part of that decision, so it would help if we could hold the committee date. |

#### S16 · The offer arrives with a 7-day deadline

| Version | Answer |
|---|---|
| **Weak** | I was wondering if maybe I could have a little more time, if that's okay? |
| **Strong** | Thank you, I'm excited about it. I have two processes finishing by [date], and I want to make one decision with full information. Could we set the deadline to [date]? |

#### S17 · "Can you just give me a ballpark?"

| Version | Answer |
|---|---|
| **Weak** | I guess somewhere between 1.5 and 2 crore is kind of what I'm thinking. |
| **Strong** | The ballpark I'd use is your L6 band. If you can share it, I'll tell you right away whether we're aligned. |

#### S18 · US role: "What do you make now?"

| Version | Answer |
|---|---|
| **Weak** | I currently earn 210k base plus about 150k in stock. |
| **Strong** | I'll keep my current pay out of it, and I understand you're not able to ask for it in California anyway. Could you share the pay scale for this position? |

---

## 8. Keeping five recruiters synchronized

- **One tracker:** loop, stage, next date, recruiter, what you've told them, deadline.
- **Weekly updates** to every active recruiter on the same day (Script 9). Each update is short and true.
- **Tell each recruiter only what's relevant and true:** stages and dates, not company names, unless naming them helps and you're comfortable.
- **Update the plan whenever a recruiter changes a date,** and rerun the arithmetic.

---

## 9. The listing: `loop_sync.py`

### 9.1 What it does

For each loop it computes the window in which that loop's offer can be alive with at least `margin` days to spare (default 3), given the honest acceleration, delay and offer validity. It adds loops in priority order while a common window exists, places the decision date `slack` weeks into it, and prints each loop's planned change and its margin in days. Loops that can't fit are listed with the specific ask that would make them fit.

To use it: copy the table from §6 into `loops.md`, fill in your own loops, and run `python -I loop_sync.py loops.md`. Re-run whenever a date changes.

### 9.2 Listing

<!-- include:loop_sync.py -->
```python
#!/usr/bin/env python3
"""loop_sync.py: plan a single decision date across several interview loops.

Reads every block like this from a Markdown file:

  <!-- loops:start name=my-search slack=0.5 -->
  | Loop | Priority | Weeks to offer | Can accelerate (w) | Can delay (w) | Offer valid (days) |
  |---|---|---|---|---|---|
  | G | 1 | 9.0 | 2.0 | 1.0 | 14 |
  | F | 3 | 3.0 | 0.0 | 2.0 | 7 |
  <!-- loops:end -->

'Weeks to offer' is your honest estimate if nothing changes. 'Can accelerate' and 'Can delay' are what the
recruiter has said is possible (expedited review, a later onsite). Priority 1 is most important.

It looks for a decision date D (in weeks from today) when every offer is still alive with at least 'margin'
days to spare (default 3), adding loops in priority order. Loops that can't fit are listed with the ask that
would make them fit (a deadline extension or more acceleration). D is placed 'slack' weeks after the earliest
feasible date, so the plan doesn't depend on every loop moving at its fastest.

Usage: python -I loop_sync.py FILE.md [--kb]
  --kb  check each block's expect=all or expect=drop:X,Y against the result.
Standard library only. Python 3.10+.
"""
import math
import re
import sys

START = re.compile(r"<!--\s*loops:start\s+(.*?)-->")
END = re.compile(r"<!--\s*loops:end\s*-->")
ROW = re.compile(r"^\|\s*(\w+)\s*\|\s*(\d+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*([\d.]+)\s*\|\s*(\d+)\s*\|\s*$")


def read_blocks(path):
    blocks, cur, fenced = [], None, False
    for line in open(path, encoding="utf-8"):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        if fenced:
            continue
        m = START.search(line)
        if m:
            cur = {"attrs": dict(re.findall(r"(\w+)=(\S+)", m.group(1))), "rows": []}
            continue
        if cur is not None and END.search(line):
            blocks.append(cur)
            cur = None
            continue
        if cur is not None:
            r = ROW.match(line.strip())
            if r:
                name, prio, w, acc, dly, valid = r.groups()
                cur["rows"].append({"loop": name, "prio": int(prio), "w": float(w), "acc": float(acc),
                                    "dly": float(dly), "life": int(valid) / 7, "valid": int(valid)})
    return blocks


def plan(block):
    a = block["attrs"]
    slack = float(a.get("slack", "0.5"))
    mgn = int(a.get("margin", "3")) / 7
    loops = sorted(block["rows"], key=lambda x: x["prio"])
    lo_i, hi_i = -math.inf, math.inf
    kept, dropped = [], []
    for x in loops:
        lo, hi = x["w"] - x["acc"], x["w"] + x["dly"] + x["life"] - mgn
        if max(lo_i, lo) <= min(hi_i, hi):
            lo_i, hi_i = max(lo_i, lo), min(hi_i, hi)
            kept.append(x)
        else:
            dropped.append(x)
    d = min(hi_i, lo_i + slack)
    print(f"plan {a.get('name', '?')}: decision date D = week {d:.1f} (feasible window {lo_i:.1f}-{hi_i:.1f}, "
          f"slack {slack:g} w, margin {round(mgn * 7)} d)")
    print(f"  {'loop':<5}{'prio':>5}{'natural':>9}{'planned':>9}  {'change':<26}{'alive until':>12}{'margin':>9}")
    for x in loops:
        if x not in kept:
            continue
        if x["w"] > d:
            p = d
        else:
            p = min(max(x["w"], d - x["life"] + mgn), d)
        p = min(max(p, x["w"] - x["acc"]), x["w"] + x["dly"])
        delta = p - x["w"]
        days = round(abs(delta) * 7)
        if days == 0:
            change = "none"
        elif delta < 0:
            change = f"accelerate {-delta:.1f} w (~{days} d)"
        else:
            change = f"delay {delta:.1f} w (~{days} d)"
        alive = p + x["life"]
        margin = round((alive - d) * 7)
        print(f"  {x['loop']:<5}{x['prio']:>5}{x['w']:>9.1f}{p:>9.1f}  {change:<26}{'wk ' + format(alive, '.1f'):>12}"
              f"{str(margin) + ' d':>9}")
    for x in dropped:
        latest = x["w"] + x["dly"] + x["life"]
        if latest < d + mgn:
            need = math.ceil((d - latest) * 7) + round(mgn * 7)
            ask = f"ask for {need} more days on the offer deadline (valid {x['valid']} -> {x['valid'] + need} d)"
        else:
            need = (x["w"] - x["acc"]) - d
            ask = f"needs {need:.1f} w more acceleration than offered"
        print(f"  DROPPED {x['loop']} (prio {x['prio']}): natural week {x['w']:.1f}; {ask}")
    return {x["loop"] for x in dropped}


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__)
        return 2
    kb = "--kb" in argv
    bad = []
    for block in read_blocks(argv[1]):
        dropped = plan(block)
        exp = block["attrs"].get("expect", "")
        want = set() if exp == "all" else set(exp.split(":", 1)[1].split(",")) if exp.startswith("drop:") else None
        if kb and want is not None and want != dropped:
            bad.append(block["attrs"].get("name", "?"))
        print()
    if kb:
        print("VERDICT: " + ("OK" if not bad else "FAIL " + ", ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 9.3 Output: V's two plans

<!-- run:loop_sync.py SELF --kb -->
```text
plan v-before-asks: decision date D = week 7.5 (feasible window 7.0-8.6, slack 0.5 w, margin 3 d)
  loop  prio  natural  planned  change                     alive until   margin
  G        1      9.0      7.5  accelerate 1.5 w (~10 d)        wk 9.5     14 d
  A        1      5.0      6.9  delay 1.9 w (~14 d)             wk 7.9      3 d
  N        2      6.0      6.5  delay 0.5 w (~4 d)              wk 7.9      3 d
  U        2      6.5      6.9  delay 0.4 w (~3 d)              wk 7.9      3 d
  DROPPED F (prio 3): natural week 3.0; ask for 14 more days on the offer deadline (valid 7 -> 21 d)

plan v-after-asks: decision date D = week 7.5 (feasible window 7.0-7.6, slack 0.5 w, margin 3 d)
  loop  prio  natural  planned  change                     alive until   margin
  G        1      9.0      7.5  accelerate 1.5 w (~10 d)        wk 9.5     14 d
  A        1      5.0      6.9  delay 1.9 w (~14 d)             wk 7.9      3 d
  N        2      6.0      6.5  delay 0.5 w (~4 d)              wk 7.9      3 d
  U        2      6.5      6.9  delay 0.4 w (~3 d)              wk 7.9      3 d
  F        3      3.0      4.9  delay 1.9 w (~14 d)             wk 7.9      3 d

VERDICT: OK
```

---

## 10. Word-for-word scripts

#### Script 1 · Verbal: deflecting "What's your current CTC?" (India)

```text
"I'd like to keep my current package out of the conversation for now. This role is a level
up from where I am, and I'd like the offer to reflect the level and the market, not my
current company's pay scale. Once we've confirmed the level, I'll be clear about what I need,
and I'm confident we'll find a number that works."
```

#### Script 2 · Verbal: deflecting "What are you expecting?"

```text
"It really depends on the level and the mix of base, equity and sign-on. Let's confirm the
level first. In the meantime, could you share the band for L6 on this team? If it's in line
with the market for Staff roles here, we'll be in range, and I'll get specific then."
```

#### Script 3 · Verbal: when current pay must be shared (a hard requirement)

```text
"Understood that it's required. My current fixed pay is [X], with variable of [Y] and RSUs
vesting at about [Z] a year. Two things to note alongside it: this role is a level up, so I'm
not using my current pay as the basis; and I'd be forfeiting about [unvested amount] in
unvested equity by leaving, which I'll want the offer to account for."
```

#### Script 4 · Email: asking for the band

```text
Subject: L6 band for [Role]

Hi [Recruiter name],

Thanks again for the call. As we discussed, I'd like to set the level before we talk
numbers. To make sure we aren't wasting each other's time, could you share the base,
equity and bonus ranges for L6 on this team in [city]? If they're in line with the market
for Staff roles, I'm confident we'll be aligned.

Best,
[Your Name]
```

#### Script 5 · Verbal: a salary-history question for a role in California

```text
"I'll keep my current pay out of the conversation; I understand California doesn't allow
employers to ask for it anyway. What would help me is the pay scale for this position, which
I believe you can share on request. Could you send it over?"
```

#### Script 6 · Email: asking a slow process to accelerate (G)

```text
Subject: Timeline for [Role]

Hi [Recruiter name],

I'm really enjoying the process with [team]. I want to share my timeline so we can plan:
I have two other processes in final rounds, and I expect decisions around [date].

I'd like [Company] to be part of that decision. Is there any way to expedite the onsite
scheduling and the committee review, so we land by then? If that isn't possible, please tell
me what timing is realistic, and I'll plan around it.

Best,
[Your Name]
```

#### Script 7 · Email: slowing a fast process (F)

```text
Subject: Scheduling the final round

Hi [Recruiter name],

Thanks for moving so quickly; I'm excited about the role. For the final round, would the
week of [date two weeks out] work? I'm finishing a few other conversations and want to give
your final round my full attention.

Also, so there are no surprises later: I'll be making one decision around [date]. If an
offer comes before then, I'd ask for a deadline of about three weeks.

Best,
[Your Name]
```

#### Script 8 · Verbal: asking for a deadline extension on an offer

```text
"Thank you, I'm genuinely excited about this. Here's where I am: I have two processes
finishing by [date], and I want to make one decision with full information, which is also
the best outcome for you, because it means if I say yes, it's a clear yes.

Could we set the deadline to [date]? If that's difficult, what's the latest date that works
on your side?"
```

#### Script 9 · Email: the weekly status update to every active recruiter

```text
Subject: Weekly update · [Your Name]

Hi [Recruiter name],

Quick update so you can plan:
• Your process: [stage, next date].
• Elsewhere: [N] processes in [stage], with decisions expected around [date].
• My decision date: around [date]. Nothing has changed / [what changed].

Anything you need from me this week?

[Your Name]
```

#### Script 10 · Verbal: "If we make an offer, will you accept?"

```text
"This is one of the roles I'm most excited about, and here's why: [one specific reason].
I'm in process with a few companies and I'll make one decision, around [date]. If the level
and the offer are right, I expect to say yes quickly. What would help me most is knowing the
level and the band as early as you can."
```

---

## 11. Probe chains

<details><summary><b>P1 · "Everyone shares current CTC. Why won't you?"</b></summary>

**Probe:** (Indian recruiter) "It's standard. Hiding it makes you look like you're hiding something."

**What they're testing:** whether you'll fold under social pressure, and whether you have a reason.

**Executor answer:** "Sorry, I didn't mean to hide anything. It's 1.4 crore."

**Staff/Principal answer:** "I'm not hiding it, and if your process requires it at the offer stage, I'll share it with documents. My point is about the basis: this is a level up, so I'd like the offer anchored on the L6 band rather than on my current company's scale. Can you share the band? Then we'll know quickly if we're aligned."

</details>

<details><summary><b>P2 · "We can't proceed without an expected number."</b></summary>

**Probe:** "The hiring manager won't schedule the loop until I have your expected CTC."

**What they're testing:** often a real process constraint; sometimes a negotiating tactic.

**Executor answer:** "Okay, put 2 crore. Is that too much?"

**Staff/Principal answer:** "Understood. Please put total comp in the upper half of your L6 band, depending on the mix. If the form needs a figure, it's [market-anchored total comp for L6], as total comp, conditional on L6. I'd rather not go lower than that and then have to explain a change later."

</details>

<details><summary><b>P3 · "That's above our band."</b></summary>

**Probe:** "Your number is above our L6 band."

**What they're testing:** whether your number was informed, and whether you'll collapse or walk.

**Executor answer:** "Oh, I'm flexible, whatever the band allows is fine."

**Staff/Principal answer:** "Thanks for telling me. Where does the band top out, in total comp? If the gap is in base, there may be room in equity or sign-on. And I'd rather be at the top of L6 than have the number push us to talk about L5. Let's see where the loop lands and talk then."

</details>

<details><summary><b>P4 · "Who else are you talking to?"</b></summary>

**Probe:** "Which companies are you in process with?"

**What they're testing:** competitive intelligence, and how real your timeline is.

**Executor answer:** "Uh, a few places, I'd rather not say, it's still early."

**Staff/Principal answer:** "A few large tech companies and one growth-stage fintech, for Staff roles. Two are in final rounds, with decisions around [date]. I'm happy to share more specifics as offers come in, if it helps us plan."

</details>

<details><summary><b>P5 · "The offer expires Friday."</b></summary>

**Probe:** (Loop F) "Our offers are valid for seven days. That's policy."

**What they're testing:** whether the deadline is real, and whether you'll take an early offer under pressure.

**Executor answer:** "Okay, I'll try to decide by Friday."

**Staff/Principal answer:** "I understand. I told you at the start that I'd make one decision around [date], and I'd ask you to hold the offer until then. If policy truly can't move, I'll need to decline, which I'd hate to do. Can you check whether an exception is possible?" (Say the last part only if you'd really decline.)

</details>

<details><summary><b>P6 · "Can you speed up your other processes instead?"</b></summary>

**Probe:** "We can't extend. Ask the others to hurry."

**What they're testing:** whether you'll do the work to synchronize, and whether your timeline is real.

**Executor answer:** "I'll try, but I don't think they will."

**Staff/Principal answer:** "I already have: one has expedited its committee and one has scheduled earlier. The earliest realistic date is [date]. That's [N] days past your deadline. Could you meet me there?"

</details>

<details><summary><b>P7 · "What would it take for you to accept today?"</b></summary>

**Probe:** "If we improve the number, would you sign today?"

**What they're testing:** whether money can buy you out of your process.

**Executor answer:** "Maybe, if it's a lot more."

**Staff/Principal answer:** "I appreciate it. The number matters, but my decision date is about comparing full offers, including level and team, not just this one. I'll keep my word on [date]. If you can hold the offer until then, you'll have a decisive answer."

</details>

<details><summary><b>P8 · "Your timeline keeps changing."</b></summary>

**Probe:** "Last week you said decisions by the 10th, now it's the 17th."

**What they're testing:** reliability: are your updates true?

**Executor answer:** "Sorry, things just keep slipping on the other side."

**Staff/Principal answer:** "Yes, one committee date moved by a week, and I told you the same day it happened. My decision date is now the 17th, and that's firm unless I tell you otherwise. I'll keep sending you the weekly update."

</details>

---

## 12. Checklist

**Comp questions**
- [ ] Your answers for current CTC, expected CTC and "a number for the form", rehearsed (Scripts 1–3).
- [ ] A market-anchored total-comp figure for the target level, in case it's mandatory (§3).
- [ ] The laws for each role's location: salary-history bans and pay-scale rights (§2.1).
- [ ] Never a range; always total comp.

**Timelines**
- [ ] All loops in one table, with honest estimates (§6).
- [ ] `loop_sync.py` run; asks drafted for each change (Scripts 6–8).
- [ ] Slowest process started first; fastest final round scheduled late.
- [ ] Weekly true updates to every recruiter (Script 9).

---

## 13. References

- Tversky, A. & Kahneman, D. (1974). Judgment under uncertainty: heuristics and biases. *Science* 185(4157), 1124–1131. [doi:10.1126/science.185.4157.1124](https://doi.org/10.1126/science.185.4157.1124).
- Galinsky, A. D. & Mussweiler, T. (2001). First offers as anchors: the role of perspective-taking and negotiator focus. *Journal of Personality and Social Psychology* 81(4), 657–669. [doi:10.1037/0022-3514.81.4.657](https://doi.org/10.1037/0022-3514.81.4.657).
- California salary-history ban and pay-scale rights (Labor Code § 432.3): [California Labor Commissioner, Equal Pay Act FAQ](https://www.dir.ca.gov/dlse/California_Equal_Pay_Act.htm).
- Market data by level: [Levels.fyi](https://www.levels.fyi/reports/examples/leveling-comparison-report.html).
- Offers, mixes and negotiation rounds: Folder 05 of this KB.
