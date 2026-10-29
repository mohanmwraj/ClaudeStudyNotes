# Domain 3 · 03 · Disaster Recovery, Backup and Automated Recovery

> **Exam task:** 3.3 (DR concepts, AWS Backup and DR strategies, recovery procedures, testing failover, cross-Region backup). **Principles:** P8 (RTO/RPO price the strategy), P3 (recovery as code), P12 (managed).

## 1. First principles

1. **RPO is set by how data gets to the recovery site. RTO is set by what already runs there.**
   * RPO: backup interval, or replication lag.
   * RTO: nothing, data only, a scaled-down stack, or a full stack.
2. **Replication is not backup.** Replication copies **mistakes** too: a deleted table, a ransomware-encrypted object, a bad migration all replicate within seconds. You need **point-in-time** copies (backups, versions, PITR) **and** replication, and you need backups that an attacker or a mistaken admin **can't delete**: Vault Lock, Object Lock, a separate account.
3. **An untested recovery isn't a recovery.** Recovery must be **automated** (runbooks as code) and **exercised** (game days, restore tests, failover drills). Only then are the RTO numbers real.

---

## 2. The four strategies with AWS mechanisms

| | **Backup and restore** | **Pilot light** | **Warm standby** | **Multi-site active/active** |
|---|---|---|---|---|
| **Data in the DR Region** | Backups copied there (AWS Backup cross-Region copy, snapshot copy, S3 CRR) | **Live replication:** Aurora Global Database, RDS cross-Region read replica, DynamoDB global tables, S3 CRR | Live replication (as pilot light) | Live, multi-writer or partitioned (DynamoDB global tables, Aurora Global Database with write forwarding) |
| **Compute in the DR Region** | None; IaC and AMIs ready | **Off.** Defined in IaC; AMIs and images replicated; the ASG may exist at 0 | **Running at reduced size** (e.g. ASG min 1–2) | **Full size,** serving traffic |
| **On disaster** | Restore data, deploy the whole stack, switch DNS | Promote the database, deploy or scale compute from 0, switch DNS | Promote the database, **scale up**, switch DNS | Shift traffic weights (or nothing, if both already serve) |
| **Typical RPO** | Hours (backup frequency) | Seconds to minutes | Seconds to minutes | Near zero |
| **Typical RTO** | Hours to a day | Tens of minutes | Minutes | Near zero |
| **Cost** | $ | $$ | $$$ | $$$$ |

**Choosing:** take the **cheapest column that meets both numbers.**

| Scenario | Answer |
|---|---|
| RPO 24 h, RTO 24 h, minimize cost | Backup and restore (AWS Backup with cross-Region copy) |
| RPO 1 min, RTO 1 h, cost-conscious | Pilot light (Aurora Global Database + IaC to launch compute) |
| RPO 1 min, RTO 10 min | Warm standby |
| RPO ≈ 0, RTO ≈ 0, global users | Active/active (DynamoDB global tables, Route 53 latency routing, or Global Accelerator) |

## 3. AWS Backup

| Concept | Detail |
|---|---|
| **Backup plan** | **Rules:** schedule (cron, or continuous for PITR-capable resources), start and completion windows, **lifecycle** (move to cold storage after N days; delete after M days), **copy actions** (to another Region and/or account), tags on recovery points |
| **Resource assignment** | By **tags** (e.g. `backup=daily`) or ARNs, so new resources tagged correctly are protected automatically (P3) |
| **Backup vault** | Container for recovery points, encrypted with a KMS key, with a **vault access policy** (e.g. deny `DeleteRecoveryPoint`) |
| **Vault Lock** | WORM protection. **Governance mode:** users with special permissions can remove it. **Compliance mode:** after the grace ("cooling-off") period, **nobody**, including the root user and AWS, can delete recovery points before retention ends or change the lock |
| **Logically air-gapped vault** | A vault type whose recovery points are isolated and shareable for recovery into another account (via RAM) |
| **Cross-account copy** | Copy recovery points to a vault in a **separate backup account** in the organization. Defends against compromise of the production account |
| **Organizations backup policies** | Define backup plans centrally and attach them to OUs; enforced in every member account |
| **Backup Audit Manager** | Frameworks of controls ("resources are backed up", "backups are copied cross-Region", "vault lock enabled") with compliance reports |
| **Restore testing** | Scheduled automated restores with validation, to prove restorability and measure restore time |

