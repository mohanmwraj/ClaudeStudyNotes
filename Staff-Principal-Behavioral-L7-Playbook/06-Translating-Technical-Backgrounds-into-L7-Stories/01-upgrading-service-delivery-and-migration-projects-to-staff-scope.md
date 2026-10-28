# 06.1 · Upgrading Service-Delivery and Migration Projects to Staff Scope

> **Folder 06 · File 1 of 3.** Many engineers have done Staff-scope work they've never described as Staff-scope work. It's buried inside projects with modest names: "the cloud migration", "the client integration", "the payments upgrade", "the bug in the pricing job". They tell those projects as task lists, because that's how they were planned and tracked, and the committee hears L5.
>
> This folder is about **finding and telling the real scope of work you've already done**, honestly. Not inflating it: finding it. This file covers:
> - the story-mining interview: twelve questions that excavate scope from an ordinary project;
> - the line between an honest upgrade and inflation;
> - telling a legacy-to-cloud migration through three lenses: strangler-fig risk mitigation, zero-downtime cutover, and multi-stakeholder alignment;
> - service delivery and consulting: influence across company boundaries;
> - telling a production bug as a COE, blast-radius and guardrail story;
> - a rubric, three story blueprints and five follow-up chains.
>
> Stories are **illustrative composites**.

---

## 1. The story-mining interview

Pick a project you think of as "just delivery". Answer these twelve questions in writing, honestly. Most people find at least two or three L6/L7 signals they'd never mentioned.

| # | Question | Scope dimension it uncovers (01.1 §3) |
|---|---|---|
| 1 | What was the business reason for this project, and what was at stake if it failed? | Impact unit |
| 2 | Who outside your team was affected by it? Name the teams, functions and companies. | Blast radius |
| 3 | What did you notice that wasn't in the plan or the spec? | Problem origin |
| 4 | What did you decide that someone else would normally have decided? | Influence |
| 5 | Who disagreed with you, about what, and how was it resolved? | Influence mechanism |
| 6 | What alternatives did you consider, and why did you reject them? | Decision quality |
| 7 | What was the riskiest moment, and what did you do about it beforehand? | Execution under risk |
| 8 | What would have happened if you hadn't been on the project? | Counterfactual ownership |
| 9 | What did you build or establish that other people used afterwards? | Leverage |
| 10 | Who did you teach or grow, and what do they do now? | People leverage |
| 11 | How long did the effects last? Are they still there? | Time horizon |
| 12 | What number would the business care about? | Business translation |

If you can't answer question 1, ask someone who was there. If the honest answer to question 8 is "nothing much would have changed", the project isn't your flagship story, and that's fine.

---

## 2. Honest upgrade vs inflation

The goal is to tell the work at its **true** size. The line:

| Honest upgrade (reframing what was true) | Inflation (claiming what wasn't) |
|---|---|
| "The migration retired $X M of licence and hardware cost" (it did; you just never said it) | Quoting a company-wide saving your project contributed a fraction of |
| "I sequenced the cutover to protect the store-opening window" (you did) | "I led the migration" when you led one workstream |
| "The business owner wanted a big-bang cutover; I argued for incremental routing, and she agreed" | Claiming a decision that your manager or architect made |
| "The reconciliation tool I built became the standard for the next three migrations" | Implying reuse that didn't happen |
| "I wasn't the lead; my part was the data migration, which was the highest-risk piece" | Hiding your actual role in "we" so it sounds bigger |

**Test:** if the person who led the project heard your story, would they agree with every sentence? If not, rewrite it until they would. The bar-raiser probes in 01.1 §8 are built to find the sentences they wouldn't.

---

## 3. A legacy-to-cloud migration through three lenses

A migration is one of the richest L7 stories available, if it's told as **risk, cutover and alignment** rather than as "we moved the app to the cloud". Pick the lens that matches the strongest part of your real contribution, and use the others as supporting detail.

### 3.1 Lens 1: strangler-fig risk mitigation

Martin Fowler's strangler fig pattern replaces a legacy system incrementally: a routing layer sends some traffic to new components, and the legacy system is retired piece by piece. As a story, the point isn't the pattern; it's that **each step retired a quantifiable risk**.

| What to say | Example |
|---|---|
| The risk of the alternative | "A big-bang cutover risked a full outage of order capture, about $X M a day" |
| The routing seam | "I put a facade in front of the order APIs, so we could route by endpoint and by store" |
| The order of extraction | "We extracted read-only endpoints first, then low-volume writes, then the core order flow" |
| Risk retired per step | "Each step moved a slice of traffic with a one-command rollback" |
| When the legacy system died | "The last module was retired in month 14, and the mainframe contract ended" |

### 3.2 Lens 2: zero-downtime cutover

The technical zoom-in, and usually the strongest **depth** signal:

| Element | What it shows |
|---|---|
| **Change data capture or dual write** | How data stayed in sync during the transition |
| **Shadow reads** and comparison | How you proved the new system was correct before it served |
| **Reconciliation** | How you found and repaired divergence |
| **Canary by cohort** (one store, one region, one customer segment) | How you limited the blast radius of each step |
| **Rollback** | How fast, and whether it was tested |
| **Cutover window choice** | What business calendar you planned around |

### 3.3 Lens 3: multi-stakeholder alignment

Enterprise migrations involve more stakeholders than most FAANG projects: business owners, operations, security, compliance, audit, vendors, outsourced teams, sometimes unions or regulators. That's a strength in an L7 story, if you show **how you aligned them**:

| Stakeholder | What they cared about | How you addressed it |
|---|---|---|
| Business owner | No disruption to trading periods | Cutover calendar around peak seasons |
| Operations | Runbooks, on-call and monitoring | Operational readiness review before each step |
| Security | Network boundaries, identity, encryption | Threat model and sign-off per phase |
| Compliance and audit | Data lineage, retention, change records | Reconciliation reports as audit evidence |
| Vendors | Contract terms, support windows | Exit dates negotiated around the plan |
| Downstream teams | Their integrations | Compatibility contracts and migration windows |

---

## 4. Service delivery and consulting: influence across company boundaries

If your experience is in consulting, outsourcing or a services company, your stories have a feature FAANG candidates rarely have: **influence across a company boundary**, often harder than influence inside one. A client's VP has no reason to take an external engineer's advice, and a statement of work constrains what you can change.

| Service-delivery fact | How to tell it at L6/L7 |
|---|---|
| "The client asked for X" | "The client asked for X; I found the business goal behind it was Y, and X wouldn't reach it" |
| "We delivered to the SOW" | "I proposed a change to the SOW that cost us nothing and saved the client a quarter" |
| "We worked with the client's architects" | "The client's lead architect and I disagreed on Z; here's how it was resolved" |
| "Multiple vendors were involved" | "Three vendors owned parts of the flow; I set up the integration contract they all built against" |
| "We handed over to the client" | "I built the client team's capability to own it; they've since extended it without us" |

The interviewer's likely probe is "who had the authority?" (Chain A). In a services context the honest answer is often "the client did", which makes your influence more impressive, not less, provided you can say exactly what you changed.

---

## 5. A production bug, told as a COE, blast-radius and guardrail story

A bug story is L4–L5 scope if it ends at the fix. It reaches L6/L7 when it's told as the start of a systemic change (05.2):

| L5 shape | L7 shape |
|---|---|
| Found the bug | Found the bug, *and* the property of the system that let it reach customers |
| Fixed it | Fixed it, contained its blast radius during the incident, and repaired the data |
| Added a test | Added a guardrail at the platform level that prevents the class of bug for every team |
| "We were more careful after that" | "The guardrail has since caught N similar changes in other teams" |

The three upgrades: **the class, not the instance; the blast radius, not just the cause; the org, not just the team.**

---

## 6. Hiring Committee Scoring Rubric

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | Credibility concern |
|---|---|---|---|---|
| **Framing** | Told as risk retired, business protected and capability built; the role is stated precisely | Told as a cross-team delivery with trade-offs | Told as a task list | Scope claimed that probes don't support |
| **Migration lens** | Strangler-fig risk sequencing, zero-downtime cutover depth and stakeholder alignment, each with specifics | Two of the three | Technical steps only | Can't explain the cutover |
| **Cross-boundary influence** | Changed a client's or vendor's decision; built their capability | Worked effectively with clients and vendors | Followed the SOW | Blames the client |
| **Bug-to-guardrail** | Class of bug prevented org-wide, with evidence | Fixed with a regression test and area-wide check | Fixed the instance | Someone else's bug |
| **Business translation** | Cost retired, revenue protected or risk removed, quantified | Org technical metric | Delivery dates | No outcome |
| **Honesty** | Role, credit and numbers survive every probe | Mostly precise | Vague | Inflated |

---

## 7. Story Blueprints

### 7.1 A legacy-to-cloud migration (composite: an on-premises order system for a retailer)

**The facts (composite):**
- A retailer's order-capture system runs on-premises on a commercial database, with a hardware lease and database licence renewal 18 months out.
- It serves e-commerce and 1,200 stores.
- The candidate was the technical lead for the data and cutover workstream, one of three workstreams.

#### How an L5 tells it

> "I worked on migrating our order system from on-prem to the cloud. We re-platformed the services onto Kubernetes, migrated the database to a managed cloud database, and set up CI/CD. I was responsible for the data migration part. We did it over about a year and it went well, with only a couple of minor issues during cutover."

**What the committee extracts:** a technical task list; a workstream role; no business stakes, no risk management, no alignment. **L5.**

#### How an L7 tells it

> "Our order-capture system for e-commerce and 1,200 stores ran on-premises, and the hardware lease and database licence both renewed in 18 months, at about $X M over the next term. If the migration missed that date, we'd pay for both. If it caused an outage, stores couldn't take orders. I was technical lead for the data and cutover workstream, which was the highest-risk of the three.
>
> The original plan was a big-bang cutover over a long weekend. I argued against it, because a failed cutover meant rolling back a database that had already taken new orders. I proposed a strangler approach instead: a facade in front of the order APIs that could route by endpoint and by store, so we'd move traffic in slices. The program director's concern was the timeline: incremental is slower. I showed her that the slices could run in parallel with the other workstreams, and that the critical path was the data sync either way. She agreed.
>
> The zero-downtime part was mine. Change data capture kept the cloud database in sync with the legacy one. Shadow reads compared results for every order lookup for two weeks before any write moved. And I built a nightly reconciliation that compared orders, line items and payment states, and reported any divergence. That reconciliation found a time-zone defect in how the old database stored store-local timestamps, which would have mis-dated about 3% of store orders after cutover.
>
> We cut over by cohort: ten pilot stores first, then by region, avoiding the trading calendar's peak weeks. The business owner, operations, security and the audit team each signed off per phase, and the reconciliation reports became the audit evidence that no orders were lost. Every cohort had a rollback that we tested before it moved.
>
> We finished two months before the renewal date, with no order-capture outage, so the lease and licence weren't renewed. The reconciliation tool and the cohort playbook were reused for the next two migrations, inventory and pricing, and an engineer I'd paired with on the reconciler led the inventory one."

**What the committee extracts:** the business stake and deadline; precise role; argued and won the strangler approach against a big-bang plan, answering a real concern; zero-downtime depth; reconciliation found a real defect; cohort cutover around the business calendar; multi-stakeholder sign-off, with audit evidence; outcome in money and risk; reuse and a grown owner. **L7, told honestly from a workstream-lead role.**

### 7.2 A service-delivery project (composite: an external team building a client's integration)

**The facts (composite):** the candidate works for a services company, leading a six-person team building an inventory-feed integration between a retail client and its marketplace partners. The client specified a nightly batch file.

#### How an L5 tells it

> "I led a team at a consulting company building an inventory integration for a retail client. The client wanted a nightly batch file to their marketplace partners. We built it to spec using their file format, tested it with two partners, and delivered on time. The client was happy with the delivery."

**What the committee extracts:** delivered to spec; no discovery, no influence. **L5.**

#### How an L7 tells it

> "I led a six-person team at a services company, building an inventory feed from a retail client to its marketplace partners. The client's spec was a nightly batch file. In discovery, I asked the client's e-commerce director what the integration was for, and the real goal was reducing overselling on marketplaces, which was costing them penalty fees and seller-rating drops. A nightly file couldn't fix that: most oversells happened on fast-moving items whose stock changed several times a day.
>
> That put me in an awkward position. We were contracted for the batch file, and the client's lead architect had designed it. I didn't go around him. I showed him the data first: from their own order history, 80% of oversells were on about 5% of items, all of which sold out within hours. I proposed keeping the nightly file for the full catalogue and adding an event-driven delta feed for the fast-moving 5%, within the same budget, by dropping two low-value reporting features from the scope.
>
> He agreed, on one condition I thought was right: the delta feed had to degrade to the nightly file if it failed, so partners never saw stale data presented as current. We changed the statement of work together, and he presented it to the director as his architecture, which it mostly was.
>
> Marketplace oversells fell by about 70% in the first quarter after launch, and penalty fees dropped accordingly. I also built the client team's ability to run it: their engineers owned the delta-feed service by the end of the engagement, and they've since extended it to two more partners without us."

**What the committee extracts:** found the business goal behind the request; recognized the specification wouldn't reach it; influenced across a company boundary without going around the client's architect; changed the SOW at no extra cost; accepted a valid condition; gave credit; measured business outcome; built the client's capability. **L7 cross-boundary influence.**

### 7.3 A production bug, told as a COE and guardrail story (composite: a pricing job's time-zone defect)

**The facts (composite):** a nightly pricing job applied next-day promotional prices six hours early in 40 stores in one time zone, so stores charged sale prices before the promotion started.

#### How an L5 tells it

> "There was a bug in our pricing batch job where promotions started early in some stores because of a time-zone issue. I found the bug, fixed the time-zone conversion, and added unit tests for the different time zones. After that, the problem didn't happen again."

**What the committee extracts:** found and fixed the instance. **L5.**

#### How an L7 tells it

> "Our nightly pricing job applied the next day's promotional prices six hours early in 40 stores in one time zone, so those stores sold at sale prices before the promotion started. It ran for one night before a store manager noticed, and it cost about $X K in margin.
>
> The immediate fix was mine: during the incident, I stopped the job from publishing to the affected time zone, which limited the blast radius to the 40 stores already affected, and corrected their prices manually before opening. The defect was a conversion that assumed the server's time zone.
>
> But the more important question in the COE was why a time-zone assumption could reach stores at all. When I checked, seven other batch jobs that published to stores had the same pattern, because they'd all been written from the same template. Two of them had produced smaller incidents the previous year that nobody had connected.
>
> So the fix went into the platform rather than the job. I changed the shared scheduling library so that any job publishing to stores receives each store's local effective time from the store registry, and the old API that took a bare timestamp was deprecated with a build warning. I also added a pre-publish check that compares the effective times of a price batch against each store's local calendar and blocks publication if any store would receive a change outside its intended window.
>
> All seven jobs were migrated within a month. The pre-publish check has since blocked four bad batches from other teams, including one from the promotions team two weeks before a major holiday sale."

**What the committee extracts:** contained blast radius during the incident; asked the class question; found the same hazard across seven jobs and two unconnected incidents; fixed it at the platform level with an engineered guardrail; evidence that it protected other teams. **L7 bug-to-guardrail story.**

---

## 8. Adversarial Bar-Raiser Follow-Up Chains

### Chain A · "What was your actual role?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Who led the overall migration?" | Precision | "I did" (if untrue) | "The program director; I led the data and cutover workstream" |
| 2 | "Who decided on the strangler approach?" | Decision rights | "We did" | "I proposed it; the director decided after I answered her timeline concern" |
| 3 | "What did the other workstreams do?" | Context | Unsure | A clear description |
| 4 | "Who had authority on the client side?" | Cross-boundary honesty | "We did" | "The client's architect and director. I influenced; they decided" |

### Chain B · The cutover

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "How did data stay in sync?" | Depth | "We migrated it" | Change data capture, with the lag and failure behaviour |
| 2 | "How did you know the new system was correct?" | Verification | "Testing" | Shadow reads and reconciliation |
| 3 | "What did reconciliation find?" | Reality | Nothing | The time-zone defect, 3% of store orders |
| 4 | "What was your rollback, and was it tested?" | Reversibility | "We had a plan" | Tested per cohort |
| 5 | "Why that order of cohorts?" | Risk sequencing | "Convenience" | Pilot stores, then regions, around the trading calendar |

### Chain C · Business stakes

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Why did this migration matter to the business?" | Translation | "Modernization" | The lease and licence renewal; store order capture |
| 2 | "What did it save or protect?" | Quantification | Unsure | The renewal cost avoided; no outage |
| 3 | "What would a failed cutover have cost?" | Risk | Unsure | A day of store orders |

### Chain D · The bug's class

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Why could that bug reach stores?" | Systems thinking | "Missing test" | The template pattern and the API that took a bare timestamp |
| 2 | "Where else did the pattern exist?" | Propagation | Didn't check | Seven jobs; two prior incidents |
| 3 | "What stops a new job doing the same?" | Guardrail | "Code review" | The library change and the pre-publish check |
| 4 | "Has it caught anything?" | Evidence | Unknown | Four batches, one before a holiday sale |

### Chain E · Honesty about scope

| # | Probe | Tests | Weak | Strong |
|---|---|---|---|---|
| 1 | "Would the project lead tell this the same way?" | Credibility | Hesitates | "Yes, and here's what she'd add" |
| 2 | "What part of the success wasn't yours?" | Credit | Little | Specific credit to others |
| 3 | "What's the biggest thing you'd do differently?" | Reflection | Nothing | A real change |

---

## 9. Checklist

- [ ] Run the twelve-question story-mining interview on your three biggest "delivery" projects.
- [ ] For each, write the business stake (question 1) and the counterfactual (question 8).
- [ ] Pass the project-lead test: would they agree with every sentence?
- [ ] For a migration: risk retired per step, the zero-downtime mechanics, and the stakeholders you aligned.
- [ ] For service delivery: what you changed across the company boundary, and what the client can now do without you.
- [ ] For a bug: the class, the blast radius, the guardrail, and evidence it protected others.

## 10. References

- Martin Fowler, "Strangler Fig Application". <https://martinfowler.com/bliki/StranglerFigApplication.html>
- Martin Kleppmann, *Designing Data-Intensive Applications* (O'Reilly, 2017): change data capture and derived data, the depth behind §3.2.
- In this KB: [01.1 The seven scope dimensions](../01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md) · [03.3 Migrations without mandates](../03-Influence-Without-Authority-and-Cross-Org-Alignment/03-driving-multi-team-migrations-and-adoption-without-mandates.md) · [05.2 COEs and guardrails](../05-Production-Outages-Mistakes-and-Psychological-Safety/02-coe-blameless-postmortems-and-systemic-org-wide-guardrails.md) · [06.2 Performance, FinOps and platform stories](02-framing-performance-tuning-cost-finops-and-platform-tooling-stories.md) · [06.3 The "not FAANG scale" objection](03-handling-the-lack-of-faang-scale-objection-with-complexity-depth.md)
- Technical depth: the CDC and streaming material in the [Unified Dataflow/Beam/Flink L7 Reference](../../Unified-Dataflow-Beam-Flink-L7-Reference/), and cutover patterns in the [Distributed Systems Design L7 Reference](../../Distributed-Systems-Design-L7-Reference/).
