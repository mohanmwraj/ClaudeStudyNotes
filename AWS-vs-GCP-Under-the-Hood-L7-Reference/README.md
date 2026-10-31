# AWS vs GCP Under the Hood: L7 Cloud Infrastructure Reference

A first-principles comparison of AWS and Google Cloud at the level of hypervisors, network fabrics, storage engines and control planes. It's for Principal backend, data and AI architects who need to translate architectures between the two clouds, pass AWS SAP-C02 scenario questions, and hold up in FAANG L7 infrastructure interviews. Service-name mapping (`S3 = GCS`) is the starting point, not the content. Each file explains *why* the two designs differ, which limits follow from that, and what breaks first in production.

## Status

| Folder | Files | Words | Listings | Gate |
|---|---|---|---|---|
| [`01-Virtualization-Compute-and-Kubernetes-Internals/`](01-Virtualization-Compute-and-Kubernetes-Internals/) | 3 | ~37.6k | 4 (Python) | Passed (2026-10-31) |
| `02-Global-Networking-Hybrid-Connectivity-and-Zero-Trust-VPC/` | 3 | — | — | Next |
| `03-Distributed-Storage-Databases-and-Lakehouse-Internals/` | 4 | — | — | Planned |
| `04-Messaging-Streaming-and-Data-Pipeline-Comparison/` | 2 | — | — | Planned |
| `05-IAM-KMS-Cryptography-and-Multi-Tenant-Governance/` | 3 | — | — | Planned |
| `06-Enterprise-Cloud-Migrations-Resiliency-and-FinOps/` | 3 | — | — | Planned |
| `07-25-Master-Multi-Cloud-and-SAP-C02-Bar-Raiser-Scenarios/` | 2 | — | — | Planned |

The folders are produced one at a time.

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
