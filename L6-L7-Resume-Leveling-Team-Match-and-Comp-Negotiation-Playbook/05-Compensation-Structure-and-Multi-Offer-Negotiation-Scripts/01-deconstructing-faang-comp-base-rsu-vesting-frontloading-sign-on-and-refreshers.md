# 05.1 · Deconstructing FAANG comp: base, RSU vesting, front-loading, sign-on and refreshers

> Folder 05 · Compensation structure and multi-offer negotiation scripts · File 1 of 3 · [KB home](../README.md) · Next: [05.2 Creating competing leverage](02-creating-competing-leverage-even-without-an-identical-tier1-offer.md)

<!-- lint-pack: comp -->

| | |
|---|---|
| **Reader** | A candidate holding, or about to hold, offers whose headline numbers aren't comparable: different vesting shapes, sign-ons, bonus targets, currencies and equity types |
| **Running exhibit** | Candidate V's five offers G, A, N, U and F (§8). **All figures are illustrative placeholders in ₹ lakh, not market data.** |
| **Listing** | `comp_model.py`: year-by-year total comp for several offers, with vesting shapes, refreshers and stock-price scenarios (§10) |
| **Verification** | The listing is byte-identical to the file that was run. §10.3 is a real run over V's five offers and three stock scenarios. The 8 pairs in §9 are checked with `script_lint.py` (comp pack). |
| **Marks** | ⚠ = field practice, not published policy. Vesting schedules vary by grant and change over time: **your grant agreement is the authority.** Nothing here is tax advice. |

**Integrity rule.** Understand the offer you have; never describe an offer's numbers to another company as larger than they are, and never present an annualized figure as if it were a guaranteed one.

---

## 0. The 60-second version

