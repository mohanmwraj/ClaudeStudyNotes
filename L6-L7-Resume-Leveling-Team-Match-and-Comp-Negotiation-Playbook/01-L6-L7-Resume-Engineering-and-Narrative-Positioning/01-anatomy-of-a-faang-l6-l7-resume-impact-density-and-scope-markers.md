# 01.1 · Anatomy of a FAANG L6/L7 resume: impact density and scope markers

> Folder 01 · L6/L7 resume engineering and narrative positioning · File 1 of 3 · [KB home](../README.md) · Next: [01.2 Silicon-to-cloud as a moat](02-framing-silicon-to-cloud-polyglot-experience-c-cpp-java-beam-ai-as-a-moat.md)

| | |
|---|---|
| **Reader** | A Senior or Staff engineer rewriting a resume and LinkedIn profile to get an L6 or L7 loop, not an L5 one |
| **Running exhibit** | Candidate V, a composite 14-year engineer whose career runs from avionics firmware to a 48,000-instance platform and LLM triage (§2.4) |
| **Listing** | `bullet_lint.py`: an impact-density linter for resume bullets, standard-library Python (§10) |
| **Verification** | The listing below is byte-identical to the file that was run. The output in §10.3 is a real run over this file's 16 transformation pairs: every Before row is flagged, every After row passes. |
| **Marks** | ⚠ = a mechanic that companies don't publish; treat it as field practice, not policy. [M] measured · [E] estimated from inputs · [D] design target. |

**Integrity rule.** This file teaches you to show work you really did, at its true scope, so that a skimming reader can see that scope. It never helps you claim decisions you didn't make. That's an ethical line, and it is also the winning tactic: every bullet is a question you'll be asked in the loop, and an inflated bullet turns a deep-dive round into a cross-examination you lose.

---

## 0. The 60-second version

1. **Your resume is read four times by four readers:** a recruiter skimming for a level, a hiring manager matching it to a problem, interviewers picking questions from it, and a committee using it to interpret feedback. Write for all four, but the first skim decides whether the other three happen at your target level.
2. **Level lives in the nouns, not the verbs.** "Architected a REST endpoint" is still an L4 bullet. Altitude comes from the *object*: a module → a service → a system → a platform → an org's portfolio → a company's direction.
3. **Every top bullet carries five slots:** an altitude **V**erb, a **N**umber, a **B**aseline, the **H**ow (mechanism) and the **S**cope. An L7 bullet adds **L**everage: something other teams now use, follow or no longer need.
4. **Delete the executor tells:** "Developed", "Worked on", "Responsible for", "Helped", "Participated", technology lists in place of outcomes, and adjectives in place of numbers ("significantly").
5. **Every number must be reconstructible in 60 seconds** from inputs you can name. If you can't rebuild it, label it as an estimate or cut it.
6. **Page 1 must make the level case on its own.** Add a three-bullet *Selected Impact* block so your strongest work surfaces even if it was eight years ago.
7. **Never edit your official title.** Add a scope note in parentheses instead. Background checks verify titles and dates; they don't verify scope, so that's where you speak.

---

## 1. Who reads your resume, in what order, and what each one scores

### 1.1 The four readers

| Reader | When | Time spent | What they score | What makes them down-level you |
|---|---|---|---|---|
| **Sourcer or recruiter** | Before any contact, and again before the intake note to the hiring manager | Seconds on the first pass; a few minutes when writing the submission | Target-title match, company tier, years in the domain, the first words of each bullet, any number that signals scale | Senior-sounding verbs, a technology list for a summary, no team or org breadth anywhere on page 1 |
| **Hiring manager** | Before the HM screen, sometimes before the recruiter call | 1–3 minutes | "Has this person solved *my* problem, at *my* scale, with *my* kind of org?" | Work that is all inside one team, or outcomes with no business consequence |
| **Interviewers** | 5–10 minutes before their round ⚠ | One read | Which project to drill into; where the claims look thin | A claim they can puncture in two questions, which then colors their whole write-up |
| **Hiring committee or leveling reviewer** | After the loop, alongside the feedback ⚠ | Minutes per packet | Whether the scope on paper matches the scope the interviewers saw; which level the evidence supports | A gap between the resume's scope and the interview's scope, in either direction |

The committee row is the one most candidates never think about. At companies that use committees, the resume often travels with the interview packet ⚠. A committee member who reads "Led org-wide platform migration" and then reads an interviewer's note "candidate couldn't explain the rollout sequencing" doesn't just discount the bullet. They discount *you*, because the inflation itself is evidence about judgment. The reverse also happens: an executor-worded resume makes a committee read strong interview signal as "strong L5" rather than "L6".

**Altitude is decided before you open your mouth.** For the full rubric a committee applies to the interview signal, see [Behavioral playbook 01.1, how committees detect L5 vs L6 vs L7](../../Staff-Principal-Behavioral-L7-Playbook/01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md). This file is about the paper that frames that signal.

### 1.2 The first skim: titles, dates, and the first words of each bullet

