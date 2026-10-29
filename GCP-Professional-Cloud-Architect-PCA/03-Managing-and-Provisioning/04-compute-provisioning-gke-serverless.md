# 03/04 · Configuring Compute: VMs, GKE, Serverless and VMware Engine

**Exam guide:** 2.3 (compute provisioning; spot vs standard; cloud-native network configuration for Compute Engine, GKE, serverless and Google Cloud VMware Engine; orchestration, configuration and patch management; container orchestration; serverless). **Principles:** P3, P5, P9, P12.

---

## 1. Compute Engine fleets: templates, MIGs, autoscaling and updates

### Building blocks

| Building block | Purpose | Key settings |
|---|---|---|
| **Custom image / image family** | Golden image with OS hardening and agents baked in (built by Cloud Build + Packer) | Faster, more consistent boot than long startup scripts. Image families give "latest approved" |
| **Instance template** (global or regional) | Immutable VM spec for a MIG | Machine type, image, disks, service account + scopes, network tags/secure tags, metadata, Spot or standard |
| **Managed instance group (MIG)**, zonal or **regional** | Fleet of identical VMs | Autoscaling, **autohealing** (health check), load balancing, **update policy** |
| **Stateful MIG** | Preserve disks/IPs/metadata per instance across recreation | For stateful apps (databases, legacy) that still want MIG autohealing |
| **OS Login** | IAM-controlled SSH (with 2FA option) instead of metadata SSH keys | Org policy `compute.requireOsLogin` |

### Autoscaling policies

* Signals: target **CPU utilization**, **load-balancer serving capacity**, **Cloud Monitoring metrics** (for example, Pub/Sub undelivered messages per instance), **schedules** (scale up before known peaks).
* **Predictive autoscaling** forecasts load from history, for apps with long initialization.
* Cool-down / initialization period so new VMs aren't judged before they're ready.
* Min/max replicas protect availability and budget.

### Update strategies (rolling updates)

| Setting | Effect |
|---|---|
| `maxSurge` | Extra VMs created above target during the update (faster, costs more temporarily) |
| `maxUnavailable` | VMs that can be down at once (0 = no capacity loss) |
| **Canary** | Two versions in one MIG (`--canary-version` with a target size such as 10%) |
| Proactive vs opportunistic | Apply now vs only when instances are recreated |
| Rollback | Start a rolling update back to the previous template |

```bash
# Regional MIG rolling update to a new template, keeping full capacity
gcloud compute instance-groups managed rolling-action start-update web-mig \
  --region=us-central1 --version=template=web-v2 \
  --max-surge=3 --max-unavailable=0

# Canary: 10% of instances on the new template
gcloud compute instance-groups managed rolling-action start-update web-mig \
  --region=us-central1 --version=template=web-v1 \
  --canary-version=template=web-v2,target-size=10%
```

### Volatility: Spot vs standard

* Set the **provisioning model** in the template (`--provisioning-model=SPOT`) and the **termination action** (STOP or DELETE).
* Handle the preemption notice with a **shutdown script** (about 30 s): checkpoint work, drain connections.
* Run two MIGs (standard baseline + Spot burst) behind one load balancer, or on GKE use a standard node pool plus a **Spot node pool** with taints and tolerations.
* GKE Autopilot: request Spot capacity per workload with the node selector `cloud.google.com/gke-spot: "true"`.
* Never put the only replica of a stateful or SLA-bound component on Spot.

---

## 2. Patch and configuration management

| Platform | How patching works | Exam answer |
|---|---|---|
| Compute Engine | **VM Manager**: **OS patch management** (patch jobs and scheduled **patch deployments**, with pre/post scripts and rollout by zone), **OS inventory**, **OS policies** (desired-state configuration) | "Patch 500 VMs across projects on a schedule with reporting" → VM Manager patch deployments |
| Compute Engine (immutable alternative) | Rebuild golden images regularly; roll MIGs to the new template | Preferred for stateless fleets (P12) |
| GKE | Control-plane and node **auto-upgrades** via **release channels**; **maintenance windows** and **exclusions**; **surge** or **blue-green node pool upgrades** | Pick a release channel and maintenance window; don't disable upgrades |
| GKE Autopilot | Google manages nodes and upgrades | Least ops |
| Cloud Run / Cloud Run functions | Platform patched by Google; you rebuild images for your dependencies (automatic base image updates are available) | Nothing to patch at the OS level |
| VMware Engine | Google manages the VMware stack lifecycle; you manage guest OSes | Guest patching remains yours |

