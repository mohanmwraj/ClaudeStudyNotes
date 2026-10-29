# 04 · An Eight-Week Study Plan

Built for someone working full time: about **10–12 hours a week**, so 80–95 hours in total. If you already run AWS workloads daily, compress it to 4–5 weeks by skimming the notes for domains you know and spending the saved time on drills.

**Rules for the whole plan:**

* **Read, then do, then test.** Every domain: notes → the hands-on lab (if you have an AWS account) → the domain drill in folder 07. Review every explanation, including for questions you got right.
* **Keep an error log.** For every wrong answer, write one line: *the constraint I missed* and *the principle (P1–P14) it maps to*. Reread the log weekly. Most people find their mistakes cluster around 3–4 principles.
* **Labs cost money only if you forget to delete them.** Each lab ends with tear-down commands. Set an AWS Budgets alert at a low amount before you start.

---

| Week | Focus | Read | Do | Test |
|---|---|---|---|---|
| 1 | Strategy + identity foundations | All of folder 00; [06/01 IAM at scale](../06-Security-and-Compliance/01-iam-at-scale.md) | Write three policies by hand: an SCP, a permissions boundary, a cross-account role trust policy | Domain 6 drill, IAM questions only |
| 2 | SDLC part 1: source, build, artifacts, pipelines | [01/01](../01-SDLC-Automation/01-source-build-and-artifacts.md), [01/02](../01-SDLC-Automation/02-codepipeline-design-and-multi-account.md) | Lab: CodeBuild + CodePipeline with an EventBridge trigger | First half of the Domain 1 drill |
| 3 | SDLC part 2: deployments and testing | [01/03](../01-SDLC-Automation/03-deployment-strategies.md), [01/04](../01-SDLC-Automation/04-testing-in-pipelines.md) | Lab: SAM Lambda canary with alarm rollback | Rest of the Domain 1 drill |
| 4 | IaC and multi-account | [02/01](../02-Configuration-Management-and-IaC/01-cloudformation-deep-dive.md), [02/02](../02-Configuration-Management-and-IaC/02-cdk-sam-and-service-catalog.md), [02/03](../02-Configuration-Management-and-IaC/03-multi-account-organizations-control-tower.md) | Lab: CloudFormation with `cfn-init`/`cfn-signal`; a change set; drift detection | First half of the Domain 2 drill |
| 5 | Systems Manager + Config; event response | [02/04](../02-Configuration-Management-and-IaC/04-systems-manager-and-config.md), all of folder 05 | Lab: Config rule + automatic remediation | Rest of the Domain 2 drill + the Domain 5 drill |
| 6 | Resilience | All of folder 03 | Lab: Route 53 failover with a health check; an AWS Backup plan with cross-Region copy | Domain 3 drill |
| 7 | Monitoring + security operations | All of folder 04; [06/02](../06-Security-and-Compliance/02-data-protection-and-network-security.md), [06/03](../06-Security-and-Compliance/03-detection-auditing-and-response.md) | Lab: CloudWatch agent + metric filter + alarm; GuardDuty → EventBridge → SNS | Domain 4 drill + the rest of the Domain 6 drill |
| 8 | Full mocks and review | The [trap catalogue](../07-Exam-Questions-and-Sample-Papers/10-trap-catalogue.md) and your error log | — | Mock paper 1 (day 1), review (day 2); mock paper 2 (day 3), review; mock paper 3 (day 5), review; AWS official sample questions (day 6) |

---

## Readiness criteria (book the exam when all are true)

* **≥ 80% on each mock paper,** taken timed and closed-book.
* **≥ 70% on every domain** in your mock results. The score is compensatory, but a domain below 70% is a large risk.
* **You can explain every option of every question you got wrong,** not just name the right letter.
* **You can draw, without notes:**
  * a cross-account CodePipeline: the KMS key, the artifact bucket policy, and the two roles;
  * the CodeDeploy lifecycle hooks for EC2 in-place, ECS and Lambda;
  * the policy evaluation flow (SCP → boundary → identity/resource → explicit deny);
  * the four DR strategies with their RTO/RPO.

## The day before and the day of the exam

* Don't learn new material. Reread the trap catalogue and your error log.
* For online proctoring, run the system check in advance and clear your desk; you can't leave the camera view.
* On the day, use the five-step procedure from [03-decoding-questions-and-elimination.md](03-decoding-questions-and-elimination.md) from the very first question. It's slower for the first few questions and faster overall.
