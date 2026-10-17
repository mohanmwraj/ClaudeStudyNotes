# Authentication, Authorization and Admission Control

**Competency:** *Understand authentication, authorization and admission control*

**Why it matters / what the exam expects:** every API request passes three gates: who are you, are you allowed, is the object acceptable. Typical tasks: switch contexts and read kubeconfig data, create Roles/ClusterRoles and bindings (often for a ServiceAccount), prove access with `kubectl auth can-i`, fix `forbidden` errors, find which admission plugins are enabled (rarely, enable one on a kubeadm control plane), and fix Pods rejected by **Pod Security Admission**.

---

## Core concepts

### The request flow

```text
 kubectl / Pod / controller
        |  HTTPS
        v
 1. Authentication       who is calling?                        fail -> 401 Unauthorized
 2. Authorization        may this user do VERB on RESOURCE?     fail -> 403 Forbidden
 3. Mutating admission   defaults and injections                 (ServiceAccount, LimitRanger,
                                                                  DefaultStorageClass, mutating webhooks)
 4. Schema validation    is the object well-formed?             fail -> 422 "is invalid"
 5. Validating admission policy checks                          fail -> usually 403 Forbidden
                                                                 (ResourceQuota, PodSecurity,
                                                                  ValidatingAdmissionPolicy, webhooks)
 6. Persisted to etcd    controllers / scheduler / kubelet react
```

- Admission runs only for writes (create, update, patch, delete) and connect requests (such as `exec`); reads (`get`, `list`, `watch`) skip admission.
- If any admission controller in either phase rejects the request, the whole request is rejected.

### Authentication (who are you?)

Kubernetes has **no User objects**. A "user" is just a name (and groups) asserted by a trusted credential. ServiceAccounts are the only identities stored in the API.

| Method | Identity comes from | Typical use | Notes |
|---|---|---|---|
| X.509 client certificate | `CN` = username, `O` = groups; signed by the cluster CA | Admins, control-plane components, kubelets | Cannot be revoked individually (no CRL support); keep them short-lived |
| ServiceAccount token (JWT) | `system:serviceaccount:<ns>:<name>` | Pods, CI systems | Projected, bound and auto-rotated in Pods; `kubectl create token` |
| OIDC tokens | Claims from an identity provider (`--oidc-*` flags, or `--authentication-config`, GA v1.34) | Humans via SSO | Groups from a claim; kubectl uses an exec plugin |
| Webhook token authentication | External service answers a TokenReview | Cloud IAM integrations | |
| Authenticating proxy | Request headers such as `X-Remote-User` set by a trusted proxy | Gateways in front of the API server | |
| Bootstrap tokens | `bootstrap.kubernetes.io/token` Secrets in `kube-system` | Joining nodes (kubeadm) | |
| Static token file | `--token-auth-file` CSV | Legacy and tests only | API server restart to change |
| Anonymous | Requests no authenticator accepted: `system:anonymous`, group `system:unauthenticated` | Health and discovery endpoints | `--anonymous-auth=false` disables it |

Built-in groups: `system:authenticated` (everyone authenticated), `system:serviceaccounts` (all SAs), `system:serviceaccounts:<ns>` (all SAs in a namespace), `system:masters` (superuser; **bypasses RBAC**, cannot be revoked with bindings).

On kubeadm clusters `/etc/kubernetes/admin.conf` holds user `kubernetes-admin` in group `kubeadm:cluster-admins` (bound to `cluster-admin`); `/etc/kubernetes/super-admin.conf` uses `system:masters` and is a break-glass credential.

```bash
kubectl auth whoami                       # SelfSubjectReview (GA v1.28)
# ATTRIBUTE   VALUE
# Username    kubernetes-admin
# Groups      [kubeadm:cluster-admins system:authenticated]
kubectl auth whoami --as=system:serviceaccount:dev:app-sa   # shows the impersonated identity
kubectl auth whoami -o yaml
```

#### Bonus: create a certificate-based user (CSR API)

Lab exercise (more CKA than CKAD). It needs `openssl`, which is not among the tools guaranteed on exam hosts (kubectl, yq, curl, wget, man).

