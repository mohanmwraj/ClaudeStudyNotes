# 07.2 · Questions 11–20: Ambiguity, Vision, Failure and Missed Deadlines

> **Folder 07 · File 2 of 3.** Ten questions about judgment under uncertainty: shifting goals, setting a technical vision, starting work nobody asked for, missing a commitment, deciding with incomplete data, your biggest technical mistake, simplifying, choosing between good options, keeping a long effort alive, and acting when data contradicts belief.
>
> These questions decide **problem origin** and **self-awareness**, two of the dimensions where L6 and L7 separate most clearly (01.1 §3). As in 07.1, questions are **original formulations**, and the L7 answers are **three-minute illustrative composites**.

---

## 1. How to use this file

1. Write your own answer before reading the models.
2. For Q14 and Q16 (missed commitment, biggest mistake), check your answer against the traps in 05.1 §5: too small, someone else's, no cost, no change.
3. For Q11, Q13 and Q15, check that your answer contains the structure you created, not just the result.
4. Rehearse the probes in §4.

---

## 2. Hiring Committee Scoring Rubric (judgment and uncertainty questions)

| Signal | Strong Hire at L7 | Down-level to L5 |
|---|---|---|
| **Problem origin** | Found or defined the problem; nobody asked | The problem and its definition were handed over |
| **Structure created** | A metric, options, staged commitments and owners, for others to work within | Clarified requirements with a PM |
| **Vision** | A multi-year direction others adopted and funded; a first step that paid for itself | A good idea for one team |
| **Failure proportion** | Failures sized to L7 scope, owned in the first sentence, with cost | Small, shared, or someone else's |
| **Decision under uncertainty** | Door type named, delay priced, information bought cheaply, tripwires set | Waited for certainty, or guessed |
| **Simplification** | Removed systems, steps or concepts for many teams | Refactored own code |
| **Persistence** | Kept a long effort alive through a real setback by changing the plan, not by pushing harder | Worked longer hours |
| **Dive Deep** | Found that a trusted metric or belief was wrong, and changed what leaders watch | Debugged a hard issue |

---

## 3. Story Blueprints: the ten questions

### Q11 · "Tell me about a time you had to deliver while the goal kept changing."

*Tests:* Embracing ambiguity (Meta), creating stability for others.

#### How an L5 tells it

> "We were building a recommendations feature, and the requirements changed several times as product leadership changed their minds. I kept the team flexible by working in short sprints and re-planning often. We eventually shipped something that leadership was happy with."

#### How an L7 tells it

> "Our marketplace leadership changed the goal for seller search three times in two months: first relevance, then seller fairness, then advertising revenue. Each change triggered a re-plan, and the four teams involved had shipped almost nothing.
>
> I stopped treating the changes as noise. They were three legitimate goals that leadership hadn't ranked, because nobody had shown them the trade-off. I built a simple simulation from our search logs that showed, for any ranking weight, the effect on relevance, the share of exposure going to small sellers, and ad revenue. Then I took it to the marketplace GM and asked her to choose a point, not a goal.
>
> She chose a weighting, and, more importantly, agreed that it would only change at quarterly reviews, using the same simulation. That gave the teams a stable target. I split the work so each team owned one input to ranking, behind a shared interface, so a change in weighting needed no re-plan.
>
> We shipped the new ranking within the quarter. Small-seller exposure rose 25% with relevance unchanged and ad revenue up slightly. At the next quarterly review, she moved the weighting once, which took the teams a day of configuration rather than a re-plan."

**What separates them:** the L7 diagnoses the changing goal as an unranked trade-off, builds a tool that makes the trade-off visible, gets the leader to choose and to agree a change cadence, and designs the work so goals can move without re-planning.

### Q12 · "Describe the technical vision you set for an area. How did others come to adopt it?"

*Tests:* Think Big without the ivory tower (02.1 §4.3), adoption without mandate.

#### How an L5 tells it

> "I created a technical vision for our team's services, moving towards an event-driven architecture. I presented it to the team and we started migrating services one by one. Other teams were interested in what we were doing."

#### How an L7 tells it

