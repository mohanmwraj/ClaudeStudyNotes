# 06 - Cross-Cutting Skills and Bonus Topics

**Exam weight:** no weight of its own - this is **not** a curriculum domain. It holds (a) the speed skills that every task in all five domains depends on (kubectl generation and modification, JSONPath/custom-columns output, labels/selectors/namespaces, YAML, vim/bash) and (b) low-frequency topics that are not named in the CKAD curriculum but can still show up inside a task or in troubleshooting (scheduling and placement, HPA, PodDisruptionBudgets).

**Why this chapter exists:** most candidates who fail CKAD know the concepts but run out of time. Generating YAML instead of typing it, extracting exact output with JSONPath, editing YAML in vim without fighting indentation and reading scheduler/YAML error messages quickly are worth 10-20 minutes over the whole exam. The bonus topics are core CKA material - cheap to learn at the syntax level, expensive to meet unprepared.

> Version note: the exam currently runs Kubernetes **v1.37**; version remarks in this chapter refer to it, and the content is valid from v1.33 on. Exam environment details (hosts, tools, allowed docs) are summarised in [00-Exam-Overview-and-Setup](../00-Exam-Overview-and-Setup/README.md).

---

## Official competencies this chapter supports

Quoted verbatim from the CKAD curriculum; the chapter does not add a competency of its own.

| Domain (weight) | Competency (verbatim) | Supported here by |
|---|---|---|
| Application Design and Build (20%) | Choose and use the right workload resource (Deployment, DaemonSet, CronJob, etc.) | generators, Deployment → DaemonSet/StatefulSet conversion ([01](01-kubectl-power-usage.md)) |
| Application Deployment (20%) | Use Kubernetes primitives to implement common deployment strategies (e.g. blue/green or canary) | labels and selectors that switch traffic ([03](03-labels-selectors-annotations-namespaces.md)) |
| Application Deployment (20%) | Understand Deployments and how to perform rolling updates | `set image`, change-cause, patching ([01](01-kubectl-power-usage.md)); HPA ([05](05-autoscaling-hpa.md)); PDB vs rollouts ([06](06-pod-disruption-budgets.md)) |
| Application Observability and Maintenance (15%) | Understand API deprecations | removed HPA/PDB API versions ([05](05-autoscaling-hpa.md), [06](06-pod-disruption-budgets.md)) |
| Application Observability and Maintenance (15%) | Use built-in CLI tools to monitor Kubernetes applications | JSONPath, custom-columns, sort-by, `kubectl top` ([02](02-output-formatting-jsonpath-and-custom-columns.md)) |
| Application Observability and Maintenance (15%) | Debugging in Kubernetes | scheduler messages ([04](04-scheduling-and-placement.md)), YAML errors ([07](07-yaml-essentials.md)), test pods ([08](08-linux-vim-bash-tmux-for-the-exam.md)) |
| Application Environment, Configuration and Security (25%) | Discover and use resources that extend Kubernetes (CRD, Operators) | `kubectl api-resources` / `kubectl explain` on CRDs ([01](01-kubectl-power-usage.md)) |
| Application Environment, Configuration and Security (25%) | Understand requests, limits, quotas | requests drive scheduling and HPA utilization, QoS output ([04](04-scheduling-and-placement.md), [05](05-autoscaling-hpa.md)) |
| Application Environment, Configuration and Security (25%) | Create & consume Secrets | decoding Secret values into files ([02](02-output-formatting-jsonpath-and-custom-columns.md)) |
| Services and Networking (20%) | Provide and troubleshoot access to applications via services | Service selectors vs pod labels, EndpointSlices ([03](03-labels-selectors-annotations-namespaces.md)) |
| Services and Networking (20%) | Demonstrate basic understanding of NetworkPolicies | label/namespace selectors, `kubernetes.io/metadata.name` ([03](03-labels-selectors-annotations-namespaces.md)) |

> **Honest scope note:** nodeSelector/affinity/taints, topology spread, PriorityClass, HPA and PDB are **not named** in the current CKAD curriculum (they are CKA topics). They are covered because candidates report them occasionally and because "why is this pod Pending?" needs them. Prioritise the 🔥 rows below.

