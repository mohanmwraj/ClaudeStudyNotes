# 07.1 · Questions 1–10: Conflict, Pushback and Disagree-and-Commit

> **Folder 07 · File 1 of 3.** Thirty questions, ten per file, each answered twice: the way a strong L5 answers it, and the way an L7 answers it. The questions are **original formulations** of standard senior competency prompts, not recalled interview questions. Every company asks some version of them.
>
> The L7 answers are the **three-minute** version of the accordion (01.3 §4): long enough to carry all six C-T-O-A-R-L beats, short enough to leave twenty minutes for probing. Each is an **illustrative composite** with placeholder numbers. Use the shape; replace the content with your own work.
>
> This file covers conflict and influence: disagreeing upward, conflict between teams, pushing back on product, disagree-and-commit, losing to a peer, delivering unpopular decisions, being changed by someone junior, difficult relationships, escalation, and reopening a decision.

---

## 1. How to use this file

1. Read the question and **write your own answer first**, before reading either model answer.
2. Compare your answer against the L5 version. If yours resembles it, look at the "what separates them" note.
3. Rehearse the follow-up probes in §4 aloud. They matter more than the opening.
4. Map each question to one of your eight core stories (Folder 08). Most of these ten questions can be answered from your Cross-Team Conflict, Disagree-and-Commit and Killing-a-Bad-Idea stories.

---

## 2. Hiring Committee Scoring Rubric (conflict and influence questions)

| Signal | Strong Hire at L7 | Down-level to L5 |
|---|---|---|
| **Counterpart** | Senior, capable people, often in other orgs, with legitimate positions | Peers or juniors on the same team; or a "difficult person" |
| **Nature of conflict** | Competing valid priorities, quantified (02.2 §3) | Personalities, or one side simply wrong |
| **Mechanism** | Data, prototypes, criteria before options, joint escalation, structural change | Persuasion in meetings; escalation against someone |
| **Concession** | Something real given up or learned | Nothing; "I was right" |
| **Commitment** | Wholehearted after losing; risks turned into owned tripwires | Passive compliance; re-litigation; "I told you so" |
| **Outcome** | A durable decision, a business result, and a better relationship | The candidate's design won |
| **Leverage** | A changed decision process the org still uses | None |

---

## 3. Story Blueprints: the ten questions

### Q1 · "Tell me about a time you disagreed with a senior leader's technical direction."

*Tests:* Backbone upward, data over opinion, respect for the leader's goal.

#### How an L5 tells it

> "Our director wanted us to adopt a new NoSQL database for a new service. I thought Postgres would be fine for our access patterns, and I said so in the design review. We discussed it and in the end we went with Postgres, which worked well."

#### How an L7 tells it

> "Our VP of Engineering announced that the search org would move its ranking features to a new vendor's feature platform, to standardize on one tool across ML teams. The goal was right: we had five feature stores and no shared definitions. I disagreed with the vehicle, because the vendor's online-serving latency, at our fan-out, would have added about 40 ms to every search.
>
> I didn't argue the decision in public. I asked her for two weeks to test it on our real query mix, and brought the results to her privately: p99 serving latency was 3× our budget, and the conversion cost of that latency was larger than the platform's projected savings. I also brought an alternative that kept her goal: adopt the vendor for feature *definitions* and offline training, and keep our own online-serving layer, reading those shared definitions.
>
> She challenged the maintenance cost of keeping our own serving layer, which was a fair point, and I committed the search infrastructure team to owning it, with a cost review each year. She approved the hybrid. Feature definitions were unified across all five ML teams within two quarters, search latency was unaffected, and the annual review is how we'll know when the vendor's serving catches up."

**What separates them:** the L7 counterpart is a VP with a sound goal; the disagreement is about means, settled with data on real traffic, privately, with an alternative that preserves the goal and a cost the candidate's team accepted.

### Q2 · "Describe a conflict between two teams where both had a legitimate case."

*Tests:* Empathy, the Technical Conflict Trap (02.2), designing a resolution neither side proposed.

#### How an L5 tells it

