# 05.2 · Creating competing leverage, even without an identical tier-1 offer

> Folder 05 · Compensation structure and multi-offer negotiation scripts · File 2 of 3 · [KB home](../README.md) · Previous: [05.1 Deconstructing comp](01-deconstructing-faang-comp-base-rsu-vesting-frontloading-sign-on-and-refreshers.md) · Next: [05.3 Three rounds of scripts](03-word-for-word-email-and-phone-scripts-for-3-rounds-of-comp-negotiation.md)

<!-- lint-pack: comp -->

| | |
|---|---|
| **Reader** | A candidate negotiating with their top-choice company who doesn't hold a matching offer from a peer company, and wants leverage that is real and stateable |
| **Running exhibit** | Candidate V negotiating Loop G's L6 offer (V's first choice, team T2), with A's and F's written offers, U in final rounds, and equity V would forfeit (§7) |
| **Listing** | `leverage_map.py`: sorts levers into what you can say, how to say it, and what you must not say, and assembles an honest leverage statement (§9) |
| **Verification** | The listing is byte-identical to the file that was run. §9.3 is a real run: the raw inventory contains an invented offer and an undocumented forfeit, and both are blocked; the honest inventory scores "strong" without them. The 8 pairs in §8 are checked with `script_lint.py` (comp pack). |
| **Marks** | ⚠ = field practice, not published policy. All amounts are illustrative. |

**Integrity rule.** Every lever you state must be true and, if asked, showable. Never invent an offer, inflate a number, describe a conversation as an offer, or set a deadline that doesn't exist. Beyond ethics: recruiters at large companies talk to each other's candidates every day, offers get verified, and a discovered bluff ends the negotiation and sometimes the offer.

---

## 0. The 60-second version

1. **Leverage is three things:** your real alternatives, the cost to them of losing you, and the legitimacy of your ask. An identical tier-1 offer is one source of the first; it isn't the only one.
2. **Your walk-away point comes from your best real alternative,** which may be staying where you are. Know it in numbers before you negotiate (05.1).
3. **Eight honest levers:** written offers of any tier, late-stage processes (as stages, not offers), forfeited equity and bonus, timing, fit with their pains, level evidence, a current-employer retention offer (private) and your walk-away.
4. **Use each lever on the component where it's strong.** A fintech's cash-heavy offer argues for sign-on and base; forfeited RSUs argue for a make-whole sign-on or extra equity.
5. **Forfeited equity is the most legitimate lever** ⚠: it's documentable, and replacing it is standard practice at many companies.
6. **Never bluff.** "I have multiple offers" without specifics gets called; an invented offer gets discovered.
7. **Run `leverage_map.py`** on your inventory. It blocks what you can't support and writes the statement you can.

---

## 1. What leverage actually is

| Element | What it means | Where it comes from |
|---|---|---|
| **Alternatives** | What you'll do if this negotiation fails: in negotiation terms, your best alternative to a negotiated agreement | Other offers, late-stage processes, staying |
| **Cost of losing you** | What it costs them to restart the search, or to lose your specific fit | Their pain (03.1), the time their search has taken, the level of signal in your packet |
| **Legitimacy of the ask** | Whether your number has a reason they can defend internally | Market data, competing offers, forfeited equity |

The "best alternative" idea comes from Fisher and Ury's negotiation work: you negotiate well when you know exactly what you'll do if there's no deal, and you never accept less than that (*Getting to Yes*, 3rd ed., ISBN 9780143118756). The recruiter, in turn, needs a **reason** to take to the compensation team: "the candidate has a written offer at X" or "the candidate forfeits Y". Your job is to hand them true reasons.

---

## 2. Why you don't need an identical tier-1 offer

Compensation teams can usually move within the band, and sometimes beyond it with approval ⚠, for any credible reason. A peer company's matching offer is the cleanest reason, but these also work:

