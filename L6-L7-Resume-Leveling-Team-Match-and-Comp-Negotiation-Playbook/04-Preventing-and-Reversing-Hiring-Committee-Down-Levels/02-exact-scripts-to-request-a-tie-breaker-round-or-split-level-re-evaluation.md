# 04.2 · Exact scripts to request a tie-breaker round or a split-level re-evaluation

> Folder 04 · Preventing and reversing hiring-committee down-levels · File 2 of 2 · [KB home](../README.md) · Previous: [04.1 Why committees down-level](01-why-hiring-committees-down-level-and-how-packets-are-debated.md) · Next folder: [05.1 Deconstructing FAANG comp](../05-Compensation-Structure-and-Multi-Offer-Negotiation-Scripts/01-deconstructing-faang-comp-base-rsu-vesting-frontloading-sign-on-and-refreshers.md)

<!-- lint-pack: hc -->

| | |
|---|---|
| **Reader** | A candidate whose offer, or expected offer, came back one level below the target, deciding whether to accept, ask for a re-evaluation, or walk |
| **Running exhibit** | Candidate V at Loop A: targeted L7, offered L6, with Loop G's L6 offer still open (§6) |
| **Listing** | `downlevel_ev.py`: compares accepting, asking and walking, as expected four-year total comp, downside, and the chance of reaching L7 (§9) |
| **Verification** | The listing is byte-identical to the file that was run. §9.3 is a real run: with Loop G as a fallback, asking for the tie-breaker has the best expected value; without a fallback, asking still wins on expectation, but its downside is staying put. The 8 pairs in §7 are checked with `script_lint.py` (hc pack). |
| **Marks** | ⚠ = field practice, not published policy. Probabilities and comp in the examples are illustrative placeholders, not data. |

**Integrity rule.** A re-evaluation request offers new, true evidence and asks for a fair process. It never disputes an interviewer's honesty, never invents a competing offer, and never threatens what you won't do.

---

## 0. The 60-second version

1. **First, understand.** Ask which areas read below the target, and whether the packet was split or consistently lower (04.1 Script 8). You can't ask for the right remedy without this.
2. **Push only when the case is narrow:** a split packet, one or two swing rounds, and new evidence the committee didn't have. Don't push when several rounds consistently read lower.
3. **Ask for a mechanism, not a different answer:** an additional round in the area of the split, or a re-review with specific new information.
4. **Never argue with the feedback.** Re-litigating an interview makes the committee defend its interviewer.
5. **Have a fallback before you ask.** A request with a live alternative is low-risk; without one, the downside is real (§6).
6. **If you accept the lower level, negotiate the terms:** top of the band, sign-on, and a written commitment on when your level will be reviewed.
7. **Use `downlevel_ev.py`** to decide with numbers rather than pride.

---

## 1. Your options when the level comes back lower

| Option | When it fits | Script |
|---|---|---|
| **Accept, and negotiate the terms** | The gap was consistent across rounds, or you strongly prefer this company | Scripts 6–7 |
| **Ask for a re-review with new information** | The packet missed true evidence you can name specifically | Script 3 |
| **Ask for a tie-breaker round** | The packet was split, with one or two swing rounds in one area | Script 2 |
| **Ask the hiring manager to support a re-evaluation** | The HM saw the target level in your conversations | Script 4 |
| **Share a competing offer at the higher level, honestly** | You have one, in writing | Script 5 |
| **Decline, and leave the door open** | A better alternative exists, or the level matters more than the company | Script 8 |

---

## 2. What's realistic, by process type ⚠

| Process type | Re-review with new info | Additional round | What usually happens |
|---|---|---|---|
| **Committee** (Google-style) | Sometimes, especially with the recruiter's or HM's support | Sometimes, when the committee itself sees a split | The recruiter decides whether to take it back to the committee |
| **Bar-raiser debrief** (Amazon-style) | Rare once the debrief has decided | Possible, but uncommon | A down-level to the lower req is common; re-interviewing for the higher level later is the usual path |
| **Candidate review** (Meta-style) | Sometimes reported | An extra round is sometimes reported for level questions | Practices vary and change |
| **HM-driven** | Easiest: the HM can often decide | The HM may simply arrange one | Depends on the HM's conviction (03.1) |