```bash
openssl genrsa -out jane.key 2048
openssl req -new -key jane.key -out jane.csr -subj "/CN=jane/O=dev-team"   # CN=user, O=group
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane
spec:
  request: $(base64 -w0 < jane.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
EOF
kubectl certificate approve jane
kubectl get csr jane -o jsonpath='{.status.certificate}' | base64 -d > jane.crt
kubectl config set-credentials jane --client-certificate=jane.crt --client-key=jane.key --embed-certs=true
kubectl config set-context jane@kubernetes --cluster=kubernetes --user=jane --namespace=dev
kubectl --context=jane@kubernetes auth whoami          # Username jane, Groups [dev-team system:authenticated]
```

### kubeconfig (how kubectl authenticates)

A kubeconfig has three lists and a pointer: **clusters** (API server URL + CA), **users** (credentials), **contexts** (cluster + user + default namespace), and **current-context**. Annotated example: [yaml/kubeconfig-example.yaml](yaml/kubeconfig-example.yaml).

```yaml
apiVersion: v1
kind: Config
current-context: jane@ckad-lab
clusters:
- name: ckad-lab
  cluster:
    server: https://192.168.56.10:6443
    certificate-authority-data: PLACEHOLDER-BASE64-CA
users:
- name: jane
  user:
    client-certificate-data: PLACEHOLDER-BASE64-CERT
    client-key-data: PLACEHOLDER-BASE64-KEY
contexts:
- name: jane@ckad-lab
  context:
    cluster: ckad-lab
    user: jane
    namespace: dev
```

File lookup order: `--kubeconfig <file>` flag, else `$KUBECONFIG` (a `:`-separated list that kubectl **merges**), else `~/.kube/config`. Per-command overrides: `--context`, `--cluster`, `--user`, `-n`.

| Command | Purpose |
|---|---|
| `kubectl config get-contexts` | Table of contexts; `*` marks the current one |
| `kubectl config get-contexts -o name` | Context names only (write them to a file) |
| `kubectl config current-context` | Name of the current context |
| `kubectl config use-context <ctx>` | Switch context (**do this first in every exam task**) |
| `kubectl config set-context --current --namespace=<ns>` | Change the default namespace of the current context |
| `kubectl config set-context <ctx> --cluster=<c> --user=<u> --namespace=<ns>` | Create or modify a context |
| `kubectl config view` | Merged config; certificate data shown as `DATA+OMITTED`, tokens `REDACTED` |
| `kubectl config view --minify` | Only what the current context uses |
| `kubectl config view --raw` | Include certificate/key data and tokens |
| `kubectl config view -o jsonpath='{.contexts[*].name}'` | Any field with JSONPath |
| `kubectl config get-clusters` / `get-users` | List clusters / users |
| `kubectl config set-cluster <c> --server=<url> --certificate-authority=<ca.crt> --embed-certs=true` | Add or modify a cluster |
| `kubectl config set-credentials <u> --client-certificate=<crt> --client-key=<key> --embed-certs=true` | Add a cert user (`--token=<t>` for a token user) |
| `kubectl config delete-context <ctx>` / `rename-context <old> <new>` / `unset <path>` | Clean-up |

```bash
# Decode the client certificate of user "jane" and inspect it
kubectl config view --raw -o jsonpath='{.users[?(@.name=="jane")].user.client-certificate-data}' | base64 -d > jane.crt
openssl x509 -in jane.crt -noout -subject -enddate
# Current context WITHOUT kubectl
grep 'current-context:' ~/.kube/config | awk '{print $2}'
```

### Authorization (may you do this?)

| Mode | What it does |
|---|---|
| `Node` | Lets kubelets read/write only what their own Pods need |
| `RBAC` | Roles and bindings stored as API objects (the standard) |
| `ABAC` | Static JSON policy file (`--authorization-policy-file`); legacy |
| `Webhook` | Asks an external service (SubjectAccessReview) |
| `AlwaysAllow` / `AlwaysDeny` | Testing only; `AlwaysAllow` makes RBAC pointless |

- Set with `--authorization-mode=Node,RBAC` (the kubeadm default) or with a structured `--authorization-config` file (GA v1.32); not both.
- Authorizers are asked in order; each returns allow, deny or no opinion. The first allow or deny wins; if every authorizer has no opinion the request gets **403**. RBAC never denies (it has no deny rules), it only allows or has no opinion.
- Check the mode: `sudo grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml`.

