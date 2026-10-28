# 08.1 · The Eight Core Stories: a Matrix Mapping to Every FAANG Question

> **Folder 08 · File 1 of 3.** A senior behavioral loop asks four to six interviewers to probe you for an hour each, across perhaps twenty prompts. You can't prepare twenty separate stories to L7 depth; nobody can rehearse that many through twenty minutes of probing each. What works is the **Rule of 8**: eight deep stories, each told at L7 scope, each covering several competencies, and a map from any question to the story that answers it best.
>
> This file covers:
> - the eight stories, what each must contain, and where in this KB each is taught;
> - a coverage matrix against Amazon's sixteen LPs and Google's and Meta's signals;
> - a **54-question grid** mapping each question to a primary and backup story, with what to lead with;
> - re-weighting a story for the question asked, and keeping range across a loop;
> - a four-week preparation plan and a mock-drill protocol;
> - a rubric, two story blueprints and a follow-up chain set that stress-tests the bank.

---

## 1. The eight stories

| # | Story | What it must contain | Taught in |
|---|---|---|---|
| **1** | **Flagship Architecture / Ambiguity** | A problem you found or defined; real alternatives; a one-way door handled deliberately; multi-team execution; business and capability impact | [01.3](../01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/03-beyond-star-the-l7-executive-storytelling-architecture.md), [04.1](../04-Ambiguity-Technical-Vision-and-Calculated-Risk/01-identifying-unasked-existential-problems-and-writing-6-page-rfcs.md), [04.2](../04-Ambiguity-Technical-Vision-and-Calculated-Risk/02-one-way-vs-two-way-doors-deciding-with-70-percent-information.md) |
| **2** | **Cross-Team Conflict / Alignment** | Two legitimate priorities owned by capable people; a resolution neither proposed; both owners signed; a better relationship | [02.2](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/02-google-gnl-and-meta-jedi-conflict-direction-and-ambiguity.md), [03.1](../03-Influence-Without-Authority-and-Cross-Org-Alignment/01-resolving-architectural-wars-between-competing-principal-engineers.md) |
| **3** | **Catastrophic Failure / Outage and COE** | A failure proportionate to your scope, owned in the first sentence; first-hour judgment; multiple causal chains; an org-wide guardrail | [05.1](../05-Production-Outages-Mistakes-and-Psychological-Safety/01-owning-catastrophic-sev1-outages-and-bad-architectural-bets.md), [05.2](../05-Production-Outages-Mistakes-and-Psychological-Safety/02-coe-blameless-postmortems-and-systemic-org-wide-guardrails.md) |
| **4** | **Disagree and Commit** | You lost an argument with a senior decider; you owned the riskiest part of their plan; tripwires instead of re-litigation; you learned about your own judgment | [02.1 §4.2](../02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/01-amazon-16-leadership-principles-l6-l7-bar-raiser-deep-dive.md) |
| **5** | **Killing a Bad Idea / Pushing Back on Executives** | A senior leader's project or request; evidence first; the sponsor heard it first and made the call; an alternative; a people plan | [03.2](../03-Influence-Without-Authority-and-Cross-Org-Alignment/02-influencing-product-and-execs-killing-bad-projects-and-saying-no.md) |
| **6** | **Speed vs Quality / Tech Debt** | A mechanism (error budget, debt portfolio, loan terms) that lets the org make the trade-off without a fight; DORA-level evidence | [04.3](../04-Ambiguity-Technical-Vision-and-Calculated-Risk/03-balancing-tech-debt-reliability-freezes-and-feature-velocity.md) |
| **7** | **Upleveling / Mentorship** | Sponsorship of a named person into Staff-scope ownership; what you gave up and where you held back; what they do now | [05.3](../05-Production-Outages-Mistakes-and-Psychological-Safety/03-delivering-hard-feedback-handling-low-performers-and-mentoring-l5s.md) |
| **8** | **FinOps / Scaling Bottleneck** | A cost or scale limit found early; unit economics; reversible and irreversible levers separated; a mechanism; a 100× extrapolation | [06.2](../06-Translating-Technical-Backgrounds-into-L7-Stories/02-framing-performance-tuning-cost-finops-and-platform-tooling-stories.md), [06.3](../06-Translating-Technical-Backgrounds-into-L7-Stories/03-handling-the-lack-of-faang-scale-objection-with-complexity-depth.md) |

### 1.1 Rules for the bank

