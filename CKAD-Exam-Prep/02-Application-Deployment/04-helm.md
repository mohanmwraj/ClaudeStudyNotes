# Helm

**Why it matters.** The competency is "Use the Helm package manager to deploy **existing** packages". The exam tests the CLI, not chart authoring. Typical tasks:

- add or update a repo, then search it
- install a chart into a namespace with given values
- find a release, upgrade it with one more value, roll it back
- uninstall a broken or pending release
- render a chart to a file
- read a chart's default values

`helm.sh/docs` is in the allowed documentation, so you can look up flags there during the exam.

> **Practice-lab note:** when a question uses a chart, prefer a local chart (`helm create webapp`, or the sample chart in [yaml/helm/](yaml/helm/README.md)) so it works offline. To practise `helm repo add`, the stable public repo `https://helm.github.io/examples` (chart `hello-world`) is a good choice. Bitnami changed its free container image catalog in 2025 (most versioned images left `docker.io/bitnami`), so Bitnami chart images may fail to pull with `ErrImagePull`/`ImagePullBackOff`.

## Helm 3 vs Helm 4

Helm v3 commands are the baseline. **Helm 4 was released in November 2025** and keeps the core CLI: `repo add/update`, `search repo`, `install`, `upgrade --install`, `rollback`, `uninstall`, `list -A`, `history`, `status`, `get values|manifest`, `show values`, `template`, `pull --untar`. On the exam host, run `helm version` first and check `helm <cmd> --help` before using an uncommon flag. `helm.sh/docs` now shows Helm 4 by default; Helm 3 pages live under `helm.sh/docs/v3/`.

Differences observed with the actual binaries (helm v3.22.1 vs v4.3.1, tested 2026-10-17). They only matter if you use these flags:

| Item | Helm 3 (v3.22.1) | Helm 4 (v4.3.1) | Portable choice |
|---|---|---|---|
| `helm list` default filter | Only `deployed` + `failed`. `-a/--all` shows every status | Lists every status. `-a/--all` is **not a flag** (`unknown shorthand flag: 'a'`) | Status flags: `--pending`, `--failed`, `--uninstalled`, ... |
| `--atomic` | Supported | Accepted with a deprecation warning. `--help` lists `--rollback-on-failure` | Check `--help` |
| `--force` (install/upgrade) | Supported | Accepted with a deprecation warning. `--help` lists `--force-replace` | Rarely needed |
| Bare `--dry-run` | Client dry-run (install still contacts the cluster) | Warning: use `--dry-run=client` or `--dry-run=server` | `helm template` for offline rendering |
| `helm template --validate` | Supported | Deprecated in favour of `--dry-run=server` | |
| `helm status --show-resources` | Supported | Unknown flag | `helm get manifest` + `kubectl get` |
| `helm rollback --recreate-pods` | Supported (deprecated) | Unknown flag | `kubectl rollout restart` |

## Core concepts

| Term | Meaning |
|---|---|
| **Chart** | A package: a directory or `.tgz` with `Chart.yaml`, `values.yaml` and `templates/`. It has a chart `version` (SemVer) and an `appVersion` (the app inside) |
| **Release** | One installed instance of a chart in a namespace, with a unique name per namespace (`helm install web ./webapp`) |
| **Revision** | Every install, upgrade or rollback of a release creates revision N+1. Rollback = a new revision that copies an old one |
| **Repository** | An HTTP server with `index.yaml` + chart archives (`helm repo add`). Searched locally after `helm repo update` |
| **OCI registry** | Charts stored as OCI artifacts (`oci://registry/path/chart`). No `repo add`: pass the full reference with `--version` |
| **Values** | Configuration that is merged into the templates. Chart defaults (`values.yaml`) are overridden by `-f` files and `--set` |
| **Artifact Hub** | Public index of charts (`helm search hub`, needs internet) |
| **Hooks** | Templates annotated `helm.sh/hook` (e.g. pre-upgrade Jobs) run at lifecycle points. `--no-hooks` skips them |
| **Release record** | Stored in the release namespace as a Secret `sh.helm.release.v1.<release>.v<revision>` |

### Chart structure