### RBAC in depth

| Object | Scope | Grants | Can reference |
|---|---|---|---|
| `Role` | One namespace | Rules on namespaced resources in that namespace | - |
| `ClusterRole` | Cluster | Rules on any resource, cluster-scoped resources (nodes, PVs, namespaces), `nonResourceURLs` | - |
| `RoleBinding` | One namespace | Subjects get the rules **only in the binding's namespace** | A Role in the same namespace **or a ClusterRole** |
| `ClusterRoleBinding` | Cluster | Subjects get the rules in **all namespaces** and on cluster-scoped resources | A ClusterRole only |

Permissions are purely additive (union of all bindings). `roleRef` is **immutable**: to change the role, delete and recreate the binding.

#### Rule anatomy

```yaml
rules:
- apiGroups: [""]                      # "" = core group
  resources: ["pods", "pods/log"]      # plural, lowercase; "<resource>/<subresource>"
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  resourceNames: ["web"]               # optional: only these object names
  verbs: ["get", "update", "patch"]
- nonResourceURLs: ["/healthz", "/version"]   # ClusterRole only
  verbs: ["get"]
```

| Verb | HTTP request | Notes |
|---|---|---|
| `get` | GET one object | |
| `list` | GET a collection | `list` returns full objects - listing Secrets reveals their data |
| `watch` | GET with `?watch=true` | |
| `create` | POST | Also used for `pods/exec`, `pods/attach`, `pods/portforward`, `pods/eviction` |
| `update` | PUT | |
| `patch` | PATCH | `kubectl apply`, `kubectl scale`, `kubectl label` use patch |
| `delete` / `deletecollection` | DELETE one / many | |
| `*` | everything | Avoid outside admin roles |
| `bind`, `escalate`, `impersonate`, `approve` | special verbs | Privilege-escalation verbs; grant with care |

| API group (`apiGroups`) | Common resources |
|---|---|
| `""` (core) | pods, services, configmaps, secrets, serviceaccounts, persistentvolumeclaims, events, namespaces, nodes, persistentvolumes, resourcequotas, limitranges |
| `apps` | deployments, replicasets, statefulsets, daemonsets |
| `batch` | jobs, cronjobs |
| `networking.k8s.io` | ingresses, networkpolicies, ingressclasses |
| `autoscaling` | horizontalpodautoscalers |
| `policy` | poddisruptionbudgets |
| `rbac.authorization.k8s.io` | roles, rolebindings, clusterroles, clusterrolebindings |
| `storage.k8s.io` | storageclasses |
| `apiextensions.k8s.io` | customresourcedefinitions |

Find any resource's group: `kubectl api-resources | grep -i <name>` (the APIVERSION column, e.g. `apps/v1` -> group `apps`).

| Subresource | Verbs needed | Used by |
|---|---|---|
| `pods/log` | `get` | `kubectl logs` |
| `pods/exec` | `create` (plus `get` on `pods`) | `kubectl exec` |
| `pods/portforward`, `pods/attach` | `create` | `kubectl port-forward`, `kubectl attach` |
| `pods/eviction` | `create` | `kubectl drain` |
| `deployments/scale` (group `apps`) | `get`, `update`, `patch` | `kubectl scale`, HPA |
| `pods/status`, `deployments/status` | `get`, `update`, `patch` | Controllers |

`kubectl exec`, `attach` and `port-forward` now use WebSockets, which start as an HTTP GET. Since v1.35 the API server also requires `create` for these upgrades (feature gate `AuthorizePodWebsocketUpgradeCreatePermission`, beta, on by default). On older versions `get` on `pods/exec` could be enough to exec, so never grant `get` on `pods/*` casually.

Rules on `resourceNames`: you cannot restrict top-level `create` (the name is not known yet) or `deletecollection` by name (subresources such as `pods/exec` can be restricted); for `list`/`watch` restricted by name the client must send `--field-selector metadata.name=<name>`.

#### Subjects

```yaml
subjects:
- kind: User                          # any name from authentication
  name: jane
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: dev-team
  apiGroup: rbac.authorization.k8s.io
- kind: ServiceAccount                # no apiGroup, namespace REQUIRED
  name: app-sa
  namespace: dev
- kind: Group                         # every ServiceAccount in namespace "qa"
  name: system:serviceaccounts:qa
  apiGroup: rbac.authorization.k8s.io
```

