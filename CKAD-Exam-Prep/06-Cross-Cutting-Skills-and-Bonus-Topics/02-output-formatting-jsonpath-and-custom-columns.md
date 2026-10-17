# Output Formatting: JSONPath, custom-columns, sort-by

**Why it matters / what the exam expects:** many tasks end with "write ... into `/opt/course/N/<file>`": pod names, IPs, images, a decoded Secret value, the pod with most restarts, a sorted list. A checker reads that file, so the content must be exactly what was asked - no headers, no `pod/` prefixes, the right order. JSONPath, custom-columns and `--sort-by` give you exact output without hand-editing.

> Conventions: `alias k=kubectl`. Practise these in a Linux shell (exam terminal, WSL or Git Bash): Windows PowerShell/cmd quote JSONPath differently.

---

## Core concepts

### Output formats

| Flag | Prints | Typical use |
|---|---|---|
| *(none)* | default table | humans |
| `-o wide` | table + extra columns (pods: IP, NODE, NOMINATED NODE, READINESS GATES) | where is it running |
| `-o yaml` / `-o json` | the full object | inspect, export, find a field path |
| `-o name` | `kind/name`, e.g. `pod/web` | piping into other commands |
| `-o jsonpath='{...}'` | a JSONPath template | extract exact values |
| `-o jsonpath-file=f.tmpl` | template read from a file | long templates |
| `-o jsonpath-as-json='{...}'` | the matches as a JSON array | feed to `yq` / `jq` / scripts |
| `-o custom-columns=HDR:path,...` | your own table | readable reports with chosen fields |
| `-o custom-columns-file=f.txt` | columns read from a file | reuse |
| `-o go-template='{{...}}'` / `-o go-template-file=f` | Go template (has `base64decode`, `if`, `eq`, `index`) | decode Secrets, conditionals |
| `-o kyaml` | KYAML (flow-style YAML, quoted strings) | alpha in v1.34 (`KUBECTL_KYAML=true`), beta and on by default since v1.35 |

### Finding the path

1. `k get pod web -o yaml` - the indentation **is** the path: `status:` → `podIP:` = `.status.podIP`.
2. `k explain pod.status.containerStatuses` - names and types of the nested fields.
3. A **single object** starts at the object: `{.status.podIP}`. A **list** (`k get pods`) is wrapped in `kind: List` → start with `{.items[*]...}`.

```bash
k get pod web -o jsonpath='{.status.podIP}'             # single object
k get pods    -o jsonpath='{.items[*].status.podIP}'    # list: every item, space-separated on ONE line
```

---

## Key fields / syntax

### JSONPath syntax (kubectl flavour)

| Syntax | Meaning | Example |
|---|---|---|
| `{ }` | wraps every expression; text outside braces is printed literally | `'name: {.metadata.name}'` |
| `.field` or `['field']` | child | `{.spec.nodeName}` |
| `$` | root (optional, kubectl always starts at the root) | `{$.kind}` |
| `[n]` | index (0-based) | `{.items[0].metadata.name}` |
| `[-1:]` | last element (negative slice) | `{.items[-1:].metadata.name}` |
| `[a:b]` | slice, `b` exclusive | `{.items[0:3].metadata.name}` |
| `[*]` | every element | `{.items[*].metadata.name}` |
| `..` | recursive descent - every field with that name at any depth | `{..image}` (also matches `status.containerStatuses[*].image` - duplicates!) |
| `[,]` | union | `{.items[*]['metadata.name','status.podIP']}` |
| `?()` with `@` | filter: `==` `!=` `<` `>` `<=` `>=`, or existence `?(@.field)` | `{.items[?(@.status.phase=="Running")].metadata.name}` |
| `{range ...}...{end}` | loop - needed for one-item-per-line output | `{range .items[*]}{.metadata.name}{"\n"}{end}` |
| `{"\n"}` `{"\t"}` | literal newline / tab | |
| `\.` | escape a dot inside a key name | `{.metadata.labels.app\.kubernetes\.io/name}` |
| **not supported** | regular expressions (`=~`), `&&` / `\|\|` in filters | pipe to `grep`, `awk` or `yq` instead |

### Bash quoting rules

| Rule | Example |
|---|---|
| Wrap the whole template in **single quotes** | `-o jsonpath='{.items[*].metadata.name}'` |
| Use **double quotes inside** for string literals | `{"\n"}` · `?(@.type=="Ready")` |
| Need a shell variable? Close and reopen the single quotes | `-o jsonpath='{.items[?(@.metadata.name=="'"$POD"'")].status.podIP}'` |
| Quote custom-columns too when they contain `[` `?` `(` `"` | `-o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status'` |
| Output has **no trailing newline** unless you add `{"\n"}` | `...'{.status.podIP}{"\n"}'` or `; echo` (screen only) |

