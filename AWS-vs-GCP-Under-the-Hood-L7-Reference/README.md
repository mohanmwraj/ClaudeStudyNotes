# AWS vs GCP Under the Hood: L7 Cloud Infrastructure Reference

A first-principles comparison of AWS and Google Cloud at the level of hypervisors, network fabrics, storage engines and control planes. It's for Principal backend, data and AI architects who need to translate architectures between the two clouds, pass AWS SAP-C02 scenario questions, and hold up in FAANG L7 infrastructure interviews. Service-name mapping (`S3 = GCS`) is the starting point, not the content. Each file explains *why* the two designs differ, which limits follow from that, and what breaks first in production.

## Status

| Folder | Files | Words | Listings | Gate |
|---|---|---|---|---|
| [`01-Virtualization-Compute-and-Kubernetes-Internals/`](01-Virtualization-Compute-and-Kubernetes-Internals/) | 3 | ~37.6k | 4 (Python) | Passed (2026-10-31) |
| [`02-Global-Networking-Hybrid-Connectivity-and-Zero-Trust-VPC/`](02-Global-Networking-Hybrid-Connectivity-and-Zero-Trust-VPC/) | 3 | ~29.3k | 3 (Python) | Passed (2026-10-31) |
| [`03-Distributed-Storage-Databases-and-Lakehouse-Internals/`](03-Distributed-Storage-Databases-and-Lakehouse-Internals/) | 4 | ~33.0k | 4 (Python) | Passed (2026-10-31) |
| [`04-Messaging-Streaming-and-Data-Pipeline-Comparison/`](04-Messaging-Streaming-and-Data-Pipeline-Comparison/) | 2 | ~16.3k | 2 (Python) | Passed (2026-10-31) |
| [`05-IAM-KMS-Cryptography-and-Multi-Tenant-Governance/`](05-IAM-KMS-Cryptography-and-Multi-Tenant-Governance/) | 3 | ~23.9k | 3 (Python) | Passed (2026-10-31) |
| [`06-Enterprise-Cloud-Migrations-Resiliency-and-FinOps/`](06-Enterprise-Cloud-Migrations-Resiliency-and-FinOps/) | 3 | ~21.8k | 3 (Python) | Passed (2026-10-31) |
| [`07-25-Master-Multi-Cloud-and-SAP-C02-Bar-Raiser-Scenarios/`](07-25-Master-Multi-Cloud-and-SAP-C02-Bar-Raiser-Scenarios/) | 2 | ~23.8k | 1 (Python, run on each file) | Passed (2026-10-31) |
| **Total** | **20** | **~185.7k** | **20** | **All 7 folders passed** |

The KB is **complete**. Across the 20 files:
- **205 bar-raiser chains**;
- **133 original SAP-C02 scenarios**, with answer letters A38 B40 C38 D37 E4;
- **domain coverage** D1 20, D2 45, D3 44, D4 24. Folder 07 alone is weighted to the exam: 6/8/6/5 for 26/29/25/20%;
- **20 deterministic listings**, each re-run on its final file by the gate.

**Suggested order:**
1. Folders 01–06 for the mechanics.
2. Folder 07 for the 25 master scenarios that combine them.
3. Two weeks before SAP-C02, go back through every §9.2 question in the KB under time.

## Folder 01 · Virtualization, compute and Kubernetes internals

