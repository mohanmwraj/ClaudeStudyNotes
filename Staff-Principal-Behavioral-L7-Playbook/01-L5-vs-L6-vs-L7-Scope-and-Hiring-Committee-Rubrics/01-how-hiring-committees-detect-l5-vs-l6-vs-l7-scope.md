# 01.1 · How Hiring Committees Detect L5 vs L6 vs L7 Scope

> **Folder 01 · File 1 of 3.** A behavioral loop doesn't measure how good you are. It measures how much **level-specific evidence your interviewers can write down**. The committee or debrief never sees you; it reads the writeups. A brilliant engineer who tells L5-shaped stories produces an L5 packet, and gets an L5 offer or none.
>
> This file explains how that evidence is produced and judged:
> - the level map across companies;
> - who decides, and from what;
> - the seven dimensions scope is measured on;
> - the exact language shift between L4 and L7;
> - the probes interviewers use to separate owners from passengers;
> - a scoring rubric, the same project told at three levels, and five adversarial follow-up chains.
>
> ⚠ marks company-internal mechanics that are described publicly only in part, or reported by practitioners. Verify the specifics for your loop with your recruiter. Example stories are **illustrative composites**: the structure is the lesson, and the numbers are placeholders for your own.

---

## 1. First, which level are we talking about?

"L7" is not one thing. Titles and numbers differ by company, so calibrate by **scope**, not by number.

| This KB's scope label | What the scope looks like | Amazon | Google | Meta |
|---|---|---|---|---|
| **L5 · Senior** | Owns a complex service, pipeline or project for one team; mentors; delivers reliably | L5 SDE II (upper) / L6 Senior SDE | L5 Senior | E5 Senior |
| **L6 · Staff** | Technical leadership across several teams; finds cross-team problems; leads via RFCs and consensus | L6 Senior SDE (upper) / L7 | L6 Staff | E6 Staff |
| **L7 · Principal / Senior Staff** | Technical direction for an org or business line; reframes strategy; changes roadmaps; grows owners | L7 Principal SDE | L7 Senior Staff (L8 Principal) | E7 Senior Staff (E8 Principal) |

⚠ Cross-company equivalences are approximate and argued about constantly. Two facts matter for preparation:
1. **Amazon's L7 Principal is a very high bar.** It is an org-spanning technical leader, closer in scope to Google/Meta Senior Staff or Principal than to Staff.
2. **Ask the recruiter which level the loop is calibrated for** and what scope that level is expected to show. You can't hit a target you haven't been told.

This KB uses the scope labels in the first column throughout.

## 2. How the decision is actually made

### 2.1 The only artifact is the writeup

Every major company trains interviewers to record **behaviors and evidence**: what you said you did, the decision, the numbers, the counterpart. They are trained not to record impressions. "Seemed very senior" is worthless in a debrief; "identified that the batch pipeline would miss the 15-minute pricing SLA once marketplace volume arrived, and wrote the proposal that moved Q3 roadmap capacity to fix it" is evidence.

So your job in every answer is to **give the interviewer quotable sentences at your target level**:
- the problem you framed;
- the alternatives you weighed;
- the person who disagreed and what changed their mind;
- the decision you made;
- the number, with its baseline.

### 2.2 Who reads it

**Amazon** (publicly described):
- Each interviewer is assigned Leadership Principles to probe, and writes feedback with a vote **before** the debrief.
- A **Bar Raiser** sits in the loop. They are a trained interviewer from outside the hiring team, accountable for the long-term hiring bar. They run the debrief, push for evidence over opinion, and are widely described as able to block a hire ⚠.
- Hire/no-hire *and level* are argued in the debrief, from the written evidence.

**Google** (publicly described):
- Interviewers submit scored feedback.
- A **hiring committee** of people who did not interview you reads the packet: resume, feedback, sometimes references. It recommends hire and **level**. Further leadership review and team matching follow ⚠ (the sequence has changed over the years).
- Because the committee never met you, **written evidence is literally all that exists**.

**Meta** (commonly reported ⚠):
- Interviewers rate defined signals.
- A debrief and calibration decides hire and level.
- For E6 and above, the behavioral round and system design carry much of the **leveling** signal. A strong coding performance with E5-shaped behavioral stories tends to produce an E5 outcome.

**Smaller and later-stage companies** (Stripe, Netflix, Uber and others) vary: often a hiring manager plus a debrief, sometimes with a committee. The mechanics differ; the principle doesn't. Evidence at a level, written down, decides.

