# 04.1 · Identifying Unasked Existential Problems and Writing Six-Page RFCs

> **Folder 04 · File 1 of 3.** The clearest single difference between L6 and L7 is **problem origin** (01.1 §3). An L6 solves a hard cross-team problem well. An L7 finds the problem **before anyone asked**: the scaling cliff eighteen months out, the regulation that invalidates the architecture, the cost curve that will eat the margin. Then they write the document that makes leadership act on it.
>
> "Tell me about a problem you identified that nobody else saw" is therefore one of the highest-yield prompts in a senior loop. This file covers:
> - what makes a problem "existential" and why nobody owns it;
> - eight techniques for finding one;
> - sizing it honestly with ranges;
> - getting attention for an unasked problem;
> - the six-page RFC or narrative: structure, failure modes, and the review process;
> - a rubric, two story blueprints and five follow-up chains.
>
> Stories are **illustrative composites**.

---

## 1. What makes a problem existential, and unowned

Larson's guide *Work on what matters* lists "existential issues" first among the places a Staff engineer should spend their time. An existential problem threatens a business goal, not just a system. They tend to have three properties:

| Property | Why it means nobody owns it |
|---|---|
| **It's between teams** | Each team's system looks fine against its own roadmap. The failure is in the interaction or the aggregate. |
| **It's beyond the planning horizon** | Quarterly planning doesn't see a cliff that arrives in month 15. |
| **It's outside engineering's usual inputs** | It comes from a contract, a regulation, a pricing change, or a strategy slide engineers don't read. |

### 1.1 The common shapes

| Shape | Example |
|---|---|
| **Scaling cliff** | Event volume will grow 10× with a planned launch; current pipelines breach an SLA at 3× |
| **Cost curve** | Infrastructure cost per order grows faster than revenue per order; margin goes negative within six quarters |
| **Strategic mismatch** | Strategy says "EU enterprise next year"; all customer data lives in one US region |
| **Compliance horizon** | A regulation coming into force in 18 months requires capabilities the architecture can't provide |
| **Dependency risk** | A vendor's end of life, a single supplier, a library with no maintainer |
| **Concentration risk** | One database, one region, one person, one team on the critical path for everything |
| **Security debt** | Credentials or authorization models that won't survive a determined attacker or an audit |
| **Silent data decay** | A data-quality problem that slowly corrupts decisions or models |

---

## 2. Eight techniques for finding one

None of these require permission. All of them are things an L7 does as routine:

1. **Extrapolate the curves.** Take growth projections from the business plan and multiply by unit costs and capacity limits. Where do the lines cross?
2. **Read the strategy and ask "what must be true?"** For each strategic goal, write what the technology must be able to do, and check whether it can.
3. **Cluster incidents across teams.** One team's incidents look like bad luck; the same root cause across five teams is a systemic problem.
4. **Follow the money.** Read the cloud bill by service and by unit (cost per request, per customer, per order). The fastest-growing line items are usually unowned.
5. **Talk to people outside engineering.** Sales knows which deals are stalling on technical requirements. Support knows which defects cost the most contacts. Finance knows which costs worry the CFO.
6. **Keep an end-of-life calendar.** Runtime versions, vendor contracts, certificates, hardware leases.
7. **Run a pre-mortem on the company's plan.** "It's two years from now and the plan failed because of technology. Why?"
8. **Notice the question nobody asked.** In planning reviews, listen for the assumption every plan depends on and none of them examines.

---

## 3. Sizing it honestly

A problem gets attention in proportion to how well it's sized. The sizing has four parts:

| Part | Question | Good form |
|---|---|---|
| **Exposure** | How bad, if it happens? | A range: "$4–9 M a year in penalties and refunds" |
| **Likelihood** | How likely, and what drives it? | "Near-certain if the launch happens on plan; the driver is seller count" |
| **Time to impact** | When does it bite? | "Month 11 to 15, depending on onboarding pace" |
| **Lead time to fix** | How long does a fix take? | "Three quarters, which is why it has to start now" |

The last two together make the argument: **when lead time to fix approaches time to impact, the problem is urgent even though nothing is broken yet.**

Use ranges, not point estimates. A range is honest about uncertainty and is harder to dismiss; a precise number invites an argument about the number instead of the risk.

---

## 4. Getting attention for an unasked problem

Unasked problems face a particular resistance: they imply someone missed something, and they compete with work that's already planned.

