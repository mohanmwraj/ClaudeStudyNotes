# Domain 2 Drill · Managing and Provisioning a Solution Infrastructure (20 questions)

Original exam-style questions for objectives 2.1–2.5 (~17.5% of the exam). The notes for this domain are in [03-Managing-and-Provisioning](../03-Managing-and-Provisioning/).

---

### Q1 · Task 2.1 · Single answer

A company needs encrypted connectivity between its data center and Google Cloud **this week** for about 500 Mbps of traffic. Within six months, traffic will grow to a sustained 20 Gbps. The company has equipment in a colocation facility that supports Google Cloud Interconnect.

What should you recommend?

- **A.** Order Dedicated Interconnect now and wait for it to be provisioned before migrating anything.
- **B.** Use Direct Peering with Google for both the initial and long-term traffic.
- **C.** Deploy HA VPN with two tunnels now, order Dedicated Interconnect for the 20 Gbps target, and keep HA VPN as a backup path after the Interconnect is live.
- **D.** Deploy a single Classic VPN tunnel now, and add more tunnels as traffic grows to 20 Gbps.

<details><summary>Answer</summary>

**Answer: C**

**Why (P14, P2):** HA VPN can be up in hours and meets the encryption need at 500 Mbps. Sustained 20 Gbps needs Interconnect, which has weeks of lead time. The VPN then remains a backup path.

- **A** — wrong: Interconnect lead time misses "this week".
- **B** — wrong: Direct Peering reaches Google's public services and doesn't provide private VPC connectivity or an SLA.
- **C** — correct: fast start now, the right long-term capacity, and resilience.
- **D** — wrong: Classic VPN has a lower SLA, and scaling tunnels to 20 Gbps is impractical compared with Interconnect.

**Reference:** <https://cloud.google.com/network-connectivity/docs/vpn/concepts/topologies>

</details>

### Q2 · Task 2.1 · Single answer

A hospital network needs a 99.99% SLA for Dedicated Interconnect. It has a presence in only **one** metropolitan area, which is on Google's list of metros supported for the single-region Critical production topology.

Which configuration meets the requirement?

- **A.** Four Dedicated Interconnect connections in the metro, two in each of two facility and edge-availability-domain combinations, ordered as a connection group with the `PRODUCTION_CRITICAL` intended capability, with VLAN attachments in the metro's region and a Cloud Router.
- **B.** Two Dedicated Interconnect connections in the metro, one in each edge availability domain, with one Cloud Router.
- **C.** One 100 Gbps Dedicated Interconnect connection plus an HA VPN tunnel as backup.
- **D.** A single Partner Interconnect VLAN attachment from one service provider.

<details><summary>Answer</summary>

**Answer: A**

**Why (P2, P14):** Since June 2026, 99.99% can be reached in a single supported metro with four connections across two edge availability domains, ordered as a `PRODUCTION_CRITICAL` connection group. Otherwise it requires two metros and two regions.

- **A** — correct: matches the documented single-region Critical production topology.
- **B** — wrong: two connections in one metro qualify only for 99.9%.
- **C** — wrong: a single connection has no Interconnect SLA, and VPN backup doesn't change that.
- **D** — wrong: a single attachment has no redundancy.

**Reference:** <https://docs.cloud.google.com/network-connectivity/docs/interconnect/tutorials/dedicated-creating-9999-availability>

</details>

### Q3 · Task 2.1 · Select TWO

Compute Engine VMs in a subnet have no external IP addresses, by organization policy. They need to (1) download OS packages from public internet repositories, and (2) read and write objects in Cloud Storage without traffic leaving Google's network.

Which two actions should you take? (Select TWO.)

- **A.** Assign ephemeral external IP addresses to the VMs during patch windows.
- **B.** Configure Cloud NAT for the subnet's region.
- **C.** Create a VPC Network Peering connection to Google's services network.
- **D.** Enable Private Google Access on the subnet.
- **E.** Create an HA VPN tunnel from the VPC to `storage.googleapis.com`.

<details><summary>Answer</summary>

**Answer: B, D**

**Why (P14):** Internet egress for private VMs is Cloud NAT. Reaching Google APIs without external IPs is Private Google Access. They're two different needs with two different mechanisms.