| Reason | Why it works |
|---|---|
| A written offer from any company, on the component where it's stronger | It's evidence of market value for that component |
| Forfeited equity or bonus | A direct, documentable cost of joining |
| A late-stage process with a decision date | Urgency, without claiming an offer |
| Strong level signal (a split packet, 04.1) | A reason to place you higher in the band |
| Their pain and your fit | The hiring manager's willingness to advocate for an exception ⚠ |
| Timing (an immediate start, a short notice period) | A real benefit to them |

---

## 3. The eight honest levers

### 3.1 Written offers, of any tier

Use an offer **on the component where it beats this one.** V's fintech offer (F) has less four-year value than G, but more year-1 cash: ₹146 L against G's ₹129 L in year-1 base, bonus and sign-on (05.1 run). That's a specific, true argument for a larger sign-on at G, not for "matching F".

### 3.2 Late-stage processes, stated as stages

"I'm in final rounds with a third company and expect a decision by the 18th" is true and creates urgency. "I have another offer coming" is not true until it's in writing.

### 3.3 Forfeited equity and bonus

If you leave unvested RSUs or a bonus due soon, the new employer is often willing to replace part of it, through sign-on cash or extra equity ⚠. Document it: a vesting statement showing the unvested amount and its schedule.

### 3.4 Timing

An immediate start, or a notice-period buyout that shortens your start, is worth something to a team in a hurry. So is flexibility on their preferred start date.

### 3.5 Fit with their pains

If the hiring manager told you their two most expensive problems, and you've solved them before (03.1), the HM may push for a stronger offer or an exception ⚠. You don't use this as a threat; you remind them why you're worth it.

### 3.6 Level evidence

A split packet (04.1) is a reason to sit at the top of the band at the offered level.

### 3.7 A current-employer retention offer: private

A counteroffer from your current employer **informs your walk-away point.** Don't use it to start an auction unless you'd genuinely stay for it. Most people who accept counteroffers are back on the market soon after ⚠, and your new employer may lose interest if they think you're shopping.

### 3.8 Your walk-away

Know the number below which you'd take your best alternative, including staying. Say it only as a conditional close in round 3 (05.3).

---

## 4. Using a non-tier-1 offer well

| Do | Don't |
|---|---|
| Compare component by component: "F's year-1 cash is ₹146 L; yours is ₹129 L." | Present F's ESOP paper value as if it were liquid equity |
| Say what kind of company it is, if you don't want to name it | Imply it's a peer company when it isn't |
| Explain why you still prefer this company | Pretend you'd take F if you wouldn't |
| Ask for the component that closes the specific gap | Ask them to "match" an offer that's structured completely differently |

---

## 5. Using forfeited equity well

1. **Get the document:** your vesting statement, showing unvested amounts by date.
2. **State the gross amount and its timing:** "about ₹110 L unvested over the next two years".
3. **Ask for partial replacement, not dollar-for-dollar** ⚠: companies often replace some, not all.
4. **Name the vehicle:** a sign-on (cash, often with clawback) or an additional equity grant (vesting over time).
5. **Expect a question about your bonus:** if a bonus is due soon, ask whether a start date after it pays is acceptable, or ask for it to be replaced too.

---

## 6. What never to do

| Never | Why |
|---|---|
| Invent an offer, a level, or a number | Offers get verified; recruiters ask for letters; it's dishonest |
| Call a conversation in progress an "offer" | It's a misrepresentation, and the recruiter will plan around it |
| Say "multiple offers" without specifics | Vague leverage gets called |
| Set a deadline that doesn't exist | It forces a decision on false terms and destroys trust if discovered |
| Threaten to walk when you won't | One empty threat makes every later statement worth less |
| Share another company's offer letter if its terms forbid it | Check the letter for confidentiality terms first ⚠ |

---

## 7. Candidate V's inventory

V is negotiating with Loop G, V's first choice (team T2, 03.2). V's first, unedited list included two things that can't be said:

<!-- levers:start name=raw-v-levers -->
| Lever | Kind | Status | Evidence |
|---|---|---|---|
| another large tech company at L6 | offer | written | offer letter, expires on the 14th |
| an L7 offer from N | offer | claimed | - |
| about ₹110 L in unvested RSUs at my current employer | forfeit | undocumented | my estimate |
| a third company | process | final-round | onsite done; decision expected on the 18th |
<!-- levers:end -->

N never made an offer; V had only been told the HM was "keen". And V hadn't checked the vesting statement. The tool blocks both. After downloading the vesting statement and dropping the invented offer:

<!-- levers:start name=v-levers -->
| Lever | Kind | Status | Evidence |
|---|---|---|---|
| another large tech company at L6 | offer | written | offer letter, expires on the 14th |
| a growth-stage fintech, with more year-1 cash | offer | written | offer letter: ₹146 L year-1 cash |
| a third company | process | final-round | onsite done; decision expected on the 18th |
| about ₹110 L in unvested RSUs at my current employer | forfeit | documented | vesting statement: ₹110 L over the next 2 years |
| I can join within 30 days if the 60-day notice period is bought out | timing | documented | employment contract, notice clause |
| the team's top two problems match work I've already done | fit | documented | HM call notes: rollout safety, telemetry loss |
| a retention offer my manager hinted at | retention | verbal | - |
| my current pay | current | documented | payslips |
<!-- levers:end -->

The honest inventory is **strong** without the invented offer: two written offers, a late-stage process, a documented forfeit, timing and fit. The retention hint and current pay stay private: the first isn't real until written, and the second would anchor G to V's past (02.2).

---

## 8. Before → After: stating leverage

#### S91 · The vague bluff

| Version | Answer |
|---|---|
| **Weak** | I have multiple offers, so you'll need to do better. |
| **Strong** | I have a written offer from another large tech company at L6, which expires on the 14th. Yours is my first choice, and I'd like to make it work. |

#### S92 · An offer that doesn't exist yet

| Version | Answer |
|---|---|
| **Weak** | Other companies are offering me L7, so match it or I walk. |
| **Strong** | I'm in final rounds with a third company and expect a decision by the 18th. I'd like to settle this offer before then. |

#### S93 · Forfeited equity

| Version | Answer |
|---|---|
| **Weak** | I guess I'll lose some RSUs, sort of, if that's okay to mention? |
| **Strong** | I'd forfeit about ₹110 L in unvested RSUs over the next two years; I have the vesting statement. I'd like the offer to replace part of it, through the sign-on or an additional grant. |

#### S94 · A non-tier-1 offer

| Version | Answer |
|---|---|
| **Weak** | The fintech is offering way more, everyone is offering more than you. |
| **Strong** | The fintech's year-1 cash is ₹146 L against ₹129 L here. I prefer your role, so I'm not asking you to match their structure, but a larger sign-on would close most of the year-1 gap. |

#### S95 · Timing

| Version | Answer |
|---|---|
| **Weak** | Sorry, my notice period is long, I know that's a problem. |
| **Strong** | I can join within 30 days if the 60-day notice period is bought out. Is that something you can include? |

#### S96 · Fit

| Version | Answer |
|---|---|
| **Weak** | You really need me, so you have to give me more. |
| **Strong** | The two problems your hiring manager described, rollout safety and silent telemetry loss, are problems I've solved before. That's why I'm excited, and why I'd ask you to look at the top of the band. |

#### S97 · The current employer

| Version | Answer |
|---|---|
| **Weak** | My manager will counter, so I expect you to beat whatever they offer. |
| **Strong** | I've decided I want to make the move; I'm not looking for a counteroffer. What I'd like is an offer that reflects the level and what I'd forfeit. |

#### S98 · Current pay

| Version | Answer |
|---|---|
| **Weak** | My current CTC is 1.46 crore, so anything above that is fine. |
| **Strong** | I'm evaluating this against my other offers and the equity I'd forfeit, rather than my current package. |