### 2.3 Three consequences candidates underestimate

1. **Level consistency across the loop.** One interviewer writing "solid L5 scope" next to four writing "L6" pulls the packet down. Every behavioral story, and the behavioral parts of design rounds, must carry your target scope.
2. **Insufficient signal is a negative.** A pleasant answer without specifics produces a thin writeup. Thin writeups read as "couldn't demonstrate", which becomes a down-level or no-hire, never a benefit of the doubt.
3. **The probe is the test.** Your prepared opening is the part every candidate rehearses. Interviewers spend the remaining 70% of the time probing **whether you were the one who did it** (§5 and §8). Stories that only survive on rails fail there.

## 3. The seven dimensions scope is measured on

Interviewers rarely use these names, but every probe maps to one of them.

| Dimension | L4 (mid) | L5 (senior) | L6 (staff) | L7 (principal) |
|---|---|---|---|---|
| **Problem origin** | Assigned a task | Assigned a problem | *Found* a problem that crosses teams | *Found* a strategic or existential problem nobody had framed, often before it hurt |
| **Ambiguity** | Clear spec | Clear goal, unclear path | Unclear goal inside a known area | Unclear area: decides what the problem *is* and whether it matters |
| **Blast radius** | A feature | A service or pipeline | Several teams' systems | An org, a platform, a business line |
| **Time horizon** | Weeks | A quarter | 6–18 months | Multi-year direction with near-term proof points |
| **Influence mechanism** | Code | Design docs, code review, mentoring | RFCs, consensus across skeptical tech leads, cross-team execution | Strategy and roadmap change, exec alignment, standards adopted by many teams, org design input |
| **Impact unit** | Tickets, features | Service SLOs, delivery | Org-level technical metrics (P99, cost, velocity, incident rate) | Business outcomes (revenue protected, cost, risk, time-to-market) **plus** a capability that keeps paying |
| **Leverage** | Own output | Own output + a junior or two | Other teams' output | Owners created: L5/L6s who now run domains; mechanisms that work without you |

**Two dimensions do most of the separation between L6 and L7:**
- **Problem origin.** An L6 story starts from a pain several teams feel. An L7 story often starts from a pain **no one feels yet**: a scaling wall, a cost curve, a regulatory change, a competitor's move. The candidate made it real enough that senior leaders changed plans.
- **Leverage.** An L6 leads the migration. An L7 also leaves behind **people and mechanisms**: domain owners, a paved road, a review standard, a decision process. These make the next ten migrations happen without them.

The size of the numbers is a weak signal. A $4M saving executed from someone else's plan is L6 evidence; a $400k saving from a problem you discovered and an org you rewired can be L7 evidence.

## 4. The linguistic shift, sentence by sentence

Here are the canonical one-line summaries at each level, annotated with what the committee extracts from each.

| Level | The sentence | Verbs that carry the level | What the committee writes | What's missing for the next level |
|---|---|---|---|---|
| **L4** | "I was given a ticket/spec and implemented the feature cleanly." | *given, implemented* | Executes well-defined work | Why the work mattered; any decision; anything beyond the ticket |
| **L5** | "I owned a complex microservice/pipeline end-to-end, mentored junior devs, and delivered on time." | *owned, mentored, delivered* | Reliable owner of a team-scoped system | A problem they found; influence outside the team; an org-level outcome |
| **L6** | "I noticed 3 teams were hitting the same data-ingestion bottleneck, authored an RFC comparing 3 architectures, built consensus across skeptical tech leads, led the cross-team migration, and reduced org-wide P99 latency by 65%." | *noticed, authored, built consensus, led* | Finds cross-team problems; decides between real alternatives; moves peers without authority; delivers an org metric | The business stakes; changing what leaders fund; people and mechanisms that outlast the project |
| **L7** | "I identified that our multi-year platform architecture would hit a hard scaling/cost wall within 12 months and threaten a $50M business line. I aligned VP/Director stakeholders to pivot the roadmap, established a cellular platform architecture adopted by 8 teams, mentored L5/L6 engineers into domain owners, and saved $4M/year in cloud TCO while cutting onboarding from 6 weeks to 3 days." | *identified (before it hurt), threaten (business translation), aligned VPs, pivot the roadmap, established (a standard), mentored into owners* | Foresight; translates technology into business risk; changes strategy; sets standards others adopt; grows owners; delivers money **and** capability | (At L8: multiple orgs or the company, industry influence) |

