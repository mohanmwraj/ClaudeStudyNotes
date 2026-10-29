# Google Cloud Professional Cloud Architect (PCA): Source-of-Truth Kit

A single, self-contained preparation module for the **Google Cloud Certified – Professional Cloud Architect** exam. It's built around the current **v6.1 exam guide** (live since 30 October 2025, re-issued with 2026 product names). The kit teaches **first-principles reasoning**, so you can derive answers to use-case questions instead of memorizing them. It contains **310 original exam-style questions**, including three timed 50-question mock papers that mirror the official weighting and case-study share.

Exam facts, case studies and product names were verified against Google's own pages on **2026-10-29**.

---

## The exam in one table

| Item | Value |
|---|---|
| Format | 2 hours · 50–60 multiple choice / multiple select · USD 200 · English or Japanese · online or test center |
| Sections (weights) | 1 Designing & planning **25%** · 2 Managing & provisioning **17.5%** · 3 Security & compliance **17.5%** · 4 Technical & business processes **15%** · 5 Managing implementation **12.5%** · 6 Solution & operations excellence **12.5%** |
| Case studies | **2 per exam** from Altostrat Media, Cymbal Retail, EHR Healthcare and KnightMotives Automotive. Case-study questions are **20–30%** of the exam |
| Anchor | The Google Cloud **Well-Architected Framework** (six pillars) |
| Validity | 2 years (the renewal exam is 1 hour, 25 questions, generative-AI case study) |

Details: [00/01-exam-blueprint-decoded.md](00-Exam-Strategy-and-First-Principles/01-exam-blueprint-decoded.md).

---

## How to use this kit

1. Read [00-Exam-Strategy-and-First-Principles](00-Exam-Strategy-and-First-Principles/) **first**, especially the 16 principles (P1–P16). Every explanation in the kit refers back to them.
2. Follow the **six-week plan** in [00/04-study-plan.md](00-Exam-Strategy-and-First-Principles/04-study-plan.md). The learning loop: read actively, name the principle, take the drill closed-book, read every explanation, log your misses.
3. Study the **four case studies** early and revisit them often ([01-Case-Studies](01-Case-Studies/)). They're the highest-yield material in the kit.
4. Take the three **timed mocks** in the final week. Aim for at least 40/50 on two of them.
5. Do the **final review** in [09-Final-Review](09-Final-Review/) during the last 48 hours.

---

## Map of the kit

### [00 · Exam Strategy and First Principles](00-Exam-Strategy-and-First-Principles/)

| File | Content |
|---|---|
| [01-exam-blueprint-decoded.md](00-Exam-Strategy-and-First-Principles/01-exam-blueprint-decoded.md) | Logistics, the six sections objective by objective (and what each really tests), what changed from older material, question anatomy |
| [02-first-principles-mental-models.md](00-Exam-Strategy-and-First-Principles/02-first-principles-mental-models.md) | **P1–P16**: geography and failure domains, availability math, state, consistency, managed services, identity, hierarchy, async, cost shape, data gravity, key custody, everything-as-code, observability, private networking, migration risk, AI systems |
| [03-decoding-questions-and-elimination.md](00-Exam-Strategy-and-First-Principles/03-decoding-questions-and-elimination.md) | Phrase dictionary, Google's built-in preferences, elimination rules, distractor archetypes, case-study method, worked examples |
| [04-study-plan.md](00-Exam-Strategy-and-First-Principles/04-study-plan.md) | Six-week plan, readiness thresholds |
| [05-product-name-rosetta.md](00-Exam-Strategy-and-First-Principles/05-product-name-rosetta.md) | 2023–2026 renames: Vertex AI → Gemini Enterprise Agent Platform, Dataproc → Managed Service for Apache Spark, Composer → Managed Service for Apache Airflow, Dataplex → Knowledge Catalog, and more |

### [01 · Case Studies](01-Case-Studies/)

Method plus a full breakdown of each company: standing constraints, requirement-by-requirement decomposition, current-to-target map, reference architecture, phased plan and likely question themes.

| [Method](01-Case-Studies/01-case-study-method.md) | [EHR Healthcare](01-Case-Studies/02-ehr-healthcare.md) | [Cymbal Retail](01-Case-Studies/03-cymbal-retail.md) | [Altostrat Media](01-Case-Studies/04-altostrat-media.md) | [KnightMotives Automotive](01-Case-Studies/05-knightmotives-automotive.md) |
|---|---|---|---|---|

### [02 · Section 1: Designing and Planning (25%)](02-Designing-and-Planning/)

[Business requirements](02-Designing-and-Planning/01-business-requirements-to-architecture.md) · [HA, scalability, DR, Gemini Cloud Assist](02-Designing-and-Planning/02-technical-requirements-ha-scalability-dr.md) · [Compute selection](02-Designing-and-Planning/03-compute-selection.md) · [Storage and database selection](02-Designing-and-Planning/04-storage-and-database-selection.md) · [Data processing](02-Designing-and-Planning/05-data-processing-selection.md) · [AI/ML selection](02-Designing-and-Planning/06-ai-ml-solution-selection.md) · [Migration planning and future improvements](02-Designing-and-Planning/07-migration-planning.md)

