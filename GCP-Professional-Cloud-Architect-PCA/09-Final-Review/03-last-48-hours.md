# 09/03 · The Last 48 Hours

A calm, structured final review is worth more than one more mock. Follow this plan.

---

## 48–24 hours before

1. **Case studies (60 minutes).** Re-read the four breakdowns in [01-Case-Studies](../01-Case-Studies/), and recite each company's standing constraints from memory:
   * **EHR Healthcare:** 99.9% availability; regulated health data; colocation lease expiring; legacy insurance integrations stay on-premises; Active Directory; Kubernetes, MySQL, SQL Server, Redis, MongoDB; email alerts ignored; outages from misconfiguration, capacity and monitoring.
   * **Cymbal Retail:** generative-AI catalog enrichment with human-in-the-loop review; taxonomy-aligned attributes; Agent Search for Commerce ("Discovery AI"); conversational commerce to reduce call-center cost; image variants; SFTP/ETL; the same four databases as EHR; Grafana, Nagios and Elastic; PCI and PII.
   * **Altostrat Media:** already on GKE, Cloud Storage, BigQuery and Cloud Run functions; **reliability and cost are top priorities**; hybrid Kubernetes; on-premises ingestion and archival; summaries, metadata and harmful-content detection; auditable, explainable AI; chatbots; Prometheus plus email.
   * **KnightMotives Automotive:** **security paramount** after breaches; **EU data protection**; hybrid and multicloud; mainframe and old ERP; dealers have no budget for new equipment; rural connectivity; data monetization; autonomous-driving AI; upskilling.
2. **Principles (30 minutes).** Read the 16 headings in [02-first-principles-mental-models.md](../00-Exam-Strategy-and-First-Principles/02-first-principles-mental-models.md), and explain each one aloud in a sentence.
3. **Traps (30 minutes).** Read [11-trap-catalogue.md](../08-Exam-Questions-and-Sample-Papers/11-trap-catalogue.md).
4. **Your miss log.** Re-read every miss from the drills and mocks. These are *your* traps.

## 24–12 hours before

1. **Decision trees (30 minutes).** Go through [02-decision-trees-one-page.md](02-decision-trees-one-page.md) twice.
2. **Numbers (15 minutes).** Go through [01-numbers-and-limits.md](01-numbers-and-limits.md).
3. **Renames (15 minutes).** Go through [05-product-name-rosetta.md](../00-Exam-Strategy-and-First-Principles/05-product-name-rosetta.md): Agent Platform, Agent Search, Agent Runtime, Managed Service for Apache Spark and Airflow, Knowledge Catalog, Cloud Run functions, Chrome Enterprise Premium.
4. **Logistics.** Confirm the exam time and time zone, and your ID. For online proctoring, run the system check, clear the desk and close other applications.
5. **Stop studying by the evening.** Sleep.

## Exam day

* Arrive or log in early. Have water nearby if your testing rules allow it.
* **First pass (about 85 minutes):** answer, flag and move on. Never spend more than 3 minutes on a question during the first pass.
* **For every question:**
  1. Underline the constraints and the qualifier.
  2. Name the principle.
  3. Derive the answer before you read the options.
  4. Eliminate options.
  5. Break ties with the qualifier.
* **For case-study questions:** apply the company's standing constraints even when the question doesn't repeat them.
* **Second pass (about 25 minutes):** revisit flagged questions. Change an answer only with a concrete reason.
* **Last minutes:** make sure no question is blank. There's no penalty for guessing.

## Ten reminders for the exam

1. Use the most managed service that meets every requirement.
2. Choose regional for production, and multi-region only when the requirement asks for it.
3. No service account keys: use attached service accounts, Workload Identity Federation and impersonation.
4. Grant roles to groups, use predefined roles, and apply least privilege.
5. Exfiltration despite IAM means VPC Service Controls.
6. A deadline means rehost first. "No plan to move" means retain.
7. Steady load means CUDs, interruptible work means Spot, and spiky load means serverless or autoscaling.
8. RAG for knowledge, tuning for behavior, and the highest AI abstraction first.
9. Alert on SLO burn, and stop relying on email.
10. Mitigate first, then find the root cause. Postmortems are blameless.

Good luck. You've prepared from first principles, so trust the method.
