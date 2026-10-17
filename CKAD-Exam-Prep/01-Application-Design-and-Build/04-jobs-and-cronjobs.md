# Jobs and CronJobs

**Why it matters:** Jobs and CronJobs are among the most frequently reported CKAD task types. Typical tasks: "create a Job that runs N times with M in parallel, retries at most K times, is killed after T seconds and cleaned up automatically", or "create a CronJob that runs every X minutes, never overlaps, keeps N successful Jobs", followed by "trigger it manually and save the logs". You need the fields, their defaults, the schedule syntax, and the Never vs OnFailure behaviour.

---

## Core concepts

### Job: run to completion

A Job creates pods until the required number of them **succeed** (exit 0). Then it is `Complete`. If too many fail, or a deadline passes, it is `Failed`. Deleting a Job deletes its pods; suspending it deletes its active pods until it is resumed.

### All Job spec fields

| Field | Default | Meaning |
|---|---|---|
| `completions` | 1 (if `parallelism` is also unset) | number of **successful** pods required |
| `parallelism` | 1 | max pods running at the same time (`0` = paused) |
| `backoffLimit` | **6** (MaxInt32 when `backoffLimitPerIndex` is set) | retries before the Job is Failed (`BackoffLimitExceeded`) |
| `activeDeadlineSeconds` | none | wall-clock limit for the **whole Job**, retries included. **Takes precedence over backoffLimit** (`DeadlineExceeded`) |
| `ttlSecondsAfterFinished` | none (kept forever) | delete the Job and its pods N s after it finishes (Complete or Failed). `0` = right away. GA v1.23 |
| `completionMode` | `NonIndexed` | `Indexed`: each pod gets an index 0..completions-1 (GA v1.24) |
| `suspend` | false | `true`: no new pods, and active pods are deleted. Resume with `false`. GA v1.24 |
| `podFailurePolicy` | none | rules on exit codes or pod conditions: `FailJob`, `Ignore`, `Count`, `FailIndex`. Requires `restartPolicy: Never`. GA v1.31 |
| `backoffLimitPerIndex` | none | retries per index (Indexed only). GA v1.33 |
| `maxFailedIndexes` | none | with `backoffLimitPerIndex`: fail the Job early once more indexes than this have failed |
| `successPolicy` | none | Indexed only: declare success when specific indexes or a count succeed. GA v1.33 |
| `podReplacementPolicy` | `TerminatingOrFailed` | `Failed` = create a replacement only once the old pod is fully terminated (the only value allowed with `podFailurePolicy`). GA v1.34 |
| `manualSelector` / `selector` | auto-generated | **do not set**: the Job controller generates a unique selector |
| `template` | required | pod template; `restartPolicy` **must** be `Never` or `OnFailure` |

### Parallelism patterns

| Pattern | `completions` | `parallelism` | Done when |
|---|---|---|---|
| Single pod (default) | unset (1) | unset (1) | 1 pod succeeds |
| Fixed completion count | N | M (default 1) | N pods succeeded |
| Indexed (static sharding) | N + `completionMode: Indexed` | M | every index 0..N-1 succeeded once |
| Work queue | **unset** | M | any pod succeeded and all pods have terminated (the pods coordinate through the queue) |

### `restartPolicy`: Never vs OnFailure

| | `Never` | `OnFailure` |
|---|---|---|
| On container failure | pod goes `Failed`; the **Job controller creates a new pod** | kubelet restarts the container **in the same pod** |
| What you see | several pods (`job-xxxxx`), the failed ones stay with STATUS `Error` | one pod, RESTARTS count climbing |
| Logs of failed attempts | kept in each failed pod: `kubectl logs <old-pod>` | only the last one: `kubectl logs <pod> --previous` |
| `backoffLimit` counts | failed pods | container restarts in pods that are Pending or Running |
| `podFailurePolicy` | supported | not allowed |
| When the Job fails | failed pods remain for inspection | running pods are terminated, so logs are easily lost |

