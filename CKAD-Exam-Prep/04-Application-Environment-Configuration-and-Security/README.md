# 04 - Application Environment, Configuration and Security (25%)

The **largest** CKAD domain: a quarter of the score. Most tasks are short and mechanical (create a Secret, mount a ConfigMap, bind a Role, set a securityContext), so this is where speed with `kubectl create ... --dry-run=client -o yaml` pays off most. Content targets Kubernetes v1.33+ and is checked against v1.37, the version the exam currently runs (see [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md)).

## Official competencies (CNCF curriculum v1.37, verbatim)

1. Discover and use resources that extend Kubernetes (CRD, Operators)
2. Understand authentication, authorization and admission control
3. Understand requests, limits, quotas
4. Define resource requirements
5. Understand ConfigMaps
6. Create & consume Secrets
7. Understand ServiceAccounts
8. Understand Application Security (SecurityContexts, Capabilities, etc.)

## Competency map

| Competency | File(s) | Exam frequency |
|---|---|---|
| Discover and use resources that extend Kubernetes (CRD, Operators) | [01-crds-and-operators.md](01-crds-and-operators.md) | Medium |
| Understand authentication, authorization and admission control | [02-authentication-authorization-admission.md](02-authentication-authorization-admission.md) | High (RBAC, contexts, PSA) / Low (admission plugins) |
| Understand requests, limits, quotas | [03-requests-limits-and-quotas.md](03-requests-limits-and-quotas.md) | High |
| Define resource requirements | [03-requests-limits-and-quotas.md](03-requests-limits-and-quotas.md) (container requests/limits, sizing, QoS) | High |
| Understand ConfigMaps | [04-configmaps.md](04-configmaps.md), [08-downward-api-and-environment-variables.md](08-downward-api-and-environment-variables.md) | High |
| Create & consume Secrets | [05-secrets.md](05-secrets.md), [08-downward-api-and-environment-variables.md](08-downward-api-and-environment-variables.md) | High |
| Understand ServiceAccounts | [06-serviceaccounts.md](06-serviceaccounts.md) | High |
| Understand Application Security (SecurityContexts, Capabilities, etc.) | [07-security-contexts-and-capabilities.md](07-security-contexts-and-capabilities.md), PSA in [02](02-authentication-authorization-admission.md) | High |

## Must know - cannot skip

- [ ] Create Secrets (`generic --from-literal/--from-file/--from-env-file`, `tls`, `docker-registry`) and decode one into a file (`-o jsonpath='{.data.k}' | base64 -d`), `echo -n` when encoding by hand
- [ ] Create ConfigMaps from literals, files (custom key), directories and env-files; update one with `--dry-run=client -o yaml | kubectl apply -f -`
- [ ] Consume ConfigMaps/Secrets as `env.valueFrom`, `envFrom` (+ `prefix`), whole volume, `items` (key -> path, `mode`/`defaultMode`) and `subPath`; know what updates live (volumes) and what needs `kubectl rollout restart` (env, subPath)
- [ ] `imagePullSecrets` on a Pod and on a ServiceAccount
- [ ] ServiceAccounts: create, `spec.serviceAccountName`, `kubectl set serviceaccount`, automount precedence (Pod wins), `kubectl create token --duration`, long-lived token Secret, mounted files under `/var/run/secrets/kubernetes.io/serviceaccount`
- [ ] Fix "forbidden" app logs: read the username, find the RoleBinding (`-o wide`), point the Deployment at the right SA
- [ ] RBAC: Role/ClusterRole/RoleBinding/ClusterRoleBinding with `kubectl create`, `apiGroups` (`""`, `apps`), subresources (`pods/log`, `pods/exec`, `deployments/scale`), RoleBinding -> ClusterRole for one namespace, `roleRef` is immutable
- [ ] `kubectl auth can-i ... --as=system:serviceaccount:<ns>:<sa>`, `--subresource`, `--list`
- [ ] kubeconfig: `use-context`, `get-contexts -o name`, `current-context`, `set-context --current --namespace`, `view --raw`
- [ ] securityContext placement (pod vs container), `runAsUser/runAsGroup/fsGroup/runAsNonRoot`, `capabilities` add/drop (no `CAP_`), `allowPrivilegeEscalation`, `readOnlyRootFilesystem` + `emptyDir`
- [ ] Pod Security Admission labels (`enforce|warn|audit` x `privileged|baseline|restricted`), restricted requirements, finding rejections in ReplicaSet events
- [ ] Requests vs limits, units (`m`, `Mi`, `Gi`), QoS classes and `.status.qosClass`, OOMKilled vs throttling
- [ ] ResourceQuota (compute + object counts, `kubectl create quota`, `describe quota`) and the "must specify" rule; LimitRange defaults applied at admission
- [ ] CRD discovery: `kubectl get crd`, `api-resources --api-group`, `explain <kind>.spec`, `<plural>.<group>`; create a CR; deleting a CRD deletes its CRs
- [ ] Downward API: env-only fields (`status.podIP`, `spec.nodeName`) vs volume-only (`metadata.labels` map), `resourceFieldRef` + `divisor`

