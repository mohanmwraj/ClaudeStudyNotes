# 02.3 · Answering "What Would You Redesign Today?" With Hindsight

> **Folder:** `02-The-3-Viable-Options-Tradeoff-Defense-Framework` · file 3 of 3
> **Question this file answers:** at minute 50 the interviewer asks, "knowing what you know now, what would you change?" How do I answer so that it shows self-critique, growth and present-day judgment, without trashing a sound decision, claiming that something was obvious all along, or offering "more tests"?
> **Running exhibits:** P-0 Beacon, Tidewater (Archetype A) and Tillpoint (Archetype B); see [02.1](01-proving-first-principles-why-you-rejected-option-a-and-option-b.md).
> **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.

| Listing | Language | What it does | Where it runs |
|---|---|---|---|
| L6 `hindsight_check.py` | Python 3, standard library | Validates hindsight ledgers. Each row needs a decision-vs-outcome class, no hindsight bias in "Known then", a specific change rather than a non-answer, and a quantified cost. Each ledger must own at least one bad decision. It also lints tellings for hindsight bias, non-answers, overcorrection and a missing "what was known then" anchor. | [§12](#12-the-hindsight-checker), on the three ledgers and all tellings in this file |

**Verification.** The gate extracts the listing from this file and checks it byte for byte against the source that was run. It then re-runs the listing on this file and compares the result with the output block in §12; the tool's verdict must read OK. Every telling is also linted by the Folder 01 lints. Results are in the [README](../README.md#gate-results).

---

## 0. Orientation

The hindsight question usually comes late (01.1 §7.9) and is often the last thing the interviewers write down. It is short, and it is diagnostic: it tests whether you can criticize your own work precisely, which only an author can do well (01.2 §15 Q9). This file gives you:
- a model for separating decision quality from outcome quality (§1.2);
- a three-part answer structure (§2);
- a taxonomy of the regrets worth having (§3);
- a reversibility lens for choosing which regret to lead with (§4);
- a whiteboard pattern for sketching v2 with a migration path (§5);
- a ledger you can validate (§6).

---

## 1. First principles: what the question tests

### 1.1 Four things in one question

| What it tests | The interviewer's private question | Evidence that answers it |
|---|---|---|
| **Self-critique** | Can they see the flaws in their own work? | A specific flaw in a component *they* owned |
| **Learning** | Have they grown since the project? | A principle they hold now that they didn't hold then |
| **Decision vs outcome** | Do they judge decisions by information, or by results? | Defends a good decision that had a bad outcome; confesses a bad decision that had a good one |
| **Present-day judgment** | What would they build now, and how would they get there? | A v2 delta with a migration path, and the trigger for acting |

### 1.2 Decision quality is not outcome quality

A decision is judged on the information and options available when it was made. An outcome is the decision plus luck. Annie Duke's *Thinking in Bets* (Portfolio/Penguin, 2018, ISBN 978-0-7352-1635-8) calls the confusion between the two "resulting". Interviewers who have run real systems are alert to it in both directions.

| | Good outcome | Bad outcome |
|---|---|---|
| **Good decision** | Say why it was good, and what would make it wrong *now* | **Defend it.** Explain the information then, the odds you accepted, and what you changed in operations afterwards (§7) |
| **Bad decision** | **Confess it.** It worked out by luck. This is rare and very credible (§8). | Own it. Root cause in your reasoning, not just the code, and the principle you hold now. |

**The two diagonal cells carry the most signal.** A candidate who defends a good decision despite a bad outcome shows judgment under pressure. A candidate who confesses a bad decision despite a good outcome shows unusual honesty.

### 1.3 Known then versus known now

Every hindsight answer needs a time anchor, a statement of what was known *then*:
- **Information available then:** "Sidecar coverage was 82% at month 0."
- **The cost of more information then:** "A full dependency inventory would have taken 6 weeks we didn't have."
- **What changed since:** scale, team, technology, requirements, or the discovery of an assumption that was wrong.

Without the anchor, a hindsight answer reads as either hindsight bias ("it was obvious") or as a redesign untethered from the original constraints.

### 1.4 Hindsight bias is a known cognitive error

Fischhoff's classic study ("Hindsight ≠ foresight: The effect of outcome knowledge on judgment under uncertainty", *Journal of Experimental Psychology: Human Perception and Performance* 1(3):288–299, 1975, DOI 10.1037/0096-1523.1.3.288) showed that people who know an outcome overestimate how predictable it was. In interviews, it shows up as phrases like "obviously we should have…" and "everyone could see…". Interviewers hear those phrases as a lack of rigor, because they deny that the original decision was made under uncertainty. The fix is the time anchor: say what was known, and whether the outcome was foreseeable *from that*.

---

## 2. The three-part answer

> **1. The change** (specific, in a component you owned) · **2. Why it wasn't done then** (information, constraint, or your own error, with the time anchor) · **3. What the current design costs, and when you'd act** (a number and a trigger).

#### How an L5 tells it

> Honestly I don't think I'd change much, the design held up. Maybe I'd add more tests and better documentation, basically just polish.

#### How an L7 tells it

> I'd make the on_missing policy a required field at namespace creation. At the time, I treated compiled-in defaults as a safe fallback, and the evidence against that was already in A2, where 1 default disabled a rate limiter, so this is a lesson I could have drawn in month 0 instead of from INC-B7 in month 7. The current design still carries the cost: 1,340 of our 2,100 namespaces were created before the field existed and run on an inferred policy their owners never confirmed. I'd act now, with a 1-quarter campaign that requires the field on each namespace's next edit.

**Why it works.**
1. **The change** is specific and lies in the candidate's own component.
2. **Why not then:** the candidate admits the information existed at the time (A2). That isn't hindsight bias; it's taking responsibility for a missed inference.
3. **The cost is counted** (1,340 namespaces), and there's a plan with a trigger ("now").

---

## 3. A taxonomy of regrets worth having

Some regrets are more informative than others. These classes are listed roughly from hardest to reverse (the most valuable to discuss) to easiest:

| Class | Why it's hard to change | Example (archetype) |
|---|---|---|
| **Data model and money/identity types** | Every consumer depends on it (Hyrum) | Tillpoint stored amounts as 2-place decimals; 3 currencies with 0 or 3 minor units later touched 11 services |
| **Keys and identifiers** | Embedded in every stored record | Tidewater keyed dedup on CDC offsets, so a CDC product change re-keyed everything |
| **Consistency model** | Clients encode their assumptions | A read-your-writes assumption baked into a cache-aside design |
| **Service or module boundary** | Moving a boundary moves teams and contracts | A "shared customer service" that 9 services call synchronously |
| **Safety defaults** (fail-open vs fail-closed) | Discovered only in failures | Beacon's compiled-in defaults (INC-B7) |
| **Migration strategy** | You get one chance per migration | Big-bang cutover vs per-namespace |
| **Operability investment** | Cheap early, expensive to retrofit under incidents | Beacon's version-skew dashboard arrived 2 months late (01.2 Q5) |
| **Build vs buy** | Sunk costs and skills | A hand-built scheduler instead of a managed workflow service |
| **Scope** | Too much delays value; too little causes rework | Tidewater descoped crypto-shredding, then needed it at month 9 |
| **People and ownership** | Organizational inertia | An on-call rotation split across 2 teams with no single owner |

**Lead with the hardest-to-reverse class you have a real example for.** "I'd change the dedup key" shows more design judgment than "I'd add a dashboard". Both are honest, but only the first is about architecture.

### 3.1 A data-model regret

#### How an L5 tells it

> We probably should have used a different database. Our data model was sort of messy and we had a lot of tech debt in the schema.

#### How an L7 tells it

> The one-way door I'd reopen is the money type. In the 2022 schema, the order service stored amounts as a decimal with 2 places, and when Tillpoint added 3 currencies with 0 or 3 minor units in month 16, every service that assumed 2 places needed a change, 11 services in all. Today I'd store integer minor units plus an ISO 4217 currency code from day 1, which adds no work at design time and cost about 6 engineer-weeks per service to retrofit.

---

## 4. Reversibility: choose the regret that matters

Amazon's 2015 shareholder letter distinguishes "one-way doors", consequential and hard to reverse, from "two-way doors", which can be walked back cheaply ([2015 letter](https://s2.q4cdn.com/299287126/files/doc_financials/annual/2015-Letter-to-Shareholders.PDF)). Apply that to hindsight:
- **Two-way-door regrets are cheap.** "I'd have chosen a different retry library" says little, because you'd just change it.
- **One-way-door regrets are where design judgment shows:** keys, data models, contracts, consistency models, migration strategy.
- **Some regrets are really about converting a one-way door into a two-way one.** "I'd put an abstraction boundary here, so the next change is cheap." That is often the best L7 hindsight answer, because it's about future reversibility, not past correctness.

---

## 5. The v2 sketch: delta plus migration path

When asked "how would you build it today?", don't redraw the whole system. Draw the **delta** on the existing board, in a different color or with a "v2" label, and add the **migration path** from v1. A v2 without a migration path is fantasy: every real redesign has to be reached from the running system.

```text
 v1 (on the board)                     v2 delta (red)                     migration path
 CDC offsets --> dedup key ----------> business event_id minted at   ->  1. add event_id column (6 tables)
 (LSN + table key)                     source write                      2. dual-key dedup for 7 days
                                                                         3. drop offset key after 1 window
 GCS raw archive (immutable Avro) ---> per-policyholder envelope     ->  1. new data encrypted per key
                                       encryption (crypto-shred)         2. quarterly compaction of history
```

#### How an L5 tells it

> If I did it again I'd rewrite the whole thing in a newer framework, since the current stack is kind of dated now and there are better tools.

#### How an L7 tells it

> My v2 changes 1 thing in the core: the dedup key. In the 2023 design I keyed dedup on the source log sequence number plus the table key, which tied the warehouse to 1 CDC product's offsets, and when the source DBA team moved to a new replication product in month 11, every key changed and I needed a 2-week bridge to map old offsets to new ones. Today I'd key on a business event ID minted at the source write, at a cost of 1 new column in 6 source tables. The migration path is dual keys for 1 retention window of 7 days, then drop the offset key.

---

## 6. The hindsight ledger

Like the constraint ledger (01.3 §2), the hindsight ledger is private preparation. `hindsight_check.py` (§12) validates it.

| Column | Rule |
|---|---|
| ID | Short label |
| Decision | What was decided, specifically |
| Known then | What was known at the time, with no hindsight bias |
| Known now | What is known now |
| Class | One of the four cells in §1.2 |
| Change today | A specific change, not a non-answer |
| Cost of current design | Quantified |
| Trigger to act | When you'd make the change (or "now") |

Each ledger must include at least one **bad decision**. A ledger of only good decisions is not self-critique.

### 6.1 A ledger that fails

<!-- hindsight:start name=l5-hindsight -->
| ID | Decision | Known then | Known now | Class | Change today | Cost of current design | Trigger to act |
|---|---|---|---|---|---|---|---|
| H1 | Used Kafka | It seemed right | It was fine | Good decision, good outcome | Nothing | — | — |
| H2 | Chose Postgres | Obviously it was the standard | Still fine | Good call | More tests | low | none |
<!-- hindsight:end -->

### 6.2 The Beacon ledger

<!-- hindsight:start name=beacon-hindsight -->
| ID | Decision | Known then | Known now | Class | Change today | Cost of current design | Trigger to act |
|---|---|---|---|---|---|---|---|
| B1 | Compiled-in defaults as the fallback when no LKG exists | A2 showed 1 default disabling a rate limiter; the month-1 SDK design still treated defaults as safe | INC-B7: 140 instances served defaults for 6 min | Bad decision, bad outcome | Required on_missing policy at namespace creation | 1,340 namespaces still run on an inferred policy | Now: 1-quarter campaign |
| B2 | Dedicated relay tier instead of mesh xDS | Sidecar coverage 82% at M0, rising ~1 point a month | Coverage 97% at M14 | Good decision, good outcome | Re-run the xDS prototype; retire the relays if it passes the exit criteria | ~0.5 engineer of relay operations | Coverage at or above 95% (met) |
| B3 | Break-glass "booleans only" enforced by namespace naming | Safety-by-naming was a known weak pattern in month 4 | 1 harmless misuse in 14 months | Bad decision, good outcome | Schema-enforced kill-switch type, checked by the consumer parser | ~2 engineer-weeks to fix; 1 misuse so far | Before the next safety review |
| B4 | Full snapshots, no deltas | Estimated median 4 KB; measured 18 KB by M3 | Median 18 KB at M14 | Good decision, good outcome | Keep; build deltas only past the trigger | ~3.6 GB/day of egress | Median above 256 KB |
<!-- hindsight:end -->

### 6.3 The Tidewater ledger

<!-- hindsight:start name=tidewater-hindsight -->
| ID | Decision | Known then | Known now | Class | Change today | Cost of current design | Trigger to act |
|---|---|---|---|---|---|---|---|
| T1 | Dedup key = CDC log sequence number + table key | 1 CDC product in use, no change planned by the DBA team | The source moved to a new CDC product in month 11 | Bad decision, bad outcome | Business event ID minted at the source write | 2-week offset bridge; 6 tables to change | Next source system onboarded |
| T2 | Raw archive as immutable Avro files for 7 years | The EU subsidiary was in scope; erasure was not raised in the RFC review | The DPO asked about erasure in month 9 | Bad decision, bad outcome | Per-policyholder envelope encryption (crypto-shredding) from day 1 | ~40 TB/month of rewrite avoided only by a retrofit | Done for new data; history by quarterly compaction |
| T3 | Single-region streaming job, cross-region raw archive | Analytics RPO requirement 24 h | No regional outage in 14 months | Good decision, good outcome | Keep | ~$4,200/month saved against a hot standby job | RPO requirement below 1 h |
<!-- hindsight:end -->

---

## 7. Defending a good decision with a bad outcome

Interviewers sometimes lead with the outcome: "your failover took 22 minutes; wasn't single-region a mistake?" The trap is to accept the framing (outcome bias) and over-apologize.

#### How an L5 tells it

> The failover was a disaster. It was a huge mistake that we decided to stay in one region, and obviously we should have known a whole region could go down.

#### How an L7 tells it

> I'd keep the decision, and I can show why. In 2024 I chose a single-region primary with a cross-region standby over active-active, because active-active would have needed conflict resolution on the ledger, about 3 quarters of work, for a 99.95% SLO that a 15-minute failover could meet. The region outage in month 14 cost 22 minutes of checkout downtime, inside the quarterly error budget of about 65 minutes but painful. What I changed was operations: the 22 minutes were 6 of detection and 16 of manual promotion, so I automated the promotion behind a 2-signal check, and the next game day failed over in 4 minutes.

**Why it works.**
- **The decision is defended on the information it was made with:** cost, SLO and failover time.
- **The bad outcome is quantified and placed against the budget.**
- **The lesson goes to the right layer:** operations, not architecture. Changing the architecture because of one outcome that fit inside the budget would be resulting.

---

## 8. Confessing a bad decision with a good outcome

This is the rarest and most credible hindsight answer. Only an author knows which successes were luck.

#### How an L5 tells it

> It worked fine in production, so I guess the design was right. Nothing really went wrong with it, and the team was happy.

#### How an L7 tells it

> The break-glass lane was a bad decision with a good outcome. When I built it in month 4, I enforced 'booleans only' with a namespace naming convention rather than a schema type, and safety-by-naming was a known weak pattern at the time. It held for 14 months with 1 harmless misuse, and I count that as luck, not design. Today I'd make the kill switch a schema type whose values are literally true or false, validated by the consumer parser, at a cost of about 2 engineer-weeks.

---

## 9. Pitfalls

| Pitfall | Sounds like | What the interviewer hears | Fix |
|---|---|---|---|
| **The non-answer** | "Nothing", "more tests", "better documentation" | No self-critique, or no depth | A specific change in your own component (§2) |
| **Rewrite in X** | "I'd use a newer framework" | Fashion, not judgment | A delta, with a migration path (§5) |
| **Hindsight bias** | "Obviously we should have known" | Doesn't understand decisions under uncertainty | The time anchor (§1.3) |
| **Overcorrection** | "It was a terrible decision" | Resulting; poor calibration | Classify it on the 2×2 (§1.2) |
| **Blaming others** | "The other team kept changing requirements" | Disowns the outcome | Name what *you* would do differently about the requirement change |
| **External regret** | "I'd have avoided the reorg" | Not a design answer | Choose a regret within your control |
| **Changing everything** | A full redesign | No prioritization | One or two changes, hardest-to-reverse first (§3, §4) |
| **Unanchored v2** | "Today I'd use event sourcing" | Ignores the constraints that applied then | Say whether the original constraints still hold |

### 9.1 When a requirement changed under you

#### How an L5 tells it

> Honestly the problem was the other team. They kept changing requirements, so it wasn't my call, and the design ended up kind of a mess.

#### How an L7 tells it

> The requirement that changed most was erasure. The RFC scoped the raw GCS archive as immutable Avro files kept for 7 years, and in month 9 the EU subsidiary's data-protection officer asked how we'd honor an erasure request in it. Rewriting files per request would have meant about 40 TB of rewrites a month at their request rate. I added per-policyholder envelope encryption for new data, so erasure deletes 1 key, plus a quarterly compaction for the history before it. Today I'd design crypto-shredding in from the start; the question was foreseeable at the time, because the subsidiary was already in scope.

**Why it works.** The requirement change is presented as a gap *in the candidate's own design review*: the subsidiary was in scope, so the question was foreseeable. It isn't presented as another team's fault. The fix is concrete, and the hindsight principle (ask the data-protection question at design time for every in-scope jurisdiction) generalizes.

---

## 10. Worked hindsight answers across the archetypes

| Archetype | Lead regret | Class | Why it's a good lead |
|---|---|---|---|
| Beacon | `on_missing` policy required at creation | Bad decision, bad outcome | Own component; safety default; information existed then |
| A · Tidewater | Dedup on a business event ID, not CDC offsets | Bad decision, bad outcome | A key: one-way door; migration path exists |
| B · Tillpoint | Integer minor units + currency code | Bad decision, bad outcome | Data model: the hardest class to change |
| C · low-latency cache (Folder 03) | A memory-accounting boundary per tenant from day 1 | Good decision, bad outcome *or* bad decision, depending on the facts | Isolation retrofits are expensive in C++ allocators |
| D · embedded firmware (Folder 03) | Bus timeouts made explicit requirements with tests, not defaults | Bad decision, good outcome (often) | Verification evidence can't be retrofitted cheaply under certification |

Folder 03 develops each archetype's hindsight with its own facts.

---

## 11. Hiring-committee scoring rubric: hindsight

Bands follow the poor / borderline / solid / outstanding vocabulary of Google's public structured-interviewing guidance ([re:Work](https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices)). The anchors are a composite (⚠).

| Dimension | Poor | Borderline | Solid (L6) | Outstanding (L7) |
|---|---|---|---|---|
| **Specificity** | "Nothing" / "more tests" | A generic improvement | A specific change in an owned component | A specific change in a one-way door, with its cost counted |
| **Time anchor** | Hindsight bias | Some context | What was known then, stated | Known then vs known now, and whether the outcome was foreseeable from that |
| **Decision vs outcome** | Judges by outcome | Some separation | Classifies correctly | Defends a good decision with a bad outcome; confesses a bad decision with a good one |
| **v2 judgment** | Full rewrite | A delta, no path | Delta with a migration path | Delta, path and trigger; the change also makes future changes cheap |
| **Growth** | None visible | A lesson stated | A principle held now | A principle held now, with evidence of having applied it since |

---

## 12. The hindsight checker

### 12.1 Listing L6: `hindsight_check.py`

<!-- listing:hindsight_check.py -->
```python
#!/usr/bin/env python3
"""hindsight_check.py - validate a hindsight ledger and lint "what would you change?" answers.

Part 1 - ledger. Every table between
    <!-- hindsight:start name=<label> -->  ...  <!-- hindsight:end -->
must have the columns
    ID | Decision | Known then | Known now | Class | Change today | Cost of current design | Trigger to act
and each row must:
  * fill every cell;
  * use a Class from the decision-vs-outcome grid (CLASSES);
  * describe "Known then" without hindsight bias ("obviously", "should have known" ...);
  * propose a specific change (not "more tests", "better docs", "rewrite it", "nothing");
  * quantify the cost of the current design (a digit).
Each ledger must also own at least one bad decision: a ledger of only good
decisions is not self-critique.

Part 2 - tellings. Every "#### How an L5/L7 tells it" blockquote is checked for
  HINDSIGHT-BIAS   it was obvious / should have known / everyone could see
  NON-ANSWER       more tests / better documentation / nothing / rewrite it in X
  OVERCORRECTION   terrible / huge mistake / I was stupid (blame without analysis)
  NO-TIME-ANCHOR   no sign of what was known *then* (at the time, month N, back then ...)

Ledgers named l5-* are negative examples and are expected to fail.
Usage: python -I hindsight_check.py <file.md>
"""
import re
import sys

COLUMNS = ["ID", "Decision", "Known then", "Known now", "Class", "Change today",
           "Cost of current design", "Trigger to act"]
CLASSES = {"Good decision, good outcome", "Good decision, bad outcome",
           "Bad decision, good outcome", "Bad decision, bad outcome"}
BIAS = re.compile(r"\b(obviously|should have known|it was clear|everyone could see|"
                  r"in retrospect it was obvious|anyone could see|was always going to)\b", re.I)
NONANSWER = re.compile(r"\b(more tests|better documentation|better docs|add more monitoring|"
                       r"nothing|rewrite it|rewrite in|use a newer version)\b", re.I)
OVER = re.compile(r"\b(terrible|huge mistake|i was stupid|disaster|awful|complete failure)\b", re.I)
ANCHOR = re.compile(r"\b(at the time|back then|then|in month \d+|month \d+|M\d+|in 20\d\d|"
                    r"when (we|I) (designed|chose|built|started)|before|originally|in the RFC)\b")
EMPTY = {"", "-", "—", "tbd", "?", "n/a", "none"}
HEADING = re.compile(r"^#### How an? (L\d) tells it\s*$")


def ledgers(md):
    out = []
    for m in re.finditer(r"<!-- hindsight:start name=(\S+) -->\n(.*?)<!-- hindsight:end -->", md, re.S):
        rows = [r for r in m.group(2).splitlines() if r.strip().startswith("|")]
        out.append((m.group(1), [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]))
    return out


def check_ledger(name, cells):
    probs = []
    header, body = cells[0], cells[2:]
    if header != COLUMNS:
        return [f"{name}: header must be {COLUMNS}"]
    col = {c: i for i, c in enumerate(header)}
    bad_owned = False
    for row in body:
        rid = row[0]
        if len(row) != len(header):
            probs.append(f"{name}/{rid}: {len(row)} cells")
            continue
        for c in COLUMNS:
            if re.sub(r"[*_`]", "", row[col[c]]).strip().lower() in EMPTY:
                probs.append(f"{name}/{rid}: empty '{c}'")
        cls = row[col["Class"]]
        if cls not in CLASSES:
            probs.append(f"{name}/{rid}: Class '{cls}' not in the decision/outcome grid")
        if cls.startswith("Bad decision"):
            bad_owned = True
        m = BIAS.search(row[col["Known then"]])
        if m:
            probs.append(f"{name}/{rid}: hindsight bias in 'Known then' ('{m.group(0)}')")
        m = NONANSWER.search(row[col["Change today"]])
        if m:
            probs.append(f"{name}/{rid}: non-answer in 'Change today' ('{m.group(0)}')")
        if not re.search(r"\d", row[col["Cost of current design"]]):
            probs.append(f"{name}/{rid}: 'Cost of current design' has no number")
    if not bad_owned:
        probs.append(f"{name}: no row owns a bad decision (Class 'Bad decision, ...')")
    return probs