> "Our logistics org had grown through three acquisitions, and every shipment crossed four systems that each held its own version of where the parcel was. Customer contacts about 'where is my order' were our largest support cost. I wrote a three-year vision: one shipment timeline, an append-only event log of everything that happened to a parcel, which every system writes to and reads from.
>
> I kept the document to four pages and made the first step small and immediately useful: a read-only timeline that merged the four systems' existing data for support agents. Two engineers built it in eight weeks. It cut average handling time on 'where is my order' contacts by 40%, which made the vision concrete for the support VP and the logistics director.
>
> Adoption came from the value, not a mandate. Each system that wrote to the log directly, instead of being merged after the fact, got near-real-time visibility for its own operations team, so the operations directors asked for it. I published a scorecard of which systems wrote directly and how fresh their data was.
>
> Two years in, three of the four systems write to the log natively, the fourth is being retired, and 'where is my order' contacts per shipment are down by half. The vision document still opens the logistics architecture review, revised once a year by the team that owns the log."

**What separates them:** the L7's vision starts from a business cost, is short, has a first step that pays off in weeks for a named executive, spreads by value and a visible scorecard, and is maintained by others.

### Q13 · "Tell me about a project you started that nobody asked you to."

*Tests:* Problem origin, Ownership, sizing and getting attention (04.1).

#### How an L5 tells it

> "I noticed our test suite was slow and flaky, so in my spare time I built a tool to detect flaky tests. I showed it to the team and we started using it. It made our builds more reliable."

#### How an L7 tells it

> "While reviewing our cloud contracts for an unrelated reason, I noticed that our main managed database's version would reach end of support in fourteen months, and the upgrade path required a change in replication mode that our failover tooling didn't support. Eleven teams' services sat on that database. No team owned the question, because each assumed the platform team did, and the platform team's roadmap was full.
>
> I sized it: if we missed the date, we'd either pay extended-support fees of about $X K a month or run unsupported, which our security policy didn't allow for anything handling customer data. I estimated the work at two quarters, which left about two quarters of buffer.
>
> I took a one-page note to the infrastructure director with a proposal: I would lead it, with one engineer from the platform team and an engineer from each of the two largest consuming teams. I built the failover-tooling change myself, since that was the riskiest piece. We upgraded the eleven teams' databases by cohort, smallest first, each with a tested rollback.
>
> We finished four months before end of support, with no extended-support fees and no customer-facing failover incidents. I also added an end-of-life calendar for every managed dependency to the platform team's quarterly review, which has since caught two more."

**What separates them:** the L7's unasked project is at org scope, found through a deliberate habit, sized in money and policy terms, taken to the right owner with a staffed plan, executed with the riskiest piece personally owned, and turned into a recurring mechanism.

### Q14 · "Tell me about a time you missed a commitment."

*Tests:* Ownership, estimation judgment, communicating bad news early.

#### How an L5 tells it

> "We committed to delivering a new API by the end of the quarter, but it slipped by three weeks because of unexpected complexity in integrating with a legacy system. We communicated the delay and delivered it soon after. I learned to add more buffer to estimates."

#### How an L7 tells it

> "I committed to my VP that our new payments-routing service would carry 50% of card traffic by the end of the year, in time for the holiday peak. We reached 20%, and the remaining 30% moved in February, after the peak. The cost was real: the old router's higher processing fees on that traffic, about $X K over the peak, and the VP had told the CFO the saving would land in the year.
>
> The cause was my estimate. I'd planned the migration by traffic volume, but the hard part turned out to be the long tail of merchant-specific routing rules: about 400 of them, each needing verification with the merchant's acquirer. I'd sampled ten rules when I estimated, and those ten happened to be simple.
>
> I knew by October that we'd miss. I told the VP that week, not in December, with three options: rush the remaining rules and accept the risk of misrouted payments during peak, migrate the simple rules and hold the complex ones, or freeze at 20% through peak. I recommended the second; she chose the third, to protect the peak, which in hindsight was right.
>
> Since then, when I estimate a migration, I sample the long tail deliberately, not randomly, and I publish the estimate with a range and the assumption that drives it. My next two migration estimates landed within 10%."

**What separates them:** the L7 commitment is at business scope, the cost is quantified including the leader's credibility, the cause is owned as their own estimation error with its mechanism, bad news went up early with options, and the change in method has evidence.

### Q15 · "Tell me about a decision you made with very incomplete data."

*Tests:* One-way vs two-way doors and the 70% rule (04.2).

#### How an L5 tells it

> "We had to choose a message queue for a new service without much time to evaluate. I picked the one our team knew best, because we didn't have time for a full comparison. It worked fine."

