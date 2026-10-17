# Rolling updates and rollbacks

**Why it matters.** "Update the image, record why, check the rollout, roll back to revision N" is one of the most common CKAD task patterns. You need:

- the `kubectl rollout` subcommands from memory
- the maxSurge/maxUnavailable arithmetic, which tasks ask about ("at most N Pods", "never below N")
- the knowledge that a rollback is a new revision, not a time machine

## Core concepts

### How a RollingUpdate proceeds

1. A change to `spec.template` makes the controller create (or reuse) a ReplicaSet for the new template. That ReplicaSet becomes the "new RS".
2. It scales the new RS up and the old RS(s) down in small steps. Two bounds hold at every moment:
   - **total Pods ≤ replicas + maxSurge**
   - **available Pods ≥ replicas − maxUnavailable**
3. A new Pod helps the rollout only when it is **Ready** (readiness probe) and has stayed Ready for `minReadySeconds`. With no readiness probe, "Ready" just means the container started.
4. Done = all replicas updated and available → condition `Progressing=True, reason NewReplicaSetAvailable`.
5. **Rollover:** if you change the template again mid-rollout, the controller creates yet another ReplicaSet. The one it was scaling up joins the "old" list and is scaled down. It does not wait for the first rollout to finish.

`Recreate` instead scales every old ReplicaSet to 0, waits until all old Pods are gone, then scales the new one up. There is downtime by design. File: [yaml/deployment-recreate.yaml](yaml/deployment-recreate.yaml).

### The maxSurge / maxUnavailable arithmetic

```text
surge       = maxSurge       as integer, or ceil (ROUND UP)    of pct x replicas
unavailable = maxUnavailable as integer, or floor (ROUND DOWN) of pct x replicas
if surge == 0 and unavailable == 0 after rounding  ->  controller uses unavailable = 1
max Pods during the update = replicas + surge
min available Pods         = replicas - unavailable
```

- Defaults: `maxSurge: 25%`, `maxUnavailable: 25%`.
- Explicitly setting **both** to 0 is rejected by validation.
- With percentages, rounding can make both 0 (e.g. `maxSurge: 0`, `maxUnavailable: 25%` with 3 replicas). Validation can't catch that, so the controller falls back to `unavailable = 1`.

**Worked examples (3, 4 and 10 replicas)**

| replicas | maxSurge / maxUnavailable | surge | unavailable | **max Pods** | **min available** | Character |
|---|---|---|---|---|---|---|
| 3 | 25% / 25% (default) | ceil(0.75) = 1 | floor(0.75) = 0 | **4** | **3** | Behaves like 1/0 |
| 4 | 25% / 25% (default) | ceil(1.0) = 1 | floor(1.0) = 1 | **5** | **3** | |
| 10 | 25% / 25% (default) | ceil(2.5) = 3 | floor(2.5) = 2 | **13** | **8** | |
| 3 | 1 / 0 | 1 | 0 | **4** | **3** | Zero capacity loss, needs room for 1 extra Pod |
| 4 | 1 / 0 | 1 | 0 | **5** | **4** | |
| 10 | 1 / 0 | 1 | 0 | **11** | **10** | Slow: one Pod at a time |
| 3 | 0 / 1 | 0 | 1 | **3** | **2** | No extra Pods (tight quota), loses 1 Pod of capacity |
| 4 | 0 / 1 | 0 | 1 | **4** | **3** | |
| 10 | 0 / 1 | 0 | 1 | **10** | **9** | |
| 3 | 25% / 0 | ceil(0.75) = 1 | 0 | **4** | **3** | |
| 10 | 25% / 0 | ceil(2.5) = 3 | 0 | **13** | **10** | |
| 3 | 0 / 25% | 0 | floor(0.75) = 0 → **1** | **3** | **2** | Both rounded to 0, so the controller forces 1 |
| 10 | 0 / 25% | 0 | floor(2.5) = 2 | **10** | **8** | |
| 10 | 100% / 0 | 10 | 0 | **20** | **10** | Full second set first: fast, 2x resources |
| any | 0 / 0 | n/a | n/a | n/a | n/a | **Rejected by the API** |