### 4.1 Markers that read as real, and markers that read as inflation

| Reads as real ownership | Reads as inflation (and triggers probing) |
|---|---|
| A named counterpart and their objection: "the inventory TL's concern was replay cost" | "I drove alignment across stakeholders" with no one named |
| A decision with a rejected alternative: "I chose per-tenant cells over a shared cluster because…" | "We went with the best architecture" |
| A baseline: "P99 went from 1.8 s to 620 ms on checkout reads, 4-week windows" | "Latency improved 65%" |
| A cost of the choice: "we gave up cross-cell joins; analytics moved to the lake" | Only upside |
| A person you grew: "Ana now owns the cell router; she presented it to the architecture council" | "I mentored the team" |
| An artifact: "a six-page proposal; the VP's comments are in it" | "I worked closely with leadership" |

## 5. How interviewers separate owners from passengers

Every technique below is designed to be answerable only by someone who was there and decided things.

| Technique | The probe | What a passenger reveals | What an owner reveals |
|---|---|---|---|
| **Zoom out** | "Why did this matter to the business?" | Repeats the technical goal | States the business risk, who cared, and why now |
| **Zoom in** | "Walk me through the hardest technical decision. Draw it." | Stays at slide level | Draws the data flow, names the failure modes, cites the numbers that decided it |
| **Counterfactual** | "What would have happened if you hadn't been there?" | "The team would have figured it out" | "The default was option B; it would have hit the wall in Q3. Nobody else was looking at the growth curve." |
| **Decision rights** | "Who made the final call?" | "We decided as a team" / "My architect" | "I recommended; my director decided, after I'd resolved the TL's objection. Here's what I decided alone." |
| **Friction** | "Who disagreed, and what was their best argument?" | "Everyone was aligned" | Names the person, states their argument *fairly*, says what they conceded and what you did |
| **Week 3** | "What were you personally doing in the third week?" | Vague activity | Specific: "Writing the backfill validator, and running the weekly cutover review with the three TLs" |
| **Artifact** | "What did you write? Who read it?" | "There were some docs" | "The RFC; the VP and four TLs reviewed it; the key comment changed the rollout order" |
| **Metric provenance** | "How was that measured? What else changed?" | Number, no method | Baseline window, measurement source, confounders, attribution |
| **Repeatability** | "What did you leave behind?" | "The system" | "A standard, an owner, a review gate. The next two migrations ran without me." |

Strong interviewers alternate zoom-out and zoom-in within one story. Real owners move between the business and the bytes without strain; borrowers can do one or the other.

## 6. Hiring Committee Scoring Rubric

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | No hire |
|---|---|---|---|---|
| **Problem framing** | Discovered a strategic problem early; quantified business risk; made leaders care | Found a real cross-team problem; framed it crisply | Worked on a problem someone handed them | Can't articulate why the work mattered |
| **Scope** | Org or business line; multiple teams adopted the outcome | Several teams; one org metric | One team or service | Task-level |
| **Decision quality** | Real alternatives with explicit criteria and costs; reversibility considered; revisited when facts changed | Compared alternatives; clear rationale | One option, justified after the fact | Can't explain why |
| **Influence** | Changed what VPs/directors funded or prioritized; resolved principled conflict between valid priorities | Built consensus among peer TLs without authority | Influence within own team | Relied on authority or escalation only |
| **Execution under friction** | Drove a multi-team, multi-quarter effort through real setbacks; sequenced risk | Led a cross-team migration to completion | Delivered own part on time | Delivery depended on others; unclear role |
| **Impact & measurement** | Business + technical + capability impact, with baselines and attribution | Org-level technical impact with numbers | Team-level delivery metrics | No measurable outcome |
| **Leverage** | Created owners and mechanisms that outlast them | Upleveled engineers across teams | Mentored juniors on own team | None |
| **Self-awareness** | Names their own wrong bets and what changed in their judgment | Reflects on what they'd improve | Generic lessons | Blames others |
| **Consistency** | Every story at L7 scope, with range across conflict, failure and people | Mostly L6 with depth | Mostly L5 | Mixed or unconvincing |

### 6.1 The ten most common down-level triggers