```text
webapp/
├── Chart.yaml          # metadata: apiVersion v2, name, version (chart), appVersion (app), type, dependencies
├── values.yaml         # default values (lowest precedence)
├── values.schema.json  # optional JSON schema to validate values
├── charts/             # dependency (sub)charts, filled by `helm dependency update`
├── crds/               # optional CRDs, installed before templates (never upgraded or deleted by Helm)
├── templates/          # Go templates rendered into manifests
│   ├── _helpers.tpl    # named templates (define/include). Files starting with _ are not rendered
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── NOTES.txt       # printed after install/upgrade (`helm get notes`)
│   └── tests/          # `helm test` Pods
└── .helmignore         # files excluded from `helm package`
```

`helm create webapp` (v3 and v4) generates Chart.yaml, values.yaml, `charts/`, .helmignore, and in templates: deployment, service, serviceaccount, ingress, httproute, hpa, NOTES.txt, _helpers.tpl and tests/test-connection.yaml. Its default values deploy `nginx` with tag = appVersion.

```yaml
# Chart.yaml (Helm 3+ chart format)
apiVersion: v2
name: webapp
description: Example chart
type: application          # or "library" (only helpers, not installable)
version: 0.1.0             # CHART version -> "webapp-0.1.0" in the CHART column
appVersion: "1.27"         # APP version   -> "APP VERSION" column, often the default image tag
dependencies:              # optional subcharts
- name: redis
  version: "~1.2.0"
  repository: "https://example.com/charts"
  condition: redis.enabled
```

Template essentials (enough to read a chart):

| Item | Example |
|---|---|
| Built-in objects | `.Release.Name`, `.Release.Namespace`, `.Release.Revision`, `.Release.IsUpgrade`, `.Chart.Name`, `.Chart.Version`, `.Chart.AppVersion`, `.Values.x`, `.Capabilities.KubeVersion`, `.Template.BasePath` |
| Values with a default | `{{ .Values.image.tag \| default .Chart.AppVersion }}` |
| Named template | `{{- define "webapp.fullname" -}}...{{- end }}` / `{{ include "webapp.fullname" . }}` |
| Blocks | `{{- if .Values.ingress.enabled }}...{{- end }}`, `{{- with .Values.resources }}...{{- end }}`, `{{- range $k, $v := .Values.env }}` |
| YAML helpers | `{{- toYaml .Values.resources \| nindent 12 }}`, `quote`, `required "msg" .Values.x` |
| `{{-` / `-}}` | Trim whitespace to the left / right |

See the full sample chart: [yaml/helm/sample-chart/webapp/](yaml/helm/README.md) ([Chart.yaml](yaml/helm/sample-chart/webapp/Chart.yaml), [values.yaml](yaml/helm/sample-chart/webapp/values.yaml), [deployment template](yaml/helm/sample-chart/webapp/templates/deployment.yaml), [_helpers.tpl](yaml/helm/sample-chart/webapp/templates/_helpers.tpl)).

### Values precedence (lowest → highest)

```text
1. chart's values.yaml
2. parent chart's values.yaml        (only for subcharts: parent overrides child defaults)
3. -f / --values files, in order     (the right-most file wins)
4. --set, --set-string, --set-file, --set-json, --set-literal   (beat every -f file; the last --set of a key wins)
```

Example: chart default `replicaCount: 2`, `-f values-override.yaml` (3), `--set replicaCount=7` → **7**. With only `-f` → 3. Try it with [yaml/helm/values-override.yaml](yaml/helm/values-override.yaml).

| `--set` form | Resulting values |
|---|---|
| `--set replicaCount=3` | `replicaCount: 3` (integers become numbers, `true`/`false` booleans) |
| `--set a=1,b=2` | Two keys (comma separates) |
| `--set image.tag=1.27-alpine` | Nested `image: {tag: ...}` |
| `--set servers={a,b,c}` | List `[a, b, c]` |
| `--set servers[0].port=80` | List element by index |
| `--set name=value1\,value2` | Escaped comma → `"value1,value2"` |
| `--set nodeSelector."kubernetes\.io/os"=linux` | Key containing dots |
| `--set resources=null` | Removes the default key from the merge |
| `--set-string image.tag=1.20` | Always a string |
| `--set-file config=./app.conf` | File content as the value |
| `--set-json 'resources={"limits":{"memory":"128Mi"}}'` | JSON value |