## Nice to know (low frequency, still covered)

- Writing a CRD from scratch (schema, printer columns, status/scale subresources, CEL rules); operator install methods (Helm, manifests, OLM); finalizers and ownerReferences - [01](01-crds-and-operators.md)
- Authentication methods, the CSR API for new users, authorization modes, aggregated ClusterRoles - [02](02-authentication-authorization-admission.md)
- Enabling/disabling admission plugins in `/etc/kubernetes/manifests/kube-apiserver.yaml`; ValidatingAdmissionPolicy (CEL) and webhooks - [02](02-authentication-authorization-admission.md)
- Quota scopes (BestEffort, PriorityClass), storage quotas, in-place Pod resize (stable since v1.35), pod-level resources - [03](03-requests-limits-and-quotas.md)
- Immutable ConfigMaps/Secrets, Kustomize `configMapGenerator` - [04](04-configmaps.md)
- Encryption at rest, external secret managers - [05](05-secrets.md)
- Projected and audience-scoped tokens, calling the API with curl - [06](06-serviceaccounts.md)
- seccomp, AppArmor, SELinux, sysctls, user namespaces (`hostUsers: false`) - [07](07-security-contexts-and-capabilities.md)
- `$(VAR)` composition and env precedence - [08](08-downward-api-and-environment-variables.md)

## Recommended study order (about 7 hours plus practice)

| Step | File | Time |
|---|---|---|
| 1 | [04-configmaps.md](04-configmaps.md) | 45 min |
| 2 | [05-secrets.md](05-secrets.md) | 45 min |
| 3 | [08-downward-api-and-environment-variables.md](08-downward-api-and-environment-variables.md) | 30 min |
| 4 | [06-serviceaccounts.md](06-serviceaccounts.md) | 40 min |
| 5 | [02-authentication-authorization-admission.md](02-authentication-authorization-admission.md) | 90 min |
| 6 | [07-security-contexts-and-capabilities.md](07-security-contexts-and-capabilities.md) | 60 min |
| 7 | [03-requests-limits-and-quotas.md](03-requests-limits-and-quotas.md) | 60 min |
| 8 | [01-crds-and-operators.md](01-crds-and-operators.md) | 40 min |
| 9 | [practice-questions.md](practice-questions.md) - do the 🔥 tasks twice, timed | 3-4 h |
| 10 | [commands.md](commands.md) - skim on exam eve | 20 min |

## All files in this chapter