| Step | What you do |
|---|---|
| **1. Check it quietly** | Validate the analysis with one or two trusted people, including someone from finance or the business side, before going wide |
| **2. Find the owner of the goal at risk** | Not the owner of the systems. The VP whose launch, margin or market is threatened |
| **3. Frame it as their risk** | "Your EU launch has a dependency nobody's tracking", not "our architecture is wrong" |
| **4. Bring a path, not just a problem** | At least a sketch of options and the first step |
| **5. Ask for a specific decision** | "Two engineers for six weeks to validate the options", not "we should think about this" |
| **6. Write it down** | The six-page document (§5), which outlives the conversation |

Avoid two traps:
- **Cassandra:** being right, loudly, without a path. People stop listening.
- **The fire alarm:** framing everything as existential. You get one or two of these a year before you lose credibility, so keep them for problems that really are.

---

## 5. The six-page RFC or narrative

Amazon's six-page narrative, a prose memo read silently at the start of the meeting, is the best-known form of a general discipline: **the senior engineer's main instrument of influence is a document.** Bezos's 2017 shareholder letter describes how much work a good one takes, and why it's worth it. Whatever your company calls it (RFC, design doc, narrative, proposal), at L7 the document's job is to **get a decision**, not to describe a design.

### 5.1 Structure

| Section | Purpose | Length guide |
|---|---|---|
| **1. Summary and decision requested** | The recommendation and what you need, readable alone | Half a page |
| **2. Context and problem** | What's happening, with data; why now | One page |
| **3. Tenets or requirements** | The criteria the decision should satisfy, ordered | A short list |
| **4. Options** | At least three, including "do nothing", each with costs, risks and what it's good at | Two pages |
| **5. Recommendation** | Which option, why it best fits the tenets, and what you're giving up | Half a page |
| **6. Risks and mitigations** | The ways the recommendation could fail, and what you'll do | Half a page |
| **7. Plan and exit criteria** | Phases, the first proof point, and when you'd stop | Half a page |
| **8. Cost and capacity** | People, time, money; what it displaces | A short table |
| **Appendix: FAQ** | The hard questions, asked and answered in advance | As needed |

Add one line that most documents omit: **what would change our recommendation.** It tells the reader you've thought about being wrong, and it pre-agrees the conditions for revisiting.

### 5.2 Failure modes

| Failure | What the reader concludes |
|---|---|
| **Solution first** (the document opens with the design) | The author decided before analysing |
| **Strawman alternatives** (two obviously bad options next to the chosen one) | The comparison can't be trusted |
| **No "do nothing" option** | Hasn't sized the cost of inaction |
| **No cost section** | Hasn't thought about what it displaces |
| **Written for engineers when the decider is a VP** | The decider can't find the decision |
| **Too long** | The author couldn't decide what mattered |
| **Unreviewed by people who disagree** | The objections will come in the meeting, unprepared |

### 5.3 The review process

1. **Draft for yourself**: write the summary first; if you can't, you're not ready.
2. **Dissenters review first**: send it to the people most likely to disagree, and incorporate their strongest arguments.
3. **Business review**: someone from finance or product checks the sizing.
4. **Decision meeting**: the decider reads silently, then discusses.
5. **Record the decision**: what was decided, by whom, and what would reopen it.

---

## 6. Hiring Committee Scoring Rubric

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | No hire |
|---|---|---|---|---|
| **Problem origin** | Found an existential problem nobody had asked about, outside their own area | Found a cross-team problem | Worked on an assigned problem | Can't say where the problem came from |
| **Technique** | Can name how they found it (curves, strategy, incident clusters, money) | Noticed a pattern | Was told about it | No technique |
| **Sizing** | Exposure, likelihood, time to impact and lead time to fix, with ranges, validated by the business | Sized in technical terms | Not sized | Overstated |
| **Attention** | Framed as the goal owner's risk; brought a path; got a specific decision | Raised it with the right people | Raised it in team channels | Complained |
| **Document** | A decision document with real alternatives, cost and exit criteria; reviewed by dissenters first | A solid design doc | A description of the solution | No written artifact |
| **Outcome** | Leadership changed plans or funding; the risk was retired before it hit | Leadership acknowledged it | Partial action | Ignored |
| **Calibration** | Has raised few such alarms, and they were right; can name one that wasn't | Reasonable judgment | Untested | Raises everything as urgent |