- **A** — wrong: violates the no-external-IP policy and exposes the VMs.
- **B** — correct: managed outbound NAT for package downloads, without inbound exposure.
- **C** — wrong: you can't peer with Google APIs. Private services access peering is for specific managed services, not Cloud Storage access.
- **D** — correct: lets VMs without external IPs reach Cloud Storage and other Google APIs.
- **E** — wrong: VPN tunnels terminate on gateways, not on Google API domains.

**Reference:** <https://cloud.google.com/vpc/docs/private-google-access>

</details>

### Q4 · Task 2.1 · Single answer

A SaaS analytics vendor runs its service in its own Google Cloud organization. It must let 200 enterprise customers, each in their own organization and VPC, reach the service over private IP addresses. Many customers use overlapping RFC 1918 ranges.

What should the vendor implement?

- **A.** VPC Network Peering between the vendor's VPC and each customer VPC.
- **B.** A Shared VPC in which each customer project is attached as a service project.
- **C.** A public endpoint with per-customer IP allow-lists.
- **D.** A Private Service Connect service attachment published by the vendor, with each customer creating a Private Service Connect endpoint in its own VPC.

<details><summary>Answer</summary>

**Answer: D**

**Why (P14):** Private Service Connect exposes a *service*, not a network. Consumers get an endpoint IP from their own address space, so overlapping ranges don't matter, and it works across organizations.

- **A** — wrong: peering forbids overlapping ranges, and 200 peerings exceed practical limits.
- **B** — wrong: Shared VPC works within one organization only, and would give the vendor control of customers' networking.
- **C** — wrong: not private connectivity.
- **D** — correct: the producer/consumer model built for multi-tenant SaaS.

**Reference:** <https://cloud.google.com/vpc/docs/private-service-connect>

</details>

### Q5 · Task 2.1 · Single answer

A security team requires that traffic between the web, application and database tiers inside a VPC be inspected for known exploit signatures, and that malicious traffic be **blocked**, using a managed Google Cloud service.

What should you configure?

- **A.** A Cloud Armor security policy on an internal passthrough Network Load Balancer.
- **B.** Cloud NGFW Enterprise firewall endpoints with security profiles for intrusion prevention, referenced by firewall policy rules.
- **C.** VPC Flow Logs on all subnets, analyzed weekly in BigQuery.
- **D.** A hierarchical firewall policy that denies TCP port 80 between the tiers.

<details><summary>Answer</summary>

**Answer: B**

**Why (P6, P14):** Signature-based intrusion *prevention* on east-west traffic is the Enterprise tier of Cloud NGFW. L3/L4 rules and flow logs can't inspect payloads or block exploits.

- **A** — wrong: Cloud Armor protects external Application Load Balancers at the edge. It doesn't inspect east-west VPC traffic.
- **B** — correct: managed IPS inline in the VPC.
- **C** — wrong: flow logs are after-the-fact metadata, with no inspection or blocking.
- **D** — wrong: blocking a port isn't signature inspection, and it may break legitimate traffic.

**Reference:** <https://cloud.google.com/firewall/docs/about-firewalls>

</details>

### Q6 · Task 2.1 · Single answer

A trading firm serves a proprietary TCP market-data feed (not HTTP) to clients from back ends in one region. The back ends must see each client's original source IP address for entitlement checks.

Which load balancer should you use?

- **A.** A global external Application Load Balancer.
- **B.** A global external proxy Network Load Balancer.
- **C.** A regional external passthrough Network Load Balancer.
- **D.** A regional internal Application Load Balancer.

<details><summary>Answer</summary>

**Answer: C**

**Why (P1, P14):** Non-HTTP traffic that must preserve the client IP at L4 needs a passthrough load balancer. Proxies terminate connections and replace the source address.

- **A** — wrong: it's for HTTP(S) only, and it proxies traffic.
- **B** — wrong: proxy load balancers terminate TCP, so back ends see the proxy's address.
- **C** — correct: a passthrough load balancer delivers packets with the original source IP.
- **D** — wrong: internal only, and HTTP only.

**Reference:** <https://cloud.google.com/load-balancing/docs/choosing-load-balancer>

</details>

### Q7 · Task 2.2 · Single answer

A brokerage must keep trade records for 7 years in write-once, read-many form. A regulator requires that nobody, including project owners, can delete or overwrite records during that period. Records are almost never read. The company wants the lowest cost.