1. Every story is inside one team.
2. Impact is "delivered on time", "migrated successfully" or "improved performance", with no business translation.
3. The important decisions were made by your manager, an architect or a director, and the story doesn't say what *you* decided.
4. No one disagreed. (No friction means no influence was needed.)
5. Numbers without baselines, measurement or attribution.
6. You can zoom out *or* zoom in, but not both.
7. "We" throughout. The interviewer can't isolate your contribution (Folder 02 dissects this).
8. Only *executing* someone else's strategy, never shaping it.
9. No people leverage beyond "mentored juniors".
10. The failure story is a bug someone else caused.

### 6.2 What ends up in the packet (illustrative writeup excerpts)

**An L7-supporting writeup:**
> "Candidate identified, unprompted, that marketplace seller onboarding would raise event volume ~10× within a year and that all three ingestion pipelines would breach the inventory-accuracy SLA. Quantified exposure at roughly $X M/yr in seller penalties and oversell refunds and took it to the VP of Engineering and the VP of Product, who moved two quarters of a planned feature to fund the work. Chose cell-per-tenant-tier over a shared cluster; explained the trade-off (no cross-cell joins) and how analytics was moved to the lake. The most resistant stakeholder was the pricing TL (replay cost); the candidate built a replay prototype that cut his estimate by 70% and conceded the rollout order. Eight teams adopted the platform; two L5s now own the router and the schema registry. Strong evidence: Think Big, Are Right A Lot, Earn Trust, Hire and Develop."

**An L5-shaped writeup for the same person, if they tell it badly:**
> "Candidate migrated the inventory pipeline to a new streaming platform with their team. Reduced latency ~40%. Mentioned other teams joined later. Did not describe alternatives considered or any disagreement. When asked who decided on the architecture, said the team did. Impact described in latency only. Solid execution; scope appears to be single-team."

Same project, same person. The second packet gets an L5 offer.

## 7. Story Blueprints

### 7.1 One project, three levels (composite: event-ingestion consolidation)

**The facts** (composite; numbers are placeholders):
- A commerce company. Three teams (search indexing, pricing, inventory) each run their own Kafka → stream-processing → warehouse pipelines.
- Each re-implements deduplication and late-event handling, differently.
- Inventory counts disagree between search and checkout often enough to cause oversell incidents.
- Pipeline cost is growing ~40% a year.
- A marketplace program, starting in about 12 months, will multiply event volume roughly tenfold.

#### How an L5 tells it

> "I owned the inventory pipeline. It was struggling with late events and duplicates, so I migrated it from our old consumer service to a streaming job with event-time windows and idempotent writes. I wrote the design, mentored two juniors through the implementation, and we delivered in one quarter. Latency dropped about 40%, and the duplicate rate went to nearly zero. Later the search team adopted some of our patterns."

**What the committee extracts:** a good owner of one pipeline. Assigned problem, one team, technical metric, no alternatives, no friction. **L5.**

#### How an L6 tells it

> "While fixing duplicates in the inventory pipeline, I noticed that search and pricing had the same problem in different forms. Three teams were maintaining three dedup implementations, and their disagreement was the root cause of our oversell incidents.
>
> I wrote an RFC with three options:
> - a shared library, which was cheap but kept three operational surfaces;
> - a shared ingestion service with per-team sinks;
> - standards only.
>
> I recommended the shared service. The pricing TL was the skeptic: he worried that replay during backfills would blow his compute budget. I built a replay prototype against a week of his traffic, which showed the cost was 30% of his estimate, and we agreed pricing would migrate last.
>
> I led the migration across all three teams over two quarters. Org-wide P99 ingest-to-queryable latency dropped 65%, oversell incidents went from about six a month to under one, and we decommissioned two clusters."

**What the committee extracts:** found a cross-team problem; real alternatives; resolved a principled objection with evidence; led execution across boundaries; org metric. **Solid L6.** Missing for L7: business stakes beyond incidents, a change in what leadership funded, and people and mechanisms left behind.

#### How an L7 tells it

