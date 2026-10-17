# Exam Strategy and Time Management

CKAD is a speed test as much as a knowledge test. Most people who fail knew the material. They failed because of time, a wrong namespace/context, or a task they believed was done but never verified.

---

## 1. The math

| Fact | Consequence |
|---|---|
| ~2 hours for ~15–20 weighted tasks | **≈ 6–7 minutes per task** on average |
| Pass mark 66% | You can miss a third of the weight and still pass. Do not chase 100%. |
| Tasks carry different weights (roughly 2%–10%) | A 2% task that takes 15 minutes is a bad trade. Skip it and come back. |
| Grading checks the **end state** of the cluster and files | Wrong namespace, wrong name or wrong file path = 0 for that check, even if your YAML was perfect |

---

## 2. Three-pass plan

| Pass | Time box | What you do |
|---|---|---|
| **Pass 1** | ~60 min | Read each task. If you can finish it in ≤ 5 min, do it and verify it. Otherwise **flag it and move on immediately**. |
| **Pass 2** | ~40 min | Do the flagged medium tasks, best weight-per-minute first. |
| **Pass 3** | ~15 min | Do the hardest flagged tasks, try partial credit on anything left, re-verify the high-weight ones. |
| Buffer | ~5 min | Final sweep: every output file exists at the exact path, every resource is in the right namespace. |

Keep a scratch list (the exam UI has a flag feature, and you can also keep notes in a terminal file): `Q4 flagged 7% netpol`, `Q9 partial — probe missing`.

---

## 3. Routine for every single task

1. **Read the whole task once**, including the bottom lines. Constraints like "do not modify the Deployment" or "write the output to …" usually sit there.
2. **Connect to the task's designated host.** Every task names one, with its `ssh <host>` command in an infobox; copy it from the task. Run any context command the task gives as well. Never skip this, even if you think you're already there. If you rely on `$do`/`$now`, re-export them on the new host.
3. **Note the namespace** and either use `-n <ns>` on every command or run `k config set-context --current --namespace=<ns>`.
4. **Generate, don't type**: `k create … $do > qN.yaml`, then edit only what's needed.
5. **Apply** (`k apply -f qN.yaml`), or `k replace --force -f` for immutable Pod fields.
6. **Verify** with one command that proves the requirement: `get -o wide`, `describe`, `logs`, `auth can-i`, `curl`, `cat <file>`.
7. **Leave cleanly.** `exit` back to the base machine (hostname `base`) before the next task; nested ssh is not supported. Check the prompt before typing `exit`: candidates report that an extra `exit` on base can close the terminal session.

Save every manifest you write as `qN.yaml` in your home directory. If something breaks later, you can fix and re-apply it in seconds.

---

## 4. Top 25 ways people lose points (and the antidote)

| # | Mistake | Antidote |
|---|---|---|
| 1 | Worked in the wrong context/cluster | Run the task's context/ssh command first, every time |
| 2 | Wrong namespace (resource created in `default`) | `-n` on every command, or set the namespace per task |
| 3 | Typo in a resource/container/label name | Copy names from the task text; never retype |
| 4 | Output file missing, at the wrong path, or with extra text | `cat` the file afterwards; write exactly what was asked (e.g. only the pod name) |
| 5 | Didn't verify | One verification command per task, no exceptions |
| 6 | 20 minutes on one 4% task | Flag at the 6–8 minute mark and move on |
| 7 | Edited a running Pod's immutable field and gave up | `k get pod x -o yaml > x.yaml` → edit → `k replace --force -f x.yaml` |
| 8 | YAML indentation error | Generate with `$do`; vim `set expandtab shiftwidth=2`; `k apply --dry-run=server -f` to validate |
| 9 | Service selector doesn't match Pod labels | `k get endpointslices -l kubernetes.io/service-name=<svc>` must list pod IPs |
| 10 | `port` vs `targetPort` mixed up | `targetPort` = container port; `port` = Service port |
| 11 | Probe on the wrong port/path → restarts or never Ready | Check the container's actual port; `describe` shows the probe failures |
| 12 | Secret value with a trailing newline | `echo -n`, or use `--from-literal` |
| 13 | NetworkPolicy AND/OR confusion | Same `- ` list item = AND; separate list items = OR |
| 14 | Egress policy blocked DNS | Add UDP/TCP 53 egress when restricting egress |
| 15 | Wrong container in a multi-container pod | `-c <name>` for logs/exec; `set image` uses `<container>=<image>` |
| 16 | Forgot `--restart=Never` on a one-shot test pod | `k run tmp --rm -it --image=busybox:1.36 --restart=Never -- …` |
| 17 | Deprecated `apiVersion` copied from memory | `k explain <kind>` / `k api-resources` show the current group/version |
| 18 | Rollback to the wrong revision | Read `k rollout history deploy/x` (+ `--revision=N`) first |
| 19 | Canary ratio wrong | Traffic ≈ replica ratio: 20% of 5 pods = 1 canary + 4 stable, all sharing the Service label |
| 20 | Quota namespace rejected your pod | Quota needs requests/limits on every container; check `k describe quota` and the ReplicaSet events |
| 21 | SA change didn't apply | Pods can't change SA in place: `k set serviceaccount deploy/x sa` (new pods) or recreate the pod |
| 22 | Helm release in the wrong namespace | Always pass `-n <ns>`; `helm list -A` to find releases |
| 23 | Left the app broken while "improving" it | Make the minimal change the task asks for |
| 24 | Deleted something you weren't asked to delete | Never delete outside the task scope; prefer editing |
| 25 | Panic after a hard task | Remember the 66% math. Move on, bank the easy points. |

---

## 5. Using the docs fast

- Use the search box on kubernetes.io/docs; type the **kind** name ("NetworkPolicy", "PersistentVolume"). The concept pages have copy-ready YAML.
- Pages worth knowing by heart (all under kubernetes.io/docs):
  - Tasks → *Configure Pods and Containers* (probes, security context, service accounts, PV/PVC, ConfigMaps, resources)
  - Concepts → *Services, Load Balancing, and Networking* (Service, Ingress, NetworkPolicy, DNS)
  - Concepts → *Workloads* (Deployments, StatefulSets, DaemonSets, Jobs, CronJobs, init/sidecar containers)
  - Reference → *kubectl Quick Reference* (cheat sheet)
  - Reference → *Deprecated API Migration Guide*
  - Tasks → *Manage Kubernetes Objects* → *Declarative Management using Kustomize*
  - helm.sh/docs → *Helm Commands*
- Copy YAML from the docs into vim with paste mode (`:set paste`) so indentation survives. Then remove what you don't need.

---

## 6. Partial credit thinking

Tasks are usually graded by several checks: the object exists, field A is right, field B is right, the output file is right. If you can't finish:
- Still create the object with the correct **name, namespace, image and labels**. Those checks are cheap points.
- Write the output file even if you're unsure of the content.
- Leave notes for yourself, not half-applied broken objects that could affect another task.

---

## 7. Mindset

- The first 2–3 tasks often feel hard. That's normal; flag and move.
- If the environment lags, keep typing in your local `qN.yaml` and apply in one go.
- Don't spend time "cleaning up" unless the task asks for it.
- In the last 10 minutes, stop starting new long tasks. Verify and bank what you have.
