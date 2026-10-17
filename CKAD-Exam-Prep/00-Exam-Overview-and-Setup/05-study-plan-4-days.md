# 4-Day Study Plan — Saturday 17 Oct → Exam Wednesday 21 Oct 2026

Plan for ~8 h on Saturday and Sunday and ~4–5 h on Monday and Tuesday. Every block ends with **hands-on practice in your lab** ([02-local-practice-lab-setup.md](02-local-practice-lab-setup.md)). Reading without typing does not count.

Legend: 🔥 = must do · ⚡ = do if time allows · ✅ = tick when done

---

## Day 1 — Saturday 17 Oct: setup, Design & Build, Deployment (≈ 8 h)

| Time | Block | Material |
|---|---|---|
| 0:00–1:00 | 🔥 Lab + terminal setup, exam rules, strategy | [02-local-practice-lab-setup.md](02-local-practice-lab-setup.md), [01-exam-environment-and-terminal-setup.md](01-exam-environment-and-terminal-setup.md), [README.md](README.md), [04-exam-strategy-and-time-management.md](04-exam-strategy-and-time-management.md) |
| 1:00–1:45 | 🔥 Speed skills: generators, `explain`, jsonpath, vim | [06 chapter](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md) files 01, 02, 08 |
| 1:45–4:15 | 🔥 **Application Design and Build (20%)**: images, workloads, Jobs/CronJobs, multi-container, volumes, PV/PVC | [01 chapter](../01-Application-Design-and-Build/README.md) + all 🔥 practice questions |
| 4:15–4:30 | Break | |
| 4:30–7:00 | 🔥 **Application Deployment (20%)**: rolling updates/rollback, blue/green, canary, Helm, Kustomize | [02 chapter](../02-Application-Deployment/README.md) + all 🔥 practice questions |
| 7:00–8:00 | 🔥 Drill: create each kind with `$do` from memory (Pod, Deployment, Service, Job, CronJob, ConfigMap, Secret, SA, Role, RoleBinding, Ingress, Quota) — twice | [03-kubectl-master-cheatsheet.md](03-kubectl-master-cheatsheet.md) §2 |

End-of-day check: you can build/save an image, create a CronJob with history limits, write a sidecar pod, roll back to a revision, do an 80/20 canary, and helm install/upgrade/rollback **without looking anything up**.

---

## Day 2 — Sunday 18 Oct: Config & Security, Observability, first mock (≈ 8 h)

| Time | Block | Material |
|---|---|---|
| 0:00–3:00 | 🔥 **Environment, Configuration and Security (25% — biggest)**: CRDs, RBAC/auth/admission, requests/limits/quotas, ConfigMaps, Secrets, ServiceAccounts, SecurityContext, Downward API | [04 chapter](../04-Application-Environment-Configuration-and-Security/README.md) + practice questions |
| 3:00–3:15 | Break | |
| 3:15–5:15 | 🔥 **Observability and Maintenance (15%)**: API deprecations, probes, `top`, logs, debugging | [03 chapter](../03-Application-Observability-and-Maintenance/README.md) + practice questions |
| 5:15–5:30 | Break | |
| 5:30–7:30 | 🔥 **Mock Exam 01**, strictly timed (120 min) | [07-Mock-Exams/mock-exam-01](../07-Mock-Exams/mock-exam-01/questions.md) |
| 7:30–8:15 | 🔥 Grade it, then redo every missed task from scratch | `solutions.md` → "if you missed it → study" table |
| Evening | ⚡ Activate **killer.sh session 1** only if you can use it before Tuesday morning (access lasts 36 h from activation) | [README](README.md) → simulator |

---

## Day 3 — Monday 19 Oct: Networking, mocks 02–03 (≈ 4–5 h)

| Time | Block | Material |
|---|---|---|
| 0:00–2:00 | 🔥 **Services and Networking (20%)**: Services & troubleshooting, Ingress, NetworkPolicies (AND/OR, DNS egress, "fix labels" pattern) | [05 chapter](../05-Services-and-Networking/README.md) + practice questions |
| 2:00–4:00 | 🔥 **Mock Exam 02** timed, or **killer.sh session 1** if activated | [mock-exam-02](../07-Mock-Exams/mock-exam-02/questions.md) |
| 4:00–4:45 | 🔥 Review misses; re-type the YAML for every miss | |