| File | Covers | Listing |
|---|---|---|
| [01.1 Nitro vs Titanium](01-Virtualization-Compute-and-Kubernetes-Internals/01-aws-nitro-hypervisor-ec2-placement-groups-vs-gcp-titanium-compute.md) | Where the virtualization tax goes. Nitro cards, hypervisor and Isolation Engine (GA 2026-06-11). KVM with Google's own VMM, Borg, Andromeda and Titanium. Placement groups (cluster, partition, spread, precision time) vs compact and spread policies. Live migration vs scheduled events. ENA allowances. 19 failure modes | `placement_planner.py` |
| [01.2 EKS vs GKE data plane](01-Virtualization-Compute-and-Kubernetes-Internals/02-eks-vs-gke-datapath-v2-ebpf-cilium-pod-ip-cni-and-karpenter-autoscaling.md) | VPC CNI warm pools, prefix delegation and fragmentation. GKE alias IPs and the 2× rule. iptables vs eBPF (Dataplane V2/Cilium). Security groups for pods vs NetworkPolicy. DNS and conntrack. Cluster Autoscaler vs Karpenter 1.15 vs EKS Auto Mode vs ComputeClasses. Control-plane tiers. 20 failure modes | `pod_ip_planner.py`, `consolidation_sim.py` |
| [01.3 Lambda vs Cloud Run](01-Virtualization-Compute-and-Kubernetes-Internals/03-serverless-internals-aws-lambda-firecracker-microvms-vs-cloud-run-borg.md) | The isolation spectrum. Firecracker and the invoke path. The scaling contract (1,000 per 10 s, 10 rps per environment). SnapStart. Hyperplane ENIs. The 2026 Lambda family (Event Functions, durable functions, Managed Instances, MicroVMs, Web Functions). Cloud Run gen1/gen2, the autoscaler formulas and billing modes. 23 failure modes | `serverless_scaling_sim.py` |

Folder 01 has 30 bar-raiser chains and 18 original SAP-C02 scenarios. The answer letters are balanced: A5 B5 C5 D5 E2. The scenarios cover all four SAP-C02 domains.

**Results worth remembering (all reproduced by the listings):**
- **Placement.**
  - A 24-broker spread group can't place an eighth broker in an AZ.
  - Compute Engine spread placement beyond 8 VMs reached a 50% largest-domain share with 12 VMs on 4 domains; pinning domains gives 25%.
  - In a single AZ without a placement group, a rack failure costs some RF=3 sets their majority at every rack count tried. A partition PG with rack-aware placement made that 0 in every trial.
- **Pod IPs.**
  - The planner reproduces all 7 published `eni-max-pods` values and all 4 GKE documentation examples.
  - A /20 subnet at 30% random occupancy has 0 free aligned /28s.
  - A 2,000-node × 110-pod fleet needs a /13 Pod range on GKE, and 250–300k VPC addresses (4–5 /16 blocks) on EKS.
- **Autoscaling [E].** Group-less provisioning cost 13% less than a single m5 node group at scale-up, and consolidation ended 5% cheaper after a traffic drop. Both approaches move pods.
- **Serverless.**
  - A 0 → 30,000 rps step at 120 ms takes Lambda 26 s to reach steady state, with ~292k requests throttled.
  - For an I/O-bound API, Cloud Run instance-based billing costs $246/month vs $518–622 for Lambda Event Functions. For a 2 rps trickle, Lambda is 3–6× cheaper.

## Folder 02 · Global networking, hybrid connectivity and zero-trust VPC

| File | Covers | Listing |
|---|---|---|
| [02.1 Regional VPC vs global VPC](02-Global-Networking-Hybrid-Connectivity-and-Zero-Trust-VPC/01-aws-regional-vpc-tgw-privatelink-vs-gcp-global-andromeda-vpc-psc.md) | Route vs publish. Non-transitive peering. TGW association/propagation, the evaluation order, AZ affinity and appliance mode, quotas and $0.02/GB processing. Cloud WAN. PrivateLink, VPC Lattice and VPC sharing. Andromeda global networks, hierarchical firewall policies, Shared VPC, peering-group quotas, NCC mesh/star, PSC, Cloud NAT, Maglev. 17 failure modes | `reachability_model.py` |
| [02.2 Hybrid BGP](02-Global-Networking-Hybrid-Connectivity-and-Zero-Trust-VPC/02-hybrid-bgp-routing-direct-connect-vif-macsec-vs-cloud-interconnect-ha-vpn.md) | DX connections, VIFs, DXGW, prefix budgets (session idle on overflow), communities 7224:7x00, timers and BFD, resiliency models, MACsec, large VPN tunnels (5 Gbps). Interconnect SLA topologies, Cloud Router priority and global mode, HA VPN 250k pps. Hybrid DNS (Resolver 10k QPS per IP, ~1.5k with conntrack). AWS Interconnect–multicloud (GA 2026-04-14). 17 failure modes | `hybrid_path_sim.py` |
| [02.3 Global edge](02-Global-Networking-Hybrid-Connectivity-and-Zero-Trust-VPC/03-global-edge-cloudfront-global-accelerator-route53-arc-vs-gcp-anycast-cdn-armor.md) | DNS vs anycast steering, hot vs cold potato, CloudFront tiers and edge compute, Global Accelerator, Route 53 health semantics (the 18% rule), ARC routing controls and zonal autoshift, Shield and WAF. GFE and the global ALB, Network Service Tiers, Cloud CDN/Media CDN, Cloud Armor. 16 failure modes | `edge_failover_sim.py` |

