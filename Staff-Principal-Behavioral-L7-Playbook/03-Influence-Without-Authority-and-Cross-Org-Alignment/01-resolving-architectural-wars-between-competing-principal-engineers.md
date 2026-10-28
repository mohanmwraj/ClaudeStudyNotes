# 03.1 · Resolving Architectural Wars Between Competing Principal Engineers

> **Folder 03 · File 1 of 3.** The hardest conflicts at L7 are not with product managers or executives. They are with **other senior engineers who are as good as you**, have their own followings, and are proposing a design that's also defensible. These "architectural wars" stall whole orgs for quarters: design docs multiply, teams wait, and executives receive contradictory advice from people they trust equally.
>
> Interviewers ask about them because they separate influence from authority more sharply than any other story. Nobody can order a principal to concede. This file covers:
> - the anatomy of an architectural war and the five types of disagreement underneath it;
> - the resolution tool for each type;
> - decision rights, joint escalation, and designing the decision process rather than winning the decision;
> - two roles: when you are one of the combatants, and when you are the arbiter;
> - a rubric, two story blueprints and five follow-up chains.
>
> Vocabulary: C-T-O-A-R-L beats (01.3), the Technical Conflict Trap and competing valid priorities (02.2). Stories are **illustrative composites**.

---

## 1. Anatomy of an architectural war

A design disagreement becomes a war when it has these properties:

| Symptom | What it looks like |
|---|---|
| **Duplicated design work** | Two or three competing design docs for the same problem, each with its own reviewers |
| **Proxy fighting** | Reviews become debates in which junior engineers repeat their principal's arguments |
| **Stalled teams** | Downstream teams defer their own decisions "until the architecture is settled" |
| **Executive whiplash** | A VP hears "A is obviously right" and "B is obviously right" from people they trust |
| **Moving goalposts** | Each side adds requirements the other design doesn't meet |
| **Time** | It has gone on for longer than either design would take to prototype |

The last row is the tell. If the argument has lasted longer than the experiment that would settle it, the argument isn't about the facts.

### 1.1 Why it happens between principals specifically

Senior engineers are usually right about the part of the problem they see. The conflict comes from what they see differently, and from what's at stake for them:
- **Different vantage points.** A storage principal sees operational burden; an application principal sees developer velocity.
- **Prior bets.** One of them championed the current system, and a replacement reads as a verdict on their judgment.
- **Org interests.** The winning design usually decides which team owns the platform, and therefore headcount and scope.
- **Reputation.** A public loss is costly for someone whose influence depends on being right.

None of that makes either person unreasonable. An L7 answer treats these forces as **design inputs** of the resolution, not as character flaws.

---

## 2. The five kinds of disagreement, and the tool for each

Most wars are several disagreements tangled together. The first L7 move is to **untangle them**, because each kind has a different resolution tool, and using the wrong one makes things worse (more data never resolves an identity conflict).

| Kind | The question underneath | How to tell | Resolution tool |
|---|---|---|---|
| **Facts** | "What is true?" (latency, cost, failure rates, team skills) | Both sides cite numbers, and the numbers differ | A time-boxed experiment, prototype or bake-off with **pre-registered** success criteria |
| **Values** | "What matters most?" (consistency vs availability, velocity vs control) | Both accept the same facts but rank the outcomes differently | Agree the **decision criteria and their weights before scoring options**; escalate the weighting to the person who owns the business trade-off |
| **Scope** | "What problem are we solving?" | The designs solve different problems well | Split the problem; each design may be right for a different slice |
| **Interests** | "Who owns it?" (team, headcount, roadmap) | The argument tracks org lines | Separate the ownership decision from the design decision; agree ownership first, or explicitly afterwards |
| **Identity** | "Was I wrong?" (prior bets, reputation) | Arguments get personal, or one side defends the current system against all evidence | Off-ramps and shared authorship: let the other person own part of the outcome and the narrative |

