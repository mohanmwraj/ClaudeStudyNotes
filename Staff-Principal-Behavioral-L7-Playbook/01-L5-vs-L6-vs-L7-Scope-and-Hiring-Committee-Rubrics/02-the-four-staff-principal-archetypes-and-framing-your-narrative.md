# 01.2 · The Four Staff/Principal Archetypes, and Framing Your Narrative

> **Folder 01 · File 2 of 3.** Every committee eventually asks, out loud or in its head: *what kind of Staff or Principal engineer is this, and do we need that kind?* A loop with six excellent but unrelated stories leaves the committee to answer that for you. A loop where every story reinforces one recognisable identity, with deliberate range around it, makes the answer easy.
>
> This file covers:
> - Will Larson's four archetypes (Tech Lead, Architect, Solver, Right Hand) as interview evidence;
> - Tanya Reilly's three pillars (big-picture thinking, cross-boundary execution, leveling up) as the lens committees actually apply;
> - how to choose a primary archetype and build a narrative spine;
> - the failure mode each archetype slides into under probing;
> - a scoring rubric, an L5 and an L7 telling of one story per archetype, and follow-up chains per archetype.
>
> Archetype descriptions are paraphrased from Larson's *Staff Engineer* and staffeng.com. Company tendencies (§4) are practitioner observation ⚠, not policy. Example stories are **illustrative composites**.

---

## 1. Why archetypes matter in an interview

Larson's observation is that "Staff engineer" is not one job. Organisations need several distinct shapes of senior IC leadership, and people who succeed at that level usually fit one shape primarily.

For interviews this has three consequences:

1. **The role you're interviewing for has a shape.** A platform org hiring its first Principal for event infrastructure wants an Architect. A product org with a struggling four-team program wants a Tech Lead. A reliability org drowning in incidents wants a Solver. Ask which shape it is (§5.3).
2. **Your stories should add up.** Committees reason from patterns. Five stories that each show the same strength from a different angle (conflict, failure, ambiguity, people) produce a confident packet. Five stories that each show a different strength produce "talented, but unclear what they'd do here".
3. **Each archetype has a characteristic way of failing under probing.** Knowing yours lets you pre-empt it (§3).

## 2. The four archetypes as interview evidence

| Archetype | What they do (paraphrased from Larson) | Evidence committees look for | Typical home | Failure mode when probed |
|---|---|---|---|---|
| **Tech Lead** | Guides the approach and execution of one team or a small cluster of teams, in close partnership with their manager(s) | Delivery across teams under ambiguity; technical decisions that unblocked execution; a team that got better; scope cut decisively | Product orgs; programs with several teams and a deadline | **Manager-lite**: coordination without technical decisions; "I ran the standups" |
| **Architect** | Owns the direction, quality and approach of a critical technical area across teams, combining deep technical knowledge with org-level leadership | A multi-year direction that got adopted and built; standards and contracts; trade-offs explained; designs that aged well | Platform and infrastructure orgs; core domains (payments, identity, data) | **Ivory tower**: designs that weren't built; "I defined the vision"; no adoption numbers |
| **Solver** | Digs into arbitrarily complex problems and finds a path; some stay in one area, others move hotspot to hotspot as leadership directs | Hard problems nobody else could crack; depth on demand; root causes across layers; the fix generalised into a mechanism | Reliability, performance, scaling crises, migrations gone wrong | **Hero**: brilliant firefights with no lasting mechanism; the org depends on them |
| **Right Hand** | Extends an executive's attention, borrowing their scope and authority to run complex organisations; adds leadership bandwidth | Org-wide programs; decisions made on the executive's behalf; operating cadence; problems found across many teams | Large orgs, often an internal promotion rather than an external hire | **Proxy**: authority borrowed, judgment unshown; "the VP asked me to" |