What should you configure?

- **A.** An Archive-class Cloud Storage bucket with a 7-year retention policy, then lock the retention policy with Bucket Lock.
- **B.** A Standard-class bucket with object versioning enabled.
- **C.** A Nearline-class bucket, with temporary holds placed manually on new objects.
- **D.** A BigQuery table with a 7-year table expiration.

<details><summary>Answer</summary>

**Answer: A**

**Why (P10, P9):** WORM compliance comes from a locked retention policy, which can't be removed or shortened. Archive class fits data almost never read.

- **A** — correct: immutable for 7 years, at the lowest storage price.
- **B** — wrong: versioning helps recovery, but owners can still delete versions.
- **C** — wrong: manual temporary holds are error-prone and can be released, and Nearline costs more than Archive.
- **D** — wrong: expiration *deletes* data. It doesn't prevent deletion or overwriting.

**Reference:** <https://cloud.google.com/storage/docs/bucket-lock>

</details>

### Q8 · Task 2.2 · Single answer

A Cloud SQL for MySQL instance grows by about 200 GB per month. Last year an outage occurred when its disk filled up. The team wants to prevent this without paying for years of unused storage up front.

What should you do?

- **A.** Provision the maximum storage size now, so the disk can never fill.
- **B.** Have an engineer check free space weekly and resize the disk manually.
- **C.** Migrate the database to Bigtable, which has no storage limits.
- **D.** Enable automatic storage increase with a sensible limit, and create a Cloud Monitoring alert on disk utilization.

<details><summary>Answer</summary>

**Answer: D**

**Why (P9, P13):** Automatic storage increase grows capacity as needed, and an alert catches runaway growth before it hits the configured limit. Cloud SQL storage can't shrink, so over-provisioning wastes money permanently.

- **A** — wrong: you pay for unused storage permanently, because storage can't be reduced.
- **B** — wrong: manual toil, which is how the outage happened.
- **C** — wrong: a different data model. Rewriting an OLTP application to fix disk sizing is disproportionate.
- **D** — correct: elastic storage plus monitoring.

**Reference:** <https://cloud.google.com/sql/docs/mysql/instance-settings>

</details>

### Q9 · Task 2.2 · Single answer

Analysts query a 50 TB BigQuery events table, almost always filtering on `event_date` and often on `customer_id`. Monthly query costs on on-demand pricing are high, and queries are slow.

What should you do first?

- **A.** Buy more slots in a larger reservation.
- **B.** Recreate the table partitioned by `event_date` and clustered by `customer_id`, and require a partition filter.
- **C.** Export the table to Cloud SQL for faster queries.
- **D.** Split the table into one dataset per analyst team.

<details><summary>Answer</summary>

**Answer: B**

**Why (P9, P4):** On-demand cost is bytes scanned. Partition pruning and clustering cut scanned bytes and latency dramatically, without extra spend.

- **A** — wrong: more slots don't reduce bytes scanned, and capacity spend rises.
- **B** — correct: queries read only the relevant partitions and blocks, and the required filter prevents accidental full scans.
- **C** — wrong: Cloud SQL isn't built for 50 TB analytical scans.
- **D** — wrong: dataset layout doesn't change bytes scanned.

**Reference:** <https://cloud.google.com/bigquery/docs/partitioned-tables>

</details>

### Q10 · Task 2.2 · Select TWO

An application writes configuration and user-uploaded files to a Cloud Storage bucket. Twice this year, a bug overwrote files and an operator deleted the wrong folder. The team wants fast self-service recovery from both kinds of mistake while keeping storage costs under control.

Which two actions should you take? (Select TWO.)

- **A.** Make the bucket publicly readable, so users can restore their own files.
- **B.** Disable uniform bucket-level access, so per-object ACLs can protect files.
- **C.** Enable object versioning with a lifecycle rule that deletes noncurrent versions after 30 days.
- **D.** Keep a second copy of every file on a Local SSD attached to the application VM.
- **E.** Keep soft delete enabled, with a retention duration that covers the recovery window.

<details><summary>Answer</summary>

**Answer: C, E**

**Why (P10, P9):** Versioning recovers overwritten objects, and soft delete recovers deleted ones. A lifecycle rule bounds the cost of old versions.