### 2.1 Facts: experiments with pre-registered criteria

A bake-off only settles the question if both sides agree **in advance** what result means what. Otherwise the losing side challenges the methodology.

Write down before running anything:
- the workload (real traffic replay, not a synthetic benchmark either side designed);
- the metrics and their thresholds ("p99 multi-region write under 80 ms at 3× current peak");
- who runs it (ideally both teams, jointly);
- what happens on each outcome, including a split result.

### 2.2 Values: criteria before options

When the facts are agreed and the disagreement persists, it's about weights. The move is to **stop debating the designs and debate the criteria**, in a meeting with no design on the table:
1. List the criteria (durability, latency, operability, cost, migration risk, team skills, time to first value).
2. Agree a weight for each, or agree who decides the weights. Usually that's the business owner, not either engineer.
3. Only then score the designs.

This works because people defend their design, but few will argue that "operability matters more than durability for the payments ledger" once it's said out loud.

### 2.3 Interests and identity: change the structure, not the person

- **Separate ownership from design.** "Whichever design wins, the storage team owns the operational layer and the application team owns the client libraries." Once headcount isn't at stake, many arguments soften.
- **Shared authorship.** Give the other principal a piece of the outcome they genuinely own, ideally the part where their design was stronger.
- **Off-ramps.** A public reversal costs a principal more than a private one. Let new data be the reason for change, not a defeat: "the replay data changed the picture for both of us."

### 2.4 Joint escalation

Sometimes it can't be resolved between peers, and it should go to a decider. The L5 move is escalating **against** the other person. The L7 move is a **joint escalation**: one document, written together, with:
- the decision needed, and by when;
- the agreed facts;
- each position, **written by its owner**;
- the criteria and where the designs score differently;
- each side's strongest argument against their own design;
- a recommendation, or an honest "we disagree; here's what you're choosing between".

A decider who receives a joint document can decide in one meeting, and the losing side has had their best case put in their own words. That makes disagree-and-commit possible afterwards.

---

## 3. Decision rights: designing the process, not winning the decision

A recurring L7 insight: **many wars persist because nobody knows who decides.** Each principal believes they have a veto. The design debate is actually a decision-rights vacuum.

Common frameworks make decision rights explicit:
- **RAPID** (Bain): Recommend, Agree, Perform, Input, Decide.
- **DACI**: Driver, Approver, Contributors, Informed.
- **The Netflix informed captain** (02.3): one named decider who must farm dissent.
- **Amazon's single-threaded owner** ⚠: one leader fully dedicated to one initiative.

At L7, the evidence interviewers want is that **you noticed the vacuum and fixed it**, sometimes by making yourself the decider, often by getting someone else named.

| | L5 behaviour | L6 behaviour | L7 behaviour |
|---|---|---|---|
| **Who decides?** | Assumes their manager does | Asks who decides | Gets the decider named, and the criteria agreed, before the debate restarts |
| **The debate** | Argues for their design | Writes a comparison | Untangles facts, values, scope, interests and identity, and applies the right tool to each |
| **The decision** | Wins or loses | Reaches consensus | Designs a process both sides trust; the outcome sticks even for the side that lost |
| **Afterwards** | Moves on | Implements | Repairs the relationship, gives credit, records the decision and what would reopen it |

---

## 4. Two roles

### 4.1 When you're one of the combatants

Your credibility depends on behaving as if you might be wrong:
1. **Write the strongest version of the other design** before arguing against it, and send it to its owner for correction.
2. **Name what would change your mind**, specifically.
3. **Propose the experiment** that could prove you wrong, and let the other side co-design it.
4. **Pre-commit publicly** to the result.
5. If you win, **give the other principal the part they were right about**, with credit. If you lose, commit (02.1 §4.2).

### 4.2 When you're the arbiter