**Infrastructure orchestration:** declare everything in **Terraform** (or **Infrastructure Manager**, Google's managed Terraform service; **Config Connector** to manage Google Cloud resources as Kubernetes objects). Detect drift with plans; apply via CI/CD (see [06/02](../06-Managing-Implementation/02-programmatic-interaction-iac.md)).

---

## 3. Cloud-native network configuration for compute

### Compute Engine

* Place VMs in custom-mode subnets; **no external IPs** (org policy `compute.vmExternalIpAccess`); **Cloud NAT** for egress; **Private Google Access**.
* **Alias IP ranges** for multiple services per VM; **multiple NICs** for appliances (each NIC in a different VPC).
* Firewall targeting by **service account** or **secure tags** (IAM-governed).

### GKE

| Setting | Recommendation |
|---|---|
| **VPC-native cluster** (alias IPs) | Default and required for most features. Plan **secondary ranges** for pods and services large enough for growth (pod CIDR exhaustion is a classic outage) |
| **Private nodes** / private cluster | Nodes have only internal IPs; control-plane access via private endpoint, **authorized networks** or the **DNS-based endpoint** |
| **GKE Dataplane V2** | eBPF data plane with built-in **network policy** enforcement and logging |
| **Network policies** | Restrict pod-to-pod traffic (default deny per namespace) |
| **Gateway API / Ingress** | Provision Google load balancers from Kubernetes; container-native LB via NEGs |
| **Multi-cluster** | Multi-cluster Gateway / Services across a fleet; **Cloud Service Mesh** for mTLS, traffic management and observability |
| **Shared VPC** | Clusters in service projects use host-project subnets (central network control) |
| Egress | Cloud NAT; NGFW policies; FQDN network policies |

### Serverless (Cloud Run / Cloud Run functions)

| Need | Configure |
|---|---|
| Reach private resources (Cloud SQL private IP, Memorystore, on-premises) | **Direct VPC egress** (recommended) or a Serverless VPC Access connector |
| Route *all* egress through the VPC (static egress IP via Cloud NAT, firewall control) | Egress setting "all traffic" + Cloud NAT |
| Make a service private | **Ingress = internal** (or internal + Cloud Load Balancing); require IAM `run.invoker` |
| Front with WAF/CDN/custom domain | Global external Application LB + serverless NEG + Cloud Armor |
| Employee-only internal app | IAP on the load balancer (or IAP directly on Cloud Run) |
| Service-to-service auth | Each service has its own **service identity**; callers present Google-signed ID tokens |

### Google Cloud VMware Engine

* A **private cloud** (vSphere, vSAN, NSX) runs on dedicated nodes in a Google region.
* A **VMware Engine network** connects to your VPC through a **private connection** (peering-based), giving VMs access to Google services and the rest of the VPC.
* On-premises reaches VMware Engine through your **Cloud Interconnect / VPN** into the VPC; **HCX** handles migration (bulk, vMotion-style, network extension for keeping IPs during migration).
* Internet access and public IPs are available through VMware Engine's own services or via the VPC (Cloud NAT / load balancers).
* NSX segments and distributed firewall work as on-premises, so the network team keeps its tools.

---

## 4. Container orchestration on GKE: what to configure

| Area | Configuration | Principle |
|---|---|---|
| Mode | **Autopilot** by default; Standard when node control is needed | P5 |
| Availability | **Regional** cluster; ≥ 2 replicas; **PodDisruptionBudgets**; topology spread constraints | P2 |
| Scaling | HPA (CPU/custom metrics), VPA (rightsizing), cluster autoscaler / node auto-provisioning | P9 |
| Identity | **Workload Identity Federation for GKE** (KSA → IAM principal); no node service-account keys; least-privilege node SA | P6 |
| Supply chain | **Artifact Registry** + vulnerability scanning; **Binary Authorization** to enforce signed or attested images | P12 |
| Isolation | Namespaces + RBAC (Google Groups for RBAC); **GKE Sandbox** (gVisor) for untrusted code; separate clusters or projects for strong isolation (prod vs dev, regulated vs not) | P6, P7 |
| Policy and config | **Config Sync** (GitOps) + **Policy Controller** (OPA Gatekeeper-based constraints) across the fleet | P12 |
| Secrets | Secret Manager (CSI driver / add-on) rather than plain Kubernetes Secrets; application-layer secrets encryption with Cloud KMS | P11 |
| Backup | **Backup for GKE** | DR |
| Observability | Cloud Logging/Monitoring integration, **Managed Service for Prometheus** | P13 |
| Cost | Spot node pools; Autopilot pay-per-pod; cost allocation by namespace/label; rightsizing recommendations | P9 |

---

## 5. Serverless computing: Cloud Run configuration points

| Setting | Guidance |
|---|---|
| **Concurrency** | Raise it (up to 1000) for I/O-bound services to cut cost; set it to 1 for CPU-heavy or non-thread-safe code |
| **Min instances** | > 0 for latency-sensitive services (no cold starts) |
| **Max instances** | Cap to protect databases and budgets |
| **CPU allocation / billing** | Request-based (CPU only during requests) vs instance-based (CPU always on; background work, WebSockets) |
| **Startup CPU boost** | Faster cold starts (for example, JVM apps) |
| **Revisions and traffic** | Every deploy is an immutable revision; **traffic splitting** for canary / blue-green; **tags** for testing a revision by URL |
| **Secrets** | Mount from Secret Manager as volumes or environment variables |
| **Jobs** | Parallel tasks with retries; triggered by Cloud Scheduler or Workflows |
| **Eventing** | **Eventarc** triggers (Cloud Storage, Pub/Sub, Audit Logs, third-party) → Cloud Run; **Cloud Tasks** for rate-controlled asynchronous dispatch; **Cloud Scheduler** for cron |

---

## 6. Worked scenarios

**A. "A stateless app on a regional MIG must deploy a new version with no capacity loss and automatic rollback if errors spike."**
Rolling update with `maxUnavailable=0` and `maxSurge>0`, or a canary version first, while monitoring error-rate SLO alerts. Roll back by updating to the previous template. Better still, run delivery through Cloud Deploy or a pipeline with automated verification (P12).

**B. "Security wants all 2,000 Linux VMs patched within 7 days of critical releases, with compliance reports."**
**VM Manager** OS patch management (patch deployments by schedule and zone rollout) plus OS inventory reports. Use golden images for new VMs.

**C. "A Cloud Run service must connect to a Cloud SQL instance that has only a private IP, and to an on-premises API over Interconnect."**
Direct VPC egress into the Shared VPC subnet (routes to on-premises via Cloud Router), and the Cloud SQL connector over private IP.

**D. "A GKE cluster ran out of pod IPs during a traffic surge."**
Pod secondary range too small. Add additional pod ranges (discontiguous multi-pod CIDR) or recreate node pools with a larger pod range. Plan IP space at design time.

---

## References

* Managed instance groups: <https://cloud.google.com/compute/docs/instance-groups>
* Rolling updates for MIGs: <https://cloud.google.com/compute/docs/instance-groups/updating-migs>
* VM Manager OS patch management: <https://cloud.google.com/compute/vm-manager/docs/patch>
* GKE release channels: <https://cloud.google.com/kubernetes-engine/docs/concepts/release-channels>
* GKE network overview: <https://cloud.google.com/kubernetes-engine/docs/concepts/network-overview>
* Cloud Run Direct VPC egress: <https://cloud.google.com/run/docs/configuring/vpc-direct-vpc>
* VMware Engine networking: <https://cloud.google.com/vmware-engine/docs/overview>
