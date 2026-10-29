# 03 · Decoding Questions and Eliminating Distractors

Professional-level AWS questions are long scenarios in which several options **work**. Your job is to find the option that **best satisfies every stated constraint**. That is a reading skill as much as a knowledge skill, and this file teaches it as a procedure.

---

## 1. The anatomy of a DOP question

Almost every question has four parts:

1. **Context.** The current architecture: "A company runs an application on EC2 instances in an Auto Scaling group behind an ALB…"
2. **Problem or change.** "Deployments cause downtime…", "A new policy requires…"
3. **Constraints.** Explicit ("within 15 minutes", "across all accounts", "without changing the application code") and **qualifiers** ("MOST operationally efficient", "LEAST cost", "fastest").
4. **The ask.** "What should the DevOps engineer do?" or "Which combination of steps… (Select TWO.)"

The constraints and the qualifier decide the answer. The context mostly tells you which tools are already present.

## 2. The five-step procedure (about 2 minutes per question)

1. **Read the last sentence first.** Note the qualifier and how many answers to select.
2. **Read the stem and underline the constraints.** Write them down mentally as a checklist, typically 2–4 items: for example *automatic*, *all accounts including future ones*, *least overhead*.
3. **Predict the answer shape** before you read the options, using the decoder table in [02-first-principles-mental-models.md](02-first-principles-mental-models.md#the-decoder-requirement-phrase--principle--typical-answer). Example: "every future account" + "least overhead" → an organization-level native feature.
4. **Eliminate options that violate any constraint.** One violation is enough to kill an option. Usually two options die quickly.
5. **Choose between the survivors with the qualifier.** Both may work; pick the one with fewer moving parts (operational efficiency), lower cost, or faster recovery, whichever the question asked for.

If you can't decide within about 3 minutes, **pick your best guess, flag it, and move on**. Come back with the time you saved on easy questions.

## 3. The qualifiers, and what each one means

| Qualifier | What wins | What loses |
|---|---|---|
| MOST operationally efficient / LEAST operational overhead / LEAST management effort | Native managed features, org-wide auto-enable, declarative configuration | Custom Lambda functions, cron jobs, self-managed servers, per-account scripts |
| MOST cost-effective / LEAST cost | The cheapest option that **still meets every requirement**: smaller DR tier, Spot for fault-tolerant work, lifecycle to cheaper storage, serverless for spiky load | Always-on duplicates, over-provisioned DR |
| FASTEST / with the LEAST downtime / MINIMIZE impact | Immutable deployments, blue/green, pre-warmed capacity, alarm-based automatic rollback | In-place, all-at-once, manual steps |
| MOST secure | Least privilege, encryption with customer-managed keys where control is needed, no long-term credentials, private connectivity | Broad wildcards, shared credentials |
| MOST scalable / highly available | Multi-AZ, decoupling, auto scaling, managed services | Single instance, vertical scaling |

When a question has **no qualifier**, the answer is the only option that fully works. Look for the hidden flaw in each of the others.

## 4. Distractor patterns you'll see repeatedly

These recur across the whole exam. Learn to spot them in 5 seconds.

1. **Polling when an event exists.** "Use a scheduled Lambda function to check every 5 minutes…" when EventBridge emits the event (P1).
2. **The right service, the wrong feature.** "Use CloudWatch detailed monitoring to collect memory metrics" (detailed monitoring is only a 1-minute period; memory needs the agent). "Enable S3 versioning to replicate across Regions" (versioning is a prerequisite for replication, not replication itself).
3. **A grant where a guardrail is needed.** "Add an IAM policy that allows…" when an SCP denies the action. "Use an SCP to grant access" (SCPs never grant, P2).
4. **A one-time fix for an ongoing requirement.** "Run a script to fix all non-compliant resources" when the requirement says *continuously* or *future resources* (P3).
5. **Per-account work at organization scale.** "In each account, enable…" when organization integration with a delegated administrator auto-enables the service (P13).
6. **The impossible mechanism.** For example: "Share the AWS-managed KMS key with the other account" (not possible); "Attach an IAM role to an S3 bucket" (buckets have policies, not roles); "Configure the ALB to roll back the deployment" (ALBs don't deploy). Know what each service can and cannot do.
7. **Manual steps when the requirement says automatic.** "The operations team reviews the dashboard and…"
8. **Over-engineering.** Multi-site active/active for a 24-hour RTO, a Step Functions state machine for one API call, or Kubernetes for a single static site.
9. **Breaking a stated constraint quietly.** "Modify the application code" when the stem says the code can't change. "Use a single Region" when the requirement says survive a Regional outage.
10. **Long-term credentials.** "Create an IAM user with access keys and store them in…" (P14). This is almost never right on DOP.
11. **Wrong Region or scope details.**
    * ACM certificates for CloudFront must be in **us-east-1**.
    * CloudFormation StackSets service-managed permissions require **Organizations** with trusted access.
    * KMS keys are Regional unless you use multi-Region keys.
    * A Config aggregator collects data but doesn't evaluate rules in source accounts.
12. **Mixing up near-synonyms:**
    * CloudTrail (who called which API) vs Config (what the configuration was, and when it changed);
    * GuardDuty (threat detection) vs Inspector (vulnerabilities) vs Macie (sensitive data) vs Detective (investigation) vs Security Hub (aggregation and standards);
    * Parameter Store (configuration, SecureString, no native rotation) vs Secrets Manager (rotation, cross-account resource policies);
    * AppConfig (feature flags and configuration validated and deployed gradually) vs Parameter Store;
    * State Manager (keep a desired state) vs Run Command (one-off) vs Automation (multi-step runbooks).

## 5. Multiple-response technique ("Select TWO / THREE")

* Each correct option is usually **one half or one third of a single solution**, for example "create the role in account B" + "update the bucket policy in account A". Look for options that **pair up** into a complete chain.
* Treat every option as an independent true/false statement about the scenario.
* If two options are mutually exclusive alternatives for the same step (two ways to do the trigger), **at most one** of them is correct. That often cuts the field quickly.
* No partial credit: pick exactly the number asked.

## 6. Time management for 180 minutes

| Checkpoint | Target |
|---|---|
| After 60 minutes | About 27 questions answered (pace about 2:13 each) |
| After 120 minutes | About 54 questions answered |
| 150 minutes | All 75 answered once, with flags on uncertain ones |
| 150–180 minutes | Review flagged questions only |

Rules that help:
* Flag liberally and answer everything on the first pass. An unanswered question is guaranteed wrong.
* Don't change an answer on review unless you find a **specific constraint** you missed. A vague feeling isn't enough.
* The exam is long: 180 minutes plus check-in. Online proctoring forbids breaks from your seat; test centres allow breaks, but the clock keeps running.

## 7. A worked decode (original example)

> *A company has 40 AWS accounts in AWS Organizations and adds new accounts every month. Security requires that Amazon GuardDuty is enabled in every account and every Region the company uses, including future accounts, and that findings are reviewed centrally. What is the MOST operationally efficient solution?*

1. **Ask and qualifier:** one answer; MOST operationally efficient.
2. **Constraints:** every account; every Region in use; **future** accounts; **central** review.
3. **Predicted shape:** GuardDuty organization integration. Designate a delegated administrator (the security account), turn on auto-enable for the organization (new accounts are covered automatically), repeat in each Region in use (GuardDuty is Regional), and review findings in the delegated admin account. Optionally send them to Security Hub.
4. **Eliminate:**
   * "StackSets to create a GuardDuty detector in every account": works, but it's the long way, and invitations or associations still have to be handled. It loses on efficiency.
   * "A Lambda triggered by `CreateAccount` that enables GuardDuty": custom code, so it loses.
   * "Enable GuardDuty in the management account only": doesn't cover member accounts, so it fails the constraint.
5. **Answer:** delegated administrator + organization auto-enable in each used Region.

The same five steps work on every question in this repo's drills and mock papers.