- **A** — wrong: a data-exposure risk, and it doesn't help recovery.
- **B** — wrong: ACLs add complexity and don't recover data.
- **C** — correct: overwrites keep the previous version, and lifecycle cleanup controls cost.
- **D** — wrong: Local SSD is ephemeral and not a backup.
- **E** — correct: deleted objects stay restorable for the soft-delete retention period.

**Reference:** <https://cloud.google.com/storage/docs/soft-delete>

</details>

### Q11 · Task 2.3 · Single answer

A company runs 1,500 Linux VMs across 30 projects. Security requires monthly OS patching that rolls out zone by zone, with pre- and post-patch scripts, and compliance reports showing each VM's patch state.

What should you use?

- **A.** A shell script run from an administrator's laptop that SSHes into each VM.
- **B.** VM Manager OS patch management with scheduled patch deployments (zonal rollout, pre/post scripts) and OS inventory reporting.
- **C.** Delete and recreate every VM manually each month from the latest public image.
- **D.** Disable automatic updates, to avoid unplanned changes.

<details><summary>Answer</summary>

**Answer: B**

**Why (P5, P12):** VM Manager is the managed, at-scale patching service, with scheduling, rollout controls and compliance reporting.

- **A** — wrong: fragile, unaudited and requires broad SSH access.
- **B** — correct: scheduled, staged patch deployments with reporting across projects.
- **C** — wrong: manual recreation is toil, and it breaks stateful VMs.
- **D** — wrong: leaves vulnerabilities unpatched.

**Reference:** <https://cloud.google.com/compute/vm-manager/docs/patch>

</details>

### Q12 · Task 2.3 · Single answer

A studio renders animation frames on GKE. The jobs are fault-tolerant and checkpoint their progress. The studio wants the lowest compute cost while keeping its always-on services unaffected.

How should you configure the cluster?

- **A.** Add a node pool covered by a 3-year committed use discount, sized for peak rendering.
- **B.** Schedule the rendering pods on the control-plane nodes.
- **C.** Add a Spot VM node pool with a taint, give the rendering pods a matching toleration and node selector, and checkpoint to Cloud Storage.
- **D.** Move rendering to sole-tenant nodes.

<details><summary>Answer</summary>

**Answer: C**

**Why (P9, P3):** Interruptible, checkpointed batch work is the ideal Spot workload. The taint and toleration keep it off the standard node pools that run always-on services.

- **A** — wrong: a commitment sized for peak pays for idle capacity between renders.
- **B** — wrong: GKE control-plane nodes are Google-managed and not schedulable for workloads.
- **C** — correct: deep discount, isolation from critical pods, and preemptions absorbed by checkpoints.
- **D** — wrong: sole-tenant nodes cost more and are for compliance or licensing.

**Reference:** <https://cloud.google.com/compute/docs/instances/spot>

</details>

### Q13 · Task 2.3 · Single answer

Workloads on a GKE cluster must call BigQuery and Cloud Storage. Each workload should have only the permissions it needs, and security forbids long-lived credentials.

What should you configure?

- **A.** Workload Identity Federation for GKE, granting each Kubernetes service account the specific IAM roles it needs.
- **B.** Grant the node pool's service account the BigQuery Admin and Storage Admin roles.
- **C.** Create a service account key and store it as a Kubernetes Secret mounted into the pods.
- **D.** Create an API key restricted to BigQuery and Cloud Storage, and pass it to the pods as an environment variable.

<details><summary>Answer</summary>

**Answer: A**

**Why (P6):** Workload Identity Federation for GKE gives each Kubernetes service account its own short-lived Google credentials and per-workload IAM, with no keys.

- **A** — correct: least privilege per workload and no long-lived secrets.
- **B** — wrong: every pod on the node inherits broad admin rights.
- **C** — wrong: a long-lived key, which is forbidden and a leak risk.
- **D** — wrong: API keys don't authorize access to BigQuery and Cloud Storage data.

**Reference:** <https://cloud.google.com/kubernetes-engine/docs/concepts/workload-identity>

</details>

### Q14 · Task 2.3 · Single answer

A company moved 200 VMs into a Google Cloud VMware Engine private cloud. The VMs must reach a Cloud SQL instance in the company's VPC and on-premises systems that are already connected to that VPC through Cloud Interconnect.

