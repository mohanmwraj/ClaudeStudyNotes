# 04.3 · Balancing Tech Debt, Reliability Freezes and Feature Velocity

> **Folder 04 · File 3 of 3.** "Tell me about a time you had to trade off speed and quality" is asked at every level. The L5 answer picks a side ("I pushed for quality", or "we shipped and fixed it later"). The L7 answer **rejects the binary for the system as a whole while making explicit trade-offs at specific moments**, and builds the mechanisms (error budgets, debt portfolios, repayment contracts) that let an organization make those trade-offs without a fight each time.
>
> This file covers:
> - why "speed vs quality" is mostly a false binary, and when it isn't;
> - a taxonomy of tech debt, and Fowler's quadrant;
> - treating debt as a portfolio: interest rate, principal, risk and strategic blocking;
> - measuring it in terms leaders recognize;
> - funding models;
> - error budgets and reliability freezes that are agreed before they're needed;
> - deliberate debt with a repayment contract;
> - a rubric, three story blueprints and five follow-up chains.
>
> Stories are **illustrative composites**.

---

## 1. Speed vs quality: mostly false, sometimes real

The DORA research program's work, summarized in Forsgren, Humble and Kim's *Accelerate* (2018), found that **throughput and stability go together**: teams that deploy more often also tend to have lower change-failure rates and faster recovery. Over months, quality is what makes speed possible.

At a specific moment, the trade-off is real: a launch window, a contract date, a competitor's move. The L7 position holds both:
- **Over the long run**, investment in quality is investment in speed, and it should be argued in those terms.
- **At decision points**, you can deliberately take on debt for a date, **if** it's prudent, recorded, owned and scheduled for repayment.

A candidate who says "I always insist on quality" sounds rigid. One who says "we shipped and fixed it later" without a repayment mechanism sounds reckless. The L7 answer is a mechanism.

---

## 2. A taxonomy of tech debt

### 2.1 Fowler's quadrant

Martin Fowler's *Technical Debt Quadrant* separates debt on two axes:

| | **Deliberate** | **Inadvertent** |
|---|---|---|
| **Reckless** | "We don't have time for design" | "What's layering?" |
| **Prudent** | "We must ship now and deal with consequences" | "Now we know how we should have done it" |

Only **prudent-deliberate** debt is a strategy. Prudent-inadvertent debt is the normal result of learning and should be repaid without blame. The reckless quadrants are what an L7 builds mechanisms to prevent.

### 2.2 The kinds of debt

| Kind | Example | How it charges interest |
|---|---|---|
| **Code** | Duplicated logic, missing tests | Slower changes; more defects |
| **Architecture** | Tight coupling between services; a shared database | Coordination cost; cascading failures |
| **Data** | Inconsistent schemas; missing lineage | Wrong decisions; slow analytics |
| **Operational** | Manual deploys; noisy alerts; missing runbooks | On-call load; slow recovery |
| **Dependency** | End-of-life runtimes and libraries | Security exposure; forced migrations |
| **Knowledge** | One person understands the system | Key-person risk; slow onboarding |
| **Test and release** | Flaky test suites; long release trains | Lower deploy frequency; risky releases |

---

## 3. Debt as a portfolio

An L5 prioritizes debt by how much it annoys them. An L7 manages it like a financial portfolio, scoring each item on four dimensions:

| Dimension | Question | Measured by |
|---|---|---|
| **Interest rate** | What does this cost us every week we don't fix it? | Engineering hours lost, incident minutes, slower lead time in the area |
| **Principal** | What does fixing it cost? | Engineer-weeks, with a range |
| **Risk** | What's the chance of a severe event, and how severe? | Incident history, exposure, blast radius |
| **Strategic blocking** | Does it block something the business wants? | Roadmap items that depend on it |

Then:
- **Fix first** what has a high interest rate and low principal (the quick wins), and anything that strategically blocks the roadmap.
- **Schedule** high-principal, high-interest items as funded programs with their own business case.
- **Insure against** high-risk items with mitigations, even before a full fix.
- **Deliberately ignore** low-interest debt, however ugly. Saying so out loud is part of the L7 signal: not all debt is worth paying.

---

## 4. Measuring it in terms leaders recognize

"The code is messy" doesn't move a roadmap. These measures do:

| Measure | What it shows |
|---|---|
| **DORA's four key metrics**: deployment frequency, lead time for changes, change failure rate, time to restore service | Delivery speed and stability |
| **Incident hours per quarter**, by cause | The reliability cost |
| **Toil percentage** (repetitive manual operational work) | Capacity lost to operations |
| **Lead time for features in the affected area** vs elsewhere | The velocity tax of the debt |
| **Onboarding time** to first meaningful change | Knowledge debt |
| **Cost of the next roadmap items** on the current base vs on a fixed one | Opportunity cost |

