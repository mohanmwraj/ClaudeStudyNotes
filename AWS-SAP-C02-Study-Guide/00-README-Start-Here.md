# AWS Certified Solutions Architect – Professional (SAP-C02) — Complete Study Guide

> **Exam date:** 31 October 2026 · **Exam version:** SAP-C02 (last day to sit it is 16 Nov 2026; SAP-C03 starts 17 Nov 2026)
> **Pass mark:** 750 / 1000 · 75 questions (65 scored) · 180 minutes · no penalty for guessing

This folder is meant to be **the only material you need**. Each chapter goes from fundamentals to Professional-level depth, then lists exam keywords, traps and a skills checklist, and ends with practice questions that have full explanations and links to official AWS documentation. The practice-papers chapter has the **official AWS sample questions explained** plus **five original full-length-style papers** (100 questions) with detailed solutions.

> ⚠️ **About "previous question papers":** real SAP-C02 exam questions are covered by the AWS Certification NDA and are never published legitimately. Brain-dump sites are unreliable and using them violates the AWS certification agreement. This guide uses (1) AWS's **official sample questions**, explained in our own words, and (2) **original questions written to the official task statements**, in the same style and difficulty.

---

## Contents

| # | Chapter | Exam domains | Priority |
|---|---|---|---|
| 00 | **This file**: how to use the guide, study plan | — | — |
| 01 | [Exam Blueprint, Question Anatomy & Answering Strategy](01-Exam-Blueprint-and-Strategy.md) | All | ★★★ read first |
| 02 | [Multi-Account Strategy & Governance (Organizations, Control Tower, RAM)](02-Multi-Account-Governance.md) | D1 1.2/1.4/1.5 | ★★★ |
| 03 | [Identity, Access Management & Federation](03-Identity-and-Access-Management.md) | D1 1.2, D2 2.3, D3 3.2 | ★★★ |
| 04 | [Networking: Multi-VPC, Hybrid Connectivity & Network Security](04-Networking-VPC-and-Hybrid-Connectivity.md) | D1 1.1, D2 2.3 | ★★★ |
| 05 | [Edge: Route 53, CloudFront, Global Accelerator & Edge Compute](05-Edge-DNS-and-Content-Delivery.md) | D1 1.1/1.3, D2 2.4/2.5 | ★★☆ |
| 06 | [Security: Encryption, Secrets, Edge Protection, Detection & Compliance](06-Security-Data-Protection-and-Threat-Detection.md) | D1 1.2, D2 2.3, D3 3.2 | ★★★ |
| 07 | [Compute: EC2, Auto Scaling, ELB, Containers & Lambda](07-Compute-Containers-and-Serverless.md) | D2, D3, D4 | ★★★ |
| 08 | [Storage: S3, EBS, EFS, FSx, Storage Gateway, Backup & Data Transfer](08-Storage-and-Data-Transfer.md) | D2, D3, D4 | ★★★ |
| 09 | [Databases & Caching](09-Databases-and-Caching.md) | D2, D3, D4 | ★★★ |
| 10 | [Application Integration: APIs, Messaging, Events & Workflows](10-Application-Integration-and-Event-Driven.md) | D2, D3, D4 4.4 | ★★☆ |
| 11 | [Analytics, Streaming, Data Lakes & AI/ML](11-Analytics-Streaming-and-AI-ML.md) | D2, D3 | ★★☆ |
| 12 | [Reliability, High Availability & Disaster Recovery](12-Resilience-HA-and-Disaster-Recovery.md) | D1 1.3, D2 2.2/2.4, D3 3.4 | ★★★ |
| 13 | [Migration & Modernization (Domain 4)](13-Migration-and-Modernization.md) | D4 | ★★★ |
| 14 | [Deployment Strategy, CI/CD & Infrastructure as Code](14-Deployment-DevOps-and-IaC.md) | D2 2.1, D3 3.1 | ★★☆ |
| 15 | [Observability, Operations & Continuous Improvement](15-Monitoring-Operations-and-Continuous-Improvement.md) | D3 | ★★☆ |
| 16 | [Cost Optimization, Cost Visibility & FinOps](16-Cost-Optimization-and-FinOps.md) | D1 1.5, D2 2.6, D3 3.5 | ★★★ |
| 17 | [**Practice Papers**: official sample explained + 5 original papers](17-Practice-Papers/README.md) | All | ★★★ |
| 18 | [Cheat Sheets, Decision Trees & Comparisons](18-Cheat-Sheets-and-Comparisons.md) | All | ★★★ final week |
| 19 | [Glossary, Final-Week Revision & Exam-Day Playbook](19-Glossary-and-Final-Revision.md) | All | ★★★ final days |

**Every topic chapter has the same structure:** what the exam tests → deep dive into each service → architecture patterns (diagrams) → decision tables (X vs Y) → keyword→answer list → traps → Professional-architect focus → skills checklist → 10 practice questions with explanations → official references.

---

## 14-day study plan (17 Oct → 31 Oct 2026)

Plan for **about 4–5 hours a day on weekdays and 7–8 hours on weekends**. Highest-weight material comes first. Each "chapter" block means: read the chapter, then do its 10 practice questions *without peeking*, then re-read the explanations of everything you missed.