**Services AWS Backup covers** include EC2/AMIs, EBS, RDS, Aurora, DynamoDB, EFS, FSx, S3, DocumentDB, Neptune, Redshift, Storage Gateway volumes, and VMware/on-premises via the Backup gateway. It's the "one place, all services, cross-Region and cross-account, with WORM" answer.

### 3.1 Native backup features (when AWS Backup isn't named)

| Service | Native point-in-time and copy features |
|---|---|
| **RDS** | Automated backups with **PITR** (retention up to 35 days); manual snapshots (kept until deleted); **cross-Region automated backup replication**; snapshot **copy** cross-Region and cross-account (re-encrypt with a KMS key in the destination; share the key or snapshot for cross-account) |
| **Aurora** | Continuous backup with PITR; **backtrack** (MySQL-compatible: rewind in place, no restore); cloning |
| **DynamoDB** | **PITR** (up to 35 days, per-second granularity, restores to a **new table**); on-demand backups; export to S3 |
| **EBS** | Snapshots (incremental); **Amazon Data Lifecycle Manager** policies (schedule, retention, **cross-Region copy**, cross-account sharing); fast snapshot restore |
| **S3** | **Versioning** (recover overwritten or deleted objects); **Object Lock** (WORM: governance or compliance mode, retention periods, legal holds); replication; lifecycle |
| **EFS** | AWS Backup (automatic backups enabled by default for new file systems through the console); EFS replication |

## 4. AWS Elastic Disaster Recovery (DRS)

* **Continuous block-level replication** of servers (on-premises, other clouds, or EC2 in another Region or AZ) into a low-cost **staging area** in your AWS account.
* On recovery, it **launches recovery instances** from the latest or a point-in-time state: **RPO in seconds, RTO in minutes**.
* **Non-disruptive drills** test recovery without affecting replication.
* **Failback** to the source environment when it's healthy again.
* **When it's the answer:** "lift-and-shift servers (databases running on VMs, legacy applications) need DR into AWS with an RPO of seconds and an RTO of minutes, at low cost" (because the staging area runs lightweight replication servers, not full copies).

## 5. Automated recovery procedures

