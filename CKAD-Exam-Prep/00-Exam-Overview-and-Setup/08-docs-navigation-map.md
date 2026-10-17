# Docs Navigation Map — where every copy-paste YAML lives

During the exam the official documentation is your only reference. Learn **where** things are now, so you can find a YAML example in about 20 seconds. Every URL below was checked on 2026-10-17. Practise with only these sites open.

> Search tip: on kubernetes.io type the **kind** name ("NetworkPolicy") or the task phrase ("liveness probe"). Concept pages explain; **Task pages have the best copy-ready YAML**.

## Everyday references
| Need | Page |
|---|---|
| kubectl one-liners | https://kubernetes.io/docs/reference/kubectl/quick-reference/ |
| `kubectl create ...` flags | https://kubernetes.io/docs/reference/kubectl/generated/kubectl_create/ |
| JSONPath syntax | https://kubernetes.io/docs/reference/kubectl/jsonpath/ |
| Labels and selectors | https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/ |
| Namespaces | https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/ |
| Recommended labels | https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/ |

## 1. Application Design and Build
| Topic | Page |
|---|---|
| Pods | https://kubernetes.io/docs/concepts/workloads/pods/ |
| Pod lifecycle, restartPolicy, hooks | https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/ |
| command / args | https://kubernetes.io/docs/tasks/inject-data-application/define-command-argument-container/ |
| Images, imagePullPolicy | https://kubernetes.io/docs/concepts/containers/images/ |
| Deployments | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| StatefulSets | https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/ |
| DaemonSets | https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/ |
| Jobs | https://kubernetes.io/docs/concepts/workloads/controllers/job/ |
| CronJobs | https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/ |
| Init containers | https://kubernetes.io/docs/concepts/workloads/pods/init-containers/ |
| Sidecar containers (native) | https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/ |
| Volumes (emptyDir, hostPath, configMap, secret, projected ...) | https://kubernetes.io/docs/concepts/storage/volumes/ |
| emptyDir walkthrough | https://kubernetes.io/docs/tasks/configure-pod-container/configure-volume-storage/ |
| PersistentVolumes / claims | https://kubernetes.io/docs/concepts/storage/persistent-volumes/ |
| PV + PVC + Pod walkthrough (hostPath) | https://kubernetes.io/docs/tutorials/configuration/configure-persistent-volume-storage/ |
| StorageClasses | https://kubernetes.io/docs/concepts/storage/storage-classes/ |
| Ephemeral volumes | https://kubernetes.io/docs/concepts/storage/ephemeral-volumes/ |

## 2. Application Deployment
| Topic | Page |
|---|---|
| Rolling update, rollback, strategy | https://kubernetes.io/docs/concepts/workloads/controllers/deployment/ |
| Canary pattern (label-based) | https://kubernetes.io/docs/concepts/workloads/management/ |
| Kustomize | https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/ |
| Helm usage | https://helm.sh/docs/intro/using_helm/ |
| Helm command reference | https://helm.sh/docs/helm/helm/ |
| `helm upgrade` / `helm rollback` | https://helm.sh/docs/helm/helm_upgrade/ · https://helm.sh/docs/helm/helm_rollback/ |

## 3. Application Observability and Maintenance
| Topic | Page |
|---|---|
| Probes (liveness/readiness/startup) | https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/ |
| Deprecated API migration guide | https://kubernetes.io/docs/reference/using-api/deprecation-guide/ |
| Deprecation policy | https://kubernetes.io/docs/reference/using-api/deprecation-policy/ |
| kubectl-convert plugin install | https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/ |
| Debug applications | https://kubernetes.io/docs/tasks/debug/debug-application/ |
| Debug pods | https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/ |
| Debug running pods (`kubectl debug`, ephemeral containers) | https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/ |
| Debug Services | https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/ |
| Logging architecture | https://kubernetes.io/docs/concepts/cluster-administration/logging/ |
| Resource metrics / metrics-server | https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/ |

