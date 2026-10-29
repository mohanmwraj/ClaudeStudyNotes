# 11 · Trap Catalogue (60 Traps)

These are the distractor patterns that cost candidates the most points on the PCA. Each trap names the attractive wrong idea, why it fails, what wins instead, and the principle that decides it. Read this file the day before the exam, and whenever a mock question surprises you.

---

## A. Architecture and availability

| # | Trap (the attractive wrong idea) | Why it fails | What wins | P |
|---|---|---|---|---|
| 1 | A single VM with snapshots counts as "highly available" | Snapshots are backups, and a single VM is a single failure domain | Regional MIG across zones plus a load balancer | P2 |
| 2 | Go multi-region active-active "to be safe" for a 99.9% requirement | Over-engineered: a large cost and complexity increase for unneeded nines | Regional multi-zone design; second region for DR | P2, P9 |
| 3 | The Cloud SQL HA standby protects against regional failure | The standby is in another **zone** of the same region | A cross-region replica (DR), or Spanner multi-region | P1 |
| 4 | A cross-region read replica fails over automatically and loses nothing | Replication is asynchronous (RPO > 0), and promotion is a separate step | Spanner multi-region for RPO 0 with automatic failover | P4 |
| 5 | A regional GKE cluster means the workloads survive a zone loss | The control plane does; workloads need replicas spread across zones and spare capacity | ≥ 2 replicas, topology spread, PDBs, headroom | P2 |
| 6 | Use session affinity to fix users losing their carts during scale-in | Keeps state on instances, so scaling and failure still lose it | Externalize state (Memorystore, Firestore) | P3 |
| 7 | Bigger machines fix latency for distant users | Latency is physics (distance) | Global LB, Premium Tier, CDN, regional back ends near users | P1 |
| 8 | DNS round robin is a global load balancer | No health- or latency-aware routing, and client caching delays failover | Global external Application Load Balancer | P1, P2 |
| 9 | You need a VPN to connect two regions of the same VPC | The VPC is global; subnets in all regions talk internally | Nothing extra; use firewall rules and routes | P1 |
| 10 | The DR plan is written, so we're covered | Untested plans fail | Scheduled drills that measure the achieved RTO/RPO | P2 |

## B. Data and storage

| # | Trap | Why it fails | What wins | P |
|---|---|---|---|---|
| 11 | BigQuery for OLTP order entry or app lookups | It's a columnar analytics warehouse, not low-latency row updates | Cloud SQL, AlloyDB, Spanner or Firestore | P4 |
| 12 | Bigtable for ad-hoc SQL joins or multi-row transactions | Wide-column store with single-row atomicity | BigQuery for analytics; Spanner for relational ACID | P4 |
| 13 | Cloud SQL for globally consistent multi-region writes | Single primary; replicas are read-only | Spanner multi-region | P4 |
| 14 | Timestamps or sequential IDs as row and primary keys | Hot-spot one split or tablet | Prefix with a high-cardinality ID; UUIDv4 or bit-reversed sequences | P4 |
| 15 | Archive or Coldline for data read weekly | Retrieval fees and minimum durations make it more expensive | Standard, Autoclass, or lifecycle rules matched to real access | P9 |
| 16 | Lifecycle `SetStorageClass` rules on an Autoclass bucket | Incompatible; Autoclass manages classes itself | Choose one: Autoclass (unknown access) or lifecycle (predictable aging) | P9 |
| 17 | Versioning makes data immutable for compliance | Owners can still delete versions | Retention policy + **Bucket Lock** (WORM) | P10 |
| 18 | Lock the retention policy now to test it | Locking is irreversible | Test unlocked; lock once requirements are confirmed | P10 |
| 19 | Memorystore as the only copy of important data | A cache can lose data | Durable system of record plus a cache | P3 |
| 20 | `gcloud storage cp` 500 TB over a 1 Gbps link | About 50 days of saturated transfer | Transfer Appliance | P10 |
| 21 | Dump and restore for "minimal downtime" database migration | Hours of downtime | Database Migration Service continuous (CDC) migration | P15 |
| 22 | Datastream to migrate an OLTP database | Datastream is analytics replication (to BigQuery or Cloud Storage) | Database Migration Service | P15 |
| 23 | Pick Data Catalog, Pub/Sub Lite or Memcached for new designs | Legacy, turned down or deprecated | Knowledge Catalog, Pub/Sub or Managed Kafka, Memorystore for Valkey | — |

## C. Compute and platforms

| # | Trap | Why it fails | What wins | P |
|---|---|---|---|---|
| 24 | GKE Standard gives the lowest operational overhead | Autopilot is the low-ops mode | GKE Autopilot (or Cloud Run) | P5 |
| 25 | Cloud Run functions for multi-hour or heavy processing | Designed for short event handlers | Cloud Run jobs or services, Batch, GKE, managed services (Transcoder API) | P5 |
| 26 | App Engine for a new greenfield container service | Google recommends Cloud Run for new workloads | Cloud Run | P5 |
| 27 | Spot VMs for databases or SLA-bound serving | Preemptible at any time | Spot only for fault-tolerant, checkpointed work | P9 |
| 28 | Preemptible VMs when Spot is offered | Legacy (24-hour limit) | Spot VMs | — |
| 29 | Rewrite everything before the data-center lease expires | Misses the deadline | Rehost or replatform first (VMware Engine, Migrate to VMs, GKE for existing containers) | P15 |
| 30 | Migrate the systems the case study says will stay | Contradicts a stated constraint (EHR legacy integrations, KnightMotives mainframe short term) | Retain, plus hybrid connectivity | P15 |
| 31 | Container Registry, Cloud IoT Core or Deployment Manager in an answer | Retired or end of support | Artifact Registry, partner MQTT broker → Pub/Sub, Terraform or Infrastructure Manager | — |

