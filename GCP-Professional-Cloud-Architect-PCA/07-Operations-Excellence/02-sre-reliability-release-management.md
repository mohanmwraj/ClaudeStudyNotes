# 07/02 · Operational Excellence, SRE and Release Management

**Exam guide:** 6.1 (operational excellence pillar of the Well-Architected Framework), 6.3 (deployment and release management), 6.4 (supporting deployed solutions), 6.5 (evaluating quality control measures), 6.6 (reliability in production: chaos engineering, penetration testing, load testing). **Principles:** P2, P12, P13.

---

## 1. The operational excellence pillar

The Well-Architected Framework's operational excellence pillar is organized around a few core principles. Learn the intent of each and its Google Cloud mechanisms:

| Principle (paraphrased) | What it means | Mechanisms |
|---|---|---|
| **Ensure operational readiness and performance** | Define SLOs, plan capacity, run readiness reviews before launch, monitor everything | SLOs in Cloud Monitoring, load tests, quotas and reservations, launch checklists |
| **Manage incidents and problems** | Clear incident process, fast mitigation, blameless postmortems, problem management for recurring issues | On-call, runbooks, Personalized Service Health, postmortems, Error Reporting |
| **Manage and optimize cloud resources** | Rightsize, automate scaling, control cost, keep inventory | Recommender, autoscaling, labels, FinOps hub, Asset Inventory |
| **Automate and manage change** | IaC, CI/CD, progressive delivery, automated rollback, policy as code | Terraform, Cloud Build, Cloud Deploy, Config Sync, Binary Authorization |
| **Continuously improve and innovate** | Learn from incidents and metrics, reduce toil, adopt new capabilities | DORA metrics, error-budget reviews, toil tracking, Gemini Cloud Assist |

Framework pillar: <https://cloud.google.com/architecture/framework/operational-excellence>

---

## 2. SRE fundamentals

| Concept | Definition | Exam use |
|---|---|---|
| **SLI** | A quantitative measure of service level: availability (good/valid requests), latency (percent under X ms), freshness, correctness | Choose user-centric SLIs (measured at the load balancer or client), not CPU |
| **SLO** | Target for an SLI over a window (99.9% of requests succeed over 28 days) | Internal objective; tighter than the SLA |
| **SLA** | Contract with consequences (credits) | External. Breaching the SLO should warn you before the SLA is at risk |
| **Error budget** | 1 − SLO (0.1% → about 43 minutes a month) | Spend on releases and experiments. When exhausted, **freeze risky releases and prioritize reliability work** (error budget policy) |
| **Toil** | Manual, repetitive, automatable operational work that scales with load | Automate it; SRE teams cap toil (Google targets under 50% of SRE time) |
| **Blameless postmortems** | Focus on systems, not individuals | Culture questions |

**Choosing an SLO:** start from what users need and what the business will pay for. 100% is never the right target. Each nine multiplies cost (P2). Altostrat's "reliability and cost are top priorities" means explicit SLOs that balance both.

---

## 3. Deployment and release management

### Strategies compared

| Strategy | How | Rollback | Risk / cost | Google Cloud implementation |
|---|---|---|---|---|
| **Recreate** | Stop the old version, start the new | Redeploy old | Downtime | Rarely acceptable for production |
| **Rolling** | Replace instances gradually | Roll forward or back gradually | Mixed versions during rollout; no extra environment | MIG rolling updates (`maxSurge` / `maxUnavailable`); GKE Deployments |
| **Blue/green** | Full new environment; switch traffic at once | **Instant** switch back | Double capacity during the switch | Two MIGs or Deployments behind an LB; Cloud Run revisions (100% shift); Cloud Deploy |
| **Canary** | Small percentage of traffic to the new version; analyze; increase | Shift traffic back | Low blast radius; needs good metrics | **Cloud Deploy canary** (GKE, Cloud Run), Cloud Run traffic splitting, MIG canary, LB weighted backends, Cloud Service Mesh |
| **A/B testing** | Route segments (headers, cookies) to variants to measure business metrics | Route back | Product experiment, not just safety | LB header routing, Cloud Service Mesh, feature flags |
| **Shadow (dark launch)** | Mirror production traffic to the new version without serving its responses | No user impact | Extra cost; careful with side effects | Traffic mirroring (Cloud Service Mesh / LB request mirroring) |
| **Feature flags** | Deploy code dark; enable per user or segment | Toggle off | Decouples deploy from release | Firestore/Remote Config/flag services |

### Practices

