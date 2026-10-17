# 04 · Security architecture

> **Exam link:** [04 · Environment, Configuration and Security](../04-Application-Environment-Configuration-and-Security/README.md) (authentication, authorization, admission, ServiceAccounts, SecurityContexts, Secrets) · [05 · Services and Networking](../05-Services-and-Networking/README.md) (NetworkPolicies). The exam tests each control on its own; an architecture layers them so that any single failure is contained.

Assume every layer will eventually fail: a vulnerable library, a leaked token, a mis-scoped RoleBinding. Defense in depth means the next layer still holds.

```text
Layer          Prevent                                         Detect / respond
-------------  ----------------------------------------------  ---------------------------------
Supply chain   scan, SBOM, sign in CI; verify at admission      registry scanning, SBOM queries
Identity       OIDC groups + namespaced RBAC; 1 SA per app;     audit logs, `kubectl auth can-i`
               bound tokens; workload identity to cloud IAM     reviews
Pod            PSA restricted; securityContext baseline;       admission policy reports
               seccomp; user namespaces
Network        default-deny NetworkPolicy; explicit allows;    flow logs (CNI), mesh telemetry
               mTLS (mesh) where identity matters
Data           Secrets encrypted at rest (KMS v2); external    secret-manager audit trail
               secret manager; rotation
Runtime        minimal nodes, patched; sandboxes for          Falco/Tetragon alerts -> SIEM
               untrusted code
```

## Principles

1. **Defense in depth.** No single control (not even PSA or NetworkPolicy) is sufficient.
2. **Least privilege everywhere:** humans, CI, workloads, pods, network paths.
3. **Secure by default at the namespace level.** New namespaces get PSA `restricted`, default-deny, no default token; exceptions are reviewed and recorded.
4. **Policy as code,** enforced at admission and tested in CI before it reaches a cluster.
5. **Identity beats location:** workload identity, mTLS and short-lived credentials instead of IP allow-lists and static keys.
6. **The namespace is the security boundary,** not the pod: anyone who can create pods in a namespace can use its Secrets and ServiceAccounts.
7. **Detect and respond:** audit logs and runtime detection are part of the design, not an afterthought.

## Recommended defaults