> "The mobile team wanted the API to return everything in one call, and the backend team wanted smaller endpoints. I worked with both teams and we agreed on a compromise with a few medium-sized endpoints. Both sides were mostly happy."

#### How an L7 tells it

> "Our mobile org needed the home screen to load in one round trip, because each extra call cost about 300 ms on slow networks in our growth markets. The backend domain teams needed to keep their services independently deployable, and an aggregate endpoint owned by one team would couple all of them. Both were right, and they'd been arguing for a quarter.
>
> I reframed it as a question of ownership: who owns the shape of a screen's data? The answer that served both was a backend-for-frontend layer owned by the mobile org, composing the domain services, with a schema contract each domain team published and versioned. The mobile team got one round trip; the domain teams kept their independence and only had to honor their published contract.
>
> The domain leads' concern was that the composition layer would become a dumping ground for business logic. I agreed, and wrote that into the contract: no business rules in the composition layer, enforced in its code review. Home-screen load time in our largest growth market fell by 1.1 seconds, and the domain teams' deploy frequency was unchanged. Two more screens followed the same pattern."

**What separates them:** the L7 names both priorities with numbers, changes the question (ownership), proposes a structure rather than a midpoint, accepts the other side's risk as a rule, and measures both sides' outcomes.

### Q3 · "Tell me about a time you pushed back on a product requirement."

*Tests:* Saying no with an alternative (03.2 §2), user and business framing.

#### How an L5 tells it

> "Product wanted real-time notifications for every price change on watched items. I told them that would be too expensive and complex. We agreed to send a daily digest instead."

#### How an L7 tells it

> "Product wanted a real-time notification whenever any watched item's price changed. I asked what the feature was for: re-engaging users who'd abandoned a purchase. The requirement as written would have sent about 40 million notifications a day, most of them for changes of a few cents, and our own data showed users who got more than three notifications a day turned them off.
>
> So I offered a different yes. Notify in real time only when the change crossed a threshold that mattered, a price drop of more than 10% or back in stock, with a cap of two a day per user, and fold everything else into a weekly summary. That was about 2% of the original volume, cheap enough to run on our existing pipeline.
>
> The product manager's concern was that we'd miss small drops on expensive items, which was a fair one, so the threshold became the larger of 10% or a fixed amount. We ran it as an experiment against the original design on a small cohort. The threshold version produced 30% more returning purchases per user, with a far lower notification opt-out rate, and it shipped as the default."

**What separates them:** the L7 asks what the requirement is for, uses data on user behavior, offers a "yes, but different" that serves the goal better, adopts the PM's correction, and lets an experiment decide.

### Q4 · "Tell me about a decision you disagreed with but committed to."

*Tests:* Disagree and Commit (02.1 §4.2). Keep this separate from your Backbone story.

#### How an L5 tells it

> "I wanted to use Kubernetes for our new platform, but the architect decided to use a serverless approach. I disagreed but went along with it and implemented my part. It turned out fine, although we had some cold-start issues later that I'd mentioned."

#### How an L7 tells it

> "I argued that our new event-processing platform should be built on our existing Kubernetes clusters. The principal architect chose a managed serverless approach, mainly to avoid our team operating more infrastructure. I made my case once, with cost projections at our expected volume, and he held his decision. I committed.
>
> Committing meant making serverless work well, not proving it wouldn't. The risk I'd raised was cold-start latency for our bursty partner traffic, so I owned that problem myself: I built a provisioned-concurrency controller driven by the partner traffic forecast, and wrote a load test that reproduced our burst shape. I also turned my cost concern into a tripwire we agreed together: if monthly cost per million events exceeded the Kubernetes estimate by 30% for a quarter, we'd revisit.
>
> The platform launched on time, p99 met its target with the controller in place, and the cost tripwire never fired, because I'd over-estimated the steady-state volume. He was right about the operational load: our team has had almost no on-call for it. That changed my default: I now put a team's operational capacity into the decision criteria explicitly."

**What separates them:** the L7 makes the case once, commits by owning the risk they raised, sets a tripwire instead of waiting to say "I told you so", and reports honestly that the decider was right.

### Q5 · "Describe a time a peer rejected your design. How did you respond?"