The pattern under all of them: **the recruiter is the gatekeeper.** Your first job is to give the recruiter a request that's easy to take forward: specific, short, evidence-based and polite.

---

## 3. When to push, and when not to

| Push when | Don't push when |
|---|---|
| The packet was **split**, and you can name the swing rounds | Several critical rounds consistently read lower |
| You have **specific new evidence** the committee didn't hear | Your "new evidence" is a restatement of the same stories |
| The **hiring manager** saw the target level | The HM is lukewarm |
| You have a **competing offer at the higher level**, in writing | The competing "offer" is a conversation in progress |
| You have a **fallback** you'd be happy with | Losing this offer would leave you worse off than you can accept |

Use `packet_sim.py` (04.1) with what the recruiter tells you. If the model says one additional round in the same area would change the outcome, a tie-breaker is the right ask. If it says an additional round wouldn't be enough, as in V's unprepared Loop G packet, a tie-breaker alone won't fix it, and a re-review would need new evidence that changes one of the existing reads.

---

## 4. The anatomy of a request

A good request has six parts, in this order, in under 200 words:

| # | Part | Example |
|---|---|---|
| 1 | **Thanks and acceptance of the process** | "Thank you for the offer and for the work on the packet." |
| 2 | **What you understood** | "I understand the leadership rounds read L6 while design and the deep dive read L7." |
| 3 | **The specific ask** | "Would the committee consider one additional leadership-focused round?" |
| 4 | **The new evidence** | "There's one cross-org example I didn't get to tell: [one sentence]." |
| 5 | **True context** | "I have another offer at L6 that expires on [date]; I'd like to make my decision with this one resolved." |
| 6 | **A graceful fallback** | "If that isn't possible, I understand, and I'd like to discuss the L6 offer." |

What you leave out matters as much:

- **No disputes:** not "the interviewer misunderstood me", not "the question was unfair".
- **No ultimatums:** "I'll withdraw unless…" ends the conversation, and it's almost never true.
- **No adjectives about yourself:** let the evidence do it.

---

## 5. If you accept the lower level

Accepting a down-level can be the right call. Accept it **on terms:**

| Ask | Why it's reasonable |
|---|---|
| **Top of the band** for the offered level | The packet showed signal above that level; pay should reflect where in the band you are |
| **A larger sign-on or initial equity** | It bridges the gap to what the higher level would have paid |
| **A written note of the scope you'll own** (03.2 Script 6) | It becomes the evidence for your first promotion case |
| **A stated review point** for the level, such as "after the first full performance cycle" | Not binding at most companies ⚠, but writing it down makes it real for your manager |

Then do the work that makes the promotion case: the scope note from 03.3 is your first-year plan.

---

## 6. Candidate V's decision at Loop A

Loop A's debrief came back at L6, not L7. The recruiter shared that the design round and the deep dive read L7, and the bar-raiser and hiring-manager rounds read L6: exactly the split in 04.1 §6.3. Loop G's L6 offer is still open for two more weeks.

V estimates four paths. The comp figures are illustrative average annual total comp in ₹ lakh, including assumed refreshers (Folder 05 builds them properly); the promotion probabilities are V's own judgment, not data.

<!-- paths:start name=v-paths -->
| Path | TC by level | Start level | Promo p/yr | Promo from year |
|---|---|---|---|---|
| A-L6 | L6=165, L7=260 | L6 | 0.15 | 2 |
| A-L7 | L7=260, L8=380 | L7 | 0.05 | 3 |
| G-L6 | L6=190, L7=300 | L6 | 0.20 | 2 |
| STAY | L6=146, L7=210 | L6 | 0.10 | 2 |
<!-- paths:end -->

**With Loop G as a fallback.** V's estimate: a 35% chance the tie-breaker succeeds. If it fails, V takes G rather than A-L6, because G pays more at L6:

<!-- options:start name=v-with-g-open paths=v-paths years=4 expect=best:ask-tiebreak-keep-g -->
| Option | Outcomes |
|---|---|
| accept-a-l6 | 1.00 A-L6 |
| take-g-l6 | 1.00 G-L6 |
| ask-tiebreak-no-fallback | 0.35 A-L7; 0.60 A-L6; 0.05 STAY |
| ask-tiebreak-keep-g | 0.35 A-L7; 0.65 G-L6 |
<!-- options:end -->

