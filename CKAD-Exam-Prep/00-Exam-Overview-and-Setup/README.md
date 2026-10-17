# 00 — CKAD Exam Overview and Setup (verified for an exam on 21 Oct 2026)

Every fact on this page was checked against the official Linux Foundation (LF) and CNCF pages on **17 October 2026**; sources are at the bottom. Re-check the [Important Instructions page](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad) the day before your exam, because the LF updates it without notice.

## Files in this folder

| File | Use it for |
|---|---|
| **README.md** (this page) | What the exam is, rules, domains, environment, what changed |
| [01-exam-environment-and-terminal-setup.md](01-exam-environment-and-terminal-setup.md) | The exam desktop, per-task SSH hosts, tools, keyboard rules, first-minute setup |
| [02-local-practice-lab-setup.md](02-local-practice-lab-setup.md) | A kind/minikube practice cluster on Windows (WSL2) for all practice and mock exams |
| [03-kubectl-master-cheatsheet.md](03-kubectl-master-cheatsheet.md) | One-page command reference for all domains |
| [04-exam-strategy-and-time-management.md](04-exam-strategy-and-time-management.md) | Three-pass plan, per-task routine, the 25 most common point-losers |
| [05-study-plan-4-days.md](05-study-plan-4-days.md) | Saturday → Wednesday plan with time blocks |
| [06-exam-day-checklist.md](06-exam-day-checklist.md) | ID, room, desk, PSI check-in, timing rules |
| [07-research-findings-and-sources.md](07-research-findings-and-sources.md) | What the research verified or refuted, with sources |
| [08-docs-navigation-map.md](08-docs-navigation-map.md) | Where every copy-paste YAML lives on kubernetes.io/helm.sh |

---

## 1. The exam at a glance

| Item | Current value | Source |
|---|---|---|
| Format | Online, remotely proctored, **performance-based** (you solve tasks on real clusters from a Linux command line) | LF Important Instructions; LF CKAD page |
| Tasks / duration | **15–20 tasks in 2 hours** (≈ 6–8 min per task) | LF Important Instructions |
| Kubernetes version | **v1.37**. LF moves to each new minor release within about 4–8 weeks; v1.38 is not expected before mid-December 2026. | LF Important Instructions; LF CKAD page; kubernetes.io releases |
| Passing score | **66%**, scored automatically | LF FAQ |
| Results | Score report by email **within 24 hours**, barring exceptions | LF FAQ |
| Price / retake | **$445**, includes **one retake** (list price on the LF CKAD page; check at checkout) | LF CKAD page |
| Prerequisites | None | LF CKAD page |
| Certification validity | **2 years** (certifications earned before 1 Apr 2024 were valid 3 years) | LF FAQ |
| Simulator | **Two killer.sh sessions** per exam registration, each with **36 hours** of access from activation. The two CKAD sessions have **different** questions. Not included with "single" exam-only registrations. | LF FAQ; killer.sh FAQ |
| Proctoring platform | PSI **Bridge** through the **PSI Secure Browser** | LF Important Instructions; LF ExamUI page |

## 2. Domains, weights and all 24 official competencies

Quoted from the CNCF curriculum file `CKAD_Curriculum_v1.37.pdf` and the LF CKAD page. The competency list has not changed since the October 2024 revision; only the cluster version has.

| Domain (weight) | Official competencies | Kit chapter |
|---|---|---|
| **Application Design and Build (20%)** | Define, build and modify container images · Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) · Understand multi-container Pod design patterns (e.g. sidecar, init and others) · Utilize persistent and ephemeral volumes | [01](../01-Application-Design-and-Build/README.md) |
| **Application Deployment (20%)** | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) · Understand Deployments and how to perform rolling updates · Use the Helm package manager to deploy existing packages · Kustomize | [02](../02-Application-Deployment/README.md) |
| **Application Observability and Maintenance (15%)** | Understand API deprecations · Implement probes and health checks · Use built-in CLI tools to monitor Kubernetes applications · Utilize container logs · Debugging in Kubernetes | [03](../03-Application-Observability-and-Maintenance/README.md) |
| **Application Environment, Configuration and Security (25%)** | Discover and use resources that extend Kubernetes (CRD, Operators) · Understand authentication, authorization and admission control · Understand requests, limits, quotas · Define resource requirements · Understand ConfigMaps · Create & consume Secrets · Understand ServiceAccounts · Understand Application Security (SecurityContexts, Capabilities, etc.) | [04](../04-Application-Environment-Configuration-and-Security/README.md) |
| **Services and Networking (20%)** | Demonstrate basic understanding of NetworkPolicies · Provide and troubleshoot access to applications via services · Use Ingress rules to expose applications | [05](../05-Services-and-Networking/README.md) |

Plus [06 — Cross-cutting skills and bonus topics](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md): the kubectl speed and output skills every task needs, and adjacent topics (scheduling, HPA, PDB) that the open-ended wording ("etc.", "and others") could pull in.