---

## 7. Story Blueprints

### 7.1 Finding an existential problem (composite: EU data residency vs the enterprise strategy)

**The facts (composite):**
- The company's strategy for next year is "EU enterprise".
- All customer data lives in one US region.
- Sales has 30 enterprise deals in the pipeline.
- No one in engineering owns the question of where data lives.

#### How an L5 tells it

> "Our sales team started getting questions about EU data residency from enterprise customers. My manager asked me to look into what it would take. I researched the options and wrote up a proposal for deploying to an EU region. It got approved and we started the project the next quarter."

**What the committee extracts:** the problem arrived through sales and a manager; a solution proposal; no sizing; no framing. **L5.**

#### How an L7 tells it

> "Our strategy deck for the next year said 'EU enterprise'. When I read it, I asked a question nobody had asked: where would those customers' data live? All of it was in one US region, and every service assumed so: IDs, backups, analytics exports, even our support tooling.
>
> I spent a week with the sales operations lead going through the enterprise pipeline. Of 30 deals, 18 had data-residency requirements in their security questionnaires, and four had already stalled on them, though nobody had connected the stalls to architecture. Those 18 were about $X M of annual contract value, more than half the year's enterprise target.
>
> Then I sized the fix. Real residency meant regional cells with data partitioned by tenant home region, not just a second deployment, and I estimated three quarters for the first EU cell. The sales cycle for those deals was two to three quarters, so the lead time to fix was already longer than the time to impact. That made it urgent, although nothing was broken.
>
> I took it to the VP of Sales and the CTO together, framed as a risk to their joint target, with a six-page document. It compared three options: a standalone EU deployment, which was fast but would have forked the product; regional cells, the recommendation; and contractual workarounds, which our counsel said wouldn't survive two of the deals. It asked for one decision: fund a residency program now with eight engineers from two teams, and let sales commit EU residency dates to the four stalled deals.
>
> They funded it that week. The first EU cell went live in under three quarters, 14 of the 18 deals closed within the year, and the cell architecture later carried a second region in half the time. The thing I'd change: I found this from a strategy deck, by luck. I've since made 'what must be true technically' a standard section of our annual planning review, so the next one gets found on purpose."

**What the committee extracts:** found it from the strategy, unprompted; validated with sales data; sized exposure, time to impact and lead time to fix; framed as the leaders' risk; a decision document with real options and a specific ask; funded; outcome in revenue; a mechanism to find the next one. **Strong L7 problem origin.**

### 7.2 The document as the instrument (composite: a cost curve the org hadn't noticed)

**The facts (composite):** infrastructure cost per order has grown 30% a year for three years while revenue per order is flat. Each team's cost looks justified in isolation.

#### How an L5 tells it

> "I noticed our cloud costs were going up a lot. I wrote a design doc proposing that we move our batch jobs to spot instances and right-size our databases. I shared it with the team and we implemented most of it, which saved about 20% on our team's bill."

**What the committee extracts:** a good cost project for one team; document describes a solution. **L5.**

#### How an L7 tells it

> "I was reading our cloud bill by unit rather than by service, and found that infrastructure cost per order had grown 30% a year for three years while revenue per order was flat. Every team's growth was individually justified, so nobody saw the aggregate. At that rate, infrastructure would consume our whole contribution margin in about six quarters. I had finance check the projection, and they agreed with the shape, though their range was wider than mine.
>
> I wrote a six-page narrative for the CFO's staff and the VP of Engineering. It opened with the decision I wanted: set a cost-per-order target as an engineering-wide goal, and fund a six-month program to meet it. It compared three options:
> - an across-the-board cut, which finance favoured but which would have hit reliability work;
> - per-team budgets, which would have made the problem everyone's and so nobody's;
> - a unit-cost target with the three largest drivers fixed centrally.
>
> Before the meeting, I sent the draft to the two directors whose teams owned the largest drivers. One of them showed me that his storage growth came from a compliance retention rule, not from waste. I moved it out of the savings estimate and into a separate retention-policy question for legal, which made the document more credible, not less.
>
> In the meeting, the CFO's staff read it silently and asked two questions, both answered in the FAQ. They approved the target and the program. Over six months, cost per order fell 35%, mostly from three changes: tiered storage for order history, autoscaling on the recommendation service, and retiring a duplicate analytics pipeline. Cost per order is now a line on the engineering leadership dashboard, reviewed monthly, and the retention question resulted in a policy change that saved another 10% the following year."

