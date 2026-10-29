# 05/02 · Troubleshooting, Root-Cause Analysis and DR Processes

**Exam guide:** 4.1 (troubleshooting / root cause analysis best practices; disaster recovery), 6.4 (supporting deployed solutions). **Principles:** P2, P13.

---

## 1. Troubleshooting method: mitigate first, then find the root cause

```text
1. Detect      SLO burn-rate alert / uptime check / user report
2. Triage      Severity? Blast radius (which users/regions)? Declare an incident if needed.
3. Mitigate    Restore service FIRST: roll back the last change, shift traffic, fail over,
               scale out, disable a feature flag. (Restore, then investigate.)
4. Diagnose    "What changed?" (deploys, config, IAM, quotas, Google incidents), then follow
               the signals: metrics → traces → logs → profiles.
5. Fix         Permanent correction through the normal pipeline (IaC/CI-CD), not by hand.
6. Learn       Blameless postmortem with action items; update runbooks/alerts/tests.
```

**Exam bias:** when an outage is in progress, the best first action is usually to **mitigate**: roll back to the last known-good release or fail over. "Start debugging in production" or "page the vendor and wait" are wrong first steps.

---

## 2. The diagnostic toolbox

| Question | Tool |
|---|---|
| Is it us or Google? | **Personalized Service Health** (incidents affecting your projects, alertable) and the public Google Cloud Service Health dashboard |
| What's the user-visible impact? | Cloud Monitoring SLO dashboards, uptime checks, load-balancer metrics (latency, 5xx by backend) |
| Where is the latency? | **Cloud Trace** (distributed traces across services) |
| Which code path burns CPU or memory? | **Cloud Profiler** (continuous low-overhead profiling) |
| What errors are new? | **Error Reporting** (grouped exceptions with first-seen time) |
| What happened in the logs? | **Logs Explorer** (query), **Log Analytics** (SQL over log buckets) |
| Who changed what? | **Cloud Audit Logs** (Admin Activity), Cloud Deploy release history, Config Sync status |
| Why is A unable to reach B? | **Connectivity Tests**, VPC Flow Logs, Firewall Rules Logging, Firewall Insights |
| Why is this principal denied? | **Policy Troubleshooter** (IAM), VPC SC violation analyzer / Policy Denied logs |
| Are we hitting limits? | **Quotas** page and quota metrics/alerts; Cloud SQL / Spanner / Bigtable utilization metrics |
| Slow SQL? | Cloud SQL **Query Insights**, BigQuery query execution graph / INFORMATION_SCHEMA jobs |
| GKE pods failing? | Pod events and status (CrashLoopBackOff, OOMKilled, ImagePullBackOff), GKE workload logs, node pool autoscaler events |
| Faster AI-assisted analysis | **Gemini Cloud Assist investigations** (correlates logs, metrics, changes and suggests causes) |
| Escalation | **Cloud Customer Care** case (with the right priority and support plan) |

### Symptom → likely cause → first check

| Symptom | Likely causes | First check |
|---|---|---|
| 502/503 from the load balancer | Backends unhealthy, health check misconfigured, firewall not allowing health-check ranges (35.191.0.0/16, 130.211.0.0/22) | Backend health in the LB; firewall rules |
| Sudden latency after a deploy | Regression in the new release | Compare revisions; **roll back**; then Trace/Profiler |
| Cloud Run 429 / cold starts | Max instances too low, concurrency too low, no min instances | Instance count and concurrency metrics |
| Database connection errors at peak | Connection exhaustion | Connection count metrics; add pooling, cap max instances |
| `PERMISSION_DENIED` after a migration | Missing role on a new service account; org policy; VPC SC | Policy Troubleshooter; audit logs; VPC SC logs |
| VM can't reach Google APIs (no external IP) | Private Google Access off; DNS; routes | Subnet PGA setting; Connectivity Tests |
| Hybrid traffic drops | BGP session down; one Interconnect link failed; asymmetric routing | Cloud Router BGP status; Interconnect metrics |
| GKE pods pending | Insufficient capacity, quota, pod IP exhaustion, taints | Pod events; cluster autoscaler logs; IP ranges |
| BigQuery costs spike | Unpartitioned scans, `SELECT *`, runaway scheduled queries | INFORMATION_SCHEMA.JOBS by user and bytes billed; custom quotas |

---

## 3. Incident management and RCA

**Roles in an incident:**

* **Incident commander:** coordinates and decides.
* **Operations lead:** hands-on mitigation.
* **Communications lead:** status updates to stakeholders and customers.
* **Scribe:** keeps the timeline.

