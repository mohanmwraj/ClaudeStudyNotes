# 05.3 · Word-for-word email and phone scripts for three rounds of comp negotiation

> Folder 05 · Compensation structure and multi-offer negotiation scripts · File 3 of 3 · [KB home](../README.md) · Previous: [05.2 Creating competing leverage](02-creating-competing-leverage-even-without-an-identical-tier1-offer.md)

<!-- lint-pack: comp -->

| | |
|---|---|
| **Reader** | A candidate with a written offer from their first-choice company, about to negotiate it, who wants exact words for each round |
| **Running exhibit** | Candidate V negotiating Loop G's L6 offer (05.1 offer G-L6; 05.2 levers). All amounts in ₹ lakh, illustrative. |
| **Listing** | `counter_calc.py`: turns the offer, your evidence and your target into a round-2 counter and a round-3 close, and flags asks your evidence doesn't support (§9) |
| **Verification** | The listing is byte-identical to the file that was run. §9.3 is a real run: the greedy version is flagged three ways; V's version is clean, and the composite outcome in §7 lands exactly on V's target. The 8 pairs in §8 are checked with `script_lint.py` (comp pack). |
| **Marks** | ⚠ = field practice, not published policy. |

**Integrity rule.** Every number you ask for has a stated, true reason. Every "yes" you give is one you'll keep. Every alternative you mention exists. Negotiation done this way doesn't damage the relationship with your future manager, and that relationship is worth more than any single component.

---

## 0. The 60-second version

1. **Three rounds are normal; more is rare** ⚠. Round 1 receives and clarifies; round 2 counters with specific numbers and reasons; round 3 closes with a conditional yes.
2. **Round 1 has no numbers from you.** Thank them, get everything in writing, ask your questions, set a date.
3. **Round 2 is one email plus one call.** Total-comp framing, specific components, a reason for each, and genuine enthusiasm. No ranges.
4. **Allocate the ask by flexibility:** base up to the band's top, then sign-on (year-1 gap and forfeited equity), then equity.
5. **Round 3 is a conditional yes:** "If you can do X, I'll sign today." Say it only if you'll do it.
6. **Know your walk-away before round 2.** If the offer already beats your best alternative, negotiate politely and never threaten to walk.
7. **Close cleanly:** accept in writing with the confirmed terms, decline the others warmly, and resign without inviting a counteroffer.

---

## 1. The three rounds at a glance

| Round | Your goal | You say | You never say | Typical length |
|---|---|---|---|---|
| **1. Receive** | Understand the offer exactly | Thanks; questions; "in writing, please"; a date | "I accept"; any number; "that's lower than I hoped" | One call, one email; 2–5 days to review ⚠ |
| **2. Counter** | Move the offer to your target with reasons | Specific components, each with a reason; enthusiasm | Ranges; ultimatums; vague "multiple offers" | One email, one call; a few days for them to respond |
| **3. Close** | Land it | A conditional yes; small final asks | An unconditional yes before the final numbers are written | One call, then signing |

---

## 2. Round 1: receive

### 2.1 What to do

1. **Thank them, sincerely.** The recruiter has worked hard for this.
2. **Say nothing about the numbers,** good or bad.
3. **Ask for the full breakdown in writing** (05.1 Script 2).
4. **Ask your clarifying questions:** vesting, cliff, clawback, refreshers, share-count method, start date.
5. **Set a date** for your response, inside every other offer's deadline (02.2).

### 2.2 Then do your homework

- Model every offer year by year (05.1, `comp_model.py`).
- Sort your levers (05.2, `leverage_map.py`).
- Compute your counter and close (§9, `counter_calc.py`).
- Decide your walk-away, and write it down.

---

## 3. Round 2: counter

### 3.1 The structure of the counter

| Part | Content |
|---|---|
| **Enthusiasm** | Why this company and team, specifically |
| **The ask** | Specific numbers per component; total comp stated |
| **The reasons** | One true reason per component: the band, the year-1 cash gap, forfeited equity |
| **Flexibility** | Which components you'd trade between |
| **The date** | When you'll decide |

### 3.2 Allocating the ask

| Order | Component | Why this order |
|---|---|---|
| 1 | **Base, up to the band's top** | Compounds through raises and bonus, but has the least room |
| 2 | **Sign-on** | Most flexible; the natural vehicle for year-1 gaps and forfeited equity ⚠ |
| 3 | **Equity** | Usually some room; adds to the four-year value |