#### Default user-facing ClusterRoles

| ClusterRole | Grants | Does NOT grant |
|---|---|---|
| `cluster-admin` | Everything. With a RoleBinding: everything in that namespace, including the namespace itself | - |
| `admin` | Read/write most namespaced resources, including Roles and RoleBindings | Write access to ResourceQuota or the Namespace itself; EndpointSlice writes |
| `edit` | Read/write most namespaced objects, including Secrets and running Pods as any SA of the namespace | Viewing or modifying Roles and RoleBindings |
| `view` | Read-only on most namespaced objects | Secrets, Roles, RoleBindings |

These are meant to be bound per namespace with RoleBindings: `kubectl create rolebinding dev-view --clusterrole=view --group=dev-team -n dev`.

**Aggregated ClusterRoles:** a ClusterRole with `aggregationRule.clusterRoleSelectors` gets its `rules` filled in by a controller from all ClusterRoles matching the labels. `admin`, `edit` and `view` aggregate ClusterRoles labelled `rbac.authorization.k8s.io/aggregate-to-admin|edit|view: "true"` - the standard way to expose CRDs to normal users ([yaml/clusterrole.yaml](yaml/clusterrole.yaml)).

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      rbac.example.com/aggregate-to-monitoring: "true"
rules: []                             # filled in by the control plane
```

Reference files: [yaml/role-pod-reader.yaml](yaml/role-pod-reader.yaml), [yaml/rolebinding-sa.yaml](yaml/rolebinding-sa.yaml), [yaml/clusterrole.yaml](yaml/clusterrole.yaml), [yaml/clusterrolebinding.yaml](yaml/clusterrolebinding.yaml), [yaml/rolebinding-to-clusterrole.yaml](yaml/rolebinding-to-clusterrole.yaml).

### Admission control (is the object acceptable?)

| Phase | Can change the object? | Examples |
|---|---|---|
| Mutating | Yes (defaults, injections) | ServiceAccount, LimitRanger, DefaultStorageClass, DefaultTolerationSeconds, AlwaysPullImages, MutatingAdmissionWebhook, MutatingAdmissionPolicy |
| Validating | No, accept or reject only | NamespaceLifecycle, ResourceQuota, PodSecurity, NodeRestriction, ValidatingAdmissionPolicy, ValidatingAdmissionWebhook |

| Plugin | On by default? | What it does |
|---|---|---|
| `NamespaceLifecycle` | Yes | Rejects objects in terminating or missing namespaces; protects `default`, `kube-system`, `kube-public` from deletion |
| `LimitRanger` | Yes | Applies LimitRange defaults, enforces min/max/ratio ([03](03-requests-limits-and-quotas.md)) |
| `ServiceAccount` | Yes | Sets the `default` SA, mounts the token volume, copies the SA's `imagePullSecrets` into the Pod |
| `DefaultStorageClass` | Yes | Gives PVCs without `storageClassName` the default StorageClass |
| `DefaultTolerationSeconds` | Yes | Adds 300 s tolerations for `not-ready` / `unreachable` taints |
| `ResourceQuota` | Yes | Rejects requests that would exceed a ResourceQuota |
| `PodSecurity` | Yes | Enforces Pod Security Standards from namespace labels (below) |
| `Priority` | Yes | Resolves `priorityClassName` to a priority value |
| `MutatingAdmissionWebhook` / `ValidatingAdmissionWebhook` | Yes | Call the configured webhooks (Kyverno, Gatekeeper, Istio injection, ...) |
| `ValidatingAdmissionPolicy` | Yes | Runs CEL ValidatingAdmissionPolicies (GA v1.30) |
| `MutatingAdmissionPolicy` | Yes in v1.36+ incl. v1.37 (beta and off by default in v1.34-v1.35) | CEL-based mutation policies |
| `NodeRestriction` | No - **kubeadm enables it** | Kubelets may only modify their own Node and Pods bound to them |
| `AlwaysPullImages` | No | Forces `imagePullPolicy: Always` (multi-tenant clusters) |

Default list for **v1.37** (the current exam version), per the admission controller docs (`kube-apiserver -h | grep enable-admission-plugins`): CertificateApproval, CertificateSigning, CertificateSubjectRestriction, DefaultIngressClass, DefaultStorageClass, DefaultTolerationSeconds, LimitRanger, MutatingAdmissionPolicy, MutatingAdmissionWebhook, NamespaceLifecycle, PersistentVolumeClaimResize, PodSecurity, Priority, ResourceQuota, RuntimeClass, ServiceAccount, StorageObjectInUseProtection, TaintNodesByCondition, ValidatingAdmissionPolicy, ValidatingAdmissionWebhook. Releases before v1.36 lack MutatingAdmissionPolicy. Always confirm on the cluster in front of you.

#### Checking and changing plugins on a kubeadm cluster

```bash
# What is configured (from any machine with kubectl)
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep -E -- '--(enable|disable)-admission-plugins'
# The defaults compiled into the binary (exec runs the binary directly, no shell needed)
kubectl -n kube-system exec kube-apiserver-<node> -- kube-apiserver -h | grep -- '--enable-admission-plugins'