> **Exam tip:** quote numeric-looking strings in values **files**: `tag: 1.20` is a YAML float and renders `nginx:1.2` (verified). `--set image.tag=1.20` keeps "1.20". `--set-string` is the explicit way.

## Key fields / syntax: the command set

Examples use the local chart `./webapp` (`helm create webapp`) or the repo `examples` (`https://helm.github.io/examples`).

### Repositories and search

```bash
helm repo add examples https://helm.github.io/examples     # add (name is local alias)
helm repo list                                              # NAME URL
helm repo update                                            # refresh all indexes (do it after add!)
helm repo update examples                                   # refresh one repo
helm repo remove examples
helm search repo hello                                      # search added repos (offline, local index)
helm search repo examples/hello-world --versions            # every chart version (CHART VERSION, APP VERSION)
helm search repo nginx --version '^1.2.0'                   # constraint
helm search hub nginx                                       # Artifact Hub (internet)
```

### Inspect a chart before installing

```bash
helm show chart  examples/hello-world                       # Chart.yaml
helm show values examples/hello-world > values.yaml         # defaults: copy, edit, use with -f
helm show readme examples/hello-world
helm show all    examples/hello-world
helm show values ./webapp                                   # works on local dirs and .tgz too
helm show values oci://registry.example.com/charts/webapp --version 0.1.0
```

### Install

```bash
helm install web ./webapp                                   # release "web" in the current namespace
helm install web ./webapp -n team-a --create-namespace     # into a (new) namespace
helm install web examples/hello-world --version 0.1.0      # pin the chart version
helm install web ./webapp -f values-prod.yaml --set replicaCount=3 --set image.tag=1.27-alpine
helm install ./webapp --generate-name                       # name like webapp-1729150000
helm install web ./webapp --dry-run=client --debug          # render + show computed values, no changes
helm install web ./webapp --wait --timeout 5m               # wait for readiness (default timeout 5m0s)
helm install web ./webapp --atomic --wait                   # Helm 3: uninstall on failure (Helm 4: see table above)
helm install web ./webapp-0.1.0.tgz                         # from a packaged chart
helm install web oci://registry.example.com/charts/webapp --version 0.1.0
```

A name already in use gives `cannot reuse a name that is still in use`. Use `helm upgrade`, or pick another name.

### Upgrade

```bash
helm upgrade web ./webapp --set replicaCount=3              # !! drops previously --set values (see below)
helm upgrade web ./webapp --reuse-values --set replicaCount=3      # keep old user values, add/override one
helm upgrade web ./webapp -f values-prod.yaml               # user values = exactly this file
helm upgrade web ./webapp --reset-values                    # back to chart defaults
helm upgrade web ./webapp --reset-then-reuse-values --set x=y      # new chart defaults + old user values + new
helm upgrade --install web ./webapp -n team-a --create-namespace   # idempotent: install if missing
helm upgrade web examples/hello-world --version 0.1.0 --reuse-values   # pin the chart version
helm upgrade web ./webapp --wait --timeout 3m --history-max 5      # keep at most 5 revisions
```

**How `helm upgrade` picks values** (verified in the Helm v3 and v4 source):

| You pass | Values used |
|---|---|
| No `-f`/`--set` at all | The previous release's user values are **reused** |
| Any `-f`/`--set`, no reuse flag | Chart defaults + **only the new** values. Earlier `--set` values are **lost** |
| `--reuse-values` + new values | Previous user values merged with the new ones (new wins). Uses the *old* chart's defaults |
| `--reset-then-reuse-values` | New chart's defaults + previous user values + new values |
| `--reset-values` | Chart defaults + new values only |

`helm upgrade` without `--version` takes the **latest** chart version from the repo, which can be an accidental chart upgrade. Pin `--version` to the current chart version (from the CHART column of `helm list`) when the task only asks for a value change.

### Roll back, uninstall

```bash
helm history web                                            # REVISION UPDATED STATUS CHART APP VERSION DESCRIPTION
helm rollback web 2                                         # new revision N+1 = copy of revision 2 ("Rollback to 2")
helm rollback web                                           # no revision (or 0) = the previous revision
helm rollback web 2 --wait --timeout 3m
helm uninstall web                                          # delete objects AND history (rollback impossible after)
helm uninstall web -n team-a --keep-history                 # keep history: status "uninstalled", rollback possible
helm uninstall web --wait                                   # wait for the objects to be deleted
```

