# 05.1 · Owning Catastrophic SEV1 Outages and Bad Architectural Bets

> **Folder 05 · File 1 of 3.** "Tell me about your biggest failure" is the question where the most otherwise-strong senior candidates lose the level. They choose a failure that's too small, or someone else's, or so heavily cushioned that nothing was really lost. The committee reads that as low self-awareness, or as a candidate who has never operated at a scale where failures are large.
>
> At L7, your failures should be **proportionate to your scope**: an outage your design caused, or an architectural bet that cost an org quarters. What earns the level is how you **owned** it, what you did in the first hour, and what's different, permanently, because of it.
>
> This file covers:
> - the kinds of failure story, ranked by signal;
> - the anatomy of a strong failure story;
> - the L7's role in a major incident, hour by hour;
> - bad architectural bets: recognizing, calling and reversing your own;
> - the traps;
> - a rubric, three story blueprints and five follow-up chains.
>
> Folder 05.2 covers what comes after: the COE, blameless postmortems and org-wide guardrails. Stories are **illustrative composites**.

---

## 1. Kinds of failure story, ranked by signal

| Kind | Signal at L7 | Why |
|---|---|---|
| **A bad architectural bet you made**, recognized and reversed | Highest | Shows judgment over time, ownership of a decision, the courage to call your own bet, and handling sunk cost |
| **An outage your design or decision caused** | High | Clear ownership; shows response, accountability and systemic repair |
| **A strategic call that was wrong** (prioritization, staffing, sequencing) | High | Shows senior-level judgment and reflection |
| **A major incident you led the response to**, not caused | Medium | Shows leadership under pressure, but ownership of the cause is weaker |
| **A missed deadline** | Medium | Often an estimation or scoping failure; good for Folder 07 Q11–20 |
| **A bug in your code** | Low at L7 | Proportionate to L4–L5 scope |
| **A failure that was really someone else's** | Negative | Reads as blame |

**Prepare two failure stories:** one operational (an outage) and one judgment-based (a bet). Interviewers who hear an outage story often follow with "now tell me about a decision you got wrong".

---

## 2. The anatomy of a strong failure story

| Beat (C-T-O-A-R-L) | In a failure story | Example sentence |
|---|---|---|
| **Headline** | Own it in the first sentence | "A retry policy I designed turned a provider slowdown into a 47-minute checkout outage." |
| **Context and risk** | The impact, honestly: customers, revenue, trust | "About 180,000 failed checkouts; roughly $X M in lost orders." |
| **Trade-off** | The decision that led there, and why it seemed right at the time | "I'd chosen aggressive client retries because the provider's errors were usually transient." |
| **Org alignment** | Who you had to work with during and after | "I took the COE to the VP and the five client-library teams." |
| **Action** | First hour, then the systemic fix | "I made the call to disable retries fleet-wide in minute 12; then I redesigned the policy." |
| **Result** | Evidence it hasn't recurred | "No retry-amplification incident since, across 300 services." |
| **Learning and leverage** | What changed in your judgment, and the mechanism others now use | "I now model the failure behavior of any default I ship to many teams." |

The beat candidates skip is **why it seemed right at the time**. Without it, the failure reads as carelessness. With it, the failure reads as a reasonable decision whose risk you now understand better, and that's what a committee wants to know you've learned.

---

## 3. The L7's role in a major incident

At L7 you are often not the incident commander. In Google's SRE incident model (*Site Reliability Engineering*, "Managing Incidents"), roles are separated: an incident commander coordinates, an operations lead works the system, and a communications lead handles updates. A senior engineer's distinctive contributions are judgment calls only they can make with confidence:

| Phase | What an L7 does |
|---|---|
| **Minutes 0–15: stabilize** | Push for mitigation before diagnosis: rollback, failover, disabling a feature. "Stop the bleeding first; understand later." |
| **Risky mitigations** | Make or advise on the irreversible ones: a regional failover, a data repair, a fleet-wide config change. State the risk out loud and record the decision. |
| **Executive communication** | Give leadership an honest, short update: impact, what's being done, next update time. Shield the responders from executive pressure. |
| **Protecting responders** | Enforce handoffs on long incidents; stop people working for twenty hours; keep blame out of the channel. |
| **After stabilization** | Preserve evidence; start the timeline; identify who should own the COE. |

**In your story,** be precise about which role you played. Claiming to have been the incident commander when you weren't collapses under the first probe ("who was IC?").

---

## 4. Bad architectural bets

### 4.1 Why they're the strongest failure stories

An outage is a moment; a bet is a judgment that played out over months. Telling one well shows:
- your **reasoning** at the time (was it a good decision with a bad outcome, or a bad decision?);
- **how long** it took you to notice, and what you noticed;
- that you could **call your own bet** when others still believed in it, or before anyone else saw it;
- that you **handled sunk cost**: you stopped when the evidence said so, not when the project ran out of money.