The most-quoted number about resume screening comes from a Ladders study: recruiters spent an average of **7.4 seconds** on the initial screen in its 2018 eye-tracking work, up from about 6 seconds in 2012, and they looked mostly at job titles and section headings ([HR Dive on the 2018 study](https://www.hrdive.com/news/eye-tracking-study-shows-recruiters-look-at-resumes-for-7-seconds/541582/)). Critics point out that the report doesn't say much about its sample or method, so treat the exact number as indicative, not a law.

What matters for you is the pattern, and that matches what senior recruiters describe: the eye goes **title → company → dates → the first three to six words of each bullet → any number**. So, for leveling:

- **The first words of each bullet carry the level.** "Led a 6-engineer team that replaced…" survives a skim. "Was part of a team that worked on…" is already L4 by the fifth word.
- **Numbers act as eye anchors.** A bullet with "48,000 instances" or "$1.14M" gets read; a bullet of pure prose gets skipped.
- **Titles are read before content.** That's why §7.3 matters: if your official title under-sells your scope, the scope note in parentheses is part of the skim.

### 1.3 The ATS is a database, not a judge

You'll read that "75% of resumes are rejected by ATS before a human sees them". That figure traces back to Preptel, a resume-services company that went out of business in 2013, and nobody has produced the study behind it ([HiringThing on the myth](https://www.hiringthing.com/blog/applicant-tracking-system-myths)). For L6/L7 roles at large companies the practical picture is:

- The applicant tracking system **stores and indexes** your resume. Recruiters and sourcers **search** it, and LinkedIn, with keywords and filters.
- **Knockout questions** (work authorization, location, sometimes years of experience) can filter you automatically. Answer those honestly and precisely (see 01.2 §6 for years of experience across several languages).
- A human decides. The ATS matters only in two ways: **parseability** (can it extract your titles and dates?) and **findability** (do your words match what a sourcer types?).

So write for the human, and keep the file parseable (§7.6).

### 1.4 The resume is a menu: interviewers order from it

At L6/L7, at least one round is usually a deep dive into a past project, and other rounds borrow from the resume too ⚠. Interviewers scan for the claim that's easiest to test and the claim that looks most inflated. Then they order those.

That changes the cost-benefit of every bullet:

| Bullet type | Cost in the loop |
|---|---|
| True, specific, and at the right altitude | It pulls the interview toward your strongest material. This is the cheapest prep you'll ever do. |
| True but under-stated | It's safe in the loop, but you get leveled from what the paper shows. |
| Inflated | It invites the probe that exposes the gap. One exposed bullet discounts every other bullet. |

The defense of each bullet lives in the [Past-Project Deep-Dive playbook](../../Past-Project-Deep-Dive-L7-Defense-Playbook/README.md); its [01.2 on architect-or-passenger probes](../../Past-Project-Deep-Dive-L7-Defense-Playbook/01-Anatomy-of-the-60-Minute-Deep-Dive-Round/02-how-interviewers-test-if-you-were-the-architect-or-just-a-passenger.md) is the companion to this file. Write each bullet so you'd be glad to be asked about it.

---

## 2. What "L6" and "L7" mean on paper

### 2.1 Ladder vocabulary

This KB uses **L5 = Senior, L6 = Staff, L7 = Principal or Senior Staff**, the same labels as the Behavioral and Past-Project playbooks. Company ladders don't line up exactly. The table is a vocabulary aid; Folder 02 covers how to calibrate the target level on the recruiter call.

| This KB | Google | Meta | Amazon | Microsoft ⚠ | Apple ⚠ |
|---|---|---|---|---|---|
| L5 Senior | L5 Senior SWE | E5 | L6 SDE III | 63–64 Senior SDE | ICT4 |
| **L6 Staff** | **L6 Staff** | **E6 Staff** | No Staff title: SDE III (L6) and Principal (L7) both get compared to it | 65–66 Principal SDE | ICT5 |
| **L7 Principal / Senior Staff** | **L7 Senior Staff** | **E7 Senior Staff** | **L7 Principal SDE** | 67 Principal; 68+ Partner | ICT6 |

The Google, Meta and Amazon ladders above (L3–L8, E3–E8, L4–L10) appear side by side in the [Levels.fyi leveling comparison](https://www.levels.fyi/reports/examples/leveling-comparison-report.html). The cross-company alignment is community consensus, not anything the companies publish, and it shifts. Uber, Stripe, NVIDIA and Qualcomm each have their own ladders and title conventions; Folder 02.01 handles them company by company.

Two traps the table exposes:

1. **"Principal" means different altitudes.** A Principal at Amazon (L7) is a rare, senior role. A Principal SDE at Microsoft (65–67) is often compared to a Google L6. "Principal Engineer" at a 300-engineer company may calibrate to L5 or L6 at a FAANG. Don't let a title do the arguing; let scope do it (§7.3).
2. **"L7" means different things.** In this KB it's the tier, not a company's level number. An Amazon L7 and a Google L7 are both "L7 tier" here, but a Google L6 is also sometimes compared to Amazon L7 ⚠.

### 2.2 The five scope axes

Committees and leveling guides describe each level along a handful of axes. These five are the ones a resume can show:

| Axis | L5 Senior | L6 Staff | L7 Principal / Senior Staff |
|---|---|---|---|
| **Problem ambiguity** | Well-defined problem; you pick the solution | The problem is fuzzy; you define it, write it down, get agreement | You decide which problems the org should work on at all |
| **Blast radius** | One team's system | Several teams, or one system many teams depend on | An org or the company; sometimes the industry (standards, OSS) |
| **Time horizon** | A quarter or two | One to two years | Multi-year direction |
| **Leverage mechanism** | Your own code and reviews | Designs others build; reviews that change others' designs; mentoring | Standards, platforms, strategies and policies that others adopt without you in the room |
| **Business coupling** | A feature metric | A product metric, a cost line, an SLO | P&L, total cost of ownership, regulatory risk, strategic options |

A bullet can show *any* of these. Your top bullets should show at least two at the target level.

### 2.3 Altitude lives in the nouns

Verbs are cheap; anyone can type "Architected". What a reader actually levels on is the **object of the verb** and the **consequence**:

| Altitude of the object | Example object | Reads as |
|---|---|---|
| Function or module | "the retry logic in the payment client" | L3–L4 |
| Service | "the payment-capture service" | L4–L5 |
| System of services | "checkout: capture, ledger, outbox, saga" | L5–L6 |
| Platform others build on | "the config platform for 1,200 services" | L6 |
| An org's portfolio or policy | "config-safety policy for ~2,000 engineers" | L6–L7 |
| Company direction | "the company's decision to consolidate on one streaming runtime" | L7+ |

**The rule:** pick the *largest object that is honestly yours*, then make the verb match it. "Architected the payment-capture retry logic" is verb inflation on a small object; it reads worse than "Rewrote the payment-capture retry logic". Verb and object must sit at the same altitude.

### 2.4 The running exhibit: Candidate V (composite)

Candidate V is not a real person. The career is assembled from the composite exhibits in the [Past-Project Deep-Dive playbook](../../Past-Project-Deep-Dive-L7-Defense-Playbook/README.md), so every number in a bullet here has a fact sheet and a whiteboard defense behind it. Use V's bullets as patterns, never as text to copy: your numbers must come from your work.

| Role | Dates | Employer (composite) | Official title | Exhibit and where it's defended | True scope at the time |
|---|---|---|---|---|---|
| R5 | 2023-02 → now | Consumer marketplace, ~2,000 engineers | Staff Software Engineer | **P-0 Beacon**, config and flag platform ([fact sheet](../../Past-Project-Deep-Dive-L7-Defense-Playbook/01-Anatomy-of-the-60-Minute-Deep-Dive-Round/01-minute-by-minute-whiteboard-pacing-strategy-from-context-to-internals.md#3-the-running-exhibit-p-0-beacon-fact-sheet)); **E Lodestar**, LLM ticket triage (this KB) | Tech lead of 6; authored the cross-org RFC; built the eval gate other teams adopted |
| R4 | 2020-09 → 2023-01 | Omnichannel retailer, in-house tech center in Bengaluru | Lead Software Engineer | **B Tillpoint**, checkout and payments ([03.2](../../Past-Project-Deep-Dive-L7-Defense-Playbook/03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/02-archetype-b-banking-microservices-java-sql-idempotency-and-saga-defense.md)) | Led the payments redesign; drove a PCI scope program across 14 teams |
| — | 2020-03 → 2020-08 | Career break | — | [01.3](03-handling-career-breaks-short-tenures-and-service-to-product-transitions.md) | Relocation and family caregiving |
| R3 | 2018-04 → 2020-02 | IT services firm, engagement for a US insurer | Technology Architect | **A Tidewater**, CDC → Beam/Dataflow ([03.1](../../Past-Project-Deep-Dive-L7-Defense-Playbook/03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/01-archetype-a-enterprise-data-migration-pipeline-beam-dataflow-gcp-defense.md)) | Designed the pipeline, dedup, reconciliation and backfill handoff for one client program |
| R2 | 2016-07 → 2018-03 | Ad-ranking company, acquired in 2018 | Senior Software Engineer | **C Quickset**, in-process C++ feature cache ([03.3](../../Past-Project-Deep-Dive-L7-Defense-Playbook/03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/03-archetype-c-cpp-low-latency-application-and-memory-optimization-defense.md)) | Designed and wrote the cache; one partner team |
| R1 | 2012-07 → 2016-06 | Avionics supplier, Bengaluru engineering center | Software Engineer → Senior Software Engineer | **D Flightline**, ARINC 429 data concentrator ([03.4](../../Past-Project-Deep-Dive-L7-Defense-Playbook/03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/04-archetype-d-embedded-systems-safety-critical-firmware-and-bus-protocol-defense.md)) | Owned word acceptance, the validity monitor and the timing budget; wrote the hardware/software memo |

**E Lodestar** (the only exhibit new to this KB) is an LLM-assisted triage system for seller-support tickets at the marketplace:

- **Volume and before-state:** ~41,000 tickets/day across 31 queues [M]; a keyword-rule router misrouted 23% of tickets on a 2,400-ticket labeled sample [M].
- **Design:** a small classifier routes first; the LLM runs only on the ~18% of tickets the classifier is unsure about, with retrieved examples from resolved tickets in its prompt; below a confidence floor the ticket goes to human triage (~6%) [M].
- **After:** misroutes 8.5% on the held-out 2,400-ticket set [M]; blended cost $0.0021 per ticket [M] (≈ $86/day, ≈ $31k/year [E]); p95 latency 1.3 s [M].
- **Leverage:** the evaluation gate (golden sets, regression thresholds in CI, cost and latency budgets) was adopted by 5 product teams [M].
- **Ownership:** ★ the routing architecture and the eval gate; ◆ the classifier fine-tuning (ML team); ○ the LLM gateway (platform team).

V's career has every pattern this folder covers: a polyglot "split" (01.2), two sub-2-year tenures, a six-month break and a services-to-product move (01.3). That's deliberate.

---

## 3. Impact density: the five-slot bullet

### 3.1 From XYZ to XYZ-L

Laszlo Bock, then Google's SVP of People Operations, published the most-cited resume formula in a September 2014 LinkedIn post: *"Accomplished [X] as measured by [Y] by doing [Z]"*. In his words: start with an active verb, measure what you accomplished numerically, and give a baseline ([the post, as mirrored by Cal State LA](https://www.calstatela.edu/sites/default/files/formula_for_a_winning_resume.docx)). Earlier that year he'd put it as "I accomplished X, relative to Y, by doing Z" in a New York Times interview ([Quartz](https://qz.com/201088/google-just-revealed-the-incredibly-simple-formula-for-killer-resumes)). It fixes the commonest failure, bullets that list duties, and it's still the right base.

For L6/L7 it misses two things:

- **Scope.** XYZ doesn't say how big the X was or how many people it touched. "Reduced latency 40% by adding a cache" fits a side project.
- **Leverage.** XYZ describes what *you* accomplished. Staff and Principal levels are about what *others* could do because of you: a design they built, a standard they followed, a platform they stopped re-inventing.

So this KB uses five slots plus one, and names them by letter so the linter in §10 can report them:

| Slot | Name | What it answers | Example fragment |
|---|---|---|---|
| **V** | Altitude verb | What kind of act was this: decide, lead, set, retire? | "Led", "Authored", "Retired", "Cut" |
| **N** | Number | How much, how big, how many? | "48,000 instances", "$0.0021 per ticket" |
| **B** | Baseline | Compared with what? | "from 29.6 h to a 3-min p95", "41 ms → 22 ms" |
| **H** | How (mechanism) | What was the insight, in one noun phrase? | "by moving label filtering into the protocol IC with DMA" |
| **S** | Scope | How wide: system scale or org breadth? | "1,200 services", "across 14 teams" |
| **L** | Leverage (L7) | What do others now use or follow? | "adopted by 5 product teams", "set policy", "retired" |

### 3.2 Density targets

**Impact density** here means how many slots a bullet fills: how much leveling information a skimmer can extract per line. The targets:

| Bullet position | Target | Why |
|---|---|---|
| Selected Impact block (top of page 1) | 5/5 for an L6 target; 4/5 **plus L** for an L7 target | These three bullets are the level case |
| First two bullets of the current role | ≥ 4/5 | They're read in the first skim |
| Any other bullet | ≥ 3/5, and a number | A bullet without a number is skipped |
| Any bullet at all | No executor opener, no weasel words, no adjectives in place of numbers | One L4-sounding bullet anchors the reader's level for the whole page |

A bullet doesn't need all slots to be good. A 3/5 bullet with a crisp mechanism beats a 5/5 bullet stuffed with numbers nobody can follow. But the *top* bullets carry the level, and those need the slots.

### 3.3 Which slot goes first

The first six words get read. Choose the opener by what's strongest:

| Opener | Use when | Example opening |
|---|---|---|
| **Outcome-first** | The outcome is striking and the number is clean | "Cut interrupt CPU from ~20% to <2% on…" |
| **Decision-first** | The act itself was the senior part: choosing, writing the RFC, leading | "Authored the hardware/software decision memo…" |
| **Leverage-first** | L7 bullets: what others now do because of you | "Established the org's default LLM evaluation gate…" |
| **Scope-first** | The scope is the surprise | "Led a 6-engineer team that replaced… for 1,200 services" |

Avoid **technology-first** openers ("Java/Spring/Kafka engineer who…"). The technology is how, not what. It belongs in the H slot or the skills section.

### 3.4 Length and number discipline

- **One or two lines**, roughly 25–45 words. The linter flags anything over 48 words.
- **One decision per bullet.** If the bullet has "and also", it's two bullets.
- **At most three numbers.** More than three and the reader stops parsing.
- **Keep units honest.** Say "p95" or "p99" for latency, "per month" for cost, "[E]" in your own notes for estimates.
- **Write "~" for approximations.** "~41,000 tickets/day" is honest; "41,327" invites "where did that come from?" unless you know it cold.

---

## 4. The verb altitude ladder and the executor tells

### 4.1 Verb tiers

| Tier | Verbs | The evidence each verb promises |
|---|---|---|
| **Executor (L3–L5)**, avoid as openers | Developed, Worked on, Implemented, Built, Wrote, Coded, Created, Helped, Assisted, Participated, Responsible for, Involved in, Handled, Supported, Used, Maintained, Tested, Fixed, Coordinated, Delivered | The activity happened. Nothing about who decided, how big it was, or what changed |
| **Ownership and outcome (L5–L6)** | Owned, Led, Drove, Cut, Reduced, Replaced, Redesigned, Migrated, Closed, Turned, Grew, Unblocked, De-risked | You were accountable for a result; there's a number |
| **Direction and leverage (L6–L7)** | Architected, Authored (an RFC, a memo, a strategy), Defined, Established, Set, Instituted, Standardized, Unified, Consolidated, Retired, Founded, Spearheaded, Shaped | Others' work changed because of yours; something became a default, a standard, or went away |

Two caveats:

- **"Built" and "Created" aren't wrong in prose.** They're weak *openers*, because they describe making a thing rather than the consequence of having it. "Built the cache" → "Replaced a 32-shard Redis fan-out with an in-process cache…".
- **"Spearheaded" is overused.** Use it once on a page, at most, and only for something you started from nothing and drove across org lines.

### 4.2 The executor-tell catalog

| Phrase | What a leveling reader infers | Fix |
|---|---|---|
| "Responsible for X" | A job description. Were you any good at it? | State a result X produced under you |
| "Worked on X", "Involved in X", "Part of the X team" | You were near X | Name your slice and its outcome; if your slice was small, say so with precision (§9) |
| "Helped X", "Assisted with X" | Someone else owned it | Name the part you owned, or drop the bullet |
| "Developed Java microservices using Spring Boot, Kafka, Docker, Kubernetes" | A technology list; no altitude at all | Move the technologies to Skills; write what the services changed |
| "Significantly improved performance" | You don't know the number, or it's small | Put the number and the baseline |
| "Collaborated with cross-functional stakeholders" | Meetings | Name the decision the collaboration produced and who signed off |
| "Mentored junior engineers" | Common, unmeasured | "Grew 3 engineers to Senior by…" |
| "Ensured timely delivery", "Delivered on schedule" | Services-company language: the plan was someone else's (01.3 §5) | Name the risk you retired to hit the date |
| "Expert in", "Proficient in", "Hands-on with" | Self-rating | Let bullets prove expertise |
| "We built…", "The team achieved…" | Who are you in this? | Use "I" scope grammar: "Led the team that…", or "Designed X; the team built Y" |

### 4.3 Verb inflation is worse than executor verbs

A reader who sees "Developed the payment retry logic" thinks *L4 or L5, maybe under-sold*. A reader who sees "Architected the payment retry logic" thinks *this person doesn't know what architecture means, or is inflating*. The second is worse: it costs you the benefit of the doubt on every other bullet.

The test for any L6/L7 verb: **could you hand the reader the artifact the verb implies?** "Architected" → a design doc with alternatives you rejected. "Authored the cross-org RFC" → the RFC, its reviewers, its decision. "Established the standard" → the standard, and who follows it. "Retired X" → the decommission date. No artifact, no verb.

---

## 5. Scope markers: the catalog, and quantifying honestly

### 5.1 The scope-marker catalog

| Marker family | Examples | Strongest form | Weak form |
|---|---|---|---|
| **Org breadth** | Teams, engineers, business units, orgs affected | "across 14 teams", "for ~2,000 engineers" | "cross-functional" |
| **System scale** | Services, instances, QPS, events/day, data volume, fleet size, devices shipped | "1,200 services (48,000 instances)", "180M records/night" | "large-scale", "high-volume" |
| **Money** | Cost avoided, cost cut, revenue protected, TCO | "avoiding a ≥$1.14M lease extension" | "cost savings" |
| **Risk** | Incidents, Sev-1s, compliance findings, audit scope, safety level | "Sev-1s from 2 to 0 over 12 months", "PCI scope 140 → 12 hosts" | "improved reliability" |
| **Time** | Lead time, window, deadline, duration | "2 weeks before lease end", "from 6 weeks to 4 days" | "faster" |
| **Decision rights** | Who approved your proposal; what became default | "approved by the chief engineer", "became the org default" | "presented to leadership" |
| **People leverage** | Engineers grown, interview bar, forums started | "grew 3 engineers to Senior" | "mentored" |
| **Standards** | RFCs, rubrics, templates, policies others follow | "the eval gate adopted by 5 product teams" | "best practices" |

### 5.2 Getting the numbers you don't have

Most engineers don't have their numbers lying around. Here's how to rebuild them honestly, with the label you keep in your own notes:

| Situation | Method | Example | Label |
|---|---|---|---|
| A dashboard existed | Pull before and after for the same window and percentile | p99 238 → 141 ms, canary vs control | [M] |
| Cost, no FinOps data | Instance-hours × list price, before and after | 40 nodes × 730 h × $0.38 vs 26 nodes | [E] |
| Engineer time saved | Engineers × waits per day × minutes saved × working days | 120 × 0.75 × 27 min × 220 days ÷ 60 ≈ 8,910 h → "~9,000 engineer-hours" | [E] |
| Incidents | Count in the incident tracker over equal windows | Sev-1s 2 → 0 over 12 months each side | [M] |
| Risk avoided | The concrete cost of the alternative, with its source | 6-month minimum extension × ~$190k/month ≈ $1.14M | [E] from a quote |
| Adoption | Count of teams or services using it, from a registry or import graph | 5 product teams call the eval gate in CI | [M] |
| You genuinely can't know | Use a range or a relative change, or drop the number | "cut review rounds from 4 to 1" (from your own records) | — |

**Confidentiality.** Never put revenue, customer counts or margins on a resume unless they're public. Use ratios ("~30% of the service's CPU"), relative changes, or public figures. For client work, use the description your contract allows ("a top-20 US insurer" may itself be confidential; "a US property-and-casualty insurer" usually isn't). When in doubt, ask (Script 8).

### 5.3 The 60-second reconstruction rule

For every number on the page, you must be able to say, in under a minute: **where it came from, over what window, and what it's compared with.** Write these down in a private "numbers card" (the format is in the [Past-Project playbook, 01.1](../../Past-Project-Deep-Dive-L7-Defense-Playbook/01-Anatomy-of-the-60-Minute-Deep-Dive-Round/01-minute-by-minute-whiteboard-pacing-strategy-from-context-to-internals.md)). If you can't, label it [E] in your notes and be ready to say "that's an estimate from X and Y", or cut it.

---

## 6. Before → After transformation lab

Sixteen pairs. **T1–T7, T9 (L6), T13 and T14 are Candidate V**, with numbers from the exhibits. **T8, T9 (L7), T10, T12, T15 and T16 are standalone illustrations** with placeholder numbers. Each pair shows:

- the executor version;
- the honest L6 version;
- an L7 version **only where the scope existed**. Where it didn't, the pair says so. That's half the lesson.

Every row in these tables is linted in §10.3.

#### T1 · "Developed Java pipelines" → a batch window you retired

| Version | Bullet |
|---|---|
| **Before** | Developed Java pipelines using Apache Beam, Kafka and BigQuery to process insurance data. |
| **After (L6)** | Architected the CDC → Kafka → Beam/Dataflow replacement for a 6-hour nightly batch (180M records/night, 38 tables) by running streaming and the 7-year backfill as one pipeline; cut worst-case staleness from 29.6 h to a 3-min p95. |
| *No L7 version* | One client program, one client team. "Set the insurer's data strategy" would be inflation; V didn't own the insurer's roadmap. |

**What must be true:** you made the CDC-vs-batch and one-pipeline decisions, and you can derive 5.56 h of a 6 h window from 180M ÷ 9,000/s. **The probe it invites:** "Why one pipeline for stream and backfill? What broke at the handoff?" That's a great probe to invite if you were there ([03.1 §6](../../Past-Project-Deep-Dive-L7-Defense-Playbook/03-Complete-L7-Whiteboard-Blueprints-for-4-Career-Archetypes/01-archetype-a-enterprise-data-migration-pipeline-beam-dataflow-gcp-defense.md)).

#### T2 · "Worked on C++ modules" → a tail-latency fix with a mechanism

| Version | Bullet |
|---|---|
| **Before** | Worked on C++ modules for the ranking service and improved performance significantly. |
| **After (L6)** | Replaced a 32-shard Redis fan-out with an in-process C++ feature cache (lock-free reads, epoch reclamation, 12 GB byte cap), cutting feature-fetch p99 from 9 ms to 0.9 ms and ranking p99 from 41 ms to 22 ms, under its 25 ms SLO. |
| *No L7 version* | One service and one partner team. The cache never became a shared library, so there's no leverage to claim. |

**What must be true:** you designed the cache and can explain why fan-out to 32 shards puts ~27.5% of requests on some shard's p99 (1 − 0.99³²). **The probe:** "What happens when a backfill floods the cache?" (V's INC-Q2).

#### T3 · "Wrote embedded C code" → a CPU budget recovered without a board respin

| Version | Bullet |
|---|---|
| **Before** | Wrote embedded C code for ARINC 429 drivers on ARM Cortex-M7 and did unit testing. |
| **After (L6)** | Cut interrupt CPU from ~20% to <2% on a 12-channel ARINC 429 avionics data concentrator by moving label filtering into the protocol IC with DMA; brought the worst minor frame from 8,600 µs to 7,700 µs (8,000 µs budget) with no board respin. |
| *No L7 version* | V was a Senior engineer on one unit. The "L6" label here describes the bullet's quality, not a claim that V was Staff in 2015. |

**What must be true:** you can derive ~33,333 words/s (12 × 100,000 bit/s ÷ 36 bit-times) and ~20% CPU (× ~6 µs per ISR). **Why it's on an L6 resume at all:** old work at Senior level still shows *how you think*. It belongs in Selected Impact if it's your sharpest mechanism (01.2 explains why).

#### T4 · "Participated in design discussions" → the decision memo you wrote

| Version | Bullet |
|---|---|
| **Before** | Participated in design discussions with the hardware team and helped with requirements. |
| **After (L6)** | Authored the hardware/software decision memo — protocol-IC label filtering plus DMA vs. a board respin — that the chief engineer approved, keeping a DO-178C retrofit (4 added channels, MC/DC-level validity monitor) on schedule with zero hardware changes. |
| *No L7 version* | One program. The memo is a Staff *behavior* (writing down a trade-off and getting a decision), which is exactly why it's worth a bullet. |

**What must be true:** you wrote the memo, measured the options, and someone with authority signed it. **The lesson:** "participated in discussions" often hides the most Staff-like thing a Senior engineer did. Go looking for the memos.

#### T5 · "Responsible for payment microservices" → correctness, then the cross-team program

| Version | Bullet |
|---|---|
| **Before** | Responsible for payment microservices in Java Spring Boot; fixed double charge bugs. |
| **After (L6)** | Led the checkout-payments redesign for a 2,400 orders/s peak — idempotency keys, a transactional outbox and a saga with idempotent compensation — taking duplicate captures from 1,214 in one Black Friday incident to zero and checkout p99 from 238 ms to 141 ms. |
| **After (L7)** | Drove the PCI scope-reduction strategy across 14 teams: tokenization at the edge shrank the cardholder-data environment from 140 hosts to 12 (~$230k/yr in audit and hardening cost) and took every team off the 45-minute shared release train. |

**What must be true for the L7 row:** you set the direction (tokenize at the edge, cut scope), wrote the plan the 14 teams executed, and negotiated the sequencing. If you only built the tokenization service, the L6 row is your ceiling here, and it's a strong one. **The probe:** "How did you get 14 teams to change their deploy process? Who said no?"

#### T6 · "Built a configuration service" → the platform, then the policy

| Version | Bullet |
|---|---|
| **Before** | Built a configuration management service using gRPC and Postgres to replace ZooKeeper. |
| **After (L6)** | Led a 6-engineer team that replaced a ZooKeeper flag store with signed, ring-staged config snapshots for 1,200 services (48,000 instances); config-caused Sev-1s went from 2 to 0 over 12 months and config pages from ~11 to ~2 per month. |
| **After (L7)** | Authored the cross-org RFC (3 alternatives, 2 revisions) that set config-safety policy for ~2,000 engineers — staged rings, auto-halt, fail-static reads — and retired the colo ZooKeeper ensemble 2 weeks before lease end, avoiding a ≥$1.14M extension. |

**Why both rows are true for V:** the L6 row is the delivery; the L7 row is the policy every change in the company now follows. **The probe:** "Name one change your rings stopped." (Three auto-halts in ring0; worst blast radius 1.1% for 4 minutes.)

#### T7 · "Built an AI chatbot" → evaluation, cost and abstention

| Version | Bullet |
|---|---|
| **Before** | Built an AI chatbot using LLMs, LangChain, RAG, vector DB, Python and FastAPI. |
| **After (L6)** | Architected LLM-assisted triage for ~41,000 seller-support tickets/day — classifier first, LLM only on low-confidence cases, abstain-to-human below threshold — cutting misroutes from 23% to 8.5% on a 2,400-ticket held-out set at $0.0021 per ticket. |
| **After (L7)** | Established the org's default LLM evaluation gate (golden sets, regression thresholds in CI, cost and latency budgets), adopted by 5 product teams, replacing ad-hoc spot checks with a measured quality delta on every model or prompt change. |

**Why the Before is so damaging in 2026:** a framework list says "wrapper". Hiring managers for AI roles look for evaluation discipline, cost per unit and failure handling. **The probe:** "How did you build the held-out set, and how do you know it isn't leaking into the prompts?"

#### T8 · "Optimized cloud costs" (illustration)

| Version | Bullet |
|---|---|
| **Before** | Migrated services to Kubernetes and optimized cloud costs. |
| **After (L6)** | Cut the search tier's compute spend from $1.9M to $1.2M a year by replacing static node pools with request-based bin-packing and right-sizing 140 services from measured p95 usage, with no SLO misses across two peak seasons. |
| **After (L7)** | Set the org's FinOps operating model — unit-cost dashboards per service, a quarterly right-sizing review, cost budgets in design review — adopted by 9 teams, holding infrastructure cost per order flat while order volume grew 2.3×. |

**Note the Before:** it opens with an altitude verb, "Migrated", and still fails. An altitude verb doesn't rescue a bullet with no number.

#### T9 · "Handled production incidents" → the fix that changed the fleet

| Version | Bullet |
|---|---|
| **Before** | Handled production incidents and on-call for the platform team. |
| **After (L6)** | Turned a 6-minute incident (0.3% of instances serving compiled-in defaults after a truncated last-known-good file) into a fleet-wide fix — fsync-and-rename writes, two LKG generations, fail-readiness for critical namespaces — enforced by a CI crash test. |
| **After (L7)** | Instituted the org-wide incident-review standard (blameless review template, action-item SLAs, quarterly failure-class reviews) across 9 teams; repeat-cause incidents fell from 7 to 1 per quarter within a year. |

The L6 row is V's INC-B7. The L7 row is an illustration: V didn't do it, so V's resume stops at L6 here.

#### T10 · "Mentored junior engineers" (illustration)

| Version | Bullet |
|---|---|
| **Before** | Mentored junior engineers and conducted code reviews. |
| **After (L6)** | Grew 3 engineers to Senior by pairing each with one RFC they led end to end, and cut the team's median review turnaround from 2.1 days to 0.6 days by routing reviews to code owners. |
| **After (L7)** | Founded the Staff+ design forum that reviews every cross-team design before funding (14 teams, weekly); 22 designs reviewed in year one, 4 redirected before build, an estimated 9 engineer-quarters saved. |

**Careful with promotions.** "Grew 3 engineers to Senior" is a claim about other people's promotions. Only write it if you were the named mentor and their promotion packets cite the work.

#### T11 · "Involved in migration" → the strangler you drove

| Version | Bullet |
|---|---|
| **Before** | Involved in migration of monolith to microservices. |
| **After (L6)** | Drove the strangler-fig migration of the order monolith's pricing and inventory domains (31% of traffic) to 2 services behind a routing facade, shadow-diffing every read before each cutover; zero customer-visible incidents across 6 cutovers. |
| *No L7 version* | The L7 version would need the migration *program*: sequencing across all domains, the funding case, the org-wide cutover policy. If you didn't own those, stop at L6. |

#### T12 · "Improved CI/CD pipelines" (illustration)

| Version | Bullet |
|---|---|
| **Before** | Improved CI/CD pipelines and reduced build times. |
| **After (L6)** | Cut median CI time from 38 to 11 minutes for a 120-engineer monorepo by adding remote build caching and test-impact analysis, recovering an estimated 9,000 engineer-hours a year. |
| **After (L7)** | Defined the org-wide build-health SLOs (p50 CI ≤ 12 min, flake rate ≤ 1%) and drove adoption through a paved-road toolchain; 11 of 13 product teams met them within two quarters. |

The 9,000 hours is the §5.2 formula: 120 × 0.75 blocking waits/day × 27 min × 220 days ÷ 60 ≈ 8,910.

#### T13 · "Worked on security fixes" → an interim control that bought time

| Version | Bullet |
|---|---|
| **Before** | Worked on security fixes and compliance requirements for ZooKeeper. |
| **After (L6)** | Closed a SOC 2 audit finding 1 month ahead of its deadline by fronting an unauthenticated 5-node ZooKeeper ensemble (read directly by ~300 services) with an mTLS proxy and per-namespace ACLs, buying its replacement 3 months of shadow mode. |
| *No L7 version* | A good judgment call inside V's own program; not org policy. |

**Why it's Staff-shaped anyway:** it shows sequencing judgment, an interim control that de-risks the long-term fix. That's a classic Staff signal ([01.3 in the Past-Project playbook](../../Past-Project-Deep-Dive-L7-Defense-Playbook/01-Anatomy-of-the-60-Minute-Deep-Dive-Round/03-framing-constraints-legacy-tech-debt-client-politics-and-tight-deadlines.md)).

#### T14 · "Wrote reconciliation scripts" → the control a regulator relies on

| Version | Bullet |
|---|---|
| **Before** | Wrote reconciliation scripts to validate data between systems. |
| **After (L6)** | Owned reconciliation for 9 regulatory reports across 38 source tables by comparing per-partition-day control totals (counts, amount sums, order-independent key hashes); it caught a dropped-event defect before any report shipped. |
| *No L7 version* | One program's control. |

#### T15 · "Took interviews" (illustration)

| Version | Bullet |
|---|---|
| **Before** | Took interviews for the team. |
| **After (L6)** | Calibrated the Senior hiring bar for 4 interview panels by writing the system-design rubric they now use, and conducted 120+ design interviews. |
| **After (L7)** | Set the org's Staff-level interview rubric and leveling guide, adopted by 6 hiring teams, by adding calibrated anchor answers per signal; split-level decisions fell from 1 in 4 Staff loops to 1 in 12 within two hiring cycles. |

**Why hiring belongs on an L6/L7 resume:** "raises the bar" is a Staff expectation at most large companies. One bullet is enough.

#### T16 · "Wrote design documents" (illustration)

| Version | Bullet |
|---|---|
| **Before** | Wrote design documents for new features and presented them to stakeholders. |
| **After (L6)** | Authored 9 design docs for the payments domain; 3 became cross-team contracts (idempotency keys, outbox schema, ledger events) consumed by 6 services, cutting new-integration review cycles from 4 rounds to 1. |
| **After (L7)** | Spearheaded the cross-org RFC that standardized event schemas across 4 business units by putting Avro, a schema registry and CI compatibility checks on the paved road, retiring 3 bespoke integration layers and cutting integration lead time from 6 weeks to 4 days. |

### 6.1 What the sixteen pairs teach

| Pattern | Pairs | Rule |
|---|---|---|
| The activity hides the decision | T1, T4, T16 | Ask "what did I decide, and who agreed?" The decision is the bullet |
| The outcome needs a baseline | T2, T3, T8, T12 | "Cut X" means nothing without "from A to B" |
| A technology list kills altitude | T1, T6, T7 | Technologies go in the H slot at most, or in Skills |
| L7 needs other teams | T5, T6, T7, T16 | Leverage means people outside your team changed what they do |
| Honest "no L7 version" | T1–T4, T11, T13, T14 | Most bullets on a strong L6 resume are L6. Two or three real L7 bullets carry an L7 case; ten fake ones sink it |
| Old work can still lead | T3, T4 | Mechanism quality doesn't expire; scope does |

---

## 7. Page architecture of an L6/L7 resume

### 7.1 Two pages, and the page-1 test

At 10–20 years of experience, two pages is normal. Three is too many: a reader who doesn't finish page 2 won't start page 3. The test: **cover page 2. Does page 1 alone make the case for your target level?** If not, you've buried the evidence.

### 7.2 Section order, and Candidate V's page 1

1. **Header:** name, city, relocation intent, phone, email, LinkedIn. GitHub only if it helps.
2. **Summary**, three lines at most: a thesis, not an objective (01.2 §4 builds it).
3. **Selected Impact**, three bullets: your best evidence from anywhere in your career.
4. **Experience**, reverse-chronological. The current role gets 4–6 bullets; older roles shrink.
5. **Technical leadership** (optional, one or two lines): RFCs, forums, interview bar, patents, talks.
6. **Skills**, grouped by depth (§7.5).
7. **Education** (and certifications, if they're relevant to the target).

```text
CANDIDATE V                                   Bengaluru · open to Hyderabad, Singapore, London
+91 XXXXX XXXXX · v@example.com · linkedin.com/in/candidate-v

Staff software engineer, 14 years from avionics firmware to fleet-scale platforms. I make data
move correctly and cheaply across every layer it crosses: interrupt budgets on a 300 MHz MCU,
a 48,000-instance config platform, streaming pipelines, LLM triage at $0.002 a ticket.

SELECTED IMPACT
• Authored the cross-org RFC that set config-safety policy for ~2,000 engineers — staged rings,
  auto-halt, fail-static reads — and retired the colo ZooKeeper ensemble 2 weeks before lease
  end, avoiding a ≥$1.14M extension.
• Drove the PCI scope-reduction strategy across 14 teams: tokenization at the edge shrank the
  cardholder-data environment from 140 hosts to 12 (~$230k/yr) and took every team off the
  45-minute shared release train.
• Cut interrupt CPU from ~20% to <2% on a 12-channel ARINC 429 avionics data concentrator by
  moving label filtering into the protocol IC with DMA, with no board respin.

EXPERIENCE
Consumer marketplace (~2,000 engineers) · Staff Software Engineer        Feb 2023 – present
• Led a 6-engineer team that replaced a ZooKeeper flag store with signed, ring-staged config
  snapshots for 1,200 services (48,000 instances); config-caused Sev-1s 2 → 0 over 12 months.
• Architected LLM-assisted triage for ~41,000 seller-support tickets/day — classifier first,
  LLM only on low-confidence cases, abstain-to-human — misroutes 23% → 8.5% at $0.0021/ticket.
• Established the org's default LLM evaluation gate, adopted by 5 product teams.
• Turned a truncated-LKG incident into a fleet-wide fix (fsync-and-rename, two generations,
  fail-readiness) enforced by a CI crash test.

Omnichannel retailer, Bengaluru tech center · Lead Software Engineer
(tech lead, checkout payments; PCI program across 14 teams)              Sep 2020 – Jan 2023
• Led the checkout-payments redesign for a 2,400 orders/s peak (idempotency keys, outbox,
  saga): duplicate captures 1,214 in one incident → 0; checkout p99 238 → 141 ms.
• [PCI program: see Selected Impact]

Career break · relocation and family caregiving                         Mar 2020 – Aug 2020

IT services firm · Technology Architect
(streaming migration for a US insurer; client team of 9)                 Apr 2018 – Feb 2020
• Architected the CDC → Kafka → Beam/Dataflow replacement for a 6-hour nightly batch
  (180M records/night): worst-case staleness 29.6 h → 3-min p95, one pipeline for stream
  and 7-year backfill.
• Owned reconciliation for 9 regulatory reports across 38 source tables.
                                                         [page 2: R2, R1, leadership, skills]
```

Notice what the Selected Impact block does for V: the strongest firmware mechanism, from 2015, sits on page 1 next to the 2025 policy work. That is the "silicon-to-cloud" case being made *by evidence* before the summary has to argue it (01.2).

**Avoid duplication.** When a bullet is promoted to Selected Impact, the role section keeps only a pointer or a compressed form, as in R4 above.

### 7.3 Titles: never edit them; annotate them

- **Background checks verify titles and dates.** In the US, employment verification goes through the employer or a records service; in India, BGV vendors check with former employers and often against EPFO service history (01.3 §6). A resume title that doesn't match HR records is a discrepancy, and discrepancies get offers rescinded.
- **The fix is a scope note,** in parentheses on the title line: *"Lead Software Engineer (tech lead, checkout payments; PCI program across 14 teams)"*. That's true, checkable by references, and visible in the skim.
- **Never "translate" a title** into the target company's ladder ("Staff-equivalent") on the resume. Say it on the recruiter call, with evidence (Folder 02).
- **LinkedIn must match the resume,** title for title and date for date. Recruiters compare them.

**Title-deflation risk map** ⚠ (field heuristics, not rules):

| Your title | Where | How a FAANG recruiter may read it without evidence |
|---|---|---|
| Principal / Lead Engineer | Company with < 500 engineers | L5–L6; the scope note decides |
| Staff Engineer | Mid-size tech company | L5–L6; depends on whether your scope crossed teams |
| Technology / Technical Architect | IT services firm | Often L5; sometimes lower if it reads as "design without ownership" |
| Lead / Senior Lead | Enterprise in-house team or GCC | L5–L6; ownership of production decides |
| Senior Software Engineer | FAANG-tier company | L5, by definition |

### 7.4 What to delete

**For Indian resumes heading to global-standard companies**, delete: the photo; date of birth or age; marital status; father's name; religion; full home address (city is enough); passport number; a "Declaration: I hereby declare that the above information is true…" line; current and expected CTC (comp is a call topic, Folder 02 and 05); a "Career Objective".

**For everyone**, delete: "References available on request"; skill-rating bars; a GPA at 10+ years; every technology you've touched once; any bullet you can't defend for five minutes.

### 7.5 Skills, grouped by depth

Group skills by how deep you'd go in an interview, not alphabetically:

```text
Production depth:  C (embedded, Cortex-M), C++ (low-latency, lock-free), Java (services, Beam)
Working:           Go, Python, SQL
Data and streaming: Apache Beam / Dataflow, Kafka, BigQuery, PostgreSQL
Platforms:         Kubernetes, gRPC, GCP, signed-artifact delivery, staged rollout
AI systems:        LLM evaluation (golden sets, CI regression gates), retrieval, cost/latency budgets
Safety and compliance: DO-178C (MC/DC), PCI DSS scope reduction, SOC 2 controls
```

The "Production depth" line is a promise: an interviewer may test any item on it at depth. Keep it short.

### 7.6 Format rules that keep you parseable

- One column. Standard headings ("Experience", "Skills", "Education").
- Titles, companies and dates as **text**, not inside tables, text boxes or images.
- A PDF exported from a text-based editor, so the text is selectable. Test it: copy all, paste into a plain-text editor, and check that the order survives.
- 10–11 pt body text; margins around 0.6–0.75 in; no more than two fonts.
- Dates as "Mon YYYY – Mon YYYY" consistently.
- File name: `Firstname-Lastname-Staff-Software-Engineer.pdf`.

---

## 8. LinkedIn: the always-on version

### 8.1 The fields that matter

| Field | Limit (verify in the editor) | What to put there |
|---|---|---|
| **Headline** | 220 characters | Target title + domain + one proof point. Front-load: many surfaces truncate it to the first ~60–70 characters ⚠ |
| **About** | 2,600 characters | Thesis, three proof paragraphs, what you're looking for (01.2 Script 6 is a full example) |
| **Experience** | Per role | The resume bullets, lightly expanded; same titles and dates |
| **Featured** | Links and posts | A public talk, a design write-up, an OSS contribution: anything that shows judgment in your own words |
| **Skills** | Many | The skills you want sourcers to filter on, matching your target JDs |

The limits are as reported by several references in 2025–2026 (for example [AuthoredUp's April 2026 reference](https://authoredup.com/blog/linkedin-character-limit)); LinkedIn changes them, so trust the editor's counter.

**Headline formulas:**

```text
L6 target: Staff Software Engineer · Distributed platforms & streaming data (Java, Beam, Kafka) · Led config platform for 48k instances · Embedded C/C++ roots
L7 target: Staff Engineer → Principal track · Config-safety & data platforms for ~2,000 engineers · Silicon-to-cloud: firmware, C++, Java, LLM evaluation
```

Don't use "Aspiring", "Seeking", "Open to opportunities" or a list of eight technologies.

### 8.2 "Open to Work": the recruiters-only caveat

LinkedIn's "Recruiters only" setting shows your interest to people using LinkedIn Recruiter, not to your whole network. LinkedIn says it takes steps to hide it from recruiters at your current company but **can't guarantee complete privacy** ([LinkedIn Help](https://www.linkedin.com/help/linkedin/answer/67405)). If your search is confidential, assume your employer could find out, and decide on that basis.

### 8.3 How sourcers find you ⚠

Sourcers search with titles, skills, companies, locations and keywords, often as Boolean strings. LinkedIn's ranking is opaque, so the practical rules are:

- Put the **target title words** where they're true: "Staff", "Principal", "Tech Lead", "Architect".
- Use the **target JD's nouns** for things you really did: "streaming", "Dataflow", "config management", "LLM evaluation", "embedded Linux".
- Keep your **location** accurate, and say where you'll relocate in the About section.

### 8.4 Consistency is a trust signal

Recruiters check the resume against LinkedIn, and background checks check both against records. Before any application: titles, dates and employers must match across resume, LinkedIn and the offer-stage forms. A one-month date mismatch looks careless; a title mismatch looks dishonest.

---

## 9. Integrity: every bullet must survive three probes

Before a bullet goes on the page, answer these three in writing:

1. **"What exactly did you decide?"** Name the decision, the alternatives and who agreed.
2. **"What did the team do, and what did you do?"** Use precise grammar: *"I designed X and wrote Y; the team built Z; the platform team owned W."* The [ownership marks](../../Past-Project-Deep-Dive-L7-Defense-Playbook/01-Anatomy-of-the-60-Minute-Deep-Dive-Round/02-how-interviewers-test-if-you-were-the-architect-or-just-a-passenger.md) (★ designed or led · ◆ reviewed or contributed · ○ consumed) make this fast.
3. **"How do you know the number?"** Source, window, comparison (§5.3).

If any answer is weak, shrink the bullet to what you can defend. A smaller, true bullet that you defend with depth is *stronger* evidence of L6 than a larger one you can't.

**Precision beats modesty and inflation alike.** "I led the design; the 6 engineers built it; I wrote the rollout controller with one other engineer" is both honest and high-altitude.

---

## 10. The listing: `bullet_lint.py`

### 10.1 What it does

It reads bullets and reports the **VNBHS-L** slots (§3.1), a score out of 5, flags for executor tells, and a verdict:

| Verdict | Meaning |
|---|---|
| `EXECUTOR` | An executor opener, a weasel phrase or a "we" opener. Rewrite it. |
| `NEEDS-WORK` | No executor tell, but missing a number, too vague, too long or too thin, or fewer than 4 slots |
| `L6-READY` | No flags; at least 4 of the 5 slots |
| `L7-READY` | L6-READY plus leverage (a standard, policy, RFC, adoption, retirement) and breadth (cross-org, org-wide, 3+ teams or 50+ engineers) |

**What it can't do:** tell whether a claim is true, or whether the scope is honest. It's a completeness check. The three probes in §9 are the truth check.

**To use it on your resume:** save the listing as `bullet_lint.py`, put your bullets one per line in `bullets.txt`, and run `python -I bullet_lint.py bullets.txt`.

### 10.2 Listing

<!-- include:bullet_lint.py -->
```python
#!/usr/bin/env python3
"""bullet_lint.py: impact-density linter for Staff/Principal (L6/L7) resume bullets.

It checks that the information a leveling reader looks for is present.
It cannot check that a claim is true; that part is yours (01.1 section 9).

Usage:
  python -I bullet_lint.py resume.txt     one bullet per line ('-', '*' or a bullet character optional)
  python -I bullet_lint.py --kb FILE.md   lint the Before/After rows of a KB file and check expectations

Slots (the 'VNBHS-L' string):
  V altitude verb opens the bullet   N a number with a unit   B a baseline (from/to, ->, vs)
  H the mechanism (how)              S scope (system or org breadth)   L leverage beyond your own work
Standard library only. Python 3.10+.
"""
import re
import sys

EXECUTOR = {
    "worked", "developed", "implemented", "wrote", "coded", "built", "created", "helped",
    "assisted", "participated", "responsible", "involved", "handled", "supported", "used",
    "utilized", "maintained", "tested", "fixed", "coordinated", "delivered", "performed",
    "contributed", "did", "made", "member", "part", "took", "attended", "learned", "gained",
}
ALTITUDE = {
    "architected", "re-architected", "led", "drove", "owned", "defined", "established", "set",
    "authored", "spearheaded", "retired", "eliminated", "standardized", "unified", "consolidated",
    "launched", "shaped", "initiated", "instituted", "founded", "steered", "directed", "scaled",
    "turned", "cut", "reduced", "halved", "raised", "grew", "saved", "replaced", "redesigned",
    "unblocked", "de-risked", "closed", "calibrated", "negotiated", "migrated", "introduced",
    "brought", "removed", "converted", "rebuilt",
}
UNIT = (
    r"%|×|x\b|ms\b|µs\b|us\b|s\b|sec\b|seconds?\b|min\b|minutes?\b|h\b|hours?\b|days?\b|weeks?\b"
    r"|months?\b|quarters?\b|years?\b|[KMB]\b|k\b|GB\b|TB\b|MB\b|PB\b|QPS\b|RPS\b|/s\b|/day\b"
    r"|/night\b|/month\b|/yr\b|/year\b|per\b|engineers?\b|teams?\b|services?\b|instances?\b"
    r"|hosts?\b|nodes?\b|regions?\b|shards?\b|tables?\b|channels?\b|repos?\b|orders?\b|events?\b"
    r"|records?\b|tickets?\b|customers?\b|users?\b|devices?\b|stores?\b|incidents?\b|pages?\b"
    r"|designs?\b|interviews?\b|reports?\b|panels?\b|business units?\b|product teams?\b"
    r"|engineer-hours\b|engineer-quarters\b|cases\b|PRs?\b|clients?\b|tests?\b|vendors?\b"
)
METRIC = re.compile(r"\$\s?\d|\d[\d,.]*\+?\s?(?:[a-z-]+\s)?(?:" + UNIT + r")|\b\d+\s(?:of|in)\s\d+\b")
BASELINE = re.compile(
    r"→|->|\bfrom\b(?:[^;.]|\.(?=\d)){0,80}?\bto\b|\bvs\.?(?=\s)|\bdown from\b|\bup from\b|\bhalved\b"
    r"|\bdoubled\b|\b\d+(?:\.\d+)?×", re.I)
MECHANISM = re.compile(
    r"\b(?:by|via|through|replacing|introducing|moving|using)\b|—|;|\bwith (?:an?|the)\b"
    r"|\breplac\w*\b.*\bwith\b", re.I)
SCOPE_NOUNS = (
    r"engineers|teams|services|instances|hosts|nodes|regions|shards|tables|channels|repos|stores"
    r"|countries|markets|business units|orgs|organizations|product lines|panels|squads|sites"
    r"|devices|customers|users|clients|vendors"
)
SCOPE = re.compile(
    r"\b\d[\d,]*\+?\s+(?:[a-z-]+\s+)?(?:" + SCOPE_NOUNS + r")\b|\b\d+-(?:channel|region|service|team|core|shard)\b"
    r"|\b(?:org-wide|cross-org|company-wide|org's|fleet-wide|multi-team|cross-team|monorepo|portfolio|platform)\b",
    re.I)
LEVERAGE = re.compile(
    r"\b(?:adopt\w*|standard\w*|default|template|reference (?:architecture|implementation)|paved[- ]road"
    r"|guardrails?|policy|policies|playbook|RFC|strategy|roadmap|direction|reused|rolled out to"
    r"|mandated|retired|retiring|deprecated|operating model|hiring bar|forum|rubric)\b", re.I)
BREADTH_WORD = re.compile(r"\b(?:cross-org|org-wide|company-wide|org's|division-wide)\b", re.I)
BREADTH_NUM = re.compile(
    r"\b(\d[\d,]*)\+?\s+(?:[a-z-]+\s+)?(teams|business units|orgs|organizations|product lines|engineers)\b", re.I)
WEASEL = re.compile(
    r"(?<![\w-])(?:helped|assisted|participated|involved in|responsible for|various|several|multiple"
    r"|etc\.?|worked on|exposure to|familiar with|tasked with|part of|duties included)(?![\w-])", re.I)
VAGUE = re.compile(
    r"\b(?:significantly|drastically|greatly|massively|hugely|substantially|dramatically|considerably"
    r"|vastly|tremendously|improved performance|enhanced|optimized|optimised|robust|seamless"
    r"|cutting-edge|state-of-the-art|best-in-class|world-class)\b", re.I)
TECH = [
    "java", "spring boot", "spring", "kafka", "beam", "dataflow", "bigquery", "kubernetes", "k8s",
    "docker", "aws", "gcp", "azure", "redis", "postgresql", "postgres", "mysql", "c\\+\\+", "python",
    "golang", "react", "terraform", "jenkins", "airflow", "spark", "flink", "grpc", "rest",
    "microservices", "llms?", "rag", "langchain", "vector db", "fastapi", "pytorch", "tensorflow",
    "linux", "git", "jira", "javascript", "typescript", "node\\.js", "mongodb", "elasticsearch",
]
TECH_RE = [re.compile(r"(?<![\w+])" + t + r"(?![\w+])", re.I) for t in TECH]
ROW = re.compile(r"^\|\s*\*\*(Before|After \(L6\)|After \(L7\))[^|]*\*\*\s*\|\s*(.+?)\s*\|\s*$")
PAIR = re.compile(r"^#{3,5}\s+(T\d+[a-z]?)\b")


def words(text):
    return re.findall(r"[^\s]+", text)


def breadth(text):
    if BREADTH_WORD.search(text):
        return True
    for num, noun in BREADTH_NUM.findall(text):
        n = int(num.replace(",", ""))
        if noun.lower() == "engineers" and n >= 50:
            return True
        if noun.lower() != "engineers" and n >= 3:
            return True
    return False


def lint(bullet):
    text = bullet.strip().lstrip("-*•· ").strip()
    w = words(text)
    first = re.sub(r"[^a-z-]", "", w[0].lower()) if w else ""
    second = re.sub(r"[^a-z-]", "", w[1].lower()) if len(w) > 1 else ""
    slots = {
        "V": first in ALTITUDE,
        "N": bool(METRIC.search(text)),
        "B": bool(BASELINE.search(text)),
        "H": bool(MECHANISM.search(text)),
        "S": bool(SCOPE.search(text)),
    }
    lev = bool(LEVERAGE.search(text))
    wide = breadth(text)
    flags = []
    if first in EXECUTOR:
        flags.append("EXECUTOR-OPENER")
    if first in {"we", "our", "team"} or (first == "the" and second == "team"):
        flags.append("WE-OPENER")
    if WEASEL.search(text):
        flags.append("WEASEL")
    if VAGUE.search(text):
        flags.append("VAGUE")
    techs = sum(1 for r in TECH_RE if r.search(text))
    if techs >= 5:
        flags.append("TECH-SOUP")
    if not slots["N"]:
        flags.append("NO-METRIC")
    if len(w) > 48:
        flags.append("LONG")
    if len(w) < 8:
        flags.append("THIN")
    score = sum(slots.values())
    if flags:
        verdict = "EXECUTOR" if {"EXECUTOR-OPENER", "WEASEL", "WE-OPENER"} & set(flags) else "NEEDS-WORK"
    elif score >= 4:
        verdict = "L7-READY" if (lev and wide) else "L6-READY"
    else:
        verdict = "NEEDS-WORK"
    slot_str = "".join(k if v else "-" for k, v in slots.items()) + ("L" if lev else "-")
    return {"verdict": verdict, "score": score, "slots": slot_str, "flags": flags,
            "words": len(w), "text": text}


def show(tag, r):
    head = r["text"] if len(r["text"]) <= 64 else r["text"][:61] + "..."
    flags = ",".join(r["flags"]) if r["flags"] else "none"
    return f"{tag:<9} {r['verdict']:<10} {r['score']}/5 {r['slots']}  {r['words']:>2}w  flags={flags}\n          {head}"


EXPECT = {
    "Before": {"EXECUTOR", "NEEDS-WORK"},
    "After (L6)": {"L6-READY", "L7-READY"},
    "After (L7)": {"L7-READY"},
}


def kb_mode(path):
    pair = "?"
    seen = {"Before": [0, 0], "After (L6)": [0, 0], "After (L7)": [0, 0]}
    bad = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = PAIR.match(line)
            if m:
                pair = m.group(1)
                continue
            m = ROW.match(line.rstrip("\n"))
            if not m:
                continue
            kind, text = m.group(1), m.group(2)
            r = lint(text)
            ok = r["verdict"] in EXPECT[kind]
            seen[kind][0] += 1
            seen[kind][1] += ok
            mark = "ok " if ok else "BAD"
            print(f"{mark} {pair:<4} " + show(kind.replace("After ", ""), r))
            if not ok:
                bad.append(f"{pair} {kind}")
    print("-" * 72)
    print("Before rows flagged:      %d/%d" % (seen["Before"][1], seen["Before"][0]))
    print("After (L6) rows ready:    %d/%d" % (seen["After (L6)"][1], seen["After (L6)"][0]))
    print("After (L7) rows L7-ready: %d/%d" % (seen["After (L7)"][1], seen["After (L7)"][0]))
    print("VERDICT: " + ("OK" if not bad else "FAIL " + "; ".join(bad)))
    return 0 if not bad else 1


def file_mode(path):
    counts = {}
    total = 0
    with open(path, encoding="utf-8") as fh:
        lines = [ln.strip() for ln in fh if ln.strip()]
    for i, ln in enumerate(lines, 1):
        r = lint(ln)
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
        total += r["score"]
        print(show(f"#{i}", r))
    n = max(1, len(lines))
    print("-" * 72)
    print("bullets %d · mean slots %.1f/5 · " % (len(lines), total / n)
          + " · ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    return 0


def main(argv):
    sys.stdout.reconfigure(encoding="utf-8")
    if len(argv) == 3 and argv[1] == "--kb":
        return kb_mode(argv[2])
    if len(argv) == 2:
        return file_mode(argv[1])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

### 10.3 Output: this file's sixteen pairs

<!-- run:bullet_lint.py --kb SELF -->
```text
ok  T1   Before    EXECUTOR   1/5 ---H--  13w  flags=EXECUTOR-OPENER,NO-METRIC
          Developed Java pipelines using Apache Beam, Kafka and BigQuer...
ok  T1   (L6)      L6-READY   5/5 VNBHS-  37w  flags=none
          Architected the CDC → Kafka → Beam/Dataflow replacement for a...
ok  T2   Before    EXECUTOR   0/5 ------  12w  flags=EXECUTOR-OPENER,WEASEL,VAGUE,NO-METRIC
          Worked on C++ modules for the ranking service and improved pe...
ok  T2   (L6)      L6-READY   5/5 VNBHS-  42w  flags=none
          Replaced a 32-shard Redis fan-out with an in-process C++ feat...
ok  T3   Before    EXECUTOR   0/5 ------  15w  flags=EXECUTOR-OPENER,NO-METRIC
          Wrote embedded C code for ARINC 429 drivers on ARM Cortex-M7 ...
ok  T3   (L6)      L6-READY   5/5 VNBHS-  43w  flags=none
          Cut interrupt CPU from ~20% to <2% on a 12-channel ARINC 429 ...
ok  T4   Before    EXECUTOR   1/5 ---H--  12w  flags=EXECUTOR-OPENER,WEASEL,NO-METRIC
          Participated in design discussions with the hardware team and...
ok  T4   (L6)      L6-READY   5/5 VNBHS-  37w  flags=none
          Authored the hardware/software decision memo — protocol-IC la...
ok  T5   Before    EXECUTOR   1/5 ---H--  12w  flags=EXECUTOR-OPENER,WEASEL,NO-METRIC
          Responsible for payment microservices in Java Spring Boot; fi...
ok  T5   (L6)      L6-READY   4/5 VNBH--  43w  flags=none
          Led the checkout-payments redesign for a 2,400 orders/s peak ...
ok  T5   (L7)      L7-READY   4/5 VNB-SL  37w  flags=none
          Drove the PCI scope-reduction strategy across 14 teams: token...
ok  T6   Before    EXECUTOR   1/5 ---H--  12w  flags=EXECUTOR-OPENER,NO-METRIC
          Built a configuration management service using gRPC and Postg...
ok  T6   (L6)      L6-READY   5/5 VNBHS-  39w  flags=none
          Led a 6-engineer team that replaced a ZooKeeper flag store wi...
ok  T6   (L7)      L7-READY   4/5 VN-HSL  37w  flags=none
          Authored the cross-org RFC (3 alternatives, 2 revisions) that...
ok  T7   Before    EXECUTOR   1/5 ---H--  13w  flags=EXECUTOR-OPENER,TECH-SOUP,NO-METRIC
          Built an AI chatbot using LLMs, LangChain, RAG, vector DB, Py...
ok  T7   (L6)      L6-READY   4/5 VNBH--  34w  flags=none
          Architected LLM-assisted triage for ~41,000 seller-support ti...
ok  T7   (L7)      L7-READY   4/5 VN-HSL  37w  flags=none
          Established the org's default LLM evaluation gate (golden set...
ok  T8   Before    NEEDS-WORK 1/5 V-----   8w  flags=VAGUE,NO-METRIC
          Migrated services to Kubernetes and optimized cloud costs.
ok  T8   (L6)      L6-READY   5/5 VNBHS-  36w  flags=none
          Cut the search tier's compute spend from $1.9M to $1.2M a yea...
ok  T8   (L7)      L7-READY   5/5 VNBHSL  36w  flags=none
          Set the org's FinOps operating model — unit-cost dashboards p...
ok  T9   Before    EXECUTOR   1/5 ----S-   9w  flags=EXECUTOR-OPENER,NO-METRIC
          Handled production incidents and on-call for the platform team.
ok  T9   (L6)      L6-READY   4/5 VN-HS-  36w  flags=none
          Turned a 6-minute incident (0.3% of instances serving compile...
ok  T9   (L7)      L7-READY   5/5 VNBHSL  28w  flags=none
          Instituted the org-wide incident-review standard (blameless r...
ok  T10  Before    NEEDS-WORK 0/5 ------   7w  flags=NO-METRIC,THIN
          Mentored junior engineers and conducted code reviews.
ok  T10  (L6)      L6-READY   5/5 VNBHSL  35w  flags=none
          Grew 3 engineers to Senior by pairing each with one RFC they ...
ok  T10  (L7)      L7-READY   4/5 VN-HSL  30w  flags=none
          Founded the Staff+ design forum that reviews every cross-team...
ok  T11  Before    EXECUTOR   0/5 ------   7w  flags=EXECUTOR-OPENER,WEASEL,NO-METRIC,THIN
          Involved in migration of monolith to microservices.
ok  T11  (L6)      L6-READY   4/5 VN-HS-  34w  flags=none
          Drove the strangler-fig migration of the order monolith's pri...
ok  T12  Before    NEEDS-WORK 0/5 ------   7w  flags=NO-METRIC,THIN
          Improved CI/CD pipelines and reduced build times.
ok  T12  (L6)      L6-READY   5/5 VNBHS-  28w  flags=none
          Cut median CI time from 38 to 11 minutes for a 120-engineer m...
ok  T12  (L7)      L7-READY   4/5 VN-HSL  31w  flags=none
          Defined the org-wide build-health SLOs (p50 CI ≤ 12 min, flak...
ok  T13  Before    EXECUTOR   0/5 ------   9w  flags=EXECUTOR-OPENER,WEASEL,NO-METRIC
          Worked on security fixes and compliance requirements for ZooK...
ok  T13  (L6)      L6-READY   4/5 VN-HS-  39w  flags=none
          Closed a SOC 2 audit finding 1 month ahead of its deadline by...
ok  T14  Before    EXECUTOR   0/5 ------   8w  flags=EXECUTOR-OPENER,NO-METRIC
          Wrote reconciliation scripts to validate data between systems.
ok  T14  (L6)      L6-READY   4/5 VN-HS-  30w  flags=none
          Owned reconciliation for 9 regulatory reports across 38 sourc...
ok  T15  Before    EXECUTOR   0/5 ------   5w  flags=EXECUTOR-OPENER,NO-METRIC,THIN
          Took interviews for the team.
ok  T15  (L6)      L6-READY   4/5 VN-HSL  22w  flags=none
          Calibrated the Senior hiring bar for 4 interview panels by wr...
ok  T15  (L7)      L7-READY   5/5 VNBHSL  38w  flags=none
          Set the org's Staff-level interview rubric and leveling guide...
ok  T16  Before    EXECUTOR   0/5 ------  11w  flags=EXECUTOR-OPENER,NO-METRIC
          Wrote design documents for new features and presented them to...
ok  T16  (L6)      L6-READY   5/5 VNBHS-  31w  flags=none
          Authored 9 design docs for the payments domain; 3 became cros...
ok  T16  (L7)      L7-READY   5/5 VNBHSL  42w  flags=none
          Spearheaded the cross-org RFC that standardized event schemas...
------------------------------------------------------------------------
Before rows flagged:      16/16
After (L6) rows ready:    16/16
After (L7) rows L7-ready: 9/9
VERDICT: OK
```

The run confirms the shape of §6: all sixteen Before rows are flagged, every L6 row passes, and every L7 row shows leverage plus breadth. Look at T8: its Before row opens with an altitude verb ("Migrated") and still gets `NEEDS-WORK`, for the missing number and the vague "optimized".

---

## 11. Word-for-word scripts

Placeholders are in `[BRACKETS]`. Read each script aloud before using it; if a sentence isn't true for you, cut it rather than soften it.

#### Script 1 · Email: sending your resume to a recruiter who reached out (anchors the level)

```text
Subject: [Your Name] · Staff Software Engineer · [Role title / req ID if known]

Hi [Recruiter name],

Thanks for reaching out. My resume is attached. The short version of the level case:

1. Platform at org scale: I led a 6-engineer team that replaced our ZooKeeper flag store
   for 1,200 services (48,000 instances), and authored the cross-org RFC that now sets
   config-safety policy for ~2,000 engineers.
2. Cross-team programs: I drove a PCI scope-reduction strategy across 14 teams
   (140 → 12 in-scope hosts).
3. Depth from silicon to cloud: avionics firmware, low-latency C++, streaming pipelines,
   and an LLM evaluation gate now used by 5 product teams.

I'm interviewing selectively for Staff-level (L6) roles, and I'd like to understand whether
this req is open at L6 or above. I'm free for a call [two specific windows, with time zone].

Best,
[Your Name]
[Phone] · [LinkedIn URL]
```

#### Script 2 · LinkedIn reply: a recruiter pitches a Senior (L5) role

```text
Hi [Name], thanks for thinking of me. I'm currently a Staff engineer [or: operating at
Staff scope, as tech lead for a platform used by 1,200 services], so I'm focusing on
L6-level roles. If [Company] has a Staff opening on [platform / data infrastructure /
AI systems], I'd be glad to talk. If it helps, I can send a one-page summary of the
cross-team work first.
```

#### Script 3 · DM: asking an L6+ insider for a referral

```text
Hi [Name], I'm a Staff engineer at [Company] working on [config platforms / streaming
data / LLM evaluation]. I saw [their talk / post / team's work on X], and [Team] looks
like a close match for what I've done: [one line, e.g. "I led a config platform for
48,000 instances and set its rollout-safety policy across the org"].

Would you be open to a 15-minute call about the team? If after that you think I'm a fit,
I'd be grateful for a referral. I'll send you a three-line summary so it takes you no time.
```

#### Script 4 · Email: the referral blurb your referrer can paste

```text
Subject: Referral blurb: [Your Name], Staff Software Engineer

Hi [Name], thank you again. Here's a blurb you can paste into the referral form, edited
however you like:

"[Your Name] is a Staff engineer at [Company] (14 years). Led the team that replaced a
ZooKeeper flag store for 1,200 services and authored the cross-org config-safety RFC;
drove a PCI scope-reduction program across 14 teams; started in avionics firmware and
low-latency C++. Targeting L6 on [Team / req ID]."

Resume attached. Please tell me when it's submitted so I can follow up with the recruiter.

[Your Name]
```

#### Script 5 · Verbal: "Walk me through your resume" (90 seconds, L6 target)

```text
"Sure. The thread through my career is making data move correctly and cheaply, at every
layer from hardware to fleet.

Most recently I'm a Staff engineer at [marketplace]. I led the team that replaced our
ZooKeeper-based flag store for 1,200 services. The interesting part wasn't the storage,
it was safety: every change now rolls through staged rings with automatic halts, and
config-caused Sev-1s went from 2 a year to 0. I wrote the RFC that made that the
org-wide policy. I also built our LLM evaluation gate, which five teams now use.

Before that, at [retailer], I led the checkout-payments redesign. We went from 1,214
double charges in one incident to zero, and I drove the PCI program across 14 teams.

Earlier I built a streaming replacement for an insurer's nightly batch, a low-latency C++
feature cache, and avionics firmware, which is where I learned to treat every
microsecond and every dropped message as something you account for.

I'm looking for a Staff role where the problem crosses team boundaries. Your [platform /
data] team looked like that. Where would you like me to go deeper?"
```

#### Script 6 · Verbal: the same question at an L7 target (2 minutes)

```text
"I'll give you the arc and then the two decisions I'd want you to judge me on.

The arc: fourteen years from firmware to fleet. I started on avionics data concentrators,
moved to low-latency C++ ranking, then streaming data, payments, and now platform and AI
systems at [marketplace], where I'm the Staff engineer for config and rollout safety.

Decision one: our config outages all had the same shape, a bad change reaching every
instance in seconds. I wrote the cross-org RFC that changed the rules for ~2,000
engineers: staged rings, automatic halts, and reads that never block on the control
plane. I also sequenced it so we retired the old ZooKeeper ensemble two weeks before a
colo lease would have cost us over a million dollars to extend.

Decision two: when teams started shipping LLM features, nobody could say whether a prompt
change made things better or worse. I set up an evaluation gate, golden sets and
regression thresholds in CI with cost budgets, and made it the default. Five product
teams use it now.

What I'm looking for is the next step in that pattern: a problem where the org needs
someone to define the direction, write it down, and make it stick across teams. That's
why the [specific org problem] caught my eye. Which of those would be most useful to
unpack?"
```

#### Script 7 · Verbal: the recruiter says "Your resume reads more Senior than Staff"

```text
"That's useful feedback, thank you. Can I give you the two pieces of evidence I'd want the
hiring manager to see, and you tell me if they change the read?

First, scope: the config platform I led serves 1,200 services, and the RFC I wrote sets
the rollout policy for about 2,000 engineers, well beyond my own team.

Second, cross-team programs: the PCI work changed how 14 teams deploy, and I owned the
plan and the sequencing.

If the resume isn't making that visible, I'll fix the resume. What I'd ask is that the
intake note to the hiring manager says I'm being considered for L6, so the loop is
calibrated to Staff signals from the start."
```

#### Script 8 · Email: asking a former manager to confirm numbers and what you may cite

```text
Subject: Quick check on two numbers for my resume

Hi [Manager's name],

I hope you're well. I'm updating my resume and want every number on it to be accurate
and shareable. Could you sanity-check these two?

1. "[Bullet with number, e.g. duplicate captures from 1,214 in one incident to zero]"
2. "[Bullet with number, e.g. PCI scope 140 → 12 hosts, ~$230k/yr]"

Also, is it OK to describe the client as "[proposed description, e.g. a US insurer]",
or would you prefer something more generic?

And if you'd be willing to be a reference later in the process, I'd be very grateful.
I'll only share your name once there's an offer-stage request, and I'll tell you first.

Thank you,
[Your Name]
```

#### Script 9 · Verbal: "What was your exact title there?" when the title under-sells the scope

```text
"My title was Lead Software Engineer. That's [Retailer]'s title for its senior-most IC
track in the tech center. In practice I was the tech lead for checkout payments, and I
ran the PCI scope-reduction program across 14 teams. My references there can speak to
that scope, and I'm happy to connect you with my former director."
```

#### Script 10 · Email: a five-line level case for the recruiter's intake note

```text
Subject: Five-line summary for the hiring-manager intake ([Role / req ID])

Hi [Recruiter name], in case it helps your submission, here's the level case in five lines:

• Scope: Staff tech lead for a config platform serving 1,200 services (48,000 instances).
• Direction: authored the cross-org RFC that sets config-safety policy for ~2,000 engineers.
• Cross-team program: PCI scope reduction across 14 teams (140 → 12 in-scope hosts).
• Leverage: LLM evaluation gate adopted by 5 product teams.
• Depth: avionics firmware, low-latency C++, streaming pipelines; strongest in [area for this role].

Target level: L6 (Staff). Happy to adjust the emphasis for this team.
[Your Name]
```

---

## 12. Probe chains

How recruiters, hiring managers and committee members push on a resume, and the two kinds of answer.

<details><summary><b>P1 · "You wrote 'Architected'. What exactly did you architect?"</b></summary>

**Probe:** "Your first bullet says you architected the pipeline. Walk me through what that meant."

**What they're testing:** whether the verb has an artifact behind it: a design with rejected alternatives, and decisions you can name.

**Executor answer:** "I was the main developer. I wrote most of the Beam code and set up the Kafka topics."

**Staff/Principal answer:** "Three decisions. One: CDC instead of a faster batch, because the 30-minute freshness requirement killed every batch option. Two: one pipeline for both streaming and the 7-year backfill, so there was one set of semantics to verify. Three: a reconciliation job as a separate control, because the regulatory reports needed proof, not trust. I wrote the design doc with those three alternatives; the client's data director signed it."

</details>

<details><summary><b>P2 · "Where did that number come from?"</b></summary>

**Probe:** "You say config Sev-1s went from 2 to 0. Over what period, and how do you know they were config-caused?"

**What they're testing:** whether your numbers are measured, and whether you understand attribution.

**Executor answer:** "That's what the team reported at the end of the year."

**Staff/Principal answer:** "From the incident tracker: 12 months before cutover against 12 months after, using the 'config change' root-cause tag, which existed before the project, so I didn't define the metric to suit myself. Two Sev-1s before; zero after. Our ring0 also halted three bad changes automatically, and the worst reached 1.1% of instances for 4 minutes. That's the better evidence, because it shows the mechanism working rather than just a lucky year."

</details>

<details><summary><b>P3 · "Was this you or the team?"</b></summary>

**Probe:** "You led a team of six. Which parts did you personally build?"

**What they're testing:** ownership precision. A Staff engineer can say exactly where their hands were.

**Executor answer:** "We all worked on everything together; it was very collaborative."

**Staff/Principal answer:** "I designed the snapshot format, the signature and version checks, and the SDK semantics, and wrote the Java reference SDK. I co-wrote the rollout controller with one engineer. The relay tier was another engineer's design that I reviewed. The Go and Python SDK ports were the language-platform teams'. My leverage was the RFC and the semantics everyone else implemented against."

</details>

<details><summary><b>P4 · "This was eight years ago. Why is it on page 1?"</b></summary>

**Probe:** "Your Selected Impact has a firmware bullet from 2015. That's not the job we're hiring for."

**What they're testing:** whether you've made a deliberate narrative choice or just padded.

**Executor answer:** "I just wanted to show I have embedded experience too."

**Staff/Principal answer:** "It's there because it's the cleanest example of how I work: I measured the interrupt load, wrote the trade-off memo, and the cheapest fix turned out to be configuring a chip we already had, not a board respin. I use the same reasoning on cloud cost: change the system's shape, not just its size. The config platform's fail-static design came straight from firmware habits: never block on something you don't control."

</details>

<details><summary><b>P5 · "Your title was Lead, not Staff."</b></summary>

**Probe:** "You're applying for Staff, but your title at [Retailer] was Lead Software Engineer."

**What they're testing:** whether you'll inflate under pressure, and whether you can show scope with evidence.

**Executor answer:** "It was basically a Staff role, I just didn't get the title."

**Staff/Principal answer:** "Correct, Lead was the title. What I can show you is the scope: I was the tech lead for checkout payments and I ran the PCI program across 14 teams. The plan, the sequencing and the negotiation with each team's lead were mine. My director can confirm that. I'd rather you level me on that evidence than on any title."

</details>

<details><summary><b>P6 · "These are big claims for one person."</b></summary>

**Probe:** "PCI scope, 14 teams, a release train: that sounds like a whole program office."

**What they're testing:** whether the L7-style bullet survives contact, and whether you know who else carried it.

**Executor answer:** "I did a lot of it myself; I worked very long hours."

**Staff/Principal answer:** "It was a program, and I didn't do it alone. I owned the technical strategy: tokenize at the edge so card data reaches one service. I wrote the per-team migration plan, and I ran the weekly review where teams reported blockers. The tokenization service was built by a team of four I didn't manage. Each team did its own migration. The compliance team owned the auditor. My job was making 14 teams' changes add up to one scope reduction."

</details>

<details><summary><b>P7 · "Why should I believe the AI numbers?"</b></summary>

**Probe:** "Misroutes from 23% to 8.5%: on what data, and how do you know it isn't overfit?"

**What they're testing:** evaluation literacy, the thing that separates AI engineering from demos.

**Executor answer:** "We tested it and the accuracy was much better."

**Staff/Principal answer:** "A held-out set of 2,400 labeled tickets, sampled across all 31 queues and frozen before we wrote a single prompt. None of those tickets were used as retrieval exemplars, which we enforce with an ID check in CI. 23% is the keyword router on that same set. In production we watch the human-reassignment rate as the online proxy. And the abstain path matters as much as accuracy: about 6% go straight to humans, by design."

</details>

<details><summary><b>P8 · The committee reads the resume after a mixed loop</b></summary>

**Probe:** (Committee member, to the recruiter) "The resume claims org-wide policy, but the design interviewer wrote 'solid, but stayed inside one system'. Is this an L6 or a strong L5?"

**What they're testing:** whether the paper scope and the observed scope agree. You aren't in the room, so your resume and your interview stories must say the same thing.

**Executor answer:** (What an inflated resume produces) The member discounts the resume entirely and levels on the weakest round: L5.

**Staff/Principal answer:** (What a consistent candidate produces) The resume's org-wide claim matches a behavioral-round story about the RFC with names, dissent and a decision, and the design interviewer's note is read as one round's scope, not a ceiling. The packet argues for L6. You prepare for this before the loop by making sure each L7-style bullet has a story in your story bank ([Behavioral playbook, Folder 08](../../Staff-Principal-Behavioral-L7-Playbook/08-Master-8-Story-Bank-Matrix-and-Interview-Prep-Playbook/)).

</details>

<details><summary><b>P9 · "What would you do differently?"</b></summary>

**Probe:** "On the config platform, what was your biggest mistake?"

**What they're testing:** whether the resume's polish hides an inability to own failure, a disqualifier at L6+.

**Executor answer:** "Honestly, it went really well. Maybe we could have finished faster."

**Staff/Principal answer:** "The last-known-good file. We wrote it in place without an fsync, and when a node was hard-stopped mid-write during a control-plane brownout, about 0.3% of instances served compiled-in defaults for 6 minutes. That's on my design. We fixed it with write-to-temp, fsync, rename, two generations, and a policy that critical namespaces fail readiness rather than serve defaults. I added a CI test that kills the process mid-write. It's on my resume as a bullet because the fix changed the fleet."

</details>

---

## 13. Checklist: the two-hour rewrite sprint

**Minute 0–30: inventory.**
- [ ] List every project from the last 8 years with: your decision, the alternatives, the number, the scope, who adopted it.
- [ ] Mark each with ★ / ◆ / ○ ownership (§9).
- [ ] Write the numbers card: source, window, comparison for each number (§5.3).

**Minute 30–75: bullets.**
- [ ] Rewrite each bullet into the five slots; add L only where others really adopted something.
- [ ] Run `bullet_lint.py` (§10). Fix every `EXECUTOR`; justify or fix every `NEEDS-WORK`.
- [ ] Pick three bullets for Selected Impact (one can be old if its mechanism is your sharpest).
- [ ] Check each L7-style bullet against §9's three probes.

**Minute 75–105: page.**
- [ ] Page-1 test: cover page 2; does page 1 make the level case?
- [ ] Titles exactly as in HR records, with scope notes in parentheses.
- [ ] Delete the §7.4 list; regroup skills by depth.
- [ ] Copy-paste test for parseability.

**Minute 105–120: LinkedIn and consistency.**
- [ ] Headline (front-loaded), About (thesis + proof), Experience matching the resume.
- [ ] Titles and dates identical across resume, LinkedIn and your records.
- [ ] Send Script 8 to anyone whose numbers you're citing.

---

## 14. References

- Ladders eye-tracking study (2018), as reported by HR Dive: [Eye-tracking study shows recruiters look at résumés for 7 seconds](https://www.hrdive.com/news/eye-tracking-study-shows-recruiters-look-at-resumes-for-7-seconds/541582/).
- Laszlo Bock's X-Y-Z formula: "My Personal Formula for a Winning Resume" (LinkedIn, 29 September 2014), [mirrored by Cal State LA](https://www.calstatela.edu/sites/default/files/formula_for_a_winning_resume.docx); the earlier "relative to Y" version, [Quartz](https://qz.com/201088/google-just-revealed-the-incredibly-simple-formula-for-killer-resumes).
- The "75% rejected by ATS" claim and its origin: [HiringThing](https://www.hiringthing.com/blog/applicant-tracking-system-myths).
- Ladders side by side: [Levels.fyi leveling comparison report](https://www.levels.fyi/reports/examples/leveling-comparison-report.html).
- LinkedIn Open to Work visibility: [LinkedIn Help](https://www.linkedin.com/help/linkedin/answer/67405). Field limits: [AuthoredUp, LinkedIn character limits](https://authoredup.com/blog/linkedin-character-limit).
- Staff archetypes and what Staff work looks like: Will Larson, [StaffEng: Staff archetypes](https://staffeng.com/guides/staff-archetypes/); Tanya Reilly, *The Staff Engineer's Path* (O'Reilly, 2022), ISBN 9781098118730.
- Companion KBs: [Past-Project Deep-Dive L7 Defense Playbook](../../Past-Project-Deep-Dive-L7-Defense-Playbook/README.md) (the defense of every V bullet); [Staff/Principal Behavioral L7 Playbook](../../Staff-Principal-Behavioral-L7-Playbook/01-L5-vs-L6-vs-L7-Scope-and-Hiring-Committee-Rubrics/01-how-hiring-committees-detect-l5-vs-l6-vs-l7-scope.md) (how committees read the signal).