| Piece | Mechanism |
|---|---|
| **The runbook** | **SSM Automation** documents or Step Functions: promote the DB, scale the ASG, update parameters, flip DNS. They're versioned, tested and auditable |
| **The switch** | Route 53 failover records with health checks (automatic); **Route 53 ARC routing controls** (an operator flips a highly available switch; data-plane only, so it works during Regional control-plane impairment); Global Accelerator endpoint weights |
| **Database promotion** | Aurora Global Database **switchover** (planned, RPO 0) or **failover** (unplanned); RDS read-replica promotion; DynamoDB global tables need no promotion (already writable) |
| **Readiness** | ARC **readiness checks** compare quotas, capacity and configuration between the primary and recovery Regions |
| **Assessment** | **AWS Resilience Hub:** define an application (from CloudFormation stacks, tags or EKS) and a **resiliency policy** (RTO/RPO targets for AZ, Region, application and infrastructure disruptions). It assesses whether the architecture meets them, recommends fixes, and generates FIS experiments and alarms. Run it in the pipeline to catch resilience drift |
| **Testing** | **AWS FIS** experiments (stop instances, fail over Aurora, disrupt an AZ's network, throttle APIs) with **stop conditions**; DRS drills; AWS Backup restore testing; RDS "reboot with failover" |

### 5.1 Don't forget the supporting cast in the recovery Region

* **Secrets:** Secrets Manager **replica secrets**.
* **Keys:** KMS **multi-Region keys**, so encrypted data and backups decrypt with the same key material.
* **Images:** ECR **replication**; AMIs via copy or Image Builder distribution.
* **Parameters and configuration:** replicate SSM parameters, or deploy them with the same IaC.
* **Quotas:** request service-quota increases in the recovery Region **before** you need them. ARC readiness checks flag mismatches.
* **IaC and pipelines:** the ability to deploy into the recovery Region even if the primary Region's tooling is down.

## 6. Exam traps

* **DynamoDB global tables and S3 replication aren't backups.** Deletes and corruption replicate. Add PITR, versioning or Object Lock.
* **Cross-Region copy of encrypted backups and snapshots** needs a **KMS key in the destination Region** (a multi-Region key, or re-encrypt with a destination key). Cross-account needs a key the other account can use.
* **Vault Lock compliance mode is irreversible** after the cooling-off period. It's the answer to "even administrators must not be able to delete backups".
* **RDS automated backups are deleted with the instance** unless retained (manual snapshots aren't). The automated-backup retention maximum is **35 days**; longer retention needs snapshots or AWS Backup.
* **Pilot light vs warm standby:** is compute **running** (warm) or **off** (pilot)? That's the whole difference.
* **"Restores take too long to meet the RTO"** → move up a tier (pilot light), or use faster restore features (EBS fast snapshot restore, Aurora cloning), not "take backups more often" (that's RPO).

## 7. Hands-on lab: AWS Backup plan with cross-Region copy (about 20 minutes, plus waiting for the backup window)

```bash
# 1) Destination vault in the DR Region (e.g. us-west-2)
aws backup create-backup-vault --region us-west-2 --backup-vault-name dop-lab-07-dr
# 2) Plan + primary vault + tag-based selection + copy rule in the primary Region
aws cloudformation deploy --stack-name dop-lab-07 \
  --template-file labs/lab-07-backup-cross-region.yaml --capabilities CAPABILITY_IAM \
  --parameter-overrides DestinationVaultArn=arn:aws:backup:us-west-2:<acct>:backup-vault:dop-lab-07-dr
# 3) Tag a small EBS volume or DynamoDB table with backup=dop-lab-07; to test immediately:
aws backup start-backup-job --backup-vault-name dop-lab-07-primary --resource-arn <arn> \
  --iam-role-arn <BackupRoleArn output>
# 4) Watch the copy job appear in us-west-2
aws backup list-copy-jobs --region us-east-1 --query 'CopyJobs[].[State,DestinationBackupVaultArn]'
```

Clean up afterwards: delete the recovery points, then both vaults, then the stack.

The template is [labs/lab-07-backup-cross-region.yaml](labs/lab-07-backup-cross-region.yaml).

## References

* Disaster recovery options in the cloud (whitepaper) — <https://docs.aws.amazon.com/whitepapers/latest/disaster-recovery-workloads-on-aws/disaster-recovery-options-in-the-cloud.html>
* AWS Backup cross-Region and cross-account copy — <https://docs.aws.amazon.com/aws-backup/latest/devguide/recov-point-create-a-copy.html>
* AWS Backup Vault Lock — <https://docs.aws.amazon.com/aws-backup/latest/devguide/vault-lock.html>
* AWS Backup restore testing — <https://docs.aws.amazon.com/aws-backup/latest/devguide/restore-testing.html>
* Backup policies in Organizations — <https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_policies_backup.html>
* Amazon Data Lifecycle Manager — <https://docs.aws.amazon.com/ebs/latest/userguide/snapshot-lifecycle.html>
* DynamoDB point-in-time recovery — <https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/Point-in-time-recovery.html>
* S3 Object Lock — <https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html>
* AWS Elastic Disaster Recovery — <https://docs.aws.amazon.com/drs/latest/userguide/what-is-drs.html>
* AWS Resilience Hub — <https://docs.aws.amazon.com/resilience-hub/latest/userguide/what-is.html>
* Route 53 ARC routing controls — <https://docs.aws.amazon.com/r53recovery/latest/dg/routing-control.html>
