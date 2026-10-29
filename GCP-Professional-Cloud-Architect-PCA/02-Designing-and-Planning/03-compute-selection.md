# 02/03 · Compute Selection: Mapping Workloads to Platforms

**Exam guide:** 1.3 ("mapping compute needs to platform products (GKE, Cloud Run, Cloud Run functions)", "choosing compute resources (Spot VMs, custom machine types, specialized workload)"). **Principles:** P3, P5, P9.

---

## 1. The decision tree

Ask these questions in order and stop at the first platform that satisfies every hard constraint.

```text
1. Is it a VMware estate that must move as-is, fast (vSphere tooling, no re-platforming)?
       └─ yes → Google Cloud VMware Engine
2. Does it need special hardware or licensing: Oracle RAC / certified bare metal?
       └─ yes → Bare Metal Solution
3. Is it a short, event-triggered piece of glue (a file landed, a message arrived, an HTTP webhook)?
       └─ yes → Cloud Run functions
4. Is it a containerizable, stateless HTTP/gRPC service or a run-to-completion job,
   with no need for node-level control, privileged containers or special kernels?
       └─ yes → Cloud Run (services, jobs, worker pools)
5. Is it containerized but needs Kubernetes APIs, operators, Helm, sidecars/mesh, stateful sets,
   custom schedulers, GPUs at scale, or portability across clouds/on-prem?
       └─ yes → GKE  (Autopilot by default; Standard when you need node-level control)
6. Otherwise (OS-level control, legacy apps, licensed software, lift-and-shift VMs, custom kernels)
       └─ Compute Engine (MIGs for fleets, Spot for fault-tolerant batch, sole-tenant for licensing)
   Batch HPC/array jobs on VMs without managing a scheduler → Batch
```

**Default bias:** the most managed platform that fits (P5). The exam often presents a VM-based answer next to a Cloud Run or GKE Autopilot answer; the VM answer loses unless a constraint forces it.

---

## 2. The platforms compared

| | **Compute Engine** | **GKE Standard** | **GKE Autopilot** | **Cloud Run** | **Cloud Run functions** |
|---|---|---|---|---|---|
| Unit | VM | Pod on nodes you manage | Pod; Google manages nodes | Container instance | Function (source code → container) |
| You manage | OS, patching, scaling config | Node pools, upgrades (auto-upgrade available), capacity | Workloads only | Container image and config | Function code |
| Scale to zero | No (MIG min ≥ 0 with schedules, but not request-driven) | No (node pools min 0 with autoscaler, but not request-driven) | Pods to zero; you pay per pod resources | **Yes** | **Yes** |
| Billing | Per VM-second | Per node + cluster fee | Per pod resource request + cluster fee | Per request-time (vCPU-s, GiB-s) or instance-based | Same as Cloud Run |
| Good for | Legacy, licensed, OS-specific, stateful VMs, GPUs with custom drivers | Complex K8s platforms, special node configs, privileged/system workloads | Most K8s workloads with low ops | Stateless web/APIs, jobs, event consumers | Event glue, webhooks, light transforms |
| Limits to remember | You own HA via MIGs | You own node operations | Some privileged/host access disallowed | Request timeout up to 60 min; jobs up to 168 h per task; no privileged containers | Single-purpose; for heavier work use Cloud Run |

### Cloud Run specifics the exam uses

* **Services** handle HTTP/gRPC/WebSockets. **Jobs** run to completion (batch, parallel tasks). **Worker pools** run pull-based background work, such as Pub/Sub or Kafka consumers.
* **Concurrency**: one instance serves many requests (default 80, up to 1000). Cheaper than one-request-per-instance.
* **Min instances** removes cold starts for latency-sensitive services. **Max instances** protects databases from connection floods.
* **Direct VPC egress** (or Serverless VPC Access connectors) reaches private IPs (Cloud SQL private IP, Memorystore, on-premises over Interconnect).
* **GPUs** (for example NVIDIA L4) for inference with scale-to-zero.
* Ingress control (internal only, or internal plus Cloud Load Balancing) and **IAP / IAM invoker** for private services.
* Multi-region: deploy to several regions behind a **global external Application Load Balancer** with **serverless NEGs**.