### List, history, status, get

```bash
helm list                                                   # current namespace
helm list -n team-a
helm list -A                                                # all namespaces: NAME NAMESPACE REVISION UPDATED STATUS CHART APP VERSION
helm list -a                                                # Helm 3: every status (Helm 4 already lists every status; no -a flag)
helm list -A --failed                                       # only failed releases
helm list -A --pending                                      # pending-install / pending-upgrade / pending-rollback
helm list -A --superseded                                   # also: --deployed, --uninstalled, --uninstalling (flags are ORed)
helm list -A -o yaml                                        # fields: name namespace revision updated status chart app_version
helm list -A -f '^web'                                      # regex on release name
helm list -A -q                                             # names only

helm history web -n team-a [--max 5] [-o yaml]
helm status web -n team-a                                   # STATUS, REVISION, LAST DEPLOYED, NOTES
helm status web --revision 2

helm get values web                                         # USER-SUPPLIED values only
helm get values web --all                                   # computed: chart defaults + user values
helm get values web --revision 1 -o yaml > /tmp/rev1.yaml   # values of an old revision
helm get manifest web                                       # rendered YAML that Helm applied
helm get notes web
helm get hooks web
helm get metadata web                                       # chart, version, app version, revision, status
helm get all web
```

### Render, download, author

```bash
helm template web ./webapp -f values.yaml --set replicaCount=2 > /tmp/web.yaml   # render locally, no cluster needed
helm template web ./webapp --show-only templates/deployment.yaml                 # one template
helm template web ./webapp -n team-a --output-dir /tmp/rendered                  # one file per template
helm pull examples/hello-world                                    # downloads hello-world-0.1.0.tgz to .
helm pull examples/hello-world --version 0.1.0 --untar --untardir /tmp/charts    # -> /tmp/charts/hello-world/
helm pull oci://registry.example.com/charts/webapp --version 0.1.0 -d /tmp
helm create webapp                                                # scaffold a chart
helm lint ./webapp [-f values.yaml]                               # static checks
helm package ./webapp [--version 0.2.0] [--app-version 1.28] [-d dist/]  # -> webapp-0.2.0.tgz
helm dependency update ./webapp                                   # fetch Chart.yaml dependencies into charts/
helm dependency build ./webapp                                    # rebuild charts/ from Chart.lock
helm dependency list ./webapp
helm registry login registry.example.com -u user                  # OCI registries
helm push webapp-0.2.0.tgz oci://registry.example.com/charts
helm env                                                          # HELM_* paths (cache, config, data)
```

## Release storage (Secrets)

```text
$ kubectl get secrets -n team-a -l owner=helm
NAME                        TYPE                 DATA   AGE
sh.helm.release.v1.web.v1   helm.sh/release.v1   1      10m
sh.helm.release.v1.web.v2   helm.sh/release.v1   1      2m
```

- One Secret per revision, in the **release namespace**: `sh.helm.release.v1.<release>.v<revision>`, type `helm.sh/release.v1`.
- Labels: `owner=helm`, `name=<release>`, `status=<deployed|superseded|failed|pending-...>`, `version=<revision>`. Filter with `kubectl get secret -n team-a -l owner=helm,name=web,status=deployed`.
- `data.release` is base64 (Secret encoding) of base64 of gzipped JSON. To decode: `kubectl get secret sh.helm.release.v1.web.v1 -n team-a -o jsonpath='{.data.release}' | base64 -d | base64 -d | gunzip`.
- `--history-max` (default 10 for upgrades) caps how many revisions are kept.
- `HELM_DRIVER=secret|configmap|sql` selects the backend (default `secret`).
- Deleting the namespace deletes the release records too. Helm then no longer knows the release.

## Release statuses

| Status | Meaning | Typical next step |
|---|---|---|
| `deployed` | Current live revision (only one per release) | |
| `superseded` | Older revision, replaced | Rollback target |
| `failed` | Install/upgrade/rollback errored or `--wait` timed out | Fix values and `upgrade`, or `rollback` |
| `pending-install` / `pending-upgrade` / `pending-rollback` | Operation in progress, **or the client died mid-operation** | Wait, or unstick (below) |
| `uninstalling` | Uninstall running | |
| `uninstalled` | Uninstalled with `--keep-history` | `helm rollback` restores it |
| `unknown` | State couldn't be determined | Inspect history |