### 4.2 Recognizing your own bad bet

The hardest part is internal. Signs, in roughly the order they appear:
1. The leading indicators you set at the start are drifting, and you find yourself explaining them away.
2. The cost of each step is higher than planned, consistently, not randomly.
3. Teams are building workarounds for your design.
4. You're defending the design in reviews more often than you're improving it.
5. Someone you respect says it out loud.

**Pre-registered kill criteria** (04.2) exist precisely because these signs are easy to rationalize.

### 4.3 Reversing it

| Step | What it involves |
|---|---|
| **Say it first** | You tell your leadership and the affected teams before they tell you. |
| **Separate the decision from the outcome** | Explain what was reasonable at the time and what you misjudged. |
| **Size the reversal** | The cost of reversing now, compared with continuing; sunk cost excluded by name. |
| **Salvage** | What survives: components, data, learning. |
| **Own the reversal plan** | You lead the way back, rather than handing the mess to someone else. |
| **Change your process** | The specific practice you'd change so the next bet is better. |

---

## 5. The traps

| Trap | What it sounds like | What the committee concludes |
|---|---|---|
| **Humble-brag** | "I cared too much about quality" | Evasive; no real failure |
| **Too small** | A bug that was caught in staging | Never operated at scale where failures are large |
| **Someone else's** | "The other team's change broke us" | Blames; low ownership |
| **No cost** | "It worked out in the end" | Hasn't confronted the impact |
| **No change** | "It was bad luck" | Doesn't learn |
| **Over-correction** | Ten minutes of self-criticism, no recovery | Low confidence; can't move on |
| **Borrowed or fictional** | Details that don't hold under probing | Credibility collapse, the worst outcome |

The right register is **matter-of-fact**: what happened, what it cost, what was yours, what you did, what's different. Not defensive, not dramatic.

---

## 6. Hiring Committee Scoring Rubric

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | No hire |
|---|---|---|---|---|
| **Proportion** | A failure at org scale: an outage your design caused, or a bet that cost quarters | A cross-team failure | A failure in own service | Trivial or humble-brag |
| **Ownership** | Owns it in the first sentence; names their own decision as a cause | Owns their part | Shares blame broadly | Blames others |
| **Honesty about impact** | Customers, revenue and trust, quantified | Quantified technically | Vague | Minimized |
| **Reasoning at the time** | Explains why it seemed right, separating decision quality from outcome | Some explanation | "It was a mistake" | No explanation |
| **Response** | Decisive mitigation, the risky calls owned, honest executive communication, responders protected | Led the technical fix | Participated | Unclear role |
| **Systemic repair** | A mechanism that prevents the class of failure across the org | A fix that prevents recurrence in the area | A fix for this instance | No fix |
| **Changed judgment** | A specific, durable change in how they decide | A reasonable lesson | Generic lesson ("test more") | None |
| **Calling own bet** (for bets) | Called it before others, stopped despite sunk cost, led the reversal | Reversed when evidence was clear | Reversed when forced | Never reversed |

---

## 7. Story Blueprints

### 7.1 An outage your design caused (composite: retry amplification from a shared client library)

**The facts (composite):**
- The candidate designed the default retry policy in the company's shared HTTP client library, used by about 300 services.
- When a payments provider slowed down, every caller retried three times with short backoff, tripling load on an already struggling dependency.
- Checkout failed for 47 minutes.

#### How an L5 tells it

> "We had an outage when our payment provider slowed down. There were a lot of retries happening which made things worse. The team worked on it and we eventually got things stable. Afterwards we reduced the retry counts in some services and added more monitoring. It was a good learning experience about retries."

**What the committee extracts:** "we had an outage" with no ownership; unclear role; instance-level fix; generic lesson. **L5, and possibly a candor concern if the design was theirs.**

#### How an L7 tells it

