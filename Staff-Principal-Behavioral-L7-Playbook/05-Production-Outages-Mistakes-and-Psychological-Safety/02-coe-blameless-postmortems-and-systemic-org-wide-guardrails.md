# 05.2 · COEs, Blameless Postmortems and Systemic Org-Wide Guardrails

> **Folder 05 · File 2 of 3.** Every senior candidate says they "ran a blameless postmortem". The committee is listening for two things that separate L7 from L5. First: did your postmortem change **the system that allowed the failure**, or just the instance? Second: did one team's lesson become **an organization's guardrail**, so that teams who never had the incident are now protected from it?
>
> This file covers:
> - the COE and the postmortem: structure, and what good looks like;
> - blamelessness as an engineering practice, not a courtesy;
> - the remediation hierarchy: pushing action items from "be more careful" to "impossible by construction";
> - propagating a lesson across an org: patterns across COEs, platform defaults, readiness reviews, game days;
> - action items that never close, and how to stop that;
> - psychological safety in technical forums;
> - a rubric, three story blueprints and five follow-up chains.
>
> Stories are **illustrative composites**.

---

## 1. The COE and the postmortem

Amazon's **Correction of Error (COE)** and Google's **postmortem** are the best-known formats; most companies run something similar. AWS's own description of a COE lists these sections: incident summary, impact, timeline, metrics, incident questions, the five whys, action items, and related items.

| Section | What good looks like | What weak looks like |
|---|---|---|
| **Summary** | Three sentences a VP can read: what happened, impact, the most important fix | A narrative of the incident channel |
| **Impact** | Customers, revenue, duration, data, trust; quantified | "Some users were affected" |
| **Timeline** | Detection, escalation, mitigation and recovery times, with gaps explained | Every message from the channel |
| **Metrics** | The graphs that show the failure and the recovery | None |
| **Questions** | How was it detected? Could it have been detected sooner? Why did mitigation take as long as it did? | Skipped |
| **Contributing factors / five whys** | Several causal chains, each reaching a system property | One chain ending at "engineer error" |
| **Action items** | Owned, dated, prioritized, at the highest level of the remediation hierarchy possible (§3) | "Be more careful"; "add monitoring"; no owners |

### 1.1 Five whys, and their limits

Five whys is useful because it forces past the first answer. Its weakness is that it implies **a single chain to a single root cause**. Richard Cook's *How Complex Systems Fail* argues that catastrophes require multiple failures together, and that post-accident attribution to a single root cause is fundamentally wrong. Strong COEs run several chains:
- why did the change cause harm?
- why wasn't it caught before production?
- why did detection take as long as it did?
- why did mitigation take as long as it did?
- why was the blast radius as large as it was?

The last two chains are the ones L5 postmortems usually skip, and they're often where the org-wide fix lives.

---

## 2. Blamelessness as an engineering practice

Google's SRE book (*Postmortem Culture: Learning from Failure*) states the principle: a blameless postmortem assumes everyone involved acted with good intentions on the information they had. John Allspaw's 2012 Etsy essay *Blameless PostMortems and a Just Culture* adds the practical reason: if engineers fear punishment, they stop giving the detailed accounts you need to understand the failure.

So blamelessness isn't kindness. It's **how you get accurate data**.

What it means in practice:
- **Ask "what made this make sense at the time?"**, not "why did you do that?"
- **Treat human error as a symptom**, not a cause: "the engineer ran the script against production" is the start of an investigation, not its end.
- **Name the system properties**: the tool that made production the default, the missing dry run, the alert that didn't fire.
- **Blameless isn't consequence-free for the system.** Owners of the system that allowed the failure get action items.

Blamelessness also isn't the absence of accountability. **Accountability shifts to the people who design the system**, and senior engineers are usually those people. An L7 who caused an outage still owns it (05.1); what they don't do is blame the person who pushed the button.

---

## 3. The remediation hierarchy

Action items differ hugely in how reliably they prevent recurrence. Borrowing from the hierarchy of controls in occupational safety, rank them:

| Level | Type | Example | Reliability |
|---|---|---|---|
| **1. Eliminate** | Remove the hazard entirely | Delete the dangerous admin endpoint; retire the manual process | Highest |
| **2. Engineer it out** | Make the unsafe action impossible or automatically safe | Staged config rollout with automatic halt; dry run by default; least-privilege access | High |
| **3. Detect and contain** | Catch it fast and limit the blast radius | Alerts on the leading signal; cells; circuit breakers; automatic rollback | Medium–high |
| **4. Process** | Add a check people must follow | Review checklist; two-person rule; change advisory | Medium |
| **5. Training and awareness** | Tell people to be careful | "Be more careful"; a wiki page; a talk | Lowest |