## D. Networking

| # | Trap | Why it fails | What wins | P |
|---|---|---|---|---|
| 32 | VPC peering is transitive | It isn't: A↔B and B↔C doesn't give A↔C | Shared VPC, NCC hub, or explicit peering | P14 |
| 33 | Peer VPCs that have overlapping ranges | Not allowed | Private Service Connect (service-level) or re-IP | P14 |
| 34 | Direct or Carrier Peering for private VPC access | These reach public Google services, with no SLA | Interconnect or HA VPN | P14 |
| 35 | One Interconnect connection for production | No SLA | 2 connections (99.9%); 4 connections in the documented topologies (99.99%) | P2 |
| 36 | Partner Interconnect for 100 Gbps | Attachments top out at 50 Gbps | Dedicated Interconnect (10/100/400 Gbps) | P14 |
| 37 | VPN for a sustained 20+ Gbps | About 3 Gbps per tunnel; impractical at scale | Interconnect | P14 |
| 38 | Public IPs plus SSH from the internet for administration | Exposure | IAP TCP forwarding + OS Login | P6 |
| 39 | Cloud NAT gives VMs access to Google APIs | NAT is for internet egress | Private Google Access / PSC for Google APIs | P14 |
| 40 | A proxy load balancer when the back end needs the client IP at L4 | Proxies replace the source IP | Passthrough Network Load Balancer (or X-Forwarded-For at L7) | P14 |
| 41 | Network tags as a security boundary | Anyone who can edit the instance can set them | Service-account or secure-tag firewall targets (IAM-governed) | P6 |

## E. Security and compliance

| # | Trap | Why it fails | What wins | P |
|---|---|---|---|---|
| 42 | Firewall rules stop BigQuery or Cloud Storage exfiltration | Firewalls don't govern Google API calls | VPC Service Controls | P6 |
| 43 | Remove an inherited permission by granting a different role lower down | Allow policies are additive | IAM deny policy (or redesign the grants) | P7 |
| 44 | Store service account keys in Secret Manager "securely" | Still a long-lived key | Attached SAs, Workload Identity Federation, impersonation | P6 |
| 45 | API keys to authorize access to Cloud Storage or BigQuery data | API keys identify projects; they don't authorize data access | IAM principals with OAuth tokens | P6 |
| 46 | Grant Editor "to unblock the team" | Basic roles violate least privilege | Predefined or custom roles to groups | P6 |
| 47 | Use Managed Microsoft AD for console sign-in | It's for AD-dependent workloads | Cloud Identity + GCDS + SSO, or Workforce Identity Federation | P6 |
| 48 | Workload Identity Federation for human users | It's for workloads | **Workforce** Identity Federation for people | P6 |
| 49 | Answer "encrypted at rest" with CMEK | Default encryption already does that; CMEK is about key *control* | CMEK, HSM or EKM only for custody requirements | P11 |
| 50 | Cloud HSM satisfies "keys must never be in Google" | Google operates the HSMs | Cloud EKM (+ Key Access Justifications) | P11 |
| 51 | Vulnerability scanning prevents bad images from running | Scanning detects; it doesn't enforce | Binary Authorization | P12 |
| 52 | Cloud Armor or a WAF stops prompt injection | Doesn't understand prompts | Model Armor | P16 |
| 53 | Google's certifications make our workload compliant | Shared responsibility | BAA, covered services, your own controls and audits | P6 |
| 54 | An organization policy for location = full sovereignty | Doesn't cover personnel access or regime monitoring | Assured Workloads (+ EKM, Access Approval as required) | P7 |

## F. Operations, processes and AI

| # | Trap | Why it fails | What wins | P |
|---|---|---|---|---|
| 55 | Add more email alerts (EHR, Altostrat) | Email alerts are already ignored | SLO burn-rate alerts routed to on-call, with runbooks | P13 |
| 56 | Alert on CPU 80% | Cause-based, noisy | Symptom-based SLO alerting; CPU on dashboards | P13 |
| 57 | Debug first while an outage is ongoing | Prolongs impact | Mitigate first (roll back, shift traffic), then investigate | P13 |
| 58 | Blame or discipline the engineer | Discourages learning; the system stays fragile | Blameless postmortem with systemic action items | P12 |
| 59 | Buy CUDs before rightsizing, sized for peak | Locks in waste | Rightsize, then commit the steady baseline; autoscale peaks | P9 |
| 60 | Fine-tune or train a custom model to add knowledge | Knowledge changes; fine-tuning doesn't give citations or freshness | RAG and grounding (Agent Search, RAG Engine); prompting and response schemas first | P16 |

---

## The meta-trap: ignoring the qualifier

Many PCA questions have two or three *working* answers. The qualifier picks the winner:

* **"Least operational overhead"** → most managed.
* **"Most cost-effective"** → cheapest that still meets every requirement.
* **"Google-recommended"** → the documented pattern.
* **"Minimal changes"** → least disruption.

When stuck between two options, re-read the qualifier, then the case study's standing constraints.