> "Twelve months before the marketplace launch, I modeled what seller onboarding would do to our event volume: roughly ten times. I found that all three ingestion pipelines would breach the inventory-accuracy commitment we were about to put in seller contracts. That exposure was about $X M a year in penalties and oversell refunds, and it put the launch itself at risk. Nobody owned that question, because each team's pipeline looked fine against its own roadmap.
>
> I wrote a six-page proposal framing it as a launch risk, not a platform rewrite. I compared three paths:
> - scaling the three pipelines independently;
> - one shared cluster;
> - a cell-based event platform, with cells per tenant tier and one standard dedup and late-data contract.
>
> I recommended cells. They capped blast radius per tier and let us onboard sellers without re-certifying everyone. The cost was giving up cross-cell joins, so I moved those analytics to the lake.
>
> The hard part was the roadmap. Funding the platform meant delaying a pricing feature the VP of Product wanted for Q2. I sat down with her and the VP of Engineering with the risk model and a phased plan: the first cell would carry the existing inventory traffic within six weeks, as a proof point. They moved two quarters of that feature's capacity to the platform.
>
> The pricing TL was the strongest skeptic, on replay cost. I built a replay prototype on his real traffic that cut his cost estimate by 70%, and I agreed his team would migrate last, after the cutover tooling had been proven on inventory.
>
> I set the event contract as the org standard, and asked two L5s to own the cell router and the schema registry. I coached both through their first design reviews with the architecture council.
>
> Eight teams are on the platform now. Oversell incidents went from about six a month to near zero through launch. We save about $Y M a year in cluster cost, and onboarding a new event source dropped from six weeks to three days. The two L5s were promoted; the router owner led the next two migrations without me."

**What the committee extracts:**
- foresight, and a business translation of a technical risk;
- a strategic reframing ("launch risk, not rewrite");
- explicit alternatives and costs;
- changed what VPs funded;
- resolved a principled objection with a prototype, and conceded something real;
- a standard adopted by eight teams;
- people grown into owners;
- business, technical and capability impact.

**Strong L7.** Notice that the technical work is the same as the L6 version. The difference is problem origin, business framing, the roadmap change, and leverage.

### 7.2 A second domain (composite: an LLM inference gateway)

#### How an L5 tells it

> "I built our team's LLM gateway: request routing, retries, caching and a cost dashboard. I added semantic caching, which cut our token spend by about 30%. Two other teams started using it."

#### How an L7 tells it

> "Six product teams were calling model providers directly. Our blended inference cost was growing faster than usage, and two teams had leaked customer data into prompts sent to a provider without a data-processing agreement. I framed that as two risks to the CFO's and the CISO's staff: a cost curve that would make the assistant roadmap unaffordable within three quarters, and a compliance exposure.
>
> I proposed one paved road: a gateway with policy enforcement (PII redaction, provider allow-lists), routing by task to the cheapest model that passed each team's eval suite, and per-team budgets. I compared it with mandating a vendor SDK and with leaving teams independent behind a policy document. The gateway won because policy enforcement had to happen in the request path; a document couldn't stop a bad request.
>
> The friction was product teams fearing latency and lock-in. I published a latency budget (gateway overhead under 15 ms at p99) and a 'bring your own model' escape hatch. I had the first two migrations done by their own engineers, pairing with them, so the pattern spread team to team rather than by mandate.
>
> In two quarters, all six teams were behind it. Cost per resolved conversation fell about 45% through routing and caching. Prompt-data incidents went to zero, with an audit trail the CISO's team now uses. An L6 I mentored owns the eval-gated routing system and runs the quarterly model reviews."

## 8. Adversarial Bar-Raiser Follow-Up Chains

Each chain is a sequence one interviewer might run on a single story. For each probe: what it tests, how a passenger answers (down-level), and how an owner answers.

### Chain A · "Who actually decided?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Who wrote the proposal?" | Authorship | "It was a team effort" | "I did. Ana wrote the router section; I wrote the risk model and recommendation." |
| 2 | "Who approved it?" | Decision rights | "Leadership" | "The VP of Engineering, after the VP of Product agreed to the trade-off on the Q2 feature." |
| 3 | "What did your director think before you talked to them?" | Whether you moved anyone | "They were supportive" | "She thought it was a platform rewrite in disguise. The phased plan with a six-week proof point changed that." |
| 4 | "Name a decision you made that someone senior disagreed with." | Backbone | Can't produce one | "Pricing migrating last. My director wanted the big team first, for the headline. I argued the cutover tooling had to be proven on lower-risk traffic, and he agreed." |
| 5 | "If you'd left in month two, what happens?" | Counterfactual | "The team continues" | "The default plan was scaling three pipelines; nobody owned the cross-team model. I believe the launch slips or ships with penalties." |