**Results from the Folder 02 listings:**
- Peering is non-transitive on both clouds. The TGW prod/dev/shared matrix holds in both directions.
- A 126-VPC peering mesh needs 7,875 connections.
- On a TGW, prepending on DX never moves traffic to a VPN; only a more specific prefix or a withdrawal does.
- Two DX links in one location still leave ~106 min/yr of full outage [E], against ~0.8 with two locations.
- Route 53 failover reaches 99% at 90 s (TTL 60, fast checks), 387 s (TTL 300), and 665 s with 5% sticky resolvers.
- A regional cache tier cut origin load by 59% [E].

## Folder 03 · Distributed storage, databases and lakehouse internals

| File | Covers | Listing |
|---|---|---|
| [03.1 Object storage](03-Distributed-Storage-Databases-and-Lakehouse-Internals/01-object-storage-s3-strong-consistency-prefix-partitioning-vs-gcs-colossus.md) | Index + blob design. S3 strong consistency (journal + witness), per-prefix rates, conditional writes, 50 TB objects, classes and the 128 KB minimum, Express One Zone, RTC, Object Lock. GCS on Colossus: the 1k/5k start with doubling every 20 min, 1 write/s per object, generation preconditions, dual-region/turbo, HNS, soft delete, Bucket Lock. 15 failure modes | `object_store_planner.py` |
| [03.2 Relational](03-Distributed-Storage-Databases-and-Lakehouse-Internals/02-relational-internals-aurora-storage-quorum-rds-proxy-vs-alloydb-and-spanner.md) | Aurora's log-is-the-database design, the 4/6 quorum and AZ+1, 10 GB segments, replicas, Global Database, Serverless v2, I/O-Optimized, Limitless, DSQL (OCC), RDS Proxy and pinning. AlloyDB log processing and the columnar engine. Spanner Paxos splits, TrueTime commit wait, stale reads, per-node capacity, key design. 15 failure modes | `quorum_replication_sim.py` |
| [03.3 NoSQL](03-Distributed-Storage-Databases-and-Lakehouse-Internals/03-nosql-internals-dynamodb-gsi-dax-streams-vs-bigtable-and-firestore.md) | DynamoDB request routers, Multi-Paxos partitions, GAC, 3,000/1,000/10 GB per partition, split for heat, GSI back-pressure, LSI 10 GB, transactions, Streams, DAX, global tables MREC/MRSC. Bigtable tablets on Colossus, per-node limits, app profiles, Data Boost, row-key design. Firestore limits. 16 failure modes | `partition_heat_sim.py` |
| [03.4 Analytics](03-Distributed-Storage-Databases-and-Lakehouse-Internals/04-analytics-redshift-athena-glue-iceberg-vs-bigquery-dremel-capacitor-storage-api.md) | Redshift RA3 (distribution, zone maps, Serverless RPUs). Athena billing on compressed bytes. Glue, Lake Formation, Iceberg commits and maintenance, S3 Tables. Dremel (serving tree, slots, shuffle tier), Capacitor, logical-byte billing, editions, Storage Read/Write APIs, BigQuery Iceberg, Omni. 15 failure modes | `scan_cost_estimator.py` |

