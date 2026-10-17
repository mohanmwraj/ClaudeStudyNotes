# YAML Essentials for Kubernetes

**Why it matters / what the exam expects:** every manifest you write or fix is YAML, and most failed `kubectl apply` attempts in the exam are indentation or type mistakes, not Kubernetes mistakes. Nobody tests YAML theory, but you must spot a misaligned key in seconds and read kubectl's error messages. Some tasks hand you a broken manifest on purpose.

> Conventions: `alias k=kubectl`. Editor settings for YAML: [08-linux-vim-bash-tmux-for-the-exam.md](08-linux-vim-bash-tmux-for-the-exam.md) and [yaml/vimrc.txt](yaml/vimrc.txt).

---

## Core concepts

### Three building blocks

| YAML | Example | JSON equivalent |
|---|---|---|
| Scalar | `image: nginx:1.27` · `replicas: 3` · `hostNetwork: true` | `"nginx:1.27"`, `3`, `true` |
| Mapping (map, dict) | `labels:` followed by indented `key: value` lines | `{"app": "web"}` |
| Sequence (list) | lines starting with `- ` | `["a", "b"]` |
| Flow style (inline JSON-like) | `command: ["sh", "-c", "sleep 3600"]` · `podSelector: {}` | identical |

kubectl converts YAML to JSON before sending it; the API's Go types then decide whether a field must be a string, an integer, a list or a map. `k explain` shows the expected type (`<string>`, `<integer>`, `<[]Object>`, `<map[string]string>`, `<IntOrString>`).

### Indentation rules

| Rule | Detail |
|---|---|
| Spaces only | a TAB character is a syntax error |
| Same level = same column | sibling keys must start in exactly the same column |
| Children deeper than parent | any consistent amount; Kubernetes convention is 2 spaces |
| `- ` items | may sit at the parent key's column (style of `kubectl -o yaml`) or 2 spaces deeper (style of many docs pages) - both valid, but be consistent within one list |
| `: ` and `- ` | the space after `:` and after `-` is mandatory |

```yaml
containers:          # compact style (kubectl -o yaml)
- name: web
  image: nginx:1.27
```

```yaml
containers:          # indented style (many docs pages) - same data
  - name: web
    image: nginx:1.27
```

### The `- name:` list-of-maps pattern

Most Kubernetes lists are lists of maps: `containers`, `initContainers`, `env`, `ports`, `volumes`, `volumeMounts`, `tolerations`, Ingress `rules`/`paths`, NetworkPolicy `ingress`/`from`. Each item starts with `- `, and every key of that item is aligned with the first key after the dash:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
spec:
  containers:
  - name: web                 # item 1 of containers starts here
    image: nginx:1.27         # aligned with "name" -> same item
    ports:
    - containerPort: 80       # list inside the item
    env:
    - name: MODE              # env item 1
      value: "prod"
    - name: PORT              # env item 2
      value: "8080"           # quoted: env values are strings
    volumeMounts:
    - name: cache
      mountPath: /cache
  - name: sidecar             # item 2 of containers
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
  volumes:                    # back at the level of "containers" -> pod spec field
  - name: cache
    emptyDir: {}              # empty map = "use defaults"
```

### Multi-line strings

| Indicator | Line breaks | Trailing newline | Typical use |
|---|---|---|---|
| `\|` literal | kept | exactly one ("clip") | scripts, config files in ConfigMaps |
| `\|-` | kept | none ("strip") | values where a trailing newline would hurt |
| `\|+` | kept | all kept ("keep") | rare |
| `>` folded | single newlines become spaces (blank line = newline) | one | long prose |
| `>-` | folded | none | long one-line command strings |

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: multiline-demo
data:
  nginx.conf: |
    server {
      listen 8080;
      location / { return 200 'ok'; }
    }
  motd: >-
    This long sentence is folded
    into one line without a trailing newline.
---
apiVersion: v1
kind: Pod
metadata:
  name: script-pod
spec:
  restartPolicy: Never
  containers:
  - name: sh
    image: busybox:1.36
    command: ["sh", "-c"]
    args:
    - |
      echo "starting"
      for i in 1 2 3; do echo "tick $i"; sleep 1; done
      echo "done"
```

The block content must be indented deeper than its key; inside a block scalar `#`, `:` and quotes are ordinary text.

### Quoting traps (implicit typing)

Kubernetes' YAML parser follows YAML 1.1 typing rules for unquoted scalars:

| Unquoted value | Becomes | Problem | Write instead |
|---|---|---|---|
| `true` `false` `yes` `no` `on` `off` `y` `n` (also `True`, `YES`, `Off`, ...) | boolean | labels, annotations, env values, ConfigMap data, nodeSelector values must be strings → error | `"true"`, `"yes"`, `"on"` |
| `8080`, `1` | integer | env `value`, labels, annotations, ConfigMap data, `args` items must be strings → error | `"8080"` |
| `1.10` | float `1.1` | the version label silently changes - or errors as a number | `"1.10"` |
| `0123` | octal → `83` | leading zero means octal | `"0123"` |
| `0x1F`, `1e3`, `1_000` | 31, 1000.0, 1000 | numbers | quote them |
| `null`, `~`, nothing | null | field treated as unset | `""` if you need an empty string |
| `NO` (country code) | boolean false | the classic "Norway problem" | `"NO"` |
| `updateMode: Off` (VPA) | boolean false | enum value lost | `"Off"` |

The opposite trap: do **not** quote numbers where the API wants integers - `replicas: "3"` and `containerPort: "80"` are rejected, and `targetPort: "8080"` is read as a *named* port (invalid name). When unsure: `k explain <path>` - `<string>` needs quotes for number/boolean-like values, `<integer>` must not be quoted.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: typed-values
  labels:
    version: "1.10"          # string, not the float 1.1
    enabled: "true"          # string, not a boolean
spec:
  containers:
  - name: app
    image: busybox:1.36
    args: ["sh", "-c", "sleep 3600"]
    env:
    - name: PORT
      value: "8080"          # env values are strings
    - name: DEBUG
      value: "yes"           # unquoted yes would be a boolean
    ports:
    - containerPort: 8080    # integer field: no quotes
```

### Multiple documents, comments, anchors

| Feature | Rule |
|---|---|
| `---` | separates documents in one file; `kubectl apply -f` processes them in order (put the Namespace first) |
| `kind: List` | alternative container with `items:` (what `k get ... -o yaml` prints for several objects) |
| Directories | `k apply -f dir/` (all files), `-R` for sub-directories |
| `#` comments | to end of line; inline comments need a space before `#` (`image: nginx:1.27 # comment`); `a#b` without the space is part of the value |
| Anchors `&x` / aliases `*x` / merge `<<:` | parsed by kubectl, but they confuse reviewers and tools - use Kustomize or Helm for reuse |
| `{}` vs `[]` vs missing | empty map vs empty list vs null - not the same (e.g. NetworkPolicy `ingress: [{}]` allows all, `ingress: []` allows nothing) |

---

## Key fields / syntax

### Common indentation bugs and how kubectl reports them

kubectl wraps parser errors like this: `error: error parsing pod.yaml: error converting YAML to JSON: yaml: line 6: <problem>`. The reported line can be off by one - look at the line above and below as well.

| # | Broken YAML (excerpt) | Reported problem | Fix |
|---|---|---|---|
| 1 | a TAB used for indentation | `found character that cannot start any token` | replace tabs with spaces (`:set list` shows them as `^I`; `:retab` converts them) |
| 2 | `name: web` followed by a **deeper** `labels:` | `mapping values are not allowed in this context` | align `labels:` with `name:` |
| 3 | `name: web: v2` (two colons) | `mapping values are not allowed in this context` | quote the value: `name: "web: v2"` |
| 4 | a key indented by 1 or 3 spaces where siblings use 2 or 4 | `did not find expected key` | align with its siblings |
| 5 | `command: ["sh", "-c", "sleep 3600"` (missing `]`) | `did not find expected ',' or ']'` | close the bracket |
| 6 | `owner: "team-a` (missing quote) | `found unexpected end of stream` | close the quote |

```text
# Example for row 2 (line 5 is wrong)
metadata:
  name: web
    labels:          <- deeper than its sibling "name"
      app: web
```

```text
# Example for row 4 (line 5 is wrong)
spec:
  containers:
  - name: web
    image: nginx:1.27
   ports:            <- 3 spaces instead of 4
   - containerPort: 80
```

### Valid YAML, invalid object (the API server complains)

| Mistake | Typical message | Fix |
|---|---|---|
| A misaligned key lands in the wrong map (e.g. `value:` aligned with `env:`) | `strict decoding error: unknown field "spec.containers[0].value"` | indent it under its list item |
| Typo in a field name | `strict decoding error: unknown field "spec.containers[0].imagee"` | `k explain` for the right name |
| Number/boolean where a string is required | `json: cannot unmarshal number into Go struct field EnvVar.spec.containers.env.value of type string` | quote the value |
| String where an integer is required | `cannot unmarshal string into Go struct field ... of type int32` | remove the quotes |
| `name:web` (no space after the colon) | parsed as the string `"name:web"` → `cannot unmarshal string into Go struct field ... of type v1.ObjectMeta` | add the space |
| `-name: web` (no space after the dash) | parsed as a key `-name`, so `containers` is empty → `Required value` / unknown field | add the space |
| Map instead of list (forgot the `-`) | `cannot unmarshal object into Go struct field PodSpec.spec.containers of type []v1.Container` | add `- ` |
| Required field missing | `The Pod "web" is invalid: spec.containers[0].image: Required value` | add it |
| Deployment selector vs labels | `selector does not match template labels` | make `spec.selector` and `spec.template.metadata.labels` agree |

