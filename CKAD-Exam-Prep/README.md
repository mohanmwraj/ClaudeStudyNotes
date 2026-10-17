# CKAD Exam Prep Kit — October 2026 (exam on Kubernetes v1.37)

A self-contained kit for passing the **Certified Kubernetes Application Developer (CKAD)** exam and for using Kubernetes as an application architect afterwards. It has a folder per exam domain with notes, reference YAML, command references and exam-style practice tasks. It also includes six full mock exams with solutions and lab scripts, a 4-day study plan, and production-grade architect notes.

> **Exam facts verified on 17 Oct 2026** against the Linux Foundation and CNCF pages: 2 hours, 15–20 hands-on tasks, pass mark 66%, Kubernetes **v1.37**, one SSH host per task, and only kubernetes.io/docs, kubernetes.io/blog and helm.sh/docs allowed. Details and sources: [00-Exam-Overview-and-Setup/README.md](00-Exam-Overview-and-Setup/README.md).

---

## Start here (in this order)

1. **Read** [00-Exam-Overview-and-Setup/README.md](00-Exam-Overview-and-Setup/README.md) for the format, rules, all 24 official competencies and what changed recently (15 min).
2. **Build your lab** with [00/02-local-practice-lab-setup.md](00-Exam-Overview-and-Setup/02-local-practice-lab-setup.md): kind on WSL2 with ingress, metrics-server and NetworkPolicy (20 min).
3. **Follow the plan** in [00/05-study-plan-4-days.md](00-Exam-Overview-and-Setup/05-study-plan-4-days.md), Saturday 17 → Wednesday 21 October.
4. For each chapter, read its `README.md`, then the topic files, then **type** the YAML from `yaml/` and do every 🔥 task in `practice-questions.md`.
5. Take the **mock exams** under strict 120-minute timing: [07-Mock-Exams](07-Mock-Exams/README.md).
6. The night before, tick every line of [MUST-KNOW-CHECKLIST.md](MUST-KNOW-CHECKLIST.md) by doing it, and go through [00/06-exam-day-checklist.md](00-Exam-Overview-and-Setup/06-exam-day-checklist.md).

---

## What's inside

| Folder | Exam weight | What you get |
|---|---|---|
| [00-Exam-Overview-and-Setup](00-Exam-Overview-and-Setup/README.md) | — | Verified exam facts, the exam environment, practice lab (kind/WSL2), [kubectl master cheatsheet](00-Exam-Overview-and-Setup/03-kubectl-master-cheatsheet.md), [strategy](00-Exam-Overview-and-Setup/04-exam-strategy-and-time-management.md), [4-day plan](00-Exam-Overview-and-Setup/05-study-plan-4-days.md), [exam-day checklist](00-Exam-Overview-and-Setup/06-exam-day-checklist.md), [research and sources](00-Exam-Overview-and-Setup/07-research-findings-and-sources.md), [docs map](00-Exam-Overview-and-Setup/08-docs-navigation-map.md) |
| [01-Application-Design-and-Build](01-Application-Design-and-Build/README.md) | **20%** | Images (podman/docker build, save, OCI), Pods, workload choice (Deployment/DaemonSet/StatefulSet/Job/CronJob), multi-container patterns (init, native and classic sidecar, adapter, ambassador), ephemeral and persistent volumes · **30 practice tasks** |
| [02-Application-Deployment](02-Application-Deployment/README.md) | **20%** | Deployments, rolling updates and rollbacks, blue/green, canary, Helm (Helm 3 and 4 differences tested), Kustomize (bases, overlays, generators, patches) · **27 practice tasks** |
| [03-Application-Observability-and-Maintenance](03-Application-Observability-and-Maintenance/README.md) | **15%** | API deprecations (legacy → migrated manifest pairs), probes, `kubectl top`/events, logs, debugging (10 broken-pod scenarios, `kubectl debug`) · **28 practice tasks** |
| [04-Application-Environment-Configuration-and-Security](04-Application-Environment-Configuration-and-Security/README.md) | **25%** | CRDs and Operators, authentication/authorization/admission (RBAC, Pod Security Admission, ValidatingAdmissionPolicy), requests/limits/quotas/LimitRange/QoS, ConfigMaps, Secrets, ServiceAccounts, SecurityContext and capabilities, Downward API · **30 practice tasks** |
| [05-Services-and-Networking](05-Services-and-Networking/README.md) | **20%** | Networking and DNS fundamentals, every Service type and how to troubleshoot it, Ingress (paths, hosts, TLS), NetworkPolicies (AND/OR, DNS egress, "fix the labels"), Gateway API (bonus) · **27 practice tasks** |
| [06-Cross-Cutting-Skills-and-Bonus-Topics](06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) | all | kubectl speed skills, jsonpath/custom-columns, labels/selectors, scheduling (affinity, taints, spread, priority), HPA, PDB, YAML, vim/bash · **24 practice tasks** |
| [07-Mock-Exams](07-Mock-Exams/README.md) | all | **6 full 2-hour papers** (Foundations → Final boss), each weighted like the real exam and covering all 24 competencies, with `setup.sh`, detailed `solutions.md` (points, verify steps, common mistakes) and `cleanup.sh` |
| [08-Architect-Notes](08-Architect-Notes/README.md) | beyond the exam | Production design: reliability/HA, resources and autoscaling, security architecture, networking (Ingress vs Gateway API after the ingress-nginx retirement), GitOps and delivery, observability, storage, multi-tenancy, and a [59-item production-readiness checklist](08-Architect-Notes/10-production-readiness-checklist.md) |
| [MUST-KNOW-CHECKLIST.md](MUST-KNOW-CHECKLIST.md) | all | Everything you must be able to do without looking it up, with target times, defaults and numbers to memorise, and architect must-knows |