> "A retry policy I designed turned a payment-provider slowdown into a 47-minute checkout outage. About 180,000 checkouts failed, roughly $X M in orders, and our largest merchant escalated to our CEO.
>
> Two years earlier, I'd set the default retry policy in our shared HTTP client: three retries, short backoff, no jitter, on any 5xx. It seemed right at the time, because our providers' errors were almost always transient, and the default cut checkout failures noticeably. What I hadn't modeled was what happens when a dependency is slow rather than failing: 300 services each retrying three times tripled its load just when it had the least capacity.
>
> I wasn't the incident commander; I joined as technical lead at minute 6. By minute 12 I was confident the retries were sustaining the overload, so I recommended disabling client retries fleet-wide through our config system. That was risky: it would surface every transient error to users. I said so in the channel, the IC agreed, and the provider recovered within four minutes of the change. The rest of the 47 minutes was the provider's own backlog draining.
>
> In the COE, I wrote the root-cause section about my own design, and presented it to the VP and the five teams that own client libraries. The fix wasn't three retries instead of two. I redesigned the default around retry budgets: each client may retry at most 10% of its requests over a rolling window, with exponential backoff and jitter, and the client stops retrying entirely when the dependency's error rate is high. I also added a load test that simulates a slow dependency, which every change to the client library must pass.
>
> We rolled the new policy to all 300 services through the library over six weeks. In the eighteen months since, we've had three provider slowdowns of similar size, and none became an outage. The lesson I took is specific: any default I ship to many teams, I now model under a slow dependency, a failing one and a recovering one, because the failure modes of a default are multiplied by everyone who uses it."

**What the committee extracts:** ownership in the first sentence; impact honestly stated; why it seemed right; precise about role; a risky mitigation called with the risk stated; wrote the COE about their own design; a systemic redesign (retry budgets), not a parameter tweak; a test that guards the class of failure; evidence over eighteen months; a specific change in judgment. **Strong L7.**

### 7.2 A bad architectural bet (composite: splitting a monolith too early)

**The facts (composite):** the candidate championed splitting a monolith into about 40 microservices. Eighteen months in, delivery speed has fallen and incidents have risen.

#### How an L5 tells it

> "We migrated our monolith to microservices, but it turned out to be harder than expected. There were a lot of issues with service-to-service communication and debugging. In the end we merged some of the services back together. I learned that microservices aren't always the right answer."

**What the committee extracts:** "we"; no ownership of the decision; a generic lesson. **L5.**

#### How an L7 tells it

> "The worst architectural bet I've made was championing a split of our order-management monolith into about forty microservices. I was the one who proposed it, and my document convinced our director.
>
> My reasoning was sound on its face: four teams were blocked on one release train, and we expected to double the team count within a year. What I got wrong was the boundaries. I drew them around nouns (orders, payments, shipments) rather than around the changes teams actually made. Most features cut across three or four services, so we traded one release train for constant cross-service coordination.
>
> The signs were there by month six: lead time for changes was getting worse, not better, and teams were creating shared libraries that coupled the services again. I explained those signs away for another four months, which I regret. What finally made me stop was my own data: when I mapped a quarter of feature work against service boundaries, 70% of changes touched three or more services.
>
> I told the director and the four TLs before anyone escalated it to me. I presented the data and said plainly that the boundaries were my mistake. I proposed consolidating into a modular monolith for the core order flow, with six services kept separate where boundaries were real: payments, search, notifications and three more. I led the consolidation myself over two quarters, using the feature-change data to draw the new boundaries.
>
> It cost us about three quarters of reduced delivery overall, which is the number I'd put on that bet. After consolidation, lead time for changes fell to below its pre-split level, and incidents caused by cross-service changes dropped by about two thirds. What I changed in my judgment: I now draw service boundaries from a quarter of real change data before proposing a split, and I set a lead-time tripwire for any decomposition I propose."

**What the committee extracts:** owns the decision personally; separates sound reasoning from the specific error (boundaries); honest about the delay in recognizing it; data-driven recognition; told leadership first; owned the reversal and led it; cost stated; changed method and a tripwire. **Strong L7 bet story.**

### 7.3 An incident you led but didn't cause (composite: a regional storage failure)

#### How an L5 tells it

> "There was a big outage when one of our cloud regions had storage problems. I was on call and worked through the night with the team to fail over to another region. It took a long time, but we got everything back up."

**What the committee extracts:** hard work during an incident; heroics; no judgment calls described; no systemic change. **L5.**

#### How an L7 tells it

> "When our primary region's block storage degraded, I was the senior engineer on the incident bridge, with a staff SRE as incident commander. Our order database was in that region, and our failover runbook had last been tested eight months earlier.
>
> The key call was whether to fail over at all. Failover had a known risk: up to 30 seconds of replication lag, which meant some orders could be lost and would need reconciliation. The alternative was waiting for the provider, with an unknown timeline. At minute 25, with the provider still giving no estimate, I recommended failover. I gave the IC the risk in one sentence: up to about 2,000 orders might need reconciling from payment records. She approved it, and I wrote the decision and the reasoning into the incident log as we went.
>
> Failover took 40 minutes, not the 10 the runbook claimed, because two services had hard-coded regional endpoints. We reconciled 1,400 orders from payment records over the next day, with no customer charged twice. During the incident I also handled the executive channel, with updates every 15 minutes, so the responders didn't have to.
>
> Afterwards, I didn't write the COE; the database team owned it, and their lead wrote it well. My contribution was the part beyond their area: a quarterly failover game day across all tier-0 services, and a CI check that rejects hard-coded regional endpoints. The next real failover, a year later, took eleven minutes."

