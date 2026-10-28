# 01.3 · Beyond STAR: the L7 Executive Storytelling Architecture

> **Folder 01 · File 3 of 3.** STAR (Situation, Task, Action, Result) is a fine scaffold for L3–L5. At L6/L7 it actively hurts you:
> - it spends the first minute on chronology;
> - it frames the work as *assigned*;
> - it turns decisions into an activity log;
> - it ends on a number without stakes.
>
> Worst of all, it has no slot for the three things committees most need at L6/L7: **the alternatives you rejected, the people you had to move, and the business consequence**.
>
> This file replaces STAR with a six-beat architecture: **CARL + Trade-off + Org-Leverage**. It covers what the committee extracts from each beat, time budgets, the grammar of ownership ("I" vs "we"), the impact ladder for numbers, and the "accordion" that lets one story run for 30 seconds or 20 minutes. Then the same story is told in STAR and in the L7 architecture, annotated beat by beat, followed by a rubric, follow-up chains per beat and a worksheet.
>
> Example stories are **illustrative composites**. Use the structure; fill it with your own facts.

---

## 1. Why STAR sounds junior at L6/L7

The same competent engineer, the same project, told in textbook STAR:

> "**Situation:** At my company we had a pricing pipeline that ran nightly as a batch job. It was built five years ago on our on-prem Hadoop cluster and later moved to the cloud. The team was six people, and we supported pricing analysts and the merchandising team. **Task:** My manager asked me to improve the freshness of prices. **Action:** I researched streaming frameworks, built a proof of concept with Apache Beam, migrated the pipeline to streaming, set up monitoring, and wrote documentation. I worked with the merchandising team to test it. **Result:** Price freshness improved from 24 hours to a few minutes, and the business was happy."

Five structural defects, each of which the writeup will expose:

| STAR defect | What it does to the writeup | What the committee concludes |
|---|---|---|
| **Situation is chronology.** Ninety seconds on history and team size. | Nothing quotable in the first minute | "Candidate struggled to get to the point" |
| **Task is assignment.** "My manager asked me to…" | Problem origin = someone else | "Executes well-defined goals": L5 |
| **Action is an activity log.** Researched, built, migrated, documented. | No decisions, no alternatives, no friction | "Unclear what judgment was exercised" |
| **Result is a vanity metric.** "24 h → minutes; the business was happy." | No baseline window, no business translation, no cost | "Impact not quantified at business level" |
| **No learning or leverage.** | No evidence of growth or of anything that persists | "No reflection; single-project scope" |

None of these are speaking-style problems. They are **missing evidence**. The L7 architecture is a checklist that forces each kind of evidence into the story.

## 2. The architecture: CARL + Trade-off + Org-Leverage

CARL (Context, Action, Result, Learning) is the common upgrade to STAR. For L6/L7 the *Action* beat is too coarse: it hides the three behaviors committees grade hardest. So split it, and widen *Learning* into *Learning and Leverage*:

| # | Beat | The committee is grading | Budget in a ~3-minute opening |
|---|---|---|---|
| 0 | **Headline** | Whether you can lead with the point | 10–15 s |
| 1 | **C · Context and business risk** | Big-picture thinking; problem discovery; why now | 25–35 s |
| 2 | **T · Trade-off: competing alternatives** | Judgment; technical depth; explicit criteria | 25–35 s |
| 3 | **O · Org alignment and friction** | Influence without authority; empathy; backbone | 30–45 s |
| 4 | **A · Decisive execution** | Ownership; the "I"; handling setbacks | 30–40 s |
| 5 | **R · Quantified business and systemic impact** | Results at the right altitude; measurement honesty | 15–25 s |
| 6 | **L · Learning and leverage** | Self-awareness; what persists; who grew | 10–20 s |

The opening runs about three minutes. Then **stop**. The interviewer will choose where to dig, and a strong opening has planted hooks in each beat for them to pull (§6).