**Without a fallback,** for comparison: if G didn't exist, a failed or withdrawn request would leave V with A-L6 or, in the rare withdrawal case, staying put:

<!-- options:start name=v-without-g paths=v-paths years=4 expect=best:ask-tiebreak-no-fallback -->
| Option | Outcomes |
|---|---|
| accept-a-l6 | 1.00 A-L6 |
| ask-tiebreak-no-fallback | 0.35 A-L7; 0.60 A-L6; 0.05 STAY |
| stay | 1.00 STAY |
<!-- options:end -->

The run (§9.3) shows the shape of the decision:

- **With G open,** asking for the tie-breaker while keeping G alive has the best expected value, and its worst case is G at L6, which V would be happy with. That's the situation to engineer: **ask from strength.**
- **Without G,** asking still has a higher expected value than accepting, but the downside is staying where V is. Ask only if you could live with that, and ask politely enough that withdrawal stays rare.
- **Taking G outright** beats accepting A at L6. A down-level at one company is a reason to compare, not a reason to accept by default.

V sends Script 2 to Loop A's recruiter, keeps Loop G informed with a true timeline (02.2 Script 9), and sets a decision date inside G's deadline.

---

## 7. Before → After: responding to a down-level

#### S71 · The first reaction

| Version | Answer |
|---|---|
| **Weak** | That's unfair, the bar raiser was clearly biased against my background. |
| **Strong** | Thank you for telling me. Which rounds read below L7, and was it a split or consistent? I'll come back to you within a day. |

#### S72 · Asking for a tie-breaker

| Version | Answer |
|---|---|
| **Weak** | You must give me another interview, the decision is wrong. |
| **Strong** | Since design and the deep dive read L7 and the leadership rounds read L6, would the committee consider one additional leadership-focused round? |

#### S73 · Using a competing offer

| Version | Answer |
|---|---|
| **Weak** | I have multiple offers at L7, so match it or I walk. |
| **Strong** | I have a written offer at the higher level from another company, which expires on the 14th. I'd like to make my decision with this level question resolved. |

#### S74 · New evidence

| Version | Answer |
|---|---|
| **Weak** | I guess maybe I didn't explain things well, sorry, I was kind of nervous. |
| **Strong** | There's one cross-org example I didn't get to tell: the config-safety policy that now governs how about 2,000 engineers ship. I'd welcome the chance to walk an interviewer through it. |

#### S75 · Accepting the lower level

| Version | Answer |
|---|---|
| **Weak** | Okay, I accept, whatever level you think is fine. |
| **Strong** | I'm inclined to accept at L6 if we can place me at the top of the band, add a sign-on to bridge the gap, and agree in writing when the level will be reviewed. |

#### S76 · When the decision is final

| Version | Answer |
|---|---|
| **Weak** | That's ridiculous, I insist you take it back to the committee. |
| **Strong** | Understood, and thank you for trying. Let's talk about the L6 offer, then: I'd like to understand where in the band it sits. |

#### S77 · Asking the hiring manager for support

| Version | Answer |
|---|---|
| **Weak** | Can you just overrule the committee for me? I really need this. |
| **Strong** | You saw the cross-org work in our conversation. If you believe it reflects L7, would you be willing to say so to the recruiter in support of an additional round? |

#### S78 · Declining

| Version | Answer |
|---|---|
| **Weak** | Honestly your process is broken, so I'm out. |
| **Strong** | Thank you for the offer. I've decided to accept another role at the level I was targeting. I'd be glad to talk again in the future, and I hope our paths cross. |

---

## 8. After the request

- **Give it a deadline that's true:** tied to your real decision date.
- **Don't send follow-up arguments.** One clean request is stronger than three emails.
- **If a tie-breaker happens,** prepare it like the swing round it is: the cross-org story with names, dissent and numbers, and a scope line at the end (04.1 Script 1).
- **If the answer is no,** move straight to the terms (§5) or to your alternative. Don't reopen it.

---

## 9. The listing: `downlevel_ev.py`

### 9.1 What it does

For each **path** (a company at a starting level, with your estimate of yearly promotion chances), it computes expected total comp over the horizon. For each **option**, a weighted mix of paths that represents how a request could end, it prints:

- the expected total;
- the **downside** (the worst path you could end up on);
- the chance of being at L7 or above by the final year.