**Results from the Folder 03 listings:**
- **Object stores:**
  - 16 hash prefixes give 56k writes/s on S3;
  - GCS takes 80 min to ramp to 16k writes/s (20 min with HNS);
  - IA costs more than Standard below ~70 KB per object.
- **Quorums:** Aurora keeps reads at AZ+1, where a 3-replica majority is down. A 10 GB segment repairs in 8 s at 10 Gbps.
- **Spanner [E]:** regional commit latency is set by ε (2ε), and multi-region by the quorum RTT.
- **DynamoDB [E]:** Zipf 1.2 throttles 20.5% of writes until the hot keys are sharded 8 ways.
- **Bigtable [E]:** timestamp-first keys put 100% of writes on one node, and 10 salts still concentrate 20% on one.
- **Analytics [E]:** CSV → partitioned Parquet cuts one query from $50 to $0.0096. BigQuery logical-byte billing is ~6× Athena for the same layout. 100 slots ≈ 701 TiB of on-demand per month.

## Folder 04 · Messaging, streaming and data pipelines

| File | Covers | Listing |
|---|---|---|
| [04.1 Messaging](04-Messaging-Streaming-and-Data-Pipeline-Comparison/01-kinesis-sqs-sns-eventbridge-msk-vs-gcp-pubsub-and-kafka-tradeoffs.md) | Queue vs log vs topic vs router. Delivery is at-least-once end-to-end. Ordering scopes. SQS (1 MiB, FIFO, visibility, DLQ redrive), SNS, EventBridge (retries 24 h / 185, archive/replay, Pipes), Kinesis (shards, EFO, 10 MiB records), MSK Express. Pub/Sub (global, quotas, ordering keys at 1 MB/s, EOD, seek, 31-day topic retention, BigQuery subscriptions), Managed Kafka, Eventarc. 17 failure modes | `delivery_semantics_sim.py` |
| [04.2 Pipelines](04-Messaging-Streaming-and-Data-Pipeline-Comparison/02-aws-glue-emr-flink-step-functions-vs-gcp-dataflow-composer-airflow-dataproc.md) | Where state and shuffle live. Exactly-once as an engine + sink contract. Glue (Flex, bookmarks), EMR (fleets, Spot task nodes, Serverless), Managed Flink (KPUs, snapshot-restart rescale), Step Functions Standard/Express/Distributed Map, MWAA. Dataflow (Streaming Engine, Shuffle, rebalancing, at-least-once mode), Managed Spark (formerly Dataproc), Managed Airflow (formerly Composer), Workflows. 16 failure modes | `pipeline_tradeoffs.py` |

**Results from the Folder 04 listings:**
- Four consumers need 120 Kinesis shards with shared reads but 60 with EFO.
- A 30 s visibility timeout duplicates 45% of 20 s-median work [E]; lease extension leaves only crash duplicates.
- A Flink checkpoint at 60 s gives ~38 s sink lag at ~1.3% overhead [E].
- At 100M executions/month, Step Functions Standard costs ~$25k against ~$413 for Express.

## Folder 05 · IAM, KMS, cryptography and multi-tenant governance