| Control | Default | Implemented by |
|---|---|---|
| Pod Security | `enforce: restricted` (pinned version), `warn`/`audit: restricted` at `latest` on every app namespace | Namespace labels, [`yaml/namespace-baseline.yaml`](yaml/namespace-baseline.yaml) |
| securityContext | `runAsNonRoot`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`, `readOnlyRootFilesystem: true`, `seccompProfile: RuntimeDefault` | pod + container `securityContext` |
| Humans | OIDC groups bound per namespace; no `cluster-admin` for daily work | RoleBinding to Role / `view` / `edit` |
| Workloads | one ServiceAccount per workload, `automountServiceAccountToken: false` unless it calls the API | ServiceAccount + pod spec |
| Cloud access | workload identity federation, no static cloud keys in Secrets | EKS Pod Identity/IRSA, GKE Workload Identity Federation, Azure Workload Identity (verify current status) |
| Network | default-deny ingress + egress, allow DNS, explicit allows per hop | NetworkPolicy, [`yaml/networkpolicy-three-tier.yaml`](yaml/networkpolicy-three-tier.yaml) |
| Secrets | synced from an external manager, mounted as files, encrypted at rest with KMS v2 | External Secrets Operator / Secrets Store CSI Driver, `EncryptionConfiguration` |
| Images | approved registries, digests, signed in CI, verified at admission | cosign + Kyverno / policy-controller / Gatekeeper; ValidatingAdmissionPolicy |
| Runtime | detection on every node; audit logs to a SIEM | Falco; API server audit policy |

## Pod Security Standards via Pod Security Admission

| Level | Allows | Typical namespaces |
|---|---|---|
| `privileged` | everything | CNI, CSI node plugins, some node agents (isolated platform namespaces only) |
| `baseline` | blocks known privilege escalations (privileged, host namespaces, hostPath, most capabilities) | legacy apps during migration; ingress/gateway data planes if they need it |
| `restricted` | baseline + non-root, no privilege escalation, drop ALL caps (only `NET_BIND_SERVICE` may be added), seccomp `RuntimeDefault`/`Localhost`, restricted volume types | every application namespace |

Rollout plan for an existing cluster:

1. Label every namespace with `warn` and `audit` at `restricted` - nothing breaks, you get warnings and audit annotations.
2. Preview enforcement without changing anything: `kubectl label --dry-run=server --overwrite ns --all pod-security.kubernetes.io/enforce=baseline` lists the pods that would violate.
3. Fix workloads (usually: non-root user, writable `emptyDir` instead of root-fs writes, drop capabilities).
4. Enforce `baseline` everywhere except platform namespaces, then `restricted` on application namespaces.
5. Pin `enforce-version` and bump it deliberately after each cluster upgrade; keep `warn-version: latest` to see what the next bump would break.

PSA only validates, and `enforce` applies only to **pods** (`warn`/`audit` also check workload templates). A Deployment that violates the policy is accepted (with a warning if `warn` is set) and its ReplicaSet then fails to create pods - look for `FailedCreate` events. PSA cannot mutate; set secure defaults in your chart/template, or with a mutating policy (Kyverno, or `MutatingAdmissionPolicy`, GA v1.36).

## securityContext baseline

| Field | Level | Value | Why |
|---|---|---|---|
| `runAsNonRoot` | pod | `true` | kubelet refuses to start a container whose user is root |
| `runAsUser` / `runAsGroup` | pod | non-zero UID/GID (e.g. 10001) | deterministic file ownership; needed when the image has no numeric `USER` |
| `fsGroup` + `fsGroupChangePolicy: OnRootMismatch` | pod | app GID | writable volumes without a root `chown`; faster mounts for large volumes |
| `seccompProfile.type` | pod | `RuntimeDefault` | blocks dangerous syscalls; required by `restricted` |
| `allowPrivilegeEscalation` | container | `false` | no setuid escalation |
| `capabilities.drop` | container | `["ALL"]` (add back only `NET_BIND_SERVICE` if unavoidable) | minimal kernel privileges |
| `readOnlyRootFilesystem` | container | `true` + `emptyDir` for scratch paths | malware cannot persist or modify binaries |
| `privileged`, host namespaces, `hostPath` | - | never in app namespaces | node takeover paths |
| `hostUsers` | pod | `false` where the node OS and runtime support it | user namespaces: root in the container is unprivileged on the host (GA v1.36; beta, on by default v1.33-v1.35) |
| `appArmorProfile` | pod/container | `RuntimeDefault` on AppArmor nodes | field-based AppArmor is GA since v1.31 |

## Decision tables / trade-offs

### RBAC design

| Principal | Bind to | Scope | Notes |
|---|---|---|---|
| Developers | custom `developer` Role or built-in `edit` | RoleBinding per namespace, subject = OIDC group | `edit` can read Secrets and run pods as any SA in the namespace |
| Read-only / support | built-in `view` | RoleBinding per namespace | excludes Secrets and RBAC objects |
| Namespace owners | built-in `admin` | RoleBinding | can create Roles/RoleBindings inside the namespace |
| CI pushing manifests | dedicated SA + Role, short-lived tokens or OIDC federation | namespace | prefer GitOps (pull) so CI needs no cluster credentials |
| GitOps controller | ClusterRole scoped by Argo CD Projects / Flux tenancy | cluster or per tenant | the most privileged identity: protect its Git repo |
| Platform admins | `cluster-admin` via a break-glass group | cluster | time-bound, audited, MFA |

Dangerous permissions to keep out of everyday roles (from the official RBAC good practices):

| Permission | Why it is dangerous |
|---|---|
| `*` verbs/resources, `cluster-admin`, group `system:masters` | wildcards grant future resources too; `system:masters` bypasses RBAC and cannot be revoked by removing bindings |
| `get`/`list`/`watch` on `secrets` | `list` and `watch` return Secret contents too |
| `create` on pods or any workload | implicitly grants every Secret, ConfigMap and ServiceAccount of the namespace |
| `escalate`, `bind`, `impersonate` | bypass RBAC's escalation protections |
| `get` on `nodes/proxy` | kubelet API: exec into any pod on the node, bypassing audit and admission |
| `create` on `pods/exec`, `pods/attach`, `pods/ephemeralcontainers` | interactive access to running workloads |
| `create` on `serviceaccounts/token` | mint tokens for any SA in scope |
| write on webhook configurations, `ValidatingAdmissionPolicy`, CRDs | disable or subvert admission control cluster-wide |

Audit regularly: `kubectl auth can-i --list --as=<user> --as-group=<group> -n <ns>`, `kubectl auth whoami`, `kubectl get rolebindings,clusterrolebindings -A -o wide`. Extend built-in roles to your CRDs with aggregation labels (snippet below) instead of writing parallel roles. For human authentication, structured authentication configuration (multiple JWT issuers, CEL claim mappings) is GA since v1.34.

### ServiceAccount hygiene

| Practice | How |
|---|---|
| One SA per workload, never `default` | `serviceAccountName: <app>`; `default` SA gets `automountServiceAccountToken: false` |
| No token unless the app calls the API | `automountServiceAccountToken: false` on SA and pod (pod setting wins) |
| Bound, short-lived tokens only | projected tokens (auto-rotated, audience-bound, invalid when the pod is deleted); `kubectl create token <sa> --duration=15m` for humans/CI; never create `kubernetes.io/service-account-token` Secrets |
| External audiences | projected `serviceAccountToken` volume with `audience` + `expirationSeconds` (>= 600) |
| Cloud permissions | workload identity federation per SA; no access keys in Secrets |
| Separate trust levels | different namespaces (the `kubernetes.io/enforce-mountable-secrets` annotation is deprecated since v1.32) |

### Secrets management options

| Approach | Secret in etcd? | Rotation | Pros | Cons | Verdict |
|---|---|---|---|---|---|
| Hand-made Secrets (`kubectl create secret`) | yes | manual | simple | sprawl, no source of truth; base64 is not encryption | labs only |
| Sealed Secrets / SOPS in Git | yes | manual re-encrypt | GitOps-native | key custody, manual rotation | small setups |
| External Secrets Operator (`ExternalSecret`) | yes (synced copy) | `refreshInterval` | central manager (Vault, AWS/GCP/Azure), works with env and volumes | copy lives in etcd: encrypt at rest, restrict RBAC | recommended default |
| Secrets Store CSI Driver (`SecretProviderClass`) | no (unless sync is enabled) | rotation feature | secret never stored in the cluster | pod start depends on the external store; files only | high-sensitivity secrets |
| Vault Agent / Vault Secrets Operator | optional | dynamic, leased | dynamic DB credentials with TTL | operating Vault; Vault is BSL-licensed (OpenBao is the open-source fork) | dynamic credentials |

Rules that apply whichever option you pick:

- **Encrypt at rest:** `EncryptionConfiguration` with **KMS v2** (GA v1.29; KMS v1 deprecated since v1.28 and disabled by default since v1.29). Local providers rank `secretbox` > `aesgcm` (rotate keys every 200,000 writes) > `aescbc` (weak); `identity` means no encryption. On managed clusters enable the provider's envelope encryption (verify current defaults).
- **Prefer files over env vars:** env leaks via child processes, crash dumps, debug endpoints and `/proc/<pid>/environ`; env never updates. Mounted Secrets update in place (not with `subPath`), and Secret volumes are tmpfs on the node.
- **Rotation without downtime:** two valid credentials during the switch (A/B), the app re-reads files (or restart via a checksum/Reloader), short TTLs.
- **RBAC:** nobody gets `list`/`watch` on Secrets by default; app ServiceAccounts rarely need Secret API access because mounts are done by the kubelet.

### Supply chain

| Stage | Control | Tools (examples) |
|---|---|---|
| Source | signed commits, protected branches, reviewed changes | Git hosting settings |
| Build | minimal pinned base, reproducible builds, vulnerability scan, SBOM | Trivy, Grype, Syft, BuildKit attestations (verify current status) |
| Sign | sign image digest + attach SBOM/provenance as attestations | Sigstore cosign (keyless OIDC in CI: Fulcio certificates, Rekor log) |
| Registry | private, immutable tags, scan on push, retention | Harbor, cloud registries |
| Admit | allowed registries, digest required, signature/attestation verified | Kyverno `ImageValidatingPolicy`, Sigstore policy-controller, OPA Gatekeeper (+ Ratify), ValidatingAdmissionPolicy for structural rules |
| Run | detect drift and anomalies | Falco, Tetragon, KubeArmor (verify current status) |

Admission engines compared:

| Engine | Language | Strengths | Watch out |
|---|---|---|---|
| ValidatingAdmissionPolicy (GA v1.30) | CEL, in the API server | no webhook to run or fail; fast | validation only; no image-signature checks; no external data |
| MutatingAdmissionPolicy (GA v1.36; beta and off by default in v1.34-v1.35) | CEL | in-process defaults | too new for many clusters |
| Kyverno | YAML + CEL (`policies.kyverno.io/v1` types, stable since Kyverno 1.18) | validate, mutate, generate, image verification, reports | legacy `ClusterPolicy` is deprecated (Kyverno 1.19) with removal planned for 1.20 (verify current status) |
| OPA Gatekeeper | Rego | very expressive, mature, audit of existing objects | Rego learning curve; signatures need Ratify |
| Sigstore policy-controller | ClusterImagePolicy | focused on signatures/attestations | opt-in per namespace (`policy.sigstore.dev/include: "true"`) |

High-value policies to enforce first: images only from approved registries; no `:latest`; signed images in production; resources and probes present; required labels (`team`, `app.kubernetes.io/name`); no `LoadBalancer`/`NodePort` Services outside platform namespaces; no `hostPath`.

### Multi-tenancy isolation levels

| Level | Mechanisms | Shared | Fits |
|---|---|---|---|
| Soft (namespaces) | namespace + RBAC + PSA + NetworkPolicy + quota | nodes, kernel, control plane, CRDs | teams of one organisation |
| Hardened namespaces | + dedicated node pools (taints/tolerations, node affinity), user namespaces, sandboxed `RuntimeClass` (gVisor, Kata) | control plane, CRDs | sensitive workloads, noisy or semi-trusted tenants |
| Virtual control planes | vcluster or hosted control planes | nodes (optionally) | tenants needing cluster-admin-like autonomy, own CRDs |
| Hard | cluster per tenant/environment | nothing | regulated data, hostile tenants, different compliance scopes |

See [09](09-multi-tenancy-and-cluster-strategy.md) for the cluster strategy side.

## NetworkPolicy and egress control

- Every namespace: default-deny for ingress **and** egress, then allow DNS (UDP+TCP 53 to CoreDNS) - [`yaml/namespace-baseline.yaml`](yaml/namespace-baseline.yaml).
- Every hop: egress rule on the caller **and** ingress rule on the callee, on the **pod** port - [`yaml/networkpolicy-three-tier.yaml`](yaml/networkpolicy-three-tier.yaml).
- NetworkPolicy knows pods, namespaces and CIDRs - not DNS names. FQDN egress (e.g. "only api.stripe.com") needs CNI-specific policy (Cilium `toFQDNs`, Calico DNS policy) or an egress proxy/gateway (verify current status for your CNI).
- Cluster-wide guard rails that namespace owners cannot override are being standardised by SIG Network as `ClusterNetworkPolicy` (successor of AdminNetworkPolicy/BaselineAdminNetworkPolicy; CRD-based, implementation-dependent - verify current status).
- What NetworkPolicy cannot do (official list): anything TLS-related, logging of allowed/denied connections, explicit deny rules, blocking traffic from the pod's own node. Use a mesh or CNI L7 features for identity-based authorization and encryption.
- Test policies like code: a connectivity matrix (allowed and denied pairs) run after every change.

## Runtime security

- **Falco** (CNCF graduated): kernel-event rules such as "shell spawned in a container", "write below /etc", "unexpected outbound connection"; forward alerts to your SIEM/on-call.
- **Audit logging:** API server audit policy that logs Secrets, ConfigMaps and token requests at `Metadata` level only (request/response levels would copy secret values into the audit log) and RBAC, admission-policy and webhook changes at `RequestResponse`; on managed clusters enable control-plane audit logs.
- **Nodes:** minimal, auto-updated node OS; no SSH by default; CIS benchmark checks.
- **Untrusted code** (CI runners, customer plugins): sandboxed `RuntimeClass`, dedicated tainted node pool, user namespaces, no ServiceAccount token, egress-restricted.

## Anti-patterns

| Anti-pattern | Risk | Do instead |
|---|---|---|
| `cluster-admin` for developers or CI | one leaked token = whole cluster | namespaced Roles, GitOps pull |
| Wildcards in Roles | silently grants future resources and subresources | enumerate resources and verbs |
| "Read-only" role with `list secrets` | read-only can read every credential | `view` (no Secrets) |
| Apps using the `default` SA with an auto-mounted token | any RCE gets an API token | own SA, automount off |
| Long-lived SA token Secrets in CI | non-expiring credential outside the cluster | `kubectl create token --duration`, OIDC federation |
| Static cloud access keys in Secrets | key leakage, no rotation | workload identity |
| PSA `privileged` on app namespaces "to make it work" | container escape paths | fix the image: non-root, writable `emptyDir` |
| Secrets in Git (even "private" repos), Helm values, env vars in manifests | credential leakage via history and forks | ESO / CSI driver / SOPS |
| No egress policy | data exfiltration, crypto-mining callbacks | default-deny egress + explicit destinations |
| Unverified images from public registries | typo-squatting, compromised tags | mirror, scan, sign, verify by digest |
| Admission webhooks with `failurePolicy: Ignore` for security policies | outage of the webhook = policies off | `Fail` + HA webhook, or in-process VAP |

## Reference YAML

- Namespace baseline (PSA labels, quota, LimitRange, default SA, default-deny + DNS): [`yaml/namespace-baseline.yaml`](yaml/namespace-baseline.yaml)
- Namespaced developer RBAC: [`yaml/rbac-namespace-developer.yaml`](yaml/rbac-namespace-developer.yaml)
- Three-tier NetworkPolicies: [`yaml/networkpolicy-three-tier.yaml`](yaml/networkpolicy-three-tier.yaml)
- Hardened Deployment: [`yaml/production-deployment-template.yaml`](yaml/production-deployment-template.yaml)

securityContext baseline (fragment of a pod template spec; passes PSA `restricted`):

```yaml
automountServiceAccountToken: false
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  fsGroupChangePolicy: OnRootMismatch
  seccompProfile:
    type: RuntimeDefault
