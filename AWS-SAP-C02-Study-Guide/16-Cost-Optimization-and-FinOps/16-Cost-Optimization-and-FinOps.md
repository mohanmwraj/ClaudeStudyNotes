# Chapter 16 — Cost Optimization, Cost Visibility & FinOps
> **Exam mapping:** D1 Task 1.5 (cost optimization & visibility strategies), D2 Task 2.6 (cost optimization strategy for new solutions), D3 Task 3.5 (cost optimization opportunities in existing solutions) — and cost appears as a *constraint* ("most cost-effective", "minimize cost", "reduce spend without…") in roughly a quarter of all questions | **Weight signal:** High | **Study time:** ~7 h
> [← Previous](../15-Monitoring-Operations-and-Continuous-Improvement/15-Monitoring-Operations-and-Continuous-Improvement.md) · [Index](../00-README-Start-Here.md) · [Next →](../17-Practice-Papers/README.md)

> **Pricing disclaimer.** All dollar figures in this chapter are **US East (N. Virginia) list prices used for illustration** (checked October 2026). Prices change and vary by Region. The exam never asks you to recall a price; it asks you to recognise *which lever is cheaper*. Learn the **ratios and the mechanisms**, not the cents.

---

## 1. What the exam really tests here

SAP-C02 rarely asks "what does Cost Explorer do?". It asks you to pick the **cheapest architecture that still satisfies every other constraint** (RTO/RPO, compliance, operational overhead, performance) and to design **organisation-wide cost governance**. Expect these decision types:

| Skill | Typical scenario | What you must decide |
|---|---|---|
| **Commitment strategy** | 300 accounts, steady EC2 + Fargate + Lambda baseline, migrating to Graviton next year | Compute SP vs EC2 Instance SP vs Convertible RI vs Standard RI; term; payment option; who buys (central account) and sharing settings |
| **Capacity vs discount** | Must guarantee capacity in one AZ for a DR event or a launch day | On-Demand Capacity Reservation (+ Savings Plan for the discount) vs zonal RI |
| **Interruptible compute** | Batch/CI/rendering/stateless web tier | Spot with diversified instance types, price-capacity-optimized, Capacity Rebalancing, checkpointing; Fargate Spot |
| **Cost visibility** | CFO wants per-business-unit, per-application cost with shared costs split | Account structure first, then cost allocation tags + Cost Categories (split charges) + CUR 2.0/Athena/QuickSight dashboards |
| **Chargeback with custom rates** | Reseller or holding company bills subsidiaries with markup/discount | AWS Billing Conductor (pro forma) — not Cost Categories |
| **Guardrails** | Sandbox accounts must stop spending at a threshold automatically | AWS Budgets **actions** (apply SCP/IAM policy, stop EC2/RDS) + Cost Anomaly Detection |
| **Architecture re-design for cost** | NAT gateway bill is huge; inter-AZ traffic exploding; Aurora I/O bill exceeds compute | Gateway endpoints; AZ-affinity; Aurora I/O-Optimized |
| **Data transfer** | Global downloads, hybrid egress, multi-Region replication | CloudFront, Direct Connect, VPC peering vs TGW, replicate only what's needed |
| **Storage & DB economics** | Petabytes of logs/objects; unpredictable DynamoDB traffic | S3 lifecycle/Intelligent-Tiering, gp3, Logs IA class, DynamoDB on-demand vs provisioned break-even |
| **Licensing** | Windows/SQL Server/Oracle migration | BYOL on Dedicated Hosts, License Manager, SQL Server edition downgrade, Optimize CPUs, move to open-source engines |

**The meta-skill:** read the stem for **the binding constraint**. "Cost-effective" is almost never the only adjective. If the question says "with the LEAST operational overhead *and* cost-effective", the managed/serverless answer beats a hand-rolled cheaper one. If it says "must not be interrupted", Spot is out no matter how cheap.

---

## 2. Core concepts & services — deep dive

### 2.1 The anchor: Well-Architected Cost Optimization pillar

AWS defines a cost-optimized workload as one that **fully utilizes all resources, achieves an outcome at the lowest possible price point, and meets functional requirements**. The pillar has **five best-practice areas**:

| Area | What it means in practice | Services / mechanisms |
|---|---|---|
| **1. Practice Cloud Financial Management (CFM)** | A FinOps function, cost-aware culture, partnership between finance and technology, forecasting, budgets | Budgets, Cost Explorer forecasts, CUR 2.0, Cloud Intelligence Dashboards, Billing Conductor |
| **2. Expenditure and usage awareness** | Governance (account structure, policies), monitoring cost & usage, decommissioning | Organizations, SCPs, tags, Cost Categories, Cost Anomaly Detection, Config |
| **3. Cost-effective resources** | Right service, right size, right pricing model, data-transfer-aware design | Compute Optimizer, Savings Plans/RIs/Spot, Graviton, managed services |
| **4. Manage demand and supply resources** | Match supply to demand: throttling, buffering, auto scaling, scheduling | Auto Scaling, SQS buffers, API throttling, Instance Scheduler, serverless |
| **5. Optimize over time** | Review regularly; adopt new services/features (gp3, Graviton, I/O-Optimized) | Cost Optimization Hub, Trusted Advisor, WA Tool reviews |

**Design principles** of the pillar: *implement Cloud Financial Management; adopt a consumption model; measure overall efficiency; stop spending money on undifferentiated heavy lifting; analyze and attribute expenditure.*

**FinOps lifecycle** (industry framework used by AWS CFM guidance): **Inform** (visibility & allocation) → **Optimize** (rates and usage) → **Operate** (governance, automation, continuous improvement). A useful mental split for exam answers:

- **Rate optimization** — pay less per unit: Savings Plans, RIs, Spot, private pricing, volume tiers via consolidated billing.
- **Usage optimization** — use fewer units: rightsizing, scheduling, auto scaling, deleting idle resources, storage tiering, architecture changes.
- **Do usage optimization *before* buying multi-year commitments.** Otherwise you commit to waste.

---

### 2.2 Purchasing options — deep dive

#### 2.2.1 On-Demand

- Billed per second (60-second minimum) for Linux, Windows and most other operating systems; a few commercial OS/Marketplace AMIs still bill per hour. No commitment.
- Right for: spiky/unpredictable workloads, short-lived projects, workloads you haven't rightsized yet, and the **portion above your committed baseline**.
- On-Demand is the "price of flexibility". Everything else is a discount for giving up flexibility (commitment), reliability (Spot), or both.

#### 2.2.2 Savings Plans (SP)

A Savings Plan is a **commitment to a consistent amount of spend in $/hour** (measured after discount) for **1 or 3 years**. Any usage beyond the commitment is billed On-Demand. Each hour's commitment is use-it-or-lose-it — **unused commitment does not roll over**.

**Four plan types (verified from the Savings Plans User Guide):**

| Plan | Max discount vs On-Demand | Applies to | Flexibility | Term / payment |
|---|---|---|---|---|
| **Compute Savings Plans** | **up to 66%** | EC2 (any family, size, **Region**, OS, tenancy incl. Dedicated Host), **AWS Fargate (ECS & EKS)**, **AWS Lambda** | Highest — move c5→m7g, us-east-1→eu-west-2, EC2→Fargate, anytime | 1 or 3 yr; No / Partial / All Upfront |
| **EC2 Instance Savings Plans** | **up to 72%** | EC2 only, **one instance family in one Region** (e.g., m5 in us-east-1) | Any size, OS, tenancy, AZ *within* that family/Region | 1 or 3 yr; No / Partial / All Upfront |
| **Database Savings Plans** (launched late 2025) | **up to 35%** (highest on serverless; lower on provisioned — e.g., up to 18% on DynamoDB on-demand throughput) | Aurora, RDS, DynamoDB, ElastiCache (Valkey), DocumentDB, Neptune, Keyspaces, Timestream (InfluxDB), DMS, OpenSearch Service — **latest instance generations (Gen 7+) and serverless usage** | Across engine, family, size, AZ, **Region**; e.g., RDS for Oracle → Aurora PostgreSQL, or RDS → DynamoDB keeps the discount | **1 yr only, No Upfront** |
| **SageMaker AI Savings Plans** | **up to 64%** | SageMaker AI instance usage (Notebook, Training, Inference, etc.) | Any family, size, Region, component | 1 or 3 yr; No / Partial / All Upfront |

Key mechanics:

- **Application order:** EC2 **Reserved Instances apply first**, then Savings Plans. Among SPs, **EC2 Instance SPs apply before Compute SPs** (because Compute SPs are broader). Within a plan, the commitment is applied to the usage with the **highest savings percentage first**.
- **Consolidated billing:** an SP applies first to the **owner account's** usage, then (if sharing is enabled) to other accounts in the organization.
- **Payment options:** All Upfront > Partial Upfront (≥ 50% upfront) > No Upfront in discount depth. 3-year > 1-year. The deepest discount is **3-yr All Upfront EC2 Instance SP**.
- **What SPs do NOT do:** they **don't reserve capacity** (pair with On-Demand Capacity Reservations), they don't discount the **$2/hour per-Region Dedicated Instance fee**, they don't cover the **EKS control-plane charge** (but do cover EKS worker EC2 and Fargate), they don't cover EBS, data transfer, or Spot usage.
- **Returns:** a plan with hourly commitment **≤ $100** can be returned if purchased **within the last 7 days and in the same calendar month**. Otherwise, commitments cannot be cancelled, modified or sold (there is **no Savings Plans marketplace**).
- **Database Savings Plans cannot be combined with RIs or DynamoDB reserved capacity on the same workload** (but can cover a different workload).
- Tools: **Savings Plans recommendations** in Cost Explorer / Cost Optimization Hub (based on 7, 30 or 60 days of history), **Savings Plans Purchase Analyzer** (model custom commitment amounts), **utilization** and **coverage** reports, SP budgets.
- **Queueing:** you can schedule SP purchases for a future date (e.g., to start the day an existing RI expires) — useful for renewal planning.

**Lambda & Fargate gotcha:** only **Compute Savings Plans** discount Lambda and Fargate. EC2 Instance SPs and RIs never do. Lambda request charges are not discounted (duration is).

#### 2.2.3 EC2 Reserved Instances (RIs)

An RI is **not an instance** — it is a **billing discount** (and optionally a capacity reservation) applied to running On-Demand instances that match its attributes.

**Offering classes:**

| | **Standard RI** | **Convertible RI** |
|---|---|---|
| Discount | Deepest (up to ~72%) | Lower (up to ~66%) |
| Modify (AZ, scope, size within family on Linux, network platform) | Yes | Yes |
| **Exchange** for different family / OS / tenancy / scope | **No** | **Yes** — for another Convertible RI of **equal or greater value** |
| **Sell in RI Marketplace** | **Yes** | **No** |
| Buy in RI Marketplace | Yes | No |
| Term / payment | 1 or 3 yr; No / Partial / All Upfront | Same |

**Scope — regional vs zonal (heavily tested):**

| | **Regional RI** | **Zonal RI** |
|---|---|---|
| Capacity reservation | **No** | **Yes — in that AZ, for the owning account only** |
| AZ flexibility | Any AZ in the Region | That AZ only |
| Instance size flexibility | **Yes** (Linux/Unix, default tenancy) | No — exact type must match |
| Sharing across org | Discount shared (if enabled) | Discount shared; **capacity is not** shared (use ODCRs + RAM to share capacity) |

**Instance size flexibility** (regional RIs only): discount applies across sizes in the same family using **normalization factors** — nano 0.25, micro 0.5, small 1, medium 2, **large 4, xlarge 8, 2xlarge 16**, 4xlarge 32, 8xlarge 64, 16xlarge 128, etc. Discount applies smallest-to-largest. **Not supported for:** zonal RIs; Windows Server (incl. with SQL Server); **RHEL; SUSE**; dedicated tenancy; some accelerated families (G4dn/G5/G6, P5, Inf1/Inf2 …).

> Example: one regional `m5.2xlarge` Linux RI (16 units) fully covers two `m5.xlarge` (2 × 8) or four `m5.large` (4 × 4), or 50% of an `m5.4xlarge`.

**RI Marketplace (verified rules):**
- Only **EC2 Standard** RIs (regional or zonal) can be sold. **Convertible RIs and RDS/ElastiCache/other-service reservations cannot.**
- RI must have been **active ≥ 30 days**, have **≥ 1 month remaining**, and any upfront payment must have been received.
- AWS charges a **12% service fee** on the upfront price; seller needs a **US-address bank account**; **lifetime selling limit of $50,000 / 5,000 RIs** per account (not increasable).
- RIs bought with a volume discount cannot be sold.

**Status notes:** Scheduled RIs are no longer offered. AWS positions **Savings Plans as the recommended commitment model for EC2**; RIs remain relevant for **capacity (zonal)**, for **reselling** (Standard), and for **non-EC2 services** (RDS, ElastiCache, OpenSearch, Redshift, MemoryDB) — though Database Savings Plans now overlap many of those.

#### 2.2.4 Reservations for other services

| Service | Reservation product | Key points |
|---|---|---|
| **Amazon RDS** | Reserved DB instances (1/3 yr; No/Partial/All Upfront) | **Size flexibility** for MySQL, MariaDB, PostgreSQL, Oracle BYOL (and Aurora) — **not** for SQL Server or Oracle License Included. Must match engine, Region, Single-AZ vs Multi-AZ (Multi-AZ counts double normalized units). Not sellable. |
| **Aurora** | Reserved DB instances (provisioned instances); **I/O-Optimized** instances also reservable | Serverless v2 not covered by RIs → use **Database Savings Plans** |
| **ElastiCache** | Reserved nodes (1/3 yr) | Size flexibility within a family now supported for reserved nodes; ElastiCache Serverless covered only via Database SP (Valkey) |
| **OpenSearch Service** | Reserved Instances (1/3 yr) | Per instance type per Region |
| **Redshift** | Reserved nodes (1/3 yr) | Provisioned clusters (RA3/DC2); Redshift Serverless uses separate reservations/compute pricing |
| **MemoryDB** | Reserved nodes | |
| **DynamoDB** | **Reserved capacity** for **provisioned** WCUs/RCUs | **Up to 54% (1 yr) / 77% (3 yr)** off provisioned rates; bought in **blocks of 100 WCU/RCU**; **Standard table class only** (not Standard-IA), **single-Region only** (not replicated WCUs), non-refundable, non-transferable. **Not for on-demand mode** — on-demand throughput is covered by Database SP instead. |