---

## Topic → file → exam frequency

| Topic | File(s) | Exam frequency |
|---|---|---|
| Generate YAML (`$do`), `explain`, `api-resources`, create/apply/replace/edit/patch/set | [01-kubectl-power-usage.md](01-kubectl-power-usage.md) | 🔥 High (every task) |
| JSONPath, custom-columns, sort-by, writing output to files | [02-output-formatting-jsonpath-and-custom-columns.md](02-output-formatting-jsonpath-and-custom-columns.md) | 🔥 High |
| Labels, selectors, annotations, namespaces, contexts | [03-labels-selectors-annotations-namespaces.md](03-labels-selectors-annotations-namespaces.md) | 🔥 High |
| YAML syntax, quoting, error messages | [07-yaml-essentials.md](07-yaml-essentials.md) | 🔥 High (every task) |
| vim, bash, network test tools, yq | [08-linux-vim-bash-tmux-for-the-exam.md](08-linux-vim-bash-tmux-for-the-exam.md) | 🔥 High (every task) |
| nodeSelector, taints and tolerations, control-plane placement | [04-scheduling-and-placement.md](04-scheduling-and-placement.md) | ⚡ Medium |
| HPA with `kubectl autoscale` | [05-autoscaling-hpa.md](05-autoscaling-hpa.md) | ⚡ Medium |
| Node affinity, pod (anti-)affinity | [04-scheduling-and-placement.md](04-scheduling-and-placement.md) | ⚡ Medium / 🧊 Low |
| Topology spread, PriorityClass and preemption | [04-scheduling-and-placement.md](04-scheduling-and-placement.md) | 🧊 Low |
| HPA `behavior`, VPA, KEDA, node autoscalers | [05-autoscaling-hpa.md](05-autoscaling-hpa.md) | 🧊 Low |
| PodDisruptionBudget, drain, eviction | [06-pod-disruption-budgets.md](06-pod-disruption-budgets.md) | 🧊 Low |
| tmux, jq (may not be available in the exam) | [08-linux-vim-bash-tmux-for-the-exam.md](08-linux-vim-bash-tmux-for-the-exam.md) | 🧊 Low |

---

## Must know - cannot skip

- [ ] Start every task on the named host/context (`ssh <host>` / `k config use-context ...`), `exit` back afterwards; re-export `$do`/`$now` on each new host.
- [ ] `export do="--dry-run=client -o yaml"` and generate Pod, Deployment, Service, Job, CronJob, ConfigMap, Secret, SA, Role/RoleBinding, Ingress, PDB, PriorityClass and HPA YAML from memory.
- [ ] Know the kinds without a generator (DaemonSet, StatefulSet, PV, PVC, NetworkPolicy) and convert/copy them fast.
- [ ] `k explain <kind>.<field> [--recursive]` for field names and nesting.
- [ ] Immutable Pod change: `/tmp/kubectl-edit-*.yaml` or exported YAML → `k replace --force -f`.
- [ ] One example each of strategic, `--type=merge` and `--type=json` patches.
- [ ] JSONPath `{range .items[*]}...{"\n"}{end}`, filters `?(@.type=="InternalIP")`, escaped dots; custom-columns with `--sort-by` and `--no-headers`.
- [ ] Redirect into the exact file path and `cat` it; write commands into files with `kubectl`, not `k`.
- [ ] Decode Secrets: `jsonpath | base64 -d` and go-template `base64decode`.
- [ ] Selectors `=`, `!=`, `in`, `notin`, `key`, `!key` on the CLI; `matchLabels` + `matchExpressions` in YAML; Service selectors are equality-only.
- [ ] `k label`/`k annotate` with `--overwrite` and `key-`; change-cause annotation.
- [ ] `k config set-context --current --namespace=<ns>`.
- [ ] Quote YAML values such as `"true"`, `"yes"`, `"1.10"`, `"0123"` and numeric env values; never quote integer fields.
- [ ] vim: `:set paste`, `V` + `>` / `<`, `Ctrl-v` block insert, `u`, `:%s/a/b/g`, `:wq`, `:q!`.
- [ ] Test pods: `k run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=2 http://svc`.
- [ ] Toleration + nodeSelector for dedicated/control-plane placement; `k taint ... key=value:Effect-` to remove.
- [ ] `k autoscale deploy x --min=2 --max=5 --cpu=70%` (v1.37), plus metrics-server and CPU requests as preconditions.

