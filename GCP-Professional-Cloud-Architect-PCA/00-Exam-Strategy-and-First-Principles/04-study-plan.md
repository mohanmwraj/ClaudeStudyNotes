# 04 · Study Plan

This kit is designed to be the **only** resource you need. The plan below assumes you already work as an engineer and can give about **90 minutes on weekdays and 3 hours on weekend days**. That's roughly six weeks. If you have more time, compress it; if you're new to Google Cloud, stretch Weeks 2–3 to two weeks each and set up the free tier to click through each service once.

---

## The learning loop (use it for every folder)

1. **Read the notes file actively.** For each decision table, cover the right-hand column and predict it before reading.
2. **Say the principle aloud.** For every service choice, name the principle (P1–P16) that justifies it. If you can't, re-read [02-first-principles-mental-models.md](02-first-principles-mental-models.md) for that principle.
3. **Do the matching drill** in [08-Exam-Questions-and-Sample-Papers](../08-Exam-Questions-and-Sample-Papers/) **without notes**. Write answers down first, then open the explanations.
4. **Read every explanation, including those for questions you got right.** You may have been right for the wrong reason.
5. **Log your misses** in a three-column file: *question · the constraint I missed · the principle*. Re-read the log every Sunday.

---

## Week-by-week

| Week | Focus | Read | Practice | Exit criterion |
|---|---|---|---|---|
| **1** | Foundations and the exam's mind | All of [00](./) (this folder); [01-Case-Studies](../01-Case-Studies/) method file and all four case studies (first read) | Recite each case's top three constraints from memory | You can explain P1–P16 in one sentence each |
| **2** | Section 1, part A: requirements, HA/DR, compute, storage | [02/01](../02-Designing-and-Planning/01-business-requirements-to-architecture.md)–[02/04](../02-Designing-and-Planning/04-storage-and-database-selection.md) | Drill 1, Q1–10 | You can pick a database and a compute platform from a three-line scenario in under a minute |
| **3** | Section 1, part B: data, AI/ML, migration | [02/05](../02-Designing-and-Planning/05-data-processing-selection.md)–[02/07](../02-Designing-and-Planning/07-migration-planning.md) | Drill 1, Q11–20 | You can draw the batch and streaming reference pipelines and the migration journey from memory |
| **4** | Section 2: networking, storage, compute, Agent Platform | All of [03](../03-Managing-and-Provisioning/) | Drill 2 | You can size hybrid connectivity for any bandwidth and SLA, and name the three Interconnect topologies |
| **5** | Sections 3 and 4: security, compliance, processes | All of [04](../04-Security-and-Compliance/) and [05](../05-Technical-and-Business-Processes/) | Drills 3 and 4 | You can say which control stops which threat (IAM, deny, org policy, VPC SC, firewall, Cloud Armor, IAP) |
| **6** | Sections 5 and 6, case drills, mocks | All of [06](../06-Managing-Implementation/) and [07](../07-Operations-Excellence/); case studies (second read) | Drills 5 and 6; case-study drill; **Mock 1** (timed) | Mock 1 ≥ 75% |
| **Final days** | Mocks and review | [09-Final-Review](../09-Final-Review/); trap catalogue | **Mock 2**, then **Mock 3**, both timed, on separate days; review all misses | Both ≥ 80%, then book or sit the exam |

---

## Readiness thresholds

| Signal | Ready | Not yet |
|---|---|---|
| Domain drills | ≥ 80% in every domain | Any domain < 70%: re-read that folder |
| Case-study drill | ≥ 80% | < 75%: re-read the case breakdowns |
| Timed mock (50 questions, 120 minutes) | ≥ 40/50 on two different mocks | < 36: two more weeks of review |
| Official sample questions (once, at the end) | Comfortable; most answers derivable from principles | Many surprises: check the trap catalogue and the rename table |

Google doesn't publish a passing score, so these thresholds are deliberately conservative.

---

## The last 48 hours

* Read [09-Final-Review/03-last-48-hours.md](../09-Final-Review/03-last-48-hours.md) and the numbers sheet.
* Re-read the four case-study breakdowns, especially the "standing constraints" boxes.
* Skim [08/11-trap-catalogue.md](../08-Exam-Questions-and-Sample-Papers/11-trap-catalogue.md).
* Don't take a new mock the night before. Sleep matters more than one more set of questions.