# Change it (on the control-plane node)
ssh <controlplane>
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak   # back up OUTSIDE manifests/
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
#   - --enable-admission-plugins=NodeRestriction,AlwaysPullImages     (comma list, no spaces; order irrelevant)
#   - --disable-admission-plugins=DefaultStorageClass                 (to switch off a default plugin)
# The kubelet recreates the static Pod automatically; the API is down for ~30-90 s
sudo crictl ps --name kube-apiserver          # new container appears
kubectl -n kube-system get pod -l component=kube-apiserver
# Not coming back?
sudo crictl ps -a --name kube-apiserver; sudo crictl logs <container-id>
sudo journalctl -u kubelet --since "5 min ago" | tail -30
ls /var/log/pods/ | grep kube-apiserver
```

> **Exam tip:** never leave a backup copy inside `/etc/kubernetes/manifests/` - the kubelet would try to run it as a second static Pod.

### Pod Security Admission (PSA)

PodSecurityPolicy was removed in v1.25; PSA (GA v1.25) is the built-in replacement. It checks Pods against the **Pod Security Standards** per namespace, configured with labels.

| Level | Intent | Main rules |
|---|---|---|
| `privileged` | Unrestricted | None |
| `baseline` | Block known privilege escalations | No `privileged`; no `hostNetwork`/`hostPID`/`hostIPC`; no `hostPath` volumes; no `hostPort`; added capabilities only from the default set (AUDIT_WRITE, CHOWN, DAC_OVERRIDE, FOWNER, FSETID, KILL, MKNOD, NET_BIND_SERVICE, SETFCAP, SETGID, SETPCAP, SETUID, SYS_CHROOT); seccomp and AppArmor not `Unconfined`; restricted SELinux types; `procMount: Default`; only safe sysctls |
| `restricted` | Hardened best practice | Baseline plus: `runAsNonRoot: true`; `runAsUser` not 0; `allowPrivilegeEscalation: false`; `capabilities.drop: ["ALL"]` (only `NET_BIND_SERVICE` may be added); `seccompProfile.type` explicitly `RuntimeDefault` or `Localhost`; volumes only configMap, csi, downwardAPI, emptyDir, ephemeral, persistentVolumeClaim, projected, secret |

| Mode | Pods that violate | Workload objects (Deployment, Job, ...) that violate |
|---|---|---|
| `enforce` | **Rejected** | Not checked - the Deployment is created, its Pods are rejected |
| `warn` | Allowed, warning returned to the client | Warning returned |
| `audit` | Allowed, annotation in the audit log | Audit annotation |

```text
pod-security.kubernetes.io/<MODE>: <LEVEL>               MODE = enforce | audit | warn
pod-security.kubernetes.io/<MODE>-version: <VERSION>     VERSION = latest (default) | v1.33 | ...
```

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: secure-apps
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
```

```bash
kubectl label namespace secure-apps pod-security.kubernetes.io/enforce=restricted
kubectl label --overwrite namespace secure-apps pod-security.kubernetes.io/enforce=baseline
kubectl label namespace secure-apps pod-security.kubernetes.io/enforce-          # remove the label
kubectl get namespace secure-apps --show-labels
# Which existing Pods would violate a stricter level? (server dry-run, changes nothing)
kubectl label --dry-run=server --overwrite namespace secure-apps pod-security.kubernetes.io/enforce=restricted
```

