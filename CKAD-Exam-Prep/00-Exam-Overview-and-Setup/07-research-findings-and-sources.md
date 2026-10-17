# Research Findings and Sources (17 Oct 2026)

This kit's exam facts come from a multi-source research pass run on 17 Oct 2026, plus follow-up checks of the official pages. It covered 5 search angles and 22 fetched sources. 109 claims were extracted and the top 25 were adversarially verified: 3 independent votes each, 2 refutations kill a claim. 20 were confirmed and 5 refuted. This page records what was verified, what was refuted, and what remains open, so you know how much to trust each part of the kit.

---

## 1. Verified (high confidence)

| # | Finding | Evidence / sources |
|---|---|---|
| 1 | **Five domains: 20 / 20 / 15 / 25 / 20.** The weights have been identical in every curriculum file from v1.24 to v1.37. | [CKAD_Curriculum_v1.37.pdf](https://github.com/cncf/curriculum/blob/master/CKAD_Curriculum_v1.37.pdf), [LF CKAD page](https://training.linuxfoundation.org/certification/certified-kubernetes-application-developer-ckad/), [cncf.io CKAD](https://www.cncf.io/training/certification/ckad/) |
| 2 | **The exam runs Kubernetes v1.37** and will still do so on 21 Oct 2026. LF aligns to a new minor version within about 4–8 weeks; v1.38 is targeted for about 16 Dec 2026. | [LF Important Instructions](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad), LF CKAD page, [kubernetes.io releases](https://kubernetes.io/releases/) |
| 3 | **No competency has changed since early 2025.** The v1.37 PDF is byte-identical to v1.33–v1.35; no v1.36 file ever existed. The last substantive revision (Oct 2024) added Kustomize, "Choose and use the right workload resource", "(CRD, Operators)" and "Capabilities". Helm, CRDs, API deprecations and blue/green/canary have been in scope since the Sept 2021 (v1.22) revision. | [cncf/curriculum commits](https://github.com/cncf/curriculum/commits/master), [v1.31 PDF](https://github.com/cncf/curriculum/blob/master/old-versions/CKAD_Curriculum_v1.31.pdf) |
| 4 | **Design & Build** has 4 competencies, **Deployment** 4, **Observability** 5, **Environment/Config/Security** 8 (including "Define resource requirements") and **Services & Networking** 3: **24 in total**, quoted in [README](README.md). The PDF misspells "deprecations" as "depreciations". | v1.37 PDF, LF CKAD page |
| 5 | **The Helm competency covers deploying existing packages**, not authoring charts. Kustomize is a bare one-word item with no stated scope. | LF CKAD page, v1.37 PDF |
| 6 | **Gateway API, EndpointSlices and native sidecars are not named** in the CKAD curriculum. Gateway API docs are an allowed resource for **CKA only**; the CKA v1.37 curriculum lists Gateway API. | v1.37 PDF, [Resources Allowed](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-allowed), [CKA v1.37 PDF](https://github.com/cncf/curriculum/blob/master/CKA_Curriculum_v1.37.pdf) |
| 7 | **15–20 performance-based tasks in 2 hours**, remotely proctored, auto-scored, **pass = 66%**, results within 24 h, **$445 with one retake**, no prerequisites. | LF Important Instructions, [LF FAQ](https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks), LF CKAD page |
| 8 | **Each task runs on a designated host** reached with `ssh <nodename>`. `exit` returns you to `base`; nested ssh is unsupported; `sudo -i` gives root. **Only SSH hosts have tools: kubectl (+k alias, completion), yq, curl, wget, man.** jq and tmux are no longer listed. Write-ups older than mid-2025 that describe `node-1`/context switching are outdated. | LF Important Instructions, [killer.sh FAQ](https://killer.sh/faq) |
| 9 | **The exam UI**: PSI Secure Browser on PSI Bridge; Content Panel on the left; remote desktop with Terminal, Firefox, VSCodium (extensions disabled) and a virtual keyboard; timer alerts at 30/15/5 min. | [LF ExamUI page](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/exam-user-interface/examui-performance-based-exams) |
| 10 | **Allowed resources**: kubernetes.io/docs (site search OK, external results not), kubernetes.io/blog, helm.sh/docs, the task's Quick Reference links, translations, `/usr/share` docs and man pages. **Kustomize docs, GitHub and discuss.kubernetes.io are not allowed.** | Resources Allowed |

## 2. Confirmed by follow-up checks (official pages, 17 Oct 2026)

| Finding | Source |
|---|---|
| Certification **valid 2 years**; certifications earned before 1 Apr 2024 are valid 3 years | LF FAQ |
| killer.sh: **2 sessions** per registration, **36 h each** from activation; the two CKAD sessions have **different questions**; not included with "single" exam-only registrations | LF FAQ, killer.sh FAQ |
| ID: valid, unexpired, government-issued, original physical document with name, photo and signature; the name must exactly match the verified name | LF FAQ |
| Keyboard: Ctrl+Shift+C/V in the terminal; INSERT key prohibited; Ctrl+Alt+W instead of Ctrl+W; don't reboot base | LF Important Instructions |
| Launch up to 30 min early; start within 30 min of the scheduled time or it's a no-show; the timer doesn't pause on connection loss; "End Exam" then "End Session" | [LF Taking the Exam](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/taking-the-exam) |
| One monitor only, no VMs, movable webcam, cleared desk, private walled room, run the PSI system check | [LF Candidate Requirements](https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2/candidate-requirements) |
| ingress-nginx retirement announced 11 Nov 2025; best-effort maintenance until March 2026; Ingress API not removed (feature-frozen); Steering/SRC statement 29 Jan 2026 | [kubernetes.io blog](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/), [statement](https://kubernetes.io/blog/2026/01/29/ingress-nginx-statement/) |
| Tool versions on 17 Oct 2026: Kubernetes stable v1.37.1, kind v0.33.0 (default node v1.37.0; kind ≥ v0.24.0 enforces NetworkPolicy out of the box), Helm 4.3.1, Gateway API v1.6.3, cloud-provider-kind v0.12.0 (native Ingress + Gateway API since v0.9.0) | dl.k8s.io, GitHub releases, helm.sh, kind docs |

## 3. Refuted during verification (don't repeat these)

- "Kustomize first arrived in v1.31" — refuted 0-3. The dating was wrong; see finding 3 for the actual history.
- "Study guides built on the v1.34/v1.35 curriculum are out of date" — refuted 0-3. The competencies are byte-identical; only the cluster version moved.
- A claim, attributed to the FAQ page, that the 4–8 week version alignment covers CKS too, and that CKS runs v1.35 — refuted 0-3 because the FAQ page doesn't say so. The authoritative CKAD version source is the Important Instructions page (finding 2).
- A blog claim that **CKAD added Gateway API at ~5%** contradicts both primary sources. Treat it as false.
- A dump site's "Core Concepts 13%" comes from the syllabus retired in Sept 2021.

## 4. What could NOT be verified (and how the kit handles it)

| Gap | Kit approach |
|---|---|
| Task patterns reported by 2025–2026 candidates: no claim survived verification | Practice questions and mocks are **original tasks written against the official competency text** and the kubernetes.io docs, labelled "exam-style" |
| Time-saving techniques and failure causes: no claim survived verification | Strategy content comes from the official environment rules plus standard kubectl practice; treat it as advice, not fact |
| Architect best practices: none verified in the research pass | [08-Architect-Notes](../08-Architect-Notes/README.md) cites kubernetes.io and the CNCF project docs directly |
| Whether helm, podman/docker, kustomize, jq, tmux and kubectl-convert are installed on exam hosts | The kit says "check with `which`". It teaches the kubectl-native way (`kubectl kustomize`, jsonpath, manual API migration) so you're never blocked |
| Which Ingress controller the exam uses | Tasks name an `ingressClassName`. Use exactly what the task says and check with `k get ingressclass` |

## 5. Open questions to re-check the day before

1. Has the [Important Instructions page](https://docs.linuxfoundation.org/tc-docs/certification/tips-cka-and-ckad) changed: version, tools, rules?
2. Does your exam checklist in the LF portal show anything unusual (ID name match, system check status)?
3. Is the killer.sh session still active (36 h window)?