**The L7 move is to push action items up the hierarchy.** "We'll train engineers on the migration tool" becomes "the migration tool now runs in dry-run mode unless the operator passes a production flag and a second engineer approves". The committee notices which level your action items are at.

---

## 4. From one team's lesson to an org's guardrail

A COE that fixes the team that had the incident protects one team. An L7 asks: **who else has this hazard and hasn't had the incident yet?**

### 4.1 Patterns across COEs

| Practice | What it does |
|---|---|
| **Tag every COE** with contributing-factor categories (config change, dependency failure, capacity, data migration, certificate expiry, access) | Makes patterns countable |
| **A quarterly review of COE themes** across the org | Finds the categories that cause most of the impact |
| **A "COE of COEs"** for the top category | Treats a recurring class of failure as one problem with one owner |

### 4.2 Propagation mechanisms

| Mechanism | How the lesson reaches teams that didn't have the incident |
|---|---|
| **Platform defaults** | The shared library, template or platform enforces the fix for everyone |
| **CI checks and linters** | Block the hazardous pattern at build time |
| **Operational readiness review** (ORR) checklist | New and existing services must show the mitigation before launch or at review |
| **Game days and chaos experiments** | Test whether the mitigation actually works under failure |
| **A searchable COE library** | Engineers can find relevant past failures when designing |

### 4.3 Action items that never close

A familiar failure of postmortem culture: dozens of action items, a third of them still open a year later. Causes and counters:

| Cause | Counter |
|---|---|
| Too many items, all equal | Three or fewer high-priority items per COE, ranked |
| No owner, or an owner who has moved on | A named owner and a date; reassignment on team change |
| Competes with the roadmap | High-priority items treated as planned work, tracked in the same system |
| Nobody checks | A monthly review of open COE actions by engineering leadership, with the aging list visible |

---

## 5. Psychological safety in technical forums

Amy Edmondson defined team psychological safety (1999) as a shared belief that the team is safe for interpersonal risk-taking. Google's Project Aristotle research later found it to be the most important factor in team effectiveness among those it studied.

For a senior engineer, the forums that matter are **incident reviews, design reviews and on-call**. What an L7 does:
- **Goes first with their own mistakes.** When the most senior engineer in the room says "my design caused this", it becomes safe for others to say "I ran the command".
- **Protects the person closest to the failure**: in the review, in the channel, and with leadership.
- **Asks questions that invite detail**: "What did you see on the dashboard at that point?" rather than "Why didn't you check the dashboard?"
- **Changes the forum's structure**: written pre-reads so quieter people can contribute; rotating facilitators; time reserved for juniors' questions.
- **Responds well to bad news.** How you react to the first person who reports a problem decides whether the second person does.

---

## 6. Hiring Committee Scoring Rubric

| Signal | Strong Hire at L7 | Hire at L6 | Down-level to L5 | No hire |
|---|---|---|---|---|
| **Causal analysis** | Multiple causal chains, including detection, mitigation and blast radius; reaches system properties | A sound root cause beyond the trigger | Stops at the trigger | Stops at "human error" |
| **Blamelessness** | Protected the person closest to the failure; held the system's designers (often themselves) accountable | Ran a blameless review | Mentions blamelessness | Names a person as the cause |
| **Remediation level** | Action items at hierarchy levels 1–3, with evidence they work | Some engineered fixes | Monitoring and process | Training only |
| **Propagation** | The lesson became an org-wide guardrail protecting teams that never had the incident | Applied to neighboring teams | Own team only | Not propagated |
| **Patterns** | Found a recurring class across COEs and treated it as one problem | Noticed repeats | Treats each incident separately | None |
| **Follow-through** | Action items closed, with a mechanism that keeps them closing | Closed own items | Some open | Abandoned |
| **Safety** | Changed how a forum works so people report problems earlier | Supportive behavior | Neutral | Punitive |

---

## 7. Story Blueprints

### 7.1 A blameless COE after a junior engineer's mistake (composite: a migration script run against production)

**The facts (composite):** an engineer six months into the job ran a data-migration script against the production database instead of staging, deleting about 40,000 customer address records. Recovery from backups took nine hours.

#### How an L5 tells it

> "One of the junior engineers on our team accidentally ran a migration script against production and deleted a lot of customer data. We restored it from backups, which took most of the day. In the postmortem we agreed people need to be more careful with production, and we added a checklist step to double-check the environment before running scripts."

**What the committee extracts:** cause attributed to the engineer; remediation at the training/process level. **L5.**