What should you configure?

- **A.** Public IP addresses on each VMware VM, with traffic to Cloud SQL and on-premises over the internet.
- **B.** A Cloud VPN tunnel from each VMware VM to the VPC.
- **C.** Re-IP every VMware VM into the VPC's subnets.
- **D.** A private connection between the VMware Engine network and the VPC, with route exchange so on-premises routes learned over Interconnect are reachable.

<details><summary>Answer</summary>

**Answer: D**

**Why (P14):** VMware Engine networks connect to your VPC through a private connection. Routing then lets VMware workloads reach VPC resources and the on-premises networks already attached to the VPC.

- **A** — wrong: exposes the workloads, and sends private traffic over the internet.
- **B** — wrong: per-VM VPNs are unmanageable and unnecessary.
- **C** — wrong: VMware Engine VMs live on NSX segments, not VPC subnets, and re-IPing defeats the low-change migration.
- **D** — correct: the documented connectivity model.

**Reference:** <https://cloud.google.com/vmware-engine/docs/overview>

</details>

### Q15 · Task 2.4 · Single answer

A data science team retrains a demand-forecasting model by hand in notebooks every month. Results are inconsistent, nobody can tell which data produced the production model, and bad models have been deployed twice.

What should you recommend?

- **A.** A cron job on a Compute Engine VM that runs the notebook every month and copies the model to the serving endpoint.
- **B.** A shared spreadsheet where scientists record which dataset they used for each training run.
- **C.** An Agent Platform Pipelines workflow (formerly Vertex AI Pipelines) that validates data, trains, evaluates against the current champion, registers the model in Model Registry, and deploys only if it performs better, run on a schedule or when new data arrives.
- **D.** A written checklist that each scientist follows before deploying a model.

<details><summary>Answer</summary>

**Answer: C**

**Why (P12, P16):** ML pipelines make retraining reproducible, record lineage automatically and enforce evaluation gates, so bad models don't reach production.

- **A** — wrong: automates the inconsistency, with no lineage or evaluation gate.
- **B** — wrong: manual tracking is unreliable and unenforced.
- **C** — correct: automated, auditable, gated MLOps with versioned models.
- **D** — wrong: process without automation keeps the human error.

**Reference:** <https://cloud.google.com/vertex-ai/docs/pipelines/introduction>

</details>

### Q16 · Task 2.4 · Single answer

A research lab must start a three-week training run on 256 accelerators next month on a fixed date, timed to a product announcement. Capacity must be guaranteed for the whole window, and the lab doesn't need the accelerators afterwards.

Which consumption model should you choose?

- **A.** Reserve the accelerators for that window with Dynamic Workload Scheduler calendar mode.
- **B.** Use Spot VMs and restart training whenever capacity is reclaimed.
- **C.** Request on-demand accelerators on the start date.
- **D.** Submit the job with Dynamic Workload Scheduler flex-start, and let it begin whenever capacity becomes available.

<details><summary>Answer</summary>

**Answer: A**

**Why (P9, P16):** A fixed future window with guaranteed capacity, and no need beyond it, is exactly what calendar-mode reservations are for.

- **A** — correct: guaranteed accelerators for a defined start date and duration.
- **B** — wrong: Spot capacity can be reclaimed at any time, which risks the deadline.
- **C** — wrong: on-demand capacity for scarce accelerators isn't guaranteed on a given day.
- **D** — wrong: flex-start doesn't guarantee a start date.

**Reference:** <https://cloud.google.com/ai-hypercomputer/docs/overview>

</details>

### Q17 · Task 2.4 · Select THREE

A team trains large models on interruptible capacity to save money. Recent runs wasted days when accelerators were reclaimed, and GPU utilization is low because data loading is slow.

Which three actions should you take? (Select THREE.)

- **A.** Checkpoint model and optimizer state to Cloud Storage regularly, and resume automatically from the latest checkpoint.
- **B.** Store the training data in a cheaper region far from the accelerators.
- **C.** Use Spot VMs or Dynamic Workload Scheduler flex-start for these fault-tolerant runs.
- **D.** Disable job retries, so failed runs don't consume more capacity.
- **E.** Keep checkpoints only on Local SSD attached to the training VMs, for speed.
- **F.** Stage training data on a high-throughput store in the same region as the accelerators, such as Hyperdisk ML, Managed Lustre or Cloud Storage with Rapid Cache.

