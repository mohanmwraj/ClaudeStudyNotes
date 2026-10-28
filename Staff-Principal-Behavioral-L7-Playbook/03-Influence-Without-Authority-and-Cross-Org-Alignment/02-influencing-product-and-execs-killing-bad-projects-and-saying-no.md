# 03.2 · Influencing Product and Executives: Killing Bad Projects and Saying No

> **Folder 03 · File 2 of 3.** At L5, "pushing back" means negotiating scope with a product manager. At L7 it means **changing what a VP funds**, sometimes stopping a project an executive started, without the authority to do either. That's why "tell me about a time you said no to a senior leader" and "tell me about a project you stopped" are standard senior prompts: they measure whether your judgment reaches the level where money and strategy are decided.
>
> This file covers:
> - how executives actually decide, and how to package engineering judgment for them;
> - pre-wiring, the "no surprises" rule and disagreeing with a VP in the room;
> - the "no" menu: six ways to say no that keep you in the conversation;
> - killing a bad project: detecting it, the kill memo, timing, and protecting the people;
> - influencing product roadmaps with engineering evidence;
> - a rubric, three story blueprints and five follow-up chains.
>
> Stories are **illustrative composites**.

---

## 1. How executives decide

A director or VP makes many decisions a week, with partial context, on behalf of an organization larger than they can see. What they need from a senior engineer is not a design. It's a **decision they can make quickly and defend later**.

| What executives weigh | What that means for how you present |
|---|---|
| **Risk** (to revenue, customers, compliance, reputation) | Lead with the risk you see, sized, with a range |
| **Money and capacity** (headcount, quarters, cost) | Translate engineering effort into capacity and opportunity cost |
| **Time** (commitments made to their own leadership) | Know what they've promised upward, and what your proposal does to it |
| **Strategy** (what the org is trying to become) | Connect the decision to a goal they already own |
| **Their own credibility** | Never make them reverse themselves in public; give them a way to change course on new information |

### 1.1 The executive brief

Whatever the medium (a six-pager, a slide, a hallway conversation), the shape is the same:
1. **The decision needed**, and by when.
2. **The recommendation**, in one sentence.
3. **Why**, in terms of the table above: risk, money, time, strategy.
4. **The alternatives**, including "do nothing", each with its cost.
5. **What you need from them**, specifically.
6. **What would change your recommendation.**

The first two lines must work alone. Many executives decide on them and read the rest only if the recommendation surprises them.

### 1.2 Pre-wiring and "no surprises"

- **Pre-wire every significant meeting.** Meet the key people one to one beforehand, especially anyone whose plan your proposal changes. A VP who first hears in a group meeting that their project is at risk will defend it, because they must.
- **No surprises.** If your analysis will embarrass someone's plan, they hear it from you first, privately, with time to shape the response.
- **Disagreeing with a VP in the room:** state the disagreement once, with data, as a question of risk rather than of their judgment ("I'm worried we'd be taking on X; here's the number"), then offer to take it offline. Repeating it in the room turns a decision into a contest.

---

## 2. The "no" menu

"No" on its own ends your influence: the requester routes around you. An L7 "no" always keeps a path open. Six forms, roughly from softest to hardest:

| Form | What you say | When to use it |
|---|---|---|
| **Yes, if** | "Yes, if we drop X or move Y to next quarter." | Capacity is the constraint, and the trade-off is theirs to make |
| **Yes, but smaller** | "We can do the part that delivers most of the value by the date." | The date is real but the scope isn't |
| **Not now** | "Yes, after Z lands, in Q3, because Z is a prerequisite." | Sequencing is the issue |
| **Not this way** | "The goal is right; this design would cost us A. Here's a design that meets the goal." | The goal is sound, the solution isn't |
| **Not us** | "This belongs with team T, who have the context; I'll make the introduction." | Ownership is wrong |
| **No, and here's why** | "We shouldn't do this. Here's the risk, sized, and what I'd do instead." | Safety, legal, ethical issues, or a clear loss |

The interviewer's follow-up is always "what did you offer instead?" A no without an alternative is a down-level signal at senior levels.

---

## 3. Killing a bad project

### 3.1 Why bad projects survive

| Force | How it keeps a project alive |
|---|---|
| **Sunk cost** | "We've invested nine months; we're nearly there." |
| **Sponsor identity** | The executive who started it is publicly associated with it |
| **Moving goalposts** | Success criteria change as each milestone is missed |
| **Team identity** | People's promotion cases depend on it |
| **No kill criteria** | Nobody wrote down, at the start, what would make it stop |
| **Asymmetric reporting** | Status reports say green until they say red |

### 3.2 Detecting it