### 2.0 Headline: lead with the level

The first sentence should carry all of the following, in under 15 seconds:
- the problem;
- the stakes;
- your role;
- the outcome.

> "This is about how I moved pricing from nightly batch to near-real-time for our most volatile products. We were losing an estimated $X M a year in margin to stale prices. I designed the tiered architecture, aligned pricing science and merchandising on it, and led the migration. It recovered most of that margin, and the price-event contract became the standard for two other teams."

If the interviewer stopped you there, they could still write a useful line in the packet. That's the test for a headline.

### 2.1 C · Context and business risk

**Purpose:** establish why this mattered *to the business*, why *now*, and why it hadn't been solved.

**What to include:**
- the business mechanism, e.g. "competitors reprice within the hour; we reprice nightly; the gap is margin";
- the size of the exposure (a range is fine);
- the trigger: why now;
- why it was unowned or unsolved;
- *how you found or framed it*. This is problem origin, the single most level-defining fact (01.1 §3).

| Anti-pattern | L7 version |
|---|---|
| "We had a legacy batch pipeline built five years ago…" | "Our prices lagged competitors by up to 24 hours on the 5% of SKUs that drive 40% of price-sensitive revenue." |
| "My manager asked me to improve freshness." | "I'd been looking at margin-leakage reports for an unrelated project, and the pattern pointed at price latency. I took it to my director with an estimate." |
| No number | "Finance's estimate, which I helped build, was $X–1.5X M a year." |

### 2.2 T · Trade-off: competing alternatives

**Purpose:** prove you chose. You need two or three real options, the **criteria**, the decisive data, and the **cost** of the winner.

**What to include:**
- the options as a set (one clause each);
- the criteria in priority order;
- the deciding fact or experiment;
- what you gave up;
- optionally, what would make you revisit the choice.

**The test of a real alternative:** a reasonable senior engineer would have chosen it. A strawman ("or we could do nothing") is worse than no alternatives, because interviewers notice.

| Anti-pattern | L7 version |
|---|---|
| "I researched streaming frameworks and picked Beam." | "Three options: run the batch every 15 minutes; stream the full catalog; or stream only the volatile tier and keep batch for the long tail." |
| No criteria | "The criteria were freshness for the volatile tier, consistency for the pricing-science models, and cost, in that order." |
| No cost | "Tiering cost us one more moving part: a reconciliation job that keeps the two tiers consistent at the model's daily snapshot." |

### 2.3 O · Org alignment and friction

**Purpose:** show influence without authority. Who had to agree, who didn't, what their position was, and how it was resolved.

At L6/L7, the best friction is **between competing valid priorities**, not between a right you and a wrong them. Folder 02 calls the alternative "the technical-conflict trap".

**What to include:**
- the stakeholders who could block, by role;
- their real position, *steelmanned*;
- the mechanism that resolved it: data, a prototype, a reframing, a concession, or a synthesis that met both core constraints;
- what you conceded;
- the decision-maker, if it wasn't you.

| Anti-pattern | L7 version |
|---|---|
| "I worked closely with stakeholders." | "Pricing science objected, and they were right to: their elasticity models needed one consistent snapshot of the full catalog, and streaming prices would make the inputs drift intraday." |
| "I convinced them with a benchmark." | "So the tiers reconcile into a single daily snapshot at a fixed cut-off. Merchandising got minutes on the volatile tier, science kept its snapshot. I gave up streaming the long tail, which I'd wanted for simplicity." |
| "Leadership approved." | "My director decided between my plan and the 15-minute batch. The deciding argument was cost: 15-minute batch meant re-reading the full catalog 96 times a day." |

### 2.4 A · Decisive execution

**Purpose:** isolate *your* actions: the decisions, artifacts, conversations and interventions, especially at the moment it nearly failed.

**What to include:**
- the two or three things only you did;
- how you sequenced the risk (shadow mode, canary, kill switch);
- the setback, and what you did about it;
- the team's work, credited by name and role.