### How every chapter is organised

```text
0X-<Domain>/
├── README.md                ← official competencies, competency → file → frequency table, must-know list, study order
├── 01-...md, 02-...md ...   ← one file per topic: concepts · key fields · imperative commands · exam traps · architect notes · docs links · self-check
├── commands.md              ← every command for the chapter, grouped and commented
├── practice-questions.md    ← exam-style tasks, most frequent first, solutions in collapsible blocks
└── yaml/                    ← reference manifests you can apply (broken/ and deprecated/ hold intentionally wrong ones to fix)
```

**Frequency tags:** 🔥 High (expect it) · ⚡ Medium · 🧊 Low (rare, but covered so nothing surprises you).

Solutions sit in `<details>` blocks. In VS Code use **Markdown: Open Preview** (Ctrl+Shift+V), or view the files on GitHub, to get the click-to-reveal behaviour. Try each task before you open its solution.

---

## About "previous exam questions"

Real CKAD questions are **confidential** under the Linux Foundation certification agreement, and sharing them can cost a certification. This kit therefore contains **no leaked questions**. Every practice task and mock exam is an **original, exam-style task**, written against the official competency list and the task *types* candidates describe publicly. They train exactly the skills that are graded. Treat any website that offers "real dumps" as both unethical and unreliable.

---

## Quality checks run on this kit (17 Oct 2026)

- Every YAML file, YAML block in the markdown and heredoc in a mock `setup.sh` was parsed. Kubernetes resources were schema-validated **in strict mode against Kubernetes v1.37** with kubeconform. Legacy manifests are checked the other way round, so that they *fail* on v1.37.
- Kubernetes lint rules: removed apiVersions, selector/label mismatches, Ingress `pathType`, Job `restartPolicy`, memory units, multi-port Service names.
- All 1,214 relative links between files resolve. 342 of the 343 cited documentation URLs returned HTTP 200; the remaining one is a GitHub page that rate-limited the checker.
- Shell scripts pass `bash -n` and use LF line endings ([.gitattributes](.gitattributes) keeps them that way). The scripts for mocks 01–04 were also dry-run end to end against stub `kubectl`/`helm`. For mocks 05–06, the manifests embedded in the scripts were extracted and linted.
- Helm examples were linted and rendered with both Helm v3.22.1 and v4.3.1. Kustomize overlays were built with standalone Kustomize v5.8.3; kubectl v1.37 embeds v5.8.1.
- Totals: 304 files, with 184 reference YAML files, **166 chapter practice tasks** and **112 mock-exam questions**.
- **Not done:** running the manifests on a live cluster (none was available while building). Your own lab run is the final test. If something doesn't behave as described, note it and treat the fix as extra practice.

---

## Using this kit on Windows

Clone or copy the folder anywhere. Practise in **WSL2 Ubuntu**, because the exam is Linux bash. Reach this folder from WSL as `/mnt/c/Users/<you>/Documents/Claude/CKAD-Exam-Prep`. Run the mock scripts with `bash setup.sh` and `bash cleanup.sh` against your kind or minikube cluster.

Good luck on Wednesday. Bank the easy points, verify every task, and keep moving.