| File | Content |
|---|---|
| [01-crds-and-operators.md](01-crds-and-operators.md) | CRD anatomy, custom resources, discovery commands, operator pattern, finalizers/ownerReferences |
| [02-authentication-authorization-admission.md](02-authentication-authorization-admission.md) | Request flow, authentication, kubeconfig, authorization modes, RBAC in depth, admission plugins, Pod Security Admission, ValidatingAdmissionPolicy |
| [03-requests-limits-and-quotas.md](03-requests-limits-and-quotas.md) | Requests/limits, units, effective Pod requests, QoS, LimitRange, ResourceQuota, in-place resize, sizing guidance |
| [04-configmaps.md](04-configmaps.md) | Every creation and consumption mode, update propagation, immutability, Kustomize generator |
| [05-secrets.md](05-secrets.md) | Secret types, data vs stringData, decoding, consumption, imagePullSecrets, encryption at rest, security reality |
| [06-serviceaccounts.md](06-serviceaccounts.md) | ServiceAccounts, token types, automount, calling the API with curl, the "forbidden" task |
| [07-security-contexts-and-capabilities.md](07-security-contexts-and-capabilities.md) | Pod vs container fields, users/groups, capabilities, seccomp/AppArmor/SELinux, restricted template, verification |
| [08-downward-api-and-environment-variables.md](08-downward-api-and-environment-variables.md) | Env var forms, Downward API fields (env vs volume), `$(VAR)`, precedence, `kubectl set env` |
| [commands.md](commands.md) | Grouped command reference for the whole chapter |
| [practice-questions.md](practice-questions.md) | 30 exam-style tasks with solutions and verification |

### yaml/ index

