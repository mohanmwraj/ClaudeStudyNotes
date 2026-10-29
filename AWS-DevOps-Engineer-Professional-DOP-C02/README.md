# AWS Certified DevOps Engineer – Professional (DOP-C02): Source of Truth

A self-contained preparation repo for the **AWS Certified DevOps Engineer – Professional** exam. It teaches each topic from first principles, meaning the small number of mechanisms that the exam's scenarios are built from. It then drills them with original exam-style questions and three full-length mock papers.

Everything in this repo was checked on **2026-10-29** against AWS's own exam guide and documentation. The links next to each claim are the sources.

---

## Exam facts (verified 2026-10-29)

| Item | Value | Source |
|---|---|---|
| Exam code | **DOP-C02**. No successor version had been announced. | [Exam page](https://aws.amazon.com/certification/certified-devops-engineer-professional/) |
| Questions | **75**: 65 scored + 10 unscored (unmarked, so treat every question as scored) | [Exam guide](https://docs.aws.amazon.com/aws-certification/latest/devops-engineer-professional-02/devops-engineer-professional-02.html) |
| Question types | Multiple choice (1 correct of 4) and multiple response (2 or more correct of 5 or more) | Exam guide |
| Duration | **180 minutes**, about 2 minutes 24 seconds per question | Exam page |
| Passing score | **750** on a 100–1,000 scaled score. Compensatory: you don't need to pass each domain | Exam guide |
| Guessing | No penalty. **Never leave a question blank** | Exam guide |
| Cost | USD 300 | Exam page |
| Delivery | Pearson VUE test centre or online proctored | Exam page |
| Languages | English, Japanese, Korean, Simplified Chinese. The Korean version is retired after 2026-12-31 | Exam page |
| Recommended experience | 2+ years provisioning, operating and managing AWS environments, plus SDLC and scripting | Exam guide |

### The six domains

| # | Domain | Weight | Questions on a 75-question paper | Folder |
|---|---|---|---|---|
| 1 | SDLC Automation | 22% | ≈ 17 | [01-SDLC-Automation](01-SDLC-Automation/) |
| 2 | Configuration Management and IaC | 17% | ≈ 13 | [02-Configuration-Management-and-IaC](02-Configuration-Management-and-IaC/) |
| 3 | Resilient Cloud Solutions | 15% | ≈ 11 | [03-Resilient-Cloud-Solutions](03-Resilient-Cloud-Solutions/) |
| 4 | Monitoring and Logging | 15% | ≈ 11 | [04-Monitoring-and-Logging](04-Monitoring-and-Logging/) |
| 5 | Incident and Event Response | 14% | ≈ 10 | [05-Incident-and-Event-Response](05-Incident-and-Event-Response/) |
| 6 | Security and Compliance | 17% | ≈ 13 | [06-Security-and-Compliance](06-Security-and-Compliance/) |

The mock papers in folder 07 follow exactly this mix.

---

## How to use this repo

1. **Read [00-Exam-Strategy-and-First-Principles](00-Exam-Strategy-and-First-Principles/) first.** It holds the mental models every later file reuses, how to decode a DOP question, and an 8-week plan.
2. **Work through folders 01–06 in order.** Each domain file ends with a summary of the traps that file covers. Do the hands-on labs if you have an AWS account (all are small; tear-down steps included).
3. **After each domain, do that domain's drill** in [07-Exam-Questions-and-Sample-Papers](07-Exam-Questions-and-Sample-Papers/). Read the explanation for **every** option, including the ones you got right.
4. **Take the three mock papers under exam conditions:** 180 minutes, no notes, answers file closed. Aim for 80%+ before booking. The pass mark is a scaled 750, and 80% on original questions of this difficulty is a safe margin.
5. **In the last week**, take AWS's official free sample questions (10 questions) as a calibration check, then reread the trap catalogue in folder 07.

## Repository map

```text
00-Exam-Strategy-and-First-Principles/     exam facts, first-principles models, question decoding, study plan
01-SDLC-Automation/                        source, build, artifacts, pipelines, deployment strategies, testing
02-Configuration-Management-and-IaC/       CloudFormation, CDK/SAM/Service Catalog, multi-account, Systems Manager + Config
03-Resilient-Cloud-Solutions/              HA multi-AZ/multi-Region, scaling, disaster recovery and backup
04-Monitoring-and-Logging/                 CloudWatch metrics/alarms/agent, logs pipelines, tracing and analytics
05-Incident-and-Event-Response/            event sources, automated remediation, troubleshooting playbook
06-Security-and-Compliance/                IAM at scale, data protection and network security, detection and audit
07-Exam-Questions-and-Sample-Papers/       domain drills, 3 full mock papers with separate answer keys, trap catalogue
```

---

## What changed since DOP-C02 was written (status on 2026-10-29)

The exam was released in March 2023 and its in-scope service list still names some services that have since been retired or changed. The exam can still mention them, so you need to know what they **were**. In real designs, use the current equivalent.

| Service | Status | What to know for the exam |
|---|---|---|
| AWS CodeCommit | Closed to new customers in July 2024, then **back to general availability on 2025-11-24** ([AWS blog](https://aws.amazon.com/blogs/devops/aws-codecommit-returns-to-general-availability/)). Not on the current in-scope list | Questions may still use CodeCommit as a pipeline source. Its events go to EventBridge, and the pipeline is triggered by an EventBridge rule |
| AWS CodeStar | Projects discontinued 2024-07-31 | Only the old project-template service. **CodeStar Connections was renamed AWS CodeConnections** (2024-03-29) and is very much alive: it's how CodePipeline reaches GitHub, GitLab and Bitbucket ([rename notice](https://docs.aws.amazon.com/dtconsole/latest/userguide/rename.html)) |
| AWS OpsWorks | OpsWorks Stacks reached end of life 2024-05-26 and was disabled for all customers, according to AWS's "OpsWorks Stacks End of Life FAQs". A web search on 2026-10-29 still returned that page's text, but the page itself now returns 404 | It was managed Chef/Puppet. If a question offers it for configuration management, the modern answer is Systems Manager (State Manager, Automation) |
| AWS Proton | End of support 2026-10-07 ([migration guide](https://docs.aws.amazon.com/proton/latest/userguide/proton-end-of-support.html)) | It was template-based platform engineering. Today, use Service Catalog, CDK or CloudFormation |
| Amazon CodeGuru Reviewer, Amazon CodeCatalyst, SSM Incident Manager, SSM Change Manager | Maintenance: closed to new customers from 2025-11-07 ([announcement](https://aws.amazon.com/about-aws/whats-new/2025/10/aws-service-availability)) | Recognize them in options. For incidents, AWS points to Systems Manager OpsCenter |
| AWS Security Hub | A new Security Hub reached general availability 2025-12-02; the original service is now **Security Hub CSPM** ([announcement](https://aws.amazon.com/about-aws/whats-new/2025/12/security-hub-near-real-time-risk-analytics/)) | Exam questions mean the original service: aggregating findings, security standards, cross-account/cross-Region aggregation, and EventBridge integration |
| Amazon ECS deployments | Native blue/green (July 2025) plus canary/linear (October 2025), without CodeDeploy ([AWS blog](https://aws.amazon.com/blogs/aws/accelerate-safe-software-releases-with-new-built-in-blue-green-deployments-in-amazon-ecs/)) | Exam questions use **CodeDeploy** for ECS blue/green. Know both |
| AWS CodePipeline | V2 pipeline type: Git tag/branch/file-path triggers, pipeline variables, QUEUED/PARALLEL modes, stage rollback and conditions ([V1 vs V2](https://docs.aws.amazon.com/codepipeline/latest/userguide/pipeline-types-planning.html)) | Newer than most exam questions, but correct answers stay correct |
| Renames | Kinesis Data Firehose → Amazon Data Firehose; Fault Injection Simulator → Fault Injection Service | The exam page notes that short service names are listed under the exam's Help button |

---

## About the questions in this repo

* **Every question is original**, written for this repo against the official task statements. None are copied from AWS material or from "exam dump" sites. Dumps are against the AWS Certification Agreement, and they are frequently wrong.
* **Every answer explains every option.** It says why the right ones are right and why each distractor fails, and ends with a link to the AWS documentation page that settles it.
* **Official AWS practice material**, free and worth taking in your final week:
  * [Official sample questions (10 questions, PDF)](https://d1.awsstatic.com/training-and-certification/docs-devops-pro/AWS-Certified-DevOps-Engineer-Professional_Sample-Questions.pdf)
  * [AWS Skill Builder exam prep plan for DOP-C02](https://skillbuilder.aws/category/exam-prep/devops-engineer-professional-DOP-C02) (includes the Official Practice Question Set)

## How this repo was checked

* **Exam facts** come from the official exam guide and exam page, fetched on 2026-10-29.
* **Every URL in every file** was fetched by a link checker and returned HTTP 200.
* **Every code sample was checked mechanically:** YAML and JSON blocks parse, and CloudFormation templates pass `cfn-lint`.
* **The question bank is checked by a validator.** It checks the format (4 options for single answer; 5 or more for multiple response; the number of answers matches "Select TWO/THREE"), that every option is explained and has a reference, the domain mix of each mock paper, the balance of correct letters, and near-duplicate stems.

The gate results are recorded in [07-Exam-Questions-and-Sample-Papers/README.md](07-Exam-Questions-and-Sample-Papers/README.md).