### Chain B · Metric provenance 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "65% of what, exactly?" | Precision | "Latency" | "P99 ingest-to-queryable, for inventory events, measured at the sink." |
| 2 | "Over what window? What was the baseline?" | Method | Unsure | "Four weeks before cutover against four weeks after, with the same seasonal week last year as a sanity check." |
| 3 | "What else changed in that period?" | Attribution | "Nothing major" | "A broker upgrade landed in week two. I isolated it: its effect was under 5% on a canary topic." |
| 4 | "How did you get the dollar figure?" | Business translation | Vague | "Contract penalty terms × projected oversell rate at 10× volume, validated with finance. It's a range, X–1.6X." |
| 5 | "What did it cost?" | Honesty | Only gains | "Two quarters of capacity, a delayed pricing feature, and cross-cell joins. Here's how we mitigated each." |

### Chain C · Friction

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Who disagreed most?" | Real influence | "No one really" | Names the role and their position |
| 2 | "What was their best argument?" | Steelmanning | Dismisses it | States it fairly: "Replay during backfills could triple his compute" |
| 3 | "Were they right about anything?" | Intellectual honesty | "Not really" | "Yes, the order. Migrating pricing last was his idea in spirit." |
| 4 | "How did you change their mind, or didn't you?" | Influence mechanism | "Escalated" / "Overruled" | "A prototype on his real traffic, plus a concession on sequencing" |
| 5 | "How is that relationship now?" | Earn Trust | "Fine" | "He co-presented the replay tooling at the quarterly review" |

### Chain D · Zoom in

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Draw the cell architecture." | Technical depth | Boxes, no data flow | Router, partitioning key, per-cell storage, contract |
| 2 | "How did dedup work across a cell migration?" | Hard detail | Hand-waves | Idempotency keys, dual-write window, validator comparing counts |
| 3 | "What was the riskiest moment of cutover?" | Execution reality | "It went smoothly" | Names it: "the first backfill overlapping live traffic. We gated on a reconciliation diff." |
| 4 | "What would you change with hindsight?" | Judgment | "Nothing" | A real regret, with its cost |

### Chain E · Leverage and persistence

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Who owns it now?" | Succession | "My team" | Named owners and their scope |
| 2 | "What happens when you're on vacation?" | Mechanisms | Hesitation | Runbooks, an on-call rotation, the council review, the standard |
| 3 | "What did the people you mentored do next?" | Upleveling | Generic | Specific promotions or projects they led |
| 4 | "What mechanism did you leave that will matter in three years?" | L7 leverage | The system itself | The event contract and the review gate every new pipeline passes |

## 9. Position honestly: a strong L6 beats a collapsed L7

Interviewers probe for 20 minutes per story. An inflated story collapses somewhere between probe 2 and probe 4, and the writeup then says **credibility concern**. That is worse than any down-level: it turns into a no-hire, and it colors every other interview in the debrief.

**If your real scope is L6, target L6 and saturate it with evidence.** One L7-shaped story inside an otherwise excellent L6 packet often leads to the conversation "is this person ready for L7 within a year?". That's a good place to negotiate from.

**What this KB will not do** is help you claim work you didn't do. It helps you **find the L6/L7 evidence already in your real work**, which is usually larger than you think (Folder 06), and **tell it at its true size**.

## 10. Checklist

- [ ] Ask the recruiter for the target level and its expected scope at that company.
- [ ] For each story: problem origin, blast radius, time horizon, influence mechanism, impact unit and leverage written down, at the target level.
- [ ] Every story has a named counterpart who disagreed, and what changed their mind.
- [ ] Every number has a baseline, a method and an attribution argument.
- [ ] You can zoom out to the business and zoom in to the hardest technical decision in the same story.
- [ ] You can say what *you* decided, distinct from what the team did and what your manager approved.
- [ ] Each story leaves people or mechanisms behind.

## 11. References

- Will Larson, *Staff Engineer: Leadership beyond the management track*. <https://staffeng.com/book>
- Tanya Reilly, *The Staff Engineer's Path* (O'Reilly, 2022; ISBN 978-1-098-11873-0). Author's page: <https://www.noidea.dog/staff>
- Amazon, *Leadership Principles*. <https://www.amazon.jobs/content/en/our-workplace/leadership-principles>
- Google Careers, *How we hire*. <https://www.google.com/about/careers/applications/how-we-hire/>
- Laszlo Bock, *Work Rules!* (Twelve, 2015): Google's structured interviewing and hiring committees, from the inside.
- In this KB: [01.2 Archetypes and narrative](02-the-four-staff-principal-archetypes-and-framing-your-narrative.md) · [01.3 Beyond STAR](03-beyond-star-the-l7-executive-storytelling-architecture.md)