## Nice to know (low frequency, still covered)

- Server-side apply, `kubectl diff`, `kubectl wait`, kuberc preferences, KYAML output, `explain --max-depth` (v1.37).
- Node affinity operators incl. `Gt`/`Lt`, pod affinity `namespaceSelector` and `matchLabelKeys`, topology spread `minDomains`/`nodeTaintsPolicy`.
- PriorityClass `preemptionPolicy: Never`, preemption and `nominatedNodeName`; reading every `FailedScheduling` fragment.
- HPA v2 `behavior`, `ContainerResource` metrics, the `tolerance` field (stable in v1.37), VPA modes, KEDA, Cluster Autoscaler vs Karpenter, in-place pod resize.
- PDB rounding, `unhealthyPodEvictionPolicy`, the Eviction API, `kubectl drain` flags.
- tmux, jq/yq, network tools (`nc`, `dig`), copy/paste in the remote desktop.

---

## Recommended study order (about 6.5 hours)

| # | File | Time | Why in this order |
|---|---|---|---|
| 1 | [08-linux-vim-bash-tmux-for-the-exam.md](08-linux-vim-bash-tmux-for-the-exam.md) | 40 min | shell and vim muscle memory speeds up everything else |
| 2 | [01-kubectl-power-usage.md](01-kubectl-power-usage.md) | 60 min | generators and update commands are used in every task |
| 3 | [07-yaml-essentials.md](07-yaml-essentials.md) | 25 min | fix manifests quickly |
| 4 | [02-output-formatting-jsonpath-and-custom-columns.md](02-output-formatting-jsonpath-and-custom-columns.md) | 60 min | "write X into a file" tasks |
| 5 | [03-labels-selectors-annotations-namespaces.md](03-labels-selectors-annotations-namespaces.md) | 40 min | run the selector lab with [yaml/labels-selectors-demo.yaml](yaml/labels-selectors-demo.yaml) |
| 6 | [04-scheduling-and-placement.md](04-scheduling-and-placement.md) | 50 min | Pending-pod troubleshooting, placement tasks |
| 7 | [05-autoscaling-hpa.md](05-autoscaling-hpa.md) | 35 min | quick-win `kubectl autoscale` task |
| 8 | [06-pod-disruption-budgets.md](06-pod-disruption-budgets.md) | 20 min | quick-win `kubectl create pdb` task |
| 9 | [practice-questions.md](practice-questions.md) | 90 min | 24 timed tasks; redo the ones you missed |
| 10 | [commands.md](commands.md) | 15 min | final review sheet |

Then continue with the mock exams: [07-Mock-Exams](../07-Mock-Exams/README.md). Production depth: [08-Architect-Notes](../08-Architect-Notes/README.md).

---

## Files in this chapter

| File | Content |
|---|---|
| [01-kubectl-power-usage.md](01-kubectl-power-usage.md) | explain, api-resources (short-name table), YAML generators and kinds without one, create/apply/replace/edit/patch/set, server-side apply, the edit-failure flow, deletion, diff, wait, label/annotate, `get all` caveats, cp, contexts, kuberc |
| [02-output-formatting-jsonpath-and-custom-columns.md](02-output-formatting-jsonpath-and-custom-columns.md) | output formats, JSONPath syntax and quoting, custom-columns, sort-by, go-template, 25 ready-made one-liners, writing output to files |
| [03-labels-selectors-annotations-namespaces.md](03-labels-selectors-annotations-namespaces.md) | label syntax, CLI and YAML selectors, field selectors, recommended labels, annotations, namespaces, selector lab with expected results |
| [04-scheduling-and-placement.md](04-scheduling-and-placement.md) | nodeName, nodeSelector, node affinity, pod (anti-)affinity, taints/tolerations, topology spread, PriorityClass/preemption, scheduler messages |
| [05-autoscaling-hpa.md](05-autoscaling-hpa.md) | HPA v2 (metrics, targets, behavior), `kubectl autoscale` across versions, load test, VPA, KEDA, node autoscalers, in-place resize |
| [06-pod-disruption-budgets.md](06-pod-disruption-budgets.md) | voluntary vs involuntary disruptions, minAvailable/maxUnavailable and rounding, unhealthyPodEvictionPolicy, eviction and drain, sizing |
| [07-yaml-essentials.md](07-yaml-essentials.md) | indentation, lists of maps, multi-line strings, quoting traps, multiple documents, error messages and fixes |
| [08-linux-vim-bash-tmux-for-the-exam.md](08-linux-vim-bash-tmux-for-the-exam.md) | exam host tools and per-host setup, vim, bash, network tools, tmux, yq/jq, copy/paste |
| [commands.md](commands.md) | every command of the chapter, grouped, one-line comments |
| [practice-questions.md](practice-questions.md) | 24 exam-style tasks with solutions and verification |

