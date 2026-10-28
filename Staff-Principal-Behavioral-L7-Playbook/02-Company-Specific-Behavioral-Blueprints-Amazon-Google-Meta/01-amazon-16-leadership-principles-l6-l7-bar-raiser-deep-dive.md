# 02.1 · Amazon's 16 Leadership Principles at L6/L7: The Bar-Raiser Deep Dive

> **Folder 02 · File 1 of 3.** Every Amazon interviewer is scoring Leadership Principles (LPs). At L6/L7 they are scoring the *same sixteen principles* they score at L5, so the principles don't tell you the level. **The size of the evidence unit does.** An L5 shows Ownership of a service; an L7 shows Ownership of a business outcome no team owned.
>
> This file covers:
> - how an Amazon loop turns your stories into a hire/no-hire and a level;
> - the "I" vs "we" probe, and how to give credit while isolating your contribution;
> - all sixteen LPs with L5 vs L6/L7 evidence;
> - deep dives on the five where senior expectations diverge most: Are Right, A Lot; Have Backbone/Disagree and Commit; Think Big (with Frugality and Bias for Action); Strive to be Earth's Best Employer; Earn Trust;
> - the Backbone/Disagree-and-Commit **two-story requirement**;
> - a debrief rubric, five story blueprints, and six follow-up chains.
>
> Vocabulary from Folder 01: scope labels (L5 Senior, L6 Staff, L7 Principal), the seven scope dimensions, and the C-T-O-A-R-L beats. ⚠ marks practitioner-reported mechanics. Stories are **illustrative composites** with placeholder numbers.

---

## 1. How an Amazon loop turns stories into a decision

### 1.1 The mechanics

⚠ Described publicly in part (Amazon's interview-prep pages; Bryar and Carr's *Working Backwards*), the rest practitioner-reported:

1. **Each interviewer is assigned LPs**, typically two or three, so the loop as a whole covers most of them. Your system-design interviewer is also scoring LPs (often Invent and Simplify, Dive Deep, Are Right A Lot).
2. **One interviewer is a Bar Raiser**: trained for the role and from outside the hiring team, so they have no stake in filling the seat. Their job is the long-term bar, and *Working Backwards* describes them as able to block a hire.
3. **Interviewers write feedback before the debrief**, organized by LP. Good feedback quotes you. "Candidate said: 'I made the call to stop the rollout at 20%'" is a data point. "Candidate showed ownership" is not.
4. **The debrief is a discussion, not a vote count.** The Bar Raiser leads it. A single well-evidenced concern (a credibility gap, a pattern of blaming others) can outweigh several lukewarm inclines.
5. **The bar is relative to the current population.** Amazon's stated intent is that a new hire raises the average of the people already at that level. At L7 that means comparing you against existing Principals, which is a small, strong population.

**Consequence:** your job in every answer is to hand the interviewer **quotable sentences about what you decided and did**, tagged (implicitly) to an LP. Interviewers who can't write data points write "insufficient signal", and insufficient signal at L7 becomes a down-level.

### 1.2 What changes at L6/L7

The principles are the same text at every level. What the loop expects as *evidence* is not.

| Same LP | L5 evidence unit | L6 evidence unit | L7 evidence unit |
|---|---|---|---|
| Ownership | My service, my on-call, my backlog | A cross-team problem nobody owned | A business outcome nobody owned; you changed which org owns it |
| Dive Deep | I found the bug | I found the systemic cause across services | I found that the org's *metric* was wrong and changed what leadership watches |
| Deliver Results | Shipped my project on time | Landed a multi-team program through setbacks | Moved a business input metric across an org, for quarters |
| Hire and Develop | Mentored a new hire | Grew L5s across teams; raised interview quality | Built owners who now lead what you started; changed how the org grows engineers |

Amazon also publishes the **Principal Engineering Community Tenets**, which describe what it expects of its most senior ICs: *Exemplary practitioner; Technically fearless; Lead with empathy; Balanced and pragmatic; Illuminate and clarify; Flexible in approach; Respect what came before; Learn, educate, and advocate; Have resounding impact.* Amazon publishes only the names. How they read against the LPs is this KB's interpretation:

| Tenet | What it adds to the LPs at L7 | Story evidence that shows it |
|---|---|---|
| Exemplary practitioner | You still do deep technical work yourself | You wrote the prototype, the risk model or the hard part of the design |
| Technically fearless | You take the problem everyone avoids | You took on the system nobody would touch, or the question nobody would ask |
| Lead with empathy | Influence that respects people's constraints | You redesigned the plan around a team's real pressures |
| Balanced and pragmatic | Not every problem gets the beautiful solution | You chose the boring option and can say why |
| Illuminate and clarify | Turn fog into decisions | Your document made a contested choice obvious to executives |
| Flexible in approach | Change your mind when facts change | You reversed your own recommendation with data |
| Respect what came before | Legacy was built under constraints you don't see | You found out why the old system was built that way before replacing it |
| Learn, educate, and advocate | Multiply knowledge | Talks, reviews, standards, people you taught |
| Have resounding impact | Outcomes at business scale | Org-level, multi-year effects |

"Respect what came before" is the one candidates most often violate in front of an Amazon Bar Raiser: the L5 migration story that opens with "the legacy system was a mess" reads as a judgment flaw at L7.

### 1.3 The Amazon artifacts an L7 story should name

Amazon runs on written mechanisms. Naming the right artifact signals you've operated at the level where they matter:

| Artifact | What it is | Where it shows up in a story |
|---|---|---|
| **Six-pager / narrative** | A prose memo read silently at the start of a meeting | "I wrote the six-pager that framed it as a launch risk" |
| **PR/FAQ** | Working Backwards: the press release and FAQ written before building | Think Big and Customer Obsession stories |
| **Mechanism** | A complete process (tool + adoption + audit) that makes good behaviour the default; the contrast is "good intentions" | Every L7 Learning-and-leverage beat |
| **Tenets** | Short, ordered principles a team uses to decide trade-offs | "I wrote the three tenets the platform team still uses to reject requests" |
| **COE (Correction of Error)** | Amazon's postmortem format: impact, timeline, five whys, actions | Failure stories (Folder 05) |
| **Input vs output metrics** | Inputs are controllable (selection, latency, defect rate); outputs follow (revenue) | Deliver Results at L7: you moved an *input* the business review tracks |
| **One-way / two-way doors** | Bezos's 2015 letter: irreversible decisions get care, reversible ones get speed | Bias for Action, Are Right A Lot (Folder 04) |

---

## 2. The "I" vs "we" probe

### 2.1 Why Amazon interviewers chase it

The interviewer is writing feedback about **you**. "We migrated the order pipeline" can't be attributed. Amazon interviewers are trained to interrupt: "What did *you* do?" Each interruption costs you time, and if they have to ask three times, the feedback says "unclear individual contribution", which at L6/L7 is fatal.

### 2.2 The credit-isolation pattern

You don't fix this by deleting "we". You fix it by **separating three things in every story**: what the team delivered, what you decided and did, and who else deserves named credit.

> **Team outcome** ("we shipped…") → **my decision** ("the call I made was…") → **my action** ("I wrote / built / negotiated…") → **named credit** ("Priya built the reconciler; that was the hardest code in the project").

| Unattributable | Isolated, with credit given |
|---|---|
| "We decided to use cells." | "I proposed cells over a shared cluster; the architecture review approved it after I showed the blast-radius model." |
| "We migrated eight teams." | "The teams migrated themselves; I built the cutover tooling and sequenced who went when." |
| "We had a lot of debate." | "The pricing TL and I disagreed on replay cost. I built a prototype on his traffic." |
| "The team improved latency 40%." | "Priya's reconciler removed the second hop, which was most of the 40%. My part was finding that the hop existed and making the case to remove it." |
| "We worked with product." | "I took the trade-off to the VP of Product myself, with the risk model." |
| "Leadership agreed." | "The VP of Engineering moved two quarters of capacity after I proposed the phased plan." |

Notice the fourth row: **naming a teammate's larger contribution is a strength**, not a weakness. It's Earn Trust evidence, and it makes everything else you claim more credible.

### 2.3 The over-correction: the royal "I"

Candidates coached on "say I" often swing to claiming everything: "I built the platform, I migrated the teams, I reduced cost." Bar Raisers probe this immediately ("Who wrote the router?"), and a story where you claimed the whole team's work collapses on the first detail you can't supply. That reads as an **Earn Trust** failure, which is worse than vagueness.

**Heuristic:** "we" for outcomes, "I" for decisions and actions, names for other people's contributions.

### 2.4 The L7 nuance: your "I" moves up the stack

At L7 much of the execution is done by others. Your "I" lives in:
- **framing**: "I reframed it as a launch risk";
- **choices**: "I chose to sequence pricing last";
- **commitments you extracted**: "I got the VP to move two quarters";
- **mechanisms**: "I set the event contract as the org standard";
- **stopping things**: "I halted the rollout at 20%";
- **people**: "I made two L5s owners and coached them through their first council reviews".