### Loops, filters, nesting

```bash
# one pod per line: name<TAB>IP
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'

# nested loop: pod name followed by all of its container images
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{":"}{range .spec.containers[*]}{" "}{.image}{end}{"\n"}{end}'

# filter on a list of maps (conditions, addresses, ports, containers ...)
k get pod web -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}{"\n"}'
k get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}{"\n"}'
k get pod web -o jsonpath='{.spec.containers[?(@.name=="sidecar")].image}{"\n"}'

# existence filter: pods that set a nodeSelector at all
k get pods -o jsonpath='{.items[?(@.spec.nodeSelector)].metadata.name}{"\n"}'

# keys that contain dots or slashes
k get deploy web -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}{"\n"}'
k get secret tls-web -o jsonpath='{.data.tls\.crt}' | base64 -d | head -3

# long template in a file
cat > pods.tmpl <<'EOF'
{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}
EOF
k get pods -o jsonpath-file=pods.tmpl
```

### custom-columns

```bash
k get pods -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IP:.status.podIP
k get pods -o custom-columns='POD:.metadata.name,IMAGES:.spec.containers[*].image'   # [*] -> comma-joined
k get pods -o custom-columns='NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status'
k get pods --no-headers -o custom-columns=NAME:.metadata.name                         # names only
```

- Format: `HEADER:JSONPATH`, comma-separated, **no** `{}`; the leading `.` is optional.
- Missing fields print `<none>`; lists print comma-separated values.
- File variant (`-o custom-columns-file=cols.txt`): line 1 = headers, line 2 = paths:

```text
NAME            NODE           IP
.metadata.name  .spec.nodeName .status.podIP
```

### `--sort-by` and `--no-headers`

```bash
k get pods --sort-by=.metadata.creationTimestamp                     # oldest first (ascending only)
k get pods --sort-by=.metadata.creationTimestamp --no-headers | tac  # newest first
k get pods --sort-by='.status.containerStatuses[0].restartCount'     # fewest -> most restarts
k get pv --sort-by=.spec.capacity.storage                            # quantities sort numerically
k get events -A --sort-by=.metadata.creationTimestamp                # timeline of events
k get pods -A -o wide --sort-by=.spec.nodeName                       # group by node
```

- The expression must yield **one** string/number/time per item: use `[0]`, not `[*]`.
- `--sort-by` takes a JSONPath with or without braces (`'{.metadata.name}'` also works).
- `--no-headers` works for the default table and custom-columns (`-o name` / jsonpath never print headers).

### go-template (when JSONPath is not enough)

```bash
k get pods -o go-template='{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}'
k get secret db -o go-template='{{.data.password | base64decode}}{{"\n"}}'          # decode in one step
k get secret db -o go-template='{{range $k, $v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}'   # every key
k get pods -o go-template='{{range .items}}{{if eq .status.phase "Running"}}{{.metadata.name}}{{"\n"}}{{end}}{{end}}'
k get deploy web -o go-template='{{index .metadata.labels "app.kubernetes.io/name"}}{{"\n"}}'
```

### Combining with Unix tools

```bash
k get pods -A --no-headers | wc -l                                    # count pods
k get pods -A --no-headers | awk '{print $1}' | sort | uniq -c        # pods per namespace
k get pods --no-headers | grep -v Running                             # not Running, incl. CrashLoopBackOff
k get pods -A -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c   # pods per node
k get pods -o name | xargs -I{} kubectl get {} -o jsonpath='{.metadata.name} {.spec.serviceAccountName}{"\n"}'
k get pods -A -o wide | tee /tmp/pods.txt                             # see AND save
k get pods -o yaml | yq '.items[] | select(.status.phase == "Running") | .metadata.name'     # yq (available on exam hosts)
k get pods -o json | jq -r '.items[] | select(.status.phase=="Running") | .metadata.name'    # jq - may NOT be available in the exam
```

> **Exam tip:** do not `awk` table columns by position when exact output matters: the RESTARTS column can read `3 (2m ago)`, which contains spaces and shifts every later column. Use JSONPath or custom-columns for exact fields.

---

## Imperative commands

### Ready-made one-liners for typical tasks