### GKE specifics the exam uses

* **Autopilot** is the recommended mode for most workloads: Google manages nodes, scaling, security hardening and patching, and you pay for pod requests.
* **Standard** fits when you need specific machine types per node pool, node-level customization (kernel parameters, privileged DaemonSets), or tight cost control through bin-packing.
* **Regional clusters** for production (control plane and nodes across zones).
* **Private clusters** (nodes without public IPs); **authorized networks** or **DNS-based endpoint** for control-plane access.
* **Workload Identity Federation for GKE** for pod-to-Google-API authentication (no keys).
* **Fleets** group clusters (including on-premises and other clouds) for Config Sync, Policy Controller, Cloud Service Mesh and multi-cluster Gateway.
* Release channels (Rapid / Regular / Stable / Extended) plus maintenance windows and exclusions to control upgrades.
* **Spot node pools** for fault-tolerant workloads; **GPU/TPU node pools** for ML.

---

## 3. Compute Engine machine families

| Family | Series examples | Choose for |
|---|---|---|
| **General purpose** | E2 (cost-optimized), N2/N2D, **N4**, C3/C3D, **C4**, C4A/N4A (Google Axion Arm), Tau T2D/T2A | Web servers, app servers, small/medium DBs, dev/test. E2 is the cheapest; C4 and N4 are the current generation |
| **Compute-optimized** | C2/C2D, H3, H4D | HPC, gaming servers, single-threaded high clock, EDA |
| **Memory-optimized** | M1, M2, M3, M4, X4 | SAP HANA, in-memory databases, large analytics |
| **Accelerator-optimized** | A2, A3, A4 (NVIDIA A100/H100/H200/B200), G2/G4 (L4, RTX) | ML training and inference, graphics, simulation |
| **Storage-optimized** | Z3 | High local-SSD throughput: scale-out databases, search |

**Custom machine types** (on E2, N2, N2D, N4 and others) let you set vCPU and memory independently. Use them when a workload is over-provisioned on predefined shapes, or when per-core licensing makes extra vCPUs expensive. **Extended memory** goes beyond the default per-vCPU memory ratio.

### Purchase and placement options

| Option | What it is | Use for | Don't use for |
|---|---|---|---|
| On-demand | Pay per second | Unpredictable workloads | — |
| **Spot VMs** | Spare capacity at a deep discount; can be **preempted at any time** with ~30 s notice; no maximum runtime | Batch, CI, rendering, stateless scale-out, checkpointed training | Databases, single-instance SLA workloads, anything that can't be interrupted |
| Preemptible VMs (legacy) | Like Spot but with a 24-hour maximum runtime | Old designs. Spot is the current recommendation | — |
| **Committed use discounts** | 1- or 3-year commitment: resource-based (vCPU/memory/GPU in a region) or spend-based / flexible (dollar per hour across eligible services) | Steady baseline | Short-lived or highly variable workloads |
| **Sustained use discounts** | Automatic discount for running certain older series a large part of the month | Applies automatically where eligible | — |
| **Reservations** | Guaranteed zonal capacity | DR capacity, launches, scarce GPUs | Cost saving on its own (pair with CUDs) |
| **Sole-tenant nodes** | Dedicated physical host | Compliance isolation, BYOL licenses tied to physical cores/sockets (Windows Server, SQL Server) | General workloads (costly) |
| **Shielded VMs** | Secure boot, vTPM, integrity monitoring | Default security posture | — |
| **Confidential VMs** | Memory encrypted in use (AMD SEV/SEV-SNP, Intel TDX) | Sensitive processing, regulatory "encryption in use" | — |

---

## 4. Specialized and adjacent compute