*Tests:* Humility among equals, separating ego from the outcome.

#### How an L5 tells it

> "I proposed a caching design for our service, but another senior engineer thought it was too complex and rejected it in review. I was disappointed, but I simplified it based on his feedback, and we went with the simpler version."

#### How an L7 tells it

> "I proposed a unified identity service to replace three login systems after an acquisition. A principal from the acquired company rejected the design in the architecture review: it assumed our session model, which would have broken single sign-on for about 30% of their enterprise customers. My first reaction was defensive, because I'd spent a month on it.
>
> Then I asked her to walk me through the failure case, and she was right; I hadn't understood how their enterprise customers federated identity. I withdrew the design, and proposed that we rewrite it together, with her owning the federation section. The joint design kept their federation model as the core and moved our consumer login onto it, the opposite of my original direction.
>
> We migrated all three login systems over three quarters with no single-sign-on breakages. The most important part of the outcome wasn't the design: the acquired engineers had felt their systems were being replaced by default, and co-ownership of identity changed that. She and I now co-chair the identity architecture review."

**What separates them:** the L7 admits the initial defensiveness, investigates the objection, concedes publicly, inverts their own design, shares ownership, and recognizes the organizational effect.

### Q6 · "Tell me about a time you had to deliver an unpopular decision to engineers."

*Tests:* Communication, transparency about reasoning, care for the people affected.

#### How an L5 tells it

> "Leadership decided we had to stop work on a project to focus on a migration. I told my team about the decision in our stand-up. Some people were unhappy, but they understood."

#### How an L7 tells it

> "I recommended, and the director approved, deprecating our internal deployment tool in favor of the company's standard platform. About 60 engineers across eight teams used our tool and liked it, and several had built their workflows around features the standard platform lacked.
>
> I announced it myself, in writing first and then in an open session. I explained the reasoning, including what we were giving up: two features with no equivalent yet. I gave a timeline set by when those gaps would close, not by a date. Then I took the hardest questions in the session without deflecting, including one engineer who said, publicly, that it was a political decision. I told him which part was a judgment call and why I'd made it.
>
> I made two commitments: my team would migrate every service's pipeline configuration with tooling, and we'd build the two missing features into the standard platform ourselves before the cutoff. We did both. All eight teams moved within the quarter, and in the retrospective survey most rated the migration as smooth. The engineer who'd called it political contributed one of the two missing features."

**What separates them:** the L7 owns the recommendation rather than relaying it, names the losses, sets the timeline by readiness, takes hostile questions directly, and makes commitments that reduce the cost to others.

### Q7 · "When have you changed your mind because of someone more junior?"

*Tests:* Intellectual humility, psychological safety you create, Are Right A Lot.

#### How an L5 tells it

> "A junior engineer on my team suggested using a different library than the one I'd chosen. I looked into it and it was better, so we switched. I think it's important to listen to everyone."

#### How an L7 tells it

> "I'd set the direction for our data platform's retention strategy: keep raw events for two years in our warehouse, for reprocessing. In a design review, a new-grad engineer on the analytics team asked, quietly, what fraction of reprocessing jobs in the last year had actually needed events older than ninety days. I didn't know.
>
> She'd already pulled the job logs: under 1% had, and all of those could have used the daily aggregates we already kept. At our volumes, the two-year raw retention cost about $X K a month, and it was also a privacy exposure we didn't need.
>
> I said in the review, in front of the room, that her analysis changed my mind, and asked her to write the proposal for ninety-day raw retention with aggregate fallback. She did; I reviewed it and got it approved with the privacy team. Storage cost fell by about 60%, and our privacy review rated the change as reducing risk. Afterwards I changed one thing about how I run reviews: the first question slot goes to the most junior person in the room."

**What separates them:** the L7's mind is changed on something they had personally set, by a junior's data; they credit her publicly, give her ownership, and change a forum so it happens again.

### Q8 · "Tell me about the most difficult working relationship you've had."

*Tests:* Empathy, ownership of your part, repair.

#### How an L5 tells it