1. **Eight different projects where possible.** If two stories come from the same project, interviewers who compare notes in the debrief see less range.
2. **Stories 3 and 4 must be different events from stories 1 and 2.** A failure inside your flagship is fine as a detail, but not as your only failure story.
3. **At least one story from the last 18 months**, and most from the last three years (02.1 §8).
4. **Every story has a named counterpart who disagreed** and a **technical zoom-in** you can sustain for ten minutes.
5. **Keep a reserve.** Have two or three shorter stories (a second failure, a second conflict) for "give me another example".

### 1.2 The story card

Fill one card per story, on a single page:

```text
STORY #_  Title: ____________________   Period: ____   Your role: ____________
HEADLINE (one sentence, with the business stake and your decision):
C  Context and risk ......... the number at stake, why now, who owned what
T  Trade-off ................ options (incl. do nothing), criteria, the door type
O  Org alignment ............ the counterpart, their best argument, what you conceded
A  Action ................... what YOU decided and did; the hardest call; the zoom-in
R  Result ................... technical → org → business → capability, with baselines
L  Learning and leverage .... what changed in your judgment; the mechanism; who owns it now
NUMBERS (with source and method): ___________________________________________
NAMED CREDIT (who did what): ________________________________________________
TOP 5 PROBES REHEARSED (from 01.1 §8 and the relevant folder): ______________
```

---

## 2. Coverage matrix

● = the story is a primary answer for this competency; ○ = it can carry it as a secondary theme.

### 2.1 Amazon's sixteen Leadership Principles

| LP | 1 Flagship | 2 Conflict | 3 Failure | 4 D&C | 5 Kill/Push | 6 Debt | 7 Mentor | 8 FinOps/Scale |
|---|---|---|---|---|---|---|---|---|
| Customer Obsession | ● | ○ | ○ | | ● | ○ | | ○ |
| Ownership | ● | ○ | ● | ○ | ○ | ○ | | ● |
| Invent and Simplify | ● | ○ | | | ○ | ○ | | ● |
| Are Right, A Lot | ● | ○ | ○ | ● | ● | | | ○ |
| Learn and Be Curious | ○ | | ● | ● | | | ○ | ○ |
| Hire and Develop the Best | ○ | | | | | | ● | |
| Insist on the Highest Standards | ○ | | ● | | | ● | ○ | |
| Think Big | ● | | | | | | | ○ |
| Bias for Action | ○ | | ● | | | ○ | | ● |
| Frugality | ○ | | | | ● | ○ | | ● |
| Earn Trust | | ● | ● | ● | ○ | | ○ | |
| Dive Deep | ○ | | ● | | ○ | ○ | | ● |
| Have Backbone; Disagree and Commit | | ● | | ● | ● | ○ | | |
| Deliver Results | ● | ○ | | ● | | ● | | ● |
| Strive to be Earth's Best Employer | | | ○ | | ○ | ● | ● | |
| Success and Scale Bring Broad Responsibility | ○ | | ○ | | ● | | | ○ |

Every LP has at least one ● and the eight stories cover all sixteen. If your real stories leave a gap, fill it with a reserve story rather than stretching one of the eight.

### 2.2 Google and Meta signals

| Signal | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| Google: emergent leadership | ● | ● | ○ | | ○ | ○ | ● | ○ |
| Google: intellectual humility | ○ | ● | ● | ● | | | ○ | |
| Google: user focus / doing the right thing | ● | | ○ | | ● | ○ | | ○ |
| Meta: conflict resolution and empathy | | ● | | ● | ● | ○ | ○ | |
| Meta: growing continuously | | ○ | ● | ● | | | ● | |
| Meta: embracing ambiguity | ● | ○ | | | ○ | | | ● |
| Meta: driving results | ● | ○ | | ○ | | ● | | ● |

---

## 3. The 54-question grid

Questions are **original formulations** of standard senior prompts. Q1–30 are answered in full in Folder 07. "Lead with" is the first beat to emphasize when this story is used for this question.