```text
# The misaligned "value" from row 1: valid YAML, wrong structure
    env:
    - name: MODE
      value: prod
    - name: LEVEL
    value: debug     <- aligned with "env", so it becomes a field of the container
```

---

## Imperative commands

```bash
k apply -f pod.yaml --dry-run=client          # YAML syntax and basic structure, nothing sent for creation
k apply -f pod.yaml --dry-run=server          # full validation (unknown fields, types, admission) without persisting
k create -f pod.yaml --validate=strict        # strict field validation (the default for kubectl apply/create)
vim +12 pod.yaml                              # open directly at the reported line
k explain pod.spec.containers.env.value       # expected type of one field
k get pod web -o yaml > web.yaml              # a known-good structure to compare against
k create deploy x --image=nginx:1.27 --dry-run=client -o yaml | less    # correct skeleton when in doubt
grep -nP '\t' pod.yaml                        # find TAB characters (GNU grep)
cat -A pod.yaml | head -20                    # tabs show as ^I, line ends as $
k get deploy web -o kyaml                     # KYAML output (beta, default on since v1.35; v1.34 needs KUBECTL_KYAML=true)
```

---

## Exam traps & tips

> **Exam tip:** before fixing a broken manifest, find the **first** error only, fix it, apply again. YAML errors cascade - one misaligned line can produce several confusing messages.

> **Exam tip:** generate a skeleton with `--dry-run=client -o yaml` and add fields around it; generated YAML is always correctly indented and typed, so you only have to align your additions.

> **Exam tip:** when pasting from the docs into vim, type `:set paste` first, then `i` and paste with the terminal shortcut, then `Esc` and `:set nopaste`; otherwise auto-indent can shift every pasted line further right ("staircase").

- Quote every env value, label value and ConfigMap value that looks like a number or a boolean.
- Do not quote integers (`replicas`, `containerPort`, `port`, `nodePort`).
- `command:`/`args:` items are strings: `args: ["--port", "8080"]`.
- `---` between documents must start at column 0.
- Keep sibling keys in the same column; for list items align with the key after `- `.

---

## Architect notes

- Treat YAML as data, not code: lint manifests in CI (`kubectl apply --dry-run=server`, kubeconform against the cluster's schemas, policy checks with Kyverno/Gatekeeper/Conftest).
- Avoid hand-copying YAML between environments; use Kustomize overlays or Helm values so differences are explicit and reviewable.
- KYAML (`-o kyaml`, beta in v1.35) is a strict, flow-style YAML subset with quoted strings that removes the implicit-typing traps - a good output format for generated manifests and diffs.
- Pin a formatter/indentation style (e.g. 2 spaces, compact lists) in the repository with an editorconfig and a pre-commit hook; consistent style makes reviews and diffs readable.
- Large YAML blobs inside ConfigMaps (embedded config files) deserve their own files plus a generator (`kubectl create configmap --from-file`, Kustomize `configMapGenerator`) instead of nested block scalars.
- Prefer server-side field validation in automation (`--validate=strict`, the kubectl default) so typos fail loudly instead of being silently dropped.

---

## Docs to bookmark

- Objects in Kubernetes (manifest structure, required fields): https://kubernetes.io/docs/concepts/overview/working-with-objects/
- Kubernetes Configuration Good Practices (blog; the old docs page /docs/concepts/configuration/overview/ redirects here): https://kubernetes.io/blog/2025/11/25/configuration-good-practices/
- Define Environment Variables for a Container: https://kubernetes.io/docs/tasks/inject-data-application/define-environment-variable-container/
- KYAML reference: https://kubernetes.io/docs/reference/encodings/kyaml/

---

## Quick self-check

1. Why does `value: 8080` under `env` fail, while `containerPort: 8080` works?
2. What is the difference between `|` and `>-`?
3. kubectl reports `mapping values are not allowed in this context` on line 7. What do you look for?
4. A pod has `labels: {enabled: yes}`. What happens and how do you fix it?
5. Is `targetPort: "8080"` the same as `targetPort: 8080`?

<details><summary>Answers</summary>

1. `env[].value` is a string field - an unquoted 8080 is a number. `containerPort` is an integer field.
2. `|` keeps line breaks and ends with one newline; `>-` folds lines into one line with spaces and removes the trailing newline.
3. A key that is indented deeper than its sibling (or a second `: ` in a value) on line 7 or right around it.
4. `yes` becomes the boolean `true`; label values must be strings, so the API rejects it. Write `enabled: "yes"`.
5. No. `"8080"` is a string, which `targetPort` interprets as a named port (and `8080` is not a valid port name); `8080` is the port number.

</details>