A rejected Pod looks like this:

```text
Error from server (Forbidden): error when creating "pod.yaml": pods "web" is forbidden: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "web" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "web" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "web" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "web" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

Fix workflow for a Deployment whose Pods never appear:

```bash
kubectl get deploy,rs -n secure-apps                       # READY 0/3, ReplicaSet CURRENT 0
kubectl describe rs -n secure-apps -l app=web | grep -A3 FailedCreate   # the violation list
kubectl get ns secure-apps --show-labels                   # which level is enforced
kubectl edit deploy web -n secure-apps                     # add the securityContext fields listed
kubectl rollout status deploy/web -n secure-apps
```

Copy-paste compliant template: [yaml/pod-restricted-compliant.yaml](yaml/pod-restricted-compliant.yaml). Namespaces: [yaml/namespace-pod-security-labels.yaml](yaml/namespace-pod-security-labels.yaml). Broken Deployment to practise on: [yaml/broken/deploy-violates-restricted.yaml](yaml/broken/deploy-violates-restricted.yaml). Field details: [07-security-contexts-and-capabilities.md](07-security-contexts-and-capabilities.md).

Exemptions (by username, RuntimeClass or namespace) are configured cluster-wide in the PodSecurity admission configuration file (`--admission-control-config-file`), not with labels.

### Bonus: ValidatingAdmissionPolicy (CEL)

In-process validation, no webhook to run. `admissionregistration.k8s.io/v1`, GA v1.30. A **policy** holds the logic; a **binding** activates it for selected resources and decides the action. Full file: [yaml/validating-admission-policy.yaml](yaml/validating-admission-policy.yaml).

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: max-replicas.example.com
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["deployments"]
  validations:
  - expression: "object.spec.replicas <= 5"
    message: "at most 5 replicas"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: max-replicas-binding.example.com
spec:
  policyName: max-replicas.example.com
  validationActions: [Deny]           # Deny | Warn | Audit (Deny and Warn cannot be combined)
  matchResources:
    namespaceSelector:
      matchLabels:
        environment: test
```

CEL variables: `object`, `oldObject`, `request`, `params` (with `paramKind` + `paramRef`), `namespaceObject`, `authorizer`. The error reads `ValidatingAdmissionPolicy 'max-replicas.example.com' with binding 'max-replicas-binding.example.com' denied request: ...`. Note that `kubectl scale` and the HPA write the `deployments/scale` subresource, which `resources: ["deployments"]` does not match - list `"deployments/scale"` too if scaling must be covered.

Admission **webhooks** (awareness): `ValidatingWebhookConfiguration` / `MutatingWebhookConfiguration` send an AdmissionReview to an HTTPS service.

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: policy.example.com
webhooks:
- name: pods.policy.example.com       # fully qualified name
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Fail                 # Ignore = fail open
  timeoutSeconds: 5
  rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: ["CREATE", "UPDATE"]
    resources: ["pods"]
  namespaceSelector:                  # keep kube-system out of the blast radius
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: NotIn
      values: ["kube-system"]
  clientConfig:
    service:
      namespace: policy-system
      name: policy-webhook
      path: /validate
      port: 443
```

---

## Key fields / syntax

| Need | Field / syntax |
|---|---|
| Core group in a rule | `apiGroups: [""]` |
| Subresource | `resources: ["pods/log"]`, `["deployments/scale"]` with `apiGroups: ["apps"]` |
| One object only | `resourceNames: ["app-config"]` |
| ServiceAccount subject | `kind: ServiceAccount`, `name`, `namespace` (no apiGroup) |
| User / Group subject | `kind: User` / `Group`, `apiGroup: rbac.authorization.k8s.io` |
| Binding target | `roleRef: {apiGroup: rbac.authorization.k8s.io, kind: Role, name: <n>}` |
| SA as a username | `system:serviceaccount:<ns>:<sa>` |
| PSA label | `pod-security.kubernetes.io/enforce: restricted` |
| Admission flags | `--enable-admission-plugins=...`, `--disable-admission-plugins=...` |

---

## Imperative commands

```bash
# Roles and ClusterRoles (generate YAML first if you want to edit)
kubectl create role pod-reader -n dev --verb=get,list,watch --resource=pods --dry-run=client -o yaml > role.yaml
kubectl create role pod-reader -n dev --verb=get --verb=list --verb=watch --resource=pods,pods/log
kubectl create role cm-reader -n dev --verb=get --resource=configmaps --resource-name=app-config
kubectl create role deploy-mgr -n dev --verb=get,list,create,update,patch,delete --resource=deployments.apps
kubectl create role scaler -n dev --verb=get,patch,update --resource=deployments/scale   # group resolved to apps
kubectl create clusterrole node-reader --verb=get,list,watch --resource=nodes
kubectl create clusterrole healthz --verb=get --non-resource-url=/healthz --non-resource-url=/version
kubectl create clusterrole monitoring --aggregation-rule="rbac.example.com/aggregate-to-monitoring=true"