1. **Compare offers year by year, not by headline.** A front-loaded grant pays most early; a back-loaded one pays most late; sign-ons exist to smooth the difference.
2. **Five components matter:** base, bonus target, initial equity grant (and its vesting shape), sign-on (and its clawback), and refreshers (which aren't guaranteed).
3. **Equity is valued at the grant price, then moves with the stock.** Run at least three price scenarios before comparing.
4. **Refreshers decide years 3 and 4,** especially with front-loaded grants. Ask what a typical refresher looks like at your level, and count it conservatively.
5. **In India, separate "CTC" into certainty buckets:** guaranteed cash, conditional cash (variable, joining bonus with clawback), liquid equity (public-company RSUs) and illiquid paper (private ESOPs).
6. **The sign-on is usually the most flexible component** ⚠; base is the least. Negotiate where there's room (05.3).
7. **Run `comp_model.py`** with your real offers before any negotiation call.

---

## 1. The anatomy of an offer

| Component | What it is | How flexible ⚠ | Watch for |
|---|---|---|---|
| **Base salary** | Annual fixed pay | Least: bounded by the level's band | Where in the band it sits |
| **Bonus** | A target percentage of base, paid on performance | The target is usually fixed by level | Whether it's guaranteed in year 1, and when it's paid |
| **Initial equity grant (RSUs)** | Shares granted at a value, vesting over years | Moderate | The vesting shape, the cliff, how the share count is set |
| **Sign-on bonus** | One-time cash, sometimes split over two years | Most flexible | Clawback terms if you leave early |
| **Refreshers** | New equity grants in later years | Not negotiable at offer; not guaranteed | What's typical for your level and rating |
| **ESPP** | Discounted share purchase, where offered | Fixed by plan | Not part of the offer's value unless you use it |
| **ESOPs (private companies)** | Options to buy shares at a strike price | Moderate | Liquidity: no market until an exit or a buyback |
| **Benefits, relocation** | Insurance, retirement, relocation support | Relocation is often negotiable | Repayment terms on relocation |

**Total comp (TC)** in this KB means base + bonus at target + equity vesting that year + sign-on paid that year.

---

## 2. Vesting shapes

### 2.1 The three common shapes

| Shape | Typical split by year | Who has reportedly used it ⚠ | What it means |
|---|---|---|---|
| **Even** | 25 / 25 / 25 / 25, often vesting quarterly or monthly | Many public tech companies | Smooth; refreshers stack on top |
| **Front-loaded** | 33 / 33 / 22 / 12 (one common variant) | Google: described as "a common 33:33:22:12 structure", with variation across grants ([Vested](https://vestedfinance.com/blog/us-stocks/investing/how-to-manage-google-rsus-a-practical-guide-for-employees/)) | High early TC; years 3–4 depend on refreshers |
| **Back-loaded** | 5 / 15 / 40 / 40 | Amazon: historically 5% after year 1, 15% after year 2, then 20% every six months ([myStockOptions](https://www.mystockoptions.com/articles/how-amazon-apple-google-adapted-their-rsu-grants-to-help-retain-top-talent); [Vested](https://vestedfinance.com/rsu-esops/blog/how-to-manage-amazon-rsus-tax-and-vesting-guide/)) | Low early equity, offset by sign-on cash in years 1 and 2 |

Schedules vary by grant and change; some companies have moved between shapes over the years. **Read the grant agreement.**

### 2.2 Cliffs, frequency and the "year-4 valley"

- **Cliff:** some grants vest nothing until the first anniversary ⚠. Ask whether yours does: it changes what you lose if you leave in month 11.
- **Frequency:** monthly or quarterly vesting after the cliff makes leaving mid-year cheaper.
- **The valley:** with a front-loaded grant, year-4 TC can be well below year 1 unless refreshers fill it. With a back-loaded grant, years 1–2 are the valley, which is why sign-ons exist.

### 2.3 How the share count is set

Equity offers are usually stated as a currency value, converted into shares using a price averaged over some window before the grant ⚠. Ask how it's computed and when: a sharp move in the stock between offer and grant changes the share count.

---

## 3. Sign-on bonuses

| Purpose | Example |
|---|---|
| Bridge a back-loaded vesting shape | Year-1 and year-2 cash to offset 5%/15% equity |
| Replace forfeited equity or bonus | You leave unvested RSUs, or a bonus due next month |
| Close a gap the band can't | The base is at the band's top; the sign-on carries the rest |

**Clawback:** many sign-ons must be repaid, often prorated, if you leave within 12 months ⚠; some are split across two years with separate clawbacks. In India, joining bonuses often carry clawback clauses, and the recovery is easy to forget when budgeting ([GreatFrontEnd on evaluating Indian offers](https://www.greatfrontend.com/blog/how-to-evaluate-tech-job-offer-india)).

---

## 4. Refreshers

- **What they are:** annual (sometimes more frequent) equity grants, usually linked to performance and level ⚠.
- **What you can learn at offer stage:** the typical refresher for your level at a "meets" or "exceeds" rating. Recruiters sometimes share it; peers can give ranges ⚠.
- **How to count them:** conservatively. Model a modest refresher, or none, and treat anything more as upside.
- **Why they matter more with front-loading:** the year-3/year-4 drop in a 33/33/22/12 grant is filled only by refreshers.

---

## 5. Stock-price risk

Equity is granted at a value, but it vests at whatever the price is then. A grant worth ₹240 L at offer is worth ₹192 L if the stock falls 20% and stays there. Model at least three scenarios: a decline, flat, and modest growth. The decline scenario is where cash-heavy offers start to look better.

---

## 6. India-specific structure

### 6.1 Certainty buckets

Indian offers are usually stated as a **CTC** (cost to company) figure that bundles very different things. Separate it into buckets before comparing (the approach in [GreatFrontEnd's guide](https://www.greatfrontend.com/blog/how-to-evaluate-tech-job-offer-india)):

| Bucket | Typical items | How to count |
|---|---|---|
| **Guaranteed cash** | Fixed salary and allowances | The core comparison number |
| **Payroll-deducted, not in hand** | Employer PF, gratuity | Long-term savings, not monthly cash |
| **Conditional cash** | Variable pay, joining bonus (with clawback) | Discount variable by its realistic payout; note clawback periods |
| **Liquid equity** | RSUs in a listed company | At grant value, with price scenarios |
| **Illiquid equity** | ESOPs in a private company | Separately; not part of comparable TC until there's a liquidity path |
| **Benefits** | Insurance, relocation, notice buyout | Count actual cash value |

### 6.2 Tax and currency ⚠

- **RSUs** of listed companies are generally taxed in India as a perquisite under salary at vesting, on the fair market value ([Vested on Amazon RSUs](https://vestedfinance.com/rsu-esops/blog/how-to-manage-amazon-rsus-tax-and-vesting-guide/)). Tax is withheld at vest, so in-hand equity value is lower than the gross figure.
- **ESOPs** are generally taxed at exercise, on the difference between fair value and strike price, which can mean tax before any liquidity.
- **Currency:** equity in a US-listed company is effectively denominated in dollars; your salary is in rupees. That's a risk and sometimes a hedge.
- Get tax advice for your own situation; this KB compares shapes, not after-tax outcomes.

### 6.3 Notice periods and buyouts

A new employer may pay a notice-period buyout or include it in the joining bonus ⚠. If yours has a 60–90-day notice period, ask early; it's a real cost the new employer can choose to cover.

---

## 7. Bands and where you sit in them

- **Comp is set by level and location** at most large companies ⚠; the team rarely changes it.
- **Each level has a band** for base and equity. Two people at the same level can differ meaningfully by where they sit in it.
- **What moves you within the band:** competing offers, interview strength (sometimes ⚠), and the forfeited value you'd walk away from.
- **When the base is at the band's top,** the remaining gap moves to equity or sign-on. That's why "the base is maxed" isn't the end of a negotiation (05.3).

---

## 8. Candidate V's five offers

All five are illustrative, in ₹ lakh. G and A follow the reported shapes from §2.1; the others use even vesting.

<!-- offer:start name=G-L6 -->
| Component | Amount | Detail |
|---|---|---|
| base | 95 | raise 3% |
| bonus | 0.15 | fraction of base, target |
| rsu | 240 | 33/33/22/12 |
| signon-y1 | 20 | y1 |
| refresh | 45 | from y2, 25/25/25/25 |
<!-- offer:end -->

<!-- offer:start name=A-L6 -->
| Component | Amount | Detail |
|---|---|---|
| base | 82 | raise 3% |
| rsu | 230 | 5/15/40/40 |
| signon-y1 | 60 | y1 |
| signon-y2 | 40 | y2 |
<!-- offer:end -->

<!-- offer:start name=N -->
| Component | Amount | Detail |
|---|---|---|
| base | 90 | raise 3% |
| rsu | 200 | 25/25/25/25 |
| refresh | 30 | from y2, 25/25/25/25 |
<!-- offer:end -->

<!-- offer:start name=U -->
| Component | Amount | Detail |
|---|---|---|
| base | 88 | raise 3% |
| bonus | 0.10 | fraction of base, target |
| rsu | 180 | 25/25/25/25 |
| signon-y1 | 15 | y1 |
| refresh | 25 | from y2, 25/25/25/25 |
<!-- offer:end -->

<!-- offer:start name=F -->
| Component | Amount | Detail |
|---|---|---|
| base | 110 | raise 5% |
| bonus | 0.10 | fraction of base, target |
| signon-y1 | 25 | y1, 12-month clawback |
| esop | 150 | illiquid until an exit or buyback |
<!-- offer:end -->

<!-- compare:start name=v-offers growth=-0.2,0,0.1 expect=best:G-L6 -->
<!-- compare:end -->

**Reading the run (§10.3):**

- **G** has the highest four-year total, but it declines every year as the front-loaded grant tapers; its year 4 depends on refreshers.
- **A** starts low and rises: the 60 + 40 sign-on fills years 1–2, and the back-loaded equity peaks in years 3–4. In relative terms it's also the most exposed to a falling stock, because its biggest equity years come last.
- **F** looks large as a headline CTC with the ESOP, but its comparable cash is the lowest; the ESOP is a separate bet on an exit.
- **N and U** are smooth; they differ mainly by bonus and sign-on.
- In the falling-stock scenario, the gap between the equity-heavy offers and F narrows sharply.

These averages also feed Folder 04's down-level decision, which used rounded figures (G ≈ 190, A ≈ 165 a year).

---

## 9. Before → After: understanding the offer

#### S81 · The verbal offer arrives

| Version | Answer |
|---|---|
| **Weak** | That sounds great, I accept! When do I start? |
| **Strong** | Thank you, I'm really pleased. Could you send the full breakdown in writing, with the vesting schedule and sign-on terms, so I can review it properly? |

#### S82 · Asking about the equity

| Version | Answer |
|---|---|
| **Weak** | Sorry, I don't really know how RSUs work, is that per year? |
| **Strong** | Is the equity figure the total grant over four years? What's the vesting split by year, is there a cliff, and how is the share count set? |

#### S83 · Asking about refreshers

| Version | Answer |
|---|---|
| **Weak** | I guess refreshers are kind of guaranteed, right? |
| **Strong** | What does a typical annual refresher look like at L6 for someone performing well? I'll treat it as upside, but it shapes years three and four. |

#### S84 · The sign-on

| Version | Answer |
|---|---|
| **Weak** | That works for me, I'll take the sign-on as it is. |
| **Strong** | What are the clawback terms on the sign-on, and is it paid in one installment or split across two years? |

#### S85 · Comparing with current pay

| Version | Answer |
|---|---|
| **Weak** | My current CTC is 1.46 crore, so this is a decent hike I guess. |
| **Strong** | I'm comparing this year by year with my other offers and with the equity I'd forfeit. Once I've done that, I'll come back with any questions. |

#### S86 · India: the CTC figure

| Version | Answer |
|---|---|
| **Weak** | 2.6 crore CTC sounds amazing, that's my dream job number. |
| **Strong** | Could you split the CTC into fixed pay, variable at target, employer PF and gratuity, joining bonus with its clawback, and the RSU grant with its vesting? |

#### S87 · Timing

| Version | Answer |
|---|---|
| **Weak** | I'll decide whenever, there's no other process going on. |
| **Strong** | I'll review the written offer and come back by Friday with any questions. I'm also finishing two other processes and will decide by the 14th. |

#### S88 · The notice period

| Version | Answer |
|---|---|
| **Weak** | I was wondering if maybe you could help with my notice period, if that's okay? |
| **Strong** | My notice period is 60 days. Is a notice buyout something you can cover, either directly or through the joining bonus? |

---

## 10. The listing: `comp_model.py`

### 10.1 What it does

For each offer, it prints year-by-year base, bonus, equity and sign-on, the four-year total, the average, the year-4-versus-year-1 change, the equity share and the lowest year. A compare block adds four-year totals under several stock-price scenarios.

It ignores taxes, currencies and benefits, and treats refreshers as a fixed assumption. Use it to compare **shapes**, not to budget.

To use it: copy the table format from §8 for each of your offers into `offers.md`, add a compare block with your scenarios, and run `python -I comp_model.py offers.md`.

### 10.2 Listing

<!-- include:comp_model.py -->
```python
#!/usr/bin/env python3
"""comp_model.py: year-by-year total comp for several offers, with vesting shape and stock-price scenarios.

Reads offer blocks and one compare block from a Markdown file:

  <!-- offer:start name=G-L6 -->
  | Component | Amount | Detail |
  |---|---|---|
  | base | 95 | raise 3% |
  | bonus | 0.15 | fraction of base, target |
  | rsu | 240 | 33/33/22/12 |
  | signon | 20 | y1 |
  | refresh | 45 | from y2, 25/25/25/25 |
  | esop | 150 | illiquid, not counted |
  <!-- offer:end -->

  <!-- compare:start name=my-offers growth=-0.2,0,0.1 -->
  <!-- compare:end -->

Amounts are in one currency unit per year (base, sign-on) or per grant (rsu, refresh, esop). The rsu detail is the
share of the grant vesting in each year. A refresh grant of the stated size is assumed every year from the stated
year, each vesting on its own schedule. Equity is valued at grant price times (1 + growth) ** (year - 1).
ESOPs in private companies are listed but not counted: they're illiquid until an exit or a buyback.
The model ignores taxes, currency moves and benefits. It's for comparing shapes, not for budgeting.
Usage: python -I comp_model.py FILE.md [--kb]
  --kb  check the compare block's expect=best:OFFER (highest 4-year total at 0% growth).
Standard library only. Python 3.10+.
"""
import re
import sys

START = re.compile(r"<!--\s*(offer|compare):start\s+(.*?)-->")
END = re.compile(r"<!--\s*(offer|compare):end\s*-->")
YEARS = 4


def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]


def read(path):
    offers, compare, cur, fenced = [], None, None, False
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
            if cur["kind"] == "offer":
                offers.append(cur)
            else:
                compare = cur
            cur = None
            continue
        if cur is not None and line.startswith("|") and not set(line.strip()) <= set("|-: "):
            c = cells(line)
            if c[0] != "Component":
                cur["rows"].append(c)
    return offers, compare


def schedule(text):
    return [float(x) / 100 for x in re.findall(r"\d+(?:\.\d+)?", text.split(",")[-1])]


def model(offer, growth):
    rows = {r[0]: (float(r[1]), r[2]) for r in offer["rows"]}
    base0, detail = rows.get("base", (0.0, ""))
    raise_ = float(re.search(r"(\d+(?:\.\d+)?)%", detail).group(1)) / 100 if "%" in detail else 0.0
    bonus = rows.get("bonus", (0.0, ""))[0]
    out = []
    for y in range(1, YEARS + 1):
        base = base0 * (1 + raise_) ** (y - 1)
        price = (1 + growth) ** (y - 1)
        equity = 0.0
        if "rsu" in rows:
            amt, det = rows["rsu"]
            sch = schedule(det)
            equity += amt * (sch[y - 1] if y <= len(sch) else 0) * price
        if "refresh" in rows:
            amt, det = rows["refresh"]
            start = int(re.search(r"y(\d)", det).group(1))
            sch = schedule(det)
            for g in range(start, y + 1):
                k = y - g
                equity += amt * (sch[k] if k < len(sch) else 0) * price
        sign = sum(v for name, (v, det) in rows.items() if name.startswith("signon") and f"y{y}" in det)
        out.append((base, base * bonus, equity, sign))
    return out, rows


def show(offer, growth):
    years, rows = model(offer, growth)
    name = offer["attrs"].get("name", "?")
    print(f"offer {name} (growth {growth:+.0%}/yr)")
    print(f"  {'year':<6}{'base':>8}{'bonus':>8}{'equity':>8}{'sign-on':>9}{'total':>9}")
    totals = []
    for y, (b, bo, eq, s) in enumerate(years, 1):
        t = b + bo + eq + s
        totals.append(t)
        print(f"  {y:<6}{b:>8.1f}{bo:>8.1f}{eq:>8.1f}{s:>9.1f}{t:>9.1f}")
    eq_share = sum(e for _, _, e, _ in years) / sum(totals)
    shape = (totals[-1] - totals[0]) / totals[0]
    print(f"  4-year total {sum(totals):.1f} · average {sum(totals) / YEARS:.1f} · year 4 vs year 1 {shape:+.1%}"
          f" · equity share {eq_share:.0%} · lowest year {totals.index(min(totals)) + 1}")
    if "esop" in rows:
        print(f"  not counted: ESOP paper value {rows['esop'][0]:.1f} ({rows['esop'][1]})")
    return sum(totals)


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) < 2:
        print(__doc__)
        return 2
    kb = "--kb" in argv
    offers, compare = read(argv[1])
    for o in offers:
        show(o, 0.0)
        print()
    bad = False
    if compare:
        growths = [float(g) for g in compare["attrs"].get("growth", "0").split(",")]
        print(f"compare {compare['attrs'].get('name', '?')}: 4-year totals by stock scenario")
        names = [o["attrs"]["name"] for o in offers]
        print("  " + f"{'scenario':<12}" + "".join(f"{n:>9}" for n in names))
        best0 = None
        for g in growths:
            vals = [sum(sum(r) for r in model(o, g)[0]) for o in offers]
            if g == 0:
                best0 = names[vals.index(max(vals))]
            print("  " + f"{format(g, '+.0%') + '/yr':<12}" + "".join(f"{v:>9.1f}" for v in vals))
        print(f"  highest at 0% growth: {best0}")
        exp = compare["attrs"].get("expect", "")
        if kb and exp.startswith("best:") and exp.split(":", 1)[1] != best0:
            bad = True
        print()
    if kb:
        print("VERDICT: " + ("FAIL" if bad else "OK"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 10.3 Output: V's five offers

<!-- run:comp_model.py SELF --kb -->
```text
offer G-L6 (growth +0%/yr)
  year      base   bonus  equity  sign-on    total
  1         95.0    14.2    79.2     20.0    208.4
  2         97.9    14.7    90.5      0.0    203.0
  3        100.8    15.1    75.3      0.0    191.2
  4        103.8    15.6    62.5      0.0    181.9
  4-year total 784.6 · average 196.1 · year 4 vs year 1 -12.7% · equity share 39% · lowest year 4

offer A-L6 (growth +0%/yr)
  year      base   bonus  equity  sign-on    total
  1         82.0     0.0    11.5     60.0    153.5
  2         84.5     0.0    34.5     40.0    159.0
  3         87.0     0.0    92.0      0.0    179.0
  4         89.6     0.0    92.0      0.0    181.6
  4-year total 673.1 · average 168.3 · year 4 vs year 1 +18.3% · equity share 34% · lowest year 1

offer N (growth +0%/yr)
  year      base   bonus  equity  sign-on    total
  1         90.0     0.0    50.0      0.0    140.0
  2         92.7     0.0    57.5      0.0    150.2
  3         95.5     0.0    65.0      0.0    160.5
  4         98.3     0.0    72.5      0.0    170.8
  4-year total 621.5 · average 155.4 · year 4 vs year 1 +22.0% · equity share 39% · lowest year 1

offer U (growth +0%/yr)
  year      base   bonus  equity  sign-on    total
  1         88.0     8.8    45.0     15.0    156.8
  2         90.6     9.1    51.2      0.0    151.0
  3         93.4     9.3    57.5      0.0    160.2
  4         96.2     9.6    63.8      0.0    169.5
  4-year total 637.5 · average 159.4 · year 4 vs year 1 +8.1% · equity share 34% · lowest year 2

offer F (growth +0%/yr)
  year      base   bonus  equity  sign-on    total
  1        110.0    11.0     0.0     25.0    146.0
  2        115.5    11.6     0.0      0.0    127.0
  3        121.3    12.1     0.0      0.0    133.4
  4        127.3    12.7     0.0      0.0    140.1
  4-year total 546.5 · average 136.6 · year 4 vs year 1 -4.1% · equity share 0% · lowest year 2
  not counted: ESOP paper value 150.0 (illiquid until an exit or buyback)

compare v-offers: 4-year totals by stock scenario
  scenario         G-L6     A-L6        N        U        F
  -20%/yr         708.8    588.1    551.2    575.4    546.5
  +0%/yr          784.6    673.1    621.5    637.5    546.5
  +10%/yr         830.1    726.3    664.9    675.8    546.5
  highest at 0% growth: G-L6

VERDICT: OK
```

---

## 11. Word-for-word scripts

#### Script 1 · Verbal: receiving the verbal offer

```text
"Thank you, I'm really pleased, and I appreciate the work you've put in. I'd like to review
it properly before we discuss anything. Could you send the full breakdown in writing: base,
bonus target, the equity grant with its vesting schedule and any cliff, the sign-on with its
clawback terms, and relocation if it applies? I'll come back to you by [day] with questions."
```

#### Script 2 · Email: asking for the written breakdown

```text
Subject: Offer details

Hi [Recruiter name],

Thank you again for the offer. To review it properly, could you send the following in
writing?
• Base salary and the annual bonus target.
• The equity grant: total value, vesting schedule by year, any cliff, vesting frequency, and
  how the share count is set (price and averaging window).
• The sign-on: amount, payment timing, and clawback terms.
• Relocation and notice-buyout support, if applicable.
• The start-date flexibility.

I'll come back to you by [day].

Best,
[Your Name]
```

#### Script 3 · Verbal: asking about refreshers

```text
"One question about the later years: what does a typical annual refresher look like at L6
for someone performing well? I know it isn't guaranteed, and I'll treat it as upside, but
with a front-loaded grant it shapes years three and four, so I'd like a realistic range."
```

#### Script 4 · Email: India, asking for the CTC breakup

```text
Subject: CTC breakup

Hi [Recruiter name],

Thank you for the offer. Could you share the CTC split into:
• fixed pay (basic, allowances);
• variable pay at target, and how it's typically paid out;
• employer PF and gratuity;
• joining bonus, with its payment date and clawback period;
• the RSU grant: value, vesting by year, and how the share count is set;
• insurance and any other benefits included in the CTC.

I'd like to compare it accurately with my other offers. Thank you!

Best,
[Your Name]
```

#### Script 5 · Verbal: clarifying the sign-on

```text
"On the sign-on: is it paid in one installment or split across two years, and what are the
clawback terms if I left in the first year? I'm not planning to, but I'd like to understand
the exact commitment before I compare offers."
```

#### Script 6 · Verbal: clarifying how the share count is set

```text
"How is the number of shares determined: is it the offer value divided by an average price
over some window before the grant date? And when is the grant date relative to my start?
I'm asking because a move in the stock between now and then would change the share count."
```

#### Script 7 · Verbal: setting the review timeline

```text
"Thank you. I'll review the written offer and come back by Friday with any questions. I'm
also finishing two other processes and plan to make one decision by the 14th, so you'll have
a clear answer then."
```

#### Script 8 · Email: asking about the notice-period buyout

```text
Subject: Notice period and start date

Hi [Recruiter name],

My notice period at [current employer] is 60 days. I can usually be released earlier if the
notice period is bought out. Is a notice buyout something [Company] can cover, either
directly or through the joining bonus? If so, I could start on [earlier date].

Best,
[Your Name]
```

#### Script 9 · Verbal: confirming you understand the shape

```text
"Let me read it back to make sure I have it right: base [X], bonus target [Y]% of base, an
equity grant of [Z] vesting [split] by year with [cliff/no cliff], a sign-on of [S] with a
[12]-month prorated clawback, and refreshers typically around [R] a year, not guaranteed.
Is that right?"
```

---

## 12. Probe chains

<details><summary><b>P1 · "This offer is X crore. That's a big jump for you."</b></summary>

**Probe:** (Recruiter) "This is a huge increase over what you make today."

**What they're testing:** whether you'll anchor on your current pay and stop negotiating.

**Executor answer:** "Yes, it's a great hike, thank you so much."

**Staff/Principal answer:** "I appreciate it. I'm evaluating it against the market for the level and against my other offers, year by year, rather than against my current package. I'll come back by Friday."

</details>

<details><summary><b>P2 · "Our equity is front-loaded, so year one is much bigger."</b></summary>

**Probe:** "Year-one comp here is higher than anywhere else."

**What they're testing:** whether you understand the shape.

**Executor answer:** "Great, that makes this the best offer."

**Staff/Principal answer:** "Thanks; it is strong in year one. Over four years it depends on refreshers, because the grant tapers to 12% in year four. What does a typical refresher look like at this level?"

</details>

<details><summary><b>P3 · "Don't worry about the vesting cliff."</b></summary>

**Probe:** "There's a one-year cliff, but everyone stays longer than a year anyway."

**What they're testing:** nothing; but the answer matters for your risk.

**Executor answer:** "Okay, no problem."

**Staff/Principal answer:** "Understood. I plan to stay well beyond a year. I'd still like to know the vesting frequency after the cliff, quarterly or monthly, so I understand the shape precisely."

</details>

<details><summary><b>P4 · "The ESOPs could be worth 10× at IPO."</b></summary>

**Probe:** (Loop F) "Our ESOPs are worth ₹1.5 Cr today and could be worth much more."

**What they're testing:** whether paper value will substitute for cash.

**Executor answer:** "Wow, okay, that's exciting."

**Staff/Principal answer:** "I'm excited about the company too. I'm treating the ESOPs as a separate bet: what's the strike price, the vesting schedule, the exercise window if I leave, and has the company run a buyback before? For comparing offers, I'm using cash and liquid equity only."

</details>

<details><summary><b>P5 · "Comp is the same for every team at this level."</b></summary>

**Probe:** "The offer is the standard L6 package."

**What they're testing:** whether you'll accept "standard" as fixed.

**Executor answer:** "Okay, then I guess there's nothing to discuss."

**Staff/Principal answer:** "Understood that the level sets the band. Where in the band does this offer sit for base and equity? That helps me see whether there's room before I come back to you."

</details>

<details><summary><b>P6 · "Why do you need it in writing?"</b></summary>

**Probe:** "I've told you the numbers. Do you really need the written version first?"

**What they're testing:** often nothing; sometimes urgency tactics.

**Executor answer:** "No, that's fine, I trust you."

**Staff/Principal answer:** "I do trust you; it's about precision. Vesting splits, cliff and clawback terms are easy to mishear on a call, and I'd like to compare offers on exactly the same basis."

</details>

<details><summary><b>P7 · "Our base is lower, but our bonus is guaranteed."</b></summary>

**Probe:** (A company with a lower base) "Our bonus effectively always pays at target."

**What they're testing:** whether you'll value conditional cash as guaranteed.

**Executor answer:** "Okay, then it's basically part of the base."

**Staff/Principal answer:** "Thanks. Is it guaranteed in writing for year one? If not, I'll count it at a realistic payout rather than at target. What has the typical payout been at this level over the last few years?"

</details>

<details><summary><b>P8 · "We can't share refresher numbers."</b></summary>

**Probe:** "Refreshers depend on performance; I can't give you numbers."

**What they're testing:** nothing; it's a common policy.

**Executor answer:** "Okay, I'll assume they're generous."

**Staff/Principal answer:** "Understood. I'll model years three and four with a conservative refresher assumption then. If that leaves a gap compared with my other offers, I may ask about the sign-on or the initial grant to balance it."

</details>

---

## 13. Checklist

- [ ] Every offer in writing, with vesting by year, cliff, frequency, sign-on clawback, and share-count method (Script 2).
- [ ] India: CTC split into certainty buckets (Script 4; §6.1).
- [ ] Refresher expectations asked, and modeled conservatively (Script 3).
- [ ] All offers in `comp_model.py`, with three stock scenarios.
- [ ] Year-by-year shapes compared, not just totals; valleys identified.
- [ ] ESOPs and other illiquid equity kept out of the comparable total.
- [ ] Notice-buyout and relocation support asked about (Script 8).

---

## 14. References

- Google RSU structure, including the "common 33:33:22:12" split: [Vested, managing Google RSUs](https://vestedfinance.com/blog/us-stocks/investing/how-to-manage-google-rsus-a-practical-guide-for-employees/).
- Amazon's back-loaded vesting: [myStockOptions](https://www.mystockoptions.com/articles/how-amazon-apple-google-adapted-their-rsu-grants-to-help-retain-top-talent); [Vested, Amazon RSUs for Indian employees](https://vestedfinance.com/rsu-esops/blog/how-to-manage-amazon-rsus-tax-and-vesting-guide/) (also on the perquisite tax at vest).
- Evaluating Indian tech offers by certainty bucket: [GreatFrontEnd](https://www.greatfrontend.com/blog/how-to-evaluate-tech-job-offer-india).
- Market data by level and location: [Levels.fyi](https://www.levels.fyi/reports/examples/leveling-comparison-report.html).