**Most strong candidates are a primary archetype with a secondary.** Common blends:
- Architect + Solver (the platform principal who also gets pulled into the worst incidents);
- Tech Lead + Architect (the program lead who also sets the domain's direction);
- Solver + Right Hand (the troubleshooter a VP sends into failing programs).

## 3. Reilly's lens: the three pillars committees apply

Tanya Reilly frames Staff work as three pillars. They map almost exactly onto what L6/L7 rubrics probe, whatever the company calls them.

| Pillar | What it means | Interview evidence | Which archetype shows it naturally | Which archetype must work to show it |
|---|---|---|---|---|
| **Big-picture thinking** | Seeing beyond the team: the business, the strategy, the multi-year arc; choosing what to work on | Problem discovery; framing technical risk as business risk; saying no to the wrong project | Architect, Right Hand | Tech Lead, Solver |
| **Execution across boundaries** | Making projects happen across teams, through ambiguity, conflict and failure | Multi-team delivery; resolving deadlocks; sequencing risk | Tech Lead, Right Hand | Architect |
| **Leveling up** | Making others better: mentoring, sponsoring, raising standards, creating owners | People who grew; review standards; paved roads; teaching through the work | Tech Lead | Solver (the "hero" trap) |

Two more of Reilly's ideas are directly usable in interviews.

**Her "maps" of the organisation.** She describes knowing where you are, what the terrain looks like (the politics, the hidden constraints), and where the treasure is (the goal worth reaching). In interview terms, an L7 story shows you **understood the terrain before you moved**:
- who owned what;
- whose roadmap the work would collide with;
- which executive cared about which risk;
- why this problem had stayed unsolved.

**"Being glue."** Reilly's essay on glue work: the unglamorous coordination, onboarding, documentation and unblocking that makes teams succeed, and that is often invisible, especially when women do it. Glue work is genuinely Staff work, but it is **easy to tell as non-technical coordination, which reads as L5 or TPM**. The fix is to tell glue work as **leverage with a technical core**:

| Glue work told as coordination (reads as down-level) | The same work told as Staff leverage |
|---|---|
| "I organised the cross-team syncs and wrote the docs." | "Three teams kept breaking each other's schemas. I designed a contract-test gate in CI and wrote the migration guide. Breaking changes went from about two a week to zero, and I stopped needing the syncs." |
| "I onboarded new engineers." | "Onboarding took six weeks because the local environment needed tribal knowledge. I built the dev-environment template and the first-week project path. New engineers now ship to production in week one." |

## 4. Archetype and company fit (practitioner observation ⚠)

These are tendencies, not rules. Teams within each company vary more than companies do.

| Company | Archetypes that commonly land well at L6/L7 | What their loops tend to stress |
|---|---|---|
| **Amazon** (L6/L7) | Architect for a business area, Solver | Ownership of outcomes; Think Big with Dive Deep; written narratives (six-pagers, PR/FAQs); being right with data |
| **Google** (L6/L7) | Tech Lead, Architect | Design-doc culture; technical leadership through consensus; navigating ambiguity; Googleyness (collaboration, humility) |
| **Meta** (E6/E7) | Tech Lead across a team of teams, Solver | Driving results and velocity; unblocking; direction in ambiguity; growth from feedback |
| **Stripe** | Solver, Architect | Rigor and craft; user impact; clear writing; meticulousness |
| **Netflix** | Solver, Architect with strong autonomy | Judgment with context, not control; candour; high talent density |
| **Uber** | Tech Lead, Solver | Execution at scale; operational ownership; customer-obsessed trade-offs |

**Right Hand** is the archetype least often hired from outside. If it's your primary, lead with the *decisions and problems* inside the programs you ran, so you read as an Architect or Solver who also operates at executive altitude, not as a delegate.

## 5. Building your narrative spine

### 5.1 The identity sentence

Write one sentence you could say in the first minute of any loop, and that every story will support. The form: archetype, domain, signature move, evidence.

- *Architect:* "I'm the engineer who sets direction for event and data infrastructure. My signature is finding the scaling or cost wall a year before we hit it, and turning that into a platform plan the org funds. The marketplace event platform is the clearest example."
- *Solver:* "I get pulled into the hardest reliability and performance problems across the platform. I find root causes that span layers, then turn the fix into a guardrail so the class of problem doesn't recur."
- *Tech Lead:* "I lead multi-team technical programs through ambiguity. I find the decision that unblocks five teams and make it, and the teams get better while we ship."

### 5.2 Range around the spine

A primary archetype isn't enough on its own. Committees check you can operate in the other pillars when the job requires it. Every packet needs:

| Archetype | What you must also show, and how |
|---|---|
| Architect | Execution: one story where you personally drove delivery through a hard cutover or setback |
| Solver | Leverage: one story where the fix became a mechanism, or where you grew someone into owning the area |
| Tech Lead | Big picture: one story where you changed *what* was built, not just how fast |
| Right Hand | Technical depth: one story where you made a hard technical call yourself and can draw it |

### 5.3 Ask which archetype the role needs

In the recruiter screen or the hiring-manager conversation, ask: *"Is this role closer to setting technical direction for an area, leading a set of teams through a program, or being the person who goes into the hardest problems?"* The answer tells you which stories to lead with.

## 6. Hiring Committee Scoring Rubric (by archetype)

| Archetype | Strong Hire at L7 | Hire at L6 | Down-level to L5 |
|---|---|---|---|
| **Tech Lead** | Led a program across a team of teams where the hardest problem was ambiguity or conflict, not workload; made the scoping and technical calls that changed the outcome; the teams' capability visibly grew; delivered business impact | Led a multi-team project to delivery; made key technical decisions; resolved cross-team blockers | Led their own team's work well; coordination without cross-team technical decisions |
| **Architect** | Set a multi-year direction for a critical area that was **adopted and built**; standards others now enforce; explains the trade-offs and what they'd change; tied to business strategy | Designed a cross-team architecture that shipped; explained the trade-offs | Designed a service; direction-setting not evidenced, or not adopted |
| **Solver** | Cracked problems others had failed on, spanning layers and teams; generalised the fix into org mechanisms; chosen by leadership for the next crisis because of the track record | Solved hard cross-team problems with depth; some generalisation | Strong debugging inside their own system; no mechanism; no cross-team reach |
| **Right Hand** | Ran an executive's priority program across many teams, made consequential decisions within delegated authority, and found problems the executive hadn't seen | Ran cross-team programs on behalf of a leader with clear technical contribution | Executed an executive's plan; decisions and judgment not visible |

**Red flags that apply to every archetype:**
- the archetype is claimed, but the stories show a different one;
- no range story;
- the signature move appears in only one story.

## 7. Story Blueprints (one per archetype)

### 7.1 Tech Lead (composite: a four-team checkout re-platform)

#### How an L5 tells it

> "I was the tech lead for the checkout migration. I broke the work into milestones, ran the weekly syncs with the four teams, tracked dependencies, and we launched on time in Q4. I also mentored two engineers on my team."

#### How an L7 tells it

> "Checkout had to move off the monolith before the holiday freeze. Four teams were involved, and the program was failing in a specific way: each team had a different idea of who owned payment-state consistency during the dual-run period. So every design review re-litigated it.
>
> I made the call that the orchestration service owned the state machine, and the other three teams consumed events. I wrote that up as a one-page decision record with the failure modes it closed. I took the payments TL, who disagreed, through the three reconciliation failures his alternative left open, and he agreed.
>
> I also cut scope. Split-tender payments moved to January, after I showed the VP that they carried 60% of the cutover risk for 3% of the order volume.
>
> We cut over three weeks before the freeze, with zero payment-state incidents through peak. Checkout p99 fell from 1.4 s to 450 ms. The part I'm proudest of: two of the four TLs ran the January split-tender launch with the decision-record format, and I wasn't in the room."

**What changed:**
- the problem is named as *ambiguity of ownership*, not workload;
- one decisive technical call, written down, with the dissent resolved;
- a scope cut argued with risk data;
- business and technical impact;
- leverage visible because the next launch ran without them.

### 7.2 Architect (composite: multi-region direction for a payments ledger)

#### How an L5 tells it

> "I designed the multi-region setup for our ledger service. I evaluated a few databases, picked one with strong consistency, and wrote the design doc. The team implemented it over two quarters."

#### How an L7 tells it

> "Our ledger ran in one region. Expansion into the EU made two things inevitable within 18 months: data-residency requirements, and an availability target our single region couldn't meet. Five teams had each started their own 'multi-region' plans with incompatible consistency assumptions.
>
> I wrote the direction for the whole payments domain:
> - EU data is homed in the EU;
> - the ledger uses per-account home regions with synchronous writes in the home region;
> - cross-region reads are asynchronous, with explicit staleness bounds;
> - a global sequencer for the cases that truly need total order: settlement batches, and nothing else.
>
> I compared it with a globally consistent database and with active-passive failover. The global option met consistency but added cross-region latency to every write, which put the p99 budget out of reach. Active-passive didn't meet residency.
>
> The friction was the fraud team. They needed a global view of recent transactions in under a second, and per-account homing broke that. Rather than overrule them, I added a replicated fraud-signal stream with a 500 ms freshness SLO, which was what they actually needed. I took the direction through the architecture council and the VP, and published the consistency contract as the domain standard.
>
> Eighteen months later, all five teams are on it. EU launch passed the residency audit first time. Availability went from 99.9% to 99.99% on the payment path. I'd change one thing: I underestimated the operational cost of the sequencer. We've since narrowed its use further."

**What changed:**
- the direction is driven by business events (expansion, regulation), not technology preference;
- alternatives were rejected on stated constraints;
- conflict between valid priorities was resolved by synthesis (the fraud-signal stream), not victory;
- adoption numbers and an outcome that aged;
- an honest regret.

### 7.3 Solver (composite: a p99 regression across layers)

#### How an L5 tells it

> "We had a latency regression in our service. I profiled it, found GC pauses were the issue, tuned the JVM flags, and p99 went back to normal."

#### How an L7 tells it

> "Order-search p99 had roughly doubled over a month. Two teams had each fixed something and declared victory, and it kept coming back. Leadership asked me to take it.
>
> The regression wasn't one cause:
> 1. A heap-size change had lengthened GC pauses past the Kafka consumers' session timeout.
> 2. That triggered consumer-group rebalance storms.
> 3. The storms caused bursts of re-processing that saturated the search cluster.
>
> Each team had seen a third of it. I proved the chain by correlating GC logs, rebalance events and cluster queue depth on one timeline, and by reproducing it in a load test where each fix removed exactly its third.
>
> The fix was three changes across three teams:
> - pause-time-bounded GC settings;
> - cooperative rebalancing with static membership;
> - admission control on the search cluster.
>
> The part that mattered more was the guardrail. I added a pre-deploy check that compares a service's GC pause distribution against its consumers' session timeouts, and an alert on rebalance rate across all consumer groups. In the following year it caught four regressions of the same class before customers saw them. Search p99 went from 900 ms back to 380 ms, and the SRE lead now owns the rebalance dashboards org-wide."

**What changed:**
- the problem had defeated others (why it needed a Solver);
- a multi-layer causal chain, *proven* rather than asserted;
- fixes across team boundaries;
- the fix generalised into a mechanism, with evidence that it worked;
- ownership handed off. That's the hero trap avoided.

### 7.4 Right Hand (composite: a VP's availability program)

#### How an L5 tells it

> "My VP asked me to run the reliability program. I set up the SLO reviews, tracked action items from postmortems, and reported progress monthly."

#### How an L7 tells it

> "Our VP had a board-level commitment to cut customer-facing incidents by half. Twenty teams were involved. She asked me to run it with her authority, and I made three calls she then backed publicly.
>
> **First**, I chose error budgets tied to release gating over a central reliability team. A central team would have absorbed the work without changing how teams shipped.
>
> **Second**, I found the real concentration. From a year of postmortems, 60% of severe incidents traced to just two shared dependencies: the config service and the identity token cache. So I redirected two quarters of platform capacity there, against both owning teams' existing roadmaps.
>
> **Third**, I negotiated a carve-out for the three teams in the middle of a migration. Gating them would have stopped the migration that removed half their incident load.
>
> Severe incidents fell 58% in three quarters. The two dependencies went from the top two incident sources to the bottom half. The error-budget policy is now the org's standard. The VP's staff meeting runs the monthly review without me, using the scorecard I designed."

**What changed:**
- the decisions are *theirs*, with the executive backing them, not the reverse;
- a data-driven finding that redirected investment;
- a nuanced exception that shows judgment;
- an outcome and a mechanism that outlived their involvement.

## 8. Adversarial Bar-Raiser Follow-Up Chains (by archetype)

### Chain T · Tech Lead: "what did *you* decide?"

| # | Probe | Tests | Weak answer | Strong answer |
|---|---|---|---|---|
| 1 | "What did your manager do on this program, versus you?" | Separation from management | Blurry | "She handled staffing and the exec updates. I owned the technical plan, the ownership decision and the scope cut." |
| 2 | "Which decision changed the outcome most?" | Decisiveness | "Good planning" | "Making orchestration own the state machine" |
| 3 | "Who disagreed with it?" | Friction | "No one" | "The payments TL. Here was his argument." |
| 4 | "What did you cut, and who was unhappy?" | Scope judgment | "We delivered everything" | "Split-tender. Product was unhappy until I showed the risk-to-volume ratio." |
| 5 | "How did the teams change?" | Leveling up | Generic | "Two TLs adopted the decision-record format and ran the next launch" |

### Chain A · Architect: "did it get built?" 🔥

| # | Probe | Tests | Weak answer | Strong answer |
|---|---|---|---|---|
| 1 | "How many teams adopted it, and how did you know?" | Adoption | "It's the standard" | "Five of five; the consistency contract is checked in design review" |
| 2 | "What did you build yourself?" | Hands-on credibility | "I focused on the vision" | "The sequencer prototype and the contract tests" |
| 3 | "Which part of your direction was wrong?" | Calibration | "None" | "The sequencer's operational cost. We narrowed it." |
| 4 | "Who would have chosen differently, and why?" | Trade-off honesty | Dismisses | "A global-database advocate. Their argument was simplicity, and it's a fair one below our latency budget." |
| 5 | "What would make you revisit the direction?" | Reversibility | "Nothing" | "If cross-region write latency dropped under X, or residency rules changed" |

### Chain S · Solver: "and after you left?"

| # | Probe | Tests | Weak answer | Strong answer |
|---|---|---|---|---|
| 1 | "Why hadn't the other teams solved it?" | Real difficulty | "They weren't good enough" (red flag) | "Each saw one layer; nobody had the timeline across the three systems" |
| 2 | "How did you prove the causal chain?" | Rigor | "It was obvious from the logs" | Correlated timeline plus a reproduction where each fix removed its share |
| 3 | "What stops it recurring?" | Mechanism | "We're careful now" | The pre-deploy check and the alert, and the four catches since |
| 4 | "Who owns it now?" | Hero trap | "I still keep an eye on it" | The named owner and their dashboards |
| 5 | "What did you get wrong along the way?" | Honesty | "Nothing" | "I chased the GC theory alone for a week. The rebalance data was there on day two." |

### Chain R · Right Hand: "whose judgment was it?"

| # | Probe | Tests | Weak answer | Strong answer |
|---|---|---|---|---|
| 1 | "Which decisions did you make that the VP didn't?" | Own judgment | "I implemented her strategy" | The three calls, with her backing after the fact |
| 2 | "Where did you disagree with the VP?" | Backbone | "We were aligned" | "She wanted a central reliability team. I argued for error budgets with release gating." |
| 3 | "How did you get teams to do it without being their manager?" | Influence | "The VP mandated it" | "The data on the two dependencies, and a carve-out that showed it wasn't bureaucracy" |
| 4 | "What did you find that she hadn't seen?" | Big picture | Nothing specific | "The 60% concentration in two dependencies" |
| 5 | "What's technical about this story?" | Depth | Struggles | Can explain the config-service and token-cache failure modes in detail |

## 9. Checklist

- [ ] One primary archetype and one secondary, chosen for the role being hired.
- [ ] An identity sentence: archetype, domain, signature move, flagship evidence.
- [ ] Every story reinforces the spine; at least one deliberate range story.
- [ ] Each archetype's failure mode pre-empted in the telling (manager-lite, ivory tower, hero, proxy).
- [ ] Glue work told as leverage with a technical core.
- [ ] You've asked which shape of Staff engineer the role needs.

## 10. References

- Will Larson, *Staff Engineer: Leadership beyond the management track* (2021). <https://staffeng.com/book>
- Will Larson, *Staff archetypes*. <https://staffeng.com/guides/staff-archetypes>
- Tanya Reilly, *The Staff Engineer's Path* (O'Reilly, 2022; ISBN 978-1-098-11873-0). Author's page: <https://www.noidea.dog/staff>
- Tanya Reilly, *Being Glue*. <https://www.noidea.dog/glue>
- In this KB: [01.1 Scope detection](01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md) · [01.3 Beyond STAR](03-beyond-star-the-l7-executive-storytelling-architecture.md)