* **Build once, deploy the same artifact everywhere** (by digest).
* **Automated verification** at each stage (SLO metrics, error rate, synthetic tests). **Automatic rollback** on failure.
* **Small, frequent releases** (lower change failure rate, faster recovery).
* **Database changes use expand/contract**: add new columns or tables first (compatible with old and new code), migrate data, switch code, then remove old structures later. This avoids lock-step deploys.
* **Release approvals** for production in regulated environments (Cloud Deploy approvals; separation of duties).
* **Freeze windows** around peak business events, plus error-budget-driven freezes.

---

## 4. Supporting deployed solutions

Covered in depth in [05/02 §5](../05-Technical-and-Business-Processes/02-troubleshooting-rca-and-dr-processes.md#5-supporting-deployed-solutions-exam-guide-64):

* support plans and good support cases;
* runbooks linked from alerts;
* on-call rotations and escalation;
* operational readiness reviews before go-live.

---

## 5. Evaluating quality control measures

| Control | Measures | Healthy sign |
|---|---|---|
| Code review | Review coverage, time to review | Every production change reviewed |
| Automated tests | Coverage of critical paths, flakiness rate | Fast, reliable test suite gating merges |
| Static analysis and security scanning | Findings trend, time to fix critical CVEs | Critical issues block release (Binary Authorization gate) |
| Canary analysis | Canary failure rate, false positives | Bad releases stopped at a small percentage |
| SLO compliance | Error budget remaining | Budget policy enforced |
| DORA metrics | Deployment frequency, lead time, change failure rate, time to restore | Improving speed **and** stability |
| Postmortem follow-through | Action items closed on time | Recurring incidents decline |
| Policy compliance | SCC findings, org-policy violations, Policy Controller audits | Trending down; guardrails preventive |

**Exam pattern:** "How do you know your release process is improving?" → DORA metrics plus SLO/error-budget trends. Not "number of tickets closed" or "lines of code".

---

## 6. Ensuring reliability in production

### Chaos engineering

1. Define **steady state** (SLIs).
2. Hypothesize that the system tolerates a fault.
3. Inject the fault with a **minimal blast radius**: terminate instances, drain a zone, add latency, fail a dependency, revoke a credential.
4. Observe.
5. Fix weaknesses.
6. Automate and repeat.

Start in pre-production; graduate to controlled production experiments.

**Tools:**

* Cloud Service Mesh **fault injection** (delays, aborts);
* deleting MIG instances or pods (autohealing tests);
* draining a zone via the LB or cordoning nodes;
* open-source tools (Chaos Toolkit, LitmusChaos, Chaos Mesh on GKE);
* DR **game days** (Google's internal practice is called DiRT).

### Penetration testing

* You **don't need to notify Google** before pen-testing your own projects. Stay within the Acceptable Use Policy and Terms of Service, and test only resources you own.
* Combine automated scanning (Web Security Scanner, SCC) with periodic expert pen tests, and fix findings through the normal pipeline.

### Load testing

* Distributed load generators (Locust/JMeter on GKE) against production-like environments.
* Verify autoscaling, quotas, connection limits and caches; test failure modes under load.
* Run before major events; request quota increases and **reservations** for capacity guarantees.

### Capacity planning

* Forecast from business drivers and historical metrics; keep headroom (N+1 or N+2 zones).
* Reservations for critical capacity (GPUs, peak events); load-test to validate.

---

## 7. Worked scenarios

**A. "A team deploys weekly, and a third of releases cause incidents requiring hotfixes."**
High change failure rate. Add automated tests and canary releases with automated verification (Cloud Deploy), smaller batches, and an error-budget policy. Measure DORA metrics.

**B. "The service has used its entire monthly error budget by day 10."**
Per the error-budget policy: freeze feature releases (except reliability fixes), prioritize reliability work from postmortems, and review whether the SLO is realistic.

**C. "Leadership wants evidence that the system survives a zone failure."**
A game day: drain one zone (or fail instances in a regional MIG/GKE) during a controlled window while watching SLIs. Verify autohealing and capacity headroom, and document the results.

**D. "Roll out a new recommendation model to 5% of users and compare engagement."**
Canary or A/B: traffic split between model versions (Agent Platform endpoint traffic split, or application-level routing), measuring business KPIs and SLOs before increasing the share.

---

## References

* Operational excellence pillar: <https://cloud.google.com/architecture/framework/operational-excellence>
* SRE book (SLOs): <https://sre.google/sre-book/service-level-objectives/>
* Error budget policy (SRE workbook): <https://sre.google/workbook/error-budget-policy/>
* Application deployment and testing strategies: <https://cloud.google.com/architecture/application-deployment-and-testing-strategies>
* Cloud Deploy canary deployments: <https://cloud.google.com/deploy/docs/deployment-strategies/canary>
* Penetration testing on Google Cloud (Cloud Security FAQ): <https://support.google.com/cloud/answer/6262505>