Retries use exponential back-off (10 s, 20 s, 40 s, ... capped). Use `Never` when you need to debug failures.

### Pods created by a Job

- Labels: `batch.kubernetes.io/job-name=<job>` and the legacy `job-name=<job>`, plus `batch.kubernetes.io/controller-uid` and `controller-uid`. `kubectl get pods -l job-name=<job>` works.
- Pod names: `<job>-<random>`; for Indexed Jobs `<job>-<index>-<random>`.
- Indexed Jobs: env `JOB_COMPLETION_INDEX`, annotation and label `batch.kubernetes.io/job-completion-index`, hostname `<job>-<index>`.
- Job conditions: `Complete`, `Failed`, `Suspended`; also `FailureTarget` and `SuccessCriteriaMet` while finishing. Typical failure reasons: `BackoffLimitExceeded`, `DeadlineExceeded`, `PodFailurePolicy`, `MaxFailedIndexesExceeded`, `FailedIndexes`.

### What you can change on an existing Job

`parallelism`, `suspend`, `activeDeadlineSeconds`, `ttlSecondsAfterFinished` (and `completions` together with `parallelism` for Indexed Jobs). The **pod template is immutable**, so delete and recreate the Job (`kubectl replace --force -f job.yaml`).

### CronJob: Jobs on a schedule

| Field | Default | Meaning |
|---|---|---|
| `schedule` | required | 5-field cron expression or macro |
| `timeZone` | kube-controller-manager's local zone | IANA name, e.g. `Etc/UTC`, `Europe/Berlin`. GA v1.27. `CRON_TZ=`/`TZ=` inside `schedule` is **rejected** |
| `concurrencyPolicy` | `Allow` | `Allow` = runs may overlap · `Forbid` = skip a new run while the previous is still running · `Replace` = kill the running Job, start the new one |
| `startingDeadlineSeconds` | none (no deadline) | a run that could not start on time (controller down, `Forbid` overlap, suspended) may still start up to N s after its scheduled time. Past that, this run is skipped and counted as failed; future runs are unaffected. Values under 10 s may never run (the controller checks every 10 s) |
| `successfulJobsHistoryLimit` | **3** | finished successful Jobs to keep (`0` = none) |
| `failedJobsHistoryLimit` | **1** | failed Jobs to keep |
| `suspend` | false | `true`: create no new Jobs (running Jobs continue). Runs missed while suspended count as missed; without a starting deadline they start immediately on resume |
| `jobTemplate` | required | `metadata` + `spec` of a Job (no apiVersion/kind) |

- CronJob **name ≤ 52 characters**: the controller appends an 11-character suffix to the name of each Job (`<cronjob>-<scheduled time in minutes>`).
- More than **100 missed schedules** (e.g. controller downtime) → no Job is started and an error is logged. A `startingDeadlineSeconds` limits how far back the controller counts.
- Edits affect only **future** Jobs. Running Jobs are not updated.
- Scheduling is approximate: a run can occasionally happen twice or not at all, so make jobs **idempotent**.
- Since v1.32, created Jobs carry the annotation `batch.kubernetes.io/cronjob-scheduled-timestamp`.

### Schedule syntax

```text
┌───────────── minute        (0-59)
│ ┌─────────── hour          (0-23)
│ │ ┌───────── day of month  (1-31)
│ │ │ ┌─────── month         (1-12)
│ │ │ │ ┌───── day of week   (0-6, Sunday = 0; or sun, mon, tue, wed, thu, fri, sat)
│ │ │ │ │
* * * * *
```

Operators: `*` any · `,` list (`1,15`) · `-` range (`9-17`) · `/` step (`*/15`, `0-30/10`) · `?` same as `*`.

| Macro | Equivalent |
|---|---|
| `@yearly` / `@annually` | `0 0 1 1 *` |
| `@monthly` | `0 0 1 * *` |
| `@weekly` | `0 0 * * 0` |
| `@daily` / `@midnight` | `0 0 * * *` |
| `@hourly` | `0 * * * *` |