### yaml/ index

| File | What it shows |
|---|---|
| [yaml/namespace.yaml](yaml/namespace.yaml) | two namespaces with labels and annotations, a namespaced ConfigMap |
| [yaml/labels-selectors-demo.yaml](yaml/labels-selectors-demo.yaml) | selector lab: 7 labelled pods, Deployment with `matchExpressions` (In/NotIn/Exists/DoesNotExist), equality-only Service |
| [yaml/node-selector-pod.yaml](yaml/node-selector-pod.yaml) | `nodeSelector` on a custom label and on well-known node labels |
| [yaml/node-affinity-pod.yaml](yaml/node-affinity-pod.yaml) | required + preferred node affinity, `Gt`, `DoesNotExist` (avoid control-plane nodes) |
| [yaml/pod-affinity-anti-affinity.yaml](yaml/pod-affinity-anti-affinity.yaml) | one cache per node (required anti-affinity) and web pods co-located with caches (pod affinity) |
| [yaml/taints-tolerations-pod.yaml](yaml/taints-tolerations-pod.yaml) | `Equal`/`Exists` tolerations, `NoExecute` + `tolerationSeconds`, control-plane placement |
| [yaml/topology-spread-deployment.yaml](yaml/topology-spread-deployment.yaml) | hard per-node spread (`matchLabelKeys`, `nodeTaintsPolicy`) plus soft per-zone spread |
| [yaml/priorityclass.yaml](yaml/priorityclass.yaml) | preempting and non-preempting PriorityClasses and a pod using one |
| [yaml/hpa-cpu.yaml](yaml/hpa-cpu.yaml) | Deployment + Service + `autoscaling/v2` HPA on CPU utilization (load-test target) |
| [yaml/hpa-behavior.yaml](yaml/hpa-behavior.yaml) | HPA with CPU Utilization + memory AverageValue and tuned scale-up/scale-down behavior |
| [yaml/pdb-min-available.yaml](yaml/pdb-min-available.yaml) | Deployment + PDB with `minAvailable` |
| [yaml/pdb-max-unavailable.yaml](yaml/pdb-max-unavailable.yaml) | Deployment + PDB with percentage `maxUnavailable` and `unhealthyPodEvictionPolicy: AlwaysAllow` |
| [yaml/vimrc.txt](yaml/vimrc.txt) | annotated YAML-friendly `~/.vimrc` (and the one-liner for exam hosts) |
| [yaml/bashrc-exam-snippet.sh](yaml/bashrc-exam-snippet.sh) | idempotent installer for `k`, completion, `$do`, `$now` on a practice machine (`bash yaml/bashrc-exam-snippet.sh`) |

Related chapters: [00 Exam overview and setup](../00-Exam-Overview-and-Setup/README.md) · [01 Design and Build](../01-Application-Design-and-Build/README.md) · [02 Deployment](../02-Application-Deployment/README.md) · [03 Observability and Maintenance](../03-Application-Observability-and-Maintenance/README.md) · [04 Environment, Configuration and Security](../04-Application-Environment-Configuration-and-Security/README.md) · [05 Services and Networking](../05-Services-and-Networking/README.md) · [07 Mock Exams](../07-Mock-Exams/README.md) · [08 Architect Notes](../08-Architect-Notes/README.md)