Signals that a project should be stopped or reshaped:
- the problem it solves has changed or disappeared;
- a cheaper path to the same outcome now exists (often a managed service or an adjacent team's system);
- the leading indicators have missed for several cycles while the plan stays the same;
- the cost to finish has grown past the value;
- the team can't articulate who will use it, or the intended users have built around it.

### 3.3 The kill memo

A strong kill recommendation is a document, not a hallway opinion. Its structure:
1. **What the project set out to do**, in its own original terms, and its sponsor's reasons, stated fairly.
2. **What has changed** since it started.
3. **Cost to finish** vs **value remaining**, honestly estimated (sunk cost excluded, by name).
4. **Alternatives**, including "continue as planned", "reshape" and "stop".
5. **What is salvageable**: components, learnings, people's expertise.
6. **The people plan**: where the team goes, and how their work is credited.
7. **A recommendation**, and what would change it.

### 3.4 Timing and the sponsor

- **Go to the sponsor first**, privately, with the memo. Give them the chance to make the call themselves. A sponsor who stops their own project on new evidence looks good; one who is overruled looks bad and will resist.
- **Frame it as new information**, not as an error in the original decision. Usually that's true: the project made sense with what was known at the time.
- **Don't wait for perfect evidence.** Every month of delay is cost. Present the kill case when the evidence is strong enough to be worth a decision.

### 3.5 Protecting the people

Killing a project badly destroys trust for years. At L7, the people plan is part of the recommendation:
- the team's engineers get their next work **before** the announcement, ideally work that uses what they learned;
- their work is credited publicly and specifically, in the announcement and in their reviews;
- promotion cases built on the project are reframed around what was learned and salvaged;
- nobody is blamed. The project was a reasonable bet that the facts moved against.

---

## 4. Influencing product roadmaps

Product managers and engineering leaders trade capacity for outcomes. Engineering influence on a roadmap works when it's expressed in **their** currency:

| Engineering concern | Expressed as a product trade-off |
|---|---|
| "This system is fragile" | "Incidents in this system cost N hours of team capacity a quarter and K customer-impacting minutes; fixing it returns that capacity in two quarters." |
| "This will be slow to build on" | "Each new feature here takes about 3× longer than it should; the next four roadmap items cost X weeks more on the current base than on a fixed one." |
| "We need to migrate" | "The old platform's end of support in Q4 creates a compliance gap for the enterprise deal; migrating removes the blocker." |
| "This design won't scale" | "At the projected growth, we cross the latency SLA in month seven; here's the revenue tied to that SLA." |

The L7 move is to **change the roadmap without a fight**: when the trade-off is framed in shared terms, product leaders often choose the engineering option themselves.

---

## 5. Hiring Committee Scoring Rubric

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | No hire |
|---|---|---|---|---|
| **Altitude** | Changed what a VP or director funded or stopped | Changed a cross-team roadmap | Negotiated scope with a PM | Complied, then complained |
| **Framing** | Risk, money, time and strategy, sized, in executive terms | Clear trade-off with numbers | Technical argument only | Opinion |
| **Saying no** | A no with a better alternative; requester chose it | Negotiated a reduced scope | "Pushed back" without an alternative | Refused, or never refused anything |
| **Killing a project** | Wrote the kill memo; sponsor made the call; salvage and people plans; costs saved | Recommended stopping with evidence | Raised doubts | Watched it fail |
| **Sponsor handling** | Pre-wired privately; sponsor kept their credibility and became an ally | Respectful escalation | Surprised people in meetings | Embarrassed a leader |
| **People** | Team redeployed and credited before the announcement | Considered the team | Not mentioned | Blamed the team |
| **Courage** | Challenged a senior leader's own project, at personal risk | Challenged a peer's | Challenged within own team | Never disagreed upward |

---

## 6. Story Blueprints

### 6.1 Killing a bad project (composite: an in-house vector search engine)

**The facts (composite):**
- A director launched an in-house vector search engine nine months ago to power product recommendations and semantic search.
- It's four months behind, with six engineers.
- Since it started, the company's managed database vendor has shipped a vector index that meets most requirements.
- The candidate is a principal in the adjacent platform org.

#### How an L5 tells it

> "Our org was building a custom vector search engine, and I thought it was a waste because the managed database had added vector search. I brought it up in a few architecture reviews and showed some benchmarks. Eventually leadership cancelled the project, and the team moved to other work. We switched to the managed option, and it worked fine."

**What the committee extracts:** raised doubts in public forums; no ownership of the decision; no sponsor handling; no people plan; no numbers. **L5.**

#### How an L7 tells it

> "Nine months into our in-house vector search engine, it was four months behind with six engineers on it. Meanwhile, our managed database vendor had shipped a vector index. Nobody had re-asked the original question, because the project had a director sponsoring it and a team whose promotions depended on it.
>
> I spent two weeks on evidence before saying anything. I ran our real recommendation queries against the managed index: it met recall and latency targets for 85% of our use cases. The other 15%, very-high-dimension embeddings for image search, it couldn't handle yet. I estimated the cost to finish the in-house engine at roughly two more quarters of six engineers, with significant ongoing operational cost, against near-zero to adopt the managed index for the 85%.
>
> I took a kill memo to the director privately first, not to the architecture review. It started with why she'd launched the project, which had been the right call nine months earlier, when no managed option existed. It recommended reshaping rather than stopping outright: move the 85% to the managed index now, and keep a two-person team on a narrow image-search engine, because that was the part the vendor couldn't do and our team had real expertise in.
>
> She pushed back hard on one point: the vendor's roadmap. She was right that depending on one vendor for search was a strategic risk. I added an abstraction layer over the index API and a quarterly review of the build-versus-buy question. She took the recommendation to her VP herself, as her decision.
>
> Before any announcement, I worked with her to place the four engineers coming off the project. Two joined the image-search team; two went to the recommendations team, where their indexing expertise made the migration faster. Their design work was credited by name in the announcement.
>
> We saved about two quarters of six engineers and the operational burden of a second datastore. The 85% migration took six weeks, and the image-search engine shipped the next quarter. A year later, the vendor added high-dimension support and we retired the image engine too, through the quarterly review we'd set up. One of the engineers led that migration."

**What the committee extracts:** found it unprompted; evidence before opinion; sized cost to finish against value; reshape rather than stop; the sponsor heard first and made the call; accepted the sponsor's valid concern; a people plan before the announcement; credit; a review mechanism that later retired the remainder. **Strong L7.**

### 6.2 Saying no to an executive request (composite: the six-week conference demo)

**The facts (composite):** the CEO wants a real-time personalized homepage live for a major industry conference in six weeks. A full implementation is a two-quarter effort touching four teams.

#### How an L5 tells it

> "Our CEO wanted a real-time personalized homepage for a conference in six weeks. I knew it wasn't possible, so I told my director it would take at least two quarters. We worked crazy hours and got a basic version ready, but it had some stability issues during the event."

**What the committee extracts:** a "no" that wasn't heard, followed by a heroic, risky partial yes. No alternative was proposed. **L5, with a judgment concern.**

#### How an L7 tells it

> "Our CEO wanted a real-time personalized homepage live for an industry conference in six weeks. The full system was a two-quarter, four-team effort: streaming features, a new ranking service, and a homepage rewrite. Building it in six weeks would have meant skipping the load testing and the rollback path on our highest-traffic page.
>
> Before saying anything, I asked his chief of staff what the conference moment actually needed. It was a keynote demo, plus the press being able to try it, not all hundred million users. That changed the problem.
>
> I wrote a one-page brief for my VP to take to him. It offered a yes, but smaller: personalization for a press-and-attendee cohort, served from the existing batch features refreshed hourly, behind a feature flag on a separate rendering path. It would look the same in the demo and carry no risk to the main homepage. The real-time system would follow on its original two-quarter plan, with the demo cohort as its first users.
>
> I was explicit about what we wouldn't do: no change to the main homepage's serving path before the conference, because a failure there during the press week would be far worse than a later launch.
>
> The CEO took the scoped version. It shipped in five weeks with two engineers, the demo ran with zero incidents, and the attendee cohort's engagement data from the conference gave us the first evidence for the real-time ranking model, which shipped on plan. The flag-based cohort launch became our standard pattern for executive demos."

**What the committee extracts:** found the real need behind the request; a "yes, but smaller" that met it; named the line they wouldn't cross and why; packaged it for the VP to carry; the demo became an asset for the full plan; a reusable pattern. **L7.**

### 6.3 Changing a product roadmap with engineering evidence (composite: checkout reliability vs a loyalty feature)

**The facts (composite):** the product org wants to spend the next quarter on a loyalty feature. The candidate believes checkout's retry behaviour causes duplicate charges and abandoned carts at a meaningful rate.

#### How an L5 tells it

> "I thought we had too much tech debt in checkout, and I kept raising it in planning, but product always prioritized features. Finally, after an incident, we got a sprint to work on it. It helped, but we still have a lot of debt."

**What the committee extracts:** tech debt framed in engineering terms; no influence until an incident forced it. **L5.**

#### How an L7 tells it

> "Product was planning a quarter on a loyalty feature, and I believed checkout's retry logic was costing more than loyalty would earn. Calling it tech debt had never moved anyone, so I measured it in their currency.
>
> I joined payment logs with session data and found that retries during provider timeouts caused duplicate-charge holds on about 0.4% of orders, and that customers who saw one abandoned 35% of the time. Our analyst validated the method. That was roughly $X M a year, against the loyalty feature's projected $Y M, which was smaller, and slower to arrive.
>
> I took it to the product director one to one first, framed as 'here's revenue we're losing that loyalty won't get back', not as 'engineering wants a quarter'. She asked a fair question: could we do both? We could do both if the checkout fix came first, because the loyalty feature added a new payment-adjacent flow, which would have built on the same retry logic.
>
> She moved loyalty a quarter later and presented the sequencing to her VP as her plan. We made checkout retries idempotent, keyed on a client-generated intent ID, in six weeks. Duplicate holds fell to near zero and abandonment in that cohort returned to baseline. Loyalty launched the next quarter on the fixed flow. Product now asks for a reliability-cost estimate on any roadmap item that touches payments."

**What the committee extracts:** translated an engineering concern into revenue; validated the analysis; pre-wired privately; answered "both?" with a sequencing argument; the product leader owned the change; a mechanism. **L7.**

---

## 7. Adversarial Bar-Raiser Follow-Up Chains

### Chain A · "Why did you think you were right?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What did the sponsor know that you didn't?" | Humility | "Nothing" | The vendor-roadmap risk |
| 2 | "How did you validate the 85%?" | Rigor | "Benchmarks" | Real queries, recall and latency thresholds, who reviewed it |
| 3 | "What if the vendor hadn't shipped?" | Counterfactual | Unsure | "The in-house engine was the right call; I'd have argued for finishing it" |
| 4 | "Was the original decision a mistake?" | Fairness | "Yes" | "No. It was right with what was known nine months earlier" |

### Chain B · The sponsor

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Who heard it first?" | Pre-wiring | "The architecture review" | "The director, privately, with the memo" |
| 2 | "How did she react?" | Honesty | "She agreed" | Her real objection, and how it changed the plan |
| 3 | "Who made the decision?" | Ownership dynamics | "I did" | "She did, and took it to her VP" |
| 4 | "What's your relationship with her now?" | Earn Trust | Unclear | Evidence of later trust |

### Chain C · The people

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What happened to the six engineers?" | Care | "They moved on" | Each placement, decided before the announcement |
| 2 | "How did they feel?" | Empathy | "Fine" | The honest reaction, and what was done about it |
| 3 | "How was their work credited?" | Credit | Not considered | Named in the announcement; reframed in reviews |
| 4 | "Would they work with you again?" | Trust | Unsure | Evidence: one led the later migration |

### Chain D · Saying no: "What did you offer instead?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What did the CEO actually need?" | Discovery | "The feature" | "A keynote demo and press access" |
| 2 | "How did you find that out?" | Method | Assumed | Asked the chief of staff |
| 3 | "What line would you not cross?" | Judgment | None | No change to the main serving path pre-conference |
| 4 | "What if he'd insisted on the full thing?" | Backbone | "We'd have done it" | "I'd have said what we'd be risking, in writing, and asked for the risk to be accepted at his level" |
| 5 | "What came of the demo?" | Leverage | Nothing | The first data for the real model; a reusable pattern |

### Chain E · Roadmap influence

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "How did you get the dollar figure?" | Business translation | Estimated | The join, the method and the analyst's validation |
| 2 | "Why hadn't it been prioritized before?" | Insight | "Product doesn't value tech debt" | "We'd described it in our terms, not theirs" |
| 3 | "Who changed the roadmap?" | Influence | "I did" | "The product director, after one conversation" |
| 4 | "What stops this needing a fight next time?" | Mechanism | Nothing | Reliability-cost estimate on payment-touching items |

---

## 8. Checklist

- [ ] One story where you changed what a director or VP funded, or stopped.
- [ ] One story where you said no to a senior request with an alternative the requester chose.
- [ ] Your kill story includes: evidence first, the sponsor heard it first and made the call, salvage, a people plan before the announcement.
- [ ] Every engineering concern in your stories is translated into risk, money, time or strategy.
- [ ] You can name what the senior leader was right about.
- [ ] Each story ends with a mechanism that makes the next such decision easier.

## 9. References

- Barbara Minto, *The Pyramid Principle* (1987): answer first, then reasons. The basis of the executive brief in §1.1.
- Jeff Bezos, *2016 Letter to Shareholders*: high-velocity decisions, and recognizing and correcting bad decisions quickly. <https://www.aboutamazon.com/news/company-news/2016-letter-to-shareholders>
- Annie Duke, *Quit: The Power of Knowing When to Walk Away* (Portfolio, 2022): kill criteria, sunk cost and the psychology of stopping.
- In this KB: [01.3 The headline beat](../01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/03-beyond-star-the-l7-executive-storytelling-architecture.md) · [03.1 Architectural wars](01-resolving-architectural-wars-between-competing-principal-engineers.md) · [03.3 Migrations without mandates](03-driving-multi-team-migrations-and-adoption-without-mandates.md) · Folder 04 covers tech-debt trade-offs and reliability freezes in depth.