| # | Question | Primary | Backup | Lead with |
|---|---|---|---|---|
| 1 | A time you disagreed with a senior leader's technical direction | 5 | 2 | The leader's goal, then the data that changed the means |
| 2 | A conflict between two teams where both had a legitimate case | 2 | 1 | Both priorities, quantified |
| 3 | A time you pushed back on a product requirement | 5 | 6 | What the requirement was for |
| 4 | A decision you disagreed with but committed to | 4 | — | Your case, made once, then what committing meant |
| 5 | A time a peer rejected your design | 2 | 4 | The flaw they found |
| 6 | Delivering an unpopular decision to engineers | 5 | 6 | What was being given up, and why |
| 7 | Changing your mind because of someone more junior | 7 | 3 | What you'd set, and their data |
| 8 | Your most difficult working relationship | 2 | 3 | Your own part in the difficulty |
| 9 | A time you escalated something | 2 | 5 | What you tried first, and the joint escalation |
| 10 | Challenging a decision that had already been made | 1 | 5 | The input that changed |
| 11 | Delivering while the goal kept changing | 1 | 2 | The unranked trade-off |
| 12 | The technical vision you set for an area | 1 | 8 | The business cost, then the first step |
| 13 | A project you started that nobody asked for | 1 | 8 | How you found it |
| 14 | A time you missed a commitment | 3 | 6 | The commitment, the cost, your estimate |
| 15 | A decision with very incomplete data | 1 | 8 | Which part was reversible |
| 16 | Your biggest technical mistake | 3 | 4 | Owned in the first sentence |
| 17 | Simplifying something others had made complex | 1 | 6 | Why the complexity existed |
| 18 | Choosing between two good opportunities | 5 | 1 | The counterfactual business risk |
| 19 | A long effort that nearly failed partway through | 1 | 6 | Why it was failing |
| 20 | When data contradicted what people believed | 8 | 5 | The belief and what depended on it |
| 21 | The strongest engineer you've grown | 7 | — | What they were missing, and what you gave them |
| 22 | A hiring decision where you disagreed with the panel | 7 | 2 | The verbatim evidence |
| 23 | Improving how your org interviews or hires | 7 | 6 | The outcome metric that was wrong |
| 24 | Changing how teams were organized | 1 | 6 | The data on cross-team dependencies |
| 25 | Making an org more effective without headcount | 8 | 6 | Where the time went |
| 26 | Protecting your team from overload | 6 | 7 | The load, measured |
| 27 | Seeing something you believed was wrong | 5 | 2 | The specific issue, and the line |
| 28 | Users' interests vs short-term business | 5 | 1 | The long-term business data |
| 29 | Changing a culture or practice | 6 | 3 | The cost of the old practice |
| 30 | Making yourself unnecessary | 7 | 1 | Your indispensability as a risk |
| 31 | Your most significant technical achievement | 1 | 8 | The business stake, then the hardest decision |
| 32 | Learning a new domain quickly | 1 | 8 | Why the domain mattered to the decision |
| 33 | Going beyond your role | 3 | 1 | The unowned gap |
| 34 | Delivering with fewer resources than you needed | 8 | 1 | The constraint, and what you removed |
| 35 | Raising the quality bar for others | 6 | 3 | The defect class, then the gate |
| 36 | Working backwards from a customer | 1 | 5 | The customer outcome |
| 37 | Taking a calculated risk | 1 | 8 | Expected value, ruin and the tripwire |
| 38 | Earning the trust of a skeptical group | 2 | 3 | Why they were skeptical, fairly |
| 39 | Finding a root cause others had given up on | 3 | 8 | The dead ends, then the insight |
| 40 | Setting a standard others adopted | 6 | 1 | Adoption economics |
| 41 | A trade-off between cost and reliability | 8 | 6 | Tiering by criticality |
| 42 | A system you owned hitting a scaling limit | 8 | 3 | When you saw it coming |
| 43 | Receiving critical feedback | 7 | 3 | The exact feedback and your first reaction |
| 44 | A difficult stakeholder outside engineering | 5 | 2 | Their goal and pressures |
| 45 | Aligning several teams on one plan | 2 | 1 | Criteria before options |
| 46 | A decision your team didn't like | 5 | 4 | What they lost |
| 47 | Something you invented | 1 | 8 | The problem it removed |
| 48 | Something you'd do differently in your last role | 3 | 4 | A real regret with its cost |
| 49 | Explaining a complex technical issue to executives | 5 | 1 | The decision they needed |
| 50 | Changing your approach mid-project | 1 | 3 | The signal that told you |
| 51 | Competing deadlines from different leaders | 5 | 2 | Making the trade-off visible to both |
| 52 | Work you're proudest of that nobody noticed | 6 | 7 | The failure that didn't happen |
| 53 | A strongly held technical opinion you've changed | 4 | 3 | The opinion and the evidence |
| 54 | Working with incomplete or bad data | 8 | 1 | How you bounded the error |