**What the committee extracts:** precise about role; owned the riskiest judgment call, with the risk quantified; a decision log; honest about what went wrong in execution; protected the responders; credited the COE author; contributed the cross-org mechanism; measured the improvement. **L7 incident leadership.**

---

## 8. Adversarial Bar-Raiser Follow-Up Chains

### Chain A · "Whose fault was it?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What was your part in causing it?" | Ownership | "Nothing directly" | "The retry default was my design" |
| 2 | "Why did it seem like a good idea at the time?" | Reasoning | "It didn't, really" | "Providers' errors were almost always transient" |
| 3 | "What would someone else on the team say caused it?" | Perspective | Unsure | A fair description of contributing factors |
| 4 | "Did anyone warn you?" | Honesty | "No" (if untrue) | The honest answer, including any warnings ignored |
| 5 | "Who wrote the root cause section?" | Accountability | "The team" | "I did, about my own design" |

### Chain B · The first hour

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What was your role on the incident?" | Precision | "I led it" | "Technical lead; the IC was someone else" |
| 2 | "What was the riskiest decision?" | Judgment | Unsure | Disabling retries fleet-wide, or the failover |
| 3 | "How did you know it was the right call?" | Evidence | "Instinct" | The data at minute 12 |
| 4 | "What could have gone wrong with it?" | Risk awareness | Nothing | Surfacing every transient error to users |
| 5 | "How did you communicate with leadership?" | Communication | "My manager handled it" | Cadence, content and the shielding of responders |

### Chain C · Systemic repair 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What prevents this class of failure, not just this instance?" | Systems thinking | "We reduced retries" | Retry budgets plus a slow-dependency load test |
| 2 | "How many services did the fix reach?" | Scope | "Ours" | All 300, through the library |
| 3 | "How do you know it works?" | Evidence | "No incidents since" | Three similar slowdowns, none became outages |
| 4 | "What would break it?" | Limits | Nothing | An honest residual risk |

### Chain D · The bad bet

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "When did you first suspect it was wrong?" | Self-awareness | "When it failed" | Month six, and the signs |
| 2 | "Why did it take four more months?" | Honesty | Defends it | "I explained the signs away. I regret that." |
| 3 | "Who did you tell first?" | Courage | "Leadership found out" | "The director and the TLs, before anyone escalated" |
| 4 | "What did it cost?" | Accountability | Vague | About three quarters of reduced delivery |
| 5 | "Would you split a monolith again?" | Learning | "No" (over-correction) | "Yes, with boundaries drawn from change data and a tripwire" |

### Chain E · "What changed in you?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "What do you do differently now?" | Learning | "Test more" | A specific practice |
| 2 | "Give me an example of using that since." | Evidence | None | A later decision made differently |
| 3 | "What did the people who worked on it think?" | Relationships | Unknown | Their view, honestly |
| 4 | "Would your old team trust your designs now?" | Earn Trust | "I think so" | Evidence: they asked for the next design review |

---

## 9. Checklist

- [ ] Two failure stories: one outage you caused or led, one judgment-based bet.
- [ ] The failure is proportionate to your target level.
- [ ] Ownership in the first sentence.
- [ ] Impact quantified: customers, revenue, trust.
- [ ] "Why it seemed right at the time", separating decision quality from outcome.
- [ ] Your role in the incident stated precisely.
- [ ] A systemic fix that prevents the class of failure, with evidence over time.
- [ ] A specific, durable change in your judgment, with a later example of applying it.

## 10. References

- Google, *Site Reliability Engineering* (O'Reilly, 2016), "Managing Incidents". <https://sre.google/sre-book/managing-incidents/>
- Richard I. Cook, "How Complex Systems Fail" (1998): why failures have multiple contributing causes. <https://how.complexsystems.fail/>
- Marc Brooker, "Timeouts, retries, and backoff with jitter", *Amazon Builders' Library*: the technical depth behind 7.1. <https://aws.amazon.com/builders-library/timeouts-retries-and-backoff-with-jitter/>
- In this KB: [02.1 Earn Trust](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/01-amazon-16-leadership-principles-l6-l7-bar-raiser-deep-dive.md) · [04.2 Calculated risk and tripwires](../04-Ambiguity-Technical-Vision-and-Calculated-Risk/02-one-way-vs-two-way-doors-deciding-with-70-percent-information.md) · [05.2 COEs and guardrails](02-coe-blameless-postmortems-and-systemic-org-wide-guardrails.md) · [05.3 Feedback and mentoring](03-delivering-hard-feedback-handling-low-performers-and-mentoring-l5s.md)