def tellings(md):
    out, lines, i, fence = [], md.splitlines(), 0, False
    while i < len(lines):
        if lines[i].startswith("```"):
            fence = not fence
        m = None if fence else HEADING.match(lines[i])
        if m:
            j = i + 1
            while j < len(lines) and not lines[j].strip():
                j += 1
            body = []
            while j < len(lines) and lines[j].startswith(">"):
                body.append(lines[j][1:].strip())
                j += 1
            out.append((m.group(1), " ".join(body)))
            i = j
            continue
        i += 1
    return out


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    md = open(sys.argv[1], encoding="utf-8").read().replace("\r\n", "\n")
    ok = True
    for name, cells in ledgers(md):
        probs = check_ledger(name, cells)
        print(f"ledger {name}: {len(cells) - 2} row(s) -> {'PASS' if not probs else str(len(probs)) + ' problem(s)'}")
        for p in probs:
            print(f"    - {p}")
        ok &= bool(probs) == name.startswith("l5")
    print()
    seen = {"L5": [0, 0], "L7": [0, 0]}
    for n, (lvl, text) in enumerate(tellings(md), 1):
        plain = re.sub(r"[*_`]", "", text)
        hits = [(r, m.group(0)) for r, rx in (("HINDSIGHT-BIAS", BIAS), ("NON-ANSWER", NONANSWER),
                                              ("OVERCORRECTION", OVER)) for m in rx.finditer(plain)]
        if not ANCHOR.search(plain):
            hits.append(("NO-TIME-ANCHOR", "nothing marks what was known then"))
        if lvl in seen:
            seen[lvl][0] += 1
            seen[lvl][1] += 1 if hits else 0
        state = "; ".join(f"{r}: {h}" for r, h in hits) if hits else "clean"
        print(f"T{n:02d} {lvl}: {state}")
    print()
    for lvl in ("L5", "L7"):
        print(f"{lvl}: {seen[lvl][0]} telling(s), {seen[lvl][1]} flagged")
    ok &= seen["L5"][0] == seen["L5"][1] and seen["L7"][1] == 0
    print("verdict:", "OK (l5 ledgers fail, other ledgers pass, L5 tellings flagged, L7 clean)" if ok else "CHECK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

### 12.2 Output on this file

<!-- output:hindsight_check.py -->
```text
ledger l5-hindsight: 2 row(s) -> 10 problem(s)
    - l5-hindsight/H1: empty 'Cost of current design'
    - l5-hindsight/H1: empty 'Trigger to act'
    - l5-hindsight/H1: non-answer in 'Change today' ('Nothing')
    - l5-hindsight/H1: 'Cost of current design' has no number
    - l5-hindsight/H2: empty 'Trigger to act'
    - l5-hindsight/H2: Class 'Good call' not in the decision/outcome grid
    - l5-hindsight/H2: hindsight bias in 'Known then' ('Obviously')
    - l5-hindsight/H2: non-answer in 'Change today' ('More tests')
    - l5-hindsight/H2: 'Cost of current design' has no number
    - l5-hindsight: no row owns a bad decision (Class 'Bad decision, ...')
ledger beacon-hindsight: 4 row(s) -> PASS
ledger tidewater-hindsight: 3 row(s) -> PASS

T01 L5: NON-ANSWER: more tests; NON-ANSWER: better documentation; NO-TIME-ANCHOR: nothing marks what was known then
T02 L7: clean
T03 L5: NO-TIME-ANCHOR: nothing marks what was known then
T04 L7: clean
T05 L5: NO-TIME-ANCHOR: nothing marks what was known then
T06 L7: clean
T07 L5: HINDSIGHT-BIAS: obviously; HINDSIGHT-BIAS: should have known; OVERCORRECTION: disaster; OVERCORRECTION: huge mistake; NO-TIME-ANCHOR: nothing marks what was known then
T08 L7: clean
T09 L5: NON-ANSWER: Nothing; NO-TIME-ANCHOR: nothing marks what was known then
T10 L7: clean
T11 L5: NO-TIME-ANCHOR: nothing marks what was known then
T12 L7: clean

L5: 6 telling(s), 6 flagged
L7: 6 telling(s), 0 flagged
verdict: OK (l5 ledgers fail, other ledgers pass, L5 tellings flagged, L7 clean)
```

**Reading the output.**
- **`l5-hindsight` fails on almost every rule:** non-answers, hindsight bias, an invalid class, an unquantified cost, and no bad decision owned.
- **The Beacon and Tidewater ledgers pass,** and each owns at least one bad decision.
- **Every L5 telling trips a hindsight rule;** every L7 telling has a time anchor and none of the flagged phrases. The gate also runs the Folder 01 lints over these tellings.

---

## 13. Failure modes

| # | Failure mode | Symptom | Fix |
|---|---|---|---|
| F1 | **Non-answer** | "I wouldn't change anything" | The three-part answer (§2) |
| F2 | **Two-way-door regret only** | "I'd use a different logging library" | Lead with a one-way door (§4) |
| F3 | **Resulting** | Regrets a good decision because of one bad outcome | The 2×2 (§1.2); defend it (§7) |
| F4 | **Hindsight bias** | "Obviously…" | The time anchor (§1.3) |
| F5 | **Overcorrection** | "Terrible decision" | Calibrate; classify |
| F6 | **Blame** | The other team changed requirements | Your design review's gap (§9.1) |
| F7 | **Fantasy v2** | A redesign with no path from v1 | Delta plus migration path (§5) |
| F8 | **No cost** | "It would be better" | Quantify the cost of the current design |
| F9 | **Running out of time** | Hindsight squeezed into minute 59 | It's in the never-cut list (01.1 §10); the 30-second version |

---

## 14. Bar-raiser chains

<details><summary><b>Q1 · "Knowing what you know now, what would you change?"</b></summary>

**Initial Prompt.** At minute 50: "If you started this project today, what would you do differently?"

**L5 Answer.** "Honestly, not much. I think the architecture held up well. Maybe more automated tests from the start."

**Why L5 Stalls.** Every system has flaws its author knows about. "Not much" signals either a passenger (who can't see the flaws) or low self-critique. "More tests" applies to every project ever built, so it carries no information.

**L7 Answer.** "Two things, the bigger first. One: I'd make the `on_missing` policy a required field at namespace creation. At the time, I treated compiled-in defaults as safe, even though A2 had already shown a default disabling a rate limiter, and INC-B7 was the bill for that missed inference. 1,340 namespaces still run on an inferred policy, and I'd fix that now with a required-on-next-edit campaign. Two: I'd re-run the xDS prototype. My relay-tier decision was right at 82% sidecar coverage, but coverage is 97% now, and the relays cost about half an engineer to operate. The first is a bad decision I own; the second is a good decision whose premise has expired."

</details>

<details><summary><b>Q2 · "Your failover took 22 minutes. Wasn't single-region a mistake?"</b></summary>

**Initial Prompt.** The interviewer leads with the outcome: "You had a 22-minute outage when the region failed. Admit it: you should have gone multi-region."

**L5 Answer.** "Yes, in hindsight that was a mistake. We should have built active-active from the start."

**Why L5 Stalls.** Accepting the framing is resulting: judging the decision by its outcome. It also commits the candidate to 3 quarters of conflict-resolution work that the SLO didn't require. An L7 interviewer often tests exactly this capitulation.

**L7 Answer.** "I'd make the same decision. Active-active meant conflict resolution on the ledger, about 3 quarters of work, and the SLO was 99.95%: about 65 minutes of quarterly budget, which a 15-minute failover meets. 22 minutes fit inside the budget. The real lesson was in the failover itself: 6 minutes of detection and 16 of manual promotion. I automated promotion behind a 2-signal check, and the next game day took 4 minutes. If the SLO were 99.99%, about 13 minutes a quarter, I'd revisit active-active, because then even a 4-minute failover spends a third of the budget."

</details>

<details><summary><b>Q3 · "Name a decision that worked out but that you'd still call a mistake."</b></summary>

**Initial Prompt.** "Tell me about something that went fine in production but that you think was a bad decision."

**L5 Answer.** "If it went fine, I'm not sure it was a mistake. Results are what count."

**Why L5 Stalls.** "Results are what count" is resulting stated as a philosophy. The interviewer is testing whether the candidate can evaluate a decision independently of its outcome, which is a core senior skill for risk decisions.

**L7 Answer.** "The break-glass lane's 'booleans only' rule, which I enforced by naming convention instead of a schema type. Safety by naming was a known weak pattern when I built it in month 4. It held for 14 months with 1 harmless misuse, and I count that as luck. The test I apply: if a careless team had misused it, would the failure have been prevented by design? It wouldn't, so it was a bad decision that happened to have a good outcome. The fix is a schema-enforced kill-switch type, about 2 engineer-weeks, and I've scheduled it before the next safety review."

</details>

<details><summary><b>Q4 · "Draw v2 on the board."</b></summary>

**Initial Prompt.** "Show me the system you'd build today. Draw it."

**L5 Answer.** The candidate erases the board and draws a new architecture with different technologies, without reference to the existing system.

**Why L5 Stalls.** A fresh drawing hides the delta, so the interviewers can't see what changed or why. It also has no migration path: there's no way to get from the running system to the new one, so it reads as a whiteboard fantasy.

**L7 Answer.** The candidate keeps the existing diagram and adds two red annotations. First, the dedup key: business event ID minted at the source write instead of the CDC offset, with the path of a new column in 6 tables, dual-key dedup for 1 retention window (7 days), then dropping the offset key. Second, the raw archive: per-policyholder envelope encryption for crypto-shredding, with new data encrypted from the cutover date and history handled by quarterly compaction. "Everything else stays. The streaming topology and the reconciliation job still fit the requirements. Both changes are one-way doors in v1, and both make the next change cheaper: a CDC product swap becomes invisible, and an erasure request becomes a key deletion."

</details>

<details><summary><b>Q5 · "Wasn't that obvious at the time?"</b></summary>

**Initial Prompt.** After the candidate names a regret: "That seems obvious. Why didn't you see it then?"

**L5 Answer.** "Yeah, it was pretty obvious, we just didn't have time to do it properly."

**Why L5 Stalls.** It combines hindsight bias ("pretty obvious") with an excuse ("didn't have time"). Both undermine the candidate. If it was obvious, why miss it? If time was the reason, where is the risk-acceptance record (01.3 §5.5)?

**L7 Answer.** "Part of it was foreseeable and part wasn't, and I'd separate them. The erasure question was foreseeable: the EU subsidiary was in scope in the RFC, and I didn't put a data-protection question in the design review checklist. That's my gap, and the checklist has it now. What wasn't foreseeable was the timing. The DPO's first erasure request came in month 9, and the retrofit cost was driven by 40 TB a month of archive growth, which was 3 times the RFC's estimate. So the lesson is a process change in my reviews, not a claim that I should have predicted everything."

</details>

<details><summary><b>Q6 · "What did you learn that you've applied since?"</b></summary>

**Initial Prompt.** "Hindsight is cheap. Show me a lesson from this project that you've actually applied on a later one."

**L5 Answer.** "I've learned to think more about failure modes and edge cases in general."

**Why L5 Stalls.** A general lesson with no evidence of application is unfalsifiable. The interviewer asked for proof of growth, not a statement of intent.

**L7 Answer.** "The `on_missing` lesson: every fallback needs an owner who has decided it's safe. On my next project, a pricing-rules distribution system, I put a required `on_unavailable` field in the rule schema before the first rule shipped. It has 3 values (serve last-known, serve the list price, refuse the sale), and each rule owner chooses one at creation. In the first quarter the review caught 2 rule sets whose owners would have defaulted to the list price, which for 1 of them meant selling below cost during an outage. That's the evidence the lesson transferred."

</details>

<details><summary><b>Q7 · "What would you change about how you ran the project, not the design?"</b></summary>

**Initial Prompt.** "Set the architecture aside. What would you change about how you led the work?"

**L5 Answer.** "Maybe communicate more with stakeholders. Communication is always something to improve."

**Why L5 Stalls.** "Communicate more" is the leadership equivalent of "more tests": generic, and impossible to check. The interviewer wants a specific process decision and its consequence.

**L7 Answer.** "I'd have started the 37 owning teams on their mismatch fixes 2 months earlier. In the original plan, the compat-shim template shipped in month 3 with the shadow mode, so teams first saw their mismatches then, and the 3-week slip in month 6 came from teams fixing mismatches on their own backlog schedules. If I'd run a read-only inventory of ZooKeeper usage in month 1, I'd have known the 37 teams and their mismatch counts before writing the cutover plan, and I'd have negotiated their capacity then. It was a sequencing mistake: I put the tool before the inventory."

</details>

<details><summary><b>Q8 · "Would you choose the same technologies today?"</b></summary>

**Initial Prompt.** "Beam and Dataflow: same choice today, or something else?"

**L5 Answer.** "I'd probably look at newer options. There are a lot of new streaming tools now that might be better."

**Why L5 Stalls.** "Newer options" without a requirement that the current choice fails is fashion. The interviewer is testing whether the candidate re-evaluates technology against requirements or against novelty.

**L7 Answer.** "I'd re-run the decision against the same kill criteria rather than against what's new. The kill criteria were 30-minute freshness, exactly-once effects on the warehouse, and the same code for backfill and streaming. Beam on Dataflow still passes all 3. The scored criterion that changed is cost: our volume grew about 35% a year, and at roughly 7,300 million events a month the managed runner's variable cost dominates. So the question I'd examine today isn't 'which framework' but 'which runner'. Beam's portability means the same pipeline could run on another runner, and I'd prototype that only if cost per million events rose above a threshold I'd set, about $12, against $10.29 now."

</details>

<details><summary><b>Q9 · "What would your successor say you got wrong?"</b></summary>

**Initial Prompt.** "The engineer who inherited this system from you: what do they curse you for?"

**L5 Answer.** "I documented everything pretty well, so I hope not much."

**Why L5 Stalls.** Every inherited system has rough edges its owner knows about. "I hope not much" is a deflection. The interviewer wants the operational debt the candidate left behind, which only an author knows.

**L7 Answer.** "Two things, and I know because I asked her. First, the compat shims: 8 of 37 were still open when I left, each with an owner and a deletion date, but each is code that translates legacy quirks, and debugging through a shim is painful. Second, the gate thresholds in the rollout controller live in code, not config, so tuning the 2,000-request minimum for a low-traffic namespace needs a deploy. I made that choice in month 2 to keep the controller's behavior reviewable, and in hindsight a reviewed config file would have given the same auditability without the deploy. She has since moved them, and I'd do it that way from the start."

</details>

<details><summary><b>Q10 · "Is there anything you'd *not* change, even though people criticize it?"</b></summary>

**Initial Prompt.** "What part of your design gets criticized that you'd defend today?"

**L5 Answer.** "I think most of the criticism was fair, so I'd probably change most of it."

**Why L5 Stalls.** Capitulating to all criticism is as uncalibrated as rejecting all of it. A senior engineer should be able to name a criticized decision and defend it on its merits.

**L7 Answer.** "Full snapshots instead of deltas. It's the most common criticism from engineers who see the design for the first time: 'you re-send 18 KB to change 1 key?' I'd defend it today. The median is still 18 KB at month 14, total egress is about 3.6 GB a day, and full snapshots give 2 properties deltas don't: a client can never apply a change to the wrong base, and any client can recover from any state with 1 fetch. Deltas would add a base-version protocol and a recovery path for a saving that's under 4 GB a day. The trigger for revisiting is written down: a median above 256 KB."

</details>

---

## 15. Checklist

- [ ] Two hindsight answers prepared in the three-part form: the change, why not then (with a time anchor), the cost and a trigger (§2).
- [ ] The lead regret is a one-way door in a component you owned (§3, §4).
- [ ] One good decision with a bad outcome, defended (§7).
- [ ] One bad decision with a good outcome, confessed, if you have one (§8).
- [ ] A v2 delta with a migration path, drawable on the existing board (§5).
- [ ] A lesson you've applied since, with evidence (Q6).
- [ ] One criticized decision you'd defend today (Q10).
- [ ] Your hindsight ledger passes `hindsight_check.py`, and owns at least one bad decision (§12).
- [ ] The 30-second hindsight version, for when time runs out (01.1 §10).

---

## 16. References

- Baruch Fischhoff, "Hindsight ≠ foresight: The effect of outcome knowledge on judgment under uncertainty", *Journal of Experimental Psychology: Human Perception and Performance* 1(3):288–299, 1975. DOI 10.1037/0096-1523.1.3.288 (verified via Crossref).
- Annie Duke, *Thinking in Bets: Making Smarter Decisions When You Don't Have All the Facts*, Portfolio/Penguin, 2018, ISBN 978-0-7352-1635-8 (verified via Open Library).
- Amazon, 2015 Letter to Shareholders (one-way and two-way doors). <https://s2.q4cdn.com/299287126/files/doc_financials/annual/2015-Letter-to-Shareholders.PDF>
- Michael Nygard, "Documenting Architecture Decisions" (ADR status and consequences; superseding a decision). <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
- Google SRE Book, "Postmortem Culture: Learning from Failure". <https://sre.google/sre-book/postmortem-culture/>
- Google re:Work, "A guide to structured interviewing for better hiring practices". <https://rework.withgoogle.com/intl/en/guides/a-guide-to-structured-interviewing-for-better-hiring-practices>