## Fixing stuck and failed releases

The symptom: `Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress`. The last revision is `pending-*`, usually because the client was killed or timed out during `--wait`.

```bash
helm history web -n team-a                       # find the pending revision and the last 'deployed'/'superseded' one
# pending-upgrade or pending-rollback: roll back to the last good revision (rollback is allowed while pending)
helm rollback web 3 -n team-a
# pending-install on revision 1 (nothing to roll back to): remove and reinstall
helm uninstall web -n team-a                     # add --no-hooks if a hook hangs
helm install web ./webapp -n team-a
# last resort: delete only the stuck revision's record, then upgrade again
kubectl delete secret sh.helm.release.v1.web.v4 -n team-a
```

| Situation | Fix |
|---|---|
| `helm list` shows `failed` after an upgrade | `helm rollback web <last good>` or `helm upgrade` with corrected values |
| First install `failed` | `helm uninstall web` + install again, `helm upgrade --install web ...` (current Helm can upgrade a failed release), or `helm install --replace` (unsafe in production) |
| Release "missing" in `helm list` | It's in another namespace (`helm list -A`), or (Helm 3) it's pending/uninstalled and needs `-a` or a status flag |
| Objects exist but no release | Someone used `kubectl apply`, or the namespace's Secrets were deleted. Install fails with an ownership conflict. Helm v3.17+ and v4 can adopt the objects with `--take-ownership`, otherwise delete them and reinstall |

## Exam-style workflows

```bash
# A) Find the release that runs chart "hello-world" / app version 1.16.0, in any namespace
helm list -A | grep -E 'hello-world|1\.16\.0'          # CHART=hello-world-0.1.0, APP VERSION=1.16.0
helm list -A -o yaml | grep -A2 'chart: hello-world'   # keys are alphabetical: chart, then name, namespace

# B) Upgrade it with one more value, keep everything else, same chart version
helm get values hello -n apps                          # what was set before
helm upgrade hello examples/hello-world -n apps --version 0.1.0 --reuse-values --set replicaCount=3
helm get values hello -n apps                          # old values + replicaCount: 3
kubectl get deploy -n apps                             # 3/3

# C) Roll back to a given revision and prove it
helm history hello -n apps
helm rollback hello 1 -n apps
helm history hello -n apps | tail -1                   # "... deployed ... Rollback to 1"

# D) Delete broken releases (failed or pending)
helm list -A --failed; helm list -A --pending
helm uninstall broken-app -n apps

# E) Install a pinned version into a new namespace with a values file and a --set
helm install web ./webapp -n team-a --create-namespace -f values.yaml --set service.type=NodePort

# F) Write rendered manifests or default values to files
helm template web ./webapp -f values.yaml > /opt/course/helm/manifest.yaml
helm show values examples/hello-world > /opt/course/helm/default-values.yaml

# G) Download and unpack a chart version into a directory, then install from it
helm pull examples/hello-world --version 0.1.0 --untar --untardir /opt/charts
helm install hello2 /opt/charts/hello-world -n apps
```

## Exam traps & tips

> **Exam tip:** `helm install`, `upgrade`, `list` and `uninstall` act on the **current kubectl namespace** unless you pass `-n`. "Release not found" usually means the wrong namespace. Use `helm list -A` to locate it.

> **Exam tip:** After `helm repo add`, run `helm repo update`. Otherwise search and install may use a stale or empty index.

> **Exam tip:** `helm upgrade ... --set x=y` without `--reuse-values` drops earlier `--set` values. If the task says "keep the existing configuration", add `--reuse-values` and verify with `helm get values`.

> **Exam tip:** The argument order is `helm install <release> <chart>`. `helm install examples/hello-world hello` fails or creates a weird name.

> **Exam tip:** `helm rollback <release> <revision>` takes the revision **number** from `helm history`, not a chart version.

> **Exam tip:** `helm uninstall` removes history unless you pass `--keep-history`. Don't uninstall when the task says "roll back".

> **Exam tip:** Need YAML without touching the cluster? Use `helm template`. `--dry-run` still talks to the cluster (and in Helm 3, client dry-run of install needs one).

## Architect notes