You've been asked, formally or informally, to settle a war between two other senior engineers:
1. **Meet each separately first.** Find their real requirement and what's at stake for them personally.
2. **Untangle the disagreement types** and tell both of them what you see: "You agree on the facts; you disagree on how much operability matters, and on who'd own the result."
3. **Fix decision rights.** If you're the decider, say so; if not, get one named.
4. **Run the right tool** for each type.
5. **Decide or recommend in writing**, citing both of their arguments.
6. **Protect the loser's standing**: credit their contributions in public, and give them a visible role in what comes next.

---

## 5. Hiring Committee Scoring Rubric

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | No hire |
|---|---|---|---|---|
| **Diagnosis** | Untangled facts, values, scope, interests and identity; named each explicitly | Recognized it wasn't purely technical | Treated it as a technical argument only | Treated it as the other person being difficult |
| **Steelmanning** | Wrote the other design's strongest version, and its owner agreed it was fair | Fairly summarized the other view | Partial or dismissive summary | Caricature |
| **Tools** | Pre-registered bake-off; criteria before options; ownership separated from design; joint escalation | A comparison doc and a review | Persuasion in meetings | Escalation against the other person; politics |
| **Decision rights** | Got a decider named and criteria agreed; designed a process both sides trusted | Clarified who decided | Assumed | Fought for a veto they didn't have |
| **Outcome** | Decision stuck; often a split or hybrid; the losing side committed and owns part of it | A clear decision, implemented | Their design won or lost | Unresolved, or resolved by attrition |
| **Relationship** | Stronger afterwards, with evidence (later collaboration, co-authorship) | Professional | Strained | Damaged |
| **Self-awareness** | Names where they were wrong or what they conceded | Some reflection | "I was right" | Blames |

**Most common down-level in this category:** the candidate's design won, the other principal "came around", and nothing is said about what the other principal was right about.

---

## 6. Story Blueprints

### 6.1 As a combatant (composite: distributed SQL vs sharded Postgres for global accounts)

**The facts (composite):**
- A company expanding to three regions needs a globally consistent account store.
- The candidate proposes adopting a distributed SQL database.
- Another principal, who designed the current Postgres sharding layer four years earlier, proposes extending it with cross-region replication.
- The debate has run for two months; four product teams are waiting.

#### How an L5 tells it

> "There was a big debate between me and another principal engineer about our database for multi-region. I wanted distributed SQL because it handles global consistency natively; he wanted to keep our sharded Postgres. I put together a detailed comparison doc showing that distributed SQL was better on consistency and operations. After a lot of meetings, leadership went with my recommendation, and he eventually came around."

**What the committee extracts:** their design won; the other principal "came around"; no account of what he was right about; resolution by leadership choosing a side. **L5 influence, with a steelmanning gap.**

#### How an L7 tells it

> "We were expanding to three regions, and four product teams were waiting on a decision about our account store. I'd proposed a distributed SQL database. Marcus, the principal who'd designed our Postgres sharding layer four years earlier, proposed extending it with cross-region replication. We'd argued for two months, and our VP had heard 'obviously A' and 'obviously B' from both of us.
>
> I stopped arguing and tried to work out what we actually disagreed about. When I wrote it down, there were three different disagreements.
> - **Facts:** we had different beliefs about cross-region write latency under our real workload.
> - **Values:** I weighted global consistency highest; he weighted operational familiarity, because his team had a decade of Postgres expertise and none in the new system.
> - **Scope:** most of our data was per-region and never needed global consistency. Only the identity and entitlement slice did, about 4% of tables.
>
> I wrote the strongest version of his design and sent it to him for correction before anyone else saw it. He added two points I'd missed, including a failure mode in my proposal around schema changes. Then we co-designed a bake-off on replayed production traffic, with thresholds we both signed in advance: multi-region write p99 under 80 ms at three times peak, failover under 30 seconds, and a schema change on a billion-row table without downtime.
>
> The results split. Distributed SQL won on global writes and failover, and lost on schema changes and operational cost for the per-region data. So the decision followed the scope: per-region data stayed on Marcus's sharded Postgres, with his replication plan for disaster recovery, and only the identity slice moved to distributed SQL. His team owned the Postgres tier and its tooling, and mine owned the identity service.
>
> We took one joint document to the VP, with both positions in our own words, and she approved the split in one meeting. All four teams were unblocked within a week. A year later, identity has had zero cross-region inconsistencies through two regional failovers, and per-region costs are about 40% below what full migration would have cost. Marcus and I co-presented the decision at the architecture forum. The part of the outcome I'm proudest of is that nobody describes it as either of our designs winning."