containers:
- name: app
  image: registry.example.com/shop/api:1.4.2
  securityContext:
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: ["ALL"]
  volumeMounts:
  - name: tmp
    mountPath: /tmp
volumes:
- name: tmp
  emptyDir:
    sizeLimit: 64Mi
```

Short-lived, audience-bound token for an external system such as Vault (fragment of a pod spec):

```yaml
volumes:
- name: vault-token
  projected:
    sources:
    - serviceAccountToken:
        path: token
        audience: vault                # rejected by any other audience
        expirationSeconds: 600         # minimum allowed; kubelet rotates it
```

Extend the built-in `edit`/`admin` roles to a CRD by aggregation:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: externalsecrets-editor
  labels:
    rbac.authorization.k8s.io/aggregate-to-edit: "true"
    rbac.authorization.k8s.io/aggregate-to-admin: "true"
rules:
- apiGroups: ["external-secrets.io"]
  resources: ["externalsecrets"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

Encryption at rest with KMS v2 (API server configuration file, passed with `--encryption-provider-config`; managed clusters expose this as a setting):

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - kms:
      apiVersion: v2
      name: cloud-kms
      endpoint: unix:///var/run/kmsplugin/socket.sock
      timeout: 3s
  - identity: {}                       # still reads data written before encryption was enabled
# After enabling, rewrite existing Secrets so they are stored encrypted:
#   kubectl get secrets --all-namespaces -o json | kubectl replace -f -
```