- **Pin everything**: chart `--version`, image tags, and ideally digests. Commit values files to git and deploy with `helm upgrade --install` from CI or GitOps (Argo CD and Flux render Helm charts themselves).
- **Chart version vs appVersion**: bump the chart version on any template change. The appVersion is informational, often the default image tag.
- **Rollout of config changes**: Helm re-renders but Kubernetes rolls Pods only if the Pod template changes. Use the `checksum/config` annotation pattern (in the [sample deployment template](yaml/helm/sample-chart/webapp/templates/deployment.yaml)) so ConfigMap/Secret changes trigger a rollout.
- **Failure handling**: `--wait` plus a timeout, and rollback on failure (`--atomic` in Helm 3; check the Helm 4 name). Never leave releases `pending-*`. Pipelines should be idempotent (`upgrade --install`).
- **Secrets in values**: values end up in the release Secret, readable by anyone who can read Secrets in that namespace. Use external secret managers (External Secrets, Sealed Secrets, CSI) for real credentials.
- **CRDs**: Helm installs `crds/` once and never upgrades or deletes them. Manage CRD lifecycles separately in production.
- **OCI registries** are the modern distribution channel (one registry for images and charts, signing with cosign). Classic `index.yaml` repos still work.
- **Helm vs Kustomize**: Helm when you need parameterised packages, versioning, release history and rollback. Kustomize for patching plain YAML per environment. Many teams combine them (Kustomize `helmCharts`, or a post-renderer). See [05-kustomize.md](05-kustomize.md).

## Docs to bookmark

- Quickstart: https://helm.sh/docs/intro/quickstart/
- Using Helm (install, upgrade, values, --set format): https://helm.sh/docs/intro/using_helm/
- Cheat sheet: https://helm.sh/docs/intro/cheatsheet/
- Commands: https://helm.sh/docs/helm/helm_install/ · https://helm.sh/docs/helm/helm_upgrade/ · https://helm.sh/docs/helm/helm_rollback/ · https://helm.sh/docs/helm/helm_uninstall/ · https://helm.sh/docs/helm/helm_list/ · https://helm.sh/docs/helm/helm_history/ · https://helm.sh/docs/helm/helm_get_values/ · https://helm.sh/docs/helm/helm_show_values/ · https://helm.sh/docs/helm/helm_template/ · https://helm.sh/docs/helm/helm_pull/ · https://helm.sh/docs/helm/helm_search_repo/ · https://helm.sh/docs/helm/helm_repo_add/
- Values files and precedence: https://helm.sh/docs/chart_template_guide/values_files/
- Charts (structure, Chart.yaml): https://helm.sh/docs/topics/charts/
- Built-in objects: https://helm.sh/docs/chart_template_guide/builtin_objects/
- Tips (checksum annotations): https://helm.sh/docs/howto/charts_tips_and_tricks/
- OCI registries: https://helm.sh/docs/topics/registries/
- Helm 3 docs: https://helm.sh/docs/v3/

## Quick self-check

1. A release was installed with `--set replicaCount=3 --set image.tag=1.27-alpine`. You run `helm upgrade web ./webapp --set service.type=NodePort`. Which values are in effect?
2. Where does Helm store the release history, and how do you list it with kubectl?
3. `helm upgrade` fails with "another operation (install/upgrade/rollback) is in progress". What do you do?
4. How do you see only the values a user supplied, and how do you see the full computed values?
5. History has revisions 1–4. You run `helm rollback web 2`. What is the new revision number and its description?
6. Which command renders a chart to stdout without contacting the cluster?

<details><summary>Answers</summary>

1. Only `service.type=NodePort` on top of the chart defaults. replicaCount and image.tag fall back to their defaults because new values were given without `--reuse-values`.
2. In Secrets named `sh.helm.release.v1.<release>.v<rev>` (type `helm.sh/release.v1`) in the release namespace: `kubectl get secret -n <ns> -l owner=helm,name=web`.
3. `helm history` to find the pending revision. Then `helm rollback <release> <last good revision>`. If it's a pending first install, `helm uninstall` and reinstall. Last resort: delete the pending revision's Secret.
4. `helm get values <rel>` (user-supplied) and `helm get values <rel> --all` (computed).
5. Revision 5, description `Rollback to 2`.
6. `helm template <name> <chart> [-f ...] [--set ...]`.

</details>