The probabilities are your judgment; the tool only keeps the arithmetic honest. Use ranges: if the decision flips between 25% and 45%, it's a close call, and the downside should decide.

To use it: copy the two table formats from §6 into `decision.md`, use your own offers (05.1 helps estimate annual totals) and run `python -I downlevel_ev.py decision.md`.

### 9.2 Listing

<!-- include:downlevel_ev.py -->
```python
#!/usr/bin/env python3
"""downlevel_ev.py: compare accepting a down-level, asking for a re-evaluation, and your alternatives.

Reads two kinds of block from a Markdown file:

  <!-- paths:start name=my-paths -->
  | Path | TC by level | Start level | Promo p/yr | Promo from year |
  |---|---|---|---|---|
  | A-L6 | L6=165, L7=260 | L6 | 0.15 | 2 |
  <!-- paths:end -->

  <!-- options:start name=my-choice paths=my-paths years=4 -->
  | Option | Outcomes |
  |---|---|
  | accept-a-l6 | 1.00 A-L6 |
  | ask-keep-g | 0.35 A-L7; 0.65 G-L6 |
  <!-- options:end -->

TC is total comp per year in any one currency unit. A path promotes one level with probability p in each year
from 'Promo from year' on; expected TC in a year mixes the two levels' TC by the chance of having been promoted.
Each option is a set of weighted outcomes (weights sum to 1): your honest guess at how a request could end.
For each option it prints the expected total over the horizon, the chance of being at L7 or above by the
last year, and the downside (the worst outcome's total). The path summary at the top uses a 4-year horizon.
The probabilities are your judgment; the tool only keeps the arithmetic honest.
Usage: python -I downlevel_ev.py FILE.md [--kb]
  --kb  check each options block's expect=best:OPTION against the result.
Standard library only. Python 3.10+.
"""
import re
import sys

START = re.compile(r"<!--\s*(paths|options):start\s+(.*?)-->")
END = re.compile(r"<!--\s*(paths|options):end\s*-->")
LEVELS = ["L4", "L5", "L6", "L7", "L8", "L9"]


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def read(path):
    paths, options, cur, fenced = {}, [], None, False
    for line in open(path, encoding="utf-8"):
        if line.lstrip().startswith("```"):
            fenced = not fenced
        if fenced:
            continue
        m = START.search(line)
        if m:
            cur = {"kind": m.group(1), "attrs": dict(re.findall(r"(\w+)=(\S+)", m.group(2))), "rows": []}
            continue
        if cur is not None and END.search(line):
            if cur["kind"] == "paths":
                for name, tc, start, p, k in cur["rows"]:
                    table = {lv.strip(): float(v) for lv, v in (x.split("=") for x in tc.split(","))}
                    paths[name] = {"tc": table, "start": start, "p": float(p), "k": int(k)}
            else:
                options.append(cur)
            cur = None
            continue
        if cur is not None and line.startswith("|") and not set(line.strip()) <= set("|-: "):
            c = cells(line)
            if c[0] not in ("Path", "Option"):
                cur["rows"].append(c)
    return paths, options


def path_value(pth, years):
    lv = pth["start"]
    up = LEVELS[LEVELS.index(lv) + 1]
    total, promoted = 0.0, 0.0
    for y in range(1, years + 1):
        promoted = 1 - (1 - pth["p"]) ** max(0, y - pth["k"] + 1)
        total += (1 - promoted) * pth["tc"][lv] + promoted * pth["tc"][up]
    return total, promoted, up