**The grammar of this beat (§3):** "I" for decisions and interventions; "we" for the team's execution; names for credit.

| Anti-pattern | L7 version |
|---|---|
| "We migrated the pipeline and set up monitoring." | "I ran the streaming tier in shadow for three weeks, comparing every price against batch. Ravi built the comparator; I set the cutover gate at a 0.1% divergence rate." |
| "It went smoothly." | "Week two, the comparator showed 2% divergence on promo SKUs. Promotions were applied in batch after pricing, and the stream had no equivalent. I paused cutover and made promotions an input event, which cost us two weeks." |

### 2.5 R · Quantified business and systemic impact

**Purpose:** prove the outcome at the altitude of the level, honestly measured.

**The impact ladder.** Climb as high as the evidence lets you:

| Rung | Example | Required at |
|---|---|---|
| Technical metric | "Freshness p95 on the volatile tier went from 24 h to 4 min" | L5+ |
| Product/user metric | "Price-match requests from stores fell 70%" | L5+ |
| Business metric | "Finance attributed $X M/yr in recovered margin, with a range" | **L6+** |
| Systemic capability | "The price-event contract became the standard; promotions and markdowns reused it" | **L7** |
| People | "Ravi now owns the streaming tier; he led the markdown integration" | **L7** |

**Measurement honesty is itself a signal:**
- give the window;
- give the baseline;
- say how it was attributed (A/B, holdout, before/after with a control);
- name what you can't separate from other changes.

"About 60–70% of the margin gap, per finance's holdout on 10% of SKUs" is stronger than "100%".

### 2.6 L · Learning and leverage

**Purpose:** show that your judgment changed, and that something remains.

| Generic (reads as nothing) | Specific (reads as growth) |
|---|---|
| "I learned communication is important." | "My first instinct was to stream everything, because it was simpler for my team to operate. I learned to start from the consumers' consistency needs, not from my operational convenience. I now ask 'who needs which guarantee' before choosing an architecture." |
| "It was a great learning experience." | "I now build the comparator before the new system. It turned a risky cutover into a data question." |

**Leverage:** the mechanism, standard or person that keeps paying without you.

## 3. The grammar of ownership

Amazon calls it **"I" vs "we"** and Folder 02 dissects it per LP. The rules below work everywhere.

1. **"I" for decisions, artifacts, conversations and interventions.** "I recommended", "I wrote", "I sat down with", "I paused the cutover".
2. **"We" for team execution and shared outcomes.** "We ran in shadow for three weeks." "We hit the gate in week five."
3. **Credit by name and role, specifically.** "Ravi built the comparator", not "the team was amazing". Specific credit *raises* your credibility, because it shows you know exactly who did what, including you.
4. **Name the decision-maker when it wasn't you.** "My director chose between the two plans." Hiding it gets exposed by the decision-rights probe (01.1 §8, Chain A) and costs trust. Showing it, plus what you did to shape the decision, is strong.
5. **No hedges on your own actions.** "I kind of helped with", "I was sort of responsible for" and "I tried to" all read as passenger language. If you did it, say so. If you didn't, don't claim it.
6. **Present tense for standards that still hold.** "The contract *is* the standard" signals that it persists.

| Passenger grammar | Owner grammar |
|---|---|
| "We decided to use tiering." | "I proposed tiering; my director approved it over the 15-minute batch." |
| "I helped with the migration." | "I led the migration; Ravi and Mei built the streaming tier." |
| "The team worked with science on the requirements." | "I sat with the head of pricing science for an afternoon to understand what the models actually needed." |

## 4. The accordion: one story, three lengths

Prepare every core story at three lengths. Interviewers will ask for each.