| File | Covers | Listing |
|---|---|---|
| [05.1 AWS IAM evaluation](05-IAM-KMS-Cryptography-and-Multi-Tenant-Governance/01-aws-iam-evaluation-logic-scp-permission-boundaries-abac-sts-cross-account.md) | Grants vs ceilings. The documented evaluation order (deny → RCP → SCP → resource → identity → boundary → session). User/session vs role-ARN resource grants. SCPs with the full IAM language (2025-09). RCPs. Boundary-based delegation. ABAC with session tags. Data perimeters. STS (ExternalId, role chaining 1 h, web identity, Pod Identity, Roles Anywhere). 16 failure modes | `iam_policy_evaluator.py` |
| [05.2 GCP IAM and VPC-SC](05-IAM-KMS-Cryptography-and-Multi-Tenant-Governance/02-gcp-iam-hierarchy-workload-identity-federation-and-vpc-service-controls.md) | Inherited allow policies, deny policies (checked first, 500 per resource), PAB (fails closed), IAM Conditions. Hierarchy design. Service-account escalation paths. Workload Identity Federation (AWS/OIDC/X.509/GKE). Org Policy (custom constraints, merge vs replace). VPC Service Controls (ingress/egress, access levels, dry run, restricted VIP). PAM. AWS ↔ GCP guardrail map. 15 failure modes | `gcp_access_resolver.py` |
| [05.3 KMS and confidential computing](05-IAM-KMS-Cryptography-and-Multi-Tenant-Governance/03-kms-envelope-encryption-cloudhsm-nitro-enclaves-and-confidential-computing.md) | Envelope mechanics. Key policies, grants, encryption context. KMS quotas (10k/20k/100k; custom key stores 1,800). Cloud KMS token quotas (~1,000 software ops/s, 2026). CloudHSM, XKS, single-tenant Cloud HSM (GA 2025-12), EKM + KAJ, Autokey. Rotation vs compromise. Nitro Enclaves attestation-gated release. Confidential VMs and Confidential Space. 15 failure modes | `kms_request_planner.py` |

**Results from the Folder 05 listings:**
- The IAM evaluator reproduces all 13 documented decisions, and the GCP resolver all 14 (IAM, Org Policy, VPC-SC).
- HKDF matches RFC 5869 test case 1 exactly.
- At 40k writes/s, per-object data keys exceed the default AWS KMS quota 4×, Cloud KMS 40× and a CloudHSM key store 22×, costing ~$311k/month in requests. Caching cuts this to ~4 calls/s, and bucket keys to ~0.

## Folder 06 · Enterprise migrations, resiliency and FinOps

| File | Covers | Listing |
|---|---|---|
| [06.1 Migrations](06-Enterprise-Cloud-Migrations-Resiliency-and-FinOps/01-large-scale-migration-patterns-strangler-fig-cdc-dms-datastream-and-cutover.md) | The 7 Rs as decisions. The CDC convergence condition. No dual writes (outbox). DMS (capture per engine, apply modes, validation, Schema Conversion), Blue/Green, MGN, EVS, AWS Transform, DataSync. Database Migration Service, Datastream, Migrate to VMs, GCVE, Storage Transfer, BigQuery Migration. Debezium. Strangler fig. Cutover and reverse-CDC runbooks. 14 failure modes | `cutover_planner.py` |
| [06.2 Multi-Region DR](06-Enterprise-Cloud-Migrations-Resiliency-and-FinOps/02-multi-region-dr-pilot-light-warm-standby-active-active-and-cell-failover.md) | RTO as a sum, RPO from replication. Static stability. The four strategies on each cloud (DRS, AWS Backup Vault Lock / air-gapped vaults, Aurora Global; PD async replication, Backup and DR, Spanner multi-region). Zonal autoshift. FIS. Service tiering. Cells and shuffle sharding. Drills and failback. 14 failure modes | `dr_calculator.py` |
| [06.3 FinOps](06-Enterprise-Cloud-Migrations-Resiliency-and-FinOps/03-cloud-finops-nat-gateway-cross-az-traps-savings-plans-and-storage-tiering.md) | Path pricing. NAT leaks and endpoints / Private Google Access. Hidden cross-AZ traffic (Kafka fetch-from-follower, topology-aware routing). Savings Plans/RIs vs CUDs/SUDs and break-even. Spot. gp3, Intelligent-Tiering/Autoclass. Observability cost. FinOps operating model. 15 failure modes | `network_cost_model.py` |

**Results from the Folder 06 listings:**
- CDC with apply equal to the average change rate never converges [E]. At 10 MB/s apply it converges, with a ~10-min trough freeze vs +63 min at peak.
- Pilot light wins total cost at the stated inputs. Warm standby only pays above ~$4.6M/h of downtime [E].
- Shuffle sharding with 5 of 100 workers fully overlaps for 1.3e-6% of customers.
- A gateway endpoint saves exactly 50 TB × $0.045.
- Zone-aware routing cuts 200 TB of chatter from $2,667 to $400/month.
- Intelligent-Tiering halves 1 PB (2 MB objects, 10/30/60 mix).

