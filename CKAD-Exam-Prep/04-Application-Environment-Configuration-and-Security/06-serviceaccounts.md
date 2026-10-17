# ServiceAccounts

**Competency:** *Understand ServiceAccounts*

**Why it matters / what the exam expects:** create a ServiceAccount, run a Pod or Deployment as it, bind RBAC to it, switch token automount on/off, issue a token, and - a classic - fix an application whose logs say `forbidden` by finding the right existing Role/RoleBinding and pointing the Deployment at the correct ServiceAccount.

---

## Core concepts

- A **ServiceAccount (SA)** is a namespaced identity for processes running in Pods (and for automation). Its username is `system:serviceaccount:<namespace>:<name>`; it is in the groups `system:serviceaccounts`, `system:serviceaccounts:<namespace>` and `system:authenticated`.
- Every namespace has a **`default`** SA (the ServiceAccount controller recreates it if deleted). With RBAC it has **no permissions** beyond API discovery.
- A Pod without `spec.serviceAccountName` runs as `default`. The old field `spec.serviceAccount` is deprecated.
- The SA of an existing Pod **cannot be changed** - recreate the Pod. For Deployments (and other controllers) change the template: `kubectl set serviceaccount deploy/<name> <sa>` (this triggers a rollout).
- The SA must exist when the Pod is created, otherwise the ServiceAccount admission plugin rejects the Pod (`serviceaccount "x" not found`).

### Tokens

| Token | How you get it | Lifetime | Notes |
|---|---|---|---|
| **Projected, bound token** (default in Pods) | Automatically mounted by the kubelet | Requested for about 1 h (`expirationSeconds: 3607`), refreshed by the kubelet | Bound to the Pod: invalid once the Pod is deleted; audience-scoped |
| **`kubectl create token <sa>`** | TokenRequest API | Server default (typically 1 h) or `--duration` | Not stored anywhere; bind to an object with `--bound-object-kind` (`Pod`, `Secret` or `Node`) |
| **Custom projected token** | `projected.sources[].serviceAccountToken` with `audience`, `expirationSeconds` (min 600) | As requested | For external systems (Vault, cloud IAM federation) |
| **Long-lived token Secret** (legacy) | Create a Secret of type `kubernetes.io/service-account-token` with annotation `kubernetes.io/service-account.name` | **Never expires** - delete the Secret to revoke | Not auto-created since v1.24; avoid |

The default mount in every Pod (unless automount is disabled):

```text
/var/run/secrets/kubernetes.io/serviceaccount/
  token       projected, auto-rotated JWT for the API server audience
  ca.crt      cluster CA (from ConfigMap kube-root-ca.crt) to verify https://kubernetes.default.svc
  namespace   the Pod's namespace (Downward API)
```

It comes from a projected volume named `kube-api-access-<suffix>` that the ServiceAccount admission plugin adds:

```yaml
volumes:
- name: kube-api-access-abcde
  projected:
    defaultMode: 420                 # 0644
    sources:
    - serviceAccountToken:
        expirationSeconds: 3607
        path: token
    - configMap:
        name: kube-root-ca.crt
        items:
        - key: ca.crt
          path: ca.crt
    - downwardAPI:
        items:
        - path: namespace
          fieldRef:
            apiVersion: v1
            fieldPath: metadata.namespace
```

### automountServiceAccountToken

| SA setting | Pod setting | Token mounted? |
|---|---|---|
| unset / `true` | unset | Yes |
| `false` | unset | No |
| `false` | `true` | **Yes** (Pod wins) |
| `true` / unset | `false` | **No** (Pod wins) |

Disable it for Pods that never call the API; keep it for Pods that do (operators, controllers, apps using in-cluster config).

### imagePullSecrets on a ServiceAccount

Secrets listed in the SA's `imagePullSecrets` are copied into every **new** Pod that uses the SA (ServiceAccount admission plugin). This is how you give a whole namespace access to a private registry without touching each Pod spec.

---

## Key fields / syntax

Files: [yaml/serviceaccount.yaml](yaml/serviceaccount.yaml), [yaml/pod-with-serviceaccount.yaml](yaml/pod-with-serviceaccount.yaml), [yaml/sa-long-lived-token-secret.yaml](yaml/sa-long-lived-token-secret.yaml), [yaml/pod-sa-token-curl.yaml](yaml/pod-sa-token-curl.yaml), [yaml/rolebinding-sa.yaml](yaml/rolebinding-sa.yaml), [yaml/pod-projected-volume.yaml](yaml/pod-projected-volume.yaml).

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: build-bot
  namespace: dev