| Day | Date | Focus | Output |
|---|---|---|---|
| 1 | Sat 17 Oct | [01 Blueprint](01-Exam-Blueprint-and-Strategy.md) → [Paper 00 (official sample)](17-Practice-Papers/Paper-00-Official-AWS-Sample-Questions-Explained.md) as a **baseline** → [02 Multi-account](02-Multi-Account-Governance.md) | Baseline score; list of weak areas |
| 2 | Sun 18 Oct | [03 IAM & federation](03-Identity-and-Access-Management.md) → [04 Networking](04-Networking-VPC-and-Hybrid-Connectivity.md) (first half) | Policy-evaluation flow memorized |
| 3 | Mon 19 Oct | [04 Networking](04-Networking-VPC-and-Hybrid-Connectivity.md) (second half: DX, VPN, hybrid DNS, inspection) | Draw TGW + DX gateway + Resolver from memory |
| 4 | Tue 20 Oct | [05 Edge](05-Edge-DNS-and-Content-Delivery.md) → [06 Security](06-Security-Data-Protection-and-Threat-Detection.md) | KMS cross-account rules memorized |
| 5 | Wed 21 Oct | [12 Resilience & DR](12-Resilience-HA-and-Disaster-Recovery.md) → **[Paper 1](17-Practice-Papers/Paper-01-Governance-Networking-Hybrid.md)** (timed, 48 min) | Score ≥ 13/20? |
| 6 | Thu 22 Oct | [07 Compute](07-Compute-Containers-and-Serverless.md) → [08 Storage](08-Storage-and-Data-Transfer.md) (first half) | |
| 7 | Fri 23 Oct | [08 Storage](08-Storage-and-Data-Transfer.md) (second half) → [09 Databases](09-Databases-and-Caching.md) | Database decision tree from memory |
| 8 | Sat 24 Oct | [10 Integration](10-Application-Integration-and-Event-Driven.md) → [11 Analytics/AI](11-Analytics-Streaming-and-AI-ML.md) → **[Paper 2](17-Practice-Papers/Paper-02-New-Solutions-Serverless-Data.md)** | |
| 9 | Sun 25 Oct | [13 Migration](13-Migration-and-Modernization.md) → **[Paper 4](17-Practice-Papers/Paper-04-Migration-Modernization.md)** | 7 Rs + tool-per-source table memorized |
| 10 | Mon 26 Oct | [14 Deployment/IaC](14-Deployment-DevOps-and-IaC.md) → [15 Operations](15-Monitoring-Operations-and-Continuous-Improvement.md) | |
| 11 | Tue 27 Oct | [16 Cost](16-Cost-Optimization-and-FinOps.md) → **[Paper 3](17-Practice-Papers/Paper-03-Continuous-Improvement-Operations.md)** | |
| 12 | Wed 28 Oct | **[Paper 5 (hardest)](17-Practice-Papers/Paper-05-Full-Mixed-Hard.md)** under exam conditions → re-study weakest 2 chapters | |
| 13 | Thu 29 Oct | [18 Cheat sheets](18-Cheat-Sheets-and-Comparisons.md) (all of it) → redo **every question you got wrong** across papers | Error log reviewed |
| 14 | Fri 30 Oct | [19 Final revision & exam-day playbook](19-Glossary-and-Final-Revision.md) → re-read [01](01-Exam-Blueprint-and-Strategy.md) §3–5 → **stop by 7 pm and sleep** | |
| — | **Sat 31 Oct** | **Exam.** Light review of the keyword table in 18 only | 🎯 |

**Keep an error log** (one line per missed question: topic · why you were wrong · the rule you'll remember). Reviewing it on day 13 is the single highest-value activity in the plan.

### If you have less time
- **7 days:** 01 → 04 → 02/03 → 12 → 13 → 06 → 09 → 16, then all papers on days 6–7 plus chapter 18.
- **3 days:** 01, 18, 19, then all six papers. Read only the explanations of questions you miss, and the chapter sections they link to.

---

## How to read readiness

| Signal | Ready? |
|---|---|
| ≥ 80% on Papers 1–5 (≥ 16/20 each) on the **first attempt** | Very likely to pass comfortably |
| 65–80% | Borderline. Focus on weak domains and redo misses |
| < 65% | Re-study the chapters linked from your misses before the next paper |
| You can explain *why every wrong option is wrong* | The best predictor of a Professional pass |

---

## Conventions used in the guide
- **Exam mapping** at the top of each chapter refers to the official task statements (for example *D1 1.1*). See [Chapter 01 §2](01-Exam-Blueprint-and-Strategy.md#2-domains-and-every-task-statement-official).
- 🔑 marks *exam keywords*, ⚠️ marks *traps*, 🧭 marks *Professional-architect judgement*.
- **Service names.** Exam questions may use old or new names. Common renames: AWS SSO → **IAM Identity Center** · Application Migration Service → **AWS Transform MGN** (renamed 2026) · Kinesis Data Firehose → **Amazon Data Firehose** · Kinesis Data Analytics → **Managed Service for Apache Flink** · SageMaker → **SageMaker AI** · CloudWatch Events → **EventBridge**. The full table is in [Chapter 18](18-Cheat-Sheets-and-Comparisons.md).
- Quotas quoted are **defaults** at the time of writing (Oct 2026). Many are soft limits that can be raised.

## Key official sources
- Exam guide: https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/solutions-architect-professional-02.html
- In-scope services: https://docs.aws.amazon.com/aws-certification/latest/solutions-architect-professional-02/sap-02-in-scope-services.html
- Official sample questions: https://d1.awsstatic.com/training-and-certification/docs-sa-pro/AWS-Certified-Solutions-Architect-Professional_Sample-Questions.pdf
- Well-Architected Framework: https://docs.aws.amazon.com/wellarchitected/latest/framework/welcome.html
- Multi-VPC networking whitepaper: https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-network-infrastructure/welcome.html
- Disaster recovery whitepaper: https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html
- Organizing your AWS environment (multi-account): https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/organizing-your-aws-environment.html
- Migration strategies (7 Rs): https://docs.aws.amazon.com/prescriptive-guidance/latest/large-migration-guide/migration-strategies.html

Good luck. 750 is very reachable if you work through every practice question and understand each explanation.