The last one is the most persuasive to product leaders (03.2 §4): "the next four features cost X weeks more on the current base than on a fixed one".

---

## 5. Funding models

| Model | How it works | Works well when | Fails when |
|---|---|---|---|
| **Fixed percentage** (e.g. 20% of capacity) | A standing allocation for engineering health | Debt is diffuse and steady | Large items never fit in the slice |
| **Fix as you touch it** | Improve code in the area you're changing | Debt is local | Debt is architectural |
| **Funded program** | A business case for a specific large item | High principal, high interest | The business case isn't made in business terms |
| **Platform team ownership** | A team owns a shared concern | Cross-cutting debt | The platform team becomes a bottleneck |
| **Error budgets** | Reliability spend is triggered by data (§6) | Reliability debt | The policy isn't agreed in advance |

An L7 typically uses several: a standing percentage for diffuse debt, funded programs for the big items, and error budgets for reliability.

---

## 6. Error budgets and reliability freezes

### 6.1 The mechanism

Google's SRE practice, described in *Site Reliability Engineering* (2016) and *The Site Reliability Workbook* (2018), turns the reliability-vs-velocity argument into arithmetic:
- Set a **service-level objective** (SLO), for example 99.9% of requests successful over 28 days.
- The **error budget** is the remainder: 0.1% of requests may fail.
- While budget remains, teams ship at full speed. When it's exhausted, the **error budget policy** applies. The workbook's example policy halts all changes and releases other than P0 issues and security fixes until the service is back within its SLO.

The point is that the freeze **isn't a decision anyone makes under pressure**. It's a pre-agreed consequence of data, so there's no argument at the moment it triggers.

### 6.2 Designing a freeze that works

| Element | Weak version | L7 version |
|---|---|---|
| **Agreement** | SRE announces it | Product and engineering leadership sign the policy *before* any freeze |
| **Scope** | The whole org | The service or team that spent the budget |
| **Trigger** | "Too many incidents" | Budget exhausted over the window, measured automatically |
| **Exceptions** | Negotiated each time | Pre-defined: security fixes, legal deadlines, approved by a named role |
| **Exit** | "When things are better" | Back within SLO over a defined window, plus the agreed reliability work done |
| **What the freeze is for** | Punishment | Directing capacity to the work that restores reliability |

### 6.3 The politics

Freezes fail when product leaders see them as engineering seizing the roadmap. The L7 work is mostly before the policy exists: choosing SLOs that reflect **what users experience**, agreeing them with product as product commitments, and showing that the budget gives product teams **more** freedom to ship when reliability is good.

---

## 7. Deliberate debt with a repayment contract

When you do take on debt for a date, make it prudent-deliberate in fact, not just in intention:

1. **Write it down:** what the shortcut is, why, and what it costs per week.
2. **Name an owner**, by person.
3. **Set a repayment date**, tied to an event ("within four weeks after launch"), not "later".
4. **Set a tripwire**: a condition that forces repayment early (incident count, a scaling threshold).
5. **Reserve the capacity** in the next plan *now*, when the date is being agreed. After the launch, there will always be a new priority.

---

## 8. Hiring Committee Scoring Rubric

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | No hire |
|---|---|---|---|---|
| **Framing** | Rejects the binary over the long run, makes explicit trade-offs at moments, and argues quality as speed | Balances them case by case | Picks a side | Dogmatic either way |
| **Prioritization** | A debt portfolio by interest rate, principal, risk and strategic blocking; deliberately ignores low-interest debt | Prioritized debt with data | By annoyance | No prioritization |
| **Measurement** | DORA metrics, incident hours and the cost of upcoming roadmap items | Some metrics | "It's slow" | None |
| **Mechanism** | Error-budget policy agreed by product before it was needed; funding model; repayment contracts | Negotiated reliability work | Asked for a debt sprint | Fought for time |
| **Deliberate debt** | Took on debt for a date with an owner, repayment date, tripwire and reserved capacity; repaid it | Shipped and fixed later, with a plan | Shipped and fixed after an incident | Never repaid |
| **Relationship with product** | Product leaders own the trade-offs with them; freezes happen without a fight | Good working relationship | Adversarial | "Product doesn't understand" |

---

## 9. Story Blueprints

### 9.1 An error-budget policy with a real freeze (composite: a payments-adjacent service with weekly incidents)

**The facts (composite):** a checkout-adjacent service has weekly customer-facing incidents; its product org has an aggressive roadmap and sees reliability work as engineering's preference.