**Not named in the CKAD curriculum** but covered in this kit at low priority, because a v1.37 cluster has them and the wording is open-ended: native sidecar containers (GA since v1.33, covered under multi-container patterns), EndpointSlices (the v1 Endpoints API has been deprecated since v1.33), and Gateway API. Gateway API belongs to **CKA**: its docs site is an allowed resource for CKA only. A CKAD exam would only let you use kubernetes.io's Gateway page.

## 3. The exam environment

| Aspect | What to expect |
|---|---|
| Screen | Task text in a resizable **Content Panel** on the left. A remote Linux desktop on the right with a **Terminal Emulator**, **Firefox** (for the allowed docs), **VSCodium** (integrated terminal allowed, extensions disabled) and a virtual keyboard. Timer alerts at 30, 15 and 5 minutes left. |
| Hosts | **Every task has a designated host.** The task's infobox shows `ssh <nodename>`. Work there, then `exit` back to the base system (hostname `base`). **Nested ssh is not supported.** The base system has none of the tools, so do all work on the SSH hosts. Do not reboot base. |
| Root | `sudo -i` on any host, or prefix commands with `sudo` |
| Tools guaranteed on SSH hosts | `kubectl` with the **`k` alias and Bash autocompletion**, `yq`, `curl`, `wget`, `man` + man pages. **jq and tmux are no longer listed** (they were in 2024). Helm, podman/docker and kustomize aren't listed either; tasks that need them should provide them, so check with `which`. |
| Keyboard | Terminal copy/paste = **Ctrl+Shift+C / Ctrl+Shift+V** (or right-click). Other apps use Ctrl+C/V. **INSERT key is prohibited.** Use **Ctrl+Alt+W** instead of Ctrl+W. Ctrl+Alt+K locates the cursor. |
| Allowed docs | **kubernetes.io/docs**, **kubernetes.io/blog**, **helm.sh/docs**, plus the links in each task's **Quick Reference** box. The kubernetes.io site search is allowed, but don't open external search results. Translations are allowed. Docs under `/usr/share` and man pages are allowed. **Gateway API docs = CKA only. Kustomize's own docs and GitHub are not allowed**, so learn Kustomize from kubernetes.io's Kustomize task page. |

Full details and setup routine: [01-exam-environment-and-terminal-setup.md](01-exam-environment-and-terminal-setup.md).

## 4. What changed recently (2024 → Oct 2026)

| When | Change | Impact on you |
|---|---|---|
| Oct 2024 | Last substantive curriculum revision. Added **Kustomize**; "Understand Jobs and CronJobs" became "Choose and use the right workload resource"; "(CRD)" became "(CRD, Operators)"; SecurityContexts gained "Capabilities". | Study material written against the v1.31–v1.35 curricula is still current on competencies. |
| 1 Apr 2024 | Validity cut from 3 years to **2 years** | Plan your renewal |
| mid-2025 | Exam environment moved to the **per-task SSH host + `base`** model. The old `node-1` + context-switching description and the preinstalled jq/tmux are gone. | Ignore older write-ups that say otherwise |
| Nov 2025 → Mar 2026 | **ingress-nginx controller retired** (no fixes after March 2026). The **Ingress API itself is GA, feature-frozen and still a CKAD competency.** | Know Ingress for the exam; prefer Gateway API or a maintained controller in real designs ([08-Architect-Notes](../08-Architect-Notes/README.md)) |
| Nov 2025 | **Helm 4** released (helm.sh now shows 4.x by default) | Core commands unchanged. Run `helm version` on the exam host. |
| Sep–Oct 2026 | Exam environment moved to **Kubernetes v1.37** | Concepts unchanged; use current API versions only |

## 5. About "previous exam questions"

Real CKAD questions are confidential under the [LF Global Certification and Confidentiality Agreement](https://docs.linuxfoundation.org/tc-docs/certification/lf-cert-agreement). Sharing them would violate it and can get a certification revoked. Every practice question and mock exam in this kit is an **original exam-style task**, modelled on the official competencies above and on the task *types* candidates describe publicly. They train the same skills without reproducing protected content.

## 6. Sources (checked 17 Oct 2026)

- LF — Important Instructions: CKA and CKAD: https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad
- LF — FAQ CKA/CKAD/CKS: https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks
- LF — Resources allowed: https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed
- LF — CKAD product page: https://training.linuxfoundation.org/certification/certified-kubernetes-application-developer-ckad/
- LF — ExamUI for performance-based exams: https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/exam-user-interface/examui-performance-based-exams
- LF — Candidate requirements: https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/candidate-requirements
- LF — Taking the exam: https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/taking-the-exam
- CNCF curriculum repo (CKAD_Curriculum_v1.37.pdf): https://github.com/cncf/curriculum
- killer.sh FAQ: https://killer.sh/faq
- Kubernetes releases: https://kubernetes.io/releases/
- Ingress NGINX retirement: https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/
