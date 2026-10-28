# Staff (L6) and Principal (L7) Behavioral Interview Playbook

A permanent reference for Staff and Principal behavioral interviews:
- how hiring committees and bar-raisers score scope;
- executive storytelling that survives probing;
- influence without authority, high-stakes technical conflict, ambiguity and calculated risk, outages and accountability;
- company-specific rubrics (Amazon, Google, Meta, Netflix, Stripe, Apple, Uber).

It is written from the evaluator's side of the table. Every file contains three things:
- **a hiring-committee scoring rubric** (what produces "Strong Hire at L7" vs "down-level to L5");
- **story blueprints** (the same engineering story told the way an L5 tells it and the way an L7 tells it, annotated);
- **adversarial bar-raiser follow-up chains** (the probes that test whether you drove the work or are describing your team's work).

---

## Status

| Folder | Contents | Status |
|---|---|---|
| [01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics](01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/) | How committees detect scope (level map, who decides, 7 scope dimensions, the L4→L7 language shift, owner-vs-passenger probes); the four Staff archetypes and Reilly's three pillars as a narrative spine; the CARL + Trade-off + Org-Leverage storytelling architecture that replaces STAR | ✅ 2026-10-28 · 3 files · ~13.4k words |
| [02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta](02-Company-Specific-Behavioral-Blueprints-Amazon-Google-Meta/) | Amazon's 16 LPs at L6/L7 (Bar Raiser mechanics, Principal Engineering tenets, the "I" vs "we" probe, the Backbone / Disagree-and-Commit two-story requirement, Think Big + Frugality + Bias for Action without the ivory tower); Google G&L and Meta's four behavioral signals, with the Technical Conflict Trap (sub-10 ms vs audit consistency via a tiered escrow SLA); Netflix's informed captain and keeper test, Stripe's users first, Apple's DRI; one story re-weighted for six companies | ✅ 2026-10-28 · 3 files · ~16.5k words |
| [03-Influence-Without-Authority-and-Cross-Org-Alignment](03-Influence-Without-Authority-and-Cross-Org-Alignment/) | Architectural wars between principals (five disagreement types and the tool for each, pre-registered bake-offs, criteria before options, joint escalation; combatant and arbiter stories); influencing executives (the brief, pre-wiring, the six-form "no" menu, the kill memo and the people plan); multi-team migrations without mandates (Larson's de-risk/enable/finish, cost per migration, stop the bleeding, finishing the long tail, mandates that aren't a tax) | ✅ 2026-10-28 · 3 files · ~11.3k words |
| [04-Ambiguity-Technical-Vision-and-Calculated-Risk](04-Ambiguity-Technical-Vision-and-Calculated-Risk/) | Finding unasked existential problems (eight discovery techniques; sizing by exposure, likelihood, time to impact and lead time to fix); the six-page decision document and its review process; one-way vs two-way doors (Bezos 2015/2016, the cost-of-being-wrong formula, converting one-way doors, the 70% rule as four steps, tripwires, calculated risk); tech debt as a portfolio, error-budget freezes agreed in advance, deliberate debt with loan terms | ✅ 2026-10-28 · 3 files · ~10.8k words |
| [05-Production-Outages-Mistakes-and-Psychological-Safety](05-Production-Outages-Mistakes-and-Psychological-Safety/) | Owning SEV1s and bad bets (failure kinds ranked by signal, the L7's role hour by hour, calling and reversing your own bet); COEs and blameless postmortems (multiple causal chains, the five-level remediation hierarchy, propagating one team's lesson as an org guardrail, patterns across COEs, psychological safety); hard feedback across levels, low performance from an IC's seat without the hero-absorbs trap, and sponsorship that grows L5s into Staff | ✅ 2026-10-28 · 3 files · ~11.0k words |
| 06-Translating-Technical-Backgrounds-into-L7-Stories | Reframing service delivery and migrations as Staff scope; performance, FinOps and platform stories; the "not FAANG scale" objection | ⏳ next |
| 07-30-Bar-Raiser-Questions-with-L5-vs-L7-Answer-Comparisons | 30 questions with L5 vs L7 answers, in three files of ten | ⏳ |
| 08-Master-8-Story-Bank-Matrix-and-Interview-Prep-Playbook | The 8-story bank and a 50+ question mapping grid; the 2-minute pitch; reverse-interview questions for VPs and directors; banned phrases and power vocabulary | ⏳ |

Folders are generated one per turn, in order.

## How to use it

1. **Read Folder 01 first.** Every later file assumes its vocabulary:
   - the seven scope dimensions;
   - the archetypes;
   - the six-beat **C-T-O-A-R-L** story architecture: Context and risk → Trade-off → Org alignment → Action → Result → Learning and leverage.
2. **Build your stories from your real work** using the worksheet in [01.3 §8](01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/03-beyond-star-the-l7-executive-storytelling-architecture.md). Score each one with the 12-point checklist that follows the worksheet.
3. **Rehearse against the follow-up chains**, not just the opening. Most of a behavioral interview is probing.

## Conventions

- **Scope labels, not company numbers.** "L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff", calibrated by scope. Company titles differ: Amazon L7 is Principal, Google and Meta L7/E7 is Senior Staff. See the mapping in [01.1 §1](01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md).
- **⚠** marks company-internal mechanics that are only partly public or are practitioner-reported. Verify with your recruiter.
- **Example stories are illustrative composites.** Their numbers are placeholders ($X M) or plausible values. The structure is the lesson.
- **Honesty is a technical requirement.** Bar-raiser probes are built to collapse borrowed or inflated stories (01.1 §9). This playbook helps you find and tell the real scope of your own work; it never helps you claim work you didn't do.
- **Questions are original formulations** of standard competency prompts, not leaked or recalled interview questions.
- **Tellings are marked** `#### How an L5 tells it` / `#### How an L7 tells it`, followed by a blockquote.

## Verification

Each folder passes a structural gate before it's marked done:

1. Every file has the three mandatory sections (scoring rubric, story blueprints, follow-up chains).
2. Every L7 telling has an L5 counterpart.
3. **The KB practises what it preaches.** No L7 example answer contains a passenger phrase this playbook tells you to drop ("I helped", "we decided", "I was asked to", "kind of", "basically", and so on). The full banned list arrives in Folder 08.
4. Relative links resolve, and external URLs answer.

**Folder 01 gate (2026-10-28):**
- 3 of 3 files pass, with 8 L5/L7 pairs and 0 banned phrases in L7 tellings.
- 6 relative links OK; 7 of 7 external URLs return 200.
- The O'Reilly book page blocks automated checks (403 even to a browser user agent), so the Reilly references point to the author's page instead, with the print ISBN, which was confirmed in Open Library.

**Folder 02 gate (2026-10-28):**
- 3 of 3 files pass, with 13 L5/L7 pairs and 0 banned phrases in L7 tellings.
- 11 relative links OK; 10 of 10 external URLs return 200.
- Company culture text was checked against the live pages before writing: Amazon's nine Principal Engineering Community Tenets (Amazon publishes names only, so the per-tenet readings are labelled as this KB's interpretation), Stripe's six current operating principles (the 2026 wording, which differs from older third-party copies), and Netflix's keeper-test and informed-captain wording.