#### How an L5 tells it

> "Our service had a lot of incidents, and I kept pushing for time to fix reliability, but product always prioritized features. After a really bad outage, leadership agreed to a reliability sprint. We fixed some issues, but things slipped again after a few months."

**What the committee extracts:** reliability argued as engineering's preference; won only by an outage; no lasting mechanism. **L5.**

#### How an L7 tells it

> "The promotions service had customer-facing incidents almost weekly, and each one meant checkout showed wrong prices for a while. Product and engineering had had the same argument every quarter: reliability work or features. Neither side was wrong, and there was no shared way to decide.
>
> I proposed replacing the argument with a policy. First I worked with the product director to define an SLO in terms of what customers experienced: 99.9% of checkout price lookups correct and under 300 ms, over 28 days. She owned the number as a product commitment, not an engineering one. Then we agreed an error-budget policy, signed by her and the engineering director before anything was triggered. If the budget ran out, the service froze feature releases until it was back within its SLO and the top reliability items were done. Security fixes and legal deadlines were exceptions, approved by her.
>
> The point I made to her was that the policy gave her team *more* freedom, not less: while there was budget, nobody would question a release.
>
> Five weeks later the budget ran out during a promotion launch. The freeze happened without a meeting, because the decision had been made in advance. The team spent three weeks on the top three causes: a cache stampede on promotion start, missing timeouts on a pricing dependency, and a deploy process with no canary. The service went back within budget and stayed there for the next two quarters. Deploy frequency actually *rose*, because a canary made releases cheaper. The same policy template is now used by eight services in the org, and the product director presented it at the product leadership offsite."

**What the committee extracts:** reframed a recurring fight as a missing mechanism; an SLO owned by product in customer terms; a policy agreed before it triggered; a real freeze without a fight; the work it bought; velocity went up; adopted by other services. **L7.**

### 9.2 Deliberate debt for a date, repaid (composite: a launch with a hard-coded shortcut)

#### How an L5 tells it

> "We had a hard launch date, so we took some shortcuts, like hard-coding the tax rules for the launch countries instead of building the rules engine. We planned to clean it up after the launch. We got to it a couple of quarters later, after it caused a bug when a tax rate changed."

**What the committee extracts:** a reasonable shortcut, but no owner, no date, no tripwire; repaid only after it caused harm. **L5.**

#### How an L7 tells it

> "We had a contractual launch date in three new countries, and the tax rules engine we needed would have taken six more weeks. I proposed a shortcut: hard-code the rules for those three countries behind the same interface the engine would implement, so callers wouldn't change when we swapped it.
>
> I treated the shortcut as a loan, and wrote down its terms in the launch plan. The interest was that any tax-rate change in those countries needed a code deploy, and the risk was a rate change arriving before repayment. I named the owner, myself, and the repayment date: the engine live within six weeks of launch. The tripwire was any announced tax change in a launch country, which would make repayment immediate. Most important, I got the six weeks of capacity reserved in the next quarter's plan at the same time the launch date was agreed, because after a launch there's always a new priority.
>
> We launched on the contractual date. The tripwire fired in week three, when one country announced a rate change effective the following month. Because the capacity was already reserved and the interface already matched, the team shipped the engine two weeks early, in time for the change. No customer was charged a wrong rate. The 'loan terms' section is now part of our launch-plan template for any shortcut taken to hit a date."

**What the committee extracts:** a prudent-deliberate shortcut designed to be cheap to repay; terms written down; owner, date and tripwire; capacity reserved in advance; the tripwire worked; a template. **L7 deliberate debt.**

### 9.3 A debt portfolio instead of a debt backlog (composite: 300 tickets nobody reads)

#### How an L5 tells it

> "Our team's tech debt backlog had hundreds of tickets. I organized a tech debt week where everyone picked items to fix. We closed about 40 tickets and the codebase felt better."

**What the committee extracts:** activity, not prioritization; no measured effect. **L5.**

#### How an L7 tells it

> "Our org's tech-debt backlog had about 300 tickets across six teams. Nobody read it, and debt weeks closed the easiest tickets rather than the most expensive ones. Meanwhile, lead time for changes in the fulfilment area was three times the org average.
>
> I replaced the backlog with a portfolio. With the six TLs, I scored the top fifty items on interest rate, principal, risk and whether they blocked the roadmap. Interest was measured from incident hours, lead-time data and on-call toil, not opinion. Five items accounted for most of the measured interest. The biggest was a shared database between fulfilment and inventory, which forced every schema change through a cross-team release.
>
> I wrote a one-page business case for the top three as funded programs, expressed as the cost of the next year's roadmap on the current base against a fixed one. Product leadership funded them. We also agreed, out loud, to ignore about 200 of the remaining tickets: they were ugly but cheap to live with. That was the decision that freed the teams' attention.
>
> Within three quarters, lead time in fulfilment fell from three times the org average to roughly the average, and change failure rate halved there. The portfolio review is now a quarterly half-day for the six TLs, and two of them run it."