> "I worked with a product manager who kept changing requirements and didn't understand technical constraints. It was frustrating. I tried to document everything carefully so we had a record, and eventually he moved to another team."

#### How an L7 tells it

> "The hardest relationship I've had was with the SRE lead for our payments platform. For about six months, every change my team proposed met a long list of objections from him, and I'd started to treat him as an obstacle. I said as much to my manager, which I'm not proud of.
>
> What changed it was asking him directly, over a coffee, why he was so cautious with our changes in particular. He told me his team had been paged for two incidents caused by our releases in my first quarter, and that nobody from my team had joined their postmortems. From his side, we were a team that broke things and left.
>
> He was right about that. I apologized for the postmortems, and I proposed that my team join every incident review involving our services and own the action items from our side. I also invited him into our design reviews early, rather than meeting his objections at release time.
>
> Within a quarter, our change failure rate in payments dropped by half, mostly from his early review comments. A year later he was the one who nominated my team's release process as the template for the platform."

**What separates them:** the L7 owns their own bad behavior, asks directly, discovers a legitimate grievance, fixes their side structurally, and shows the relationship became productive.

### Q9 · "Describe a time you escalated something. Was it the right call?"

*Tests:* Escalation judgment: when, how, and with whom.

#### How an L5 tells it

> "Another team wasn't delivering an API we depended on, and our launch was at risk. After a few weeks of waiting, I escalated to my manager, who talked to their manager, and they prioritized it."

#### How an L7 tells it

> "Our fraud team needed transaction-graph features from the data platform team for a new model, and the platform team's roadmap had no room for two quarters. Fraud losses on the affected product were about $X K a week. I spent two weeks trying to resolve it at our level: I offered engineers from my team to build it under their review, and proposed a smaller interim version. Their lead was willing, but her quarter was already committed to her VP.
>
> At that point it wasn't a disagreement between us; it was a priority decision above both of us. So I escalated, but jointly. I wrote a one-page note with her, setting out the fraud exposure, her current commitments and the options, and we took it to both VPs together.
>
> The VPs agreed to slip one of her lower-impact items by six weeks, and my team supplied two engineers. The features shipped in five weeks, and fraud losses on that product fell by about 60% after the model launched. Was escalation right? Yes, but I'd do it sooner: I spent a week longer than I needed to before recognizing that the decision wasn't ours to make."

**What separates them:** the L7 exhausts peer-level options, recognizes when a decision belongs above both parties, escalates *with* the other lead using a joint document, and reflects honestly on timing.

### Q10 · "Tell me about a time you challenged a decision that had already been made."

*Tests:* Reopening decisions properly: new information, the right forum, no re-litigation.

#### How an L5 tells it

> "We had decided to build a feature a certain way, but halfway through I realized there was a better approach. I brought it up with the team and we switched, which saved some time."

#### How an L7 tells it

> "Our org had decided, through a full design review, to build regional failover for the checkout service using active-passive replication, with a recovery-time objective of fifteen minutes. Three months later, the business signed a contract with a major retail partner that included a five-minute availability commitment with financial penalties. Nobody had connected the contract to the architecture decision.
>
> I didn't reopen the decision because I preferred a different design. I reopened it because one of its inputs had changed. I wrote a two-page note to the original review group: the new requirement, the penalty exposure, and the specific part of the decision it invalidated, the recovery-time objective. I proposed three options, including keeping the design and negotiating the contract term.
>
> The review group met within a week and changed one thing: a warm standby with automated failover, which met five minutes at about 30% more cost, rather than a full active-active redesign. Sales also negotiated a ramp period for the new term. We met the commitment through two regional events in the following year with no penalties. I also added a step to our contract-review process: commercial teams now flag any availability or latency term to the architecture review before signing."

**What separates them:** the L7 reopens because an input changed, not out of preference; goes to the original decision-makers; narrows the change to what the new input invalidates; offers non-engineering options; and fixes the process gap that caused it.

---

## 4. Bar-Raiser Follow-Up Chains

Three probes per question: what to expect, and the shape of an owner's answer.