**What the committee extracts:** untangled three disagreement types; steelmanned and had it corrected by the opponent; accepted a flaw in own proposal; pre-registered bake-off co-designed; let the result and the scope split decide; separated ownership; joint escalation; relationship strengthened; business outcome. **Strong L7.**

### 6.2 As the arbiter (composite: orchestration vs choreography for order lifecycle)

**The facts (composite):** two senior engineers in a commerce org disagree on how to coordinate the order lifecycle across eight services: one wants a central workflow engine (orchestration); the other wants services reacting to domain events (choreography). Each has written a design; teams are building against both.

#### How an L5 tells it

> "Two senior engineers on my org disagreed on orchestration vs choreography for our order flow. I was asked to weigh in because I knew both systems. I reviewed both designs, and I thought the workflow engine was better for visibility, so I recommended it. Leadership agreed, and we went with that approach."

**What the committee extracts:** gave an opinion; no process; no attention to the losing side. **L5.**

#### How an L7 tells it

> "Two senior engineers in our commerce org had been arguing for a quarter about how to coordinate the order lifecycle across eight services. Dana wanted a central workflow engine; Sam wanted services to react to domain events. Teams had started building against both designs, so we were accumulating integration debt every week. Our director asked me to settle it.
>
> I didn't start with the designs. I met each of them alone and asked what they'd be most worried about if the other design won. Dana's worry was debuggability: last year a stuck refund took three days to trace across five services. Sam's was coupling: his team had been blocked for weeks by a central scheduler in a previous system. Both were real incidents, and both had numbers.
>
> That told me the disagreement was mostly about values, so I ran a criteria session with both of them and the four service TLs, with no designs on the table. We agreed four criteria and their order: end-to-end traceability of any order, no single team on the critical path for others' releases, compensations for partial failure, and time to first value. The director confirmed the order.
>
> Scored against those criteria, neither design won outright. The lifecycle that needed traceability and compensations, payment through fulfilment, went to the workflow engine, owned by Dana's team. Everything that only needed to *react* to order state, such as notifications, analytics and loyalty points, stayed choreographed on events, owned by Sam's team. Sam also took ownership of the event schema contract, which was where his design had been strongest.
>
> I wrote the decision record with both of their arguments in their own words, and what would reopen the decision. Within a quarter the eight services had converged, and stuck-order investigation time went from days to under an hour, because every critical-path order had a workflow history. Sam and Dana now run the commerce architecture review together."

**What the committee extracts:** arbitration through process; found each side's real fear; untangled values from facts; criteria before options, ordered by the decider; a split by scope; ownership given to both according to their strengths; a decision record; a stronger relationship. **L7 arbiter.**

---

## 7. Adversarial Bar-Raiser Follow-Up Chains

### Chain A · "What was the other principal right about?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "State his design as he would." | Steelmanning | A weakened version | His real argument, including the expertise point |
| 2 | "What did he see that you missed?" | Humility | "Nothing important" | The schema-change failure mode |
| 3 | "Did his view change your design?" | Influence both ways | "No" | "Yes: the per-region data stayed on his tier" |
| 4 | "How would he tell this story?" | Empathy | Unsure | Plausibly, in his words |
| 5 | "Would he recommend you?" | Relationship | Hesitates | "Yes. We co-presented the decision." |