| Length | When it's used | Contents |
|---|---|---|
| **30 seconds** | "Give me a quick overview of your biggest project", an intro, or a hiring-manager screen | The headline (§2.0), plus one sentence of impact |
| **3 minutes** | The standard behavioral prompt | Beats 0–6, then stop |
| **15–20 minutes** | Deep-dive rounds, Amazon LP probing, "walk me through it in detail" | Every beat expanded, plus **the hardest-decision zoom-in** (§4.1), plus the setback, plus counterfactuals |

### 4.1 Prepare the hardest-decision zoom-in

For every story, pre-build one decision you can go arbitrarily deep on. Know:
- the options;
- the data that decided it;
- the trade-off accepted;
- the risk you carried;
- what would change your mind;
- one detail only a participant would know (the comparator's false positives, the promo ordering bug).

Interviewers zoom into decisions to test authorship. A prepared zoom-in turns that test into your strongest five minutes.

## 5. Story Blueprints

### 5.1 The same story, told in STAR (L5) and in the L7 architecture

#### How an L5 tells it

> "At my company we had a pricing pipeline that ran nightly as a batch job. My manager asked me to improve the freshness of prices. I researched streaming frameworks, built a proof of concept with Apache Beam, migrated the pipeline to streaming, set up monitoring, and wrote documentation. I worked with the merchandising team to test it. Price freshness improved from 24 hours to a few minutes, and the business was happy."

#### How an L7 tells it

> **[Headline]** "This is about moving pricing from nightly batch to near-real-time for our most volatile products. We were losing an estimated $X M a year in margin to stale prices. I designed the tiered architecture, aligned pricing science and merchandising, and led the migration. It recovered most of that margin, and the price-event contract became the standard two other teams now use.
>
> **[C]** I found it sideways. I was reading margin-leakage reports for another project, and the losses clustered on SKUs where competitors repriced within the hour and we repriced overnight. That was about 5% of SKUs, but 40% of price-sensitive revenue. I built a rough estimate with finance, $X–1.5X M a year, and took it to my director. Nobody owned the problem: pricing owned the batch, merchandising owned the complaints.
>
> **[T]** I put three options to her:
> - run the batch every 15 minutes;
> - stream the full catalog;
> - stream only the volatile tier, with batch kept for the long tail.
>
> The criteria were freshness for the volatile tier, consistency for the pricing-science models, then cost. Fifteen-minute batch meant re-reading the full catalog 96 times a day, which was too expensive. Full streaming broke science's models. Tiering won, at the cost of a reconciliation job between the tiers.
>
> **[O]** The real negotiation was with pricing science. Their elasticity models need one consistent full-catalog snapshot, and intraday streaming would make the inputs drift. They were right. So the tiers reconcile into one snapshot at a fixed daily cut-off: merchandising got minutes on the volatile tier, and science kept its snapshot. I gave up streaming the long tail, which I'd wanted for simplicity. My director approved tiering over the 15-minute batch.
>
> **[A]** I ran the streaming tier in shadow for three weeks. Ravi built the comparator that checked every streamed price against batch, and I set the cutover gate at 0.1% divergence. In week two we hit 2% on promoted SKUs: promotions were applied in batch after pricing, and the stream had no equivalent. I paused cutover and made promotions an input event. That cost two weeks, and it would have caused wrong prices on the most visible products.
>
> **[R]** Freshness p95 on the volatile tier went from 24 hours to 4 minutes. Finance's holdout on 10% of SKUs attributed roughly 60–70% of the estimated margin gap as recovered. Batch compute fell about 30%, because the volatile tier left the nightly job. The price-event contract is now the standard; promotions and markdowns are built on it.
>
> **[L]** My first instinct, stream everything, optimized for my team's operations. I learned to start from what each consumer needs to be true, and I now build the comparator before the new system. Ravi owns the streaming tier now and led the markdown integration."

**Beat-by-beat annotation:**

| Beat | What the committee writes down |
|---|---|
| Headline | Business problem, stakes, role and outcome in one breath |
| C | **Found the problem** (problem origin = self); quantified it with finance; explained why it was unowned |
| T | Three real options; explicit, ordered criteria; the decisive cost argument; the cost of the winner |
| O | Competing *valid* priorities; steelmanned the other side; a synthesis met both core constraints; conceded something; decision-maker named |
| A | Own interventions isolated; risk sequenced with shadow mode and a numeric gate; a setback handled by pausing; specific credit |
| R | Technical, product and business metrics with honest attribution; a systemic capability |
| L | Changed judgment; a reusable practice; a person grown into ownership |

### 5.2 The architecture applied to a failure story

Failure stories use the same beats with a different emphasis. The *Trade-off* beat becomes **the bet you made and why it was reasonable at the time**. The *Execution* beat splits into **recovery** and **the systemic fix**. Folder 05 goes deep on this.

#### How an L5 tells it

> "I made a mistake when I deployed a schema change that broke the downstream reporting jobs. I rolled it back, fixed the issue, and added a test. I learned to be more careful with schema changes."

#### How an L7 tells it

> "I approved a schema-evolution policy that let producers add required fields under 'backward-compatible'. Three weeks later it broke the finance close: two consumers deserialised with old readers and silently dropped records. The quarter-end report was 0.8% short until we caught it. The policy was my call. I'd optimized for producer velocity, and I hadn't modeled readers that were pinned to old versions.
>
> I ran the recovery: froze schema changes, replayed the affected partitions from the retained log, and reconciled with finance before the filing deadline. The systemic fix was a compatibility gate in CI that checks every change against every *registered* reader version, not just the latest, plus a reader-version inventory owned by the platform team. It has blocked eleven unsafe changes since. What I changed in myself: I write the failure modes of a policy before I approve it, and I ask who isn't in the room."

## 6. Hiring Committee Scoring Rubric (by beat)

| Beat | Strong Hire at L7 | Hire at L6 | Down-level to L5 |
|---|---|---|---|
| Headline | Business problem, stakes, role, outcome in ≤ 15 s | Clear problem and role | Starts with history; point emerges late |
| C · Context and risk | Self-discovered or self-framed; business exposure quantified; why now; why unowned | Real cross-team problem, clearly framed | Assigned; technical framing only |
| T · Trade-off | 2–3 real options; ordered criteria; deciding data; cost of the winner; what would change the choice | Alternatives with rationale | One option, justified after the fact |
| O · Alignment | Competing valid priorities; steelmanned; synthesis or principled concession; senior decision-maker shaped | Peer TLs persuaded with evidence | "Worked with stakeholders"; no named friction |
| A · Execution | Own interventions isolated; risk sequenced; a setback handled; specific credit | Led delivery across teams | Activity list; "we" throughout |
| R · Impact | Business + technical + capability; honest attribution and ranges | Org-level technical metric | Team-level or vanity metric |
| L · Learning and leverage | Changed judgment; mechanism and people that persist | Reflective lesson | Generic lesson, or none |

## 7. Adversarial Bar-Raiser Follow-Up Chains (one per beat)

Each probe below is the natural next question when that beat is weak, and the natural test of authorship when it is strong.

| Beat | Probe 1 | Probe 2 | Probe 3 | Probe 4 | What a passenger reveals |
|---|---|---|---|---|---|
| **C** | "How did you first notice this?" | "How did you get to $X M? Who checked it?" | "Why hadn't anyone fixed it before?" | "What would have happened in a year without it?" | Can't explain discovery; the number came from someone else |
| **T** | "Why not the 15-minute batch?" | "What would have made full streaming the right call?" | "What did tiering cost you?" | "Which option would your skeptics have picked?" | Alternatives are strawmen; no cost; no criteria |
| **O** | "Who was the hardest person to convince?" | "What exactly did they say?" | "Were they right about anything?" | "What did you give up?" | No named person; friction resolved by authority |
| **A** | "What did you personally do in week two?" | "Who built the comparator, and what did you do?" | "What almost went wrong?" | "What would you have done if the gate never passed?" | Vague on own actions; no setback; credit absorbed |
| **R** | "How was the margin attributed?" | "What else changed that quarter?" | "What did it cost to run?" | "Who uses the contract now?" | Number without method; no capability |
| **L** | "What would you do differently?" | "Where was your judgment wrong?" | "Who owns it now?" | "What did the people involved go on to do?" | "Nothing"; hero dependence |

**Two meta-probes interviewers use across all beats:**
- **"Tell me something about this project that isn't in your answer."** Owners have a dozen; passengers have none.
- **"Let's go back to [beat]. Say more."** If the second telling contradicts the first in a detail, the writeup notes it.

## 8. Worksheet: build a story

```text
STORY: ______________________          TARGET LEVEL: L6 / L7      ARCHETYPE: ________

0  HEADLINE (≤ 15 s): problem + stakes + my role + outcome
   ____________________________________________________________

1  C  How did I find or frame it?  ____________________________
      Business mechanism + exposure (range) + source of the number  ______________
      Why now?  ______________   Why unowned / unsolved?  ______________

2  T  Option A / B / C (each one a reasonable senior engineer might choose)
      ______________ / ______________ / ______________
      Criteria in order: 1 ________ 2 ________ 3 ________
      Deciding fact or experiment: ______________
      Cost of the winner: ______________   What would change my mind: ______________

3  O  Who could block (role): ______________   Their position, steelmanned: ______________
      Mechanism: data / prototype / reframing / concession / synthesis  ______________
      What I conceded: ______________   Decision-maker: ______________

4  A  Only-I actions (2–3): ______________
      Risk sequencing: shadow / canary / gate / kill switch  ______________
      The setback and my response: ______________
      Credit by name and role: ______________

5  R  Technical: ________ (baseline, window)   Product/user: ________
      Business: ________ (attribution method, range)   Capability: ________

6  L  Judgment that changed: ______________   Practice I now use: ______________
      Mechanism or person that persists: ______________

ZOOM-IN DECISION: ______________  (options, data, trade-off, risk, a detail only I know)
30 s / 3 min / 15 min versions rehearsed:  [ ] [ ] [ ]
```

## 9. Self-scoring checklist (score every story, every rewrite)

- [ ] The headline would make a useful packet line on its own.
- [ ] Problem origin is me (found or framed), or I say honestly who handed it over and what I reframed.
- [ ] Business exposure is quantified, with a source.
- [ ] There are two or three alternatives a reasonable senior engineer might choose.
- [ ] The criteria are explicit and ordered; the winner's cost is stated.
- [ ] A named stakeholder role disagreed; their position is stated fairly.
- [ ] The resolution is a synthesis, a concession or evidence, not authority.
- [ ] Two or three only-I actions; specific credit to others.
- [ ] A setback, and what I did about it.
- [ ] Impact reaches the business rung, with honest attribution.
- [ ] Learning changes my judgment, not just my knowledge.
- [ ] Something (a person, a standard, a mechanism) persists without me.

Twelve out of twelve is an L7-shaped story. Nine to eleven is L6-shaped. Below nine, rewrite it before the loop.

## 10. References

- Amazon, *Leadership Principles* (the "I" vs "we" probing originates in LP-based interviewing). <https://www.amazon.jobs/content/en/our-workplace/leadership-principles>
- Jeff Bezos, *2016 Letter to Shareholders* (decision speed, disagree and commit). <https://www.aboutamazon.com/news/company-news/2016-letter-to-shareholders>
- Barbara Minto, *The Pyramid Principle* (the conclusion first, then the support): the source of the headline-first discipline.
- Tanya Reilly, *The Staff Engineer's Path* (O'Reilly, 2022; ISBN 978-1-098-11873-0). Author's page: <https://www.noidea.dog/staff>
- In this KB: [01.1 Scope detection](01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md) · [01.2 Archetypes](02-the-four-staff-principal-archetypes-and-framing-your-narrative.md)
