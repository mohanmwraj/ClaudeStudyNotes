# Chapter 17 — Practice Papers

> [← Chapter 16](../16-Cost-Optimization-and-FinOps.md) · [Index](../00-README-Start-Here.md) · [Next → Chapter 18](../18-Cheat-Sheets-and-Comparisons.md)

## Why there are no real "previous papers"
AWS certification exam content is covered by the **AWS Certification Program Agreement / NDA**. AWS never publishes past SAP-C02 papers, and "dumps" sold online are unauthorized, often wrong, and can get a certification revoked. The only **official** questions available for free are AWS's **10-question sample set**. This chapter gives you:

| Paper | Contents | Questions | Use it |
|---|---|---|---|
| [Paper 00 — Official AWS Sample Questions (Explained)](Paper-00-Official-AWS-Sample-Questions-Explained.md) | AWS's official sample questions, paraphrased and explained in depth, with links to the original PDF | 10 | **Day 1 baseline** |
| [Paper 1 — Governance, Networking & Hybrid](Paper-01-Governance-Networking-Hybrid.md) | Organizations/SCPs, Control Tower, TGW, DX/VPN, hybrid DNS, Identity Center, DR, migration basics | 20 | After ch. 02–06, 12 |
| [Paper 2 — Designing New Solutions (Serverless, Containers, Data)](Paper-02-New-Solutions-Serverless-Data.md) | API GW/Lambda/DynamoDB, Step Functions, EKS/ECS, Aurora Serverless, Cognito, edge, data lake | 20 | After ch. 07–11 |
| [Paper 3 — Continuous Improvement, Operations & Security Hardening](Paper-03-Continuous-Improvement-Operations.md) | RDS Proxy, observability, patching, Config remediation, GuardDuty/Security Hub, cost fixes | 20 | After ch. 14–16 |
| [Paper 4 — Migration & Modernization](Paper-04-Migration-Modernization.md) | 7 Rs, discovery, MGN, DMS/SCT, DataSync/Transfer Family/FSx, mainframe, strangler fig | 20 | After ch. 13 |
| [Paper 5 — Full Mixed (Hardest)](Paper-05-Full-Mixed-Hard.md) | Multi-Region active-active, data perimeter, Cloud WAN, StackSets, cross-account CI/CD, DRS, FIS | 20 | 2–3 days before the exam |

**Total: 110 questions, every one with a detailed explanation and official references.** Each topic chapter (02–16) also ends with **10 more practice questions** (150 more).

## How to take a paper
1. Set a timer for **48 minutes** (exam pace is about 2.4 minutes per question).
2. Answer all 20 questions without looking at the solutions. Flag any you guessed.
3. Mark your answers with the **answer key**. Then read the **detailed solution for every question**, including the ones you got right, especially the flagged guesses.
4. Log each miss in your error log as: *topic → why I chose wrong → rule to remember*.
5. Use each paper's **Score interpretation** section to pick which chapters to revisit.

## Score → readiness

| Average across Papers 1–5 | Interpretation |
|---|---|
| ≥ 16/20 (80%) | Exam-ready. Keep revising the cheat sheets |
| 13–15/20 | Close. Target your weakest domain(s) |
| < 13/20 | Re-study the linked chapters, then retake the paper after 2 days |

> The real exam's scaled pass mark of 750 does not correspond exactly to 75% raw, because scoring is scaled. Consistently scoring ≥ 75–80% on hard original questions is a strong signal.

## Other legitimate official practice (optional)
- AWS official sample questions PDF: https://d1.awsstatic.com/training-and-certification/docs-sa-pro/AWS-Certified-Solutions-Architect-Professional_Sample-Questions.pdf
- AWS Skill Builder has an official practice question set and practice exam for SAP-C02 (see Paper 00 for details): https://skillbuilder.aws/