| Requirement | Schedule |
|---|---|
| every minute | `* * * * *` |
| every 5 minutes | `*/5 * * * *` |
| every 15 minutes, 09:00–17:59, Monday–Friday | `*/15 9-17 * * 1-5` |
| at minute 30 of every hour | `30 * * * *` |
| every 2 hours, on the hour | `0 */2 * * *` |
| twice a day, 06:00 and 18:00 | `0 6,18 * * *` |
| daily at 02:30 | `30 2 * * *` |
| weekdays at 08:00 | `0 8 * * 1-5` |
| Sundays at 03:00 | `0 3 * * 0` |
| first day of every month at midnight | `0 0 1 * *` (`@monthly`) |
| every 10 minutes between 01:00 and 03:59 | `*/10 1-3 * * *` |
| quarter past every hour on weekends | `15 * * * 6,0` |

When **both** day-of-month and day-of-week are restricted, standard cron semantics apply: the job runs when **either** matches. Avoid combining them unless that is what you want.

---

## Key fields / syntax

| File | Shows |
|---|---|
| [yaml/job.yaml](yaml/job.yaml) | completions, parallelism, backoffLimit, activeDeadlineSeconds, ttlSecondsAfterFinished |
| [yaml/job-parallel-indexed.yaml](yaml/job-parallel-indexed.yaml) | Indexed Job using `JOB_COMPLETION_INDEX` |
| [yaml/job-pod-failure-policy.yaml](yaml/job-pod-failure-policy.yaml) | podFailurePolicy (FailJob/Ignore), backoffLimitPerIndex + maxFailedIndexes |
| [yaml/job-with-native-sidecar.yaml](yaml/job-with-native-sidecar.yaml) | a Job whose native sidecar does not block completion |
| [yaml/cronjob.yaml](yaml/cronjob.yaml) | schedule, timeZone, concurrencyPolicy, startingDeadlineSeconds, history limits, suspend |

Job with the usual exam fields:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: batch-job
spec:
  completions: 6
  parallelism: 2
  backoffLimit: 3
  activeDeadlineSeconds: 120
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: busybox:1.36
        command: ["sh", "-c", "echo working; sleep 5"]
```

CronJob with the usual exam fields:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cleaner
spec:
  schedule: "*/15 * * * *"
  timeZone: "Etc/UTC"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 60
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 4
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 40
      template:
        spec:
          restartPolicy: Never
          containers:
          - name: cleaner
            image: busybox:1.36
            command: ["sh", "-c", "echo cleaning; date"]
```

Pod failure policy (fail fast on exit code 42, ignore disruptions):

```yaml
spec:
  podFailurePolicy:
    rules:
    - action: FailJob
      onExitCodes:
        containerName: main
        operator: In
        values: [42]
    - action: Ignore
      onPodConditions:
      - type: DisruptionTarget
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: main
        image: busybox:1.36
        command: ["sh", "-c", "exit 42"]
```

---

## Imperative commands