An L7 who tells a story full of "I wrote the code" sounds like a strong L5. An L7 whose "I" is entirely meetings sounds like a manager-lite (01.2). The best L7 stories have one **zoom-in** where you did hard technical work yourself (Exemplary practitioner), inside a story whose arc is organizational.

---

## 3. All sixteen LPs: L5 vs L6/L7 evidence

Short quotations are from Amazon's published principles; the evidence columns are this KB's calibration.

| LP | L5 evidence | L6/L7 evidence | The L7 trap |
|---|---|---|---|
| **Customer Obsession** ("start with the customer and work backwards") | Fixed a customer-reported problem in my service | Worked backwards from a customer outcome to change a multi-team roadmap; can name the customer metric | "Customer" means an internal stakeholder only; no line to the end customer |
| **Ownership** ("never say 'that's not my job'") | Owned my service end to end | Took a problem nobody owned; acted for the company over your team | Owning everything personally instead of creating owners |
| **Invent and Simplify** | Built a clever solution | Removed a whole category of work or system; simplified for many teams | Invention without simplification; a new platform that adds a layer |
| **Are Right, A Lot** ("seek diverse perspectives and work to disconfirm their beliefs") | Made a good technical call | Judgment track record on ambiguous, high-stakes calls, *including how you sought disconfirmation* | Telling only stories where you were right from the start |
| **Learn and Be Curious** | Learned a new technology | Learned a new domain (finance, legal, supply chain) to frame a problem correctly | Curiosity as a hobby, not applied to the business |
| **Hire and Develop the Best** | Mentored one engineer | Grew owners across teams; raised hiring bar (interviewing, Bar Raiser track, rubric work) | "Mentored juniors" with no outcome |
| **Insist on the Highest Standards** ("problems are fixed so they stay fixed") | Code review rigor; tests | A standard or gate that changed quality for an org | Perfectionism that blocked delivery |
| **Think Big** ("create and communicate a bold direction") | A good idea for my team | A multi-year direction others adopted and funded | Vision with no first step (ivory tower, §4.3) |
| **Bias for Action** ("many decisions are reversible") | Moved fast on a fix | Separated one-way from two-way doors and set the pace accordingly | Speed on an irreversible decision |
| **Frugality** ("no extra points for growing headcount") | Saved cost in my service | Delivered a big outcome with constrained resources; retired systems to fund new ones | Cost cutting that created risk |
| **Earn Trust** ("vocally self-critical") | Good working relationships | Rebuilt trust with a sceptical org; publicly owned your own mistake | Only stories where you look good |
| **Dive Deep** ("skeptical when metrics and anecdote differ") | Debugged a hard problem | Found that a trusted metric was misleading; audited the system behind a dashboard | Depth with no consequence for decisions |
| **Have Backbone; Disagree and Commit** | Pushed back on a design in review | Challenged a senior leader with data, and committed wholly when you lost (§4.2) | Backbone only against peers or juniors |
| **Deliver Results** | Shipped on time | Moved a business input metric through real setbacks | Output ("shipped") instead of outcome |
| **Strive to be Earth's Best Employer** | Kind teammate | Mechanisms for on-call health, growth, inclusion and safety at org level (§4.4) | Treating it as an HR question rather than an engineering-leadership one |
| **Success and Scale Bring Broad Responsibility** | Considered privacy or accessibility in my feature | Weighed second-order effects (privacy, sustainability, partner impact) in an org decision | A generic statement with no decision it changed |

---

## 4. The five LPs where L6/L7 expectations diverge most

### 4.1 Are Right, A Lot

**What changes at senior levels:** at L5, being right is about a technical call. At L6/L7 it's about **judgment under ambiguity, and process**: how you sought evidence against your own view. The principle's own text puts the emphasis there: "seek diverse perspectives and work to disconfirm their beliefs".

What an L7 answer contains:
1. **A real prior**, stated honestly: "My instinct was X."
2. **A deliberate attempt to disconfirm it**: a pre-mortem, a dissenting reviewer you sought out, a cheap experiment designed to fail.
3. **Kill criteria set in advance**: "If p99 exceeds 30 ms at 10% traffic, we stop."
4. **A track record across bets**, not one lucky call: "Of the four big bets I made in that org, three held; the fourth I reversed in month two."
5. **What changed in your judgment** after you were wrong.

**Trap:** an "Are Right A Lot" story where you were right from the start and nobody disagreed. That's evidence of luck, not judgment.

### 4.2 Have Backbone; Disagree and Commit: the two-story requirement

The principle has two halves, and senior loops test both. Prepare **two separate stories**:

| | Story A: Backbone (you challenged and moved a decision) | Story B: Disagree and Commit (you lost, and made it succeed) |
|---|---|---|
| **Counterpart** | Someone *senior* to you: a director, VP or more senior principal | The decision-maker who overruled you |
| **What you show** | Data or a prototype, not opinion; respectful escalation; tenacity | Wholehearted commitment; no re-litigation; you made the chosen path succeed |
| **Outcome** | The decision changed, or a better hybrid emerged | The chosen path shipped and worked (or failed for reasons you'd flagged, handled without "I told you so") |
| **L7 extra** | You changed the *decision process*, not just the decision | You learned something about your own judgment: what the decider weighted that you didn't |

Bezos named "disagree and commit" in his 2016 shareholder letter as a way to keep high-velocity decisions moving. He gave the example of himself disagreeing and committing to a team's call.

**What disagree-and-commit is not:**
- *Malicious compliance:* doing it badly to prove a point.
- *Passive commitment:* "I did my part as told."
- *Re-litigation:* reopening the decision every sprint.
- *"I told you so":* when the risk you flagged materializes.

The senior form of commitment is **making the risks you raised into tracked, owned mitigations** inside the chosen plan, with agreed tripwires for revisiting it, so that if you were right, the system tells everyone, not you.

**When you should not commit:** safety, legal, ethical or security issues are escalation matters, not disagree-and-commit matters. An L7 can say where that line is. If a loop asks "would you ever not commit?", the answer is yes, with that line drawn precisely.

### 4.3 Think Big, with Frugality and Bias for Action: avoiding the ivory tower

These three principles pull against each other. Think Big alone produces the **ivory-tower architect** (01.2): a twelve-month vision document, a platform nobody asked for, and a request for headcount. Frugality and Bias for Action alone produce a tactician who never changes direction. The L7 story holds all three at once:

| Element | Ivory-tower version | L7 version |
|---|---|---|
| Direction | "A unified platform for everything" | A bold end state, *plus* the customer problem it solves first |
| First step | Phase 1 is twelve months | A proof point in six weeks with the people you already have |
| Funding | New headcount | Retire or consolidate systems to fund the next phase |
| Reversibility | One big irreversible migration | Two-way-door increments; the one-way door identified and saved for when the evidence is in |
| Adoption | Mandate | Teams pulled in by the first proof point |

The sentence that tells a Bar Raiser you're not ivory-tower: **"The first phase paid for the second."**

### 4.4 Strive to be Earth's Best Employer, for an IC

Added in 2021. Many senior ICs prepare nothing for it because it sounds like a manager's principle. At L6/L7 it's an engineering-leadership principle about **the environment engineers work in**:
- **On-call health:** page budgets, toil limits, follow-the-sun handoffs, ending heroics as a norm.
- **Psychological safety in technical forums:** design reviews where juniors speak; blameless COEs (Folder 05).
- **Growth:** sponsoring people for visible work; spreading the glue work (01.2) rather than dumping it on the same people.
- **Inclusion in technical decisions:** who gets to be in the room for architecture choices; documentation and time zones that don't exclude distributed teams.

The L7 version is a **mechanism**, not an act of kindness: "I introduced a page budget per service. Any team above two out-of-hours pages per on-call week gets reliability work prioritized over features the next sprint. Median pages per week fell from eleven to three within two quarters, and attrition on those teams stopped being the outlier."

### 4.5 Earn Trust

The principle's text is unusually specific: "vocally self-critical, even when doing so is awkward or embarrassing", and leaders "benchmark themselves and their teams against the best".

- **L5 evidence:** good relationships; delivered what you promised.
- **L7 evidence:** you *rebuilt* trust that was damaged, often between orgs; you **publicly owned your own mistake in front of senior people**; you benchmarked your org's system against the best external one and reported the gap honestly.

**The test a Bar Raiser applies:** in all your stories, have you ever been wrong in public? If not, Earn Trust gets scored low regardless of how warm the relationships sound.

---

## 5. Hiring Committee Scoring Rubric (the Amazon debrief view)

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | No hire / Bar-Raiser concern |
|---|---|---|---|---|
| **Individual contribution** | Clear "I" in framing, decisions and mechanisms; credit to named others; one technical zoom-in | Clear decisions and actions across teams | Contribution visible only in own team's work | "We" throughout, or claims collapse on detail |
| **Ownership scope** | A business outcome with no prior owner | A cross-team problem | Own service | Says "that wasn't my area" |
| **Backbone** | Moved a VP-level decision with data or a prototype; changed the decision process | Changed a peer or director decision with evidence | Pushed back in code or design review | No disagreement in any story |
| **Commitment** | Lost an argument; turned the risks into owned mitigations; made it succeed; learned about own judgment | Committed and delivered after losing | "Did what was decided" | Re-litigated, or "I told you so" |
| **Are Right, A Lot** | Track record over several bets; sought disconfirmation; reversed own call with data | Good calls with stated alternatives | Right once, without alternatives | Can't recall being wrong |
| **Think Big / Frugality / Bias for Action** | Bold direction, first proof point fast and cheap, phases self-funding | Multi-team direction delivered incrementally | Team-level idea | Vision with no path, or action with no direction |
| **Earn Trust** | Vocally self-critical in front of senior people; rebuilt damaged trust across orgs | Honest about own errors; strong peer trust | Good relationships | Blames others; claims others' work |
| **Hire and Develop / Earth's Best Employer** | Created owners and org mechanisms (page budgets, review norms, rubrics) | Grew engineers across teams | Mentored on own team | No evidence |
| **Customer Obsession / Deliver Results** | Moved a customer-facing input metric across an org, with measurement | Org technical metric with customer link | Delivery on time | No measurable outcome |

**Bar-Raiser red flags that override inclines** (⚠ practitioner-reported pattern): a story that collapses on detail; disparaging former colleagues or "the legacy team"; every story ends with you right and others wrong; contradiction between two interviewers' accounts of the same story.

---

## 6. Story Blueprints

### 6.1 "I" vs "we" (composite: decomposing an order-routing monolith)

**The facts:** an order-routing service owned by four teams; deploys take a day of coordination; incidents in one routing rule take down all routing. The candidate led the decomposition.

#### How an L5 tells it

> "We had a monolithic routing service and deployments were painful. We decided to break it into per-fulfillment-type services. We had a lot of design discussions with the other teams and eventually agreed on an approach. We migrated over three quarters and deploy frequency went from weekly to daily. It was a great team effort."

**What the interviewer can write:** almost nothing attributable. "Team decomposed a service." Three follow-ups needed just to find the candidate. **Insufficient signal; L5 at best.**

#### How an L7 tells it

> "Routing was one service owned by four teams, and every deploy needed a day of coordination. Worse, a bad rule for one fulfillment type could stop routing for all of them. That happened twice in a quarter, and each time it stopped about $X M of orders for an hour.
>
> I made the case that this was a blast-radius problem, not a deploy-speed problem. That framing changed the design. Instead of splitting by team, I proposed splitting by failure domain: one routing cell per fulfillment type, behind a thin dispatcher that could fail open to a default route.
>
> I wrote the design and the migration sequence, and I made one call that the teams resisted: the highest-revenue type would go *last*, after the dispatcher had carried three lower-risk types for a month. The teams did the migrations themselves. My part was the cutover tooling, the shadow-traffic comparator, and the go/no-go for each cutover. Priya, an L5 on the grocery team, built the comparator's diffing engine, which was the hardest code in the project and caught two routing-rule bugs before they reached customers.
>
> Over three quarters all four types moved. Cross-type routing outages went to zero; deploys went from a weekly coordinated train to each team deploying on its own, several times a day. Priya now owns the dispatcher."

**What the interviewer can write:** reframed the problem (blast radius); chose the split; made and defended the sequencing call; built specific tooling; owned go/no-go; gave a named teammate credit for the hardest code; created an owner. Multiple quotable data points for Ownership, Are Right A Lot, Earn Trust, Hire and Develop.

### 6.2 Backbone, Story A (composite: challenging a synchronous fraud gate)

**The facts:** after a fraud spike, a director of risk mandates a synchronous fraud-model call on every checkout, adding ~180 ms at p99. The candidate believes most of the value can be captured without the latency.

#### How an L5 tells it

> "Our director wanted to add a synchronous fraud check to checkout. I thought it would hurt latency, so I raised it in the design review. I suggested we do it asynchronously. They listened, and in the end we went with a mix of both. Latency stayed reasonable."

**What the committee extracts:** disagreement raised, outcome vague, no data, unclear who moved whom. **L5.**

#### How an L7 tells it

> "After a fraud spike, the director of risk mandated a synchronous model call on every checkout. Her concern was legitimate: we'd lost $X M in a month. But the call added about 180 ms at p99, and our own experiments put the conversion cost of that much latency at roughly 1%, which was larger than the fraud loss.
>
> I didn't argue in the design review, because opinion against a director after a loss doesn't move anyone. I asked for two weeks and ran the model in shadow mode on all traffic. The data showed that 97% of fraud value sat in orders that hadn't shipped yet. Holding *fulfillment* for high-risk scores, rather than blocking *checkout*, captured almost all of it. The remaining 3% was in instant digital goods, where a synchronous check made sense.
>
> I took that to her one to one first, not in the review, so she could shape it before it was public. She pushed hard on the digital-goods edge cases, and she was right that our hold rule missed gift cards, so I added them to the synchronous path. The final design was synchronous for digital goods and gift cards, and an asynchronous score with a fulfillment hold for everything else.
>
> Checkout p99 stayed within 10 ms of baseline, fraud losses fell 92% over the next quarter, and she presented the design at the risk council as her team's standard. The lasting change was procedural: risk controls that touch checkout now require a shadow-mode run before launch. I wrote that requirement, and she co-signed it."

**What the committee extracts:** challenged a senior leader after a loss, which is the hardest time; used a prototype and data, not opinion; private-first escalation; conceded a real point; hybrid outcome; changed the decision *process*. Strong Backbone and Earn Trust.

### 6.3 Disagree and Commit, Story B (composite: losing the ledger argument)

**The facts:** a regulator's deadline requires new transaction reporting in nine months. The candidate argues for rebuilding the payments ledger on an event-sourced design first; the VP chooses to extend the existing ledger with a reporting adapter.

#### How an L5 tells it

> "I proposed rebuilding the ledger, but my manager and the VP decided to go with an adapter on the old system. I disagreed, but I committed and did my part of the work. We delivered on time. Later we had some reconciliation problems, which I had predicted, and then they agreed to plan the rebuild."

**What the committee extracts:** "did my part" is passive commitment; "which I had predicted" is "I told you so". **Down-level, and an Earn Trust flag.**

#### How an L7 tells it

> "We had nine months to deliver new regulatory transaction reporting. I argued for rebuilding the ledger on an event-sourced model first: the reporting would fall out of it, and the old ledger's batch corrections made audit trails hard to reconstruct. The VP chose an adapter on the existing ledger. Her reasoning was that a rebuild put a regulatory date at risk, and missing that date had consequences far beyond engineering. I made my case once more with an estimate, she held her decision, and I committed.
>
> Committing meant making her plan succeed, so I took the riskiest piece myself. The adapter's weak point was exactly what I'd worried about: batch corrections that rewrote history. I designed a reconciliation harness that compared adapter output against an independent recomputation every night, and I turned my rebuild concerns into three tracked risks with tripwires the VP agreed to. One of them was: if reconciliation breaks exceed 0.01% of volume for two weeks, we revisit the architecture.
>
> We shipped on the regulatory date. Four months later the tripwire fired during a holiday peak. Because the criteria were agreed in advance, there was no argument, and no 'I told you so': the revisit happened in a week, with data. The rebuild was funded as a planned program, and the adapter kept running through it.
>
> What I learned was about my own judgment. I had weighted architectural cleanliness above regulatory risk, and she was right about the order of operations. The rebuild was better as a second step, informed by four months of real reconciliation data, than as a first step under a deadline."

**What the committee extracts:** a real disagreement with a senior decider; committed wholly; took the hardest part; converted objections into owned mitigations and agreed tripwires; no re-litigation; when the risk landed, the mechanism handled it; learned something specific about own judgment. **Textbook L7 Disagree and Commit.**

### 6.4 Think Big with Frugality and Bias for Action (composite: seller tooling consolidation)

**The facts:** sellers use five separate internal tools to manage listings, inventory, pricing, promotions and returns; each has its own team; seller support contacts are rising.

#### How an L5 tells it

> "I proposed a unified seller platform to replace the five tools. I wrote a long vision doc with a target architecture and a two-year roadmap and presented it to leadership. They liked it, but it needed twelve engineers, and they couldn't fund it that year. I still think it's the right direction."

**What the committee extracts:** a big idea with no first step and no funding path. **Ivory tower; L5 or a Think Big concern.**

#### How an L7 tells it

> "Seller support contacts were growing faster than sellers, and when I traced the top contact reasons, 40% came from sellers being unable to see across our five tools. A price change in one didn't show up in the promotions tool for hours. The end state I proposed was one seller workspace on shared listing data, with the five tools becoming views over it.
>
> I didn't ask for a twelve-person team. The first phase was a read-only cross-tool view of a seller's listing state, built by two engineers in six weeks on data the tools already published. That addressed the top contact reason directly, so it was a support-cost project before it was a platform.
>
> Phase one cut contacts in that category by 30% in the first month. That bought the credibility for phase two, and I funded it by retiring the promotions tool's separate data store, which was costing $X K a month, into the shared model. The irreversible step, making the shared model the system of record for writes, I held back until two tools had run on it read-only for a quarter.
>
> Eighteen months in, four of the five tools are views over the shared model, total contacts per seller are down 35%, and we run two fewer databases than when we started. The first phase paid for the second."

**What the committee extracts:** bold end state tied to a customer metric; tiny, fast first proof point; self-funding phases (Frugality); held the one-way door back (Bias for Action applied correctly). **Think Big without the ivory tower.**

### 6.5 Earn Trust and Earth's Best Employer (composite: on-call burnout caused by your own design)

**The facts:** a notification platform the candidate designed two years earlier is now the top source of out-of-hours pages for three downstream teams.

#### How an L5 tells it

> "Some teams were getting a lot of pages from the notification platform. I worked on reducing alert noise and tuned thresholds, and the number of pages went down. The teams were happier afterwards."

**What the committee extracts:** a good fix, no ownership of the cause, no mechanism. **L5.**

#### How an L7 tells it

> "Two years after I designed our notification platform, it had become the top source of out-of-hours pages for three downstream teams. Their engineers were averaging eleven pages a week on call, and two had left citing on-call. The root cause was a choice I'd made: retrying failed sends synchronously, which turned any provider slowdown into a cascade into their services.
>
> I said that plainly at the engineering all-hands: the design was mine, and the pages were a consequence of it. Then I fixed the cause, not the symptom. I moved retries to a queue with per-provider circuit breakers, so a provider slowdown now degrades delivery latency instead of paging anyone.
>
> The cause was mine, but the pattern was the org's: nothing stopped any team from exporting its failures onto someone else's pager. I proposed a page budget per service, agreed with the directors: any team whose service generates more than two out-of-hours pages per on-call week, for itself or for others, gets reliability work prioritized ahead of features the next sprint.
>
> Within two quarters median out-of-hours pages fell from eleven a week to three across the org, and on-call stopped appearing in exit interviews. The page budget is still in the operational-readiness checklist, and the downstream TL who'd been loudest about the pages now co-chairs the review that enforces it."

**What the committee extracts:** vocally self-critical in public; fixed the cause; turned a personal fix into an org mechanism for engineer well-being; rebuilt a damaged relationship. **Earn Trust and Earth's Best Employer at L7.**

---

## 7. Adversarial Bar-Raiser Follow-Up Chains

### Chain A · "What did *you* do?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "You said 'we' several times. What was your role, specifically?" | Isolation | "I was the tech lead" (a title, not an action) | "I chose the split, wrote the sequence, built the cutover tooling, and owned go/no-go." |
| 2 | "Who wrote the design?" | Authorship | "The team" | "I did. Two TLs reviewed it; the dispatcher section changed after Raj's review." |
| 3 | "Which part was hardest, and who did it?" | Honesty about credit | Claims it, then can't detail it | "The comparator's diffing engine. Priya built it; I defined what 'equivalent routing' meant." |
| 4 | "What would have happened differently without you?" | Counterfactual | "It'd have been slower" | "The default plan split by team. The cross-type outage risk would have stayed." |
| 5 | "Tell me about one decision you got wrong in it." | Self-criticism | "None really" | A specific misjudgement and its cost |

### Chain B · Backbone: "How did you know you were right?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What was the director's strongest argument?" | Steelmanning | Dismisses it | "We'd lost $X M in a month; doing nothing wasn't an option." |
| 2 | "Why didn't you just escalate?" | Influence choice | "I did" or "I didn't want to" | "Escalation after a loss looks like protecting my metric. Data from her own model was more persuasive." |
| 3 | "What if the shadow data had gone the other way?" | Intellectual honesty | "It wouldn't have" | "Then synchronous was right and I'd have shipped it, optimizing the latency of the model call." |
| 4 | "What did you concede?" | Real negotiation | Nothing | "Gift cards. She was right." |
| 5 | "How did she feel afterwards?" | Earn Trust | "Fine" | "She presented it at the risk council as her standard. That was the point." |

### Chain C · Disagree and Commit: "Did you really commit?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What did committing look like day to day?" | Active vs passive | "I did my tasks" | "I took the riskiest piece, the reconciliation harness." |
| 2 | "Did you raise it again after the decision?" | Re-litigation | "A few times" | "Once, with an estimate, before it was final. After that, only through the agreed tripwires." |
| 3 | "When the problems came, what did you say?" | "I told you so" | Some version of it | "Nothing about the original argument. The tripwire triggered the agreed revisit." |
| 4 | "Was the VP right?" | Self-awareness | "No" | "About the order, yes. The rebuild was better second." |
| 5 | "Where would you not commit?" | Ethical line | "I always commit" | "Safety, legal, security, ethics. Those I escalate, and I'd say so openly." |

### Chain D · Think Big: "Who paid for it?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What did the first phase cost?" | Frugality | "We got a team" | "Two engineers, six weeks, existing data." |
| 2 | "What would you have done if phase one failed?" | Reversibility | "It wouldn't" | "Stopped. It was read-only; nothing depended on it." |
| 3 | "Which decision was irreversible, and when did you make it?" | One-way doors | Can't identify one | "System of record for writes, a quarter after read-only proved out." |
| 4 | "What did you turn off?" | Simplify | Nothing | "The promotions data store, and later two databases." |

### Chain E · Are Right, A Lot: "When were you wrong?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What was your initial instinct?" | Honest prior | Retrofits | States it, including if it was wrong |
| 2 | "How did you try to prove yourself wrong?" | Disconfirmation | "I asked the team" | A pre-mortem, a dissenting reviewer, an experiment designed to fail |
| 3 | "What would have made you stop?" | Kill criteria | None | Pre-set thresholds |
| 4 | "Give me a big call you got wrong." | Track record | A small one | A significant bet, the cost, and the reversal |
| 5 | "What do you do differently because of it?" | Learning | Generic | A specific change in how you decide |

### Chain F · Earn Trust and Earth's Best Employer

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Whose fault was the paging problem?" | Ownership of cause | Points elsewhere | "Mine. The synchronous retry was my design." |
| 2 | "Did anyone outside your team hear you say that?" | Vocally self-critical | No | "The all-hands, and the downstream TLs one to one first." |
| 3 | "Why a mechanism rather than just fixing your system?" | L7 leverage | "Mine was fixed" | "Nothing stopped the next team doing the same thing to someone else." |
| 4 | "How did you know engineers were better off?" | Measurement | "They said so" | Pages per on-call week, exit-interview themes, rotation volunteer rate |

---

## 8. Building your Amazon story set

1. **Map stories to LPs, two per heavily probed LP.** Interviewers often ask "give me another example". At L6/L7 the most probed are Ownership, Are Right A Lot, Backbone/D&C, Deliver Results, Dive Deep, Earn Trust, Think Big and Hire and Develop. Folder 08's matrix maps eight stories to all sixteen.
2. **Each story carries three or four LPs, but leads with one.** Re-weight the opening sentence for the LP being asked about.
3. **Recency matters.** ⚠ Amazon interviewers commonly prefer stories from the last two or three years; older ones need a reason.
4. **Keep the Backbone and D&C stories separate.** One story that does both ("I disagreed, then committed, then it turned out I was right") reads as neither.
5. **Have one story where you were wrong in public.** It serves Earn Trust, Are Right A Lot and Learn and Be Curious at once.

## 9. Checklist

- [ ] Every story separates team outcome, my decisions, my actions and named credit.
- [ ] One technical zoom-in per story that shows you as an exemplary practitioner.
- [ ] Backbone story against someone *senior*, won with data or a prototype, with a concession.
- [ ] A separate Disagree-and-Commit story where you lost, took the hardest part, and set tripwires instead of re-litigating.
- [ ] A Think Big story whose first phase is small, fast and self-funding.
- [ ] An Earth's Best Employer mechanism (on-call, growth, inclusion) with a metric.
- [ ] At least one story where you were publicly wrong.
- [ ] No disparagement of "legacy" or former colleagues (Respect what came before).

## 10. References

- Amazon, *Leadership Principles*. <https://www.amazon.jobs/content/en/our-workplace/leadership-principles>
- Amazon, *Principal Engineering Community Tenets*. <https://www.amazon.jobs/content/en/teams/principal-engineering/tenets>
- Jeff Bezos, *2016 Letter to Shareholders* ("disagree and commit"; deciding with about 70% of the information). <https://www.aboutamazon.com/news/company-news/2016-letter-to-shareholders>
- Colin Bryar and Bill Carr, *Working Backwards* (St. Martin's Press, 2021): the Bar Raiser process, six-pagers, PR/FAQ, input metrics and mechanisms from the inside.
- In this KB: [01.1 Scope detection](../01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md) · [01.3 Storytelling architecture](../01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/03-beyond-star-the-l7-executive-storytelling-architecture.md) · [02.2 Google and Meta](02-google-gnl-and-meta-jedi-conflict-direction-and-ambiguity.md) · [02.3 Netflix, Stripe, Apple](03-netflix-keeper-test-stripe-users-first-and-apple-dri-culture.md)