---

## 9. The listing: `leverage_map.py`

### 9.1 What it does

For each lever, it assigns a verdict and a weight:

| Verdict | Meaning |
|---|---|
| `USE` | True and documented: state it plainly |
| `USE-AS-VERBAL` / `USE-AS-STAGE` | True, but say exactly what it is: a verbal offer, a process stage |
| `USE-WITH-DOC` | State it, and be ready to show the document |
| `GET-DOC` | Possibly true, but undocumented: get the document first |
| `PRIVATE` / `OPTIONAL` / `KEEP-QUIET` | Informs your own decision; don't use it to negotiate |
| `DO-NOT-STATE` | No evidence: never say it |

Then it scores the inventory's strength and assembles an honest leverage statement from the strongest usable levers.

To use it: list your levers in `levers.md` with the table format from §7, including the ones you're tempted to exaggerate, and run `python -I leverage_map.py levers.md`. Say only what it lets through.

### 9.2 Listing

<!-- include:leverage_map.py -->
```python
#!/usr/bin/env python3
"""leverage_map.py: sort your negotiation levers into what you can say, how to say it, and what you must not say.

Reads every block like this from a Markdown file:

  <!-- levers:start name=my-levers -->
  | Lever | Kind | Status | Evidence |
  |---|---|---|---|
  | Offer from G at L6 | offer | written | offer letter, expires 14th |
  | Unvested RSUs | forfeit | documented | vesting statement, ~110 unvested |
  <!-- levers:end -->

Kinds and statuses:
  offer      written | verbal | claimed      process   final-round | onsite | early | claimed
  forfeit    documented | undocumented       timing    documented | claimed
  fit        documented | claimed            retention written | verbal
  current    documented                      (your current pay; optional, it anchors to the past)
Anything 'claimed', or with no evidence ('-'), can't be stated. A retention offer is private: it informs your own
walk-away point and is never used to start an auction.
Usage: python -I leverage_map.py FILE.md [--kb]
  --kb  blocks named 'raw-*' must contain DO-NOT-STATE or GET-DOC items; every other block must have none.
Standard library only. Python 3.10+.
"""
import re
import sys

START = re.compile(r"<!--\s*levers:start\s+(.*?)-->")
END = re.compile(r"<!--\s*levers:end\s*-->")
RULES = {
    ("offer", "written"): ("USE", 3, "I have a written offer from {x}; it expires on [date]."),
    ("offer", "verbal"): ("USE-AS-VERBAL", 2, "I have a verbal offer from {x}; I expect it in writing by [date]."),
    ("process", "final-round"): ("USE-AS-STAGE", 1, "I'm in final rounds with {x}; I expect a decision by [date]."),
    ("process", "onsite"): ("USE-AS-STAGE", 1, "I have an onsite with {x} on [date]."),
    ("process", "early"): ("KEEP-QUIET", 0, "too early to be leverage; mention only if asked"),
    ("forfeit", "documented"): ("USE-WITH-DOC", 2, "I'd forfeit {x}; I'd like the offer to account for it."),
    ("forfeit", "undocumented"): ("GET-DOC", 0, "get the vesting statement before you mention it"),
    ("timing", "documented"): ("USE", 1, "{x}"),
    ("fit", "documented"): ("USE", 1, "Use as a reason the role is worth more, never as a threat: {x}."),
    ("retention", "written"): ("PRIVATE", 0, "sets your walk-away point; mention only if you'd truly accept it"),
    ("retention", "verbal"): ("PRIVATE", 0, "not real until written; don't mention it"),
    ("current", "documented"): ("OPTIONAL", 0, "anchors to your past; use only if it is higher than the offer"),
}


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def read(path):
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
        if cur is not None and line.startswith("|") and not set(line.strip()) <= set("|-: "):
            c = cells(line)
            if c[0] != "Lever":
                cur["rows"].append(c)
    return blocks


def classify(block):
    name = block["attrs"].get("name", "?")
    print(f"levers {name}")
    flags, usable, strength = [], [], 0
    for lever, kind, status, evidence in block["rows"]:
        kind, status = kind.lower(), status.lower()
        if status == "claimed" or (evidence.strip() in ("", "-") and kind in ("offer", "process", "forfeit", "timing")):
            verdict, weight, say = "DO-NOT-STATE", 0, "no evidence: never state it, however tempting"
        else:
            verdict, weight, say = RULES.get((kind, status), ("CHECK", 0, "unknown kind/status"))
        if verdict in ("DO-NOT-STATE", "GET-DOC"):
            flags.append(lever)
        strength += weight
        if weight:
            usable.append((weight, lever, say.format(x=lever)))
        print(f"  {verdict:<14} w{weight}  {lever}")
        if verdict not in ("USE", "USE-AS-VERBAL", "USE-AS-STAGE", "USE-WITH-DOC"):
            print(f"                     -> {say.format(x=lever)}")
    band = "strong" if strength >= 6 else "moderate" if strength >= 3 else "thin"
    print(f"  strength {strength} ({band})")
    if usable:
        print("  honest leverage statement (top 3):")
        for _, _, say in sorted(usable, key=lambda u: -u[0])[:3]:
            print(f"    \"{say}\"")
    print(f"  result: {'clean' if not flags else str(len(flags)) + ' lever(s) you must not use yet'}")
    return name, flags


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__)
        return 2
    kb = "--kb" in argv
    bad = []
    for block in read(argv[1]):
        name, flags = classify(block)
        if kb and name.startswith("raw-") != bool(flags):
            bad.append(name)
        print()
    if kb:
        print("VERDICT: " + ("OK" if not bad else "FAIL " + ", ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 9.3 Output: V's two inventories

<!-- run:leverage_map.py SELF --kb -->
```text
levers raw-v-levers
  USE            w3  another large tech company at L6
  DO-NOT-STATE   w0  an L7 offer from N
                     -> no evidence: never state it, however tempting
  GET-DOC        w0  about ₹110 L in unvested RSUs at my current employer
                     -> get the vesting statement before you mention it
  USE-AS-STAGE   w1  a third company
  strength 4 (moderate)
  honest leverage statement (top 3):
    "I have a written offer from another large tech company at L6; it expires on [date]."
    "I'm in final rounds with a third company; I expect a decision by [date]."
  result: 2 lever(s) you must not use yet