```bash
# Generate (the words after -- become the container COMMAND)
kubectl create job batch-job --image=busybox:1.36 --dry-run=client -o yaml -- sh -c 'echo hi; sleep 5' > job.yaml
kubectl create cronjob cleaner --image=busybox:1.36 --schedule="*/15 * * * *" --dry-run=client -o yaml -- sh -c 'date' > cj.yaml
kubectl create cronjob cleaner --image=busybox:1.36 --schedule="*/15 * * * *" --restart=Never --dry-run=client -o yaml -- date > cj.yaml
#   kubectl create job writes restartPolicy Never; kubectl create cronjob defaults to OnFailure (override with --restart)
vi job.yaml && kubectl apply -f job.yaml                  # add completions/parallelism/backoffLimit/... (no flags exist)

# Run a CronJob now (uses its jobTemplate)
kubectl create job cleaner-manual-1 --from=cronjob/cleaner

# Watch and wait
kubectl get jobs -w                                       # COMPLETIONS e.g. 3/6, DURATION, AGE
kubectl get pods -l job-name=batch-job                    # the Job's pods
kubectl wait --for=condition=complete job/batch-job --timeout=120s
kubectl wait --for=condition=failed job/batch-job --timeout=120s

# Logs
kubectl logs job/batch-job                                # logs of ONE pod of the Job
kubectl logs -l job-name=batch-job --prefix --tail=-1     # all pods; with -l the default is the last 10 lines
kubectl logs job/batch-job > /opt/course/n/logs.txt       # save as asked

# Status details
kubectl describe job batch-job                            # Pods Statuses, events (BackoffLimitExceeded...)
kubectl get job batch-job -o jsonpath='{.status.succeeded}/{.spec.completions}{"\n"}'
kubectl get job batch-job -o jsonpath='{.status.conditions[*].type}{" "}{.status.conditions[*].reason}{"\n"}'
kubectl get cronjob cleaner                               # SCHEDULE, TIMEZONE, SUSPEND, ACTIVE, LAST SCHEDULE
kubectl get cronjob cleaner -o jsonpath='{.status.lastScheduleTime}{" "}{.status.lastSuccessfulTime}{"\n"}'

# Suspend / resume
kubectl patch cronjob cleaner -p '{"spec":{"suspend":true}}'
kubectl patch cronjob cleaner -p '{"spec":{"suspend":false}}'
kubectl patch job batch-job -p '{"spec":{"suspend":true}}'

# Change the pod template of a Job (immutable)
kubectl get job batch-job -o yaml > job.yaml   # or better: edit your original manifest
kubectl replace --force -f job.yaml

# Cleanup
kubectl delete job batch-job                              # deletes its pods too
kubectl delete cronjob cleaner                            # deletes its Jobs and pods too
kubectl delete jobs --field-selector status.successful=1  # finished-successful Jobs in the namespace
kubectl delete pods --field-selector=status.phase==Succeeded
```

---

## Exam traps & tips

> **Exam tip:** `kubectl create job`/`cronjob` have no flags for completions, parallelism, backoffLimit, deadlines or history limits. Generate with `--dry-run=client -o yaml`, add the fields in vi, then apply. Put Job fields under `spec` (Job) or `spec.jobTemplate.spec` (CronJob). The pod's `restartPolicy` goes one level deeper, under `template.spec`.

> **Exam tip:** "Trigger the CronJob now" or "test the CronJob" means `kubectl create job <name> --from=cronjob/<cronjob>`. Then `kubectl logs job/<name>`.

> **Exam tip:** With `kubectl logs -l ...` the default is **10 lines per pod** and at most 5 concurrent pods (`--max-log-requests`). Use `--tail=-1` for everything, or loop over the pods.

> **Exam tip:** `activeDeadlineSeconds` exists at **two** levels. Job `spec.activeDeadlineSeconds` limits the whole Job. Pod `spec.template.spec.activeDeadlineSeconds` limits each pod. Put it where the task says ("the Job must be terminated after 40 s" → Job spec).

- `restartPolicy: OnFailure` + a failing Job: when the backoff limit is hit, the pod is terminated and the logs are gone. Prefer `Never` when the task asks you to investigate failures.
- Recreating a Job from `kubectl get job -o yaml` output fails with `` `selector` not auto-generated `` unless you remove `spec.selector` and the `controller-uid` labels from `spec.template.metadata.labels`. Keep your original manifest instead.
- `ttlSecondsAfterFinished` deletes the Job: if the task also wants you to read its logs afterwards, get them before the TTL fires.
- Quote the schedule: `schedule: "*/5 * * * *"`. An unquoted value starting with `*` is a YAML alias error.
- `concurrencyPolicy: Forbid` + `startingDeadlineSeconds` → a run skipped because the previous one was still running counts as missed.
- A classic sidecar in `containers` keeps a Job pod Running forever, so the Job never completes. Make it a native sidecar (see [06-multi-container-pods.md](06-multi-container-pods.md)).
- A CronJob name longer than 52 characters is rejected.