#### How an L7 tells it

> "During a supplier crisis, our procurement team needed a way to reallocate inventory between warehouses daily, rather than monthly, within three weeks. We had no demand forecast at warehouse level, and building one properly would take a quarter.
>
> I classified the decision first. The reallocation *algorithm* was a two-way door: we could change it daily. Physically moving stock was not, because every move cost money. So I designed for that asymmetry: a simple heuristic based on the previous two weeks' sales by warehouse, which we could improve continuously, and a cap so that no more than 10% of a warehouse's stock could be moved in a day, which limited the damage of a bad recommendation.
>
> I also set a tripwire with the procurement director: if the rate of stock moved and then moved back exceeded 5% in any week, the system would stop recommending until we reviewed it. We launched in sixteen days.
>
> Stockouts on the constrained items fell by about half during the crisis. The tripwire fired once, in week four, when a regional promotion distorted sales, and we added promotions as an input. The forecast model that came later used our heuristic as its baseline, and beat it by only 12%, which told us the quick version had been worth it."

**What separates them:** the L7 separates the reversible part (the algorithm) from the irreversible part (physical moves), caps the irreversible part, sets a tripwire with the business owner, moves fast, and validates the decision afterwards.

### Q16 · "What's the biggest technical mistake you've made?"

*Tests:* Proportion, ownership, reasoning at the time (05.1).

#### How an L5 tells it

> "I once deployed a change without enough testing, and it caused errors for some users for about an hour. I rolled it back and added more tests. Now I'm much more careful about testing before deploying."

#### How an L7 tells it

> "The biggest technical mistake I've made was the data model for our multi-tenant SaaS product: I chose a shared schema with a tenant ID column for all customers. At the time it was reasonable: we had 200 small customers, and per-tenant databases would have multiplied our operational work.
>
> What I didn't anticipate was enterprise customers. Within two years, our five largest customers were a third of revenue, and two of them required data isolation and per-tenant encryption keys in their contracts. Retrofitting isolation onto a shared schema took two engineers most of a year, and one large deal slipped by a quarter while we did it.
>
> I owned it in the planning review: the model was my design, and the cost was about a year of two engineers plus the delayed deal. I led the retrofit: a hybrid where large tenants get dedicated schemas with their own keys, and small tenants stay shared, with the routing layer deciding per tenant.
>
> The lesson I took isn't 'always isolate tenants', which would have been wrong for us at the start. It's that I now write down, for any foundational data model, which business change would make it wrong, and put that signal in front of leadership. For our next product, that signal was 'first contract requiring isolation', and the design had a migration path ready before it arrived."

**What separates them:** the L7 mistake is foundational and costly, the reasoning at the time is explained, the cost is quantified, ownership is public, the candidate led the repair, and the lesson is a precise practice rather than an over-correction.

### Q17 · "Describe a time you simplified something others had made complex."

*Tests:* Invent and Simplify, Respect What Came Before (02.1 §1.2).

#### How an L5 tells it

> "Our configuration system had grown really complicated, with lots of overlapping settings. I refactored it to remove unused options and made the documentation clearer. It was much easier to use afterwards."

#### How an L7 tells it

> "Our feature-flag system had grown to about 9,000 flags across 70 services, with three ways to evaluate a flag, and nobody could say which flags were still in use. Incidents caused by flag interactions had happened four times in a year.
>
> Before proposing anything, I talked to the engineers who'd built the three evaluation modes. Each mode had been added for a real reason: one for mobile clients that couldn't call the service, one for batch jobs, one for server latency. Any simplification had to keep those needs.
>
> I proposed one evaluation model, with a local cached copy of flag rules for all three clients, which met all three needs. I also gave every flag a lifecycle: a type (release, experiment or permanent), an owner, and an expiry for release flags. A weekly job opened a pull request to delete any expired release flag whose value had been constant for 30 days.
>
> Within two quarters, the flag count fell from 9,000 to about 2,500, the three evaluation modes became one, and flag-interaction incidents dropped to zero for the next year. The original authors of two of the modes reviewed the design, and one of them owns the system now."

**What separates them:** the L7 simplifies across 70 services, first understands why the complexity exists, keeps the legitimate needs, adds a lifecycle so it doesn't regrow, and involves the original authors.