#### How an L7 tells it

> "An engineer six months into the job ran a migration script against production instead of staging and deleted about 40,000 customer address records. Restoring them took nine hours, during which those customers couldn't check out.
>
> I ran the COE, and the first thing I did was talk to her privately, before the review, to tell her the review would be about the system and that I'd say so in the room. Then I asked her to walk me through what she saw. Her terminal looked identical for staging and production. Her credentials worked on both. The script had no dry-run mode. And our runbook said to 'run the migration', without saying where.
>
> The review asked five questions, not one: why the script could run against production, why nothing caught the mistake, why detection took twenty minutes, why restoring took nine hours, and why one script could touch every customer. The answers were system properties, every one. Production access was standing rather than requested. The tool had no guard. Backups were taken but had never been restored at that size, so nobody knew restoring would take nine hours.
>
> The action items were all engineered, not training. Production database access became just-in-time, approved per session. Migration tooling runs as a dry run unless it's given an explicit production flag plus a second engineer's approval, and it refuses any statement affecting more than a set number of rows without a further override. And we added point-in-time recovery with a quarterly restore drill, which brought a full-table restore down to under forty minutes.
>
> Because the hazard wasn't specific to us, I took the tooling changes to the platform team as a default for every service with a database. Within a quarter, all 60 teams had just-in-time access. Two other teams later reported that the row-limit guard had blocked a mistaken statement. The engineer who ran the script ran the next quarter's restore drill and presented it at the engineering all-hands."

**What the committee extracts:** protected the person first; got an accurate account; five causal chains reaching system properties; all action items at hierarchy levels 2–3; restore time measured and fixed; propagated as a platform default; evidence it protected other teams; the engineer's standing restored publicly. **Strong L7.**

### 7.2 Turning one team's COE into an org-wide guardrail (composite: certificate expiry)

#### How an L5 tells it

> "Our service had an outage because a TLS certificate expired. We renewed it, added a calendar reminder for the next renewal, and set up an alert for certificate expiry on our service."

**What the committee extracts:** a reasonable team-level fix. **L5.**

#### How an L7 tells it

> "An expired TLS certificate on an internal API took down our order-status service for 50 minutes. The team's COE was good: they renewed it, automated their renewal and added an alert. But when I read it I asked a different question: who else has certificates nobody's tracking?
>
> I spent a week building an inventory by scanning our internal endpoints and certificate stores. We had about 1,900 certificates. Roughly 400 were renewed manually, 60 expired within ninety days, and 11 had no identifiable owner at all. Two of the eleven fronted payment services.
>
> I wrote a one-page note to the infrastructure director framing it as a predictable outage class with a date attached, not as a hygiene issue. The proposal was an engineering fix at the platform level, not a reminder process. Every certificate would be issued through one internal certificate authority with automatic renewal. Any certificate expiring within 21 days without automatic renewal would page its owning team. And the service template would reject manually managed certificates for new services.
>
> The platform team built the automation, with me as the design lead, and we migrated the 400 manual certificates over a quarter, starting with the 60 closest to expiry and the eleven ownerless ones. Since then, certificate-expiry incidents across the org have gone from about four a year to zero over two years. The certificate inventory is now part of the operational readiness review."

**What the committee extracts:** read a team-level COE and asked the org-level question; quantified the hazard across the org; framed it as a predictable outage with a date; an engineered platform fix, not a process; prioritized by risk; measured outcome over two years; embedded in the readiness review. **L7 propagation.**

### 7.3 A pattern across COEs (composite: config changes as the top outage class)

#### How an L5 tells it

> "We had several outages caused by bad config changes, so I suggested we add more review for config changes on our team. We now require two approvals for config pushes."

**What the committee extracts:** a process fix (hierarchy level 4) for one team. **L5.**

#### How an L7 tells it

> "Reviewing a year of our org's COEs for the annual planning cycle, I tagged each by contributing factor. Config changes were the trigger in 38% of SEV1s and SEV2s, more than code deploys. Code deploys went through canaries and automatic rollback; config changes went to the whole fleet at once, and they were reviewed by a human, which our COEs showed didn't catch the dangerous ones.
>
> I proposed treating config changes exactly like code: staged rollout through cells, automatic health checks between stages, and automatic rollback on regression. I wrote it as a COE of COEs, with the eighteen incidents in an appendix, and the org's engineering leadership funded a small team to build it into our config service.
>
> The hard part was adoption: a few teams relied on instant global config pushes for incident mitigation. Their concern was right, so the design kept an emergency path that skips staging, which requires an incident ID and is logged for review. After the rollout, config-triggered SEV1s and SEV2s fell by about 80% over the next year. The remaining 20% were mostly caught at the first stage, with blast radius limited to one cell. COE tagging is now standard, and the quarterly theme review is run by the SRE leads."