**What the committee extracts:** replaced a list with a portfolio; measured interest from data; concentrated investment where interest was highest; business case in roadmap terms; explicitly chose to ignore low-interest debt; measured outcome in DORA terms; handed the mechanism to others. **L7.**

---

## 10. Adversarial Bar-Raiser Follow-Up Chains

### Chain A · "Why should product care?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "How did you describe the problem to the product director?" | Translation | "Tech debt" | Customer-visible price errors; the cost of the next roadmap items |
| 2 | "Who owns the SLO?" | Shared ownership | "SRE" | "The product director, as a product commitment" |
| 3 | "Why would she sign a freeze policy?" | Influence | "We made her" | "It gave her team more freedom while budget remained" |
| 4 | "What happened when it triggered?" | Mechanism | A negotiation | "No meeting. The decision was already made" |
| 5 | "Did velocity suffer?" | Outcome honesty | Avoids | Deploy frequency rose, with the reason |

### Chain B · Prioritization

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "How did you decide which debt to fix?" | Method | "What hurt most" | Interest, principal, risk, blocking |
| 2 | "How did you measure interest?" | Data | Opinion | Incident hours, lead time, toil |
| 3 | "What did you decide not to fix?" | Judgment | "We'll get to it all" | About 200 tickets, explicitly |
| 4 | "How did you know it worked?" | Measurement | "Felt better" | Lead time and change failure rate in the area |

### Chain C · Deliberate debt

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Why was the shortcut acceptable?" | Prudence | "We had to" | Behind the final interface; cheap to repay |
| 2 | "Who owned repayment?" | Ownership | "The team" | "I did, by name in the plan" |
| 3 | "What would have forced repayment early?" | Tripwire | Nothing | Any announced tax change |
| 4 | "How did you make sure it got repaid?" | Mechanism | "We prioritized it" | Capacity reserved when the date was agreed |

### Chain D · The freeze itself

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What was frozen, exactly?" | Scope | "Everything" | Feature releases for one service |
| 2 | "What wasn't?" | Exceptions | Unsure | Security fixes, legal deadlines |
| 3 | "How did it end?" | Exit criteria | "When things improved" | Back within SLO plus top items done |
| 4 | "What would you change about the policy?" | Reflection | Nothing | A specific improvement |

### Chain E · "Tell me about debt you created"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What's the worst tech debt you personally introduced?" | Ownership | Someone else's | Their own, specifically |
| 2 | "Which quadrant was it?" | Self-awareness | Unsure | Prudent-inadvertent, or honestly reckless |
| 3 | "What did it cost?" | Honesty | Little | A real cost |
| 4 | "What changed in how you work?" | Learning | Generic | A specific practice |

---

## 11. Checklist

- [ ] Your speed-vs-quality story ends in a mechanism, not a side.
- [ ] You can describe debt in interest, principal, risk and strategic-blocking terms.
- [ ] You can name a measurement leaders recognize (DORA metrics, incident hours, roadmap cost).
- [ ] An error-budget story where product owned the SLO and signed the policy before it triggered.
- [ ] A deliberate-debt story with an owner, a repayment date, a tripwire and reserved capacity.
- [ ] You can name debt you deliberately decided not to fix.
- [ ] You can name debt you introduced yourself.

## 12. References

- Martin Fowler, "Technical Debt Quadrant". <https://martinfowler.com/bliki/TechnicalDebtQuadrant.html>
- Google, *Site Reliability Engineering* (O'Reilly, 2016), "Embracing Risk" (error budgets). <https://sre.google/sre-book/embracing-risk/>
- Google, *The Site Reliability Workbook* (O'Reilly, 2018), "Error Budget Policy" (example policy). <https://sre.google/workbook/error-budget-policy/>
- DORA research program (the four key metrics). <https://dora.dev/>
- Nicole Forsgren, Jez Humble and Gene Kim, *Accelerate* (IT Revolution, 2018).
- In this KB: [03.2 Influencing product roadmaps](../03-Influence-Without-Authority-and-Cross-Org-Alignment/02-influencing-product-and-execs-killing-bad-projects-and-saying-no.md) · [04.2 One-way and two-way doors](02-one-way-vs-two-way-doors-deciding-with-70-percent-information.md) · Folder 05 covers what happens when reliability fails: SEV1s and COEs.