automountServiceAccountToken: false
imagePullSecrets:
- name: regcred
---
apiVersion: v1
kind: Pod
metadata:
  name: sa-demo
  namespace: dev
spec:
  serviceAccountName: build-bot          # not "serviceAccount" (deprecated)
  automountServiceAccountToken: true     # overrides the SA's false
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
---
apiVersion: v1
kind: Secret                             # legacy long-lived token (avoid)
metadata:
  name: build-bot-token
  namespace: dev
  annotations:
    kubernetes.io/service-account.name: build-bot
type: kubernetes.io/service-account-token
```

---

## Imperative commands

```bash
# Create / inspect
kubectl create serviceaccount app-sa -n dev                          # short name: sa
kubectl create sa app-sa -n dev --dry-run=client -o yaml > sa.yaml
kubectl get sa -n dev
kubectl describe sa app-sa -n dev                                   # Tokens: <none> is normal since v1.24
kubectl get pod web -n dev -o jsonpath='{.spec.serviceAccountName}{"\n"}'

# Assign
kubectl set serviceaccount deploy/web app-sa -n dev                 # alias: kubectl set sa; triggers a rollout
kubectl create deployment web --image=nginx:1.27 -n dev --dry-run=client -o yaml > web.yaml   # then add serviceAccountName
kubectl run tmp --image=busybox:1.36 -n dev --dry-run=client -o yaml -- sleep 3600 > pod.yaml # add serviceAccountName, apply
kubectl get pod web -n dev -o yaml > web-pod.yaml && kubectl replace --force -f web-pod.yaml  # bare Pod: recreate after editing

# Automount and pull secrets
kubectl patch sa default -n dev -p '{"automountServiceAccountToken": false}'
kubectl patch sa app-sa -n dev -p '{"imagePullSecrets":[{"name":"regcred"}]}'

# Tokens
kubectl create token app-sa -n dev                                  # short-lived JWT to stdout
kubectl create token app-sa -n dev --duration=2h > /opt/course/6/token
kubectl create token app-sa -n dev --audience=https://vault.example.com
kubectl create token app-sa -n dev --bound-object-kind=Pod --bound-object-name=web   # dies with the Pod
kubectl get secret app-sa-token -n dev -o jsonpath='{.data.token}' | base64 -d       # legacy Secret token

# RBAC for the SA
kubectl create role pod-reader -n dev --verb=get,list,watch --resource=pods
kubectl create rolebinding app-sa-pod-reader -n dev --role=pod-reader --serviceaccount=dev:app-sa
kubectl auth can-i list pods -n dev --as=system:serviceaccount:dev:app-sa
kubectl auth can-i --list -n dev --as=system:serviceaccount:dev:app-sa

# Look inside a Pod
kubectl exec -n dev web -- ls /var/run/secrets/kubernetes.io/serviceaccount
kubectl exec -n dev web -- cat /var/run/secrets/kubernetes.io/serviceaccount/namespace
```

### Calling the API from inside a Pod (curl + mounted token)

```bash
kubectl exec -it -n dev api-client -- sh          # e.g. a curlimages/curl:8.10.1 Pod (yaml/pod-sa-token-curl.yaml)
SA=/var/run/secrets/kubernetes.io/serviceaccount
TOKEN=$(cat $SA/token)
NS=$(cat $SA/namespace)
curl --cacert $SA/ca.crt -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/$NS/pods
# quick and insecure variant (skips CA verification):
curl -sk -H "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/namespaces/$NS/pods
# the API server address is also in $KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT
```

| Response | Meaning |
|---|---|
| `200` + JSON `PodList` | Token valid and RBAC allows the request |
| `403` + `pods is forbidden: User "system:serviceaccount:dev:api-reader" cannot list resource "pods" in API group "" in the namespace "dev"` | Authenticated, but no RBAC permission - add a Role/RoleBinding or use another SA |
| `401 Unauthorized` | Token missing, expired or invalid (e.g. the bound Pod or Secret was deleted) |

---

## Typical exam task: "the app's logs show forbidden"

```bash
kubectl config use-context <ctx>
kubectl logs deploy/app -n team | tail -3
#   ... pods is forbidden: User "system:serviceaccount:team:default" cannot list resource "pods" ...
#   -> the Deployment runs as "default", which has no permissions

kubectl get role,rolebinding -n team -o wide       # which binding grants what, to which SERVICEACCOUNTS
kubectl describe role pod-lister -n team           # confirm the rule: pods - get, list
kubectl get clusterrolebinding -o wide | grep team # also check cluster-wide bindings
kubectl get sa -n team                             # the SA named in the binding must exist