levers v-levers
  USE            w3  another large tech company at L6
  USE            w3  a growth-stage fintech, with more year-1 cash
  USE-AS-STAGE   w1  a third company
  USE-WITH-DOC   w2  about ₹110 L in unvested RSUs at my current employer
  USE            w1  I can join within 30 days if the 60-day notice period is bought out
  USE            w1  the team's top two problems match work I've already done
  PRIVATE        w0  a retention offer my manager hinted at
                     -> not real until written; don't mention it
  OPTIONAL       w0  my current pay
                     -> anchors to your past; use only if it is higher than the offer
  strength 11 (strong)
  honest leverage statement (top 3):
    "I have a written offer from another large tech company at L6; it expires on [date]."
    "I have a written offer from a growth-stage fintech, with more year-1 cash; it expires on [date]."
    "I'd forfeit about ₹110 L in unvested RSUs at my current employer; I'd like the offer to account for it."
  result: clean

VERDICT: OK
```

---

## 10. Word-for-word scripts

#### Script 1 · Verbal: the honest leverage statement

```text
"Let me be transparent about where I am. I have a written offer from another large tech
company at L6, which expires on the 14th. I'd also forfeit about ₹110 L in unvested RSUs
over the next two years by leaving; I have the vesting statement. And I'm in final rounds
with a third company, with a decision expected on the 18th.