## Folder 07 · 25 master multi-cloud and SAP-C02 bar-raiser scenarios

| File | Covers | Listing |
|---|---|---|
| [07.1 MS-01 to MS-12](07-25-Master-Multi-Cloud-and-SAP-C02-Bar-Raiser-Scenarios/01-scenarios-01-to-12-hybrid-networking-security-and-multi-account-org-design.md) | Multi-cloud landing zone. 99.99% hybrid connectivity with MACsec and BFD. Segmented hub with symmetric inspection. Hybrid DNS at 400 VPCs. SaaS private connectivity with overlapping CIDRs. Data perimeter (RCP/SCP/endpoint policies vs VPC-SC). Keyless CI/CD and workload identity. Immutable org-wide logging. HYOK with attested processing. Global edge with UDP and static IPs. Tiered tenant isolation. Cross-cloud data partnership. 12 failure modes | `scenario_coverage.py` |
| [07.2 MS-13 to MS-25](07-25-Master-Multi-Cloud-and-SAP-C02-Bar-Raiser-Scenarios/02-scenarios-13-to-25-zero-downtime-migration-dr-serverless-and-data-platforms.md) | Oracle → PostgreSQL with a 15-minute freeze. 2,000-VM data-center exit. Strangler fig with outbox and CDC. RPO-0 ledger (DSQL/MRSC vs Spanner). Warm standby with static stability. Ransomware-resilient backups. Serverless bursts. Exactly-once effects in an order saga. Kafka migration with offset translation. Hadoop → lakehouse. A 30% cost program. Governed RAG (2026 names flagged). Cell-based SaaS with wave deploys. 17 failure modes | `scenario_coverage.py` |

Every master scenario has five parts: **Situation**, **Constraints**, **AWS design**, **GCP design**, and **Decision and trade-offs**. Each links to at least two mechanism files and maps to one bar-raiser chain and one SAP-C02 question. `scenario_coverage.py` enforces all of this on each file.

**What Folder 07 shows, using numbers from the earlier listings:**
- **Migration (MS-13):** the binding constraint is usually *convergence* (apply > peak change rate) or *validation time*, not bytes copied.
- **DR (MS-16, MS-17):**
  - RPO is set by the replication mode, so RPO 0 rules out every asynchronous design.
  - An RTO requirement eliminates options before the cost model ranks them. At the 06.2 inputs, pilot light is cheapest but fails a 30-minute RTO.
- **Serverless bursts (MS-19):** these are scaling-*rate* problems. 3,600 environments are needed and the quota is 5,000, yet 292k requests were throttled.
- **Cost (MS-23):** a ~31% cost reduction [E] comes from paths, commitment floors, tiers, telemetry and right-sizing, not from flat budget cuts.
- **GenAI (MS-24):** entitlement filtering must happen at retrieval, before text reaches the model.

## Conventions

- **Spine of every file.** It's checked by the gate, in this order:
  1. `0. Orientation`
  2. `1. First principles`
  3. **Side-by-side architectural Rosetta matrix** (≥ 12 rows)
  4. **Internal mechanics** (one or more sections)
  5. **Failure modes, throttling limits and quota traps**
  6. **Architecture diagrams** (≥ 2 Mermaid + ≥ 1 ASCII)
  7. **Bar-raiser chains and SAP-C02 scenarios**
  8. Checklist
  9. References (last)
- **Labels.**
  - **[D]** documented by the provider.
  - **[E]** an estimate or model output with stated inputs.
  - **⚠** inferred from talks or papers, or not publicly documented. Say how you know before using it in an interview.