**What the committee extracts:** found a cross-incident pattern from data; recognized that the existing process control wasn't working; an engineered, hierarchy-level-2–3 fix; preserved a legitimate need through a logged emergency path; measured outcome; handed the review mechanism to owners. **L7.**

---

## 8. Adversarial Bar-Raiser Follow-Up Chains

### Chain A · "So whose fault was it?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Wasn't it the engineer's mistake?" | Systems thinking | "Yes, but..." | "She made the last of several errors the system allowed" |
| 2 | "Was there any accountability?" | Blameless ≠ unaccountable | "No, it's blameless" | "Yes, for the owners of the tooling and access model" |
| 3 | "What did you say to her?" | Safety | Didn't | The private conversation before the review |
| 4 | "How would she describe the review?" | Empathy | Unsure | Plausibly, with evidence (she ran the next drill) |

### Chain B · "Which level are those action items?"

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Which action item matters most?" | Prioritization | Lists all | One, and why |
| 2 | "Does it rely on anyone remembering anything?" | Hierarchy | Yes | No: it's enforced by the tool |
| 3 | "How do you know it works?" | Evidence | "No recurrence" | Blocked mistakes reported by other teams |
| 4 | "Which items are still open?" | Follow-through | All closed (if untrue) | The honest status |

### Chain C · "Who else had this problem?" 🔥

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "Did other teams have the same hazard?" | Propagation | "Probably" | The inventory: 1,900 certificates, 11 ownerless |
| 2 | "How did you find out?" | Initiative | Didn't | A week of scanning |
| 3 | "Why would the director care?" | Framing | "Reliability matters" | A predictable outage class, with a date |
| 4 | "How did the fix reach teams that hadn't had the incident?" | Mechanism | "We told them" | Platform CA, template, readiness review |

### Chain D · Patterns

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "How did you notice the pattern?" | Method | "It felt like a lot" | Tagged a year of COEs |
| 2 | "Why hadn't anyone seen it?" | Insight | Unsure | Each COE was read alone |
| 3 | "Why not just add more review?" | Remediation level | "We did" | Review was the control that had been failing |
| 4 | "Who objected?" | Influence | Nobody | Teams needing instant pushes; the emergency path |

### Chain E · Psychological safety

| # | Probe | Tests | Passenger | Owner |
|---|---|---|---|---|
| 1 | "How do you know people report problems early?" | Measurement | "They seem to" | Time from first signal to report; near-miss reports |
| 2 | "What did you change about the forum?" | Structural change | Nothing | Pre-reads, facilitation, juniors' time |
| 3 | "Tell me about a time someone brought you bad news." | Behavior | Generic | A specific reaction, and its effect |
| 4 | "When did you last say 'I was wrong' in a review?" | Going first | Can't recall | A specific occasion |

---

## 9. Checklist

- [ ] Your COE story has several causal chains, including detection, mitigation and blast radius.
- [ ] Nobody in your story is "the cause"; system properties are.
- [ ] You can rank your action items on the remediation hierarchy, and the top ones are engineered.
- [ ] The lesson reached teams that never had the incident.
- [ ] One story about a pattern across many incidents.
- [ ] You can describe what you did for the person closest to the failure.
- [ ] Action items closed, with a mechanism that keeps them closing.

## 10. References

- AWS Cloud Operations blog, "Why you should develop a correction of error (COE)". <https://aws.amazon.com/blogs/mt/why-you-should-develop-a-correction-of-error-coe/>
- Google, *Site Reliability Engineering* (O'Reilly, 2016), "Postmortem Culture: Learning from Failure". <https://sre.google/sre-book/postmortem-culture/>
- Richard I. Cook, "How Complex Systems Fail" (1998). <https://how.complexsystems.fail/>
- John Allspaw, "Blameless PostMortems and a Just Culture", Etsy *Code as Craft*, 2012.
- Amy Edmondson, "Psychological Safety and Learning Behavior in Work Teams", *Administrative Science Quarterly* 44(2), 1999.
- Sidney Dekker, *The Field Guide to Understanding 'Human Error'* (3rd ed., CRC Press, 2014).
- In this KB: [05.1 Owning SEV1s](01-owning-catastrophic-sev1-outages-and-bad-architectural-bets.md) · [05.3 Feedback and mentoring](03-delivering-hard-feedback-handling-low-performers-and-mentoring-l5s.md) · Folder 06 reframes production-bug stories as COE and guardrail stories.