**Severity levels** should be defined in advance with response-time expectations.

**Blameless postmortem** contents:

1. Summary and impact (users, duration, SLO budget consumed).
2. Timeline (detection, mitigation and resolution times: **MTTD**, **MTTR**).
3. **Root cause and contributing factors** (techniques: "5 whys", causal trees). Focus on systems and processes, not people.
4. What went well and what went poorly.
5. **Action items** with owners and dates: prevention (tests, guardrails), detection (alerts), mitigation (runbooks, automation).

**Exam angle:** answers that blame or punish individuals are wrong. Answers that add automated guardrails, tests or alerts as postmortem actions are right. Recurring incidents caused by "misconfigured systems" (EHR) call for IaC, policy-as-code and peer review, not more manual checklists.

---

## 4. Disaster recovery as a process (not just architecture)

| Step | Practice |
|---|---|
| Define | Per application: RTO, RPO, DR pattern ([02/02 §4](../02-Designing-and-Planning/02-technical-requirements-ha-scalability-dr.md#4-disaster-recovery-rtorpo-to-pattern)) |
| Document | Runbooks: failover, data validation, DNS/LB switch, communications, **failback** |
| Automate | IaC for DR environments; scripted promotion (Cloud SQL replica promotion, Spanner automatic, Backup and DR restores); health-checked traffic shifting |
| Test | Scheduled **DR drills** (at least annually, more for critical systems); **restore tests** from backups; game days and chaos experiments; measure the **achieved** RTO/RPO |
| Secure | Immutable backups (backup vaults, Bucket Lock); backups in a separate project and region with separate IAM, against ransomware |
| Review | After each test or incident, and after major architecture changes |

**Hybrid DR** (on-premises primary, Google Cloud as DR site) is a common first cloud use case. Replicate data (Backup and DR Service, database replication, Storage Transfer), keep images and templates ready, and use Interconnect/VPN for replication traffic. Its key advantage is that you pay mostly for storage until a disaster (pilot light).

---

## 5. Supporting deployed solutions (exam guide 6.4)

* **Support model:** a Cloud Customer Care plan matched to criticality (Enhanced or Premium for production-critical workloads; Premium includes a Technical Account Manager and fastest response).
* **Case quality:** include project IDs, resource names, timestamps (UTC), error messages, impact and steps already taken. Use the correct priority.
* **Runbooks and playbooks** for known alerts. Every alert should link to a runbook.
* **On-call rotations** with escalation policies (PagerDuty/Opsgenie integrations from Cloud Monitoring).
* **Knowledge transfer:** operations readiness reviews before go-live (monitoring, alerts, runbooks, backups, DR tested, capacity, security sign-off).

---

## 6. Worked scenarios

**A. "Right after a new version of the checkout service was released, error rates rose from 0.1% to 4%."**
Roll back immediately (Cloud Deploy rollback or a Cloud Run traffic shift to the previous revision). Then compare traces and logs between revisions, write a postmortem, and add a canary with automated verification so the next bad release stops at 10%.

**B. "A VM-based app intermittently can't reach Cloud Storage since being moved to a subnet without external IPs."**
Enable **Private Google Access** on the new subnet (and check DNS and routes). Verify with Connectivity Tests.

**C. "The DR plan says RTO 2 hours, but nobody has tested it in 18 months."**
Schedule a DR drill now and measure the achieved RTO/RPO. Automate failover steps with IaC and scripts, fix gaps, and set a regular test cadence.

**D. "Users report failures; Cloud Monitoring shows healthy services; Personalized Service Health shows a regional networking incident."**
Execute the regional failover runbook (shift traffic via the global LB or DNS), communicate status, and follow Google's incident updates. Afterwards, review whether the architecture's regional dependency matches the SLO.

---

## References

* Incident management (SRE book chapter): <https://sre.google/sre-book/managing-incidents/>
* Postmortem culture: <https://sre.google/sre-book/postmortem-culture/>
* Personalized Service Health: <https://cloud.google.com/service-health/docs/overview>
* Connectivity Tests: <https://cloud.google.com/network-intelligence-center/docs/connectivity-tests/concepts/overview>
* Policy Troubleshooter: <https://cloud.google.com/policy-intelligence/docs/troubleshoot-access>
* DR planning guide: <https://cloud.google.com/architecture/dr-scenarios-planning-guide>
* Cloud Customer Care: <https://cloud.google.com/support>