- **Bar-raiser chains** use `<details><summary><b>Qn · …</b></summary>` with four bold labels in order: **Initial Prompt.**, **L5 Answer.**, **Why L5 Stalls.**, **L7 Answer.**
- **SAP-C02 scenarios** use `<details><summary><b>Sn · SAP-C02 · Domain d · Select ONE|TWO</b></summary>`. Each has a **Scenario.**, options **A.**–**D.** (or **E.**), an `**Answer: X**` line, and a correct/wrong rationale for every option.
  - **Every scenario is an original formulation.** No exam dumps or recalled items.
  - Scenarios that use 2026 services (Lambda MicroVMs, Lambda Web Functions) are flagged because they may postdate the exam's item bank.
- **Master scenarios** (Folder 07) use `### MS-NN · title` headings. Their SAP-C02 questions carry a `**Maps to:** MS-NN` line.
- **Scope labels:** L5 = Senior, L6 = Staff, L7 = Principal / Senior Staff.
- **Spelling:** American English. Prices are USD list prices (us-east-1 for AWS, Tier 1 for Cloud Run) unless stated otherwise.

## Verification method

The build harness lives outside the KB. Each file is assembled from a template in which:
- `<!-- include:NAME -->` inserts a listing;
- `<!-- run:NAME -->` inserts that listing's real output.

The gate (`gate.py`) then checks the final files:
1. The spine order, the Rosetta table size, Mermaid syntax (known diagram type, balanced `subgraph`/`end`, quoted labels with special characters) and the ASCII diagram count.
2. The chain and scenario formats. Answer letters must exist among the options, every option needs a rationale, and the number of answers must match "Select ONE/TWO".
3. Every YAML block parses (PyYAML `safe_load_all`), and every JSON block parses.
4. Every listing is byte-identical to its source. Each listing is **re-run on the final file**, its output must match the embedded block exactly, and the output must end in `verdict: OK`.
5. All relative links and anchors resolve. With `--urls`, every external URL returns a non-error status.

The listings are deterministic (seeded RNGs, no hash-order dependence) and use only the Python 3 standard library: `python -I <listing>.py <any-path>`.

## Where this KB refines the brief

1. **Folder names.** The brief's role line describes the KB as running from `01-Compute-and-Virtualization-Physics/` to `07-Multi-Cloud-DR-FinOps-and-SAP-C02-Scenarios/`, while its repository blueprint uses the longer names in the status table. This KB follows the **blueprint names exactly**.
2. **File headers.** The brief asks for a `### FILE: <folder>/<file>.md` header before each file. Because the files are written to disk as a real directory tree, each file's path *is* its header. The chat summary for each folder lists the paths.
3. **"Borg / Titanium offload" for compute.** Google documents Borg as the cluster manager under Cloud Run and its infrastructure. The 2015 Borg paper describes VMs as Borg tasks, but no current Compute Engine contract does, so 01.1 marks it ⚠. Titanium (the adapter plus data-center offload processors) is the documented offload architecture.
4. **2026 currency.** The AWS Lambda family changed substantially in 2025–2026: Managed Instances, durable functions, MicroVMs, and Web Functions, which also renamed classic functions to "Event Functions". So did Karpenter (1.15, with the `Balanced` consolidation policy) and EC2 placement (precision time placement groups). Folder 01 covers the current state and flags the newest items for exam use.
5. **Models are labeled models.** The consolidation and cost listings are transparent models of documented rules and list prices. They show the *shape* of the trade-off; they aren't benchmarks of the products.
6. **"25 master scenarios" in two files.** The blueprint gives Folder 07 two files, so they split by theme:
   - MS-01–12: foundations (networking, security, organization design);
   - MS-13–25: workloads (migration, DR, serverless, data, cost, GenAI, cells).

   The master scenarios reuse the numbers that Folders 01–06's listings produce instead of inventing new ones, so every figure can be traced back to its mechanism.
7. **Product renames in 2026.** Google renamed Vertex AI to **Gemini Enterprise Agent Platform** on 2026-04-22 (for example, Vertex AI Search became Agent Search). Dataproc and Cloud Composer are now Managed Service for Apache Spark and Managed Service for Apache Airflow. The KB uses the current names and gives the former ones, because exam item banks and older docs still use them.