### 3.3 Email first, then call

Send the counter by email so the numbers are exact, then talk it through on a call so the tone is warm. Recruiters need written numbers to take to the compensation team ⚠.

### 3.4 India specifics

- **Fixed versus variable:** ask for movement in fixed pay; variable at target isn't guaranteed.
- **Joining bonus:** the natural vehicle for the notice-period buyout and forfeited equity; ask about the clawback period.
- **"Hike percentage" framing:** don't argue in percentages of your current CTC (02.2). Argue from the level's band and your evidence.
- **Relocation:** if you're moving cities, ask for it explicitly.

---

## 4. Round 3: close

### 4.1 The conditional yes

"If you can [specific change], I'll sign today." It works because it gives the recruiter a clear, final target to take to the compensation team, and a guaranteed outcome if they hit it. It only works if it's true: **if they hit the number, you sign.**

### 4.2 Small final asks

Once the main numbers are settled, a few small asks are normal: a start date, relocation details, a written note of scope and the level-review point (04.2 Script 7). Don't reopen the big numbers.

### 4.3 Get it in writing, then sign

Ask for the revised offer letter, check every number against what was agreed, then sign.

### 4.4 After you sign

- **Decline the other offers** the same day, warmly (Script 9).
- **Resign without inviting a counteroffer** (05.2 Script 8).
- **Thank the recruiter.** They may be your first ally inside the company.

---

## 5. Sequencing several offers

- **Negotiate last with your first choice** ⚠, once your other offers are in writing.
- **Don't negotiate hard with companies you'd never join.** It wastes their time, and recruiters talk to each other.
- **Tell each company the truth about your timeline** (02.2 Script 9).
- **Don't run an auction.** Ask your first choice to address specific gaps, not to "beat" everyone.

---

## 6. When to stop

- **After round 3,** in almost every case. Further rounds produce small gains and real friction ⚠.
- **When the offer reaches your target.** Taking the last ₹5 L at the cost of your future manager's goodwill is a bad trade.
- **When they say it's final, and it's above your walk-away.** Take it, or take your alternative. Don't keep pushing.

---

## 7. Candidate V's negotiation with Loop G

**V's evidence** (05.2): a written L6 offer from another large tech company; a fintech offer with ₹146 L of year-1 cash; ₹110 L of documented unvested RSUs; a late-stage process. **V's walk-away:** A's L6 offer, worth 658 on this file's simple four-year basis (no refreshers, no raises). G's offer is already worth 697 on that basis, so V negotiates politely and doesn't threaten to walk.

**V's target:** 770, which is G's offer plus half the forfeited equity plus the year-1 cash gap, rounded.

First, the greedy version V considered and discarded:

<!-- counter:start name=raw-v-greedy -->
| Item | Value |
|---|---|
| offer-base | 95 |
| offer-bonus | 0.15 |
| offer-rsu | 240 |
| offer-signon | 20 |
| band-base-max | ? |
| forfeit | 110 |
| makewhole-share | 0.5 |
| competing-y1-cash | 146 |
| best-alt-4y | 658 |
| target-4y | 1000 |
| pad | 0.05 |
| basis | - |
<!-- counter:end -->

Then the version V sent:

<!-- counter:start name=v-vs-g -->
| Item | Value |
|---|---|
| offer-base | 95 |
| offer-bonus | 0.15 |
| offer-rsu | 240 |
| offer-signon | 20 |
| band-base-max | 102 |
| forfeit | 110 |
| makewhole-share | 0.5 |
| competing-y1-cash | 146 |
| best-alt-4y | 658 |
| target-4y | 770 |
| pad | 0.05 |
| basis | written L6 offer elsewhere; vesting statement for ₹110 L unvested; fintech year-1 cash ₹146 L |
<!-- counter:end -->

**How it went (composite):**