### Q18 · "Tell me about a time you had to choose between two good opportunities."

*Tests:* Prioritization, opportunity cost, saying no to good work.

#### How an L5 tells it

> "I was asked to lead two projects at once: a new search feature and a performance improvement. I couldn't do both well, so I talked to my manager and we decided I'd focus on the search feature. The performance work was given to someone else."

#### How an L7 tells it

> "In the same month, two directors asked me to lead their initiatives: a new real-time pricing platform, high-profile and well funded, and a less visible effort to fix our order-data pipeline, whose errors were forcing finance to restate weekly revenue reports.
>
> The pricing platform was the career-visible choice. I compared them on what each would cost the business if it went badly without me. The pricing platform had a strong team and a clear design; it would be somewhat slower without me. The order-data problem had no owner, an unclear cause, and finance had flagged it as a risk in the audit planning.
>
> I chose the order-data pipeline, and told the pricing director why, offering to review the pricing design at two milestones and recommending a staff engineer for the lead role, whom I'd worked with. He accepted both.
>
> The pipeline problem turned out to be late-arriving cancellations being counted in the wrong week. Fixing it, plus a reconciliation control, ended the weekly restatements within six weeks, and the auditors closed the risk item. The pricing platform shipped on time under the engineer I'd recommended, and that project was central to her promotion case."

**What separates them:** the L7 chooses by counterfactual business risk rather than visibility, takes the less glamorous problem, explains the choice to the director they turned down, sponsors someone else into the other role, and reports both outcomes.

### Q19 · "Tell me about a long-running effort that nearly failed partway through. How did you keep it alive?"

*Tests:* Deliver Results through setbacks, changing the plan rather than pushing harder.

#### How an L5 tells it

> "Our migration project was falling behind and the team was getting demotivated. I worked extra hours, organized some team-building, and kept everyone focused on the goal. We got it done eventually."

#### How an L7 tells it

> "Eight months into a two-year program to move our analytics from an on-premises Hadoop cluster to a cloud warehouse, we were in trouble. We'd migrated 20% of the jobs, the remaining 80% looked harder, the cluster's hardware support contract was ending, and the VP was asking whether we should stop and renew.
>
> I looked at why. We'd been migrating job by job, in priority order, and every job had different dependencies, so each one was a project. I changed the unit of work: instead of jobs, we'd migrate *datasets*, starting with the twenty most-shared ones, which half of all remaining jobs depended on. Once those were in the warehouse, most dependent jobs could move with little work.
>
> I took the revised plan to the VP with the honest picture: the original timeline wasn't achievable, the revised one finished four months late, and renewing hardware support for one year would cost $X K, against the cost of stopping. She approved the revised plan and the one-year support extension.
>
> The dataset-first approach roughly tripled our migration rate. We finished within the revised plan, retired the cluster two months before the extended support ended, and the dataset-dependency graph we built became the org's data catalog."

**What separates them:** the L7 diagnoses why the effort is failing, changes the unit of work rather than the effort level, resets expectations honestly with a costed option, and leaves a durable asset.

### Q20 · "Tell me about a time the data told you something different from what people believed."

*Tests:* Dive Deep: "skeptical when metrics and anecdote differ".

#### How an L5 tells it

> "Everyone thought our app was slow because of the backend, but when I looked at the traces, most of the time was spent on the client rendering images. I optimized the image loading, and the app got faster."

#### How an L7 tells it

> "Our customer-support org believed that most refund requests came from late deliveries, and a large program was being planned to speed up delivery in our slowest regions. The dashboard everyone used agreed: 'late delivery' was the top refund reason.
>
> When I sampled 300 refund tickets and read them, the story was different. The refund reason was a dropdown that agents selected, and 'late delivery' was the first option. In about half the tickets labeled 'late', the customer's actual complaint was a damaged or wrong item. The dashboard was measuring which option was first in a list.
>
> I took the sample to the support VP and the logistics director before the program was funded, showing the tickets themselves, not just my summary. They agreed to a two-week test: the reason field was redesigned so agents had to choose from a category tree, with no default, and we classified a fresh sample.
>
> With better data, late delivery fell to the third most common reason, behind damaged items and wrong items. The delivery-speed program was reduced to two regions, and the savings funded a packaging and picking-accuracy effort instead, which cut refunds by about 20% in two quarters. The dashboard now shows the share of tickets with an unclassified reason, so we notice if the data degrades again."