### [03 · Section 2: Managing and Provisioning (17.5%)](03-Managing-and-Provisioning/)

[VPC and hybrid networking](03-Managing-and-Provisioning/01-vpc-design-and-hybrid-networking.md) · [Load balancing and edge](03-Managing-and-Provisioning/02-load-balancing-and-edge.md) · [Storage configuration and lifecycle](03-Managing-and-Provisioning/03-storage-configuration-and-lifecycle.md) · [Compute, GKE, serverless, VMware Engine](03-Managing-and-Provisioning/04-compute-provisioning-gke-serverless.md) · [Agent Platform ML workflows and prebuilt AI](03-Managing-and-Provisioning/05-agent-platform-ml-workflows.md)

### [04 · Section 3: Security and Compliance (17.5%)](04-Security-and-Compliance/)

[IAM and resource hierarchy](04-Security-and-Compliance/01-iam-and-resource-hierarchy.md) · [Keys, secrets, Sensitive Data Protection](04-Security-and-Compliance/02-data-protection-kms-secrets-dlp.md) · [Perimeters and secure remote access](04-Security-and-Compliance/03-perimeter-network-security-and-remote-access.md) · [Supply chain and AI security](04-Security-and-Compliance/04-supply-chain-and-ai-security.md) · [Compliance and audit](04-Security-and-Compliance/05-compliance-and-audit.md)

### [05 · Section 4: Technical and Business Processes (15%)](05-Technical-and-Business-Processes/)

[SDLC, CI/CD and testing](05-Technical-and-Business-Processes/01-sdlc-cicd-testing.md) · [Troubleshooting, RCA and DR processes](05-Technical-and-Business-Processes/02-troubleshooting-rca-and-dr-processes.md) · [Stakeholders, change, skills and cost](05-Technical-and-Business-Processes/03-business-processes-stakeholders-cost.md)

### [06 · Section 5: Managing Implementation (12.5%)](06-Managing-Implementation/)

[Advising teams: deployment, Apigee, testing, migration tools](06-Managing-Implementation/01-advising-teams-deployment-apis.md) · [Programmatic access, emulators and IaC](06-Managing-Implementation/02-programmatic-interaction-iac.md)

### [07 · Section 6: Operations Excellence (12.5%)](07-Operations-Excellence/)

[Observability: monitoring, logging, profiling, alerting](07-Operations-Excellence/01-observability-monitoring-logging.md) · [Operational excellence, SRE and release management](07-Operations-Excellence/02-sre-reliability-release-management.md)

### [08 · Exam Questions and Sample Papers](08-Exam-Questions-and-Sample-Papers/): everything to practice with

* **Six domain drills:** 20 questions each, 120 in total.
* **Case-study drill:** 40 questions, 10 per company.
* **Three timed mock papers:** 50 questions each, with answers and full explanations in separate files.
* **[Trap catalogue](08-Exam-Questions-and-Sample-Papers/11-trap-catalogue.md):** 60 traps.

Every question is original. Every option is explained and tied to a principle and an official reference.

### [09 · Final Review](09-Final-Review/)

[Numbers and limits](09-Final-Review/01-numbers-and-limits.md) · [All decision trees on one page](09-Final-Review/02-decision-trees-one-page.md) · [The last 48 hours](09-Final-Review/03-last-48-hours.md)

---

## Quality gates (run 2026-10-29)

* **Question validator** (all 310 questions). It checks:
  * option counts per question type;
  * that each answer key agrees with the correct/wrong labels;
  * that every option is explained;
  * a principle reference and an official URL on every question;
  * that task IDs exist in the v6.1 guide;
  * mock size, section mix and case-study share (12/50 per mock, from exactly two case studies);
  * answer-letter balance and multiple-select share;
  * near-duplicate stems across the whole bank.
* **Link check:** every relative link and anchor, and every external URL.
* **JSON code blocks** parse.

---

## Provenance and limits

* **Sources:** Google's certification page, the current and v6.1 exam guides, the four official case-study PDFs, Google Cloud documentation and release notes. Each notes file ends with its references.
* **Original questions:** none are copied from Google's [official sample questions](https://docs.google.com/forms/d/e/1FAIpQLSf54f7FbtSJcXUY6-DUHfBG31jZ3pujgb8-a5io_9biJsNpqg/viewform) or from any question dump. Take the official sample once, at the end, as a calibration.
* **Change:** Google renames and updates products often. If a fact here conflicts with the live exam guide on the day you sit the exam, the exam guide wins. Check the certification page for announcements before booking.
* **Not affiliated:** this kit isn't affiliated with or endorsed by Google.