| Need | Product | Notes |
|---|---|---|
| Move VMware VMs without changing tools | **Google Cloud VMware Engine** | Dedicated VMware stack (vSphere, vSAN, NSX) managed by Google; HCX for migration; connect to VPC via private connection |
| Oracle RAC, Exadata-class, low-latency to Google Cloud | **Bare Metal Solution**; or Oracle Database@Google Cloud | Certified hardware in Google data centers |
| Batch scheduling on VMs | **Batch** | Managed job queue; uses Spot; HPC |
| Kubernetes on your hardware / at the edge | **Google Distributed Cloud** (software only for VMware/bare metal; connected for edge hardware; air-gapped) | Fleet-managed like GKE |
| Windows workloads | Compute Engine with license-included Windows images, or BYOL on sole-tenant nodes; Managed Service for Microsoft AD | Containers: GKE Windows Server node pools |
| Legacy PaaS | **App Engine** standard/flexible | Still supported. For new apps Google recommends Cloud Run |
| AI accelerators | GPUs on Compute Engine/GKE/Cloud Run; **TPUs** via Cloud TPU, GKE or Agent Platform | See [02/06](06-ai-ml-solution-selection.md) and [03/05](../03-Managing-and-Provisioning/05-agent-platform-ml-workflows.md) |

---

## 5. Requirement → compute choice: fast lookup

| Scenario cue | Choice | Why (principle) |
|---|---|---|
| "Stateless containerized API, spiky traffic, small team" | Cloud Run | P5, P9 scale to zero |
| "Existing Helm charts and Kubernetes manifests; minimize ops" | GKE Autopilot | Keeps K8s APIs (P15 least change) + P5 |
| "Requires a privileged DaemonSet / custom kernel module" | GKE Standard or Compute Engine | Autopilot/Cloud Run restrictions |
| "Process each uploaded image to create thumbnails" | Cloud Run functions (Eventarc trigger on Cloud Storage) | Event glue |
| "Nightly video rendering, can restart, cost-sensitive" | Spot VMs (Batch or MIG) or GKE Spot node pool, checkpointing | P9 |
| "Lift-and-shift 400 VMware VMs before data-center exit, keep vCenter" | VMware Engine | P15 speed with no re-platforming |
| "Windows Server + SQL Server licenses tied to physical cores (BYOL)" | Sole-tenant nodes | Licensing |
| "Single-threaded EDA tools need highest per-core performance" | Compute-optimized (C-family / H-family) | Fit |
| "SAP HANA 6 TB" | Memory-optimized (M-series / X4), certified | Fit |
| "Run a container for 3 hours to process a batch file once a day" | Cloud Run job | P5; jobs run up to 168 h per task |
| "Pub/Sub consumer that must run continuously without HTTP" | Cloud Run worker pool or GKE Deployment | Pull-based workloads |
| "ML inference with bursty traffic, GPU" | Cloud Run with GPU, or GKE with GPU node pool and autoscaling | Scale to zero (Cloud Run) vs control (GKE) |
| "Large-scale model training across thousands of accelerators" | AI Hypercomputer: TPU/GPU on GKE or Managed Training Clusters | Specialized workload |

---

## 6. Traps

* **Cloud Run functions for long or heavy processing.** Use Cloud Run services or jobs, or GKE.
* **App Engine for a new greenfield design** when Cloud Run fits. Google's current guidance favors Cloud Run.
* **Spot VMs for production databases or anything that must not be interrupted.**
* **Preemptible VMs** in an answer when Spot is offered. Spot is the current product (no 24-hour limit).
* **GKE Standard "for lower ops".** Autopilot is the lower-ops mode.
* **Moving VMware estates with Migrate to VMs** when the requirement is to keep VMware tooling and operations. That's VMware Engine.
* **Oversized predefined shapes** when a custom machine type fits licensing or cost constraints.

---

## References

* Choosing a compute option: <https://cloud.google.com/docs/choosing-a-compute-option>
* Machine families: <https://cloud.google.com/compute/docs/machine-resource>
* Spot VMs: <https://cloud.google.com/compute/docs/instances/spot>
* GKE Autopilot overview: <https://cloud.google.com/kubernetes-engine/docs/concepts/autopilot-overview>
* Cloud Run overview: <https://cloud.google.com/run/docs/overview/what-is-cloud-run>
* Sole-tenant nodes: <https://cloud.google.com/compute/docs/nodes/sole-tenant-nodes>