### 3.1 Load check

Count how often each story is primary: stories 1 and 5 carry the most. That's typical, and it's why **story 1 needs the most rehearsal**: it will be probed hardest and most often. If your real flagship is weaker than your conflict story, swap their roles in the grid.

---

## 4. Re-weighting and range

### 4.1 Re-weighting one story for different questions

The same story answers different questions by **changing the headline and the beat you expand**, never the facts:

| Question | Headline for the same flagship story | Expanded beat |
|---|---|---|
| "Tell me about ambiguity" | "Nobody had defined the problem or who owned it…" | Context and risk; the structure you created |
| "Tell me about influence without authority" | "Funding it meant delaying a VP's feature…" | Org alignment |
| "Tell me about a hard technical decision" | "The irreversible choice was the partition key…" | Trade-off, with the zoom-in |
| "Tell me about Think Big" | "The end state was one platform for eight teams; the first step was six weeks…" | Action: the first phase that paid for the second |

### 4.2 Keeping range across a loop

- **Track what you've told** to each interviewer. Some candidates note it between rounds.
- **Don't reuse a story with the same competency lead** in two interviews; the debrief will notice.
- **Use the reserve** for "another example": a shorter story is better than a second telling of the same one.

---

## 5. Four-week preparation plan

| Week | Focus | Output |
|---|---|---|
| **1. Mine** | Run the twelve-question story-mining interview (06.1 §1) on your ten biggest projects. Choose eight plus two reserves. | Ten one-paragraph summaries; the coverage matrix filled honestly |
| **2. Write** | One story card per story (§1.2). Get the numbers, with sources. Pass the project-lead test (06.1 §2). | Eight cards; the 100× table (06.3 §4) for stories 1 and 8 |
| **3. Rehearse** | Tell each story aloud at 30 seconds, 3 minutes and 15 minutes. Record and listen. Run the language scan (08.3). | Timed recordings; the banned phrases removed |
| **4. Drill** | Mock loops with a partner who uses the follow-up chains, not just the openers. Calibrate company emphasis (02.3 §5). | Two full mock loops; a list of the probes that broke you, fixed |

### 5.1 Mock-drill protocol

1. The partner picks a question from the grid **at random**.
2. You answer in three minutes, timed.
3. The partner runs **four probes**, from 01.1 §8 or the relevant folder's chains, escalating in difficulty.
4. The partner writes **two sentences of interviewer feedback**, as they would in a packet: what's quotable, and what's missing.
5. You score yourself with the 12-point checklist (01.3 §9).
6. Repeat with a different question that maps to the **same** story, to practice re-weighting.

---

## 6. Hiring Committee Scoring Rubric (the loop as a whole)

| Signal | Strong Hire at L7 | Down-level to L5 |
|---|---|---|
| **Consistency** | Every story at L7 scope; the debrief finds no weak round | One or two strong stories, the rest at L5 |
| **Range** | Different projects for different competencies; failure, conflict and people all covered | The same project in every round |
| **Depth under probing** | Every story survives 15–20 minutes of probes, with a technical zoom-in | Stories collapse at probe two or three |
| **Calibration** | Opening re-weighted for each question and each company | The same telling regardless of the question |
| **Honesty** | Numbers, roles and credit consistent across interviewers | Contradictions between rounds |
| **Coverage** | All of the company's signals have evidence from at least one strong story | Gaps: no failure, no people story, no disagreement upward |

---

## 7. Story Blueprints

### 7.1 Fitting the story to the question (question: "Tell me about a time you were right when others thought you were wrong")

The candidate uses story 8 (a FinOps story about staging a capacity commitment, 06.2 §6.2).

#### How an L5 tells it

> "Sure. So our Kubernetes costs had doubled, and I built a showback dashboard, and then a rightsizing recommender, and teams applied the recommendations, and then there was a discussion with finance about commitments, and I thought we should commit in two tranches, and that turned out to be right, and costs went down 28%."

**What the committee extracts:** the whole story recited in sequence, with the part the question asked about buried in the middle. The interviewer has to dig for the judgment. **The story may be L7; the telling is L5.**

#### How an L7 tells it