```bash
# 1. Pod names, one per line (no header, no "pod/" prefix)
k get pods -n team-a -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
#    same with custom-columns:   k get pods -n team-a --no-headers -o custom-columns=NAME:.metadata.name
#    with the kind prefix:       k get pods -n team-a -o name

# 2. Every image running in the cluster, with counts (from the official docs task)
k get pods -A -o jsonpath='{.items[*].spec.containers[*].image}' | tr -s '[[:space:]]' '\n' | sort | uniq -c
#    unique list only:  ... | tr -s '[[:space:]]' '\n' | sort -u     (add .spec.initContainers[*].image if asked)

# 3. Images per pod
k get pods -o custom-columns='POD:.metadata.name,IMAGES:.spec.containers[*].image'

# 4. Pods running on a given node (all namespaces)
k get pods -A --field-selector spec.nodeName=node01 -o wide

# 5. Restart counts, sorted ascending
k get pods -o custom-columns='NAME:.metadata.name,RESTARTS:.status.containerStatuses[*].restartCount' --sort-by='.status.containerStatuses[0].restartCount'

# 6. The pod with the most restarts (namespace + name)
k get pods -A --sort-by='.status.containerStatuses[0].restartCount' --no-headers -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name | tail -1

# 7. Node name + InternalIP
k get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'

# 8. Decoded Secret value (single key / all keys)
k get secret db -n team-a -o jsonpath='{.data.password}' | base64 -d; echo
k get secret db -n team-a -o go-template='{{range $k, $v := .data}}{{$k}}={{$v | base64decode}}{{"\n"}}{{end}}'

# 9. QoS class of every pod
k get pods -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass

# 10. Container names in a pod (init containers first)
k get pod web -o jsonpath='init: {.spec.initContainers[*].name}{"\n"}app: {.spec.containers[*].name}{"\n"}'

# 11. Pod IPs and nodes
k get pods -o custom-columns=NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName

# 12. Pods whose phase is not Running (NOTE: CrashLoopBackOff pods are still phase Running!)
k get pods -A --field-selector=status.phase!=Running

# 13. Ready condition per pod
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}'

# 14. Deployments with image and replica count
k get deploy -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image,REPLICAS:.spec.replicas'

# 15. Service ClusterIP and the first NodePort
k get svc web -o jsonpath='{.spec.clusterIP}{" "}{.spec.ports[0].nodePort}{"\n"}'

# 16. Newest pod name
k get pods --sort-by=.metadata.creationTimestamp --no-headers -o custom-columns=NAME:.metadata.name | tail -1

# 17. ServiceAccount used by each pod
k get pods -o custom-columns=NAME:.metadata.name,SA:.spec.serviceAccountName

# 18. Requests / limits per container of a pod
k get pod web -o jsonpath='{range .spec.containers[*]}{.name}{"\t"}{.resources.requests.cpu}{"\t"}{.resources.requests.memory}{"\t"}{.resources.limits.cpu}{"\t"}{.resources.limits.memory}{"\n"}{end}'

# 19. Number of pods per node
k get pods -A -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | uniq -c

# 20. Node taints
k get nodes -o custom-columns='NAME:.metadata.name,TAINTS:.spec.taints[*].key,EFFECT:.spec.taints[*].effect'

# 21. PersistentVolumes sorted by capacity
k get pv --sort-by=.spec.capacity.storage -o custom-columns=NAME:.metadata.name,CAPACITY:.spec.capacity.storage,CLAIM:.spec.claimRef.name

# 22. Current namespace of the current context (empty = default)
k config view --minify -o jsonpath='{..namespace}'; echo

# 23. Pod using the most CPU right now (needs metrics-server)
k top pod -A --sort-by=cpu --no-headers | head -1

# 24. Warning events, newest last
k get events -A --field-selector type=Warning --sort-by=.metadata.creationTimestamp

# 25. Kubelet version and OS image per node
k get nodes -o custom-columns=NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion,OS:.status.nodeInfo.osImage
```

### Writing output to a file exactly as asked

```bash
mkdir -p /opt/course/1                                       # the directory may not exist yet
k get pods -n team-a -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' > /opt/course/1/pods.txt
cat /opt/course/1/pods.txt                                   # ALWAYS look at the result
cat -A /opt/course/1/pods.txt                                # '$' = line end, '^I' = tab: spot stray spaces/headers
k get pods -A -o wide | tee /opt/course/1/all.txt            # print and save at the same time
k logs web -c app > /opt/course/1/web.log                    # logs to a file
k logs web -c app 2>&1 | tee /opt/course/1/web.log           # include stderr messages too
k get pods -A >> /opt/course/1/all.txt                       # >> appends, > overwrites
```