**What separates them:** the L7 questions an org-level belief that a major program depends on, reads raw data rather than the dashboard, finds a measurement artifact, brings evidence leaders can see, redirects funding, and adds a data-quality signal.

---

## 4. Bar-Raiser Follow-Up Chains

| Q | Probe | Tests | Owner's answer shape |
|---|---|---|---|
| **11** | "Why hadn't leadership ranked the goals?" | Insight | Nobody had shown them the trade-off |
| | "What did the simulation not capture?" | Honesty | A real limitation |
| | "How often can the weighting change?" | Mechanism | Quarterly, using the same simulation |
| **12** | "What was the first step, and who benefited?" | Ivory-tower test | The read-only timeline; the support VP |
| | "Who resisted?" | Influence | A named system owner and their reason |
| | "Who owns the vision now?" | Leverage | The log's owning team |
| **13** | "How did you find it?" | Technique | Reading contracts; an end-of-life habit |
| | "Why you, not the platform team?" | Ownership | Nobody owned it; a staffed proposal |
| | "What's the mechanism now?" | Durability | The end-of-life calendar |
| **14** | "When did you know you'd miss?" | Early warning | October, told that week |
| | "What did your VP choose, and was she right?" | Humility | The freeze, and yes |
| | "How do you estimate now?" | Learning | Deliberate long-tail sampling; ranges |
| **15** | "Which part was irreversible?" | Door classification | Physical stock moves |
| | "Who agreed the tripwire?" | Alignment | The procurement director |
| | "Was the quick version worth it?" | Validation | The later model beat it by only 12% |
| **16** | "Why did the shared schema seem right then?" | Reasoning | 200 small customers; operational load |
| | "What did it cost?" | Accountability | A year of two engineers; a delayed deal |
| | "Would you isolate tenants from the start next time?" | Over-correction test | No; write down the business signal that would make it wrong |
| **17** | "Why did the three modes exist?" | Respect what came before | Each one's real reason |
| | "What stops it regrowing?" | Mechanism | The lifecycle and automatic deletion |
| | "Who owns it now?" | Leverage | One of the original authors |
| **18** | "Why not the visible project?" | Values | Counterfactual business risk |
| | "What did you tell the other director?" | Candor | The reasoning, plus reviews and a recommended lead |
| | "What happened to the other project?" | Sponsorship | Shipped under the recommended engineer |
| **19** | "Why was it failing?" | Diagnosis | Job-by-job unit of work |
| | "What did you tell the VP?" | Honesty | The original plan wasn't achievable; costed options |
| | "What would have happened if you'd just pushed harder?" | Judgment | The same rate, a missed contract end |
| **20** | "Why didn't you trust the dashboard?" | Dive Deep | Reading tickets contradicted it |
| | "How did you persuade leaders?" | Evidence | The tickets themselves |
| | "How will you know if it degrades again?" | Mechanism | Unclassified-reason share on the dashboard |

---

## 5. Checklist

- [ ] Q11, Q13, Q15: your answer includes the structure you created for others.
- [ ] Q12: your vision has a first step that paid off within weeks for a named leader.
- [ ] Q14, Q16: owned in the first sentence, cost quantified, the cause is yours, the change has evidence.
- [ ] Q17: you can say why the complexity existed before you removed it.
- [ ] Q18: you chose on business risk, and can say what happened to the option you didn't take.
- [ ] Q19: you changed the plan, not just the effort.
- [ ] Q20: you read raw data, and changed what leaders watch.

## 6. References

- In this KB: [04.1 Existential problems](../04-Ambiguity-Technical-Vision-and-Calculated-Risk/01-identifying-unasked-existential-problems-and-writing-6-page-rfcs.md) · [04.2 One-way and two-way doors](../04-Ambiguity-Technical-Vision-and-Calculated-Risk/02-one-way-vs-two-way-doors-deciding-with-70-percent-information.md) · [05.1 Owning failures](../05-Production-Outages-Mistakes-and-Psychological-Safety/01-owning-catastrophic-sev1-outages-and-bad-architectural-bets.md) · [07.1 Questions 1–10](01-questions-01-to-10-conflict-pushback-and-disagree-and-commit.md) · [07.3 Questions 21–30](03-questions-21-to-30-mentorship-hiring-org-design-and-ethics.md)