| File | What it shows |
|---|---|
| [yaml/crd-crontab.yaml](yaml/crd-crontab.yaml) | Full CRD: names, scope, schema with validation/defaults/CEL, printer columns, status + scale subresources |
| [yaml/cr-crontab-instance.yaml](yaml/cr-crontab-instance.yaml) | Two CronTab custom resources (one relying on a schema default) |
| [yaml/role-pod-reader.yaml](yaml/role-pod-reader.yaml) | Role with core group, subresources (pods/log, pods/exec), resourceNames, apps/deployments/scale |
| [yaml/rolebinding-sa.yaml](yaml/rolebinding-sa.yaml) | RoleBinding with ServiceAccount, User and Group subjects |
| [yaml/clusterrole.yaml](yaml/clusterrole.yaml) | ClusterRole for cluster-scoped resources + nonResourceURLs; aggregation into `view` |
| [yaml/clusterrolebinding.yaml](yaml/clusterrolebinding.yaml) | ClusterRoleBinding to a Group and a ServiceAccount |
| [yaml/rolebinding-to-clusterrole.yaml](yaml/rolebinding-to-clusterrole.yaml) | ClusterRole reused in one namespace via RoleBinding; cross-namespace SA bound to `view` |
| [yaml/serviceaccount.yaml](yaml/serviceaccount.yaml) | ServiceAccounts, automount disabled, imagePullSecrets on an SA |
| [yaml/pod-with-serviceaccount.yaml](yaml/pod-with-serviceaccount.yaml) | Pod and Deployment running as a specific SA |
| [yaml/sa-long-lived-token-secret.yaml](yaml/sa-long-lived-token-secret.yaml) | Manual non-expiring `kubernetes.io/service-account-token` Secret |
| [yaml/pod-sa-token-curl.yaml](yaml/pod-sa-token-curl.yaml) | SA + Role + RoleBinding + Pod calling the API with curl and the mounted token |
| [yaml/resourcequota-compute.yaml](yaml/resourcequota-compute.yaml) | Compute quota plus BestEffort and PriorityClass scoped quotas |
| [yaml/resourcequota-object-count.yaml](yaml/resourcequota-object-count.yaml) | Object-count (`count/<resource>.<group>`) and storage quotas |
| [yaml/limitrange.yaml](yaml/limitrange.yaml) | LimitRange: Container defaults/min/max/ratio, Pod max, PVC bounds |
| [yaml/pod-qos-guaranteed.yaml](yaml/pod-qos-guaranteed.yaml) | Guaranteed QoS Pod |
| [yaml/pod-qos-burstable.yaml](yaml/pod-qos-burstable.yaml) | Burstable QoS Pod |
| [yaml/pod-qos-besteffort.yaml](yaml/pod-qos-besteffort.yaml) | BestEffort QoS Pod |
| [yaml/configmap.yaml](yaml/configmap.yaml) | ConfigMap with env-style and file-style keys, binaryData; immutable ConfigMap |
| [yaml/pod-configmap-env.yaml](yaml/pod-configmap-env.yaml) | `configMapKeyRef` env vars, renamed key, optional reference |
| [yaml/pod-configmap-envfrom.yaml](yaml/pod-configmap-envfrom.yaml) | `envFrom` with and without prefix; `env` overriding `envFrom` |
| [yaml/pod-configmap-volume.yaml](yaml/pod-configmap-volume.yaml) | Whole-map volume, `items` with modes, single file via `subPath` |
| [yaml/secret-opaque.yaml](yaml/secret-opaque.yaml) | Opaque Secret with base64 `data`; immutable Secret |
| [yaml/secret-stringdata.yaml](yaml/secret-stringdata.yaml) | `stringData`, file-style key, basic-auth and ssh-auth types |
| [yaml/pod-secret-env.yaml](yaml/pod-secret-env.yaml) | `secretKeyRef` env vars and `envFrom` with prefix |
| [yaml/pod-secret-volume.yaml](yaml/pod-secret-volume.yaml) | Secret volume with `items` and `defaultMode: 0400`; whole Secret as files |
| [yaml/pod-projected-volume.yaml](yaml/pod-projected-volume.yaml) | Projected volume: Secret + ConfigMap + Downward API + audience-scoped SA token |
| [yaml/pod-imagepullsecrets.yaml](yaml/pod-imagepullsecrets.yaml) | dockerconfigjson Secret (placeholder), Pod `imagePullSecrets`, SA `imagePullSecrets` |
| [yaml/secret-tls-example.yaml](yaml/secret-tls-example.yaml) | Structure of a `kubernetes.io/tls` Secret (placeholder data clearly marked) |
| [yaml/pod-securitycontext.yaml](yaml/pod-securitycontext.yaml) | runAsUser/runAsGroup/fsGroup/supplementalGroups, container-level override |
| [yaml/pod-capabilities.yaml](yaml/pod-capabilities.yaml) | Default capabilities vs drop ALL vs drop ALL + NET_ADMIN, with verification |
| [yaml/pod-readonly-rootfs.yaml](yaml/pod-readonly-rootfs.yaml) | nginx with `readOnlyRootFilesystem` and emptyDir write paths |
| [yaml/pod-restricted-compliant.yaml](yaml/pod-restricted-compliant.yaml) | Pod passing the `restricted` Pod Security Standard |
| [yaml/namespace-pod-security-labels.yaml](yaml/namespace-pod-security-labels.yaml) | Namespaces with PSA enforce/warn/audit labels and version pins |
| [yaml/broken/deploy-violates-restricted.yaml](yaml/broken/deploy-violates-restricted.yaml) | Intentionally broken Deployment rejected by PSA (practice fixing it) |
| [yaml/validating-admission-policy.yaml](yaml/validating-admission-policy.yaml) | ValidatingAdmissionPolicy + Binding with CEL rules |
| [yaml/pod-downward-api-env.yaml](yaml/pod-downward-api-env.yaml) | Every env-capable `fieldRef` plus `resourceFieldRef` with divisors |
| [yaml/pod-downward-api-volume.yaml](yaml/pod-downward-api-volume.yaml) | downwardAPI volume: labels/annotations maps, single fields, resources |
| [yaml/pod-env-dependent-vars.yaml](yaml/pod-env-dependent-vars.yaml) | `$(VAR)` composition, `$$` escape, order dependence, expansion in args |
| [yaml/kubeconfig-example.yaml](yaml/kubeconfig-example.yaml) | kubeconfig structure: clusters, users (cert, token, exec), contexts (placeholders) |

## Related chapters

- Exam format, terminal setup, kubectl cheatsheet: [../00-Exam-Overview-and-Setup/README.md](../00-Exam-Overview-and-Setup/README.md)
- Kustomize generators and Helm (operator installs): [../02-Application-Deployment/README.md](../02-Application-Deployment/README.md)
- JSONPath, custom-columns, labels/selectors: [../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md](../06-Cross-Cutting-Skills-and-Bonus-Topics/README.md)
- Production design beyond the exam: [../08-Architect-Notes/README.md](../08-Architect-Notes/README.md)
- Kit start page and final checklist: [../README.md](../README.md), [../MUST-KNOW-CHECKLIST.md](../MUST-KNOW-CHECKLIST.md)