#### 2.2.5 On-Demand Capacity Reservations (ODCR) & Capacity Blocks

- **ODCR** reserves EC2 capacity for a specific instance type, platform, **AZ**, tenancy, and count — **no term commitment** (create/cancel any time; future-dated reservations can require a minimum commitment duration). You pay the **On-Demand rate whether or not instances run in it**.
- **Discount + capacity = ODCR + Savings Plan (or regional RI).** The SP or regional RI discount applies to instances running in the reservation *and to unused reserved capacity*. This is AWS's recommended replacement for zonal RIs when you need flexibility.
- Can be **shared across accounts via AWS RAM**; can be targeted (only launches that specify the reservation) or open (any matching launch consumes it). **Capacity Reservation Fleets** reserve across multiple instance types. Can be used in cluster placement groups.
- **Use cases:** DR in another Region/AZ where you must be sure capacity exists at failover; regulated "must run" events (Black Friday); scaling a large cluster on a fixed date.
- **EC2 Capacity Blocks for ML** reserve GPU/Trainium instances for a defined future window (days to weeks), paid upfront — for short training runs where On-Demand GPU capacity is scarce.

#### 2.2.6 Spot Instances

Spare EC2 capacity at **up to 90% off On-Demand**. Prices change gradually with long-term supply/demand (no bidding war since 2017 pricing model). You can be **interrupted** when EC2 needs the capacity back.

| Mechanism | Detail |
|---|---|
| **Interruption notice** | **2-minute warning** via instance metadata (`spot/instance-action`) and an **EventBridge** event. Interruption behaviour: **terminate** (default), **stop**, or **hibernate** (EBS-backed, persistent requests). |
| **EC2 instance rebalance recommendation** | An **earlier** signal that the instance is at **elevated risk** of interruption — arrives before (sometimes well before) the 2-minute notice. Use it to proactively drain and replace. |
| **Capacity Rebalancing** (Auto Scaling / EC2 Fleet / Spot Fleet) | Automatically launches a replacement Spot instance when a rebalance recommendation arrives, then terminates the at-risk one. |
| **Allocation strategies** | **price-capacity-optimized** (**recommended** for most workloads — picks the most available pools, then cheapest among them); **capacity-optimized** (lowest interruption, for high cost-of-interruption work like long CI, HPC, rendering, deep learning); **capacity-optimized-prioritized** (capacity first, honour your type priorities best-effort); **diversified** (spread evenly across pools — large/long-running fleets); **lowest-price** (**not recommended** — highest interruption risk; still the CLI default for fleets, so override it). |
| **Spot placement score** | Returns a **score 1–10** for how likely a Spot request of a given size and instance mix will succeed in a **Region or AZ**. Free. Requires **≥ 3 instance types** (or attributes resolving to ≥ 3) for a meaningful score. Use to pick Regions/AZs for Spot-heavy workloads. |
| **Spot Instance advisor / interruption frequency** | Historical interruption-rate bands per instance type — informational. |
| **Attribute-based instance type selection** | Specify vCPU/memory ranges instead of type names → maximises pools automatically. |
| **Spot Fleet vs EC2 Fleet vs ASG** | **EC2 Auto Scaling group with mixed instances policy** is the usual answer for services; **EC2 Fleet** (`instant`/`request`/`maintain`) for programmatic batch launches; **Spot Fleet** is the older API (still works). All support On-Demand base + Spot percentage. |
| **Spot blocks (defined duration)** | **Retired** — don't pick an answer that relies on them. |

**Good Spot workloads:** stateless web/API tiers behind a load balancer, containers (ECS/EKS with Spot capacity providers / Karpenter), CI/CD runners, big data (EMR task nodes, Spark), batch (AWS Batch), rendering, ML training with checkpointing, test/dev.
**Bad Spot workloads:** single-instance stateful databases, anything that cannot tolerate a 2-minute termination, licensed software tied to an instance, workloads requiring a specific single instance type in a single AZ.

**Spot best-practice recipe** (what the "correct" answer usually contains): diversify across **many instance types and all AZs**, use **price-capacity-optimized**, enable **Capacity Rebalancing**, handle the 2-minute notice (drain, checkpoint to S3/EFS), keep an **On-Demand base** for the minimum required capacity.

#### 2.2.7 Dedicated Hosts and Dedicated Instances

| | **Dedicated Instances** | **Dedicated Hosts** |
|---|---|---|
| Isolation | Hardware dedicated to your account | A whole physical server dedicated to you |
| Visibility of sockets/cores, host affinity | No | **Yes** — needed for **per-socket / per-core / per-VM BYOL** licences (Windows Server, SQL Server, Oracle, some RHEL/SUSE subscriptions) |
| Billing | Per instance + **$2/hour per-Region fee** whenever ≥ 1 Dedicated Instance runs (not SP-discountable) | **Per host-hour**, regardless of how many instances run on it |
| Discounts | Compute & EC2 Instance SPs apply to dedicated tenancy (fee excluded); RIs with dedicated tenancy | **Dedicated Host Reservations** (1/3 yr), **Compute SPs apply to Dedicated Host usage** |
| Management | Automatic placement | Host Resource Groups + **AWS License Manager** can auto-allocate/release hosts and track licence limits |

Exam rule: "**reuse existing per-core/per-socket licences**, licence compliance requires visibility of physical cores" → **Dedicated Hosts** (+ License Manager). "Compliance requires single-tenant hardware, no licence constraint" → Dedicated Instances (cheaper to operate).

#### 2.2.8 Layering commitments — the model answer

```text
 Spend/hour
   ^
   |        ~~~~~ peaks ~~~~~           <- On-Demand (or Spot if interruptible)
   |   ~~~~/                 \~~~~
   |--/---------------------------\---  <- Spot for fault-tolerant burst / batch
   |=================================   <- Compute Savings Plan (flexible baseline)
   |#################################   <- EC2 Instance SP / Standard RI (very stable core)
   |%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%   <- ODCR (+SP discount) only where capacity is mandatory
   +-----------------------------------> time
```

- Commit to the **trough** (the minimum steady usage over the last 30–60 days after rightsizing), not the average. Typical target: **coverage 70–90%** of steady compute, **utilization ~100%**.
- Use **EC2 Instance SP / Standard RI** only for workloads whose family and Region won't change; use **Compute SP** for everything else (especially if Graviton/Fargate/Lambda migration is planned).
- **Stagger** purchases (e.g., quarterly tranches) so expirations don't create a cliff and you can adapt.
- **Centralise** purchasing in one account (often a dedicated "commitments" or the management account) and rely on sharing.

---

### 2.3 AWS Organizations consolidated billing

