# 05/03 · Business Processes: Stakeholders, Change, Skills and Cost

**Exam guide:** 4.2 (stakeholder management, change management, team assessment / skills readiness, decision-making processes, customer success management, cost optimization / resource optimization (CapEx/OpEx), business continuity). **Principles:** P9, P15.

These questions have no product to memorize. They test judgment. Google's preferred answers are **collaborative, incremental, data-driven and people-aware**.

---

## 1. Stakeholder management

| Practice | What it looks like | Wrong-answer smell |
|---|---|---|
| Identify stakeholders and their interests | Map executives, security, finance, legal/compliance, operations, developers, end users, partners (dealers, insurers) | Ignoring a stakeholder who can veto (security, compliance) |
| Clarify decision rights | **RACI** for key decisions (who's Responsible, Accountable, Consulted, Informed) | "The architect decides alone" |
| Influence with evidence | Proofs of concept, TCO models, pilots, benchmarks, reference architectures | Arguing from preference |
| Facilitate trade-off discussions | Present options with costs, risks and benefits tied to business goals; let the accountable owner choose | Presenting one option as the only way |
| Communicate continuously | Roadmaps, demos, status against KPIs | Big reveal at the end |

**Exam pattern:** "The security team is blocking the migration over data-exfiltration concerns" → engage them early. Co-design controls (VPC SC, org policies, CMEK) and demonstrate them in a pilot. Don't escalate around them or postpone security.

---

## 2. Change management

| Principle | Application |
|---|---|
| **Incremental change** | Pilot → early adopters → waves. Each wave reduces risk and builds skills (P15) |
| **Explain the why** | Tie the change to business outcomes (KnightMotives' five-year experience goal; EHR's outages) |
| **Train before you switch** | Hands-on training and sandboxes before people are expected to operate the new platform |
| **Feedback loops** | Retrospectives per wave; adjust the plan |
| **Reinforce** | Update processes, incentives and documentation so old habits don't return |
| **Technical change control** | Changes through CI/CD with automated checks and approvals, rather than manual change-advisory boards for every small change. Peer review plus automation is Google's model |

---

## 3. Team assessment and skills readiness

* **Assess** current skills against what the target architecture needs: Kubernetes, IaC, SRE, data engineering, ML.
* **Close the gaps** with:
  * training paths and certifications (Google Skills, formerly Cloud Skills Boost);
  * hands-on labs;
  * pairing with experienced engineers or a Google Cloud partner;
  * a **Cloud Center of Excellence (CCoE)** that sets standards, builds the landing zone and coaches teams.
* **Match the architecture to the team.** If the team is small or new to cloud, managed and serverless services reduce the skills burden (P5). This is a legitimate design input.
* **Hire for missing critical roles** (KnightMotives: "attracting top-tier talent") while upskilling the existing staff.

**Exam pattern:** "Operations staff only know VMs; leadership wants containers in 6 months" → a training plan plus a pilot on **GKE Autopilot or Cloud Run** (less to learn), with partner support. Don't pick an option that has untrained staff run self-managed Kubernetes in production immediately.

---

## 4. Decision-making processes

| Tool | Purpose |
|---|---|
| **Architecture Decision Records (ADRs)** | Record context, options, decision and consequences. Makes future reviews and audits easy |
| **Proof of concept / pilot** | Validate assumptions (performance, cost, compatibility) before committing |
| **Data-driven evaluation** | Use Migration Center assessments, load tests, cost estimates (Pricing Calculator), and Recommender data |
| **Architecture review** | Lightweight review against the Well-Architected Framework, not a bottleneck |
| **Reversible vs irreversible decisions** | Move fast on reversible ones (two-way doors); analyze carefully irreversible ones (data residency, locking a retention policy, multi-year commitments) |

---

## 5. Customer success management

* Define **success criteria** with the business up front: KPIs, SLOs, adoption targets.
* **Measure and review** regularly (dashboards in Looker or Data Studio; SLO reports).
* Collect user feedback (surveys, product analytics) and feed it into the backlog.
* Use Google's **customer success** resources where available (Technical Account Managers in Premium Support, partner success programs).
* For the case studies: Cymbal measures conversion, call deflection and return rates; KnightMotives measures dealer satisfaction and time on lot; EHR measures provider onboarding time and availability.

---

## 6. Cost and resource optimization (CapEx and OpEx)

### CapEx vs OpEx

| | CapEx (on-premises) | OpEx (cloud) |
|---|---|---|
| Spend | Up-front hardware and data-center investment, depreciated | Pay as you go; monthly operating expense |
| Capacity | Bought for peak, often idle | Elastic; pay for use |
| Risk | Over- or under-provisioning; refresh cycles | Cost overruns without governance |
| Finance impact | Budget cycles, asset management | Requires FinOps discipline, forecasting, commitments |

Moving to cloud shifts spending to OpEx ("a shift in financial priorities", KnightMotives). Commitments (CUDs) reintroduce some predictability in exchange for discounts.

### The FinOps loop: Inform → Optimize → Operate

| Phase | Google Cloud tools and practices |
|---|---|
| **Inform** (visibility) | **Billing reports**, **Cloud Billing export to BigQuery** (detailed usage and cost), **labels** and tags for allocation, **FinOps hub**, Looker or Data Studio cost dashboards, showback/chargeback by team |
| **Optimize** (rates and usage) | **Usage:** rightsizing (**Recommender**: idle VMs, idle disks and IPs, VM rightsizing, unattended projects), autoscaling, schedules for non-prod (stop at night), storage lifecycle, BigQuery partitioning. **Rates:** **CUDs** (resource-based and spend-based / flexible), **sustained use discounts** (automatic), **Spot**, **Standard network tier** where acceptable |
| **Operate** (governance) | **Budgets and alerts** (with Pub/Sub notifications for automated actions), **quotas** to cap usage, org policies to restrict expensive resources, BigQuery **custom quotas**, regular cost reviews, policies for labeling |

### Commitment choice

| Workload | Commitment |
|---|---|
| Steady VMs of a known family in one region for 3 years | **Resource-based CUD** (3-year for the larger discount) |
| Steady spend that may shift across machine families, regions or services | **Spend-based / flexible CUD** (Compute Flex CUDs now cover more services and VM families, and are billed as discounted prices) |
| Cloud SQL, AlloyDB, Spanner, Memorystore, GKE Autopilot, Cloud Run steady usage | Service-specific spend-based CUDs (where offered) |
| Unpredictable or short-term usage | No commitment; autoscaling and on-demand |
| Fault-tolerant batch | **Spot** (no commitment) |

### Budget automation pattern

```text
Budget threshold (e.g., 90% of monthly) ──▶ Pub/Sub notification ──▶ Cloud Run function
     ──▶ notify Slack + (for sandbox projects only) disable billing or stop resources
```

Never automate disabling billing on **production** projects. That deletes or stops resources and causes an outage.

---

## 7. Business continuity (process side)

* **People:** cross-train staff, document runbooks, keep escalation contacts current, cover on-call.
* **Process:** BCP exercises (tabletop plus technical drills), communication plans for customers and regulators, and a supplier-continuity review (including your cloud support plan).
* **Technology:** the DR patterns from [02/02](../02-Designing-and-Planning/02-technical-requirements-ha-scalability-dr.md), tested per [05/02](02-troubleshooting-rca-and-dr-processes.md).

---

## 8. Worked scenarios

**A. "Finance complains that cloud costs are unpredictable and can't be attributed to departments."**
Labels (enforced via IaC and policy), billing export to BigQuery, per-department dashboards, budgets with alerts; then CUDs for the stable baseline. Inform before optimizing.

**B. "Leadership wants to cut cloud spend 20% quickly without hurting production."**
Recommender actions (delete idle resources, rightsize), schedules for non-production, storage lifecycle and Autoclass, Spot for batch, CUDs for the steady state. Avoid blanket downsizing of production.

**C. "A new platform is technically ready, but adoption by development teams is low."**
Change management: training, documentation, golden-path templates (a service catalog), champions in each team, feedback loops, and measured adoption KPIs. Not a mandate with no support.

**D. "Two teams disagree about GKE vs Cloud Run for a new service."**
A decision process: list the requirements (NFRs), build a small PoC, evaluate against criteria (ops burden, features, cost), record an ADR, and let the accountable owner decide.

---

## References

* FinOps hub: <https://cloud.google.com/billing/docs/how-to/finops-hub>
* Cloud Billing export to BigQuery: <https://cloud.google.com/billing/docs/how-to/export-data-bigquery>
* Committed use discounts: <https://cloud.google.com/docs/cuds>
* Budgets and alerts: <https://cloud.google.com/billing/docs/how-to/budgets>
* Recommender: <https://cloud.google.com/recommender/docs/overview>
* Well-Architected Framework, cost optimization: <https://cloud.google.com/architecture/framework/cost-optimization>