## 4. Application Environment, Configuration and Security
| Topic | Page |
|---|---|
| Custom resources | https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/ |
| CRD walkthrough (copy-ready CRD) | https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/ |
| Operator pattern | https://kubernetes.io/docs/concepts/extend-kubernetes/operator/ |
| Authentication | https://kubernetes.io/docs/reference/access-authn-authz/authentication/ |
| Authorization modes | https://kubernetes.io/docs/reference/access-authn-authz/authorization/ |
| RBAC (Role/Binding YAML) | https://kubernetes.io/docs/reference/access-authn-authz/rbac/ |
| Admission controllers | https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/ |
| Pod Security Admission (namespace labels) | https://kubernetes.io/docs/concepts/security/pod-security-admission/ |
| Pod Security Standards (what restricted requires) | https://kubernetes.io/docs/concepts/security/pod-security-standards/ |
| Resource requests/limits | https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/ |
| Memory limits walkthrough | https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/ |
| QoS classes | https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/ |
| ResourceQuota | https://kubernetes.io/docs/concepts/policy/resource-quotas/ |
| LimitRange | https://kubernetes.io/docs/concepts/policy/limit-range/ |
| ConfigMaps (concept) | https://kubernetes.io/docs/concepts/configuration/configmap/ |
| ConfigMaps in Pods (copy-ready) | https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/ |
| Secrets (concept, types) | https://kubernetes.io/docs/concepts/configuration/secret/ |
| Secrets in Pods (copy-ready) | https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/ |
| Private registry / imagePullSecrets | https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/ |
| ServiceAccounts (concept) | https://kubernetes.io/docs/concepts/security/service-accounts/ |
| ServiceAccounts in Pods (copy-ready) | https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/ |
| ServiceAccount admin (tokens) | https://kubernetes.io/docs/reference/access-authn-authz/service-accounts-admin/ |
| SecurityContext + capabilities | https://kubernetes.io/docs/tasks/configure-pod-container/security-context/ |
| Downward API env vars | https://kubernetes.io/docs/tasks/inject-data-application/environment-variable-expose-pod-information/ |
| Downward API volume | https://kubernetes.io/docs/tasks/inject-data-application/downward-api-volume-expose-pod-information/ |

## 5. Services and Networking
| Topic | Page |
|---|---|
| Services (all types, ports, headless, ExternalName) | https://kubernetes.io/docs/concepts/services-networking/service/ |
| EndpointSlices | https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/ |
| DNS for Services and Pods | https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/ |
| Ingress (rules, pathType, TLS) | https://kubernetes.io/docs/concepts/services-networking/ingress/ |
| Ingress controllers | https://kubernetes.io/docs/concepts/services-networking/ingress-controllers/ |
| NetworkPolicy (default deny examples at the bottom) | https://kubernetes.io/docs/concepts/services-networking/network-policies/ |
| Gateway API | https://kubernetes.io/docs/concepts/services-networking/gateway/ |

## Bonus / cross-cutting
| Topic | Page |
|---|---|
| nodeSelector, affinity | https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/ |
| Taints and tolerations | https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/ |
| Topology spread | https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/ |
| PriorityClass | https://kubernetes.io/docs/concepts/scheduling-eviction/pod-priority-preemption/ |
| HPA | https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/ · walkthrough: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/ |
| PDB | https://kubernetes.io/docs/tasks/run-application/configure-pdb/ · https://kubernetes.io/docs/concepts/workloads/pods/disruptions/ |

## Drill (10 minutes, do it twice)
Close this page. Using only kubernetes.io search, find and copy into your terminal: (1) a NetworkPolicy with a namespaceSelector, (2) a PV + PVC pair, (3) a Pod with a startupProbe, (4) a Role + RoleBinding, (5) an Ingress with TLS, (6) a CronJob, (7) a Pod with a native sidecar. Target: under 30 seconds each.