Secret synced from an external manager with External Secrets Operator (requires ESO and a `ClusterSecretStore`; API `external-secrets.io/v1`, checked against the ESO CRD schema in Oct 2026):

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: api-db
  namespace: shop
spec:
  refreshInterval: 1h                  # re-sync (rotation) interval
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secrets-manager
  target:
    name: api-db                       # the Kubernetes Secret ESO creates and owns
    creationPolicy: Owner
  data:
  - secretKey: password
    remoteRef:
      key: prod/shop/api-db
      property: password
```

In-process admission rules with ValidatingAdmissionPolicy (GA v1.30; no webhook needed):

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: approved-images
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  validations:
  - expression: >-
      object.spec.containers.all(c, c.image.startsWith('registry.example.com/')) &&
      (!has(object.spec.initContainers) ||
       object.spec.initContainers.all(c, c.image.startsWith('registry.example.com/')))
    message: "Images must come from registry.example.com."
  - expression: "object.spec.containers.all(c, !c.image.endsWith(':latest'))"
    message: "The :latest tag is not allowed."
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: approved-images
spec:
  policyName: approved-images
  validationActions: ["Deny"]          # start with ["Warn", "Audit"] to measure impact
  matchResources:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: NotIn
        values: ["kube-system"]
```

Signature verification with Kyverno's CEL-based `ImageValidatingPolicy` (requires Kyverno >= 1.18; structure checked against the Kyverno docs and CRD schema in Oct 2026):