---

## Day 4 — Tuesday 20 Oct: dress rehearsal + weak spots (≈ 4–5 h)

| Time | Block | Material |
|---|---|---|
| 0:00–2:00 | 🔥 **Mock Exam 03 or 04** timed (pick the one covering your weakest domain) | [07-Mock-Exams](../07-Mock-Exams/README.md) |
| 2:00–2:45 | 🔥 Fix weak spots from all attempts so far | chapter practice questions |
| 2:45–3:30 | 🔥 [MUST-KNOW-CHECKLIST.md](../MUST-KNOW-CHECKLIST.md) — tick every line by **doing** it | |
| 3:30–4:30 | ⚡ **killer.sh session 2** (CKAD session 2 has *different* questions from session 1; it is open for 36 h after activation) or Mock 05 | |
| Evening | 🔥 Exam logistics: PSI system check, ID ready, room cleared, webcam/mic tested | [06-exam-day-checklist.md](06-exam-day-checklist.md) |
| | 🔥 Sleep 7–8 h. A tired brain loses more points than one missed topic. | |

Mock 06 ("Final boss") is optional. If you score ≥ 66% on it, you are very likely ready.

---

## Exam day — Wednesday 21 Oct

| When | What |
|---|---|
| Morning | 30-minute warm-up from memory: NetworkPolicy with DNS egress, CronJob, probes, securityContext with capabilities, canary, `helm upgrade` + `rollback`, `k create role/rolebinding` + `auth can-i`. **No new topics.** |
| −60 min | Close every app, clear the desk, plug in the laptop, restart, run the PSI system check |
| −30 min | Start check-in (ID, room scan) |
| First 2 min in the exam | Check `k`, completion and `$do`; set up `~/.vimrc` if needed ([01-exam-environment-and-terminal-setup.md](01-exam-environment-and-terminal-setup.md)) |
| During | Three-pass plan and per-task routine ([04-exam-strategy-and-time-management.md](04-exam-strategy-and-time-management.md)) |

---

## Short on time? Priority order

If you lose a day, protect these (highest exam yield first):

1. Context/namespace discipline + imperative generators + verifying
2. Deployments: rolling update, rollback, scale, `set image`, canary/blue-green
3. ConfigMaps, Secrets (env + volume), ServiceAccounts, RBAC Role/RoleBinding + `auth can-i`
4. Probes (all three kinds)
5. Services (ClusterIP/NodePort, selector/targetPort troubleshooting) and NetworkPolicies
6. Jobs/CronJobs, multi-container (init + sidecar), PV/PVC/emptyDir
7. SecurityContext (runAsUser, capabilities, readOnlyRootFilesystem), requests/limits, ResourceQuota/LimitRange
8. Helm (install/upgrade/rollback/list) and Kustomize (`apply -k`, overlays)
9. Ingress (path/host rules, TLS)
10. API deprecations (fix old manifests), `kubectl top`, logs, debugging
11. Image build/save with podman/docker
12. CRDs (create a CR, `explain`), admission control/PSA labels
13. Bonus: scheduling, HPA, PDB, Gateway API

---

## Progress tracker

| Area | Read | Practice Qs done | Score / notes |
|---|---|---|---|
| 01 Design & Build | ☐ | ☐ | |
| 02 Deployment | ☐ | ☐ | |
| 03 Observability | ☐ | ☐ | |
| 04 Env/Config/Security | ☐ | ☐ | |
| 05 Services & Networking | ☐ | ☐ | |
| 06 Cross-cutting | ☐ | ☐ | |
| Mock 01 | | | __ % |
| Mock 02 | | | __ % |
| Mock 03 | | | __ % |
| Mock 04 | | | __ % |
| Mock 05 | | | __ % |
| Mock 06 (hard) | | | __ % |
| killer.sh #1 / #2 | | | __ % / __ % |