### Chain B · "Why did it take two months?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What was the cost of the delay?" | Business awareness | Unsure | Four teams blocked; integration debt per week |
| 2 | "What did you do in the first two months?" | Reflection | Defends it | "Argued. That was my mistake; we'd have settled it faster with the bake-off in week two." |
| 3 | "What made you change approach?" | Self-awareness | External event | The realization that the argument outlasted the experiment |
| 4 | "How would you shorten it next time?" | Learning | "Better communication" | "Untangle the types and agree the criteria in week one" |

### Chain C · "How did you know the bake-off was fair?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Who designed the benchmark?" | Fairness | "I did" | "Both teams jointly" |
| 2 | "What workload?" | Rigor | Synthetic | Replayed production traffic |
| 3 | "When were the thresholds set?" | Pre-registration | After | Before, and signed by both |
| 4 | "What if the result had favoured him on everything?" | Commitment | "It wouldn't" | "Then his design, and I'd have committed" |
| 5 | "What did the bake-off not measure?" | Limits | Nothing | Long-term operational cost, team learning curve |

### Chain D · Decision rights

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Who had the authority to decide?" | Clarity | "Leadership" | "The VP, once we brought one document" |
| 2 | "Why didn't the VP just decide earlier?" | Insight | Unsure | "She had contradictory advice from two people she trusted" |
| 3 | "Could you have decided yourself?" | Judgment | "Yes" or "No" | Why a joint decision was better than a unilateral one here |
| 4 | "What would reopen the decision?" | Durability | Nothing | Conditions written in the decision record |

### Chain E · Arbiter: "Whose side were you on?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Did you have a preference going in?" | Honesty | "No" | The honest prior, and how it was kept out of the process |
| 2 | "How did you make each side feel heard?" | Empathy | "Meetings" | Separate one-to-ones about their fears |
| 3 | "Why criteria before designs?" | Method | Unsure | People defend designs; few argue against an ordered criterion |
| 4 | "What did each side lose?" | Honesty | "Nothing" | What each gave up |
| 5 | "What's their relationship now?" | Outcome | Unknown | They co-run the review |

---

## 8. Checklist

- [ ] Your architectural-conflict story has a counterpart who is senior and **good**, not a difficult person.
- [ ] You can name which disagreement types were tangled (facts, values, scope, interests, identity) and the tool used for each.
- [ ] You wrote the strongest version of the other design and had its owner correct it.
- [ ] Any experiment had criteria agreed before it ran.
- [ ] You can say who had decision rights, and what you did if nobody did.
- [ ] The outcome gives the other side a part they were right about, with credit.
- [ ] The relationship has evidence of being stronger afterwards.
- [ ] Prepare one combatant story and one arbiter story.

## 9. References

- Bain & Company, *RAPID decision-making*. <https://www.bain.com/insights/rapid-decision-making/>
- Will Larson, *Staff Engineer: Leadership beyond the management track*: the chapters on managing technical quality and on getting into the room. <https://staffeng.com/book>
- Tanya Reilly, *The Staff Engineer's Path* (O'Reilly, 2022; ISBN 978-1-098-11873-0): on navigating conflict and aligning on technical direction. Author's page: <https://www.noidea.dog/staff>
- Roger Fisher and William Ury, *Getting to Yes* (1981): separating positions from interests, the basis of §2.
- In this KB: [02.2 The Technical Conflict Trap](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/02-google-gnl-and-meta-jedi-conflict-direction-and-ambiguity.md) · [02.1 Disagree and Commit](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/01-amazon-16-leadership-principles-l6-l7-bar-raiser-deep-dive.md) · [03.2 Influencing executives](02-influencing-product-and-execs-killing-bad-projects-and-saying-no.md) · [03.3 Migrations without mandates](03-driving-multi-team-migrations-and-adoption-without-mandates.md)
- Technical depth for 6.1 and 6.2: the multi-region and saga material in the [Distributed Systems Design L7 Reference](../../Distributed-Systems-Design-L7-Reference/).