<details><summary>Answer</summary>

**Answer: A, C, F**

**Why (P9, P10, P3):** Interruptible capacity is cheap only if progress survives preemption (checkpoints in durable storage). Accelerators are expensive only when idle, so feed them from fast storage close by.

- **A** — correct: preemption costs minutes of progress, not days.
- **B** — wrong: cross-region data adds latency and egress, and starves the accelerators.
- **C** — correct: discounted capacity that suits restartable runs.
- **D** — wrong: without retries, preempted runs simply die.
- **E** — wrong: Local SSD is lost with the VM, which defeats the checkpoint.
- **F** — correct: removes the data-loading bottleneck.

**Reference:** <https://cloud.google.com/ai-hypercomputer/docs/overview>

</details>

### Q18 · Task 2.5 · Single answer

A professional-services firm wants its 8,000 employees to ask questions across Google Drive, SharePoint and Jira, get answers that respect each user's existing document permissions, use prebuilt AI agents for research tasks, and work with source-grounded notebooks. It wants minimal custom development.

What should you recommend?

- **A.** A custom RAG application on GKE with connectors written by the firm's developers.
- **B.** Gemini Enterprise, with connectors to Drive, SharePoint and Jira, its prebuilt agents, and NotebookLM.
- **C.** Agent Search for Commerce, indexing the documents as products.
- **D.** The Cloud Translation API with glossaries.

<details><summary>Answer</summary>

**Answer: B**

**Why (P16, P5):** Employee-facing enterprise search, agents and NotebookLM with permission-aware connectors are the packaged product's core purpose. That's the highest abstraction that fits.

- **A** — wrong: large custom effort that duplicates a managed product.
- **B** — correct: permission-aware search and chat, prebuilt agents and NotebookLM.
- **C** — wrong: the commerce variant is for retail catalogs, not employee knowledge.
- **D** — wrong: translation doesn't search or answer questions.

**Reference:** <https://cloud.google.com/gemini-enterprise>

</details>

### Q19 · Task 2.5 · Single answer

A video platform must automatically flag explicit content in uploaded videos and mark scene boundaries so editors can jump to flagged segments. The team wants the least development effort.

Which service should you use?

- **A.** Extract frames manually and send each frame to the Cloud Vision API.
- **B.** Imagen on Agent Platform.
- **C.** Speech-to-Text with the Chirp model.
- **D.** The Video Intelligence API, with explicit content detection and shot change detection.

<details><summary>Answer</summary>

**Answer: D**

**Why (P16, P5):** A prebuilt video API already provides both features. Choose the API that matches the task exactly.

- **A** — wrong: frame extraction and per-frame calls are custom plumbing, and you lose temporal context.
- **B** — wrong: Imagen generates and edits images. It doesn't moderate video.
- **C** — wrong: transcribes audio. It doesn't detect visual content.
- **D** — correct: explicit content detection and shot detection in one managed API.

**Reference:** <https://cloud.google.com/video-intelligence/docs>

</details>

### Q20 · Task 2.5 · Single answer

A product team wants to evaluate a partner large language model from Model Garden in a prototype this week. They want no infrastructure to manage and pay-per-token pricing. They may move to dedicated serving later if usage grows.

How should they use the model?

- **A.** Deploy the model on a GKE cluster with GPU node pools before starting the prototype.
- **B.** Buy GPU servers for the on-premises data center.
- **C.** Call the model as a managed API (Model-as-a-Service) from Model Garden on Agent Platform.
- **D.** Train a comparable model from scratch with Agent Platform custom training.

<details><summary>Answer</summary>

**Answer: C**

**Why (P5, P16):** Managed model APIs give instant access with no infrastructure and usage-based pricing, which is ideal for prototypes. Dedicated serving can come later if economics or control require it.

- **A** — wrong: infrastructure work before value is proven.
- **B** — wrong: capital expense and lead time for a prototype.
- **C** — correct: zero-ops, pay-per-use access.
- **D** — wrong: enormous cost and effort to replicate an available model.

**Reference:** <https://cloud.google.com/model-garden>

</details>