| Round | V | G |
|---|---|---|
| 1 | Thanks; written breakdown; questions on vesting, refreshers, clawback; "I'll come back by Friday" | Sends the breakdown; refreshers "typically meaningful at L6" |
| 2 | Email and call: base ₹102 L (the band's top, which the recruiter had shared), sign-on ₹75 L, RSU ₹264 L, with reasons | Comes back with base ₹100 L, sign-on ₹45 L, RSU ₹250 L: "this is close to the best we can do" |
| 3 | "If you can bring the sign-on to ₹55 L and the RSU to ₹255 L, I'll sign today." | Agrees, and sends the revised letter |

The final package: base 100, sign-on 55, RSU 255, bonus 15%. On the same basis: 4 × 100 × 1.15 + 255 + 55 = **770**, exactly V's target. V signs that day, declines A, F and U warmly, and resigns without inviting a counteroffer.

---

## 8. Before → After: the moments that decide the outcome

#### S101 · Round 1: the offer call

| Version | Answer |
|---|---|
| **Weak** | I accept, thank you so much, this is amazing! |
| **Strong** | Thank you, I'm really pleased. Could you send the full breakdown in writing? I'll review it and come back to you by Friday. |

#### S102 · Round 2: naming the number

| Version | Answer |
|---|---|
| **Weak** | Somewhere between 2 and 2.5 crore a year would be nice. |
| **Strong** | I'd like to ask for a base of ₹102 L, a sign-on of ₹75 L and an RSU grant of ₹264 L. Here's the reasoning for each. |

#### S103 · "This is our best offer"

| Version | Answer |
|---|---|
| **Weak** | Okay, I guess that's fine then, thanks anyway. |
| **Strong** | Thank you for going back to the team. We're close. If you can bring the sign-on to ₹55 L and the RSU to ₹255 L, I'll sign today. |

#### S104 · Pressure

| Version | Answer |
|---|---|
| **Weak** | Give me a 75 lakh sign-on or I walk. |
| **Strong** | The sign-on is where I'd most like movement, because I'd forfeit about ₹110 L in unvested RSUs. I have the vesting statement if that helps. |

#### S105 · The close

| Version | Answer |
|---|---|
| **Weak** | Sounds good, let's do it, whatever you can manage. |
| **Strong** | If you can add ₹73 L across sign-on and equity, I'll sign today. |

#### S106 · India: the hike frame

| Version | Answer |
|---|---|
| **Weak** | My current CTC is 1.46 crore, so I need at least a 40% hike. |
| **Strong** | I'm basing my ask on the L6 band and my other offers, not on my current package. The two gaps are year-one cash and the equity I'd forfeit. |

#### S107 · Declining another offer

| Version | Answer |
|---|---|
| **Weak** | Sorry, your offer was too low, the other company is way better. |
| **Strong** | Thank you for the offer and for your work on it. I've accepted another role that's a closer fit for what I want to build next. I hope our paths cross. |

#### S108 · Your current employer's counter

| Version | Answer |
|---|---|
| **Weak** | I'll stay if you beat their offer by a good margin. |
| **Strong** | Thank you, I appreciate it. I've made my decision, and it's about the work rather than the money. I'd like to focus on a smooth handover. |

---

## 9. The listing: `counter_calc.py`

### 9.1 What it does

It compares the offer, your target and your walk-away on one simple basis (four years of base and bonus, plus the equity grant and sign-on; no refreshers or raises), then:

- computes how much your evidence **supports**: the offer or your best alternative, plus a make-whole share of forfeited equity, plus any year-1 cash gap against a competing offer;
- builds a round-2 counter at target plus a small anchor, allocated base → sign-on → equity;
- writes the round-3 close sentence;
- flags asks without a basis, asks more than 10% above what your evidence supports, an unknown base band, and a target below your walk-away.

To use it: copy the table from §7 into `counter.md` with your numbers, and run `python -I counter_calc.py counter.md`.

### 9.2 Listing

<!-- include:counter_calc.py -->
```python
#!/usr/bin/env python3
"""counter_calc.py: turn an offer, your evidence and your target into a round-2 counter and a round-3 close.

Reads every block like this from a Markdown file (amounts in one currency unit):

  <!-- counter:start name=my-counter -->
  | Item | Value |
  |---|---|
  | offer-base | 95 |
  | offer-bonus | 0.15 |
  | offer-rsu | 240 |
  | offer-signon | 20 |
  | band-base-max | 102 |
  | forfeit | 110 |
  | makewhole-share | 0.5 |
  | competing-y1-cash | 146 |
  | best-alt-4y | 658 |
  | target-4y | 770 |
  | pad | 0.05 |
  | basis | written L6 offer; vesting statement |
  <!-- counter:end -->

Everything is compared as a simple 4-year value: 4 x base x (1 + bonus) + RSU grant + sign-on, with no refreshers
and no raises, so offers are compared on what they commit to. 'best-alt-4y' is your best real alternative on the
same basis (your walk-away). 'band-base-max' may be '?'.
The counter asks for target x (1 + pad), allocated in this order: base up to the band maximum; then sign-on, enough
to cover the larger of the year-1 cash gap and the make-whole share of forfeited equity; then the rest as RSUs.
Flags: NO-BASIS (no stated reason), ASK-UNSUPPORTED (the ask is more than 10% above what your evidence supports),
BAND-UNKNOWN (ask for the band before countering on base), BELOW-WALKAWAY (your target is below your alternative).
Usage: python -I counter_calc.py FILE.md [--kb]
  --kb  blocks named 'raw-*' must raise flags; every other block must be clean.
Standard library only. Python 3.10+.
"""
import re
import sys

START = re.compile(r"<!--\s*counter:start\s+(.*?)-->")
END = re.compile(r"<!--\s*counter:end\s*-->")


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
            cur = {"attrs": dict(re.findall(r"(\w+)=(\S+)", m.group(1))), "v": {}}
            continue
        if cur is not None and END.search(line):
            blocks.append(cur)
            cur = None
            continue
        if cur is not None and line.startswith("|") and not set(line.strip()) <= set("|-: "):
            c = cells(line)
            if c[0] != "Item":
                cur["v"][c[0]] = c[1]
    return blocks


def num(v, key, default=None):
    x = v.get(key, "")
    try:
        return float(x)
    except ValueError:
        return default


def calc(block):
    v, name = block["v"], block["attrs"].get("name", "?")
    base, bonus = num(v, "offer-base"), num(v, "offer-bonus", 0.0)
    rsu, sign = num(v, "offer-rsu", 0.0), num(v, "offer-signon", 0.0)
    band = num(v, "band-base-max")
    forfeit, share = num(v, "forfeit", 0.0), num(v, "makewhole-share", 0.5)
    comp_y1, alt = num(v, "competing-y1-cash"), num(v, "best-alt-4y")
    target, pad = num(v, "target-4y"), num(v, "pad", 0.05)
    basis = v.get("basis", "-").strip()
    flags = []
    mult = 4 * (1 + bonus)
    offer4 = mult * base + rsu + sign
    y1 = base * (1 + bonus) + sign
    print(f"counter {name} (4-year value, no refreshers or raises)")
    print(f"  current offer: base {base:.1f} · bonus {bonus:.0%} · RSU {rsu:.1f} · sign-on {sign:.1f}"
          f" -> 4-year {offer4:.1f} · year-1 cash {y1:.1f}")
    if alt is not None:
        if offer4 >= alt:
            print(f"  walk-away (best alternative): {alt:.1f} -> this offer already beats it: negotiate, "
                  f"don't threaten to walk")
        else:
            print(f"  walk-away (best alternative): {alt:.1f} -> below it today; you have a real alternative")
        if target < alt:
            flags.append(f"BELOW-WALKAWAY target {target:.1f} < alternative {alt:.1f}")
    makewhole = forfeit * share
    y1_gap = max(0.0, (comp_y1 or 0.0) - y1)
    support = max(offer4, alt or 0.0) + makewhole + y1_gap
    ask = target * (1 + pad)
    print(f"  supportable: {support:.1f} (offer or alternative {max(offer4, alt or 0.0):.1f} + make-whole "
          f"{makewhole:.1f} + year-1 cash gap {y1_gap:.1f})")
    print(f"  target {target:.1f} · round-2 ask {ask:.1f} (+{pad:.0%} anchor)")
    if basis in ("", "-"):
        flags.append("NO-BASIS state the reason for every number you ask for")
    if ask > 1.10 * support:
        flags.append(f"ASK-UNSUPPORTED ask {ask:.1f} > 110% of supportable {support:.1f}")
    if band is None:
        flags.append("BAND-UNKNOWN ask where the base band tops out before countering on base")
    gap = max(0.0, ask - offer4)
    new_base = base
    if band is not None and band > base:
        new_base = min(band, base + gap / mult)
    gap -= mult * (new_base - base)
    y1_gap_after = max(0.0, (comp_y1 or 0.0) - (new_base * (1 + bonus) + sign))
    add_sign = min(gap, max(makewhole, y1_gap_after))
    new_sign = sign + max(0.0, add_sign)
    gap -= max(0.0, add_sign)
    new_rsu = rsu + max(0.0, gap)
    new4 = mult * new_base + new_rsu + new_sign
    print(f"  round 2 counter: base {base:.1f} -> {new_base:.1f}"
          + (" (band max)" if band is not None and new_base == band else "")
          + f" · sign-on {sign:.1f} -> {new_sign:.1f} · RSU {rsu:.1f} -> {new_rsu:.1f}")
    print(f"     check: 4-year {new4:.1f} · year-1 cash {new_base * (1 + bonus) + new_sign:.1f}")
    close = max(0.0, target - offer4)
    print(f"  round 3 close: \"If you can add {close:.1f} across sign-on and equity, I'll sign today.\"")
    print(f"  basis: {basis}")
    for f in flags:
        print(f"  FLAG {f}")
    print(f"  result: {'clean' if not flags else str(len(flags)) + ' flag(s)'}")
    return name, flags


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__)
        return 2
    kb = "--kb" in argv
    bad = []
    for block in read(argv[1]):
        name, flags = calc(block)
        if kb and name.startswith("raw-") != bool(flags):
            bad.append(name)
        print()
    if kb:
        print("VERDICT: " + ("OK" if not bad else "FAIL " + ", ".join(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 9.3 Output: V's two versions

<!-- run:counter_calc.py SELF --kb -->
```text
counter raw-v-greedy (4-year value, no refreshers or raises)
  current offer: base 95.0 · bonus 15% · RSU 240.0 · sign-on 20.0 -> 4-year 697.0 · year-1 cash 129.2
  walk-away (best alternative): 658.0 -> this offer already beats it: negotiate, don't threaten to walk
  supportable: 768.8 (offer or alternative 697.0 + make-whole 55.0 + year-1 cash gap 16.8)
  target 1000.0 · round-2 ask 1050.0 (+5% anchor)
  round 2 counter: base 95.0 -> 95.0 · sign-on 20.0 -> 75.0 · RSU 240.0 -> 538.0
     check: 4-year 1050.0 · year-1 cash 184.2
  round 3 close: "If you can add 303.0 across sign-on and equity, I'll sign today."
  basis: -
  FLAG NO-BASIS state the reason for every number you ask for
  FLAG ASK-UNSUPPORTED ask 1050.0 > 110% of supportable 768.8
  FLAG BAND-UNKNOWN ask where the base band tops out before countering on base
  result: 3 flag(s)

counter v-vs-g (4-year value, no refreshers or raises)
  current offer: base 95.0 · bonus 15% · RSU 240.0 · sign-on 20.0 -> 4-year 697.0 · year-1 cash 129.2
  walk-away (best alternative): 658.0 -> this offer already beats it: negotiate, don't threaten to walk
  supportable: 768.8 (offer or alternative 697.0 + make-whole 55.0 + year-1 cash gap 16.8)
  target 770.0 · round-2 ask 808.5 (+5% anchor)
  round 2 counter: base 95.0 -> 102.0 (band max) · sign-on 20.0 -> 75.0 · RSU 240.0 -> 264.3
     check: 4-year 808.5 · year-1 cash 192.3
  round 3 close: "If you can add 73.0 across sign-on and equity, I'll sign today."
  basis: written L6 offer elsewhere; vesting statement for ₹110 L unvested; fintech year-1 cash ₹146 L
  result: clean

VERDICT: OK
```

---

## 10. Word-for-word scripts

#### Script 1 · Verbal: Round 1, the offer call

```text
"Thank you, I'm really pleased, and thank you for all the work getting here. I'd like to
review it properly before we discuss anything. Could you send the full breakdown in writing,
including the vesting schedule, any cliff, the sign-on and its clawback terms? I'll come back
to you by Friday. One quick question now: what's the timeline on your side?"
```

#### Script 2 · Email: Round 1, confirming receipt and the date

```text
Subject: Thank you, and next steps

Hi [Recruiter name],

Thank you for the offer and for sending the details. I'm excited about the role and the team.

I'm reviewing everything now and will come back to you by Friday with any questions. As I
mentioned, I'm also finishing two other processes and plan to make one decision by the 14th.

Best,
[Your Name]
```

#### Script 3 · Email: Round 2, the counter

```text
Subject: Offer: my response

Hi [Recruiter name],

Thank you again. I want to start by saying [Company] is my first choice: [team]'s rollout-
safety problem is exactly where my experience fits, and I'd like to make this work.

Having compared the offers year by year, I'd like to ask for three changes:
• Base: ₹102 L, the top of the L6 band you shared, given the split in the packet toward L7.
• Sign-on: ₹75 L. By leaving, I'd forfeit about ₹110 L in unvested RSUs over the next two
  years (I can share the vesting statement), and the other offer I hold has higher year-one
  cash.
• RSU grant: ₹264 L.

On the same four-year basis, that's about ₹808 L against ₹697 L today. I'm flexible on how
it's split between the sign-on and the equity.

I'll decide by the 14th. Could we talk this week?

Best,
[Your Name]
```

#### Script 4 · Verbal: Round 2, the counter call

```text
"Thanks for the time. You have my email; I wanted to talk it through, because I really do want
to join. The two things driving my ask are the equity I'd forfeit, about ₹110 L over two
years, and year-one cash, where the other offer is higher. The base I'd only ask to move to
the band's top. I'm flexible on the split between sign-on and equity. What's possible on your
side?"
```

#### Script 5 · Verbal: Round 2, "this is close to our best"

```text
"Thank you for going back to the team; I know that takes effort. We're close. The gap that
matters most to me is the forfeited equity. If the sign-on could come up a bit more, with a
small increase in the grant, I think we'd be there. Let me think about the exact number and
come back to you this afternoon."
```

#### Script 6 · Email: Round 2, India-specific counter

```text
Subject: Offer: my response

Hi [Recruiter name],

Thank you for the offer and the CTC breakup. [Company] is my first choice, and I'd like to make
it work. Three requests:
• Fixed pay: ₹[X] L, rather than an increase in variable, since variable isn't guaranteed.
• Joining bonus: ₹[Y] L, covering the 60-day notice buyout and part of the ₹110 L in unvested
  RSUs I'd forfeit (vesting statement available), with a 12-month prorated clawback.
• Relocation support for the move from [city].

I'm basing this on the L6 band and my other offers rather than my current package. I'll
decide by [date].

Best,
[Your Name]
```

#### Script 7 · Verbal: Round 3, the conditional close

```text
"I've thought about your revised offer. We're very close. If you can bring the sign-on to
₹55 L and the RSU grant to ₹255 L, I'll sign today. If that's not possible, tell me what is,
and I'll give you a decision by tomorrow."
```

#### Script 8 · Email: accepting, with the confirmed terms

```text
Subject: Acceptance

Hi [Recruiter name],

I'm delighted to accept. To confirm the terms we agreed:
• Base: ₹100 L; bonus target 15%.
• RSU grant: ₹255 L, vesting [schedule].
• Sign-on: ₹55 L, [payment timing], with [clawback terms].
• Start date: [date].

I'll sign the revised letter as soon as it arrives. Thank you for all your work on this; I'm
looking forward to working with you.

Best,
[Your Name]
```

#### Script 9 · Email: declining the other offers

```text
Subject: Thank you, and my decision

Hi [Recruiter name],

Thank you for the offer and for your work throughout the process. After a lot of thought, I've
accepted another role that's the closest fit for what I want to build next. It wasn't an easy
decision, and I came away impressed by [team / person / problem].

I'd be glad to stay in touch, and I hope our paths cross.

Best,
[Your Name]
```

#### Script 10 · Verbal: walking away gracefully, when the gap is too large

```text
"Thank you for trying; I can tell you've pushed hard. Where we've landed is below what I can
accept, given the alternative I have, so I'm going to decline. I'm disappointed it didn't
work out this time, because I liked the team. I'd welcome hearing from you if things change."
```

(Use only when the final offer is below your walk-away, and never as a tactic to reopen the negotiation.)

---

## 11. Probe chains

<details><summary><b>P1 · "What number would make you sign today?"</b></summary>

**Probe:** (Round 1, before you've seen the written offer) "Just tell me your number."

**What they're testing:** whether you'll name a number before you know the structure.

**Executor answer:** "Maybe around 2.2 crore?"

**Staff/Principal answer:** "I'd rather give you a precise answer than a quick one. Once I have the written breakdown, I'll come back by Friday with specifics, and with the reasons behind them."

</details>

<details><summary><b>P2 · "Why should we move the base? It's already strong."</b></summary>

**Probe:** (Round 2) "The base is already high in the band."

**What they're testing:** whether your base ask has a reason.

**Executor answer:** "Because I think I deserve more."

**Staff/Principal answer:** "I'm only asking for the band's top, because the packet was split toward L7. If the base can't move, I'm happy to see that value in the sign-on or equity instead."

</details>

<details><summary><b>P3 · "We can't replace your unvested equity."</b></summary>

**Probe:** "We don't do make-whole."

**What they're testing:** whether the reason survives a policy answer.

**Executor answer:** "Then I'll have to think about it."

**Staff/Principal answer:** "Understood. It's still a cost of joining, so I'd ask for it to be reflected in the sign-on, even partly. That's where most of my ask is."

</details>

<details><summary><b>P4 · "Your ask is much higher than the other offer."</b></summary>

**Probe:** "The other company's L6 offer is lower than ours. Why ask for more?"

**What they're testing:** whether your ask is supported or greedy.

**Executor answer:** "Because you're a bigger company."

**Staff/Principal answer:** "You're right that your offer is already higher on four-year value. My ask isn't about matching it; it's about two specific costs: the ₹110 L in equity I'd forfeit, and the year-one cash gap against the fintech offer. That's where my numbers come from."

</details>

<details><summary><b>P5 · "If we do this, will you stop interviewing?"</b></summary>

**Probe:** (Round 3) "If we hit your number, are you done?"

**What they're testing:** whether your conditional yes is real.

**Executor answer:** "Probably, but let me see what the others say."

**Staff/Principal answer:** "Yes. If you hit those numbers, I'll sign today and withdraw from the other processes."

</details>

<details><summary><b>P6 · "We need an answer by tomorrow."</b></summary>

**Probe:** (Round 2) "The compensation team needs a yes or no by tomorrow."

**What they're testing:** whether pressure ends your negotiation.

**Executor answer:** "Okay, then I accept."

**Staff/Principal answer:** "I can do tomorrow. To make it a yes, the sign-on is the piece that matters most. If you can move it toward ₹55 L, I'll confirm tomorrow morning."

</details>

<details><summary><b>P7 · "Other candidates don't negotiate this much."</b></summary>

**Probe:** "You're asking for a lot compared with most candidates."

**What they're testing:** social pressure.

**Executor answer:** "Sorry, I don't want to be difficult."

**Staff/Principal answer:** "I understand. Each part of my ask has a specific reason, and I've tried to keep it to one round of changes. Which of the three is hardest for you?"

</details>

<details><summary><b>P8 · (Your future manager calls) "I hear the negotiation is tough."</b></summary>

**Probe:** (Hiring manager) "The recruiter mentioned you're negotiating hard. Is everything okay?"

**What they're testing:** whether the negotiation is about the job or about the money, and whether the relationship is intact.

**Executor answer:** "It's just business."

**Staff/Principal answer:** "Everything's fine, and thank you for checking. I'm excited about the team. The open item is the equity I'd forfeit by leaving; I'm trying to close that gap fairly. I expect we'll be done this week, and I'm looking forward to starting on rollout safety."

</details>

---

## 12. Checklist

**Round 1**
- [ ] Thanks; no numbers; the breakdown in writing; questions; a date (Scripts 1–2).

**Before round 2**
- [ ] `comp_model.py` (05.1), `leverage_map.py` (05.2) and `counter_calc.py` all run.
- [ ] Walk-away written down; target and ask computed; a reason for each component.

**Round 2**
- [ ] Email with specific numbers and reasons (Script 3, or Script 6 for India), then a call (Script 4).
- [ ] No ranges, no ultimatums, no vague leverage.

**Round 3**
- [ ] A conditional yes you'll keep (Script 7).
- [ ] Terms confirmed in writing (Script 8); revised letter checked line by line.

**After**
- [ ] Other offers declined the same day (Script 9).
- [ ] Resignation without inviting a counteroffer (05.2 Script 8).

---

## 13. References

- The best alternative to a negotiated agreement, and principled negotiation: Fisher, Ury and Patton, *Getting to Yes*, 3rd edition (Penguin, 2011), ISBN 9780143118756.
- Why the first specific number matters: [Galinsky & Mussweiler (2001)](https://doi.org/10.1037/0022-3514.81.4.657).
- Evaluating Indian offers, joining bonuses and clawbacks: [GreatFrontEnd](https://www.greatfrontend.com/blog/how-to-evaluate-tech-job-offer-india).
- The offers and levers behind V's numbers: [05.1](01-deconstructing-faang-comp-base-rsu-vesting-frontloading-sign-on-and-refreshers.md) and [05.2](02-creating-competing-leverage-even-without-an-identical-tier1-offer.md) of this KB.