kubectl set serviceaccount deploy/app monitor-sa -n team     # point the Deployment at the bound SA
kubectl rollout status deploy/app -n team
kubectl auth can-i list pods -n team --as=system:serviceaccount:team:monitor-sa   # yes
kubectl logs deploy/app -n team | tail -3                     # no more "forbidden"
```

If no suitable binding exists (and the task allows it), create one: `kubectl create rolebinding app-pods -n team --role=pod-lister --serviceaccount=team:<sa>`. Do not edit or delete existing RBAC objects unless the task says so.

---

## Exam traps & tips

> **Exam tip:** binding flag syntax is `--serviceaccount=<ns>:<name>`; impersonation is `--as=system:serviceaccount:<ns>:<name>`. Mixing them up is the most common RBAC/SA mistake.

> **Exam tip:** `kubectl edit pod` cannot change `serviceAccountName` on a running Pod. Edit the Deployment (or `kubectl set serviceaccount`), or recreate a bare Pod with `kubectl replace --force -f`.

> **Exam tip:** `kubectl create token` only prints a token; it creates no object. If the task wants a token "stored in a file", redirect the output. If it wants a token that never expires, create the annotated `kubernetes.io/service-account-token` Secret.

> **Exam tip:** with `automountServiceAccountToken: false`, `/var/run/secrets/kubernetes.io/serviceaccount` does not exist - apps using in-cluster config fail with "unable to load in-cluster configuration".

- ServiceAccount subjects in bindings require `namespace`; there is no `apiGroup` for them.
- The SA must be in the same namespace as the Pod.
- RBAC fixes take effect immediately, but the app may need a restart (or its retry loop) to recover.
- A long-lived token Secret created before its SA exists is not populated; create the SA first.

---

## Architect notes

- **One ServiceAccount per workload**, named after the app; never grant permissions to `default`. Disable automount on `default` and on every Pod that does not call the API.
- **Short-lived, bound tokens only.** Avoid long-lived token Secrets; for CI/CD outside the cluster prefer OIDC federation (workload identity) or `kubectl create token --duration` per job.
- **Workload identity for clouds:** projected tokens with a dedicated `audience` are exchanged for cloud IAM credentials (EKS Pod Identity/IRSA, GKE Workload Identity, Azure Workload Identity) - no static cloud keys in Secrets.
- External systems should validate SA tokens with the **TokenReview** API (immediate revocation when the bound Pod is deleted) rather than only checking the JWT signature.
- A mounted token is a bearer credential: anyone who can `exec` into the Pod or read its filesystem can use it. Restrict `pods/exec` and keep SA permissions minimal.
- Audit SA permissions regularly: `kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>`; alert on ClusterRoleBindings to SAs.
- Centralise registry access with SA `imagePullSecrets` per namespace, or kubelet credential provider plugins, instead of per-Pod secrets.
- Avoid binding roles to the group `system:serviceaccounts:<ns>` - it silently grants every current and future SA in the namespace.

---

## Docs to bookmark

- https://kubernetes.io/docs/concepts/security/service-accounts/
- https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
- https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/
- https://kubernetes.io/docs/tasks/run-application/access-api-from-pod/
- https://kubernetes.io/docs/concepts/storage/projected-volumes/
- https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/kubectl_create_token/

---

## Quick self-check

1. Which identity does a Pod in namespace `shop` use if its spec has no `serviceAccountName`, and what can it do with RBAC enabled?
2. How do you make Deployment `api` in `shop` use SA `api-sa`?
3. The SA has `automountServiceAccountToken: false` and the Pod sets it to `true`. Is a token mounted?
4. Write the command to put a 30-minute token for SA `ci` (namespace `tools`) into `/tmp/ci.token`.
5. Where are the token, CA certificate and namespace found inside a Pod?
6. How do you create a token that never expires, and how do you revoke it?

<details><summary>Answers</summary>

1. `system:serviceaccount:shop:default`; only API discovery - no access to resources unless someone bound a role to it.
2. `kubectl set serviceaccount deploy/api api-sa -n shop` (or set `spec.template.spec.serviceAccountName`).
3. Yes - the Pod-level setting overrides the SA-level setting.
4. `kubectl create token ci -n tools --duration=30m > /tmp/ci.token`.
5. `/var/run/secrets/kubernetes.io/serviceaccount/token`, `.../ca.crt`, `.../namespace`.
6. Create a Secret of type `kubernetes.io/service-account-token` with annotation `kubernetes.io/service-account.name: <sa>`; delete that Secret to revoke the token.

</details>
