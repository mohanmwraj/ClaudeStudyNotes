# Staff (L6) and Principal (L7) Behavioral Interview Playbook

A permanent reference for Staff and Principal behavioral interviews:
- how hiring committees and bar-raisers score scope;
- executive storytelling that survives probing;
- influence without authority, high-stakes technical conflict, ambiguity and calculated risk, outages and accountability, people leverage;
- company-specific rubrics (Amazon, Google, Meta, Netflix, Stripe and Apple, plus Uber in the 01.2 company-fit table);
- an eight-story bank mapped to 54 questions, and the language that gets your scope written down.

It is written from the evaluator's side of the table. Every file contains three things:
- **a hiring-committee scoring rubric** (what produces "Strong Hire at L7" vs "down-level to L5");
- **story blueprints** (the same engineering story told the way an L5 tells it and the way an L7 tells it, annotated);
- **adversarial bar-raiser follow-up chains** (the probes that test whether you drove the work or are describing your team's work).

**Complete 2026-10-28:** 8 folders, 24 files, ~95.9k words, 91 L5/L7 story pairs.

---

## Status

| Folder | Contents | Status |
|---|---|---|
| [01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics](01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/) | How committees detect scope (level map, who decides, 7 scope dimensions, the L4→L7 language shift, owner-vs-passenger probes); the four Staff archetypes and Reilly's three pillars as a narrative spine; the CARL + Trade-off + Org-Leverage storytelling architecture that replaces STAR | ✅ · 3 files · ~13.4k words |
| [02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta](02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/) | Amazon's 16 LPs at L6/L7 (Bar Raiser mechanics, Principal Engineering tenets, the "I" vs "we" probe, the Backbone / Disagree-and-Commit two-story requirement, Think Big + Frugality + Bias for Action without the ivory tower); Google G&L and Meta's four behavioral signals, with the Technical Conflict Trap (sub-10 ms vs audit consistency via a tiered escrow SLA); Netflix's informed captain and keeper test, Stripe's users first, Apple's DRI; one story re-weighted for six companies | ✅ · 3 files · ~16.5k words |
| [03-Influence-Without-Authority-and-Cross-Org-Alignment](03-Influence-Without-Authority-and-Cross-Org-Alignment/) | Architectural wars between principals (five disagreement types and the tool for each, pre-registered bake-offs, criteria before options, joint escalation; combatant and arbiter stories); influencing executives (the brief, pre-wiring, the six-form "no" menu, the kill memo and the people plan); multi-team migrations without mandates (Larson's de-risk/enable/finish, cost per migration, stop the bleeding, finishing the long tail, mandates that aren't a tax) | ✅ · 3 files · ~11.3k words |
| [04-Ambiguity-Technical-Vision-and-Calculated-Risk](04-Ambiguity-Technical-Vision-and-Calculated-Risk/) | Finding unasked existential problems (eight discovery techniques; sizing by exposure, likelihood, time to impact and lead time to fix); the six-page decision document and its review process; one-way vs two-way doors (Bezos 2015/2016, the cost-of-being-wrong formula, converting one-way doors, the 70% rule as four steps, tripwires, calculated risk); tech debt as a portfolio, error-budget freezes agreed in advance, deliberate debt with loan terms | ✅ · 3 files · ~10.8k words |
| [05-Production-Outages-Mistakes-and-Psychological-Safety](05-Production-Outages-Mistakes-and-Psychological-Safety/) | Owning SEV1s and bad bets (failure kinds ranked by signal, the L7's role hour by hour, calling and reversing your own bet); COEs and blameless postmortems (multiple causal chains, the five-level remediation hierarchy, propagating one team's lesson as an org guardrail, patterns across COEs, psychological safety); hard feedback across levels, low performance from an IC's seat without the hero-absorbs trap, and sponsorship that grows L5s into Staff | ✅ · 3 files · ~11.0k words |
| [06-Translating-Technical-Backgrounds-into-L7-Stories](06-Translating-Technical-Backgrounds-into-L7-Stories/) | The twelve-question story-mining interview and the honest-upgrade-vs-inflation line; legacy-to-cloud migrations through three lenses (strangler-fig risk, zero-downtime cutover, multi-stakeholder alignment); influence across a company boundary in service delivery; bug → COE → guardrail; performance, FinOps (unit cost, one-way commitment levers) and tooling (DORA + SPACE) up the impact ladder; the "not FAANG scale" objection (nine complexity dimensions, a six-step response, the 100× extrapolation drill, scripted answers) | ✅ · 3 files · ~10.5k words |
| [07-30-Bar-Raiser-Questions-with-L5-vs-L7-Answer-Comparisons](07-30-Bar-Raiser-Questions-with-L5-vs-L7-Answer-Comparisons/) | 30 original-formulation questions, each with an L5 answer, a three-minute L7 answer, "what separates them", and three follow-up probes. Q1–10: conflict, pushback, disagree-and-commit, escalation and reopening decisions. Q11–20: shifting goals, vision, unasked projects, missed commitments, deciding on incomplete data, biggest mistake, simplification, choosing between good options, rescuing a long effort, data vs belief. Q21–30: sponsorship, hiring disagreements, improving the loop, org design, leverage without headcount, protecting the team, ethics, users vs short-term business, culture, making yourself unnecessary | ✅ · 3 files · ~13.1k words |
| [08-Master-8-Story-Bank-Matrix-and-Interview-Prep-Playbook](08-Master-8-Story-Bank-Matrix-and-Interview-Prep-Playbook/) | The Rule of 8 (Flagship Architecture/Ambiguity, Cross-Team Conflict, Failure/COE, Disagree and Commit, Killing a Bad Idea, Speed vs Quality, Upleveling, FinOps/Scale) with story cards, a coverage matrix against all 16 LPs and Google/Meta signals, a **54-question grid**, re-weighting and range, a four-week prep plan and a mock-drill protocol; the two-minute pitch, "why leave / why this level / first 90 days", and reverse-interview questions for VPs and directors; red-flag phrases by category, grammar transformations, power vocabulary, and `story_lint.py` | ✅ · 3 files · ~9.3k words |

All folders were completed on 2026-10-28.

## How to use it

1. **Read Folder 01 first.** Every later file assumes its vocabulary:
   - the seven scope dimensions;
   - the archetypes;
   - the six-beat **C-T-O-A-R-L** story architecture: Context and risk → Trade-off → Org alignment → Action → Result → Learning and leverage.
2. **Mine your real work** with the twelve-question interview in [06.1 §1](06-Translating-Technical-Backgrounds-into-L7-Stories/01-upgrading-service-delivery-and-migration-projects-to-staff-scope.md). Choose eight stories plus reserves using [08.1](08-Master-8-Story-Bank-Matrix-and-Interview-Prep-Playbook/01-the-8-core-stories-matrix-mapping-to-every-faang-question.md).
3. **Write one story card per story**, scoring each with the 12-point checklist in [01.3 §9](01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/03-beyond-star-the-l7-executive-storytelling-architecture.md). Run each through `story_lint.py` from [08.3 §4](08-Master-8-Story-Bank-Matrix-and-Interview-Prep-Playbook/03-red-flag-phrases-to-ban-and-power-vocabulary-for-staff-engineers.md).
4. **Calibrate for the company** with Folder 02, especially the "one story, six emphases" exercise in 02.3 §5.
5. **Rehearse against the follow-up chains**, not just the opening. Most of a behavioral interview is probing. Use the Folder 07 answers as a benchmark *after* writing your own, and the mock-drill protocol in 08.1 §5.1.
6. **Prepare the bookends:** the pitch and reverse questions in 08.2.

The four-week plan in 08.1 §5 sequences all of this.

## Conventions

- **Scope labels, not company numbers.** "L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff", calibrated by scope. Company titles differ: Amazon L7 is Principal, Google and Meta L7/E7 is Senior Staff. See the mapping in [01.1 §1](01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md).
- **⚠** marks company-internal mechanics that are only partly public or are practitioner-reported. Verify with your recruiter.
- **Example stories are illustrative composites.** Their numbers are placeholders ($X M) or plausible values. The structure is the lesson.
- **Honesty is a technical requirement.** Bar-raiser probes are built to collapse borrowed or inflated stories (01.1 §9, 06.1 §2). This playbook helps you find and tell the real scope of your own work; it never helps you claim work you didn't do.
- **Questions are original formulations** of standard competency prompts, not leaked or recalled interview questions.
- **Tellings are marked** `#### How an L5 tells it` / `#### How an L7 tells it`, followed by a blockquote. 01.1 also has one L6 telling, to show the middle step.
- **American spelling** throughout.

## Verification

Every file passed a structural gate:
1. Every file has the three mandatory sections (scoring rubric, story blueprints, follow-up chains).
2. Every L7 telling has an L5 counterpart.
3. **The KB practices what it preaches.** No L7 example answer contains any of the 27 red-flag phrases in [08.3](08-Master-8-Story-Bank-Matrix-and-Interview-Prep-Playbook/03-red-flag-phrases-to-ban-and-power-vocabulary-for-staff-engineers.md): passenger ("I helped", "I was involved in"), ownerless ("we decided"), hedges ("kind of", "basically"), blame, inflation and fog.
4. Relative links resolve, and external URLs answer.

### Final gate (2026-10-28, all 24 files)

| Check | Result |
|---|---|
| Structure | 24 of 24 files have all three mandatory sections |
| Story pairs | 91 L5 tellings, 91 L7 tellings |
| Red-flag phrases in L7 tellings | 0 against the full 27-phrase list. Running `story_lint.py`, extracted from 08.3, over all 91 L7 tellings also gives 0 red; its only 2 amber hits are a deliberate quotation ("obviously A", "obviously B") in 03.1. Over the 91 L5 tellings it flags 20 red, as intended. |
| 08.3's before/after examples | Counts quoted in the text match the lint's output (6 red + 3 amber; 3 red + 2 amber) |
| Relative links | 119 OK |
| External URLs | 40 of 40 return 200 |
| Spelling | British spellings normalized to American in prose; links and quotations untouched |

### Source checks and substitutions

- **Fetched and checked against the live pages before writing:**
  - Amazon's nine Principal Engineering Community Tenets. Amazon publishes names only, so the per-tenet readings are labeled as this KB's interpretation.
  - Stripe's six current operating principles, in the 2026 wording, which differs from older third-party copies.
  - Netflix's keeper-test and informed-captain wording.
  - Larson's migration phases, and his "start with the most challenging teams" advice. 03.3 §2.1 reconciles this with the lowest-blast-radius-first cutover order used in Folder 01.
  - The AWS COE section list.
  - The SRE Workbook's freeze wording.
- **Bezos 2015 letter:** aboutamazon.com has no page for it (404), so it is cited via the PDF on Amazon's investor-relations CDN. The Type 1 / Type 2 quotations were checked against that PDF's text.
- **Sites that refuse automated checks:**
  - O'Reilly (403): Reilly's book is cited via the author's page, with the print ISBN confirmed in Open Library.
  - Etsy (403): the blameless-postmortem essay is cited by title and year.
  - ACM (403): "The Tail at Scale" and the SPACE paper are cited by DOI, both confirmed in Crossref.
- **The banned-phrase check earned its place:** it caught two passenger phrases in a 05.3 L7 telling, which were rewritten.

## Where this KB refines the brief

1. **Files are written straight to disk**, so there are no `### FILE:` headers in chat. The folder *is* the repository, with the blueprint's exact folder and file names.
2. **"L7" is calibrated by scope**, with an explicit company mapping. A story tuned for Google L7 (Senior Staff) and one tuned for Amazon L7 (Principal) differ in how much org-level evidence they need.
3. **The storytelling framework is defined precisely.** CARL + Trade-off + Org-Leverage becomes six beats with time budgets, a grading lens per beat, and a follow-up chain per beat.
4. **Company process claims are hedged where they aren't public** (⚠), rather than presented as insider certainty. Interview mechanics change; the evidence principles don't.
5. **The question grid has 54 questions**, more than the 50+ asked for. Each has a primary story, a backup, and what to lead with.
6. **Language is made checkable.** The banned list became a runnable `story_lint.py`, and the same list gates the KB's own L7 answers.
7. **The Technical Conflict Trap gets a real design**, not just a framing: the sub-10 ms vs audit-consistency example (02.2 §3.4) is resolved with an escrow-based tiered SLA that is technically sound.
8. **Failure, people and ethics stories each get a role boundary.** Precise incident roles (05.1 §3), what the manager owns versus the IC (05.3 §2.1), and where disagree-and-commit stops applying (02.1 §4.2, 07.3 Q27).

## Related KBs in this workspace

These supply the technical depth that L7 stories zoom into:
- [Staff Backend Interview Playbook](../Staff-Backend-Interview-Playbook/): technical L5/L6 mock loops (see `09-Staff-Capstone`).
- [Distributed Systems Design L7 Reference](../Distributed-Systems-Design-L7-Reference/): the architectures behind migration, cell and multi-region stories.
- [Unified Dataflow/Beam/Flink L7 Reference](../Unified-Dataflow-Beam-Flink-L7-Reference/): streaming and data-platform story material.
- [Production AI Engineering L7 Reference](../Production-AI-Engineering-L7-Reference/): LLM platform, evaluation and cost stories.
- [Java Backend Master Reference](../Java-Backend-Master-Reference/): JVM performance and runtime depth for performance stories.
- [LLD + Concurrency Machine Coding L7 Reference](../LLD-Concurrency-Machine-Coding-L7-Reference/): the machine-coding round that usually sits in the same loop.