**What the committee extracts:** found the aggregate in unit terms; validated with finance; a decision-first document with real alternatives; dissenters reviewed first, and the document improved because of it; a decider persuaded by the document; an org-level metric and a mechanism. **L7.**

---

## 8. Adversarial Bar-Raiser Follow-Up Chains

### Chain A · "How did you find it?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What first made you look?" | Origin | "Sales asked" or "my manager asked" | "The strategy deck said EU enterprise; I asked where the data would live" |
| 2 | "Why hadn't anyone else seen it?" | Insight into the vacuum | "They weren't paying attention" | Why it fell between owners and outside planning horizons |
| 3 | "What data confirmed it?" | Validation | "It was obvious" | The pipeline analysis with sales operations |
| 4 | "What else did you consider might be the real problem?" | Rigor | Nothing | Alternatives ruled out |
| 5 | "How do you find these routinely?" | Technique | Luck | Named techniques; a mechanism |

### Chain B · Sizing

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "How did you get the number?" | Method | Estimated | Source, method, who validated it |
| 2 | "What's the range?" | Honesty | A single figure | A range, and what drives its width |
| 3 | "Why was it urgent if nothing was broken?" | Lead-time insight | "It was big" | Lead time to fix vs time to impact |
| 4 | "What if you'd been wrong about the size?" | Calibration | Unsure | What the smaller case would have meant for the plan |

### Chain C · The document

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What was the first sentence?" | Decision orientation | Context | The decision requested |
| 2 | "What were the alternatives?" | Real options | Two strawmen | Three, each good at something, including do nothing |
| 3 | "Who reviewed it first?" | Dissent | "My team" | The directors most likely to disagree |
| 4 | "What changed because of their review?" | Openness | Nothing | The storage driver moved out of the savings |
| 5 | "What questions came in the meeting?" | Preparation | Many unexpected | Two, both in the FAQ |

### Chain D · Getting attention

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Who did you take it to, and why them?" | Targeting | "My manager" | The owner of the goal at risk |
| 2 | "What did you ask for?" | Specificity | "Awareness" | A specific decision with capacity attached |
| 3 | "What did it displace?" | Trade-off | Nothing | The work that moved |
| 4 | "How long from finding to funding?" | Velocity | Months | Weeks, and why |

### Chain E · Calibration: "How often are you wrong?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "How many problems like this have you raised?" | Fire-alarm risk | Many | A few, chosen |
| 2 | "Tell me about one that turned out not to matter." | Self-awareness | None | A specific false alarm, and what it taught |
| 3 | "How do you decide what's worth raising?" | Judgment | "Gut" | The exposure, likelihood and lead-time test |

---

## 9. Checklist

- [ ] One story where you found a problem nobody asked about, outside your own systems.
- [ ] You can name the technique you used to find it.
- [ ] Sizing: exposure, likelihood, time to impact and lead time to fix, with a range, validated by someone outside engineering.
- [ ] You took it to the owner of the goal at risk, framed as their risk, with a specific ask.
- [ ] You can describe the document: its first sentence, its alternatives, who reviewed it first and what changed.
- [ ] The outcome changed funding or plans, and the risk was retired before it hit.
- [ ] A mechanism to find the next one.

## 10. References

- Will Larson, "Work on what matters" (StaffEng guide): existential issues, and the traps of snacking, preening and chasing ghosts. <https://staffeng.com/guides/work-on-what-matters>
- Jeff Bezos, *2017 Letter to Shareholders* (on high standards and writing great six-page memos). <https://www.aboutamazon.com/news/company-news/2017-letter-to-shareholders>
- Colin Bryar and Bill Carr, *Working Backwards* (St. Martin's Press, 2021): the six-page narrative and PR/FAQ in practice.
- Gary Klein, "Performing a Project Premortem", *Harvard Business Review*, September 2007. <https://hbr.org/2007/09/performing-a-project-premortem>
- In this KB: [01.1 Problem origin as a scope dimension](../01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md) · [03.2 The executive brief](../03-Influence-Without-Authority-and-Cross-Org-Alignment/02-influencing-product-and-execs-killing-bad-projects-and-saying-no.md) · [04.2 One-way and two-way doors](02-one-way-vs-two-way-doors-deciding-with-70-percent-information.md)