- One **payer (management account)** receives a single bill for all member accounts. No extra cost.
- **Volume pricing tiers are aggregated** across all accounts — S3 storage tiers, data transfer-out tiers, etc. Ten accounts each using 40 TB of S3 are billed as 400 TB at the tiered rate.
- **RI and Savings Plans discounts are shared** across all accounts by default (benefit applies to the purchasing account first, then others). Billing treats the org as one account; zonal RIs in another account can even be applied before a member's own regional RIs to maximise utilisation.
- **Discount sharing controls (management account → Billing preferences):**
  - **Deactivate sharing per account** — that account's RIs/SPs stay with it, and it doesn't receive others' discounts. **Both the purchasing and receiving accounts must have sharing active** for a discount to flow. The SP **owner account must remain active** for its SP to benefit others.
  - **Group-based sharing** (uses **Cost Categories**, Accounts dimension only; each account in one group; payer can't be in a group):
    - **Prioritized group sharing** — owner first, then its group, then rest of org.
    - **Restricted group sharing** — owner first, then **only** within the group; never outside, even if unused.
  - Final monthly bill uses the preference in place at **23:59:59 UTC on the last day of the month**.
- **Credits** can also be shared or restricted.
- **Gotcha:** if an SP owner account **leaves the organization**, its SPs no longer apply to the consolidated bill.
- **SCPs have no effect on billing behaviour** — they can stop resource creation, but they don't stop discount sharing.
- **Billing transfer** (newer): a management account can transfer bill payment/management to an external account that manages several organizations' bills (used with Billing Conductor by partners/holding companies).

---

### 2.4 Cost visibility & governance tools

#### 2.4.1 AWS Cost Explorer

- Interactive cost & usage analysis: group/filter by service, account, Region, usage type, tag, cost category, purchase option, etc. Default history: 13 months at daily/monthly granularity (multi-year monthly history can be enabled); **hourly and resource-level granularity** is an opt-in paid feature (limited lookback, 14 days).
- **Forecasting**: ML forecast with **80% prediction interval**; horizon extended to **18 months** (Nov 2025, previously 12) using up to 36 months of history. AI explanations via Amazon Q Developer.
- **Recommendations**: **Savings Plans** and **RI purchase recommendations** (by service; lookback 7/30/60 days; term and payment option; per account or org-wide), **rightsizing recommendations** (EC2 — powered by Compute Optimizer when enabled).
- **Reports**: **RI utilization** & **RI coverage**, **SP utilization** & **SP coverage**. *Utilization* = how much of what you bought you're using (aim ~100%). *Coverage* = how much of your eligible usage is covered by commitments (aim high but not 100%).
- **Cost views**: unblended, blended, **amortized** (spreads upfront fees across the term — use this for showback), net unblended/net amortized (after credits/discounts).
- **Cost Explorer API** is charged per request (useful for automation, but CUR is cheaper for bulk analytics).

#### 2.4.2 Cost and Usage Report (CUR) → AWS Data Exports / CUR 2.0

- **AWS Data Exports** is the current mechanism; export types: **CUR 2.0** (recommended), **FOCUS 1.0/1.2 with AWS columns** (FinOps Open Cost & Usage Specification — vendor-neutral multi-cloud schema), **Cost Optimization Recommendations** (from Cost Optimization Hub), **Carbon emissions**, a pre-built **Cost and usage dashboard** (QuickSight integration), and **Legacy CUR**.
- CUR 2.0 improvements: **fixed, consistent schema**, **SQL-style column selection and row filtering** (exclude sensitive columns or certain accounts), nested tag/attribute columns, account name columns. Delivered to **S3** in **Parquet** (best for Athena) or CSV, refreshed up to several times a day, with hourly/daily/monthly line items and **resource IDs**.
- **Analytics stack:** Data Exports → S3 → **Glue crawler / Athena table** → **Amazon QuickSight** (now **Amazon Quick Sight**, part of the **Amazon Quick Suite**) → **Cloud Intelligence Dashboards (CID)**: **CUDOS** (Cost & Usage Dashboards Operations Solution — deep service-level drill-downs), **CID** (executive view), **KPI dashboard** (savings/coverage/tagging KPIs), **Trusted Advisor Organizational (TAO)** and **Compute Optimizer** dashboards. Deploy in a dedicated data-collection/FinOps account; replicate exports from the management account's bucket with S3 replication.
- **When CUR beats Cost Explorer:** line-item/resource-level detail, joining with CMDB or tag data, custom allocation (e.g., splitting shared EKS clusters), multi-year retention, feeding third-party FinOps tools.

#### 2.4.3 AWS Budgets

- Budget types: **Cost**, **Usage**, **RI utilization**, **RI coverage**, **Savings Plans utilization**, **Savings Plans coverage**. Periods: daily, monthly, quarterly, annual; **fixed, planned (per-period amounts) or auto-adjusting** budgets (auto-adjusting based on historical spend).
- Alerts on **actual** or **forecasted** thresholds → email, **SNS**, Amazon Q Developer in chat apps (Slack/Chime).
- **Budget actions** (run automatically or after **manual approval**):
  1. **Apply an IAM policy** (e.g., deny `ec2:RunInstances`) to a user/group/role,
  2. **Apply an SCP** to an account/OU (**only from the management account**),
  3. **Stop specific EC2 or RDS instances** (in the same account — can't target instances in another account from the management account).
  Multiple actions can fire at the same threshold. Requires an IAM role that AWS Budgets assumes.
- Budgets are cheap (first budgets free; action-enabled budgets incur a small daily charge) — the exam treats them as the low-overhead control.
- **Budgets vs CloudWatch billing alarms:** billing alarms (`EstimatedCharges`, us-east-1) are legacy and account-total only; Budgets support filters (tags, accounts, services, cost categories), forecasts, and actions.
- **Budgets cover AWS Marketplace charges** (filter by billing entity) — Cost Anomaly Detection mostly doesn't.

#### 2.4.4 AWS Cost Anomaly Detection

- **ML-based** detection of unusual spend on **net unblended cost**; runs ~**3 times a day**; uses Cost Explorer data (up to ~24 h delay). New services need ~10 days of history.
- **Monitors**: AWS services (all services independently — AWS-managed monitor), **linked account**, **cost category**, **cost allocation tag**.
- **Alert subscriptions**: individual (immediate, via **SNS**) or daily/weekly summaries (email); thresholds by absolute $ or % impact.
- **Root-cause analysis** ranked by dollar impact across **service, account, Region, usage type**; integrates with EventBridge and Amazon Q Developer.
- Free. Doesn't monitor most AWS Marketplace charges (use Budgets).
- **Budgets vs Anomaly Detection:** Budgets = "tell me (or act) when I cross a number I chose". Anomaly Detection = "tell me when spend deviates from the learned pattern, even if I'm under budget" (e.g., a leaked access key spinning up GPU instances on day 2 of the month).

#### 2.4.5 Cost allocation tags

- **User-defined tags** (key you create, e.g., `CostCenter`, `Application`, `Environment`) and **AWS-generated tags** (e.g., `aws:createdBy`, `aws:cloudformation:stack-name`; `awsApplication` from AppRegistry — auto-activated, doesn't count toward quota).
- Tags **must be activated** as cost allocation tags in the **Billing console of the management account** (or via `UpdateCostAllocationTagsStatus`). New keys take **up to 24 h to appear**, then **up to 24 h to activate**. Tag data appears in Cost Explorer/CUR **only from activation onward** (AWS offers a limited **backfill** request for historical months — don't rely on it in exam answers).
- **Not all resources/charges are taggable** (e.g., some data transfer, support fees) → need Cost Categories split charges or account-based allocation for the remainder.
- **Enforcement:**
  - **Tag policies** (AWS Organizations) standardise **key capitalisation and allowed values**; with `enforced_for` they **block non-compliant tagging operations** on listed resource types. They **do NOT require tags to exist at resource creation** via native APIs. (Since Nov 2025, tag policies can also declare **required tag keys** that IaC tools — CloudFormation via a hook, Terraform, Pulumi — validate before deployment.)
  - **SCPs (or IAM policies) with `aws:RequestTag/<key>` and `aws:TagKeys` conditions** — **deny create calls that lack the tag**. This is the exam answer for "**prevent creation of untagged resources**".
  - **AWS Config** rule `required-tags` — detect (and remediate via SSM Automation) non-compliance after the fact.
  - **Resource Groups Tag Editor** — bulk tag existing resources.
- **Account-based allocation is the strongest allocation dimension.** Tags fail for shared/untaggable resources; accounts never do. Best practice: **account per workload/environment**, tags for finer splits.

#### 2.4.6 AWS Cost Categories

- Rules that map cost & usage into **business-meaningful groups** (e.g., `BusinessUnit = Retail`) using accounts, tags, services, charge types, other cost categories — **hierarchical** and retroactive for the current/previous months as rules allow.
- **Split charges**: allocate shared costs (shared networking account, enterprise support, shared EKS cluster) to other categories **proportionally, evenly, or by fixed %**.
- Appear in Cost Explorer, Budgets, CUR, Anomaly Detection — and are the grouping mechanism for **RI/SP group sharing**.
- **Do not change prices** → no markups. That's Billing Conductor.

#### 2.4.7 AWS Billing Conductor (ABC)

- Creates a **pro forma** second version of the bill for **showback/chargeback** with **custom rates**: **billing groups** (sets of accounts with a primary account), **pricing plans/rules** (global or service-specific **markup or discount**, Free Tier control), **custom line items** (one-time/recurring flat or % charges/credits — e.g., allocate support fees or internal platform fees).
- Accounts in a billing group see **pro forma costs** in Cost Explorer, Bills page, Budgets and their own CUR; the payer sees the **margin report** (pro forma vs billable).
- **Does not change the AWS invoice** or how RIs/SPs/credits are actually applied.
- Users: AWS **resellers / Channel Partners**, MSPs, holding companies with subsidiaries, internal IT that charges BUs a blended rate. Charged for standard billing groups; free for billing-transfer billing groups.

#### 2.4.8 AWS Pricing Calculator

- Estimate cost of planned architectures (public console, shareable estimate link, exportable). In-console version (inside Billing and Cost Management) can create **workload estimates** and **bill estimates** that factor **your discounts and commitments** (and model "what if" SP/RI purchases). Use for **migration business cases** (with Migration Evaluator / AWS Transform assessment data) and TCO.

#### 2.4.9 Cost Optimization Hub

- **Single place to consolidate, de-duplicate and prioritise** cost recommendations **across accounts and Regions** (org-wide when the management account opts in; delegated admin supported). Free.
- Recommendation types: **rightsizing**, **idle resource deletion**, **Graviton migration**, **upgrade to newer generation**, **Savings Plans and reservation purchases**. Supported resources include EC2, Auto Scaling groups, EBS, Lambda, ECS on Fargate, RDS instances and storage, Aurora storage, ElastiCache, MemoryDB, DynamoDB, DocumentDB, OpenSearch/Redshift reservations, SageMaker endpoints/SP, WorkSpaces, **NAT gateways**.
- **Savings estimates incorporate your actual discounts** (RIs, SPs, private pricing) and **de-duplicate** overlapping actions (e.g., won't count both "rightsize" and "buy SP" savings for the same instance).
- Provides a **cost efficiency metric** to track progress. Exportable via Data Exports.

#### 2.4.10 AWS Compute Optimizer

- ML analysis of **CloudWatch utilisation metrics** (default 14-day lookback; **enhanced infrastructure metrics** paid feature extends to **93 days**; memory requires the CloudWatch agent) to recommend: **EC2 instance types** (incl. Graviton), **Auto Scaling group** configs, **EBS volume** type/size/IOPS (e.g., gp2→gp3), **Lambda memory**, **ECS on Fargate task size**, **RDS/Aurora DB instances & storage**, **commercial software licences** (e.g., SQL Server edition), and **idle resources**.
- Findings: Under-provisioned / Over-provisioned / Optimized; performance-risk ratings. Org-wide via management or delegated admin account. Feeds Cost Optimization Hub.
- **Compute Optimizer finds the right *size*; Cost Optimization Hub prioritises *all* savings; Cost Explorer recommends *commitments* (also in COH).**

#### 2.4.11 AWS Trusted Advisor (cost checks)

- Cost optimization checks such as **low-utilization EC2 instances**, **idle load balancers**, **underutilized EBS volumes**, **unassociated Elastic IPs**, **idle RDS instances**, **RI/SP optimization and expiration**, Lambda over-provisioning, etc. (some checks are now sourced from Compute Optimizer/Cost Optimization Hub).
- **Full set of checks requires Business Support or higher** (AWS has restructured support-plan names — check current tiers); Basic support gets core security/service-limit checks only. Organizational view aggregates across accounts. Results also available via EventBridge and Trusted Advisor Priority (Enterprise).

#### 2.4.12 Showback vs chargeback

| | **Showback** | **Chargeback** |
|---|---|---|
| Definition | Report costs to teams for awareness; no money moves | Actually bill the team's budget / P&L |
| Accuracy needed | Directional | High; must be auditable and agreed |
| Typical tools | Cost Explorer, Cost Categories, CUR/CID dashboards, Budgets per team | CUR 2.0 + Cost Categories split charges; **Billing Conductor** when custom rates/markups are needed |
| Shared costs | Often shown separately | Must be allocated (split charges / custom line items) |
| Commitment benefits | Often show **amortized** cost | Decide policy: central team keeps savings, or pass through amortized RI/SP benefits |

**Maturity path:** account structure → tagging strategy + enforcement → Cost Categories → showback dashboards → chargeback (possibly Billing Conductor) → unit economics (cost per transaction/customer, from CUR joined with business metrics).

---

### 2.5 Architectural cost levers

#### 2.5.1 Compute

- **Rightsizing first** (Compute Optimizer). Downsize over-provisioned instances; change family to match profile (compute-, memory-, storage-optimised); use burstable **T-family** for low average CPU with unlimited mode awareness.
- **AWS Graviton (Arm)**: AWS cites **up to 40% better price performance** vs comparable x86 instances (Graviton2 claim; later generations improve further) and roughly **~20% lower price per instance** at the same size. Works on EC2, Fargate, Lambda (arm64), RDS/Aurora, ElastiCache, OpenSearch, EMR. Needs Arm-compatible binaries/containers (multi-arch images). Lambda arm64 has a lower GB-second price.
- **Newer generations** are usually cheaper per unit of performance (m5→m7i/m7g, r5→r7g).
- **Scheduling non-production**: dev/test running 12 h × 5 days = **60 of 168 hours (≈ 64% fewer hours)**. Tools: **Instance Scheduler on AWS** (solution: DynamoDB schedules, Lambda, tags, cross-account, EC2 + RDS), **Systems Manager Quick Setup Resource Scheduler**, ASG scheduled actions (desired=0), Aurora/RDS stop (RDS auto-restarts after 7 days stopped!).
- **Auto scaling**: target tracking (e.g., 50–70% CPU), **predictive scaling** for cyclical loads, scale-in protection only where needed, **warm pools** to keep pre-initialised stopped instances cheaply (pay only EBS for stopped instances).
- **Elasticity over peak provisioning:** the cloud cost model punishes "provision for peak".

#### 2.5.2 Containers

- **Bin-packing**: ECS placement strategy `binpack` (on CPU/memory) packs tasks onto fewer instances; EKS **Karpenter** consolidation removes under-utilised nodes and picks cheapest fitting instance types (incl. Spot).
- **Right-size task/pod requests** (over-requested pods waste node capacity; Compute Optimizer supports ECS on Fargate; tools like Kubecost / EKS split cost allocation data in CUR for per-pod cost).
- **Fargate vs EC2 launch type**: Fargate = no node management, pay per vCPU/GB-second of task; EC2 = cheaper at high, steady utilisation with good bin-packing + RIs/SPs. Compute SPs cover both.
- **Fargate Spot**: up to **70% off** Fargate price, interruptible with **2-minute warning** (SIGTERM to task); use via **capacity provider strategy** (e.g., base 2 on FARGATE, weight 1:3 FARGATE:FARGATE_SPOT). Fargate Spot is ECS-only (not EKS) — EKS uses Spot via EC2 managed node groups/Karpenter.
- **Fargate on Graviton** (ARM64) cheaper per vCPU/GB.

#### 2.5.3 Serverless vs always-on — the break-even idea

Lambda cost = **requests × $0.20/M + GB-seconds × ~$0.0000166667 (x86)**; arm64 is cheaper per GB-s. Always-on cost = instance-hours regardless of traffic. Serverless wins at **low/variable/spiky** utilisation; always-on (with SPs) wins at **high, steady** throughput. Also count **API Gateway** (REST ≈ $3.50/M vs **HTTP API ≈ $1.00/M — about 71% cheaper**), ALB hourly + LCU, NAT, and **operational overhead** (patching, scaling) — the exam usually weights the last one heavily. See worked scenario 5.5.

#### 2.5.4 Storage

| Lever | Detail |
|---|---|
| **S3 Lifecycle** | Transition: Standard → Standard-IA / One Zone-IA (**min 30 days storage**) → Glacier Instant Retrieval (**90 d min**) → Glacier Flexible Retrieval (**90 d**) → Glacier Deep Archive (**180 d**, cheapest, 12–48 h restore). Expire old versions and **abort incomplete multipart uploads**. Each transition is a per-request charge — avoid transitioning millions of tiny objects (by default lifecycle **doesn't transition objects < 128 KB**). |
| **S3 Intelligent-Tiering** | For **unknown/changing access patterns**: auto-moves objects between Frequent, Infrequent (after 30 d), Archive Instant Access (90 d) tiers, optional Archive Access/Deep Archive Access tiers; **no retrieval fees**, small **per-object monitoring fee**; objects **< 128 KB are not monitored and always billed at Frequent tier**. |
| **S3 Storage Lens / Storage Class Analysis** | Find candidates for lifecycle, incomplete MPUs, non-current versions. |
| **S3 Requester Pays** | Shift request & transfer cost to data consumers. |
| **EBS gp2 → gp3** | gp3 is **~20% cheaper per GB** and decouples performance: **baseline 3,000 IOPS / 125 MB/s** included regardless of size; gp2 IOPS scale with size (3 IOPS/GB). Modify in place with **Elastic Volumes** (no downtime). Also io1→io2 (same price, better durability) and right-size provisioned IOPS. |
| **EBS cleanup** | Delete **unattached volumes**, old **snapshots** (incremental, but orphaned AMI snapshots accumulate); automate with **Data Lifecycle Manager**; move long-retention snapshots to **EBS Snapshots Archive** (~75% cheaper, **90-day minimum**, 24–72 h restore); **Recycle Bin** prevents accidental deletion. st1/sc1 for throughput/cold HDD workloads. |
| **EFS** | **Lifecycle management** to **EFS Infrequent Access** and **EFS Archive** tiers; **One Zone** storage classes for non-critical data; **Elastic throughput** (pay for what you use) vs Provisioned. |
| **FSx** | Data deduplication/compression (FSx for Windows, FSx for ONTAP with capacity pool tiering), HDD storage options, single-AZ for dev. |
| **Public IPv4** | **$0.005/hour per public IPv4 address** (in-use or idle, since Feb 2024) — clean up idle Elastic IPs; prefer private subnets + endpoints, IPv6, or shared egress. |

#### 2.5.5 Databases

- **Aurora I/O-Optimized vs Standard (decision rule, verified):** choose **I/O-Optimized when I/O spend ≥ 25% of total Aurora spend**; otherwise Standard. I/O-Optimized: **no per-I/O charges**, instance price **~30% higher**, storage **$0.225 vs $0.10 per GB-month**. Switch Standard → I/O-Optimized **once every 30 days**; back to Standard **any time** (non-NVMe instances: no downtime).
- **Aurora Serverless v2**: scales in fine-grained **ACU** increments (≈ 2 GiB memory each); can now scale down to **0 ACU with auto-pause** for idle dev/test; ideal for variable or unpredictable load and many small databases; for steady high load, provisioned + RIs/Database SP is cheaper. Mixed clusters (provisioned writer + Serverless v2 readers) are allowed.
- **RDS**: Multi-AZ doubles instance cost (use only where needed — not dev); **stop** dev DBs (auto-restart after 7 days); use **gp3 storage**; Graviton instance classes; **RDS Optimize CPU** to reduce vCPU-based licence costs; downgrade **SQL Server Enterprise → Standard** where features allow (licence-included price difference is large); consider **Babelfish for Aurora PostgreSQL** or migration to open-source engines to remove commercial licences.
- **DynamoDB capacity modes:**
  - **On-demand**: pay per request (**$0.625/M WRU, $0.125/M RRU** after the Nov-2024 50% price cut). Instant scaling, zero planning.
  - **Provisioned**: pay per WCU/RCU-hour (**$0.00065/WCU-h, $0.00013/RCU-h**) + auto scaling + reserved capacity.
  - **Break-even**: a fully-used WCU for 1 hour = 3,600 writes ⇒ **$0.18 per million writes** provisioned vs **$0.625** on-demand ⇒ provisioned is cheaper when **average utilisation of provisioned capacity > ~29%** (same ratio for reads). Spiky, unpredictable, or new tables → on-demand. Steady, predictable → provisioned + auto scaling (+ reserved capacity for a 1–3 yr baseline).
  - You can switch modes (limited number of switches per 24 h).
  - **Standard-IA table class**: ~60% lower storage, higher request price — for **storage-dominated** tables (old orders, logs).
  - **TTL** deletes expired items **for free** (no WCU consumed).
- **Read replicas vs caching:** read replicas cost a full instance each and still incur DB I/O; **ElastiCache/DAX** absorb hot reads at microsecond latency and can be cheaper than several replicas for repetitive key-based reads. Replicas fit **complex/ad-hoc queries** and reporting; caches fit **repetitive reads of the same items**. Also consider Aurora **reader auto scaling** and query optimisation (Performance Insights) before adding hardware.
- **Redshift**: pause/resume provisioned clusters, RA3 with managed storage, **Redshift Serverless** for intermittent analytics, Concurrency Scaling free credits (1 h/day accrued), **Spectrum/Athena** for cold data in S3.

#### 2.5.6 Data transfer — deep dive (the most under-estimated bill line)

**Core rules of thumb (list prices, us-east-1):**

| Path | Charge |
|---|---|
| Internet → AWS (ingress) | **Free** |
| AWS → Internet (egress) | Tiered, **~$0.09/GB** first 10 TB; first **100 GB/month free** (aggregated across services/Regions) |
| Within same AZ, private IP | **Free** |
| **Across AZs** in a Region (EC2↔EC2, EC2↔RDS, etc.) | **~$0.01/GB in each direction** (i.e., ~$0.02/GB round trip). Also applies to public/Elastic IPs within a Region. |
| **Between Regions** | **~$0.02/GB** out of source Region (varies; higher from some Regions) |
| **VPC peering** | **Free within same AZ**; cross-AZ normal inter-AZ rate; inter-Region peering = inter-Region rate. **No hourly charge, no processing charge.** |
| **Transit Gateway** | **$0.05/attachment-hour** + **$0.02/GB processed** (charged to the sending VPC/attachment) — on top of normal data transfer. No processing charge for data sent from a TGW **peering** attachment. |
| **NAT gateway** | **$0.045/hour per gateway (per AZ)** + **$0.045/GB processed** — in addition to any internet egress or cross-AZ charges. |
| **Gateway VPC endpoints** (S3, DynamoDB only) | **Free** — no hourly, no per-GB. |
| **Interface VPC endpoints (PrivateLink)** | **~$0.01/hour per endpoint per AZ** + **$0.01/GB** processed (cheaper tiers above 1 PB). |
| **CloudFront** | Origin fetch from AWS origins (S3, ALB, EC2) to CloudFront **free**; edge-to-viewer egress cheaper than direct S3/EC2 egress at most tiers; **1 TB/month free tier**; Savings Bundle / private pricing for big volumes. |
| **Direct Connect** | **Ingress free**; **DTO over DX at a much lower rate** (e.g., ~$0.02/GB from US Regions vs ~$0.09/GB internet) + port-hours. |
| **S3 Transfer Acceleration** | **Adds** a per-GB fee — performance feature, not a cost saver. |
| **Global Accelerator** | Fixed hourly + **data transfer premium** per GB — performance feature. |

**Design implications:**

1. **NAT gateway per-GB processing is the classic hidden cost.** Private instances pulling from S3/DynamoDB through NAT pay $0.045/GB for nothing. → **Add S3 and DynamoDB gateway endpoints (free)** to the private route tables. For other AWS services with heavy traffic (ECR, CloudWatch Logs, STS, KMS, SQS), **interface endpoints** at $0.01/GB + hourly are cheaper than NAT's $0.045/GB once volume exceeds roughly (hourly endpoint cost ÷ $0.035/GB) — e.g., an interface endpoint in 3 AZs costs ~$22/month, which breaks even vs NAT at ~630 GB/month. (ECR image layers come from S3 → also need the S3 gateway endpoint.)
2. **Keep NAT gateways per AZ** and route each AZ's subnets to its local NAT — otherwise you pay cross-AZ + NAT processing (and lose AZ independence). The new **regional NAT gateway** mode is billed per AZ it covers.
3. **Centralised egress (shared NAT in an egress VPC via TGW)** saves NAT hourly charges but **adds TGW $0.02/GB processing** — it only pays off when many VPCs have *low* egress volume. High-volume VPCs are cheaper with local NAT + gateway endpoints.
4. **Inter-AZ chatter:** chatty microservices, Kafka replication, Cassandra/Elasticsearch clusters, and app↔DB across AZs. Use **AZ-affinity routing** (keep calls in-AZ where resilience allows), **MSK rack-awareness / follower fetching**, **ALB cross-zone load balancing considerations** (ALB doesn't charge inter-AZ for LB→target traffic; NLB with cross-zone enabled does incur inter-AZ charges). Never sacrifice Multi-AZ resilience of a production tier just to save inter-AZ transfer — exam answers keep Multi-AZ.
5. **VPC peering vs TGW:** high-volume pairs of VPCs → **peering** (no processing fee, free same-AZ). TGW for **scale and transitive routing** (hundreds of VPCs, on-prem). Hybrid: TGW for the mesh + targeted peering for heavy pairs.
6. **Internet egress → CloudFront** (cheaper per GB, caching reduces origin load, free origin fetch). Big static downloads/video: CloudFront always beats serving directly from S3/EC2.
7. **Hybrid egress → Direct Connect** when large volumes go back on-premises; DX DTO rates are a fraction of internet rates. VPN over internet pays internet DTO rates.
8. **Cross-Region replication costs**: S3 CRR = inter-Region transfer + replication PUT requests (+ **S3 RTC** per-GB fee if enabled); DynamoDB global tables = replicated write units in each Region + transfer; Aurora Global Database = replicated write I/Os + transfer; EBS snapshot copy and AMI copy = transfer + storage. **Replicate only what the RPO requires** (filter by prefix/tag; don't replicate logs).
9. **Compress and filter at source** (Kinesis/Firehose compression, Parquet, CloudWatch Logs subscription filters) to cut transfer and storage at the same time.

#### 2.5.7 Logging & observability cost

- **CloudWatch Logs Infrequent Access log class**: **~50% lower ingestion price per GB** (e.g., $0.25 vs $0.50/GB); storage and Logs Insights pricing identical. Supports Logs Insights, export to S3, KMS, cross-account, masking. **Does not support** metric filters, subscription filters, Live Tail, Logs Anomaly Detection, `GetLogEvents`/`FilterLogEvents`, Container/Lambda Insights, EMF. **Log class can't be changed after the log group is created** → create new log groups for IA. There's also a **Delivery** class for Lambda logs delivered straight to S3/Firehose (2-day fixed retention).
- **Retention**: log groups default to **Never expire** — set retention policies (e.g., 30/90 days) and archive to S3 + Glacier for long-term compliance.
- **Vended logs** (VPC Flow Logs, Route 53 Resolver query logs, etc.) have **volume-tiered** pricing; sending them **directly to S3** is generally cheaper than to CloudWatch Logs; use Parquet + hourly partitions for Athena.
- **CloudTrail**: the **first copy of management events per Region is free**; additional trails and **data events** are charged per event — scope data events with advanced event selectors. CloudTrail Lake has ingest/retention pricing.
- **Metrics**: custom metrics and high-resolution metrics cost per metric; avoid high-cardinality dimensions; EMF and metric streams have their own costs. Container Insights/Application Signals add cost — enable where needed.

#### 2.5.8 Licensing

- **License-included vs BYOL**: license-included (Windows, SQL Server, RHEL on EC2/RDS) is simplest; **BYOL** can be much cheaper if you own licences with Software Assurance/licence mobility — often requires **Dedicated Hosts** for per-socket/per-core licences (Windows Server, older SQL Server licence terms, Oracle on some terms).
- **AWS License Manager**: define licence rules (vCPU/core/socket/instance counts), **enforce limits at launch**, track usage across accounts (Organizations), manage **Dedicated Host allocation via host resource groups**, discover software via SSM inventory, and manage **user-based subscriptions** (e.g., Microsoft Office/Visual Studio, Remote Desktop).
- **SQL Server cost levers**: **downgrade Enterprise → Standard** (Compute Optimizer licence recommendations identify Enterprise instances not using Enterprise features), **Optimize CPUs** (disable vCPUs/hyperthreading to cut per-core licence count on memory-heavy instances), consolidate instances, use **Developer edition** for non-prod, move to **Babelfish/Aurora PostgreSQL**.
- **Oracle**: RDS for Oracle (LI only for SE2) vs BYOL; Database Savings Plans now give an Oracle→Aurora PostgreSQL migration path without losing the commitment.
- **Windows**: consider Linux containers/.NET Core on Linux (AWS Transform for .NET modernisation) to remove Windows licence cost.

#### 2.5.9 Security-service & API cost levers

- **KMS**: $1/month per customer managed key + per-request charges ($0.03 per 10,000 requests for symmetric). **S3 Bucket Keys** reduce SSE-KMS request traffic from S3 to KMS by **up to 99%** by using a bucket-level data key — the exam answer for "SSE-KMS costs/throttling on a high-request S3 bucket". AWS managed keys have no monthly fee. SSE-S3 is free.
- **API Gateway**: **HTTP API (~$1.00/M)** vs **REST API (~$3.50/M)** — choose HTTP API unless you need REST-only features (**API keys & usage plans, request validation, WAF integration, private endpoints, edge-optimized, caching, X-Ray**, request/response transformations). Caching on REST is billed hourly per cache size. For very high, steady throughput, **ALB → Lambda** can be cheaper than API Gateway.
- **Secrets Manager vs SSM Parameter Store**: Secrets Manager $0.40/secret/month + API calls (needed for rotation); Parameter Store standard parameters are free — use for non-secret config.
- **GuardDuty / Security Hub / Macie / Inspector** are usage-based — scope Macie to sampled/automated discovery, use GuardDuty cost dashboards; but never answer "disable security service to save cost" on the exam.

---

## 3. Architecture patterns

### Pattern 1 — Organisation-wide FinOps data platform (CUR 2.0 + CID)

```text
 Management (payer) account                       FinOps / Data-collection account
 +-------------------------------+                 +--------------------------------------------+
 | AWS Data Exports              |  S3 replication |  S3 bucket (CUR 2.0 Parquet, FOCUS,        |
 |  - CUR 2.0 (resource IDs,     | --------------> |   COH recommendations, carbon)             |
 |    hourly, split cost alloc)  |                 |        |                                   |
 |  - FOCUS 1.2                  |                 |  Glue crawler / Data Catalog               |
 |  - Cost Optimization Recs     |                 |        |                                   |
 | Cost Categories, tags active  |                 |  Amazon Athena (views, CMDB joins)         |
 +-------------------------------+                 |        |                                   |
                                                   |  Amazon Quick Sight (QuickSight)           |
 Member accounts ---- Compute Optimizer,           |   CUDOS | CID | KPI | TAO | CO dashboards  |
                      Trusted Advisor data  ---->  |  Row-level security per BU                 |
                      (data collection Lambdas)    +--------------------------------------------+
```

- **When:** any multi-account org needing showback/chargeback, unit economics, or KPIs (coverage, utilisation, tagging compliance, Graviton %).
- **Why a separate account:** least privilege — BU analysts get dashboards without access to the payer account. Row-level security per business unit.
- **Trade-off:** small ongoing cost (Athena scans, Quick Sight users) vs Cost Explorer (free UI). Use Parquet + partitions to keep Athena cheap.

### Pattern 2 — Automated budget guardrails for sandbox/dev OUs

```text
              forecast >= 80%                     actual >= 100%
 AWS Budgets ----------------> SNS --> Slack/Chime (Amazon Q Developer in chat apps)
 (per account,     |
  filter: account, +--> Budget action (auto)    : attach SCP "DenyNewCompute" to sandbox account
  cost category)   +--> Budget action (approval): stop tagged EC2/RDS instances in that account
                   |
 Cost Anomaly Detection (AWS services monitor + linked-account monitor)
   --> individual alerts via SNS --> EventBridge --> Lambda (ticket / auto-quarantine key)
```

- **When:** "developers must not exceed $X; stop provisioning automatically; least operational overhead".
- SCP actions **only** from the management account; instance-stop actions only on instances in the budget's own account.
- **Trade-off:** an SCP blocks *new* resources; it doesn't stop running ones — combine with stop actions or Instance Scheduler.

### Pattern 3 — Endpoint-first VPC (kill NAT processing)

```text
                VPC (3 AZs)
  +-----------------------------------------------------------+
  | Private subnets AZ-a/b/c                                  |
  |   EC2 / EKS nodes / Lambda ENIs                           |
  |     |  S3, DynamoDB  -------> Gateway endpoints (FREE)    |
  |     |  ECR api, STS, KMS,                                 |
  |     |  Logs, SQS, SSM -------> Interface endpoints        |
  |     |                          ($/AZ-hour + $0.01/GB)     |
  |     |  everything else ------> NAT GW in SAME AZ          |
  |                                ($/hour + $0.045/GB) -> IGW|
  +-----------------------------------------------------------+
  Shared endpoints option: centralise interface endpoints in a shared-services VPC
  with Route 53 private hosted zones (saves per-VPC hourly fees, adds TGW $/GB).
```

- **When:** high NAT "bytes processed", container image pulls, log shipping, data lake reads.
- **Trade-off:** interface endpoints have an hourly floor — centralise them when you have many low-traffic VPCs; keep them local in high-traffic VPCs.

### Pattern 4 — Spot-first, Graviton-aware compute tier

```text
  ALB  -->  Auto Scaling group (mixed instances policy)
            On-Demand base capacity: 4  (covered by Compute Savings Plan)
            Above base: 20% On-Demand / 80% Spot
            Spot allocation: price-capacity-optimized
            Instance requirements: 2-8 vCPU, 4-32 GiB, arm64 + x86 (multi-arch AMI/image)
            Capacity Rebalancing: ON
            Lifecycle hook: drain on rebalance recommendation / 2-min notice
  Batch side: AWS Batch / EKS + Karpenter (Spot + consolidation), checkpoints to S3
```

- **When:** stateless services and fault-tolerant batch where the stem says "reduce cost, tolerate interruptions".
- **Trade-off:** engineering for interruption (idempotency, checkpointing). Not for singleton stateful systems.

### Pattern 5 — Centralised commitment management

```text
  Management account (Billing preferences)
     |-- RI/SP sharing: ON org-wide (default)
     |-- Restricted sharing group "Subsidiary-X" (Cost Category: accounts A,B,C)
     |
  Commitments account  (buys Compute SPs quarterly, 3-yr No Upfront tranches)
     |-- benefits flow: owner first -> rest of org
  Subsidiary-X account A (buys its own RIs) -> benefits stay inside A,B,C only
  FinOps reviews: SP/RI utilisation & coverage budgets (alert < 95% utilisation)
```

- **When:** central IT owns the rate-optimisation programme; some entities must keep their own benefits.
- **Trade-off:** chargeback complexity — decide whether BUs see on-demand-equivalent, amortised, or net cost.

### Pattern 6 — Non-production scheduling

```text
  Instance Scheduler on AWS (hub account, DynamoDB schedule table) / SSM Resource Scheduler
      |-- cross-account roles --> dev/test accounts
      |-- tag Schedule=office-hours (08:00-20:00 Mon-Fri)
      +--> stop/start EC2, RDS, Aurora clusters; ASG desired=0 at night
  Savings: 168h -> 60h per week  (~64% fewer instance-hours)
```

- **Trade-off:** don't buy commitments for scheduled resources (they'd sit idle at night); use Aurora Serverless v2 auto-pause or serverless alternatives where restart latency is acceptable.

### Pattern 7 — Layered tag governance

```text
  Prevent    : SCP deny ec2:RunInstances / rds:CreateDBInstance ... if aws:RequestTag/CostCenter is null
  Standardise: Tag policy (allowed keys/values, case) + enforced_for on resource types
               + required tag keys validated by CloudFormation hook / Terraform / Pulumi
  Detect     : AWS Config required-tags (org conformance pack) -> SSM Automation remediation
  Allocate   : activate cost allocation tags (payer) -> Cost Categories (+ split charges)
  Report     : Cost Explorer / CUR 2.0 / CID tagging-compliance KPIs
```

---

## 4. Decision tables / "X vs Y"

### 4.1 Commitment and pricing-model selector

| Need | Best fit | Why not the others |
|---|---|---|
| Steady EC2 baseline, family/Region may change, Fargate/Lambda too | **Compute SP** | EC2 Instance SP locks family+Region; RIs don't cover Fargate/Lambda |
| Very stable EC2 family in one Region, max discount | **EC2 Instance SP** (or Standard RI) | Compute SP gives less discount |
| Need to **resell** if plans change | **Standard RI** (RI Marketplace) | SPs and Convertible RIs can't be sold |
| Need to change family/OS/tenancy during term but use RIs | **Convertible RI** (exchange for ≥ equal value) | Standard can't exchange |
| **Guaranteed capacity** in a specific AZ + discount | **ODCR + Savings Plan** (or zonal RI) | SPs/regional RIs give no capacity |
| Many database engines, plan to migrate Oracle → Aurora or RDS → DynamoDB | **Database SP** (1-yr, No Upfront) | RDS RIs are engine/family specific |
| DynamoDB provisioned, steady for 3 years | **DynamoDB reserved capacity** (up to 77%) | Database SP is 1-yr only, smaller discount |
| Interruptible, flexible start time | **Spot** / Fargate Spot | Commitments wasted on bursty usage |
| Short-term GPU training window | **EC2 Capacity Blocks for ML** | ODCR at On-Demand price; Spot unreliable for scarce GPUs |
| Unknown workload, new app | **On-Demand** first, measure, then commit | Committing before rightsizing locks in waste |
| Per-core BYOL licences | **Dedicated Hosts** (+ Host Reservation or Compute SP, License Manager) | Dedicated Instances hide sockets/cores |

### 4.2 Capacity assurance options

| | Zonal RI | ODCR | Capacity Blocks for ML |
|---|---|---|---|
| Commitment | 1/3 yr | None (cancel anytime; future-dated may need a minimum duration) | Fixed window, prepaid |
| Discount | Yes (built in) | No by itself — add SP/regional RI | Priced per block |
| Size/AZ flexibility | None | None (specific type/AZ); Capacity Reservation Fleets for multiple types | Specific accelerated type |
| Share capacity cross-account | No | **Yes (RAM)** | — |
| Use | Legacy approach | DR, events, critical baselines | ML training/inference bursts |

### 4.3 Visibility & governance tools

| Question in the stem | Tool |
|---|---|
| "Visualise/analyse spend trends, forecast next quarter, filter by tag" | **Cost Explorer** |
| "Most granular, line-item/resource-level data for custom analytics/BI" | **CUR 2.0 via Data Exports** → Athena/Quick Sight |
| "Multi-cloud-standard schema" | **FOCUS** export |
| "Alert/act when spend or usage crosses a threshold / forecast" | **AWS Budgets** (+ actions) |
| "Detect unusual spend without setting thresholds; root cause" | **Cost Anomaly Detection** |
| "Group costs into business units incl. shared costs" | **Cost Categories** (+ split charges) |
| "Bill subsidiaries/customers with markup or custom rates" | **Billing Conductor** |
| "Single prioritised list of savings opportunities across org, de-duplicated" | **Cost Optimization Hub** |
| "Right instance size / EBS / Lambda memory / Fargate task size" | **Compute Optimizer** |
| "Idle LBs, unassociated EIPs, low-utilisation checks (plus security/limits)" | **Trusted Advisor** |
| "Estimate cost of a planned architecture / migration" | **Pricing Calculator** (+ Migration Evaluator) |
| "Enforce consistent tag keys/values" | **Tag policies** |
| "Prevent untagged resource creation" | **SCP with `aws:RequestTag` condition** |
| "Find resources missing tags" | **AWS Config `required-tags`** / Tag Editor |

### 4.4 Allocation mechanisms

| Mechanism | Strength | Weakness |
|---|---|---|
| **Accounts** (per workload/BU/env) | 100% coverage, incl. untaggable charges; hard security boundary | Shared services still need splitting |
| **Cost allocation tags** | Fine-grained (app, feature, owner) | Not retroactive; not every charge taggable; drift without enforcement |
| **Cost Categories** | Business mapping across accounts + tags; split shared costs; used for sharing groups | No price changes |
| **Billing Conductor** | Custom rates, markups, custom line items, pro forma per group | Extra cost; another model to maintain |
| **CUR + custom logic** | Anything (e.g., per-pod EKS cost, unit economics) | Engineering effort |

### 4.5 Egress & connectivity cost

| Option | Hourly | Per GB | Choose when |
|---|---|---|---|
| **Gateway endpoint** (S3/DynamoDB) | 0 | 0 | Always, for S3/DynamoDB from private subnets in the same Region |
| **Interface endpoint** | ~$0.01 × AZs | ~$0.01 | Other AWS services with meaningful volume, or private access from on-prem/peered networks |
| **NAT gateway** | ~$0.045 per AZ | ~$0.045 + egress | Internet access from private subnets |
| **VPC peering** | 0 | 0 same-AZ; inter-AZ/Region rates otherwise | Few VPCs, heavy traffic pairs |
| **Transit Gateway** | ~$0.05/attachment | ~$0.02 processing + transfer | Many VPCs, transitive, hybrid hub |
| **CloudFront** | 0 | Lower than direct egress; origin fetch free | Any significant internet delivery |
| **Direct Connect** | Port-hours | Low DTO (e.g., ~$0.02 in US) | Large steady hybrid egress |
| **Site-to-Site VPN** | ~$0.05/connection-hour | Internet DTO rates | Low volume, backup to DX |

### 4.6 Compute model economics

| | Lambda | Fargate | EC2 (+SP/Spot) |
|---|---|---|---|
| Billing unit | Requests + GB-s (1 ms granularity) | vCPU-s + GB-s of task | Instance-seconds |
| Idle cost | **Zero** | Zero if scaled to 0 tasks | Full instance cost |
| Best when | Spiky, event-driven, low average utilisation | Containers, steady-ish, no node ops | High steady utilisation, special hardware, licensing |
| Discounts | Compute SP (duration) | Compute SP, **Fargate Spot** (ECS) | All SPs/RIs, Spot |
| Ops overhead | Lowest | Low | Highest |

### 4.7 Storage tiering choices

| Situation | Answer |
|---|---|
| Known pattern: hot 30 days, rarely read after, keep 7 years | **Lifecycle**: Standard → Standard-IA (30 d) → Glacier Flexible/Deep Archive; expire at 7 yr |
| Unknown/changing access per object, larger objects | **S3 Intelligent-Tiering** (no retrieval fees) |
| Billions of tiny objects (< 128 KB) | Stay in Standard or aggregate objects (tar/Parquet) — IT/IA don't help |
| Rarely accessed but needs millisecond retrieval | **Glacier Instant Retrieval** |
| Compliance archive, restore in 12–48 h OK | **Glacier Deep Archive** |
| Reproducible data (thumbnails, derived) | **One Zone-IA** |
| EBS performance decoupled from size | **gp3** |
| Old snapshots retained for compliance | **EBS Snapshots Archive** |
| NFS with cold files | **EFS lifecycle → IA / Archive** |

### 4.8 Database cost choices

| Situation | Answer |
|---|---|
| Aurora I/O ≥ 25% of Aurora bill | **Aurora I/O-Optimized** |
| Aurora I/O < 25% | **Aurora Standard** |
| Intermittent/unpredictable relational load, dev DBs idle at night | **Aurora Serverless v2** (scale to 0 with auto-pause) |
| DynamoDB spiky/unknown, utilisation of provisioned capacity < ~29% | **On-demand** |
| DynamoDB steady, predictable | **Provisioned + auto scaling + reserved capacity** |
| Large DynamoDB table, mostly cold data | **Standard-IA table class** |
| Same hot items read repeatedly | **ElastiCache / DAX** before more replicas |
| Complex reporting queries hurting the primary | **Read replica** (or zero-ETL to Redshift) |
| SQL Server Enterprise features unused | **Downgrade to Standard**; Optimize CPU; consider Babelfish |

---

## 5. Worked cost scenarios (with numbers)

> Illustrative us-east-1 list prices; the method matters more than the cents.

### 5.1 NAT gateway → gateway endpoints

A data platform in 3 AZs moves **60 TB/month from S3** and **10 TB/month from DynamoDB** into private subnets via NAT gateways.

| Item | Via NAT | With gateway endpoints |
|---|---|---|
| NAT processing: 70,000 GB × $0.045 | **$3,150/month** | $0 |
| Gateway endpoint charges | — | $0 |
| NAT hourly (3 × $0.045 × 730) | $98.55 | $98.55 (still needed for internet) |
| **Saving** | | **$3,150/month ≈ $37,800/year** |

Bonus: S3 and DynamoDB traffic stays on the AWS network and can be restricted with endpoint policies and `aws:SourceVpce` bucket policies.

### 5.2 Inter-AZ replication — self-managed Kafka vs Amazon MSK

Producers write **60 TB/month**, replication factor 3 across 3 AZs, consumers read 60 TB/month.

- Self-managed Kafka on EC2: each byte replicated to 2 other AZs → **120 TB cross-AZ** × $0.02/GB (out + in) = **$2,400/month**. Consumers reading from leaders: ~2/3 cross-AZ → 40 TB × $0.02 = **$800/month**.
- **Amazon MSK does not charge for data transfer between brokers within a cluster** → the $2,400 disappears. Enabling **rack-aware follower fetching** (consumers read from a replica in their own AZ) removes most of the $800.
- Lesson: managed services sometimes eliminate whole categories of data-transfer cost — read the pricing page of the managed alternative before rejecting it as "more expensive".

### 5.3 Sizing a Savings Plan commitment

After rightsizing, the org's On-Demand-equivalent compute spend is **trough $60/h, average $85/h, peak $140/h**. Assume a Compute SP discount of ~28% (illustrative 1-yr, No Upfront).

- **Commit to the trough:** commitment = $60 × 0.72 = **$43.20/h**. Every hour is fully utilised. Saving = $16.80/h × 730 ≈ **$12,264/month**.
- **Commit to the average ($61.20/h):** in an hour where usage is only $60 OD-equivalent, it consumes $43.20 of commitment — **$18 of commitment is wasted** and you paid $61.20 for $60 of On-Demand usage — worse than no plan for that hour.
- **Practice:** buy the trough now, review **utilisation (target ~100%)** and **coverage** monthly, add **tranches** as the baseline grows. Use the Savings Plans Purchase Analyzer to model "what if I buy another $5/h".

### 5.4 Aurora I/O-Optimized decision

Monthly Aurora Standard bill: instances **$4,000**, storage 2,000 GB × $0.10 = **$200**, I/O 10.5 billion × $0.20/M = **$2,100**. Total **$6,300**; I/O share = 2,100 / 6,300 = **33% (≥ 25%)**.

| | Standard | I/O-Optimized |
|---|---|---|
| Instances | $4,000 | $4,000 × 1.30 = $5,200 |
| Storage | $200 | 2,000 × $0.225 = $450 |
| I/O | $2,100 | $0 |
| **Total** | **$6,300** | **$5,650** (−$650/month, ~10%) |

Counter-case: I/O = $800 → total $5,000, share 16% → I/O-Optimized would still cost $5,650 → **stay Standard**. Algebra: I/O-Optimized wins when `I/O > 0.3 × instances + 1.25 × storage` — which is why AWS's rule of thumb is ~25% of total Aurora spend.

### 5.5 Serverless vs always-on break-even

API backend: Lambda 512 MB, 200 ms average, x86, behind an **HTTP API**.

- Per request: 0.5 GB × 0.2 s = 0.1 GB-s × $0.0000166667 = $0.00000167 + request $0.0000002 + HTTP API $0.000001 ≈ **$2.87 per million requests**.
- Always-on alternative: 2 × m6g.large (for HA) at ~$0.077/h ≈ $112/month + ALB (~$16/month + LCUs ≈ $10) ≈ **$139/month**.
- **Break-even ≈ 139 / 2.87 ≈ 48 million requests/month** (~18 requests/second average).
  - At 5 M/month: Lambda ≈ $14 vs EC2 $139 → **serverless ~10× cheaper**.
  - At 300 M/month: Lambda ≈ $861 vs EC2 (scaled to ~4–6 instances) ≈ $300 → **EC2/Fargate cheaper** — still weigh operational overhead.
- If the same API used a **REST API** ($3.50/M), the per-million cost jumps to ~$5.37 and break-even roughly halves — choose HTTP API unless REST-only features are required.

### 5.6 DynamoDB on-demand vs provisioned

Table averages **200 writes/s** (1 KB items), with short daily peaks to **1,000 writes/s**.

- **On-demand:** 200 × 2,592,000 s (30 days) = 518.4 M writes × $0.625/M ≈ **$324/month**.
- **Provisioned for peak (1,000 WCU, no auto scaling):** 1,000 × 730 × $0.00065 ≈ **$475/month** (utilisation 20% < 29% ⇒ worse than on-demand).
- **Provisioned + auto scaling** (target 70%, average ~290 WCU): ≈ 290 × 730 × $0.00065 ≈ **$138/month** — cheapest, *if* peaks ramp gradually enough for auto scaling (plus burst capacity) to avoid throttling.
- Add **1-yr reserved capacity** for the 200 WCU baseline and the steady-state cost falls further.
- Decision: predictable ramps → provisioned + auto scaling (+ reserved); sudden unpredictable spikes or brand-new table → on-demand.

### 5.7 Scheduling non-production

40 × m6i.xlarge dev instances at ~$0.192/h.

- 24×7: 40 × $0.192 × 730 ≈ **$5,606/month**.
- Office hours (12 h × 5 days ≈ 260 h/month): 40 × $0.192 × 260 ≈ **$1,997/month** → **saving ≈ $3,609/month (64%)**.
- A 1-yr SP (~30%) on 24×7 instances would only save ~$1,680 — **scheduling beats committing** for non-prod, and you should *not* commit for hours that are scheduled off.

### 5.8 gp2 → gp3 migration

500 × 1 TiB gp2 volumes (≈ 512,000 GB) at $0.10 = **$51,200/month**. gp3 at $0.08 = **$40,960/month** → **$10,240/month saved**. A 1 TiB gp2 volume has ~3,000 baseline IOPS — the same as gp3's included baseline — so no extra IOPS charge. Done online with Elastic Volumes. (A 5 TiB gp2 volume gets 15,000 IOPS; on gp3 you'd pay for 12,000 extra provisioned IOPS — usually still cheaper, but calculate.)

### 5.9 Internet delivery via CloudFront

Serving **200 TB/month** of downloads directly from S3 pays internet egress at S3's tiered rates (≈ $0.09 falling to $0.05/GB across tiers; roughly **$13,800**). Through CloudFront: origin fetch S3→CloudFront is **free**, CloudFront's North America per-GB rates are lower at each band (≈ $0.085 falling to $0.04/GB; roughly **$12,000**), the cache cuts S3 GET requests, and committed-use private pricing can lower it further. You also gain latency improvements and AWS Shield Standard. Global Accelerator or S3 Transfer Acceleration would **add** per-GB fees.

### 5.10 CloudWatch Logs class + retention

Application debug logs ingest **20 TB/month**, queried only during incidents.

- Standard ingestion 20,000 GB × $0.50 = **$10,000/month**; Infrequent Access 20,000 × $0.25 = **$5,000/month**.
- Storage with the default **Never expire**: after 12 months, hundreds of TB of archived logs at $0.03/GB-month (≈ **$7,000+/month and growing**). Set **30-day retention** and export older logs to S3 (lifecycle to Glacier) if compliance needs them.
- Caveat: IA can't feed **metric filters or subscription filters** — keep alerting logs in Standard.

---

## 6. Exam keyword → answer cheat list

| Keyword / phrase in the stem | Likely answer |
|---|---|
| "Steady-state, flexible across instance families/Regions, includes Fargate/Lambda" | **Compute Savings Plan** |
| "Specific instance family in one Region, maximum savings" | **EC2 Instance Savings Plan** (3-yr All Upfront for max) |
| "May need to sell unused reservation later" | **Standard RI** + RI Marketplace |
| "Change instance family during the term" with RIs | **Convertible RI** |
| "Guarantee capacity in an AZ for DR / event" | **On-Demand Capacity Reservation** (+ SP for discount) |
| "Capacity reserved and shared with other accounts" | **ODCR shared via AWS RAM** |
| "Fault-tolerant, can be interrupted, flexible, minimize cost" | **Spot** (price-capacity-optimized, diversified) |
| "Minimize Spot interruptions for long jobs" | **capacity-optimized** (+ checkpointing) |
| "Which Region/AZ is most likely to fulfil a Spot request" | **Spot placement score** |
| "Earlier signal than the 2-minute notice" | **EC2 rebalance recommendation** / Capacity Rebalancing |
| "ECS tasks, interruptible, cheapest" | **Fargate Spot** capacity provider |
| "Existing per-core licences, licence compliance" | **Dedicated Hosts + License Manager** |
| "Many DB engines, migrate engines, 1-yr commitment" | **Database Savings Plan** |
| "Accounts shouldn't receive/share RI discounts" | **Turn off RI/SP sharing** for those accounts (management account) |
| "Share commitments only within a subsidiary's accounts" | **Restricted group sharing** (Cost Categories) |
| "Combine bills, volume discounts across accounts" | **Organizations consolidated billing** |
| "Stop provisioning automatically when budget exceeded" | **AWS Budgets action applying SCP/IAM policy** |
| "Automatically stop instances when budget exceeded" | **Budgets action — stop EC2/RDS** |
| "Unexpected spend spike, ML, root cause" | **Cost Anomaly Detection** |
| "Detailed hourly, resource-level billing data, query with SQL" | **CUR 2.0 (Data Exports) + Athena** |
| "Executive cost dashboards across the org" | **Cloud Intelligence Dashboards (CUDOS) on Quick Sight** |
| "Map costs to business units, split shared costs" | **Cost Categories + split charges** |
| "Custom rates/markup for internal or reseller billing" | **AWS Billing Conductor** |
| "Prioritised, de-duplicated savings across the org" | **Cost Optimization Hub** |
| "Rightsize EC2/EBS/Lambda/Fargate" | **Compute Optimizer** |
| "Prevent creation of resources without CostCenter tag" | **SCP with `aws:RequestTag` condition** |
| "Standardise tag values/capitalisation" | **Tag policies** |
| "Tags not showing in Cost Explorer" | **Activate cost allocation tags** in the management account (wait up to 24 h) |
| "NAT gateway data processing charges high, traffic to S3/DynamoDB" | **Gateway VPC endpoints** |
| "High-volume VPC-to-VPC traffic, few VPCs, lowest cost" | **VPC peering** (not TGW) |
| "Reduce internet data transfer cost for global users" | **CloudFront** |
| "Large recurring data transfer to on-premises" | **Direct Connect** |
| "I/O charges are > 25% of Aurora bill" | **Aurora I/O-Optimized** |
| "Unpredictable relational DB load / idle dev DBs" | **Aurora Serverless v2** |
| "Unpredictable DynamoDB traffic" | **On-demand capacity** |
| "Steady DynamoDB throughput for years" | **Provisioned + reserved capacity** |
| "Infrequently queried logs, cheaper ingestion" | **CloudWatch Logs Infrequent Access class** |
| "SSE-KMS request costs on S3" | **S3 Bucket Keys** |
| "Cheapest API Gateway option, simple proxy to Lambda" | **HTTP API** |
| "Unknown access patterns on S3" | **S3 Intelligent-Tiering** |
| "Cheapest archival, restore within 48 h" | **S3 Glacier Deep Archive** |
| "EBS cost reduction without performance loss" | **gp2 → gp3** |
| "Dev/test environments idle nights and weekends" | **Instance Scheduler on AWS** / stop schedules |
| "Better price performance for compute" | **Graviton** |
| "Least operational overhead AND cost-effective" | Managed/serverless option, not DIY on EC2 |

---

## 7. Traps & distractors

1. **"Buy RIs/SPs to save cost" before rightsizing** — the best answer rightsizes/schedules first, then commits to the new baseline.
2. **EC2 Instance SP or RIs for Fargate/Lambda** — only **Compute Savings Plans** discount Fargate and Lambda.
3. **Regional RI for capacity** — regional RIs and Savings Plans **never reserve capacity**. Zonal RIs or ODCRs do.
4. **Selling Convertible RIs or RDS RIs on the Marketplace** — impossible; only EC2 Standard RIs.
5. **"Cancel the Savings Plan"** — SPs can't be cancelled (except the ≤ $100/h, 7-day, same-month return).
6. **Spot for a stateful single-instance DB or "must not be interrupted"** — wrong regardless of savings.
7. **lowest-price Spot allocation** — highest interruption risk; AWS recommends **price-capacity-optimized**.
8. **Spot blocks / defined duration** — retired; any answer relying on them is wrong.
9. **Tag policies to prevent untagged resources** — tag policies enforce *values/format* on tagging operations; **SCPs with `aws:RequestTag`** prevent untagged creation.
10. **Expecting tags to show retroactively** — tags only appear after activation (management account) and from then on.
11. **Cost Categories to apply markups** — no; **Billing Conductor**.
12. **Billing Conductor changes the AWS invoice** — no; it's pro forma only.
13. **SCPs to stop RI sharing** — SCPs don't affect billing; use **Billing preferences** sharing settings.
14. **CloudWatch billing alarm + custom Lambda to stop instances** — works, but higher overhead than **Budgets actions**.
15. **Interface endpoint for S3 to cut NAT cost** — works, but the **gateway endpoint is free**; choose gateway unless on-premises/peered-VPC access to S3 via private IP is required (gateway endpoints aren't reachable from on-prem or across peering/TGW).
16. **Centralised NAT via TGW "to save money"** — TGW adds ~$0.02/GB; only cheaper for many low-volume VPCs.
17. **Transit Gateway for two high-volume VPCs** — VPC peering is cheaper (no processing, free same-AZ).
18. **S3 Transfer Acceleration or Global Accelerator to reduce cost** — both *add* cost; they're performance features.
19. **Removing Multi-AZ in production to save inter-AZ charges** — violates the reliability requirement.
20. **S3 Intelligent-Tiering for tiny objects** — objects < 128 KB aren't auto-tiered; IA classes bill a 128 KB minimum object size and 30-day minimum duration.
21. **Lifecycle to Glacier for data accessed weekly** — retrieval fees and minimum durations make it more expensive.
22. **Changing an existing log group to Infrequent Access** — not possible; create a new log group. And IA can't use metric/subscription filters.
23. **DynamoDB reserved capacity for on-demand tables or Standard-IA tables** — not supported.
24. **Aurora I/O-Optimized "always cheaper"** — only when I/O ≥ ~25% of spend; storage costs 2.25× and instances ~30% more.
25. **"Stop the RDS instance indefinitely"** — RDS/Aurora auto-start after 7 days; use snapshot + delete, or Aurora Serverless v2 auto-pause for long idle periods.
26. **Dedicated Instances for BYOL per-socket licences** — need Dedicated Hosts.
27. **Savings Plans covering the Dedicated Instance $2/h Region fee, EKS control plane, data transfer, EBS** — they don't.
28. **Cost Explorer for "most detailed" data** — CUR 2.0 is the most granular.
29. **Trusted Advisor full cost checks on Basic/Developer support** — not available.
30. **REST API "because it's the default"** when the stem stresses cost and needs only Lambda proxy + JWT auth — HTTP API.

---

## 8. Professional architect focus

- **Cost is an architectural property, not a finance afterthought.** Make cost a non-functional requirement with a target (e.g., cost per order ≤ $0.002). Track **unit economics** from CUR joined with business KPIs — total spend rising is fine if cost per transaction falls.
- **Account structure is your allocation foundation.** One workload/environment per account gives 100% attributable cost; tags then provide the finer split. Shared platforms (networking, EKS, data lakes) need an explicit **split-charge policy** agreed with finance.
- **Own the commitment portfolio centrally.** A FinOps team (or CCoE) buys SPs/RIs in tranches, monitors utilisation/coverage weekly, aligns expiries, and decides how savings are shown to BUs (amortised vs on-demand-equivalent). Don't let 300 teams buy their own RIs.
- **Sequence:** *visibility → usage optimisation → rate optimisation → automation/governance.* Each step funds the next.
- **Beware "optimisation debt":** a 3-year EC2 Instance SP on m5 can block a Graviton migration that would save more. Use Compute SPs where roadmap uncertainty exists; prefer 1-year terms when a re-platform (containers, serverless) is planned within 18 months.
- **Draw data transfer on the architecture diagram.** Label every arrow with $/GB: NAT, TGW, inter-AZ, inter-Region, egress. Most surprise bills come from data movement, not compute.
- **Resilience vs cost is a business decision.** Present options: Multi-AZ vs single-AZ, pilot light vs warm standby, replication scope. Quantify the cost of downtime vs the cost of redundancy. Never silently remove resilience to hit a cost target.
- **Guardrails over gatekeeping.** Budgets actions, SCPs that block expensive instance families or unused Regions in sandboxes, Service Catalog products with pre-approved sizes — these let teams move fast within limits.
- **Anomaly response runbook.** Who receives Cost Anomaly Detection alerts, how fast they respond, and how compromised credentials (crypto-mining) are contained — cost alerts are also security signals.
- **Review cadence:** monthly cost review per workload (Cost Optimization Hub + Compute Optimizer), quarterly commitment review, annual Well-Architected cost review; adopt new price-performance features (Graviton generations, gp3, I/O-Optimized, Logs IA, Database SPs).
- **Negotiate at scale.** Large customers can use private pricing agreements and CloudFront private pricing — mention to stakeholders, though exam answers focus on self-service levers.
- **Stakeholder language:** CFOs care about forecast accuracy and commitments (multi-year liabilities); engineering cares about not being blocked. FinOps translates: forecast with Cost Explorer (80% prediction interval), explain variance, and report savings realised.
- **Emerging / SAP-C03 preview (not core for SAP-C02):** generative-AI cost management (Amazon Bedrock on-demand vs provisioned throughput vs batch inference, prompt caching, model distillation, Bedrock Guardrails cost per text unit), and FinOps for AI agents (Bedrock AgentCore usage-based pricing). Expect "cost per inference" thinking to appear in SAP-C03.

---

## 9. Skills checklist

- [ ] I can state the definition and five areas of the Well-Architected Cost Optimization pillar.
- [ ] I can choose between Compute SP, EC2 Instance SP, Database SP, SageMaker AI SP, Standard RI and Convertible RI, and say what each covers (incl. Fargate and Lambda).
- [ ] I can explain regional vs zonal RIs, instance size flexibility and normalization factors, and which platforms lack size flexibility.
- [ ] I know the RI Marketplace rules (EC2 Standard only, ≥ 30 days active, ≥ 1 month remaining, 12% fee).
- [ ] I can design capacity assurance with ODCR + Savings Plans and share it via RAM.
- [ ] I can configure a Spot fleet/ASG with price-capacity-optimized, diversification, Capacity Rebalancing, and handle the 2-minute notice.
- [ ] I know when Dedicated Hosts are required for licensing and how License Manager helps.
- [ ] I can explain consolidated billing volume aggregation, RI/SP application order, turning off sharing, and prioritized vs restricted group sharing.
- [ ] I can pick the right tool among Cost Explorer, CUR 2.0/Data Exports, Budgets (+ actions), Cost Anomaly Detection, Cost Categories, Billing Conductor, Pricing Calculator, Cost Optimization Hub, Compute Optimizer and Trusted Advisor.
- [ ] I can design tag governance: activation, tag policies, SCP `aws:RequestTag`, Config rules.
- [ ] I can explain showback vs chargeback and when Billing Conductor is needed.
- [ ] I can calculate NAT vs gateway endpoint savings, inter-AZ cost, and TGW vs peering cost.
- [ ] I can apply the Aurora I/O-Optimized 25% rule and the DynamoDB ~29% utilisation break-even.
- [ ] I can estimate a serverless vs always-on break-even and choose HTTP API vs REST API.
- [ ] I can design S3 lifecycle/Intelligent-Tiering policies respecting minimum durations and the 128 KB rule.
- [ ] I can reduce logging cost with the Logs IA class, retention policies and S3 export.
- [ ] I can identify licence cost levers (BYOL, edition downgrade, Optimize CPUs, open-source migration).

---

## 10. Practice questions

> Original SAP-C02-style questions written for this guide — not real exam questions.

**Q1.** A retail company runs 120 AWS accounts in AWS Organizations. Its compute footprint has been rightsized and has a stable 24×7 baseline equivalent to about $90/hour of On-Demand spend, currently split across m5, c5 and r5 EC2 instances in us-east-1 and eu-west-1. Over the next 18 months, the platform team plans to migrate most services to Graviton-based instances, move several microservices to Amazon ECS on AWS Fargate, and re-platform event-processing jobs to AWS Lambda. The CFO has approved a 3-year commitment but does not want any upfront payment. Which purchasing approach provides the GREATEST savings while staying aligned with the roadmap?

- A. Purchase 3-year No Upfront EC2 Instance Savings Plans for the m5, c5 and r5 families in each Region, sized to the current baseline.
- B. Purchase 3-year No Upfront Compute Savings Plans in a central account, sized to the post-rightsizing baseline, with RI/SP discount sharing enabled across the organization.
- C. Purchase 3-year No Upfront Convertible Reserved Instances for the current instances and exchange them for Graviton instance types as the migration proceeds.
- D. Purchase 3-year All Upfront Standard Reserved Instances and sell them in the Reserved Instance Marketplace as workloads move to Fargate and Lambda.

**Q2.** A media analytics company runs Amazon EMR and containerized ETL jobs in private subnets across three Availability Zones. Each AZ has its own NAT gateway. The monthly bill shows NAT gateway data processing charges of more than $9,000. VPC Flow Logs analysis shows that about 85% of NAT traffic goes to Amazon S3 buckets and Amazon DynamoDB tables in the same Region, and most of the remainder is Amazon ECR image pulls. The security team requires that traffic to AWS services must not traverse the internet. Which combination of actions will reduce costs the MOST with the LEAST operational overhead? **(Select TWO.)**

- A. Create S3 and DynamoDB gateway VPC endpoints and associate them with the private subnet route tables in all three AZs.
- B. Create an S3 interface VPC endpoint in each AZ and update applications to use the endpoint-specific DNS names.
- C. Create interface VPC endpoints for ECR (`ecr.api` and `ecr.dkr`), relying on the S3 gateway endpoint for image layer downloads.
- D. Replace the three NAT gateways with a single NAT gateway in one AZ and route all private subnets to it.
- E. Replace the NAT gateways with self-managed NAT instances on Graviton-based EC2 instances.

**Q3.** A holding company owns four subsidiaries. Each subsidiary has between 10 and 40 AWS accounts, all within a single AWS Organization so that the group benefits from consolidated volume pricing and shared Savings Plans. The group finance team must send each subsidiary a monthly invoice that applies a 6% internal platform markup on all AWS usage, adds a fixed monthly charge for shared security tooling, and does not reveal the group's negotiated discounts. Subsidiary finance teams must be able to analyze their own costs at these internal rates in Cost Explorer. Which solution meets these requirements with the LEAST effort?

- A. Create a Cost Category per subsidiary with split-charge rules to allocate the security tooling cost, and share Cost Explorer access with each subsidiary.
- B. Configure AWS Billing Conductor with a billing group per subsidiary, a pricing plan with a 6% markup pricing rule, and a recurring custom line item for the security tooling charge.
- C. Export CUR 2.0 to Amazon S3, build Athena queries that apply the 6% markup and add the fixed charge, and publish Amazon Quick Sight dashboards to each subsidiary.
- D. Move each subsidiary into its own AWS Organization and configure billing transfer so that each subsidiary pays AWS directly.

**Q4.** A software company gives each development team a sandbox account under a Sandbox OU. Finance has three requirements: (1) every new EC2 instance, EBS volume, and RDS DB instance must carry a `CostCenter` tag at creation; (2) when a sandbox account's forecasted monthly spend exceeds $2,000, the account must automatically be prevented from launching new resources until the next month; and (3) the FinOps team must be alerted within a day about unusual spend patterns in any account, with root-cause information, without having to maintain thresholds for every service. Which combination of actions meets these requirements with the LEAST operational overhead? **(Select THREE.)**

- A. Attach an SCP to the Sandbox OU that denies `ec2:RunInstances`, `ec2:CreateVolume`, and `rds:CreateDBInstance` when the `aws:RequestTag/CostCenter` condition key is null.
- B. Create a tag policy for the Sandbox OU that defines `CostCenter` as a required key and enforce it for EC2 and RDS resource types, which blocks creation of untagged resources through all APIs.
- C. Create an AWS Budgets cost budget for each sandbox account with a forecasted-spend threshold of $2,000 and an automatic budget action that applies a deny-provisioning SCP to that account.
- D. Create an Amazon CloudWatch billing alarm in each sandbox account that invokes a Lambda function to detach the developers' IAM policies when estimated charges exceed $2,000.
- E. Enable AWS Cost Anomaly Detection with an AWS services monitor and a linked-account monitor, and subscribe the FinOps team to individual alerts through an Amazon SNS topic.
- F. Enable AWS Trusted Advisor cost optimization checks in every account and configure weekly email reports to the FinOps team.

**Q5.** A visual-effects studio renders frames on EC2. Each render job runs 2–6 hours, checkpoints progress to Amazon S3 every 10 minutes, and can resume on any instance with at least 16 vCPUs and 64 GiB of memory. Deadlines are measured in days, not hours. The current fleet uses On-Demand c5.4xlarge instances in a single AZ and costs $180,000 per month. Previous experiments with Spot Instances using a single instance type had frequent interruptions that wasted render time. Which solution will reduce cost the MOST while minimizing wasted work?

- A. Use an EC2 Fleet with the lowest-price Spot allocation strategy, a single instance type (c5.4xlarge), and capacity spread across all AZs.
- B. Use an Auto Scaling group with attribute-based instance type selection (≥ 16 vCPUs, ≥ 64 GiB), Spot with the price-capacity-optimized allocation strategy across all AZs, Capacity Rebalancing enabled, and resume from the latest S3 checkpoint after interruption.
- C. Purchase a 1-year Compute Savings Plan for the full $180,000 monthly On-Demand spend and keep the On-Demand fleet in a single AZ.
- D. Create On-Demand Capacity Reservations for c5.4xlarge in one AZ and run Spot Instances inside the reservations to avoid interruptions.

**Q6.** A fintech company runs an Aurora PostgreSQL cluster (Aurora Standard configuration) for its ledger. Last month's Aurora charges were: DB instances $9,000, storage (3 TB) $300, and I/O requests $4,200. Workload growth is expected to increase I/O further. The CTO asks for the most cost-effective change that does not require application changes or reduce availability. What should the solutions architect recommend?

- A. Add two Aurora Replicas and direct read traffic to the reader endpoint to reduce I/O on the writer.
- B. Switch the cluster's storage configuration to Aurora I/O-Optimized.
- C. Migrate the cluster to Aurora Serverless v2 with the Aurora Standard configuration.
- D. Purchase Reserved DB instances for the existing Aurora Standard instances and keep the storage configuration unchanged.

**Q7.** An e-commerce company has two Amazon DynamoDB tables in provisioned capacity mode. Table `Sessions` is used by a marketing microsite whose traffic jumps from near zero to 30,000 writes per second within seconds when campaigns launch at unannounced times; average utilization of its provisioned capacity is 9%, and users still see throttling at campaign start. Table `Orders` has had a steady 4,000 WCU and 12,000 RCU consumed, 24×7, for the past two years, and the business expects this to continue for at least three more years. Which actions will MOST reduce cost while meeting performance needs? **(Select TWO.)**

- A. Switch the `Sessions` table to on-demand capacity mode.
- B. Keep the `Sessions` table in provisioned mode, enable auto scaling with a 70% target utilization, and add DynamoDB Accelerator (DAX).
- C. Purchase 3-year DynamoDB reserved capacity for the `Orders` table baseline in its Region.
- D. Change the `Orders` table to the DynamoDB Standard-Infrequent Access table class.
- E. Switch the `Orders` table to on-demand capacity mode and cover it with a Database Savings Plan.

**Q8.** A video-learning platform serves 350 TB of course videos per month directly from an Amazon S3 bucket in us-east-1 to learners worldwide using presigned URLs. Data transfer out is now the largest line item on the bill, and learners in Asia report slow start times. The company wants to reduce data transfer costs and improve performance while keeping content private. Which solution meets these requirements MOST cost-effectively?

- A. Enable S3 Transfer Acceleration on the bucket and generate presigned URLs that use the accelerate endpoint.
- B. Use S3 Cross-Region Replication to copy the videos to buckets in ap-southeast-1 and eu-west-1, and use Route 53 latency-based routing to direct learners to the nearest bucket.
- C. Put an Amazon CloudFront distribution in front of the S3 bucket with origin access control, and serve content with CloudFront signed URLs or signed cookies.
- D. Place AWS Global Accelerator in front of an Application Load Balancer that proxies requests to S3 through a fleet of EC2 instances.

**Q9.** A manufacturing group uses a single AWS Organization with 200 accounts. One subsidiary, which operates three accounts (A, B, and C), has purchased its own EC2 Reserved Instances and Compute Savings Plans from account A. The subsidiary's finance director requires that these commitment discounts benefit only accounts A, B, and C, and must never be applied to other accounts in the organization, even if part of the commitment is unused in some hours. All other accounts should continue to share commitments organization-wide. What should the solutions architect do?

- A. In the management account's billing preferences, deactivate RI and Savings Plans discount sharing for accounts A, B, and C.
- B. Create a Cost Category that groups accounts A, B, and C, and configure restricted group sharing for RI and Savings Plans discounts using that Cost Category.
- C. Attach an SCP to accounts outside the subsidiary that denies the use of Reserved Instances and Savings Plans owned by account A.
- D. Create a Cost Category that groups accounts A, B, and C, and configure prioritized group sharing for RI and Savings Plans discounts using that Cost Category.

**Q10.** A SaaS company sends all application logs from 600 Lambda functions and 200 ECS services to Amazon CloudWatch Logs. Logging is the third-largest cost on its bill. Analysis shows: (1) verbose debug logs are about 70% of ingested volume and are queried only during incident investigations using CloudWatch Logs Insights; (2) error and audit logs feed metric filters that drive alarms; (3) no log group has a retention setting configured. Compliance requires 1 year of retention for audit logs only. Which actions will reduce logging cost the MOST while preserving required functionality? **(Select TWO.)**

- A. Change the log class of the existing debug log groups from Standard to Infrequent Access.
- B. Send debug logs to new log groups created with the Infrequent Access log class, and keep error and audit logs in Standard log groups.
- C. Move all logs, including error and audit logs, to Infrequent Access log groups and recreate the metric filters on those log groups.
- D. Set retention policies on all log groups (for example, 14–30 days for debug and error logs and 1 year for audit logs).
- E. Enable CloudWatch Logs Live Tail on all debug log groups to reduce the need for Logs Insights queries.

### Answers & explanations

<details><summary>Show answer — Q1</summary>

**Correct: B.**

- **Why B:** Compute Savings Plans apply regardless of instance family, size, Region, and OS, and also apply to **Fargate and Lambda**. That fits the planned move to Graviton, Fargate and Lambda. A 3-year No Upfront term meets the CFO's constraint. Buying centrally with sharing enabled lets the benefit follow usage across the 120 accounts. Sizing to the rightsized baseline avoids unused commitment.
- **A:** EC2 Instance SPs are locked to one family in one Region (m5, c5, r5). They stop applying when workloads move to Graviton families, Fargate, or Lambda.
- **C:** Convertible RIs can be exchanged for Graviton EC2 types, but they **never cover Fargate or Lambda**. Exchanges also add operational effort.
- **D:** All Upfront breaks the no-upfront constraint. Marketplace sales carry a 12% fee and a $50,000 lifetime selling limit, and depend on finding buyers. It's a poor plan for a known migration.

References: https://docs.aws.amazon.com/savingsplans/latest/userguide/plan-types.html · https://aws.amazon.com/savingsplans/faq/
</details>

<details><summary>Show answer — Q2</summary>

**Correct: A, C.**

- **A:** S3 and DynamoDB **gateway endpoints have no hourly or per-GB charge**. They remove about 85% of NAT processing and keep traffic off the internet. They only need route-table associations, with no application changes.
- **C:** ECR API and Docker registry calls need **interface endpoints** (`ecr.api`, `ecr.dkr`). Their ~$0.01/GB processing is far below NAT's ~$0.045/GB. Image layers are served from S3, which the gateway endpoint from A already handles.
- **B:** An S3 interface endpoint works, but it adds hourly and per-GB charges where the gateway endpoint is free. It also needs DNS or application changes, unless private DNS is configured.
- **D:** A single NAT gateway adds cross-AZ data transfer charges and creates a single-AZ point of failure. It still pays NAT processing.
- **E:** NAT instances add patching, scaling and HA work, and traffic still goes over the internet path.

References: https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html · https://docs.aws.amazon.com/vpc/latest/privatelink/gateway-endpoints.html · https://aws.amazon.com/privatelink/pricing/
</details>

<details><summary>Show answer — Q3</summary>

**Correct: B.**

- **Why B:** AWS Billing Conductor builds a **pro forma** view per billing group. Pricing rules can apply a **markup**, and **custom line items** add recurring flat charges. Accounts in a billing group see the pro forma costs in Cost Explorer and on their bills, not the negotiated rates. The real AWS invoice and the sharing of SPs and volume tiers stay unchanged.
- **A:** Cost Categories group and split costs but **can't change rates**. Subsidiaries would see actual discounted costs.
- **C:** This works but needs significant custom build and upkeep. Subsidiaries also couldn't use Cost Explorer at internal rates.
- **D:** Separate organizations lose shared volume pricing and commitment sharing, and still don't apply a markup.

Reference: https://docs.aws.amazon.com/billingconductor/latest/userguide/what-is-billingconductor.html
</details>

<details><summary>Show answer — Q4</summary>

**Correct: A, C, E.**

- **A:** An SCP with a null-check on `aws:RequestTag/CostCenter` **denies creation requests that lack the tag**. This is the standard pattern for requiring tags at creation.
- **C:** AWS Budgets supports **forecasted** thresholds and **budget actions**. From the management account, an action can automatically **apply an SCP** to the account to block new provisioning, with no custom code.
- **E:** Cost Anomaly Detection uses ML, so no per-service thresholds are needed. It runs about three times a day and gives root-cause analysis by service, account, Region and usage type. Individual alerts can go through SNS.
- **B:** Tag policies standardize tag keys and values and can block **non-compliant tagging operations**. They **don't stop resources being created without the tag** through native APIs. Required-tag validation applies to supported IaC tools, not to every API call.
- **D:** A billing alarm plus Lambda is custom code with higher overhead. Billing alarms also don't support forecasts the way Budgets does.
- **F:** Trusted Advisor finds idle or low-utilization resources. It doesn't detect anomalies, and full checks need Business Support or higher.

References: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-controls.html · https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html · https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_tag-policies.html
</details>

<details><summary>Show answer — Q5</summary>

**Correct: B.**

- **Why B:** Checkpointed jobs with flexible deadlines suit Spot, which offers up to 90% savings. **Attribute-based selection** across all AZs gives access to many capacity pools. **price-capacity-optimized** picks pools with the lowest interruption risk and then the lowest price. **Capacity Rebalancing** replaces at-risk instances early, and resuming from S3 checkpoints limits lost work to about 10 minutes.
- **A:** **lowest-price** has the highest interruption risk, and a single instance type keeps the pool count low. This repeats the earlier failure.
- **C:** A Compute SP saves far less than Spot (up to 66% vs up to 90%). Committing the full spend, including variable usage, risks unused commitment.
- **D:** Capacity Reservations are billed at On-Demand rates. Spot Instances can't run in an ODCR to avoid interruption, so this adds cost.

References: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-fleet-allocation-strategy.html · https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/rebalance-recommendations.html
</details>

<details><summary>Show answer — Q6</summary>

**Correct: B.**

- **Why B:** I/O is $4,200 of $13,500, which is **31%**, above AWS's **25%** guideline for I/O-Optimized. Estimated cost after switching: instances $9,000 × 1.3 = $11,700, plus storage 3,000 GB × $0.225 = $675, with no I/O charges. That totals about $12,375, saving about $1,125 a month, and the gap widens as I/O grows. Switching needs no application change. On non-NVMe instances there's no downtime, and you can switch back to Standard at any time.
- **A:** Replicas add whole instances, roughly +$6,000 or more. Aurora bills I/O at the cluster volume, so reads served by replicas still incur I/O. Total cost goes up.
- **C:** Serverless v2 on Standard still pays per-I/O. A steady, heavy ledger workload is usually cheaper on provisioned instances.
- **D:** RIs discount only the instance line item. The 31% I/O share stays and keeps growing. RIs can be combined with I/O-Optimized later, so D alone isn't the best answer.

References: https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.StorageReliability.html · https://aws.amazon.com/rds/aurora/pricing/
</details>

<details><summary>Show answer — Q7</summary>

**Correct: A, C.**

- **A:** `Sessions` has unpredictable spikes within seconds and 9% utilization, well below the ~29% break-even. On-demand bills per request and absorbs sudden traffic up to the table's limits without capacity planning. It removes both the waste and the throttling that auto scaling can't react to quickly enough.
- **C:** `Orders` has had steady, fully used provisioned throughput for years. **Reserved capacity** gives up to 77% off provisioned rates on a 3-year term. It's available for provisioned, single-Region, Standard-class tables.
- **B:** Auto scaling reacts over minutes, not seconds, and DAX caches reads, not writes. Both add cost without fixing write throttling at campaign start.
- **D:** Standard-IA lowers storage cost but raises the per-throughput price. It suits storage-dominated tables, not throughput-heavy ones, and it rules out reserved capacity.
- **E:** For a steady, high-utilization table, on-demand costs several times more than provisioned. Database SPs give only up to about 18% off on-demand throughput, on a 1-year term.

References: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/capacity-mode.html · https://aws.amazon.com/dynamodb/pricing/provisioned/
</details>

<details><summary>Show answer — Q8</summary>

**Correct: C.**

- **Why C:** CloudFront's per-GB delivery rates are lower than direct S3 internet egress, and **S3-to-CloudFront origin fetch is free**. Edge caching improves start times worldwide. **Origin access control** keeps the bucket private, and signed URLs or cookies control learner access.
- **A:** Transfer Acceleration **adds** a per-GB fee on top of egress. It speeds up long-distance transfers but doesn't cache, so cost goes up.
- **B:** Replication adds inter-Region transfer and duplicate storage, and you still pay internet egress from each bucket.
- **D:** Global Accelerator adds a per-GB premium. The EC2 proxy fleet adds compute and operational overhead, and still has no caching.

References: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html · https://aws.amazon.com/cloudfront/pricing/
</details>

<details><summary>Show answer — Q9</summary>

**Correct: B.**

- **Why B:** **Restricted group sharing** uses a Cost Category built on the Accounts dimension. Commitments benefit the owner account first, then **only** accounts in the same group, and **never** accounts outside it, even when some commitment goes unused. Other accounts keep organization-wide sharing.
- **A:** Turning off sharing for A, B and C means **both** the purchasing and receiving accounts must have sharing on for discounts to flow. So account A's commitments would no longer reach B and C.
- **C:** SCPs control API authorization. They have **no effect on how billing discounts are applied**.
- **D:** Prioritized group sharing serves the group first but **releases unused benefits to the rest of the organization**, which breaks the "never" requirement.

Reference: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/ri-turn-off.html
</details>

<details><summary>Show answer — Q10</summary>

**Correct: B, D.**

- **B:** The Infrequent Access log class has about **half the ingestion price** and supports CloudWatch Logs Insights, which is how the debug logs are used. The log class **can't be changed after a log group is created**, so the debug logs need new IA log groups. Error and audit logs must stay in Standard because **metric filters aren't supported on IA**.
- **D:** Log groups default to **never expire**, so storage grows without limit. Retention policies cut storage cost and still meet the 1-year audit requirement.
- **A:** You can't change the class of an existing log group.
- **C:** IA log groups don't support metric filters, so the alarms would break.
- **E:** Live Tail is an interactive tailing feature with its own charges. It doesn't reduce ingestion or storage costs, and it isn't supported on IA log groups.

References: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatch_Logs_Log_Classes.html · https://aws.amazon.com/cloudwatch/pricing/
</details>

---

## 11. References

**Frameworks & pricing fundamentals**
- Cost Optimization Pillar — AWS Well-Architected Framework: https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/welcome.html
- How AWS Pricing Works (whitepaper): https://docs.aws.amazon.com/whitepapers/latest/how-aws-pricing-works/abstract-and-introduction.html

**Purchasing options**
- What are Savings Plans?: https://docs.aws.amazon.com/savingsplans/latest/userguide/what-is-savings-plans.html
- Savings Plans types: https://docs.aws.amazon.com/savingsplans/latest/userguide/plan-types.html
- How Savings Plans apply to your usage: https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-applying.html
- Savings Plans FAQ: https://aws.amazon.com/savingsplans/faq/
- EC2 Reserved Instances: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-reserved-instances.html
- Types of Reserved Instances (offering classes): https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/reserved-instances-types.html
- How Reserved Instance discounts are applied: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/apply_ri.html
- Sell in the Reserved Instance Marketplace: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ri-market-general.html
- On-Demand Capacity Reservations: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-capacity-reservations.html
- Spot Instances: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html
- Spot Instance interruptions: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-interruptions.html
- EC2 instance rebalance recommendations: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/rebalance-recommendations.html
- Fleet allocation strategies: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-fleet-allocation-strategy.html
- Spot placement score: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-placement-score.html
- Dedicated Hosts: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/dedicated-hosts-overview.html
- DynamoDB provisioned pricing & reserved capacity: https://aws.amazon.com/dynamodb/pricing/provisioned/

**Billing, visibility & governance**
- Consolidated billing for AWS Organizations: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/consolidated-billing.html
- RI and Savings Plans discount sharing: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/ri-turn-off.html
- AWS Cost Explorer: https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html
- Forecasting with Cost Explorer: https://docs.aws.amazon.com/cost-management/latest/userguide/ce-forecast.html
- AWS Data Exports (CUR 2.0, FOCUS): https://docs.aws.amazon.com/cur/latest/userguide/what-is-data-exports.html
- Cloud Intelligence Dashboards on AWS: https://docs.aws.amazon.com/guidance/latest/cloud-intelligence-dashboards/getting-started.html
- AWS Budgets: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html
- Budget actions: https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-controls.html
- AWS Cost Anomaly Detection: https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html
- Cost allocation tags: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/cost-alloc-tags.html
- Activating user-defined cost allocation tags: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html
- Tag policies: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_tag-policies.html
- Enforce required tag keys in IaC: https://docs.aws.amazon.com/organizations/latest/userguide/enforce-required-tag-keys-iac.html
- AWS Cost Categories: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/manage-cost-categories.html
- AWS Billing Conductor: https://docs.aws.amazon.com/billingconductor/latest/userguide/what-is-billingconductor.html
- AWS Pricing Calculator: https://docs.aws.amazon.com/pricing-calculator/latest/userguide/what-is-pricing-calculator.html
- Cost Optimization Hub: https://docs.aws.amazon.com/cost-management/latest/userguide/cost-optimization-hub.html
- AWS Compute Optimizer: https://docs.aws.amazon.com/compute-optimizer/latest/ug/what-is-compute-optimizer.html
- AWS Trusted Advisor: https://docs.aws.amazon.com/awssupport/latest/user/trusted-advisor.html

**Architectural levers**
- Aurora storage configurations (I/O-Optimized vs Standard): https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.Overview.StorageReliability.html
- Amazon Aurora pricing: https://aws.amazon.com/rds/aurora/pricing/
- DynamoDB capacity modes: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/capacity-mode.html
- NAT gateway pricing guidance: https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-pricing.html
- Gateway endpoints: https://docs.aws.amazon.com/vpc/latest/privatelink/gateway-endpoints.html
- Amazon VPC pricing: https://aws.amazon.com/vpc/pricing/
- AWS PrivateLink pricing: https://aws.amazon.com/privatelink/pricing/
- AWS Transit Gateway pricing: https://aws.amazon.com/transit-gateway/pricing/
- CloudWatch Logs log classes: https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatch_Logs_Log_Classes.html
- Amazon CloudWatch pricing: https://aws.amazon.com/cloudwatch/pricing/
- S3 Bucket Keys: https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-key.html
- S3 Intelligent-Tiering: https://docs.aws.amazon.com/AmazonS3/latest/userguide/intelligent-tiering.html
- S3 Lifecycle: https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html
- EBS volume types: https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html
- Fargate capacity providers (Fargate Spot): https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-capacity-providers.html
- Choosing between HTTP APIs and REST APIs: https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-vs-rest.html
- AWS License Manager: https://docs.aws.amazon.com/license-manager/latest/userguide/license-manager.html
- Instance Scheduler on AWS: https://aws.amazon.com/solutions/implementations/instance-scheduler-on-aws/

---

> [← Previous](../15-Monitoring-Operations-and-Continuous-Improvement/15-Monitoring-Operations-and-Continuous-Improvement.md) · [Index](../00-README-Start-Here.md) · [Next →](../17-Practice-Papers/README.md)