**Folder 03 gate (2026-10-28):**
- 3 of 3 files pass, with 8 L5/L7 pairs and 0 banned phrases in L7 tellings.
- 11 relative links OK; 8 of 8 external URLs return 200.
- Larson's migration phases and his "start with the most challenging teams" advice were checked against the essay. 03.3 §2.1 reconciles that advice with the lowest-blast-radius-first cutover order used in Folder 01.

**Folder 04 gate (2026-10-28):**
- 3 of 3 files pass, with 8 L5/L7 pairs and 0 banned phrases in L7 tellings.
- 9 relative links OK; 10 of 10 external URLs return 200.
- The Bezos 2015 letter has no page on aboutamazon.com (404), so the link points to the PDF on Amazon's investor-relations CDN. The Type 1 / Type 2 quotations were checked against that PDF's text. The SRE Workbook freeze wording ("other than P0 issues or security fixes") was matched to the example policy.

**Folder 05 gate (2026-10-28):**
- 3 of 3 files pass, with 9 L5/L7 pairs.
- The banned-phrase check caught two passenger phrases in a 05.3 L7 telling ("I helped her see…", "the same kind of problem"); both were rewritten.
- 9 relative links OK; 9 of 9 external URLs return 200.
- Etsy's blameless-postmortem essay returns 403 to automated checks, so it is cited by title and year. The COE section list was matched to AWS's own description.

## Where this KB refines the brief

1. **Files are written straight to disk**, so there are no `### FILE:` headers in chat. The folder *is* the repository, with the blueprint's exact folder and file names.
2. **"L7" is calibrated by scope**, with an explicit company mapping. A story tuned for Google L7 (Senior Staff) and one tuned for Amazon L7 (Principal) differ in how much org-level evidence they need.
3. **The storytelling framework is defined precisely.** CARL + Trade-off + Org-Leverage becomes six beats with time budgets, a grading lens per beat, and a follow-up chain per beat.
4. **Company process claims are hedged where they aren't public** (⚠), rather than presented as insider certainty. Interview mechanics change; the evidence principles don't.

## Related KBs in this workspace

These supply the technical depth that L7 stories zoom into:
- [Staff Backend Interview Playbook](../Staff-Backend-Interview-Playbook/): technical L5/L6 mock loops (see `09-Staff-Capstone`).
- [Distributed Systems Design L7 Reference](../Distributed-Systems-Design-L7-Reference/): the architectures behind migration, cell and multi-region stories.
- [Unified Dataflow/Beam/Flink L7 Reference](../Unified-Dataflow-Beam-Flink-L7-Reference/): streaming and data-platform story material.
- [Production AI Engineering L7 Reference](../Production-AI-Engineering-L7-Reference/): LLM platform, evaluation and cost stories.
- [LLD + Concurrency Machine Coding L7 Reference](../LLD-Concurrency-Machine-Coding-L7-Reference/): the machine-coding round that usually sits in the same loop.