# Bindings
kubectl create rolebinding pod-reader-rb -n dev --role=pod-reader --serviceaccount=dev:app-sa
kubectl create rolebinding jane-edit -n dev --clusterrole=edit --user=jane        # ClusterRole scoped to "dev"
kubectl create rolebinding team-view -n dev --clusterrole=view --group=dev-team
kubectl create clusterrolebinding node-reader-crb --clusterrole=node-reader --serviceaccount=monitoring:node-exporter
kubectl create clusterrolebinding root-admin --clusterrole=cluster-admin --user=root --dry-run=client -o yaml

# Verify
kubectl auth can-i create deployments -n dev                           # yes / no for yourself
kubectl auth can-i list pods -n dev --as=jane
kubectl auth can-i list pods -n dev --as=jane --as-group=dev-team      # --as-group needs --as
kubectl auth can-i list secrets -n dev --as=system:serviceaccount:dev:app-sa
kubectl auth can-i get pods --subresource=log -n dev --as=jane          # subresources via --subresource
kubectl auth can-i patch deployments --subresource=scale -n dev --as=jane
kubectl auth can-i '*' '*' -A                                          # am I effectively cluster-admin?
kubectl auth can-i --list -n dev --as=system:serviceaccount:dev:app-sa  # everything this SA may do
kubectl auth can-i delete pods -n dev -q --as=jane; echo $?             # exit code 0 = yes, 1 = no