Your role is my first choice, because of the team and the problem. I'd like to find a way to
make the offer reflect the level and what I'd be walking away from."
```

#### Script 2 · Email: stating a competing offer

```text
Subject: Where I am

Hi [Recruiter name],

Thank you for the offer. To be transparent: I have a written offer from another large tech
company at L6, which expires on the 14th. I'm happy to share its level and expiry date if
that's useful.

[Company] is my first choice. I'll come back to you by [day] with specifics on what would
make this an easy yes.

Best,
[Your Name]
```

#### Script 3 · Email: the make-whole ask for forfeited equity

```text
Subject: Unvested equity I'd forfeit

Hi [Recruiter name],

One more consideration as we finalize: by leaving [current employer], I'd forfeit about
₹110 L in unvested RSUs vesting over the next two years. I can share the vesting statement.

I'm not asking for it to be replaced in full, but I'd like the offer to account for part of
it, through the sign-on or an additional equity grant, whichever works better on your side.

Best,
[Your Name]
```

#### Script 4 · Verbal: using a non-tier-1 offer on the right component

```text
"I want to be precise about the other offer, because it's structured very differently. It's
a growth-stage company, cash-heavy, with equity that's illiquid, so I'm not counting that. On
cash alone, its first year is ₹146 L against ₹129 L here. I prefer your role, so I'm not
asking you to match its structure. A larger sign-on would close most of the year-one gap,
and that would make this an easy decision."
```

#### Script 5 · Verbal: the late-stage process

```text
"I'm also in final rounds with a third company. My onsite is done, and I expect their
decision by the 18th. I'm telling you so you can plan: I'd like to settle your offer before
then, because yours is the one I want."
```

#### Script 6 · Verbal: timing as a lever

```text
"On timing: my notice period is 60 days, but I can usually be released in 30 if it's bought
out. If you can cover the buyout, directly or through the joining bonus, I could start on
[date], which I know matters for the team's roadmap."
```

#### Script 7 · Verbal: when the recruiter says "We don't negotiate"

```text
"I understand there's a structure. I'm not asking you to break it, just to place me where the
evidence supports: the competing offer at L6, the equity I'd forfeit, and the split in the
packet. If the base is fixed, is there flexibility on the sign-on or the initial grant?"
```

#### Script 8 · Verbal: telling your current manager you're leaving (and declining a counter)

```text
"I wanted to tell you first: I've accepted a role elsewhere, and my last day will be [date]. I
know you might want to discuss a counteroffer, and I appreciate that. I've thought hard about
it, and the decision is about the kind of problem I want to work on next, not the money. I'd
like to make the handover as smooth as possible. Here's my plan for it."
```

#### Script 9 · Verbal: when asked to show the competing offer

```text
"Yes, I can share it. I'll send the page with the company type, level and expiry date. If you
need the comp figures, I'll check the letter's confidentiality terms first and share what I'm
allowed to."
```

---

## 11. Probe chains

<details><summary><b>P1 · "Which company is the other offer from?"</b></summary>

**Probe:** "Can you tell me which company?"

**What they're testing:** whether the offer is real, and how it compares.

**Executor answer:** "I'd rather not say." (After using it as leverage.)

**Staff/Principal answer:** "It's [a large tech company / name, if you're comfortable], at L6, expiring on the 14th. I'm happy to share the letter's first page."

</details>

<details><summary><b>P2 · "That company isn't really our competitor."</b></summary>

**Probe:** (About F) "A fintech's offer doesn't set our pay."

**What they're testing:** whether you understand the lever's limits.

**Executor answer:** "Well, it's still more money, so you should match it."

**Staff/Principal answer:** "Agreed, it doesn't set your band. I'm only using it for one point: year-one cash. I'd be giving up ₹17 L of first-year cash to join you, which a larger sign-on could close. Everything else, I'm comparing with offers at your level."

</details>

<details><summary><b>P3 · "We don't replace unvested equity."</b></summary>

**Probe:** "We don't do make-whole grants."

**What they're testing:** whether the lever disappears or converts.

**Executor answer:** "Oh, okay, then never mind."

**Staff/Principal answer:** "Understood. It's still a real cost of joining, so could it be reflected in the sign-on instead? Even partial replacement would help me close the decision."

</details>

<details><summary><b>P4 · "Do you have the offer in writing?"</b></summary>

**Probe:** "Is the other offer in writing yet?"

**What they're testing:** whether you're describing an offer or a hope.

**Executor answer:** "It's basically confirmed; the letter is coming."

**Staff/Principal answer:** If written: "Yes, dated the 3rd, expiring the 14th." If not: "Not yet. It's a verbal offer; I expect the letter by Wednesday, and I'll tell you when it arrives."

</details>

<details><summary><b>P5 · "Are you going to take a counteroffer from your company?"</b></summary>

**Probe:** "How do I know you won't use our offer to get a raise where you are?"

**What they're testing:** whether you're shopping.

**Executor answer:** "Maybe, it depends on what they offer."

**Staff/Principal answer:** "I won't. I've decided to move, for the work; I'll tell my manager that when I resign. What I need from you is an offer that reflects the level and the forfeited equity."

</details>

<details><summary><b>P6 · "We'll match the other offer exactly."</b></summary>

**Probe:** "We'll match the other offer's total comp."

**What they're testing:** whether "match" closes the deal.

**Executor answer:** "Great, I accept!"

**Staff/Principal answer:** "Thank you, I appreciate it. Can you send the revised breakdown? I want to check the shape year by year, since the structures are different. If it holds up, I expect to say yes quickly."

</details>

<details><summary><b>P7 · "Your current pay is much lower. Why should we pay more?"</b></summary>

**Probe:** (India) "Your current CTC is well below this. We're already giving a big hike."

**What they're testing:** whether you'll accept the "hike on current" frame.

**Executor answer:** "Yes, that's true, I'm grateful for the hike."

**Staff/Principal answer:** "I understand. I'm evaluating it against the market for L6 and against my other offers, rather than against my current package, because this role is a level up. On that basis, the gaps I've mentioned are the sign-on and the forfeited equity."

</details>

<details><summary><b>P8 · "If we improve the sign-on, can you decide today?"</b></summary>

**Probe:** "If we add to the sign-on, will you sign today?"

**What they're testing:** whether you'll commit, and whether your process is a pretext.

**Executor answer:** "Sure, I'll sign now."

**Staff/Principal answer:** "If the revised offer closes the year-one gap and partly covers the forfeited equity, yes, I'll sign by end of day. Can you send it in writing?" (Say this only if you mean it. It's the round-3 close in 05.3.)

</details>

---

## 12. Checklist

- [ ] Your walk-away number, from your best real alternative (05.1, `comp_model.py`).
- [ ] Every lever listed, including the ones you're tempted to exaggerate; `leverage_map.py` run.
- [ ] Documents ready: offer letters (check confidentiality terms), vesting statement, notice clause.
- [ ] Each lever matched to the component it argues for (§3, §4).
- [ ] The honest leverage statement, rehearsed (Script 1).
- [ ] A decision on any retention offer made privately, in advance (§3.7).

---

## 13. References

- The best alternative to a negotiated agreement: Roger Fisher, William Ury and Bruce Patton, *Getting to Yes*, 3rd edition (Penguin, 2011), ISBN 9780143118756.
- First offers as anchors: [Galinsky & Mussweiler (2001)](https://doi.org/10.1037/0022-3514.81.4.657).
- Year-by-year comparison of the offers: [05.1 of this KB](01-deconstructing-faang-comp-base-rsu-vesting-frontloading-sign-on-and-refreshers.md).
- The fit evidence behind §3.5: [03.1 of this KB](../03-Hiring-Manager-Screen-and-Team-Match-Mastery/01-the-hiring-manager-sell-call-diagnosing-their-pain-in-the-first-10-minutes.md).