When the task wants the **command** (not its output) in a file, use `kubectl` (aliases do not exist in non-interactive shells) and a quoted heredoc so nothing gets expanded:

```bash
cat > /opt/course/2/pods-by-age.sh <<'EOF'
kubectl get pods -A --sort-by=.metadata.creationTimestamp
EOF
bash /opt/course/2/pods-by-age.sh                            # prove that it works
```

| The task says | Produce |
|---|---|
| "names of the pods" | one name per line, no header, no `pod/` prefix (jsonpath `range` or `--no-headers -o custom-columns`) |
| "in the format `name:ip`" | build exactly that: `{range .items[*]}{.metadata.name}{":"}{.status.podIP}{"\n"}{end}` |
| "the decoded value" | `base64 -d`, not the base64 string |
| "sorted by ..." | `--sort-by=` (ascending) or pipe to `sort` / `tac` |
| "the command" | the command text in the file, using `kubectl`, tested with `bash file` |

---

## Exam traps & tips

> **Exam tip:** `{.items[*].metadata.name}` prints everything on ONE line separated by spaces. If the task wants one per line, use `{range .items[*]}...{"\n"}{end}`.

> **Exam tip:** a CrashLoopBackOff pod has `status.phase=Running`. `--field-selector status.phase!=Running` will not show it - use `k get pods | grep -v Running` or check `.status.containerStatuses[*].state`.

> **Exam tip:** the `-o name` output is `pod/web`, not `web`. Many "write the names" tasks want plain names.

> **Exam tip:** after redirecting into a file, `cat` it. An empty file usually means a JSONPath typo (kubectl prints nothing for a non-existent path) or the wrong namespace.

- Labels, annotations and Secret keys containing dots need `\.` in JSONPath: `{.data.tls\.crt}`.
- `{..image}` on pods also matches `status.containerStatuses[*].image` - use the explicit `.spec.containers[*].image` path.
- `--sort-by` with `[*]` is ambiguous; use `[0]`.
- `jq` may not be available in the exam; `yq` is listed as available (one-liners in [08](08-linux-vim-bash-tmux-for-the-exam.md)), and JSONPath / go-template always work.
- JSONPath has no `&&`, no `||` and no regex: filter twice, or pipe to `grep`/`awk`.

---

## Architect notes

- Scripts and CI jobs should consume `-o json` / `-o jsonpath`, never parse the human table output (columns change between kubectl versions, e.g. the RESTARTS format).
- `-o json` plus `jq` (or `-o yaml` plus `yq`) is the robust combination for automation; JSONPath alone cannot express boolean logic.
- For fleet-wide inventory (images, versions, owners), prefer a proper source - kube-state-metrics, an admission/inventory controller or a policy engine report - over ad-hoc kubectl loops.
- Standardise label keys (`app.kubernetes.io/*`) so custom-columns reports and dashboards work across teams.
- Secret values printed with `base64 -d` end up in shell history and terminal scrollback; in production use short-lived RBAC and audit logging for `get secrets`.
- KYAML (`-o kyaml`, beta in v1.35) avoids YAML's implicit typing traps when you hand manifests to other tools or people.

---

## Docs to bookmark

- JSONPath Support: https://kubernetes.io/docs/reference/kubectl/jsonpath/
- kubectl Quick Reference - formatting output, sorting: https://kubernetes.io/docs/reference/kubectl/quick-reference/
- kubectl overview - output options, custom columns, sorting: https://kubernetes.io/docs/reference/kubectl/
- List All Container Images Running in a Cluster: https://kubernetes.io/docs/tasks/access-application-cluster/list-all-running-container-images/
- KYAML reference: https://kubernetes.io/docs/reference/encodings/kyaml/

---

## Quick self-check

1. Print every pod's name and node, one per line, separated by a tab.
2. Why does `k get pods -o jsonpath='{.items[*].metadata.name}' > names.txt` often not satisfy "one name per line"?
3. Get the InternalIP of node `node01` only.
4. Decode key `tls.crt` of Secret `web-tls`.
5. Sort pods by restart count and print only the name of the pod with the most restarts.

<details><summary>Answers</summary>

1. `k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'`
2. `[*]` without `range` prints all names on one line separated by spaces.
3. `k get node node01 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}'`
4. `k get secret web-tls -o jsonpath='{.data.tls\.crt}' | base64 -d`
5. `k get pods --sort-by='.status.containerStatuses[0].restartCount' --no-headers -o custom-columns=NAME:.metadata.name | tail -1`

</details>