**Timeline: 4 replicas, maxSurge 1, maxUnavailable 0 (bounds: 5 / 4).** Each step waits for the new Pod to be Ready:

```text
step  old RS  new RS  total  available  action
0     4       0       4      4          start
1     4       1       5      4          +1 new (surge used up)
2     3       1       4      4          new Pod Ready -> -1 old
3     3       2       5      4          +1 new
...   ...     ...     ...    ...        repeat
8     0       4       4      4          done: Progressing=True NewReplicaSetAvailable
```

**10 replicas, 25%/25% (bounds 13 / 8).** The first step creates 3 new Pods and removes 2 old ones at once (8 old + 3 new = 11). After that, every time new Pods become available more old Pods go and more new Pods come, never above 13 total or below 8 available. The exact batch sizes depend on timing. The two bounds never change.

### Ways to change the template (each starts a rollout)

| Method | Example | Note |
|---|---|---|
| `kubectl set image` | `kubectl set image deploy/web web=nginx:1.27-alpine` | Fastest. `*=img` sets every container |
| `kubectl set env` / `set resources` | `kubectl set env deploy/web MODE=blue` | |
| `kubectl edit` | `kubectl edit deploy web` | Opens `$EDITOR`. The rollout starts on save |
| `kubectl apply -f` | Edit the file, apply | The declarative route. The file is the source of truth |
| `kubectl patch` | `kubectl patch deploy web -p '{"spec":{"template":{"spec":{"containers":[{"name":"web","image":"nginx:1.27-alpine"}]}}}}'` | Containers merge by `name` |
| `kubectl rollout restart` | `kubectl rollout restart deploy/web` | Adds `kubectl.kubernetes.io/restartedAt` to the template. Same spec, new Pods |
| `kubectl replace` | `kubectl replace -f web.yaml` | Full object replace (`--force` = delete + create) |

### Change-cause: recording why

`kubectl rollout history` prints the `kubernetes.io/change-cause` annotation of each revision's ReplicaSet. The controller copies the Deployment's annotations onto the current ReplicaSet on every sync. That gives these rules:

- **Change first, annotate second**: `kubectl set image ...` then `kubectl annotate deploy/web kubernetes.io/change-cause="..." --overwrite`.
- **Annotating before the change overwrites the cause of the revision that is still current.**
- **Forget to annotate and the new revision inherits the previous text.** The history then lies.
- `--overwrite` is required once the annotation exists. Without it kubectl refuses: `--overwrite is false but found the following declared annotation(s)`.
- Declarative alternative: put the annotation in `metadata.annotations` of the manifest and `kubectl apply`. Template and cause change in one step.
- `--record` is **deprecated** (hidden from `--help`, prints a warning). It stores the whole command line as the cause. Don't rely on it.

### History and rollback semantics

```text
$ kubectl rollout history deployment/web
deployment.apps/web
REVISION  CHANGE-CAUSE
1         initial release nginx:1.27
2         upgrade to nginx:1.27-alpine
3         upgrade to nginx:does-not-exist          <- broken (ImagePullBackOff)

$ kubectl rollout undo deployment/web               # = back to the previous revision (2)
deployment.apps/web rolled back

$ kubectl rollout history deployment/web
REVISION  CHANGE-CAUSE
1         initial release nginx:1.27
3         upgrade to nginx:does-not-exist
4         upgrade to nginx:1.27-alpine             <- revision 2 is gone: its template now IS revision 4

$ kubectl rollout undo deployment/web --to-revision=1
$ kubectl rollout history deployment/web
REVISION  CHANGE-CAUSE
3         upgrade to nginx:does-not-exist
4         upgrade to nginx:1.27-alpine
5         initial release nginx:1.27
```

What `rollout undo` really does:

1. It reads the Pod template stored in the target revision's ReplicaSet, removes `pod-template-hash`, and writes it back into the Deployment's `spec.template`. It also copies that ReplicaSet's annotations, including the change-cause, onto the Deployment.
2. The template now matches the old ReplicaSet, so the controller re-uses it (no new ReplicaSet) and gives it **the next revision number**. The old number disappears from the history. The old numbers are kept in the ReplicaSet annotation `deployment.kubernetes.io/revision-history`.
3. It is a normal rolling update governed by the current `strategy`.
4. **Only the Pod template is rolled back.** `replicas`, `strategy`, the Deployment's labels, and the contents of ConfigMaps/Secrets are not restored.
5. It fails on a paused Deployment: `you cannot rollback a paused deployment; resume it first with 'kubectl rollout resume' and try again`.
6. If the target equals the current template you get `skipped rollback (current template already matches revision N)`. A revision that was cleaned up (beyond `revisionHistoryLimit`) gives `unable to find specified revision N in history`.

`kubectl rollout history deployment/web --revision=3` prints that revision's Pod template (image, env, labels, change-cause). Use it to find which revision had a given image. `kubectl rollout undo deployment/web --to-revision=1 --dry-run=client` prints the Pod template a rollback would restore, without changing anything.

### Pause and resume (Deployments only)

| Action | Effect |
|---|---|
| `kubectl rollout pause deployment/web` | Sets `spec.paused=true`. Condition `Progressing=Unknown, reason DeploymentPaused`. The progress deadline is not checked |
| Template changes while paused | Saved in the spec, **no new ReplicaSet**. Batch several changes (image, env, resources) into **one** revision |
| Scaling while paused | Still works (`kubectl scale`) |
| Pausing in the middle of a rollout | Freezes the current mix of old and new Pods: a quick manual canary |
| `kubectl rollout resume deployment/web` | One rollout with all accumulated changes |
| `undo` / `restart` while paused | Refused. Resume first |

### Restart

`kubectl rollout restart deployment/web` (also works for `daemonset` and `statefulset`, and with `--selector=app=web`) re-creates all Pods following the strategy. Typical reasons: pick up a changed ConfigMap or Secret used as env vars, re-pull a mutable tag, clear a bad in-memory state. It creates a new revision whose template differs only by the `kubectl.kubernetes.io/restartedAt` annotation.

### Detecting a failed rollout

| Signal | Command |
|---|---|
| `rollout status` exits non-zero | `kubectl rollout status deploy/web --timeout=90s; echo $?`. Exit 1 when the progress deadline is exceeded (`error: deployment "web" exceeded its progress deadline`) or the `--timeout` expires |
| Progressing condition | `kubectl get deploy web -o jsonpath='{.status.conditions[?(@.type=="Progressing")].reason}'` → `ProgressDeadlineExceeded` |
| ReplicaSet counts | `kubectl get rs -l app=web`: the new RS has DESIRED > READY and stays that way |
| Pods | `kubectl get pods -l app=web`: `ErrImagePull`/`ImagePullBackOff`, `CrashLoopBackOff`, `0/1 Running` (readiness failing), `Pending` (unschedulable) |
| Quota / admission | `kubectl describe deploy web` shows `ReplicaFailure=True, FailedCreate`, and `kubectl get events` has the API error |

The deadline is `progressDeadlineSeconds` (default 600 s). Kubernetes **never rolls back automatically**. The old Pods that maxUnavailable kept alive continue serving. You fix forward (`set image` again) or `rollout undo`. A CI pattern: `kubectl rollout status deploy/web --timeout=120s || kubectl rollout undo deploy/web`.

### DaemonSet and StatefulSet rollouts (brief)

| | Deployment | DaemonSet | StatefulSet |
|---|---|---|---|
| Field | `spec.strategy` | `spec.updateStrategy` | `spec.updateStrategy` |
| Types | `RollingUpdate` (default), `Recreate` | `RollingUpdate` (default), `OnDelete` | `RollingUpdate` (default), `OnDelete` |
| Knobs | `maxSurge` 25%, `maxUnavailable` 25% | `maxUnavailable` (default 1), `maxSurge` (default 0) | `partition` (only ordinals ≥ partition update), `maxUnavailable` (beta since v1.35, default 1) |
| Order | Any | Node by node | Highest ordinal first, one at a time, each must be Ready |
| History objects | ReplicaSets | ControllerRevisions | ControllerRevisions |
| `rollout status/history/undo/restart` | Yes | Yes | Yes |
| `rollout pause/resume` | Yes | **No** | **No** |

