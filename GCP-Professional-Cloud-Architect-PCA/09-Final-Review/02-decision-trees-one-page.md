# 09/02 · All the Decision Trees on One Page

These are compressed versions of the selection logic in the notes. Rehearse them until each takes under 30 seconds.

---

## Compute

```text
VMware as-is, fast exit ............................ VMware Engine
Oracle RAC / certified bare metal .................. Bare Metal Solution / Oracle Database@Google Cloud
Short event glue (file landed, message, webhook) ... Cloud Run functions
Stateless container (HTTP or job), no node control . Cloud Run (services / jobs / worker pools)
Needs K8s APIs, Helm, mesh, GPUs at scale, portability
                                                 ... GKE Autopilot  (Standard only for node-level control)
OS control, licenses, legacy, lift-and-shift ....... Compute Engine (MIG; Spot for batch; sole-tenant for BYOL)
Batch HPC / array jobs on VMs ...................... Batch
K8s on-prem / edge / other clouds .................. Google Distributed Cloud / attached clusters in a GKE fleet
```

## Database and storage

```text
Analytics over large history ..................... BigQuery (+ Google Cloud Lakehouse for Iceberg)
Relational, global scale or 99.999% .............. Spanner
PostgreSQL, high performance / HTAP / vectors .... AlloyDB
Standard MySQL/PostgreSQL/SQL Server, 1 region ... Cloud SQL
Huge throughput key/row, time series ............. Bigtable (design the row key!)
Mobile/web documents, offline sync ............... Firestore
Cache / sessions ................................. Memorystore (Valkey / Redis)
Objects / media / lake / backups ................. Cloud Storage (Autoclass if access unknown)
Shared NFS ....................................... Filestore (Regional/Enterprise for HA) / NetApp Volumes
HPC/AI parallel file system ...................... Managed Lustre
Block for one VM ................................. Persistent Disk / Hyperdisk (regional for HA); Local SSD = scratch
```

## Data processing

```text
Messaging/ingest ........... Pub/Sub   (Kafka API required → Managed Service for Apache Kafka)
Stream/batch transforms .... Dataflow
Existing Spark/Hadoop ...... Managed Service for Apache Spark (ex-Dataproc; serverless or clusters)
SQL transforms ............. BigQuery (+ Dataform)
No-transform load .......... Pub/Sub BigQuery subscription / BigQuery load jobs
CDC to analytics ........... Datastream
Data DAG orchestration ..... Managed Service for Apache Airflow (ex-Composer)
Service orchestration ...... Workflows      Event routing ... Eventarc      Cron ... Cloud Scheduler
Governance/lineage ......... Knowledge Catalog (ex-Dataplex)     Share data ... BigQuery sharing / clean rooms
```

## AI

```text
Employee search + agents + NotebookLM ........... Gemini Enterprise
Customer site search / RAG ...................... Agent Search (ex-Vertex AI Search)
Retail search / recommendations ................. Agent Search for Commerce / Recommendations
Contact center .................................. Customer Engagement Suite (Conversational Agents, Agent Assist)
Exact pre-trained task .......................... Vision / Video Intelligence / Speech-to-Text / Translation / Document AI
Flexible multimodal reasoning, extraction ....... Gemini (+ response schema)       Images ... Imagen      Video ... Veo
Needs your facts ................................ RAG / grounding (never fine-tune for knowledge)
Needs style/behaviour ........................... Tuning
Agents with tools/memory ........................ ADK + Agent Runtime (ex-Agent Engine)
MLOps ........................................... Agent Platform Pipelines, Feature Store, Model Registry, Model Monitoring
Big training .................................... AI Hypercomputer: TPU/GPU; DWS calendar (deadline) / flex-start / Spot
Guardrails ...................................... Model Armor + Sensitive Data Protection + HITL
```

## Networking

```text
Same org, central network team ............ Shared VPC
Few VPCs, no overlap, separate admins ..... VPC Peering (non-transitive)
Expose one service / overlap / cross-org .. Private Service Connect
Many VPCs + sites, hub-and-spoke .......... Network Connectivity Center
VM → Google APIs without public IP ........ Private Google Access (or PSC endpoint)
VM → internet egress ...................... Cloud NAT
Admin access .............................. IAP TCP forwarding + OS Login
Hybrid: quick/≤ few Gbps/encrypted ........ HA VPN (99.99%)
Hybrid: high bandwidth, colo .............. Dedicated Interconnect (10/100/400G)
Hybrid: no colo / < 10 Gbps ............... Partner Interconnect (≤ 50G attachments)
Other cloud ............................... Cross-Cloud Interconnect
Encrypt private link ...................... MACsec or HA VPN over Interconnect
```

## Load balancing

```text
HTTP(S), global users ............... Global external Application LB (+ CDN, Cloud Armor, IAP)
HTTP(S), one region / residency ..... Regional external Application LB
Internal HTTP, multi-region ......... Cross-region internal Application LB
Non-HTTP TCP, TLS offload, global ... Global external proxy Network LB
UDP / keep client IP ................ External passthrough Network LB
Internal TCP/UDP .................... Internal passthrough Network LB
Serverless / on-prem back ends ...... Serverless NEG / hybrid connectivity NEG
```

## Security: threat to control

```text
Exfiltration despite valid IAM ........ VPC Service Controls
Who can do what ....................... IAM (groups, predefined roles); remove inherited → deny policy
What can be configured / where ........ Organization policy (locations, no SA keys, no external IP, domain sharing)
Org-wide network guardrail ............ Hierarchical firewall policy
East-west intrusion prevention ........ Cloud NGFW Enterprise (IPS)
Edge L7 attacks, DDoS, bots ........... Cloud Armor
User access to apps without VPN ....... IAP + context-aware access (Chrome Enterprise Premium)
Workloads outside Google, no keys ..... Workload Identity Federation    People from external IdP ... Workforce IF
Temporary elevation ................... Impersonation / Privileged Access Manager
Key control / revoke .................. CMEK   HSM hardware ... Cloud HSM   Keys outside Google ... Cloud EKM (+KAJ)
Secrets ............................... Secret Manager     PII discovery / de-identification ... Sensitive Data Protection
Only trusted images run ............... Binary Authorization
Prompt injection / LLM data leaks ..... Model Armor
Posture + threats ..................... Security Command Center   SIEM/SOAR ... Google Security Operations
Regime (FedRAMP, sovereignty) ......... Assured Workloads
```

## DR pattern by RTO/RPO

```text
Hours–days RTO, hours RPO ........ Backup & restore (cold)
~1 h RTO, minutes RPO ............ Pilot light / warm standby (cross-region replica, scaled-down stack)
Near-zero RTO/RPO ................ Multi-site active-active (global LB + Spanner/Firestore multi-region)
```

## Migration tools

```text
Assess ............ Migration Center
VMs ............... Migrate to Virtual Machines      VMware as-is ... VMware Engine + HCX
VMs → containers .. Migrate to Containers
Databases ......... Database Migration Service (continuous); Oracle → PostgreSQL via conversion workspace
Files online ...... Storage Transfer Service         Files offline ... Transfer Appliance
Warehouse ......... BigQuery Migration Service
Mainframe ......... Retain + Mainframe Connector + incremental modernization
```