| Q | Probe | Tests | Owner's answer shape |
|---|---|---|---|
| **1** | "What if her VP had overruled the hybrid?" | Commitment | "I'd have committed, and put the latency cost into a tripwire" |
| | "Why privately?" | Influence judgment | "Data in public after an announcement forces a defense" |
| | "What's the risk in your own serving layer?" | Honesty | The maintenance cost, and the annual review |
| **2** | "Who owns the composition layer, and why them?" | Structure | The mobile org: it owns the screen's needs |
| | "What stops it growing business logic?" | Mechanism | The contract rule enforced in review |
| | "Did either team lose anything?" | Trade-off honesty | The mobile org took on a service to run |
| **3** | "How did you know about the opt-out behavior?" | Data | The existing notification data, and who analyzed it |
| | "What did the experiment measure?" | Rigor | Returning purchases per user and opt-out rate |
| | "What if the original had won the experiment?" | Commitment | "We'd have shipped it, with a cost plan" |
| **4** | "How many times did you raise it?" | Re-litigation | Once, before the decision |
| | "What did you personally own afterwards?" | Active commitment | The cold-start controller and load test |
| | "Was he right?" | Self-awareness | Yes, on operations, and what changed in the candidate |
| **5** | "What was your first reaction?" | Honesty | Defensive, and what moved past it |
| | "Why give her the federation section?" | Shared ownership | Her expertise, and the acquired team's trust |
| | "What did the acquired engineers think before?" | Org awareness | That their systems were being replaced by default |
| **6** | "Whose decision was it?" | Ownership | "My recommendation; the director approved" |
| | "What did you say to the engineer who called it political?" | Courage | The judgment call, named and explained |
| | "What did the decision cost the teams?" | Care | The two missing features, built by the candidate's team |
| **7** | "What had you assumed?" | Reflection | That reprocessing needed old raw events |
| | "How did you credit her?" | Credit | Publicly, plus ownership of the proposal |
| | "What did you change afterwards?" | Mechanism | The first question slot in reviews |
| **8** | "What was your part in the problem?" | Ownership | Missing postmortems; treating him as an obstacle |
| | "What did he say when you asked?" | Listening | The two incidents and the postmortems |
| | "How do you know it changed?" | Evidence | Change failure rate; his nomination later |
| **9** | "What did you try before escalating?" | Exhaustion of options | Engineers offered; interim version |
| | "How did the other lead feel about escalating?" | Joint escalation | She co-wrote the note |
| | "Would you do it differently?" | Reflection | Sooner, once it was clearly above both of them |
| **10** | "Why wasn't this re-litigation?" | Judgment | An input changed; only the affected part reopened |
| | "Who did you take it to?" | Forum | The original review group |
| | "How do you stop it happening again?" | Process | The contract-review step |

---

## 5. Checklist

- [ ] For each of the ten questions, you've written your own answer before reading the models.
- [ ] Every counterpart in your answers is senior, capable and partly right.
- [ ] Your Q1 (Backbone) and Q4 (Disagree and Commit) answers use **different** stories.
- [ ] Each answer includes a concession or something you learned from the other side.
- [ ] Each answer ends with a durable change: a process, a structure or a relationship.
- [ ] You've rehearsed the three probes per question aloud.

## 6. References

- In this KB: [02.1 Backbone and Disagree-and-Commit](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/01-amazon-16-leadership-principles-l6-l7-bar-raiser-deep-dive.md) · [02.2 The Technical Conflict Trap](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/02-google-gnl-and-meta-jedi-conflict-direction-and-ambiguity.md) · [03.1 Architectural wars](../03-Influence-Without-Authority-and-Cross-Org-Alignment/01-resolving-architectural-wars-between-competing-principal-engineers.md) · [03.2 The "no" menu](../03-Influence-Without-Authority-and-Cross-Org-Alignment/02-influencing-product-and-execs-killing-bad-projects-and-saying-no.md) · [07.2 Questions 11–20](02-questions-11-to-20-ambiguity-vision-failure-and-missed-deadlines.md) · [07.3 Questions 21–30](03-questions-21-to-30-mentorship-hiring-org-design-and-ethics.md)
- Folder 08 maps all thirty questions, and twenty more, to the eight core stories.