def evaluate(block, paths):
    a = block["attrs"]
    years = int(a.get("years", "4"))
    print(f"options {a.get('name', '?')} (horizon {years} y; TC in the paths' units)")
    print(f"  {'option':<26}{'expected':>10}{'downside':>10}  by year {years}")
    results = []
    for name, outcomes in block["rows"]:
        parts = [(float(w), p.strip()) for w, p in (o.strip().split(None, 1) for o in outcomes.split(";"))]
        if abs(sum(w for w, _ in parts) - 1.0) > 1e-6:
            raise ValueError(f"weights for {name} must sum to 1")
        exp = worst = 0.0
        worst = None
        reach = 0.0
        for w, pname in parts:
            val, promoted, _ = path_value(paths[pname], years)
            exp += w * val
            worst = val if worst is None else min(worst, val)
            start = paths[pname]["start"]
            reach += w * (1.0 if LEVELS.index(start) >= 3 else promoted)
        results.append((exp, name))
        print(f"  {name:<26}{exp:>10.1f}{worst:>10.1f}  {100 * reach:5.1f}% at L7 or above")
    best = max(results)[1]
    print(f"  best expected: {best}")
    return best


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__)
        return 2
    kb = "--kb" in argv
    paths, options = read(argv[1])
    print("paths (expected total, chance promoted by the last year):")
    for name, p in paths.items():
        val, promoted, up = path_value(p, 4)
        print(f"  {name:<8} starts {p['start']}, {100 * promoted:4.1f}% at {up} by year 4, expected {val:.1f}")
    print()
    bad = []
    for block in options:
        best = evaluate(block, paths)
        exp = block["attrs"].get("expect", "")
        if kb and exp.startswith("best:") and exp.split(":", 1)[1] != best:
            bad.append(block["attrs"].get("name", "?"))
        print()
    if kb:
        print("VERDICT: " + ("OK" if not bad else "FAIL " + ", ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 9.3 Output: V's decision

<!-- run:downlevel_ev.py SELF --kb -->
```text
paths (expected total, chance promoted by the last year):
  A-L6     starts L6, 38.6% at L7 by year 4, expected 737.3
  A-L7     starts L7,  9.8% at L8 by year 4, expected 1057.7
  G-L6     starts L6, 48.8% at L7 by year 4, expected 875.3
  STAY     starts L6, 27.1% at L7 by year 4, expected 619.9

options v-with-g-open (horizon 4 y; TC in the paths' units)
  option                      expected  downside  by year 4
  accept-a-l6                    737.3     737.3   38.6% at L7 or above
  take-g-l6                      875.3     875.3   48.8% at L7 or above
  ask-tiebreak-no-fallback       843.6     619.9   59.5% at L7 or above
  ask-tiebreak-keep-g            939.1     875.3   66.7% at L7 or above
  best expected: ask-tiebreak-keep-g

options v-without-g (horizon 4 y; TC in the paths' units)
  option                      expected  downside  by year 4
  accept-a-l6                    737.3     737.3   38.6% at L7 or above
  ask-tiebreak-no-fallback       843.6     619.9   59.5% at L7 or above
  stay                           619.9     619.9   27.1% at L7 or above
  best expected: ask-tiebreak-no-fallback

VERDICT: OK
```

---

## 10. Word-for-word scripts

#### Script 1 · Verbal: the next-day call to the recruiter

```text
"Thanks for yesterday's call; I've had time to think. First, I appreciate the offer, and I
understand how the packet came out: design and the deep dive at L7, the bar-raiser and
hiring-manager rounds at L6.

I'd like to ask for one thing before I decide. Since the split is in the leadership area,
would the committee consider one additional leadership-focused round? There's a cross-org
example I didn't get to tell, and I think it's the evidence that's missing.

I have another offer that expires on the 14th, so I'd need to know by the 10th. If an
additional round isn't possible, I understand, and I'd like to talk about the L6 offer."
```

#### Script 2 · Email: requesting a tie-breaker round

```text
Subject: Request: one additional round before I decide

Hi [Recruiter name],

Thank you for the offer, and for walking me through the outcome. I understand the design and
deep-dive rounds read L7, and the bar-raiser and hiring-manager rounds read L6.

I'd like to ask whether the committee would consider one additional round focused on
leadership and cross-org influence. There's one example I didn't get to tell that I believe
is the missing evidence: I wrote the cross-org RFC that set config-safety policy for about
2,000 engineers, and led its adoption through dissent from two org leads. I'd welcome an
interviewer probing it in depth.

For timing: I have another offer at L6 that expires on [date], so I'd need to know by
[date]. If an additional round isn't possible, I understand, and I'd like to discuss the L6
offer.

Thank you for considering it.
[Your Name]
```

#### Script 3 · Email: requesting a re-review with new information

```text
Subject: Additional information for the committee, if helpful

Hi [Recruiter name],

Thank you for explaining the outcome. If the process allows it, I'd like to offer one piece
of information the committee didn't have, because it speaks directly to the area that read
below the target level.

[Two or three sentences of specific, true evidence: the decision, the scope, the outcome.
Include names of roles, numbers, and what changed.]

I'm happy to be interviewed on it, or to provide a reference who saw it firsthand. If a
re-review isn't possible, I understand completely.

Best,
[Your Name]
```

#### Script 4 · Verbal: asking the hiring manager for support

```text
"I wanted to talk to you directly about the level. The packet came back at L6, with the
leadership rounds as the split. In our conversation, we spent a lot of time on the
cross-org work. If you believe it reflects L7, would you be willing to say so to the
recruiter, in support of an additional round? If you don't, I'd really value hearing why;
it will help me either way."
```

#### Script 5 · Email: sharing a competing offer at a higher level, honestly

```text
Subject: Context for the level decision

Hi [Recruiter name],

In the interest of transparency: I've received a written offer from another company at
[the higher level / a level they describe as equivalent to L7], which expires on [date]. I'm
happy to share the offer letter's level and date if that's useful.

I'm not asking you to match a title. I'm sharing it because it suggests the higher level is
supportable, and I'd prefer to make my decision with your level question resolved. Is an
additional round or a re-review possible before [date]?

Best,
[Your Name]
```

(Send this only with a real, written offer. Never describe a conversation in progress as an offer.)

#### Script 6 · Verbal: accepting the lower level, on terms

```text
"I've thought about it, and I'm inclined to accept at L6. Three things would make it an easy
yes. First, placement at the top of the L6 band, given that half the packet read L7. Second,
a sign-on that bridges part of the gap to what the higher level would have paid. Third, a
written note of the scope I'd own and when my level would be reviewed, so my manager and I
start with the same expectation. Can we work on those?"
```

#### Script 7 · Email: confirming the review commitment in writing

```text
Subject: Confirming the scope and review timing

Hi [Manager name],

I'm excited to accept. To make sure we start with the same expectations, here's my
understanding of what we agreed:
• Scope: [owning X across Y teams].
• Level review: after my first full performance cycle, based on that scope.

I know a level review isn't a promise of an outcome. I just want us both to have it written
down. Does this match your understanding?

Best,
[Your Name]
```

#### Script 8 · Email: declining, and keeping the door open

```text
Subject: Thank you, and my decision

Hi [Recruiter name],

Thank you for the offer, and for your work throughout the process. I've decided to accept
another role at the level I was targeting. It was a difficult decision; I came away very
impressed by [team / specific person or problem].

I'd be glad to stay in touch. If a role at [the higher level] opens on [team] in the future,
I'd welcome hearing from you.

Best,
[Your Name]
```

#### Script 9 · Verbal: when the recruiter says the decision is final

```text
"Understood, and thank you for asking. Then let's talk about the L6 offer. I'd like to know
where it sits in the band, and whether there's room on the sign-on, given the split in the
packet. I'll make my decision by [date]."
```

#### Script 10 · Verbal: the tie-breaker round itself, opening

```text
"Thank you for making time. I understand this round is about leadership and cross-org
influence, so let me give you the example I think matters most, and please push on any part
of it. It's the config-safety policy: why no single team could fix the problem, who
disagreed and why, how I got to a decision, and what happened over the following two years."
```

---

## 11. Probe chains

<details><summary><b>P1 · "Why should the committee look at this again?"</b></summary>

**Probe:** (Recruiter) "Committees rarely revisit decisions. What's different?"

**What they're testing:** whether you have new evidence, or just disappointment.

**Executor answer:** "Because I really think I deserve L7."

**Staff/Principal answer:** "Two things are different from what they reviewed. The packet split exactly on the leadership rounds, and there's a cross-org example I didn't tell that speaks directly to that. I'm asking for a chance to show it, not for a different reading of the same evidence."

</details>

<details><summary><b>P2 · "Was the bar raiser unfair?"</b></summary>

**Probe:** (Recruiter, testing) "Do you feel the bar raiser was unfair to you?"

**What they're testing:** whether you'll blame the interviewer, which would end the request.

**Executor answer:** "Honestly, yes, I don't think they understood my work."

**Staff/Principal answer:** "No. I think I chose the wrong story for that round. I told a strong Staff story when the round was looking for cross-org scope. That's on me, and it's why I'm asking for one more round rather than a different reading."

</details>

<details><summary><b>P3 · "If we can't do another round, will you accept L6?"</b></summary>

**Probe:** "Hypothetically, if the answer is no, what would you do?"

**What they're testing:** whether your request is a bluff.

**Executor answer:** "I'd have to walk away."

**Staff/Principal answer:** "I'd consider the L6 offer seriously, alongside the other offer I have, and decide by [date]. The level matters to me, but so does the team. I'd want to talk about where the offer sits in the band."

</details>

<details><summary><b>P4 · "Other candidates accept the level they're given."</b></summary>

**Probe:** "Most people in your position just accept L6."

**What they're testing:** social pressure; whether you'll feel you're being difficult.

**Executor answer:** "Okay, sorry, I didn't mean to cause trouble."

**Staff/Principal answer:** "I understand, and I'm not trying to make this hard. A narrow split with evidence that wasn't heard seems worth one request. If the answer is no, I'll respect it."

</details>

<details><summary><b>P5 · "Can you show me the other offer?"</b></summary>

**Probe:** "You mentioned an offer at a higher level. Can we see it?"

**What they're testing:** whether the leverage is real.

**Executor answer:** "I'd rather not share it."

**Staff/Principal answer:** "Yes, I can share the page with the level and expiration date; I'll remove the comp figures, if that's acceptable." (If you can't show it, you shouldn't have mentioned it.)

</details>

<details><summary><b>P6 · "We'll level you up after six months if you perform."</b></summary>

**Probe:** "Accept L6, and we'll look at L7 after six months."

**What they're testing:** whether you understand how promises at offer stage work.

**Executor answer:** "Great, that works, thank you."

**Staff/Principal answer:** "I appreciate that. Could we write it down: the scope I'd own, and that my level will be reviewed after the first full cycle? I know it isn't a guarantee of the outcome, but having it in writing makes sure my future manager has the same understanding."

</details>

<details><summary><b>P7 · "Why does the level matter so much? The pay difference is small."</b></summary>

**Probe:** "The L6 offer is generous. Why push on the title?"

**What they're testing:** your reasoning, and your priorities.

**Executor answer:** "It's about respect."

**Staff/Principal answer:** "It's about scope and trajectory more than title. The level sets the problems I'll be given and the starting point for the next promotion, and the comp difference compounds through refreshers. That said, I'm open to L6 on the right terms; I've told you what those are."

</details>

<details><summary><b>P8 · (The tie-breaker) "Tell me something you haven't told the others."</b></summary>

**Probe:** (Tie-breaker interviewer) "I've read the packet. Give me something new."

**What they're testing:** whether the "new evidence" exists, at the higher level.

**Executor answer:** A retelling of the same project from a different angle.

**Staff/Principal answer:** The cross-org story told at L7 depth: the problem no single org owned, the two org leads who disagreed and why, the options document, how the decision was made and held, the adoption numbers, and what V would do differently. End with the scope line (04.1 Script 1).

</details>

---

## 12. Checklist

- [ ] Understand before reacting: which rounds, split or consistent (04.1 Script 8).
- [ ] Run `packet_sim.py` with what you heard; identify the swing rounds.
- [ ] Check the push criteria (§3); make sure you have a fallback.
- [ ] Run `downlevel_ev.py` with your offers and honest probabilities.
- [ ] Send one request, in the six-part shape, under 200 words (Script 2 or 3).
- [ ] Ask the hiring manager for support only if they saw the target level (Script 4).
- [ ] If accepting, negotiate the terms and write down the review point (Scripts 6–7).
- [ ] If declining, leave the door open (Script 8).

---

## 13. References

- The Bar Raiser's role in the hiring decision: [About Amazon](https://www.aboutamazon.com/news/workplace/amazon-bar-raiser).
- How packets are read and why splits resolve downward: [04.1 of this KB](01-why-hiring-committees-down-level-and-how-packets-are-debated.md).
- Comp by level and the comp model behind the path figures: [05.1 of this KB](../05-Compensation-Structure-and-Multi-Offer-Negotiation-Scripts/01-deconstructing-faang-comp-base-rsu-vesting-frontloading-sign-on-and-refreshers.md).
- Telling the cross-org story at L7 depth: [Behavioral playbook, Folder 03](../../Staff-Principal-Behavioral-L7-Playbook/03-Influence-Without-Authority-and-Cross-Org-Alignment/01-resolving-architectural-wars-between-competing-principal-engineers.md).