```yaml
apiVersion: policies.kyverno.io/v1
kind: ImageValidatingPolicy
metadata:
  name: require-signed-images
spec:
  validationActions: [Deny]
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE", "UPDATE"]
      resources: ["pods"]
  matchImageReferences:
  - expression: "image.registry == 'registry.example.com'"
  attestors:
  - name: ci                           # referenced in CEL as attestors.ci (no hyphens in CEL names)
    cosign:
      keyless:                         # signed in CI with OIDC (no long-lived key)
        identities:
        - issuer: https://token.actions.githubusercontent.com
          subjectRegExp: "^https://github\\.com/example-org/.+/\\.github/workflows/release\\.yml@refs/tags/v.+$"
  validations:
  - expression: >-
      images.containers.map(image, verifyImageSignatures(image, [attestors.ci])).all(e, e > 0)
    message: "Images must be signed by the release workflow."
```

Sign in CI by digest (keyless) with cosign:

```bash
cosign sign --yes registry.example.com/shop/api@sha256:4bf9d34f1c1d5b8e3fa2c9a0e1b7d6c5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9
cosign verify registry.example.com/shop/api@sha256:4bf9d34f1c1d5b8e3fa2c9a0e1b7d6c5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9 \
  --certificate-identity-regexp '^https://github\.com/example-org/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Checklist

Use the official [Application Security Checklist](https://kubernetes.io/docs/concepts/security/application-security-checklist/) as the per-workload review list and the [Security Checklist](https://kubernetes.io/docs/concepts/security/security-checklist/) for the cluster; this list is the architect's summary.

- [ ] Every application namespace: PSA `enforce: restricted` (pinned), `warn`/`audit: restricted` (`latest`).
- [ ] Every pod: non-root, no privilege escalation, drop ALL, read-only root fs, seccomp `RuntimeDefault`.
- [ ] Humans authenticate via OIDC groups; RoleBindings per namespace; no daily `cluster-admin`; break-glass is audited.
- [ ] No wildcards, `escalate`/`bind`/`impersonate`, `nodes/proxy`, Secret `list`/`watch` in everyday roles.
- [ ] One ServiceAccount per workload; token automount off unless needed; no long-lived token Secrets.
- [ ] Cloud access through workload identity; no static keys in Secrets.
- [ ] Default-deny ingress + egress, DNS allowed, explicit allows per hop; egress to the internet restricted.
- [ ] Secrets from an external manager, mounted as files, rotated; etcd encryption at rest with KMS v2.
- [ ] Images scanned, SBOM produced, signed by digest; admission verifies registry, digest and signature.
- [ ] Structural policies (no `:latest`, resources, labels) enforced with VAP/Kyverno/Gatekeeper, tested in CI.
- [ ] API audit logs and runtime detection (Falco or equivalent) flow to a SIEM with on-call routing.

## References

- Security checklist: https://kubernetes.io/docs/concepts/security/security-checklist/
- Application security checklist: https://kubernetes.io/docs/concepts/security/application-security-checklist/
- Pod Security Standards: https://kubernetes.io/docs/concepts/security/pod-security-standards/
- Pod Security Admission: https://kubernetes.io/docs/concepts/security/pod-security-admission/
- Enforce Pod Security Standards with namespace labels: https://kubernetes.io/docs/tasks/configure-pod-container/enforce-standards-namespace-labels/
- Configure a security context: https://kubernetes.io/docs/tasks/configure-pod-container/security-context/
- Linux kernel security constraints (seccomp, AppArmor, SELinux): https://kubernetes.io/docs/concepts/security/linux-kernel-security-constraints/
- Seccomp tutorial: https://kubernetes.io/docs/tutorials/security/seccomp/
- User namespaces: https://kubernetes.io/docs/concepts/workloads/pods/user-namespaces/
- Runtime classes: https://kubernetes.io/docs/concepts/containers/runtime-class/
- RBAC: https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- RBAC good practices: https://kubernetes.io/docs/concepts/security/rbac-good-practices/
- Authentication: https://kubernetes.io/docs/reference/access-authn-authz/authentication/
- Service accounts: https://kubernetes.io/docs/concepts/security/service-accounts/
- Configure service accounts for pods: https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
- Network policies: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Good practices for Secrets: https://kubernetes.io/docs/concepts/security/secrets-good-practices/
- Encrypting confidential data at rest: https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/
- KMS provider: https://kubernetes.io/docs/tasks/administer-cluster/kms-provider/
- ValidatingAdmissionPolicy: https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/
- MutatingAdmissionPolicy: https://kubernetes.io/docs/reference/access-authn-authz/mutating-admission-policy/
- Admission controllers: https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/
- Auditing: https://kubernetes.io/docs/tasks/debug/debug-cluster/audit/
- Multi-tenancy: https://kubernetes.io/docs/concepts/security/multi-tenancy/
- SIG Network policy API (ClusterNetworkPolicy): https://network-policy-api.sigs.k8s.io/
- External Secrets Operator: https://external-secrets.io/latest/
- Secrets Store CSI Driver: https://secrets-store-csi-driver.sigs.k8s.io/
- Vault Secrets Operator: https://developer.hashicorp.com/vault/docs/platform/k8s/vso · OpenBao: https://openbao.org/
- Sigstore cosign (signing containers): https://docs.sigstore.dev/cosign/signing/signing_with_containers/
- Sigstore policy-controller: https://docs.sigstore.dev/policy-controller/overview/
- Kyverno ImageValidatingPolicy: https://kyverno.io/docs/policy-types/image-validating-policy/
- OPA Gatekeeper: https://open-policy-agent.github.io/gatekeeper/website/docs/
- Falco: https://falco.org/docs/