---

## Architect notes

- **Idempotency is mandatory.** Jobs retry, CronJobs may double-fire or skip, and nodes disappear. Design for at-least-once: dedupe keys, upserts, checkpoints.
- **Bound everything:** `backoffLimit`, `activeDeadlineSeconds`, resource requests and limits, and `ttlSecondsAfterFinished` or history limits. Thousands of finished Jobs and pods bloat etcd and slow the API.
- **Use podFailurePolicy** to fail fast on non-retryable exit codes and to ignore infrastructure disruptions (`DisruptionTarget`). This saves compute and gives clearer failure reasons.
- **Set `timeZone` explicitly** on every CronJob (usually `Etc/UTC`). Never depend on the controller-manager's local zone, and remember DST shifts for local zones.
- **Use `concurrencyPolicy: Forbid`** for jobs that touch shared state (backups, migrations), together with a `startingDeadlineSeconds` that makes stale runs skip instead of piling up.
- **Indexed Jobs + `backoffLimitPerIndex`** suit embarrassingly parallel batch work (sharded ETL, rendering, ML preprocessing). Large or multi-tenant batch platforms add a queue or quota layer (e.g. Kueue).
- **Observability:** export Job success and failure metrics (kube-state-metrics `kube_job_*`, `kube_cronjob_*`) and alert on "last successful run older than X". A silent CronJob failure is a classic production incident.
- **Native sidecars for Jobs** (service-mesh proxies, log shippers) remove old hacks such as sharing a "done" file or `curl -X POST localhost:15020/quitquitquit`.

---

## Docs to bookmark

- Jobs (all fields, patterns, failure policy): <https://kubernetes.io/docs/concepts/workloads/controllers/job/>
- CronJob (schedule syntax, time zones, limits): <https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/>
- Running automated tasks with a CronJob: <https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/>
- Indexed Job for parallel processing: <https://kubernetes.io/docs/tasks/job/indexed-parallel-processing-static/>
- Handling retriable and non-retriable pod failures (podFailurePolicy): <https://kubernetes.io/docs/tasks/job/pod-failure-policy/>
- TTL controller for finished resources: <https://kubernetes.io/docs/concepts/workloads/controllers/ttlafterfinished/>
- `kubectl create job` / `cronjob`: <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_job/>, <https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_cronjob/>

---

## Quick self-check

1. Defaults of `completions`, `parallelism` and `backoffLimit`? Which wins: `activeDeadlineSeconds` or `backoffLimit`?
2. Write the schedule for "every 20 minutes between 08:00 and 18:59 on weekdays".
3. A Job with `restartPolicy: OnFailure` fails and you cannot find logs. Why, and what would you change?
4. How do you run a CronJob's job template right now under the name `manual-1`?
5. What do `concurrencyPolicy: Replace` and `Forbid` do when the previous run is still active?
6. Which field gives each pod of a Job a unique number, and how does the container read it?

<details><summary>Answers</summary>

1. `completions` 1, `parallelism` 1, `backoffLimit` 6. `activeDeadlineSeconds` takes precedence: once it is reached no more pods start and the Job fails with `DeadlineExceeded`, even if retries remain.
2. `*/20 8-18 * * 1-5`
3. With `OnFailure` the container restarts inside the same pod, and when the backoff limit is reached the pod is terminated, so its logs disappear. Use `restartPolicy: Never` (failed pods stay with their logs) or ship logs elsewhere.
4. `kubectl create job manual-1 --from=cronjob/<name>`
5. `Replace` deletes the running Job and starts the new one. `Forbid` skips the new run. (`Allow`, the default, runs both.)
6. `completionMode: Indexed`. The index is in env `JOB_COMPLETION_INDEX` (also in the annotation and label `batch.kubernetes.io/job-completion-index`, and the hostname `<job>-<index>`).

</details>