Example file: [yaml/daemonset-statefulset-updates.yaml](yaml/daemonset-statefulset-updates.yaml). A StatefulSet stuck on a broken Pod (OrderedReady) needs the template reverted **and** the broken Pod deleted (the "forced rollback" in the docs). A `Recreate` update strategy for StatefulSets exists only as **alpha in v1.37**, the exam's version (feature gate `StatefulSetRecreateStrategy`, off by default). Don't count on it in the exam cluster.

## Key fields / syntax

```yaml
# Zero-downtime rolling update: never lose capacity, add one Pod at a time
spec:
  minReadySeconds: 10
  progressDeadlineSeconds: 300
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1          # integer or "25%"
      maxUnavailable: 0
```

```yaml
# Recreate: the rollingUpdate block must be absent (null) or the API rejects the object
spec:
  strategy:
    type: Recreate
```

Full files: [yaml/deployment-rolling-update.yaml](yaml/deployment-rolling-update.yaml) · [yaml/deployment-recreate.yaml](yaml/deployment-recreate.yaml).

## Imperative commands

```bash
# 0. Starting point (generate, then apply)
kubectl create deployment web --image=nginx:1.27 --replicas=4 --dry-run=client -o yaml > web.yaml
kubectl apply -f web.yaml
kubectl annotate deployment/web kubernetes.io/change-cause="initial release nginx:1.27" --overwrite

# 1. Update + record the cause (change FIRST, annotate SECOND)
kubectl set image deployment/web nginx=nginx:1.27-alpine          # container is "nginx" (named after the image)
kubectl annotate deployment/web kubernetes.io/change-cause="upgrade to nginx:1.27-alpine" --overwrite
kubectl rollout status deployment/web                              # blocks until done; non-zero exit on failure
kubectl rollout status deployment/web --timeout=60s                # bounded wait
kubectl rollout status deployment/web --watch=false                # one-shot check

# 2. History
kubectl rollout history deployment/web
kubectl rollout history deployment/web --revision=2                # template of revision 2

# 3. Rollback
kubectl rollout undo deployment/web                                # previous revision
kubectl rollout undo deployment/web --to-revision=1                # specific revision
kubectl rollout undo deployment/web --to-revision=1 --dry-run=client  # preview: prints the template it would restore

# 4. Batch several changes into one revision
kubectl rollout pause deployment/web
kubectl set image deployment/web nginx=nginx:1.27
kubectl set env deployment/web LOG_LEVEL=info
kubectl set resources deployment/web -c nginx --limits=memory=128Mi
kubectl rollout resume deployment/web
kubectl rollout status deployment/web

# 5. Restart Pods without changing the spec
kubectl rollout restart deployment/web

# 6. Strategy tuning (no rollout by itself)
kubectl patch deployment web -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl patch deployment web -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null}}}'   # switch to Recreate
kubectl patch deployment web -p '{"spec":{"minReadySeconds":10,"progressDeadlineSeconds":120}}'

# 7. Verify what is running
kubectl get deploy web -o jsonpath='{.spec.template.spec.containers[*].image}{"\n"}'
kubectl get rs -l app=web -o wide                                  # which RS owns the Pods, with images
kubectl get pods -l app=web -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'
```

## Exam traps & tips

> **Exam tip:** Switching to `Recreate` while the old `rollingUpdate:` block is still there fails with ``spec.strategy.rollingUpdate: Forbidden: may not be specified when strategy `type` is 'Recreate'``. Delete the whole `rollingUpdate:` block in `kubectl edit`. In a patch, set `"rollingUpdate": null`.

> **Exam tip:** Revision numbers move on rollback: undo to revision 2 creates revision N+1, and "2" disappears from the history. If a task asks for "the revision that ran image X", read `kubectl rollout history deploy/web --revision=<n>` for each n. Don't guess from the order.

> **Exam tip:** `kubectl annotate` without `--overwrite` fails when the change-cause already exists. Always add `--overwrite`.

> **Exam tip:** `kubectl rollout undo` on a paused Deployment errors. Run `kubectl rollout resume` first.

> **Exam tip:** "Update the image and make sure the rollout succeeded" means run `kubectl rollout status deploy/<n>`, see `successfully rolled out`, and then check the image with jsonpath.