# Inspect
kubectl get roles,rolebindings -n dev
kubectl get rolebindings -n dev -o wide              # ROLE, USERS, GROUPS, SERVICEACCOUNTS columns
kubectl get clusterrolebindings -o wide | grep -E 'app-sa|jane'
kubectl describe role pod-reader -n dev
kubectl describe clusterrole view | head -40
kubectl auth reconcile -f rbac.yaml --dry-run=client   # create/update RBAC objects additively
```

---

## Exam traps & tips

> **Exam tip:** `--serviceaccount=<namespace>:<name>` uses a colon and no `system:` prefix. In `--as` you need the full username: `--as=system:serviceaccount:<namespace>:<name>`.

> **Exam tip:** a RoleBinding grants access only in **its own** namespace. Create it with `-n <target-namespace>` even when the ServiceAccount lives elsewhere.

> **Exam tip:** you cannot edit `roleRef`. `kubectl edit` fails with "cannot change roleRef" - delete and recreate the binding (`kubectl create rolebinding ... --dry-run=client -o yaml | kubectl replace --force -f -`).

> **Exam tip:** in `kubectl auth can-i`, `deployments/foo` means the deployment **named** foo. For a subresource use `--subresource=scale` or `--subresource=log`.

> **Exam tip:** with PSA `enforce`, `kubectl apply` of a Deployment succeeds, then nothing happens. Always look at `kubectl describe rs` events (FailedCreate) when READY stays 0.

> **Exam tip:** switch context first: `kubectl config use-context <ctx>` (the task header gives it). A correct answer in the wrong cluster scores zero.

- Resource names in rules are **plural lowercase** (`pods`, `deployments`), never kinds (`Pod`).
- Forgetting `apiGroups: ["apps"]` for deployments in hand-written YAML: the rule silently matches nothing. `kubectl create role --resource=deployments` resolves the group for you.
- `kubectl create role` validates resource names against the API (it needs a reachable cluster even with `--dry-run=client`).
- RBAC changes take effect immediately - no Pod restart needed for the permission itself (the app may cache errors, so check its logs again).
- Editing `kube-apiserver.yaml`: a YAML typo means the API server never comes back. Keep the backup, check `crictl` and kubelet logs.
- PSA warnings for a namespace label change list existing violating Pods, but existing Pods keep running; enforcement only affects new Pods.

---

## Architect notes

- **Humans via SSO groups, workloads via ServiceAccounts.** Map OIDC groups to RoleBindings; avoid client certificates for people (no revocation) and keep `system:masters` / `super-admin.conf` for break-glass only.
- **Least privilege by default:** one ServiceAccount per workload, namespace-scoped Roles, no wildcards, no `cluster-admin` for apps or CI. Review with `kubectl auth can-i --list --as=...` or tools such as rbac-lookup / rakkess.
- Treat `secrets: get/list/watch`, `pods/exec`, `create pods` (runs as any SA in the namespace), `nodes/proxy`, `bind`, `escalate` and `impersonate` as **privileged** permissions.
- Prefer a ClusterRole defined once + per-namespace RoleBindings over copy-pasted Roles; aggregate CRD permissions into `view`/`edit`/`admin`.
- **Pod Security:** `baseline` enforced everywhere, `restricted` enforced for application namespaces, `warn`/`audit` at `restricted` to drive migration; pin `-version` for predictable upgrades.
- **Policy layering:** PSA for pod hardening, ValidatingAdmissionPolicy (CEL) for simple org rules, webhooks (Kyverno, Gatekeeper) only for what CEL cannot express. Give webhooks `failurePolicy`, `timeoutSeconds`, and namespace selectors that exclude system namespaces to avoid cluster-wide outages.
- **Audit logging** (`--audit-policy-file`) is the only reliable answer to "who changed this?"; ship it off-cluster.
- Rotate credentials: short-lived tokens (`kubectl create token --duration`), bound SA tokens, cert expiry alerts, and remove unused kubeconfig users.

---

## Docs to bookmark

- https://kubernetes.io/docs/concepts/security/controlling-access/
- https://kubernetes.io/docs/reference/access-authn-authz/authentication/
- https://kubernetes.io/docs/reference/access-authn-authz/authorization/
- https://kubernetes.io/docs/reference/access-authn-authz/rbac/ (kubectl create role/rolebinding examples, default roles)
- https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/
- https://kubernetes.io/docs/concepts/security/pod-security-admission/
- https://kubernetes.io/docs/concepts/security/pod-security-standards/
- https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/
- https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/
- https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/
- https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/
- https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/
- https://kubernetes.io/docs/reference/access-authn-authz/certificate-signing-requests/
- https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/

---

## Quick self-check

1. Put these in order: validating admission, authentication, schema validation, authorization, mutating admission.
2. You need ServiceAccount `ci:deployer` to manage Deployments only in namespace `prod`. Which objects, in which namespace?
3. Why does `kubectl edit rolebinding x` fail when you change `roleRef.name`?
4. What does a RoleBinding that references the ClusterRole `edit` grant?
5. A Deployment in a namespace with `pod-security.kubernetes.io/enforce=restricted` shows READY 0/2 and no Pods. Where do you find the reason?
6. How do you print only the context names of your kubeconfig?

<details><summary>Answers</summary>

1. Authentication, authorization, mutating admission, schema validation, validating admission (then persistence to etcd).
2. A Role in `prod` (apiGroups `apps`, resources `deployments`, verbs as needed) and a RoleBinding **in `prod`** with subject `kind: ServiceAccount, name: deployer, namespace: ci`. Imperative: `kubectl create role deployer -n prod --verb=get,list,watch,create,update,patch,delete --resource=deployments` and `kubectl create rolebinding deployer -n prod --role=deployer --serviceaccount=ci:deployer`.
3. `roleRef` is immutable. Delete the binding and create a new one.
4. The `edit` permissions, but only inside the RoleBinding's namespace.
5. In the ReplicaSet events: `kubectl describe rs -n <ns>` shows `FailedCreate ... violates PodSecurity "restricted:latest": ...`.
6. `kubectl config get-contexts -o name` (or `kubectl config view -o jsonpath='{.contexts[*].name}'`).

</details>