> "Finance wanted to sign a three-year capacity commitment for our Kubernetes clusters immediately, sized on our current usage. I argued that was the one irreversible decision in our cost program, and that committing before we'd rightsized would lock in waste for three years. I was in the minority: finance and my own director both wanted the discount that quarter.
>
> I showed them the data: three services held 40% of reserved CPU at under 15% utilization, and our recommender projected that rightsizing would cut reserved capacity by about a third within two quarters. I proposed committing half now, to capture most of the discount on capacity we'd certainly use, and the rest after rightsizing.
>
> They agreed. Two quarters later, the second tranche was 40% smaller than finance's original proposal, which avoided about $X M of committed spend we wouldn't have used. What I took from it was a rule I now apply to every cost program: identify the irreversible lever first, and make sure nothing reversible that affects its size is still pending."

**What separates them:** the L7 headline is the moment of being right against others, the expanded beat is the judgment and the data, and the rest of the story (the dashboard, the recommender) appears only as supporting evidence.

### 7.2 Range: "Give me another example"

After the candidate has told their conflict story (story 2), the interviewer asks for another conflict example.

#### How an L5 tells it

> "Well, in that same project, there was also a disagreement with the security team about the authentication approach. We had a few meetings and found a solution that worked for both of us."

**What the committee extracts:** the same project, a thinner story, no counterpart detail. Range: low.

#### How an L7 tells it

> "A different one, from a year earlier. Our mobile org needed the home screen in one round trip, and the backend domain teams needed to stay independently deployable. I reframed it as a question of who owns a screen's data shape, and proposed a composition layer owned by the mobile org, with versioned contracts from each domain team. The domain leads' fair worry was that the layer would fill up with business logic, so 'no business rules in composition' went into the contract and the code review. Home-screen load in our largest growth market fell by 1.1 seconds, and the domain teams' deploy frequency didn't change. Happy to go deeper on any part."

**What separates them:** the L7 answer comes from a different project, is the 60-second version of a reserve story with all the beats, and invites probing rather than hoping to avoid it.

---

## 8. Bar-Raiser Follow-Up Chains: stress-testing the bank

Run these against your full set of eight. They're the probes that expose a bank that is too thin.

| # | Probe | What it exposes | Strong response |
|---|---|---|---|
| 1 | "Give me another example." | No reserve | A different project, shorter, with all beats |
| 2 | "Something more recent?" | Stale stories | A story from the last 18 months |
| 3 | "Tell me about a failure in that same project." | A sanitized flagship | A real failure inside the flagship, owned |
| 4 | "Who would disagree with how you've described this?" | Inflation | Names the person, says what they'd add |
| 5 | "What did your manager think of this at the time?" | Hidden decision rights | Honest: what the manager approved, questioned or decided |
| 6 | "You mentioned that project earlier with a different number." | Inconsistency | The numbers match, because they're on the card |
| 7 | "If I called the counterpart, what would they say about you?" | Earn Trust | Plausible, specific, and not entirely flattering |
| 8 | "What's the story you're least proud of?" | Self-awareness beyond the prepared failure | A second, honest regret from the reserve |

---

## 9. Checklist

- [ ] Eight stories chosen, from as many different projects as possible, plus two or three reserves.
- [ ] One story card each, with numbers, sources and named credit.
- [ ] The coverage matrix has no empty LP or signal, filled honestly.
- [ ] Every question in the grid has a primary and a backup story you'd actually use.
- [ ] Story 1 rehearsed the most: 30 seconds, 3 minutes and 15 minutes.
- [ ] Two mock loops run with probing partners; the probes that broke you are fixed.

## 10. References

- In this KB: [01.3 The C-T-O-A-R-L architecture and the worksheet](../01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/03-beyond-star-the-l7-executive-storytelling-architecture.md) · [07.1](../07-30-Bar-Raiser-Questions-with-L5-vs-L7-Answer-Comparisons/01-questions-01-to-10-conflict-pushback-and-disagree-and-commit.md), [07.2](../07-30-Bar-Raiser-Questions-with-L5-vs-L7-Answer-Comparisons/02-questions-11-to-20-ambiguity-vision-failure-and-missed-deadlines.md) and [07.3](../07-30-Bar-Raiser-Questions-with-L5-vs-L7-Answer-Comparisons/03-questions-21-to-30-mentorship-hiring-org-design-and-ethics.md): Q1–30 in full · [08.2 The pitch and reverse questions](02-2-minute-elevator-pitch-and-reverse-interview-questions-for-vp-directors.md) · [08.3 Language](03-red-flag-phrases-to-ban-and-power-vocabulary-for-staff-engineers.md)
- Amazon, *Leadership Principles*. <https://www.amazon.jobs/content/en/our-workplace/leadership-principles>
