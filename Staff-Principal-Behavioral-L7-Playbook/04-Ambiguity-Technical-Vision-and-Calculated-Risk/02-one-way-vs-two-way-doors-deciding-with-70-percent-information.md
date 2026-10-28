# 04.2 · One-Way vs Two-Way Doors: Deciding with 70% of the Information

> **Folder 04 · File 2 of 3.** Senior engineers are paid for decisions made under uncertainty. The behavioral loop tests two opposite failure modes: the engineer who **studies a reversible decision for a quarter**, and the engineer who **moves fast through an irreversible one**. Both are judgment failures, and an L7 can tell you, for every big decision in their stories, which kind of door it was and how they treated it accordingly.
>
> This file covers:
> - Bezos's Type 1 and Type 2 decisions, and why reversibility is a cost, not a binary;
> - an engineering catalogue of one-way and two-way doors;
> - converting one-way doors into two-way doors;
> - the 70% rule operationalized: cost of delay, buying information, tripwires;
> - calculated risk: expected value, ruin, pre-mortems and decision records;
> - a rubric, three story blueprints and five follow-up chains.
>
> Stories are **illustrative composites**.

---

## 1. The two doors

Jeff Bezos's 2015 letter to shareholders distinguished two kinds of decision:
- **Type 1:** "consequential and irreversible or nearly irreversible", one-way doors. They should be made "methodically, carefully, slowly, with great deliberation and consultation".
- **Type 2:** "changeable, reversible", two-way doors. They "can and should be made quickly by high judgment individuals or small groups".

His warning was about the second kind: as organizations grow, they tend to use the heavyweight Type 1 process for most decisions, including Type 2 ones, and the result is slowness, unthoughtful risk aversion and less invention.

The 2016 letter added the operating rule: "most decisions should probably be made with somewhere around 70% of the information you wish you had. If you wait for 90%, in most cases, you're probably being slow." It continued: being good at quickly recognizing and correcting bad decisions makes being wrong less costly than you think, "whereas being slow is going to be expensive for sure."

### 1.1 Reversibility is a cost, not a category

In engineering, almost nothing is perfectly irreversible, and almost nothing is free to undo. The useful measure is:

> **cost of being wrong = cost to reverse × (time to detect the error + time to reverse it)**, plus anything that can't be recovered at all (lost data, broken customer trust, a missed market window).

That gives a spectrum, and two questions an L7 asks of every decision:
1. **How expensive is it to undo, and how fast would we know we need to?**
2. **Can we make it cheaper to undo before we commit?**

---

## 2. An engineering catalogue of doors

| Usually one-way (or expensive to reverse) | Why | Usually two-way | Why |
|---|---|---|---|
| **Public API contracts** and event schemas with external consumers | Every integration depends on them (02.3: Stripe versioning) | Internal APIs with few consumers | You can change callers yourself |
| **Data deletion** and lossy migrations | Data can't be recovered | Data migrations that keep the old copy until verified | Rollback is a pointer swap |
| **Identifier formats and semantics** | They spread into every system and log | Internal implementation choices | Hidden behind an interface |
| **Primary datastore for a core domain** | Migrating off takes quarters | Caching layers, read replicas | Remove and fall back |
| **Multi-year vendor commitments** | Contractual | Month-to-month services behind an abstraction | Switchable |
| **Customer-visible pricing and promises** | Trust and contracts | Feature flags and experiments | Turned off in seconds |
| **Security and privacy exposure** | Leaked data stays leaked | Config, timeouts, thresholds | Changed in a deploy |
| **Org structure and ownership** | Disruptive to people | Tooling choices inside a team | Low switching cost |

The trap in both directions:
- **Treating a two-way door as one-way:** a design review lasting six weeks over a cache eviction policy.
- **Treating a one-way door as two-way:** "we'll fix the ID format later", said about IDs that partners are about to store in their databases.

---

## 3. Converting one-way doors into two-way doors

Often the most valuable thing an L7 does with a one-way decision is **not make it yet**, by building the means to make it reversibly:

| Technique | What it converts |
|---|---|
| **Abstraction layer** over a vendor or datastore | Vendor lock-in → switchable (at a known cost) |
| **Feature flags and dark launches** | A launch → a toggle |
| **Shadow mode** (run the new path alongside the old, compare, don't serve) | A risky cutover → an observation |
| **Dual-write with reconciliation** | A data migration → a reversible pointer swap |
| **API versioning** | A contract change → an opt-in |
| **Cells and pilots** (one region, one tenant tier, one market) | A global change → a local experiment |
| **Contract terms** (exit clauses, shorter initial terms, committed spend in tranches) | A multi-year bet → staged commitments |
| **Keep the old system warm** for a defined period | A decommission → a fallback |

Each costs something: engineering time, duplicated infrastructure, slower full rollout. The L7 judgment is whether **the option value is worth the cost** of keeping the door open.

---

## 4. The 70% rule, operationalized

"Decide with 70%" is not a licence to guess. It's a discipline with four steps:

| Step | Question | Example |
|---|---|---|
| **1. Classify the door** | How expensive to reverse, and how fast would we know? | Autoscaling policy: minutes to revert, alarms within minutes → two-way |
| **2. Price the delay** | What does waiting cost? | Each week without the new policy costs $X K in over-provisioning, and peak arrives in six weeks |
| **3. Price the missing information** | What would the missing 30% tell us, and can we buy it cheaply? | A load test at 3× would take two weeks; a canary on 5% of traffic would take two days |
| **4. Decide, then design the detection** | What tripwire tells us we were wrong, and what do we do then? | "If p99 rises above 250 ms or errors exceed 0.5% on the canary, revert automatically" |

Step 4 is the one candidates leave out, and it's what makes a fast decision safe. **Speed of decision depends on speed of detection.** If you can't detect an error quickly, the door is effectively one-way, however easy the rollback.

---

## 5. Calculated risk

Amazon's Bias for Action principle ends: "We value calculated risk taking." The calculation an L7 can articulate:

1. **Expected value:** probability-weighted outcomes. Necessary, but not sufficient.
2. **Ruin:** avoid any option with a meaningful chance of an unrecoverable outcome (data loss, a regulatory breach, a company-ending outage), even if its expected value is positive.
3. **Asymmetry:** prefer bets where the downside is capped and the upside isn't. Reversibility is what caps the downside.
4. **Base rates:** how often do projects like this one succeed? Your plan's optimism is not evidence.
5. **Pre-mortem:** Gary Klein's technique: assume the decision has failed, and have everyone write down why. It surfaces risks that a "does anyone have concerns?" meeting doesn't.
6. **Decision record:** write down what you decided, what you knew, what you assumed, and what would change your mind. Michael Nygard's architecture decision records (ADRs) are the lightweight engineering form. They also let you judge the decision later by its **process** rather than only its outcome: a good decision can have a bad outcome. Annie Duke's *Thinking in Bets* calls the opposite mistake "resulting".

---

## 6. Hiring Committee Scoring Rubric

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | No hire |
|---|---|---|---|---|
| **Classification** | Names the door type for each major decision, with the cost-of-being-wrong reasoning | Distinguishes reversible from irreversible | Treats all decisions alike | Doesn't think about reversibility |
| **Speed on two-way doors** | Decided quickly with partial information, priced the delay, bought cheap information | Moved quickly | Waited for certainty | Moved recklessly or never |
| **Care on one-way doors** | Slowed the irreversible part down, converted what could be converted, decided the rest deliberately | Careful with risky changes | Same pace for everything | Rushed an irreversible decision |
| **Detection** | Tripwires and kill criteria set before deciding; automated where possible | Monitoring in place | Hoped it would work | No detection |
| **Calculated risk** | Expected value, ruin and asymmetry explicit; pre-mortem; a decision record | Considered risks | Listed risks | Ignored risks |
| **Learning** | Judges decisions by process as well as outcome; can describe a good decision with a bad outcome, and vice versa | Reflects on outcomes | Outcome only | Doesn't reflect |

---

## 7. Story Blueprints

### 7.1 Moving fast through a two-way door (composite: a pre-peak scaling change with incomplete data)

**The facts (composite):** six weeks before a seasonal peak, a new autoscaling policy promises to cut over-provisioning by 40%, but there's no time for the full load-test cycle the team normally runs.

#### How an L5 tells it

> "Before our holiday peak, we had a new autoscaling policy we wanted to use, but we didn't have time for full load testing. We decided to be safe and keep the old policy for the peak, then switch afterwards. It meant we over-provisioned a lot, but peak went smoothly."

**What the committee extracts:** a safe call, but one that treated a reversible decision as irreversible and paid the full cost of delay. **L5.**

#### How an L7 tells it

> "Six weeks before our seasonal peak, a new autoscaling policy promised to cut our over-provisioning by about 40%, roughly $X K a week through the peak. Our normal process was a four-week load-test cycle, which would have pushed the change past peak and cost us all of that saving.
>
> I treated it as a two-way door, because it was: the policy was a config change that could be reverted in under two minutes, and our latency alarms would tell us within five. What made it risky wasn't reversibility, but detection under a sudden surge. So instead of the full load test, I designed a cheaper way to get the missing information. We ran the new policy on 5% of traffic for a week, including a deliberate surge test at off-peak hours, replaying the previous year's worst ten minutes.
>
> I set the tripwires before we started: if p99 latency rose above 250 ms, or scale-up lag exceeded 90 seconds during the surge, the controller would revert automatically to the old policy. I also kept a floor of capacity equal to last year's peak for the two highest-traffic days, because those were the days when an error would be hardest to recover from.
>
> The canary held, so we rolled it out over a week. Through peak we saved about 35% of over-provisioning cost. The tripwire fired once, on a regional surge, reverted that region automatically in under two minutes, and nobody outside the on-call channel noticed. The canary-plus-surge-replay approach is now our standard alternative to the full cycle for any reversible scaling change."

**What the committee extracts:** classified the door; priced the delay; recognized that detection, not rollback, was the real risk; bought cheap information; set tripwires in advance, automated; capped the downside on the worst days; a reusable practice. **L7.**

### 7.2 Slowing down on a one-way door (composite: partner API identifier semantics)

**The facts (composite):** a team is about to launch a partner API that 2,000 partners will integrate in the first year. It exposes order IDs that encode the region and a sequence number.

#### How an L5 tells it

> "We were launching a partner API, and I noticed our order IDs exposed some internal details. I raised it, but we were under pressure to launch, so we shipped and planned to change the IDs in v2. When we tried to change them later, partners pushed back because it would break their systems, so we still have the old format."

**What the committee extracts:** spotted the issue but treated an irreversible decision as reversible; the cost landed later. **L5.**

#### How an L7 tells it

> "Three weeks before launching a partner API that 2,000 partners would integrate in its first year, I reviewed the contract and found that our order IDs encoded the region and a sequence number. Partners would store those IDs in their own databases, and some would parse them. That made the ID format a one-way door: once partners depended on it, we could never move an order between regions or change our sharding without breaking them.
>
> The launch team's view was reasonable: the date was committed to two launch partners, and 'we'll fix it in v2' had worked for other changes. My argument was about which parts of the launch were reversible. Almost everything was: endpoints could be versioned, fields could be added, behaviour could be flagged. The ID format was not.
>
> So I proposed slowing down only that part. We'd issue opaque IDs, random and with no meaning, mapped to internal IDs in a lookup service. That took two engineers about two weeks, and would cost a small amount of read latency. I also wrote the identifier rules into the API style guide: external identifiers are opaque, documented as such, and must never be parsed.
>
> The launch slipped by one week, not three, because the rest of the launch went ahead in parallel. I told the two launch partners myself why, and both agreed. Two years later, we re-sharded the order store and moved several large merchants between regions, with zero partner-visible changes. That would have been impossible with the original IDs."

**What the committee extracts:** identified the one irreversible element inside a mostly reversible launch; slowed down only that element; made the change cheaply; codified the rule; managed the external impact personally; proven value later. **L7 one-way-door judgment.**

### 7.3 A calculated risk that failed (composite: betting on a new storage engine)

#### How an L5 tells it

> "We tried a new storage engine for our metrics system because it was supposed to be much faster. It turned out to have stability problems under our load, so we had to roll back. It was a learning experience, and we're more careful now about trying new technologies."

**What the committee extracts:** a failed bet with no stated reasoning, no limits on downside, and a generic lesson ("more careful"). **L5.**

#### How an L7 tells it

> "Our metrics platform's storage costs were growing faster than our fleet, and a newer storage engine promised about 5× compression on our data shape. I made the bet to adopt it. I knew it was less mature than our existing engine, so I structured the bet to cap the downside.
>
> First, I wrote down why: the expected saving, about $X M a year, and the main risk, stability under our write pattern, which the engine's community hadn't tested at our scale. Second, I made it reversible: the new engine ran behind our existing query layer, fed by a dual write, with the old engine kept as the source of truth for 90 days. Third, I set tripwires: any data loss on a validation sample, or a p99 query latency regression over 2× for a week, and we'd stop.
>
> Seven weeks in, the second tripwire fired. Under compaction during our daily peak write window, query latency spiked to four times baseline. We spent a week trying to tune it, which I'd budgeted for, and then I made the call to stop. Because of the dual write, stopping meant removing a read path, with no migration back and no data lost.
>
> The cost was about three engineer-months and some dual-write infrastructure. I wrote it up in the decision record against what we'd assumed at the start: the compression was real, and the stability risk I'd named was exactly what failed. I judged it a good bet with a bad outcome. A year later, the engine's compaction was redesigned upstream, we re-ran the same validation in two weeks using the harness we'd built, and adopted it. We're now saving most of the original estimate."

**What the committee extracts:** a calculated bet with stated reasoning; reversibility and tripwires designed up front; a budgeted tuning window; a decisive stop; cost honestly stated; judged by process as well as outcome; the harness made the later adoption cheap. **L7 calculated risk.**

---

## 8. Adversarial Bar-Raiser Follow-Up Chains

### Chain A · "Which kind of door was it?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "How reversible was that decision?" | Classification | "Fairly" | Cost to reverse, time to detect, time to reverse |
| 2 | "What part of it was irreversible?" | Decomposition | "None" or "All" | The specific element: the ID format |
| 3 | "Could you have made that part reversible?" | Conversion | Didn't consider | The opaque-ID technique and its cost |
| 4 | "Why not wait until v2?" | Judgment | "We could have" | Why partners' storage made it permanent |
| 5 | "What did slowing down cost?" | Honesty | Nothing | One week; two partners told personally |

### Chain B · "Why didn't you wait for more data?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What did you not know when you decided?" | Uncertainty | Claims certainty | The specific missing 30% |
| 2 | "What did waiting cost?" | Cost of delay | Unpriced | $X K a week through peak |
| 3 | "How did you get some of the missing information?" | Buying information | "We didn't" | Canary plus surge replay |
| 4 | "How fast would you have known you were wrong?" | Detection | Unsure | Five minutes, by alarm |
| 5 | "What did you do to protect the worst case?" | Ruin avoidance | Nothing | Capacity floor on the two peak days |

### Chain C · Tripwires and kill criteria

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "When did you set the stop conditions?" | Pre-commitment | After problems appeared | Before starting, in writing |
| 2 | "Who decided to stop?" | Ownership | "It was clear" | "I made the call" |
| 3 | "How long did you try to fix it first?" | Budgeted persistence | Indefinitely | A pre-budgeted week |
| 4 | "Was it a bad decision?" | Resulting | "Yes, it failed" | Process vs outcome, stated honestly |

### Chain D · Calculated risk

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What was the expected value?" | Quantification | Unsure | The saving, the probability, the cost |
| 2 | "What was the worst realistic outcome?" | Ruin | Didn't think | Named, and how it was excluded |
| 3 | "What's the base rate for bets like this?" | Outside view | Unknown | An honest estimate |
| 4 | "Did you run a pre-mortem?" | Method | No | What it surfaced |

### Chain E · Speed in general

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Tell me about a decision you made too slowly." | Self-awareness | None | A specific case and its cost |
| 2 | "And one you made too fast?" | Balance | None | A specific case and its cost |
| 3 | "How do you decide how much process a decision gets?" | Framework | "It depends" | The door classification |
| 4 | "How do you stop your org using one-way-door process for everything?" | L7 leverage | Unsure | A mechanism: decision rights by door type |

---

## 9. Checklist

- [ ] For every major decision in your stories, you can say which kind of door it was, and why.
- [ ] One story where you moved fast on a two-way door with partial information, priced the delay and set tripwires.
- [ ] One story where you slowed down the one irreversible part of an otherwise fast decision.
- [ ] One calculated risk that failed, with reasoning, a capped downside, a pre-set stop, and an honest process-vs-outcome judgment.
- [ ] You can name a technique for converting a one-way door into a two-way door, and what it cost.
- [ ] You never say "we'll fix it in v2" about something external parties will store or depend on.

## 10. References

- Jeff Bezos, *2015 Letter to Shareholders* (Type 1 and Type 2 decisions), PDF on Amazon's investor-relations site. <https://s2.q4cdn.com/299287126/files/doc_financials/annual/2015-Letter-to-Shareholders.PDF>
- Jeff Bezos, *2016 Letter to Shareholders* (about 70% of the information; disagree and commit). <https://www.aboutamazon.com/news/company-news/2016-letter-to-shareholders>
- Michael Nygard, "Documenting Architecture Decisions" (2011). <https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions>
- Gary Klein, "Performing a Project Premortem", *Harvard Business Review*, September 2007. <https://hbr.org/2007/09/performing-a-project-premortem>
- Annie Duke, *Thinking in Bets* (Portfolio, 2018): resulting, and judging decisions by process.
- In this KB: [02.1 Bias for Action and Are Right, A Lot](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/01-amazon-16-leadership-principles-l6-l7-bar-raiser-deep-dive.md) · [02.3 API permanence at Stripe](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/03-netflix-keeper-test-stripe-users-first-and-apple-dri-culture.md) · [04.1 Existential problems](01-identifying-unasked-existential-problems-and-writing-6-page-rfcs.md) · [04.3 Tech debt and reliability freezes](03-balancing-tech-debt-reliability-freezes-and-feature-velocity.md)