> **Exam tip:** A task like "roll out a new image to only some Pods first" can be done by `kubectl set image` followed immediately by `kubectl rollout pause`, then `resume` later. The proper canary pattern is in [03-deployment-strategies.md](03-deployment-strategies.md).

> **Exam tip:** With `revisionHistoryLimit: 0` there is nothing to undo to. If the task wants rollbacks, make sure it is > 0.

## Architect notes

- **Zero-downtime recipe:** `maxUnavailable: 0`, `maxSurge: 1` (or 25%), a real readiness probe, `minReadySeconds` of a few seconds, and graceful shutdown (`preStop` sleep of about 5 s plus a `terminationGracePeriodSeconds` longer than your drain time). Endpoint removal is asynchronous, so without the `preStop` delay some requests still hit terminating Pods.
- **Capacity for surge:** maxSurge needs spare quota and node room. Under a tight ResourceQuota, use `maxSurge: 0, maxUnavailable: 1`, or the rollout stalls with `ReplicaFailure/FailedCreate`.
- **Gate deployments in CI/CD** on `kubectl rollout status --timeout` and set `progressDeadlineSeconds` to match. Kubernetes reports failure but never acts on it.
- **Automatic rollback and analysis** (error rate, latency) are not built in. Use Argo Rollouts or Flagger, or a pipeline step.
- **GitOps caveat:** `kubectl rollout undo` changes the live spec. Argo CD or Flux will re-apply the broken version from git. Roll back by reverting the commit.
- **Config is not versioned by rollbacks.** Use immutable, hash-named ConfigMaps/Secrets (Kustomize generators, Helm checksum annotations). Then a rollback also restores the config the old Pods referenced, as long as the old object still exists.
- **Backward-compatible releases:** during a rolling update both versions serve traffic and share the database. Use expand/contract schema migrations and tolerant readers.
- **Long-lived connections** (WebSockets, gRPC) don't rebalance on their own after a rollout. Plan connection draining or max-connection-age settings.

## Docs to bookmark

- Updating a Deployment: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#updating-a-deployment
- Rolling back: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-to-a-previous-revision
- Pause and resume: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#pausing-and-resuming-a-deployment
- Failed Deployment / progress deadline: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#failed-deployment
- Strategy (maxSurge / maxUnavailable): https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy
- `kubectl rollout`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_rollout/
- `kubectl set image`: https://kubernetes.io/docs/reference/kubectl/generated/kubectl_set/kubectl_set_image/
- DaemonSet rolling update: https://kubernetes.io/docs/tasks/manage-daemon/update-daemon-set/
- StatefulSet update strategies: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- Tutorial, performing a rolling update: https://kubernetes.io/docs/tutorials/kubernetes-basics/update/update-intro/

## Quick self-check

1. 10 replicas, default strategy. What are the maximum total Pods and the minimum available Pods during an update?
2. 3 replicas with `maxSurge: 0` and `maxUnavailable: 25%`. What happens?
3. History shows revisions 1, 2, 3. You run `kubectl rollout undo --to-revision=1`. What does the history show afterwards?
4. In which order should you run `set image` and `annotate change-cause`, and why?
5. You need image, env and resource changes to produce a single new revision. How?
6. Which command proves a rollout failed, in a way a script can check?

<details><summary>Answers</summary>

1. surge = ceil(2.5) = 3 → max **13** Pods. unavailable = floor(2.5) = 2 → min **8** available.
2. floor(0.75) = 0 and surge = 0, so the controller uses maxUnavailable = 1: max 3 Pods, min 2 available. (Setting both explicitly to 0 would be rejected.)
3. 2, 3, 4. Revision 1's template became revision 4, and its change-cause comes with it.
4. Change first, then `annotate --overwrite`. The controller copies the Deployment's annotations to the current ReplicaSet, so annotating first would relabel the revision that is still current.
5. `kubectl rollout pause`, make all the changes, `kubectl rollout resume`.
6. `kubectl rollout status deploy/<n> --timeout=<t>` and check `$?` (non-zero on `ProgressDeadlineExceeded` or timeout). Or read the Progressing condition reason with jsonpath.

</details>
